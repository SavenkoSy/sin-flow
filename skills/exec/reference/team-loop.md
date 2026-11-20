# Team: the post-PR loop

Read by `skills/exec/SKILL.md` § After the PR, when the repo is a team repo.

The PR is ready until a point reproduces. The goal of this phase is an approved PR, and the team merges it, not the user.
After each push, run step 1 again before you write to the user. Act on every new point without a question. Write to
the user only when you wait for a person outside this session.

1. **State.** `gh pr view <url> --json state,reviewDecision,reviews,comments,mergeStateStatus,mergeCommit > <workspace>/pr.json`,
   grep it. `state` is `MERGED` → ledger `Plan <id>: merged <mergeCommit.oid>`, `status: merged` in the plan header, then
   § After the merge of `reference/visual-check.md` (one `sin-flow:implementer`, grid role `visual`: the route sweep and
   the merge check), once, and the loop ends; a `WAKE merged` takes this same path. `DIRTY` → one rebase round onto the base. `BEHIND` alone is no reason to rebase: the team merges it as is, and GitHub asks for an update when a rule needs one. A rebase round — an `sin-flow:implementer` (grid role `rebase`)
   rebases and pushes with `--force-with-lease` (the shipper never rewrites history) — your branch, not a question.
   Size the check by `git range-diff <old base>..<old head> <new base>..HEAD`: only docs, deploy-notes numbering or
   generated API docs in it, and no new base commit touches a non-doc file of the branch → the range-diff plus the
   repo's doc checks, then push — no full gate, CI runs the suite. Any code or spec line, or a base commit in a
   non-doc file the branch touches → `sin-flow:shipper` `gate`.
2. **Bot review.** One call: does any of the repo's last 5 merged PRs carry a review-bot comment? None → ledger
   `bot: none (0 of 5 PR)`. Any → the bot's comments are a teammate's points: step 4.
3. **The user's review** → one fix round. The user's questions about code → a `sin-flow:read-only-analyst`. A
   question that reopens a product decision is not a task here: answer from the plan's `ingest-miss:` line and the rejected alternative
   beside it; reversing it is the user's call.
4. **A teammate's review.** Re-run step 1 first. Then run `sin-flow-unanswered <url>`: each line it prints is a point of
   this step (a thread whose last comment is not yours, or a PR comment after your last one), and its reply goes in that
   thread. Never find points by a time window. Per point, by its severity label (none → low, unless it names a wrong result that a user or a caller sees):
   - **low** → a reply, never a fix.
   - **medium** → reproduce it: a failing spec, a measured row, a read-only query by the profile's `## Measure`.
     Not reproduced → a reply, no fix.
   - **high** → the same re-verification; reproduced → step 6, not reproduced → a reply.
   - **A request for the plan, docs or evidence in the PR** → never a fix, never a docs commit; one reply, verbatim:
     «The plan and evidence are in #<issue> — everything is there.»

   A rare or unobserved case — a volume, a limit, a race, a row that may not exist — with zero rows is not
   reproduced. Every reply is short, in English, and argues the PR is ready: what was checked, the number or the
   reason, «not changing; ready to merge». Only reproduced points reach step 6; only a point that reopens a product
   decision goes to the user, all such points in one question. The user comes back after your final message → this step for everything posted since, then
   your answer.
5. **Base watcher** — every team PR, and any PR whose base is another feature branch. Before ending the turn, start
   one background Bash (`run_in_background`) in this checkout: `sin-flow-watch <url>`, or for a plan with `after:`
   `sin-flow-watch <url> <first repo> <first branch>` (the `repo` cell of the `after:` row in the spec; the first PR as
   in `sin-flow:plan` Step 1). It checks every 10 min for up to 24 h and prints one `WAKE <reason>` line: base
   changed, `DIRTY`, new activity by anyone but the author and a deploy bot, new commits on a feature-branch
   base, the first PR merged, or this PR merged (`WAKE merged: <url>`). A failed or empty `gh` read is never a wake. Every wake → step 4 first, except `WAKE merged`, which runs step 1 only and ends the loop. A `WAKE activity` needs
   nothing more: start the watcher again. For a draft PR whose first PR merged, in the same repo: if `baseRefName` is still the first
   branch, run `gh pr edit <url> --base <profile base>`. Then run the rebase round of step 1 onto the profile base,
   and push. Then, in both repo cases: run `gh pr ready <url>` and write one line to the user. Other wakes stay as
   they are: the rebase round of step 1, the push, one line to the user. After a rebase wake, start the watcher
   again. A draft stays a draft for a person. The watcher exits with no `WAKE` line (a kill, the 24 h end) → step 1
   at once, then start it again.
6. **No fix is pushed unreviewed.** One batched round (grid role `fix`) for every reproduced point and the user's: fix each point
   where it was flagged and in every sibling of the same pattern on the branch (the flagged query → every sibling
   query; the flagged error list → every rescue of that client; a flagged test fixture (a recorded response, a factory, a snapshot) → every
   fixture on the branch against its spec's inputs) — points fixed in one place only came back three times. Then step 6 of `skills/exec/SKILL.md` § Final gate and final review on the fix commits, then `sin-flow:shipper` `commit` — commit and push (a new commit shows the reviewer only the change), then a reply in each thread with
   the fix SHA. When the profile sets `review.request`, run `sin-flow-rerequest <PR url>` after every reply batch, with a push or without one: it re-requests
   the profile's `review.request` and everyone who reviewed the PR, and skips an approved PR.
