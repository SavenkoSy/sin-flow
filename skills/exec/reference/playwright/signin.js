async function signIn(browser, { url, email, password, ready = 'true', emailLabel = 'Email', passwordLabel = 'Password', context: options = {}, init, watch }) {
  if (!email || !password) throw new Error(`sign-in at ${url}: the email or the password variable is not set`);
  const context = await browser.newContext(options);
  try {
    if (init) await context.addInitScript(init);
    const page = await context.newPage();
    if (watch) watch(page);
    const open = () => page.goto(url, { waitUntil: 'domcontentloaded' });
    await open().catch(open);
    await page.getByLabel(emailLabel).fill(email);
    const field = page.getByLabel(passwordLabel, { exact: true });
    await field.fill(password);
    await field.press('Enter');
    await page.waitForFunction(ready, null, { timeout: 90_000 });
    const signInPath = new URL(url).pathname;
    await page.waitForURL((current) => !current.pathname.startsWith(signInPath), { timeout: 90_000 });
    return { context, landed: page.url() };
  } catch (error) {
    await context.close();
    throw error;
  }
}

module.exports = { signIn };
