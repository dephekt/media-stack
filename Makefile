DOCKER_CONTEXT=media-server

# Per-stack context overrides. STACK_CONTEXT helper in Makefile.include picks these up.
CONTEXT_pangolin=pangolin-edge

# Stacks deployed from synced files on the media server need compose paths to
# resolve against the remote project directory when using the SSH docker context.
PROJECT_DIR_mqtt=/home/daniel/docker/mqtt
PROJECT_DIR_grow=/home/daniel/docker/grow

# Per-host helpers for sync-secrets split (one rsync per remote).
CONTEXT_HOST_media=$(shell docker context inspect $(DOCKER_CONTEXT) -f '{{.Endpoints.docker.Host}}')
REMOTE_HOST_media=$(shell echo $(CONTEXT_HOST_media) | sed 's|^ssh://||')
CONTEXT_HOST_pangolin=$(shell docker context inspect $(CONTEXT_pangolin) -f '{{.Endpoints.docker.Host}}')
REMOTE_HOST_pangolin=$(shell echo $(CONTEXT_HOST_pangolin) | sed 's|^ssh://||')

# Export all variables from config.env
include core/config.env
export

# Resolve docker host from context (for rsync of secrets)
# Kept for backward compat with any targets that reference REMOTE_HOST directly.
CONTEXT_HOST=$(shell docker context inspect $(DOCKER_CONTEXT) -f '{{.Endpoints.docker.Host}}')
REMOTE_HOST=$(shell echo $(CONTEXT_HOST) | sed 's|^ssh://||')

STACKS := core media immich iptv channels monitoring pangolin mqtt grow matrix penpot kanban cci

SERVICES_core   := newt auth ldap homepage db update-manager agent-kb
SERVICES_media  := jellyfin radarr sonarr nzbget seerr
SERVICES_immich := immich-server immich-machine-learning redis database
SERVICES_iptv   := iptvboss
SERVICES_channels  := channels-dvr
SERVICES_monitoring := apprise-api events-watcher service-checks agent-kb-redeploy
SERVICES_pangolin := pangolin gerbil traefik
SERVICES_mqtt    := mosquitto-site mosquitto-central
SERVICES_grow    := grow-app-site
SERVICES_matrix  := tuwunel element-web
SERVICES_penpot  := penpot-frontend penpot-backend penpot-mcp penpot-exporter penpot-postgres penpot-valkey
SERVICES_kanban  := kanban-router kanboard kanboard-admin-init kanboard-oauth-init kanban-ref
SERVICES_cci     := cci-blackbook

REQUIRED_SECRETS := \
	core/secrets/KEYCLOAK_ADMIN_PASSWORD.env \
	core/secrets/DB_PASSWORD.env \
	core/secrets/MARIADB_ROOT_PASSWORD \
	core/secrets/LDAP_ADMIN_PASSWORD \
	core/secrets/NEWT_ID.env \
	core/secrets/NEWT_SECRET.env \
	monitoring/apprise/monitoring.yaml \
	monitoring/secrets/IPTV_UPSTREAM_USER.env \
	monitoring/secrets/IPTV_UPSTREAM_PASS.env \
	monitoring/secrets/IPTV_LOCAL_USER.env \
	monitoring/secrets/IPTV_LOCAL_PASS.env \
	monitoring/secrets/GHCR_READ_TOKEN.env \
	pangolin/secrets/pangolin.env \
	pangolin/config/config.yml \
	mqtt/secrets/MQTT_EDGE_PASSWORD \
	mqtt/secrets/MQTT_GROW_APP_SITE_PASSWORD \
	mqtt/secrets/MQTT_BRIDGE_PASSWORD \
	grow/secrets/FIRMWARE_OCI_TOKEN \
	grow/secrets/FIRMWARE_UPDATE_TOKEN \
	matrix/secrets/TUWUNEL_OIDC_CLIENT_SECRET \
	penpot/secrets/penpot.env \
	kanban/secrets/kanboard.env \
	cci/secrets/cci.env

