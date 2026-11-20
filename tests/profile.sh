#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$root/bin:$PATH"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export FLOW_HOME="$scratch/home" CLAUDE_CONFIG_DIR="$scratch/home"
unset $(compgen -e | grep '^CLAUDE_PLUGIN_OPTION_' || true)
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
expect_eq "bad switch" "FAIL p: tracker.write.assign 'yes' is not on, off or own" "$out"

mk p 'tracker.write.assign: own' 'tracker.stale_days: 5'
run sin-flow-profile validate p
expect_eq "assign own" "OK p" "$out"

mk p 'tracker.stale_days: 0'
run sin-flow-profile validate p
expect_eq "bad stale days" "FAIL p: tracker.stale_days '0' is not a number from 1 to 99" "$out"

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
expect_eq "bad group_by" "FAIL p: group_by 'team' is not one of epic, milestone, priority, label, rules, field:<name>" "$out"

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

run sin-flow-profile p mirror
expect_eq "mirror absent, no inferred line" off "$out"
run sin-flow-profile nosuch dir
expect_eq "unknown key dir rc" 2 "$rc"
expect_has "unknown key dir names the profiles" "profiles: p" "$out"
run sin-flow-profile p dir
expect_eq "known key dir" "$FLOW_HOME/profiles/p" "$out"
mk p
printf '## Inferred 2026-11-05\nnotes: work/<key>/<id>/; plan mirrored to the issue (issues enabled).\n' >> "$FLOW_HOME/profiles/p/profile.md"
run sin-flow-profile p mirror
expect_eq "mirror absent, inferred mirrored" github "$out"
for value in on github; do
  mk p "notes.mirror: $value"
  run sin-flow-profile p mirror
  expect_eq "mirror $value" github "$out"
done
mk p 'notes.mirror: off'
run sin-flow-profile p mirror
expect_eq "mirror off" off "$out"
mk p "notes.mirror: $adapter"
run sin-flow-profile p mirror
expect_eq "mirror script" "$adapter" "$out"
run sin-flow-profile validate p
expect_eq "mirror script valid" "OK p" "$out"
mk p 'notes.mirror: ~/adapter.sh'
run env HOME="$home_dir" sin-flow-profile p mirror
expect_eq "mirror tilde script" "$home_dir/adapter.sh" "$out"
mk p 'notes.mirror: yes'
run sin-flow-profile validate p
expect_eq "mirror bad value rc" 1 "$rc"
expect_has "mirror bad value" "notes.mirror 'yes' is not off, github or a path" "$out"
mk p 'notes.mirror: /nonexistent'
run sin-flow-profile p mirror
expect_eq "mirror missing script rc" 2 "$rc"
expect_has "mirror missing script" "notes.mirror /nonexistent is not an executable file" "$out"

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

options() { jq -n --argjson o "$1" '{pluginConfigs: {"other@x": {options: {handoff: "wrong"}}, "sin-flow@test": {options: $o}}}' > "$CLAUDE_CONFIG_DIR/settings.json"; }

rm -f "$CLAUDE_CONFIG_DIR/settings.json"
run sin-flow-profile user context_guard
expect_eq "user default number" 40 "$out"
run sin-flow-profile user branch_prefix
expect_eq "user no default" "" "$out"
run sin-flow-profile user nope
expect_eq "user unknown rc" 2 "$rc"
run sin-flow-profile model strong "$nongit"
expect_eq "model tier default" opus "$out"

options '{"handoff": "tmux", "context_guard": 30, "models_strong": "fable"}'
run sin-flow-profile user handoff
expect_eq "user from settings" tmux "$out"
run sin-flow-profile user context_guard
expect_eq "user number from settings" 30 "$out"
run sin-flow-profile model plan "$nongit"
expect_eq "stage model falls to tier" "fable -" "$out"
run sin-flow-profile model implementer hard "$nongit"
two_words=$out
run sin-flow-profile model "implementer hard" "$nongit"
expect_eq "role and level in one word are split" "$two_words" "$out"

