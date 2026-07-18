from __future__ import annotations

from dataclasses import dataclass
from enum import Enum, auto
from typing import List


class TokenType(Enum):
    # Keywords
    WORKFLOW = auto()
    INPUT = auto()
    OUTPUT = auto()
    TASK = auto()
    BRANCH = auto()
    WHEN = auto()
    RETRY = auto()
    FROM = auto()
    WITH = auto()
    HARD_CHECK = auto()
    SOFT_CHECK = auto()
    TRUE = auto()
    FALSE = auto()
    TYPE_NAME = auto()  # str / bool / int / float / list

    # Literals & identifiers
    IDENTIFIER = auto()
    STRING = auto()

    # Punctuation
    LBRACE = auto()
    RBRACE = auto()
    COLON = auto()
    DOT = auto()
    EQ_EQ = auto()

    # Structure
    NEWLINE = auto()
    EOF = auto()


@dataclass
class Token:
    type: TokenType
    value: str
    line: int
    col: int

    def __repr__(self) -> str:
        return f"{self.type.name} {self.value!r} at {self.line}:{self.col}"


KEYWORDS = {
    "workflow": TokenType.WORKFLOW,
    "input": TokenType.INPUT,
    "output": TokenType.OUTPUT,
    "task": TokenType.TASK,
    "branch": TokenType.BRANCH,
    "when": TokenType.WHEN,
    "retry": TokenType.RETRY,
    "from": TokenType.FROM,
    "with": TokenType.WITH,
    "hard_check": TokenType.HARD_CHECK,
    "soft_check": TokenType.SOFT_CHECK,
    "true": TokenType.TRUE,
    "false": TokenType.FALSE,
    "str": TokenType.TYPE_NAME,
    "bool": TokenType.TYPE_NAME,
    "int": TokenType.TYPE_NAME,
    "float": TokenType.TYPE_NAME,
    "list": TokenType.TYPE_NAME,
}


class TokenizeError(Exception):
    def __init__(self, message: str, line: int, col: int):
        super().__init__(f"{message} (line {line}, col {col})")
        self.line = line
        self.col = col


class Tokenizer:
    def __init__(self, source: str):
        self.source = source
        self.pos = 0
        self.line = 1
        self.col = 1
        self.tokens: List[Token] = []

    # ---- low-level helpers ------------------------------------------------

    def _peek(self, offset: int = 0) -> str:
        idx = self.pos + offset
        if idx < len(self.source):
            return self.source[idx]
        return ""

    def _advance(self) -> str:
        ch = self.source[self.pos]
        self.pos += 1
        if ch == "\n":
            self.line += 1
            self.col = 1
        else:
            self.col += 1
        return ch

    def _at_end(self) -> bool:
        return self.pos >= len(self.source)

    def _add(self, ttype: TokenType, value: str, line: int, col: int) -> None:
        self.tokens.append(Token(ttype, value, line, col))

    # ---- main entry point -------------------------------------------------

    def tokenize(self) -> List[Token]:
        while not self._at_end():
            ch = self._peek()
            line, col = self.line, self.col

            # Newline -> NEWLINE token (collapse nothing; one token per '\n')
            if ch == "\n":
                self._advance()
                self._add(TokenType.NEWLINE, "\\n", line, col)
                continue

            # Skip other whitespace
            if ch in " \t\r":
                self._advance()
                continue

            # Comment: '#' to end of line (newline itself is kept)
            if ch == "#":
                while not self._at_end() and self._peek() != "\n":
                    self._advance()
                continue

            # Punctuation
            if ch == "{":
                self._advance()
                self._add(TokenType.LBRACE, "{", line, col)
                continue
            if ch == "}":
                self._advance()
                self._add(TokenType.RBRACE, "}", line, col)
                continue
            if ch == ":":
                self._advance()
                self._add(TokenType.COLON, ":", line, col)
                continue
            if ch == ".":
                self._advance()
                self._add(TokenType.DOT, ".", line, col)
                continue

            # Double equals
            if ch == "=":
                if self._peek(1) == "=":
                    self._advance()
                    self._advance()
                    self._add(TokenType.EQ_EQ, "==", line, col)
                    continue
                raise TokenizeError("Unexpected single '=' (did you mean '==' ?)", line, col)

            # String literal
            if ch == '"':
                self._add(TokenType.STRING, self._read_string(), line, col)
                continue

            # Identifier / keyword
            if ch.isalpha() or ch == "_":
                word = self._read_identifier()
                ttype = KEYWORDS.get(word, TokenType.IDENTIFIER)
                self._add(ttype, word, line, col)
                continue

            raise TokenizeError(f"Unexpected character {ch!r}", line, col)

        self._add(TokenType.EOF, "", self.line, self.col)
        return self.tokens

    # ---- token readers ----------------------------------------------------

    def _read_string(self) -> str:
        start_line, start_col = self.line, self.col
        self._advance()  # consume opening quote
        chars: List[str] = []
        while True:
            if self._at_end():
                raise TokenizeError("Unterminated string literal", start_line, start_col)
            ch = self._peek()
            if ch == "\n":
                raise TokenizeError("Unterminated string literal (newline in string)", start_line, start_col)
            if ch == '"':
                self._advance()  # consume closing quote
                return "".join(chars)
            if ch == "\\":
                self._advance()
                if self._at_end():
                    raise TokenizeError("Unterminated escape sequence", self.line, self.col)
                esc = self._advance()
                mapping = {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}
                chars.append(mapping.get(esc, esc))
                continue
            chars.append(self._advance())

    def _read_identifier(self) -> str:
        chars: List[str] = []
        while not self._at_end():
            ch = self._peek()
            if ch.isalnum() or ch == "_":
                chars.append(self._advance())
            else:
                break
        return "".join(chars)


if __name__ == "__main__":
    demo_source = '''workflow ProductLaunch {
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
    tokenizer = Tokenizer(demo_source)
    for token in tokenizer.tokenize():
        print(f"{token.type.name} {token.value!r} at {token.line}:{token.col}")
