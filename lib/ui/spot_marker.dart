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

  /// Käyttäjän ilmoittama, vahvistamaton kohde. Eri sävy kuin avoimen
  /// aineiston kohteilla, mutta ero ei jää värin varaan: merkissä on lisäksi
  /// oma tunnus kulmassa.
  static const Color unverified = Color(0xFF8A5000);

  static Color colorFor(
    SpotPrecision precision, [
    SpotVerification verification = SpotVerification.curated,
  ]) {
    if (verification == SpotVerification.reported) return unverified;
    return switch (precision) {
      SpotPrecision.space => exact,
      SpotPrecision.sign => exact,
      SpotPrecision.area => approximate,
    };
  }

  /// Lyhyt selitys siitä, mitä sijainti tarkoittaa.
  static String explain(SpotPrecision precision) => switch (precision) {
    SpotPrecision.space => 'Merkitty invapysäköintipaikka tässä kohdassa.',
    SpotPrecision.sign =>
      'Invapysäköinnin liikennemerkki. Paikka on merkin välittömässä läheisyydessä.',
    SpotPrecision.area =>
      'Pysäköintialue, jolla on invapaikkoja. Sijainti on alueen keskipiste — '
          'paikan tarkkaa kohtaa alueella ei tiedetä.',
  };

  /// Selitys, joka ottaa huomioon myös sen, mistä tieto on peräisin.
  ///
  /// Käyttäjän ilmoittaman kohteen kohdalla tarkkuutta kuvaava teksti olisi
  /// harhaanjohtava: kysymys ei ole siitä, missä kohtaa aluetta paikka on,
  /// vaan siitä, onko paikkaa lainkaan.
  static String explainSpot(ParkingSpot spot) => switch (spot.verification) {
    SpotVerification.curated => explain(spot.precision),
    SpotVerification.reported =>
      'Käyttäjän ilmoittama paikka, jota kukaan muu ei ole vielä '
          'vahvistanut. Sijainti on likimääräinen.',
    SpotVerification.confirmed =>
      'Käyttäjien ilmoittama paikka, jonka ${spot.confirmations} eri '
          'käyttäjää on vahvistanut paikan päällä.',
  };

  static String shortLabel(SpotPrecision precision) => switch (precision) {
    SpotPrecision.space => 'Tarkka paikka',
    SpotPrecision.sign => 'Liikennemerkki',
    SpotPrecision.area => 'Alueella',
  };

  static String shortLabelForSpot(ParkingSpot spot) =>
      switch (spot.verification) {
        SpotVerification.curated => shortLabel(spot.precision),
        SpotVerification.reported => 'Vahvistamaton ilmoitus',
        SpotVerification.confirmed => 'Käyttäjien vahvistama',
      };
}

class SpotMarkerIcon extends StatelessWidget {
  const SpotMarkerIcon({super.key, required this.spot});

  final ParkingSpot spot;

  @override
  Widget build(BuildContext context) {
    final color = SpotVisuals.colorFor(spot.precision, spot.verification);
    final isReported = spot.verification == SpotVerification.reported;
    // Vahvistamaton kohde piirretään aina läpikuultavana riippumatta siitä,
    // mitä sen precision sanoo — täytetty merkki lupaa varmuutta, jota ei ole.
    final isHollow = isReported || spot.precision == SpotPrecision.area;
    final isSign = spot.precision == SpotPrecision.sign && !isReported;

    return Semantics(
      label: '${spot.title}. ${SpotVisuals.shortLabelForSpot(spot)}',
      button: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              // Alue esitetään läpikuultavana ja liikennemerkki neliönä, jotta
              // ero tarkkaan paikkaan näkyy ilman värin erottamista.
              color: isHollow ? Colors.white : color,
              shape: isSign ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: isSign ? BorderRadius.circular(6) : null,
              border: Border.all(color: color, width: isHollow ? 3 : 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                Icons.accessible,
                size: 18,
                color: isHollow ? color : Colors.white,
              ),
            ),
          ),
          // Vahvistamattomuus merkitään omalla tunnuksella eikä pelkällä
          // värillä. Sovelluksen käyttäjäkunta huomioiden pelkkä sävyero
          // olisi tässä huono valinta.
          if (isReported)
            Positioned(
              top: -3,
              right: -3,
              // Tunnus toistaa visuaalisesti sen, minkä Semantics-otsikko jo
              // kertoo. Ilman poissulkemista ruudunlukija lukisi perään
              // irrallisen "?":n.
              child: ExcludeSemantics(child: _UnverifiedBadge(color: color)),
            ),
        ],
      ),
    );
  }
}

class _UnverifiedBadge extends StatelessWidget {
  const _UnverifiedBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: const Center(
        child: Text(
          '?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 9,
            height: 1.1,
            fontWeight: FontWeight.bold,
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
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
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
            const SizedBox(height: 6),
            _row(
              context,
              SpotPrecision.area,
              'Vahvistamaton ilmoitus',
              verification: SpotVerification.reported,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    SpotPrecision precision,
    String label, {
    SpotVerification verification = SpotVerification.curated,
  }) {
    final color = SpotVisuals.colorFor(precision, verification);
    final isReported = verification == SpotVerification.reported;
    final isHollow = isReported || precision == SpotPrecision.area;
    final isSign = precision == SpotPrecision.sign && !isReported;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: isHollow ? Colors.white : color,
            shape: isSign ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: isSign ? BorderRadius.circular(4) : null,
            border: Border.all(color: color, width: isHollow ? 2.5 : 1.5),
          ),
          child: isReported
              ? Center(
                  // Selitteen tekstisarake kertoo saman asian sanoina.
                  child: ExcludeSemantics(
                    child: Text(
                      '?',
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        height: 1.1,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
