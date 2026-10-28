# tests

A test counts only if a real regression of the changed behavior would make one of its assertions
fail. One question per behavioral change: if this behavior broke where it is actually used, would
the suite go red? Read a spec before claiming what it covers; before claiming no spec exists, grep
all of `spec/` under TREE for the class, the method and the route, and say how far you looked.

## Look for

For each part of the diff that changes a return value, a raised error, a side effect, a query, a
request, a response shape or an ordering, name the smallest realistic regression (drop the branch,
return the old value, omit the field, skip the call). That regression is the trigger. A finding is
a spec that would stay green under it, or no spec at all on the path from the entry point.

**One row per behaviour, no catch-all.** Walk every changed public method, behaviour and branch —
each new `if` / `case` arm, early return, rescue, counter, bound and cursor write. For each one,
name the spec `file:line` whose assertion fails under its regression. A behaviour with no such line,
or one you doubt, is an F row: a gap. "All covered", "adequately covered", "every one of these has
a spec" and any line that clears several behaviours at once are forbidden; a behaviour you did not
map to a spec line is a gap, and "pinned by a spec" is never a DECLINED reason.

- **Stale HTTP recording.** A recorder that matches method + URI only replays the old response
  when the diff changes a request body or query and its recording is not in `files.txt`. Read the
  recorder's match config first (STACK `ruby` or `mixed`: VCR `match_requests_on` in `spec/support`
  or `spec/*_helper.rb`). If it matches the body, a stale recording fails loudly: no finding.
- **Success-only mock.** A stub of the client or collaborator whose
  behavior the change depends on returns only the success case: no cap (page size, max window,
  batch limit), no error path (timeout, 4xx/5xx, rate limit), no second page. Quote the real
  contract where it is visible — in the client code, a cassette, the partner's doc in TREE, or
  `pr.md`.
- **Hand-built message fixture.** A spec that builds a message body itself — the answer we parse,
  the request or payload we send — proves nothing about the wire shape. Compare its keys and
  envelope with the contract `pr.md` names (the issue's field list, the transport's envelope); a
  key or wrapper that differs, or no spec asserting the field names we send, is a gap.
- **Per-run bound.** For each automatic path that sends external requests or enqueues jobs (cron,
  queue action, callback), the regression is "bound removed or blank". Name the spec that runs it
  over more eligible rows than the bound — including the first run, with no cursor and the bound's
  setting at its base value (`context.md` `## Settings`) — and asserts the exact number sent;
  none → a gap, even when no bound exists in the code yet.
- **Failure survival per handler.** When a message, row or job must survive a failure (not acked,
  not deleted, retried, not marked done), each new handler, subclass or receiver on that path needs
  its own example where it raises and the item survives. A base-class example with a stub handler
  does not cover a subclass that adds its own rescue, early return or ack. A gap the PR body
  discloses is still an F row — quote the disclosure.
- **Pinned asymmetry.** A spec that pins two branches returning different values for the same empty
  state is not evidence the difference is intended; report it with both branch lines.
- **rswag drift.** A serializer field, endpoint param or status changed, but the rswag spec schema
  and the generated swagger file (`swagger/**/*.yaml|json`) did not; or a `run_test!` whose
  response has no schema, so it checks the status code only.
- **Tautological assertion.** The spec asserts the value it stubbed, `expect(x).to eq(x)`, only
  `not_to raise_error`, only `be_present`/`be_truthy` on something always present, or only that a
  mock received `:call`. A mock/log-call check is not an observation of the output.
- **Happy path only.** `pr.md` says the change is about an edge (nil, empty list, duplicate, retry,
  boundary value, unauthorized caller) and every new example exercises the normal case.
- **Caller-path gap.** A unit spec covers the new branch, but the values the real caller passes
  never reach it, and no request/job spec runs that caller.
- **Lost coverage.** A spec file or `it` block deleted, or a matcher weakened (`eq` → `include`,
  exact count → `be_positive`), while the behavior it pinned still exists in the code.
- **`allow_any_instance_of` / `expect_any_instance_of`** on the class under test or on the
  collaborator the diff changed, so the changed code never runs in the spec.
- **Time and order dependence.** Assertions on dates without `freeze_time`/`travel_to` while the
  code reads `Time.current`/`Date.today`; `eq([...])` over a query with no `order`; examples that
  rely on records, `Rails.cache`, ENV or class-level state left by another example.
- **Migration compatibility.** Specs build only new-format rows while the change must also read
  rows written before it (nullable column, renamed key, backfill still pending).

Evidence for each finding: the changed line, the spec line(s) that run it (or the grep that found
none), and why the named regression would pass them.

## Do not raise

Report every suspicion with the best trigger and evidence you have (`trigger: none found` is
allowed); reality, the validation boundary and severity are judged by `verify`. Only two things go
to DECLINED:

- **Pre-existing.** A problem in a spec the diff did not touch, whose subject the diff did not
  change and does not newly reach.
- **Linter.** What a linter, type checker or CI job in this repo already enforces — quote the
  enabled rule at its config `file:line`.

## Sources

- `tests bmad-code-org/BMAD-METHOD skills/bmad-code-review/review-prompts/verification-gap.md`
