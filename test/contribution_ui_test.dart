import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:esteri/data/parking_spot.dart';
import 'package:esteri/services/contribution_service.dart';
import 'package:esteri/services/location_service.dart';
import 'package:esteri/ui/add_spot_sheet.dart';
import 'package:esteri/ui/spot_details_sheet.dart';
import 'package:esteri/ui/spot_marker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

final LatLng here = LatLng(61.4980, 23.7610);

Future<ContributionService> contributionService(
  List<http.Request> seen, {
  int status = 202,
  String url = 'https://api.test',
}) async {
  SharedPreferences.setMockInitialValues({});
  return ContributionService.load(
    baseUrl: url,
    client: MockClient((request) async {
      seen.add(request);
      return http.Response('{"status":"queued"}', status);
    }),
  );
}

Future<void> pumpDetails(
  WidgetTester tester,
  ParkingSpot spot, {
  ContributionService? contributions,
  LocationService? location,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SpotDetailsSheet(
          spot: spot,
          contributions: contributions,
          location: location,
        ),
      ),
    ),
  );
}

void main() {
  group('kohteen tiedot', () {
    testWidgets('ilman lähetyspalvelua vahvistuspainikkeita ei ole', (
      tester,
    ) async {
      await pumpDetails(tester, spotAt(61.5, 23.8));

      expect(find.text('Paikka on'), findsNothing);
      expect(find.text('Ei löydy'), findsNothing);
      // Muu näkymä toimii entiseen tapaan.
      expect(find.text('Navigoi tähän'), findsOneWidget);
    });

    testWidgets('vahvistuspainikkeet näkyvät, kun lähetys on käytössä', (
      tester,
    ) async {
      await pumpDetails(
        tester,
        spotAt(61.5, 23.8),
        contributions: await contributionService([]),
        location: FakeLocationService(first: here),
      );

      expect(find.text('Paikka on'), findsOneWidget);
      expect(find.text('Ei löydy'), findsOneWidget);
    });

    testWidgets(
      'vahvistus lähettää kohteen tunnisteen ja kuittaa käyttäjälle',
      (tester) async {
        final seen = <http.Request>[];
        await pumpDetails(
          tester,
          spotAt(61.5, 23.8, uid: 'osm:node/42'),
          contributions: await contributionService(seen),
          location: FakeLocationService(first: here),
        );

        await tester.tap(find.text('Paikka on'));
        await tester.pumpAndSettle();

        final body = jsonDecode(seen.single.body) as Map<String, Object?>;
        expect(body['kind'], 'present');
        expect(body['target_uid'], 'osm:node/42');
        expect(body['lat'], here.latitude);
        expect(body['accuracy_m'], 8);

        expect(
          find.textContaining('ilmoituksesi tästä paikasta on kirjattu'),
          findsOneWidget,
        );
      },
    );

    testWidgets('"ei löydy" lähettää kiiston eikä vahvistusta', (tester) async {
      final seen = <http.Request>[];
      await pumpDetails(
        tester,
        spotAt(61.5, 23.8, uid: 'osm:node/42'),
        contributions: await contributionService(seen),
        location: FakeLocationService(first: here),
      );

      await tester.tap(find.text('Ei löydy'));
      await tester.pumpAndSettle();

      expect(jsonDecode(seen.single.body)['kind'], 'missing');
    });

    testWidgets('vahvistus voi samalla korjata ruutumäärän', (tester) async {
      // Erillistä korjausnappia ei ole: "Paikka on" ja "täällä on kaksi
      // ruutua eikä kolme" ovat sama ele paikan päällä.
      final seen = <http.Request>[];
      await pumpDetails(
        tester,
        spotAt(61.5, 23.8, uid: 'osm:node/42'),
        contributions: await contributionService(seen),
        location: FakeLocationService(first: here),
      );

      await tester.tap(find.widgetWithText(ChoiceChip, '2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paikka on'));
      await tester.pumpAndSettle();

      final body = jsonDecode(seen.single.body) as Map<String, Object?>;
      expect(body['kind'], 'present');
      expect(body['capacity'], 2);
      expect(body['target_uid'], 'osm:node/42');
    });

    testWidgets('kiisto ei kanna ruutumäärää', (tester) async {
      // Olemattomalla paikalla ei ole ruutuja, ja palvelin hylkää yhdistelmän.
      final seen = <http.Request>[];
      await pumpDetails(
        tester,
        spotAt(61.5, 23.8, uid: 'osm:node/42'),
        contributions: await contributionService(seen),
        location: FakeLocationService(first: here),
      );

      await tester.tap(find.widgetWithText(ChoiceChip, '2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ei löydy'));
      await tester.pumpAndSettle();

      final body = jsonDecode(seen.single.body) as Map<String, Object?>;
      expect(body['kind'], 'missing');
      expect(body.containsKey('capacity'), isFalse);
    });

    testWidgets('evätty sijaintilupa kerrotaan eikä lähetetä mitään', (
      tester,
    ) async {
      final seen = <http.Request>[];
      await pumpDetails(
        tester,
        spotAt(61.5, 23.8),
        contributions: await contributionService(seen),
        location: FakeLocationService(
          denial: LocationDenial.permissionDenied,
          first: here,
        ),
      );

      await tester.tap(find.text('Paikka on'));
      await tester.pumpAndSettle();

      expect(seen, isEmpty);
      expect(find.textContaining('sijaintiluvan'), findsOneWidget);
    });

    testWidgets('liian epätarkka sijainti torjutaan jo laitteella', (
      tester,
    ) async {
      // Hylkäys tehdään heti eikä vasta moderoinnissa: käyttäjä voi siirtyä
      // katveesta ja yrittää uudelleen, mutta vain jos hänelle kerrotaan.
      final seen = <http.Request>[];
      await pumpDetails(
        tester,
        spotAt(61.5, 23.8),
        contributions: await contributionService(seen),
        location: FakeLocationService(first: here, accuracyM: 350),
      );

      await tester.tap(find.text('Paikka on'));
      await tester.pumpAndSettle();

      expect(seen, isEmpty);
      expect(find.textContaining('±350 m'), findsOneWidget);
    });

    testWidgets('vahvistusten ja kiistojen määrä näytetään', (tester) async {
      await pumpDetails(
        tester,
        spotAt(61.5, 23.8, confirmations: 4, disputes: 2),
      );

      expect(
        find.text('4 käyttäjää on vahvistanut paikan päällä'),
        findsOneWidget,
      );
      expect(find.text('2 käyttäjää ei löytänyt paikkaa'), findsOneWidget);
    });

    testWidgets('vahvistamaton ilmoitus esitetään vahvistamattomana', (
      tester,
    ) async {
      await pumpDetails(
        tester,
        spotAt(
          61.5,
          23.8,
          source: 'users',
          precision: SpotPrecision.area,
          verification: SpotVerification.reported,
        ),
      );

      expect(find.text('Käyttäjän ilmoittama invapaikka'), findsOneWidget);
      expect(
        find.textContaining('kukaan muu ei ole vielä vahvistanut'),
        findsOneWidget,
      );
      // Vahvistamatonta ilmoitusta ei saa esittää pysäköintialueena, vaikka
      // sen sijaintitarkkuus onkin "area".
      expect(
        find.textContaining('Pysäköintialue, jolla on invapaikkoja'),
        findsNothing,
      );
    });
  });

  group('markkeri', () {
    testWidgets('vahvistamaton kohde erottuu myös ilman värin näkemistä', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpotMarkerIcon(
              spot: spotAt(
                61.5,
                23.8,
                verification: SpotVerification.reported,
                precision: SpotPrecision.area,
              ),
            ),
          ),
        ),
      );

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets(
      'avoimen aineiston kohteessa ei ole vahvistamattoman tunnusta',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: SpotMarkerIcon(spot: spotAt(61.5, 23.8))),
          ),
        );

        expect(find.text('?'), findsNothing);
      },
    );
  });

  group('uuden paikan ilmoitus', () {
    Future<void> pumpAddSheet(
      WidgetTester tester, {
      required ContributionService contributions,
      required LocationService location,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => AddSpotSheet.show(
                  context,
                  contributions: contributions,
                  location: location,
                ),
                child: const Text('avaa'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('avaa'));
      await tester.pumpAndSettle();
    }

    testWidgets('lähettää uuden kohteen sijainnin ja saatteen', (tester) async {
      final seen = <http.Request>[];
      await pumpAddSheet(
        tester,
        contributions: await contributionService(seen),
        location: FakeLocationService(first: here),
      );

      expect(find.textContaining('Sijainti löytyi'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'P-talon 2. krs');
      await tester.tap(find.text('Lähetä ilmoitus'));
      await tester.pumpAndSettle();

      final body = jsonDecode(seen.single.body) as Map<String, Object?>;
      expect(body['kind'], 'new');
      expect(body['lat'], here.latitude);
      expect(body['lon'], here.longitude);
      expect(body['note'], 'P-talon 2. krs');
      expect(body.containsKey('target_uid'), isFalse);
    });

    testWidgets('ruutumäärä lähtee mukaan valittuna', (tester) async {
      final seen = <http.Request>[];
      await pumpAddSheet(
        tester,
        contributions: await contributionService(seen),
        location: FakeLocationService(first: here),
      );

      await tester.tap(find.widgetWithText(ChoiceChip, '3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lähetä ilmoitus'));
      await tester.pumpAndSettle();

      final body = jsonDecode(seen.single.body) as Map<String, Object?>;
      expect(body['capacity'], 3);
    });

    testWidgets('valitsematta jätetty määrä ei mene mukaan arvauksena', (
      tester,
    ) async {
      // Tyhjä kenttä ja arvaus ovat eri asioita: arvaus näyttäisi kartalla
      // tiedolta, jota kukaan ei ole antanut.
      final seen = <http.Request>[];
      await pumpAddSheet(
        tester,
        contributions: await contributionService(seen),
        location: FakeLocationService(first: here),
      );

      await tester.tap(find.text('Lähetä ilmoitus'));
      await tester.pumpAndSettle();

      final body = jsonDecode(seen.single.body) as Map<String, Object?>;
      expect(body.containsKey('capacity'), isFalse);
    });

    testWidgets('saman sirun uudelleenvalinta peruu määrän', (tester) async {
      // Väärin osunutta napautusta ei saisi muuten peruttua ilman lomakkeen
      // sulkemista.
      final seen = <http.Request>[];
      await pumpAddSheet(
        tester,
        contributions: await contributionService(seen),
        location: FakeLocationService(first: here),
      );

      await tester.tap(find.widgetWithText(ChoiceChip, '2'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lähetä ilmoitus'));
      await tester.pumpAndSettle();

      final body = jsonDecode(seen.single.body) as Map<String, Object?>;
      expect(body.containsKey('capacity'), isFalse);
    });

    testWidgets('epätarkalla sijainnilla lähetystä ei voi tehdä', (
      tester,
    ) async {
      final seen = <http.Request>[];
      await pumpAddSheet(
        tester,
        contributions: await contributionService(seen),
        location: FakeLocationService(first: here, accuracyM: 200),
      );

      expect(find.textContaining('±200 m'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);

      await tester.tap(find.text('Lähetä ilmoitus'));
      await tester.pumpAndSettle();
      expect(seen, isEmpty);
    });

    testWidgets('ilman sijaintilupaa kerrotaan syy eikä lähetetä', (
      tester,
    ) async {
      final seen = <http.Request>[];
      await pumpAddSheet(
        tester,
        contributions: await contributionService(seen),
        location: FakeLocationService(
          denial: LocationDenial.serviceDisabled,
          first: here,
        ),
      );

      expect(find.text('Ilmoittaminen vaatii sijainnin.'), findsOneWidget);
      expect(seen, isEmpty);
    });

    testWidgets('verkkokatko ei hukkaa ilmoitusta vaan jonottaa sen', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final contributions = await ContributionService.load(
        baseUrl: 'https://api.test',
        client: MockClient((_) async => throw Exception('verkko poikki')),
      );

      await pumpAddSheet(
        tester,
        contributions: contributions,
        location: FakeLocationService(first: here),
      );

      await tester.tap(find.text('Lähetä ilmoitus'));
      await tester.pumpAndSettle();

      expect(contributions.pendingCount, 1);
      expect(find.textContaining('lähtee, kun yhteys palaa'), findsOneWidget);
    });
  });
}
