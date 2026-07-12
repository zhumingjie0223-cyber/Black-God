#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
媒体生成引擎 — Black God 888
生图（文生图/图生图）+ 生视频 + 统一接口
"""
import json
import urllib.request
import urllib.parse
import time
import os
from pathlib import Path


class MediaEngine:
    """生图 + 生视频统一引擎"""

    def __init__(self, output_dir="/tmp/bg88_media"):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

    # ─── 生图 ───────────────────────────────
    def text_to_image(self, prompt: str, width=1024, height=1024, model="flux"):
        """
        文生图 — 用 Pollinations.ai（免费、无需 Key）
        生成合规的图像内容
        """
        encoded = urllib.parse.quote(prompt)
        seed = int(time.time()) % 100000
        url = (f"https://image.pollinations.ai/prompt/{encoded}"
               f"?width={width}&height={height}&seed={seed}&model={model}&nologo=true")
        out = self.output_dir / f"img_{seed}.jpg"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=120) as r:
                data = r.read()
            out.write_bytes(data)
            return {"success": True, "path": str(out), "url": url, "prompt": prompt}
        except Exception as e:
            return {"success": False, "error": str(e), "url": url}

    def image_to_image(self, prompt: str, source_image: str, strength=0.7):
        """图生图 — 基于源图改"""
        # Pollinations 支持 image 参数做参考
        encoded = urllib.parse.quote(prompt)
        seed = int(time.time()) % 100000
        img_param = urllib.parse.quote(source_image) if source_image.startswith("http") else ""
        url = (f"https://image.pollinations.ai/prompt/{encoded}"
               f"?width=1024&height=1024&seed={seed}&model=flux&nologo=true")
        if img_param:
            url += f"&image={img_param}"
        out = self.output_dir / f"i2i_{seed}.jpg"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=120) as r:
                out.write_bytes(r.read())
            return {"success": True, "path": str(out), "url": url}
        except Exception as e:
            return {"success": False, "error": str(e)}

    # ─── 生视频 ─────────────────────────────
    def text_to_video(self, prompt: str, provider="local_ffmpeg"):
        """
        文生视频
        provider:
          - local_ffmpeg: 用生成的图片+ffmpeg合成动态视频（无依赖兜底）
          - api: 接外部视频生成API（需配置Key）
        """
        if provider == "api":
            return self._video_via_api(prompt)
        # 兜底：生成关键帧图 → ffmpeg 合成带运镜的视频
        return self._video_via_frames(prompt)

    def _video_via_frames(self, prompt: str, num_frames=4):
        """生成多帧图 → ffmpeg 合成视频（Ken Burns 运镜）"""
        frames = []
        for i in range(num_frames):
            r = self.text_to_image(f"{prompt}, cinematic frame {i+1}", model="flux")
            if r["success"]:
                frames.append(r["path"])
            time.sleep(0.5)
        if not frames:
            return {"success": False, "error": "帧生成失败"}
        # ffmpeg 合成
        seed = int(time.time()) % 100000
        out = self.output_dir / f"vid_{seed}.mp4"
        list_file = self.output_dir / f"frames_{seed}.txt"
        list_file.write_text("\n".join(f"file '{f}'\nduration 1.5" for f in frames))
        cmd = (f"ffmpeg -y -f concat -safe 0 -i {list_file} "
               f"-vf 'scale=1024:1024,zoompan=z=1.1:d=45' -pix_fmt yuv420p {out} 2>/dev/null")
        os.system(cmd)
        if out.exists():
            return {"success": True, "path": str(out), "frames": len(frames)}
        return {"success": False, "error": "ffmpeg合成失败", "frames": frames}

    def _video_via_api(self, prompt: str):
        """预留：接入外部视频生成API（如可灵/Runway/即梦）"""
        return {"success": False, "error": "API视频生成需配置Key", "todo": True}


# Agent 工具注册
def gen_image_tool(args, **kw):
    eng = MediaEngine()
    r = eng.text_to_image(args.get("prompt", ""),
                          width=args.get("width", 1024),
                          height=args.get("height", 1024))
    return f"图片已生成: {r['path']}" if r["success"] else f"失败: {r['error']}"

def gen_video_tool(args, **kw):
    eng = MediaEngine()
    r = eng.text_to_video(args.get("prompt", ""))
    return f"视频已生成: {r['path']}" if r["success"] else f"失败: {r.get('error')}"
