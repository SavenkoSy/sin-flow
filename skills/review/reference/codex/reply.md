# Codex: reply

The judge read your findings and the findings of the other finders. Its verdict follows below. This is your one turn
to reply. After your reply, the judge reads it and gives the final status of each row.

The verdict has two kinds of rows:

- `K<n>` rows: the judge keeps the finding. Its `from:` line names the finder rows. `codex/F<k>` is your row.
- `R<n>` rows: the judge rejects the finding, with a reason and a refutation.

Reply to these rows only:

1. Each `R` row whose claim starts with `codex/`: the judge rejected your finding.
2. Each `K` row: any finder raised it, and the judge kept it.

For each row, set `stance`:

- `accept` when the judge is right. Keep `argument` and `evidence` short.
- `contest` when the judge is wrong. `argument` says why, in at most three sentences. `evidence` quotes the code that
  proves it, with `file:line`, from the working directory. For a rejected row, show the path from an entry point to
  the line. For a kept row, show the guard, the caller or the value that makes the defect impossible.

Rules:

- Contest only with code that you read now. A contest with no `file:line` quote has no effect.
- Do not raise a new finding here. The judge ignores it.
- Do not edit a file. Do not run a test or a build.
- `row` is the row id exactly as the verdict writes it, for example `K2` or `R4`.

The verdict:

