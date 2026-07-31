import 'package:flutter/material.dart';

import '../config.dart';
import '../data/spot_data_source.dart';
import '../services/data_updater.dart';
import '../services/map_key_store.dart';
import '../services/navigation_launcher.dart';
import 'licenses_screen.dart';

/// Asetukset: karttatiilien API-avain ja aineiston päivitys.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.store,
    this.dataSource,
    this.updater,
  });

  final MapKeyStore store;

  /// Null testeissä ja silloin kun aineistoa ei voi päivittää.
  final SpotDataSource? dataSource;
  final DataUpdater? updater;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.store.key);

  bool _checkingKey = false;
  MapKeyCheck? _keyResult;

  bool _updating = false;
  String? _updateMessage;
  Map<String, String> _metadata = const {};

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadMetadata() async {
    final source = widget.dataSource;
    if (source == null) return;
    final meta = await source.metadata();
    if (mounted) setState(() => _metadata = meta);
  }

  Future<void> _saveAndVerifyKey() async {
    setState(() {
      _checkingKey = true;
      _keyResult = null;
    });

    final value = _controller.text.trim();
    final check = await MapKeyStore.verify(value);

    // Verkkovirhe ei tarkoita väärää avainta, joten avain tallennetaan
    // muutenkin kuin onnistuneella tarkistuksella.
    if (check.isOk || check.status == MapKeyStatus.networkError) {
      await widget.store.save(value);
    }

    if (!mounted) return;
    setState(() {
      _checkingKey = false;
      _keyResult = check;
    });
  }

  Future<void> _updateData() async {
    final source = widget.dataSource;
    final updater = widget.updater;
    if (source == null || updater == null) return;

    setState(() {
      _updating = true;
      _updateMessage = null;
    });

    final result = await updater.update(source);
    if (!mounted) return;

    final message = switch (result.status) {
      UpdateStatus.updated =>
        'Aineisto päivitetty: ${result.count} kohdetta (${_formatDate(result.version)}).',
      UpdateStatus.upToDate => 'Aineisto on jo ajan tasalla.',
      UpdateStatus.unavailable =>
        result.message ?? 'Päivitystä ei voitu hakea juuri nyt.',
      UpdateStatus.rejected =>
        '${result.message ?? 'Päivitys hylättiin.'} Nykyinen aineisto jäi voimaan.',
    };

    setState(() {
      _updating = false;
      _updateMessage = message;
    });
    await _loadMetadata();
  }

  static String _formatDate(String? isoTimestamp) {
    if (isoTimestamp == null || isoTimestamp.length < 10) return 'tuntematon';
    final date = isoTimestamp.substring(0, 10).split('-');
    return '${date[2]}.${date[1]}.${date[0]}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Asetukset')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Karttatiilien API-avain', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Taustakartta ja osoitehaku tulevat Maanmittauslaitokselta ja '
            'vaativat API-avaimen. Avain on ilmainen: se luodaan MML:n '
            'OmaTili-palvelussa eikä vaadi laskutustiliä tai luottokorttia. '
            'Avain tallennetaan vain tälle laitteelle.',
            style: theme.textTheme.bodyMedium,
          ),
          TextButton.icon(
            onPressed: () =>
                NavigationLauncher.openUrl(Config.mmlKeyInstructionsUrl),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Ohje avaimen luomiseen'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'API-avain',
              hintText: 'Liitä avain tähän',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _saveAndVerifyKey(),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _checkingKey ? null : _saveAndVerifyKey,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: _checkingKey
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Tallenna ja testaa'),
          ),
          if (_keyResult != null) ...[
            const SizedBox(height: 12),
            _Notice(
              text: _keyResult!.message,
              isError: !_keyResult!.isOk,
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Ilman avainta invapaikat näkyvät kartalla ja navigointi toimii, '
            'mutta taustakartta jää tyhjäksi ja osoitehaku ei ole käytössä.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),

          const Divider(height: 40),

          Text('Invapaikka-aineisto', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_metadata.isNotEmpty)
            Text(
              '${_metadata['count'] ?? '?'} kohdetta · '
              'päivitetty ${_formatDate(_metadata['generated_at'])}',
              style: theme.textTheme.bodyMedium,
            ),
          const SizedBox(height: 8),
          Text(
            'Aineisto koostetaan avoimista rajapinnoista kerran viikossa. '
            'Päivitys ladataan verkosta, joten sovellusta ei tarvitse päivittää '
            'kaupasta. Sovellus toimii ladatun aineiston varassa myös ilman '
            'verkkoyhteyttä.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (widget.dataSource != null && widget.updater != null)
            OutlinedButton.icon(
              onPressed: _updating ? null : _updateData,
              icon: _updating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_updating ? 'Tarkistetaan…' : 'Tarkista päivitykset'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          if (_updateMessage != null) ...[
            const SizedBox(height: 12),
            _Notice(text: _updateMessage!, isError: false),
          ],

          const Divider(height: 40),

          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.copyright_outlined),
            title: const Text('Lisenssit ja lähteet'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LicensesScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isError ? Icons.warning_amber : Icons.check_circle_outline),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
