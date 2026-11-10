#!/usr/bin/env bash
# Local SonarQube Community scan: start container, scan, print issues, stop container.
# Usage: sonar-scan.sh [scan] [options]
#        sonar-scan.sh stop | status | reset | help
# Run "sonar-scan.sh help" for all options. Env vars mirror the CI names (SONAR_SOURCES, ...).
set -euo pipefail

STATE_DIR="${SONAR_STATE_DIR:-$HOME/.ekino-sonar}"
COMPOSE_FILE="$STATE_DIR/docker-compose.sonar.yml"
CRED_FILE="$STATE_DIR/credentials.env"
PORT="${SONAR_PORT:-9000}"
SONAR_IMAGE="${SONAR_IMAGE:-docker.io/library/sonarqube:community}"
SCANNER_IMAGE="${SCANNER_IMAGE:-docker.io/sonarsource/sonar-scanner-cli:latest}"
DEFAULT_SOURCES="src/wp-content/themes/Dwight-School-Hanoi-Theme,src/wp-content/plugins/dwight-usp,src/wp-content/plugins/ekino-hubspot-form-embedded,src/wp-content/mu-plugins"
DEFAULT_EXCLUSIONS="**/vendor/**,**/node_modules/**,**/languages/**,**/*.min.js,**/*.min.css"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[sonar] $*"; }

# Runtime: SONAR_RUNTIME env wins. Otherwise use the first of podman/docker that is installed AND running.
RT="${SONAR_RUNTIME:-}"
if [ -z "$RT" ]; then
  installed=()
  for c in podman docker; do
    command -v "$c" >/dev/null 2>&1 || continue
    installed+=("$c")
    if "$c" info >/dev/null 2>&1; then RT="$c"; break; fi
  done
  if [ -z "$RT" ]; then
    [ ${#installed[@]} -gt 0 ] || die "neither podman nor docker is installed"
    hint=""
    for c in "${installed[@]}"; do
      [ "$c" = podman ] && hint="$hint podman machine start;"
      [ "$c" = docker ] && hint="$hint start Docker Desktop;"
    done
    die "installed (${installed[*]}) but none is running. Try:$hint"
  fi
fi

compose() { "$RT" compose -f "$COMPOSE_FILE" "$@"; }

write_compose() {
  mkdir -p "$STATE_DIR"
  cat > "$COMPOSE_FILE" <<YML
services:
  sonarqube:
    image: ${SONAR_IMAGE}
    container_name: ekino-sonarqube
    ports: ["127.0.0.1:${PORT}:9000"]
    environment:
      SONAR_ES_BOOTSTRAP_CHECKS_DISABLE: "true"
    volumes:
      - sonar_data:/opt/sonarqube/data
      - sonar_extensions:/opt/sonarqube/extensions
volumes:
  sonar_data:
  sonar_extensions:
YML
}

check_runtime() {
  "$RT" info >/dev/null 2>&1 || {
    [ "$RT" = podman ] && die "podman is not running. Run: podman machine start"
    die "$RT daemon is not running"; }
}

api() { curl -fsS -u "$1" "${@:2}"; }

wait_up() {
  log "waiting for SonarQube (first start takes about 1-2 min)..."
  for _ in $(seq 1 120); do
    s="$(curl -fsS "http://localhost:$PORT/api/system/status" 2>/dev/null || true)"
    case "$s" in *'"status":"UP"'*) return 0;; esac
    sleep 3
  done
  die "SonarQube did not become ready in time. Check: $RT logs ekino-sonarqube"
}

# Creates a random admin password (replacing admin/admin) and a user token, once.
bootstrap_auth() {
  [ -f "$CRED_FILE" ] && { # shellcheck disable=SC1090
    . "$CRED_FILE"; return 0; }
  log "first run: securing admin account and creating a token"
  ADMIN_PASS="$(openssl rand -hex 12)Aa1!"
  api "admin:admin" -X POST "http://localhost:$PORT/api/users/change_password" \
    -d "login=admin" -d "previousPassword=admin" --data-urlencode "password=$ADMIN_PASS" >/dev/null \
    || die "cannot change default admin password. If you changed it by hand, create $CRED_FILE with ADMIN_PASS=... and SONAR_TOKEN=..., or run: $0 reset"
  SONAR_TOKEN="$(api "admin:$ADMIN_PASS" -X POST "http://localhost:$PORT/api/user_tokens/generate" \
    -d "name=ekino-local-$(date +%s)" | python3 -I -c 'import sys,json;print(json.load(sys.stdin)["token"])')"
  umask 077
  printf 'ADMIN_PASS=%q\nSONAR_TOKEN=%q\n' "$ADMIN_PASS" "$SONAR_TOKEN" > "$CRED_FILE"
}

