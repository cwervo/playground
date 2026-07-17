'use strict';

/* =========================================================================
   TuringDoodle
   Draw symbols on paper, show them to the camera, and TuringDoodle turns
   them into a running Turing machine (or a handwritten math expression).
   ========================================================================= */

/* ---------------------------------------------------------------------- *
 * Constants
 * ---------------------------------------------------------------------- */

const WORK_MAX = 560;          // longest side of the working (CV) resolution
const MIN_PIXELS = 8;          // ignore ink blobs smaller than this (noise)
const GRID_N = 16;             // template grid resolution (N x N)
const MATCH_MAX_DIST = 0.40;   // normalized Hamming distance cutoff for a match
const MAX_SAMPLES_PER_SYMBOL = 6;

const MATH_ALPHABET = [
  '0','1','2','3','4','5','6','7','8','9',
  '+','-','/','%','~','*','=','^','$',
  'A','B','C','D','E','F','G','H','I','J','K','L','M','N',
  'O','P','Q','R','S','T','U','V','W','X','Y','Z'
];

const TUTORIALS = {
  simple: [
    `TuringDoodle turns hand-drawn marks into a working Turing machine.
     Two symbols are all you need: a dash <span class="sym-demo">&minus;</span>
     means <b>0</b>, and a line <span class="sym-demo">|</span> means <b>1</b>.`,
    `Grab a plain sheet of white paper and a dark marker. Draw a single short
     horizontal dash near the top-left. That's your first <b>0</b>.`,
    `Now draw a single vertical line next to it. That's a <b>1</b>. Draw a
     row of a few dashes and lines side by side, left to right &mdash; that
     row is a <b>Turing tape</b>.`,
    `Hold the sheet flat in front of the camera and tap the shutter button
     below to scan it. TuringDoodle reads your marks left-to-right and shows
     them as an editable tape.`,
    `Ready for the fun part? Draw a tape shaped like
     <span class="sym-demo">| | | &minus; | |</span> &mdash; a group of lines,
     one dash, then another group of lines: two numbers, unary-style. Scan
     it, then hit <b>Run</b> and watch the machine erase the dash and delete
     one line, leaving a tape whose length is the sum!`
  ],
  math: [
    `Math mode expands the alphabet to digits <b>0-9</b>, letters <b>A-Z</b>,
     operators <b>+ - * / % ^ ~ =</b>, and variables written as
     <b>$</b> followed by a letter (like <b>$A</b>).`,
    `Before scanning, train the recognizer: open <b>Settings</b>, and for
     each symbol you plan to use, draw it on paper, hold it to the camera
     so it fills most of the frame, and tap its tile &mdash; TuringDoodle
     remembers what your handwriting looks like.`,
    `Once a few symbols are trained, draw a short expression in a single
     row, like <span class="sym-demo">12+7</span> or
     <span class="sym-demo">$A*$B</span>, and tap the shutter.`,
    `TuringDoodle segments the row left-to-right, matches each mark against
     your trained samples, and overlays the recognized expression plus its
     live value. Assign values to any variables in the panel that appears.`
  ],
  custom: [
    `Custom mode is a playground for exploring higher-order Turing machines
     beyond plain binary. Define your own alphabet in <b>Settings</b> &mdash;
     any comma-separated list of symbols.`,
    `Train each symbol the same way as Math mode: draw it large on paper,
     hold it to the camera, and tap its tile in the Settings train grid.`,
    `Then draw any row using your alphabet and tap the shutter to scan.
     Recognized symbols are overlaid on the photo left-to-right.`
  ]
};

/* ---------------------------------------------------------------------- *
 * DOM references
 * ---------------------------------------------------------------------- */

const video = document.getElementById('camera');
const stage = document.getElementById('stage');
const stageCtx = stage.getContext('2d');

const modeSelect = document.getElementById('modeSelect');
const settingsBtn = document.getElementById('settingsBtn');
const helpBtn = document.getElementById('helpBtn');
const settingsPanel = document.getElementById('settingsPanel');
const closeSettings = document.getElementById('closeSettings');
const legendEl = document.getElementById('legend');

const customAlphabetSection = document.getElementById('customAlphabetSection');
const customAlphabetInput = document.getElementById('customAlphabetInput');
const applyCustomAlphabet = document.getElementById('applyCustomAlphabet');
const trainGrid = document.getElementById('trainGrid');
const clearTrainingBtn = document.getElementById('clearTraining');
const thresholdBias = document.getElementById('thresholdBias');
const mirrorToggle = document.getElementById('mirrorToggle');
const flipCameraBtn = document.getElementById('flipCameraBtn');

const tutorialCard = document.getElementById('tutorialCard');
const tutorialStepLabel = document.getElementById('tutorialStepLabel');
const tutorialBody = document.getElementById('tutorialBody');
const tutorialNext = document.getElementById('tutorialNext');
const tutorialBack = document.getElementById('tutorialBack');
const tutorialSkip = document.getElementById('tutorialSkip');

const resultBanner = document.getElementById('resultBanner');

