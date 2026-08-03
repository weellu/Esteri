import 'package:latlong2/latlong.dart';

/// Kuinka tarkasti kohteen sijainti vastaa todellista pysäköintiruutua.
///
/// Tämä ei ole tekninen yksityiskohta vaan käyttäjälle olennainen ero:
/// "invapaikka tässä" ja "tällä alueella on invapaikkoja" ovat autoilijalle
/// eri lupaus. Yli puolet aineistosta on alueen keskipisteitä.
enum SpotPrecision {
  /// Sijainti on itse pysäköintiruutu.
  space,

  /// Liikennemerkki — ruutu on merkin välittömässä läheisyydessä.
  sign,

  /// Alueen keskipiste — ruutu on jossain alueella, ei tässä pisteessä.
  area;

  static SpotPrecision parse(String raw) => switch (raw) {
    'space' => SpotPrecision.space,
    'sign' => SpotPrecision.sign,
    'area' => SpotPrecision.area,
    _ => SpotPrecision.area,
  };
}

/// Mistä kohteen olemassaolo tiedetään.
///
/// Eri asia kuin [SpotPrecision], joka kertoo vain sijainnin tarkkuuden.
/// Kunnan rekisterissä oleva paikka voi olla sijainniltaan epätarkka mutta
/// olemassaolostaan varma, ja käyttäjän ilmoittama päinvastoin.
enum SpotVerification {
  /// Avoimesta aineistosta: OSM, Digiroad tai kunnan oma rekisteri.
  curated,

  /// Yhden käyttäjän ilmoitus, jota kukaan muu ei ole vielä vahvistanut.
  reported,

  /// Useampi käyttäjä on vahvistanut paikan päällä.
  confirmed,

  /// Useampi käyttäjä ei löytänyt paikkaa, vaikka se on avoimessa
  /// aineistossa. Rekisteri ja maasto ovat eri mieltä, eikä sitä voi
  /// ratkaista ruudulta — mutta käyttäjälle se on kerrottava ennen kuin hän
  /// ajaa paikalle.
  disputed;

  /// Tuntematon arvo tulkitaan varovaisesti vahvistamattomaksi. Uudempi
  /// aineisto voi tuntea tasoja, joita tämä sovellusversio ei — silloin on
  /// parempi luvata liian vähän kuin liikaa.
  static SpotVerification parse(String? raw) => switch (raw) {
    null => SpotVerification.curated,
    'confirmed' => SpotVerification.confirmed,
    'disputed' => SpotVerification.disputed,
    _ => SpotVerification.reported,
  };

  /// Onko kohteen olemassaolo käyttäjien varassa.
  ///
  /// Kiistetty kohde ei ole: se on avoimesta aineistosta, ja käyttäjien
  /// panos on nimenomaan epäily sitä kohtaan.
  bool get isFromUsers =>
      this == SpotVerification.reported || this == SpotVerification.confirmed;

  /// Onko kohteeseen syytä suhtautua varauksella.
  bool get isUncertain =>
      this == SpotVerification.reported || this == SpotVerification.disputed;
}

class ParkingSpot {
  const ParkingSpot({
    required this.id,
    required this.uid,
    required this.source,
    required this.lat,
    required this.lon,
    required this.precision,
    this.capacity,
    this.name,
    this.address,
    this.restrictions,
    this.maxDurationH,
    this.fee,
    this.updated,
    this.verification = SpotVerification.curated,
    this.confirmations = 0,
    this.disputes = 0,
  });

  final int id;
  final String uid;
  final String source;
  final double lat;
  final double lon;
  final SpotPrecision precision;
  final int? capacity;
  final String? name;
  final String? address;
  final String? restrictions;
  final double? maxDurationH;
  final bool? fee;
  final String? updated;
  final SpotVerification verification;

  /// Montako käyttäjää on vahvistanut kohteen paikan päällä.
  final int confirmations;

  /// Montako käyttäjää on ilmoittanut, ettei kohdetta löydy.
  final int disputes;

  LatLng get position => LatLng(lat, lon);

  /// Paras saatavilla oleva otsikko. Suurimmalla osalla kohteista ei ole
  /// nimeä eikä osoitetta, joten viimeinen vaihtoehto kuvaa tarkkuutta.
  String get title {
    if (name != null && name!.isNotEmpty) return name!;
    if (address != null && address!.isNotEmpty) return address!;
    // Käyttäjän ilmoittama kohde ei ole pysäköintialue vaikka sijainti on
    // epätarkka, joten tarkkuudesta johdettu otsikko olisi sille väärä.
    if (verification.isFromUsers) return 'Käyttäjän ilmoittama invapaikka';
    return switch (precision) {
      SpotPrecision.space => 'Invapysäköintipaikka',
      SpotPrecision.sign => 'Invapysäköinnin liikennemerkki',
      SpotPrecision.area => 'Pysäköintialue, jolla invapaikkoja',
    };
  }

  factory ParkingSpot.fromRow(Map<String, Object?> row) => ParkingSpot(
    id: row['id'] as int,
    uid: row['uid'] as String,
    source: row['source'] as String,
    lat: (row['lat'] as num).toDouble(),
    lon: (row['lon'] as num).toDouble(),
    precision: SpotPrecision.parse(row['precision'] as String),
    capacity: row['capacity'] as int?,
    name: row['name'] as String?,
    address: row['address'] as String?,
    restrictions: row['restrictions'] as String?,
    maxDurationH: (row['max_duration_h'] as num?)?.toDouble(),
    fee: row['fee'] == null ? null : (row['fee'] as int) == 1,
    updated: row['updated'] as String?,
    // Sarakkeet lisättiin aineistoon skeemaversiota nostamatta, joten ne
    // voivat puuttua vanhemmasta tiedostosta kokonaan. Puuttuva sarake
    // luetaan samoin kuin tyhjä arvo.
    verification: SpotVerification.parse(row['verification'] as String?),
    confirmations: (row['confirmations'] as int?) ?? 0,
    disputes: (row['disputes'] as int?) ?? 0,
  );
}

/// Lähteiden näyttönimet ja lisenssiviittaukset.
const Map<String, String> kSourceNames = {
  'osm': 'OpenStreetMap',
  'digiroad': 'Digiroad / Väylävirasto',
  'tampere': 'Tampereen kaupunki',
  'turku': 'Turun kaupunki',
  'helsinki': 'Helsingin kaupunki',
  'users': 'Sovelluksen käyttäjät',
};
