import 'package:flutter/material.dart';

import '../config.dart';
import '../services/contribution_service.dart';
import '../services/location_service.dart';
import 'contribution_actions.dart';

/// Uuden invapaikan ilmoittaminen.
///
/// Sijainti otetaan laitteen paikannuksesta eikä kartalta raahaamalla:
/// ilmoituksen arvo on siinä, että joku on oikeasti ollut paikalla. Kartalta
/// osoitettu piste näyttäisi samalta mutta ei kertoisi maastosta mitään, eikä
/// sitä voisi erottaa arvauksesta jälkikäteen.
///
/// Ohjeteksti puhuu ruudussa olemisesta, ei siellä seisomisesta. Tämän
/// sovelluksen käyttäjistä osa ei seiso, ja ilmoitus on tarkoituskin tehdä
/// autosta käsin — silloin puhelin on ruudussa, mikä on juuri se mitä
/// sijainnilta halutaan.
///
/// Ilmoitus julkaistaan vahvistamattomana. Se kerrotaan tässä suoraan, jotta
/// käyttäjä tietää mitä lähettää — ja miksi kolmen eri ihmisen ilmoitus on
/// arvokkaampi kuin yhden.
class AddSpotSheet extends StatefulWidget {
  const AddSpotSheet({
    super.key,
    required this.contributions,
    required this.location,
  });

  final ContributionService contributions;
  final LocationService location;

  static Future<void> show(
    BuildContext context, {
    required ContributionService contributions,
    required LocationService location,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => Padding(
        // Näppäimistö ei saa peittää saatekenttää.
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: AddSpotSheet(contributions: contributions, location: location),
      ),
    );
  }

  @override
  State<AddSpotSheet> createState() => _AddSpotSheetState();
}

class _AddSpotSheetState extends State<AddSpotSheet> {
  final TextEditingController _note = TextEditingController();

  PositionFix? _fix;
  bool _locating = true;
  bool _sending = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _problem = null;
    });

    final denial = await widget.location.ensureAvailable();
    if (!mounted) return;
    if (denial != null) {
      setState(() {
        _locating = false;
        _problem = 'Ilmoittaminen vaatii sijainnin.';
      });
      return;
    }

    try {
      final fix = await widget.location.currentFix();
      if (!mounted) return;
      final accuracy = fix.accuracyM;
      setState(() {
        _fix = fix;
        _locating = false;
        _problem = accuracy != null && accuracy > Config.maxSubmitAccuracyM
            // Kerrotaan mistä tarkkuus paranee, ei käsketä liikkumaan:
            // katoksen alla oleva ei välttämättä pääse sieltä pois helposti.
            ? 'Sijainti on epätarkka (±${accuracy.round()} m). Tarkkuus '
                  'paranee yleensä katoksen ja parkkihallin ulkopuolella.'
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _problem = 'Sijaintia ei saatu.';
      });
    }
  }

  Future<void> _submit() async {
    final fix = _fix;
    if (fix == null) return;

    setState(() => _sending = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final outcome = await widget.contributions.submit(
      Submission(
        kind: SubmissionKind.newSpot,
        lat: fix.position.latitude,
        lon: fix.position.longitude,
        accuracyM: fix.accuracyM,
        note: _note.text.trim(),
      ),
    );

    if (!mounted) return;
    setState(() => _sending = false);
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(submissionMessage(outcome))));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fix = _fix;
    final canSend = fix != null && _problem == null && !_sending;

    return SafeArea(
      // Sisältö vierii, koska sen korkeus ei ole ennustettava: sijainnin tila
      // vaihtelee latauksesta virheeseen, saatteen kenttä kasvaa, ja
      // näppäimistö vie puolet ruudusta. Ilman vieritystä lomake ylivuotaa
      // pienellä näytöllä eikä lähetyspainikkeeseen yletä.
      // Näppäimistön vaatiman tilan hoitaa jo [show], joten sitä ei lisätä
      // tähän toiseen kertaan.
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ilmoita invapaikka', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(
                'Tee ilmoitus ruudusta käsin — vaikka autosta. Sijainti otetaan '
                'siitä, missä puhelin juuri nyt on, joten muualta lähetetty '
                'ilmoitus merkitsee paikan väärään kohtaan.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),

              if (_locating)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Haetaan sijaintia…'),
                    ],
                  ),
                )
              else
                _LocationStatus(fix: fix, problem: _problem, onRetry: _locate),

              const SizedBox(height: 16),
              TextField(
                controller: _note,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Missä tarkalleen? (valinnainen)',
                  hintText: 'esim. P-talon 2. kerros, hissin vieressä',
                  border: OutlineInputBorder(),
                ),
              ),
              Text(
                'Saate näkyy vain ylläpidolle eikä päädy karttaan.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: canSend ? _submit : null,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: const Text('Lähetä ilmoitus'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Ilmoitus näkyy kartalla vahvistamattomana, kunnes useampi '
                'käyttäjä on käynyt vahvistamassa sen paikan päällä.\n\n'
                // Lisenssiehto on kerrottava ennen lähetystä, ei sen jälkeen:
                // avoimeen aineistoon luovutettua kohdetta ei saa enää pois,
                // koska se on siihen mennessä levinnyt eteenpäin.
                'Lähettämällä luovutat sijainnin avoimeen aineistoon '
                '(ODbL 1.0). Nimeäsi tai laitettasi ei tallenneta.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationStatus extends StatelessWidget {
  const _LocationStatus({
    required this.fix,
    required this.problem,
    required this.onRetry,
  });

  final PositionFix? fix;
  final String? problem;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = problem != null;
    final accuracy = fix?.accuracyM;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: failed
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(failed ? Icons.gps_off : Icons.gps_fixed, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  problem ??
                      'Sijainti löytyi'
                          '${accuracy == null ? '' : ' (±${accuracy.round()} m)'}.',
                  style: theme.textTheme.bodyMedium,
                ),
                if (failed)
                  TextButton(
                    onPressed: onRetry,
                    child: const Text('Hae uudelleen'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
