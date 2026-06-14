#!/usr/bin/env bash
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
USER_ROLE="${KANBOARD_USER_ROLE:-kanboard-user}"
ADMIN_ROLE="${KANBOARD_ADMIN_ROLE:-kanboard-admin}"
USER_GROUP="${KANBOARD_USER_GROUP:-kanboard-users}"
ADMIN_GROUP="${KANBOARD_ADMIN_GROUP:-kanboard-admins}"
SOURCE_ADMIN_GROUP="${KANBOARD_SOURCE_ADMIN_GROUP:-admin}"
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

remote_json_file() {
  local body="$1"
  local path="/tmp/kcadm-kanboard-body-$$-${RANDOM}.json"
  printf '%s' "$body" |
    docker --context "$DOCKER_CONTEXT" exec -i "$AUTH_CONTAINER" sh -c "cat > '$path'"
  printf '%s\n' "$path"
}

remote_rm() {
  local path="$1"
  docker --context "$DOCKER_CONTEXT" exec "$AUTH_CONTAINER" rm -f "$path" >/dev/null 2>&1 || true
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
      -s "webOrigins=[\"$PUBLIC_URL\",\"$LAN_URL\"]" \
      -s 'attributes={"pkce.code.challenge.method":"S256"}' >/dev/null
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
      -s "webOrigins=[\"$PUBLIC_URL\",\"$LAN_URL\"]" \
      -s 'attributes={"pkce.code.challenge.method":"S256"}' >/dev/null
  fi
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

set_execution_requirement() {
  local flow_alias="$1"
  local execution_id="$2"
  local requirement="$3"
  kc update "$(flow_executions_endpoint "$flow_alias")" -r "$REALM" \
    -s "id=$execution_id" \
    -s "requirement=$requirement" \
    -n >/dev/null
}

copy_source_admin_members() {
  local target_group_id="$1"
  local source_group_id
  source_group_id="$(group_id_by_name "$SOURCE_ADMIN_GROUP")"
  if [ -z "$source_group_id" ]; then
    printf 'Source admin group not found, skipping member copy: %s\n' "$SOURCE_ADMIN_GROUP" >&2
    return
  fi

  kc get "groups/$source_group_id/members" -r "$REALM" --fields id,username |
    jq -r '.[].id' |
    while IFS= read -r user_id; do
      [ -n "$user_id" ] || continue
      kc update "users/$user_id/groups/$target_group_id" -r "$REALM" \
        -s "realm=$REALM" \
        -s "userId=$user_id" \
        -s "groupId=$target_group_id" \
        -n >/dev/null
    done
}

ensure_group_mapper() {
  local client_id="$1"
  local mapper_body
  mapper_body="$(
    jq -nc '{
      name: "kanboard_roles",
      protocol: "openid-connect",
      protocolMapper: "oidc-group-membership-mapper",
      consentRequired: false,
      config: {
        "full.path": "false",
        "claim.name": "kanboard_roles",
        "id.token.claim": "true",
        "access.token.claim": "true",
        "userinfo.token.claim": "true",
        "introspection.token.claim": "true",
        "lightweight.claim": "false"
      }
    }'
  )"
  local mapper_id
  local mapper_json
  mapper_json="$(kc get "clients/$client_id/protocol-mappers/models" -r "$REALM")"
  mapper_id="$(
    printf '%s' "$mapper_json" |
      jq -r '.[] | select(.name == "kanboard_roles") | .id' |
      head -n 1
  )"

  if [ -n "$mapper_id" ]; then
    if printf '%s' "$mapper_json" | jq -e '
      .[] | select(.id == "'"$mapper_id"'") |
      .protocolMapper == "oidc-group-membership-mapper" and
      .config["full.path"] == "false" and
      .config["claim.name"] == "kanboard_roles" and
      .config["id.token.claim"] == "true" and
      .config["access.token.claim"] == "true" and
      .config["userinfo.token.claim"] == "true" and
      .config["introspection.token.claim"] == "true"
    ' >/dev/null; then
      return
    fi
    kc delete "clients/$client_id/protocol-mappers/models/$mapper_id" -r "$REALM" >/dev/null
  fi

  local mapper_file
  mapper_file="$(remote_json_file "$mapper_body")"
  kc create "clients/$client_id/protocol-mappers/models" -r "$REALM" -f "$mapper_file" >/dev/null
  remote_rm "$mapper_file"
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
      -s "description=Deny users without the $CLIENT_ID.$USER_ROLE client role" >/dev/null
    gate_exec_id="$(
      kc get "$(flow_executions_endpoint "$parent_flow_alias")" -r "$REALM" |
        jq -r --arg alias "$gate_alias" '.[] | select(.displayName == $alias) | .id' |
        head -n 1
    )"
  fi

  set_execution_requirement "$parent_flow_alias" "$gate_exec_id" CONDITIONAL

  ensure_flow_execution "$gate_alias" conditional-user-role REQUIRED "Require $CLIENT_ID.$USER_ROLE for Kanboard forms" \
    "condUserRole=$CLIENT_ID.$USER_ROLE" "negate=true"
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

ensure_client_role "$client_id" "$USER_ROLE"
ensure_client_role "$client_id" "$ADMIN_ROLE"

user_group_id="$(ensure_group "$USER_GROUP")"
admin_group_id="$(ensure_group "$ADMIN_GROUP")"

assign_group_role "$user_group_id" "$USER_ROLE"
assign_group_role "$admin_group_id" "$USER_ROLE"
assign_group_role "$admin_group_id" "$ADMIN_ROLE"
copy_source_admin_members "$admin_group_id"

ensure_group_mapper "$client_id"
ensure_auth_flow "$client_id"
store_client_secret "$client_id"

printf 'Configured Keycloak client %s in realm %s and stored its secret in 1Password.\n' "$CLIENT_ID" "$REALM"
