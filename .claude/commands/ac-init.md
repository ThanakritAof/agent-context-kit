---
description: Initialize agent-context for this repository
---
Perform the Initialize action from the agent-context skill (`references/procedures.md`): if `docs/context/` does not already exist, scaffold it, ensure the vendor entrypoints (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`), install the `/ac-` slash commands, add the `.gitignore` entry, and generate `index.md`, `summary.md`, and `generated/repo-tree.md`. If `docs/context/` already exists, say so and suggest `/ac-resume` instead.
