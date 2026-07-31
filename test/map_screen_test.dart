import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leparkki/config.dart';
import 'package:leparkki/services/geocoder.dart';
import 'package:leparkki/services/map_key_store.dart';
import 'package:leparkki/ui/map_screen.dart';
import 'package:leparkki/ui/spot_marker.dart';

import 'fakes.dart';

Future<void> pumpMap(
  WidgetTester tester,
  FakeSpotRepository repo,
  MapKeyStore store, {
  MmlGeocoder? geocoder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MapScreen(
        database: repo,
        keyStore: store,
        geocoder: geocoder ?? fakeGeocoder(),
      ),
    ),
  );
  // onMapReady + viive + asynkroninen haku.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('kohteet haetaan vain näkyvältä alueelta', (tester) async {
    final repo = FakeSpotRepository([
      spotAt(Config.fallbackLat, Config.fallbackLon),
    ]);
    await pumpMap(tester, repo, await fakeKeyStore());

    expect(repo.requestedBounds, isNotEmpty,
        reason: 'karttanäkymän pitää kysyä rajattua aluetta, ei koko aineistoa');
    final bounds = repo.requestedBounds.first;
    expect(bounds[0], lessThan(Config.fallbackLat));
    expect(bounds[1], greaterThan(Config.fallbackLat));
    expect(bounds[2], lessThan(Config.fallbackLon));
    expect(bounds[3], greaterThan(Config.fallbackLon));
  });

  testWidgets('markerin napautus avaa kohteen tiedot', (tester) async {
    final repo = FakeSpotRepository([
      spotAt(Config.fallbackLat, Config.fallbackLon,
          name: 'Keskustorin invapaikka', capacity: 2),
    ]);
    await pumpMap(tester, repo, await fakeKeyStore());

    expect(find.byType(SpotMarkerIcon), findsOneWidget);

    await tester.tap(find.byType(SpotMarkerIcon));
    await tester.pumpAndSettle();

    expect(find.text('Keskustorin invapaikka'), findsOneWidget);
    expect(find.text('2 invapaikkaa'), findsOneWidget);
    expect(find.text('Navigoi tähän'), findsOneWidget);
  });

  testWidgets('osoitehaun valinta siirtää kartan ja hakee uuden alueen kohteet',
      (tester) async {
    // Helsinki on kaukana oletusnäkymästä (Tampere), joten siirtymän näkee
    // haetuista rajoista.
    const helsinkiLat = 60.1699;
    const helsinkiLon = 24.9384;

    final repo = FakeSpotRepository([spotAt(helsinkiLat, helsinkiLon)]);
    await pumpMap(
      tester,
      repo,
      await fakeKeyStore(key: 'avain'),
      geocoder: fakeGeocoder(results: [
        (label: 'Rautatientori, Helsinki', lat: helsinkiLat, lon: helsinkiLon),
      ]),
    );

    final boundsBefore = repo.requestedBounds.length;

    await tester.enterText(find.byType(TextField), 'Rautatientori');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rautatientori, Helsinki'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(repo.requestedBounds.length, greaterThan(boundsBefore),
        reason: 'kartan siirron pitää laukaista uusi haku');
    final latest = repo.requestedBounds.last;
    expect(latest[0], lessThan(helsinkiLat));
    expect(latest[1], greaterThan(helsinkiLat));
    expect(latest[2], lessThan(helsinkiLon));
    expect(latest[3], greaterThan(helsinkiLon));
  });

  testWidgets('ilman API-avainta näytetään huomautus', (tester) async {
    await pumpMap(tester, FakeSpotRepository([]), await fakeKeyStore());
    expect(find.text('Taustakartta puuttuu'), findsOneWidget);
  });

  testWidgets('avaimen kanssa huomautusta ei näytetä', (tester) async {
    await pumpMap(
      tester,
      FakeSpotRepository([]),
      await fakeKeyStore(key: 'testiavain'),
    );
    expect(find.text('Taustakartta puuttuu'), findsNothing);
  });

  testWidgets('kyselyn epäonnistuminen näytetään eikä jätetä tyhjäksi kartaksi',
      (tester) async {
    // Tyhjä kartta ilman selitystä näyttää käyttäjälle samalta kuin
    // "tällä alueella ei ole invapaikkoja". Juuri tämä piilotti Androidin
    // rtree-virheen: sovellus näytti toimivan, mutta kohteita ei koskaan tullut.
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          database: FailingSpotRepository(),
          keyStore: await fakeKeyStore(key: 'avain'),
          geocoder: fakeGeocoder(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Invapaikkoja ei voitu ladata.'), findsOneWidget);
  });

  testWidgets('onnistunut haku ei näytä virheilmoitusta', (tester) async {
    await pumpMap(
      tester,
      FakeSpotRepository([spotAt(Config.fallbackLat, Config.fallbackLon)]),
      await fakeKeyStore(),
    );
    expect(find.text('Invapaikkoja ei voitu ladata.'), findsNothing);
  });

  testWidgets('hakupalkki ja selite näkyvät kartalla', (tester) async {
    await pumpMap(tester, FakeSpotRepository([]), await fakeKeyStore());
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(MapLegend), findsOneWidget);
  });
}
