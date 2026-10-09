# Skills

Agent Skills developed and collected by the **Ekino Vietnam** team — reusable instruction packages for AI coding agents (Claude Code, and other tools supporting the [Agent Skills](https://agentskills.io) open standard).

## Available skills

- [`ekino-review-mr`](./ekino-review-mr) — review a GitLab merge request and optionally post findings back inline via `glab`.
- [`jira-assistance`](./jira-assistance) — log work, comment, change status, and update fields on a JIRA ticket.

## Usage

Each skill is a self-contained folder with a `SKILL.md`. Drop it into your agent's skills directory (e.g. `.claude/skills/`), or install with a compatible CLI:

```bash
npx skills add ekinotech/skills@ekino-review-mr
```

## License

MIT — see [LICENSE](./LICENSE).
