#!/usr/bin/env node
'use strict';

// wlan-editor — a tiny LAN server that lets everyone on the same WiFi
// collaboratively edit one HTML page. Zero dependencies: plain node.
//
//   node server.js [--port 8080] [--file page.json] [--code 1234]

const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');

// ---------------------------------------------------------------- config

function parseArgs(argv) {
  const out = { port: Number(process.env.PORT) || 8080, file: path.join(__dirname, 'page.json'), code: process.env.ROOM_CODE || '' };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--help' || a === '-h') out.help = true;
    else if (a === '--port' || a === '-p') out.port = Number(argv[++i]);
    else if (a === '--file' || a === '-f') out.file = path.resolve(argv[++i]);
    else if (a === '--code' || a === '-c') out.code = String(argv[++i]);
    else { console.error(`unknown option: ${a}`); out.help = true; }
  }
  return out;
}

const ARGS = parseArgs(process.argv.slice(2));

if (ARGS.help || !Number.isInteger(ARGS.port)) {
  console.log(`wlan-editor — collaborative HTML editing over the local network

  node server.js [options]

  -p, --port <n>     port to listen on           (default 8080, or $PORT)
  -f, --file <path>  where the page is saved     (default ./page.json)
  -c, --code <str>   require a room code to join (default none, or $ROOM_CODE)
  -h, --help         show this
`);
  process.exit(ARGS.help ? 0 : 1);
}

const PUBLIC_DIR = path.join(__dirname, 'public');
const MAX_BODY = 4 * 1024 * 1024;       // 4 MB per request
const MAX_BLOCK = 256 * 1024;           // 256 KB of HTML per block
const MAX_BLOCKS = 2000;
const UNDO_DEPTH = 200;
const PALETTE = ['#e6194b', '#3cb44b', '#f58231', '#4363d8', '#911eb4', '#00998f',
                 '#f032e6', '#9a6324', '#0082c8', '#808000'];

// ---------------------------------------------------------------- state

const newId = () => crypto.randomUUID().slice(0, 8);

const SEED = {
  title: 'Our page',
  blocks: [
    { id: newId(), html: '<h1>Hello, everyone 👋</h1>' },
    { id: newId(), html: '<p>Anyone on this WiFi can type here. Click a paragraph and start editing — everybody sees it right away.</p>' },
    { id: newId(), html: '<p>Use the <b>&lt;/&gt;</b> button on a block to edit its raw HTML, or <b>Source</b> up top to rewrite the whole page.</p>' },
    { id: newId(), html: '<style>\n  body { font-family: Georgia, serif; }\n  h1 { color: #4363d8; }\n</style>' },
  ],
};

const doc = { title: SEED.title, blocks: SEED.blocks.map((b) => ({ ...b })), version: 0 };
const undoStack = [];

function loadFromDisk() {
  try {
    const raw = JSON.parse(fs.readFileSync(ARGS.file, 'utf8'));
    if (!Array.isArray(raw.blocks)) throw new Error('no blocks array');
    doc.title = typeof raw.title === 'string' ? raw.title : doc.title;
    doc.blocks = raw.blocks
      .filter((b) => b && typeof b.html === 'string')
      .map((b) => ({ id: typeof b.id === 'string' && b.id ? b.id : newId(), html: b.html }));
    if (!doc.blocks.length) doc.blocks = [{ id: newId(), html: '<p></p>' }];
    console.log(`loaded ${doc.blocks.length} blocks from ${ARGS.file}`);
  } catch (err) {
    if (err.code !== 'ENOENT') console.warn(`could not read ${ARGS.file}: ${err.message} — starting fresh`);
  }
}

