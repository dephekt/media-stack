DOCKER_CONTEXT=media-server

# Export all variables from config.env
include core/config.env
export

# Resolve docker host from context (for rsync of secrets)
CONTEXT_HOST=$(shell docker context inspect $(DOCKER_CONTEXT) -f '{{.Endpoints.docker.Host}}')
REMOTE_HOST=$(shell echo $(CONTEXT_HOST) | sed 's|^ssh://||')

STACKS := core media immich iptv matrix

SERVICES_core   := newt auth ldap homepage db update-manager
SERVICES_media  := jellyfin radarr sonarr nzbget seerr
SERVICES_immich := immich-server immich-machine-learning redis database
SERVICES_iptv   := iptvboss
SERVICES_matrix := homeserver

REQUIRED_SECRETS := \
	core/secrets/KEYCLOAK_ADMIN_PASSWORD.env \
	core/secrets/DB_PASSWORD.env \
	core/secrets/MARIADB_ROOT_PASSWORD \
	core/secrets/LDAP_ADMIN_PASSWORD \
	core/secrets/NEWT_ID.env \
	core/secrets/NEWT_SECRET.env

include Makefile.include

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

.PHONY: inject-secrets check-secrets sync-secrets build-script-providers

inject-secrets:
	@echo "Injecting secrets from 1Password..."
	@mkdir -p core/secrets
	@$(READ_SECRET_FN); \
	read_secret "op://Develop/Keycloak Admin/password" "core/secrets/KEYCLOAK_ADMIN_PASSWORD.env"; \
	read_secret "op://Develop/Keycloak DB/password" "core/secrets/DB_PASSWORD.env"; \
	read_secret "op://Develop/Keycloak Admin/password" "core/secrets/MARIADB_ROOT_PASSWORD"; \
	read_secret "op://Develop/LDAP/password" "core/secrets/LDAP_ADMIN_PASSWORD"; \
	read_secret "op://Develop/Pangolin/newt id" "core/secrets/NEWT_ID.env"; \
	read_secret "op://Develop/Pangolin/newt secret" "core/secrets/NEWT_SECRET.env"
	@echo "Secrets injected successfully!"
	@echo "Note: core/secrets/* files are git-ignored and should not be committed"

sync-secrets: check-secrets
	@if [ "$(DOCKER_CONTEXT)" != "default" ]; then \
		echo "Syncing secrets to remote host: $(REMOTE_HOST)"; \
		rsync -avz --relative core/secrets core/config.env matrix/config.env keycloak-import/ immich/.env immich/hwaccel.ml.yml immich/hwaccel.transcoding.yml $(REMOTE_HOST):~/docker/; \
		echo "Secrets synced to remote host"; \
	else \
		echo "Using local context, no sync needed"; \
	fi

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
