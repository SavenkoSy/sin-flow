# Visual check — when the profile sets `ui.visual_check: playwright`

Every change that renders something is checked in a real browser by an agent before it is handed over. The user
does not walk a UI checklist (2026-09-27: «I am not going to review that kind of thing»); the first pass found a defect no
spec could see — a load-more that reloaded the page under a rate-limit fuse. This file is the one source.

## When

- Any plan unit with `UI surface: yes`, or a hotfix whose diff touches a path in the profile's `ui.surface_paths`.
  Once per plan, after the final-review fixes are committed, before the PR.
- Nothing rendered changed → no check; one ledger line `Visual check: skipped — no UI surface`.

## What

The plan's `### UI checklist`, one check per item, each written as «URL → action → what must be there». The action
is what a user of the device does — tap, type into, paste then close the keyboard, scroll to the end, open a sheet,
edit a row that already exists — done in the page, not read off the DOM. With a phone device every changed surface
also gets `t.phone(page, '<name>')`, and once more with each sheet open as `t.phone(page, '<name>', true)` — that adds
the check that the page behind the sheet does not scroll (found by the user after two PRs). An item a browser
cannot see (a crawler's behaviour, a production-only header, a CDN rule) is a `SKIP` with its reason, never a silent
omission. Add the one or two places the implementer was least sure of even if the checklist missed them.

## How

- The server: start it as the profile's `## Run` says (or the repo README for a non-TTY shell). Never a second one
  while `lsof -nP -iTCP:<port> -sTCP:LISTEN` shows one. A change to app boot config needs a restart. Shut it down
  after the check — unless the user asked to look.
- The script: `<workspace>/playwright/check.js`, outside the repo, never committed. It only holds the checks:

  ```js
  const { run } = require(`<this file's folder>/playwright/harness.js`);

  run('<id>', async (t) => {
    const page = await t.newPage();
    await page.goto('/fresh');
    const chip = page.locator('[data-testid="genre-chip"]').first();
    t.check(await chip.getAttribute('rel') === 'nofollow', '/fresh chip has rel=nofollow');
    const stayed = await t.stayedInPlace(page, () => chip.click());
    t.check(stayed, 'chip tap is a client-side visit, not a reload');
    await t.shot(page, 'fresh-after-chip');
  });
  ```

  Run with the profile values in the environment:
  `FLOW_UI_SERVER=<ui.server> FLOW_UI_DEVICE=<ui.device> FLOW_UI_SHOTS=<ui.screenshots> node check.js`
  (`FLOW_UI_SERVER_CHROMIUM` when the profile's `## Run` names a separate host for Chromium; `FLOW_UI_LOCALE` when it
  names a locale). `ui.screenshots` absent → `~/Desktop/<key>-review`. `playwright` is installed next to the harness (no `node_modules/` in `reference/playwright/` → `npm ci` there first),
  the browsers in `~/Library/Caches/ms-playwright`; a launch that says a browser is missing → `npx playwright install
  chromium webkit` inside `reference/playwright/`.
- The harness runs every check on Chromium and WebKit, on the device viewport. Navigation waits for
  `domcontentloaded` — WebKit's `load` never fires on some pages.
- Real iOS Safari: for an item the plan marks `iOS simulator: yes` and for every copy, paste or on-screen-keyboard
  item — Playwright's WebKit skips exactly those (copy passed on Chromium with a mock, skipped on WebKit, dead on the
  phone). Drive the simulator through the `mobile` MCP tools when the profile's `## Run` names them; screenshots go to
  the same folder.
- Who: one `sin-flow:implementer` (`<mid>`, effort medium) writes and runs the script and returns
  `VISUAL: green | red`, the `RESULT` lines, one `FAIL:` line per failure and the `SHOTS` path. The orchestrator
  reads that block only.

## After

- Screenshots land in `<ui.screenshots>/<id>/` — the user looks and deletes them.
- A `FAIL` is a fix round like a review finding: one implementer with every failure, then the check again, then
  gate + commit. Before the PR, not after.
- Every `SKIP` with its reason reaches the user (final message, NOT AS IN THE TICKET, as «not checked»); the PR body
  does not carry it.

## Pitfalls met so far

- A stream-response link is not a full client-side visit: a non-stream error response reloads the whole page. Check
  stream links separately from navigation links.
- A throttle or fuse counts per minute slot: start its trip right after a minute boundary and finish the checks
  inside the same minute.
- Sound: the user hears every ▶ a check taps (2026-10-06: «I do not want to hear that»). The harness mutes it — Chromium
  launches with `--mute-audio`, and an init script forces every media element in every frame to muted / volume 0.
  Always open pages through `t.newPage()`; a script that launches its own browser or context bypasses the mute.
