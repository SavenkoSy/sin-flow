#!/usr/bin/env bash
set -euo pipefail

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

usage() {
  die "usage: build-package.sh pr <PR number|url> <out-dir> [--at <sha>] [--base <sha>] [--depth quick|thorough]
       build-package.sh exec <base-ref> <out-dir> --intent <plan-path> [--notes <ledger-path>] [--depth quick|thorough]"
}

[ $# -ge 3 ] || usage
MODE=$1
TARGET=$2
OUT=$3
shift 3

AT=""
FORK=""
DEPTH_ARG=""
INTENT=""
NOTES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --at) AT=${2:?--at needs a sha}; shift 2 ;;
    --base) FORK=${2:?--base needs a sha}; shift 2 ;;
    --depth) DEPTH_ARG=${2:?--depth needs quick or thorough}; shift 2 ;;
    --intent) INTENT=${2:?--intent needs a path}; shift 2 ;;
    --notes) NOTES=${2:?--notes needs a path}; shift 2 ;;
    *) usage ;;
  esac
done
case "$DEPTH_ARG" in "" | quick | thorough) ;; *) usage ;; esac
case "$MODE" in pr | exec) ;; *) usage ;; esac

git rev-parse --show-toplevel >/dev/null 2>&1 || die "not inside a git repo: $PWD"
KEY=$(sin-flow-profile key) || die "no flow profile for this repo: run /sin-flow:setup"
TEAM_RULES=$(sin-flow-profile "$KEY" dir)/review-team.md

mkdir -p "$OUT"
PKG=$(cd "$OUT" && pwd -P)
rm -rf "$PKG/tree" "$PKG/findings"
rm -f "$PKG/manifest.env" "$PKG/pr.md" "$PKG/rules.md" "$PKG/diff.patch" "$PKG/files.txt" \
  "$PKG/context.md" "$PKG/verdict.md" "$PKG/failed.txt" "$PKG/post.json"
mkdir -p "$PKG/findings"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

git_diff() {
  git -c core.quotePath=false --literal-pathspecs diff --no-color --no-ext-diff "$@"
}

write_local_diff() {
  git_diff "$@" > "$PKG/diff.patch"
  git_diff --numstat -z "$@" | tr '\0' '\n' | awk -F'\t' '
    function emit() {
      if (a == "-") a = 0
      if (d == "-") d = 0
      printf "%s\t+%s\t-%s\n", path, a, d
    }
    NF >= 3 && $3 == "" { a = $1; d = $2; getline; getline; path = $0; emit(); next }
    NF >= 3 { a = $1; d = $2; path = $3; emit() }
  ' > "$PKG/files.txt"
}

write_rules() {
  : > "$PKG/rules.md"
  {
    printf '%s\n' CLAUDE.md CLAUDE.local.md
    cut -f1 "$PKG/files.txt" \
      | awk -F/ '{ d = ""; for (i = 1; i < NF; i++) { d = d $i "/"; print d "CLAUDE.md" } }' \
      | LC_ALL=C sort -u
  } > "$WORK/rules-paths.txt"
  while IFS= read -r f; do
    if [ -f "$TREE/$f" ]; then
      { printf '## %s\n\n' "$f"; cat "$TREE/$f"; printf '\n'; } >> "$PKG/rules.md"
    fi
  done < "$WORK/rules-paths.txt"
  if [ ! -s "$PKG/rules.md" ]; then
    printf 'no CLAUDE.md at %s\n' "$SHA" > "$PKG/rules.md"
  fi
  if [ -f "$TEAM_RULES" ]; then
    { printf '\n'; cat "$TEAM_RULES"; } >> "$PKG/rules.md"
  fi
}

write_team() {
  TEAM=no
  [ -f "$TEAM_RULES" ] || return 0
  TEAM=yes
}

