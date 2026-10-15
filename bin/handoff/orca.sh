#!/bin/bash
set -euo pipefail
command="cd $(printf %q "$FLOW_CWD") && $FLOW_PROMPT"
for row in "path:$FLOW_CWD" ${ORCA_WORKTREE_ID:+"id:$ORCA_WORKTREE_ID"}; do
  cmd=(orca terminal create --worktree "$row" --title "$FLOW_NAME" --command "$command" --json)
  if [ "${1:-}" = --probe ]; then printf '%q ' "${cmd[@]}"; echo; exit 0; fi
  "${cmd[@]}" > /dev/null 2>&1 && exit 0
done
echo "Orca has no row for $FLOW_CWD and this terminal is not in an Orca row" >&2
exit 3
