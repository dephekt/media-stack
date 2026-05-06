"""
EPG freshness check.

iptvboss's xmltv.php does not expose Last-Modified or any timestamp on the
<tv> root element, so we can't measure "data age" from the HTTP response.
Instead we use a coverage proxy: parse the XMLTV stream, find the latest
programme stop time, and require that stop time to be at least
EPG_MIN_FUTURE_HOURS into the future. A fresh EPG always extends
~12-48 hours forward; a stale EPG truncates near or below "now."

The response body is ~12 MB; we stream-parse it with xml.etree.iterparse
and clear elements as we go to keep memory bounded.
"""

import os
import time
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime

from _lib import check_main, notify, read_secret, state_get, state_set

LOCAL = os.environ["LOCAL_XC_URL"]
MIN_FUTURE_HOURS = float(os.environ.get("EPG_MIN_FUTURE_HOURS", "6"))
USER = read_secret("IPTV_LOCAL_USER.env")
PASS = read_secret("IPTV_LOCAL_PASS.env")


def latest_stop_ts(stream) -> float:
    """Stream-parse XMLTV; return max(programme.stop) as Unix timestamp."""
    latest = 0.0
    for _event, elem in ET.iterparse(stream, events=("end",)):
        if elem.tag == "programme":
            stop = elem.get("stop", "")
            if stop:
                # XMLTV format: "YYYYMMDDHHMMSS +HHMM"
                ts = datetime.strptime(stop, "%Y%m%d%H%M%S %z").timestamp()
                if ts > latest:
                    latest = ts
            elem.clear()
    return latest


@check_main("iptv-epg-freshness")
def main():
    url = f"{LOCAL}/xmltv.php?username={USER}&password={PASS}"
    with urllib.request.urlopen(url, timeout=120) as resp:
        latest = latest_stop_ts(resp)

    if latest == 0:
        raise ValueError("No <programme stop=...> found in xmltv.php response")

    future_hours = (latest - time.time()) / 3600
    is_stale = future_hours < MIN_FUTURE_HOURS

    print(
        f"[iptv-epg-freshness] latest_stop_in={future_hours:.1f}h "
        f"min={MIN_FUTURE_HOURS}h stale={is_stale}"
    )

    prev_stale = state_get("iptv_epg_stale", False)
    state_set("iptv_epg_stale", is_stale)

    if is_stale and not prev_stale:
        notify(
            tags=["critical", "iptv"],
            title="IPTV EPG coverage running thin",
            body=f"Latest programme ends in {future_hours:.1f}h "
            f"(want >= {MIN_FUTURE_HOURS}h). Check iptvboss EPG refresh.",
        )
    elif not is_stale and prev_stale:
        notify(
            tags=["info", "iptv"],
            title="IPTV EPG coverage recovered",
            body=f"Latest programme now ends in {future_hours:.1f}h.",
        )


if __name__ == "__main__":
    main()
