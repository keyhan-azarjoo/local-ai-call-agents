/// The website every user-built app gets. One small page that reads the app's
/// description (/api/_spec) and draws it: customer pages at `/`, the manager at `/manage`.
library;

String appHtml(String title, String theme, {bool dark = false, String font = 'sans'}) => '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${_esc(title)}</title><style>:root{--accent:$theme;--font:${_fonts[font] ?? _fonts['sans']}}</style><link rel="stylesheet" href="/app.css"></head>
<body${dark ? ' class="dark"' : ''}><header><a class="brand" href="/">${_esc(title)}</a><nav id="nav"></nav></header><main id="main"><p class="muted">Loading…</p></main>
<footer>Made with LocalAILine</footer><script src="/app.js"></script></body></html>''';

String pausedHtml(String title) => '''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${_esc(title)}</title><link rel="stylesheet" href="/app.css"></head><body><main><div class="card center"><h2>${_esc(title)}</h2>
<p class="muted">This app is paused right now. Please try again later.</p></div></main></body></html>''';

const _fonts = {
  'sans': '-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif',
  'serif': 'Georgia,"Times New Roman",serif',
  'rounded': 'ui-rounded,"SF Pro Rounded","Nunito","Varela Round",-apple-system,sans-serif',
};

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

const appCss = r'''
*{box-sizing:border-box}body{margin:0;font:15px/1.5 var(--font,sans-serif);color:#1d2433;background:#f5f7fa}
header{display:flex;flex-wrap:wrap;align-items:center;gap:16px;padding:14px 24px;background:#fff;border-bottom:1px solid #e3e8ef;position:sticky;top:0;z-index:5}
.brand{font-weight:700;font-size:18px;color:var(--accent);text-decoration:none;margin-right:auto}
nav a{color:#475467;text-decoration:none;padding:6px 10px;border-radius:6px;font-size:14px}nav a.on,nav a:hover{background:#eef2f7;color:#1d2433}
main{max-width:1040px;margin:0 auto;padding:24px}footer{text-align:center;color:#98a2b3;font-size:12px;padding:24px}
h1,h2,h3{line-height:1.25;margin:0 0 10px}h2{font-size:22px}h3{font-size:17px}
.block{margin-bottom:28px}.muted{color:#667085}.card{background:#fff;border:1px solid #e3e8ef;border-radius:10px;padding:16px}
.center{text-align:center;max-width:420px;margin:60px auto}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:14px}
.card .t{font-weight:600;font-size:16px;margin-bottom:4px}.kv{font-size:13.5px;color:#475467}.kv b{color:#1d2433;font-weight:500}
.price{font-weight:600;color:var(--accent)}
input,select,textarea{width:100%;padding:9px 11px;border:1px solid #cfd6e0;border-radius:7px;font:inherit;background:#fff}
textarea{min-height:80px}label{display:block;font-size:13px;font-weight:500;margin:10px 0 4px}
button{font:inherit;border:1px solid #cfd6e0;background:#fff;border-radius:7px;padding:7px 14px;cursor:pointer}
button.primary{background:var(--accent);border-color:var(--accent);color:#fff}button.danger{color:#c4320a}
button:disabled{opacity:.5;cursor:default}.row{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
.search{margin-bottom:14px;max-width:360px}.ok{background:#e7f6ee;color:#05603a;padding:10px 14px;border-radius:8px;margin-top:12px}
.err{background:#fdecea;color:#b42318;padding:10px 14px;border-radius:8px;margin-top:12px}
.picks{border:1px solid #e3e8ef;border-radius:8px;max-height:280px;overflow:auto;background:#fff}
.pick{display:flex;align-items:center;gap:10px;padding:7px 10px;border-bottom:1px solid #f0f2f5}.pick:last-child{border:0}
.pick span{flex:1}.qty{display:flex;align-items:center;gap:6px}.qty button{padding:2px 9px}
table{width:100%;border-collapse:collapse;background:#fff;border:1px solid #e3e8ef;border-radius:10px;overflow:hidden;font-size:14px}
th,td{text-align:left;padding:9px 12px;border-bottom:1px solid #eef1f5;vertical-align:top}th{background:#f8fafc;font-weight:600;font-size:13px;color:#475467}
.tabs{display:flex;gap:6px;flex-wrap:wrap;margin-bottom:18px}.tabs button.on{background:#1d2433;color:#fff;border-color:#1d2433}
.modal{position:fixed;inset:0;background:rgba(16,24,40,.45);display:flex;align-items:flex-start;justify-content:center;padding:40px 16px;overflow:auto;z-index:9}
.modal .card{width:100%;max-width:560px}
body.dark{background:#111418;color:#e6e9ef}body.dark header,body.dark .card,body.dark table,body.dark .picks,body.dark input,body.dark select,body.dark textarea,body.dark button{background:#1a1e24;color:#e6e9ef;border-color:#2c323b}
body.dark th{background:#20252c;color:#aab3c0}body.dark td,body.dark .pick{border-color:#2c323b}body.dark .kv{color:#aab3c0}body.dark .kv b{color:#e6e9ef}
body.dark nav a{color:#aab3c0}body.dark nav a.on,body.dark nav a:hover{background:#262c34;color:#fff}body.dark button.primary{background:var(--accent);border-color:var(--accent);color:#fff}.chip{display:inline-block;background:#eef2f7;border-radius:99px;padding:1px 9px;font-size:12.5px;margin:1px}
''';

const appJs = r'''
const MANAGER = location.pathname.startsWith('/manage');
const KEY_NAME = 'appkey_' + location.port;
let SPEC = null, KEY = localStorage.getItem(KEY_NAME) || '';
const cache = {};
const $ = (h) => { const d = document.createElement('div'); d.innerHTML = h.trim(); return d.firstElementChild; };
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

async function api(path, opts = {}) {
  const r = await fetch('/api/' + path, {...opts, headers: {'Content-Type': 'application/json', 'X-Key': KEY}});
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.error || ('Error ' + r.status));
  return j;
}
const table = (id) => SPEC.tables.find((t) => t.id === id);
const labelOf = (t) => { const f = t.fields[0]; if (f && !f.manager_only && !['link', 'links', 'longtext', 'yesno'].includes(f.type)) return f.id; return (t.fields.find((x) => x.type === 'text') || f || {id: 'id'}).id; };
async function rows(id, fresh) { if (fresh || !cache[id]) cache[id] = await api('t/' + id); return cache[id]; }
async function names(id) { const t = table(id); const m = {}; if (!t) return m; for (const r of await rows(id)) m[r.id] = r[labelOf(t)] ?? ('#' + r.id); return m; }

async function show(f, v) {
  if (v === null || v === undefined || v === '') return '';
  if (f.type === 'money') return '<span class="price">' + Number(v).toFixed(2) + '</span>';
  if (f.type === 'yesno') return v ? 'Yes' : 'No';
  if (f.type === 'link') return esc((await names(f.link))[v] ?? v);
  if (f.type === 'links' && Array.isArray(v)) { const n = await names(f.link); return v.map((x) => '<span class="chip">' + (typeof x === 'object' ? x.qty + ' × ' + esc(n[x.id] ?? x.id) : esc(n[x] ?? x)) + '</span>').join(' '); }
  if (f.type === 'longtext') return esc(v).replace(/\n/g, '<br>');
  return esc(v);
}

function md(text) {
  return text.split('\n').map((l) => {
    const s = esc(l).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>');
    if (/^### /.test(l)) return '<h3>' + s.slice(4) + '</h3>';
    if (/^## /.test(l)) return '<h3>' + s.slice(3) + '</h3>';
    if (/^# /.test(l)) return '<h2>' + s.slice(2) + '</h2>';
    if (/^[-*] /.test(l)) return '<li>' + s.slice(2) + '</li>';
    return l.trim() ? '<p>' + s + '</p>' : '';
  }).join('');
}

function input(f, v) {
  const id = 'f_' + f.id, req = f.required ? ' required' : '';
  const val = esc(v ?? '');
  switch (f.type) {
    case 'longtext': return '<textarea id="' + id + '"' + req + '>' + val + '</textarea>';
    case 'number': case 'money': return '<input id="' + id + '" type="number" step="any" value="' + val + '"' + req + '>';
    case 'yesno': return '<select id="' + id + '"><option value="false">No</option><option value="true"' + (v ? ' selected' : '') + '>Yes</option></select>';
    case 'date': return '<input id="' + id + '" type="date" value="' + val + '"' + req + '>';
    case 'time': return '<input id="' + id + '" type="time" value="' + val + '"' + req + '>';
    case 'datetime': return '<input id="' + id + '" type="datetime-local" value="' + val + '"' + req + '>';
    case 'email': return '<input id="' + id + '" type="email" value="' + val + '"' + req + '>';
    case 'phone': return '<input id="' + id + '" type="tel" value="' + val + '"' + req + '>';
    case 'choice': return '<select id="' + id + '"' + req + '><option value="">Choose…</option>' + f.options.map((o) => '<option' + (o === v ? ' selected' : '') + '>' + esc(o) + '</option>').join('') + '</select>';
    default: return '<input id="' + id + '" value="' + val + '"' + req + '>';
  }
}

// A form for adding (or, for the manager, editing) a record.
async function formBlock(b, t, record, onDone) {
  const fields = (b.fields ? b.fields.map((x) => t.fields.find((f) => f.id === x)) : t.fields).filter((f) => f && (MANAGER || !f.manager_only));
  const el = $('<div class="card"><form></form></div>');
  const form = el.querySelector('form');
  const picks = {}, redraws = [];
  if (b.title) form.append($('<h3>' + esc(b.title) + '</h3>'));
  for (const f of fields) {
    const v = record ? record[f.id] : undefined;
    form.append($('<label for="f_' + f.id + '">' + esc(f.label) + (f.required ? ' *' : '') + '</label>'));
    if (f.type === 'link') {
      const n = await names(f.link);
      form.append($('<select id="f_' + f.id + '"' + (f.required ? ' required' : '') + '><option value="">Choose…</option>' + Object.entries(n).map(([id, name]) => '<option value="' + id + '"' + (String(v) === id ? ' selected' : '') + '>' + esc(name) + '</option>').join('') + '</select>'));
    } else if (f.type === 'links') {
      const n = await names(f.link), sel = picks[f.id] = {};
      for (const x of (Array.isArray(v) ? v : [])) typeof x === 'object' ? sel[x.id] = x.qty : sel[x] = 1;
      // Prices (if the other table has one) and a running total.
      const money = table(f.link)?.fields.find((x) => x.type === 'money'), price = {};
      if (money) for (const r of await rows(f.link)) price[r.id] = Number(r[money.id]) || 0;
      const box = $('<div class="picks"></div>'), total = $('<div class="kv" style="text-align:right;margin-top:6px"></div>');
      const draw = () => {
        if (money) { const sum = Object.entries(sel).reduce((a, [id, q]) => a + (price[id] || 0) * q, 0); total.innerHTML = sum ? 'Total: <span class="price">' + sum.toFixed(2) + '</span>' : ''; }
        box.innerHTML = Object.entries(n).map(([id, name]) => '<div class="pick"><span>' + esc(name) + (money ? ' <span class="muted">' + (price[id] ?? 0).toFixed(2) + '</span>' : '') + '</span>' + (f.qty
        ? '<div class="qty"><button type="button" data-d="-1" data-id="' + id + '">−</button><b>' + (sel[id] || 0) + '</b><button type="button" data-d="1" data-id="' + id + '">+</button></div>'
        : '<input type="checkbox" style="width:auto" data-id="' + id + '"' + (sel[id] ? ' checked' : '') + '>') + '</div>').join('') || '<div class="pick muted">Nothing to choose yet.</div>'; };
      box.addEventListener('click', (e) => { const id = e.target.dataset.id; if (!id) return; if (e.target.dataset.d) { sel[id] = Math.max(0, (sel[id] || 0) + Number(e.target.dataset.d)); if (!sel[id]) delete sel[id]; } else { e.target.checked ? sel[id] = 1 : delete sel[id]; } draw(); });
      draw(); redraws.push(draw);
      // "Add" buttons on lists of the same page put things in here.
      document.addEventListener('pick', (e) => { if (e.detail.table !== f.link) return; sel[e.detail.id] = (sel[e.detail.id] || 0) + 1; draw(); box.scrollIntoView({behavior: 'smooth', block: 'nearest'}); });
      form.append(box, total);
    } else form.append($(input(f, v)));
  }
  const msg = $('<div></div>');
  form.append($('<div class="row" style="margin-top:16px"><button class="primary">' + esc(b.submit || (record ? 'Save' : 'Send')) + '</button></div>'), msg);
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const body = {};
    for (const f of fields) {
      if (f.type === 'links') { const sel = picks[f.id]; body[f.id] = Object.entries(sel).map(([id, q]) => f.qty ? {id: Number(id), qty: q} : Number(id)); continue; }
      const raw = form.querySelector('#f_' + f.id).value;
      body[f.id] = f.type === 'link' ? (raw ? Number(raw) : null) : (f.type === 'yesno' ? raw === 'true' : raw);
    }
    const btn = form.querySelector('button.primary'); btn.disabled = true;
    try {
      const path = 't/' + t.id + (record && record.id ? '/' + record.id : '');
      await api(path, {method: record || t.kind === 'single' ? 'PUT' : 'POST', body: JSON.stringify(body)});
      delete cache[t.id];
      if (onDone) return onDone();
      msg.className = 'ok'; msg.textContent = b.thanks || 'Thank you — we got it.';
      if (t.kind !== 'single') { form.reset(); for (const k in picks) { for (const id in picks[k]) delete picks[k][id]; } redraws.forEach((d) => d()); }
    } catch (err) { msg.className = 'err'; msg.textContent = err.message; }
    btn.disabled = false;
  });
  return el;
}

async function listBlock(b, t, pageBlocks) {
  const fields = (b.fields ? b.fields.map((x) => t.fields.find((f) => f.id === x)) : t.fields).filter((f) => f && (MANAGER || !f.manager_only));
  const label = labelOf(t);
  const canPick = pageBlocks.some((o) => o.type === 'form' && table(o.table)?.fields.some((f) => f.type === 'links' && f.link === t.id));
  const el = $('<div></div>');
  if (b.title) el.append($('<h2>' + esc(b.title) + '</h2>'));
  const q = $('<input class="search" placeholder="Search ' + esc(t.title.toLowerCase()) + '…">');
  if (b.search !== false) el.append(q);
  const grid = $('<div class="grid"></div>'); el.append(grid);
  const all = await rows(t.id, true);
  const draw = async () => {
    const words = q.value.toLowerCase().split(/\s+/).filter(Boolean);
    const list = all.filter((r) => words.every((w) => JSON.stringify(r).toLowerCase().includes(w)));
    grid.innerHTML = list.length ? '' : '<p class="muted">Nothing here yet.</p>';
    for (const r of list) {
      let h = '<div class="card"><div class="t">' + esc(r[label] ?? '') + '</div>';
      for (const f of fields) { if (f.id === label) continue; const v = await show(f, r[f.id]); if (v !== '') h += '<div class="kv">' + (f.type === 'longtext' ? '' : esc(f.label) + ': ') + '<b>' + v + '</b></div>'; }
      if (canPick) h += '<div style="margin-top:10px"><button class="primary" data-id="' + r.id + '">Add</button></div>';
      const card = $(h + '</div>');
      card.querySelector('button')?.addEventListener('click', () => document.dispatchEvent(new CustomEvent('pick', {detail: {table: t.id, id: r.id}})));
      grid.append(card);
    }
  };
  q.addEventListener('input', draw); await draw();
  return el;
}

async function infoBlock(b, t) {
  const r = (await rows(t.id, true))[0] || {};
  let h = '<div class="card">' + (b.title ? '<h3>' + esc(b.title) + '</h3>' : '');
  for (const f of t.fields) { if (!MANAGER && f.manager_only) continue; const v = await show(f, r[f.id]); if (v !== '') h += '<div class="kv">' + esc(f.label) + ': <b>' + v + '</b></div>'; }
  return $(h + '</div>');
}

async function renderPage(p, main) {
  main.innerHTML = '';
  for (const b of p.blocks) {
    const box = $('<div class="block"></div>'); main.append(box);
    try {
      if (b.type === 'text') { box.innerHTML = md(b.text); continue; }
      const t = table(b.table); if (!t) continue;
      if (b.type === 'list') box.append(await listBlock(b, t, p.blocks));
      if (b.type === 'info') box.append(await infoBlock(b, t));
      if (b.type === 'form') box.append(await formBlock(b, t, t.kind === 'single' ? (await rows(t.id))[0] : null));
    } catch (e) { box.innerHTML = '<div class="err">' + esc(e.message) + '</div>'; }
  }
  if (!p.blocks.length) main.innerHTML = '<p class="muted">This page is empty.</p>';
}

// ---------- manager ----------
async function login(main) {
  main.innerHTML = '';
  const el = $('<div class="card center"><h2>Manager</h2><p class="muted">Enter the manager PIN (shown in LocalAILine).</p><form><input id="pin" inputmode="numeric" placeholder="PIN" autofocus><div class="row" style="margin-top:12px;justify-content:center"><button class="primary">Sign in</button></div><div id="m"></div></form></div>');
  el.querySelector('form').addEventListener('submit', async (e) => {
    e.preventDefault();
    try { await fetch('/api/_login', {method: 'POST', body: JSON.stringify({pin: el.querySelector('#pin').value})}).then(async (r) => { if (!r.ok) throw new Error((await r.json()).error); });
      KEY = el.querySelector('#pin').value; localStorage.setItem(KEY_NAME, KEY); start(); }
    catch (err) { const m = el.querySelector('#m'); m.className = 'err'; m.textContent = err.message; }
  });
  main.append(el);
}

function modal(content) { const m = $('<div class="modal"></div>'); m.append(content); m.addEventListener('click', (e) => { if (e.target === m) m.remove(); }); document.body.append(m); return m; }

async function manageTable(t, main) {
  main.innerHTML = '';
  if (t.kind === 'single') {
    main.append($('<h2>' + esc(t.title) + '</h2>'), $('<p class="muted">' + esc(t.purpose || '') + '</p>'));
    main.append(await formBlock({}, t, (await rows(t.id, true))[0] || {}, () => manageTable(t, main)));
    return;
  }
  const head = $('<div class="row" style="margin-bottom:12px"><h2 style="margin:0;flex:1">' + esc(t.title) + '</h2><input class="search" style="margin:0;max-width:240px" placeholder="Search…"><button class="primary">Add</button></div>');
  main.append(head);
  if (t.purpose) main.append($('<p class="muted">' + esc(t.purpose) + '</p>'));
  const box = $('<div style="overflow:auto"></div>'); main.append(box);
  const all = await rows(t.id, true);
  const shown = t.fields.slice(0, 7);
  const draw = async () => {
    const words = head.querySelector('input').value.toLowerCase().split(/\s+/).filter(Boolean);
    const list = all.filter((r) => words.every((w) => JSON.stringify(r).toLowerCase().includes(w))).reverse();
    let h = '<table><tr>' + shown.map((f) => '<th>' + esc(f.label) + '</th>').join('') + '<th>Added</th><th></th></tr>';
    for (const r of list) { h += '<tr>'; for (const f of shown) h += '<td>' + await show(f, r[f.id]) + '</td>'; h += '<td class="muted">' + esc(r.created_at || '') + '</td><td class="row" style="flex-wrap:nowrap"><button data-e="' + r.id + '">Edit</button><button class="danger" data-x="' + r.id + '">Delete</button></td></tr>'; }
    box.innerHTML = h + '</table>' + (list.length ? '' : '<p class="muted">Nothing here yet. Use Add.</p>');
  };
  const edit = async (r) => { const card = $('<div></div>'); const m = modal(card); card.append(await formBlock({title: (r ? 'Edit ' : 'Add to ') + t.title.toLowerCase()}, t, r, () => { m.remove(); manageTable(t, main); })); };
  head.querySelector('button').addEventListener('click', () => edit(null));
  head.querySelector('input').addEventListener('input', draw);
  box.addEventListener('click', async (e) => {
    const id = e.target.dataset.e || e.target.dataset.x; if (!id) return;
    const r = all.find((x) => String(x.id) === id);
    if (e.target.dataset.e) return edit(r);
    if (!confirm('Delete this record?')) return;
    await api('t/' + t.id + '/' + id, {method: 'DELETE'}); delete cache[t.id]; manageTable(t, main);
  });
  await draw();
}

async function manager(main, nav) {
  const items = [...SPEC.tables.map((t) => ['t', t]), ...SPEC.pages.filter((p) => p.manager).map((p) => ['p', p])];
  nav.innerHTML = '<a href="/">View website</a><a href="#" id="out">Sign out</a>';
  nav.querySelector('#out').addEventListener('click', (e) => { e.preventDefault(); localStorage.removeItem(KEY_NAME); KEY = ''; start(); });
  main.innerHTML = '';
  const tabs = $('<div class="tabs"></div>'), body = $('<div></div>');
  main.append(tabs, body);
  const open = (i) => { tabs.querySelectorAll('button').forEach((b, j) => b.classList.toggle('on', i === j)); const [k, x] = items[i]; location.hash = x.id; k === 't' ? manageTable(x, body) : renderPage(x, body); };
  items.forEach(([k, x], i) => { const b = $('<button>' + esc(x.title) + '</button>'); b.addEventListener('click', () => open(i)); tabs.append(b); });
  const at = items.findIndex(([, x]) => x.id === location.hash.slice(1));
  if (items.length) open(at < 0 ? 0 : at);
}

async function start() {
  const main = document.getElementById('main'), nav = document.getElementById('nav');
  try { SPEC = await api('_spec'); } catch (e) { main.innerHTML = '<div class="err">' + esc(e.message) + '</div>'; return; }
  if (MANAGER) return SPEC.manager ? manager(main, nav) : login(main);
  const pages = SPEC.pages.filter((p) => !p.manager);
  const id = location.pathname.startsWith('/p/') ? decodeURIComponent(location.pathname.slice(3)) : (pages[0] || {}).id;
  nav.innerHTML = pages.map((p) => '<a href="/p/' + p.id + '"' + (p.id === id ? ' class="on"' : '') + '>' + esc(p.title) + '</a>').join('') + '<a href="/manage">Manager</a>';
  const p = pages.find((x) => x.id === id);
  if (!p) { main.innerHTML = '<p class="muted">Page not found.</p>'; return; }
  document.title = p.title + ' · ' + SPEC.name;
  await renderPage(p, main);
}
start();
''';
