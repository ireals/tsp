/**
 * TEE Simulator Plus — Main WebUI JavaScript
 * Handles KSU bridge communication, tab navigation, and UI state.
 * No external dependencies.
 */

'use strict';

// ============================================================
// Constants
// ============================================================

/** Whitelist of allowed commands — must match bridge.sh WHITELIST */
const COMMAND_WHITELIST = [
  'keybox_add',
  'keybox_list',
  'keybox_select',
  'keybox_delete',
  'keybox_validate',
  'target_list_installed',
  'target_add',
  'target_remove',
  'target_import',
  'target_export',
  'profiler_run',
  'profiler_reference',
  'profiler_calibrate',
  'config_get',
  'config_set',
  'log_tail'
];

/** Path to bridge.sh on device */
const BRIDGE_SCRIPT = '/data/adb/modules/tee_simulator_plus/scripts/bridge.sh';

/** Duration (ms) for toast notifications */
const TOAST_DURATION = 3000;

// ============================================================
// KSU API Detection & Mock
// ============================================================

/**
 * Detect KSU WebUI API availability.
 * In development mode (no ksu object), provide a console-logging mock.
 */
function initKsuApi() {
  if (typeof window.ksu !== 'undefined') {
    // Running inside KernelSU WebUI — enable fullscreen
    try {
      window.ksu.fullScreen(true);
    } catch (e) {
      console.warn('[TSP] fullScreen not supported:', e);
    }
    return;
  }

  // Development mock — logs commands to console
  console.info('[TSP] KSU API not detected, using development mock');
  window.ksu = {
    exec: function (script, input) {
      console.log('[TSP Mock] exec:', script, input);
      // Return a simulated empty success response
      return JSON.stringify({ status: 0, data: null, message: 'mock' });
    },
    fullScreen: function (enabled) {
      console.log('[TSP Mock] fullScreen:', enabled);
    }
  };
}

// ============================================================
// Command Execution
// ============================================================

/**
 * Execute a command through the KSU bridge.
 * Validates against the whitelist, builds JSON input, and parses the response.
 *
 * @param {string} command — Command name (must be in COMMAND_WHITELIST)
 * @param {object} [params={}] — Optional parameters for the command
 * @returns {Promise<any>} — Resolved data field from the bridge response
 * @throws {Error} If command is not whitelisted or bridge returns an error
 */
async function execCommand(command, params = {}) {
  // Validate command against whitelist
  if (!COMMAND_WHITELIST.includes(command)) {
    throw new Error(`Command not allowed: ${command}`);
  }

  // Build JSON input matching bridge.sh expected format
  const input = JSON.stringify({ command, params });

  let rawResponse;
  try {
    rawResponse = window.ksu.exec(BRIDGE_SCRIPT, input);
  } catch (e) {
    throw new Error(`Bridge execution failed: ${e.message || e}`);
  }

  // Parse response JSON
  let response;
  try {
    response = JSON.parse(rawResponse);
  } catch (e) {
    throw new Error(`Invalid response from bridge: ${rawResponse}`);
  }

  // Check status
  if (response.status !== 0) {
    throw new Error(response.message || `Command failed with status ${response.status}`);
  }

  return response.data;
}

// ============================================================
// Utility Functions
// ============================================================

/**
 * Display an error toast notification.
 * @param {string} message — Error message to display
 */
function showError(message) {
  showToast(message, 'error');
}

/**
 * Display a success toast notification.
 * @param {string} message — Success message to display
 */
function showSuccess(message) {
  showToast(message, 'success');
}

/**
 * Internal toast display helper.
 * Creates a temporary notification element and auto-removes it.
 * @param {string} message — Text to display
 * @param {'error'|'success'} type — Toast type for styling
 */
function showToast(message, type) {
  // Remove any existing toast
  const existing = document.querySelector('.toast');
  if (existing) {
    existing.remove();
  }

  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.setAttribute('role', 'alert');
  toast.setAttribute('aria-live', 'polite');
  toast.textContent = message;

  document.body.appendChild(toast);

  // Trigger reflow for CSS transition
  void toast.offsetWidth;
  toast.classList.add('toast-visible');

  // Auto-dismiss
  setTimeout(() => {
    toast.classList.remove('toast-visible');
    toast.addEventListener('transitionend', () => toast.remove(), { once: true });
    // Fallback removal if transition doesn't fire
    setTimeout(() => toast.remove(), 500);
  }, TOAST_DURATION);
}

