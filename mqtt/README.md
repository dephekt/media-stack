# mqtt

Two Mosquitto 2.x brokers with a durable site-to-central bridge.

## Brokers

- **mosquitto-site** — Daniel's local bus for `grow/daniel-home/#`. Exposed on host port `1883` so LAN ESPHome devices can connect directly (not via Pangolin — raw TCP). Bridges up to central on the internal `mqtt` docker network.
- **mosquitto-central** — Aggregator. No host port; reachable only over the `mqtt` docker network via the site bridge.

## Users

| User | Broker | Purpose |
|---|---|---|
| `edge-daniel-home` | site | ESPHome edge devices |
| `bridge-daniel-home` | central | Site broker bridge credential |

## Secrets

Secrets are injected from 1Password and rsynced to media-server:

```
make inject-secrets
make sync-secrets-media
```

Required secret files (git-ignored):
- `mqtt/secrets/MQTT_EDGE_PASSWORD`
- `mqtt/secrets/MQTT_BRIDGE_PASSWORD`

## Deploy

```
make mqtt-up
```

LAN devices connect to `<media-server-LAN-IP>:1883`.
