# review pipeline

The one procedure every caller follows once a package exists: `/sin-flow:review` in pr mode, sin-flow:exec
in exec mode. Input: `PKG`, the path `build-package.sh` printed. `LENSES` = the `lenses/` folder
beside this file. Formats, lens roles and return
lines live in the `sin-flow:reviewer` agent; what each lens looks for lives in `$LENSES/<lens>.md`. This file
is only the order, the checks and the render.

You are the orchestrator. You dispatch, check one-line returns and render with shell. You never read
`findings/*.md`, `diff.patch` or the code, and you never judge a finding — that is `verify`'s job.
The only package files you touch are `manifest.env`, and `context.md` + `verdict.md` through the
render and extract commands below.

## 1. Manifest

`cat "$PKG/manifest.env"`. Pick the finders:

| DEPTH | Finders |
|---|---|
| `quick` | `all` |
| `thorough` | `code`, `fit` |

Each finder is a bundle: its lens file names the checklists (`$LENSES/<checklist>.md`) it runs in one
agent. No lens runs twice.

## 2. How every lens is dispatched

Agent tool, `subagent_type: "sin-flow:reviewer"`, the tier from this table, passed as its resolved alias, `description: "sin-flow:review <lens>"`,
and the prompt exactly `Package: <PKG>. Lens: <lens>. Lenses: <LENSES>.` — nothing else. The agent reads what it needs from the package; context
added to the prompt biases the lens and is paid for twice.

| Lens | Tier |
|---|---|
| `context` | mid |
| `code` | strong |
| `fit` | mid |
| `all` | strong |
| `verify` | strong |
| `settle` | strong |

## 3. Order

1. `context` — pr mode only, alone; the finders wait for its return. Exec mode skips it: finders and
   `verify` find the entry points themselves.
2. The finders for the depth — **one message, all in parallel**, one `sin-flow:reviewer` each. Unless
   the caller's skill says this round runs without Codex, the same message also runs `bash $LENSES/../codex.sh find "$PKG"` as a background Bash call. The
   script reads the `codex_review` option and prints `CODEX · off` when Codex is not on. In pr mode it runs only when
   `codex_model_pr` names a model family or a model, and runs on the newest model of that family.
3. `verify` — alone, after every finder and the Codex run are back or recorded as failed. It is a fresh agent
   and sees only the package, never your summary.
4. **Codex turns** — exec mode, only when `findings/codex.md` exists. Run each step once, in this order:
   1. `bash $LENSES/../codex.sh reply "$PKG"` (foreground, up to 15 min). Codex reads `verdict.md` and contests
      rows with quoted code.
   2. `settle` — one `sin-flow:reviewer`, only when the reply line shows more than 0 contested. It gives the final
      status of each contested row and rewrites `verdict.md`. Nobody replies to it.
   3. `bash $LENSES/../codex.sh stats "$PKG"` — prints the trial line and appends it to
      `~/.claude/sin-flow/codex-trial.tsv`.

## 4. Check every return

A return passes when the line matches its pattern **and** the file exists with the matching first
line. Check the files in one Bash call: `head -1 "$PKG"/findings/*.md`, plus `"$PKG/context.md"` in pr mode (and
`head -1 "$PKG/verdict.md"` after verify).

```
context  ^CONTEXT · entry [^ ]+:[0-9]+ · <PKG>/context\.md$
         first line: CONTEXT · entry …
finder   ^LENS <lens> · [0-9]+ findings · <PKG>/findings/<lens>\.md$
         first line: LENS: <lens> · <n> findings  (same <n>)
verify   ^VERIFY · [0-9]+ in · [0-9]+ kept · [0-9]+ rejected · blocking (yes|no) · <PKG>/verdict\.md$
         first line: VERIFY · …  (same numbers)
codex    ^LENS codex · [0-9]+ findings · <PKG>/findings/codex\.md$   (a finder line)
         or ^CODEX · (off|skipped · .+)$ — no file, nothing to re-run
reply    ^CODEX REPLY · ([0-9]+ contested · [0-9]+ accepted · <PKG>/codex/reply\.md|none · .+|skipped · .+)$
settle   ^SETTLE · [0-9]+ contested · [0-9]+ changed · <PKG>/verdict\.md$
         first line of <PKG>/codex/settle.md: SETTLE · …  (same numbers)
stats    ^CODEX · found [0-9]+ · kept [0-9]+ · unique [0-9]+ · contested [0-9]+ · changed [0-9]+$
```

The Codex script is never re-run: `skipped` already wrote its reason to `failed.txt`, and the review goes on
without Codex. A failed `settle` → re-dispatch once; still bad → `echo "lens settle failed: …" >> "$PKG/failed.txt"`,
and `verdict.md` from `verify` stands.

