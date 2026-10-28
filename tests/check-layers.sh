#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

export FLOW_HOME="$scratch/home"
mkdir -p "$FLOW_HOME/profiles/acme-shop" "$FLOW_HOME/profiles/abc" "$FLOW_HOME/profiles/core" "$scratch/repo"
printf -- '---\nkey: acme-shop\nrepo.slug: someorg/widgetry\nrepo.path: ~/src/widgetry\n---\n' > "$FLOW_HOME/profiles/acme-shop/profile.md"
cd "$scratch/repo"
git init -q
git config user.email t@example.com
git config user.name t
echo "the plugin already says Marker**" > base.md
git add base.md
git commit -qm base
git branch base

check() { LAYER_BASE=base bash "$root/scripts/check-layers.sh" 2>&1; }
added() { printf '%s\n' "$@" > added.md; }

added "plain text"
out=$(check) || fail "case 1: clean tree fails: $out"

added "see PRIVATE-RUNBOOK.md"
out=$(check) || fail "case 2: no private-terms.txt yet, but it failed: $out"
printf '# a comment line\n\nPRIVATE-RUNBOOK.md\nTEAM HEADING\nMarker**\n' > "$FLOW_HOME/private-terms.txt"
out=$(check) && fail "case 3: a term from private-terms.txt passes"
grep -qF "private: 'PRIVATE-RUNBOOK.md'" <<<"$out" || fail "case 3: got $out"

added "a heading TEAM HEADING"
out=$(check) && fail "case 4: a term with spaces passes"
grep -qF "private: 'TEAM HEADING'" <<<"$out" || fail "case 4: got $out"

added "write a comment line and Marker** here"
out=$(check) || fail "case 5: a comment line or a term already on the base fails: $out"

added "the acme-shop repo"
out=$(check) && fail "case 6: a profile folder name passes"
grep -qF "private: 'acme-shop'" <<<"$out" || fail "case 6: got $out"

added "abc and core stay out"
out=$(check) || fail "case 7: a short or excluded folder name fails: $out"

added "the widgetry repo"
out=$(check) && fail "case 8: a repo.slug part passes"
grep -qF "private: 'widgetry'" <<<"$out" || fail "case 8: got $out"

echo "ok: 8 cases"
