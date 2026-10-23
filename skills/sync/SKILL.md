---
name: sync
description: 'Board stage of the flow (sin-flow:sync → sin-flow:plan → sin-flow:exec) for any repo whose flow profile names a GitHub Projects board in `tracker.board` or a local tracker adapter in `tracker.adapter`; the first argument is the profile key (default: the key of the cwd). Every milestone on the board is in scope. The mechanical half runs in the `sin-flow:board` subagent on the cheap tier: it fetches the board, diffs it, refreshes the per-ticket briefs, classifies what the rules decide outright, republishes the triage page and hands back a fixed-shape digest. This session never fetches a board. Phase 1 reports that digest, closes the tickets the agent parked, and proposes which batch to take. Phase 2 takes a named batch — the agent records the claim, then assigns it and moves it to In progress if the profile''s write switches permit, and writes the seed plan in ~/.claude/sin-flow/work/<key>/ — then hands off to sin-flow:plan. Use when invoked as `/sin-flow:sync [key] [take <batch>|new]`, when asked to sync/refresh the board triage, to see what is open or blocked, or to take/assign a batch.'
---

# sin-flow:sync — one board per profile

A private working picture of every **unstarted** ticket on one profile's board, grouped into
batches that can be fixed together, each lit by whether it can be started now, plus a way to claim
one batch in a single move.

| Phase | Ends with |
|---|---|
| **1 — Sync and propose** | a ranked proposal of which batch to take, then **stop and wait** |
| **2 — Take a batch** | the batch is claimed and a planning session is running |

Phase 2 runs **only** when the user says the word. Never take a batch on your own initiative, and
read **Discussing a batch is not taking it** below before you believe you have been told to.

Chat with the user in `chat_language` from `~/.claude/sin-flow/user.md`, or in the language the user writes in when it is absent. Headings and fixed phrases defined here are rendered in that language. Files, commits, PRs and issues are always English.

## Tracker and switches

Profile keys that sync reads. The contract for a local adapter is
[`reference/adapter-contract.md`](reference/adapter-contract.md).

| Key | Default | Meaning |
|---|---|---|
| `tracker.adapter` | absent | path of a local tracker adapter. When set, sync reads and writes through it and ignores `tracker.board` |
| `tracker.board` | absent | `<org>#<project number>` of a GitHub Projects board, the built-in adapter |
| `tracker.write.light` | `off` | push the light of each classified ticket to the tracker |
| `tracker.write.assign` | `off` | in take mode, make the user the only assignee |
| `tracker.write.status` | `off` | in take mode, move the taken tickets to `In progress` |
| `group_by` | `milestone` | the groups on the page: `epic`, `milestone`, `priority`, `label`, or `rules` (the batches of `board/rules.md`) |

An absent switch is `off`. With an adapter, a write step that `<adapter> supports <key>` does not
list is `off` too. The page shows lights, groups and claims with every switch off.

## Step 0 — Profile, silently

The `resolve` line is the one output of Step 0. All other Step 0 checks stay silent.

Run `sin-flow-profile resolve <first argument>`, or `sin-flow-profile resolve` with no argument. The
first argument is the first word of the invocation unless that word is `take` or `new`. Exit 2 →
print its output, which is the `usage:` line, and stop. Exit 0 → keep the line it prints:

```
key: <key> · tracker: <adapter path | board | none> · from: <argument | cwd> · cwd profile: <key | none>
```

`<key>` is its `key:` value. **The first line of each chat report of this run is that line,
verbatim.** Print it before the checks below, so a stop also shows the key. Give it in each
dispatch prompt as `resolved: <line>`.

`tracker: none` → one line, `no board in this profile`, and stop. No
`$(sin-flow-profile <key> dir)/board/state.json` → run phase 1 with `mode: new`. The agent builds
the board folder first.

Read the switches with `sin-flow-profile <key> get <field> || true`: `tracker.write.light`,
`tracker.write.assign`, `tracker.write.status` and `group_by`. The CLI reads these four and
`tracker.adapter` from `profile.md` only, never from the team file `.claude/flow.md`. An absent
switch is `off`; an absent `group_by` is `milestone`. When `sin-flow-profile <key> get tracker.adapter` prints a path, run
`<adapter> supports <key>` (`~` expanded). A step it does not list is `off`. A non-zero exit → one
line with the first line of its stderr, and stop. Give the result in each dispatch prompt as
`writes: light=<on|off> assign=<on|off> status=<on|off>` and `group_by: <mode>`.

