"""Käyttäjien maastossa antamat vahvistukset ja kiistot.

Signaali kohdistuu kohteeseen, ei havaintoon, joten se liitetään vasta
deduplikoinnin jälkeen. Ennen sitä ei ole olemassa sitä kohdetta, jonka
käyttäjä sovelluksessa näki.

**Signaalit eivät poista kohteita.** Kiistoja näytetään käyttäjälle, mutta
avoimen aineiston kohde jää aineistoon vaikka sitä kiistettäisiin: kiistoja
on helppo tuottaa väärin (väärä paikka, väärä tulkinta merkistä, ilkivalta),
ja puuttuva invapaikka on autoilijalle vakavampi virhe kuin ylimääräinen.
Kiistetyt kohteet on tarkoitettu ihmisen katsottavaksi, ei automaattisesti
pudotettavaksi.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

from .model import (
    PRECISION_AREA,
    VERIFICATION_DISPUTED,
    VERIFICATION_REPORTED,
    ParkingSpot,
    median_capacity,
)

log = logging.getLogger(__name__)

STATE_PATH = Path("contributions/tila.json")


def load_state(path: Path = STATE_PATH) -> dict[str, Any]:
    """Lue moderoinnin tilatiedosto. Puuttuva tiedosto on tyhjä tila."""
    if not path.exists():
        return {"high_water_mark": 0, "signals": {}}
    state = json.loads(path.read_text(encoding="utf-8"))
    state.setdefault("high_water_mark", 0)
    state.setdefault("signals", {})
    return state


def save_state(state: dict[str, Any], path: Path = STATE_PATH) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # Sisennetty ja avaimet järjestyksessä: tiedosto luetaan PR-diffinä,
    # ja yhden rivin JSON tekisi diffistä lukukelvottoman.
    path.write_text(
        json.dumps(state, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def apply_signals(spots: list[ParkingSpot], signals: dict[str, Any]) -> tuple[int, int]:
    """Liitä vahvistukset ja kiistot kohteisiin.

    Signaali on tallennettu sillä uid:llä, jonka käyttäjä sovelluksessa näki.
    Deduplikoinnin ankkuri voi vaihtua ajojen välillä, kun lähteisiin tulee
    uusia havaintoja, jolloin sama fyysinen paikka tunnetaan eri uid:llä.
    Siksi osumaa etsitään myös `merged_from`-listasta — muuten vahvistukset
    katoaisivat juuri niistä kohteista, joista on eniten tietoa.

    Palauttaa (liitetyt kohteet, orpojen signaalien määrä).
    """
    if not signals:
        return 0, 0

    applied: set[str] = set()
    matched_spots = 0

    for spot in spots:
        present = 0
        missing = 0
        capacities: list[int] = []
        hits: list[str] = []
        for uid in (spot.uid, *spot.merged_from):
            signal = signals.get(uid)
            if signal is None or uid in hits:
                continue
            hits.append(uid)
            present += int(signal.get("present", 0))
            missing += int(signal.get("missing", 0))
            capacities.extend(signal.get("capacities") or [])

        if not hits:
            continue

        applied.update(hits)
        matched_spots += 1
        # Nolla kirjoitetaan Nonena, jotta se ei päädy ulostuloon: "0
        # vahvistusta" ja "ei tietoa" ovat sama asia eikä kenttää kannata
        # viedä 2 787 kohteen tiedostoon turhaan.
        # Lisätään, ei ylikirjoiteta. Käyttäjän kohteella on jo lukema
        # lähteestä (montako erillistä ilmoitusta klusterin muodosti), ja
        # ylikirjoitus pudotti sen napin painalluksella takaisin yhteen —
        # vahvistaminen siis pienensi vahvistusten määrää. Luvut ovat
        # erillisiä havaintoja eivätkä mene päällekkäin: "uusi paikka" kasvattaa
        # klusteria, vahvistusnappi kirjaa signaalin.
        spot.confirmations = ((spot.confirmations or 0) + present) or None
        spot.disputes = ((spot.disputes or 0) + missing) or None

        # Maastohavainto voittaa rekisterin vasta kun havaintoja on kaksi.
        # Kunnan aineisto voi olla vanhentunut, mutta yksi ohikulkija voi olla
        # yksinkertaisesti väärässä — ja rekisterin ylikirjoittaminen yhden
        # napautuksen perusteella olisi huonompi vaihtokauppa kuin odottaa
        # toista. Tyhjään kenttään yksikin havainto on parannus.
        reported = median_capacity(capacities)
        if reported is not None and (len(capacities) >= 2 or spot.capacity is None):
            spot.capacity = reported

    orphans = len(set(signals) - applied)
    if orphans:
        # Ei poisteta tilatiedostosta: uid voi palata, kun lähde päivittyy.
        log.info("%d signaalia ei osunut yhteenkään kohteeseen (säilytetään)", orphans)
    log.info("Käyttäjäsignaalit liitetty %d kohteeseen", matched_spots)
    return matched_spots, orphans


# Montako kiistoa tarvitaan, ennen kuin kohteeseen kosketaan lainkaan. Yksi
# ilmoitus "ei löydy" voi tarkoittaa myös sitä, että etsijä katsoi väärästä
# kohdasta — kahden eri laitteen erehtyminen samalla tavalla on jo harvinaisempaa.
DISPUTE_MIN = 2

# Käyttäjän kohde poistetaan julkaisusta vasta, kun kiistoja on selvä enemmistö.
# Kynnys on korkeampi kuin alentamisen, koska poisto on peruuttamaton siihen
# asti kunnes joku ilmoittaa paikan uudelleen.
DROP_MIN = 3
DROP_FACTOR = 2


def demote_disputed(spots: list[ParkingSpot]) -> tuple[list[ParkingSpot], int, int]:
    """Pura kiistetyt kohteet.

    Ilman tätä vahvistus oli yksisuuntainen: väärin vahvistetusta tiedosta ei
    ollut paluutietä, ja kohde jolla oli kymmenen kiistoa näytti käyttäjälle
    samalta kuin ennenkin.

    Käyttäjän ilmoittama kohde voidaan poistaa kokonaan — sen ainoa todiste
    olivat ilmoitukset, ja ne ovat nyt enemmistöltään kielteisiä. Avoimen
    aineiston kohdetta ei poisteta, koska seuraava ajo hakisi sen takaisin
    lähteestä ja koska kunnan rekisteri voi silti olla oikeassa. Se merkitään
    kiistellyksi, jolloin sovellus voi kertoa erimielisyydestä.

    Palauttaa (jäljelle jäävät kohteet, alennetut, poistetut).
    """
    kept: list[ParkingSpot] = []
    demoted = 0
    dropped = 0

    for spot in spots:
        disputes = spot.disputes or 0
        confirmations = spot.confirmations or 0

        if disputes < DISPUTE_MIN or disputes <= confirmations:
            kept.append(spot)
            continue

        if spot.source == "users" and disputes >= DROP_MIN and disputes > DROP_FACTOR * confirmations:
            dropped += 1
            continue

        if spot.source == "users":
            # Tarkkuus seuraa vahvistusta: kiistelty kohde ei saa luvata
            # tarkkaa ruutua, vaikka se olisi aiemmin noussut siihen.
            spot.verification = VERIFICATION_REPORTED
            spot.precision = PRECISION_AREA
        else:
            spot.verification = VERIFICATION_DISPUTED
        demoted += 1
        kept.append(spot)

    if demoted or dropped:
        log.info("Kiistettyjä: %d alennettu, %d poistettu julkaisusta", demoted, dropped)
    return kept, demoted, dropped
