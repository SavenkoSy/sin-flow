#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir "$scratch/bin" "$scratch/data"
cat > "$scratch/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2 $3" in
  "pr view https://github.com/o/r/pull/7") echo me ;;
  "api --paginate repos/o/r/pulls/7/comments") cat "$DATA/review-1.json" "$DATA/review-2.json" ;;
  "api --paginate repos/o/r/issues/7/comments") cat "$DATA/issue-1.json" "$DATA/issue-2.json" ;;
  *) exit 1 ;;
esac
EOF
cat > "$scratch/bin/sin-flow-profile" <<'EOF'
#!/usr/bin/env bash
case "$1 $2 $3" in
  "key  ") echo demo ;;
  "demo get review.deploy_bots") [ -n "${BOTS:-}" ] && printf '%s\n' "$BOTS" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$scratch/bin/gh" "$scratch/bin/sin-flow-profile"
export DATA="$scratch/data"

rc() { jq -cn --argjson id "$1" --arg reply "$2" --arg who "$3" --arg at "$4" --arg body "$5" \
  '{id: $id, user: {login: $who}, created_at: $at, body: $body, path: "a.rb", line: 3}
   + (if $reply == "" then {} else {in_reply_to_id: ($reply | tonumber)} end)'; }
ic() { jq -cn --argjson id "$1" --arg who "$2" --arg at "$3" --arg body "$4" \
  '{id: $id, user: {login: $who}, created_at: $at, body: $body}'; }

printf '%s\n' "$(rc 1 "" lead 2026-01-01T10:00:00Z "open root")" "$(rc 2 "" lead 2026-01-01T10:01:00Z "answered root")" \
  "$(rc 3 2 me 2026-01-01T11:00:00Z "fixed")" | jq -s . > "$DATA/review-1.json"
printf '%s\n' "$(rc 4 "" lead 2026-01-01T10:02:00Z "follow root")" "$(rc 5 4 me 2026-01-01T11:01:00Z "done")" \
  "$(rc 6 4 lead 2026-01-01T12:00:00Z "still wrong")" "$(rc 7 "" "vercel[bot]" 2026-01-01T10:03:00Z "preview")" \
  | jq -s . > "$DATA/review-2.json"
printf '%s\n' "$(ic 10 lead 2026-01-01T09:00:00Z "old note")" "$(ic 11 me 2026-01-01T11:30:00Z "replied")" \
  | jq -s . > "$DATA/issue-1.json"
printf '%s\n' "$(ic 12 lead 2026-01-01T12:30:00Z "new note")" "$(ic 13 "vercel[bot]" 2026-01-01T12:40:00Z "deployed")" \
  | jq -s . > "$DATA/issue-2.json"

out=$(BOTS="vercel" PATH="$scratch/bin:$PATH" "$root/bin/sin-flow-unanswered" https://github.com/o/r/pull/7)
expected='thread 1 lead a.rb:3 open root
thread 4 lead a.rb:3 still wrong
comment 12 lead new note'
[ "$out" = "$expected" ] || fail "case 1: want [$expected], got [$out]"

out=$(PATH="$scratch/bin:$PATH" "$root/bin/sin-flow-unanswered" https://github.com/o/r/pull/7)
grep -qF "thread 7 vercel[bot]" <<<"$out" || fail "case 2: no review.deploy_bots skips a bot thread: got $out"
grep -qF "comment 13 vercel[bot]" <<<"$out" || fail "case 2: no review.deploy_bots skips a bot comment: got $out"

out=$(PATH="$scratch/bin:$PATH" "$root/bin/sin-flow-unanswered" not-a-url 2>&1) && fail "case 3: a bad url exits 0"
grep -qF "not a PR url" <<<"$out" || fail "case 3: got $out"

echo "ok: 3 cases"
