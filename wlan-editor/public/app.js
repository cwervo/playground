'use strict';

/* wlan-editor client.
 *
 * Merge model: the page is a list of blocks. Edits are scoped to one block,
 * and the last write to a block wins. Two people editing different blocks
 * never clobber each other; two people in the *same* block will fight, so we
 * show who is where (the coloured outline) to keep that rare. */

const $ = (sel) => document.querySelector(sel);
const pageEl = $('#page');
const rosterEl = $('#roster');
const bannerEl = $('#banner');
const dotEl = $('#conn-dot');
const titleEl = $('#title');
const undoBtn = $('#btn-undo');
const meBtn = $('#btn-me');
const sourcePane = $('#source-pane');
const sourceText = $('#source-text');

const LS_NAME = 'wlan-editor:name';
const LS_CODE = 'wlan-editor:code';

let me = { id: null, name: null, color: '#999' };
let blocks = [];                 // [{id, html}] — mirrors the server
let version = 0;
let roomCode = localStorage.getItem(LS_CODE) || '';
let stream = null;

const dirty = new Map();         // blockId -> html not yet acked/sent
const sourceOpen = new Set();    // blockIds currently open in per-block source view
let sendTimer = null;

// ------------------------------------------------------------ helpers

const qs = (params) => {
  const p = new URLSearchParams(params);
  if (roomCode) p.set('code', roomCode);
  const s = p.toString();
  return s ? `?${s}` : '';
};

async function api(path, body) {
  const res = await fetch(path, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(roomCode ? { 'x-room-code': roomCode } : {}) },
    body: JSON.stringify(body),
  });
  if (res.status === 401) { await askForCode(); throw new Error('room code'); }
  return res.json().catch(() => ({}));
}

const send = (op) => api('/api/op', { clientId: me.id, op }).catch(() => {});

function banner(text) {
  if (!text) { bannerEl.hidden = true; return; }
  bannerEl.textContent = text;
  bannerEl.hidden = false;
}

function defaultName() {
  const animals = ['Fox', 'Owl', 'Moth', 'Crow', 'Newt', 'Wren', 'Hare', 'Bee', 'Elk', 'Toad'];
  return animals[Math.floor(Math.random() * animals.length)] + '-' + Math.floor(Math.random() * 90 + 10);
}

// ------------------------------------------------------------ caret

/** Character offset of the caret within `root`, or null if it isn't in there. */
function caretOffset(root) {
  const sel = window.getSelection();
  if (!sel || !sel.rangeCount) return null;
  const range = sel.getRangeAt(0);
  if (!root.contains(range.endContainer)) return null;
  const pre = range.cloneRange();
  pre.selectNodeContents(root);
  pre.setEnd(range.endContainer, range.endOffset);
  return pre.toString().length;
}

function setCaret(root, offset) {
  if (offset == null) return;
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  let seen = 0;
  let node = null;
  let into = 0;
  let n;
  while ((n = walker.nextNode())) {
    const len = n.nodeValue.length;
    if (seen + len >= offset) { node = n; into = offset - seen; break; }
    seen += len;
  }
  const range = document.createRange();
  if (node) range.setStart(node, Math.min(into, node.nodeValue.length));
  else { range.selectNodeContents(root); range.collapse(false); }
  range.collapse(true);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);
}

// ------------------------------------------------------------ rendering

const holderFor = (id) => pageEl.querySelector(`.holder[data-id="${CSS.escape(id)}"]`);

const TOOLS = `
  <div class="tools">
    <button data-act="src"  title="Edit this block's HTML">&lt;/&gt;</button>
    <button data-act="up"   title="Move up">↑</button>
    <button data-act="down" title="Move down">↓</button>
    <button data-act="add"  title="Add a block below">+</button>
    <button data-act="del"  title="Delete this block" class="danger">✕</button>
  </div>`;

/** Content that renders to nothing (a bare <style>, <script>, <meta>…) gets a
 *  clickable chip so it doesn't look like an empty hole in the page. */
function paintBlock(blockEl, html) {
  blockEl.innerHTML = html;
  const hidden = blockEl.querySelector('style, script, link, meta, title');
  // A <style> element's textContent is its CSS, which renders nothing — strip the
  // non-rendering elements before asking whether anything is left to see.
  let invisible = false;
  if (hidden) {
    const probe = blockEl.cloneNode(true);
    for (const n of probe.querySelectorAll('style, script, link, meta, title')) n.remove();
    invisible = !probe.textContent.trim() &&
      !probe.querySelector('img, video, canvas, svg, hr, iframe, input, br, table');
  }

  if (invisible) {
    blockEl.contentEditable = 'false';
    blockEl.classList.add('chip');
    const tag = document.createElement('span');
    tag.className = 'chip-label';
    tag.textContent = `<${hidden.tagName.toLowerCase()}> — click to edit`;
    blockEl.append(tag);            // the real element stays in the DOM, so <style> still applies
  } else {
    blockEl.contentEditable = 'true';
    blockEl.classList.remove('chip');
  }
}

