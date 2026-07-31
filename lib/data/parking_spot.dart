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

  LatLng get position => LatLng(lat, lon);

  /// Paras saatavilla oleva otsikko. Suurimmalla osalla kohteista ei ole
  /// nimeä eikä osoitetta, joten viimeinen vaihtoehto kuvaa tarkkuutta.
  String get title {
    if (name != null && name!.isNotEmpty) return name!;
    if (address != null && address!.isNotEmpty) return address!;
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
      );
}

/// Lähteiden näyttönimet ja lisenssiviittaukset.
const Map<String, String> kSourceNames = {
  'osm': 'OpenStreetMap',
  'digiroad': 'Digiroad / Väylävirasto',
  'tampere': 'Tampereen kaupunki',
  'turku': 'Turun kaupunki',
  'helsinki': 'Helsingin kaupunki',
};
