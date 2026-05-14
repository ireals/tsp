/**
 * TEE Simulator Plus — WebUI
 * KSU WebUI exec API uses callback-based async (matches Tricky-Addon pattern)
 */

'use strict';

const MODULE_DIR = '/data/adb/modules/tee-simulator-plus';
const BRIDGE_SCRIPT = `${MODULE_DIR}/scripts/bridge.sh`;
const TRICKY_STORE_DIR = '/data/adb/tricky_store';

// ============================================================
// KSU exec wrapper — callback-based async API
// ============================================================

/**
 * Execute a shell command via KSU WebUI exec API.
 * Uses the callback-based pattern matching Tricky-Addon and modern KSU.
 */
function ksuExec(command) {
  return new Promise((resolve, reject) => {
    if (typeof ksu === 'undefined' || typeof ksu.exec !== 'function') {
      // Development fallback
      console.log('[TSP Mock] exec:', command);
      resolve({ errno: 0, stdout: '{"status":0,"data":null}', stderr: '' });
      return;
    }

    const callbackName = `tsp_cb_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
    window[callbackName] = (errno, stdout, stderr) => {
      try {
        delete window[callbackName];
      } catch (e) {}
      resolve({ errno, stdout: stdout || '', stderr: stderr || '' });
    };

    try {
      ksu.exec(command, '{}', callbackName);
    } catch (e) {
      try { delete window[callbackName]; } catch (_) {}
      reject(e);
    }
  });
}

/**
 * Run a bridge command. Returns the parsed `data` field.
 */
async function execCommand(command, params = {}) {
  const input = JSON.stringify({ command, params });
  // Single-quote-escape input for shell
  const escaped = input.replace(/'/g, `'\\''`);
  const cmdline = `sh ${BRIDGE_SCRIPT} '${escaped}'`;

  let result;
  try {
    result = await ksuExec(cmdline);
  } catch (e) {
    throw new Error(`Bridge exec failed: ${e.message || e}`);
  }

  const stdout = (result.stdout || '').trim();
  if (!stdout) {
    if (result.stderr) {
      throw new Error(`Bridge stderr: ${result.stderr.trim()}`);
    }
    throw new Error('Empty response from bridge');
  }

  let parsed;
  try {
    parsed = JSON.parse(stdout);
  } catch (e) {
    throw new Error(`Invalid bridge response: ${stdout.substring(0, 200)}`);
  }

  if (parsed.status !== 0) {
    throw new Error(parsed.message || `Bridge returned status ${parsed.status}`);
  }
  return parsed.data;
}

// ============================================================
// Toast notifications
// ============================================================

function showToast(message, type = 'info') {
  const existing = document.querySelector('.toast');
  if (existing) existing.remove();

  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.textContent = message;
  document.body.appendChild(toast);
  void toast.offsetWidth;
  toast.classList.add('toast-visible');

  setTimeout(() => {
    toast.classList.remove('toast-visible');
    setTimeout(() => toast.remove(), 300);
  }, 3000);
}

const showError = (msg) => showToast(msg, 'error');
const showSuccess = (msg) => showToast(msg, 'success');

function escapeHtml(str) {
  const div = document.createElement('div');
  div.textContent = String(str ?? '');
  return div.innerHTML;
}

// ============================================================
// Status panel
// ============================================================

async function loadStatus() {
  const indicator = document.getElementById('module-status-indicator');
  const text = document.getElementById('module-status-text');
  const keyboxEl = document.getElementById('active-keybox-name');
  const targetCountEl = document.getElementById('target-count');

  try {
    const status = await execCommand('status_get');
    if (indicator) indicator.classList.add('active');
    if (text) text.textContent = '有効';
    if (keyboxEl) keyboxEl.textContent = status.keyboxPresent ? (status.keyboxName || 'keybox.xml') : '未設定';
    if (targetCountEl) targetCountEl.textContent = String(status.targetCount || 0);
  } catch (e) {
    console.warn('[TSP] status load failed:', e.message);
    if (indicator) indicator.classList.remove('active');
    if (text) text.textContent = '読込失敗';
    if (keyboxEl) keyboxEl.textContent = '—';
    if (targetCountEl) targetCountEl.textContent = '0';
  }
}

// ============================================================
// Tab switching
// ============================================================

function initTabs() {
  const tabs = document.querySelectorAll('[role="tab"]');
  const panels = document.querySelectorAll('[role="tabpanel"]');

  tabs.forEach((tab) => {
    tab.addEventListener('click', () => {
      tabs.forEach((t) => {
        t.classList.remove('active');
        t.setAttribute('aria-selected', 'false');
      });
      panels.forEach((p) => {
        p.classList.remove('active');
        p.setAttribute('hidden', '');
      });
      tab.classList.add('active');
      tab.setAttribute('aria-selected', 'true');
      const panelId = tab.getAttribute('aria-controls');
      const panel = document.getElementById(panelId);
      if (panel) {
        panel.classList.add('active');
        panel.removeAttribute('hidden');
      }
    });
  });
}

// ============================================================
// Keybox panel — single keybox at /data/adb/tricky_store/keybox.xml
// ============================================================

function initKeyboxPanel() {
  const uploadBtn = document.getElementById('btn-upload-keybox');
  const fileInput = document.getElementById('input-keybox-file');
  const removeBtn = document.getElementById('btn-remove-keybox');

  if (uploadBtn && fileInput) {
    uploadBtn.addEventListener('click', (e) => {
      e.preventDefault();
      fileInput.click();
    });
    fileInput.addEventListener('change', handleKeyboxUpload);
  }

  if (removeBtn) {
    removeBtn.addEventListener('click', handleKeyboxRemove);
  }
}

async function handleKeyboxUpload(event) {
  const file = event.target.files && event.target.files[0];
  if (!file) return;

  const uploadBtn = document.getElementById('btn-upload-keybox');
  if (uploadBtn) uploadBtn.disabled = true;

  try {
    // Read file as text
    const content = await new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.onerror = () => reject(new Error('ファイル読み込み失敗'));
      reader.readAsText(file);
    });

    // Write to a tmp location, then call upload (which validates and moves)
    const tmpPath = `/data/local/tmp/tsp_upload_${Date.now()}.xml`;
    // Use base64 to avoid shell escaping issues
    const b64 = btoa(unescape(encodeURIComponent(content)));
    const writeCmd = `echo '${b64}' | base64 -d > '${tmpPath}' && chmod 644 '${tmpPath}'`;
    const writeRes = await ksuExec(writeCmd);
    if (writeRes.errno !== 0) {
      throw new Error('一時ファイル書き込み失敗: ' + (writeRes.stderr || writeRes.errno));
    }

    await execCommand('keybox_upload', { path: tmpPath, displayName: file.name });

    // Cleanup tmp
    await ksuExec(`rm -f '${tmpPath}'`);

    showSuccess(`Keybox "${file.name}" を保存しました`);
    await loadKeyboxInfo();
    await loadStatus();
  } catch (err) {
    showError(`アップロード失敗: ${err.message}`);
  } finally {
    if (uploadBtn) uploadBtn.disabled = false;
    event.target.value = '';
  }
}

