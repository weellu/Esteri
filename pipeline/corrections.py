"""Ylläpitäjän korjaukset avoimeen aineistoon.

Erillään `signals.py`:stä tarkoituksella: signaalit ovat koneen keräämää
käyttäjädataa, tämä on ihmisen tekemä päätös. Jos ne olisivat samassa
tiedostossa, moderointiajo kirjoittaisi tiedoston, johon ylläpitäjä on käsin
lisännyt rivejä — ja ennemmin tai myöhemmin se menisi päällekkäin.

Korjauksia tarvitaan, koska avoimen aineiston virhettä ei voi korjata tästä
päästä: seuraava ajo hakee kohteen takaisin lähteestä sellaisena kuin se siellä
on. Kaksi toimintoa:

    poista   kohdetta ei julkaista lainkaan
    siirra   kohde julkaistaan annetussa sijainnissa

Siirto on useimmiten oikeampi kuin poisto. Väärä koordinaatti ei tarkoita,
ettei invapaikkaa ole — se tarkoittaa, että se on jossain muualla. Poisto
hävittää tiedon, siirto korjaa sen.

Tiedostoa ei koskaan kirjoiteta ohjelmallisesti. Se katselmoidaan PR:ssä kuten
muutkin `contributions/`-tiedostot.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any, Optional

from .geo import haversine_m, in_finland_bbox
from .model import ParkingSpot

log = logging.getLogger(__name__)

CORRECTIONS_PATH = Path("contributions/korjaukset.json")

ACTION_REMOVE = "poista"
ACTION_MOVE = "siirra"
_ACTIONS = (ACTION_REMOVE, ACTION_MOVE)

# Kuinka kaukana kohde saa olla kirjatusta sijainnista ja silti tulla
# korjatuksi.
#
# Tämä ei ole hienosäätöä vaan turvaraja. `signals.py` dokumentoi jo, että
# deduplikoinnin ankkuri voi vaihtua ajojen välillä, jolloin sama uid voi
# osoittaa eri kohteeseen kuin korjausta kirjattaessa. Ilman tarkistusta ajo
# voisi jonain päivänä poistaa tai siirtää väärän paikan hiljaa — ja hiljaa
# katoava invapaikka on pahin mahdollinen vikatyyppi tässä sovelluksessa.
MAX_DRIFT_M = 50.0


def load_corrections(path: Path = CORRECTIONS_PATH) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        log.warning("Korjauslistaa ei voitu lukea (%s) — mitään ei korjata", exc)
        return []
    if not isinstance(data, list):
        log.warning("Korjauslista ei ole lista — mitään ei korjata")
        return []

    usable: list[dict[str, Any]] = []
    for entry in data:
        if not isinstance(entry, dict) or not entry.get("uid"):
            continue
        if entry.get("toiminto") not in _ACTIONS:
            log.warning(
                "Ohitetaan korjaus ilman kelvollista toimintoa: %s", entry.get("uid")
            )
            continue
        usable.append(entry)
    return usable


def _target(entry: dict[str, Any]) -> Optional[tuple[float, float]]:
    lat, lon = entry.get("uusi_lat"), entry.get("uusi_lon")
    if not isinstance(lat, (int, float)) or not isinstance(lon, (int, float)):
        return None
    if not in_finland_bbox(float(lat), float(lon)):
        return None
    return float(lat), float(lon)


def apply_corrections(
    spots: list[ParkingSpot], corrections: list[dict[str, Any]]
) -> tuple[list[ParkingSpot], int, int, int]:
    """Sovella korjaukset.

    Palauttaa (jäljelle jäävät, poistetut, siirretyt, ohitetut).
    """
    if not corrections:
        return spots, 0, 0, 0

    by_uid = {str(e["uid"]): e for e in corrections}
    kept: list[ParkingSpot] = []
    removed = moved = skipped = 0

    for spot in spots:
        # Sama haku kuin signaaleilla: uid on voinut vaihtua deduplikoinnissa,
        # ja korjaus katoaisi juuri niistä kohteista, joista on eniten tietoa.
        entry = None
        for uid in (spot.uid, *spot.merged_from):
            entry = by_uid.get(uid)
            if entry is not None:
                break

        if entry is None:
            kept.append(spot)
            continue

        lat, lon = entry.get("lat"), entry.get("lon")
        if isinstance(lat, (int, float)) and isinstance(lon, (int, float)):
            drift = haversine_m(spot.lat, spot.lon, float(lat), float(lon))
            if drift > MAX_DRIFT_M:
                log.warning(
                    "Korjausta ei tehty: %s on %.0f m päässä kirjatusta sijainnista "
                    "(raja %.0f m). Tarkista korjauslista.",
                    entry["uid"],
                    drift,
                    MAX_DRIFT_M,
                )
                skipped += 1
                kept.append(spot)
                continue

        if entry["toiminto"] == ACTION_REMOVE:
            log.info(
                "Poistettu julkaisusta: %s — %s", entry["uid"], entry.get("syy", "ei syytä")
            )
            removed += 1
            continue

        target = _target(entry)
        if target is None:
            log.warning(
                "Siirtoa ei tehty: %s:llä ei ole kelvollista uutta sijaintia",
                entry["uid"],
            )
            skipped += 1
            kept.append(spot)
            continue

        spot.lat, spot.lon = target
        log.info("Siirretty: %s — %s", entry["uid"], entry.get("syy", "ei syytä"))
        moved += 1
        kept.append(spot)

    if removed or moved or skipped:
        log.info(
            "Korjauslista: %d poistettu, %d siirretty, %d ohitettu",
            removed,
            moved,
            skipped,
        )
    return kept, removed, moved, skipped
