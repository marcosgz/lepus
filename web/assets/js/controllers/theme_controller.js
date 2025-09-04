(function() {
  StimulusApp.register("theme", class extends Stimulus.Controller {
    static targets = ["icon"]

    connect() {
      const stored = localStorage.getItem("lepus:theme");
      const prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
      const theme = stored || (prefersDark ? 'dark' : 'light');
      this.applyTheme(theme);
    }

    toggle() {
      const current = document.documentElement.getAttribute('data-theme') || 'dark';
      const next = current === 'dark' ? 'light' : 'dark';
      this.applyTheme(next);
      try { localStorage.setItem('lepus:theme', next); } catch (_) {}
    }

    applyTheme(theme) {
      if (theme === 'light') {
        document.documentElement.setAttribute('data-theme', 'light');
        this.iconTarget.textContent = '🌞';
      } else {
        document.documentElement.setAttribute('data-theme', 'dark');
        this.iconTarget.textContent = '🌙';
      }
    }
  });
})();


