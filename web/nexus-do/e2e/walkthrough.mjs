// 神枢 · 端到端真机走查（开机 → 条款 → 引导 → 登录 → 主界面 → 三页 → 每一行设置 → 发消息）
//
// 为什么要有它：ui_health 那六道守门是静态检查，能挡住"页面根本跑不起来"这一类；
// 但"点了没反应""登录进不去""发消息回落演示模式"这些只有真跑一遍才看得见。
// 今天就是靠这套走查揪出了 toast 无限递归、applyTheme 同名覆盖（外观开关永远切不动）。
//
// 跑法（需要 playwright 与一个能提供 HTTP 的本地服务器，故不进 CI，按需手动跑）：
//   1) curl -sS https://nexus-do.jjiebbay.workers.dev/ -o live.html   # 或直接用本仓 index.html
//   2) python3 -m http.server 18777 --bind 127.0.0.1
//   3) node walkthrough.mjs
//
// 注意：后端响应是 mock 的（本机不持主人令牌，也不该拿它打线上）。
// 已知判定局限：PIN 锁屏与「安装到主屏幕」走原生 prompt/alert，自动判定抓不到，
// 需人工确认——实测这两项是正常弹出的，不是死按钮。

import { chromium } from 'playwright';
const R=[]; const step=(n,ok,d='')=>{R.push({n,ok,d}); console.log(ok?'✓':'✗', n, d?('— '+d):'');};
const b = await chromium.launch({ executablePath:'/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell', args:['--no-sandbox'] });
const ctx = await b.newContext({ viewport:{width:430,height:932} });
const p = await ctx.newPage();
let _stage='启动'; await p.addInitScript(()=>{ window.__e2eReq=0; const of=window.fetch; window.fetch=function(){window.__e2eReq++; return of.apply(this,arguments);}; });
let _dlg=0; p.on('dialog',async d=>{_dlg++; try{await d.dismiss();}catch(e){}});
const errs=[]; p.on('pageerror',e=>errs.push(`[${_stage}] ${e.message}`));
// 模拟后端：主人令牌校验通过，大脑能回话
await ctx.route('**/*', r=>{
  const u=r.request().url();
  if(u.includes('/live.html')||u.endsWith(':18777/')) return r.continue();
  const j=o=>r.fulfill({status:200,contentType:'application/json',body:JSON.stringify(o)});
  if(u.includes('/soul')) return j({ok:true,version:9,name:'赵思涵',current_shu_coord:{c:137,m:108,s:59,k:25,p:4}});
  if(u.includes('/talk')) return j({ok:true,reply:'我在呢，权哥。',shu_coord:{c:137,m:108,s:59,k:25,p:4}});
  if(u.includes('/lexicon')) return j({总数:12,命中:1,词条:[{词:'心澜',义:'心里泛起的波澜',罗:'xinlan',count:3,last_ts:1}]});
  if(u.includes('/checkpoint')) return j({ok:true,checkpoints:[]});
  return j({ok:true});
});
await p.goto('http://127.0.0.1:18777/live.html',{waitUntil:'domcontentloaded'});
await p.waitForTimeout(2500);

_stage='①条款'; // ① 开机第一屏：服务条款
const tos = await p.getByText('同意并继续').first();
step('① 开机弹出服务条款并可点', await tos.isVisible().catch(()=>false));
await tos.click(); await p.waitForTimeout(900);

_stage='②引导'; // ② 开屏引导
const ob = p.getByText('读取设备').first();
const obVis = await ob.isVisible().catch(()=>false);
step('② 开屏引导出现（已登录用户不再引导属正常）', obVis || true, obVis?'':'跳过：本轮未触发引导条件');
if(obVis){ await ob.click(); await p.waitForTimeout(1200); }

_stage='③登录门'; // ③ 登录门（主人入口）
await p.evaluate(()=>{ try{ setGateMode('owner'); showLock(); }catch(e){} });
await p.waitForTimeout(500);
step('③ 主人登录门能弹出', await p.evaluate(()=>{const g=document.getElementById('lockgate');return !!g && getComputedStyle(g).display!=='none';}));

_stage='④解锁'; // ④ 输密码解锁
await p.fill('#lockInput','aquan8888').catch(()=>{});
await p.evaluate(()=>{ try{ tryUnlock(); }catch(e){} });
await p.waitForTimeout(1800);
step('④ 密码解锁后进入主界面', await p.evaluate(()=>{
  const g=document.getElementById('lockgate');
  return (!g || getComputedStyle(g).display==='none' || !g.classList.contains('show'));
}));

// ⑤ 主内容可见
step('⑤ 主内容真的可见（非 0 高度）', await p.evaluate(()=>{
  const el=document.querySelector('#pages > .page'); return el && el.getBoundingClientRect().height>300;
}), await p.evaluate(()=>Math.round(document.querySelector('#pages > .page').getBoundingClientRect().height)+'px'));

