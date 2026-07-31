import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../config.dart';
import 'parking_spot.dart';

/// Kohteiden lähde karttanäkymälle.
///
/// Rajapinta erottaa karttanäkymän SQLitestä, jotta näkymän logiikan voi
/// testata ilman tiedostojärjestelmää ja natiiveja liitännäisiä.
abstract class SpotRepository {
  Future<List<ParkingSpot>> spotsInBounds({
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
    int limit,
  });

  Future<List<ParkingSpot>> searchByText(String query, {int limit});
}

/// Paikallinen invapaikkatietokanta.
///
/// Aineisto toimitetaan sovelluksen mukana SQLite-tiedostona. Sitä ei voi
/// kysellä suoraan assetista, joten se kopioidaan ensimmäisellä
/// käynnistyksellä laitteen tiedostojärjestelmään.
///
/// Kartalle ei koskaan ladata koko aineistoa vaan ainoastaan näkyvän
/// karttaruudun kohteet. Se on tarkoituksellista: flutter_map renderöi
/// markerit Flutter-widgeteinä, eikä tuhansia widgetejä kannata pitää
/// puussa yhtä aikaa edes klusteroituna.
class SpotDatabase implements SpotRepository {
  SpotDatabase._(this._db, this._useRtree);

  final Database _db;
  final bool _useRtree;

  static const String _versionKey = 'bundled_data_version';

  static Future<SpotDatabase> open() async {
    final path = await _ensureLocalCopy();
    final db = await openDatabase(path, readOnly: true);

    final meta = await db.query('meta', where: 'key = ?', whereArgs: ['has_rtree']);
    final useRtree = meta.isNotEmpty && meta.first['value'] == '1';

    return SpotDatabase._(db, useRtree);
  }

  /// Kopioi assetissa oleva tietokanta laitteelle, jos sitä ei vielä ole tai
  /// jos mukana toimitettu versio on vaihtunut.
  static Future<String> _ensureLocalCopy() async {
    final dir = await getApplicationSupportDirectory();
    final target = p.join(dir.path, 'invapaikat.sqlite');
    final prefs = await SharedPreferences.getInstance();
    final installed = prefs.getString(_versionKey);

    final exists = File(target).existsSync();
    if (exists && installed == Config.bundledDataVersion) {
      return target;
    }

    final bytes = await rootBundle.load(Config.assetDatabasePath);
    await File(target).writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
    await prefs.setString(_versionKey, Config.bundledDataVersion);
    debugPrint('Invapaikka-aineisto asennettu: ${Config.bundledDataVersion}');
    return target;
  }

  /// Hae näkyvän karttaruudun kohteet.
  ///
  /// R-tree-indeksi tekee tästä vakioaikaisen suhteessa aineiston kokoon;
  /// ilman sitä jokainen kartansiirto olisi taulun täysiskannaus.
  @override
  Future<List<ParkingSpot>> spotsInBounds({
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
    int limit = Config.maxSpotsPerViewport,
  }) async {
    final rows = _useRtree
        ? await _db.rawQuery(
            '''
            SELECT s.* FROM spots_bbox b
            JOIN spots s ON s.id = b.id
            WHERE b.max_lat >= ? AND b.min_lat <= ?
              AND b.max_lon >= ? AND b.min_lon <= ?
            LIMIT ?
            ''',
            [minLat, maxLat, minLon, maxLon, limit],
          )
        : await _db.rawQuery(
            '''
            SELECT * FROM spots
            WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?
            LIMIT ?
            ''',
            [minLat, maxLat, minLon, maxLon, limit],
          );

    if (rows.length == limit) {
      debugPrint('Karttaruudussa vähintään $limit kohdetta — tulos katkaistiin.');
    }
    return rows.map(ParkingSpot.fromRow).toList(growable: false);
  }

  /// Vapaa tekstihaku nimen ja osoitteen perusteella.
  ///
  /// Kattaa vain ne kohteet, joilla on nimi tai osoite — aineistossa
  /// osoite on vain 214 kohteella. Paikannimihaku hoidetaan geokoodauksella,
  /// ei tästä.
  @override
  Future<List<ParkingSpot>> searchByText(String query, {int limit = 20}) async {
    final term = '%${query.trim()}%';
    if (query.trim().isEmpty) return const [];
    final rows = await _db.rawQuery(
      '''
      SELECT * FROM spots
      WHERE name LIKE ? OR address LIKE ?
      LIMIT ?
      ''',
      [term, term, limit],
    );
    return rows.map(ParkingSpot.fromRow).toList(growable: false);
  }

  Future<Map<String, String>> metadata() async {
    final rows = await _db.query('meta');
    return {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
  }

  Future<int> count() async {
    final result = await _db.rawQuery('SELECT COUNT(*) AS n FROM spots');
    return result.first['n'] as int;
  }

  Future<void> close() => _db.close();
}
