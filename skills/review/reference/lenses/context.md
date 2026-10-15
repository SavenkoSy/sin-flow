# context

This lens writes `<pkg>/context.md`, not findings. It runs first and alone; every finder and
`verify` read its `## Entry points`, `## Flow`, `## External input`, `## Settings` and
`## End of run` instead of deriving them again.

## Look for

### Method

1. Read `pr.md` (PR body and issue, or the plan in exec mode), then `files.txt`. Work set = changed
   files outside `spec/`, `test/`, `__tests__/`, `*.spec.*`, `*.test.*`, fixtures and cassettes.
2. For each file in the work set, list the symbols its hunks in `diff.patch` add or change: class,
   module, method, constant, scope, job class, event or receiver name.
3. Grep callers in `TREE` upward, one hop at a time, until an entry point. Grep the full constant
   (`Foo::SyncBar`), its bare name and its underscored form (`foo_sync_bar`): schedules, queue
   tables and yml configs name classes as strings. Ignore hits under spec dirs.
4. Stop a chain at the first entry point. A chain whose callers run out first goes to `## Unreachable`.
5. From each entry, follow the changed code down to where its data lands.
6. List every environment-dependent value the changed code reads: a settings key (`Settings.*`,
   `config_for`, `Rails.application.config.*`), `ENV[...]` / `ENV.fetch`, credentials, a feature
   flag (Flipper, a boolean setting, a DB-backed toggle). Grep the base settings file and every
   per-environment override (`config/settings.yml`, `config/settings/*.yml`,
   `config/environments/*.rb`, `.env*` in TREE) for its value.
7. For each entry, find where a run records how it ended: a status column, `success!` / `fail!`, a
   degraded or partial result, a counter of errors, a return value the caller reads, a watermark
   or cursor write.

| kind | where it lives |
|---|---|
| route | `config/routes.rb` → `Controller#action` |
| job | `app/jobs`, `app/workers`; schedule in `config/schedule.rb`, `config/sidekiq*.yml`, sidekiq-cron config or initializer; else the `perform_later` / `perform_async` call site |
| rake | `lib/tasks/**/*.rake` → `namespace:task` |
| receiver | webhook and partner-callback controllers, event receivers, SNS/SQS consumers + queue or topic name |
| callback | `before_*` / `after_*` / `after_commit` in a model, when the save that fires it is outside the diff |
| mutation | `app/graphql/mutations` and resolvers |
| deploy | data steps in `db/migrate`, after-deploy services |
| page / api-route | JS/TS: `pages/**`, `app/**/page.tsx`, `pages/api/**`, `app/**/route.ts`; callers by `import` grep |

### `<pkg>/context.md`

The shape lives in the `sin-flow:reviewer` agent (`## context.md`); this lens adds
`## Settings` and `## End of run` after `## Unreachable`. What goes in it:

- `## What it does` — for a human: what the PR does for the product and why; the first sentence names
  no class, table or file.
- `## Entry points` / `## Flow` — every entry from the Method above; every hop carries `file:line`.
  An entry, schedule or queue is listed with the grep hit that makes it one, quoted as `file:line`.
- `## External input` — one row per place outside input enters on a `## Flow` line. `validated`
  quotes the guard — strong params `permit`, a model validation, a `.present?` / `blank?` return,
  a schema or signature check, middleware — or says `none found`. Never fill it from assumption.
- `## Read first` — prefer a file on several `## Flow` lines, the file where data lands, a
  file in `RISK`.
- `## Unreachable` — changed non-spec files no entry reaches, docs and config included, each with
  the symbols grepped. It takes a file off the path lenses only: `intent` still maps every file
  in `files.txt`.
- `## Settings` — one row per value from step 6; `none` when the changed code reads none:

  ```
  S<k> | <name> | read <file:line> | default <base file:line "value"> or blank or none found | overrides <env file:line "value">, … or none | on/set → <what the reader does> · off/blank → <what the reader does> | E<k>
  ```

  A value blank or absent in the base file is written `blank`, never left out.
- `## End of run` — one row per entry from step 7; `none` when no entry records an end:

  ```
  E<k> | success recorded <file:line> | degraded / partial / zero-work end <file:line> or none found | the caller or status sees <what, on that end>
  ```

  A run that can end degraded, partial or with no work done and is still recorded as success is
  named in its row as `degraded → success`.

## Do not raise

- Findings, severities, verdicts or fix suggestions: `context.md` describes, it never judges. What
  looks wrong goes into the rows as fact (`blank`, `none found`, `degraded → success`); the finders
  and `verify` judge it.
- Unchanged lines as defects: they appear only as `## Flow` hops. Finders send a defect on lines the
  diff does not touch and the change does not newly reach to DECLINED as pre-existing.
- What a linter, type checker or CI job in this repo already enforces.

## Sources

- `Piebald-AI/claude-code-system-prompts · system-prompts/skill-code-review-correctness-finder-angles.md`
  — Angle C: grep the callers of each changed function.
- `trailofbits/skills · plugins/fp-check/skills/fp-check/SKILL.md` — "Execution context" and
  "Caller analysis" in step 0.
- No upstream reviewer has an entry-point stage (research notes, Context). `## Entry points`, `## Flow` and
  `## External input` are this flow's own design.