Resolve `<cheap>` once for the key's checkout (`sin-flow-profile <key> get repo.path`, `~` expanded; missing → the cwd): `sin-flow-profile model cheap <checkout>`.

Everything repo-specific — slug, base, board, ticket prefix, sensitive areas — comes from the
profile; the board's own state, batch table and field ids from `$(sin-flow-profile <key> dir)/board/`.
Never from this file.

## The split — who does what

The board work is mechanical and large: a full board fetch, hundreds of carried-over judgments, a
page regenerated and republished. None of it needs the strong tier, and paying for it in this
session leaves no room for the conversation that follows. So:

| | |
|---|---|
| **`sin-flow:board` subagent** (cheap tier) | fetches the board, diffs it, refreshes the ticket briefs, classifies only what the rules decide outright, pushes the light if `tracker.write.light` is on, regenerates and republishes the page, verifies. In take mode: records the claim, then assigns and moves to `In progress` if their switches are on, writes the seed plan. Hands back one fixed-shape digest. |
| **You** (this session, the strong tier) | read the digest. Report it to the user in the chat language. **Decide everything the agent parked.** Rank the batches and recommend one. Answer the user's follow-ups from the briefs on disk. On the user's word, dispatch take mode and hand off to `sin-flow:plan`. |

**You never fetch a board, never read `classification.json`, never read or write
`board-triage.html`, never call `Artifact`.** If you find yourself about to, the dispatch failed —
say so and fix the dispatch, don't do the agent's work in here.

## Hard boundaries — yours