MEDIA_SYNC_REQUIRED := \
	core/secrets \
	core/config.env \
	core/docker-compose.yml \
	core/newt-entrypoint.sh \
	immich/.env \
	immich/hwaccel.ml.yml \
	immich/hwaccel.transcoding.yml \
	monitoring/config.env \
	monitoring/secrets \
	monitoring/apprise \
	monitoring/events-watcher \
	monitoring/service-checks \
	mqtt/secrets \
	mqtt/site \
	mqtt/central \
	mqtt/entrypoint \
	mqtt/docker-compose.yml \
	grow/secrets \
	grow/docker-compose.yml \
	matrix/secrets \
	matrix/config.env \
	matrix/docker-compose.yml \
	matrix/config/tuwunel.toml \
	matrix/config/element-web.json \
	penpot/secrets \
	penpot/docker-compose.yml \
	kanban/secrets \
	kanban/router \
	kanban/ref \
	kanban/kanboard \
	kanban/keycloak \
	kanban/docker-compose.yml \
	cci/secrets \
	cci/app \
	cci/Dockerfile \
	cci/pyproject.toml \
	cci/uv.lock \
	cci/docker-compose.yml

MEDIA_SYNC_OPTIONAL := \
	keycloak-import/

include Makefile.include

# Check that all required secrets files exist and are non-empty.
check-secrets:
	@missing=0; \
	for f in $(REQUIRED_SECRETS); do \
		if [ ! -f "$$f" ]; then \
			echo "Missing secret file: $$f"; missing=1; \
		elif [ ! -s "$$f" ]; then \
			echo "Empty secret file: $$f"; missing=1; \
		fi; \
	done; \
	if [ $$missing -ne 0 ]; then \
		echo "Run 'make inject-secrets' to generate missing secrets."; \
		exit 1; \
	fi; \
	echo "All required secrets present"

# Shell function to safely read secrets from 1Password
# This avoids blank secrets being written and synced to the docker host
define READ_SECRET_FN
read_secret() { \
	local op_ref="$$1"; \
	local dest_file="$$2"; \
	local secret_val; \
	if ! secret_val=$$(op read "$$op_ref"); then \
		echo "ERROR: Failed to read from 1Password: $$op_ref"; \
		exit 1; \
	fi; \
	if [ -z "$$secret_val" ]; then \
		echo "ERROR: Empty secret retrieved from: $$op_ref"; \
		exit 1; \
	fi; \
	printf "%s" "$$secret_val" > "$$dest_file"; \
}
endef

.PHONY: inject-secrets check-secrets sync-secrets sync-secrets-media sync-secrets-pangolin build-script-providers monitoring-config-load

# Register monitoring/apprise/monitoring.yaml with apprise-api under the
# 'monitoring' token. Idempotent -- re-run after editing the YAML or after
# a fresh deploy. apprise-api persists the registered config in its bind-
# mounted /config volume, so this is only needed at setup / on YAML edits.
monitoring-config-load:
	@DOCKER_CONTEXT=$(DOCKER_CONTEXT) ./monitoring/apprise/load-config.sh

