### Quick reference for AI agents and power users

Read `README.md` first. This is a reference, not a tutorial.

## Components at a glance
### Core Infrastructure
- **Pangolin (self-hosted)**: Reverse-proxy + control plane running on a separate edge VPS at `pangolin.dephekt.net`. Managed in this repo under `pangolin/` and deployed via the `pangolin-edge` Docker context. Bundles Traefik (TLS termination) and Gerbil (WireGuard tunnel endpoint). EE license enabled.
- **Newt**: Local agent in this stack on the `containers` host. Autodiscovers Docker containers via labels (Pangolin Blueprints), registers proxy resources with Pangolin, and runs per-target healthchecks for the resources it proxies.
- **Keycloak (`auth`)**: Identity provider; OIDC/SAML, user federation.
- **OpenLDAP (`ldap`)**: Directory service; federated with Keycloak.
- **MariaDB (`db`)**: Database for Keycloak.

### Applications
- **Media Stack** (`media/`): Jellyfin (streaming), Radarr (movies), Sonarr (TV), NZBGet (downloads), Jellyseerr (requests).
- **Immich** (`immich/`): Photo management at `https://photos.${DOMAIN}`.
- **IPTVBoss** (`iptv/`): IPTV management and XC server.
- **Channels DVR** (`channels/`): Fancybits Channels DVR (host network; DVR/config volumes on the Docker host).
- **MQTT** (`mqtt/`): Daniel's grow site broker plus central aggregator. The `mqtt` network is explicitly named `grow-mqtt` so the separate `grow/` stack can attach.
- **Grow App** (`grow/`): LAN-local grow-app site HMI for Daniel's grow. No Pangolin or Keycloak in Phase 1; exposed directly on host port `3080`.

### Monitoring & alerting (`monitoring/`)
Three local containers + two SaaS witnesses; all paths land in Discord (and UptimeRobot also sends mobile push). See `monitoring/README.md` for the routing matrix and the constellation-of-alerts diagnostic pattern.
- **apprise-api**: Central notification router; accepts tagged HTTP POSTs and fans out to Discord webhooks + ntfy.sh per `monitoring/apprise/monitoring.yaml.template`.
- **events-watcher**: Tails `docker events --filter event=health_status` and turns container healthcheck transitions into `tag=critical`/`tag=info` notifications. Pings healthchecks.io every 5 min as a dead-man for the daemon itself.
- **service-checks**: supercronic-driven container running probe scripts under `service-checks/checks/` (IPTV auth, channel-count, EPG freshness, EPG canary, renewal warning). Each script pings its own hc.io check at start/success/fail via the `_lib.py` `check_main` decorator. A `*/5` heartbeat cron POSTs `tag=heartbeat` through apprise to hc.io as the apprise-pipeline dead-man.
- **UptimeRobot** (SaaS, off-box): external HTTP probes for the public dephekt.net domains. Status page at `status.dephekt.net`. Notifies via mobile push + a Discord webhook into `#public-status`. Lives outside the homelab so it still pages when home internet is down.
- **Healthchecks.io** (SaaS, off-box): dead-man checks (one per cron job, plus events-watcher and apprise-pipeline). Ping URLs are provisioned via API and stored in 1Password (`op://Personal/Healthchecks.io/ping-url-*`); render-config.sh injects them at deploy time. Alerts via hc.io's Discord integration.

## Networks
- **`proxy`** (external, shared): All frontend containers that Pangolin proxies to
- **`core`** (internal): Core services backend (auth, ldap, db)
- **`immich`** (internal): Immich services backend
- Individual projects use `proxy` for external access and their own internal networks for backends

