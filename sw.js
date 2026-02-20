const CACHE_NAME = 'tech-flow-runner-v4';

// Critical assets: all must be cached for the install event to succeed.
const CRITICAL_ASSETS = [
  '/',
  '/index.html',
  '/manifest.json',
  '/favicon.svg',
  '/apple-touch-icon.png',
];

// Large or optional assets: cached opportunistically so a fetch failure
// (slow network, file missing in a deploy) does not abort SW installation.
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

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  const pathName = new URL(event.request.url).pathname;
  if (pathName.startsWith('/api/') || pathName.endsWith('/leaderboard.php')) return;

  event.respondWith(
    caches.match(event.request).then((cachedResponse) => {
      if (cachedResponse) return cachedResponse;
      return fetch(event.request)
        .then((networkResponse) => {
          const clone = networkResponse.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
          return networkResponse;
        })
        .catch(() => caches.match('/index.html'));
    })
  );
});
