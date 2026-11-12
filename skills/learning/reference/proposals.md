# Proposals: diffs the user approves

## Mode: author or user

`scripts/mode.sh` prints the mode once for each run.

- **author**: the plugin is loaded in place from a git checkout the user can commit to. `${CLAUDE_PLUGIN_ROOT}` is
  not under a `plugins/cache/` folder and is inside a git work tree with a writable git dir. Proposals may target
  `skills/`, `agents/`, `hooks/` and `bin/` of that checkout, as well as the plugin options and `profiles/<key>/`.
- **user**: the plugin runs from the plugin cache, which an update overwrites. Proposals are applied only to the
  plugin options (`claude plugin configure <id> --values-stdin`) and `~/.claude/sin-flow/profiles/<key>/`. A proposal
  with a target in the flow layer is never applied. It goes to `LD/proposals-for-author.md` as one block that the
  author can act on without the digest: `## <YYYY-MM-DD> <target below the plugin root>`, the version (`basename
  ${CLAUDE_PLUGIN_ROOT}`), the problem in the two numbers, counts with their filter set and repos, **now**,
  **proposed**, **effect**. These blocks need no approval.

The user's settings (the plugin options, their copies of `examples/`, `profiles/<key>/`) hold how the flow works for
this user. The plugin holds the mechanism and the defaults that every user starts from. Only in author mode does a
finding also ask whether the mechanism itself failed.

## When a proposal is due

A proposal needs a mode counted on 2 or more sessions, or the user's explicit ask. An open inbox row is an ask. When
a hook, a script or a check can carry the fix, propose that first and a text line second. A proposal never stops or
blocks a stage to enforce a precondition that the flow could set up itself. It fixes how the stage is opened, and a
stage in the wrong state keeps its work.

Every run carries one **Deletions** entry, with the same evidence as an addition: lines of the stage skill that no
read session followed, lines that a hook or another line contradicts, lines that a newer rule supersedes, and pairs
of lines that say the same thing, merged into one. A run that adds and never deletes is incomplete.

A **Rewrite** proposal is due when the stage skill grew in each of the last 3 digests of that stage and no Rewrite of
that stage was carried within those 3 digests. It is the whole skill from scratch, with only what a read
session followed or a hook enforces. Write it as the proposed copy `D/flow-<stage>/proposed/plugin/skills/<stage>/SKILL.md`,
then copy it to `D/flow-<stage>-rewrite.md` for the user to read. The user approves it as a whole.

A declined proposal stays in the digest marked `declined <date>`. The next run does not propose it again unless new
rows contradict the decline.

## Fields

One proposal for each numbered entry, each with:
- **layer**: `user` (a plugin option, the user's copy of an `examples/` script), `profile` (`profiles/<key>/`) or
  `plugin` (the mechanism, for every user). A proposal that rests on sessions or a complaint from one repo, or on the
  words of one user, is `user` or `profile` by default. It is `plugin` only with evidence from 2 or more users or a
  defect in the mechanism. A `plugin` proposal holds no word that only one repo uses. Read it against each repo key
  in its evidence and one key that is not there.
- **switch**: the plugin option or profile key that turns the behaviour on, read from the proposed text. `author`
  when it acts only in author mode or only in this user's own setup (the apply scripts, a step that only the plugin
  author runs, this user's terminal, account or bot). `none` when it acts for every user. With a key, say what a user
  without that key gets. The chat report sorts the proposals by this field, never by the target file.
- **target**: a `file:line` in `${CLAUDE_PLUGIN_ROOT}/skills/<stage>/SKILL.md`,
  `${CLAUDE_PLUGIN_ROOT}/agents/<name>.md` or `${CLAUDE_PLUGIN_ROOT}/skills/review/reference/lenses/<lens>.md`, a hook
  path, `${CLAUDE_PLUGIN_ROOT}/bin/…`, `~/.claude/sin-flow/profiles/<key>/profile.md`, a plugin option by its key,
  or the user's copy of an `examples/` script under `~/.claude/sin-flow/`. Never another file.
- **writers**: every place that writes or repeats the thing the proposal fixes, found by grep, listed. A proposal
  that changes fewer than all of them says which it leaves and why.
- **now**: the current text, verbatim, 6 lines or fewer. **proposed**: the replacement, verbatim.
- **evidence**: the digest section and the count it rests on, with the repos.
- **effect**: the `scorecard.tsv` column, run-log column or digest count that must move, which way, and within how
  many runs of the stage. The next Effect check reads this line.
- **blocking?**: `no` for text, thresholds and order. `yes` for anything that denies a tool call, exits non-zero or
  stops a session. A `yes` proposal names the live probe that must run first: which repo, which command, and what
  output proves that it does not block the wrong caller.

## The proposed copy

Each proposal that the mode lets this run apply is a whole file before the chat report. There is one path rule:

- a file of the plugin: `D/flow-<stage>/proposed/plugin/<path below the plugin root>`.
- a profile file or the user's copy of a script: `D/flow-<stage>/proposed/user/<path below ~/.claude/sin-flow>`.

Copy the live file there with `cp -p`, then edit the copy. A new file is written there directly. In the same step,
append one line `<root>\t<path>\t<sha256 of the live file, or absent>` to `D/flow-<stage>/proposed/base.tsv`. The root is
`plugin` or `user`, the path is the one below it, and the sha is `shasum -a 256` of the live file before the edit. Put all proposals
of the stage for one file into one copy. `scripts/make-apply.sh` reads these trees, and it builds `targets.tsv`,
`patches.diff` and the apply scripts. A plugin option is not a file: name its key and value in the proposal, and
the main thread sets it after the approval.
