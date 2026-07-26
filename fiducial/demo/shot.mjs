import pw from '/opt/node22/lib/node_modules/playwright/index.js';
import { readFileSync } from 'fs';
const { chromium } = pw;
const body = readFileSync(new URL('./fiducial-playground.html', import.meta.url), 'utf8');
const html = `<!doctype html><html><head><meta charset="utf-8"></head><body>${body}</body></html>`;
const browser = await chromium.launch();
for (const theme of ['dark', 'light']) {
  const page = await browser.newPage({ viewport: { width: 1100, height: 1500 }, deviceScaleFactor: 2 });
  page.on('dialog', d => d.dismiss());
  await page.setContent(html, { waitUntil: 'load' });
  await page.waitForFunction(() => document.querySelectorAll('#photoThumbs button').length === 5);
  await page.evaluate(t => { window.__silent = true; document.documentElement.setAttribute('data-theme', t); }, theme);
  await page.waitForTimeout(500);
  for (const [mod, name] of [['photo','01photo'],['barcode','02barcode'],['tag','03tag'],['color','04color']]) {
    await page.evaluate(m => document.querySelector(`.tab[data-mod="${m}"]`).click(), mod);
    await page.evaluate(() => { const b=document.querySelector('.module.active .btn.primary'); b&&b.click(); });
    await page.waitForTimeout(300);
    await page.screenshot({ path: `/home/user/playground/fiducial/demo/shots/${theme}-${name}.png`, fullPage: true });
  }
  await page.close();
}
await browser.close();
console.log('screenshots done');
