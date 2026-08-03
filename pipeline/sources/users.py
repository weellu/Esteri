"""Käyttäjien ilmoittamat invapaikat.

Ainoa lähde, joka ei hae verkosta. Kohteet luetaan versionhallinnassa olevasta
tiedostosta `contributions/kayttajat.geojson`, jonka moderointiajo (moderate.py)
tuottaa ja ihminen hyväksyy mergeämällä PR:n. Julkaisuputki ei siis koskaan
lisää aineistoon mitään, mitä ei ole ensin katsottu.

Tiedosto on GeoJSONia nimenomaan siksi, että GitHub piirtää sen kartaksi
selaimessa ja PR-diffin voi arvioida katsomalla pisteitä kartalla ilman
erillistä moderointikäyttöliittymää.

Sijainnin tarkkuus seuraa vahvistusten määrää:

    reported  -> precision "area"   yksi ilmoitus, sijaintiin ei voi luottaa
                                    metrilleen (GPS-heitto, väärä napautus)
    confirmed -> precision "space"  useampi laite eri käynneillä samassa
                                    kohdassa — hajonta on todellinen mittaus

Tämä ei ole kikkailua vaan sisällöllisesti oikein: yksittäisen ilmoituksen
sijaintivirhettä ei voi arvioida mitenkään, kolmen ilmoituksen keskihajonnan
voi. Sivuvaikutuksena vanhat sovellusversiot, jotka eivät tunne
`verification`-kenttää, esittävät vahvistamattoman ilmoituksen varovaisemmin
("alueella") eivätkä lupaa tarkkaa paikkaa.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any, Optional

from ..model import (
    PRECISION_AREA,
    PRECISION_SPACE,
    VERIFICATION_CONFIRMED,
    VERIFICATION_REPORTED,
    ParkingSpot,
)

log = logging.getLogger(__name__)

CONTRIBUTIONS_PATH = Path("contributions/kayttajat.geojson")

# Montako eri laitetta tarvitaan, ennen kuin ilmoitus muuttuu vahvistetuksi.
# Sama kynnys kuin moderate.py:ssä, ja säädin jolla moderoinnin työmäärää
# säädetään: matalampi kynnys = enemmän automaattista hyväksyntää.
CONFIRM_THRESHOLD = 3


def _precision_for(reports: int) -> str:
    return PRECISION_SPACE if reports >= CONFIRM_THRESHOLD else PRECISION_AREA


def _verification_for(reports: int) -> str:
    return VERIFICATION_CONFIRMED if reports >= CONFIRM_THRESHOLD else VERIFICATION_REPORTED


def _spot_from_feature(feature: dict[str, Any]) -> Optional[ParkingSpot]:
    try:
        lon, lat = feature["geometry"]["coordinates"][:2]
        props = feature["properties"]
        spot_id = str(props["id"])
        reports = int(props.get("reports", 1))
    except (KeyError, TypeError, ValueError, IndexError) as exc:
        log.warning("Ohitetaan vajaa kohde käyttäjätiedostossa: %s", exc)
        return None

    try:
        return ParkingSpot(
            source="users",
            source_id=spot_id,
            lat=float(lat),
            lon=float(lon),
            precision=_precision_for(reports),
            verification=_verification_for(reports),
            confirmations=reports,
            # Vapaa teksti on moderoitu ennen tänne päätymistä. Ilmoituksen
            # mukana tullutta tekstiä ei julkaista koskaan sellaisenaan.
            name=props.get("name") or None,
            updated=props.get("last_seen") or None,
        )
    except ValueError as exc:  # koordinaatti alueen ulkopuolella tms.
        log.warning("Ohitetaan kelvoton kohde %s: %s", spot_id, exc)
        return None


def load(path: Path = CONTRIBUTIONS_PATH) -> list[ParkingSpot]:
    if not path.exists():
        # Normaali tilanne ennen ensimmäistä hyväksyttyä ilmoitusta. Ei ole
        # virhe eikä saa kaataa ajoa.
        log.info("%s puuttuu — ei käyttäjien ilmoittamia kohteita", path)
        return []

    payload = json.loads(path.read_text(encoding="utf-8"))
    features = payload.get("features", [])
    spots = [s for s in (_spot_from_feature(f) for f in features) if s is not None]
    log.info("users: %d kohdetta tiedostosta %s", len(spots), path)
    return spots


def fetch_all() -> list[ParkingSpot]:
    return load()
