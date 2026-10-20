---
name: plan
description: 'Plan stage of the flow (sync / ingest → plan → exec), for any repo that has a flow profile. Autonomous, runs on the strong tier in its own tab, never asks the user. Takes a seed or an epic intake from ~/.claude/sin-flow/work/<key>/<id>/, reads every ticket (latest comment first), fans out read-only source analysis, measures each claim through the profile''s measurement route, reconciles the two, and rewrites plan.md in place in English — one block per ticket or story with the measured evidence, the exact change, every copy and every writer, re-verify, tests, waves, builder/audit, gates from the profile, and a Finish line that is standing authorization for exec. Mirrors the plan to the GitHub issue when the profile says so (never in upstream mode), dispositions no-code tickets, then hands off to sin-flow:exec in a new tab. Use when invoked as "/sin-flow:plan [id|path]", or asked to verify/plan a batch, an epic or a ticket before coding.'
---

# sin-flow:plan — from seed to a plan a coder can follow literally

Stage 3 of the flow: **sync / ingest → *plan* → exec → review**. It ships no application code and
writes one file, `plan.md`, plus evidence beside it. Every line of the plan is backed by a
measurement, a `file:line`, or is tagged `inferred`.

```
${CLAUDE_PLUGIN_ROOT}/skills/plan/
  SKILL.md                         this file
  reference/plan-template.md       the exact shape of the written plan (Step 6)
  reference/probe-traps.md         measurement traps that bind on every repo, and the browser harness
  reference/harness-template.mjs   browser probe harness; every repo value comes from env (Step 4)
```

Everything repo-specific — base branch, gates, tracker, measurement route, sources, UI check,
branch and commit conventions — comes from the profile, never from this file.

Chat with the user in `chat_language` from `~/.claude/sin-flow/user.md`, or in the language the user writes in when it is absent. Headings and fixed phrases defined here are rendered in that language. Files, commits, PRs and issues are always English.

## Arguments

| Invocation | Meaning |
|---|---|
| `/sin-flow:plan` | the newest `plan.md` or `intake.md` under `~/.claude/sin-flow/work/<key>/`, `<key>` resolved from the cwd |
| `/sin-flow:plan <id>` | `~/.claude/sin-flow/work/<key>/<id>/` — `<id>` is whatever the folder is named (`gh-<N>`, `batch-<N>`, `epic-<N>`, `<N-M>`); carry it unchanged into branch, tab and progress lines, never parse it as a number |
| `/sin-flow:plan <path>` | that file |

Nothing found → one line naming the newest seed under that key, so one word or a path settles it.
A seed older than 2026-10-13 that still sits inside the repo is moved into `work/<key>/<id>/` before
Step 1 and never committed.

## Step 0 — Profile, silently

Run `sin-flow-profile validate` (resolves the profile from `git remote get-url origin`; fallback the
`profile:` line in the seed header). All green prints nothing. On a failure act as the setup design
says: no profile → run `/sin-flow:setup` onboarding in this session, then continue; `gh` not logged in or
`jq` missing → stop on one line with the fix; a gate not runnable → continue (plan does not run
gates).

Resolve the tiers once: `sin-flow-profile model strong` and `sin-flow-profile model mid`. `<strong>` and `<mid>`
below are the aliases they print; pass the alias as `model`, never the tier word.

Read once and keep for the whole run: the profile frontmatter, `## Inferred` (base, gates, tracker,
team, notes, sensitive), `## Measure`, `## Run`, `## Never`. Read via `sin-flow-profile <key> get <k>` for
a single key.

**Upstream mode** ⇔ `sin-flow-profile <key> get repo.fork` prints a slug: read
`${CLAUDE_PLUGIN_ROOT}/skills/ingest/reference/upstream.md` once; every `gh` call carries `-R <repo.slug>`.

**Never ask the user anything.** Every question belongs to ingest. A point the seed left open is
yours: decide it, write it into the plan's Rulings (Step 6), move on.

Models: this stage runs on the strong tier. Source analysts are `sin-flow:read-only-analyst` on `<mid>`,
`<strong>` only for a unit that adds a table, a migration or an abstraction other units build on. Name the
model on every dispatch, and only one of the resolved tiers.

---

## The doctrine — why this stage exists

