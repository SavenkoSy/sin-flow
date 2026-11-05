#!/bin/bash
set -u
FLOW_HOME="${FLOW_HOME:-$HOME/.claude/sin-flow}"
note=""

add() { note="${note:+$note }$1"; }

if [ "$(sed -n 1p "$FLOW_HOME/user.md" 2>/dev/null)" = "---" ]; then
  if out=$("${CLAUDE_PLUGIN_ROOT}/bin/sin-flow-profile" migrate-user 2>&1); then
    add "sin-flow moved the preferences of $FLOW_HOME/user.md to the plugin options. Tell the user this in one line: $(printf '%s' "$out" | tr '\n' ' ')"
  else
    add "sin-flow could not move the preferences of $FLOW_HOME/user.md to the plugin options, so the flow uses the defaults. Tell the user in one line to run sin-flow-profile migrate-user. Error: $(printf '%s' "$out" | tr '\n' ' ')"
  fi
fi

if out=$("${CLAUDE_PLUGIN_ROOT}/bin/sin-flow-profile" migrate-options 2>&1); then
  [ -z "$out" ] || add "sin-flow moved renamed plugin options to their new names. Tell the user this in one line: $(printf '%s' "$out" | paste -sd ';' -)"
else
  add "sin-flow could not move renamed plugin options to their new names. Tell the user in one line to run sin-flow-profile migrate-options. Error: $(printf '%s' "$out" | tr '\n' ' ')"
fi

[ -n "$note" ] || exit 0
jq -cn --arg m "$note" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
