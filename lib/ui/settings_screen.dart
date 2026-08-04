import 'package:flutter/material.dart';

import '../data/spot_data_source.dart';
import '../services/data_updater.dart';
import 'licenses_screen.dart';

/// Asetukset: aineiston päivitys ja lisenssit.
///
/// Karttatiilien API-avainta ei kysytä käyttäjältä. Avain on taustapalvelussa,
/// eikä sitä ole olemassa asiakaspäässä lainkaan.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.dataSource,
    this.updater,
  });

  /// Null testeissä ja silloin kun aineistoa ei voi päivittää.
  final SpotDataSource? dataSource;
  final DataUpdater? updater;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _updating = false;
  String? _updateMessage;
  Map<String, String> _metadata = const {};

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    final source = widget.dataSource;
    if (source == null) return;
    final meta = await source.metadata();
    if (mounted) setState(() => _metadata = meta);
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