cmd_stop() { [ -f "$COMPOSE_FILE" ] || { log "nothing to stop"; return 0; }; compose stop >/dev/null 2>&1 || true; log "SonarQube stopped (data kept)"; }

cmd_status() {
  "$RT" ps --filter name=ekino-sonarqube --format '{{.Names}} {{.Status}}' 2>/dev/null | grep . || echo "not running"
  [ -f "$CRED_FILE" ] && echo "credentials: $CRED_FILE" || echo "credentials: none yet"
}

cmd_reset() {
  [ -f "$COMPOSE_FILE" ] && compose down -v >/dev/null 2>&1 || true
  rm -f "$CRED_FILE"; log "container, volumes and saved credentials removed"
}

usage() {
  cat <<'TXT'
Usage: sonar-scan.sh [scan] [options]     (also: stop | status | reset | help)

Project
  --project-dir DIR          repo root to scan (default: current dir)
  --key KEY                  project key        env SONARQUBE_PROJECT_KEY  (default: folder name)
  --name NAME                project name       env SONARQUBE_PROJECT_NAME (default: key)
Scope                         (comma-separated, relative to project dir; globs allowed in exclusions)
  --sources LIST             env SONAR_SOURCES            (default: Dwight own code)
  --exclusions LIST          env SONAR_EXCLUSIONS         (default: vendor, node_modules, languages, *.min.*)
  --coverage-exclusions LIST env SONAR_COVERAGE_EXCLUSIONS
  --cpd-exclusions LIST      env SONAR_CPD_EXCLUSIONS     (copy-paste detection)
Tests
  --tests LIST               env SONAR_TESTS              (default: tests, if it exists)
  --test-inclusions LIST     env SONAR_TEST_INCLUSIONS
  --coverage-report FILE     PHP clover report (default: coverage/clover.xml, if it exists)
Other
  --extra "-Dk=v -Dk2=v2"    env SONAR_EXTRA_CONFIG       extra scanner properties, passed as is
  --out FILE                 HTML report path             (default /tmp/<key>-sonar-report.html)
  --keep                     leave SonarQube running after the scan
  --no-wait                  do not wait for the quality gate
  --no-open                  do not open the HTML report
TXT
}