mkdir -p "$FLOW_HOME/profiles/sh" "$FLOW_HOME/profiles/c"
printf -- '---\nkey: sh\nmeasure.doc: none\nsources.db.env_file: .env.db_readonly\nsources.db.var: DB_URL\n---\n## Measure\nshared line\n' > "$FLOW_HOME/profiles/sh/profile.md"
printf -- '---\nkey: c\nrepo.slug: acme/c\nextends: sh\n---\n## Measure\nown line\n' > "$FLOW_HOME/profiles/c/profile.md"
run sin-flow-profile c get sources.db.var
expect_eq "child reads the shared field" DB_URL "$out"
run sin-flow-profile validate c
expect_eq "child validates with shared measure.doc and sources" "OK c (sources.db.env_file relative, checked inside the checkout)" "$out"
printf -- '---\nkey: c\nrepo.slug: acme/c\nextends: sh\nmeasure.doc: none\n---\n## Measure\nown line\n' > "$FLOW_HOME/profiles/c/profile.md"
run sin-flow-profile validate c
expect_eq "child with own measure.doc validates with shared sources" "OK c (sources.db.env_file relative, checked inside the checkout)" "$out"
run sin-flow-profile validate sh
expect_eq "shared profile needs no slug" "OK sh (sources.db.env_file relative, checked inside the checkout)" "$out"
run sin-flow-profile c section Measure
expect_eq "section reads own then shared" "$(printf '## Measure\nown line\n## Measure\nshared line')" "$out"
run sin-flow-profile c fields
expect_has "fields has the shared field" "sources.db.var: DB_URL" "$out"
case "$out" in *"key: sh"*) fail "fields shows the shared key" ;; esac
run sin-flow-profile p fields
expect_eq "fields without extends rc" 0 "$rc"
printf -- '---\nkey: only\ntracker.board: acme#3\n---\n' > "$repo/.claude/flow.md"
run sin-flow-profile only fields
expect_eq "fields of a team file only key rc" 0 "$rc"
printf -- '---\nkey: c\nrepo.slug: acme/c\nextends: zz\nmeasure.doc: none\n---\n' > "$FLOW_HOME/profiles/c/profile.md"
run sin-flow-profile validate c
expect_has "extends names a missing profile" "extends zz: no profile at" "$out"
printf 'DB_URL=x\n' > "$scratch/shared.env"
chmod 644 "$scratch/shared.env"
printf -- '---\nkey: sh\nmeasure.doc: none\nsources.db.env_file: %s\nsources.db.var: DB_URL\n---\n' "$scratch/shared.env" > "$FLOW_HOME/profiles/sh/profile.md"
printf -- '---\nkey: c\nrepo.slug: acme/c\nextends: sh\n---\n' > "$FLOW_HOME/profiles/c/profile.md"
run sin-flow-profile validate c
expect_has "child checks the shared env file" "sources.db: $scratch/shared.env is not chmod 600" "$out"
printf -- '---\nkey: sh\nmeasure.doc: none\nrepo.base: main\n---\n## Measure\nshared line\n' > "$FLOW_HOME/profiles/sh/profile.md"
printf -- '---\nkey: c\nrepo.slug: acme/c\nextends: sh\nrepo.base: dev\n---\n' > "$FLOW_HOME/profiles/c/profile.md"
run sin-flow-profile c get repo.base
expect_eq "child value wins in get" dev "$out"
run sin-flow-profile c fields
expect_has "fields keeps the child value" "repo.base: dev" "$out"
case "$out" in *"repo.base: main"*) fail "fields shows the shared value of an overridden field" ;; esac
run sin-flow-profile c section Measure
expect_eq "section falls to the shared heading rc" 0 "$rc"
expect_eq "section of a child without the heading" "$(printf '## Measure\nshared line')" "$out"
printf -- '---\nkey: c\nrepo.slug: acme/c\nrepo.base: dev\nmeasure.doc: none\n---\n## Measure\nown line\n' > "$FLOW_HOME/profiles/c/profile.md"
run sin-flow-profile c get repo.base; plain_get="$rc $out"
run sin-flow-profile c get nope; plain_miss="$rc $out"
run sin-flow-profile c get measure.doc; plain_doc="$rc $out"
run sin-flow-profile c section Measure; plain_section="$rc $out"
run sin-flow-profile c section Nope; plain_nosection="$rc $out"
run sin-flow-profile c fields; plain_fields="$rc $out"
printf -- '---\nkey: c\nrepo.slug: acme/c\nextends: zz\nrepo.base: dev\nmeasure.doc: none\n---\n## Measure\nown line\n' > "$FLOW_HOME/profiles/c/profile.md"
run sin-flow-profile c get repo.base
expect_eq "missing parent, get a field" "$plain_get" "$rc $out"
run sin-flow-profile c get nope
expect_eq "missing parent, get an absent field" "$plain_miss" "$rc $out"
run sin-flow-profile c get measure.doc
expect_eq "missing parent, get measure.doc" "$plain_doc" "$rc $out"
run sin-flow-profile c section Measure
expect_eq "missing parent, section" "$plain_section" "$rc $out"
run sin-flow-profile c section Nope
expect_eq "missing parent, absent section" "$plain_nosection" "$rc $out"
run sin-flow-profile c fields
expect_eq "missing parent, fields" "$plain_fields" "$rc $(grep -v '^extends:' <<<"$out")"

