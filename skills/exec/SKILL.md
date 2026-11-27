---
name: exec
description: Exec stage of the flow (ingest → plan → exec) for any repo with a flow profile. Executes an approved plan from ~/.claude/sin-flow/work/<key>/<id>/plan.md with subagents — the plan diffed against its GitHub issue first, implementers in waves (one message per wave when files are disjoint), a model and an effort named on every dispatch, a coverage audit per unit, one final review through the review pipeline, a visual check when the profile asks for one, every gate and git step through the `sin-flow:shipper` agent — then opens the PR without asking. A team repo gets the post-PR loop; a solo repo waits for the user's go-ahead to merge and merges by the `merge` option (squash by default). Ends in the one final message defined here. Use when invoked as `/sin-flow:exec <plan path>` or handed a plan to execute.
---

# sin-flow:exec — execute the plan, ship one PR

Execute the plan at the path given. No path → one line, stop. Repo facts — base, gates, branch and commit shape,
tracker, UI check, who merges — come from the profile, never from this text.

Chat with the user in the `chat_language` option (`sin-flow-profile user chat_language`), or in the language the user writes in when it is absent. Headings and fixed phrases defined here are rendered in that language. Files, commits, PRs and issues are always English.

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
- **Models**: the model grid is the only source of the model and the effort of a dispatch.
  `sin-flow-profile model <role> [level] <checkout>` prints both, for example `sonnet high`. Before the first
  dispatch, run it once for each row of the table below and write the results to the ledger. Pass the first word
  as `model` and the second word as `effort`. An effort of `-` means: pass no effort.
- **User preferences**: the plugin options, read with `sin-flow-profile user <key>` (chat language, branch prefix, hand-off launcher, reviews folder);
  unset → the defaults in the plugin's `userConfig`. They are the user's, never a repo's.

## Models — name a model AND an effort on every dispatch

The main session's model is never changed — switching it breaks the prompt cache. An omitted model inherits this
session's and burns it on mechanical work.

| Dispatch | Agent | Grid role | Level |
|---|---|---|---|
| Implementer | `sin-flow:implementer` | `implementer` | `builder:` from the plan's verdicts row |
| Implementer, a return block that does not parse | `sin-flow:implementer` | `implementer` | the unit's |
| Implementer, fix round 2 and fix round 3 | `sin-flow:implementer` | `implementer` | `fix-2`, `fix-3` |
| Fix dispatch: final-review rows, the user's findings, the post-PR batch | `sin-flow:implementer` | `fix` | the highest `builder:` of the touched units |
| Coverage audit, scoped re-review | `sin-flow:read-only-analyst` | `audit` | none |
| Adversarial check, the user's code question | `sin-flow:read-only-analyst` | `adversarial` | none |
| Final review | `sin-flow:reviewer`, one per lens | `lens-<lens>` | none |
| Pre-ship reviewer | the profile's `review.preship_agent` | `preship` | none |
| Visual check | `sin-flow:implementer` | `visual` | none |
| Gate, commit, push, PR | `sin-flow:shipper` | `shipper` | none |
| Rebase onto a moved base | `sin-flow:implementer` | `rebase` | none |
| Hand-off of this session | `sin-flow-handoff --level` | `exec` | the highest `builder:` of the plan |

`builder:` and `audit:` come from the plan. `builder:` is the level of the unit. The levels are `cheap`, `mid`,
`hard` and `strong`, lowest first. An old plan says `haiku`, `sonnet` or `opus`. Read them as cheap, mid, strong.
You can raise `builder:` or `audit:` with the reason in the ledger. Raise cheap → mid when the brief carries no
exact code. Raise mid → hard when the diff hits the plan's forcing list.
Never lower one, never raise one because you are unsure. A row with no value is a plan defect: treat it as mid / run
and ledger it.
Purpose-made agents only — never `general-purpose`. No subagent has a turn cap (`maxTurns` is inert, measured): keep briefs small and split a unit rather
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
   owns the post-PR phase and nothing is re-implemented. A team PR → `pkill -f 'sin-flow-watch <url>'`, then start
   the watcher of `reference/team-loop.md` step 5 at once: a watcher that another session started wakes only that session.
