# grow

Daniel's LAN-local `grow-app` site-mode HMI.

## Service

- **grow-app-site** — SvelteKit server for the local grow HMI/API.
- Image: `ghcr.io/dephekt/grow-app:edge-node24-bookworm-slim`.
- LAN URL: `http://<media-server-LAN-IP>:3080`.
- MQTT broker: `mosquitto-site` on the shared `grow-mqtt` Docker network.
- Firmware packages: private GHCR OCI artifacts under
  `ghcr.io/dephekt/grow-fleet-*`, fetched server-side with a package
  token.

This is Phase 1 site mode only. It is not exposed through Pangolin and does not
use Keycloak.

## Secrets

`make inject-agent-secrets` writes the grow-app runtime secrets from 1Password:

- `op://Agents/GitHub/ghcr-read-packages` ->
  `grow/secrets/FIRMWARE_OCI_TOKEN`
- `op://Agents/Grow App/firmware-update-token` ->
  `grow/secrets/FIRMWARE_UPDATE_TOKEN`

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