let saveTimer = null;
let saving = false;
function scheduleSave() {
  if (saveTimer) return;
  saveTimer = setTimeout(() => { saveTimer = null; saveNow(); }, 800);
}
function saveNow(sync = false) {
  if (saving && !sync) return;
  const body = JSON.stringify({ title: doc.title, blocks: doc.blocks }, null, 2);
  const tmp = `${ARGS.file}.tmp`;
  if (sync) {
    try { fs.writeFileSync(tmp, body); fs.renameSync(tmp, ARGS.file); }
    catch (err) { console.error(`save failed: ${err.message}`); }
    return;
  }
  saving = true;
  fs.writeFile(tmp, body, (err) => {
    if (err) { saving = false; return console.error(`save failed: ${err.message}`); }
    fs.rename(tmp, ARGS.file, (err2) => {
      saving = false;
      if (err2) console.error(`save failed: ${err2.message}`);
    });
  });
}

// ---------------------------------------------------------------- clients

/** @type {Map<string, {id:string,res:http.ServerResponse,name:string,color:string,blockId:string|null,seen:number}>} */
const clients = new Map();
let colorCursor = 0;

function sse(client, event, data) {
  try {
    client.res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  } catch { drop(client.id); }
}

function broadcast(event, data, exceptId) {
  for (const c of clients.values()) if (c.id !== exceptId) sse(c, event, data);
}

function drop(id) {
  const c = clients.get(id);
  if (!c) return;
  clients.delete(id);
  try { c.res.end(); } catch {}
  scheduleRoster();
}

let rosterTimer = null;
function scheduleRoster() {
  if (rosterTimer) return;
  rosterTimer = setTimeout(() => { rosterTimer = null; broadcast('roster', rosterList()); }, 150);
}
function rosterList() {
  return [...clients.values()].map((c) => ({ id: c.id, name: c.name, color: c.color, blockId: c.blockId }));
}

function snapshot() {
  return { version: doc.version, title: doc.title, blocks: doc.blocks, canUndo: undoStack.length > 0 };
}

// ---------------------------------------------------------------- ops

function pushUndo() {
  undoStack.push({ title: doc.title, blocks: doc.blocks.map((b) => ({ ...b })) });
  if (undoStack.length > UNDO_DEPTH) undoStack.shift();
}

const indexOfBlock = (id) => doc.blocks.findIndex((b) => b.id === id);

function cleanBlocks(list) {
  if (!Array.isArray(list)) return null;
  const out = [];
  const seen = new Set();
  for (const b of list.slice(0, MAX_BLOCKS)) {
    if (!b || typeof b.html !== 'string' || b.html.length > MAX_BLOCK) continue;
    let id = typeof b.id === 'string' && b.id ? b.id : newId();
    while (seen.has(id)) id = newId();
    seen.add(id);
    out.push({ id, html: b.html });
  }
  return out.length ? out : [{ id: newId(), html: '<p></p>' }];
}

/**
 * Applies one op. Returns the op to broadcast (normalised), or an error string.
 * Merge model: last write wins, but scoped to a single block — two people
 * editing different blocks never clobber each other.
 */
