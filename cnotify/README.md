# cnotify

cam-availability poller. Polls a configured listing page and sends notifications via `apprise-api` when a watched entry's availability state transitions.

## Notification routing

Notifications are posted to `apprise-api:8000/notify?tag=cam`, which fans out to the `notify-cam-<rand>` ntfy topic defined in `monitoring/apprise/monitoring.yaml`.

## Registry authentication

The image lives in a private Codeberg registry. A one-time `docker login` is required on the machine that runs `make cnotify-up`:

```sh
docker login codeberg.org
```

Use a Codeberg personal access token with read-only scope on the `stackdrift-images` org packages. The local Docker CLI forwards auth to the remote daemon over SSH — the remote host itself does not need its own login for the make-driven deploy flow.

## State file

The watch list and last-known availability are persisted in `data/state.json` (bind-mounted into the container at `/app/data/state.json`). This file is gitignored.

### Migrating from Render (one-time cutover)

1. Grab the state from Render:
   ```sh
   # via Render shell or SSH
   cat /var/data/state.json
   ```
2. Copy it to the media-server:
   ```sh
   scp /tmp/state.json containers:~/docker/cnotify/data/state.json
   ```
3. Optionally zero out the now-unused fields before deploying:
   - Set `apprise_urls` to `[]`
   - Set `base_url` to `null`

If no state.json is present, the container starts with an empty watch list and state is built up as watches are added via the UI.
