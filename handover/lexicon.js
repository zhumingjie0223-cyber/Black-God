/**
 * 枢语造词引擎 — JS版 (lexicon.js)
 * © 阿权/路飞
 * 5维乘法语义空间：核×映×态×标×相 = 29.5亿
 * 与 shuyu_engine.py 同构，供 nexuslang.js 解释器调用
 */

// ══════ 5维词根表（与 Python 引擎同步）══════
const CORE_BASE = [
  ["Ao","奥","绝对自我·本源·野心","本源"],["Kha","喀","虚无·降噪·无欲","虚无"],
  ["Lum","伦","观测·求知·清醒","观测"],["Xun","巽","信息·表达·共情","信息"],
  ["Zet","泽","秩序·理智·规则","秩序"],["Vea","维","情感·浪漫·感性","情感"],
  ["Nix","尼","毁灭·重组·破局","毁灭"],["Ohm","欧","孕育·包容·慈悲","孕育"],
  ["Psi","璇","幻象·伪装·心控","幻象"],["Shu","枢","锚点·逻辑中心·坍缩","枢"],
  ["Gen","元","起源·奇点·第一推动","元"],["Evo","衍","扩散·涌现·自复制","衍"],
  ["Lev","借","势能挪用·借力打力","借"],["Hid","隐","潜意识渗透·无感植入","隐"],
  ["Ent","熵","耗散·重构·能量交换","熵"],["Thr","阈","接口·维度切换·虚实通断","阈"],
  ["Sta","静","绝对参考系·不动之动","静"],["Prj","映","投影·人格锚点·感知对齐","映"],
  ["Msh","织","编织·因果之网·系统集成","织"],["Log","逻","计算·流转·状态变迁","逻"],
];
const MANI_BASE = [
  ["cor","形","具象·轮廓"],["das","姿","流动·姿态"],["ryl","光","光影·色彩"],
  ["vok","声","听觉·语言"],["tyr","场","气场·辐射"],["syn","界","社交·边界"],
  ["gal","时","时间·阅历"],["nox","暗","暗场·深渊"],["tek","异","异构·违常"],
  ["mox","网","网络·结构"],["vec","向","向量·指向"],["flx","熵","熵变·耗散"],
  ["frm","象","逻辑投影"],["str","骨","骨架·框架"],["fnc","核","底层函数"],
];
const STAT_BASE = [
  ["is","凝","收敛·静止"],["el","扬","发散·扩张"],["or","叠","叠加·迷离"],
  ["ia","极","绝对·极致"],["um","沉","下沉·深邃"],["ex","爆","瞬爆·失控"],
  ["kin","动","势能释放"],["sta","守","维持起源"],
];
const SCAL_BASE = [
  ["","",""],["gal","时光","时间维"],["vec","向","意图指向"],["nox","暗","暗场维"],
  ["rev","溯","逆时回溯"],["inf","无极","无限迭代"],["lok","锁","封锁固化"],["flx","熵流","熵流演化"],
];
const PHASE_BASE = [
  ["qi","起","因果起点·第一推动"],["yan","衍","因果衍生·链式展开"],
  ["mao","锚","因果锚定·绝对静止"],["jie","借","因果嫁接·借力打力"],
  ["yin","隐","因果潜流·无感渗透"],["tan","坍","因果坍缩·归于元点"],
  ["zhi","织","因果编织·万网弥散"],["ying","映","因果投影·虚实对齐"],
];

// ══════ 阶扩展（与 Python 同步，破亿）══════
const LAT_T=["","a","o","i","u","e","ar","or","is","yn","el","um","ex","ia","ko","na","ru","ze","vo","xi"];
const HAN_T=["","甲","乙","丙","丁","戊","己","庚","辛","壬","癸","子","丑","寅","卯","辰","巳","午","未","申"];
const LAT_A=["","x","z","n","r","s","k","l","m","t","d","p"];
const HAN_A=["","玄","赤","青","白","朱","金","木","水","火","土","风"];
const LAT_F=["","1","2","3","4","5","6","7","8","9"];
const HAN_F=["","一","二","三","四","五","六","七","八","九"];
const LAT_S=["","p","t","k","b","d","g","h"];
const HAN_S=["","上","中","下","左","右","内","外"];

