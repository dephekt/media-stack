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

# Discord webhooks. Stored in 1Password as full webhook URLs
# (https://discord.com/api/webhooks/<id>/<token>); we parse them into
# id/token here because Apprise's discord:// scheme takes those components
# directly rather than the raw URL.
parse_discord_webhook() {
  # Args: <op_ref> <out_id_var> <out_token_var>
  _url="$(op read "$1")" || { echo "ERROR: failed to read $1" >&2; exit 1; }
  _id="$(printf '%s' "$_url" \
    | sed -nE 's|^https://discord(app)?\.com/api/webhooks/([0-9]+)/([A-Za-z0-9_-]+).*$|\2|p')"
  _token="$(printf '%s' "$_url" \
    | sed -nE 's|^https://discord(app)?\.com/api/webhooks/([0-9]+)/([A-Za-z0-9_-]+).*$|\3|p')"
  if [ -z "$_id" ] || [ -z "$_token" ]; then
    echo "ERROR: could not parse Discord webhook URL from $1 into id/token" >&2
    echo "       expected form: https://discord.com/api/webhooks/<id>/<token>" >&2
    exit 1
  fi
  eval "$2=\$_id"
  eval "$3=\$_token"
}

parse_discord_webhook 'op://Personal/rsyduej7c4oak4uhm7v54ku7dm/alert-webhook' \
  DISCORD_IPTV_ID DISCORD_IPTV_TOKEN
parse_discord_webhook 'op://Personal/rsyduej7c4oak4uhm7v54ku7dm/infra-webhook' \
  DISCORD_INFRA_ID DISCORD_INFRA_TOKEN
parse_discord_webhook 'op://Personal/rsyduej7c4oak4uhm7v54ku7dm/cam-webhook' \
  DISCORD_CAM_ID DISCORD_CAM_TOKEN

sed \
  -e "s|{{TOPIC_IPTV}}|$TOPIC_IPTV|g" \
  -e "s|{{TOPIC_GENERAL}}|$TOPIC_GENERAL|g" \
  -e "s|{{TOPIC_CAM}}|$TOPIC_CAM|g" \
  -e "s|{{TOPIC_PUBLIC_INFRA}}|$TOPIC_PUBLIC_INFRA|g" \
  -e "s|{{DISCORD_IPTV_ID}}|$DISCORD_IPTV_ID|g" \
  -e "s|{{DISCORD_IPTV_TOKEN}}|$DISCORD_IPTV_TOKEN|g" \
  -e "s|{{DISCORD_INFRA_ID}}|$DISCORD_INFRA_ID|g" \
  -e "s|{{DISCORD_INFRA_TOKEN}}|$DISCORD_INFRA_TOKEN|g" \
  -e "s|{{DISCORD_CAM_ID}}|$DISCORD_CAM_ID|g" \
  -e "s|{{DISCORD_CAM_TOKEN}}|$DISCORD_CAM_TOKEN|g" \
  "$TEMPLATE" > "$OUT"

echo "Rendered $OUT (apprise config) from template + 1Password topics"
