const pw = require('playwright');
const fs = require('fs');
const os = require('os');
const path = require('path');

const SERVER = process.env.FLOW_UI_SERVER;
if (!SERVER) throw new Error('FLOW_UI_SERVER is not set: pass the profile ui.server');
const HOSTS = { chromium: process.env.FLOW_UI_SERVER_CHROMIUM || SERVER, webkit: SERVER };
const DEVICE = process.env.FLOW_UI_DEVICE || 'iPhone 13';
const LOCALE = process.env.FLOW_UI_LOCALE || 'en-US';

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
    const record = (status, name, detail = '') => {
      results.push(status);
      console.log(`${engine} ${status} ${name}${detail ? ' — ' + detail : ''}`);
    };
    const newPage = async (options = {}) => {
      const context = await browser.newContext({ ...pw.devices[DEVICE], locale: LOCALE, ...options });
      await context.addInitScript(silenceMedia);
      const page = await context.newPage();
      const goto = page.goto.bind(page);
      page.goto = (url, opts) => goto(url.startsWith('/') ? base + url : url, { waitUntil: 'domcontentloaded', ...opts });
      return page;
    };
    const t = {
      engine,
      base,
      newPage,
      check: (ok, name, detail) => record(ok ? 'PASS' : 'FAIL', name, detail),
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
        record(r.small ? 'FAIL' : 'PASS', `${name}: inputs ≥ 16px, no focus zoom on iPhone`, `${r.small} below 16px`);
        record(r.tail > r.vh / 5 ? 'FAIL' : 'PASS', `${name}: no empty tail below the content`, `${Math.round(r.tail)}px`);
        if (sheetOpen) record(r.locked ? 'PASS' : 'FAIL', `${name}: the page behind the open sheet does not scroll`, r.locked ? '' : 'html and body still scroll');
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
    await browser.close();
    const count = (status) => results.filter((r) => r === status).length;
    failed += count('FAIL');
    console.log(`RESULT ${engine} pass=${count('PASS')} fail=${count('FAIL')} skip=${count('SKIP')}`);
  }
  console.log(`SHOTS ${dir}`);
  process.exitCode = failed ? 1 : 0;
}

module.exports = { run, HOSTS };
