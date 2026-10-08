// Photographs web pages with headless Chrome, driven over the DevTools protocol (no packages needed).
//   node tool/capture_pages.mjs plan.json
// plan.json: {"out": "<folder>", "shots": [{"name", "url", "width"?, "height"?, "scale"?, "mobile"?,
//              "scrollTo"?: "<css selectors, first match wins>", "offset"?: px above it, "clickText"?: "<button text>",
//              "clock"?: "HH:MM" (the page's time today),
//              "action"?: "board" | "calendar" | "stay"}]}
// Chrome runs with its own temporary profile: your own Chrome and its data are not used.
import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const plan = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const chromePath = process.env.CHROME || ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', '/usr/bin/google-chrome', '/usr/bin/chromium'].find(existsSync);
if (!chromePath) throw new Error('Google Chrome not found (set CHROME=/path/to/chrome)');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const profile = mkdtempSync(join(tmpdir(), 'll-chrome-'));
const chrome = spawn(chromePath, ['--headless=new', '--remote-debugging-port=0', `--user-data-dir=${profile}`, '--hide-scrollbars', '--no-first-run',
  '--no-default-browser-check', '--disable-extensions', '--mute-audio', '--force-color-profile=srgb', '--lang=en-GB', 'about:blank'], { stdio: 'ignore' });
let port;
for (let i = 0; i < 100 && !port; i++) {
  await sleep(100);
  try { port = readFileSync(join(profile, 'DevToolsActivePort'), 'utf8').split('\n')[0]; } catch {}
}
if (!port) throw new Error('Chrome did not start');

const version = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json();
const ws = new WebSocket(version.webSocketDebuggerUrl);
await new Promise((r, e) => { ws.onopen = r; ws.onerror = e; });
let next = 0;
const waiting = new Map();
ws.onmessage = (m) => {
  const msg = JSON.parse(m.data);
  if (msg.id && waiting.has(msg.id)) {
    const { ok, fail } = waiting.get(msg.id);
    waiting.delete(msg.id);
    msg.error ? fail(new Error(msg.error.message)) : ok(msg.result);
  }
};
const send = (method, params = {}, sessionId) => new Promise((ok, fail) => {
  const id = ++next;
  waiting.set(id, { ok, fail });
  ws.send(JSON.stringify({ id, method, params, sessionId }));
});

async function shoot(s) {
  const width = s.width || 1440, height = s.height || 900, scale = s.scale || 1;
  const { targetId } = await send('Target.createTarget', { url: 'about:blank' });
  const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
  const run = (method, params) => send(method, params, sessionId);
  const js = async (expression) => (await run('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true })).result.value;
  await run('Page.enable');
  await run('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: scale, mobile: !!s.mobile });
  if (s.mobile) await run('Emulation.setUserAgentOverride', { userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1' });
  if (s.clock) {
    // The page's clock at this time today ("open now" on a website then doesn't depend on when the pictures are made).
    const [h, m] = s.clock.split(':').map(Number), at = new Date();
    at.setHours(h, m, 0, 0);
    await run('Page.addScriptToEvaluateOnNewDocument', { source: `(() => { const R = Date, shift = ${at.getTime()} - R.now();
      class D extends R { constructor(...a) { a.length ? super(...a) : super(R.now() + shift); } static now() { return R.now() + shift; } }
      window.Date = D; })();` });
  }
  await run('Page.navigate', { url: s.url });
  // Ready: loaded, nothing spinning, fonts and pictures in.
  const ready = `(async () => document.readyState === 'complete' && !document.querySelector('.spinner, .boot') && (await document.fonts.ready, true)
    && [...document.images].every((i) => i.complete))()`;
  const settle = async () => {
    for (let i = 0; i < 150; i++) {
      if (await js(ready).catch(() => false)) break;
      await sleep(100);
    }
    await sleep(700);
  };
  await settle();
  if (s.action === 'board' || s.action === 'calendar') {
    await js(`(() => { const b = document.querySelector('.seg button[data-m=${s.action}]'); if (b && !b.classList.contains('on')) b.click(); })()`);
    await settle();
  }
  const target = s.scrollTo || (s.action === 'stay' ? '.avail.stay' : null);
  if (target) {
    // (Straight there: the sites scroll smoothly, which a picture taken mid-way would catch.)
    await js(`(() => { const el = ${JSON.stringify(target.split(',').map((x) => x.trim()))}.map((q) => document.querySelector(q)).find(Boolean);
      if (!el) return; const sec = el.closest('section') || el;
      const bar = [...document.querySelectorAll('header, nav, .nav, .topbar')].find((b) => /sticky|fixed/.test(getComputedStyle(b).position));
      document.documentElement.style.scrollBehavior = 'auto';
      window.scrollTo(0, sec.getBoundingClientRect().top + window.scrollY - (bar ? bar.offsetHeight : 0) - ${s.offset ?? 8}); })()`);
    await settle();
  }
  if (s.clickText) {
    await js(`(() => { const b = [...document.querySelectorAll('button, a')].find((x) => x.textContent.trim() === ${JSON.stringify(s.clickText)}); if (b) b.click(); })()`);
    await settle();
  }
  const shot = await run('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
  writeFileSync(join(plan.out, `${s.name}.png`), Buffer.from(shot.data, 'base64'));
  await send('Target.closeTarget', { targetId });
  console.log(`saved ${s.name}.png`);
}

try {
  for (const s of plan.shots) await shoot(s);
} finally {
  ws.close();
  chrome.kill();
  await sleep(300);
  rmSync(profile, { recursive: true, force: true });
}
