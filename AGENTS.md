### Quick reference for AI agents and power users

Read `README.md` first. This is a reference, not a tutorial.

## Components at a glance
### Core Infrastructure
- **Pangolin (cloud)**: Management platform for monitoring self-hosted nodes. Handles health checks, failover, and resource configuration
- **Pangolin self-hosted nodes**: 4 geographically distributed VPSes (Toronto, Singapore, France, Seattle) providing edge ingress and TLS termination. Traffic flows via WireGuard tunnels between edge nodes and Newt
- **Newt**: Local agent on this infrastructure. Autodiscovers Docker containers via labels (Pangolin Blueprints) and registers proxy resources with Pangolin
- **Keycloak (`auth`)**: Identity provider; OIDC/SAML, user federation
- **OpenLDAP (`ldap`)**: Directory service; federated with Keycloak
- **MariaDB (`db`)**: Database for Keycloak

### Applications
- **Media Stack** (`media/`): Jellyfin (streaming), Radarr (movies), Sonarr (TV), NZBGet (downloads)
- **Immich** (`immich/`): Photo management at `https://photos.${DOMAIN}`
- **IPTVBoss** (`iptv/`): IPTV management and XC server
- **Tech Blog** (`tech-blog/`): Hugo static site for dephekt.net

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
├─ Makefile                      # Project orchestration
├─ core/
│  ├─ docker-compose.yml         # Newt, Keycloak, MariaDB, OpenLDAP
│  ├─ config.env                 # Non-secret config (DOMAIN, DB settings, etc.)
│  └─ secrets/                   # One-file-per-secret (git-ignored)
│     ├─ KEYCLOAK_ADMIN_PASSWORD.env
│     ├─ DB_PASSWORD.env
│     ├─ MARIADB_ROOT_PASSWORD
│     ├─ LDAP_ADMIN_PASSWORD
│     ├─ NEWT_ID.env
│     └─ NEWT_SECRET.env
├─ media/
│  └─ docker-compose.yml         # Jellyfin, Radarr, Sonarr, NZBGet
├─ immich/
│  ├─ docker-compose.yml         # Immich services
│  └─ .env                       # Immich-specific config
├─ iptv/
│  └─ docker-compose.yml         # IPTVBoss, XC server
├─ keycloak-import/              # Realm imports (git-ignored)
└─ keycloak-export/              # Realm exports (git-ignored)
```

## Environment & secrets
- **Core config** (`core/config.env`): `DOMAIN`, `KC_DB`, `KC_DB_USERNAME`, `KC_DB_URL`, `LDAP_BASE_DN`, `PANGOLIN_ENDPOINT`
- **Core secrets** (`core/secrets/`): `KEYCLOAK_ADMIN_PASSWORD.env`, `DB_PASSWORD.env`, `MARIADB_ROOT_PASSWORD`, `LDAP_ADMIN_PASSWORD`, `NEWT_ID.env`, `NEWT_SECRET.env`
- Generate secrets: `make inject-secrets` (uses 1Password CLI)
- Secrets are `.env` files containing single values; sourced into containers via Docker Compose secrets

## Makefile
**Always use the Makefile** - Do not call `docker compose` directly. The Makefile ensures consistent project names and proper context for all operations.

### Project Structure
Each project has explicit variables for consistent naming:
- `CORE_PROJECT=core` - Newt, Keycloak, MariaDB, OpenLDAP
- `MEDIA_PROJECT=media` - Jellyfin, Radarr, Sonarr, NZBGet  
- `IMMICH_PROJECT=immich` - Immich services
- `IPTV_PROJECT=iptv` - IPTVBoss, XC server

All `docker compose` commands use explicit `-p $(PROJECT_NAME)` and `--project-directory` flags.

### Key Patterns
- **Secrets management**: `make inject-secrets` (from 1Password), `make check-secrets` (validation)
- **Project targets**: `<project>-up`, `<project>-down`, `<project>-restart`, `logs-<project>`
- **Service-specific targets**: `auth-up`, `auth-restart`, `ldap-restart`, etc. for granular control
- **Remote deployment**: `make sync-secrets` uses rsync to copy secrets/config to remote Docker context

### Common Commands
```bash
make inject-secrets          # Generate all secrets from 1Password
make up                      # Start core stack (checks secrets first)
make media-up                # Start media stack
make auth-restart            # Restart Keycloak
make logs-core               # View core logs
```

Run `make` without arguments to see all available targets.

## Deployment
### Local deployment
```bash
make inject-secrets && make up
```

### Remote deployment (SSH context)
```bash
docker context create remote --docker "host=ssh://user@host"
docker context use remote
make up
```

**Note**: Bind-mount host paths resolve on the remote host. Ensure required files/dirs exist there. Named volumes are managed by the remote engine.

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
```

**See**: [Pangolin Blueprints documentation](https://docs.pangolin.net/manage/blueprints#docker-labels-format)

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
