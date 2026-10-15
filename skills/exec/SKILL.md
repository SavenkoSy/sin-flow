---
name: exec
description: Exec stage of the flow (ingest → plan → exec) for any repo with a flow profile. Executes an approved plan from ~/.claude/sin-flow/work/<key>/<id>/plan.md with subagents — the plan diffed against its GitHub issue first, implementers in waves (one message per wave when files are disjoint), a model and an effort named on every dispatch, a coverage audit per unit, one final review through the review pipeline, a visual check when the profile asks for one, every gate and git step through the `sin-flow:shipper` agent — then opens the PR without asking. A team repo gets the post-PR loop; a solo repo waits for the user's "merge" and merges by the user's `merge` preference (squash by default). Ends in the one final message defined here. Use when invoked as `/sin-flow:exec <plan path>` or handed a plan to execute.
---

# sin-flow:exec — execute the plan, ship one PR

Execute the plan at the path given. No path → one line, stop. Repo facts — base, gates, branch and commit shape,
tracker, UI check, who merges — come from the profile, never from this text.

Chat with the user in `chat_language` from `~/.claude/sin-flow/user.md`, or in the language the user writes in when it is absent. Headings and fixed phrases defined here are rendered in that language. Files, commits, PRs and issues are always English.

## Inputs

- **Plan**: `~/.claude/sin-flow/work/<key>/<id>/plan.md`. `<key>` and `<id>` are its two parent folders. The plan's folder
  is the **workspace**: `progress.md` (the ledger), `briefs/`, `evidence/`, `pr-body.md`, `gate-*.log`,
  `final-review*/`, `playwright/`. Nothing of it is ever written inside the repo — agent notes never go into a
  product repo.
- **Profile**: `sin-flow-profile validate` first, silently. A failure is handled as `/sin-flow:setup` says (no profile → run
  its onboarding here and continue; `gh` not logged in → one line with the fix, stop; a gate that cannot run → stop
  before the first wave with the fix). Then read the profile once: `sin-flow-profile <key> get <group.key>` for keys, the
  `## Inferred`, `## Run`, `## Never` sections for prose. An agent with a clean context gets only the section it needs,
  pasted into its brief.
- **Models** — before the first dispatch run `sin-flow-profile model strong`, `sin-flow-profile model mid` and
  `sin-flow-profile model cheap` once and write the three aliases to the ledger. `<strong>`, `<mid>`, `<cheap>` below
  mean those aliases; pass the alias as `model`, never the tier word.
- **User preferences**: `~/.claude/sin-flow/user.md` (chat language, branch prefix, hand-off launcher, reviews folder);
  absent → the defaults `/sin-flow:setup` names. They are the user's, never a repo's.

## Models — name a model AND an effort on every dispatch

The main session's model is never changed — switching it breaks the prompt cache. An omitted model inherits this
session's and burns it on mechanical work.

| Role | Agent | Tier | Effort |
|---|---|---|---|
| Implementer | `sin-flow:implementer` | `builder:` from the plan's verdicts row | medium; high when `builder:` is strong (or legacy `opus`) |
| Implementer, fix round 3 | `sin-flow:implementer` | strong | high |
| Coverage audit, scoped re-review | `sin-flow:read-only-analyst` | mid | low |
| Adversarial check, the user's code question | `sin-flow:read-only-analyst` | mid | medium |
| Final review | `sin-flow:reviewer`, one per lens | the lens table in `${CLAUDE_PLUGIN_ROOT}/skills/review/reference/pipeline.md` | the table's; none named → medium |
| Visual check | `sin-flow:implementer` | mid | medium |
| Gate, commit, push, PR | `sin-flow:shipper` | mid | low |
| Rebase onto a moved base | `sin-flow:implementer` | mid | low |

`builder:` and `audit:` come from the plan. `builder:` is a tier — `cheap`, `mid` or `strong`; a plan written before
tiers says `haiku`, `sonnet` or `opus`, read as cheap, mid, strong. You may raise either with the reason in the
ledger — cheap → mid when the brief carries no exact code, mid → strong when the diff hits the plan's forcing list.
Never lower one, never raise one because you are unsure. A row with no value is a plan defect: treat it as mid / run
and ledger it.
Purpose-made agents only — never `general-purpose`. A model comes only from the three resolved tiers; never name one
outside them. No subagent has a turn cap (`maxTurns` is inert, measured): keep briefs small and split a unit rather
than trust an implementer to stop.

