import json
import os
import urllib.request

from _lib import check_main, notify, read_secret, state_get, state_set

LOCAL = os.environ["LOCAL_XC_URL"]
FLOOR = int(os.environ.get("CHANNEL_FLOOR", "200"))
USER = read_secret("IPTV_LOCAL_USER.env")
PASS = read_secret("IPTV_LOCAL_PASS.env")


@check_main("iptv-channel-count")
def main():
    url = f"{LOCAL}/player_api.php?username={USER}&password={PASS}&action=get_live_streams"
    streams = json.loads(urllib.request.urlopen(url, timeout=30).read())
    count = len(streams)

    prev_below = state_get("iptv_channel_count_below", False)
    state_set("iptv_channel_count_below", count < FLOOR)

    print(f"[iptv-channel-count] count={count} floor={FLOOR}")

    if count < FLOOR and not prev_below:
        notify(
            tags=["critical", "iptv"],
            title="IPTV channel count below floor",
            body=f"Only {count} live streams returned (floor={FLOOR}). Check iptvboss/upstream.",
        )
    elif count >= FLOOR and prev_below:
        notify(
            tags=["info", "iptv"],
            title="IPTV channel count recovered",
            body=f"Live stream count back to {count} (floor={FLOOR}).",
        )


if __name__ == "__main__":
    main()