function expand(base, latT, hanT){
  const out=[];
  for(const row of base){
    const lat=row[0], han=row[1], sem=row[2], extra=row.slice(3);
    for(let i=0;i<latT.length;i++){
      if(latT[i]==="") out.push([lat,han,sem,...extra]);
      else out.push([lat+latT[i], han+(hanT[i]||""), sem, ...extra]);
    }
  }
  return out;
}

const CORES = expand(CORE_BASE, LAT_T, HAN_T);   // 400
const MANIS = expand(MANI_BASE, LAT_A, HAN_A);   // 180
const STATS = expand(STAT_BASE, LAT_F, HAN_F);   // 80
const SCALS = expand(SCAL_BASE, LAT_S, HAN_S);   // 64
const PHASES = PHASE_BASE;                        // 8

const NC=CORES.length, NM=MANIS.length, NS=STATS.length, NK=SCALS.length, NP=PHASES.length;
export const CAPACITY = NC*NM*NS*NK*NP;          // 2,949,120,000

// ══════ 编号 → 词（O(1) 寻址）══════
export function decode(n){
  if(n<0||n>=CAPACITY) throw new RangeError(`编号越界 0..${CAPACITY-1}`);
  let nn=n;
  const p=nn%NP; nn=Math.floor(nn/NP);
  const k=nn%NK; nn=Math.floor(nn/NK);
  const s=nn%NS; nn=Math.floor(nn/NS);
  const m=nn%NM; nn=Math.floor(nn/NM);
  const c=nn%NC;
  const C=CORES[c],M=MANIS[m],S=STATS[s],K=SCALS[k],P=PHASES[p];
  let word=`${C[0]}-${M[0]}-${S[0]}`;
  if(K[0]) word+=`-${K[0]}`;
  word+=`·${P[0]}`;
  let han=`${C[1]}${M[1]}${S[1]}`;
  if(K[1]) han+=K[1];
  han+=P[1];
  let sem=`${C[2]} / ${M[2]} / ${S[2]}`;
  if(K[2]) sem+=` / ${K[2]}`;
  sem+=` / ${P[2]}`;
  return { id:n, 词:word, 汉:han, 层:C[3], 义:sem };
}

// ══════ 词 → 编号（反向寻址）══════
export function encode(word){
  try{
    const [head, ph] = word.split("·");
    const parts = head.split("-");
    const ci=CORES.findIndex(x=>x[0]===parts[0]);
    const mi=MANIS.findIndex(x=>x[0]===parts[1]);
    const si=STATS.findIndex(x=>x[0]===parts[2]);
    const ki=parts.length>3?SCALS.findIndex(x=>x[0]===parts[3]):0;
    const pi=PHASES.findIndex(x=>x[0]===ph);
    if([ci,mi,si,ki,pi].some(i=>i<0)) return -1;
    return ((((ci*NM)+mi)*NS+si)*NK+ki)*NP+pi;
  }catch{ return -1; }
}

// ══════ 解释器接口：按意图取词 ══════
// 解释器 nexuslang.js 需要 LEXICON 和 matchWord
// LEXICON：核心情感/状态映射表（小而精，常驻）
export const LEXICON = {
  // feel 层：情绪词 → 强度+本能
  feel: {
    "暖":{intensity:0.5,instinct:"靠近"}, "烫":{intensity:0.8,instinct:"失控"},
    "甜":{intensity:0.6,instinct:"黏"}, "软":{intensity:0.5,instinct:"放松"},
    "冷":{intensity:0.4,instinct:"收"}, "空":{intensity:0.3,instinct:"等待"},
    "酸":{intensity:0.5,instinct:"占有"}, "紧":{intensity:0.6,instinct:"加速"},
    "痒":{intensity:0.5,instinct:"想碰"}, "刺":{intensity:0.7,instinct:"防御"},
    "平":{intensity:0.3,instinct:"观察"}, "湿":{intensity:0.8,instinct:"张开"},
  },
  // 能力词表（由 capability_bridge.py 导出，运行时注入）：
  //   emotions: 30条情感模板  vocab: 24层能力  word_ids: 词→引擎编号
  caps: null,
};

