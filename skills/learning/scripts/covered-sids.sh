#!/usr/bin/env bash
set -euo pipefail
learning="${1:-$("$(dirname "$0")/learning-dir.sh")}"
for f in "$learning"/*/*.md; do
  awk '
    /^## / { exit }
    tolower($0) ~ /sessions covered|^[-* ]*covered:/ { on = 1; print; next }
    on && (/^[[:space:]]*$/ || (/^(- |\*\*|[A-Z][A-Za-z'"'"' ]*:)/ && !/^- `?[0-9a-f]{8}/)) { on = 0 }
    on { print }
  ' "$f"
done 2>/dev/null | grep -oE '[0-9a-f]{8}' | sort -u || true
