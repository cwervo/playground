import pw from '/opt/node22/lib/node_modules/playwright/index.js';
import { readFileSync } from 'fs';
const { chromium } = pw;

const body = readFileSync(new URL('./fiducial-playground.html', import.meta.url), 'utf8');
const html = `<!doctype html><html><head><meta charset="utf-8"></head><body>${body}</body></html>`;

const browser = await chromium.launch();
const page = await browser.newPage();
page.on('console', m => { if (m.type() === 'error') console.error('PAGE ERR:', m.text()); });
page.on('pageerror', e => console.error('PAGEERROR:', e.message));
page.on('dialog', d => d.dismiss());

await page.setContent(html, { waitUntil: 'load' });
// wait for template enrollment (images loaded)
await page.waitForFunction(() => window.__selfTest && document.querySelectorAll('#photoThumbs button').length === 5, { timeout: 8000 });
await page.waitForTimeout(400);

const r = await page.evaluate(() => window.__selfTest());
console.log('photo (clean):', JSON.stringify(r.photo));
console.log('photo (camera sim):', r.photoAug.ok + '/' + r.photoAug.n, 'correct');
console.log('barcode 0..31 all match:', r.barcode.every((v, i) => v === i));
console.log('tag samples:', JSON.stringify(r.tag));
console.log('color 0..63 all match:', r.color.every((v, i) => v === i));
console.log('fails:', r.fails.length ? r.fails : 'none');
console.log('OVERALL:', r.pass ? 'PASS ✅' : 'FAIL ❌');
await browser.close();
process.exit(r.pass ? 0 : 1);
