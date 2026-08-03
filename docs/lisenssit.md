# Lisenssit ja attribuutio

Repossa on kaksi eri lisenssin alaista osaa, eikä niitä saa sekoittaa
keskenään.

## Lähdekoodi — MIT

`lib/`, `pipeline/`, `tests/`, `test/` ja konfiguraatiot. Ks. [LICENSE](../LICENSE).

## Aineisto — ODbL 1.0

`assets/data/invapaikat.sqlite` ja pipelinen tuottama `data/`.

Aineisto sisältää OpenStreetMap-dataa. OSM on ODbL 1.0 -lisensoitu, ja lisenssi
on **share-alike**: jos dataa yhdistellään tai muokataan ja tulos jaetaan, tulos
on jaettava samalla lisenssillä. Yhdistämällä OSM:n muihin lähteisiin syntyy
ODbL:n tarkoittama *johdettu tietokanta* (derived database), joten koko
yhdistetty aineisto on ODbL:n alainen — ei pelkkä OSM-osuus.

Tämä ei estä sovelluksen jakelua kaupoissa eikä kaupallista käyttöä. Se
tarkoittaa, että itse **aineisto** on pidettävä avoimena ja attribuoituna.

En ole juristi, ja jos sovellusta viedään kaupalliseen jakeluun, tämä kohta
kannattaa tarkistuttaa.

## Attribuutiovelvoitteet

Nämä ovat lisenssiehtoja, eivät kohteliaisuutta.

| Lähde | Krediitti | Lisenssi |
|---|---|---|
| OpenStreetMap | © OpenStreetMap-tekijät | ODbL 1.0 |
| Digiroad | © Väylävirasto | CC BY 4.0 |
| Tampere | © Tampereen kaupunki | CC BY 4.0 |
| Turku | © Turun kaupunki | CC BY 4.0 |
| Helsinki | © Helsingin kaupunki | CC BY 4.0 |
| Sovelluksen käyttäjät | © Esterin käyttäjät | ODbL 1.0 |
| Karttatiilet ja geokoodaus | © Maanmittauslaitos | MML:n avoimen datan lisenssi |

## Käyttäjien ilmoitukset

Käyttäjien lähettämät paikat ja vahvistukset päätyvät samaan julkaistavaan
aineistoon, joten ne ovat ODbL:n alaisia siinä missä muukin. Käytännössä tämä
tarkoittaa, että **ilmoituksen lähettäminen luovuttaa sen avoimeen aineistoon**
— sitä ei voi jälkikäteen ottaa pois, koska aineisto on jo levinnyt eteenpäin.
Tämä on kerrottava käyttäjälle ennen lähetystä, ei sen jälkeen.

Ilmoituksesta ei tallenneta lähettäjää: laitetunniste on satunnainen UUID, joka
jää taustapalveluun eikä päädy julkaistuun aineistoon lainkaan. Siksi ODbL:n
edellyttämä attribuutio on kollektiivinen ("© Esterin käyttäjät") eikä
nimeäminen ole mahdollista — eikä tarpeen, koska yksittäinen koordinaatti ei
yllä teoskynnykseen.

Käyttäjän kirjoittama saateteksti **ei mene aineistoon**. Se näkyy vain
moderoinnin PR-kuvauksessa. Moderoimaton vapaa teksti ODbL-aineistossa leviäisi
eteenpäin kaikkiin sitä käyttäviin palveluihin, eikä sitä saisi enää pois.

### Miten attribuutio on toteutettu

- **Sovelluksessa**: pysyvästi näkyvä palkki kartan alalaidassa
  (`lib/ui/attribution_bar.dart`). Sitä ei ole piilotettu valikon taakse,
  koska OSM edellyttää selkeää mainintaa selattavan kartan yhteydessä.
  Napauttamalla avautuu koko lisenssiluettelo (`lib/ui/licenses_screen.dart`).
- **Kohteen tiedoissa**: yksittäisen kohteen lähde nimetään erikseen.
- **Aineistotiedostossa**: `license`- ja `attribution`-kentät sekä GeoJSONin
  `metadata`-lohkossa että SQLiten `meta`-taulussa, jotta tieto ei katoa jos
  tiedosto irtoaa reposta.
- **Maanmittauslaitoksen krediitti näytetään vain kun taustakarttaa oikeasti
  näytetään** — ilman API-avainta tiiliä ei haeta, jolloin krediitti olisi
  harhaanjohtava.

## Jos lähteitä lisätään

Uusi lähde vaatii kolme muutosta, ja kaikki kolme on tehtävä:

1. `pipeline/sources/` — lähdemoduuli
2. `pipeline/outputs.py` — `ATTRIBUTION`-vakio
3. `lib/ui/licenses_screen.dart` — luettelon kortti

Jos lähteen lisenssi on tiukempi kuin ODbL tai kieltää jatkojakelun, aineistoa
**ei saa** yhdistää tähän julkaistavaan tiedostoon.
