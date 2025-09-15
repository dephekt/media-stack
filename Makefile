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

.PHONY: network lan-net shim core-up core-down ai-up ai-down up down restart logs-core logs-ai

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
