from __future__ import annotations

from dataclasses import dataclass, field
from typing import List, Optional, Dict, Set

from tokenizer import Token, TokenType, Tokenizer


# ---------------------------------------------------------------------------
# AST 节点定义
# ---------------------------------------------------------------------------

@dataclass
class InputDecl:
    name: str
    type: str
    from_task: Optional[str] = None


@dataclass
class OutputDecl:
    name: str
    type: str


@dataclass
class TaskNode:
    name: str
    inputs: List[InputDecl] = field(default_factory=list)
    outputs: List[OutputDecl] = field(default_factory=list)
    hard_check: Optional[str] = None
    soft_check: Optional[str] = None


@dataclass
class WhenNode:
    task_ref: str
    field_ref: str
    expected_value: bool
    tasks: List[TaskNode] = field(default_factory=list)


@dataclass
class BranchNode:
    when_clauses: List[WhenNode] = field(default_factory=list)


@dataclass
class WorkflowNode:
    name: str
    inputs: List[InputDecl] = field(default_factory=list)
    tasks: List[TaskNode] = field(default_factory=list)
    branches: List[BranchNode] = field(default_factory=list)


# ---------------------------------------------------------------------------
# 语法错误
# ---------------------------------------------------------------------------

class ParseError(Exception):
    def __init__(self, message: str, line: int, col: int):
        super().__init__(f"[line {line}, col {col}] {message}")
        self.message = message
        self.line = line
        self.col = col


# ---------------------------------------------------------------------------
# 递归下降解析器
# ---------------------------------------------------------------------------

