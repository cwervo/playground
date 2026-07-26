// Downscale + re-encode the 5 test JPEGs to small base64 for embedding.
import pw from '/opt/node22/lib/node_modules/playwright/index.js';
const { chromium } = pw;
import { readFileSync, writeFileSync } from 'fs';

const DIR = '/root/.claude/uploads/c3e02f01-5545-50e2-a445-b857123b3d63/';
const FILES = [
  ['1', 'd47d1026-FullSizeRender.jpeg'],
  ['2', '5f39f451-FullSizeRender.jpeg'],
  ['3', 'b7d46651-FullSizeRender.jpeg'],
  ['4', '486fb44a-FullSizeRender.jpeg'],
  ['5', '233a9676-FullSizeRender.jpeg'],
];
const MAX = 360; // longest edge px

const browser = await chromium.launch();
const page = await browser.newPage();
const out = {};
for (const [label, fn] of FILES) {
  const b64 = readFileSync(DIR + fn).toString('base64');
  const small = await page.evaluate(async ({ b64, MAX }) => {
    const img = new Image();
    await new Promise((res, rej) => { img.onload = res; img.onerror = rej; img.src = 'data:image/jpeg;base64,' + b64; });
    let { width: w, height: h } = img;
    const s = Math.min(1, MAX / Math.max(w, h));
    w = Math.round(w * s); h = Math.round(h * s);
    const c = document.createElement('canvas'); c.width = w; c.height = h;
    const ctx = c.getContext('2d');
    ctx.drawImage(img, 0, 0, w, h);
    return c.toDataURL('image/jpeg', 0.72);
  }, { b64, MAX });
  out[label] = small;
  console.error(`${label}: ${fn} -> ${(small.length/1024).toFixed(1)} KB dataURL`);
}
await browser.close();
writeFileSync('/home/user/playground/fiducial/tools/thumbs.json', JSON.stringify(out));
console.error('wrote thumbs.json');
