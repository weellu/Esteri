# Esterin lähetyspalvelu

Cloudflare Worker + D1. Ottaa vastaan käyttäjien vahvistukset ja uudet
invapaikkailmoitukset. **Ei osallistu lukupolkuun lainkaan.**

Sovelluksen kartta, haku ja navigointi toimivat kokonaan ilman tätä palvelua:
aineisto tulee staattisena SQLitenä GitHub Pagesista. Jos tämä palvelu on
alhaalla, käyttäjä ei voi lähettää ilmoitusta ja sovellus jättää sen omaan
jonoonsa myöhemmin lähetettäväksi. Liikkeellä olevalle käyttäjälle "lähetys ei
mennyt läpi" on eri asia kuin "sovellus ei toimi", ja tämä jako pitää eron
voimassa.

## Työnjako

Worker on tarkoituksella tyhmä. Se tekee vain sen, mitä muualla ei voi tehdä:

| | Worker | `pipeline/moderate.py` |
|---|---|---|
| Muotovalidointi, Suomen rajaus | kyllä | kyllä (uudelleen) |
| Rate limit | kyllä | — |
| Saman laitteen toistojen karsinta | kyllä | — |
| Onko uusi paikka vai vahvistus | — | kyllä |
| Klusterointi, vahvistuskynnys | — | kyllä |
| Etäisyys tunnettuun kohteeseen | — | kyllä |

Sisällölliset säännöt ovat Pythonissa, koska siellä on käytettävissä koko
aineisto ja koska niitä voi muuttaa ilman uutta deployta. Workerin logiikka
muuttuu harvoin — se on hyvä asia palvelulle, jota ei valvota.

## Käyttöönotto

**Kaikki wrangler-komennot ajetaan tästä hakemistosta.** Wrangler etsii
`wrangler.tomlin` työhakemistosta ylöspäin, eikä repon juuressa ole sellaista.
Juuresta ajettuna komento ei löydä konfiguraatiota ja valittaa puuttuvasta
Workerin nimestä, vaikka nimi on tiedostossa.

```bash
cd backend

npm install -g wrangler
wrangler login

wrangler d1 create esteri           # vain jos kantaa ei vielä ole
wrangler d1 execute esteri --remote --file=schema.sql

wrangler secret put MODERATION_TOKEN  # satunnainen merkkijono, esim. openssl rand -hex 32
wrangler secret put IP_SALT           # toinen satunnainen merkkijono

wrangler deploy
```

### Skeemamuutokset olemassa olevaan kantaan

`schema.sql` käyttää `CREATE TABLE IF NOT EXISTS`, joten se **ei** muuta jo
luotua taulua. Uusi sarake on lisättävä erikseen:

```bash
wrangler d1 execute esteri --remote \
  --command "ALTER TABLE submissions ADD COLUMN capacity INTEGER"
```

Aja tämä kerran. Uusi kanta saa sarakkeen suoraan `schema.sql`:stä, joten
komentoa ei tarvita puhtaalta pöydältä aloitettaessa.

Kanta on jo luotu ja sen `database_id` on `wrangler.tomlissa`. Jos joudut
luomaan sen uudelleen, kopioi `wrangler d1 create` -komennon tulosteesta **vain
`database_id`** — komento ehdottaa bindingiksi kannan nimeä, mutta binding on
Workerin koodin sopimus ja sen on pysyttävä `DB`:nä (`env.DB`).

Deployn jälkeen:

1. Anna Workerin osoite sovellukselle. Se luetaan käännösaikaisesta
   `ESTERI_API`-määrittelystä (`Config.contributionApiBase`):

   ```bash
   flutter run --dart-define=ESTERI_API=https://esteri-api.<tili>.workers.dev
   ```

   Ilman sitä ilmoitusnapit ovat piilossa eikä sovellus ota yhteyttä tänne.
2. Tallenna GitHubiin repositoryn asetuksiin:
   - secret `MODERATION_TOKEN` — moderointiajon lukuoikeus jonoon
   - variable `CONTRIBUTION_API_BASE` — sama osoite kuin yllä

