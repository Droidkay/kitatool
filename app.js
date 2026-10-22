/* Kitatool — gaming speed test. Runs entirely in the browser against Cloudflare's speed test network. */
'use strict';

const BASE = 'https://speed.cloudflare.com';
const $ = (id) => document.getElementById(id);
const C = {
  cyan: '#00E5FF', blue: '#2F7BFF', violet: '#B15CFF', pink: '#FF4FD8',
  lime: '#7CFF6B', amber: '#FFC23D', red: '#FF4D5E', dim: '#8A8FA3', bg: '#06070B',
};
const DPR = () => Math.min(window.devicePixelRatio || 1, 3);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const median = (a) => { if (!a.length) return 0; const s = [...a].sort((x, y) => x - y); const m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };
const jitterOf = (a) => a.length < 2 ? 0 : a.slice(1).reduce((t, v, i) => t + Math.abs(v - a[i]), 0) / (a.length - 1);
const fmt = (v, d = 0) => v == null || isNaN(v) ? '–' : v.toFixed(d);
const fmtSpeed = (v) => v == null ? '–' : v < 10 ? v.toFixed(2) : v < 100 ? v.toFixed(1) : v.toFixed(0);
const pingColor = (ms) => ms == null ? C.red : ms < 40 ? C.lime : ms < 80 ? C.amber : C.red;
const gradeColor = (g) => (g === 'A+' || g === 'A') ? C.lime : g === 'B' ? C.cyan : g === 'C' ? C.amber : C.red;

const REGIONS = [
  { name: 'London', flag: '🇬🇧', r: 'eu-west-2' },
  { name: 'Frankfurt', flag: '🇩🇪', r: 'eu-central-1' },
  { name: 'Ireland', flag: '🇮🇪', r: 'eu-west-1' },
  { name: 'Paris', flag: '🇫🇷', r: 'eu-west-3' },
  { name: 'Cape Town', flag: '🇿🇦', r: 'af-south-1' },
  { name: 'Bahrain', flag: '🇧🇭', r: 'me-south-1' },
  { name: 'US East', flag: '🇺🇸', r: 'us-east-1' },
];
const regionUrl = (r) => `https://dynamodb.${r}.amazonaws.com/ping`;

/* =================================================================== measurement */

let rtCount = 0;
/** One round trip on a warm connection. Uses Resource Timing when the server allows it (cleanest), else wall clock. */
async function latencySample(signal, timeoutMs = 2000) {
  const url = `${BASE}/__down?bytes=0&r=${Math.random().toString(36).slice(2)}`;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), timeoutMs);
  if (signal) signal.addEventListener('abort', () => ctl.abort(), { once: true });
  const t0 = performance.now();
  try {
    const res = await fetch(url, { cache: 'no-store', signal: ctl.signal });
    await res.arrayBuffer();
    const t1 = performance.now();
    let rtt = t1 - t0;
    const e = performance.getEntriesByName(url).pop();
    if (e && e.requestStart > 0 && e.responseStart > e.requestStart) rtt = e.responseStart - e.requestStart;
    const st = res.headers.get('server-timing');
    const dur = st && /dur=([\d.]+)/.exec(st);
    if (dur) rtt -= parseFloat(dur[1]);
    if (++rtCount % 50 === 0) performance.clearResourceTimings();
    return Math.max(rtt, 0.5);
  } finally {
    clearTimeout(timer);
  }
}

async function fetchMeta() {
  try {
    const r = await fetch(`${BASE}/meta`, { cache: 'no-store' });
    const o = await r.json();
    return { ip: o.clientIp || '', isp: o.asOrganization || '', city: o.city || '', country: o.country || '', colo: o.colo || '' };
  } catch (e) {
    try {
      const t = await (await fetch(`${BASE}/cdn-cgi/trace`, { cache: 'no-store' })).text();
      const get = (k) => (new RegExp(`^${k}=(.*)$`, 'm').exec(t) || [])[1] || '';
      return { ip: get('ip'), isp: '', city: '', country: get('loc'), colo: get('colo') };
    } catch (e2) { return { ip: '', isp: '', city: '', country: '', colo: '' }; }
  }
}

/** Download with parallel streams; returns steady-state Mbps (first 2 s of ramp-up excluded). */
async function download(durationMs, streams, onTick, signal) {
  let bytes = 0;
  const start = performance.now();
  const end = start + durationMs;
  const ctl = new AbortController();
  signal.addEventListener('abort', () => ctl.abort(), { once: true });
  if (signal.aborted) ctl.abort();

  const worker = async () => {
    while (performance.now() < end && !ctl.signal.aborted) {
      try {
        const res = await fetch(`${BASE}/__down?bytes=50000000&r=${Math.random()}`, { cache: 'no-store', signal: ctl.signal });
        const reader = res.body.getReader();
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          bytes += value.byteLength;
          if (performance.now() >= end) { reader.cancel().catch(() => {}); break; }
        }
      } catch (e) { if (ctl.signal.aborted) return; await sleep(100); }
    }
  };
  const out = await runTransfer(() => bytes, start, end, streams, worker, onTick, ctl);
  if (signal.aborted) throw new DOMException('cancel', 'AbortError');
  return out;
}

