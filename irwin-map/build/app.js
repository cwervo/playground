const REGION = __REGION__;
const DATA   = __SITES__;

const MODES = [
  {k:'foot',       label:'On foot',          dash:'1.5 5',    blurb:'Everything under two miles of Times Square.'},
  {k:'subway',     label:'MTA subway',       dash:'',         blurb:'One swipe, twenty minutes, four museums.'},
  {k:'metronorth', label:'MTA Metro-North',  dash:'10 6',     blurb:'Hudson Line out of Grand Central.'},
  {k:'lirr',       label:'LIRR',             dash:'4 4',      blurb:'Nothing. Not one Irwin on the whole network.'},
  {k:'amtrak',     label:'Amtrak',           dash:'18 6 2 6', blurb:'The Northeast Corridor, north and south.'},
  {k:'car',        label:'Car',              dash:'4 4',      blurb:'Up I-95 for the Boston pair.'},
  {k:'plane',      label:'Plane',            dash:'20 5 2 5 2 5',     blurb:'The far rim of the circle.'},
];
const MODE = Object.fromEntries(MODES.map(m => [m.k, m]));
const STATUS = {
  installed:  'Permanently sited',
  collection: 'In the collection',
  historic:   'Historic site — not extant',
  gallery:    'Gallery representation',
};

const POS = {
  beacon:    {bow: 0.00, dx: 14, dy:  4, a:'start', short:'Dia Beacon'},
  yale:      {bow: 0.12, dx: 14, dy: 16, a:'start', short:'Yale University Art Gallery'},
  wellesley: {bow:-0.13, dx:-14, dy: 18, a:'end',   short:'Wellesley College'},
  harvard:   {bow:-0.06, dx: 14, dy: -8, a:'start', short:'Harvard Art Museums'},
  hirshhorn: {bow: 0.04, dx:-14, dy:  5, a:'end',   short:'Hirshhorn Museum'},
  buffalo:   {bow:-0.05, dx: 15, dy:  5, a:'start', short:'Buffalo AKG'},
  moma:      {bow: 0.00, dx: 12, dy: -8, a:'start', short:'MoMA'},
  pace:      {bow: 0.13, dx:-12, dy: -3, a:'end',   short:'Pace Gallery'},
  diachelsea:{bow:-0.13, dx:-12, dy: 14, a:'end',   short:'Dia Chelsea'},
  whitney:   {bow: 0.06, dx:-12, dy:  5, a:'end',   short:'Whitney'},
  breuer:    {bow:-0.14, dx: 12, dy:  6, a:'start', short:'Breuer Building'},
  met:       {bow: 0.02, dx: 12, dy:  4, a:'start', short:'The Met'},
  gugg:      {bow: 0.14, dx: 12, dy:  3, a:'start', short:'Guggenheim'},
};

const esc = s => String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
const col = m => `var(--m-${m})`;

function arc(ax, ay, bx, by, bow){
  const mx = (ax+bx)/2, my = (ay+by)/2, dx = bx-ax, dy = by-ay;
  return `M${ax},${ay}Q${(mx - dy*bow).toFixed(1)},${(my + dx*bow).toFixed(1)} ${bx},${by}`;
}

function marker(s, x, y, r, override){
  const c = override || col(s.mode);
  if (s.status === 'installed')
    return `<circle class="halo" cx="${x}" cy="${y}" r="${r+1.8}"/>`
         + `<circle cx="${x}" cy="${y}" r="${r+5}" fill="none" stroke="${c}" stroke-width="1.1" opacity=".5"/>`
         + `<circle cx="${x}" cy="${y}" r="${r}" fill="${c}"/>`;
  if (s.status === 'collection')
    return `<circle class="halo" cx="${x}" cy="${y}" r="${r}"/>`
         + `<circle cx="${x}" cy="${y}" r="${r}" fill="var(--surface)" stroke="${c}" stroke-width="2.6"/>`;
  if (s.status === 'gallery')
    return `<circle class="halo" cx="${x}" cy="${y}" r="${r}"/>`
         + `<circle cx="${x}" cy="${y}" r="${r}" fill="var(--surface)" stroke="${c}" stroke-width="2.2"/>`
         + `<circle cx="${x}" cy="${y}" r="${r-3.4}" fill="${c}"/>`;
  const d = r + 1.2;   // historic — open diamond
  return `<path class="halo" d="M${x},${y-d}L${x+d},${y}L${x},${y+d}L${x-d},${y}Z"/>`
       + `<path d="M${x},${y-d}L${x+d},${y}L${x},${y+d}L${x-d},${y}Z" fill="var(--surface)" stroke="${c}" stroke-width="2.4"/>`;
}


