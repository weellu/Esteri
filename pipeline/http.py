"""HTTP-apurit lähdemoduuleille.

Pelkkää standardikirjastoa: pipeline ei tarvitse ulkoisia riippuvuuksia,
koska kaikki lähteet osaavat uudelleenprojisoida WGS84:ään palvelinpuolella.
"""

from __future__ import annotations

import json
import logging
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Optional

log = logging.getLogger(__name__)

# Turun WFS vastaa 403:lla Pythonin oletus-User-Agentille ja vaatii
# selainmaisen tunnisteen.
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "Esteri/0.1 (+https://github.com/weellu/Esteri; avoin data -pipeline)"
)

# Overpass taas hylkää selainmaisen tunnisteen (HTTP 406) ja odottaa kuvaavaa
# tunnistetta yhteystiedolla — se on myös sen käyttöetiketin mukaista.
# Siksi User-Agent on lähdekohtainen eikä globaali vakio.
DESCRIPTIVE_USER_AGENT = "Esteri/0.1 (avoin data -pipeline; +https://github.com/weellu/Esteri)"

DEFAULT_TIMEOUT = 180
MAX_ATTEMPTS = 3


class FetchError(RuntimeError):
    """Lähteen haku epäonnistui pysyvästi."""


def _request(url: str, data: Optional[bytes], timeout: int, user_agent: str) -> bytes:
    req = urllib.request.Request(url, data=data, headers={"User-Agent": user_agent})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def fetch(
    url: str,
    *,
    params: Optional[dict[str, Any]] = None,
    data: Optional[dict[str, Any]] = None,
    timeout: int = DEFAULT_TIMEOUT,
    attempts: int = MAX_ATTEMPTS,
    user_agent: str = USER_AGENT,
) -> bytes:
    """Hae URL uudelleenyrityksin. Palauttaa raa'at tavut."""
    if params:
        url = f"{url}?{urllib.parse.urlencode(params)}"
    body = urllib.parse.urlencode(data).encode() if data else None

    last: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            return _request(url, body, timeout, user_agent)
        except urllib.error.HTTPError as exc:
            last = exc
            # 4xx on pysyvä virhe (401 = ei avointa pääsyä, 403 = estetty):
            # uudelleenyritys ei auta, joten keskeytä heti.
            if 400 <= exc.code < 500 and exc.code != 429:
                raise FetchError(f"{url} -> HTTP {exc.code}") from exc
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            last = exc
        if attempt < attempts:
            delay = 2 ** attempt
            log.warning("yritys %d/%d epäonnistui (%s), odotetaan %ds", attempt, attempts, last, delay)
            time.sleep(delay)
    raise FetchError(f"{url} epäonnistui {attempts} yrityksen jälkeen: {last}")


def fetch_json(url: str, **kwargs: Any) -> Any:
    raw = fetch(url, **kwargs)
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        preview = raw[:200].decode("utf-8", "replace")
        raise FetchError(f"{url} ei palauttanut JSONia: {preview!r}") from exc


def fetch_text(url: str, **kwargs: Any) -> str:
    return fetch(url, **kwargs).decode("utf-8", "replace")


def fetch_first_ok(urls: list[str], **kwargs: Any) -> bytes:
    """Kokeile useaa peilipalvelinta järjestyksessä (Overpass aikakatkaisee usein)."""
    last: Exception | None = None
    for url in urls:
        try:
            return fetch(url, **kwargs)
        except FetchError as exc:
            log.warning("peili %s epäonnistui: %s", url, exc)
            last = exc
    raise FetchError(f"kaikki peilit epäonnistuivat: {last}")
