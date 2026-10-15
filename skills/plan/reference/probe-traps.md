# Probe traps

Each trap has already cost at least one session. Read the relevant one before writing a probe, not
after it produces a confusing result. Traps that only apply to one repo's stack belong in that
repo's measure doc (`~/.claude/sin-flow/profiles/<key>/`), not here.

## A reopen may be a stale deploy

When the environment exposes no build SHA, a reopen filed after a merge does not prove the fix was
live. Re-run QA's exact sequence before believing it. If it does not reproduce, check
`git merge-base --is-ancestor <fix> origin/<deployed branch>` and what touched the file since, and
report the deploy-lag explanation as **unproven**, with the alternatives (stale build cache, wrong
host, partial rollout, trace captured pre-merge).

**Better: make the first probe a `deploy` probe.** Pick one or two *behavioural markers* whose value
provably differs before and after the fixes under test, and print them before anything else runs.
On one all-reopens batch this probe answered a ticket outright — the reopen was filed 45 min after
merge against a build that had not shipped. **Write the marker into every fix comment** so a retest
can prove the build is live. A merged commit and green CI do not prove a backend is deployed: probe a
route the fix adds (404 before, 401 after) beside a control route.

## One observation is not a rate

"~15–20 % of loads" off one event in six samples is an anecdote with a percentage attached; five
fresh reps of that case put the metric at one flat value, an order of magnitude under the threshold.
For any intermittent claim run ≥ 5 reps and print **every** rep, not the max. Identical reps mean a
deterministic cost and the "race" framing is wrong. State the rate measured and the rate needed after
the fix; no reproduction at all is the finding. Hover bugs: vary the number of pointer moves
(steps 1, 2, 3, 4, 6, 12 plus `hover()`), three reps each, every one printed.

## An API field is not what the user sees

A defect confirmed from a payload, and the user opens the page and sees the right value. Two
mistakes travel together: the read was never confirmed on the surface (the frontend can derive,
guard or ignore the field), and it happened once (a cached value over a flaky upstream samples a
moment). For anything a user sees, open the URL and read the DOM; repeat the API read ≥ 5 times.
Write "the API returns X" or "the page renders Y" — never "the tile shows X" unless you looked.

## A probe that measures something else

- **Fault injection:** when the source names one failing request, inject on that URL only, three
  modes — 404, 500, hang. For "UI races X", hold the request and drive every control.
- **A no-fault control** runs beside every fault-injection probe.
- **The ticket's own entry path** — a near-enough path measures a different code branch.
- **Concurrency needs processes:** `Promise.all` from one page multiplexes over one HTTP/2
  connection (0/14 double inserts); parallel `curl` processes read 13/14. Race, dedup and
  rate-limit probes fork processes.
- **The probe asserts its own visibility:** first lines print viewport, box, match count; abort when
  the element is off-screen or the selector matches more than one node. Wait on the selector, never
  on a fixed sleep.
- **Selectors die with the fix:** re-read each against the new DOM; every zero-count assertion needs
  a positive gate first (real rows exist).
- **Check-then-write races:** measure each sequential order. Never pipe an every-copy grep through
  `head`. End a harness with `process.exit(0)`.
- **Camera or media surfaces** leave `play()` pending headless, so headless "not reproducible" there
  is not evidence — ask the user before a headed run; never launch one on your own.

## The detached node

A sampler that watched an input produced one sample and then nothing. It captured
`document.activeElement` once; the framework remounted the node and the probe polled a corpse.
Tag the node, record on every tick both the tagged node and a fresh `querySelector`, and drive ticks
from a `MutationObserver`. `taggedConnected: false` while `liveCount: 1` proves a **swap**, not a
re-render — the harness's `node` probe does exactly this. Never hold an element reference across time.

## An actionability failure is not a user symptom

`subtree intercepts pointer events` proves a node is covered, not that the user cannot reach the
goal. Drive the gesture the feature is actually operated with (`mouse.down/move/up` for a slider, a
real keystroke for an input) and print the value before and after. Ask: had this click succeeded,
what would have changed? Nothing → the block is cosmetic.

## "I cannot sign in as that account" is usually false

The account the ticket names holds the state it describes; another account has different flags and
data. Sign in as it before ending with "not measurable on this account". The measure doc says where
the shared QA password lives; only the email varies, and QA pastes it into the ticket.

## Mutating probes

Capture a baseline, run the sequence, print every intermediate state, restore **from the captured
object**, print it again. Prefer an idempotent write (echo the stored value) so QA can re-run the
assertion indefinitely — a one-way field cannot be re-tested otherwise.

## Browser harness

`harness-template.mjs` carries sign-in with `storageState` reuse, an in-page authenticated `call()`
that returns status, headers and body (several defects are only visible in a response header),
console and HTTP-failure logging, and `example` / `mutating` / `node` probes to copy. It reads every
repo value from env; the profile's measure doc names them:

| env | meaning |
|---|---|
| `FLOW_ENV_FILE` | env file loaded first (credentials); never printed |
| `FLOW_BASE_URL`, `FLOW_API_URL` | app and API origins |
| `FLOW_SIGNIN_PATH` | sign-in page path |
| `FLOW_EMAIL_LABEL`, `FLOW_PASSWORD_LABEL` | form labels for the two fields |
| `FLOW_READY_EXPR` | JS expression, truthy once signed in |
| `FLOW_TOKEN_EXPR` | JS expression returning a bearer token; unset → cookies only |
| `FLOW_EMAIL`, `FLOW_PASSWORD_VAR` | the account (the one the ticket names) and the env var holding its password |
| `FLOW_STATE_DIR` | where sessions are stored, one file per account |
| `FLOW_BLOCK_HOSTS` | regex of hosts to abort (third-party scripts that break headless) |

Run it from the directory the doc names, `login` first, headless always (`HEADED=1` only after the
user says yes). Copy the finished script to `work/<key>/<id>/verify-<id>.mjs`; never commit it.
