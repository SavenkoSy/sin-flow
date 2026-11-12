#!/usr/bin/env bash
set -uo pipefail

tests="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset FLOW_HOME
failed=0
suites=0

for suite in "$tests"/*.sh; do
  name=$(basename "$suite")
  [ "$name" = run-all.sh ] && continue
  suites=$((suites + 1))
  mkdir -p "$scratch/$name/home"
  if HOME="$scratch/$name/home" bash "$suite" >"$scratch/$name/out" 2>&1; then
    printf 'ok    %-24s %s\n' "$name" "$(tail -1 "$scratch/$name/out")"
  else
    failed=$((failed + 1))
    printf 'FAIL  %-24s\n' "$name"
    tail -20 "$scratch/$name/out" | sed 's/^/      /'
  fi
done

echo "suites: $suites, failed: $failed"
[ "$failed" -eq 0 ]
