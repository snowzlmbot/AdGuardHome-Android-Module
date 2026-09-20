const MODULE_ROOT = '/data/adb/modules/AdGuardHome';
const CONTROL = `${MODULE_ROOT}/scripts/lifecycle/control.sh`;
const DIAGNOSTICS = `${MODULE_ROOT}/scripts/diagnostics/diagnostics.sh`;

const messages = {
  zh: {
    'title.local': '本地 DNS', 'title.console': '控制台',
    'status.current': '当前状态', 'status.loading': '正在读取…', 'status.waiting': '等待 KernelSU 返回状态',
    'section.runtime': '运行控制', 'section.engine': '过滤引擎', 'section.dnsRoute': 'DNS 路由', 'section.mode': '工作模式',
    'section.dashboardEntry': '管理入口', 'section.optional': '可选功能', 'section.adapters': '独立适配器', 'section.fileRules': '去文件广告规则', 'section.fileRulesTitle': '已安装应用覆盖',
    'component.file': '文件', 'component.filter': '规则',
    'hint.autoRefresh': '操作后自动刷新', 'hint.isolation': '故障不会停止 DNS 核心',
    'action.start': '▶ 启动', 'action.pause': 'Ⅱ 暂停', 'action.resume': '↗ 恢复', 'action.restart': '↻ 重启核心',
    'action.openDashboard': '打开管理界面', 'action.queryLog': '打开查询日志', 'action.credentials': '查看登录凭据', 'action.logs': '查看模块日志', 'action.backup': '备份配置', 'action.refresh': '刷新状态', 'action.close': '关闭',
    'mode.unknown': '未知', 'mode.1': '内网兼容', 'mode.1help': '校园网 / 企业域名', 'mode.2': '纯加密', 'mode.3help': '域名上游引导',
    'dashboard.waiting': '等待核心启动…', 'adapter.proxy': '代理配置适配', 'adapter.file': '文件级去广告',
    'adapter.fileWarning': '高风险 · 默认关闭', 'adapter.proxyToggle': '切换代理适配', 'adapter.fileToggle': '切换文件适配',
    'policy.ipv6': 'IPv6 DNS 防泄漏', 'policy.ipv6Help': '阻断直连 IPv6 DNS', 'policy.encrypted': '853 加密 DNS 防泄漏', 'policy.encryptedHelp': 'DoT / DoQ 端口策略', 'policy.vpn': 'VPN 兼容旁路', 'policy.vpnHelp': 'VPN 运行时优先保证连接',
    'footer.refresh': '状态每 5 秒自动刷新', 'credential.title': '管理登录信息', 'credential.username': '用户名',
    'credential.password': '密码', 'credential.warning': '仅在你主动点击时读取。请勿截图公开。', 'logs.eyebrow': '脱敏诊断', 'logs.title': '最近模块日志', 'toast.logs': '日志读取失败',
    'toggle.on': '开启', 'toggle.off': '关闭',
    'fileRules.waiting': '等待规则状态', 'fileRules.help': '只处理已存在的应用目录，不会为未安装应用创建占位文件夹。', 'fileRules.packageLabel': '应用包名（可选）', 'fileRules.packagePlaceholder': 'com.example.app', 'fileRules.refresh': '↻ 更新规则并清理', 'fileRules.apply': '扫描并覆盖已安装应用', 'fileRules.meta': '规则 {state} · 已安装 {installed} · 已清理 {applied} · 待处理 {changed} · 缺失 {missing}',
    'overall.running': '运行中', 'overall.paused': '已暂停', 'overall.stopped': '已停止', 'overall.degraded': '部分功能异常', 'overall.failed': '启动失败',
    'summary.running': 'DNS 核心与过滤规则已生效', 'summary.filtersLoading': 'DNS 核心已运行，过滤规则仍在加载', 'summary.paused': '核心保留运行，DNS 重定向已撤销',
    'summary.stopped': '模块已停止；点击启动恢复', 'summary.degraded': '核心已运行，但部分组件未生效',
    'summary.failed': 'AdGuard Home 核心未启动',
    'toast.done': '操作已提交', 'toast.backup': '配置备份已创建', 'toast.mode': '模式已保存', 'toast.modePending': '模式已保存，核心恢复后生效',
    'toast.failed': '操作失败', 'toast.fileRules': '规则已更新并完成已安装应用扫描', 'toast.refreshed': '状态已刷新', 'toast.unavailable': 'AdGuard Home 尚未启动',
    'toast.bridge': '请在 KernelSU 模块 WebUI 中打开', 'toast.credentials': '凭据读取失败',
    'status.ready': '正常', 'status.running': '运行中', 'status.failed': '失败', 'status.degraded': '异常', 'status.removed': '已撤销',
    'status.unknown': '未知', 'status.disabled': '已关闭', 'status.blocked': '等待核心', 'status.paused': '已暂停', 'status.stopped': '已停止', 'status.loading': '加载中', 'status.unavailable': '不可用',
    'reason.missing_binary': '核心文件缺失，请重新刷入模块', 'reason.missing_config': '配置文件缺失', 'reason.invalid_config': '配置文件无效',
    'reason.invalid_ports': '端口配置无效', 'reason.runtime_config': '无法更新运行配置', 'reason.web_port_timeout': 'Web 服务启动超时',
    'reason.initial_configuration': '首次初始化失败', 'reason.dns_port_timeout': 'DNS 服务启动超时', 'reason.core_not_ready': '等待核心启动',
    'reason.discovery_failed': '无法读取 Android 网络状态', 'reason.no_network': '当前没有可用网络', 'reason.invalid_mode': 'DNS 模式无效',
    'reason.module_paused': '模块已暂停', 'reason.ready': '运行正常', 'reason.dns_not_exposed': '系统未公开 DNS 地址，但网络可用',
    'reason.mode_configuration': 'DNS 模式配置失败', 'reason.mode_restart_timeout': '模式切换后核心重启超时', 'reason.unknown': '请查看诊断状态'
    , 'network.wifi': 'Wi‑Fi', 'network.mobile': '移动数据', 'network.ethernet': '以太网', 'network.other': '其他网络', 'network.vpn': 'VPN'
  },
  en: {
    'title.local': 'LOCAL DNS', 'title.console': 'CONTROL',
    'status.current': 'CURRENT STATUS', 'status.loading': 'Loading…', 'status.waiting': 'Waiting for KernelSU status',
    'section.runtime': 'RUNTIME CONTROL', 'section.engine': 'Filtering engine', 'section.dnsRoute': 'DNS ROUTING', 'section.mode': 'Working mode',
    'section.dashboardEntry': 'DASHBOARD', 'section.optional': 'OPTIONAL FEATURES', 'section.adapters': 'Isolated adapters', 'section.fileRules': 'FILE AD RULES', 'section.fileRulesTitle': 'Installed app coverage',
    'component.file': 'FILE', 'component.filter': 'FILTERS',
    'hint.autoRefresh': 'Refreshes after actions', 'hint.isolation': 'Adapter failures do not stop DNS',
    'action.start': '▶ Start', 'action.pause': 'Ⅱ Pause', 'action.resume': '↗ Resume', 'action.restart': '↻ Restart core',
    'action.openDashboard': 'Open dashboard', 'action.queryLog': 'Open query log', 'action.credentials': 'Show credentials', 'action.logs': 'View module logs', 'action.backup': 'Backup config', 'action.refresh': 'Refresh status', 'action.close': 'Close',
    'mode.unknown': 'Unknown', 'mode.1': 'LAN compatible', 'mode.1help': 'Campus / enterprise domains', 'mode.2': 'Encrypted', 'mode.3help': 'Domain upstream bootstrap',
    'dashboard.waiting': 'Waiting for the core…', 'adapter.proxy': 'Proxy configuration adapter', 'adapter.file': 'File-level ad cleanup',
    'adapter.fileWarning': 'HIGH RISK · OFF BY DEFAULT', 'adapter.proxyToggle': 'Toggle proxy adapter', 'adapter.fileToggle': 'Toggle file adapter',
    'policy.ipv6': 'IPv6 DNS leak protection', 'policy.ipv6Help': 'Block direct IPv6 DNS', 'policy.encrypted': 'Encrypted DNS leak protection', 'policy.encryptedHelp': 'DoT / DoQ port policy', 'policy.vpn': 'VPN compatibility bypass', 'policy.vpnHelp': 'Prioritize VPN connectivity',
    'footer.refresh': 'Status refreshes every 5 seconds', 'credential.title': 'Dashboard credentials', 'credential.username': 'Username',
    'credential.password': 'Password', 'credential.warning': 'Read only after an explicit click. Do not share screenshots.', 'logs.eyebrow': 'REDACTED DIAGNOSTICS', 'logs.title': 'Recent module logs', 'toast.logs': 'Failed to read logs',
    'toggle.on': 'ON', 'toggle.off': 'OFF',
    'fileRules.waiting': 'Waiting for rule status', 'fileRules.help': 'Only existing app paths are processed; no placeholder folders are created for uninstalled apps.', 'fileRules.packageLabel': 'Package name (optional)', 'fileRules.packagePlaceholder': 'com.example.app', 'fileRules.refresh': '↻ Update rules & clean', 'fileRules.apply': 'Scan installed apps', 'fileRules.meta': 'Rules {state} · installed {installed} · cleaned {applied} · changed {changed} · missing {missing}',
    'overall.running': 'Running', 'overall.paused': 'Paused', 'overall.stopped': 'Stopped', 'overall.degraded': 'Partially degraded', 'overall.failed': 'Startup failed',
    'summary.running': 'DNS core and filtering rules are active', 'summary.filtersLoading': 'DNS core is running; filter lists are still loading', 'summary.paused': 'Core is running; DNS redirects are removed',
    'summary.stopped': 'The module is stopped; press Start to recover', 'summary.degraded': 'Core is running, but a component is inactive',
    'summary.failed': 'AdGuard Home core is not running',
    'toast.done': 'Action submitted', 'toast.backup': 'Configuration backup created', 'toast.mode': 'Mode saved', 'toast.modePending': 'Mode saved; it will apply after core recovery',
    'toast.failed': 'Action failed', 'toast.fileRules': 'Rules updated and installed-app scan completed', 'toast.refreshed': 'Status refreshed', 'toast.unavailable': 'AdGuard Home is not running',
    'toast.bridge': 'Open this page inside KernelSU module WebUI', 'toast.credentials': 'Failed to read credentials',
    'status.ready': 'Ready', 'status.running': 'Running', 'status.failed': 'Failed', 'status.degraded': 'Degraded', 'status.removed': 'Removed',
    'status.unknown': 'Unknown', 'status.disabled': 'Disabled', 'status.blocked': 'Waiting for core', 'status.paused': 'Paused', 'status.stopped': 'Stopped', 'status.loading': 'Loading', 'status.unavailable': 'Unavailable',
    'reason.missing_binary': 'Core binary is missing; reinstall the module', 'reason.missing_config': 'Configuration file is missing', 'reason.invalid_config': 'Configuration is invalid',
    'reason.invalid_ports': 'Port configuration is invalid', 'reason.runtime_config': 'Failed to update runtime configuration', 'reason.web_port_timeout': 'Web service startup timed out',
    'reason.initial_configuration': 'First-run configuration failed', 'reason.dns_port_timeout': 'DNS service startup timed out', 'reason.core_not_ready': 'Waiting for the core',
    'reason.discovery_failed': 'Unable to read Android network state', 'reason.no_network': 'No active network', 'reason.invalid_mode': 'Invalid DNS mode',
    'reason.module_paused': 'Module is paused', 'reason.ready': 'Running normally', 'reason.dns_not_exposed': 'Android did not expose DNS addresses, but the network is active',
    'reason.mode_configuration': 'DNS mode configuration failed', 'reason.mode_restart_timeout': 'Core restart timed out after mode change', 'reason.unknown': 'Check diagnostics for details'
    , 'network.wifi': 'Wi‑Fi', 'network.mobile': 'Mobile data', 'network.ethernet': 'Ethernet', 'network.other': 'Other network', 'network.vpn': 'VPN'
  }
};

