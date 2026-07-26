import pw from '/opt/node22/lib/node_modules/playwright/index.js';
import { readFileSync } from 'fs';
const { chromium } = pw;
const body = readFileSync(new URL('./desk-scanner.html', import.meta.url), 'utf8');
const html = `<!doctype html><html><head><meta charset="utf-8"></head><body>${body}</body></html>`;
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1100, height: 1400 }, deviceScaleFactor: 2 });
page.on('console', m => console.log('PAGE', m.type(), m.text()));
page.on('pageerror', e => console.error('PAGEERROR', e.message));
await page.setContent(html, { waitUntil: 'load' });
await page.waitForFunction(() => window.__scanTest && Object.values(imgs).every(i=>i.complete), { timeout: 8000 }).catch(()=>{});
await page.waitForTimeout(500);
const shot = process.argv[2];
if (shot === 'shot') {
  await page.evaluate(() => { document.querySelector('#scan').click(); });
  await page.waitForTimeout(300);
  await page.screenshot({ path: '/home/user/playground/fiducial/demo/desk-shot.png', fullPage: true });
  console.log('screenshot written');
}
const r = await page.evaluate(() => { window.__debug = true; return window.__scanTest(); });
console.log('RESULT', JSON.stringify(r, null, 1));
await browser.close();
