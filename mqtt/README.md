# mqtt

Two Mosquitto 2.x brokers with a durable site-to-central bridge.

## Brokers

- **mosquitto-site** — Daniel's local bus for `grow/daniel-home/#`. Exposed on host port `1883` so LAN ESPHome devices can connect directly (not via Pangolin — raw TCP). Bridges up to central on the shared `grow-mqtt` docker network.
- **mosquitto-central** — Aggregator. No host port; reachable only over the shared `grow-mqtt` docker network via the site bridge.

## Users

| User | Broker | Purpose |
|---|---|---|
| `edge-daniel-home` | site | ESPHome edge devices |
| `grow-app-site-daniel-home` | site | Local site-mode `grow-app` server |
| `bridge-daniel-home` | central | Site broker bridge credential |

## Secrets

Secrets are injected from 1Password and rsynced to media-server:

```
make inject-secrets
make sync-secrets-media
```

Required secret files (git-ignored):
- `mqtt/secrets/MQTT_EDGE_PASSWORD`
- `mqtt/secrets/MQTT_GROW_APP_SITE_PASSWORD`
- `mqtt/secrets/MQTT_BRIDGE_PASSWORD`

## Deploy

```
make mqtt-up
```

LAN devices connect to `<media-server-LAN-IP>:1883`.
The local grow-app HMI is deployed separately from `grow/docker-compose.yml` but
attaches to this stack through the external Docker network named `grow-mqtt`.
