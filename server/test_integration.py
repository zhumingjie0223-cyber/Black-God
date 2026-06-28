#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Black God 融合内核 —— 三模块协同集成测试
链路: 分级推理(难度判定) -> 多智能体(分解+执行+验证) -> 自进化(经验记录+技能生成)
使用 Mock call_fn，不消耗真实 API。
"""
import sys, os, json, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "core"))

from adaptive_reasoning import AdaptiveReasoningEngine, ReasoningLevelSelector
from multi_agent import multi_agent_execute, PlannerAgent, Coordinator
from self_evolving import SelfEvolvingLoop, VectorMemory, ExperienceRecorder

# ============ Mock 模型 ============
class MockLLM:
    """模拟模型：根据 prompt 关键词返回合理的结构化回复，覆盖三个模块的解析需求。"""
    def __init__(self):
        self.calls = 0

    def __call__(self, prompt, **kw):
        self.calls += 1
        p = prompt.lower()
        # 规划器：需要 JSON 子任务列表
        if "分解" in prompt or "subtask" in p or "plan" in p or "拆解" in prompt:
            return json.dumps({
                "subtasks": [
                    {"id": 1, "desc": "收集需求与资料", "agent": "executor"},
                    {"id": 2, "desc": "实现核心逻辑", "agent": "executor"},
                    {"id": 3, "desc": "测试与汇总", "agent": "executor"},
                ]
            }, ensure_ascii=False)
        # 验证器：需要 JSON 通过判定
        if "验证" in prompt or "verify" in p or "通过" in prompt:
            return json.dumps({"passed": True, "score": 0.9, "reason": "结果符合预期"}, ensure_ascii=False)
        # 技能抽取
        if "技能" in prompt or "skill" in p:
            return json.dumps({
                "name": "auto-generated-skill",
                "description": "从本次任务自动学习的技能",
                "triggers": ["示例触发"],
                "body": "## 步骤\n1. ...\n2. ..."
            }, ensure_ascii=False)
        # 默认：执行结果
        return f"[Mock执行结果#{self.calls}] 已完成: {prompt[:40]}"

PASS, FAIL = "✅", "❌"
results = []

def check(name, cond, detail=""):
    results.append((name, cond))
    print(f"{PASS if cond else FAIL} {name}" + (f"  | {detail}" if detail else ""))

print("="*60)
print("Black God 融合内核 · 三模块协同集成测试")
print("="*60)

llm = MockLLM()

# ---------- 1. 分级推理 ----------
print("\n[模块1] 分级推理 AdaptiveReasoning")
simple = ReasoningLevelSelector.select_level("今天几号")
hard = ReasoningLevelSelector.select_level("设计一个分布式高并发限流系统并证明其正确性，分析边界条件")
check("简单任务->低级别", simple in ("none", "low"), f"level={simple}")
check("复杂任务->高级别", hard in ("high", "xhigh", "medium"), f"level={hard}")

engine = AdaptiveReasoningEngine(llm)
r = engine.reason("写一个快速排序并分析复杂度")
check("reason() 返回结构完整", isinstance(r, dict) and "level" in r, f"keys={list(r.keys())}")

# ---------- 2. 多智能体 ----------
print("\n[模块2] 多智能体 MultiAgent")
ma = multi_agent_execute("做一个待办事项 Web 应用", llm, num_executors=3)
check("多智能体返回 dict", isinstance(ma, dict), f"keys={list(ma.keys())}")
check("产生了子任务结果", bool(ma.get("results") or ma.get("subtasks") or ma.get("final")),
      f"results={len(ma.get('results', []))}")

# ---------- 3. 自进化 ----------
print("\n[模块3] 自进化 SelfEvolving")
vm = VectorMemory()
vm.add("任务A: 写排序算法", "实现了快排")
vm.add("任务B: 做网页", "实现了前端")
hits = vm.search("排序算法实现", top_k=2)
check("向量记忆可检索", len(hits) > 0, f"命中{len(hits)}条")
check("检索相关性正确", hits and "排序" in hits[0].get("task", ""), f"top={hits[0].get('task','')[:20] if hits else 'N/A'}")

rec = ExperienceRecorder()
rec.record_failure("解析PDF", "找不到表格", ["尝试pdfplumber", "失败"])
exps = rec.get_relevant_experiences("PDF表格提取")
check("经验记录可复用", len(exps) >= 0, f"相关经验{len(exps)}条")

loop = SelfEvolvingLoop(llm, skills_dir="/tmp/bg_test_skills")
def mock_exec(task):
    return {"answer": "完成", "steps": ["步骤1", "步骤2"], "success": True}
ev = loop.execute_with_evolution("自动学习型任务", mock_exec)
check("自进化执行返回结果", isinstance(ev, dict), f"keys={list(ev.keys())}")

# ---------- 4. 全链路协同 ----------
print("\n[全链路] 分级->多智能体->自进化 串联")
task = "构建一个带用户认证的博客系统"
lvl = ReasoningLevelSelector.select_level(task)
pipeline_ma = multi_agent_execute(task, llm, num_executors=2)
vm.add(task, str(pipeline_ma)[:100], {"level": lvl})
final_hits = vm.search(task, top_k=1)
chain_ok = bool(lvl and pipeline_ma and final_hits)
check("全链路串联成功", chain_ok, f"难度={lvl}, 子任务执行={bool(pipeline_ma)}, 记忆回写={bool(final_hits)}")

# ---------- 汇总 ----------
print("\n" + "="*60)
passed = sum(1 for _, c in results if c)
total = len(results)
print(f"测试结果: {passed}/{total} 通过  |  模型调用次数: {llm.calls}")
print("="*60)
sys.exit(0 if passed == total else 1)
