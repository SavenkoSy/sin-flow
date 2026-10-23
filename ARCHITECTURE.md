# Architecture

sin-flow has three layers. Each change goes to exactly one of them.

| layer | where | holds |
|---|---|---|
| plugin | this repo | the mechanism and the defaults that every user starts from |
| user | `~/.claude/sin-flow/user.md` | the preferences of one user: language, terminal, models, Codex, merge method |
| profile | `~/.claude/sin-flow/profiles/<key>/` | the facts of one repo or one team: base, gates, sources, reviewers, tracker |

The user and profile layers are never in this repo. The same split is the Claude Code plugin model: a plugin
declares `userConfig`, and the answers live in the user's settings, not in the plugin.

## Rules

1. A mechanism for one tool or one practice (Orca, Codex, CircleCI, a terminal, a team's reviewer habit) does
   nothing until a `user.md` or profile key turns it on. With an empty `user.md` and a minimal profile, the plugin
   behaves as it did before that mechanism existed.
2. The plugin reads the key. The value lives only in the user or profile layer. The setup key table
   (`skills/setup/SKILL.md`) names each key, its default and its meaning.
3. No plugin text carries one user's quote, one repo's words, a private repo name, a profile key, a login or a
   local path. Examples use placeholders.
4. One user's complaint becomes a plugin rule only when it holds for a user with other tools and another team.
   Otherwise it becomes a key.

## Check

`scripts/check-layers.sh` runs in CI on every PR and in the local gates.

- Every script under `bin/`, `hooks/` and `skills/` that calls a third-party tool must read a `user.md` or
  profile key. `bin/handoff/` adapters are exempt: `handoff:` selects them.
- Locally, it also fails when an added line holds a word from the user's profiles (repo slugs, repo folder names,
  the home path) that the plugin did not hold before. The words are read at run time and never committed.
