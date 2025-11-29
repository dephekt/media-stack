# Immich Setup

Self-hosted photo and video management with Intel Arc GPU acceleration.

## Setup Steps

### 1. Create Storage Directories

On the container host:
```bash
ssh containers
# Create local directory for database
sudo mkdir -p /var/lib/immich/postgres
sudo chown -R 999:999 /var/lib/immich/postgres  # postgres user in container
```

NFS mount for photos will be at `/media/daniel/immich` (systemd mount from NAS).

### 2. Configure Environment

Copy the template and customize:
```bash
cd /home/daniel/docker/immich
cp config.env.template .env
```

Edit `.env` and set:
- `DB_PASSWORD` - Generate a random password (alphanumeric only)

The following are already configured:
- `UPLOAD_LOCATION=/media/daniel/immich` - NFS-backed storage on NAS
- `DB_DATA_LOCATION=/var/lib/immich/postgres` - Database on local SSD/NVMe
- `TZ=US/Central` - Timezone

### 3. Deploy

```bash
make immich-up
```

### 4. Initial Setup

1. Access `https://photos.dephekt.net`
2. Create admin account
3. Configure Keycloak OIDC integration (optional):
   - Go to Administration → Settings → OAuth Authentication
   - Enable OAuth
   - Add Keycloak as provider with settings from `.env`

## Hardware Acceleration

### Transcoding (Intel Arc A310)
- **Enabled:** QuickSync via `/dev/dri` 
- **Codec:** H.264, H.265, AV1 encode/decode
- Configured in `hwaccel.transcoding.yml` service `quicksync`

### Machine Learning (OpenVINO)
- **Enabled:** Intel GPU inference acceleration
- **Models:** Facial recognition, object detection, smart search
- Image tag: `immich-machine-learning:release-openvino`
- Configured in `hwaccel.ml.yml` service `openvino`

## Pangolin Integration

- **Domain:** `photos.${DOMAIN}` → `photos.dephekt.net`
- **Auth:** None (Immich handles its own auth or OIDC via Keycloak)
- **Port:** 2283 (HTTP)
- **Network:** `media_default` (shared with Newt for proxying)

## Makefile Commands

```bash
make immich-up        # Start Immich stack
make immich-down      # Stop Immich stack
make immich-restart   # Restart Immich stack
make logs-immich      # Follow logs
```

## Storage

**Photos (NFS on NAS):**
- NAS path: `/mnt/root/media-containers/immich/`
- Mounted at: `/media/daniel/immich/` (container host and local machine)
- Contains: Photos, videos, thumbnails

**Database (Local SSD):**
- Container host: `/var/lib/immich/postgres/`
- PostgreSQL data files stay local for performance
- Backup separately to NAS (not implemented yet)

## Notes

- Database is PostgreSQL with pgvector for AI search
- Redis used for job queues
- Model cache is a Docker volume (not on NFS for performance)
- Ports are not exposed on host (Pangolin proxies 2283 internally)

