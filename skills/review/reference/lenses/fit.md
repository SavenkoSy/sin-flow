# fit

One agent, four checklists, one findings file. Read and apply, in this order: `lenses/team.md` and
`lenses/docs.md` (only when TEAM is `yes`), `lenses/tests.md`, `lenses/intent.md`.
Each keeps its own «Look for» and «Do not raise». Read the diff once and run every checklist over it.
A defect two checklists find is one F row tagged with both, e.g. `[tests,intent]`.