let current = {};
let lockedLanguage = localStorage.getItem('agh-language');
let language = lockedLanguage || (/^zh/i.test(navigator.language || '') ? 'zh' : 'en');
const $ = (id) => document.getElementById(id);
const text = (key) => messages[language]?.[key] || messages.en[key] || key;

function applyLanguage() {
  document.documentElement.lang = language === 'zh' ? 'zh-CN' : 'en';
  document.querySelectorAll('[data-i18n]').forEach((node) => { node.textContent = text(node.dataset.i18n); });
  document.querySelectorAll('[data-i18n-aria]').forEach((node) => { node.setAttribute('aria-label', text(node.dataset.i18nAria)); });
  document.querySelectorAll('[data-i18n-placeholder]').forEach((node) => { node.setAttribute('placeholder', text(node.dataset.i18nPlaceholder)); });
  document.title = language === 'zh' ? 'AdGuard Home 控制台' : 'AdGuard Home Control';
}

function exec(command) {
  return new Promise((resolve, reject) => {
    if (!window.ksu?.exec) return reject(new Error('KSU_BRIDGE_UNAVAILABLE'));
    const callback = `agh_${Date.now()}_${Math.random().toString(16).slice(2)}`;
    window[callback] = (errno, stdout, stderr) => {
      delete window[callback];
      resolve({ errno: Number(errno), stdout: stdout || '', stderr: stderr || '' });
    };
    try { window.ksu.exec(command, '{}', callback); }
    catch (error) { delete window[callback]; reject(error); }
  });
}

