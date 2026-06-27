#!/bin/sh
set -eu

export NEWT_ID="$(cat /run/secrets/NEWT_ID.env)"
export NEWT_SECRET="$(cat /run/secrets/NEWT_SECRET.env)"

exec /entrypoint.sh "$@"
