/**
 * 枢语造词引擎 — JS版 (lexicon.js)
 * © 阿权/路飞
 * 5维乘法语义空间：核×映×态×标×相 = 76.7亿（核1040×映180×态80×标64×相8）
 * 与 shuyu_engine.py 同构，供 nexuslang.js 解释器调用
 *
 * v4.1（2026-09）新能力（两侧同构，tests/engine.test.mjs 跨实现用例看住）：
 *   encodeHan  汉译（纯中文）→ 编号，枢语从"单向产出"变成"双向可寻址"
 *   search     语义关键词 → 命中的词根（5 轴）
 *   compose    按义造词：每轴给 下标/拉丁根/汉译/语义关键词 任一种 → 唯一编号
 *   decode     输出增加 根 / 坐标{c,m,s,k,p}，与 Python 字段对等
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
  // —— v4 扩充：32 个新核心语义族（追加式，老编号全保留，容量 29.5亿→76.7亿）——
  ["Aur","曜","光曜·显照·觉明","显照"],["Umb","翳","阴翳·遮蔽·潜行","阴翳"],
  ["Onr","梦","梦域·潜识·异境","梦域"],["Tid","潮","潮汐·涨落·周律","潮汐"],
  ["Cry","晶","结晶·凝序·折光","结晶"],["Aby","渊","深渊·未知·引坠","深渊"],
  ["Pyr","焰","焰核·燃驱·转化","焰核"],["Neb","雾","雾散·弥漫·混沌","雾散"],
  ["Vin","藤","藤蔓·缠生·延展","藤蔓"],["Oss","骸","骸骨·残构·记痕","骸骨"],
  ["Pul","脉","脉动·节律·活流","脉动"],["Vor","噬","吞噬·消解·并吞","吞噬"],
  ["Blo","绽","绽放·涌现·盛发","绽放"],["Ech","回","回响·余韵·共振","回响"],
  ["Fro","霜","霜封·凝寂·冷守","霜封"],["Emb","烬","余烬·残温·将熄","余烬"],
  ["Tho","棘","棘刺·防御·锋守","棘刺"],["Vel","帷","帷幔·掩隔·仪境","帷幔"],
  ["Dri","漂","漂流·无系·随势","漂流"],["Rad","根","根系·扎固·汲养","根系"],
  ["Spk","芒","星芒·点爆·迸发","星芒"],["Hol","空","空腔·虚位·容纳","空腔"],
  ["Fat","命","命网·因缘·定数","命网"],["Mir","镜","镜面·映照·对称","镜面"],
  ["Ash","灰","灰烬·终寂·归尘","灰烬"],["See","种","种因·起势·孕发","种因"],
  ["Sto","暴","风暴·激变·裹挟","风暴"],["Sil","丝","丝缕·细连·牵系","丝缕"],
  ["Run","符","符文·封印·载义","符文"],["Aeo","劫","劫纪·纪元·轮替","劫纪"],
  ["Lux","烛","烛照·微明·守夜","烛照"],["Gla","冰","冰川·缓移·亘古","冰川"],
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

const CORES = expand(CORE_BASE, LAT_T, HAN_T);   // 1040 (52族×20阶)
const MANIS = expand(MANI_BASE, LAT_A, HAN_A);   // 180
const STATS = expand(STAT_BASE, LAT_F, HAN_F);   // 80
const SCALS = expand(SCAL_BASE, LAT_S, HAN_S);   // 64
const PHASES = PHASE_BASE;                        // 8

const NC=CORES.length, NM=MANIS.length, NS=STATS.length, NK=SCALS.length, NP=PHASES.length;
export const CAPACITY = NC*NM*NS*NK*NP;          // 7,667,712,000（核1040×映180×态80×标64×相8，v4 追加 32 族后）
export const AXES = Object.freeze({ 核:NC, 映:NM, 态:NS, 标:NK, 相:NP });

// 反向索引：拉丁词形 → 轴内下标（把 encode 从 O(轴长) 线性扫描降到 O(1)）
const CORE_IDX = new Map(CORES.map((x,i)=>[x[0],i]));
const MANI_IDX = new Map(MANIS.map((x,i)=>[x[0],i]));
const STAT_IDX = new Map(STATS.map((x,i)=>[x[0],i]));
const SCAL_IDX = new Map(SCALS.map((x,i)=>[x[0],i]));
const PHASE_IDX = new Map(PHASES.map((x,i)=>[x[0],i]));
// 汉译反向索引：汉 → 轴内下标（encodeHan 用）
const AXIS_LIST = [CORES, MANIS, STATS, SCALS, PHASES];
const LAT_IDX = [CORE_IDX, MANI_IDX, STAT_IDX, SCAL_IDX, PHASE_IDX];
const HAN_IDX = AXIS_LIST.map(ax => new Map(ax.map((x,i)=>[x[1],i])));
const AXIS_NAMES = ['核','映','态','标','相'];
const BASES = [CORE_BASE, MANI_BASE, STAT_BASE, SCAL_BASE, PHASE_BASE];
const TONE_LENS = [LAT_T.length, LAT_A.length, LAT_F.length, LAT_S.length, 1];

const idOf = (c,m,s,k,p) => ((((c*NM)+m)*NS+s)*NK+k)*NP+p;

// ══════ 编号 → 词（O(1) 寻址）══════
export function decode(n){
  // 必须先挡非整数：NaN/小数/undefined 过不了下面的区间比较（与 NaN 比大小恒为 false），
  // 会一路穿到 CORES[c] 取到 undefined，抛出看不懂的 TypeError。
  if(!Number.isInteger(n)) throw new TypeError("编号必须是整数");
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
  return { id:n, 词:word, 汉:han, 层:C[3], 义:sem,
           根:[C[0],M[0],S[0],K[0]||"∅",P[0]],
           坐标:{c,m,s,k,p} };
}

// ══════ 词 → 编号（O(1) 反向寻址，非法词返回 -1）══════
// 单射铁律：encode 必须是 decode 的严格逆。凡 decode 产不出的写法一律判非法，
// 否则畸形词会被映射到一个合法编号，跨仓语义就此错位。
export function encode(word){
  try{
    // 用最后一个「·」切相位：词形里核-映-态-标段不含「·」，多写一个「·」属畸形，
    // 切完前段会带上残留的「·」而匹配不到轴，自然被判 -1（与 Python 的 rsplit 同规则）。
    const sep = word.lastIndexOf("·");
    if(sep < 0) return -1;
    const head = word.slice(0, sep), ph = word.slice(sep+1);
    const parts = head.split("-");
    if(parts.length < 3 || parts.length > 4) return -1;
    const ci = CORE_IDX.get(parts[0]) ?? -1;
    const mi = MANI_IDX.get(parts[1]) ?? -1;
    const si = STAT_IDX.get(parts[2]) ?? -1;
    const ki = parts.length > 3 ? (SCAL_IDX.get(parts[3]) ?? -1) : 0;
    const pi = PHASE_IDX.get(ph) ?? -1;
    if([ci,mi,si,ki,pi].some(i=>i<0)) return -1;
    // 空标轴只能用 3 段词形表达；写成 "核-映-态-·相" 这种显式空标段属畸形，
    // decode 永远产不出它，必须拒绝（否则它会和 3 段词形撞同一个编号）。
    if(parts.length > 3 && ki === 0) return -1;
    return idOf(ci,mi,si,ki,pi);
  }catch{ return -1; }
}

// ══════ 汉译 → 编号（纯中文反向寻址，解不出/解不唯一返回 -1）══════
// 汉译 = 核汉(1~2字) + 映汉(1~2字) + 态汉(1~2字) + 标汉(0~3字) + 相汉(1字)。
// 各轴后缀字（阶/相/频/标位）与下一轴首字零交集，所以汉译唯一可解码（tests 有结构引理守卫）。
// 实现上不依赖这个引理：回溯枚举全部切法，只有恰好一种切法才返回编号，与 Python encode_han 同规则。
export function encodeHan(han){
  if(typeof han !== 'string' || han.length < 4) return -1;
  const chars = Array.from(han);            // 按码点切，不按 UTF-16 码元
  const pi = HAN_IDX[4].get(chars[chars.length-1]);
  if(pi === undefined) return -1;
  const body = chars.slice(0,-1);
  const L = body.length;
  const seg = (a,b) => body.slice(a,b).join('');
  let found = -1, count = 0;
  for(const lc of [1,2]){
    if(lc > L) continue;
    const ci = HAN_IDX[0].get(seg(0,lc)); if(ci === undefined) continue;
    for(const lm of [1,2]){
      if(lc+lm > L) continue;
      const mi = HAN_IDX[1].get(seg(lc,lc+lm)); if(mi === undefined) continue;
      for(const ls of [1,2]){
        if(lc+lm+ls > L) continue;
        const si = HAN_IDX[2].get(seg(lc+lm,lc+lm+ls)); if(si === undefined) continue;
        const ki = HAN_IDX[3].get(seg(lc+lm+ls,L)); if(ki === undefined) continue;
        if(++count > 1) return -1;
        found = idOf(ci,mi,si,ki,pi);
      }
    }
  }
  return count === 1 ? found : -1;
}

// ══════ 语义检索：关键词 → 命中的词根（5 轴基表级，不展开阶）══════
// 每项 {轴,下标,拉丁,汉,义}，下标是**展开后**轴内下标（基表下标×阶数，即 0 阶），可直接喂给 compose / coinFromCoord。
export function search(keyword, axis){
  if(typeof keyword !== 'string' || !keyword.trim()) return [];
  const kw = keyword.trim(), kwl = kw.toLowerCase();
  const out = [];
  for(let ai=0; ai<5; ai++){
    const name = AXIS_NAMES[ai];
    if(axis && axis !== name) continue;
    const base = BASES[ai], tl = TONE_LENS[ai];
    for(let bi=0; bi<base.length; bi++){
      const [lat, han, sem] = base[bi];
      if(!lat && !han) continue;             // 标轴首项是空阶，没有可检索内容
      if(kwl === lat.toLowerCase() || (han && han.includes(kw)) || (sem && sem.includes(kw)) ||
         (lat && kwl.length >= 2 && lat.toLowerCase().includes(kwl))){
        out.push({ 轴:name, 下标:bi*tl, 拉丁:lat, 汉:han, 义:sem });
      }
    }
  }
  return out;
}

// 把一轴的用户输入解析成展开后下标：整数下标 / 拉丁根 / 汉译 / 语义关键词（基表首命中，0 阶）
function resolveAxis(ai, val){
  if(val === undefined || val === null || val === '') return 0;
  const n = AXIS_LIST[ai].length, name = AXIS_NAMES[ai];
  if(typeof val === 'boolean') throw new RangeError(`${name}轴不接受布尔值`);
  if(typeof val === 'number'){
    if(!Number.isInteger(val) || val < 0 || val >= n) throw new RangeError(`${name}轴下标越界 0..${n-1}: ${val}`);
    return val;
  }
  if(typeof val !== 'string') throw new RangeError(`${name}轴入参类型非法`);
  const v = val.trim();
  if(/^\d+$/.test(v)) return resolveAxis(ai, Number(v));
  let i = LAT_IDX[ai].get(v); if(i !== undefined) return i;
  i = HAN_IDX[ai].get(v); if(i !== undefined) return i;
  const hits = search(v, name);
  if(hits.length) return hits[0].下标;
  throw new RangeError(`${name}轴找不到「${val}」`);
}

// ══════ 按义造词：{核,映,态,标,相}（也接受 c,m,s,k,p 键）→ 唯一编号，确定性 ══════
// 解析失败抛 RangeError（不静默落到别的词上——按义造词不许造错词）。
export function compose(spec){
  if(!spec || typeof spec !== 'object') throw new RangeError('compose 需要对象');
  const alias = { c:'核', m:'映', s:'态', k:'标', p:'相' };
  const norm = {};
  for(const key of Object.keys(spec)){
    const k = alias[key] ?? key;
    if(!AXIS_NAMES.includes(k)) throw new RangeError(`未知轴「${key}」`);
    norm[k] = spec[key];
  }
  const idx = AXIS_NAMES.map((name, ai) => resolveAxis(ai, norm[name]));
  return decode(idOf(...idx));
}

// ══════ 解释器接口：按意图取词 ══════
// 解释器 nexuslang.js 需要 LEXICON 和 matchWord
// LEXICON：核心情感/状态映射表（小而精，常驻）
export const LEXICON = {
  // feel 层：情绪词 → 强度+本能（纯中文；matchWord 长词优先，"心疼"先于"疼"）
  feel: {
    // —— 原始 12 个体感词（顺序与取值冻结，历史行为不变）——
    "暖":{intensity:0.5,instinct:"靠近"}, "烫":{intensity:0.8,instinct:"失控"},
    "甜":{intensity:0.6,instinct:"黏"}, "软":{intensity:0.5,instinct:"放松"},
    "冷":{intensity:0.4,instinct:"收"}, "空":{intensity:0.3,instinct:"等待"},
    "酸":{intensity:0.5,instinct:"占有"}, "紧":{intensity:0.6,instinct:"加速"},
    "痒":{intensity:0.5,instinct:"想碰"}, "刺":{intensity:0.7,instinct:"防御"},
    "平":{intensity:0.3,instinct:"观察"}, "湿":{intensity:0.8,instinct:"张开"},
    // —— v4.1 扩充：单字体感词（只挑情绪指向明确的字，避免"热/亮/松"这类日常字误触）——
    "怕":{intensity:0.7,instinct:"缩"},   "慌":{intensity:0.7,instinct:"乱"},
    "闷":{intensity:0.4,instinct:"憋"},   "涩":{intensity:0.4,instinct:"别扭"},
    "麻":{intensity:0.5,instinct:"僵"},   "疼":{intensity:0.7,instinct:"护"},
    "痛":{intensity:0.8,instinct:"哭"},   "怒":{intensity:0.8,instinct:"炸"},
    "羞":{intensity:0.6,instinct:"躲"},   "倦":{intensity:0.3,instinct:"歇"},
    "醉":{intensity:0.7,instinct:"飘"},   "悔":{intensity:0.5,instinct:"回头"},
    "怨":{intensity:0.5,instinct:"别过脸"}, "颤":{intensity:0.7,instinct:"抖"},
    "燃":{intensity:0.8,instinct:"冲"},   "苦":{intensity:0.5,instinct:"忍"},
    "胀":{intensity:0.6,instinct:"满"},   "脆":{intensity:0.6,instinct:"碎"},
    // —— v4.1 扩充：双字情绪词（长词优先命中，语义更准）——
    "心疼":{intensity:0.7,instinct:"抱"},   "心动":{intensity:0.7,instinct:"靠近"},
    "心安":{intensity:0.4,instinct:"放松"}, "心慌":{intensity:0.7,instinct:"乱"},
    "想哭":{intensity:0.7,instinct:"哭"},   "想你":{intensity:0.7,instinct:"黏"},
    "想他":{intensity:0.6,instinct:"黏"},   "委屈":{intensity:0.6,instinct:"撇嘴"},
    "吃醋":{intensity:0.6,instinct:"占有"}, "嫉妒":{intensity:0.6,instinct:"占有"},
    "失落":{intensity:0.4,instinct:"垂"},   "孤单":{intensity:0.4,instinct:"等待"},
    "安心":{intensity:0.4,instinct:"放松"}, "期待":{intensity:0.6,instinct:"望"},
    "害怕":{intensity:0.7,instinct:"缩"},   "紧张":{intensity:0.6,instinct:"加速"},
    "开心":{intensity:0.6,instinct:"笑"},   "难过":{intensity:0.6,instinct:"哭"},
    "生气":{intensity:0.7,instinct:"炸"},   "愤怒":{intensity:0.8,instinct:"炸"},
    "尴尬":{intensity:0.5,instinct:"躲"},   "满足":{intensity:0.6,instinct:"黏"},
    "疲惫":{intensity:0.3,instinct:"歇"},   "兴奋":{intensity:0.8,instinct:"冲"},
    "温柔":{intensity:0.5,instinct:"软"},   "踏实":{intensity:0.4,instinct:"放松"},
    "不安":{intensity:0.6,instinct:"加速"}, "厌烦":{intensity:0.5,instinct:"收"},
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
// feel 表按「长词优先、同长按表内顺序」排好的键列表；表被 loadCapabilities 增补后失效重建
let _FEEL_KEYS = null, _FEEL_SIZE = -1;
function feelKeys(){
  const n = Object.keys(LEXICON.feel).length;
  if(!_FEEL_KEYS || _FEEL_SIZE !== n){
    _FEEL_KEYS = Object.keys(LEXICON.feel).map((w,i)=>[w,i]).sort((a,b)=>(b[0].length-a[0].length)||(a[1]-b[1])).map(x=>x[0]);
    _FEEL_SIZE = n;
  }
  return _FEEL_KEYS;
}

export function matchWord(text, layer){
  if(!text) return null;
  if(layer==="feel"){
    // 先精确情感词：长词优先（"心疼"不能被"疼"抢走），同长按表内顺序（历史行为不变）
    for(const word of feelKeys()){
      if(text.includes(word)) return { word, ...LEXICON.feel[word] };
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
    // word_ids 是可选字段（有的词包只带 vocab），缺了只是查不到编号，不该整个匹配崩掉
    const ids = (LEXICON.caps && LEXICON.caps.word_ids) || null;
    for(const it of _CAP_FLAT){
      if(text.includes(it.word)){
        return { word:it.word, layer:it.layer, cat:it.cat,
                 id:(ids ? (ids[it.word] ?? null) : null) };
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
  return decode(idOf(c,m,s,k,p));
}

// ══════ 从坐标造词：把 5 维坐标映射成真实枢语词（O(1) 可寻址）══════
function _clampAxis(v, max) { v = Math.floor(v || 0); return v < 0 ? 0 : (v >= max ? max - 1 : v); }
export function coinFromCoord(coord) {
  const c = _clampAxis(coord.c, NC), m = _clampAxis(coord.m, NM), s = _clampAxis(coord.s, NS),
        k = _clampAxis(coord.k, NK), p = _clampAxis(coord.p, NP);
  return decode(idOf(c, m, s, k, p));
}

// ══════ 确定性种子造词（无 Math.random，可复现的自主造词）══════
export function autoCoin(seed) {
  let h = 2166136261 >>> 0;
  const str = String(seed);
  for (let i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 16777619) >>> 0; }
  h ^= h << 13; h ^= h >>> 17; h ^= h << 5; h >>>= 0;
  return decode(h % CAPACITY);
}

// ══════ 按状态自主造词：心情/情绪决定核心层 ══════
export function coinFromState(soul, seed) {
  const mood = soul && soul.心绪 != null ? soul.心绪 : 0.5;
  const miss = soul && soul.miss_you != null ? soul.miss_you : 0;
  let layer;
  if (miss > 0.7) layer = '映';
  else if (mood > 0.65) layer = '情感';
  else if (mood < 0.35) layer = '熵';
  else layer = '枢';
  if (seed != null) { const w = autoCoin(String(seed) + '|' + layer); return { ...w, 层意图: layer }; }
  return { ...coinWord(layer), 层意图: layer };
}

export default { CAPACITY, AXES, decode, encode, encodeHan, search, compose, LEXICON, matchWord, coinWord, coinFromCoord, autoCoin, coinFromState, loadCapabilities };
