import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

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

/// Osoite- ja paikannimihaku oman Workerin kautta.
///
/// Vastausmuoto on Maanmittauslaitoksen Pelias-rajapinnan GeoJSON, mutta
/// sovellus ei kutsu MML:ää suoraan: API-avain on Workerissa eikä laitteella.
/// Siksi tämä ei ota vastaan avainta lainkaan — sellaista ei ole olemassa
/// asiakaspäässä.
class MmlGeocoder {
  MmlGeocoder({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? Config.geocodeUrl;

  final http.Client _client;
  final String _baseUrl;

  /// Lyhin hakusana, joka lähetetään verkkoon.
  ///
  /// Yhden merkin haku ei tuota käyttökelpoista tulosta, mutta maksaa saman
  /// verran kuin mikä tahansa muu: hakupalkin viive laukaisee kutsun aina kun
  /// kirjoittaja pysähtyy yli 350 ms:ksi, myös heti ensimmäisen kirjaimen
  /// jälkeen.
  ///
  /// Raja on kaksi eikä kolme, koska **Ii** on kunta. Kolmen merkin raja
  /// tekisi siitä hakukelvottoman.
  static const int minQueryLength = 2;

  /// Muistivälimuisti onnistuneille hauille.
  ///
  /// Sama hakusana toistuu käytössä jatkuvasti: kirjoitusvirheen korjaus
  /// askelpalauttimella palaa lyhyempään sanaan, joka on juuri haettu, ja sama
  /// osoite haetaan usein uudelleen saman istunnon aikana.
  ///
  /// Virheitä ei talleteta. Verkkovirhe on ohimenevä tila, eikä sitä pidä
  /// jäädyttää välimuistiin — muuten yksi katkos rikkoisi haun siihen asti,
  /// kunnes sovellus käynnistetään uudelleen.
  static const int maxCacheEntries = 64;

  final Map<String, List<GeocodeResult>> _cache = {};

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

  Future<List<GeocodeResult>> search(String query, {int limit = 8}) async {
    final text = query.trim();
    if (text.length < minQueryLength) return const [];

    // Pelias ei erottele kirjainkokoa, joten "Hämeenkatu" ja "hämeenkatu"
    // ovat välimuistin kannalta sama haku.
    final cacheKey = '${text.toLowerCase()}|$limit';
    final cached = _cache.remove(cacheKey);
    if (cached != null) {
      // Uudelleen lisäys siirtää osuman jonon perälle, jolloin poistuvaksi
      // valikoituu aina pisimpään koskematta ollut.
      _cache[cacheKey] = cached;
      return cached;
    }

    // Kieli ja lähteet kiinnitetään Workerissa, ei täällä: proxy ei välitä
    // mielivaltaista MML-pyyntöä vaan täsmälleen tämän haun.
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'text': text,
      'size': '$limit',
    });

    final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 12));
    } catch (error) {
      throw GeocoderException('Hakua ei voitu tehdä: verkkovirhe.');
    }

    // Virhe ei ole enää koskaan käyttäjän avaimessa, koska avainta ei ole
    // asiakaspäässä. 502 ja 503 tarkoittavat, että vika on taustapalvelussa
    // tai sen takana — kumpaankaan käyttäjä ei voi vaikuttaa, joten häntä ei
    // myöskään pyydetä korjaamaan mitään.
    if (response.statusCode == 502 || response.statusCode == 503) {
      throw const GeocoderException(
        'Haku ei ole juuri nyt käytettävissä. Yritä hetken kuluttua uudelleen.',
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

    final stored = List<GeocodeResult>.unmodifiable(results);
    if (_cache.length >= maxCacheEntries) _cache.remove(_cache.keys.first);
    _cache[cacheKey] = stored;
    return stored;
  }

  void dispose() => _client.close();
}
