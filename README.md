# Esteri

Liikkumisesteisten pysäköintipaikkojen karttasovellus iOS:lle ja Androidille.
Aineisto kootaan avoimista rajapinnoista: OpenStreetMap, Digiroad sekä
Tampereen, Turun ja Helsingin omat avoimet aineistot.

## Tilanne

| Osa | Tila |
|---|---|
| Datapipeline | Valmis, tuottaa 2 787 kohdetta |
| Julkaisuputki (GitHub Actions + Pages) | Valmis, odottaa repon luontia |
| Karttanäkymä, klusterointi, kohteen tiedot | Valmis, ajettu iOS-simulaattorissa |
| Navigointi puhelimen karttasovellukseen | Valmis |
| Haku osoitteella ja paikannimellä | Valmis |
| Oman sijainnin seuranta | Valmis |
| Datan päivitys verkosta | Valmis |
| Käyttäjien lisäämät paikat ja vahvistukset | Valmis, odottaa Workerin deployta |

## Datapipeline

Ajo:

```bash
python3 -m pipeline.build                       # kaikki lähteet
python3 -m pipeline.build --sources tampere turku
python3 -m pipeline.build --use-cache           # ei verkkoa, kehitykseen
```

Ei ulkoisia riippuvuuksia — pelkkä Pythonin standardikirjasto. Kaikki lähteet
osaavat uudelleenprojisoida WGS84:ään palvelinpuolella, joten
koordinaattimuunnoskirjastoa ei tarvita.

Testit:

```bash
python3 -m unittest discover -s tests -t .
```

### Ulostulot

`data/invapaikat.geojson` (799 kt, pakattuna 66 kt) — jakelua varten.
`data/invapaikat.sqlite` (488 kt) — sovelluksen käyttöön, R-tree-indeksillä.

Sovellus ei pidä kaikkia kohteita kartalla yhtä aikaa vaan hakee näkyvän
karttaruudun pisteet SQLitestä. Ilman R-treetä jokainen kartansiirto olisi
taulun täysiskannaus.

### Lähteet ja niiden tuottamat määrät

| Lähde | Raakahavaintoja | Lopputuloksessa |
|---|---:|---:|
| OpenStreetMap | 2 288 | 2 240 |
| Digiroad (lisäkilpi H12.7) | 232 | 226 |
| Tampere | 156 | 145 |
| Turku | 118 | 88 |
| Helsinki | 88 | 88 |
| **Yhteensä** | **2 882** | **2 787** |

Rajapintojen yksityiskohdat, sudenkuopat ja umpikujat on dokumentoitu
tiedostossa [`docs/tietolahteet.md`](docs/tietolahteet.md). Lue se ennen kuin
muutat lähdemoduuleja — siellä on kirjattuna mm. miksi Digiroadin lisäkilpiä
kysytään viidellä erillisellä kyselyllä ja miksi Turku vaatii selainmaisen
User-Agentin.

### Datan tarkkuus — tämä pitää näkyä käyttöliittymässä

Kohteet eivät ole keskenään samanarvoisia, ja ero on käyttäjälle olennainen:

| Tarkkuus | Kohteita | Mitä sijainti tarkoittaa |
|---|---:|---|
| `space` | 1 005 | Sijainti on itse pysäköintiruutu |
| `area` | 1 468 | Alueen keskipiste — ruutu on jossain alueella |
| `sign` | 314 | Liikennemerkki, ruutu merkin läheisyydessä |

Yli puolet kohteista on alueen keskipisteitä. Sovellus ei saa esittää niitä
samalla tavalla kuin tarkkoja ruutuja: autoilijalle "invapaikka tässä" ja
"tällä pysäköintialueella on invapaikkoja" ovat eri lupaus.

Tarkkuuden rinnalla kulkee **erillinen** kenttä `verification`, joka kertoo
mistä kohteen olemassaolo tiedetään. Nämä eivät ole sama asia: kunnan
rekisterissä oleva paikka voi olla sijainniltaan epätarkka mutta
olemassaolostaan varma, ja käyttäjän ilmoittama päinvastoin.

| `verification` | Mitä tarkoittaa |
|---|---|
| *(tyhjä)* | Avoimesta aineistosta |
| `reported` | Yhden käyttäjän ilmoitus, ei vahvistusta |
| `confirmed` | Vähintään kolme laitetta vahvistanut maastossa |

Paikkamäärä tunnetaan 2 397 kohteelle, osoite vain 214:lle.

### Deduplikointi

Saman lähteen kahta kohdetta ei koskaan yhdistetä — vierekkäiset invaruudut
ovat OSM:ssä erillisiä pisteitä noin kolmen metrin päässä toisistaan, ja
etäisyyspohjainen yhdistely sulauttaisi kahden paikan pysäköintipaikan yhdeksi.
Yhdistely tapahtuu vain lähteiden välillä, ilman ketjuuntumista.

