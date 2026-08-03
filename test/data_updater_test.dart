import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:esteri/config.dart';
import 'package:esteri/services/data_updater.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const installed = '2026-07-01T00:00:00+00:00';
const newer = '2026-07-31T00:00:00+00:00';
const older = '2026-06-01T00:00:00+00:00';

Map<String, Object?> manifest({
  String version = newer,
  int schema = 1,
  int count = 2787,
}) =>
    {
      'generated_at': version,
      'schema_version': schema,
      'count': count,
    };

/// Rakenna aito SQLite-tiedosto, joka vastaa pipelinen tuottamaa rakennetta.
Future<File> buildDatabase(
  Directory dir, {
  required int rows,
  String schemaVersion = '1',
  String name = 'test.sqlite',
}) async {
  final path = '${dir.path}/$name';
  final db = await databaseFactoryFfi.openDatabase(path);
  await db.execute('CREATE TABLE spots (id INTEGER PRIMARY KEY, uid TEXT)');
  await db.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)');
  final batch = db.batch();
  for (var i = 1; i <= rows; i++) {
    batch.insert('spots', {'id': i, 'uid': 'osm:$i'});
  }
  batch.insert('meta', {'key': 'schema_version', 'value': schemaVersion});
  batch.insert('meta', {'key': 'count', 'value': '$rows'});
  await batch.commit(noResult: true);
  await db.close();
  return File(path);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('evaluateManifest — milloin toimiva aineisto saa korvautua', () {
    test('uudempi kelvollinen aineisto ladataan', () {
      final result = evaluateManifest(manifest(), installed);
      expect(result.shouldDownload, isTrue);
      expect(result.version, newer);
      expect(result.count, 2787);
    });

    test('sama versio ei aiheuta latausta', () {
      final result = evaluateManifest(manifest(version: installed), installed);
      expect(result.shouldDownload, isFalse);
      expect(result.status, UpdateStatus.upToDate);
    });

    test('vanhempi julkaistu aineisto ei korvaa uudempaa paikallista', () {
      // Esim. jos julkaisu palautetaan takaisin vanhaan versioon.
      final result = evaluateManifest(manifest(version: older), installed);
      expect(result.shouldDownload, isFalse);
      expect(result.status, UpdateStatus.upToDate);
    });

    test('ensimmäisellä käynnistyksellä ilman asennettua versiota ladataan', () {
      expect(evaluateManifest(manifest(), null).shouldDownload, isTrue);
    });

    test('tuntematon skeemaversio hylätään', () {
      final result = evaluateManifest(manifest(schema: 2), installed);
      expect(result.shouldDownload, isFalse);
      expect(result.status, UpdateStatus.rejected);
      expect(result.message, contains('uudemman sovellusversion'));
    });

    test('liian pieni aineisto hylätään', () {
      // Rikkoutunut lähde voi tuottaa muodollisesti kelvollisen mutta lähes
      // tyhjän aineiston. Se ei saa korvata toimivaa dataa.
      final result = evaluateManifest(manifest(count: 12), installed);
      expect(result.shouldDownload, isFalse);
      expect(result.status, UpdateStatus.rejected);
      expect(result.message, contains('12 kohdetta'));
    });

    test('rajatapaus: täsmälleen alarajalla hyväksytään', () {
      final result = evaluateManifest(
        manifest(count: Config.minAcceptableSpotCount),
        installed,
      );
      expect(result.shouldDownload, isTrue);
    });

    test('rajatapaus: yksi alle alarajan hylätään', () {
      final result = evaluateManifest(
        manifest(count: Config.minAcceptableSpotCount - 1),
        installed,
      );
      expect(result.status, UpdateStatus.rejected);
    });

    test('puuttuvat kentät hylätään', () {
      expect(
        evaluateManifest({'generated_at': newer}, installed).status,
        UpdateStatus.rejected,
      );
      expect(
        evaluateManifest({'schema_version': 1, 'count': 2000}, installed).status,
        UpdateStatus.rejected,
      );
    });

    test('väärän tyyppinen vastaus hylätään', () {
      expect(evaluateManifest('ei ole objekti', installed).status,
          UpdateStatus.rejected);
      expect(evaluateManifest(null, installed).status, UpdateStatus.rejected);
    });

    test('tekstimuotoinen count hylätään eikä tulkita luvuksi', () {
      final result = evaluateManifest(
        {'generated_at': newer, 'schema_version': 1, 'count': '2787'},
        installed,
      );
      expect(result.status, UpdateStatus.rejected);
    });
  });

  group('validateDatabaseFile — ladatun tiedoston tarkistus', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('esteri_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('kelvollinen tiedosto hyväksytään', () async {
      final file = await buildDatabase(dir, rows: 2787);
      expect(await validateDatabaseFile(file, expectedCount: 2787), isNull);
    });

    test('katkennut lataus tunnistetaan rivimäärästä', () async {
      // Metatieto lupaa 2787, mutta rivejä on vähemmän.
      final file = await buildDatabase(dir, rows: 1600);
      final problem = await validateDatabaseFile(file, expectedCount: 2787);
      expect(problem, isNotNull);
      expect(problem, contains('1600 kohdetta'));
    });

    test('väärä skeemaversio hylätään', () async {
      final file = await buildDatabase(dir, rows: 2787, schemaVersion: '2');
      expect(await validateDatabaseFile(file, expectedCount: 2787),
          contains('skeemaversio'));
    });

    test('liian pieni aineisto hylätään vaikka määrä täsmäisi', () async {
      final file = await buildDatabase(dir, rows: 10);
      expect(await validateDatabaseFile(file, expectedCount: 10), isNotNull);
    });

    test('roskatiedosto ei mene läpi tietokantana', () async {
      final file = File('${dir.path}/roska.sqlite')
        ..writeAsBytesSync(List<int>.filled(4096, 7));
      expect(await validateDatabaseFile(file, expectedCount: 2787),
          contains('ei ole kelvollinen'));
    });

    test('tyhjä tiedosto hylätään', () async {
      final file = File('${dir.path}/tyhja.sqlite')..writeAsBytesSync([]);
      expect(await validateDatabaseFile(file, expectedCount: 2787), isNotNull);
    });

    test('olematon tiedosto hylätään', () async {
      expect(
        await validateDatabaseFile(File('${dir.path}/ei-ole.sqlite'),
            expectedCount: 2787),
        isNotNull,
      );
    });
  });
}
