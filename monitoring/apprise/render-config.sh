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
TOPIC_CAM="$(op read 'op://Personal/Ntfy/topic-cam')" \
  || { echo "ERROR: failed to read op://Personal/Ntfy/topic-cam" >&2; exit 1; }
TOPIC_PUBLIC_INFRA="$(op read 'op://Personal/Ntfy/topic-public-infra')" \
  || { echo "ERROR: failed to read op://Personal/Ntfy/topic-public-infra" >&2; exit 1; }

if [ -z "$TOPIC_IPTV" ] || [ -z "$TOPIC_GENERAL" ] || [ -z "$TOPIC_CAM" ] || [ -z "$TOPIC_PUBLIC_INFRA" ]; then
  echo "ERROR: empty topic value from 1Password" >&2
  exit 1
fi

sed \
  -e "s|{{TOPIC_IPTV}}|$TOPIC_IPTV|g" \
  -e "s|{{TOPIC_GENERAL}}|$TOPIC_GENERAL|g" \
  -e "s|{{TOPIC_CAM}}|$TOPIC_CAM|g" \
  -e "s|{{TOPIC_PUBLIC_INFRA}}|$TOPIC_PUBLIC_INFRA|g" \
  "$TEMPLATE" > "$OUT"

echo "Rendered $OUT (apprise config) from template + 1Password topics"
