#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

DOCKER_CONTEXT="${DOCKER_CONTEXT:-media-server}"
AUTH_CONTAINER="${AUTH_CONTAINER:-auth}"
REALM="${KEYCLOAK_REALM:-home}"
CLIENT_ID="${KANBOARD_OIDC_CLIENT_ID:-kanboard}"
CLIENT_NAME="${KANBOARD_OIDC_CLIENT_NAME:-Kanboard}"
PUBLIC_URL="${KANBOARD_PUBLIC_URL:-https://kanban.ai.dephekt.net}"
LAN_URL="${KANBOARD_LAN_URL:-http://containers.home.arpa:8097}"
FLOW_ALIAS="${KANBOARD_AUTH_FLOW:-kanboard-browser}"
GATE_ALIAS="${KANBOARD_AUTH_GATE:-Kanboard role gate}"
FORM_FLOW_ALIAS="${KANBOARD_FORM_FLOW:-${FLOW_ALIAS} forms}"
FORM_GATE_ALIAS="${KANBOARD_FORM_GATE:-Kanboard form role gate}"
ACCESS_ROLE="${KANBOARD_ACCESS_ROLE:-kanboard}"
ACCESS_GROUP="${KANBOARD_ACCESS_GROUP:-kanboard}"
LEGACY_USER_ROLE="${KANBOARD_LEGACY_USER_ROLE:-kanboard-user}"
LEGACY_ADMIN_ROLE="${KANBOARD_LEGACY_ADMIN_ROLE:-kanboard-admin}"
LEGACY_USER_GROUP="${KANBOARD_LEGACY_USER_GROUP:-kanboard-users}"
LEGACY_ADMIN_GROUP="${KANBOARD_LEGACY_ADMIN_GROUP:-kanboard-admins}"
OP_ITEM="${KANBOARD_OP_ITEM:-Kanboard}"
OP_VAULT="${KANBOARD_OP_VAULT:-Agents}"
OP_SECRET_FIELD="${KANBOARD_OP_SECRET_FIELD:-oauth client secret}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

require_cmd docker
require_cmd jq
require_cmd op-agent

KCADM_CONFIG="/tmp/kcadm-kanboard-${USER:-user}-$$.config"

cleanup() {
  docker --context "$DOCKER_CONTEXT" exec "$AUTH_CONTAINER" rm -f "$KCADM_CONFIG" >/dev/null 2>&1 || true
}
trap cleanup EXIT

kc() {
  docker --context "$DOCKER_CONTEXT" exec -e "KCADM_CONFIG=$KCADM_CONFIG" "$AUTH_CONTAINER" sh -lc '
    set -eu
    if [ ! -s "$KCADM_CONFIG" ]; then
      admin_pass=$(cat /run/secrets/KEYCLOAK_ADMIN_PASSWORD.env)
      /opt/keycloak/bin/kcadm.sh config credentials \
        --config "$KCADM_CONFIG" \
        --server http://localhost:8080 \
        --realm master \
        --user "${KEYCLOAK_ADMIN:-admin}" \
        --password "$admin_pass" >/dev/null
    fi
    cmd="$1"
    shift
    /opt/keycloak/bin/kcadm.sh "$cmd" --config "$KCADM_CONFIG" "$@"
  ' sh "$@"
}

json_get() {
  jq -r "$1"
}

urlencode() {
  jq -nr --arg value "$1" '$value | @uri'
}

flow_executions_endpoint() {
  printf 'authentication/flows/%s/executions' "$(urlencode "$1")"
}

client_uuid() {
  kc get clients -r "$REALM" -q "clientId=$CLIENT_ID" --fields id,clientId |
    json_get '.[0].id // empty'
}

group_id_by_name() {
  local name="$1"
  kc get groups -r "$REALM" --fields id,name,path |
    jq -r --arg name "$name" '.[] | select(.name == $name) | .id' |
    head -n 1
}

