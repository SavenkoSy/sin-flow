# Add: `/sin-flow:setup add <source>`

The hard rules of `../SKILL.md` apply.

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
