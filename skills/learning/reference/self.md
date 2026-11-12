# Self: a review of sin-flow:learning

`/sin-flow:learning self`, or the last consolidator of a full run. One consolidator on the grid row `learning-consolidator` does
it. It replaces the rows, the scorecard and the flags. The digest form, `proposals.md` and `apply.md` hold.

- **Rows**: the learning runs that no earlier `LD/*/self.md` header lists. These are the `## Learning <date> …`
  entries in `LD/ledger.md` and the digests they name, plus `scripts/select-runs.sh self` (run-log rows whose `skill`
  ends in `learning`). Fewer than 3: stop and say so. It reads earlier learning runs only, never this one.
- **Workspace** `D/self/`, digest `D/self.md`. Its header lists the runs under `Sessions covered:`.
- **Under review**: `SKILL.md`, the files in `reference/`, `scripts/` and `hooks/scripts/learning-launch.sh`.
- **Ideas**: `inbox.md` rows with flow `learning`, plus each `inbox-archive.md` row marked "handed to
  `/sin-flow:learning self`" that no earlier `LD/*/self.md` header lists.
- **Readers**: one `sin-flow:read-only-analyst` on the grid row `learning-reader` for each learning run. It gets the
  digests of that run, its ledger entry, the dump of the session that the entry names, and the self question list
  from `questions.md`.
- **Numbers**, for each run: the rows of stage `learning` in `LD/scorecard.tsv` (cost, readers, flagged and sampled
  sessions), the share of proposals approved and reverted, lines deleted against added, growth of the skills it
  reviews, and user corrections about learning.
- Proposals target only the files under review. They go to `D/self/proposed/plugin/…` by `proposals.md`.
