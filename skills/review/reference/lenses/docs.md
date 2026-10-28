# docs

This lens checks each doc that the diff makes false, and each doc that a repo rule ties to the code.
The `## team rules` section holds the obligations of one repo: a runbook, an API schema, a flags doc.

## Look for

Read `<pkg>/rules.md` (every `CLAUDE.md` and the `## team rules` section), `files.txt`, the diff and
`<pkg>/pr.md`. Then, for each obligation below that the diff triggers, check it is met in the diff.

- **Maintenance triggers.** Every `CLAUDE.md` line of the form «when you change X, update Y» (a
  docs gate, a doc-first gate, a dependency graph, a README row, a glossary, `Last verified`) whose X
  matches a file in `files.txt`: Y is in the diff and says what the code now does.
- **Docs say what the code does.** Each doc, plan or README line the diff touches or that names a
  changed class, flag, setting, endpoint, count or env: recompute every number it states (columns,
  steps, windows, limits) from the code, and flag text the code no longer backs — a removed key, a
  reversed decision, an old name.

## Do not raise

- A doc the change does not touch and no trigger names.
- Wording and tone in prose that states the right facts.

## Sources

- Not in the lock: an audit of teammate comments on flow PRs.
