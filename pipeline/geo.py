"""Geometria-apurit: keskipisteet ja etäisyydet.

Kaikki toimii WGS84-asteissa. Etäisyydet lasketaan haversinella — tarkkuus
riittää hyvin kymmenien metrien duplikaattikynnyksiin.
"""

from __future__ import annotations

import math
from typing import Any, Iterable

EARTH_RADIUS_M = 6_371_008.8


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Kahden pisteen etäisyys metreinä."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = p2 - p1
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlambda / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(a))


def _ring_centroid(ring: list[list[float]]) -> tuple[float, float, float]:
    """Renkaan pinta-alapainotettu keskipiste. Palauttaa (lon, lat, |pinta-ala|).

    Käyttää shoelace-kaavaa. Rappeutuneille renkaille (nolla pinta-ala, esim.
    kaikki pisteet samalla suoralla) palautetaan kärkipisteiden keskiarvo,
    jotta yksittäinen viivamainen pysäköintialue ei katoa.
    """
    if len(ring) >= 2 and ring[0] == ring[-1]:
        ring = ring[:-1]
    if not ring:
        raise ValueError("tyhjä rengas")
    if len(ring) < 3:
        lon = sum(p[0] for p in ring) / len(ring)
        lat = sum(p[1] for p in ring) / len(ring)
        return lon, lat, 0.0

    area2 = 0.0
    cx = 0.0
    cy = 0.0
    for i in range(len(ring)):
        x0, y0 = ring[i][0], ring[i][1]
        x1, y1 = ring[(i + 1) % len(ring)][0], ring[(i + 1) % len(ring)][1]
        cross = x0 * y1 - x1 * y0
        area2 += cross
        cx += (x0 + x1) * cross
        cy += (y0 + y1) * cross

    if abs(area2) < 1e-12:
        lon = sum(p[0] for p in ring) / len(ring)
        lat = sum(p[1] for p in ring) / len(ring)
        return lon, lat, 0.0

    factor = 1.0 / (3.0 * area2)
    return cx * factor, cy * factor, abs(area2) / 2.0


def centroid(geometry: dict[str, Any]) -> tuple[float, float]:
    """GeoJSON-geometrian keskipiste. Palauttaa (lat, lon)."""
    gtype = geometry.get("type")
    coords = geometry.get("coordinates")
    if gtype is None or coords is None:
        raise ValueError(f"kelvoton geometria: {geometry!r}")

    if gtype == "Point":
        return float(coords[1]), float(coords[0])

    if gtype == "MultiPoint" or gtype == "LineString":
        pts = list(coords)
        return (
            sum(p[1] for p in pts) / len(pts),
            sum(p[0] for p in pts) / len(pts),
        )

    if gtype == "MultiLineString":
        pts = [p for line in coords for p in line]
        return (
            sum(p[1] for p in pts) / len(pts),
            sum(p[0] for p in pts) / len(pts),
        )

    if gtype == "Polygon":
        lon, lat, _ = _ring_centroid(coords[0])
        return lat, lon

    if gtype == "MultiPolygon":
        # Painota osapolygonit pinta-alalla, jotta pieni saareke ei siirrä
        # keskipistettä pois pääalueelta.
        total = 0.0
        acc_lon = 0.0
        acc_lat = 0.0
        fallback: list[tuple[float, float]] = []
        for polygon in coords:
            lon, lat, area = _ring_centroid(polygon[0])
            fallback.append((lon, lat))
            total += area
            acc_lon += lon * area
            acc_lat += lat * area
        if total > 0:
            return acc_lat / total, acc_lon / total
        return (
            sum(p[1] for p in fallback) / len(fallback),
            sum(p[0] for p in fallback) / len(fallback),
        )

    if gtype == "GeometryCollection":
        pts = [centroid(g) for g in geometry.get("geometries", [])]
        if not pts:
            raise ValueError("tyhjä GeometryCollection")
        return sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)

    raise ValueError(f"tukematon geometriatyyppi: {gtype}")


# Suomen bounding box. Käytetään Overpass-kyselyissä, koska
# area["ISO3166-1"="FI"] aikakatkaisee toistuvasti. Bbox vuotaa naapurimaiden
# puolelle, joten tulokset suodatetaan tällä samalla laatikolla ja lisäksi
# maantieteellisesti tarkemmin jäljempänä.
FINLAND_BBOX = (59.5, 19.0, 70.1, 31.7)  # (min_lat, min_lon, max_lat, max_lon)


def in_finland_bbox(lat: float, lon: float) -> bool:
    min_lat, min_lon, max_lat, max_lon = FINLAND_BBOX
    return min_lat <= lat <= max_lat and min_lon <= lon <= max_lon
