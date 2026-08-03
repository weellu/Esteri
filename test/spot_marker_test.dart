import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:esteri/data/parking_spot.dart';
import 'package:esteri/ui/spot_marker.dart';

ParkingSpot spotWith(SpotPrecision precision, {String? name}) => ParkingSpot(
      id: 1,
      uid: 'osm:node/1',
      source: 'osm',
      lat: 60.17,
      lon: 24.94,
      precision: precision,
      name: name,
    );

void main() {
  group('SpotVisuals', () {
    test('alue erottuu värillä tarkoista kohteista', () {
      expect(SpotVisuals.colorFor(SpotPrecision.area),
          isNot(SpotVisuals.colorFor(SpotPrecision.space)));
    });

    test('jokaisella tarkkuudella on oma selite', () {
      final texts = SpotPrecision.values.map(SpotVisuals.explain).toSet();
      expect(texts.length, SpotPrecision.values.length);
    });

    test('alueen selite kertoo ettei tarkkaa kohtaa tiedetä', () {
      expect(SpotVisuals.explain(SpotPrecision.area), contains('keskipiste'));
    });
  });

  group('SpotMarkerIcon', () {
    testWidgets('kertoo ruudunlukijalle otsikon ja tarkkuuden', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpotMarkerIcon(spot: spotWith(SpotPrecision.area, name: 'Tori')),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Tori. Alueella'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('liikennemerkki piirretään neliönä, tarkka paikka ympyränä',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SpotMarkerIcon(spot: spotWith(SpotPrecision.sign)),
                SpotMarkerIcon(spot: spotWith(SpotPrecision.space)),
              ],
            ),
          ),
        ),
      );

      final decorations = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((w) => w.decoration)
          .whereType<BoxDecoration>()
          .toList();

      expect(decorations.any((d) => d.shape == BoxShape.rectangle), isTrue,
          reason: 'liikennemerkin pitää erottua muodolla, ei vain värillä');
      expect(decorations.any((d) => d.shape == BoxShape.circle), isTrue);
    });

    testWidgets('alue piirretään läpikuultavana täytöllä', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SpotMarkerIcon(spot: spotWith(SpotPrecision.area))),
        ),
      );

      final decoration = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((w) => w.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.border != null);

      expect(decoration.color, Colors.white,
          reason: 'epätarkka kohde ei saa näyttää yhtä vahvalta kuin tarkka');
    });
  });

  group('ClusterIcon', () {
    testWidgets('näyttää lukumäärän ja kuvailee sen ruudunlukijalle',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ClusterIcon(count: 12))),
      );

      expect(find.text('12'), findsOneWidget);
      expect(find.bySemanticsLabel('12 invapaikkaa tällä alueella'), findsOneWidget);
      handle.dispose();
    });
  });

  group('MapLegend', () {
    testWidgets('selittää kaikki kolme tarkkuustasoa', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MapLegend())),
      );

      expect(find.text('Tarkka paikka'), findsOneWidget);
      expect(find.text('Liikennemerkki'), findsOneWidget);
      expect(find.text('Alueella invapaikkoja'), findsOneWidget);
    });
  });
}
