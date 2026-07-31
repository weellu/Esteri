import unittest

from pipeline.sources.digiroad import PARKING_SIGN_TYPES
from pipeline.sources.osm import parse_capacity
from pipeline.sources.turku import _parse_pos


class TestParseCapacity(unittest.TestCase):
    def test_missing_tag_means_no_information(self):
        self.assertEqual(parse_capacity(None), (False, None))

    def test_zero_means_explicitly_no_disabled_spaces(self):
        # Tämä on aitoa tietoa: alueella tiedetään EI olevan invapaikkoja.
        self.assertEqual(parse_capacity("0"), (False, None))

    def test_no_means_explicitly_none(self):
        self.assertEqual(parse_capacity("no"), (False, None))
        self.assertEqual(parse_capacity("NO"), (False, None))

    def test_yes_means_present_but_count_unknown(self):
        self.assertEqual(parse_capacity("yes"), (True, None))

    def test_plain_number(self):
        self.assertEqual(parse_capacity("4"), (True, 4))

    def test_semicolon_list_takes_first_number(self):
        self.assertEqual(parse_capacity("2;3"), (True, 2))

    def test_number_with_suffix(self):
        self.assertEqual(parse_capacity("4+"), (True, 4))

    def test_whitespace_is_ignored(self):
        self.assertEqual(parse_capacity("  7 "), (True, 7))

    def test_unparseable_text_counts_as_present_without_count(self):
        self.assertEqual(parse_capacity("useita"), (True, None))

    def test_empty_string_is_no_information(self):
        self.assertEqual(parse_capacity(""), (False, None))


class TestDigiroadSignFilter(unittest.TestCase):
    def test_parking_sign_included(self):
        self.assertIn("E2", PARKING_SIGN_TYPES)

    def test_prohibition_signs_excluded(self):
        # C-sarjan kieltomerkki H12.7-lisäkilvellä tarkoittaa poikkeusta
        # rajoitukseen, ei osoitettua invapaikkaa.
        for sign in ("C38", "C40", "C41", "C1", "C2"):
            self.assertNotIn(sign, PARKING_SIGN_TYPES)

    def test_warning_signs_excluded(self):
        for sign in ("A15", "A33"):
            self.assertNotIn(sign, PARKING_SIGN_TYPES)


class TestTurkuAxisOrder(unittest.TestCase):
    def test_lon_lat_order_is_detected(self):
        # Palvelin palauttaa lon lat, vaikka EPSG:4326 määrittelee lat lon.
        self.assertEqual(_parse_pos("22.2565309 60.4486930"), (60.4486930, 22.2565309))

    def test_lat_lon_order_is_also_handled(self):
        self.assertEqual(_parse_pos("60.4486930 22.2565309"), (60.4486930, 22.2565309))

    def test_coordinates_outside_finland_are_rejected(self):
        self.assertIsNone(_parse_pos("10.0 10.0"))

    def test_projected_coordinates_are_rejected(self):
        # EPSG:3877-arvot eivät saa mennä läpi asteina.
        self.assertIsNone(_parse_pos("23459078.060 6704295.407"))

    def test_malformed_input_is_rejected(self):
        self.assertIsNone(_parse_pos("60.1"))
        self.assertIsNone(_parse_pos("ei numeroita"))


if __name__ == "__main__":
    unittest.main()
