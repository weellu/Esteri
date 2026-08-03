"""Ulostulomuodot: GeoJSON jakelua varten, SQLite sovelluksen kyselyihin.

Sovellus ei koskaan pidä kaikkia kohteita kartalla yhtä aikaa, vaan hakee
näkyvän karttaruudun pisteet SQLitestä. Siksi R-tree-indeksi on olennainen:
ilman sitä viewport-kysely olisi taulun täysiskannaus jokaisella kartansiirrolla.
"""

from __future__ import annotations

import json
import logging
import sqlite3
from dataclasses import asdict
from pathlib import Path
from typing import Any, Optional

from .model import ParkingSpot

log = logging.getLogger(__name__)

# Skeemaversiota EI nosteta uusia sarakkeita lisättäessä.
#
# Sovellus vaatii julkaistulta aineistolta täsmälleen tukemansa version
# (evaluateManifest), joten noston hinta on se, että vanhat sovellusversiot
# lakkaavat pysyvästi saamasta datapäivityksiä. Sarakkeen lisääminen on
# additiivinen muutos: kysely on `SELECT *` ja rivit luetaan nimetyistä
# kentistä, joten vanha sovellus jättää uudet sarakkeet huomiotta.
#
# Nosta versio vasta, jos olemassa olevan kentän merkitys tai tyyppi muuttuu.
SCHEMA_VERSION = 1

# Aineisto sisältää OpenStreetMap-dataa, joten yhdistelmä on ODbL:n
# tarkoittama johdettu tietokanta ja jaettava samalla lisenssillä.
# Attribuutio kulkee tiedoston mukana, jotta se ei katoa matkalla.
LICENSE = "ODbL-1.0"
ATTRIBUTION = (
    "© OpenStreetMap-tekijät (ODbL), © Väylävirasto (CC BY 4.0), "
    "© Tampereen kaupunki, © Turun kaupunki, © Helsingin kaupunki, "
    "© Esterin käyttäjät (ODbL)"
)


def _properties(spot: ParkingSpot) -> dict[str, Any]:
    props = asdict(spot)
    props.pop("lat")
    props.pop("lon")
    return {k: v for k, v in props.items() if v not in (None, {}, [])}


def write_geojson(spots: list[ParkingSpot], path: Path, *, generated_at: str) -> None:
    payload = {
        "type": "FeatureCollection",
        "metadata": {
            "generated_at": generated_at,
            "schema_version": SCHEMA_VERSION,
            "count": len(spots),
            "license": LICENSE,
            "attribution": ATTRIBUTION,
        },
        "features": [
            {
                "type": "Feature",
                "geometry": {
                    # GeoJSON on aina lon, lat -järjestyksessä (RFC 7946).
                    "type": "Point",
                    "coordinates": [round(spot.lon, 7), round(spot.lat, 7)],
                },
                "properties": _properties(spot),
            }
            for spot in spots
        ],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    log.info("Kirjoitettu %s (%d kohdetta, %.1f kt)", path, len(spots), path.stat().st_size / 1024)


def write_manifest(
    spots: list[ParkingSpot], path: Path, *, generated_at: str, files: dict[str, Path]
) -> None:
    """Kirjoita pieni manifesti, jonka sovellus hakee version tarkistamiseen.

    Ilman tätä sovelluksen pitäisi ladata koko aineisto vain nähdäkseen, onko
    se muuttunut. Manifesti on muutama sata tavua.
    """
    payload = {
        "generated_at": generated_at,
        "schema_version": SCHEMA_VERSION,
        "count": len(spots),
        "license": LICENSE,
        "attribution": ATTRIBUTION,
        "files": {
            name: {"name": file.name, "bytes": file.stat().st_size}
            for name, file in files.items()
            if file.exists()
        },
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    log.info("Kirjoitettu %s", path)


def _rtree_available(conn: sqlite3.Connection) -> bool:
    try:
        conn.execute("CREATE VIRTUAL TABLE _rtree_probe USING rtree(id, minx, maxx)")
        conn.execute("DROP TABLE _rtree_probe")
        return True
    except sqlite3.OperationalError:
        return False


def write_sqlite(spots: list[ParkingSpot], path: Path, *, generated_at: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        path.unlink()

    conn = sqlite3.connect(path)
    try:
        conn.execute(
            """
            CREATE TABLE spots (
                id             INTEGER PRIMARY KEY,
                uid            TEXT NOT NULL UNIQUE,
                source         TEXT NOT NULL,
                lat            REAL NOT NULL,
                lon            REAL NOT NULL,
                precision      TEXT NOT NULL,
                capacity       INTEGER,
                name           TEXT,
                address        TEXT,
                restrictions   TEXT,
                max_duration_h REAL,
                fee            INTEGER,
                updated        TEXT,
                merged_from    TEXT,
                verification   TEXT,
                confirmations  INTEGER,
                disputes       INTEGER
            )
            """
        )
        conn.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)")

        rows = [
            (
                index,
                spot.uid,
                spot.source,
                spot.lat,
                spot.lon,
                spot.precision,
                spot.capacity,
                spot.name,
                spot.address,
                spot.restrictions,
                spot.max_duration_h,
                None if spot.fee is None else int(spot.fee),
                spot.updated,
                ",".join(spot.merged_from) or None,
                spot.verification,
                spot.confirmations,
                spot.disputes,
            )
            for index, spot in enumerate(spots, start=1)
        ]
        conn.executemany(
            "INSERT INTO spots VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            rows,
        )

        # Tavallinen indeksi luodaan AINA, ei vain R-treen puuttuessa.
        # Androidin järjestelmä-SQLitessä ei ole rtree-moduulia, joten
        # sovellus joutuu siellä käyttämään tätä indeksiä riippumatta siitä,
        # tukiko aineiston rakentanut kone R-treetä.
        conn.execute("CREATE INDEX idx_spots_latlon ON spots(lat, lon)")

        has_rtree = _rtree_available(conn)
        if has_rtree:
            conn.execute(
                "CREATE VIRTUAL TABLE spots_bbox USING rtree(id, min_lat, max_lat, min_lon, max_lon)"
            )
            conn.executemany(
                "INSERT INTO spots_bbox VALUES (?,?,?,?,?)",
                [(row[0], row[3], row[3], row[4], row[4]) for row in rows],
            )
        else:
            log.warning("SQLite ilman R-tree-tukea — aineistoon ei kirjoiteta spots_bbox-taulua")

        conn.executemany(
            "INSERT INTO meta VALUES (?,?)",
            [
                ("generated_at", generated_at),
                ("schema_version", str(SCHEMA_VERSION)),
                ("count", str(len(spots))),
                ("has_rtree", "1" if has_rtree else "0"),
                ("license", LICENSE),
                ("attribution", ATTRIBUTION),
            ],
        )
        conn.commit()
        conn.execute("VACUUM")
    finally:
        conn.close()

    log.info("Kirjoitettu %s (%d kohdetta, %.1f kt)", path, len(spots), path.stat().st_size / 1024)
