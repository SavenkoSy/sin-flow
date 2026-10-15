#!/bin/bash
set -euo pipefail

[ $# -eq 1 ] || { echo "usage: fetch-board.sh <profile key>" >&2; exit 2; }
PROFILE_CLI="${FLOW_PROFILE:-sin-flow-profile}"
BOARD=$("$PROFILE_CLI" "$1" get tracker.board) || { echo "no tracker.board in profile $1" >&2; exit 1; }
[ "$BOARD" != "null" ] || { echo "no board in this profile" >&2; exit 1; }
ORG=${BOARD%%#*}
PROJ=${BOARD##*#}
STATE="$("$PROFILE_CLI" "$1" dir)/board/state.json"
[ -f "$STATE" ] || { echo "no board state at $STATE" >&2; exit 1; }

RAW=$(mktemp)
trap 'rm -f "$RAW"' EXIT

CURSOR=""
for _ in $(seq 1 30); do
  if [ -z "$CURSOR" ]; then AFTER="null"; else AFTER="\"$CURSOR\""; fi
  RESP=$(gh api graphql -f query="
  {
    organization(login: \"$ORG\") {
      projectV2(number: $PROJ) {
        items(first: 100, after: $AFTER) {
          pageInfo { hasNextPage endCursor }
          nodes {
            id
            fieldValueByName(name: \"Status\") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
            priority: fieldValueByName(name: \"Priority\") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
            light: fieldValueByName(name: \"Light\") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
            content {
              ... on Issue {
                number title url state createdAt updatedAt repository { name }
                assignees(first: 5) { nodes { login } }
                labels(first: 10) { nodes { name } }
                milestone { title }
              }
            }
          }
        }
      }
    }
  }")
  printf '%s\n' "$RESP" >> "$RAW"
  [ "$(jq -r '.data.organization.projectV2.items.pageInfo.hasNextPage' <<<"$RESP")" = "true" ] || break
  CURSOR=$(jq -r '.data.organization.projectV2.items.pageInfo.endCursor' <<<"$RESP")
done

STATUSES=$(jq -c '.scope.statuses' "$STATE")
ASSIGNEE_FILTER=$(jq -c '.scope.assigneeFilter // {}' "$STATE")
jq --indent 1 -n --argjson statuses "$STATUSES" --argjson filter "$ASSIGNEE_FILTER" '
def nz(d): if . == null or . == "" then d else . end;
{"🟢 Ready now": "green", "🟡 Check first": "yellow", "🔴 Blocked upstream": "red"} as $light
| ($filter | with_entries(select(.key | startswith("_") | not))) as $required
| [inputs | .data.organization.projectV2.items.nodes[]]
| reduce .[] as $node ({order: [], at: {}};
    if .at[$node.id] == null
    then .at[$node.id] = (.order | length) | .order += [$node]
    else .order[.at[$node.id]] = $node end)
| .order
| map(
    (.content // {}) as $issue
    | select(($issue.number // 0) != 0 and $issue.state == "OPEN")
    | ((.fieldValueByName // {}).name | nz("No Status")) as $status
    | select($statuses | index($status))
    | [$issue.assignees.nodes[].login] as $assignees
    | select(($required[$status] | nz(null)) as $who | $who == null or ($assignees | index($who)))
    | {
        n: $issue.number,
        m: (($issue.milestone // {}).title | nz("No milestone")),
        t: $issue.title,
        u: $issue.url,
        a: $assignees,
        p: ((.priority // {}).name | nz("")),
        l: [$issue.labels.nodes[].name],
        s: $status,
        light: $light[(.light // {}).name | nz("")],
        updated: $issue.updatedAt
      })
| sort_by(.n)' "$RAW"
