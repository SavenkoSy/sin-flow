import { chromium } from "@playwright/test";
import { existsSync, mkdirSync, writeFileSync } from "fs";
import { join } from "path";

const env = (name, fallback) => {
  const value = process.env[name] ?? fallback;
  if (value === undefined) throw new Error(`${name} is not set — the profile's measure doc names it`);
  return value;
};

if (process.env.FLOW_ENV_FILE) process.loadEnvFile(process.env.FLOW_ENV_FILE);

const BASE = env("FLOW_BASE_URL");
const API = env("FLOW_API_URL", BASE);
const SIGNIN_PATH = env("FLOW_SIGNIN_PATH", "/sign-in");
const EMAIL_LABEL = env("FLOW_EMAIL_LABEL", "Email");
const PASSWORD_LABEL = env("FLOW_PASSWORD_LABEL", "Password");
const READY_EXPR = env("FLOW_READY_EXPR", "true");
const TOKEN_EXPR = process.env.FLOW_TOKEN_EXPR || "";
const EMAIL = env("FLOW_EMAIL");
const PASSWORD_VAR = env("FLOW_PASSWORD_VAR", "FLOW_PASSWORD");
const STATE_DIR = env("FLOW_STATE_DIR", ".flow-sessions");
const BLOCK_HOSTS = process.env.FLOW_BLOCK_HOSTS ? new RegExp(process.env.FLOW_BLOCK_HOSTS) : null;
const STATE_FILE = join(STATE_DIR, `${EMAIL.replace(/[^a-z0-9]/gi, "-")}.json`);

const LAUNCH = {
  channel: "chrome",
  headless: process.env.HEADED !== "1",
  args: ["--disable-blink-features=AutomationControlled"],
};

async function login() {
  const password = process.env[PASSWORD_VAR];
  if (!password) throw new Error(`${PASSWORD_VAR} missing for ${EMAIL}`);
  const browser = await chromium.launch(LAUNCH);
  const page = await browser.newPage();
  await page.goto(`${BASE}${SIGNIN_PATH}`);
  await page.getByLabel(EMAIL_LABEL).fill(EMAIL);
  const passwordField = page.getByLabel(PASSWORD_LABEL, { exact: true });
  await passwordField.fill(password);
  await passwordField.press("Enter");
  await page.waitForFunction(READY_EXPR, null, { timeout: 90_000 });
  await page.waitForURL((url) => !url.pathname.startsWith(SIGNIN_PATH), { timeout: 90_000 });
  mkdirSync(STATE_DIR, { recursive: true });
  writeFileSync(STATE_FILE, JSON.stringify(await page.context().storageState(), null, 2));
  console.log(`signed in as ${EMAIL} → ${STATE_FILE}\nlanded on ${page.url()}`);
  await browser.close();
}

async function withPage(run, viewport = { width: 1280, height: 900 }) {
  if (!existsSync(STATE_FILE)) throw new Error(`no session for ${EMAIL} — run "login" first`);
  const browser = await chromium.launch(LAUNCH);
  const context = await browser.newContext({ storageState: STATE_FILE, viewport });
  if (BLOCK_HOSTS) await context.route(BLOCK_HOSTS, (route) => route.abort());
  const page = await context.newPage();
  const log = { console: [], failures: [], requests: [] };
  page.on("console", (message) => {
    if (message.type() === "error") log.console.push(message.text().slice(0, 160));
  });
  page.on("response", (response) => {
    const url = response.url();
    if (response.status() >= 400) log.failures.push(`${response.status()} ${response.request().method()} ${url.slice(0, 120)}`);
    log.requests.push({ url, status: response.status(), t: Date.now() });
  });
  try {
    await run(page, log);
  } finally {
    if (log.console.length) console.log(`  console errors: ${JSON.stringify(log.console.slice(0, 3))}`);
    if (log.failures.length) console.log(`  http failures: ${JSON.stringify(log.failures.slice(0, 6))}`);
    await browser.close();
  }
  return log;
}

const settle = (page, ms = 4000) => page.waitForTimeout(ms);

const call = async (page, path, init = {}) => {
  const token = TOKEN_EXPR ? await page.evaluate(TOKEN_EXPR) : null;
  return page.evaluate(
    async ([api, requestPath, options, token]) => {
      const response = await fetch(`${api}${requestPath}`, {
        credentials: "include",
        ...options,
        headers: {
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
          ...(options.body ? { "Content-Type": "application/json" } : {}),
          ...(options.headers ?? {}),
        },
      });
      const text = await response.text();
      let body;
      try {
        body = JSON.parse(text);
      } catch {
        body = text.slice(0, 400);
      }
      return { status: response.status, headers: Object.fromEntries(response.headers.entries()), body };
    },
    [API, path, init, token],
  );
};

