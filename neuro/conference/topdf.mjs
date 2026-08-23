// topdf.mjs — print the proceedings HTML to PDF.
//
// The document paginates and draws its own ley lines in JavaScript after layout
// (see conference/build.tcl), so this waits for the page to set
// data-ready="1" before printing. Printing earlier gives a PDF with the right
// text and no lines on it, which is a failure that looks like a success.
//
//   node conference/topdf.mjs build/conference/proceedings.html build/conference/proceedings.pdf
//
// Needs Playwright's Chromium. Any browser that can print a page at an exact
// physical size will do; this one is used because the repo already has it.

import { pathToFileURL } from "node:url";
import { resolve } from "node:path";
import { existsSync } from "node:fs";

// ESM resolution ignores NODE_PATH, so a globally-installed Playwright has to
// be found by hand. Local install first, then the usual global locations, then
// whatever PLAYWRIGHT_MODULE points at.
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
    } catch { /* try the next one */ }
  }
  console.error("topdf: playwright not found. npm i -D playwright, or set PLAYWRIGHT_MODULE.");
  process.exit(2);
}
const { chromium } = await loadPlaywright();

const [inPath, outPath] = process.argv.slice(2);
if (!inPath || !outPath) {
  console.error("usage: node conference/topdf.mjs <in.html> <out.pdf>");
  process.exit(1);
}

const EXECUTABLE = process.env.CHROMIUM_PATH || undefined;

const browser = await chromium.launch({
  executablePath: EXECUTABLE,
  args: ["--no-sandbox"],
});
const page = await browser.newPage();

let failed = false;
page.on("pageerror", (e) => { failed = true; console.error("page error:", e.message); });
page.on("console", (m) => { if (m.type() === "error") console.error("console:", m.text()); });

await page.goto(pathToFileURL(resolve(inPath)).href, { waitUntil: "load" });
await page.waitForFunction(() => document.documentElement.dataset.ready === "1",
                           { timeout: 120000 });

const stat = await page.evaluate(() => ({
  pages:  document.querySelectorAll(".page").length,
  lines:  document.querySelectorAll("svg.ley path").length,
  stubs:  document.querySelectorAll(".stub").length,
  boxes:  document.querySelectorAll(".rbox").length,
  // only real links; the legend on page 2 carries a specimen highlight
  marks:  document.querySelectorAll("mark.hl[data-link]").length,
}));

// Every highlight must have produced a stub and a line. A silent mismatch here
// means a link id in the transcript has no entry in the link table, and the
// reader would get a highlight that points nowhere.
if (stat.marks !== stat.stubs) {
  console.error(`topdf: ${stat.marks} highlights but ${stat.stubs} stubs -- a link id is unresolved`);
  failed = true;
}

await page.pdf({
  path: resolve(outPath),
  width: "11in",
  height: "8.5in",
  printBackground: true,
  preferCSSPageSize: true,
  margin: { top: 0, right: 0, bottom: 0, left: 0 },
});
await browser.close();

console.error(`topdf: wrote ${outPath}  ${stat.pages} pages, ${stat.marks} highlights, ` +
              `${stat.stubs} stubs, ${stat.boxes} region boxes, ${stat.lines} ley lines`);
process.exit(failed ? 1 : 0);
