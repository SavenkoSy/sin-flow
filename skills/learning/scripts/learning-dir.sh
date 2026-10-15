#!/usr/bin/env bash
set -uo pipefail
home="${FLOW_HOME:-$HOME/.claude/sin-flow}"
dir="${FLOW_LEARNING_DIR:-}"
if [ -z "$dir" ] && [ -f "$home/user.md" ]; then
  dir=$(sed -n 's/^learning_dir:[[:space:]]*//p' "$home/user.md" | sed 's/[[:space:]]#.*//; s/^"//; s/"$//' | head -1)
fi
[ -n "$dir" ] || dir="$home/learning"
case "$dir" in "~"/*) dir="$HOME/${dir#\~/}" ;; esac
printf '%s\n' "$dir"