async function probeDeploy() {
  console.log(`\n═══ deploy — behavioural markers ═══`);
  await withPage(async (page) => {
    await page.goto(BASE, { waitUntil: "domcontentloaded" });
    await settle(page);
    const marker = await call(page, "/marker/endpoint");
    console.log(`  marker → ${marker.status} ${JSON.stringify(marker.body).slice(0, 200)}  (before fix: <value>, after: <value>)`);
  });
}

async function probeExample() {
  console.log(`\n═══ <unit> — <defect> ═══`);
  await withPage(async (page) => {
    await page.goto(BASE, { waitUntil: "domcontentloaded" });
    await settle(page);
    for (let rep = 1; rep <= 5; rep++) {
      const result = await call(page, "/some/endpoint");
      console.log(`  rep ${rep}: ${result.status} ${JSON.stringify(result.body).slice(0, 300)}  x-some-header=${result.headers["x-some-header"]}`);
    }
  });
}

async function probeMutating() {
  console.log(`\n═══ <unit> — <mutating defect> ═══`);
  const watched = ["fieldA", "fieldB"];
  const pick = (body) => Object.fromEntries(watched.map((key) => [key, body?.[key] ?? null]));
  await withPage(async (page) => {
    await page.goto(BASE, { waitUntil: "domcontentloaded" });
    await settle(page);
    const path = "/some/settings";
    const read = async (label) => {
      const result = await call(page, path);
      console.log(`  ${label}: ${result.status} ${JSON.stringify(pick(result.body))}`);
      return result;
    };
    const write = async (label, body) => {
      const result = await call(page, path, { method: "PATCH", body: JSON.stringify(body) });
      console.log(`  PATCH ${JSON.stringify(body)} → ${result.status}\n    ${label}: ${JSON.stringify(pick(result.body))}`);
      return result.body;
    };
    const baseline = await read("baseline");
    const body = baseline.body;
    const missing = watched.filter((key) => typeof body !== "object" || body === null || !(key in body));
    if (baseline.status !== 200 || missing.length) {
      console.log(`  ABORT before any write: baseline ${baseline.status}, missing ${missing.join(", ") || "none"}`);
      return;
    }
    try {
      await write("after write 1", { fieldA: 77 });
      await read("final");
    } finally {
      await write("restored", pick(body));
    }
  });
}

async function probeNodeIdentity() {
  console.log(`\n═══ <unit> — node identity across a remount ═══`);
  const selector = '[data-testid="<input>"]';
  await withPage(async (page) => {
    await page.goto(BASE, { waitUntil: "domcontentloaded" });
    await page.locator(selector).waitFor({ timeout: 60_000 });
    await page.locator(selector).click();
    await page.evaluate((sel) => {
      const element = document.activeElement;
      element.dataset.probeTag = "A";
      window.__tagged = element;
      window.__events = [];
      const startedAt = performance.now();
      const stamp = (what) =>
        window.__events.push({
          t: Math.round(performance.now() - startedAt),
          what,
          taggedConnected: window.__tagged.isConnected,
          taggedValue: window.__tagged.value,
          taggedIsActive: document.activeElement === window.__tagged,
          liveCount: document.querySelectorAll(sel).length,
          liveValue: document.querySelector(sel)?.value,
          activeValue: document.activeElement?.value,
          activeCaret: document.activeElement?.selectionStart,
        });
      stamp("install");
      element.addEventListener("input", () => stamp("input"));
      new MutationObserver(() => stamp("mutation")).observe(document.body, { childList: true, subtree: true });
      window.__stamp = stamp;
    }, selector);
    await page.keyboard.type("example", { delay: 100 });
    await settle(page, 2000);
    await page.evaluate(() => window.__stamp("final"));
    const events = await page.evaluate(() => window.__events);
    events.forEach((event) =>
      console.log(
        `    ${String(event.t).padStart(5)}ms ${event.what.padEnd(9)} ` +
          `tagged{connected:${event.taggedConnected} active:${event.taggedIsActive} v:${JSON.stringify(event.taggedValue)}} ` +
          `live{n:${event.liveCount} v:${JSON.stringify(event.liveValue)}} ` +
          `active{v:${JSON.stringify(event.activeValue)} caret:${event.activeCaret}}`,
      ),
    );
    console.log(`  ⇒ taggedConnected:false while liveCount:1 = the node was REPLACED, not re-rendered`);
  });
}

const PROBES = {
  login,
  deploy: probeDeploy,
  example: probeExample,
  mutating: probeMutating,
  node: probeNodeIdentity,
};

const requested = process.argv.slice(2);
if (!requested.length) {
  console.log(`usage: node verify-<id>.mjs ${Object.keys(PROBES).join(" | ")}`);
  process.exit(1);
}
for (const name of requested) {
  const probe = PROBES[name];
  if (!probe) {
    console.log(`unknown probe: ${name}`);
    continue;
  }
  try {
    await probe();
  } catch (error) {
    console.log(`probe ${name} threw: ${error.message}`);
  }
}
process.exit(0);
