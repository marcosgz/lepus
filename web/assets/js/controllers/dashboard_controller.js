(function() {
  StimulusApp.register("dashboard", class extends Stimulus.Controller {
    static targets = [
      "refreshRange", "refreshLabel",
      "processCount", "queueCount", "totalMessages", "memoryUsage",
      "connectionCount", "publishRate", "consumeRate",
      "processDetail", "queueDetail", "messageDetail", "memoryDetail", "connectionDetail", "rateDetail",
      "processesRoot", "queuesRoot"
    ]

    connect() {
      this.intervalSec = parseInt(this.refreshRangeTarget.value || '15', 10);
      this.refreshLabelTarget.textContent = this.intervalSec;
      this.consumerStates = {}; // Store expanded/collapsed states
      this.queueStates = {}; // Store expanded/collapsed states for queues
      this.setupCharts();
      this.poll();
      this.startTimer();
    }

    disconnect() {
      if (this.timer) clearInterval(this.timer);
    }

    updateRefresh() {
      this.intervalSec = parseInt(this.refreshRangeTarget.value, 10);
      this.refreshLabelTarget.textContent = this.intervalSec;
      this.startTimer();
    }

    startTimer() {
      if (this.timer) clearInterval(this.timer);
      this.timer = setInterval(() => this.poll(), this.intervalSec * 1000);
    }

    async poll() {
      // Check if we're offline
      if (!navigator.onLine) {
        this.showOfflineMessage();
        return;
      }

      try {
        const [processes, queues, connections] = await Promise.all([
          this.fetchLepusProcesses(),
          this.fetchRabbitQueues(),
          this.fetchRabbitConnections()
        ]);
        this.renderStats(processes, queues, connections);
        this.renderProcesses(processes);
        this.renderQueues(queues);
        this.updateCharts(queues);
        this.restoreConsumerStates();
        this.restoreQueueStates();
        this.hideOfflineMessage();
      } catch (error) {
        console.warn('Dashboard poll failed:', error);
        this.showOfflineMessage();
      }
    }

    async fetchLepusProcesses() {
      try {
        const r = await fetch('/api/processes');
        if (!r.ok) throw new Error('bad');
        return await r.json();
      } catch (_) {
        // demo fallback
        const now = Date.now();
        return [
          { id: 1, name: 'Supervisor A', pid: 1001, hostname: 'host-a', kind: 'supervisor', last_heartbeat_at: now, rss_memory: 120_000_000 },
          { id: 2, name: 'Worker A1', pid: 1002, hostname: 'host-a', kind: 'worker', supervisor_id: 1, last_heartbeat_at: now, rss_memory: 80_000_000 },
          { id: 3, name: 'Worker A2', pid: 1003, hostname: 'host-a', kind: 'worker', supervisor_id: 1, last_heartbeat_at: now - 65_000, rss_memory: 90_000_000 },
        ];
      }
    }

    async fetchRabbitQueues() {
      try {
        const r = await fetch('/api/queues/grouped');
        if (!r.ok) throw new Error('bad');
        return await r.json();
      } catch (_) {
        // demo fallback
        return [
          {
            name: 'orders',
            main: { name: 'orders', type: 'classic', messages: 42, messages_ready: 21, messages_unacknowledged: 2, consumers: 3, memory: 1024*1024*8 },
            retry: { name: 'orders.retry', type: 'classic', messages: 5, messages_ready: 5, messages_unacknowledged: 0, consumers: 0, memory: 1024*1024*1 },
            error: { name: 'orders.error', type: 'classic', messages: 2, messages_ready: 2, messages_unacknowledged: 0, consumers: 0, memory: 1024*512 }
          },
          {
            name: 'invoices',
            main: { name: 'invoices', type: 'quorum', messages: 12, messages_ready: 12, messages_unacknowledged: 0, consumers: 2, memory: 1024*1024*2 },
            retry: null,
            error: null
          }
        ];
      }
    }

    async fetchRabbitConnections() {
      try {
        const r = await fetch('/api/connections');
        if (!r.ok) throw new Error('bad');
        return await r.json();
      } catch (_) {
        // demo fallback
        return [
          {name: 'conn-1', state: 'running'},
          {name: 'conn-2', state: 'idle'},
          {name: 'conn-3', state: 'running'}
        ];
      }
    }

    renderStats(processes, queues, connections) {
      const processCount = processes.length;
      const queueCount = queues.filter(q => !q.name.endsWith('.retry') && !q.name.endsWith('.error')).length;
      const totalMessages = queues.reduce((sum, q) => sum + (q.messages || 0), 0);
      const memory = processes.reduce((sum, p) => sum + (p.rss_memory || 0), 0);
      console.log('renderStats', { processes, queues, connections });

      // Process details
      const supervisors = processes.filter(p => p.kind === 'supervisor').length;
      const workers = processes.filter(p => p.kind === 'worker').length;
      this.processCountTarget.textContent = processCount;
      this.processDetailTarget.textContent = `Supervisors ${supervisors}, Workers ${workers}`;

      // Queue details
      const runningQueues = queues.filter(q => !q.name.endsWith('.retry') && !q.name.endsWith('.error') && (q.consumers || 0) > 0).length;
      const pausedQueues = queueCount - runningQueues;
      this.queueCountTarget.textContent = queueCount;
      this.queueDetailTarget.textContent = `${runningQueues} running, ${pausedQueues} paused`;

      // Message details
      const readyMessages = queues.reduce((sum, q) => sum + (q.messages_ready || 0), 0);
      const unackedMessages = queues.reduce((sum, q) => sum + (q.messages_unacknowledged || 0), 0);
      this.totalMessagesTarget.textContent = totalMessages.toLocaleString();
      this.messageDetailTarget.textContent = `${readyMessages.toLocaleString()} ready, ${unackedMessages.toLocaleString()} unacked`;

      // Memory details
      const rssMemory = memory;
      const heapMemory = processes.reduce((sum, p) => sum + (p.heap_memory || Math.round(p.rss_memory * 0.7)), 0);
      this.memoryUsageTarget.textContent = (memory / (1024*1024)).toFixed(1) + ' MB';
      this.memoryDetailTarget.textContent = `RSS ${(rssMemory / (1024*1024)).toFixed(1)} MB, Heap ${(heapMemory / (1024*1024)).toFixed(1)} MB`;

      // Connection details
      const activeConnections = connections.filter(c => c.state === 'running' || !c.state).length;
      const idleConnections = connections.length - activeConnections;
      this.connectionCountTarget.textContent = connections.length;
      this.connectionDetailTarget.textContent = `${activeConnections} active, ${idleConnections} idle`;

      // Rate details
      const publish = Math.max(0, Math.round(totalMessages * 0.1));
      const consume = Math.max(0, Math.round(totalMessages * 0.08));
      const peakPublish = Math.round(publish * 1.5);
      const peakConsume = Math.round(consume * 1.3);
      this.publishRateTarget.textContent = publish;
      this.consumeRateTarget.textContent = consume;
      this.rateDetailTarget.textContent = `Peak: ${peakPublish}/${peakConsume} msg/s`;
    }

    renderProcesses(processes) {
      // Group by application
      const byApplication = new Map();

      // First, group supervisors by application
      processes.forEach(p => {
        if (p.kind === 'supervisor') {
          const app = p.application || 'DefaultApp';
          if (!byApplication.has(app)) {
            byApplication.set(app, { application: app, supervisors: [] });
          }
          byApplication.get(app).supervisors.push(p);
        }
      });

      // Then, group workers by supervisor
      processes.forEach(p => {
        if (p.kind === 'worker' && p.supervisor_id) {
          for (const appData of byApplication.values()) {
            const supervisor = appData.supervisors.find(s => s.id === p.supervisor_id);
            if (supervisor) {
              if (!supervisor.workers) supervisor.workers = [];
              supervisor.workers.push(p);
              break;
            }
          }
        }
      });

      this.processesRootTarget.innerHTML = '';

      for (const {application, supervisors} of byApplication.values()) {
        // Application Card
        const appCard = document.createElement('div');
        appCard.className = 'card application-card';
        appCard.innerHTML = `
          <div class="card-header">
            <h2><span class="level-label">Application</span> ${this.escape(application)}</h2>
          </div>
          <div class="card-body">
            <div class="supervisors-container">
              ${supervisors.map(supervisor => this.renderSupervisor(supervisor)).join('')}
            </div>
          </div>
        `;
        this.processesRootTarget.appendChild(appCard);
      }
    }

    renderSupervisor(supervisor) {
      const healthy = (Date.now() - (supervisor.last_heartbeat_at || 0)) < 60_000;
      const workers = supervisor.workers || [];

      return `
        <div class="supervisor-card">
          <div class="card-header">
            <div class="supervisor-info">
              <h3><span class="level-label">Supervisor</span> ${this.escape(supervisor.name)} <span class="badge ${healthy ? 'ok' : 'err'}">${healthy ? 'healthy' : 'unreachable'}</span></h3>
            </div>
            <div class="supervisor-meta">
              <span class="meta-text">PID ${supervisor.pid} • ${this.escape(supervisor.hostname)} • ${(supervisor.rss_memory/(1024*1024)).toFixed(1)} MB</span>
            </div>
          </div>
          <div class="card-body">
            <div class="workers-container">
              ${workers.map(worker => this.renderWorker(worker)).join('')}
            </div>
          </div>
        </div>
      `;
    }

    renderWorker(worker) {
      const healthy = (Date.now() - (worker.last_heartbeat_at || 0)) < 60_000;
      const consumers = worker.consumers || [];

      return `
        <div class="worker-card">
          <div class="card-header">
            <div class="worker-info">
              <h4><span class="level-label">Worker</span> ${this.escape(worker.name)} <span class="badge ${healthy ? 'ok' : 'err'}">${healthy ? 'healthy' : 'unreachable'}</span></h4>
            </div>
            <div class="worker-meta">
              <span class="meta-text">PID ${worker.pid} • ${worker.connections || 0} connections • ${(worker.rss_memory/(1024*1024)).toFixed(1)} MB</span>
            </div>
          </div>
          <div class="card-body">
            <div class="consumers-container">
              ${consumers.map(consumer => this.renderConsumer(consumer)).join('')}
            </div>
          </div>
        </div>
      `;
    }

    renderConsumer(consumer) {
      const totalConcurrent = consumer.threads || 1;
      const processed = consumer.processed || 0;
      const rejected = consumer.rejected || 0;
      const errored = consumer.errored || 0;

      const subscriptionText = totalConcurrent === 1 ? 'subscription' : 'subscriptions';

      return `
        <div class="consumer-card" data-consumer-id="${consumer.class_name}">
          <div class="card-header consumer-header" data-action="click->dashboard#toggleConsumer">
            <div class="consumer-info">
              <h5><span class="level-label">Consumer</span> ${this.escape(consumer.class_name)} <span class="badge concurrent">${totalConcurrent} ${subscriptionText}</span></h5>
            </div>
            <div class="consumer-meta">
              <div class="consumer-stats-preview">
                <span class="stat-mini processed">${processed}</span>
                <span class="stat-mini rejected">${rejected}</span>
                <span class="stat-mini errored">${errored}</span>
              </div>
              <span class="expand-icon">▼</span>
            </div>
          </div>
          <div class="card-body consumer-details" style="display: none;">
            <div class="consumer-details-content">
              <table class="consumer-table">
                <tr>
                  <td class="label">Exchange:</td>
                  <td>${this.escape(consumer.exchange)}</td>
                </tr>
                <tr>
                  <td class="label">Queue:</td>
                  <td>${this.escape(consumer.queue)}</td>
                </tr>
                ${consumer.route ? `
                <tr>
                  <td class="label">Route:</td>
                  <td>${this.escape(consumer.route)}</td>
                </tr>
                ` : ''}
                <tr>
                  <td class="label">Subscriptions:</td>
                  <td>${totalConcurrent} ${subscriptionText}</td>
                </tr>
                <tr>
                  <td class="label">Stats:</td>
                  <td>
                    <span class="stat processed">${processed} processed</span>
                    <span class="stat rejected">${rejected} rejected</span>
                    <span class="stat errored">${errored} errored</span>
                  </td>
                </tr>
              </table>
            </div>
          </div>
        </div>
      `;
    }

    renderQueues(groupedQueues) {
      const tbody = this.queuesRootTarget;
      tbody.innerHTML = '';

      for (const group of groupedQueues) {
        const q = group.main || {name: group.name, type: 'classic', messages_ready: 0, messages_unacknowledged: 0, messages: 0, consumers: 0};
        const tr = document.createElement('tr');
        tr.className = 'queue-row';
        tr.dataset.queue = group.name;
        tr.setAttribute('data-action', 'click->dashboard#toggleQueue');
        tr.innerHTML = this.queueCells(q, true);
        tbody.appendChild(tr);

        const sub = document.createElement('tr');
        sub.className = 'sub-row';
        const td = document.createElement('td');
        td.colSpan = 8;
        td.innerHTML = `
          <div class="grid" style="grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 8px;">
            ${group.retry ? `<div class="metric"><div class="metric-label">Retry</div>${this.queueInline(group.retry)}</div>` : ''}
            ${group.error ? `<div class="metric"><div class="metric-label">Error</div>${this.queueInline(group.error)}</div>` : ''}
            ${!group.retry && !group.error ? '<div class="metric"><div class="metric-label">No extra queues</div><div class="metric-value">—</div></div>' : ''}
          </div>`;
        sub.appendChild(td);
        sub.hidden = true;
        tbody.appendChild(sub);
      }
    }

    queueCells(q, showToggle) {
      const total = (q.messages != null) ? q.messages : (q.messages_ready || 0) + (q.messages_unacknowledged || 0);
      return `
        <td>${this.escape(q.name)}</td>
        <td><span class="badge">${this.escape(q.type || 'classic')}</span></td>
        <td>${q.messages_ready ?? 0}</td>
        <td>${q.messages_unacknowledged ?? 0}</td>
        <td>${total}</td>
        <td>${q.consumers ?? 0}</td>
        <td>${q.memory ? (q.memory/(1024*1024)).toFixed(1) + ' MB' : '—'}</td>
        <td>${showToggle ? '<button class="btn">Details</button>' : ''}</td>
      `;
    }

    queueInline(q) {
      const total = (q.messages != null) ? q.messages : (q.messages_ready || 0) + (q.messages_unacknowledged || 0);
      return `
        <div class="queue-detail-content">
          <div class="queue-name">${this.escape(q.name)}</div>
          <div class="queue-stats">
            <div class="stat-item">
              <span class="stat-label">Ready:</span>
              <span class="stat-value">${q.messages_ready ?? 0}</span>
            </div>
            <div class="stat-item">
              <span class="stat-label">Unacked:</span>
              <span class="stat-value">${q.messages_unacknowledged ?? 0}</span>
            </div>
            <div class="stat-item">
              <span class="stat-label">Total:</span>
              <span class="stat-value">${total}</span>
            </div>
          </div>
        </div>
      `;
    }

    setupCharts() {
      const rateCtx = document.getElementById('rateChart');
      const queueCtx = document.getElementById('queueChart');

      this.rateChart = new Chart(rateCtx, {
        type: 'line',
        data: {
          labels: [],
          datasets: [
            { label: 'Publish', data: [], borderColor: '#6ea8fe', backgroundColor: 'rgba(110,168,254,0.15)', tension: 0.3, fill: true },
            { label: 'Consume', data: [], borderColor: '#7ee787', backgroundColor: 'rgba(126,231,135,0.15)', tension: 0.3, fill: true }
          ]
        },
        options: {
          responsive: true, maintainAspectRatio: false,
          scales: { x: { ticks: { color: getComputedStyle(document.documentElement).getPropertyValue('--muted') } }, y: { ticks: { color: getComputedStyle(document.documentElement).getPropertyValue('--muted') } } },
          plugins: { legend: { labels: { color: getComputedStyle(document.documentElement).getPropertyValue('--muted') } } }
        }
      });

      this.queueChart = new Chart(queueCtx, {
        type: 'doughnut',
        data: { labels: [], datasets: [{ data: [], backgroundColor: ['#6ea8fe', '#7ee787', '#f7c948', '#ff6b6b', '#8b5cf6', '#fb923c'] }] },
        options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { position: 'bottom', labels: { color: getComputedStyle(document.documentElement).getPropertyValue('--muted') } } } }
      });
    }

    updateCharts(groupedQueues) {
      const nowLabel = new Date().toLocaleTimeString();
      const total = groupedQueues.reduce((sum, group) => {
        const mainMessages = group.main ? (group.main.messages || 0) : 0;
        const retryMessages = group.retry ? (group.retry.messages || 0) : 0;
        const errorMessages = group.error ? (group.error.messages || 0) : 0;
        return sum + mainMessages + retryMessages + errorMessages;
      }, 0);
      const pub = Math.max(0, Math.round(total * 0.1 + Math.random() * 5));
      const con = Math.max(0, Math.round(total * 0.08 + Math.random() * 5));

      const maxPoints = 20;
      const labels = this.rateChart.data.labels;
      if (labels.length >= maxPoints) { labels.shift(); this.rateChart.data.datasets.forEach(d => d.data.shift()); }
      labels.push(nowLabel);
      this.rateChart.data.datasets[0].data.push(pub);
      this.rateChart.data.datasets[1].data.push(con);
      this.rateChart.update('none');

      this.queueChart.data.labels = groupedQueues.map(group => group.name);
      this.queueChart.data.datasets[0].data = groupedQueues.map(group => {
        const mainMessages = group.main ? (group.main.messages || 0) : 0;
        const retryMessages = group.retry ? (group.retry.messages || 0) : 0;
        const errorMessages = group.error ? (group.error.messages || 0) : 0;
        return mainMessages + retryMessages + errorMessages;
      });
      this.queueChart.update('none');
    }

    toggleConsumer(event) {
      const header = event.currentTarget;
      const consumerCard = header.closest('.consumer-card');
      const details = consumerCard.querySelector('.consumer-details');
      const expandIcon = header.querySelector('.expand-icon');
      const consumerId = consumerCard.dataset.consumerId;

      if (details.style.display === 'none') {
        details.style.display = 'block';
        expandIcon.textContent = '▲';
        consumerCard.classList.add('expanded');
        this.consumerStates[consumerId] = true;
      } else {
        details.style.display = 'none';
        expandIcon.textContent = '▼';
        consumerCard.classList.remove('expanded');
        this.consumerStates[consumerId] = false;
      }
    }

    restoreConsumerStates() {
      Object.keys(this.consumerStates).forEach(consumerId => {
        const consumerCard = document.querySelector(`[data-consumer-id="${consumerId}"]`);
        if (consumerCard && this.consumerStates[consumerId]) {
          const details = consumerCard.querySelector('.consumer-details');
          const expandIcon = consumerCard.querySelector('.expand-icon');
          if (details && expandIcon) {
            details.style.display = 'block';
            expandIcon.textContent = '▲';
            consumerCard.classList.add('expanded');
          }
        }
      });
    }

    toggleQueue(event) {
      const row = event.currentTarget.closest('tr');
      const queueName = row && row.dataset && row.dataset.queue;
      if (!queueName) return;

      const sub = row.nextElementSibling;
      if (sub && sub.classList.contains('sub-row')) {
        const isHidden = sub.hidden;
        sub.hidden = !isHidden;
        this.queueStates[queueName] = !isHidden;
      }
    }

    restoreQueueStates() {
      Object.keys(this.queueStates).forEach(queueName => {
        const queueRow = document.querySelector(`[data-queue="${queueName}"]`);
        if (queueRow && this.queueStates[queueName]) {
          const sub = queueRow.nextElementSibling;
          if (sub && sub.classList.contains('sub-row')) {
            sub.hidden = false;
          }
        }
      });
    }

    showOfflineMessage() {
      // Update stats to show offline state
      this.processCountTarget.textContent = '—';
      this.queueCountTarget.textContent = '—';
      this.totalMessagesTarget.textContent = '—';
      this.memoryUsageTarget.textContent = '—';
      this.connectionCountTarget.textContent = '—';
      this.publishRateTarget.textContent = '—';
      this.consumeRateTarget.textContent = '—';

      // Update detail texts
      this.processDetailTarget.textContent = 'Offline';
      this.queueDetailTarget.textContent = 'Offline';
      this.messageDetailTarget.textContent = 'Offline';
      this.memoryDetailTarget.textContent = 'Offline';
      this.connectionDetailTarget.textContent = 'Offline';
      this.rateDetailTarget.textContent = 'Offline';
    }

    hideOfflineMessage() {
      // Clear any offline indicators - normal operation will update these
    }

    escape(s) { return String(s).replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c])); }
  });
})();


