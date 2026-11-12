# Apply: from the proposed copies to the live files

## What `make-apply.sh` builds

`scripts/make-apply.sh D` reads every `D/*/proposed/plugin/` and `D/*/proposed/user/` tree and writes `D/apply/`:

- `targets.tsv` with the columns `layer root path target sha256 proposed stages`. `target` is the real path below
  one root: the resolved `${CLAUDE_PLUGIN_ROOT}` or `~/.claude/sin-flow`. `sha256` is the live file that the proposed copy started from, read from
  `D/*/proposed/base.tsv` (`shasum -a 256`), or `absent` for a new file. A file with no record there gets the sha of
  the live file at build time. A copy equal to the live file gets no row.
- `proposed/`, the final copy of each target, and `patches.diff`.
- `apply-user.sh` for the `user` and `profile` layers, and `apply-plugin.sh` for the `plugin` layer.

When two stages propose to the same file, the script merges the two copies against the live file. When they change
the same lines, it stops and names the file. Then the main thread writes the merged copy to
`D/merged/proposed/<root>/<path>` and runs the script again. That copy wins.

Each apply script does these steps:
1. It checks the live sha of each target against `targets.tsv`. When one differs, another session edited the file.
   The script stops and changes nothing. Rebase the copy onto the live file, record the new base sha in `base.tsv`, and run `make-apply.sh` again.
2. It copies each target to `LD/backups/<date>/<path below its root>` first. A backup from an earlier apply of that
   day stays. Then it copies the proposed file with `cp -p` to `<target>.new` and moves it over the target with `mv`,
   so that a script that runs at that moment keeps its old text. It checks the target with `cmp`. When a backup copy,
   a rollback copy or the file copy fails, it restores every target and stops with exit 4, before the next target.
3. `apply-plugin.sh` only: it runs `bash scripts/check-layers.sh` in the checkout. A failure restores every target
   and stops.

## After the user approves

1. The ledger quotes the user line verbatim with its HH:MM. An apply script runs only after that line exists in the
   transcript.
2. Make a partial approval, or a scope change in the user's line, in the copies under `D/*/proposed/` first. Then
   run `make-apply.sh D` again.
3. Run `bash <abs D>/apply/apply-user.sh`, then `apply-plugin.sh` in author mode, once each. Never edit a live file
   piece by piece, and never straight from the list. When the call is denied, give the user the line
   `! bash <abs D>/apply/apply-<layer>.sh`. Set each approved plugin option with `claude plugin configure`.
4. When the applied text differs from the proposed text, add a `⚠ CORRECTION` note to the proposal entry, with why.
5. Author mode, after the applies: tell the user to run `/reload-plugins`. Ship the checkout changes as one PR
   through `sin-flow:shipper` in ship mode, after its `gate` mode ran green on the same tree. Use the profile that
   `sin-flow-profile key` resolves in the plugin checkout.
6. Before the PR goes into the chat report, review it from the plugin checkout: `cd "${CLAUDE_PLUGIN_ROOT}" &&
   skills/review/reference/build-package.sh pr <PR> <abs D>/review-pkg`, then `pipeline.md` as written. Its
   `reproduces` rows go to one fix as a new commit through `sin-flow:shipper` `gate`, then `commit` mode. The report
   names the review file and the rows left as `possible`.
7. In user mode, append each flow-layer proposal to `LD/proposals-for-author.md`, by `proposals.md`.
