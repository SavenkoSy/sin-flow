#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$root/bin:$PATH"
unset FLOW_CONFIG_DIR CLAUDE_CODE_ENTRYPOINT
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

clean_env() { env -u TMUX -u CMUX_WORKSPACE_ID -u ORCA_TERMINAL_HANDLE -u __CFBundleIdentifier -u TERM_PROGRAM "$@"; }

fresh_home auto
out=$(clean_env ORCA_TERMINAL_HANDLE=term_1 sin-flow-handoff --detect)
expect_eq "case 13" orca "$out"

out=$(clean_env __CFBundleIdentifier=com.stablyai.orca sin-flow-handoff --detect)
expect_eq "case 14" orca "$out"

out=$(clean_env TMUX=/tmp/tmux-1,1,0 ORCA_TERMINAL_HANDLE=term_1 sin-flow-handoff --detect)
expect_eq "case 15" tmux "$out"

out=$(clean_env TERM_PROGRAM=Foo sin-flow-handoff --detect)
expect_eq "case 16" "none — checked: TMUX unset, CMUX_WORKSPACE_ID unset, ORCA_TERMINAL_HANDLE unset, __CFBundleIdentifier=unset, TERM_PROGRAM=Foo" "$out"

fresh_home orca
out=$(clean_env sin-flow-handoff --detect)
expect_eq "case 17" orca "$out"

rc=0
out=$(clean_env sin-flow-handoff --probe --cwd "$plain" --prompt x) || rc=$?
expect_eq "case 18 rc" 0 "$rc"
case "$out" in "orca terminal create"*) ;; *) fail "case 18: got $out" ;; esac

fake=$(mktemp -d "$scratch/fake.XXXXXX")
printf '#!/bin/sh\n' > "$fake/tmux"
chmod +x "$fake/tmux"
rc=0
out=$(PATH="$root/bin:/usr/bin:/bin" sin-flow-handoff --check orca) || rc=$?
expect_eq "case 19 orca rc" 3 "$rc"
expect_eq "case 19 orca" "orca: the orca command is not on PATH (Orca puts it in ORCA_CLI_BIN_DIR)" "$out"
out=$(PATH="$fake:$root/bin:/usr/bin:/bin" sin-flow-handoff --check tmux)
expect_eq "case 19 tmux" ok "$out"
rc=0
out=$(sin-flow-handoff --check foo) || rc=$?
expect_eq "case 19 foo rc" 2 "$rc"
expect_eq "case 19 foo" "no adapter for foo" "$out"

safe_path="$root/bin:/usr/bin:/bin"

rc=0
out=$(PATH="$safe_path" sin-flow-handoff --check tmux) || rc=$?
expect_eq "case 20 tmux missing rc" 3 "$rc"
expect_eq "case 20 tmux missing" "tmux: the tmux command is not on PATH" "$out"

rc=0
out=$(clean_env PATH="$safe_path" sin-flow-handoff --check cmux) || rc=$?
expect_eq "case 21 cmux missing rc" 3 "$rc"
expect_eq "case 21 cmux missing" "cmux: the cmux command is not on PATH" "$out"

printf '#!/bin/sh\n' > "$fake/cmux"
chmod +x "$fake/cmux"
rc=0
out=$(clean_env PATH="$fake:$safe_path" sin-flow-handoff --check cmux) || rc=$?
expect_eq "case 21 cmux no workspace rc" 3 "$rc"
expect_eq "case 21 cmux no workspace" "cmux: this session is not inside a cmux workspace" "$out"
out=$(clean_env CMUX_WORKSPACE_ID=ws_1 PATH="$fake:$safe_path" sin-flow-handoff --check cmux)
expect_eq "case 21 cmux ok" ok "$out"

open_fail=$(mktemp -d "$scratch/openfail.XXXXXX")
printf '#!/bin/sh\nexit 1\n' > "$open_fail/open"
open_ok=$(mktemp -d "$scratch/openok.XXXXXX")
printf '#!/bin/sh\nexit 0\n' > "$open_ok/open"
chmod +x "$open_fail/open" "$open_ok/open"
for row in iterm:iTerm ghostty:Ghostty warp:Warp; do
  terminal=${row%%:*}
  app=${row##*:}
  rc=0
  out=$(PATH="$open_fail:$safe_path" sin-flow-handoff --check "$terminal") || rc=$?
  expect_eq "case 22 $terminal rc" 3 "$rc"
  expect_eq "case 22 $terminal" "$terminal: the $app app is not installed" "$out"
  out=$(PATH="$open_ok:$safe_path" sin-flow-handoff --check "$terminal")
  expect_eq "case 22 $terminal ok" ok "$out"
done

fresh_home tmux
out=$(clean_env sin-flow-handoff --detect)
expect_eq "case 23 detect" tmux "$out"
out=$(clean_env sin-flow-handoff --probe --cwd "$plain" --prompt x)
case "$out" in "tmux new-window"*) ;; *) fail "case 23 probe: got $out" ;; esac

echo "ok: 23 cases"
