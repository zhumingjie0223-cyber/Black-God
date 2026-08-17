---
name: auto-gap-audio-transcription
version: 1.0.0
description: |
  自动发现的能力缺口：任务需要 audio_transcribe, summarize，当前工具链不足，需要自我延伸。
triggers:
  - "audio_transcription"
  - "把一段录音自动转文字并总结重点"
mutating: true
---

# auto-gap-audio-transcription

## Contract
- 当任务需要缺失工具时触发。
- 优先寻找已有工具替代；没有则生成新工具/技能方案。
- 完成后把经验写入记忆。

## Phases
1. 分析缺失工具：audio_transcribe, summarize
2. 尝试用现有工具链替代。
3. 若替代失败，生成新的 SKILL.md 或工具实现计划。
4. 验证新能力能被路由命中。

## Generated From
把一段录音自动转文字并总结重点