Sijainti otetaan tarkimmasta havainnosta, metatiedot luotettavimmasta
lähteestä. Käytännössä Digiroadin liikennemerkki antaa hyvän sijainnin ja
Tampereen aluetieto paikkamäärän — yhdistettynä molemmat.

Kynnysarvot (25 m tarkoille havainnoille, 60 m kun mukana on alue) ovat
perusteltuja arvauksia, **joita ei ole validoitu maastossa.**

## Tunnetut rajoitteet

- **Espoo ja Oulu puuttuvat.** Molemmilla on oma liikennemerkkirekisteri
  oikealla skeemalla, mutta GetFeature palauttaa HTTP 401 eli aineisto ei ole
  avointa. Avoimen pääsyn pyytäminen kaupungeilta olisi todennäköisesti suurin
  yksittäinen parannus, jonka voi saada ilman koodia.
- **Helsingin aineisto kattaa vain kantakaupungin** ja
  asukaspysäköintivyöhykkeet, joten Helsingin todellinen määrä on suurempi.
- **Digiroadin kattavuus on heikko:** invamerkkejä löytyy vain 37 kunnasta,
  vaikka merkkejä on kaikkiaan lähes 600 000.
- **Overpass-peilit eivät ole synkronissa.** Peräkkäiset ajot voivat tuottaa
  hieman eri määrän kohteita sen mukaan, mikä peili vastaa. Ero on ollut
  luokkaa 1–3 %.
- **Mitään lähdettä ei ole validoitu maastossa.**

## Lisenssit

**Koodi on MIT, aineisto on ODbL 1.0.** Nämä eivät ole sama asia.

Aineisto sisältää OpenStreetMap-dataa, ja ODbL on share-alike: yhdistämällä
OSM:n muihin lähteisiin syntyy johdettu tietokanta, jolloin **koko yhdistetty
aineisto** on ODbL:n alainen — ei pelkkä OSM-osuus. Tämä ei estä kaupallista
käyttöä eikä kauppajakelua, mutta aineisto on pidettävä avoimena ja
attribuoituna.

Attribuutio on toteutettu pysyvästi näkyvänä palkkina kartan alalaidassa, ei
valikon taakse piilotettuna. Lisäksi `license`- ja `attribution`-kentät kulkevat
aineistotiedoston mukana, jotta tieto ei katoa jos tiedosto irtoaa reposta.

Yksityiskohdat ja lähdekohtaiset velvoitteet: [`docs/lisenssit.md`](docs/lisenssit.md).

## Julkaisu

`.github/workflows/build-data.yml` ajaa pipelinen viikoittain ja julkaisee
tuloksen GitHub Pagesiin. Julkaisu keskeytyy, jos kohteita on alle 1 500 —
rajapinnan muutos ei saa korvata toimivaa aineistoa lähes tyhjällä.

Lukupolku on kokonaan maksuton ja staattinen: GitHub Actions ja Pages
riittävät. Käyttäjien ilmoitusten vastaanottoon tarvitaan lisäksi pieni
Worker, mutta sekin mahtuu ilmaistasolle moninkertaisesti — ks. alla.

## Sovellus

Flutter, kohdealustat iOS ja Android. Karttakirjasto `flutter_map` 8.3
klusteroinnilla (`flutter_map_marker_cluster` 8.2).

```bash
flutter run
flutter test
```

### API-avain

Taustakartta tulee Maanmittauslaitokselta ja vaatii maksuttoman API-avaimen
(OmaTili-rekisteröinti, ei laskutustiliä eikä luottokorttia). Avain annetaan
sovelluksen sisällä avainkuvakkeesta — sitä ei tarvitse kääntää mukaan.
Sovellus testaa avaimen hakemalla yhden tiilen ja kertoo heti, kelpaako se.

Kehityksessä avaimen voi antaa myös käännösaikana:

```bash
flutter run --dart-define=MML_API_KEY=<avain>
```

**Sovellus on käyttökelpoinen ilman avainta.** Invapaikat, kohteen tiedot ja
navigointi toimivat; vain taustakartta jää tyhjäksi. Navigointi avaa puhelimen
oman karttasovelluksen `url_launcher`illa eikä vaadi avainta millään alustalla.

### Haku

Hakupalkki yhdistää kaksi eri asiaa:

1. **Osoitteet ja paikannimet** Maanmittauslaitoksen geokoodauspalvelusta
   (`avoin-paikkatieto.maanmittauslaitos.fi/geocoding/v2/pelias/search`).
   Tämä on ensisijainen tapa, koska käyttäjä tietää minne on menossa — ei
   minkä nimisen invapaikan luo. Valinta siirtää kartan sinne zoomilla 16.
