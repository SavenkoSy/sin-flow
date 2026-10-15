# intent

Does the diff do what was asked, all of it, and only that? The task text lives in `pr.md`: pr mode —
PR title, body, linked issue and its comments; exec mode — the plan text. Clean code that solves a
different problem still fails the task. The author's narrative is testimony, not evidence: check
every claim against the code under TREE.

## Look for

1. **Build the criteria list.** Start from the acceptance criteria, then read the rest of the task
   text: a requirement written once in a description or a comment counts as much as a listed one
   (a backfill, a setting, a data change, a docs update). Read the issue and the plan both: every requirement named in either is a criterion. Issues
   are often reopened: read comments newest first, and a later comment that changes a requirement
   replaces the earlier one. Number them `AC1…ACn`, each with its `pr.md:line`. When `pr.md` holds
   no task text there are no criteria: write zero findings.
   - **One criterion per field or item.** When the task gives a list — the fields of a request or
     an answer payload, statuses, columns, environments, a rate or volume — each item is its own
     criterion (`AC4.1`, `AC4.2`, …) with its `pr.md:line`.
   - **"No X" criteria.** A criterion that says something does not happen is checked by grepping
     every path that does X, not by finding the path that does the alternative.
   - **Deferred items.** A requirement the ticket or the PR body defers ("not in this PR",
     "follow-up") leaves the list only when the deferring `pr.md` line names that requirement's
     subject; a deferral in the plan or the ledger (`# Notes`, `DEFERRED:`) never does. Otherwise
     the requirement stays a criterion.
2. **Mark each criterion** `implemented` / `partial` / `missing`, backed by a `file:line` you read.
   A method whose name sounds like the criterion proves nothing — trace it from the entry
   point the criterion is about, and quote the code line that reads or writes each field the
   criterion names, not the method that handles the message. Grep TREE before calling it missing:
   the behavior may already exist outside the diff (then it is implemented, cite that line).
3. **Every path to the defect.** Find every caller of the code the task says is broken. When the
   fix covers one call path and another still reaches the same defect, the criterion is `partial`;
   name each uncovered path with `file:line`.
4. **Two readings.** When a criterion admits two defensible readings, name both, say which one the
   diff implements, and raise it with the `pr.md` line that supports the other reading quoted, or
   `none found`.
5. **PR description vs diff.** Extract each checkable claim from the PR body or plan — what it
   changes, what it preserves, "same as X", "also handles Y" — and try to falsify it. A claim the
   diff does not back is a finding.
   - The PR's own "What is NOT in this PR" / "Out of scope" / "Follow-up" sections are claims:
     grep the diff for each thing they say is absent — a producer, a caller, a field, a
     dependency. Present in the diff → a finding.
   - Claims from earlier rounds of the body count while their text is still in `pr.md`.
   - A class-level or module doc comment the diff adds or changes is a claim: falsify it against
     the code under it.
6. **Every changed file maps to a criterion.** Walk `files.txt` — docs, config, specs and the files
   `context.md` lists under `## Unreachable` included — and map each file to the criterion or claim
   it serves. A file that maps to none is a finding: work from another ticket (its name, path or
   content names another ticket or feature), or unrequested change — a new outbound field on a
   consumer the task does not name, a changed default, a job that now runs where it did not, a
   hunk that serves no criterion. It is a question for the author, not proof of a bug.

Writing the findings:
- `partial` / `missing` criterion: the line is where the behavior would have to live (the handler
  the diff touched on that flow); evidence quotes the criterion at `pr.md:line` and the code line
  that shows the gap; trigger is the scenario the criterion describes, from its entry point.
- An `implemented` criterion is not written, and never goes on the DECLINED line. One whose mark
  rests on less than a quoted code line per named field — a method name, a doc line, a spec, some
  of its fields — is an F row.
- A requirement that cannot be decided from the code (UI copy, a product choice) is an F row with
  `trigger: none found` and the reason in `breaks`.
- A file with no criterion: the line is its first changed line; evidence quotes that line and the
  nearest criterion it could serve, or `none found`.

## Do not raise

Report every suspicion with the best trigger and evidence you have (`trigger: none found` is
allowed); reality, the validation boundary and severity are judged by `verify`. Only two things go
to DECLINED:

- **Pre-existing.** A gap whose cause sits on lines the diff does not touch and that the change
  does not newly reach, and that no criterion asks this PR to change.
- **Linter.** What a linter, type checker or CI job in this repo already enforces — quote the
  enabled rule at its config `file:line`.

## Sources

- `intent bmad-code-org/BMAD-METHOD skills/bmad-code-review/customize.toml`
  (Intent Alignment Auditor)
- `intent bmad-code-org/BMAD-METHOD skills/bmad-code-review/references/claims-check.md`
  (the narrative as testimony, falsify each claim).
