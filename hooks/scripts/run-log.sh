#!/bin/bash
set -u
input=$(cat)
sid=$(jq -r '.session_id // empty' <<<"$input")
tp=$(jq -r '.transcript_path // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")
[ -n "$sid" ] && [ -n "$tp" ] && [ -f "$tp" ] || exit 0
source "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/stage.sh"
stage_line=$(flow_stage "$sid" "$tp")
[ -n "$stage_line" ] || exit 0
read -r stage n skill <<<"$stage_line"
[ -n "$cwd" ] || cwd=$(jq -r 'select(.cwd) | .cwd' "$tp" | head -1)
repo=$(flow_repo_key "$cwd" "$stage" "$n")
log="${FLOW_RUNS_LOG:-$HOME/.claude/sin-flow/runs.tsv}"
mkdir -p "$(dirname "$log")"
[ -f "$log" ] || printf 'date\trepo\tstage\tn\tsession_id\taccount\tmodel\tstart\tend\tturns\tuser_turns\tctx_first_k\tctx_last_k\thandoff\tlimit_hits\tskill\n' > "$log"
if grep -q "	$sid	" "$log"; then t=$(mktemp); grep -v "	$sid	" "$log" > "$t" && mv "$t" "$log"; fi
model=$(jq -r 'select(.type=="assistant") | .message.model // empty' "$tp" | grep -v synthetic | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
start=$(jq -r 'select(.timestamp) | .timestamp' "$tp" | head -1 | cut -c1-16)
end=$(jq -r 'select(.timestamp) | .timestamp' "$tp" | tail -1 | cut -c1-16)
read -r turns ctx_first ctx_last <<<"$(jq -r 'select(.type=="assistant" and .message.usage) | .message.usage | (.input_tokens + (.cache_read_input_tokens//0) + (.cache_creation_input_tokens//0))' "$tp" | awk 'NR==1{f=$1} {l=$1; c++} END{printf "%d %d %d", c, f/1000, l/1000}')"
user_turns=$(jq -r 'def relay: test("^(Another Claude session sent a message|\\[Subagent hand-back\\]|Base directory for this skill|\\[Request interrupted|A session-scoped Stop hook|Goal check-in:|Stop hook feedback:|Your claude\\.ai usage limit has reset)"); select(.type=="user" and .isMeta != true and .isCompactSummary != true) | .parentUuid as $p | .message.content | if type=="string" then (if (length==0 or startswith("<") or relay) then empty else $p end) else (if (map(select(.type=="tool_result"))|length)>0 then empty else ((map(select(.type=="text"))|map(.text)|join("")) | if ((gsub("\\[Image #[0-9]+\\]|\\s";"")|length)>0 and (startswith("<")|not) and (relay|not)) then $p else empty end) end) end' "$tp" | sort -u | grep -c .)
queued=$(jq -r 'select(.type=="attachment" and .attachment.type=="queued_command" and .attachment.humanTurn==true) | .uuid' "$tp" | grep -c .)
user_turns=$((user_turns + queued))
handoff=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Bash") | .input.command // empty | reduce split("\n")[] as $l ({d:null, o:[]}; if .d then (if ($l|sub("^\\t+";"")) == .d then .d = null else . end) else (.o += [$l] | .d = (($l | capture("<<-?\\s*[\"\\x27]?(?<t>[A-Za-z_][A-Za-z0-9_]*)") | .t) // null)) end) | select(any(.o[]; test("(^|[;&|])\\s*([A-Za-z_][A-Za-z0-9_]*=\\S*\\s+)*sin-flow-handoff ") and (test("<N>|sin-flow-handoff\\s+(--help|-h)\\b")|not))) | "h"' "$tp" | grep -c .)
limit_hits=$(jq -r 'select(.type=="system" and .subtype=="informational") | .content // empty' "$tp" | grep -c 'Usage limit reached')
sj="$HOME/.claude/state/sessions/$sid.json"
home=$(jq -r '.config_home // empty' "$sj" 2>/dev/null)
[ -n "$home" ] || home=${tp%%/projects/*}
acct=$(basename "$home")
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${end%%T*}" "$repo" "$stage" "$n" "$sid" "$acct" "${model:-?}" "$start" "$end" "$turns" "$user_turns" "$ctx_first" "$ctx_last" "$handoff" "$limit_hits" "$skill" >> "$log"
