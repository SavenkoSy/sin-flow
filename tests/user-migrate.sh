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

echo "ok: $cases cases"
