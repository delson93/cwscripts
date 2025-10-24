#!/usr/bin/env bash
#
# bulk-varnish-control-auto-token.sh
#
# Bulk Varnish Control for Cloudways (auto obtains OAuth access token).
# Usage:
#   ./bulk-varnish-control-auto-token.sh -e email -k api_key -a enable|disable [--dry-run] [--no-prompt]
#
# Requirements: curl, jq
set -euo pipefail

CLOUDWAYS_BASE="https://api.cloudways.com/api/v1"
TOKEN_ENDPOINT="${CLOUDWAYS_BASE}/oauth/access_token"
SERVERS_ENDPOINT="${CLOUDWAYS_BASE}/server"
VARNISH_ENDPOINT="${CLOUDWAYS_BASE}/service/varnish"

# Helpers
usage() {
  cat <<EOF
Usage: $0 -e email -k api_key -a enable|disable [--dry-run] [--no-prompt]
  -e email        : Cloudways account email (required)
  -k api_key      : Cloudways API key (required)
  -a action       : enable or disable varnish on all servers (required)
  --dry-run       : do not perform POSTs, only show actions
  --no-prompt     : do not ask for confirmation (non-interactive)
  -h, --help      : show this help
EOF
  exit 1
}

err_exit() {
  echo "Error: $1" >&2
  exit "${2:-1}"
}

check_requirements() {
  command -v curl >/dev/null 2>&1 || err_exit "curl is required but not installed."
  command -v jq >/dev/null 2>&1 || err_exit "jq is required but not installed."
}

# Default flags
EMAIL=""
API_KEY=""
ACTION=""
DRY_RUN=false
NO_PROMPT=false

# Parse args (simple POSIX-parsing)
while [[ $# -gt 0 ]]; do
  case "$1" in
    -e) EMAIL="$2"; shift 2 ;;
    -k) API_KEY="$2"; shift 2 ;;
    -a) ACTION="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --no-prompt) NO_PROMPT=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

if [[ -z "$EMAIL" ]]; then
  read -rp "Enter Cloudways account email: " EMAIL
fi
if [[ -z "$API_KEY" ]]; then
  read -rp "Enter Cloudways API key: " API_KEY
fi
if [[ -z "$ACTION" ]]; then
  read -rp "Choose action (enable|disable): " ACTION
fi

ACTION_LOWER=$(echo "$ACTION" | tr '[:upper:]' '[:lower:]')
if [[ "$ACTION_LOWER" != "enable" && "$ACTION_LOWER" != "disable" ]]; then
  err_exit "Action must be 'enable' or 'disable'."
fi

check_requirements

# ---- 1) Get OAuth access token ----
echo "Requesting OAuth access token..."
token_response=$(curl -sS -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "email=$(printf "%s" "$EMAIL" | sed 's/%/%25/g; s/&/%26/g')" \
  -d "api_key=$(printf "%s" "$API_KEY" | sed 's/%/%25/g; s/&/%26/g')" \
  "$TOKEN_ENDPOINT" || true)

# Validate JSON
if ! echo "$token_response" | jq -e . >/dev/null 2>&1; then
  echo "Failed to parse token response:"
  echo "$token_response"
  err_exit "Unable to obtain access token."
fi

if echo "$token_response" | jq -e 'has("error") or .access_token==null' >/dev/null 2>&1; then
  # Show non-sensitive error details and abort
  err_msg=$(echo "$token_response" | jq -r '.error_description // .error // .message // "Unknown error"')
  echo "Failed to obtain access token: $err_msg"
  echo "Full response (non-sensitive):"
  echo "$token_response"
  err_exit "Aborting due to token error."
fi

ACCESS_TOKEN=$(echo "$token_response" | jq -r '.access_token')
if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
  echo "No access_token found in response:"
  echo "$token_response"
  err_exit "Aborting."
fi

echo "Access token acquired (will expire in the token lifetime)."
echo

AUTH_HEADER="Authorization: Bearer ${ACCESS_TOKEN}"
ACCEPT_HEADER="Accept: application/json"
CONTENT_TYPE_HEADER="Content-Type: application/x-www-form-urlencoded"

