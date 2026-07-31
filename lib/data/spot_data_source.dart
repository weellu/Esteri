import 'dart:io';

import 'package:flutter/foundation.dart';

import 'parking_spot.dart';
import 'spot_database.dart';

/// Vaihdettava kohdelähde karttanäkymälle.
///
/// Kääre `SpotDatabase`n ympärille, jotta levyllä oleva aineisto voidaan
/// korvata ajon aikana ilman että käyttöliittymän tarvitsee tietää siitä.
/// Ilmoittaa kuuntelijoille kun data on vaihtunut, jolloin kartta hakee
/// näkyvän alueen kohteet uudelleen.
class SpotDataSource extends ChangeNotifier implements SpotRepository {
  SpotDataSource._(this._db);

  SpotDatabase _db;

  static Future<SpotDataSource> open() async =>
      SpotDataSource._(await SpotDatabase.open());

  @override
  Future<List<ParkingSpot>> spotsInBounds({
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
    int limit = 2000,
  }) =>
      _db.spotsInBounds(
        minLat: minLat,
        maxLat: maxLat,
        minLon: minLon,
        maxLon: maxLon,
        limit: limit,
      );

  @override
  Future<List<ParkingSpot>> searchByText(String query, {int limit = 20}) =>
      _db.searchByText(query, limit: limit);

  Future<Map<String, String>> metadata() => _db.metadata();

  /// Ota ladattu aineisto käyttöön.
  ///
  /// Tietokanta on suljettava ennen tiedoston korvaamista. Jos korvaaminen
  /// epäonnistuu, vanha aineisto avataan takaisin — käyttäjä ei saa jäädä
  /// ilman dataa epäonnistuneen päivityksen takia.
  Future<void> installDownloaded(File downloaded, String version) async {
    final target = await SpotDatabase.localPath();
    await _db.close();
    try {
      await downloaded.rename(target);
      await SpotDatabase.setInstalledVersion(version);
    } catch (error) {
      debugPrint('Aineiston korvaaminen epäonnistui: $error');
      _db = await SpotDatabase.open();
      rethrow;
    }
    _db = await SpotDatabase.open();
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    await _db.close();
    super.dispose();
  }
}
