import json, os, time, urllib.request
from _lib import read_secret, notify, state_get, state_set, check_main

UPSTREAM     = os.environ["UPSTREAM_XC_URL"]
WARN_DAYS    = int(os.environ.get("EXP_WARNING_DAYS", "7"))
USER         = read_secret("IPTV_UPSTREAM_USER.env")
PASS         = read_secret("IPTV_UPSTREAM_PASS.env")


@check_main("iptv-renewal-warn")
def main():
    url = f"{UPSTREAM}?username={USER}&password={PASS}"
    data = json.loads(urllib.request.urlopen(url, timeout=15).read())
    exp_date_raw = data.get("user_info", {}).get("exp_date")

    if exp_date_raw is None:
        raise ValueError(f"exp_date missing from user_info: {data.get('user_info')}")

    exp_ts = int(exp_date_raw)
    now_ts = time.time()
    days_remaining = (exp_ts - now_ts) / 86400

    print(f"[iptv-renewal-warn] exp_date={exp_ts} days_remaining={days_remaining:.1f} warn_days={WARN_DAYS}")

    if days_remaining >= WARN_DAYS:
        # Subscription is not yet within warning window; clear any prior warn state.
        state_set("iptv_renewal_last_warn_day", None)
        return

    # Within the warning window. Fire at most once per calendar day to avoid spam.
    today_str = time.strftime("%Y-%m-%d", time.localtime())
    last_warn_day = state_get("iptv_renewal_last_warn_day")

    if last_warn_day == today_str:
        # Already warned today.
        return

    state_set("iptv_renewal_last_warn_day", today_str)
    notify(
        tags=["warning", "iptv"],
        title="IPTV subscription expiring soon",
        body=f"Subscription expires in {days_remaining:.1f} days (exp_date={exp_ts}). Renew before it lapses.",
    )


if __name__ == "__main__":
    main()
