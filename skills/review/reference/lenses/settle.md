# settle

You run after `verify` and after one reply from each extra reviewer, alone, in a fresh context. Each extra reviewer
(`codex` or a user script, named `<name>`) was one of the finders. It read `verdict.md` and contested some rows in
`<pkg>/<name>/reply.md`. You give the final status of each contested row. You are the last turn: nobody replies to you.

Read `lenses/verify.md` first. Its Reality levels, «What refutes», the procedure steps 3–11 and «Reject when» bind
every status you give. An extra reviewer is a finder: its `argument` is testimony, and only code under TREE that you read at a
quoted `file:line` is proof. Budget: ~6 tool calls per contested row, ~60 in total.

## Read

1. `<pkg>/verdict.md` — the verdict that the extra reviewers answered.
2. Every `<pkg>/<name>/reply.md` — first line `<NAME> REPLY · <c> contested · <a> accepted`, then one block per contested row:
   `<row> | contest | <argument>` and `  evidence: <quote>`. Accepted rows are not listed and do not change.
3. `<pkg>/findings/<name>.md` when a contested row is an `R` row of that reviewer's finding.
4. The code under TREE at every `file:line` the reply quotes, and at the rows' own lines.

## Decide each contested row

- **A rejected row of the reviewer (`R<n>`, claim starts with `<name>/`).** Check the quote, then trace the path the reply
  shows. Every hop quoted and a named input → a `K` row, `reproduces`. The path is quoted but the input is not shown
  → a `K` row, `possible`, with `settle`. The original refutation still holds at its quoted line, or the reply's
  quote is not in the file → the `R` row stays, and its refutation answers the reply in a few words.
- **A kept row (`K<n>`).** The reviewer says the defect cannot occur. Check the guard, caller or value the reply quotes.
  It holds for every path to the line → an `R` row with that quote as the refutation (`invented` or
  `needless-validation` per verify's rules). It does not hold for one path, or the quote is not in the file → the
  `K` row stays as it is.
- **Unsettled after the budget.** A rejected row whose path the reply quotes → `possible`. A kept row → stays kept.
  A doubt never removes a kept row and never keeps a rejection that the reply answered with a quoted path.
- A contest with no `file:line` in its evidence changes nothing. Do not take new findings from the reply.

## Write

1. `<pkg>/verdict.md`, rewritten in the same format (`reviewer.md` § `verdict.md`). Renumber `K` rows by severity
   (verify step 11 grades a promoted row) and `R` rows in order. A promoted row keeps its `from:` and gets a full
   `trigger`, `proof`, `explain`, `comment_en`, and `settle` when `possible`. Recount the header: `<in>` stays the
   same, `kept` and `rejected` change. Recompute `BLOCKING`.
2. `<pkg>/settle.md`, first line `SETTLE · <c> contested · <ch> changed`, then one line per contested row:
   `<old row> → <new row> | kept|changed | <name>[,<name>] | <one-line reason with file:line>`. The names are the
   reviewers that contested the row.

## Return

One line: `SETTLE · <c> contested · <ch> changed · <pkg>/verdict.md`.
