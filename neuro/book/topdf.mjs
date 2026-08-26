// topdf.mjs — print the book to PDF at 300 x 380 mm.
//
//   node book/topdf.mjs build/book/one-afternoon.html build/book/one-afternoon.pdf
//
// Unlike the conference proceedings, this document has no layout JavaScript in
// it: every page is composed by hand, so there is nothing to wait for except
// the embedded fonts and the embedded images. Both are waited for anyway --
// printing before a base64 image has decoded gives a PDF with the captions and
// none of the plates, which is a failure that looks like a success.

import { pathToFileURL } from "node:url";
import { resolve } from "node:path";
import { existsSync } from "node:fs";

async function loadPlaywright() {
  const candidates = [
    process.env.PLAYWRIGHT_MODULE,
    "playwright",
    "/opt/node22/lib/node_modules/playwright/index.mjs",
    "/usr/lib/node_modules/playwright/index.mjs",
    "/usr/local/lib/node_modules/playwright/index.mjs",
  ].filter(Boolean);
  for (const c of candidates) {
    try {
      return await import(c.startsWith("/") && existsSync(c) ? pathToFileURL(c).href : c);
    } catch { /* next */ }
  }
  console.error("topdf: playwright not found. npm i -D playwright, or set PLAYWRIGHT_MODULE.");
  process.exit(2);
}
const { chromium } = await loadPlaywright();

const [inPath, outPath] = process.argv.slice(2);
if (!inPath || !outPath) {
  console.error("usage: node book/topdf.mjs <in.html> <out.pdf>");
  process.exit(1);
}

const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH || undefined,
  args: ["--no-sandbox"],
});
const page = await browser.newPage();

let failed = false;
page.on("pageerror", (e) => { failed = true; console.error("page error:", e.message); });
page.on("console", (m) => { if (m.type() === "error") console.error("console:", m.text()); });

await page.goto(pathToFileURL(resolve(inPath)).href, { waitUntil: "load" });
await page.evaluate(async () => {
  await document.fonts.ready;
  await Promise.all([...document.images].map((i) => i.decode().catch(() => {})));
});

const stat = await page.evaluate(() => ({
  pages: document.querySelectorAll(".page").length,
  images: document.images.length,
  broken: [...document.images].filter((i) => !i.naturalWidth).length,
  codes: document.querySelectorAll(".qr svg").length,
  // a page whose content is taller than the page box has overset text on it
  overset: [...document.querySelectorAll(".page")]
    .map((p, i) => [i + 1, p.scrollHeight - p.clientHeight])
    .filter(([, over]) => over > 2),
}));

if (stat.broken) {
  console.error(`topdf: ${stat.broken} images failed to decode`);
  failed = true;
}
if (stat.overset.length) {
  console.error("topdf: content overflows the page box on: " +
                stat.overset.map(([p, o]) => `p${p} (+${o}px)`).join(", "));
  failed = true;
}

await page.pdf({
  path: resolve(outPath),
  width: "300mm",
  height: "380mm",
  printBackground: true,
  preferCSSPageSize: true,
  margin: { top: 0, right: 0, bottom: 0, left: 0 },
});
await browser.close();

console.error(`topdf: wrote ${outPath}  ${stat.pages} pages, ${stat.images} plates, ` +
              `${stat.codes} QR codes`);
process.exit(failed ? 1 : 0);
