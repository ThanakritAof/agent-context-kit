## Persistent Project Context

Before any non-trivial task, read `docs/context/summary.md` first (then `docs/context/index.md`). It shows active work, each task's status (done or not), where to resume, and the backlog of things to do next.

- Resume matching unfinished work, or create a task under `docs/context/work/`.
- Checkpoint after a meaningful decision, implementation phase, verification, or blocker — record where you stopped so the next agent can resume.
- Before ending the session, switching agents, or compaction: make sure `summary.md` reflects the latest state.

Full mechanics live in the `agent-context` skill (`SKILL.md` + `references/procedures.md`). Skip tracking for trivial or read-only questions. Never store secrets, raw transcripts, or chain-of-thought.
