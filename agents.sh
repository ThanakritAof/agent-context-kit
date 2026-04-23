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
TASK_TITLE=""
TASK_STATUS="planned"
UPDATE_TASK_FILE=""

usage() {
  cat <<EOF
Usage:
  bash $SCRIPT_NAME [--force] [--clean] [--no-generate] [--max-depth N] [--help]
  bash $SCRIPT_NAME --start-task "Task title" [--task-status STATUS]
  bash $SCRIPT_NAME --update-task .agents/sessions/YYYY-MM-DDTHH-MM-SS-task.md --task-status STATUS

Options:
  --force             Overwrite scaffold files that already exist.
  --clean             Remove all scaffold files.
  --no-generate       Skip the repository tree generation step.
  --max-depth N       Set repository tree depth (default: 4).
  --start-task TITLE  Create a planned session note before implementation starts.
  --update-task FILE  Update an existing session note status.
  --task-status NAME  Task status: planned, in_progress, blocked, completed.
                      Default: planned.
  --help              Show this help message.
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
    --start-task)
      require_value "$1" "${2:-}"
      TASK_TITLE="$2"
      shift; shift
      ;;
    --update-task)
      require_value "$1" "${2:-}"
      UPDATE_TASK_FILE="$2"
      shift; shift
      ;;
    --task-status)
      require_value "$1" "${2:-}"
      TASK_STATUS="$2"
      shift; shift
      ;;
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

case "$TASK_STATUS" in
  planned|in_progress|blocked|completed) ;;
  *) die "--task-status must be one of: planned, in_progress, blocked, completed" ;;
esac

if [[ -n "$TASK_TITLE" && -n "$UPDATE_TASK_FILE" ]]; then
  die "--start-task and --update-task cannot be used together"
fi

if [[ "$CLEAN" -eq 1 && ( -n "$TASK_TITLE" || -n "$UPDATE_TASK_FILE" ) ]]; then
  die "--clean cannot be combined with task lifecycle options"
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

local_iso_timestamp() {
  local timestamp
  local prefix
  local suffix

  timestamp="$(date +%Y-%m-%dT%H:%M:%S%z)"
  prefix="${timestamp%??}"
  suffix="${timestamp#$prefix}"
  printf '%s:%s' "$prefix" "$suffix"
}

CURRENT_DATE="$(local_iso_timestamp)"
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

