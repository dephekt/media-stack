#!/bin/sh
set -eu
RUN=/run/mosquitto
mkdir -p "$RUN"
# Hashed password file: edge user (ESPHome). grow-app-site added later.
mosquitto_passwd -b -c "$RUN/passwd" edge-daniel-home "$(cat /run/secrets/MQTT_EDGE_PASSWORD)"
# Runtime config = template + the bridge remote_password appended to the (last) connection block.
cp /mosquitto/config/mosquitto.conf.tmpl "$RUN/mosquitto.conf"
cp /mosquitto/config/acl "$RUN/acl"
printf 'remote_password %s\n' "$(cat /run/secrets/MQTT_BRIDGE_PASSWORD)" >> "$RUN/mosquitto.conf"
# mosquitto drops privileges to the 'mosquitto' user (uid 1883); make the runtime
# files (passwd + rendered conf) readable by it before handing off.
chmod 700 "$RUN"; chmod 600 "$RUN"/*
chown -R mosquitto:mosquitto "$RUN"
exec /docker-entrypoint.sh mosquitto -c "$RUN/mosquitto.conf"
