---
name: ingest
description: 'Stage 0 of the flow (sin-flow:ingest → sin-flow:plan → sin-flow:exec) for one request or a few related ones in any repo with a flow profile. Takes one or more sources — an issue URL, `GH-N`, a Slack permalink (read only), a Rollbar item, the request in plain words, a screenshot, a log excerpt, a draft path, or `epic N` / a list of `N-M` story ids — reads it in full, verifies the claim in code, measures it read-only through the profile''s measurement route and sources, explains the mechanism with its evidence, locks decisions one question per turn, and ends in exactly one exit the repo''s channels enable: plan (seed → sin-flow:plan tab), hotfix (one-block plan → sin-flow:exec tab, PR without asking), data-fix (a support recipe a human runs), answer (a reply draft) or investigation (a written finding). Notes live in ~/.claude/sin-flow/work/<key>/<id>/, never in the repo. The one stage where the user is in the loop. Use when invoked as `/sin-flow:ingest [key] <source>` or when the user says "there''s a bug", "look into this ticket", "what is this ticket", "support writes", "look at the thread", "Rollbar is spamming", "ours or theirs?", "look at why", "make a fix", "take epic N into work".'
---

# sin-flow:ingest — the front for one request or a few related ones

Read, verify, measure, explain, lock — and only then pick the exit. Every downstream stage runs
unattended, so a product question not closed here becomes a `Ruling:` an agent takes on the user's
behalf.

```
sin-flow:ingest → sin-flow:plan → sin-flow:exec     (plan, epic — a seed the next stage verifies and plans)
sin-flow:ingest → sin-flow:exec                     (hotfix — a one-block plan, PR opened without asking)
sin-flow:ingest → a human / the user                (data-fix, answer, investigation — no code)
```

Repo facts never live in this file. Everything specific — base, tracker, gates, measurement route,
sources, integrations, consumers, sensitive paths, deviations — comes from the profile.

Chat with the user in the `chat_language` option (`sin-flow-profile user chat_language`), or in the language the user writes in when it is absent, whatever language the source is in. Headings and fixed phrases defined here are rendered in that language. Files, commits, PRs and issues are always English.

## Hard boundaries

- **Never write application code, never commit, never push.** Code is written by `sin-flow:exec` (and
  its implementers); commits and PRs by the `sin-flow:shipper` agent it dispatches.
- **Never execute anything that writes to a live system** — production, stage, a shared dev
  database. Measurement is read-only; a data-fix recipe is written to disk and run by a human.
- **Never run an app console, a runner or a one-off script against a live database** — not to
  measure, not to verify, not to "just check one record". A read-only client (`psql`, a `GET`) is
  the only way to a number.
- **Never print a credential.** Values from a source's env file reach a subprocess as `$VAR` only;
  never `cat`, `echo`, `env` or paste them; never print a connection URL.
- **Never post to Slack** — read tools only. Reply drafts are text in the chat; the user posts.
- **Never comment on an issue in a repo the user does not own without a "yes" for that specific
  comment.** Draft it, show it, wait. An earlier "go ahead" does not cover it. In upstream mode the rule is `reference/upstream.md` § Write policy instead.
- **Never write agent notes into a repo or worktree.**
  Seeds, plans, evidence, drafts and findings go to `~/.claude/sin-flow/work/<key>/<id>/`.
- **Never cut a branch or edit a tracked file in the shared checkout.** A writing exit makes its own
  worktree first; the main checkout stays on its branch for every other session.
- **Never run a downstream stage in this session.** A PreToolUse hook denies `sin-flow:plan`, `sin-flow:exec`
  and `sin-flow:implementer`.
- **Never invent a case.** A risk, failure mode or edge case exists only if it was measured, read at
  a named `file:line`, or said by a person. Otherwise the sentence is "not checked".
- **Never offer manual admin work as the fix,** and never propose an alternate look for a visual
  bug — measure it against the canonical design the repo or profile names.
- **A memory or repo convention that contradicts these boundaries does not override them.** Say the
  conflict out loud and let the user decide.
- **A workaround is an inbox row, not a memory.** A tool, script, hook or hand-off fails and you work
  around it → in the same turn append an `open` row to `inbox.md` in the folder
  `${CLAUDE_PLUGIN_ROOT}/skills/learning/scripts/learning-dir.sh` prints: next free number, date, stage, the
  exact error, `file:line` when known, the workaround. Memory keeps only the user's preferences; a memory that
  describes a flow defect moves to that row and is deleted.

## Arguments

```
/sin-flow:ingest [key] <issue-url | GH-N | slack-permalink | rollbar-url | "words" | screenshot | log | draft | epic N | N-M | <repo-url> "<words>" …>
```

