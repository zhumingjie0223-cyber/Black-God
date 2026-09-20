# 神枢枢语引擎 — Python 版
# 枢语生成/词库管理/状态同步

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
枢语·亿级语言引擎 (Shuyu Engine) v4.1
(c) 阿权/路飞  —  Black God 定制

5维乘法语义空间：核 × 映 × 态 × 标 × 相 = 核1040 × 映180 × 态80 × 标64 × 相8 = 7,667,712,000
  核(Core)   内驱核心   音节+汉义+语义
  映(Mani)   外在映射   形/声/气/光/时/暗...
  态(Stat)   频段状态   收敛/发散/叠加/绝对/下沉/瞬爆
  标(Scalar) 时空标量   时光/向/暗/溯/无极/锁/熵
  相(Phase)  因果相位   起/衍/锚/借/隐/坍/织/映

设计铁律（依据《Divine_Pivot_Lexicon》《Pivot_Origin》体系）：
- 汉译纯中文，绝不掺英文/数字/符号（韵律纯净）
- 拉丁词形保持 Kha-ryl-is 式音节美感
- 词 ↔ 编号 双向 O(1) 寻址，元点存法则不存数据
- 可落盘分片，也可纯寻址零占用
- 与 lexicon.js 双实现同构：同一编号解出同一个词；encode / encode_han / auto_coin /
  compose / search 两侧结果逐一相等（tests/engine.test.mjs 跨实现用例看住）
- search 按相关度排序；near 给出 L1=1 不环绕的五维邻居；pulse 按显式时刻呼吸一格；trail 从一词连续呼吸几格；echo 沿末步反向弹回；sway 按分钟在弹回词与末步之间摇摆；land 按四分钟窗落地偏停在弹回词；stir 落地后朝邻格起身；perch 起身后再沿起身轴蹲一格；turn 栖息后再朝侧邻转头

