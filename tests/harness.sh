#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$root/skills/exec/reference/playwright"
template="$root/skills/plan/reference/harness-template.mjs"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cases=0

fail() { echo "FAIL: $*" >&2; exit 1; }

expect_has() {
  cases=$((cases + 1))
  case "$3" in *"$2"*) ;; *) fail "$1: want substring [$2], got [$3]" ;; esac
}

expect_not() {
  cases=$((cases + 1))
  case "$3" in *"$2"*) fail "$1: did not want [$2], got [$3]" ;; esac
}

command -v node >/dev/null || fail "node is not installed"
cp "$src/harness.js" "$src/signin.js" "$scratch/"
mkdir -p "$scratch/node_modules/playwright"
cat > "$scratch/node_modules/playwright/index.js" <<'JS'
const fs = require('fs');
const note = (line) => fs.appendFileSync(process.env.STUB_LOG, line + '\n');
let flaked = false;
let signinFlakes = Number(process.env.STUB_SIGNIN_FLAKE || 0);
const newContext = async (options = {}) => {
  note(`context as=${'as' in options} state=${Boolean(options.storageState)}`);
  let url = 'about:blank';
  let closed = false;
  const handlers = {};
  const emit = (event, value) => (handlers[event] || []).forEach((handler) => handler(value));
  const page = {
    on: (event, handler) => { (handlers[event] = handlers[event] || []).push(handler); },
    goto: async (target) => {
      note(`goto ${target}`);
      if (target.endsWith('/sign-in') && signinFlakes > 0) { signinFlakes -= 1; throw new Error('net::ERR_TIMED_OUT'); }
      if (target.includes('/flaky') && !flaked) { flaked = true; throw new Error('net::ERR_TIMED_OUT'); }
      if (target.includes('/dead')) throw new Error('net::ERR_CONNECTION_REFUSED');
      url = target.includes('/away') ? 'https://app.test/sign-in' : target.includes('/offsite') ? 'https://other.test/offsite' : target.includes('/slash') ? target + '/' : target;
      if (process.env.STUB_CONSOLE) emit('console', { type: () => 'error', text: () => process.env.STUB_CONSOLE, location: () => ({ url: 'https://cdn.test/x.jpg' }) });
      if (process.env.STUB_PAGEERROR) emit('pageerror', new Error(process.env.STUB_PAGEERROR));
      return { status: () => Number(process.env.STUB_STATUS || 200) };
    },
    getByLabel: (label) => ({
      fill: async () => note(`fill ${label}`),
      press: async () => { if (!process.env.STUB_SIGNIN_STAY) url = 'https://app.test/home'; },
    }),
    waitForFunction: async (expr) => note(`ready ${expr}`),
    waitForURL: async (done) => { if (!done(new URL(url))) throw new Error('still on sign-in'); },
    waitForLoadState: async () => {},
    url: () => url,
    locator: () => ({ innerText: async () => process.env.STUB_BODY || 'fine' }),
    screenshot: async () => {},
    evaluate: async (fn) => (String(fn).includes('getClientRects') ? { small: 0, tail: 0, vh: 800, locked: false } : true),
    context: () => context,
  };
  const context = {
    addInitScript: async () => note('init script'),
    newPage: async () => page,
    storageState: async () => {
      if (closed) throw new Error('context is closed');
      note('state read');
      return { cookies: [{ name: 'session' }] };
    },
    close: async () => { closed = true; },
  };
  return context;
};
const engine = { launch: async () => ({ newContext, close: async () => {} }) };
module.exports = { chromium: engine, webkit: engine, devices: { 'iPhone 13': {} } };
JS

check() {
  local script="$1"
  shift
  : > "$scratch/stub.log"
  printf '%s\n' "const { run, sweep } = require('./harness.js');" "$script" > "$scratch/check.js"
  (cd "$scratch" && env STUB_LOG="$scratch/stub.log" FLOW_UI_SERVER=https://app.test FLOW_UI_SHOTS="$scratch/shots" \
    FLOW_UI_SIGNIN=https://app.test/sign-in FLOW_UI_ROLES='{"pro":["PRO_EMAIL","PRO_PASSWORD"]}' \
    PRO_EMAIL=pro@test PRO_PASSWORD=secret "$@" node check.js 2>&1; echo "exit=$?")
}

