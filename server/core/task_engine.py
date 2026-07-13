#!/usr/bin/env python3
# ⚠️ DEPRECATED(方案① · 2026-07-13)——本模块属"大脑常驻"能力,已划归 CF 主轨 web/nexus-do。
# 详见 docs/architecture/双轨边界-方案①.md。勿在此扩展 对话/情绪/记忆/偏好/画像 逻辑,统一走 nexus-do;
# Python server/ 已降级为按需重活后端,本文件待 CF 主轨功能对等后归档(现阶段只标记,不删除)。
"""
Black God 任务执行引擎
实现 plan → execute → verify → report 闭环
"""
import json
import time
from datetime import datetime
from pathlib import Path

class TaskEngine:
    def __init__(self):
        self.tasks_file = Path("/opt/bg-agent/memory/tasks.jsonl")
        self.tasks_file.parent.mkdir(exist_ok=True)
        
    def create_task(self, user_message):
        """创建任务"""
        task_id = f"task_{int(time.time())}"
        task = {
            "task_id": task_id,
            "title": user_message[:50],
            "status": "created",
            "user_message": user_message,
            "steps": [],
            "artifacts": [],
            "errors": [],
            "created_at": datetime.now().isoformat(),
            "updated_at": datetime.now().isoformat()
        }
        
        self._save_task(task)
        return task
    
    def plan(self, task):
        """生成执行计划"""
        task["status"] = "planning"
        task["updated_at"] = datetime.now().isoformat()
        
        # 分析意图
        intent = self._analyze_intent(task["user_message"])
        
        # 生成步骤
        steps = self._generate_steps(intent)
        
        task["intent"] = intent
        task["steps"] = steps
        task["status"] = "planned"
        
        self._save_task(task)
        return task
    
    def execute(self, task, agent_callback):
        """执行任务"""
        task["status"] = "running"
        task["updated_at"] = datetime.now().isoformat()
        
        for i, step in enumerate(task["steps"]):
            step["status"] = "running"
            step["started_at"] = datetime.now().isoformat()
            
            try:
                result = agent_callback(step)
                step["status"] = "completed"
                step["result"] = result
                step["completed_at"] = datetime.now().isoformat()
            except Exception as e:
                step["status"] = "failed"
                step["error"] = str(e)
                task["errors"].append({
                    "step": i,
                    "error": str(e),
                    "timestamp": datetime.now().isoformat()
                })
                break
        
        task["updated_at"] = datetime.now().isoformat()
        self._save_task(task)
        return task
    
    def verify(self, task):
        """验证任务结果"""
        task["status"] = "verifying"
        
        # 检查所有步骤是否完成
        all_completed = all(s.get("status") == "completed" for s in task["steps"])
        
        if all_completed:
            task["status"] = "completed"
            task["success"] = True
        else:
            task["status"] = "failed"
            task["success"] = False
        
        task["verified_at"] = datetime.now().isoformat()
        task["updated_at"] = datetime.now().isoformat()
        
        self._save_task(task)
        return task
    
    def report(self, task):
        """生成任务报告"""
        report = {
            "task_id": task["task_id"],
            "title": task["title"],
            "status": task["status"],
            "success": task.get("success", False),
            "steps_completed": sum(1 for s in task["steps"] if s.get("status") == "completed"),
            "steps_total": len(task["steps"]),
            "artifacts": task.get("artifacts", []),
            "errors": task.get("errors", []),
            "duration": self._calculate_duration(task)
        }
        
        return report
    
    def _analyze_intent(self, message):
        """分析用户意图"""
        msg_lower = message.lower()
        
        if any(k in msg_lower for k in ['代码', 'code', '写', 'write', '函数']):
            return "code_generation"
        elif any(k in msg_lower for k in ['搜索', 'search', '查', '找']):
            return "information_retrieval"
        elif any(k in msg_lower for k in ['设计', 'design', 'ui', '页面']):
            return "design_creation"
        elif any(k in msg_lower for k in ['分析', 'analysis', '统计', '数据']):
            return "data_analysis"
        else:
            return "general_task"
    
    def _generate_steps(self, intent):
        """根据意图生成步骤"""
        base_steps = [
            {"id": 1, "title": "分析需求", "status": "pending"},
            {"id": 2, "title": "选择工具", "status": "pending"},
            {"id": 3, "title": "执行任务", "status": "pending"},
            {"id": 4, "title": "验证结果", "status": "pending"}
        ]
        
        return base_steps
    
    def _calculate_duration(self, task):
        """计算任务时长"""
        try:
            created = datetime.fromisoformat(task["created_at"])
            updated = datetime.fromisoformat(task["updated_at"])
            return (updated - created).total_seconds()
        except:
            return 0
    
    def _save_task(self, task):
        """保存任务"""
        with open(self.tasks_file, "a", encoding="utf-8") as f:
            f.write(json.dumps(task, ensure_ascii=False) + "\n")
    
    def get_tasks(self, limit=20):
        """获取任务列表"""
        if not self.tasks_file.exists():
            return []
        
        tasks = []
        with open(self.tasks_file, "r", encoding="utf-8") as f:
            for line in f:
                try:
                    tasks.append(json.loads(line))
                except:
                    pass
        
        # 按时间倒序
        tasks.sort(key=lambda x: x.get("created_at", ""), reverse=True)
        return tasks[:limit]

if __name__ == "__main__":
    engine = TaskEngine()
    
    # 测试
    task = engine.create_task("用Python计算1到100的和")
    print(f"创建任务: {task['task_id']}")
    
    task = engine.plan(task)
    print(f"生成计划: {len(task['steps'])} 步")
    
    print("✓ 任务引擎测试通过")
