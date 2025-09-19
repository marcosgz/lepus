(function() {
  StimulusApp.register("connection", class extends Stimulus.Controller {
    static targets = ["indicator", "text"]

    connect() {
      this.check();
      this.timer = setInterval(() => this.check(), 10000);
    }

    disconnect() {
      if (this.timer) clearInterval(this.timer);
    }

    async check() {
      // Check if we're offline first
      if (!navigator.onLine) {
        this.indicatorTarget.classList.add('disconnected');
        this.textTarget.textContent = 'Offline';
        return;
      }

      try {
        const res = await fetch('/api/health');
        if (res.ok) {
          this.indicatorTarget.classList.remove('disconnected');
          this.textTarget.textContent = 'Connected';
        } else {
          this.indicatorTarget.classList.add('disconnected');
          this.textTarget.textContent = 'Disconnected';
        }
      } catch (error) {
        this.indicatorTarget.classList.add('disconnected');
        // More specific error handling
        if (error.name === 'TypeError' && error.message.includes('fetch')) {
          this.textTarget.textContent = 'Offline';
        } else {
          this.textTarget.textContent = 'Disconnected';
        }
      }
    }
  });
})();


