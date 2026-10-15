#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$root/bin:$PATH"
unset FLOW_CONFIG_DIR
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

fresh_home() {
  FLOW_HOME=$(mktemp -d "$scratch/home.XXXXXX")
  export FLOW_HOME
  printf 'handoff: %s\n' "$1" > "$FLOW_HOME/user.md"
}

expect_eq() {
  [ "$2" = "$3" ] || fail "$1: want [$2], got [$3]"
}

plain=$(mktemp -d "$scratch/plain.XXXXXX")
touch "$plain/x.md"

fresh_home print
want=$(sin-flow-profile model strong "$plain")
out=$(sin-flow-handoff --probe --cwd "$plain" --name launch-posts --prompt "Continue the posts" | sed -n 2p)
expect_eq "case 1" "cd '$plain' && claude -n 'launch-posts' --model '$want' 'Continue the posts'" "$out"

fresh_home print
out=$(sin-flow-handoff --probe --cwd "$plain" --prompt "it's done" | sed -n 2p)
case "$out" in *"'it'\\''s done'"*) ;; *) fail "case 2: got $out" ;; esac

fresh_home same-session
rc=0
out=$(sin-flow-handoff --probe --prompt "go on") || rc=$?
expect_eq "case 3 rc" 0 "$rc"
expect_eq "case 3" "continue in this session: go on" "$out"

fresh_home "$scratch/script.sh"
printf '#!/usr/bin/env bash\necho "$*"\necho "$FLOW_PROMPT"\n' > "$scratch/script.sh"
chmod +x "$scratch/script.sh"
want=$(sin-flow-profile model strong "$PWD")
out=$(sin-flow-handoff --probe --name t --prompt "go on")
expect_eq "case 4" "--probe --name t --prompt go on
claude -n 't' --model '$want' 'go on'" "$out"

fresh_home print
rc=0
err=$(sin-flow-handoff --probe --prompt x sin-flow:plan "$plain/x.md" 2>&1 >/dev/null) || rc=$?
expect_eq "case 5 rc" 2 "$rc"
expect_eq "case 5" "--prompt takes no stage or target: sin-flow:plan $plain/x.md" "$err"

fresh_home print
out=$(sin-flow-handoff --probe --cwd "$plain" --prompt x | sed -n 2p)
case "$out" in *"claude -n 'continue-"[0-9]*"' --model"*) ;; *) fail "case 6: got $out" ;; esac
case "$out" in *"claude -n 'continue-"*[!0-9]"' --model"*) fail "case 6 digits: got $out" ;; esac

fresh_home print
out=$(sin-flow-handoff --probe --cwd "$plain" --goal "PR open" --prompt "ship it" | sed -n 2p)
case "$out" in *"'/goal PR open To reach the condition: ship it'") ;; *) fail "case 7: got $out" ;; esac

fresh_home print
out=$(sin-flow-handoff --probe sin-flow:plan "$plain/x.md" | sed -n 2p)
case "$out" in *"'/sin-flow:plan $plain/x.md'") ;; *) fail "case 8: got $out" ;; esac

fresh_home print
cfg=$(mktemp -d "$scratch/cfg.XXXXXX")
out=$(FLOW_CONFIG_DIR="$cfg" sin-flow-handoff --probe --cwd "$plain" --prompt x | sed -n 2p)
case "$out" in "cd '$plain' && CLAUDE_CONFIG_DIR='$cfg' claude"*) ;; *) fail "case 9: got $out" ;; esac

fresh_home print
rc=0
err=$(sin-flow-handoff --probe --cwd "$plain" --name launch-posts "Continue writing the launch posts" 2>&1 >/dev/null) || rc=$?
expect_eq "case 10 rc" 2 "$rc"
case "$err" in "usage: sin-flow-handoff "*) ;; *) fail "case 10: got $err" ;; esac

rc=0
err=$(sin-flow-handoff --probe --cwd "$plain" --prompt "-rf" 2>&1 >/dev/null) || rc=$?
expect_eq "case 11 rc" 2 "$rc"
expect_eq "case 11" "--prompt must not start with -" "$err"

fresh_home same-session
out=$(sin-flow-handoff --probe --goal "PR open" --prompt "ship it")
expect_eq "case 12" "continue in this session: /goal PR open To reach the condition: ship it" "$out"

echo "ok: 12 cases"
