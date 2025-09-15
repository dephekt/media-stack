NETWORK=proxy
CORE_COMPOSE=core/docker-compose.yml
AI_COMPOSE=ai/docker-compose.yml
LAN_NET_NAME=core_lan
LAN_PARENT=eno2
LAN_SUBNET=192.168.8.0/24
LAN_GATEWAY=192.168.8.1
ROUTER_IP=192.168.8.241
HOST_SHIM_IF=lan-shim
HOST_SHIM_IP=192.168.8.250/24
OP_RUN_CORE=op run --env-file="core/local.env" --
OP_RUN_AI=op run --env-file="ai/local.env" --

.PHONY: network lan-net shim core-up core-down ai-up ai-down up down restart logs-core logs-ai auth-stop auth-start auth-export auth-import auth-migrate

network:
	docker network create $(NETWORK) || true

lan-net:
	# Create macvlan network if not exists
	@if ! docker network ls --format '{{.Name}}' | grep -q '^$(LAN_NET_NAME)$$'; then \
		docker network create -d macvlan \
		  --subnet=$(LAN_SUBNET) --gateway=$(LAN_GATEWAY) \
		  -o parent=$(LAN_PARENT) $(LAN_NET_NAME); \
	fi

shim:
	sudo ip link add $(HOST_SHIM_IF) link $(LAN_PARENT) type macvlan mode bridge || true
	sudo ip addr add $(HOST_SHIM_IP) dev $(HOST_SHIM_IF) || true
	sudo ip link set $(HOST_SHIM_IF) up || true

core-up: network lan-net
	$(OP_RUN_CORE) docker compose -f $(CORE_COMPOSE) up -d

core-down:
	docker compose -f $(CORE_COMPOSE) down

ai-up: network
	$(OP_RUN_AI) docker compose -f $(AI_COMPOSE) up -d

ai-down:
	docker compose -f $(AI_COMPOSE) down

up: core-up ai-up
	echo "Stacks started"

down: ai-down core-down
	echo "Stacks stopped"

restart: down up

logs-core:
	docker compose -f $(CORE_COMPOSE) logs -f | cat

logs-ai:
	docker compose -f $(AI_COMPOSE) logs -f | cat

auth-stop:
	docker compose -f $(CORE_COMPOSE) stop auth

auth-start:
	docker compose -f $(CORE_COMPOSE) start auth

auth-export: auth-stop
	mkdir -p ./keycloak-export
	$(OP_RUN_CORE) \
	    docker compose -f $(CORE_COMPOSE) run --rm --no-deps \
		-v ./keycloak-export:/opt/keycloak/data/export \
		auth export \
		--dir /opt/keycloak/data/export \
		--users realm_file

auth-transfer-export:
	mkdir -p ./keycloak-export
	mkdir -p ./keycloak-import
	cp -r ./keycloak-export/* ./keycloak-import/

auth-import: auth-stop
	mkdir -p ./keycloak-import
	$(OP_RUN_CORE) \
		docker compose -f $(CORE_COMPOSE) run --rm --no-deps \
		-v ./keycloak-import:/opt/keycloak/data/import \
		auth import \
		--dir /opt/keycloak/data/import

auth-migrate: auth-export auth-transfer-export auth-import
