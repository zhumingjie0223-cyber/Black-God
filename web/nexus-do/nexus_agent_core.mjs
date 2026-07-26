// ============================================================
// Black God · 逆向移植模块 B1
// AgentStateMachineDO (Replit逆向) + ModelRouter (Replit逆向)
// opus4.8 生成 → opus4.8 审核修复5个bug → 2026-07-26
// ============================================================

const PHASE = { IDLE:'IDLE', DISPATCHING:'DISPATCHING', WAITING_FOR_INPUT:'WAITING_FOR_INPUT' };
const LEASE_TTL_MS = 30_000;
const ALARM_INTERVAL_MS = 5_000;

export class AgentStateMachineDO {
  constructor(state,env){this.state=state;this.env=env;this.storage=state.storage;this.ALARM_INTERVAL=ALARM_INTERVAL_MS}
  async _getPhase(){return(await this.storage.get('phase'))||PHASE.IDLE}
  async _setPhase(p){await this.storage.put('phase',p)}
  async _getQueue(){return(await this.storage.get('queue'))||[]}
  async _setQueue(q){await this.storage.put('queue',q)}
  async _getLease(){return(await this.storage.get('lease'))||null}
  async _setLease(l){if(l===null)await this.storage.delete('lease');else await this.storage.put('lease',l)}
  _newToken(){return crypto.randomUUID()}
  async _ensureAlarm(){const e=await this.storage.getAlarm();if(e===null)await this.storage.setAlarm(Date.now()+ALARM_INTERVAL_MS)}
  _json(obj,status=200){return new Response(JSON.stringify(obj),{status,headers:{'content-type':'application/json;charset=utf-8'}})}

  async fetch(request){
    const url=new URL(request.url);
    const method=request.method.toUpperCase();
    const path=url.pathname;
    try{
      if(method==='POST'&&path.endsWith('/enqueue'))return await this.handleEnqueue(request);
      if(method==='POST'&&path.endsWith('/dispatch'))return await this.handleDispatch();
      if(method==='POST'&&path.endsWith('/complete'))return await this.handleComplete(request);
      if(method==='GET'&&path.endsWith('/state'))return await this.handleState();
      return this._json({error:'not_found'},404);
    }catch(err){return this._json({error:'internal_error',message:String(err?.message||err)},500)}
  }

  async handleEnqueue(request){
    const body=await request.json().catch(()=>({}));
    if(body.message===undefined)return this._json({error:'missing_message'},400);
    const queue=await this._getQueue();
    const item={id:crypto.randomUUID(),message:body.message,task:body.task||null,enqueuedAt:Date.now()};
    queue.push(item);
    await this._setQueue(queue);
    await this._ensureAlarm();
    return this._json({ok:true,id:item.id,queueLength:queue.length});
  }

  async handleDispatch(){
    const lease=await this._getLease();
    if(lease&&lease.expiry>Date.now())return this._json({error:'lease_held',lease},409);
    const queue=await this._getQueue();
    if(queue.length===0){await this._setPhase(PHASE.IDLE);return this._json({error:'queue_empty',phase:PHASE.IDLE},404)}
    const item=queue.shift();
    await this._setQueue(queue);
    const newLease={token:this._newToken(),itemId:item.id,task:item.task,acquiredAt:Date.now(),expiry:Date.now()+LEASE_TTL_MS};
    await this._setLease(newLease);
    await this._setPhase(PHASE.DISPATCHING);
    await this._ensureAlarm();
    return this._json({ok:true,phase:PHASE.DISPATCHING,lease:newLease,item,remaining:queue.length});
  }

  async handleComplete(request){
    const body=await request.json().catch(()=>({}));
    const lease=await this._getLease();
    if(!lease)return this._json({error:'no_active_lease'},409);
    if(body.token!==lease.token)return this._json({error:'invalid_lease_token'},403);
    if(lease.expiry<=Date.now()){await this._setLease(null);await this._setPhase(PHASE.IDLE);return this._json({error:'lease_expired'},410)}
    await this._setLease(null);
    const queue=await this._getQueue();
    const phase=body.waitForInput===true?PHASE.WAITING_FOR_INPUT:PHASE.IDLE;
    await this._setPhase(phase);
    return this._json({ok:true,phase,completedItemId:lease.itemId,queueLength:queue.length});
  }

  async handleState(){
    const[phase,queue,lease]=await Promise.all([this._getPhase(),this._getQueue(),this._getLease()]);
    return this._json({phase,queueLength:queue.length,queue,lease,leaseValid:lease?lease.expiry>Date.now():false,now:Date.now()});
  }

