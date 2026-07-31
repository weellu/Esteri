import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:leparkki/services/geocoder.dart';

String featureCollection(List<Map<String, Object?>> features) => jsonEncode({
      'type': 'FeatureCollection',
      'features': features,
    });

/// http.Response(String, ...) olettaa latin1:n, kun content-type ei kerro
/// merkistöä. Oikea rajapinta palauttaa UTF-8:aa, joten testivastaukset
/// rakennetaan tavuista.
http.Response jsonResponse(String body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(body), status);

Map<String, Object?> feature(
  double first,
  double second, {
  String? label = 'Hämeenkatu 1, Tampere',
  String? localadmin,
}) =>
    {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [first, second],
      },
      'properties': {
        'label': ?label,
        'localadmin': ?localadmin,
      },
    };

void main() {
  group('MmlGeocoder.search', () {
    test('tulkitsee GeoJSONin lon/lat-järjestyksen oikein', () async {
      final geocoder = MmlGeocoder(
        client: MockClient((_) async =>
            jsonResponse(featureCollection([feature(23.7610, 61.4978)]))),
      );

      final results = await geocoder.search('Hämeenkatu', apiKey: 'avain');

      expect(results, hasLength(1));
      expect(results.single.lat, closeTo(61.4978, 1e-6));
      expect(results.single.lon, closeTo(23.7610, 1e-6));
    });

    test('tulkitsee myös lat/lon-järjestyksen', () async {
      // Palvelun akselijärjestys voi vaihtua CRS-tulkinnan mukana. Suomen
      // arvoalueet eivät mene päällekkäin, joten järjestys on pääteltävissä.
      final geocoder = MmlGeocoder(
        client: MockClient((_) async =>
            jsonResponse(featureCollection([feature(61.4978, 23.7610)]))),
      );

      final results = await geocoder.search('Hämeenkatu', apiKey: 'avain');

      expect(results.single.lat, closeTo(61.4978, 1e-6));
      expect(results.single.lon, closeTo(23.7610, 1e-6));
    });

    test('hylkää koordinaatit Suomen ulkopuolelta', () async {
      // Tukholma. Jos tällainen menisi läpi väärin tulkittuna, käyttäjä
      // ohjattaisiin täysin väärään paikkaan.
      final geocoder = MmlGeocoder(
        client: MockClient((_) async =>
            jsonResponse(featureCollection([feature(18.07, 59.33)]))),
      );

      expect(await geocoder.search('Tukholma', apiKey: 'avain'), isEmpty);
    });

    test('lähettää avaimen ja hakusanan pyynnössä', () async {
      Uri? captured;
      final geocoder = MmlGeocoder(
        client: MockClient((request) async {
          captured = request.url;
          return jsonResponse(featureCollection([]));
        }),
      );

      await geocoder.search('Keskustori', apiKey: 'salainen');

      expect(captured!.queryParameters['text'], 'Keskustori');
      expect(captured!.queryParameters['api-key'], 'salainen');
      expect(captured!.queryParameters['sources'], contains('addresses'));
      expect(captured!.queryParameters['sources'], contains('geographic-names'));
    });

    test('ei hae kiinteistötunnuksia eikä karttalehtiä', () async {
      Uri? captured;
      final geocoder = MmlGeocoder(
        client: MockClient((request) async {
          captured = request.url;
          return jsonResponse(featureCollection([]));
        }),
      );

      await geocoder.search('123', apiKey: 'avain');

      final sources = captured!.queryParameters['sources']!;
      expect(sources, isNot(contains('cadastral-units')));
      expect(sources, isNot(contains('mapsheets')));
    });

    test('tyhjä hakusana ei tee verkkokutsua', () async {
      var called = false;
      final geocoder = MmlGeocoder(
        client: MockClient((_) async {
          called = true;
          return jsonResponse(featureCollection([]));
        }),
      );

      expect(await geocoder.search('   ', apiKey: 'avain'), isEmpty);
      expect(called, isFalse);
    });

    test('puuttuva avain kerrotaan käyttäjälle ymmärrettävästi', () async {
      final geocoder = MmlGeocoder(
        client: MockClient((_) async => jsonResponse('')),
      );

      expect(
        () => geocoder.search('Hämeenkatu', apiKey: ''),
        throwsA(isA<GeocoderException>().having(
          (e) => e.message,
          'message',
          contains('API-avaimen'),
        )),
      );
    });

    test('401 tunnistetaan kelpaamattomaksi avaimeksi', () async {
      final geocoder = MmlGeocoder(
        client: MockClient((_) async => jsonResponse('nope', 401)),
      );

      expect(
        () => geocoder.search('Hämeenkatu', apiKey: 'vaara'),
        throwsA(isA<GeocoderException>().having(
          (e) => e.message,
          'message',
          contains('ei kelpaa'),
        )),
      );
    });

    test('rikkinäinen vastaus ei kaada sovellusta', () async {
      final geocoder = MmlGeocoder(
        client: MockClient((_) async => jsonResponse('{"virhe": true}')),
      );

      expect(
        () => geocoder.search('Hämeenkatu', apiKey: 'avain'),
        throwsA(isA<GeocoderException>()),
      );
    });

    test('kunta näytetään vain jos se ei ole jo nimessä', () async {
      final geocoder = MmlGeocoder(
        client: MockClient((_) async => jsonResponse(featureCollection([
              feature(23.7610, 61.4978,
                  label: 'Hämeenkatu 1, Tampere', localadmin: 'Tampere'),
              feature(23.7620, 61.4988, label: 'Keskustori', localadmin: 'Tampere'),
            ]))),
      );

      final results = await geocoder.search('Tampere', apiKey: 'avain');

      expect(results[0].region, isNull, reason: 'Tampere on jo labelissa');
      expect(results[1].region, 'Tampere');
    });

    test('nimettömät osumat ohitetaan', () async {
      final geocoder = MmlGeocoder(
        client: MockClient((_) async => jsonResponse(
                featureCollection([feature(23.7610, 61.4978, label: null)]))),
      );

      expect(await geocoder.search('x', apiKey: 'avain'), isEmpty);
    });

    test('ääkköset säilyvät vastauksessa', () async {
      final geocoder = MmlGeocoder(
        client: MockClient((_) async => jsonResponse(featureCollection(
                [feature(23.7610, 61.4978, label: 'Pyynikintörmä')]))),
      );

      final results = await geocoder.search('Pyynikki', apiKey: 'avain');
      expect(results.single.label, 'Pyynikintörmä');
    });
  });
}
