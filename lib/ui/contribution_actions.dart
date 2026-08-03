import 'package:flutter/material.dart';

import '../config.dart';
import '../data/parking_spot.dart';
import '../services/contribution_service.dart';
import '../services/location_service.dart';

/// Käyttäjälle näytettävä lopputulos.
///
/// Jonoon jääminen ei ole virheilmoitus. Sovellusta käytetään liikkeellä, ja
/// pysäköintihalli ilman kenttää on normaali olotila — käyttäjän tekemä työ ei
/// mene hukkaan, ja se on kerrottava niin.
String submissionMessage(SubmissionOutcome outcome) => switch (outcome) {
  SubmissionOutcome.sent => 'Kiitos! Ilmoituksesi on kirjattu.',
  SubmissionOutcome.duplicate => 'Olit jo ilmoittanut tästä paikasta.',
  SubmissionOutcome.queued =>
    'Ei verkkoyhteyttä. Ilmoitus lähtee, kun yhteys palaa.',
  SubmissionOutcome.tooMany =>
    'Olet lähettänyt paljon ilmoituksia tänään. Yritä huomenna uudelleen.',
  SubmissionOutcome.rejected => 'Ilmoitusta ei voitu lähettää.',
  SubmissionOutcome.unavailable =>
    'Ilmoitusten lähetys ei ole käytössä tässä versiossa.',
};

/// Hae sijainti lähetystä varten, tai kerro miksi ei onnistu.
///
/// Palauttaa `null` ja näyttää syyn, jos lupaa ei ole tai mittaus on liian
/// epätarkka. Huono mittaus hylätään jo tässä eikä vasta palvelimella, koska
/// käyttäjä voi silloin siirtyä ulos katveesta ja yrittää heti uudelleen —
/// hiljainen hylkäys viikkoja myöhemmin ei anna sitä mahdollisuutta.
Future<PositionFix?> resolveFix(
  BuildContext context,
  LocationService location,
) async {
  final messenger = ScaffoldMessenger.of(context);

  final denial = await location.ensureAvailable();
  if (denial != null) {
    messenger.showSnackBar(SnackBar(content: Text(_denialMessage(denial))));
    return null;
  }

  final PositionFix fix;
  try {
    fix = await location.currentFix();
  } catch (error) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Sijaintia ei saatu. Yritä hetken päästä.')),
    );
    return null;
  }

  final accuracy = fix.accuracyM;
  if (accuracy != null && accuracy > Config.maxSubmitAccuracyM) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Sijainti on epätarkka (±${accuracy.round()} m). Siirry taivasalle '
          'ja yritä uudelleen.',
        ),
      ),
    );
    return null;
  }
  return fix;
}

String _denialMessage(LocationDenial denial) => switch (denial) {
  LocationDenial.serviceDisabled =>
    'Ilmoittaminen vaatii sijainnin. Kytke sijaintipalvelut päälle.',
  LocationDenial.permissionDenied => 'Ilmoittaminen vaatii sijaintiluvan.',
  LocationDenial.permissionDeniedForever =>
    'Sijaintilupa on estetty. Salli sijainti laitteen asetuksista.',
};

/// Vahvistuspainikkeet kohteen tiedoissa.
///
/// Vastapari on tarkoituksellinen: pelkkä "vahvista"-nappi kasvattaisi
/// aineistoa mutta ei koskaan siivoaisi sitä, ja poistunut invapaikka jäisi
/// kartalle ikuisesti.
class ContributionActions extends StatefulWidget {
  const ContributionActions({
    super.key,
    required this.spot,
    required this.contributions,
    required this.location,
  });

  final ParkingSpot spot;
  final ContributionService contributions;
  final LocationService location;

  @override
  State<ContributionActions> createState() => _ContributionActionsState();
}

class _ContributionActionsState extends State<ContributionActions> {
  bool _busy = false;
  late bool _done = widget.contributions.hasActedOn(widget.spot.uid);

  Future<void> _send(bool present) async {
    setState(() => _busy = true);
    try {
      final fix = await resolveFix(context, widget.location);
      if (fix == null || !mounted) return;

      final outcome = await widget.contributions.submit(
        Submission(
          kind: present ? SubmissionKind.present : SubmissionKind.missing,
          lat: fix.position.latitude,
          lon: fix.position.longitude,
          accuracyM: fix.accuracyM,
          targetUid: widget.spot.uid,
        ),
      );
      if (!mounted) return;

      setState(
        () => _done =
            outcome != SubmissionOutcome.rejected &&
            outcome != SubmissionOutcome.unavailable,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(submissionMessage(outcome))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_done) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Kiitos — ilmoituksesi tästä paikasta on kirjattu.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Oletko paikan päällä?', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _send(true),
                  icon: const Icon(Icons.check),
                  label: const Text('Paikka on'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _send(false),
                  icon: const Icon(Icons.close),
                  label: const Text('Ei löydy'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
