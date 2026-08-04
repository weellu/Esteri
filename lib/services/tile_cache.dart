import 'dart:io';

import 'package:http_cache_core/http_cache_core.dart';
import 'package:http_cache_file_store/http_cache_file_store.dart';
import 'package:path_provider/path_provider.dart';

/// Karttatiilien levyvälimuisti.
///
/// Ilman tätä `flutter_map`in oletusprovider pitää tiiliä vain muistissa,
/// jolloin jokainen kylmä käynnistys lataa saman kuvan uudelleen. Käyttäjät
/// katsovat toistuvasti samoja paikkoja — kotia, työpaikkaa, kauppaa — joten
/// sama tiili haettiin verkosta yhä uudelleen.
///
/// Merkitys on kolminkertainen: sovellus on nopeampi, se toimii heikolla
/// yhteydellä, ja karttapalvelun kiintiö riittää moninkertaiselle
/// käyttäjämäärälle. Viimeinen ratkaisee, paljonko taustakartta maksaa.
class TileCache {
  const TileCache._();

  /// Kuinka kauan tiili kelpaa ilman uudelleentarkistusta.
  ///
  /// Taustakartta muuttuu hitaasti: uusi kaava tai rakennus näkyy aineistossa
  /// vasta kuukausien päästä. Kuukausi on siis lyhyt suhteessa siihen, kuinka
  /// nopeasti kuva vanhenee, mutta riittävä pitämään välimuistin ajan tasalla
  /// ilman että käyttäjän tarvitsee tehdä mitään.
  static const Duration maxStale = Duration(days: 30);

  /// Väliaikaishakemisto on oikea paikka tälle, ei dokumenttihakemisto.
  ///
  /// Tiilet ovat aina uudelleen haettavissa, joten käyttöjärjestelmä saa
  /// poistaa ne levytilan loppuessa. Samasta syystä ne jäävät pois
  /// varmuuskopioista: iCloudiin ei kuulu satoja megatavuja karttakuvaa,
  /// jonka saa verkosta takaisin.
  ///
  /// Tämä on myös ainoa koko rajoite. `dio_cache_interceptor` ei tarjoa
  /// kokokattoa, joten välimuistin siivous jää käyttöjärjestelmän ja
  /// [maxStale]:n varaan.
  static Future<CacheStore?> open() async {
    try {
      final directory = await getTemporaryDirectory();
      return FileCacheStore(
        '${directory.path}${Platform.pathSeparator}kartta_tiilet',
      );
    } catch (_) {
      // Välimuisti on nopeutus, ei ehto kartan toiminnalle. Jos hakemistoa ei
      // saada auki, kartta hakee tiilet verkosta kuten ennenkin.
      return null;
    }
  }
}
