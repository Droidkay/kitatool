// Kitatool service worker: caches the app shell so it opens instantly and installs as an app.
// Speed-test traffic (Cloudflare, AWS) is never cached.
const CACHE = 'kitatool-v4';
const SHELL = ['/', '/index.html', '/style.css', '/app.js', '/icon.svg', '/manifest.webmanifest', '/save.html', '/save.css', '/save.js', '/nepa.html', '/nepa.css', '/nepa.js', '/nepa/lgas.json'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (url.origin !== location.origin || e.request.method !== 'GET') return;
  // Network first, so updates show up straight away; cache when offline.
  e.respondWith(
    fetch(e.request).then((res) => {
      const copy = res.clone();
      caches.open(CACHE).then((c) => c.put(e.request, copy));
      return res;
    }).catch(() => caches.match(e.request).then((r) => r || caches.match('/index.html')))
  );
});