/**
 * Format an ISO timestamp string for display.
 * @param {string} isoString — ISO 8601 date string
 * @returns {string} Formatted date string (locale-aware)
 */
function formatTimestamp(isoString) {
  if (!isoString) return '—';
  try {
    const date = new Date(isoString);
    if (isNaN(date.getTime())) return isoString;
    return date.toLocaleString('ja-JP', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit'
    });
  } catch (e) {
    return isoString;
  }
}

// ============================================================
// Status Panel
// ============================================================

/**
 * Fetch module configuration and update the status panel.
 * Populates: module status indicator, active keybox name, target count.
 */
async function loadStatus() {
  const statusIndicator = document.getElementById('module-status-indicator');
  const statusText = document.getElementById('module-status-text');
  const activeKeyboxEl = document.getElementById('active-keybox-name');
  const targetCountEl = document.getElementById('target-count');

  try {
    const config = await execCommand('config_get', {});

    // Module status — active if config loads successfully
    if (statusIndicator) {
      statusIndicator.classList.add('active');
    }
    if (statusText) {
      statusText.textContent = 'Active';
    }

    // Active keybox name
    if (activeKeyboxEl) {
      if (config && config.activeKeyboxId) {
        // Try to find the keybox name from metadata
        const meta = (config.keyboxMetadata || []).find(
          (k) => k.id === config.activeKeyboxId
        );
        activeKeyboxEl.textContent = meta ? meta.name : config.activeKeyboxId;
      } else {
        activeKeyboxEl.textContent = '未設定';
      }
    }

    // Target count
    if (targetCountEl) {
      const targets = config && config.targetList ? config.targetList : [];
      targetCountEl.textContent = String(targets.length);
    }
  } catch (e) {
    // Module may not be running or bridge unavailable
    console.warn('[TSP] Failed to load status:', e);
    if (statusIndicator) {
      statusIndicator.classList.add('inactive');
    }
    if (statusText) {
      statusText.textContent = 'Inactive';
    }
    if (activeKeyboxEl) {
      activeKeyboxEl.textContent = '—';
    }
    if (targetCountEl) {
      targetCountEl.textContent = '0';
    }
  }
}

// ============================================================
// Tab Switching
// ============================================================

/**
 * Initialize tab navigation.
 * Handles active state, aria attributes, and panel visibility.
 */
function initTabs() {
  const tabButtons = document.querySelectorAll('[role="tab"]');
  const tabPanels = document.querySelectorAll('[role="tabpanel"]');

  tabButtons.forEach((button) => {
    button.addEventListener('click', () => {
      // Deactivate all tabs
      tabButtons.forEach((btn) => {
        btn.classList.remove('active');
        btn.setAttribute('aria-selected', 'false');
      });

      // Hide all panels
      tabPanels.forEach((panel) => {
        panel.classList.remove('active');
        panel.setAttribute('hidden', '');
      });

      // Activate clicked tab
      button.classList.add('active');
      button.setAttribute('aria-selected', 'true');

      // Show corresponding panel
      const panelId = button.getAttribute('aria-controls');
      const panel = document.getElementById(panelId);
      if (panel) {
        panel.classList.add('active');
        panel.removeAttribute('hidden');
      }
    });
  });
}

// ============================================================
// Keybox List
// ============================================================

/**
 * Load and render the keybox list in the Keybox tab.
 */
async function loadKeyboxList() {
  const listEl = document.getElementById('keybox-list');
  if (!listEl) return;

  listEl.innerHTML = '<p class="loading">読み込み中...</p>';

  try {
    const data = await execCommand('keybox_list', {});
    const keyboxes = Array.isArray(data) ? data : [];

    if (keyboxes.length === 0) {
      listEl.innerHTML = '<p class="empty-state">Keyboxが登録されていません</p>';
      return;
    }

    listEl.innerHTML = keyboxes
      .map(
        (kb) => `
        <div class="keybox-item${kb.active ? ' keybox-active' : ''}" data-id="${kb.id}">
          <div class="keybox-info">
            <span class="keybox-name">${escapeHtml(kb.name || kb.id)}</span>
            <span class="keybox-meta">${formatTimestamp(kb.addedAt)}</span>
          </div>
          <div class="keybox-actions">
            ${
              !kb.active
                ? `<button class="btn btn-small btn-outlined" data-action="select" data-id="${kb.id}" aria-label="選択">選択</button>`
                : '<span class="badge badge-active">使用中</span>'
            }
            <button class="btn btn-small btn-danger" data-action="delete" data-id="${kb.id}" aria-label="削除">削除</button>
          </div>
        </div>`
      )
      .join('');
  } catch (e) {
    listEl.innerHTML = `<p class="error-state">読み込みに失敗しました: ${escapeHtml(e.message)}</p>`;
  }
}

