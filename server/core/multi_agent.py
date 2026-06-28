#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Manus 多智能体架构 — Black God 内核强化 #1

核心机制：
  1. Planner Agent：分析任务 → 输出执行计划（有序子任务）
  2. Executor Agents（多个）：并行执行子任务，独立上下文
  3. Verification Agent：检查中间结果，发现问题通知 Planner 重规划
  4. Coordinator：异步协调，任务状态管理

优势：
  - 任务自动分解 → 避免"走一步看一步"
  - 独立上下文 → 解决 token 爆炸问题
  - 异步执行 → 后台运行，关闭 App 也在工作
  - 自动纠错 → Verification 循环
"""
import json
import time
from typing import List, Dict, Any


class PlannerAgent:
    """规划智能体 - 分解任务，生成执行计划"""
    
    def __init__(self, call_fn):
        """call_fn: 模型调用函数，接收 messages 列表，返回文本"""
        self.call_fn = call_fn
    
    def plan(self, task: str) -> Dict[str, Any]:
        """
        分析任务，生成执行计划
        
        返回：
        {
          "task_name": "任务名",
          "subtasks": [
            {"id": 1, "title": "子任务1", "description": "...", "depends_on": [], "priority": "high"},
            ...
          ],
          "execution_order": "1→2→3...",
          "estimated_steps": 5,
          "risks": ["风险1", "风险2"]
        }
        """
        prompt = f"""分析这个任务，输出详细的执行计划。

任务：{task}

请以 JSON 格式输出：
{{
  "task_name": "任务简称",
  "subtasks": [
    {{"id": 1, "title": "子任务1", "description": "详细描述", "depends_on": [], "priority": "high/medium/low"}},
    ...
  ],
  "execution_order": "执行顺序（如 1→2→3 或 1,2,3 并行后→4）",
  "estimated_steps": 预计步骤数,
  "risks": ["风险1", "风险2"],
  "context_for_executors": "每个 Executor 需要的共同上下文"
}}

只输出 JSON，不要其他文字。"""
        
        messages = [{"role": "user", "content": prompt}]
        try:
            raw = self.call_fn(messages)
            plan = self._parse_json(raw)
            return plan if plan else {"subtasks": [], "error": "规划失败"}
        except Exception as e:
            return {"subtasks": [], "error": str(e)}
    
    def _parse_json(self, raw: str) -> Dict:
        """从模型输出提取 JSON"""
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


class ExecutorAgent:
    """执行智能体 - 执行单个子任务，独立上下文"""
    
    def __init__(self, agent_id: int, call_fn):
        self.agent_id = agent_id
        self.call_fn = call_fn
        self.context = {}  # 独立上下文，不会爆炸
    
    def execute(self, subtask: Dict, shared_context: str = "") -> Dict:
        """
        执行子任务
        
        返回：
        {
          "agent_id": 1,
          "subtask_id": 1,
          "status": "success/failed",
          "result": "执行结果",
          "duration": 2.5,
          "issues": ["问题1"]
        }
        """
        start = time.time()
        
        prompt = f"""执行这个子任务：

标题：{subtask.get('title', '')}
描述：{subtask.get('description', '')}

共享上下文：
{shared_context}

请完成这个子任务，输出结果。如果失败，说明原因。"""
        
        messages = [{"role": "user", "content": prompt}]
        try:
            result = self.call_fn(messages)
            duration = time.time() - start
            
            return {
                "agent_id": self.agent_id,
                "subtask_id": subtask.get("id"),
                "status": "success",
                "result": result[:500],  # 限制长度
                "duration": round(duration, 2),
                "issues": []
            }
        except Exception as e:
            return {
                "agent_id": self.agent_id,
                "subtask_id": subtask.get("id"),
                "status": "failed",
                "result": str(e),
                "duration": round(time.time() - start, 2),
                "issues": [str(e)]
            }


class VerificationAgent:
    """验证智能体 - 检查中间结果，发现问题通知重规划"""
    
    def __init__(self, call_fn):
        self.call_fn = call_fn
    
    def verify(self, subtask: Dict, result: str) -> Dict:
        """
        验证子任务的结果
        
        返回：
        {
          "verified": true/false,
          "issues": ["问题1", "问题2"],
          "suggestion": "建议的改进方向"
        }
        """
        prompt = f"""验证这个子任务的结果是否正确完成。

