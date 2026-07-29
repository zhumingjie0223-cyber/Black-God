import { EventBus } from './nexus_event_bus.mjs';
import { WorldGraph } from './nexus_world_graph.mjs';
import { ShuyuBridge } from './nexus_shuyu_bridge.mjs';
import { SelfImprove } from './nexus_self_improve.mjs';
import { ExperienceMemory } from './memory/experience_memory.mjs';
import { CapabilityGrowth } from './capabilities.mjs';
import { ShenshuCore } from './nexus_do.mjs';
let pass=0,fail=0; const ok=(n,c)=>{c?(pass++,console.log('✓',n)):(fail++,console.error('✗',n));};

{ const b=new EventBus(); let n=0; const off=b.on('x',async()=>{n++;throw Error('x')}); const r=await b.emit('x'); ok('事件异步异常被收口',r[0].status==='rejected'); off(); await b.emit('x'); ok('事件可取消',n===1); }
{ let t=1; const g=new WorldGraph({}, {maxEntities:10,maxRelations:10,clock:()=>t++}); g.addEntity({id:'a',confidence:2}); g.addEntity({id:'b'}); g.connect('a','b','causes',.4); g.connect('a','b','causes',.9); ok('世界实体置信度钳制',g.predict('a').confidence===1); ok('世界关系去重更新',g.export().relations.length===1&&g.findCause('b')[0].confidence===.9); const r=new WorldGraph(g.export()); ok('世界快照恢复',r.predict('b')?.id==='b'); }
{ let t=7; const m=new ExperienceMemory([], {clock:()=>t,maxRecords:10}); const a=m.remember({concept:'x'}),b=m.remember({concept:'x'}); ok('经验ID同毫秒唯一',a.id!==b.id); m.reinforce(a.id,.8); const r=new ExperienceMemory(m.export()); ok('经验恢复强化',r.search('x')[0].confidence===1); }
{ let t=9; const s=new ShuyuBridge(null,{clock:()=>t}); const h1=s.hash({b:2,a:1}),h2=s.hash({a:1,b:2}); const a=s.encode('x',{}),b=s.encode('x',{}); ok('枢语hash稳定且在范围',JSON.stringify(h1)===JSON.stringify(h2)&&h1.every(x=>x>=0&&x<=1)); ok('枢语ID不碰撞',a.shu_id!==b.shu_id); }
{ const bus=new EventBus(),mem=new ExperienceMemory(),caps=new CapabilityGrowth(); let applied=0;bus.on('improvement.applied',()=>applied++); const si=new SelfImprove({eventBus:bus,memory:mem,capabilities:caps}); const no=await si.improve(Error('bad'),{result:{score:.5},capability:'talk'}); const yes=await si.improve(Error('bad'),{result:{score:.9},capability:'talk'}); ok('自改进阈值拒绝',!no.applied); ok('自改进验证通过并成长',yes.applied&&applied===1&&caps.get('talk').successes===1); }
{ const T=Object.create(ShenshuCore.prototype); const store=new Map(); T.storage={put:async(k,v)=>store.set(k,v)}; const r=T.recordCognitiveOutcome({text:'输入',reply:'输出',ok:true}); await T.flushCognitiveV2(true); ok('core最小接线不依赖constructor',!!r.experienceId&&store.get('cognitive_v2')?.version===2); }
console.log(`\n${pass} passed, ${fail} failed`); process.exit(fail?1:0);
