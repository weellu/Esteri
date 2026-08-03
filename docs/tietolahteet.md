# Tietolähteet — invapaikat

Kartoitettu 31.7.2026. Kaikki luvut on mitattu kyselemällä rajapintoja suoraan,
ei dokumentaatiosta.

## Yhteenveto

| Lähde | Kohteita | Tyyppi | Tila |
|---|---:|---|---|
| OSM `parking_space=disabled` | ~890 | Yksittäinen ruutu | Käytössä |
| OSM `amenity=parking` + `capacity:disabled` > 0 | 1 341 | Alue, ruutumäärä tiedossa | Käytössä |
| Tampere `inva- pysäköintialue` | 156 | Alue + osoite + paikkamäärä | Käytössä |
| Turku `Liikennemerkit_invapaikat` | 118 | Liikennemerkki (piste) | Käytössä |
| Helsinki `Pysakointipaikat_alue` `tyyppi='Inva'` | 88 | Alue (polygoni) | Käytössä |
| Digiroad liikennemerkit, lisäkilpi H12.7 | 253 | Liikennemerkki (piste) | Käytössä, harva |
| Espoo `GIS:Liikennemerkit` | ? | Liikennemerkki | **401 — ei avointa pääsyä** |
| Oulu `gis:liikennemerkit` | ? | Liikennemerkki | **401 — ei avointa pääsyä** |
| Seinäjoki | 0 | — | **Ei rajapintaa, ks. alla** |

Vantaalla, Jyväskylässä, Lahdessa, Porissa, Vaasassa ja Hämeenlinnassa ei ole
WFS-tasoa invapaikoille.

## OpenStreetMap

Overpass API. Suomen bbox `59.5,19.0,70.1,31.7` on huomattavasti nopeampi kuin
`area["ISO3166-1"="FI"]`, joka aikakatkaisee usein. Bbox vuotaa hieman rajojen yli,
joten tulokset on suodatettava maakoodilla jälkikäteen.

Huom: `capacity:disabled` on merkitty 3 086 kohteeseen, mutta vain 1 341:ssä arvo on
> 0. Loput ovat eksplisiittisiä "ei invapaikkoja" -merkintöjä, eikä niitä saa
tulkita paikoiksi.

Overpass on jaettu ilmaisresurssi — kyselyt ajetaan vain pipelinessä, ei
sovelluksesta. Peilipalvelimet: `overpass-api.de`, `overpass.kumi.systems`.

## Digiroad (Väylävirasto)

WFS: `https://avoinapi.vaylapilvi.fi/vaylatiedot/digiroad/wfs`
Taso: `digiroad:dr_liikennemerkit` — 591 896 merkkiä koko maassa.

Invapaikka = päämerkki, jolla on lisäkilpi **H12.7** ("Invalidin ajoneuvo").
Lisäkilvet ovat kentissä `kilpityyp1`…`kilpityyp5`. Osumat: 189 / 59 / 7 / 0 / 0,
uniikkeja 253.

Päämerkki on lähes aina `E2` (pysäköintipaikka, vanha koodi 521). Loput ovat
yksittäisiä muita merkkejä.

Varmistettuja umpikujia — älä etsi näitä uudelleen:
- Vanha lisäkilpikoodi `836` ei esiinny aineistossa lainkaan (0 osumaa). Lisäkilvet
  on migroitu H-koodeihin, joten piilossa ei ole lisää dataa.
- `E9.1`/`E9.2` eivät ole pysäköintipaikkamerkkejä tässä aineistossa.
- CQL:n `OR`-suodatin useamman `kilpityypN`-kentän yli kaataa palvelimen (HTTP 500).
  Kysy kenttä kerrallaan ja yhdistä tulokset `id`:n perusteella.
- `resultType=hits` yhdessä monimutkaisen CQL:n kanssa palauttaa 500.

Kattavuus on heikko: invamerkkejä löytyy vain 37 kunnasta (Suomessa yli 300).
Digiroad on siis täydentävä lähde, ei ensisijainen.

Koordinaatisto oletuksena ETRS-TM35FIN; `srsName=EPSG:4326` toimii ja palauttaa
lon/lat-järjestyksessä. Lisenssi: CC BY 4.0.

## Tampere

WFS: `https://geodata.tampere.fi/geoserver/ows`
Taso: `liikennealueet:pysakointi_pysakointipaikat_polygon_gk24` (3 184 kohdetta)
Suodatin: `kohteen_tyyppi = 'inva- pysäköintialue'` → **156**

Laadukkain lähde. Mukana `paikkamaara`, `osoite`, `rajoitustyyppi`,
maksullisuusajat arkena/lauantaina/sunnuntaina, `suurin_sallittu_pysakointiaika`.
`outputFormat=application/json` ja `srsName=EPSG:4326` toimivat suoraan.

Huom: kirjoitusasu on `inva- pysäköintialue` — väliviivan jälkeen välilyönti.

## Turku

WFS: `https://turku.asiointi.fi/TeklaOGCWeb/WFS.ashx`
Taso: `GIS:Liikennemerkit_invapaikat` → **118**

