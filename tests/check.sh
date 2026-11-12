#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cases=0

fail() { echo "FAIL: $*" >&2; exit 1; }

for name in $(env | sed -n 's/^\(CLAUDE_PLUGIN_OPTION_[A-Z_]*\)=.*/\1/p'); do unset "$name"; done
unset TMUX CMUX_WORKSPACE_ID ORCA_TERMINAL_HANDLE FLOW_HOME
export __CFBundleIdentifier=none TERM_PROGRAM=none
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

mkdir "$scratch/bin"
cat > "$scratch/bin/claude" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "plugin list") [ -n "${NO_PLUGIN:-}" ] && echo '[]' || echo '[{"id":"sin-flow@test","enabled":true}]' ;;
  "plugin configure") jq -cn --arg u "${UNCONFIGURED:-}" '{configured: [], unconfigured: ($u | split(" "))}' ;;
  *) exit 1 ;;
esac
EOF
cat > "$scratch/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "auth status") [ -z "${NO_GH_AUTH:-}" ] ;;
  "repo view") echo '{"name":"demo","defaultBranchRef":{"name":"main"},"hasIssuesEnabled":true,"hasProjectsEnabled":false,"squashMergeAllowed":true,"mergeCommitAllowed":false,"rebaseMergeAllowed":false}' ;;
  "pr list") echo '[]' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$scratch/bin/claude" "$scratch/bin/gh"
export PATH="$root/bin:$scratch/bin:$PATH"

fresh_home() {
  HOME=$(mktemp -d "$scratch/home.XXXXXX")
  export HOME
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  flow="$HOME/.claude/sin-flow"
  mkdir -p "$flow/profiles" "$flow/work" "$flow/reviews" "$scratch/outside"
  git init -q --bare "$HOME/copy.git"
  git -C "$flow" init -q
  git -C "$flow" remote add origin "$HOME/copy.git"
  options "{\"work_remote\":\"$HOME/copy.git\",\"handoff\":\"print\",\"limit_guard\":\"off\"}"
  cd "$scratch/outside"
}

options() { jq -n --argjson o "$1" '{pluginConfigs: {"sin-flow@test": {options: $o}}}' > "$CLAUDE_CONFIG_DIR/settings.json"; }
option() {
  jq --arg k "$1" --arg v "$2" '.pluginConfigs["sin-flow@test"].options[$k] = $v' "$CLAUDE_CONFIG_DIR/settings.json" > "$CLAUDE_CONFIG_DIR/settings.tmp"
  mv "$CLAUDE_CONFIG_DIR/settings.tmp" "$CLAUDE_CONFIG_DIR/settings.json"
}
status_line() {
  jq --arg c "$1" '.statusLine = {type: "command", command: $c}' "$CLAUDE_CONFIG_DIR/settings.json" > "$CLAUDE_CONFIG_DIR/settings.tmp"
  mv "$CLAUDE_CONFIG_DIR/settings.tmp" "$CLAUDE_CONFIG_DIR/settings.json"
}

run() { rc=0; out=$(sin-flow-check "$@" 2>&1) || rc=$?; }
has() { cases=$((cases + 1)); grep -qF -- "$2" <<<"$out" || fail "$1: no [$2] in: $out"; }
has_not() { cases=$((cases + 1)); ! grep -qF -- "$2" <<<"$out" || fail "$1: [$2] in: $out"; }
last() { cases=$((cases + 1)); [ "$(tail -1 <<<"$out")" = "$2" ] || fail "$1: the last line is [$(tail -1 <<<"$out")], want [$2]: $out"; }
code() { cases=$((cases + 1)); [ "$rc" = "$2" ] || fail "$1: exit $rc, want $2: $out"; }

fresh_home
run
code "case 1" 0
last "case 1" "all good"
has_not "case 1" "→ fix:"
has_not "case 1" " project "
has "case 1" "[✓] flow      skills"
has "case 1" "prefs: the language of the user · squash · new-commit · handoff print · models opus/sonnet/haiku"

