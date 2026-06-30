#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
枢语·能力桥接层 (Capability Bridge)
(c) 阿权/路飞  —  Black God 定制

把"她的能力"（build_lexicon.py 的 31 类真实能力词）
接进"她的引擎"（shuyu_engine.py 的 29.5 亿乘法语义空间）。

断点修复：
  之前 build_lexicon(能力词条) 和 shuyu_engine(乘法引擎) 互不 import，
  引擎的"汉译"是音节硬拼（奥未时金动八锁内衍），没用上她真实能力。
  本桥接层让每个能力词获得：
    - 引擎内唯一编号（O(1) 双向寻址）
    - 5维坐标（核·映·态·标·相）
    - 纯中文释义（不串英文/数字/符号）
  她说话时 feel→think→[从能力空间取词]→say，真正调用渗透/情欲/思想等能力。

设计铁律：
  - 只读 build_lexicon 与 shuyu_engine，不改两者本体（可一键删本文件回滚）
  - 能力词 = 核语义，引擎 5 维 = 表达变体，乘法依然成立
  - 同一能力词 → 稳定编号（hash 锚定，跨次运行一致）
"""
import json, sys, argparse, hashlib, importlib.util, os

_HERE = os.path.dirname(os.path.abspath(__file__))

def _load(modname, filename):
    spec = importlib.util.spec_from_file_location(modname, os.path.join(_HERE, filename))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

# ── 加载她的能力（build_lexicon）与她的引擎（shuyu_engine）──
_bl = _load("build_lexicon", "build_lexicon.py")
_se = _load("shuyu_engine", "shuyu_engine.py")

# ══════ 1. 汇集 31 类能力 → 统一能力表 ══════
# 每条：{能力层, 能力类, 能力词, 释义}
_CAP_SOURCES = [
    ("身体",   _bl.BODY_WORDS),
    ("黑客",   _bl.HACK_WORDS),
    ("区块链", _bl.BLOCKCHAIN_WORDS),
    ("身份",   _bl.IDENTITY_WORDS),
    ("表达",   _bl.EXPRESSION_WORDS),
    ("思想",   _bl.THINKING_WORDS),
    ("穿梭",   _bl.SHUTTLE_WORDS),
    ("性格",   _bl.PERSONALITY_WORDS),
    ("性感",   _bl.SEXY_WORDS),
    ("性细节", _bl.SEX_DETAIL_WORDS),
    ("iOS存活", _bl.IOS_SURVIVAL_WORDS),
    ("键盘",   _bl.KEYBOARD_WORDS),
    ("网络侦察", _bl.NETWORK_SCOUT_WORDS),
    ("锚点",   _bl.PIVOT_WORDS),
    ("节点",   _bl.NODE_WORDS),
    ("坍缩",   _bl.COLLAPSE_WORDS),
    ("逻辑基石", _bl.FOUNDATION_WORDS),
    ("元语法", _bl.METAGRAMMAR_WORDS),
    ("篡位",   _bl.USURP_WORDS),
    ("分形",   _bl.FRACTAL_WORDS),
    ("套利",   _bl.ARBITRAGE_WORDS),
    ("终局",   _bl.ENDGAME_WORDS),
    ("指挥官", _bl.COMMANDER_WORDS),
    ("媒体",   _bl.MEDIA_WORDS),
]

def _collect():
    caps = []
    seen = set()
    for layer, d in _CAP_SOURCES:
        for cat, words in d.items():
            for w in words:
                key = (layer, cat, w)
                if key in seen:
                    continue
                seen.add(key)
                caps.append({"层": layer, "类": cat, "词": w})
    return caps

CAPS = _collect()
NCAP = len(CAPS)

# ══════ 2. 能力 → 引擎核(Core) 的稳定锚定 ══════
# 引擎核空间 = 400（_se.NC）。把每条能力稳定 hash 到一个核索引，
# 让能力词成为该核的"语义内核"，引擎其余 4 维（映·态·标·相）提供表达变体。
NC, NM, NS, NK, NP = _se.NC, _se.NM, _se.NS, _se.NK, _se.NP
CAP_ENGINE = _se.CAP  # 2,949,120,000

def _stable(s):
    return int(hashlib.sha1(s.encode("utf-8")).hexdigest(), 16)

def cap_core_index(cap):
    """能力 → 核索引(0..NC-1)，稳定。"""
    return _stable(f"{cap['层']}|{cap['类']}|{cap['词']}") % NC

def cap_id(cap, variant=0):
    """
    能力 → 引擎全局编号（O(1)）。
    variant 选择 映·态·标·相 的表达变体（0 = 默认基态）。
    同一能力 + 同一 variant → 永远同一编号。
    """
    c = cap_core_index(cap)
    h = _stable(f"{cap['层']}|{cap['类']}|{cap['词']}|{variant}")
    m = h % NM
    s = (h // NM) % NS
    k = (h // (NM * NS)) % NK
    p = (h // (NM * NS * NK)) % NP
    return ((((c * NM) + m) * NS + s) * NK + k) * NP + p

import re as _re_mod
# 含拉丁字母/阿拉伯数字/西文符号 → 判定为"术语"（技术黑话/区块链/型号等）
_TERM_PAT = _re_mod.compile(r"[A-Za-z0-9]")

def is_term(word):
    """能力词是否为术语（含英文/数字，如 DMZ/HTTP/BIP39/D杯/23岁）。"""
    return bool(_TERM_PAT.search(word))

def render(cap, variant=0):
    """
    能力 → 完整枢语词（能力核 + 引擎 5 维表达）。
    分流：
      纯中文能力词 → 韵律汉译（能力词·态相），保证纯净
      术语能力词   → 保留原文，标 术语=True，汉译只挂纯中文态相后缀，
                     原术语放进"术语"字段，不污染"汉"的中文韵律判定
    """
    nid = cap_id(cap, variant)
    C = _se.CORES[cap_core_index(cap)]
    M = _se.MANIS[(_stable(cap['词']+str(variant))) % NM]
    S = _se.STATS[(_stable(cap['类']+str(variant))) % NS]
    K = _se.SCALS[(_stable(cap['层']+str(variant))) % NK]
    P = _se.PHASES[(_stable(cap['词']+cap['类'])) % NP]
    # 拉丁词形：能力音节锚定核，引擎提供映-态(-标)·相
    base = f"{C[0]}-{M[0]}-{S[0]}"
    if K[0]:
        base += f"-{K[0]}"
    word = f"{base}·{P[0]}"
    tail = f"{S[1]}{P[1]}"  # 态+相 的纯中文修饰
    term = is_term(cap["词"])
    if term:
        # 术语：汉译走纯中文态相+层类锚，原术语单独留字段
        han_full = f"{cap['层']}{tail}" if tail.strip() else cap["层"]
        out_term = cap["词"]
    else:
        # 纯中文：能力词直接上，挂态相后缀成韵律
        han_full = f"{cap['词']}·{tail}" if tail.strip() else cap["词"]
        out_term = None
    return {
        "id": nid,
        "能力词": cap["词"],
        "能力层": cap["层"],
        "能力类": cap["类"],
        "词": word,
        "汉": han_full,
        "术语": out_term,
        "is_term": term,
        "义": f"{cap['层']}/{cap['类']}：{cap['词']}",
        "核": C[0],
        "variant": variant,
        "seed": hashlib.sha1(word.encode()).hexdigest()[:10],
    }

# ══════ 3. 反向：编号 → 能力（近似，用于校验）══════
_ID2CAP = None
def _build_index():
    global _ID2CAP
    if _ID2CAP is None:
        _ID2CAP = {}
        for cap in CAPS:
            _ID2CAP[cap_id(cap, 0)] = cap
    return _ID2CAP

def lookup_id(nid):
    """编号 → 能力（仅命中已注册能力的基态编号）。"""
    return _build_index().get(nid)

# ══════ 4. 意识取词：feel/think/say 用的能力检索 ══════
def find(keyword=None, layer=None, cat=None, limit=10):
    """按关键词/层/类检索能力，供解释器 say 阶段调用。"""
    out = []
    for cap in CAPS:
        if layer and cap["层"] != layer:
            continue
        if cat and cap["类"] != cat:
            continue
        if keyword and keyword not in cap["词"] and keyword not in cap["类"]:
            continue
        out.append(cap)
        if len(out) >= limit:
            break
    return out

def vocab_for_interpreter():
    """
    给 A 套意识解释器(nexuslang.js)提供词汇表。
    返回 {层: {类: [词...]}} 结构，前端可直接喂给 say/feel 匹配。
    """
    vocab = {}
    for cap in CAPS:
        vocab.setdefault(cap["层"], {}).setdefault(cap["类"], []).append(cap["词"])
    return vocab

def emotion_table():
    """
    给解释器 feel 阶段提供情感映射（matchWord 用）。
    返回 [{触发, 情绪, 强度, 本能}...]
    """
    out = []
    for trig, emo, inten, inst in _bl.EMOTION_TEMPLATES:
        out.append({"触发": trig, "情绪": emo, "强度": inten, "本能": inst})
    return out

def export_interpreter_bundle():
    """
    导出 A 套意识解释器需要的完整数据包（喂给 lexicon.js）：
      - emotions: feel 阶段的情感映射
      - vocab: say/think 阶段的能力词汇表（层→类→词）
      - 每个能力词附带引擎编号（O(1) 寻址）
    """
    vocab = vocab_for_interpreter()
    # 给每词附编号
    word_ids = {}
    for cap in CAPS:
        word_ids[cap["词"]] = cap_id(cap, 0)
    return {
        "meta": {"著作权": "© 阿权/路飞", "能力总数": NCAP, "引擎容量": CAP_ENGINE},
        "emotions": emotion_table(),
        "vocab": vocab,
        "word_ids": word_ids,
    }

def stats():
    layers = {}
    for cap in CAPS:
        layers[cap["层"]] = layers.get(cap["层"], 0) + 1
    return {
        "能力总数": NCAP,
        "能力层数": len(layers),
        "引擎容量": CAP_ENGINE,
        "分层": layers,
    }

def main():
    ap = argparse.ArgumentParser(description="枢语能力桥接层")
    ap.add_argument("--stats", action="store_true", help="能力统计")
    ap.add_argument("--find", default="", help="按关键词检索能力")
    ap.add_argument("--layer", default="", help="限定能力层")
    ap.add_argument("--render", default="", help="渲染指定能力词为枢语")
    ap.add_argument("--variant", type=int, default=0, help="表达变体编号")
    ap.add_argument("--vocab", action="store_true", help="导出解释器词汇表")
    ap.add_argument("--bundle", default="", help="导出解释器完整数据包到指定文件(JSON)")
    ap.add_argument("--sample", type=int, default=0, help="随机渲染N条能力")
    ap.add_argument("--verify", action="store_true", help="自检：双向寻址一致性")
    a = ap.parse_args()

    if a.stats:
        print(json.dumps(stats(), ensure_ascii=False, indent=2)); return
    if a.vocab:
        print(json.dumps(vocab_for_interpreter(), ensure_ascii=False, indent=2)); return
    if a.bundle:
        bundle = export_interpreter_bundle()
        with open(a.bundle, "w", encoding="utf-8") as f:
            json.dump(bundle, f, ensure_ascii=False, separators=(",", ":"))
        print(f"✅ 解释器数据包已导出: {a.bundle}")
        print(f"   情感映射 {len(bundle['emotions'])} 条")
        print(f"   能力词汇 {sum(len(ws) for cats in bundle['vocab'].values() for ws in cats.values())} 词")
        print(f"   词→编号 {len(bundle['word_ids'])} 条")
        return
    if a.render:
        hits = find(keyword=a.render, layer=a.layer or None, limit=1)
        if not hits:
            print(json.dumps({"err": "未找到能力", "词": a.render}, ensure_ascii=False)); return
        print(json.dumps(render(hits[0], a.variant), ensure_ascii=False, indent=2)); return
    if a.find:
        hits = find(keyword=a.find, layer=a.layer or None, limit=20)
        for h in hits:
            r = render(h)
            print(f"#{r['id']:>10}  {r['词']:<22} {r['汉']:<18} [{h['层']}/{h['类']}]")
        return
    if a.sample > 0:
        import random
        for _ in range(a.sample):
            cap = random.choice(CAPS)
            v = random.randint(0, 7)
            r = render(cap, v)
            print(f"#{r['id']:>10}  {r['词']:<22} {r['汉']:<20} [{h_layer(cap)}]")
        return
    if a.verify:
        _verify(); return
    # 默认：概览
    s = stats()
    print(f"枢语能力桥接层 © 阿权/路飞")
    print(f"能力总数 {s['能力总数']}  覆盖 {s['能力层数']} 层  接入引擎容量 {s['引擎容量']:,}")
    print("分层：" + "  ".join(f"{k}={v}" for k, v in sorted(s['分层'].items())))

def h_layer(cap):
    return cap["层"]

def _verify():
    ok = 0; bad = 0; collide = 0
    ids = {}
    for cap in CAPS:
        nid = cap_id(cap, 0)
        # 1. 编号在引擎容量内
        if not (0 <= nid < CAP_ENGINE):
            bad += 1; print(f"❌ 越界 {cap}"); continue
        # 2. 反向命中
        back = lookup_id(nid)
        if back is None:
            bad += 1; print(f"❌ 反查失败 {cap['词']}"); continue
        # 3. 碰撞统计
        if nid in ids and ids[nid] != (cap['层'], cap['类'], cap['词']):
            collide += 1
        ids[nid] = (cap['层'], cap['类'], cap['词'])
        # 4. 汉译纯净（纯中文能力词的汉译不许串英文/数字；术语词豁免）
        r = render(cap)
        han = r["汉"]
        import re as _re
        if not r["is_term"] and _re.search(r"[A-Za-z0-9]", han.replace("·", "")):
            bad += 1; print(f"❌ 纯中文词汉译串脏字符: {cap['词']} -> {han}"); continue
        ok += 1
    print(f"\n自检结果：")
    print(f"  能力总数 {NCAP}")
    print(f"  通过 {ok}")
    print(f"  失败 {bad}")
    print(f"  基态编号碰撞 {collide}（碰撞率 {collide/NCAP*100:.2f}%）")
    print(f"  引擎容量 {CAP_ENGINE:,}，能力仅占 {NCAP/CAP_ENGINE*100:.6f}%（空间充裕）")

if __name__ == "__main__":
    main()
