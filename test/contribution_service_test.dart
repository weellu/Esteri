import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:esteri/services/contribution_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String base = 'https://api.test';

const Submission newSpot = Submission(
  kind: SubmissionKind.newSpot,
  lat: 61.4980,
  lon: 23.7610,
  accuracyM: 8,
  note: 'Hissin vieressä',
);

const Submission confirmation = Submission(
  kind: SubmissionKind.present,
  lat: 61.4980,
  lon: 23.7610,
  accuracyM: 8,
  targetUid: 'osm:node/1',
);

/// Palvelu, jonka verkkovastaukset testi määrää.
Future<ContributionService> service({
  required Future<http.Response> Function(http.Request) handler,
  Map<String, Object> prefs = const {},
  String url = base,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  return ContributionService.load(client: MockClient(handler), baseUrl: url);
}

Future<http.Response> Function(http.Request) always(
  int status, {
  String body = '{}',
  List<http.Request>? seen,
}) {
  return (request) async {
    seen?.add(request);
    return http.Response(body, status);
  };
}

void main() {
  group('laitetunniste', () {
    test('on UUID v4 ja säilyy käynnistysten yli', () async {
      final first = await service(handler: always(202));
      expect(
        first.deviceId,
        matches(RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$')),
      );
      // Versio- ja varianttibitit: palvelin hylkää muut muodot.
      expect(first.deviceId[14], '4');
      expect('89ab', contains(first.deviceId[19]));

      // Sama asetusvarasto, uusi lataus: tunniste ei saa vaihtua, muuten
      // saman laitteen toistoja ei voisi karsia.
      final again = await ContributionService.load(
        client: MockClient(always(202)),
        baseUrl: base,
      );
      expect(again.deviceId, first.deviceId);
    });

    test('kaksi eri arvontaa tuottaa eri tunnisteet', () {
      expect(
        ContributionService.newDeviceId(),
        isNot(ContributionService.newDeviceId()),
      );
    });
  });

  group('lähetys', () {
    test(
      'onnistunut lähetys menee oikeaan osoitteeseen oikealla rungolla',
      () async {
        final seen = <http.Request>[];
        final s = await service(
          handler: always(202, body: '{"status":"queued"}', seen: seen),
        );

        expect(await s.submit(newSpot), SubmissionOutcome.sent);
        expect(seen.single.url.toString(), '$base/v1/submissions');

        final body = jsonDecode(seen.single.body) as Map<String, Object?>;
        expect(body['kind'], 'new');
        expect(body['lat'], 61.4980);
        expect(body['lon'], 23.7610);
        expect(body['accuracy_m'], 8);
        expect(body['note'], 'Hissin vieressä');
        expect(body['device'], s.deviceId);
      },
    );

    test('vahvistus kuljettaa kohteen tunnisteen', () async {
      final seen = <http.Request>[];
      final s = await service(handler: always(202, seen: seen));

      await s.submit(confirmation);
      final body = jsonDecode(seen.single.body) as Map<String, Object?>;
      expect(body['kind'], 'present');
      expect(body['target_uid'], 'osm:node/1');
    });

    test('palvelimen tunnistama toisto erotetaan onnistuneesta', () async {
      final s = await service(
        handler: always(202, body: '{"status":"duplicate"}'),
      );
      expect(await s.submit(confirmation), SubmissionOutcome.duplicate);
    });

    test('vuorokauden raja kerrotaan omana tuloksenaan', () async {
      final s = await service(handler: always(429));
      expect(await s.submit(newSpot), SubmissionOutcome.tooMany);
    });

    test('ilman taustapalvelun osoitetta ei lähetetä mitään', () async {
      final seen = <http.Request>[];
      final s = await service(
        handler: always(202, seen: seen),
        url: '',
      );

      expect(await s.submit(newSpot), SubmissionOutcome.unavailable);
      expect(seen, isEmpty);
      expect(s.enabled, isFalse);
    });

    test(
      'vahvistettu kohde muistetaan, jottei nappia painella turhaan',
      () async {
        final s = await service(handler: always(202));
        expect(s.hasActedOn('osm:node/1'), isFalse);
        await s.submit(confirmation);
        expect(s.hasActedOn('osm:node/1'), isTrue);
      },
    );
  });

  group('jono', () {
    test('verkkovirhe jättää lähetyksen jonoon eikä hukkaa sitä', () async {
      final s = await service(
        handler: (_) async => throw const SocketExceptionStub(),
      );

      expect(await s.submit(newSpot), SubmissionOutcome.queued);
      expect(s.pendingCount, 1);
    });

    test('palvelimen 5xx jonotetaan, 4xx ei', () async {
      final serverError = await service(handler: always(503));
      expect(await serverError.submit(newSpot), SubmissionOutcome.queued);
      expect(serverError.pendingCount, 1);

      final badRequest = await service(handler: always(400));
      expect(await badRequest.submit(newSpot), SubmissionOutcome.rejected);
      // Muotovirhe ei korjaannu odottamalla: jonossa se jumittaisi loputkin.
      expect(badRequest.pendingCount, 0);
    });

    test('jono lähtee, kun yhteys palaa', () async {
      var online = false;
      final seen = <http.Request>[];
      final s = await service(
        handler: (request) async {
          if (!online) throw const SocketExceptionStub();
          seen.add(request);
          return http.Response('{}', 202);
        },
      );

      await s.submit(newSpot);
      await s.submit(confirmation);
      expect(s.pendingCount, 2);

      online = true;
      expect(await s.flushPending(), 2);
      expect(s.pendingCount, 0);
      expect(seen, hasLength(2));
      // Sisältö on säilynyt jonon läpi.
      expect(jsonDecode(seen.first.body)['note'], 'Hissin vieressä');
    });

    test('yhä poikki oleva verkko ei tyhjennä jonoa', () async {
      final s = await service(
        handler: (_) async => throw const SocketExceptionStub(),
      );
      await s.submit(newSpot);

      expect(await s.flushPending(), 0);
      expect(s.pendingCount, 1);
    });

    test(
      'katkennut yhteys lopettaa purun eikä yritä koko jonoa turhaan',
      () async {
        var attempts = 0;
        final s = await service(
          handler: (_) async {
            attempts++;
            throw const SocketExceptionStub();
          },
        );
        await s.submit(newSpot);
        await s.submit(newSpot);
        await s.submit(newSpot);
        attempts = 0;

        await s.flushPending();
        // Ensimmäinen epäonnistuminen riittää: loput jäävät jonoon yrittämättä.
        expect(attempts, 1);
        expect(s.pendingCount, 3);
      },
    );

    test('jono ei kasva rajatta', () async {
      final s = await service(
        handler: (_) async => throw const SocketExceptionStub(),
      );
      for (var i = 0; i < ContributionService.maxPending + 10; i++) {
        await s.submit(newSpot);
      }
      expect(s.pendingCount, ContributionService.maxPending);
    });
  });
}

/// Verkkovirhe ilman dart:io-riippuvuutta.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();

  @override
  String toString() => 'verkko poikki';
}
