---
name: learning
description: 'Self-review stage of the flow for every repo with a flow profile, run outside any product repo. A script computes a fixed scorecard from the run log and the transcripts and flags sessions. Read-only subagents read the flagged sessions and a small sample. One digest for each stage ranks the failure modes and ends in diff proposals that the user approves before anything is edited. `self` reviews sin-flow:learning itself. Use when invoked as `/sin-flow:learning [--dry-run] [repo-key|all|self] [stage] [n] [question]`, when the launch hook opens it, or when the user asks why a flow session behaved as it did: "why did exec-N not hand off", "what went wrong in plan-N", "review the flow runs".'
---

# sin-flow:learning

Chat with the user in the `chat_language` option (`sin-flow-profile user chat_language`). When it is absent, use the
language the user writes in. Fixed phrases are rendered in that language. Files are English.

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

Every finding names its **layer** first, by the rules in `${CLAUDE_PLUGIN_ROOT}/ARCHITECTURE.md`. The repo is a
column, not a separate flow.

## Arguments

`/sin-flow:learning [--dry-run] [repo-key|all|self] [stage] [n] [question…]`

- A leading absolute path (the launcher's cwd anchor) is skipped.
- `repo-key`: a folder name under `~/.claude/sin-flow/profiles/`, or `?` for rows the run log could not place. `all`,
  or no key, means every repo. When the first token is a stage name, the key is `all`.
- `self`: reviews sin-flow:learning itself. Follow `reference/self.md` in place of steps 2 to 5.
- `stage`: a value of the run log's `stage` column: `setup`, `sync`, `ingest`, `epic`, `plan`, `exec`, `review`, then
  the rest the log carries (`build`, `commit`, …). That is also the full-run order.
- `n`: the run log's `n` column. A named `n` overrides the coverage exclusion. A re-read is the user's call.
- Anything after is the user's question, answered first in the digest. A question about one item of a stage list:
  readers answer that item and items 3, 4 and 6, and the digest names its sessions in §0.
- `--dry-run`: run `scripts/select-runs.sh --dry-run <key> [stage] [n]`, print its output, and stop.

## Paths and models

- `S=${CLAUDE_PLUGIN_ROOT}/skills/learning/scripts`. `LD` is the folder that `$S/learning-dir.sh` prints. Every file
  of this stage lives there, never in the plugin.
- `D=LD/<YYYY-MM-DD>`. A second run on the same day uses `LD/<YYYY-MM-DD>-2`. Every file inside keeps its plain name.
- The run log is `~/.claude/sin-flow/runs.tsv`: `date repo stage n session_id account model start end turns
  user_turns ctx_first_k ctx_last_k handoff limit_hits skill`.
- Resolve each grid row once with `sin-flow-profile model <grid row>`. It prints a model and an effort. Name both on
  every dispatch:

| role | agent | grid row |
|---|---|---|
| consolidator, one for each stage | `general-purpose` | `learning-consolidator` |
| reader | `sin-flow:read-only-analyst` | `learning-reader` |
| plugin PR review | by `skills/review/reference/pipeline.md` | its lens rows |

## Run

1. **Mode.** `MODE=$($S/mode.sh)` prints `author` or `user`. `reference/proposals.md` says what each mode may change.
2. **Rows.** `mkdir -p D/run`, then `$S/select-runs.sh <key|all> [stage] [n] > D/run/rows.tsv`. It keeps one row
   for each session and drops covered rows unless `n` is given. A row is covered when a digest header names it in
   its `Sessions covered:` block. Rows that the log gets after this step belong to the next run.
3. **Scorecard.** `$S/scorecard.sh D/run/rows.tsv D/run` writes `sessions.tsv`: one row for each session with its
   user turns, hand-offs, guard events, max context, weighted token cost, gates, fix rounds and PR.
4. **Flags.** `$S/flag.sh D/run` writes `flags.tsv` and prints `stages.tsv`, one summary row for each stage. A session
   gets a flag for one of these reasons:
   - `turns`: its user turns are above the stage median.
   - `guard`: it has a guard or limit event.
   - `gate`: its last gate is red, or a `sin-flow:shipper` return says `blocked`.
   - `cost`: its cost is above the stage p90.
   - `short`: its turn count is below a fifth of the stage median.

   The script also takes a sample of the clean sessions of each stage: a tenth of them, and at least 2. The sample
   grows until flagged plus sampled sessions are a third of the stage. Readers open only these sessions. The
   numbers in `stages.tsv` cover every row.
5. **Consolidators.** Each stage with 3 or more rows goes to one consolidator, at most 4 in flight. A stage with
   fewer rows, or a stage the user leaves out, is skipped and named in the ledger entry. The brief names the stage,
   `D`, `MODE`, the two model names, the open `inbox.md` rows that the stage owns, and the user's question. It tells
   the consolidator to follow `$S/../reference/consolidator.md`. An inbox row that touches more than one stage gets
   one owner stage. The consolidator writes `D/flow-<stage>.md` and its proposed copies, and returns 300 words or
   fewer. In a full run the last consolidator runs `reference/self.md` when 3 or more learning runs are undigested.
6. **Apply files.** `$S/make-apply.sh D` reads every `D/*/proposed/` tree. It writes `D/apply/targets.tsv`,
   `patches.diff`, `apply-user.sh` and `apply-plugin.sh`. No agent writes these files by hand. When the script stops
   on a conflict, follow `reference/apply.md`.
7. **Report.** Give the chat report of § Chat. Then wait.
8. **Approval and apply.** Follow § Approval, then `reference/apply.md`.
9. **Close.** Follow § Close.

## Chat

The conclusion and the path, in the `chat_language` option, in 15 lines or fewer. The proposals go in three lists:
«your settings», «only for you», then «the plugin, for everyone». Each proposal goes to the list that its **switch**
names. A plugin option or a profile key goes to «your settings» under that key. `author` goes to «only for you».
`none` goes to «the plugin, for everyone». Before the report, read each «for everyone» line as a user with another
setup. When it changes nothing for that user, its switch is wrong: fix it in the digest and move the line.

Inside each list, show the proposals as one block «today → after the change». Group them by what the user sees, with
one short bold topic for each group. Each topic gives what happens today and what changes against today, in plain
words, with no file name. Do not give one line for each proposal or each file. In user mode, one more line names
`proposals-for-author.md` and the count of blocks added. After the lists, give one inbox block: one line for each
`P<n>` with the row numbers it takes or covers, then each declined row with its reason. The 15 lines do not count
this block. Counts carry their filter set in the digest.

## Approval

Nothing is edited before the user approves. "Do it" or "go" in the launch request approves the run, not a diff the
user did not see. The user approves by number or all at once, in a line said to the list. Silence, "not now" or a
question is not approval. The ledger quotes the user line verbatim with its HH:MM. An apply script runs only after
that line exists in the transcript.

## Close

- The run ends with no open `inbox.md` row of a stage it covered. A row of a skipped stage stays open, and the ledger
  entry names it. Never walk the open rows with the user one at a time. Decide each open row yourself: take it into
  a numbered proposal with its layer, mark it covered by `P<n>`, or decline it with a one-line reason. Show that list
  in the same chat report as the proposals, and the user approves it once with them. A taken row goes through the
  apply scripts like every other proposal.
- After the applies, follow `reference/close.md`: the scorecard rows, the ledger entry and the inbox marks.
- On `CTX GUARD` or `LIMIT GUARD`: let the readers in flight finish. Write the digests, the ledger entry and
  `D/continue.md` (the steps left and the inbox verdicts). Hand off with `sin-flow-handoff --cwd <this cwd> --name
  learning sin-flow:learning <anchor> "continue: read <continue.md>"`. After it prints `opened:`, this session writes
  nothing more and stops. When no tab opens, tell the user that line in one line, and stop.

## Boundaries

- Runs outside every product repo and reads none except the `.ledger-paths` files. A claim that needs more says "not
  checked" and names the path to check.
- Never writes to an external system or a product repo except the author-mode plugin PR, and never merges that PR.
- Never edits a skill, agent, hook, profile, plugin option or launcher without the user's approval and a backup made
  first. In user mode never edits the flow layer.
- Never turns on a hook that can deny or stop a session before the live probe named in the proposal has run.
