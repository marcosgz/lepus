// Service Worker Manager - Handles service worker registration and updates
class ServiceWorkerManager {
  constructor() {
    this.registration = null;
  }

  // Register service worker
  async register() {
    if (!('serviceWorker' in navigator)) {
      console.warn('Service Worker not supported');
      return false;
    }

    try {
      this.registration = await navigator.serviceWorker.register('/sw.js');
      console.log('Service Worker registered successfully:', this.registration.scope);

      // Check for updates
      this.registration.addEventListener('updatefound', () => {
        const newWorker = this.registration.installing;
        newWorker.addEventListener('statechange', () => {
          if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
            console.log('New service worker available. Reload to update.');
            this.showUpdateNotification();
          }
        });
      });

      // Wait for service worker to be ready
      await navigator.serviceWorker.ready;
      console.log('Service Worker ready');
      return true;
    } catch (error) {
      console.warn('Service Worker registration failed:', error);
      return false;
    }
  }

  // Show update notification (optional enhancement)
  showUpdateNotification() {
    // You could implement a notification here to prompt users to reload
    // For now, we'll just log it
    console.log('Update available - consider implementing user notification');
  }

  // Unregister service worker (for development/testing)
  async unregister() {
    if (this.registration) {
      await this.registration.unregister();
      console.log('Service Worker unregistered');
    }
  }

  // Check if service worker is active
  isActive() {
    return navigator.serviceWorker.controller !== null;
  }

  // Get service worker registration
  getRegistration() {
    return this.registration;
  }
}

// Export for use in other modules
window.ServiceWorkerManager = ServiceWorkerManager;
