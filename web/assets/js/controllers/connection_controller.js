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
      try {
        const res = await fetch('/api/health');
        if (res.ok) {
          this.indicatorTarget.classList.remove('disconnected');
          this.textTarget.textContent = 'Connected';
        } else {
          this.indicatorTarget.classList.add('disconnected');
          this.textTarget.textContent = 'Disconnected';
        }
      } catch (_) {
        this.indicatorTarget.classList.add('disconnected');
        this.textTarget.textContent = 'Disconnected';
      }
    }
  });
})();


