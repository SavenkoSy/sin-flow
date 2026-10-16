#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$root"
unset CTX_GUARD_THRESHOLD
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

expect_eq() {
  [ "$2" = "$3" ] || fail "$1: want [$2], got [$3]"
}

run_guard() {
  local stage=$1 tokens=$2 user_md=$3 sid transcript
  sid="case-$RANDOM-$RANDOM"
  HOME=$(mktemp -d "$scratch/home.XXXXXX")
  export HOME
  mkdir -p "$HOME/.claude/sin-flow"
  [ -z "$user_md" ] || printf '%s\n' "$user_md" > "$HOME/.claude/sin-flow/user.md"
  transcript="$HOME/transcript.jsonl"
  jq -cn --arg c "<command-name>/sin-flow:$stage</command-name><command-args>GH-1</command-args>" '{type:"user",message:{content:$c}}' > "$transcript"
  jq -cn --argjson t "$tokens" '{type:"assistant",message:{usage:{input_tokens:$t}}}' >> "$transcript"
  if [ -n "${used_pct:-}" ]; then
    mkdir -p "$HOME/.claude/state/sessions"
    jq -cn --argjson u "$used_pct" '{used_pct:$u}' > "$HOME/.claude/state/sessions/$sid.json"
  fi
  jq -cn --arg sid "$sid" --arg tp "$transcript" '{session_id:$sid,transcript_path:$tp}' | bash "$root/hooks/scripts/ctx-guard.sh"
}

message() { jq -r '.hookSpecificOutput.additionalContext // empty' | cut -d. -f1; }

out=$(run_guard setup 900000 "")
expect_eq "case 1" "" "$out"

out=$(run_guard plan 450000 "" | message)
expect_eq "case 2" "CTX GUARD: context at 45 % (threshold 40 %)" "$out"

out=$(run_guard plan 450000 "context_guard: 50")
expect_eq "case 3" "" "$out"

out=$(CTX_GUARD_THRESHOLD=30 run_guard plan 450000 "context_guard: 50" | message)
expect_eq "case 4" "CTX GUARD: context at 45 % (threshold 30 %)" "$out"

out=$(run_guard plan 450000 "context_window: 200000" | message)
expect_eq "case 5" "CTX GUARD: context at 45 % (threshold 40 %)" "$out"

out=$(used_pct=55 run_guard plan 10000 "" | message)
expect_eq "case 6" "CTX GUARD: context at 55 % (threshold 40 %)" "$out"

echo "ok: 6 cases"
