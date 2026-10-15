#!/usr/bin/env bash
set -uo pipefail
root="${1:-${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/../../..}}"
root=$(cd "$root" 2>/dev/null && pwd -P) || { echo user; exit 0; }
case "$root/" in */plugins/cache/*) echo user; exit 0 ;; esac
[ "$(git -C "$root" rev-parse --is-inside-work-tree 2>/dev/null)" = true ] || { echo user; exit 0; }
gitdir=$(git -C "$root" rev-parse --absolute-git-dir 2>/dev/null) && [ -w "$gitdir" ] || { echo user; exit 0; }
echo author
