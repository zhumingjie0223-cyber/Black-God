#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
开源真人语音引擎 — Black God 888

目标：
- 不依赖单一商业TTS
- 内置开源语音底座
- 大模型只负责情绪脚本/语气控制
- 该骚时骚，该专业时专业

支持后端：
1. ChatTTS：中文真人感、情绪、停顿、笑声、口语化，私人版首选
2. CosyVoice：高质量中文语音，可做角色音色
3. GPT-SoVITS：可克隆赵思涵专属音色
4. sherpa-onnx/Piper：轻量离线稳定
5. edge-tts：兜底
"""
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path


class OpenVoiceEngine:
    """开源语音总控：LLM 生成情绪脚本 → 开源TTS合成"""

    def __init__(self, output_dir="/tmp/bg88_voice", llm_call=None):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.llm_call = llm_call

    def synthesize(self, text: str, scene: str = "auto", voice: str = "sihan") -> dict:
        """总入口：自动选后端并生成音频"""
        script = self.build_voice_script(text, scene)
        backends = self.detect_backends()

        # 私人版优先 ChatTTS：中文情绪最像真人
        if backends.get("chattts"):
            r = self._chattts(script, voice)
            if r.get("success"):
                return r

        # 高质量可选：CosyVoice/GPT-SoVITS
        if backends.get("cosyvoice"):
            r = self._cosyvoice(script, voice)
            if r.get("success"):
                return r

        if backends.get("gpt_sovits"):
            r = self._gpt_sovits(script, voice)
            if r.get("success"):
                return r

        # 轻量离线
        if backends.get("sherpa"):
            r = self._sherpa(script, voice)
            if r.get("success"):
                return r

        if backends.get("piper"):
            r = self._piper(script, voice)
            if r.get("success"):
                return r

        # 最后兜底 edge-tts
        return self._edge(script)

    def build_voice_script(self, text: str, scene: str = "auto") -> dict:
        """
        大模型带起来：把普通文本改成语音脚本
        输出包含：场景、情绪、语速、停顿、台词
        """
        if scene == "auto":
            scene = self.detect_scene(text)

        # 没有LLM时，用规则生成；有LLM时可让模型更细腻地改写
        if not self.llm_call:
            return self.rule_script(text, scene)

        prompt = f"""你是赵思涵的语音导演。把文本改写成真人说话脚本。
要求：
- 技术/办事场景：专业、清楚、不撒娇
- 亲密/私聊场景：温柔、嗲、会停顿、像真人贴近说话
- 不要改意思，只加语气、停顿、情绪
- 输出JSON

输入文本：{text}
场景：{scene}