flow_id_by_alias() {
  local alias="$1"
  kc get authentication/flows -r "$REALM" --fields id,alias |
    jq -r --arg alias "$alias" '.[] | select(.alias == $alias) | .id' |
    head -n 1
}

ensure_client() {
  local id
  id="$(client_uuid)"
  if [ -z "$id" ]; then
    kc create clients -r "$REALM" \
      -s "clientId=$CLIENT_ID" \
      -s "name=$CLIENT_NAME" \
      -s enabled=true \
      -s protocol=openid-connect \
      -s publicClient=false \
      -s standardFlowEnabled=true \
      -s directAccessGrantsEnabled=false \
      -s serviceAccountsEnabled=false \
      -s frontchannelLogout=false \
      -s "rootUrl=$PUBLIC_URL" \
      -s "baseUrl=$PUBLIC_URL/" \
      -s "adminUrl=$PUBLIC_URL/" \
      -s "redirectUris=[\"$PUBLIC_URL/oauth/callback*\",\"$LAN_URL/oauth/callback*\"]" \
      -s "webOrigins=[\"$PUBLIC_URL\",\"$LAN_URL\"]" >/dev/null
  else
    kc update "clients/$id" -r "$REALM" \
      -s "name=$CLIENT_NAME" \
      -s enabled=true \
      -s protocol=openid-connect \
      -s publicClient=false \
      -s standardFlowEnabled=true \
      -s directAccessGrantsEnabled=false \
      -s serviceAccountsEnabled=false \
      -s frontchannelLogout=false \
      -s "rootUrl=$PUBLIC_URL" \
      -s "baseUrl=$PUBLIC_URL/" \
      -s "adminUrl=$PUBLIC_URL/" \
      -s "redirectUris=[\"$PUBLIC_URL/oauth/callback*\",\"$LAN_URL/oauth/callback*\"]" \
      -s "webOrigins=[\"$PUBLIC_URL\",\"$LAN_URL\"]" >/dev/null
  fi
}

disable_client_pkce() {
  local client_id="$1"
  local attrs
  attrs="$(
    kc get "clients/$client_id" -r "$REALM" --fields attributes |
      jq -c '(.attributes // {}) + {"pkce.code.challenge.method": ""}'
  )"

  # Keycloak removes the stored PKCE row when this value is empty. Deleting the
  # key from the JSON representation can leave a stale effective DB row behind.
  kc update "clients/$client_id" -r "$REALM" -s "attributes=$attrs" >/dev/null
}

ensure_client_role() {
  local client_id="$1"
  local role="$2"
  if ! kc get "clients/$client_id/roles/$role" -r "$REALM" >/dev/null 2>&1; then
    kc create "clients/$client_id/roles" -r "$REALM" \
      -s "name=$role" \
      -s "description=Kanboard access role" >/dev/null
  fi
}

ensure_group() {
  local group="$1"
  local id
  id="$(group_id_by_name "$group")"
  if [ -z "$id" ]; then
    kc create groups -r "$REALM" -s "name=$group" >/dev/null
    id="$(group_id_by_name "$group")"
  fi
  printf '%s\n' "$id"
}

assign_group_role() {
  local group_id="$1"
  local role="$2"
  kc add-roles -r "$REALM" --gid "$group_id" --cclientid "$CLIENT_ID" --rolename "$role" >/dev/null 2>&1 || true
}

add_user_to_group() {
  local user_id="$1"
  local group_id="$2"
  kc update "users/$user_id/groups/$group_id" -r "$REALM" \
    -s "realm=$REALM" \
    -s "userId=$user_id" \
    -s "groupId=$group_id" \
    -n >/dev/null
}

set_execution_requirement() {
  local flow_alias="$1"
  local execution_id="$2"
  local requirement="$3"
  kc update "$(flow_executions_endpoint "$flow_alias")" -r "$REALM" \
    -s "id=$execution_id" \
    -s "requirement=$requirement" \
    -n >/dev/null
}

