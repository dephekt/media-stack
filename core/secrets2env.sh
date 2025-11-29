#!/bin/sh
set -eu

# Export env vars from secret files ending in .env
for secret_file in $(find /run/secrets -maxdepth 1 -type f -name '*.env' 2>/dev/null); do
    var_name=$(basename "${secret_file%*.env}")
    export "$var_name"="$(cat "$secret_file")"
done

exec "$@"


