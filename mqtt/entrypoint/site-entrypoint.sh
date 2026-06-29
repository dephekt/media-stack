#!/bin/sh
set -eu
RUN=/run/mosquitto
mkdir -p "$RUN"
# Hashed password file: edge devices and the local site-mode grow-app (the
# grow-app web server and the history-recorder share this credential).
mosquitto_passwd -b -c "$RUN/passwd" edge-daniel-home "$(cat /run/secrets/MQTT_EDGE_PASSWORD)"
mosquitto_passwd -b "$RUN/passwd" grow-app-site-daniel-home "$(cat /run/secrets/MQTT_GROW_APP_SITE_PASSWORD)"
cp /mosquitto/config/mosquitto.conf.tmpl "$RUN/mosquitto.conf"
cp /mosquitto/config/acl "$RUN/acl"
# mosquitto drops privileges to the 'mosquitto' user (uid 1883); make the runtime
# files (passwd + conf) readable by it before handing off.
chmod 700 "$RUN"; chmod 600 "$RUN"/*
chown -R mosquitto:mosquitto "$RUN"
exec /docker-entrypoint.sh mosquitto -c "$RUN/mosquitto.conf"