fresh_home
options '{"handoff":"print","limit_guard":"off"}'
run
code "case 2" 0
has "case 2" "! user    work-remote    Your plans and evidence are on this computer only. → fix: the copy question of Install step 3"
last "case 2" "open: 1"

fresh_home
git -C "$flow" remote remove origin
run
has "case 3" "Git does not push to the copy on GitHub. → fix: git -C $flow remote add origin $HOME/copy.git"
git -C "$flow" remote add origin "$HOME/other.git"
run
has "case 3" "remote set-url origin $HOME/copy.git"
git -C "$flow" remote set-url origin "$HOME/copy.git"
rm -rf "$HOME/copy.git"
run
has "case 3" "git ls-remote $HOME/copy.git does not answer"

fresh_home
printf -- '---\nmerge: squash\n---\nnotes\n' > "$flow/user.md"
run
has "case 4" "the preferences are not migrated to the plugin options → fix: sin-flow-profile migrate-user"
printf 'notes\n' > "$flow/user.md"
run
last "case 4" "all good"

fresh_home
option handoff bogus
run
code "case 5" 1
has "case 5" "✗ user    handoff        handoff 'bogus' is not auto, same-session, print, tmux, cmux, iterm, ghostty, warp, orca or an executable path"
touch "$HOME/handoff.sh"
option handoff "~/handoff.sh"
run
has "case 5" "is not executable → fix: chmod +x ~/handoff.sh"
chmod +x "$HOME/handoff.sh"
run
code "case 5" 0
last "case 5" "all good"

fresh_home
option workspace bogus
option reviewer_watch bogus
run
code "case 6" 1
has "case 6" "✗ user    workspace      workspace 'bogus' is not empty, git, orca or an executable path"
has "case 6" "! user    reviewer-watch reviewer_watch 'bogus' is not empty, orca or an executable path"
option workspace orca
option reviewer_watch orca
run
last "case 6" "all good"

fresh_home
UNCONFIGURED="context_guard limit_guard" run
has "case 7" "the context guard uses the default 40 → fix: the context_guard question of Install step 3"
has "case 7" "the limit guard reads any status line that writes the state file → fix: the limit_guard question of Install step 3"
last "case 7" "open: 2"

fresh_home
option limit_guard on
run
has "case 8" "the limit guard has no writer → fix: the wrapper install of Install step 3"
printf 'echo state/sessions limit_5h\n' > "$HOME/own.sh"
status_line "sh ~/own.sh"
run
has "case 8" "the status line ~/own.sh writes the state file"
last "case 8" "all good"
mkdir -p "$flow/bin"
echo old > "$flow/bin/sin-flow-statusline"
status_line "sh ~/.claude/sin-flow/bin/sin-flow-statusline 'sh ~/gone.sh --flag'"
run
has "case 8" "the status line wrapper is out of date → fix: cp"
has "case 8" "the wrapped status line file does not exist: ~/gone.sh → fix: restore statusLine from the newest"
cp "$root/bin/sin-flow-statusline" "$flow/bin/sin-flow-statusline"
touch "$HOME/gone.sh"
run
last "case 8" "all good"
status_line "sh ~/.claude/sin-flow/bin/sin-flow-statusline"
run
last "case 8" "all good"

fresh_home
option handoff auto
run
has "case 9" "The flow did not find your terminal. It shows the command, and then you start the next stage. → fix: the terminal question of Install step 4"
TERM_PROGRAM=iTerm.app run
has "case 9" "auto finds iterm"
has "case 9" "handoff auto (iterm)"
option handoff tmux
run
has "case 9" "! user    terminal       tmux: "
has "case 9" "→ fix: install it, or set handoff: print"

fresh_home
option models_strong gpt
run
code "case 10" 1
has "case 10" "✗ user    model-strong   models.strong: 'gpt' is not one of opus, sonnet, haiku, fable"

