// Bootstrap the Lepus dashboard. Kept in a separate file (rather than an
// inline <script>) so it runs under a strict Content Security Policy that
// forbids `unsafe-inline`, which is the default for many Rails apps.
(async function () {
  const offlineManager = new OfflineManager();
  const serviceWorkerManager = new ServiceWorkerManager();

  document.querySelectorAll("[data-offline-action='reload']").forEach((el) => {
    el.addEventListener("click", () => window.location.reload());
  });
  document.querySelectorAll("[data-offline-action='dismiss']").forEach((el) => {
    el.addEventListener("click", () => {
      const c = document.getElementById("offline-content");
      if (c) c.style.display = "none";
    });
  });

  await serviceWorkerManager.register();
  await offlineManager.initialize();
})();
