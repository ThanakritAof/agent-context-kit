#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename -- "$0")"
SCRIPT_DIR="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
  pwd
)"

FORCE=0
CLEAN=0
RUN_GENERATOR=1
MAX_DEPTH=4

usage() {
  cat <<EOF
Usage: bash $SCRIPT_NAME [--force] [--clean] [--no-generate] [--max-depth N] [--help]

Options:
  --force         Overwrite scaffold files that already exist.
  --clean         Remove all scaffold files.
  --no-generate   Skip the repository tree generation step.
  --max-depth N   Set repository tree depth (default: 4).
  --help          Show this help message.
EOF
}

log() { printf '[agents] %s\n' "$*"; }
warn() { printf '[agents] warn: %s\n' "$*" >&2; }
die() { printf '[agents] error: %s\n' "$*" >&2; exit 1; }

require_value() {
  if [[ -z "${2:-}" ]]; then
    die "$1 requires a value"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)       FORCE=1; shift ;;
    --clean)       CLEAN=1; shift ;;
    --no-generate) RUN_GENERATOR=0; shift ;;
    --max-depth)
      require_value "$1" "${2:-}"
      MAX_DEPTH="$2"
      shift; shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
done

if ! [[ "$MAX_DEPTH" =~ ^[0-9]+$ ]]; then
  die "--max-depth must be a non-negative integer"
fi

cd "$SCRIPT_DIR"

# ── clean mode ──────────────────────────────────────────────

if [[ "$CLEAN" -eq 1 ]]; then
  for target in .agents scripts/update_repo_context.py; do
    if [[ -e "$target" ]]; then
      rm -rf "$target"
      log "removed $target"
    fi
  done
  rmdir scripts 2>/dev/null && log "removed scripts/" || true
  log "clean complete"
  exit 0
fi

# ── detect project ──────────────────────────────────────────

