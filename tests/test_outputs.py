import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from pipeline.model import PRECISION_AREA, PRECISION_SPACE, ParkingSpot
from pipeline.outputs import write_geojson, write_manifest, write_sqlite

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


class TestManifest(unittest.TestCase):
    """Manifesti on se, jonka sovellus hakee tarkistaakseen onko uutta dataa.

    Sen kentät ovat sopimus sovelluksen kanssa: jos jokin puuttuu tai
    muuttuu tyypiltään, sovellus hylkää päivityksen kokonaan.
    """

    def _write(self, tmp, spots):
        geojson = tmp / "invapaikat.geojson"
        sqlite = tmp / "invapaikat.sqlite"
        write_geojson(spots, geojson, generated_at=GENERATED_AT)
        write_sqlite(spots, sqlite, generated_at=GENERATED_AT)
        manifest = tmp / "manifest.json"
        write_manifest(
            spots,
            manifest,
            generated_at=GENERATED_AT,
            files={"geojson": geojson, "sqlite": sqlite},
        )
        return json.loads(manifest.read_text(encoding="utf-8"))

    def test_contains_fields_the_app_requires(self):
        with tempfile.TemporaryDirectory() as tmp:
            payload = self._write(Path(tmp), sample_spots())
        # Sovellus vaatii nämä kolme oikean tyyppisinä, muuten se hylkää
        # päivityksen. Erityisesti count on luku, ei merkkijono.
        self.assertIsInstance(payload["generated_at"], str)
        self.assertIsInstance(payload["schema_version"], int)
        self.assertIsInstance(payload["count"], int)
        self.assertEqual(payload["count"], 2)
        self.assertEqual(payload["generated_at"], GENERATED_AT)

    def test_count_matches_sqlite_row_count(self):
        # Sovellus vertaa manifestin lukua ladatun tiedoston riveihin ja
        # hylkää päivityksen jos ne eivät täsmää.
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            payload = self._write(tmp_path, sample_spots())
            conn = sqlite3.connect(tmp_path / "invapaikat.sqlite")
            rows = conn.execute("SELECT COUNT(*) FROM spots").fetchone()[0]
            conn.close()
        self.assertEqual(payload["count"], rows)

    def test_carries_license_and_attribution(self):
        with tempfile.TemporaryDirectory() as tmp:
            payload = self._write(Path(tmp), sample_spots())
        self.assertEqual(payload["license"], "ODbL-1.0")
        self.assertIn("OpenStreetMap", payload["attribution"])

    def test_lists_published_files_with_sizes(self):
        with tempfile.TemporaryDirectory() as tmp:
            payload = self._write(Path(tmp), sample_spots())
        self.assertEqual(payload["files"]["sqlite"]["name"], "invapaikat.sqlite")
        self.assertGreater(payload["files"]["sqlite"]["bytes"], 0)
        self.assertEqual(payload["files"]["geojson"]["name"], "invapaikat.geojson")

    def test_manifest_is_small_enough_to_poll(self):
        # Manifestin koko ratkaisee, kannattaako sitä hakea joka
        # käynnistyksellä. Aineisto itse on satoja kilotavuja.
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            self._write(tmp_path, sample_spots())
            size = (tmp_path / "manifest.json").stat().st_size
        self.assertLess(size, 2048)


if __name__ == "__main__":
    unittest.main()
