#!/usr/bin/env bash
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
LENSES=$HERE/lenses
FLOW_HOME=${FLOW_HOME:-$HOME/.claude/sin-flow}
CODEX_TIMEOUT_SECONDS=900

die() { echo "codex.sh: $*" >&2; exit 2; }
usage() { die "usage: codex.sh find|reply|stats <pkg>"; }

[ $# -eq 2 ] || usage
CMD=$1
PKG=$2
[ -f "$PKG/manifest.env" ] || die "no manifest.env in $PKG"
. "$PKG/manifest.env"
D=$PKG/codex
LOG=$D/live.log
mkdir -p "$D" "$PKG/findings"

pref() { sed -n "s/^$1: *//p" "$FLOW_HOME/user.md" 2>/dev/null | head -1 | tr -d '"'; }

log() { printf '%s\n' "$@" >> "$LOG"; }

orca_on() {
  [ "$(pref codex_watch)" = orca ] && command -v orca >/dev/null 2>&1 &&
    orca status --json 2>/dev/null | jq -e '.result.runtime.reachable == true' > /dev/null
}

orca_worktree_set() {
  orca_on || return 0
  (cd "$TREE" && orca worktree set --worktree active "$@" --json >/dev/null 2>&1) ||
    { [ -n "${ORCA_WORKTREE_ID:-}" ] && orca worktree set --worktree "id:$ORCA_WORKTREE_ID" "$@" --json >/dev/null 2>&1; } ||
    true
}

status_line() { orca_worktree_set --comment "$1"; }

skip() {
  echo "lens codex skipped: $1" >> "$PKG/failed.txt"
  log "=== codex skipped: $1 ==="
  status_line "codex: skipped ($1)"
  echo "$2 · skipped · $1"
  exit 0
}

failure_reason() {
  local rc=$1 tail_log
  tail_log=$(tail -n +"$2" "$LOG")
  if [ "$rc" -eq 142 ]; then echo "timeout after ${CODEX_TIMEOUT_SECONDS}s"
  elif printf '%s' "$tail_log" | grep -qiE 'usage limit|rate limit|429|quota'; then echo "usage limit"
  elif printf '%s' "$tail_log" | grep -qiE '401|unauthorized|not logged in'; then echo "not logged in"
  elif printf '%s' "$tail_log" | grep -qi 'error'; then
    printf 'error: %s' "$(printf '%s' "$tail_log" | grep -i 'error' | tail -1 | cut -c1-160)"
  else echo "exit $rc"
  fi
}

run_codex() {
  local schema=$1 out=$2 prompt=$3 resume=${4:-} start rc
  start=$(($(wc -l < "$LOG") + 1))
  rm -f "$out"
  if [ -n "$resume" ]; then
    (cd "$TREE" && perl -e 'alarm shift; exec @ARGV' "$CODEX_TIMEOUT_SECONDS" \
      codex exec -s read-only -c project_doc_max_bytes=0 resume -c project_doc_max_bytes=0 \
      --output-schema "$schema" -o "$out" "$resume" "$prompt" < /dev/null > /dev/null 2>> "$LOG") 2> /dev/null
  else
    (cd "$TREE" && perl -e 'alarm shift; exec @ARGV' "$CODEX_TIMEOUT_SECONDS" \
      codex exec -s read-only -c project_doc_max_bytes=0 -C "$TREE" \
      --output-schema "$schema" -o "$out" "$prompt" < /dev/null > /dev/null 2>> "$LOG") 2> /dev/null
  fi
  rc=$?
  if [ "$rc" -eq 0 ] && ! jq -e . "$out" > /dev/null 2>&1; then
    REASON="no JSON answer"
    return 1
  fi
  if [ "$rc" -ne 0 ]; then
    REASON=$(failure_reason "$rc" "$start")
    return 1
  fi
  [ -n "$resume" ] || sed -n "$start,\$p" "$LOG" | sed -n 's/^session id: *//p' | head -1 > "$D/session"
}

fill() {
  sed -e "s|{PKG}|$PKG|g" -e "s|{LENSES}|$LENSES|g" -e "s|{STACK}|${STACK:-}|g" -e "s|{TEAM}|${TEAM:-}|g" "$1"
}

cmd_find() {
  if [ "$MODE" != exec ]; then echo "CODEX · off · pr mode"; exit 0; fi
  if [ "$(pref codex_review)" != on ]; then echo "CODEX · off"; exit 0; fi
  : > "$LOG"
  rm -f "$D/session" "$D/find.json" "$PKG/findings/codex.md"
  command -v codex >/dev/null 2>&1 || skip "not installed" CODEX
  codex login status >/dev/null 2>&1 || skip "not logged in" CODEX
  status_line "codex: finding"
  log "=== codex find · $(date '+%H:%M:%S') · ${SHA:0:8} against ${BASE:0:8} ==="
  run_codex "$HERE/codex/find.schema.json" "$D/find.json" "$(fill "$HERE/codex/find.md")" || skip "$REASON" CODEX
  local n
  n=$(jq '.findings | length' "$D/find.json")
  {
    printf 'LENS: codex · %s findings\n' "$n"
    jq -r '.findings | to_entries[] | .value as $f
      | ($f.checklists | map(select(length > 0)) | if length == 0 then ["codex"] else . end | join(",")) as $tags
      | "F\(.key + 1) | \($f.file):\($f.line) | [\($tags)] \($f.claim | gsub("\\s+"; " "))",
        "  trigger: \($f.trigger | gsub("\\s+"; " "))",
        "  evidence: \($f.evidence | gsub("\\s+"; " "))",
        "  breaks: \($f.breaks | gsub("\\s+"; " "))"' "$D/find.json"
    echo "DECLINED: none"
  } > "$PKG/findings/codex.md"
  log "" "=== codex findings ===" "$(cat "$PKG/findings/codex.md")"
  status_line "codex: $n findings, waiting for the judge"
  echo "LENS codex · $n findings · $PKG/findings/codex.md"
}

cmd_reply() {
  [ -s "$D/session" ] || { echo "CODEX REPLY · none · no codex session"; exit 0; }
  [ -s "$PKG/verdict.md" ] || { echo "CODEX REPLY · none · no verdict"; exit 0; }
  local rows
  rows=$(grep -cE '^K[0-9]+ [|] |^R[0-9]+ [|] [a-z-]+ [|] [^|]* [|] codex/' "$PKG/verdict.md")
  log "" "=== judge verdict ===" "$(grep -E '^(VERIFY|K[0-9]+|R[0-9]+|BLOCKING|  from:)' "$PKG/verdict.md")"
  if [ "$rows" -eq 0 ]; then
    printf 'CODEX REPLY · 0 contested · 0 accepted\n' > "$D/reply.md"
    echo "CODEX REPLY · 0 contested · 0 accepted · $D/reply.md"
    exit 0
  fi
  status_line "codex: replying on $rows rows"
  log "" "=== codex reply · $(date '+%H:%M:%S') ==="
  run_codex "$HERE/codex/reply.schema.json" "$D/reply.json" "$(cat "$HERE/codex/reply.md" "$PKG/verdict.md")" "$(cat "$D/session")" ||
    skip "$REASON" "CODEX REPLY"
  local ids contested accepted
  ids=$(grep -oE '^(K|R)[0-9]+' "$PKG/verdict.md" | paste -sd' ' -)
  jq -r --arg ids " $ids " '.replies[]
    | .row as $row
    | select(.stance == "contest" and ($ids | contains(" " + $row + " ")) and (.evidence | test(":[0-9]+")))
    | "\(.row) | contest | \(.argument | gsub("\\s+"; " "))", "  evidence: \(.evidence | gsub("\\s+"; " "))"' \
    "$D/reply.json" > "$D/reply.body"
  contested=$(grep -cE '^(K|R)[0-9]+ [|] contest' "$D/reply.body")
  accepted=$(jq '[.replies[] | select(.stance == "accept")] | length' "$D/reply.json")
  { printf 'CODEX REPLY · %s contested · %s accepted\n' "$contested" "$accepted"; cat "$D/reply.body"; } > "$D/reply.md"
  rm -f "$D/reply.body"
  log "$(cat "$D/reply.md")"
  status_line "codex: contested $contested rows, waiting for the judge"
  echo "CODEX REPLY · $contested contested · $accepted accepted · $D/reply.md"
}

cmd_stats() {
  [ -s "$PKG/findings/codex.md" ] || { echo "CODEX · no findings file"; exit 0; }
  local found kept unique contested changed branch
  found=$(head -1 "$PKG/findings/codex.md" | sed -n 's/^LENS: codex · \([0-9]*\) findings$/\1/p')
  read -r kept unique < <(awk '
    /^K[0-9]+ [|] / { inK = 1; next }
    /^(R[0-9]+ [|] |BLOCKING:)/ { inK = 0 }
    inK && /^  from: / {
      sub(/^  from: */, ""); n = split($0, ids, / *, */); c = 0
      for (i = 1; i <= n; i++) if (ids[i] ~ /^codex\//) c++
      if (c > 0) k++
      if (c > 0 && c == n) u++
      inK = 0
    }
    END { print k + 0, u + 0 }' "$PKG/verdict.md" 2>/dev/null || echo "0 0")
  contested=$(head -1 "$D/reply.md" 2>/dev/null | sed -n 's/^CODEX REPLY · \([0-9]*\) contested.*/\1/p')
  changed=$(head -1 "$D/settle.md" 2>/dev/null | sed -n 's/^SETTLE · [0-9]* contested · \([0-9]*\) changed.*/\1/p')
  branch=$(git -C "$TREE" branch --show-current 2>/dev/null)
  local line="CODEX · found ${found:-0} · kept $kept · unique $unique · contested ${contested:-0} · changed ${changed:-0}"
  [ -s "$D/settle.md" ] && log "" "=== judge settle ===" "$(cat "$D/settle.md")"
  log "" "=== $line ==="
  status_line "codex: kept $kept, unique $unique"
  [ -s "$FLOW_HOME/codex-trial.tsv" ] ||
    printf 'date\tkey\tbranch\tsha\tfound\tkept\tunique\tcontested\tchanged\n' > "$FLOW_HOME/codex-trial.tsv"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%F)" "$KEY" "$branch" "${SHA:0:8}" \
    "${found:-0}" "$kept" "$unique" "${contested:-0}" "${changed:-0}" >> "$FLOW_HOME/codex-trial.tsv"
  echo "$line"
}

case "$CMD" in
  find) cmd_find ;;
  reply) cmd_reply ;;
  stats) cmd_stats ;;
  *) usage ;;
esac
