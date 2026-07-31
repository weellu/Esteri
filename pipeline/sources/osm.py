"""OpenStreetMap Overpass API.

Kaksi eri kohdetyyppiä, joita ei saa sekoittaa keskenään:

1. `parking_space=disabled` — yksittäinen merkitty invaruutu. Sijainti on
   itse ruutu, eli tarkin mahdollinen tieto.
2. `amenity=parking` + `capacity:disabled` — pysäköintialue, jolla on
   invapaikkoja. Sijainti on alueen keskipiste, ei ruutu.

`capacity:disabled` on merkitty myös alueille, joilla invapaikkoja EI ole
(arvo 0 tai "no"). Nämä on suodatettava pois — muuten sovellus ohjaisi
käyttäjän paikkaan, jossa nimenomaan tiedetään ettei invapaikkoja ole.
"""

from __future__ import annotations

import logging
from typing import Any, Iterator, Optional

from ..geo import FINLAND_BBOX, in_finland_bbox
from ..http import DESCRIPTIVE_USER_AGENT, fetch_first_ok
from ..model import PRECISION_AREA, PRECISION_SPACE, ParkingSpot

log = logging.getLogger(__name__)

SOURCE = "osm"

ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
]

_BBOX = "{},{},{},{}".format(*FINLAND_BBOX)

_QUERY_SPACES = f"""
[out:json][timeout:280][bbox:{_BBOX}];
nwr["parking_space"="disabled"];
out tags center;
"""

_QUERY_AREAS = f"""
[out:json][timeout:280][bbox:{_BBOX}];
nwr["amenity"="parking"]["capacity:disabled"];
out tags center;
"""

# Arvot, jotka tarkoittavat "ei invapaikkoja". Nämä ovat aitoa tietoa, ei
# puuttuvaa tietoa, ja siksi ne suodatetaan pois eikä tulkita tuntemattomaksi.
_NEGATIVE_CAPACITY = {"no", "none", "0", "false"}


def parse_capacity(raw: Optional[str]) -> tuple[bool, Optional[int]]:
    """Tulkitse `capacity:disabled`. Palauttaa (onko paikkoja, määrä).

    Määrä on None, kun tiedetään että paikkoja on mutta ei montako
    (esim. arvo "yes").
    """
    if raw is None:
        return False, None
    value = raw.strip().lower()
    if not value or value in _NEGATIVE_CAPACITY:
        return False, None
    if value in {"yes", "y", "true"}:
        return True, None
    # Muodot "2", "2;3", "n. 4", "4+" — poimi ensimmäinen kokonaisluku.
    digits = ""
    for char in value:
        if char.isdigit():
            digits += char
        elif digits:
            break
    if not digits:
        # Tuntematon merkintätapa: tulkitaan olemassaoloksi ilman määrää
        # mieluummin kuin hylätään tieto kokonaan.
        log.debug("tuntematon capacity:disabled arvo: %r", raw)
        return True, None
    count = int(digits)
    return (count > 0), (count if count > 0 else None)


def _coords(element: dict[str, Any]) -> Optional[tuple[float, float]]:
    if "lat" in element and "lon" in element:
        return float(element["lat"]), float(element["lon"])
    center = element.get("center")
    if center:
        return float(center["lat"]), float(center["lon"])
    return None


def _run_query(query: str) -> list[dict[str, Any]]:
    import json

    raw = fetch_first_ok(
        ENDPOINTS,
        data={"data": query},
        timeout=320,
        user_agent=DESCRIPTIVE_USER_AGENT,
    )
    return json.loads(raw).get("elements", [])


def _address(tags: dict[str, str]) -> Optional[str]:
    street = tags.get("addr:street")
    if not street:
        return None
    number = tags.get("addr:housenumber")
    city = tags.get("addr:city")
    parts = [f"{street} {number}".strip() if number else street]
    if city:
        parts.append(city)
    return ", ".join(parts)


def _fee(tags: dict[str, str]) -> Optional[bool]:
    value = tags.get("fee")
    if value is None:
        return None
    value = value.strip().lower()
    if value in {"yes", "true"}:
        return True
    if value in {"no", "false"}:
        return False
    return None


def fetch_spaces() -> Iterator[ParkingSpot]:
    for element in _run_query(_QUERY_SPACES):
        pos = _coords(element)
        if pos is None:
            continue
        lat, lon = pos
        if not in_finland_bbox(lat, lon):
            continue
        tags = element.get("tags", {})
        _, capacity = parse_capacity(tags.get("capacity"))
        yield ParkingSpot(
            source=SOURCE,
            source_id=f"{element['type']}/{element['id']}",
            lat=lat,
            lon=lon,
            precision=PRECISION_SPACE,
            capacity=capacity if capacity else 1,
            name=tags.get("name"),
            address=_address(tags),
            fee=_fee(tags),
            extras={"osm_type": element["type"]},
        )


def fetch_areas() -> Iterator[ParkingSpot]:
    for element in _run_query(_QUERY_AREAS):
        tags = element.get("tags", {})
        has_spots, capacity = parse_capacity(tags.get("capacity:disabled"))
        if not has_spots:
            continue
        pos = _coords(element)
        if pos is None:
            continue
        lat, lon = pos
        if not in_finland_bbox(lat, lon):
            continue
        yield ParkingSpot(
            source=SOURCE,
            source_id=f"{element['type']}/{element['id']}",
            lat=lat,
            lon=lon,
            precision=PRECISION_AREA,
            capacity=capacity,
            name=tags.get("name"),
            address=_address(tags),
            fee=_fee(tags),
            extras={"osm_type": element["type"], "parking": tags.get("parking")},
        )


def fetch_all() -> list[ParkingSpot]:
    spots = list(fetch_spaces())
    log.info("OSM: %d yksittäistä invaruutua", len(spots))
    areas = list(fetch_areas())
    log.info("OSM: %d pysäköintialuetta joilla invapaikkoja", len(areas))
    return spots + areas
