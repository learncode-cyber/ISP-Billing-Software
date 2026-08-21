// AR Qudrix ISP OS — Service Worker
// Enables offline functionality, caching strategy, and background sync

const CACHE_VERSION = 'v1.0.0';
const CACHE_NAMES = {
  static: `${CACHE_VERSION}-static`,
  dynamic: `${CACHE_VERSION}-dynamic`,
  api: `${CACHE_VERSION}-api`
};

const STATIC_ASSETS = [
  '/',
  '/index.html',
  '/manifest.json',
  '/css/app.css',
  '/js/app.js',
  '/images/icon-192x192.png',
  '/images/icon-512x512.png'
];

const API_ROUTES = [
  '/api/dashboards',
  '/api/customers',
  '/api/billing',
  '/api/network/devices',
  '/api/support/tickets'
];

const NETWORK_TIMEOUT = 5000; // 5 seconds

// Install event: Cache static assets
self.addEventListener('install', (event) => {
  console.log('[SW] Installing service worker...');
  
  event.waitUntil(
    caches.open(CACHE_NAMES.static).then((cache) => {
      console.log('[SW] Caching static assets');
      return cache.addAll(STATIC_ASSETS).catch((err) => {
        console.warn('[SW] Some static assets failed to cache:', err);
        // Continue even if some assets fail to cache
      });
    }).then(() => self.skipWaiting())
  );
});

// Activate event: Clean up old caches
self.addEventListener('activate', (event) => {
  console.log('[SW] Activating service worker...');
  
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames
          .filter((name) => !Object.values(CACHE_NAMES).includes(name))
          .map((name) => {
            console.log('[SW] Deleting old cache:', name);
            return caches.delete(name);
          })
      );
    }).then(() => self.clients.claim())
  );
});

// Fetch event: Implement caching strategy
self.addEventListener('fetch', (event) => {
  const { request } = event;
  const { method, url } = request;

  // Skip non-GET requests
  if (method !== 'GET') {
    event.respondWith(fetch(request));
    return;
  }

  // API requests: Network-first strategy with cache fallback
  if (url.includes('/api/')) {
    event.respondWith(networkFirstStrategy(request));
    return;
  }

  // HTML pages: Network-first
  if (request.headers.get('accept')?.includes('text/html')) {
    event.respondWith(networkFirstStrategy(request));
    return;
  }

  // Static assets: Cache-first
  event.respondWith(cacheFirstStrategy(request));
});

// Network-first strategy: Try network, fall back to cache
async function networkFirstStrategy(request) {
  try {
    const response = await Promise.race([
      fetch(request),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('Network timeout')), NETWORK_TIMEOUT)
      )
    ]);

    if (!response.ok) throw new Error(`HTTP ${response.status}`);

    // Cache successful responses
    const cache = await caches.open(CACHE_NAMES.api);
    cache.put(request, response.clone());

    return response;
  } catch (error) {
    console.log('[SW] Network failed, trying cache:', request.url);
    const cached = await caches.match(request);
    if (cached) return cached;

    // Offline fallback
    return new Response(
      JSON.stringify({
        error: 'offline',
        message: 'You are offline. Showing cached data.',
        data: null
      }),
      {
        status: 503,
        statusText: 'Service Unavailable',
        headers: { 'Content-Type': 'application/json' }
      }
    );
  }
}

// Cache-first strategy: Try cache, fall back to network
async function cacheFirstStrategy(request) {
  const cached = await caches.match(request);
  if (cached) return cached;

  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(CACHE_NAMES.dynamic);
      cache.put(request, response.clone());
    }
    return response;
  } catch (error) {
    console.warn('[SW] Fetch failed:', request.url);
    return new Response('Offline - Asset not cached', { status: 503 });
  }
}

// Background sync: Sync pending requests when online
self.addEventListener('sync', (event) => {
  console.log('[SW] Background sync event:', event.tag);

  if (event.tag === 'sync-pending-requests') {
    event.waitUntil(syncPendingRequests());
  }
});

async function syncPendingRequests() {
  try {
    const db = await openIndexedDB();
    const outbox = await db.getAll('outbox');

    for (const request of outbox) {
      try {
        const response = await fetch(request.url, {
          method: request.method,
          headers: request.headers,
          body: request.body
        });

        if (response.ok) {
          await db.delete('outbox', request.id);
          console.log('[SW] Synced request:', request.id);
        }
      } catch (err) {
        console.warn('[SW] Failed to sync:', request.id, err);
      }
    }

    // Notify clients that sync is complete
    const clients = await self.clients.matchAll();
    clients.forEach((client) => {
      client.postMessage({
        type: 'SYNC_COMPLETE',
        count: outbox.length
      });
    });
  } catch (err) {
    console.error('[SW] Sync failed:', err);
  }
}

// Handle messages from clients
self.addEventListener('message', (event) => {
  console.log('[SW] Message from client:', event.data);

  if (event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }

  if (event.data.type === 'CLEAR_CACHE') {
    caches.keys().then((names) => {
      names.forEach((name) => {
        if (name.startsWith('v')) {
          caches.delete(name);
        }
      });
    });
  }

  if (event.data.type === 'CACHE_URLS') {
    caches.open(CACHE_NAMES.dynamic).then((cache) => {
      cache.addAll(event.data.urls);
    });
  }
});

// Notifications: Handle notification clicks
self.addEventListener('notificationclick', (event) => {
  console.log('[SW] Notification clicked:', event.notification.tag);
  event.notification.close();

  const urlToOpen = event.notification.data?.url || '/';
  event.waitUntil(
    clients.matchAll({ type: 'window' }).then((clientList) => {
      // Check if window already exists
      for (let i = 0; i < clientList.length; i++) {
        if (clientList[i].url === urlToOpen && 'focus' in clientList[i]) {
          return clientList[i].focus();
        }
      }
      // Open new window
      if (clients.openWindow) {
        return clients.openWindow(urlToOpen);
      }
    })
  );
});

// IndexedDB helper
function openIndexedDB() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('arqudrix', 1);

    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(wrapDB(request.result));

    request.onupgradeneeded = (event) => {
      const db = event.target.result;
      if (!db.objectStoreNames.contains('outbox')) {
        db.createObjectStore('outbox', { keyPath: 'id' });
      }
    };
  });
}

function wrapDB(db) {
  return {
    getAll(storeName) {
      return new Promise((resolve, reject) => {
        const transaction = db.transaction([storeName], 'readonly');
        const store = transaction.objectStore(storeName);
        const request = store.getAll();
        request.onerror = () => reject(request.error);
        request.onsuccess = () => resolve(request.result);
      });
    },
    delete(storeName, key) {
      return new Promise((resolve, reject) => {
        const transaction = db.transaction([storeName], 'readwrite');
        const store = transaction.objectStore(storeName);
        const request = store.delete(key);
        request.onerror = () => reject(request.error);
        request.onsuccess = () => resolve();
      });
    }
  };
}

console.log('[SW] Service Worker registered and ready');
