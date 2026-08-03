/**
 * Esterin lähetysten vastaanotto.
 *
 * Worker on tarkoituksella tyhmä. Se ottaa vastaan, karsii ilmeisen roskan ja
 * tallentaa — mitään sisällöllistä päätöstä se ei tee. Kaikki harkintaa
 * vaativa (onko ilmoitus uusi paikka vai vahvistus, riittääkö vahvistuksia,
 * mikä on etäisyys tunnettuun kohteeseen) tehdään pipeline/moderate.py:ssä,
 * jossa on käytettävissä koko aineisto ja jota voi muuttaa ilman uutta
 * deployta. Tässä on vain se, mitä ei voi tehdä muualla.
 *
 * Yksityisyys: laitetunniste on satunnainen UUID, ei laitteen oma tunnus.
 * IP:tä ei tallenneta, vain päivittäin vaihtuvalla suolalla laskettu tiiviste
 * — se riittää vuorokauden rate limitiin muttei henkilön seuraamiseen
 * päivästä toiseen. Kumpikaan ei koskaan poistu tästä tietokannasta:
 * moderointivienti jättää ne pois, koska vientitiedosto päätyy julkiseen
 * repoon.
 */

const FINLAND = { minLat: 59.0, maxLat: 70.5, minLon: 19.0, maxLon: 32.0 };

const KINDS = new Set(['new', 'present', 'missing']);

// Saman laitteen lähetykset tätä lähempänä toisiaan ovat sama ilmoitus.
// Toisto voi tulla myös sovelluksen offline-jonosta uudelleenyrityksenä,
// joten se on hiljainen ei-virhe.
const DUPLICATE_RADIUS_M = 20;

const LIMITS = {
  device: { max: 20, windowSeconds: 86400 },
  ip: { max: 60, windowSeconds: 86400 },
};

const MAX_NOTE_LENGTH = 120;
const MAX_BODY_BYTES = 2048;

// Lähetykset poistetaan puolen vuoden jälkeen. Ne on siihen mennessä viety
// moderointiin ja tulos on versionhallinnassa, joten alkuperäistä riviä ei
// tarvita — eikä henkilötietoa lähentelevää aineistoa kannata säilyttää
// pidempään kuin se on käytössä.
const RETENTION_DAYS = 180;

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });

function haversineM(lat1, lon1, lat2, lon2) {
  const R = 6371000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

async function hashIp(ip, salt, day) {
  const data = new TextEncoder().encode(`${salt}:${day}:${ip}`);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return [...new Uint8Array(digest)]
    .slice(0, 16)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/** Palauta virheteksti, tai null jos runko kelpaa. */
function validate(body) {
  if (typeof body !== 'object' || body === null) return 'runko ei ole objekti';
  if (!KINDS.has(body.kind)) return 'tuntematon kind';

  const { lat, lon } = body;
  if (typeof lat !== 'number' || typeof lon !== 'number' || !isFinite(lat) || !isFinite(lon)) {
    return 'lat ja lon vaaditaan lukuina';
  }
  if (lat < FINLAND.minLat || lat > FINLAND.maxLat || lon < FINLAND.minLon || lon > FINLAND.maxLon) {
    return 'koordinaatti Suomen ulkopuolella';
  }
  if (body.accuracy_m != null && (typeof body.accuracy_m !== 'number' || body.accuracy_m < 0)) {
    return 'accuracy_m ei ole kelvollinen';
  }
  if (typeof body.device !== 'string' || !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(body.device)) {
    return 'device ei ole UUID';
  }
  if (body.kind !== 'new') {
    if (typeof body.target_uid !== 'string' || body.target_uid.length > 80) {
      return 'target_uid vaaditaan vahvistuksessa';
    }
  }
  if (body.note != null && typeof body.note !== 'string') return 'note ei ole merkkijono';
  return null;
}

/**
 * Siivoa saate: ohjausmerkit pois ja pituus kuriin.
 *
 * Saate ei paady julkaistuun aineistoon - se nakyy vain moderaattorille PR:n
 * kuvauksessa. Siivous on silti tarpeen, koska rivinvaihdot ja ohjausmerkit
 * rikkoisivat sen Markdown-esityksen.
 */
function cleanNote(note) {
  if (typeof note !== 'string') return null;
  // eslint-disable-next-line no-control-regex
  const stripped = note.replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim();
  return stripped ? stripped.slice(0, MAX_NOTE_LENGTH) : null;
}

async function checkRateLimit(db, key, limit, now) {
  const bucket = `${key}:${Math.floor(now / limit.windowSeconds)}`;
  const expiresAt = now + limit.windowSeconds;

  await db
    .prepare(
      `INSERT INTO rate_limits (bucket, count, expires_at) VALUES (?, 1, ?)
       ON CONFLICT(bucket) DO UPDATE SET count = count + 1`
    )
    .bind(bucket, expiresAt)
    .run();

  const row = await db.prepare('SELECT count FROM rate_limits WHERE bucket = ?').bind(bucket).first();
  return (row?.count ?? 0) <= limit.max;
}

/**
 * Onko tämä saman laitteen toisto samasta paikasta?
 *
 * Rajaus tehdään ensin karkealla laatikolla, jotta indeksi kelpaa, ja
 * tarkka etäisyys lasketaan vasta muutamalle ehdokkaalle.
 */
async function findDuplicate(db, body) {
  const delta = DUPLICATE_RADIUS_M / 111000;
  const { results } = await db
    .prepare(
      `SELECT id, lat, lon FROM submissions
       WHERE device = ? AND kind = ?
         AND lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?
         AND (? IS NULL OR target_uid IS ?)
       LIMIT 20`
    )
    .bind(
      body.device,
      body.kind,
      body.lat - delta,
      body.lat + delta,
      body.lon - delta * 2,
      body.lon + delta * 2,
      body.target_uid ?? null,
      body.target_uid ?? null
    )
    .all();

  for (const row of results ?? []) {
    if (haversineM(body.lat, body.lon, row.lat, row.lon) <= DUPLICATE_RADIUS_M) return row.id;
  }
  return null;
}

async function handleSubmission(request, env) {
  const raw = await request.text();
  if (raw.length > MAX_BODY_BYTES) return json({ error: 'runko liian suuri' }, 413);

  let body;
  try {
    body = JSON.parse(raw);
  } catch {
    return json({ error: 'kelvoton JSON' }, 400);
  }

  const problem = validate(body);
  if (problem) return json({ error: problem }, 400);

  const now = Math.floor(Date.now() / 1000);
  const day = new Date(now * 1000).toISOString().slice(0, 10);
  const ip = request.headers.get('cf-connecting-ip') ?? '0.0.0.0';
  const ipHash = await hashIp(ip, env.IP_SALT ?? 'esteri', day);

  const deviceOk = await checkRateLimit(env.DB, `d:${body.device}`, LIMITS.device, now);
  const ipOk = await checkRateLimit(env.DB, `i:${ipHash}`, LIMITS.ip, now);
  if (!deviceOk || !ipOk) {
    return json({ error: 'liikaa lähetyksiä, yritä huomenna' }, 429);
  }

  const duplicate = await findDuplicate(env.DB, body);
  if (duplicate !== null) {
    // Ei virhe: sovelluksen offline-jono yrittää uudelleen, ja sama käyttäjä
    // voi vahvistaa saman paikan uudestaan myöhemmin. Kumpikaan ei ole uusi
    // riippumaton havainto, joten laskuri ei saa kasvaa.
    await env.DB.prepare('UPDATE submissions SET created_at = ? WHERE id = ?')
      .bind(new Date().toISOString(), duplicate)
      .run();
    return json({ status: 'duplicate' }, 202);
  }

  await env.DB.prepare(
    `INSERT INTO submissions
       (kind, target_uid, lat, lon, accuracy_m, note, device, app_version, ip_hash, created_at)
     VALUES (?,?,?,?,?,?,?,?,?,?)`
  )
    .bind(
      body.kind,
      body.kind === 'new' ? null : body.target_uid,
      body.lat,
      body.lon,
      body.accuracy_m ?? null,
      body.kind === 'new' ? cleanNote(body.note) : null,
      body.device,
      typeof body.app_version === 'string' ? body.app_version.slice(0, 20) : null,
      ipHash,
      new Date().toISOString()
    )
    .run();

  return json({ status: 'queued' }, 202);
}

/**
 * Moderointivienti.
 *
 * Laitetunniste ja IP-tiiviste EIVÄT ole mukana: vientitiedosto käsitellään
 * GitHub Actionsissa ja tulos päätyy julkiseen repoon. Moderointiin ei
 * tarvita tietoa siitä, kuka lähetti — vain se, montako riippumatonta
 * lähetystä samasta kohdasta on.
 */
async function handleQueue(request, env) {
  const auth = request.headers.get('authorization') ?? '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!env.MODERATION_TOKEN || token !== env.MODERATION_TOKEN) {
    return json({ error: 'ei oikeutta' }, 401);
  }

  const url = new URL(request.url);
  const since = Number.parseInt(url.searchParams.get('since') ?? '0', 10) || 0;
  const limit = Math.min(Number.parseInt(url.searchParams.get('limit') ?? '1000', 10) || 1000, 5000);

  const { results } = await env.DB.prepare(
    `SELECT id, kind, target_uid, lat, lon, accuracy_m, note, app_version, created_at
       FROM submissions WHERE id > ? ORDER BY id LIMIT ?`
  )
    .bind(since, limit)
    .all();

  const cutoff = new Date(Date.now() - RETENTION_DAYS * 86400 * 1000).toISOString();
  await env.DB.prepare('DELETE FROM submissions WHERE created_at < ?').bind(cutoff).run();
  await env.DB.prepare('DELETE FROM rate_limits WHERE expires_at < ?')
    .bind(Math.floor(Date.now() / 1000))
    .run();

  return json({ submissions: results ?? [], since, count: (results ?? []).length });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === 'POST' && url.pathname === '/v1/submissions') {
      return handleSubmission(request, env);
    }
    if (request.method === 'GET' && url.pathname === '/v1/queue') {
      return handleQueue(request, env);
    }
    if (request.method === 'GET' && url.pathname === '/v1/health') {
      return json({ status: 'ok' });
    }
    return json({ error: 'tuntematon polku' }, 404);
  },
};
