# media-stack

**A self-hosted, Docker-based platform for sharing my home apps — streaming, photos, chat, and more — with family and friends.**

I built this to give the people I share with a polished experience that hides all the moving parts. No VPN to install, no pile of weird links to remember, no separate password for every app. They visit a friendly link on my domain, sign in once, and everything just works in a browser.

## What my users never have to deal with

- Installing a VPN or any client software
- Knowing or caring which components are involved
- Tracking a dozen links to complicated apps
- A different login for every service

As an engineer who loves my friends but has very little time to spare, getting there meant building on a few non-negotiables:

- **Enterprise identity (SSO)** and access management
- **Familiar git-based DevOps** patterns
- **Containerized** runtime and deployment
- A **support and login portal** as the front door

## How it works

Two ideas carry the whole platform:

1. **A Pangolin edge proxy authenticates and routes every request.** Pangolin runs on a small VPS at the internet edge. Each stack at home runs a **Newt** tunnel client that *dials out* to Pangolin over WireGuard — so **nothing at home needs an open inbound port**. Pangolin terminates TLS, optionally checks the user's login, and forwards to the right container.
2. **Keycloak is the single identity provider.** One account unlocks everything, with Google and Apple social login available.

```
                Internet
                   │  HTTPS (automatic TLS)
                   ▼
   ┌───────────────────────────────────┐
   │  Pangolin  ·  edge VPS            │   Traefik (TLS) + Gerbil (WireGuard)
   │  authenticates + routes requests  │
   └───────────────┬───────────────────┘
                   │  over a WireGuard tunnel that
                   │  Newt dials OUT to the edge —
                   │  no inbound ports at home
                   ▼
   ┌───────────────────────────────────┐
   │  Newt  ·  home host               │   finds containers by Docker label
   └───────────────┬───────────────────┘
                   ▼
   Jellyfin · Immich · Matrix · Kanboard · Penpot · …
   each an independent Docker Compose project
```

No client software is required. For the user it's just HTTPS in a browser.

### One login for everything

Identity is managed by **Keycloak**. Services with native OIDC/SAML (Immich, Penpot, Pangolin itself) use Keycloak directly as their identity provider. Apps with no auth of their own get **Pangolin's** login put in front of them — backed by the same Keycloak, so it's still one account.

Jellyfin is the awkward one: it only federates auth through an **LDAP** directory. So I run **OpenLDAP** and configure Keycloak to federate with it, making OpenLDAP the password backend. Keycloak syncs its users and groups into OpenLDAP's schema, so when Jellyfin asks LDAP to authenticate someone, it also sees their Keycloak group membership:

- member of `streaming` → gets a Jellyfin account
- member of `streaming` **and** `admin` → becomes a Jellyfin admin

The result: users have one username and password for everything — whether the auth is proxied by Pangolin, handled natively by Keycloak, or checked by LDAP for Jellyfin — and they never need to know Pangolin or OpenLDAP exist. They only ever see Keycloak.

### The landing page

A **Hugo** static site (`core` → `homepage`) is the front door: support guides written in Markdown, login and help links, and — once a user is signed in through Pangolin's Keycloak-backed auth — an apps grid linking to everything they can reach, grouped by category (streaming, photos, AI, …). It's built in CI, published to a container registry, and pulled on deploy.

## What's inside

Every top-level directory is an **independent Docker Compose project**, stitched together by the root `Makefile`. They don't depend on one another at the compose level — they couple only through a few shared Docker networks (`proxy`, `core`, `monitoring`, `grow-mqtt`) and the shared Keycloak/LDAP identity. Grouped the way the project's architecture sees them:

**Edge & identity — the foundation**

| Stack | What it is |
|---|---|
| [`pangolin/`](pangolin/README.md) | The Pangolin reverse-proxy / control plane (Traefik + Gerbil WireGuard), deployed to the edge VPS via its own `pangolin-edge` Docker context |
| [`core/`](core/) | The shared backbone: **Newt** tunnel client, **Keycloak** (`auth`), **OpenLDAP** (`ldap`), **MariaDB** (`db`), the **Hugo** homepage, the **WUD** update notifier, and the MkDocs `agent-kb` docs site |

**Media & streaming — the reason all the rest exists**

