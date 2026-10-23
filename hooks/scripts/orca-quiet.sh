#!/usr/bin/env bash
set -u

FLOW_HOME="${FLOW_HOME:-$HOME/.claude/sin-flow}"
grep -qE '^workspace:[[:space:]]*orca[[:space:]]*$' "$FLOW_HOME/user.md" 2>/dev/null || exit 0
command -v orca >/dev/null 2>&1 || exit 0
payload=$(cat)
[ "$(jq -r '.background_tasks // [] | length' <<<"$payload" 2>/dev/null)" -gt 0 ] 2>/dev/null || exit 0
cwd=$(jq -r '.cwd // empty' <<<"$payload")
top=$(git -C "${cwd:-$PWD}" rev-parse --show-toplevel 2>/dev/null) || exit 0
(sleep 2; orca worktree set --worktree "path:$top" --read --json) >/dev/null 2>&1 &
disown
exit 0
