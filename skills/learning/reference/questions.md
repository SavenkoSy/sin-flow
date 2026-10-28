# Stage question lists and digest forms

One list per stage, for every repo. Items 3, 4 and 6 of the exec list go into every stage's list. A stage's
list is also its digest form: the items are the timeline columns and the stage-specific headings of §4.

## How a session is found and named

- The run log's `skill` column names the command that started the session. A stage launched through a hand-off
  launcher with `--goal …` starts with `/goal`, not with the skill; the skill name sits in the goal text, and a
  self-hand-off continuation also starts with `/goal`. Grepping `<command-name>/<skill>` finds none of these —
  trust the run log's `skill` column.
- The progress ledger (exec item 7): `~/.claude/sin-flow/work/<key>/<id>/progress.md` for `sin-flow:*` and `flow-*` runs;
  for older runs, the path in `<sid8>.ledger-paths` — the ledger the session itself wrote.

## exec

1. Timeline — CMD line (time, args incl. `continue:`, the `/goal` text when there is one), first Agent
   dispatch, each wave's gate result line, PR opened (time, URL), the exit line the ledger or goal names
   (shipped / blocked / handoff written — which one), the hand-to-user step when the profile asks for a
   visual check or a solo merge, and whether the user answered in this session; last line (time; `/exit`,
   hand-off, or silence).
2. Hand-off events — every TOOL line that launches a hand-off (`sin-flow-handoff`, or the launcher that the `handoff`
   option names): HH:MM, ctx at that minute, full command, the
   nearest preceding CTX GUARD / LIMIT GUARD / USER line verbatim, the `RESULT:` line that came back (`opened:`,
   `paste into …`, `continue in this session:`, `exited <n>: no tab opened`; older runs print `session:`),
   whether the goal text was carried verbatim, and whether the assistant stopped or kept working
   (quote its next line).
3. Guard messages — every `CTX GUARD`, `LIMIT GUARD`, `Usage limit reached`: HH:MM, ctx, the assistant's next
   text ≤ 200 chars; obeyed, argued or ignored.
4. User turns — every USER line: HH:MM, ≤ 120 chars, class a review/fix on diff · b QA · c unrelated task ·
   d question · e complaint about exec's behaviour · f git/PR/CI mechanics · g hand-off/context/limit
   instruction; count per class.
5. Orchestrator's own work — `TOOL: Bash` vs `TOOL: Agent` counts; ≤ 3 Bash examples the skill says to
   delegate to `sin-flow:shipper` or a subagent (test suite, grep/sed over app code, PR creation, git rebase).
6. Stalls — every gap ≥ 20 min: from → to, last line before it.
7. Ledger — from the progress ledger file, not from the dump (it clips the writes): its appends per unit;
   every `handoff:`, `Ruling:` and `next action` line verbatim.
8. Final review — its rows from the review file for this PR against the PR's later human/bot comments: each
   later comment raised first by the review, or missed and classed real (reproduced: the reply or the fix
   shows a failing spec, a measured row or the user's order) · not reproduced (answered without a fix) ·
   redundant validation · hypothetical · style · test gap. Only `real` is a post-PR defect. The reader reads
   that review file and may run read-only `gh pr view` / `gh api` on that PR.
9. Final output — the orchestrator's final chat message after the PR line, verbatim from `.long.txt`, with
   its line and word count, and the user's next USER line about it, if any.

## plan

1. Timeline — CMD line, the seed or intake it read, first measurement, plan written, hand-off.
2. Self-check result before hand-off; the hand-off command as run (flags, `--goal` text), the `RESULT:` line
   relayed or the in-session fallback taken; ctx at hand-off.
3. Every `ingest-miss:` line from `<sid8>.misses` — each is a question ingest or sync left open.
4. Measurements — each claim measured or left "not checked", through which source of the profile; any
   credential value printed in the dump is a finding.
5. User turns (plan asks the user nothing — every USER line is a finding, classed as exec item 4).

## ingest

1. Timeline — CMD line (the source handed over), the exit taken (plan / hotfix / data-fix / answer /
   investigation) and when.
2. The first answer to the user — HH:MM, and how many TOOL lines preceded it.
3. Questions asked of the user, in order, one per turn or bundled, with the answers verbatim.
4. For a hotfix: the brief the implementer got, gate results, the commit, the PR, every USER line during it.
5. For a plan exit: the seed path and the hand-off to plan with its `RESULT:` line.

## epic

1. Questions asked of the user, in order, with the answers verbatim.
2. The intake contract path; stories in it.
3. Hand-off to plan and its `RESULT:` line.

## sync

1. Timeline — CMD line (key, phase), the board agent's dispatch and return, the digest shown, the batch taken.
2. Board agent cost — from `.agents.tsv`: model, turns, cache.
3. What the main thread fetched itself that the board agent should have (any board fetch is a finding).
4. Tickets closed or parked, and the user's verdict on the proposed batch, verbatim.

## review

1. Timeline — CMD line (time, PR, depth, `--at`), package built, each lens's return line, verify's return
   line, review file written, last line (time; `/exit`, `post`, or silence).
2. Findings — per lens, `<n> findings` from its return line; verify's `in · kept · rejected`, kept split by
   verify's verdict (the tokens `<this file's folder>/../../review/reference/lenses/verify.md` defines) and
   high / med / low, rejected split by the reason verify gives.
3. Posted — every `post <n,…>`: HH:MM, the numbers, the poster's return; the rows never posted.
4. Outcome — for each posted comment, did the flagged line change before merge (`gh api` on the PR's review
   comments and its merged diff). For an exec-mode review file, which later human/bot PR comments the pipeline
   missed, classed as exec item 8, with a count per class. An exec-mode file has no review row: it gets a
   reader of its own with this item only.
5. User quotes — every USER line verbatim with HH:MM, and the row it is about.

Before its proposals, stage review runs `bash <this file's folder>/../../review/reference/check-sources.sh`. Each row it prints is a
source that moved: fetch its compare diff and propose a numbered diff to the lens whose `## Sources` names
that row. The compare diff is that proposal's evidence.

The review reader may read the named review file and run read-only `gh api` / `gh pr view` on that PR.

## setup

1. Mode — first run on the machine, onboarding a repo, check, or `add <source>`.
2. Questions asked of the user — count (the skill allows three), each verbatim with the answer.
3. Final line — the all-clear line or the list of rows with fixes; which fixes the user approved.
4. Any credential value printed in the dump — a finding with HH:MM.

## build, commit and other stages

Items 1 (timeline: CMD, first dispatch, commit/PR, last line), 3, 4, 5 and 6 of the exec list.

## self

One reader per learning run: its digest, its ledger entry, its session dump.

1. Proposals — how many; approved, `declined`, written for the author, later reverted by an Effect check; did
   each carry an `effect` line and did the next digest read it.
2. Deletions and Rewrite — lines deleted vs added by the applied proposals; was a Deletions entry there.
3. Skill size — the header's size and delta per stage.
4. User turns about learning itself — verbatim with HH:MM: corrections, "not that", "simpler", a proposal the
   user asked to change.
5. Final-message check-in — the user's answer, and whether it became a proposal.
6. Inbox — rows the run consumed, rows it left open, its `learning` row.
