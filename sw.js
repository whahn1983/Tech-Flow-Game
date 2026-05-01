// Bump CACHE_NAME on every released change. The activate handler purges any
// caches that don't match this name, so old assets are evicted on first load
// after a deploy.
const CACHE_NAME = 'tech-flow-runner-v9';

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
// The MP3 is excluded — at ~7MB it's lazily fetched on first playback instead.
const OPTIONAL_ASSETS = ['/icons/icon-192.png', '/icons/icon-512.png'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE_NAME)
      .then((cache) => cache.addAll(CRITICAL_ASSETS))
      .then(() =>
        caches
          .open(CACHE_NAME)
          .then((cache) =>
            Promise.all(OPTIONAL_ASSETS.map((url) => cache.add(url).catch(() => {})))
          )
      )
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key)))
      )
      .then(() => self.clients.claim())
  );
});

// Static asset extensions cached cache-first. Audio is excluded — the player
// streams it lazily and we don't want a multi-megabyte cache entry per visitor.
const STATIC_REGEX = /\.(?:css|js|png|jpg|jpeg|svg|webp|woff2?)(?:\?.*)?$/;

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
          // Only cache successful, basic (same-origin) responses to avoid
          // poisoning the cache with opaque or error responses.
          if (networkResponse.ok && networkResponse.type === 'basic') {
            const clone = networkResponse.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
          }
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
        if (networkResponse.ok && networkResponse.type === 'basic') {
          const clone = networkResponse.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        }
        return networkResponse;
      })
      .catch(() =>
        caches
          .match(event.request)
          .then((cachedResponse) => cachedResponse || caches.match('/index.html'))
      )
  );
});
