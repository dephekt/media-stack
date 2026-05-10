# monitoring stack

Notification fan-out and probe machinery for the homelab. The stack runs
three local containers (`apprise-api`, `events-watcher`, `service-checks`)
and integrates with two SaaS witnesses (`UptimeRobot`, `Healthchecks.io`)
to give independent paths to the phone for different failure classes.

## Where alerts actually land

Everything routes to Discord, plus UptimeRobot's mobile push app for the
external-probe path. There is no longer a self-hosted notification
delivery server in this stack — `ntfy` was retired because iOS ntfy can't
mute per-topic, making Discord (mutable channels, same UX on iOS and
Android) the better surface.

| Source                                        | Path to your phone                               | Discord channel    |
|-----------------------------------------------|--------------------------------------------------|--------------------|
| `events-watcher` (container healthcheck transitions) | apprise-api → Discord webhook + ntfy.sh   | `#container-alerts`|
| `service-checks` (IPTV probes)                | apprise-api → Discord webhook + ntfy.sh          | `#iptv-alerts`     |
| `UptimeRobot` (external HTTP probes for public dephekt.net domains) | direct → push app + Discord webhook | `#public-status`   |
| `Healthchecks.io` (dead-man for cron / daemon / apprise pipeline) | direct → Discord integration  | hc.io's configured channel |

Public status page (UptimeRobot): <https://status.dephekt.net/>.

ntfy.sh is kept as a redundant secondary channel for the infra-alert tags
(iptv, critical/warning/info) — it's an independent path from Discord, so a
Discord outage wouldn't silence those alerts. Cam alerts go to Discord only.

## Constellation-of-alerts diagnosis

The three independent paths (Discord channels, UptimeRobot push,
healthchecks.io) form a truth table. Reading which alerts fired vs which
didn't is itself the diagnosis:

- **Only UptimeRobot fires (multiple domains)**: home internet is down or
  the wireguard / pangolin / newt path is broken. apprise can't reach
  Discord, so internal alerts are silent.
- **UptimeRobot + apprise both fire**: a specific service or container is
  unhealthy but the overall network path works.
- **Only healthchecks.io fires**: a check or daemon stopped silently
  (cron container died, supercronic crashed, events-watcher wedged,
  apprise lost internet egress). The thing that *would have* fired an
  alert never ran.

## Local services

- **apprise-api** (`caronc/apprise:latest`) — central notification router.
  In-docker: `apprise-api:8000`. Public URL: `apprise.${DOMAIN}` (Pangolin
  SSO, Member role). Accepts tagged HTTP POSTs and fans out per the routing
  config in `apprise/monitoring.yaml.template`.
- **events-watcher** (custom alpine + docker-cli) — tails
  `docker events --filter event=health_status` and POSTs `tag=critical`
  on unhealthy transitions, `tag=info` on recovery. State file under the
  shared `monitoring-state` volume dedups across container restarts. Also
  pings hc.io every 5 min as a dead-man for the daemon itself.