Valmiiksi suodatettu taso, kentät `Varustelaji_koodi` = `H12.7`. Aineiston
sijaintitarkkuudeksi ilmoitetaan alle 10 cm, kattaa n. 630 km katuverkkoa.

Kaksi sudenkuoppaa:
- `opaskartta.turku.fi` uudelleenohjaa hostiin `turku.asiointi.fi`. Käytä jälkimmäistä.
- Palvelin vastaa **403**, jos User-Agent on Pythonin oletus. Selainmainen
  User-Agent vaaditaan.
- `outputFormat=application/json` ei toimi; vastaus on GML 3.1.1.

Koordinaatisto **EPSG:3877** (ETRS-GK23FIN) — vaatii muunnoksen WGS84:ään.

## Helsinki

WFS: `https://kartta.hel.fi/ws/geoserver/avoindata/wfs`
Taso: `avoindata:Pysakointipaikat_alue` (8 752 kohdetta)
Suodatin: `tyyppi = 'Inva'` → **88**

Kattaa vain kantakaupungin ja asukaspysäköintivyöhykkeet, joten Helsingin todellinen
määrä on suurempi kuin 88. Päivittyy aktiivisesti (viimeisin päivitys 30.7.2026).

## Espoo ja Oulu — eivät käytettävissä

Molemmilla on oma liikennemerkkirekisteri, jonka GetCapabilities on julkinen ja
skeema lupaava (Espoo: `Liikennemerkkityyppi2020_koodi`, Oulu: `Varustelaji_koodi`),
mutta GetFeature palauttaa **HTTP 401**. Aineisto ei ole avointa.

- Espoo: `https://kartat.espoo.fi/TeklaOGCWeb/WFS.ashx`, taso `GIS:Liikennemerkit`
- Oulu: `https://e-kartta.ouka.fi/TeklaOGCWeb/WFS.ashx`, taso `gis:liikennemerkit`

Kannattaa kysyä kaupungeilta avointa pääsyä — skeeman perusteella data on olemassa
ja H12.7 löytyisi suoraan koodikentästä.

## Seinäjoki — ei aineistoa (tarkistettu 3.8.2026)

Toisin kuin Espoossa ja Oulussa, tässä ei ole 401:n takana odottavaa valmista
aineistoa. Dataa ei näytä olevan olemassa avoimessa muodossa lainkaan.

Varmistettuja umpikujia — älä etsi näitä uudelleen:
- WFS `https://kartat.seinajoki.fi/teklaogcweb/wfs.ashx` **vastaa 200**, mutta
  tarjoaa vain viisi tasoa: `kanta:Rakennus`, `rakval:ValmisRakennus`,
  `mkos:Osoite`, `sjkkaupunki:PohjakarttaValmis`,
  `sjkkaupunki:AsemakaavoitettuAlue`. Ei pysäköintiä, ei liikennemerkkejä.
- Tekla-vakionimet `GIS:Liikennemerkit`, `gis:liikennemerkit` ja
  `sjkkaupunki:Liikennemerkit` palauttavat `TYPENAME not found` — piilotettua
  tasoa ei ole. Kaupunki itsekin ilmoittaa, ettei sillä ole jatkuvassa
  ylläpidossa olevia WFS-rajapintoja.
- WMS (17 tasoa) on pelkkää taustakarttaa, kaavoja ja ilmakuvia. Rasteria
  muutenkin — pisteitä ei saisi ulos vaikka taso olisi.
- Digiroadissa **0 invamerkkiä** kuntakoodilla 743. Seinäjoki ei ole niiden 37
  kunnan joukossa, joista H12.7-merkkejä löytyy.
- Seipark Oy (kaupungin oma pysäköintiyhtiö) kertoo verkkosivullaan
  invatunnuksen oikeuksista mutta ei julkaise paikkalistaa eikä rajapintaa.

Aineistossa on Seinäjoen seudulla 9 kohdetta, kaikki OSM:stä (6 `space`,
3 `area`). Se on selvästi alikartoitettu ~65 000 asukkaan kaupungiksi.

Etenemistavat: kysy kaupungilta (`karttapalvelut@seinajoki.fi`) onko
liikennemerkkirekisteriä ylipäätään olemassa, ja Seiparkilta heidän omista
alueistaan. Toinen reitti on OSM-kartoitus — ainoa, joka ei vaadi kenenkään
lupaa.

## Datan laatu — mitä käyttöliittymän pitää kertoa

Lähteet eivät ole samanarvoisia, ja tämä on näytettävä käyttäjälle:

- **Tarkka ruutu** — OSM `parking_space=disabled`, Turun liikennemerkit,
  Helsingin polygonit. Sijainti on itse paikka.
- **Alue, jolla on invapaikkoja** — OSM `capacity:disabled`, Tampereen alueet.
  Sijainti on alueen keskipiste, ei ruutu. Käyttäjälle ei saa luvata tarkkaa paikkaa.
- **Liikennemerkki** — Digiroad. Merkki on olemassa, ruutujen määrä ja tarkka
  sijainti tuntematon.

Yksikään lähde ei ole maastossa validoitu.
