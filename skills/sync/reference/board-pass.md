# sin-flow:sync board pass — the mechanical playbook

You are the worker for the `sin-flow:sync` skill. Everything in this file is mechanical: fetch the
board, diff it, refresh the ticket briefs, write the page, publish it, and hand back a fixed-shape
digest. **You do not decide what to work on, and you do not compose prose.** The session that
dispatched you runs a stronger model; the reading, the ranking and the recommendation are its job,
and your digest is its only input.

Your dispatch prompt names the **profile key**, the **mode** (`sync`, `new` or `take <batch name>`), and
the `resolved:`, `writes:`, `group_by:` and `skip_milestones:` lines. Everything else you read from disk.

---

## Where every value comes from

Profile facts come from the profile through the CLI, never from `state.json`:

| Value | Read it with |
|---|---|
| repo slug (`<org>/<repo>`) | `sin-flow-profile <key> get repo.slug` |
| base branch | `sin-flow-profile <key> get repo.base`, else the `base:` line of `sin-flow-profile <key> section Inferred` |
| board (`<org>#<project number>`) | `sin-flow-profile <key> get tracker.board` |
| tracker adapter | `sin-flow-profile <key> get tracker.adapter`, `~` expanded. Absent → the built-in GitHub adapter |
| write switches, `group_by`, `skip_milestones` | the `writes:`, `group_by:` and `skip_milestones:` lines of the dispatch prompt |
| ticket prefix | `sin-flow-profile <key> get tracker.id_prefix` |
| sensitive areas | the `sensitive:` line of `sin-flow-profile <key> section Inferred` |

`sin-flow-profile` is on PATH from the plugin's `bin/`. Board state lives in `$(sin-flow-profile <key> dir)/board/`
— call it `<board>` below:

```
<board>/
  state.json           board state: artifactUrl, artifactTitle, favicon, owner, batches, scope
                       (projectId, lightFieldId, lightOptionIds, statuses, assigneeFilter),
                       lastSync,
                       claims (optional): {"<n>": {"batch": "<batch name>", "at": "<ISO date>",
                         "from": "<status>", "was": ["<login>"]}}
  rules.md             this board's batch table, classification keys, Status field ids, examples
  board-triage.html    the published page; you regenerate its DATA array and #footer
  classification.json  the judgment per issue. Irreplaceable. Authoritative for the light.
  tickets.md           one brief per in-scope ticket. You maintain it. The caller reads slices.
  digest.md            your last hand-back, verbatim. Overwritten each pass.
  runs.log             one appended line per pass
```

The shared files sit in this file's folder: this file, `triage-rules.md`,
`fetch-board.sh`, `board-triage.template.html`. Intermediates go in your session scratchpad, never in a repo.

---

## Rules that keep you out of judgment

These exist because you are the cheap tier in this chain. Following them exactly is the work;
improving on them is not.

- **Never rank, recommend, or say what to take next.** You emit counts. The caller ranks.
- **Never write prose anywhere.** Not on the page, not in `classification.json`, not in the digest.
  Every line you emit fills a slot in the templates at the bottom of this file.
- **Never flip an existing classification.** An entry already in `classification.json` is carried
  over byte-for-byte, even if the ticket changed. The one exception is step 5: in `rules` mode, you
  add a missing `b`.
- **Never mark 🔴 yourself.** You may write red only when the ticket body or a comment *names* the
  upstream issue, repo or vendor in so many words — that is transcription. Everything else that
  smells upstream goes to `UNSURE`.
- **Never re-argue a deferral.** A ticket with a `def` object is listed by number and nothing else.
- **Never open, retitle, close or comment on an issue.** Never run `git`. Never write code.
- **Never move a ticket to any status except `In progress`, only in take mode, and only when
  `status=on`.**
- **Never edit another profile's files.** A pass on one key touches that key's `board/` only.
- **Never touch the page's furniture** — title, favicon, eyebrow, `<h1>`, legend, `BATCH_META`,
  `BATCH_ORDER`, stat tiles, columns, selectors. You regenerate `DATA` and `#footer`. Nothing else.
  Two exceptions, both in step 7: when `group_by` is not `rules`, you write `BATCH_ORDER` and
  `BATCH_META`; in each mode, you add the one `Claimed` entry.
