---
name: learning
description: 'Self-review stage of the flow (sin-flow:setup, sin-flow:sync, sin-flow:ingest, sin-flow:plan, sin-flow:exec, sin-flow:review) for every repo with a flow profile at once — one procedure over one run log, run outside any product repo; `self` reviews sin-flow:learning itself. Reads ~/.claude/sin-flow/runs.tsv filtered by repo key and stage, finds each transcript by session id under every ~/.claude/projects/*/ folder, dumps it with the scripts beside this file, fans the reading out to read-only subagents (one per transcript), consolidates one digest per stage — timeline, hand-off events, ranked failure modes tagged measured/read/inferred and split by repo, verbatim user quotes — and ends in diff proposals the user approves before anything is edited (with a backup). In author mode (the plugin loaded from the user''s own git checkout) proposals may change the plugin itself; in user mode they change only user.md and the repo profiles, and flow-layer ideas are written down for the plugin author. `--dry-run` lists the selected runs and stops. Use when invoked as `/sin-flow:learning [--dry-run] [repo-key|all|self] [stage] [n] [question]`, when the launch hook opens it because undigested exec runs have piled up, or when the user asks why a flow session behaved as it did — "why did exec-N not hand off", "what went wrong in plan-N", "review the flow runs".'
---

# sin-flow:learning

Chat with the user in `chat_language` from `~/.claude/sin-flow/user.md`, or in the language the user writes in
when it is absent. Headings and fixed phrases are rendered in that language. Files are English.

The golden rule: every finding and every proposal first answers "what problem does this solve?". The flow
exists so that a task closes with no user touch between ingest and the result, and the code is right without
their review — the user looks at the result, not at the PR, and gives the next task. Every question is closed
at ingest; plan and exec ask the user nothing. This stage measures the flow on two numbers:

- **user touches per task**;
- **post-PR defects** — a later human/bot comment that the flow's final review (the pipeline in
  `${CLAUDE_PLUGIN_ROOT}/skills/review/reference/`) did not raise and that reproduced: a failing spec, a measured row, or a fix the user
  ordered. A comment that did not reproduce is not a defect: it counts in neither number, and no lens is tuned
  to raise it.

A skill line a session broke at no cost to either number is not a finding — at most a Deletions candidate.

Learning improves the user's workflow: it finds what to automate, what the user keeps doing by hand, what their
sessions show they need. Every finding names its **layer** first — the user's files (`user.md`, their copies of the
`examples/`, `profiles/<key>/`) hold how the flow works for this user; the plugin holds the mechanism and the
defaults every user starts from. A habit of one user never becomes a plugin rule. Only in author mode does a finding
also ask whether the mechanism itself failed — and then it goes to the plugin, in its own apply script.

One procedure covers every repo. The repo is a column, not a separate flow: a failure mode seen in two or
more repos is a sin-flow:* skill problem; a mode seen in one repo only is first a profile problem.

## Arguments

`/sin-flow:learning [--dry-run] [repo-key|all|self] [stage] [n] [question…]`

