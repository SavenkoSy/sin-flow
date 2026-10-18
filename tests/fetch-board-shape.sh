#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/profile/board"
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

cat > "$scratch/bin/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$scratch/query"
cat <<'JSON'
{"data":{"organization":{"projectV2":{"items":{
  "pageInfo":{"hasNextPage":false,"endCursor":null},
  "nodes":[
    {"id":"PVTI_1","fieldValueByName":{"name":"Todo"},"priority":null,"light":{"name":"🟢 Ready now"},
     "content":{"number":11,"title":"With parent","url":"https://github.com/acme/widgets/issues/11","state":"OPEN",
       "createdAt":"2026-10-01T00:00:00Z","updatedAt":"2026-10-02T00:00:00Z","repository":{"name":"widgets"},
       "assignees":{"nodes":[]},"labels":{"nodes":[{"name":"bug"}]},"milestone":null,
       "parent":{"number":5,"title":"Checkout epic"}}},
    {"id":"PVTI_2","fieldValueByName":{"name":"Todo"},"priority":null,"light":null,
     "content":{"number":12,"title":"Without parent","url":"https://github.com/acme/widgets/issues/12","state":"OPEN",
       "createdAt":"2026-10-01T00:00:00Z","updatedAt":"2026-10-03T00:00:00Z","repository":{"name":"widgets"},
       "assignees":{"nodes":[]},"labels":{"nodes":[]},"milestone":{"title":"M1"},
       "parent":null}}
  ]}}}}}
JSON
EOF

cat > "$scratch/bin/profile" <<EOF
#!/usr/bin/env bash
case "\$2" in
  get) [ "\$3" = tracker.board ] && echo 'acme#1' || exit 1 ;;
  dir) echo "$scratch/profile" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$scratch/bin/gh" "$scratch/bin/profile"

printf '{"scope":{"statuses":["Todo"]}}\n' > "$scratch/profile/board/state.json"

out=$(PATH="$scratch/bin:$PATH" FLOW_PROFILE="$scratch/bin/profile" bash "$root/skills/sync/reference/fetch-board.sh" acme)

expect_has "query asks for the parent" "parent { number title }" "$(cat "$scratch/query")"
expect_eq "row count" 2 "$(jq 'length' <<<"$out")"
expect_eq "epic of a ticket with a parent" "Checkout epic" "$(jq -r '.[] | select(.n == 11) | .e' <<<"$out")"
expect_eq "epic of a ticket without a parent" null "$(jq -c '.[] | select(.n == 12) | .e' <<<"$out")"
expect_eq "milestone default" "No milestone" "$(jq -r '.[] | select(.n == 11) | .m' <<<"$out")"
expect_eq "light map" green "$(jq -r '.[] | select(.n == 11) | .light' <<<"$out")"

echo "ok: $cases cases"
