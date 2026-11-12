# Your own scripts

Each step that acts on a system outside the flow reads one key. The value is `off`, a built-in name, or an absolute
or `~` path to an executable file of the user. `workspace` has no `off`, because each stage needs a worktree. A path
replaces the built-in for that step. An unset key keeps the
built-in. The user keeps the script outside the plugin, for example in `~/.claude/sin-flow/`.

| step | key | built-in | example |
|---|---|---|---|
| start the next stage | option `handoff` | `auto` and the terminal names | `examples/handoff.sh.example` |
| make or remove a worktree | option `workspace` | `git`, `orca` | `examples/workspace.sh.example` |
| show each step of an extra reviewer | option `reviewer_watch` | `orca` | `examples/reviewer-watch.sh.example` |
| review the code once more | option `extra_reviewers`, one entry for each script | `codex` | `examples/reviewer.sh.example` |
| merge the user's own PR | the file `~/.claude/sin-flow/merge.sh` | the copy of `examples/merge.sh.example` | the same file |
| copy the plan to the ticket | profile key `notes.mirror` | `github` (`on` is `github`) | `examples/mirror.sh.example` |
| read and write the board | profile key `tracker.adapter` | `tracker.board` (GitHub Projects) | `skills/sync/reference/adapter-contract.md` |

The user's own hand-off script gets `FLOW_CWD`, `FLOW_NAME`, `FLOW_MODEL` and `FLOW_PROMPT` (the full shell line to run)
in its environment, exits `0` only when the tab opened, and with `--probe` prints the command it would run and opens
nothing; a non-zero exit makes `sin-flow-handoff` print the command instead. Its arguments are the hand-off options, then
`<stage> <target> [extra]` — or nothing more when the options carry `--prompt <text>`; the target is an absolute path, or a PR number or URL for `sin-flow:review`.

The workspace script gets one of two commands. `<script> create <repo> <name> <branch> <base>` makes a worktree of
the checkout `<repo>` on the new branch `<branch>` from `<base>`. It prints the absolute worktree path as the last
line and exits `0`. `<script> remove <path>` removes that worktree and exits `0`. Then `sin-flow-worktree` deletes the
local branch. A non-zero exit stops `sin-flow-worktree` with that exit.

The reviewer watch script gets one argument: the text of the step, for example `codex: finding`. It runs in the review
tree. The flow ignores its output and its exit code.

Each reviewer script is one more finder in the exec review. Its name is the file name up to the first dot, and it
must be unique and not a name of the flow (`codex`, `context`, `code`, `fit`, `all`, `verify`, `settle`, `findings`,
`tree`). The script runs in the review tree and gets `<command> <pkg> <name>`. `<pkg>` is the review package: its
`manifest.env` gives `TREE`, `SHA` and `BASE`, and its `diff.patch` holds the diff. Its stderr goes to
`<pkg>/<name>/live.log`.

- `<script> find <pkg> <name>`: print each finding on stdout in the finder format of `agents/reviewer.md` § Finder
  file, without the `LENS:` line. Exit `0`. The flow writes `<pkg>/findings/<name>.md` and counts the `F` rows.
- `<script> reply <pkg> <name>`: read `<pkg>/verdict.md`. Your rows have `<name>/F<k>` in their `from:` or claim.
  For each row you contest, print `<row> | contest | <argument>` and `  evidence: <file:line quote>`. Exit `0`. Each
  row you do not print is accepted.

A non-zero exit, a run of more than 15 minutes or a name that is taken writes the reason to `failed.txt`. Then the
review goes on without that reviewer, and the other reviewers still run. `/sin-flow:review` of a PR runs only `codex`.
`codex-trial.tsv` records only `codex`.

`sin-flow-profile <key> mirror` prints the mirror route of a repo: `off`, `github` or the expanded script path. An
absent `notes.mirror` follows the `## Inferred` notes line. The mirror script gets one of three commands. `<ticket>`
is the id on the plan's `ticket:` line, and `<file>` is a `sin-flow-mirror` copy, never split.

- `<script> put <ticket> <file>`: keep one copy of the plan on the ticket. Make it the first time, then replace it.
  Print its URL and exit `0`.
- `<script> add <ticket> <file>`: add one evidence file to the ticket as a new note. Print its URL and exit `0`.
- `<script> get <ticket>`: print the time of the last change of the copy (ISO 8601, UTC) on the first line, then the
  copy. Exit `1` when the ticket has no copy.

Any other exit: the stage writes the first stderr line to its ledger or report and continues. The local `plan.md`
stays the truth.
