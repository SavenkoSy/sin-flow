#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
[ $# -eq 2 ] || { echo "usage: turns.sh <out dir of scorecard.sh> <stage>" >&2; exit 2; }
awk -F'\t' -v stage="$2" 'NR == 1 { for (i = 1; i <= NF; i++) col[$i] = i; next }
  $col["stage"] == stage && $col["transcript"] != "no" && $col["user_turns"] > 0 { print $col["sid8"] "\t" $col["repo"] "\t" $col["n"] "\t" $col["transcript"] }' "$1/sessions.tsv" |
while IFS=$'\t' read -r sid8 repo n file; do
  printf '## %s %s %s\n' "$sid8" "$repo" "$n"
  "$here/dump.sh" "$file" | awk '
    / (ASSISTANT|CMD): / { if (after) { print; after = 0 } before = $0; next }
    / USER(\(queued\))?: / { if (before != "") print before; before = ""; print; after = 1 }
  '
done
