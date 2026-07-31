import math
import unittest

from pipeline.geo import centroid, haversine_m, in_finland_bbox


class TestHaversine(unittest.TestCase):
    def test_known_distance_helsinki_tampere(self):
        # Helsinki (60.1699, 24.9384) -> Tampere (61.4978, 23.7610), n. 161 km.
        d = haversine_m(60.1699, 24.9384, 61.4978, 23.7610)
        self.assertAlmostEqual(d / 1000, 161, delta=3)

    def test_one_degree_latitude_is_about_111km(self):
        d = haversine_m(60.0, 24.0, 61.0, 24.0)
        self.assertAlmostEqual(d / 1000, 111.2, delta=0.5)

    def test_identical_points_are_zero(self):
        self.assertEqual(haversine_m(60.0, 24.0, 60.0, 24.0), 0.0)

    def test_symmetric(self):
        a = haversine_m(60.1, 24.9, 60.2, 25.1)
        b = haversine_m(60.2, 25.1, 60.1, 24.9)
        self.assertAlmostEqual(a, b, places=6)


class TestCentroid(unittest.TestCase):
    def test_point_returns_lat_lon_swapped_from_geojson_order(self):
        # GeoJSON on [lon, lat]; centroid palauttaa (lat, lon).
        self.assertEqual(centroid({"type": "Point", "coordinates": [24.9, 60.1]}), (60.1, 24.9))

    def test_square_polygon_centre(self):
        square = {
            "type": "Polygon",
            "coordinates": [[[0, 0], [2, 0], [2, 2], [0, 2], [0, 0]]],
        }
        lat, lon = centroid(square)
        self.assertAlmostEqual(lat, 1.0, places=9)
        self.assertAlmostEqual(lon, 1.0, places=9)

    def test_l_shaped_polygon_centroid_is_area_weighted_not_vertex_average(self):
        # L-muoto: kärkipisteiden keskiarvo olisi (0.833, 0.833), mutta
        # pinta-alapainotettu keskipiste on eri kohdassa.
        l_shape = {
            "type": "Polygon",
            "coordinates": [[[0, 0], [2, 0], [2, 1], [1, 1], [1, 2], [0, 2], [0, 0]]],
        }
        lat, lon = centroid(l_shape)
        self.assertAlmostEqual(lon, 5 / 6, places=6)
        self.assertAlmostEqual(lat, 5 / 6, places=6)

    def test_polygon_without_closing_point_still_works(self):
        square = {"type": "Polygon", "coordinates": [[[0, 0], [2, 0], [2, 2], [0, 2]]]}
        lat, lon = centroid(square)
        self.assertAlmostEqual(lat, 1.0, places=9)
        self.assertAlmostEqual(lon, 1.0, places=9)

    def test_degenerate_polygon_falls_back_to_vertex_average(self):
        # Kaikki pisteet samalla suoralla -> nolla pinta-ala.
        line = {"type": "Polygon", "coordinates": [[[0, 0], [1, 1], [2, 2], [0, 0]]]}
        lat, lon = centroid(line)
        self.assertAlmostEqual(lat, 1.0, places=9)
        self.assertAlmostEqual(lon, 1.0, places=9)

    def test_multipolygon_weights_by_area_so_small_island_does_not_dominate(self):
        multi = {
            "type": "MultiPolygon",
            "coordinates": [
                [[[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]]],  # iso, keskipiste (5,5)
                [[[100, 100], [101, 100], [101, 101], [100, 101], [100, 100]]],  # pieni
            ],
        }
        lat, lon = centroid(multi)
        # Painotettu keskiarvo: (5*100 + 100.5*1) / 101 = 5.945
        self.assertAlmostEqual(lon, (5 * 100 + 100.5) / 101, places=6)
        self.assertLess(lon, 10, "pieni saareke ei saa vetää keskipistettä pois pääalueelta")

    def test_linestring_is_vertex_average(self):
        line = {"type": "LineString", "coordinates": [[0, 0], [2, 4]]}
        self.assertEqual(centroid(line), (2.0, 1.0))

    def test_unknown_geometry_type_raises(self):
        with self.assertRaises(ValueError):
            centroid({"type": "Curve", "coordinates": []})

    def test_missing_coordinates_raises(self):
        with self.assertRaises(ValueError):
            centroid({"type": "Point"})


class TestFinlandBbox(unittest.TestCase):
    def test_helsinki_is_inside(self):
        self.assertTrue(in_finland_bbox(60.17, 24.94))

    def test_utsjoki_is_inside(self):
        self.assertTrue(in_finland_bbox(69.9, 27.0))

    def test_stockholm_is_outside(self):
        self.assertFalse(in_finland_bbox(59.33, 18.07))

    def test_latitude_and_longitude_ranges_do_not_overlap(self):
        # Tähän nojaa Turun GML-akselijärjestyksen päättely.
        min_lat, min_lon, max_lat, max_lon = 59.5, 19.0, 70.1, 31.7
        self.assertLess(max_lon, min_lat)


if __name__ == "__main__":
    unittest.main()