## The orchestrator does not run the work

The dispatching thread is the most expensive place in the chain when it fills with Bash output.

- Bash here is bookkeeping: `ls`, `git status`, `git diff --stat`, `git diff` into a file (`git add -N` first for new
  files), writing a brief, a ledger append, the issue diff. Never a test run, a build, a log tail, a grep over app
  code, `git commit / push / reset / rebase`, `gh pr create` — those go to `sin-flow:shipper` or an implementer.
- Output whose size you cannot predict goes to a file you `grep -c`.
- A return block is your artifact. Never re-read the report it points at.

## Setup

1. **Ledger.** `progress.md`, first line `# ledger — plan: <path>`. A ledger already naming this plan means resume:
   every `Unit <u>: complete` line is done — never re-dispatch it. Args with `continue:` → read that text,
   `git status --short` and the ledger's hand-off section before anything else; a named PR URL means this session
   owns the post-PR phase and nothing is re-implemented.
2. **Plan vs issue, before anything else.** The plan is mirrored when the header's `ticket:` is a GitHub issue and
   the profile's `## Inferred` notes line says so (`notes.mirror` not `off`): the issue body when the user authored
   it, the `<!-- sin-flow:plan -->` comment otherwise. Not mirrored → skip. Otherwise `gh` the mirror into `<workspace>/issue-plan.md` and `diff` it
   against `plan.md`. They differ and the issue was edited after the file's mtime → the issue wins: write it over
   the local file, ledger `plan: issue newer, taken`. The file newer → ledger `plan: local newer`; it is mirrored at
   Finish.
3. **Read the plan once.** Header, verdicts, waves, Finish line. **`exit: hotfix`** in the header (a one-block plan
   from ingest) is one unit: `## Files` is its ownership, `## Tasks` its brief, `## Verification` its definition of
   done, `## Gates` the `commands` for every `sin-flow:shipper` gate; `builder: mid`, `audit: run`; review depth quick, one
   round; the rest of this skill applies unchanged. A unit marked `RULING_NEEDED: measure before exec`
   does not start until the user says «without measuring» — every other unit goes on; say so in one line.
4. **Base and branch.** Base = the plan header's `base:`, else the profile's base (`repo.base` or `## Inferred`).
   A base that is not ready never stops you: when the plan depends on an unmerged branch or PR, start from that
   branch, otherwise from a freshly fetched `origin/<base>`. The header's `worktree:` exists → work there
   (`EnterWorktree`). Otherwise, when this checkout is busy — a dirty tree, another branch, another session in it →
   `git worktree add .claude/worktrees/<id> -b <header's branch:> <base>`, `EnterWorktree`, everything there. No
   `branch:` line → `sin-flow:shipper` names it by convention on its first `local` / `commit`. Never work on the base branch.
   Ledger `Base: <ref> (<why>)`.
5. **Sensitive paths.** The repo's `.claude/sensitive-paths.txt` (or the profile's `sensitive_paths`): match the
   plan's files against it. A hit adds `<ATTENTION>` to the commit subject and the PR title, and the PR body names
   the area and old → new. Ledger the hit. That prefix is the whole mechanism: do not stop, and do not write the
   repo's sensitive-change record — it records an agreement, so it is added after one exists. An implementer
   reaching for a sensitive path the plan never listed: halt that unit, ledger it, report it — never widen scope.
6. **`global-constraints.md`** once: the plan's binding rules, the repo `CLAUDE.md` rules a reviewer fails someone
   on, the profile's `## Never` and `## Run`, verbatim. **`review-preamble.md`** once: no subagents, read-only, do
   not trust the report, output format. Every dispatch points at both.
7. **Conflict scan → waves.** One row per pair of units sharing a file or an interface (what one produces vs what
   the other consumes, your ruling); one row per unit (does its own text agree with itself). Shared by default:
   schema dumps, route tables, locale files, lockfiles, navigation components. A unit with a migration sits alone in
   its wave. A consumer sits after its producer. Confirm the plan's wave table against the scan — a shared file the
   plan missed moves a unit to a later wave. Write the final waves into the ledger before the first dispatch.
