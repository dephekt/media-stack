import json
import os
import urllib.request

from _lib import check_main, notify, read_secret, state_get, state_set

UPSTREAM = os.environ["UPSTREAM_XC_URL"]
USER = read_secret("IPTV_UPSTREAM_USER.env")
PASS = read_secret("IPTV_UPSTREAM_PASS.env")


@check_main("iptv-auth")
def main():
    url = f"{UPSTREAM}?username={USER}&password={PASS}"
    data = json.loads(urllib.request.urlopen(url, timeout=15).read())
    auth_ok = data.get("user_info", {}).get("auth") == 1

    prev = state_get("iptv_auth_ok", True)
    state_set("iptv_auth_ok", auth_ok)

    if not auth_ok and prev:
        notify(
            tags=["critical", "iptv"],
            title="IPTV upstream auth failed",
            body=f"player_api.php returned auth={data.get('user_info', {}).get('auth')}; check subscription.",
        )
    elif auth_ok and not prev:
        notify(tags=["info", "iptv"], title="IPTV upstream auth recovered")


if __name__ == "__main__":
    main()
