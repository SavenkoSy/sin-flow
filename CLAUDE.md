# sin-flow

A Claude Code plugin: the ticket-to-PR flow as skills, agents, hooks and CLIs.

## What lives where

- `.claude-plugin/plugin.json`: the plugin manifest; `.claude-plugin/marketplace.json`: this repo as a one-plugin marketplace.
- `skills/<stage>/`: one skill per stage (setup, sync, ingest, plan, exec, review, learning), invoked as `/sin-flow:<stage>`.
- `agents/`: subagents, dispatched as `sin-flow:<agent>`.
- `hooks/hooks.json` + `hooks/scripts/`: hooks, referenced through `${CLAUDE_PLUGIN_ROOT}`.
- `bin/`: CLIs on the Bash PATH while the plugin is enabled (`sin-flow-profile`, `sin-flow-infer`, `sin-flow-handoff`, `sin-flow-worktree`, `sin-flow-rerequest`); `bin/handoff/`: terminal adapters.

## Rules

- Every change belongs to one layer: plugin, user or profile. Read `ARCHITECTURE.md` before a change to `skills/`, `agents/`, `hooks/` or `bin/`; `scripts/check-layers.sh` must pass.

- Work through pull requests to `main`; never push to `main` directly.
- No AI attribution: no `Co-Authored-By`, no "Generated with" line, in commits or PR bodies.
- No code comments in any language; tool directives are allowed.
- User data lives in `~/.claude/sin-flow/` (profiles, work, reviews, runs log), never in the plugin.
- Call the CLIs by name, never by absolute path; reference plugin files through `${CLAUDE_PLUGIN_ROOT}`.
