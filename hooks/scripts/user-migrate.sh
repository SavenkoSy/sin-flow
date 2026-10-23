#!/bin/bash
set -u
FLOW_HOME="${FLOW_HOME:-$HOME/.claude/sin-flow}"
[ "$(sed -n 1p "$FLOW_HOME/user.md" 2>/dev/null)" = "---" ] || exit 0

say() {
  jq -cn --arg m "$1" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
  exit 0
}

if out=$("${CLAUDE_PLUGIN_ROOT}/bin/sin-flow-profile" migrate-user 2>&1); then
  say "sin-flow moved the preferences of $FLOW_HOME/user.md to the plugin options. Tell the user this in one line: $(printf '%s' "$out" | tr '\n' ' ')"
fi
say "sin-flow could not move the preferences of $FLOW_HOME/user.md to the plugin options, so the flow uses the defaults. Tell the user in one line to run sin-flow-profile migrate-user. Error: $(printf '%s' "$out" | tr '\n' ' ')"
