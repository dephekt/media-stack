# grow

Daniel's LAN-local `grow-app` site-mode HMI.

## Services

- **grow-app-site** — SvelteKit server for the local grow HMI/API. Queries
  history server-side via `/api/history`; browsers never hit InfluxDB directly.
  - Image: `ghcr.io/dephekt/grow-app:edge-node24-bookworm-slim`.
  - LAN URL: `http://<media-server-LAN-IP>:3080`.
  - MQTT broker: `mosquitto-site` on the shared `grow-mqtt` Docker network.
  - Firmware packages: private GHCR OCI artifacts under
    `ghcr.io/dephekt/grow-fleet-*`, fetched server-side with a package token.

- **grow-influxdb** — Per-site InfluxDB 2.7 time-series store. Admin port
  `8086` is loopback-bound (`127.0.0.1:8086`) and not reachable from LAN or
  Pangolin; only `grow-app-site` and `grow-history-recorder` access it over the
  internal Docker network.

- **grow-history-recorder** — Sidecar (grow-app image) that subscribes to
  `mosquitto-site` as the read-only `recorder-daniel-home` MQTT user and writes
  sensor readings to `grow-influxdb`. Uses ACL `read grow/daniel-home/#` and
  never publishes.

This is Phase 1 site mode only. It is not exposed through Pangolin and does not
use Keycloak.

## Secrets

`make inject-agent-secrets` writes the grow-app runtime secrets from 1Password:

- `op://Agents/MQTT/recorder password` ->
  `mqtt/secrets/MQTT_RECORDER_PASSWORD` *(read-only recorder MQTT user)*
- `op://Agents/InfluxDB/admin password` ->
  `grow/secrets/INFLUXDB_ADMIN_PASSWORD`
- `op://Agents/InfluxDB/admin token` ->
  `grow/secrets/INFLUXDB_ADMIN_TOKEN`
- `op://Agents/GitHub/ghcr-read-packages` ->
  `grow/secrets/FIRMWARE_OCI_TOKEN`
- `op://Agents/Grow App/firmware-update-token` ->
  `grow/secrets/FIRMWARE_UPDATE_TOKEN`

`MQTT_GROW_APP_SITE_PASSWORD` is also written to `mqtt/secrets/` by the same
`make inject-agent-secrets` run (it is shared with the `mqtt` stack).

The firmware update token must match `firmware_update_token` in the ESPHome
secrets used by `grow-fleet`.

## Deploy

Bring up the MQTT stack first so the external `grow-mqtt` network exists:

```bash
make inject-agent-secrets
make sync-secrets-media
make mqtt-up
make grow-pull
make grow-up
```

For normal grow-app UI updates after the app image has been published, run:

```bash
make grow-pull
make grow-app-site-up
```

Use `make grow-up` instead when the grow Compose file or secrets need to be
synced before recreating the service.

Health check:

```bash
curl http://<media-server-LAN-IP>:3080/health
```
