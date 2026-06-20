# penpot

Self-hosted Penpot design workspace for grow-app HMI redesign work.

## Service

- Public URL: `https://design.ai.dephekt.net`.
- Internal URL: `http://containers.home.arpa:9001`.
- Auth: Penpot uses Keycloak OIDC directly. Pangolin only routes TLS traffic;
  its SSO gate is disabled for this resource.
- OIDC client ID: `penpot`.
- Keycloak redirect URI: `https://design.ai.dephekt.net/api/auth/oidc/callback`.
- MCP: enabled through Penpot's built-in MCP server.

## Secrets

`make inject-secrets` renders `penpot/secrets/penpot.env` from 1Password:

| Variable | 1Password source |
|---|---|
| `PENPOT_SECRET_KEY` | `op://Develop/Penpot/secret key` |
| `PENPOT_DATABASE_PASSWORD` | `op://Develop/Penpot/database password` |
| `POSTGRES_PASSWORD` | same value as `PENPOT_DATABASE_PASSWORD` |
| `PENPOT_OIDC_CLIENT_SECRET` | `op://Develop/Penpot/OIDC client secret` |

Generate `PENPOT_SECRET_KEY` once with:

```bash
python3 -c "import secrets; print(secrets.token_urlsafe(64))"
```

## Deploy

```bash
make inject-secrets
make sync-secrets-media
make penpot-up
```

Health checks:

```bash
curl http://containers.home.arpa:9001/
curl https://design.ai.dephekt.net/
```

## Backup and Restore Notes

Persistent data lives in Docker volumes on the media server:

- `penpot_penpot-postgres-v15` stores the PostgreSQL database.
- `penpot_penpot-assets` stores uploaded assets and design media.

Before upgrades, dump the database from `penpot-postgres` and snapshot both
volumes on the media server. Restores need the database dump, the assets volume,
and the same `PENPOT_SECRET_KEY`; rotating that key invalidates existing
sessions and invitations.