8. Set the header's `status:` line to `in-progress` (added when the header has none).
9. `repo.fork` set → § Upstream mode below, before the first dispatch.

## Per wave

**Briefs first.** One `briefs/unit-<u>.md` per unit. First line: read `<workspace>/global-constraints.md` before
anything. Then: files it owns and files it must not touch (the plan's `### Every copy` split into those two lists —
no such block is a plan defect, ledger it), the interfaces earlier units froze, `builder:` / `audit:` verbatim, your
rulings that override plan text, the spec files it runs, its definition of done, and the sibling note — other
implementers may be editing other files in this checkout right now; never run a whole-project test or lint, only
the specs and files the brief names. Exact values live only in the brief; a subagent never reads the whole plan.

**Dispatch the wave's implementers in ONE message** (parallel when files are disjoint), each with
one line on where the unit fits, the brief path, the report path `briefs/unit-<u>-report.md`, the branch, its model
and effort. Same-shape small edits in different files → one implementer, one brief, the highest `builder:` and
`audit:` of the merged rows. Never two implementers on overlapping files: the later unit waits.

**Return block** `TASK / STATUS / FILES / TESTS / DEFERRED / RULING_NEEDED` (`${CLAUDE_PLUGIN_ROOT}/agents/implementer.md`).
Ledger it. A `DEFERRED` line is this PR's work: it enters that unit's fix loop as a finding. A `RULING_NEEDED` line
is yours: `Ruling: …` in the ledger; if it changes the unit, resume that implementer with the ruling. A block that
does not parse is not a red: re-dispatch once to a fresh implementer with the schema restated and the report path it
already wrote; malformed again → ledger it and hand the unit to the final review as unverified. Never spend a fix
round on a reporting failure.

**Coverage audit**, when the plan says `audit: run` (`skip → run` with a reason; `run → skip` never). Materialise
`git diff <base> -- <its files> > briefs/unit-<u>-diff.txt`, check `grep -c '^diff --git'` against the file list,
dispatch one `sin-flow:read-only-analyst` with the brief, the report and the diff. One question: **what did the brief require
that no test asserts?** Findings only: a requirement with no covering test; a test that passes with the code it names
deleted; a test asserting a constant production also uses; a listed file the diff never touches; a spec deleted where
retargeting kept coverage. ≤ 30 lines, no code-quality judgement. The audits of wave N, any re-review of a fix and
any adversarial check go out **in the same message** as wave N+1's implementers.

**Fix loop, 3 rounds max, per unit.** Rounds 1–2 resume the original implementer with the findings verbatim; round 3
a fresh implementer on `<strong>`. Each round ends in a scoped re-review of the fix diff: ADDRESSED / NOT ADDRESSED per
finding, plus `${CLAUDE_PLUGIN_ROOT}/skills/review/reference/lenses/paths.md` on that diff. At the cap, rule on each open finding and ledger it.
Never fix findings yourself.

**Wave gate** — only when the profile says `gates.cadence: wave`. When every implementer of the wave has returned and
every fix loop is closed: `sin-flow:shipper` mode `gate`, `label: wave-<k>` (log `<workspace>/gate-wave-<k>.log`). It returns
`STATUS: green | red` and, on red, `TAIL:` — the path to the failing tail. Red → attribute by the failing paths to a unit in this
wave and run one fix round there (the tail is the finding); a red you cannot attribute is a plan defect — `Ruling:`
and stop the wave as blocked.

**`sin-flow:shipper` prompt**, every mode: `mode`, `profile: <key>`, `id: <id>`, `work_dir: <workspace>`, plus the mode's own
fields (`${CLAUDE_PLUGIN_ROOT}/agents/shipper.md` § Prompt). Its return block (`MODE / STATUS / PROFILE / BRANCH / COMMITS / LOG /
TAIL / PR / MERGE / NOTE`) is all you read. `STATUS: blocked` → its `NOTE` is a finding: rule or fix, never bypass.

