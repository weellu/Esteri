import json
import tempfile
import unittest
from pathlib import Path

from pipeline.signals import apply_relocations, apply_signals, demote_disputed
from pipeline.model import (
    PRECISION_AREA,
    PRECISION_SPACE,
    VERIFICATION_CONFIRMED,
    VERIFICATION_DISPUTED,
    VERIFICATION_REPORTED,
    ParkingSpot,
    median_capacity,
)
from pipeline.sources import users


def write(features):
    path = Path(tempfile.mkdtemp()) / "kayttajat.geojson"
    path.write_text(
        json.dumps({"type": "FeatureCollection", "features": features}),
        encoding="utf-8",
    )
    return path


def feature(spot_id="u00001", lat=61.498, lon=23.761, **props):
    return {
        "type": "Feature",
        "geometry": {"type": "Point", "coordinates": [lon, lat]},
        "properties": {"id": spot_id, **props},
    }


class UsersSourceTest(unittest.TestCase):
    def test_puuttuva_tiedosto_ei_ole_virhe(self):
        # Normaali tilanne ennen ensimmäistä hyväksyttyä ilmoitusta.
        missing = Path(tempfile.mkdtemp()) / "ei-ole.geojson"
        self.assertEqual(users.load(missing), [])

    def test_yksi_ilmoitus_on_vahvistamaton_ja_sijainniltaan_epatarkka(self):
        spots = users.load(write([feature(reports=1)]))
        self.assertEqual(len(spots), 1)
        self.assertEqual(spots[0].verification, VERIFICATION_REPORTED)
        # Yksittäisen ilmoituksen sijaintivirhettä ei voi arvioida mitenkään,
        # joten se ei saa luvata tarkkaa paikkaa.
        self.assertEqual(spots[0].precision, PRECISION_AREA)
        self.assertEqual(spots[0].confirmations, 1)
        self.assertEqual(spots[0].uid, "users:u00001")

    def test_kynnyksen_ylittava_maara_nostaa_tarkaksi_paikaksi(self):
        spots = users.load(write([feature(reports=users.CONFIRM_THRESHOLD)]))
        self.assertEqual(spots[0].verification, VERIFICATION_CONFIRMED)
        self.assertEqual(spots[0].precision, PRECISION_SPACE)

    def test_koordinaatti_luetaan_geojson_jarjestyksessa(self):
        # GeoJSON on aina [lon, lat]. Väärinpäin luettuna Tampere olisi Somaliassa.
        spots = users.load(write([feature(lat=61.498, lon=23.761, reports=1)]))
        self.assertAlmostEqual(spots[0].lat, 61.498)
        self.assertAlmostEqual(spots[0].lon, 23.761)

    def test_saateteksti_ei_paady_kohteeseen(self):
        # Moderoimatonta käyttäjätekstiä ei julkaista ODbL-aineistossa.
        spots = users.load(write([feature(reports=1, note="jotain rumaa")]))
        self.assertIsNone(spots[0].name)

    def test_ihmisen_kasin_lisaama_nimi_kelpaa(self):
        spots = users.load(write([feature(reports=1, name="Kauppakeskuksen P-taso")]))
        self.assertEqual(spots[0].name, "Kauppakeskuksen P-taso")

    def test_kelvoton_kohde_ohitetaan_muita_kaatamatta(self):
        spots = users.load(
            write(
                [
                    {"type": "Feature", "geometry": {}, "properties": {}},
                    feature("u00002", reports=1),
                ]
            )
        )
        self.assertEqual([s.source_id for s in spots], ["u00002"])

    def test_alueen_ulkopuolinen_koordinaatti_ohitetaan(self):
        spots = users.load(write([feature(lat=999.0, reports=1)]))
        self.assertEqual(spots, [])

    def test_puuttuva_reports_tulkitaan_yhdeksi(self):
        spots = users.load(write([feature()]))
        self.assertEqual(spots[0].verification, VERIFICATION_REPORTED)


class UsersAuthorityTest(unittest.TestCase):
    def test_kayttajalahde_ei_ohita_avointa_aineistoa_yhdistettaessa(self):
        from pipeline.dedupe import deduplicate
        from pipeline.model import ParkingSpot

        official = ParkingSpot(
            source="tampere",
            source_id="1",
            lat=61.498,
            lon=23.761,
            precision=PRECISION_SPACE,
            capacity=3,
        )
        reported = ParkingSpot(
            source="users",
            source_id="u00001",
            lat=61.49801,
            lon=23.76101,
            precision=PRECISION_AREA,
            verification=VERIFICATION_REPORTED,
            confirmations=1,
        )

        merged = deduplicate([official, reported])
        self.assertEqual(len(merged), 1)
        # Kuntarekisterin kohde voittaa: sen sijainti, sen metatiedot, eikä
        # yhden käyttäjän ilmoitus merkitse sitä vahvistamattomaksi.
        self.assertEqual(merged[0].source, "tampere")
        self.assertEqual(merged[0].capacity, 3)
        self.assertIsNone(merged[0].verification)