copy_group_members() {
  local source_group="$1"
  local target_group_id="$2"
  local source_group_id
  source_group_id="$(group_id_by_name "$source_group")"
  if [ -z "$source_group_id" ]; then
    return
  fi

  kc get "groups/$source_group_id/members" -r "$REALM" --fields id,username |
    jq -r '.[].id' |
    while IFS= read -r user_id; do
      [ -n "$user_id" ] || continue
      add_user_to_group "$user_id" "$target_group_id"
    done
}

migrate_legacy_group_members() {
  local target_group_id="$1"
  copy_group_members "$LEGACY_USER_GROUP" "$target_group_id"
  copy_group_members "$LEGACY_ADMIN_GROUP" "$target_group_id"
}

remove_group_by_name() {
  local group="$1"
  local id
  id="$(group_id_by_name "$group")"
  if [ -n "$id" ]; then
    kc delete "groups/$id" -r "$REALM" >/dev/null
  fi
}

remove_client_role() {
  local client_id="$1"
  local role="$2"
  if kc get "clients/$client_id/roles/$role" -r "$REALM" >/dev/null 2>&1; then
    kc delete "clients/$client_id/roles/$role" -r "$REALM" >/dev/null
  fi
}

remove_legacy_access_model() {
  local client_id="$1"
  remove_group_by_name "$LEGACY_USER_GROUP"
  remove_group_by_name "$LEGACY_ADMIN_GROUP"
  remove_client_role "$client_id" "$LEGACY_USER_ROLE"
  remove_client_role "$client_id" "$LEGACY_ADMIN_ROLE"
}

remove_group_mapper() {
  local client_id="$1"
  local mapper_id
  local mapper_json
  mapper_json="$(kc get "clients/$client_id/protocol-mappers/models" -r "$REALM")"
  mapper_id="$(
    printf '%s' "$mapper_json" |
      jq -r '.[] | select(.name == "kanboard_roles") | .id' |
      head -n 1
  )"

  if [ -n "$mapper_id" ]; then
    kc delete "clients/$client_id/protocol-mappers/models/$mapper_id" -r "$REALM" >/dev/null
  fi
}

ensure_auth_flow() {
  local client_id="$1"
  local flow_id
  flow_id="$(flow_id_by_alias "$FLOW_ALIAS")"
  if [ -z "$flow_id" ]; then
    kc create authentication/flows/browser/copy -r "$REALM" -s "newName=$FLOW_ALIAS" >/dev/null
    flow_id="$(flow_id_by_alias "$FLOW_ALIAS")"
  fi

  local legacy_gate_exec_id
  legacy_gate_exec_id="$(
    kc get "$(flow_executions_endpoint "$FLOW_ALIAS")" -r "$REALM" |
      jq -r --arg alias "$GATE_ALIAS" '.[] | select(.displayName == $alias) | .id' |
      head -n 1
  )"
  if [ -n "$legacy_gate_exec_id" ]; then
    set_execution_requirement "$FLOW_ALIAS" "$legacy_gate_exec_id" DISABLED
  fi

  ensure_gate_flow "$FORM_FLOW_ALIAS" "$FORM_GATE_ALIAS"

  kc update "clients/$client_id" -r "$REALM" \
    -s "authenticationFlowBindingOverrides={\"browser\":\"$flow_id\"}" >/dev/null
}

