import 'package:flutter/material.dart';

import '../services/navigation_launcher.dart';

/// Aineistojen lisenssit ja attribuutiot.
///
/// Nämä eivät ole kohteliaisuutta vaan lisenssiehtoja: OSM edellyttää
/// ODbL-maininnan ja tekijöiden krediitin, CC BY 4.0 edellyttää lähteen
/// nimeämisen.
class LicensesScreen extends StatelessWidget {
  const LicensesScreen({super.key});

  static const _entries = <_LicenseEntry>[
    _LicenseEntry(
      title: 'OpenStreetMap',
      credit: '© OpenStreetMap-tekijät',
      license: 'Open Database License (ODbL) 1.0',
      url: 'https://www.openstreetmap.org/copyright',
      note: 'Suurin osa sovelluksen invapaikoista.',
    ),
    _LicenseEntry(
      title: 'Digiroad — liikennemerkit',
      credit: '© Väylävirasto',
      license: 'Creative Commons Nimeä 4.0 (CC BY 4.0)',
      url: 'https://vayla.fi/vaylista/aineistot/digiroad',
      note: 'Invapysäköinnin liikennemerkit (lisäkilpi H12.7).',
    ),
    _LicenseEntry(
      title: 'Tampereen kaupunki',
      credit: '© Tampereen kaupunki',
      license: 'Creative Commons Nimeä 4.0 (CC BY 4.0)',
      url: 'https://data.tampere.fi',
      note: 'Invapysäköintialueet paikkamäärineen ja rajoitusaikoineen.',
    ),
    _LicenseEntry(
      title: 'Turun kaupunki',
      credit: '© Turun kaupunki',
      license: 'Creative Commons Nimeä 4.0 (CC BY 4.0)',
      url: 'https://www.avoindata.fi/data/fi/dataset/turun-kaupungin-liikennemerkit',
      note: 'Invapaikkojen liikennemerkit.',
    ),
    _LicenseEntry(
      title: 'Helsingin kaupunki',
      credit: '© Helsingin kaupunki',
      license: 'Creative Commons Nimeä 4.0 (CC BY 4.0)',
      url: 'https://hri.fi',
      note: 'Kantakaupungin invapysäköintipaikat.',
    ),
    _LicenseEntry(
      title: 'Maanmittauslaitos',
      credit: '© Maanmittauslaitos',
      license: 'Maanmittauslaitoksen avoimen datan lisenssi',
      url: 'https://www.maanmittauslaitos.fi/avoindata-lisenssi-cc40',
      note: 'Taustakartta ja osoitehaku.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Lisenssit ja lähteet')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Sovelluksen invapaikat on koostettu useasta avoimesta aineistosta. '
            'Koska mukana on OpenStreetMap-dataa, yhdistetty aineisto on '
            'johdettu tietokanta ja jaetaan ODbL-lisenssillä.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          for (final entry in _entries) ...[
            _LicenseCard(entry: entry),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          Text(
            'Aineistoja ei ole varmistettu maastossa. Noudata aina paikan päällä '
            'olevia liikennemerkkejä.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _LicenseEntry {
  const _LicenseEntry({
    required this.title,
    required this.credit,
    required this.license,
    required this.url,
    required this.note,
  });

  final String title;
  final String credit;
  final String license;
  final String url;
  final String note;
}

class _LicenseCard extends StatelessWidget {
  const _LicenseCard({required this.entry});

  final _LicenseEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(entry.credit, style: theme.textTheme.bodyMedium),
            Text(
              entry.license,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(entry.note, style: theme.textTheme.bodySmall),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => NavigationLauncher.openUrl(entry.url),
                child: const Text('Lisätietoja'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
