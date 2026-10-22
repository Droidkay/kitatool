// Kitatool Save: paste a TikTok / Instagram / X / Facebook / Pinterest link and download the media.
// Talks to the download server set in window.KITA_SAVE_API (see server/ in this repo).
(() => {
  const API = (window.KITA_SAVE_API || '').replace(/\/$/, '');
  const $ = (id) => document.getElementById(id);
  const PLATFORMS = [
    ['tiktok', /(^|\.)(tiktok\.com|tiktokv\.com)$/, 'TikTok', '#FF4FD8'],
    ['instagram', /(^|\.)(instagram\.com|instagr\.am)$/, 'Instagram', '#B15CFF'],
    ['x', /(^|\.)(x\.com|twitter\.com)$/, 'X', '#E6E8EF'],
    ['facebook', /(^|\.)(facebook\.com|fb\.watch|fb\.com)$/, 'Facebook', '#2F7BFF'],
    ['pinterest', /(^|\.)(pinterest\.[a-z.]+|pin\.it)$/, 'Pinterest', '#FF4D5E'],
  ];
  const ICON = {
    video: '<svg viewBox="0 0 24 24"><rect x="3" y="5" width="13" height="14" rx="3"/><path d="M16 10l5-3v10l-5-3"/></svg>',
    audio: '<svg viewBox="0 0 24 24"><path d="M9 18V6l11-2v12"/><circle cx="6" cy="18" r="3"/><circle cx="17" cy="16" r="3"/></svg>',
    image: '<svg viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="16" rx="3"/><circle cx="9" cy="10" r="2"/><path d="M21 16l-5-5-9 9"/></svg>',
  };
  let serverUp = false;

  function findUrl(text) {
    const m = (text || '').match(/https?:\/\/[^\s"'<>]+/i);
    return m ? m[0].replace(/[),.]+$/, '') : '';
  }
  function platformOf(url) {
    try {
      const h = new URL(url).hostname.toLowerCase();
      return PLATFORMS.find(([, rx]) => rx.test(h)) || null;
    } catch (e) { return null; }
  }
  function show(id, on) { $(id).classList.toggle('hidden', !on); }
  function status(title, text) { $('statusTitle').textContent = title; $('statusText').textContent = text || ''; show('status', true); }
  function fail(msg) { show('status', false); show('result', false); $('errorText').textContent = msg; show('errorCard', true); }
  function esc(s) { return String(s || '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }

  function highlight() {
    const p = platformOf($('url').value.trim());
    document.querySelectorAll('#platforms span').forEach((s) => s.classList.toggle('on', !!p && s.dataset.p === p[0]));
    $('goBtn').querySelector('span').textContent = p && p[0] === 'instagram' ? 'Get video or photos' : 'Get video';
  }

  // ---------------------------------------------------------------- server wake-up
  async function ping() {
    if (!API) { setChip('Not set up', 'var(--red)'); return false; }
    const slow = setTimeout(() => setChip('Waking server…', 'var(--amber)'), 2500);
    try {
      const r = await fetch(`${API}/api/health`, { cache: 'no-store' });
      clearTimeout(slow);
      serverUp = r.ok;
      setChip(serverUp ? 'Ready' : 'Server error', serverUp ? 'var(--lime)' : 'var(--red)');
      return serverUp;
    } catch (e) {
      clearTimeout(slow);
      setChip('Offline', 'var(--red)');
      return false;
    }
  }
  function setChip(t, c) { $('srvChip').textContent = t; $('srvChip').style.setProperty('--c', c); }

  async function api(path, tries = 2) {
    for (let i = 0; i < tries; i++) {
      try {
        const r = await fetch(`${API}${path}`, { cache: 'no-store' });
        const j = await r.json().catch(() => ({}));
        if (!r.ok) throw Object.assign(new Error(j.error || `Server error (${r.status})`), { final: r.status < 500 || r.status === 504 });
        return j;
      } catch (e) {
        if (e.final || i === tries - 1) throw e;
        status('Waking up the server…', 'The free server sleeps when nobody uses it. First use can take up to a minute.');
        await new Promise((res) => setTimeout(res, 4000));
      }
    }
  }

  // ---------------------------------------------------------------- read a post
  async function go(e) {
    if (e) e.preventDefault();
    const url = findUrl($('url').value.trim());
    show('errorCard', false);
    show('result', false);
    if (!url) return fail('Paste the post link first. In TikTok or Instagram tap Share → Copy link.');
    if (!platformOf(url)) return fail('That link isn\'t from TikTok, Instagram, X, Facebook or Pinterest.');
    $('url').value = url;
    $('goBtn').disabled = true;
    status('Reading the post…', serverUp ? '' : 'Waking the server, this can take up to a minute the first time.');
    try {
      if (!serverUp) await ping();
      const info = await api(`/api/info?url=${encodeURIComponent(url)}`, 3);
      render(info);
    } catch (err) {
      fail(err.message || 'Something went wrong. Try again.');
    } finally {
      $('goBtn').disabled = false;
      show('status', false);
    }
  }

  function render(info) {
    const p = PLATFORMS.find(([k]) => k === info.platform);
    $('resPlatform').textContent = p ? p[2] : info.platform;
    $('resPlatform').style.setProperty('--c', p ? p[3] : 'var(--cyan)');
    $('resAuthor').textContent = info.author ? `@${String(info.author).replace(/^@/, '')}` : (p ? p[2] : '');
    $('resTitle').textContent = info.title || '';
    const img = $('resThumb');
    if (info.thumbnail) {
      img.referrerPolicy = 'no-referrer';
      img.src = info.thumbnail;
      img.onerror = () => { img.removeAttribute('src'); };
    } else img.removeAttribute('src');

    const box = $('items');
    box.innerHTML = '';
    const colors = { video: 'var(--cyan)', audio: 'var(--pink)', image: 'var(--violet)' };
    info.items.forEach((it) => {
      const b = document.createElement('button');
      b.className = 'item';
      b.style.setProperty('--c', colors[it.kind] || 'var(--cyan)');
      const sub = it.kind === 'video' ? (info.platform === 'tiktok' ? 'MP4 · no watermark' : 'MP4')
        : it.kind === 'audio' ? 'M4A audio' : 'JPG';
      const thumb = it.kind === 'image' && it.thumb ? `<img src="${esc(it.thumb)}" referrerpolicy="no-referrer" alt="">` : ICON[it.kind] || ICON.video;
      b.innerHTML = `<span class="ic">${thumb}</span><span class="tx"><b>${esc(it.label)}</b><small>${sub}</small></span><span class="dl">Save</span><span class="bar"></span>`;
      b.onclick = () => download(b, it);
      box.appendChild(b);
    });
    if (info.items.filter((i) => i.kind === 'image').length > 1) {
      const all = document.createElement('button');
      all.className = 'ghost';
      all.textContent = 'Save all photos';
      all.onclick = async () => { for (const el of box.querySelectorAll('.item')) if (!el.classList.contains('done')) await el.onclick(); };
      box.appendChild(all);
    }
    show('result', true);
    $('result').scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  // ---------------------------------------------------------------- download with progress
  async function download(btn, it) {
    if (btn.dataset.busy) return;
    btn.dataset.busy = '1';
    const dl = btn.querySelector('.dl'), bar = btn.querySelector('.bar');
    dl.textContent = it.kind === 'image' ? 'Saving…' : 'Preparing…';
    try {
      const r = await fetch(`${API}${it.file}`, { cache: 'no-store' });
      if (!r.ok) {
        const j = await r.json().catch(() => ({}));
        throw new Error(j.error || `Server error (${r.status})`);
      }
      const total = +r.headers.get('Content-Length') || 0;
      const name = (/filename="([^"]+)"/.exec(r.headers.get('Content-Disposition') || '') || [])[1] || 'kitatool';
      const reader = r.body.getReader();
      const chunks = [];
      let got = 0;
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        chunks.push(value);
        got += value.length;
        if (total) { bar.style.width = `${Math.round((got / total) * 100)}%`; dl.textContent = `${Math.round((got / total) * 100)}%`; }
        else dl.textContent = `${(got / 1048576).toFixed(1)} MB`;
      }
      const blob = new Blob(chunks, { type: r.headers.get('Content-Type') || 'application/octet-stream' });
      await saveBlob(blob, name);
      bar.style.width = '100%';
      dl.textContent = 'Saved';
      btn.classList.add('done');
    } catch (err) {
      dl.textContent = 'Retry';
      bar.style.width = '0';
      fail(err.message || 'Download failed. Try again.');
      show('result', true);
    } finally {
      delete btn.dataset.busy;
    }
  }

  async function saveBlob(blob, name) {
    // On phones, the share sheet lets you "Save video" / "Save image" straight to the gallery.
    const file = new File([blob], name, { type: blob.type });
    const isPhone = /Android|iPhone|iPad/i.test(navigator.userAgent);
    if (isPhone && navigator.canShare && navigator.canShare({ files: [file] })) {
      try { await navigator.share({ files: [file] }); return; } catch (e) { if (e.name === 'AbortError') return; }
    }
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = name;
    document.body.appendChild(a);
    a.click();
    setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 4000);
  }

  // ---------------------------------------------------------------- wiring
  $('form').addEventListener('submit', go);
  $('url').addEventListener('input', highlight);
  $('pasteBtn').addEventListener('click', async () => {
    try {
      const t = await navigator.clipboard.readText();
      const u = findUrl(t);
      $('url').value = u || t;
      highlight();
      if (u && platformOf(u)) go();
    } catch (e) {
      $('url').focus();
      setChip('Long-press the box to paste', 'var(--amber)');
    }
  });

  // Shared from another app (Android "Share → Kitatool") or opened as save.html?url=…
  const q = new URLSearchParams(location.search);
  const shared = findUrl(q.get('url') || q.get('text') || q.get('title') || '');
  ping().then(() => { if (shared) { $('url').value = shared; highlight(); go(); } });
  if (shared) { $('url').value = shared; highlight(); }
  if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => {});
})();
