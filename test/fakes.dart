import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:leparkki/config.dart';
import 'package:leparkki/data/parking_spot.dart';
import 'package:leparkki/data/spot_database.dart';
import 'package:leparkki/services/geocoder.dart';
import 'package:leparkki/services/map_key_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Muistinvarainen korvike SQLitelle, jotta näkymien logiikan voi testata
/// ilman natiiveja liitännäisiä.
class FakeSpotRepository implements SpotRepository {
  FakeSpotRepository(this.spots, {this.searchResults = const []});

  final List<ParkingSpot> spots;
  final List<ParkingSpot> searchResults;

  final List<List<double>> requestedBounds = [];
  final List<String> searchQueries = [];

  @override
  Future<List<ParkingSpot>> spotsInBounds({
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
    int limit = Config.maxSpotsPerViewport,
  }) async {
    requestedBounds.add([minLat, maxLat, minLon, maxLon]);
    return spots
        .where((s) =>
            s.lat >= minLat && s.lat <= maxLat && s.lon >= minLon && s.lon <= maxLon)
        .toList();
  }

  @override
  Future<List<ParkingSpot>> searchByText(String query, {int limit = 20}) async {
    searchQueries.add(query);
    return searchResults.take(limit).toList();
  }
}

ParkingSpot spotAt(
  double lat,
  double lon, {
  String uid = 'osm:1',
  SpotPrecision precision = SpotPrecision.space,
  int? capacity,
  String? name,
  String? address,
}) =>
    ParkingSpot(
      id: 1,
      uid: uid,
      source: 'osm',
      lat: lat,
      lon: lon,
      precision: precision,
      capacity: capacity,
      name: name,
      address: address,
    );

Future<MapKeyStore> fakeKeyStore({String? key}) async {
  SharedPreferences.setMockInitialValues(
    key == null ? <String, Object>{} : <String, Object>{'mml_api_key': key},
  );
  return MapKeyStore.load();
}

/// Geokoodaaja, joka palauttaa annetut osumat verkkoon menemättä.
MmlGeocoder fakeGeocoder({
  List<({String label, double lat, double lon})> results = const [],
  int status = 200,
}) {
  final body = jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (final r in results)
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [r.lon, r.lat],
          },
          'properties': {'label': r.label},
        },
    ],
  });
  return MmlGeocoder(
    client: MockClient(
      (_) async => http.Response.bytes(utf8.encode(body), status),
    ),
  );
}