class Parser:
    def __init__(self, tokens: List[Token]):
        self.tokens = tokens
        self.pos = 0

    # ---- 基础工具 ----

    def _skip_newlines(self) -> None:
        while self.pos < len(self.tokens) and self.tokens[self.pos].type == TokenType.NEWLINE:
            self.pos += 1

    def peek(self) -> Token:
        self._skip_newlines()
        return self.tokens[self.pos]

    def advance(self) -> Token:
        tok = self.peek()
        self.pos += 1
        return tok

    def check(self, ttype: TokenType) -> bool:
        return self.peek().type == ttype

    def expect(self, ttype: TokenType, what: str = "") -> Token:
        tok = self.peek()
        if tok.type != ttype:
            desc = what or ttype.name
            raise ParseError(
                f"期望 {desc}，但遇到 {tok.type.name} ('{tok.value}')",
                tok.line, tok.col,
            )
        self.pos += 1
        return tok

    # ---- 入口 ----

    def parse(self) -> WorkflowNode:
        workflow = self.parse_workflow()
        tok = self.peek()
        if tok.type != TokenType.EOF:
            raise ParseError(
                f"workflow 结束后存在多余内容: {tok.type.name} ('{tok.value}')",
                tok.line, tok.col,
            )
        return workflow

    # ---- workflow ----

    def parse_workflow(self) -> WorkflowNode:
        self.expect(TokenType.WORKFLOW, "'workflow' 关键字")
        name_tok = self.expect(TokenType.IDENTIFIER, "workflow 名称")
        self.expect(TokenType.LBRACE, "'{'")

        workflow = WorkflowNode(name=name_tok.value)

        while not self.check(TokenType.RBRACE):
            tok = self.peek()
            if tok.type == TokenType.INPUT:
                workflow.inputs.append(self.parse_input_decl())
            elif tok.type == TokenType.TASK:
                workflow.tasks.append(self.parse_task())
            elif tok.type == TokenType.BRANCH:
                workflow.branches.append(self.parse_branch())
            elif tok.type == TokenType.EOF:
                raise ParseError("workflow 块未闭合，缺少 '}'", tok.line, tok.col)
            else:
                raise ParseError(
                    f"workflow 块内不支持的语句起始 token: {tok.type.name} ('{tok.value}')",
                    tok.line, tok.col,
                )

        self.expect(TokenType.RBRACE, "'}'")
        return workflow

    # ---- input / output ----

    def parse_input_decl(self) -> InputDecl:
        self.expect(TokenType.INPUT, "'input' 关键字")
        name_tok = self.expect(TokenType.IDENTIFIER, "input 名称")

        type_name = ""
        if self.check(TokenType.COLON):
            self.advance()
            type_tok = self.peek()
            if type_tok.type in (TokenType.TYPE_NAME, TokenType.IDENTIFIER):
                self.advance()
                type_name = type_tok.value
            else:
                raise ParseError(
                    f"期望类型名，但遇到 {type_tok.type.name} ('{type_tok.value}')",
                    type_tok.line, type_tok.col,
                )

        from_task: Optional[str] = None
        if self.check(TokenType.FROM):
            self.advance()
            from_tok = self.expect(TokenType.IDENTIFIER, "from 后的 task 名称")
            from_task = from_tok.value

        return InputDecl(name=name_tok.value, type=type_name, from_task=from_task)

    def parse_output_decl(self) -> OutputDecl:
        self.expect(TokenType.OUTPUT, "'output' 关键字")
        name_tok = self.expect(TokenType.IDENTIFIER, "output 名称")
        self.expect(TokenType.COLON, "':'")
        type_tok = self.peek()
        if type_tok.type in (TokenType.TYPE_NAME, TokenType.IDENTIFIER):
            self.advance()
        else:
            raise ParseError(
                f"期望类型名，但遇到 {type_tok.type.name} ('{type_tok.value}')",
                type_tok.line, type_tok.col,
            )
        return OutputDecl(name=name_tok.value, type=type_tok.value)

    # ---- task ----

    def parse_task(self) -> TaskNode:
        self.expect(TokenType.TASK, "'task' 关键字")
        name_tok = self.expect(TokenType.IDENTIFIER, "task 名称")
        self.expect(TokenType.LBRACE, "'{'")

        task = TaskNode(name=name_tok.value)

        while not self.check(TokenType.RBRACE):
            tok = self.peek()
            if tok.type == TokenType.INPUT:
                task.inputs.append(self.parse_input_decl())
            elif tok.type == TokenType.OUTPUT:
                task.outputs.append(self.parse_output_decl())
            elif tok.type == TokenType.HARD_CHECK:
                self.advance()
                self.expect(TokenType.COLON, "':'")
                str_tok = self.expect(TokenType.STRING, "hard_check 的字符串")
                if task.hard_check is not None:
                    raise ParseError(
                        f"task '{task.name}' 重复定义 hard_check", tok.line, tok.col
                    )
                task.hard_check = str_tok.value
            elif tok.type == TokenType.SOFT_CHECK:
                self.advance()
                self.expect(TokenType.COLON, "':'")
                str_tok = self.expect(TokenType.STRING, "soft_check 的字符串")
                if task.soft_check is not None:
                    raise ParseError(
                        f"task '{task.name}' 重复定义 soft_check", tok.line, tok.col
                    )
                task.soft_check = str_tok.value
            elif tok.type == TokenType.EOF:
                raise ParseError(f"task '{task.name}' 块未闭合，缺少 '}}'", tok.line, tok.col)
            else:
                raise ParseError(
                    f"task 块内不支持的语句起始 token: {tok.type.name} ('{tok.value}')",
                    tok.line, tok.col,
                )

        self.expect(TokenType.RBRACE, "'}'")
        return task

    # ---- branch / when ----

    def parse_branch(self) -> BranchNode:
        self.expect(TokenType.BRANCH, "'branch' 关键字")
        self.expect(TokenType.LBRACE, "'{'")

        branch = BranchNode()
        while not self.check(TokenType.RBRACE):
            tok = self.peek()
            if tok.type == TokenType.WHEN:
                branch.when_clauses.append(self.parse_when())
            elif tok.type == TokenType.EOF:
                raise ParseError("branch 块未闭合，缺少 '}'", tok.line, tok.col)
            else:
                raise ParseError(
                    f"branch 块内只允许 when 子句，遇到 {tok.type.name} ('{tok.value}')",
                    tok.line, tok.col,
                )

        self.expect(TokenType.RBRACE, "'}'")
        return branch

    def parse_when(self) -> WhenNode:
        self.expect(TokenType.WHEN, "'when' 关键字")
        task_ref = self.expect(TokenType.IDENTIFIER, "task 引用").value
        self.expect(TokenType.DOT, "'.'")
        field_ref = self.expect(TokenType.IDENTIFIER, "字段引用").value
        self.expect(TokenType.EQ_EQ, "'=='")

        token = self.peek()
        if token.type == TokenType.TRUE:
            expected_value = True
            self.advance()
        elif token.type == TokenType.FALSE:
            expected_value = False
            self.advance()
        else:
            raise ParseError(
                f"when 条件期望 'true' 或 'false'，但遇到 {token.type.name} ('{token.value}')",
                token.line, token.col,
            )

        self.expect(TokenType.LBRACE, "'{'")

        tasks: List[TaskNode] = []
        while not self.check(TokenType.RBRACE):
            token = self.peek()
            if token.type == TokenType.TASK:
                tasks.append(self.parse_task())
            elif token.type == TokenType.EOF:
                raise ParseError("when 块未闭合，缺少 '}'", token.line, token.col)
            else:
                raise ParseError(
                    f"when 块内目前只支持 task 定义，遇到 {token.type.name} ('{token.value}')",
                    token.line, token.col,
                )

        self.expect(TokenType.RBRACE, "'}'")

        return WhenNode(
            task_ref=task_ref,
            field_ref=field_ref,
            expected_value=expected_value,
            tasks=tasks,
        )