Repeat form: `/sin-flow:ingest [key] <source> [<source> …]`. Sources can be in different repos.

**Start check, silent.** Run `sin-flow-profile validate` (≈ 1 s): profile found, required keys,
`gh auth status`, `work/` present. All green prints nothing and you go on. Otherwise:

| what failed | what this stage does |
|---|---|
| no profile for the repo | one line "no profile for `<key>` — running setup", run `sin-flow:setup`'s onboard in this session, then continue |
| `gh` not logged in, `jq` missing | stop on one line with the fix (`gh auth login`) |
| measurement route or a source unavailable now | continue; step 3 records "not measured: <source> unavailable (<reason>)" |
| `work/` not a git repo or no remote | one warning line, continue |

`key` is optional: without it the profile is resolved from `git remote get-url origin` of the main
checkout (the parent of `git rev-parse --path-format=absolute --git-common-dir`), so any worktree
maps to its repo. A GitHub issue or repo URL (or `owner/repo`) in the source decides the key — the profile whose `repo.slug` is that slug (`grep -lE "^repo\.slug:[[:space:]]*\"?<slug>\"?([[:space:]]|$)" ~/.claude/sin-flow/profiles/*/profile.md`, the match of `agents/shipper.md:30`); none → setup's onboard with that URL (§ Onboard step 0) — only when the cwd's
repo has no profile, or the slug is neither its `repo.slug` nor in that profile's `consumers`; a consumer slug keeps the cwd's key. With several sources, the first source decides the key. A source in another repo with a profile becomes a unit of that repo (`exits.md` § Ticket map). When the cwd is in no repo with a profile and no key or URL was given, ask in one line —
never guess. A problem in a tool with no URL and no matching cwd: ask in one line which repo; never guess. Read `profile.md` once (`sin-flow-profile <key> dir`); hand an agent only the section it needs.
Resolve `<mid>` and `<strong>` once for the resolved key's checkout (`sin-flow-profile <key> get repo.path`, `~` expanded; none → the cwd): `sin-flow-profile model mid <checkout>`, `sin-flow-profile model strong <checkout>`.

Then, whatever validate printed: `sin-flow-profile <key> get repo.fork` prints a slug → upstream mode: read
`reference/upstream.md` once; its § Rules to read run before step 1.

**Which sources and exits this repo has** follows from the profile — never from this file:

| enabled | when |
|---|---|
| sources: issue URL, `GH-N`, words, screenshot, log, draft | always (`GH-N` needs issues on the remote) |
| source: Slack permalink | the profile has `integrations.slack`, or the Slack read tools are connected |
| source: Rollbar item | the profile has `integrations.rollbar` (the MCP server name is its value) |
| source: `epic N`, `N-M …` | the profile has `tracker.id: N-M`; the backlog it reads is the one `## Tracker` names |
| exits: plan, hotfix, investigation | always |
| exits: data-fix, answer | a support channel exists — `integrations.slack` or `integrations.rollbar` — or the source is someone else's issue |

A source or exit the profile does not enable is said in one line with the profile key that would
enable it; then the nearest enabled one is used. How each source is read: `reference/sources.md`.

## Ids and the notes folder

Every run owns `~/.claude/sin-flow/work/<key>/<id>/` (`mkdir -p`). `<id>` is `gh-<N>` when issues are
the tracker, `<N-M>` or `epic-<N>` when `tracker.id: N-M`, `<slug>` when `tracker.kind: local` and
no id applies. With several units, each unit keeps its own folder, named by its own id. The first unit's id names only the spec and the run. Before the issue exists, `ingest-<slug>` stands in and is renamed once it does. The
folder holds `plan.md`, `evidence/`, `reply.md`, `investigation.md` — nothing of it is ever
`git add`ed. Status of a unit without a remote tracker lives in `status:` at the head of its
`plan.md`, nowhere else.

---

# The front — same on every exit

## 1. Read the source in full

**Latest comment first** — most issues are reopens, and the remaining defect is rarely what the body
says. A thread: every message, then every file; screenshots carry the account and the date nobody
typed. Name the last message you read, with its date, before the user asks "did you really read
all the messages?". A screenshot or quote: name what it shows — page, record, date — before touching a file.
Rollbar: the item title is a template; the occurrence is the fact, and its version matters (§ 5,
release gap).

**Then the repo's own reference for the area, never whole files.** The domain index or architecture
docs the repo's `CLAUDE.md` names, the backlog `## Tracker` names, and in upstream mode also the files of `reference/upstream.md` § Rules to read — grep for the area's terms, read
by line range. Then the nearest existing record on the same area: earlier seeds and findings in
`~/.claude/sin-flow/work/<key>/*/` (`grep -l`). A decision already locked there is quoted, not reopened.
Check memory for anything the user has rejected in this repo.

