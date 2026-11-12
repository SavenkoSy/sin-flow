# Consolidator: one stage, from the scorecard to the digest

You get a stage, the day folder `D`, the mode, the model and the effort of the grid row `learning-reader`, the inbox rows that the stage
owns, and the user's question. `S` is the `scripts/` folder beside this folder. Your workspace is `D/flow-<stage>/`.
You write only inside it, and the digest `D/flow-<stage>.md`. You write no `targets.tsv` and no apply script. You
write nothing to `inbox.md`.

## 1. Inputs

- `D/run/sessions.tsv`: one row for each session of the run, with every number. `D/run/stages.tsv`: the summary row
  of your stage. `D/run/flags.tsv`: the columns `stage repo n sid8 session_id pick reasons reader events`.
- `pick` is `flag`, `sample`, `skip` or `missing`. `reasons` names the rule that set the flag. `events` holds each
  guard, red gate and `blocked` return as `<kind>@MM-DDTHH:MM`. `reader` is the group of the session.
- Dump the picked sessions and the user turns of every row of the stage, in one Bash call:

```
awk -F'\t' -v st=<stage> '$1 == st && ($6 == "flag" || $6 == "sample") { print $5 }' D/run/flags.tsv |
  while read -r sid; do $S/dump-session.sh "$sid" D/flow-<stage>/dumps; done
$S/turns.sh D/run <stage> > D/flow-<stage>/turns.txt
```

- `dump-session.sh` writes `<sid8>.{txt,ctx,guards,agents.tsv,long.txt,errors,misses,ledger-paths}`, and adds to
  `stats.txt` and `transcripts.tsv`. `.misses` holds every `ingest-miss:` line that the session itself wrote.
- Files under review: `${CLAUDE_PLUGIN_ROOT}/skills/<stage>/SKILL.md`, the agents and hooks that the stage calls
  (`agents/{shipper,implementer,reviewer,read-only-analyst,review-poster,board}.md`, `hooks/scripts/{stage,work-commit,ctx-guard,exec-guard}.sh`,
  the run-log hook that `grep -l 'runs.tsv' ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/*.sh` finds, `sin-flow-handoff` and the
  launcher that the `handoff` option names), and `~/.claude/sin-flow/profiles/<key>/profile.md`. For the stage `review`
  they also hold `skills/review/reference/{pipeline.md,lenses/,sources.lock.tsv}` and
  `~/.claude/sin-flow/profiles/<key>/review-team.md`. A stage with no sin-flow:* skill yet is read against the skill in
  its `skill` column, and its proposals go to the sin-flow:* skill that replaces it.
- Stage review, before its proposals: run `bash ${CLAUDE_PLUGIN_ROOT}/skills/review/reference/check-sources.sh`. Each
  row it prints is a source that moved. Fetch its compare diff and propose a numbered diff to the lens whose
  `## Sources` names that row. The compare diff is the evidence of that proposal.

## 2. Readers

Every reader is `sin-flow:read-only-analyst` on the grid row `learning-reader`, at most 3 in flight. Save each report to
`readers/<name>.md`. Three kinds:

- **Session reader**, one for each value of the `reader` column of your stage. It gets the dump paths of its
  sessions, their rows of `flags.tsv` and `sessions.tsv`, the profile path of each repo, the stage question list
  from `questions.md`, items 3, 4 and 6 of the exec list, and the user's question as the last heading. For a flagged
  session it starts at each time in `events` and at each `USER` line, and reads 60 lines before and after. It reads a
  sampled session and a dump below 60 KB in full. Word budget: 220 for each session.
- **Turns reader**, one for the stage when `turns.txt` holds a user line. It gets `turns.txt` and item 4 of the exec
  list. It gives the class of every user turn, the count for each class and session, and every class e and g turn
  verbatim with the session and HH:MM. Its counts cover every row of the stage.