function makeHolder(block) {
  const holder = document.createElement('div');
  holder.className = 'holder';
  holder.dataset.id = block.id;
  holder.innerHTML = TOOLS;
  const el = document.createElement('div');
  el.className = 'block';
  el.spellcheck = false;
  paintBlock(el, block.html);
  holder.append(el);
  return holder;
}

function renderAll() {
  const active = document.activeElement;
  const focusedId = active && active.classList.contains('block')
    ? active.closest('.holder').dataset.id : null;
  const offset = focusedId ? caretOffset(active) : null;

  pageEl.replaceChildren(...blocks.map(makeHolder));

  if (focusedId) {
    const el = holderFor(focusedId)?.querySelector('.block');
    if (el && el.isContentEditable) { el.focus(); setCaret(el, offset); }
  }
  paintRoster(lastRoster);
}

function applyRemoteSet(id, html) {
  const holder = holderFor(id);
  if (!holder) return;
  if (sourceOpen.has(id) || dirty.has(id)) return;   // don't stomp on what someone here is typing
  const el = holder.querySelector('.block');
  const focused = document.activeElement === el;
  const offset = focused ? caretOffset(el) : null;
  paintBlock(el, html);
  if (focused && el.isContentEditable) setCaret(el, offset);
  holder.classList.remove('flash');
  void holder.offsetWidth;
  holder.classList.add('flash');
}

// ------------------------------------------------------------ sending edits

function queueSet(el) {
  const id = el.closest('.holder').dataset.id;
  dirty.set(id, el.innerHTML);
  if (sendTimer) return;
  sendTimer = setTimeout(flush, 220);
}

function flush() {
  clearTimeout(sendTimer);
  sendTimer = null;
  if (!dirty.size || !me.id) return;
  const ops = [...dirty].map(([id, html]) => ({ type: 'set', id, html }));
  for (const [id, html] of dirty) {
    const b = blocks.find((x) => x.id === id);
    if (b) b.html = html;
  }
  dirty.clear();
  api('/api/op', { clientId: me.id, ops }).catch(() => {});
}

// ------------------------------------------------------------ per-block source

function openBlockSource(id) {
  const holder = holderFor(id);
  const block = blocks.find((b) => b.id === id);
  if (!holder || !block || sourceOpen.has(id)) return;
  flush();
  sourceOpen.add(id);

  const el = holder.querySelector('.block');
  el.hidden = true;

  const wrap = document.createElement('div');
  wrap.className = 'block-editing';
  const ta = document.createElement('textarea');
  ta.className = 'block-source';
  ta.spellcheck = false;
  ta.value = block.html;
  const actions = document.createElement('div');
  actions.className = 'source-actions';
  actions.innerHTML = '<button class="btn primary" data-act="save">Save</button><button class="btn" data-act="cancel">Cancel</button>';
  wrap.append(ta, actions);
  holder.append(wrap);
  ta.focus();
  ta.setSelectionRange(ta.value.length, ta.value.length);
  ta.style.height = Math.min(ta.scrollHeight + 8, 480) + 'px';

  const close = (save) => {
    sourceOpen.delete(id);
    wrap.remove();
    el.hidden = false;
    if (save) {
      const html = ta.value;
      block.html = html;
      paintBlock(el, html);
      send({ type: 'set', id, html });
    } else {
      paintBlock(el, block.html);
    }
  };

  actions.addEventListener('click', (e) => {
    const act = e.target.dataset.act;
    if (act) close(act === 'save');
  });
  ta.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') { e.preventDefault(); close(false); }
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) { e.preventDefault(); close(true); }
  });
}

// ------------------------------------------------------------ whole-page source

function htmlToBlocks(text) {
  const tpl = document.createElement('template');
  tpl.innerHTML = text;
  const out = [];
  for (const node of tpl.content.childNodes) {
    if (node.nodeType === Node.ELEMENT_NODE) out.push(node.outerHTML);
    else if (node.nodeType === Node.COMMENT_NODE) out.push(`<!--${node.nodeValue}-->`);
    else if (node.nodeType === Node.TEXT_NODE && node.nodeValue.trim()) out.push(node.nodeValue.trim());
  }
  if (!out.length) out.push('<p></p>');
  // Reuse ids positionally so people's cursors and presence survive an apply.
  return out.map((html, i) => ({ id: blocks[i]?.id, html }));
}

