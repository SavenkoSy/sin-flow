# sin-flow:ingest — reading each source

One run takes one or more sources. Read each source in full before the map.
One ticket map covers all of them (`exits.md` § Ticket map).
More than two sources: dispatch one `sin-flow:read-only-analyst` for each source. Send all briefs in one message, as § E2 does.
Which ones the repo enables: SKILL.md § Arguments.

| Source | How it is read | Notes |
|---|---|---|
| Issue URL | `gh issue view <url> --comments` | ours, a consumer repo's, or an upstream repo's; a consumer issue is the normal case when the profile lists `consumers` |
| Repo URL + words | the slug decides the key (SKILL.md § Arguments); no profile → setup § Onboard step 0 | the request is the words |
| `GH-N` | `gh issue view N --repo <repo.slug> --comments` | our repo's issue |
| Slack permalink | `slack_read_thread`, then `slack_read_file` for every attachment | read tools only — never a send, draft, reaction or canvas tool |
| Rollbar item URL | `mcp__<integrations.rollbar>__get-item-details`, then `list-occurrences` | fingerprint, first/last seen, real parameters, the version each occurrence carries |
| `"words"` | the user's quote is the source | any language; recorded verbatim in the seed and the evidence header |
| screenshot path | `Read` the image | it names the page, the state and often the record nobody typed |
| log excerpt | pasted text or a path | the timestamp, request path and job class are the fixture |
| draft path | an existing `plan.md`, `investigation.md` or evidence file under `~/.claude/sin-flow/work/` | continue it — its decisions and findings stand; never restart from zero |
| `epic N`, `N-M …` | § Epic below | needs `tracker.id: N-M` in the profile |

**A unit id handed as words is not a words source.** "story 26.5", `1-11`: it already exists in the
backlog — run it as the `N-M` source, never as a new request.

## Epic

The batch source. Unit of work: one branch per the profile's `git.branch` deviation (default
convention otherwise) and one PR, one commit per story when `git.commit_unit: story`. It closes
every product question for the batch so `sin-flow:plan` and `sin-flow:exec` run without the user.

Invocation — an explicit argument is the decision, never re-asked:

- `epic 10` — the whole epic
- `10-2 10-3 10-4` — a named subset of one epic
- `epic 10 --skip 10-10` — the epic minus rows

### E1. Scope from disk, not from memory

1. The backlog file `## Tracker` names: `grep -n` the epic's heading, read that heading's line range
   only — never the whole file.
2. Statuses: `grep -l '^status:'` over `~/.claude/sin-flow/work/<key>/*/plan.md` for the epic's ids. A
   story whose plan says `done` or `superseded` is out and is listed as such.
3. Candidate batch = the argument's rows minus the out rows. Say the list in one line.

### E2. Ground every question in code before asking it

This session reads no code for the batch. Dispatch one `sin-flow:read-only-analyst` (`<mid>`) per candidate
story, all in **one message**. Each brief carries the story's heading and line range in the backlog
and this fixed question set, answered in ≤ 40 lines with `file:line`:

- what already exists for this story — tables, models, events, queries, components, routes, locale
  keys — and what is missing;
- the files it will create and modify, and which of them a sibling story in the batch also touches
  (schema, routes, locales, shared layout count as shared);
- external inputs it depends on (provider API, dataset, metric table) and whether that data exists —
  through the profile's measurement route only; otherwise «not measured», never a guess;
- **every product question only the user can answer**, each with 2–3 alternatives and, for each,
  what the user sees on which page — public copy (title, meta, badges, empty states), where a new
  block sits among the existing ones, what happens to the story's records when their user is deleted.

The analysts report facts; the recommendation is yours.

### E3. Overview, then one question per turn

First message, in the fixed headings: the batch, proposed dispositions (rows to leave out and why —
a story gated on a step the user owns, a story superseded elsewhere), the dependency sketch and the
wave order it implies, and data facts that change scope (a metric table with no rows makes a tab
pointless). Then the questions, **one per turn**, in dependency order, each in the three-line shape
of SKILL.md § 4. An answer that opens a new question queues it; it does not jump the line.

A question the user does not answer → "deferred by the user — sin-flow:plan decides and records it
in Rulings"; never asked again. Never re-propose anything the user rejected in this repo — check
memory first.

### E4. Write the seed and hand off

`~/.claude/sin-flow/work/<key>/epic-<N>/plan.md` — the `plan` exit's seed format
(`reference/exits.md` § Seed), with `exit: epic`, `batch: <ids>`, `out: <ids + one-line reason>` in
the header, and these extra sections after `## Decisions`:

- `## File ownership` — table story → files (create / modify); shared files listed once with every
  owner named. `sin-flow:plan` turns this into waves.
- `## Dependencies` — `A blocks B` lines only.

Each batch story gets one line in `## Tickets`: id, title, the backlog heading with its line range,
`status: ready-for-dev`. Then the worktree (`reference/exits.md` § Worktree, named after the batch branch) and the
hand-off to `sin-flow:plan` exactly as the `plan` exit does it. No story files, no backlog edits, no
estimates, no `builder:`/`audit:` — those are `sin-flow:plan`'s.