- **PR reader**, one for each 20 values of the `pr` column that are not `none`. It gets those rows of
  `sessions.tsv` and item 8 of the exec list. It reads the review file of each PR, in the `reviews_dir` option (`sin-flow-profile user reviews_dir`, default
  `~/.claude/sin-flow/reviews/`), and may run read-only
  `gh pr view` and `gh api` on that PR. It returns the post-PR defects for each PR and their sum.

Each prompt also carries:
- the dump format line: `MM-DD HH:MM KIND: text`, with KIND one of CMD, USER, USER(sys), USER(queued), AGENT, SKILL,
  ASSISTANT, TOOL, RESULT, SYSTEM. AGENT is a subagent hand-back or an "Another Claude session" relay, not a user
  turn. SKILL is the skill text that the session loaded.
- the rule: tag every claim `measured` with the HH:MM it rests on, or `inferred`. Anything else is "not checked".
- "Open only the files named here and the ledger paths in `.ledger-paths`. Return markdown text. You cannot write
  files." Add the exceptions that the stage list names.

## 3. The digest

Write `D/flow-<stage>.md` from the scorecard files and the reader reports only. Open a dump again only when two
readers contradict each other on the same minute.

Header, before the first `## `:
- stage, repo filter, `n`, dates, the mode (`author` or `user`), and the exact `select-runs.sh` line with its row
  count.
- `Sessions covered:` with the `sid8` of every row of your stage in `flags.tsv` whose `pick` is not `missing`. The
  scorecard counted each of them. A later line `Read:` names the flagged and sampled ones. A later line
  `No transcript:` names the `missing` ones. Put no other session id inside the `Sessions covered:` block.
- "Context figures are measured (`input+cache_read+cache_creation` per assistant turn), window 1M".
- the size of `skills/<stage>/SKILL.md` in lines and KB, with the delta since the previous digest of that stage.

Body:
0. **The user's question**, if they asked one: 6 sentences or fewer, each tagged.
0a. **Scorecard**: the row of your stage from `stages.tsv`, and the rows of the same stage from `LD/scorecard.tsv`
    above it. Say which numbers moved.
0b. **Effect check**: for each proposal that an earlier digest of this stage applied, read the metric it named. The
    result is shifted as expected, not shifted, or moved the wrong way. The wrong way proposes the revert.
0c. **Inbox**: for each open `inbox.md` row of this stage, the problem it removes, what these sessions show for or
    against it, and the verdict: propose now, or wait for what.
1. Timeline table: one row for each session that a reader read, with `repo` and `skill` columns, then the stage's
   columns.
2. Hand-off and guard table: every hand-off and guard event, in time order, with ctx and outcome.
3. User turns, from the turns reader: the count for each class and session, and each class e and g turn verbatim.
4. The stage-specific sections of the digest form in `questions.md`.
5. **Recurring failure modes, ranked**: each with a count, the repos, a tag (`measured`, `read` with `file:line`, or
   `inferred`), and one quote or one HH:MM line. The count is `k/N` of all rows when a scorecard column or the turns
   reader gives it. In all other cases it is `k/R` of the sessions read, and the line says so. A mode on a single
   session goes to a **Watch** list at the end of this section, not to a proposal. A mode seen only in old-skill
   runs, whose sin-flow:* successor no longer has that line, is listed as `gone in sin-flow:<stage>` and proposes
   nothing.
6. **Diff proposals**, by `proposals.md`. Sections 0 to 5 hold no proposal. Each proposal in 6 points back to 0 to 5.

Stage exec only: copy the `===` final-message block of one read session whole from `<sid8>.long.txt` to
`D/flow-exec/final-message-<sid8>.md`. Name it in your return only when it breaks the Final message shape in
`${CLAUDE_PLUGIN_ROOT}/skills/exec/SKILL.md`.

## 4. Return

Return only the ranked modes, the proposals with their layer and switch, and the post-PR defect count. Use 300 words
or fewer.
