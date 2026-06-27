#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Hermes 自进化循环 — Black God 内核强化 #3

核心机制：
  1. 成功任务 → 自动提取步骤 → 生成可复用技能
  2. 失败任务 → 分析失败原因 → 记录到经验库
  3. 向量记忆 → 历史任务向量化 → 新问题自动检索相似经验
  4. 用户模型 → 学到用户偏好和工作风格

优势：
  - Agent 越用越强（技能库不断扩张）
  - 新问题自动找相似经验（避免重复犯错）
  - 学到用户个人风格（个性化越来越强）
  - 完全本地化（无需云端，隐私安全）
"""
import json
import hashlib
import time
from typing import List, Dict, Any
from pathlib import Path


class SkillExtractor:
    """技能提取器 - 从成功任务提取可复用技能"""
    
    def __init__(self, call_fn):
        self.call_fn = call_fn
    
    def extract(self, task: str, execution_steps: List[str], 
                result: str) -> Dict[str, Any]:
        """
        从成功任务提取技能
        
        返回：
        {
          "skill_name": "技能名称",
          "description": "技能描述",
          "steps": ["步骤1", "步骤2"],
          "keywords": ["关键词1", "关键词2"],
          "success_rate": 0.95,
          "applicable_scenarios": "适用场景描述"
        }
        """
        prompt = f"""从这个成功的任务中提取一个可复用的技能。

任务：{task}

执行步骤：
{chr(10).join(f"- {s}" for s in execution_steps)}

最终结果：{result[:200]}

请生成一个技能定义，包括：
1. 技能名称（简洁，易于记忆）
2. 详细描述
3. 执行步骤（可复用的通用步骤）
4. 关键词（用于检索）
5. 适用场景