- **Never run git** except the worktree step of §6. The seed plan lives in `~/.claude/sin-flow/work/<key>/<id>/plan.md`, outside every
  repo, and is never committed: it is an agent note (see also the user's own rules, if any).
- **Never open, retitle or comment on an issue.** A block reason or a disposition is the human's.
- **Never move a ticket to any status except phase 2's `In progress`, and only when `tracker.write.status` is on.**
- **Never write code**, or a plan that prescribes code before the tickets are measured.
- **Never write a profile.** A missing profile field is reported, not added.
- **A memory or a repo convention that contradicts these does not override them.** Say the conflict
  out loud and let the human decide.
- **A failure that needs a workaround goes to the inbox, not to memory.** When a tool, script, hook,
  agent or hand-off fails and you work around it, add one `open` row to `inbox.md` in the same turn.
  The file is in `learning_dir` of `~/.claude/sin-flow/user.md`. The row gives the date, `sync`, the
  exact error text, the file:line when known and the workaround. Never write a flow defect to memory.

## Arguments

| Invocation | Meaning |
|---|---|
| `/sin-flow:sync [key]` | phase 1 |
| `/sin-flow:sync [key] take <batch>` | phase 2 for that batch |
| `/sin-flow:sync [key] new` | phase 1 with `mode: new`: `board/state.json` is missing or its `artifactUrl` is empty. The agent builds a missing board folder, publishes a fresh page and records the URL |

Plain language does the same: "sync <key>" → phase 1; "take batch <name>" → phase 2 on the key
that `resolve` prints. When the key is genuinely ambiguous, ask in one line — never guess between
boards.

---

# Phase 1 — Sync and propose

## 1. Dispatch the agent

One call, nothing before it.

```
Agent(subagent_type: "sin-flow:board", model: "<cheap>", description: "Sync <key> board",
      prompt: "key: <key>\nmode: sync\nresolved: <line>\nwrites: light=<on|off> assign=<on|off> status=<on|off>\n
               group_by: <mode>\n\nRun the sync pass in
               ${CLAUDE_PLUGIN_ROOT}/skills/sync/reference/board-pass.md and return the SYNC DIGEST
               template, nothing else.")
```

Write `mode: new` in place of `mode: sync` for the `new` invocation or a missing `board/state.json`.

Keep the agent's id. You will send decisions back to it.

**When the digest carries a `FAILED` publish or a `NOTES` line you cannot resolve**, report exactly
that and stop. Do not retry by doing the work yourself.

## 2. Report — result first, plain words

**Bold labels, not `#` headings; one table; ~35–45 lines; the questions numbered at the end.** In
this order:

**The `resolve` line** — verbatim, as Step 0 printed it.

**Board state** — `<n> tickets: <g> 🟢 / <y> 🟡 / <r> 🔴`, the board, the page link stated as
unchanged.

**Movement** — what left the page and why: to QA, back as `Reopened`, shipped, closed. Nothing moved
is itself a line: `movement: none`.

Then the table, which is the part the user reads first — one row per group, empty groups included:

| Group | 🟢 | 🟡 | 🔴 |
|---|---|---|---|

In `group_by: rules`, the groups are the batches of `board/rules.md`, as before. After a switch to
`rules`, the agent gives a batch to each ticket that has none, or parks it. In the other
modes, the field that `group_by` names gives the groups. Inside a group, tickets sort by resolved
priority `High`, `Medium`, `Low`, then empty, then by number.

**New** — each new ticket: linked number, group, light, and **one sentence of what a user of the
product sees going wrong**. The digest carries that sentence on the ticket's `problem:` sub-line.

**Decisions needed** — numbered, step 3.

**Deferred** — exactly one line, numbers only (below).

**What I recommend taking** — step 4, one recommendation.

The 🔴 list and what each waits on, scope collisions, and "not code in this repo" are sub-lines
under `What I recommend taking` — they are the reason a batch is smaller than its count, not sections.

### Never ask a question without saying what the ticket is about

The correction the user has had to make most often, verbatim:

> you ask me questions, but you don't tell me what the ticket is about

Every ticket you name — in `New`, in `Decisions needed`, in `What I recommend taking` — carries **one
sentence of what the ticket wants**, and a link. A bare number with a question after it is a
failed report. The brief is already on disk.

The user also asks, every time it is missing, **whose repo the fix lands in**. When a ticket points
outside the profile's repo, say so on its line.

And the user asks whether the comments were read ("did you read their comments? or only the
description again?"). The agent puts the last two comments in every brief. Use them — a reopen's real
defect is in the comment, not the body.

### Deferred tickets get one line and nothing more

A deferred ticket carries a `def` object and stays on the page — the deferral is a decision about
*what to work on*, not about the board. The report must not re-argue it:

> Still deferred, not proposed: GH-976, GH-1227.

Never re-explain a reason already in `def.why`, never re-propose a deferred ticket under
`What I recommend taking`, and never silently drop one from the line.

**The one exception that earns a second line** is the digest's `DEFERRED WITH MOVEMENT` slot:
someone commented, labelled, or closed it — that is how most deferrals lift.

> Deferred with movement: GH-1227 — updated 2026-09-22.

Un-defer only when the user says so.

## 3. Close what the agent parked — your half of the job

The agent writes nothing for a ticket the rules do not plainly decide, and it restores
`classification.json`'s value over any light a teammate changed on the board. Both land in the
digest, and both are yours.

**Split them by whose call it is, out loud** ("tell me briefly which decisions are needed — which
are yours, which are mine"). Under `Decisions needed`, two groups:

- **I decide** — decide it, say what you decided in one line, move on. Batch when the board's
  rules decide once you have read the brief; light 🟢/🟡; priority; a duplicate or residual call.
- **Yours** — a product call, a copy question, a priority the user owns, whether a symptom is worth
  chasing. Numbered, one sentence of what the ticket wants, one sentence of the question, a link.

For each parked ticket: read its block in `board/tickets.md` first; open the issue only if the
block is not enough. **🔴 is always yours** — the agent may not invent one, because red means a
named blocker and a routing decision.

For each `LIGHT DIVERGENCE`: a teammate proposed a colour and the agent overwrote it with the
recorded one. Read the ticket, then **accept** or **confirm the reject**. Report both values and the
reason either way, so a teammate's retriage is never silently undone. A 🔴 set because the symptom
*looks* like bad data is exactly the mistake the verify-upstream batch exists to catch.

Send everything you decided back in one message; the agent writes it and republishes:

```
SendMessage(to: "<agent id>",
            message: "decisions:\n  GH-1307 · batch <batch> · light yellow · priority High (inferred)\n  GH-1288 · accept the board's red · waits on <org>/<repo>#884\nApply these, republish, and return the SYNC DIGEST again.")
```

**The counts may not shrink between turns.** When you re-report after a round of decisions, the
table and the ticket list cover the same set as before, plus what changed: *"why do you write a table
for 8 tickets. and then for 3."*

## 4. Propose what to take, then stop

- Rank batches by how much 🟢 unstarted work each holds; **lead with the recommendation**, one line.
- Name the **clusters inside a batch that share a file** — those must travel in one branch.
- Flag any ticket in the recommended batch that is **not code in the profile's repo**.
- Deferred tickets and the `Claimed` group are excluded from the proposal.

Then **stop.** Do not assign, do not move statuses, do not write a plan, do not launch anything,
do not ask whether to proceed.

## Answering follow-ups — the user asks by group, not by ticket

What the user types after a report: *"tell me about the reds"*, *"let's talk about the yellows"*,
*"1279, 1227, 1269 a bit more context"*, *"1310 a real example — link, I want to see it"*. Five to eight
tickets at a time, a whole colour or a whole batch.

The briefs are on disk, one block per in-scope ticket, comments included:

```
$(sin-flow-profile <key> dir)/board/tickets.md
```

**Read the slice, never the file.** `grep -A6 '^### GH-1227' …`, or one `grep` for the whole group
the user named. Only when a block is not enough do you open the issue — and then read the **latest
comment first**, because most of these are reopens.

Answer a group in the fixed ticket headings, one block per ticket: the ticket link as the signature
line, then **WHAT HAPPENED · EVIDENCE · WHAT WE DO** (see also the user's own rules, if any). A
heading with no content says so on its line.

---

# Phase 2 — Take a batch

## Discussing a batch is not taking it

The single failure the user has had to correct most often, in the user's own words:

> you started again. we are still discussing the yellows!!! why did you start. I want to add
> something else!

> I don't understand why you started the planner for 45 when we have not finished. I said
> "add to the batch" but I had not said TAKE the batch yet.

The user assembles a batch out loud, over several turns, before taking it. Assembling is not taking.

| The user says | You do |
|---|---|
| "take …", "yes, take <batch>", "take all the greens", "take these 4 greens" | **phase 2** |
| "add to the batch", "let's add 7 greens", "let's talk about the yellows", "I'll add something else", "leave it out of this scope", "976 stays out of this one" | **nothing** — keep the running list, keep talking |

The trigger is **take**, said as an instruction, nothing else. When you are not certain, keep
talking. Asking "take it?" once costs one line; starting a planner the user did not ask for costs
the whole session.

While the user is assembling, hold the list in the conversation and restate it when it changes. Do not
write a seed plan, do not assign anything, do not dispatch the agent, do not open a tab.

## 5. Dispatch take mode

```
Agent(subagent_type: "sin-flow:board", model: "<cheap>", description: "Take <batch> on <key>",
      prompt: "key: <key>\nmode: take <batch name>\ntickets: <numbers, when the user narrowed the batch>\n
               resolved: <line>\nwrites: light=<on|off> assign=<on|off> status=<on|off>\ngroup_by: <mode>\n\n
               Run the take pass in ${CLAUDE_PLUGIN_ROOT}/skills/sync/reference/board-pass.md and return
               the TAKE DIGEST template, nothing else.")
```

The agent records the claim of every ticket in `state.json` `claims`. Then, if
`tracker.write.assign` is on, it assigns every ticket to the user (state.json `owner`) and removes
the previous assignee. If `tracker.write.status` is on, it moves them to `In progress`. It writes
the seed plan and republishes the page. It does not launch
anything.

Report: tickets taken, **every teammate displaced by name and ticket**, the seed plan's path, and
how many tickets are genuinely codeable versus blocked on something outside the repo.

## 6. Hand off to `sin-flow:plan`

Phase 2 does not end with a question. The user already chose the batch; "shall I plan it now?" is
a stop the user did not ask for.

Answer every part of the user's current message before the hand-off: take-updates are reversible,
the launch is not.

**The next stage never inherits this session's model.** `sin-flow:plan` runs on `<strong>`: `sin-flow-handoff` resolves it from `--cwd`; with `--cwd` omitted, add `--model <strong>` from `sin-flow-profile model strong`.

**Worktree first.** A taken batch is an ingest from the board, so it gets its worktree the same way:
`sin-flow-worktree --repo <the checkout below> --name <id>-<slug> --branch <branch> --base origin/<base>`, with
`<id>` the seed's folder name and `<slug>` kebab-case from the batch name. In Orca it makes an Orca workspace, so
the plan and exec tabs show in its own row; when it prints `mode: orca`, close its `shell:` as `skills/ingest/reference/exits.md` says. Write `worktree: <path>` into the
seed header; `sin-flow:plan` keeps that checkout. No checkout below → skip this step; plan creates the worktree.

```
sin-flow-handoff [--cwd <worktree>] --name plan-<id> sin-flow:plan <absolute seed path>
```

`<id>` is the seed's folder name (`batch-<N>` or `gh-<N>`). The checkout is `sin-flow-profile <key> get repo.path`
with `~` expanded; missing → the main checkout of this session's cwd when the `resolve` line says `cwd profile: <key>`
(its `repo.slug` matches): `dirname "$(git rev-parse --path-format=absolute --git-common-dir)"`; neither → omit
`--cwd` — `sin-flow:plan` resolves the profile from the seed's `profile:` line.

**Read the output and the exit code.** `opened: …` — planning runs in a new tab; never start a second one.
`paste into a new terminal tab …` — no tab: relay the printed command in one line.
`continue in this session: …` → invoke `sin-flow:plan` with that path in this session.
Non-zero — no tab opened: `1` bad path, `2` bad option or `handoff:` setting, any other code is the
launcher's own. Invoke `sin-flow:plan` in this session instead, and say in one line what you substituted.

Put the `opened:` or printed line in your closing report, then stop. Planning belongs to that session now.

**`CTX GUARD` in a tool result:** finish the in-flight dispatch; a batch already taken gets this hand-off now; otherwise say in one line that the talk continues in a new `/sin-flow:sync <key>` session (`board/digest.md` and `tickets.md` carry it), and stop.

---

## Files

Everything lives outside any repo, so a sync never shows up in a project's `git status`.

```
${CLAUDE_PLUGIN_ROOT}/skills/sync/
  SKILL.md                    this file — the chat side. Thin on purpose.
  reference/board-pass.md     the agent's playbook: every mechanical step, boundaries, templates
  reference/triage-rules.md   the light vocabulary, the priority order, the two checks
  reference/fetch-board.sh    paginated board fetch → normalized JSON on stdout; takes the key
  reference/adapter-contract.md  the contract for a local tracker adapter: commands, ticket shape
~/.claude/sin-flow/profiles/<key>/board/
  state.json                  board state only — repo, base and measurement are profile facts
  rules.md                    the board's batch table, classification keys, Status field ids
  board-triage.html           the published page
  classification.json         the judgment per issue. Irreplaceable. Authoritative for the light.
  tickets.md                  one short brief per in-scope ticket. Your drill-down.
  digest.md                   the agent's last hand-back, verbatim. Survives a compaction.
  runs.log                    one appended line per pass
~/.claude/sin-flow/work/<key>/<id>/plan.md   the seed a take writes
```

## Scope

**No milestone filter.** Every open issue on the board is in scope; each row carries its milestone
so the split stays *visible*, nothing filters on it.

**The status filter must not widen beyond `scope.statuses` in `board/state.json`.** Statuses that
mean someone is holding the ticket — QA, In progress, In review, Blocked — are out on every board:
the page answers *"what can I pick up next"*, not *"what is the team holding"*. `Reopened` stays
filtered to the user (`scope.assigneeFilter`): someone else's regression is not the user's to
re-fix. If `tracker.write.status` is off, a claimed ticket stays in scope and shows in the
`Claimed` group. A claimed ticket that leaves scope and comes back, for example as a reopen after
QA, loses its claim and goes back to its own group.
Movement belongs in the chat report, never on the page. A status outside `scope.statuses` appears
nowhere: not in the digest, the table, `Movement`, `Decisions needed` or a follow-up answer.
