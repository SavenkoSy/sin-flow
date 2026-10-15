# docs

Everything the PR changes besides the code: the docs, plan, runbook and API schema that must move
with it, and the ops steps a deploy needs. On 13 flow PRs in one team repo the teammates
raised 37 such points and our other lenses saw almost none: no lens owned them.

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
- **Plan.** A plan section this PR implements carries the repo's done marker and PR reference.
- **Feature flags.** A flag the diff adds or reads at a new call site has its row in the flags doc
  with every call site and the default.
- **DEPLOY / runbook.** An after-deploy action the change needs (backfill, enqueue, flag flip, rake,
  index rebuild) has an item in the house format (`rules.md`); items sit in the section that matches
  when they must run relative to the migrations and jobs a deploy runs on its own; dependent steps are
  ordered; the item names the environment and what to measure first; a destructive step names its
  rollback or archive.
- **API schema.** A request or response shape change is in the rswag spec and in every generated
  swagger version; shapes reuse the shared components; type and format sit inside `schema:`; required
  fields, enums and bounds the code enforces are declared.
- **Approvals.** A sensitive change or a deviation from the ticket's acceptance criteria carries the
  approval record the repo's rule asks for (who, when, channel; not the PR author).
- **Ops.** A new external call, bucket, queue or secret the code needs in production is provided
  for: the IAM permission, the setting in each env's settings file, the flag that gates it.
- **PR body.** The repo's PR template and language, as `rules.md` states them.

## Do not raise

- A doc the change does not touch and no trigger names.
- Wording and tone in prose that states the right facts.

## Sources

- Not in the lock: an audit of teammate comments on flow PRs and the profile folder's `review-team.md`
  rules DOCS-SYNC, DEPLOY, SWAGGER, APPROVAL-RECORD, FLIPPER, CONFIG.
