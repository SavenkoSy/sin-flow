#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir "$scratch/bin" "$scratch/data" "$scratch/reviews" "$scratch/profile"
cat > "$scratch/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2 $3" in
  "api user -q") echo me ;;
  "pr view 7") echo author ;;
  "api --paginate repos/o/r/pulls/7/comments") jq -r "$5" "$DATA/comments.json" ;;
  *) exit 1 ;;
esac
EOF
cat > "$scratch/bin/sin-flow-profile" <<'EOF'
#!/usr/bin/env bash
case "$1 $2 $3" in
  "demo get repo.slug") echo o/r ;;
  "user reviews_dir ") echo "$DATA/../reviews" ;;
  "demo dir ") echo "$DATA/../profile" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$scratch/bin/gh" "$scratch/bin/sin-flow-profile"
export DATA="$scratch/data"

rc() { jq -cn --argjson id "$1" --arg reply "$2" --arg who "$3" --arg body "$4" \
  '{id: $id, user: {login: $who, type: "User"}, body: $body, path: "a.rb", line: 3, original_line: 3,
    original_commit_id: "abcdef1234567890"}
   + (if $reply == "" then {} else {in_reply_to_id: ($reply | tonumber)} end)'; }

printf '%s\n' \
  "$(rc 1 "" me "root")" "$(rc 2 1 author "Disagreed, this is fine")" \
  "$(rc 3 "" me "root")" "$(rc 4 3 author "Not fixed, see the note")" \
  "$(rc 5 "" me "root")" "$(rc 6 5 lead "Agreed, this needs a fix")" \
  "$(rc 7 "" me "root")" "$(rc 8 7 author "Fixed in the next commit")" \
  "$(rc 9 "" me "root")" "$(rc 10 9 author "This is deliberate")" \
  "$(rc 11 "" me "root")" "$(rc 12 11 author "You are mistaken, it is done elsewhere")" \
  "$(rc 13 "" me "root")" "$(rc 14 13 author "Fixed? No, I won't change it")" \
  "$(rc 15 "" me "root")" "$(rc 16 15 lead "Done")" "$(rc 17 15 author "Good catch, taken")" \
  | jq -s . > "$DATA/comments.json"

out=$(PATH="$scratch/bin:$PATH" bash "$root/skills/review/reference/eval.sh" responses demo 7 | cut -f3,6)
expected=$'1\twrong
3\twrong
5\tignored
7\tfixed
9\tintentional
11\twrong
13\twrong
15\tfixed'
[ "$out" = "$expected" ] || fail "responses: want [$expected], got [$out]"
[ "$(wc -l < "$scratch/reviews/responses.tsv")" -eq 8 ] || fail "responses.tsv does not hold 8 rows"

echo "ok: 8 cases"