function parseKeyValues(raw) {
  return Object.fromEntries(raw.split(/\r?\n/).filter(Boolean).map((line) => {
    const index = line.indexOf('=');
    return index < 0 ? [line, ''] : [line.slice(0, index), line.slice(index + 1)];
  }));
}

function localizedStatus(value) { return text(`status.${value || 'unknown'}`); }
function localizedReason(reason) { return text(`reason.${reason || 'unknown'}`); }
function localizedNetwork(state) {
  const base = text(`network.${state.network || 'other'}`);
  return state.vpn === 'true' ? `${base} + ${text('network.vpn')}` : base;
}

function showToast(message) {
  const node = $('toast');
  node.textContent = message;
  node.classList.add('show');
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => node.classList.remove('show'), 2400);
}

function setBusy(busy) {
  document.querySelectorAll('button').forEach((button) => { button.disabled = busy; });
  document.body.classList.toggle('busy', busy);
}

function applyFileRulesStatus(state) {
  const ruleState = state.file_rules_state || 'unknown';
  $('fileRulesState').textContent = ruleState;
  const packageName = state.file_package_filter && state.file_package_filter !== 'all' ? ` · ${state.file_package_filter}` : '';
  $('fileRulesMeta').textContent = `${text('fileRules.meta').replace('{state}', ruleState).replace('{installed}', state.file_targets_installed || '0').replace('{applied}', state.file_targets_applied || '0').replace('{changed}', state.file_targets_changed || '0').replace('{missing}', state.file_targets_missing || '0')}${packageName}`;
}

