# Close: the scorecard, the ledger and the inbox

- Run `scripts/scorecard.sh append D/run <stage>=<post-PR defects> …`, with the count that each consolidator
  returned. It adds the rows of `D/run/stages.tsv` to `LD/scorecard.tsv`, with the same columns on every run. A
  stage with no count keeps `na`.
- Append to `LD/ledger.md` under `## Learning <date> flow-<stage>` (or `self`): the sid8, repo filter, mode, rows
  covered, rows read, digest path, ranked modes (one line each), the user line with its HH:MM, proposals applied
  (with backup paths), declined and written for the author, and the PR link in author mode. The ledger is the memory
  of this stage.
- In `inbox.md`, mark each row that this run turned into a proposal: `proposed <digest>`, then `applied <date>`,
  `declined <date>` or `for author <date>`. Closed rows move to `inbox-archive.md`.
- Append one row for flow `learning`: what in this skill got in the way this run, or "nothing".
  `/sin-flow:learning self` reads that row.
- Only the main thread writes `inbox.md`. A new row takes the next number after the highest in `inbox.md` and
  `inbox-archive.md`.
- An item a reader could not answer is marked so in the digest. The ledger entry names the absent input (a run-log
  column, a dump field) as a proposal, not as a fact.
