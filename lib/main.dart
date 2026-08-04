import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http_cache_core/http_cache_core.dart';

import 'config.dart';
import 'data/spot_data_source.dart';
import 'services/contribution_service.dart';
import 'services/data_updater.dart';
import 'services/tile_cache.dart';
import 'ui/map_screen.dart';
import 'ui/spot_marker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EsteriApp());
}

class EsteriApp extends StatefulWidget {
  const EsteriApp({super.key});

  @override
  State<EsteriApp> createState() => _EsteriAppState();
}

class _EsteriAppState extends State<EsteriApp> {
  late final Future<AppServices> _services = AppServices.create();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Esteri',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: SpotVisuals.exact),
        useMaterial3: true,
      ),
      // Taustapalvelun osoite on käännösaikainen, joten sen puuttuminen on
      // rakennusvirhe eikä käyttötilanne. Aiemmin siitä seurasi vain
      // ilmoitustoimintojen katoaminen, ja sellainen käännös ehti julkaisuun
      // asti kenenkään huomaamatta (1.0.1+3). Nyt myös taustakartta ja haku
      // kulkevat Workerin kautta, joten hiljainen rappeutuminen ei enää ole
      // vaihtoehto: sovellus pysähtyy heti näkyvään virheeseen.
      home: Config.isConfigured
          ? FutureBuilder<AppServices>(
              future: _services,
              builder: _buildServices,
            )
          : const _MissingConfiguration(),
    );
  }

  Widget _buildServices(
    BuildContext context,
    AsyncSnapshot<AppServices> snapshot,
  ) {
    if (snapshot.hasError) {
      return _StartupError(error: snapshot.error!);
    }
    if (!snapshot.hasData) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final services = snapshot.data!;
    return MapScreen(
      database: services.dataSource,
      dataSource: services.dataSource,
      updater: services.updater,
      contributions: services.contributions,
      tileCache: services.tileCache,
    );
  }
}

class AppServices {
  AppServices(
    this.dataSource,
    this.updater,
    this.contributions,
    this.tileCache,
  );

  final SpotDataSource dataSource;
  final DataUpdater updater;

  /// Null, kun taustapalvelua ei ole määritetty tähän käännökseen. Silloin
  /// ilmoitustoiminnot jäävät pois käyttöliittymästä kokonaan.
  final ContributionService? contributions;

  /// Null, jos välimuistihakemistoa ei saatu auki. Kartta toimii silti.
  final CacheStore? tileCache;

  static Future<AppServices> create() async {
    // Aineiston asennus ja välimuistin avaus ovat riippumattomia, joten
    // ne tehdään rinnakkain.
    final dataSource = SpotDataSource.open();
    final tileCache = TileCache.open();
    final contributions = Config.contributionsEnabled
        ? ContributionService.load()
        : null;
    final services = AppServices(
      await dataSource,
      DataUpdater(),
      await contributions,
      await tileCache,
    );

    // Päivitystä ei odoteta: kartta avautuu heti mukana tulleella tai
    // aiemmin ladatulla aineistolla, ja tuoreempi vaihtuu tilalle taustalla
    // jos sellainen löytyy. Epäonnistunut päivitys ei näy käyttäjälle —
    // vanha aineisto jää voimaan ja tilanteen voi tarkistaa asetuksista.
    unawaited(services._updateInBackground());
    return services;
  }

  Future<void> _updateInBackground() async {
    final result = await updater.update(dataSource);
    if (result.status != UpdateStatus.updated &&
        result.status != UpdateStatus.upToDate) {
      debugPrint('Aineiston taustapäivitys: ${result.message}');
    }
  }
}

/// Näkyviin, kun sovellus on käännetty ilman taustapalvelun osoitetta.
///
/// Tämä ei ole käyttäjälle tarkoitettu virhe vaan rakentajalle: tällaista
/// pakettia ei pidä päästää kauppaan. Teksti on silti suomeksi ja siisti,
/// koska jos se kaikesta huolimatta päätyy jonkun käsiin, arvoituksellinen
/// tyhjä kartta on huonompi kuin selvä ilmoitus.
class _MissingConfiguration extends StatelessWidget {
  const _MissingConfiguration();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.build_outlined, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('Sovellusta ei ole käännetty loppuun',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(
              'Taustapalvelun osoite puuttuu, joten taustakartta, osoitehaku '
              'eivätkä ilmoitustoiminnot ole käytettävissä. Käännä sovellus '
              'ESTERI_API-määrittelyn kanssa:',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            SelectableText(
              '--dart-define=ESTERI_API=https://esteri-api.weellu.workers.dev',
              style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Invapaikka-aineistoa ei voitu avata.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('$error', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
