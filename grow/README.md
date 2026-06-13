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
make grow-up
```

Health check:

```bash
curl http://<media-server-LAN-IP>:3080/health
```
