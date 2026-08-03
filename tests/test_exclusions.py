import json
import tempfile
import unittest
from pathlib import Path

from pipeline.exclusions import MAX_DRIFT_M, apply_exclusions, load_exclusions
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


def entry(uid="tampere:1459", lat=LAT, lon=LON, syy="testi"):
    return {"uid": uid, "lat": lat, "lon": lon, "syy": syy, "lisatty": "2026-08-03"}


class ApplyExclusionsTest(unittest.TestCase):
    def test_listattu_kohde_poistuu(self):
        kept, removed, skipped = apply_exclusions([spot()], [entry()])
        self.assertEqual((kept, removed, skipped), ([], 1, 0))

    def test_muut_kohteet_jaavat(self):
        others = spot("9999", lat=61.5, lon=23.8)
        kept, removed, _ = apply_exclusions([spot(), others], [entry()])
        self.assertEqual([s.source_id for s in kept], ["9999"])
        self.assertEqual(removed, 1)

    def test_poisto_loytyy_myos_yhdistetysta_tunnuksesta(self):
        # Deduplikoinnin ankkuri voi vaihtua ajojen välillä, jolloin sama
        # fyysinen paikka tunnetaan eri uid:llä. Ilman merged_from-hakua
        # poisto katoaisi juuri niistä kohteista, joista on eniten tietoa.
        merged = spot("3320", merged=["tampere:1459", "tampere:3320"])
        kept, removed, _ = apply_exclusions([merged], [entry()])
        self.assertEqual((kept, removed), ([], 1))

    def test_ajautunut_kohde_jaa_poistamatta(self):
        # Turvaraja: jos uid osoittaa nyt eri paikkaan kuin poistoa
        # kirjattaessa, hiljainen poisto olisi pahin mahdollinen vika.
        moved = spot(lat=LAT + 200 * METER)
        kept, removed, skipped = apply_exclusions([moved], [entry()])
        self.assertEqual((len(kept), removed, skipped), (1, 0, 1))

    def test_pieni_siirtyma_sallitaan(self):
        nudged = spot(lat=LAT + (MAX_DRIFT_M / 2) * METER)
        _, removed, skipped = apply_exclusions([nudged], [entry()])
        self.assertEqual((removed, skipped), (1, 0))

    def test_ilman_koordinaattia_poisto_tehdaan_silti(self):
        # Koordinaatti on suositus eikä pakollinen: vanha rivi ei saa lakata
        # toimimasta siksi, että kenttä puuttuu.
        bare = {"uid": "tampere:1459", "syy": "ei koordinaattia"}
        _, removed, _ = apply_exclusions([spot()], [bare])
        self.assertEqual(removed, 1)

    def test_tyhja_lista_ei_koske_mihinkaan(self):
        spots = [spot()]
        kept, removed, skipped = apply_exclusions(spots, [])
        self.assertEqual((kept, removed, skipped), (spots, 0, 0))


class LoadExclusionsTest(unittest.TestCase):
    def write(self, content):
        path = Path(tempfile.mkdtemp()) / "poistetut.json"
        path.write_text(content, encoding="utf-8")
        return path

    def test_puuttuva_tiedosto_ei_ole_virhe(self):
        missing = Path(tempfile.mkdtemp()) / "ei-ole.json"
        self.assertEqual(load_exclusions(missing), [])

    def test_rikkinainen_tiedosto_ei_poista_mitaan(self):
        # Kaatuminen olisi väärä reaktio: julkaisu keskeytyisi kokonaan.
        # Hiljainen ohitus on väärä toiseen suuntaan, joten se lokitetaan.
        self.assertEqual(load_exclusions(self.write("{ ei json")), [])

    def test_rivit_ilman_uidia_ohitetaan(self):
        path = self.write(json.dumps([{"syy": "unohtui uid"}, entry()]))
        self.assertEqual([e["uid"] for e in load_exclusions(path)], ["tampere:1459"])


if __name__ == "__main__":
    unittest.main()