/** Upload with parallel streams. Chunk size grows as requests finish quickly. */
async function upload(durationMs, streams, onTick, signal) {
  let bytes = 0;
  const start = performance.now();
  const end = start + durationMs;
  const ctl = new AbortController();
  signal.addEventListener('abort', () => ctl.abort(), { once: true });
  if (signal.aborted) ctl.abort();
  const pool = new Uint8Array(8 * 1024 * 1024);
  for (let i = 0; i < pool.length; i += 65536) crypto.getRandomValues(pool.subarray(i, i + 65536));

  const worker = async () => {
    let size = 256 * 1024;
    while (performance.now() < end && !ctl.signal.aborted) {
      const t = performance.now();
      try {
        await fetch(`${BASE}/__up?r=${Math.random()}`, { method: 'POST', body: pool.subarray(0, size), mode: 'no-cors', cache: 'no-store', signal: ctl.signal });
        if (performance.now() <= end + 400) bytes += size;
        if (performance.now() - t < 400 && size < pool.length) size *= 2;
      } catch (e) { if (ctl.signal.aborted) return; await sleep(100); }
    }
  };
  const out = await runTransfer(() => bytes, start, end, streams, worker, onTick, ctl);
  if (signal.aborted) throw new DOMException('cancel', 'AbortError');
  return out;
}

async function runTransfer(getBytes, start, end, streams, worker, onTick, ctl) {
  const workers = Array.from({ length: streams }, worker);
  const win = [];
  let rampBytes = -1;
  while (performance.now() < end && !ctl.signal.aborted) {
    await sleep(100);
    const now = performance.now();
    const b = getBytes();
    if (rampBytes < 0 && now - start >= 2000) rampBytes = b;
    win.push([now, b]);
    while (win.length > 2 && now - win[0][0] > 900) win.shift();
    const [t0, b0] = win[0];
    const mbps = now > t0 ? ((b - b0) * 8) / ((now - t0) / 1000) / 1e6 : 0;
    onTick(Math.max(0, mbps), Math.min(1, (now - start) / (end - start)));
  }
  ctl.abort();
  await Promise.allSettled(workers);
  const total = getBytes();
  return { mbps: ((total - Math.max(0, rampBytes)) * 8) / ((end - start - 2000) / 1000) / 1e6, bytes: total };
}

/** Ping to a cloud region (game-server proxy): fastest of a few warm requests. */
async function regionPing(r) {
  const once = async () => {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 3000);
    const t = performance.now();
    try {
      await fetch(`${regionUrl(r)}?x=${Math.random()}`, { mode: 'no-cors', cache: 'no-store', signal: ctl.signal });
      return performance.now() - t;
    } catch (e) { return null; } finally { clearTimeout(timer); }
  };
  await once(); // DNS + TLS warm-up
  const times = [];
  for (let i = 0; i < 4; i++) { const v = await once(); if (v != null) times.push(v); }
  return times.length ? Math.min(...times) : null;
}

function netInfo() {
  const c = navigator.connection || navigator.mozConnection || navigator.webkitConnection;
  if (!navigator.onLine) return { type: 'Offline' };
  if (!c) return { type: 'Online' };
  const types = { wifi: 'Wi-Fi', cellular: 'Mobile data', ethernet: 'Ethernet', wimax: 'WiMAX', bluetooth: 'Bluetooth' };
  return {
    type: types[c.type] || (c.effectiveType ? c.effectiveType.toUpperCase() : 'Online'),
    effective: c.effectiveType,
    saveData: c.saveData,
  };
}

/* =================================================================== gaming verdicts */

const Gaming = {
  score(r) {
    const p = r.ping <= 20 ? 35 : r.ping <= 40 ? 30 : r.ping <= 60 ? 24 : r.ping <= 90 ? 15 : r.ping <= 130 ? 8 : 3;
    const j = r.jitter <= 3 ? 20 : r.jitter <= 8 ? 16 : r.jitter <= 15 ? 11 : r.jitter <= 30 ? 6 : 2;
    const l = r.loss == null ? 14 : r.loss <= 0 ? 20 : r.loss < .5 ? 16 : r.loss < 1 ? 12 : r.loss < 2.5 ? 6 : 0;
    const b = r.bloat == null ? 9 : r.bloat <= 10 ? 15 : r.bloat <= 30 ? 12 : r.bloat <= 60 ? 8 : r.bloat <= 150 ? 4 : 1;
    const d = r.down >= 50 ? 5 : r.down >= 20 ? 4 : r.down >= 10 ? 3 : r.down >= 5 ? 2 : 1;
    const u = r.up >= 10 ? 5 : r.up >= 5 ? 4 : r.up >= 3 ? 3 : r.up >= 1 ? 2 : 1;
    return Math.max(0, Math.min(100, p + j + l + b + d + u));
  },
  grade: (s) => s >= 90 ? 'A+' : s >= 80 ? 'A' : s >= 70 ? 'B' : s >= 55 ? 'C' : s >= 40 ? 'D' : 'F',
  verdict: (s) => s >= 90 ? 'Elite. Ready for ranked and tournaments.' : s >= 80 ? 'Excellent for competitive online play.'
    : s >= 70 ? 'Good. Smooth for most online games.' : s >= 55 ? 'Playable, but expect the odd lag spike.'
    : s >= 40 ? 'Laggy. Casual games only.' : 'Poor connection for online gaming.',
  bloatGrade: (ms) => ms == null ? '–' : ms < 5 ? 'A+' : ms < 30 ? 'A' : ms < 60 ? 'B' : ms < 200 ? 'C' : ms < 400 ? 'D' : 'F',
  readiness(r) {
    const loss = r.loss || 0, bloat = r.bloat || 0;
    const lvl = (g, o) => g ? 'great' : o ? 'ok' : 'poor';
    return [
      ['Competitive shooters', 'CoD, Valorant, Free Fire', lvl(r.ping < 40 && r.jitter < 8 && loss < .5 && bloat < 60, r.ping < 80 && r.jitter < 15 && loss < 1.5)],
      ['Football online', 'EA FC, eFootball, Division Rivals', lvl(r.ping < 50 && r.jitter < 10 && loss < .5, r.ping < 90 && r.jitter < 20 && loss < 1.5)],
      ['Battle royale', 'PUBG, Fortnite, Warzone', lvl(r.ping < 60 && r.jitter < 12 && loss < 1, r.ping < 110 && loss < 2.5)],
      ['Cloud gaming', 'Xbox Cloud, GeForce NOW', lvl(r.down >= 35 && r.ping < 40 && r.jitter < 8, r.down >= 15 && r.ping < 70)],
      ['Live streaming', '1080p60 to YouTube / Twitch', lvl(r.up >= 10 && bloat < 100, r.up >= 5)],
      ['Voice chat', 'Discord, party chat', lvl(r.ping < 100 && loss < 1, r.ping < 200 && loss < 3)],
    ];
  },
};