function applyOp(op) {
  if (!op || typeof op.type !== 'string') return { error: 'bad op' };

  switch (op.type) {
    case 'set': {
      const i = indexOfBlock(op.id);
      if (i < 0) return { error: 'no such block' };
      if (typeof op.html !== 'string' || op.html.length > MAX_BLOCK) return { error: 'bad html' };
      if (doc.blocks[i].html === op.html) return { noop: true };
      pushUndo();
      doc.blocks[i] = { id: op.id, html: op.html };
      return { op: { type: 'set', id: op.id, html: op.html } };
    }
    case 'insert': {
      if (doc.blocks.length >= MAX_BLOCKS) return { error: 'too many blocks' };
      const html = typeof op.html === 'string' && op.html.length <= MAX_BLOCK ? op.html : '<p></p>';
      const id = newId();
      const at = op.afterId == null ? 0 : indexOfBlock(op.afterId) + 1;
      pushUndo();
      doc.blocks.splice(at < 0 ? doc.blocks.length : at, 0, { id, html });
      return { op: { type: 'insert', id, html, afterId: op.afterId ?? null } };
    }
    case 'delete': {
      const i = indexOfBlock(op.id);
      if (i < 0) return { error: 'no such block' };
      pushUndo();
      doc.blocks.splice(i, 1);
      if (!doc.blocks.length) doc.blocks.push({ id: newId(), html: '<p></p>' });
      return { op: { type: 'delete', id: op.id }, resync: true };
    }
    case 'move': {
      const i = indexOfBlock(op.id);
      if (i < 0) return { error: 'no such block' };
      const dir = op.dir === 'up' ? -1 : 1;
      const j = i + dir;
      if (j < 0 || j >= doc.blocks.length) return { noop: true };
      pushUndo();
      const [b] = doc.blocks.splice(i, 1);
      doc.blocks.splice(j, 0, b);
      return { op: { type: 'move', id: op.id, dir: dir < 0 ? 'up' : 'down' }, resync: true };
    }
    case 'replace': {
      const blocks = cleanBlocks(op.blocks);
      if (!blocks) return { error: 'bad blocks' };
      pushUndo();
      doc.blocks = blocks;
      if (typeof op.title === 'string') doc.title = op.title.slice(0, 200);
      return { resync: true };
    }
    case 'title': {
      if (typeof op.title !== 'string') return { error: 'bad title' };
      const title = op.title.slice(0, 200);
      if (title === doc.title) return { noop: true };
      pushUndo();
      doc.title = title;
      return { op: { type: 'title', title } };
    }
    case 'undo': {
      const prev = undoStack.pop();
      if (!prev) return { noop: true };
      doc.title = prev.title;
      doc.blocks = prev.blocks;
      return { resync: true };
    }
    default:
      return { error: `unknown op: ${op.type}` };
  }
}

function commit(op, fromId) {
  const result = applyOp(op);
  if (result.error || result.noop) return result;
  doc.version++;
  scheduleSave();
  if (result.resync) broadcast('sync', snapshot());
  else broadcast('op', { version: doc.version, from: fromId, op: result.op, canUndo: undoStack.length > 0 });
  if (!result.resync) {
    // keep the sender's undo affordance current too
    const self = clients.get(fromId);
    if (self) sse(self, 'meta', { canUndo: undoStack.length > 0 });
  }
  return result;
}

// ---------------------------------------------------------------- http

const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
               '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8',
               '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon' };

const escapeHtml = (s) => String(s).replace(/[&<>"']/g, (c) =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

function authorised(req, url) {
  if (!ARGS.code) return true;
  const given = req.headers['x-room-code'] || url.searchParams.get('code') || '';
  const a = Buffer.from(String(given));
  const b = Buffer.from(ARGS.code);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > MAX_BODY) { reject(new Error('body too large')); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => {
      try { resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {}); }
      catch (err) { reject(err); }
    });
    req.on('error', reject);
  });
}

function json(res, status, data) {
  const body = JSON.stringify(data);
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'content-length': Buffer.byteLength(body) });
  res.end(body);
}

function serveStatic(req, res, pathname) {
  const rel = pathname === '/' ? 'index.html' : pathname.replace(/^\/+/, '');
  const file = path.resolve(PUBLIC_DIR, rel);
  if (file !== PUBLIC_DIR && !file.startsWith(PUBLIC_DIR + path.sep)) return json(res, 403, { error: 'forbidden' });
  fs.readFile(file, (err, buf) => {
    if (err) return json(res, 404, { error: 'not found' });
    res.writeHead(200, { 'content-type': MIME[path.extname(file)] || 'application/octet-stream', 'cache-control': 'no-cache' });
    res.end(buf);
  });
}

const docHtml = () => doc.blocks.map((b) => b.html).join('\n');

