---
name: review
description: 'Review stage of the flow, for any repo with a flow profile. Reviews a PR through the review pipeline — a package of the code at the PR''s SHA, a context pass (what the PR does, the flow from its entry point, three files to read first), one finder agent at quick, two at thorough (code checklists; team, docs, tests, intent) and one verify pass that sorts every finding into reproduces / possible / invented with a quoted file:line. Depth comes from the profile: review-team.md in the profile folder → thorough, none → quick. Writes the review to the reviews folder from the user preferences as <key>-<pr>-<sha8>.md and summarizes it in chat in the chat language. Posts the high/med reproduces findings itself, never the rest, as ONE review with event COMMENT through the review-poster agent; `recheck` reviews only the commits since the last review and approves the PR itself when nothing is left open. Must run inside the product repo. Use when invoked as "/sin-flow:review <PR>" or "/sin-flow:review post <n,n>", or when the user says "look at this PR", "review a teammate''s PR", "what is in this PR".'
argument-hint: "<PR number|url> [quick|thorough] [--at <sha>] [--base <sha>] | post <n,n,…> | recheck <PR>"
---

# Flow Review

```
/sin-flow:review <PR number|url> [quick|thorough] [--at <sha>] [--base <sha>]
/sin-flow:review post <n,n,…>
/sin-flow:review recheck <PR number|url>
```

Chat with the user in the `chat_language` option (`sin-flow-profile user chat_language`), or in the language the user writes in when it is absent. Headings and fixed phrases defined here are rendered in that language. Files, commits, PRs and issues are always English.

`REF=${CLAUDE_PLUGIN_ROOT}/skills/review/reference` — the package script, the pipeline, the lenses.

Depth: an explicit `quick` / `thorough` wins; otherwise `build-package.sh` picks `thorough` when the
profile folder has `review-team.md` and `quick` when it does not. `quick` = context + `all` + verify;
`thorough` splits the finder into `code` (`<strong>`) and `fit` (`<mid>`). `--at <sha>` reviews the PR as it
was at that commit. `--base <sha>` sets the fork point explicitly — for a PR whose base branch was
rewritten after that commit.

You dispatch and relay. The package script, the pipeline and the agents do the work: you never read
`diff.patch`, `findings/*.md` or the code, and you never re-judge a verdict.

`CTX GUARD` in a tool result: finish the step in flight and its chat (the review file is the trail), then say in
one line that the next `/sin-flow:review` command — `post`, `recheck` or another PR — belongs in a new session, and stop.

## Where it runs

Inside the product repo that owns the PR. `git rev-parse --show-toplevel` must succeed; if it does
not, say in one line which repo the review needs and stop. `KEY=$(sin-flow-profile key)`; no profile →
one line "no profile for this repo — running setup", run `sin-flow:setup`'s onboard in this session, then continue. Resolve `<strong>` and `<mid>` once: `sin-flow-profile model strong`, `sin-flow-profile model mid`.

User preferences are the plugin options, read with `sin-flow-profile user <key>`. `REVIEWS` = the `reviews_dir` option (default
`~/.claude/sin-flow/reviews`). The verdict tokens `reproduces` / `possible` / `invented` and the
review file headings are format: they stay English, in chat too.

## Review a PR

1. `gh pr view <PR> --json url,headRefOid -q '[.url, .headRefOid] | @tsv'`. `SHA8` = the first 8
   characters of the `--at` value, else of `headRefOid`.
2. `PKG=<scratchpad>/review/$KEY-<pr>-$SHA8`, where `<scratchpad>` is this session's scratchpad
   directory from your system prompt.
3. `"$REF/build-package.sh" pr <PR> "$PKG" [--at <sha>] [--base <sha>] [--depth quick|thorough]`.
   It prints only the package path. Non-zero → relay its stderr in one line and stop.
4. Follow `$REF/pipeline.md` with that `PKG`. Its render step writes `$REVIEWS/$KEY-<pr>-$SHA8.md`
   (call it `REVIEW`) and records `Package: <PKG>` as its last line.
5. **Settle before the verdict.** When the profile's `measure.doc` is not `none` and a K row is
   `possible` at `med`, take those rows' `settle` lines (the second command in `$REF/pipeline.md` § 6)
   and run each one yourself by `measure.doc`, its preflight first — a measurement is yours, never an
   agent's. Each row gets one number with its query and filter. When the number refutes the row (zero
   rows, a value that no writer sets), the row is `settled — <number, filter>` and does not count for
   the verdict. When the number confirms the row, the number stays beside it. When the preflight fails
   or `measure.doc` is `none`, relay as usual and add one line: the human step that the preflight names.
6. **Post without asking:** every K row that is `high` or `med` and `reproduces` goes through Post,
   below, in this invocation. Nothing else is posted. None qualifies → post nothing.
