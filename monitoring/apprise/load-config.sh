#!/bin/sh
# Register monitoring/apprise/monitoring.yaml with the apprise-api container
# under the 'monitoring' token. Idempotent: safe to re-run after YAML edits.
#
# apprise-api requires configurations to be POSTed to /add/<token>; it does not
# auto-load files dropped into /config. The registered config persists across
# container restarts via the bind-mounted /config volume, so this script only
# needs to run on initial setup or after editing monitoring.yaml.
set -eu

DOCKER_CONTEXT="${DOCKER_CONTEXT:-default}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
YAML="$(cat "$SCRIPT_DIR/monitoring.yaml")"
PAYLOAD="$(jq -n --arg cfg "$YAML" --arg fmt yaml '{config:$cfg, format:$fmt}')"

docker --context "$DOCKER_CONTEXT" exec -i apprise-api \
  curl -fsS -X POST -H "Content-Type: application/json" \
  --data-binary "$PAYLOAD" \
  "http://localhost:8000/add/monitoring" >/dev/null

echo "Apprise 'monitoring' config registered (POST /add/monitoring)"
