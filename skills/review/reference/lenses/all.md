# all

One agent, every checklist, one findings file — the quick depth and every fix round. Read and apply
the checklists `lenses/code.md` names, then the ones `lenses/fit.md` names, with the same conditions.
Each keeps its own «Look for» and «Do not raise». Read the diff once and run every checklist over it.
A defect two checklists find is one F row tagged with both.

A recheck has review threads in `pr.md`. Do not raise a thread's defect at its line again. For each
thread the author answered as fixed, look for the same defect class at the other sites the PR
changes under TREE, and raise each one that is still there.
