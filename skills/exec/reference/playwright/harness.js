const pw = require('playwright');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { signIn } = require('./signin.js');

if (process.env.FLOW_ENV_FILE) process.loadEnvFile(process.env.FLOW_ENV_FILE.replace(/^~(?=\/)/, os.homedir()));

const SERVER = process.env.FLOW_UI_SERVER;
if (!SERVER) throw new Error('FLOW_UI_SERVER is not set: pass the profile ui.server');
const HOSTS = { chromium: process.env.FLOW_UI_SERVER_CHROMIUM || SERVER, webkit: SERVER };
const DEVICE = process.env.FLOW_UI_DEVICE || 'iPhone 13';
const LOCALE = process.env.FLOW_UI_LOCALE || 'en-US';
const ROLES = JSON.parse(process.env.FLOW_UI_ROLES || '{}');
const CONSOLE_ALLOW = process.env.FLOW_UI_CONSOLE_ALLOW ? new RegExp(process.env.FLOW_UI_CONSOLE_ALLOW) : null;
const ERROR_SCREEN = process.env.FLOW_UI_ERROR_TEXT ? new RegExp(process.env.FLOW_UI_ERROR_TEXT) : null;

function silenceMedia() {
  const proto = HTMLMediaElement.prototype;
  const muted = Object.getOwnPropertyDescriptor(proto, 'muted');
  const volume = Object.getOwnPropertyDescriptor(proto, 'volume');
  const silence = (el) => { muted.set.call(el, true); volume.set.call(el, 0); };
  Object.defineProperty(proto, 'muted', { configurable: true, get() { return muted.get.call(this); }, set() { muted.set.call(this, true); } });
  Object.defineProperty(proto, 'volume', { configurable: true, get() { return volume.get.call(this); }, set() { volume.set.call(this, 0); } });
  const play = proto.play;
  proto.play = function () { silence(this); return play.call(this); };
  document.addEventListener('play', (event) => silence(event.target), true);
}

