# Triage rules

Two independent judgments per ticket. The **batch** answers "what can be fixed together"; the
**light** answers "can it be started right now". A ticket can be 🟢 in a batch nobody is working
on, and 🔴 in the most active one — keep them separate. The light and priority rules below hold on
every board. The batch table, the `classification.json` key names, the `Status` field ids and the
board's own examples live in `~/.claude/sin-flow/profiles/<key>/board/rules.md`.

## Batch — decided by where the fix lands, not by the surface the bug shows on

Classify a ticket against the batch table of its board. The surface a bug appears on is a weak
signal: confirm the file the fix lands in before choosing a batch — that changes both the batch and
who can take it.

A batch whose name says "verify upstream" is for a symptom that points outside the profile's repo
but is unproven. A batch whose name says "confirmed upstream" is for a fix that lands in another
repo: route it, don't fix it here, and name the upstream issue. A board with neither marks such a
ticket 🔴 with the other repo named.

Every batch in the table is shown on the page even when empty. An `Other` batch, where the table has
one, is only for tickets whose classification is unclear — never a home for small or odd work.

## Light — one vocabulary, all boards

Light answers "can it be started right now" — never complexity (boards carry `Size` for that).

| Light | Meaning |
|---|---|
| 🟢 green — Ready now | self-contained; root cause known or cheap to find in the profile's repo; nothing to wait for. Start now. |
| 🟡 yellow — Check first | something must be settled before code: a measurement through the profile's measurement route, a product or copy decision, a QA "verify X" ticket, or a **sensitive area** (the `sensitive:` line of the profile's `## Inferred`) that needs written approval first. |
| 🔴 red — Blocked upstream | cannot start until someone else acts: a vendor feed or data delivery, a DevOps/environment change, a change in another repo, or a decision owned by someone else. The row names who or what it waits on. |

**🔴 means "the fix is upstream", not "the symptom is data."** Mark red only with a named blocker;
"looks like a data problem" is 🟡 on every board. Tickets that read as upstream data problems have
turned out to be self-contained bugs that shipped from the profile's repo — which is exactly what
the verify-upstream batch and 🟡 exist for. Record the upstream issue number, vendor or repo so the
page can show what each red waits on.

**🟡 is also the right answer for QA tickets phrased as "verify X."** Those often describe expected
behaviour rather than a defect, and coding against them wastes the batch. Same for a copy or product
question dressed as a bug.

The board option labels are identical on every board (`🟢 Ready now | 🟡 Check first |
🔴 Blocked upstream`), so `fetch-board.sh`'s light map is shared. A local adapter returns the
light words `green`, `yellow`, `red` itself (`adapter-contract.md`).

## Priority

The board's `Priority` single-select field is unset in practice, so priority comes from the issue
body, where QA writes a `## Severity / Priority` section in mixed formats (`Priority: High`,
`Priority: P2 (medium)`, sometimes only a severity). Resolve in this order:

1. the board's `Priority` field, if it is ever set — it wins;
2. the body's `Priority:` line, normalised `P1|High → High`, `P2|Medium → Medium`, `P3|Low → Low`;
3. otherwise infer from severity and impact, and mark it `High (inferred)` so nobody mistakes an
   inference for a product call.

Escalating a stated priority is legitimate but must be marked — a `P2 (medium)` ticket whose
feature is completely unreachable on mobile is triaged `High (inferred)`. Store the resolved value
in `classification.json` so it isn't re-parsed (and re-argued) on every sync.

The resolved priority is the sort key inside each group on the page, whatever `group_by` is.

## Two checks before adding a new row

- **Duplicate of an existing ticket?** Keep the older number, note the duplicate in the digest, and
  don't give the same defect two rows.
- **Residual of a closed ticket?** Common, and *not* a duplicate. Real, self-contained, usually 🟢.

## Scope collisions worth flagging

When several tickets in different batches touch the same file or surface, say so — two people
batching them separately will collide in the merge.
