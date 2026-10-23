---
name: learning
description: 'Self-review stage of the flow (sin-flow:setup, sin-flow:sync, sin-flow:ingest, sin-flow:plan, sin-flow:exec, sin-flow:review) for every repo with a flow profile at once. One procedure over one run log, run outside any product repo. `self` reviews sin-flow:learning itself. Reads ~/.claude/sin-flow/runs.tsv filtered by repo key and stage, finds each transcript by session id under every ~/.claude/projects/*/ folder, dumps it with the scripts beside this file, and fans the reading out to read-only subagents (one per transcript). Consolidates one digest per stage: timeline, hand-off events, ranked failure modes tagged measured/read/inferred and split by repo, verbatim user quotes. Ends in diff proposals the user approves before anything is edited (with a backup). In author mode (the plugin loaded from the user''s own git checkout) proposals may change the plugin itself, and the applied changes ship as one PR. In user mode they change only the plugin options and the repo profiles, and flow-layer ideas are written down for the plugin author. `--dry-run` lists the selected runs and stops. Use when invoked as `/sin-flow:learning [--dry-run] [repo-key|all|self] [stage] [n] [question]`, when the launch hook opens it because undigested exec runs have piled up, or when the user asks why a flow session behaved as it did: "why did exec-N not hand off", "what went wrong in plan-N", "review the flow runs".'
---

# sin-flow:learning

Chat with the user in the `chat_language` option (`sin-flow-profile user chat_language`). When it is absent, use the language the user
writes in. Headings and fixed phrases are rendered in that language. Files are English.

## The golden rule

Every finding and proposal first answers "what problem does this solve?". The flow exists so that a task closes with
no user touch between ingest and the result, and the code is right without their review. The user looks at the result,
not at the PR, a plan or a digest, and gives the next task. Ingest closes every question. Plan and exec ask the user
nothing. This stage measures the flow on two numbers:

- **user touches per task**.
- **post-PR defects**: a later human or bot comment that reproduced (a failing spec, a measured row, or a fix the user
  ordered) and that the final review (`${CLAUDE_PLUGIN_ROOT}/skills/review/reference/`) did not raise. A comment that
  did not reproduce counts in neither number, and no lens is tuned to raise it. A skill line that a session broke at
  no cost to either number is not a finding. It is at most a Deletions candidate.

Every finding names its **layer** first, by the rules in `${CLAUDE_PLUGIN_ROOT}/ARCHITECTURE.md`. The user's settings (the sin-flow plugin options, their copies of `examples/`, `profiles/<key>/`)
hold how the flow works for this user. The plugin holds the mechanism and the defaults that every user starts from. A
habit of one user never becomes a plugin rule. Only in author mode does a finding also ask whether the mechanism
itself failed. Then it goes to the plugin, in its own apply script. The repo is a column, not a separate flow. A
failure mode seen in two or more repos is a sin-flow:* skill problem. A mode seen in one repo only is first a profile
problem.

## Arguments

`/sin-flow:learning [--dry-run] [repo-key|all|self] [stage] [n] [question…]`

- A leading absolute path (the launcher's cwd anchor) is skipped.
- `repo-key`: a folder name under `~/.claude/sin-flow/profiles/`, or `?` for rows the run log could not place. `all`,
  or no key, means every repo. When the first token is a stage name, the key is `all`.
- `self`: reviews sin-flow:learning itself (section **Self**).
- `stage`: a value of the run log's `stage` column: `setup`, `sync`, `ingest`, `epic`, `plan`, `exec`, `review`, then
  the rest the log carries (`build`, `commit`, …). That is also the full-run order.
- `n`: the run log's `n` column. A named `n` overrides the coverage exclusion. A re-read is the user's call.
- Anything after is the user's question, answered first in the digest. A question about one item of a stage list (the
  final message, a hand-off): readers answer that item and items 3, 4 and 6, and the digest names its sessions in §0.