# ---------------------------------------------------------------------------
# AST 遍历与语义校验
# ---------------------------------------------------------------------------

def collect_all_tasks(workflow: WorkflowNode) -> List[TaskNode]:
    """递归收集 workflow 顶层 task 以及所有 branch/when 内嵌套的 task，拍平返回。"""
    all_tasks: List[TaskNode] = []
    all_tasks.extend(workflow.tasks)
    for branch in workflow.branches:
        for when_clause in branch.when_clauses:
            all_tasks.extend(when_clause.tasks)
    return all_tasks


def validate_ast(workflow: WorkflowNode) -> List[str]:
    """
    最小可行的语义校验：
    1. task 名重复检测
    2. from_task 引用的 task 必须真实存在
    3. task 之间通过 from_task 形成的依赖图不能有环（DFS 三色标记法）
    """
    errors: List[str] = []
    all_tasks = collect_all_tasks(workflow)

    # 1. 检查 task 名重复
    seen: Set[str] = set()
    for task in all_tasks:
        if task.name in seen:
            errors.append(f"Duplicate task name: '{task.name}'")
        seen.add(task.name)

    task_names = {task.name for task in all_tasks}

    # 2. 检查 input 引用的 from_task 是否存在
    for task in all_tasks:
        for inp in task.inputs:
            if inp.from_task is not None and inp.from_task not in task_names:
                errors.append(
                    f"Task '{task.name}' input '{inp.name}' references "
                    f"unknown task '{inp.from_task}'"
                )

    # 3. 构建依赖图并用 DFS 检测环
    graph: Dict[str, Set[str]] = {task.name: set() for task in all_tasks}
    for task in all_tasks:
        for inp in task.inputs:
            if inp.from_task is not None and inp.from_task in task_names:
                graph[task.name].add(inp.from_task)

    WHITE, GRAY, BLACK = 0, 1, 2
    color: Dict[str, int] = {name: WHITE for name in graph}
    cycle_found: List[List[str]] = []

    def dfs(node: str, path: List[str]) -> None:
        color[node] = GRAY
        path.append(node)
        for dep in graph[node]:
            if color[dep] == GRAY:
                cycle_start = path.index(dep)
                cycle_found.append(path[cycle_start:] + [dep])
            elif color[dep] == WHITE:
                dfs(dep, path)
        path.pop()
        color[node] = BLACK

    for name in graph:
        if color[name] == WHITE:
            dfs(name, [])

    for cycle in cycle_found:
        errors.append("Dependency cycle detected: " + " -> ".join(cycle))

    return errors


if __name__ == "__main__":
    source = '''workflow ProductLaunch {
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
    tokens = Tokenizer(source).tokenize()
    workflow = Parser(tokens).parse()

    all_tasks = collect_all_tasks(workflow)
    print("All tasks:", [task.name for task in all_tasks])

    errors = validate_ast(workflow)
    print("Validation errors:", errors)
