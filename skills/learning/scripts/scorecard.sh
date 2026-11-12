#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
header_sessions='stage	repo	n	sid8	session_id	date	skill	transcript	turns	user_turns	handoffs	limit_hits	guard_events	ctx_max_k	cost	cost_main	cost_sub	cost_by_family	sub_agents	tool_errors	max_gap_min	gates	red_gates	final_gate	blocked	fix_rounds	pr	events'

usage() {
  echo "usage: scorecard.sh <rows.tsv> <out dir> | scorecard.sh append <out dir> [<stage>=<post-PR defects> ...]" >&2
  exit 2
}

append() {
  out=$1
  shift
  [ -f "$out/stages.tsv" ] || { echo "no stages.tsv in $out: run flag.sh first" >&2; exit 2; }
  card="$("$here/learning-dir.sh")/scorecard.tsv"
  mkdir -p "$(dirname "$card")"
  header_card=$(head -1 "$out/stages.tsv")
  if [ -f "$card" ] && [ "$(head -1 "$card")" != "$header_card" ]; then
    if [ "$(wc -l < "$card")" -gt 1 ]; then mv "$card" "${card%.tsv}.$(date +%F-%H%M%S).tsv"; else rm -f "$card"; fi
  fi
  [ -f "$card" ] || printf '%s\n' "$header_card" > "$card"
  run=$(awk -F'\t' 'NR == 2 { print $2 }' "$out/stages.tsv")
  if [ -n "$run" ] && awk -F'\t' -v run="$run" 'NR > 1 && $2 == run { found = 1 } END { exit !found }' "$card"; then
    echo "scorecard already holds run $run" >&2
    exit 0
  fi
  awk -F'\t' -v OFS='\t' -v defects="$*" '
    BEGIN { k = split(defects, d, " "); for (i = 1; i <= k; i++) { split(d[i], p, "="); set[p[1]] = p[2] } }
    NR == 1 { for (i = 1; i <= NF; i++) col[$i] = i; next }
    { if ($col["stage"] in set) $col["post_pr_defects"] = set[$col["stage"]]; print }
  ' "$out/stages.tsv" >> "$card"
  echo "$card"
}