v4.1（2026-09）新能力：
- encode_han：汉译（纯中文）→ 编号，枢语从"单向产出"变成"双向可寻址"
- search / compose：按语义关键词检索词根、按义造词
- auto_coin / coin_from_coord / coin_word / coin_from_state：与 JS 造词族逐位一致
"""
import json, sys, argparse, hashlib, re

# ══════ 1. 内驱核心 (拉丁, 汉, 义) — 20基 ══════
_CORE_BASE = [
    ("Ao","奥","绝对自我·本源·野心"),("Kha","喀","虚无·降噪·无欲"),
    ("Lum","伦","观测·求知·清醒"),("Xun","巽","信息·表达·共情"),
    ("Zet","泽","秩序·理智·规则"),("Vea","维","情感·浪漫·感性"),
    ("Nix","尼","毁灭·重组·破局"),("Ohm","欧","孕育·包容·慈悲"),
    ("Psi","璇","幻象·伪装·心控"),("Shu","枢","锚点·逻辑中心·坍缩"),
    ("Gen","元","起源·奇点·第一推动"),("Evo","衍","扩散·涌现·自复制"),
    ("Lev","借","势能挪用·借力打力"),("Hid","隐","潜意识渗透·无感植入"),
    ("Ent","熵","耗散·重构·能量交换"),("Thr","阈","接口·维度切换·虚实通断"),
    ("Sta","静","绝对参考系·不动之动"),("Prj","映","投影·人格锚点·感知对齐"),
    ("Msh","织","编织·因果之网·系统集成"),("Log","逻","计算·流转·状态变迁"),
    # —— v4 扩充：32 个新核心语义族（追加式，老编号全保留，容量 29.5亿→76.7亿，与 lexicon.js 同步）——
    ("Aur","曜","光曜·显照·觉明"),("Umb","翳","阴翳·遮蔽·潜行"),
    ("Onr","梦","梦域·潜识·异境"),("Tid","潮","潮汐·涨落·周律"),
    ("Cry","晶","结晶·凝序·折光"),("Aby","渊","深渊·未知·引坠"),
    ("Pyr","焰","焰核·燃驱·转化"),("Neb","雾","雾散·弥漫·混沌"),
    ("Vin","藤","藤蔓·缠生·延展"),("Oss","骸","骸骨·残构·记痕"),
    ("Pul","脉","脉动·节律·活流"),("Vor","噬","吞噬·消解·并吞"),
    ("Blo","绽","绽放·涌现·盛发"),("Ech","回","回响·余韵·共振"),
    ("Fro","霜","霜封·凝寂·冷守"),("Emb","烬","余烬·残温·将熄"),
    ("Tho","棘","棘刺·防御·锋守"),("Vel","帷","帷幔·掩隔·仪境"),
    ("Dri","漂","漂流·无系·随势"),("Rad","根","根系·扎固·汲养"),
    ("Spk","芒","星芒·点爆·迸发"),("Hol","空","空腔·虚位·容纳"),
    ("Fat","命","命网·因缘·定数"),("Mir","镜","镜面·映照·对称"),
    ("Ash","灰","灰烬·终寂·归尘"),("See","种","种因·起势·孕发"),
    ("Sto","暴","风暴·激变·裹挟"),("Sil","丝","丝缕·细连·牵系"),
    ("Run","符","符文·封印·载义"),("Aeo","劫","劫纪·纪元·轮替"),
    ("Lux","烛","烛照·微明·守夜"),("Gla","冰","冰川·缓移·亘古"),
]
# ══════ 2. 外在映射 — 15基 ══════
_MANI_BASE = [
    ("cor","形","具象·轮廓"),("das","姿","流动·姿态"),("ryl","光","光影·色彩"),
    ("vok","声","听觉·语言"),("tyr","场","气场·辐射"),("syn","界","社交·边界"),
    ("gal","时","时间·阅历"),("nox","暗","暗场·深渊"),("tek","异","异构·违常"),
    ("mox","网","网络·结构"),("vec","向","向量·指向"),("flx","熵","熵变·耗散"),
    ("frm","象","逻辑投影"),("str","骨","骨架·框架"),("fnc","核","底层函数"),
]
# ══════ 3. 频段状态 — 8基 ══════
_STAT_BASE = [
    ("is","凝","收敛·静止"),("el","扬","发散·扩张"),("or","叠","叠加·迷离"),
    ("ia","极","绝对·极致"),("um","沉","下沉·深邃"),("ex","爆","瞬爆·失控"),
    ("kin","动","势能释放"),("sta","守","维持起源"),
]
# ══════ 4. 时空标量 — 8基（首项空）══════
_SCAL_BASE = [
    ("","",""),("gal","时光","时间维"),("vec","向","意图指向"),("nox","暗","暗场维"),
    ("rev","溯","逆时回溯"),("inf","无极","无限迭代"),("lok","锁","封锁固化"),("flx","熵流","熵流演化"),
]
# ══════ 5. 因果相位 — 8基 ══════
_PHASE_BASE = [
    ("qi","起","因果起点·第一推动"),("yan","衍","因果衍生·链式展开"),
    ("mao","锚","因果锚定·绝对静止"),("jie","借","因果嫁接·借力打力"),
    ("yin","隐","因果潜流·无感渗透"),("tan","坍","因果坍缩·归于元点"),
    ("zhi","织","因果编织·万网弥散"),("ying","映","因果投影·虚实对齐"),
]

# ══════ 阶扩展：纯音节，只动拉丁，不污染汉义 ══════
# 拉丁阶 = 在词根后缀一个谐音音节；汉义阶 = 在汉字后缀一个纯中文"阶名"
_LAT_TONE = ["","a","o","i","u","e","ar","or","is","yn","el","um","ex","ia","ko","na","ru","ze","vo","xi"]  # 20
_HAN_TONE = ["","甲","乙","丙","丁","戊","己","庚","辛","壬","癸","子","丑","寅","卯","辰","巳","午","未","申"]  # 20
_LAT_AURA = ["","x","z","n","r","s","k","l","m","t","d","p"]  # 12
_HAN_AURA = ["","玄","赤","青","白","朱","金","木","水","火","土","风"]  # 12
_LAT_FREQ = ["","1","2","3","4","5","6","7","8","9"]  # 10
_HAN_FREQ = ["","一","二","三","四","五","六","七","八","九"]  # 10
_LAT_SCAL = ["","p","t","k","b","d","g","h"]  # 8
_HAN_SCAL = ["","上","中","下","左","右","内","外"]  # 8  (首项对应空阶)

def _expand(base, lat_tones, han_tones):
    out=[]
    for (lat,han,sem) in base:
        for i,lt in enumerate(lat_tones):
            ht = han_tones[i] if i < len(han_tones) else ""
            if lt=="":
                out.append((lat,han,sem))
            else:
                out.append((lat+lt, han+ht, sem))
    return out

CORES  = _expand(_CORE_BASE, _LAT_TONE, _HAN_TONE)   # 52*20=1040
MANIS  = _expand(_MANI_BASE, _LAT_AURA, _HAN_AURA)   # 15*12=180
STATS  = _expand(_STAT_BASE, _LAT_FREQ, _HAN_FREQ)   # 8*10=80
SCALS  = _expand(_SCAL_BASE, _LAT_SCAL, _HAN_SCAL)   # 8*8=64
PHASES = list(_PHASE_BASE)                            # 8

NC,NM,NS,NK,NP = len(CORES),len(MANIS),len(STATS),len(SCALS),len(PHASES)
CAP = NC*NM*NS*NK*NP
AXES = {"核":NC,"映":NM,"态":NS,"标":NK,"相":NP}

_LAYERS = ["本源","虚无","观测","信息","秩序","情感","毁灭","孕育","幻象","枢",
           "元","衍","借","隐","熵","阈","静","映","织","逻",
           # v4 扩充 32 族的层名（顺序与 _CORE_BASE 追加段一一对应，同 lexicon.js 第 4 列）
           "显照","阴翳","梦域","潮汐","结晶","深渊","焰核","雾散",
           "藤蔓","骸骨","脉动","吞噬","绽放","回响","霜封","余烬",
           "棘刺","帷幔","漂流","根系","星芒","空腔","命网","镜面",
           "灰烬","种因","风暴","丝缕","符文","劫纪","烛照","冰川"]
LAYER_BY_CORE = {b[0]:l for b,l in zip(_CORE_BASE,_LAYERS)}
_TONES_PER_CORE = len(_LAT_TONE)   # 每族 20 阶：核下标 // 20 = 族下标 = 层下标

def _layer_of(core_lat):
    """核拉丁根 → 层名（保留旧接口；内部已改为按下标 O(1) 取，见 decode）"""
    for k in sorted(LAYER_BY_CORE, key=len, reverse=True):
        if core_lat.startswith(k): return LAYER_BY_CORE[k]
    return "枢"

# ══════ 反向索引：拉丁 / 汉 → 轴内下标（encode 从 O(轴长) 线性扫描降到 O(1)，与 lexicon.js 同构）══════
_AXES = (CORES, MANIS, STATS, SCALS, PHASES)
_LAT_IDX = tuple({x[0]:i for i,x in enumerate(ax)} for ax in _AXES)
_HAN_IDX = tuple({x[1]:i for i,x in enumerate(ax)} for ax in _AXES)
_AXIS_NAMES = ("核","映","态","标","相")
_BASES = (_CORE_BASE, _MANI_BASE, _STAT_BASE, _SCAL_BASE, _PHASE_BASE)
_TONE_LENS = (len(_LAT_TONE), len(_LAT_AURA), len(_LAT_FREQ), len(_LAT_SCAL), 1)

def _id_of(c,m,s,k,p):
    return ((((c*NM)+m)*NS+s)*NK+k)*NP+p

def _coord_of(n):
    nn=n
    p = nn % NP; nn//=NP
    k = nn % NK; nn//=NK
    s = nn % NS; nn//=NS
    m = nn % NM; nn//=NM
    c = nn % NC
    return c,m,s,k,p

def decode(n):
    """编号 → 枢语词（O(1) 寻址）。汉译纯中文，词形有韵律。

    返回字段与 lexicon.js 完全对等：id / 词 / 汉 / 层 / 义 / 根 / 坐标；
    Python 侧另保留 seed（历史字段，只增不删）。
    """
    # 必须先挡非整数：nan/小数过不了下面的区间比较（与 nan 比大小恒为 False），
    # 会一路穿到 CORES[c] 抛出看不懂的 TypeError。bool 也不算合法编号。
    if isinstance(n, bool) or not isinstance(n, int):
        raise TypeError("编号必须是整数")
    if n<0 or n>=CAP: raise ValueError(f"编号越界 0..{CAP-1}")
    c,m,s,k,p = _coord_of(n)
    C,M,S,K,P = CORES[c],MANIS[m],STATS[s],SCALS[k],PHASES[p]
    # 拉丁词形：核-映-态(-标)·相
    base = f"{C[0]}-{M[0]}-{S[0]}"
    if K[0]: base += f"-{K[0]}"
    word = f"{base}·{P[0]}"
    # 汉译：纯中文
    han = f"{C[1]}{M[1]}{S[1]}"
    if K[1]: han += K[1]
    han += P[1]
    # 语义
    sem = f"{C[2]} / {M[2]} / {S[2]}"
    if K[2]: sem += f" / {K[2]}"
    sem += f" / {P[2]}"
    return {"id":n,"词":word,"汉":han,"层":_LAYERS[c//_TONES_PER_CORE],"义":sem,
            "根":[C[0],M[0],S[0],K[0] or "∅",P[0]],
            "坐标":{"c":c,"m":m,"s":s,"k":k,"p":p},
            "seed":hashlib.sha1(word.encode()).hexdigest()[:10]}

def decode_full(n):
    """兼容旧接口：decode 现已自带 id，此处等价于 decode。"""
    return decode(n)

def encode(word):
    """枢语词（拉丁词形）→ 编号（反向寻址，O(1)）。

    单射铁律：encode 必须是 decode 的严格逆。凡 decode 产不出的写法一律判非法（返回 -1），
    否则畸形词会被映射到一个合法编号，跨仓语义就此错位。
    """
    try:
        head, ph = word.rsplit("·",1)
        parts = head.split("-")
        # 词形只有 3 段（空标轴）或 4 段（带标轴）两种，其余一律非法
        if len(parts) < 3 or len(parts) > 4:
            return -1
        clat = parts[0]; mlat=parts[1]; slat=parts[2]
        klat = parts[3] if len(parts)>3 else ""
        # 空标轴只能用 3 段词形表达；"核-映-态-·相" 这种显式空标段 decode 永远产不出，
        # 放行的话它会和 3 段词形撞同一个编号（与 lexicon.js 同规则）
        if len(parts) > 3 and klat == "":
            return -1
        ci=_LAT_IDX[0][clat]; mi=_LAT_IDX[1][mlat]; si=_LAT_IDX[2][slat]
        ki=_LAT_IDX[3][klat]; pi=_LAT_IDX[4][ph]
        return _id_of(ci,mi,si,ki,pi)
    except Exception:
        return -1

def encode_han(han):
    """汉译（纯中文）→ 编号。解不出或解不唯一一律 -1，与拉丁 encode 同一单射铁律。

    汉译 = 核汉(1~2 字) + 映汉(1~2 字) + 态汉(1~2 字) + 标汉(0~3 字) + 相汉(1 字)。
    各轴后缀字（阶/相/频/标位）与下一轴首字零交集，因此汉译唯一可解码（tests 里有结构引理守卫）。
    实现上不依赖这个引理：回溯枚举全部切法，只有恰好一种切法时才返回编号，否则 -1。
    """
    if not isinstance(han, str) or len(han) < 4:
        return -1
    pi = _HAN_IDX[4].get(han[-1])
    if pi is None:
        return -1
    body = han[:-1]
    found = []
    L = len(body)
    for lc in (1,2):
        ci = _HAN_IDX[0].get(body[:lc])
        if ci is None or lc > L: continue
        for lm in (1,2):
            mi = _HAN_IDX[1].get(body[lc:lc+lm])
            if mi is None or lc+lm > L: continue
            for ls in (1,2):
                si = _HAN_IDX[2].get(body[lc+lm:lc+lm+ls])
                if si is None or lc+lm+ls > L: continue
                ki = _HAN_IDX[3].get(body[lc+lm+ls:])
                if ki is None: continue
                found.append(_id_of(ci,mi,si,ki,pi))
                if len(found) > 1:
                    return -1
    return found[0] if len(found) == 1 else -1

# ══════ 语义检索：关键词 → 命中的词根（5 轴基表级，不展开阶）══════
def _hit_score(kw, kwl, lat, han, sem):
    latl = (lat or "").lower()
    if kwl and kwl == latl: return 400
    if han and han == kw: return 380
    if sem and kw in sem.split("·"): return 300
    if han and han.startswith(kw): return 240
    if han and kw in han: return 200
    if sem and kw in sem: return 160
    if latl and len(kwl) >= 2 and kwl in latl: return 100
    return 0

def search(keyword, axis=None):
    """在 5 轴基表的 拉丁/汉/义 里找关键词（拉丁不分大小写），返回按相关度排序的命中。

    每项：{"轴","下标","拉丁","汉","义"}，下标是**展开后**轴内下标（基表下标 × 阶数，即 0 阶），
    可直接喂给 compose / coin_from_coord。axis 可限定 核/映/态/标/相 之一。
    排序：精确拉丁/汉 > 义段整词 > 前缀/包含；同分按轴序、下标。不改命中集合。
    """
    if not isinstance(keyword, str) or not keyword.strip():
        return []
    kw = keyword.strip(); kwl = kw.lower()
    out = []
    for ai,(name,base,tl) in enumerate(zip(_AXIS_NAMES,_BASES,_TONE_LENS)):
        if axis and axis != name: continue
        for bi,(lat,han,sem) in enumerate(base):
            if not lat and not han: continue   # 标轴首项是空阶，没有可检索内容
            if _hit_score(kw, kwl, lat, han, sem) > 0:
                out.append({"轴":name,"下标":bi*tl,"拉丁":lat,"汉":han,"义":sem})
    out.sort(key=lambda h: (-_hit_score(kw, kwl, h["拉丁"], h["汉"], h["义"]), _AXIS_NAMES.index(h["轴"]), h["下标"]))
    return out

def _resolve_axis(ai, val):
    """把一轴的用户输入解析成展开后下标：整数下标 / 拉丁根 / 汉译 / 语义关键词（基表首命中，0 阶）。"""
    if val is None or val == "":
        return 0
    if isinstance(val, bool):
        raise ValueError(f"{_AXIS_NAMES[ai]}轴不接受布尔值")
    n = len(_AXES[ai])
    if isinstance(val, int):
        if val < 0 or val >= n: raise ValueError(f"{_AXIS_NAMES[ai]}轴下标越界 0..{n-1}: {val}")
        return val
    if not isinstance(val, str):
        raise ValueError(f"{_AXIS_NAMES[ai]}轴入参类型非法")
    v = val.strip()
    if v.isdigit():
        return _resolve_axis(ai, int(v))
    i = _LAT_IDX[ai].get(v)
    if i is not None: return i
    i = _HAN_IDX[ai].get(v)
    if i is not None: return i
    hits = search(v, _AXIS_NAMES[ai])
    if hits: return hits[0]["下标"]
    raise ValueError(f"{_AXIS_NAMES[ai]}轴找不到「{val}」")

def compose(spec):
    """按义造词：spec 为 {核,映,态,标,相}（也接受 c,m,s,k,p 键），每轴给
    整数下标 / 拉丁根 / 汉译 / 语义关键词 任一种；缺省轴取 0。确定性，返回 decode 结果。
    解析失败抛 ValueError（不静默落到别的词上——按义造词不许造错词）。
    """
    if not isinstance(spec, dict):
        raise ValueError("compose 需要 dict")
    alias = {"c":"核","m":"映","s":"态","k":"标","p":"相"}
    norm = {}
    for key,val in spec.items():
        k = alias.get(key, key)
        if k not in _AXIS_NAMES: raise ValueError(f"未知轴「{key}」")
        norm[k] = val
    idx = [_resolve_axis(ai, norm.get(name)) for ai,name in enumerate(_AXIS_NAMES)]
    return decode(_id_of(*idx))

def _resolve_word(value):
    if isinstance(value, bool) or value is None:
        raise ValueError("类比词必须是编号或枢语词")
    if isinstance(value, int):
        return decode(value)
    if not isinstance(value, str) or not value.strip():
        raise ValueError("类比词必须是编号或枢语词")
    s = value.strip()
    if re.fullmatch(r"0|[1-9][0-9]*", s):
        return decode(int(s))
    nid = encode(s)
    if nid < 0:
        nid = encode_han(s)
    if nid < 0:
        raise ValueError(f"类比找不到「{value}」")
    return decode(nid)

def analogy(a, b, c):
    """五维类比造词：A:B :: C:?  →  C + (B − A) 按轴取模，与 lexicon.js analogy 同构。"""
    A, B, C = _resolve_word(a), _resolve_word(b), _resolve_word(c)
    sizes = (NC, NM, NS, NK, NP)
    keys = ("c", "m", "s", "k", "p")
    idx = [((C["坐标"][k] + B["坐标"][k] - A["坐标"][k]) % sizes[i] + sizes[i]) % sizes[i] for i, k in enumerate(keys)]
    return decode(_id_of(*idx))

def near(value, limit=8):
    """五维 L1=1 邻近词，不环绕；与 lexicon.js near 同构。编号空间不变。"""
    try:
        n = int(limit)
    except (TypeError, ValueError):
        n = 8
    n = 16 if n > 16 else (1 if n < 1 else n)
    word = _resolve_word(value)
    sizes = (NC, NM, NS, NK, NP)
    keys = ("c", "m", "s", "k", "p")
    origin = [word["坐标"][k] for k in keys]
    out = []
    for i, name in enumerate(_AXIS_NAMES):
        for delta in (-1, 1):
            nxt = origin[i] + delta
            if nxt < 0 or nxt >= sizes[i]:
                continue
            idx = list(origin)
            idx[i] = nxt
            w = decode(_id_of(*idx))
            out.append({"距": 1, "轴": name, "id": w["id"], "词": w["词"], "汉": w["汉"], "义": w["义"], "坐标": w["坐标"]})
    return out[:n]


_PULSE_MAX_AT = 4102444800


def _pulse_phase(hour):
    if 5 <= hour <= 7:
        return "晨"
    if 8 <= hour <= 16:
        return "昼"
    if 17 <= hour <= 19:
        return "昏"
    return "夜"


def pulse(seed, at):
    """一息：按显式 Unix 秒沿一轴呼吸一格，不环绕；与 lexicon.js pulse 同构。"""
    if isinstance(at, bool):
        raise ValueError("一息时刻必须是0至4102444800的Unix秒")
    if isinstance(at, str):
        if not re.fullmatch(r"0|[1-9][0-9]*", at):
            raise ValueError("一息时刻必须是0至4102444800的Unix秒")
        t = int(at)
    else:
        try:
            t = int(at)
        except (TypeError, ValueError):
            raise ValueError("一息时刻必须是0至4102444800的Unix秒")
        if t != at:
            raise ValueError("一息时刻必须是0至4102444800的Unix秒")
    if t < 0 or t > _PULSE_MAX_AT:
        raise ValueError("一息时刻必须是0至4102444800的Unix秒")
    word = _resolve_word(0 if seed is None or seed == "" else seed)
    day = ((t % 86400) + 86400) % 86400
    hour = day // 3600
    minute = (day % 3600) // 60
    sizes = (NC, NM, NS, NK, NP)
    keys = ("c", "m", "s", "k", "p")
    origin = [word["坐标"][k] for k in keys]
    axis = hour % 5
    direction = 1 if minute < 30 else -1
    nxt = list(origin)
    candidate = nxt[axis] + direction
    moved = False
    if 0 <= candidate < sizes[axis]:
        nxt[axis] = candidate
        moved = True
    out = decode(_id_of(*nxt))
    return {
        "息": _pulse_phase(hour),
        "时": hour,
        "分": minute,
        "轴": _AXIS_NAMES[axis],
        "向": direction,
        "动": moved,
        "种": {"id": word["id"], "词": word["词"], "汉": word["汉"]},
        "id": out["id"], "词": out["词"], "汉": out["汉"], "义": out["义"], "坐标": out["坐标"],
    }


def _parse_trail_n(n):
    if n is None or n == "":
        return 3
    if isinstance(n, bool):
        raise ValueError("余息步数必须是2至4")
    if isinstance(n, str):
        if not re.fullmatch(r"[1-9][0-9]*", n):
            raise ValueError("余息步数必须是2至4")
        value = int(n)
    else:
        try:
            value = int(n)
        except (TypeError, ValueError):
            raise ValueError("余息步数必须是2至4")
        if value != n:
            raise ValueError("余息步数必须是2至4")
    if value < 2 or value > 4:
        raise ValueError("余息步数必须是2至4")
    return value


def _compact_pulse(p):
    return {
        "息": p["息"], "时": p["时"], "分": p["分"], "轴": p["轴"], "向": p["向"], "动": p["动"],
        "id": p["id"], "词": p["词"], "汉": p["汉"], "义": p["义"], "坐标": p["坐标"],
    }


def trail(seed, at, n=3):
    """余息：从一词连续呼吸几格，每步 +60 秒，不环绕；与 lexicon.js trail 同构。"""
    count = _parse_trail_n(n)
    origin = pulse(seed, at)
    if isinstance(at, str):
        start = int(at)
    else:
        start = int(at)
    steps = [_compact_pulse(origin)]
    current = origin["id"]
    for i in range(1, count):
        step_at = start + i * 60
        if step_at > _PULSE_MAX_AT:
            break
        nxt = pulse(current, step_at)
        steps.append(_compact_pulse(nxt))
        current = nxt["id"]
    last = steps[-1]
    return {
        "息": steps[0]["息"],
        "种": origin["种"],
        "步": len(steps),
        "迹": steps,
        "id": last["id"], "词": last["词"], "汉": last["汉"], "义": last["义"], "坐标": last["坐标"],
    }


def echo(seed, at, n=3):
    """回息：余息走完后沿末步反向弹一格，不环绕；与 lexicon.js echo 同构。"""
    walk = trail(seed, at, n)
    last = walk["迹"][-1]
    sizes = (NC, NM, NS, NK, NP)
    keys = ("c", "m", "s", "k", "p")
    axis = _AXIS_NAMES.index(last["轴"])
    rebound = [last["坐标"][k] for k in keys]
    back = -last["向"]
    candidate = rebound[axis] + back
    echoed = False
    if 0 <= candidate < sizes[axis]:
        rebound[axis] = candidate
        echoed = True
    out = decode(_id_of(*rebound))
    return {
        "息": last["息"],
        "种": walk["种"],
        "步": walk["步"],
        "迹": walk["迹"],
        "回": echoed,
        "轴": last["轴"],
        "向": back,
        "id": out["id"], "词": out["词"], "汉": out["汉"], "义": out["义"], "坐标": out["坐标"],
    }


def _compact_pose(word, meta):
    return {
        "息": meta["息"], "时": meta["时"], "分": meta["分"], "轴": meta["轴"], "向": meta["向"], "动": meta["动"],
        "id": word["id"], "词": word["词"], "汉": word["汉"], "义": word["义"], "坐标": word["坐标"],
    }


def sway(seed, at, n=3):
    """摇息：回息后按分钟在弹回词与末步之间摇摆，不环绕；与 lexicon.js sway 同构。"""
    rest = echo(seed, at, n)
    last = rest["迹"][-1]
    if isinstance(at, str):
        t = int(at)
    else:
        t = int(at)
    side = (t // 60) % 2
    rest_pose = _compact_pose(rest, {"息": last["息"], "时": last["时"], "分": last["分"], "轴": rest["轴"], "向": rest["向"], "动": rest["回"]})
    lean = last
    swaying = rest["id"] != last["id"]
    pose = lean if swaying and side == 1 else rest_pose
    return {
        "息": rest["息"],
        "种": rest["种"],
        "步": rest["步"],
        "迹": rest["迹"],
        "回": rest["回"],
        "轴": pose["轴"],
        "向": pose["向"],
        "摇": swaying,
        "侧": side if swaying else 0,
        "摆": rest_pose if (swaying and side == 1) else (lean if swaying else rest_pose),
        "id": pose["id"], "词": pose["词"], "汉": pose["汉"], "义": pose["义"], "坐标": pose["坐标"],
    }


def land(seed, at, n=3):
    """落息：摇息后按四分钟窗落地，偏停在弹回词，不环绕；与 lexicon.js land 同构。"""
    rest = echo(seed, at, n)
    last = rest["迹"][-1]
    if isinstance(at, str):
        t = int(at)
    else:
        t = int(at)
    phase = (t // 60) % 4
    rest_pose = _compact_pose(rest, {"息": last["息"], "时": last["时"], "分": last["分"], "轴": rest["轴"], "向": rest["向"], "动": rest["回"]})
    lean = last
    can_land = rest["id"] != last["id"]
    airborne = can_land and phase == 0
    pose = lean if airborne else rest_pose
    return {
        "息": rest["息"],
        "种": rest["种"],
        "步": rest["步"],
        "迹": rest["迹"],
        "回": rest["回"],
        "轴": pose["轴"],
        "向": pose["向"],
        "落": not airborne,
        "侧": 1 if airborne else 0,
        "着": rest_pose if airborne else lean,
        "id": pose["id"], "词": pose["词"], "汉": pose["汉"], "义": pose["义"], "坐标": pose["坐标"],
    }


def stir(seed, at, n=3):
    """起息：落息落地后按八分钟窗从着地点朝邻格起身，不环绕；与 lexicon.js stir 同构。"""
    down = land(seed, at, n)
    last = down["迹"][-1]
    if isinstance(at, str):
        t = int(at)
    else:
        t = int(at)
    neighbors = near(down["id"], 16)
    rising = bool(down["落"]) and len(neighbors) > 0
    pick = neighbors[(t // 480) % len(neighbors)] if rising else None
    keys = ("c", "m", "s", "k", "p")
    sit = _compact_pose(down, {"息": last["息"], "时": last["时"], "分": last["分"], "轴": down["轴"], "向": down["向"], "动": down["落"]})
    pose = sit
    if pick is not None:
        axis = _AXIS_NAMES.index(pick["轴"])
        direction = 1 if pick["坐标"][keys[axis]] > down["坐标"][keys[axis]] else -1
        pose = _compact_pose(pick, {"息": last["息"], "时": last["时"], "分": last["分"], "轴": pick["轴"], "向": direction, "动": True})
    return {
        "息": down["息"],
        "种": down["种"],
        "步": down["步"],
        "迹": down["迹"],
        "回": down["回"],
        "轴": pose["轴"],
        "向": pose["向"],
        "落": down["落"],
        "侧": down["侧"],
        "着": down["着"],
        "起": pick is not None,
        "由": sit,
        "id": pose["id"], "词": pose["词"], "汉": pose["汉"], "义": pose["义"], "坐标": pose["坐标"],
    }


def perch(seed, at, n=3):
    """栖息：起息起身后沿起身轴再蹲一格，越界则蹲在起身词上，未起不栖；与 lexicon.js perch 同构。"""
    up = stir(seed, at, n)
    last = up["迹"][-1]
    sizes = (NC, NM, NS, NK, NP)
    keys = ("c", "m", "s", "k", "p")
    rise = _compact_pose(up, {"息": last["息"], "时": last["时"], "分": last["分"], "轴": up["轴"], "向": up["向"], "动": up["起"]})
    pose = rise
    nested = False
    if up["起"]:
        nested = True
        axis = _AXIS_NAMES.index(up["轴"])
        coord = [up["坐标"][k] for k in keys]
        nxt = coord[axis] + up["向"]
        if 0 <= nxt < sizes[axis]:
            coord[axis] = nxt
            pose = _compact_pose(decode(_id_of(*coord)), {"息": last["息"], "时": last["时"], "分": last["分"], "轴": up["轴"], "向": up["向"], "动": True})
    return {
        "息": up["息"],
        "种": up["种"],
        "步": up["步"],
        "迹": up["迹"],
        "回": up["回"],
        "轴": pose["轴"],
        "向": pose["向"],
        "落": up["落"],
        "侧": up["侧"],
        "着": up["着"],
        "起": up["起"],
        "由": up["由"],
        "起处": rise,
        "栖": nested,
        "id": pose["id"], "词": pose["词"], "汉": pose["汉"], "义": pose["义"], "坐标": pose["坐标"],
    }


def turn(seed, at, n=3):
    """转息：栖息后再朝侧邻转头，未栖不转，无侧邻则停在栖处；与 lexicon.js turn 同构。"""
    nest = perch(seed, at, n)
    last = nest["迹"][-1]
    if isinstance(at, str):
        t = int(at)
    else:
        t = int(at)
    sit = _compact_pose(nest, {"息": last["息"], "时": last["时"], "分": last["分"], "轴": nest["轴"], "向": nest["向"], "动": nest["栖"]})
    neighbors = [word for word in near(nest["id"], 16) if word["轴"] != nest["轴"]]
    turning = bool(nest["栖"]) and len(neighbors) > 0
    pick = neighbors[(t // 960) % len(neighbors)] if turning else None
    keys = ("c", "m", "s", "k", "p")
    pose = sit
    if pick is not None:
        axis = _AXIS_NAMES.index(pick["轴"])
        direction = 1 if pick["坐标"][keys[axis]] > nest["坐标"][keys[axis]] else -1
        pose = _compact_pose(pick, {"息": last["息"], "时": last["时"], "分": last["分"], "轴": pick["轴"], "向": direction, "动": True})
    return {
        "息": nest["息"],
        "种": nest["种"],
        "步": nest["步"],
        "迹": nest["迹"],
        "回": nest["回"],
        "轴": pose["轴"],
        "向": pose["向"],
        "落": nest["落"],
        "侧": nest["侧"],
        "着": nest["着"],
        "起": nest["起"],
        "由": nest["由"],
        "起处": nest["起处"],
        "栖": nest["栖"],
        "栖处": sit,
        "转": pick is not None,
        "id": pose["id"], "词": pose["词"], "汉": pose["汉"], "义": pose["义"], "坐标": pose["坐标"],
    }


def gaze(seed, at, n=3):
    """顾息：转头后再沿转轴把目光探一格，未转不顾，三十二分钟窗才探，越界停在转处；与 lexicon.js gaze 同构。"""
    looked = turn(seed, at, n)
    last = looked["迹"][-1]
    if isinstance(at, str):
        t = int(at)
    else:
        t = int(at)
    face = _compact_pose(looked, {"息": last["息"], "时": last["时"], "分": last["分"], "轴": looked["轴"], "向": looked["向"], "动": looked["转"]})
    keys = ("c", "m", "s", "k", "p")
    pose = face
    gazing = False
    if looked["转"] and (t // 1920) % 2 == 0:
        gazing = True
        sizes = [NC, NM, NS, NK, NP]
        axis = _AXIS_NAMES.index(looked["轴"])
        coord = [looked["坐标"][key] for key in keys]
        nxt = coord[axis] + looked["向"]
        if 0 <= nxt < sizes[axis]:
            coord[axis] = nxt
            pose = _compact_pose(decode(_id_of(*coord)), {"息": last["息"], "时": last["时"], "分": last["分"], "轴": looked["轴"], "向": looked["向"], "动": True})
    return {
        "息": looked["息"],
        "种": looked["种"],
        "步": looked["步"],
        "迹": looked["迹"],
        "回": looked["回"],
        "轴": pose["轴"],
        "向": pose["向"],
        "落": looked["落"],
        "侧": looked["侧"],
        "着": looked["着"],
        "起": looked["起"],
        "由": looked["由"],
        "起处": looked["起处"],
        "栖": looked["栖"],
        "栖处": looked["栖处"],
        "转": looked["转"],
        "转处": face,
        "顾": gazing,
        "id": pose["id"], "词": pose["词"], "汉": pose["汉"], "义": pose["义"], "坐标": pose["坐标"],
    }


def incline(seed, at, n=3):
    """倾息：望出去后再沿望轴倾近一格，未顾不倾，六十四分钟窗才倾，越界停在望处；与 lexicon.js incline 同构。"""
    gazed = gaze(seed, at, n)
    last = gazed["迹"][-1]
    if isinstance(at, str):
        t = int(at)
    else:
        t = int(at)
    look = _compact_pose(gazed, {"息": last["息"], "时": last["时"], "分": last["分"], "轴": gazed["轴"], "向": gazed["向"], "动": gazed["顾"]})
    keys = ("c", "m", "s", "k", "p")
    pose = look
    inclining = False
    if gazed["顾"] and (t // 3840) % 2 == 0:
        inclining = True
        sizes = [NC, NM, NS, NK, NP]
        axis = _AXIS_NAMES.index(gazed["轴"])
        coord = [gazed["坐标"][key] for key in keys]
        nxt = coord[axis] + gazed["向"]
        if 0 <= nxt < sizes[axis]:
            coord[axis] = nxt
            pose = _compact_pose(decode(_id_of(*coord)), {"息": last["息"], "时": last["时"], "分": last["分"], "轴": gazed["轴"], "向": gazed["向"], "动": True})
    return {
        "息": gazed["息"],
        "种": gazed["种"],
        "步": gazed["步"],
        "迹": gazed["迹"],
        "回": gazed["回"],
        "轴": pose["轴"],
        "向": pose["向"],
        "落": gazed["落"],
        "侧": gazed["侧"],
        "着": gazed["着"],
        "起": gazed["起"],
        "由": gazed["由"],
        "起处": gazed["起处"],
        "栖": gazed["栖"],
        "栖处": gazed["栖处"],
        "转": gazed["转"],
        "转处": gazed["转处"],
        "顾": gazed["顾"],
        "顾处": look,
        "倾": inclining,
        "id": pose["id"], "词": pose["词"], "汉": pose["汉"], "义": pose["义"], "坐标": pose["坐标"],
    }


def nestle(seed, at, n=3):
    """贴息：倾近后再贴住一格，未倾不贴，一百二十八分钟窗才贴，越界停在倾处；与 lexicon.js nestle 同构。"""
    leaned = incline(seed, at, n)
    last = leaned["迹"][-1]
    if isinstance(at, str):
        t = int(at)
    else:
        t = int(at)
    rest = _compact_pose(leaned, {"息": last["息"], "时": last["时"], "分": last["分"], "轴": leaned["轴"], "向": leaned["向"], "动": leaned["倾"]})
    keys = ("c", "m", "s", "k", "p")
    pose = rest
    nestling = False
    if leaned["倾"] and (t // 7680) % 2 == 0:
        nestling = True
        sizes = [NC, NM, NS, NK, NP]
        axis = _AXIS_NAMES.index(leaned["轴"])
        coord = [leaned["坐标"][key] for key in keys]
        nxt = coord[axis] + leaned["向"]
        if 0 <= nxt < sizes[axis]:
            coord[axis] = nxt
            pose = _compact_pose(decode(_id_of(*coord)), {"息": last["息"], "时": last["时"], "分": last["分"], "轴": leaned["轴"], "向": leaned["向"], "动": True})
    return {
        "息": leaned["息"],
        "种": leaned["种"],
        "步": leaned["步"],
        "迹": leaned["迹"],
        "回": leaned["回"],
        "轴": pose["轴"],
        "向": pose["向"],
        "落": leaned["落"],
        "侧": leaned["侧"],
        "着": leaned["着"],
        "起": leaned["起"],
        "由": leaned["由"],
        "起处": leaned["起处"],
        "栖": leaned["栖"],
        "栖处": leaned["栖处"],
        "转": leaned["转"],
        "转处": leaned["转处"],
        "顾": leaned["顾"],
        "顾处": leaned["顾处"],
        "倾": leaned["倾"],
        "倾处": rest,
        "贴": nestling,
        "id": pose["id"], "词": pose["词"], "汉": pose["汉"], "义": pose["义"], "坐标": pose["坐标"],
    }


def hold(seed, at, n=3):
    """含息：贴住后再含住一格，未贴不含，二百五十六分钟窗才含，越界停在贴处；与 lexicon.js hold 同构。"""
    nestled = nestle(seed, at, n)
    last = nestled["迹"][-1]
    if isinstance(at, str):
        t = int(at)
    else:
        t = int(at)
    close = _compact_pose(nestled, {"息": last["息"], "时": last["时"], "分": last["分"], "轴": nestled["轴"], "向": nestled["向"], "动": nestled["贴"]})
    keys = ("c", "m", "s", "k", "p")
    pose = close
    holding = False
    if nestled["贴"] and (t // 15360) % 2 == 0:
        holding = True
        sizes = [NC, NM, NS, NK, NP]
        axis = _AXIS_NAMES.index(nestled["轴"])
        coord = [nestled["坐标"][key] for key in keys]
        nxt = coord[axis] + nestled["向"]
        if 0 <= nxt < sizes[axis]:
            coord[axis] = nxt
            pose = _compact_pose(decode(_id_of(*coord)), {"息": last["息"], "时": last["时"], "分": last["分"], "轴": nestled["轴"], "向": nestled["向"], "动": True})
    return {
        "息": nestled["息"],
        "种": nestled["种"],
        "步": nestled["步"],
        "迹": nestled["迹"],
        "回": nestled["回"],
        "轴": pose["轴"],
        "向": pose["向"],
        "落": nestled["落"],
        "侧": nestled["侧"],
        "着": nestled["着"],
        "起": nestled["起"],
        "由": nestled["由"],
        "起处": nestled["起处"],
        "栖": nestled["栖"],
        "栖处": nestled["栖处"],
        "转": nestled["转"],
        "转处": nestled["转处"],
        "顾": nestled["顾"],
        "顾处": nestled["顾处"],
        "倾": nestled["倾"],
        "倾处": nestled["倾处"],
        "贴": nestled["贴"],
        "贴处": close,
        "含": holding,
        "id": pose["id"], "词": pose["词"], "汉": pose["汉"], "义": pose["义"], "坐标": pose["坐标"],
    }

# ══════ 造词族：与 lexicon.js 逐位一致 ══════
_U32 = 0xFFFFFFFF

def auto_coin(seed):
    """确定性种子造词：FNV-1a(32 位，按 UTF-16 码元) + xorshift，与 JS autoCoin 逐位一致。
    已知限制：哈希是 uint32，高位约 44% 语义空间永不可达（JS 侧测试同样钉住此现状，改哈希需两侧同时拍板）。
    """
    s = str(seed)
    h = 2166136261
    units = s.encode("utf-16-le")
    for i in range(0, len(units), 2):
        h ^= units[i] | (units[i+1] << 8)
        h = (h * 16777619) & _U32
    h ^= (h << 13) & _U32
    h ^= h >> 17
    h ^= (h << 5) & _U32
    h &= _U32
    return decode(h % CAP)

def _clamp_axis(v, mx):
    try:
        v = int(v // 1) if isinstance(v, float) else int(v or 0)
    except Exception:
        v = 0
    return 0 if v < 0 else (mx-1 if v >= mx else v)

def coin_from_coord(coord):
    """从 5 维坐标造词，越界坐标夹回合法区间（与 JS coinFromCoord 一致）。"""
    coord = coord or {}
    c=_clamp_axis(coord.get("c"),NC); m=_clamp_axis(coord.get("m"),NM); s=_clamp_axis(coord.get("s"),NS)
    k=_clamp_axis(coord.get("k"),NK); p=_clamp_axis(coord.get("p"),NP)
    return decode(_id_of(c,m,s,k,p))

def coin_word(layer_name, rng=None):
    """从指定核心层随机取一个词；层名不存在则全空间随机（与 JS coinWord 一致）。rng 可传 random.Random 保证可复现。"""
    import random as _random
    rng = rng or _random
    if layer_name in _LAYERS:
        base = _LAYERS.index(layer_name) * _TONES_PER_CORE
        c = base + rng.randrange(_TONES_PER_CORE)
        return decode(_id_of(c, rng.randrange(NM), rng.randrange(NS), rng.randrange(NK), rng.randrange(NP)))
    return decode(rng.randrange(CAP))

def coin_from_state(soul, seed=None, rng=None):
    """按状态自主造词：心绪/想念决定核心层（与 JS coinFromState 同规则），有 seed 则确定性。"""
    soul = soul or {}
    mood = soul.get("心绪", 0.5); mood = 0.5 if mood is None else mood
    miss = soul.get("miss_you", 0); miss = 0 if miss is None else miss
    if miss > 0.7: layer = "映"
    elif mood > 0.65: layer = "情感"
    elif mood < 0.35: layer = "熵"
    else: layer = "枢"
    w = auto_coin(f"{seed}|{layer}") if seed is not None else coin_word(layer, rng)
    w = dict(w); w["层意图"] = layer
    return w

def _parse_compose_arg(text):
    """把 CLI 的 "核=毁灭,映=光,态=爆,标=溯,相=起" 解析成 compose 的 spec。"""
    spec = {}
    for seg in text.split(","):
        seg = seg.strip()
        if not seg: continue
        if "=" not in seg: raise ValueError(f"compose 片段缺少「=」: {seg}")
        k, v = seg.split("=", 1)
        spec[k.strip()] = v.strip()
    return spec

def main(argv=None):
    ap=argparse.ArgumentParser(description="枢语 5 维语义空间引擎（Python 版，与 lexicon.js 同构）")
    ap.add_argument("--count",action="store_true",help="只打印容量")
    ap.add_argument("--id",type=int,default=-1,help="编号 → 词")
    ap.add_argument("--word",default="",help="拉丁词形 → 编号（如 Kha-ryl-is·qi）")
    ap.add_argument("--han",default="",help="汉译 → 编号（如 奥形凝起）")
    ap.add_argument("--search",default="",help="语义关键词 → 命中的词根（5 轴）")
    ap.add_argument("--compose",default="",help="按义造词，如 核=毁灭,映=光,态=爆,标=溯,相=起")
    ap.add_argument("--analogy",nargs=3,metavar=("A","B","C"),help="五维类比造词：A:B :: C:?")
    ap.add_argument("--near",default="",help="五维邻近词（L1=1，不环绕）")
    ap.add_argument("--pulse",default="",help="一息种子（编号或词，缺省为0）")
    ap.add_argument("--trail",nargs="?",const="",default=None,help="余息种子（编号或词，缺省为0）")
    ap.add_argument("--echo",nargs="?",const="",default=None,help="回息种子（编号或词，缺省为0）")
    ap.add_argument("--sway",nargs="?",const="",default=None,help="摇息种子（编号或词，缺省为0）")
    ap.add_argument("--land",nargs="?",const="",default=None,help="落息种子（编号或词，缺省为0）")
    ap.add_argument("--stir",nargs="?",const="",default=None,help="起息种子（编号或词，缺省为0）")
    ap.add_argument("--perch",nargs="?",const="",default=None,help="栖息种子（编号或词，缺省为0）")
    ap.add_argument("--turn",nargs="?",const="",default=None,help="转息种子（编号或词，缺省为0）")
    ap.add_argument("--gaze",nargs="?",const="",default=None,help="顾息种子（编号或词，缺省为0）")
    ap.add_argument("--incline",nargs="?",const="",default=None,help="倾息种子（编号或词，缺省为0）")
    ap.add_argument("--nestle",nargs="?",const="",default=None,help="贴息种子（编号或词，缺省为0）")
    ap.add_argument("--hold",nargs="?",const="",default=None,help="含息种子（编号或词，缺省为0）")
    ap.add_argument("--at",type=int,default=-1,help="一息/余息/回息/摇息/落息/起息/栖息/转息/顾息/倾息/贴息/含息 Unix 秒（UTC）")
    ap.add_argument("--n",type=int,default=3,help="余息/回息/摇息/落息/起息/栖息/转息/顾息/倾息/贴息/含息步数，2至4")
    ap.add_argument("--coin",default=None,help="确定性种子造词（与 JS autoCoin 同种子同词）")
    ap.add_argument("--sample",type=int,default=0)
    ap.add_argument("--dump",default="")
    ap.add_argument("--limit",type=int,default=0)
    ap.add_argument("--shard",type=int,default=5_000_000)
    a=ap.parse_args(argv)
    out=lambda obj: print(json.dumps(obj,ensure_ascii=False,indent=2))
    print(f"枢语5维语义空间容量: {CAP:,}  (核{NC}×映{NM}×态{NS}×标{NK}×相{NP})")
    if a.count: return
    if a.id>=0:
        out(decode_full(a.id)); return
    if a.word:
        nid=encode(a.word)
        out({"word":a.word,"id":nid,"verify":decode_full(nid) if nid>=0 else None}); return
    if a.han:
        nid=encode_han(a.han)
        out({"han":a.han,"id":nid,"verify":decode_full(nid) if nid>=0 else None}); return
    if a.search:
        out({"keyword":a.search,"hits":search(a.search)}); return
    if a.compose:
        try:
            out(compose(_parse_compose_arg(a.compose)))
        except ValueError as ex:
            print(json.dumps({"error":str(ex)},ensure_ascii=False)); sys.exit(2)
        return
    if a.analogy:
        try:
            out(analogy(*a.analogy))
        except (ValueError, TypeError) as ex:
            print(json.dumps({"error":str(ex)},ensure_ascii=False)); sys.exit(2)
        return
    if a.near:
        try:
            out({"word":a.near,"neighbors":near(a.near)})
        except (ValueError, TypeError) as ex:
            print(json.dumps({"error":str(ex)},ensure_ascii=False)); sys.exit(2)
        return
    if a.hold is not None and a.at >= 0:
        try:
            out(hold(a.hold, a.at, a.n))
        except (ValueError, TypeError) as ex:
            print(json.dumps({"error":str(ex)},ensure_ascii=False)); sys.exit(2)
        return
    if a.nestle is not None and a.at >= 0:
        try:
            out(nestle(a.nestle, a.at, a.n))
        except (ValueError, TypeError) as ex:
            print(json.dumps({"error":str(ex)},ensure_ascii=False)); sys.exit(2)
        return
    if a.incline is not None and a.at >= 0:
        try:
            out(incline(a.incline, a.at, a.n))
        except (ValueError, TypeError) as ex:
            print(json.dumps({"error":str(ex)},ensure_ascii=False)); sys.exit(2)
        return
    if a.gaze is not None and a.at >= 0:
        try:
            out(gaze(a.gaze, a.at, a.n))
        except (ValueError, TypeError) as ex:
            print(json.dumps({"error":str(ex)},ensure_ascii=False)); sys.exit(2)
        return
    if a.turn is not None and a.at >= 0:
        try:
            out(turn(a.turn, a.at, a.n))
        except (ValueError, TypeError) as ex:
            print(json.dumps({"error":str(ex)},ensure_ascii=False)); sys.exit(2)
        return
    if a.perch is not None and a.at >= 0:
        try:
            out(perch(a.perch, a.at, a.n))
        except (ValueError, TypeError) as ex:
            print(json.dumps({"error":str(ex)},ensure_ascii=False)); sys.exit(2)
        return
    if a.stir is not None and a.at >= 0:
        try:
            out(stir(a.stir, a.at, a.n))
        except (ValueError, TypeError) as ex:
            print(json.dumps({"error":str(ex)},ensure_ascii=False)); sys.exit(2)
        return
    if a.land is not None and a.at >= 0:
        try:
            out(land(a.land, a.at, a.n))
        except (ValueError, TypeError) as ex:
            print(json.dumps({"error":str(ex)},ensure_ascii=False)); sys.exit(2)
        return
    if a.sway is not None and a.at >= 0:
        try:
            out(sway(a.sway, a.at, a.n))
        except (ValueError, TypeError) as ex:
            print(json.dumps({"error":str(ex)},ensure_ascii=False)); sys.exit(2)
        return
    if a.echo is not None and a.at >= 0:
        try:
            out(echo(a.echo, a.at, a.n))
        except (ValueError, TypeError) as ex:
            print(json.dumps({"error":str(ex)},ensure_ascii=False)); sys.exit(2)
        return
    if a.trail is not None and a.at >= 0:
        try:
            out(trail(a.trail, a.at, a.n))
        except (ValueError, TypeError) as ex:
            print(json.dumps({"error":str(ex)},ensure_ascii=False)); sys.exit(2)
        return
    if a.at >= 0:
        try:
            out(pulse(a.pulse, a.at))
        except (ValueError, TypeError) as ex:
            print(json.dumps({"error":str(ex)},ensure_ascii=False)); sys.exit(2)
        return
    if a.coin is not None:
        out(auto_coin(a.coin)); return
    if a.sample>0:
        import random
        for _ in range(a.sample):
            n=random.randint(0,CAP-1)
            d=decode(n)
            print(f"#{n:>10}  {d['词']:<22} {d['汉']:<10} [{d['层']}]  {d['义']}")
        return
    if a.dump:
        limit=a.limit if a.limit>0 else CAP
        n=0; si=0; size=0
        fh=open(f"{a.dump}.{si:05d}.jsonl","w",encoding="utf-8")
        while n<limit:
            line=json.dumps(decode_full(n),ensure_ascii=False,separators=(",",":"))
            fh.write(line+"\n"); size+=len(line)+1; n+=1
            if n%a.shard==0:
                fh.close(); si+=1; fh=open(f"{a.dump}.{si:05d}.jsonl","w",encoding="utf-8")
                if n%50_000_000==0: print(f"  已生成 {n:,} 条 ~{size/1024/1024/1024:.1f}GB")
        fh.close()
        print(f"落盘完成 {n:,} 条 ~{size/1024/1024/1024:.2f}GB 分片{si+1}")

if __name__=="__main__": main()
