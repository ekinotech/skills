---
name: ekino-sonar-scan
description: "Run a local SonarQube Community scan on a project. Starts a SonarQube container, scans the chosen paths with the scanner container, prints issues and the quality gate, then stops the container. Scope (paths) and project key are configurable."
user-invocable: true
when_to_use: "Invoke when the user wants to run Sonar locally, check Sonar issues before pushing, scan specific folders or plugins, or stop/reset the local SonarQube. Triggers: 'sonar scan', 'run sonar local', 'check sonar', 'scan theme/plugin with sonar'."
category: utilities
keywords: [sonar, sonarqube, community, scan, code quality, podman, docker, local]
argument-hint: "[scan|stop|status|reset|help] [--sources a,b] [--key KEY] [--name NAME] [--exclusions x,y] [--coverage-exclusions x] [--cpd-exclusions x] [--tests dir] [--test-inclusions x] [--extra \"-Dk=v\"] [--out FILE] [--keep] [--no-open]"
allowed-tools:
  - Bash(bash "${CLAUDE_SKILL_DIR}/scripts/sonar-scan.sh" *)
---

# Local Sonar scan

Arguments: `$ARGUMENTS`

Runs SonarQube Community in a container only for the duration of the scan. Everything is local. Nothing is posted anywhere and the project files are never modified. State (compose file, generated admin password, token) lives in `~/.ekino-sonar/`, outside any repo.

## Steps

1. **Resolve options.** Map the user's words and `$ARGUMENTS` to script options. Full list and defaults: `README.md`, or run the script with `help`.
   - Scope: `--sources` (comma-separated, relative to the project dir; if the user names folders like "only the theme", map them to real paths with `ls`), `--exclusions`, `--coverage-exclusions`, `--cpd-exclusions`.
   - Project: `--project-dir` (repo root, default current dir), `--key`, `--name`.
   - Tests and coverage: `--tests`, `--test-inclusions`, `--coverage-report` (clover.xml is picked up on its own if it exists).
   - Other: `--extra "-Dk=v"` for any scanner property, `--out`, `--keep`, `--no-wait`, `--no-open`.
   - The same settings can come from env vars (`SONAR_SOURCES`, `SONAR_EXCLUSIONS`, `SONAR_COVERAGE_EXCLUSIONS`, `SONAR_CPD_EXCLUSIONS`, `SONAR_TESTS`, `SONAR_TEST_INCLUSIONS`, `SONAR_EXTRA_CONFIG`, `SONARQUBE_PROJECT_KEY`, `SONARQUBE_PROJECT_NAME`), same names as the CI job. A flag wins over its env var.
   - With no scope given, the script scans the Dwight own code. For any other project, always pass `--sources`.
   - Only ask if something is truly ambiguous. Otherwise do not ask.
2. **Run the scan** (foreground, it takes 2 to 5 minutes the first time because of image pulls and server start; use a long timeout, e.g. 600000 ms):
   ```bash
   bash "${CLAUDE_SKILL_DIR}/scripts/sonar-scan.sh" scan --project-dir <dir> --sources <paths> [--key <key>]
   ```
   The script starts the container, waits until ready, creates a token on first run, runs the scanner container, prints issues, writes an HTML report to `/tmp/<key>-sonar-report.html` (and opens it unless `--no-open`), then stops the container on exit (even on failure). Add `--keep` only if the user wants to browse the dashboard afterward.
3. **Report to the user:** the HTML report path, quality gate status, issue counts by severity and type, and the top issues as `file:line message [rule]`. Group by the scope the user asked about. Do not dump all 50 lines if there are only a few that matter. Say plainly if the scan failed and show the error line.
4. **Other commands:**
   - `status`: is the container running, and are credentials saved.
   - `stop`: stop a container left running by `--keep`. Data is kept.
   - `reset`: delete container, volumes and saved credentials (a full clean slate). Confirm with the user first, since it erases scan history.

## Rules

- Never print the contents of `~/.ekino-sonar/credentials.env`. The token and admin password are secrets.
- Do not edit the repo to add Sonar files. This skill does not need `sonar-project.properties` (settings are passed as scanner arguments). If the repo already has one, command-line values here take priority.
- Local only. Never point this at a remote Sonar server, and never run it against a remote machine.
- If the runtime is not running, the script says how to start it (for podman: `podman machine start`). Relay that to the user, do not try to start VMs yourself.
- A local Community instance has its own default rule set and quality gate. Results can differ from the team's Sonar server. Say so when comparing with an existing report.
- If a Sonar issue is a real finding, suggest the fix, but do not apply it unless asked.

## Environment overrides

The runtime (podman or docker) is detected on its own: the first one installed and running. `SONAR_PORT` (default 9000; set it if another service uses 9000), `SONAR_IMAGE`, `SCANNER_IMAGE`, `SONAR_NETWORK`, `SONAR_STATE_DIR`.

The server URL and token are never configurable: the skill only targets its own local server.
