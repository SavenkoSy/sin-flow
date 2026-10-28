---
name: setup
description: 'One idempotent command that installs the flow on this machine, onboards the current repo, checks all three layers, and adds a new read-only data source. First run on a machine creates ~/.claude/sin-flow/{profiles,work,reviews} and its local git; first run in a repo infers everything the repo and GitHub can answer (sin-flow-infer) and asks at most three questions, one per turn, before writing ~/.claude/sin-flow/profiles/<key>/profile.md; every later run only checks and ends in exactly "all good" or a list where each row carries one fix, applied only after a "yes". `add <source>` registers a credential without ever reading its value, verifies it with one harmless call and records it in the profile. Use when invoked as `/sin-flow:setup` or `/sin-flow:setup add <source>`, when a flow stage reports "no profile", or when the user says "set up the flow", "check the flow", "add access to …".'
---

# sin-flow:setup — install → onboard → check → add

One command, four modes, each idempotent: a second run asks nothing and changes nothing when everything is in place.

Chat with the user in the `chat_language` option (`sin-flow-profile user chat_language`), or in the language the user writes in when it is absent. Fixed phrases defined here (`all good`, the questions, the fixes) are rendered in that language. Every file you write is English.

## Hard rules

- **Never read a secret into the context.** Variable names only: `grep -o '^[A-Z_0-9]*=' <file>`. A value reaches a
  subprocess only as `$VAR` after `set -a; . <file>; set +a` inside a `( … )` subshell; pipe any output that could echo
  it through `sed -E 's#[a-z]+://[^ ]*#<url>#g'`. Never `cat`, `echo`, `env` or `printenv` a credential file or variable.
- **A credential file stays where the user keeps it**: `.env.<source>_readonly` in the root of the main checkout,
  git-ignored, `chmod 600`. Stages read it by absolute path of the main checkout
  (`dirname "$(git rev-parse --path-format=absolute --git-common-dir)"`), never from a worktree; nothing is copied or linked.
- **Never guess a measurement route.** No answer → `measure.doc: none`, and every number stays "not measured".
- **One question per turn**, in prose, only where the repo and GitHub are silent or contradict each other.
- **Nothing changes without a yes** after install — a check only reports.
- Read-only everywhere in the product repo: setup writes only under `~/.claude/sin-flow/` (and project-local settings after a yes).

## Resolve

- Key: `sin-flow-profile key` (cwd → `git remote get-url origin` → profile whose `repo.slug` matches; else `<repo>/.claude/flow.md`).
- No key and cwd is a repo → **onboard**. Cwd is not a repo → install/check of the flow and user layers only.
- `add <source>` as the argument → **add**.

## Install (first run on a machine — `~/.claude/sin-flow` missing)

1. `mkdir -p ~/.claude/sin-flow/{profiles,work,reviews}`; `.gitignore` = `/*`, `!/.gitignore`, `!/work/`, `!/profiles/`;
   `git init`. `work/` and `profiles/` are one local repo; a remote is added only when `work_remote` is set — never
   created here, and nothing is pushed by setup or by the Stop hook.
