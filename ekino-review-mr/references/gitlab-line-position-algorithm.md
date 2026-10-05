# GitLab Line-Position Algorithm

How `ekino-review-mr` turns a finding (file + approximate location) into a
GitLab Discussions API call that lands as a real inline comment on the exact
diff line, never a flat top-level note.

## Why this needs its own logic

`glab` has no CLI command for posting a line-anchored comment. `glab mr note`
only posts a flat note on the MR overview. The only way to anchor a comment to
a line is the raw REST Discussions endpoint, which requires a `position`
object that GitLab validates strictly: wrong SHA or wrong line number → `400`.

## 1. Get `diff_refs`

```bash
glab mr view <MR_SEL> -F json | jq '.diff_refs'
# { "base_sha": "...", "head_sha": "...", "start_sha": "..." }
```

Fetch this once per review run. If the MR is updated (new commits pushed)
mid-review, re-fetch before posting, because a stale `head_sha` is rejected.

## 2. Get the raw diff and build a per-file line index

```bash
glab mr diff <MR_SEL> --raw
```

Parse it as a standard unified diff. For each file's hunks:

- Hunk header `@@ -old_start,old_count +new_start,new_count @@` seeds two
  counters: `old_line = old_start`, `new_line = new_start` (both decremented
  by 1 before the loop so the first line increment lands correctly).
- For each following line in the hunk, before consuming it:
  - `+` (added): this line's position is `new_line` only (no `old_line`).
    Increment `new_line`.
  - `-` (removed): this line's position is `old_line` only (no `new_line`).
    Increment `old_line`.
  - ` ` (context/unchanged): this line's position has **both** `old_line`
    and `new_line`. Increment both.
- Build a map: `file_path -> [{content, old_line, new_line}, ...]` covering
  every line touched or shown in the diff. This is the only set of lines
  GitLab will accept a position for. You cannot comment on a line the diff
  doesn't show.

Do this parse yourself (Read the raw diff text and walk it line by line).
Do not guess line numbers from the final-file content. They must match the
diff's own numbering exactly, or the API rejects the position.

## 3. Anchor every finding to one line in that index

For a finding tied to a specific changed line, use that line directly
(prefer `new_line`, which comments on the new version of the file, unless
the finding is specifically about a removed line, in which case use
`old_line` with no `new_line`).

For a finding that doesn't map to one obvious line (spans a block, concerns
a whole new file, or is a design/strategic finding with no natural line),
pick the single most relevant anchor and explain the fuller scope in the
comment body:

- Whole new file → its first line in the diff (usually `@@ -0,0 +1 ...`'s
  first `+` line).
- A block/function that's the actual problem → the line that starts the
  block (e.g. the function signature, the `if` that's missing a check).
- A missing-tests / phantom-coverage finding → the line in the source diff
  that introduces the untested behavior (not the test file, since often
  there's no test file to anchor to).

Never post a finding as a plain top-level note because it doesn't cleanly
fit one line. Pick the closest fitting line. That is the rule.

## 4. Build the request body as a file, not inline flags

`glab api`'s `-f/--raw-field` nested-key syntax for objects (`position[...]`)
is not documented in `glab api --help` and is unreliable to depend on. Write
the full JSON payload to a file and POST it with `--input`, which is
deterministic and avoids shell-quoting/nesting issues entirely:

```json
{
  "body": "**Important:** missing null check before this value is used.\n\nSay why it matters here.",
  "position": {
    "position_type": "text",
    "base_sha": "<diff_refs.base_sha>",
    "start_sha": "<diff_refs.start_sha>",
    "head_sha": "<diff_refs.head_sha>",
    "old_path": "src/foo.ts",
    "new_path": "src/foo.ts",
    "new_line": 42
  }
}
```

For a finding on a removed line, use `"old_line": 42` instead of
`"new_line"`, and drop `new_line`.

Post it:

```bash
glab api --hostname <HOST> --method POST "projects/<PROJECT_ID>/merge_requests/<IID>/discussions" \
  --input /path/to/payload.json
```

## 5. Handle rejection without downgrading

If the POST returns `400`/`422` (line not part of the diff, stale SHA):

1. Re-fetch `diff_refs` and re-parse the diff once, since the MR may have moved.
2. Retry the same finding against the recomputed position.
3. If it still fails, do **not** fall back to a flat `glab mr note`. Record
   the finding as a posting failure in the final report (file, finding,
   error) so a human can act on it. Silent downgrade to a generic comment
   defeats the point of this skill.

## 6. Exception: the summary note

The overview (summary, mandatory-gate results, risk level, verdict) has no
single code line to anchor to and is posted once as a plain note via
`glab mr note`. Every item in the Findings section still gets its own inline
discussion per the rules above.

## 7. Exception: general questions

Unresolved questions are posted as threads so the author can answer and
resolve them. A line-specific question follows sections 3-5 exactly (same
`position`, same retry rule). A general question (no natural code line) is
posted to the same endpoint without `position`, which creates a resolvable
discussion thread on the MR overview (unlike `glab mr note`, which is a
plain note):

```json
{ "body": "**Question:** Is this endpoint only for internal callers?\n\nThe answer decides whether the missing auth check is a blocker." }
```

```bash
glab api --hostname <HOST> --method POST "projects/<PROJECT_ID>/merge_requests/<IID>/discussions" \
  --input /path/to/question.json
```

Only use this for questions. A finding with no obvious line still follows
section 3: pick the closest fitting line.

## Future extension (not in v1)

GitLab supports multi-line range positions (`position.line_range` with
`start`/`end` objects) for anchoring a whole block precisely instead of one
line. Deferred until single-line anchoring proves insufficient in practice.