A malformed return, an `ERROR · …` return or a missing file → re-dispatch that lens once with the
same prompt (failed finders together, in one message). Still bad →
`echo "lens <lens> failed: <the return line, or no file>" >> "$PKG/failed.txt"` and go on:
finders work without `context.md`; the render works without `verdict.md`.

## 5. Render the review file

Run as is, with `PKG` set. It prints the review file path.

```bash
. "$PKG/manifest.env"
if [ "$MODE" = pr ]; then NAME=$KEY-$PR-$(printf %.8s "$SHA"); else NAME=$KEY-$(git -C "$TREE" branch --show-current | tr / -); fi
DIR=$(sin-flow-profile user reviews_dir)
case "$DIR" in "~"/*) DIR=$HOME/${DIR#\~/} ;; esac
OUT=$DIR/$NAME.md
[ "$MODE" != pr ] && [ -e "$OUT" ] && ! grep -q "$SHA" "$OUT" && OUT=$DIR/$NAME-$(printf %.8s "$SHA").md
V=$PKG/verdict.md
mkdir -p "$(dirname "$OUT")"
{
  if [ "$MODE" = pr ]; then
    printf '# %s · PR %s · %s\n\n' "$REPO" "$PR" "$(sed -n '1s/^# PR [0-9]* · //p' "$PKG/pr.md")"
  else
    printf '# %s · %s\n\n' "$REPO" "$NAME"
  fi
  printf 'REPO=%s PR=%s SHA=%s DEPTH=%s STACK=%s LINES=%s RISK=%s\n\n' \
    "$REPO" "$PR" "$SHA" "$DEPTH" "$STACK" "$LINES" "$RISK"
  if [ -s "$PKG/context.md" ]; then tail -n +2 "$PKG/context.md"; elif [ "$MODE" = pr ]; then echo 'context: lens failed'; fi
  echo
  if [ -s "$V" ]; then
    printf '## Findings\n\n| # | severity | reality | file:line | claim |\n|---|---|---|---|---|\n'
    awk -F' [|] ' '/^K[0-9]+ [|] / { c = $5; for (i = 6; i <= NF; i++) c = c " / " $i
      printf "| %s | %s | %s | `%s` | %s |\n", $1, $2, $3, $4, c }' "$V"
    awk -F' [|] ' '/^K[0-9]+ [|] / { printf "\n### %s · %s · %s · %s\n\n", $1, $2, $3, $4; on = 1; next }
      /^(R[0-9]+ [|] |BLOCKING:)/ { on = 0 }
      on && /^  (explain|comment_en|settle): / { sub(/^  /, ""); print }' "$V"
    printf '\n## Rejected\n\n'
    grep -E '^R[0-9]+ [|] ' "$V" | sed 's/^/- /'
    grep -qE '^R[0-9]+ [|] ' "$V" || echo none
    printf '\n## Verdict\n\n'
    head -1 "$V"
    grep -E '^BLOCKING:' "$V"
  else
    printf '## Verdict\n\nverify: lens failed — findings are unverified and not rendered\n'
  fi
  if [ -s "$PKG/failed.txt" ]; then echo; cat "$PKG/failed.txt"; fi
  printf '\nPackage: %s\n' "$PKG"
} > "$OUT"
mkdir -p "${OUT%.md}.findings" && cp "$PKG"/findings/*.md "$V" "${OUT%.md}.findings/" 2>/dev/null
[ -d "$PKG/codex" ] && cp "$PKG"/codex/*.md "$PKG/codex/live.log" "${OUT%.md}.findings/" 2>/dev/null
echo "$OUT"
```

The finder outputs, and the Codex reply, settle log and live log, are copied beside the review file into `<review>.findings/`: the package lives in a
scratchpad and disappears, and a later `/learning` needs them to tell «the lens never saw it» from «saw
it and did not raise it».

The review file is the durable record: `/sin-flow:review post` reads the `### K<k> · … · <file>:<line>`
headings and `comment_en:` lines back out of it, so never hand-edit their shape.

## 6. Exec mode — what the caller takes out

sin-flow:exec acts on `verdict.md` through these extracts, never by reading findings:

```bash
grep -E '^K[0-9]+ [|] [a-z]+ [|] reproduces [|]' "$PKG/verdict.md" | cut -d' ' -f1 | paste -sd, -
awk '/^K[0-9]+ [|] [a-z]+ [|] possible [|]/ { print; on = 1; next } /^(K|R)[0-9]+ [|] |^BLOCKING:/ { on = 0 }
  on && /^  settle: /' "$PKG/verdict.md"
head -1 "$PKG/verdict.md"
```

- `reproduces` rows (first command) → ONE fix dispatch with the complete list — the verdict path
  plus those K numbers — then the re-review the caller's skill names.
- `possible` rows with their `settle` (second command) → the PR body section
  «Not fixed — does not reproduce».
- Rejected → one ledger line with the counts from the verdict header (third command).