out=$(check "run('none', async (t) => { await t.newPage(); });")
expect_has "zero checks fail" "chromium FAIL no checks" "$out"
expect_has "zero checks fail on webkit" "webkit FAIL no checks" "$out"
expect_has "zero checks exit 1" "exit=1" "$out"

out=$(check "run('one', async (t) => { t.check(true, 'fine'); });")
expect_not "one check passes" "no checks" "$out"
expect_has "one check passes without a crash" "PASS fine" "$out"
expect_has "one check exit 0" "exit=0" "$out"

out=$(check "run('console', async (t) => { const p = await t.newPage(); await p.goto('/a'); t.check(true, 'a'); });" STUB_CONSOLE='boom happened')
expect_has "console error fails" "FAIL /a: console.error boom happened @ https://cdn.test/x.jpg" "$out"

out=$(check "run('source', async (t) => { const p = await t.newPage(); await p.goto('/a'); t.check(true, 'a'); });" STUB_CONSOLE='boom happened' FLOW_UI_CONSOLE_ALLOW='@ https://cdn\.test/')
expect_not "allow entry can name the source" "FAIL" "$out"
expect_has "allow entry can name the source exit 0" "exit=0" "$out"

long="boom $(printf 'x%.0s' $(seq 1 400)) tail-marker"
out=$(check "run('long', async (t) => { const p = await t.newPage(); await p.goto('/a'); t.check(true, 'a'); });" STUB_CONSOLE="$long" FLOW_UI_CONSOLE_ALLOW='tail-marker')
expect_not "allow entry matches past the printed length" "FAIL" "$out"
expect_has "allow entry matches past the printed length exit 0" "exit=0" "$out"

out=$(check "run('allowed', async (t) => { const p = await t.newPage(); await p.goto('/a'); t.check(true, 'a'); });" STUB_CONSOLE='boom happened' FLOW_UI_CONSOLE_ALLOW='^console.error boom')
expect_not "allowed console error passes" "FAIL" "$out"
expect_has "allowed console error passes exit 0" "exit=0" "$out"

out=$(check "run('pageerror', async (t) => { const p = await t.newPage(); await p.goto('/a'); t.check(true, 'a'); });" STUB_PAGEERROR='undefined is not a function')
expect_has "page error fails" "FAIL /a: pageerror undefined is not a function" "$out"

out=$(check "run('roles', async (t) => { await t.newPage({ as: 'pro' }); await t.newPage({ as: 'pro' }); t.check(true, 'x'); });")
log=$(cat "$scratch/stub.log")
expect_has "role signs in" "goto https://app.test/sign-in" "$log"
cases=$((cases + 1))
[ "$(grep -c 'goto https://app.test/sign-in' "$scratch/stub.log")" = 2 ] || fail "one sign-in for each engine: $log"
expect_not "as is not a context option" "as=true" "$log"
expect_has "contexts are opened with as absent" "as=false" "$log"
expect_has "role page gets the session" "state=true" "$log"
cases=$((cases + 1))
[ "$(grep -c 'state read' "$scratch/stub.log")" = 4 ] || fail "each role page reads a fresh session: $log"
expect_not "the sign-in context stays open for the reads" "context is closed" "$out"

mkdir -p "$scratch/home"
printf 'PRO_EMAIL=pro@test\nPRO_PASSWORD=secret\n' > "$scratch/home/creds.env"
out=$(cd "$scratch" && env STUB_LOG="$scratch/stub.log" HOME="$scratch/home" FLOW_ENV_FILE='~/creds.env' FLOW_UI_SERVER=https://app.test \
  FLOW_UI_SHOTS="$scratch/shots" FLOW_UI_SIGNIN=https://app.test/sign-in FLOW_UI_ROLES='{"pro":["PRO_EMAIL","PRO_PASSWORD"]}' \
  node -e "require('./harness.js').run('envfile', async (t) => { await t.newPage({ as: 'pro' }); t.check(true, 'x'); });" 2>&1; echo "exit=$?")
expect_has "env file with ~ loads" "exit=0" "$out"
expect_not "env file gives the credentials" "not set" "$out"

out=$(check "run('unknown', async (t) => { await t.newPage({ as: 'ghost' }); });")
expect_has "unknown role fails" "role ghost is not in FLOW_UI_ROLES" "$out"

