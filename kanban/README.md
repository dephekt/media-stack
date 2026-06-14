# kanban

Shared Kanboard deployment for agent-driven project tracking.

## Service

- **kanban-router** - LAN and Pangolin-facing front door.
- **kanboard** - Kanboard application, pinned to `kanboard/kanboard:v1.2.51`.
- **kanban-ref** - prefix-aware redirector for links such as `/i/HGC-001`.

Public URL:

```text
https://kanban.ai.dephekt.net
```

LAN fallback URL:

```text
http://containers.home.arpa:8097
```

The public route is registered through Pangolin/Newt. The LAN route is a direct
host port on the media-server Docker context, so it remains usable when the
internet/Pangolin path is down.

## Secrets

`make inject-agent-secrets` renders the ignored file
`kanban/secrets/kanboard.env` from the `op://Agents/Kanboard` 1Password item.
Required fields:

- `password` - admin web password.
- `api token` - Kanboard JSON-RPC token.

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