## 2. Verify in code

**The ticket text is a claim, not a fact; so are the user's words.** Find the code path and read it —
the condition, the query, the job, the component — at `file:line`. When the profile lists
`consumers`, open the consumer's checkout and read how it calls this repo and what it does with the
response: the consumer side often decides whether the bug is ours at all.

More than two files → fan out `sin-flow:read-only-analyst` agents (`<mid>`), one narrow question each, all in
one message, `file:line` in a reply of ≤ 40 lines; relay only its conclusion, never paste the report. An agent's report is a
reading, not a fact, until step 3 measures it or you read the lines yourself. Every claim carried
forward is tagged **measured**, **read at `file:line`** or **inferred**. A "no" in chat is a claim
too ("nothing to move", "the code is not the cause"): say what you read and what you did not read.

History while you are there: `gh pr list --repo <slug> --state merged --search "<keyword>"`,
`git log -S '<condition>' --oneline -- <file>`. A bug fixed once before is a regression or a release
gap; both change the verdict.

Who already works on each ticket source: `gh pr list --repo <slug> --state all --search "<n>"` and
`git ls-remote --heads origin | grep -iE '(^|/)<id>([/-]|$)'`, with `<id>` from § Ids. A merged PR
means the work is done, unless a newer comment reopens it. Another person's open PR or branch means
the ticket is theirs. Say who, and drop it from the units.

## 3. Measure

The route is the profile's and nothing else: `measure.doc` (a path, or `none`), `measure.preflight`,
the `## Measure` section and each `sources.<name>` (`kind`, `env_file`, `var`, `purpose`, `tunnel`,
`preflight`). Pick the source by `purpose`/`kind`; read `measure.doc` for the commands and the
rules it binds (roles, `LIMIT`, forbidden columns, how to close a tunnel).

- **Preflight: check, do not ask.** Run `measure.preflight` or the source's `preflight` silently. On
  failure with `tunnel` set: run the `tunnel` string verbatim as its own Bash call, nothing chained to
  it, then the preflight again. Still down: one line to the user naming the missing piece (VPN, SSO),
  then wait. Never "did you turn on the VPN?", and never a `!` command for the tunnel.
- **No route → no number.** `measure.doc: none`, or the source is down: write "not measured: <why>",
  every claim stays `inferred`, and the seed carries `RULING_NEEDED: measure before exec`.

Rules that bind every number:

- **A rate needs at least five repetitions, each printed.** One run of a query is a sample.
- **Every number carries its filter set** — the `WHERE`, the date range, the account — beside it.
- **Measure on the fixture the report names.** The report said account 81418 → measure 81418.
- **Read the notes on the record first**: a "reactivate" that was a deliberate cancellation two days
  earlier is a business decision, not a defect.
- **A failing spec is a task in the plan, never a run here.**

Write `work/<key>/<id>/evidence/YYYY-MM-DD_<slug>.md`: date, environment, base SHA, the source link,
each query verbatim, each result with its filter set, the repetition table for any rate, one line
per number saying what it is measured on. `sin-flow:plan` spot-checks this file instead of re-measuring,
so a number without its query is worthless there. **Skip only when nothing numeric is claimed** —
and say so in the first message: "not measured" is honest; a silent skip is not.

---

# Talk — the user is in the loop here

## Context discipline

- **No `ScheduleWakeup` polling.** Dispatch, end the turn; each agent's notification wakes you.
- **`CTX GUARD` in a tool result means hand off now:** verdict `plan`, seed with what is verified and
  every open point under `## Open decisions`, then the hand-off. A half-measured seed in
  `sin-flow:plan`'s hands beats a full one this session can no longer afford.

## 4. Talk to the user

The first message: what happens and why, the evidence for each half, and the recommended exit, in the
user's chat language. Mechanism first, questions after. It says what is true today, read from the code or measured.

**Then one question per turn.** Each question names the decision, two or three options, and your pick
with why. Product decisions only — contract, semantics, what a number counts, what the user
sees, a new column or param. Never names, file placement or spec structure: those are yours.

- **Look for the answer before you ask.** Before a question, check whether the code, the platform or
  the docs already answer it. If one does, record it as your decision with its `file:line` or link,
  and do not ask. Existing behaviour answers a question only when the request does not ask to change
  it.
- **Admin and low-usage internal surfaces get no questions and no design pass.** Reuse the closest
  existing pattern there and record it as your decision.