/**
 * Escape HTML special characters to prevent XSS.
 * @param {string} str — Raw string
 * @returns {string} Escaped string safe for innerHTML
 */
function escapeHtml(str) {
  const div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}

// ============================================================
// Initialization
// ============================================================

document.addEventListener('DOMContentLoaded', async () => {
  // Detect and initialize KSU API (or mock)
  initKsuApi();

  // Set up tab navigation
  initTabs();

  // Load module status
  await loadStatus();

  // Load initial keybox list
  await loadKeyboxList();
});

// ============================================================
// Task 17: Keybox Panel
// ============================================================

/**
 * Initialize the Keybox panel — upload button, file input, and delegated actions.
 */
function initKeyboxPanel() {
  const uploadBtn = document.getElementById('keybox-upload-btn');
  const fileInput = document.getElementById('keybox-file-input');
  const listEl = document.getElementById('keybox-list');

  // Upload button triggers hidden file input
  if (uploadBtn && fileInput) {
    uploadBtn.addEventListener('click', () => {
      fileInput.click();
    });

    fileInput.addEventListener('change', handleKeyboxUpload);
  }

  // Delegate click events on keybox list for select/delete
  if (listEl) {
    listEl.addEventListener('click', async (e) => {
      const btn = e.target.closest('[data-action]');
      if (!btn) return;

      const action = btn.getAttribute('data-action');
      const id = btn.getAttribute('data-id');

      if (action === 'select') {
        try {
          await execCommand('keybox_select', { id });
          await loadKeyboxList();
          await loadStatus();
          showSuccess('Keyboxを選択しました');
        } catch (err) {
          showError(`選択に失敗しました: ${err.message}`);
        }
      } else if (action === 'delete') {
        const confirmed = confirm('このKeyboxを削除しますか？');
        if (!confirmed) return;

        try {
          await execCommand('keybox_delete', { id });
          await loadKeyboxList();
          await loadStatus();
          showSuccess('Keyboxを削除しました');
        } catch (err) {
          showError(`削除に失敗しました: ${err.message}`);
        }
      }
    });
  }
}

/**
 * Handle keybox file upload.
 * Reads the selected file and sends it to the bridge for import.
 * @param {Event} event — File input change event
 */
async function handleKeyboxUpload(event) {
  const file = event.target.files[0];
  if (!file) return;

  try {
    const reader = new FileReader();
    const content = await new Promise((resolve, reject) => {
      reader.onload = () => resolve(reader.result);
      reader.onerror = () => reject(new Error('ファイルの読み込みに失敗しました'));
      reader.readAsText(file);
    });

    const displayName = file.name.replace(/\.[^.]+$/, '');
    await execCommand('keybox_add', { path: file.name, displayName, content });
    await loadKeyboxList();
    showSuccess(`Keybox "${displayName}" を追加しました`);
  } catch (err) {
    showError(`アップロードに失敗しました: ${err.message}`);
  }

  // Reset file input so the same file can be re-selected
  event.target.value = '';
}

// ============================================================
// Task 18: Target Panel
// ============================================================

/**
 * Initialize the Target panel — search, import/export, and app list.
 */
function initTargetPanel() {
  const searchInput = document.getElementById('target-search-input');
  const importBtn = document.getElementById('target-import-btn');
  const exportBtn = document.getElementById('target-export-btn');
  const importFileInput = document.getElementById('target-import-file');

  if (searchInput) {
    searchInput.addEventListener('input', (e) => {
      handleTargetSearch(e.target.value);
    });
  }

  if (importBtn) {
    importBtn.addEventListener('click', () => {
      if (importFileInput) {
        importFileInput.click();
      } else {
        handleTargetImport();
      }
    });
  }

  if (importFileInput) {
    importFileInput.addEventListener('change', handleTargetImport);
  }

  if (exportBtn) {
    exportBtn.addEventListener('click', handleTargetExport);
  }

  // Load initial target list
  loadTargetList();
}

