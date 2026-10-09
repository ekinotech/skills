# ekino-review-mr

Review a GitLab merge request for correctness, security, breaking changes, code quality, and AI-slop patterns. Then, if you want, post every finding back to GitLab as a **line-anchored discussion**, not a flat top-level comment.

## Key features

- **Line-anchored discussions, not flat comments.** Uses `glab` + the raw GitLab Discussions API to compute the exact diff `position` for each finding, so it lands as an inline comment on the exact file and line, the same way a human reviewer would. Only one flat post is allowed: the summary note.
- **Asks instead of guessing.** Questions the review can't answer from code, docs, or JIRA are posted as their own resolvable threads (on the code line when they are about specific code, as general MR threads otherwise), so the author can answer in place.
- **Three mandatory gates run before every verdict**, not just a code read:
  - *Duplicate/prior implementation*: searches merged/open MRs, issues, and git history so you don't review (or ship) work that's already done elsewhere.
  - *Project standards*: reads `CLAUDE.md` / `AGENTS.md` / `docs/code-standards.md` etc.; if none exist, generates a baseline `docs/code-standards.md` from the codebase instead of falling back to generic best practices.
  - *Strategic necessity*: reviews as a senior maintainer/owner, not just a linter: does this MR create real value, or is it correct-but-unneeded?
- **Anti-AI-slop checklist** (`references/anti-ai-slop.md`): a tuned list of dumping-ground files, parallel reimplementation, premature abstraction, defensive paranoia, catch-and-swallow, phantom test coverage, and more, with guidance on when *not* to flag so it doesn't turn into a witch hunt.
- **Plain review comments.** Simple English, no emoji, no em dashes, no bot signature or timestamp.
- **Severity-bucketed findings**: Critical (bugs/security/data loss) → Important (logic issues, structural slop) → Suggestion (style, micro slop) → clear verdict: Approve / Request changes / Comment.
- **Reviews the MR's real code, not your working tree.** Finds a local clone of the MR's project (current directory first, then a quick search of common project folders in `$HOME`), fetches the target branch and the MR head, and reads files at the MR's exact head SHA via `git show`. It never pulls, checks out, or stashes, so your branches and uncommitted work are untouched. Falls back to the GitLab files API when no clone is found or the fetch fails, and flags target-branch drift (files changed on the target since the MR branched).
- **Works from any directory with an MR URL.** All `glab` calls are scoped to the MR's own host and project, so reviewing an MR from another project never hits the current repo by mistake.
- **Fails safe.** If `glab` isn't installed or authenticated, the review stops and reports that instead of fabricating findings from just the MR title/description.

## Why install it

Reviewing MRs well requires more than reading a diff: catching duplicate work, checking against project-specific standards, judging strategic value, and spotting AI-generated code smells all take extra steps most reviews skip. This skill writes that checklist down so every review (by a human or an agent) covers the same ground, and turns findings into inline discussions GitLab shows natively instead of one wall-of-text comment nobody reads line by line.

## Requirements

- [`glab`](https://gitlab.com/gitlab-org/cli) (GitLab CLI) installed and authenticated: `glab auth login`.
- Pass an MR URL to review from any directory; a bare IID resolves against the current directory's repo. The skill runs `git fetch` in the matching local clone to get the MR head and the latest target branch; working trees and branches are never modified. To control where it looks for clones, set `EKINO_REVIEW_MR_SEARCH_ROOTS=~/work:~/oss` (default: `~/Projects`, `~/code`, `~/src`, `~/dev`, `~/workspace`, `~/git`, `~/repos`, and similar).
- Optional: JIRA ticket context. When the MR title, branch, or description contains a JIRA key, `scripts/fetch-jira-issue.sh` fetches the ticket (read-only, GET only) so the diff is checked against it. Credentials are read from env vars, then `<project>/.claude/.env`, `~/.claude/.env`, then `ekino-review-mr/.env`:
  ```
  JIRA_BASE_URL=https://your-company.atlassian.net
  # Cloud only: add your email. Omit it for a Server/Data Center personal access token.
  JIRA_EMAIL=you@company.com
  JIRA_API_TOKEN=<token>
  ```
  Without credentials the review still runs; it reports the keys it found and how to configure access.

## How to use

Invoke with an MR IID or URL:

```
/ekino-review-mr 123
```

Review-only (default): prints the full review to chat: summary, gate results, findings, verdict. Nothing is posted, edited, committed, or pushed. Exception: if the repo has no project standards doc, it creates a local `docs/code-standards.md` and reports the addition (does not push it).

Post the review back to GitLab, one line-anchored discussion per finding, one thread per unresolved question, plus one summary note:

```
/ekino-review-mr 123 --reply
```

- **`Fixes todo` label** → when at least one finding was posted, the MR gets a red `Fixes todo` label. A similar existing label (`Fix todo`, `Fixes to do`, `fixes-todo`, ...) is reused instead of creating a new one. Label errors (e.g. no permission to create labels) are reported but never stop the review.
- **Approve** verdict → runs `glab mr approve` after all findings are posted.
- **Request changes** → discussions are left open/unresolved (the blocking signal in GitLab); MR is not approved.
- **Comment** → suggestions + summary note only, no approve/revoke action. Also used instead of Approve when an open question could change the verdict.

There is no `--fix` mode. This skill reviews and posts. It does not fix code.

## Best practices

- Authenticate `glab` once per machine (`glab auth login`) before using `--reply`; the skill checks and fails safe (prints locally, warns) if auth is missing.
- Let it generate `docs/code-standards.md` the first time you run it in a repo with no standards doc, then commit that file yourself. Future reviews will use it instead of generic conventions.
- Treat Suggestion-level anti-slop findings as discussion starters, not blockers. The reference doc is tuned to avoid over-flagging (see "when NOT to flag").
- `--reply` is not idempotent in v1: re-running it on the same MR posts a fresh summary note, discussions, and question threads each time (the `Fixes todo` label is not duplicated). Don't re-run `--reply` on an MR you've already reviewed unless you want duplicate discussions.
- Review the "Mandatory gates" section of the output even on a clean diff. A technically correct MR can still fail the duplicate-work or strategic-necessity gate.

## Reference docs

- `references/anti-ai-slop.md`: full slop list, phrasing guide, stack-specific appendix (Go, React/TS, Tailwind, SQL).
- `references/gitlab-line-position-algorithm.md`: how diff hunks are parsed into GitLab's `position` object for the Discussions API.
- `references/project-rules-example.md`: worked example of project-specific compliance checking.
- `scripts/fetch-jira-issue.sh`: read-only JIRA issue fetcher (summary, type, status, description).
- `scripts/resolve-mr-code-context.sh`: finds the MR's local clone, fetches the MR head + target branch, and reports local or API mode.

## License

MIT. See the parent [LICENSE](../LICENSE).
