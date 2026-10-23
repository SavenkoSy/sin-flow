# Architecture

sin-flow has three layers. Each change goes to exactly one of them.

| layer | where | holds |
|---|---|---|
| plugin | this repo | the mechanism and the defaults that every user starts from |
| user | the plugin options (`userConfig`), saved in the user's Claude Code settings | the preferences of one user: language, terminal, models, Codex, merge method |
| profile | `~/.claude/sin-flow/profiles/<key>/` | the facts of one repo or one team: base, gates, sources, reviewers, tracker |

The user and profile layers are never in this repo. The plugin declares `userConfig` in `.claude-plugin/plugin.json`, and
the answers live in the user's settings, not in the plugin. `sin-flow-profile user <key>` is the one reader.

## Rules

1. A mechanism for one tool or one practice (Orca, Codex, CircleCI, a terminal, a team's reviewer habit) does
   nothing until a user option or profile key turns it on. With every option at its default and a minimal profile, the plugin
   behaves as it did before that mechanism existed.
2. The plugin reads the key. The value lives only in the user or profile layer. `userConfig` in `plugin.json` and the
   setup option table (`skills/setup/SKILL.md`) name each key, its default and its meaning.
3. No plugin text carries one user's quote, one repo's words, a private repo name, a profile key, a login or a
   local path. Examples use placeholders.
4. One user's complaint becomes a plugin rule only when it holds for a user with other tools and another team.
   Otherwise it becomes a key.

## Check

`scripts/check-layers.sh` runs in CI on every PR and in the local gates.

- Every script under `bin/`, `hooks/` and `skills/` that calls a third-party tool must read a user option
  (`sin-flow-profile user`, `CLAUDE_PLUGIN_OPTION_<KEY>` or `${user_config.KEY}`) or a profile key. `bin/handoff/` adapters are exempt: `handoff:` selects them.
- Locally, it also fails when an added line holds a word from the user's profiles (repo slugs, repo folder names,
  the home path) that the plugin did not hold before. The words are read at run time and never committed.