/* =================================================================== history */

const History = {
  key: 'kitatool.history.v1',
  load() { try { return JSON.parse(localStorage.getItem(this.key) || '[]'); } catch (e) { return []; } },
  add(r) { const list = [r, ...this.load()].slice(0, 60); try { localStorage.setItem(this.key, JSON.stringify(list)); } catch (e) {} return list; },
  clear() { try { localStorage.removeItem(this.key); } catch (e) {} },
};

/* =================================================================== canvases */

function fitCanvas(cv) {
  const r = cv.getBoundingClientRect();
  const d = DPR();
  const w = Math.max(1, Math.round(r.width * d)), h = Math.max(1, Math.round(r.height * d));
  if (cv.width !== w || cv.height !== h) { cv.width = w; cv.height = h; }
  const ctx = cv.getContext('2d');
  ctx.setTransform(d, 0, 0, d, 0, 0);
  return { ctx, w: r.width, h: r.height };
}

/* ---------- aurora background */
const aurora = { accent: C.cyan, cur: [0, 229, 255] };
function hexRgb(h) { const n = parseInt(h.slice(1), 16); return [n >> 16 & 255, n >> 8 & 255, n & 255]; }
function drawAurora(t) {
  const cv = $('aurora');
  const { ctx, w, h } = fitCanvas(cv);
  const tgt = hexRgb(aurora.accent);
  aurora.cur = aurora.cur.map((v, i) => v + (tgt[i] - v) * 0.04);
  const [r, g, b] = aurora.cur.map(Math.round);
  const drift = (Math.sin(t / 7000) + 1) / 2;
  ctx.clearRect(0, 0, w, h);
  const g1 = ctx.createRadialGradient(w * (0.15 + 0.3 * drift), h * 0.12, 0, w * (0.15 + 0.3 * drift), h * 0.12, Math.max(w, h) * 0.7);
  g1.addColorStop(0, `rgba(${r},${g},${b},0.20)`); g1.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = g1; ctx.fillRect(0, 0, w, h);
  const g2 = ctx.createRadialGradient(w * (0.9 - 0.3 * drift), h * 0.8, 0, w * (0.9 - 0.3 * drift), h * 0.8, Math.max(w, h) * 0.8);
  g2.addColorStop(0, 'rgba(177,92,255,0.13)'); g2.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = g2; ctx.fillRect(0, 0, w, h);
}

/* ---------- speedometer */
const START = 0.75 * Math.PI, SWEEP = 1.5 * Math.PI;
const TICKS = [0, 5, 10, 25, 50, 100, 250, 500, 1000];
const dialPos = (mbps) => Math.log10(1 + Math.min(Math.max(mbps, 0), 1000)) / Math.log10(1001);
const gauge = { pos: 0, vel: 0, target: 0, spin: 0 };