shared_sources() { printf -- '---\nkey: sh\nmeasure.doc: none\n%s\n---\n' "$1" > "$FLOW_HOME/profiles/sh/profile.md"; }
own_sources() { printf -- '---\nkey: c\nrepo.slug: acme/c\nmeasure.doc: none\n%s\n---\n' "$1" > "$FLOW_HOME/profiles/c/profile.md"; }
child_extends() { printf -- '---\nkey: c\nrepo.slug: acme/c\nextends: sh\n%s\n---\n' "$1" > "$FLOW_HOME/profiles/c/profile.md"; }
printf 'DB_URL=x\n' > "$scratch/ok.env"
chmod 600 "$scratch/ok.env"
printf 'OTHER=x\n' > "$scratch/other.env"
chmod 600 "$scratch/other.env"
for env in "$scratch/shared.env" "$scratch/ok.env"; do
  own_sources "sources.db.env_file: $env"
  run sin-flow-profile validate c; plain=$out
  shared_sources "sources.db.env_file: $env"
  child_extends ""
  run sin-flow-profile validate c
  expect_eq "shared env_file without var, $(basename "$env")" "$plain" "$out"
done
own_sources "sources.db.var: DB_URL"
run sin-flow-profile validate c; plain=$out
shared_sources "sources.db.var: DB_URL"
child_extends ""
run sin-flow-profile validate c
expect_eq "shared var without env_file" "$plain" "$out"
own_sources "sources.db.env_file:"
run sin-flow-profile validate c; plain=$out
shared_sources "sources.db.env_file:"
child_extends ""
run sin-flow-profile validate c
expect_eq "shared empty env_file" "$plain" "$out"
for env in "$scratch/ok.env" "$scratch/other.env"; do
  own_sources "sources.db.env_file: $env
sources.db.var: DB_URL"
  run sin-flow-profile validate c; plain=$out
  shared_sources "sources.db.var: DB_URL"
  child_extends "sources.db.env_file: $env"
  run sin-flow-profile validate c
  case "$env" in
    */other.env) plain="$plain (set in $FLOW_HOME/profiles/sh/profile.md)" ;;
  esac
  expect_eq "own env_file with shared var, $(basename "$env")" "$plain" "$out"
done
expect_has "shared var is checked in the own env file" "variable DB_URL not in $scratch/other.env" "$out"
mkdir -p "$FLOW_HOME/profiles/zz2"
printf -- '---\nkey: zz2\nmeasure.doc: none\n---\n' > "$FLOW_HOME/profiles/zz2/profile.md"
run sin-flow-profile validate zz2
expect_eq "profile nobody extends needs a slug" "FAIL zz2: repo.slug missing" "$out"
rm -rf "$FLOW_HOME/profiles/sh" "$FLOW_HOME/profiles/c" "$FLOW_HOME/profiles/zz2"

mkdir -p "$FLOW_HOME/profiles/sh" "$FLOW_HOME/profiles/c" "$FLOW_HOME/profiles/zz2"
printf -- '---\nkey: sh\nmeasure.doc: none\nsources.db.var: DB_URL\n---\n' > "$FLOW_HOME/profiles/sh/profile.md"
printf -- '---\nkey: c\nrepo.slug: acme/c\nextends: sh\nsources.db.var:\n---\n' > "$FLOW_HOME/profiles/c/profile.md"
run sin-flow-profile c get sources.db.var
expect_eq "empty own value reads the shared value in get" DB_URL "$out"
run sin-flow-profile c fields
expect_has "empty own value reads the shared value in fields" "sources.db.var: DB_URL" "$out"
printf -- '---\nkey: c\nrepo.slug: acme/c\nextends: sh\nsources.db.var: OWN_URL\n---\n' > "$FLOW_HOME/profiles/c/profile.md"
run sin-flow-profile c fields
case "$out" in *"sources.db.var: DB_URL"*) fail "fields shows the shared value of a field with an own value" ;; esac

printf -- '---\nkey: c\nextends: c\nmeasure.doc: none\n---\n' > "$FLOW_HOME/profiles/c/profile.md"
run sin-flow-profile validate c
expect_has "a profile that extends itself needs a slug" "repo.slug missing" "$out"
expect_has "a profile cannot extend itself" "extends c: a profile cannot extend itself" "$out"

