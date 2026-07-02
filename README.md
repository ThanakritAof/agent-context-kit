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
| `/ac-note <text>` | Add an item to the backlog |
| `/ac-backlog` | View / manage the backlog |
| `/ac-resume` | Report resumable work (blockers first) plus the backlog |
| `/ac-checkpoint [note]` | Checkpoint the active task |
| `/ac-complete` | Complete and archive the active task |

Optional shortcuts — the same actions work in plain language. Installed per vendor at `.claude/commands/`, `.agent/workflows/`, `.codex/prompts/`.