function drawGauge(dt) {
  const cv = $('gauge');
  const { ctx, w } = fitCanvas(cv);
  const S = w, c = S / 2, stroke = S * 0.055, pad = stroke * 2.4, r = S / 2 - pad;
  ctx.clearRect(0, 0, S, S);
  ctx.lineCap = 'round';

  // track
  ctx.beginPath(); ctx.arc(c, c, r, START, START + SWEEP);
  ctx.strokeStyle = 'rgba(255,255,255,0.06)'; ctx.lineWidth = stroke; ctx.stroke();

  const running = state.running;
  const phase = state.phase;
  const accA = phase === 'upload' ? C.violet : C.cyan;
  const accB = phase === 'upload' ? C.pink : C.blue;

  if (!running) {
    gauge.spin += dt * 0.0017;
    const a0 = gauge.spin;
    const grad = ctx.createConicGradient ? ctx.createConicGradient(a0, c, c) : null;
    if (grad) {
      grad.addColorStop(0, 'rgba(0,229,255,0)'); grad.addColorStop(0.55, 'rgba(0,229,255,0.15)');
      grad.addColorStop(0.8, C.cyan); grad.addColorStop(0.83, C.blue); grad.addColorStop(1, 'rgba(47,123,255,0)');
    }
    ctx.beginPath(); ctx.arc(c, c, r, a0, a0 + Math.PI * 1.66);
    ctx.strokeStyle = grad || C.cyan; ctx.lineWidth = stroke * 0.5; ctx.stroke();
    return;
  }

  // ticks + labels
  ctx.font = `500 ${Math.round(S * 0.032)}px Inter, sans-serif`;
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  for (const t of TICKS) {
    const a = START + SWEEP * dialPos(t);
    const ci = Math.cos(a), si = Math.sin(a);
    ctx.beginPath();
    ctx.moveTo(c + ci * (r - stroke * 1.4), c + si * (r - stroke * 1.4));
    ctx.lineTo(c + ci * (r - stroke * 0.9), c + si * (r - stroke * 0.9));
    ctx.strokeStyle = 'rgba(255,255,255,0.35)'; ctx.lineWidth = 2; ctx.stroke();
    ctx.fillStyle = C.dim;
    ctx.fillText(String(t), c + ci * (r - stroke * 2.6), c + si * (r - stroke * 2.6));
  }

  if (phase === 'download' || phase === 'upload') {
    // spring-damped needle
    const k = 70, damp = 2 * Math.sqrt(k) * 0.62, step = Math.min(dt, 34) / 1000;
    gauge.vel += (k * (gauge.target - gauge.pos) - damp * gauge.vel) * step;
    gauge.pos += gauge.vel * step;
    const p = Math.max(0, Math.min(1, gauge.pos));
    const end = START + SWEEP * p;
    // glow
    ctx.save();
    ctx.shadowColor = accB; ctx.shadowBlur = stroke * 1.6;
    const grad = ctx.createConicGradient ? ctx.createConicGradient(START, c, c) : null;
    if (grad) { grad.addColorStop(0, accA); grad.addColorStop(Math.max(0.002, Math.min(0.999, p * 0.75)), accB); grad.addColorStop(1, accB); }
    ctx.beginPath(); ctx.arc(c, c, r, START, Math.max(end, START + 0.001));
    ctx.strokeStyle = grad || accA; ctx.lineWidth = stroke; ctx.stroke();
    ctx.restore();
    // floating pointer just inside the arc (keeps the centre clear for the number)
    const tipR = r - stroke * 1.5, tailR = r - stroke * 3.6, base = stroke * 0.32;
    const cos = Math.cos(end), sin = Math.sin(end);
    const tx = c + cos * tipR, ty = c + sin * tipR;
    const bx = c + cos * tailR, by = c + sin * tailR;
    const px = Math.cos(end + Math.PI / 2) * base, py = Math.sin(end + Math.PI / 2) * base;
    const ng = ctx.createLinearGradient(bx, by, tx, ty);
    ng.addColorStop(0, 'rgba(255,255,255,0)'); ng.addColorStop(1, '#fff');
    ctx.save(); ctx.shadowColor = '#fff'; ctx.shadowBlur = 10;
    ctx.beginPath(); ctx.moveTo(tx, ty); ctx.lineTo(bx + px, by + py); ctx.lineTo(bx - px, by - py); ctx.closePath();
    ctx.fillStyle = ng; ctx.fill(); ctx.restore();
  } else {
    ctx.beginPath(); ctx.arc(c, c, r, START, START + SWEEP * Math.max(0.002, state.progress));
    ctx.strokeStyle = phase === 'regions' ? C.amber : C.lime; ctx.lineWidth = stroke * 0.5; ctx.stroke();
  }
}

/* ---------- live line */
function drawLine(cv, series, cap = 100) {
  const { ctx, w, h } = fitCanvas(cv);
  ctx.clearRect(0, 0, w, h);
  const all = series.flatMap((s) => s.data);
  if (all.length < 2) return;
  const maxV = Math.max(...all) * 1.15 || 1;
  for (const s of series) {
    const d = s.data;
    if (d.length < 2) continue;
    const step = w / ((s.cap || cap) - 1);
    const x0 = w - step * (d.length - 1);
    const pts = d.map((v, i) => [x0 + i * step, h - (v / maxV) * h * 0.92]);
    const path = new Path2D();
    path.moveTo(pts[0][0], pts[0][1]);
    for (let i = 1; i < pts.length; i++) {
      const [ax, ay] = pts[i - 1], [bx, by] = pts[i], mx = (ax + bx) / 2;
      path.bezierCurveTo(mx, ay, mx, by, bx, by);
    }
    const fill = new Path2D(path);
    fill.lineTo(pts[pts.length - 1][0], h); fill.lineTo(pts[0][0], h); fill.closePath();
    const fg = ctx.createLinearGradient(0, 0, 0, h);
    fg.addColorStop(0, s.color + '55'); fg.addColorStop(1, s.color + '00');
    ctx.fillStyle = fg; ctx.fill(fill);
    ctx.save(); ctx.shadowColor = s.color; ctx.shadowBlur = 14;
    ctx.strokeStyle = s.color; ctx.lineWidth = 2.5; ctx.lineJoin = 'round'; ctx.stroke(path); ctx.restore();
    const [lx, ly] = pts[pts.length - 1];
    ctx.beginPath(); ctx.arc(lx, ly, 9, 0, Math.PI * 2); ctx.fillStyle = s.color + '55'; ctx.fill();
    ctx.beginPath(); ctx.arc(lx, ly, 3.5, 0, Math.PI * 2); ctx.fillStyle = '#fff'; ctx.fill();
  }
}

/* ---------- score ring */
function drawScoreRing(frac, color) {
  const cv = $('scoreRing');
  const { ctx, w } = fitCanvas(cv);
  const s = 9, r = w / 2 - s;
  ctx.clearRect(0, 0, w, w);
  ctx.lineCap = 'round';
  ctx.beginPath(); ctx.arc(w / 2, w / 2, r, 0, Math.PI * 2); ctx.strokeStyle = 'rgba(255,255,255,0.07)'; ctx.lineWidth = s; ctx.stroke();
  ctx.save(); ctx.shadowColor = color; ctx.shadowBlur = 14;
  ctx.beginPath(); ctx.arc(w / 2, w / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * frac); ctx.strokeStyle = color; ctx.stroke();
  ctx.restore();
}

