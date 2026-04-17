# agent-context-kit

Lightweight scaffolding for adding an `.agents/` context layer to a repository. This project creates a small, opinionated workspace for humans and AI agents: policy notes, active task context, resumable session checkpoints, durable topic notes, and a generated repository tree index.

## Why This Exists

Large language model workflows degrade when context is scattered across chat history, local notes, and undocumented conventions. `agent-context-kit` keeps that context close to the codebase so agents can resume work faster and with less guesswork.

## Key Features

- Scaffolds a consistent `.agents/` directory structure
- Creates starter files for policy, active state, and durable notes
- Generates `.agents/index/repo-tree.md` from the current filesystem
- Detects basic project types and records them in `.agents/active.md`
- Preserves existing scaffold files unless you explicitly use `--force`
- Supports cleanup with a single `--clean` flag

## Requirements

- macOS or Linux
- `bash`
- `python3` for repository tree generation
- Standard Unix utilities available on most developer machines: `install`, `mktemp`, `grep`, `rm`, `rmdir`

Git is optional. If the script is run outside a Git working tree, the generated active context falls back to `branch: "not a git repo"`.

## Repository Layout

This repository currently contains the scaffold entry point and the tree generator:

```text
.
├── agents.sh
├── scripts/
│   └── update_repo_context.py
└── .agents/
    ├── AGENTS.md
    ├── active.md
    ├── index/
    ├── private/
    ├── sessions/
    └── topics/
```

## Quick Start

Run the scaffold from the repository root:

```bash
bash agents.sh
```

On a normal run, the script:

1. Creates the `.agents/` folder structure if it does not exist
2. Writes starter files such as `.agents/AGENTS.md` and `.agents/active.md`
3. Creates `scripts/update_repo_context.py`
4. Ensures `.agents/private/` is present in `.gitignore`
5. Validates the Python generator with `python3 -m py_compile`
6. Generates `.agents/index/repo-tree.md`

## Generated Files

After `bash agents.sh`, you should have:

```text
.agents/
├── AGENTS.md
├── active.md
├── index/
│   └── repo-tree.md
├── private/
│   └── .gitkeep
├── sessions/
│   └── .gitkeep
└── topics/
    └── service-overview.md
scripts/
└── update_repo_context.py
```

### What Each File Is For

- `.agents/AGENTS.md`: repository-level rules for humans and agents
- `.agents/active.md`: current task focus, state, blockers, and next action
- `.agents/index/repo-tree.md`: generated filesystem overview used as quick context
- `.agents/sessions/`: resumable task checkpoints
- `.agents/topics/`: durable notes that should outlive a single task
- `.agents/private/`: local-only notes that should never be shared
- `scripts/update_repo_context.py`: standalone generator for refreshing the repo tree

## CLI Reference

### `agents.sh`

Show help:

```bash
bash agents.sh --help
```

Scaffold or refresh missing files:

```bash
bash agents.sh
```

Overwrite existing scaffold files:

```bash
bash agents.sh --force
```

Skip repository tree generation:

```bash
bash agents.sh --no-generate
```

Increase traversal depth when building the tree:

```bash
bash agents.sh --max-depth 6
```

Remove the scaffolded artifacts:

```bash
bash agents.sh --clean
```

### `scripts/update_repo_context.py`

Generate or refresh the repository tree manually:

```bash
python3 scripts/update_repo_context.py
```

Available options:

```bash
python3 scripts/update_repo_context.py --help
```

Common examples:

```bash
python3 scripts/update_repo_context.py --max-depth 6
python3 scripts/update_repo_context.py --root .
python3 scripts/update_repo_context.py --output .agents/index/repo-tree.md
```

## How Detection Works

`agents.sh` inspects the repository root to label the project in `.agents/active.md`. It currently recognizes:

- `node` via `package.json`
- `python` via `pyproject.toml`, `setup.py`, or `requirements.txt`
- `go` via `go.mod`
- `rust` via `Cargo.toml`
- `ruby` via `Gemfile`
- `jvm` via `pom.xml`, `build.gradle`, or `build.gradle.kts`
- `make` via `Makefile` or `makefile`
- `docker-compose` via `docker-compose.yml` or `docker-compose.yaml`
- `docker` via `Dockerfile`

If nothing matches, the project type is recorded as `unknown`.

## Repository Tree Behavior

The tree generator intentionally excludes noisy directories and caches, including:

- `.agents`
- `.git`
- `node_modules`
- `dist`
- `build`
- `coverage`
- `tmp`
- common editor and Python cache directories

This keeps `.agents/index/repo-tree.md` focused on the application structure instead of generated files.

## Typical Workflow

1. Run `bash agents.sh` once to create the scaffold.
2. Fill in `.agents/topics/service-overview.md` with real project details.
3. Keep `.agents/active.md` updated as work moves forward.
4. Refresh `.agents/index/repo-tree.md` whenever the repository structure changes significantly.

## Troubleshooting

### `python3 not found`

The scaffold still creates most files, but automatic tree generation is skipped. Install Python 3 and rerun:

```bash
python3 scripts/update_repo_context.py
```

### Existing files were not updated

This is expected. The scaffold is idempotent by default. Use:

```bash
bash agents.sh --force
```

### The tree output looks too shallow

Increase the scan depth:

```bash
bash agents.sh --max-depth 6
```

or:

```bash
python3 scripts/update_repo_context.py --max-depth 6
```

### Branch shows `not a git repo`

Run the scaffold inside a Git working tree if you want the active context to capture the current branch name.

## Development Notes

- There is no build step for this repository.
- The Bash script is the main entry point.
- The Python generator is standalone and uses only the standard library.
- The scaffold can recreate `scripts/update_repo_context.py`, so `bash agents.sh --clean` is reversible by running `bash agents.sh` again.
