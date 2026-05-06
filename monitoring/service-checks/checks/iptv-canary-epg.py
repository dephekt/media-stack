"""
Per-channel EPG canary check.

The global freshness check (iptv-epg-freshness.py) confirms the EPG extends
N hours forward overall, but a single channel can silently drop all guide data
while the aggregate EPG still looks healthy.  This check watches six specific
channels and fires a critical alert the moment any of them lose their guide.

For each canary channel we measure:
  - present          : did a <channel id="..."> element appear?
  - n_future_prog    : count of <programme> whose stop is in the future
  - latest_stop_h    : hours until the furthest future stop time (0 if none)
  - n_unique_titles  : count of distinct programme titles

A canary is healthy iff all four metrics meet their thresholds.

State is persisted per-canary so transitions (healthy→failing, failing→healthy)
each fire exactly one notification and steady-state is silent.

Memory: the XMLTV response is ~12 MB; we stream-parse with iterparse and clear
elements immediately, keeping memory flat regardless of file size.
"""

import os
import time
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime

from _lib import check_main, notify, read_secret, state_get, state_set

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

LOCAL = os.environ["LOCAL_XC_URL"]
USER = read_secret("IPTV_LOCAL_USER.env")
PASS = read_secret("IPTV_LOCAL_PASS.env")

_DEFAULT_CHANNELS = (
    "ABCWICS.us,HallmarkChannel.us,HallmarkFamily.us,CBSKMOV.us,NBCWAND.us,skyhits.uk"
)

CANARY_IDS = [
    ch.strip()
    for ch in os.environ.get("EPG_CANARY_CHANNELS", _DEFAULT_CHANNELS).split(",")
    if ch.strip()
]
MIN_FUTURE_PROG = int(os.environ.get("EPG_CANARY_MIN_FUTURE_PROG", "6"))
MIN_FUTURE_HOURS = float(os.environ.get("EPG_CANARY_MIN_FUTURE_HOURS", "12"))
MIN_UNIQUE_TITLES = int(os.environ.get("EPG_CANARY_MIN_UNIQUE_TITLES", "3"))

SCRIPT = "iptv-canary-epg"


# ---------------------------------------------------------------------------
# XMLTV streaming parser
# ---------------------------------------------------------------------------


def _parse_canaries(stream, canary_set: set) -> dict:
    """Stream-parse XMLTV; return per-canary stats for the requested ids.

    Returns a dict keyed by channel-id:
        {
            "present":        bool,
            "display_name":   str | None,
            "n_future_prog":  int,
            "latest_stop_ts": float,   # unix timestamp; 0.0 if no programmes
            "titles":         set[str],
        }
    """
    now = time.time()

    stats = {
        ch_id: {
            "present": False,
            "display_name": None,
            "n_future_prog": 0,
            "latest_stop_ts": 0.0,
            "titles": set(),
        }
        for ch_id in canary_set
    }

    for _event, elem in ET.iterparse(stream, events=("end",)):
        tag = elem.tag

        if tag == "channel":
            ch_id = elem.get("id", "")
            if ch_id in canary_set:
                stats[ch_id]["present"] = True
                dn = elem.findtext("display-name")
                if dn:
                    stats[ch_id]["display_name"] = dn.strip()
            elem.clear()

        elif tag == "programme":
            ch_id = elem.get("channel", "")
            if ch_id not in canary_set:
                elem.clear()
                continue

            stop_raw = elem.get("stop", "")
            if stop_raw:
                try:
                    stop_ts = datetime.strptime(stop_raw, "%Y%m%d%H%M%S %z").timestamp()
                except ValueError:
                    stop_ts = 0.0

                if stop_ts > now:
                    stats[ch_id]["n_future_prog"] += 1
                    if stop_ts > stats[ch_id]["latest_stop_ts"]:
                        stats[ch_id]["latest_stop_ts"] = stop_ts

                title = elem.findtext("title") or ""
                if title.strip():
                    stats[ch_id]["titles"].add(title.strip())

            elem.clear()

    return stats


# ---------------------------------------------------------------------------
# Per-canary health evaluation
# ---------------------------------------------------------------------------


def _evaluate(ch_id: str, s: dict, now: float) -> tuple[bool, str | None]:
    """Return (is_healthy, reason_or_None)."""
    if not s["present"]:
        return False, "channel not in EPG roster"

    latest_h = (s["latest_stop_ts"] - now) / 3600 if s["latest_stop_ts"] else 0.0
    n_prog = s["n_future_prog"]
    n_titles = len(s["titles"])

    reasons = []
    if n_prog < MIN_FUTURE_PROG:
        reasons.append(f"future_prog={n_prog} (need >= {MIN_FUTURE_PROG})")
    if latest_h < MIN_FUTURE_HOURS:
        reasons.append(f"latest_stop={latest_h:.1f}h (need >= {MIN_FUTURE_HOURS}h)")
    if n_titles < MIN_UNIQUE_TITLES:
        reasons.append(f"unique_titles={n_titles} (need >= {MIN_UNIQUE_TITLES})")

    if reasons:
        return False, "; ".join(reasons)
    return True, None


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


@check_main(SCRIPT)
def main():
    url = f"{LOCAL}/xmltv.php?username={USER}&password={PASS}"
    with urllib.request.urlopen(url, timeout=120) as resp:
        stats = _parse_canaries(resp, set(CANARY_IDS))

    now = time.time()

    for ch_id in CANARY_IDS:
        s = stats[ch_id]
        is_healthy, reason = _evaluate(ch_id, s, now)

        # One-line stdout summary for `make logs-monitoring`
        if is_healthy:
            latest_h = (s["latest_stop_ts"] - now) / 3600
            print(
                f"[{SCRIPT}] {ch_id:<24} OK    "
                f"future_prog={s['n_future_prog']} "
                f"latest_stop={latest_h:.1f}h "
                f"unique_titles={len(s['titles'])}"
            )
        else:
            print(f"[{SCRIPT}] {ch_id:<24} FAIL  {reason}")

        # State transition logic
        state_key = f"iptv_canary_{ch_id}"
        prev = state_get(state_key, {"healthy": True, "reason": None})
        prev_healthy = prev.get("healthy", True)

        if not is_healthy and prev_healthy:
            display = s["display_name"] or ch_id
            notify(
                tags=["critical", "iptv"],
                title=f"IPTV canary {ch_id} EPG broken",
                body=f"{display}: {reason}",
            )
        elif is_healthy and not prev_healthy:
            notify(
                tags=["info", "iptv"],
                title=f"IPTV canary {ch_id} EPG recovered",
            )

        state_set(state_key, {"healthy": is_healthy, "reason": reason})


if __name__ == "__main__":
    main()