## File structure
```
./
├─ README.md
├─ AGENTS.md                     # This file
├─ Makefile                      # Per-stack orchestration entry points
├─ Makefile.include              # Shared rule generators (STACK_RULES, SERVICE_RULES, STACK_CONTEXT helper)
├─ core/                         # newt, auth (keycloak), ldap, db (mariadb), homepage, update-manager
├─ media/                        # jellyfin, radarr, sonarr, nzbget, seerr
├─ immich/                       # immich-server, machine-learning, postgres, redis
├─ iptv/                         # iptvboss (XC server + noVNC)
├─ channels/                     # channels-dvr (host network)
├─ monitoring/                   # apprise-api, events-watcher, service-checks (+ SaaS: UptimeRobot, Healthchecks.io)
├─ pangolin/                     # pangolin server + gerbil + traefik; deploys to pangolin-edge context
├─ mqtt/                         # grow-control site broker + central aggregator
├─ grow/                         # grow-app site-mode HMI
├─ keycloak-import/              # Realm imports (git-ignored)
└─ keycloak-export/              # Realm exports (git-ignored)
```

Each stack dir contains a `docker-compose.yml`, optional `config.env`, optional `secrets/` (gitignored), and any per-stack subdirectories (`apprise/`, `events-watcher/`, `service-checks/`, `config/traefik/`, etc.). Rendered config files (e.g. `monitoring/apprise/monitoring.yaml`, `pangolin/config/config.yml`) are gitignored and reproduced from `*.template` siblings via per-stack `render-config.sh` scripts at `make inject-secrets` time.

## Environment & secrets
- **Core config** (`core/config.env`): `DOMAIN`, `KC_DB`, `KC_DB_USERNAME`, `KC_DB_URL`, `LDAP_BASE_DN`, `PANGOLIN_ENDPOINT`. Loaded by every stack via the Makefile's `include core/config.env`/`export`.
- **Per-stack secrets** live under each stack's `secrets/` directory (git-ignored by `**/secrets/`). All are written by `make inject-secrets` from 1Password.
- Single-value `.env` files (e.g. `core/secrets/NEWT_ID.env`) get exposed as Docker Compose secrets and read at runtime via the `secrets2env.sh` shim baked into the stackdrift custom images. This shim reads `/run/secrets/<NAME>.env` and exports `<NAME>` as a regular env var before exec'ing the service.
- A few stacks use `KEY=VALUE`-form env files (e.g. `monitoring/secrets/healthchecks.env`, `pangolin/secrets/pangolin.env`) consumed via Compose `env_file:` rather than the shim — used when the upstream image lacks the shim and doesn't accept `_FILE` env vars (traefik) or for our own custom images that just want plain env.
- Secret rotation: change values in 1Password, run `make inject-secrets` (re-renders any templated configs too), then `make sync-secrets` to ship to the remote and `make <stack>-up` to recreate any service whose env changed.

## Makefile
**Always use the Makefile** — never call `docker compose` directly. Direct invocations bypass the env exports the Makefile provides; in particular `${DOMAIN}` would render empty in Pangolin labels and break resource registration. Every deploy goes through `make`.

### How targets are generated
- `STACKS := core media immich iptv channels monitoring pangolin mqtt grow matrix` — list of every stack.
- `SERVICES_<stack> := svc1 svc2 ...` — per-stack service list, used to auto-generate per-service targets.
- `Makefile.include` evaluates `STACK_RULES` and `SERVICE_RULES` over those lists to emit `<stack>-up/-down/-restart/-logs` and `<svc>-up/-restart/-logs/-stop/-start` for every name. When a service name matches its stack name (e.g. `pangolin`/`pangolin`), the SERVICE_RULES generation is skipped for that service so `<name>-up` resolves to the whole-stack rule, not just one service.
- Per-stack Docker context: `STACK_CONTEXT(stack) = $(or $(CONTEXT_$(stack)),$(DOCKER_CONTEXT))`. Default is `media-server`; override per stack via `CONTEXT_<stack>=<context>`. Currently `CONTEXT_pangolin=pangolin-edge` routes pangolin's deploys to the edge VPS while every other stack lands on `media-server`.