/**
 * Load and render the installed app list with target toggle switches.
 */
async function loadTargetList() {
  const listEl = document.getElementById('target-list');
  if (!listEl) return;

  listEl.innerHTML = '<p class="loading">アプリ一覧を読み込み中...</p>';

  try {
    const data = await execCommand('target_list_installed', {});
    const apps = Array.isArray(data) ? data : [];

    if (apps.length === 0) {
      listEl.innerHTML = '<p class="empty-state">インストール済みアプリが見つかりません</p>';
      return;
    }

    listEl.innerHTML = apps
      .map(
        (app) => `
        <div class="target-item" data-package="${escapeHtml(app.packageName)}" data-name="${escapeHtml(app.appName || app.packageName)}">
          <div class="target-info">
            <span class="target-app-name">${escapeHtml(app.appName || app.packageName)}</span>
            <span class="target-package-name">${escapeHtml(app.packageName)}</span>
          </div>
          <label class="toggle-switch">
            <input type="checkbox" class="target-toggle" data-package="${escapeHtml(app.packageName)}" ${app.isTarget ? 'checked' : ''}>
            <span class="toggle-slider"></span>
          </label>
        </div>`
      )
      .join('');

    // Attach toggle event listeners
    listEl.querySelectorAll('.target-toggle').forEach((toggle) => {
      toggle.addEventListener('change', (e) => {
        const packageName = e.target.getAttribute('data-package');
        handleTargetToggle(packageName, e.target.checked);
      });
    });
  } catch (e) {
    listEl.innerHTML = `<p class="error-state">読み込みに失敗しました: ${escapeHtml(e.message)}</p>`;
  }
}

/**
 * Handle toggling an app's target state.
 * @param {string} packageName — Package name of the app
 * @param {boolean} isTarget — Whether the app should be a target
 */
async function handleTargetToggle(packageName, isTarget) {
  try {
    if (isTarget) {
      await execCommand('target_add', { packageName });
    } else {
      await execCommand('target_remove', { packageName });
    }
    await loadStatus();
  } catch (err) {
    showError(`ターゲット変更に失敗しました: ${err.message}`);
    // Revert the toggle visually
    const toggle = document.querySelector(`.target-toggle[data-package="${packageName}"]`);
    if (toggle) {
      toggle.checked = !isTarget;
    }
  }
}

/**
 * Filter displayed app items by partial match on package name or app name.
 * @param {string} query — Search query string
 */
function handleTargetSearch(query) {
  const items = document.querySelectorAll('.target-item');
  const lowerQuery = query.toLowerCase().trim();

  items.forEach((item) => {
    const packageName = (item.getAttribute('data-package') || '').toLowerCase();
    const appName = (item.getAttribute('data-name') || '').toLowerCase();

    if (!lowerQuery || packageName.includes(lowerQuery) || appName.includes(lowerQuery)) {
      item.style.display = '';
    } else {
      item.style.display = 'none';
    }
  });
}

/**
 * Import targets from a target.txt file.
 * @param {Event} [event] — File input change event (optional)
 */
async function handleTargetImport(event) {
  let content = null;

  if (event && event.target && event.target.files && event.target.files[0]) {
    const file = event.target.files[0];
    const reader = new FileReader();
    content = await new Promise((resolve, reject) => {
      reader.onload = () => resolve(reader.result);
      reader.onerror = () => reject(new Error('ファイルの読み込みに失敗しました'));
      reader.readAsText(file);
    });
    event.target.value = '';
  }

  try {
    await execCommand('target_import', { path: 'target.txt', content });
    await loadTargetList();
    await loadStatus();
    showSuccess('ターゲットリストをインポートしました');
  } catch (err) {
    showError(`インポートに失敗しました: ${err.message}`);
  }
}

/**
 * Export the current target list.
 */
async function handleTargetExport() {
  try {
    const data = await execCommand('target_export', {});
    const path = data && data.path ? data.path : '/data/adb/modules/tee_simulator_plus/config/target.txt';
    showSuccess(`ターゲットリストをエクスポートしました: ${path}`);
  } catch (err) {
    showError(`エクスポートに失敗しました: ${err.message}`);
  }
}

