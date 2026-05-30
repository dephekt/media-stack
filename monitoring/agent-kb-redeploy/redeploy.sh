#!/bin/sh
# Scoped redeploy of just the agent-kb service in the `core` compose project.
#
# `compose pull` fetches the current image for agent-kb's tag; `up -d` recreates
# the container only when the resolved image actually changed (otherwise it's a
# no-op). The compose file + config.env are bind-mounted read-only from the
# host's synced ~/docker/core; -p core keeps the container in its real project
# so Pangolin/Newt see the same labels on the new container.
#
# Failures (e.g. a transient registry error) just exit non-zero and land in the
# container log; supercronic retries on the next tick. We deliberately do NOT
# notify on failure -- a 3-minute cron would spam apprise -- only on an actual
# image swap, which is the signal worth seeing.
set -eu

COMPOSE="docker compose -p core --env-file /core/config.env -f /core/docker-compose.yml"
SVC=agent-kb
APPRISE_URL="${APPRISE_URL:-http://apprise-api:8000/notify/monitoring}"

img() { docker inspect -f '{{.Image}}' "$SVC" 2>/dev/null || echo none; }

before=$(img)
$COMPOSE pull -q "$SVC"
$COMPOSE up -d "$SVC"
after=$(img)

if [ "$before" != "$after" ]; then
  echo "agent-kb redeployed: ${before} -> ${after}"
  curl -fsS -m 10 -X POST -H 'Content-Type: application/json' \
    -d "{\"title\":\"agent-kb redeployed\",\"body\":\"${before} -> ${after}\"}" \
    "${APPRISE_URL}?tag=info" >/dev/null 2>&1 || true
fi