async function handleKeyboxRemove() {
  if (!confirm('Keyboxを削除しますか?')) return;
  try {
    await execCommand('keybox_remove');
    showSuccess('Keyboxを削除しました');
    await loadKeyboxInfo();
    await loadStatus();
  } catch (err) {
    showError(`削除失敗: ${err.message}`);
  }
}

async function loadKeyboxInfo() {
  const infoEl = document.getElementById('keybox-info');
  if (!infoEl) return;
  infoEl.innerHTML = '<p class="loading">読み込み中...</p>';

  try {
    const data = await execCommand('keybox_get');
    if (!data || !data.present) {
      infoEl.innerHTML = '<p class="empty-state">Keyboxが設定されていません。アップロードしてください。</p>';
      return;
    }
    infoEl.innerHTML = `
      <div class="keybox-item active">
        <div class="keybox-info">
          <div class="keybox-name">${escapeHtml(data.displayName || 'keybox.xml')}</div>
          <div class="keybox-detail">アルゴリズム: ${escapeHtml(data.algorithm || '不明')}</div>
          <div class="keybox-detail">サブジェクト: ${escapeHtml(data.certificateSubject || '不明')}</div>
          <div class="keybox-detail">ハッシュ: ${escapeHtml((data.hash || '').substring(0, 16))}...</div>
          <div class="keybox-detail">パス: ${escapeHtml(data.path || '')}</div>
        </div>
        <div class="keybox-actions">
          <button class="btn btn-outlined" id="btn-remove-keybox">削除</button>
        </div>
      </div>
    `;
    const removeBtn = document.getElementById('btn-remove-keybox');
    if (removeBtn) removeBtn.addEventListener('click', handleKeyboxRemove);
  } catch (err) {
    infoEl.innerHTML = `<p class="error-state">読み込み失敗: ${escapeHtml(err.message)}</p>`;
  }
}

