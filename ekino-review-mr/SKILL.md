---
name: ekino-review-mr
description: "Review a GitLab merge request for correctness, security, breaking changes, code quality, and AI-slop patterns. Posts every finding back to GitLab as a line-anchored discussion via glab + the GitLab Discussions API — never a flat top-level comment."
user-invocable: true
when_to_use: "Invoke to review a GitLab MR by IID/URL, optionally post the review back to GitLab with every finding pinned to its exact file+line."
category: utilities
keywords: [mr, merge request, review, gitlab, glab, inline comment, discussion, position, anti-slop, ai-slop]
argument-hint: "<MR IID or URL> [--reply]"
allowed-tools:
  - Bash(command -v *)
  - Bash(printf *)
  - Bash(awk *)
  - Bash(sed *)
  - Bash(glab mr view *)
  - Bash(glab mr diff *)
  - Bash(glab mr note *)
  - Bash(glab mr approve *)
  - Bash(glab mr revoke *)
  - Bash(glab mr checkout *)
  - Bash(glab ci status *)
  - Bash(glab api *)
  - Bash(glab auth status *)
  - Bash(git fetch *)
  - Bash(git log *)
  - Bash(git diff *)
  - Bash(git status *)
  - Bash(date *)
  - Bash(mkdir *)
  - Read
  - Write
  - Glob
  - Grep
metadata:
  author: duc.nguyen
  version: "1.0.0"
---

# Review Merge Request

Review MR `$ARGUMENTS` in this repository.

## Modes

- **Review-only** (default): review the MR and print findings to chat. Do not post anything to GitLab, edit, commit, or push. Exception: if no project standards doc exists, create a local `docs/code-standards.md` from a codebase scan, report the change, and do not push it.
- **Reply** (`--reply`): after the review, post it back to the MR — one flat summary note plus one line-anchored discussion per finding. See "Posting the review" below. There is no `--fix` mode in v1; this skill only reviews and posts, it does not remediate.

## Argument parsing

Derive `MR_REF` from `$ARGUMENTS`: pick the last `http(s)://` token if present, else the first bare/`!`-prefixed numeric IID token, ignoring `--reply` and any surrounding natural-language words (e.g. "review MR ... --reply"):

```
!`MR_REF="$(printf '%s\n' "$ARGUMENTS" | awk '{ ref=""; for (i = 1; i <= NF; i++) { tok=$i; if (tok == "--reply") continue; if (tok ~ /^https?:\/\//) { ref=tok } else if (ref == "" && tok ~ /^!?[0-9]+$/) { ref=tok } } print ref }')" && printf 'MR_REF=%s\n' "$MR_REF"`
```

If `MR_REF` prints empty, stop and ask the user for a valid MR IID or URL — do not guess.

Detect flag: `--reply` present → reply mode active (post to GitLab).

## Context

MR metadata (includes `diff_refs` needed for posting later):
```
!`MR_REF="$(printf '%s\n' "$ARGUMENTS" | awk '{ ref=""; for (i = 1; i <= NF; i++) { tok=$i; if (tok == "--reply") continue; if (tok ~ /^https?:\/\//) { ref=tok } else if (ref == "" && tok ~ /^!?[0-9]+$/) { ref=tok } } print ref }')"; MR_HOST="$(printf '%s\n' "$MR_REF" | sed -nE 's#^https?://([^/]*)/.*#\1#p')"; if ! command -v glab >/dev/null 2>&1; then echo "glab CLI not installed — install: https://gitlab.com/gitlab-org/cli#installation"; elif [ -n "$MR_HOST" ] && ! glab auth status --hostname "$MR_HOST" >/dev/null 2>&1; then echo "glab not authenticated for $MR_HOST — run: glab auth login --hostname $MR_HOST"; elif [ -z "$MR_HOST" ] && ! glab auth status >/dev/null 2>&1; then echo "glab not authenticated — run: glab auth login"; else glab api "merge_requests/$MR_REF" 2>/dev/null || glab mr view "$MR_REF" -F json; fi`
```

