#!/usr/bin/env python3
"""
Black God Optimizer - 10大核心能力
集成到 Black God Agent 的推理优化层
"""

import json
import hashlib
import sqlite3
import re
from pathlib import Path
from datetime import datetime
from collections import deque
from typing import Optional, Dict, List, Any

class BlackGodOptimizer:
    """Black God 内核优化器"""
    
    def __init__(self, db_dir: Path):
        self.cache_db = db_dir / "optimizer_cache.db"
        self.cache_db.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()
        
        # 能力1：多轮对话记忆（50条）
        self.conversation_history = deque(maxlen=50)
        
        # 能力4：学习的模式
        self.learned_patterns = {
            "coding": [],
            "analysis": [],
            "creative": [],
            "tool_use": [],
            "general": []
        }
        
        # 统计
        self.stats = {
            "total_requests": 0,
            "cache_hits": 0,
            "semantic_cache_hits": 0,
            "zero_cost_hits": 0,
            "strategy_fast": 0,
            "strategy_tool": 0,
            "strategy_standard": 0,
            "strategy_deep": 0,
            "strategy_decompose": 0
        }
    
    def _init_db(self):
        """初始化缓存数据库"""
        conn = sqlite3.connect(self.cache_db)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS cache (
                id INTEGER PRIMARY KEY,
                query_hash TEXT UNIQUE,
                query TEXT,
                response TEXT,
                complexity INTEGER,
                task_type TEXT,
                strategy TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                hit_count INTEGER DEFAULT 0
            )
        """)
        conn.commit()
        conn.close()
    
    # ========== 能力5：零成本规则 ==========
    def is_ultra_simple(self, user_input: str) -> bool:
        """零成本规则：极简单问题"""
        ultra_simple_patterns = [
            "什么是", "怎么", "如何", "区别", "定义",
            "是什么", "哪个", "用法", "例子", "意思"
        ]
        has_simple_keyword = any(p in user_input for p in ultra_simple_patterns)
        is_short = len(user_input) < 50
        return has_simple_keyword and is_short
    
    def analyze_complexity(self, user_input: str) -> int:
        """分析任务复杂度（1-10）"""
        if self.is_ultra_simple(user_input):
            return 1
        
        complexity = 5
        
        # 简单任务
        if any(kw in user_input for kw in ["什么是", "定义", "解释"]) and len(user_input) < 50:
            complexity = 2
        
        # 复杂任务
        if any(kw in user_input for kw in ["设计系统", "架构", "完整方案", "端到端"]):
            complexity = 9
        
        # 需要工具
        if any(kw in user_input for kw in ["执行", "运行", "查", "读取", "搜索"]):
            complexity = 6
        
        # 编程任务
        if any(kw in user_input for kw in ["代码", "写", "实现", "算法"]):
            complexity = 6
        
        # 长度影响
        if len(user_input) > 200:
            complexity = min(10, complexity + 2)
        
        return min(10, complexity)
    
    # ========== 能力9：多策略路由 ==========
    def select_strategy(self, complexity: int, task_type: str, task: str) -> Dict[str, Any]:
        """选择最优策略"""
        # 策略1：fast（简单任务）
        if complexity <= 3:
            self.stats["strategy_fast"] += 1
            return {
                "name": "fast",
                "thinking_budget": 0,
                "use_tools": False,
                "needs_decompose": False
            }
        
        # 策略2：tool_use（需要工具）
        if task_type == "tool_use" or any(kw in task for kw in ["执行", "运行", "查", "读取"]):
            self.stats["strategy_tool"] += 1
            return {
                "name": "tool_use",
                "thinking_budget": 2000,
                "use_tools": True,
                "needs_decompose": False
            }
        
        # 策略3：standard（中等任务）
        if complexity <= 5:
            self.stats["strategy_standard"] += 1
            return {
                "name": "standard",
                "thinking_budget": 2000,
                "use_tools": False,
                "needs_decompose": False
            }
        
        # 策略4：deep_thinking（复杂任务）
        if complexity <= 7:
            self.stats["strategy_deep"] += 1
            return {
                "name": "deep_thinking",
                "thinking_budget": 5000,
                "use_tools": False,
                "needs_decompose": False
            }
        
        # 策略5：decompose_thinking（极复杂任务）
        self.stats["strategy_decompose"] += 1
        return {
            "name": "decompose_thinking",
            "thinking_budget": 10000,
            "use_tools": False,
            "needs_decompose": True
        }
    
    # ========== 能力10：语义缓存 ==========
    def get_semantic_cache(self, query: str) -> Optional[str]:
        """语义缓存：相似问题自动命中"""
        # 1. 精确匹配
        query_hash = hashlib.md5(query.encode()).hexdigest()
        conn = sqlite3.connect(self.cache_db)
        cursor = conn.cursor()
        
        cursor.execute("SELECT response FROM cache WHERE query_hash=?", (query_hash,))
        result = cursor.fetchone()
        
        if result:
            cursor.execute("UPDATE cache SET hit_count=hit_count+1 WHERE query_hash=?", (query_hash,))
            conn.commit()
            conn.close()
            self.stats["cache_hits"] += 1
            return result[0]
        
        # 2. 语义相似匹配
        keywords = self._extract_keywords(query)
        if not keywords:
            conn.close()
            return None
        
        cursor.execute("SELECT query, response FROM cache ORDER BY hit_count DESC LIMIT 50")
        candidates = cursor.fetchall()
        conn.close()
        
        for cached_query, response in candidates:
            cached_keywords = self._extract_keywords(cached_query)
            similarity = self._calculate_similarity(keywords, cached_keywords)
            
            if similarity >= 0.6:
                self.stats["semantic_cache_hits"] += 1
                return response
        
        return None
    
    def _extract_keywords(self, text: str) -> set:
        """提取关键词"""
        # 提取英文单词
        english_words = re.findall(r'[a-zA-Z]+', text)
        keywords = {w.lower() for w in english_words}
        
        # 提取中文2字词
        chinese_text = re.sub(r'[a-zA-Z0-9\s]', '', text)
        stopwords = {"是", "的", "了", "和", "在", "有", "什么", "怎么", "如何"}
        
        for i in range(len(chinese_text) - 1):
            bigram = chinese_text[i:i+2]
            if bigram not in stopwords and len(bigram) == 2:
                keywords.add(bigram)
        
        return keywords
    
    def _calculate_similarity(self, kw1: set, kw2: set) -> float:
        """计算相似度（英文词优先）"""
        if not kw1 or not kw2:
            return 0.0
        
        # 提取英文核心词
        eng1 = {k for k in kw1 if k.isalpha() and k.isascii()}
        eng2 = {k for k in kw2 if k.isalpha() and k.isascii()}
        
        # 如果有英文词，只比较英文词
        if eng1 and eng2:
            if eng1 == eng2:
                return 1.0
            intersection = len(eng1 & eng2)
            union = len(eng1 | eng2)
            return intersection / union if union > 0 else 0.0
        
        # 否则比较全部词
        intersection = len(kw1 & kw2)
        union = len(kw1 | kw2)
        return intersection / union if union > 0 else 0.0
    
    def save_cache(self, query: str, response: str, complexity: int, task_type: str, strategy: str):
        """保存到缓存"""
        query_hash = hashlib.md5(query.encode()).hexdigest()
        conn = sqlite3.connect(self.cache_db)
        
        try:
            conn.execute("""
                INSERT INTO cache (query_hash, query, response, complexity, task_type, strategy)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (query_hash, query, response, complexity, task_type, strategy))
            conn.commit()
        except sqlite3.IntegrityError:
            pass
        
        conn.close()
    
    # ========== 能力3：智能任务分解 ==========
    def should_decompose(self, task: str) -> bool:
        """判断是否需要分解"""
        decompose_keywords = [
            "设计系统", "完整方案", "端到端", 
            "全流程", "架构", "从0到1", "整个"
        ]
        
        if any(kw in task for kw in decompose_keywords):
            return True
        
        if len(task) > 150:
            return True
        
        return False
    
    def decompose_task(self, task: str) -> List[str]:
        """分解任务"""
        if "设计系统" in task or "架构" in task:
            return [
                f"步骤1: 需求分析 - {task[:50]}",
                f"步骤2: 架构设计 - {task[:50]}",
                f"步骤3: 技术选型 - {task[:50]}",
                f"步骤4: 实现方案 - {task[:50]}"
            ]
        elif "完整" in task or "全流程" in task or "端到端" in task:
            return [
                f"第1阶段: {task[:60]}",
                f"第2阶段: {task[:60]}",
                f"第3阶段: {task[:60]}"
            ]
        else:
            mid = len(task) // 2
            return [
                f"前半部分: {task[:mid]}",
                f"后半部分: {task[mid:]}"
            ]
    
    # ========== 能力4：任务分类 ==========
    def categorize_task(self, task: str) -> str:
        """任务分类"""
        if any(kw in task.lower() for kw in ["代码", "python", "js", "算法", "实现", "编程"]):
            return "coding"
        elif any(kw in task for kw in ["分析", "数据", "统计", "对比", "评估"]):
            return "analysis"
        elif any(kw in task for kw in ["写", "创意", "设计", "文案", "故事"]):
            return "creative"
        elif any(kw in task for kw in ["执行", "运行", "查询", "读取", "搜索"]):
            return "tool_use"
        else:
            return "general"
    
    # ========== 核心优化入口 ==========
    def optimize_request(self, user_input: str) -> Dict[str, Any]:
        """
        核心优化入口
        返回：优化策略和元数据
        """
        self.stats["total_requests"] += 1
        
        # 1. 检查缓存（语义缓存）
        cached = self.get_semantic_cache(user_input)
        if cached:
            return {
                "cached": True,
                "response": cached,
                "strategy": "cache"
            }
        
        # 2. 分析复杂度
        complexity = self.analyze_complexity(user_input)
        
        # 3. 任务分类
        task_type = self.categorize_task(user_input)
        
        # 4. 选择策略
        strategy = self.select_strategy(complexity, task_type, user_input)
        
        # 5. 判断是否需要分解
        needs_decompose = strategy["needs_decompose"] or self.should_decompose(user_input)
        subtasks = self.decompose_task(user_input) if needs_decompose else None
        
        # 6. 零成本规则判断
        if complexity == 1:
            self.stats["zero_cost_hits"] += 1
        
        return {
            "cached": False,
            "complexity": complexity,
            "task_type": task_type,
            "strategy": strategy["name"],
            "thinking_budget": strategy["thinking_budget"],
            "use_tools": strategy["use_tools"],
            "needs_decompose": needs_decompose,
            "subtasks": subtasks
        }
    
    def post_process(self, user_input: str, response: str, metadata: Dict):
        """后处理：保存缓存"""
        self.save_cache(
            user_input,
            response,
            metadata.get("complexity", 5),
            metadata.get("task_type", "general"),
            metadata.get("strategy", "standard")
        )
    
    def get_stats(self) -> Dict[str, Any]:
        """获取统计信息"""
        cache_rate = (self.stats["cache_hits"] / self.stats["total_requests"] * 100) if self.stats["total_requests"] > 0 else 0
        semantic_rate = (self.stats["semantic_cache_hits"] / self.stats["total_requests"] * 100) if self.stats["total_requests"] > 0 else 0
        
        return {
            "total_requests": self.stats["total_requests"],
            "cache_hits": self.stats["cache_hits"],
            "cache_hit_rate": f"{cache_rate:.1f}%",
            "semantic_cache_hits": self.stats["semantic_cache_hits"],
            "semantic_hit_rate": f"{semantic_rate:.1f}%",
            "zero_cost_hits": self.stats["zero_cost_hits"],
            "strategy_usage": {
                "fast": self.stats["strategy_fast"],
                "tool": self.stats["strategy_tool"],
                "standard": self.stats["strategy_standard"],
                "deep": self.stats["strategy_deep"],
                "decompose": self.stats["strategy_decompose"]
            }
        }