// ============================================================
// Target panel — uses /data/adb/tricky_store/target.txt
// ============================================================

let _allApps = [];

function initTargetPanel() {
  const search = document.getElementById('input-target-search');
  if (search) {
    search.addEventListener('input', (e) => filterTargets(e.target.value));
  }
  const exportBtn = document.getElementById('btn-export-targets');
  if (exportBtn) exportBtn.addEventListener('click', handleTargetExport);
  const importBtn = document.getElementById('btn-import-targets');
  if (importBtn) importBtn.addEventListener('click', () => {
    const fi = document.getElementById('input-import-file');
    if (fi) fi.click();
  });
  const importFile = document.getElementById('input-import-file');
  if (importFile) importFile.addEventListener('change', handleTargetImport);
}

async function loadTargetList() {
  const listEl = document.getElementById('app-list');
  if (!listEl) return;
  listEl.innerHTML = '<p class="loading">アプリ一覧読み込み中...</p>';

  try {
    const data = await execCommand('target_list_installed');
    _allApps = Array.isArray(data) ? data : [];
    renderAppList(_allApps);
  } catch (err) {
    listEl.innerHTML = `<p class="error-state">読み込み失敗: ${escapeHtml(err.message)}</p>`;
  }
}

function renderAppList(apps) {
  const listEl = document.getElementById('app-list');
  if (!listEl) return;
  if (apps.length === 0) {
    listEl.innerHTML = '<p class="empty-state">アプリが見つかりません</p>';
    return;
  }
  listEl.innerHTML = apps.map((app) => `
    <div class="app-item" data-package="${escapeHtml(app.packageName)}" data-name="${escapeHtml((app.appName || app.packageName).toLowerCase())}">
      <div class="app-item-info">
        <div class="app-item-name">${escapeHtml(app.appName || app.packageName)}</div>
        <div class="app-item-package">${escapeHtml(app.packageName)}</div>
      </div>
      <label class="toggle-switch">
        <input type="checkbox" data-pkg="${escapeHtml(app.packageName)}" ${app.isTarget ? 'checked' : ''}>
        <span class="toggle-slider"></span>
      </label>
    </div>
  `).join('');
  listEl.querySelectorAll('input[type=checkbox]').forEach((cb) => {
    cb.addEventListener('change', (e) => {
      handleTargetToggle(e.target.getAttribute('data-pkg'), e.target.checked);
    });
  });
}

function filterTargets(query) {
  const q = (query || '').toLowerCase().trim();
  if (!q) { renderAppList(_allApps); return; }
  renderAppList(_allApps.filter((app) =>
    app.packageName.toLowerCase().includes(q) ||
    (app.appName || '').toLowerCase().includes(q)
  ));
}

