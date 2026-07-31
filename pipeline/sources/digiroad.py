"""Digiroad (Väylävirasto) — liikennemerkit, lisäkilpi H12.7.

Invapaikka tunnistetaan lisäkilvestä H12.7 ("Invalidin ajoneuvo"), joka voi
olla missä tahansa viidestä lisäkilpikentästä. Päämerkki on lähes aina E2
(pysäköintipaikka), mutta suodatus tehdään lisäkilven perusteella, koska
invalidikilpi voi esiintyä myös muiden merkkien kanssa.

Kaksi rajapinnan rajoitusta, jotka sanelevat toteutuksen:
- CQL:n OR-suodatin useamman kilpityypN-kentän yli kaataa palvelimen (HTTP 500),
  joten kentät kysytään erikseen ja tulokset yhdistetään id:n perusteella.
- resultType=hits yhdessä monimutkaisen suodattimen kanssa palauttaa niin ikään
  500, joten kokonaismäärää ei kysytä erikseen.

Kattavuus on heikko: merkkejä löytyy vain n. 37 kunnasta. Digiroad on
täydentävä lähde, ei ensisijainen.
"""

from __future__ import annotations

import logging
from typing import Any, Optional

from ..geo import in_finland_bbox
from ..http import fetch_json
from ..model import PRECISION_SIGN, ParkingSpot

log = logging.getLogger(__name__)

SOURCE = "digiroad"

WFS_URL = "https://avoinapi.vaylapilvi.fi/vaylatiedot/digiroad/wfs"
LAYER = "digiroad:dr_liikennemerkit"

DISABLED_PLATE = "H12.7"
PLATE_FIELDS = [f"kilpityyp{i}" for i in range(1, 6)]

# Vain nämä päämerkit tulkitaan pysäköintipaikaksi. Muut H12.7:n kanssa
# esiintyvät merkit (esim. C-sarjan kieltomerkit) tarkoittavat päinvastaista:
# rajoitus, josta invaluvalla on poikkeus — ei osoitettua invapaikkaa.
PARKING_SIGN_TYPES = {"E2", "E3.1", "E3.2", "E3.3", "E3.4", "E4.1", "E4.2", "E4.3"}


def _query(plate_field: str) -> list[dict[str, Any]]:
    payload = fetch_json(
        WFS_URL,
        params={
            "service": "WFS",
            "version": "2.0.0",
            "request": "GetFeature",
            "typeNames": LAYER,
            "outputFormat": "application/json",
            "srsName": "EPSG:4326",
            "count": "10000",
            "CQL_FILTER": f"{plate_field}='{DISABLED_PLATE}'",
        },
    )
    return payload.get("features", [])


def _plates(props: dict[str, Any]) -> list[str]:
    return [props[f] for f in PLATE_FIELDS if props.get(f)]


def _municipality(props: dict[str, Any]) -> Optional[int]:
    code = props.get("kuntakoodi")
    return int(code) if code not in (None, "") else None


def fetch_all() -> list[ParkingSpot]:
    by_id: dict[str, dict[str, Any]] = {}
    for field in PLATE_FIELDS:
        features = _query(field)
        log.info("Digiroad: %s='%s' -> %d", field, DISABLED_PLATE, len(features))
        for feature in features:
            by_id[feature["properties"]["id"]] = feature

    spots: list[ParkingSpot] = []
    skipped_non_parking = 0
    for feature in by_id.values():
        props = feature["properties"]
        sign_type = props.get("tyyppi")
        if sign_type not in PARKING_SIGN_TYPES:
            skipped_non_parking += 1
            continue
        lon, lat = feature["geometry"]["coordinates"][:2]
        if not in_finland_bbox(lat, lon):
            continue
        spots.append(
            ParkingSpot(
                source=SOURCE,
                source_id=str(props["id"]),
                lat=float(lat),
                lon=float(lon),
                precision=PRECISION_SIGN,
                name=props.get("tien_nimi") or None,
                updated=props.get("muokkauspv") or None,
                extras={
                    "sign_type": sign_type,
                    "plates": _plates(props),
                    "municipality": _municipality(props),
                },
            )
        )

    log.info(
        "Digiroad: %d invamerkkiä, joista %d pysäköintimerkkejä (%d muuta merkkityyppiä ohitettu)",
        len(by_id),
        len(spots),
        skipped_non_parking,
    )
    return spots
