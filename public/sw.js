// Minimal service worker: enables installability for /admin.
// Network-only — never caches HTML or assets, so the panel is always up to date.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));
self.addEventListener("fetch", (event) => {
  event.respondWith(fetch(event.request));
});
