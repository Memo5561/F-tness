// Serves build/web and screenshots the demo app (CanvasKit) with Playwright.
// Usage: node tool/web_shot.js out/web_demo.png
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');
const root = path.join(__dirname, '..', 'build', 'web');
const types = { '.html': 'text/html', '.js': 'application/javascript', '.json': 'application/json',
  '.wasm': 'application/wasm', '.png': 'image/png', '.otf': 'font/otf', '.ttf': 'font/ttf', '.mjs': 'application/javascript' };
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0]);
  if (p === '/') p = '/index.html';
  const f = path.join(root, p);
  fs.readFile(f, (err, data) => {
    if (err) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': types[path.extname(f)] || 'application/octet-stream' });
    res.end(data);
  });
});
server.listen(8765, async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 420, height: 760 }, deviceScaleFactor: 2 });
  page.on('console', m => { if (m.type() === 'error') console.log('console:', m.text()); });
  await page.goto('http://localhost:8765/');
  await page.waitForTimeout(6000);
  await page.screenshot({ path: process.argv[2] || 'out/web_demo.png' });
  // drag to rotate
  await page.mouse.move(210, 350);
  await page.mouse.down();
  await page.mouse.move(318, 350, { steps: 12 }); // +108 px = +65 deg yaw (front lever 25 -> 90)
  await page.mouse.up();
  await page.waitForTimeout(900); // > 250 ms zoom ease after release
  await page.screenshot({ path: (process.argv[2] || 'out/web_demo.png').replace('.png', '_rot.png') });
  // fps estimate
  const fps = await page.evaluate(() => new Promise(r => { let n = 0; const t0 = performance.now();
    function f() { n++; if (performance.now() - t0 < 3000) requestAnimationFrame(f); else r(n / 3); } requestAnimationFrame(f); }));
  console.log('rAF fps (headless, software GL):', fps.toFixed(1));
  await browser.close();
  server.close();
});
