"""Duplikaattien tunnistus lähteiden välillä.

Keskeinen sääntö: **saman lähteen kahta kohdetta ei koskaan yhdistetä.**
Vierekkäiset invaruudut ovat OSM:ssä erillisiä pisteitä noin kolmen metrin
päässä toisistaan, ja etäisyyspohjainen yhdistely sulauttaisi ne yhdeksi —
jolloin kahden paikan parkkipaikasta tulisi yhden paikan parkkipaikka.
Lähteen sisällä erillinen tietue tarkoittaa erillistä kohdetta, ja se
luotetaan sellaisenaan.

Tästä seuraa myös, ettei ketjuuntumista sallita: jos OSM-piste A ja
OSM-piste C ovat molemmat lähellä Digiroad-merkkiä B, ei muodosteta yhtä
klusteria {A, B, C} — se yhdistäisi A:n ja C:n kiertotietä. Sen sijaan B
liitetään vain lähimpään, ja toinen jää omaksi kohteekseen.
"""

from __future__ import annotations

import logging
from collections import defaultdict
from typing import Iterable, Optional

from .geo import haversine_m
from .model import PRECISION_AREA, ParkingSpot, merge_cluster

log = logging.getLogger(__name__)

# Kaksi tarkkaa havaintoa (ruutu tai liikennemerkki) samasta paikasta ovat
# tyypillisesti alle 25 m päässä toisistaan: merkki seisoo ruudun vieressä.
PRECISE_RADIUS_M = 25.0

# Kun toinen havainnoista on alueen keskipiste, ero voi olla kymmeniä metrejä
# ilman että kyse on eri paikasta. Isompi säde tuo mukanaan riskin yhdistää
# vierekkäiset erilliset alueet, mutta väärä erillisyys on käyttäjälle
# harmittomampi kuin kadonnut paikka.
AREA_RADIUS_M = 60.0


def match_radius(a: ParkingSpot, b: ParkingSpot) -> float:
    if a.precision == PRECISION_AREA or b.precision == PRECISION_AREA:
        return AREA_RADIUS_M
    return PRECISE_RADIUS_M


class _Grid:
    """Karkea ruutuindeksi, jotta ei tarvitse verrata kaikkia kaikkiin."""

    def __init__(self, cell_m: float) -> None:
        # Yksi leveysaste on n. 111 km. Pituusasteen pituus kutistuu pohjoista
        # kohti, mutta ruudukon ei tarvitse olla tarkka — se on vain karsin.
        self.cell_deg = cell_m / 111_000.0
        self.cells: dict[tuple[int, int], list[ParkingSpot]] = defaultdict(list)

    def _key(self, lat: float, lon: float) -> tuple[int, int]:
        return int(lat / self.cell_deg), int(lon / self.cell_deg)

    def add(self, spot: ParkingSpot) -> None:
        self.cells[self._key(spot.lat, spot.lon)].append(spot)

    def nearby(self, spot: ParkingSpot) -> Iterable[ParkingSpot]:
        row, col = self._key(spot.lat, spot.lon)
        for dr in (-1, 0, 1):
            for dc in (-1, 0, 1):
                yield from self.cells.get((row + dr, col + dc), ())


def deduplicate(spots: list[ParkingSpot]) -> list[ParkingSpot]:
    """Yhdistä eri lähteiden havainnot samasta fyysisestä paikasta."""
    if not spots:
        return []

    grid = _Grid(AREA_RADIUS_M)
    for spot in spots:
        grid.add(spot)

    # Käsittele luotettavimmat ensin, jotta ne toimivat klusterin ankkurina ja
    # heikommat lähteet kiinnittyvät niihin — ei toisin päin.
    anchors = sorted(
        spots,
        key=lambda s: (s.authority_rank, s.precision_rank, s.uid),
        reverse=True,
    )

    consumed: set[str] = set()
    merged: list[ParkingSpot] = []

    for anchor in anchors:
        if anchor.uid in consumed:
            continue
        consumed.add(anchor.uid)

        # Enintään yksi kumppani per lähde, ja vain lähteistä joita klusterissa
        # ei vielä ole. Näin klusteri ei voi koskaan sisältää kahta saman
        # lähteen kohdetta.
        best_per_source: dict[str, tuple[float, ParkingSpot]] = {}
        for candidate in grid.nearby(anchor):
            if candidate.source == anchor.source or candidate.uid in consumed:
                continue
            distance = haversine_m(anchor.lat, anchor.lon, candidate.lat, candidate.lon)
            if distance > match_radius(anchor, candidate):
                continue
            current = best_per_source.get(candidate.source)
            if current is None or distance < current[0]:
                best_per_source[candidate.source] = (distance, candidate)

        cluster = [anchor]
        for _, partner in best_per_source.values():
            consumed.add(partner.uid)
            cluster.append(partner)

        merged.append(merge_cluster(cluster))

    duplicates = len(spots) - len(merged)
    log.info(
        "Deduplikointi: %d havaintoa -> %d kohdetta (%d yhdistettiin)",
        len(spots),
        len(merged),
        duplicates,
    )
    return merged


def stats_by_source(spots: list[ParkingSpot]) -> dict[str, int]:
    counts: dict[str, int] = defaultdict(int)
    for spot in spots:
        counts[spot.source] += 1
    return dict(counts)
