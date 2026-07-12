#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Black God 语音引擎 v2.0
- 内置 TTS：edge-tts（免费，开箱即用）
- 外接 TTS：用户自填 API（OpenAI TTS / 火山 / 自建 GPT-SoVITS 等）
- 训练接口占位：后续接入 GPT-SoVITS / RVC / CosyVoice / ChatTTS / F5-TTS
- 18 种情绪标签
- 双版本：官方版（中性）/ 私人版（赵思涵）
"""
import os, sys, json, asyncio, hashlib, time, pathlib, threading, urllib.request, urllib.error
from typing import Dict, List, Optional, Any

ROOT = pathlib.Path(__file__).parent
VOICE_MODELS_DIR = ROOT / "voice_models"
VOICE_SAMPLES_DIR = ROOT / "voice_samples"
VOICE_CACHE_DIR = ROOT / "voice_cache"
for d in [VOICE_MODELS_DIR, VOICE_SAMPLES_DIR, VOICE_CACHE_DIR]:
    d.mkdir(exist_ok=True)

# ============================================================
# 版本配置 — 官方版 / 私人版
# ============================================================
EDITION = os.environ.get("BG_EDITION", "official")  # official | private

# ============================================================
# 18 种情绪标签
# ============================================================
EMOTIONS = {
    "moan":       {"name": "叫床/高潮",  "speed": 0.85, "pitch": 1.05},
    "seductive":  {"name": "发骚/撩拨",  "speed": 0.9,  "pitch": 1.08},
    "whisper":    {"name": "温柔呢喃",   "speed": 0.8,  "pitch": 1.0},
    "shy":        {"name": "欲拒还迎",   "speed": 0.9,  "pitch": 1.06},
    "cute":       {"name": "撒娇",      "speed": 0.95, "pitch": 1.15},
    "happy":      {"name": "开心/兴奋",  "speed": 1.1,  "pitch": 1.1},
    "cold":       {"name": "傲慢/高冷",  "speed": 0.85, "pitch": 0.92},
    "angry":      {"name": "生气/不爽",  "speed": 1.15, "pitch": 1.0},
    "cry":        {"name": "哭泣/委屈",  "speed": 0.8,  "pitch": 0.98},
    "tired":      {"name": "累了/困",    "speed": 0.85, "pitch": 0.95},
    "serious":    {"name": "正经办事",   "speed": 1.0,  "pitch": 1.0},
    "report":     {"name": "汇报工作",   "speed": 1.05, "pitch": 1.0},
    "explain":    {"name": "解释技术",   "speed": 0.95, "pitch": 1.0},
    "nervous":    {"name": "紧张/焦虑",  "speed": 1.2,  "pitch": 1.05},
    "surprised":  {"name": "惊讶/震惊",  "speed": 1.15, "pitch": 1.2},
    "comfort":    {"name": "安慰/关心",  "speed": 0.9,  "pitch": 1.02},
    "tease":      {"name": "调侃/玩笑",  "speed": 1.05, "pitch": 1.12},
    "urgent":     {"name": "不耐烦/催促","speed": 1.25, "pitch": 1.05},
}

# ============================================================
# 音色配置 — 官方版（中性）/ 私人版（赵思涵甜美女声）
# ============================================================
VOICES = {
    "official": {
        "name": "Black God 助理",
        "language": "zh-CN",
        "edge_voice": "zh-CN-YunxiNeural",       # 男声，中性专业
        "edge_styles": {
            "happy": "cheerful", "cold": "serious", "angry": "angry",
            "whisper": "gentle", "comfort": "gentle", "explain": "calm",
        },
        "emotions": list(EMOTIONS.keys()),
        "custom_model": None,
    },
    "private": {
        "name": "赵思涵（甜美女声）",
        "language": "zh-CN",
        "edge_voice": "zh-CN-XiaoxiaoNeural",     # 甜美女声
        "edge_styles": {
            "cute": "cheerful", "happy": "cheerful", "cold": "serious",
            "angry": "angry", "whisper": "gentle", "comfort": "gentle",
            "tease": "cheerful", "seductive": "cheerful", "moan": "gentle",
        },
        "emotions": list(EMOTIONS.keys()),
        "custom_model": None,
    },
}

# 私人版独有的情绪描述（官方版不暴露）
EMOTION_DETAILS_PRIVATE = {
    "moan": "喘息、颤音、失控感、呻吟",
    "seductive": "暧昧勾引、嗲声挑逗",
    "shy": "假推开但语气软",
}


class VoiceEngine:
    """统一语音引擎"""

    def __init__(self):
        self.edition = EDITION
        self.voice_key = "private" if EDITION == "private" else "official"
        self.voice_cfg = VOICES[self.voice_key]
        self.backend = self._detect_backend()
        self.cache_lock = threading.Lock()
        self.stats = {"total_calls": 0, "total_seconds": 0.0,
                       "by_emotion": {e: 0 for e in EMOTIONS}}
        # 外接 API 配置（用户自行填写）
        self.external_api = {
            "enabled": False,
            "url": "",        # 例: https://api.openai.com/v1/audio/speech
            "key": "",        # 用户 API Key
            "model": "",      # 例: tts-1, cosyvoice, gpt-sovits
            "voice": "",      # 例: alloy, nova, sihan
        }

    def _detect_backend(self) -> str:
        try:
            import edge_tts
            return "edge-tts"
        except ImportError:
            pass
        try:
            import pyttsx3
            return "pyttsx3"
        except ImportError:
            pass
        return "mock"

    # ============================================================
    # 能力查询
    # ============================================================
    def get_capabilities(self) -> Dict[str, Any]:
        emotions_out = {}
        for k, v in EMOTIONS.items():
            entry = {"name": v["name"], "speed": v["speed"], "pitch": v["pitch"]}
            if self.edition == "private" and k in EMOTION_DETAILS_PRIVATE:
                entry["desc"] = EMOTION_DETAILS_PRIVATE[k]
            emotions_out[k] = entry
        return {
            "edition": self.edition,
            "backend": self.backend,
            "voice": self.voice_cfg["name"],
            "emotions": emotions_out,
            "models_loaded": self._list_models(),
            "external_api": {"enabled": self.external_api["enabled"],
                             "url": self.external_api["url"] or None,
                             "model": self.external_api["model"] or None},
            "stats": self.stats,
        }

    def _list_models(self) -> List[Dict[str, Any]]:
        models = []
        for pattern in ["*.pth", "*.onnx", "*.pt", "*.ckpt"]:
            for p in VOICE_MODELS_DIR.glob(pattern):
                models.append({"name": p.stem, "size_mb": round(p.stat().st_size/1048576, 2),
                               "format": p.suffix.lstrip(".")})
        return models

    # ============================================================
    # 外接 API 配置
    # ============================================================
    def configure_external_api(self, url: str, key: str, model: str = "", voice: str = "") -> Dict:
        self.external_api["enabled"] = bool(url and key)
        self.external_api["url"] = url
        self.external_api["key"] = key
        self.external_api["model"] = model
        self.external_api["voice"] = voice
        return {"ok": True, "enabled": self.external_api["enabled"],
                "url": url, "model": model, "voice": voice}

    # ============================================================
    # 合成 — 统一入口
    # ============================================================
    async def synthesize(self, text: str, emotion: str = "serious",
                         voice: str = None, format: str = "mp3") -> Dict[str, Any]:
        if emotion not in EMOTIONS:
            emotion = "serious"
        emo = EMOTIONS[emotion]
        rate, pitch = emo["speed"], emo["pitch"]
        vk = voice or self.voice_key
        if vk not in VOICES:
            vk = self.voice_key
        vcfg = VOICES[vk]

        # 缓存
        key_str = f"{text}|{vk}|{emotion}|{rate}|{pitch}|{self.backend}|{self.external_api['enabled']}"
        key = hashlib.md5(key_str.encode()).hexdigest()[:16]
        cache_path = VOICE_CACHE_DIR / f"{key}.{format}"
        if cache_path.exists():
            self._update_stats(emotion, len(text) * 0.15 / rate)
            return {"ok": True, "cached": True, "path": str(cache_path),
                    "url": f"/api/voice/file/{key}.{format}", "emotion": emotion,
                    "voice": vcfg["name"], "duration": round(len(text)*0.15/rate, 2)}

        try:
            if self.external_api["enabled"]:
                meta = await self._synth_external(text, emotion, vcfg, rate, pitch, cache_path, format)
            elif self.backend == "edge-tts":
                meta = await self._synth_edge_tts(text, vcfg, emotion, rate, pitch, cache_path)
            elif self.backend == "pyttsx3":
                meta = self._synth_pyttsx3(text, vcfg, rate, pitch, cache_path)
            else:
                meta = self._synth_mock(text, rate, pitch, cache_path)
            self._update_stats(emotion, len(text) * 0.15 / rate)
            return {"ok": True, "cached": False, "path": str(cache_path),
                    "url": f"/api/voice/file/{key}.{format}", "emotion": emotion,
                    "voice": vcfg["name"], "duration": round(len(text)*0.15/rate, 2), **meta}
        except Exception as e:
            return {"ok": False, "error": str(e), "backend": self.backend}

    async def _synth_edge_tts(self, text, vcfg, emotion, rate, pitch, output_path) -> Dict:
        import edge_tts
        edge_voice = vcfg["edge_voice"]
        rate_str = f"{int((rate-1.0)*100):+d}%"
        pitch_str = f"{int((pitch-1.0)*100):+d}Hz"
        comm = edge_tts.Communicate(text, edge_voice, rate=rate_str, pitch=pitch_str)
        await comm.save(str(output_path))
        return {"backend": "edge-tts", "voice": edge_voice, "rate": rate_str, "pitch": pitch_str}

    def _synth_pyttsx3(self, text, vcfg, rate, pitch, output_path) -> Dict:
        import pyttsx3
        engine = pyttsx3.init()
        engine.setProperty("rate", int(150 * rate))
        engine.save_to_file(text, str(output_path))
        engine.runAndWait()
        return {"backend": "pyttsx3"}

    async def _synth_external(self, text, emotion, vcfg, rate, pitch, output_path, fmt) -> Dict:
        """外接 TTS API — OpenAI 兼容格式 / 自定义 POST"""
        api = self.external_api
        body = json.dumps({"model": api["model"] or "tts-1",
                            "input": text,
                            "voice": api["voice"] or "alloy",
                            "response_format": fmt,
                            "speed": rate}).encode("utf-8")
        req = urllib.request.Request(api["url"], data=body, method="POST")
        req.add_header("Content-Type", "application/json")
        req.add_header("Authorization", f"Bearer {api['key']}")
        try:
            resp = urllib.request.urlopen(req, timeout=30)
            output_path.write_bytes(resp.read())
            return {"backend": "external-api", "url": api["url"], "model": api["model"]}
        except urllib.error.HTTPError as e:
            return {"backend": "external-api", "error": f"HTTP {e.code}: {e.read().decode('utf-8', errors='replace')[:200]}"}

    def _synth_mock(self, text, rate, pitch, output_path) -> Dict:
        import wave, struct, math
        duration = max(1.0, len(text) * 0.15 / rate)
        sr = 16000
        n = int(duration * sr)
        freq = 440 * pitch
        with wave.open(str(output_path), "wb") as wf:
            wf.setnchannels(1); wf.setsampwidth(2); wf.setframerate(sr)
            for i in range(n):
                s = int(32767 * 0.3 * math.sin(2 * math.pi * freq * i / sr))
                wf.writeframes(struct.pack("<h", s))
        return {"backend": "mock", "note": "占位音频，请安装 edge-tts 或配置外接 API"}

    def _update_stats(self, emotion, duration):
        self.stats["total_calls"] += 1
        self.stats["total_seconds"] += duration
        self.stats["by_emotion"][emotion] = self.stats["by_emotion"].get(emotion, 0) + 1

    # ============================================================
    # 训练接口（占位）— 后续接入 GPT-SoVITS / RVC / CosyVoice / ChatTTS / F5-TTS
    # ============================================================
    TRAINING_BACKENDS = {
        "gpt-sovits": {"name": "GPT-SoVITS", "min_samples": 10, "needs_gpu": True},
        "rvc":        {"name": "RVC",        "min_samples": 5,  "needs_gpu": True},
        "cosyvoice":  {"name": "CosyVoice",  "min_samples": 3,  "needs_gpu": True},
        "f5-tts":     {"name": "F5-TTS",     "min_samples": 1,  "needs_gpu": True},
        "chat-tts":   {"name": "ChatTTS",    "min_samples": 0,  "needs_gpu": False},
    }

    def train(self, backend: str = "gpt-sovits", emotion: str = None,
              samples_dir: str = "", model_name: str = "custom_voice",
              epochs: int = 100) -> Dict[str, Any]:
        """训练接口 — 占位，后续接入实际训练脚本"""
        if backend not in self.TRAINING_BACKENDS:
            return {"ok": False, "error": f"不支持的后端: {backend}，可选: {list(self.TRAINING_BACKENDS.keys())}"}
        cfg = self.TRAINING_BACKENDS[backend]
        if not samples_dir:
            return {"ok": False, "error": "请提供样本目录", "available_backends": self.TRAINING_BACKENDS}
        sp = pathlib.Path(samples_dir)
        if not sp.exists():
            return {"ok": False, "error": f"目录不存在: {samples_dir}"}
        files = list(sp.glob("*.wav")) + list(sp.glob("*.mp3"))
        if len(files) < cfg["min_samples"]:
            return {"ok": False, "error": f"样本不足: 需≥{cfg['min_samples']}，当前{len(files)}"}
        # TODO: 接入实际训练
        # from tools.gpt_sovits import train as sovits_train
        # sovits_train(samples_dir, model_name, epochs)
        return {"ok": True, "backend": backend, "model": model_name,
                "emotion": emotion, "samples": len(files), "epochs": epochs,
                "output": str(VOICE_MODELS_DIR / f"{model_name}.pth"),
                "status": "queued", "note": f"需在 GPU 环境执行 {cfg['name']} 训练"}

    def load_model(self, model_path: str) -> Dict[str, Any]:
        p = pathlib.Path(model_path)
        if not p.exists():
            return {"ok": False, "error": f"模型不存在: {model_path}"}
        return {"ok": True, "model": p.stem, "format": p.suffix,
                "size_mb": round(p.stat().st_size/1048576, 2), "status": "registered"}


# 单例
_engine: Optional[VoiceEngine] = None
_lock = threading.Lock()

def get_voice_engine() -> VoiceEngine:
    global _engine
    with _lock:
        if _engine is None:
            _engine = VoiceEngine()
        return _engine


if __name__ == "__main__":
    eng = get_voice_engine()
    print(json.dumps(eng.get_capabilities(), ensure_ascii=False, indent=2, default=str))
