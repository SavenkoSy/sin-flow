# failures

Swallowed failures in the changed lines: an error, a `false` or a `nil` that the code turns into
"success" or "nothing happened", so the job finishes, the row is not written and nobody is told.

## Look for

For each error handler or fallback the diff adds or changes, name the concrete errors it hides and
what the caller sees instead. Walk the `## Flow` lines in `<pkg>/context.md` to find the caller.

- **Broad rescue.** `rescue => e`, bare `rescue`, `rescue StandardError` / `Exception`, the
  `rescue nil` modifier. List what it catches beyond the intended error — `NoMethodError` from a
  typo, `ActiveRecord::RecordInvalid`, `ActiveRecord::StatementInvalid`, a timeout — and whether
  the handler only logs and continues, returns `nil` / `[]` / `{}` / `false`, or re-raises.
- **Rescue inside a job or consumer.** A `rescue` in `perform` or a message handler that does not
  re-raise ends the retry: Sidekiq / ActiveJob marks the job done, the SQS message is deleted.
  Check `retry_on` / `discard_on` against what the code actually raises.
- **Degraded run marked success.** A per-item rescue that counts or logs errors into a degraded or
  partial result, after which the run is still recorded as success (`context.md`
  `## End of run`, `degraded → success`), is a swallowed failure whatever the repo's
  convention. Its concrete input can be a required setting blank in the base or production file
  (`## Settings`), a client error, a row that raises. Say what the operator sees: a green run,
  no alert.
- **"Picked up by the next run."** A handler that drops a failed row because a later run will
  retry it: trace that the next run reaches that row (cursor, eligibility, budget). Until that path
  is shown, the failure is swallowed.
- **Non-bang persistence.** `save`, `update`, `create`, `destroy`, `update_attribute` whose `false`
  or unsaved record is ignored; `valid?` never read; `create` in a loop with no error collection.
- **Bulk writes that skip the model.** `update_all`, `update_columns`, `insert_all`, `upsert_all`,
  `delete_all` skip validations and callbacks. Raise it when the change relies on one, and quote
  it: a search reindex, a counter, an audit row, an `after_commit` enqueue.
- **Ignored return values.** A service result, `errors`, `success?`, an HTTP status, a `system` /
  `Open3` exit status dropped; Faraday with no `raise_error`; HTTParty / `Net::HTTP` status unread.
- **Nil flowing on.** `find_by`, `where(…).first`, `dig`, `Hash#[]` returning nil that the next
  lines use; `&.`, `try`, `presence ||`, `|| {}`, `.to_h`, `Array()`, `fetch(k, default)` turning
  that nil into a silent skip, or into a default written as if it were real data.
- **Client errors swallowed.** HTTP, S3, SQS / SNS errors (`Faraday::Error`, `Aws::S3::Errors::*`,
  `Net::ReadTimeout`) rescued to a log line; retries exhausted with no re-raise and no error report.
- **Log and continue.** `Rails.logger.error` with no re-raise or error-tracker report inside a job,
  or a log line with no record id, so the failure cannot be found afterwards.
- JS/TS: `catch {}` or `catch (e) { console.error(e) }` and carry on; `.catch(() => null)`; a
  promise never awaited; `fetch` with no `res.ok` check; `?.` on a value the next step needs.

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

- `anthropics/claude-plugins-official · plugins/pr-review-toolkit/agents/silent-failure-hunter.md`
  — hidden errors per catch block, log-and-continue, optional chaining that hides errors,
  unjustified fallbacks. Its user-message and error-ID checks are left out.