// ============================================================
// Task 19: Diagnostics Panel
// ============================================================

/**
 * Initialize the Diagnostics panel — run and calibrate buttons.
 */
function initDiagnosticsPanel() {
  const runBtn = document.getElementById('diagnostics-run-btn');
  const calibrateBtn = document.getElementById('diagnostics-calibrate-btn');

  if (runBtn) {
    runBtn.addEventListener('click', runDiagnostics);
  }

  if (calibrateBtn) {
    calibrateBtn.addEventListener('click', calibrateProfile);
  }
}

/**
 * Run the timing side-channel diagnostics profiler.
 */
async function runDiagnostics() {
  const sampleCountInput = document.getElementById('diagnostics-sample-count');
  const thresholdInput = document.getElementById('diagnostics-threshold');
  const resultsEl = document.getElementById('diagnostics-results');
  const runBtn = document.getElementById('diagnostics-run-btn');

  const sampleCount = sampleCountInput ? parseInt(sampleCountInput.value, 10) || 100 : 100;
  const threshold = thresholdInput ? parseFloat(thresholdInput.value) || 2.0 : 2.0;

  if (runBtn) {
    runBtn.disabled = true;
    runBtn.textContent = '実行中...';
  }

  if (resultsEl) {
    resultsEl.innerHTML = '<p class="loading">診断を実行中...</p>';
  }

  try {
    const data = await execCommand('profiler_run', { sampleCount, cpuCore: 0 });
    renderDiagnosticsResults(data, threshold);
  } catch (err) {
    if (resultsEl) {
      resultsEl.innerHTML = `<p class="error-state">診断に失敗しました: ${escapeHtml(err.message)}</p>`;
    }
  } finally {
    if (runBtn) {
      runBtn.disabled = false;
      runBtn.textContent = '診断実行';
    }
  }
}

/**
 * Render diagnostics results with color-coded judgment.
 * @param {object} data — Profiler result data
 * @param {number} [threshold=2.0] — Detection threshold for judgment
 */
function renderDiagnosticsResults(data, threshold = 2.0) {
  const resultsEl = document.getElementById('diagnostics-results');
  if (!resultsEl || !data) return;

  const tA = data.t_a != null ? data.t_a : data.tA;
  const tN = data.t_n != null ? data.t_n : data.tN;
  const diff = data.diff != null ? data.diff : (tA - tN);
  const ratio = data.ratio != null ? data.ratio : (tN !== 0 ? diff / tN : 0);
  const filteredBadSamples = data.filteredBadSamples != null ? data.filteredBadSamples : data.filtered_bad_samples || 0;
  const judgment = data.judgment || (Math.abs(ratio) > threshold ? 'Positive' : 'Negative');

  const isPositive = judgment === 'Positive';
  const judgmentColor = isPositive ? 'var(--color-danger, #e53935)' : 'var(--color-success, #43a047)';
  const judgmentLabel = isPositive ? '⚠️ Positive (検出あり)' : '✓ Negative (検出なし)';

  let html = `
    <div class="diagnostics-result-card">
      <h3>診断結果</h3>
      <div class="result-grid">
        <div class="result-item">
          <span class="result-label">T_a (実測値)</span>
          <span class="result-value">${typeof tA === 'number' ? tA.toFixed(3) : '—'} ms</span>
        </div>
        <div class="result-item">
          <span class="result-label">T_n (基準値)</span>
          <span class="result-value">${typeof tN === 'number' ? tN.toFixed(3) : '—'} ms</span>
        </div>
        <div class="result-item">
          <span class="result-label">差分 (diff)</span>
          <span class="result-value">${typeof diff === 'number' ? diff.toFixed(3) : '—'} ms</span>
        </div>
        <div class="result-item">
          <span class="result-label">比率 (ratio)</span>
          <span class="result-value">${typeof ratio === 'number' ? ratio.toFixed(4) : '—'}</span>
        </div>
        <div class="result-item">
          <span class="result-label">除外サンプル数</span>
          <span class="result-value">${filteredBadSamples}</span>
        </div>
        <div class="result-item result-judgment">
          <span class="result-label">判定</span>
          <span class="result-value" style="color: ${judgmentColor}; font-weight: bold;">${judgmentLabel}</span>
        </div>
      </div>
    </div>`;

  if (isPositive) {
    html += `
    <div class="advisory-card advisory-warning">
      <h4>⚠️ タイミングサイドチャネル検出リスク</h4>
      <p>診断の結果、TEE操作のタイミング差が検出可能なレベルにあります。以下の対策を推奨します：</p>
      <ul>
        <li><strong>Latency Equalizer を有効化</strong> — タイミング差を平準化します</li>
        <li><strong>サンプル数を増やして再測定</strong> — より正確な結果を得られます</li>
        <li><strong>閾値 (threshold) を確認</strong> — 現在の閾値: ${threshold}。環境に合わせて調整してください</li>
      </ul>
    </div>`;
  }

  resultsEl.innerHTML = html;
}

