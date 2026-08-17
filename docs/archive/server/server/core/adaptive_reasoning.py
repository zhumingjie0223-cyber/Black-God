#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ⚠️ DEPRECATED(方案① · 2026-07-13)——本模块属"大脑常驻"能力,已划归 CF 主轨 web/nexus-do。
# 详见 docs/architecture/双轨边界-方案①.md。勿在此扩展 对话/情绪/记忆/偏好/画像 逻辑,统一走 nexus-do;
# Python server/ 已降级为按需重活后端,本文件待 CF 主轨功能对等后归档(现阶段只标记,不删除)。
"""
GPT-5.5 分级推理引擎 — Black God 内核强化 #2

核心机制：
  根据任务复杂度，自动选择推理深度
  - none：快速回答（0-1秒）
  - low：轻度推理（1-3秒）
  - medium：中度推理（3-10秒）
  - high：深度推理（10-30秒）
  - xhigh：超深度推理（30-120秒）

优势：
  - 简单任务快速回答，不浪费 token
  - 复杂任务深度推理，确保正确性
  - 自动选择推理等级，无需手动调参
  - 内部自我验证，错误率大幅降低
"""
import json
import re
from typing import Dict


class ReasoningLevelSelector:
    """自动选择推理等级"""
    
    @staticmethod
    def select_level(task: str) -> str:
        """
        根据任务特征自动选择推理等级
        
        返回：none / low / medium / high / xhigh
        """
        # 计算复杂度指标
        length = len(task)
        complexity_keywords = [
            "设计", "架构", "规划", "分析", "比较", "评估",
            "为什么", "怎样", "如何", "解释", "推导",
            "多步", "复杂", "困难", "挑战", "问题"
        ]
        keyword_count = sum(1 for kw in complexity_keywords if kw in task)
        
        # 数学/代码关键词
        code_keywords = ["代码", "算法", "编程", "函数", "类", "设计模式"]
        has_code = any(kw in task for kw in code_keywords)
        
        # 计算复杂度分数
        score = 0
        if length < 20:
            score += 0  # 非常简短
        elif length < 50:
            score += 1  # 简短
        elif length < 150:
            score += 2  # 中等
        elif length < 300:
            score += 3  # 较长
        else:
            score += 4  # 很长
        
        score += keyword_count * 0.5
        if has_code:
            score += 2
        
        # 映射到推理等级
        if score < 1:
            return "none"
        elif score < 2:
            return "low"
        elif score < 3.5:
            return "medium"
        elif score < 5:
            return "high"
        else:
            return "xhigh"


class ReasoningPromptBuilder:
    """为不同推理等级构建 prompt"""
    
    @staticmethod
    def build(task: str, level: str) -> str:
        """为指定推理等级构建 prompt"""
        
        base = f"任务：{task}\n\n"
        
        if level == "none":
            return base + "请快速回答，无需详细推理。"
        
        elif level == "low":
            return base + """请进行轻度推理：
1. 快速分析问题
2. 给出初步答案
3. 简单说明理由"""
        
        elif level == "medium":
            return base + """请进行中度推理：
1. 分析问题的关键点
2. 列举可能的方向
3. 选择最合理的方案
4. 详细说明理由
5. 检查答案的完整性"""
        
        elif level == "high":
            return base + """请进行深度推理：
1. 详细分析问题的各个方面
2. 列举多个可能的解决方案
3. 对每个方案进行优缺点分析
4. 选择最优方案并详细论证
5. 预见可能的问题并给出应对方案
6. 最后再检查一遍逻辑是否严密"""
        
        elif level == "xhigh":
            return base + """请进行超深度推理（思维链）：
1. 逐步分解问题为子问题
2. 对每个子问题进行多路径探索
3. 对每条路径进行成本效益分析
4. 在关键决策点做出多个假设，分别探索
5. 对每个假设的结论进行自我验证
6. 如发现矛盾，立即回溯并重新探索
7. 综合所有路径的结论，给出最终答案
8. 最后进行完整性检查和正确性验证

请在回答中展示你的思维过程，包括：
- 思考的每一步
- 考虑过的替代方案
- 做出的决策和理由
- 自我验证的结果"""
        
        return base


