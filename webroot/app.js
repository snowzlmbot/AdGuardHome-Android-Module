const MODULE_ROOT = '/data/adb/modules/AdGuardHome';
const CONTROL = `${MODULE_ROOT}/scripts/lifecycle/control.sh`;
const DIAGNOSTICS = `${MODULE_ROOT}/scripts/diagnostics/diagnostics.sh`;

const labels = {
  running: ['运行中', 'DNS 核心与防火墙规则均已就绪'],
  paused: ['已暂停', '核心保留运行，DNS 重定向已撤销'],
  stopped: ['已停止', '点击启动以恢复服务'],
  degraded: ['部分可用', '核心运行中，但部分组件未就绪'],
  failed: ['异常', '请查看组件状态或运行诊断'],
  unknown: ['正在检测', '等待 KernelSU 返回状态'],
};

let current = {};
let busy = false;
let toastTimer;

function execRoot(command) {
  return new Promise((resolve, reject) => {
    if (!window.ksu || typeof window.ksu.exec !== 'function') {
      reject(new Error('请从 KernelSU 管理器打开模块 WebUI'));
      return;
    }
    const callback = `agh_callback_${Date.now()}_${Math.random().toString(16).slice(2)}`;
    window[callback] = (errno, stdout, stderr) => {
      delete window[callback];
      resolve({ errno, stdout: stdout || '', stderr: stderr || '' });
    };
    try {
      window.ksu.exec(command, '{}', callback);
    } catch (error) {
      delete window[callback];
      reject(error);
    }
  });
}

function parseKv(text) {
  const result = {};
  text.split(/\r?\n/).forEach((line) => {
    const index = line.indexOf('=');
    if (index > 0) result[line.slice(0, index)] = line.slice(index + 1);
  });
  return result;
}

function setText(id, value) {
  const node = document.getElementById(id);
  if (node) node.textContent = value ?? '—';
}

function showToast(message, isError = false) {
  const node = document.getElementById('toast');
  node.textContent = message;
  node.style.borderColor = isError ? 'rgba(255,107,107,.55)' : 'rgba(150,255,115,.45)';
  node.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => node.classList.remove('show'), 2600);
}

function setToggle(id, enabled) {
  const button = document.getElementById(id);
  button.classList.toggle('active', enabled);
  button.setAttribute('aria-pressed', String(enabled));
  button.textContent = enabled ? '开启' : '关闭';
}

function render(state) {
  current = state;
  const status = state.status || 'unknown';
  const [title, detail] = labels[status] || labels.unknown;
  document.body.dataset.status = status;
  setText('overall', title);
  setText('statusReason', detail);
  setText('modeNumber', state.mode || '—');
  setText('modeName', state.mode_name || '未配置');
  setText('core', state.core || 'unknown');
  setText('firewall', state.firewall || 'unknown');
  setText('network', state.network || 'unknown');
  setText('proxy', state.proxy || (state.proxy_enabled === 'true' ? 'waiting' : 'disabled'));
  setText('file_adapter', state.file_adapter || (state.file_enabled === 'true' ? 'waiting' : 'disabled'));
  setText('webPort', state.web_port || '—');
  setText('webUrl', state.web_url || '尚未分配');
  document.getElementById('signal').className = `signal ${status}`;
  document.querySelectorAll('[data-mode]').forEach((button) => {
    button.classList.toggle('active', button.dataset.mode === state.mode);
  });
  setToggle('proxyToggle', state.proxy_enabled === 'true');
  setToggle('fileToggle', state.file_enabled === 'true');
}

async function refresh({ silent = false } = {}) {
  if (busy) return;
  busy = true;
  document.getElementById('refresh').classList.add('spinning');
  try {
    const result = await execRoot(`sh ${DIAGNOSTICS}`);
    if (result.errno !== 0) throw new Error(result.stderr || '状态读取失败');
    render(parseKv(result.stdout));
  } catch (error) {
    render({ status: 'unknown', mode_name: 'KernelSU WebUI 不可用' });
    if (!silent) showToast(error.message, true);
  } finally {
    busy = false;
    document.getElementById('refresh').classList.remove('spinning');
  }
}

async function runControl(action, successText) {
  if (busy) return;
  busy = true;
  try {
    const result = await execRoot(`sh ${CONTROL} ${action}`);
    if (result.errno !== 0) throw new Error(result.stderr || `操作失败：${action}`);
    showToast(successText);
    await new Promise((resolve) => setTimeout(resolve, 700));
  } catch (error) {
    showToast(error.message, true);
  } finally {
    busy = false;
    await refresh({ silent: true });
  }
}

async function openDashboard() {
  if (!current.web_url || current.web_url === 'unavailable') {
    showToast('管理端口尚未就绪', true);
    return;
  }
  const result = await execRoot(`am start -a android.intent.action.VIEW -d ${current.web_url}`);
  if (result.errno !== 0) showToast('无法打开浏览器', true);
}

async function showCredentials() {
  const result = await execRoot("sed -n 's/^username=//p;s/^password=//p' /data/adb/agh/state/credentials.conf");
  if (result.errno !== 0) {
    showToast('凭据尚未生成', true);
    return;
  }
  const lines = result.stdout.trim().split(/\r?\n/);
  setText('credentialUser', lines[0] || 'admin');
  setText('credentialPassword', lines[1] || '不可用');
  document.getElementById('credentialDialog').showModal();
}

document.getElementById('refresh').addEventListener('click', () => refresh());
document.querySelectorAll('[data-command]').forEach((button) => {
  const messages = {
    start: '启动请求已提交',
    pause: '过滤已暂停',
    resume: '过滤恢复请求已提交',
    'restart-core': '核心正在重启',
  };
  button.addEventListener('click', () => runControl(button.dataset.command, messages[button.dataset.command] || '操作已提交'));
});
document.querySelectorAll('[data-mode]').forEach((button) => {
  button.addEventListener('click', () => runControl(`set-mode ${button.dataset.mode}`, `已切换到模式 ${button.dataset.mode}`));
});
document.getElementById('openAdmin').addEventListener('click', openDashboard);
document.getElementById('showCredentials').addEventListener('click', showCredentials);
document.getElementById('closeDialog').addEventListener('click', () => document.getElementById('credentialDialog').close());
document.getElementById('proxyToggle').addEventListener('click', () => {
  const enabled = current.proxy_enabled === 'true';
  runControl(enabled ? 'disable-proxy' : 'enable-proxy', enabled ? '代理适配已关闭' : '代理适配已开启');
});
document.getElementById('fileToggle').addEventListener('click', () => {
  const enabled = current.file_enabled === 'true';
  runControl(enabled ? 'disable-file' : 'enable-file', enabled ? '文件适配已关闭' : '文件适配已开启');
});

refresh({ silent: true });
setInterval(() => refresh({ silent: true }), 5000);
