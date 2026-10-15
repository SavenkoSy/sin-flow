# rails

This lens is a finder: report every suspicion the changed lines raise, each with its quoted evidence. Whether it is real, whether a guard or validation boundary already covers it, and how severe it is are judged by verify, not here. Style, convention, naming, dead code, YAGNI, DRY duplication and SOLID violations ARE findings for this lens — reviewers raise them as low-severity notes — so report them, citing the `lenses/rails.md:line` of the check each one breaks.

## Look for

### Orientation

Read the `Gemfile`, `config/` and the code around each hunk before applying any check below. A check
about a gem or store the project does not use does not apply. Where the project has its own
convention — base class, namespace, query-object return type, where API docs live — new code follows
it; that convention outranks this file.

### Security

- An action that loads a record by id without scoping it to the current user, account or tenant.
- A new endpoint, action or job entry with no authentication or authorization check, while its siblings have one.
- A secret, token or key committed in code, a fixture or a log line; a token or PII written to logs.
- `send` / `public_send` / `constantize` / `safe_constantize` on a value from params or a payload.
- A redirect to a URL taken from params; a file path built from user input.
- A webhook or callback receiver that does not verify the signature before acting.

### ActiveRecord and queries

- An association read inside a loop, a serializer or a view with no `includes` / `preload` → N+1.
- `.count` on a loaded relation where `.size` would not hit the DB; `.present?` / `.any?` that loads a whole relation.
- `pluck` or `map(&:id)` feeding a second query when a join or subquery would do it once.
- `find_by` whose `nil` result is not handled, or `find` where a missing row is an expected case.
- Several writes that must succeed together, outside a transaction.
- A uniqueness validation with no unique index behind it → duplicates under concurrency.
- A callback (`after_save`, `after_commit`) with side effects — mail, HTTP, enqueue — that fires on writes the change did not mean to trigger.
- `update_column(s)` / `update_all` / `insert_all` where the skipped validations or callbacks matter.
- `default_scope` added or changed.

#### Signal → pattern — raise a pattern only when its signal is on a changed line; quote it
| signal in the diff | pattern |
|---|---|
| `OFFSET` / `.offset` / page number over a table that grows | keyset pagination |
| a job that can run twice (retry, at-least-once queue) | idempotent job |
| a POST we retry, or one a caller retries | idempotency key |
| a DB write and an enqueue/publish in one unit | transactional outbox |
| retries without jitter | full jitter |
| a remote call in the request path | timeout, circuit breaker |
| a concurrent read-modify-write | `lock_version` / row lock |
| a write per row inside a loop | `upsert_all` / `insert_all` / `update_all` — they skip callbacks and validations |
| `.all.each`, an unbounded load | `find_each` / `in_batches` |
| an FK or filtered column with no index | index (Postgres creates none for an FK) |

### Migrations

- A new column, foreign key or filtered column without an index; an index added to a large table without `algorithm: :concurrently`.
- `null: false` or a default added on a table with existing rows and no backfill step.
- Data changes written with model classes inside a migration (the model changes later; the migration does not).
- A migration that cannot be rolled back — `change` with an irreversible step and no `up` / `down`.
- `db/schema.rb` or `structure.sql` out of step with the migration in the same diff.

### Controllers and API

- Strong params that permit a field the caller must not set (owner, role, status, price).
- A changed response field, status code or param with no matching change in the API docs or clients in TREE.
- An error path that returns 200, or a 500 for a client mistake that should be a 4xx.
- Pagination missing on an endpoint that returns a growing collection.

### Models and services

- Business rules split between a controller and a model, or duplicated in two services.
- A service with more than one public entry point, or one that both reads and writes unrelated aggregates.
- A `rescue => e` (or `rescue StandardError`) that swallows the error with no log, re-raise or result value.
- A new class or method that duplicates one already in TREE — grep for it before calling it new.
- Dead code the diff leaves behind: an unused method, constant, param or branch.

### Background jobs

- Job arguments that are whole records instead of ids, or that are not serializable.
- A job that is not safe to run twice while the queue retries it.
- A job enqueued inside a transaction that may roll back, or before the record is committed.
- A long loop in one job with no batching, no checkpoint and no bound.

### Ruby

- Mutation of a frozen or shared object; a constant holding a mutable value that callers change.
- `Time.now` / `Date.today` instead of the zone-aware `Time.current` / `Date.current`.
- Float arithmetic on money.
- A method that returns different types on different branches (`nil`, `false`, a record) where callers only handle one.
- Nesting deeper than the surrounding code, or a method far longer than its neighbours, where a guard clause or an extracted object would do.
- A name that says something other than what the code does.

### PostgreSQL

- A query that filters or sorts on a column with no index, on a table that grows.
- `LIKE '%…'` or a function on the filtered column, which the index cannot serve.
- Filtering, sorting or joining on a JSONB key instead of a typed column.
- A long transaction holding row locks across a remote call.

### Search (Elasticsearch / OpenSearch), only if the project uses it

- A mapping change that needs a reindex with no reindex step.
- `from` + `size` paging past the max result window; a query with no size limit.
- A record write with no matching index update, or an index update outside the commit.

### Redis and caching, only if the project uses it

- `KEYS` in code that runs in production; a key with no TTL that grows with users or records.
- A cache with no invalidation when the source record changes.
- Redis used as the only store for data that must survive a restart.

### Always flag (igmarin)
- `permit!` in any form (`params.require(:x).permit!`) → every attribute, including owner, role and state columns, becomes mass-assignable.
- `html_safe`, `raw` or `<%==` on a string that carries user- or partner-supplied data without `sanitize` → XSS.
- SQL built by interpolation or concatenation — `where("… #{x}")`, `order(params[:sort])`, `find_by_sql`, `execute`, `Arel.sql`,
  `select`/`pluck` with a built string → injection. Flag every one; the trigger names where the interpolated value comes from.
- Business logic in a controller action — pricing, tax, scoring, domain calculation, multi-model writes → belongs in a model or service.
- Destructive migration on a large or hot table without a safe path — `remove_column` / `rename_column` / `rename_table` /
  `change_column` type / `drop_table` with no `ignored_columns` deploy first → running code hits a missing column, or the table is locked.


## Do not raise

- Lines the diff does not touch and the change does not newly reach — write them under DECLINED as pre-existing.
- What RuboCop or CI already enforces in this repo — only when `rules.md` or the repo config (`.rubocop.yml` at SHA) shows the cop is on.
- Generated files: `db/schema.rb` / `db/structure.sql` written by a migration, generated API doc files.
- A future problem the diff gives no evidence for.
- Framework or gem internals the diff does not touch.

## Sources
- `rails ← igmarin/rails-agent-skills skills/code-review/SKILL.md@9c639c4d` — Always Critical list.
- Not in the lock: the remaining checks are written for this pipeline from general Rails, Ruby and PostgreSQL practice.