- `--dry-run`: run `scripts/select-runs.sh --dry-run <key> [stage] [n]`, print its output, and stop.

## Inputs

`S=${CLAUDE_PLUGIN_ROOT}/skills/learning/scripts`. `LD` is the folder that `$S/learning-dir.sh` prints (the `learning_dir`
option, default `~/.claude/sin-flow/learning`). Every file of this stage lives there, never in the plugin.

| what | where |
|---|---|
| run log | `~/.claude/sin-flow/runs.tsv` (`FLOW_RUNS_LOG` overrides it): `date repo stage n session_id account model start end turns user_turns ctx_first_k ctx_last_k handoff limit_hits skill`. `skill` is the slash command that started the session, so old and new runs can be told apart |
| transcripts | `~/.claude/projects/*/<session_id>.jsonl` in every project folder. `dump-session.sh` finds them with `find -mindepth 2 -maxdepth 2`, never `ls` on one folder |
| scripts | `$S/`: `dump.sh`, `stats.sh`, `ctx.sh`, `guards.sh` (CTX/LIMIT GUARD lines exist only here), `per-agent.sh`, `dump-session.sh`, `select-runs.sh`, `covered-sids.sh`, `learning-dir.sh`, `mode.sh` |
| status-line state | `~/.claude/state/sessions/<session_id>.json`: `used_pct`, `limit_5h`, `config_home`, when a status line writes it (the sin-flow wrapper with `limit_guard: on`, or the user's own) |
| repo profiles | `~/.claude/sin-flow/profiles/<key>/profile.md` |
| stages under review | `${CLAUDE_PLUGIN_ROOT}/skills/<stage>/SKILL.md`. A stage with no sin-flow:* skill yet is read against the skill in its `skill` column, and its proposals target the sin-flow:* skill that replaces it |
| agents and hooks | `${CLAUDE_PLUGIN_ROOT}/agents/{shipper,implementer,reviewer,read-only-analyst}.md`, `${CLAUDE_PLUGIN_ROOT}/hooks/scripts/{stage,work-commit,ctx-guard,exec-guard}.sh`, the run-log hook (`grep -l 'runs.tsv' ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/*.sh`), `sin-flow-handoff` and the launcher that the `handoff` option names |
| review pipeline | `${CLAUDE_PLUGIN_ROOT}/skills/review/reference/{pipeline.md,lenses/,sources.lock.tsv}`, `~/.claude/sin-flow/profiles/<key>/review-team.md`, review files in the `reviews_dir` option (default `~/.claude/sin-flow/reviews/`) |
| ideas from outside the runs | `LD/inbox.md`. Sessions outside learning never edit a skill. They append a row here |

## Setup: pick the rows

**Who starts a run**: the user, or `${CLAUDE_PLUGIN_ROOT}/hooks/scripts/learning-launch.sh` at the end of a
`sin-flow:exec` session. The hook launches when `learning_runs` (default 10) exec rows are undigested, no `claude -n
learning` process runs, and nothing was launched since `LD/ledger.md` last changed. It runs `sin-flow-handoff --cwd
<learning_cwd> --name learning sin-flow:learning <path> all` and appends one line to `LD/launch.log`. Resolve
`<strong>` and `<mid>` once with `sin-flow-profile model strong|mid` from this cwd.

A run is **undigested** when `scripts/covered-sids.sh` does not find its `session_id[:8]`. The script reads the
`Sessions covered:` block (that line and its continuation lines, up to a blank line or the next field) in the header
(the lines above the first `## `) of every `LD/*/*.md`. A session that a header names anywhere else stays undigested.
The launch hook counts with the same script. Rows appended after Setup belong to the next run.

```
LD=$($S/learning-dir.sh)
MODE=$($S/mode.sh)
$S/select-runs.sh <key|all> [stage] [n] > <workspace>/dumps/rows.tsv
```

`select-runs.sh` keeps the header, keeps one row per session, and drops covered rows unless `n` is given.

- **No stage given: a full run.** One pass covers every stage with undigested rows and also **self**. Each stage goes
  to one consolidator subagent (`general-purpose`, `<strong>`). It runs Setup, Fan-out and Consolidate for that stage
  with at most 3 readers in flight, writes its digest, and returns only the ranked modes and the proposals (≤ 300
  words). At most 4 consolidators are in flight. A stage with fewer than 3 undigested rows is skipped and named in the
  ledger entry. The last consolidator runs **self** when 3 or more learning runs are undigested. It reads earlier
  learning runs only, never this one. Plan the reader counts so that self fits inside the 20-subagent cap.
- **Workspace**: `LD/<YYYY-MM-DD>/flow-<stage>/` with `dumps/` and `readers/`. A second run on the same day uses the
  workspace `flow-<stage>-2/` and writes `flow-<stage>-2.md`. Every file inside the workspace keeps its plain name.

For each selected session, one Bash call writes to files only: `$S/dump-session.sh <session_id>
LD/<date>/flow-<stage>/dumps`. It writes `<sid8>.{txt,ctx,guards,agents.tsv,long.txt,errors,misses,ledger-paths}`,
appends to `stats.txt` and `transcripts.tsv`, and writes a session with no transcript to `missing.txt`. `.misses`
holds every `ingest-miss:` line the session itself wrote, never one from the skill text it loaded. The main thread
reads `stats.txt`, `rows.tsv`, `missing.txt` and `wc -c dumps/*.txt`. A `missing.txt` row is named in the digest
header as not read.

## Fan-out: one reader per transcript

`sin-flow:read-only-analyst` on `<mid>`, at most 3 in flight. Dumps under 10 KB share one reader. The dispatcher saves
each report to `readers/<sid8>.md`. Each prompt carries:
- the paths: `.txt`, `.ctx`, `.guards`, `.long.txt` (assistant texts ≥ 300 chars), `.agents.tsv`, `.errors`,
  `.misses`, `.ledger-paths`, `rows.tsv`.
- the dump format line: `MM-DD HH:MM KIND: text`, with KIND one of CMD, USER, USER(sys), USER(queued), AGENT, SKILL,
  ASSISTANT, TOOL, RESULT, SYSTEM. AGENT is a subagent hand-back or an "Another Claude session" relay, not a user
  turn. SKILL is the skill text that the session loaded.
- the session's row (repo, skill, `n`, account), its place in its chain (n-th of N), the repo's profile path, the
  stage question list from `reference/questions.md`, plus items 3, 4 and 6 of the exec list, and the user's question,
  if any, as the last heading.
- the rule: tag every claim `measured` with the HH:MM it rests on, or `inferred`. Anything else is "not checked". Word
  budget 700, or 220 per grouped session.
- "Read the dump fully. Open only the files named here and the ledger paths in `.ledger-paths`. Return markdown text.
  You cannot write files." Add the exceptions that the stage list names (a review file, read-only `gh pr view` or `gh
  api` on that PR).

## Consolidate: the digest

`LD/<date>/flow-<stage>.md`, in the digest form from `reference/questions.md`, written from the reader reports only.
It opens a dump again only when two readers contradict each other on the same minute.

Header, before the first `## `:
- stage, repo filter, `n`, dates, the mode (`author` or `user`), and the exact `select-runs.sh` line with its row
  count.
- `Sessions covered:` with one full id or 8-char prefix per covered row. A session left out or not read is named on
  another line, never in this block.
- "Context figures are measured (`input+cache_read+cache_creation` per assistant turn), window 1M".
- the size of `skills/<stage>/SKILL.md` in lines and KB, with the delta since the previous digest of that stage. Every
  line of a skill is paid on every request, so growth is a finding.

Body:
0. **The user's question**, if they asked one: ≤ 6 sentences, each tagged.
0b. **Effect check**: for each proposal that an earlier digest of this stage applied, read the metric it named. The
    result is shifted as expected, not shifted, or moved the wrong way. The wrong way proposes the revert.
0c. **Inbox**: for each open `inbox.md` row of this stage, the problem it removes, what these sessions show for or
    against it, and the verdict: propose now, or wait for what.
1. Timeline table: one row per session, with `repo` and `skill` columns, then the stage's columns.
2. Hand-off and guard table: every hand-off and guard event across the chain, in time order, with ctx and outcome.
3. User turns: the count per class per session, and verbatim quotes of every class e and g turn with session and
   HH:MM.
4. The stage-specific sections of the digest form.
5. **Recurring failure modes, ranked**: each with a count (`k/N sessions`), the repos, a tag (`measured`, `read` with
   `file:line`, or `inferred`), and one quote or one HH:MM line. A mode on a single session says `1/N` and goes to a
   **Watch** list at the end of this section, not to a proposal. A mode seen only in old-skill runs, whose sin-flow:*
   successor no longer has that line, is listed as `gone in sin-flow:<stage>` and proposes nothing.
6. **Diff proposals**. Sections 0 to 5 hold no proposal. Each proposal in 6 points back to 0 to 5.

## Mode: author or user

- **author**: `$S/mode.sh` prints the mode once per run. Author means the plugin is loaded in place from a git
  checkout the user can commit to. `${CLAUDE_PLUGIN_ROOT}` is not under a `plugins/cache/` folder and is inside a git
  work tree with a writable git dir. Proposals may target `skills/`, `agents/`, `hooks/` and `bin/` of that checkout,
  as well as the plugin options and `profiles/<key>/`.
- **user**: the plugin runs from the plugin cache, which an update overwrites. Proposals are applied only to
  the plugin options (`claude plugin configure <id> --values-stdin`) and `~/.claude/sin-flow/profiles/<key>/`. A proposal with a target in the flow layer is
  never applied. It goes to `LD/proposals-for-author.md` as one block that the author can act on without the digest:
  `## <YYYY-MM-DD> <target below the plugin root>`, the version (`basename ${CLAUDE_PLUGIN_ROOT}`), the problem in the
  two numbers, counts with their filter set and repos, **now**, **proposed**, **effect**. They need no approval.

## Proposals: diffs the user approves

A proposal needs a mode counted on ≥ 2 sessions, or the user's explicit ask. An open inbox row is an ask. When a hook,
a script or a check can carry the fix, propose that first and a text line second. A mode in one repo only targets that
repo's profile first. A proposal never stops or blocks a stage to enforce a precondition that the flow could set up
itself. It fixes how the stage is opened, and a stage in the wrong state keeps working.

Every run carries one **Deletions** entry, with the same evidence as an addition: lines of the stage skill that no
covered session followed, lines that a hook or another line contradicts, lines that a newer rule supersedes, and pairs
of lines that say the same thing, merged into one. A run that adds and never deletes is incomplete.

A **Rewrite** proposal is due when the stage skill grew in each of the last 3 digests of that stage and no Rewrite of
that stage was carried within those 3 digests. It is the whole skill from scratch in
`LD/<date>/flow-<stage>-rewrite.md`, with only what a covered session followed or a hook enforces. The user approves
it as a whole.

One proposal per numbered entry, each with:
- **layer**: `user` (a plugin option, the user's copy of an `examples/` script), `profile` (`profiles/<key>/`) or `plugin`
  (the mechanism, for every user). One user's habit or preference is `user` or `profile` in every mode. A `plugin` proposal holds no word
  that only one repo uses. Read it against each repo key in its evidence and one key that is not there. A `plugin`
  proposal for one tool or one practice also names the plugin option or profile key that turns it on, and says what a
  user with no such key gets.
- **target**: a `file:line` in `${CLAUDE_PLUGIN_ROOT}/skills/<stage>/SKILL.md`,
  `${CLAUDE_PLUGIN_ROOT}/agents/<name>.md` or `${CLAUDE_PLUGIN_ROOT}/skills/review/reference/lenses/<lens>.md`, a hook
  path, `${CLAUDE_PLUGIN_ROOT}/bin/…`, `~/.claude/sin-flow/profiles/<key>/profile.md`, a plugin option by its key,
  or the user's copy of an `examples/` script under `~/.claude/sin-flow/`. Never another file.
- **writers**: every place that writes or repeats the thing the proposal fixes, found by grep, listed. A proposal that
  changes fewer than all of them says which it leaves and why.
- **now**: the current text, verbatim, ≤ 6 lines. **proposed**: the replacement, verbatim.
- **evidence**: the digest section and the count it rests on, with the repos.
- **effect**: the run-log column or digest count that must move, which way, and within how many runs of the stage. The
  next Effect check reads this line.
- **blocking?**: `no` for text, thresholds and order. `yes` for anything that denies a tool call, exits non-zero or
  stops a session. A `yes` proposal names the live probe that must run first: which repo, which command, and what
  output proves that it does not block the wrong caller.

Each proposal that the mode lets this run apply is a file before the chat report:
- the whole proposed copy of each target in `LD/<date>/flow-<stage>/proposed/`, and `patches.diff`.
- `targets.tsv`, one row per target with its real path and the sha256 of the live file (`shasum -a 256`).
- `apply-user.sh` for the `user` and `profile` layers, `apply-plugin.sh` for the `plugin` layer. Each script:
  1. checks the live sha of each target against `targets.tsv`. When one differs, another session edited it: the script
     stops and changes nothing. Rebase the copy onto the live file and write its row again.
  2. copies each target to `LD/backups/<date>/<target path below its root>` first (root `${CLAUDE_PLUGIN_ROOT}` or
     `~/.claude/sin-flow`, `mkdir -p` the folder, a second edit on the same day reuses the backup). Then it copies the
     proposed file over the target and checks it with `cmp`.
  3. `apply-plugin.sh` only: runs `bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-layers.sh` in the checkout. A failure restores
     every target from its backup and stops.

When two stages propose to the same file, the main thread owns the merge. It writes the merged copies, `targets.tsv`
and the apply scripts in `LD/<date>/merged/`. An inbox row that touches more than one stage gets one owning stage,
named in the consolidator brief.

Nothing is edited before the user approves. "Do it" or "go" in the launch request approves the run, not a diff the
user has not seen. The user approves by number, or all at once: "all", "yes", "apply" or "your call", in any language,
said to the list. Silence, "not now" or a question is not approval.

1. The ledger quotes the approving user line verbatim with its HH:MM. An apply script runs only after that line exists
   in the transcript.
2. Make a partial approval, or a scope change in the user's line, in the copies first.
3. Run `bash <abs path>/apply-user.sh`, then `apply-plugin.sh` in author mode, once each. Never edit a live file piece
   by piece. Denied: give the user the line `! bash <abs path>/apply-<layer>.sh`.
4. When the applied text differs from the proposed text, add a `⚠ CORRECTION` note to the proposal entry, with why.
5. Author mode, after the applies: tell the user to run `/reload-plugins`. Ship the checkout changes as one PR through
   `sin-flow:shipper` in ship mode, with the profile that `sin-flow-profile key` resolves in the plugin checkout.
6. A declined proposal stays in the digest marked `declined <date>`. The next run does not propose it again unless new
   rows contradict the decline.

## Self: reviewing sin-flow:learning

`/sin-flow:learning self`, or the last consolidator of a full run. It replaces Setup and Fan-out. The other sections
hold.

- **Rows**: the learning runs that no earlier `LD/*/self.md` header lists. These are the `## Learning <date> …`
  entries in `LD/ledger.md` and the digests they name, plus `select-runs.sh self` (run-log rows whose `skill` ends in
  `learning`). Fewer than 3: stop and say so. Workspace `LD/<date>/self/`, digest `LD/<date>/self.md`.
- **Under review**: this file, `reference/questions.md`, `scripts/` and `hooks/scripts/learning-launch.sh`.
- **Ideas**: `inbox.md` rows with flow `learning`, plus each `inbox-archive.md` row marked "handed to
  `/sin-flow:learning self`" that no earlier `LD/*/self.md` header lists.
- **Readers**: one `sin-flow:read-only-analyst` on `<mid>` per learning run, with its digest, its ledger entry, the
  dump of the session that the entry names, and the self question list from `reference/questions.md`.
- **Numbers**, per run: the share of proposals approved and reverted, lines deleted against added, growth of the
  skills it reviews, and user corrections about learning. Proposals target only the files under review.

## Close the loop

- Append to `LD/ledger.md` under `## Learning <date> flow-<stage>` (or `self`): the sid8, repo filter, mode, rows
  covered, digest path, ranked modes (one line each), the approving line with its HH:MM, proposals applied (with
  backup paths), declined and written for the author, and the PR link in author mode. The ledger is the memory of this
  stage.
- In `inbox.md`, mark each row that this run turned into a proposal: `proposed <digest>`, then `applied <date>`,
  `declined <date>` or `for author <date>`. Append one row for flow `learning`: what in this skill got in the way this
  run, or "nothing". `/sin-flow:learning self` reads that row.
- The run ends with an empty `inbox.md` table. Closed rows move to `inbox-archive.md`. Each open row goes to the user
  one at a time, with your pick, until it is closed. A row the user accepts becomes a numbered proposal with its layer
  and goes through the apply scripts like every other. Never edit a live target straight from the walk. A new row takes the next number after the highest in both files.
- On `CTX GUARD`: let the readers in flight finish, write the digest and the ledger entry for their sessions, tell the
  user in one line to run `/sin-flow:learning <same mode>` in a new session, and stop.
- An item a reader could not answer is marked so in the digest. The ledger entry names the missing input (a run-log
  column, a dump field) as a proposal, not as a fact.

## Chat: the user's headings

Plain language: a signature line with what was asked, then these headings in this order, then stop:

- **WHAT HAPPENED**: one sentence, cause → effect. The mechanism, an arrow, then what the user saw.
- **EVIDENCE**: the two numbers for the covered sessions, split by repo, and the `file:line` behind the cause, ≤ 3
  lines.
- **WHAT I PROPOSE**: two lists, «your settings» then «the plugin, for everyone», ≤ 6 lines in all. One line «now →
  will be» per thing the user of the flow experiences, with its proposals folded in. No proposal numbers, no
  identifiers. In user mode, one more line names `proposals-for-author.md` and the count of blocks added.

Copy the `===` final-message block of one covered exec session whole from `<sid8>.long.txt` to
`LD/<date>/flow-<stage>/final-message-<sid8>.md`. Never quote it in chat and ask no question about it. Name it in chat
only as a finding: when it breaks the Final message shape in `${CLAUDE_PLUGIN_ROOT}/skills/exec/SKILL.md`, or when a
PR body is over 200 words.

The whole report is ≤ 15 lines. Counts carry their filter set in the digest. Chat never holds a reader's paragraph,
only the conclusion and the path.

## Boundaries

- Runs outside every product repo and reads none except the `.ledger-paths` files. A claim that needs more says "not
  checked" and names the path to check.
- Never writes to auto-memory, Slack, a ticket or a product repo. The one GitHub write is the author-mode plugin PR,
  and it never merges that PR.
- Never edits a skill, agent, hook, profile, plugin option or launcher without the user's approval and a backup made
  first. In user mode never edits the flow layer.
- Never turns on a hook that can deny or stop a session before the live probe named in the proposal has run.

## Known issues (open, inbox #39)

- Item 2: the harness caps one launch at 20 subagents in total, so consolidators can lose their readers.
- Item 4: `scripts/dump.sh` clips TOOL lines and `exit=` RESULT lines at 140 to 300 characters.
- Item 8: the auto-mode classifier blocks even a read-only probe run of an apply script.
