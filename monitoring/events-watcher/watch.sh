#!/bin/sh
set -u
APPRISE_URL="${APPRISE_URL:-http://apprise-api:8000/notify/monitoring}"
STATE_DIR="${STATE_DIR:-/state}"
STATE_FILE="$STATE_DIR/events-watcher-last-status.json"
mkdir -p "$STATE_DIR"
[ -f "$STATE_FILE" ] || echo '{}' > "$STATE_FILE"

# Background heartbeat to healthchecks.io: pings every 5 minutes so hc.io's
# dead-man check goes red (and pages via its own Discord integration) if this
# daemon ever silently dies. Skipped if HC_PING_URL_EVENTS_WATCHER is unset to
# keep local/dev runs quiet. Detached subshell so a hung curl can't stall the
# event stream.
( while true; do
    [ -n "${HC_PING_URL_EVENTS_WATCHER:-}" ] && \
      curl -fsS -m 10 "$HC_PING_URL_EVENTS_WATCHER" >/dev/null 2>&1 || true
    sleep 300
  done ) &

emit() {
  # emit <tag> <name> <title> [<body>]
  # apprise-api rejects empty bodies with HTTP 400, so substitute a
  # placeholder when the caller passes nothing (typical for recovery).
  tag="$1"; name="$2"; title="$3"; body="${4:-}"
  [ -z "$body" ] && body="(no body)"
  curl -fsS -X POST -H "Content-Type: application/json" \
    "$APPRISE_URL?tag=$tag" \
    -d "$(jq -nc --arg t "$title" --arg b "$body" '{title:$t, body:$b}')" \
    || echo "warn: apprise POST failed for $name" >&2
}

# Returns the previous status we recorded for $name (empty if none).
prev_status() { jq -r --arg n "$1" '.[$n] // ""' "$STATE_FILE"; }

# Atomically updates last-known status for $name.
set_status() {
  tmp=$(mktemp)
  jq --arg n "$1" --arg s "$2" '. + {($n): $s}' "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

# Startup pass: notify for any container *currently* unhealthy that we haven't
# already notified about. Avoids re-spamming on watcher restart.
# Containers without a healthcheck (status is empty) are silently skipped.
echo "info: startup pass — scanning running containers"
docker ps --format '{{.Names}}' | while read -r name; do
  status=$(docker inspect "$name" --format '{{.State.Health.Status}}' 2>/dev/null || echo "")
  case "$status" in
    unhealthy)
      if [ "$(prev_status "$name")" != "unhealthy" ]; then
        echo "info: $name is unhealthy — emitting critical notification"
        details=$(docker inspect "$name" --format '{{json .State.Health.Log}}' \
          | jq -r '.[-1].Output // "(no output)"')
        # jq's // doesn't fall back on empty strings -- only on null/false.
        # An exit-status-only healthcheck (no stdout) produces "" here, and
        # apprise-api rejects empty bodies with HTTP 400.
        [ -z "$details" ] && details="(no output)"
        emit critical "$name" "$name unhealthy (already)" "$details"
        set_status "$name" unhealthy
      else
        echo "info: $name is unhealthy (already notified — skipping)"
      fi
      ;;
    healthy)
      echo "info: $name is healthy — recording status"
      set_status "$name" healthy
      ;;
    "")
      # No healthcheck configured; skip silently
      ;;
    *)
      echo "info: $name has status '$status' — skipping"
      ;;
  esac
done
echo "info: startup pass complete — entering docker events stream"

# Reconnect loop: docker events is long-running and can drop on dockerd
# restart. Sleep briefly and reconnect rather than letting the container exit.
while true; do
  docker events --filter event=health_status \
    --format '{{.Actor.Attributes.name}}|{{.Status}}' \
  | while IFS='|' read -r name status; do
      case "$status" in
        "health_status: unhealthy")
          [ "$(prev_status "$name")" = "unhealthy" ] && continue
          details=$(docker inspect "$name" --format '{{json .State.Health.Log}}' \
            | jq -r '.[-1].Output // "(no output)"')
          [ -z "$details" ] && details="(no output)"
          emit critical "$name" "$name unhealthy" "$details"
          set_status "$name" unhealthy
          ;;
        "health_status: healthy")
          prev=$(prev_status "$name")
          [ "$prev" = "healthy" ] && continue
          set_status "$name" healthy
          # Only emit "recovered" if there was an actual prior unhealthy
          # state to recover FROM. A first-ever healthy event (e.g., a
          # newly-created container or one that just got a healthcheck
          # added) should silently record without notifying.
          [ "$prev" = "unhealthy" ] && emit info "$name" "$name recovered"
          ;;
      esac
    done
  echo "warn: docker events stream ended; reconnecting in 1s" >&2
  sleep 1
done