async function handleTargetToggle(pkg, isTarget) {
  try {
    if (isTarget) await execCommand('target_add', { packageName: pkg });
    else await execCommand('target_remove', { packageName: pkg });
    await loadStatus();
    // Update local state
    const app = _allApps.find((a) => a.packageName === pkg);
    if (app) app.isTarget = isTarget;
  } catch (err) {
    showError(`変更失敗: ${err.message}`);
    const cb = document.querySelector(`input[data-pkg="${pkg}"]`);
    if (cb) cb.checked = !isTarget;
  }
}

async function handleTargetExport() {
  try {
    const data = await execCommand('target_export');
    showSuccess(`エクスポート: ${data.path || '/data/adb/tricky_store/target.txt'}`);
  } catch (err) {
    showError(`エクスポート失敗: ${err.message}`);
  }
}

async function handleTargetImport(event) {
  const file = event.target.files && event.target.files[0];
  if (!file) return;
  try {
    const content = await new Promise((resolve, reject) => {
      const r = new FileReader();
      r.onload = () => resolve(r.result);
      r.onerror = () => reject(new Error('読み込み失敗'));
      r.readAsText(file);
    });
    const tmpPath = `/data/local/tmp/tsp_targets_${Date.now()}.txt`;
    const b64 = btoa(unescape(encodeURIComponent(content)));
    await ksuExec(`echo '${b64}' | base64 -d > '${tmpPath}'`);
    const result = await execCommand('target_import', { path: tmpPath });
    await ksuExec(`rm -f '${tmpPath}'`);
    showSuccess(`インポート完了: ${result.imported || 0}件`);
    await loadTargetList();
    await loadStatus();
  } catch (err) {
    showError(`インポート失敗: ${err.message}`);
  } finally {
    event.target.value = '';
  }
}

// ============================================================
// Diagnostics panel
// ============================================================

function initDiagnosticsPanel() {
  const runBtn = document.getElementById('btn-run-diagnostics');
  const calBtn = document.getElementById('btn-calibrate');
  if (runBtn) runBtn.addEventListener('click', runDiagnostics);
  if (calBtn) calBtn.addEventListener('click', calibrateProfile);
}

async function runDiagnostics() {
  const sampleEl = document.getElementById('input-sample-count');
  const thresholdEl = document.getElementById('input-threshold');
  const sampleCount = sampleEl ? parseInt(sampleEl.value, 10) || 500 : 500;
  const runBtn = document.getElementById('btn-run-diagnostics');
  const resultsEl = document.getElementById('diagnostics-results');

  if (runBtn) { runBtn.disabled = true; runBtn.textContent = '実行中...'; }
  if (resultsEl) resultsEl.innerHTML = '<p class="loading">診断実行中...</p>';

  try {
    const data = await execCommand('profiler_run', { sampleCount, cpuCore: 0 });
    renderDiagnosticsResults(data);
  } catch (err) {
    if (resultsEl) resultsEl.innerHTML = `<p class="error-state">診断失敗: ${escapeHtml(err.message)}</p>`;
  } finally {
    if (runBtn) { runBtn.disabled = false; runBtn.textContent = '実行'; }
  }
}

