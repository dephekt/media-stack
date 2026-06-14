# kanban

Shared Kanboard deployment for agent-driven project tracking.

## Service

- **kanban-router** - LAN and Pangolin-facing front door.
- **kanboard** - Kanboard application, pinned to `kanboard/kanboard:v1.2.51`
  with the OAuth2 plugin baked into a local image.
- **kanboard-oauth-init** - one-shot container that writes Keycloak OAuth2
  settings into the Kanboard database.
- **kanban-ref** - prefix-aware redirector for links such as `/i/HGC-001`.

Public URL:

```text
https://kanban.ai.dephekt.net
```

LAN fallback URL:

```text
http://containers.home.arpa:8097
```

The public route is registered through Pangolin/Newt, but Pangolin SSO is
disabled for this resource. Kanboard login is handled by Keycloak OIDC in the
`home` realm. The LAN route is a direct host port on the media-server Docker
context, so it remains usable when the internet/Pangolin path is down.

## Authentication

Keycloak owns login eligibility for the `kanboard` OIDC client:

- client roles: `kanboard-user`, `kanboard-admin`
- assignment groups: `kanboard-users`, `kanboard-admins`
- the custom `kanboard-browser` flow denies users without
  `kanboard.kanboard-user`
- the `kanboard_roles` claim exposes Kanboard-specific group membership to the
  Kanboard OAuth2 plugin

Kanboard owns application roles. OIDC-created users start as normal Kanboard
users; promote administrators inside Kanboard. Keep the local `admin` user as a
break-glass account for local/offline access.

The Keycloak client intentionally leaves PKCE disabled because the Kanboard
OAuth2 plugin used by this deployment does not send `code_challenge` parameters.

Kanboard stores one application URL, so the OIDC callback is the public
`https://kanban.ai.dephekt.net/oauth/callback`. The LAN route remains available
for direct Kanboard access and the local `admin` fallback.

Configure the Keycloak side from this checkout:

```bash
kanban/keycloak/configure-kanboard-client.sh
```

The script is idempotent and stores the generated client secret in
`op://Agents/Kanboard/oauth client secret`.

## Secrets

`make inject-agent-secrets` renders the ignored file
`kanban/secrets/kanboard.env` from the `op://Agents/Kanboard` 1Password item.
Required fields:

- `password` - admin web password.
- `api token` - Kanboard JSON-RPC token.
- `oauth client secret` - Keycloak OIDC client secret for the `kanboard`
  client.

The API username is Kanboard's built-in `jsonrpc` user.

Reference prefix mappings live in `kanban/ref/projects.yaml` and are copied into
the redirector image at build time.

## Deploy

```bash
make inject-agent-secrets
make sync-secrets-media
make kanban-up
```

Health checks:

```bash
curl http://containers.home.arpa:8097/healthcheck.php
curl https://kanban.ai.dephekt.net/healthcheck.php
```

Reference redirects:

```bash
curl -I http://containers.home.arpa:8097/i/HGC-001
curl -I https://kanban.ai.dephekt.net/i/HGC-001
```
