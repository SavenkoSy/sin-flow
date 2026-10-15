#!/bin/bash
set -euo pipefail
export CMUX_QUIET=1
cmd=(cmux new-surface --workspace "${CMUX_WORKSPACE_ID:?}" --working-directory "$FLOW_CWD" --command "$FLOW_PROMPT" --focus false --json)
if [ "${1:-}" = --probe ]; then printf '%q ' "${cmd[@]}"; echo; exit 0; fi
surface=$("${cmd[@]}" | jq -r '.surface_ref // empty')
[ -z "$surface" ] || cmux rename-tab --workspace "$CMUX_WORKSPACE_ID" --surface "$surface" -- "$FLOW_NAME" > /dev/null 2>&1 || true
