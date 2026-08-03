import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:esteri/ui/attribution_bar.dart';
import 'package:esteri/ui/licenses_screen.dart';
import 'package:esteri/ui/map_screen.dart';

import 'fakes.dart';

Future<void> pumpBar(WidgetTester tester, {required bool showMapTiles}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: AttributionBar(showMapTiles: showMapTiles)),
    ),
  );
}

void main() {
  group('AttributionBar', () {
    testWidgets('OSM ja ODbL mainitaan aina', (tester) async {
      // ODbL edellyttää tekijöiden ja lisenssin mainintaa. Tämä ei ole
      // valinnainen yksityiskohta vaan ehto datan käytölle.
      await pumpBar(tester, showMapTiles: false);
      expect(find.textContaining('OpenStreetMap'), findsOneWidget);
      expect(find.textContaining('ODbL'), findsOneWidget);
    });

    testWidgets('kartan lähde mainitaan kun tiiliä näytetään', (tester) async {
      await pumpBar(tester, showMapTiles: true);
      expect(find.textContaining('Maanmittauslaitos'), findsOneWidget);
    });

    testWidgets('kartan lähdettä ei mainita kun tiiliä ei näytetä',
        (tester) async {
      await pumpBar(tester, showMapTiles: false);
      expect(find.textContaining('Maanmittauslaitos'), findsNothing);
    });

    testWidgets('napautus avaa koko lisenssiluettelon', (tester) async {
      await pumpBar(tester, showMapTiles: true);
      await tester.tap(find.byType(AttributionBar));
      await tester.pumpAndSettle();
      expect(find.byType(LicensesScreen), findsOneWidget);
    });
  });

  group('LicensesScreen', () {
    testWidgets('jokainen käytetty lähde on lueteltu', (tester) async {
      // ListView rakentaa vain näkyvät kortit, joten testinäkymä on
      // kasvatettava jotta koko luettelo on kerralla arvioitavissa.
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: LicensesScreen()));

      for (final source in [
        'OpenStreetMap',
        'Digiroad',
        'Tampereen kaupunki',
        'Turun kaupunki',
        'Helsingin kaupunki',
        'Maanmittauslaitos',
      ]) {
        expect(find.textContaining(source), findsWidgets, reason: 'puuttuu: $source');
      }
    });

    testWidgets('yhdistetyn aineiston ODbL-velvoite kerrotaan', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LicensesScreen()));
      expect(find.textContaining('johdettu tietokanta'), findsOneWidget);
    });
  });

  group('kartalla', () {
    testWidgets('attribuutio on näkyvissä ilman napautusta', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MapScreen(
            database: FakeSpotRepository([]),
            keyStore: await fakeKeyStore(),
            geocoder: fakeGeocoder(),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(AttributionBar), findsOneWidget);
    });
  });
}
