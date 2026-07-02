# Context Schema

This document defines artifact ownership and policy. For the exact step-by-step mechanics of each action (file names, frontmatter fields, regeneration layouts), see [procedures.md](procedures.md).

## Read order

1. `docs/context/summary.md`
2. `docs/context/index.md`
3. `docs/context/project.md`
4. Relevant `docs/context/topics/*.md`
5. Relevant `docs/context/work/*.md`

## Ownership

- `index.md`: generated routing table; do not edit manually.
- `summary.md`: generated rolling state; refresh every configured checkpoint interval and at lifecycle boundaries.
- `project.md`: human-reviewed, durable project-wide facts.
- `backlog.md`: things to do next, not yet started; append with `/ac-note`, promote to `work/` when begun.
- `topics/`: human-reviewed, reusable domain knowledge and gotchas.
- `work/`: active task state, checkpoints, evidence, and handoff.
- `archive/`: completed task records.
- `generated/`: reproducible context such as the repository tree.
- `.context.local/`: ignored machine-local and private data.

## Promotion rules

- Keep one-off discoveries in the task document.
- Promote reusable, evidenced knowledge to a topic document.
- Promote facts that affect the whole repository to `project.md`.
- Link existing docs instead of duplicating them.
- Do not promote guesses, raw transcripts, secrets, or chain-of-thought.

## Checkpoint rules

Record a checkpoint after a meaningful decision, implementation phase, verification run, or blocker. Include a compact result and an immediate next action. Add evidence and rationale when available.

Refresh `summary.md` at the configured checkpoint interval (default every 3). Refresh immediately before session end, context compaction, agent switch, blocking, or completion.
