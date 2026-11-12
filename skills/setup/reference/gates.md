# Name the gates

Onboard step 4 and the check use this file. The lines that you write are text that the shipper reads. Keep the format.

**Name the gates** — after every `sin-flow-infer --write`, read each file on its `gate files:` line in full and write
these lines right under it. A `gates.*` key in the profile wins over them. A command counts when a `run:` line
(comments skipped) calls a test, lint or security command of the stack, always without options or paths, once per
entry. Examples per stack:
- JavaScript: `npm <script>` / `npm run <script>` (not ci or install), `pnpm <script>` / `pnpm run <script>`,
  `yarn <script>` (not install), eslint, jest, vitest, tsc, written bare, never `npx eslint` or `npx tsc`.
- Ruby: rspec, rubocop, brakeman, bundle-audit, bundler-audit, i18n-tasks with its subcommand, `rails test`,
  `rake test|spec`, each with its `bundle exec ` / `bin/` / `npx ` prefix.
- Python: pytest. Go: `go test`. Rust: `cargo test`.

The lines to write:
- `gates (CI): <entries joined by "; ">.` — one entry per `.github/workflows/*` file whose `on:` has `pull_request` or
  `push`: `` `cmd`, `cmd` — <file> (<all its triggers joined by />[ on <the pull_request/push branches joined by ", ">]) ``, <file> being the repo-relative path (`.github/workflows/ci.yml`);
  a file with no such command is left out. One entry for `.circleci/config.yml`, from the jobs listed under `workflows`
  without `filters.branches.only`: `` `cmd` (<workflow>/<job>, …), `cmd` (…) — .circleci/config.yml, workflows that run on
  feature branches ``, or, when none of those jobs calls such a command, `CircleCI: no gate command found in jobs that
  run on feature branches — .circleci/config.yml (workflows: <workflow>/<job>, …)`. No entry at all →
  `gates (stack fallback, no CI found): …` from the stack's manifest, for example the package.json `lint` / `test` /
  `build` scripts, `bundle exec rspec` for a Gemfile, `pytest` for a pyproject.toml.
- `gates (pre-commit, lefthook.yml): <hook> <name>: `<first line of run, ≤ 90 chars>`; ….` — every `pre-commit`,
  `commit-msg` and `pre-push` command or job with a `run:`.