| Stack | What it is |
|---|---|
| [`media/`](media/) | Jellyfin (streaming + GPU transcode → `stream.${DOMAIN}`), Sonarr, Radarr, NZBGet, and Jellyseerr (requests) |
| [`immich/`](immich/README.md) | Self-hosted photos & video at `photos.${DOMAIN}` — server, ML, PostgreSQL, Valkey, with Intel Arc acceleration |
| [`channels/`](channels/) | Channels DVR (host networking + GPU transcode); config and recordings live on the Docker host |
| [`iptv/`](iptv/) | IPTVBoss — the noVNC management UI plus an XtremeCodes guide/playlist server, both behind SSO |

**Communication & messaging**

| Stack | What it is |
|---|---|
| [`matrix/`](matrix/README.md) | Tuwunel homeserver (`matrix.${DOMAIN}`) + Element Web (`chat.${DOMAIN}`) for family/friends chat |
| [`mqtt/`](mqtt/README.md) | Mosquitto **site** broker + **central** aggregator, joined by a durable bridge — the MQTT spine for the grow-control system |
| [`grow/`](grow/README.md) | LAN-local grow-app HMI on port `3080`, riding the shared MQTT network |

**Collaboration & knowledge**

| Stack | What it is |
|---|---|
| [`kanban/`](kanban/README.md) | Shared Kanboard tracker at `kanban.ai.dephekt.net` (LAN fallback `http://containers.home.arpa:8097`) |
| [`penpot/`](penpot/README.md) | Self-hosted Penpot design workspace at `design.ai.${DOMAIN}` (Keycloak OIDC directly; Pangolin only does ingress/TLS) |
| [`cci/`](cci/README.md) | The CCI Black Book MCP retrieval service at `cci.ai.${DOMAIN}/mcp` — bearer auth, bounded cited evidence packs (the stack's one first-party application) |

**Operations**

| Stack | What it is |
|---|---|
| [`monitoring/`](monitoring/README.md) | A notification router (apprise-api) plus custom probes and a Docker-health watcher, backed by two off-box SaaS witnesses (UptimeRobot, Healthchecks.io) so that a *dead watcher gets noticed too*. Public status page: [status.dephekt.net](https://status.dephekt.net/) |

## Running it

Everything goes through the root **`Makefile`** — never call `docker compose` directly. A bare invocation skips the env exports the Makefile sets, which would render `${DOMAIN}` empty in the Pangolin labels and break routing. The Makefile generates per-stack and per-service targets and runs Compose against **remote SSH Docker contexts** (the `media-server` host for most stacks, `pangolin-edge` for the edge VPS). Secrets are pulled from **1Password** at deploy time and surfaced to containers as Docker secrets.

```bash
make inject-secrets && make sync-secrets && make up   # full deploy
make <stack>-up                                        # one stack, e.g. core-up
make <svc>-restart                                     # one service, e.g. auth-restart
make                                                   # list every generated target
```

The full operator reference — shared networks, the secrets workflow, Blueprint/Newt internals, and linting — lives in [`AGENTS.md`](AGENTS.md).

## Adding a new service (Pangolin Blueprints)

You don't edit the proxy to expose something new — you label the container and Newt autodiscovers it:

```yaml
labels:
  - "pangolin.proxy-resources.app.name=My App"
  - "pangolin.proxy-resources.app.protocol=http"
  - "pangolin.proxy-resources.app.full-domain=app.${DOMAIN}"
  - "pangolin.proxy-resources.app.targets[0].enabled=true"
  - "pangolin.proxy-resources.app.targets[0].port=8080"
  # optional: put Keycloak SSO in front
  - "pangolin.proxy-resources.app.auth.sso-enabled=true"
  - "pangolin.proxy-resources.app.auth.sso-roles[0]=Member"
```

Pangolin auto-provisions the branded domain and its TLS certificate. The exhaustive label schema is documented in [`AGENTS.md`](AGENTS.md).

## Certificates and HTTPS

TLS termination and certificate provisioning/renewal are handled entirely by Pangolin (Traefik + Let's Encrypt via Cloudflare DNS-01) at the edge — there's nothing to manage per app.

## Acknowledgements

**[Dashboard Icons](https://github.com/homarr-labs/dashboard-icons)** — over 1,800 curated icons for services, applications, and tools, designed for dashboards and app directories. They power the homepage service icons. Browse the collection at [dashboardicons.com](https://dashboardicons.com/).
