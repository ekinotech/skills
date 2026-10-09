#!/usr/bin/env bash
# JIRA helper: view issue, search (JQL), find users, log work, comment, transition, update fields.
# Uses REST API v2 (works on Cloud and Server/DC).
#
# Usage:
#   jira.sh get KEY
#   jira.sh search "JQL" [--max N]
#   jira.sh users "name"
#   jira.sh worklogs KEY
#   jira.sh logwork KEY "1h 30m" [--comment "text"] [--started "2026-10-08" | "2026-10-08 14:00"]
#     (--started is read in the JIRA profile timezone, the one the JIRA UI shows)
#   jira.sh comment KEY "text"
#   jira.sh transitions KEY
#   jira.sh transition KEY TRANSITION_ID
#   jira.sh update KEY [--summary "text"] [--description "text"] [--assignee "accountId (Cloud) | username (Server/DC)"]
#
# Credentials: read only from <skill dir>/.env (no env vars, no project files).
#   JIRA_BASE_URL, JIRA_API_TOKEN, JIRA_EMAIL (Cloud only; omit for Server/DC PAT)

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$SKILL_DIR/.env"

read_env_value() {
  local name="$1" file="$2" v
  [ -f "$file" ] || return 1
  v="$(sed -nE "s/^[[:space:]]*(export[[:space:]]+)?${name}[[:space:]]*=[[:space:]]*(.*)$/\2/p" "$file" | tail -n 1)"
  if [[ $v =~ ^\"([^\"]*)\" ]]; then v="${BASH_REMATCH[1]}"
  elif [[ $v =~ ^\'([^\']*)\' ]]; then v="${BASH_REMATCH[1]}"
  else v="$(printf '%s' "$v" | sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//')"
  fi
  printf '%s\n' "$v"
}

resolve() {
  read_env_value "$1" "$ENV_FILE" || true
}

die() { echo "$*" >&2; exit 1; }
# need_val OPTION COUNT_OF_REMAINING_ARGS: fail clearly when an option has no value
need_val() { [ "$2" -ge 2 ] || die "Missing value for $1"; }

JIRA_BASE_URL="$(resolve JIRA_BASE_URL)"
JIRA_API_TOKEN="$(resolve JIRA_API_TOKEN)"
JIRA_EMAIL="$(resolve JIRA_EMAIL)"

if [ -z "$JIRA_BASE_URL" ] || [ -z "$JIRA_API_TOKEN" ]; then
  echo "JIRA_CREDENTIALS_MISSING: JIRA_BASE_URL / JIRA_API_TOKEN not set."
  echo "Add to $ENV_FILE:"
  echo "  JIRA_BASE_URL=https://your-company.atlassian.net"
  echo "  # JIRA_EMAIL: Cloud only; omit this line for a Server/DC personal access token"
  echo "  JIRA_EMAIL=you@company.com"
  echo "  JIRA_API_TOKEN=<token>"
  exit 1
fi
case "$JIRA_BASE_URL" in
  https://*) JIRA_BASE_URL="${JIRA_BASE_URL%/}" ;;
  *) echo "JIRA_BASE_URL must start with https://" >&2; exit 1 ;;
esac
command -v jq >/dev/null 2>&1 || { echo "jq is required. Install: brew install jq" >&2; exit 1; }

# Auth goes through curl's stdin config so the token never appears in argv.
curl_auth_config() {
  if [ -n "$JIRA_EMAIL" ]; then
    printf 'user = "%s:%s"\n' "$JIRA_EMAIL" "$JIRA_API_TOKEN"
  else
    printf 'header = "Authorization: Bearer %s"\n' "$JIRA_API_TOKEN"
  fi
}

# api METHOD PATH [JSON_BODY]  -> prints body, exits non-zero on HTTP error
api() {
  local method="$1" path="$2" data="${3:-}" body_file http_code
  body_file="$(mktemp)"
  if [ -n "$data" ]; then
    http_code="$(curl_auth_config | curl -sS --connect-timeout 10 --max-time 60 -K - -X "$method" -H 'Accept: application/json' \
      -H 'Content-Type: application/json' --data "$data" -o "$body_file" -w '%{http_code}' \
      "$JIRA_BASE_URL/rest/api/2/$path" || true)"
  else
    http_code="$(curl_auth_config | curl -sS --connect-timeout 10 --max-time 60 -K - -X "$method" -H 'Accept: application/json' \
      -o "$body_file" -w '%{http_code}' "$JIRA_BASE_URL/rest/api/2/$path" || true)"
  fi
  http_code="${http_code:-000}"
  case "$http_code" in
    2*) cat "$body_file"; rm -f "$body_file" ;;
    401|403) echo "Access denied (HTTP $http_code). Check JIRA_EMAIL / JIRA_API_TOKEN and permissions." >&2; rm -f "$body_file"; return 1 ;;
    404) echo "Not found (HTTP 404). Wrong key, or no access." >&2; rm -f "$body_file"; return 1 ;;
    000) echo "Request failed. Could not reach $JIRA_BASE_URL." >&2; rm -f "$body_file"; return 1 ;;
    *) echo "Unexpected HTTP $http_code:" >&2; head -c 600 "$body_file" >&2; echo >&2; rm -f "$body_file"; return 1 ;;
  esac
}