printf -- '---\nkey: sh\nextends: zz2\nmeasure.doc: none\n---\n' > "$FLOW_HOME/profiles/sh/profile.md"
printf -- '---\nkey: zz2\nmeasure.doc: none\nsources.db.var: GRAND_URL\n---\n' > "$FLOW_HOME/profiles/zz2/profile.md"
printf -- '---\nkey: c\nrepo.slug: acme/c\nextends: sh\nmeasure.doc: none\n---\n' > "$FLOW_HOME/profiles/c/profile.md"
run sin-flow-profile validate c
expect_has "a shared profile with its own extends is an error" "extends sh: sh has its own extends, and only one level is read" "$out"
run sin-flow-profile c get sources.db.var
expect_eq "extends reads one level, get rc" 1 "$rc"
expect_eq "extends reads one level, get" "" "$out"
run sin-flow-profile c fields
case "$out" in *"GRAND_URL"*) fail "fields reads the parent of the parent" ;; esac

printf 'DB_URL=x\n' > "$scratch/inherited.env"
chmod 600 "$scratch/inherited.env"
printf -- '---\nkey: sh\nmeasure.doc: none\nsources.db.env_file: %s/absent.env\nsources.db.var: DB_URL\n---\n' "$scratch" > "$FLOW_HOME/profiles/sh/profile.md"
printf -- '---\nkey: c\nrepo.slug: acme/c\nextends: sh\n---\n' > "$FLOW_HOME/profiles/c/profile.md"
run sin-flow-profile validate c
expect_has "a missing shared env file names the shared profile" "sources.db: $scratch/absent.env missing (set in $FLOW_HOME/profiles/sh/profile.md)" "$out"
run sin-flow-profile validate sh
expect_has "a missing own env file names no other profile" "sources.db: $scratch/absent.env missing" "$out"
case "$out" in *"(set in"*) fail "an own env file error names another profile" ;; esac
printf -- '---\nkey: sh\nmeasure.doc: none\nsources.db.env_file: %s\nsources.db.var: NOPE_URL\n---\n' "$scratch/inherited.env" > "$FLOW_HOME/profiles/sh/profile.md"
run sin-flow-profile validate c
expect_has "a missing shared var names the shared profile" "variable NOPE_URL not in $scratch/inherited.env (set in $FLOW_HOME/profiles/sh/profile.md)" "$out"
rm -rf "$FLOW_HOME/profiles/sh" "$FLOW_HOME/profiles/c" "$FLOW_HOME/profiles/zz2"
out=$(CLAUDE_PLUGIN_OPTION_HANDOFF=iterm sin-flow-profile user handoff)
expect_eq "user env wins" iterm "$out"

mkdir -p "$scratch/bin"
cat > "$scratch/bin/claude" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  "plugin list --json") echo '[{"id":"sin-flow@test","enabled":true}]' ;;
  "plugin configure sin-flow@test --values-stdin") cat > "$CLAUDE_CONFIG_DIR/configured.json" ;;
  *) exit 9 ;;
esac
FAKE
chmod +x "$scratch/bin/claude"
printf -- '---\nchat_language: uk\nmodels.strong: fable\nmodels.plan: opus\nwork_remote: "git@example.com:a/b.git"  # note\n---\nFree notes.\n' > "$FLOW_HOME/user.md"
run env PATH="$scratch/bin:$PATH" sin-flow-profile migrate-user
expect_eq "migrate rc" 0 "$rc"
expect_has "migrate skips stage model" "not migrated (not a user key): models_plan" "$out"
expect_eq "migrate payload" '{"chat_language":"uk","models_strong":"fable","work_remote":"git@example.com:a/b.git"}' "$(jq -cS . "$CLAUDE_CONFIG_DIR/configured.json")"
expect_eq "migrate keeps notes" "Free notes." "$(cat "$FLOW_HOME/user.md")"
expect_has "migrate backup" "models.plan: opus" "$(cat "$FLOW_HOME"/backups/*/user.md)"
printf -- '---\ncodex_review: on\ncodex_watch: orca\n---\n' > "$FLOW_HOME/user.md"
run env PATH="$scratch/bin:$PATH" sin-flow-profile migrate-user
expect_eq "migrate old reviewer keys" '{"extra_reviewers":"codex","reviewer_watch":"orca"}' "$(jq -cS . "$CLAUDE_CONFIG_DIR/configured.json")"
printf -- '---\ncodex_review: off\nhandoff: tmux\n---\n' > "$FLOW_HOME/user.md"
run env PATH="$scratch/bin:$PATH" sin-flow-profile migrate-user
expect_eq "migrate codex_review off" '{"handoff":"tmux"}' "$(jq -cS . "$CLAUDE_CONFIG_DIR/configured.json")"
expect_eq "migrate codex_review off is not skipped" "" "$(grep 'not migrated' <<<"$out" || true)"

echo "ok: $cases cases"
