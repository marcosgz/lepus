(function() {
  StimulusApp.register("queue", class extends Stimulus.Controller {
    static targets = []

    toggle(event) {
      const row = event.currentTarget.closest('tr');
      const name = row && row.dataset && row.dataset.queue;
      if (!name) return;
      const sub = row.nextElementSibling;
      if (sub && sub.classList.contains('sub-row')) {
        sub.hidden = !sub.hidden;
      }
    }
  });
})();


