"""Turku — GIS:Liikennemerkit_invapaikat.

Ainoa kunta, jolla on valmis invapaikkataso. Sijaintitarkkuudeksi ilmoitetaan
alle 10 cm, kattaa n. 630 km katuverkkoa asemakaava-alueella.

Kolme sudenkuoppaa, jotka on jo kertaalleen selvitetty:
- Portaalissa mainittu opaskartta.turku.fi uudelleenohjaa hostiin
  turku.asiointi.fi. Käytetään suoraan jälkimmäistä.
- Palvelin vastaa 403:lla Pythonin oletus-User-Agentille (ks. http.USER_AGENT).
- outputFormat=application/json ei ole tuettu; vastaus on aina GML 3.1.1.

Palvelin osaa uudelleenprojisoida WGS84:ään, joten koordinaattimuunnosta ei
tarvita.
"""

from __future__ import annotations

import logging
import xml.etree.ElementTree as ET
from typing import Optional

from ..geo import FINLAND_BBOX, in_finland_bbox
from ..http import fetch_text
from ..model import PRECISION_SIGN, ParkingSpot

log = logging.getLogger(__name__)

SOURCE = "turku"

WFS_URL = "https://turku.asiointi.fi/TeklaOGCWeb/WFS.ashx"
LAYER = "GIS:Liikennemerkit_invapaikat"

NS = {
    "gml": "http://www.opengis.net/gml",
    "GIS": "http://www.tekla.com/schemas/GIS",
}


def _parse_pos(text: str) -> Optional[tuple[float, float]]:
    """Tulkitse gml:pos. Palauttaa (lat, lon).

    GML 3.1.1:n akselijärjestys EPSG:4326:lle on epäselvä käytännössä — tämä
    palvelin palauttaa lon/lat. Järjestys päätellään arvoalueista, koska Suomen
    leveys- ja pituusasteet eivät mene päällekkäin (lat 59.5–70.1, lon 19–31.7).
    """
    parts = text.split()
    if len(parts) < 2:
        return None
    try:
        a, b = float(parts[0]), float(parts[1])
    except ValueError:
        return None

    min_lat, min_lon, max_lat, max_lon = FINLAND_BBOX
    a_is_lat = min_lat <= a <= max_lat
    b_is_lat = min_lat <= b <= max_lat
    if b_is_lat and not a_is_lat:
        return b, a  # lon lat
    if a_is_lat and not b_is_lat:
        return a, b  # lat lon
    return None


def fetch_all() -> list[ParkingSpot]:
    body = fetch_text(
        WFS_URL,
        params={
            "service": "WFS",
            "version": "1.1.0",
            "request": "GetFeature",
            "typeName": LAYER,
            "srsName": "EPSG:4326",
            "maxFeatures": "10000",
        },
    )
    root = ET.fromstring(body)

    spots: list[ParkingSpot] = []
    dropped = 0
    for member in root.findall(".//gml:featureMember", NS):
        feature = member.find("GIS:Liikennemerkit_invapaikat", NS)
        if feature is None:
            continue
        pos_el = feature.find(".//gml:pos", NS)
        id_el = feature.find("GIS:Id", NS)
        if pos_el is None or pos_el.text is None or id_el is None:
            dropped += 1
            continue
        parsed = _parse_pos(pos_el.text)
        if parsed is None:
            dropped += 1
            continue
        lat, lon = parsed
        if not in_finland_bbox(lat, lon):
            dropped += 1
            continue
        code_el = feature.find("GIS:Varustelaji_koodi", NS)
        label_el = feature.find("GIS:Varustelaji", NS)
        spots.append(
            ParkingSpot(
                source=SOURCE,
                source_id=str(id_el.text),
                lat=lat,
                lon=lon,
                precision=PRECISION_SIGN,
                capacity=1,
                extras={
                    "sign_code": code_el.text if code_el is not None else None,
                    "sign_label": label_el.text if label_el is not None else None,
                },
            )
        )

    if dropped:
        log.warning("Turku: %d kohdetta hylättiin puuttuvan tai kelvottoman sijainnin takia", dropped)
    log.info("Turku: %d invapaikkaa", len(spots))
    return spots