7. Chat, below.

## Chat — in the chat language, plain

Take the content out of `REVIEW` with shell and relay it in the chat language — translate, never
rewrite a finding in your own words:

```bash
sed -n '/^## What it does$/,/^## External input$/p' "$REVIEW" | sed '$d'
grep -E '^\| K[0-9]+ \| (high|med) \|' "$REVIEW"
grep -cE '^\| K[0-9]+ \| low \|' "$REVIEW"
grep -cE '^- R[0-9]+ \|' "$REVIEW"
grep '^lens .* failed' "$REVIEW"
```

- **VERDICT** — the first line: `approve` when no K row is high or med (rows that step 5 settled do
  not count) and verify said `blocking no`; else `don't approve — K<n>, …` (those rows). Advice; the
  user decides.
- **WHAT IT DOES** — the `## What it does` sentences.
- **ENTRY POINT** — the `## Entry points` rows.
- **FLOW** — the `## Flow` lines, then the three `## Read first` files.
- **FINDINGS** — the high and med rows as a table `# · severity · reality · file:line · claim`
  (`no high/med` when there are none); a row that step 5 measured shows its number in `reality`; low
  as one line: `N more low — in the file`.
- **REJECTED** — `N — in the file` (invented, needless validation, duplicates, pre-existing, nit without a rule).
- A failed lens, if any, in one line.
- The `REVIEW` path, absolute, on its own line.
- The last line, always: `posted: K<n>, … — <review url>`, or `not posted — no high/med reproduces`.

## Post

1. The numbers: Review step 6's selection, or the user's `/sin-flow:review post <n,…>` (`1,3` and `K1,K3`
   both mean K1 and K3), which posts exactly what the user numbered.
2. `REVIEW` = the review file this session rendered; if none, the newest `$REVIEWS/$KEY-*.md` — name
   it in the relay. From its `REPO=… PR=… SHA=…` line take `REPO`, `PR`, `SHA`; from its last line
   take `PKG`. `PR=-` is an exec-mode review: nothing to post, say so and stop.
3. `gh pr view "$PR" --repo "$REPO" --json headRefOid -q .headRefOid` differs from `SHA` → post
   nothing: the PR got new commits since the review, its line numbers may have moved; tell the user
   `<SHA8> → <head8>` and that `/sin-flow:review recheck <PR>` goes first. Stop.
4. Build `post.json` from the chosen rows (`WANT` = the numbers as `,1,3,`):

   ```bash
   mkdir -p "$PKG"
   awk -v want="$WANT" '/^### K[0-9]+ · / { k = substr($(2), 2); loc = $NF; next }
     /^comment_en: / && index(want, "," k ",") { p = loc; sub(/:[0-9]+$/, "", p); l = loc; sub(/^.*:/, "", l)
       printf "%s\t%s\t%s\n", p, l, substr($(0), 13) }' "$REVIEW" \
     | jq -R -s 'split("\n") | map(select(length > 0) | split("\t") | {path: .[0], line: (.[1] | tonumber), body: .[2]})' \
     > "$PKG/post.json"
   jq length "$PKG/post.json"
   ```

   The count must equal the numbers asked; a number with no row → name it and stop.
5. Dispatch `sin-flow:review-poster`: Agent tool, `subagent_type: "sin-flow:review-poster"`,
   `model: <mid>`, prompt `PR: https://github.com/<REPO>/pull/<PR>. post.json: <PKG>/post.json.` — nothing else.
6. Relay the review URL, the inline and body counts, and anything it skipped.

## Recheck

`/sin-flow:review recheck <PR>`, or "recheck", "they pushed the fixes", "approved or not?". `SHA` = the newest
`$REVIEWS/$KEY-<pr>-*.md`; `K` = the rows posted from it.
1. `"$REF/build-package.sh" pr <PR> "$PKG" --base <SHA> --depth quick`, then `$REF/pipeline.md` — the
   commits since the review only.
2. Chat opens with one line: `approve` or `don't approve — K<n>, …`: each posted K row closed /
   open at the head, then the new high/med rows.
3. Every K row closed and no new high/med row → Approve, below, without asking. Anything else → no
   approve; the new high/med `reproduces` rows go through Post as in Review step 6.

## Approve

"approve", "approve it", "… but approve", or Recheck step 3. `REVIEW`, `REPO`, `PR`, `SHA` as in Post 2.
1. Head ≠ `SHA` → no approve; tell the user `<SHA8> → <head8>` and that `recheck` goes first. Stop.
2. Numbers named in the same line → Post them first.
3. `gh pr review "$PR" --repo "$REPO" --approve`, then
   `gh api "repos/$REPO/pulls/$PR/reviews" --jq 'map(select(.state=="APPROVED"))[-1].submitted_at'`.
   Say approved only with that time; empty → say it did not land.