detect_project_types() {
  local types=()
  [[ -f package.json ]]                                         && types+=("node")       || true
  [[ -f pyproject.toml || -f setup.py || -f requirements.txt ]] && types+=("python")     || true
  [[ -f go.mod ]]                                               && types+=("go")         || true
  [[ -f Cargo.toml ]]                                           && types+=("rust")       || true
  [[ -f Gemfile ]]                                              && types+=("ruby")       || true
  [[ -f pom.xml || -f build.gradle || -f build.gradle.kts ]]    && types+=("jvm")        || true
  [[ -f Makefile || -f makefile ]]                               && types+=("make")       || true
  [[ -f docker-compose.yml || -f docker-compose.yaml ]]          && types+=("docker-compose") || true
  [[ -f Dockerfile ]]                                           && types+=("docker")     || true
  if [[ ${#types[@]} -gt 0 ]]; then
    local IFS=', '
    printf '%s' "${types[*]}"
  else
    printf '%s' "unknown"
  fi
}

CURRENT_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'not a git repo')"
PROJECT_TYPES="$(detect_project_types)"

# ── helpers ─────────────────────────────────────────────────

write_file() {
  local path="$1"
  local mode="${2:-0644}"
  local tmp

  tmp="$(mktemp)"
  cat > "$tmp"

  if [[ -f "$path" && "$FORCE" -ne 1 ]]; then
    log "skip  $path (already exists)"
    rm -f "$tmp"
    return 0
  fi

  mkdir -p "$(dirname "$path")"
  install -m "$mode" "$tmp" "$path"
  rm -f "$tmp"
  log "write $path"
}

ensure_line_in_file() {
  local file="$1"
  local line="$2"

  mkdir -p "$(dirname "$file")"
  touch "$file"
  if ! grep -Fqx "$line" "$file"; then
    printf '%s\n' "$line" >> "$file"
    log "append $file :: $line"
  fi
}

# ── create directories ──────────────────────────────────────

mkdir -p \
  .agents/sessions \
  .agents/topics \
  .agents/private \
  .agents/index \
  scripts

touch .agents/sessions/.gitkeep
touch .agents/topics/.gitkeep
touch .agents/private/.gitkeep

# ── .agents/AGENTS.md ───────────────────────────────────────

write_file ".agents/AGENTS.md" <<'AGENTS_EOF'
# AGENTS.md

## Purpose
This repository uses `.agents/` as a structured agent context workspace for humans and AI agents.
Keep this file short. Store policy here, not task history.

## Reading Order & Trust Priority
Before non-trivial work, read in this order. When information conflicts, higher items win.

1. Latest explicit user instruction
2. Verified codebase state
3. `.agents/AGENTS.md` (this file)
4. `.agents/active.md`
5. Most relevant file in `.agents/topics/`
6. Most recent file in `.agents/sessions/`
7. `.agents/index/repo-tree.md`

If notes conflict with the codebase, trust the codebase.

## Context System

| Path | Purpose |
|------|---------|
| `.agents/active.md` | Hot working state — current focus, blockers, next action |
| `.agents/topics/` | Durable knowledge that survives across sessions |
| `.agents/sessions/` | Per-task checkpoints and resumable logs |
| `.agents/private/` | Local-only notes (gitignored, never shared) |
| `.agents/index/repo-tree.md` | Auto-generated directory tree |

## Rules
- Read `.agents/active.md` before meaningful work.
- Update `.agents/active.md` when focus, blocker, or next action changes.
- Create a session note (`YYYY-MM-DD-short-topic.md`) at resumable checkpoints.
- Promote only durable, evidenced knowledge into `.agents/topics/`.
- Record evidence: file paths, commands, outputs, decisions.
- Mark uncertainty explicitly.
- Remove stale notes when they stop matching the codebase.

Do not store: secrets, raw transcripts, chain-of-thought, speculative notes, duplicate summaries.

## Session Notes Format
Include: Summary, Current State, Decisions, Blockers, Files Touched, Commands Run, Next Todo, Resume Prompt.

## Minimum Update Contract
After meaningful work:
- `.agents/active.md` — when focus, blockers, or next steps change
- `.agents/sessions/` — when a task reaches a checkpoint
- `.agents/topics/` — only when knowledge is durable beyond the current task

## Maintenance
```
bash agents.sh                         # scaffold or refresh
bash agents.sh --force                 # overwrite all scaffold files
bash agents.sh --clean                 # remove scaffold entirely
python3 scripts/update_repo_context.py # regenerate repo tree
```
AGENTS_EOF

# ── .agents/active.md ───────────────────────────────────────

write_file ".agents/active.md" <<ACTIVE_EOF
---
updated_at: "${CURRENT_DATE}"
status: "active"
current_focus: "initial setup"
branch: "${CURRENT_BRANCH}"
project_type: "${PROJECT_TYPES}"
---

# Active Context

## Objective
(describe current objective)

## Current State
- Context scaffold initialized
- Detected project type: ${PROJECT_TYPES}

## Blockers
(none yet)

## Next Action
Begin first task and update this file.
ACTIVE_EOF

# ── .agents/topics/service-overview.md ──────────────────────

write_file ".agents/topics/service-overview.md" <<'SERVICE_EOF'
# Service Note

## What is this project?
(brief description)

## Where is it running?
- Local: `http://localhost:____`
- Staging:
- Production:

## How to run locally?
```bash
# (commands to start the project)
```

## Important things to know
- Database:
- Key env vars:
- Deploy how:

## Notes
(anything else worth knowing)
SERVICE_EOF

# ── .agents/index/repo-tree.md ──────────────────────────────

write_file ".agents/index/repo-tree.md" <<'TREE_EOF'
# Repository Tree

Generated at: not generated yet
Generated by: `scripts/update_repo_context.py`

## Tree
```text
(not generated yet — run: python3 scripts/update_repo_context.py)
```
TREE_EOF

# ── scripts/update_repo_context.py ──────────────────────────

write_file "scripts/update_repo_context.py" "0755" <<'PY_EOF'
#!/usr/bin/env python3
"""Generate .agents/index/repo-tree.md from the current repository tree."""
from __future__ import annotations

import argparse
from datetime import datetime
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Iterable

DEFAULT_EXCLUDED_NAMES = {
    ".agents",
    ".git",
    ".next",
    ".venv",
    ".cache",
    ".idea",
    ".mypy_cache",
    ".pytest_cache",
    ".vscode",
    "__pycache__",
    "build",
    "coverage",
    "dist",
    "logs",
    "node_modules",
    "tmp",
    "venv",
}

DEFAULT_IMPORTANT_TOP_LEVEL = {
    "agents.sh",
    "app",
    "docker-compose.yml",
    "Makefile",
    "package.json",
    "pyproject.toml",
    "scripts",
    "src",
    "tests",
    "web",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate .agents/index/repo-tree.md from the current repository tree."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path("."),
        help="Repository root to scan (default: current directory).",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(".agents/index/repo-tree.md"),
        help="Output markdown file path.",
    )
    parser.add_argument(
        "--max-depth",
        type=int,
        default=4,
        help="Maximum traversal depth from root (default: 4).",
    )
    return parser.parse_args()


def should_exclude(path: Path, excluded_names: set[str]) -> bool:
    return path.name in excluded_names


def sorted_children(path: Path, excluded_names: set[str]) -> list[Path]:
    try:
        children = [child for child in path.iterdir() if not should_exclude(child, excluded_names)]
    except OSError:
        return []

    return sorted(children, key=lambda child: (not child.is_dir(), child.name.lower()))


def format_tree_lines(root: Path, max_depth: int, excluded_names: set[str]) -> list[str]:
    lines = ["."]

    def walk(current: Path, prefix: str, depth: int) -> None:
        if depth >= max_depth:
            return

        children = sorted_children(current, excluded_names)
        total = len(children)

        for index, child in enumerate(children):
            is_last = index == total - 1
            branch = "└── " if is_last else "├── "
            display_name = f"{child.name}/" if child.is_dir() else child.name
            lines.append(f"{prefix}{branch}{display_name}")

            if child.is_dir():
                child_prefix = "    " if is_last else "│   "
                walk(child, prefix + child_prefix, depth + 1)

    walk(root, prefix="", depth=0)
    return lines


def collect_important_top_level(root: Path, excluded_names: set[str]) -> list[str]:
    items = sorted_children(root, excluded_names)
    result: list[str] = []

    for item in items:
        if item.name in DEFAULT_IMPORTANT_TOP_LEVEL:
            marker = f"`{item.name}/`" if item.is_dir() else f"`{item.name}`"
            result.append(marker)

    if result:
        return result

    return [f"`{item.name}/`" if item.is_dir() else f"`{item.name}`" for item in items]


def render_markdown(
    *,
    generated_at: str,
    root_display: str,
    max_depth: int,
    excluded_names: Iterable[str],
    tree_lines: list[str],
    important_top_level: list[str],
    generator_path: str,
) -> str:
    excluded_block = "\n".join(f"- `{name}`" for name in sorted(excluded_names))
    tree_block = "\n".join(tree_lines)
    important_block = "\n".join(f"- {item}" for item in important_top_level)

    return f"""# Repository Tree

Generated at: {generated_at}
Generated by: `{generator_path}`

## Scope
- Root: `{root_display}`
- Max depth: {max_depth}

## Excluded
{excluded_block}

## Tree
```text
{tree_block}
```

## Important Top-Level Areas
{important_block}

## Notes
This file is generated from the current filesystem state.
`.agents/` is intentionally excluded.
Do not manually maintain this file unless debugging the generator.
"""


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)

    with NamedTemporaryFile("w", encoding="utf-8", delete=False, dir=path.parent) as handle:
        handle.write(content)
        temp_path = Path(handle.name)

    temp_path.replace(path)


def main() -> None:
    args = parse_args()

    root = args.root.resolve()
    if not root.exists():
        raise SystemExit(f"Repository root does not exist: {root}")

    output = args.output
    if not output.is_absolute():
        output = root / output

    excluded_names = set(DEFAULT_EXCLUDED_NAMES)
    generated_at = datetime.now().astimezone().isoformat(timespec="seconds")
    tree_lines = format_tree_lines(root, args.max_depth, excluded_names)
    important_top_level = collect_important_top_level(root, excluded_names)

    content = render_markdown(
        generated_at=generated_at,
        root_display=".",
        max_depth=args.max_depth,
        excluded_names=excluded_names,
        tree_lines=tree_lines,
        important_top_level=important_top_level,
        generator_path="scripts/update_repo_context.py",
    )

    atomic_write(output, content)
    print(f"Generated: {output}")


if __name__ == "__main__":
    main()
PY_EOF

# ── .gitignore ──────────────────────────────────────────────

ensure_line_in_file ".gitignore" ".agents/private/"

# ── repo tree generation ────────────────────────────────────

if [[ "$RUN_GENERATOR" -eq 1 ]]; then
  if command -v python3 >/dev/null 2>&1; then
    log "validate scripts/update_repo_context.py"
    python3 -m py_compile scripts/update_repo_context.py

    log "run python3 scripts/update_repo_context.py --max-depth $MAX_DEPTH"
    python3 scripts/update_repo_context.py --max-depth "$MAX_DEPTH"
  else
    warn "python3 not found; skipped repo tree generation"
  fi
fi

# ── summary ─────────────────────────────────────────────────

cat <<'SUMMARY_EOF'

Done.

Created:
  .agents/AGENTS.md
  .agents/active.md
  .agents/index/repo-tree.md
  .agents/sessions/   (empty, for checkpoints)
  .agents/topics/service-overview.md
  .agents/topics/     (for durable knowledge)
  .agents/private/    (gitignored)
  scripts/update_repo_context.py

Commands:
  bash agents.sh                         # scaffold
  bash agents.sh --force                 # overwrite
  bash agents.sh --clean                 # remove
  python3 scripts/update_repo_context.py # regen tree

SUMMARY_EOF
