import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:esteri/data/parking_spot.dart';
import 'package:esteri/data/spot_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Rakenna aineisto pipelinen skeemalla.
///
/// [withRtree] jäljittelee eroa alustojen välillä: iOS:n SQLitessä on
/// rtree-moduuli, Androidin järjestelmä-SQLitessä ei. Ilman taulua kysely
/// on pakko tehdä (lat, lon) -indeksillä.
Future<Database> buildDatabase(
  Directory dir, {
  required bool withRtree,
  String name = 'spots.sqlite',
}) async {
  final db = await databaseFactoryFfi.openDatabase('${dir.path}/$name');
  await db.execute('''
    CREATE TABLE spots (
      id INTEGER PRIMARY KEY, uid TEXT NOT NULL UNIQUE, source TEXT NOT NULL,
      lat REAL NOT NULL, lon REAL NOT NULL, precision TEXT NOT NULL,
      capacity INTEGER, name TEXT, address TEXT, restrictions TEXT,
      max_duration_h REAL, fee INTEGER, updated TEXT, merged_from TEXT
    )
  ''');
  await db.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)');
  await db.execute('CREATE INDEX idx_spots_latlon ON spots(lat, lon)');

  const rows = [
    // Tampere, näkyvällä alueella
    (1, 'osm:1', 61.4978, 23.7610),
    (2, 'osm:2', 61.4990, 23.7650),
    // Helsinki, alueen ulkopuolella
    (3, 'osm:3', 60.1699, 24.9384),
  ];
  for (final (id, uid, lat, lon) in rows) {
    await db.insert('spots', {
      'id': id,
      'uid': uid,
      'source': 'osm',
      'lat': lat,
      'lon': lon,
      'precision': 'space',
    });
  }
  await db.insert('meta', {'key': 'schema_version', 'value': '1'});
  // Metatieto väittää R-treen olevan käytettävissä myös silloin kun taulua
  // ei ole — juuri tähän lippuun luottaminen rikkoi Androidin.
  await db.insert('meta', {'key': 'has_rtree', 'value': '1'});

  if (withRtree) {
    await db.execute(
      'CREATE VIRTUAL TABLE spots_bbox USING rtree(id, min_lat, max_lat, min_lon, max_lon)',
    );
    for (final (id, _, lat, lon) in rows) {
      await db.insert('spots_bbox', {
        'id': id,
        'min_lat': lat,
        'max_lat': lat,
        'min_lon': lon,
        'max_lon': lon,
      });
    }
  }
  return db;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('esteri_db'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('R-treen tunnistus tapahtuu laitteelta, ei metatiedosta', () {
    test('havaitaan käytettäväksi kun taulu on olemassa', () async {
      final db = await buildDatabase(dir, withRtree: true);
      expect(await SpotDatabase.rtreeUsable(db), isTrue);
      await db.close();
    });

    test('havaitaan puuttuvaksi vaikka metatieto väittää muuta', () async {
      // Tämä on se tilanne, joka rikkoi Androidin: has_rtree='1' kertoo vain
      // aineiston rakentaneesta koneesta, ei lukevasta laitteesta.
      final db = await buildDatabase(dir, withRtree: false);
      expect(await SpotDatabase.rtreeUsable(db), isFalse);
      await db.close();
    });
  });

  group('spotsInBounds', () {
    Future<List<ParkingSpot>> query(Database db) async {
      final spots = await SpotDatabase.fromDatabase(db);
      return spots.spotsInBounds(
        minLat: 61.40,
        maxLat: 61.55,
        minLon: 23.60,
        maxLon: 23.90,
      );
    }

    test('palauttaa alueen kohteet R-treen kanssa', () async {
      final db = await buildDatabase(dir, withRtree: true);
      final result = await query(db);
      expect(result.map((s) => s.uid), unorderedEquals(['osm:1', 'osm:2']));
      await db.close();
    });

    test('palauttaa samat kohteet ilman R-treetä', () async {
      // Regressio: ennen korjausta tämä heitti "no such module: rtree" ja
      // kartta jäi tyhjäksi koko Androidilla.
      final db = await buildDatabase(dir, withRtree: false);
      final result = await query(db);
      expect(result.map((s) => s.uid), unorderedEquals(['osm:1', 'osm:2']));
      await db.close();
    });

    test('molemmat polut antavat identtisen tuloksen', () async {
      final withRtree = await buildDatabase(dir, withRtree: true, name: 'a.sqlite');
      final without = await buildDatabase(dir, withRtree: false, name: 'b.sqlite');

      final a = (await query(withRtree)).map((s) => s.uid).toList()..sort();
      final b = (await query(without)).map((s) => s.uid).toList()..sort();

      expect(a, b);
      await withRtree.close();
      await without.close();
    });

    test('alueen ulkopuoliset kohteet rajautuvat pois ilman R-treetä', () async {
      final db = await buildDatabase(dir, withRtree: false);
      final result = await query(db);
      expect(result.map((s) => s.uid), isNot(contains('osm:3')));
      await db.close();
    });

    test('raja noudattaa annettua ruutua', () async {
      final db = await buildDatabase(dir, withRtree: false);
      final spots = await SpotDatabase.fromDatabase(db);
      final result = await spots.spotsInBounds(
        minLat: 60.0,
        maxLat: 60.5,
        minLon: 24.5,
        maxLon: 25.5,
      );
      expect(result.map((s) => s.uid), ['osm:3']);
      await db.close();
    });
  });
}