/* =================================================================== test controller */

const state = {
  running: false, phase: null, progress: 0, live: 0, latency: null,
  ping: null, jitter: null, loss: null, down: null, up: null, meta: null,
  downS: [], upS: [], pingS: [], result: null, ctl: null,
};

function setPhase(p) {
  state.phase = p; state.progress = 0; state.live = 0;
  gauge.target = 0;
  if (p === 'download' || p === 'upload') { gauge.pos = 0; gauge.vel = 0; }
  aurora.accent = p === 'upload' ? C.pink : p === 'regions' ? C.amber : C.cyan;
  const order = ['ping', 'download', 'upload', 'regions'];
  document.querySelectorAll('#steps span').forEach((el) => {
    const i = order.indexOf(el.dataset.p), cur = order.indexOf(p);
    el.classList.toggle('on', state.result != null || (cur >= 0 && i <= cur));
    el.classList.toggle('active', el.dataset.p === p);
  });
  const ph = $('readPhase');
  ph.textContent = ({ ping: 'PING', download: 'DOWNLOAD', upload: 'UPLOAD', regions: 'GAME REGIONS' })[p] || '';
  ph.style.color = p === 'upload' ? C.pink : p === 'regions' ? C.amber : p === 'ping' ? C.lime : C.cyan;
  $('readUnit').textContent = (p === 'download' || p === 'upload') ? 'Mbps' : 'ms';
  const gc = $('graphCard');
  gc.classList.remove('hidden');
  gc.style.setProperty('--g', p === 'upload' ? C.pink : p === 'ping' ? C.lime : C.cyan);
  gc.classList.add('glow');
  $('graphTitle').textContent = ({ ping: 'Latency · live', download: 'Download · live', upload: 'Upload · live', regions: 'Download & upload' })[p];
}

function renderTiles() {
  const live = state.running ? state.live : null;
  $('vPing').textContent = fmt(state.ping); $('vPing').style.color = state.ping != null ? pingColor(state.ping) : '';
  $('vJitter').textContent = fmt(state.jitter, 1);
  $('vJitter').style.color = state.jitter == null ? '' : state.jitter < 8 ? C.lime : state.jitter < 20 ? C.amber : C.red;
  $('vLoss').textContent = fmt(state.loss, 1);
  $('vLoss').style.color = state.loss == null ? '' : state.loss <= 0 ? C.lime : state.loss < 1.5 ? C.amber : C.red;
  $('vDown').textContent = fmtSpeed(state.down ?? (state.phase === 'download' ? live : null));
  $('vUp').textContent = fmtSpeed(state.up ?? (state.phase === 'upload' ? live : null));
}

async function startTest() {
  if (state.running) return;
  Object.assign(state, {
    running: true, progress: 0, live: 0, latency: null, ping: null, jitter: null, loss: null,
    down: null, up: null, downS: [], upS: [], pingS: [], result: null, ctl: new AbortController(),
  });
  const signal = state.ctl.signal;
  $('goBtn').classList.add('hidden'); $('readout').classList.remove('hidden');
  $('cancelBtn').classList.remove('hidden'); $('results').classList.add('hidden'); $('errorCard').classList.add('hidden');
  renderTiles();
  const net = netInfo();
  let lost = 0, probes = 0;
  const probe = async () => {
    probes++;
    try { const v = await latencySample(signal); return v; } catch (e) { if (signal.aborted) throw e; lost++; return null; }
  };

  try {
    // ---------- ping
    setPhase('ping');
    const metaP = fetchMeta();
    await latencySample(signal).catch(() => {}); // warm-up (TLS)
    const samples = [];
    for (let i = 0; i < 20; i++) {
      if (signal.aborted) throw new DOMException('cancel', 'AbortError');
      const v = await probe();
      if (v != null) { samples.push(v); state.latency = v; state.pingS.push(v); }
      state.progress = (i + 1) / 20;
      await sleep(60);
    }
    if (!samples.length) throw new Error("Couldn't reach the test server. Check your connection and try again.");
    state.ping = median(samples); state.jitter = jitterOf(samples);
    state.loss = (lost / probes) * 100;
    renderTiles();
    state.meta = await metaP;
    renderMeta();

    // ---------- download + loaded latency
    setPhase('download');
    const ld = [];
    let stopProbe = false;
    const loadedLoop = async (out) => {
      await sleep(1200);
      while (!stopProbe && !signal.aborted) {
        const v = await probe().catch(() => null);
        if (v != null) { out.push(v); }
        await sleep(350);
      }
    };
    let pl = loadedLoop(ld);
    const dl = await download(10000, 6, (mbps, p) => {
      state.live = mbps; state.progress = p; gauge.target = dialPos(mbps); state.downS.push(mbps); renderTiles();
    }, signal);
    stopProbe = true; await pl;
    state.down = dl.mbps; renderTiles();

    // ---------- upload + loaded latency
    setPhase('upload');
    const lu = [];
    stopProbe = false;
    pl = loadedLoop(lu);
    const ul = await upload(9000, 4, (mbps, p) => {
      state.live = mbps; state.progress = p; gauge.target = dialPos(mbps); state.upS.push(mbps); renderTiles();
    }, signal);
    stopProbe = true; await pl;
    state.up = ul.mbps; renderTiles();

    // ---------- regions
    if (signal.aborted) throw new DOMException('cancel', 'AbortError');
    setPhase('regions');
    let done = 0;
    const regions = await Promise.all(REGIONS.map(async (g) => {
      const ms = await regionPing(g.r);
      state.progress = ++done / REGIONS.length;
      return { name: g.name, flag: g.flag, ms };
    }));

    if (signal.aborted) throw new DOMException('cancel', 'AbortError');
    state.loss = probes ? (lost / probes) * 100 : null;
    const loadedDown = ld.length >= 3 ? median(ld) : null;
    const loadedUp = lu.length >= 3 ? median(lu) : null;
    const loadMax = Math.max(loadedDown ?? -1, loadedUp ?? -1);
    const r = {
      time: Date.now(), down: state.down, up: state.up, ping: state.ping, jitter: state.jitter, loss: state.loss,
      loadedDown, loadedUp, bloat: loadMax >= 0 ? Math.max(0, loadMax - state.ping) : null,
      dataMb: (dl.bytes + ul.bytes) / 1e6, meta: state.meta, net, regions,
    };
    state.result = r;
    History.add(r);
    showResult(r);
  } catch (e) {
    if (!(e && e.name === 'AbortError')) {
      $('errorText').textContent = (e && e.message) || 'Test failed. Check your connection and try again.';
      $('errorCard').classList.remove('hidden');
    }
  } finally {
    state.running = false;
    state.phase = null;
    $('cancelBtn').classList.add('hidden');
    $('readout').classList.add('hidden');
    $('goBtn').classList.remove('hidden');
    document.querySelectorAll('#steps span').forEach((el) => {
      el.classList.toggle('on', state.result != null);
      el.classList.remove('active');
    });
    if (!state.result) $('graphCard').classList.add('hidden');
    aurora.accent = C.cyan;
    renderTiles(); renderHistory();
  }
}

