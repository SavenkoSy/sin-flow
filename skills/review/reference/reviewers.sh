#!/usr/bin/env bash
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
LENSES=$HERE/lenses
FLOW_HOME=${FLOW_HOME:-$HOME/.claude/sin-flow}
TIMEOUT_SECONDS=900
RESERVED=" codex context code fit all verify settle findings tree "

die() { echo "reviewers.sh: $*" >&2; exit 2; }
usage() { die "usage: reviewers.sh find|reply|stats <pkg>"; }

[ $# -eq 2 ] || usage
CMD=$1
PKG=$2
[ -f "$PKG/manifest.env" ] || die "no manifest.env in $PKG"
. "$PKG/manifest.env"
mkdir -p "$PKG/findings"

pref() { "$HERE/../../../bin/sin-flow-profile" user "$1" 2>/dev/null; }

upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

entries() {
  local list items entry name problem seen=" "
  list=$(pref extra_reviewers)
  [ "$list" != off ] || list=
  read -r -a items <<< "$list"
  for entry in ${items[@]+"${items[@]}"}; do
    case "$entry" in "~"/*) entry="$HOME/${entry#\~/}" ;; esac
    name=$(basename "$entry")
    name=${name%%.*}
    problem=
    case "$entry" in
      codex) ;;
      /*) case "$RESERVED" in *" $name "*) problem="the name $name belongs to the flow: $entry" ;; esac ;;
      *) problem="'$entry' is not codex or a path" ;;
    esac
    [ -n "$problem" ] || case "$seen" in *" $name "*) problem="duplicate name $name: $entry" ;; esac
    [ -n "$problem" ] || seen="$seen$name "
    printf '%s\t%s\t%s\n' "$name" "$entry" "$problem"
  done
}

select_reviewer() {
  NAME=$1
  ENTRY=$2
  UPPER=$(upper "$1")
  D=$PKG/$NAME
  LOG=$D/live.log
  mkdir -p "$D"
  touch "$LOG"
}

log() { printf '%s\n' "$@" >> "$LOG"; }

orca_on() {
  [ "$(pref reviewer_watch)" = orca ] && command -v orca >/dev/null 2>&1 &&
    orca status --json 2>/dev/null | jq -e '.result.runtime.reachable == true' > /dev/null
}

orca_worktree_set() {
  orca_on || return 0
  (cd "$TREE" && orca worktree set --worktree active "$@" --json >/dev/null 2>&1) ||
    { [ -n "${ORCA_WORKTREE_ID:-}" ] && orca worktree set --worktree "id:$ORCA_WORKTREE_ID" "$@" --json >/dev/null 2>&1; } ||
    true
}

status_line() {
  local watch held=""
  watch=$(pref reviewer_watch)
  case "$watch" in
    orca)
      for _ in $(seq 200); do mkdir "$PKG/.card.lock" 2>/dev/null && { held=1; break; }; sleep 0.05; done
      [ -z "$held" ] || trap 'rmdir "$PKG/.card.lock" 2>/dev/null; exit 143' INT TERM HUP
      printf '%s\n' "$1" > "$D/watch"
      orca_worktree_set --comment "$(cat "$PKG"/*/watch 2>/dev/null | paste -sd ';' -)"
      [ -z "$held" ] || { rmdir "$PKG/.card.lock" 2>/dev/null; trap - INT TERM HUP; } ;;
    /*|"~"/*) watch="${watch/#\~/$HOME}"; [ -x "$watch" ] && (cd "$TREE" && "$watch" "$1") >/dev/null 2>&1 || true ;;
  esac
}

skip() {
  echo "lens $NAME skipped: $1" >> "$PKG/failed.txt"
  log "=== $NAME skipped: $1 ==="
  status_line "$NAME: skipped ($1)"
  echo "$2 · skipped · $1"
  exit 0
}

failure_reason() {
  local rc=$1 tail_log
  tail_log=$(tail -n +"$2" "$LOG")
  if [ "$rc" -eq 142 ]; then echo "timeout after ${TIMEOUT_SECONDS}s"
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
    (cd "$TREE" && perl -e 'alarm shift; exec @ARGV' "$TIMEOUT_SECONDS" \
      codex exec --skip-git-repo-check -s read-only -c project_doc_max_bytes=0 resume -c project_doc_max_bytes=0 \
      --output-schema "$schema" -o "$out" "$resume" "$prompt" < /dev/null > /dev/null 2>> "$LOG") 2> /dev/null
  else
    (cd "$TREE" && perl -e 'alarm shift; exec @ARGV' "$TIMEOUT_SECONDS" \
      codex exec --skip-git-repo-check -s read-only -c project_doc_max_bytes=0 ${MODEL:+-m "$MODEL"} -C "$TREE" \
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

run_script() {
  local start rc
  start=$(($(wc -l < "$LOG") + 1))
  (cd "$TREE" && perl -e 'alarm shift; exec @ARGV' "$TIMEOUT_SECONDS" \
    "$ENTRY" "$1" "$PKG" "$NAME" < /dev/null 2>> "$LOG") 2> /dev/null
  rc=$?
  [ "$rc" -eq 0 ] || { REASON=$(failure_reason "$rc" "$start"); return 1; }
}

fill() {
  sed -e "s|{PKG}|$PKG|g" -e "s|{LENSES}|$LENSES|g" -e "s|{STACK}|${STACK:-}|g" -e "s|{TEAM}|${TEAM:-}|g" "$1"
}

newest_model() {
  case "$1" in
    "") return 0 ;;
    *-*) echo "$1" ;;
    *) jq -r --arg f "$1" '.models[] | select(.visibility == "list") | .slug | select(test("^gpt-[0-9.]+-" + $f + "$"))' \
         "${CODEX_HOME:-$HOME/.codex}/models_cache.json" 2>/dev/null | sort -V | tail -1 ;;
  esac
}

find_codex() {
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
}

find_script() {
  [ -f "$ENTRY" ] && [ -x "$ENTRY" ] || skip "$ENTRY is not an executable file" "$UPPER"
  status_line "$NAME: finding"
  log "=== $NAME find · $(date '+%H:%M:%S') · ${SHA:0:8} against ${BASE:0:8} ==="
  run_script find > "$D/find.body" || skip "$REASON" "$UPPER"
  ! grep -qvE '^(F[0-9]+ [|] .+[|] |  (trigger|evidence|breaks): |DECLINED: |[[:space:]]*$)' "$D/find.body" ||
    skip "output not in finder format: $(grep -vE '^(F[0-9]+ [|] .+[|] |  (trigger|evidence|breaks): |DECLINED: |[[:space:]]*$)' "$D/find.body" | head -1 | cut -c1-80)" "$UPPER"
  {
    printf 'LENS: %s · %s findings\n' "$NAME" "$(grep -cE '^F[0-9]+ [|] ' "$D/find.body")"
    cat "$D/find.body"
    grep -q '^DECLINED: ' "$D/find.body" || echo "DECLINED: none"
  } > "$PKG/findings/$NAME.md"
  rm -f "$D/find.body"
}

find_one() {
  if [ -n "$3" ]; then
    echo "lens $1 skipped: $3" >> "$PKG/failed.txt"
    echo "$(upper "$1") · skipped · $3"
    exit 0
  fi
  select_reviewer "$1" "$2"
  if [ "$MODE" != exec ]; then
    [ "$NAME" = codex ] || { echo "$UPPER · off · pr mode runs only Codex"; exit 0; }
    MODEL=$(newest_model "$(pref codex_model_pr)")
    [ -n "$MODEL" ] || { echo "CODEX · off · pr mode, no model for codex_model_pr"; exit 0; }
  fi
  : > "$LOG"
  rm -f "$D/session" "$D/find.json" "$PKG/findings/$NAME.md"
  if [ "$NAME" = codex ]; then find_codex; else find_script; fi
  local n
  n=$(head -1 "$PKG/findings/$NAME.md" | sed -n "s/^LENS: $NAME · \([0-9]*\) findings\$/\1/p")
  log "" "=== $NAME findings ===" "$(cat "$PKG/findings/$NAME.md")"
  status_line "$NAME: $n findings, waiting for the judge"
  echo "LENS $NAME · $n findings · $PKG/findings/$NAME.md"
}

reply_codex() {
  run_codex "$HERE/codex/reply.schema.json" "$D/reply.json" "$(cat "$HERE/codex/reply.md" "$PKG/verdict.md")" "$(cat "$D/session")" ||
    skip "$REASON" "CODEX REPLY"
  local contested accepted
  jq -r --arg ids " $IDS " '.replies[]
    | .row as $row
    | select(.stance == "contest" and ($ids | contains(" " + $row + " ")) and (.evidence | test(":[0-9]+")))
    | "\(.row) | contest | \(.argument | gsub("\\s+"; " "))", "  evidence: \(.evidence | gsub("\\s+"; " "))"' \
    "$D/reply.json" > "$D/reply.body"
  contested=$(grep -cE '^(K|R)[0-9]+ [|] contest' "$D/reply.body")
  accepted=$(jq '[.replies[] | select(.stance == "accept")] | length' "$D/reply.json")
  { printf 'CODEX REPLY · %s contested · %s accepted\n' "$contested" "$accepted"; cat "$D/reply.body"; } > "$D/reply.md"
  rm -f "$D/reply.body"
}

reply_script() {
  run_script reply > "$D/reply.out" || skip "$REASON" "$UPPER REPLY"
  awk -v ids=" $IDS " '
    /^(K|R)[0-9]+ [|] contest [|] / { row = $0; id = $1; next }
    row != "" && /^  evidence: .*:[0-9]+/ && index(ids, " " id " ") { print row; print }
    { row = "" }' "$D/reply.out" > "$D/reply.body"
  rm -f "$D/reply.out"
  local contested
  contested=$(grep -cE '^(K|R)[0-9]+ [|] contest' "$D/reply.body")
  { printf '%s REPLY · %s contested · %s accepted\n' "$UPPER" "$contested" "$((ROWS > contested ? ROWS - contested : 0))"
    cat "$D/reply.body"; } > "$D/reply.md"
  rm -f "$D/reply.body"
}

reply_one() {
  select_reviewer "$1" "$2"
  [ -s "$PKG/findings/$NAME.md" ] || exit 0
  [ "$NAME" != codex ] || [ -s "$D/session" ] || { echo "CODEX REPLY · none · no codex session"; exit 0; }
  [ -s "$PKG/verdict.md" ] || { echo "$UPPER REPLY · none · no verdict"; exit 0; }
  IDS=$(grep -oE '^(K|R)[0-9]+' "$PKG/verdict.md" | paste -sd' ' -)
  ROWS=$(grep -cE "^K[0-9]+ [|] |^R[0-9]+ [|] [a-z-]+ [|] [^|]* [|] $NAME/" "$PKG/verdict.md")
  log "" "=== judge verdict ===" "$(grep -E '^(VERIFY|K[0-9]+|R[0-9]+|BLOCKING|  from:)' "$PKG/verdict.md")"
  if [ "$ROWS" -eq 0 ]; then
    printf '%s REPLY · 0 contested · 0 accepted\n' "$UPPER" > "$D/reply.md"
    echo "$UPPER REPLY · 0 contested · 0 accepted · $D/reply.md"
    exit 0
  fi
  status_line "$NAME: replying on $ROWS rows"
  log "" "=== $NAME reply · $(date '+%H:%M:%S') ==="
  if [ "$NAME" = codex ]; then reply_codex; else reply_script; fi
  local contested accepted
  read -r contested accepted < <(head -1 "$D/reply.md" | sed -n 's/^.* REPLY · \([0-9]*\) contested · \([0-9]*\) accepted$/\1 \2/p')
  log "$(cat "$D/reply.md")"
  status_line "$NAME: contested $contested rows, waiting for the judge"
  echo "$UPPER REPLY · $contested contested · $accepted accepted · $D/reply.md"
}

stats_one() {
  select_reviewer "$1" "$2"
  [ -s "$PKG/findings/$NAME.md" ] || exit 0
  local found kept unique contested changed branch
  found=$(head -1 "$PKG/findings/$NAME.md" | sed -n "s/^LENS: $NAME · \([0-9]*\) findings\$/\1/p")
  read -r kept unique < <(awk -v me="$NAME/" '
    /^K[0-9]+ [|] / { inK = 1; next }
    /^(R[0-9]+ [|] |BLOCKING:)/ { inK = 0 }
    inK && /^  from: / {
      sub(/^  from: */, ""); n = split($0, ids, / *, */); c = 0
      for (i = 1; i <= n; i++) if (index(ids[i], me) == 1) c++
      if (c > 0) k++
      if (c > 0 && c == n) u++
      inK = 0
    }
    END { print k + 0, u + 0 }' "$PKG/verdict.md" 2>/dev/null || echo "0 0")
  contested=$(head -1 "$D/reply.md" 2>/dev/null | sed -n 's/^.* REPLY · \([0-9]*\) contested.*/\1/p')
  changed=$(awk -F' [|] ' -v me="$NAME" 'NR > 1 && $2 == "changed" {
      n = split($3, names, ","); for (i = 1; i <= n; i++) if (names[i] == me) c++
    } END { print c + 0 }' "$PKG/settle.md" 2>/dev/null)
  local line="$UPPER · found ${found:-0} · kept $kept · unique $unique · contested ${contested:-0} · changed ${changed:-0}"
  [ -s "$PKG/settle.md" ] && log "" "=== judge settle ===" "$(cat "$PKG/settle.md")"
  log "" "=== $line ==="
  status_line "$NAME: kept $kept, unique $unique"
  if [ "$NAME" = codex ]; then
    branch=$(git -C "$TREE" branch --show-current 2>/dev/null)
    [ -s "$FLOW_HOME/codex-trial.tsv" ] ||
      printf 'date\tkey\tbranch\tsha\tfound\tkept\tunique\tcontested\tchanged\n' > "$FLOW_HOME/codex-trial.tsv"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%F)" "$KEY" "$branch" "${SHA:0:8}" \
      "${found:-0}" "$kept" "$unique" "${contested:-0}" "${changed:-0}" >> "$FLOW_HOME/codex-trial.tsv"
  fi
  echo "$line"
}

cmd_find() {
  local out i=0 name entry problem
  out=$(mktemp -d)
  while IFS=$'\t' read -r name entry problem; do
    ( find_one "$name" "$entry" "$problem" ) > "$out/$i" &
    i=$((i + 1))
  done < <(entries)
  wait
  [ "$i" -gt 0 ] || echo "REVIEWERS · off"
  for ((j = 0; j < i; j++)); do cat "$out/$j"; done
  rm -rf "$out"
}

cmd_each() {
  local out i=0 name entry problem
  out=$(mktemp -d)
  while IFS=$'\t' read -r name entry problem; do
    [ -z "$problem" ] || continue
    ( "$1" "$name" "$entry" ) > "$out/$i" &
    [ "$2" = parallel ] || wait
    i=$((i + 1))
  done < <(entries)
  wait
  for ((j = 0; j < i; j++)); do cat "$out/$j"; done
  rm -rf "$out"
}

case "$CMD" in
  find) cmd_find ;;
  reply) cmd_each reply_one parallel ;;
  stats) cmd_each stats_one serial ;;
  *) usage ;;
esac