body_as_of() {
  if [ -z "$AT" ]; then
    jq -r '.body // ""' "$3"
    return
  fi
  gh api graphql -F owner="${REPO%/*}" -F name="${REPO#*/}" -F n="$2" \
    -f query="query(\$owner:String!,\$name:String!,\$n:Int!){repository(owner:\$owner,name:\$name){$1(number:\$n){body userContentEdits(first:100){nodes{editedAt diff}}}}}" \
    | jq -r --argjson cut "$COMMIT_EPOCH" --arg k "$1" '
      .data.repository[$k]
      | ([.userContentEdits.nodes[] | select((.editedAt | fromdateiso8601) < $cut)]
         | max_by(.editedAt | fromdateiso8601)) as $e
      | if $e then ($e.diff // "") else (.body // "") end'
}

write_issue() {
  local issue cut
  issue=$({ jq -r .title "$WORK/pr.json"; cat "$WORK/pr-body.md"; } \
    | grep -oE '(GH-|#)[0-9]+' | tr -d 'GH#-' | awk -v pr="$PR" '$0 != pr { print; exit }' || true)
  if [ -z "$issue" ]; then
    printf '## Linked issue: none found in title or body\n'
    return
  fi
  if ! gh issue view "$issue" --repo "$REPO" --json number,title,body,comments > "$WORK/issue.json" 2>/dev/null; then
    printf '## Linked issue #%s: not readable\n' "$issue"
    return
  fi
  cut=0
  [ -z "$AT" ] || cut=$COMMIT_EPOCH
  body_as_of issue "$issue" "$WORK/issue.json" > "$WORK/issue-body.md"
  jq -r --argjson cut "$cut" --arg sha8 "${SHA:0:8}" --rawfile body "$WORK/issue-body.md" '
    (.comments | map(select($cut == 0 or ((.createdAt | fromdateiso8601) < $cut)))) as $kept
    | "## Linked issue #\(.number) · \(.title)", "", $body, "",
      "## Issue comments · \($kept | length) of \(.comments | length)"
        + (if $cut == 0 then "" else " · older than \($sha8)" end),
      ($kept[] | "", "### \(.author.login) · \(.createdAt)", "", .body)
  ' "$WORK/issue.json"
}

pr_mode() {
  PR=$(printf '%s' "$TARGET" | sed -E 's#^.*/pull/([0-9]+).*$#\1#')
  case "$PR" in '' | *[!0-9]*) die "not a PR number or url: $TARGET" ;; esac
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
  case "$TARGET" in
    */pull/*)
      url_repo=$(printf '%s' "$TARGET" | sed -E 's#^.*github\.com/([^/]+/[^/]+)/pull/.*$#\1#')
      [ "$url_repo" = "$REPO" ] || die "PR url is for $url_repo, this checkout is $REPO"
      ;;
  esac
  gh pr view "$PR" --repo "$REPO" --json url,baseRefName,headRefOid,title,body > "$WORK/pr.json"
  BASE=$(jq -r .baseRefName "$WORK/pr.json")
  local head want mb local_obj=yes
  FOREIGN_DROPPED=unknown
  head=$(jq -r .headRefOid "$WORK/pr.json")
  want=${AT:-$head}

  git fetch --quiet origin "pull/$PR/head" "$BASE" >/dev/null 2>&1 || true
  SHA=$(git rev-parse --verify --quiet "$want^{commit}" || true)
  if [ -z "$SHA" ]; then
    SHA=$(gh api "repos/$REPO/commits/$want" -q .sha) || die "commit not found: $want"
    git fetch --quiet origin "$SHA" >/dev/null 2>&1 || true
    git cat-file -e "$SHA^{commit}" 2>/dev/null || local_obj=no
  fi

  TREE=$PKG/tree
  mkdir -p "$TREE"
  if [ "$local_obj" = yes ]; then
    git archive "$SHA" | tar -x -C "$TREE"
    if [ -n "$FORK" ]; then
      mb=$(git rev-parse --verify "$FORK^{commit}") || die "base commit not found: $FORK"
    else
      mb=$(git merge-base "origin/$BASE" "$SHA") || die "no merge base between origin/$BASE and $SHA"
    fi
    write_local_diff "$mb" "$SHA"
    [ -n "$FORK$AT" ] && FOREIGN_DROPPED=-
    [ -n "$FORK$AT" ] || gh api "repos/$REPO/pulls/$PR/files" --paginate \
      --jq '.[] | .filename, (.previous_filename // empty)' > "$WORK/pr-paths.txt" 2>/dev/null \
      || : > "$WORK/pr-paths.txt"
    if [ -z "$FORK$AT" ] && [ -s "$WORK/pr-paths.txt" ]; then
      FOREIGN_DROPPED=$(cut -f1 "$PKG/files.txt" | grep -cvxFf "$WORK/pr-paths.txt" || true)
      pr_paths=()
      while IFS= read -r p; do pr_paths+=("$p"); done < "$WORK/pr-paths.txt"
      write_local_diff "$mb" "$SHA" -- "${pr_paths[@]}"
    fi
    COMMIT_EPOCH=$(git show -s --format=%ct "$SHA")
  else
    gh api "repos/$REPO/tarball/$SHA" | tar -xz -C "$TREE" --strip-components=1
    gh api -H 'Accept: application/vnd.github.diff' "repos/$REPO/compare/$BASE...$SHA" > "$PKG/diff.patch"
    gh api "repos/$REPO/compare/$BASE...$SHA" \
      --jq '.files[] | "\(.filename)\t+\(.additions)\t-\(.deletions)"' > "$PKG/files.txt"
    COMMIT_EPOCH=$(gh api "repos/$REPO/commits/$SHA" --jq '.commit.committer.date | fromdateiso8601')
  fi

  body_as_of pullRequest "$PR" "$WORK/pr.json" > "$WORK/pr-body.md"
  {
    jq -r --arg sha "$SHA" --arg pr "$PR" --rawfile body "$WORK/pr-body.md" '
      "# PR \($pr) · \(.title)", .url,
      "base \(.baseRefName) · reviewed at \($sha) · head \(.headRefOid)",
      "", "## Body", "", $body, ""
    ' "$WORK/pr.json"
    write_issue
  } > "$PKG/pr.md"
}

exec_mode() {
  [ -n "$INTENT" ] || usage
  [ -f "$INTENT" ] || die "no intent file: $INTENT"
  [ -z "$NOTES" ] || [ -f "$NOTES" ] || die "no notes file: $NOTES"
  TREE=$(git rev-parse --show-toplevel)
  SHA=$(git rev-parse HEAD)
  BASE=$TARGET
  PR=-
  FOREIGN_DROPPED=-
  REPO=$(git remote get-url origin 2>/dev/null | sed -nE 's#^.*github\.com[:/]##p' | sed 's#\.git$##' || true)
  [ -n "$REPO" ] || REPO=local/$(basename "$TREE")
  local mb fork_ref=$BASE
  git rev-parse --verify --quiet "origin/$BASE^{commit}" >/dev/null && fork_ref=origin/$BASE
  mb=$(git merge-base "$fork_ref" HEAD) || die "no merge base between $fork_ref and HEAD"
  write_local_diff "$mb" HEAD
  {
    printf '# Intent: %s\n\n' "$INTENT"
    cat "$INTENT"
    if [ -n "$NOTES" ]; then
      printf '\n# Notes: %s\n\n' "$NOTES"
      cat "$NOTES"
    fi
  } > "$PKG/pr.md"
}

if [ "$MODE" = pr ]; then pr_mode; else exec_mode; fi

write_rules
write_team

cut -f1 "$PKG/files.txt" | awk -F. 'NF > 1 { print $NF }' > "$WORK/exts.txt"
has_ext() {
  grep -qxE "$1" "$WORK/exts.txt"
}
ruby=no
js=no
if has_ext 'rb|rake|erb|ru'; then ruby=yes; fi
if has_ext 'js|jsx|ts|tsx|vue'; then js=yes; fi
if [ "$ruby$js" = yesyes ]; then
  STACK=mixed
elif [ "$ruby" = yes ]; then
  STACK=ruby
elif [ "$js" = yes ]; then
  STACK=js
elif [ -f "$TREE/Gemfile" ]; then
  STACK=ruby
else
  STACK=js
fi

awk -F'\t' '$1 !~ /(^|\/)(spec|test)\// && $1 !~ /cassettes/ && $1 !~ /^docs\/.*\.md$/' \
  "$PKG/files.txt" > "$WORK/prod.txt"
cut -f1 "$WORK/prod.txt" > "$WORK/prod-paths.txt"
LINES=$(awk -F'\t' '{ s += substr($2, 2) + substr($3, 2) } END { print s + 0 }' "$WORK/prod.txt")

risk=""
add_risk() {
  if grep -qE "$2" "$WORK/prod-paths.txt"; then risk="$risk,$1"; fi
}
add_risk migration '(^|/)db/migrate/'
add_risk job '(^|/)app/jobs/|_job\.rb$|workers'
add_risk webhook 'webhook|receiver|callbacks'
add_risk serializer 'serializers'
RISK=${risk#,}
RISK=${RISK:-none}

if [ -z "$DEPTH_ARG" ] && [ -f "$TEAM_RULES" ]; then DEPTH_ARG=thorough; fi
DEPTH=${DEPTH_ARG:-quick}

printf '%s\n' "MODE=$MODE" "KEY=$KEY" "REPO=$REPO" "PR=$PR" "SHA=$SHA" "BASE=$BASE" "TREE=$TREE" \
  "STACK=$STACK" "LINES=$LINES" "RISK=$RISK" "DEPTH=$DEPTH" "TEAM=$TEAM" "FOREIGN_DROPPED=$FOREIGN_DROPPED" \
  > "$PKG/manifest.env"

headers=$(grep -c '^diff --git ' "$PKG/diff.patch" || true)
listed=$(wc -l < "$PKG/files.txt" | tr -d ' ')
[ "$headers" = "$listed" ] || die "diff.patch has $headers file headers, files.txt has $listed lines"

printf '%s\n' "$PKG"