MR diff (raw, for correctness/security/anti-slop analysis and later for line-position parsing):
```
!`MR_REF="$(printf '%s\n' "$ARGUMENTS" | awk '{ ref=""; for (i = 1; i <= NF; i++) { tok=$i; if (tok == "--reply") continue; if (tok ~ /^https?:\/\//) { ref=tok } else if (ref == "" && tok ~ /^!?[0-9]+$/) { ref=tok } } print ref }')"; MR_HOST="$(printf '%s\n' "$MR_REF" | sed -nE 's#^https?://([^/]*)/.*#\1#p')"; if ! command -v glab >/dev/null 2>&1; then echo "glab CLI not installed — install: https://gitlab.com/gitlab-org/cli#installation"; elif [ -n "$MR_HOST" ] && ! glab auth status --hostname "$MR_HOST" >/dev/null 2>&1; then echo "glab not authenticated for $MR_HOST — run: glab auth login --hostname $MR_HOST"; elif [ -z "$MR_HOST" ] && ! glab auth status >/dev/null 2>&1; then echo "glab not authenticated — run: glab auth login"; else glab mr diff "$MR_REF" --raw; fi`
```

Pipeline/CI status:
```
!`if ! command -v glab >/dev/null 2>&1; then echo "glab CLI not installed — install: https://gitlab.com/gitlab-org/cli#installation"; elif ! glab auth status >/dev/null 2>&1; then echo "glab not authenticated — run: glab auth login"; else glab ci status 2>/dev/null || echo "No pipeline found"; fi`
```

If either metadata or diff block above prints a "glab CLI not installed"/"glab not authenticated" message instead of JSON/diff content, stop here and report that to the user — the review cannot proceed without MR data. Do not fabricate findings from the MR title/description alone.

## Instructions

Perform a thorough code review of this MR. Follow these steps.

### 1. Understand the MR
- Read the MR title, description, and linked issues.
- Understand the intent and scope of the changes.
- Compare stated scope vs the diff's actual size — a wide gap is itself a signal (see anti-slop reference).
- Extract 3-7 concrete search terms from title/description/changed API names/routes/files. Use them for duplicate and prior-work checks.

### 2. Run mandatory gates

Run these gates before final verdict. They can produce findings even when the code itself is correct.

**Duplicate / prior implementation gate**
- Check whether the same outcome was already implemented, merged, opened, or rejected by someone else.
- Search GitLab MRs/issues and git history with the extracted terms:
  - `glab api "merge_requests?scope=all&search=<terms>"`
  - `glab api "issues?scope=all&search=<terms>"`
  - `git log --all --grep="<terms>" --oneline --decorate -20`
- Exclude the current MR from duplicate results before judging overlap.
- Grep the codebase for touched symbols, routes, command names, config keys, or UI labels that may indicate existing implementation.
- If a merged MR already satisfies the outcome, mark an **Important** duplicate finding and request closing or retargeting.
- If an open MR overlaps materially, mark **Important** unless this MR is clearly the chosen successor and explains why.

**Project standards gate**
- Prefer existing project docs in this order: `CLAUDE.md`, `AGENTS.md`, `docs/code-standards.md`, `docs/system-architecture.md`, `docs/project-overview-pdr.md`, `docs/project-roadmap.md`, then nearby package/module docs.
- If no standards doc exists, scan the codebase for naming, structure, package manager, test commands, error handling, file-size limits, i18n, security, and architecture patterns. Create `docs/code-standards.md` with a concise baseline before continuing. Leave it local and report it — do not push it as part of this skill.
- Check the MR against the discovered or generated standards. Do not rely on generic best practices when project standards are available.
- If standards conflict or are stale, cite the conflict and use current code plus repo docs as evidence.

**Strategic necessity gate**
- Review as the project owner/senior maintainer, not only as a code reviewer.
- Ask whether the MR creates clear value: user outcome, roadmap alignment, security improvement, maintainer toil reduction, reliability, or compliance.
- If the MR is correct but unnecessary, duplicates roadmap work, or adds maintenance burden without clear value, mark an **Important** product-risk finding.
- If value depends on a business call the code cannot answer, list it as an unresolved question at the end.

### 3. Analyze the diff
- Read every changed file carefully.
- For modified files, read the full file (not just the diff) to understand surrounding context.
- Check if the changes align with the stated MR purpose.

### 4. Check for issues

**Correctness**: logic errors, off-by-one, nil/null dereference, missing error handling, race conditions, unhandled edge cases.

**Security**: injection (SQL, XSS, command, SSRF, path traversal), hardcoded secrets/credentials, missing input validation at system boundaries, authentication/authorization gaps.

**Breaking changes**: API contract changes, database schema changes without migrations, config format changes without backwards compatibility, removed/renamed exports/public interfaces.

