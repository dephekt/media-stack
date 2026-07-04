# grow

Daniel's LAN-local `grow-app` site-mode HMI.

## Services

- **grow-app-site** — SvelteKit server for the local grow HMI/API. Queries
  history server-side via `/api/history`; browsers never hit InfluxDB directly.
  - Image: `ghcr.io/dephekt/grow-app:edge-node24-bookworm-slim`.
  - LAN URL: `http://<media-server-LAN-IP>:3080`.
  - Public URL: `https://daniel.grow.dephekt.net` (via Pangolin, SSO disabled).
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

The app enforces its own login: app-owned local accounts **plus** a confidential
per-site OIDC client (Keycloak realm `home`, client `grow-site-daniel-home`).
Access is granted by group claim — `/grow-admin` (global) or
`/grow-site-daniel-home` (this site). A bootstrap admin is created from
`GROW_AUTH_ADMIN_PASSWORD` on the auth DB's first boot; the secret is inert
afterward. The auth DB lives on the `grow-app-data` volume — deleting that volume
logs everyone out and re-arms the bootstrap secret. The HMI is reachable on the
LAN (`http://192.168.8.3:3080`) and publicly at `https://daniel.grow.dephekt.net`
through Pangolin — **SSO disabled** on the resource, so Pangolin is routing + TLS
only and grow-app enforces its own auth (decision 19). Both origins are in
`GROW_AUTH_ORIGINS` and the Keycloak client's redirect URIs. The Pangolin resource
is registered by newt from the `pangolin.proxy-resources.grow-daniel-home.*` labels
on `grow-app-site` (which also joins the shared `proxy` network).

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
- `op://Agents/Grow App/site-admin-login` ->
  `grow/secrets/GROW_AUTH_ADMIN_PASSWORD` *(bootstrap admin; first boot only)*
- `op://Agents/Grow App/oidc-client-secret` ->
  `grow/secrets/GROW_OIDC_CLIENT_SECRET` *(confidential OIDC client secret)*

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
