#!/usr/bin/env bash
set -uo pipefail
home="${FLOW_HOME:-$HOME/.claude/sin-flow}"
dir="${FLOW_LEARNING_DIR:-}"
[ -n "$dir" ] || dir=$("$(dirname "$0")/../../../bin/sin-flow-profile" user learning_dir 2>/dev/null)
[ -n "$dir" ] || dir="$home/learning"
case "$dir" in "~"/*) dir="$HOME/${dir#\~/}" ;; esac
printf '%s\n' "$dir"
