#!/usr/bin/env bash
set -uo pipefail

root=$(git rev-parse --show-toplevel)
cd "$root"
base=${LAYER_BASE:-origin/main}
tools='orca|codex|cmux|tmux|osascript|circleci|wezterm|kitty'
fail=0

while IFS= read -r f; do
  case "$f" in bin/handoff/*|scripts/*) continue ;; esac
  head -c 200 "$f" | grep -q '^#!' || continue
  grep -qE "(^|[^a-zA-Z_./-])($tools)[[:space:]]" "$f" || continue
  grep -qE 'user\.md|user_field|pref |sin-flow-profile' "$f" && continue
  echo "layer: $f calls a third-party tool and reads no user.md or profile key"
  fail=1
done < <(git ls-files bin hooks skills | grep -v node_modules)

flow_home=${FLOW_HOME:-$HOME/.claude/sin-flow}
if [ -d "$flow_home/profiles" ] && git rev-parse --verify --quiet "$base" >/dev/null; then
  terms=$( {
    printf '%s\n' "$HOME"
    sed -n 's/^repo\.slug:[[:space:]]*//p' "$flow_home"/profiles/*/profile.md | tr '/' '\n'
    sed -n 's/^repo\.path:[[:space:]]*//p' "$flow_home"/profiles/*/profile.md | sed 's#.*/##'
  } | tr -d '"' | grep -vxF -e '' -e sin-flow -e "$(basename "$root")" | sort -u)
  added=$( { git diff "$base" -- . ':!*.html'; git ls-files --others --exclude-standard | grep -v '\.html$' | xargs -I{} sed 's/^/+/' {}; } \
    | grep '^+' | grep -v '^+++')
  while IFS= read -r term; do
    [ ${#term} -ge 4 ] || continue
    git grep -qiF -- "$term" "$base" -- . ':!*.html' && continue
    hit=$(grep -inF -- "$term" <<<"$added" | head -1)
    [ -z "$hit" ] || { echo "private: '$term' in an added line: ${hit:0:160}"; fail=1; }
  done <<<"$terms"
fi

exit $fail
