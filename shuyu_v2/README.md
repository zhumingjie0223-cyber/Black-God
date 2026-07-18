# shuyu_v2 — 枢语 v2:任务合同 + 验证引擎 + DSL 解析器(P0 骨架)

> 状态:**最小可运行骨架,非生产就绪**。响应三轮架构批评后的首个真实落地(不是文档)。
> 目标:把"神枢调度任务"从模糊的自然语言,变成有正式合同、可机器验收、可静态检查的工程对象。

## 四大组件

| 文件 | 作用 | 依赖 |
|---|---|---|
| `tokenizer.py` | 枢语 DSL v2 词法分析(关键字/标识符/字符串切分) | 纯标准库 |
| `parser.py` | 递归下降语法分析 → 真实 AST;`validate_ast` 做重名/未知引用/循环依赖(DFS 三色标记)检测 | 纯标准库 |
| `task_contract.py` | 任务合同数据结构:三层验收(HardCheck/SoftCheck/HumanReview)字段分离、失败根因区分、验收成本预算 | pydantic |
| `verification_engine.py` | 硬检查用 subprocess 真实执行;软检查裁判可插拔;失败归因启发式(v1 粗糙,非最终解) | pydantic |

## 一键复现(工业级:声明即可跑)

```bash
# 在仓库根目录
pip install -r shuyu_v2/requirements.txt
python3 -m pytest shuyu_v2/tests_v2.py -q          # 13 用例应全过
```

也可作为包被上层消费(import 已做「包内相对 + 目录内回退」双兼容):

```python
from shuyu_v2.parser import Parser, validate_ast
from shuyu_v2.task_contract import TaskContract
```

仅用无依赖的 DSL 部分时,连 pydantic 都不需要:

```bash
python3 - <<'PY'
from shuyu_v2.tokenizer import Tokenizer
from shuyu_v2.parser import Parser, validate_ast
wf = Parser(Tokenizer("workflow demo { task A { output x: str } }").tokenize()).parse()
print("errors:", validate_ast(wf) or "无")
PY
```

## 已知限制(不掩盖)

- `verification_engine` 的失败归因用字符串匹配 schema 识别早期失败,脆弱。
- `soft_check` 的 `judge_caller` 只是接口占位,未接入真实 LLM API。
- retry DSL 语法(`retry with ... from ...`)尚未实现,只有 `task_contract` 层的 `OnFailPolicy`。
- 这是最小骨架,不是生产就绪代码;尚未接入神枢主体(`web/nexus-do/`)或旧 Python 内核(`server/`)。
