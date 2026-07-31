import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from pipeline.model import PRECISION_AREA, PRECISION_SPACE, ParkingSpot
from pipeline.outputs import write_geojson, write_sqlite

GENERATED_AT = "2026-07-31T12:00:00+00:00"


def sample_spots():
    return [
        ParkingSpot(
            source="tampere",
            source_id="1",
            lat=61.4978,
            lon=23.7610,
            precision=PRECISION_AREA,
            capacity=4,
            address="Hämeenkatu 1",
            fee=True,
            merged_from=["tampere:1"],
        ),
        ParkingSpot(
            source="osm",
            source_id="node/2",
            lat=60.1699,
            lon=24.9384,
            precision=PRECISION_SPACE,
            capacity=1,
            fee=False,
            merged_from=["osm:node/2"],
        ),
    ]


class TestGeoJson(unittest.TestCase):
    def test_coordinates_are_lon_lat_per_rfc7946(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "out.geojson"
            write_geojson(sample_spots(), path, generated_at=GENERATED_AT)
            payload = json.loads(path.read_text(encoding="utf-8"))
        lon, lat = payload["features"][0]["geometry"]["coordinates"]
        self.assertAlmostEqual(lon, 23.7610, places=4)
        self.assertAlmostEqual(lat, 61.4978, places=4)

    def test_metadata_and_count(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "out.geojson"
            write_geojson(sample_spots(), path, generated_at=GENERATED_AT)
            payload = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(payload["metadata"]["count"], 2)
        self.assertEqual(payload["metadata"]["generated_at"], GENERATED_AT)
        self.assertEqual(len(payload["features"]), 2)

    def test_none_fields_are_omitted_but_false_is_kept(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "out.geojson"
            write_geojson(sample_spots(), path, generated_at=GENERATED_AT)
            payload = json.loads(path.read_text(encoding="utf-8"))
        osm_props = payload["features"][1]["properties"]
        self.assertNotIn("address", osm_props, "tyhjää kenttää ei kirjoiteta")
        self.assertIn("fee", osm_props)
        self.assertIs(osm_props["fee"], False, "fee=False ei saa kadota")

    def test_scandinavian_characters_are_not_escaped(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "out.geojson"
            write_geojson(sample_spots(), path, generated_at=GENERATED_AT)
            self.assertIn("Hämeenkatu", path.read_text(encoding="utf-8"))


class TestSqlite(unittest.TestCase):
    def test_rows_and_columns_roundtrip(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "out.sqlite"
            write_sqlite(sample_spots(), path, generated_at=GENERATED_AT)
            conn = sqlite3.connect(path)
            rows = conn.execute(
                "SELECT uid, source, lat, lon, precision, capacity, address, fee FROM spots ORDER BY uid"
            ).fetchall()
            conn.close()
        self.assertEqual(len(rows), 2)
        osm_row = rows[0]
        self.assertEqual(osm_row[0], "osm:node/2")
        self.assertEqual(osm_row[7], 0, "fee=False tallentuu nollana, ei NULLina")
        tre_row = rows[1]
        self.assertEqual(tre_row[6], "Hämeenkatu 1")
        self.assertEqual(tre_row[5], 4)

    def test_viewport_query_via_rtree_returns_only_spots_in_bbox(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "out.sqlite"
            write_sqlite(sample_spots(), path, generated_at=GENERATED_AT)
            conn = sqlite3.connect(path)
            has_rtree = conn.execute(
                "SELECT value FROM meta WHERE key='has_rtree'"
            ).fetchone()[0]
            if has_rtree == "1":
                rows = conn.execute(
                    """
                    SELECT s.uid FROM spots_bbox b JOIN spots s ON s.id = b.id
                    WHERE b.min_lat >= ? AND b.max_lat <= ? AND b.min_lon >= ? AND b.max_lon <= ?
                    """,
                    (60.0, 60.5, 24.5, 25.5),
                ).fetchall()
            else:
                rows = conn.execute(
                    "SELECT uid FROM spots WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?",
                    (60.0, 60.5, 24.5, 25.5),
                ).fetchall()
            conn.close()
        self.assertEqual([r[0] for r in rows], ["osm:node/2"], "Tampereen kohde ei kuulu ruutuun")

    def test_meta_records_count_and_schema_version(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "out.sqlite"
            write_sqlite(sample_spots(), path, generated_at=GENERATED_AT)
            conn = sqlite3.connect(path)
            meta = dict(conn.execute("SELECT key, value FROM meta").fetchall())
            conn.close()
        self.assertEqual(meta["count"], "2")
        self.assertEqual(meta["generated_at"], GENERATED_AT)
        self.assertIn("schema_version", meta)

    def test_rewriting_replaces_previous_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "out.sqlite"
            write_sqlite(sample_spots(), path, generated_at=GENERATED_AT)
            write_sqlite(sample_spots()[:1], path, generated_at=GENERATED_AT)
            conn = sqlite3.connect(path)
            count = conn.execute("SELECT COUNT(*) FROM spots").fetchone()[0]
            conn.close()
        self.assertEqual(count, 1)


if __name__ == "__main__":
    unittest.main()
