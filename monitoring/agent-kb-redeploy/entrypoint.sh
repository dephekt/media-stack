#!/bin/sh
# Log into the codeberg registry once (REGISTRY_DEPLOY_KEY, reused from CI) so
# `docker compose pull` can fetch the private agent-kb image, then hand off to
# supercronic. The daemon (media-server) holds no registry creds of its own --
# every pull's auth comes from the client, which here is this container.
set -eu

if [ -s /run/secrets/REGISTRY_DEPLOY_KEY.env ]; then
  docker login codeberg.org -u "${REGISTRY_USER:-stackdrift}" \
    --password-stdin < /run/secrets/REGISTRY_DEPLOY_KEY.env
else
  echo "WARN: /run/secrets/REGISTRY_DEPLOY_KEY.env missing/empty -- pulls of the private image will fail" >&2
fi

exec supercronic /etc/supercronic/crontab