/**
 * Run calibration to establish a baseline profile.
 */
async function calibrateProfile() {
  const sampleCountInput = document.getElementById('diagnostics-sample-count');
  const calibrateBtn = document.getElementById('diagnostics-calibrate-btn');

  const sampleCount = sampleCountInput ? parseInt(sampleCountInput.value, 10) || 100 : 100;

  if (calibrateBtn) {
    calibrateBtn.disabled = true;
    calibrateBtn.textContent = 'キャリブレーション中...';
  }

  try {
    const data = await execCommand('profiler_calibrate', { sampleCount });
    const mean = data && data.mean != null ? data.mean.toFixed(3) : '—';
    const stddev = data && data.stddev != null ? data.stddev.toFixed(3) : '—';
    showSuccess(`キャリブレーション完了 — 平均: ${mean} ms, 標準偏差: ${stddev} ms`);
  } catch (err) {
    showError(`キャリブレーションに失敗しました: ${err.message}`);
  } finally {
    if (calibrateBtn) {
      calibrateBtn.disabled = false;
      calibrateBtn.textContent = 'キャリブレーション';
    }
  }
}

// ============================================================
// Task 20: Logs Panel
// ============================================================

/** Interval ID for log polling */
let logPollingInterval = null;

/**
 * Initialize the Logs panel — log level selector and polling.
 */
function initLogsPanel() {
  const logLevelSelect = document.getElementById('log-level-select');

  if (logLevelSelect) {
    logLevelSelect.addEventListener('change', (e) => {
      handleLogLevelChange(e.target.value);
    });
  }

  // Load logs immediately
  loadLogs();

  // Start polling
  startLogPolling();
}

/**
 * Load the latest log entries and render them in the log viewer.
 */
async function loadLogs() {
  const logViewer = document.getElementById('log-viewer');
  const refreshIndicator = document.getElementById('log-refresh-indicator');

  if (!logViewer) return;

  // Show refresh indicator
  if (refreshIndicator) {
    refreshIndicator.classList.add('active');
  }

  try {
    const data = await execCommand('log_tail', { lines: 200 });
    const logContent = typeof data === 'string' ? data : (data && data.content ? data.content : JSON.stringify(data, null, 2));
    logViewer.textContent = logContent;

    // Auto-scroll to bottom
    logViewer.scrollTop = logViewer.scrollHeight;
  } catch (err) {
    // Only show error if log viewer is empty (avoid spamming on poll failures)
    if (!logViewer.textContent) {
      logViewer.textContent = `ログの読み込みに失敗しました: ${err.message}`;
    }
  } finally {
    if (refreshIndicator) {
      refreshIndicator.classList.remove('active');
    }
  }
}

/**
 * Start polling for log updates every 5 seconds.
 */
function startLogPolling() {
  // Clear any existing interval
  if (logPollingInterval) {
    clearInterval(logPollingInterval);
  }

  logPollingInterval = setInterval(() => {
    loadLogs();
  }, 5000);
}

/**
 * Handle log level change.
 * @param {string} level — New log level value
 */
async function handleLogLevelChange(level) {
  try {
    await execCommand('config_set', { key: 'logLevel', value: level });
    showSuccess(`ログレベルを "${level}" に変更しました`);
  } catch (err) {
    showError(`ログレベルの変更に失敗しました: ${err.message}`);
  }
}

// ============================================================
// Updated DOMContentLoaded — Initialize All Panels
// ============================================================

// Patch the DOMContentLoaded to also initialize all panels.
// Since the original listener already runs, we add a second one for the panels.
document.addEventListener('DOMContentLoaded', () => {
  initKeyboxPanel();
  initTargetPanel();
  initDiagnosticsPanel();
  initLogsPanel();
});
