#!/bin/sh
# Render monitoring.yaml.template -> monitoring.yaml using topic names from
# 1Password. The rendered file is gitignored; the template is committed.
# Called automatically by `make inject-secrets`. Idempotent.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/monitoring.yaml.template"
OUT="$SCRIPT_DIR/monitoring.yaml"

TOPIC_IPTV="$(op read 'op://Personal/Ntfy/topic-iptv')" \
  || { echo "ERROR: failed to read op://Personal/Ntfy/topic-iptv" >&2; exit 1; }
TOPIC_GENERAL="$(op read 'op://Personal/Ntfy/topic-general')" \
  || { echo "ERROR: failed to read op://Personal/Ntfy/topic-general" >&2; exit 1; }

if [ -z "$TOPIC_IPTV" ] || [ -z "$TOPIC_GENERAL" ]; then
  echo "ERROR: empty topic value from 1Password" >&2
  exit 1
fi

sed \
  -e "s|{{TOPIC_IPTV}}|$TOPIC_IPTV|g" \
  -e "s|{{TOPIC_GENERAL}}|$TOPIC_GENERAL|g" \
  "$TEMPLATE" > "$OUT"

echo "Rendered $OUT (apprise config) from template + 1Password topics"
