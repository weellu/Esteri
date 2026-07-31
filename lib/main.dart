import 'package:flutter/material.dart';

import 'data/spot_database.dart';
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
            database: services.database,
            keyStore: services.keyStore,
          );
        },
      ),
    );
  }
}

class AppServices {
  AppServices(this.database, this.keyStore);

  final SpotDatabase database;
  final MapKeyStore keyStore;

  static Future<AppServices> create() async {
    // Tietokannan asennus ja avaimen lataus ovat riippumattomia, joten
    // ne tehdään rinnakkain.
    final database = SpotDatabase.open();
    final keyStore = MapKeyStore.load();
    return AppServices(await database, await keyStore);
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