const tapePanel = document.getElementById('tapePanel');
const tapeScroll = document.getElementById('tapeScroll');
const tapeAddZero = document.getElementById('tapeAddZero');
const tapeAddOne = document.getElementById('tapeAddOne');
const tapeRemove = document.getElementById('tapeRemove');
const tapeClear = document.getElementById('tapeClear');
const tapeReset = document.getElementById('tapeReset');
const tapeStep = document.getElementById('tapeStep');
const tapeRun = document.getElementById('tapeRun');
const speedSlider = document.getElementById('speedSlider');
const tmStateEl = document.getElementById('tmState');

const exprPanel = document.getElementById('exprPanel');
const exprReadout = document.getElementById('exprReadout');
const exprVarsEl = document.getElementById('exprVars');
const exprResult = document.getElementById('exprResult');

const scanBtn = document.getElementById('scanBtn');
const liveBtn = document.getElementById('liveBtn');
const uploadBtn = document.getElementById('uploadBtn');
const uploadInput = document.getElementById('uploadInput');
const cameraError = document.getElementById('cameraError');

const workCanvas = document.createElement('canvas');
const workCtx = workCanvas.getContext('2d', { willReadFrequently: true });

/* ---------------------------------------------------------------------- *
 * Application state
 * ---------------------------------------------------------------------- */

const appState = {
  mode: 'simple',
  stream: null,
  facingMode: 'environment',
  mirror: false,
  thresholdBias: 0,

  frozen: false,
  frozenCanvas: null,
  lastBinary: null,
  lastWorkW: 0,
  lastWorkH: 0,
  lastGroups: null,        // math/custom mode: recognized groups with .symbol

  tape: [],                // simple mode: [{value: 0|1|null}]
  groupsForTape: [],       // parallel array of bbox groups (or null)
  snapshot: [],
  tm: null,                // {state, head} | null

  lastMergedTokens: [],
  varValues: {},

  tutorialMode: 'simple',
  tutorialStep: 0
};

/* ---------------------------------------------------------------------- *
 * Persistence helpers
 * ---------------------------------------------------------------------- */

function loadSettings() {
  try {
    const s = JSON.parse(localStorage.getItem('td_settings') || '{}');
    if (typeof s.thresholdBias === 'number') appState.thresholdBias = s.thresholdBias;
    if (typeof s.mirror === 'boolean') appState.mirror = s.mirror;
    if (typeof s.facingMode === 'string') appState.facingMode = s.facingMode;
  } catch { /* ignore malformed settings */ }
}

function saveSettings() {
  localStorage.setItem('td_settings', JSON.stringify({
    thresholdBias: appState.thresholdBias,
    mirror: appState.mirror,
    facingMode: appState.facingMode
  }));
}

function loadTemplates(mode) {
  const key = mode === 'math' ? 'td_templates_math' : 'td_templates_custom';
  try { return JSON.parse(localStorage.getItem(key) || '{}'); }
  catch { return {}; }
}

function saveTemplates(mode, obj) {
  const key = mode === 'math' ? 'td_templates_math' : 'td_templates_custom';
  localStorage.setItem(key, JSON.stringify(obj));
}

function parseCustomAlphabet(str) {
  const seen = new Set();
  const out = [];
  for (const raw of str.split(',')) {
    const s = raw.trim();
    if (!s || seen.has(s)) continue;
    seen.add(s);
    out.push(s);
  }
  return out;
}

function currentAlphabetForMode() {
  if (appState.mode === 'simple') return ['0', '1'];
  if (appState.mode === 'math') return MATH_ALPHABET;
  return parseCustomAlphabet(localStorage.getItem('td_custom_alphabet') || '');
}

/* ---------------------------------------------------------------------- *
 * Camera
 * ---------------------------------------------------------------------- */

async function startCamera(facingMode) {
  try {
    if (appState.stream) {
      appState.stream.getTracks().forEach(t => t.stop());
    }
    const stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: { ideal: facingMode }, width: { ideal: 1280 }, height: { ideal: 960 } },
      audio: false
    });
    appState.stream = stream;
    video.srcObject = stream;
    await video.play();
    cameraError.classList.add('hidden');
  } catch (err) {
    cameraError.classList.remove('hidden');
    cameraError.innerHTML =
      `<div>Camera unavailable (${(err && (err.message || err.name)) || 'unknown error'}).<br>` +
      `You can still <b>upload a photo</b> (top-left button) or build a tape manually below.</div>`;
  }
}

/* ---------------------------------------------------------------------- *
 * Vision pipeline
 * ---------------------------------------------------------------------- */

function computeWorkingSize(srcW, srcH) {
  const scale = WORK_MAX / Math.max(srcW, srcH);
  return { w: Math.max(1, Math.round(srcW * scale)), h: Math.max(1, Math.round(srcH * scale)) };
}

function toGrayscale(imageData) {
  const { data } = imageData;
  const gray = new Uint8ClampedArray(data.length / 4);
  for (let i = 0, p = 0; i < data.length; i += 4, p++) {
    gray[p] = (data[i] * 0.299 + data[i + 1] * 0.587 + data[i + 2] * 0.114) | 0;
  }
  return gray;
}

function otsuThreshold(gray) {
  const hist = new Array(256).fill(0);
  for (let i = 0; i < gray.length; i++) hist[gray[i]]++;
  const total = gray.length;
  let sum = 0;
  for (let t = 0; t < 256; t++) sum += t * hist[t];
  let sumB = 0, wB = 0, varMax = 0, threshold = 128;
  for (let t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB === 0) continue;
    const wF = total - wB;
    if (wF === 0) break;
    sumB += t * hist[t];
    const mB = sumB / wB;
    const mF = (sum - sumB) / wF;
    const varBetween = wB * wF * (mB - mF) * (mB - mF);
    if (varBetween > varMax) { varMax = varBetween; threshold = t; }
  }
  return threshold;
}

