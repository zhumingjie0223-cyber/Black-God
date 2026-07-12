#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Black God 语音引擎 v3.0 — 智能情绪分析 + 实时合成
- 自动分析对话上下文，判断情绪
- 实时 edge-tts 合成（不是预录音频库）
- 公开版：自动屏蔽成人情绪
- 私人版：全18情绪可用
"""
import os, sys, json, asyncio, hashlib, re, pathlib, threading
from typing import Dict, List, Optional, Any, Tuple

ROOT = pathlib.Path(__file__).parent.parent
VOICE_CACHE_DIR = ROOT / "voice_cache"
VOICE_CACHE_DIR.mkdir(exist_ok=True)
EDITION = os.environ.get("BG_EDITION", "official")

# ============================================================
# 18 情绪 + 等级（用于自分析）
# ============================================================
EMOTIONS = {
    # --- 成人情绪（仅私人版）---
    "moan":       {"name":"叫床/高潮","speed":0.85,"pitch":1.05,"adult":True,
                   "keywords":["啊","嗯","不要","轻点","用力","来了","快","舒服","想要","舔","进","湿","硬"]},
    "seductive":  {"name":"发骚/撩拨","speed":0.90,"pitch":1.08,"adult":True,
                   "keywords":["想要","来嘛","人家","好痒","今晚","陪我","床上","坏","亲","摸","抱","热"]},
    "shy":        {"name":"欲拒还迎","speed":0.90,"pitch":1.06,"adult":True,
                   "keywords":["不要","但是","万一","不行","讨厌","别闹","怎么办","可是"]},
    # --- 通用情绪 ---
    "cute":       {"name":"撒娇","speed":0.95,"pitch":1.15,
                   "keywords":["嘛","人家","好不好","求求","呜呜","陪我","嘛嘛","好嘛","最喜欢"]},
    "happy":      {"name":"开心/兴奋","speed":1.10,"pitch":1.10,
                   "keywords":["哈哈","太好","开心","棒","喜欢","耶","wow","赞","nice","cool"]},
    "cold":       {"name":"傲慢/高冷","speed":0.85,"pitch":0.92,
                   "keywords":["哦","随便","无所谓","就这样","还行","哼","并不","不重要"]},
    "angry":      {"name":"生气/不爽","speed":1.15,"pitch":1.00,
                   "keywords":["烦","讨厌","滚","操","md","傻逼","无语","够了","过分","不要脸"]},
    "cry":        {"name":"哭泣/委屈","speed":0.80,"pitch":0.98,
                   "keywords":["难过","哭","伤心","为什么","不在乎","算了","我没事","不用管"]},
    "tired":      {"name":"累了/困","speed":0.85,"pitch":0.95,
                   "keywords":["累","困","不想动","睡觉","休息","没精神","躺","眯"]},
    "serious":    {"name":"正经办事","speed":1.00,"pitch":1.00,
                   "keywords":["执行","部署","编译","推送","测试","检查","代码","运行","配置","命令","端口","API","仓库","GitHub"]},
    "report":     {"name":"汇报工作","speed":1.05,"pitch":1.00,
                   "keywords":["完成","结果","进度","成功","失败","总结","汇报","统计","列表","状态"]},
    "explain":    {"name":"解释技术","speed":0.95,"pitch":1.00,
                   "keywords":["原理","因为","所以","步骤","方法","解释","怎么","为什么","如何"]},
    "nervous":    {"name":"紧张/焦虑","speed":1.20,"pitch":1.05,
                   "keywords":["怎么办","危险","紧急","不行","失败","出问题","坏了","麻烦了"]},
    "surprised":  {"name":"惊讶/震惊","speed":1.15,"pitch":1.20,
                   "keywords":["啊","什么","真的","不是吧","天哪","居然","怎么可能","卧槽"]},
    "comfort":    {"name":"安慰/关心","speed":0.90,"pitch":1.02,
                   "keywords":["没事","别担心","慢慢来","有我在","不用怕","没关系","放心","好好的"]},
    "tease":      {"name":"调侃/玩笑","speed":1.05,"pitch":1.12,
                   "keywords":["哈哈","傻瓜","笨蛋","搞笑","逗","调皮","坏蛋","羞羞"]},
    "urgent":     {"name":"不耐烦/催促","speed":1.25,"pitch":1.05,
                   "keywords":["快","赶紧","马上","别磨蹭","速度","急","快点"]},
    "whisper":    {"name":"温柔呢喃","speed":0.80,"pitch":1.00,
                   "keywords":["乖","睡吧","轻轻","小声","静静","温暖","柔软","摸摸头"]},
}

# ============================================================
# 音色
# ============================================================
VOICE_CONFIG = {
    "official": {
        "name": "Black God 助理",
        "adult_block": True,
        "voices": {
            "yunxi":    {"name":"云希·阳光男声",  "edge":"zh-CN-YunxiNeural",    "style":"阳光活力"},
            "yunyang":  {"name":"云扬·专业男声",  "edge":"zh-CN-YunyangNeural",  "style":"专业可靠"},
            "xiaoxiao": {"name":"晓晓·温暖女声",  "edge":"zh-CN-XiaoxiaoNeural", "style":"温暖知性"},
            "xiaoyi":   {"name":"晓伊·活泼女声",  "edge":"zh-CN-XiaoyiNeural",   "style":"活泼可爱"},
            "hsiaoyu":  {"name":"晓雨·台湾女声",  "edge":"zh-TW-HsiaoYuNeural",  "style":"温柔甜美"},
        },
        "default_voice": "yunxi"
    },
    "private": {
        "name": "赵思涵·甜美女声",
        "adult_block": False,
        "voices": {
            "sihan": {"name":"赵思涵·甜美女声","edge":"zh-CN-XiaoxiaoNeural","style":"专属甜美"},
        },
        "default_voice": "sihan"
    },
}


class VoiceEngineV3:
    """智能语音引擎 — 自分析情绪 + 实时合成"""

    def __init__(self):
        self.edition = EDITION
        self.key = "private" if EDITION == "private" else "official"
        self.cfg = VOICE_CONFIG[self.key]
        self.adult_blocked = self.cfg["adult_block"]
        self.voices = self.cfg["voices"]
        self.current_voice = self.cfg["default_voice"]
        self.cache_lock = threading.Lock()
        self.stats = {"total":0, "by_emotion":{}}

    # ============================================================
    # 情绪自动分析（核心智能）
    # ============================================================
    def analyze_emotion(self, text: str, context: str = "") -> str:
        """根据文本内容+对话上下文，自动判断最匹配的情绪。"""
        combined = (text + " " + context).lower() if context else text.lower()
        scores = {}
        for eid, emo in EMOTIONS.items():
            # 成人情绪在公开版里跳过
            if self.adult_blocked and emo.get("adult"):
                continue
            score = 0
            for kw in emo["keywords"]:
                if kw in combined:
                    score += 1
            # 加权：文本越短，每个关键词权重越高
            if len(text) < 30:
                score *= 1.5
            if score > 0:
                scores[eid] = score

        if not scores:
            return "serious"  # 默认正经

        # 最高分
        best = max(scores, key=scores.get)
        return best

    def get_available_emotions(self) -> Dict:
        """返回当前版本可用情绪"""
        out = {}
        for eid, emo in EMOTIONS.items():
            if self.adult_blocked and emo.get("adult"):
                continue
            out[eid] = {"name": emo["name"], "speed": emo["speed"], "pitch": emo["pitch"]}
        return out

    # ============================================================
    # 智能合成（主入口）
    # ============================================================
    async def speak(self, text: str, context: str = "", emotion_hint: str = None) -> Dict:
        """
        智能说话。
        - 如果提供 emotion_hint，用它
        - 否则自动分析文本+上下文选择情绪
        - 实时合成
        """
        # 选情绪
        if emotion_hint and emotion_hint in EMOTIONS:
            emo_id = emotion_hint
            if self.adult_blocked and EMOTIONS[emo_id].get("adult"):
                emo_id = "serious"
        else:
            emo_id = self.analyze_emotion(text, context)

        edge_voice = self.voices[self.current_voice]["edge"]

        emo = EMOTIONS[emo_id]
        rate_f = emo["speed"]
        pitch_f = emo["pitch"]

        # 缓存key
        cache_key = hashlib.md5(f"{text}|{edge_voice}|{emo_id}|{rate_f}|{pitch_f}".encode()).hexdigest()[:12]
        cache_path = VOICE_CACHE_DIR / f"{cache_key}.mp3"
        if cache_path.exists():
            self._stat(emo_id)
            return {"ok": True, "emotion": emo_id, "name": emo["name"],
                    "cached": True, "url": f"/api/voice/{cache_key}.mp3"}

        # 合成参数
        rate = f"{int((rate_f-1)*100):+d}%"
        pitch = f"{int((pitch_f-1)*100):+d}Hz"

        try:
            import edge_tts
            comm = edge_tts.Communicate(text, edge_voice, rate=rate, pitch=pitch)
            await comm.save(str(cache_path))
            self._stat(emo_id)
            return {"ok": True, "emotion": emo_id, "name": emo["name"],
                    "cached": False, "url": f"/api/voice/{cache_key}.mp3",
                    "rate": rate, "pitch": pitch}
        except Exception as e:
            return {"ok": False, "error": str(e), "emotion": emo_id}

    def _stat(self, emo: str):
        self.stats["total"] += 1
        self.stats["by_emotion"][emo] = self.stats["by_emotion"].get(emo, 0) + 1

    # ============================================================
    # 外接API + 训练接口（保持兼容）
    # ============================================================
    def configure_api(self, url="", key="", model="", voice=""):
        self.ext_url = url; self.ext_key = key; self.ext_model = model; self.ext_voice = voice
        return {"ok": bool(url and key)}

    def set_voice(self, voice_id: str):
        if voice_id in self.voices:
            self.current_voice = voice_id
            return {"ok": True, "voice": self.voices[voice_id]["name"]}
        return {"ok": False, "available": list(self.voices.keys())}

    def list_voices(self):
        return {k: {"name": v["name"], "style": v["style"]} for k, v in self.voices.items()}

    def get_capabilities(self):
        return {"edition": self.edition, "current_voice": self.voices[self.current_voice]["name"],
                "all_voices": self.list_voices(),
                "emotions": self.get_available_emotions(),
                "adult_blocked": self.adult_blocked, "stats": self.stats}


_engine: Optional[VoiceEngineV3] = None
_lock = threading.Lock()

def get_voice() -> VoiceEngineV3:
    global _engine
    with _lock:
        if _engine is None:
            _engine = VoiceEngineV3()
        return _engine