2. **Plan vs issue, before anything else.** `sin-flow-profile <key> mirror` prints the route. `off` → skip. `github`: the
   plan is mirrored when the header's `ticket:` is a GitHub issue: the comment that `skills/plan/SKILL.md` Step 6 § Mirror
   edits, never the issue body and never a comment of another plan. Not mirrored → skip. Otherwise `gh` the mirror into
   `<workspace>/issue-plan.md` and `diff` it against `sin-flow-mirror --comment plan.md` (over 60 000 bytes, part 1 of `sin-flow-mirror --comment plan.md <dir>`) — the mirror points at no local file.
   A script path and a `ticket:` other than `none` → `<script> get <ticket>`: exit `1` → skip, no copy; another
   non-zero exit → skip the compare and ledger `plan: mirror get failed — <first stderr line>`; exit `0` → its first
   line is the edit time and the rest goes to `<workspace>/issue-plan.md`, diffed against `sin-flow-mirror plan.md` (`skills/setup/reference/user-scripts.md`).
   They differ and the issue was edited after the file's mtime → the issue wins: write it over the local file, keep the
   local header lines the mirror drops (`worktree:`, `measure:`), ledger
   `plan: issue newer, taken`. The file newer → ledger `plan: local newer`; it is mirrored at Finish.
3. **Read the plan once.** Header, verdicts, waves, Finish line. **`exit: hotfix`** in the header (a one-block plan
   from ingest) is one unit: `## Files` is its ownership, `## Tasks` its brief, `## Verification` its definition of
   done, `## Gates` the `commands` for every `sin-flow:shipper` gate; `builder: mid`, `audit: run`; review depth quick, one
   round; the rest of this skill applies unchanged. A unit marked `RULING_NEEDED: measure before exec`
   does not start until the user says «without measuring» — every other unit goes on; say so in one line.
4. **Base and branch.** Base = the plan header's `base:`, else the profile's base (`repo.base` or `## Inferred`).
   A base that is not ready never stops you: when the plan depends on an unmerged branch or PR, start from that
   branch, otherwise from a freshly fetched `origin/<base>`. That branch stays the header `base:`, and the PR is a
   draft against it. After the first unit merges, the target is the profile base (`repo.base` or `## Inferred`). This session already runs in a clean checkout on the
   header's `branch:` → work in place. A clean checkout whose branch is already merged into the
   base (a stage-verify fix plan) → `git switch -c <header's branch:> origin/<base>` there, in place, no new
   worktree. `git diff --name-only <old HEAD> HEAD` lists a lockfile → the first gate's `commands` start with the
   install step of the repo's CI workflow. A folder with a `package.json` that a gate enters has no `node_modules`, or a
   symlink to another checkout's packages (`find . -maxdepth 2 -name node_modules -type l`): before the first dispatch, one `sin-flow:shipper` `gate`,
`label: install`, `commands:` `[rm <link> && ]cd <its folder> && <the install step of the repo's CI workflow>`. A hook denies
   that install → link the main checkout's `node_modules` when its lockfile is the same (`cmp`) and its `.bin` exists. Otherwise
   ledger `Ruling: packages missing — <folder>`, go on, and name the install command in the final message. The header's `worktree:` exists and this session is not in it → the § Hand-off
   command with `--cwd <that path>`, then end the turn. Otherwise, when this checkout is busy — a dirty tree, another
   branch, another session in it → `sin-flow-worktree --repo <this checkout> --name <id> --branch <header's branch:> --base <base>`,
   then the § Hand-off command with `--cwd <its path:>`, then end the turn. Never `EnterWorktree`: an Orca workspace
   lies outside `.claude/worktrees/`, so the call stops on a permission prompt. No
   `branch:` line → `sin-flow:shipper` names it by convention on its first `local` / `commit`. Never work on the base branch.
   Then each name in the profile's `repo.local_files` that this checkout lacks and `repo.path` has → `cp -p
   <repo.path>/<name> <name>`; never a link, never print one. Ledger `Base: <ref> (<why>)` and `Copied: <names>`.
5. **Sensitive paths.** The repo's `.claude/sensitive-paths.txt` (or the profile's `sensitive_paths`): match the
   plan's files against it. A hit adds `<ATTENTION>` to the commit subject and the PR title, and the PR body names
   the area and old → new. Ledger the hit. That prefix is the whole mechanism: do not stop. Write the repo's
   sensitive-change record only from an agreement that exists. A locked decision that records an approval (who,
   when, channel, quote) is that agreement. It covers each implementation detail of the approved option: copy it
   into the record as given, never mark a detail "not confirmed" and never ask the approver again. Only a change
   to the approved behaviour itself goes to the final message as a question. An implementer
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
9. `repo.fork` set → read `reference/upstream-mode.md` and follow it, before the first dispatch.

## Per wave

**Briefs first.** One `briefs/unit-<u>.md` per unit. First line: read `<workspace>/global-constraints.md` before
anything. Then: files it owns and files it must not touch (the plan's `### Every copy` split into those two lists —
no such block is a plan defect, ledger it), the interfaces earlier units froze, `builder:` / `audit:` verbatim, your
rulings that override plan text, the spec files it runs, its definition of done, and the sibling note — other
implementers may be editing other files in this checkout right now; never run a whole-project test or lint, only
the specs and files the brief names. Exact values live only in the brief; a subagent never reads the whole plan.
Write every brief in its own message, before the dispatch message: a Write can be denied, and an implementer
dispatched beside a denied Write starts with no brief.