function binarize(gray, threshold) {
  const binary = new Uint8Array(gray.length);
  for (let i = 0; i < gray.length; i++) binary[i] = gray[i] < threshold ? 1 : 0;
  return binary;
}

function connectedComponents(binary, w, h) {
  const labels = new Int32Array(w * h).fill(-1);
  const comps = [];
  const stack = [];
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const idx = y * w + x;
      if (binary[idx] !== 1 || labels[idx] !== -1) continue;
      const compId = comps.length;
      labels[idx] = compId;
      let minX = x, maxX = x, minY = y, maxY = y, count = 0;
      stack.push(idx);
      while (stack.length) {
        const cur = stack.pop();
        const cx = cur % w, cy = (cur / w) | 0;
        count++;
        if (cx < minX) minX = cx; if (cx > maxX) maxX = cx;
        if (cy < minY) minY = cy; if (cy > maxY) maxY = cy;
        for (let dy = -1; dy <= 1; dy++) {
          for (let dx = -1; dx <= 1; dx++) {
            if (dx === 0 && dy === 0) continue;
            const nx = cx + dx, ny = cy + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            const nidx = ny * w + nx;
            if (binary[nidx] === 1 && labels[nidx] === -1) {
              labels[nidx] = compId;
              stack.push(nidx);
            }
          }
        }
      }
      comps.push({ minX, maxX, minY, maxY, count });
    }
  }
  return { labels, comps };
}