2. **Aineiston omat kohteet** nimen tai osoitteen perusteella. Täydentävä,
   koska osoite tunnetaan vain 214 kohteelle ja nimi harvemmalle.

Geokoodaus käyttää samaa API-avainta kuin karttatiilet, joten erillistä
rekisteröitymistä ei tarvita. Ilman avainta aineiston oma haku toimii silti —
käyttäjä ei jää täysin ilman hakua.

Haetaan vain lähteitä `addresses`, `interpolated-road-addresses` ja
`geographic-names`. Kiinteistötunnukset ja karttalehdet on jätetty pois: ne
eivät auta pysäköintipaikan etsijää.

Koordinaattien akselijärjestys päätellään arvoalueista samalla logiikalla kuin
Turun aineistossa. Suomen leveys- ja pituusasteet eivät mene päällekkäin, joten
CRS84:n ja EPSG:4326:n sekaannus ei voi sijoittaa tulosta hiljaisesti väärin.

### Sijainnin seuranta

Sijaintipainike kiertää kolme tilaa:

| Tila | Sijaintipiste | Kartta |
|---|---|---|
| Pois | ei näy, GPS sammutettu | — |
| Seuraa | päivittyy | siirtyy sijainnin mukana |
| Elävä | päivittyy | pysyy paikallaan |

Kartan raahaus pudottaa seurannan eläväksi mutta **ei sammuta paikannusta**:
liikkeellä olevan on voitava selata karttaa ilman että se nykii takaisin, mutta
oman sijainnin on silti pysyttävä ajan tasalla. Sama koskee hakutuloksen ja
kohteen valintaa. Painikkeen painallus elävässä tilassa keskittää kartan
takaisin, ja seurantatilassa sammuttaa paikannuksen kokonaan.

Zoom asetetaan vain ensimmäisen sijainnin kohdalla (16, sama kuin
hakutuloksella). Sen jälkeen seuranta säilyttää käyttäjän valitseman
mittakaavan — kartta ei saa zoomata itsestään.

Seuranta on **vain etualalla**: `NSLocationWhenInUseUsageDescription` ja
`ACCESS_FINE_LOCATION` riittävät, taustalupia ja Androidin foreground serviceä
ei tarvita. Virta peruutetaan näkymän tuhoutuessa, joten GPS ei jää päälle.

Päivitysten suodatin on 5 metriä. Ilman suodatinta paikallaan seisova laite
tuottaisi päivitysvirran pelkästä mittauksen heittelystä ja kartta nykisi
jatkuvasti.

Karttanäkymä riippuu `LocationService`-rajapinnasta eikä suoraan
`geolocator`ista, jotta seurannan tilakone on testattavissa ilman laitetta.

### Arkkitehtuuri

Aineisto toimitetaan sovelluksen mukana SQLitenä ja kopioidaan ensimmäisellä
käynnistyksellä laitteelle. Kartalle ei koskaan ladata koko aineistoa vaan
ainoastaan näkyvän karttaruudun kohteet R-tree-kyselyllä — `flutter_map`
renderöi markerit Flutter-widgeteinä, eikä tuhansia widgetejä kannata pitää
puussa yhtä aikaa edes klusteroituna.

Karttanäkymä riippuu `SpotRepository`-rajapinnasta eikä suoraan SQLitestä,
jotta näkymän logiikka on testattavissa ilman natiiveja liitännäisiä.

### Datan päivitys

Sovellus tarkistaa käynnistyessään julkaistun manifestin ja lataa tuoreemman
aineiston taustalla. **Datapäivitys ei siis vaadi kauppakierrosta** — se on
Flutterissa erityisen arvokasta, koska OTA-päivityksiä ei ole. Päivityksen voi
myös käynnistää käsin asetuksista.

Päivitys on tarkoituksellisen varovainen: vanha aineisto korvataan vain jos
uusi läpäisee kaikki tarkistukset. Sovellusta käytetään liikkeellä, eikä
epäonnistunutta päivitystä voi korjata paikan päällä.

Uusi aineisto hylätään, jos
- skeemaversio ei ole tämän sovellusversion tukema,
- kohteita on alle 1 500 (sama suoja kuin julkaisuputkessa),
- ladatun tiedoston rivimäärä ei täsmää manifestin lukuun — katkennut lataus
  voi jättää metatiedon paikalleen mutta rivit vajaiksi, tai
- tiedosto ei avaudu tietokantana.

Julkaistun aineiston versio ei myöskään voi kulkea taaksepäin: vanhempi
julkaisu ei korvaa uudempaa paikallista kopiota.

Bundlattu aineisto on vain ensiasennuksen lähtötila. Se päivitetään näin:

```bash
cp data/invapaikat.sqlite assets/data/
# päivitä Config.bundledDataVersion uudella generated_at-arvolla
```