**Commit unit** — the profile's `git.commit_unit` (e.g. one commit per plan unit) → after the wave, `sin-flow:shipper` mode
`local` per unit in wave order: the unit id, its title in English (translated when the plan's is not), its `FILES`,
one paragraph on what changed and why. No such key → nothing is committed until the final review.

`Unit <u>: complete (<sha | uncommitted>, audit clean | skipped)` — move on without checking in. Do not stop between
waves. Do not ask.

## Final gate and final review — once, through the review pipeline

1. **Gate.** Cadence not `wave` → `sin-flow:shipper` mode `gate` now (`label: final`), red handled as the wave gate.
2. **Commit.** `sin-flow:shipper` mode `local`: branch and commit the work, no push, no PR — the package sees committed work
   only, and the main thread never commits itself.
3. **Package.** `bash ${CLAUDE_PLUGIN_ROOT}/skills/review/reference/build-package.sh exec <base> <workspace>/final-review --intent <plan path>
   --notes <workspace>/progress.md --depth <thorough when the profile folder has review-team.md, else quick>`. It
   prints only the package path `<pkg>`; a non-zero exit is a broken call — fix it, never hand-build a package.
   Check `grep -c '^diff --git' <pkg>/diff.patch` against the union of all `FILES`, then
   `cat <workspace>/global-constraints.md >> <pkg>/rules.md`.
4. **Run** `${CLAUDE_PLUGIN_ROOT}/skills/review/reference/pipeline.md` as written, every lens as `subagent_type: sin-flow:reviewer` with the lens table's
   model. Each reviewer returns one line — ledger it. Read `<pkg>/verdict.md` only; never open `findings/`. Render
   the review file into the reviews folder (user preference) as `<key>-<branch>.md`.
5. **Rows → one fix dispatch.** `reproduces` rows and `possible` rows of every severity go into ONE fix dispatch,
   every K block verbatim. A `possible` row is fixed the way it proposes, with a spec asserting the fixed behaviour
   («measure the settle → fix what reproduces»). Two exceptions, only these: the plan's text already accepts this
   exact risk, or the measurement the row's `settle` names was run and refutes it — ledger `final-review settled:
   K<n> — plan:<line> «<quote>»` or `— measured: <number, filter>`. «Reopens a plan decision» without a quoted line,
   «a new mechanism», «outside this ticket», «a separate PR» are not exceptions. Rejected rows → one ledger line `final-review
   rejected: <n> (<reason> <count>, …)`.
6. **After the fix**: scoped re-review, `sin-flow:shipper` `gate` (when the fix touched code), `sin-flow:shipper` `local` (`commit` once a PR exists) — a NEW
   commit, never an amend. **Review until clean** when the profile folder has `review-team.md`: steps 3–5 again on
   the fix commits only (`build-package.sh exec <SHA= of the previous round's manifest.env> …-<round> --depth quick`)
   — every line the fix wrote gets the lenses; code an earlier round passed is not reviewed again. Stop when verify keeps no row step 5 does not
   settle; at most 3 rounds; rows still open → ledger `final-review open: K<n> — <claim>`. No team file → one scoped
   re-review after the fix, no second round.

## Visual check — when the profile sets `ui.visual_check` and a unit has `UI surface: yes`

Follow `reference/visual-check.md` (one source; do not restate it). Dispatch one `sin-flow:implementer` (`<mid>`, medium) with
that path, every unit's `### UI checklist`, the ledger's `Ruling:` lines that changed a rendered surface, the profile's
`ui.*` values and `## Run`, and the label `<id>`. It returns `VISUAL / RESULT / FAIL / SHOTS`; ledger it. Red → one
fix dispatch with every `FAIL:` line, the check again, then `sin-flow:shipper` gate + `local`. Still red → those items reach the
final message as «not checked», and the PR ships. No rendered change → ledger `Visual check: skipped — no UI
surface`.

## Finish — ship, then report. The PR happens before the final message.

1. **PR body** `<workspace>/pr-body.md`, ≤ 200 words, English, in the shipper's shape (§ Mode `ship`: the `[<ID>]`
   signature, a non-closing `Ref #<N>`), then three headings: **Why** (the goal, from the plan
   header), **What** (one line per shipped unit), **Rollback** (revert of the merged change; a step the deploy needs
   reversed, if any). A heading with no content says so. Nothing else — no test plan, no checklist, no decisions, no
   deferred rows, no AI attribution. Before writing it, reconcile against `git diff --stat <base>`: a file the body
   does not account for means the body is wrong. The diff carries no agent notes — a plan, ledger or evidence file
   in it is a defect: `sin-flow:shipper` removes it before the push.
