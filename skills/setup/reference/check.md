# Check

Each later run. A check only reports. The hard rules of `../SKILL.md` apply.

## Run the script

Run `sin-flow-check` in the cwd. It runs the checks of the three layers and changes nothing.
It prints one line for each check: the mark, the layer, the check name, the result, and after `→ fix:` the one fix.

- `✓`: the check is ok.
- `✗` = a stage cannot work; `!` = it can, marked "not measured".
- `?`: a session check. You do it. § Session checks tells how.

Outside a repo the script prints the flow and user rows only. Exit `1` means that one row or more has `✗`.
A `✗ project profile` row with "no profile for this repo" means that the mode is onboard: read `onboard.md`.

| layer | the script checks | fix offered |
|---|---|---|
| flow | `claude plugin list` shows `sin-flow` enabled; `sin-flow-profile`, `sin-flow-infer`, `sin-flow-handoff` on PATH; the Stop hook `work-commit.sh` in the plugin's `hooks/hooks.json`; `gh auth status`; `git`, `jq`, `bash` | `claude plugin install sin-flow@sin-flow`; `gh auth login`; `brew install …` |
| user | the three folders; the local git; preferences not migrated; the copy on GitHub; the values of `handoff`, `workspace` and `reviewer_watch`; `context_guard` and `limit_guard` not configured; the status line wrapper, its wrapped file and the writer of the limit guard; the terminal; the three model tiers; the last three lines of `stop-commit.log` | the row names it |
| project | `sin-flow-profile validate` (required keys, paths, `notes.mirror` and `tracker.adapter` scripts executable, `sources.*` env files: present, `600`, git-ignored, variable present); `gh repo view <slug>`; `git ls-remote --heads origin <base>`; every gate command's binary on PATH; `sin-flow-infer` vs `## Inferred` — base or `gate files:` changed? | `sin-flow-infer --write <key>`, then name the gates; `chmod 600 <file>`; "add to .gitignore" |

The script reads every value with `sin-flow-profile user <key>`.

## Session checks

The script cannot do these two. It prints a `?` row for each one. Change that row to `✓` or to a problem row.

- **Gates.** Read `gates.md`. Name the gates again from the files on the `gate files:` line. Compare them with the
  stored `gates` lines of `## Inferred`. Changed → a `!` row, fix: `sin-flow-infer --write <key>`, then name the gates.
- **Sources.** Run each source's preflight/verify, as the profile gives them. Fix: "open the tunnel: <tunnel>".
  A source that is unreachable now (tunnel closed, VPN off, SSO expired) is a `!` row with its human step, never a failure.

## Fixes

Offer the fix of each row. Apply a fix only after a "yes". A fix that names a step of `reference/install.md` is a
question of the install: read only that step, ask its question, then save the answer as that step says.

## Output

Print one line per layer, then exactly `all good` when all are `✓`, else one row per problem with one fix.
The script ends with the three layer lines in this shape. Correct them with the results of the session checks.

```
sin-flow:setup <date>
[✓] flow      skills N/N, sin-flow-* on PATH, Stop hook ok, gh auth ok
[✓] user      ~/.claude/sin-flow ok, git clean, remote: — (local only), prefs: en · squash · new-commit · handoff auto (iterm) · models opus/sonnet/haiku
[✓] project   <key>: profile valid · base <b> on origin · gates ✓ · measure: <doc|none> · sources: <names>
all good
```