# Turn "YYYY-MM-DD" (09:00 assumed) or "YYYY-MM-DD HH:MM" into a JIRA timestamp in the
# timezone of the JIRA profile (what the JIRA UI shows). Full ISO strings pass through.
normalize_started() {
  local in="$1" tz stamp
  case "$in" in
    ????-??-??T*)
      printf '%s' "$in" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}[+-][0-9]{4}$' \
        || { echo "Bad --started ISO: $1 (use yyyy-MM-ddTHH:mm:ss.SSS+0700)" >&2; return 1; }
      printf '%s' "$in"; return ;;
    ????-??-??) in="$in 09:00" ;;
    ????-??-??\ ??:??) ;;
    *) echo "Bad --started: $1 (use YYYY-MM-DD, \"YYYY-MM-DD HH:MM\", or full ISO)" >&2; return 1 ;;
  esac
  tz="$(api GET myself | jq -r '.timeZone // empty')"
  [ -n "$tz" ] || { echo "Could not read JIRA timezone" >&2; return 1; }
  if date -j -f '%Y-%m-%d' '2000-01-01' '+%Y' >/dev/null 2>&1; then
    stamp="$(TZ="$tz" date -j -f '%Y-%m-%d %H:%M' "$in" '+%Y-%m-%dT%H:%M:00.000%z' 2>/dev/null)" || stamp=""
  else
    stamp="$(TZ="$tz" date -d "$in" '+%Y-%m-%dT%H:%M:00.000%z' 2>/dev/null)" || stamp=""
  fi
  # BSD date rolls impossible dates (02-30) and DST gaps forward; reject any change.
  [ "${stamp:0:16}" = "${in/ /T}" ] || { echo "Invalid date/time in $tz: $in" >&2; return 1; }
  echo "Started $in in JIRA timezone $tz ($stamp)" >&2
  printf '%s' "$stamp"
}

check_key() {
  [[ $1 =~ ^[A-Z][A-Z0-9_]+-[0-9]+$ ]] || die "Not a JIRA key: $1"
}

cmd="${1:-}"; shift || true
if [ "$cmd" = "search" ]; then
  jql="${1:-}"; shift || true
  [ -n "$jql" ] || { echo "Missing JQL, e.g. \"project = KEY AND assignee = currentUser()\"" >&2; exit 1; }
  max=50
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --max) need_val "$1" "$#"; max="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done
  printf '%s' "$max" | grep -Eq '^[0-9]+$' || { echo "Bad --max: $max" >&2; exit 1; }
  # Cloud (email set) removed /search in favour of /search/jql, which has no total.
  endpoint="search"; [ -z "$JIRA_EMAIL" ] || endpoint="search/jql"
  api GET "$endpoint?maxResults=$max&fields=summary,status,issuetype,priority&jql=$(jq -rn --arg q "$jql" '$q|@uri')" \
    | jq -r '"Total: \(.total // (.issues|length))", (.issues[] | "\(.key) | \(.fields.status.name) | \(.fields.issuetype.name) | \(.fields.priority.name // "-") | \(.fields.summary)")'
  exit 0
fi
if [ "$cmd" = "users" ]; then
  q="${1:-}"; [ -n "$q" ] || die "Missing name to search"
  enc="$(jq -rn --arg q "$q" '$q|@uri')"
  # Cloud reads "query", Server/DC reads "username"; send both.
  api GET "user/search?query=$enc&username=$enc" \
    | jq -r '.[] | "\(.accountId // .name)\t\(.displayName)\tactive=\(.active)"'
  exit 0