function openSourcePane() {
  flush();
  sourceText.value = blocks.map((b) => b.html).join('\n\n');
  sourcePane.hidden = false;
  sourceText.focus();
}

$('#btn-source').addEventListener('click', openSourcePane);
$('#source-cancel').addEventListener('click', () => { sourcePane.hidden = true; });
$('#source-apply').addEventListener('click', () => {
  send({ type: 'replace', blocks: htmlToBlocks(sourceText.value) });
  sourcePane.hidden = true;
});
sourceText.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') sourcePane.hidden = true;
  if (e.key === 'Tab') {
    e.preventDefault();
    const { selectionStart: s, selectionEnd: t } = sourceText;
    sourceText.setRangeText('  ', s, t, 'end');
  }
});

// ------------------------------------------------------------ page events

pageEl.addEventListener('input', (e) => {
  const el = e.target.closest('.block');
  if (el && el.isContentEditable) queueSet(el);
});

pageEl.addEventListener('focusin', (e) => {
  const el = e.target.closest('.block');
  if (el) sendPresence(el.closest('.holder').dataset.id);
});

pageEl.addEventListener('focusout', (e) => {
  if (e.target.closest('.block')) { flush(); sendPresence(null); }
});

// Paste as plain text: pasting a chunk of someone's styled document into a
// page you're all writing together is never what anyone meant.
pageEl.addEventListener('paste', (e) => {
  const el = e.target.closest('.block');
  if (!el || !el.isContentEditable) return;
  e.preventDefault();
  const text = (e.clipboardData || window.clipboardData).getData('text/plain');
  document.execCommand('insertText', false, text);
});

pageEl.addEventListener('keydown', (e) => {
  const holder = e.target.closest('.holder');
  if (!holder) return;
  if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
    e.preventDefault();
    flush();
    send({ type: 'insert', afterId: holder.dataset.id, html: '<p></p>' });
  }
  if (e.key === 's' && (e.metaKey || e.ctrlKey)) {
    e.preventDefault();
    flush();
    banner('Nothing to save — everything is saved on the host laptop as you type. Use “Save file” to download a copy.');
    setTimeout(() => banner(''), 4000);
  }
});

pageEl.addEventListener('click', (e) => {
  const chip = e.target.closest('.block.chip');
  if (chip) return openBlockSource(chip.closest('.holder').dataset.id);

  const btn = e.target.closest('.tools button');
  if (!btn) return;
  const id = btn.closest('.holder').dataset.id;
  flush();
  switch (btn.dataset.act) {
    case 'src': return openBlockSource(id);
    case 'up': return send({ type: 'move', id, dir: 'up' });
    case 'down': return send({ type: 'move', id, dir: 'down' });
    case 'add': return send({ type: 'insert', afterId: id, html: '<p></p>' });
    case 'del': return send({ type: 'delete', id });
  }
});

$('#add-end').addEventListener('click', () => {
  flush();
  send({ type: 'insert', afterId: blocks.length ? blocks[blocks.length - 1].id : null, html: '<p></p>' });
});

undoBtn.addEventListener('click', () => send({ type: 'undo' }));

let titleTimer = null;
titleEl.addEventListener('input', () => {
  clearTimeout(titleTimer);
  titleTimer = setTimeout(() => send({ type: 'title', title: titleEl.value }), 300);
});

meBtn.addEventListener('click', () => {
  const next = prompt('What should everyone call you?', me.name);
  if (!next || !next.trim()) return;
  me.name = next.trim().slice(0, 24);
  localStorage.setItem(LS_NAME, me.name);
  meBtn.textContent = me.name;
  sendPresence(currentBlockId);
});

window.addEventListener('beforeunload', flush);

// ------------------------------------------------------------ presence

let currentBlockId = null;
function sendPresence(blockId) {
  currentBlockId = blockId;
  if (!me.id) return;
  api('/api/presence', { clientId: me.id, name: me.name, blockId }).catch(() => {});
}
setInterval(() => { if (me.id) sendPresence(currentBlockId); }, 8000);

