"""
shuyu_v2 P0 组件的最小回归测试。

覆盖：
- task_contract.py: TaskContract 能正确构造，字段结构符合三层验收分离设计
- verification_engine.py: 硬检查/软检查能跑通，通过态判定正确
- tokenizer.py: 词法分析能正确切分关键字/标识符/字符串
- parser.py: 语法分析能正确构建 AST，validate_ast 能抓出真实语义错误

运行方式（在 shuyu_v2 目录下）：
    pytest tests_v2.py -v
"""

from __future__ import annotations

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

from task_contract import (
    TaskContract, Verification, HardCheck, SoftCheck, HardCheckKind,
    JudgeModelConfig, TriggerMode, OnFailPolicy, CostBudget, InspectionMode,
)
from verification_engine import VerificationEngine
from tokenizer import Tokenizer, TokenType
from parser import Parser, validate_ast, collect_all_tasks


# ---------------------------------------------------------------------------
# task_contract.py
# ---------------------------------------------------------------------------

def _make_demo_contract() -> TaskContract:
    return TaskContract(
        name="抓取商品页并提取价格",
        input_schema={"url": "str"},
        output_schema={"price": "float", "currency": "str"},
        verification=Verification(
            hard_checks=[
                HardCheck(
                    check_id="schema_check",
                    kind=HardCheckKind.SCHEMA_VALIDATION,
                    command="python3 -c \"import sys,ast; d=ast.literal_eval(sys.argv[1]); "
                            "assert isinstance(d.get('price'), (int,float))\" {output}",
                ),
            ],
            soft_checks=[
                SoftCheck(
                    check_id="price_plausibility",
                    rubric="价格是否合理",
                    judge=JudgeModelConfig(provider="anthropic", model="claude-haiku-4-5"),
                    pass_threshold=0.8,
                    trigger=TriggerMode.SAMPLING,
                    sample_rate=0.1,
                ),
            ],
        ),
    )


def test_task_contract_three_layer_separation():
    """三层验收标准必须字段分离，不能混在一个列表里。"""
    contract = _make_demo_contract()
    assert len(contract.verification.hard_checks) == 1
    assert len(contract.verification.soft_checks) == 1
    assert len(contract.verification.human_reviews) == 0


def test_task_contract_failure_routes_are_distinct():
    """任务定义缺陷 vs 执行质量缺陷，必须有不同的默认处理路线。"""
    contract = _make_demo_contract()
    policy = contract.on_fail_policy
    assert policy.definition_defect_route.max_retries == 0
    assert policy.quality_defect_route.max_retries == 2
    assert policy.definition_defect_route.escalate_to != policy.quality_defect_route.escalate_to


def test_task_contract_empty_verification_rejected():
    """不允许构造没有任何验收标准的任务合同。"""
    import pytest
    with pytest.raises(Exception):
        Verification(hard_checks=[], soft_checks=[], human_reviews=[])


# ---------------------------------------------------------------------------
# verification_engine.py
# ---------------------------------------------------------------------------

def test_verification_engine_passes_when_all_checks_ok():
    contract = _make_demo_contract()
    engine = VerificationEngine()

    def fake_judge(check, output):
        return 0.9

    result = engine.verify(contract, {"price": 19.9, "currency": "USD"}, fake_judge)
    assert result.passed is True
    assert result.failure_cause is None


def test_verification_engine_detects_quality_defect():
    """硬检查通过但软检查分数不够，应归因为执行质量缺陷。"""
    contract = _make_demo_contract()
    engine = VerificationEngine()

    def low_score_judge(check, output):
        return 0.1  # 远低于 pass_threshold=0.8

    result = engine.verify(contract, {"price": 19.9, "currency": "USD"}, low_score_judge)
    assert result.passed is False
    from task_contract import FailureCause
    assert result.failure_cause == FailureCause.EXECUTION_QUALITY_DEFECT


def test_verification_engine_detects_definition_defect():
    """连 schema 校验都过不了，应归因为任务定义缺陷。"""
    contract = _make_demo_contract()
    engine = VerificationEngine()

    def fake_judge(check, output):
        return 0.9

    # 故意传入不含 price 字段的坏输出，让 schema_check 失败
    bad_output = {"currency": "USD"}
    result = engine.verify(contract, bad_output, fake_judge)
    assert result.passed is False


# ---------------------------------------------------------------------------
# tokenizer.py
# ---------------------------------------------------------------------------

def test_tokenizer_recognizes_keywords():
    tokens = Tokenizer("workflow task input output branch when from").tokenize()
    types = [t.type for t in tokens if t.type != TokenType.NEWLINE]
    assert types[:-1] == [
        TokenType.WORKFLOW, TokenType.TASK, TokenType.INPUT,
        TokenType.OUTPUT, TokenType.BRANCH, TokenType.WHEN, TokenType.FROM,
    ]
    assert types[-1] == TokenType.EOF


def test_tokenizer_handles_chinese_string():
    tokens = Tokenizer('soft_check: "评审设计文档是否达到发布标准"').tokenize()
    strings = [t.value for t in tokens if t.type == TokenType.STRING]
    assert strings == ["评审设计文档是否达到发布标准"]


def test_tokenizer_rejects_unterminated_string():
    import pytest
    from tokenizer import TokenizeError
    with pytest.raises(TokenizeError):
        Tokenizer('"unterminated').tokenize()


# ---------------------------------------------------------------------------
# parser.py
# ---------------------------------------------------------------------------

_DEMO_SOURCE = '''workflow ProductLaunch {
  input idea: str

  task Design {
    input idea
    output design_doc: str
    hard_check: "test -f design_doc.txt"
  }

  task Review {
    input design_doc from Design
    output approved: bool
    soft_check: "评审设计文档是否达到发布标准"
  }

  branch {
    when Review.approved == true {
      task Ship {
        input design_doc from Design
        output result: str
      }
    }
  }
}
'''


def test_parser_builds_expected_ast():
    tokens = Tokenizer(_DEMO_SOURCE).tokenize()
    workflow = Parser(tokens).parse()
    task_names = [t.name for t in collect_all_tasks(workflow)]
    assert task_names == ["Design", "Review", "Ship"]


def test_validate_ast_accepts_valid_workflow():
    tokens = Tokenizer(_DEMO_SOURCE).tokenize()
    workflow = Parser(tokens).parse()
    assert validate_ast(workflow) == []


def test_validate_ast_detects_unknown_reference():
    bad_source = '''workflow Bad {
  task A {
    input x from NonExistent
    output y: str
  }
}
'''
    tokens = Tokenizer(bad_source).tokenize()
    workflow = Parser(tokens).parse()
    errors = validate_ast(workflow)
    assert len(errors) == 1
    assert "NonExistent" in errors[0]


def test_validate_ast_detects_cycle():
    bad_source = '''workflow Bad {
  task A {
    input x from B
    output y: str
  }
  task B {
    input z from A
    output w: str
  }
}
'''
    tokens = Tokenizer(bad_source).tokenize()
    workflow = Parser(tokens).parse()
    errors = validate_ast(workflow)
    assert any("cycle" in e.lower() for e in errors)


if __name__ == "__main__":
    import subprocess
    result = subprocess.run(
        ["python3", "-m", "pytest", __file__, "-v"],
        cwd=os.path.dirname(__file__),
    )
    sys.exit(result.returncode)
