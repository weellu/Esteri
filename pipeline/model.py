"""Normalisoitu tietomalli invapaikoille.

Kaikki lähteet muunnetaan tähän muotoon. Koordinaatit ovat aina WGS84
(lat/lon desimaaliasteina) — lähdekohtaiset koordinaatistot hoidetaan
lähdemoduuleissa.
"""

from __future__ import annotations

from dataclasses import dataclass, field, replace
from typing import Any, Optional

# Kuinka tarkasti sijainti vastaa todellista pysäköintiruutua.
# Tämä on käyttäjälle näkyvä laatuero, ei sisäinen tekninen yksityiskohta:
# "alue" tarkoittaa että ruutu on jossain lähistöllä, ei tässä pisteessä.
PRECISION_SPACE = "space"  # yksittäinen ruutu, sijainti on itse paikka
PRECISION_SIGN = "sign"    # liikennemerkki, ruutu merkin välittömässä läheisyydessä
PRECISION_AREA = "area"    # alueen keskipiste, ruudun tarkka sijainti tuntematon

_PRECISION_RANK = {PRECISION_SPACE: 3, PRECISION_SIGN: 2, PRECISION_AREA: 1}

# Mistä kohteen olemassaolo tiedetään. Eri asia kuin precision, joka kertoo
# vain sijainnin tarkkuuden: käyttäjän ilmoittama paikka voi olla sijainniltaan
# tarkka mutta silti vahvistamaton, ja kunnan rekisterissä oleva paikka voi
# olla sijainniltaan epätarkka mutta olemassaolostaan varma.
#
# None tarkoittaa avoimesta aineistosta peräisin olevaa kohdetta. Se on
# oletus, eikä sitä kirjoiteta ulostuloon lainkaan — 2 787 kohteen tiedostossa
# turha kenttä maksaa enemmän kuin kertoo.
VERIFICATION_REPORTED = "reported"    # yhden käyttäjän ilmoitus, ei vahvistusta
VERIFICATION_CONFIRMED = "confirmed"  # useampi laite vahvistanut paikan päällä

_VERIFICATIONS = (None, VERIFICATION_REPORTED, VERIFICATION_CONFIRMED)

# Montako viimeisintä ruutumäärää otetaan mediaaniin. Kaikkien aikojen mediaani
# jumittaisi vanhaan lukemaan: jos ruutuja maalataan yksi pois, kymmenen vanhaa
# ilmoitusta pitäisi tuloksen ennallaan vuosiksi. Ikkuna päästää todellisen
# muutoksen läpi viidessä käynnissä, mutta yksittäinen väärin laskenut ei riitä
# kääntämään sitä.
CAPACITY_WINDOW = 5


