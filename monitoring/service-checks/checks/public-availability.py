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
"""
import os, urllib.error, urllib.request
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


def probe(host: str) -> tuple[bool, str | None]:
    """Return (is_up, reason_if_down)."""
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


@check_main("public-availability")
def main():
    for host in DOMAINS:
        is_up, reason = probe(host)
        state_key = f"public_avail_{host}"
        prev = state_get(state_key, {"up": True, "reason": None})
        prev_up = prev.get("up", True)

        status = "OK" if is_up else f"FAIL  {reason}"
        print(f"[public-availability] {host:<30} {status}")

        if not is_up and prev_up:
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
                    f"({reason}). The container healthcheck and newt's "
                    f"target healthcheck are blind to this layer -- "
                    f"likely a stale newt TCP proxy, Pangolin blueprint "
                    f"glitch, gerbil tunnel issue, traefik routing, or "
                    f"LE cert problem."
                ),
            )
        elif is_up and not prev_up:
            notify(
                tags=["public-infra"],
                title=f"Public URL recovered: {host}",
                body=f"https://{host}/ probe succeeding again.",
            )

        state_set(state_key, {"up": is_up, "reason": reason})


if __name__ == "__main__":
    main()