[ $# -ge 2 ] || usage
if [ "$1" = append ]; then
  shift
  append "$@"
  exit 0
fi

rows=$1
out=$2
[ -f "$rows" ] || { echo "no rows file: $rows" >&2; exit 2; }
mkdir -p "$out"
projects="$HOME/.claude/projects"
printf '%s\n' "$header_sessions" > "$out/sessions.tsv"

main_filter='
  def ts: (.timestamp // "")[0:16];
  def texts: .message.content | if type == "string" then [.] elif type == "array" then map(if .type == "text" then (.text // "") elif .type == "tool_result" then (.content | if type == "array" then map(.text? // "") | join("\n") elif . == null then "" else tostring end) else "" end) else [] end;
  (select(.timestamp) | ["T", ((.timestamp | sub("\\.[0-9]+"; "") | fromdateiso8601) / 60 | floor)] | @tsv),
  (select(.type == "assistant" and .message.usage) | .message.usage as $u | ["M", "main", (.message.id // .uuid // ""), (.message.model // ""), ($u.input_tokens // 0), ($u.cache_creation_input_tokens // 0), ($u.cache_read_input_tokens // 0), ($u.output_tokens // 0)] | @tsv),
  (select(.type == "user") | ts as $t | (.message.content | arrays | .[] | select(.type == "tool_result" and .is_error == true) | ["E", $t] | @tsv)),
  (select(.type == "user") | ts as $t | texts[] | match("MODE: (gate|local|commit|ship)[ \t]*\n[ \t]*STATUS: (green|red|done|blocked)[ \t]*\n(?<rest>(.|\n){0,1500})"; "g") | ["S", $t, .captures[0].string, .captures[1].string, ((.captures[2].string // "") | (capture("(^|\n)[ \t]*PR: (?<u>https://[^ \n]+/pull/[0-9]+)") | .u) // "none")] | @tsv)
'
sub_filter='select(.type == "assistant" and .message.usage) | .message.usage as $u | ["M", input_filename, (.message.id // .uuid // ""), (.message.model // ""), ($u.input_tokens // 0), ($u.cache_creation_input_tokens // 0), ($u.cache_read_input_tokens // 0), ($u.output_tokens // 0)] | @tsv'

awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) col[$i] = i; next }
  { line = ""; split("stage repo n session_id date skill turns user_turns handoff limit_hits", want, " ")
    for (i = 1; i <= 10; i++) { v = $col[want[i]]; line = line (i > 1 ? "\t" : "") (v == "" ? "-" : v) }
    print line }' "$rows" |
while IFS=$'\t' read -r stage repo n sid date skill turns user_turns handoffs limit_hits; do
  f=$(find "$projects" -mindepth 2 -maxdepth 2 -name "${sid}*.jsonl" 2>/dev/null | head -1)
  if [ -z "$f" ]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\tno\t%s\t%s\t%s\t%s\t0\t0\t0\t0\t0\t-\t0\t0\t0\t0\t0\tnone\t0\t0\tnone\t-\n' "$stage" "$repo" "$n" "${sid:0:8}" "$sid" "$date" "$skill" "$turns" "$user_turns" "$handoffs" "$limit_hits" >> "$out/sessions.tsv"
    continue
  fi
  sub="${f%.jsonl}/subagents"
  {
    jq -r "$main_filter" "$f" 2>/dev/null
    "$here/guards.sh" "$f" 2>/dev/null | sed 's/^\(.\{11\}\).*/G	\1/'
    [ -d "$sub" ] && find "$sub" -name '*.jsonl' -exec jq -r "$sub_filter" {} + 2>/dev/null
  } | awk -F'\t' -v OFS='\t' -v lead="$stage	$repo	$n	${sid:0:8}	$sid	$date	$skill	$f	$turns	$user_turns	$handoffs	$limit_hits" '
    function family(m) { m = tolower(m); if (m ~ /fable/) return "fable"; if (m ~ /opus/) return "opus"; if (m ~ /sonnet/) return "sonnet"; if (m ~ /haiku/) return "haiku"; return "" }
    BEGIN {
      win["fable"] = 8; wout["fable"] = 40; wread["fable"] = 0.20
      win["opus"] = 4; wout["opus"] = 20; wread["opus"] = 0.20
      win["sonnet"] = 2; wout["sonnet"] = 10; wread["sonnet"] = 0.10
      win["haiku"] = 0.10; wout["haiku"] = 0.50; wread["haiku"] = 0.01
      final = "none"; pr = "none"
    }
    $1 == "T" { if (last != "" && $2 - last > gap) gap = $2 - last; last = $2; next }
    $1 == "M" {
      if (seen[$2, $3]++) next
      fam = family($4); if (fam == "") next
      c = ($5 * win[fam] + $6 * win[fam] * 1.25 + $7 * wread[fam] + $8 * wout[fam]) / 1e6
      by[fam] += c
      if ($2 == "main") { cmain += c; ctx = $5 + $6 + $7; if (ctx > ctxmax) ctxmax = ctx } else { csub += c; agents[$2] = 1 }
      next
    }
    $1 == "E" { errors++; next }
    $1 == "G" { guards++; sub(/ /, "T", $2); events = events " guard@" $2; next }
    $1 == "S" {
      if ($3 == "gate") { gates++; final = $4; if ($4 == "red") { red++; events = events " red@" substr($2, 6) } }
      if ($3 == "commit" && $4 == "done") fixes++
      if ($4 == "blocked") { blocked++; events = events " blocked@" substr($2, 6) }
      if ($5 != "none") pr = $5
    }
    END {
      fams = ""
      split("fable opus sonnet haiku", order, " ")
      for (i = 1; i <= 4; i++) if (order[i] in by) fams = fams (fams == "" ? "" : ",") order[i] "=" sprintf("%.2f", by[order[i]])
      na = 0; for (a in agents) na++
      sub(/^ /, "", events)
      print lead, guards + 0, int(ctxmax / 1000), sprintf("%.2f", cmain + csub), sprintf("%.2f", cmain), sprintf("%.2f", csub), (fams == "" ? "-" : fams), na, errors + 0, gap + 0, gates + 0, red + 0, final, blocked + 0, fixes + 0, pr, (events == "" ? "-" : events)
    }
  ' >> "$out/sessions.tsv"
done
echo "$out/sessions.tsv"
