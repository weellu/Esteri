import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:esteri/data/parking_spot.dart';
import 'package:esteri/ui/spot_marker.dart';

ParkingSpot spotWith(
  SpotPrecision precision, {
  String? name,
  SpotVerification verification = SpotVerification.curated,
  int confirmations = 0,
  int disputes = 0,
}) =>
    ParkingSpot(
      id: 1,
      uid: 'osm:node/1',
      source: 'osm',
      lat: 60.17,
      lon: 24.94,
      precision: precision,
      name: name,
      verification: verification,
      confirmations: confirmations,
      disputes: disputes,
    );

/// Markerin oman kehyksen koristelu. Vahvistamattomalla kohteella on lisäksi
/// kulmatunnus, joten pelkkä "ensimmäinen reunallinen" ei riitä erotteluksi
/// ilman tätä järjestysoletusta: kehys piirtyy Stackissa ennen tunnusta.
BoxDecoration markerDecoration(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.byType(DecoratedBox))
    .map((w) => w.decoration)
    .whereType<BoxDecoration>()
    .firstWhere((d) => d.border != null);

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

    test('vahvistamaton erottuu väriltään molemmista tarkkuustasoista', () {
      final reported = SpotVisuals.colorFor(
        SpotPrecision.space,
        SpotVerification.reported,
      );
      expect(reported, isNot(SpotVisuals.colorFor(SpotPrecision.space)));
      expect(reported, isNot(SpotVisuals.colorFor(SpotPrecision.area)));
    });

    test('vahvistamattoman väri ei riipu tarkkuudesta', () {
      // Ilmoituksessa kysymys ei ole sijainnin tarkkuudesta vaan siitä, onko
      // paikkaa lainkaan — tarkkuuden mukaan värjääminen sekoittaisi nämä.
      final colors = SpotPrecision.values
          .map((p) => SpotVisuals.colorFor(p, SpotVerification.reported))
          .toSet();
      expect(colors, {SpotVisuals.unverified});
    });

    test('vahvistettu kohde värjätään kuin avoin aineisto', () {
      for (final precision in SpotPrecision.values) {
        expect(
          SpotVisuals.colorFor(precision, SpotVerification.confirmed),
          SpotVisuals.colorFor(precision),
          reason: 'vahvistettua ei ole syytä esittää epävarmempana',
        );
      }
    });

    test('avoimen aineiston selite pysyy tarkkuuden selitteenä', () {
      final spot = spotWith(SpotPrecision.area);
      expect(SpotVisuals.explainSpot(spot), SpotVisuals.explain(SpotPrecision.area));
    });

    test('vahvistamattoman selite puhuu ilmoituksesta, ei alueesta', () {
      final spot = spotWith(
        SpotPrecision.area,
        verification: SpotVerification.reported,
      );
      final text = SpotVisuals.explainSpot(spot);
      expect(text, contains('vahvistanut'));
      expect(text, isNot(contains('keskipiste')),
          reason: 'alueen selite lupaisi väärää asiaa yhdestä ilmoituksesta');
    });

    test('vahvistetun selite kertoo vahvistajien määrän', () {
      final spot = spotWith(
        SpotPrecision.space,
        verification: SpotVerification.confirmed,
        confirmations: 4,
      );
      expect(SpotVisuals.explainSpot(spot), contains('4'));
    });

    test('kiistetyn selite kertoo montako ei löytänyt', () {
      final spot = spotWith(
        SpotPrecision.space,
        verification: SpotVerification.disputed,
        disputes: 4,
      );
      final text = SpotVisuals.explainSpot(spot);
      expect(text, contains('4'));
      expect(text, contains('ei löytänyt'));
    });

    test('lyhyt selite erottaa kaikki kolme alkuperää', () {
      final labels = {
        SpotVisuals.shortLabelForSpot(spotWith(SpotPrecision.space)),
        SpotVisuals.shortLabelForSpot(spotWith(SpotPrecision.space,
            verification: SpotVerification.reported)),
        SpotVisuals.shortLabelForSpot(spotWith(SpotPrecision.space,
            verification: SpotVerification.confirmed)),
      };
      expect(labels.length, 3);
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

      expect(markerDecoration(tester).color, Colors.white,
          reason: 'epätarkka kohde ei saa näyttää yhtä vahvalta kuin tarkka');
    });

    testWidgets('vahvistamaton on läpikuultava vaikka tarkkuus olisi tarkka',
        (tester) async {
      // Täytetty merkki lupaa varmuutta, jota yhden käyttäjän ilmoituksella
      // ei ole, vaikka sijainti olisi tallentunut tarkkana.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpotMarkerIcon(
              spot: spotWith(SpotPrecision.space,
                  verification: SpotVerification.reported),
            ),
          ),
        ),
      );

      expect(markerDecoration(tester).color, Colors.white);
    });

    testWidgets('kiistetty erottuu vahvistamattomasta tunnuksellaan', (
      tester,
    ) async {
      // Kysymysmerkki: emme tiedä onko paikkaa. Huutomerkki: joku kävi
      // katsomassa eikä löytänyt. Käyttäjälle ne ovat eri tieto.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpotMarkerIcon(
              spot: spotWith(
                SpotPrecision.space,
                verification: SpotVerification.disputed,
                disputes: 2,
              ),
            ),
          ),
        ),
      );

      expect(find.text('!'), findsOneWidget);
      expect(find.text('?'), findsNothing);
    });

    testWidgets('vahvistettu ei saa vahvistamattoman tunnusta', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpotMarkerIcon(
              spot: spotWith(SpotPrecision.space,
                  verification: SpotVerification.confirmed, confirmations: 3),
            ),
          ),
        ),
      );

      expect(find.text('?'), findsNothing);
    });

    testWidgets('ruudunlukija kuulee alkuperän eikä tarkkuutta', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpotMarkerIcon(
              spot: spotWith(SpotPrecision.area,
                  name: 'Tori', verification: SpotVerification.reported),
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Tori. Vahvistamaton ilmoitus'), findsOneWidget);
      // Kulmatunnus on visuaalinen toisto samasta tiedosta. Ruudunlukijalle se
      // olisi pelkkä irrallinen "?" otsikon perässä.
      expect(tester.getSemantics(find.byType(SpotMarkerIcon)).label,
          isNot(contains('?')));
      handle.dispose();
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

    testWidgets('selittää myös vahvistamattoman ilmoituksen', (tester) async {
      // Käyttäjä näkee kartalla oranssin kysymysmerkin — selitteen on
      // kerrottava mitä se tarkoittaa, muuten merkki on pelkkä häiriö.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MapLegend())),
      );

      expect(find.text('Vahvistamaton ilmoitus'), findsOneWidget);
      expect(find.text('?'), findsOneWidget);
    });
  });
}
