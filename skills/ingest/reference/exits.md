# sin-flow:ingest — the exits

Read only the section for the chosen exit. Paths: `<work>` = `~/.claude/sin-flow/work/<key>/<id>`;
`<repo>` = the main checkout (parent of `git rev-parse --path-format=absolute --git-common-dir`), or
`sin-flow-profile <key> get repo.path` when a URL in the source decided a key other than the cwd's;
`<base>` = the base the profile resolves (`repo.base`, else the GitHub default branch).

## Ticket map (plan, hotfix, epic)

One unit by default — fewer, bigger. Split only when the
parts live in different repos, or one part must merge before another can start. Show the map — per
unit: title, repo, type, `after: <id>` for the second case — and lock it with one question; the
answer goes into `## Decisions`. Then run everything below once per unit, in map order. A unit in
another repo takes everything from that repo's profile.

## Tracker unit

- **Upstream mode:** reuse the issue the user names; otherwise title and body per `upstream.md` § Issue body — no source link, no evidence, no local path; `gh issue create --repo <slug> --title … --body-file <work>/issue-body.md`, no `--assignee`, no `--milestone`; `upstream.first_issue` absent → § Write policy (the first public write); a reused issue opens nothing, so the PR is the first public write.
- **Issues on the remote:** reuse the issue the user names; otherwise `gh issue create --repo <slug>
  --assignee @me --title "<title>" --body-file <work>/issue-body.md`. `tracker.board` set → add `--milestone "<m>"`:
  the milestone of the closest open or closed issue on the same area (`gh issue list --repo <slug> --state all
  --search "<area terms>" --json number,title,milestone`); none fits → drop it and say so in the report's
  `ticket:` line. English. The body names the
  source, states the problem and the measured cause in a paragraph each, carries the evidence inline;
  it does not restate the ticket you read. Someone else's ticket is never closed or retitled, and a board
  status is not touched — that is `sin-flow:sync`'s and `sin-flow:plan`'s. Rename `ingest-<slug>` → `gh-<N>`.
- **`tracker.kind: local`:** no remote unit. The id is `<N-M>` (next free in the owning epic — one
  above the highest id in the backlog and in `work/<key>/*/plan.md`, compared numerically per
  segment so `1-1` never reads as `1-10`) or `<slug>`; `status: ready-for-dev` in the plan header.
  The owning epic is the one whose stories already touch the surface; never a new epic, never a
  question — pick the closest and record why.

## Worktree

