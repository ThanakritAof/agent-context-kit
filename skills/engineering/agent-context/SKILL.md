---
name: agent-context
description: Initialize and maintain vendor-neutral repository context under docs/context, including project overview, durable topics, active work, checkpoints, rolling summaries, a backlog of things to do next, resumable handoffs across different agents (Claude Code, Codex, Antigravity), and archives. Use when setting up persistent AI context, starting or resuming non-trivial work, recording decisions or verification, switching agents, approaching context compaction, completing work, noting a backlog item, or when the user asks to initialize, save, checkpoint, summarize, restore, or resume project context.
---

# Agent Context

Persist shared context in the target repository, not in the installed skill. Treat the skill as the workflow and `docs/context/` as the data store.

This skill is instruction-driven: **you** perform every action with your own file tools (read, write, edit) plus ordinary shell utilities (`date`, `git`, `find`/`tree`). There is no program to run. Follow the procedures exactly so any agent reproduces the same artifacts.

## Resolve the target

Use the current repository root unless the user names another repository. Every path in this skill is relative to that target root, not to the installed skill directory. When the skill is installed outside the target, prefix paths with the target root.

The skill ships templates under [assets/templates/](assets/templates/). Copy a template into the target and replace its `{{placeholder}}` tokens; never write skill-relative state into the target as data.

## Choose the action

Decide which lifecycle action applies, then follow its steps in [references/procedures.md](references/procedures.md). Do not improvise the mechanics — the procedures define exact file names, frontmatter fields, and regeneration layouts.

- **Initialize** — no active context exists. Scaffold `docs/context/`, the vendor entrypoints (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`), the `/ac-` slash commands, and the `.gitignore` entry.
- **Start work** — non-trivial work with no matching active task. Create a task under `docs/context/work/`.
- **Resume** — read `docs/context/summary.md` and the selected task, then report resumable state (blockers first, where each task stopped, and the backlog).
- **Checkpoint** — record a compact result, next action, and where you stopped (`resume_point`) after a meaningful decision, implementation phase, verification run, or blocker. Do not checkpoint every tool call or edit.
- **Backlog** — capture something to do later without starting it (`/ac-note`), or view and promote items (`/ac-backlog`); items surface in the summary briefing.
- **Refresh summary** — force a rolling-summary refresh before session end, context compaction, agent switch, blocking, or completion, even when no new checkpoint is due.
- **Complete** — set a task to `completed` and move it to `docs/context/archive/`, only after proportional verification.
- **Refresh tree** — regenerate `docs/context/generated/repo-tree.md` after meaningful repository-layout changes.
- **Inspect** — report active task status without changing anything.
- **Clean** — remove managed context artifacts (context tree, vendor entrypoint blocks, `/ac-` commands) when the user asks to uninstall.

Record a decision, evidence, or blocker only when that fact exists. Do not invent them.

## Automatic workflow

For every non-trivial implementation task:

1. Read `docs/context/summary.md` first, then `docs/context/index.md`.
2. Read `docs/context/project.md`, relevant topics, and the matching task.
3. Resume matching active work or create a task.
4. Record meaningful checkpoints; do not checkpoint every tool call or file edit.
5. Refresh the summary every configured interval (default: every 3 checkpoints). Force a refresh before session end, compaction, agent switch, blocking, or completion.
6. Promote reusable evidence to `topics/` and project-wide facts to `project.md`.
7. Archive completed work.

Skip tracking for trivial questions and read-only lookups. Never store secrets, raw transcripts, hidden reasoning, or unsupported claims.

## Preserve trust order

Follow this priority when context conflicts:

1. Latest explicit user instruction
2. Verified code and command output
3. Root agent instructions
4. `docs/context/project.md` and topic documents
5. Rolling summary and task records
6. Generated repository tree

Mark stale context and correct it when verified. Do not treat generated or historical notes as stronger than current code.

## References

- [references/procedures.md](references/procedures.md) — exact, deterministic steps for every action. Read it before performing any action.
- [references/context-schema.md](references/context-schema.md) — artifact ownership, promotion rules, and checkpoint policy. Read it when changing document structure or promotion behavior.
