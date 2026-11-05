#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$root"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export FLOW_HOME="$scratch/home" CLAUDE_CONFIG_DIR="$scratch/home"
unset $(compgen -e | grep '^CLAUDE_PLUGIN_OPTION_' || true)
mkdir -p "$FLOW_HOME" "$scratch/bin"
export PATH="$scratch/bin:$PATH"
cases=0

fail() { echo "FAIL: $*" >&2; exit 1; }

expect_eq() {
  cases=$((cases + 1))
  [ "$2" = "$3" ] || fail "$1: want [$2], got [$3]"
}

cat > "$scratch/bin/claude" <<'FAKE'
#!/usr/bin/env bash
[ -z "${FAKE_FAIL:-}" ] || { echo "configure failed" >&2; exit 1; }
case "$*" in
  "plugin list --json") echo '[{"id":"sin-flow@test","enabled":true}]' ;;
  "plugin configure sin-flow@test --values-stdin") cat > "$CLAUDE_CONFIG_DIR/configured.json" ;;
  *) exit 9 ;;
esac
FAKE
chmod +x "$scratch/bin/claude"

hook() { echo '{}' | bash "$root/hooks/scripts/user-migrate.sh" | jq -r '.hookSpecificOutput.additionalContext // empty' | cut -d' ' -f1-4; }

expect_eq "no user.md" "" "$(hook)"

printf 'Notes only.\n' > "$FLOW_HOME/user.md"
expect_eq "no frontmatter" "" "$(hook)"

printf -- '---\nhandoff: tmux\n---\nNotes.\n' > "$FLOW_HOME/user.md"
expect_eq "fails" "sin-flow could not move" "$(FAKE_FAIL=1 hook)"
expect_eq "fails keeps user.md" "---" "$(sed -n 1p "$FLOW_HOME/user.md")"

expect_eq "moves" "sin-flow moved the preferences" "$(hook)"
expect_eq "moves payload" '{"handoff":"tmux"}' "$(jq -c . "$CLAUDE_CONFIG_DIR/configured.json")"
expect_eq "moves keeps notes" "Notes." "$(cat "$FLOW_HOME/user.md")"
expect_eq "second start is quiet" "" "$(hook)"

opts() {
  jq -n --argjson o "$1" '{pluginConfigs: {"sin-flow@test": {options: $o}}}' > "$CLAUDE_CONFIG_DIR/settings.json"
  rm -f "$CLAUDE_CONFIG_DIR/configured.json" "$FLOW_HOME/backups/options-migrated"
}
full() { echo '{}' | bash "$root/hooks/scripts/user-migrate.sh" | jq -r '.hookSpecificOutput.additionalContext // empty'; }
configured() { jq -c . "$CLAUDE_CONFIG_DIR/configured.json" 2>/dev/null || echo none; }

opts '{"codex_review":"on","codex_watch":"orca"}'
expect_eq "old options move" "sin-flow moved renamed plugin" "$(hook)"
expect_eq "old options payload" '{"extra_reviewers":"codex","reviewer_watch":"orca"}' "$(configured)"
opts '{"codex_review":"on","codex_watch":"orca"}'
expect_eq "old options report" "codex_review on -> extra_reviewers codex;codex_watch orca -> reviewer_watch orca" "$(full | sed 's/.*one line: //')"

opts '{"codex_review":"on"}'
hook > /dev/null
rm -f "$CLAUDE_CONFIG_DIR/configured.json"
expect_eq "second run is quiet" "" "$(hook)"
expect_eq "second run, no configure" none "$(configured)"
jq '.pluginConfigs["sin-flow@test"].options.extra_reviewers = ""' "$CLAUDE_CONFIG_DIR/settings.json" > "$scratch/s.json"
mv "$scratch/s.json" "$CLAUDE_CONFIG_DIR/settings.json"
expect_eq "cleared after the move is quiet" "" "$(hook)"
expect_eq "cleared after the move stays cleared" none "$(configured)"

opts '{"codex_review":"codex","extra_reviewers":"x","codex_watch":"orca","reviewer_watch":"/x.sh"}'
expect_eq "new options set" "" "$(hook)"
expect_eq "new options untouched" none "$(configured)"

opts '{"handoff":"tmux"}'
expect_eq "nothing old" "" "$(hook)"
expect_eq "nothing old, no configure" none "$(configured)"

opts '{"codex_review":"off"}'
expect_eq "old off" "" "$(hook)"
expect_eq "old off, no configure" none "$(configured)"

opts '{"codex_review":"on"}'
expect_eq "options fail" "sin-flow could not move" "$(FAKE_FAIL=1 hook)"
expect_eq "options fail, no marker" no "$([ -f "$FLOW_HOME/backups/options-migrated" ] && echo yes || echo no)"
expect_eq "options retry" "sin-flow moved renamed plugin" "$(hook)"

printf -- '---\nhandoff: tmux\n---\nNotes.\n' > "$FLOW_HOME/user.md"
opts '{"codex_review":"on"}'
both=$(full)
case "$both" in *"preferences of"*"renamed plugin options"*) cases=$((cases + 1)) ;; *) fail "both steps report: $both" ;; esac

echo "ok: $cases cases"
