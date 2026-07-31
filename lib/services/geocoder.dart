import 'dart:convert';

import 'package:http/http.dart' as http;

/// Geokoodauksen tulos: osoite tai paikannimi karttasijainteineen.
class GeocodeResult {
  const GeocodeResult({
    required this.label,
    required this.lat,
    required this.lon,
    this.region,
  });

  /// Käyttäjälle näytettävä koko nimi, esim. "Hämeenkatu 1, Tampere".
  final String label;

  /// Tarkentava tieto, esim. kunta. Null jos sama kuin labelissa jo.
  final String? region;

  final double lat;
  final double lon;
}

class GeocoderException implements Exception {
  const GeocoderException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Maanmittauslaitoksen geokoodauspalvelu (Pelias-pohjainen).
///
/// Käyttää samaa maksutonta API-avainta kuin karttatiilet, joten käyttäjän
/// ei tarvitse rekisteröityä erikseen hakua varten.
class MmlGeocoder {
  MmlGeocoder({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _baseUrl =
      'https://avoin-paikkatieto.maanmittauslaitos.fi/geocoding/v2/pelias/search';

  /// Haetaan vain osoitteita ja paikannimiä. Kiinteistötunnukset ja
  /// karttalehdet jätetään pois — ne eivät auta invapaikan etsijää.
  static const String _sources =
      'addresses,interpolated-road-addresses,geographic-names';

  /// Suomen leveys- ja pituusasteet eivät mene päällekkäin (lat 59.5–70.1,
  /// lon 19.0–31.7), joten akselijärjestys voidaan päätellä arvoista.
  /// Tämä suojaa siltä, että palvelu vaihtaisi CRS84:n ja EPSG:4326:n
  /// tulkintaa — sekaannus, joka sijoittaisi kaikki tulokset Somaliaan.
  static (double lat, double lon)? _asLatLon(num a, num b) {
    const minLat = 59.5, maxLat = 70.1, minLon = 19.0, maxLon = 31.7;
    final aLat = a >= minLat && a <= maxLat;
    final bLat = b >= minLat && b <= maxLat;
    final aLon = a >= minLon && a <= maxLon;
    final bLon = b >= minLon && b <= maxLon;
    if (bLat && aLon && !aLat) return (b.toDouble(), a.toDouble()); // [lon, lat]
    if (aLat && bLon && !bLat) return (a.toDouble(), b.toDouble()); // [lat, lon]
    return null;
  }

  Future<List<GeocodeResult>> search(
    String query, {
    required String apiKey,
    int limit = 8,
  }) async {
    final text = query.trim();
    if (text.isEmpty) return const [];
    if (apiKey.isEmpty) {
      throw const GeocoderException(
        'Haku osoitteella vaatii API-avaimen. Lisää se asetuksista.',
      );
    }

    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'text': text,
      'size': '$limit',
      'lang': 'fi',
      'sources': _sources,
      'api-key': apiKey,
    });

    final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 12));
    } catch (error) {
      throw GeocoderException('Hakua ei voitu tehdä: verkkovirhe.');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const GeocoderException(
        'API-avain ei kelpaa hakuun. Tarkista se asetuksista.',
      );
    }
    if (response.statusCode != 200) {
      throw GeocoderException('Hakupalvelu vastasi virheellä ${response.statusCode}.');
    }

    final Object? decoded;
    try {
      // allowMalformed: viallinen tavu ei saa kaataa hakua käsittelemättömään
      // poikkeukseen — mieluummin korvausmerkki kuin kaatuminen.
      decoded = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
    } on FormatException {
      throw const GeocoderException('Hakupalvelun vastausta ei ymmärretty.');
    }
    if (decoded is! Map || decoded['features'] is! List) {
      throw const GeocoderException('Hakupalvelun vastausta ei ymmärretty.');
    }

    final results = <GeocodeResult>[];
    for (final feature in decoded['features'] as List) {
      if (feature is! Map) continue;
      final geometry = feature['geometry'];
      final properties = feature['properties'];
      if (geometry is! Map || properties is! Map) continue;
      final coordinates = geometry['coordinates'];
      if (coordinates is! List || coordinates.length < 2) continue;
      final first = coordinates[0];
      final second = coordinates[1];
      if (first is! num || second is! num) continue;

      final position = _asLatLon(first, second);
      if (position == null) continue;

      final label = (properties['label'] ?? properties['name'])?.toString();
      if (label == null || label.isEmpty) continue;

      final region = properties['localadmin']?.toString() ??
          properties['region']?.toString();

      results.add(
        GeocodeResult(
          label: label,
          region: region != null && !label.contains(region) ? region : null,
          lat: position.$1,
          lon: position.$2,
        ),
      );
    }
    return results;
  }

  void dispose() => _client.close();
}