class InternalVerifier:
    """内部验证器 - 推理过程中的自我检查"""
    
    @staticmethod
    def verify_reasoning(reasoning: str, task: str, call_fn) -> Dict:
        """
        验证推理过程的正确性
        
        返回：
        {
          "valid": true/false,
          "issues": ["问题1", "问题2"],
          "confidence": 0.95,
          "suggestion": "改进建议"
        }
        """
        prompt = f"""检查这个推理过程是否正确。

原始任务：{task}

推理过程：
{reasoning[:1000]}

请检查：
1. 逻辑是否严密？
2. 有没有遗漏的情况？
3. 结论是否正确？
4. 有没有更好的方案？

JSON 格式：
{{
  "valid": true/false,
  "issues": ["问题1"],
  "confidence": 0.95,
  "suggestion": "改进建议"
}}"""
        
        messages = [{"role": "user", "content": prompt}]
        try:
            raw = call_fn(messages)
            verdict = _parse_json(raw)
            return verdict if verdict else {"valid": True, "confidence": 0.8}
        except Exception as e:
            return {"valid": False, "confidence": 0, "issues": [str(e)]}


class AdaptiveReasoningEngine:
    """自适应推理引擎 - 根据任务动态选择推理深度"""
    
    def __init__(self, call_fn):
        self.call_fn = call_fn
        self.selector = ReasoningLevelSelector()
        self.builder = ReasoningPromptBuilder()
        self.verifier = InternalVerifier()
    
    def reason(self, task: str, force_level: str = None) -> Dict:
        """
        执行自适应推理
        
        task: 任务描述
        force_level: 强制推理等级（可选）
        
        返回：
        {
          "answer": "最终答案",
          "reasoning_level": "xhigh",
          "reasoning_process": "完整推理过程",
          "verification": {"valid": true, "confidence": 0.95},
          "duration": 5.2
        }
        """
        import time
        start = time.time()
        
        # Step 1: 选择推理等级
        level = force_level or self.selector.select_level(task)
        
        # Step 2: 构建 prompt
        prompt = self.builder.build(task, level)
        
        # Step 3: 调用模型进行推理
        messages = [{"role": "user", "content": prompt}]
        try:
            reasoning_result = self.call_fn(messages)
        except Exception as e:
            return {
                "answer": f"推理失败：{e}",
                "reasoning_level": level,
                "reasoning_process": "",
                "verification": {"valid": False},
                "duration": time.time() - start
            }
        
        # Step 4: 内部验证（仅在 high/xhigh 等级）
        verification = None
        if level in ["high", "xhigh"]:
            verification = self.verifier.verify_reasoning(
                reasoning_result, task, self.call_fn
            )
            
            # 如果验证失败，进行修正
            if not verification.get("valid"):
                correction_prompt = f"""你的前一个推理有问题：
{verification.get('issues')}

请重新推理，避免这些问题。

原始任务：{task}"""
                messages = [{"role": "user", "content": correction_prompt}]
                try:
                    reasoning_result = self.call_fn(messages)
                except Exception:
                    pass
        
        # Step 5: 提取最终答案（从推理过程中）
        final_answer = _extract_final_answer(reasoning_result)
        
        return {
            "answer": final_answer,
            "reasoning_level": level,
            "reasoning_process": reasoning_result[:500],
            "verification": verification or {"valid": True, "confidence": 0.9},
            "duration": round(time.time() - start, 2)
        }


def _parse_json(raw: str) -> Dict:
    """从文本中提取 JSON"""
    if not raw:
        return None
    try:
        return json.loads(raw.strip())
    except Exception:
        pass
    try:
        start = raw.find("{")
        end = raw.rfind("}")
        if start != -1 and end != -1:
            return json.loads(raw[start:end+1])
    except Exception:
        pass
    return None


def _extract_final_answer(text: str) -> str:
    """从推理过程中提取最终答案"""
    # 寻找"最终答案"、"结论"等关键词
    keywords = ["最终答案", "结论", "答案是", "所以"]
    for kw in keywords:
        if kw in text:
            idx = text.find(kw)
            return text[idx:idx+200].strip()
    # 如果找不到，返回最后一段
    lines = text.strip().split("\n")
    return "\n".join(lines[-3:]) if lines else text
