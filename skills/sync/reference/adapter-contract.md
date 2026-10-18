# Tracker adapter contract

Read this file when you write a local adapter for a tracker that is not a GitHub Projects board.
`sin-flow:sync` has one built-in adapter: GitHub Projects. A different tracker, for example Jira,
needs an adapter that the user writes, or that the user's own model writes from this page.

## Where the adapter lives

An adapter is one executable file of the user, outside the plugin. The profile names it:

```
tracker.adapter: ~/trackers/acme-adapter
```

The value is an absolute path or a `~` path. When `tracker.adapter` is set, sync uses it and
ignores `tracker.board`. When it is absent, sync uses the built-in GitHub Projects adapter:
`fetch-board.sh` for the read, and the mutations in `board-pass.md` § Reference for the writes.

The board state stays in `$(sin-flow-profile <key> dir)/board/` for each adapter. `state.json`,
`classification.json` and the page do not change.

## Commands

Each command takes the profile key as the first argument after its command words: `$2` for `read`
and `supports`, `$3` for each `write` command. On success, exit 0. On any other exit code, the pass
stops and the digest shows the first line of stderr.

| Command | Required | Does |
|---|---|---|
| `<adapter> read <key>` | yes | prints a JSON array of tickets to stdout, sorted by `n` |
| `<adapter> supports <key>` | yes | prints the write steps it has, one on each line, from `light`, `assign`, `status`. An empty output means read only |
| `<adapter> write light <key> <n> <green\|yellow\|red>` | only if `supports` lists `light` | sets the light of ticket `<n>` |
| `<adapter> write assign <key> <n> <user>` | only if `supports` lists `assign` | makes `<user>` the only assignee of ticket `<n>`. Prints each removed assignee on its own line |
| `<adapter> write status <key> <n> <status name>` | only if `supports` lists `status` | moves ticket `<n>` to that status |

`read` applies the scope of the board, as `fetch-board.sh` does. It keeps a ticket only when its
status is in `scope.statuses` of `<board>/state.json`. When `scope.assigneeFilter` names a user
for that status, it keeps the ticket only when that user is an assignee. Keys in
`scope.assigneeFilter` that start with `_` are notes, not filters.

## Ticket shape

Each element of the `read` array is one open ticket. The keys are short. They are the keys that
`fetch-board.sh` prints, and the page `DATA`, the diff and `classification.json` read these keys.

| Name | JSON key | Type | Required |
|---|---|---|---|
| id | `n` | string or number | yes |
| title | `t` | string | yes |
| status | `s` | string | yes |
| epic | `e` | string or `null` | yes, `null` when the ticket has no epic |
| milestone | `m` | string | yes, `"No milestone"` when empty |
| priority | `p` | string | yes, `""` when not set |
| labels | `l` | array of strings | yes, `[]` when none |
| assignee | `a` | array of strings | yes, `[]` when none |

Optional keys:

| JSON key | Type | Meaning |
|---|---|---|
| `u` | string | the URL of the ticket |
| `updated` | ISO time | the last change; the briefs refresh when it is newer than their stamp |
| `light` | `green`, `yellow`, `red` or `null` | the light that the tracker holds now. Required on each ticket when `supports` lists `light` |

When `supports` lists `light`, `read` gives the `light` key on each ticket, `null` when the tracker
has no light. Without it, sync cannot see a light that a teammate changed, and writes over it.

The adapter returns the light words `green`, `yellow` and `red` itself. The built-in adapter maps
the board option labels to these words (`triage-rules.md` § Light).

## Write switches

Three profile switches control the board writes. Each switch is `on` or `off`. An absent switch is
`off`.

| Switch | Write step |
|---|---|
| `tracker.write.light` | `write light` |
| `tracker.write.assign` | `write assign` |
| `tracker.write.status` | `write status` |

A write step runs only when its switch is `on` **and** `supports` lists the step. Sync records
claims and shows lights and groups on the page also when each switch is off.

## Example skeleton

A read-only adapter for a fictional tracker `acme`. It reads a JSON export from disk.

```bash
#!/bin/bash
set -euo pipefail

EXPORT="$HOME/acme/export.json"

case "$1" in
  supports) ;;
  read)
    STATE="$(sin-flow-profile "$2" dir)/board/state.json"
    jq --argjson statuses "$(jq -c '.scope.statuses' "$STATE")" \
       --argjson filter "$(jq -c '.scope.assigneeFilter // {}' "$STATE")" '
      [.issues[]
       | select(.status as $s | $statuses | index($s))
       | select($filter[.status] as $who | $who == null or .owner == $who)
       | {n: .key, t: .summary, s: .status, e: .epic,
          m: (.release // "No milestone"), p: (.priority // ""),
          l: (.tags // []), a: [.owner // empty], u: .link}]
      | sort_by(.n)' "$EXPORT" ;;
  *) echo "acme adapter: no command $1" >&2; exit 2 ;;
esac
```

A `write` branch reads the key from `$3`: `write light <key> <n> <light>` gives `$4` = `<n>` and
`$5` = `<light>`.

## See also

- `board-pass.md` § Reference: the GitHub mutations of the built-in adapter.
- `triage-rules.md`: the light words and the priority order.
