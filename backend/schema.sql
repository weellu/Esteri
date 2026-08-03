-- Esterin lähetysjono (Cloudflare D1).
--
-- Tämä on vastaanottolaatikko, ei sovelluksen tietokanta. Kartta, haku ja
-- navigointi toimivat kokonaan ilman tätä palvelua: aineisto tulee staattisena
-- SQLitenä GitHub Pagesista. Jos tämä palvelu on alhaalla, käyttäjä ei voi
-- lähettää ilmoitusta, mutta sovellus ei riko itseään.

CREATE TABLE IF NOT EXISTS submissions (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  kind        TEXT    NOT NULL,   -- 'new' | 'present' | 'missing'
  target_uid  TEXT,               -- vain vahvistuksissa
  lat         REAL    NOT NULL,   -- lähettäjän oma sijainti
  lon         REAL    NOT NULL,
  accuracy_m  REAL,
  -- Invaruutujen määrä ilmoituskohdassa. Vapaaehtoinen: arvausta ei kannata
  -- pakottaa. Kelpaa lajeilla 'new' ja 'present' — jälkimmäisellä se on
  -- korjaus, kun ruutujen määrä on muuttunut tai laskettu väärin.
  capacity    INTEGER,
  note        TEXT,               -- vain 'new', näkyy vain moderaattorille
  device      TEXT    NOT NULL,   -- satunnais-UUID, ei henkilötieto
  app_version TEXT,
  ip_hash     TEXT    NOT NULL,   -- päivittäin vaihtuvalla suolalla
  created_at  TEXT    NOT NULL
);

-- Jonon vienti lukee aina id-järjestyksessä lukukohdasta eteenpäin.
CREATE INDEX IF NOT EXISTS idx_submissions_id ON submissions(id);

-- Saman laitteen toistojen karsintaan tarvitaan haku laitteen ja lajin
-- mukaan. Ilman tätä jokainen lähetys skannaisi koko taulun.
CREATE INDEX IF NOT EXISTS idx_submissions_device ON submissions(device, kind);

-- Rate limit -laskurit. Avain on 'laji:tunniste:aikaikkuna', jolloin vanhat
-- rivit voi poistaa yhdellä ehdolla eikä erillistä siivousajoa tarvita.
CREATE TABLE IF NOT EXISTS rate_limits (
  bucket     TEXT    PRIMARY KEY,
  count      INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_rate_expiry ON rate_limits(expires_at);
