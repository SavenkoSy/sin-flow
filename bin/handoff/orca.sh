#!/bin/bash
set -euo pipefail
command="cd $(printf %q "$FLOW_CWD") && $FLOW_PROMPT"
rows=$(orca worktree list --json 2>/dev/null | jq -r --arg p "$FLOW_CWD" --arg c "${ORCA_WORKTREE_ID:-}" '
  [.result.worktrees[]? | select(.path == $p or .id == $c)]
  | sort_by(.path != $p) | .[].id') || rows=""
while IFS= read -r id; do
  [ -n "$id" ] || continue
  cmd=(orca terminal create --worktree "id:$id" --title "$FLOW_NAME" --command "$command" --json)
  if [ "${1:-}" = --probe ]; then printf '%q ' "${cmd[@]}"; echo; exit 0; fi
  "${cmd[@]}" > /dev/null 2>&1 && exit 0
done <<< "$rows"
echo "Orca shows no workspace for $FLOW_CWD and this terminal is not in a shown one: add the folder as a workspace in Orca, then hand off again" >&2
exit 3
