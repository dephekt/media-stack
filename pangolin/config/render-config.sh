#!/bin/sh
# Render config.yml.template -> config.yml using secrets from 1Password.
# The rendered file is gitignored; the template is committed.
# Called automatically by `make inject-secrets`. Idempotent.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/config.yml.template"
OUT="$SCRIPT_DIR/config.yml"

SERVER_SECRET="$(op read 'op://Develop/Self-Hosted Pangolin/server-secret')" \
  || { echo "ERROR: failed to read op://Develop/Self-Hosted Pangolin/server-secret" >&2; exit 1; }
SMTP_USER="$(op read 'op://Develop/Self-Hosted Pangolin/smtp-user')" \
  || { echo "ERROR: failed to read op://Develop/Self-Hosted Pangolin/smtp-user" >&2; exit 1; }
SMTP_PASS="$(op read 'op://Develop/Self-Hosted Pangolin/smtp-pass')" \
  || { echo "ERROR: failed to read op://Develop/Self-Hosted Pangolin/smtp-pass" >&2; exit 1; }

if [ -z "$SERVER_SECRET" ] || [ -z "$SMTP_USER" ] || [ -z "$SMTP_PASS" ]; then
  echo "ERROR: empty secret value from 1Password" >&2
  exit 1
fi

sed \
  -e "s|{{SERVER_SECRET}}|$SERVER_SECRET|g" \
  -e "s|{{SMTP_USER}}|$SMTP_USER|g" \
  -e "s|{{SMTP_PASS}}|$SMTP_PASS|g" \
  "$TEMPLATE" > "$OUT"

echo "Rendered $OUT (pangolin config) from template + 1Password secrets"