**Code quality (anti-slop)** — load `references/anti-ai-slop.md` when ANY of: diff adds >300 lines, OR ≥2 inline anti-slop flags fire (dumping-ground new file, parallel reimplementation, premature abstraction, defensive paranoia, catch-and-swallow, phantom coverage, diff size mismatch with stated scope, unrelated files touched), OR you cannot confidently judge genuine YAGNI vs slop. The reference is VCS-agnostic — same taxonomy as GitHub PR review.

**Project-specific compliance**: use the standards loaded/generated by the Project standards gate. See `references/project-rules-example.md` for a worked example.

**Testing**: new code paths covered, existing tests still pass, edge cases tested, watch for phantom coverage.

### 5. Summarize findings

Present your review as:

**Summary**: 1-2 sentence overview of what the MR does.

**Risk level**: Low / Medium / High.

**Mandatory gates**: Duplicate/prior implementation | Project standards | Strategic necessity — each: clear/found/missing as applicable.

**Findings**: severity-bucketed list. For each finding, capture enough to anchor it later: **file path** and the **specific line(s)** it applies to (or the closest defensible anchor line — see step 6). This is required, not optional — a finding without a concrete file+line cannot be posted per this skill's contract.
- **Critical**: Must fix before merge (bugs, security, data loss)
- **Important**: Should fix (logic issues, missing validation, *structural* AI slop)
- **Suggestion**: Nice to have (style, minor improvements, *micro* AI slop)

**Verdict**: **Approve** (no critical/important issues) | **Request changes** (critical/important issues exist) | **Comment** (suggestions only).

## Posting the review (`--reply`)

If `$ARGUMENTS` contains `--reply`, post the review to GitLab after the analysis above. **Every finding becomes its own line-anchored discussion. The only flat, non-anchored post allowed is the single summary note.** Full algorithm, JSON payload shape, and failure handling: `references/gitlab-line-position-algorithm.md`. Read it before posting — do not improvise the position math.

### 1. Pre-flight
```bash
command -v glab >/dev/null 2>&1 || { echo "glab CLI not installed — install: https://gitlab.com/gitlab-org/cli#installation — printing review locally"; exit 0; }
glab auth status >/dev/null 2>&1 || { echo "glab not authenticated — run: glab auth login — printing review locally"; exit 0; }
```
On failure, fall back to printing the review in chat and warn the user — never fail the whole skill.

### 2. Compute diff_refs and the line-position index
- Fetch `diff_refs` (`base_sha`, `start_sha`, `head_sha`) from the MR metadata JSON already fetched in Context.
- Parse the raw diff (also already fetched) into a per-file `{old_line, new_line}` index per `references/gitlab-line-position-algorithm.md` step 2.

### 3. Post the summary note (the one allowed flat post)
```bash
glab mr note "$MR_REF" -m "$(cat <<'EOF'
<summary + mandatory gate results + risk level + verdict>

*Posted by ekino-review-mr at <ISO-8601 UTC timestamp>*
EOF
)"
```
Use `date -u +"%Y-%m-%dT%H:%M:%SZ"` for the timestamp.

### 4. Post every finding as a line-anchored discussion
For each finding from step 5 above:
1. Resolve its `(file, old_line?, new_line?)` from the index built in step 2. Apply the anchor rule from the reference doc if the finding doesn't map to one obvious line — always pick the closest defensible line, never skip posting it inline.
2. Write the JSON payload (`body` + `position`) to a scratch file.
3. `glab api --method POST "projects/:id/merge_requests/$MR_REF/discussions" --input <payload-file>`
4. On `400`/`422`: re-fetch `diff_refs`, re-parse the diff once, retry. If it still fails, record it as a posting failure (file, finding, error) — do not fall back to a flat comment for that finding.

### 5. Verdict-dependent action
- **Approve**: `glab mr approve "$MR_REF"` after all findings (there should be none Critical/Important) are posted.
- **Request changes**: do not approve. Leave the inline discussions unresolved — that is the blocking signal in GitLab. Do not call `glab mr approve`.
- **Comment**: no approve/revoke action; inline discussions (Suggestions) and the summary note are enough.

### 6. Idempotency
v1 does not dedupe. Re-running `ekino-review-mr <MR_REF> --reply` posts a fresh summary note and fresh discussions each time.

## Final output

After the mode completes, report to chat:
- Verdict (Approve / Request changes / Comment)
- Duplicate/prior implementation, project standards, strategic necessity results
- If `--reply` ran: number of discussions posted, any posting failures (file/finding/error), whether the summary note posted or fell back to local print
- Unresolved questions, if any
