## Self-hosted stack for sharing media with family and friends

I made this Docker-based streaming media platform to offer my family and friends a better way to access services I've provided ad-hoc for years. A major goal of this iteration is giving my users a polished experience that hides complexity and minimizes the learning curve.

In an ideal world, users are shielded from:
- installing VPN or similar software for access
- having to know about the components involved
- keeping track of many 'weird' links to complicated apps
- having different credentials for each thing

As an engineer that loves my friends but has very little time to spare, I needed:
- enterprise identity (SSO) and access management
- familiar git-based devops patterns
- containerized runtime and deployment
- support and user login portal

## Technical Summary

Using Pangolin and this Docker stack, I can securely share apps running at home without my users installing VPN or other special software. Users visit friendly links using my domain and have a single account for all services, with Google and Apple social login available.

Each app is exposed under a familiar, branded domain with automated TLS certificate provisioning and maintenance. Exposing new apps involves only adding a few labels to its container, which Pangolin uses to auto-configure and discover its resources for proxying.

### Hugo landing page

I'm using a Hugo static site to write support guides in Markdown and quickly deploy them for users to reference. The site works as a landing page for users with support, login and other helpful links in one place. The hugo site is intended to be built with Docker via CI actions, published to a container registry and pulled on deployment via Docker or Kubernetes.

Using Pangolin's auth layer (backed by my Keycloak instance), logged in users are able to access an apps page which has a grid with links to services available in different categories like streaming, AI, photos, etc.

### Identity and access management

Identity for everything is managed by Keycloak. Services with native OIDC or SAML support (like Immich or Pangolin) use Keycloak as their identity provider. Pangolin provides an auth layer for apps and services that don't support auth or OIDC.

Jellyfin only supports managing users and auth by federating with an LDAP directory. To make this work in a low friction way, I configure Keycloak to federate with an OpenLDAP service. This makes the OpenLDAP directory become the password backend for Keycloak.

When Keycloak or Jellyfin need to authenticate a user by password, they ask OpenLDAP. Keycloak handles syncing its users and groups to OpenLDAP's expected directory schema, so Jellyfin is able to see what Keycloak groups have been assigned to a given user.

Jellyfin is configured to check for group membership when a Keycloak user tries to sign in. If they are a member of the `streaming` group, they get a Jellyfin account and are able to login. If they are a member of `streaming` and `admin` groups, they're made a Jellyfin admin.

Users have a single username and password for everything, regardless if the auth is proxied by Pangolin for non-OIDC/SAML apps or by Keycloak or by LDAP for Jellyfin. And they don't need to be aware Pangolin or OpenLDAP exist, as they only interact with Keycloak.

## What’s inside

I group sets of services into separate Docker compose projects in this repo:

- core: key things for providing the service
  - newt
  - auth (keycloak)
  - ldap
  - homepage (hugo landing site)
  - update-manager (wud — image-update notifications)
- media
  - jellyfin
  - seerr (jellyseerr)
  - sonarr
  - radarr
  - nzbget
- immich
  - server
  - machine-learning
  - database
  - redis
- iptv: iptvboss services
  - web vnc to access iptvboss app
  - XtremeCodes API for IPTV client playlist and guide data
- channels: Channels DVR (`fancybits/channels-dvr`) — host networking; config and recordings under `/mnt/data/channels-dvr/` on the Docker host. Start with `make channels-up` or `make up` ([`channels/docker-compose.yml`](channels/docker-compose.yml)).
- monitoring: notification + probe machinery (apprise-api + ntfy + events-watcher + service-checks). Routes tagged HTTP POSTs from any homelab service to mobile push via the self-hosted ntfy instance with iOS instant-push via the upstream ntfy.sh APNs gateway. See [`monitoring/README.md`](monitoring/README.md).
- pangolin: the Pangolin reverse-proxy / control-plane itself, deployed via a separate Docker context (`pangolin-edge`) to the edge VPS. The Makefile auto-routes `pangolin-up` etc. to the right host. See [`pangolin/README.md`](pangolin/README.md).

## How it works (one minute)

- Requests hit the closest Pangolin edge node
- Pangolin authenticates users (if auth is configured) and routes to your site’s Newt
- Newt discovers containers via Docker labels (Blueprints) and forwards to the configured target
- Services providing their own auth (via OIDC/SAML with Keycloak) are exposed without Pangolin's auth in front

No client software is required for users. Everything is just HTTPS in a browser.

## Adding a new service (Pangolin Blueprints)

Expose a container with Pangolin proxy resource labels; Newt autodiscovers:

```yaml
labels:
  - "pangolin.proxy-resources.app.name=My App"
  - "pangolin.proxy-resources.app.protocol=http"
  - "pangolin.proxy-resources.app.full-domain=app.${DOMAIN}"
  - "pangolin.proxy-resources.app.targets[0].enabled=true"
  - "pangolin.proxy-resources.app.targets[0].port=8080"
```
## Certificates and HTTPS

TLS termination and cert management are handled by Pangolin at the edge.

## Acknowledgements

**[Dashboard Icons](https://github.com/homarr-labs/dashboard-icons)** - A collection of over 1800 curated icons for services, applications and tools, designed specifically for dashboards and app directories. Used to power the homepage service icons. Browse the collection at [dashboardicons.com](https://dashboardicons.com/).
