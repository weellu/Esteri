import unittest

from pipeline.moderate import (
    CONFIRM_MAX_DISTANCE_M,
    build_report,
    moderate,
)
from pipeline.signals import apply_signals
from pipeline.sources.users import CONFIRM_THRESHOLD

# Tampereen keskustori. Metrin siirtymä leveysasteessa on n. 1/111000.
LAT, LON = 61.4980, 23.7610
METER = 1 / 111_000


def submission(sid, kind, *, lat=LAT, lon=LON, target=None, note=None, accuracy=8.0):
    return {
        "id": sid,
        "kind": kind,
        "lat": lat,
        "lon": lon,
        "target_uid": target,
        "note": note,
        "accuracy_m": accuracy,
        "created_at": "2026-08-03T10:00:00Z",
    }


def empty_state():
    return {"high_water_mark": 0, "signals": {}}


def empty_contributions():
    return {"type": "FeatureCollection", "features": []}


class NewSpotTest(unittest.TestCase):
    def test_ilmoitus_kaukana_tunnetuista_luo_uuden_kohteen(self):
        contributions = empty_contributions()
        result = moderate(
            [submission(1, "new", note="P-talon 2. krs")],
            dataset=[("osm:node/1", LAT + 500 * METER, LON)],
            contributions=contributions,
            state=empty_state(),
        )

        self.assertEqual(len(result.new_spots), 1)
        self.assertEqual(len(contributions["features"]), 1)
        props = contributions["features"][0]["properties"]
        self.assertEqual(props["reports"], 1)
        # Saateteksti ei saa päätyä julkaistavaan aineistoon.
        self.assertNotIn("note", props)
        self.assertNotIn("P-talon", str(contributions))

    def test_ilmoitus_tunnetun_kohteen_paalla_on_vahvistus_ei_uusi_kohde(self):
        contributions = empty_contributions()
        state = empty_state()
        result = moderate(
            [submission(1, "new", lat=LAT + 10 * METER)],
            dataset=[("osm:node/1", LAT, LON)],
            contributions=contributions,
            state=state,
        )

        self.assertEqual(result.new_spots, [])
        self.assertEqual(contributions["features"], [])
        self.assertEqual(result.confirmations, 1)
        self.assertEqual(state["signals"]["osm:node/1"]["present"], 1)

    def test_kaksi_ilmoitusta_samasta_paikasta_yhdistyy(self):
        contributions = empty_contributions()
        result = moderate(
            [
                submission(1, "new"),
                submission(2, "new", lat=LAT + 5 * METER),
            ],
            dataset=[],
            contributions=contributions,
            state=empty_state(),
        )

        self.assertEqual(len(contributions["features"]), 1)
        self.assertEqual(contributions["features"][0]["properties"]["reports"], 2)
        self.assertEqual(len(result.new_spots), 1)
        self.assertEqual(len(result.grown), 1)

    def test_kaukana_toisistaan_olevat_ilmoitukset_pysyvat_erillisina(self):
        contributions = empty_contributions()
        moderate(
            [
                submission(1, "new"),
                submission(2, "new", lat=LAT + 40 * METER),
            ],
            dataset=[],
            contributions=contributions,
            state=empty_state(),
        )

        self.assertEqual(len(contributions["features"]), 2)

    def test_kolmas_ilmoitus_nostaa_vahvistetuksi(self):
        contributions = empty_contributions()
        result = moderate(
            [submission(i, "new", lat=LAT + i * METER) for i in range(1, CONFIRM_THRESHOLD + 1)],
            dataset=[],
            contributions=contributions,
            state=empty_state(),
        )

        self.assertEqual(len(result.promoted), 1)
        self.assertEqual(
            contributions["features"][0]["properties"]["reports"], CONFIRM_THRESHOLD
        )


class ConfirmationTest(unittest.TestCase):
    def test_vahvistus_kasvattaa_laskuria(self):
        state = empty_state()
        moderate(
            [submission(1, "present", target="osm:node/1")],
            dataset=[("osm:node/1", LAT, LON)],
            contributions=empty_contributions(),
            state=state,
        )
        self.assertEqual(state["signals"]["osm:node/1"], {"present": 1, "missing": 0, "last": "2026-08-03"})

    def test_kiisto_kirjataan_erikseen(self):
        state = empty_state()
        result = moderate(
            [submission(1, "missing", target="osm:node/1")],
            dataset=[("osm:node/1", LAT, LON)],
            contributions=empty_contributions(),
            state=state,
        )
        self.assertEqual(result.disputes, 1)
        self.assertEqual(state["signals"]["osm:node/1"]["missing"], 1)

    def test_vahvistus_kaukaa_hylataan(self):
        state = empty_state()
        far = LAT + (CONFIRM_MAX_DISTANCE_M + 50) * METER
        result = moderate(
            [submission(1, "present", lat=far, target="osm:node/1")],
            dataset=[("osm:node/1", LAT, LON)],
            contributions=empty_contributions(),
            state=state,
        )
        self.assertEqual(result.confirmations, 0)
        self.assertEqual(state["signals"], {})
        self.assertEqual(len(result.rejected), 1)

    def test_tuntematon_kohde_hyvaksytaan_koska_uid_voi_palata(self):
        state = empty_state()
        moderate(
            [submission(1, "present", target="osm:node/999")],
            dataset=[("osm:node/1", LAT, LON)],
            contributions=empty_contributions(),
            state=state,
        )
        self.assertEqual(state["signals"]["osm:node/999"]["present"], 1)