  async alarm(){
    const lease=await this._getLease();
    const now=Date.now();
    // Bug A fixed: 过期任务放回queue，避免丢失
    if(lease&&lease.expiry<=now){
      const queue=await this._getQueue();
      if(lease.task!==undefined&&lease.task!==null){
        queue.unshift({id:lease.itemId,task:lease.task,message:{__requeued:true,reason:'lease_timeout'},enqueuedAt:now});
        await this._setQueue(queue);
      }
      await this._setLease(null);
      await this._setPhase(PHASE.IDLE);
    }
    const[queue,curLease]=await Promise.all([this._getQueue(),this._getLease()]);
    if(queue.length>0||curLease){
      // Bug B fixed: 保证不设置到过去时间
      const rawNext=curLease?Math.min(curLease.expiry,now+this.ALARM_INTERVAL):now+this.ALARM_INTERVAL;
      await this.state.storage.setAlarm(Math.max(rawNext,now+1000));
    }else{await this._setPhase(PHASE.IDLE)}
  }
}

// ---------------------------------------------------------------------------
// ModelRouter — Replit多模型分档路由逆向
// ---------------------------------------------------------------------------
export const TIER=Object.freeze({LITE:'LITE',ECONOMY:'ECONOMY',POWER:'POWER',POWER_TURBO:'POWER_TURBO'});
export const EffortLevel=Object.freeze({MINIMAL:0,LOW:1,MEDIUM:2,HIGH:3,MAX:4});
const TIER_ORDER=[TIER.POWER_TURBO,TIER.POWER,TIER.ECONOMY,TIER.LITE];
const DEFAULT_TIER_CONFIG=Object.freeze({
  [TIER.LITE]:        {minScore:0, maxTokens:4096,   costWeight:1, models:['qwen3.6-flash'],  effortCap:1},
  [TIER.ECONOMY]:     {minScore:25,maxTokens:16384,  costWeight:3, models:['qwen3.7-max'],    effortCap:2},
  [TIER.POWER]:       {minScore:55,maxTokens:65536,  costWeight:8, models:['claude-opus-4-8'],effortCap:3},
  [TIER.POWER_TURBO]: {minScore:80,maxTokens:200000, costWeight:20,models:['claude-opus-5'],  effortCap:4},
});

export class ModelRouter{
  constructor(opts={}){
    this.config={...DEFAULT_TIER_CONFIG,...(opts.tierConfig||{})};
    this.availability=opts.availability||(()=>true);
    this.budgetLimit=opts.budgetLimit??Infinity;
    this.spent=0;
  }
  _score(req){
    let s=0;
    s+=Math.min(30,(req.estimatedTokens??0)/4000*30);
    s+=(req.complexity??0)*30;
    s+=((req.effort??EffortLevel.MEDIUM)/EffortLevel.MAX)*25;
    if(req.needsTools)s+=8;
    if(req.needsReasoning)s+=12;
    if(req.priority==='high')s+=10;
    return Math.max(0,Math.min(100,s));
  }
  _tierForScore(score){
    for(const tier of TIER_ORDER){if(score>=this.config[tier].minScore)return tier}
    return TIER.LITE;
  }
  _pickModel(tier){return this.config[tier].models.find(m=>this.availability(m))||null}
  route(req={}){
    const score=this._score(req);
    const tier=this._tierForScore(score);
    // Bug C fixed: indexOf返回-1时兜底为0
    const startIdx=Math.max(0,TIER_ORDER.indexOf(tier));
    for(let i=startIdx;i<TIER_ORDER.length;i++){
      const candidate=TIER_ORDER[i];
      const cfg=this.config[candidate];
      if(!cfg)continue;
      if(this.spent+cfg.costWeight>this.budgetLimit)continue;
      const model=this._pickModel(candidate);
      if(!model)continue;
      const effort=Math.min(req.effort??EffortLevel.MEDIUM,cfg.effortCap);
      this.spent+=cfg.costWeight;
      return{tier:candidate,model,score,effort,maxTokens:cfg.maxTokens,degraded:candidate!==tier};
    }
    // Bug D+E fixed: 兜底检查budgetLimit和空引用
    const liteCfg=this.config[TIER.LITE];
    const liteModel=(liteCfg&&Array.isArray(liteCfg.models)&&liteCfg.models.length>0)?liteCfg.models[0]:null;
    if(liteCfg&&this.spent+liteCfg.costWeight<=this.budgetLimit)this.spent+=liteCfg.costWeight;
    return{tier:TIER.LITE,model:liteModel,score,effort:EffortLevel.MINIMAL,maxTokens:liteCfg?.maxTokens??4096,degraded:true,fallback:true};
  }
  resetBudget(){this.spent=0}
}