function applyStatus(state) {
  current = state;
  if (!lockedLanguage && /^(zh|en)$/.test(state.language || '')) {
    language = state.language;
    localStorage.setItem('agh-language', language);
    lockedLanguage = language;
    applyLanguage();
  }

  const overall = state.status || 'failed';
  $('overall').textContent = text(`overall.${overall}`);
  const reasonKey = overall === 'failed' ? state.core_reason : overall === 'degraded' ? (state.firewall_reason || state.core_reason) : overall;
  $('statusReason').textContent = text(`summary.${overall}`) || localizedReason(reasonKey);
  if (overall === 'running' && state.filters !== 'ready') $('statusReason').textContent = text('summary.filtersLoading');
  if (overall === 'failed' || overall === 'degraded') $('statusReason').textContent = localizedReason(reasonKey);
  $('signal').className = `signal ${overall}`;
  $('modeNumber').textContent = state.mode || '—';
  $('modeName').textContent = state.mode_name || text('mode.unknown');

  ['core', 'firewall', 'network', 'proxy', 'file_adapter', 'filters'].forEach((key) => {
    const node = $(key);
    const value = state[key] || 'unknown';
    node.textContent = key === 'network' && value !== 'unknown' ? `${localizedNetwork(state)} · ${localizedStatus(value)}` : localizedStatus(value);
    node.className = value;
  });
  $('webPort').textContent = state.core === 'ready' ? (state.web_port || '—') : '—';
  $('webUrl').textContent = state.web_url === 'unavailable' ? text('dashboard.waiting') : (state.web_url || text('dashboard.waiting'));
  $('openAdmin').disabled = state.web_url === 'unavailable' || !state.web_url;

  document.querySelectorAll('[data-mode]').forEach((button) => button.classList.toggle('active', button.dataset.mode === state.mode));
  updateToggle($('proxyToggle'), state.proxy_enabled === 'true');
  updateToggle($('fileToggle'), state.file_enabled === 'true');
  applyFileRulesStatus(state);
  document.querySelectorAll('.policy-toggle').forEach((button) => {
    const key = button.dataset.policy;
    const enabled = key === 'block_853' ? state.dot_block === 'true' && state.doq_block === 'true' : state[ key === 'redirect_ipv6_dns' ? 'ipv6_dns_block' : key ] === 'true';
    updateToggle(button, enabled);
  });
}

