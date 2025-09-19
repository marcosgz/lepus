// Service Worker for Lepus Web Dashboard
// Provides offline caching for static assets

const CACHE_NAME = 'lepus-dashboard-v1';
const STATIC_ASSETS = [
  '/',
  '/assets/css/styles.css',
  '/assets/js/app.js',
  '/assets/js/offline-manager.js',
  '/assets/js/service-worker-manager.js',
  '/assets/js/controllers/theme_controller.js',
  '/assets/js/controllers/connection_controller.js',
  '/assets/js/controllers/dashboard_controller.js',
  '/assets/js/controllers/queue_controller.js'
];

// Install event - cache static assets
self.addEventListener('install', (event) => {
  console.log('Service Worker: Installing...');
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => {
        console.log('Service Worker: Caching static assets');
        return cache.addAll(STATIC_ASSETS);
      })
      .then(() => {
        console.log('Service Worker: Installation complete');
        return self.skipWaiting();
      })
      .catch((error) => {
        console.error('Service Worker: Installation failed', error);
      })
  );
});

// Activate event - clean up old caches
self.addEventListener('activate', (event) => {
  console.log('Service Worker: Activating...');
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          if (cacheName !== CACHE_NAME) {
            console.log('Service Worker: Deleting old cache', cacheName);
            return caches.delete(cacheName);
          }
        })
      );
    }).then(() => {
      console.log('Service Worker: Activation complete');
      return self.clients.claim();
    })
  );
});

// Fetch event - serve from cache when offline
self.addEventListener('fetch', (event) => {
  // Only handle GET requests
  if (event.request.method !== 'GET') {
    return;
  }

  // Skip cross-origin requests
  if (!event.request.url.startsWith(self.location.origin)) {
    return;
  }

  event.respondWith(
    caches.match(event.request)
      .then((cachedResponse) => {
        // Return cached version if available
        if (cachedResponse) {
          console.log('Service Worker: Serving from cache', event.request.url);
          return cachedResponse;
        }

        // Otherwise, fetch from network
        console.log('Service Worker: Fetching from network', event.request.url);
        return fetch(event.request)
          .then((response) => {
            // Don't cache non-successful responses
            if (!response || response.status !== 200 || response.type !== 'basic') {
              return response;
            }

            // Clone the response for caching
            const responseToCache = response.clone();

            caches.open(CACHE_NAME)
              .then((cache) => {
                // Only cache static assets, not API responses
                const url = new URL(event.request.url);
                if (url.pathname.startsWith('/assets/') ||
                    url.pathname === '/' ||
                    url.pathname === '/index.html') {
                  console.log('Service Worker: Caching response', event.request.url);
                  cache.put(event.request, responseToCache);
                }
              });

            return response;
          })
          .catch((error) => {
            console.log('Service Worker: Network fetch failed', event.request.url, error);

            // For navigation requests, return the cached index.html
            if (event.request.mode === 'navigate') {
              return caches.match('/');
            }

            // For other requests, return a generic offline response
            if (event.request.url.endsWith('.js') || event.request.url.endsWith('.css')) {
              return new Response(
                '/* Offline - Resource not available */',
                {
                  status: 200,
                  headers: {
                    'Content-Type': event.request.url.endsWith('.js') ? 'application/javascript' : 'text/css'
                  }
                }
              );
            }

            throw error;
          });
      })
  );
});

// Handle messages from the main thread
self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});
