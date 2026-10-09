# jira-assistance

A Claude Code skill to manage JIRA tickets from the chat: log work, add comments, change status, and edit fields.

## Features

- **Search** tickets with JQL (for example, your open tickets in a project).
- **Log work** with a time, an optional comment, and an optional start date/time (read in your JIRA profile timezone).
- **Comment** on a ticket, including a ready-made comment linking the open GitLab MR of the current branch (via `glab`).
- **Transition** a ticket to another status (picked by name).
- **Update** the summary, description, or assignee (`users` finds the accountId on JIRA Cloud).
- **Safe by default**: reads (`get`, `search`, `users`, `worklogs`, `transitions`) are pre-approved. Writes are not in the skill's allowed tools, so Claude Code asks permission, and the skill also shows each write and waits for your yes. In bypass/auto permission modes only the skill's own instruction remains, so keep a permission mode that prompts.
- Works with JIRA Cloud and JIRA Server / Data Center (REST API v2).

## Requirements

- [Claude Code](https://claude.com/claude-code)
- `bash`, `curl`, and [`jq`](https://jqlang.github.io/jq/) (`brew install jq`)
- [`glab`](https://gitlab.com/gitlab-org/cli) (optional, only for the "comment MR" flow)

## Installation

```bash
npx skills add ekinotech/skills@jira-assistance
```

Or install manually (use `.claude/skills/` in a project instead of `~/.claude/skills/` for a project-level install):

```bash
git clone https://github.com/ekinotech/skills.git
cp -R skills/jira-assistance ~/.claude/skills/jira-assistance
```

> The skill reads its credentials from `.env` inside its own folder, wherever it is installed.

## Configuration

Create `.env` in the skill folder (for example `~/.claude/skills/jira-assistance/.env`):

```bash
JIRA_BASE_URL=https://your-company.atlassian.net
JIRA_API_TOKEN=<your token>
# JIRA Cloud only: add your email. Omit it for Server/DC.
JIRA_EMAIL=you@company.com
```

Put comments on their own lines.

- **JIRA Cloud**: create an API token at <https://id.atlassian.com/manage-profile/security/api-tokens> and set `JIRA_EMAIL`.
- **Server / Data Center**: create a Personal Access Token in your JIRA profile and leave `JIRA_EMAIL` out.

Then protect the file:

```bash
chmod 600 ~/.claude/skills/jira-assistance/.env
```

The token is only read from this file. It is never passed on the command line and never printed. Do not paste it into the chat.

## Usage

Invoke the skill with `/jira-assistance <KEY-123> <what to do>`, or just ask in natural language.

```text
/jira-assistance list my open tickets in project PROJ
/jira-assistance PROJ-123 logwork 2h fix upload bug
/jira-assistance PROJ-123 logwork 1h 30m code review --started "2026-10-08 14:00"
/jira-assistance PROJ-123 comment MR ready for review
/jira-assistance PROJ-123 move to In Review
/jira-assistance PROJ-123 update assignee John Doe
```

If you do not give a ticket key, the skill tries the current git branch name and recent commit subjects.

## Script commands

The skill calls `scripts/jira.sh`, which you can also run directly:

```text
jira.sh get KEY
jira.sh search "JQL" [--max N]
jira.sh users "name"
jira.sh worklogs KEY
jira.sh logwork KEY "1h 30m" [--comment "text"] [--started "2026-10-08" | "2026-10-08 14:00"]
jira.sh comment KEY "text"
jira.sh transitions KEY
jira.sh transition KEY TRANSITION_ID
jira.sh update KEY [--summary "text"] [--description "text"] [--assignee "accountId (Cloud) | username (Server/DC)"]
```

## Notes

- Time formats: `30m`, `2h`, `1h 30m`, `1d`. The skill never invents a time; it asks if you do not give one.
- `--started "YYYY-MM-DD"` assumes 09:00. Do not add a timezone offset.
- `update --description` replaces the whole description, so the skill shows the old and new text first.
- Write actions cannot be undone from here. A wrong worklog or comment must be removed in the JIRA UI.
- On JIRA Cloud, `--assignee` needs an accountId (look it up with `users`). `search` uses `/search/jql` on Cloud and `/search` on Server/DC.
- Comments use JIRA wiki markup (REST API v2).

## License

MIT