const SHAPEKEY = [
  ['installed',  'Permanently sited'],
  ['collection', 'In a collection'],
  ['gallery',    'Gallery representation'],
  ['historic',   'Historic site, not extant'],
];
function shapeKey(x, y){
  const rows = SHAPEKEY.map(([st, label], i) => {
    const cy = y + 30 + i * 27;
    return marker({status: st}, x + 11, cy, 6.5, 'var(--ink-2)')
         + `<text class="keylab" x="${x + 30}" y="${cy + 4}">${label}</text>`;
  }).join('');
  return `<g pointer-events="none"><text class="keyhd" x="${x}" y="${y}">WHAT YOU'D FIND THERE</text>${rows}</g>`;
}

/* ---------------------------------------------------------------- maps --- */
const O = DATA.origin;
const inInset  = DATA.sites.filter(s => s.inInset);
const onRegion = DATA.sites.filter(s => !s.inInset);

function routeGroup(sites, key, ax, ay, r){
  let casings = '', lines = '', hits = '', marks = '', labels = '';
  sites.forEach(s => {
    const p = POS[s.k], bx = key === 'ix' ? s.ix : s.x, by = key === 'ix' ? s.iy : s.y;
    const d = arc(ax, ay, bx, by, p.bow), dash = MODE[s.mode].dash;
    casings += `<path class="casing" d="${d}"/>`;
    lines   += `<path class="route" data-k="${s.k}" data-mode="${s.mode}" d="${d}" style="stroke:${col(s.mode)}"${dash ? ` stroke-dasharray="${dash}"` : ''}/>`;
    hits    += `<path class="hit" data-k="${s.k}" d="${d}"/>`;
    marks   += `<g class="mk" data-k="${s.k}" data-mode="${s.mode}" tabindex="0" role="button" aria-label="${esc(s.name)}, ${s.mi} miles, ${STATUS[s.status].toLowerCase()}">${marker(s, bx, by, r)}</g>`;
    labels  += `<text class="lab${r < 6 ? ' sm' : ''}" data-k="${s.k}" data-mode="${s.mode}" x="${bx + p.dx}" y="${by + p.dy}" text-anchor="${p.a}">${esc(p.short)}</text>`;
  });
  return `<g class="casings">${casings}</g><g class="routes">${lines}</g>`
       + `<g class="marks">${marks}</g><g class="labels">${labels}</g><g class="hits">${hits}</g>`;
}

function drawMain(){
  const svg = document.getElementById('map');
  svg.setAttribute('viewBox', `0 0 ${REGION.vbW} ${REGION.vbH}`);
  const outland = REGION.states.map(s => `<path class="outland" d="${s.p}"/>`).join('');
  const counties = REGION.counties.map((c, i) =>
    `<path class="county" d="${c.p}" fill="var(--b${c.b})" data-i="${i}"/>`).join('');
  const lines = REGION.states.map(s => `<path class="stateline" d="${s.p}"/>`).join('');
  const rings = REGION.ringPaths.map(r =>
    `<path class="ring" d="${r.p}"/><text class="ringlab" x="${r.lx + 7}" y="${r.ly + 4}">${r.mi}</text>`).join('');
  svg.innerHTML =
      `<rect width="100%" height="100%" fill="var(--sea)"/>`
    + `<g>${outland}</g><g id="counties">${counties}</g><g>${lines}</g><g>${rings}</g>`
    + routeGroup(onRegion, 'x', O.x, O.y, 6.5)
    + `<g pointer-events="none">`
    +   `<circle cx="${O.x}" cy="${O.y}" r="9" fill="none" stroke="var(--ink)" stroke-width="1.2" opacity=".55"/>`
    +   `<circle cx="${O.x}" cy="${O.y}" r="2.6" fill="var(--ink)"/>`
    +   `<text class="origin-lab" x="${O.x + 15}" y="${O.y + 15}">TIMES SQUARE</text>`
    +   `<text class="origin-lab" x="${O.x + 15}" y="${O.y + 30}" opacity=".75">7 more works within 2.2 mi →</text>`
    + `</g>`
    + shapeKey(700, 830);
}