function renderMeta() {
  const m = state.meta;
  if (m && (m.isp || m.colo)) $('subline').textContent = [m.isp, [m.city, m.colo].filter(Boolean).join(' ')].filter(Boolean).join(' · ');
}

function showResult(r) {
  $('results').classList.remove('hidden');
  $('goBtn').classList.remove('hidden');
  $('graphTitle').textContent = 'Download & upload';
  $('graphCard').classList.remove('glow');
  const score = Gaming.score(r), grade = Gaming.grade(score), gc = gradeColor(grade);
  $('grade').textContent = grade; $('grade').style.color = gc;
  $('scoreNum').textContent = `${score}/100`;
  $('verdict').textContent = Gaming.verdict(score);
  const card = $('scoreCard'); card.style.setProperty('--g', gc); card.classList.add('glow');
  const bg = Gaming.bloatGrade(r.bloat);
  const kb = $('kBloat'); kb.textContent = r.bloat == null ? '–' : `+${fmt(r.bloat)} ms · ${bg}`; kb.style.color = gradeColor(bg);
  const kd = $('kLd'); kd.textContent = `${fmt(r.loadedDown)} ms`; kd.style.color = pingColor(r.loadedDown);
  const ku = $('kLu'); ku.textContent = `${fmt(r.loadedUp)} ms`; ku.style.color = pingColor(r.loadedUp);
  // animate the score ring
  const t0 = performance.now();
  const anim = (t) => { const f = Math.min(1, (t - t0) / 1200); drawScoreRing((1 - Math.pow(1 - f, 3)) * score / 100, gc); if (f < 1) requestAnimationFrame(anim); };
  requestAnimationFrame(anim);

  const lv = { great: ['Great', C.lime], ok: ['Playable', C.amber], poor: ['Laggy', C.red] };
  $('readiness').innerHTML = Gaming.readiness(r).map(([t, d, l]) =>
    `<div class="ready-row"><div><b>${t}</b><small>${d}</small></div><span class="chip" style="--c:${lv[l][1]}">${lv[l][0]}</span></div>`).join('');

  const sorted = [...r.regions].sort((a, b) => (a.ms ?? 1e9) - (b.ms ?? 1e9));
  const maxMs = Math.max(60, ...sorted.map((g) => g.ms || 0));
  $('regions').innerHTML = sorted.map((g) => {
    const col = pingColor(g.ms);
    const f = Math.max(0.03, Math.min(1, (g.ms ?? maxMs) / maxMs));
    return `<div class="region"><span>${g.flag}</span><span>${g.name}</span><div class="bar"><i data-w="${(f * 100).toFixed(1)}%" style="background:linear-gradient(90deg,${col}80,${col})"></i></div><span class="ms" style="color:${col}">${g.ms == null ? '—' : fmt(g.ms) + ' ms'}</span></div>`;
  }).join('');
  requestAnimationFrame(() => document.querySelectorAll('#regions .bar i').forEach((el) => { el.style.width = el.dataset.w; }));

  const m = r.meta || {};
  const rows = [['Network', r.net.type]];
  if (r.net.effective) rows.push(['Browser estimate', r.net.effective.toUpperCase()]);
  if (m.isp) rows.push(['Provider', m.isp]);
  if (m.colo) rows.push(['Test server', [m.city, m.colo].filter(Boolean).join(' · ')]);
  if (m.ip) rows.push(['Public IP', m.ip.includes(':') ? m.ip.split(':').slice(0, 3).join(':') + ':•••' : m.ip.replace(/\.\d+$/, '.•••')]);
  rows.push(['Data used', `${fmt(r.dataMb)} MB`]);
  $('conn').innerHTML = rows.map(([k, v]) => `<div class="kv"><span>${k}</span><b>${escapeHtml(v)}</b></div>`).join('');
}

