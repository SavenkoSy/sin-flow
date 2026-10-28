#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir "$scratch/bin"
cat > "$scratch/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "repo view") echo main; exit 0 ;;
  "pr view") ;;
  *) exit 1 ;;
esac
n=$(( $(cat "$QUEUE/n" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$QUEUE/n"
[ -f "$QUEUE/$n.json" ] || n=last
[ -f "$QUEUE/$n.fail" ] && exit 1
cat "$QUEUE/$n.json"
EOF
printf '#!/usr/bin/env bash\n[ "$1" = fetch ] && exit 0\nexit 1\n' > "$scratch/bin/git"
cat > "$scratch/bin/sin-flow-profile" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  key) echo demo ;;
  demo) [ "$2 $3" = "get review.deploy_bots" ] && printf '%s\n' "${BOTS:-}" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$scratch/bin/gh" "$scratch/bin/git" "$scratch/bin/sin-flow-profile"

pr() {
  jq -n --arg base "$1" --arg merge "$2" --argjson logins "$3" --arg body "$4" \
    '{author: {login: "me"}, baseRefName: $base, mergeStateStatus: $merge, reviews: [],
      comments: [$logins[] | {author: {login: .}, body: $body}]}'
}

run_case() {
  QUEUE=$(mktemp -d "$scratch/q.XXXXXX")
  export QUEUE
  local i=0 row
  while IFS= read -r row; do
    i=$(( i + 1 ))
    case "$row" in
      FAIL) touch "$QUEUE/$i.fail"; echo '{}' > "$QUEUE/$i.json" ;;
      RAW:*) printf '%s' "${row#RAW:}" > "$QUEUE/$i.json" ;;
      *) eval "pr $row" > "$QUEUE/$i.json" ;;
    esac
  done
  pr main BEHIND '[]' x > "$QUEUE/last.json"
  PATH="$scratch/bin:$PATH" SIN_FLOW_WATCH_INTERVAL=0 SIN_FLOW_WATCH_HOURS=1 \
    "$root/bin/sin-flow-watch" https://github.com/o/r/pull/1
}

out=$(BOTS="other, vercel" run_case <<'EOF'
FAIL
main CLEAN '[]' x
FAIL
RAW:
RAW:not json
main CLEAN '[]' 'line\nwith \\ escapes and "quotes"'
main CLEAN '["vercel[bot]"]' x
main CLEAN '["me"]' x
main CLEAN '["alice"]' 'a\nb'
EOF
)
[ "$out" = "WAKE activity: 1 new review or comment" ] || fail "case 1: got $out"

out=$(run_case <<'EOF'
main CLEAN '[]' x
FAIL
RAW:{"baseRefName": null}
main CLEAN '[]' x
EOF
)
[ "$out" = "WAKE BEHIND" ] || fail "case 2: got $out"

out=$(run_case <<'EOF'
main CLEAN '[]' x
stage CLEAN '[]' x
EOF
)
[ "$out" = "WAKE base: main -> stage" ] || fail "case 3: got $out"

out=$(run_case <<'EOF'
main CLEAN '[]' "$(printf 'tab\there')"
main DIRTY '[]' x
EOF
)
[ "$out" = "WAKE DIRTY" ] || fail "case 4: got $out"

out=$(run_case <<'EOF'
main CLEAN '[]' x
main CLEAN '["vercel[bot]"]' x
EOF
)
[ "$out" = "WAKE activity: 1 new review or comment" ] || fail "case 7: an empty review.deploy_bots skips no bot: got $out"

out=$(BOTS="vercel" run_case <<'EOF'
main CLEAN '[]' x
main CLEAN '["vercel[bot]", "vercel"]' x
main DIRTY '[]' x
EOF
)
[ "$out" = "WAKE DIRTY" ] || fail "case 8: review.deploy_bots skips the bot with and without [bot]: got $out"

[ "$(head -1 "$root/bin/sin-flow-watch")" = "#!/usr/bin/env bash" ] || fail "case 5: no bash shebang"
grep -q 'echo "\$s" | jq' "$root/bin/sin-flow-watch" && fail "case 6: parses JSON through echo"

echo "ok: 8 cases"