class CapacityMedianTest(unittest.TestCase):
    """Ruutumäärä on ilmoittajien enemmistön näkemys."""

    def test_yksi_ilmoitus_kelpaa_sellaisenaan(self):
        self.assertEqual(median_capacity([3]), 3)

    def test_yksi_vaarin_laskenut_ei_siirra_tulosta(self):
        self.assertEqual(median_capacity([3, 3, 2]), 3)

    def test_parillisella_maaralla_luvataan_vahempi(self):
        # Käyttäjä pettyy vähemmän löytäessään enemmän kuin luvattiin.
        self.assertEqual(median_capacity([2, 3]), 2)

    def test_todellinen_muutos_menee_lapi_ikkunan_verran(self):
        # Ruutuja maalattiin yksi pois: viisi tuoretta havaintoa riittää,
        # vaikka vanhoja olisi enemmän.
        self.assertEqual(median_capacity([3] * 6 + [2] * 5), 2)

    def test_ei_havaintoja_tarkoittaa_ei_tietoa(self):
        self.assertIsNone(median_capacity([]))

    def test_roska_ei_kaada_eika_kelpaa(self):
        self.assertIsNone(median_capacity([0, -1, "kolme", None]))


class CapacityFromReportsTest(unittest.TestCase):
    def test_ilmoitettu_maara_paatyy_kohteeseen(self):
        spots = users.load(write([feature(reports=3, capacities=[3, 3, 2])]))
        self.assertEqual(spots[0].capacity, 3)

    def test_ilman_maaraa_kentta_jaa_tyhjaksi(self):
        spots = users.load(write([feature(reports=1)]))
        self.assertIsNone(spots[0].capacity)


class SignalCapacityTest(unittest.TestCase):
    """Maastohavainnon ja rekisterin suhde."""

    def spot(self, capacity=None):
        return ParkingSpot(
            source="tampere",
            source_id="1",
            lat=61.498,
            lon=23.761,
            precision=PRECISION_AREA,
            capacity=capacity,
        )

    def test_yksi_havainto_tayttaa_tyhjan_kentan(self):
        spot = self.spot(capacity=None)
        apply_signals([spot], {"tampere:1": {"present": 1, "capacities": [2]}})
        self.assertEqual(spot.capacity, 2)

    def test_yksi_havainto_ei_ylikirjoita_rekisteria(self):
        # Ohikulkija voi olla väärässä. Rekisterin kumoaminen yhden napautuksen
        # perusteella olisi huonompi vaihtokauppa kuin odottaa toista.
        spot = self.spot(capacity=4)
        apply_signals([spot], {"tampere:1": {"present": 1, "capacities": [2]}})
        self.assertEqual(spot.capacity, 4)

    def test_kaksi_havaintoa_voittaa_rekisterin(self):
        spot = self.spot(capacity=4)
        apply_signals([spot], {"tampere:1": {"present": 2, "capacities": [2, 2]}})
        self.assertEqual(spot.capacity, 2)


class ConfirmationSummingTest(unittest.TestCase):
    def test_vahvistusnappi_ei_pienenna_vahvistusten_maaraa(self):
        # Aiemmin signaali ylikirjoitti lähteen lukeman: kolmen ilmoituksen
        # kohde putosi yhteen, kun joku painoi "Paikka on".
        spot = ParkingSpot(
            source="users",
            source_id="u00001",
            lat=61.46,
            lon=24.05,
            precision=PRECISION_AREA,
            verification=VERIFICATION_REPORTED,
            confirmations=3,
        )
        apply_signals([spot], {"users:u00001": {"present": 1, "missing": 0}})
        self.assertEqual(spot.confirmations, 4)


