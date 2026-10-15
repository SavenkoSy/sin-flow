#!/bin/bash
set -u
input=$(cat)
sid=$(jq -r '.session_id // empty' <<<"$input")
tp=$(jq -r '.transcript_path // empty' <<<"$input")
[ -n "$sid" ] || exit 0
source "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/stage.sh"
stage_line=$(flow_stage "$sid" "$tp")
[ "${stage_line%% *}" = exec ] || exit 0

pref() {
  sed -n "s/^$1:[[:space:]]*//p" "$HOME/.claude/sin-flow/user.md" 2>/dev/null | sed 's/[[:space:]]#.*//; s/^"//; s/"$//' | head -1
}

runs=$(pref learning_runs)
case "$runs" in ''|*[!0-9]*) runs=10 ;; esac
log="${FLOW_RUNS_LOG:-$HOME/.claude/sin-flow/runs.tsv}"
covered=$("${CLAUDE_PLUGIN_ROOT}"/skills/learning/scripts/covered-sids.sh)
count=$(awk -F'\t' 'NR>1 && $3=="exec" && $16 ~ /^(sin-flow:|flow-)/ {print $5}' "$log" 2>/dev/null | cut -c1-8 | grep -vxF -f <(printf '%s\n' "$covered") | wc -l | tr -d ' ')
grep -q "	$sid	" "$log" 2>/dev/null || count=$((count + 1))
[ "$count" -ge "$runs" ] || exit 0

learning=$("${CLAUDE_PLUGIN_ROOT}"/skills/learning/scripts/learning-dir.sh)
launched="$HOME/.claude/state/learning-launched-flow"
[ -e "$launched" ] && ! [ "$learning/ledger.md" -nt "$launched" ] && exit 0
ps -axo command | grep -qE -- "-n (flow-)?learning" && exit 0

cwd=$(pref learning_cwd)
case "$cwd" in
  '') cwd=$learning ;;
  "~"/*) cwd="$HOME/${cwd#\~/}" ;;
esac
mkdir -p "$learning"
target="$cwd/CLAUDE.md"
if [ ! -f "$target" ]; then
  target="$learning/ledger.md"
  [ -f "$target" ] || : > "$target"
fi
mkdir -p "$(dirname "$launched")"
touch "$launched"
printf '%s\t%s\t%s undigested\tlaunching\n' "$(date -u +%FT%TZ)" "$sid" "$count" >> "$learning/launch.log"
out=$("${CLAUDE_PLUGIN_ROOT}/bin/sin-flow-handoff" --cwd "$cwd" --name learning sin-flow:learning "$target" all 2>&1)
rc=$?
[ "$rc" -eq 0 ] || rm -f "$launched"
printf '%s\t%s\trc=%s\t%s\n' "$(date -u +%FT%TZ)" "$sid" "$rc" "$(printf '%s' "$out" | tr -s '\t\n' '  ')" >> "$learning/launch.log"
exit 0
