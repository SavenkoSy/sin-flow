#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$root/bin:$PATH"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export FLOW_HOME="$scratch/home"
mkdir -p "$FLOW_HOME/profiles"
cases=0

fail() { echo "FAIL: $*" >&2; exit 1; }

expect_eq() {
  cases=$((cases + 1))
  [ "$2" = "$3" ] || fail "$1: want [$2], got [$3]"
}

expect_has() {
  cases=$((cases + 1))
  case "$3" in *"$2"*) ;; *) fail "$1: want substring [$2], got [$3]" ;; esac
}

mk() {
  local key="$1"
  shift
  mkdir -p "$FLOW_HOME/profiles/$key"
  { printf -- '---\nkey: %s\nrepo.slug: acme/%s\nmeasure.doc: none\n' "$key" "$key"; printf '%s\n' "$@"; printf -- '---\n'; } > "$FLOW_HOME/profiles/$key/profile.md"
}

run() {
  rc=0
  out=$("$@" 2>&1) || rc=$?
}

nongit=$(mktemp -d "$scratch/plain.XXXXXX")

mk p 'tracker.write.light: on'
run sin-flow-profile validate p
expect_eq "switch on rc" 0 "$rc"
expect_eq "switch on" "OK p" "$out"

mk p 'tracker.write.light: "on"'
run sin-flow-profile validate p
expect_eq "quoted on" "OK p" "$out"

mk p 'tracker.write.assign: yes'
run sin-flow-profile validate p
expect_eq "bad switch rc" 1 "$rc"
expect_eq "bad switch" "FAIL p: tracker.write.assign 'yes' is not on or off" "$out"

for sw in light status; do
  mk p "tracker.write.$sw: maybe"
  run sin-flow-profile validate p
  expect_eq "bad switch $sw rc" 1 "$rc"
  expect_eq "bad switch $sw" "FAIL p: tracker.write.$sw 'maybe' is not on or off" "$out"
done

mk p 'tracker.write.light: off' 'tracker.write.assign: off' 'tracker.write.status: off'
run sin-flow-profile validate p
expect_eq "switches off" "OK p" "$out"

mk p 'group_by: team'
run sin-flow-profile validate p
expect_eq "bad group_by rc" 1 "$rc"
expect_eq "bad group_by" "FAIL p: group_by 'team' is not one of epic, milestone, priority, label, rules" "$out"

for g in epic milestone priority label rules; do
  mk p "group_by: $g"
  run sin-flow-profile validate p
  expect_eq "group_by $g" "OK p" "$out"
done

mk p 'tracker.adapter: rel/path'
run sin-flow-profile validate p
expect_eq "relative adapter rc" 1 "$rc"
expect_has "relative adapter" "tracker.adapter rel/path is not an absolute or ~ path" "$out"

mk p 'tracker.adapter: /nonexistent'
run sin-flow-profile validate p
expect_eq "missing adapter rc" 1 "$rc"
expect_has "missing adapter" "tracker.adapter /nonexistent is not an executable file" "$out"

adapter="$scratch/adapter.sh"
printf '#!/bin/sh\n' > "$adapter"
chmod +x "$adapter"
mk p "tracker.adapter: $adapter"
run sin-flow-profile validate p
expect_eq "executable adapter" "OK p" "$out"

adapter_dir="$scratch/trackers"
mkdir -p "$adapter_dir"
mk p "tracker.adapter: $adapter_dir"
run sin-flow-profile validate p
expect_eq "directory adapter rc" 1 "$rc"
expect_has "directory adapter" "tracker.adapter $adapter_dir is not an executable file" "$out"

home_dir=$(mktemp -d "$scratch/userhome.XXXXXX")
cp "$adapter" "$home_dir/adapter.sh"
mk p 'tracker.adapter: ~/adapter.sh'
run env HOME="$home_dir" sin-flow-profile validate p
expect_eq "tilde adapter" "OK p" "$out"
run env HOME="$scratch/nowhere" sin-flow-profile validate p
expect_eq "tilde adapter missing rc" 1 "$rc"
expect_has "tilde adapter missing" "tracker.adapter ~/adapter.sh is not an executable file" "$out"

mk p
run sin-flow-profile validate p
expect_eq "no new keys" "OK p" "$out"

mk q 'tracker.board: acme#1'
cd "$nongit"
run sin-flow-profile resolve q
expect_eq "resolve rc" 0 "$rc"
expect_eq "resolve argument" "key: q · tracker: acme#1 · from: argument · cwd profile: none" "$out"

run sin-flow-profile resolve nope
expect_eq "unknown key rc" 2 "$rc"
expect_eq "unknown key" "usage: /sin-flow:sync <key> [take <batch> | new]   keys: p q" "$out"

run sin-flow-profile resolve
expect_eq "no key no cwd rc" 2 "$rc"
expect_has "no key no cwd" "usage: /sin-flow:sync" "$out"

mk q 'tracker.board: null'
run sin-flow-profile resolve q
expect_eq "null board" "key: q · tracker: none · from: argument · cwd profile: none" "$out"

mk q 'tracker.board: acme#1' "tracker.adapter: $adapter"
run sin-flow-profile resolve q
expect_eq "adapter wins" "key: q · tracker: $adapter · from: argument · cwd profile: none" "$out"

mk q 'tracker.board: acme#1'
mk w
repo=$(mktemp -d "$scratch/repo.XXXXXX")
git -C "$repo" init -q
git -C "$repo" remote add origin git@github.com:acme/widgets.git
mk widgets
sed -i.bak 's#^repo.slug:.*#repo.slug: acme/widgets#' "$FLOW_HOME/profiles/widgets/profile.md"
cd "$repo"
run sin-flow-profile resolve q
expect_eq "other key in repo" "key: q · tracker: acme#1 · from: argument · cwd profile: widgets" "$out"
run sin-flow-profile resolve
expect_eq "cwd key" "key: widgets · tracker: none · from: cwd · cwd profile: widgets" "$out"

mkdir -p "$repo/.claude"
printf -- '---\nkey: team\ntracker.board: acme#2\n---\n' > "$repo/.claude/flow.md"
run sin-flow-profile resolve team
expect_eq "team key argument rc" 0 "$rc"
expect_eq "team key argument" "key: team · tracker: acme#2 · from: argument · cwd profile: widgets" "$out"

printf -- '---\nkey: widgets\ntracker.board: acme#2\ntracker.adapter: %s\ntracker.write.light: on\ntracker.write.assign: on\ntracker.write.status: on\ngroup_by: label\n---\n' "$adapter" > "$repo/.claude/flow.md"
for field in tracker.write.light tracker.write.assign tracker.write.status group_by tracker.adapter; do
  run sin-flow-profile widgets get "$field"
  expect_eq "$field not from team file rc" 1 "$rc"
  expect_eq "$field not from team file" "" "$out"
done
run sin-flow-profile widgets get tracker.board
expect_eq "board from team file" "acme#2" "$out"
run sin-flow-profile resolve widgets
expect_eq "resolve ignores team adapter" "key: widgets · tracker: acme#2 · from: argument · cwd profile: widgets" "$out"

echo "ok: $cases cases"