**Dispatch the wave's implementers in one message** (parallel when files are disjoint). At most `max_live_agents`
(`sin-flow-profile user max_live_agents`) agents are live at a time, audits included: a larger wave goes out in
batches of that size, the next agent when one returns. Each dispatch carries
one line on where the unit fits, the brief path, the report path `briefs/unit-<u>-report.md`, the branch, its model
and effort. Same-shape small edits in different files → one implementer, one brief, the highest `builder:` and
`audit:` of the merged rows. Never two implementers on overlapping files: the later unit waits.

**Return block** `TASK / STATUS / FILES / TESTS / DEFERRED / RULING_NEEDED` (`${CLAUDE_PLUGIN_ROOT}/agents/implementer.md`).
Ledger it. A `DEFERRED` line is this PR's work: it enters that unit's fix loop as a finding. A `RULING_NEEDED` line
is yours: `Ruling: …` in the ledger; if it changes the unit, resume that implementer with the ruling. A block that
does not parse is not a red: re-dispatch once to a fresh implementer (the unit's level) with the schema restated and the report path it
already wrote; malformed again → ledger it and hand the unit to the final review as unverified. Never spend a fix
round on a reporting failure.

**Coverage audit**, when the plan says `audit: run` (`skip → run` with a reason; `run → skip` never). Materialise
`git diff <base> -- <its files> > briefs/unit-<u>-diff.txt`, check `grep -c '^diff --git'` against the file list,
dispatch one `sin-flow:read-only-analyst` with the brief, the report and the diff. One question: **what did the brief require
that no test asserts?** Findings only: a requirement with no covering test; a test that passes with the code it names
deleted (only when the profile has no `gates.spec_cmd`; with it, the canary below measures this); a test asserting a
constant production also uses; a listed file the diff never touches; a spec deleted where
retargeting kept coverage. ≤ 30 lines, no code-quality judgement. The audits of wave N, any re-review of a fix and
any adversarial check go out **in the same message** as wave N+1's implementers.

**Fix loop, 3 rounds max, per unit.** Round 1 resumes the original implementer with the findings verbatim.
Round 2 follows the grid row `implementer fix-2`, and round 3 follows `implementer fix-3`. A row that says `same`
resumes the original implementer. Any other row starts a fresh implementer on that row. If the unit ran on a
higher model or effort than the row, the fresh implementer keeps what the unit ran on. Only a failed check
counts as a round: a red gate, a failed spec or a finding of the coverage audit. A timeout, a tool failure or a
return block that does not parse is a retry on the same grid row. It does not count. Each round ends in a scoped re-review of the fix diff: ADDRESSED / NOT ADDRESSED per
finding, plus `${CLAUDE_PLUGIN_ROOT}/skills/review/reference/lenses/paths.md` on that diff. At the cap, rule on each open finding and ledger it.
Never fix findings yourself.

**Wave gate** — only when the profile says `gates.cadence: wave`. When every implementer of the wave has returned and
every fix loop is closed: `sin-flow:shipper` mode `gate`, `label: wave-<k>` (log `<workspace>/gate-wave-<k>.log`). It returns
`STATUS: green | red` and, on red, `TAIL:` — the path to the failing tail. Red → attribute by the failing paths to a unit in this
wave and run one fix round there (the tail is the finding). A failing spec that no unit touches → one `sin-flow:implementer`
(grid role `fix`) runs that spec alone 3 times on `origin/<base>` in a scratch `git worktree add --detach`, then removes it.
Red on the base → ledger `Ruling: base red — <spec>`, the next gate passes `commands`: the lines of the last
`gate-<label>.commands` with that spec left out through the runner's own exclude option, and the final message names it
under what differs from the ticket. Write the exclude as `**/<file name>`: `(`, `)`, `[` and `]` are glob syntax and match
nothing. Green on the base → the same implementer runs it alone 3 times on this branch. Green → `Ruling: flaky under load —
<spec>`, excluded as above. Red → the diff breaks it: one fix round for the unit whose files the spec imports.

**`sin-flow:shipper` prompt**, every mode: `mode`, `profile: <key>`, `id: <id>`, `work_dir: <workspace>`, plus the mode's own
fields (`${CLAUDE_PLUGIN_ROOT}/agents/shipper.md` § Prompt). Its return block (`MODE / STATUS / PROFILE / BRANCH / COMMITS / LOG /
TAIL / PR / MERGE / NOTE`) is all you read. `STATUS: blocked` → its `NOTE` is a finding: rule or fix, never bypass.

**Commit unit** — the profile's `git.commit_unit` (e.g. one commit per plan unit) → after the wave, `sin-flow:shipper` mode
`local` per unit in wave order: the unit id, its title in English (translated when the plan's is not), its `FILES` (one path per line),
one paragraph on what changed and why. No such key → nothing is committed until the final review.

**Canary** — when the profile sets `gates.spec_cmd`. When every implementer of the wave has returned, and before the
next wave's dispatch, one `sin-flow:shipper` `gate` with `label: canary-<k>`, `commands: true` and `canary:` one line per
unit (its id, then its `FILES`). `commands: true` is the shell command `true`: the shipper runs no other gate before the
canary. The unit id on the line is the same `<u>` that the `verdict` call below takes, because the log is `canary-<u>.log`.
`CANARY reverted: green` → the unit's specs pass without its code: a finding for that unit's fix loop.

Then `sin-flow-gate verdict <workspace> <u> <sha | uncommitted> <clean | skipped>` per unit, and append its line to
the ledger as it prints it. `Unit <u>: complete (…)` → move on without checking in. `Unit <u>: not proven: …` → a
finding for that unit's fix loop, then the canary again. Do not stop between waves. Do not ask.

## Final gate and final review — once, through the review pipeline

1. **Gate.** Cadence not `wave` → `sin-flow:shipper` mode `gate` now (`label: final`), red handled as the wave gate.
2. **Commit.** `sin-flow:shipper` mode `local`: branch and commit the work, no push, no PR — the package sees committed work
   only, and the main thread never commits itself.
3. **Package.** `bash ${CLAUDE_PLUGIN_ROOT}/skills/review/reference/build-package.sh exec <base> <workspace>/final-review --intent <plan path>
   --notes <workspace>/progress.md --depth <thorough when the profile folder has review-team.md, else quick>`. It
   prints only the package path `<pkg>`; a non-zero exit is a broken call — fix it, never hand-build a package.
   Check `grep -c '^diff --git' <pkg>/diff.patch` against the union of all `FILES`, then
   `cat <workspace>/global-constraints.md >> <pkg>/rules.md`.
4. **Run** `${CLAUDE_PLUGIN_ROOT}/skills/review/reference/pipeline.md` as written, every lens as `subagent_type: sin-flow:reviewer` with the model
   and the effort of its `lens-<lens>` grid row. Each reviewer returns one line — ledger it, and each `reviewers.sh` line too: the `<NAME> · found …` stats line
   is the per-PR record of that extra reviewer. Read `<pkg>/verdict.md` only; never open `findings/`. Render
   the review file into the reviews folder (user preference) as `<key>-<branch>.md` (`-<sha8>` added when that
   file already holds the review of another commit).
5. **Rows → one fix dispatch.** `reproduces` rows and `possible` rows of every severity go into ONE fix dispatch
   (grid role `fix`), every K block verbatim, plus the ledger's `Ruling:` lines. A fix that reverses a ruling is a regression the
   scoped re-review reports. A `possible` row is fixed the way it proposes, with a spec asserting the fixed behaviour
   («measure the settle → fix what reproduces»). Two exceptions, only these: the plan's text already accepts this
   exact risk, or the measurement the row's `settle` names was run and refutes it — ledger `final-review settled:
   K<n> — plan:<line> «<quote>»` or `— measured: <number, filter>`. «Reopens a plan decision» without a quoted line,
   «a new mechanism», «outside this ticket», «a separate PR» are not exceptions. Rejected rows → one ledger line `final-review
   rejected: <n> (<reason> <count>, …)`.
6. **After the fix**: scoped re-review, `sin-flow:shipper` `gate` (after every fix: the shipper pushes only a tree that
   a gate ran green on), `sin-flow:shipper` `local` (`commit` once a PR exists) — a new
   commit. **Review until clean** when the profile folder has `review-team.md`: steps 3–5 again on
   the fix commits only (`build-package.sh exec <SHA= of the previous round's manifest.env> …-<round> --depth quick`)
   — every line the fix wrote gets the lenses; code an earlier round passed is not reviewed again. These rounds
   run without extra reviewers: no `reviewers.sh` call, no extra reviewer turns. Stop when verify keeps no row step 5 does not
   settle; at most 3 rounds; rows still open → ledger `final-review open: K<n> — <claim>`. No team file → one scoped
   re-review after the fix, no second round.
7. **Pre-ship reviewer** — when the profile sets `review.preship_agent`. After step 6, dispatch that `subagent_type`
   once (grid role `preship`) with `<pkg>/diff.patch` of the last package, the plan path and one ask: review this diff as
   you review this team's PRs. Its points go through step 5 like verify's rows, then step 6. The type is not
   available → ledger `preship: <type> not available`, go on.

## Visual check — when the profile sets `ui.visual_check` and a unit has `UI surface: yes`

Follow `reference/visual-check.md` (one source; do not restate it). Dispatch one `sin-flow:implementer` (grid role `visual`) with
that path, every unit's `### UI checklist`, the ledger's `Ruling:` lines that changed a rendered surface, the profile's
`ui.*` values, `## Run` and the UI section of its `measure.doc`, and the label `<id>`. It returns `VISUAL / RESULT /
FAIL / SHOTS`; ledger it, and act on it as § After of that file says.
The route sweep after a merge needs no UI surface. § After the merge of that file runs it when the profile sets `ui.sweep`.

## Finish — ship, then report. The PR happens before the final message.

1. **PR body** `<workspace>/pr-body.md`, English, in the shipper's shape (§ Mode `ship`: the `[<ID>]`
   signature, a non-closing `Ref #<N>`), then the goal from the plan header and one line per shipped unit.
   Before writing it, reconcile against `git diff --stat <base>`: a file the body
   does not account for means the body is wrong. The diff carries no agent notes — a plan, ledger or evidence file
   in it is a defect: `sin-flow:shipper` removes it before the push.
2. **`sin-flow:shipper` mode `ship`**: branch, base, PR title in English (the plan's, translated when it is not, with the
   tracker prefix the profile's convention gives and `<ATTENTION>` when step 5 of Setup hit), `body_file`. It pushes
   the branch (never the base) and opens the PR; ledger its `PR:` and `MERGE:` (the user's merge method).
   It refuses with `NOTE: no green gate for <sha>` when no gate ran green on the tree of `HEAD`
   (`${CLAUDE_PLUGIN_ROOT}/agents/shipper.md` § Mode `ship`, step 1): dispatch `gate`, then `ship` again.
   If the plan header has `after:`, pass `draft: true`. Read the `repo` cell of the `after:` row in the spec. It tells
   same repo from other repo. At this point the header `base:` is the first branch. Same repo: first start one
   background Bash with `run_in_background`, and end the turn:
   `deadline=$(( $(date +%s) + 86400 )); until git ls-remote --exit-code origin <base> >/dev/null 2>&1 || [ $(date +%s) -gt $deadline ]; do sleep 60; done`.
   The notification of the finished background Bash wakes the session. Then dispatch one `sin-flow:implementer` (grid role `rebase`) to run `git rebase <base>` in the worktree, as
   the rebase round does. Then run `ship`. If the remote base is still absent after the loop, do not ship. Write one line to
   the user. The plan stays `status: verified`.
3. **Mirror**. Set `status: shipped` in the plan header. Route `github` and mirrored (Setup 2) → write `sin-flow-mirror --comment plan.md` back to
   the comment it came from; over 60 000 bytes → `sin-flow-mirror --comment plan.md <dir>`, each part back to its own comment.
   A script path and a `ticket:` other than `none` → `<script> put <ticket> <file>` with the `sin-flow-mirror plan.md` copy. Append `Plan <id>: shipped <URL>` to the ledger.
4. **The final message** (below), then the post-PR phase that fits the repo — same turn, no pause. Team: start the
   watcher of `reference/team-loop.md` step 5 before the message. Solo: start
   `gh pr checks <PR> --watch --fail-fast` with `run_in_background`. A red check is a finding: one fix round, `gate`,
   `commit`, one line to the user.

**Never ask before pushing or opening the PR** — except the first public write of `reference/upstream-mode.md` — and blocked units do not hold it: a plan where 8 of 9 units are
green ships those 8, and the ninth is a line in the final message under what differs from the ticket.

## After the PR — who merges decides the loop

`repo.fork` set → team. Otherwise `team` from the profile key; absent → the `## Inferred` team line; neither → more than one author among the last 20
merged PRs means team. **Team → the post-PR loop. Solo → the user's review.**

### Solo — the user's review

1. **No server.** Bring the app up only when the user asks to look — then as the profile's `## Run` says, deep-linked to
   what changed, and for each changed screen one line with the path a user takes to reach it from the start page
   (sign-in and role included) — a link alone does not say how to get there. If you started one, shut it down once
   the user approves; if the user rejected something, it stays up.
2. A state the app cannot reach on its own (an empty table a check needs rows in, a role the user must be in) → hand the
   user a console snippet that uses the repo's own write path, never raw inserts; run it only when the user says
   «you run it».
3. **Wait for the user's verdict.** This is the one place where waiting is correct: shipping was pre-authorized,
   judging is the user's. Do not declare the work done, do not start the next plan. The user's findings come back
   **collected, not one at a time**: one implementer (grid role `fix`), the visual check again when a rendered surface changed, then one
   `sin-flow:shipper` gate + `commit` for the batch (a new commit); ledger `Round <k>: complete (<sha>)`.
4. **Merge on the user's go-ahead.** A message that asks to merge or approves the merge → run
   `gh pr view <PR> --json isDraft,baseRefName`. For a plan with `after:`, also run
   `gh pr list -R <first repo> --head <first branch> --state merged --json url -q '.[0].url'`. Find the first repo
   and branch as in `sin-flow:plan` Step 1. If the output is empty, stop and write one line: the first unit merges first.
   If the first PR is merged, the repo is the same, and `baseRefName` is still the first branch, run
   `gh pr edit <PR> --base <profile base>`, then the rebase round (`reference/team-loop.md` step 1). For a plan with no `after:`, if
   `baseRefName` is not the profile base, stop and write the same line. Then, if `isDraft` is `true`, run `gh pr ready <PR>`, then
   `bash ~/.claude/sin-flow/merge.sh <PR> <MERGE from the ship block>` — the user's copy of
   `${CLAUDE_PLUGIN_ROOT}/examples/merge.sh.example` (absent → copy it there first, `chmod +x`). It waits for checks,
   merges by that method (squash when empty) and prints the merge commit. What it removed (a branch, the worktree) is
   only what its output and the disk show, never what this text or the example says. Ledger
   `Plan <id>: merged <sha>`, `status: merged` in the plan header; one line back; then § After the merge of
   `reference/visual-check.md` (one `sin-flow:implementer`, grid role `visual`: the route sweep and the merge check). The profile sets `ci.after_merge: on` → watch each workflow run on the merge commit
   to its end (`gh run list --commit <sha>`, then `gh run watch <id> --exit-status`). A red run → a fix PR at once,
   as § After the merge of that file says for a `FAIL`. No key → no watch. Exit 3 — the PR conflicts with its
   base → the rebase round (`reference/team-loop.md` step 1), then `merge.sh` once more, no question. Any other non-zero exit → paste its
   output and stop; never re-run its lines by hand.

### Team — the post-PR loop

Read `reference/team-loop.md` and follow it. Its step 1 holds the rebase round that § Solo also uses.

## Final message — the one definition

Every flow stage that ships a PR ends with this message, and only this one. The user reads it to learn what the
product does now, not how the run went. Plain words, in the chat language, ≤ 15 non-blank lines. Write it to
`<workspace>/final-message.md` first: `grep -cv '^[[:space:]]*$'` on it prints 15 or less, else cut it and count again.

- The ticket or plan id and the PR link.
- The result: what changed in the product and how it works after the merge
  (behind a flag: off, then on). A step the deploy needs is one line.
- What differs from the ticket or the plan, one line each (asked → now → why): a `Ruling:` that changed behaviour,
  a `Stale decision:` line of the plan, a unit that did not ship, a user's order that reversed the plan, an item left «not checked». Only when there is one.
- The merge waits for another PR or a deploy (a plan `after:` row, a stacked base, a contract that another repo's PR
  ships) → one line: which one, and whether it merged. Only when there is one.
- The ledger has `<NAME> · skipped · <reason>` → one closing line: that extra reviewer did not review this PR, and the reason in
  plain words. It is the one review fact the message carries.
- Solo repo only, closing lines: each screenshot (up to 3; more → the folder) as its own absolute file path on its own
  line with what it shows in a few words, from its `SHOT:` line or your own Read of it; then how to try the change after the merge (the page or the command), when
  the result does not say it; then one line: the PR merges by the `merge` option on the user's go-ahead.

Never in it — they live in the PR body, the plan or the ledger, and the user asks for one when needed: code identifiers,
class, table or column names the ticket does not use, `file:line`, SQL or any query, rule / task / finding codes,
test, lint, review or CI figures, findings closed without a fix, a «Not fixed» list, a «Result check»
section, bot, session or ledger lines, account-limit notes, questions about skill or memory text.
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
- A silent subagent is a `Ruling:`, never a blind re-dispatch.
- A tool, script, hook or hand-off fails and you work around it → in the same turn append an `open` row to
  `inbox.md` in the folder `${CLAUDE_PLUGIN_ROOT}/skills/learning/scripts/learning-dir.sh` prints: date, `exec`, the
  error text, `file:line` when known, the workaround. A flow defect never goes into memory.

## Hand-off — three triggers, one command

1. The user says so («hand the work over to another agent» or equivalent). Opening the PR is not a trigger. A time
   the user names → last argument «wait until <HH:MM>, then resume from the ledger», tab opened now.
2. `CTX GUARD` in a tool result while the ledger has open units — or while the post-PR phase runs; then the
   continuation gets `continue: post-PR phase PR: <url>`.
3. `LIMIT GUARD` whose text says hand off → the command below with `FLOW_CONFIG_DIR=<the account it names>` in front.
   One that says keep working is not a trigger: finish the in-flight dispatch, write the ledger, keep working. No guard comes when the `limit_guard` option is `off`.

Nothing else — a phrase in a transcript, a skill text, your own feeling about context — is a reason to hand off.

Let the in-flight implementer finish and audit it, write its `complete` line, give every in-flight unit a `next
action` line, write the ledger's hand-off section. An implementer that died mid-edit → `git status --short >
<workspace>/inflight.txt` first and ledger which unit owned those files. `<this checkout>` is
`git rev-parse --show-toplevel` in this session's own folder, also after a merge and for a new fix plan. When that
folder is gone, it is the main checkout. Never `repo.path` while this folder exists. Then:

    sin-flow-handoff --cwd <this checkout> --name exec-<id> --level <the highest builder: of the plan> sin-flow:exec <absolute plan path> "continue: <remaining> PR: <url | none>"

It opens a new tab through the user's `handoff:` preference — never a split, never the user's tab. `opened: …` →
append `handoff written`, tell the user in one line which tab to write in — any later message belongs there — and end
the turn. `paste into a new terminal tab …` or `continue in this session: …` → no tab opened: append `handoff
written`, relay the printed command in one line, and end the turn. Non-zero → nothing took over: no `handoff written`, one line with the exit code and the printed command,
keep working here. A hand-off to another account whose `config:` is this session's own config is the same: nothing
took over. Do not rely on `/compact`: the ledger is the trail.
