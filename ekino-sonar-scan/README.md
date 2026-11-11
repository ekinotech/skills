# ekino-sonar-scan

Run a local SonarQube Community scan with one command. The skill starts SonarQube in a container, scans the paths you choose, prints the issues, writes an HTML report, then stops the container.

Everything is local. Nothing is sent to a remote server and your repo is not modified.

## Install

```bash
npx skills add ekinotech/skills@ekino-sonar-scan
```

Or copy the `ekino-sonar-scan/` folder into your agent's skills directory (for Claude Code: `~/.claude/skills/`).

## Requirements

- podman or docker, installed and running. The script detects which one is running and uses it (podman first if both are).
- `curl`, `python3`, `openssl` (all standard on macOS).
- About 2 GB of free RAM for SonarQube. The first run pulls two images (`sonarqube:community`, `sonar-scanner-cli`).

If nothing is running, the script says what to start: `podman machine start` or Docker Desktop.

## Quick start

In Claude Code:

```
/ekino-sonar-scan
/ekino-sonar-scan --sources src/wp-content/themes/Dwight-School-Hanoi-Theme
```

Or directly:

```bash
bash ~/.claude/skills/ekino-sonar-scan/scripts/sonar-scan.sh scan --project-dir . --sources src/wp-content/plugins/dwight-usp
```

With no options it scans the Dwight own code (theme, `dwight-usp`, `ekino-hubspot-form-embedded`, `mu-plugins`), uses the folder name as the project key, and writes `/tmp/<key>-sonar-report.html`.

## Which project is scanned