function drawInset(){
  const svg = document.getElementById('inset'), I = DATA.inset;
  svg.setAttribute('viewBox', `-14 -10 ${I.w + 46} ${I.h + 22}`);
  svg.innerHTML =
      `<rect x="-14" y="-10" width="${I.w + 46}" height="${I.h + 22}" fill="var(--sea)"/>`
    + `<g>${I.land.map(l => `<path d="${l.p}" fill="var(--${l.k})" stroke="var(--hair)" stroke-width="1" vector-effect="non-scaling-stroke"/>`).join('')}</g>`
    + `<g class="waterlab" pointer-events="none">`
    +   `<text x="52" y="548" text-anchor="middle" transform="rotate(-70 52 548)">HUDSON R.</text>`
    +   `<text x="420" y="424" text-anchor="middle" transform="rotate(-63 420 424)">EAST R.</text>`
    +   `<text x="423" y="76" text-anchor="middle" transform="rotate(-61 423 76)">CENTRAL PARK</text>`
    + `</g>`
    + routeGroup(inInset, 'ix', O.ix, O.iy, 5.5)
    + `<g pointer-events="none">`
    +   `<circle cx="${O.ix}" cy="${O.iy}" r="8" fill="none" stroke="var(--ink)" stroke-width="1.2" opacity=".55"/>`
    +   `<circle cx="${O.ix}" cy="${O.iy}" r="2.4" fill="var(--ink)"/>`
    +   `<text class="origin-lab" x="${O.ix - 13}" y="${O.iy - 10}" text-anchor="end">TIMES SQ</text>`
    + `</g>`;
}

/* ------------------------------------------------------------ chrome --- */
function drawChrome(){
  document.getElementById('stats').innerHTML = [
    ['13',  'places inside the circle'],
    ['2',   'reliably there any day'],
    ['293', 'miles to the farthest'],
    ['0',   'reachable on the LIRR'],
  ].map(([b, s]) => `<div class="stat"><b>${b}</b><span>${s}</span></div>`).join('');

  document.getElementById('bandsw').innerHTML =
    REGION.bands.map((_, i) => `<div style="background:var(--b${i})"></div>`).join('');

  document.getElementById('modes').innerHTML = MODES.map(m => {
    const n = DATA.sites.filter(s => s.mode === m.k).length;
    const sw = `<svg class="swatch" viewBox="0 0 34 14" aria-hidden="true"><path d="M0,7H34" stroke="${col(m.k)}" stroke-width="3" stroke-linecap="round"${m.dash ? ` stroke-dasharray="${m.dash}"` : ''}/></svg>`;
    return n === 0
      ? `<div class="chip null" aria-disabled="true">${sw}<span>${m.label}<br><span style="font-size:12.5px;color:var(--ink-3)">${m.blurb}</span></span><span class="ct">0</span></div>`
      : `<button class="chip" type="button" data-mode="${m.k}" aria-pressed="true">${sw}<span>${m.label}<br><span style="font-size:12.5px;color:var(--ink-3)">${m.blurb}</span></span><span class="ct">${n}</span></button>`;
  }).join('');

  document.getElementById('tbody').innerHTML = DATA.sites
    .slice().sort((a, b) => a.mi - b.mi).map(s => `
      <tr data-k="${s.k}" tabindex="0">
        <td><strong>${esc(s.name)}</strong><br><span style="color:var(--ink-3);font-size:13.5px">${esc(s.place)}</span></td>
        <td><span class="w">${esc(s.work)}</span></td>
        <td><span class="modecell"><i style="background:${col(s.mode)}"></i>${MODE[s.mode].label}</span></td>
        <td class="num">${s.mi}</td>
        <td><span class="tag">${STATUS[s.status]}</span></td>
      </tr>`).join('');
}

/* ------------------------------------------------------------ state --- */
const active = new Set(MODES.map(m => m.k));
let selected = 'beacon';

