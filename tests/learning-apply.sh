#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
make="$root/skills/learning/scripts/make-apply.sh"
scratch=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$scratch"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

export CLAUDE_PLUGIN_ROOT="$scratch/plugin"
export FLOW_HOME="$scratch/flow"
day="$scratch/learning/2026-01-02"
mkdir -p "$CLAUDE_PLUGIN_ROOT/skills/demo" "$CLAUDE_PLUGIN_ROOT/scripts" "$FLOW_HOME/profiles/acme" "$day"
printf 'one\ntwo\nthree\nfour\nfive\nsix\nseven\n' > "$CLAUDE_PLUGIN_ROOT/skills/demo/SKILL.md"
printf '[ ! -e "%s/red" ]\n' "$scratch" > "$CLAUDE_PLUGIN_ROOT/scripts/check-layers.sh"
printf 'key: acme\n' > "$FLOW_HOME/profiles/acme/profile.md"

propose() { mkdir -p "$(dirname "$day/$1")"; cat > "$day/$1"; }
sed 's/^one$/ONE/' "$CLAUDE_PLUGIN_ROOT/skills/demo/SKILL.md" | propose flow-exec/proposed/plugin/skills/demo/SKILL.md
sed 's/^seven$/SEVEN/' "$CLAUDE_PLUGIN_ROOT/skills/demo/SKILL.md" | propose flow-plan/proposed/plugin/skills/demo/SKILL.md
printf 'a new file\n' | propose flow-exec/proposed/plugin/skills/demo/new.md
printf 'key: acme\nbase: main\n' | propose flow-exec/proposed/user/profiles/acme/profile.md
cat "$CLAUDE_PLUGIN_ROOT/scripts/check-layers.sh" | propose flow-plan/proposed/plugin/scripts/check-layers.sh

"$make" "$day" >/dev/null || fail "case 1: make-apply fails on changes that do not overlap"
t="$day/apply/targets.tsv"
[ "$(head -1 "$t")" = "$(printf 'layer\troot\tpath\ttarget\tsha256\tproposed\tstages')" ] || fail "case 2: the column order"
[ "$(wc -l < "$t" | tr -d ' ')" = 4 ] || fail "case 3: three targets, a copy equal to the live file is left out: $(cat "$t")"
cell() { awk -F'\t' -v p="$1" -v c="$2" '$3 == p { print $c }' "$t"; }
[ "$(cell skills/demo/SKILL.md 1)|$(cell skills/demo/SKILL.md 4)|$(cell skills/demo/SKILL.md 7)" = "plugin|$CLAUDE_PLUGIN_ROOT/skills/demo/SKILL.md|flow-exec,flow-plan" ] || fail "case 4: the plugin row: $(grep SKILL "$t")"
[ "$(cell profiles/acme/profile.md 1)|$(cell profiles/acme/profile.md 4)" = "profile|$FLOW_HOME/profiles/acme/profile.md" ] || fail "case 5: the profile row"
[ "$(cell skills/demo/new.md 5)" = absent ] || fail "case 6: a new file has sha absent"
[ "$(sed -n '1p;7p' "$day/apply/proposed/plugin/skills/demo/SKILL.md" | tr '\n' ' ')" = "ONE SEVEN " ] || fail "case 7: two stages on one file are merged"
grep -q '^+base: main' "$day/apply/patches.diff" || fail "case 8: patches.diff holds the profile change"

echo "edited by another session" >> "$CLAUDE_PLUGIN_ROOT/skills/demo/SKILL.md"
rc=0; bash "$day/apply/apply-plugin.sh" >/dev/null || rc=$?
[ "$rc" = 3 ] || fail "case 9: a changed live file stops the apply, rc $rc"
[ ! -e "$CLAUDE_PLUGIN_ROOT/skills/demo/new.md" ] || fail "case 9: nothing is applied after a sha miss"
sed -i.bak '$d' "$CLAUDE_PLUGIN_ROOT/skills/demo/SKILL.md" && rm "$CLAUDE_PLUGIN_ROOT/skills/demo/SKILL.md.bak"

bash "$day/apply/apply-user.sh" >/dev/null || fail "case 10: apply-user fails"
grep -q '^base: main$' "$FLOW_HOME/profiles/acme/profile.md" || fail "case 10: the profile is not applied"
[ "$(cat "$scratch/learning/backups/2026-01-02/profiles/acme/profile.md")" = "key: acme" ] || fail "case 11: the backup holds the old profile"
[ "$(head -1 "$CLAUDE_PLUGIN_ROOT/skills/demo/SKILL.md")" = one ] || fail "case 12: apply-user leaves the plugin alone"

touch "$scratch/red"
rc=0; bash "$day/apply/apply-plugin.sh" >/dev/null || rc=$?
[ "$rc" = 5 ] || fail "case 13: a failed layer check stops the apply, rc $rc"
[ "$(head -1 "$CLAUDE_PLUGIN_ROOT/skills/demo/SKILL.md")" = one ] || fail "case 13: the skill is restored"
[ ! -e "$CLAUDE_PLUGIN_ROOT/skills/demo/new.md" ] || fail "case 13: the new file is removed"
rm "$scratch/red"

bash "$day/apply/apply-plugin.sh" >/dev/null || fail "case 14: apply-plugin fails"
[ "$(sed -n '1p;7p' "$CLAUDE_PLUGIN_ROOT/skills/demo/SKILL.md" | tr '\n' ' ')" = "ONE SEVEN " ] || fail "case 14: the skill is not applied"
[ -f "$CLAUDE_PLUGIN_ROOT/skills/demo/new.md" ] || fail "case 14: the new file is not applied"
[ "$(head -1 "$scratch/learning/backups/2026-01-02/skills/demo/SKILL.md")" = one ] || fail "case 15: the backup holds the old skill"
[ ! -e "$CLAUDE_PLUGIN_ROOT/skills/demo/SKILL.md.new" ] || fail "case 16: no .new file is left"

sed 's/^one$/UNO/' "$day/flow-exec/proposed/plugin/skills/demo/SKILL.md" | sed 's/^ONE$/UNO/' | propose flow-sync/proposed/plugin/skills/demo/SKILL.md
printf 'one\ntwo\nthree\nfour\nfive\nsix\nseven\n' > "$CLAUDE_PLUGIN_ROOT/skills/demo/SKILL.md"
rc=0; out=$("$make" "$day" 2>&1) || rc=$?
[ "$rc" = 1 ] || fail "case 17: two stages on the same line must stop, rc $rc"
grep -q 'plugin/skills/demo/SKILL.md' <<<"$out" || fail "case 17: the conflict names the file: $out"
printf 'UNO\ntwo\nthree\nfour\nfive\nsix\nSEVEN\n' | propose merged/proposed/plugin/skills/demo/SKILL.md
"$make" "$day" >/dev/null || fail "case 18: a merged copy resolves the conflict"
[ "$(head -1 "$day/apply/proposed/plugin/skills/demo/SKILL.md")" = UNO ] || fail "case 18: the merged copy wins"

echo "ok: 18 cases"
