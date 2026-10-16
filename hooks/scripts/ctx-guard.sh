#!/bin/bash
set -u
input=$(cat)
sid=$(jq -r '.session_id // empty' <<<"$input")
tp=$(jq -r '.transcript_path // empty' <<<"$input")
[ -n "$sid" ] || exit 0
[ -z "$(jq -r '.agent_id // empty' <<<"$input")" ] || exit 0
source "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/stage.sh"
stage_line=$(flow_stage "$sid" "$tp")
skill=${stage_line##* }
dir="$HOME/.claude/state/sessions"
sj="$dir/$sid.json"

say() {
  jq -cn --arg m "$1" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
  exit 0
}

window=1000000
limit_thr=${LIMIT_GUARD_THRESHOLD:-90}
limit_7d_thr=${LIMIT_GUARD_7D_THRESHOLD:-98}
limit_marker="$dir/$sid.limit-guard"
own=""
[ -f "$limit_marker" ] || own=$(jq -r --argjson t "$limit_thr" --argjson w "$limit_7d_thr" '
  select(((.limit_5h // 0) >= $t) or ((.limit_7d // 0) >= $w))
  | [.config_home, "\(.limit_5h // "?") % of the 5-hour limit and \(.limit_7d // "?") % of the 7-day limit"]
  | @tsv' "$sj" 2>/dev/null)
if [ -n "$own" ]; then
  IFS=$'\t' read -r own_home own_level <<<"$own"
  mkdir -p "$dir"
  : > "$limit_marker"
  head="LIMIT GUARD: account $(basename "$own_home") is at ${own_level} (thresholds ${limit_thr} % 5-hour, ${limit_7d_thr} % 7-day, read from the status line)."
  if [ -n "$stage_line" ]; then
    say "$head This is a ${skill} session — finish the in-flight dispatch and write the ledger, so the work resumes from it after the reset; tell the user in one line and keep working."
  else
    say "$head This is not a flow session — tell the user in one line and keep working."
  fi
fi

[ -n "$stage_line" ] || exit 0
[ "$skill" != sin-flow:setup ] || exit 0
guard="$dir/$sid.guard"
used=$(jq -r '.used_pct // empty' "$sj" 2>/dev/null)
if [ -z "$used" ] && [ -f "$tp" ]; then
  tokens=$(tail -n 400 "$tp" | jq -rs '
    map(select(.type == "assistant" and .message.usage != null)) | last // empty
    | .message.usage | (.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)' 2>/dev/null)
  case "$tokens" in ''|*[!0-9]*) ;; *) used=$(( tokens * 100 / window )) ;; esac
fi
configured=$(awk -F': *' '$1 == "context_guard" { print $2; exit }' "$HOME/.claude/sin-flow/user.md" 2>/dev/null)
case "$configured" in ''|*[!0-9]*) configured=40 ;; esac
thr=${CTX_GUARD_THRESHOLD:-$configured}
last_ctx=0
[ -f "$guard" ] && last_ctx=$(sed -n 1p "$guard")
last_ctx=${last_ctx:-0}
used_i=${used%.*}
case "$used_i" in ''|*[!0-9]*) exit 0 ;; esac
[ "$used_i" -ge "$thr" ] || exit 0
level=$(( used_i / 5 * 5 ))
[ "$level" -gt "$last_ctx" ] || exit 0
mkdir -p "$dir"
printf '%s\n' "$level" > "$guard"
case "$skill" in
  sin-flow:exec) rule="hand off now per the skill's Hand-off section, trigger 2: let the in-flight implementer finish, write the ledger's hand-off section, run sin-flow-handoff with sin-flow:exec, the same plan path and \"continue: <remaining> PR: <url | none>\", then end the turn." ;;
  sin-flow:ingest) rule="hand off now per the skill's Context discipline rule: verdict plan, seed with what is verified and every open point under ## Open decisions, then the hand-off to sin-flow:plan." ;;
  sin-flow:plan) rule="hand off now per the skill's CTX GUARD rule: let the in-flight dispatch finish, put every measured number in evidence/<unit>.md, run sin-flow-handoff with sin-flow:plan, the same plan path and \"continue: from Step <n>\", then end the turn; never hand a half-measured plan to sin-flow:exec." ;;
  sin-flow:sync) rule="follow the skill's CTX GUARD rule: finish the in-flight dispatch; a batch already taken gets its hand-off to sin-flow:plan now; otherwise tell the user in one line that the talk continues in a new /sin-flow:sync <key> session, then stop." ;;
  sin-flow:review) rule="follow the skill's CTX GUARD rule: finish the step in flight and its chat (the review file is the trail), then tell the user in one line that the next /sin-flow:review command belongs in a new session, then stop." ;;
  sin-flow:learning) rule="follow the skill's CTX GUARD rule: let the in-flight readers finish, write the digest and the ledger entry for the sessions they covered, then tell the user in one line to run /sin-flow:learning with the same mode in a new session, then stop." ;;
  *) rule="follow the skill's CTX GUARD rule." ;;
esac
say "CTX GUARD: context at ${used_i} % (threshold ${thr} %). This is a ${skill} session — $rule"
