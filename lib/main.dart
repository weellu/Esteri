import 'dart:async';

import 'package:flutter/material.dart';

import 'data/spot_data_source.dart';
import 'services/data_updater.dart';
import 'services/map_key_store.dart';
import 'ui/map_screen.dart';
import 'ui/spot_marker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LEParkkiApp());
}

class LEParkkiApp extends StatefulWidget {
  const LEParkkiApp({super.key});

  @override
  State<LEParkkiApp> createState() => _LEParkkiAppState();
}

class _LEParkkiAppState extends State<LEParkkiApp> {
  late final Future<AppServices> _services = AppServices.create();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LEParkki',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: SpotVisuals.exact),
        useMaterial3: true,
      ),
      home: FutureBuilder<AppServices>(
        future: _services,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _StartupError(error: snapshot.error!);
          }
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final services = snapshot.data!;
          return MapScreen(
            database: services.dataSource,
            keyStore: services.keyStore,
            dataSource: services.dataSource,
            updater: services.updater,
          );
        },
      ),
    );
  }
}

class AppServices {
  AppServices(this.dataSource, this.keyStore, this.updater);

  final SpotDataSource dataSource;
  final MapKeyStore keyStore;
  final DataUpdater updater;

  static Future<AppServices> create() async {
    // Aineiston asennus ja avaimen lataus ovat riippumattomia, joten
    // ne tehdään rinnakkain.
    final dataSource = SpotDataSource.open();
    final keyStore = MapKeyStore.load();
    final services = AppServices(await dataSource, await keyStore, DataUpdater());

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
