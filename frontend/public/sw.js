// sw.js — service worker for AR Qudrix ISP OS.
//
// Strategy:
//   • App shell (HTML/JS/CSS/icons): cache-first with a versioned cache, so
//     the app boots with zero network.
//   • Navigations: network-first, falling back to the cached shell — an SPA
//     deep link must still open offline.
//   • API GETs: NOT blanket-cached. Business data lives in IndexedDB where
//     it is tenant-scoped and purgeable on logout; caching API responses in
//     the Cache API would create a second, harder-to-purge copy of tenant
//     data. Only a small allowlist of non-sensitive endpoints is cached.
//   • API mutations: never cached, never intercepted — they go through the
//     app's outbox instead.

const VERSION = "v1.0.0";
const SHELL_CACHE = `arq-shell-${VERSION}`;
const RUNTIME_CACHE = `arq-runtime-${VERSION}`;

const SHELL_ASSETS = ["/", "/index.html", "/manifest.webmanifest"];

// Only these API paths may be runtime-cached: platform-level, non-tenant,
// non-sensitive. Everything else is deliberately excluded.
const CACHEABLE_API = ["/api/v1/compliance/news"];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(SHELL_CACHE)
      .then((c) => c.addAll(SHELL_ASSETS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  // Cache invalidation: drop every cache not belonging to this version.
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((k) => k !== SHELL_CACHE && k !== RUNTIME_CACHE)
            .map((k) => caches.delete(k))
      ))
      .then(() => self.clients.claim())
  );
});

// Let the page trigger an immediate update (used by the "new version
// available" prompt) — safe SW migration rather than a silent swap.
self.addEventListener("message", (event) => {
  if (event.data?.type === "SKIP_WAITING") self.skipWaiting();
  if (event.data?.type === "PURGE_CACHES") {
    caches.keys().then((keys) => keys.forEach((k) => caches.delete(k)));
  }
});

self.addEventListener("fetch", (event) => {
  const req = event.request;
  const url = new URL(req.url);

  // Never touch non-GET: mutations belong to the outbox, not the cache.
  if (req.method !== "GET") return;
  if (url.origin !== self.location.origin) return;

  // API requests
  if (url.pathname.startsWith("/api/")) {
    const allowed = CACHEABLE_API.some((p) => url.pathname.startsWith(p));
    if (!allowed) return; // pass through to network; app falls back to IndexedDB
    event.respondWith(staleWhileRevalidate(req));
    return;
  }

  // SPA navigations: network-first, cached shell as the offline fallback.
  if (req.mode === "navigate") {
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(SHELL_CACHE).then((c) => c.put("/index.html", copy));
          return res;
        })
        .catch(() => caches.match("/index.html").then((r) => r || offlineFallback()))
    );
    return;
  }

  // Static assets: cache-first (they are content-hashed by the build).
  event.respondWith(
    caches.match(req).then((hit) => hit || fetch(req).then((res) => {
      if (res.ok) {
        const copy = res.clone();
        caches.open(SHELL_CACHE).then((c) => c.put(req, copy));
      }
      return res;
    }).catch(() => offlineFallback()))
  );
});

function staleWhileRevalidate(req) {
  return caches.open(RUNTIME_CACHE).then((cache) =>
    cache.match(req).then((cached) => {
      const network = fetch(req).then((res) => {
        if (res.ok) cache.put(req, res.clone());
        return res;
      }).catch(() => cached);
      return cached || network;
    })
  );
}

function offlineFallback() {
  return new Response(
    "<!doctype html><meta charset=utf-8><title>Offline</title>" +
    "<body style='font-family:system-ui;padding:40px;text-align:center'>" +
    "<h1>You're offline</h1><p>Reopen the app to continue working with your cached data.</p>",
    { headers: { "Content-Type": "text/html" }, status: 200 }
  );
}

// Background Sync — an enhancement. The app's foreground `online` listener
// is the primary sync trigger because Background Sync support varies.
self.addEventListener("sync", (event) => {
  if (event.tag === "arq-outbox-sync") {
    event.waitUntil(
      self.clients.matchAll().then((clients) =>
        clients.forEach((c) => c.postMessage({ type: "SYNC_NOW" }))
      )
    );
  }
});
