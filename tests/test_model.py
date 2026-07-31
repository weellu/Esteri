import unittest

from pipeline.model import (
    PRECISION_AREA,
    PRECISION_SIGN,
    PRECISION_SPACE,
    ParkingSpot,
    merge_cluster,
)


def make(source, sid, precision=PRECISION_SPACE, **kwargs):
    return ParkingSpot(
        source=source, source_id=sid, lat=60.17, lon=24.94, precision=precision, **kwargs
    )


class TestValidation(unittest.TestCase):
    def test_unknown_precision_rejected(self):
        with self.assertRaises(ValueError):
            make("osm", "1", precision="roughly")

    def test_out_of_range_latitude_rejected(self):
        with self.assertRaises(ValueError):
            ParkingSpot(source="osm", source_id="1", lat=95.0, lon=24.9, precision=PRECISION_SPACE)

    def test_negative_capacity_rejected(self):
        with self.assertRaises(ValueError):
            make("osm", "1", capacity=-1)

    def test_uid_combines_source_and_id(self):
        self.assertEqual(make("osm", "node/123").uid, "osm:node/123")


class TestMergeCluster(unittest.TestCase):
    def test_single_spot_records_its_own_uid(self):
        merged = merge_cluster([make("osm", "1")])
        self.assertEqual(merged.merged_from, ["osm:1"])

    def test_empty_cluster_raises(self):
        with self.assertRaises(ValueError):
            merge_cluster([])

    def test_geometry_comes_from_most_precise_observation(self):
        area = ParkingSpot(
            source="tampere", source_id="t", lat=60.0, lon=24.0, precision=PRECISION_AREA
        )
        sign = ParkingSpot(
            source="digiroad", source_id="d", lat=61.0, lon=25.0, precision=PRECISION_SIGN
        )
        merged = merge_cluster([area, sign])
        self.assertEqual((merged.lat, merged.lon), (61.0, 25.0))
        self.assertEqual(merged.precision, PRECISION_SIGN)

    def test_metadata_fills_from_most_authoritative_source_that_has_it(self):
        osm = make("osm", "o", capacity=9, name="OSM-nimi", fee=False)
        tampere = make("tampere", "t", precision=PRECISION_AREA, capacity=3, address="Hämeenkatu 1")
        merged = merge_cluster([osm, tampere])
        # Sijainti tarkimmasta (osm/space), mutta paikkamäärä kunnan datasta.
        self.assertEqual(merged.precision, PRECISION_SPACE)
        self.assertEqual(merged.capacity, 3)
        self.assertEqual(merged.address, "Hämeenkatu 1")
        # Kenttä, jota kunnalla ei ole, peritään heikommasta lähteestä.
        self.assertEqual(merged.name, "OSM-nimi")
        self.assertIs(merged.fee, False)

    def test_false_is_preserved_and_not_treated_as_missing(self):
        low = make("digiroad", "d", precision=PRECISION_SIGN, fee=True)
        high = make("helsinki", "h", fee=False)
        merged = merge_cluster([low, high])
        self.assertIs(merged.fee, False, "False ei saa tulkita puuttuvaksi arvoksi")

    def test_merged_from_lists_every_source_sorted(self):
        merged = merge_cluster(
            [make("osm", "o"), make("digiroad", "d", precision=PRECISION_SIGN), make("turku", "t")]
        )
        self.assertEqual(merged.merged_from, ["digiroad:d", "osm:o", "turku:t"])

    def test_extras_from_higher_authority_win_on_key_collision(self):
        low = make("digiroad", "d", precision=PRECISION_SIGN, extras={"note": "digiroad"})
        high = make("turku", "t", extras={"note": "turku"})
        merged = merge_cluster([low, high])
        self.assertEqual(merged.extras["note"], "turku")

    def test_merging_does_not_mutate_inputs(self):
        osm = make("osm", "o", capacity=None)
        tampere = make("tampere", "t", precision=PRECISION_AREA, capacity=3)
        merge_cluster([osm, tampere])
        self.assertIsNone(osm.capacity)
        self.assertEqual(osm.merged_from, [])


if __name__ == "__main__":
    unittest.main()
