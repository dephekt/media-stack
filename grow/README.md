# grow

Daniel's LAN-local `grow-app` site-mode HMI.

## Service

- **grow-app-site** — SvelteKit server for the local grow HMI/API.
- Image: `codeberg.org/stackdrift-images/grow-app:edge-node24-bookworm-slim`.
- LAN URL: `http://<media-server-LAN-IP>:3080`.
- MQTT broker: `mosquitto-site` on the shared `grow-mqtt` Docker network.

This is Phase 1 site mode only. It is not exposed through Pangolin and does not
use Keycloak.

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
