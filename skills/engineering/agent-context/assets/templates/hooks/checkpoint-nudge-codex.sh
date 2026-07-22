#!/bin/sh
# agent-context-kit:managed
# Checkpoint nudge hook (Codex PostToolUse, matcher: apply_patch).
#
# Purpose: after a run of implementation edits with no checkpoint in between,
# remind the agent to record one. It never writes a checkpoint itself — the
# summary/decision/next-action text needs judgment only the agent has; this
# script only counts edits and injects a reminder via additionalContext.
#
# Codex reports every file edit as tool_name "apply_patch" with the patch
# text in tool_input.command, using the standard apply_patch marker format
# ("*** Update File: <path>", "*** Add File: <path>", "*** Delete File: <path>").
# There is no separate file_path field, so paths are parsed out of that text.
#
# Cadence: change the number below, then save — no reinstall needed.
threshold={{nudge_threshold}}

# Codex hooks run with the session cwd, which may be a subdirectory — resolve
# the repo root via git so the counter file always lands in the same place.
root=$(git rev-parse --show-toplevel 2>/dev/null || printf '.')
state_dir="$root/.context.local"
counter_file="$state_dir/checkpoint-nudge-count"
mkdir -p "$state_dir"

input=$(cat)
paths=$(printf '%s' "$input" | grep -oE '\*\*\* (Update|Add|Delete) File: [^\\]*')

# A write to a task file *is* a checkpoint (or a new task) — reset the count.
case "$paths" in
  *docs/context/work/*)
    printf '0' > "$counter_file"
    exit 0
    ;;
esac

count=$(cat "$counter_file" 2>/dev/null || printf '0')
case "$count" in ''|*[!0-9]*) count=0 ;; esac
count=$((count + 1))

if [ "$count" -ge "$threshold" ]; then
  printf '0' > "$counter_file"
  cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"You have made $threshold+ implementation edits since the last checkpoint. If this reflects a meaningful decision, implementation phase, or verification run, record one now (agent-context skill: Checkpoint action) before continuing. If not, ignore this and carry on."}}
EOF
else
  printf '%s' "$count" > "$counter_file"
fi

exit 0
