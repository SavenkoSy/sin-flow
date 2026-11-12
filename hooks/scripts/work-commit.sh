#!/usr/bin/env bash
set -euo pipefail

root="${FLOW_HOME:-$HOME/.claude/sin-flow}"
log="$root/stop-commit.log"
pushed="$root/.last-push"
pushing="$root/.pushing"
lock="$root/.autosave.lock"
STALE_LOCK_MINUTES=10
cat >/dev/null 2>&1 || true
[ -d "$root/.git" ] || exit 0
if ! mkdir "$lock" 2>/dev/null; then
  [ -n "$(find "$lock" -maxdepth 0 -mmin "+$STALE_LOCK_MINUTES" 2>/dev/null)" ] || exit 0
  rmdir "$lock" 2>/dev/null || true
  mkdir "$lock" 2>/dev/null || exit 0
fi
trap 'rmdir "$lock" 2>/dev/null || true' EXIT
stamp=$(date '+%F %T')
today=$(date '+%F')
big=$(cd "$root" && find work profiles -type f -size +50M 2>/dev/null || true)
printf '%s\n' "$big" | sed '/^$/d; s|^|/|' >"$root/.git/info/exclude"
if [ -n "$big" ]; then
  printf '%s\n' "$big" | tr '\n' '\0' |
    (cd "$root" && xargs -0 git rm -q -r --cached --ignore-unmatch --) >/dev/null 2>>"$log" || true
fi
if ! git -C "$root" add -A >/dev/null 2>>"$log"; then
  printf '%s\tadd failed\n' "$stamp" >>"$log"
  exit 0
fi
if ! git -C "$root" diff --cached --quiet; then
  amend=
  if [ "$(git -C "$root" log -1 --format=%s 2>/dev/null)" = "autosave $today" ] &&
    [ -z "$(git -C "$root" branch -r --contains HEAD 2>/dev/null)" ] &&
    [ "$(cat "$pushing" 2>/dev/null)" != "$(git -C "$root" rev-parse HEAD)" ]; then
    amend=--amend
  fi
  if git -C "$root" commit -q $amend -m "autosave $today" >/dev/null 2>>"$log"; then
    printf '%s\tcommitted\t%s\n' "$stamp" "$(git -C "$root" rev-parse --short HEAD)" >>"$log"
  else
    printf '%s\tcommit failed\n' "$stamp" >>"$log"
  fi
fi
[ "$(cat "$pushed" 2>/dev/null)" = "$today" ] && exit 0
git -C "$root" remote get-url origin >/dev/null 2>&1 || exit 0
head=$(git -C "$root" rev-parse HEAD)
branch=$(git -C "$root" branch --show-current)
printf '%s' "$head" >"$pushing"
trap - EXIT
(
  if git -C "$root" push -q origin "$head:refs/heads/$branch" >/dev/null 2>>"$log"; then
    printf '%s' "$today" >"$pushed"
    printf '%s\tpushed\n' "$(date '+%F %T')" >>"$log"
  else
    printf '%s\tpush failed\n' "$(date '+%F %T')" >>"$log"
  fi
  rmdir "$lock" 2>/dev/null || true
  rm -f "$pushing"
) </dev/null >/dev/null 2>&1 &
exit 0