def median_capacity(values: list[int]) -> Optional[int]:
    """Ruutumäärä ilmoitusten enemmistön mukaan, tai None jos ei tietoa.

    Parillisella määrällä otetaan alempi keskiluku: kahden ja kolmen ruudun
    välillä luvataan kaksi. Sama varovaisuus kuin muuallakin — käyttäjä pettyy
    vähemmän löytäessään enemmän kuin luvattiin.
    """
    usable = [int(v) for v in values[-CAPACITY_WINDOW:] if isinstance(v, int) and v > 0]
    if not usable:
        return None
    usable.sort()
    return usable[(len(usable) - 1) // 2]


# Lähteen luotettavuus metatiedoissa. Kuntien omat rekisterit ovat tarkempia
# ja tuoreempia kuin OSM; Digiroadissa on lähinnä merkin olemassaolo.
#
# Käyttäjälähde on pohjalla tarkoituksella. Jos käyttäjän ilmoitus osuu samaan
# paikkaan avoimen aineiston kohteen kanssa, avoin aineisto voittaa sekä
# sijainnin että metatiedot — ilmoitus muuttuu tällöin vahvistukseksi, ei
# kilpailevaksi kohteeksi.
_AUTHORITY_RANK = {
    "tampere": 4,
    "turku": 4,
    "helsinki": 4,
    "osm": 2,
    "digiroad": 1,
    "users": 0,
}


@dataclass
class ParkingSpot:
    source: str
    source_id: str
    lat: float
    lon: float
    precision: str
    capacity: Optional[int] = None
    name: Optional[str] = None
    address: Optional[str] = None
    restrictions: Optional[str] = None
    max_duration_h: Optional[float] = None
    fee: Optional[bool] = None
    updated: Optional[str] = None
    verification: Optional[str] = None
    # Käyttäjien maastossa antamat signaalit. Täytetään signals.py:ssä
    # deduplikoinnin jälkeen, koska ne kohdistuvat lopulliseen kohteeseen
    # eivätkä yksittäiseen havaintoon.
    confirmations: Optional[int] = None
    disputes: Optional[int] = None
    extras: dict[str, Any] = field(default_factory=dict)
    # Täytetään deduplikoinnissa: mistä lähteistä tämä kohde on koostettu.
    merged_from: list[str] = field(default_factory=list)

    def __post_init__(self) -> None:
        if self.precision not in _PRECISION_RANK:
            raise ValueError(f"tuntematon precision: {self.precision!r}")
        if self.verification not in _VERIFICATIONS:
            raise ValueError(f"tuntematon verification: {self.verification!r}")
        if not (-90 <= self.lat <= 90) or not (-180 <= self.lon <= 180):
            raise ValueError(f"koordinaatti alueen ulkopuolella: {self.lat}, {self.lon}")
        if self.capacity is not None and self.capacity < 0:
            raise ValueError(f"negatiivinen paikkamäärä: {self.capacity}")

    @property
    def uid(self) -> str:
        return f"{self.source}:{self.source_id}"

    @property
    def precision_rank(self) -> int:
        return _PRECISION_RANK[self.precision]

    @property
    def authority_rank(self) -> int:
        return _AUTHORITY_RANK.get(self.source, 0)


# Metatietokentät, jotka voidaan periä toisesta lähteestä yhdistettäessä.
#
# `verification` ei ole listalla eikä saa olla: se seuraa ankkuria. Perittynä
# yhden käyttäjän ilmoitus tarttuisi kuntarekisterin kohteeseen ja merkitsisi
# varman paikan vahvistamattomaksi — tai päinvastoin.
_MERGEABLE_FIELDS = (
    "capacity",
    "name",
    "address",
    "restrictions",
    "max_duration_h",
    "fee",
    "updated",
)


def merge_cluster(spots: list[ParkingSpot]) -> ParkingSpot:
    """Yhdistä samaa fyysistä paikkaa tarkoittavat havainnot yhdeksi.

    Sijainti otetaan tarkimmasta havainnosta, koska "alueen keskipiste" on
    huonompi vastaus kuin "tämä ruutu". Metatiedot täydennetään
    luotettavimmasta lähteestä, joka kyseisen kentän tuntee — Digiroadin
    merkki antaa hyvän sijainnin mutta ei tiedä paikkamäärää, kun taas
    Tampereen aluetieto tietää paikkamäärän mutta ei tarkkaa ruutua.
    """
    if not spots:
        raise ValueError("tyhjää klusteria ei voi yhdistää")
    if len(spots) == 1:
        only = spots[0]
        return replace(only, merged_from=[only.uid])

    # Sijainti + precision: tarkin voittaa, tasapelin ratkaisee auktoriteetti.
    base = max(spots, key=lambda s: (s.precision_rank, s.authority_rank))
    # Metatiedot: auktoriteetti ratkaisee, tasapelin tarkkuus.
    by_authority = sorted(
        spots, key=lambda s: (s.authority_rank, s.precision_rank), reverse=True
    )

    # Metatiedot ratkaistaan puhtaasti auktoriteettijärjestyksessä — myös
    # silloin kun ankkurilla itsellään on arvo. Muuten OSM:n arvaus
    # paikkamäärästä jäisi voimaan vain siksi, että sen sijainti sattui
    # olemaan tarkempi kuin kunnan aineiston.
    merged = replace(base)
    for name in _MERGEABLE_FIELDS:
        for candidate in by_authority:
            value = getattr(candidate, name)
            if value is not None:
                setattr(merged, name, value)
                break

    merged.extras = {}
    for candidate in reversed(by_authority):
        merged.extras.update(candidate.extras)

    merged.merged_from = sorted(s.uid for s in spots)
    return merged
