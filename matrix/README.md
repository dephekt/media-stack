# matrix

Matrix homeserver (Tuwunel) with Element Web for family and friends chat.

## Services

- **tuwunel** — Tuwunel Matrix homeserver (Rust, Apache-2.0). Uses built-in RocksDB (no PostgreSQL). Exposed via Pangolin at `matrix.${DOMAIN}`.
- **element-web** — Element Web client. Exposed via Pangolin at `chat.${DOMAIN}`.

## Secrets

Required secret files (git-ignored):

- `matrix/secrets/TUWUNEL_OIDC_CLIENT_SECRET`

Inject from 1Password:

```bash
make inject-secrets
```

Or manually:

```bash
op read "op://Develop/Matrix/client secret" > matrix/secrets/TUWUNEL_OIDC_CLIENT_SECRET
```

## Deploy

```bash
make matrix-up
```

## Configuration

Tuwunel is configured via `matrix/config/tuwunel.toml` (mounted read-only). Key settings:

- `server_name = "dephekt.net"` — immutable after first start
- `allow_registration = false` — registration is disabled; use OIDC
- `allow_federation = true` — federation enabled
- OIDC provider configured for Keycloak (`home` realm)

## First-time setup

1. Ensure `matrix.dephekt.net` and `chat.dephekt.net` DNS routes exist (Pangolin auto-provisions).
2. Run `make inject-secrets` to populate the OIDC client secret.
3. Run `make matrix-up` to start Tuwunel and Element Web.
4. The first user to log in via OIDC will be granted admin privileges.

## OIDC / SSO

Tuwunel uses Keycloak as the OIDC identity provider. The client (`tuwunel`) is configured in the `home` realm with:

- Client authentication: enabled
- Standard flow: enabled
- PKCE: S256
- Redirect URI: `https://matrix.dephekt.net/_matrix/client/unstable/login/sso/callback/tuwunel`

## Federation

This setup uses `dephekt.net` as the Matrix server name, with client traffic served from `matrix.dephekt.net`. Federation is enabled by default. Ensure DNS and Pangolin routes for `matrix.dephekt.net` are resolvable externally.

## Element Web

Element Web is configured via `matrix/config/element-web.json` to point to the Tuwunel homeserver at `https://matrix.dephekt.net`. It runs on a separate domain (`chat.dephekt.net`) for security.