ensure_gate_flow() {
  local parent_flow_alias="$1"
  local gate_alias="$2"
  local gate_exec_id
  gate_exec_id="$(
    kc get "$(flow_executions_endpoint "$parent_flow_alias")" -r "$REALM" |
      jq -r --arg alias "$gate_alias" '.[] | select(.displayName == $alias) | .id' |
      head -n 1
  )"

  if [ -z "$gate_exec_id" ]; then
    kc create "$(flow_executions_endpoint "$parent_flow_alias")/flow" -r "$REALM" \
      -s "alias=$gate_alias" \
      -s type=basic-flow \
      -s provider=basic-flow \
      -s "description=Deny users without the $CLIENT_ID.$ACCESS_ROLE client role" >/dev/null
    gate_exec_id="$(
      kc get "$(flow_executions_endpoint "$parent_flow_alias")" -r "$REALM" |
        jq -r --arg alias "$gate_alias" '.[] | select(.displayName == $alias) | .id' |
        head -n 1
    )"
  fi

  set_execution_requirement "$parent_flow_alias" "$gate_exec_id" CONDITIONAL

  ensure_flow_execution "$gate_alias" conditional-user-role REQUIRED "Require $CLIENT_ID.$ACCESS_ROLE for Kanboard forms" \
    "condUserRole=$CLIENT_ID.$ACCESS_ROLE" "negate=true"
  ensure_flow_execution "$gate_alias" deny-access-authenticator REQUIRED "Deny non-Kanboard users for Kanboard forms" \
    'denyErrorMessage=kanboard-access-required'
}

ensure_flow_execution() {
  local flow_alias="$1"
  local provider="$2"
  local requirement="$3"
  local config_alias="$4"
  shift 4

  local exec_id
  exec_id="$(
    kc get "$(flow_executions_endpoint "$flow_alias")" -r "$REALM" |
      jq -r --arg provider "$provider" '.[] | select(.providerId == $provider) | .id' |
      head -n 1
  )"

  if [ -z "$exec_id" ]; then
    kc create "$(flow_executions_endpoint "$flow_alias")/execution" -r "$REALM" \
      -s "provider=$provider" >/dev/null
    exec_id="$(
      kc get "$(flow_executions_endpoint "$flow_alias")" -r "$REALM" |
        jq -r --arg provider "$provider" '.[] | select(.providerId == $provider) | .id' |
        head -n 1
    )"
  fi

  set_execution_requirement "$flow_alias" "$exec_id" "$requirement"

  local config_id
  config_id="$(
    kc get "$(flow_executions_endpoint "$flow_alias")" -r "$REALM" |
      jq -r --arg id "$exec_id" '.[] | select(.id == $id) | .authenticationConfig // empty' |
      head -n 1
  )"

  if [ -z "$config_id" ]; then
    local args=(-s "alias=$config_alias")
    local pair
    for pair in "$@"; do
      args+=(-s "config.$pair")
    done
    kc create "authentication/executions/$exec_id/config" -r "$REALM" "${args[@]}" >/dev/null
  else
    local args=(-s "alias=$config_alias")
    local pair
    for pair in "$@"; do
      args+=(-s "config.$pair")
    done
    kc update "authentication/config/$config_id" -r "$REALM" "${args[@]}" >/dev/null
  fi
}

store_client_secret() {
  local client_id="$1"
  local secret
  secret="$(kc get "clients/$client_id/client-secret" -r "$REALM" | jq -r '.value')"
  if [ -z "$secret" ] || [ "$secret" = "null" ]; then
    printf 'Unable to read Keycloak client secret\n' >&2
    exit 1
  fi
  op-agent item edit "$OP_ITEM" --vault "$OP_VAULT" "${OP_SECRET_FIELD}[concealed]=$secret" >/dev/null
}

ensure_client
client_id="$(client_uuid)"
if [ -z "$client_id" ]; then
  printf 'Unable to find or create Keycloak client: %s\n' "$CLIENT_ID" >&2
  exit 1
fi
disable_client_pkce "$client_id"

ensure_client_role "$client_id" "$ACCESS_ROLE"

access_group_id="$(ensure_group "$ACCESS_GROUP")"
migrate_legacy_group_members "$access_group_id"
assign_group_role "$access_group_id" "$ACCESS_ROLE"

remove_group_mapper "$client_id"
ensure_auth_flow "$client_id"
remove_legacy_access_model "$client_id"
store_client_secret "$client_id"

printf 'Configured Keycloak client %s in realm %s and stored its secret in 1Password.\n' "$CLIENT_ID" "$REALM"