- **The user's one-word answers are decisions.** "yes", "no", "the first" — record each, dated, under
  `## Decisions (locked with the user, <date>)`; never re-ask it here or downstream.
- **A reversed decision → re-measure, then edit.** The numbers behind the old course are no longer
  the argument; run the query the new course needs, then rewrite.
- **"don't know" / "skip it" → `## Open decisions`**, with who decides and what it blocks. On
  `hotfix` you write the `Ruling:` yourself (your option and why); on `plan` and `epic`,
  `sin-flow:plan` writes it. Nobody downstream asks the user again.
- **"same issue"** → reuse that ticket; the PR carries the same id.

---

# Verdict — exactly one exit

## 5. Verdict and exit

State the exit in one line with its reason — «hotfix: one condition in one file, every decision
locked, no doc says otherwise» — **and run it in the same turn.** The exit, the owning epic and the
id are yours; the user's word changes a verdict, it does not start one, and it is never a hotfix criterion. The one wait: a question that would
change the verdict or the seed is still open — ask it, then act. After the tab opens, do not edit the
seed; send a new fact to the plan tab in one message: `SendMessage` to the tab's name. When `ListAgents` does
not list that name (the tab runs under another account), send it through the terminal the `handoff` option
names, then read that terminal once to confirm the tab took it.

| Exit | When | Produces | Hands to |
|---|---|---|---|
| `plan` | a defect or change with decisions to lock, or anything failing a `hotfix` criterion | tracker unit(s), own worktree each, seed `plan.md` + evidence | `sin-flow:plan` in a new tab |
| `hotfix` | all five hotfix criteria below | own worktree, one-block `plan.md` with `exit: hotfix` | `sin-flow:exec` in a new tab → PR, no question |
| `data-fix` | the code is right, specific rows are wrong | a recipe in the profile's `support/` + a reply draft | a human runs it |
| `answer` | nobody needs code | a reply draft, evidence linked | the user posts it |
| `investigation` | the mechanism is not proven, the behaviour is by design, or the fix belongs to work not yet taken | `work/<key>/<id>/investigation.md` | the user, and the exit the finding names |

**Hotfix criteria — all five, or it is `plan`:**

1. one condition, in one file (specs excepted), and the plan fits one block;
2. no product decision — the correct behaviour is already written in the ticket, a spec or the
   repo's docs, or every open point is ruled;
3. no migration, no new column, endpoint or param;
4. no sensitive path — `.claude/sensitive-paths.txt` (or the profile's `sensitive_paths`) and the
   sensitive section of the repo's `CLAUDE.md`; a sensitive area stops the skill before any plan;
5. no sibling unit it must wait for.

The exact procedure per exit — ticket map, worktree, seed and one-block plan format, mirror to the
issue (never in upstream mode), hand-off command and its exit codes, the support recipe, the reply draft, the finding — is
in `reference/exits.md`. Read the section for the chosen exit, and only it, before acting.

The `epic` source has its own front (scope from the backlog, one analyst per story, dispositions,
then one question per turn) and ends in the `plan` exit for the whole batch:
`reference/sources.md` § Epic.

### A release gap found on the way

When step 1 or 2 shows the fix already merged but the failing environment does not carry it —
Rollbar occurrences on a version older than the fix's merge, or `git branch -r --contains
<merge-sha>` missing the deployed branch — say so in the recommendation and name the release command
or skill the repo's `CLAUDE.md` names. **Do not run it.** A release is the user's move; the verdict
here is still one of the exits, usually `answer`.

---

## Report

Close every run with this block, whatever the exit. A run that cannot fill `verdict`, `evidence` and
`hand-off` is not finished.

```
source:    <issue URL | GH-N | permalink | Rollbar item | "words" | screenshot | epic N | N-M …>   (one value for each source)
profile:   <key>   repo: <slug>   base: <branch> @ <sha>
verdict:   plan | hotfix | data-fix | answer | investigation     (<one-line reason>, <date>)
evidence:  <path>  |  not measured — <reason>  |  skipped — <reason>
notes:     ~/.claude/sin-flow/work/<key>/<id>/ (<files written>)
ticket:    <id> (created | reused | local) [, <id> after <id> …]  |  none
worktree:  <path> (made | user's row reused)  |  n/a
hand-off:  <stage> tab opened: <name> (board: In progress | not moved) | command given | on <id>'s branch (same repo) | waits for the PR of <id> (other repo) | failed: exit <code>, command given, inbox #<n>  |  human: <who>  |  user posts  |  none
open:      <count> open decisions  |  RULING_NEEDED: measure before exec  |  release gap: <named>  |  nothing
```
