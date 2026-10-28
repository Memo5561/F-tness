// Screenshots of the Flutter web build (real widget path: ticker, gestures,
// reduced-resolution offscreen rendering at dpr 2).
// Usage: (cd build/web && python3 -m http.server 8765 &) ; node tool/web_shots.js 8765 out
const { chromium } = require('playwright');
const port = process.argv[2] || 8765;
const out = process.argv[3] || 'out';
(async () => {
  const t0 = Date.now();
  const log = (s) => console.log(((Date.now() - t0) / 1000).toFixed(1) + 's ' + s);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 400, height: 640 }, deviceScaleFactor: 2 });
  page.on('pageerror', (e) => log('pageerror: ' + e.message));
  await page.goto(`http://127.0.0.1:${port}/?ex=cal_pistol_squat`, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(8000);
  await page.screenshot({ path: `${out}/web_dpr2_initial.png`, timeout: 60000 });
  log('initial shot');
  // horizontal drag on the 3D view -> yaw (+ a little pitch)
  await page.mouse.move(150, 300);
  await page.mouse.down();
  for (let i = 1; i <= 12; i++) await page.mouse.move(150 + i * 10, 300 + i * 2);
  await page.mouse.up();
  await page.waitForTimeout(3000);
  await page.screenshot({ path: `${out}/web_dpr2_dragged.png`, timeout: 60000 });
  log('dragged shot');
  // switch to light theme
  await page.mouse.click(380, 28);
  await page.waitForTimeout(3000);
  await page.screenshot({ path: `${out}/web_dpr2_light.png`, timeout: 60000 });
  log('light shot');
  // horizontal body: starts at the preferred yaw 35; a drag into the end-on
  // window (yaw ~95) snaps back out after release
  const p1 = await browser.newPage({ viewport: { width: 400, height: 640 }, deviceScaleFactor: 1 });
  p1.on('pageerror', (e) => log('pageerror: ' + e.message));
  await p1.goto(`http://127.0.0.1:${port}/?ex=cal_front_lever`, { waitUntil: 'domcontentloaded' });
  await p1.waitForTimeout(8000);
  await p1.screenshot({ path: `${out}/web_dpr1_lever_initial.png`, timeout: 60000 });
  await p1.mouse.move(100, 300);
  await p1.mouse.down();
  for (let i = 1; i <= 10; i++) await p1.mouse.move(100 + i * 10, 300);
  await p1.waitForTimeout(500);
  await p1.screenshot({ path: `${out}/web_dpr1_lever_during_drag.png`, timeout: 60000 });
  await p1.mouse.up();
  await p1.waitForTimeout(2000);
  await p1.screenshot({ path: `${out}/web_dpr1_lever_released.png`, timeout: 60000 });
  log('lever shots');
  await browser.close();
})();