2. **`sin-flow:shipper` mode `ship`**: branch, base, PR title in English (the plan's, translated when it is not, with the
   tracker prefix the profile's convention gives and `<ATTENTION>` when step 5 of Setup hit), `body_file`. It pushes
   the branch (never the base) and opens the PR; ledger its `PR:` and `MERGE:` (the user's merge method).
3. **Mirror**. Set `status: shipped` in the plan header. Mirror on (Setup 2) → write `plan.md` back to the issue
   copy it came from; over 60 000 bytes → the first 60 000 plus «continued in comments», the rest as comments. Append `Plan <id>: shipped <URL>` to the ledger.
4. **Waiting plans.** No `spec:` line in the plan header → skip. Otherwise, for every plan in the spec's map with
   `after: <this id>`: same repo → `git -C <its worktree> rebase <this branch>` (it has no commits yet), then
   `sin-flow-handoff --cwd <its worktree> --name plan-<its id> --model <strong> sin-flow:plan <its plan path>`. This launches
   another plan's stage, not a hand-off of this session. Non-zero exit → one line with the command, go on.
5. **The final message** (below), then the post-PR phase that fits the repo — same turn, no pause.

**Never ask before pushing or opening the PR** — except § Upstream mode's first public write — and blocked units do not hold it: a plan where 8 of 9 units are
green ships those 8, and the ninth is a line under NOT AS IN THE TICKET.

## Upstream mode — `repo.fork` set

`U=${CLAUDE_PLUGIN_ROOT}/skills/ingest/reference/upstream.md`. Read the files of `U` § Rules to read at `origin/<base>`
(`git show origin/<base>:<path>`) at Setup 9 and again before the PR body. An AI ban → `Plan <id>: blocked` with the
quoted line. A required trailer → `trailer` on every `sin-flow:shipper` `local` / `commit`; a subject or title format →
every `title`; `## Gates` → every gate's `commands`. No plan mirror (Setup 2, Finish 3). The PR body follows `U` § PR
body (the diff-stat reconcile stays). `upstream.first_issue` absent → the PR is the first public write: show the exact
title and body, dispatch `ship` only on the user's "yes", then add `upstream.first_issue: <PR URL>` to the profile
frontmatter (`U` § Write policy). After the PR: the team loop; replies follow `U` § Review replies («Done in <short
sha>» for a fix), no «The plan and evidence are in #<issue>» reply, no «ready to merge», no re-request.

## After the PR — who merges decides the loop

`repo.fork` set → team. Otherwise `team` from the profile key; absent → the `## Inferred` team line; neither → more than one author among the last 20
merged PRs means team. **Team → the post-PR loop. Solo → the user's review.**

### Solo — the user's review

1. Screenshots exist → the closing line of the final message names their folder (absolute path) — the user looks
   and deletes them.
2. **No server.** Bring the app up only when the user asks to look — then as the profile's `## Run` says, deep-linked to
   what changed, and for each changed screen one line with the path a user takes to reach it from the start page
   (sign-in and role included) — a link alone does not say how to get there. If you started one, shut it down once the user approves; if the user rejected something, it stays
   up.
3. A state the app cannot reach on its own (an empty table a check needs rows in, a role the user must be in) → hand the
   user a console snippet that uses the repo's own write path, never raw inserts; run it only when the user says
   «you run it».
4. **Wait for the user's verdict.** This is the one place where waiting is correct: shipping was pre-authorized,
   judging is the user's. Do not declare the work done, do not start the next plan. The user's findings come back
   **collected, not one at a time**: one implementer on the touched unit's `builder:` (mid when they span
   units, strong only when the forcing list is hit), the visual check again when a rendered surface changed, then one `sin-flow:shipper` gate + `commit` (commit and push)
   for the batch (a new commit, never an amend); ledger `Round <k>: complete (<sha>)`.
5. **Merge on the user's word.** "merge", or an approval that says so → `ExitWorktree` if you are in one, then
   `bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/reference/merge.sh <PR> <MERGE from the ship block>` — it waits for checks,
   merges by that method (squash when empty), deletes the remote and local branch, removes the worktree, fast-forwards
   the local base without ever switching the main checkout's branch, and prints the merge commit. Ledger
   `Plan <id>: merged <sha>`, `status: merged` in the plan header; one line back. Non-zero exit → paste its output and stop; never re-run its lines by hand (2026-10-13: a
   hand-inlined copy deleted the branch after a failed merge and GitHub closed the PR).

### Team — the post-PR loop

The PR is ready until a point reproduces. The user does not merge here; the team does.

1. **State.** `gh pr view <url> --json state,reviewDecision,reviews,comments,mergeStateStatus > <workspace>/pr.json`,
   grep it. `BEHIND` or `DIRTY` → one rebase round onto the base — an `sin-flow:implementer` on `<mid>`, effort low, rebases and pushes with
   `--force-with-lease` (the shipper never rewrites history) — your branch, not a question. Size the check by `git range-diff <old base>..<old head>
   <new base>..HEAD`: only docs, deploy-notes numbering or generated API docs in it, and no new base commit touches
   a non-doc file of the branch → the range-diff plus the repo's doc checks, then push — no full gate, CI runs the
   suite. Any code or spec line,
   or a base commit in a non-doc file the branch touches → `sin-flow:shipper` `gate`.
2. **Bot review.** One call: does any of the repo's last 5 merged PRs carry a review-bot comment? None → ledger
   `bot: none (0 of 5 PR)`. Any → the bot's comments are a teammate's points: step 4.
3. **The user's review** → one fix round. The user's questions about code → a `sin-flow:read-only-analyst`. A
   question that reopens a product decision is not a task here: answer from the plan's `ingest-miss:` line and the rejected alternative
   beside it; reversing it is the user's call.
4. **A teammate's review.** Re-run step 1 first. Per point, by its severity label (none → by what it claims):
   - **low** → a reply, never a fix.
   - **medium** → reproduce it: a failing spec, a measured row, a read-only query by the profile's `## Measure`.
     Not reproduced → a reply, no fix.
   - **high** → the same re-verification; reproduced → step 6, not reproduced → a reply.
   - **A request for the plan, docs or evidence in the PR** → never a fix, never a docs commit; one reply, verbatim:
     «The plan and evidence are in #<issue> — everything is there.»

   A rare or unobserved
   case — a volume, a limit, a race, a row that may not exist — with zero rows is not reproduced. Every reply is
   short, in English, and argues the PR is ready: what was checked, the number or the reason, «not changing; ready to
   merge». Only reproduced points reach step 6; only a point that reopens a product decision goes to the user, all
   such points in one question. Never ask the user whether to fix or guard a point — this step decides. The user
   comes back after your final message → this step for everything posted since, then your answer.
5. **Base watcher** — every team PR, and any PR whose base is another feature branch. Before ending the turn, start
   one background Bash (`run_in_background`): every 10 min, up to 24 h, `git fetch -q origin` and
   `gh pr view <url> --json baseRefName,mergeStateStatus,reviews,comments`; it exits when `baseRefName` changed, the
   state is `BEHIND` / `DIRTY`, a review or comment by anyone but the PR author and a deploy bot is new since the last
   check, or — only when the base is another feature branch — the base has commits the branch lacks. On wake → a new
   review or comment: step 4, then start the watcher again; otherwise the rebase round of step 1, the push, one line
   to the user.
6. **No fix is pushed unreviewed.** One batched round for every reproduced point and the user's: fix each point
   where it was flagged and in every sibling of the same pattern on the branch (the flagged query → every sibling
   query; the flagged error list → every rescue of that client) — points fixed in one place only came back three
   times. Then Final review step 6 on the fix commits, then `sin-flow:shipper` `commit` — commit and push (a NEW commit, never an amend — a separate commit shows the reviewer only the change), then a reply in each thread with
   the fix SHA. `tracker.board` set and every point of a reviewer's review fixed or answered → re-request them:
   `gh api -X POST repos/<repo>/pulls/<n>/requested_reviewers -f 'reviewers[]=<login>'`.

## Final message — the one definition

Every flow stage that ships a PR ends with this message, and only this one. The user reads it to learn what the
product does now, not how the run went. Plain words, in the chat language. A line or a heading is written only when
it carries something; never one that says «none» or «nothing».

Shape — ≤ 15 non-blank lines from the signature to the closing line. Write it to `<workspace>/final.md` first;
`grep -c .` over 15 → merge or cut lines until it fits, then print it:

```
<ticket or plan id> · <PR link>

**WHAT WE DID**
**HOW IT WORKS NOW**
**NOT AS IN THE TICKET**
```

- The signature line — the ticket or plan id and the PR link — sits above the headings; it is not a heading.
- **WHAT WE DID** — what changed in the product, one line per shipped piece, in the ticket's words.
- **HOW IT WORKS NOW** — the product after the merge as its user or the calling system sees it: what starts it, what
  happens, what comes out. Behind a flag → off, then on. Something that must happen at deploy (a migration, a
  console step, a schedule) is one plain line here.
- **NOT AS IN THE TICKET** — only when something works differently from what the ticket or the plan asked: a
  `Ruling:` that changed behaviour, a unit that did not ship, a user's order that reversed the plan, an item left «not checked».
  One plain line each — asked → now → why.
- Solo repo only, closing lines: each screenshot (up to 3; more → the folder) as its own absolute file path on its own
  line with what it shows in a few words; then how to try the change after the merge (the page or the command), when
  HOW IT WORKS NOW does not say it; then «say "merge"».

Never in it — they live in the PR body, the plan or the ledger, and the user asks for one when needed: code identifiers,
class, table or column names the ticket does not use, `file:line`, SQL or any query, rule / task / finding codes,
test, lint, review or CI figures, findings closed without a fix, a «Not fixed» list, a «Result check»
section, who waits for what, bot, session or ledger lines, account-limit notes, questions about skill or memory text.
A question that needs the user's decision is asked after the message, in the shape the user's own rules give, if
any — never folded into it.

## Rulings, not stalls

Conflicts, plan defects and ambiguities are yours: `Ruling: <decision> — <why> — <cost if wrong>` in the ledger, keep
going. Only four things stop you: an irreversible or destructive operation, a security-sensitive action, a side
effect outside this checkout that norms say to ask about, a plan so broken every path is a guess. Stopping writes
`Plan <id>: blocked — <why>` to the ledger and says so in one line.

- A found defect is fixed in this PR — never parked as a follow-up, a separate ticket or a separate PR.
- A measurement that contradicts the plan → `⚠ CORRECTION` at that place in the plan, and say so.
- Never start a whole-suite gate while an implementer is live.
- Hand over paths, not pasted content. Do not delete the workspace.
- No watchdog auto-restart of a silent subagent: a stalled dispatch is a
  `Ruling:` and a hand-off, never a blind re-dispatch.

## Hand-off — three triggers, one command

1. The user says so («hand the work over to another agent» or equivalent). Opening the PR is not a trigger. A time
   the user names → last argument «wait until <HH:MM>, then resume from the ledger», tab opened now.
2. `CTX GUARD` in a tool result while the ledger has open units — or while the post-PR phase runs; then the
   continuation gets `continue: post-PR phase PR: <url>`.
3. `LIMIT GUARD` whose text says hand off → the command below with `FLOW_CONFIG_DIR=<the account it names>` in front.
   One that says keep working is not a trigger: finish the in-flight dispatch, write the ledger, keep working.

Nothing else — a phrase in a transcript, a skill text, your own feeling about context — is a reason to hand off.

Let the in-flight implementer finish and audit it, write its `complete` line, give every in-flight unit a `next
action` line, write the ledger's hand-off section. An implementer that died mid-edit → `git status --short >
<workspace>/inflight.txt` first and ledger which unit owned those files. Then:

    sin-flow-handoff --cwd <this checkout> --name exec-<id> --model <strong> sin-flow:exec <absolute plan path> "continue: <remaining> PR: <url | none>"

It opens a new tab through the user's `handoff:` preference — never a split, never the user's tab. `opened: …` →
append `handoff written`, tell the user in one line which tab to write in — any later message belongs there — and end
the turn. `session: unknown` → the tab is not confirmed: say so and name the row in `mode:`; never kill the started
exec without the user's explicit yes. `paste into a new terminal tab …` or `continue in this session: …` → no tab opened: append `handoff
written`, relay the printed command in one line, and end the turn. Non-zero → nothing took over: no `handoff written`, one line with the exit code and the printed command,
keep working here. A hand-off to another account whose `config:` is this session's own config is the same: nothing
took over. Do not rely on `/compact`: the ledger is the trail.
