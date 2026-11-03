#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export FLOW_HOME="$scratch/home"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
today=$(date '+%F')
cases=0

fail() { echo "FAIL: $*" >&2; exit 1; }

expect_eq() {
  cases=$((cases + 1))
  [ "$2" = "$3" ] || fail "$1: want [$2], got [$3]"
}

stop() {
  echo '{}' | bash "$root/hooks/scripts/work-commit.sh"
  for _ in $(seq 50); do
    [ -z "$(jobs -p)" ] && [ -z "$(pgrep -f "git -C $FLOW_HOME push" || true)" ] && break
    sleep 0.1
  done
}

count() { git -C "$FLOW_HOME" rev-list --count "${1:-HEAD}"; }

mkdir -p "$FLOW_HOME/work"
printf '/*\n!/.gitignore\n!/work/\n' > "$FLOW_HOME/.gitignore"
git -C "$FLOW_HOME" init -q -b main
git -C "$FLOW_HOME" add .gitignore && git -C "$FLOW_HOME" commit -q -m "autosave 2026-01-01 10:00:00"

echo a > "$FLOW_HOME/work/a"
stop
expect_eq "first stop of the day commits" "2" "$(count)"
expect_eq "subject is the day" "autosave $today" "$(git -C "$FLOW_HOME" log -1 --format=%s)"

echo b > "$FLOW_HOME/work/b"
stop
echo c > "$FLOW_HOME/work/c"
stop
expect_eq "later stops amend" "2" "$(count)"
expect_eq "amend keeps the files" "work/a work/b work/c" "$(git -C "$FLOW_HOME" show --name-only --format= HEAD | sort | tr '\n' ' ' | sed 's/ $//')"

stop
expect_eq "no change, no commit" "2" "$(count)"

dd if=/dev/zero of="$FLOW_HOME/work/big.log" bs=1m count=51 2>/dev/null
echo g > "$FLOW_HOME/work/g"
stop
expect_eq "big new file stays out" "" "$(git -C "$FLOW_HOME" ls-files work/big.log)"
expect_eq "small file next to it goes in" "work/g" "$(git -C "$FLOW_HOME" ls-files work/g)"

dd if=/dev/zero of="$FLOW_HOME/work/grown.log" bs=1m count=1 2>/dev/null
stop
expect_eq "small log is tracked" "work/grown.log" "$(git -C "$FLOW_HOME" ls-files work/grown.log)"
dd if=/dev/zero of="$FLOW_HOME/work/grown.log" bs=1m count=51 2>/dev/null
stop
expect_eq "log that grew past the limit leaves the index" "" "$(git -C "$FLOW_HOME" ls-files work/grown.log)"
expect_eq "file stays on disk" "1" "$([ -f "$FLOW_HOME/work/grown.log" ] && echo 1)"

git init -q --bare "$scratch/remote.git"
git -C "$FLOW_HOME" remote add origin "$scratch/remote.git"
echo d > "$FLOW_HOME/work/d"
stop
for _ in $(seq 50); do [ -f "$FLOW_HOME/.last-push" ] && break; sleep 0.1; done
expect_eq "push marks the day" "$today" "$(cat "$FLOW_HOME/.last-push")"
git -C "$FLOW_HOME" fetch -q origin
expect_eq "pushed head" "$(git -C "$FLOW_HOME" rev-parse HEAD)" "$(git -C "$FLOW_HOME" rev-parse origin/main)"

echo e > "$FLOW_HOME/work/e"
stop
echo f > "$FLOW_HOME/work/f"
stop
expect_eq "pushed commit is never amended" "1" "$(count origin/main..HEAD)"
expect_eq "pushed history intact" "0" "$(count HEAD..origin/main)"

echo "ok: $cases cases"
