"""Lähderekisteri.

Espoo ja Oulu puuttuvat tarkoituksella: molemmilla on oma liikennemerkki-
rekisteri oikealla skeemalla, mutta GetFeature palauttaa HTTP 401 eli data ei
ole avointa. Ks. docs/tietolahteet.md.
"""

from __future__ import annotations

from typing import Callable

from ..model import ParkingSpot
from . import digiroad, helsinki, osm, tampere, turku

SOURCES: dict[str, Callable[[], list[ParkingSpot]]] = {
    "osm": osm.fetch_all,
    "digiroad": digiroad.fetch_all,
    "tampere": tampere.fetch_all,
    "turku": turku.fetch_all,
    "helsinki": helsinki.fetch_all,
}

__all__ = ["SOURCES", "digiroad", "helsinki", "osm", "tampere", "turku"]
