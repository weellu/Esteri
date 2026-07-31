"""Helsinki — Pysakointipaikat_alue, tyyppi 'Inva'.

Kattaa vain kantakaupungin ja asukaspysäköintivyöhykkeet, joten Helsingin
todellinen invapaikkamäärä on suurempi kuin tästä aineistosta saatava.
Aineisto päivittyy aktiivisesti.

Geometria on polygoni, mutta pinta-ala on yksittäisen ruudun kokoluokkaa
(tyypillisesti 12–36 m²), joten keskipiste vastaa käytännössä ruutua. Siksi
tarkkuudeksi merkitään 'space' eikä 'area'.
"""

from __future__ import annotations

import logging
from typing import Any, Optional

from ..geo import centroid, in_finland_bbox
from ..http import fetch_json
from ..model import PRECISION_AREA, PRECISION_SPACE, ParkingSpot

log = logging.getLogger(__name__)

SOURCE = "helsinki"

WFS_URL = "https://kartta.hel.fi/ws/geoserver/avoindata/wfs"
LAYER = "avoindata:Pysakointipaikat_alue"
DISABLED_TYPE = "Inva"

# Tätä suurempi polygoni ei ole yksittäinen ruutu vaan alue, jolloin
# keskipiste ei enää kelpaa ruudun sijainniksi.
MAX_SPACE_AREA_M2 = 60.0


def _int_or_none(value: Any) -> Optional[int]:
    try:
        parsed = int(float(value))
    except (TypeError, ValueError):
        return None
    return parsed if parsed > 0 else None


def fetch_all() -> list[ParkingSpot]:
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
            "CQL_FILTER": f"tyyppi='{DISABLED_TYPE}'",
        },
    )
    features = payload.get("features", [])

    spots: list[ParkingSpot] = []
    for feature in features:
        props = feature["properties"]
        lat, lon = centroid(feature["geometry"])
        if not in_finland_bbox(lat, lon):
            continue
        area = props.get("pinta_ala")
        try:
            area_m2 = float(area) if area is not None else None
        except (TypeError, ValueError):
            area_m2 = None
        precision = PRECISION_SPACE
        if area_m2 is not None and area_m2 > MAX_SPACE_AREA_M2:
            precision = PRECISION_AREA

        capacity = _int_or_none(props.get("paikat_des")) or _int_or_none(props.get("paikat_ala"))
        spots.append(
            ParkingSpot(
                source=SOURCE,
                source_id=str(props.get("id") or feature.get("id")),
                lat=lat,
                lon=lon,
                precision=precision,
                capacity=capacity or 1,
                restrictions=props.get("lisatieto") or None,
                updated=props.get("paivitetty_tietopalveluun") or None,
                extras={
                    "orientation": props.get("paikan_asento"),
                    "area_m2": area_m2,
                    "owner": props.get("datanomistaja"),
                },
            )
        )

    log.info("Helsinki: %d invapaikkaa", len(spots))
    return spots
