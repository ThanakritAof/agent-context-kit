# Context Procedures

Exact, deterministic steps for every lifecycle action. Perform them with your own file tools and ordinary shell utilities. No program is run; consistency comes from following these steps.

All paths are relative to the target repository root (see SKILL.md → Resolve the target).

## Conventions

### Timestamps

Use one ISO-8601 timestamp per action, captured once at the start:

```bash
date +%Y-%m-%dT%H:%M:%S%z   # e.g. 2026-06-30T14:23:01+0700  → use as <now>
```

For task file names use the colon-free variant:

```bash
date +%Y-%m-%dT%H-%M-%S      # e.g. 2026-06-30T14-23-01  → use as <stamp>
```

### Managed marker

The first line of every managed file (`index.md`, `summary.md`, `project.md`, `topics/service-overview.md`, `backlog.md`, `generated/repo-tree.md`) is exactly:

```
<!-- agent-context-kit:managed -->
```

`config.yaml` is also managed, but YAML does not support HTML comments. Use a YAML comment on its first line instead:

```
# agent-context-kit:managed
```

### Frontmatter format

Task documents begin with YAML frontmatter, then a blank line, then the Markdown body:

```
---
key: value
---

<body>
```

Value rules, applied so any agent re-parses them identically:

- **Strings**: wrap in double quotes, e.g. `task: "Fix login recovery"`. Escape embedded `"` as `\"`. An empty string is `""`.
- **Integers**: bare, e.g. `checkpoint_count: 3`.
- **Booleans**: bare lowercase `true` / `false`.