# ---- 2) Fetch server list ----
echo "Fetching server list..."
servers_response=$(curl -sS -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" "$SERVERS_ENDPOINT" || true)

if ! echo "$servers_response" | jq -e . >/dev/null 2>&1; then
  echo "Failed to parse servers response:"
  echo "$servers_response"
  err_exit "Unable to list servers."
fi

# Handle API-level errors
if echo "$servers_response" | jq -e 'has("error") or .status==false' >/dev/null 2>&1; then
  err_msg=$(echo "$servers_response" | jq -r '.error_description // .message // .error // "Unknown error"')
  echo "API error while fetching servers: $err_msg"
  echo "Full response:"
  echo "$servers_response"
  err_exit "Aborting due to API error."
fi

# Extract server IDs
server_ids=()
if echo "$servers_response" | jq -e 'type=="array"' >/dev/null 2>&1; then
  mapfile -t server_ids < <(echo "$servers_response" | jq -r '.[].id')
elif echo "$servers_response" | jq -e 'has("servers")' >/dev/null 2>&1; then
  mapfile -t server_ids < <(echo "$servers_response" | jq -r '.servers[]?.id')
else
  echo "Unexpected servers response structure:"
  echo "$servers_response"
  err_exit "Aborting."
fi

server_count=${#server_ids[@]}
if [[ "$server_count" -eq 0 ]]; then
  echo "No servers found for this account."
  exit 0
fi

echo "Found $server_count server(s)."
echo "Action: $ACTION_LOWER"
echo "Dry run: $DRY_RUN"
echo

if [[ "$DRY_RUN" == false && "$NO_PROMPT" == false ]]; then
  read -rp "Proceed to ${ACTION_LOWER} varnish for all ${server_count} server(s)? [y/N]: " confirm
  confirm=${confirm:-N}
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Operation cancelled by user."
    exit 0
  fi
fi

# ---- 3) Iterate servers and change varnish ----
success_count=0
failure_count=0
declare -A failures

for sid in "${server_ids[@]}"; do
  echo -n "Server ID $sid : "
  if [[ "$DRY_RUN" == true ]]; then
    echo "DRY-RUN - would call ${VARNISH_ENDPOINT} with server_id=${sid}&action=${ACTION_LOWER}"
    continue
  fi

  post_data="server_id=${sid}&action=${ACTION_LOWER}"
  http_output=$(curl -sS -w "\n%{http_code}" -X POST \
    -H "$AUTH_HEADER" -H "$CONTENT_TYPE_HEADER" -H "$ACCEPT_HEADER" \
    -d "$post_data" \
    "$VARNISH_ENDPOINT" || true)

  http_body=$(echo "$http_output" | sed '$d')
  http_code=$(echo "$http_output" | tail -n1)

  if [[ "$http_code" != "200" && "$http_code" != "201" && "$http_code" != "202" ]]; then
    echo "FAIL (HTTP $http_code)"
    echo "  Response: $http_body"
    failures["$sid"]="HTTP $http_code - $http_body"
    ((failure_count++))
    continue
  fi

  ok=$(echo "$http_body" | jq -r '.status // empty' || echo "")
  if [[ "$ok" == "true" || "$ok" == "True" ]]; then
    echo "OK"
    ((success_count++))
  else
    msg=$(echo "$http_body" | jq -r '.message // .error_description // .error // "Unknown response"')
    echo "FAIL - $msg"
    failures["$sid"]="$msg"
    ((failure_count++))
  fi
done

# ---- Summary ----
echo
echo "Bulk Varnish Control - Summary"
echo "Action       : ${ACTION_LOWER}"
echo "Total target : ${server_count}"
if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run      : true (no changes made)"
else
  echo "Succeeded    : ${success_count}"
  echo "Failed       : ${failure_count}"
fi

if [[ "$failure_count" -gt 0 ]]; then
  echo
  echo "Failures detail:"
  for sid in "${!failures[@]}"; do
    echo "  Server ${sid}: ${failures[$sid]}"
  done
  exit 2
fi

exit 0
