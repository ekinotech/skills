---
name: jira-assistance
description: "Log work, comment, change status, and update fields on a JIRA ticket. Use when the user asks to logwork, log time, update a ticket, add a JIRA comment, or move a ticket to another status."
user-invocable: true
when_to_use: "Invoke when the user wants to log time on a JIRA ticket, add a comment, transition a ticket, or edit its summary/description/assignee."
argument-hint: "<KEY-123> <what to do, e.g. logwork 2h fix upload bug>"
allowed-tools:
  - Bash(bash ${CLAUDE_SKILL_DIR}/scripts/jira.sh get *)
  - Bash(bash ${CLAUDE_SKILL_DIR}/scripts/jira.sh search *)
  - Bash(bash ${CLAUDE_SKILL_DIR}/scripts/jira.sh users *)
  - Bash(bash ${CLAUDE_SKILL_DIR}/scripts/jira.sh worklogs *)
  - Bash(bash ${CLAUDE_SKILL_DIR}/scripts/jira.sh transitions *)
  - Bash(glab mr view *)
  - Bash(glab mr list *)
---

# JIRA logwork and update

Request: `$ARGUMENTS`

Script: `bash ${CLAUDE_SKILL_DIR}/scripts/jira.sh <command> KEY ...` (needs `jq`).
Credentials are read only from `.env` in the skill directory (`${CLAUDE_SKILL_DIR}/.env`) (`JIRA_BASE_URL`, `JIRA_API_TOKEN`, and `JIRA_EMAIL` for JIRA Cloud only; leave it out for Server/Data Center). If the output starts with `JIRA_CREDENTIALS_MISSING`, show the setup lines to the user and stop. Never ask for the token in chat and never print it.

## Steps

1. **Find the ticket key.** Use the key in the request. If none, try `git branch --show-current` and recent `git log` subjects (pattern `[A-Z][A-Z0-9_]+-[0-9]+`). If still unclear, ask the user.
2. **Read first.** Run `get KEY` so the user sees the summary and current status. Use `worklogs KEY` before logging, to avoid a duplicate entry for the same day and work.
3. **Plan the action** from the request:
   - List/search tickets ("my tickets in project X"): `search "<JQL>" [--max N]`, e.g. `project = KEY AND assignee = currentUser() AND resolution = Unresolved ORDER BY updated DESC`. The project key may differ from what the user says; on "project does not exist", ask the user for the right key. Read only, no confirmation.
   - Log work: `logwork KEY "<time>" [--comment "$(cat <<'EOF' ... EOF)"] [--started "<YYYY-MM-DD[ HH:MM]>"]`. Time is `30m`, `2h`, `1h 30m`, `1d`. If the user gave no time, ask. If no comment, build one from the request or recent commits. Default start is now. For another day or time, pass `--started "YYYY-MM-DD"` (09:00 assumed) or `--started "YYYY-MM-DD HH:MM"`. The script reads it in the timezone of the JIRA profile (what the JIRA UI shows), not the machine timezone, so do not add an offset. Tell the user which timezone was used.
   - **Passing free text** (comments, worklog comments, summary, description): MR titles, commit subjects, and ticket text can contain backticks, `$(...)`, `$VAR`, or quotes, which a double-quoted shell argument would execute or expand. Always pass such text through a single-quoted heredoc: `bash ${CLAUDE_SKILL_DIR}/scripts/jira.sh comment KEY "$(cat <<'EOF'` then the text, then `EOF` and `)"`. Never put the text inside double quotes directly.
   - Comment: `comment KEY "$(cat <<'EOF' ... EOF)"` (see above).
   - Comment with an MR link (the user says "comment MR", "báo MR", "MR ready for review"): get the MR from the current repo, never guess it.
     1. If the user gave an MR number or URL, use it. Otherwise find the MR of the current branch: `glab mr list --source-branch "$(git branch --show-current)"`.
     2. Run `glab mr view <iid> -F json` and read `title`, `web_url`, `state`, `source_branch`. If no MR or several match, say so and ask.
     3. Build a short comment in JIRA wiki markup with the link as `[!<iid> <title>|<web_url>]` (remove `|`, `[`, `]` from the title so the link does not break), plus the user's note if any (for example "Ready for review"). Example: `MR ready for review: [!2957 feat(upload): upload documents by zip file|https://gitlab.example/.../merge_requests/2957]`.
     4. Show the final text, confirm, then run `comment` with the heredoc form. Only link MRs that are open, unless the user says otherwise.
   - Change status: run `transitions KEY`, pick the matching id by name, then `transition KEY <id>`. If the name is ambiguous, ask.
   - Edit fields: `update KEY [--summary ..] [--description ..] [--assignee ..]`. For `--assignee` on JIRA Cloud, first run `users "<name>"` (read only) to get the accountId and show the match to the user; on Server/DC the username works. `--description` replaces the whole text, so show the old text and the new text.
4. **Confirm before any write.** Show the exact action (ticket, time, date, comment text, or new values) and wait for a yes from the user. Reads (`get`, `search`, `worklogs`, `transitions`) need no confirmation. Do not batch several writes behind one confirmation unless the user asked for all of them.
5. **Run the write command**, then report the result in one or two lines. On an error (401/403/404, bad time format), say so plainly and do not retry blindly.

## Rules

- Write commands (`logwork`, `comment`, `transition`, `update`) change a shared system and cannot be undone from here (a wrong worklog or comment must be removed in the JIRA UI). Always confirm first.
- Do not invent time. Log only what the user states.
- Keep comments short and factual. Reply in the user's language (Vietnamese or English), but write the JIRA comment in the language the user gives or the ticket already uses.
