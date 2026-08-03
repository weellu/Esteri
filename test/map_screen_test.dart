import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:esteri/config.dart';
import 'package:esteri/services/geocoder.dart';
import 'package:esteri/services/location_service.dart';
import 'package:esteri/services/map_key_store.dart';
import 'package:esteri/ui/map_screen.dart';
import 'package:esteri/ui/spot_marker.dart';

import 'fakes.dart';

Future<void> pumpMap(
  WidgetTester tester,
  FakeSpotRepository repo,
  MapKeyStore store, {
  MmlGeocoder? geocoder,
  LocationService? locationService,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MapScreen(
        database: repo,
        keyStore: store,
        geocoder: geocoder ?? fakeGeocoder(),
        locationService: locationService,
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

    expect(
      repo.requestedBounds,
      isNotEmpty,
      reason: 'karttanäkymän pitää kysyä rajattua aluetta, ei koko aineistoa',
    );
    final bounds = repo.requestedBounds.first;
    expect(bounds[0], lessThan(Config.fallbackLat));
    expect(bounds[1], greaterThan(Config.fallbackLat));
    expect(bounds[2], lessThan(Config.fallbackLon));
    expect(bounds[3], greaterThan(Config.fallbackLon));
  });

  testWidgets('markerin napautus avaa kohteen tiedot', (tester) async {
    final repo = FakeSpotRepository([
      spotAt(
        Config.fallbackLat,
        Config.fallbackLon,
        name: 'Keskustorin invapaikka',
        capacity: 2,
      ),
    ]);
    await pumpMap(tester, repo, await fakeKeyStore());

    expect(find.byType(SpotMarkerIcon), findsOneWidget);

    await tester.tap(find.byType(SpotMarkerIcon));
    await tester.pumpAndSettle();

    expect(find.text('Keskustorin invapaikka'), findsOneWidget);
    expect(find.text('2 invapaikkaa'), findsOneWidget);
    expect(find.text('Navigoi tähän'), findsOneWidget);
  });

  testWidgets(
    'osoitehaun valinta siirtää kartan ja hakee uuden alueen kohteet',
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
        geocoder: fakeGeocoder(
          results: [
            (
              label: 'Rautatientori, Helsinki',
              lat: helsinkiLat,
              lon: helsinkiLon,
            ),
          ],
        ),
      );

      final boundsBefore = repo.requestedBounds.length;

      await tester.enterText(find.byType(TextField), 'Rautatientori');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rautatientori, Helsinki'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(
        repo.requestedBounds.length,
        greaterThan(boundsBefore),
        reason: 'kartan siirron pitää laukaista uusi haku',
      );
      final latest = repo.requestedBounds.last;
      expect(latest[0], lessThan(helsinkiLat));
      expect(latest[1], greaterThan(helsinkiLat));
      expect(latest[2], lessThan(helsinkiLon));
      expect(latest[3], greaterThan(helsinkiLon));
    },
  );

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

  testWidgets('kyselyn epäonnistuminen näytetään eikä jätetä tyhjäksi kartaksi', (
    tester,
  ) async {
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

  group('sijainnin seuranta', () {
    testWidgets('painike keskittää kartan ensimmäiseen sijaintiin', (
      tester,
    ) async {
      final repo = FakeSpotRepository([]);
      final location = FakeLocationService(first: helsinki);
      await pumpMap(
        tester,
        repo,
        await fakeKeyStore(),
        locationService: location,
      );

      await tapTracking(tester);

      expect(
        location.subscriptions,
        1,
        reason: 'paikannuksen pitää käynnistyä',
      );
      expect(userDot(tester), helsinki);
      expect(
        boundsContain(repo.requestedBounds.last, helsinki),
        isTrue,
        reason: 'kartan pitää siirtyä sijaintiin',
      );
    });

    testWidgets('seuranta siirtää kartan uuden sijainnin mukana', (
      tester,
    ) async {
      final repo = FakeSpotRepository([]);
      final location = FakeLocationService(first: helsinki);
      await pumpMap(
        tester,
        repo,
        await fakeKeyStore(),
        locationService: location,
      );
      await tapTracking(tester);

      location.emit(oulu);
      await settle(tester);

      expect(userDot(tester), oulu);
      expect(
        boundsContain(repo.requestedBounds.last, oulu),
        isTrue,
        reason: 'seurantatilassa kartan pitää seurata liikkuvaa käyttäjää',
      );
    });

    testWidgets(
      'kartan raahaus irrottaa seurannan mutta jättää pisteen eläväksi',
      (tester) async {
        // Jos kartta nykäisisi takaisin käyttäjän oman siirron jälkeen, karttaa
        // ei voisi selata liikkeellä ollessa — juuri silloin kun sitä tarvitaan.
        final repo = FakeSpotRepository([]);
        final location = FakeLocationService(first: helsinki);
        await pumpMap(
          tester,
          repo,
          await fakeKeyStore(),
          locationService: location,
        );
        await tapTracking(tester);

        await tester.drag(find.byType(FlutterMap), const Offset(-200, -200));
        await settle(tester);

        location.emit(oulu);
        await settle(tester);

        expect(userDot(tester), oulu, reason: 'paikannuksen pitää jatkua');
        expect(
          boundsContain(repo.requestedBounds.last, oulu),
          isFalse,
          reason: 'raahauksen jälkeen kartta ei saa siirtyä itsestään',
        );
        expect(find.byTooltip('Keskitä kartta sijaintiin'), findsOneWidget);
      },
    );

    testWidgets('painikkeen painallus seurantatilassa lopettaa paikannuksen', (
      tester,
    ) async {
      final location = FakeLocationService(first: helsinki);
      await pumpMap(
        tester,
        FakeSpotRepository([]),
        await fakeKeyStore(),
        locationService: location,
      );
      await tapTracking(tester);
      await tapTracking(tester);

      expect(
        location.cancellations,
        1,
        reason: 'GPS on sammutettava, ei vain piilotettava kartalta',
      );
      expect(find.byType(CircleLayer), findsNothing);
      expect(find.byTooltip('Näytä oma sijainti'), findsOneWidget);
    });

    testWidgets('evätty lupa kerrotaan eikä paikannusta aloiteta', (
      tester,
    ) async {
      final location = FakeLocationService(
        denial: LocationDenial.permissionDeniedForever,
      );
      await pumpMap(
        tester,
        FakeSpotRepository([]),
        await fakeKeyStore(),
        locationService: location,
      );

      await tapTracking(tester);

      expect(location.subscriptions, 0);
      expect(
        find.text(
          'Sijaintilupa on estetty. Salli sijainti laitteen asetuksista.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('sijaintivirta katkeaa: seuranta pysähtyy ja siitä kerrotaan', (
      tester,
    ) async {
      final location = FakeLocationService(first: helsinki);
      await pumpMap(
        tester,
        FakeSpotRepository([]),
        await fakeKeyStore(),
        locationService: location,
      );
      await tapTracking(tester);

      location.fail(Exception('paikannin sammui'));
      await settle(tester);

      expect(find.text('Sijainnin seuranta keskeytyi.'), findsOneWidget);
      expect(find.byTooltip('Näytä oma sijainti'), findsOneWidget);
    });

    testWidgets('näkymän sulkeminen peruuttaa paikannuksen', (tester) async {
      // Ilman tätä GPS jäisi päälle näkymän tuhouduttua ja söisi akkua.
      final location = FakeLocationService(first: helsinki);
      await pumpMap(
        tester,
        FakeSpotRepository([]),
        await fakeKeyStore(),
        locationService: location,
      );
      await tapTracking(tester);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      expect(location.cancellations, 1);
    });
  });
}

const helsinki = LatLng(60.1699, 24.9384);
const oulu = LatLng(65.0121, 25.4651);

Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

Future<void> tapTracking(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await settle(tester);
}

/// Kartalla näkyvän sijaintipisteen paikka, tai null jos pistettä ei ole.
LatLng? userDot(WidgetTester tester) {
  final layers = tester.widgetList<CircleLayer>(find.byType(CircleLayer));
  if (layers.isEmpty) return null;
  return layers.first.circles.first.point;
}

bool boundsContain(List<double> bounds, LatLng point) =>
    bounds[0] < point.latitude &&
    bounds[1] > point.latitude &&
    bounds[2] < point.longitude &&
    bounds[3] > point.longitude;
