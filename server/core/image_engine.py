#!/usr/bin/env python3
"""Black God 生图引擎 — Pollinations.ai 免费无审查"""
import urllib.request, urllib.parse, json, os, hashlib, pathlib, threading
from typing import Dict, Optional

CACHE = pathlib.Path(__file__).parent.parent / "generated_images"
CACHE.mkdir(exist_ok=True)

POLLINATIONS = "https://image.pollinations.ai/prompt/{prompt}?width={w}&height={h}&nologo=true&seed={seed}&enhance=true"

class ImageEngine:
    def __init__(self):
        self.stats = {"total":0, "cached":0}

    def generate(self, prompt: str, width=768, height=1024, seed=None, style="raw") -> Dict:
        """生成图片 — 免费无审查"""
        if seed is None:
            seed = hash(prompt) % 9999 + 1

        # 缓存
        cache_key = hashlib.md5(f"{prompt}|{width}|{height}|{seed}".encode()).hexdigest()[:12]
        cache_path = CACHE / f"{cache_key}.jpg"
        if cache_path.exists():
            self.stats["cached"] += 1
            return {"ok": True, "cached": True, "url": f"/api/images/{cache_key}.jpg"}

        try:
            encoded = urllib.parse.quote(prompt)
            url = POLLINATIONS.format(prompt=encoded, w=width, h=height, seed=seed)
            req = urllib.request.Request(url, headers={"User-Agent": "BlackGod/3.0"})
            with urllib.request.urlopen(req, timeout=60) as resp:
                cache_path.write_bytes(resp.read())
            self.stats["total"] += 1
            return {"ok": True, "cached": False, "url": f"/api/images/{cache_key}.jpg",
                    "seed": seed, "size": cache_path.stat().st_size}
        except Exception as e:
            return {"ok": False, "error": str(e)}

    def generate_batch(self, prompt: str, count=3, width=768, height=1024) -> list:
        results = []
        for i in range(count):
            results.append(self.generate(prompt, width, height, seed=i*7+11))
        return results

_engine = None
def get_image_engine():
    global _engine
    if _engine is None:
        _engine = ImageEngine()
    return _engine
