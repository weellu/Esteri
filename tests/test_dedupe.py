import unittest

from pipeline.dedupe import AREA_RADIUS_M, PRECISE_RADIUS_M, deduplicate, match_radius
from pipeline.model import PRECISION_AREA, PRECISION_SIGN, PRECISION_SPACE, ParkingSpot

BASE_LAT = 60.170000
BASE_LON = 24.940000

# Yksi metri pohjoiseen asteina.
METRE_LAT = 1 / 111_000


def spot(source, sid, *, north_m=0.0, precision=PRECISION_SPACE, **kwargs):
    return ParkingSpot(
        source=source,
        source_id=sid,
        lat=BASE_LAT + north_m * METRE_LAT,
        lon=BASE_LON,
        precision=precision,
        **kwargs,
    )


class TestMatchRadius(unittest.TestCase):
    def test_two_precise_observations_use_tight_radius(self):
        a = spot("osm", "1", precision=PRECISION_SPACE)
        b = spot("digiroad", "2", precision=PRECISION_SIGN)
        self.assertEqual(match_radius(a, b), PRECISE_RADIUS_M)

    def test_any_area_widens_the_radius(self):
        a = spot("osm", "1", precision=PRECISION_SPACE)
        b = spot("tampere", "2", precision=PRECISION_AREA)
        self.assertEqual(match_radius(a, b), AREA_RADIUS_M)


class TestDeduplicate(unittest.TestCase):
    def test_two_adjacent_spots_from_same_source_are_never_merged(self):
        # Vierekkäiset invaruudut ovat OSM:ssä eri pisteitä n. 3 m välein.
        # Näiden yhdistäminen hävittäisi todellisen pysäköintipaikan.
        spots = [spot("osm", "a"), spot("osm", "b", north_m=3)]
        result = deduplicate(spots)
        self.assertEqual(len(result), 2)

    def test_close_spots_from_different_sources_are_merged(self):
        spots = [spot("osm", "a"), spot("digiroad", "b", north_m=10, precision=PRECISION_SIGN)]
        result = deduplicate(spots)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0].merged_from, ["digiroad:b", "osm:a"])

    def test_distant_spots_from_different_sources_are_kept_apart(self):
        spots = [spot("osm", "a"), spot("digiroad", "b", north_m=200, precision=PRECISION_SIGN)]
        self.assertEqual(len(deduplicate(spots)), 2)

    def test_no_chaining_through_a_shared_neighbour(self):
        # A(osm) -- B(digiroad) -- C(osm), A ja C molemmat 15 m B:stä mutta
        # 30 m toisistaan. B saa liittyä vain toiseen; A ja C eivät saa
        # päätyä samaan klusteriin.
        spots = [
            spot("osm", "a", north_m=0),
            spot("digiroad", "b", north_m=15, precision=PRECISION_SIGN),
            spot("osm", "c", north_m=30),
        ]
        result = deduplicate(spots)
        self.assertEqual(len(result), 2)
        for merged in result:
            sources = [uid.split(":")[0] for uid in merged.merged_from]
            self.assertEqual(len(sources), len(set(sources)), "klusterissa on kaksi samaa lähdettä")

    def test_municipal_source_anchors_the_cluster_over_osm(self):
        spots = [
            spot("osm", "a", capacity=9),
            spot("helsinki", "h", north_m=8, capacity=2),
        ]
        result = deduplicate(spots)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0].source, "helsinki")
        self.assertEqual(result[0].capacity, 2, "kunnan oma arvo ei saa korvautua OSM:n arvolla")

    def test_precise_location_wins_over_area_centroid(self):
        area = spot("tampere", "t", precision=PRECISION_AREA, capacity=4)
        exact = spot("osm", "o", north_m=20, precision=PRECISION_SPACE)
        result = deduplicate([area, exact])
        self.assertEqual(len(result), 1)
        merged = result[0]
        self.assertEqual(merged.precision, PRECISION_SPACE)
        self.assertAlmostEqual(merged.lat, exact.lat, places=9)
        self.assertEqual(merged.capacity, 4, "paikkamäärä peritään kunnan aineistosta")

    def test_empty_input(self):
        self.assertEqual(deduplicate([]), [])

    def test_result_is_deterministic_regardless_of_input_order(self):
        spots = [
            spot("osm", "a"),
            spot("digiroad", "b", north_m=10, precision=PRECISION_SIGN),
            spot("turku", "c", north_m=500, precision=PRECISION_SIGN),
        ]
        first = [s.uid for s in deduplicate(list(spots))]
        second = [s.uid for s in deduplicate(list(reversed(spots)))]
        self.assertEqual(sorted(first), sorted(second))


if __name__ == "__main__":
    unittest.main()
