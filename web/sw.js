// The dashboard no longer works offline. This worker replaces the old caching
// one: it deletes the caches that one left behind, unregisters itself and
// reloads the open dashboard tabs once so they load straight from the server.

self.addEventListener("install", () => self.skipWaiting());

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter((key) => key.startsWith("lepus-dashboard")).map((key) => caches.delete(key)));
    await self.registration.unregister();
    const clients = await self.clients.matchAll({ type: "window" });
    for (const client of clients) client.navigate(client.url);
  })());
});