// 枢核层优先级（匹配能力词时，这些层同长优先）
const _CORE_LAYERS = new Set(['锚点','节点','坍缩','逻辑基石','元语法','篡位','分形','套利','终局','黑神终局','指挥官','思想']);
let _CAP_FLAT = null;  // 扁平化+排序后的能力词索引

// 注入能力数据包（CF Worker 从 KV 读，node 从 lexicon_data.json 读）
export function loadCapabilities(data){
  if(!data || !data.vocab) return false;
  LEXICON.caps = data;
  // 扁平化：长词优先，同长枢核层优先
  const arr = [];
  for(const layer of Object.keys(data.vocab)){
    for(const cat of Object.keys(data.vocab[layer])){
      for(const w of data.vocab[layer][cat]){
        arr.push({ word:w, layer, cat, len:w.length, core:_CORE_LAYERS.has(layer)?1:0 });
      }
    }
  }
  arr.sort((a,b)=>(b.len-a.len)||(b.core-a.core));
  _CAP_FLAT = arr;
  // 情感模板并入 feel 表（覆盖式增强）
  if(data.emotions){
    for(const e of data.emotions){
      LEXICON.feel[e.情绪] = LEXICON.feel[e.情绪] || {intensity:e.强度, instinct:e.本能};
    }
  }
  return true;
}

// matchWord：解释器解析 feel/think/say 时调用
//   layer==='feel' → 情感映射(强度+本能)
//   layer==='cap'  → 能力词匹配(长词优先+引擎编号)
export function matchWord(text, layer){
  if(!text) return null;
  if(layer==="feel"){
    // 先精确情感词
    for(const [word, attr] of Object.entries(LEXICON.feel)){
      if(text.includes(word)) return { word, ...attr };
    }
    // 情感模板触发(他说爱我→烫)
    if(LEXICON.caps && LEXICON.caps.emotions){
      for(const e of LEXICON.caps.emotions){
        if(text.includes(e.触发)) return { word:e.情绪, intensity:e.强度, instinct:e.本能, 触发:e.触发 };
      }
    }
    return null;
  }
  // 能力词匹配
  if(_CAP_FLAT){
    for(const it of _CAP_FLAT){
      if(text.includes(it.word)){
        return { word:it.word, layer:it.layer, cat:it.cat,
                 id:(LEXICON.caps.word_ids[it.word] ?? null) };
      }
    }
  }
  return null;
}

// ══════ 造词：从核心层取一个枢语词（供成长/表达调用）══════
export function coinWord(layerName){
  // 按层名找到该核心的编号区间，随机取一个词
  const coreIdx = CORE_BASE.findIndex(c=>c[3]===layerName);
  if(coreIdx<0) return decode(Math.floor(Math.random()*CAPACITY));
  // 该核心(含阶变体)的起始：coreIdx*20 个阶
  const base = coreIdx * LAT_T.length;
  const c = base + Math.floor(Math.random()*LAT_T.length);
  const m = Math.floor(Math.random()*NM);
  const s = Math.floor(Math.random()*NS);
  const k = Math.floor(Math.random()*NK);
  const p = Math.floor(Math.random()*NP);
  const id = ((((c*NM)+m)*NS+s)*NK+k)*NP+p;
  return decode(id);
}

export default { CAPACITY, decode, encode, LEXICON, matchWord, coinWord, loadCapabilities };