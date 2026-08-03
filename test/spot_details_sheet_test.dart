import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:esteri/data/parking_spot.dart';
import 'package:esteri/ui/spot_details_sheet.dart';

ParkingSpot spot({
  SpotPrecision precision = SpotPrecision.space,
  int? capacity,
  bool? fee,
  double? maxDurationH,
  String? address,
  String? restrictions,
  String source = 'osm',
  String? updated,
}) =>
    ParkingSpot(
      id: 1,
      uid: '$source:1',
      source: source,
      lat: 60.17,
      lon: 24.94,
      precision: precision,
      capacity: capacity,
      address: address,
      restrictions: restrictions,
      maxDurationH: maxDurationH,
      fee: fee,
      updated: updated,
    );

Future<void> pumpSheet(WidgetTester tester, ParkingSpot value) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: SpotDetailsSheet(spot: value))),
  );
}

void main() {
  testWidgets('epätarkasta kohteesta kerrotaan että sijainti on keskipiste',
      (tester) async {
    await pumpSheet(tester, spot(precision: SpotPrecision.area));
    expect(find.textContaining('keskipiste'), findsOneWidget);
  });

  testWidgets('tarkasta kohteesta ei väitetä epävarmuutta', (tester) async {
    await pumpSheet(tester, spot(precision: SpotPrecision.space));
    expect(find.textContaining('keskipiste'), findsNothing);
    expect(find.textContaining('tässä kohdassa'), findsOneWidget);
  });

  testWidgets('paikkamäärä taivutetaan yksikössä ja monikossa', (tester) async {
    await pumpSheet(tester, spot(capacity: 1));
    expect(find.text('1 invapaikka'), findsOneWidget);

    await pumpSheet(tester, spot(capacity: 4));
    expect(find.text('4 invapaikkaa'), findsOneWidget);
  });

  testWidgets('maksuttomuus ja maksullisuus näytetään eri tavalla',
      (tester) async {
    await pumpSheet(tester, spot(fee: true));
    expect(find.text('Maksullinen'), findsOneWidget);

    await pumpSheet(tester, spot(fee: false));
    expect(find.text('Maksuton'), findsOneWidget);
  });

  testWidgets('tuntematonta maksullisuutta ei arvata', (tester) async {
    await pumpSheet(tester, spot());
    expect(find.text('Maksullinen'), findsNothing);
    expect(find.text('Maksuton'), findsNothing);
  });

  testWidgets('kesto muotoillaan tunneiksi ja minuuteiksi', (tester) async {
    await pumpSheet(tester, spot(maxDurationH: 2));
    expect(find.text('Enintään 2 h'), findsOneWidget);

    await pumpSheet(tester, spot(maxDurationH: 0.5));
    expect(find.text('Enintään 30 min'), findsOneWidget);
  });

  testWidgets('lähde nimetään ihmisluettavasti', (tester) async {
    await pumpSheet(tester, spot(source: 'digiroad'));
    expect(find.textContaining('Digiroad / Väylävirasto'), findsOneWidget);
  });

  testWidgets('varoitus validoimattomasta datasta näkyy aina', (tester) async {
    // Yhtäkään lähdettä ei ole varmistettu maastossa, joten tätä ei saa
    // jättää pois millään kohteella.
    for (final precision in SpotPrecision.values) {
      await pumpSheet(tester, spot(precision: precision));
      expect(find.textContaining('Noudata aina paikan päällä'), findsOneWidget,
          reason: 'puuttuu tarkkuudella $precision');
    }
  });

  testWidgets('navigointipainike on aina tarjolla', (tester) async {
    await pumpSheet(tester, spot());
    expect(find.text('Navigoi tähän'), findsOneWidget);
  });

  testWidgets('puuttuvia kenttiä ei näytetä tyhjinä riveinä', (tester) async {
    await pumpSheet(tester, spot());
    expect(find.byIcon(Icons.home_outlined), findsNothing);
    expect(find.byIcon(Icons.local_parking_outlined), findsNothing);
    expect(find.byIcon(Icons.schedule_outlined), findsNothing);
  });

  testWidgets('osoite ja rajoitukset näkyvät kun ne tunnetaan', (tester) async {
    await pumpSheet(
      tester,
      spot(address: 'Hämeenkatu 1', restrictions: 'kiekkopysäköinti; ark 8-18'),
    );
    expect(find.text('Hämeenkatu 1'), findsOneWidget);
    expect(find.text('kiekkopysäköinti; ark 8-18'), findsOneWidget);
  });
}
