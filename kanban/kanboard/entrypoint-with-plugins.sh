#!/bin/sh
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