cmd_scan() {
  local project_dir="$PWD" key="${SONARQUBE_PROJECT_KEY:-}" name="${SONARQUBE_PROJECT_NAME:-}"
  local sources="${SONAR_SOURCES:-$DEFAULT_SOURCES}" exclusions="${SONAR_EXCLUSIONS:-$DEFAULT_EXCLUSIONS}"
  local cov_excl="${SONAR_COVERAGE_EXCLUSIONS:-}" cpd_excl="${SONAR_CPD_EXCLUSIONS:-}"
  local tests="${SONAR_TESTS:-}" test_incl="${SONAR_TEST_INCLUSIONS:-}" cov_report="" extra_cfg="${SONAR_EXTRA_CONFIG:-}"
  local out="" keep=0 wait_gate=1 open_report=1
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || [ "$1" = --keep ] || [ "$1" = --no-wait ] || [ "$1" = --no-open ] || die "option $1 needs a value"
    case "$1" in
      --project-dir) project_dir="$2"; shift 2;;
      --key) key="$2"; shift 2;;
      --name) name="$2"; shift 2;;
      --sources) sources="$2"; shift 2;;
      --exclusions) exclusions="$2"; shift 2;;
      --coverage-exclusions) cov_excl="$2"; shift 2;;
      --cpd-exclusions) cpd_excl="$2"; shift 2;;
      --tests) tests="$2"; shift 2;;
      --test-inclusions) test_incl="$2"; shift 2;;
      --coverage-report) cov_report="$2"; shift 2;;
      --extra) extra_cfg="$2"; shift 2;;
      --out) out="$2"; shift 2;;
      --keep) keep=1; shift;;
      --no-wait) wait_gate=0; shift;;
      --no-open) open_report=0; shift;;
      -h|--help) usage; return 0;;
      *) die "unknown option: $1 (see: help)";;
    esac
  done
  project_dir="$(cd "$project_dir" && pwd)"
  [ -n "$key" ] || key="$(basename "$project_dir" | tr 'A-Z ' 'a-z-' | tr -cd 'a-z0-9_.:-')"
  [ -n "$name" ] || name="$key"
  [ -n "$tests" ] || { [ -d "$project_dir/tests" ] && tests="tests"; }
  [ -n "$cov_report" ] || { [ -f "$project_dir/coverage/clover.xml" ] && cov_report="coverage/clover.xml"; }
  [ -z "$cov_report" ] || [ -f "$project_dir/$cov_report" ] || die "coverage report not found: $cov_report"

  # Fail early on a wrong scope instead of after a 2 minute start.
  IFS=',' read -ra paths <<<"$sources"
  for p in "${paths[@]}"; do [ -e "$project_dir/$p" ] || die "source path not found: $p (in $project_dir)"; done
  if [ -n "$tests" ]; then
    IFS=',' read -ra tpaths <<<"$tests"
    for p in "${tpaths[@]}"; do [ -e "$project_dir/${p#./}" ] || die "tests path not found: $p (in $project_dir)"; done
  fi

  check_runtime
  write_compose
  [ "$keep" = 1 ] || trap 'cmd_stop' EXIT
  log "runtime=$RT project=$key"
  log "scope: $sources"
  compose up -d >/dev/null
  wait_up
  bootstrap_auth

  local extra=()
  [ -z "$cov_report" ] || extra+=("-Dsonar.php.coverage.reportPaths=$cov_report")
  [ -z "$tests" ] || extra+=("-Dsonar.tests=$tests")
  [ -z "$test_incl" ] || extra+=("-Dsonar.test.inclusions=$test_incl")
  [ -z "$cov_excl" ] || extra+=("-Dsonar.coverage.exclusions=$cov_excl")
  [ -z "$cpd_excl" ] || extra+=("-Dsonar.cpd.exclusions=$cpd_excl")
  [ "$wait_gate" = 0 ] || extra+=("-Dsonar.qualitygate.wait=true")
  if [ -n "$extra_cfg" ]; then
    local words; read -ra words <<<"$extra_cfg"   # extra goes last so it can override
    extra+=("${words[@]}")
  fi

  local net="${SONAR_NETWORK:-$("$RT" inspect ekino-sonarqube --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null | awk '{print $1}')}"
  [ -n "$net" ] || net="ekino-sonar_default"
  log "running scanner container"
  # --userns=keep-id keeps file ownership readable on podman; harmless to omit on docker.
  local userns=(); [ "$RT" = podman ] && userns=(--userns=keep-id)
  set +e
  "$RT" run --rm ${userns[@]+"${userns[@]}"} \
    --network "$net" -e SONAR_HOST_URL="http://sonarqube:9000" -e SONAR_TOKEN="$SONAR_TOKEN" \
    -v "$project_dir:/usr/src:Z" "$SCANNER_IMAGE" \
    -Dsonar.projectKey="$key" -Dsonar.projectName="$name" \
    -Dsonar.sources="$sources" -Dsonar.exclusions="$exclusions" \
    -Dsonar.scm.disabled=true -Dsonar.sourceEncoding=UTF-8 ${extra[@]+"${extra[@]}"}
  local rc=$?
  set -e
  [ $rc -eq 0 ] || log "scanner exit code $rc (non-zero can mean a failed quality gate)"
  report "$key" "$open_report" "$out"
  log "dashboard: http://localhost:$PORT/dashboard?id=$key (only while the container runs; use --keep to leave it up)"
  return 0
}

report() {
  local key="$1" open_report="$2" out="${3:-}" url="http://localhost:$PORT/api" tmp here html
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  tmp="$(mktemp)"
  echo; echo "===== Issues for $key ====="
  api "$SONAR_TOKEN:" "$url/issues/search?componentKeys=$key&resolved=false&ps=500&facets=severities,types" >"$tmp" 2>/dev/null || true
  python3 -I "$here/report.py" issues "$tmp"
  echo "----- Quality gate -----"
  api "$SONAR_TOKEN:" "$url/qualitygates/project_status?projectKey=$key" >"$tmp" 2>/dev/null || true
  python3 -I "$here/report.py" gate "$tmp"
  rm -f "$tmp"

  html="${out:-/tmp/${key}-sonar-report.html}"
  if SONAR_TOKEN="$SONAR_TOKEN" python3 -I "$here/html-report.py" "http://localhost:$PORT" "$key" "$html" >/dev/null; then
    log "HTML report: $html"
    if [ "$open_report" = 1 ]; then
      if command -v open >/dev/null 2>&1; then open "$html"
      elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$html" >/dev/null 2>&1 || true
      else log "no opener found, open the file by hand"; fi
    fi
  else
    log "could not build the HTML report"
  fi
}

case "${1:-scan}" in
  scan) shift || true; cmd_scan "$@";;
  stop) check_runtime; cmd_stop;;
  status) cmd_status;;
  reset) check_runtime; cmd_reset;;
  -h|--help|help) usage;;
  --*) cmd_scan "$@";;
  *) die "unknown command: $1";;
esac
