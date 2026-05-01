const CACHE_NAME = 'tech-flow-runner-v6';

// Critical assets: must be cached for the install event to succeed.
const CRITICAL_ASSETS = [
  '/',
  '/index.html',
  '/manifest.json',
  '/favicon.svg',
  '/apple-touch-icon.png',
  '/css/styles.css',
  '/js/game.js',
];

// Optional assets: cached opportunistically so failures here don't abort install.
const OPTIONAL_ASSETS = [
  '/icons/icon-192.png',
  '/icons/icon-512.png',
  '/Tech%20Flow.mp3',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(CRITICAL_ASSETS))
      .then(() =>
        caches.open(CACHE_NAME).then((cache) =>
          Promise.all(OPTIONAL_ASSETS.map((url) => cache.add(url).catch(() => {})))
        )
      )
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key)))
    ).then(() => self.clients.claim())
  );
});

const STATIC_REGEX = /\.(?:css|js|png|jpg|jpeg|svg|webp|woff2?|mp3|ogg)(?:\?.*)?$/;

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;

  const url = new URL(event.request.url);

  // Never cache leaderboard / API requests; always go to the network.
  if (url.pathname.startsWith('/api/') || url.pathname.endsWith('/leaderboard.php')) return;

  // Cache-first for hashed/static assets — they rarely change and benefit from being instant offline.
  if (STATIC_REGEX.test(url.pathname)) {
    event.respondWith(
      caches.match(event.request).then((cached) => {
        if (cached) return cached;
        return fetch(event.request).then((networkResponse) => {
          const clone = networkResponse.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
          return networkResponse;
        });
      })
    );
    return;
  }

  // Network-first for HTML / navigation — keeps users on the latest UI when online,
  // falls back to cached index.html when offline.
  event.respondWith(
    fetch(event.request)
      .then((networkResponse) => {
        const clone = networkResponse.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        return networkResponse;
      })
      .catch(() =>
        caches.match(event.request).then((cachedResponse) => cachedResponse || caches.match('/index.html'))
      )
  );
});
