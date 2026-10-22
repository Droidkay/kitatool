// Light Dey? — live NEPA tracker. Talks to the Supabase database set in nepa/config.json.
(() => {
  const $ = (id) => document.getElementById(id);
  const store = {
    get(k, d) { try { const v = localStorage.getItem('nepa.' + k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } },
    set(k, v) { try { localStorage.setItem('nepa.' + k, JSON.stringify(v)); } catch (e) {} },
  };
  let CFG = null, LGAS = {}, area = store.get('area', null), scope = store.get('scope', 'state'), last = null, timer = 0;

  function deviceId() {
    let id = store.get('device', '');
    if (!/^[A-Za-z0-9_-]{12,64}$/.test(id)) {
      const a = new Uint8Array(16);
      (window.crypto || {}).getRandomValues ? crypto.getRandomValues(a) : a.forEach((_, i) => { a[i] = Math.random() * 256; });
      id = 'w' + Array.from(a, (b) => b.toString(16).padStart(2, '0')).join('');
      store.set('device', id);
    }
    return id;
  }

  async function rpc(fn, args) {
    if (!CFG || !CFG.url || !CFG.key) throw new Error('The tracker isn\'t set up yet. Check back soon.');
    const r = await fetch(`${CFG.url.replace(/\/$/, '')}/rest/v1/rpc/${fn}`, {
      method: 'POST',
      headers: { apikey: CFG.key, Authorization: `Bearer ${CFG.key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(args || {}),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) throw new Error((j && j.message) || `Server error (${r.status})`);
    return j;
  }

  // ---------------------------------------------------------------- formatting
  function dur(min) {
    min = Math.max(0, Math.round(min));
    const h = Math.floor(min / 60), m = min % 60;
    return h ? (m ? `${h}h ${m}m` : `${h}h`) : `${m}m`;
  }
  function ago(iso) { return (Date.now() - new Date(iso).getTime()) / 60000; }
  function hrs(min) { return (min / 60).toFixed(min >= 600 ? 0 : 1).replace(/\.0$/, '') + 'h'; }
  function esc(s) { return String(s || '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }
  function toast(t) {
    let el = document.querySelector('.toast');
    if (!el) { el = document.createElement('div'); el.className = 'toast'; document.body.appendChild(el); }
    el.textContent = t; el.classList.add('show');
    clearTimeout(el._t); el._t = setTimeout(() => el.classList.remove('show'), 2600);
  }
  function err(title, text) { $('errTitle').textContent = title; $('errText').textContent = text; $('errCard').classList.remove('hidden'); }
  function clearErr() { $('errCard').classList.add('hidden'); }
  function setChip(t, c) { $('liveChip').textContent = t; $('liveChip').style.setProperty('--c', c); }

  // ---------------------------------------------------------------- area setup
  function fillStates() {
    const s = $('selState');
    s.innerHTML = '<option value="">Choose state</option>' + Object.keys(LGAS).map((k) => `<option>${esc(k)}</option>`).join('');
    if (area) s.value = area.state;
    fillLgas();
  }
  function fillLgas() {
    const st = $('selState').value, l = $('selLga');
    l.innerHTML = '<option value="">Choose LGA</option>' + (LGAS[st] || []).map((k) => `<option>${esc(k)}</option>`).join('');
    if (area && area.state === st) l.value = area.lga;
    l.disabled = !st;
    loadHoods();
  }
  async function loadHoods() {
    const st = $('selState').value, lga = $('selLga').value;
    $('hoodList').innerHTML = '';
    if (!st || !lga) return;
    try {
      const list = await rpc('nepa_hoods', { p_state: st, p_lga: lga });
      $('hoodList').innerHTML = list.map((h) => `<option value="${esc(h)}">`).join('');
    } catch (e) { /* suggestions are optional */ }
  }
  function openSetup() {
    $('setup').classList.remove('hidden');
    $('mine').classList.add('hidden');
    if (area) $('inHood').value = area.hood;
    fillStates();
    $('setup').scrollIntoView({ behavior: 'smooth', block: 'start' });
  }
  function saveArea() {
    const st = $('selState').value, lga = $('selLga').value, hood = $('inHood').value.trim().replace(/\s+/g, ' ');
    if (!st || !lga) return toast('Pick your state and LGA');
    if (hood.length < 2) return toast('Type your area or street name');
    area = { state: st, lga, hood };
    store.set('area', area);
    $('setup').classList.add('hidden');
    refresh();
  }

  // ---------------------------------------------------------------- my area
  function renderMine(s) {
    const box = $('mine');
    box.classList.remove('hidden', 'on', 'off');
    document.body.classList.remove('lit', 'dark');
    $('mineHood').textContent = (s && s.hood) || area.hood;
    $('mineWhere').textContent = `${area.lga}, ${area.state}`;
    if (!s || s.status === 'unknown') {
      $('verdict').textContent = 'No reports yet';
      $('since').textContent = 'Be the first in your area. Tap below when light comes or goes.';
      $('todayHrs').textContent = '–';
      $('todayFill').style.width = '0';
      renderWeek(null);
      return;
    }
    const on = s.status === 'on';
    box.classList.add(on ? 'on' : 'off');
    document.body.classList.add(on ? 'lit' : 'dark');
    $('verdict').textContent = on ? 'Light dey!' : 'No light';
    const m = s.since ? ago(s.since) : 0;
    let line = m < 1 ? (on ? 'Just came on' : 'Just went off') : `${on ? 'On' : 'Gone'} for ${dur(m)}`;
    if (s.stale) line = `Last report ${dur(ago(s.last_at))} ago`;
    else line += ` · ${s.reporters} ${s.reporters === 1 ? 'report' : 'reports'} in the last 45 min`;
    $('since').textContent = line;
    $('todayHrs').textContent = `${dur(s.on_today_min)} of ${dur(s.today_min)}`;
    $('todayFill').style.width = `${s.today_min ? Math.min(100, (s.on_today_min / s.today_min) * 100) : 0}%`;
    renderWeek(s.week);
  }
  function renderWeek(week) {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const w = week || Array.from({ length: 7 }, (_, i) => ({ day: new Date(Date.now() - (6 - i) * 864e5).toISOString().slice(0, 10), on_min: 0 }));
    $('week').innerHTML = w.map((d, i) => {
      const pct = Math.min(100, (d.on_min / 1440) * 100);
      const dn = days[new Date(d.day + 'T12:00:00').getDay()];
      return `<div class="d ${i === 6 ? 'today' : ''} ${d.on_min ? '' : 'none'}"><b>${d.on_min ? hrs(d.on_min) : ''}</b><span class="col" style="height:${Math.max(3, pct * 0.62)}px"></span><small>${i === 6 ? 'Today' : dn}</small></div>`;
    }).join('');
  }

  async function report(on) {
    if (!area) return openSetup();
    const btns = [$('repOn'), $('repOff')];
    btns.forEach((b) => { b.disabled = true; });
    try {
      const s = await rpc('nepa_report', { p_state: area.state, p_lga: area.lga, p_hood: area.hood, p_status: on, p_device: deviceId(), p_source: 'tap' });
      if (s && s.hood && s.hood !== area.hood) { area.hood = s.hood; store.set('area', area); }
      last = s;
      renderMine(s);
      btns.forEach((b) => b.classList.remove('picked'));
      (on ? btns[0] : btns[1]).classList.add('picked');
      toast(on ? 'Thanks! Light dey for ' + area.hood : 'Thanks! Noted, no light for ' + area.hood);
      if (navigator.vibrate) navigator.vibrate(30);
      loadBoard();
    } catch (e) {
      toast(e.message);
    } finally {
      btns.forEach((b) => { b.disabled = false; });
    }
  }

  function share() {
    const s = last;
    let text;
    if (s && s.status === 'on') text = `Light dey for ${s.hood}, ${area.lga} 💡 On for ${dur(ago(s.since))}, ${dur(s.on_today_min)} today.`;
    else if (s && s.status === 'off') text = `No light for ${s.hood}, ${area.lga} 🌑 Gone for ${dur(ago(s.since))}. Only ${dur(s.on_today_min)} of light today.`;
    else text = `Is there light in your area right now?`;
    text += '\n\nCheck your area on Light Dey? 👇';
    const url = 'https://kitatool.com/nepa.html';
    if (navigator.share && /Android|iPhone|iPad/i.test(navigator.userAgent)) {
      navigator.share({ text, url }).catch(() => {});
    } else {
      window.open(`https://x.com/intent/post?text=${encodeURIComponent(text)}&url=${encodeURIComponent(url)}`, '_blank', 'noopener');
    }
  }

  // ---------------------------------------------------------------- board
  async function loadBoard() {
    const st = scope === 'state' && area ? area.state : null;
    try {
      const b = await rpc('nepa_board', { p_state: st, p_limit: 60 });
      $('pOn').textContent = b.on; $('pOff').textContent = b.off; $('pRep').textContent = b.reports_24h;
      const myKey = area ? [area.state, area.lga, area.hood].map(slug).join('|') : '';
      $('boardList').innerHTML = b.areas.length ? b.areas.map((a) => {
        const on = a.status === 'on';
        const st2 = a.status === 'unknown' ? 'No recent reports' : `${on ? 'Light' : 'No light'} · ${ago(a.since || a.last_at) < 1 ? 'now' : dur(ago(a.since || a.last_at))}`;
        return `<div class="row ${on ? 'on' : ''} ${a.stale ? 'stale' : ''} ${a.area === myKey ? 'me' : ''}">
          <span class="dot"></span>
          <div><b>${esc(a.hood)}</b><small>${esc(a.lga)}${st ? '' : ', ' + esc(a.state)}</small></div>
          <div class="rt"><div class="st">${st2}</div><small>${hrs(a.on_24h_min)} in 24h</small></div></div>`;
      }).join('') : `<div class="empty">No reports ${st ? 'in ' + esc(st) + ' ' : ''}in the last 24 hours yet. Set your area and tap when light comes or goes. Your neighbours will see it here.</div>`;
      setChip('Live', 'var(--lime)');
    } catch (e) {
      setChip('Offline', 'var(--red)');
      $('boardList').innerHTML = `<div class="empty">${esc(e.message)}</div>`;
    }
  }
  function slug(t) { return String(t || '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, ''); }

  async function refresh() {
    clearErr();
    if (area) {
      try {
        last = await rpc('nepa_status', { p_state: area.state, p_lga: area.lga, p_hood: area.hood });
        renderMine(last);
      } catch (e) {
        renderMine(null);
        err('Can\'t reach the tracker', e.message);
      }
    }
    await loadBoard();
  }

  // ---------------------------------------------------------------- start
  async function start() {
    try {
      [CFG, LGAS] = await Promise.all([
        fetch('nepa/config.json', { cache: 'no-store' }).then((r) => r.json()),
        fetch('nepa/lgas.json').then((r) => r.json()),
      ]);
    } catch (e) {
      err('Can\'t load', 'Check your connection and reload.');
      return;
    }
    $('selState').onchange = fillLgas;
    $('selLga').onchange = loadHoods;
    $('saveArea').onclick = saveArea;
    $('changeBtn').onclick = openSetup;
    $('repOn').onclick = () => report(true);
    $('repOff').onclick = () => report(false);
    $('shareBtn').onclick = share;
    document.querySelectorAll('#scope button').forEach((b) => {
      b.classList.toggle('sel', b.dataset.s === scope);
      b.onclick = () => {
        scope = b.dataset.s; store.set('scope', scope);
        document.querySelectorAll('#scope button').forEach((x) => x.classList.toggle('sel', x === b));
        loadBoard();
      };
    });
    if (!area) openSetup();
    await refresh();
    timer = setInterval(refresh, 60000);
    document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(); });
  }
  start();
  if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => {});
})();
