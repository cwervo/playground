// Search Zocdoc for NYC specialists who take Aetna and offer video visits.
//
// Usage:
//   node search.mjs                 # neurologists + pulmonologists
//   node search.mjs pulmonologists  # one specialty slug
//   HEADED=1 node search.mjs        # watch the browser
//
// Requires playwright (npm i playwright, or a global install on NODE_PATH).
// Output: results.json and results.md in this directory, plus a screenshot
// per specialty for debugging when selectors drift.

import { chromium } from 'playwright';
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));

// Zocdoc's slug for the Aetna carrier and the NYC location, taken from the
// URLs Zocdoc itself links to for "Neurologists in New York who take Aetna".
const AETNA = 'aetna-300m';
const NYC = 'new-york-46063pm';

const SPECIALTIES = process.argv.slice(2).length
  ? process.argv.slice(2)
  : ['neurologists', 'pulmonologists'];

const searchUrl = (specialty) =>
  `https://www.zocdoc.com/${specialty}/${NYC}/${AETNA}?visit_type=video&new_patient=true`;

async function acceptCookies(page) {
  const btn = page.getByRole('button', { name: /accept|agree|got it/i }).first();
  if (await btn.isVisible({ timeout: 3000 }).catch(() => false)) await btn.click();
}

// Zocdoc exposes a "Visit type" filter; make sure "Video visit" is selected in
// case the query param is ignored.
async function ensureVideoFilter(page) {
  const filter = page.getByRole('button', { name: /visit type|video visit/i }).first();
  if (!(await filter.isVisible({ timeout: 5000 }).catch(() => false))) return;
  await filter.click();
  const video = page.getByRole('radio', { name: /video/i }).or(page.getByLabel(/video visit/i)).first();
  if (await video.isVisible({ timeout: 3000 }).catch(() => false)) {
    if (!(await video.isChecked().catch(() => false))) await video.click();
  }
  await page.keyboard.press('Escape');
  await page.waitForLoadState('networkidle').catch(() => {});
}

async function scrapeCards(page) {
  // Provider cards carry a data-test attribute on current Zocdoc markup; fall
  // back to any article/list item that links to a /doctor/ profile.
  const cards = page.locator('[data-test="search-result-card"], [data-test*="provider-card"]');
  const fallback = page.locator('article, li').filter({ has: page.locator('a[href*="/doctor/"]') });
  const list = (await cards.count()) ? cards : fallback;
  const n = await list.count();
  const out = [];
  for (let i = 0; i < n; i++) {
    const card = list.nth(i);
    const text = (await card.innerText().catch(() => '')).replace(/\s+/g, ' ').trim();
    const link = await card.locator('a[href*="/doctor/"]').first().getAttribute('href').catch(() => null);
    const name = await card.locator('h2, h3, [data-test*="name"]').first().innerText().catch(() => '');
    out.push({
      name: name.trim(),
      profile: link ? new URL(link, 'https://www.zocdoc.com').href : null,
      video: /video visit/i.test(text),
      newPatients: /new patients/i.test(text),
      rating: (text.match(/(\d\.\d{1,2})\s*\(?\d*\)?/) || [])[1] ?? null,
      nextAvailable: (text.match(/(today|tomorrow|[A-Z][a-z]{2},? [A-Z][a-z]{2} \d{1,2})[^.]{0,30}/) || [])[0] ?? null,
      summary: text.slice(0, 300),
    });
  }
  return out;
}

async function run() {
  const browser = await chromium.launch({ headless: !process.env.HEADED });
  const context = await browser.newContext({
    locale: 'en-US',
    timezoneId: 'America/New_York',
    viewport: { width: 1280, height: 900 },
  });
  const page = await context.newPage();
  const results = {};

  for (const specialty of SPECIALTIES) {
    const url = searchUrl(specialty);
    console.log(`\n== ${specialty}: ${url}`);
    try {
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60_000 });
      await acceptCookies(page);
      await ensureVideoFilter(page);
      await page.waitForSelector('a[href*="/doctor/"]', { timeout: 30_000 }).catch(() => {});
      await page.screenshot({ path: join(here, `${specialty}.png`), fullPage: true });
      const cards = await scrapeCards(page);
      results[specialty] = { url, count: cards.length, providers: cards };
      console.log(`found ${cards.length} provider cards`);
      for (const c of cards) console.log(` - ${c.name || '(no name)'}${c.video ? ' [video]' : ''}${c.nextAvailable ? ' next: ' + c.nextAvailable : ''}`);
    } catch (err) {
      results[specialty] = { url, error: String(err.message || err) };
      console.error(`failed: ${err.message || err}`);
    }
  }

  await browser.close();
  writeFileSync(join(here, 'results.json'), JSON.stringify(results, null, 2));
  writeFileSync(join(here, 'results.md'), toMarkdown(results));
  console.log('\nwrote results.json and results.md');
}

function toMarkdown(results) {
  const lines = ['# Zocdoc: NYC specialists, Aetna, video visits', ''];
  for (const [specialty, r] of Object.entries(results)) {
    lines.push(`## ${specialty}`, '', `Source: ${r.url}`, '');
    if (r.error) { lines.push(`Error: ${r.error}`, ''); continue; }
    if (!r.providers.length) { lines.push('No provider cards found.', ''); continue; }
    lines.push('| Provider | Video | New patients | Rating | Next available | Profile |', '|---|---|---|---|---|---|');
    for (const p of r.providers) {
      lines.push(`| ${p.name || '?'} | ${p.video ? 'yes' : '?'} | ${p.newPatients ? 'yes' : '?'} | ${p.rating ?? ''} | ${p.nextAvailable ?? ''} | ${p.profile ?? ''} |`);
    }
    lines.push('');
  }
  return lines.join('\n');
}

run().catch((e) => { console.error(e); process.exit(1); });