class ValidationTest(unittest.TestCase):
    def test_suomen_ulkopuolinen_koordinaatti_hylataan(self):
        result = moderate(
            [submission(1, "new", lat=48.85, lon=2.35)],
            dataset=[],
            contributions=empty_contributions(),
            state=empty_state(),
        )
        self.assertEqual(len(result.rejected), 1)
        self.assertEqual(result.new_spots, [])

    def test_huono_paikannustarkkuus_hylataan(self):
        result = moderate(
            [submission(1, "new", accuracy=400.0)],
            dataset=[],
            contributions=empty_contributions(),
            state=empty_state(),
        )
        self.assertEqual(len(result.rejected), 1)

    def test_hylatty_lahetys_ei_esta_muiden_kasittelya(self):
        contributions = empty_contributions()
        result = moderate(
            [submission(1, "new", lat=48.85, lon=2.35), submission(2, "new")],
            dataset=[],
            contributions=contributions,
            state=empty_state(),
        )
        self.assertEqual(len(result.rejected), 1)
        self.assertEqual(len(contributions["features"]), 1)


class HighWaterMarkTest(unittest.TestCase):
    def test_lukukohta_siirtyy_suurimpaan_kasiteltyyn(self):
        state = empty_state()
        moderate(
            [submission(7, "new"), submission(12, "new", lat=LAT + 200 * METER)],
            dataset=[],
            contributions=empty_contributions(),
            state=state,
        )
        self.assertEqual(state["high_water_mark"], 12)

    def test_lukukohta_siirtyy_myos_hylatyista(self):
        # Muuten hylätty lähetys haettaisiin jonosta joka viikko uudelleen.
        state = empty_state()
        moderate(
            [submission(5, "new", lat=48.85, lon=2.35)],
            dataset=[],
            contributions=empty_contributions(),
            state=state,
        )
        self.assertEqual(state["high_water_mark"], 5)


class ReportTest(unittest.TestCase):
    def test_kuvaus_sisaltaa_saatteen_ja_karttalinkin(self):
        result = moderate(
            [submission(1, "new", note="Hissin vieressä")],
            dataset=[("osm:node/1", LAT + 500 * METER, LON)],
            contributions=empty_contributions(),
            state=empty_state(),
        )
        report = build_report(result)
        self.assertIn("Hissin vieressä", report)
        self.assertIn("openstreetmap.org", report)
        self.assertIn("u00001", report)


class SignalApplicationTest(unittest.TestCase):
    """apply_signals liittää laskurit valmiiseen kohteeseen."""

    def _spot(self, uid="osm:node/1", merged_from=None):
        from pipeline.model import ParkingSpot

        source, source_id = uid.split(":", 1)
        return ParkingSpot(
            source=source,
            source_id=source_id,
            lat=LAT,
            lon=LON,
            precision="space",
            merged_from=merged_from if merged_from is not None else [uid],
        )

    def test_laskurit_liitetaan_uid_osumalla(self):
        spot = self._spot()
        apply_signals([spot], {"osm:node/1": {"present": 4, "missing": 1}})
        self.assertEqual(spot.confirmations, 4)
        self.assertEqual(spot.disputes, 1)

    def test_signaali_seuraa_kohdetta_vaikka_ankkuri_vaihtuu(self):
        # Kohde tunnetaan nyt Tampereen uid:llä, mutta käyttäjä vahvisti sen
        # kun ankkurina oli OSM-piste. Signaali ei saa kadota.
        spot = self._spot("tampere:5", merged_from=["osm:node/1", "tampere:5"])
        apply_signals([spot], {"osm:node/1": {"present": 2, "missing": 0}})
        self.assertEqual(spot.confirmations, 2)

    def test_sama_signaali_ei_lasketa_kahdesti(self):
        # merged_from sisältää myös ankkurin oman uid:n.
        spot = self._spot("osm:node/1", merged_from=["osm:node/1"])
        apply_signals([spot], {"osm:node/1": {"present": 3, "missing": 0}})
        self.assertEqual(spot.confirmations, 3)

    def test_nolla_ei_paady_ulostuloon(self):
        spot = self._spot()
        apply_signals([spot], {"osm:node/1": {"present": 0, "missing": 0}})
        self.assertIsNone(spot.confirmations)
        self.assertIsNone(spot.disputes)

    def test_orpo_signaali_raportoidaan_mutta_ei_kaada(self):
        spot = self._spot()
        matched, orphans = apply_signals([spot], {"turku:404": {"present": 1}})
        self.assertEqual(matched, 0)
        self.assertEqual(orphans, 1)


if __name__ == "__main__":
    unittest.main()
