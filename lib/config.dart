/// Sovelluksen asetukset.
///
/// Karttatiilet ja osoitehaku tulevat Maanmittauslaitokselta, mutta sovellus
/// ei kutsu MML:ää suoraan. Molemmat kulkevat oman Workerin kautta, joka
/// lisää API-avaimen palvelinpäässä.
///
/// Sovelluksessa ei siis ole avainta lainkaan — ei käyttäjän syöttämää eikä
/// käännökseen upotettua. Jälkimmäinen ei olisi salaisuus: `String
/// .fromEnvironment` päätyy binääriin selkokielisenä.
///
/// Ainoa käännösaikainen arvo on taustapalvelun osoite, [contributionApiBase].
library;

class Config {
  const Config._();

  /// Taustakartan tiiliosoite.
  ///
  /// Osoittaa omaan Workeriin, ei suoraan Maanmittauslaitokselle. MML:n
  /// API-avain on Workerissa eikä sovelluksessa: kaikki mikä lähetetään
  /// laitteelle on julkista, joten käännökseen upotettu avain olisi
  /// kaivettavissa binäärista eikä vaihdettavissa ilman kauppakierrosta.
  ///
  /// Huom: polkujärjestys on {z}/{y}/{x}, koska WMTS:n järjestys on
  /// {TileMatrix}/{TileRow}/{TileCol} — ei tavanomainen z/x/y. Worker olettaa
  /// saman järjestyksen. Väärä järjestys tuottaa kartan, joka näyttää
  /// lataavan mutta esittää väärää aluetta.
  static String get tileUrl => '$contributionApiBase/v1/tiles/{z}/{y}/{x}.png';

  /// Osoite- ja paikannimihaku. Sama Worker, sama syy.
  static String get geocodeUrl => '$contributionApiBase/v1/geocode';

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

  /// Taustapalvelun osoite (Cloudflare Worker, ks. `backend/`).
  ///
  /// Sama Worker hoitaa kolme asiaa: karttatiilet, osoitehaun ja käyttäjien
  /// ilmoitusten vastaanoton. Se annetaan käännösaikana:
  ///
  ///     flutter run --dart-define=ESTERI_API=https://esteri-api.weellu.workers.dev
  ///
  /// **Lippu tarvitaan myös `flutter build`iin, eikä sen puuttuminen ole enää
  /// osittainen puute.** Aiemmin ilman sitä jäivät pois vain ilmoitustoiminnot,
  /// ja versio 1.0.1+3 lähti kauppaan sellaisena. Nyt myös taustakartta ja haku
  /// kulkevat tämän kautta, joten ilman osoitetta sovellus ei ole vajaa vaan
  /// rikki. Siksi [isConfigured] tarkistetaan käynnistyksessä ja puuttuva
  /// osoite pysäyttää sovelluksen näkyvään virheeseen — hiljainen
  /// rappeutuminen olisi juuri se vika, joka jo kerran päätyi julkaisuun.
  static const String contributionApiBase = String.fromEnvironment(
    'ESTERI_API',
  );

  static bool get isConfigured => contributionApiBase.isNotEmpty;

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
