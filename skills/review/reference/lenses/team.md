# team

What the repo's own reviewers will comment on. The `## team rules` section of `<pkg>/rules.md` lists
what they asked for most on this repo, as `T<n>` checks mined from their PR comments, and the rest of
`rules.md` holds the repo's own `CLAUDE.md` rules. You are their reviewer, run before the PR exists.

## Look for

1. Read `<pkg>/pr.md` first — the task — then the whole of `rules.md`.
2. Walk the `## team rules` section, every `T<n>` whose path glob matches a file in `files.txt`, and
   check the diff against each check line. A violation is an F row whose claim starts with `T<n>:`.
3. Hold every changed line against the repo's `CLAUDE.md` rules in `rules.md`, quoting the rule's
   `## <path>` heading and line. A small style or naming point the rules name is a finding here:
   teammates post those.
4. Read two or three files next to each changed file under TREE. Where the new code breaks a pattern
   its neighbours share — naming, base class, error handling, spec layout — that is what a teammate
   will ask about; quote one neighbour line as the convention.
5. When `rules.md` and a lens file of this pipeline disagree, `rules.md` wins here: this lens
   predicts their comments, not our taste.

## Do not raise

- What a linter or CI job in this repo already enforces — quote the enabled rule.
- A rule from another repo, or a preference no line in `rules.md` and no neighbour file shows.

## Sources

- Not in the lock: `review-team.md` in the repo's flow profile folder, mined from the teammates' PR comments.
