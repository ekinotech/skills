# ekino-review-mr

Review a GitLab merge request for correctness, security, breaking changes, code quality, and AI-slop patterns — then, optionally, post every finding back to GitLab as a **line-anchored discussion**, not a flat top-level comment.

## Key features

- **Line-anchored discussions, not flat comments.** Uses `glab` + the raw GitLab Discussions API to compute the exact diff `position` for each finding, so it lands as an inline comment on the precise file+line — the same experience as a human reviewer. Only one flat post is allowed: the summary note.
- **Three mandatory gates run before every verdict**, not just a code read:
  - *Duplicate/prior implementation* — searches merged/open MRs, issues, and git history so you don't review (or ship) work that's already done elsewhere.
  - *Project standards* — reads `CLAUDE.md` / `AGENTS.md` / `docs/code-standards.md` etc.; if none exist, generates a baseline `docs/code-standards.md` from the codebase instead of falling back to generic best practices.
  - *Strategic necessity* — reviews as a senior maintainer/owner, not just a linter: does this MR create real value, or is it correct-but-unneeded?
- **Anti-AI-slop taxonomy** (`references/anti-ai-slop.md`) — a calibrated checklist for dumping-ground files, parallel reimplementation, premature abstraction, defensive paranoia, catch-and-swallow, phantom test coverage, and more, with guidance on when *not* to flag so it doesn't turn into a witch hunt.
- **Severity-bucketed findings**: Critical (bugs/security/data loss) → Important (logic issues, structural slop) → Suggestion (style, micro slop) → clear verdict: Approve / Request changes / Comment.
- **Fails safe.** If `glab` isn't installed or authenticated, the review stops and reports that instead of fabricating findings from just the MR title/description.

## Why install it

Reviewing MRs well requires more than reading a diff: catching duplicate work, checking against project-specific standards, judging strategic value, and spotting AI-generated code smells all take deliberate steps most reviews skip. This skill encodes that checklist so every review — human or agent-driven — covers the same ground, and turns findings into inline discussions GitLab renders natively instead of one wall-of-text comment nobody reads line by line.

## Requirements

- [`glab`](https://gitlab.com/gitlab-org/cli) (GitLab CLI) installed and authenticated: `glab auth login`.
- Run from within the git repository the MR belongs to (the skill uses `glab api`/`glab mr` against the current project).
- Optional — JIRA ticket context. When the MR title, branch, or description contains a JIRA key, `scripts/fetch-jira-issue.sh` fetches the ticket (read-only, GET only) so the diff is checked against it. Credentials are read from env vars, then `<project>/.claude/.env`, `~/.claude/.env`, then `ekino-review-mr/.env`:
  ```
  JIRA_BASE_URL=https://your-company.atlassian.net
  JIRA_EMAIL=you@company.com   # Cloud only; omit for Server/Data Center personal access token
  JIRA_API_TOKEN=<token>
  ```
  Without credentials the review still runs; it reports the keys it found and how to configure access.

## How to use

Invoke with an MR IID or URL:

```
/ekino-review-mr 123
```

Review-only (default): prints the full review to chat — summary, gate results, findings, verdict. Nothing is posted, edited, committed, or pushed. Exception: if the repo has no project standards doc, it creates a local `docs/code-standards.md` and reports the addition (does not push it).

Post the review back to GitLab, one line-anchored discussion per finding plus one summary note:

```
/ekino-review-mr 123 --reply
```

- **Approve** verdict → runs `glab mr approve` after all findings are posted.
- **Request changes** → discussions are left open/unresolved (the blocking signal in GitLab); MR is not approved.
- **Comment** → suggestions + summary note only, no approve/revoke action.

There is no `--fix` mode — this skill reviews and posts, it does not remediate.

## Best practices

- Authenticate `glab` once per machine (`glab auth login`) before using `--reply`; the skill checks and fails safe (prints locally, warns) if auth is missing.
- Let it generate `docs/code-standards.md` the first time you run it in a repo with no standards doc, then commit that file yourself — future reviews will use it instead of generic conventions.
- Treat Suggestion-level anti-slop findings as discussion starters, not blockers — the reference doc explicitly calibrates against over-flagging (see "when NOT to flag").
- `--reply` is not idempotent in v1: re-running it on the same MR posts a fresh summary note and fresh discussions each time. Don't re-run `--reply` on an MR you've already reviewed unless you want duplicate discussions.
- Review the "Mandatory gates" section of the output even on a clean diff — a technically-correct MR can still fail the duplicate-work or strategic-necessity gate.

## Reference docs

- `references/anti-ai-slop.md` — full slop taxonomy, phrasing guide, stack-specific appendix (Go, React/TS, Tailwind, SQL).
- `references/gitlab-line-position-algorithm.md` — how diff hunks are parsed into GitLab's `position` object for the Discussions API.
- `references/project-rules-example.md` — worked example of project-specific compliance checking.
- `scripts/fetch-jira-issue.sh` — read-only JIRA issue fetcher (summary, type, status, description).

## License

MIT — see the parent [LICENSE](../LICENSE).
