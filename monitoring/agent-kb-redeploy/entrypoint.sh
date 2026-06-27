#!/bin/sh
# Log into GHCR once so `docker compose pull` can fetch agent-kb even if the
# package is private or visibility has not been opened yet, then hand off to
# supercronic. The daemon (media-server) holds no registry creds of its own --
# every pull's auth comes from the client, which here is this container.
set -eu

if [ -s /run/secrets/GHCR_READ_TOKEN.env ]; then
  docker login ghcr.io -u "${REGISTRY_USER:-dephekt}" \
    --password-stdin < /run/secrets/GHCR_READ_TOKEN.env
else
  echo "WARN: /run/secrets/GHCR_READ_TOKEN.env missing/empty -- authenticated GHCR pulls will fail" >&2
fi

exec supercronic /etc/supercronic/crontab
