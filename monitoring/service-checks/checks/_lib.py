import functools
import json
import os
import sys
import traceback
import urllib.request
from pathlib import Path

APPRISE_URL = os.environ["APPRISE_URL"]
STATE_DIR = Path(os.environ.get("STATE_DIR", "/state"))


def read_secret(name: str) -> str:
    return Path(f"/run/secrets/{name}").read_text().strip()


def notify(*, tags: list, title: str, body: str = "") -> None:
    # Defense-in-depth: apprise-api returns HTTP 400 on empty body.
    if not body:
        body = "(no body)"
    payload = json.dumps({"title": title, "body": body}).encode()
    qs = "&".join(f"tag={t}" for t in tags)
    req = urllib.request.Request(
        f"{APPRISE_URL}?{qs}",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    urllib.request.urlopen(req, timeout=10).read()


def _hc_ping(script_name: str, suffix: str = "") -> None:
    """Ping healthchecks.io for this script. suffix is "", "/start", or "/fail".

    Silent if HC_PING_URL_<SCRIPT_NAME> is unset -- keeps local/dev runs quiet.
    Network failures are swallowed: hc.io's job is to alert when pings stop,
    so a transient ping failure should never break the underlying check.
    """
    env_var = "HC_PING_URL_" + script_name.upper().replace("-", "_")
    url = os.environ.get(env_var)
    if not url:
        return
    try:
        urllib.request.urlopen(url + suffix, timeout=5).read()
    except Exception:
        pass


def state_get(key: str, default=None):
    p = STATE_DIR / f"{key}.json"
    return json.loads(p.read_text()) if p.exists() else default


def state_set(key: str, value) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    (STATE_DIR / f"{key}.json").write_text(json.dumps(value))


def check_main(script_name: str):
    """Wrap a check's main(): emit warning on uncaught errors, dedup so
    persistent failures fire once and recover-once. The script runs inside
    crond which only logs the traceback to stdout -- without this wrapper a
    silent failure (e.g. iptv stack down) produces no notification.

    Also pings healthchecks.io at /start, success, and /fail (when
    HC_PING_URL_<SCRIPT_NAME> is set). hc.io's role is the dead-man side: it
    alerts via Discord if the script ever silently stops running (cron dead,
    container crashed, supercronic wedged), which the apprise-on-failure path
    cannot detect because it never fires in the first place."""

    def deco(fn):
        @functools.wraps(fn)
        def wrapper(*a, **kw):
            err_key = f"{script_name}-last-error"
            _hc_ping(script_name, "/start")
            try:
                fn(*a, **kw)
            except Exception as e:
                _hc_ping(script_name, "/fail")
                err_class = type(e).__name__
                msg = str(e)[:500]
                prev = state_get(err_key)
                if prev != err_class:
                    notify(
                        tags=["warning", "iptv"],
                        title=f"{script_name} failed: {err_class}",
                        body=msg or traceback.format_exc(limit=3),
                    )
                    state_set(err_key, err_class)
                sys.exit(1)
            else:
                _hc_ping(script_name)
                if state_get(err_key) is not None:
                    notify(tags=["info", "iptv"], title=f"{script_name} recovered")
                    state_set(err_key, None)

        return wrapper

    return deco