function reviewDir(label) {
  const dir = path.join(process.env.FLOW_UI_SHOTS || path.join(os.homedir(), '.claude', 'sin-flow', 'work', 'screens'), label);
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

async function run(label, checks, engines = Object.keys(HOSTS)) {
  const dir = reviewDir(label);
  let failed = 0;
  for (const engine of engines) {
    const base = HOSTS[engine];
    const browser = await pw[engine].launch(engine === 'chromium' ? { args: ['--mute-audio'] } : {});
    const results = [];
    let made = 0;
    const record = (status, name, detail = '') => {
      results.push(status);
      console.log(`${engine} ${status} ${name}${detail ? ' — ' + detail : ''}`);
    };
    const verify = (ok, name, detail) => {
      made += 1;
      record(ok ? 'PASS' : 'FAIL', name, detail);
    };
    const device = { ...pw.devices[DEVICE], locale: LOCALE };
    const sessions = new Map();
    const reported = new Set();
    const pageFault = (page, text) => {
      const full = text.split('\n')[0];
      const line = full.slice(0, 300);
      const where = new URL(page.url()).pathname;
      if (CONSOLE_ALLOW?.test(full) || reported.has(where + line)) return;
      reported.add(where + line);
      record('FAIL', `${where}: ${line}`);
    };
    const watch = (page) => {
      page.on('console', (message) => {
        if (message.type() !== 'error') return;
        const source = message.location().url;
        pageFault(page, `console.error ${message.text().split('\n')[0]}${source ? ` @ ${source}` : ''}`);
      });
      page.on('pageerror', (error) => pageFault(page, `pageerror ${error.message}`));
    };
    const session = (role) => {
      if (!sessions.has(role)) {
        const vars = ROLES[role];
        if (!vars) throw new Error(`role ${role} is not in FLOW_UI_ROLES`);
        const signing = signIn(browser, {
          url: process.env.FLOW_UI_SIGNIN,
          ready: process.env.FLOW_UI_SIGNIN_READY,
          emailLabel: process.env.FLOW_UI_EMAIL_LABEL,
          passwordLabel: process.env.FLOW_UI_PASSWORD_LABEL,
          email: process.env[vars[0]],
          password: process.env[vars[1]],
          context: device,
          init: silenceMedia,
          watch,
        }).then((signedIn) => signedIn.context);
        signing.catch(() => sessions.delete(role));
        sessions.set(role, signing);
      }
      return sessions.get(role).then((context) => context.storageState());
    };
    const newPage = async ({ as, ...options } = {}) => {
      const storageState = as ? await session(as) : undefined;
      const context = await browser.newContext({ ...device, ...(storageState ? { storageState } : {}), ...options });
      await context.addInitScript(silenceMedia);
      const page = await context.newPage();
      watch(page);
      const goto = page.goto.bind(page);
      page.goto = (url, opts) => goto(url.startsWith('/') ? base + url : url, { waitUntil: 'domcontentloaded', ...opts });
      return page;
    };
    const t = {
      engine,
      base,
      newPage,
      check: verify,
      skip: (name, why) => record('SKIP', name, why),
      shot: (page, name) => page.screenshot({ path: path.join(dir, `${engine}-${name}.png`) }),
      phone: async (page, name, sheetOpen = false) => {
        const r = await page.evaluate(() => {
          const shown = [...document.querySelectorAll('body *')].filter((e) => e.getClientRects().length);
          const small = shown.filter((e) => e.matches('input, textarea, select') && parseFloat(getComputedStyle(e).fontSize) < 16).length;
          const bottom = Math.max(...shown.map((e) => e.getBoundingClientRect().bottom)) + window.scrollY;
          const locked = [document.documentElement, document.body].some((e) => {
            const s = getComputedStyle(e);
            return ['hidden', 'clip'].includes(s.overflowY) || s.position === 'fixed';
          });
          return { small, tail: document.documentElement.scrollHeight - bottom, vh: window.innerHeight, locked };
        });
        verify(!r.small, `${name}: inputs ≥ 16px, no focus zoom on iPhone`, `${r.small} below 16px`);
        verify(r.tail <= r.vh / 5, `${name}: no empty tail below the content`, `${Math.round(r.tail)}px`);
        if (sheetOpen) verify(r.locked, `${name}: the page behind the open sheet does not scroll`, r.locked ? '' : 'html and body still scroll');
      },
      stayedInPlace: async (page, action) => {
        await page.evaluate(() => { window.__stayedInPlace = true; });
        await action();
        return page.evaluate(() => window.__stayedInPlace === true).catch(() => false);
      },
    };
    try {
      await checks(t);
    } catch (e) {
      record('FAIL', 'script error', e.message.split('\n')[0]);
    }
    if (!made) record('FAIL', 'no checks', 'the script made no t.check call');
    await browser.close();
    const count = (status) => results.filter((r) => r === status).length;
    failed += count('FAIL');
    console.log(`RESULT ${engine} pass=${count('PASS')} fail=${count('FAIL')} skip=${count('SKIP')}`);
  }
  console.log(`SHOTS ${dir}`);
  process.exitCode = failed ? 1 : 0;
}

const samePath = (a, b) => a.replace(/\/+$/, '') === b.replace(/\/+$/, '');

function sweep(label, routes = JSON.parse(process.env.FLOW_UI_SWEEP || '[]')) {
  return run(label, async (t) => {
    for (const item of routes) {
      const [route, role] = item.trim().split(/\s+/);
      const name = `${route} as ${role}`;
      const page = await t.newPage(role === '-' ? {} : { as: role }).catch((error) => error);
      if (page instanceof Error) {
        t.check(false, `${name}: signs in`, page.message.split('\n')[0]);
        continue;
      }
      const open = () => page.goto(route).catch((error) => error);
      let response = await open();
      if (response instanceof Error) response = await open();
      if (response instanceof Error) {
        t.check(false, `${name}: opens`, response.message.split('\n')[0]);
        await page.context().close();
        continue;
      }
      await page.waitForLoadState('networkidle', { timeout: 15_000 }).catch(() => {});
      t.check(Boolean(response) && response.status() < 400, `${name}: opens`, response ? `HTTP ${response.status()}` : 'no response');
      const landed = new URL(page.url());
      const wanted = new URL(t.base + route);
      t.check(landed.origin === wanted.origin && samePath(landed.pathname, wanted.pathname), `${name}: stays on its path`, landed.origin === wanted.origin ? landed.pathname : landed.origin + landed.pathname);
      if (ERROR_SCREEN) {
        const hit = (await page.locator('body').innerText()).match(ERROR_SCREEN);
        t.check(!hit, `${name}: no error screen`, hit ? hit[0] : '');
      }
      const slug = route.replace(/[^a-z0-9]+/gi, '-').replace(/^-|-$/g, '') || 'home';
      await t.shot(page, `${slug}-${role}`);
      await page.context().close();
    }
  });
}

if (require.main === module && process.argv[2] === 'sweep') sweep(process.argv[3] || 'sweep');

module.exports = { run, sweep, HOSTS };
