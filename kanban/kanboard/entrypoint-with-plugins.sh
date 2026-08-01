#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Daniel Snider

set -eu

for plugin in /opt/kanboard/plugins/*; do
    [ -d "$plugin" ] || continue

    plugin_name="$(basename "$plugin")"
    target="/var/www/app/plugins/$plugin_name"

    rm -rf "$target"
    cp -a "$plugin" "$target"
    chown -R nginx:nginx "$target"
done

exec /usr/local/bin/entrypoint.sh "$@"