function updateToggle(button, enabled) {
  button.classList.toggle('active', enabled);
  button.textContent = text(enabled ? 'toggle.on' : 'toggle.off');
  button.dataset.enabled = String(enabled);
}

async function refresh(silent = true) {
  try {
    const result = await exec(`sh ${DIAGNOSTICS}`);
    if (result.errno !== 0) throw new Error(result.stderr || 'diagnostics failed');
    applyStatus(parseKeyValues(result.stdout));
    if (!silent) showToast(text('toast.refreshed'));
  } catch (error) {
    $('overall').textContent = text('overall.failed');
    $('statusReason').textContent = error.message === 'KSU_BRIDGE_UNAVAILABLE' ? text('toast.bridge') : text('toast.failed');
    $('signal').className = 'signal failed';
  }
}

async function runControl(action) {
  const allowed = new Set(['start', 'pause', 'resume', 'restart-core', 'enable-proxy', 'disable-proxy', 'enable-file', 'disable-file']);
  if (!allowed.has(action)) return;
  setBusy(true);
  try {
    const result = await exec(`sh ${CONTROL} ${action}`);
    if (result.errno !== 0) throw new Error(result.stderr || action);
    showToast(text('toast.done'));
    await new Promise((resolve) => setTimeout(resolve, 1200));
    await refresh();
  } catch (error) { showToast(`${text('toast.failed')}: ${error.message}`); }
  finally { setBusy(false); }
}

async function setPolicy(policy, enabled) {
  const allowed = new Set(['redirect_ipv6_dns', 'block_853', 'bypass_vpn_traffic']);
  if (!allowed.has(policy)) return;
  setBusy(true);
  try {
    const keys = policy === 'block_853' ? ['block_ipv4_dot', 'block_ipv6_dot', 'block_ipv4_doq', 'block_ipv6_doq'] : [policy];
    for (const key of keys) {
      const result = await exec(`sh ${CONTROL} set-policy ${key} ${enabled ? 'true' : 'false'}`);
      if (result.errno !== 0) throw new Error(result.stderr || policy);
    }
    showToast(text('toast.done'));
    await new Promise((resolve) => setTimeout(resolve, 800));
    await refresh();
  } catch (error) { showToast(`${text('toast.failed')}: ${error.message}`); }
  finally { setBusy(false); }
}

async function setMode(mode) {
  if (!['1', '2', '3'].includes(mode)) return;
  setBusy(true);
  try {
    const result = await exec(`sh ${CONTROL} set-mode ${mode}`);
    if (result.errno !== 0) throw new Error(result.stderr || 'set-mode');
    showToast(text(current.core === 'ready' ? 'toast.mode' : 'toast.modePending'));
    await new Promise((resolve) => setTimeout(resolve, 800));
    await refresh();
  } catch (error) { showToast(`${text('toast.failed')}: ${error.message}`); }
  finally { setBusy(false); }
}