Write keys in the order listed in [Task frontmatter schema](#task-frontmatter-schema). Replace the whole file on every edit (no in-place partial rewrites of frontmatter).

### Slugs

Derive a task slug from its title:

1. Transliterate to ASCII and lowercase.
2. Replace every run of non-`[a-z0-9]` characters with a single `-`.
3. Strip leading and trailing `-`.
4. Truncate to 64 characters, then strip any trailing `-`.
5. If the result is empty, use `task-<first 8 hex of sha1(title)>`.

Convenience shell:

```bash
printf '%s' "$TITLE" | iconv -t ascii//TRANSLIT 2>/dev/null \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
  | cut -c1-64 | sed -E 's/-+$//'
```

### Excluded directory names

When walking the repository, skip any directory whose name is one of:

```
.cache .context.local .git .idea .mypy_cache .next .pytest_cache
.venv .vscode __pycache__ build coverage dist logs node_modules tmp venv
```

`.agents/` is not excluded: it is Codex's native skill-discovery directory (see [Vendor entrypoints](#vendor-entrypoints)), the same tier as `.claude/`.

Also skip `docs/context/generated/`.

## Initialize

Run when no `docs/context/` exists, or when the user asks to initialize.

1. Create directories: `docs/context/work/`, `docs/context/archive/`, `docs/context/topics/`, `docs/context/generated/`, and `.context.local/`.
2. Add an empty `.gitkeep` to `docs/context/work/` and `docs/context/archive/`.
3. Ensure the vendor entrypoints (see [Vendor entrypoints](#vendor-entrypoints)): `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md`.
4. Ensure `.gitignore` contains the line `.context.local/` (append it if missing; do not duplicate).
5. Write these files from [assets/templates/](../assets/templates/), substituting `{{placeholder}}` tokens. Skip a file that already exists unless the user asked to overwrite:
   - `docs/context/config.yaml` ← `config.yaml`
   - `docs/context/project.md` ← `project.md`
   - `docs/context/topics/service-overview.md` ← `service-overview.md`
   - `docs/context/backlog.md` ← `backlog.md`
6. Install the `/ac-` slash commands (see [Slash commands](#slash-commands)).
7. Regenerate `index.md` and `summary.md` (see below).
8. Generate `generated/repo-tree.md` (see [Refresh tree](#refresh-tree)).

Template placeholders (the literal managed marker is already in each template):

- `{{updated_at}}` → `<now>`
- `{{project_name}}` → the target root directory name
- `{{project_type}}` → detected types (see below), or `unknown`
- `{{branch}}` → `git -C <root> rev-parse --abbrev-ref HEAD` (or `not a git repo`)

Project-type detection — include each label whose marker file exists at the root, joined by `, `:

| Label | Marker files |
|---|---|
| node | `package.json` |
| python | `pyproject.toml`, `setup.py`, `requirements.txt` |
| go | `go.mod` |
| rust | `Cargo.toml` |
| ruby | `Gemfile` |
| jvm | `pom.xml`, `build.gradle`, `build.gradle.kts` |
| make | `Makefile`, `makefile` |
| docker-compose | `docker-compose.yml`, `docker-compose.yaml` |
| docker | `Dockerfile` |

## Start work

Run for non-trivial work with no matching active task.

1. If `docs/context/` does not exist, Initialize first.
2. Capture `<now>` and `<stamp>`. Compute `<slug>` from the title.
3. File path: `docs/context/work/<stamp>-<slug>.md`. If it exists, append `-2`, `-3`, … before `.md` until unique.
4. The file `id` is its base name without `.md`.
5. Write the file as frontmatter + the body from `assets/templates/task.md` (substitute `{{task_title}}` and `{{created_at}}`). If the initial status is not `planned`, update the `## Status` section body to match.
6. Regenerate `index.md` and `summary.md`.

Initial frontmatter values for a new task:

```
id: "<file stem>"
created_at: "<now>"
updated_at: "<now>"
status: "planned"          # or the requested status
done: false                # true only when status is "completed"
checkpoint_count: 0
owner: "<owner or unassigned>"
task: "<title>"
latest_summary: "Task created; context and plan are not complete yet."
next_action: "Complete the context and plan before implementation."
resume_point: "Not started yet."
latest_decision: ""
latest_evidence: ""
blocker: ""
```

Valid statuses: `planned`, `in_progress`, `blocked`, `completed`.

## Resume / Inspect

- **Inspect**: read every `docs/context/work/*.md`, ordered `blocked` → `in_progress` → `planned`, then by `updated_at` descending. Report for each: `task`, file path, `status`, `owner`, `checkpoint_count`, `latest_summary`, `next_action`, `resume_point`, and `blocker` when set. Then list up to 5 open items from `backlog.md`. If there is no active work, say "No active work."
- **Resume**: do the Inspect read, then read `docs/context/summary.md` and the selected task before editing code. Tell the user to do the same.

## Checkpoint

Run after a meaningful decision, implementation phase, verification run, or blocker. The task must live under `docs/context/work/` (you cannot checkpoint an archived task).

1. Read the task. Capture `<now>`.
2. `checkpoint_count` += 1. Set `updated_at: "<now>"` and `latest_summary` to the compact result.
3. Set the optional fields only when provided this checkpoint: `next_action`, `resume_point` (where you stopped so the next agent can pick up), `latest_evidence`, `latest_decision`, `blocker`.
4. If a non-empty `blocker` is set, set `status: "blocked"`. Otherwise, if `status` was `planned`, set it to `in_progress`.
5. If the status changed in step 4, replace the `## Status` section body with:

   ```
   - Current status: `<status>`
   - Done: `false`
   ```

6. Append to the body, under `## Checkpoints`:

   ```
   ### Checkpoint <count> — <now>

   - Summary: <summary>
   - Decision: <decision>        # only if provided
   - Evidence: <evidence>        # only if provided
   - Blocker: <blocker>          # only if non-empty
   - Next action: <next_action>  # only if set
   ```

7. Replace the `## Handoff` section body with:

   ```
   - Current state: <summary>
   - Status: `<status>`
   - Next action: <next_action or "Not recorded">
   - Stopped at: <resume_point or "Not recorded">
   - Latest evidence: <latest_evidence>   # only if set
   - Blocker: <blocker>                    # only if set
   ```

8. Regenerate `index.md`.
9. Refresh `summary.md` if **any** of these hold: this checkpoint forces it (handoff/boundary), a non-empty `blocker` is set, or `checkpoint_count` is a multiple of the configured interval. Read the interval from `every_checkpoints:` under `summary:` in `docs/context/config.yaml` (default 3, minimum 1).

## Refresh summary (standalone)

Force a rolling-summary refresh before session end, compaction, agent switch, blocking, or completion, without adding a checkpoint: regenerate `index.md` and `summary.md`. Do not touch `project.md`, topics, or task bodies.

## Complete

Run only after proportional verification.

1. Resolve the task; it must be under `docs/context/work/` or `docs/context/archive/`. Refuse any path outside those two directories.
2. Set `status: "completed"`, `done: true`, `updated_at: "<now>"`.
3. Replace the `## Status` section body with:

   ```
   - Current status: `completed`
   - Done: `true`
   ```

4. Append to the body:

   ```
   ## Status Update — <now>

   - Status: `completed`
   ```

5. If the task is under `work/`, move the file to `docs/context/archive/` (same file name).
6. Regenerate `index.md` and `summary.md`.

The same flow updates any other status (`blocked`, `in_progress`, `planned`); only `completed` moves the file to `archive/`.

## Backlog

`docs/context/backlog.md` holds things to do next that are not yet started. It has an `## Open` list and a `## Done` list of `- [ ]` / `- [x]` items.

**Add (`/ac-note <text>`)** — append a new item under `## Open`, using the date from `date +%Y-%m-%d`:

```
- [ ] <text>  (<date>)
```

Do not start the work; only capture it. Replace the `_None yet…_` placeholder with the first real item. Then refresh `summary.md` so the item shows in the briefing.

**View (`/ac-backlog`)** — read `backlog.md` and list the open items. If the user picks one to start, promote it (below); if one is obsolete, remove it.

**Promote to a task** — when starting a backlog item, run [Start work](#start-work) with the item text as the title, then move it from `## Open` to `## Done` (replacing the `_None yet._` placeholder if present):

```
- [x] <text>  (<date>) → work/<file>.md
```

If `## Open` becomes empty, restore its `_None yet…_` placeholder line.

## Refresh tree

Regenerate `docs/context/generated/repo-tree.md` after meaningful layout changes. Default max depth is 4.

Prefer `tree` when available:

```bash
tree -a -L 4 --noreport \
  -I '.cache|.context.local|.git|.idea|.mypy_cache|.next|.pytest_cache|.venv|.vscode|__pycache__|build|coverage|dist|logs|node_modules|tmp|venv'
```

Fallback with `find` (depth-limited, pruned):

```bash
find . -maxdepth 4 \
  \( -name .git -o -name node_modules -o -name .venv -o -name venv \
     -o -name __pycache__ -o -name dist -o -name build -o -name coverage \
     -o -name .context.local -o -name .next -o -name .pytest_cache \
     -o -name .mypy_cache -o -name .idea -o -name .vscode -o -name .cache \
     -o -name logs -o -name tmp \) -prune -o -print | sort
```

Drop the `docs/context/generated/` subtree from the listing. Write the file as:

````
<!-- agent-context-kit:managed -->
# Repository Tree

Generated at: <now>
Root: `<absolute root path>`
Max depth: <max depth>

```text
.
<tree lines, directories before files, case-insensitive name order>
```

This file is generated. Do not edit it manually.
````

The tree is reproducible structure, not byte-exact output; either tool's listing is acceptable as long as the exclusions hold.

## Clean

Run only when the user asks to uninstall managed context.

1. Delete `docs/context/` and `.context.local/` (entire trees; `backlog.md` goes with them).
2. Remove the managed block (everything from `<!-- agent-context-kit:start -->` through `<!-- agent-context-kit:end -->`, inclusive) from `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md`. For each: if nothing meaningful remains (only the `# Agent Instructions` heading in `AGENTS.md`, or an otherwise empty file), delete the file; otherwise keep the remaining user content.
3. Delete the installed `ac-*.md` commands from `.claude/commands/`, `.agent/workflows/`, and `.codex/prompts/` (whichever exist). Remove each directory that becomes empty.
4. Remove the `.context.local/` line from `.gitignore`, keeping other lines.
5. If the [continuity hook](#continuity-hook-optional) was installed for any vendor, remove it from that vendor's config file per its removal note — only if the user confirms it was installed, since it is opt-in and not part of default Initialize.

## Regenerate index.md

`index.md` is a generated routing table. Read frontmatter from every task to rebuild it. Sort active tasks (`work/*.md`) by `updated_at` descending. Take the 5 most recently updated archived tasks (`archive/*.md`) for "Recently Completed".

Links are relative to `docs/context/` (so a work task is `work/<file>.md`, an archived task is `archive/<file>.md`). In table cells, escape `|` as `\|` and replace newlines with spaces. Use the `task` field as the title; fall back to the file stem.

Write exactly:

```
<!-- agent-context-kit:managed -->
# Project Context

Updated: <now>

## Read Order

1. `summary.md` — compact current state
2. `project.md` — stable project context
3. Relevant files under `topics/`
4. Relevant task under `work/`

## Active Work

<table when active tasks exist, else the line: No active work.>

## Recently Completed

<bullet list of completed links, else the line: No completed work recorded.>

## Context Areas

- [Project context](project.md)
- [Backlog](backlog.md)
- [Durable topics](topics/)
- [Generated repository tree](generated/repo-tree.md)
```

Active-work table (only when there is at least one active task):

```
| Task | Status | Owner | Checkpoints | Updated | Next action |
|---|---|---|---:|---|---|
| [<task>](work/<file>.md) | <status> | <owner> | <checkpoint_count> | <updated_at> | <next_action> |
```

Recently-completed bullets (only when archived tasks exist):

```
- [<task>](archive/<file>.md)
```

## Regenerate summary.md

`summary.md` is the rolling state. Order active tasks so `blocked` come first, then `in_progress`, then `planned`; within each group sort by `updated_at` descending. Show at most `max_active` tasks in full (read `max_active:` under `summary:` in `docs/context/config.yaml`, default 5); if more are active, add the line `… and <N> more active (see index.md).` after the blocks. Take the 3 most recent archived tasks for "Recently Completed", and up to the first 5 open items from `backlog.md` for "Backlog".

Write exactly:

```
<!-- agent-context-kit:managed -->
# Current Context Summary

Updated: <now>

This rolling summary is regenerated every configured checkpoint interval and at lifecycle boundaries.

## Current State

<per-active-task blocks in the order above, else the line: No active tasks.>

## Backlog

<up to 5 open backlog items as bullets, else the line: No backlog items.>

## Recently Completed

<bullet list, else the line: No recently completed tasks.>

## Resume

Open `index.md`, then read the linked task and relevant topic documents before editing code.
```

Per active task, one block (blank line between blocks):

```
### [<task>](work/<file>.md)

- Status: `<status>`
- Owner: `<owner>`
- Checkpoints: `<checkpoint_count>`
- Current state: <latest_summary>
- Next action: <next_action>
- Stopped at: <resume_point>            # only if set and not "Not started yet."
- Latest decision: <latest_decision>   # only if set
- Latest evidence: <latest_evidence>   # only if set
- Blocker: <blocker>                    # only if set
```

Backlog bullets (copy the open lines verbatim from `backlog.md`):

```
- <backlog item text>
```

Recently-completed bullets:

```
- [<task>](archive/<file>.md) — <latest_summary or "Completed">
```

## Vendor entrypoints

Different agents auto-load different files at session start. Point all of them at the same context so a fresh agent from any vendor discovers active work:

| File | Read by | Managed content (template) |
|---|---|---|
| `AGENTS.md` | Codex (native), Antigravity | `assets/templates/agents-block.md` |
| `CLAUDE.md` | Claude Code | `assets/templates/claude-md.md` (imports `AGENTS.md` via `@AGENTS.md`) |
| `GEMINI.md` | Antigravity / Gemini CLI | `assets/templates/gemini-md.md` |

State lives only in `docs/context/`; these files just point to it. Keep them short — all three treat the content as context, not enforced config, so brevity improves adherence.

Each managed block is the template contents wrapped in markers:

```
<!-- agent-context-kit:start -->
<contents of the template>
<!-- agent-context-kit:end -->
```

To ensure a block in any of these files (same logic for all three):

- If a `<!-- agent-context-kit:start -->` … `<!-- agent-context-kit:end -->` block already exists, replace it in place.
- Else if the file has other content, append a blank line and then the block (preserve the user's existing content).
- Else create the file with just the block. For `AGENTS.md` only, prefix it with `# Agent Instructions` and a blank line.

Claude Code does not read `AGENTS.md`; the `@AGENTS.md` line inside `CLAUDE.md` is what pulls the shared instructions in. Antigravity's `AGENTS.md` support varies by version, so `GEMINI.md` carries the same pointer as a fallback.

## Slash commands

Initialize installs six commands, all prefixed `/ac-` to avoid clashing with built-ins (`/resume`, `/complete`) or other skills. Each command body is a thin wrapper in [assets/templates/commands/](../assets/templates/commands/) that points back to this file — do not duplicate action logic into it.

| Command | Action |
|---|---|
| `/ac-init` | [Initialize](#initialize) this repository |
| `/ac-note <text>` | Add an item to the backlog (see [Backlog](#backlog)) |
| `/ac-backlog` | View / manage the backlog |
| `/ac-resume` | [Resume](#resume--inspect) briefing |
| `/ac-checkpoint [note]` | [Checkpoint](#checkpoint) the active task |
| `/ac-complete` | [Complete](#complete) the active task |

Install each command file (same file name `ac-<name>.md`) into the location the vendor auto-discovers:

| Vendor | Directory | Invoked as |
|---|---|---|
| Claude Code | `.claude/commands/` (project) or `~/.claude/commands/` (personal) | `/ac-note` … |
| Antigravity | `.agent/workflows/` | `/ac-note` … |
| Codex | `.codex/prompts/` (repo) or `~/.codex/prompts/` (user) | `/ac-note` … |

Codex custom prompts are user-scoped and deprecating in favor of skills; if repo-level `/ac-` commands are not picked up, the same actions still work by asking in plain language (Codex reads `AGENTS.md`). Only create directories/commands for vendors the user actually uses; skip a command file that already exists unless the user asks to overwrite.

`/ac-init` has a bootstrap problem the other five don't: it only gets installed *by* Initialize, so it doesn't exist yet in a repository that has never been initialized — plain language ("use the agent-context skill, initialize") is the only way to trigger it there. This is moot once the skill itself is installed at the personal/global scope (e.g. via `npx skills add <repo> -a <agent>` without `--project`, or `~/.claude/skills/`): install `/ac-init` at the matching personal scope too (`~/.claude/commands/ac-init.md` for Claude Code; Codex prompts are user-scoped by default) so it is available in every repository immediately, before that repository has been initialized.

## Continuity hook (optional)

Everything above is loaded once (vendor entrypoint at session start) and after that relies on the agent choosing to re-read `summary.md` — nothing re-asserts it mid-session. On a long session, especially around context compaction, that instruction can fade before the agent thinks to refresh it.

Claude Code, Codex, and Antigravity each have a real `SessionStart` hook mechanism with (as far as could be verified) the same shape: a `matcher` on the trigger source, a `command`, and plain stdout automatically added as context. Installing the same one-line command in each closes the gap, independent of whether the agent remembers to act.

Run this only when the user explicitly asks for it (e.g. "install the continuity hook") — never as part of default Initialize. Each vendor's hook lives in that vendor's own config, so skipping one (or all) never affects the others or the baseline pointer-file design.

The command is identical everywhere:

```
cat docs/context/summary.md 2>/dev/null || true
```

It degrades safely to no output (not an error) when `docs/context/` doesn't exist yet.

| Vendor | File | Confidence |
|---|---|---|
| Claude Code | `.claude/settings.json` (project) or `~/.claude/settings.json` (personal) | High — official docs |
| Codex | `.codex/hooks.json` (project) or `~/.codex/hooks.json` (user) | High — official docs |
| Antigravity | `.agents/hooks.json` (project) or `~/.gemini/antigravity-cli/hooks.json` (global) | Medium — schema pieced together from third-party sources, not confirmed against an official reference; verify it actually fires before relying on it |

Claude Code and Codex use the identical JSON shape:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "cat docs/context/summary.md 2>/dev/null || true"
          }
        ]
      }
    ]
  }
}
```

Antigravity's `hooks.json` is assumed to use the same shape (unconfirmed — some third-party examples wrap it in an extra custom-named key instead of a bare `hooks` key; if the hook doesn't fire in practice, that wrapper is the first thing to try).

Install procedure, per vendor file — never overwrite the file wholesale, since it may hold unrelated settings/hooks:

1. Read the target file. If it does not exist, create it with just the JSON above (Codex and Antigravity ship no `hooks.json` by default, so this is usually a fresh file; Claude Code's `settings.json` usually already exists with other keys).
2. If it exists but has no `hooks` key, add one with just `SessionStart` as above, leaving every other key untouched.
3. If `hooks` exists but has no `SessionStart` array, add the `SessionStart` key above without touching sibling keys (`PreToolUse`, etc.).
4. If `hooks.SessionStart` already exists, check its entries for the exact `command` string `cat docs/context/summary.md 2>/dev/null || true`. If found, it's already installed — do nothing. Otherwise append a new entry (the object with `matcher` and `hooks` above) to the existing array.
5. Validate the result is well-formed JSON before considering the step done.

The `matcher` fires on new sessions, `--resume`/`--continue`, `/clear`, and right after compaction — the last one is what matters most: even if nobody remembered to refresh `summary.md` before compaction, the hook re-injects whatever it currently says immediately after, so state is never fully lost.

To remove it (part of [Clean](#clean) if the user asks): in each vendor file that has it, find the `hooks.SessionStart` entry with that exact command string and remove it; delete the `SessionStart` key if it becomes empty; leave every other key untouched.

## Task frontmatter schema

Keys, in order:

| Key | Type | Notes |
|---|---|---|
| `id` | string | File stem (no `.md`). |
| `created_at` | string | ISO timestamp, set once. |
| `updated_at` | string | ISO timestamp, set on every change. |
| `status` | string | `planned` \| `in_progress` \| `blocked` \| `completed`. |
| `done` | boolean | `true` only when `status` is `completed`. |
| `checkpoint_count` | integer | Number of recorded checkpoints. |
| `owner` | string | Agent or person; `unassigned` if unknown. |
| `task` | string | Human-readable title. |
| `latest_summary` | string | Compact current state. |
| `next_action` | string | Immediate resumable next step. |
| `resume_point` | string | Where work stopped, for the next agent; `"Not started yet."` initially. |
| `latest_decision` | string | Most recent decision; `""` if none. |
| `latest_evidence` | string | Most recent verification; `""` if none. |
| `blocker` | string | Current blocker; `""` if none. |
