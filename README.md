# agent-context-kit

Vendor-neutral, persistent project context for AI coding agents. Shared state lives under `docs/context/`, stays reviewable in Git, and survives chat resets, compaction, and switching agents (Claude Code, Codex, Antigravity).

## Layout

```text
skills/engineering/agent-context/   # the installable skill (SKILL.md + references/ + assets/)
docs/context/                       # per-project context this skill manages
AGENTS.md / CLAUDE.md / GEMINI.md   # short pointers so any agent auto-discovers docs/context/
```

`docs/context/`:

```text
docs/context/
├── index.md                # generated routing table
├── summary.md              # generated rolling summary — read this first
├── project.md              # durable project-wide context
├── backlog.md              # things to do next, captured with /ac-note
├── config.yaml             # tracking and summary policy
├── topics/                 # reusable, evidenced knowledge
├── work/                   # active task state and checkpoints
├── archive/                # completed task records
└── generated/repo-tree.md  # reproducible repository structure

.context.local/             # gitignored machine-local/private context
```

The skill is instruction-driven — no program to install or run. The agent performs every action with its own file tools plus `date`/`git`/`find` (optionally `tree`), following [SKILL.md](skills/engineering/agent-context/SKILL.md) and [references/procedures.md](skills/engineering/agent-context/references/procedures.md). Never stores secrets, raw transcripts, or chain-of-thought.

## Install

### With `npx skills` (recommended — works for every agent)

```bash
# Claude Code
npx skills add ThanakritAof/agent-context-kit -a claude-code

# Other agents (codex, antigravity, gemini-cli, cursor, etc.)
npx skills add ThanakritAof/agent-context-kit -a <agent-name>
```

### Alternative — symlink

```bash
ln -s "$(pwd)/skills/engineering/agent-context" .claude/skills/agent-context   # Claude Code
ln -s "$(pwd)/skills/engineering/agent-context" .agents/skills/agent-context   # Codex
```

Either way, tell the agent to run the skill's **Initialize** action once per target repo — it scaffolds `docs/context/`, the `AGENTS.md`/`CLAUDE.md`/`GEMINI.md` pointers, the `/ac-` slash commands, and the `.gitignore` entry. Native install is optional: the skill also works by just telling any agent to "use the agent-context skill" — it's designed for explicit invocation, not description-matching.

If you installed the skill globally (as `npx skills add` does by default), also drop `/ac-init` at the same personal scope so it works in any repo without a prior Initialize run there:

```bash
mkdir -p ~/.claude/commands
curl -fsSL https://raw.githubusercontent.com/ThanakritAof/agent-context-kit/main/skills/engineering/agent-context/assets/templates/commands/ac-init.md \
  -o ~/.claude/commands/ac-init.md
```

### Continuity hook (optional)

Everything else here is loaded once at session start and relies on the agent choosing to re-read it later — nothing re-asserts it mid-session, so it can fade on a long conversation, especially around context compaction. Claude Code, Codex, and Antigravity each support a real `SessionStart` hook that re-injects `docs/context/summary.md` on session start, resume, `/clear`, and right after compaction — so state survives even if nobody remembered to refresh it first. Ask the agent to "install the continuity hook" and it merges the JSON below into whichever vendor(s) you name; each is independent, so installing (or skipping) one never affects the others.

The command is the same for all three:

```
cat docs/context/summary.md 2>/dev/null || true
```

| Vendor | File | Confidence |
|---|---|---|
| Claude Code | `.claude/settings.json` (project) or `~/.claude/settings.json` (personal) | High |
| Codex | `.codex/hooks.json` (project) or `~/.codex/hooks.json` (user) | High |
| Antigravity | `.agents/hooks.json` (project) or `~/.gemini/antigravity-cli/hooks.json` (global) | Medium — schema not confirmed against an official reference; verify it actually fires |