out=$(check "run('signin-console', async (t) => { await t.newPage({ as: 'pro' }); t.check(true, 'x'); });" STUB_CONSOLE='signin boom')
expect_has "sign-in page console error fails" "FAIL /sign-in: console.error signin boom" "$out"

out=$(check "run('signin-pageerror', async (t) => { await t.newPage({ as: 'pro' }); t.check(true, 'x'); });" STUB_PAGEERROR='signin crash')
expect_has "sign-in page error fails" "FAIL /sign-in: pageerror signin crash" "$out"

out=$(check "run('signin-init', async (t) => { await t.newPage({ as: 'pro' }); t.check(true, 'x'); });")
cases=$((cases + 1))
[ "$(grep -E 'init script|goto https://app.test/sign-in' "$scratch/stub.log" | head -n 1)" = "init script" ] || fail "the sign-in context gets the media mute before its page opens: $(cat "$scratch/stub.log")"

out=$(check "run('ready', async (t) => { await t.newPage({ as: 'pro' }); t.check(true, 'x'); });")
expect_has "sign-in waits for the default ready expression" "ready true" "$(cat "$scratch/stub.log")"

out=$(check "run('ready', async (t) => { await t.newPage({ as: 'pro' }); t.check(true, 'x'); });" FLOW_UI_SIGNIN_READY='window.app?.ready')
expect_has "sign-in waits for the ready expression of the profile" "ready window.app?.ready" "$(cat "$scratch/stub.log")"

out=$(check "sweep('sweep');" FLOW_UI_SWEEP='["/a pro", "/away pro", "/b -"]' FLOW_UI_ERROR_TEXT='went wrong' STUB_BODY='Something went wrong')
expect_has "sweep opens" "chromium PASS /a as pro: opens" "$out"
expect_has "sweep catches a redirect" "chromium FAIL /away as pro: stays on its path" "$out"
expect_has "sweep catches an error screen" "chromium FAIL /b as -: no error screen" "$out"
expect_has "sweep exit 1" "exit=1" "$out"

out=$(check "sweep('sweep');" FLOW_UI_SWEEP='["/flaky pro"]')
expect_has "sweep retries one network error" "chromium PASS /flaky as pro: opens" "$out"

out=$(check "sweep('sweep');" FLOW_UI_SWEEP='["/a pro"]' STUB_STATUS=500)
expect_has "sweep catches a 5xx" "chromium FAIL /a as pro: opens — HTTP 500" "$out"

out=$(check "sweep('sweep');" FLOW_UI_SWEEP='["/dead pro"]')
expect_has "sweep fails after a second goto error" "chromium FAIL /dead as pro: opens — net::ERR_CONNECTION_REFUSED" "$out"
cases=$((cases + 1))
[ "$(grep -c 'goto https://app.test/dead' "$scratch/stub.log")" = 4 ] || fail "each engine tries a dead page twice: $(cat "$scratch/stub.log")"
expect_has "sweep with a goto error exit 1" "exit=1" "$out"

out=$(check "sweep('sweep');" FLOW_UI_SWEEP='["/a pro"]' STUB_SIGNIN_STAY=1)
expect_has "sweep sign-in error fails" "chromium FAIL /a as pro: signs in — still on sign-in" "$out"
expect_has "sweep sign-in error exit 1" "exit=1" "$out"

out=$(check "sweep('sweep');" FLOW_UI_SWEEP='["/a pro"]' PRO_PASSWORD=)
expect_has "sweep names a variable that is not set" "chromium FAIL /a as pro: signs in — sign-in at https://app.test/sign-in: the email or the password variable is not set" "$out"

out=$(check "sweep('sweep');" FLOW_UI_SWEEP='["/a pro"]' STUB_SIGNIN_FLAKE=1)
expect_has "sign-in retries one network error" "chromium PASS /a as pro: opens" "$out"

out=$(check "sweep('sweep');" FLOW_UI_SWEEP='["/a pro", "/b pro"]' STUB_SIGNIN_FLAKE=2)
expect_has "a sign-in that fails twice fails its item" "chromium FAIL /a as pro: signs in — net::ERR_TIMED_OUT" "$out"
expect_has "the next item of that role signs in again" "chromium PASS /b as pro: opens" "$out"

