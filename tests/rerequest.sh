#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir "$scratch/bin"
cat > "$scratch/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CASE/calls"
case "$1 $2" in
  "pr view") cat "$CASE/pr.json" ;;
  "api --paginate") jq -r "$5" "$CASE/reviews.json" ;;
  "api -X") printf '%s\n' "$*" > "$CASE/posted" ;;
  *) exit 1 ;;
esac
EOF
cat > "$scratch/bin/sin-flow-profile" <<'EOF'
#!/usr/bin/env bash
case "$1 $2 $3" in
  "key  ") echo demo ;;
  "demo get review.request") [ -n "${REQUEST:-}" ] && printf '%s\n' "$REQUEST" ;;
  "demo get review.ignored_approvers") [ -n "${IGNORED:-}" ] && printf '%s\n' "$IGNORED" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$scratch/bin/gh" "$scratch/bin/sin-flow-profile"

review() { jq -cn --arg l "$1" --arg t "$2" --arg s "$3" '{user: {login: $l, type: $t}, state: $s}'; }

new_case() {
  CASE=$(mktemp -d "$scratch/case.XXXXXX")
  export CASE
}

run_case() {
  jq -n --arg d "$1" '{author: {login: "me"}, state: "OPEN", reviewDecision: $d}' > "$CASE/pr.json"
  shift
  printf '%s\n' "$@" | jq -s . > "$CASE/reviews.json"
  PATH="$scratch/bin:$PATH" "$root/bin/sin-flow-rerequest" https://github.com/o/r/pull/7
}

bot_approved=$(review "cursor[bot]" Bot APPROVED)
lead_commented=$(review lead User COMMENTED)

new_case
out=$(run_case APPROVED "$bot_approved" "$lead_commented")
[ "$out" = "rerequest: none · PR approved" ] || fail "case 1: no key keeps the approved PR: got $out"
grep -q reviews "$CASE/calls" && fail "case 1: no key reads the reviews of an approved PR"

new_case
out=$(IGNORED="cursor[bot]" run_case APPROVED "$bot_approved" "$lead_commented")
[ "$out" = "rerequest: lead" ] || fail "case 2: an ignored bot approval still counts: got $out"
grep -qF "reviewers[]=lead" "$CASE/posted" || fail "case 2: no POST for lead"

new_case
out=$(IGNORED="cursor" run_case APPROVED "$bot_approved" "$lead_commented")
[ "$out" = "rerequest: lead" ] || fail "case 3: a key without [bot] does not match the bot: got $out"

new_case
out=$(IGNORED="cursor[bot]" run_case APPROVED "$bot_approved" "$(review lead User APPROVED)")
[ "$out" = "rerequest: none · PR approved" ] || fail "case 4: a person's approval does not count: got $out"
[ -e "$CASE/posted" ] && fail "case 4: a POST on an approved PR"

new_case
out=$(IGNORED="cursor[bot]" run_case APPROVED "$(review lead User APPROVED)" "$(review lead User CHANGES_REQUESTED)" "$(review lead User COMMENTED)")
[ "$out" = "rerequest: lead" ] || fail "case 5: a later change request does not replace the approval: got $out"

new_case
out=$(IGNORED="cursor[bot]" REQUEST="boss, lead" run_case REVIEW_REQUIRED "$lead_commented")
[ "$out" = "rerequest: boss,lead" ] || fail "case 6: a PR that is not approved: got $out"

echo "ok: 6 cases"