fi
key="${1:-}"; shift || true
[ -n "$cmd" ] && [ -n "$key" ] || { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
check_key "$key"

case "$cmd" in
  get)
    api GET "issue/$key?fields=summary,status,issuetype,assignee,description,timetracking" \
      | jq -r '"Summary: \(.fields.summary // "")",
               "Type: \(.fields.issuetype.name // "")",
               "Status: \(.fields.status.name // "")",
               "Assignee: \(.fields.assignee.displayName // "unassigned")",
               "Time spent: \(.fields.timetracking.timeSpent // "none")  Remaining: \(.fields.timetracking.remainingEstimate // "none")",
               "Description:", (.fields.description // "(empty)")'
    ;;
  worklogs)
    api GET "issue/$key/worklog" \
      | jq -r '.worklogs[] | "\(.started[0:16])  \(.timeSpent)  \(.author.displayName)  \((.comment // "") | gsub("[\r\n]+";" "))"'
    ;;
  logwork)
    time_spent="${1:-}"; shift || true
    [ -n "$time_spent" ] || { echo "Missing time, e.g. \"1h 30m\"" >&2; exit 1; }
    printf '%s' "$time_spent" | grep -Eq '^([0-9]+[wdhm] ?)+$' || { echo "Bad time format: $time_spent (use e.g. 2h, 1h 30m, 1d)" >&2; exit 1; }
    comment=""; started=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --comment) need_val "$1" "$#"; comment="$2"; shift 2 ;;
        --started) need_val "$1" "$#"; started="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done
    [ -z "$started" ] || started="$(normalize_started "$started")"
    payload="$(jq -n --arg t "$time_spent" --arg c "$comment" --arg s "$started" \
      '{timeSpent:$t} + (if $c != "" then {comment:$c} else {} end) + (if $s != "" then {started:$s} else {} end)')"
    api POST "issue/$key/worklog" "$payload" | jq -r --arg k "$key" '"Logged \(.timeSpent) on \($k) (worklog id \(.id))"'
    ;;
  comment)
    text="${1:-}"; [ -n "$text" ] || { echo "Missing comment text" >&2; exit 1; }
    api POST "issue/$key/comment" "$(jq -n --arg b "$text" '{body:$b}')" | jq -r '"Comment added (id \(.id))"'
    ;;
  transitions)
    api GET "issue/$key/transitions" | jq -r '.transitions[] | "\(.id)\t\(.name) -> \(.to.name)"'
    ;;
  transition)
    tid="${1:-}"; [ -n "$tid" ] || { echo "Missing transition id (see: transitions)" >&2; exit 1; }
    api POST "issue/$key/transitions" "$(jq -n --arg i "$tid" '{transition:{id:$i}}')" >/dev/null
    echo "Transition $tid applied to $key"
    ;;
  update)
    summary=""; description=""; assignee=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --summary) need_val "$1" "$#"; summary="$2"; shift 2 ;;
        --description) need_val "$1" "$#"; description="$2"; shift 2 ;;
        --assignee) need_val "$1" "$#"; assignee="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done
    if [ -n "$assignee" ] && [ -n "$JIRA_EMAIL" ] && ! printf '%s' "$assignee" | grep -Eq '^[0-9a-f:-]{20,}$'; then
      die "JIRA Cloud needs an accountId for --assignee. Look it up with: users \"name\""
    fi
    fields="$(jq -n --arg s "$summary" --arg d "$description" --arg a "$assignee" '
      (if $s != "" then {summary:$s} else {} end)
      + (if $d != "" then {description:$d} else {} end)
      + (if $a != "" then {assignee:(if ($a|test("^[0-9a-f:-]{20,}$")) then {accountId:$a} else {name:$a} end)} else {} end)')"
    [ "$fields" != "{}" ] || { echo "Nothing to update" >&2; exit 1; }
    api PUT "issue/$key" "$(jq -n --argjson f "$fields" '{fields:$f}')" >/dev/null
    echo "Updated $key: $(echo "$fields" | jq -r 'keys | join(", ")')"
    ;;
  *) echo "Unknown command: $cmd" >&2; exit 1 ;;
esac