done_flag_for_status() {
  if [[ "$1" == "completed" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

escape_yaml_double_quoted() {
  local value="$1"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

slugify_task_title() {
  local title="$1"
  local slug

  slug="$(
    printf '%s' "$title" \
      | LC_ALL=C tr '[:upper:]' '[:lower:]' \
      | LC_ALL=C tr -cs '[:alnum:]' '-' \
      | sed 's/^-*//; s/-*$//; s/--*/-/g'
  )"
  slug="${slug:0:60}"

  if [[ -z "$slug" ]]; then
    slug="task"
  fi

  printf '%s' "$slug"
}

unique_session_path() {
  local slug="$1"
  local timestamp_prefix
  local candidate
  local index

  timestamp_prefix="$(date +%Y-%m-%dT%H-%M-%S)"
  candidate=".agents/sessions/${timestamp_prefix}-${slug}.md"

  if [[ ! -e "$candidate" ]]; then
    printf '%s' "$candidate"
    return 0
  fi

  index=2
  while true; do
    candidate=".agents/sessions/${timestamp_prefix}-${slug}-${index}.md"
    if [[ ! -e "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
    index=$((index + 1))
  done
}

write_active_for_task() {
  local task_title="$1"
  local task_status="$2"
  local session_path="$3"
  local updated_at="$4"
  local escaped_title
  local escaped_session_path
  local done_flag
  local current_state
  local next_action

  escaped_title="$(escape_yaml_double_quoted "$task_title")"
  escaped_session_path="$(escape_yaml_double_quoted "$session_path")"
  done_flag="$(done_flag_for_status "$task_status")"

  case "$task_status" in
    planned)
      current_state="Task is planned. Implementation is waiting for plan approval."
      next_action="Write or review the plan, then update status to in_progress after user approval."
      ;;
    in_progress)
      current_state="Task is registered and in progress."
      next_action="Continue implementation and update the session note at the next meaningful checkpoint."
      ;;
    blocked)
      current_state="Task is blocked."
      next_action="Resolve or document the blocker before continuing implementation."
      ;;
    completed)
      current_state="Task is completed."
      next_action="Review verification notes or start the next task."
      ;;
  esac

  cat > ".agents/active.md" <<ACTIVE_EOF
---
updated_at: "${updated_at}"
status: "${task_status}"
current_focus: "${escaped_title}"
branch: "${CURRENT_BRANCH}"
project_type: "${PROJECT_TYPES}"
session_note: "${escaped_session_path}"
done: ${done_flag}
---

# Active Context

## Objective
${task_title}

## Current State
- ${current_state}
- Session note: \`${session_path}\`
- Status: \`${task_status}\`
- Done: \`${done_flag}\`

## Blockers
(none recorded)

## Next Action
${next_action}
ACTIVE_EOF

  log "update .agents/active.md"
}

create_task_session_note() {
  local task_title="$1"
  local task_status="$2"
  local created_at
  local escaped_title
  local slug
  local session_path
  local done_flag

  created_at="$(local_iso_timestamp)"
  escaped_title="$(escape_yaml_double_quoted "$task_title")"
  slug="$(slugify_task_title "$task_title")"
  session_path="$(unique_session_path "$slug")"
  done_flag="$(done_flag_for_status "$task_status")"

  cat > "$session_path" <<TASK_EOF
---
created_at: "${created_at}"
updated_at: "${created_at}"
status: "${task_status}"
done: ${done_flag}
task: "${escaped_title}"
branch: "${CURRENT_BRANCH}"
project_type: "${PROJECT_TYPES}"
---

# Session Note: ${task_title}

## Summary
Task registered before implementation. Complete the plan and get approval before changing code.

## Status
- Current status: \`${task_status}\`
- Done: \`${done_flag}\`

## Current State
- Task note created before implementation.
- Plan must be completed before editing files.

## Plan

### Scope
- Goal:
- Non-goals:

### Files To Inspect
- \`path/to/file\` — why this file matters

### Files Expected To Change
- \`path/to/file\`

### Proposed Changes
- Describe the intended changes before editing.

### Verification Plan
- \`command to run\`

### Risks
- Note compatibility, migration, data, UX, or test risks.

### Approval
Waiting for user approval before implementation.

## Decisions
- Session note created before coding.
- Implementation must wait until the plan is approved.

## Blockers
- None recorded.

## Files Touched
- None yet.

## Commands Run
- \`bash agents.sh --start-task "${task_title}"\`

## Next Todo
- Fill in the plan with concrete files and verification steps.
- Ask the user to approve the plan.
- After approval, run \`bash agents.sh --update-task "${session_path}" --task-status in_progress\`.

## Resume Prompt
Resume \`${task_title}\` from this session note. Read \`.agents/active.md\`, then inspect the files listed here before editing.
TASK_EOF

  write_active_for_task "$task_title" "$task_status" "$session_path" "$created_at"
  log "write $session_path"
}

extract_task_title_from_session() {
  local session_path="$1"
  local task_title

  task_title="$(sed -n 's/^task: "\(.*\)"$/\1/p' "$session_path" | head -n 1)"
  task_title="${task_title//\\\"/\"}"
  task_title="${task_title//\\\\/\\}"

  if [[ -z "$task_title" ]]; then
    task_title="$(basename "$session_path" .md)"
  fi

  printf '%s' "$task_title"
}

update_task_session_status() {
  local session_path="$1"
  local task_status="$2"
  local updated_at
  local done_flag
  local tmp
  local task_title

  if [[ ! -f "$session_path" ]]; then
    die "session note not found: $session_path"
  fi

  updated_at="$(local_iso_timestamp)"
  done_flag="$(done_flag_for_status "$task_status")"
  tmp="$(mktemp)"

  awk -v updated_at="$updated_at" -v task_status="$task_status" -v done_flag="$done_flag" '
    BEGIN {
      in_frontmatter = 0
      in_status_section = 0
      seen_updated_at = 0
      seen_status = 0
      seen_done = 0
      seen_status_line = 0
      seen_done_line = 0
    }
    NR == 1 && $0 == "---" {
      in_frontmatter = 1
      print
      next
    }
    in_frontmatter && $0 == "---" {
      if (!seen_updated_at) {
        print "updated_at: \"" updated_at "\""
      }
      if (!seen_status) {
        print "status: \"" task_status "\""
      }
      if (!seen_done) {
        print "done: " done_flag
      }
      in_frontmatter = 0
      print
      next
    }
    in_frontmatter && $0 ~ /^updated_at:/ {
      print "updated_at: \"" updated_at "\""
      seen_updated_at = 1
      next
    }
    in_frontmatter && $0 ~ /^status:/ {
      print "status: \"" task_status "\""
      seen_status = 1
      next
    }
    in_frontmatter && $0 ~ /^done:/ {
      print "done: " done_flag
      seen_done = 1
      next
    }
    $0 == "## Status" {
      in_status_section = 1
      seen_status_line = 0
      seen_done_line = 0
      print
      next
    }
    in_status_section && $0 ~ /^## / {
      if (!seen_status_line) {
        print "- Current status: `" task_status "`"
      }
      if (!seen_done_line) {
        print "- Done: `" done_flag "`"
      }
      in_status_section = 0
      print
      next
    }
    in_status_section && $0 ~ /^- Current status:/ {
      print "- Current status: `" task_status "`"
      seen_status_line = 1
      next
    }
    in_status_section && $0 ~ /^- Done:/ {
      print "- Done: `" done_flag "`"
      seen_done_line = 1
      next
    }
    {
      print
    }
  ' "$session_path" > "$tmp"

  install -m 0644 "$tmp" "$session_path"
  rm -f "$tmp"

  {
    printf '\n## Status Update - %s\n' "$updated_at"
    printf -- '- Status: `%s`\n' "$task_status"
    printf -- '- Done: `%s`\n' "$done_flag"
  } >> "$session_path"

  task_title="$(extract_task_title_from_session "$session_path")"
  write_active_for_task "$task_title" "$task_status" "$session_path" "$updated_at"
  log "update $session_path"
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

## Mention Behavior
When the user mentions `@AGENTS`, `@ AGENTS`, or attaches this file without extra instructions:
- Treat this file as the active operating policy.
- Read `.agents/active.md` immediately.
- If `.agents/active.md` points to an unfinished session note, summarize the task, status, blocker, and next action, then ask whether to resume it.
- If there is no unfinished session note, say that agent context is loaded and ready for the next task.
- Do not require the user to type "read this file" or any extra setup instruction.
- Do not create a new session note until the user provides a concrete task.

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
| `.agents/sessions/` | Planned task notes, checkpoints, and resumable logs |
| `.agents/private/` | Local-only notes (gitignored, never shared) |
| `.agents/index/repo-tree.md` | Auto-generated directory tree |

## Rules
- Read `.agents/active.md` before meaningful work.
- Before starting non-trivial implementation, run `bash agents.sh --start-task "short task title"` so the task is recorded immediately with `status: "planned"`.
- Before editing files, fill the active session note `## Plan` with Scope, Files To Inspect, Files Expected To Change, Proposed Changes, Verification Plan, Risks, and Approval.
- Ask the user to approve the plan. Do not implement until the user explicitly approves.
- After approval, run `bash agents.sh --update-task .agents/sessions/YYYY-MM-DDTHH-MM-SS-short-topic.md --task-status in_progress`.
- Update `.agents/active.md` when focus, blocker, or next action changes.
- Keep the active session note updated at resumable checkpoints.
- When work is blocked or completed, run `bash agents.sh --update-task .agents/sessions/YYYY-MM-DDTHH-MM-SS-short-topic.md --task-status blocked|completed`.
- Promote only durable, evidenced knowledge into `.agents/topics/`.
- Record evidence: file paths, commands, outputs, decisions.
- Mark uncertainty explicitly.
- Remove stale notes when they stop matching the codebase.

Do not store: secrets, raw transcripts, chain-of-thought, speculative notes, duplicate summaries.

## Session Notes Format
File names use local time in `YYYY-MM-DDTHH-MM-SS-task-slug.md`.
Frontmatter timestamps use local time with an explicit timezone offset, such as `2026-04-23T19:56:52+07:00`.
Include: frontmatter with `status` and `done`, Summary, Status, Current State, Plan, Approval, Decisions, Blockers, Files Touched, Commands Run, Next Todo, Resume Prompt.

## Minimum Update Contract
For meaningful work:
- `.agents/sessions/` — create before implementation starts with `status: "planned"`
- `.agents/sessions/` — fill the `## Plan` section before editing files
- `.agents/active.md` — update when focus, blockers, status, or next steps change
- `.agents/sessions/` — update when a task reaches a checkpoint, blocks, or completes
- `.agents/topics/` — only when knowledge is durable beyond the current task

## Maintenance
```
bash agents.sh                         # scaffold or refresh
bash agents.sh --start-task "..."      # create a planned task note
bash agents.sh --update-task .agents/sessions/YYYY-MM-DDTHH-MM-SS-topic.md --task-status completed
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

# ── task lifecycle ──────────────────────────────────────────

if [[ -n "$TASK_TITLE" ]]; then
  create_task_session_note "$TASK_TITLE" "$TASK_STATUS"
  RUN_GENERATOR=0
fi

if [[ -n "$UPDATE_TASK_FILE" ]]; then
  update_task_session_status "$UPDATE_TASK_FILE" "$TASK_STATUS"
  RUN_GENERATOR=0
fi

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
  .agents/sessions/   (for task notes and checkpoints)
  .agents/topics/service-overview.md
  .agents/topics/     (for durable knowledge)
  .agents/private/    (gitignored)
  scripts/update_repo_context.py

Commands:
  bash agents.sh                         # scaffold
  bash agents.sh --start-task "..."      # create planned task note
  bash agents.sh --update-task FILE --task-status completed
  bash agents.sh --force                 # overwrite
  bash agents.sh --clean                 # remove
  python3 scripts/update_repo_context.py # regen tree

SUMMARY_EOF