2. `command -v gh git jq bash`, `gh auth status`. A miss is a row with its fix (`brew install jq`, `gh auth login`).
3. Show the preferences with defaults — `chat_language`, `merge: squash`, `after_review: new-commit`,
   `branch_prefix: ""`, `handoff: auto`, `learning_dir: ~/.claude/sin-flow/learning`, `learning_runs: 0`,
   `learning_cwd:` (empty → `learning_dir`), `work_remote: ""`,
   `models_strong: opus`, `models_mid: sonnet`, `models_cheap: haiku`,
   `reviews_dir: ~/.claude/sin-flow/reviews` — ask once "keep the defaults?" — a user whose account has no Opus sets
   `models_strong: sonnet`. Then ask `context_guard` once, as its own question: "a plan, exec, ingest, sync, review or
   learning session hands its work to a fresh session when its context reaches N % of the 1M window — keep 40?" →
   set `context_guard: <N>`. Then ask `limit_guard` once, as its own question: "When a usage limit stops a session,
   Claude Code waits and continues the task after the reset. sin-flow can also warn a flow session before the stop, so it
   writes its ledger first. That needs a small status line wrapper in your settings. Keep the built-in only (default), or
   add the sin-flow guard?"
   - Built-in → `limit_guard: off`. No settings change.
   - sin-flow guard → `limit_guard: on`, then the wrapper install:
     1. `S=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json`, `cur=$(jq -r '.statusLine.command // ""' "$S")`.
     2. When `cur` contains `sin-flow-statusline`, run `mkdir -p ~/.claude/sin-flow/bin`, copy `${CLAUDE_PLUGIN_ROOT}/bin/sin-flow-statusline` there and `chmod +x`. Do not change `S`. Stop.
     3. Check each word of `cur` that names a file after `~` expansion. When that file contains both `state/sessions`
        and `limit_5h`, the user's own status line writes the state file. Then leave `S` alone and say so in one line.
     4. Else show the new command and ask "yes?". When `cur` is empty, the new command is
        `sh ~/.claude/sin-flow/bin/sin-flow-statusline`. Else it is
        `sh ~/.claude/sin-flow/bin/sin-flow-statusline '<cur, each ' as '\''>'`.
     5. On a yes: `mkdir -p ~/.claude/sin-flow/bin`, copy `${CLAUDE_PLUGIN_ROOT}/bin/sin-flow-statusline` there,
        `chmod +x`. `mkdir -p ~/.claude/sin-flow/backups/<YYYY-MM-DD>`, then copy `S` to
        `~/.claude/sin-flow/backups/<YYYY-MM-DD>/settings.json`. Set
        `new` as a shell variable in the same Bash call, then write
        `jq --arg c "$new" '.statusLine = ((.statusLine // {}) + {type: "command", command: $c})' "$S"` to `S.tmp`,
        check it with `jq empty`, then `mv` it over `S`.
     6. On a no: `limit_guard: off`, and one line that the guard needs the wrapper.

   Save the answers as plugin options: `ID` = the first enabled id that starts with `sin-flow@` in
   `claude plugin list --json`. Pipe one JSON object of string values to `claude plugin configure "$ID" --values-stdin`.
   Options left out keep their values. The user may also set them in `/plugin configure` or `/config`.
4. Hand-off, decided once; when `sin-flow-profile user handoff` already prints a named terminal, keep it and skip this step.
   `sin-flow-handoff --detect` prints a terminal name or `none — checked: …`.
   A name → ask "should the flow open new <terminal> tabs for the next stage itself?" — yes → `handoff: auto`,
   no → `handoff: print`.
   `none` → quote the printed line as is (never add a reason of your own) and ask "which terminal do you run Claude Code
   in: tmux, cmux, iTerm, Ghostty, Warp, Orca, or other?". A named one → `sin-flow-handoff --check <name>`: `ok` →
   `handoff: <name>`; anything else → tell the user the printed reason in one line and set `handoff: print`.
   `other` → offer to copy `${CLAUDE_PLUGIN_ROOT}/examples/handoff.sh.example` to `~/.claude/sin-flow/handoff.sh`
   (`chmod +x`; it opens a new macOS Terminal window, the user may adapt it) — yes →
   `handoff: ~/.claude/sin-flow/handoff.sh`, no → `handoff: print`.
   Copy `${CLAUDE_PLUGIN_ROOT}/examples/merge.sh.example` to `~/.claude/sin-flow/merge.sh` when absent (`chmod +x`): the
   merge step of sin-flow:exec runs that copy, and the user adapts it — for example to keep the worktree after the merge.
5. Offer `Read(~/.claude/sin-flow/**)`, `Bash(sin-flow-profile *)`, `Bash(sin-flow-infer *)`, `Bash(sin-flow-handoff *)` in
   user settings — add only on a yes.

The preferences are the `userConfig` options of the plugin (`${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`).
Claude Code keeps the values in `pluginConfigs["<id>"].options` of the user's `settings.json`. Every reader uses
`sin-flow-profile user <key>`: the hook env `CLAUDE_PLUGIN_OPTION_<KEY>` first, then `settings.json`, then the
`default` in `plugin.json`. An unset option keeps its default:

