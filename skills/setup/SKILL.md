---
name: setup
description: 'One idempotent command with four modes. Install: the first run on a machine creates ~/.claude/sin-flow/{profiles,work,reviews} and its local git. Onboard: the first run in a repo infers what the repo and GitHub can answer, asks at most three questions, one per turn, and writes ~/.claude/sin-flow/profiles/<key>/profile.md. Check: every later run only checks all three layers and ends in exactly "all good" or a list where each row carries one fix, applied only after a "yes". `add <source>` registers a read-only credential without ever reading its value. Use when invoked as `/sin-flow:setup` or `/sin-flow:setup add <source>`, when a flow stage reports "no profile", or when the user says "set up the flow", "check the flow", "add access to …".'
---

# sin-flow:setup — install → onboard → check → add

One command, four modes, each idempotent: a second run asks nothing and changes nothing when everything is in place.

Chat with the user in the `chat_language` option (`sin-flow-profile user chat_language`), or in the language the user writes in when it is absent. Fixed phrases defined here (`all good`, the questions, the fixes) are written in ASD-STE100 English and rendered in that language. Every file you write is English. Tell the user what a setting does, never its option key.

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

## Mode

Find the mode first. Then read the file of that mode. Do not read the file of another mode, except the one install step that a check fix names.
All files are in `${CLAUDE_PLUGIN_ROOT}/skills/setup/reference/`.

- Key: `sin-flow-profile key` (cwd → `git remote get-url origin` → profile whose `repo.slug` matches; else `<repo>/.claude/flow.md`).

Use the first row that holds:

| condition | mode | read |
|---|---|---|
| `add <source>` as the argument | **add** | `add.md` |
| `~/.claude/sin-flow` missing | **install** | `install.md` |
| No key and cwd is a repo, or a stage reported "no profile" | **onboard** | `onboard.md`, and `gates.md` at its step 4 |
| each later run | **check** | `check.md`, and `gates.md` when the cwd has a profile |

- An install in a repo with no key continues with onboard.
- Cwd is not a repo → install/check of the flow and user layers only.
- Onboard for another stage ends at its step 5: hand back to the stage that called setup, at the step it stopped on.
- A check ends in exactly `all good`, or in a list where each row carries one fix.

## Options

The preferences are the `userConfig` options of the plugin. The manifest is the one source of each key, its default
and its meaning. When a mode needs them, print them with one command:

```
jq -r '.userConfig | to_entries[] | "\(.key)\t\(.value.default // "")\t\(.value.description)"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"
```

`sin-flow-profile user <key>` prints the value in use. Do not keep a second list of the options in a skill.

## Files

| file | holds |
|---|---|
| `reference/install.md` | the folders, the tools, the settings message and its questions, the guards, the terminal, the allow rules, the model grid |
| `reference/onboard.md` | the upstream repo step, `sin-flow-infer`, the questions, the profile and its format |
| `reference/gates.md` | how to name the gates from the CI and lefthook files |
| `reference/check.md` | `sin-flow-check`, how to read its rows, the session checks, the output block |
| `reference/add.md` | the credential file, the harmless call for each provider, the profile keys of a source |
| `reference/user-scripts.md` | "Your own scripts": the contract of each script of the user. Other stages cite it |
