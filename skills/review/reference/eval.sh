#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: eval.sh responses <key> <pr> | build <key> <pr>... | score <key>" >&2
  exit 2
}

[ $# -ge 2 ] || usage
CMD=$1
KEY=$2
shift 2
REPO=$(sin-flow-profile "$KEY" get repo.slug)
REVIEWS=$(sin-flow-profile user reviews_dir)
case "$REVIEWS" in "~"/*) REVIEWS=$HOME/${REVIEWS#\~/} ;; esac
SET=$(sin-flow-profile "$KEY" dir)/review-evals.tsv
LOG=$REVIEWS/responses.tsv

threads() {
  local pr=$1 me author
  me=$(gh api user -q .login)
  author=$(gh pr view "$pr" --repo "$REPO" --json author -q .author.login)
  gh api --paginate "repos/$REPO/pulls/$pr/comments" \
    --jq '.[] | [.id, (.in_reply_to_id // 0), .user.login, .user.type, .path, (.line // 0), .original_line, .original_commit_id, (.body | gsub("[\t\r\n]"; " "))] | @tsv' \
    | awk -F'\t' -v me="$me" -v author="$author" -v pr="$pr" '
      $2 == 0 { top[$1] = $0; order[++n] = $1; next }
      !($2 in reply) { reply[$2] = $9 }
      END {
        for (i = 1; i <= n; i++) {
          split(top[order[i]], f, "\t")
          r = tolower(reply[f[1]])
          if (r ~ /^(fixed|done|resolved)/) c = "fixed"
          else if (r ~ /intend|by design|on purpose|decision|chose/) c = "intentional"
          else if (r != "") c = "wrong"
          else if (f[6] == 0) c = "fixed"
          else c = "ignored"
          who = f[3] == me ? "ours" : (f[3] == author || f[4] != "User") ? "skip" : "human"
          printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", who, pr, f[1], substr(f[8], 1, 8), f[5], f[7], c
        }
      }'
}

seen() { [ -f "$2" ] && cut -f3 "$2" | grep -qx "$1"; }

case "$CMD" in
  responses)
    [ $# -eq 1 ] || usage
    threads "$1" | while IFS=$'\t' read -r who pr id sha path line class; do
      [ "$who" = ours ] || continue
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$KEY" "$pr" "$id" "$sha" "$path:$line" "$class"
      seen "$id" "$LOG" || printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$KEY" "$pr" "$id" "$sha" "$path:$line" "$class" >> "$LOG"
    done
    ;;
  build)
    [ $# -ge 1 ] || usage
    for pr in "$@"; do
      threads "$pr" | while IFS=$'\t' read -r who pr id sha path line class; do
        [ "$who" = human ] && [ "$class" = fixed ] || continue
        seen "$id" "$SET" && continue
        printf '%s\t%s\t%s\t%s\t%s\n' "$KEY" "$pr" "$id" "$sha" "$path:$line" | tee -a "$SET"
      done
    done
    ;;
  score)
    [ -s "$SET" ] || { echo "no eval set: $SET" >&2; exit 1; }
    while IFS=$'\t' read -r key pr id sha loc; do
      file=$REVIEWS/$key-$pr-$sha.md
      [ -f "$file" ] || file=$(ls -tr "$REVIEWS/$key-$pr-"*.md 2>/dev/null | head -1)
      if [ -z "$file" ]; then printf '%s\t%s\tno-review\n' "$pr" "$loc"; continue; fi
      awk -v loc="$loc" -v pr="$pr" -v name="${file##*/}" '
        BEGIN { p = loc; sub(/:[0-9]+$/, "", p); l = loc; sub(/^.*:/, "", l); best = "missed"; gap = 4 }
        function near(at, out,   q, m, d) {
          q = at; sub(/:[0-9]+$/, "", q); m = at; sub(/^.*:/, "", m)
          d = m - l; if (d < 0) d = -d
          if (q == p && d < gap) { gap = d; best = out }
        }
        /^### K[0-9]+ · / { near($NF, ($4 ~ /^(high|med)$/ && $6 == "reproduces") ? "posted" : "kept-" $4 "-" $6) }
        /^- R[0-9]+ \| / { split($0, f, " [|] "); near(f[3], "rejected-" f[2]) }
        END { printf "%s\t%s\t%s\t%s\n", pr, loc, best, name }' "$file"
    done < "$SET" | tee /dev/stderr | cut -f3 | sort | uniq -c
    ;;
  *) usage ;;
esac
