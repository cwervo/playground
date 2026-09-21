// Render index.html to a sequential A5 PDF, report any page whose content
// overflows its 148 x 210 mm box, and optionally dump PNG proofs.
// usage: NODE_PATH=$(npm root -g) node render.js out/pages.pdf [proofs-dir]
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
(async () => {
  const [,, out, proofs] = process.argv;
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 800, height: 1200 }, deviceScaleFactor: 2 });
  await p.goto('file://' + path.resolve('index.html'), { waitUntil: 'networkidle' });
  await p.evaluate(() => document.fonts.ready);
  await p.emulateMedia({ media: 'print' });
  const overflow = await p.evaluate(() => {
    const bad = [];
    document.querySelectorAll('.page').forEach((el, i) => {
      const box = el.getBoundingClientRect();
      let maxBottom = 0;
      el.querySelectorAll('*').forEach(c => {
        // ignore absolutely positioned furniture (footers, cover overlays) and its children
        if (c.closest('[data-abs]') || (() => { for (let a = c; a && a !== el; a = a.parentElement) { if (getComputedStyle(a).position === 'absolute') return true; } return false; })()) return;
        const r = c.getBoundingClientRect();
        if (r.height > 0) maxBottom = Math.max(maxBottom, r.bottom);
      });
      const padBottom = parseFloat(getComputedStyle(el).paddingBottom);
      const limit = box.bottom - padBottom;
      if (maxBottom > limit + 0.5) bad.push({ page: i + 1, overBy_px: Math.round(maxBottom - limit) });
    });
    return bad;
  });
  console.log('pages:', await p.locator('.page').count());
  console.log('overflow:', JSON.stringify(overflow));
  await p.pdf({ path: out, width: '148mm', height: '210mm', printBackground: true, preferCSSPageSize: true, margin: { top: 0, right: 0, bottom: 0, left: 0 } });
  if (proofs) {
    fs.mkdirSync(proofs, { recursive: true });
    await p.emulateMedia({ media: 'screen' });
    const pages = p.locator('.page');
    const n = await pages.count();
    for (let i = 0; i < n; i++) await pages.nth(i).screenshot({ path: path.join(proofs, `p${String(i + 1).padStart(2, '0')}.png`) });
  }
  await b.close();
})();
