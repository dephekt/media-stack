#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Daniel Snider

set -eu

export NEWT_ID="$(cat /run/secrets/NEWT_ID.env)"
export NEWT_SECRET="$(cat /run/secrets/NEWT_SECRET.env)"

exec /entrypoint.sh "$@"