Paikallinen ajo (myös tästä hakemistosta):

```bash
wrangler dev --local
curl -X POST localhost:8787/v1/submissions -d '{
  "kind":"new","lat":61.498,"lon":23.761,
  "device":"00000000-0000-4000-8000-000000000000","accuracy_m":8
}'
```

## Rajapinta

### `POST /v1/submissions`

```json
{
  "kind": "new | present | missing",
  "target_uid": "osm:node/123",
  "lat": 61.4980,
  "lon": 23.7610,
  "accuracy_m": 8.0,
  "capacity": 3,
  "note": "P-talon 2. krs",
  "device": "<satunnainen UUID>",
  "app_version": "1.0.1"
}
```

`202 {"status":"queued"}` — otettiin vastaan
`202 {"status":"duplicate"}` — sama laite on jo ilmoittanut samasta kohdasta
`400` — muotovirhe · `429` — vuorokauden raja täynnä

`target_uid` vaaditaan vahvistuksissa, `note` huomioidaan vain lajilla `new`.

`capacity` on invaruutujen määrä ilmoituskohdassa, 1–99, ja se on aina
vapaaehtoinen — käyttäjää ei pakoteta arvaamaan. Se kelpaa lajeilla `new` ja
`present`, ja `present` on nimenomaan se tapa korjata määrä jälkikäteen: ruutuja
voidaan maalata lisää tai pois, ja ensimmäinen laskija on voinut laskea väärin.
Lajilla `missing` se on virhe.

Saman laitteen toisto samasta paikasta on edelleen `duplicate` eikä kasvata
havaintojen määrää, mutta **annettu `capacity` päivittää olemassa olevan rivin.**
Muuten käyttäjä ei voisi korjata omaa aiempaa lukemaansa: korjaus hylättäisiin
hiljaa duplikaattina ja väärä määrä jäisi voimaan.

### `GET /v1/queue?since=<id>&limit=<n>`

Vaatii `Authorization: Bearer <MODERATION_TOKEN>`. Palauttaa lähetykset
id-järjestyksessä lukukohdasta eteenpäin. Vastauksessa **ei ole**
laitetunnistetta eikä IP-tiivistettä: vastaus käsitellään GitHub Actionsissa
ja tulos päätyy julkiseen repoon.

Kutsu siivoaa samalla yli 180 vrk vanhat lähetykset ja vanhentuneet rate
limit -laskurit. Erillistä siivousajoa ei siis tarvita.

### `GET /v1/health`

## Yksityisyys

- **Ei tunnuksia, ei kirjautumista.** Tunnukset olisivat GDPR-taakka ja
  karkottaisivat juuri sen käyttäjän, joka istuu autossa ja haluaa napauttaa
  yhtä nappia.
- **Laitetunniste** on sovelluksen ensimmäisellä käynnistyksellä arpoma UUID.
  Se ei ole laitteen oma tunnus eikä seuraa käyttäjää sovelluksen
  uudelleenasennuksen yli. Sitä käytetään vain toistojen karsintaan.
- **IP-osoitetta ei tallenneta.** Rate limit käyttää tiivistettä, jonka suola
  vaihtuu vuorokausittain, joten sama osoite ei ole yhdistettävissä yli
  vuorokauden rajan.
- **Kumpikaan ei poistu tästä tietokannasta.** Moderointivienti jättää ne pois.

## Kustannus

Rahassa nolla. Ilmaistason rajat (100 000 pyyntöä ja 100 000 kirjoitettua
riviä vuorokaudessa) ovat noin kolmikymmenkertaiset arvioituun käyttöön
nähden. Todellinen hinta on moderointi: noin kymmenen minuuttia viikossa,
eikä sitä voi automatisoida pois. Jos se venyy, kiristä
`CONFIRM_THRESHOLD`-kynnystä `pipeline/sources/users.py`:ssä — säädin on
siinä, ei siinä että jaksaa enemmän.
