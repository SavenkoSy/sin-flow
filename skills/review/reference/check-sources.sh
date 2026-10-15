#!/usr/bin/env bash
set -euo pipefail

LOCK="${REVIEW_LOCK:-$(cd "$(dirname "$0")" && pwd -P)/sources.lock.tsv}"

tail -n +2 "$LOCK" | while IFS=$'\t' read -r lens repo path sha date note; do
  [ -z "$lens" ] && continue
  [ "$sha" = "-" ] && continue
  if ! result=$(gh api "repos/$repo/commits?path=$path&per_page=1" --jq '.[0].sha + "|" + .[0].commit.committer.date' 2>&1); then
    echo "$lens $repo $path ERROR $result"
    continue
  fi
  new_sha="${result%%|*}"
  new_date="${result##*|}"
  new_date="${new_date%%T*}"
  if [ -z "$new_sha" ] || [ "$new_sha" = "null" ]; then
    echo "$lens $repo $path ERROR empty response"
    continue
  fi
  if [ "$new_sha" != "$sha" ]; then
    echo "$lens $repo $path ${sha:0:8}→${new_sha:0:8} $new_date https://github.com/$repo/compare/$sha...$new_sha"
  fi
done

exit 0
