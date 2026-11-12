#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$root/bin:$PATH"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export FLOW_HOME="$scratch/home" CLAUDE_CONFIG_DIR="$scratch/home"
unset $(compgen -e | grep '^CLAUDE_PLUGIN_OPTION_' || true)
mkdir -p "$FLOW_HOME/profiles/widgets"
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

run() {
  rc=0
  out=$("$@" 2>"$scratch/err") || rc=$?
  err=$(cat "$scratch/err")
}

options() { jq -n --argjson o "$1" '{pluginConfigs: {"sin-flow@test": {options: $o}}}' > "$CLAUDE_CONFIG_DIR/settings.json"; }
row() { printf '%s\t%s\t%s\t%s\n' "$@"; }

plain=$(mktemp -d "$scratch/plain.XXXXXX")
repo=$(mktemp -d "$scratch/repo.XXXXXX")
git -C "$repo" init -q
git -C "$repo" remote add origin git@github.com:acme/widgets.git
profile() { { printf -- '---\nkey: widgets\nrepo.slug: acme/widgets\nmeasure.doc: none\n'; printf '%s\n' "$@"; printf -- '---\n'; } > "$FLOW_HOME/profiles/widgets/profile.md"; }
profile

while read -r role level want_model want_effort; do
  run sin-flow-profile model "$role" "$level" "$plain"
  expect_eq "default $role $level" "$want_model $want_effort" "$out"
done <<'TABLE'
setup * opus -
sync * opus -
ingest * opus -
plan * opus -
exec * opus -
exec mid opus -
exec strong opus -
review * opus -
learning * opus -
implementer cheap haiku medium
implementer mid sonnet medium
implementer hard opus high
implementer strong opus high
implementer haiku haiku medium
implementer sonnet sonnet medium
implementer opus opus high
implementer fix-2 same -
implementer fix-3 opus high
fix * sonnet high
fix mid sonnet high
fix hard opus high
fix strong opus high
preship * opus high
audit * sonnet low
adversarial * sonnet medium
visual * sonnet medium
shipper * sonnet low
rebase * sonnet low
lens-context * sonnet medium
lens-code * opus high
lens-fit * sonnet high
lens-all * opus high
lens-verify * opus high
lens-settle * opus high
analyst * sonnet medium
analyst hard opus high
plan-audit * sonnet medium
ingest-reader * sonnet medium
board * haiku low
review-poster * sonnet low
learning-reader * sonnet medium
learning-consolidator * opus high
TABLE

expect_eq "each default role is in the table" "" "$(cut -f1 "$root/examples/models.tsv" | sed 1d | sort -u | while read -r r; do grep -q "^$r " "$0" || echo "$r"; done)"

unread() {
  local r
  cut -f1 "$root/examples/models.tsv" | sed 1d | sort -u | while read -r r; do
    case "$r" in
      setup|sync|ingest|plan|exec|review|learning) grep -qF 'model "${model_name' "$root/bin/sin-flow-handoff" || echo "$r" ;;
      *) grep -rqF -e "\`$r\`" -e "model $r" "$root/skills" "$root/agents" "$root/bin" || echo "$r" ;;
    esac
  done
}
expect_eq "each grid role has a reader" "" "$(unread)"

run sin-flow-profile model strong "$plain"
expect_eq "tier form prints one word" opus "$out"
run sin-flow-profile model exec "$plain"
expect_eq "stage form with a folder" "opus -" "$out"
run sin-flow-profile model nope "$plain"
expect_eq "unknown role rc" 2 "$rc"
expect_has "unknown role message" "no grid row for role 'nope'" "$err"

options '{"models_mid": "fable"}'
run sin-flow-profile model implementer mid "$plain"
expect_eq "a tier word resolves through the option" "fable medium" "$out"
rm "$CLAUDE_CONFIG_DIR/settings.json"

{ row role level model effort; row implementer hard mid high; row exec mid sonnet high; row shipper '*' cheap low; } > "$FLOW_HOME/models.tsv"
run sin-flow-profile model implementer hard "$plain"
expect_eq "user row wins" "sonnet high" "$out"
run sin-flow-profile model implementer strong "$plain"
expect_eq "user file leaves the other rows" "opus high" "$out"
run sin-flow-profile model exec mid "$plain"
expect_eq "user row for one exec level" "sonnet high" "$out"
run sin-flow-profile model exec hard "$plain"
expect_eq "exec level with no row takes the any row" "opus -" "$out"
run sin-flow-profile model shipper "$plain"
expect_eq "user any row wins" "haiku low" "$out"

