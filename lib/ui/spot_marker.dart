import 'package:flutter/material.dart';

import '../data/parking_spot.dart';

/// Markerien ulkoasu tarkkuuden mukaan.
///
/// Kolme tarkkuustasoa erotetaan sekä muodolla että täytöllä — ei pelkällä
/// värillä. Sovelluksen käyttäjäkunta huomioiden pelkkään väriin nojaaminen
/// olisi huono valinta, ja muoto erottuu myös pienessä koossa.
class SpotVisuals {
  const SpotVisuals._();

  static const Color exact = Color(0xFF0B5FA5);
  static const Color approximate = Color(0xFF5B7A93);

  static Color colorFor(SpotPrecision precision) => switch (precision) {
        SpotPrecision.space => exact,
        SpotPrecision.sign => exact,
        SpotPrecision.area => approximate,
      };

  /// Lyhyt selitys siitä, mitä sijainti tarkoittaa.
  static String explain(SpotPrecision precision) => switch (precision) {
        SpotPrecision.space => 'Merkitty invapysäköintipaikka tässä kohdassa.',
        SpotPrecision.sign =>
          'Invapysäköinnin liikennemerkki. Paikka on merkin välittömässä läheisyydessä.',
        SpotPrecision.area =>
          'Pysäköintialue, jolla on invapaikkoja. Sijainti on alueen keskipiste — '
              'paikan tarkkaa kohtaa alueella ei tiedetä.',
      };

  static String shortLabel(SpotPrecision precision) => switch (precision) {
        SpotPrecision.space => 'Tarkka paikka',
        SpotPrecision.sign => 'Liikennemerkki',
        SpotPrecision.area => 'Alueella',
      };
}

class SpotMarkerIcon extends StatelessWidget {
  const SpotMarkerIcon({super.key, required this.spot});

  final ParkingSpot spot;

  @override
  Widget build(BuildContext context) {
    final color = SpotVisuals.colorFor(spot.precision);
    final isArea = spot.precision == SpotPrecision.area;
    final isSign = spot.precision == SpotPrecision.sign;

    return Semantics(
      label: '${spot.title}. ${SpotVisuals.shortLabel(spot.precision)}',
      button: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // Alue esitetään läpikuultavana ja liikennemerkki neliönä, jotta
          // ero tarkkaan paikkaan näkyy ilman värin erottamista.
          color: isArea ? Colors.white : color,
          shape: isSign ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: isSign ? BorderRadius.circular(6) : null,
          border: Border.all(color: color, width: isArea ? 3 : 2),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Center(
          child: Icon(
            Icons.accessible,
            size: 18,
            color: isArea ? color : Colors.white,
          ),
        ),
      ),
    );
  }
}

class ClusterIcon extends StatelessWidget {
  const ClusterIcon({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$count invapaikkaa tällä alueella',
      button: true,
      // Klusteri luetaan yhtenä elementtinä. Ilman tätä ruudunlukija
      // ilmoittaisi erikseen pelkän luvun, joka ei kerro mitään.
      container: true,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: SpotVisuals.exact,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: Center(
          child: Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

/// Selite, joka kertoo mitä markerien muodot tarkoittavat.
class MapLegend extends StatelessWidget {
  const MapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row(context, SpotPrecision.space, 'Tarkka paikka'),
            const SizedBox(height: 6),
            _row(context, SpotPrecision.sign, 'Liikennemerkki'),
            const SizedBox(height: 6),
            _row(context, SpotPrecision.area, 'Alueella invapaikkoja'),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, SpotPrecision precision, String label) {
    final color = SpotVisuals.colorFor(precision);
    final isArea = precision == SpotPrecision.area;
    final isSign = precision == SpotPrecision.sign;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: isArea ? Colors.white : color,
            shape: isSign ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: isSign ? BorderRadius.circular(4) : null,
            border: Border.all(color: color, width: isArea ? 2.5 : 1.5),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