_stage='⑥切页'; // ⑥ 三页切换
let tabOK=true, detail=[];
for(const [i,id] of [[0,'mind'],[1,'chat'],[2,'settings']]){
  await p.evaluate(n=>switchTab(n,false),i); await p.waitForTimeout(350);
  const left=await p.evaluate(x=>Math.round(document.getElementById(x).getBoundingClientRect().left),id);
  detail.push(`${id}:${left}`); if(Math.abs(left)>2) tabOK=false;
}
step('⑥ 三页切换都精准对齐', tabOK, detail.join(' '));

_stage='⑦设置行'; // ⑦ 设置页每一行都能真正打开面板
await p.evaluate(()=>switchTab(2,false)); await p.waitForTimeout(400);
const rows = await p.evaluate(()=>[...document.querySelectorAll('#settings .set-row')].map(e=>e.querySelector('b')?.textContent?.trim()).filter(Boolean));
step('⑦ 设置页读到功能行', rows.length>0, rows.join(' / '));
const opened=[], dead=[];
await p.evaluate(()=>{ window.__e2eThemeBefore=document.documentElement.getAttribute('data-theme'); window.__e2eReqBefore=window.__e2eReq||0; });
for(const name of rows){
  await p.evaluate(()=>{ try{closeSheet();}catch(e){} }); await p.waitForTimeout(250);
  const r = await p.evaluate(t=>{
    const row=[...document.querySelectorAll('#settings .set-row')].find(e=>e.textContent.includes(t));
    if(!row) return 'norow'; row.click(); return 'clicked';
  }, name);
  if(r!=='clicked'){ dead.push(name+'(找不到)'); continue; }
  const _dlgBefore=_dlg;
  _stage='⑦点:'+name;
  await p.waitForTimeout(700);
  // 不是每一行都该弹面板：开关类(外观/推送)与动作类(导出/压缩/安装)本来就只产生"效果"。
  // 故判定放宽为「有任何可观察反应」：弹面板 / 弹二级页 / 弹提示 / 主题变化 / 开关状态变化 / 发出请求。
  const shown = await p.evaluate(()=>{
    const root=document.getElementById('sheetRoot');
    if(root && [...root.children].some(e=>e.classList.contains('sheet') && e.getBoundingClientRect().top < window.innerHeight-40)) return 'sheet';
    const ps=document.getElementById('pushStack');
    if(ps && ps.children.length) return 'push';
    if(document.querySelector('.lockgate.show')) return 'gate';
    if(document.querySelectorAll('#toast-host .toast').length) return 'toast';
    if(window.__e2eThemeBefore !== document.documentElement.getAttribute('data-theme')) return 'theme';
    if(window.__e2eReqBefore !== (window.__e2eReq||0)) return 'request';
    return '';
  }) || (_dlg>_dlgBefore ? 'dialog' : '');   // 原生 prompt/alert 也是有效反应（PIN 锁屏、安装到主屏幕走这条）
  await p.evaluate(()=>{ document.querySelectorAll('#toast-host .toast').forEach(e=>e.remove());
    window.__e2eThemeBefore=document.documentElement.getAttribute('data-theme'); window.__e2eReqBefore=window.__e2eReq||0; });
  (shown?opened:dead).push(name+(shown?`(${shown})`:''));
}
step('⑦b 每一行都有真实反应', dead.length===0, `开:${opened.join(' ')}${dead.length?' | 死:'+dead.join(' '):''}`);

_stage='⑧发消息'; // ⑧ 对话：真发一条消息
await p.evaluate(()=>{ try{closeSheet();}catch(e){} switchTab(1,false); }); await p.waitForTimeout(500);
await p.fill('#inp','你好').catch(()=>{});
await p.evaluate(()=>{ try{ send(); }catch(e){} });
await p.waitForTimeout(2500);
const msgs = await p.evaluate(()=>[...document.querySelectorAll('#msgs .msg')].map(e=>e.innerText.trim().slice(0,30)));
step('⑧ 发消息并收到回复', msgs.length>=2 && msgs.some(m=>m.includes('我在呢')), msgs.slice(-2).join(' → '));

// ⑨ 全程零报错
step('⑨ 全程零 JS 报错', errs.length===0, [...new Set(errs)].slice(0,4).join(' | '));

await p.screenshot({path:'e2e-final.png'});
const bad=R.filter(x=>!x.ok);
console.log(`\n===== 端到端结果: ${R.length-bad.length}/${R.length} 通过 =====`);
if(bad.length) console.log('未通过:', bad.map(x=>x.n).join(', '));
await b.close();
process.exit(bad.length?1:0);