- **service-checks** (custom alpine + supercronic + python3) — cron host
  for the probe scripts under `service-checks/checks/`. Schedule in
  `service-checks/crontab`. Uses supercronic instead of dcron (dcron
  hits Docker's default seccomp profile and crash-loops on `setpgid`).
  Each cron job pings its own hc.io check URL on `/start` / success /
  `/fail` via the `_lib.py` `check_main` decorator. A separate `*/5`
  cron entry fires an apprise heartbeat that hc.io tracks as the
  alerting-pipeline witness.

## SaaS witnesses

- **UptimeRobot** — external HTTP probes for the public dephekt.net
  domains (auth, stream, requests.stream, tv.stream, photos, www,
  pangolin, iptvboss). Notification destinations: UptimeRobot's mobile
  push app + a Discord webhook into `#public-status`. Status page at
  status.dephekt.net. Lives entirely off-box, so an outage that takes
  down the whole homelab still pages the phone via SaaS push. Managed
  in the UptimeRobot web UI; nothing in this repo controls it.

- **Healthchecks.io** — dead-man checks (one per cron job, plus the
  events-watcher daemon heartbeat, plus the apprise-pipeline heartbeat).
  When a cron job's expected ping doesn't arrive within its grace
  window, hc.io alerts via its own Discord integration. The list of
  checks and their schedules is provisioned via API; ping URLs come from
  1Password (`op://Personal/Healthchecks.io/ping-url-*`) and are
  injected at deploy time by `apprise/render-config.sh`.

## Apprise tag routing

`apprise/monitoring.yaml.template` is committed with placeholders;
`render-config.sh` substitutes the actual values from 1Password
(`op://Personal/Ntfy/topic-{iptv,general}` and the Discord webhooks under
`op://Personal/.../alert-webhook|cam-webhook|infra-webhook`). The rendered
`monitoring.yaml` is gitignored.

| Tag                           | Destinations                                  | Source of alerts                                  |
|-------------------------------|------------------------------------------------|---------------------------------------------------|
| `iptv`                        | ntfy.sh `notify-iptv-<rand>` + Discord `#iptv-alerts`  | service-checks IPTV probes              |
| `critical`, `warning`, `info` | ntfy.sh `notify-general-<rand>` + Discord `#container-alerts` | events-watcher container transitions      |
| `heartbeat`                   | hc.io (`jsons://hc-ping.com/<uuid>`) — used by the apprise-pipeline cron | service-checks `*/5` heartbeat cron |

The `heartbeat` tag uses apprise's generic `jsons://` scheme rather than a
dedicated `healthchecks://` plugin (apprise 1.10 doesn't ship one). hc.io
ignores the JSON body and treats the request as a successful ping.

## Apprise config registration

apprise-api stores configs by token; YAML files dropped into `/config` are
not auto-loaded. The rendered `monitoring.yaml` must be POSTed to
`/add/monitoring` once after each render:

```bash
make monitoring-config-load
```

The registered config persists in the bind-mounted `/config` volume across
container restarts, so this only runs on first setup or after editing the
template.

## Sending a notification (from inside docker)

```bash
docker exec <container> curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"title":"hello","body":"world"}' \
  'http://apprise-api:8000/notify/monitoring?tag=critical'
```

The path is `/notify/monitoring` (the registered token name), not bare
`/notify` — the latter returns HTTP 400.

## service-checks scripts

| Script                       | Schedule    | Probes                                            |
|------------------------------|-------------|---------------------------------------------------|
| `iptv-auth.py`               | `:17` hourly | upstream `user_info.auth == 1`                    |
| `iptv-channel-count.py`      | `:23` hourly | local `get_live_streams` length vs `CHANNEL_FLOOR` |
| `iptv-epg-freshness.py`      | `:29` hourly | latest `<programme stop>` vs `EPG_MIN_FUTURE_HOURS` |
| `iptv-canary-epg.py`         | `:35` hourly | per-channel EPG presence/coverage for a watchlist |
| `iptv-renewal-warn.py`       | `09:00` daily | `exp_date - now() < EXP_WARNING_DAYS` (once/day) |
| (apprise heartbeat curl)     | `*/5` every 5 min | dead-man for the apprise → hc.io pipeline    |

External HTTP probing of public dephekt.net domains is **not** done here
— UptimeRobot owns that and its results go to the `#public-status`
Discord channel and the mobile push app.

All Python scripts use the shared `_lib.py` (`read_secret`, `notify`,
`state_get/set`, `@check_main` decorator). The decorator pings hc.io at
start / success / fail in addition to the apprise notifications, so each
cron job has both the alert-on-failure and dead-man-on-silence paths
covered.

### Editing the schedule

supercronic reads its crontab once at startup and does not watch for file
changes. After editing `service-checks/crontab`:

```bash
make sync-secrets-media     # ship the file to the host
make service-checks-restart # supercronic re-reads on restart
```

## Apprise YAML schema gotcha

A URL with a tag must indent `tag:` **deeper** than the URL key (mapping
value of the URL entry, not a sibling). The 4-space-indent form parses
zero tags; 6-space-indent (or any indent strictly deeper than the list's
`-`) parses correctly. Apprise's wiki examples under-document this. See
the header comment in `apprise/monitoring.yaml.template`.
