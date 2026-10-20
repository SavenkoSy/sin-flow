#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wrapper="$root/bin/sin-flow-statusline"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

expect_eq() {
  [ "$2" = "$3" ] || fail "$1: want [$2], got [$3]"
}

fresh_home() {
  HOME=$(mktemp -d "$scratch/home.XXXXXX")
  export HOME
}

fresh_home
stdin=$(jq -cn --arg tp "$HOME/cfg/projects/p/s1.jsonl" '{session_id:"s1",transcript_path:$tp,rate_limits:{five_hour:{used_percentage:95},seven_day:{used_percentage:40}},context_window:{used_percentage:12}}')
out=$(printf '%s' "$stdin" | sh "$wrapper")
expect_eq "case 1 stdout" "Claude · 12 %" "$out"
expect_eq "case 1 state" "{\"used_pct\":12,\"limit_5h\":95,\"limit_7d\":40,\"config_home\":\"$HOME/cfg\"}" "$(cat "$HOME/.claude/state/sessions/s1.json")"

fresh_home
stdin='{"session_id":"s2","note":"a\nb","context_window":{"used_percentage":5}}'
out=$(printf '%s' "$stdin" | sh "$wrapper" cat)
expect_eq "case 2" "$stdin" "$out"

fresh_home
out=$(printf '%s' '{"session_id":"s3"}' | sh "$wrapper" "printf '%s' \"it's\"")
expect_eq "case 3" "it's" "$out"

fresh_home
out=$(printf '%s' '{"session_id":"s4","context_window":{"used_percentage":5}}' | sh "$wrapper" 'echo ran')
expect_eq "case 4 stdout" "ran" "$out"
expect_eq "case 4 state" "null" "$(jq -c '.limit_5h' "$HOME/.claude/state/sessions/s4.json")"

fresh_home
status=0
out=$(printf '%s' 'not json' | sh "$wrapper" 'echo ok') || status=$?
expect_eq "case 5 stdout" "ok" "$out"
expect_eq "case 5 exit" "0" "$status"
[ ! -e "$HOME/.claude/state/sessions" ] || [ -z "$(ls "$HOME/.claude/state/sessions")" ] || fail "case 5: state file written"

fresh_home
out=$(printf '%s' 'not json' | sh "$wrapper")
expect_eq "case 6" "Claude" "$out"

fresh_home
stdin=$(jq -cn --arg tp "$HOME/projects/cfg/projects/p/s7.jsonl" '{session_id:"s7",transcript_path:$tp}')
printf '%s' "$stdin" | sh "$wrapper" true
expect_eq "case 7" "$HOME/projects/cfg" "$(jq -r '.config_home' "$HOME/.claude/state/sessions/s7.json")"

fresh_home
out=$(printf '%s' '{"session_id":"s8"}' | sh "$wrapper" 'cat <(echo y)')
expect_eq "case 8" "y" "$out"

fresh_home
out=$(printf '%s' '{"session_id":"s9","context_window":"x"}' | sh "$wrapper" 'echo ran')
expect_eq "case 9 stdout" "ran" "$out"
expect_eq "case 9 leftovers" "" "$(find "$HOME/.claude/state/sessions" -name '*.json*')"

echo "ok: 9 cases"
