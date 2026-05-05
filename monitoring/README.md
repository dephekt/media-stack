# monitoring stack

Self-hosted notification fan-out: `apprise-api` accepts tagged HTTP POSTs from
other services in the homelab, routes by tag to one or more `ntfy` topics,
which the user subscribes to via the ntfy mobile app.

## Phase 1 services

- **apprise-api** (`caronc/apprise:latest`) — central notification router.
  Reachable in-docker at `apprise-api:8000`. Public URL: `apprise.dephekt.net`
  (Pangolin SSO, Member role).
- **ntfy** (`binwiederhier/ntfy:latest`) — push delivery. Public URL:
  `ntfy.dephekt.net` (no SSO; ntfy handles its own auth at the topic level).

Future phases add `events-watcher` (docker-events → apprise) and
`service-checks` (cron-driven IPTV probes → apprise).

## Apprise config registration

`apprise-api` does **not** auto-load YAML files dropped into `/config`. The
config at `monitoring/apprise/monitoring.yaml` must be POSTed to the
`/add/monitoring` endpoint to register it under the `monitoring` token.

After **first deploy** or **any edit** to `monitoring.yaml`:

```bash
make monitoring-config-load
```

The registered config persists in apprise-api's bind-mounted `/config` volume
across container restarts and host reboots, so this only needs to be run on
setup or on YAML changes — not on every `make monitoring-up`.

## Sending a notification (from inside docker)

```bash
docker exec <some-container> curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"title":"hello","body":"world","tag":"critical"}' \
  http://apprise-api:8000/notify/monitoring
```

Tag routing (per `monitoring.yaml`):

| Tag                          | Lands on topic                       |
|------------------------------|--------------------------------------|
| `iptv`                       | `notify-iptv-bfa34c04458e4c3f`       |
| `critical`, `warning`, `info`| `notify-general-b0501a75ac11fc8b`    |

The full topic URL for mobile subscription is
`https://ntfy.dephekt.net/<topic>`.

## Apprise YAML schema gotcha

A URL with a tag must indent `tag:` **deeper** than the URL key (i.e., as a
mapping value of the URL entry, not as a sibling). The 4-space-indent form
parses zero tags; 6-space-indent (or any indent strictly deeper than the
list's `-`) parses correctly. The Apprise wiki examples under-document this.
See the comment at the top of `apprise/monitoring.yaml`.