function renderDiagnosticsResults(d) {
  const el = document.getElementById('diagnostics-results');
  if (!el || !d) return;
  const tA = d.attestedMeanMs ?? d.t_a ?? 0;
  const tN = d.nonAttestedMeanMs ?? d.t_n ?? 0;
  const diff = d.diffMs ?? d.diff ?? 0;
  const ratio = d.ratio ?? 0;
  const filtered = d.filteredBadSamples ?? 0;
  const total = d.totalSamples ?? d.sampleCount ?? 0;
  const judgment = d.judgment || (ratio > (d.threshold || 1.1) ? 'Positive' : 'Negative');
  const positive = judgment === 'Positive';

  el.innerHTML = `
    <div class="result-metric"><div class="result-metric-label">T_a (attested)</div><div class="result-metric-value">${Number(tA).toFixed(3)} ms</div></div>
    <div class="result-metric"><div class="result-metric-label">T_n (non-attested)</div><div class="result-metric-value">${Number(tN).toFixed(3)} ms</div></div>
    <div class="result-metric"><div class="result-metric-label">差分 (diff)</div><div class="result-metric-value">${Number(diff).toFixed(3)} ms</div></div>
    <div class="result-metric"><div class="result-metric-label">比率 (ratio)</div><div class="result-metric-value">${Number(ratio).toFixed(3)}x</div></div>
    <div class="result-metric"><div class="result-metric-label">外れ値</div><div class="result-metric-value">${filtered}/${total}</div></div>
    <div class="result-judgment ${positive ? 'positive' : 'negative'}">${positive ? '⚠ Positive (検知の可能性)' : '✓ Negative'}</div>
    ${positive ? `<div class="advisory">推奨: Latency_Equalizer を有効化、サンプル数を増やす、参照プロファイルを再キャリブレーション</div>` : ''}
  `;
}

async function calibrateProfile() {
  const sampleEl = document.getElementById('input-sample-count');
  const sampleCount = sampleEl ? parseInt(sampleEl.value, 10) || 500 : 500;
  const btn = document.getElementById('btn-calibrate');
  if (btn) { btn.disabled = true; btn.textContent = 'キャリブレーション中...'; }
  try {
    const data = await execCommand('profiler_calibrate', { sampleCount });
    showSuccess(`キャリブレーション完了: 平均=${Number(data.meanMs || 0).toFixed(3)}ms, σ=${Number(data.stddevMs || 0).toFixed(3)}ms`);
  } catch (err) {
    showError(`キャリブレーション失敗: ${err.message}`);
  } finally {
    if (btn) { btn.disabled = false; btn.textContent = 'キャリブレーション'; }
  }
}

// ============================================================
// Logs panel
// ============================================================

let _logPollInterval = null;

function initLogsPanel() {
  const sel = document.getElementById('select-log-level');
  if (sel) sel.addEventListener('change', (e) => handleLogLevelChange(e.target.value));
  loadLogs();
  if (_logPollInterval) clearInterval(_logPollInterval);
  _logPollInterval = setInterval(loadLogs, 5000);
}

async function loadLogs() {
  const viewer = document.getElementById('log-viewer');
  const refresh = document.getElementById('log-refresh-indicator');
  if (!viewer) return;
  if (refresh) refresh.removeAttribute('hidden');
  try {
    const data = await execCommand('log_tail', { lines: 200 });
    const content = (data && data.lines) ? data.lines.replace(/\\n/g, '\n') : '';
    viewer.textContent = content || '(ログなし)';
    viewer.scrollTop = viewer.scrollHeight;
  } catch (err) {
    if (!viewer.textContent) viewer.textContent = `ログ読込失敗: ${err.message}`;
  } finally {
    if (refresh) refresh.setAttribute('hidden', '');
  }
}

async function handleLogLevelChange(level) {
  try {
    await execCommand('config_set', { key: 'logLevel', value: level.toUpperCase() });
    showSuccess(`ログレベル: ${level}`);
  } catch (err) {
    showError(`変更失敗: ${err.message}`);
  }
}

// ============================================================
// Init
// ============================================================

document.addEventListener('DOMContentLoaded', async () => {
  if (typeof ksu !== 'undefined' && typeof ksu.fullScreen === 'function') {
    try { ksu.fullScreen(true); } catch (e) {}
  }
  initTabs();
  initKeyboxPanel();
  initTargetPanel();
  initDiagnosticsPanel();
  initLogsPanel();

  await loadStatus();
  await loadKeyboxInfo();
  await loadTargetList();
});
