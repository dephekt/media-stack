#!/bin/sh
set -eu
RUN=/run/mosquitto
mkdir -p "$RUN"
# Hashed password file: per-site bridge user. grow-app-central added later.
mosquitto_passwd -b -c "$RUN/passwd" bridge-daniel-home "$(cat /run/secrets/MQTT_BRIDGE_PASSWORD)"
cp /mosquitto/config/acl "$RUN/acl"
# mosquitto drops privileges to the 'mosquitto' user (uid 1883); make the passwd
# readable by it before handing off.
chmod 700 "$RUN"; chmod 600 "$RUN"/*
chown -R mosquitto:mosquitto "$RUN"
exec /docker-entrypoint.sh mosquitto -c /mosquitto/config/mosquitto.conf
