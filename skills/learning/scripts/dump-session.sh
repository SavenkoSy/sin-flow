#!/bin/bash
set -uo pipefail
sid="$1"
out="$2"
here="$(cd "$(dirname "$0")" && pwd)"
s8="${sid:0:8}"
f=$(find "$HOME/.claude/projects" -mindepth 2 -maxdepth 2 -name "${sid}*.jsonl" 2>/dev/null | head -1)
mkdir -p "$out"
if [ -z "$f" ]; then printf '%s\tno transcript under ~/.claude/projects/*/\n' "$sid" >> "$out/missing.txt"; exit 0; fi
printf '%s\t%s\n' "$s8" "$f" >> "$out/transcripts.tsv"
"$here/dump.sh" "$f" > "$out/$s8.txt"
"$here/ctx.sh" "$f" > "$out/$s8.ctx"
"$here/guards.sh" "$f" > "$out/$s8.guards"
"$here/per-agent.sh" "$f" > "$out/$s8.agents.tsv"
jq -rs '[.[] | select(.type=="assistant") | ((.timestamp // "")[5:16] | sub("T";" ")) as $t | .message.content[]? | select(.type=="text" and (.text | length) >= 300) | "=== \($t) ===\n\(.text)"] | join("\n\n")' "$f" > "$out/$s8.long.txt"
jq -r '((.timestamp // "")[5:16] | sub("T";" ")) as $t | select(.type=="user") | .message.content | arrays | .[] | select(.type=="tool_result" and .is_error==true) | "\($t) ERROR: \(.content | if type=="array" then map(.text? // "") | join(" ") else tostring end | gsub("\n";" ") | .[:200])"' "$f" > "$out/$s8.errors"
jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | .input | (.content // .new_string // .command // empty) | strings' "$f" | grep -oE 'ingest-miss:.{0,250}' | sort -u > "$out/$s8.misses"
jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | .input.file_path // empty | select(endswith("progress.md"))' "$f" | sort -u > "$out/$s8.ledger-paths"
printf '%s\t%s\n' "$s8" "$("$here/stats.sh" "$f" | tr '\n' ' ')" >> "$out/stats.txt"
