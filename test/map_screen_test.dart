import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leparkki/config.dart';
import 'package:leparkki/services/map_key_store.dart';
import 'package:leparkki/ui/map_screen.dart';
import 'package:leparkki/ui/spot_marker.dart';

import 'fakes.dart';

Future<void> pumpMap(
  WidgetTester tester,
  FakeSpotRepository repo,
  MapKeyStore store,
) async {
  await tester.pumpWidget(
    MaterialApp(home: MapScreen(database: repo, keyStore: store)),
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

  testWidgets('selite näkyy kartalla', (tester) async {
    await pumpMap(tester, FakeSpotRepository([]), await fakeKeyStore());
    expect(find.byType(MapLegend), findsOneWidget);
  });
}
