"""
End-to-end public availability check.

Probes each public dephekt.net subdomain over HTTPS from inside this
container. Unlike the container-level healthchecks (which test the app
process) and newt's per-target healthchecks (which test inside the docker
network), this exercises the full external path:

    HTTPS -> traefik (edge) -> gerbil tunnel -> newt -> docker proxy -> target

A failure anywhere in that chain (Pangolin blueprint glitch, stale newt
TCP proxy, gerbil tunnel down, expired LE cert, traefik misconfig) shows
up here and nowhere else.

5xx, connection errors, and DNS failures are treated as "down". 4xx
responses (e.g., a 401 challenge from an SSO-gated resource) are
"up" -- they prove the edge is responding and routing correctly. 3xx
follows are handled by urllib's default opener.

Flap dampening: each domain is probed twice (with a short delay between
attempts) to absorb sub-second TCP/TLS blips, and an alert only fires
after FAILURE_THRESHOLD consecutive cycles have failed. Probes run in
parallel across domains so the worst-case wall time stays under the
1-minute cron cadence.
"""
import os, time, urllib.error, urllib.request
from concurrent.futures import ThreadPoolExecutor
from _lib import notify, state_get, state_set, check_main

_DEFAULT_DOMAINS = (
    "auth.dephekt.net,"
    "iptvboss.dephekt.net,"
    "stream.dephekt.net,"
    "movies.stream.dephekt.net,"
    "shows.stream.dephekt.net,"
    "grabs.stream.dephekt.net,"
    "requests.stream.dephekt.net,"
    "photos.dephekt.net,"
    "cnotify.dephekt.net,"
    "ntfy.dephekt.net,"
    "apprise.dephekt.net,"
    "www.dephekt.net,"
    "updates.stream.dephekt.net,"
    "pangolin.dephekt.net"
)
DOMAINS = [s.strip() for s in os.environ.get("PUBLIC_DOMAINS", _DEFAULT_DOMAINS).split(",") if s.strip()]
TIMEOUT = float(os.environ.get("PUBLIC_PROBE_TIMEOUT", "15"))
RETRY_DELAY = float(os.environ.get("PUBLIC_PROBE_RETRY_DELAY", "2"))
FAILURE_THRESHOLD = int(os.environ.get("PUBLIC_FAILURE_THRESHOLD", "2"))


def _probe_once(host: str) -> tuple[bool, str | None]:
    url = f"https://{host}/"
    req = urllib.request.Request(
        url,
        method="HEAD",
        headers={"User-Agent": "monitoring-public-availability/1.0"},
    )
    try:
        urllib.request.urlopen(req, timeout=TIMEOUT)
        return True, None
    except urllib.error.HTTPError as e:
        # 4xx (auth challenges, not-found) prove the edge is responding.
        # 5xx is the proxy/upstream failure mode we want to catch.
        if e.code >= 500:
            return False, f"HTTP {e.code}"
        return True, None
    except (urllib.error.URLError, TimeoutError) as e:
        reason = getattr(e, "reason", None) or str(e)
        return False, f"{type(e).__name__}: {reason}"
    except Exception as e:
        return False, f"{type(e).__name__}: {e}"


def probe(host: str) -> tuple[bool, str | None]:
    is_up, reason = _probe_once(host)
    if is_up:
        return True, None
    time.sleep(RETRY_DELAY)
    return _probe_once(host)


@check_main("public-availability")
def main():
    with ThreadPoolExecutor(max_workers=max(len(DOMAINS), 1)) as ex:
        results = list(zip(DOMAINS, ex.map(probe, DOMAINS)))

    for host, (is_up, reason) in results:
        state_key = f"public_avail_{host}"
        prev = state_get(state_key, {})
        prev_failures = prev.get("consecutive_failures", 0)
        prev_alerted = prev.get("alerted", False)

        status = "OK" if is_up else f"FAIL  {reason}"
        print(f"[public-availability] {host:<30} {status}")

        if is_up:
            failures = 0
            alerted = False
            if prev_alerted:
                notify(
                    tags=["public-infra"],
                    title=f"Public URL recovered: {host}",
                    body=f"https://{host}/ probe succeeding again.",
                )
        else:
            failures = prev_failures + 1
            alerted = prev_alerted
            if failures >= FAILURE_THRESHOLD and not prev_alerted:
                # Tag-only public-infra (no critical/info), so this lands on a
                # dedicated topic separate from container-side alerts. A
                # public-infra alert without a corresponding general alert means
                # the container is fine internally and the proxy/edge layer is
                # the failure surface.
                notify(
                    tags=["public-infra"],
                    title=f"Public URL down: {host}",
                    body=(
                        f"https://{host}/ probe from service-checks failed "
                        f"{failures} cycles in a row ({reason}). The container "
                        f"healthcheck and newt's target healthcheck are blind "
                        f"to this layer -- likely a stale newt TCP proxy, "
                        f"Pangolin blueprint glitch, gerbil tunnel issue, "
                        f"traefik routing, or LE cert problem."
                    ),
                )
                alerted = True

        state_set(state_key, {
            "consecutive_failures": failures,
            "alerted": alerted,
            "reason": reason,
        })


if __name__ == "__main__":
    main()