Bundlattu kopio otetaan käyttöön vain jos se on **uudempi** kuin levyllä oleva.
Vertailu on nimenomaan "uudempi", ei "eri" — muuten sovelluspäivitys
ylikirjoittaisi verkosta ladatun tuoreemman aineiston joka käynnistyksellä.

**Uusia sarakkeita lisättäessä skeemaversiota ei nosteta.** Sovellus vaatii
julkaistulta aineistolta täsmälleen tukemansa version, joten noston hinta on
se, että vanhat sovellusversiot lakkaavat pysyvästi saamasta datapäivityksiä.
Sarakkeen lisääminen on additiivinen muutos, jonka vanha sovellus jättää
huomiotta. Versio nostetaan vasta, jos olemassa olevan kentän merkitys muuttuu.

## Käyttäjien ilmoitukset

Kaksi toimintoa: kohteen vahvistaminen tai kiistäminen maastossa, ja uuden
invapaikan ilmoittaminen. Molemmat vaativat sijainnin — ilmoituksen koko arvo
on siinä, että joku on oikeasti seissyt paikan päällä.

```
sovellus ──POST──> Worker + D1 (backend/)
                        │
                  moderate.yml (pe)
                        ↓
              pipeline/moderate.py
                        ↓
         contributions/*.geojson ──PR──> ihminen ──merge──>
                        ↓
              build-data.yml ──> Pages ──> sovellus
```

**Kirjoitus on erotettu luvusta tarkoituksella.** Kartta, haku ja navigointi
toimivat kokonaan ilman taustapalvelua, koska aineisto tulee staattisena
tiedostona. Jos Worker on alhaalla, ilmoitus jää laitteen jonoon ja lähtee kun
yhteys palaa — liikkeellä olevalle käyttäjälle "lähetys ei mennyt läpi" on eri
asia kuin "sovellus ei toimi".

### Työnjako

Worker (`backend/`) on tarkoituksella tyhmä: muotovalidointi, rate limit ja
saman laitteen toistojen karsinta. Kaikki harkintaa vaativa on
`pipeline/moderate.py`:ssä, jossa on käytettävissä koko aineisto ja jota voi
muuttaa ilman uutta deployta.

| Ilmoitus | Käsittely | Ihmistyötä |
|---|---|---|
| Yli 100 m päässä kohteesta | Hylätään | ei |
| Paikannustarkkuus yli 50 m | Hylätään jo laitteella | ei |
| Alle 25 m tunnetusta kohteesta | Kirjataan vahvistukseksi | ei |
| Alle 15 m toisesta ilmoituksesta | Yhdistetään, sijainti keskiarvoistuu | ei |
| Kolmas eri laite samasta kohdasta | Nousee vahvistetuksi | ei |
| Muu uusi paikka | Julkaistaan `reported`-tilassa | katselmointi |

### Moderointi ei ole portti

Yksittäinen ilmoitus julkaistaan heti vahvistamattomana, ja sovellus esittää
sen erikseen merkittynä. Ihmisen tehtävä ei ole päättää onko paikka olemassa —
sitä ei ruudulta näe — vaan poistaa ilkivalta. Jos moderointi olisi portti,
jonon pituus kasvaisi suoraan sen mukaan ehtiikö kukaan katsoa sitä, ja
ominaisuus kuolisi ensimmäiseen kiireiseen kuukauteen.

Moderointi tapahtuu PR:ssä: GitHub piirtää `contributions/kayttajat.geojson`in
kartaksi, joten pisteet näkee kartalla suoraan diffistä myös puhelimella.
Hyväksyntä on merge, hylkäys on PR:n sulkeminen. Työmäärä on noin kymmenen
minuuttia viikossa; jos se venyy, kynnystä kiristetään
`CONFIRM_THRESHOLD`-vakiosta eikä jaksamalla enemmän.

### Yksityisyys

Ei tunnuksia eikä kirjautumista. Laitetunniste on sovelluksen arpoma
satunnainen UUID, joka jää taustapalveluun eikä päädy julkaistuun aineistoon.
IP-osoitetta ei tallenneta, vain rate limitiin käytettävä tiiviste, jonka suola
vaihtuu vuorokausittain. Käyttäjän kirjoittama saateteksti näkyy vain
moderoinnin PR-kuvauksessa eikä koskaan aineistossa.

### Käyttöönotto

Toiminnot ovat piilossa, kunnes taustapalvelun osoite on annettu — nappi, joka
lähettää olemattomaan osoitteeseen, on huonompi kuin ei nappia lainkaan.

```bash
flutter run --dart-define=ESTERI_API=https://<worker>.workers.dev
```

Workerin pystytys ja tarvittavat GitHub-salaisuudet: [`backend/README.md`](backend/README.md).
