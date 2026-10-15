#!/bin/bash
s="${1%.jsonl}/subagents"
[ -d "$s" ] || exit 0
for m in "$s"/*.meta.json; do
  j="${m%.meta.json}.jsonl"
  d=$(jq -r '.description // .agentType // "?"' "$m")
  jq -rs --arg d "$d" '[.[] | select(.type=="assistant" and .message.usage)] as $a
    | [$d, ($a[0].message.model // "?" | sub("claude-";"") | sub("-5-5";"")), ($a|length),
       ([$a[].message.content[]? | select(.type=="tool_use")] | length),
       (([$a[].message.usage.cache_read_input_tokens // 0] | add // 0)/1e6*10|round/10),
       (([$a[].message.usage.cache_creation_input_tokens // 0] | add // 0)/1e3|round),
       (([$a[].message.usage.output_tokens // 0] | add // 0)/1e3|round),
       ($a[0].timestamp[11:16] // "")] | @tsv' "$j"
done | sort -t$'\t' -k8
