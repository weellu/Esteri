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
  static const String userAgentPackageName = 'fi.esteri.app';

  /// Aineiston versio. Nosta tätä, kun assets/data/invapaikat.sqlite
  /// päivitetään — muuten sovellus jättää vanhan kopion käyttöön.
  static const String bundledDataVersion = '2026-07-31T10:52:06+00:00';

  static const String assetDatabasePath = 'assets/data/invapaikat.sqlite';

  /// Julkaistu aineisto. Pipeline ajetaan viikoittain GitHub Actionsissa ja
  /// tulos julkaistaan Pagesiin, joten datapäivitys ei vaadi kauppakierrosta.
  static const String dataBaseUrl = 'https://weellu.github.io/Esteri';
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

  /// Käyttäjien ilmoitusten vastaanotto (Cloudflare Worker, ks. `backend/`).
  ///
  /// **Tyhjä oletusarvo on tarkoituksellinen.** Kun osoitetta ei ole, sovellus
  /// piilottaa vahvistus- ja lisäysnapit kokonaan — nappi, joka lähettää
  /// olemattomaan osoitteeseen, on huonompi kuin ei nappia lainkaan. Täytä
  /// tämä `wrangler deploy`n jälkeen tai anna käännösaikana:
  ///
  ///     flutter run --dart-define=ESTERI_API=https://<worker>.workers.dev
  ///
  /// Lähetys ei kuulu lukupolkuun: kartta, haku ja navigointi toimivat
  /// ilman tätä palvelua täsmälleen kuten ennenkin.
  static const String contributionApiBase = String.fromEnvironment(
    'ESTERI_API',
  );

  static bool get contributionsEnabled => contributionApiBase.isNotEmpty;

  static String get contributionSubmitUrl =>
      '$contributionApiBase/v1/submissions';

  /// Kulkee lähetyksen mukana, jotta rikkinäisen version tuottamat ilmoitukset
  /// voi tunnistaa jälkikäteen. Pidä sama kuin pubspec.yamlin version.
  static const String appVersion = '1.0.1';

  /// Paikannustarkkuus, jota huonommalla ilmoitusta ei kannata lähettää.
  /// Sama raja kuin moderoinnissa (`pipeline/moderate.py`), jotta käyttäjälle
  /// kerrotaan heti eikä hylätä hiljaa vasta palvelimella.
  static const double maxSubmitAccuracyM = 50;
}