out=$(check "sweep('sweep');" FLOW_UI_SWEEP='["/offsite -"]')
expect_has "a redirect to another origin is not the same path" "chromium FAIL /offsite as -: stays on its path — https://other.test/offsite" "$out"

out=$(check "run('dedupe', async (t) => { const p = await t.newPage(); await p.goto('/a'); await p.goto('/a'); t.check(true, 'a'); });" STUB_CONSOLE='boom happened')
cases=$((cases + 1))
[ "$(printf '%s\n' "$out" | grep -c 'chromium FAIL /a: console.error boom happened')" = 1 ] || fail "a repeated console error prints one line: $out"

out=$(check "run('phone', async (t) => { const p = await t.newPage(); await p.goto('/a'); await t.phone(p, 'p'); });")
expect_has "phone results count as checks" "chromium PASS p: no empty tail below the content" "$out"
expect_not "phone only script is not zero checks" "no checks" "$out"
expect_has "phone only script exit 0" "exit=0" "$out"

out=$(check "sweep('sweep');" FLOW_UI_SWEEP='["/slash -"]')
expect_has "trailing slash is the same path" "chromium PASS /slash as -: stays on its path" "$out"
expect_has "trailing slash sweep exit 0" "exit=0" "$out"

out=$(cd "$scratch" && env STUB_LOG="$scratch/stub.log" HOME="$scratch/home" FLOW_UI_SERVER=https://app.test FLOW_UI_SHOTS="$scratch/shots" \
  FLOW_UI_SIGNIN=https://app.test/sign-in FLOW_UI_ROLES='{"pro":["PRO_EMAIL","PRO_PASSWORD"]}' PRO_EMAIL=pro@test PRO_PASSWORD=secret \
  FLOW_UI_SWEEP='["/a pro"]' node harness.js sweep x 2>&1; echo "exit=$?")
expect_has "the sweep command prints a result" "RESULT chromium pass=" "$out"
expect_has "the sweep command takes its label from the argument" "SHOTS $scratch/shots/x" "$out"
expect_has "the sweep command exit 0" "exit=0" "$out"

cp "$template" "$scratch/verify.mjs"
: > "$scratch/stub.log"
printf 'FLOW_PASSWORD=secret\n' > "$scratch/home/probe.env"
out=$(cd "$scratch" && env STUB_LOG="$scratch/stub.log" HOME="$scratch/home" FLOW_ENV_FILE='~/probe.env' FLOW_HARNESS_DIR="$scratch" FLOW_BASE_URL=https://app.test FLOW_EMAIL=pro@test \
  FLOW_STATE_DIR="$scratch/sessions" FLOW_READY_EXPR='probe-ready' node verify.mjs login 2>&1; echo "exit=$?")
expect_has "the probe login signs in" "signed in as pro@test" "$out"
expect_not "the probe login does not throw" "threw" "$out"
expect_has "the probe login opens the sign-in page" "goto https://app.test/sign-in" "$(cat "$scratch/stub.log")"
expect_has "the probe login passes the ready expression" "ready probe-ready" "$(cat "$scratch/stub.log")"
cases=$((cases + 1))
[ -s "$scratch/sessions/pro-test.json" ] || fail "the probe login did not write the session file: $out"

cases=$((cases + 1))
grep -q "signin.js" "$template" || fail "the probe template does not use the shared sign-in"
cases=$((cases + 1))
! grep -q "getByLabel" "$template" || fail "the probe template keeps its own sign-in"

cases=$((cases + 1))
! grep -q "@playwright/test" "$template" || fail "the probe template keeps the @playwright/test import"
cases=$((cases + 1))
grep -q 'createRequire(join(env("FLOW_HARNESS_DIR"), "harness.js"))' "$template" || fail "the probe template does not load through FLOW_HARNESS_DIR"
cases=$((cases + 1))
grep -q 'writeFileSync(STATE_FILE, JSON.stringify(await context.storageState()' "$template" || fail "login does not write the storageState"
cases=$((cases + 1))
grep -q "STATE_FILE" "$template" || fail "the probe template has no STATE_FILE"
cases=$((cases + 1))
grep -q "LAUNCH" "$template" || fail "the probe template lost LAUNCH"
cases=$((cases + 1))
grep -q "mutating" "$template" || fail "the probe template lost its probes"

echo "harness: $cases cases passed"
