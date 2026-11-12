#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
gate="$root/bin/sin-flow-gate"
work="$scratch/work"
cases=0

fail() { echo "FAIL: $*" >&2; exit 1; }

expect_eq() {
  cases=$((cases + 1))
  [ "$2" = "$3" ] || fail "$1: want [$2], got [$3]"
}

expect_exit() {
  local name=$1 want=$2 got=0
  shift 2
  "$@" >/dev/null 2>&1 || got=$?
  expect_eq "$name" "$want" "$got"
}

mkdir -p "$work" "$scratch/repo" "$scratch/empty" "$scratch/plain"
cd "$scratch/repo"
git init -q -b main
echo one > tracked.txt
git add tracked.txt
git commit -q -m base
base=$(git rev-parse HEAD)

echo 'echo "3 examples, 0 failures"' > "$work/pass.commands"
echo 'echo "3 examples, 1 failure"; exit 1' > "$work/fail.commands"
echo 'true' > "$work/true.commands"

expect_exit "no record at all refuses" 1 bash "$gate" green-for "$work" "$base"
expect_exit "a missing work folder refuses" 1 bash "$gate" green-for "$scratch/absent" "$base"

echo two > tracked.txt
echo new > added.txt
expect_eq "green run prints green" "green" "$(bash "$gate" run "$work/gate-final.log" "$work/pass.commands")"
expect_eq "green run writes the record" "1" "$([ -f "$work/gate-final.log.green" ] && echo 1)"
expect_eq "record names the head" "head $base" "$(sed -n 1p "$work/gate-final.log.green")"
expect_eq "green run keeps the tail" "1" "$([ -f "$work/gate-final.log.tail" ] && echo 1)"
expect_eq "log keeps the entry line" "=== exit 0 · tests 3 ===" "$(tail -1 "$work/gate-final.log")"
expect_exit "the head under the tested changes refuses" 1 bash "$gate" green-for "$work" "$base"
expect_eq "refusal line" "no green gate for $base" "$(bash "$gate" green-for "$work" "$base" || true)"

git add tracked.txt added.txt
git commit -q -m work
tested=$(git rev-parse HEAD)
expect_exit "the commit of the tested tree passes" 0 bash "$gate" green-for "$work" "$tested"
expect_eq "pass line" "green gate for $tested" "$(bash "$gate" green-for "$work" "$tested")"
expect_exit "another work folder refuses" 1 bash "$gate" green-for "$scratch/empty" "$tested"

echo three > tracked.txt
git commit -q -am later
later=$(git rev-parse HEAD)
expect_exit "a commit after the gate refuses" 1 bash "$gate" green-for "$work" "$later"
expect_exit "an unknown sha refuses" 1 bash "$gate" green-for "$work" 0000000000000000000000000000000000000000

expect_eq "true-only run prints green" "green" "$(bash "$gate" run "$work/gate-canary-1.log" "$work/true.commands")"
expect_eq "true-only run writes no record" "" "$(ls "$work/gate-canary-1.log.green" 2>/dev/null)"
expect_exit "true-only run does not open the ship" 1 bash "$gate" green-for "$work" "$later"

echo note > untracked-note.md
expect_eq "green run on the committed tree" "green" "$(bash "$gate" run "$work/gate-fix.log" "$work/pass.commands")"
expect_exit "an untracked file left out of the commit still passes" 0 bash "$gate" green-for "$work" "$later"

expect_eq "red run prints red" "red: echo \"3 examples, 1 failure\"; exit 1 (exit 1)" "$(bash "$gate" run "$work/gate-fix.log" "$work/fail.commands" || true)"
expect_eq "red run removes the old record" "" "$(ls "$work/gate-fix.log.green" 2>/dev/null)"
expect_exit "red run closes the ship" 1 bash "$gate" green-for "$work" "$later"

cd "$scratch/plain"
expect_eq "green run outside a repo prints green" "green" "$(bash "$gate" run "$work/gate-plain.log" "$work/pass.commands")"
expect_eq "green run outside a repo writes no record" "" "$(ls "$work/gate-plain.log.green" 2>/dev/null)"
cd "$scratch/repo"

expect_eq "verdict without a canary log" "Unit u1: complete (abc123, audit clean)" "$(bash "$gate" verdict "$work" u1 abc123 clean)"
printf 'CANARY none: no code file in the unit\n' > "$work/canary-u2.log"
expect_eq "verdict with canary none" "Unit u2: complete (abc123, audit clean, canary none)" "$(bash "$gate" verdict "$work" u2 abc123 clean)"
printf 'CANARY reverted: green\nCANARY restored: green tests 4\n' > "$work/canary-u3.log"
expect_eq "verdict with a green revert" "Unit u3: not proven: its specs pass with its code reverted" "$(bash "$gate" verdict "$work" u3 abc123 clean)"
printf 'CANARY reverted: red\nCANARY restored: green tests 4\n' > "$work/canary-u4.log"
expect_eq "verdict with a red revert" "Unit u4: complete (abc123, audit skipped, canary red, 4 tests)" "$(bash "$gate" verdict "$work" u4 abc123 skipped)"
: > "$work/canary-u5.log"
expect_eq "verdict with an empty canary log" "Unit u5: not proven: its specs fail with its code in place" "$(bash "$gate" verdict "$work" u5 abc123 clean)"

echo "ok: $cases cases"