function median(arr) {
  if (!arr.length) return 0;
  const s = [...arr].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

function clusterComponents(comps) {
  const n = comps.length;
  const parent = Array.from({ length: n }, (_, i) => i);
  function find(a) { while (parent[a] !== a) { parent[a] = parent[parent[a]]; a = parent[a]; } return a; }
  function union(a, b) { const ra = find(a), rb = find(b); if (ra !== rb) parent[ra] = rb; }

  const heights = comps.map(c => c.maxY - c.minY + 1);
  const medianH = median(heights) || 10;
  const gap = Math.max(6, medianH * 0.7);

  for (let i = 0; i < n; i++) {
    for (let j = i + 1; j < n; j++) {
      const a = comps[i], b = comps[j];
      const ax0 = a.minX - gap, ax1 = a.maxX + gap, ay0 = a.minY - gap, ay1 = a.maxY + gap;
      const intersects = !(b.minX > ax1 || b.maxX < ax0 || b.minY > ay1 || b.maxY < ay0);
      if (intersects) union(i, j);
    }
  }

  const groupsMap = new Map();
  for (let i = 0; i < n; i++) {
    const r = find(i);
    if (!groupsMap.has(r)) groupsMap.set(r, []);
    groupsMap.get(r).push(comps[i]);
  }

  const groups = [];
  for (const members of groupsMap.values()) {
    const minX = Math.min(...members.map(m => m.minX));
    const maxX = Math.max(...members.map(m => m.maxX));
    const minY = Math.min(...members.map(m => m.minY));
    const maxY = Math.max(...members.map(m => m.maxY));
    const count = members.reduce((s, m) => s + m.count, 0);
    groups.push({ minX, maxX, minY, maxY, count, cx: (minX + maxX) / 2, cy: (minY + maxY) / 2 });
  }
  return groups;
}

function extractGroupGrid(binary, w, h, group, N) {
  const { minX, maxX, minY, maxY } = group;
  const gw = maxX - minX + 1, gh = maxY - minY + 1;
  const grid = new Uint8Array(N * N);
  for (let gy = 0; gy < N; gy++) {
    for (let gx = 0; gx < N; gx++) {
      const x0 = minX + Math.floor(gx / N * gw);
      const x1 = minX + Math.floor((gx + 1) / N * gw);
      const y0 = minY + Math.floor(gy / N * gh);
      const y1 = minY + Math.floor((gy + 1) / N * gh);
      let ink = 0, total = 0;
      for (let y = y0; y <= y1 && y <= maxY; y++) {
        for (let x = x0; x <= x1 && x <= maxX; x++) {
          total++;
          if (binary[y * w + x] === 1) ink++;
        }
      }
      grid[gy * N + gx] = (total > 0 && ink / total > 0.18) ? 1 : 0;
    }
  }
  return grid;
}

function classifySimple(group) {
  const width = group.maxX - group.minX + 1;
  const height = group.maxY - group.minY + 1;
  const aspect = width / height;
  if (aspect >= 1.7) return 0;
  if (aspect <= 0.6) return 1;
  return null;
}

function matchTemplate(grid, templates, alphabet) {
  let best = null, bestDist = Infinity;
  for (const sym of alphabet) {
    const samples = templates[sym];
    if (!samples || !samples.length) continue;
    for (const s of samples) {
      let dist = 0;
      for (let k = 0; k < grid.length; k++) if (grid[k] !== s[k]) dist++;
      if (dist < bestDist) { bestDist = dist; best = sym; }
    }
  }
  const normalized = bestDist / grid.length;
  if (best === null || normalized > MATCH_MAX_DIST) return { symbol: null, confidence: 1 - normalized };
  return { symbol: best, confidence: 1 - normalized };
}

function scanFromSource(source, sw, sh) {
  const { w, h } = computeWorkingSize(sw, sh);
  workCanvas.width = w;
  workCanvas.height = h;
  workCtx.drawImage(source, 0, 0, w, h);
  const imageData = workCtx.getImageData(0, 0, w, h);
  const gray = toGrayscale(imageData);
  const threshold = Math.min(255, Math.max(0, otsuThreshold(gray) + appState.thresholdBias));
  const binary = binarize(gray, threshold);
  const { comps } = connectedComponents(binary, w, h);
  const filtered = comps.filter(c =>
    c.count >= MIN_PIXELS &&
    (c.maxX - c.minX) < w * 0.9 &&
    (c.maxY - c.minY) < h * 0.9
  );
  const groups = clusterComponents(filtered).sort((a, b) => a.cx - b.cx);
  return { w, h, groups, binary };
}

/* ---------------------------------------------------------------------- *
 * Simple mode: tape + Turing machine (unary addition)
 * ---------------------------------------------------------------------- */

function captureSnapshot() {
  appState.snapshot = appState.tape.map(c => ({ ...c }));
}

function buildTapeFromGroups(groups) {
  appState.tape = groups.map(g => ({ value: classifySimple(g) }));
  appState.groupsForTape = groups.slice();
  appState.tm = null;
  captureSnapshot();
  renderTape();

  const zeros = appState.tape.filter(c => c.value === 0).length;
  const unknowns = appState.tape.filter(c => c.value === null).length;
  if (unknowns > 0) {
    showResultBanner(`Scanned ${appState.tape.length} marks, ${unknowns} unclear — tap them to set −/|.`);
  } else if (zeros === 1) {
    const idx = appState.tape.findIndex(c => c.value === 0);
    const m = idx, n = appState.tape.length - idx - 1;
    showResultBanner(`Tape read as ${m} + ${n}. Tap ▶ Run to compute.`);
  } else {
    showResultBanner(`Scanned tape: ${appState.tape.map(c => (c.value === 0 ? '−' : '|')).join(' ')}`);
  }
}

function renderTape() {
  tapeScroll.innerHTML = '';
  appState.tape.forEach((cell, i) => {
    const div = document.createElement('div');
    div.className = 'tape-cell';
    div.dataset.index = String(i);
    if (cell.value === 0) { div.classList.add('zero'); div.textContent = '−'; }
    else if (cell.value === 1) { div.classList.add('one'); div.textContent = '|'; }
    else { div.classList.add('unknown'); div.textContent = '?'; }
    if (appState.tm && appState.tm.head === i && appState.tm.state !== 'idle') {
      div.classList.add('head');
    }
    tapeScroll.appendChild(div);
  });
  updateTMStateText();
}

tapeScroll.addEventListener('click', (e) => {
  const cell = e.target.closest('.tape-cell');
  if (!cell) return;
  if (appState.tm && appState.tm.timer) return; // don't edit mid-run
  const idx = Number(cell.dataset.index);
  const cur = appState.tape[idx].value;
  appState.tape[idx].value = cur === null ? 0 : (cur === 0 ? 1 : 0);
  appState.tm = null;
  captureSnapshot();
  renderTape();
});

function validateTapeForRun() {
  if (appState.tape.some(c => c.value === null)) return 'Resolve unclear cells first (tap them).';
  const zeros = appState.tape.filter(c => c.value === 0).length;
  if (zeros !== 1) return 'Draw exactly one dash (0) between two groups of lines (1s), e.g. | | | − | |.';
  if (appState.tape.length < 3) return 'Tape too short — need at least one 1, one 0, one 1.';
  return null;
}

function startRunIfNeeded() {
  if (!appState.tm || appState.tm.state === 'idle') {
    const err = validateTapeForRun();
    if (err) { showResultBanner(err); return false; }
    appState.tm = { state: 'seek-separator', head: 0, timer: null };
  }
  return true;
}

function updateTMStateText() {
  const tm = appState.tm;
  if (!tm) { tmStateEl.textContent = ''; return; }
  const labels = {
    idle: 'Ready.',
    'seek-separator': 'Seeking the dash (0)…',
    'seek-end': 'Marked. Sweeping to the end of the tape…',
    'delete-last': 'Deleting the last line…',
    halt: 'Halted ✓',
    error: 'Error — ran off the tape.'
  };
  tmStateEl.textContent = `${labels[tm.state] || tm.state}  (head @ ${tm.head})`;
}

function stepTM() {
  if (!startRunIfNeeded()) return;
  const tm = appState.tm;
  if (tm.state === 'halt' || tm.state === 'error') return;
  const tape = appState.tape;
  switch (tm.state) {
    case 'seek-separator':
      if (tm.head >= tape.length) { tm.state = 'error'; break; }
      if (tape[tm.head].value === 1) { tm.head++; }
      else { tape[tm.head].value = 1; tm.state = 'seek-end'; tm.head++; }
      break;
    case 'seek-end':
      if (tm.head < tape.length) { tm.head++; }
      else { tm.state = 'delete-last'; tm.head = tape.length - 1; }
      break;
    case 'delete-last':
      tape.splice(tm.head, 1);
      if (appState.groupsForTape.length > tm.head) appState.groupsForTape.splice(tm.head, 1);
      tm.state = 'halt';
      break;
  }
  renderTape();
  if (tm.state === 'halt') {
    showResultBanner(`Halted — result tape has ${tape.length} lines. Sum = ${tape.length}.`);
  } else if (tm.state === 'error') {
    showResultBanner('Machine error: ran off the tape.');
  }
}

function runTM() {
  if (!startRunIfNeeded()) return;
  if (appState.tm.timer) return;
  const delay = Math.max(80, 750 - (Number(speedSlider.value) - 1) * 70);
  appState.tm.timer = setInterval(() => {
    stepTM();
    if (!appState.tm || appState.tm.state === 'halt' || appState.tm.state === 'error') {
      if (appState.tm && appState.tm.timer) clearInterval(appState.tm.timer);
      if (appState.tm) appState.tm.timer = null;
    }
  }, delay);
}

/* ---------------------------------------------------------------------- *
 * Math / custom mode: expression recognition + evaluation
 * ---------------------------------------------------------------------- */

function mergeTokens(raw) {
  const out = [];
  let i = 0;
  while (i < raw.length) {
    const t = raw[i];
    if (t === '$' && i + 1 < raw.length && /^[A-Z]$/.test(raw[i + 1])) {
      out.push('$' + raw[i + 1]); i += 2; continue;
    }
    if (/^[0-9]$/.test(t)) {
      let num = t; i++;
      while (i < raw.length && /^[0-9]$/.test(raw[i])) { num += raw[i]; i++; }
      out.push(num); continue;
    }
    out.push(t); i++;
  }
  return out;
}

function evaluateExpression(tokens, vars) {
  let pos = 0;
  const PREC = { '+': 1, '-': 1, '*': 2, '/': 2, '%': 2, '^': 3 };
  const RIGHT_ASSOC = { '^': true };

  function peek() { return tokens[pos]; }
  function advance() { return tokens[pos++]; }

  function applyOp(op, a, b) {
    switch (op) {
      case '+': return a + b;
      case '-': return a - b;
      case '*': return a * b;
      case '/': return b === 0 ? NaN : a / b;
      case '%': return b === 0 ? NaN : a % b;
      case '^': return Math.pow(a, b);
      default: throw new Error(`Unknown operator "${op}"`);
    }
  }

  function parsePrimary() {
    const t = peek();
    if (t === undefined) throw new Error('Incomplete expression');
    if (t === '-' || t === '~') {
      advance();
      const val = parsePrimary();
      return t === '-' ? -val : (~Math.trunc(val));
    }
    if (/^[0-9]+$/.test(t)) { advance(); return parseFloat(t); }
    if (/^\$[A-Z]$/.test(t)) { advance(); return Number(vars[t] ?? 0); }
    throw new Error(`Unexpected symbol "${t}"`);
  }

  function parseExpr(minPrec) {
    let left = parsePrimary();
    for (;;) {
      const op = peek();
      const prec = PREC[op];
      if (prec === undefined || prec < minPrec) break;
      advance();
      const nextMinPrec = RIGHT_ASSOC[op] ? prec : prec + 1;
      const right = parseExpr(nextMinPrec);
      left = applyOp(op, left, right);
    }
    return left;
  }

  const result = parseExpr(0);
  if (pos !== tokens.length) throw new Error(`Unexpected trailing symbol "${tokens[pos]}"`);
  return result;
}

function evalWithEquals(tokens, vars) {
  const eqIdx = tokens.indexOf('=');
  if (eqIdx === -1) return { value: evaluateExpression(tokens, vars) };
  const lhs = evaluateExpression(tokens.slice(0, eqIdx), vars);
  const rhs = evaluateExpression(tokens.slice(eqIdx + 1), vars);
  return { lhs, rhs, equal: Math.abs(lhs - rhs) < 1e-9 };
}

function formatNum(x) {
  if (!isFinite(x)) return String(x);
  return String(Math.round(x * 1e6) / 1e6);
}

function processExpressionGroups(groups) {
  const alphabet = currentAlphabetForMode();
  const templates = loadTemplates(appState.mode);
  const rawTokens = groups.map(g => {
    const grid = extractGroupGrid(appState.lastBinary, appState.lastWorkW, appState.lastWorkH, g, GRID_N);
    const match = matchTemplate(grid, templates, alphabet);
    g.symbol = match.symbol || '?';
    return g.symbol;
  });
  appState.lastGroups = groups;
  exprPanel.classList.remove('hidden');
  exprReadout.textContent = rawTokens.join(' ') || '—';

  const unknownCount = rawTokens.filter(t => t === '?').length;
  if (unknownCount > 0) {
    exprResult.textContent = `${unknownCount} unrecognized mark(s) — train them in Settings, then rescan.`;
    exprVarsEl.innerHTML = '';
    showResultBanner(`Recognized ${rawTokens.length} marks, ${unknownCount} unrecognized.`);
    return;
  }

  const merged = mergeTokens(rawTokens);
  appState.lastMergedTokens = merged;
  const vars = [...new Set(merged.filter(t => /^\$[A-Z]$/.test(t)))];
  renderExprVars(vars);
  evaluateAndShow();
}

function renderExprVars(vars) {
  exprVarsEl.innerHTML = '';
  for (const v of vars) {
    if (!(v in appState.varValues)) appState.varValues[v] = 0;
    const label = document.createElement('label');
    label.innerHTML = `<span>${v}</span>`;
    const input = document.createElement('input');
    input.type = 'number';
    input.value = String(appState.varValues[v]);
    input.addEventListener('input', () => {
      appState.varValues[v] = Number(input.value) || 0;
      evaluateAndShow();
    });
    label.appendChild(input);
    exprVarsEl.appendChild(label);
  }
}

function evaluateAndShow() {
  try {
    const r = evalWithEquals(appState.lastMergedTokens, appState.varValues);
    if ('equal' in r) {
      exprResult.textContent = `${formatNum(r.lhs)} ${r.equal ? '==' : '!='} ${formatNum(r.rhs)}`;
    } else {
      exprResult.textContent = `= ${formatNum(r.value)}`;
    }
  } catch (err) {
    exprResult.textContent = `⚠ ${err.message}`;
  }
}

/* ---------------------------------------------------------------------- *
 * Training
 * ---------------------------------------------------------------------- */

function captureTrainingSample(symbol) {
  if (video.readyState < 2) { showResultBanner('Camera not ready.'); return; }
  const { w, h, groups, binary } = scanFromSource(video, video.videoWidth, video.videoHeight);
  if (!groups.length) { showResultBanner('No mark detected — make sure the symbol fills most of the frame.'); return; }
  const g = groups.slice().sort((a, b) => b.count - a.count)[0];
  const grid = extractGroupGrid(binary, w, h, g, GRID_N);
  const templates = loadTemplates(appState.mode);
  if (!templates[symbol]) templates[symbol] = [];
  templates[symbol].push(Array.from(grid));
  if (templates[symbol].length > MAX_SAMPLES_PER_SYMBOL) templates[symbol].shift();
  saveTemplates(appState.mode, templates);
  renderTrainGrid();
  renderLegend();
  showResultBanner(`Captured "${symbol}" sample (${templates[symbol].length}/${MAX_SAMPLES_PER_SYMBOL}).`);
}

function renderTrainGrid() {
  trainGrid.innerHTML = '';
  if (appState.mode === 'simple') {
    const p = document.createElement('p');
    p.className = 'hint';
    p.textContent = 'Simple mode recognizes − and | automatically by shape — no training needed.';
    trainGrid.appendChild(p);
    return;
  }
  const alphabet = currentAlphabetForMode();
  const templates = loadTemplates(appState.mode);
  for (const sym of alphabet) {
    const count = (templates[sym] || []).length;
    const tile = document.createElement('div');
    tile.className = 'train-tile' + (count > 0 ? ' has-samples' : '');
    tile.innerHTML = `<span>${sym}</span>${count > 0 ? `<span class="count">${count}</span>` : ''}`;
    tile.title = `Hold up "${sym}" to the camera, then tap to capture`;
    tile.addEventListener('click', () => captureTrainingSample(sym));
    trainGrid.appendChild(tile);
  }
}

function renderLegend() {
  legendEl.innerHTML = '';
  if (appState.mode === 'simple') {
    const chips = [['−', '0'], ['|', '1']];
    for (const [glyph, val] of chips) {
      const chip = document.createElement('div');
      chip.className = 'legend-chip trained';
      chip.innerHTML = `<span class="glyph">${glyph}</span><span>= ${val}</span>`;
      legendEl.appendChild(chip);
    }
    return;
  }
  const alphabet = currentAlphabetForMode();
  const templates = loadTemplates(appState.mode);
  for (const sym of alphabet) {
    const count = (templates[sym] || []).length;
    const chip = document.createElement('div');
    chip.className = 'legend-chip ' + (count > 0 ? 'trained' : 'untrained');
    chip.innerHTML = `<span class="glyph">${sym}</span><span>${count}</span>`;
    chip.addEventListener('click', () => settingsPanel.classList.remove('hidden'));
    legendEl.appendChild(chip);
  }
}

/* ---------------------------------------------------------------------- *
 * Result banner
 * ---------------------------------------------------------------------- */

let bannerTimer = null;
function showResultBanner(text, ms = 3200) {
  resultBanner.textContent = text;
  resultBanner.classList.remove('hidden');
  if (bannerTimer) clearTimeout(bannerTimer);
  bannerTimer = setTimeout(() => resultBanner.classList.add('hidden'), ms);
}

/* ---------------------------------------------------------------------- *
 * Scan / freeze flow
 * ---------------------------------------------------------------------- */

function freezeFrame(w, h) {
  if (!appState.frozenCanvas) appState.frozenCanvas = document.createElement('canvas');
  appState.frozenCanvas.width = w;
  appState.frozenCanvas.height = h;
  appState.frozenCanvas.getContext('2d').drawImage(workCanvas, 0, 0);
  appState.frozen = true;
  scanBtn.classList.add('hidden');
  liveBtn.classList.remove('hidden');
}

function processScan(sourceEl, sw, sh) {
  const { w, h, groups, binary } = scanFromSource(sourceEl, sw, sh);
  appState.lastBinary = binary;
  appState.lastWorkW = w;
  appState.lastWorkH = h;
  freezeFrame(w, h);

  if (!groups.length) {
    showResultBanner('No marks detected — check lighting and try again.');
    return;
  }
  if (appState.mode === 'simple') {
    appState.lastGroups = null;
    buildTapeFromGroups(groups);
  } else {
    processExpressionGroups(groups);
  }
}

async function handleScan() {
  if (video.readyState < 2) { showResultBanner('Camera not ready yet.'); return; }
  processScan(video, video.videoWidth, video.videoHeight);
}

function handleUpload(file) {
  const img = new Image();
  const url = URL.createObjectURL(file);
  img.onload = () => {
    processScan(img, img.naturalWidth, img.naturalHeight);
    URL.revokeObjectURL(url);
  };
  img.src = url;
}

function goLive() {
  appState.frozen = false;
  appState.frozenCanvas = null;
  appState.lastGroups = null;
  scanBtn.classList.remove('hidden');
  liveBtn.classList.add('hidden');
}

/* ---------------------------------------------------------------------- *
 * Mode switching
 * ---------------------------------------------------------------------- */

function setMode(mode) {
  appState.mode = mode;
  localStorage.setItem('td_mode', mode);
  goLive();
  resultBanner.classList.add('hidden');
  tapePanel.classList.toggle('hidden', mode !== 'simple');
  exprPanel.classList.add('hidden');
  customAlphabetSection.style.display = mode === 'custom' ? '' : 'none';
  if (mode === 'custom') customAlphabetInput.value = localStorage.getItem('td_custom_alphabet') || '';
  renderLegend();
  renderTrainGrid();
  if (!localStorage.getItem(`td_tutorial_seen_${mode}`)) showTutorial(mode);
}

/* ---------------------------------------------------------------------- *
 * Tutorial
 * ---------------------------------------------------------------------- */

function showTutorial(mode) {
  appState.tutorialMode = mode;
  appState.tutorialStep = 0;
  tutorialCard.classList.remove('hidden');
  renderTutorialStep();
}

function renderTutorialStep() {
  const steps = TUTORIALS[appState.tutorialMode];
  tutorialStepLabel.textContent = `Step ${appState.tutorialStep + 1} of ${steps.length}`;
  tutorialBody.innerHTML = steps[appState.tutorialStep];
  tutorialBack.disabled = appState.tutorialStep === 0;
  tutorialNext.textContent = appState.tutorialStep === steps.length - 1 ? "Let's go!" : 'Next';
}

function dismissTutorial() {
  tutorialCard.classList.add('hidden');
  localStorage.setItem(`td_tutorial_seen_${appState.tutorialMode}`, '1');
}

/* ---------------------------------------------------------------------- *
 * Rendering loop
 * ---------------------------------------------------------------------- */

function resizeCanvasIfNeeded() {
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  const targetW = Math.round(window.innerWidth * dpr);
  const targetH = Math.round(window.innerHeight * dpr);
  if (stage.width !== targetW || stage.height !== targetH) {
    stage.width = targetW;
    stage.height = targetH;
  }
}

function drawCover(ctx, media, mw, mh, W, H) {
  const scale = Math.max(W / mw, H / mh);
  const dw = mw * scale, dh = mh * scale;
  const dx = (W - dw) / 2, dy = (H - dh) / 2;
  ctx.drawImage(media, dx, dy, dw, dh);
}

function drawLiveGuide(ctx, W, H) {
  const bw = W * 0.7, bh = H * 0.4;
  const bx = (W - bw) / 2, by = (H - bh) / 2;
  const bracket = Math.min(bw, bh) * 0.12;
  ctx.save();
  ctx.strokeStyle = 'rgba(94, 234, 212, 0.85)';
  ctx.lineWidth = 3;
  ctx.lineCap = 'round';
  const corners = [
    [bx, by, 1, 1], [bx + bw, by, -1, 1],
    [bx, by + bh, 1, -1], [bx + bw, by + bh, -1, -1]
  ];
  for (const [x, y, dx, dy] of corners) {
    ctx.beginPath();
    ctx.moveTo(x, y + bracket * dy);
    ctx.lineTo(x, y);
    ctx.lineTo(x + bracket * dx, y);
    ctx.stroke();
  }
  ctx.restore();
}

function drawGroupsOverlay(ctx, W, H) {
  if (!appState.frozenCanvas) return;
  const sx = W / appState.frozenCanvas.width;
  const sy = H / appState.frozenCanvas.height;
  const list = appState.mode === 'simple' ? appState.groupsForTape : appState.lastGroups;
  if (!list) return;
  list.forEach((g, i) => {
    if (!g) return;
    const x = g.minX * sx, y = g.minY * sy;
    const w = (g.maxX - g.minX) * sx, h = (g.maxY - g.minY) * sy;
    const isHead = appState.mode === 'simple' && appState.tm &&
      appState.tm.state !== 'idle' && appState.tm.head === i;
    ctx.strokeStyle = isHead ? '#5eead4' : 'rgba(255,255,255,0.55)';
    ctx.lineWidth = isHead ? 3 : 1.5;
    ctx.strokeRect(x - 4, y - 4, w + 8, h + 8);
    if (appState.mode !== 'simple' && g.symbol) {
      ctx.font = '600 15px sans-serif';
      const label = g.symbol;
      const tw = ctx.measureText(label).width;
      ctx.fillStyle = 'rgba(0,0,0,0.6)';
      ctx.fillRect(x - 4, y - 26, tw + 12, 20);
      ctx.fillStyle = g.symbol === '?' ? '#f87171' : '#5eead4';
      ctx.fillText(label, x + 2, y - 11);
    }
  });
}

function draw() {
  resizeCanvasIfNeeded();
  const W = stage.width, H = stage.height;

  stageCtx.save();
  if (appState.mirror && !appState.frozen) {
    stageCtx.translate(W, 0);
    stageCtx.scale(-1, 1);
  }
  if (appState.frozen && appState.frozenCanvas) {
    stageCtx.drawImage(appState.frozenCanvas, 0, 0, W, H);
  } else if (video.readyState >= 2 && video.videoWidth) {
    drawCover(stageCtx, video, video.videoWidth, video.videoHeight, W, H);
  } else {
    stageCtx.fillStyle = '#000';
    stageCtx.fillRect(0, 0, W, H);
  }
  stageCtx.restore();

  if (appState.frozen) drawGroupsOverlay(stageCtx, W, H);
  else drawLiveGuide(stageCtx, W, H);

  requestAnimationFrame(draw);
}

/* ---------------------------------------------------------------------- *
 * Event wiring
 * ---------------------------------------------------------------------- */

modeSelect.addEventListener('change', () => setMode(modeSelect.value));

settingsBtn.addEventListener('click', () => {
  renderTrainGrid();
  settingsPanel.classList.remove('hidden');
});
closeSettings.addEventListener('click', () => settingsPanel.classList.add('hidden'));

helpBtn.addEventListener('click', () => showTutorial(appState.mode));
tutorialNext.addEventListener('click', () => {
  const steps = TUTORIALS[appState.tutorialMode];
  if (appState.tutorialStep >= steps.length - 1) { dismissTutorial(); return; }
  appState.tutorialStep++;
  renderTutorialStep();
});
tutorialBack.addEventListener('click', () => {
  if (appState.tutorialStep > 0) { appState.tutorialStep--; renderTutorialStep(); }
});
tutorialSkip.addEventListener('click', dismissTutorial);

applyCustomAlphabet.addEventListener('click', () => {
  const list = parseCustomAlphabet(customAlphabetInput.value);
  localStorage.setItem('td_custom_alphabet', list.join(','));
  if (appState.mode === 'custom') { renderLegend(); renderTrainGrid(); }
  showResultBanner(`Custom alphabet set (${list.length} symbols).`);
});

clearTrainingBtn.addEventListener('click', () => {
  if (appState.mode === 'simple') return;
  if (!confirm('Clear all trained samples for this mode?')) return;
  saveTemplates(appState.mode, {});
  renderTrainGrid();
  renderLegend();
});

thresholdBias.addEventListener('input', () => {
  appState.thresholdBias = Number(thresholdBias.value);
  saveSettings();
});
mirrorToggle.addEventListener('change', () => {
  appState.mirror = mirrorToggle.checked;
  saveSettings();
});
flipCameraBtn.addEventListener('click', () => {
  appState.facingMode = appState.facingMode === 'environment' ? 'user' : 'environment';
  saveSettings();
  startCamera(appState.facingMode);
});

tapeAddZero.addEventListener('click', () => {
  appState.tape.push({ value: 0 });
  appState.groupsForTape.push(null);
  appState.tm = null;
  captureSnapshot();
  renderTape();
});
tapeAddOne.addEventListener('click', () => {
  appState.tape.push({ value: 1 });
  appState.groupsForTape.push(null);
  appState.tm = null;
  captureSnapshot();
  renderTape();
});
tapeRemove.addEventListener('click', () => {
  if (!appState.tape.length) return;
  appState.tape.pop();
  appState.groupsForTape.pop();
  appState.tm = null;
  captureSnapshot();
  renderTape();
});
tapeClear.addEventListener('click', () => {
  appState.tape = [];
  appState.groupsForTape = [];
  appState.tm = null;
  appState.snapshot = [];
  renderTape();
  resultBanner.classList.add('hidden');
});
tapeReset.addEventListener('click', () => {
  if (appState.tm && appState.tm.timer) clearInterval(appState.tm.timer);
  appState.tape = appState.snapshot.map(c => ({ ...c }));
  appState.tm = null;
  renderTape();
});
tapeStep.addEventListener('click', stepTM);
tapeRun.addEventListener('click', runTM);

scanBtn.addEventListener('click', handleScan);
liveBtn.addEventListener('click', goLive);
uploadBtn.addEventListener('click', () => uploadInput.click());
uploadInput.addEventListener('change', () => {
  const file = uploadInput.files && uploadInput.files[0];
  if (file) handleUpload(file);
  uploadInput.value = '';
});

window.addEventListener('resize', resizeCanvasIfNeeded);
window.addEventListener('orientationchange', resizeCanvasIfNeeded);

/* ---------------------------------------------------------------------- *
 * Init
 * ---------------------------------------------------------------------- */

function init() {
  loadSettings();
  thresholdBias.value = String(appState.thresholdBias);
  mirrorToggle.checked = appState.mirror;

  const savedMode = localStorage.getItem('td_mode') || 'simple';
  modeSelect.value = savedMode;
  setMode(savedMode);

  resizeCanvasIfNeeded();
  requestAnimationFrame(draw);
  startCamera(appState.facingMode);
}

init();