**A plan written from source reading is not trustworthy enough to code from.** Measured over four
earlier batches (read: the old plan stage's record): 5 of 11, 2 + 3 of 10, 3 of 8 and 7 of 11 tickets
changed once measured — four planned fixes would have shipped without fixing their ticket.

**Expect ~20 % attrition and ~30 % root-cause rewrites; an all-reopens batch attrites ~half.** A pass
that confirms every ticket exactly as filed is a sign nothing was measured. The causes that made
reopens ship no code, each with its fix:

| Cause | Fix |
|---|---|
| merged, not deployed | a `deploy` probe first (`probe-traps.md` § stale deploy) and a marker in every fix comment |
| a test-harness artifact read as a user symptom | drive the real gesture, print before/after |
| one observation reported as a rate | ≥ 5 reps, print every rep |
| a benchmark against a different input | publish the query and filter set with every number |
| a coverage gap with no defect | accept source confirmation; a comment, not a status flip |

Two failure modes, opposite directions. **A fresh ticket** describes a real defect and usually
guesses the mechanism — believe the symptom, never its root-cause section. **A reopened ticket** may
describe a defect that no longer exists: the body is the original complaint, the last comment is a
different defect in the same code, and the reopen itself may be a stale deploy.

---

## Step 1 — Base, worktree, seed

`git fetch origin`. Base = the seed header's `base:`, else the profile's base (`repo.base` or
`## Inferred`). Record the real SHA of `origin/<base>` — the seed's recorded base is usually stale and
the header must not lie. When a unit depends on an unmerged branch or PR in this repo, that branch is the base.
The unit's PR is a draft against it. GitHub moves the PR to the profile base when a person deletes that branch
after its merge. Never write "start after the merge". The header `after:` and the spec `## Map` row give that
branch: the `plan` cell, then its `branch:` line. Write it in the header as `base: <that branch> @ <sha>`. If
the branch is only local, use the local ref, not `origin/`.

**A unit that waits in another repo.** The `after:` row names another repo. Before Step 2, find the PR of the
first unit with `gh pr list -R <its repo> --head <its branch> --state all --json url,state -q '.[0]'`. If the
PR is `CLOSED` and not merged, write one line to the user and stop. If no PR
exists, write one line to the user: `Plan <id> waits for the PR of <first id> in <its repo>. It stops after 24 h.`
Then start one background Bash with `run_in_background`, and end the turn:
`deadline=$(( $(date +%s) + 86400 )); until [ -n "$(gh pr list -R <its repo> --head <its branch> --state all --json state -q '.[0].state')" ] || [ $(date +%s) -gt $deadline ]; do sleep 60; done`.
Then run the lookup again. If the loop ends with no PR, write `Plan <id> stopped: no PR of <first id> in 24 h.` and end.
If the PR is `CLOSED` and not merged, write one line to the user and stop. If the loop ends
with an `OPEN` or `MERGED` PR, write `gh pr diff <url>` to `<work>/first-pr.diff`. Write
`gh pr view <url> --json headRefName,headRefOid,files` to `<work>/first-pr.json`. Each Step 3 brief reads
`first-pr.diff` in full. The base stays the profile base of this repo. The notification of the finished
background Bash wakes the session. Then continue with Step 2.

**Own checkout.** A seed whose `worktree:` line names a checkout keeps it, on its branch. Otherwise
remove this repo's `.claude/worktrees/*` whose PR is merged or closed and whose tree is clean
(`git worktree remove`, never `--force`), then
`git worktree add .claude/worktrees/<id>-<slug> -b <branch> origin/<base>` with the branch from the
profile's convention (`git.branch`, else `<prefix>/<type>/<id>/<slug>`) and write the path into the
plan's `worktree:` line. When the branch already exists, note `resume` and do not recreate it. When it must
sit on an unmerged branch or PR, `git merge --no-edit <that head>` in the worktree moves it there (`origin/<that head>` only when the branch is on `origin`); never
`git reset --hard`. Every
analyst and the auditor read code in that worktree, never in the shared checkout.

**Read the seed.** It always carries the header (`profile:`, `repo:`, `base:`, `exit:`, `status:`, `branch:`,
`source:`, `ticket:`, `worktree:`),
the units and file clusters. A seed from ingest or an epic intake may also carry `## Problem`,
`## Root cause (measured)`, `## Evidence`, `## Decisions (locked with the user, <date>)`,
`## Open decisions`, `## Not in scope`; an epic seed (`exit: epic`) adds `## File ownership` and
`## Dependencies`, which seed the waves:

- **Locked decisions are binding.** Copied verbatim into the plan, cited where a change follows from
  one, never reopened.
- **An `## Evidence` entry with query text, numbers, date and base SHA is a measurement.** Spot-check
  one number (Step 5); re-measure in full only if it disagrees or the base moved past its files.
- **`## Open decisions`** become Rulings lines (Step 6).

An epic seed or a legacy `intake.md` is the user's word; read it once. Check whether an adjacent batch the seed names has
started (`git branch -r --list`, `gh pr list -R <repo.slug>`) — a sequencing constraint is only real if it has.

## Step 2 — Read every ticket, latest comment first

When the tracker is GitHub issues, one pass over every ticket, bodies **and** comments:

```bash
for n in <numbers>; do
  gh issue view $n -R <repo.slug> --json number,title,state,labels,body,comments \
    --jq '"STATE: \(.state)\nTITLE: \(.title)\n\n--- BODY ---\n\(.body)\n\n--- COMMENTS ---\n"
          + ([.comments[] | "[\(.createdAt) \(.author.login)]\n\(.body)"] | join("\n···\n"))'
done
```

A local tracker (`tracker.kind: local`) has its story text in the intake; read that slice of the
repo's own artifacts the intake names. A rich seed does not skip this read — a comment may be newer
than the ingest session. A newer comment that contradicts a locked decision is not applied: the
decision stands, and the pair goes into the closing report as a question for the user.

**For a reopen, the last comment is the ticket.** Note per ticket: the layer, any question QA left
explicitly unverified (those are yours), and what would *disprove* it — that is the probe.

**A suggested fix may not be buildable** — one probe settles it before the plan builds on it.
**Look for a teammate's fix first**: `gh pr list -R <repo.slug> --search <N>` and the new branches from the fetch;
a teammate already carrying it → the ticket is dropped and the measurement goes on the issue — in upstream mode the measurement stays in `work/` and the plan row names the other PR.

## Step 3 — Source analysis fan-out, one message

One `sin-flow:read-only-analyst` per ticket or story (or tight pair), all in one message so they run
concurrently. Give each the text you already fetched — never make agents re-fetch. A brief carries:

- the defect or story as measured or decided, quoted, with numbers and the owned-files row;
- the files to read **in full**, in the worktree;
- **competing hypotheses named** — an agent given a list argues, one given none confirms the ticket;
  and an explicit instruction to say when the ticket's root cause is wrong;
- the repo's constraints from its `CLAUDE.md` and the profile's `## Never`; in upstream mode also the files of `upstream.md` § Rules to read;
- the required reply, ≤ 60 lines with `file:line` and quoted code: verdict; mechanism; exact
  insertion points and **the existing analogue to copy** (a new pattern is a finding, not a default);
  new files with full paths; the minimal change as before/after; migration shape if any; a re-verify
  assertion with expected before→after values; tests — which files, what they assert now, what to
  add, what breaks; i18n keys when the repo has locales;
- **every instance of the defect class**, not the one QA found;
- when the change touches a query, a list endpoint, a job or a loop over rows: the new query as SQL
  (`.to_sql` or literal) and the tables and filters it hits — you EXPLAIN it (Step 4);
- a perf note against the repo's page budget for any user-facing surface, when its `CLAUDE.md` has one.

Upstream § AI ban found → the plan header `status: blocked — <quoted line>`, no hand-off.

**Agents never drive a browser or run probes.** Source analysis fans out; measurement stays with you.

## Step 4 — The measurement route

The route is the profile's `measure.doc` and `sources.*` — nothing else. Read the doc **in full**
before the first probe and measure only the ways it prescribes; never print a credential, a
connection string or an env file, and never a value the doc marks private. Read
`reference/probe-traps.md` before writing any probe.

**Preflight: check, never ask.** Run `measure.preflight` (or each source's `preflight`) before
Step 3. Down → one status line `<source> down — measuring when it is up`, start
`until <preflight> >/dev/null 2>&1; do sleep 15; done` with `run_in_background`, and keep going with
Steps 2–3 and the draft. If it fires before Step 6, measure. If not, every claim that needed it is
`not measured — <source> unavailable (<reason>)`, stays `inferred`, gets its bounded query written
as that unit's first exec step, and the header carries `RULING_NEEDED: measure before exec`.
A probe the auto-mode classifier denies is the same path, with the reason `classifier denied`: do not
retry it and do not ask; write its inbox row (Step 10) and go on with code reads and `work/` notes.

**`measure.doc: none`** → every number is `not measured — no route`; claims stay `inferred`; numbers
are never invented and never taken from a local or dev database as a volume claim.

**Data routes (SQL, HTTP API).** Read-only queries and requests run by you; no runner scripts, no
writes. Every probe's query or request, the numbers, and the filter set go verbatim into
`evidence/<unit>.md` and the unit's VERIFIED block. A number without its query and filter set does
not count. Dev data is not prod data: never a volume or coverage claim from dev.

**Measure the change's query too.** When the change touches a query, a list endpoint, a job or a loop
over rows: `EXPLAIN (ANALYZE, BUFFERS)` of the NEW query on the route (a write: plain `EXPLAIN`, or
`BEGIN … ROLLBACK` only when the doc allows it); paste query, top plan nodes, rows, timing and filter
set. A local or test DB does not count. If it shows the change needs an index (concurrent), a schema
change or work moved into a job, that is part of this unit — never a separate ticket.

**Browser route** (the measure doc names a browser harness). Copy `reference/harness-template.mjs`
to the script directory the doc names, set its env from the doc (`probe-traps.md` § Browser harness),
sign in **as the account the ticket names**, and write the `deploy` probe first. The script is never
committed: after the last probe copy it to `work/<key>/<id>/verify-<id>.mjs`; the plan cites that
path and exec copies it back to re-verify. A probe that mutates shared state captures a baseline
first and restores it last, printing both. One probe per ticket, named for it; keep the variants.

**Deploy state.** Before believing a reopen, establish what the environment is running by whatever
the doc offers; if it offers nothing, write that down instead of assuming.

## Step 5 — Measure and reconcile

Run the probes yourself. **The measurement wins over the agents.** An agent report is a hypothesis
with citations; the probe is the referee. When a probe contradicts an agent, send that agent the
trace with `SendMessage` and make it close the gap — "recommend ONE, say what each alternative
breaks" — never spawn a new one or resolve it yourself. When a probe contradicts the ticket, that is
the finding, written in the ticket's own terms.

**A probe that produced one sample and stopped has measured nothing** — treat a suspiciously clean
result as a broken probe until proven otherwise. ≥ 5 reps for anything intermittent, every rep
printed. The layer you measured is part of the claim: "the API returns X" is not "the page shows X".

**Seed evidence is reused, not redone.** Per `## Evidence` entry: run one of its queries, compare one
number. Agrees and the base has not moved past its files → cite it by path with the spot-check number.
Disagrees or the base moved → re-measure in full and say which line went stale. An entry missing
query, numbers, date or base SHA is a claim and is measured as today.

## Step 6 — Write the plan in place

Same folder: `work/<key>/<id>/plan.md` (from an intake, write `plan.md` beside it). **English.**
Shape and order: `reference/plan-template.md` — follow it literally. The parts that carry judgement:

**Verdicts — `builder` and `audit`** are the two fields exec reads before dispatching. You assign them
because you measured and wrote the change; exec may raise either with a logged reason, never lower.
- `builder: cheap` only when the change alters no behaviour (docs, comments, a rename with no
  call-site semantics) — even when the exact code is written out (measured: 4 of 5 haiku (cheap) rows on
  behaviour changes came back for a fix round). `mid` otherwise. `strong` only from the forcing list.
- `audit: skip` only for the same no-behaviour set. `run` for everything else.
- **Forcing list → `builder: strong` + `audit: run`**, whatever the size: a path in the repo's
  sensitive list (`.claude/sensitive-paths.txt` or the profile's `sensitive_paths`); without one,
  authorization or roles, money or billing, a migration or the persistence schema, dedup/matching
  constants, an abstraction other units build on. Name the trigger in the row.
- Unsure `mid`/`strong` → `mid` unless the forcing list clearly hits; unsure `skip`/`run` → `run`.

**Waves** from the ownership table: no two units in one wave share a file or an interface; schema
files, routes, locale files and layout/nav components count as shared; **a unit with a migration sits
alone in its wave**; a consumer sits after its producer. One line per wave saying why it is a wave.

**Per unit, every block is required** — `Verified`, `Change`, `Every copy`, `Every writer`, `Traps`,
`Re-verify`, `Tests`, `Not in scope`, and `UI checklist` when the profile has `ui.visual_check`:
- `Every copy` is **the grep and what it found** — the exact command over the symbol, prop,
  predicate or literal the change touches, every hit at `file:line` with in scope / out of scope and
  one reason; a copy with the same defect is always in scope. It exists because "fix touched one
  branch, left the identical sibling broken" is the one QA failure that recurred across four tickets
  after prose rules already forbade it: a required section is a gate, prose is not.
- `Every writer` — for each column the change writes or starts reading differently, every other
  writer (jobs, callbacks, services, raw SQL, merges) at `file:line` with the guard it applies and
  whether the change carries it (measured: would have caught 4 of 17 post-PR defects).
- A trap the plan names gets a discriminating test that ships; every new test fails with its hunk
  reverted; re-verify asserts the ticket's symptoms 1:1 at the rendered layer.
- `UI checklist` — numbered, each item `URL → what must be visible`, on the profile's `ui.device`
  first when set; exec turns each into one browser check, so each item is checkable or says why not.
- A defect found while verifying is fixed in this plan as its own unit — never `Not in scope`, never a
  follow-up issue, never a deferred-work file. Only a fix in another team's repo is listed, as prose.

**Gates** come from the profile: `gates.commands` when set, else the `gates:` line of `## Inferred`
(what CI runs); `gates.cadence` (`wave` = full gates after every wave; default final); `gates.prepare`
after a migration. Exec's shipper runs them — the plan names only what a unit adds. Never a command
that resets, drops or seeds a dev database. Upstream mode: the commands
`upstream.md` § Rules to read finds replace the `gates:` line and are written into `## Gates` — exec passes them to every gate.

**Commit plan and PR title** follow the profile's convention (`git.commit_subject`,
`git.commit_unit`, `tracker.id_prefix`; else `[<ID>] <title>`); upstream mode: the format `upstream.md` § Rules to
read names, else plain `<title>`. The PR title lists every id that
**ships code**, ascending — a no-code ticket never enters it. Migrations commit last.

**Rulings** — every point you decided: `Ruling: <what> — <why> — <cost if wrong>`. An open decision
the seed left: `ingest-miss: <quoted line> → <the call> (rejected: <alternative>)`, reversible option
taken. Exec never halts on either.

**Finish line** — copy the paragraph from the template verbatim, filling branch and base. It is
standing authorization; a plan that ends at "ready to commit" is unfinished.

**Mirror.** The local `plan.md` is the truth. When the profile says the plan is mirrored (`notes.mirror: on`;
absent → the `## Inferred` notes line; never in upstream mode): the user's own issue → its
body (`gh issue edit <N> --body-file mirror.md`); anyone else's → one comment starting
`<!-- sin-flow:plan -->`, created once and edited in place
(`gh api -X PATCH repos/<slug>/issues/comments/<id> -F body=@mirror.md`). Over 60 000 bytes → the first
60 000 plus `continued in comments`, the rest as comments. Each new evidence file → one
`gh issue comment --body-file`, from its own `sin-flow-mirror` copy. An issue never points at a local file:
`sin-flow-mirror plan.md > mirror.md` drops every line that points at the notes, a worktree or evidence, and turns
any other path into its file name; the local file keeps everything.
A multi-ticket plan goes to every ticket's issue.

## Step 7 — Plan audit before hand-off

One `sin-flow:read-only-analyst` (`<mid>`) reads the written plan against the code in the worktree and
returns, with `file:line`: every seed unit without a section or a verdicts row; every row without
`builder`/`audit`; every owned file two units claim and neither flags shared; every wave that breaks
a dependency; every method, constant, keyword or i18n key a `Change` calls but neither creates nor
finds defined; every file a change touches that is not in its owned row; every value two sections
state differently; every unit missing `Every copy` or `Every writer`; every claim about existing
behaviour or data with no `file:line`, query or evidence path behind it. Fix each hit in the plan,
not in the check. Re-mirror if the plan changed.

## Step 8 — Disposition the no-code tickets, now

**Do it, do not ask** — only when the tracker is GitHub issues and not in upstream mode — there the disposition is the unit's row in the plan. Per no-code ticket:

- **comment the evidence** — the measurement verbatim, the mechanism, an executable re-verify, and
  any by-design behaviour that looks like a bug. Unproven reason it no longer reproduces → say it is
  unproven and list the candidates. Never a comment that reads as "QA was wrong".
- with `tracker.board` and `tracker.write.status: on`: if verified fixed or verified not-reproducible,
  move Status to the board's QA column. The Status field and option ids are in
  `~/.claude/sin-flow/profiles/<key>/board/rules.md`. A person blocks it: leave the status and write an
  `ingest-miss:` line. Upstream blocks it: unassign only with `tracker.write.assign: on`. In each case,
  name the upstream ticket and what unblocks it. A switch that is off or absent: no board write, and the
  plan row says `board: not written (switch off)`. **Never `Blocked`. Never close** — the close is not ours.

A local tracker: the disposition is the unit's row in the plan (`no code — <why>`).

## Step 9 — Report, in the chat language

≤ 12 lines, lead with **what the measurement changed**: verdict per ticket one line each; every
re-attributed root cause and to what; every ticket that left and where; traps found (a fix that
would have shipped a new bug); dispositions with links; locked-decision vs newer-comment pairs as
the only question; branch, PR title, and the `RULING_NEEDED` units if any. Calls you made are one
line each ("GH-N: BE gate goes too — FE-only measured as a 409"), never a question.

## Step 10 — Hand off to sin-flow:exec and end the turn

The coding stage starts **immediately** — no "shall I start?". **The launch is the last write to the
plan file.** A later change goes into the file, and one line tells the user to pass it to the running exec.

**`sin-flow:exec` always runs on `<strong>`**, never this session's model:

```
sin-flow-handoff --cwd <worktree> --name exec-<id> --model <strong> \
  --goal 'work/<key>/<id>/progress.md has "Plan <id>: shipped <PR-URL>", or "Plan <id>: blocked", or "handoff written".' \
  sin-flow:exec <absolute plan path>
```

Tell exec: work in that worktree; the plan's Finish line is standing authorization; plan, evidence
and harness stay in `work/` — never committed. Relay the `opened:` or printed line.

**Read the output and the exit code.** `opened: …` — exec runs in a new tab; never start a second one.
`session: unknown` — the tab is not confirmed: say so, name the row in `mode:`, never kill the started exec without the user's explicit yes.
`paste into a new terminal tab …` — no tab: relay the printed command in one line.
`continue in this session: …` — the user chose one session: invoke `sin-flow:exec` with that path here.
Non-zero — nothing started: `1` bad path, `2` bad option or `handoff:` setting, any other code is the
launcher's own (the command is printed after it) → give the user the exact command in one line; never
run `sin-flow:exec` in this session. Never diagnose a subprocess from an empty log: check `git status`, `git branch` and the child transcript first. A
silent mechanism is never grounds for a blocking question.

**`CTX GUARD` in a tool result** hands this plan to a fresh `sin-flow:plan`: let the in-flight dispatch finish, put every measured number in `evidence/<unit>.md` with its query, run `sin-flow-handoff --cwd <worktree> --name plan-<id> --model <strong> sin-flow:plan <absolute plan path> "continue: from Step <n>"`, read its output as above and end the turn. Never hand a half-measured plan to `sin-flow:exec`.

This stage writes no auto-memory: what the next run needs is in the plan and its evidence. A tool,
script, hook or hand-off that fails and needs a workaround is a flow defect: in the same turn append one
`open` row to `inbox.md` in the folder `${CLAUDE_PLUGIN_ROOT}/skills/learning/scripts/learning-dir.sh`
prints, with the date, `plan`, the exact error text, `file:line` when known and the workaround. A memory
entry is not the report.

## What this skill never does

- Edit application code or commit anything.
- File follow-up issues or write a deferred-work file.
- Put a no-code ticket's id in the PR title, or write a change for a ticket it did not measure.
- Let an agent's report stand where a probe contradicts it.