Every writing exit gets its own worktree before anything else (inbox #36: a branch cut in the shared
checkout moved with another session's checkout and took the uncommitted diff along).

Branch: the profile's `git.branch` deviation, else `<prefix>/<type>/<id>/<slug>` — `prefix` is the
user preference `branch_prefix` (`~/.claude/sin-flow/user.md`; empty → no segment), `type` bug | task |
story. `<slug>` kebab-case from the intent.

Where the session started decides, in every repo (inbox #36, #38, #43, #44). Primary checkout: `git
rev-parse --git-dir` equals `git rev-parse --git-common-dir`; otherwise the cwd is a linked worktree.

**A linked worktree is reused** only when the cwd's main checkout is `<repo>`. In Orca (`sin-flow-handoff --detect` prints `orca`) any linked worktree is the workspace the
user made for this work, whatever its name; elsewhere only one whose basename is the unit's id (`gh-<N>`,
`<N-M>`, `epic-<N>`). It must be clean (`git status --porcelain` prints nothing) and, after `git fetch
origin <base>`, `git rev-list --count origin/<base>..HEAD` is 0 — otherwise ask the user, never create a
second one. Then in the cwd: `git merge --ff-only origin/<base>`, `git branch -m <branch>`. Only the first
unit takes it; every other unit gets a new one as below.

**From the primary checkout, and for every further unit, a new worktree.** In Orca it is a new Orca workspace, so its tab is visible:

```
git -C <repo> fetch -q origin <base>
orca worktree create --repo path:<repo> --name <id>-<slug> --base-branch origin/<base> --setup skip --no-parent --json
git -C <.result.worktree.path> branch -m <branch>
orca terminal list --worktree path:<.result.worktree.path> --json | jq -r '.. | objects | select(has("handle") and (has("agentIdentity") | not)) | .handle'
```

Orca opens a plain shell as the new workspace's first terminal; the last line prints its handle. Keep it:
once the hand-off prints `opened:` for this worktree, `orca terminal close --terminal <handle> --tab`, so the
stage tab is the only one. Only that handle, only in a worktree this step created.

Outside Orca:

```
git -C <repo> fetch -q origin <base>
git -C <repo> worktree add .claude/worktrees/<id>-<slug> -b <branch> origin/<base>
```

Opening a tab in that worktree is the hand-off's job (`sin-flow-handoff --cwd <wt>`), never this step's.

## Seed (plan, epic)

`<work>/plan.md`, outside every repo and worktree. English. First line `> Created: YYYY-MM-DD`, then
the header lines the next stage reads verbatim:

```
profile: <key>
repo: <slug>
base: <base>
exit: plan | hotfix | epic
status: ready-for-dev
branch: <the branch the worktree was made on>
source: <issue URL | permalink | Rollbar item | "words" | screenshot path>
ticket: <id>
worktree: <absolute worktree path>
spec: <absolute spec path>      (only when the map has more than one unit)
after: <id>                     (only when this unit waits for another)
```

Sections, in this order; one with nothing to say carries one line saying so:

1. `## Tickets` — the unit with link and title; the source under it; the whole map when there is one.
2. `## Problem` — what the user sees, three sentences at most.
3. `## Root cause (measured)` — the mechanism, the `file:line`, the number that proves it; or
   `RULING_NEEDED: measure before exec` with the reason no number exists.
4. `## Evidence` — one link per file in `<work>/evidence/`, each with date, base SHA, what it measures.
   An entry with query text, numbers, date and SHA **is** a measurement to `sin-flow:plan`.
5. `## Decisions (locked with the user, <date>)` — the user's answers, one line each, dated. Binding:
   `sin-flow:plan` copies them verbatim and never reopens them.
6. `## Open decisions` — who decides, what it blocks; `sin-flow:plan` settles each as a `Ruling:` with the
   rejected alternative beside it.
7. `## Not in scope` — what the user said to leave, in their words; a defect seen on the way goes into
   the fix, not here.
8. `## File clusters` — the files the fix touches, each verified at the base commit, `NOT FOUND`
   otherwise; plus every doc section the fix makes false (heading and line range).
9. `## Branch and PR skeleton` — the branch, and the PR title by convention (`[<ID>] <title>` when the
   tracker gives an id).
10. `## Finish line` — one line: *the coding stage commits, pushes and opens the PR itself, in the same
    session, without asking.* It authorizes the downstream stages, never this skill.

**More than one unit → one spec**, `~/.claude/sin-flow/work/<key>/<first id>/spec.md`: the map (id, repo,
title, worktree, `after:`) and the decisions every unit shares. No parent issue on GitHub.

## Mirror to the issue

Only when the unit is an issue and mirroring is on (issues enabled and the repo is a team's, unless
the profile says `notes.mirror: off`); never in upstream mode. Nothing from `work/` is ever `git add`ed.
Every issue body, mirror and comment is self-contained: no local path (`~/`, `/Users/`, a scratchpad),
code cited as a permalink at the base SHA, a local source or evidence file summarized in the text.

- The user authored the issue (one this skill created): `gh issue edit <N> --body-file plan.md`.
- Anyone else's issue: one comment that starts with `<!-- sin-flow:plan -->`, created once, then edited in
  place (`gh api -X PATCH repos/<slug>/issues/comments/<id> -F body=@plan.md`) — never their body.
- Over 60 000 bytes: the first 60 000 plus `continued in comments`, the rest as comments.
- Each evidence file: one `gh issue comment --body-file` (not in upstream mode).

## Hand-off (plan, epic, hotfix)

**The next stage never inherits this session's model:** hand off on `<strong>`
(`sin-flow-handoff` resolves it from `--cwd <wt>`).

```
sin-flow-handoff --cwd <wt> --name <stage>-<id> <sin-flow:plan | sin-flow:exec> <work>/plan.md
```

`plan` and `epic` → `sin-flow:plan`; `hotfix` → `sin-flow:exec`. One tab per unit without `after:`, all in
this turn; a unit with `after: <id>` is launched by that unit's `sin-flow:exec` once its PR is open.

**Read the output and the exit code.** `0` — handed off: `opened: …` (a new tab, from an adapter or
the user's own script), `paste into a new terminal tab …` or `continue in this session: …` (the user
runs the printed command; relay it in one line); never start a second one on `0`. Non-zero — no tab
opened: `1` bad path, `2` bad option or `handoff:` setting, anything else the launcher's own code, after
which the command is printed and copied. Any non-zero:
one line with the code and the printed command. `session: unknown` in the output means the tab is not
confirmed: never report it as opened. Name the row in `mode:` and the first suspect: a worktree path this
account never opened stops the new tab on Claude Code's folder-trust prompt — tell the user to answer
«Yes, I trust this folder» in that tab. Never
kill a started stage without the user's explicit yes. Put the `opened:` or printed line in the report, then
stop.

## Exit `hotfix`

Tracker unit and worktree as above (the shipper refuses to invent a ticket). Then `<work>/plan.md`
with the seed header (`exit: hotfix`) and one block instead of sections 3–9:

- `## Intent` — problem and approach, one or two sentences each.
- `## Boundaries` — Always: the invariants the area already lives by, the user's decisions, your
  `Ruling:` lines. Never: out of scope and the approaches the user refused.
- `## I/O & edge cases` — only rows measured or read; none → no section.
- `## Code map` — step 2 verbatim: `path` — role, what to reuse, what not to change, the analogue.
- `## Tasks` — the failing spec reproducing the reported case on the fixture the report named; the
  fix, one task per file; each doc section the fix makes false — `-- update -- why` (the implementer
  edits it, ingest edits no doc).
- `## Files` — every path the tasks touch: the implementer's ownership and the shipper's commit list.
- `## Verification` — the step 3 query to re-run with the expected result after the fix; the new spec.
- `## Gates` — `gates.hotfix: full` → the full gate list (`gates.commands`, else the `gates` lines of
  `## Inferred`); absent → the touched specs plus the repo's lint (CI's gates run on the PR).
- `## Finish line` — as in the seed; plus «PR without asking; the merge is the user's».

Hand off to `sin-flow:exec`. A second occurrence of the same pattern elsewhere is a second hotfix under
the same unit.

## Exit `data-fix`

The code is right, specific rows are wrong. Recipes live in `~/.claude/sin-flow/profiles/<key>/support/`
— never in the repo. Read its `README.md` first, every time; none → create it from the rules below
with an index table.

- `<date>_<slug>.<ext>` in the repo's stack (one statement → `.sql`) — code only: ALL-CAPS inputs at
  the top unset with a raise «fill in …», a guard on the record's owner, BEFORE / AFTER prints of the
  rows touched, the change in one transaction, `DRY_RUN` wherever a step is irreversible.
- `<date>_<slug>.md` beside it — what and why, in the reporter's words and ours; the verification
  query **before** with expected counts — run it now through the read-only route and paste the result
  with the time; the same query **after** — run it when the user says the script ran; who runs it and where
  (the person the README names — never this skill, never the user's session); rollback as a query,
  or «none» said out loud. Add the pair to the README index with a run count of 0.

Plus a support reply draft in plain English, five sentences at most: what was wrong, what will
change, when they see it, what to check. The recipe reaches the person who runs it as text in the
ticket or thread — through the user.

## Exit `answer`

A reply draft in `<work>/reply.md`: plain language, **five sentences at most**, the evidence linked,
the mechanism in one sentence, no identifier before the plain sentence that explains it. Above it in
chat, two sentences for the user: what the reply tells the reporter, and why that helps them.

- Slack thread: Slack-ready plain text — no headings, no tables — shown in chat and put on the
  clipboard with `pbcopy` in the same turn, one line "in the clipboard". The user posts it.
- Issue in our repo: post only on the user's word — `gh issue comment <N> --repo <slug> --body-file <work>/reply.md`.
- Issue in another repo: show the exact text and wait for a "yes" for that comment — except upstream mode: `upstream.md` § Write policy.
- If auto mode refuses the post, give the user that one command once, prefixed `!`, flush left in a code
  block, and nothing else in that message.

## Exit `investigation`

`<work>/investigation.md`, in this order: a three-line `## Hand-off brief` (what happened, where the
case stands, which exit next and why not now); the user's words verbatim, treated as a hypothesis;
`## Confirmed findings`, each read at `file:line` or measured with its query; only the paths someone
raised or the data suggests; `## Conclusion` with its confidence and **what would change the
verdict** — the one measurement or fact that would turn this into `hotfix` or `plan`.

No tracker unit, no worktree, no code. The last line of the chat message is the Conclusion's last
line.