The skill scans the folder where you started Claude Code (the session's working directory). `--project-dir` is only needed to scan a different folder.

```bash
cd ~/Documents/Projects/retail-on-brand
claude
> /ekino-sonar-scan --sources app,resources/js,routes,database   # scans retail-on-brand
```

What this means in practice:

- **Start Claude at the repo root**, not in a subfolder. Paths in `--sources`, `--tests` and `--coverage-report` are relative to that folder, and the default project key is its name (`retail-on-brand`).
- **Always pass `--sources` outside Dwight.** The default scope is the Dwight paths. In any other project those folders do not exist, so the script stops at once with `source path not found` and starts nothing.
- **`tests/` and `coverage/clover.xml`** are picked up on their own if they exist in that folder.
- **Another folder:** add `--project-dir /path/to/repo` (or use `cd` before running the script by hand).
- **Reports and state are not per project.** The HTML goes to `/tmp/<key>-sonar-report.html`, so different projects do not overwrite each other as long as their keys differ. SonarQube and its credentials are shared (`~/.ekino-sonar/`), and each project is a separate Sonar project, identified by its key.

## Options

Every option has an env var with the same name as in the CI `sonar-scanner` job, so you can reuse CI settings. A flag wins over its env var.

| Option | Env var | Default |
|---|---|---|
| `--project-dir DIR` | | current dir |
| `--key KEY` | `SONARQUBE_PROJECT_KEY` | folder name, lowercased |
| `--name NAME` | `SONARQUBE_PROJECT_NAME` | same as key |
| `--sources LIST` | `SONAR_SOURCES` | Dwight own code |
| `--exclusions LIST` | `SONAR_EXCLUSIONS` | `vendor`, `node_modules`, `languages`, `*.min.js`, `*.min.css` |
| `--coverage-exclusions LIST` | `SONAR_COVERAGE_EXCLUSIONS` | none |
| `--cpd-exclusions LIST` | `SONAR_CPD_EXCLUSIONS` | none (copy-paste detection) |
| `--tests LIST` | `SONAR_TESTS` | `tests`, if it exists |
| `--test-inclusions LIST` | `SONAR_TEST_INCLUSIONS` | none |
| `--coverage-report FILE` | | `coverage/clover.xml`, if it exists |
| `--extra "-Dk=v -Dk2=v2"` | `SONAR_EXTRA_CONFIG` | none. Added last, so it can override the rest |
| `--out FILE` | | `/tmp/<key>-sonar-report.html` |
| `--keep` | | stop the container after the scan |
| `--no-wait` | | wait for the quality gate |
| `--no-open` | | open the HTML report |

Lists are comma-separated and relative to the project dir. Source, tests and coverage paths are checked before anything starts, so a typo fails in a second, not after a two-minute server start.

Not supported on purpose: `sonar.host.url`, `sonar.token`, `qualitygate.wait` as a free value. The skill always uses its own local server and token. It never targets a remote Sonar.

Other commands:

```bash
sonar-scan.sh status   # is it running, are credentials saved
sonar-scan.sh stop     # stop a container left up by --keep (data is kept)
sonar-scan.sh reset    # delete container, volumes and credentials (erases scan history)
sonar-scan.sh help
```

## Examples

`--sources` takes only the list of paths. Do not write `sonar.sources=` in front of it (the script would look for a folder with that name and stop with `source path not found`).

### Dwight (WordPress, `~/Documents/Projects/dwighthanoi`)

Run from the repo root.

```
# Minimal: the default scope is already the Dwight own code
/ekino-sonar-scan

# Explicit scope, same four paths as sonar.sources
/ekino-sonar-scan --sources src/wp-content/themes/Dwight-School-Hanoi-Theme,src/wp-content/plugins/dwight-usp,src/wp-content/plugins/ekino-hubspot-form-embedded,src/wp-content/mu-plugins

# One plugin only, own key and report path
/ekino-sonar-scan --sources src/wp-content/plugins/dwight-usp --key dwight-usp --out ~/Desktop/usp.html
```

Full, with every option (Dwight):

```
/ekino-sonar-scan --project-dir ~/Documents/Projects/dwighthanoi --key dwighthanoi --name "Dwight Hanoi" --sources src/wp-content/themes/Dwight-School-Hanoi-Theme,src/wp-content/plugins/dwight-usp,src/wp-content/plugins/ekino-hubspot-form-embedded,src/wp-content/mu-plugins --exclusions "**/vendor/**,**/node_modules/**,**/languages/**,**/*.min.js,**/*.min.css" --coverage-exclusions "**/languages/**" --cpd-exclusions "**/assets/**" --tests tests --test-inclusions "**/*Test.php" --coverage-report coverage/clover.xml --extra "-Dsonar.php.version=8.2" --out /tmp/dwighthanoi-sonar-report.html --no-open
```

`--coverage-report` needs `make test-coverage` first, and fails early if the file is missing. Add `--keep` to leave SonarQube running, `--no-wait` to skip the quality gate wait.

Same thing without Claude Code:

```bash
bash ~/.claude/skills/ekino-sonar-scan/scripts/sonar-scan.sh scan \
  --project-dir ~/Documents/Projects/dwighthanoi \
  --sources src/wp-content/themes/Dwight-School-Hanoi-Theme,src/wp-content/plugins/dwight-usp,src/wp-content/plugins/ekino-hubspot-form-embedded,src/wp-content/mu-plugins
```

If port 9000 is taken by another container, prefix the command with `SONAR_PORT=9100`.

### ROB (Laravel, `~/Documents/Projects/retail-on-brand`)

ROB has no `src/` folder, so the CI default `./src` does not apply. Always pass `--sources`.

Minimal (scans `app`, `resources/js`, `routes`, `database`; `tests` is picked up on its own):

```
/ekino-sonar-scan --project-dir ~/Documents/Projects/retail-on-brand --sources app,resources/js,routes,database
```

Full, with the skill (`/ekino-sonar-scan`), every option, same values as the CI job:

```
/ekino-sonar-scan \
  --project-dir ~/Documents/Projects/retail-on-brand \
  --key retail-on-brand \
  --name "Retail On Brand" \
  --sources app,resources/js,routes,database \
  --exclusions '**/*.ico,**/*.jpg,**/*.png,**/*.svg,vendor/**,node_modules/**,public/**' \
  --coverage-exclusions 'database/**,routes/**,resources/js/**,app/Nova/**,app/Console/Commands/Datafix/**' \
  --cpd-exclusions 'database/migrations/**' \
  --tests tests \
  --test-inclusions '**/*Test.php' \
  --extra '-Dsonar.php.coverage.reportPaths=tests/reports/coverage.xml -Dsonar.php.tests.reportPath=tests/reports/junit.xml' \
  --out /tmp/retail-on-brand-sonar-report.html
```

Paste it into the Claude Code prompt. If your terminal splits the lines, put it on one line.

Full, plain bash (no Claude Code), same options:

```bash
bash ~/.claude/skills/ekino-sonar-scan/scripts/sonar-scan.sh scan \
  --project-dir ~/Documents/Projects/retail-on-brand \
  --key retail-on-brand \
  --name "Retail On Brand" \
  --sources app,resources/js,routes,database \
  --exclusions '**/*.ico,**/*.jpg,**/*.png,**/*.svg,vendor/**,node_modules/**,public/**' \
  --coverage-exclusions 'database/**,routes/**,resources/js/**,app/Nova/**,app/Console/Commands/Datafix/**' \
  --cpd-exclusions 'database/migrations/**' \
  --tests tests \
  --test-inclusions '**/*Test.php' \
  --extra '-Dsonar.php.coverage.reportPaths=tests/reports/coverage.xml -Dsonar.php.tests.reportPath=tests/reports/junit.xml' \
  --out /tmp/retail-on-brand-sonar-report.html
```

Or with the CI variable names, so you can reuse what is in the GitLab job:

```bash
cd ~/Documents/Projects/retail-on-brand
SONAR_SOURCES='app,resources/js,routes,database' \
SONAR_TESTS='tests' \
SONAR_EXCLUSIONS='**/*.ico,**/*.jpg,**/*.png,**/*.svg,vendor/**,node_modules/**,public/**' \
SONAR_COVERAGE_EXCLUSIONS='database/**,routes/**,resources/js/**,app/Nova/**,app/Console/Commands/Datafix/**' \
SONAR_CPD_EXCLUSIONS='database/migrations/**' \
SONAR_EXTRA_CONFIG='-Dsonar.php.coverage.reportPaths=tests/reports/coverage.xml -Dsonar.php.tests.reportPath=tests/reports/junit.xml' \
SONARQUBE_PROJECT_KEY=retail-on-brand SONARQUBE_PROJECT_NAME='Retail On Brand' \
  bash ~/.claude/skills/ekino-sonar-scan/scripts/sonar-scan.sh scan
```

The coverage and junit reports in `--extra` must exist before the scan. In ROB they come from the `test` job (`tests/reports/`). Without them the scan still runs, but coverage shows as empty.

### Other patterns

```bash
# Add any scanner property
sonar-scan.sh scan --extra "-Dsonar.php.version=8.2 -Dsonar.verbose=true"

# Keep SonarQube up to browse the dashboard on http://localhost:9000
sonar-scan.sh scan --keep
sonar-scan.sh stop
```

To include coverage in Dwight, run `make test-coverage` first. The skill picks up `coverage/clover.xml` on its own. In other projects, pass the report path with `--coverage-report` or `--extra`.

## What you get

- Terminal: issue counts by severity and type, the top 50 issues as `file:line message [rule]`, and the quality gate status.
- HTML: a single page at `/tmp/<key>-sonar-report.html` with the gate and its conditions, metric tiles, the full issue table and security hotspots. It opens automatically (`--no-open` to skip).
- Dashboard: `http://localhost:<port>/dashboard?id=<key>`, only while the container runs (use `--keep`).

## Files and state

```
ekino-sonar-scan/
  SKILL.md              instructions for Claude Code
  README.md             this file
  scripts/
    sonar-scan.sh       main entry point
    report.py           terminal summary
    html-report.py      HTML export
~/.ekino-sonar/
  docker-compose.sonar.yml   generated
  credentials.env            generated admin password and token. Do not share.
```

On the first run the script replaces the default `admin/admin` password with a random one and creates a token. Both are saved in `credentials.env`. Scan history lives in the container volumes (`ekino-sonar_*`) and survives `stop`.

## Troubleshooting

| Problem | Fix |
|---|---|
| `installed (...) but none is running` | `podman machine start`, or start Docker Desktop |
| `port is already allocated` | Another service uses the port. Run with `SONAR_PORT=9100` in front of the command |
| Scan fails right after "first run" | `sonar-scan.sh reset`, then run again |
| `cannot change default admin password` | You changed it by hand. Run `reset`, then scan again |
| Scanner cannot reach the server | The scanner joins the SonarQube container network. Check `docker ps` shows `ekino-sonarqube`, or set `SONAR_NETWORK` |
| Slow scanner on Apple Silicon | The scanner image is amd64 and runs emulated. It works, just slower |
| Results differ from the team's Sonar | A local server has its own default rules and quality gate. Use it to catch issues early, not to match the team report exactly |

## Notes

- The default sources are the Dwight own-code paths. For another project, always pass `--sources`.
- `SONAR_PORT`, `SONAR_IMAGE`, `SCANNER_IMAGE`, `SONAR_NETWORK` and `SONAR_STATE_DIR` are advanced overrides.