function escapeHtml(s) { return String(s).replace(/[&<>"']/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch]); }

async function shareResult() {
  const r = state.result; if (!r) return;
  const grade = Gaming.grade(Gaming.score(r));
  const text = `My gaming connection: ${grade} on Kitatool\n↓ ${fmtSpeed(r.down)} Mbps · ↑ ${fmtSpeed(r.up)} Mbps · Ping ${fmt(r.ping)} ms · Jitter ${fmt(r.jitter, 1)} ms\nTest yours: https://kitatool.com`;
  try {
    if (navigator.share) await navigator.share({ title: 'Kitatool result', text });
    else { await navigator.clipboard.writeText(text); toast('Result copied'); }
  } catch (e) {}
}

function toast(msg) {
  const el = document.createElement('div');
  el.textContent = msg;
  Object.assign(el.style, { position: 'fixed', left: '50%', bottom: '96px', transform: 'translateX(-50%)', background: 'rgba(30,32,44,.95)', padding: '10px 18px', borderRadius: '999px', fontSize: '14px', zIndex: 20 });
  document.body.appendChild(el); setTimeout(() => el.remove(), 1800);
}

/* =================================================================== live ping */

const LIVE_TARGETS = [{ name: 'Cloudflare', url: null }, ...REGIONS.map((g) => ({ name: g.name, url: regionUrl(g.r) }))];
const live = { target: LIVE_TARGETS[0], on: false, samples: [], sent: 0, lost: 0, run: 0 };
const LIVE_CAP = 120;

async function liveSample(t) {
  if (!t.url) return latencySample(null, 2000);
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 2000);
  const s = performance.now();
  try { await fetch(`${t.url}?x=${Math.random()}`, { mode: 'no-cors', cache: 'no-store', signal: ctl.signal }); return performance.now() - s; }
  finally { clearTimeout(timer); }
}

async function liveLoop(run) {
  await liveSample(live.target).catch(() => {}); // warm-up
  while (live.on && live.run === run) {
    const t0 = performance.now();
    let v = null;
    try { v = await liveSample(live.target); } catch (e) { v = null; }
    if (!live.on || live.run !== run) break;
    live.samples.push(v); live.sent++; if (v == null) live.lost++;
    if (live.samples.length > LIVE_CAP) live.samples.shift();
    renderLive();
    await sleep(Math.max(20, 250 - (performance.now() - t0)));
  }
}

let wakeLock = null;
async function setLive(on) {
  live.on = on; live.run++;
  const btn = $('liveBtn');
  btn.textContent = on ? 'STOP' : 'START'; btn.classList.toggle('on', on);
  if (on) {
    live.samples = []; live.sent = 0; live.lost = 0;
    try { wakeLock = await navigator.wakeLock?.request('screen'); } catch (e) {}
    liveLoop(live.run);
  } else {
    try { await wakeLock?.release(); } catch (e) {} wakeLock = null;
  }
  renderLive();
}

function renderLive() {
  const ok = live.samples.filter((v) => v != null);
  const cur = live.samples[live.samples.length - 1];
  const avg = ok.length ? ok.reduce((a, b) => a + b, 0) / ok.length : null;
  const jit = ok.length >= 2 ? jitterOf(ok) : null;
  const loss = live.sent ? (live.lost * 100) / live.sent : null;
  const spikes = avg != null ? ok.filter((v) => v > avg + 50).length : 0;
  const nowEl = $('liveNow');
  nowEl.textContent = !live.on ? '—' : live.samples.length && cur == null ? 'LOST' : fmt(cur);
  const col = live.on ? pingColor(cur ?? avg) : C.dim;
  nowEl.style.color = col;
  aurora.accent = live.on ? col : C.cyan;
  $('liveSub').textContent = live.on ? `ms · ${live.target.name}` : 'Tap start to monitor';
  const set = (id, v, color) => { const el = $(id); el.textContent = v; el.style.color = color || ''; };
  set('lAvg', fmt(avg), avg != null ? pingColor(avg) : '');
  set('lMin', fmt(ok.length ? Math.min(...ok) : null), C.lime);
  set('lMax', fmt(ok.length ? Math.max(...ok) : null), ok.length ? pingColor(Math.max(...ok)) : '');
  set('lJit', fmt(jit, 1), jit == null ? '' : jit < 8 ? C.lime : C.amber);
  set('lLoss', fmt(loss, 1), loss == null ? '' : loss <= 0 ? C.lime : C.red);
  set('lSpk', String(spikes), spikes ? C.amber : C.lime);
  const card = $('liveCard');
  card.style.setProperty('--g', col); card.classList.toggle('glow', live.on);
  drawBars();
}

function drawBars() {
  const cv = $('bars');
  const { ctx, w, h } = fitCanvas(cv);
  ctx.clearRect(0, 0, w, h);
  const ok = live.samples.filter((v) => v != null);
  const maxV = Math.max(100, ...ok) * 1.1;
  const slot = w / LIVE_CAP, bw = Math.max(1.5, slot * 0.62);
  ctx.setLineDash([4, 4]); ctx.strokeStyle = 'rgba(255,255,255,0.10)'; ctx.lineWidth = 1;
  for (const g of [50, 100]) { const y = h - (g / maxV) * h; ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke(); }
  ctx.setLineDash([]);
  const x0 = w - slot * live.samples.length;
  live.samples.forEach((v, i) => {
    const x = x0 + i * slot;
    if (v == null) { ctx.fillStyle = 'rgba(255,77,94,0.85)'; ctx.fillRect(x, 0, bw, h); return; }
    const bh = Math.max(3, (v / maxV) * h);
    const col = pingColor(v);
    const g = ctx.createLinearGradient(0, h - bh, 0, h);
    g.addColorStop(0, col); g.addColorStop(1, col + '40');
    ctx.fillStyle = g;
    ctx.beginPath();
    if (ctx.roundRect) ctx.roundRect(x, h - bh, bw, bh, bw / 2); else ctx.rect(x, h - bh, bw, bh);
    ctx.fill();
  });
}

/* =================================================================== history view */

function renderHistory() {
  const list = History.load();
  $('histCount').textContent = `${list.length} test${list.length === 1 ? '' : 's'}`;
  $('clearBtn').classList.toggle('hidden', !list.length);
  if (!list.length) {
    $('histList').innerHTML = '<div class="card"><div class="card-title">No tests yet</div><p class="dim" style="font-size:13px;margin-top:4px">Run a test from the Test tab and your results will appear here.</p></div>';
    return;
  }
  const df = new Intl.DateTimeFormat(undefined, { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
  $('histList').innerHTML = list.map((r) => {
    const g = Gaming.grade(Gaming.score(r));
    const sub = [r.net?.type, r.meta?.isp].filter(Boolean).join(' · ');
    return `<div class="card">
      <div class="hist-head"><span class="g" style="color:${gradeColor(g)}">${g}</span><div><b>${df.format(new Date(r.time))}</b><small>${escapeHtml(sub)}</small></div></div>
      <div class="hist-stats">
        <div><label style="color:${C.cyan}">↓</label>${fmtSpeed(r.down)} <small>Mbps</small></div>
        <div><label style="color:${C.pink}">↑</label>${fmtSpeed(r.up)} <small>Mbps</small></div>
        <div><label style="color:${pingColor(r.ping)}">Ping</label>${fmt(r.ping)} <small>ms</small></div>
        <div><label style="color:${C.dim}">Jitter</label>${fmt(r.jitter, 1)} <small>ms</small></div>
      </div></div>`;
  }).join('');
}

/* =================================================================== wiring */

function showTab(name) {
  document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t.id === `tab-${name}`));
  document.querySelectorAll('.tabbar button').forEach((b) => b.classList.toggle('sel', b.dataset.tab === name));
  if (name !== 'live' && live.on) setLive(false);
  if (name === 'history') renderHistory();
  if (name === 'live') renderLive();
  aurora.accent = name === 'history' ? C.violet : C.cyan;
  window.scrollTo({ top: 0 });
}

function init() {
  $('goBtn').onclick = startTest;
  $('againBtn').onclick = () => { window.scrollTo({ top: 0, behavior: 'smooth' }); startTest(); };
  $('cancelBtn').onclick = () => state.ctl?.abort('cancel');
  $('shareBtn').onclick = shareResult;
  $('clearBtn').onclick = () => { History.clear(); renderHistory(); };
  $('liveBtn').onclick = () => setLive(!live.on);
  document.querySelectorAll('.tabbar button').forEach((b) => { b.onclick = () => showTab(b.dataset.tab); });

  $('targets').innerHTML = LIVE_TARGETS.map((t, i) => `<button data-i="${i}" class="${i === 0 ? 'sel' : ''}">${t.name}</button>`).join('');
  $('targets').querySelectorAll('button').forEach((b) => {
    b.onclick = () => {
      live.target = LIVE_TARGETS[+b.dataset.i];
      $('targets').querySelectorAll('button').forEach((x) => x.classList.toggle('sel', x === b));
      if (live.on) { setLive(false); setLive(true); } else renderLive();
    };
  });

  const n = netInfo();
  const chip = $('netChip');
  chip.textContent = n.type;
  chip.style.setProperty('--c', n.type === 'Offline' ? C.red : C.cyan);
  window.addEventListener('online', () => { chip.textContent = netInfo().type; chip.style.setProperty('--c', C.cyan); });
  window.addEventListener('offline', () => { chip.textContent = 'Offline'; chip.style.setProperty('--c', C.red); });

  renderHistory();
  if ('serviceWorker' in navigator && location.protocol === 'https:') navigator.serviceWorker.register('sw.js').catch(() => {});

  let last = performance.now();
  const frame = (t) => {
    const dt = t - last; last = t;
    drawAurora(t);
    if ($('tab-test').classList.contains('active')) {
      drawGauge(dt);
      if (state.running) {
        const rv = $('readValue');
        if (state.phase === 'download' || state.phase === 'upload') { rv.textContent = fmtSpeed(state.live); rv.style.color = '#fff'; }
        else { rv.textContent = fmt(state.latency); rv.style.color = pingColor(state.latency); }
      }
      if (!$('graphCard').classList.contains('hidden')) {
        const cv = $('graph');
        if (state.phase === 'ping') drawLine(cv, [{ data: state.pingS, color: C.lime, cap: 24 }]);
        else if (state.phase === 'download') drawLine(cv, [{ data: state.downS, color: C.cyan }]);
        else drawLine(cv, [{ data: state.downS, color: C.cyan }, { data: state.upS, color: C.pink }]);
      }
    }
    requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
}

document.addEventListener('DOMContentLoaded', init);
