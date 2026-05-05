# pangolin

Pangolin (self-hosted reverse proxy / control-plane with WireGuard tunnels via Gerbil) running on the edge VPS at `pangolin.dephekt.net`.

## Deployment

Deploy from the local box — the `pangolin-edge` Docker context forwards all commands over SSH to `root@pangolin.dephekt.net`:

```sh
make inject-secrets      # render config.yml + write pangolin.env from 1Password
make sync-secrets-pangolin  # rsync compose + rendered config to the edge host
make pangolin-up         # docker compose up -d via pangolin-edge context
```

## State

Runtime state lives at `/opt/pangolin/config/` on the edge host and is NOT tracked in git:

- `config/db/db.sqlite` — Pangolin SQLite database
- `config/letsencrypt/acme.json` — Let's Encrypt certificates
- `config/key` — Gerbil WireGuard private key
- `config/GeoLite2-Country.mmdb` — GeoIP database (auto-fetched by Pangolin)
- `config/logs/`, `config/traefik/logs/` — transient log files

These paths are bind-mounted by the compose file; `make sync-secrets-pangolin` never touches them (no `--delete` flag).

## Render flow

`make inject-secrets` does two things for this stack:

1. Reads `op://Develop/Cloudflared API/credential` and writes `secrets/pangolin.env` as `CLOUDFLARE_DNS_API_TOKEN=<value>`. Traefik loads this via `env_file` for the DNS-01 Let's Encrypt challenge.

2. Calls `config/render-config.sh`, which reads three secrets from `op://Develop/Self-Hosted Pangolin` (`server-secret`, `smtp-user`, `smtp-pass`) and substitutes them into `config/config.yml.template`, producing the gitignored `config/config.yml`.

## EE license key

The Pangolin EE license key is set once via the Pangolin web dashboard at `https://pangolin.dephekt.net`. It is stored in the SQLite database (not in compose or config files) and survives restarts without re-entry.