### Sync split
`sync-secrets-media` rsyncs all media-server-bound stack files to `~/docker/` on `containers`. `sync-secrets-pangolin` rsyncs the pangolin stack to `/opt/pangolin/` on the edge VPS. Bare `sync-secrets` runs both. Neither passes `--delete`; on-host runtime state (LE certs, sqlite, gerbil keys) is preserved.

### Common commands
```bash
make inject-secrets         # Pull all secrets from 1P; render template configs
make sync-secrets           # rsync to both remote hosts
make up                     # Start every stack on its respective context
make <stack>-up             # Bring up one stack (e.g. core-up, monitoring-up)
make <svc>-restart          # Restart one service (e.g. auth-restart, apprise-api-restart)
make logs-<stack>           # Follow logs for one stack
```

Run `make` with no args to see every generated target.

## Deployment
The `containers` Docker context (alias: `media-server`) is configured at `ssh://daniel@containers`. The `pangolin-edge` context is `ssh://root@pangolin.dephekt.net`. Both are SSH-based; Docker CLI on this local box forwards commands to the remote daemon. Bind-mount paths resolve on the remote host, so absolute paths in compose files refer to the remote filesystem.

```bash
make inject-secrets && make sync-secrets && make up
```

For pangolin specifically, the compose uses absolute `/opt/pangolin/...` bind paths because relative `./config` would resolve on the local box (where the path doesn't exist) and the remote daemon would auto-create empty directories.

## Pangolin quick refs
### Blueprints
Pangolin uses **Blueprints** to declaratively configure resources via Docker labels. Newt discovers labeled containers and registers them with Pangolin.

**Label format**: `pangolin.<resource-type>.<resource-id>.<property>`

**Resource types**:
- `proxy-resources` - HTTP/TCP/UDP services exposed through Pangolin edge nodes
- `client-resources` - Services accessed via Olm clients (e.g., SSH, RDP)

**HTTP proxy resource (most common)**:
```yaml
labels:
  - "pangolin.proxy-resources.<id>.name=My App"
  - "pangolin.proxy-resources.<id>.protocol=http"
  - "pangolin.proxy-resources.<id>.full-domain=app.${DOMAIN}"
  - "pangolin.proxy-resources.<id>.targets[0].method=http"  # http, https, or h2c
  - "pangolin.proxy-resources.<id>.targets[0].port=8080"    # optional if single port exposed
```

**TCP/UDP proxy resource**:
```yaml
labels:
  - "pangolin.proxy-resources.<id>.name=My Service"
  - "pangolin.proxy-resources.<id>.protocol=tcp"  # or udp
  - "pangolin.proxy-resources.<id>.proxy-port=3000"
  - "pangolin.proxy-resources.<id>.targets[0].port=3000"
```

**Auto-detection**: When `hostname` and `port` aren't explicit, Pangolin auto-detects from container config

**Authentication** (HTTP only):
```yaml
- "pangolin.proxy-resources.<id>.auth.sso-enabled=true"
- "pangolin.proxy-resources.<id>.auth.sso-roles[0]=Member"
- "pangolin.proxy-resources.<id>.auth.auto-login-idp=1"  # straight-to-Keycloak redirect
```

**Target health monitoring** (populates Pangolin's Health column; lets Pangolin make failover decisions):
```yaml
- "pangolin.proxy-resources.<id>.targets[0].healthcheck.hostname=<docker-network-host>"
- "pangolin.proxy-resources.<id>.targets[0].healthcheck.port=<port>"
- "pangolin.proxy-resources.<id>.targets[0].healthcheck.path=/health"
```
Defaults from the schema apply: `enabled=true`, `mode=http`, `interval=30s`, `timeout=5s`, healthy/unhealthy-threshold=1. Healthcheck hostname/port can differ from the proxy target's port (e.g., Keycloak's HC is on port 9000, the proxy target is 8080).

**See**: [Pangolin Blueprints documentation](https://docs.pangolin.net/manage/blueprints#docker-labels-format). The exhaustive label schema lives in `~/dev/pangolin/server/lib/blueprints/types.ts` if a key isn't documented yet.

## Newt quick refs
### Configuration
- **Env**: `PANGOLIN_ENDPOINT`, `NEWT_ID`, `NEWT_SECRET`
- **Mount**: `/var/run/docker.sock:ro` (for Docker label discovery)

### Key Functions

**Registers with Pangolin**
- Uses Newt ID and secret to authenticate via HTTP and receive a session token
- Establishes persistent websocket connection for control messages

**Handles WireGuard Tunnels**
- Receives WireGuard control messages (endpoint, public key) over websocket
- Brings up userspace WireGuard tunnel using netstack
- Pings tunnel peer to ensure connectivity

**Creates Traffic Proxies**
- Receives proxy control messages specifying target services
- Creates local TCP/UDP proxies attached to the WireGuard tunnel
- Relays traffic from edge nodes to configured target containers

## Docker utilities
### Inspecting container labels

Two bash functions parse Docker container labels into structured JSON for efficient processing with jq:

**`docker_labels_parse`** - Converts raw Docker label strings into structured JSON with container name, project, and parsed labels
**`filter_pangolin_labels`** - Filters docker ps JSON to show only Pangolin-proxied containers (calls `docker_labels_parse` internally)

*Note: Hyphenated aliases (`docker-labels-parse`, `filter-pangolin-labels`) available for convenience*

#### Usage pattern
```bash
docker ps --format json | filter_pangolin_labels
```

#### Example output
```json
[
  {
    "name": "auth",
    "project": "core",
    "pangolin_labels": {
      "pangolin.proxy-resources.auth.full-domain": "auth.dephekt.net",
      "pangolin.proxy-resources.auth.name": "Keycloak",
      "pangolin.proxy-resources.auth.protocol": "http",
      "pangolin.proxy-resources.auth.targets[0].method": "http",
      "pangolin.proxy-resources.auth.targets[0].port": "8080"
    }
  },
  {
    "name": "jellyfin",
    "project": "media",
    "pangolin_labels": {
      "pangolin.proxy-resources.jellyfin.full-domain": "stream.dephekt.net",
      "pangolin.proxy-resources.jellyfin.name": "Jellyfin",
      "pangolin.proxy-resources.jellyfin.protocol": "http",
      "pangolin.proxy-resources.jellyfin.targets[0].enabled": "true",
      "pangolin.proxy-resources.jellyfin.targets[0].method": "http",
      "pangolin.proxy-resources.jellyfin.targets[0].port": "8096"
    }
  }
]
```

#### Why these exist
Docker's `--format json` outputs labels as a single comma-separated string requiring brittle regex parsing. These functions convert that flat string into proper JSON objects, enabling use of jq built-ins (`select()`, `map()`, `group_by()`) for efficient filtering and aggregation over container label data.

## Linting

- `make lint`         — runs ruff (Python), shellcheck (POSIX sh), yamllint (YAML)
- `make lint-py` / `lint-sh` / `lint-yaml` — individual linters
- `make format`       — applies ruff formatter to Python under `monitoring/service-checks/`
- `make format-check` — verifies Python formatting without writing

Requires:
- `uv` (https://docs.astral.sh/uv/) — runs ruff and yamllint via `uvx` without a project venv
- `shellcheck` — `apt install shellcheck`

Configs live at the repo root: `pyproject.toml` (ruff), `.shellcheckrc`, `.yamllint.yml`. The yamllint config keeps strict 2-space indentation but disables `line-length` and `document-start` (compose files have legitimately long label/URL lines and don't use `---`). The yamllint target uses `git ls-files` so rendered output like `pangolin/config/config.yml` is automatically skipped — only the committed `*.template` is linted.
