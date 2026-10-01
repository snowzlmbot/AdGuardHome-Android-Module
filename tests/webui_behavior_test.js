'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const script = fs.readFileSync(path.join(__dirname, '../module/webroot/app.js'), 'utf8');
const nodes = new Map();
function element(id) {
  if (!nodes.has(id)) nodes.set(id, {id, dataset:{}, value:'', textContent:'', disabled:false, hidden:false,
    classList:{toggle(){}, add(){}, remove(){}}, setAttribute(){}, addEventListener(name, fn){this[name]=fn;}});
  return nodes.get(id);
}
const vpn = element('vpn'); vpn.dataset.policy = 'bypass_vpn_traffic';
const commands=[];
let state={language:'zh', status:'degraded', core:'ready', network:'ready', firewall:'bypassed',
  vpn:'true', vpn_passthrough:'true', firewall_reason:'vpn_passthrough',
  file_enabled:'false', proxy_enabled:'false', file_rules_state:'ready', web_url:'http://127.0.0.1:3000'};
const window={ksu:{exec(command, _, callback){
  commands.push(command);
  if (command.includes('set-policy bypass_vpn_traffic')) {
    const enabled=command.endsWith('true');
    state={...state, vpn_passthrough:String(enabled), bypass_vpn_traffic:String(enabled),
      firewall:enabled?'bypassed':'ready', firewall_reason:enabled?'vpn_passthrough':'ready'};
    window[callback](0, 'policy=bypass_vpn_traffic='+enabled, '');
  } else window[callback](0,Object.entries(state).map(([k,v])=>k+'='+v).join('\n'),'');
}}};
const context=vm.createContext({window, document:{getElementById:element, documentElement:{},body:element('body'),
  querySelectorAll(selector){return selector==='.policy-toggle'?[vpn]:selector==='button'?[vpn]:[];}},
  localStorage:{getItem(){return 'zh';},setItem(){}},navigator:{language:'zh'},console,
  setTimeout(fn){queueMicrotask(fn);return 1;},clearTimeout(){},setInterval(){}});
(async()=>{
  vm.runInContext(script,context);
  await vm.runInContext('refresh()',context);
  assert.equal(vpn.dataset.enabled,'true','enabled VPN must render enabled');
  assert.ok(!element('firewall').textContent.startsWith('status.'),'bypass status must be localized');
  await vpn.click();
  assert.ok(commands.some(x=>x.endsWith('set-policy bypass_vpn_traffic false')),'click must DISABLE VPN bypass');
  assert.equal(vpn.dataset.enabled,'false','persisted disabled state must read back');
  assert.equal(element('firewall').textContent,'正常','firewall must render ready after disabling bypass');
  await vpn.click();
  assert.equal(vpn.dataset.enabled,'true','second click can re-enable bypass');
  state={...state, file_rules_state:'failed',file_rules_reason:'checksum_download'};
  await vm.runInContext('refresh()',context);
  assert.ok(element('fileRulesMeta').textContent.includes('checksum_download'),'show rule download failure reason');
  console.log('WebUI behavior passed: render, disable/read-back/re-enable VPN, localized bypass, rule failure reason');
})().catch(error=>{console.error(error);process.exitCode=1;});
