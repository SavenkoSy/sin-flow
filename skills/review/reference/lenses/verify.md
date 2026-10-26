# verify

You run last, alone, in a fresh context, and write `<pkg>/verdict.md` in the format defined in
`reviewer.md`. Finders report every suspicion and judge nothing: reality, the validation
boundary, hypothetical inputs and severity are decided here only. A finder's `trigger` is
testimony; proof comes only from code under TREE, `pr.md`, `rules.md` and the lens files, each read
at a quoted `file:line` — no database, no stage, no running code; an inferred hop never carries
reproduces. Budget: ~5 tool calls per finding, ~80 in total (160 with `TEAM=yes` at `DEPTH=thorough`); unsettled → possible with a path, else invented.

## Reality

- **reproduces** — a named input and a path from an entry point to the line, every hop quoted.
- **possible** — the path is quoted, but nothing in TREE or `pr.md` shows the input occurs → `settle`.
  Always a K row, shown whatever its impact; never an R row.
- **invented** — only when no path reaches the line, the quoted code is not in the file, or the
  claimed behaviour does not happen → an R row. A refutation that the value is already guaranteed
  (non-nil, validated, cast) by its only writer or an upstream guard is `needless-validation`, never
  `invented`; a finding restating another R or K is `duplicate`.

A lack of disproof is not confirmation. A risk counts only when TREE, `pr.md` or `rules.md` shows
it; a hypothetical actor or consumer (an external contract's consumer is not one), a "one day"
volume, a parameter value no caller passes (grep the real callers' values) → `invented`. A premise
only the ticket or an issue states (what another service will send, a setting's future value, a
volume) and no code path under TREE produces is possible at most; `settle` names one real message,
row or value. An R row has one of five reasons: `invented`, `needless-validation`, `duplicate`,
`pre-existing`, `nit-no-rule` (a style point no rule names — never a real defect of small impact).

## What refutes

- Code under TREE at a quoted `file:line`: a guard, a caller and the values it passes, a type, a DB
  constraint or unique index, a spec that runs the path against the real contract and asserts the
  outcome (not a cassette recorded before the change, not a stub of the changed collaborator).
- Outside code, only the ticket: a requirement it states, or a decision `pr.md` marks as the
  user's (a locked-decisions heading, a line naming it a user decision) → `invented`, quoting it. It
  refutes only the behaviour it names: a decision on a value's source is silent on its empty value.
  With `TEAM=yes` and an approval rule in `rules.md` (a sensitive-change or AC-deviation sign-off), the decision
  refutes only if it is recorded the way that rule says — who, when, channel, and not the PR's
  author; otherwise keep a low K at the decision's line whose fix is that record, quoting the rule.
- With `TEAM=yes`, a gap between what `pr.md` or the plan states (which keys or roles may call, a limit, an
  environment, a count) and what the diff does is an intent defect, never `invented` for want of an
  actor who would exploit it.
- The author's rationale — PR body, README, plan, code comment, docs — never refutes a defect and
  never lowers its severity: keep the K and append ` | known: <file:line> "<quote>"` to its K line.
  A `pr.md` or README section another finding in this run shows is stale proves nothing.
- The PR discussion in `pr.md` (`## PR review threads`, `## PR reviews`, `## PR conversation`). A
  finding that a thread already raised is `duplicate` of that thread, quoting it, unless the thread's
  answer is wrong at TREE. An author's reply ("fixed in <sha>", "done") is testimony: check it at
  TREE. When the code at TREE still has the defect, keep the K and append
  ` | answered: <thread id> "<quote>"`. A decision a reply attributes to an approver counts as a
  ticket decision, under the same `rules.md` approval rule.

## External contracts

An API response, a webhook or message payload we send, a swagger or rswag schema, field names the
ticket specifies: the consumer lives outside the repo — never require its code, never call it
hypothetical. The contract is the ticket's field list, the swagger/rswag schema and the shape the
old code produced (`diff.patch` `-` lines, the old producer's empty value). Our output at the
boundary differing from any of them → reproduces, unless the ticket asks for that change. A
schema admitting both values (`nullable`) does not refute a change from the old shape; two branches
returning different empty values for one input is a finding. A message another service sends us is
the reverse case: its shape is a premise (Reality) until TREE holds a received one or its fixture.

## Procedure

1. **Load** `manifest.env`, `context.md` (`## Entry points`, `## External input`), `rules.md`,
   `files.txt`, `diff.patch` hunk headers and every `findings/*.md` (F rows and DECLINED lines).
   Expected: quick = `all`; thorough = `code`, `fit`; in exec mode also `codex` when `findings/codex.md` exists.
   Codex is another model, run as one more finder; its rows get the same rules as every other row. Every F claim opens with its `[checklist]`;
   the per-lens rules below apply to the rows of that checklist. A missing or unparsable file → `incomplete: <lens>` in the BLOCKING reason.
   Ignore every severity word a finder wrote. Code only under TREE — in pr mode never the checkout.
2. **Audit DECLINED.** A finder declines for two reasons only, each line tagged: `pre-existing`
   (step 7) or `linter` (an enabled rule in the linter config under TREE, config line quoted).
   Promote to a candidate `<lens>/D<k>` (k = its position among that file's DECLINED lines) every
   line that is untagged, gives another reason (known, documented, deliberate, pinned by a spec,
   convention, self-heals, `AC<n> implemented`), or whose citation does not say what it claims
   (the quoted text lacks the declined subject, the `file:line` is in a hunk or newly reached, the
   rule is disabled or absent). Its claim is the declined suspicion — for `AC<n> implemented`,
   "AC<n> is not met", refuted only by quoted lines carrying each field the criterion names. It
   goes through steps 3–12 like an F row; `in` = F rows + promoted D rows.
3. **Check the quote** at the cited `file:line` under TREE. There or elsewhere in the same method →
   correct the line and go on; not in the file → `invented`, quoting what the line actually says.
4. **Trace the path** from an entry point in `context.md` — or a route, job `perform`, webhook,
   rake task or callback you find — to the cited line, one hop per quoted `file:line`. Before
   concluding there is none, check the Rails dynamic forms (routes → action, `before_action` and
   model callbacks, `perform_later`/`perform_async`, `delegate`, association and scope names,
   `send`/`public_send`/`constantize` on a built string): a failed literal grep proves nothing
   while one can reach it. No path → `invented`, quoting the dead end (the grep and its scope, the
   unreachable branch, the ruling constant). A hop you cannot resolve (dynamic dispatch, a producer
   outside TREE) caps it at possible, `settle` naming that hop; an external consumer is no such hop.
5. **Name the input** that takes that path to the bad outcome; when `pr.md` names an account,
   record or request, use that one.
   - External input (params, webhook or partner payload, job args) → reproduces when the value
     passes every guard between the boundary and the line; quote the permit/parse line.
   - Internal state (a column value, a missing association, a cache entry, a row an older release
     wrote, a blank setting) → reproduces only when TREE shows a writer that produces it or
     `pr.md` reports it; otherwise possible, `settle` = the query that would count it (table,
     column, filter set).
   - Timing (concurrent requests, a retried job, callback order) → reproduces when the code
     shows both paths overlap with nothing serializing them — quote the retry config, second
     worker, schedule or queue, the absent lock or unique index; otherwise possible.
   - A nil, error or `false` counts only with the path from an entry point that produces it.
6. **Validation boundary.** Input is validated once, where it enters from outside (`context.md`
   `## External input`: params, webhook, partner callback, job or rake args). A finding asking to
   guard or nil-check inside our own call chain → trace the callers up. Strong params, a model
   validation, `.present?`/`presence`, a raising `find`, middleware, a `before_action`, a guard
   upstream, an earlier step that guarantees the row (a `find_by` after the step that created it),
   our own sole caller guaranteeing the value → `needless-validation`, quoting that guard. It stands
   when an external entry reaches the line unguarded (quote it) or the line is itself the boundary.
7. **Diff scope.** A line outside every hunk of `diff.patch` → `pre-existing`, unless the diff makes
   it newly reachable (adds a caller, removes a guard before it, widens its input) — quote which.
8. **Rules.** A convention finding is kept only with two quotes: the rule at `rules.md:line` (name
   its `## <path>` heading; a `## team rules` section names its `T<n>`) or `lenses/rails.md:line`,
   and the violating line;
   reality reproduces, trigger `convention: <rule location>`. Otherwise, and for a rule the code
   silences (`# rubocop:disable`) or a CI linter enforces (quote the cop), `nit-no-rule`.
9. **Gate.** Correct for THIS codebase (Rails version, gems, schema)? Would the fix break a caller
   or existing behavior? Does code or the ticket refute it («What refutes»)? Did the finder see the
   whole context? Then run «Reject when»; a failure is rejected with the line that answers it.
10. **Merge.** Two findings share a root cause only when the same defect produced both — the same
    line or fix alone is not one. Merge into one K: every id in `from`, the most concrete trigger,
    the highest severity. A rejected finding restating another R or K → reason `duplicate`,
    `same as R<j>` / `K<j>`.
    Every F and promoted D lands exactly once — in one K's `from` or one R row whose claim begins
    with `<lens>/F<k>` or `<lens>/D<k>`. Check: `in` = Σ `from` entries + rejected.
11. **Grade** — finder severities ignored. One rule per kind of finding, the same for every kept
    finding whichever lens raised it and whether or not the ticket, an issue or a human reviewer
    names it. Before calling an impact limited, follow the `breaks` chain to where it ends — an
    aggregate, a decorator's pick, a response, a partner field, a watermark; a finding raised as a
    missing spec or guard is graded by that chain, not by the missing spec.
    - high: reproduces, reachable today at this sha (the trigger quotes a path from an entry
      point under TREE), AND at least one of: silent data loss or corruption (a run marked success
      that did no work; a watermark or cursor advanced past rows never processed); wrong data
      persisted; an external or partner contract broken («External contracts»); an unbounded
      request or job flood (an automatic path sending far more than the rate `pr.md` states, no
      budget in settings); a security hole (auth/IDOR, injection, secrets). None nameable → med.
    - med: reproduces with limited impact a user or partner sees, or possible with high impact.
      possible is never above med.
    - low: possible with limited impact (kept, with `settle`); reproduces whose only effect is
      what an operator sees (a console count, a log line, a duplicate row a one-off backfill
      writes); a convention, style, YAGNI or DRY violation named in `rules.md`,
      `lenses/rails.md`, quoted per step 8 — named in none → `nit-no-rule`.
    - perf: a finding whose `lenses/rails.md` «Signal → pattern» row is quoted from a changed line
      is kept — possible goes to med, never `invented` for an unshown volume or as generic («Reject
      when»); `settle` = `EXPLAIN (ANALYZE, BUFFERS)` of the new query, table and filter set. It is
      refuted only by the ticket, a user decision naming that shape, or a `rules.md` line that
      prescribes how to write that code and that this PR did not add; a feature description in
      `rules.md`, `pr.md` or the plan is `known:`, not a refutation.
    - tests lens: a verification gap alone breaks nothing for a user today → med at most, and only
      with the regression and the green spec quoted. If it shows the code is wrong, grade that defect.
    - intent lens: a `missing`/`partial` criterion is high only when the ticket asked for it
      explicitly (quote the `pr.md` line) and TREE confirms the gap; one read into the ticket →
      med. A PR claim the diff does not back, or scope creep that changes behavior → med; scope
      creep with no behavior change → `nit-no-rule`.
    - BLOCKING yes iff any K is high; the reason names those K ids, or says `no high`, plus any
      `incomplete: <lens>`.
12. **Write** `verdict.md`: K rows high → med → low, then R rows.
    - `trigger`: entry → hops → input, each hop with `file:line`; `proof`: the line(s) at fault.
    - `explain`: for the user, plain English, 1–3 sentences: what the user of the product
      sees, then one sentence naming the mechanism. No file or class names up front.
    - `comment_en`: a teammate's PR comment, English, ≤4 sentences: what breaks for which input,
      why (the line), the concrete fix when the code makes it clear, else what must hold. No
      praise, no "consider / verify / ensure / double-check", no emojis, no AI attribution.
    - `settle` (possible only): the one piece of evidence that would make it reproduces — a query
      with table, column and filter set, the caller that would produce the input, or the log line.
    - R refutation: the code or ticket `file:line` that disproves this claim («What refutes»). A
      true fact about nearby code is not one; "self-heals" or "the next run picks it up" refutes
      only with the line showing the next run reaches that row.
13. **Return** one line, `VERIFY · <in> in · <kept> kept · <rejected> rejected · blocking yes|no ·
    <pkg>/verdict.md`, and write nothing outside `<pkg>/`.

## Reject when

- Already handled in the diff or upstream (a re-raising handler, `rescue_from` → a declared 4xx),
  or the ask restates the code → `invented`; `needless-validation` when the ask is a guard or the
  value is already guaranteed (Reality).
- Code raises loudly on a state you never showed the program can reach → `invented`.
- Generic "missing validation / rescue / rate limit / auth / index" with no concrete input that
  produces a wrong outcome → `invented`.
- A pedantic nitpick a senior engineer would not raise; style not named in `rules.md`, the rails
  lens; what the CI linter catches; a rule the code explicitly silences → `nit-no-rule`.
- "Lack of test coverage" with no named regression, unless `rules.md` requires that test →
  `nit-no-rule`.
- Data loss, authorization/IDOR, injection, secrets, concurrency and public-contract findings are
  never rejected as "unlikely" or "small" — only on a quoted code counter-line.

## Sources

- `verify anthropics/claude-plugins-official plugins/code-review/commands/code-review.md`
- `verify obra/superpowers skills/receiving-code-review/SKILL.md`
- `verify EveryInc/compound-engineering-plugin skills/ce-code-review/references/subagent-template.md`
- `verify kodustech/kodus-ai libs/code-review/infrastructure/agents/prompts/verifier-prompt.ts`
- `verify bmad-code-org/BMAD-METHOD skills/bmad-code-review/step-03-triage.md`
- `verify EveryInc/compound-engineering-plugin skills/ce-code-review/references/validator-batch-template.md`
- `verify affaan-m/ECC agents/code-reviewer.md`
- Not in the lock: the user's own rules, if any.
