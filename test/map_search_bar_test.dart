import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leparkki/data/parking_spot.dart';
import 'package:leparkki/services/geocoder.dart';
import 'package:leparkki/ui/map_search_bar.dart';

import 'fakes.dart';

Future<void> pumpSearchBar(
  WidgetTester tester, {
  required FakeSpotRepository repository,
  required MmlGeocoder geocoder,
  String apiKey = 'avain',
  ValueChanged<GeocodeResult>? onPlace,
  ValueChanged<ParkingSpot>? onSpot,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MapSearchBar(
          repository: repository,
          geocoder: geocoder,
          apiKey: apiKey,
          onPlaceSelected: onPlace ?? (_) {},
          onSpotSelected: onSpot ?? (_) {},
        ),
      ),
    ),
  );
}

/// Kirjoita hakuun ja odota viive + asynkroniset haut.
Future<void> typeQuery(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('osoitehaun tulokset näytetään omana ryhmänään', (tester) async {
    await pumpSearchBar(
      tester,
      repository: FakeSpotRepository([]),
      geocoder: fakeGeocoder(results: [
        (label: 'Hämeenkatu 1, Tampere', lat: 61.4978, lon: 23.7610),
      ]),
    );

    await typeQuery(tester, 'Hämeenkatu');

    expect(find.text('Osoitteet ja paikat'), findsOneWidget);
    expect(find.text('Hämeenkatu 1, Tampere'), findsOneWidget);
  });

  testWidgets('paikan valinta välitetään kartalle', (tester) async {
    GeocodeResult? selected;
    await pumpSearchBar(
      tester,
      repository: FakeSpotRepository([]),
      geocoder: fakeGeocoder(results: [
        (label: 'Keskustori, Tampere', lat: 61.4980, lon: 23.7600),
      ]),
      onPlace: (place) => selected = place,
    );

    await typeQuery(tester, 'Keskustori');
    await tester.tap(find.text('Keskustori, Tampere'));
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.lat, closeTo(61.4980, 1e-6));
    expect(selected!.lon, closeTo(23.7600, 1e-6));
  });

  testWidgets('aineiston omat kohteet näkyvät erillisenä ryhmänä',
      (tester) async {
    await pumpSearchBar(
      tester,
      repository: FakeSpotRepository(
        [],
        searchResults: [
          spotAt(61.4978, 23.7610, name: 'Keskustorin invapaikka'),
        ],
      ),
      geocoder: fakeGeocoder(),
    );

    await typeQuery(tester, 'Keskustori');

    expect(find.text('Invapaikat'), findsOneWidget);
    expect(find.text('Keskustorin invapaikka'), findsOneWidget);
  });

  testWidgets('ilman avainta paikallinen haku toimii silti', (tester) async {
    // Osoitehaku vaatii avaimen, mutta aineiston oma haku ei — käyttäjä ei
    // saa jäädä täysin ilman hakua vain koska avain puuttuu.
    await pumpSearchBar(
      tester,
      apiKey: '',
      repository: FakeSpotRepository(
        [],
        searchResults: [spotAt(61.4978, 23.7610, name: 'Hämeenkadun invapaikka')],
      ),
      geocoder: fakeGeocoder(),
    );

    await typeQuery(tester, 'Hämeenkatu');

    expect(find.text('Hämeenkadun invapaikka'), findsOneWidget);
    expect(find.textContaining('API-avaimen'), findsOneWidget);
  });

  testWidgets('kelpaamaton avain kerrotaan käyttäjälle', (tester) async {
    await pumpSearchBar(
      tester,
      repository: FakeSpotRepository([]),
      geocoder: fakeGeocoder(status: 401),
    );

    await typeQuery(tester, 'Hämeenkatu');

    expect(find.textContaining('ei kelpaa'), findsOneWidget);
  });

  testWidgets('tyhjä tulos kerrotaan selvästi', (tester) async {
    await pumpSearchBar(
      tester,
      repository: FakeSpotRepository([]),
      geocoder: fakeGeocoder(),
    );

    await typeQuery(tester, 'zzzzzz');

    expect(find.text('Ei hakutuloksia.'), findsOneWidget);
  });

  testWidgets('haku ei lähde jokaisesta näppäimestä', (tester) async {
    final repository = FakeSpotRepository([]);
    await pumpSearchBar(
      tester,
      repository: repository,
      geocoder: fakeGeocoder(),
    );

    // Kolme peräkkäistä muutosta viiveen sisällä -> vain viimeinen haetaan.
    await tester.enterText(find.byType(TextField), 'H');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'Hä');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'Häme');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(repository.searchQueries, ['Häme']);
  });

  testWidgets('tyhjennys poistaa tulokset', (tester) async {
    await pumpSearchBar(
      tester,
      repository: FakeSpotRepository([]),
      geocoder: fakeGeocoder(results: [
        (label: 'Hämeenkatu 1, Tampere', lat: 61.4978, lon: 23.7610),
      ]),
    );

    await typeQuery(tester, 'Hämeenkatu');
    expect(find.text('Hämeenkatu 1, Tampere'), findsOneWidget);

    await tester.tap(find.byTooltip('Tyhjennä haku'));
    await tester.pumpAndSettle();

    expect(find.text('Hämeenkatu 1, Tampere'), findsNothing);
  });

  testWidgets('tyhjä hakukenttä ei tee hakua', (tester) async {
    final repository = FakeSpotRepository([]);
    await pumpSearchBar(
      tester,
      repository: repository,
      geocoder: fakeGeocoder(),
    );

    await typeQuery(tester, '   ');

    expect(repository.searchQueries, isEmpty);
  });
}