| option | default | meaning |
|---|---|---|
| `chat_language` | absent → the language the user writes in | language of the chat; files, commits, PRs and issues stay English |
| `handoff` | `auto` | how a stage starts the next one: `auto` — a new tab in the detected terminal, else print · `same-session` · `print` — print the ready command and copy it to the clipboard · `tmux`, `cmux`, `iterm`, `ghostty`, `warp`, `orca` — that terminal's adapter, when detection cannot tell · a path to the user's own script |
| `learning_dir` | `~/.claude/sin-flow/learning` | where `/sin-flow:learning` keeps digests, inbox and ledger |
| `learning_runs` | `0` | how many undigested `sin-flow:exec` runs start a learning session when an exec session ends. `0`: never |
| `learning_cwd` | `learning_dir` | where that learning session starts; its `CLAUDE.md`, else `<learning_dir>/ledger.md`, is the hand-off path |
| `merge` | `squash` | merge method for the user's own PRs |
| `after_review` | `new-commit` | how review fixes land on an open PR: a new commit on top |
| `branch_prefix` | `""` | first segment of the convention branch `<prefix>/<type>/<id>/<slug>`; empty → no segment |
| `context_guard` | `40` | percent of the 1M-token context window at which plan, exec, ingest, sync, review and learning hand off or stop; `CTX_GUARD_THRESHOLD` overrides it for one session |
| `limit_guard` | `on` | `on`: the LIMIT GUARD warns a session at 90 % of the 5-hour or 98 % of the 7-day limit, from the state file that the status line wrapper writes. `off`: only the Claude Code auto-continue. Setup sets `off` when the user keeps the built-in |
| `models_strong` | `opus` | plan, exec and learning sessions, every hand-off, the review lenses on the strong tier, exec's fix round 3. One of `opus`, `sonnet`, `haiku`, `fable` |
| `models_mid` | `sonnet` | read-only analysts, implementers, shipper, review-poster, the review lenses on the mid tier |
| `models_cheap` | `haiku` | the board agent |
| `reviews_dir` | `~/.claude/sin-flow/reviews` | where `/sin-flow:review` writes review files |
| `opensource_dir` | `~/.claude/sin-flow/opensource` | where setup clones a repo that is someone else's, one folder for each repo |
| `codex_review` | `off` | `on` → the exec review at the end of a unit also runs OpenAI Codex CLI as one more finder, then gives Codex one reply turn on the verdict (`skills/review/reference/pipeline.md` § 3). Needs `codex` installed and `codex login`; without them the review goes on and the last message says so |
| `codex_model_pr` | `""` | a Codex model family `<family>` (the newest listed `gpt-<version>-<family>` in `~/.codex/models_cache.json`), or a full model name → `/sin-flow:review` of a teammate's PR also runs Codex as a finder on that model; empty → pr mode runs no Codex |
| `codex_watch` | `""` | `orca` → the Orca workspace card shows each step of that Codex run |
| `workspace` | `""` | `orca` or `git`: where `sin-flow-worktree` makes every stage's worktree; empty → `git`. `orca` also turns on the Stop hook `orca-quiet.sh`: it marks the Orca worktree read while background tasks run |
| `work_remote` | `""` | a git remote for `~/.claude/sin-flow` (work notes and profiles); empty → local only |
| `notes_globs` | `""` | space-separated globs of agent notes in every repo; the shipper never stages a match. The profile key `notes.paths` adds the globs of one repo |

A repo profile may set `models.strong`, `models.mid`, `models.cheap` and `models.<stage>` (`setup`, `sync`, `ingest`,
`plan`, `exec`, `review`, `learning`: the session a hand-off opens for that stage); it wins over the options for that repo. `sin-flow-profile model <tier|stage>`
prints what a stage will use.

The user's own hand-off script gets `FLOW_CWD`, `FLOW_NAME`, `FLOW_MODEL` and `FLOW_PROMPT` (the full shell line to run)
in its environment, exits `0` only when the tab opened, and with `--probe` prints the command it would run and opens
nothing; a non-zero exit makes `sin-flow-handoff` print the command instead. Its arguments are the hand-off options, then
`<stage> <target> [extra]` — or nothing more when the options carry `--prompt <text>`; the target is an absolute path, or a PR number or URL for `sin-flow:review`.

