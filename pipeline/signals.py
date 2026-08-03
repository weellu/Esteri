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

from .model import ParkingSpot, median_capacity

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
        spot.confirmations = present or None
        spot.disputes = missing or None

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
