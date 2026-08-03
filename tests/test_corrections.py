import json
import tempfile
import unittest
from pathlib import Path

from pipeline.corrections import (
    MAX_DRIFT_M,
    apply_corrections,
    load_corrections,
)
from pipeline.model import PRECISION_AREA, ParkingSpot

LAT, LON = 61.476855, 23.761579
METER = 1 / 111_000


def spot(source_id="1459", lat=LAT, lon=LON, source="tampere", merged=None):
    return ParkingSpot(
        source=source,
        source_id=source_id,
        lat=lat,
        lon=lon,
        precision=PRECISION_AREA,
        merged_from=merged or [],
    )


def entry(uid="tampere:1459", lat=LAT, lon=LON, syy="testi", toiminto="poista", **extra):
    return {
        "uid": uid,
        "toiminto": toiminto,
        "lat": lat,
        "lon": lon,
        "syy": syy,
        "lisatty": "2026-08-03",
        **extra,
    }


class RemoveCorrectionTest(unittest.TestCase):
    def test_listattu_kohde_poistuu(self):
        kept, removed, moved, skipped = apply_corrections([spot()], [entry()])
        self.assertEqual((kept, removed, moved, skipped), ([], 1, 0, 0))

    def test_muut_kohteet_jaavat(self):
        others = spot("9999", lat=61.5, lon=23.8)
        kept, removed, _, _ = apply_corrections([spot(), others], [entry()])
        self.assertEqual([s.source_id for s in kept], ["9999"])
        self.assertEqual(removed, 1)

    def test_poisto_loytyy_myos_yhdistetysta_tunnuksesta(self):
        # Deduplikoinnin ankkuri voi vaihtua ajojen välillä, jolloin sama
        # fyysinen paikka tunnetaan eri uid:llä. Ilman merged_from-hakua
        # poisto katoaisi juuri niistä kohteista, joista on eniten tietoa.
        merged = spot("3320", merged=["tampere:1459", "tampere:3320"])
        kept, removed, _, _ = apply_corrections([merged], [entry()])
        self.assertEqual((kept, removed), ([], 1))

    def test_ajautunut_kohde_jaa_poistamatta(self):
        # Turvaraja: jos uid osoittaa nyt eri paikkaan kuin poistoa
        # kirjattaessa, hiljainen poisto olisi pahin mahdollinen vika.
        moved = spot(lat=LAT + 200 * METER)
        kept, removed, _, skipped = apply_corrections([moved], [entry()])
        self.assertEqual((len(kept), removed, skipped), (1, 0, 1))

    def test_pieni_siirtyma_sallitaan(self):
        nudged = spot(lat=LAT + (MAX_DRIFT_M / 2) * METER)
        _, removed, _, skipped = apply_corrections([nudged], [entry()])
        self.assertEqual((removed, skipped), (1, 0))

    def test_ilman_koordinaattia_poisto_tehdaan_silti(self):
        # Koordinaatti on suositus eikä pakollinen: vanha rivi ei saa lakata
        # toimimasta siksi, että kenttä puuttuu.
        bare = {"uid": "tampere:1459", "toiminto": "poista", "syy": "ei koordinaattia"}
        _, removed, _, _ = apply_corrections([spot()], [bare])
        self.assertEqual(removed, 1)

    def test_tyhja_lista_ei_koske_mihinkaan(self):
        spots = [spot()]
        kept, removed, moved, skipped = apply_corrections(spots, [])
        self.assertEqual((kept, removed, moved, skipped), (spots, 0, 0, 0))


class LoadCorrectionsTest(unittest.TestCase):
    def write(self, content):
        path = Path(tempfile.mkdtemp()) / "poistetut.json"
        path.write_text(content, encoding="utf-8")
        return path

    def test_puuttuva_tiedosto_ei_ole_virhe(self):
        missing = Path(tempfile.mkdtemp()) / "ei-ole.json"
        self.assertEqual(load_corrections(missing), [])

    def test_rikkinainen_tiedosto_ei_poista_mitaan(self):
        # Kaatuminen olisi väärä reaktio: julkaisu keskeytyisi kokonaan.
        # Hiljainen ohitus on väärä toiseen suuntaan, joten se lokitetaan.
        self.assertEqual(load_corrections(self.write("{ ei json")), [])

    def test_rivit_ilman_uidia_ohitetaan(self):
        path = self.write(json.dumps([{"syy": "unohtui uid"}, entry()]))
        self.assertEqual([e["uid"] for e in load_corrections(path)], ["tampere:1459"])


class MoveCorrectionTest(unittest.TestCase):
    """Siirto on useimmiten oikeampi kuin poisto: väärä koordinaatti ei
    tarkoita, ettei paikkaa ole."""

    def move(self, **kw):
        target = {"uusi_lat": 61.475691, "uusi_lon": 23.761403, **kw}
        return entry(toiminto="siirra", **target)

    def test_kohde_siirtyy_annettuun_sijaintiin(self):
        target = spot()
        kept, removed, moved, skipped = apply_corrections([target], [self.move()])
        self.assertEqual((len(kept), removed, moved, skipped), (1, 0, 1, 0))
        self.assertAlmostEqual(target.lat, 61.475691)
        self.assertAlmostEqual(target.lon, 23.761403)

    def test_siirto_sailyttaa_kohteen_muut_tiedot(self):
        target = spot()
        target.capacity = 1
        apply_corrections([target], [self.move()])
        self.assertEqual(target.capacity, 1)
        self.assertEqual(target.source, "tampere")

    def test_ilman_uutta_sijaintia_ei_siirreta(self):
        target = spot()
        _, _, moved, skipped = apply_corrections(
            [target], [entry(toiminto="siirra")]
        )
        self.assertEqual((moved, skipped), (0, 1))
        self.assertAlmostEqual(target.lat, LAT)

    def test_suomen_ulkopuolinen_kohde_ei_kelpaa(self):
        target = spot()
        _, _, moved, skipped = apply_corrections(
            [target], [self.move(uusi_lat=0.0, uusi_lon=0.0)]
        )
        self.assertEqual((moved, skipped), (0, 1))

    def test_tuntematon_toiminto_ohitetaan_jo_luettaessa(self):
        path = Path(tempfile.mkdtemp()) / "korjaukset.json"
        path.write_text(
            json.dumps([{"uid": "x", "toiminto": "tuhoa"}, entry()]), encoding="utf-8"
        )
        self.assertEqual([e["uid"] for e in load_corrections(path)], ["tampere:1459"])


if __name__ == "__main__":
    unittest.main()