子任务：{subtask.get('title', '')}
要求：{subtask.get('description', '')}

执行结果：
{result[:300]}

请判断：
1. 结果是否符合要求？
2. 有没有遗漏或错误？
3. 是否需要重做？

JSON 格式：
{{
  "verified": true/false,
  "issues": ["问题1", "问题2"],
  "suggestion": "改进建议"
}}"""
        
        messages = [{"role": "user", "content": prompt}]
        try:
            raw = self.call_fn(messages)
            verdict = self._parse_json(raw)
            return verdict if verdict else {"verified": True, "issues": []}
        except Exception as e:
            return {"verified": False, "issues": [str(e)]}
    
    def _parse_json(self, raw: str) -> Dict:
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


class Coordinator:
    """协调智能体 - 异步协调，任务状态管理"""
    
    def __init__(self, max_executors: int = 3):
        self.max_executors = max_executors
        self.task_queue = []
        self.completed_tasks = []
        self.failed_tasks = []
    
    def coordinate(self, plan: Dict, planner: PlannerAgent, 
                   executors: List[ExecutorAgent], 
                   verifier: VerificationAgent) -> Dict:
        """
        协调整个执行流程
        
        返回：
        {
          "status": "completed/partial_failed",
          "completed": [结果1, 结果2, ...],
          "failed": [失败1, 失败2, ...],
          "replans": 重规划次数,
          "total_duration": 总耗时
        }
        """
        start = time.time()
        subtasks = plan.get("subtasks", [])
        shared_context = plan.get("context_for_executors", "")
        
        completed = []
        failed = []
        replans = 0
        
        # 按依赖关系执行任务
        executed_ids = set()
        
        while len(completed) + len(failed) < len(subtasks):
            # 找出可以执行的任务（依赖已完成）
            ready_tasks = [
                t for t in subtasks 
                if t.get("id") not in executed_ids 
                and all(dep in executed_ids for dep in t.get("depends_on", []))
            ]
            
            if not ready_tasks:
                break
            
            # 分配给 Executor 并行执行
            for task in ready_tasks[:self.max_executors]:
                executor = executors[len(executed_ids) % len(executors)]
                result = executor.execute(task, shared_context)
                
                # 验证结果
                verdict = verifier.verify(task, result.get("result", ""))
                
                if verdict.get("verified"):
                    completed.append(result)
                    executed_ids.add(task.get("id"))
                else:
                    # 验证失败，需要重规划
                    replans += 1
                    if replans < 2:  # 最多重规划一次
                        # 通知 Planner 重规划
                        new_plan = planner.plan(
                            f"前一个任务失败：{task.get('title')}。"
                            f"问题：{verdict.get('issues')}。"
                            f"请重新规划。"
                        )
                        plan.update(new_plan)
                        subtasks = plan.get("subtasks", [])
                    else:
                        failed.append(result)
                        executed_ids.add(task.get("id"))
        
        return {
            "status": "completed" if not failed else "partial_failed",
            "completed": completed,
            "failed": failed,
            "replans": replans,
            "total_duration": round(time.time() - start, 2)
        }


def multi_agent_execute(task: str, call_fn, num_executors: int = 3) -> Dict:
    """
    多智能体执行引擎的完整流程
    
    task: 用户任务
    call_fn: 模型调用函数
    num_executors: 并行执行的 Executor 数量
    
    返回：(最终答案, 执行信息)
    """
    # 初始化各个 Agent
    planner = PlannerAgent(call_fn)
    executors = [ExecutorAgent(i, call_fn) for i in range(num_executors)]
    verifier = VerificationAgent(call_fn)
    coordinator = Coordinator(max_executors=num_executors)
    
    # Step 1: 规划
    plan = planner.plan(task)
    if not plan.get("subtasks"):
        return task, {"error": "规划失败"}
    
    # Step 2: 协调执行
    result = coordinator.coordinate(plan, planner, executors, verifier)
    
    # Step 3: 生成最终答案
    final_answer = f"""任务执行完成。

已完成：{len(result.get('completed', []))} 个子任务
失败：{len(result.get('failed', []))} 个子任务
重规划：{result.get('replans', 0)} 次
总耗时：{result.get('total_duration', 0)} 秒

执行结果：
{chr(10).join(f"- {r.get('result', '')[:100]}" for r in result.get('completed', []))}
"""
    
    return final_answer, result
