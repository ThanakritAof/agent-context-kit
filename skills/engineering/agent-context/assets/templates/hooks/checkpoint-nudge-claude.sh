#!/bin/sh
# agent-context-kit:managed
# Checkpoint nudge hook (Claude Code PostToolUse, matcher: Edit|Write|NotebookEdit).
#
# Purpose: after a run of implementation edits with no checkpoint in between,
# remind the agent to record one. It never writes a checkpoint itself — the
# summary/decision/next-action text needs judgment only the agent has; this
# script only counts edits and injects a reminder via additionalContext.
#
# Cadence: change the number below, then save — no reinstall needed.
threshold={{nudge_threshold}}

state_dir="${CLAUDE_PROJECT_DIR:-.}/.context.local"
counter_file="$state_dir/checkpoint-nudge-count"
mkdir -p "$state_dir"

input=$(cat)
file_path=$(printf '%s' "$input" | sed -n 's/.*"file_path" *: *"\([^"]*\)".*/\1/p')

# A write to a task file *is* a checkpoint (or a new task) — reset the count.
case "$file_path" in
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