inject-secrets:
	@echo "Injecting secrets from 1Password..."
	@mkdir -p core/secrets monitoring/secrets matrix/secrets penpot/secrets
	@$(READ_SECRET_FN); \
	read_secret "op://Develop/Keycloak Admin/password" "core/secrets/KEYCLOAK_ADMIN_PASSWORD.env"; \
	read_secret "op://Develop/Keycloak DB/password" "core/secrets/DB_PASSWORD.env"; \
	read_secret "op://Develop/Keycloak Admin/password" "core/secrets/MARIADB_ROOT_PASSWORD"; \
	read_secret "op://Develop/LDAP/password" "core/secrets/LDAP_ADMIN_PASSWORD"; \
	read_secret "op://Develop/Self-Hosted Pangolin/newt id" "core/secrets/NEWT_ID.env"; \
	read_secret "op://Develop/Self-Hosted Pangolin/newt secret" "core/secrets/NEWT_SECRET.env"; \
	read_secret "op://Develop/IPTV Upstream/username" "monitoring/secrets/IPTV_UPSTREAM_USER.env"; \
	read_secret "op://Develop/IPTV Upstream/password" "monitoring/secrets/IPTV_UPSTREAM_PASS.env"; \
	read_secret "op://Develop/IPTV Local XC/username" "monitoring/secrets/IPTV_LOCAL_USER.env"; \
	read_secret "op://Develop/IPTV Local XC/password" "monitoring/secrets/IPTV_LOCAL_PASS.env"; \
	read_secret "op://Personal/GitHub/Security/GHCR Read PAT" "monitoring/secrets/GHCR_READ_TOKEN.env"; \
	read_secret "op://Develop/Matrix/client secret" "matrix/secrets/TUWUNEL_OIDC_CLIENT_SECRET"
	@# Render apprise/monitoring.yaml from template + 1Password topic names.
	@# Topic names stay out of the public repo by living in 1P; the rendered
	@# file is gitignored. Re-run after rotating topic values in 1Password.
	@./monitoring/apprise/render-config.sh
	@mkdir -p pangolin/secrets pangolin/config
	@# Pangolin Cloudflare DNS token: KEY=VALUE form for compose env_file
	@secret_val=$$(op read "op://Develop/Cloudflared API/credential") || { echo "ERROR: failed to read op://Develop/Cloudflared API/credential"; exit 1; }; \
	if [ -z "$$secret_val" ]; then echo "ERROR: empty Cloudflare token"; exit 1; fi; \
	printf "CLOUDFLARE_DNS_API_TOKEN=%s\n" "$$secret_val" > pangolin/secrets/pangolin.env
	@# Render pangolin/config/config.yml from template + 1Password
	@./pangolin/config/render-config.sh
	@# Penpot: KEY=VALUE env file consumed by upstream images.
	@set -eu; \
	read_penpot_secret() { \
		local op_ref="$$1"; \
		local secret_val; \
		if ! secret_val=$$(op read "$$op_ref"); then \
			echo "ERROR: Failed to read from 1Password: $$op_ref"; \
			exit 1; \
		fi; \
		if [ -z "$$secret_val" ]; then \
			echo "ERROR: Empty secret retrieved from: $$op_ref"; \
			exit 1; \
		fi; \
		printf "%s" "$$secret_val"; \
	}; \
	PENPOT_SECRET_KEY=$$(read_penpot_secret "op://Develop/Penpot/secret key"); \
	PENPOT_DATABASE_PASSWORD=$$(read_penpot_secret "op://Develop/Penpot/database password"); \
	PENPOT_OIDC_CLIENT_SECRET=$$(read_penpot_secret "op://Develop/Penpot/OIDC client secret"); \
	{ \
		printf "PENPOT_SECRET_KEY=%s\n" "$$PENPOT_SECRET_KEY"; \
		printf "PENPOT_DATABASE_PASSWORD=%s\n" "$$PENPOT_DATABASE_PASSWORD"; \
		printf "POSTGRES_PASSWORD=%s\n" "$$PENPOT_DATABASE_PASSWORD"; \
		printf "PENPOT_OIDC_CLIENT_SECRET=%s\n" "$$PENPOT_OIDC_CLIENT_SECRET"; \
	} > penpot/secrets/penpot.env
	@echo "Secrets injected successfully!"
	@echo "Note: */secrets/* files are git-ignored and should not be committed"

