#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$root"
unset CTX_GUARD_THRESHOLD LIMIT_GUARD_THRESHOLD LIMIT_GUARD_7D_THRESHOLD CLAUDE_CONFIG_DIR $(compgen -e | grep '^CLAUDE_PLUGIN_OPTION_' || true)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

expect_eq() {
  [ "$2" = "$3" ] || fail "$1: want [$2], got [$3]"
}

run_guard() {
  local stage=$1 tokens=$2 options=$3 sid transcript
  sid="case-$RANDOM-$RANDOM"
  HOME=$(mktemp -d "$scratch/home.XXXXXX")
  export HOME
  mkdir -p "$HOME/.claude/sin-flow"
  [ -z "$options" ] || jq -n --argjson o "$options" '{pluginConfigs: {"sin-flow@test": {options: $o}}}' > "$HOME/.claude/settings.json"
  transcript="$HOME/transcript.jsonl"
  jq -cn --arg c "<command-name>/sin-flow:$stage</command-name><command-args>GH-1</command-args>" '{type:"user",message:{content:$c}}' > "$transcript"
  jq -cn --argjson t "$tokens" '{type:"assistant",message:{usage:{input_tokens:$t}}}' >> "$transcript"
  if [ -n "${used_pct:-}" ] || [ -n "${limit_5h:-}" ]; then
    mkdir -p "$HOME/.claude/state/sessions"
    jq -cn --arg u "${used_pct:-}" --arg l "${limit_5h:-}" \
      '(if $u == "" then {} else {used_pct: ($u | tonumber)} end) + (if $l == "" then {} else {limit_5h: ($l | tonumber), limit_7d: 10, config_home: "/x/home"} end)' \
      > "$HOME/.claude/state/sessions/$sid.json"
  fi
  jq -cn --arg sid "$sid" --arg tp "$transcript" '{session_id:$sid,transcript_path:$tp}' | bash "$root/hooks/scripts/ctx-guard.sh"
}

message() { jq -r '.hookSpecificOutput.additionalContext // empty' | cut -d. -f1; }

out=$(run_guard setup 900000 "")
expect_eq "case 1" "" "$out"

out=$(run_guard plan 450000 "" | message)
expect_eq "case 2" "CTX GUARD: context at 45 % (threshold 40 %)" "$out"

out=$(run_guard plan 450000 '{"context_guard": 50}')
expect_eq "case 3" "" "$out"

out=$(CTX_GUARD_THRESHOLD=30 run_guard plan 450000 '{"context_guard": 50}' | message)
expect_eq "case 4" "CTX GUARD: context at 45 % (threshold 30 %)" "$out"

out=$(run_guard plan 450000 '{"context_window": 200000}' | message)
expect_eq "case 5" "CTX GUARD: context at 45 % (threshold 40 %)" "$out"

out=$(used_pct=55 run_guard plan 10000 "" | message)
expect_eq "case 6" "CTX GUARD: context at 55 % (threshold 40 %)" "$out"

out=$(run_guard plan 450000 '{"context_guard": "abc"}' | message)
expect_eq "case 7" "CTX GUARD: context at 45 % (threshold 40 %)" "$out"

out=$(run_guard plan 450000 '{"context_guard": "50"}')
expect_eq "case 8" "" "$out"

out=$(CLAUDE_PLUGIN_OPTION_CONTEXT_GUARD=50 run_guard plan 450000 "")
expect_eq "case 9" "" "$out"

limit_head="LIMIT GUARD: account home is at 95 % of the 5-hour limit and 10 % of the 7-day limit (thresholds 90 % 5-hour, 98 % 7-day, read from the status line)"

out=$(limit_5h=95 run_guard plan 10000 "" | message)
expect_eq "case 10" "$limit_head" "$out"

out=$(limit_5h=95 run_guard plan 10000 '{"limit_guard": "off"}')
expect_eq "case 11" "" "$out"

out=$(limit_5h=95 run_guard plan 10000 '{"limit_guard": "on"}' | message)
expect_eq "case 12" "$limit_head" "$out"

out=$(CLAUDE_PLUGIN_OPTION_LIMIT_GUARD=off limit_5h=95 run_guard plan 10000 "")
expect_eq "case 13" "" "$out"

echo "ok: 13 cases"
