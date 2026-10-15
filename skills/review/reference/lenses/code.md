# code

One agent, four checklists, one findings file. Read and apply, in this order: `lenses/paths.md`,
`lenses/rails.md` (only when STACK is `ruby` or `mixed`), `lenses/failures.md`, `lenses/contract.md`.
Each keeps its own «Look for» and «Do not raise». Read the diff once and run every checklist over it.
A defect two checklists find is one F row tagged with both, e.g. `[paths,failures]`.
