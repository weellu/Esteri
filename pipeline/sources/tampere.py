"""Tampere — pysäköintialueet, kohteen_tyyppi 'inva- pysäköintialue'.

Laadukkain yksittäinen lähde: mukana paikkamäärä, osoite, rajoitustyyppi ja
maksullisuusajat erikseen arkena, lauantaina ja sunnuntaina.

Huom: invapaikat eivät ole omana aineistonaan avoindata-portaalissa, vaan
piilossa yleisen pysäköintiaineiston sisällä. Suodatusarvon kirjoitusasu on
tarkalleen 'inva- pysäköintialue' — väliviivan jälkeen tulee välilyönti.

Geometria on polygoni, joten sijainti on alueen keskipiste eikä yksittäinen
ruutu.
"""

from __future__ import annotations

import logging
from typing import Any, Optional

from ..geo import centroid, in_finland_bbox
from ..http import fetch_json
from ..model import PRECISION_AREA, ParkingSpot

log = logging.getLogger(__name__)

SOURCE = "tampere"

WFS_URL = "https://geodata.tampere.fi/geoserver/ows"
LAYER = "liikennealueet:pysakointi_pysakointipaikat_polygon_gk24"
DISABLED_TYPE = "inva- pysäköintialue"


def _int_or_none(value: Any) -> Optional[int]:
    try:
        parsed = int(float(value))
    except (TypeError, ValueError):
        return None
    return parsed if parsed > 0 else None


def _float_or_none(value: Any) -> Optional[float]:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _restrictions(props: dict[str, Any]) -> Optional[str]:
    """Kokoa rajoitukset yhdeksi käyttäjälle näytettäväksi merkkijonoksi."""
    parts: list[str] = []
    kind = props.get("rajoitustyyppi")
    if kind:
        parts.append(str(kind))
    for label, key in (
        ("ark", "rajoitus_maksullinen_arkena"),
        ("la", "rajoitus_maksullinen_lauantaina"),
        ("su", "rajoitus_maksullinen_sunnuntaina"),
    ):
        window = props.get(key)
        if window and str(window).strip() not in {"-", ""}:
            parts.append(f"maksullinen {label} {window}")
    extra = props.get("rajoitusten_lisatiedot")
    if extra:
        parts.append(str(extra))
    return "; ".join(parts) if parts else None


def _fee(props: dict[str, Any]) -> Optional[bool]:
    kind = (props.get("rajoitustyyppi") or "").lower()
    if "maksullinen" in kind:
        return True
    if props.get("maksuvyohyke"):
        return True
    if "kiekko" in kind or "ilmainen" in kind:
        return False
    return None


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
            "CQL_FILTER": f"kohteen_tyyppi='{DISABLED_TYPE}'",
        },
    )
    features = payload.get("features", [])

    spots: list[ParkingSpot] = []
    for feature in features:
        props = feature["properties"]
        lat, lon = centroid(feature["geometry"])
        if not in_finland_bbox(lat, lon):
            continue
        spots.append(
            ParkingSpot(
                source=SOURCE,
                source_id=str(props.get("id") or feature.get("id")),
                lat=lat,
                lon=lon,
                precision=PRECISION_AREA,
                capacity=_int_or_none(props.get("paikkamaara")),
                address=props.get("osoite") or None,
                restrictions=_restrictions(props),
                max_duration_h=_float_or_none(props.get("suurin_sallittu_pysakointiaika")),
                fee=_fee(props),
                extras={
                    "area_number": props.get("alueen_numero"),
                    "note": props.get("lisatietoa"),
                    "link": props.get("lisatietoa_linkki"),
                },
            )
        )

    log.info("Tampere: %d invapysäköintialuetta", len(spots))
    return spots
