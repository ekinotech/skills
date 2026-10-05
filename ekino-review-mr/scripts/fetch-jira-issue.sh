#!/usr/bin/env bash
# Fetch JIRA issue summary/status/description for MR review context.
# READ-ONLY: issues HTTP GET requests only. Never creates, edits, transitions, or comments.
#
# Usage: fetch-jira-issue.sh KEY-123 [KEY-456 ...]
#
# Credentials (first value found wins, per variable):
#   1. Environment variables
#   2. <project root>/.claude/.env
#   3. ~/.claude/.env
#   4. <this skill>/.env
#
#   JIRA_BASE_URL   e.g. https://your-company.atlassian.net
#   JIRA_API_TOKEN  Cloud API token, or Server/Data Center personal access token
#   JIRA_EMAIL      Cloud only (Basic auth). Leave unset for Server/DC PAT (Bearer auth).

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ENV_FILES=("$PROJECT_ROOT/.claude/.env" "$HOME/.claude/.env" "$SKILL_DIR/.env")

if [ "$#" -eq 0 ]; then
  echo "Usage: $(basename "$0") KEY-123 [KEY-456 ...]" >&2
  exit 1
fi

# Read one KEY=VALUE from a dotenv file without sourcing it (no code execution).
read_env_value() {
  local name="$1" file="$2"
  [ -f "$file" ] || return 1
  sed -nE "s/^[[:space:]]*(export[[:space:]]+)?${name}[[:space:]]*=[[:space:]]*(.*)$/\2/p" "$file" \
    | tail -n 1 | sed -E 's/[[:space:]]+$//; s/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/'
}

# Resolve a variable: environment first, then each env file in order.
resolve() {
  local name="$1" value="${!1:-}" file
  if [ -z "$value" ]; then
    for file in "${ENV_FILES[@]}"; do
      value="$(read_env_value "$name" "$file" || true)"
      [ -n "$value" ] && break
    done
  fi
  printf '%s' "$value"
}

JIRA_BASE_URL="$(resolve JIRA_BASE_URL)"
JIRA_API_TOKEN="$(resolve JIRA_API_TOKEN)"
JIRA_EMAIL="$(resolve JIRA_EMAIL)"

if [ -z "$JIRA_BASE_URL" ] || [ -z "$JIRA_API_TOKEN" ]; then
  echo "JIRA_CREDENTIALS_MISSING: found JIRA key(s) $*, but cannot fetch them (JIRA_BASE_URL / JIRA_API_TOKEN not set)."
  echo "To enable, add to ~/.claude/.env (or <project>/.claude/.env, or export as env vars):"
  echo "  JIRA_BASE_URL=https://your-company.atlassian.net"
  echo "  JIRA_EMAIL=you@company.com   # Cloud only; omit for Server/DC personal access token"
  echo "  JIRA_API_TOKEN=<token>       # Cloud: https://id.atlassian.com/manage-profile/security/api-tokens"
  exit 0
fi

case "$JIRA_BASE_URL" in
  https://*) JIRA_BASE_URL="${JIRA_BASE_URL%/}" ;;
  *) echo "JIRA_BASE_URL must start with https://" >&2; exit 1 ;;
esac

# Auth goes through curl's stdin config so the token never appears in argv / process list.
curl_auth_config() {
  if [ -n "$JIRA_EMAIL" ]; then
    printf 'user = "%s:%s"\n' "$JIRA_EMAIL" "$JIRA_API_TOKEN"
  else
    printf 'header = "Authorization: Bearer %s"\n' "$JIRA_API_TOKEN"
  fi
}

for key in "$@"; do
  if ! printf '%s' "$key" | grep -Eq '^[A-Z][A-Z0-9_]+-[0-9]+$'; then
    echo "== $key: skipped (not a JIRA key format)"
    continue
  fi

  url="$JIRA_BASE_URL/rest/api/2/issue/$key?fields=summary,status,issuetype,description"
  body_file="$(mktemp)"
  http_code="$(curl_auth_config | curl -sS --get -K - -H 'Accept: application/json' \
    -o "$body_file" -w '%{http_code}' "$url" 2>/dev/null || true)"
  http_code="${http_code:-000}"

  echo "== $key"
  case "$http_code" in
    200)
      if command -v jq >/dev/null 2>&1; then
        jq -r '"Summary: \(.fields.summary // "")",
               "Type: \(.fields.issuetype.name // "")",
               "Status: \(.fields.status.name // "")",
               "Description:", (.fields.description // "(empty)")' "$body_file"
      else
        cat "$body_file"; echo
      fi
      ;;
    401|403) echo "Access denied (HTTP $http_code). Check JIRA_EMAIL / JIRA_API_TOKEN and project permissions." ;;
    404) echo "Not found (HTTP 404). Not a JIRA issue, or no access." ;;
    000) echo "Request failed. Could not reach $JIRA_BASE_URL." ;;
    *) echo "Unexpected HTTP $http_code." ;;
  esac
  rm -f "$body_file"
done
