# Onboard

The first run in a repo: the repo has no profile. The hard rules of `../SKILL.md` apply.
Other stages cite "Onboard step 0" by name. Keep the step numbers.

0. **Upstream repo** — the repo, from the URL or slug, else `origin` (its parent when `origin` is a fork, `gh repo view --json isFork,parent`),
   is someone else's (`gh repo view <slug> --json viewerPermission` is `READ`, `TRIAGE` or empty): the checkout is `$(sin-flow-profile user opensource_dir)/<name>` (`<owner>-<name>` when that folder holds
   another repo). Absent → `gh repo clone <slug> "$(sin-flow-profile user opensource_dir)/<name>"`. Inside it `gh repo fork --remote --remote-name fork`:
   `origin` stays the upstream, `fork` is the user's fork. A clone whose `origin` is a fork
   → `git remote rename origin fork`, then `upstream` renamed to `origin`, or `git remote add origin <parent URL>`.
   Continue in that folder; `${CLAUDE_PLUGIN_ROOT}/skills/ingest/reference/upstream.md` applies from here.
   A URL or slug of the user's own repo (`WRITE`, `MAINTAIN` or `ADMIN`) that is not this checkout's `origin` → one line
   «run /sin-flow:setup inside `<slug>`'s checkout», then stop, and the calling stage with it; never onboard this checkout under another slug.
1. `sin-flow-infer` (read-only, ≈ 5 s) prints the `## Inferred <date>` block: base, issues/Projects, merge methods, team by
   PR authors, the CI and lefthook files (`gate files:`), a stack fallback when no CI file exists,
   dev server, sensitive paths.
2. Find credential files: `ls -a <main checkout> | grep -E '^\.env\.[a-z0-9_]+_readonly$'`; for each, names only.
   Find the app's local secret files: `git -C <main checkout> ls-files --others --ignored --exclude-standard` lines
   whose file name starts with `.env`, minus `*.example` and `*_readonly`; names only, never the content.
3. Ask, one per turn, only what is missing:
   - base — only when `sin-flow-infer` printed `CONFLICT`;
   - "Where do read-only numbers come from: a doc path or `none`?" — always, the route is never inferred;
   - board — only when Projects are enabled: "does the team run a board? which number?";
   - for each `.env.<source>_readonly`: "what is the source `<source>` for?" (one sentence → `purpose`);
   - UI stack found (next/react/rails views): "check the UI with Playwright? URL?" — optional.
4. Write `~/.claude/sin-flow/profiles/<key>/profile.md`: frontmatter with `key`, `repo.slug`, `repo.path` (the main
   checkout, `dirname "$(git rev-parse --path-format=absolute --git-common-dir)"`, `$HOME` written as `~`), `repo.fork` (the slug of remote `fork`, only when it exists), `repo.local_files` (the step 2 secret files, repo-relative; exec copies them into every worktree), `measure.doc`
   and only the deviations the user gave; then `sin-flow-infer --write <key>` fills `## Inferred` and you name the gates into it
   (`gates.md`); add `## Measure` in one or two lines. Write `notes.mirror: github` into the frontmatter when the Inferred notes line
   says mirrored and the team has more than one author, else `notes.mirror: off` — a default the user changes, also to a script path (`user-scripts.md`).
   `notes.paths` (absent by default): space-separated globs of the repo's own agent notes; the shipper never stages them.
   If the profile gets a board, also write `tracker.write.light: off`, `tracker.write.assign: off`,
   `tracker.write.status: off` and `group_by: milestone`. These are defaults that the user changes. The sync
   skill's `## Tracker and switches` gives their meanings.
   Show the file. A personal measurement doc lives beside it as `measure.md`.
5. Hand back to the stage that called setup, at the step it stopped on.

## Profile format

Flat `group.key: value` lines (lists as `["a","b"]`), prose sections `## Inferred`, `## Measure`, `## Run`,
`## Ship`, `## Tracker`, `## Never`. Optional keys the stages read when set: `tracker.skip_milestones` (a comma list of milestones that a sync batch proposal skips), `review.request` (logins exec asks for review and asks again after each reply batch), `review.deploy_bots` (logins of deploy bots that the base watcher skips), `review.ignored_approvers` (logins whose approval `sin-flow-rerequest` does not count, and with no key every approval counts), `gates.lint_fix` (the lint autocorrect commands), `pr.relink_after_bot: on` (shipper saves the PR body once more when a bot added a `Closes` line that GitHub did not link), `tracker.held_statuses` (Status options that a new board leaves out of scope), `gates.spec_cmd` (a test command that takes spec file paths; exec runs the canary with it, and no key means no canary), `review.preship_agent` (a `subagent_type` that exec runs on the final diff before the PR), `notes.paths` (extra globs the shipper treats as agent notes), `notes.mirror` (`off`, `github` or a script path, `user-scripts.md`), `tracker.stale_days` (the days after a take when a claimed ticket with no open PR shows as a stale claim, default 3), `ci.after_merge: on` (exec watches each workflow run on the merge commit to its end, and no key means no watch), `ui.after_merge` (a URL where exec does the visual check again after each merge that changed a rendered surface, and no key means a check on `ui.server` after the merge only when the visual check before it was blocked, red or had a `SKIP`). Keys that setup may write: `tracker.adapter`, `tracker.write.light`, `tracker.write.assign`, `tracker.write.status`, `group_by`. Required: `key`, `repo.slug`, `measure.doc`. Never a secret — pointers only.
