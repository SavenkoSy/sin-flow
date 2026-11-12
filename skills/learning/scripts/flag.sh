#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
[ $# -ge 1 ] || { echo "usage: flag.sh <out dir of scorecard.sh> [run date]" >&2; exit 2; }
out=$(cd "$1" && pwd)
day=${2:-$(date +%F)}
[ -f "$out/sessions.tsv" ] || { echo "no sessions.tsv in $out: run scorecard.sh first" >&2; exit 2; }
per_reader=10
per_pr_reader=20
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

stat_of() {
  awk -F'\t' -v c="$1" 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == c) k = i; next } $8 != "no" { print $1 "\t" $k }' "$out/sessions.tsv" |
    sort -t$'\t' -k1,1 -k2,2n |
    awk -F'\t' -v OFS='\t' -v c="$1" '
      { n[$1]++; v[$1, n[$1]] = $2 }
      END {
        for (st in n) {
          k = n[st]; m = int((k + 1) / 2)
          print st, c "_median", (k % 2 ? v[st, m] : (v[st, m] + v[st, m + 1]) / 2)
          i = int(0.9 * k) + 1; if (i > k) i = k
          print st, c "_p90", v[st, i]
        }
      }'
}
{ stat_of user_turns; stat_of cost; stat_of ctx_max_k; stat_of turns; } > "$tmp/stats"

awk -F'\t' -v OFS='\t' '
  FILENAME == ARGV[1] { stat[$1, $2] = $3; next }
  FNR == 1 { for (i = 1; i <= NF; i++) col[$i] = i; next }
  {
    st = $col["stage"]; r = ""
    if ($col["transcript"] == "no") { print st, $col["repo"], $col["n"], $col["sid8"], $col["session_id"], "missing", "-", $col["events"]; next }
    if ($col["user_turns"] + 0 > stat[st, "user_turns_median"] + 0) r = r ",turns"
    if ($col["guard_events"] + $col["limit_hits"] > 0) r = r ",guard"
    if ($col["final_gate"] == "red" || $col["blocked"] > 0) r = r ",gate"
    if ($col["cost"] + 0 > stat[st, "cost_p90"] + 0) r = r ",cost"
    if ($col["turns"] * 5 < stat[st, "turns_median"]) r = r ",short"
    sub(/^,/, "", r)
    print st, $col["repo"], $col["n"], $col["sid8"], $col["session_id"], (r == "" ? "clean" : "flag"), (r == "" ? "-" : r), $col["events"]
  }
' "$tmp/stats" "$out/sessions.tsv" > "$tmp/marked"

awk -F'\t' '$6 == "clean" { print $1 "\t" $5 }' "$tmp/marked" | while IFS=$'\t' read -r st sid; do
  printf '%s\t%s\t%s\n' "$st" "$(printf '%s%s' "$day" "$sid" | cksum | cut -d' ' -f1)" "$sid"
done | sort -t$'\t' -k1,1 -k2,2n > "$tmp/order"

cp "$tmp/marked" "$tmp/marked2"
awk -F'\t' -v OFS='\t' '
  FILENAME == ARGV[1] { clean[$1]++; rank[$3] = clean[$1]; next }
  FILENAME == ARGV[2] { rows[$1]++; if ($6 == "clean") total[$1]++; if ($6 == "flag") flagged[$1]++; next }
  {
    if ($6 == "clean") {
      want = int((total[$1] + 9) / 10); if (want < 2) want = 2
      floor = int((rows[$1] + 2) / 3) - flagged[$1]; if (floor > want) want = floor
      $6 = (rank[$5] <= want) ? "sample" : "skip"
    }
    print
  }
' "$tmp/order" "$tmp/marked" "$tmp/marked2" | sort -t$'\t' -k1,1 -k2,2 -k5,5 | awk -F'\t' -v OFS='\t' -v per="$per_reader" '
  BEGIN { print "stage", "repo", "n", "sid8", "session_id", "pick", "reasons", "reader", "events" }
  { reader = "-"; if ($6 == "flag" || $6 == "sample") { picked[$1]++; reader = $1 "-" int((picked[$1] + per - 1) / per) } print $1, $2, $3, $4, $5, $6, $7, reader, $8 }
' > "$out/flags.tsv"

if [ "$("$here/mode.sh")" = author ]; then plugin=$(git -C "$here" rev-parse --short HEAD 2>/dev/null); else plugin=$(basename "$(cd "$here/../../.." && pwd -P)"); fi
run="$(basename "$(dirname "$out")")/$(basename "$out")"

awk -F'\t' -v OFS='\t' -v day="$day" -v run="$run" -v plugin="${plugin:-?}" -v per="$per_reader" -v perpr="$per_pr_reader" '
  FILENAME == ARGV[1] { stat[$1, $2] = $3; next }
  FILENAME == ARGV[2] { if (FNR > 1) { if ($6 == "flag") flagged[$1]++; if ($6 == "sample") sampled[$1]++ } next }
  FNR == 1 { for (i = 1; i <= NF; i++) col[$i] = i; next }
  {
    st = $col["stage"]; if (!(st in rows)) order[++k] = st
    rows[st]++
    if ($col["transcript"] == "no") { missing[st]++; next }
    if ($col["user_turns"] == 0) zero[st]++; else withturns[st] = 1
    handoffs[st] += $col["handoffs"]; limits[st] += $col["limit_hits"]
    if ($col["guard_events"] > 0) guards[st]++
    gates[st] += $col["gates"]; red[st] += $col["red_gates"]; fixes[st] += $col["fix_rounds"]
    if ($col["final_gate"] == "red") redfinal[st]++
    if ($col["pr"] != "none" && !seen[st, $col["pr"]]++) prs[st]++
    cost[st] += $col["cost"]
    m = split($col["cost_by_family"], parts, ",")
    for (i = 1; i <= m; i++) if (split(parts[i], kv, "=") == 2) fam[st, kv[1]] += kv[2]
  }
  END {
    print "date", "run", "plugin", "stage", "sessions_n", "no_transcript", "user_turns_median", "zero_user_turn_sessions", "handoffs", "guard_sessions", "limit_hits", "gates", "red_gates", "red_final_gates", "fix_rounds", "prs", "post_pr_defects", "ctx_max_k_median", "cost_total", "cost_median", "cost_p90", "cost_by_family", "flagged", "sampled", "readers"
    split("fable opus sonnet haiku", names, " ")
    for (j = 1; j <= k; j++) {
      st = order[j]; f = ""
      for (i = 1; i <= 4; i++) if ((st, names[i]) in fam) f = f (f == "" ? "" : ",") names[i] "=" sprintf("%.2f", fam[st, names[i]])
      picked = flagged[st] + sampled[st]
      print day, run, plugin, st, rows[st], missing[st] + 0, stat[st, "user_turns_median"] + 0, zero[st] + 0, handoffs[st] + 0, guards[st] + 0, limits[st] + 0, gates[st] + 0, red[st] + 0, redfinal[st] + 0, fixes[st] + 0, prs[st] + 0, "na", stat[st, "ctx_max_k_median"] + 0, sprintf("%.2f", cost[st]), sprintf("%.2f", stat[st, "cost_median"]), sprintf("%.2f", stat[st, "cost_p90"]), (f == "" ? "-" : f), flagged[st] + 0, sampled[st] + 0, int((picked + per - 1) / per) + withturns[st] + int((prs[st] + perpr - 1) / perpr)
    }
  }
' "$tmp/stats" "$out/flags.tsv" "$out/sessions.tsv" > "$out/stages.tsv"
cat "$out/stages.tsv"