- A leading absolute path (the launcher's cwd anchor) is skipped.
- `repo-key` — a folder name under `~/.claude/sin-flow/profiles/`, or `?` for rows the run log could not place.
  `all`, or no key, means every repo. A first token that is a stage name, not a key, means `all` with that stage.
- `self` — reviews sin-flow:learning itself (section **Self** below); stage and `n` are not used.
- `stage` — a value of the run log's `stage` column: `setup`, `sync`, `ingest`, `epic`, `plan`, `exec`,
  `review`, then the rest the log carries (`build`, `commit`, …). That is also the full-run order.
- `n` — the run log's `n` column. Naming `n` overrides the coverage exclusion: a re-read is the user's call.
- Anything after is the user's question, answered first in the digest.
- `--dry-run` — run `scripts/select-runs.sh --dry-run <key> [stage] [n]`, print its output as it is
  (one line per run: repo, stage, n, sid8, date, skill, undigested yes/no; then listed/undigested per repo),
  and stop. Nothing is dumped, dispatched or written.

## Inputs

`S=${CLAUDE_PLUGIN_ROOT}/skills/learning/scripts`. `LD` below is the learning folder that `$S/learning-dir.sh`
prints: `learning_dir` from `~/.claude/sin-flow/user.md`, default `~/.claude/sin-flow/learning`. The digests, the
inbox, the ledger, the backups and `proposals-for-author.md` live there; nothing of the user's goes into the
plugin.

| what | where |
|---|---|
| run log — one row per finished session, every repo | `~/.claude/sin-flow/runs.tsv` (`FLOW_RUNS_LOG` overrides it): `date repo stage n session_id account model start end turns user_turns ctx_first_k ctx_last_k handoff limit_hits skill`. `skill` is the slash command that started the session — `sin-flow:*` for the unified flow, older names for runs before it — so old and new runs can be told apart |
| transcripts | `~/.claude/projects/*/<session_id>.jsonl` — every project folder, worktree and workspace folders included; `scripts/dump-session.sh` finds them with `find -mindepth 2 -maxdepth 2`, never `ls` on one folder |
| dump scripts | beside this file, `scripts/`: `dump.sh` (event lines, a `RESULT:` line per hand-off launch), `stats.sh`, `ctx.sh` (context per turn), `guards.sh` (CTX/LIMIT GUARD lines exist only here), `per-agent.sh` (one line per subagent), `dump-session.sh` (all of them for one session), `select-runs.sh`, `learning-dir.sh`, `mode.sh` |
| status-line state at the last turn | `~/.claude/state/sessions/<session_id>.json` — `used_pct`, `limit_5h`, `config_home` — when the user's status line writes it |
| repo profiles | `~/.claude/sin-flow/profiles/<key>/profile.md` |
| the stages under review | `${CLAUDE_PLUGIN_ROOT}/skills/<stage>/SKILL.md`; a stage with no sin-flow:* skill yet is reviewed against the skill in its `skill` column, and its proposals target the sin-flow:* skill that replaces it |
| agents and hooks the stages run | `${CLAUDE_PLUGIN_ROOT}/agents/{shipper,implementer,reviewer,read-only-analyst}.md`, `${CLAUDE_PLUGIN_ROOT}/hooks/scripts/{stage,work-commit,ctx-guard,exec-guard}.sh`, the hook that writes the run log (`grep -l 'runs.tsv' ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/*.sh`), `sin-flow-handoff` and the launcher `handoff:` in `user.md` names, if any |
| the review pipeline | `${CLAUDE_PLUGIN_ROOT}/skills/review/reference/{pipeline.md,lenses/,sources.lock.tsv}`, team rules in `~/.claude/sin-flow/profiles/<key>/review-team.md` (mined from the profile's `review.team_sources`), review files in `reviews_dir` from `user.md` (default `~/.claude/sin-flow/reviews/`) |
| what earlier runs already covered | the header of every `LD/*/*.md` — digests of older flows included |
| ideas from outside the runs | `LD/inbox.md`. Sessions outside learning never edit a skill; they append a row here |
| stage question lists and digest forms | `reference/questions.md` beside this file |

Product repo checkouts are out of bounds, with one exception: the progress ledger a covered session wrote
(`<sid8>.ledger-paths`), read-only. A claim that needs anything else in a repo says "not checked" and names
the path a session in that repo should check.

## Who starts a run

The user, by hand, or `${CLAUDE_PLUGIN_ROOT}/hooks/scripts/learning-launch.sh` at the end of a `sin-flow:exec` session:
when the run log holds `learning_runs` (default 10) undigested exec rows, no `claude -n learning` process runs and
nothing was launched since `LD/ledger.md` last changed, it runs `sin-flow-handoff --cwd <learning_cwd> --name learning
sin-flow:learning <path> all` and appends one line to `LD/launch.log`. The leading path is handled as in
Arguments.

## Setup — pick the rows

Resolve `<strong>` and `<mid>` once with `sin-flow-profile model strong|mid` from this cwd; no repo profile here, so they come from `user.md` or the defaults.

Covered rule — `scripts/covered-sids.sh`, the same one the launch hook counts with: a run is **undigested** when its
`session_id[:8]` is on no `Sessions covered:` block (that line and its continuation lines, up to a blank line or
the next field) in the header (the lines above the first `## `) of any `LD/*/*.md`. A session the header
names anywhere else — left out, not read, not in the TSV yet — stays undigested. Rows appended after Setup belong
to the next run.

```
LD=$($S/learning-dir.sh)
MODE=$($S/mode.sh)
$S/select-runs.sh <key|all> [stage] [n] > <workspace>/dumps/rows.tsv
```

The script keeps the header, drops a repeated `session_id` (one session is read once, whatever repo or stage a
duplicate row gave it) and drops covered rows unless `n` is given.

- No stage given → a **full run**: every stage with undigested rows, in the full-run order, one digest per
  stage. When more than one stage is due, each stage goes to one consolidator subagent (`general-purpose`,
  `<strong>`) that runs Setup → Fan-out → Consolidate for that stage with at most 3 readers in flight, writes its
  digest, and returns only the ranked modes and the proposals (≤ 300 words). The main thread keeps its context
  for Proposals and Close the loop across all stages. At most 4 consolidators in flight; the next starts when
  one returns. A stage with fewer than 3 undigested rows is skipped and named in the ledger entry.
  The last consolidator runs **self** (section Self) when 3 or more learning runs are undigested; it reads earlier
  learning runs only, never this one. Plan the reader caps so self keeps its consolidator and readers inside the
  20-subagent cap.
- A question about one item of a stage list (the final message, a hand-off) → readers answer that item and
  items 3, 4, 6, and the digest names its sessions in §0, not in the header.
- Workspace: `LD/<YYYY-MM-DD>/flow-<stage>/` with `dumps/` and `readers/`. Same day, second run →
  same folder, digest `flow-<stage>-2.md`.

For every selected session, one Bash call, output to files only:

```
$S/dump-session.sh <session_id> LD/<date>/flow-<stage>/dumps
```

It writes `<sid8>.{txt,ctx,guards,agents.tsv,long.txt,errors,misses,ledger-paths}`, appends to `stats.txt`
and `transcripts.tsv`, and a session with no transcript to `missing.txt`. `.misses` holds every
`ingest-miss:` line the session itself wrote (decoded from its tool inputs — never the skill text it loaded).

The main thread reads `stats.txt`, `rows.tsv`, `missing.txt` and `wc -c dumps/*.txt`. A row in `missing.txt`
is named in the digest header as not read.

## Fan-out — one reader per transcript

`sin-flow:read-only-analyst` on `<mid>`, at most 3 in flight. One dump per reader; dumps under 10 KB are grouped into one reader.
Readers cannot write files: the dispatcher saves each report to `readers/<sid8>.md`. Each prompt carries:

- the paths (`.txt`, `.ctx`, `.guards`, `.long.txt` — every assistant text ≥ 300 chars, unclipped;
  `.agents.tsv` — one line per subagent with its model and cost; `.errors` — every failed or denied tool call;
  `.misses`; `.ledger-paths`; `rows.tsv`) and the dump format line (`MM-DD HH:MM KIND: text`; KIND = CMD, USER,
  USER(sys), USER(queued), ASSISTANT, TOOL, RESULT, SYSTEM);
- the session's row: repo, skill, `n`, account, and where it sits in its chain (n-th of N);
- the repo's profile path, for a question the profile answers (gates, tracker, team or solo);
- the user's question, if any, as the last heading;
- the fixed question list for the stage from `reference/questions.md`; items 3, 4 and 6 of the exec list go
  into every stage's list;
- the rule: every claim tagged `measured` with the HH:MM it rests on, or `inferred`; anything the dump does
  not show is "not checked"; word budget 700 (220 per session for the grouped ones);
- "Read the dump fully. Do not open anything else except the files named here. Do not look into a product
  repo, except the ledger paths in `.ledger-paths`. Return markdown text; you cannot write files." — plus the
  exceptions the stage list names (a review file, read-only `gh pr view` / `gh api` on that PR).

## Consolidate — the digest

`LD/<date>/flow-<stage>.md`, in the stage's digest form from `reference/questions.md`. The main
thread (or the stage's consolidator) writes it from the readers' reports; it never opens a `.jsonl`, and
re-opens a dump only when two readers contradict each other on the same minute.

Header, always, before the first `## `:

- stage, repo filter, `n`, dates, and the mode (`author` or `user`);
- `Sessions covered:` and the session ids covered — full ids or 8-char prefixes, one per covered row (the next run
  excludes these); a session left out or not read is named on another line, never in this block;
- the filter: the exact `select-runs.sh` line and the row count it returned;
- "Context figures are measured (`input+cache_read+cache_creation` per assistant turn); window 1M";
- the size of `skills/<stage>/SKILL.md` — lines and KB — with the delta since the previous digest of that
  stage. Every line of a skill is paid on every request; growth is a finding.

Body:

0. **The user's question**, if they asked one — ≤ 6 sentences, each tagged, before anything else.
0b. **Effect check** — for every proposal applied by an earlier digest of this stage (digests of older flows
   included), the metric it named: shifted as expected / not shifted / moved the wrong
   way → propose the revert. A bad learning run must not silently shape every run after it.
0c. **Inbox** — every open `inbox.md` row for this stage: what problem it removes in the two numbers, what
   these sessions show for or against it, and the verdict — a proposal now, or wait (and for what).
1. Timeline table — one row per session, with `repo` and `skill` columns, then the stage's columns.
2. Hand-off / guard table — every hand-off and guard event across the chain, in time order, with ctx and the
   outcome.
3. User turns — count per class per session; verbatim quotes of every class e and g turn, with session and
   HH:MM.
4. The stage-specific sections of the digest form.
5. **Recurring failure modes, ranked** — each with a count (`k/N sessions`), the repos it appeared in, a tag
   (`measured`, `read` with `file:line` in the skill, hook or profile, `inferred`), and one quote or one HH:MM
   line. A mode that rests on a single session says `1/N`, is not generalised, and goes to a **Watch** list at
   the end of this section — not to a proposal. A mode seen only in old-skill runs whose sin-flow:* successor no
   longer has the line it rests on is listed as `gone in sin-flow:<stage>` and proposes nothing.
6. **Diff proposals** — see below. Nothing in sections 0–5 is a proposal; nothing in 6 lacks a pointer back to
   0–5.

## Mode — author or user

`$S/mode.sh` prints the mode once per run; the digest header records it.

- **author** — the plugin is loaded in place from a git checkout the user can commit to: `${CLAUDE_PLUGIN_ROOT}`
  is not under a `plugins/cache/` folder and is inside a git work tree with a writable git dir. Proposals may
  target the flow layer — `skills/`, `agents/`, `hooks/`, `bin/` of that checkout — as well as `user.md` and
  `profiles/<key>/`. After the user's "yes", `apply-plugin.sh` edits the checkout; then tell the user to run
  `/reload-plugins`. Committing is the user's step: never commit, push or open a PR in the checkout.
- **user** — the plugin runs from the plugin cache, which an update overwrites. Proposals are applied only to
  `~/.claude/sin-flow/user.md` and `~/.claude/sin-flow/profiles/<key>/`, after a "yes". A proposal whose target is
  in the flow layer is never applied: it is appended to `LD/proposals-for-author.md` as one block per proposal,
  written so the plugin author can act on it without the digest — `## <YYYY-MM-DD> — <target relative to the
  plugin root>`, the plugin version (`basename ${CLAUDE_PLUGIN_ROOT}`), the problem in the two numbers, the
  evidence as counts with their filter set and repo keys, **now**, **proposed** and **effect** as below. These
  blocks need no approval: they change nothing that runs. The chat report names the file and how many blocks
  were added.

## Proposals — diffs the user approves

A proposal needs a mode counted on ≥ 2 sessions, or the user's explicit ask — an open inbox row is one. When
a hook, script or check can carry the fix, propose that first and a text line second — a hook that denies or
stops still needs its live probe. A mode in one repo only targets that repo's profile first. A proposal never
stops or blocks a stage to enforce a precondition the flow could set up itself: it fixes how the stage is opened,
and a stage in the wrong state keeps working — the user touches the flow only at the start.

Every run also carries one **Deletions** entry: lines of the stage skill that no covered session followed,
lines a hook or another line contradicts, lines a newer rule supersedes, and pairs of lines that say the same
thing, merged into one — with the same evidence as an addition. A run that adds and never deletes is
incomplete. When the digest header shows the stage skill grew in each of the last 3 digests of that stage, the
run also carries a **Rewrite** proposal: the whole skill written from scratch in
`LD/<date>/flow-<stage>-rewrite.md`, keeping only what a covered session followed or a hook enforces;
the user approves it as a whole.

One proposal per numbered entry, each with:

- **layer** — `user` (`~/.claude/sin-flow/user.md`, the user's copy of an `examples/` script), `profile`
  (`~/.claude/sin-flow/profiles/<key>/`) or `plugin` (the mechanism, for every user). A finding that is one user's
  habit or preference is `user` or `profile`, whatever mode the run is in;
- **target** — `${CLAUDE_PLUGIN_ROOT}/skills/<stage>/SKILL.md:<line>`, an agent `${CLAUDE_PLUGIN_ROOT}/agents/<name>.md:<line>`,
  a lens `${CLAUDE_PLUGIN_ROOT}/skills/review/reference/lenses/<lens>.md:<line>`, a hook path, `${CLAUDE_PLUGIN_ROOT}/bin/…`,
  a profile `~/.claude/sin-flow/profiles/<key>/profile.md`, `~/.claude/sin-flow/user.md`, or the user's copy of an
  `examples/` script under `~/.claude/sin-flow/`. Never another file;
- **now** — the current text, verbatim, ≤ 6 lines;
- **proposed** — the replacement, verbatim;
- **evidence** — the digest section and the count it rests on, with the repos;
- **effect** — the run-log column or digest count that must move, which way, within how many runs of the
  stage; the next digest's Effect check reads this line;
- **blocking?** — `no` for text, thresholds, ordering; `yes` for anything that denies a tool call, exits
  non-zero, or stops a session. A `yes` proposal also names the live probe that must run first (which repo,
  which command, what output proves it does not block the wrong caller).

Every proposal the mode lets this run apply is a file before the chat report: the whole proposed copy of each
target in `LD/<date>/flow-<stage>/proposed/` (all approved together), `patches.diff`, `targets.tsv` (target path,
`shasum -a 256` of the live file when the copy was made), and the apply scripts — `apply-user.sh` for the `user`
and `profile` layers, `apply-plugin.sh` for the `plugin` layer, approved and run separately — each of which:

1. checks every target's live sha against `targets.tsv` and stops, changing nothing, when one differs — another
   session edited it; rebase the copy onto the live file and rewrite the row;
2. for each target copies it to `LD/backups/<date>/<target path below its root>` first — the root is
   `${CLAUDE_PLUGIN_ROOT}` or `~/.claude/sin-flow`; `mkdir -p` the folder, and a second edit the same day reuses
   the backup — then copies the proposed file over it and checks it with `cmp`.

When two stages propose to the same file, the copies are merged into one before the apply scripts are written.
Nothing is edited before the user's approval — "do it" or "go" in the launch request approves the run, not a
diff they have not seen.

The user approves by number, or all at once — "all", "yes", "apply" or "your call", in any language, said to the
list approve every number in it. Silence, "not now" or a question is not approval. Then:

1. A partial approval, or a scope change in their line, is made in the copies first.
2. `bash <abs path>/apply-user.sh`, then `apply-plugin.sh` in author mode, once each — never piecemeal edits of a live file. Denied → stop and give the user
   the one line to run: `! bash <abs path>/apply-<layer>.sh`.
3. A `⚠ CORRECTION` note in the digest's proposal entry if the applied text differs from the proposed one,
   and why.
4. Author mode, a flow-layer target applied → tell the user to run `/reload-plugins` and that the commit is
   theirs.

A proposal the user declined stays in the digest marked `declined <date>` — the next run must not re-propose it
unless new rows contradict the decline.

## Self — reviewing sin-flow:learning

`/sin-flow:learning self`. No hook launches it: the user runs it when ideas for learning have piled up, or asks.
One stage, **self**. This section replaces Setup and Fan-out; Consolidate, Mode, Proposals, Close the loop,
Chat and Boundaries hold.

- **Rows** — the learning runs no earlier `LD/*/self.md` header lists: the `## Learning <date> — …`
  entries in `LD/ledger.md` and the digests they name, plus `select-runs.sh self` (run-log rows whose
  `skill` ends in `learning`). Fewer than 3 → stop and say so.
- **Under review** — this file, `reference/questions.md`, `scripts/`, the launch hook `hooks/scripts/learning-launch.sh`.
- **Ideas** — `inbox.md` rows with flow `learning`.
- **Sessions** — the session id the ledger entry names; dumped with `dump-session.sh` like any other.
- **Workspace** `LD/<date>/self/`; digest `LD/<date>/self.md`.
- **Readers** — one `sin-flow:read-only-analyst` on `<mid>` per learning run: its digest, its ledger entry, its session dump, with
  the self question list from `reference/questions.md`.
- **Numbers** — instead of user touches and post-PR defects: share of proposals approved, share reverted,
  lines deleted vs added per run, growth of the skills it reviews, user corrections about learning per run.
  Proposals target only the files under review.

## Close the loop

- Append to `LD/ledger.md` under `## Learning <date> — flow-<stage>` (or `self`): this session's id (8
  chars), the repo filter, the mode, rows covered, the digest path, the ranked modes in one line each, proposals
  applied (with backup paths), declined, and written to `proposals-for-author.md`. The ledger is the memory of
  this stage; nothing goes into auto-memory.
- In `inbox.md`, mark every row this run turned into a proposal: `proposed <digest>`, then `applied <date>`,
  `declined <date>` or `for author <date>` — and append one row for flow `learning`: what in this skill got in
  the way this run, or "nothing". That row is what `/sin-flow:learning self` reads.
- The run ends with an empty `inbox.md` table. Every closed row (`applied`, `declined`, `closed`) moves to
  `inbox-archive.md` beside it. Each row still open goes to the user one at a time, with your pick, until it is
  closed or archived. A new row takes the next number after the highest in both files.
- `CTX GUARD` in a tool result: let the in-flight readers finish, write the digest and the ledger entry for the sessions
  they covered, then tell the user in one line to run `/sin-flow:learning <same mode>` in a new session — rows on no
  `Sessions covered:` block are picked up there — and stop.
- If a reader could not answer an item, the digest says so under that item and the ledger entry names the
  missing input — a new run-log column, a new dump field — as a proposal for this skill, `scripts/` or the
  run-log hook, not as a fact.

## Chat — the user's headings

The report in chat is plain language: a signature line with what was asked, then these headings, rendered in
the chat language, in this order, and then it stops:

- **WHAT HAPPENED** — one sentence, cause → effect: the mechanism, an arrow, then what the user saw.
- **EVIDENCE** — the two numbers (user touches, post-PR defects) for the covered sessions, split by repo, and
  the `file:line` behind the cause, ≤ 3 lines.
- **WHAT I PROPOSE** — two lists, «your settings» then «the plugin, for everyone», ≤ 6 lines in all, «how it works now → how it will be», one line per thing the user of
  the flow experiences, with every proposal that changes it folded in; plain words, no proposal numbers, no
  identifiers. User mode: one more line naming `proposals-for-author.md` and the blocks added.
- **FINAL MESSAGE** — one covered exec session's final message, its `===` block copied whole from
  `<sid8>.long.txt` to `LD/<date>/flow-<stage>/final-message-<sid8>.md` and never quoted in chat: its lines
  and words against the Final message shape in `${CLAUDE_PLUGIN_ROOT}/skills/exec/SKILL.md`, the PR bodies' word counts (> 200 is a
  finding), the path, and one question: ok / too long / something missing? The answer is a proposal to
  sin-flow:exec's final step.

Whole report ≤ 15 lines. Counts carry their filter set in the digest, not in chat.

## Boundaries

- Runs outside every product repo.
- Never writes to auto-memory, Slack, GitHub, a ticket or a product repo.
- Never edits a skill, agent, hook, profile, `user.md` or launcher without the user's approval (numbers or
  "all") and a backup made first; in user mode never edits the flow layer at all.
- Never commits or pushes the plugin checkout.
- Never turns on a hook that can deny or stop a session without the live probe named in the proposal having
  run.
- Never reports a reader's paragraph back verbatim in chat — the digest holds it; chat holds the conclusion
  and the path.

## Known issues

Open, not fixed by this procedure:

- The harness caps one launch at 20 subagents in total: a full run's consolidators can be refused their
  readers (inbox #39 item 2).
- `scripts/dump.sh` clips TOOL lines and `exit=` RESULT lines at 140–300 characters, so long worktree paths
  are cut (inbox #39 item 4).
- Another session can edit a target skill mid-run; the apply scripts refuse on a changed sha, but nothing stops the
  edit itself and the copies must be rebased by hand (inbox #39 item 7).
- The auto-mode classifier blocks even a read-only probe run of an apply script (inbox #39 item 8).
