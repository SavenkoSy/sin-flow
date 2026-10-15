# contract

What the change stops doing, or does differently, for someone who already depends on it: a caller
in the repo, a consumer outside it, a job already in a queue, a row already in a table.

## Look for

- **Deleted or replaced behaviour.** For every chunk the diff removes or replaces (skip renames and
  whitespace), name the invariant it held — a guard, a default, a scope filter, a callback, a flag
  gate, a URL resolve, an ordering — then search `TREE` for where the new code holds it. Neither
  re-established nor retired in `pr.md` → a finding that names the invariant.
- **Orphans.** A removed method, constant, scope, route, i18n key or job class that is still
  referenced — grep `TREE`, including strings in yml, schedules and SQL; code the change left dead.
- **Response and payload shape.** For every serializer, `render json:`, jbuilder view, webhook or
  outgoing payload on a `## Flow` line in `<pkg>/context.md`: `null` ↔ `{}` / `[]` / `""`; a key added,
  removed or renamed; a type change (string ↔ integer, id as string); nesting; JSON:API `data` /
  `attributes` / `relationships`; pagination meta; status code; error body. Compare with the
  swagger / rswag / OpenAPI doc and with a sibling serializer that renders the same field. A field
  emitted outside the flag that gates it counts.
- **Empty values, old and new.** A doc, changelog, swagger line or PR claim such as "no shape
  change" or "same keys" is a claim to check, not proof. For every field whose producer the diff
  replaces, read what the old producer returns when there is no value and what the new one returns
  on every branch it has: `null` vs `{}` vs `[]` vs `""`. A different empty value between old and new, or between two branches of the new code, is a
  finding.
- **Field names against the task.** For every message, payload, file or response the change reads
  from or writes to another system, put the field names the ticket, issue or linked doc gives
  (`pr.md:line`) beside the names the code reads or writes (`file:line`). A name that differs — a
  prefix dropped, a synonym, other nesting — is a finding whichever side is right. A spec that
  builds the body by hand proves nothing about the names on the wire.
- **Column semantics.** Same column, new meaning: what `NULL` means now, a sentinel value, a changed
  default, an enum value renamed or renumbered, units, timezone. Grep every reader of the column in
  `app/`, `lib/`, raw SQL strings, queries and exports.
- **Callers inside the repo.** Grep each changed public method, class and constant; check every call
  site against the new signature, return shape (nil vs `[]`, raise vs `false`) and side effects.
- **Consumers outside the repo.** Each one named in `pr.md` or `rules.md` — an FE app, a partner,
  another service. Quote the line that names them and the field they read.
- **Jobs already enqueued.** A `perform` signature, job class name or queue that changed while old
  jobs sit in the queue, the retry set or the schedule; a cron entry naming a removed class; a
  message producer deployed separately from its consumer.
- **Feature flags.** Trace every flag and setting in `context.md` `## Settings` both ways. With
  the flag off, is the old behaviour kept exactly? A removed flag check; a new default; new
  behaviour that runs past its flag. With the flag on, trace the new path the same way: a new wait
  on an action that only publishes asynchronous work (enqueues a job, sends a message) orders
  nothing downstream.
- JS/TS: a changed prop, exported type or response type that other modules still use the old way
  — grep the imports.

## Do not raise

Report every suspicion with the best trigger and evidence you have (`trigger: none found` is
allowed); reality, the validation boundary and severity are judged by `verify`. Only two things go
to DECLINED:

- **Pre-existing.** A defect whose cause sits on lines the diff does not touch and that the change
  does not newly reach. When the change is what makes an unchanged line break, it is a finding:
  anchor it on the changed line.
- **Linter.** What a linter, type checker or CI job in this repo already enforces — quote the
  enabled rule at its config `file:line`.

## Sources

- `bmad-code-org/BMAD-METHOD · skills/bmad-code-review/references/deletion-check.md` — "did it
  carry behavior or a contract that the change neither re-established nor intentionally retired?"
- `Piebald-AI/claude-code-system-prompts · system-prompts/skill-code-review-correctness-finder-angles.md`
  — Angle B (name the invariant a deleted line enforced, find where it is re-established) and
  Angle C (callers of each changed function).
- `EveryInc/compound-engineering-plugin · skills/ce-code-review/references/personas/api-contract-reviewer.md`
  — sentinel contract overloads (Column semantics) and response/payload shape compared against a
  sibling serializer or the swagger/OpenAPI doc.