Claude Code and Codex share this exact shape (merge into the file's existing `hooks` object — don't overwrite other hooks/settings):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          { "type": "command", "command": "cat docs/context/summary.md 2>/dev/null || true" }
        ]
      }
    ]
  }
}
```

Antigravity's `hooks.json` is assumed to use the same shape. See [Continuity hook](skills/engineering/agent-context/references/procedures.md#continuity-hook-optional) for the exact merge/removal steps.

### Checkpoint nudge hook (optional)

The continuity hook above only re-reads `summary.md` back in — it doesn't make the agent write checkpoints. This second, separate hook nudges that side: a `PostToolUse` hook counts implementation edits since the last checkpoint and, past a threshold (default 8), injects a one-line reminder into the agent's context. It never writes a checkpoint itself — the summary/decision text still needs the agent's judgment. Ask the agent to "install the checkpoint nudge hook".

**Claude Code and Codex only.** Antigravity's `PostToolUse` hook has no channel back to the model (its stdout is always `{}`), so this one isn't available there — Antigravity users get the continuity hook only.

| Vendor | File | Script |
|---|---|---|
| Claude Code | `.claude/settings.json` (merge) + `.claude/hooks/checkpoint-nudge.sh` | [checkpoint-nudge-claude.sh](skills/engineering/agent-context/assets/templates/hooks/checkpoint-nudge-claude.sh) |
| Codex | `.codex/hooks.json` (merge) + `.codex/hooks/checkpoint-nudge.sh` | [checkpoint-nudge-codex.sh](skills/engineering/agent-context/assets/templates/hooks/checkpoint-nudge-codex.sh) |

See [Checkpoint nudge hook](skills/engineering/agent-context/references/procedures.md#checkpoint-nudge-hook-optional) for the exact merge/removal steps and why the two scripts differ (Claude Code reports a plain edited-file path; Codex reports a patch blob that has to be parsed for `*** Update File:`-style markers).

## Reference

- **[agent-context](./skills/engineering/agent-context/SKILL.md)** — Initialize and maintain vendor-neutral repository context: project overview, durable topics, active work, checkpoints, rolling summaries, a backlog of things to do next, and resumable handoffs across Claude Code, Codex, and Antigravity. Trigger by asking to initialize, save, checkpoint, summarize, restore, or resume project context.

### Lifecycle actions

| Action | What it does |
|---|---|
| Initialize | Scaffold `docs/context/`, vendor entrypoints, `/ac-` commands, `.gitignore` |
| Start work | Create a tracked task under `docs/context/work/` |
| Checkpoint | Record result, decision, evidence, blocker, and where you stopped (`resume_point`) |
| Backlog | Capture something for later (`/ac-note`) without starting it |
| Refresh summary | Force a rolling-summary update before a handoff or session boundary |
| Resume / Inspect | Report active tasks (blockers first), where each stopped, and the backlog |
| Complete | Mark a task `completed` and move it to `docs/context/archive/` |
| Refresh tree | Regenerate `docs/context/generated/repo-tree.md` |
| Clean | Remove all managed context artifacts |

The summary refresh interval is configured by `every_checkpoints:` in `docs/context/config.yaml` (default 3).

### Slash commands

| Command | What it does |
|---|---|
| `/ac-init` | Initialize this repository |
| `/ac-note <text>` | Add an item to the backlog |
| `/ac-backlog` | View / manage the backlog |
| `/ac-resume` | Report resumable work (blockers first) plus the backlog |
| `/ac-checkpoint [note]` | Checkpoint the active task |
| `/ac-complete` | Complete and archive the active task |

Optional shortcuts — the same actions work in plain language. Installed per vendor at `.claude/commands/`, `.agent/workflows/`, `.codex/prompts/`. `/ac-init` is the exception: it's only installed *by* Initialize, so a never-initialized repo won't have it yet. Install it at the personal scope too (`~/.claude/commands/ac-init.md`) so it works before that first run — see [Install](#install).
