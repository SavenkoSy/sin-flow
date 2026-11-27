#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$root/bin:$PATH"
unset FLOW_CONFIG_DIR CLAUDE_CODE_ENTRYPOINT $(compgen -e | grep '^CLAUDE_PLUGIN_OPTION_' || true)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

FLOW_HOME="$scratch/home"
CLAUDE_CONFIG_DIR=$FLOW_HOME
export FLOW_HOME CLAUDE_CONFIG_DIR
mkdir -p "$FLOW_HOME"
jq -n '{pluginConfigs: {"sin-flow@test": {options: {workspace: "git"}}}}' > "$CLAUDE_CONFIG_DIR/settings.json"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

git init -q --bare -b main "$scratch/origin.git"
git clone -q "$scratch/origin.git" "$scratch/repo" 2>/dev/null
repo="$scratch/repo"
git -C "$repo" commit -q --allow-empty -m base
git -C "$repo" push -q origin main

git -C "$repo" switch -q -c epic-1
git -C "$repo" commit -q --allow-empty -m story
git -C "$repo" push -q origin epic-1
git -C "$repo" switch -q main
git -C "$scratch/origin.git" branch -q -D epic-1

out=$(sin-flow-worktree --repo "$repo" --name 1-2-x --branch epic-1 --base origin/main 2>"$scratch/err") || fail "case 1: pushed and gone branch refused: $(cat "$scratch/err")"
grep -q '^state: new$' <<<"$out" || fail "case 1: pushed and gone branch, want state new, got [$out]"
grep -q '^deleted stale branch epic-1' "$scratch/err" || fail "case 1: want the deleted line on stderr"
[ "$(git -C "$repo" rev-parse epic-1)" = "$(git -C "$repo" rev-parse origin/main)" ] || fail "case 1: new branch is not on the base"
git -C "$repo" worktree remove "$repo/.claude/worktrees/1-2-x"
git -C "$repo" branch -q -D epic-1

git -C "$repo" switch -q -c epic-2
git -C "$repo" commit -q --allow-empty -m story
git -C "$repo" push -q origin epic-2
git -C "$repo" commit -q --allow-empty -m unpushed
git -C "$repo" switch -q main
git -C "$scratch/origin.git" branch -q -D epic-2
rc=0
sin-flow-worktree --repo "$repo" --name 2-1-x --branch epic-2 --base origin/main >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "case 2: unpushed commit, want exit 1, got $rc"
git -C "$repo" rev-parse -q --verify refs/heads/epic-2 >/dev/null || fail "case 2: branch with unpushed work was deleted"

git -C "$repo" switch -q -c epic-3
git -C "$repo" commit -q --allow-empty -m story
git -C "$repo" push -q origin epic-3
git -C "$repo" switch -q main
rc=0
sin-flow-worktree --repo "$repo" --name 3-1-x --branch epic-3 --base origin/main >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "case 3: branch still on origin, want exit 1, got $rc"

git -C "$repo" switch -q -c local-only
git -C "$repo" switch -q main
rc=0
sin-flow-worktree --repo "$repo" --name 4-1-x --branch local-only --base origin/main >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "case 4: never pushed, want exit 1, got $rc"

echo "worktree: 4 cases ok"
