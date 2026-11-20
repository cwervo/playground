// Offline support for the installed app. Flutter no longer generates a
// caching service worker, so this small one keeps the app shell available.
//
// Only same-origin GETs are cached. Requests to model providers are never
// touched: they go straight to the network, and API keys never pass through
// this file.
const CACHE = 'switchboard-v1';

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      for (const name of await caches.keys()) {
        if (name !== CACHE) await caches.delete(name);
      }
      await self.clients.claim();
    })(),
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== self.location.origin) {
    return;
  }
  event.respondWith(
    (async () => {
      const cache = await caches.open(CACHE);
      const cached = await cache.match(req);
      const fresh = fetch(req)
        .then((res) => {
          if (res.ok) cache.put(req, res.clone());
          return res;
        })
        .catch(() => undefined);
      // The page itself: prefer the network so a new release shows up on the
      // next load. Everything else: answer from cache, refresh in background.
      if (req.mode === 'navigate') {
        return (await fresh) || cached || Response.error();
      }
      if (cached) {
        event.waitUntil(fresh);
        return cached;
      }
      return (await fresh) || Response.error();
    })(),
  );
});