class DemoteDisputedTest(unittest.TestCase):
    """Kiiston purku: vahvistus ei saa olla yksisuuntainen."""

    def spot(self, source, confirmations, disputes, verification=None):
        return ParkingSpot(
            source=source,
            source_id="1",
            lat=61.5,
            lon=23.8,
            precision=PRECISION_SPACE,
            verification=verification,
            confirmations=confirmations,
            disputes=disputes,
        )

    def test_yksi_kiisto_ei_riita_mihinkaan(self):
        # Yksi "ei löydy" voi tarkoittaa myös väärästä kohdasta etsimistä.
        spot = self.spot("users", 1, 1, VERIFICATION_CONFIRMED)
        kept, demoted, dropped = demote_disputed([spot])
        self.assertEqual((len(kept), demoted, dropped), (1, 0, 0))
        self.assertEqual(spot.verification, VERIFICATION_CONFIRMED)

    def test_vahvistuksia_enemman_kuin_kiistoja_ei_pura(self):
        spot = self.spot("users", 3, 2, VERIFICATION_CONFIRMED)
        _, demoted, dropped = demote_disputed([spot])
        self.assertEqual((demoted, dropped), (0, 0))

    def test_kiistojen_enemmisto_alentaa_kayttajan_kohteen(self):
        spot = self.spot("users", 1, 2, VERIFICATION_CONFIRMED)
        kept, demoted, dropped = demote_disputed([spot])
        self.assertEqual((len(kept), demoted, dropped), (1, 1, 0))
        self.assertEqual(spot.verification, VERIFICATION_REPORTED)
        # Tarkkuus seuraa vahvistusta: kiistelty ei saa luvata tarkkaa ruutua.
        self.assertEqual(spot.precision, PRECISION_AREA)

    def test_selva_enemmisto_poistaa_kayttajan_kohteen(self):
        spot = self.spot("users", 1, 3, VERIFICATION_CONFIRMED)
        kept, _, dropped = demote_disputed([spot])
        self.assertEqual((kept, dropped), ([], 1))

    def test_avoimen_aineiston_kohdetta_ei_poisteta_vaan_merkitaan(self):
        # Seuraava ajo hakisi sen joka tapauksessa takaisin lähteestä, ja
        # kunnan rekisteri voi silti olla oikeassa.
        spot = self.spot("tampere", 0, 3)
        kept, demoted, dropped = demote_disputed([spot])
        self.assertEqual((len(kept), demoted, dropped), (1, 1, 0))
        self.assertEqual(spot.verification, VERIFICATION_DISPUTED)


class ApplyRelocationsTest(unittest.TestCase):
    """Tarkennus siirtää kohteen sinne, missä ruutu oikeasti on."""

    LAT, LON = 61.5, 23.8
    NEAR = [61.5010, 23.8010]
    NEAR2 = [61.5012, 23.8012]

    def spot(self, precision):
        return ParkingSpot(
            source="tampere",
            source_id="1",
            lat=self.LAT,
            lon=self.LON,
            precision=precision,
        )

    def test_yksi_tarkennus_siirtaa_alueen_keskipisteen(self):
        # Keskipiste on jo valmiiksi arvaus, joten yksi maastomittaus on
        # siitä parannus vaikka sekin heittäisi.
        spot = self.spot(PRECISION_AREA)
        moved, _ = apply_relocations(
            [spot], {"tampere:1": {"relocations": [self.NEAR]}}
        )
        self.assertEqual(moved, 1)
        self.assertAlmostEqual(spot.lat, self.NEAR[0])

    def test_yksi_tarkennus_ei_siirra_tarkkaa_ruutua(self):
        # Ruudun sijainti on kerran jo todettu; yhden ihmisen napautus ei
        # saa kumota sitä.
        spot = self.spot(PRECISION_SPACE)
        moved, _ = apply_relocations(
            [spot], {"tampere:1": {"relocations": [self.NEAR]}}
        )
        self.assertEqual(moved, 0)
        self.assertAlmostEqual(spot.lat, self.LAT)

    def test_kaksi_tarkennusta_siirtaa_tarkankin_ruudun(self):
        spot = self.spot(PRECISION_SPACE)
        moved, _ = apply_relocations(
            [spot], {"tampere:1": {"relocations": [self.NEAR, self.NEAR2]}}
        )
        self.assertEqual(moved, 1)

    def test_sijainti_on_havaintojen_keskiarvo(self):
        spot = self.spot(PRECISION_AREA)
        apply_relocations(
            [spot], {"tampere:1": {"relocations": [self.NEAR, self.NEAR2]}}
        )
        self.assertAlmostEqual(spot.lat, (self.NEAR[0] + self.NEAR2[0]) / 2, places=6)

    def test_kaksi_tarkennusta_nostaa_alueen_ruuduksi(self):
        # Lähetyksen tarkkuusraja on 50 m, joten yksi mittaus ei riitä
        # lupaamaan "tämä on itse ruutu". Kaksi riippumatonta on jo mittaus.
        spot = self.spot(PRECISION_AREA)
        _, sharpened = apply_relocations(
            [spot], {"tampere:1": {"relocations": [self.NEAR, self.NEAR2]}}
        )
        self.assertEqual(sharpened, 1)
        self.assertEqual(spot.precision, PRECISION_SPACE)

    def test_yksi_tarkennus_ei_nosta_tarkkuutta(self):
        spot = self.spot(PRECISION_AREA)
        _, sharpened = apply_relocations(
            [spot], {"tampere:1": {"relocations": [self.NEAR]}}
        )
        self.assertEqual(sharpened, 0)
        self.assertEqual(spot.precision, PRECISION_AREA)


if __name__ == "__main__":
    unittest.main()