{ row role level model effort; row implementer hard fable xhigh; } > "$FLOW_HOME/profiles/widgets/models.tsv"
run sin-flow-profile model implementer hard "$repo"
expect_eq "profile row wins over the user row" "fable xhigh" "$out"
run sin-flow-profile model implementer hard "$plain"
expect_eq "profile row holds for its repo only" "sonnet high" "$out"
run sin-flow-profile model exec mid "$repo"
expect_eq "user row holds in a repo with a profile" "sonnet high" "$out"

profile 'models.exec: fable' 'models.mid: opus'
run sin-flow-profile model exec mid "$repo"
expect_eq "models.exec wins over the grid model" "fable high" "$out"
run sin-flow-profile model audit "$repo"
expect_eq "models.mid resolves the tier word" "opus low" "$out"
profile

{ row role level model effort; printf 'implementer mid gpt high\n'; row visual '*' mid top; row rebase '*' strong high; } > "$FLOW_HOME/models.tsv"
run sin-flow-profile model implementer mid "$plain"
expect_eq "malformed row rc" 0 "$rc"
expect_eq "malformed row falls to the default row" "sonnet medium" "$out"
expect_has "malformed row message" "models.tsv:2: not a grid row" "$err"
run sin-flow-profile model visual "$plain"
expect_eq "bad effort falls to the default row" "sonnet medium" "$out"
expect_has "bad effort message" "models.tsv:3: not a grid row" "$err"
run sin-flow-profile model rebase "$plain"
expect_eq "good row beside a malformed row" "opus high" "$out"
rm "$FLOW_HOME/models.tsv"

{ row role level model effort; row visual '*' same low; row implementer fix-2 same -; } > "$FLOW_HOME/models.tsv"
run sin-flow-profile model visual "$plain"
expect_eq "same on another role falls to the default row" "sonnet medium" "$out"
expect_has "same on another role message" "models.tsv:2: not a grid row" "$err"
expect_has "same on another role names the rule" "valid only on an implementer row" "$err"
run sin-flow-profile model implementer fix-2 "$plain"
expect_eq "same on implementer fix-2 stays valid" "same -" "$out"
rm "$FLOW_HOME/models.tsv"

run sin-flow-profile model exec "$scratch/no-such-folder"
expect_eq "a missing folder rc" 2 "$rc"
expect_has "a missing folder message" "not a folder: $scratch/no-such-folder" "$err"
run sin-flow-profile model implementer hard "$plain"
expect_eq "a level word is still read as a level" "opus high" "$out"

options '{"handoff": "print"}'
touch "$plain/x.md"
{ row role level model effort; row exec mid mid high; } > "$FLOW_HOME/models.tsv"
out=$(sin-flow-handoff --probe --cwd "$plain" --level mid sin-flow:exec "$plain/x.md" | sed -n 2p)
expect_has "hand-off passes the grid model and effort" "--model 'sonnet' --effort 'high' '/sin-flow:exec" "$out"
out=$(sin-flow-handoff --probe --cwd "$plain" --level hard sin-flow:exec "$plain/x.md" | sed -n 2p)
expect_has "hand-off with no effort in the grid" "--model 'opus' '/sin-flow:exec" "$out"
out=$(sin-flow-handoff --probe --cwd "$plain" --level mid --model fable --effort low sin-flow:exec "$plain/x.md" | sed -n 2p)
expect_has "hand-off options win over the grid" "--model 'fable' --effort 'low' '/sin-flow:exec" "$out"
rm "$FLOW_HOME/models.tsv"
out=$(sin-flow-handoff --probe --cwd "$plain" --model fable --effort low sin-flow:nope "$plain/x.md" 2>/dev/null | sed -n 2p)
expect_has "a grid failure does not stop a hand-off that names its model" "--model 'fable' --effort 'low' '/sin-flow:nope" "$out"
rc=0
sin-flow-handoff --probe --cwd "$plain" sin-flow:nope "$plain/x.md" >/dev/null 2>&1 || rc=$?
expect_eq "a grid failure without --model stops the hand-off" 2 "$rc"

echo "ok: $cases cases"
