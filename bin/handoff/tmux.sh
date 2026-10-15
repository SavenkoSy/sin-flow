#!/bin/bash
set -euo pipefail
cmd=(tmux new-window -c "$FLOW_CWD" -n "$FLOW_NAME" "$FLOW_PROMPT")
if [ "${1:-}" = --probe ]; then printf '%q ' "${cmd[@]}"; echo; exit 0; fi
"${cmd[@]}"