## Onboard (first run in a repo — no profile)

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
   (below); add `## Measure` in one or two lines. Write `notes.mirror: on` into the frontmatter when the Inferred notes line
   says mirrored and the team has more than one author, else `notes.mirror: off` — a default the user flips.
   `notes.paths` (absent by default): space-separated globs of the repo's own agent notes; the shipper never stages them.
   If the profile gets a board, also write `tracker.write.light: off`, `tracker.write.assign: off`,
   `tracker.write.status: off` and `group_by: milestone`. These are defaults that the user changes. The sync
   skill's `## Tracker and switches` gives their meanings.
   Show the file. A personal measurement doc lives beside it as `measure.md`.
5. Hand back to the stage that called setup, at the step it stopped on.

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

Profile format: flat `group.key: value` lines (lists as `["a","b"]`), prose sections `## Inferred`, `## Measure`, `## Run`,
`## Ship`, `## Tracker`, `## Never`. Optional keys the stages read when set: `review.request` (logins exec asks for review and asks again after each reply batch), `review.deploy_bots` (logins of deploy bots that the base watcher skips), `review.ignored_approvers` (logins whose approval `sin-flow-rerequest` does not count, and with no key every approval counts), `gates.lint_fix` (the lint autocorrect commands), `pr.relink_after_bot: on` (shipper saves the PR body once more when a bot added a `Closes` line that GitHub did not link), `tracker.held_statuses` (Status options that a new board leaves out of scope), `gates.spec_cmd` (a test command that takes spec file paths; exec runs the canary with it, and no key means no canary), `review.preship_agent` (a `subagent_type` that exec runs on the final diff before the PR), `notes.paths` (extra globs the shipper treats as agent notes). Keys that setup may write: `tracker.adapter`, `tracker.write.light`, `tracker.write.assign`, `tracker.write.status`, `group_by`. Required: `key`, `repo.slug`, `measure.doc`. Never a secret — pointers only.

## Check (every later run)

Run each check; print one line per layer, then exactly `all good` when all are `✓`, else one row per problem with
one fix. `✗` = a stage cannot work; `!` = it can, marked "not measured".

