# Upstream repos — contributing to someone else's project

Read by ingest, plan, exec and `sin-flow:shipper` whenever the profile is in upstream mode.

## Detection
- Upstream mode ⇔ `sin-flow-profile <key> get repo.fork` prints a slug.
- `repo.slug` is the upstream repo; remote `origin` points at it. Remote `fork` is the user's fork (`repo.fork`).
  `origin/<base>` is therefore upstream's base; every `--repo <repo.slug>` lands upstream.
- Someone else's repo: `gh repo view <slug> --json viewerPermission` is `READ`, `TRIAGE` or empty.
- `<fork-owner>` = `repo.fork` up to the `/`.

## Rules to read
In the checkout at `origin/<base>`, before step 1 of ingest and in plan Step 3, each that exists:
`CONTRIBUTING.md`, `.github/CONTRIBUTING.md`, `docs/CONTRIBUTING.md`; the PR template
(`.github/pull_request_template.md`, `.github/PULL_REQUEST_TEMPLATE.md`, `.github/PULL_REQUEST_TEMPLATE/*.md`,
`PULL_REQUEST_TEMPLATE.md`); `.github/ISSUE_TEMPLATE/*` (`.md` and `.yml` forms); `AGENTS.md`; `CLAUDE.md`;
`AI_POLICY.md`. They are the repo's constraints and beat the user's defaults. Lint and test commands they name
replace the `gates:` line of `## Inferred`: plan writes them into `## Gates`, exec passes them to every gate.

## AI ban
A rule above forbids AI-generated or AI-assisted contributions → nothing is written upstream. Ingest takes the
`investigation` exit and tells the user, quoting the line. Plan or exec finding it later → `blocked`, quoting
the line.

## Write policy
- First public write in a repo (`upstream.first_issue` absent from the profile) — the first issue, or the first PR when
  ingest reused an existing issue and opened none: show the user the exact title and body, post only on their "yes",
  then add `upstream.first_issue: <issue or PR URL>` to the profile frontmatter.
- After that, issues, the PR, PR comments and review replies go out without asking.
- Never upstream: a plan mirror, evidence comments, board or status moves, `--assignee`, `--milestone`,
  reviewer requests, closing or approving anything, links to `~/.claude/` or any local path.
- One logical change per PR, minimal diff, no drive-by reformatting. No ping for review more than once a week.

## Issue body
The repo's issue template, every field filled in order (a `.yml` form: each field's `label` as a heading).
Where it dictates nothing:

    <one line: what fails, under what condition>

    Reproduce:
    1. <minimal command or code, actually run>
    Expected: <…>
    Actual: <exact error, trimmed stack trace>
    Environment: <version, OS, runtime>
    Cause: <file:line + why> | not verified
    Happy to send a PR if this direction is welcome.

A cause is written only with a `file:line` or a failing test; otherwise `not verified`.

## PR body
The repo's PR template, every section kept in order; a section with nothing to say says so. Free text inside it,
or the whole body where the repo dictates nothing:

    Fixes #<n>.
    Problem: <observable failure, one sentence>.
    Fix: <what the code now does, imperative, one or two sentences>.
    Verification: <test added / command run + result>.
    Out of scope: <what this PR deliberately does not touch> (omit if nothing).
    AI assistance: written with Claude Code (<model>); <what was generated>.

- The linked issue uses the closing keyword the repo asks for (`Fixes #<n>` by default).
- AI disclosure in the form the repo asks for; an `Assisted-by:` commit trailer only when the repo asks for one.
- Never claim a human reviewed or tested what no human did.
- Visual proof the template asks for: images uploaded to the PR, never committed; when they cannot be uploaded,
  the section says so and the final message tells the user.
- These override, in upstream mode only: Why/What/Rollback, the 200-word cap, the non-closing `Ref #<N>` rule and
  the AI-attribution strip.

## Review replies
One per review comment, inline, in English, plain:

    Done in <short sha>: <what changed, one line>.
    I kept <X> because <concrete reason: test, constraint, link>. Happy to switch to <their option> if you prefer.
    Good catch — I don't know yet; checking <what> and will reply here.

Never argue twice; no praise, no apologies, no restated diff; never "ready to merge".