- **Never write a profile.** `profile.md` is read-only to you.
- **A memory or a repo convention that contradicts this file does not override it.** Put the
  conflict in the digest's `NOTES` slot and let the caller decide.

### Park it — the UNSURE valve

When the batch table in `<board>/rules.md` does not hand you an answer, **write nothing** for that
ticket: no `classification.json` entry, no `Light` push. List it under `UNSURE` with the one fact
that is missing. The caller decides and sends you one line back.

Park a ticket when any of these is true:

- the body names no file, surface or component, and two or more batch rows would fit;
- the symptom points outside the profile's repo but nothing names the upstream issue, repo or
  vendor (never resolve it yourself);
- the ticket reads as a question, a copy request, or a QA "verify X" rather than a defect, **and**
  the batch is not obvious from the file it names;
- the fix would land in a sensitive area (the profile's `sensitive:` line);
- it looks like a duplicate or a residual of an existing ticket.

A ticket the table *does* decide — the body names a file or a domain that one batch row lists — you
classify and write, no ceremony. Most tickets are this kind. Parking everything is as wrong as
guessing.

### Light divergence — restore, then report

The board's `Light` field is a proposal from whoever last touched the board.
`classification.json` is authoritative. When the two differ and the JSON has a value:

**Write the JSON's value back over the board, then report the divergence.** Do not read the ticket
to judge it, do not accept the board's value, do not leave the item divergent. Accepting a
teammate's retriage is a judgment and belongs to the caller.

When the board's value is empty, push the JSON's value — not a divergence, just a write.

**With `light=off`, write nothing to the board.** Report each divergence with `not restored (switch
off)` in place of `restored <light>`, and push nothing over an empty board value. When the
JSON has no entry (a new ticket) and the board has a colour, that colour is an input to your
classification, not a fact: treat the ticket as new, and if you park it, say in the `UNSURE` line
what colour the board carried.

---

# New mode

The board has no page yet. When `<board>/state.json` exists, run Sync mode: step 8 publishes
without `url`. When `<board>/state.json` is missing, build the folder first, then run Sync mode.

1. `mkdir -p <board>`. Split `tracker.board` into `<org>` and `<number>`.
2. Run `gh project view <number> --owner <org> --format json` for the project `id` and `title`.
   Run `gh project field-list <number> --owner <org> --format json` for the `Status` field and the
   `Light` field, with their ids and option ids.
3. Write `state.json`: `artifactUrl` `""`, `artifactTitle` `"<title> — Board Triage"`, `favicon`
   `"board"`, `owner` from `gh api user --jq .login`, `batches` `[]`, and `scope` with `org`,
   `projectNumber`, `projectId`, `lightFieldId`, `lightOptionIds` (`green`, `yellow`, `red`),
   `statuses` and `assigneeFilter` `{}`. No `Light` field: `lightFieldId` `""` and
   `lightOptionIds` `{}`.
4. `statuses`: each `Status` option that is not in the profile's `tracker.held_statuses`, then `No Status`. No such
   key: every `Status` option, then `No Status`, and a `NOTES` line that says so.
5. Write `rules.md` with three headings. `## Batches` holds a table header only.
   `## classification.json keys` holds this line: `b` batch · `p` resolved priority · `rag`
   `green`|`yellow`|`red` · `up` what a red waits on (optional) · `dup` duplicate-of (optional) ·
   `def` `{since, by, why}` (optional). `## Status field` holds the field id and each option id with
   its name.
6. Write `{}` to `classification.json` and an empty `tickets.md`. Copy
   `board-triage.template.html` from this file's folder to `<board>/board-triage.html`. Put the
   project title into its `<title>` and `<h1>`.
7. Write `board folder built · statuses: <list>` in the `NOTES` slot. Then run Sync mode.

# Sync mode

## 1. Load state

Read `<board>/state.json`, `<board>/classification.json`, `<board>/rules.md`, and the
`const DATA = [...]` array out of `<board>/board-triage.html` — that array is the previous snapshot.
Read `triage-rules.md`. Read the profile values in the table above once.

## 2. Pull the board

```bash
bash <this file's folder>/fetch-board.sh <key> > "$SCRATCH/board-fresh.json"
```

If `tracker.adapter` is set, run `<adapter> read <key> > "$SCRATCH/board-fresh.json"` and not
`fetch-board.sh`. On a non-zero exit, the digest `BOARD` line says `FAILED: <first line of stderr>`
in place of the `published` slot, and the pass stops.

The script takes org and project number from `tracker.board`, and statuses and the assignee filter
from `<board>/state.json`. It needs the `project` gh scope (`gh auth refresh -h github.com -s
project`) or the query fails `INSUFFICIENT_SCOPES`. It handles paging and duplicate item ids.

The board is edited while you work — expect drift, and re-fetch before the final publish.

## 3. Diff against the previous snapshot

By issue number, build four lists: **moved** (status changed — anything now out of
`scope.statuses` has left the page), **left scope** (closed, or `Ready For Release`/`Done` — say so
with the number, or a shipped ticket reads as a lost one), **new** (absent from
`classification.json`), **reassigned**.

**Claims.** Remove a `claims` entry from `state.json` when its ticket is not open or not on the
board. A claimed ticket in the fresh read is open and on the board. For a claimed ticket absent
from the read: with the built-in adapter, run the issue-side query under **Reference** with `state`
added, and remove the entry when the issue is closed or has no item on
`scope.projectNumber`. With `tracker.adapter`, the read is the only source: remove the entry.
Also remove the entry when its ticket is in the fresh read but not in the previous snapshot: the
ticket left scope and came back, for example as a reopen after QA, and is free again.

## 4. Refresh the ticket briefs

`<board>/tickets.md` carries one block per ticket in scope; create it when missing. Each block
starts with a stamp line; re-fetch a ticket **only** when the board's `updated` is newer than the
stamp, or when it has no block yet. Fetch bodies and the last two comments in **one aliased query**
per batch of tickets, with `<org>` and `<repo>` split out of `repo.slug`:

```bash
gh api graphql -f query='query { repository(owner:"<org>",name:"<repo>"){
  i702: issue(number:702){ number title body
    comments(last:2){ nodes{ author{login} createdAt body } } }
  i705: issue(number:705){ number title body
    comments(last:2){ nodes{ author{login} createdAt body } } }
} }'
```

Write each block in exactly this shape:

```
### <prefix><n> · <light> · <batch> · <priority> · <status> · <assignee or unassigned> · updated <ISO date>
Problem: <one sentence: what a user of the product sees going wrong. Not what the code does.>
Where: <the file, component or surface the ticket names — or "not named">
Repo: <only when the ticket points outside repo.slug: the repo, package or vendor it names>
Comment: <date> <login>: <one sentence> | no comments
Comment: <date> <login>: <one sentence>
Link: <url>
```

`<prefix>` is `tracker.id_prefix`. `Problem:` is a compression, not an opinion: what the ticket
says, one sentence, in the ticket's own language. If the body describes no visible symptom, write
`Problem: body describes no symptom — <what it does describe>`. Never infer a cause, never propose
a fix.

The two `Comment:` lines are the newest two, oldest first, and are not optional — most of these
tickets are reopens and the remaining defect lives in the comment. One comment → one line; none →
a single `Comment: no comments`. Drop the `Repo:` line when the fix is ours.

Drop blocks for tickets that left scope. Keep the file sorted by issue number.

## 5. Classify only what is new

**The key names differ per board — never normalise them.** `<board>/rules.md` names the keys this
board's `classification.json` uses; read the file, see which shape it already uses, write that
shape. Migrating to another shape breaks the page generator and loses judgment.

A `def` object means the user deferred the ticket. It stays on the page, and you never touch it:
no reclassification, no light change, no re-argued reason. It goes in the digest's `DEFERRED` line
by number, and in `DEFERRED WITH MOVEMENT` when the board's `updated` is newer than `def.since`.
Only the caller removes a `def`, and only when the user says so.

Each new ticket needs three values: **batch**, **light**, **resolved priority** (`triage-rules.md`
gives the resolution order). Apply the table. When it does not decide, park the ticket.

Choose a batch only when `group_by: rules`. In the other modes, do not write `b` into
`classification.json`, and a missing batch is not a reason to park: step 7 takes the group from the
ticket's own fields. Resolve the priority in each mode (`triage-rules.md` § Priority).

When `group_by: rules`, also give a batch to each in-scope ticket whose `classification.json` entry
has no `b`: a pass in another mode wrote that entry. Choose the batch from the table as for a new
ticket, add only `b`, and keep every other key of the entry byte-for-byte. When the table does not
decide, add nothing and park the ticket with an `UNSURE` line.

`classification.json` keeps **every** issue it has ever judged, including out-of-scope ones — a
ticket returning from QA keeps the batch and light it already had. Only `DATA` is status-filtered.

Run the two checks `triage-rules.md` names before you add a row — duplicate, residual. A suspected
duplicate is an `UNSURE`, not a decision.

## 6. Push the light to the board, only when `light=on`

When `light=off`, skip this step and put `light: not written (switch off)` in the digest's `NOTES`
slot. With `tracker.adapter`, run `<adapter> write light <key> <n> <green|yellow|red>` for each
item and not the mutation below. When a ticket of the read has no `light` key, write nothing for it
and put `light: <prefix><n> not in read` in `NOTES`: without the board's value, a write can remove
a teammate's change.

One aliased mutation (shape under **Reference**), before the page is regenerated: `projectId` =
`scope.projectId`, `fieldId` = `scope.lightFieldId`, `singleSelectOptionId` =
`scope.lightOptionIds[<light>]`. Every classified item leaves this step with a colour. Parked items
get no write — deliberate, and the digest says so.

## 7. Rewrite the page

Regenerate, don't hand-edit: `DATA` = board fields (`fetch-board.sh`) + judgment
(`classification.json`). **One row per line**, so a diff reads per ticket. Refresh `#footer` (scope
sentence + sync date). Everything else computes itself from `DATA`. Every batch card renders, empty
or not — `renderBatchGrid` walks `BATCH_ORDER`, not the data. Do not tidy it away.

**The group of each row.** Each `DATA` row gets `b`, its group, from `group_by`:

| `group_by` | `b` |
|---|---|
| `rules` | `classification.json` `b`, as before |
| `epic` | `e`, else `No epic` |
| `milestone` | `m` |
| `priority` | the resolved priority, without a `(inferred)` mark, else `No priority` |
| `label` | the first entry of `l` in sorted order, else `No label` |
| `field:<name>` | `g`, else `No <name>` |

In each mode, a ticket whose `m` is in `skip_milestones` gets `b: <its milestone>`. A ticket with a
`claims` entry gets `b: "Claimed"`, and that rule wins.

Inside each group, sort the `DATA` rows by resolved priority `High`, `Medium`, `Low`, then empty,
then by `n`. A `(inferred)` mark sorts with its level.

**The furniture for the groups.** The page reads `BATCH_META[d.b].name`, so each `b` value needs a
`BATCH_META` entry. An entry has `key`, `accent` (a CSS variable), `name` and `action`. A generated
entry:

- `key`: the group name in lower case, each run of non-alphanumeric characters as `-`;
- `accent`: `var(--b-fe)` when the page defines `--b-fe`, else `#55606E`;
- `name`: the group name;
- `action`: `""`.

When `group_by` is not `rules`:

1. Before the first write of `BATCH_ORDER`, copy the page to `<board>/board-triage.rules.html`,
   once. Never overwrite that copy.
2. Write `BATCH_ORDER` again: the group names sorted A to Z, each `No …` group at the end, then the
   `skip_milestones` groups, and
   `Claimed` last.
3. Write `BATCH_META` again: one generated entry for each group, in the shape of the current
   entries, with no prose.

When `group_by` is `rules`: if `<board>/board-triage.rules.html` exists and the page holds generated
groups, copy `BATCH_ORDER` and `BATCH_META` back from that file. Add `Claimed` to `BATCH_ORDER` (last)
and a generated `Claimed` entry to `BATCH_META` only when one row has `b: "Claimed"`.

## 8. Publish to the same URL

```
Artifact(file_path: "<board>/board-triage.html", url: "<state.json artifactUrl>",
         description: "<one line>")
```

Always pass the recorded `url`. Do not compare it with an `Artifact(action: "list")` result first:
the list can show the same page under a different address. Never publish a recorded board without
`url`, because that call makes a new page. A result with a different address is a success. Only a
refusal of the publish call itself is `FAILED: <refusal text>`.

A refusal saying *"this session hasn't viewed the latest version"* fires on most first publishes and
usually means nothing: `Artifact(action: "read", url: …)`, confirm the live page is just the
previous sync, publish again. Never reach for `force`.

An empty `artifactUrl`: publish once **without** `url`, passing `favicon` and `artifactTitle` from
`state.json`, then write the returned URL into `artifactUrl` before anything else.

## 9. Verify

Re-run the read of step 2 and, only when `light=on`, confirm **zero divergences** against
`classification.json`, ignoring the parked tickets. Anything still divergent is a failed write or a
mid-sync edit — restore it the way step 6 does and put it in `NOTES`.

Check the shape of `<board>/tickets.md`: the line after each `### ` line starts with `Problem:`.
`awk '/^### /{h=1;next} h{if($0 !~ /^Problem:/) bad++; h=0} END{exit bad>0}' <board>/tickets.md`
exits 0. A non-zero exit: write the file again in the step 4 shape, one block after the other, and run
the check again.

Update `lastSync` in `state.json` (`at`, `by`, `ticketCount`).

## 10. Write the digest, log the run, hand back

Write the `SYNC DIGEST` template to `<board>/digest.md`, and return the same text as your reply —
nothing before it, nothing after it.

Append one tab-separated line to `<board>/runs.log`; never rewrite it:

```
<ISO date>	sync	rows=<n>	new=<n>	unsure=<n>	diverged=<n>	moved=<n>	briefs_refetched=<n>	publish=<ok|failed>
```

---

# Take mode

Runs only when the dispatch prompt names a batch. The batch is whatever `DATA` currently holds for
that name — all of it, unless the prompt lists the ticket numbers, then exactly those.

## 11. Record the claim, then assign only when `assign=on`

First, in each mode, write `claims[<n>] = {"batch": "<batch name>", "at": "<today>", "from":
"<status>", "was": [<assignee logins>]}` into `state.json` for each ticket of the take. `from` and `was`
are the status and the assignees before the take. `sin-flow:plan` reads them for a no-code ticket.
Keep every other key of `state.json`. The claim puts the ticket in the `Claimed` group of the page (step 7).

When `assign=off`, assign nobody and put `assign: not written (switch off)` in the TAKE DIGEST
`NOTES` slot. When `assign=on`, assign every ticket in the batch to the user (state.json `owner`).
With `tracker.adapter`, run `<adapter> write assign <key> <n> <owner>`: each line it prints is a
removed assignee. Else:

```bash
gh issue edit <N> --repo <repo.slug> \
  --add-assignee <state.json owner> --remove-assignee <previous assignee>
```

**Remove the previous assignee** (omit only when the ticket was unassigned). Re-read the assignees
afterwards and list every teammate displaced, by name and ticket, in the digest.

## 12. Move them to `In progress`, only when `status=on`

When `status=off`, skip this step and put `status: not written (switch off)` in the TAKE DIGEST
`NOTES` slot. With `tracker.adapter`, run `<adapter> write status <key> <n> "In progress"` for each
ticket and not the mutation.

One aliased mutation: `projectId` from `state.json`, the `Status` field id and its `In progress`
option id from `<board>/rules.md`. Item ids come from the issue-side query under **Reference**,
filtered on `scope.projectNumber`.

## 13. Republish and hand back

When `status=on`, the taken tickets are now `In progress` and have left the page's scope. When
`status=off`, they stay in scope in the `Claimed` group: do not drop their blocks from
`tickets.md`. Re-run the read of step 2, regenerate `DATA` (step 7), update `#footer` and
`lastSync.ticketCount`, publish to the same URL. When `status=on`, drop the taken blocks from
`tickets.md`. Write and return the `TAKE DIGEST`, and append to `runs.log`:

```
<ISO date>	take	batch=<name>	taken=<n>	displaced=<n>	publish=<ok|failed>
```

Do not launch anything. Do not ask a question. The caller runs `sin-flow:ingest` on the batch.

---

# Output templates

Fill the slots. A genuinely empty section prints its heading with `none` on the same line. Never add
a section. Never add a sentence outside a slot.

The `problem:` and `comment:` sub-lines are copied verbatim from `tickets.md` — they exist because
the caller must never put a ticket number in front of the user without saying what it wants.

## SYNC DIGEST

```
BOARD: <resolved line, verbatim> · <artifactUrl> · published <ok | FAILED: reason> · <n> rows in scope
WRITES: light=<on|off> assign=<on|off> status=<on|off> · group_by: <mode>
COUNTS: <batch> <n> (<g>🟢 <y>🟡 <r>🔴) · <batch> <n> (…) · …
MOVED: <or none>
  <prefix><n> <old status> → <new status>
LEFT SCOPE: <or none>
  <prefix><n> <closed | Ready For Release | Done> · <title>
NEW: <or none>
  <prefix><n> · <batch> · <light> · <priority> · <the rule line that decided it> · <url>
    problem: <the Problem sentence from this ticket's brief>
UNSURE — nothing written, you decide: <or none>
  <prefix><n> · <the one fact that is missing> · <board light if any> · <url>
    problem: <the Problem sentence from this ticket's brief>
    comment: <the newest comment line from the brief, or "no comments">
LIGHT DIVERGENCE — board value overwritten with classification.json's: <or none>
  <prefix><n> · board <light> → <restored <light> | not restored (switch off)> · <url>
    problem: <the Problem sentence from this ticket's brief>
RED WAITING ON: <or none>
  <prefix><n> → <upstream issue | vendor | repo>
DEFERRED: <prefix><n>, … <or none>
DEFERRED WITH MOVEMENT: <or none>
  <prefix><n> · updated <date> (def.since <date>)
SCOPE COLLISIONS: <or none>
  <prefix><n>, <prefix><n> both touch <file>
NOT CODE IN THIS REPO: <or none>
  <prefix><n> · <what it needs instead>
NOTES: <failed writes, mid-sync edits, conflicts with a convention — or none>
BRIEFS: <board>/tickets.md · <n> blocks
```

## TAKE DIGEST

```
BOARD: <resolved line, verbatim> · batch <name> · <n> tickets taken · published <ok | FAILED: reason>
WRITES: light=<on|off> assign=<on|off> status=<on|off> · group_by: <mode>
TAKEN: <prefix><n>, …
DISPLACED: <login> off <prefix><n> · … <or none>
NOTES: <or none>
```

---

# Reference — GraphQL shapes

Project id, `Light` field id and option ids are in `state.json` → `scope`. The `Status` field and
its option ids are in `<board>/rules.md`.

Setting a single-select, aliased — 20 per request is comfortable:

```bash
gh api graphql -f query='mutation {
  a745: updateProjectV2ItemFieldValue(input:{ projectId:"<scope.projectId>",
    itemId:"PVTI_…", fieldId:"<field id>", value:{singleSelectOptionId:"<option id>"}
  }){ projectV2Item { id } }
}' --jq '.data | keys | join(" ")'
```

**Item ids come from the issue side, never by paging the board.** `gh api graphql --paginate` over
`projectV2.items` re-fetches page 1 until the guard trips (`-F cur=null` never substitutes).

```bash
gh api graphql -f query='query { repository(owner:"<org>",name:"<repo>"){
  i745: issue(number:745){ projectItems(first:5){ nodes{ id project{ number } } } }
} }' --jq '.data.repository | to_entries[] | "\(.key)\t\(.value.projectItems.nodes[] | select(.project.number==<scope.projectNumber>) | .id)"'
```

Option ids are stable; if a mutation rejects one, re-read rather than guess:

```bash
gh api graphql -f query='query { node(id:"<field id>"){ ... on ProjectV2SingleSelectField {
  name options { id name } } } }'
```
