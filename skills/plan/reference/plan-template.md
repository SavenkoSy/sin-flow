# Plan template

`sin-flow:plan` Step 6 writes `~/.claude/sin-flow/work/<key>/<id>/plan.md` in exactly this order, in English.
`<unit>` is a ticket (`GH-N`, `<PREFIX>-N`, `#N`) or a story (`N-M`) — whatever the tracker names it.
A section with genuinely nothing in it says so on its own line; it is never dropped.

```markdown
# <id> — <one-line title>

status: verified — ready to execute · <date> · <model>
profile: <key>
repo: <slug>
base: <branch> @ <real sha>
exit: <carried from the seed: plan | epic>
branch: <branch per profile convention> (new | resume)
source: <carried from the seed, one line for each source>
ticket: <carried from the seed>
worktree: <path>
spec: <carried from the seed, when present>
after: <carried from the seed, when present>
measure: <measure.doc path | none> · sources used: <names | none>
RULING_NEEDED: measure before exec — <units>          ← only when Step 4 could not measure

## Decisions (locked with the user, <date>)
<the seed's locked decisions, verbatim, date kept — or "none: thin seed">

## What the measurement changed
| unit | seed assumed | measured |
<only the units that moved; "nothing moved" is allowed and will be doubted>

## Verdicts
| unit | verdict | layer | wave | builder | audit | files owned | depends on | UI |
verdict ∈ ✅ CONFIRMED · ⚠️ CONFIRMED, root cause re-attributed · ⚠️ PARTIALLY — scope shrinks ·
❌ NOT REPRODUCIBLE · 🔴 NOT OURS — upstream · 🆕 STORY (an intake story, nothing to reproduce)
A forcing-list hit names its trigger in the row.

## Waves
| wave | units | why one wave |

## Measurement
Route: <measure.doc>, preflight <result>. Browser route: harness `work/<key>/<id>/verify-<id>.mjs`,
the exact commands, env set from the doc. Data route: evidence files `evidence/<unit>.md`.
Every load-bearing probe: query or request · numbers · filter set (or the evidence path that holds them).

## <unit> — <title>                                      ← one section per unit, in wave order

### Decisions
<the locked decisions this unit implements, or "none">

### ✅ Verified — <how>
<raw measurement pasted, not paraphrased; reused seed evidence cited by path + spot-check number;
"not measured — <reason>" with the bounded query as exec step 1 when the route was down>

### Change
<exact before/after at file:line in the worktree; the analogue reused; every new file with its path;
the alternatives and why each loses>

### Every copy
$ <exact grep command>
<every hit at file:line → in scope | out of scope — <one reason>; or "1 hit, the file being changed">

### Every writer
<per column written or read differently: every other writer at file:line, its guard, carried yes/no;
or "no column touched">

### Traps
<what the change walks into — a fix that would ship a new bug, a plan-shape hazard, a redirect that
swallows a stream, a cassette that replays the old response>

### ↻ Re-verify after the change
<exact probe command or query + a before → after table; asserts the ticket's symptoms 1:1 at the
rendered layer>

### Tests
<existing files and what they assert now; what to add; what breaks; a discriminating test per named
trap; each new test fails with its hunk reverted>

### UI checklist                                        ← only when the profile has ui.visual_check
1. <URL> → <what must be visible> (on <ui.device> first when set)

### Not in scope
<what the ticket does not ask for, with the reason — never a defect found on the way>

## Gates
Run by exec's shipper: <gates.commands, or the `gates:` line of `## Inferred`; upstream mode: the commands `upstream.md` § Rules to read names>, cadence <final | wave>.
This plan adds: <e.g. gates.prepare after the migration in wave N | nothing>.

## Commit plan
One branch `<branch>` off `<base>`, one PR into `<base>`. Commits, in order: <unit → subject per
profile convention>. Migrations last. Restart / migrate steps if a schema changed.

## PR title
<every id that ships code, ascending, per profile convention — no no-code ticket>

## Finish line — standing authorization
Exec checks four things: each unit in this plan has its code, its own tests pass, its audit is clean
and the final review is clean. Then `sin-flow:exec` sends the `sin-flow:shipper` agent to push
`<branch>` and open the PR against `<base>`. Exec does this in the same session and does not stop.
This section is standing authorization. The user approved it already.

The executing agent does not ask. It does not offer to commit. It does not end its turn with a
finished diff in the working tree or with a branch that it did not push. Blocked units and units that
exec cannot verify do not hold the PR. Ship the units that passed, and write the rest into the final
chat message.

If the units that shipped code are not the same as the list in this plan, make the PR title again.
Use the units that shipped. Plan, evidence and harness stay in `~/.claude/sin-flow/work/`. Do not
commit them.

## Dispositions
| unit | no code because | what was done (comment link, status) |

## Found while verifying
<only a fix in another team's repo, as prose with its owner; everything else is a unit above>

## Rulings
- Ruling: <what>. Why: <why>. Cost if wrong: <cost>.
ingest-miss: <quoted seed line that leaves it open> → <the call> (rejected: <alternative>)
```