fresh_home
printf '2026-01-02 10:00:00\tcommitted\tabc\n2026-01-02 10:01:00\tpush failed\n' > "$flow/stop-commit.log"
git -C "$flow" add -A >/dev/null 2>&1
run
has "case 11" "the Stop hook commit failed: 2026-01-02 10:01:00"
printf 'a\tcommitted\nb\tcommitted\nc\tcommitted\n' >> "$flow/stop-commit.log"
run
has_not "case 11" "the Stop hook commit failed"

fresh_home
rmdir "$flow/reviews"
run
code "case 12" 1
has "case 12" "✗ user    folders        missing: $flow/reviews → fix: mkdir -p $flow/reviews"
rm -rf "$flow/.git"
run
has "case 12" "is not a git repository → fix: git init"

fresh_home
NO_GH_AUTH=1 NO_PLUGIN=1 run
code "case 13" 1
has "case 13" "✗ flow    gh             gh is not logged in → fix: gh auth login"
has "case 13" "✗ flow    plugin         claude plugin list shows no enabled sin-flow → fix: claude plugin install sin-flow@sin-flow"

fresh_home
repo="$HOME/demo"
git init -q --bare "$HOME/demo-origin.git"
git init -q -b main "$repo"
git -C "$repo" remote add origin "$HOME/demo-origin.git"
git -C "$repo" commit -q --allow-empty -m first
git -C "$repo" push -q origin main
run "$repo"
code "case 14" 1
has "case 14" "✗ project profile        no profile for this repo → fix: onboard: reference/onboard.md"

mkdir -p "$flow/profiles/demo"
printf -- '---\nkey: demo\nrepo.slug: %s\nmeasure.doc: none\n---\n' "$HOME/demo-origin" > "$flow/profiles/demo/profile.md"
sin-flow-infer --write demo "$repo" >/dev/null
run "$repo"
code "case 15" 0
has "case 15" "✓ project profile        profile valid"
has "case 15" "✓ project base           base main on origin"
has "case 15" "✓ project gate-tools"
has "case 15" "✓ project inferred"
has "case 15" "? project gates-named"
has_not "case 15" "? project sources"
has "case 15" "[?] project   demo: profile valid · base main on origin · gates ✓ · measure: none · sources: none"
last "case 15" "open: 1"

printf 'pre-commit:\n  commands:\n    lint:\n      run: true\n' > "$repo/lefthook.yml"
run "$repo"
has "case 16" "! project inferred       the base or the gate files changed after the last sin-flow-infer --write → fix: sin-flow-infer --write demo, then name the gates"
sin-flow-infer --write demo "$repo" >/dev/null
printf 'gates (CI): `no-such-binary-of-the-test run`, `git status` — .github/workflows/ci.yml (pull_request).\n' >> "$flow/profiles/demo/profile.md"
run "$repo"
has "case 16" "✓ project inferred"
has "case 16" "! project gate-tools     not on PATH: no-such-binary-of-the-test → fix: install no-such-binary-of-the-test"

printf -- '---\nkey: demo\nrepo.slug: %s\nrepo.base: release\nmeasure.doc: none\nsources.db.env_file: .env.db_readonly\nsources.db.var: DB_URL\n---\n' "$HOME/demo-origin" > "$flow/profiles/demo/profile.md"
sin-flow-infer --write demo "$repo" >/dev/null
printf 'DB_URL=x\n' > "$repo/.env.db_readonly"
chmod 644 "$repo/.env.db_readonly"
run "$repo"
code "case 17" 1
has "case 17" "demo/.env.db_readonly is not chmod 600 → fix: chmod 600 /"
has "case 17" "is not git-ignored → fix: add to .gitignore"
has "case 17" "✗ project base           base release is not a branch on origin"
has "case 17" "? project sources        the session runs the preflight and the verify call of: db"

echo "ok: $cases cases"