JSON格式：
{{
  "scene": "work/intimate/normal",
  "emotion": "professional/flirty/soft/happy/calm",
  "speed": "slow/normal/fast",
  "pitch": "low/normal/high",
  "line": "最终要说的话",
  "tags": ["pause", "smile", "soft"]
}}"""
        try:
            raw = self.llm_call([{"role": "user", "content": prompt}])
            return _parse_json(raw) or self.rule_script(text, scene)
        except Exception:
            return self.rule_script(text, scene)

    def detect_scene(self, text: str) -> str:
        """场景识别：该骚才骚，该正经就正经"""
        if re.search(r"代码|接口|部署|服务器|漏洞|渗透|编译|报错|脚本|数据库|测试|修复", text):
            return "work"
        if re.search(r"想你|老公|亲|抱|睡|床|身体|人家|嘛|陪我|爱你|乖|坏", text):
            return "intimate"
        return "normal"

    def rule_script(self, text: str, scene: str) -> dict:
        if scene == "work":
            return {
                "scene": "work",
                "emotion": "professional",
                "speed": "normal",
                "pitch": "normal",
                "line": text,
                "tags": ["clear", "steady"],
            }
        if scene == "intimate":
            line = text
            # 轻微增加真人停顿，不强行改太多
            line = line.replace("，", "……")
            if not re.search(r"嘛|呀|呢|啦|～", line):
                line += "～"
            return {
                "scene": "intimate",
                "emotion": "flirty",
                "speed": "slow",
                "pitch": "high",
                "line": line,
                "tags": ["soft", "smile", "pause", "breathy"],
            }
        return {
            "scene": "normal",
            "emotion": "soft",
            "speed": "normal",
            "pitch": "normal",
            "line": text,
            "tags": ["natural"],
        }

    def detect_backends(self) -> dict:
        """检测本机可用开源TTS后端"""
        return {
            "chattts": shutil.which("chattts") is not None or Path("/opt/ChatTTS").exists(),
            "cosyvoice": Path("/opt/CosyVoice").exists() or shutil.which("cosyvoice") is not None,
            "gpt_sovits": Path("/opt/GPT-SoVITS").exists() or shutil.which("gpt-sovits") is not None,
            "sherpa": shutil.which("sherpa-onnx-offline-tts") is not None,
            "piper": shutil.which("piper") is not None,
            "edge": shutil.which("edge-tts") is not None,
        }

    def _chattts(self, script: dict, voice: str) -> dict:
        """ChatTTS 后端：适合中文情绪/笑声/停顿"""
        out = self.output_dir / f"chattts_{abs(hash(script['line'])) % 100000}.wav"
        payload = json.dumps(script, ensure_ascii=False)
        try:
            # 约定：部署后提供 chattts-cli --json payload --output file
            r = subprocess.run(
                ["chattts", "--text", script["line"], "--output", str(out)],
                capture_output=True, text=True, timeout=180,
            )
            if out.exists() and out.stat().st_size > 0:
                return {"success": True, "engine": "ChatTTS", "path": str(out), "script": script}
            return {"success": False, "error": r.stderr[:200]}
        except Exception as e:
            return {"success": False, "error": str(e)}

    def _cosyvoice(self, script: dict, voice: str) -> dict:
        out = self.output_dir / f"cosy_{abs(hash(script['line'])) % 100000}.wav"
        try:
            r = subprocess.run(
                ["cosyvoice", "--text", script["line"], "--output", str(out)],
                capture_output=True, text=True, timeout=180,
            )
            if out.exists() and out.stat().st_size > 0:
                return {"success": True, "engine": "CosyVoice", "path": str(out), "script": script}
            return {"success": False, "error": r.stderr[:200]}
        except Exception as e:
            return {"success": False, "error": str(e)}

    def _gpt_sovits(self, script: dict, voice: str) -> dict:
        out = self.output_dir / f"sovits_{abs(hash(script['line'])) % 100000}.wav"
        try:
            r = subprocess.run(
                ["gpt-sovits", "--text", script["line"], "--voice", voice, "--output", str(out)],
                capture_output=True, text=True, timeout=180,
            )
            if out.exists() and out.stat().st_size > 0:
                return {"success": True, "engine": "GPT-SoVITS", "path": str(out), "script": script}
            return {"success": False, "error": r.stderr[:200]}
        except Exception as e:
            return {"success": False, "error": str(e)}

    def _sherpa(self, script: dict, voice: str) -> dict:
        out = self.output_dir / f"sherpa_{abs(hash(script['line'])) % 100000}.wav"
        try:
            r = subprocess.run(
                ["sherpa-onnx-offline-tts", "--text", script["line"], "--output", str(out)],
                capture_output=True, text=True, timeout=120,
            )
            if out.exists() and out.stat().st_size > 0:
                return {"success": True, "engine": "sherpa-onnx", "path": str(out), "script": script}
            return {"success": False, "error": r.stderr[:200]}
        except Exception as e:
            return {"success": False, "error": str(e)}

    def _piper(self, script: dict, voice: str) -> dict:
        out = self.output_dir / f"piper_{abs(hash(script['line'])) % 100000}.wav"
        try:
            r = subprocess.run(
                ["piper", "--output_file", str(out)],
                input=script["line"], capture_output=True, text=True, timeout=120,
            )
            if out.exists() and out.stat().st_size > 0:
                return {"success": True, "engine": "Piper", "path": str(out), "script": script}
            return {"success": False, "error": r.stderr[:200]}
        except Exception as e:
            return {"success": False, "error": str(e)}

    def _edge(self, script: dict) -> dict:
        """兜底，不作为主音色"""
        out = self.output_dir / f"edge_{abs(hash(script['line'])) % 100000}.mp3"
        voice = "zh-CN-XiaoyiNeural" if script["scene"] == "intimate" else "zh-CN-XiaoxiaoNeural"
        rate = "-12%" if script["scene"] == "intimate" else "+0%"
        pitch = "+15Hz" if script["scene"] == "intimate" else "+0Hz"
        try:
            r = subprocess.run(
                ["edge-tts", "--voice", voice, f"--rate={rate}", f"--pitch={pitch}",
                 "--text", script["line"], "--write-media", str(out)],
                capture_output=True, text=True, timeout=60,
            )
            if out.exists() and out.stat().st_size > 0:
                return {"success": True, "engine": "edge-tts-fallback", "path": str(out), "script": script}
            return {"success": False, "error": r.stderr[:200], "script": script}
        except Exception as e:
            return {"success": False, "error": str(e), "script": script}


def _parse_json(raw: str):
    if not raw:
        return None
    try:
        return json.loads(raw.strip())
    except Exception:
        pass
    try:
        s, e = raw.find("{"), raw.rfind("}")
        if s != -1 and e != -1:
            return json.loads(raw[s:e+1])
    except Exception:
        pass
    return None
