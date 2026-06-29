# mqtt

A single Mosquitto 2.x broker — the per-site local bus. Each site is an
autonomous island; there is no central broker. (An earlier design bridged every
site up to a central aggregator; that was dropped — remote access is provided at
the app layer by Pangolin, not by bridging the MQTT bus.)

## Broker

- **mosquitto-site** — Daniel's local bus for `grow/daniel-home/#`. Exposed on
  host port `1883` so LAN ESPHome devices can connect directly (not via Pangolin
  — raw TCP). The local `grow-app` and `grow-history-recorder` (see
  `grow/docker-compose.yml`) attach over the shared `grow-mqtt` docker network.

## Users

| User | Purpose |
|---|---|
| `edge-daniel-home` | ESPHome edge devices |
| `grow-app-site-daniel-home` | Local site-mode `grow-app` server |
| `recorder-daniel-home` | Read-only history-recorder (subscribes only) |

## Secrets

Secrets are injected from 1Password and rsynced to media-server:

```
make inject-agent-secrets
make sync-secrets-media
```

Required secret files (git-ignored):
- `mqtt/secrets/MQTT_EDGE_PASSWORD`
- `mqtt/secrets/MQTT_GROW_APP_SITE_PASSWORD`

## Deploy

```
make mqtt-up
```

LAN devices connect to `<media-server-LAN-IP>:1883`.
The local grow-app HMI + InfluxDB + history-recorder are deployed separately from
`grow/docker-compose.yml` but attach to this stack through the external Docker
network named `grow-mqtt`.
