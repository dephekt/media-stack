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

## Apprise config — template + render flow

ntfy has no OIDC support and the docker repo is public, so committing literal
topic names into `monitoring.yaml` would let anyone read the repo, subscribe
to our topics, and see all notifications. Instead:

- `monitoring/apprise/monitoring.yaml.template` is committed (with `{{TOPIC_*}}`
  placeholders).
- `monitoring/apprise/monitoring.yaml` is gitignored and rendered from the
  template by `monitoring/apprise/render-config.sh` at `make inject-secrets`
  time, using topic values from 1Password (`op://Personal/Ntfy/topic-iptv`
  and `op://Personal/Ntfy/topic-general`).

After `make inject-secrets`, the rendered config is registered with apprise-api
via:

```bash
make monitoring-config-load
```

This POSTs the YAML to `apprise-api`'s `/add/monitoring` endpoint, which stores
it in the bind-mounted `/config` volume. The registered config persists across
container restarts, so `monitoring-config-load` only needs to run on setup
or after editing the template / rotating topics.

To rotate topic names: change the values in 1Password, then run
`make inject-secrets && make monitoring-config-load` and re-subscribe on the
mobile app.

## Sending a notification (from inside docker)

```bash
docker exec <some-container> curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"title":"hello","body":"world","tag":"critical"}' \
  http://apprise-api:8000/notify/monitoring
```

Tag routing (per `monitoring.yaml.template`):

| Tag                          | Lands on topic              |
|------------------------------|-----------------------------|
| `iptv`                       | `{{TOPIC_IPTV}}` (from 1P)  |
| `critical`, `warning`, `info`| `{{TOPIC_GENERAL}}` (from 1P) |

The full topic URL for mobile subscription is
`https://ntfy.dephekt.net/<topic>`.

## Apprise YAML schema gotcha

A URL with a tag must indent `tag:` **deeper** than the URL key (i.e., as a
mapping value of the URL entry, not as a sibling). The 4-space-indent form
parses zero tags; 6-space-indent (or any indent strictly deeper than the
list's `-`) parses correctly. The Apprise wiki examples under-document this.
See the comment at the top of `apprise/monitoring.yaml.template`.