# Agent-managed secrets live in the 1Password "Agents" vault and are injected via
# the op-agent service-account wrapper (~/.local/bin/op-agent) — kept separate from
# inject-secrets, which reads Develop/Personal via Daniel's own 1Password and which
# the service account cannot access. Safe to run autonomously.
inject-agent-secrets:
	@echo "Injecting agent-managed secrets from 1Password (Agents vault)..."
	@mkdir -p mqtt/secrets grow/secrets kanban/secrets
	@set -eu; \
	read_agent_secret() { \
		local op_ref="$$1"; \
		local dest_file="$$2"; \
		local secret_val; \
		if ! secret_val=$$(op-agent read "$$op_ref"); then \
			echo "ERROR: Failed to read from 1Password: $$op_ref"; \
			exit 1; \
		fi; \
		if [ -z "$$secret_val" ]; then \
			echo "ERROR: Empty secret retrieved from: $$op_ref"; \
			exit 1; \
		fi; \
		printf '%s' "$$secret_val" > "$$dest_file"; \
	}; \
	read_agent_secret 'op://Agents/MQTT/edge password' mqtt/secrets/MQTT_EDGE_PASSWORD; \
	read_agent_secret 'op://Agents/MQTT/grow app site password' mqtt/secrets/MQTT_GROW_APP_SITE_PASSWORD; \
	read_agent_secret 'op://Agents/MQTT/bridge password' mqtt/secrets/MQTT_BRIDGE_PASSWORD; \
	read_agent_secret 'op://Agents/Grow App/github-firmware-oci-token' grow/secrets/FIRMWARE_OCI_TOKEN; \
	read_agent_secret 'op://Agents/Grow App/firmware-update-token' grow/secrets/FIRMWARE_UPDATE_TOKEN; \
	admin_password=$$(op-agent read 'op://Agents/Kanboard/password'); \
	api_token=$$(op-agent read 'op://Agents/Kanboard/api token'); \
	oauth_client_secret=$$(op-agent read 'op://Agents/Kanboard/oauth client secret'); \
	if [ -z "$$admin_password" ] || [ -z "$$api_token" ] || [ -z "$$oauth_client_secret" ]; then \
		echo "ERROR: Empty Kanboard secret from 1Password"; \
		exit 1; \
	fi; \
	{ \
		printf 'KANBOARD_ADMIN_PASSWORD=%s\n' "$$admin_password"; \
		printf 'API_AUTHENTICATION_TOKEN=%s\n' "$$api_token"; \
		printf 'KANBOARD_OAUTH2_CLIENT_SECRET=%s\n' "$$oauth_client_secret"; \
	} > kanban/secrets/kanboard.env
	@echo "Agent-managed secrets injected (mqtt/secrets/, grow/secrets/, kanban/secrets/)."

sync-secrets-media: check-secrets
	@if [ "$(DOCKER_CONTEXT)" != "default" ]; then \
		missing=0; \
		for path in $(MEDIA_SYNC_REQUIRED); do \
			if [ ! -e "$$path" ]; then \
				echo "Missing media sync input: $$path"; \
				missing=1; \
			fi; \
		done; \
		if [ $$missing -ne 0 ]; then \
			echo "Cannot sync media-server files; restore missing required inputs."; \
			exit 1; \
		fi; \
		optional_inputs=""; \
		for path in $(MEDIA_SYNC_OPTIONAL); do \
			if [ -e "$$path" ]; then \
				optional_inputs="$$optional_inputs $$path"; \
			else \
				echo "Skipping optional media sync input: $$path"; \
			fi; \
		done; \
		echo "Syncing secrets to $(REMOTE_HOST_media)"; \
		rsync -avz --exclude='__pycache__/' --exclude='*.pyc' --relative $(MEDIA_SYNC_REQUIRED) $$optional_inputs $(REMOTE_HOST_media):~/docker/ && \
		echo "Secrets synced to $(REMOTE_HOST_media)"; \
	else \
		echo "Using local context, no sync needed"; \
	fi

sync-secrets-pangolin: check-secrets
	@echo "Syncing to $(REMOTE_HOST_pangolin)"; \
	cd pangolin && rsync -avz --relative \
	  docker-compose.yml \
	  secrets/pangolin.env \
	  config/config.yml \
	  config/traefik/traefik_config.yml \
	  config/traefik/dynamic_config.yml \
	  $(REMOTE_HOST_pangolin):/opt/pangolin/

