#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Reflexion 自我反思模块 — Black God 思维强化引擎 #1

原理：模型给出答案后，再当一次"审稿人"批判自己的答案，
若发现问题则带着批判重做一次，显著提升复杂任务正确率。

设计原则：
  1. 零侵入：独立模块，run() 里只加一个调用点
  2. 可开关：通过 enable 参数控制，默认对"复杂任务"才触发（省 token）
  3. 防过度：最多反思 1 轮，避免无限循环和成本爆炸
  4. 快速跳过：简单任务/已明显正确的答案直接放行
"""
import json


# 判断是否值得反思：简单问候/极短答案不反思，省钱省时
SKIP_KEYWORDS = ("你好", "hi", "hello", "在吗", "谢谢", "几号", "几点", "天气")


def should_reflect(user_msg, answer, had_tools):
    """决定这次任务是否值得反思"""
    if not answer or len(answer) < 20:
        return False
    msg = (user_msg or "").strip().lower()
    # 简单寒暄类跳过
    if len(msg) < 8 and any(k in msg for k in SKIP_KEYWORDS):
        return False
    # 答案里出现不确定/出错信号 → 一定要反思
    uncertain = ("可能", "也许", "出错", "失败", "不确定", "无法", "error", "抱歉")
    if any(u in answer for u in uncertain):
        return True
    # 调用过工具的任务（有实际操作）→ 值得反思
    if had_tools:
        return True
    # 长答案（复杂问题）→ 值得反思
    if len(answer) > 200:
        return True
    return False


CRITIQUE_PROMPT = """你是一个严格的审稿人。请批判性审查下面这个回答是否真正解决了用户的问题。

用户问题：
{user_msg}

待审查的回答：
{answer}

请检查：
1. 是否真正回答了用户的问题？有没有答非所问？
2. 有没有事实错误、逻辑漏洞、遗漏的关键点？
3. 如果用到了工具结果，结论是否和结果一致？

只输出 JSON，格式如下，不要有其他文字：
{{"ok": true/false, "problems": "若有问题简述哪里不对，无问题留空", "hint": "若需重做，给出改进方向"}}"""


REDO_PROMPT = """你之前的回答经审查发现问题：
{problems}

改进方向：{hint}

请针对用户的原始问题，给出一个修正后的、更准确完整的回答。
用户原始问题：{user_msg}"""


def reflect(user_msg, answer, log, call_fn):
    """
    执行一轮反思。
    call_fn: 一个函数，接收 messages 列表，返回模型回复文本（复用 agent 的 call_openai）

    返回：(final_answer, reflection_info)
      reflection_info = {"reflected": bool, "ok": bool, "problems": str}
    """
    had_tools = bool(log)
    if not should_reflect(user_msg, answer, had_tools):
        return answer, {"reflected": False}

    # Step 1: 自我批判
    tool_summary = ""
    if log:
        tool_summary = "\n\n（参考：本任务调用过的工具结果）\n" + \
                       "\n".join(f"- {s.get('tool')}: {s.get('result','')[:100]}" for s in log[-3:])

    critique_msg = [
        {"role": "user", "content": CRITIQUE_PROMPT.format(
            user_msg=user_msg, answer=answer) + tool_summary}
    ]
    try:
        raw = call_fn(critique_msg)
    except Exception:
        return answer, {"reflected": False}

    # 解析批判结果
    verdict = _parse_verdict(raw)
    if verdict.get("ok", True):
        # 审查通过，原答案放行
        return answer, {"reflected": True, "ok": True, "problems": ""}

    # Step 2: 带着批判重做
    problems = verdict.get("problems", "回答可能不够准确")
    hint = verdict.get("hint", "请更仔细地回答")
    redo_msg = [
        {"role": "user", "content": REDO_PROMPT.format(
            problems=problems, hint=hint, user_msg=user_msg)}
    ]
    try:
        new_answer = call_fn(redo_msg)
        if new_answer and len(new_answer.strip()) > 10:
            return new_answer, {"reflected": True, "ok": False, "problems": problems}
    except Exception:
        pass

    return answer, {"reflected": True, "ok": False, "problems": problems}


def _parse_verdict(raw):
    """从模型输出里提取 JSON 判定，容错处理"""
    if not raw:
        return {"ok": True}
    # 尝试直接解析
    try:
        return json.loads(raw.strip())
    except Exception:
        pass
    # 尝试提取 {...} 片段
    try:
        start = raw.find("{")
        end = raw.rfind("}")
        if start != -1 and end != -1:
            return json.loads(raw[start:end+1])
    except Exception:
        pass
    # 解析失败：看关键词兜底
    low = raw.lower()
    if '"ok": false' in low or '"ok":false' in low or "不对" in raw or "错误" in raw:
        return {"ok": False, "problems": raw[:150], "hint": ""}
    return {"ok": True}