function pageHtml() {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(doc.title)}</title>
</head>
<body>
${docHtml()}
</body>
</html>
`;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const p = url.pathname;

  if (p.startsWith('/api/') || p === '/preview' || p === '/export') {
    if (!authorised(req, url)) return json(res, 401, { error: 'room code required' });
  }

  // --- live stream -------------------------------------------------
  if (p === '/api/stream' && req.method === 'GET') {
    const id = newId();
    const name = (url.searchParams.get('name') || 'Guest').slice(0, 24);
    const color = PALETTE[colorCursor++ % PALETTE.length];
    res.writeHead(200, {
      'content-type': 'text/event-stream; charset=utf-8',
      'cache-control': 'no-cache, no-transform',
      connection: 'keep-alive',
      'x-accel-buffering': 'no',
    });
    const client = { id, res, name, color, blockId: null, seen: Date.now() };
    clients.set(id, client);
    req.socket.setNoDelay(true);
    sse(client, 'hello', { you: { id, name, color }, roster: rosterList(), ...snapshot() });
    scheduleRoster();
    req.on('close', () => drop(id));
    return;
  }

  if (p === '/api/op' && req.method === 'POST') {
    let body;
    try { body = await readBody(req); } catch (err) { return json(res, 400, { error: err.message }); }
    const from = typeof body.clientId === 'string' ? body.clientId : '';
    const ops = Array.isArray(body.ops) ? body.ops : [body.op];
    for (const op of ops) {
      const r = commit(op, from);
      if (r.error) return json(res, 400, { error: r.error, version: doc.version });
    }
    return json(res, 200, { version: doc.version });
  }

  if (p === '/api/presence' && req.method === 'POST') {
    let body;
    try { body = await readBody(req); } catch (err) { return json(res, 400, { error: err.message }); }
    const c = clients.get(body.clientId);
    if (!c) return json(res, 404, { error: 'unknown client — reconnect' });
    if (typeof body.name === 'string' && body.name.trim()) c.name = body.name.trim().slice(0, 24);
    c.blockId = typeof body.blockId === 'string' ? body.blockId : null;
    c.seen = Date.now();
    scheduleRoster();
    return json(res, 200, { ok: true });
  }

  if (p === '/api/state' && req.method === 'GET') return json(res, 200, snapshot());

  // --- plain page: styles AND scripts run here ---------------------
  if (p === '/preview') {
    const body = pageHtml();
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
    return res.end(body);
  }

  if (p === '/export') {
    const body = pageHtml();
    const safe = (doc.title || 'page').replace(/[^a-z0-9._-]+/gi, '-').replace(/^-+|-+$/g, '') || 'page';
    res.writeHead(200, {
      'content-type': 'text/html; charset=utf-8',
      'content-disposition': `attachment; filename="${safe}.html"`,
    });
    return res.end(body);
  }

  if (req.method !== 'GET') return json(res, 405, { error: 'method not allowed' });
  return serveStatic(req, res, p);
});

// keep proxies and sleepy phones from dropping the stream
setInterval(() => {
  for (const c of clients.values()) {
    try { c.res.write(': ping\n\n'); } catch { drop(c.id); }
  }
}, 20000).unref();

// ---------------------------------------------------------------- boot

function lanAddresses() {
  const out = [];
  for (const [iface, addrs] of Object.entries(os.networkInterfaces())) {
    for (const a of addrs || []) {
      if (a.family === 'IPv4' && !a.internal) out.push({ iface, address: a.address });
    }
  }
  return out;
}

loadFromDisk();

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`port ${ARGS.port} is already in use — try: node server.js --port ${ARGS.port + 1}`);
    process.exit(1);
  }
  throw err;
});

server.listen(ARGS.port, '0.0.0.0', () => {
  const suffix = ARGS.code ? `  (room code: ${ARGS.code})` : '';
  console.log(`\n  wlan-editor is up${suffix}`);
  console.log(`  saving to ${ARGS.file}\n`);
  console.log('  Tell people on this WiFi to open:');
  const lan = lanAddresses();
  if (!lan.length) console.log('    (no LAN address found — are you connected to WiFi?)');
  for (const { iface, address } of lan) console.log(`    http://${address}:${ARGS.port}   [${iface}]`);
  console.log(`\n  On this laptop:  http://localhost:${ARGS.port}\n`);
});

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => {
    console.log('\nsaving and shutting down…');
    saveNow(true);
    process.exit(0);
  });
}
