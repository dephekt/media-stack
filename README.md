## Self-hosted stack for sharing media with family and friends

I made this Docker-based streaming media platform to offer my family and friends a better way to access services I've informally provided for years. A major goal of this iteration is hiding complexity and minimizing the learning curve and information density for the end user.

In an ideal world, my users are shielded from:
- installing VPN or similar software for access
- having to know about the components involved
- keeping track of many 'weird' links to complicated apps
- having different credentials for each thing

As an engineer that loves my friends but has very little time to spare, I needed:
- enterprise identity and access management
- familiar git-based devops patterns
- containerized runtime and deployment
- support and user login portal for users

## Technical Summary

Using Pangolin and this Docker stack, I can securely share apps running at home without my users installing VPN or other special software. Users visit friendly links and have a single account for all services, with Google and Apple social login available.

Each app is exposed under a familiar, branded domain with automated TLS certificate provisioning and maintenance. Exposing new apps involves only adding a few labels to its container, which Pangolin uses to auto-configure and discover its resources for proxying.

### Hugo landing page
I'm using a markdown-based Hugo static site to write support guides in Markdown and quickly deploy them for users to reference. The site works as a landing page for users with support, login, and other helpful links in one place. The hugo site is brought in to this Docker project as a git submodule during build, then deployed.

Logged in users are able to access an apps page, which has a grid with links to services available in different categories.

### Identity and access management
Identity for everything is managed by Keycloak in partnership with Pangolin as an OIDC client. Since Jellyfin natively supports LDAP and not OIDC/SAML, Keycloak federates with an OpenLDAP container and keeps users and groups in sync. Then Jellyfin federates with LDAP.

Jellyfin is configured to check for group membership when a Keycloak user tries to sign in. If they are a member of the `streaming` group, they get a Jellyfin account and are able to login. If they are a member of `streaming` and `admin` groups, they're made a Jellyfin admin.

My users have a single username and password for everything, whether the auth is proxied by Pangolin for non-OIDC/SAML apps, by Keycloak with OIDC/SAML clients like Immich and Open WebUI, or by LDAP. And they have no idea Pangolin or LDAP exist.

## What’s inside (at a glance)
- Pangolin (managed self‑hosted) edge nodes for global ingress and failover
- Newt (local agent) for tunnel + autodiscovery via Docker labels
- Keycloak (auth) and MariaDB (db)


## How it works (one minute)
- Requests hit the closest Pangolin edge node
- Pangolin authenticates users (per your policy) and routes to your site’s Newt
- Newt discovers containers via Docker labels (Blueprints) and forwards to them

No client software is required for your users. Everything is just HTTPS in a browser.


## Before you start
- Docker + Docker Compose v2 installed
- Pangolin managed self‑hosted nodes deployed (see Pangolin docs)
- 1Password CLI (`op`) for secret injection (or adapt templates to your secret manager)
- For remote deployment: SSH access to your Docker host


## Setup in 6 steps
1) Configure non-secret settings (optional)
- Edit `core/config.env` and `ai/config.env` if you need to change domain or other public settings
- Default domain is `dephekt.net` - change it to yours

2) Generate secrets from 1Password
```bash
make inject-secrets   # generates core/secrets.env and ai/secrets.env
```
This uses your 1Password vault to populate secret values. The generated files are git-ignored.

3) (Optional) Create LAN shim if you need host LAN access
```bash
make lan-net
make shim
```

4) Start the core stack
```bash
make core-up   # newt, keycloak, db
```

5) No dashboard config needed if using Blueprints labels (Newt autodiscovers)

You should now reach:
- Keycloak at `https://auth.${DOMAIN}`

**Remote deployment:** Use Docker contexts - `docker context create remote --docker "host=ssh://user@host"`, then deploy normally.


## Add your first app (Pangolin Blueprints)
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


## Common issues (and quick checks)
- Resource not visible: confirm Newt is running with Docker socket and labels are correct
- Wrong target port: set `targets[0].port` label explicitly


## Where things live
- Core stack: `core/docker-compose.yml`
- Config files (public): `core/config.env`
- Secrets directory (git-ignored): `core/secrets/`
- Make commands: `Makefile`
- Keycloak realm exports: `keycloak-import/` (import with `make auth-import`)


## Want the deep dive?
See `AGENTS.md` for service inventory, env variables, labels, and command reference.


## Acknowledgements

**[Dashboard Icons](https://github.com/homarr-labs/dashboard-icons)** - A collection of over 1800 curated icons for services, applications and tools, designed specifically for dashboards and app directories. Used to power the homepage service icons. Browse the collection at [dashboardicons.com](https://dashboardicons.com/).


 