| layer | checks | fix offered |
|---|---|---|
| flow | `claude plugin list` shows `sin-flow` enabled; `sin-flow-profile`, `sin-flow-infer`, `sin-flow-handoff` on PATH; the Stop hook `work-commit.sh` in the plugin's `hooks/hooks.json`; `gh auth status`; `git`, `jq`, `bash` | `claude plugin install sin-flow@sin-flow`; `gh auth login`; `brew install …` |
| user | `~/.claude/sin-flow/{profiles,work,reviews}` exist; `git -C ~/.claude/sin-flow status --porcelain` empty or committable; `~/.claude/sin-flow/user.md` has frontmatter keys → `!` "the preferences are not migrated to the plugin options", fix: `sin-flow-profile migrate-user`; `work_remote` set → `git ls-remote` reachable, unset → `!` "notes are local only"; every value is read with `sin-flow-profile user <key>`; `handoff` is `auto`, `same-session`, `print`, `tmux`, `cmux`, `iterm`, `ghostty`, `warp`, `orca` or an executable path; `claude plugin configure <id> --json` lists `context_guard` as unconfigured → `!` "the context guard uses the default 40", fix: Install step 3's `context_guard` question, then set `context_guard: <N>`; the same list holds `limit_guard` → `!` "the limit guard reads any status line that writes the state file", fix: Install step 3's `limit_guard` question; `limit_guard: on` and `statusLine.command` of `S` contains `sin-flow-statusline` → `cmp` the copy in `~/.claude/sin-flow/bin/` with `${CLAUDE_PLUGIN_ROOT}/bin/sin-flow-statusline`, a difference → `!` "the status line wrapper is out of date", fix: copy it again; same case and the wrapped command names a file that does not exist → `!` "the wrapped status line file does not exist: <path>", fix: restore `statusLine` from the newest `~/.claude/sin-flow/backups/*/settings.json`, or Install step 3's wrapper install again; `limit_guard: on`, no wrapper and no own writer (Install step 3 item 3) → `!` "the limit guard has no writer", fix: Install step 3's wrapper install; under a terminal name `sin-flow-handoff --check <name>` prints `ok` (else `!` with the printed reason, fix: install it or `handoff: print`); under `auto` `sin-flow-handoff --detect` names a terminal (`none` → `!` quoting the `--detect` line, "the hand-off prints the command", fix: Install step 4's terminal question and `--check`); `sin-flow-profile model strong`, `… mid`, `… cheap` each print an alias (exit 2 → `✗`, fix: the value it names); `tail -3 ~/.claude/sin-flow/stop-commit.log` has no `failed`; `tmutil destinationinfo` → warning only | `git init`; `chmod +x <handoff path>`; "set up Time Machine" |
| project | `sin-flow-profile validate` (required keys, paths, `sources.*` env files: present, `600`, git-ignored, variable present); `gh repo view <slug>`; `git ls-remote --heads origin <base>`; every gate command's binary on PATH; `sin-flow-infer` vs `## Inferred` — base or `gate files:` changed?; the gates named again from those files vs the stored `gates` lines — changed?; each source's preflight/verify | `sin-flow-infer --write <key>`, then name the gates; `chmod 600 <file>`; "add to .gitignore"; "open the tunnel: <tunnel>" |

A source that is unreachable now (tunnel closed, VPN off, SSO expired) is a `!` row with its human step, never a failure.

```
sin-flow:setup <date>
[✓] flow      skills N/N, sin-flow-* on PATH, Stop hook ok, gh auth ok
[✓] user      ~/.claude/sin-flow ok, git clean, remote: — (local only), prefs: en · squash · new-commit · handoff auto (iterm) · models opus/sonnet/haiku
[✓] project   <key>: profile valid · base <b> on origin · gates ✓ · measure: <doc|none> · sources: <names>
all good
```

## Add — `/sin-flow:setup add <source>`

For a source without a `.env.<source>_readonly` file the user already keeps, or to re-verify one that has it.

1. Ask only: where the credential lives (file) and the variable name, plus one sentence on what it is for. Default file
   name `.env.<source>_readonly` in the main checkout root.
   When the file does not exist yet, give the user one line to run in their own terminal, never through `!`, because
   the `!` shell cannot read input: `( umask 077; read -rs v; printf '<VAR>=%s\n' "$v" > <abs file> )`, then paste the
   value and press Enter. For a new database role, the user runs `openssl rand -hex 24` in that terminal and uses the output for the role and the file.
2. `git check-ignore -q <file>` in the repo; not ignored → fix "add to `.gitignore`" after a yes. `chmod 600` after a yes.
3. One harmless call, never a write — the provider table:

| provider | call | records |
|---|---|---|
| Postgres (`kind: postgres`) | open the tunnel if `tunnel` is set (bounded: `timeout 60 ssh -N -L …` in the background), then `psql "$VAR" -tA -c "select current_user, pg_is_in_recovery(), has_table_privilege(current_user, '<table>', 'INSERT'), (select count(*) from information_schema.table_privileges where grantee = current_user and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE'))"` | `readonly: "verified <date>: role …, INSERT = false, 0 write grants"` |
| Postgres via IAM (`kind: postgres-iam`) | the profile's `preflight`, then the measure doc's connect recipe with `select current_user, pg_is_in_recovery()` | `readonly: verified …` when the role has no write grant |
| Cloudflare | `curl -s -H "Authorization: Bearer $VAR" https://api.cloudflare.com/client/v4/user/tokens/verify` → `.result.status` only | `status: "active <date> (permissions not exposed by verify)"` |
| AWS | `aws sts get-caller-identity --query Arn` | `status: "active <date> (identity only)"` |
| GitHub | `gh auth status` | scopes when shown |
| other HTTP API | one `GET` of a small read endpoint the user names | `status: "active <date> (HTTP <code>)"` |

   The call shows write rights → say so and do not record the source until the user confirms.
4. Write to the profile:
   `sources.<name>.{kind, env_file, var, base_url, tunnel, preflight, verify, readonly|status, purpose}` — `env_file` is
   the file name relative to the main checkout, never a value. Add one `## Measure` line naming when to use the source.
5. Offer an allow-rule in the repo's `.claude/settings.local.json` (`Bash(psql *)`, `Bash(curl -s -H * <base_url>/*)`,
   and `Bash(<tunnel>)` with the exact `tunnel` string when it is set, so auto mode does not send it to the
   classifier) — only after a yes.
6. Before the final message, grep everything written this run for the credential's first characters, without printing
   them: `( set -a; . <file>; set +a; grep -rlF -- "${VAR:0:24}" ~/.claude/sin-flow | wc -l )` must be `0`.

A second `add` of the same source only re-verifies and updates `readonly`/`status`.
