// Offline Manager - Handles offline detection and external dependency loading
class OfflineManager {
  constructor() {
    this.isOnline = navigator.onLine;
    this.stimulusLoaded = false;
    this.chartLoaded = false;
    this.initialized = false;

    this.setupEventListeners();
  }

  setupEventListeners() {
    // Set up online/offline event listeners
    window.addEventListener('online', () => {
      this.isOnline = true;
      this.hideOfflineBanner();
      this.hideOfflineContent();
    });

    window.addEventListener('offline', () => {
      this.isOnline = false;
      this.showOfflineBanner();
      this.showOfflineContent();
    });
  }

  // Function to show offline banner
  showOfflineBanner() {
    const banner = document.getElementById('offline-banner');
    if (banner) {
      banner.style.display = 'block';
    }
  }

  // Function to hide offline banner
  hideOfflineBanner() {
    const banner = document.getElementById('offline-banner');
    if (banner) {
      banner.style.display = 'none';
    }
  }

  // Function to show offline content
  showOfflineContent() {
    const content = document.getElementById('offline-content');
    const mainContent = document.querySelector('.stats-grid');
    if (content && mainContent) {
      content.style.display = 'flex';
      mainContent.style.display = 'none';
      // Hide other main sections
      document.querySelectorAll('.chart-grid, .processes-grid, .queues-grid').forEach(section => {
        section.style.display = 'none';
      });
    }
  }

  // Function to hide offline content
  hideOfflineContent() {
    const content = document.getElementById('offline-content');
    const mainContent = document.querySelector('.stats-grid');
    if (content && mainContent) {
      content.style.display = 'none';
      mainContent.style.display = 'grid';
      // Show other main sections
      document.querySelectorAll('.chart-grid, .processes-grid, .queues-grid').forEach(section => {
        section.style.display = 'grid';
      });
    }
  }

  // Function to load external scripts with fallback
  loadExternalScript(src, fallbackCode, onLoad) {
    const script = document.createElement('script');
    script.src = src;
    script.onload = function() {
      onLoad(true);
    };
    script.onerror = function() {
      console.warn('Failed to load external script:', src);
      if (fallbackCode) {
        // Execute fallback code
        eval(fallbackCode);
        onLoad(false);
      } else {
        onLoad(false);
      }
    };
    document.head.appendChild(script);
  }

  // Load Stimulus with fallback
  loadStimulus() {
    return new Promise((resolve) => {
      this.loadExternalScript(
        'https://unpkg.com/@hotwired/stimulus@3.2.2/dist/stimulus.umd.js',
        `
          // Minimal Stimulus fallback
          window.Stimulus = {
            Application: class {
              constructor() { this.controllers = new Map(); }
              register(name, controller) { this.controllers.set(name, controller); }
              start() {
                console.warn('Using offline Stimulus fallback');
                // Basic controller initialization
                document.querySelectorAll('[data-controller]').forEach(element => {
                  const controllers = element.dataset.controller.split(' ');
                  controllers.forEach(controllerName => {
                    const ControllerClass = this.controllers.get(controllerName);
                    if (ControllerClass) {
                      new ControllerClass(element);
                    }
                  });
                });
              }
            },
            Controller: class {
              constructor(element) { this.element = element; }
              get targets() {
                return {
                  find: (name) => this.element.querySelector('[data-' + this.constructor.name.toLowerCase().replace('controller', '') + '-target="' + name + '"]'),
                  findAll: (name) => this.element.querySelectorAll('[data-' + this.constructor.name.toLowerCase().replace('controller', '') + '-target="' + name + '"]')
                };
              }
            }
          };
        `,
        (loaded) => {
          this.stimulusLoaded = loaded;
          if (!loaded) this.showOfflineBanner();
          resolve(loaded);
        }
      );
    });
  }

  // Load Chart.js with fallback
  loadChartJs() {
    return new Promise((resolve) => {
      this.loadExternalScript(
        'https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js',
        `
          // Chart.js fallback - simple canvas drawing
          window.Chart = class {
            constructor(ctx, config) {
              this.ctx = ctx;
              this.config = config;
              this.drawFallbackChart();
            }

            drawFallbackChart() {
              const canvas = this.ctx.canvas;
              const width = canvas.width;
              const height = canvas.height;

              // Clear canvas
              this.ctx.clearRect(0, 0, width, height);

              // Draw fallback message
              this.ctx.fillStyle = '#666';
              this.ctx.font = '14px system-ui';
              this.ctx.textAlign = 'center';
              this.ctx.fillText('Charts unavailable offline', width/2, height/2);
            }

            update() { this.drawFallbackChart(); }
            destroy() {}
          };
        `,
        (loaded) => {
          this.chartLoaded = loaded;
          if (!loaded) this.showOfflineBanner();
          resolve(loaded);
        }
      );
    });
  }

  // Load local scripts
  loadLocalScripts() {
    const scripts = [
      '/assets/js/app.js',
      '/assets/js/controllers/theme_controller.js',
      '/assets/js/controllers/connection_controller.js',
      '/assets/js/controllers/dashboard_controller.js',
      '/assets/js/controllers/queue_controller.js'
    ];

    return new Promise((resolve) => {
      let loadedCount = 0;
      scripts.forEach(src => {
        const script = document.createElement('script');
        script.src = src;
        script.onload = () => {
          loadedCount++;
          if (loadedCount === scripts.length) {
            resolve();
          }
        };
        script.onerror = () => {
          console.warn('Failed to load local script:', src);
          loadedCount++;
          if (loadedCount === scripts.length) {
            resolve();
          }
        };
        document.head.appendChild(script);
      });
    });
  }

  // Initialize the application
  async initialize() {
    if (this.initialized) return;
    this.initialized = true;

    // Set up dismiss button
    const dismissBtn = document.getElementById('dismiss-offline');
    if (dismissBtn) {
      dismissBtn.addEventListener('click', () => this.hideOfflineBanner());
    }

    // Check initial online status
    if (!this.isOnline) {
      this.showOfflineBanner();
      // Show offline content if we're offline and external dependencies failed to load
      setTimeout(() => {
        if (!this.stimulusLoaded || !this.chartLoaded) {
          this.showOfflineContent();
        }
      }, 2000); // Wait 2 seconds to see if dependencies load
    }

    // Load dependencies in sequence
    await this.loadStimulus();
    await this.loadChartJs();
    await this.loadLocalScripts();
  }
}

// Export for use in other modules
window.OfflineManager = OfflineManager;