function showDetail(k){
  const s = DATA.sites.find(x => x.k === k); if (!s) return;
  selected = k;
  document.getElementById('detailhint').textContent = `${s.mi} mi from Times Square`;
  document.getElementById('detail').innerHTML = `
    <div class="col">
      <div class="kicker"><i style="background:${col(s.mode)}"></i><span>${MODE[s.mode].label} &middot; ${STATUS[s.status]}</span></div>
      <h3>${esc(s.name)}</h3>
      <p class="place">${esc(s.place)}</p>
      <p class="work">${esc(s.work)}</p>
      <p class="note" style="margin-bottom:0">${esc(s.note)}</p>
    </div>
    <p class="how">${esc(s.how)}</p>`;
  paint();
}

function paint(){
  document.querySelectorAll('.route, .mk, .lab').forEach(el => {
    const m = el.dataset.mode, k = el.dataset.k;
    const off = !active.has(m);
    el.classList.toggle('dim', off);
    el.style.opacity = off ? '' : (k === selected ? '1' : '.82');
    if (el.classList.contains('route')) el.setAttribute('stroke-width', k === selected ? 4 : 2.6);
  });
  document.querySelectorAll('#tbody tr').forEach(tr => {
    tr.style.background = tr.dataset.k === selected ? 'var(--surface-2)' : '';
  });
}

/* -------------------------------------------------------------- wire --- */
const tip = document.getElementById('tip');
function showTip(e, html){
  tip.innerHTML = html; tip.style.opacity = '1';
  const w = tip.offsetWidth, h = tip.offsetHeight;
  tip.style.left = Math.min(e.clientX + 14, innerWidth - w - 10) + 'px';
  tip.style.top  = Math.max(8, e.clientY - h - 12) + 'px';
}
const hideTip = () => { tip.style.opacity = '0'; };

function init(){
  drawMain(); drawInset(); drawChrome(); showDetail(selected);

  document.getElementById('counties').addEventListener('mousemove', e => {
    const p = e.target.closest('.county'); if (!p) return hideTip();
    const c = REGION.counties[+p.dataset.i];
    showTip(e, `<strong>${esc(c.n)} County</strong><br>${c.d} mi from Times Square`);
  });
  document.getElementById('counties').addEventListener('mouseleave', hideTip);

  document.querySelectorAll('#map, #inset').forEach(svg => {
    svg.addEventListener('mouseover', e => {
      const t = e.target.closest('[data-k]'); if (!t) return;
      const s = DATA.sites.find(x => x.k === t.dataset.k); if (!s) return;
      showTip(e, `<strong>${esc(s.name)}</strong><br>${s.mi} mi &middot; ${MODE[s.mode].label}`);
    });
    svg.addEventListener('mousemove', e => { if (!e.target.closest('[data-k]')) hideTip(); });
    svg.addEventListener('mouseleave', hideTip);
    svg.addEventListener('click', e => {
      const t = e.target.closest('[data-k]'); if (t) showDetail(t.dataset.k);
    });
    svg.addEventListener('keydown', e => {
      if (e.key !== 'Enter' && e.key !== ' ') return;
      const t = e.target.closest('[data-k]'); if (t) { e.preventDefault(); showDetail(t.dataset.k); }
    });
  });

  document.getElementById('modes').addEventListener('click', e => {
    const b = e.target.closest('.chip[data-mode]'); if (!b) return;
    const m = b.dataset.mode;
    active.has(m) ? active.delete(m) : active.add(m);
    b.setAttribute('aria-pressed', active.has(m));
    paint();
  });

  document.getElementById('tbody').addEventListener('click', e => {
    const tr = e.target.closest('tr'); if (tr) showDetail(tr.dataset.k);
  });
  document.getElementById('tbody').addEventListener('keydown', e => {
    if (e.key !== 'Enter' && e.key !== ' ') return;
    const tr = e.target.closest('tr'); if (tr) { e.preventDefault(); showDetail(tr.dataset.k); }
  });

  if (!matchMedia('(prefers-reduced-motion: reduce)').matches) {
    document.querySelectorAll('#map .marks .mk, #inset .marks .mk').forEach((g, i) => {
      g.classList.add('fade'); g.style.animationDelay = (90 + i * 45) + 'ms';
    });
  }
}
init();
