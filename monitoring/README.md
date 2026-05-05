# monitoring stack

Self-hosted notification fan-out and probe machinery for the homelab.
`apprise-api` accepts tagged HTTP POSTs from other services, routes by tag to
one or more `ntfy` topics, and `ntfy` delivers to the mobile app (with iOS
instant push via the upstream ntfy.sh APNs gateway). Two helper containers
turn local signals into notifications: `events-watcher` translates docker
healthcheck transitions, and `service-checks` runs cron-driven probes
(IPTV-specific, plus an end-to-end public-URL availability check).

## Services

- **apprise-api** (`caronc/apprise:latest`) — central notification router.
  In-docker: `apprise-api:8000`. Public URL: `apprise.${DOMAIN}` (Pangolin
  SSO, Member role).
- **ntfy** (`binwiederhier/ntfy:latest`) — push delivery. Public URL:
  `ntfy.${DOMAIN}` (no Pangolin SSO; ntfy uses topic-name secrecy and the
  upstream ntfy.sh access token for instant push).
- **events-watcher** (custom alpine + docker-cli) — tails
  `docker events --filter event=health_status` and POSTs `tag=critical`
  on unhealthy transitions, `tag=info` on recovery. State file under
  the shared `monitoring-state` volume dedups across container restarts.
- **service-checks** (custom alpine + supercronic + python3) — cron host
  for the probe scripts under `service-checks/checks/`. Schedule lives
  in `service-checks/crontab`. Uses supercronic instead of dcron (dcron
  hits Docker's default seccomp profile and crash-loops on `setpgid`).

## Notification topics & tag routing

`monitoring/apprise/monitoring.yaml.template` is committed with `{{TOPIC_*}}`
placeholders; `render-config.sh` substitutes the actual topic names from
1Password (`op://Personal/Ntfy/topic-{iptv,cam,public-infra,general}`) at
`make inject-secrets` time. The rendered `monitoring.yaml` is gitignored.

| Tag                           | Lands on topic                         | Source of alerts                                     |
|-------------------------------|----------------------------------------|------------------------------------------------------|
| `iptv`                        | `notify-iptv-<rand>`                   | service-checks IPTV probes (auth, channels, EPG, renewal, canary) |
| `cam`                         | `notify-cam-<rand>`                    | cnotify availability transitions                     |
| `public-infra`                | `notify-public-infra-<rand>`           | public-availability HEAD probe — proxy/edge breakage |
| `critical`, `warning`, `info` | `notify-general-<rand>`                | events-watcher container transitions, anything else  |

A `public-infra` alert without a corresponding general/critical alert means
the container is fine internally and the public proxy/edge path is the
failure surface (stale newt TCP proxy, traefik/gerbil/edge issue, LE cert).

## Apprise config registration

apprise-api stores configs by token; YAML files dropped into `/config` are
not auto-loaded. The rendered `monitoring.yaml` must be POSTed to
`/add/monitoring` once after each render:

```bash
make monitoring-config-load
```

The registered config persists in the bind-mounted `/config` volume across
container restarts, so this only runs on first setup or after editing the
template / rotating topics. To rotate topics: change values in 1Password,
then `make inject-secrets && make monitoring-config-load` and re-subscribe
on the mobile app.

## Sending a notification (from inside docker)

```bash
docker exec <container> curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"title":"hello","body":"world","tag":"critical"}' \
  http://apprise-api:8000/notify/monitoring
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
| `public-availability.py`     | every minute | HEAD probe of each public dephekt.net subdomain  |

All scripts use the shared `_lib.py` (`read_secret`, `notify`, `state_get/set`,
`@check_main` decorator). Per-script and per-target state files persist in
the `monitoring-state` named volume so transitions dedup across container
restarts.

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