JSON 格式：
{{
  "skill_name": "技能名",
  "description": "详细描述",
  "steps": ["步骤1", "步骤2"],
  "keywords": ["关键词1"],
  "applicable_scenarios": "场景描述"
}}"""
        
        messages = [{"role": "user", "content": prompt}]
        try:
            raw = self.call_fn(messages)
            skill = _parse_json(raw)
            if skill:
                skill["success_rate"] = 1.0  # 初始成功率 100%
                skill["created_at"] = time.time()
                skill["usage_count"] = 0
            return skill
        except Exception as e:
            return None


class ExperienceRecorder:
    """经验记录器 - 记录失败经验，避免重复犯错"""
    
    def __init__(self):
        self.experiences = []
    
    def record_failure(self, task: str, error: str, 
                       attempted_steps: List[str]) -> Dict:
        """
        记录失败经验
        
        返回：
        {
          "id": "exp_xxx",
          "task": "任务",
          "error": "错误原因",
          "attempted_steps": ["步骤1"],
          "lesson": "学到的教训",
          "timestamp": 1234567890
        }
        """
        experience = {
            "id": f"exp_{hashlib.md5(task.encode()).hexdigest()[:8]}",
            "task": task,
            "error": error,
            "attempted_steps": attempted_steps,
            "timestamp": time.time(),
            "lesson": f"避免：{error}"
        }
        self.experiences.append(experience)
        return experience
    
    def get_relevant_experiences(self, task: str, top_k: int = 3) -> List[Dict]:
        """
        获取相关经验（基于关键词匹配）
        """
        task_words = set(task.lower().split())
        
        scored = []
        for exp in self.experiences:
            exp_words = set(exp["task"].lower().split())
            similarity = len(task_words & exp_words) / max(len(task_words), 1)
            if similarity > 0:
                scored.append((exp, similarity))
        
        scored.sort(key=lambda x: x[1], reverse=True)
        return [exp for exp, _ in scored[:top_k]]


class VectorMemory:
    """向量记忆 - 历史任务向量化存储和检索"""
    
    def __init__(self):
        self.memories = []
    
    def add(self, task: str, result: str, metadata: Dict = None):
        """
        添加任务到向量记忆
        
        实际应该用向量数据库（如 Pinecone/Weaviate），
        这里简化为关键词向量化
        """
        vector = self._simple_vectorize(task)
        
        memory = {
            "id": f"mem_{hashlib.md5(task.encode()).hexdigest()[:8]}",
            "task": task,
            "result": result[:200],
            "vector": vector,
            "metadata": metadata or {},
            "timestamp": time.time(),
            "access_count": 0
        }
        self.memories.append(memory)
    
    def search(self, query: str, top_k: int = 3) -> List[Dict]:
        """
        搜索相似的历史任务
        """
        query_vector = self._simple_vectorize(query)
        
        scored = []
        for mem in self.memories:
            similarity = self._cosine_similarity(query_vector, mem["vector"])
            if similarity > 0.3:  # 相似度阈值
                scored.append((mem, similarity))
        
        scored.sort(key=lambda x: x[1], reverse=True)
        
        # 更新访问计数
        for mem, _ in scored[:top_k]:
            mem["access_count"] += 1
        
        return [mem for mem, _ in scored[:top_k]]
    
    def _simple_vectorize(self, text: str) -> Dict[str, float]:
        """简化的向量化：关键词频率"""
        words = text.lower().split()
        vector = {}
        for word in words:
            if len(word) > 2:  # 过滤短词
                vector[word] = vector.get(word, 0) + 1
        return vector
    
    def _cosine_similarity(self, v1: Dict, v2: Dict) -> float:
        """计算余弦相似度"""
        if not v1 or not v2:
            return 0
        
        all_words = set(v1.keys()) | set(v2.keys())
        dot_product = sum(v1.get(w, 0) * v2.get(w, 0) for w in all_words)
        
        norm1 = sum(v**2 for v in v1.values()) ** 0.5
        norm2 = sum(v**2 for v in v2.values()) ** 0.5
        
        if norm1 == 0 or norm2 == 0:
            return 0
        
        return dot_product / (norm1 * norm2)


class UserModel:
    """用户模型 - 学到用户偏好和工作风格"""
    
    def __init__(self):
        self.preferences = {}
        self.interaction_history = []
    
    def learn_from_interaction(self, task: str, result: str, 
                               user_feedback: str = None):
        """
        从交互中学习用户偏好
        """
        interaction = {
            "task": task,
            "result": result[:100],
            "feedback": user_feedback,
            "timestamp": time.time()
        }
        self.interaction_history.append(interaction)
        
        # 简化的偏好学习：提取常见关键词
        words = task.lower().split()
        for word in words:
            if len(word) > 3:
                self.preferences[word] = self.preferences.get(word, 0) + 1
    
    def get_user_profile(self) -> Dict:
        """
        获取用户档案
        """
        if not self.preferences:
            return {}
        
        # 排序偏好
        sorted_prefs = sorted(
            self.preferences.items(),
            key=lambda x: x[1],
            reverse=True
        )
        
        return {
            "top_interests": [w for w, _ in sorted_prefs[:10]],
            "interaction_count": len(self.interaction_history),
            "learning_curve": self._calculate_learning_curve()
        }
    
    def _calculate_learning_curve(self) -> float:
        """计算学习曲线（简化）"""
        if len(self.interaction_history) < 2:
            return 0
        return min(1.0, len(self.interaction_history) / 100)


class SelfEvolvingLoop:
    """自进化循环 - 整合所有组件"""
    
    def __init__(self, call_fn, skills_dir: str = None):
        self.call_fn = call_fn
        self.skills_dir = Path(skills_dir) if skills_dir else Path("/tmp/black_god_skills")
        self.skills_dir.mkdir(exist_ok=True)
        
        self.skill_extractor = SkillExtractor(call_fn)
        self.experience_recorder = ExperienceRecorder()
        self.vector_memory = VectorMemory()
        self.user_model = UserModel()
        
        self.skill_library = {}  # 技能库（内存）
        self.load_skills()
    
    def execute_with_evolution(self, task: str, execute_fn) -> Dict:
        """
        执行任务并自动进化
        
        execute_fn: 执行函数，返回 (result, steps, success)
        
        返回：
        {
          "result": "执行结果",
          "success": true/false,
          "evolved": true/false,
          "new_skill": {"name": "..."},
          "relevant_experience": [...]
        }
        """
        # Step 1: 检索相关经验
        relevant_exp = self.experience_recorder.get_relevant_experiences(task)
        
        # Step 2: 执行任务
        try:
            result, steps, success = execute_fn(task)
        except Exception as e:
            # 失败：记录经验
            self.experience_recorder.record_failure(task, str(e), [])
            return {
                "result": str(e),
                "success": False,
                "evolved": False,
                "error": str(e)
            }
        
        # Step 3: 成功后的自进化
        evolved_skill = None
        if success:
            # 提取技能
            evolved_skill = self.skill_extractor.extract(task, steps, result)
            if evolved_skill:
                self.skill_library[evolved_skill["skill_name"]] = evolved_skill
                self.save_skill(evolved_skill)
            
            # 添加到向量记忆
            self.vector_memory.add(task, result, {"success": True})
            
            # 学习用户偏好
            self.user_model.learn_from_interaction(task, result)
        
        return {
            "result": result,
            "success": success,
            "evolved": evolved_skill is not None,
            "new_skill": evolved_skill,
            "relevant_experience": relevant_exp,
            "user_profile": self.user_model.get_user_profile()
        }
    
    def save_skill(self, skill: Dict):
        """保存技能到文件"""
        skill_file = self.skills_dir / f"{skill['skill_name']}.json"
        with open(skill_file, "w", encoding="utf-8") as f:
            json.dump(skill, f, ensure_ascii=False, indent=2)
    
    def load_skills(self):
        """从文件加载技能"""
        if self.skills_dir.exists():
            for skill_file in self.skills_dir.glob("*.json"):
                try:
                    with open(skill_file, "r", encoding="utf-8") as f:
                        skill = json.load(f)
                        self.skill_library[skill["skill_name"]] = skill
                except Exception:
                    pass


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
