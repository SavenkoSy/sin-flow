#!/bin/bash
set -u
input=$(cat)
sid=$(jq -r '.session_id // empty' <<<"$input")
tp=$(jq -r '.transcript_path // empty' <<<"$input")
tool=$(jq -r '.tool_name // empty' <<<"$input")
[ -n "$sid" ] || exit 0
source "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/stage.sh"
stage_line=$(flow_stage "$sid" "$tp")
[ -n "$stage_line" ] || exit 0
stage=${stage_line%% *}

deny() {
  jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

case "$stage:$tool" in
  ingest:Skill)
    skill=$(jq -r '.tool_input.skill // empty' <<<"$input")
    if printf '%s' "$skill" | grep -Eq '^sin-flow:(plan|exec)$'; then
      deny "sin-flow:ingest never runs downstream stages in-session — end with an exit and hand off"
    fi
    ;;
  ingest:Agent)
    kind=$(jq -r '.tool_input.subagent_type // empty' <<<"$input")
    case "$kind" in implementer|sin-flow:implementer) deny "sin-flow:ingest never dispatches an implementer — end with an exit and hand off" ;; esac
    ;;
esac
exit 0
