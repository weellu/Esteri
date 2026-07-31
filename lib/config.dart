/// Sovelluksen asetukset.
///
/// Karttatiilet tulevat Maanmittauslaitoksen maksuttomasta
/// karttakuvapalvelusta, joka vaatii API-avaimen. Avain luodaan MML:n
/// OmaTili-palvelussa eikä se vaadi laskutustiliä tai luottokorttia.
///
/// Avain annetaan sovelluksen asetuksissa ja tallennetaan laitteelle.
/// Vaihtoehtoisesti sen voi antaa käännösaikana kehitystä varten:
///
///     flutter run --dart-define=MML_API_KEY=<avain>
///
/// Käännösaikainen arvo toimii oletuksena, jonka käyttäjä voi korvata.
library;

class Config {
  const Config._();

  /// Kehityskäyttöön tarkoitettu oletusavain. Tyhjä, ellei annettu.
  static const String defaultMmlApiKey = String.fromEnvironment('MML_API_KEY');

  /// MML:n karttakuvapalvelun RESTful WMTS -osoite.
  ///
  /// Huom: WMTS:n polkujärjestys on {TileMatrix}/{TileRow}/{TileCol} eli
  /// z/y/x — ei tavanomainen z/x/y. Väärä järjestys tuottaa kartan, joka
  /// näyttää lataavan mutta esittää väärää aluetta.
  static String mmlTileUrl(String apiKey) =>
      'https://avoin-karttakuva.maanmittauslaitos.fi/avoin/wmts/1.0.0'
      '/taustakartta/default/WGS84_Pseudo-Mercator/{z}/{y}/{x}.png'
      '?api-key=$apiKey';

  /// Yksittäinen tiili avaimen kelpoisuuden testaamiseen (Tampereen seutu).
  static String mmlProbeTileUrl(String apiKey) =>
      'https://avoin-karttakuva.maanmittauslaitos.fi/avoin/wmts/1.0.0'
      '/taustakartta/default/WGS84_Pseudo-Mercator/6/19/37.png'
      '?api-key=$apiKey';

  static const String mmlKeyInstructionsUrl =
      'https://www.maanmittauslaitos.fi/rajapinnat/api-avaimen-ohje';

  /// Tunniste tiilipyynnöissä. OSM:n omaa tiilipalvelinta ei käytetä
  /// lainkaan, koska sen käyttöehdot eivät salli sovellusjakelua.
  static const String userAgentPackageName = 'fi.leparkki.leparkki';

  /// Aineiston versio. Nosta tätä, kun assets/data/invapaikat.sqlite
  /// päivitetään — muuten sovellus jättää vanhan kopion käyttöön.
  static const String bundledDataVersion = '2026-07-31T10:52:06+00:00';

  static const String assetDatabasePath = 'assets/data/invapaikat.sqlite';

  /// Julkaistu aineisto. Pipeline ajetaan viikoittain GitHub Actionsissa ja
  /// tulos julkaistaan Pagesiin, joten datapäivitys ei vaadi kauppakierrosta.
  static const String dataBaseUrl = 'https://weellu.github.io/LEParkki';
  static const String dataManifestUrl = '$dataBaseUrl/manifest.json';
  static const String dataSqliteUrl = '$dataBaseUrl/invapaikat.sqlite';

  /// Skeemaversio, jonka tämä sovellusversio osaa lukea. Uudempaa ei asenneta,
  /// koska kentät voivat olla muuttuneet.
  static const int supportedSchemaVersion = 1;

  /// Alaraja hyväksyttävälle aineistolle. Sama suoja kuin julkaisuputkessa:
  /// rikkoutunut lähde tai katkennut lataus ei saa korvata toimivaa dataa
  /// lähes tyhjällä.
  static const int minAcceptableSpotCount = 1500;

  /// Kartan aloitusnäkymä, kun sijaintia ei ole käytettävissä.
  static const double fallbackLat = 61.4978;
  static const double fallbackLon = 23.7610;
  static const double fallbackZoom = 12;

  /// Yläraja kerralla kartalle haettaville kohteille. Koko aineisto on
  /// alle 3 000 kohdetta, joten raja ei käytännössä osu — se on suoja
  /// aineiston kasvaessa.
  static const int maxSpotsPerViewport = 2000;
}