async function runFileRules(action) {
  const packageName = ($('filePackage').value || '').trim();
  if (packageName && !/^[A-Za-z0-9._-]+$/.test(packageName)) {
    showToast(text('toast.failed'));
    return;
  }
  setBusy(true);
  try {
    const argument = packageName ? ` ${packageName}` : '';
    const result = await exec(`sh ${CONTROL} ${action}${argument}`);
    if (result.errno !== 0) throw new Error(result.stderr || action);
    showToast(text('toast.fileRules'));
    await new Promise((resolve) => setTimeout(resolve, 1200));
    await refresh();
  } catch (error) { showToast(`${text('toast.failed')}: ${error.message}`); }
  finally { setBusy(false); }
}

async function showCredentials() {
  try {
    const result = await exec("sed -n 's/^username=//p;s/^password=//p' /data/adb/agh/state/credentials.conf");
    if (result.errno !== 0) throw new Error(result.stderr || 'credentials');
    const lines = result.stdout.trim().split(/\r?\n/);
    $('credentialUser').textContent = lines[0] || 'admin';
    $('credentialPassword').textContent = lines[1] || '—';
    const dialog = $('credentialDialog');
    if (dialog.showModal) dialog.showModal(); else dialog.setAttribute('open', '');
  } catch { showToast(text('toast.credentials')); }
}

async function createBackup() {
  try {
    const result = await exec(`sh ${CONTROL} backup`);
    if (result.errno !== 0) throw new Error(result.stderr || 'backup');
    showToast(text('toast.backup'));
  } catch (error) { showToast(`${text('toast.failed')}: ${error.message}`); }
}

async function showLogs() {
  try {
    const result = await exec(`sh ${DIAGNOSTICS} logs`);
    if (result.errno !== 0) throw new Error(result.stderr || 'logs');
    $('logOutput').textContent = result.stdout.trim() || '—';
    const dialog = $('logDialog');
    if (dialog.showModal) dialog.showModal(); else dialog.setAttribute('open', '');
  } catch { showToast(text('toast.logs')); }
}

async function openDashboard(path = '') {
  if (!current.web_url || current.web_url === 'unavailable') return showToast(text('toast.unavailable'));
  const result = await exec(`am start -a android.intent.action.VIEW -d ${current.web_url}${path}`);
  if (result.errno !== 0) showToast(text('toast.unavailable'));
}

applyLanguage();
document.querySelectorAll('[data-command]').forEach((button) => button.addEventListener('click', () => runControl(button.dataset.command)));
document.querySelectorAll('[data-mode]').forEach((button) => button.addEventListener('click', () => setMode(button.dataset.mode)));
$('refresh').addEventListener('click', () => refresh(false));
$('openAdmin').addEventListener('click', () => openDashboard(''));
$('openQueryLog').addEventListener('click', () => openDashboard('/#logs?response_status=all'));
$('showCredentials').addEventListener('click', showCredentials);
$('showLogs').addEventListener('click', showLogs);
$('createBackup').addEventListener('click', createBackup);
$('closeDialog').addEventListener('click', () => $('credentialDialog').close ? $('credentialDialog').close() : $('credentialDialog').removeAttribute('open'));
$('closeLogs').addEventListener('click', () => $('logDialog').close ? $('logDialog').close() : $('logDialog').removeAttribute('open'));
$('proxyToggle').addEventListener('click', () => runControl($('proxyToggle').dataset.enabled === 'true' ? 'disable-proxy' : 'enable-proxy'));
$('fileToggle').addEventListener('click', () => runControl($('fileToggle').dataset.enabled === 'true' ? 'disable-file' : 'enable-file'));
$('refreshFileRules').addEventListener('click', () => runFileRules('file-rules-refresh'));
$('applyFileRules').addEventListener('click', () => runFileRules('file-apply'));
document.querySelectorAll('.policy-toggle').forEach((button) => button.addEventListener('click', () => setPolicy(button.dataset.policy, button.dataset.enabled !== 'true')));

refresh(false);
setInterval(() => refresh(true), 5000);
