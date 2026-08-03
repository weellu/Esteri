"""Käyttäjien lähetysten automaattinen käsittely ja moderointipaketin kokoaminen.

Ajetaan viikoittain GitHub Actionsissa. Lukee Workerin jonon, soveltaa
automaattisäännöt ja kirjoittaa kaksi versionhallittua tiedostoa:

    contributions/kayttajat.geojson   hyväksytyt ja ilmoitetut kohteet
    contributions/tila.json           vahvistuslaskurit ja jonon lukukohta

Näistä avataan PR. GitHub piirtää .geojson-tiedoston kartaksi, joten moderaattori
näkee pisteet kartalla suoraan diffissä — erillistä moderointikäyttöliittymää
ei tarvita. Hyväksyntä on merge, hylkäys on PR:n sulkeminen, ja yksittäisen
roskakohteen voi poistaa muokkaamalla tiedostoa PR:ssä.

**Moderointi ei ole portti.** Yksittäinen ilmoitus julkaistaan heti tilassa
`reported`, jonka sovellus esittää erikseen vahvistamattomana. Ihmisen tehtävä
ei ole päättää onko paikka olemassa — sitä ei ruudulta näe — vaan poistaa
ilkivalta. Jos moderointi olisi portti, jonon pituus kasvaisi suoraan sen
mukaan, ehtiikö kukaan katsoa sitä, ja ominaisuus kuolisi ensimmäiseen
kiireiseen kuukauteen.

Sisältöä ei koskaan julkaista käyttäjän kirjoittamana. Lähetyksen saateteksti
näkyy vain PR:n kuvauksessa moderaattorille eikä päädy aineistoon, joka leviää
ODbL:n alla eteenpäin.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Optional

from .geo import haversine_m
from .signals import STATE_PATH, load_state, save_state
from .sources.users import CONFIRM_THRESHOLD, CONTRIBUTIONS_PATH

log = logging.getLogger("moderate")

# Ilmoitus näin lähellä olemassa olevaa kohdetta ei ole uusi paikka vaan
# vahvistus. Sama kynnys kuin deduplikoinnin tarkka säde: jos aineistossa jo
# on kohde tässä, käyttäjä on sen kohdalla.
EXISTING_RADIUS_M = 25.0

# Kahden käyttäjäilmoituksen yhdistäminen samaksi paikaksi. Tiukempi kuin
# EXISTING_RADIUS_M, koska tässä ei ole mitään ulkopuolista vahvistusta:
# löysä säde sulauttaisi vierekkäiset invaruudut yhdeksi.
CLUSTER_RADIUS_M = 15.0

# Vahvistus kauempaa kuin tämä hylätään. Käyttäjän on oltava paikan päällä —
# muuten vahvistus ei kerro mitään maastosta.
CONFIRM_MAX_DISTANCE_M = 100.0

# Paikannustarkkuus, jota huonommalla lähetystä ei oteta vastaan. Sisätiloissa
# tai kaupunkikuilussa GPS voi heittää satoja metrejä, jolloin lähetys
# kohdistuu käytännössä satunnaiseen paikkaan.
MAX_GPS_ACCURACY_M = 50.0

KIND_NEW = "new"
KIND_PRESENT = "present"
KIND_MISSING = "missing"


class ModerationResult:
    def __init__(self) -> None:
        self.new_spots: list[dict[str, Any]] = []
        self.grown: list[dict[str, Any]] = []
        self.promoted: list[dict[str, Any]] = []
        self.confirmations = 0
        self.disputes = 0
        self.rejected: list[tuple[int, str]] = []

    @property
    def needs_pr(self) -> bool:
        return bool(self.new_spots or self.grown or self.promoted) or bool(
            self.confirmations or self.disputes
        )


def load_dataset(path: Path) -> list[tuple[str, float, float]]:
    """Lue julkaistu aineisto (uid, lat, lon) -kolmikoiksi.

    Tarvitaan sen ratkaisemiseen, onko ilmoitus uusi paikka vai vahvistus
    olemassa olevaan. Ilman aineistoa kumpaakaan ei voi päätellä, joten
    puuttuva tiedosto on virhe eikä tyhjä lista.
    """
    payload = json.loads(path.read_text(encoding="utf-8"))
    out: list[tuple[str, float, float]] = []
    for feature in payload.get("features", []):
        props = feature.get("properties", {})
        source = props.get("source")
        source_id = props.get("source_id")
        if source is None or source_id is None:
            continue
        lon, lat = feature["geometry"]["coordinates"][:2]
        out.append((f"{source}:{source_id}", float(lat), float(lon)))
    return out


def _nearest(
    lat: float, lon: float, candidates: Iterable[tuple[str, float, float]]
) -> tuple[Optional[str], float]:
    best_uid: Optional[str] = None
    best = float("inf")
    for uid, clat, clon in candidates:
        distance = haversine_m(lat, lon, clat, clon)
        if distance < best:
            best, best_uid = distance, uid
    return best_uid, best


def load_contributions(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"type": "FeatureCollection", "features": []}
    return json.loads(path.read_text(encoding="utf-8"))


def _features(contributions: dict[str, Any]) -> list[dict[str, Any]]:
    return contributions.setdefault("features", [])


def _bump_signal(
    state: dict[str, Any],
    uid: str,
    key: str,
    when: str,
    capacity: Optional[int] = None,
) -> None:
    signal = state["signals"].setdefault(uid, {"present": 0, "missing": 0})
    signal[key] = int(signal.get(key, 0)) + 1
    signal["last"] = when
    # Ruutumäärät kertyvät listaksi eikä yhdeksi arvoksi: mediaani tarvitsee
    # havainnot, ja lista näyttää PR-diffissä suoraan, mihin luku perustuu.
    if capacity is not None:
        signal.setdefault("capacities", []).append(int(capacity))


def _next_id(features: list[dict[str, Any]]) -> str:
    used = 0
    for feature in features:
        raw = str(feature.get("properties", {}).get("id", ""))
        if raw.startswith("u"):
            try:
                used = max(used, int(raw[1:]))
            except ValueError:
                continue
    return f"u{used + 1:05d}"


def _validate(submission: dict[str, Any]) -> Optional[str]:
    """Palauta hylkäyksen syy, tai None jos lähetys kelpaa."""
    kind = submission.get("kind")
    if kind not in (KIND_NEW, KIND_PRESENT, KIND_MISSING):
        return f"tuntematon laji {kind!r}"
    try:
        lat = float(submission["lat"])
        lon = float(submission["lon"])
    except (KeyError, TypeError, ValueError):
        return "koordinaatti puuttuu tai on kelvoton"
    if not (59.0 <= lat <= 70.5) or not (19.0 <= lon <= 32.0):
        return "koordinaatti Suomen ulkopuolella"
    accuracy = submission.get("accuracy_m")
    if accuracy is not None and float(accuracy) > MAX_GPS_ACCURACY_M:
        return f"paikannustarkkuus {float(accuracy):.0f} m"
    if kind in (KIND_PRESENT, KIND_MISSING) and not submission.get("target_uid"):
        return "vahvistuksesta puuttuu kohde"
    return None


def moderate(
    submissions: list[dict[str, Any]],
    dataset: list[tuple[str, float, float]],
    contributions: dict[str, Any],
    state: dict[str, Any],
) -> ModerationResult:
    """Sovella automaattisäännöt lähetyksiin.

    Lähetykset käsitellään id-järjestyksessä, jotta saman ajon sisällä tulleet
    ilmoitukset samasta paikasta klusteroituvat keskenään: toinen ilmoitus
    kiinnittyy ensimmäisen luomaan kohteeseen eikä synnytä omaansa.
    """
    result = ModerationResult()
    features = _features(contributions)
    dataset_index = {uid: (lat, lon) for uid, lat, lon in dataset}

    for submission in sorted(submissions, key=lambda s: int(s["id"])):
        submission_id = int(submission["id"])
        # Lukukohta siirtyy myös hylätyistä. Muuten kelvoton lähetys haettaisiin
        # jonosta joka viikko uudelleen ja hylättäisiin uudelleen, jolloin
        # jokaisen PR:n hylkäyslista kasvaisi loputtomiin.
        state["high_water_mark"] = max(state["high_water_mark"], submission_id)

        problem = _validate(submission)
        if problem is not None:
            result.rejected.append((submission_id, problem))
            continue

        lat = float(submission["lat"])
        lon = float(submission["lon"])
        when = str(submission.get("created_at", ""))[:10]
        kind = submission["kind"]
        capacity = submission.get("capacity")
        capacity = int(capacity) if isinstance(capacity, int) and capacity > 0 else None

        if kind in (KIND_PRESENT, KIND_MISSING):
            uid = str(submission["target_uid"])
            known = dataset_index.get(uid)
            if known is not None:
                distance = haversine_m(lat, lon, known[0], known[1])
                if distance > CONFIRM_MAX_DISTANCE_M:
                    result.rejected.append(
                        (submission_id, f"vahvistus {distance:.0f} m päästä kohteesta")
                    )
                    continue
            # Tuntematon uid hyväksytään silti: kohde voi olla käyttäjän
            # aineistoversiossa mutta pudonnut tästä ajosta, ja signaali
            # kelpaa taas kun se palaa. Etäisyyttä ei silloin voi tarkistaa.
            _bump_signal(
                state,
                uid,
                "present" if kind == KIND_PRESENT else "missing",
                when,
                capacity=capacity,
            )
            if kind == KIND_PRESENT:
                result.confirmations += 1
            else:
                result.disputes += 1
            continue

        # Uusi paikka. Ensin: onko tämä oikeasti uusi?
        nearest_uid, distance = _nearest(lat, lon, dataset)
        if nearest_uid is not None and distance <= EXISTING_RADIUS_M:
            # Käyttäjä on jo tunnetun kohteen kohdalla. Arvokkaampaa kirjata
            # tämä vahvistuksena kuin luoda kilpaileva duplikaatti.
            _bump_signal(state, nearest_uid, "present", when, capacity=capacity)
            result.confirmations += 1
            continue

        existing = _nearest(
            lat,
            lon,
            [
                (
                    f["properties"]["id"],
                    f["geometry"]["coordinates"][1],
                    f["geometry"]["coordinates"][0],
                )
                for f in features
            ],
        )
        if existing[0] is not None and existing[1] <= CLUSTER_RADIUS_M:
            feature = next(f for f in features if f["properties"]["id"] == existing[0])
            props = feature["properties"]
            reports = int(props.get("reports", 1))
            # Sijainti on ilmoitusten liukuva keskiarvo. Yksittäisen GPS-mittauksen
            # virhe on satunnainen, joten keskiarvo tarkentuu ilmoitusten myötä.
            coords = feature["geometry"]["coordinates"]
            coords[0] = round((coords[0] * reports + lon) / (reports + 1), 7)
            coords[1] = round((coords[1] * reports + lat) / (reports + 1), 7)
            props["reports"] = reports + 1
            props["last_seen"] = when
            if capacity is not None:
                props.setdefault("capacities", []).append(capacity)
            entry = {
                "id": props["id"],
                "lat": coords[1],
                "lon": coords[0],
                "reports": props["reports"],
                "note": submission.get("note"),
                "distance": distance,
            }
            if reports + 1 == CONFIRM_THRESHOLD:
                result.promoted.append(entry)
            else:
                result.grown.append(entry)
            continue

        spot_id = _next_id(features)
        features.append(
            {
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [round(lon, 7), round(lat, 7)]},
                "properties": {
                    "id": spot_id,
                    "reports": 1,
                    "first_seen": when,
                    "last_seen": when,
                    **({"capacities": [capacity]} if capacity is not None else {}),
                },
            }
        )
        result.new_spots.append(
            {
                "id": spot_id,
                "lat": lat,
                "lon": lon,
                "reports": 1,
                "note": submission.get("note"),
                "distance": distance,
            }
        )

    features.sort(key=lambda f: f["properties"]["id"])
    return result


def write_contributions(contributions: dict[str, Any], path: Path) -> None:
    contributions["type"] = "FeatureCollection"
    contributions["metadata"] = {
        "kuvaus": "Käyttäjien ilmoittamat invapaikat. Moderoitu PR-katselmoinnissa.",
        "license": "ODbL-1.0",
        "count": len(contributions.get("features", [])),
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(contributions, ensure_ascii=False, indent=1) + "\n",
        encoding="utf-8",
    )


def _map_link(lat: float, lon: float) -> str:
    return f"https://www.openstreetmap.org/?mlat={lat:.6f}&mlon={lon:.6f}#map=19/{lat:.6f}/{lon:.6f}"


def _entry_lines(entries: list[dict[str, Any]]) -> list[str]:
    lines = []
    for entry in entries:
        lines.append(
            f"- **{entry['id']}** · [{entry['lat']:.5f}, {entry['lon']:.5f}]"
            f"({_map_link(entry['lat'], entry['lon'])})"
            f" · {entry['distance']:.0f} m lähimpään tunnettuun"
            f" · {entry['reports']} ilmoitusta"
        )
        if entry.get("note"):
            # Saate näytetään vain moderaattorille. Lainausmerkeissä ja
            # katkaistuna, eikä se päädy aineistoon.
            note = str(entry["note"]).replace("\n", " ")[:80]
            lines.append(f"  > {note}")
    return lines


def build_report(result: ModerationResult) -> str:
    """Kirjoita PR:n kuvaus.

    Jokaisesta kohteesta kerrotaan se, mitä päätökseen tarvitaan: missä se on,
    kuinka kaukana lähin tunnettu paikka on ja moniko on ilmoittanut. Kartan
    piirtää GitHub itse geojson-diffistä.
    """
    parts: list[str] = []
    parts.append("## Käyttäjien lähetykset\n")
    parts.append(
        f"Vahvistuksia {result.confirmations}, kiistoja {result.disputes}, "
        f"uusia kohteita {len(result.new_spots)}.\n"
    )

    if result.new_spots:
        parts.append(f"\n### Uudet ilmoitetut paikat ({len(result.new_spots)})\n")
        parts.append(
            "Julkaistaan tilassa `reported`, jonka sovellus esittää "
            "vahvistamattomana. Poista rivit, jotka näyttävät ilkivallalta.\n"
        )
        parts.extend(_entry_lines(result.new_spots))

    if result.promoted:
        parts.append(f"\n### Nousi vahvistetuksi ({len(result.promoted)})\n")
        parts.append(
            f"{CONFIRM_THRESHOLD} eri laitetta on ilmoittanut samasta kohdasta — "
            "kohde siirtyy tarkaksi paikaksi.\n"
        )
        parts.extend(_entry_lines(result.promoted))

    if result.grown:
        parts.append(f"\n### Sai lisäilmoituksia ({len(result.grown)})\n")
        parts.extend(_entry_lines(result.grown))

    if result.rejected:
        parts.append(f"\n### Hylättiin automaattisesti ({len(result.rejected)})\n")
        parts.extend(f"- #{sid}: {reason}" for sid, reason in result.rejected)

    parts.append(
        "\n---\n_Saatetekstit näkyvät vain tässä kuvauksessa eivätkä päädy "
        "julkaistuun aineistoon._\n"
    )
    return "\n".join(parts)


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Käsittele käyttäjien lähetykset")
    parser.add_argument(
        "--queue",
        type=Path,
        required=True,
        help="Workerilta haettu jono JSON-tiedostona",
    )
    parser.add_argument(
        "--dataset",
        type=Path,
        default=Path("data/invapaikat.geojson"),
        help="Julkaistu aineisto, jota vasten uutuus ratkaistaan",
    )
    parser.add_argument("--contributions", type=Path, default=CONTRIBUTIONS_PATH)
    parser.add_argument("--state", type=Path, default=STATE_PATH)
    parser.add_argument("--report", type=Path, help="Kirjoita PR:n kuvaus tähän")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)-7s %(name)s: %(message)s",
    )

    queue = json.loads(args.queue.read_text(encoding="utf-8"))
    submissions = queue.get("submissions", queue if isinstance(queue, list) else [])
    if not submissions:
        log.info("Jono on tyhjä — ei muutoksia")
        return 0

    dataset = load_dataset(args.dataset)
    log.info("%d lähetystä, %d kohdetta vertailuaineistossa", len(submissions), len(dataset))

    contributions = load_contributions(args.contributions)
    state = load_state(args.state)

    result = moderate(submissions, dataset, contributions, state)
    state["generated_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds")

    write_contributions(contributions, args.contributions)
    save_state(state, args.state)

    log.info(
        "Uusia %d, kasvoi %d, nousi vahvistetuksi %d, vahvistuksia %d, kiistoja %d, hylättiin %d",
        len(result.new_spots),
        len(result.grown),
        len(result.promoted),
        result.confirmations,
        result.disputes,
        len(result.rejected),
    )

    if args.report:
        args.report.write_text(build_report(result), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