let lastRoster = [];
function paintRoster(list) {
  lastRoster = list || [];
  const mine = lastRoster.find((p) => p.id === me.id);
  const others = lastRoster.filter((p) => p.id !== me.id);
  const ordered = mine ? [mine, ...others] : others;

  rosterEl.replaceChildren(...ordered.map((p) => {
    const chip = document.createElement('span');
    chip.className = 'who' + (p.blockId ? ' typing' : '');
    chip.style.color = p.color;
    chip.innerHTML = `<i style="background:${p.color}"></i>`;
    chip.append(p.id === me.id ? `${p.name} (you)` : p.name);
    return chip;
  }));

  for (const holder of pageEl.querySelectorAll('.holder')) {
    holder.classList.remove('remote');
    holder.removeAttribute('data-remote-name');
    holder.style.removeProperty('--remote');
  }
  for (const p of others) {
    if (!p.blockId) continue;
    const holder = holderFor(p.blockId);
    if (!holder) continue;
    holder.classList.add('remote');
    holder.dataset.remoteName = p.name;
    holder.style.setProperty('--remote', p.color);
  }
}

// ------------------------------------------------------------ stream

function setTitleValue(t) {
  if (document.activeElement !== titleEl) titleEl.value = t;
  document.title = t || 'Shared page';
}

function adopt(snap) {
  version = snap.version;
  blocks = snap.blocks.map((b) => ({ ...b }));
  setTitleValue(snap.title);
  undoBtn.disabled = !snap.canUndo;
  renderAll();
}

function connect() {
  if (stream) stream.close();
  stream = new EventSource(`/api/stream${qs({ name: me.name })}`);

  stream.addEventListener('open', () => { dotEl.className = 'dot live'; dotEl.title = 'connected'; });

  stream.addEventListener('hello', (e) => {
    const data = JSON.parse(e.data);
    me.id = data.you.id;
    me.color = data.you.color;
    document.documentElement.style.setProperty('--me-color', me.color);
    meBtn.textContent = me.name;
    banner('');
    dotEl.className = 'dot live';
    adopt(data);
    paintRoster(data.roster || []);
    sendPresence(currentBlockId);
  });

  stream.addEventListener('sync', (e) => adopt(JSON.parse(e.data)));

  stream.addEventListener('roster', (e) => paintRoster(JSON.parse(e.data)));

  stream.addEventListener('meta', (e) => { undoBtn.disabled = !JSON.parse(e.data).canUndo; });

  stream.addEventListener('op', (e) => {
    const { version: v, from, op, canUndo } = JSON.parse(e.data);
    version = v;
    undoBtn.disabled = !canUndo;
    if (!op) return;

    switch (op.type) {
      case 'set': {
        const b = blocks.find((x) => x.id === op.id);
        if (b) b.html = op.html;
        if (from !== me.id) applyRemoteSet(op.id, op.html);
        break;
      }
      case 'insert': {
        const at = op.afterId == null ? 0 : blocks.findIndex((b) => b.id === op.afterId) + 1;
        const index = at < 0 ? blocks.length : at;
        blocks.splice(index, 0, { id: op.id, html: op.html });
        const holder = makeHolder({ id: op.id, html: op.html });
        const before = pageEl.children[index];
        before ? pageEl.insertBefore(holder, before) : pageEl.append(holder);
        if (from === me.id) {
          const el = holder.querySelector('.block');
          el.focus();
          setCaret(el, 0);
          sendPresence(op.id);
        }
        break;
      }
      case 'title':
        setTitleValue(op.title);
        break;
    }
  });

  stream.addEventListener('error', () => {
    dotEl.className = 'dot lost';
    dotEl.title = 'disconnected';
    banner('Lost the connection to the host laptop — trying again. Your latest edits are safe here until it comes back.');
  });
}

// ------------------------------------------------------------ boot

async function askForCode() {
  const given = prompt('This page needs a room code (ask whoever is hosting):', '');
  if (given == null) return false;
  roomCode = given.trim();
  localStorage.setItem(LS_CODE, roomCode);
  return true;
}

async function start() {
  me.name = localStorage.getItem(LS_NAME) || defaultName();
  localStorage.setItem(LS_NAME, me.name);
  meBtn.textContent = me.name;

  for (let tries = 0; tries < 5; tries++) {
    const res = await fetch(`/api/state${qs({})}`, {
      headers: roomCode ? { 'x-room-code': roomCode } : {},
    }).catch(() => null);
    if (res && res.ok) { connect(); return; }
    if (res && res.status === 401) { if (!(await askForCode())) break; continue; }
    banner('Cannot reach the host laptop. Is it still on this WiFi?');
    await new Promise((r) => setTimeout(r, 1500));
  }
  banner('Could not join. Reload the page to try again.');
}

start();
