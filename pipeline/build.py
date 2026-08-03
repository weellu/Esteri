"""Pipelinen ajuri: hae -> normalisoi -> deduplikoi -> kirjoita.

Ajo:
    python3 -m pipeline.build
    python3 -m pipeline.build --sources tampere turku --output-dir data
    python3 -m pipeline.build --use-cache          # ei verkkoa, kehitykseen

Yhden lähteen kaatuminen ei kaada koko ajoa — muut lähteet kirjoitetaan silti
ja epäonnistuneet raportoidaan lopuksi. Poikkeus: jos kaikki lähteet
epäonnistuvat, ajo palauttaa virhekoodin, jotta CI ei julkaise tyhjää dataa.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from .dedupe import deduplicate, stats_by_source
from .model import ParkingSpot
from .outputs import write_geojson, write_manifest, write_sqlite
from .signals import STATE_PATH, apply_signals, load_state
from .sources import SOURCES

log = logging.getLogger("pipeline")

DEFAULT_OUTPUT_DIR = Path("data")
DEFAULT_CACHE_DIR = Path(".cache")

# Lähteet, jotka luetaan levyltä eikä verkosta. Välimuisti on tarkoitettu
# verkkohakujen välttämiseen kehityksessä; paikallisella lähteellä se vain
# piilottaisi juuri tehdyn muutoksen seuraavalta --use-cache-ajolta.
LOCAL_SOURCES = frozenset({"users"})


def _cache_path(cache_dir: Path, name: str) -> Path:
    return cache_dir / f"{name}.json"


def _save_cache(cache_dir: Path, name: str, spots: list[ParkingSpot]) -> None:
    cache_dir.mkdir(parents=True, exist_ok=True)
    _cache_path(cache_dir, name).write_text(
        json.dumps([asdict(s) for s in spots], ensure_ascii=False), encoding="utf-8"
    )


def _load_cache(cache_dir: Path, name: str) -> Optional[list[ParkingSpot]]:
    path = _cache_path(cache_dir, name)
    if not path.exists():
        return None
    raw = json.loads(path.read_text(encoding="utf-8"))
    return [ParkingSpot(**item) for item in raw]


def collect(
    names: list[str], *, cache_dir: Path, use_cache: bool
) -> tuple[list[ParkingSpot], list[str]]:
    collected: list[ParkingSpot] = []
    failed: list[str] = []

    for name in names:
        local = name in LOCAL_SOURCES
        if use_cache and not local:
            cached = _load_cache(cache_dir, name)
            if cached is not None:
                log.info("%s: %d kohdetta välimuistista", name, len(cached))
                collected.extend(cached)
                continue
            log.warning("%s: välimuistia ei löydy, haetaan verkosta", name)

        try:
            spots = SOURCES[name]()
        except Exception as exc:  # lähde alas tai rajapinta muuttunut
            log.error("%s epäonnistui: %s", name, exc)
            failed.append(name)
            continue
        if not local:
            _save_cache(cache_dir, name, spots)
        collected.extend(spots)

    return collected, failed


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Rakenna invapaikka-aineisto avoimista lähteistä")
    parser.add_argument("--sources", nargs="+", choices=sorted(SOURCES), default=sorted(SOURCES))
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE_DIR)
    parser.add_argument(
        "--use-cache",
        action="store_true",
        help="Käytä aiemmin haettua dataa verkon sijaan (kehitykseen)",
    )
    parser.add_argument("--no-dedupe", action="store_true", help="Ohita deduplikointi (vertailuun)")
    parser.add_argument(
        "--state",
        type=Path,
        default=STATE_PATH,
        help="Moderoinnin tilatiedosto, josta käyttäjien vahvistukset luetaan",
    )
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)-7s %(name)s: %(message)s",
    )

    raw, failed = collect(args.sources, cache_dir=args.cache_dir, use_cache=args.use_cache)
    if not raw:
        log.error("Yksikään lähde ei tuottanut dataa — ei kirjoiteta mitään")
        return 1

    log.info("Raakahavainnot lähteittäin: %s", stats_by_source(raw))

    spots = raw if args.no_dedupe else deduplicate(raw)

    # Vahvistukset liitetään vasta deduplikoinnin jälkeen: käyttäjä vahvisti
    # sen kohteen, jonka näki sovelluksessa, ja se kohde syntyy vasta tässä.
    apply_signals(spots, load_state(args.state)["signals"])

    spots.sort(key=lambda s: (s.lat, s.lon, s.uid))

    generated_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
    geojson_path = args.output_dir / "invapaikat.geojson"
    sqlite_path = args.output_dir / "invapaikat.sqlite"
    write_geojson(spots, geojson_path, generated_at=generated_at)
    write_sqlite(spots, sqlite_path, generated_at=generated_at)
    write_manifest(
        spots,
        args.output_dir / "manifest.json",
        generated_at=generated_at,
        files={"geojson": geojson_path, "sqlite": sqlite_path},
    )

    log.info("Lopputulos lähteittäin: %s", stats_by_source(spots))
    log.info("Yhteensä %d kohdetta", len(spots))
    if failed:
        log.warning("Epäonnistuneet lähteet: %s", ", ".join(failed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
