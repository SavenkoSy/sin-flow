#!/bin/bash
set -euo pipefail
runs="${FLOW_RUNS_LOG:-${FLOW_HOME:-$HOME/.claude/sin-flow}/runs.tsv}"
learning=$("$(dirname "$0")/learning-dir.sh")
dry=0
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --runs) runs="$2"; shift ;;
    *) args+=("$1") ;;
  esac
  shift
done
repo="${args[0]:-all}"
stage="${args[1]:-}"
n="${args[2]:-}"
[ -f "$runs" ] || { echo "no run log: $runs" >&2; exit 2; }
covered=$(mktemp)
trap 'rm -f "$covered"' EXIT
"$(dirname "$0")/covered-sids.sh" "$learning" > "$covered"
awk -F'\t' -v OFS='\t' -v repo="$repo" -v stage="$stage" -v n="$n" -v dry="$dry" -v covfile="$covered" '
  FILENAME == covfile { seen8[$1] = 1; next }
  FNR == 1 { for (i = 1; i <= NF; i++) col[$i] = i; header = $0
            if (!("session_id" in col) || !("repo" in col) || !("stage" in col)) { print "run log has no repo/stage/session_id header" > "/dev/stderr"; exit 2 }
            if (!dry) print header; next }
  {
    sid = $col["session_id"]; r = $col["repo"]; st = $col["stage"]; nn = $col["n"]
    sk = ("skill" in col) ? $col["skill"] : ""
    if (sid == "" || dup[sid]++) next
    if (repo == "self") { if (sk !~ /(^|[-:])learning$/) next }
    else if (repo != "all" && r != repo) next
    if (stage != "" && st != stage) next
    if (n != "" && nn != n) next
    undig = (substr(sid, 1, 8) in seen8) ? "no" : "yes"
    if (dry) { printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", r, st, nn, substr(sid, 1, 8), $col["date"], sk, undig; total[r]++; if (undig == "yes") open[r]++ }
    else if (undig == "yes" || n != "") print
  }
  END { if (dry) { print "--"; print "repo\tlisted\tundigested"; for (r in total) printf "%s\t%d\t%d\n", r, total[r], open[r] + 0 } }
' "$covered" "$runs"
