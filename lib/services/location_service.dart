/// Laitteen sijainti karttanäkymälle.
///
/// Oma rajapinta natiivin paikannusliitännäisen edessä, jotta seurannan
/// logiikan voi testata ilman laitetta — samasta syystä kuin karttanäkymä
/// riippuu `SpotRepository`sta eikä suoraan SQLitestä.
///
/// Vain etualan seuranta: `NSLocationWhenInUseUsageDescription` ja
/// `ACCESS_FINE_LOCATION` riittävät, taustalupia ei pyydetä.
library;

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Miksi sijaintia ei saada. Syyt erotellaan, koska käyttäjän korjausliike on
/// eri: palvelut kytketään päälle laitteen asetuksista, lupa myönnetään
/// sovellukselle.
enum LocationDenial {
  serviceDisabled,
  permissionDenied,

  /// Käyttäjä on estänyt luvan pysyvästi — uutta kyselyä ei enää näytetä,
  /// joten hänet on ohjattava laitteen asetuksiin.
  permissionDeniedForever,
}

abstract class LocationService {
  /// Varmistaa sijaintipalvelut ja luvan. Palauttaa `null`, kun seurannan voi
  /// aloittaa, muussa tapauksessa esteen syyn.
  Future<LocationDenial?> ensureAvailable();

  /// Yksittäinen sijainti seurannan aloitushetkeen.
  Future<LatLng> current();

  /// Jatkuvat sijaintipäivitykset. Seuranta päättyy, kun tilaus peruutetaan.
  Stream<LatLng> positions();
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  /// Viiden metrin suodatin riittää pysäköintipaikan etsimiseen. Ilman
  /// suodatinta paikallaan seisova laite tuottaisi päivitysvirran pelkästä
  /// mittauksen heittelystä ja kartta nykisi jatkuvasti.
  static const LocationSettings _settings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 5,
  );

  @override
  Future<LocationDenial?> ensureAvailable() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationDenial.serviceDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return switch (permission) {
      LocationPermission.denied => LocationDenial.permissionDenied,
      LocationPermission.deniedForever =>
        LocationDenial.permissionDeniedForever,
      _ => null,
    };
  }

  @override
  Future<LatLng> current() async {
    final position = await Geolocator.getCurrentPosition();
    return LatLng(position.latitude, position.longitude);
  }

  @override
  Stream<LatLng> positions() => Geolocator.getPositionStream(
    locationSettings: _settings,
  ).map((position) => LatLng(position.latitude, position.longitude));
}
