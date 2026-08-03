"""Ylläpitäjän poistolista.

Erillään `signals.py`:stä tarkoituksella: signaalit ovat koneen keräämää
käyttäjädataa, tämä on ihmisen tekemä päätös. Jos ne olisivat samassa
tiedostossa, moderointiajo kirjoittaisi tiedoston, johon ylläpitäjä on käsin
lisännyt rivejä — ja ennemmin tai myöhemmin se menisi päällekkäin.

Poisto on tarpeen, koska avoimen aineiston kohdetta ei voi korjata tästä
päästä: seuraava ajo hakee sen takaisin lähteestä. Kiiston purku merkitsee
sellaisen kohteen `disputed`-tilaan, mutta joskus tiedetään varmasti, että
kohde on virheellinen — silloin sitä ei kannata näyttää lainkaan.

Tiedostoa ei koskaan kirjoiteta ohjelmallisesti. Se katselmoidaan PR:ssä kuten
muutkin `contributions/`-tiedostot.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

from .geo import haversine_m
from .model import ParkingSpot

log = logging.getLogger(__name__)

EXCLUSIONS_PATH = Path("contributions/poistetut.json")

# Kuinka kaukana kohde saa olla kirjatusta sijainnista ja silti tulla
# poistetuksi.
#
# Tämä ei ole hienosäätöä vaan turvaraja. `signals.py` dokumentoi jo, että
# deduplikoinnin ankkuri voi vaihtua ajojen välillä, jolloin sama uid voi
# osoittaa eri kohteeseen kuin poistoa kirjattaessa. Ilman tarkistusta ajo
# voisi jonain päivänä poistaa väärän paikan hiljaa — ja hiljaa katoava
# invapaikka on pahin mahdollinen vikatyyppi tässä sovelluksessa.
MAX_DRIFT_M = 50.0


def load_exclusions(path: Path = EXCLUSIONS_PATH) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        log.warning("Poistolistaa ei voitu lukea (%s) — mitään ei poisteta", exc)
        return []
    if not isinstance(data, list):
        log.warning("Poistolista ei ole lista — mitään ei poisteta")
        return []
    return [e for e in data if isinstance(e, dict) and e.get("uid")]


def apply_exclusions(
    spots: list[ParkingSpot], exclusions: list[dict[str, Any]]
) -> tuple[list[ParkingSpot], int, int]:
    """Poista listatut kohteet. Palauttaa (jäljelle jäävät, poistetut, ohitetut)."""
    if not exclusions:
        return spots, 0, 0

    by_uid = {str(e["uid"]): e for e in exclusions}
    kept: list[ParkingSpot] = []
    removed = 0
    skipped = 0

    for spot in spots:
        # Sama haku kuin signaaleilla: uid on voinut vaihtua deduplikoinnissa,
        # ja poisto katoaisi juuri niistä kohteista, joista on eniten tietoa.
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
                    "Poistoa ei tehty: %s on %.0f m päässä kirjatusta sijainnista "
                    "(raja %.0f m). Tarkista poistolista.",
                    entry["uid"],
                    drift,
                    MAX_DRIFT_M,
                )
                skipped += 1
                kept.append(spot)
                continue

        log.info("Poistettu julkaisusta: %s — %s", entry["uid"], entry.get("syy", "ei syytä"))
        removed += 1

    if removed or skipped:
        log.info("Poistolista: %d poistettu, %d ohitettu", removed, skipped)
    return kept, removed, skipped
