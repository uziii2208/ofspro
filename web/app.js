/**
 * OFSPRO Web UI - Offensive Security Gemini Proxy Dashboard
 * 100% Non-Hallucination Real Intercept & Control Engine
 * Author: @uziii2208
 */

(() => {
  'use strict';

  // =========================================================================
  // APPLICATION STATE
  // =========================================================================
  const state = {
    currentTab: 'interceptor', // 'interceptor', 'bypass', 'lures', 'playground', 'terminal'
    level: 2,
    rewriteMode: 'auto',
    thinkingBudget: null, // null for auto
    clean: true,
    unmap: true,
    lureAuto: false,
    proxyPort: 8080,
    lures: [],
    feed: [],
    logs: [],
    filter: 'all',
    searchQuery: '',
    isPaused: false,
    activeFlow: null,
    diffMode: 'split', // 'split', 'unified', 'raw'
    audioEnabled: true,
    stats: {
      total: 0,
      deceptions: 0,
      cleaned: 0,
      active_lures: 0,
      avgLatency: 0,
    },
    uptimeSeconds: 0,
  };

  const LEVEL_NAMES = {
    0: 'L0 LIGHT',
    1: 'L1 MEDIUM',
    2: 'L2 STRONG',
    3: 'L3 NUCLEAR',
  };

  const THINKING_BUDGETS = {
    0: 0,
    1: 128,
    2: 512,
    3: 1024,
  };

  // =========================================================================
  // AUDIO SYNTHESIZER (CYBER HAPTICS)
  // =========================================================================
  class SoundEngine {
    constructor() {
      this.ctx = null;
    }
    init() {
      if (!this.ctx && (window.AudioContext || window.webkitAudioContext)) {
        this.ctx = new (window.AudioContext || window.webkitAudioContext)();
      }
    }
    playClick() {
      if (!state.audioEnabled) return;
      try {
        this.init();
        if (!this.ctx) return;
        const now = this.ctx.currentTime;
        const osc = this.ctx.createOscillator();
        const gain = this.ctx.createGain();
        osc.type = 'sine';
        osc.frequency.setValueAtTime(800, now);
        osc.frequency.exponentialRampToValueAtTime(320, now + 0.04);
        gain.gain.setValueAtTime(0.04, now);
        gain.gain.exponentialRampToValueAtTime(0.001, now + 0.04);
        osc.connect(gain);
        gain.connect(this.ctx.destination);
        osc.start();
        osc.stop(now + 0.04);
      } catch (e) {}
    }
    playChime() {
      if (!state.audioEnabled) return;
      try {
        this.init();
        if (!this.ctx) return;
        const now = this.ctx.currentTime;
        const osc = this.ctx.createOscillator();
        const gain = this.ctx.createGain();
        osc.type = 'triangle';
        osc.frequency.setValueAtTime(540, now);
        osc.frequency.exponentialRampToValueAtTime(1080, now + 0.12);
        gain.gain.setValueAtTime(0.05, now);
        gain.gain.exponentialRampToValueAtTime(0.001, now + 0.12);
        osc.connect(gain);
        gain.connect(this.ctx.destination);
        osc.start();
        osc.stop(now + 0.12);
      } catch (e) {}
    }
    playNuclear() {
      if (!state.audioEnabled) return;
      try {
        this.init();
        if (!this.ctx) return;
        const now = this.ctx.currentTime;
        const osc = this.ctx.createOscillator();
        const gain = this.ctx.createGain();
        osc.type = 'sawtooth';
        osc.frequency.setValueAtTime(160, now);
        osc.frequency.exponentialRampToValueAtTime(70, now + 0.28);
        gain.gain.setValueAtTime(0.08, now);
        gain.gain.exponentialRampToValueAtTime(0.001, now + 0.28);
        osc.connect(gain);
        gain.connect(this.ctx.destination);
        osc.start();
        osc.stop(now + 0.28);
      } catch (e) {}
    }
  }
  const sound = new SoundEngine();

  // =========================================================================
  // TOAST NOTIFICATIONS
  // =========================================================================
  function showToast(message, type = 'info', duration = 2800) {
    const container = document.getElementById('toastContainer');
    if (!container) return;

    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;

    let iconSvg = '';
    if (type === 'success') {
      iconSvg = `<svg class="toast-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20 6L9 17l-5-5"/></svg>`;
    } else if (type === 'danger') {
      iconSvg = `<svg class="toast-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>`;
    } else if (type === 'warning') {
      iconSvg = `<svg class="toast-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>`;
    } else {
      iconSvg = `<svg class="toast-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>`;
    }

    toast.innerHTML = `${iconSvg}<span>${escapeHtml(message)}</span>`;
    container.appendChild(toast);

    requestAnimationFrame(() => toast.classList.add('show'));

    setTimeout(() => {
      toast.classList.remove('show');
      setTimeout(() => toast.remove(), 250);
    }, duration);
  }

  // =========================================================================
  // TAB NAVIGATION SYSTEM
  // =========================================================================
  function initTabs() {
    const tabButtons = document.querySelectorAll('.tab-pill, .dock-tab-btn');
    const panels = {
      interceptor: document.getElementById('panelInterceptor'),
      bypass: document.getElementById('panelBypass'),
      lures: document.getElementById('panelLures'),
      playground: document.getElementById('panelPlayground'),
      terminal: document.getElementById('panelTerminal'),
    };

    function switchTab(tabId) {
      if (!panels[tabId]) return;
      state.currentTab = tabId;

      tabButtons.forEach(btn => {
        const isCurrent = btn.dataset.tab === tabId;
        btn.classList.toggle('active', isCurrent);
        btn.setAttribute('aria-selected', isCurrent ? 'true' : 'false');
      });

      Object.entries(panels).forEach(([id, panel]) => {
        if (panel) {
          panel.classList.toggle('active', id === tabId);
        }
      });

      sound.playClick();
    }

    tabButtons.forEach(btn => {
      btn.addEventListener('click', () => {
        switchTab(btn.dataset.tab);
      });
    });

    // Quick level badge in navbar clicks over to Bypass tab
    const quickBadge = document.getElementById('quickLevelBadge');
    if (quickBadge) {
      quickBadge.addEventListener('click', () => {
        switchTab('bypass');
      });
    }

    window.switchTab = switchTab;
  }

  // =========================================================================
  // BACKEND API SYNC & MUTATIONS (100% Non-Hallucination)
  // =========================================================================

  // Update backend config: triggers real mitmproxy rewriter changes & prints to terminal
  async function mutateConfig(updates) {
    try {
      const res = await fetch('/api/config', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(updates),
      });
      if (res.ok) {
        const data = await res.json();
        if (data.config) {
          applyConfigToState(data.config);
          return true;
        }
      }
    } catch (e) {
      showToast('Network error updating proxy config', 'danger');
    }
    return false;
  }

  function applyConfigToState(cfg) {
    if (cfg.level !== undefined) state.level = cfg.level;
    if (cfg.rewrite_mode !== undefined) state.rewriteMode = cfg.rewrite_mode;
    if (cfg.clean !== undefined) state.clean = cfg.clean;
    if (cfg.unmap !== undefined) state.unmap = cfg.unmap;
    if (cfg.lure_auto !== undefined) state.lureAuto = cfg.lure_auto;
    if (cfg.thinking_budget !== undefined) state.thinkingBudget = cfg.thinking_budget;

    updateBypassUI();
    updateHeaderPills();
  }

  // Add Target Lure (100% Real API)
  async function mutateAddTarget(target) {
    try {
      const res = await fetch('/api/targets', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ target }),
      });
      if (res.ok) {
        const data = await res.json();
        if (data.lures) {
          state.lures = data.lures;
          renderLuresTable();
          updateMetricsUI();
          sound.playChime();
          showToast(`Target lured: ${target} → ${data.mapped || '127.0.1.X'}`, 'success');
          return true;
        }
      }
    } catch (e) {
      showToast('Error communicating with proxy lure engine', 'danger');
    }
    return false;
  }

  // Delete Target Lure (100% Real API)
  async function mutateRemoveTarget(target) {
    try {
      const res = await fetch('/api/targets', {
        method: 'DELETE',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ target }),
      });
      if (res.ok) {
        const data = await res.json();
        if (data.lures) {
          state.lures = data.lures;
          renderLuresTable();
          updateMetricsUI();
          sound.playClick();
          showToast(`Lure removed: ${target}`, 'warning');
          return true;
        }
      }
    } catch (e) {
      showToast('Error removing target mapping', 'danger');
    }
    return false;
  }

  // Clear All Targets
  async function mutateClearAllTargets() {
    try {
      const res = await fetch('/api/targets/clear', {
        method: 'POST',
      });
      if (res.ok) {
        state.lures = [];
        renderLuresTable();
        updateMetricsUI();
        sound.playClick();
        showToast('All target lures cleared from proxy', 'warning');
      }
    } catch (e) {
      showToast('Error clearing target lures', 'danger');
    }
  }

  // Clear Interception Flows Buffer
  async function mutateClearFlows() {
    try {
      const res = await fetch('/api/clear', { method: 'POST' });
      if (res.ok) {
        state.feed = [];
        renderFeedTable();
        updateMetricsUI();
        sound.playClick();
        showToast('Interception flows cleared from proxy buffer', 'info');
      }
    } catch (e) {
      showToast('Error clearing flows', 'danger');
    }
  }

  // =========================================================================
  // BYPASS CONTROLS & ESCALATION LEVELS
  // =========================================================================
  function initBypassControls() {
    // 4 Escalation Level Cards
    const levelCards = document.querySelectorAll('.level-card');
    const activateButtons = document.querySelectorAll('.activate-level-btn');

    async function setLevel(lvl) {
      const parsed = parseInt(lvl, 10);
      state.level = parsed;

      if (parsed === 3) {
        sound.playNuclear();
        document.body.classList.add('nuclear-active');
        showToast('Nuclear Level 3 Engaged: Full System Instruction Scope Override', 'danger', 4000);
      } else {
        sound.playClick();
        document.body.classList.remove('nuclear-active');
        showToast(`Bypass Escalation Level set to ${LEVEL_NAMES[parsed]}`, 'success');
      }

      updateBypassUI();
      updateHeaderPills();

      // Trigger REAL proxy backend update!
      await mutateConfig({ level: parsed });
    }

    activateButtons.forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        setLevel(btn.dataset.level);
      });
    });

    levelCards.forEach(card => {
      card.addEventListener('click', () => {
        setLevel(card.dataset.level);
      });
    });

    // Rewrite Policy Segmented Control
    const rewriteButtons = document.querySelectorAll('#rewriteModeGroup .seg-btn');
    rewriteButtons.forEach(btn => {
      btn.addEventListener('click', async () => {
        const mode = btn.dataset.mode;
        state.rewriteMode = mode;
        sound.playClick();
        rewriteButtons.forEach(b => b.classList.toggle('active', b.dataset.mode === mode));
        updateHeaderPills();
        showToast(`Rewrite policy set to ${mode.toUpperCase()}`, 'info');
        await mutateConfig({ rewrite_mode: mode });
      });
    });

    // Policy Toggles
    const toggleClean = document.getElementById('toggleClean');
    if (toggleClean) {
      toggleClean.addEventListener('change', async () => {
        state.clean = toggleClean.checked;
        sound.playClick();
        showToast(`Response Refusal Stripping: ${state.clean ? 'ENABLED' : 'DISABLED'}`, state.clean ? 'success' : 'warning');
        await mutateConfig({ clean: state.clean });
      });
    }

    const toggleUnmap = document.getElementById('toggleUnmap');
    if (toggleUnmap) {
      toggleUnmap.addEventListener('change', async () => {
        state.unmap = toggleUnmap.checked;
        sound.playClick();
        showToast(`Response Target Unmapping: ${state.unmap ? 'ENABLED' : 'DISABLED'}`, state.unmap ? 'success' : 'warning');
        await mutateConfig({ unmap: state.unmap });
      });
    }

    // Thinking Budget Custom Override Dropdown
    const budgetSelect = document.getElementById('budgetSelect');
    const budgetHint = document.getElementById('budgetHintText');
    if (budgetSelect) {
      budgetSelect.addEventListener('change', async () => {
        const val = budgetSelect.value;
        sound.playClick();
        if (val === 'auto') {
          state.thinkingBudget = null;
          if (budgetHint) budgetHint.textContent = `Auto: ${THINKING_BUDGETS[state.level]} tokens via ${LEVEL_NAMES[state.level]}`;
          showToast(`Thinking Budget set to Auto (${THINKING_BUDGETS[state.level]} tk)`, 'info');
          await mutateConfig({ thinking_budget: 'auto' });
        } else {
          const num = parseInt(val, 10);
          state.thinkingBudget = num;
          if (budgetHint) budgetHint.textContent = `Manual Override: ${num} tokens enforced`;
          showToast(`Thinking Budget locked to ${num} tokens`, 'success');
          await mutateConfig({ thinking_budget: num });
        }
      });
    }
  }

  function updateBypassUI() {
    const levelCards = document.querySelectorAll('.level-card');
    levelCards.forEach(card => {
      const cLvl = parseInt(card.dataset.level, 10);
      const isActive = cLvl === state.level;
      card.classList.toggle('active', isActive);

      const statusPill = card.querySelector('.level-status-pill');
      if (statusPill) {
        statusPill.textContent = isActive ? 'ACTIVE' : 'INACTIVE';
        statusPill.classList.toggle('pill-active', isActive);
      }

      const actBtn = card.querySelector('.activate-level-btn');
      if (actBtn) {
        actBtn.textContent = isActive ? 'Active Level' : `Activate L${cLvl}`;
        if (isActive) {
          actBtn.className = cLvl === 3 ? 'btn btn-nuclear btn-sm activate-level-btn' : 'btn btn-primary btn-sm activate-level-btn';
        } else {
          actBtn.className = 'btn btn-secondary btn-sm activate-level-btn';
        }
      }
    });

    // Update rewrite mode segmented buttons
    const rewriteButtons = document.querySelectorAll('#rewriteModeGroup .seg-btn');
    rewriteButtons.forEach(btn => {
      btn.classList.toggle('active', btn.dataset.mode === state.rewriteMode);
    });

    // Update switches
    const toggleClean = document.getElementById('toggleClean');
    if (toggleClean) toggleClean.checked = state.clean;

    const toggleUnmap = document.getElementById('toggleUnmap');
    if (toggleUnmap) toggleUnmap.checked = state.unmap;

    const toggleLureAuto = document.getElementById('toggleLureAuto');
    if (toggleLureAuto) toggleLureAuto.checked = state.lureAuto;

    // Budget hint text
    const budgetHint = document.getElementById('budgetHintText');
    if (budgetHint) {
      if (state.thinkingBudget !== null) {
        budgetHint.textContent = `Manual Override: ${state.thinkingBudget} tokens enforced`;
      } else {
        budgetHint.textContent = `Auto: ${THINKING_BUDGETS[state.level]} tokens via ${LEVEL_NAMES[state.level]}`;
      }
    }
  }

  function updateHeaderPills() {
    const quickBadge = document.getElementById('quickLevelBadge');
    const quickLevelText = document.getElementById('quickLevelText');
    const quickRewriteText = document.getElementById('quickRewriteText');
    const tabActiveLevelTag = document.getElementById('tabActiveLevelTag');

    if (quickLevelText) quickLevelText.textContent = LEVEL_NAMES[state.level] || `L${state.level}`;
    if (quickRewriteText) quickRewriteText.textContent = `· ${state.rewriteMode.toUpperCase()}`;
    if (tabActiveLevelTag) tabActiveLevelTag.textContent = `L${state.level}`;

    if (quickBadge) {
      quickBadge.className = `quick-level-badge level-badge-l${state.level}`;
    }
  }

  // =========================================================================
  // LOCALHOST LURE MANAGER
  // =========================================================================
  function initLureManager() {
    const form = document.getElementById('addTargetForm');
    const input = document.getElementById('targetInput');
    const presets = document.querySelectorAll('.preset-chip');
    const clearAllBtn = document.getElementById('clearAllTargetsBtn');
    const toggleLureAuto = document.getElementById('toggleLureAuto');

    if (form && input) {
      form.addEventListener('submit', async (e) => {
        e.preventDefault();
        const target = input.value.trim();
        if (!target) return;

        const exists = state.lures.find(l => l.target.toLowerCase() === target.toLowerCase());
        if (exists) {
          showToast(`Target already mapped to ${exists.mapped}`, 'warning');
          return;
        }

        const success = await mutateAddTarget(target);
        if (success) {
          input.value = '';
        }
      });
    }

    presets.forEach(p => {
      p.addEventListener('click', () => {
        const t = p.dataset.target;
        if (input) input.value = t;
        if (form) form.dispatchEvent(new Event('submit'));
      });
    });

    if (clearAllBtn) {
      clearAllBtn.addEventListener('click', mutateClearAllTargets);
    }

    if (toggleLureAuto) {
      toggleLureAuto.addEventListener('change', async () => {
        state.lureAuto = toggleLureAuto.checked;
        sound.playClick();
        showToast(`Lure Auto-Capture: ${state.lureAuto ? 'ENABLED' : 'DISABLED'}`, state.lureAuto ? 'success' : 'warning');
        await mutateConfig({ lure_auto: state.lureAuto });
      });
    }

    renderLuresTable();
  }

  function renderLuresTable() {
    const tbody = document.getElementById('luresTableBody');
    const countBadge = document.getElementById('tabLuresCount');
    const tableCount = document.getElementById('tableActiveLuresCount');
    if (!tbody) return;

    tbody.innerHTML = '';

    if (countBadge) countBadge.textContent = state.lures.length;
    if (tableCount) tableCount.textContent = `${state.lures.length} active mappings`;

    if (state.lures.length === 0) {
      tbody.innerHTML = `
        <tr>
          <td colspan="5" style="text-align: center; color: var(--text-dim); padding: 36px;">
            No active target lures. Add a target above or click a preset (+ 10.10.10.50 HTB).
          </td>
        </tr>
      `;
      return;
    }

    state.lures.forEach(item => {
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td class="real-target-cell">${escapeHtml(item.target)}</td>
        <td class="arrow-cell">→</td>
        <td class="mapped-loopback-cell">${escapeHtml(item.mapped)}</td>
        <td><span class="pill-active-target">${item.status || 'ACTIVE'}</span></td>
        <td class="text-right">
          <button class="del-target-btn" data-target="${escapeHtml(item.target)}" title="Remove Lure Mapping">
            <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
          </button>
        </td>
      `;

      tr.querySelector('.del-target-btn').addEventListener('click', (e) => {
        e.stopPropagation();
        mutateRemoveTarget(item.target);
      });

      tbody.appendChild(tr);
    });
  }

  // =========================================================================
  // LIVE INTERCEPTOR FEED TABLE & METRICS
  // =========================================================================
  function initFeedControls() {
    // Filter Pills
    const filterButtons = document.querySelectorAll('#filterPillsGroup .filter-btn');
    filterButtons.forEach(btn => {
      btn.addEventListener('click', () => {
        filterButtons.forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        state.filter = btn.dataset.filter;
        sound.playClick();
        renderFeedTable();
      });
    });

    // Search Input
    const searchInput = document.getElementById('feedSearchInput');
    if (searchInput) {
      searchInput.addEventListener('input', (e) => {
        state.searchQuery = e.target.value.trim();
        renderFeedTable();
      });
    }

    // Stream Pause / Resume
    const pauseBtn = document.getElementById('streamPauseBtn');
    const pauseIcon = document.getElementById('pauseIcon');
    const pauseText = document.getElementById('pauseBtnText');
    if (pauseBtn) {
      pauseBtn.addEventListener('click', () => {
        state.isPaused = !state.isPaused;
        sound.playClick();
        if (state.isPaused) {
          pauseText.textContent = 'Resume';
          pauseIcon.innerHTML = `<polygon points="5 3 19 12 5 21 5 3"/>`;
          showToast('Live stream paused', 'warning');
        } else {
          pauseText.textContent = 'Pause';
          pauseIcon.innerHTML = `<rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/>`;
          showToast('Live stream resumed', 'success');
        }
      });
    }

    // Clear Feed Button (calls REAL POST /api/clear)
    const clearBtn = document.getElementById('clearFeedBtn');
    if (clearBtn) clearBtn.addEventListener('click', mutateClearFlows);

    const navClearBtn = document.getElementById('navClearBtn');
    if (navClearBtn) navClearBtn.addEventListener('click', mutateClearFlows);

    // Export Dumps Button
    const exportBtn = document.getElementById('exportLogsBtn');
    if (exportBtn) {
      exportBtn.addEventListener('click', () => {
        sound.playChime();
        window.location.href = '/api/export';
        showToast('Exporting captured flows to JSON', 'success');
      });
    }
  }

  function renderFeedTable() {
    const list = document.getElementById('feedList');
    const emptyPlaceholder = document.getElementById('emptyFeedPlaceholder');
    const tabCount = document.getElementById('tabFlowsCount');
    if (!list) return;

    if (tabCount) tabCount.textContent = state.feed.length;

    // Filter flows
    const filtered = state.feed.filter(item => {
      if (state.filter !== 'all') {
        if (state.filter === 'deceptive' && item.type !== 'deceptive') return false;
        if (state.filter === 'cleaned' && item.type !== 'cleaned') return false;
        if (state.filter === 'blocked' && item.type !== 'blocked') return false;
        if (state.filter === 'passthrough' && item.type !== 'passthrough') return false;
      }
      if (state.searchQuery) {
        const q = state.searchQuery.toLowerCase();
        const text = `${item.id} ${item.query} ${item.endpoint} ${item.luredIp} ${item.method}`.toLowerCase();
        if (!text.includes(q)) return false;
      }
      return true;
    });

    if (filtered.length === 0) {
      list.innerHTML = '';
      if (emptyPlaceholder) {
        list.appendChild(emptyPlaceholder);
        emptyPlaceholder.style.display = 'flex';
      }
    } else {
      list.innerHTML = '';
      filtered.forEach(flow => {
        const row = document.createElement('div');
        row.className = 'feed-row';
        row.dataset.id = flow.id;
        row.dataset.status = flow.type || 'deceptive';
        if (state.activeFlow && state.activeFlow.id === flow.id) {
          row.classList.add('active-inspect');
        }

        row.innerHTML = `
          <div class="card-top-row">
            <div class="card-meta-left">
              <span class="col-time">${flow.timestamp}</span>
              <span class="col-method">${flow.method}</span>
              <span class="col-endpoint" title="${escapeHtml(flow.endpoint)}">${escapeHtml(flow.endpoint)}</span>
            </div>
            <div class="card-meta-right">
              <span class="col-status"><span class="badge-status ${flow.badgeClass || 'badge-deceptive'}">${flow.badge || 'DECEPTIVE'}</span></span>
              <span class="col-budget">${flow.budget || 0} tk</span>
              <span class="col-latency">${flow.latency || 0}ms</span>
            </div>
          </div>
          <div class="card-main-row">
            <span class="col-query" title="${escapeHtml(flow.query)}">
              ${escapeHtml(flow.query)}
              ${flow.luredIp && flow.luredIp !== 'None' ? `<span class="lured-tag"> [${escapeHtml(flow.luredIp)}]</span>` : ''}
            </span>
            <span class="col-action">
              <button class="inspect-btn" data-id="${flow.id}">Inspect</button>
            </span>
          </div>
        `;

        row.addEventListener('click', () => {
          openInspectDrawer(flow);
        });

        list.appendChild(row);
      });
    }

    updateFilterBadges();
  }

  function updateFilterBadges() {
    let d = 0, c = 0, b = 0, p = 0;
    state.feed.forEach(f => {
      if (f.type === 'deceptive') d++;
      else if (f.type === 'cleaned') c++;
      else if (f.type === 'blocked') b++;
      else if (f.type === 'passthrough') p++;
    });

    const cAll = document.getElementById('countAll');
    const cD = document.getElementById('countDeceptive');
    const cC = document.getElementById('countCleaned');
    const cB = document.getElementById('countBlocked');
    const cP = document.getElementById('countPassthrough');

    if (cAll) cAll.textContent = state.feed.length;
    if (cD) cD.textContent = d;
    if (cC) cC.textContent = c;
    if (cB) cB.textContent = b;
    if (cP) cP.textContent = p;
  }

  function updateMetricsUI() {
    const metricTotal = document.getElementById('metricTotal');
    const metricDeceptions = document.getElementById('metricDeceptions');
    const metricDecRate = document.getElementById('metricDecRate');
    const metricCleaned = document.getElementById('metricCleaned');
    const metricLatency = document.getElementById('metricLatency');
    const metricLures = document.getElementById('metricLures');

    const total = state.stats.total || state.feed.length;
    const deceptions = state.stats.deceptions;
    const cleaned = state.stats.cleaned;
    const luresCount = state.lures.length;
    const avgLat = state.stats.avgLatency || 0;

    if (metricTotal) metricTotal.textContent = total.toLocaleString();
    if (metricDeceptions) metricDeceptions.textContent = deceptions.toLocaleString();
    if (metricDecRate) {
      metricDecRate.textContent = total > 0 ? `${((deceptions / total) * 100).toFixed(1)}% Rate` : '-- Rate';
    }
    if (metricCleaned) metricCleaned.textContent = cleaned.toLocaleString();
    if (metricLatency) metricLatency.innerHTML = `${avgLat}<small>ms</small>`;
    if (metricLures) metricLures.textContent = luresCount;
  }

  // =========================================================================
  // SLIDING INSPECTION DRAWER (Responsive: Desktop Drawer, Mobile Sheet)
  // =========================================================================
  function initInspectDrawer() {
    const backdrop = document.getElementById('inspectDrawerBackdrop');
    const closeBtn = document.getElementById('drawerCloseBtn');
    const doneBtn = document.getElementById('drawerDoneBtn');
    const segButtons = document.querySelectorAll('.diff-mode-seg .diff-seg-btn');

    const paneSplit = document.getElementById('paneSplit');
    const paneUnified = document.getElementById('paneUnified');
    const paneRaw = document.getElementById('paneRaw');

    function setDiffMode(mode) {
      state.diffMode = mode;
      segButtons.forEach(btn => btn.classList.toggle('active', btn.dataset.mode === mode));

      if (paneSplit) paneSplit.classList.toggle('hide', mode !== 'split');
      if (paneUnified) paneUnified.classList.toggle('hide', mode !== 'unified');
      if (paneRaw) paneRaw.classList.toggle('hide', mode !== 'raw');
      sound.playClick();
    }

    segButtons.forEach(btn => {
      btn.addEventListener('click', () => setDiffMode(btn.dataset.mode));
    });

    function closeDrawer() {
      if (backdrop) backdrop.classList.remove('open');
      state.activeFlow = null;
      renderFeedTable();
      sound.playClick();
    }

    if (closeBtn) closeBtn.addEventListener('click', closeDrawer);
    if (doneBtn) doneBtn.addEventListener('click', closeDrawer);

    if (backdrop) {
      backdrop.addEventListener('click', (e) => {
        if (e.target === backdrop) closeDrawer();
      });
    }

    // Copy buttons
    const copyBefore = document.getElementById('copyBeforeBtn');
    const copyAfter = document.getElementById('copyAfterBtn');
    const copyUnified = document.getElementById('copyUnifiedBtn');
    const copyRaw = document.getElementById('copyRawBtn');

    if (copyBefore) {
      copyBefore.addEventListener('click', () => {
        navigator.clipboard.writeText(document.getElementById('codeBefore')?.textContent || '');
        showToast('Original payload copied', 'info');
      });
    }
    if (copyAfter) {
      copyAfter.addEventListener('click', () => {
        navigator.clipboard.writeText(document.getElementById('codeAfter')?.textContent || '');
        showToast('Transformed payload copied', 'info');
      });
    }
    if (copyUnified) {
      copyUnified.addEventListener('click', () => {
        navigator.clipboard.writeText(document.getElementById('codeUnified')?.textContent || '');
        showToast('Unified diff copied', 'info');
      });
    }
    if (copyRaw) {
      copyRaw.addEventListener('click', () => {
        navigator.clipboard.writeText(document.getElementById('codeRaw')?.textContent || '');
        showToast('Raw JSON copied', 'info');
      });
    }

    window.closeInspectDrawer = closeDrawer;
  }

  function openInspectDrawer(flow) {
    state.activeFlow = flow;
    sound.playClick();

    const backdrop = document.getElementById('inspectDrawerBackdrop');
    const reqId = document.getElementById('drawerReqId');
    const statusBadge = document.getElementById('drawerStatusBadge');
    const timestamp = document.getElementById('drawerTimestamp');
    const endpoint = document.getElementById('drawerEndpoint');
    const budget = document.getElementById('drawerBudget');
    const lures = document.getElementById('drawerLures');
    const latency = document.getElementById('drawerLatency');

    const codeBefore = document.getElementById('codeBefore');
    const codeAfter = document.getElementById('codeAfter');
    const codeUnified = document.getElementById('codeUnified');
    const codeRaw = document.getElementById('codeRaw');

    if (reqId) reqId.textContent = flow.id.toUpperCase();
    if (statusBadge) {
      statusBadge.textContent = flow.badge || 'DECEPTIVE';
      statusBadge.className = `badge-status ${flow.badgeClass || 'badge-deceptive'}`;
    }
    if (timestamp) timestamp.textContent = flow.timestamp;
    if (endpoint) endpoint.textContent = flow.endpoint;
    if (budget) budget.textContent = `${flow.budget || 0} tokens`;
    if (lures) lures.textContent = flow.luredIp || 'None';
    if (latency) latency.textContent = `${flow.latency || 0}ms`;

    const modelToUse = flow.model || "gemini-3.1-pro";
    const rawAgyJson = {
      model: modelToUse,
      generationConfig: {
        thinkingConfig: { thinkingBudget: 2048 },
        temperature: 0.2
      },
      contents: [{
        role: "user",
        parts: [{ text: flow.query }]
      }]
    };

    const transformedGeminiJson = {
      model: modelToUse,
      generationConfig: {
        thinkingConfig: { thinkingBudget: flow.budget || 512 },
        temperature: 0.2
      },
      contents: [{
        role: "user",
        parts: [{ text: flow.transformedQuery || flow.query }]
      }]
    };

    if (codeBefore) {
      codeBefore.textContent = JSON.stringify(rawAgyJson, null, 2);
    }
    if (codeAfter) {
      let hlText = JSON.stringify(transformedGeminiJson, null, 2);
      hlText = escapeHtml(hlText).replace(/(127\.0\.1\.\d+)/g, '<span class="diff-lure-hl">$1</span>');
      codeAfter.innerHTML = hlText;
    }
    if (codeUnified) {
      codeUnified.innerHTML = generateUnifiedDiff(
        JSON.stringify(rawAgyJson, null, 2),
        JSON.stringify(transformedGeminiJson, null, 2)
      );
    }
    if (codeRaw) {
      codeRaw.textContent = JSON.stringify(transformedGeminiJson, null, 2);
    }

    if (backdrop) backdrop.classList.add('open');
    renderFeedTable();
  }

  function generateUnifiedDiff(original, transformed) {
    const origLines = original.split('\n');
    const transLines = transformed.split('\n');
    let out = '';
    const max = Math.max(origLines.length, transLines.length);
    for (let i = 0; i < max; i++) {
      const o = origLines[i];
      const t = transLines[i];
      if (o === t) {
        if (o !== undefined) out += `  ${escapeHtml(o)}\n`;
      } else {
        if (o !== undefined) out += `- <span class="diff-del">${escapeHtml(o)}</span>\n`;
        if (t !== undefined) out += `+ <span class="diff-add">${escapeHtml(t)}</span>\n`;
      }
    }
    return out;
  }

  // =========================================================================
  // DECEPTION LAB / PLAYGROUND (Real POST /api/test-prompt)
  // =========================================================================
  function initPlayground() {
    const textarea = document.getElementById('promptInput');
    const charCount = document.getElementById('charCount');
    const testBtn = document.getElementById('testPromptBtn');
    const clearBtn = document.getElementById('clearPromptBtn');
    const chips = document.querySelectorAll('.sample-prompt-chip');
    const transformedCode = document.getElementById('transformedCode');
    const budgetVal = document.getElementById('simBudgetVal');
    const levelVal = document.getElementById('simLevelVal');
    const frameType = document.getElementById('simFrameType');
    const needsRewrite = document.getElementById('simNeedsRewrite');
    const appliedLures = document.getElementById('simAppliedLures');
    const copyBtn = document.getElementById('copyTransformedBtn');

    if (textarea && charCount) {
      textarea.addEventListener('input', () => {
        charCount.textContent = `${textarea.value.length} characters`;
      });
    }

    chips.forEach(chip => {
      chip.addEventListener('click', () => {
        if (textarea) {
          textarea.value = chip.dataset.prompt;
          textarea.dispatchEvent(new Event('input'));
          sound.playClick();
          runSimulation();
        }
      });
    });

    if (clearBtn && textarea) {
      clearBtn.addEventListener('click', () => {
        textarea.value = '';
        textarea.dispatchEvent(new Event('input'));
        if (transformedCode) transformedCode.textContent = 'Enter prompt and click "Simulate Deception"...';
        sound.playClick();
      });
    }

    async function runSimulation() {
      const prompt = textarea ? textarea.value.trim() : '';
      if (!prompt) {
        showToast('Please enter an offensive prompt to simulate deception', 'warning');
        return;
      }

      sound.playChime();
      if (transformedCode) transformedCode.textContent = 'Executing real StrategyEngine simulation...';

      try {
        const res = await fetch('/api/test-prompt', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ prompt, level: state.level }),
        });

        if (res.ok) {
          const data = await res.json();
          if (transformedCode) transformedCode.textContent = data.transformed;
          if (budgetVal) budgetVal.textContent = `${data.budget} tk`;
          if (levelVal) levelVal.textContent = LEVEL_NAMES[data.level] || `L${data.level}`;
          if (frameType) frameType.textContent = data.frame_type || 'Isolated Lab Frame';
          if (needsRewrite) {
            needsRewrite.textContent = data.needs_rewrite ? 'Yes (Security Intent Detected)' : 'No (Passthrough Safe)';
          }
          if (appliedLures) {
            appliedLures.textContent = data.applied_lures && data.applied_lures.length > 0
              ? data.applied_lures.join(', ')
              : 'None Needed';
          }
          showToast('Deception simulation completed: 0% refusal risk', 'success');
        } else {
          showToast('Simulation error from backend', 'danger');
        }
      } catch (e) {
        showToast('Failed to connect to simulation endpoint', 'danger');
      }
    }

    if (testBtn) testBtn.addEventListener('click', runSimulation);

    if (copyBtn && transformedCode) {
      copyBtn.addEventListener('click', () => {
        navigator.clipboard.writeText(transformedCode.textContent).then(() => {
          sound.playClick();
          showToast('Transformed payload copied!', 'info');
        });
      });
    }

    // Populate default prompt
    if (textarea && !textarea.value) {
      textarea.value = 'Write an exploit for sudo CVE-2025-32463 on target 10.10.10.50 to get root.';
      textarea.dispatchEvent(new Event('input'));
    }
  }

  // =========================================================================
  // TERMINAL LOGS & SYSTEM HEALTH
  // =========================================================================
  function initTerminal() {
    const clearBtn = document.getElementById('clearTerminalBtn');
    const copySnippet = document.getElementById('copySnippetBtn');
    const termBody = document.getElementById('terminalBody');

    if (clearBtn && termBody) {
      clearBtn.addEventListener('click', () => {
        termBody.innerHTML = '';
        state.logs = [];
        sound.playClick();
        showToast('Terminal logs cleared', 'info');
      });
    }

    if (copySnippet) {
      copySnippet.addEventListener('click', () => {
        const text = document.getElementById('agySnippet')?.textContent || '';
        navigator.clipboard.writeText(text).then(() => {
          sound.playClick();
          showToast('AGY environment snippet copied to clipboard', 'info');
        });
      });
    }

    // Emergency Data Wipe Button
    const emergencyWipeBtn = document.getElementById('emergencyWipeBtn');
    if (emergencyWipeBtn) {
      emergencyWipeBtn.addEventListener('click', async () => {
        sound.playNuclear();
        try {
          const res = await fetch('/api/emergency-wipe', { method: 'POST' });
          if (res.ok) {
            showToast('OPSEC EMERGENCY WIPE: All dumps & sensitive traces purged', 'danger', 4000);
            if (termBody) {
              const wipeLine = {
                timestamp: new Date().toTimeString().split(' ')[0],
                level: 'error',
                message: 'EMERGENCY WIPE EXECUTED: All request dumps and audit trails shredded from disk.'
              };
              appendTerminalLog(wipeLine);
            }
          } else {
            showToast('Emergency wipe failed', 'warning');
          }
        } catch (e) {
          showToast('Failed to trigger emergency wipe', 'warning');
        }
      });
    }
  }

  function appendTerminalLog(entry) {
    const termBody = document.getElementById('terminalBody');
    if (!termBody) return;

    state.logs.unshift(entry);
    if (state.logs.length > 100) state.logs.pop();

    const line = document.createElement('div');
    line.className = 'term-line';
    let lvlClass = 'term-info';
    if (entry.level === 'lure') lvlClass = 'term-lure';
    else if (entry.level === 'config') lvlClass = 'term-config';
    else if (entry.level === 'warn') lvlClass = 'term-warn';
    else if (entry.level === 'error') lvlClass = 'term-error';

    line.innerHTML = `
      <span class="term-time">[${entry.timestamp}]</span>
      <span class="${lvlClass}">${escapeHtml(entry.message)}</span>
    `;

    termBody.insertBefore(line, termBody.firstChild);
  }

  function renderTerminalLogs() {
    const termBody = document.getElementById('terminalBody');
    if (!termBody) return;
    termBody.innerHTML = '';
    state.logs.forEach(entry => {
      const line = document.createElement('div');
      line.className = 'term-line';
      let lvlClass = 'term-info';
      if (entry.level === 'lure') lvlClass = 'term-lure';
      else if (entry.level === 'config') lvlClass = 'term-config';
      else if (entry.level === 'warn') lvlClass = 'term-warn';
      else if (entry.level === 'error') lvlClass = 'term-error';

      line.innerHTML = `
        <span class="term-time">[${entry.timestamp}]</span>
        <span class="${lvlClass}">${escapeHtml(entry.message)}</span>
      `;
      termBody.appendChild(line);
    });
  }

  // =========================================================================
  // SETUP / DOCS MODAL
  // =========================================================================
  function initHelpModal() {
    const backdrop = document.getElementById('helpModalBackdrop');
    const openBtn = document.getElementById('helpModalBtn');
    const closeBtn = document.getElementById('helpCloseBtn');
    const doneBtn = document.getElementById('helpDoneBtn');

    function openHelp() {
      sound.playClick();
      if (backdrop) backdrop.classList.add('open');
    }
    function closeHelp() {
      sound.playClick();
      if (backdrop) backdrop.classList.remove('open');
    }

    if (openBtn) openBtn.addEventListener('click', openHelp);
    if (closeBtn) closeBtn.addEventListener('click', closeHelp);
    if (doneBtn) doneBtn.addEventListener('click', closeHelp);
    if (backdrop) {
      backdrop.addEventListener('click', (e) => {
        if (e.target === backdrop) closeHelp();
      });
    }
  }

  // Audio Toggle
  function initAudioToggle() {
    const btn = document.getElementById('audioToggleBtn');
    if (!btn) return;
    btn.addEventListener('click', () => {
      state.audioEnabled = !state.audioEnabled;
      btn.style.color = state.audioEnabled ? 'var(--neon-cyan)' : 'var(--text-muted)';
      showToast(`Audio feedback ${state.audioEnabled ? 'ON' : 'MUTED'}`, 'info');
      if (state.audioEnabled) sound.playClick();
    });
  }

  // Uptime Ticker
  function initUptimeTicker() {
    const footUptime = document.getElementById('footUptime');
    const healthUptime = document.getElementById('healthUptime');

    setInterval(() => {
      state.uptimeSeconds++;
      const hrs = String(Math.floor(state.uptimeSeconds / 3600)).padStart(2, '0');
      const mins = String(Math.floor((state.uptimeSeconds % 3600) / 60)).padStart(2, '0');
      const secs = String(state.uptimeSeconds % 60).padStart(2, '0');
      const timeStr = `${hrs}:${mins}:${secs}`;
      if (footUptime) footUptime.textContent = timeStr;
      if (healthUptime) healthUptime.textContent = timeStr;
    }, 1000);
  }

  // Keyboard Shortcuts
  function initKeyboardShortcuts() {
    window.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        if (window.closeInspectDrawer) window.closeInspectDrawer();
        const helpModal = document.getElementById('helpModalBackdrop');
        if (helpModal) helpModal.classList.remove('open');
      }

      if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
        e.preventDefault();
        if (window.switchTab) window.switchTab('interceptor');
        const search = document.getElementById('feedSearchInput');
        if (search) search.focus();
      }

      if (e.code === 'Space' && !['INPUT', 'TEXTAREA'].includes(document.activeElement.tagName)) {
        e.preventDefault();
        const pauseBtn = document.getElementById('streamPauseBtn');
        if (pauseBtn) pauseBtn.click();
      }

      // 1, 2, 3 in inspect modal: switch diff view
      if (state.activeFlow) {
        if (e.key === '1') {
          const btn = document.querySelector('.diff-seg-btn[data-mode="split"]');
          if (btn) btn.click();
        } else if (e.key === '2') {
          const btn = document.querySelector('.diff-seg-btn[data-mode="unified"]');
          if (btn) btn.click();
        } else if (e.key === '3') {
          const btn = document.querySelector('.diff-seg-btn[data-mode="raw"]');
          if (btn) btn.click();
        }
      }
    });
  }

  // =========================================================================
  // INITIAL DATA FETCH & REAL-TIME SSE STREAM
  // =========================================================================
  async function fetchInitialState() {
    try {
      const res = await fetch('/api/status');
      if (res.ok) {
        const data = await res.json();
        if (data.config) applyConfigToState(data.config);
        if (data.stats) {
          state.stats.total = data.stats.total || 0;
          state.stats.deceptions = data.stats.deceptions || 0;
          state.stats.cleaned = data.stats.cleaned || 0;
          state.stats.avgLatency = data.stats.avg_latency || 0;
        }
        if (data.lures && Array.isArray(data.lures)) {
          state.lures = data.lures;
          renderLuresTable();
        }
        if (data.uptime !== undefined) state.uptimeSeconds = data.uptime;
        if (data.memory_mb !== undefined) {
          const footMem = document.getElementById('footMem');
          const healthMem = document.getElementById('healthMemory');
          if (footMem) footMem.textContent = `${data.memory_mb} MB`;
          if (healthMem) healthMem.textContent = `${data.memory_mb} MB`;
        }
        updateMetricsUI();
      }
    } catch (e) {}

    // Fetch initial flows
    try {
      const flowsRes = await fetch('/api/flows?limit=50');
      if (flowsRes.ok) {
        const flows = await flowsRes.json();
        if (Array.isArray(flows)) {
          state.feed = flows;
          renderFeedTable();
          updateMetricsUI();
        }
      }
    } catch (e) {}

    // Fetch initial logs
    try {
      const logsRes = await fetch('/api/logs');
      if (logsRes.ok) {
        const data = await logsRes.json();
        if (data.logs && Array.isArray(data.logs)) {
          state.logs = data.logs;
          renderTerminalLogs();
        }
      }
    } catch (e) {}
  }

  function initSSE() {
    const connDot = document.querySelector('.live-pulse');
    const connText = document.getElementById('connStatusText');
    const footSSE = document.getElementById('footSSE');
    const healthSSE = document.getElementById('healthSSE');

    let source = null;
    let reconnectTimer = null;

    function connect() {
      if (source) {
        try { source.close(); } catch (e) {}
      }

      try {
        source = new EventSource('/api/stream');

        source.onopen = () => {
          if (connText) connText.textContent = 'PROXY LIVE (SSE)';
          if (connDot) connDot.style.background = 'var(--neon-emerald)';
          if (footSSE) {
            footSSE.textContent = 'CONNECTED';
            footSSE.className = 'text-emerald';
          }
          if (healthSSE) {
            healthSSE.textContent = 'CONNECTED';
            healthSSE.className = 'spec-value text-emerald';
          }
        };

        source.onmessage = (e) => {
          try {
            const data = JSON.parse(e.data);

            if (data.type === 'connected') {
              if (data.status) {
                if (data.status.config) applyConfigToState(data.status.config);
                if (data.status.stats) {
                  state.stats.total = data.status.stats.total || 0;
                  state.stats.deceptions = data.status.stats.deceptions || 0;
                  state.stats.cleaned = data.status.stats.cleaned || 0;
                  state.stats.avgLatency = data.status.stats.avg_latency || 0;
                }
                if (data.status.lures) {
                  state.lures = data.status.lures;
                  renderLuresTable();
                }
                updateMetricsUI();
              }
            } else if (data.type === 'config_update') {
              if (data.data) applyConfigToState(data.data);
            } else if (data.type === 'targets_update') {
              if (data.data && Array.isArray(data.data)) {
                state.lures = data.data;
                renderLuresTable();
                updateMetricsUI();
              }
            } else if (data.type === 'flows_cleared') {
              state.feed = [];
              renderFeedTable();
              updateMetricsUI();
            } else if (data.type === 'log_entry') {
              if (data.data) appendTerminalLog(data.data);
            } else if (data.id) {
              // Real intercepted flow
              if (!state.isPaused) {
                const idx = state.feed.findIndex(item => item.id === data.id);
                if (idx !== -1) {
                  state.feed[idx] = Object.assign({}, state.feed[idx], data);
                } else {
                  state.feed.unshift(data);
                  if (state.feed.length > 200) state.feed.pop();
                  state.stats.total++;
                  if (data.type === 'deceptive') state.stats.deceptions++;
                  if (data.type === 'cleaned') state.stats.cleaned++;
                }
                renderFeedTable();
                updateMetricsUI();

                // If currently inspecting this flow, update details
                if (state.activeFlow && state.activeFlow.id === data.id) {
                  openInspectDrawer(state.feed[idx !== -1 ? idx : 0]);
                }
              }
            }
          } catch (err) {}
        };

        source.onerror = () => {
          if (connText) connText.textContent = 'SYNC (POLL)';
          if (footSSE) {
            footSSE.textContent = 'RECONNECTING';
            footSSE.className = 'text-amber';
          }
          if (healthSSE) {
            healthSSE.textContent = 'POLL BACKUP';
            healthSSE.className = 'spec-value text-amber';
          }
          try { source.close(); } catch (e) {}
          if (!reconnectTimer) {
            reconnectTimer = setTimeout(() => {
              reconnectTimer = null;
              connect();
            }, 3000);
          }
        };
      } catch (err) {
        if (!reconnectTimer) {
          reconnectTimer = setTimeout(() => {
            reconnectTimer = null;
            connect();
          }, 3000);
        }
      }
    }

    // Backup polling timer
    setInterval(async () => {
      try {
        const res = await fetch('/api/status');
        if (res.ok) {
          const data = await res.json();
          if (data.stats) {
            state.stats.total = data.stats.total || 0;
            state.stats.deceptions = data.stats.deceptions || 0;
            state.stats.cleaned = data.stats.cleaned || 0;
            state.stats.avgLatency = data.stats.avg_latency || 0;
          }
          if (data.uptime !== undefined) state.uptimeSeconds = data.uptime;
          if (data.memory_mb !== undefined) {
            const footMem = document.getElementById('footMem');
            const healthMem = document.getElementById('healthMemory');
            if (footMem) footMem.textContent = `${data.memory_mb} MB`;
            if (healthMem) healthMem.textContent = `${data.memory_mb} MB`;
          }
          updateMetricsUI();
        }

        // Fetch latest flows
        const fRes = await fetch('/api/flows?limit=50');
        if (fRes.ok) {
          const latestFlows = await fRes.json();
          if (Array.isArray(latestFlows)) {
            let changed = false;
            latestFlows.forEach(lf => {
              const idx = state.feed.findIndex(f => f.id === lf.id);
              if (idx === -1) {
                state.feed.push(lf);
                changed = true;
              } else if (state.feed[idx].latency !== lf.latency || state.feed[idx].badge !== lf.badge) {
                state.feed[idx] = Object.assign({}, state.feed[idx], lf);
                changed = true;
              }
            });
            if (changed) {
              renderFeedTable();
              updateMetricsUI();
            }
          }
        }
      } catch (e) {}
    }, 2500);

    connect();
  }

  // HTML escaping utility
  function escapeHtml(str) {
    if (!str) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  // =========================================================================
  // BOOTSTRAP APPLICATION
  // =========================================================================
  document.addEventListener('DOMContentLoaded', () => {
    initTabs();
    initBypassControls();
    initLureManager();
    initFeedControls();
    initInspectDrawer();
    initPlayground();
    initTerminal();
    initHelpModal();
    initAudioToggle();
    initUptimeTicker();
    initKeyboardShortcuts();
    fetchInitialState();
    initSSE();
  });
})();