sync-secrets: sync-secrets-media sync-secrets-pangolin
	@echo "All secrets synced"

# Core specific build dependency for keycloak providers
core-up:

auth-export: auth-stop check-secrets
	mkdir -p ./keycloak-export
	$(call STACK_CMD,core) run --rm --no-deps \
		-v ./keycloak-export:/opt/keycloak/data/export \
		auth export \
		--dir /opt/keycloak/data/export \
		--users realm_file

auth-transfer-export:
	mkdir -p ./keycloak-export
	mkdir -p ./keycloak-import
	cp -r ./keycloak-export/* ./keycloak-import/

auth-import: auth-stop check-secrets
	mkdir -p ./keycloak-import
	$(call STACK_CMD,core) run --rm --no-deps \
		-v ./keycloak-import:/opt/keycloak/data/import \
		auth import \
		--dir /opt/keycloak/data/import

auth-migrate: auth-export auth-transfer-export auth-import

ldap-test:
	@echo "=== Testing LDAP connection ==="
	@LDAP_PASSWORD=$$(cat core/secrets/LDAP_ADMIN_PASSWORD); \
	BASE_DN="dc=$${DOMAIN//./,dc=}"; \
	docker exec ldap ldapsearch -x -H ldap://localhost:389 \
		-b "$$BASE_DN" \
		-D "cn=admin,$$BASE_DN" \
		-w "$$LDAP_PASSWORD" 2>&1 | grep -E "(^dn:|^result:|Success)" || \
		(echo "✗ LDAP test failed" && exit 1)
	@echo "✓ LDAP connection successful"

.PHONY: ldap-reset-admin
ldap-reset-admin:
	@echo "Resetting LDAP admin password via ldapi..."
	@LDAP_PASSWORD=$$(cat core/secrets/LDAP_ADMIN_PASSWORD); \
	if [ -z "$$LDAP_PASSWORD" ]; then echo "ERROR: core/secrets/LDAP_ADMIN_PASSWORD is empty"; exit 1; fi; \
	docker exec -i ldap sh -lc 'set -e; \
	  HASH=$$(slappasswd -s "'"'"$$LDAP_PASSWORD"'"'"); \
	  DBDN=$$(ldapsearch -LLL -Y EXTERNAL -H ldapi:/// -b cn=config "(olcRootDN=cn=admin,$$LDAP_BASE_DN)" dn | sed -n "s/^dn: //p" | head -1); \
	  printf "dn: %s\nchangetype: modify\nreplace: olcRootPW\nolcRootPW: %s\n" "$$DBDN" "$$HASH" > /tmp/reset.ldif; \
	  ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/reset.ldif; \
	  echo "✓ LDAP admin password updated"'

# -----------------------------------------------------------------------------
# Linting / formatting
# -----------------------------------------------------------------------------
# Requires:
#   uv         -- runs ruff/yamllint via `uvx` without a project venv
#   shellcheck -- apt install shellcheck
#
# YAML target uses `git ls-files` so rendered/gitignored YAML (e.g. the
# 1Password-rendered pangolin/config/config.yml) is automatically skipped.

PY_LINT_PATHS   := monitoring/service-checks kanban/ref cci/app cci/tests
SH_LINT_FILES   := $(shell find . -type f -name '*.sh' -not -path './.git/*' -not -path '*/secrets/*')
YAML_LINT_FILES := $(shell git ls-files '*.yml' '*.yaml' '*.yml.template' '*.yaml.template')

.PHONY: lint lint-py lint-sh lint-yaml format format-check

lint: lint-py lint-sh lint-yaml

lint-py:
	uvx ruff check $(PY_LINT_PATHS)

lint-sh:
	shellcheck $(SH_LINT_FILES)

lint-yaml:
	uvx yamllint $(YAML_LINT_FILES)

format:
	uvx ruff format $(PY_LINT_PATHS)

format-check:
	uvx ruff format --check $(PY_LINT_PATHS)
