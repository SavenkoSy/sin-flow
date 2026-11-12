# Install

The first run on a machine: `~/.claude/sin-flow` does not exist. The hard rules of `../SKILL.md` apply.
Step 3 shows the current values: `sin-flow-profile user <key>` prints each one, and `../SKILL.md` § Options prints each default.
The check cites the steps of this file by number. Keep the numbers.

1. `mkdir -p ~/.claude/sin-flow/{profiles,work,reviews}`; `.gitignore` = `/*`, `!/.gitignore`, `!/work/`, `!/profiles/`;
   `git init`. `work/` and `profiles/` are one local repo. Setup never creates a remote repository. When `work_remote`
   is set, setup adds it as `origin`, and the Stop hook `work-commit.sh` pushes to `origin` once a day.
2. `command -v gh git jq bash`, `gh auth status`. A miss is a row with its fix (`brew install jq`, `gh auth login`).
3. Run `sin-flow-handoff --detect` first. Then show all settings in one message, with the current values, in this shape:

   ```
   These are your settings. Each one has a default value.

   Chat
     1. Chat language: the language that you write in.
     2. Next stage (hand-off): <item 2 text>

   Pull requests
     3. Merge method for your PRs: squash, one commit.
     4. Review fixes: a new commit on top of the PR.
     5. Branch name: <type>/<id>/<slug>, with no prefix.

   Models
     6. Plans, code changes and the last review: opus.
     7. Agents that read code, write code and run tests: sonnet.
     8. Work on the board: haiku.

   Your notes
     9.  Copy of your plans and evidence: on this computer only.
         The next question is about a copy on GitHub.
     10. Review files: ~/.claude/sin-flow/reviews

   Learning loop
     A learning session reads your earlier flow runs. It finds the
     problems and proposes changes that make your flow better. Each
     change needs your approval.
     11. Learning notes: ~/.claude/sin-flow/learning
     12. Automatic start: off. Give a number, for example 10, to start
         a session after 10 exec runs.
     13. Learning session starts in: the learning notes folder.

   Keep these values? To change an item, give its number.
   ```

   Items and options: 1 `chat_language`, 2 `handoff`, 3 `merge`, 4 `after_review`, 5 `branch_prefix`,
   6 `models_strong`, 7 `models_mid`, 8 `models_cheap`, 9 `work_remote`, 10 `reviews_dir`, 11 `learning_dir`,
   12 `learning_runs`, 13 `learning_cwd`. Item 2 by value: a terminal from `--detect` or set earlier → "starts in a new
   <Terminal> tab."; `none` from `--detect` → "the flow did not find your terminal." and on the next line "It shows the
   command, and then you start the next stage."; `print` → that second line only; `same-session` → "continues in
   this session."; a script path → "your script <path> starts it.". Item 9 with a value → "Copy of your plans and
   evidence: <work_remote>." Item 12 with a number N → "Automatic start: after N exec runs that are not reviewed."
   A yes keeps the values. Numbers → ask about those items only, one per turn. A user whose account has no Opus sets
   `models_strong: sonnet`.

   When `work_remote` is empty, ask as its own question: "Your plans and evidence are on this computer only. Do you
   want a copy in a private GitHub repository? Give the repository URL, or write no." A URL → `work_remote: <url>`, then
   `git -C ~/.claude/sin-flow remote add origin <url>` (`remote set-url` when `origin` exists). No → keep it empty.

   Then ask `context_guard` once, as its own question: "a plan, exec, ingest, sync, review or
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
4. Terminal, only when `--detect` printed `none` and `handoff` is not a terminal name or a script path. Do not quote
   the `none — checked: …` line. Ask "Which terminal do you use: tmux, cmux, iTerm, Ghostty, Warp, Orca, or other?".
   A named one → `sin-flow-handoff --check <name>`: `ok` → `handoff: <name>`; anything else → tell the user the printed
   reason in one line and set `handoff: print`.
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
`default` in `plugin.json`. An unset option keeps its default. `../SKILL.md` § Options prints each key, default and meaning.

The SessionStart hook moves two old option names once (the marker `backups/options-migrated`), with `sin-flow-profile migrate-options`: `codex_review: on`
becomes `extra_reviewers: codex`, and `codex_watch` becomes `reviewer_watch`. A new name that is already set stays.

A repo profile may set `models.strong`, `models.mid`, `models.cheap` and `models.<stage>` (`setup`, `sync`, `ingest`,
`plan`, `exec`, `review`, `learning`: the session a hand-off opens for that stage); it wins over the options for that repo. `sin-flow-profile model <tier|stage>`
prints what a stage will use.

**Model grid.** `${CLAUDE_PLUGIN_ROOT}/examples/models.tsv` names the model and the effort of each session and each
subagent. Its columns are `role`, `level`, `model` and `effort`, tab-separated. To change rows for every repo, write
the header line and only those rows in `~/.claude/sin-flow/models.tsv`. To change rows for one repo, write them in
`~/.claude/sin-flow/profiles/<key>/models.tsv`. `${CLAUDE_PLUGIN_ROOT}/ARCHITECTURE.md` § Model grid has the order of the layers.
`model` is `strong`, `mid` or `cheap` (the options `models_strong`, `models_mid` and `models_cheap`), or `opus`, `sonnet`, `haiku`, `fable`. `effort` is
`low`, `medium`, `high`, `xhigh`, `max` or `-` (none). `sin-flow-profile model <role> [level]` prints the row in use.
A user with no grid file gets the default grid.
