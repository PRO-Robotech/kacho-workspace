#!/usr/bin/env python3
"""Лексер оболочки — ровно в той мере, в какой его читают страж и гейт.

Читатели два, и разбор у них ОДИН: `.claude/hooks/lib/bash_guard.py` (страж команды
Bash до исполнения) и `scripts/tooling-gate/check-21-harness-hooks-wired.sh`
(провязка хуков: команда записи в `settings.json` и вызов соседа из хука). Два
разбора одной оболочки разошлись бы молча — ровно тот класс, который оба ловят.

Что различается: одинарные и двойные кавычки, `$'…'`, экранирование, `$(…)`,
обратные кавычки, `<(…)`/`>(…)`, `${…}`, `$((…))`, комментарий с начала слова,
продолжение строки, heredoc (`<<`, `<<-`, в кавычках и без — тело пропускается
как данные), операторы управления и перенаправления. Перевод строки — разделитель
только вне кавычек и вне тела heredoc.

Чего не различается и что не утверждается: `case … in шаблон)` внутри `$(…)`
(скобка шаблона читается закрывающей), раскрытие переменных, алиасов и функций.
"""
from __future__ import annotations

SUBST = "\x00"     # метка подстановки команды в слове; исходник — Word.subs
ARITH = "\x01"     # метка арифметики $((…)) — команд в ней нет


class Word(str):
    """Слово команды после снятия кавычек. `subs` — исходники подстановок в нём."""
    subs: tuple[str, ...] = ()


def _word(text: str, subs: list[str]) -> Word:
    w = Word(text)
    w.subs = tuple(subs)
    return w


OPS = ("&&", "||", ";;", "|&", "&>>", "&>", "<<<", "<<-", "<<", ">>", ">|", "<&", ">&",
       "<>", ";", "&", "|", "(", ")", "<", ">")
REDIRECT = {"<<<", "&>>", "&>", ">>", ">|", "<&", ">&", "<>", "<", ">"}


class Lexer:
    r"""Лексер оболочки ровно в той мере, в какой он нужен стражу.

    Выдаёт поток: `Word` (кавычки сняты; подстановка команды оставлена меткой
    `SUBST`, её исходник — в `Word.subs` по порядку меток; арифметика — меткой
    `ARITH`; `${…}` и `$ИМЯ` остаются в слове буквально, не раскрытыми) и операторы
    строкой, перевод строки — `"\n"`. Тело heredoc пропускается целиком.
    Незакрытая кавычка или подстановка — `ValueError`.
    """

    def __init__(self, src: str):
        self.s = src
        self.i = 0
        self.heredocs: list[tuple[str, bool]] = []

    def error(self, what: str) -> ValueError:
        return ValueError(f"{what} (позиция {self.i})")

    def peek(self, k: int = 0) -> str:
        j = self.i + k
        return self.s[j] if j < len(self.s) else ""

    # ── подстановки: исходник возвращается, чтобы судить его как команду ──────
    def paren_sub(self) -> str:
        """`$(` или `<(` уже съедены: читать до парной `)` на уровне команды."""
        start = self.i
        sub = Lexer(self.s)
        sub.i = self.i
        depth = 0
        while True:
            tok = sub.next_token()
            if tok is None:
                self.i = sub.i
                raise self.error("незакрытая подстановка $(…)")
            if tok == "(":
                depth += 1
            elif tok == ")":
                if depth == 0:
                    self.i = sub.i
                    return self.s[start:sub.i - 1]
                depth -= 1

    def arith_sub(self) -> None:
        """`$((` уже съеден: до парной `))`."""
        depth = 0
        while self.i < len(self.s):
            c = self.s[self.i]
            if c == "(":
                depth += 1
            elif c == ")":
                if depth == 0 and self.peek(1) == ")":
                    self.i += 2
                    return
                depth -= 1
            self.i += 1
        raise self.error("незакрытая арифметика $((…))")

    def backtick_sub(self) -> str:
        """Открывающая обратная кавычка съедена: до парной, `\\` экранирует."""
        out = []
        while self.i < len(self.s):
            c = self.s[self.i]
            if c == "\\" and self.i + 1 < len(self.s):
                out.append(self.s[self.i + 1])
                self.i += 2
                continue
            if c == "`":
                self.i += 1
                return "".join(out)
            out.append(c)
            self.i += 1
        raise self.error("незакрытая обратная кавычка")

    def brace_param(self) -> str:
        """`${` съеден: до парной `}`. Возвращает содержимое — оно остаётся в слове."""
        start = self.i
        depth = 0
        while self.i < len(self.s):
            c = self.s[self.i]
            if c == "\\":
                self.i += 2
                continue
            if c == "{":
                depth += 1
            elif c == "}":
                if depth == 0:
                    self.i += 1
                    return self.s[start:self.i - 1]
                depth -= 1
            self.i += 1
        raise self.error("незакрытое ${…}")

    def dollar(self, buf: list[str], subs: list[str]) -> bool:
        """На `$`: подстановка команды, арифметика или параметр. True — съедено."""
        nxt = self.peek(1)
        if nxt == "(" and self.peek(2) == "(":
            self.i += 3
            self.arith_sub()
            buf.append(ARITH)
            return True
        if nxt == "(":
            self.i += 2
            subs.append(self.paren_sub())
            buf.append(SUBST)
            return True
        if nxt == "{":
            self.i += 2
            buf.append("${" + self.brace_param() + "}")
            return True
        return False

    def double_quoted(self, buf: list[str], subs: list[str]) -> None:
        self.i += 1
        while self.i < len(self.s):
            c = self.s[self.i]
            if c == '"':
                self.i += 1
                return
            if c == "\\" and self.peek(1) in ('"', "\\", "$", "`", "\n"):
                if self.peek(1) != "\n":
                    buf.append(self.peek(1))
                self.i += 2
                continue
            if c == "$" and self.dollar(buf, subs):
                continue
            if c == "`":
                self.i += 1
                subs.append(self.backtick_sub())
                buf.append(SUBST)
                continue
            buf.append(c)
            self.i += 1
        raise self.error("незакрытая двойная кавычка")

    def single_quoted(self, buf: list[str], ansi: bool) -> None:
        self.i += 1
        while self.i < len(self.s):
            c = self.s[self.i]
            if ansi and c == "\\" and self.i + 1 < len(self.s):
                buf.append(self.s[self.i + 1])
                self.i += 2
                continue
            if c == "'":
                self.i += 1
                return
            buf.append(c)
            self.i += 1
        raise self.error("незакрытая одинарная кавычка")

    def skip_heredoc_bodies(self) -> None:
        """Перевод строки съеден: тела ожидающих heredoc — данные, пропустить."""
        for delim, strip_tabs in self.heredocs:
            while self.i < len(self.s):
                end = self.s.find("\n", self.i)
                line = self.s[self.i:] if end < 0 else self.s[self.i:end]
                self.i = len(self.s) if end < 0 else end + 1
                if (line.lstrip("\t") if strip_tabs else line) == delim:
                    break
            # Конец ввода без разделителя: оболочка исполняет, предупредив, — не отказ.
        self.heredocs = []

    def next_token(self):
        s = self.s
        while self.i < len(s):
            c = s[self.i]
            if c in " \t":
                self.i += 1
                continue
            if c == "\\" and self.peek(1) == "\n":
                self.i += 2
                continue
            if c == "#":
                end = s.find("\n", self.i)
                self.i = len(s) if end < 0 else end
                continue
            if c == "\n":
                self.i += 1
                self.skip_heredoc_bodies()
                return "\n"
            if c in "<>" and self.peek(1) == "(":
                self.i += 2
                sub = self.paren_sub()
                return _word(SUBST, [sub])
            for op in OPS:
                if s.startswith(op, self.i):
                    self.i += len(op)
                    if op in ("<<", "<<-"):
                        delim = self.next_token()
                        if not isinstance(delim, Word):
                            raise self.error("heredoc без разделителя")
                        self.heredocs.append((str(delim), op == "<<-"))
                        return self.next_token()
                    return op
            w = self.word()
            if w is None:
                continue
            return w
        return None

    def word(self) -> Word | None:
        buf: list[str] = []
        subs: list[str] = []
        s = self.s
        while self.i < len(s):
            c = s[self.i]
            if c in " \t\n" or any(s.startswith(op, self.i) for op in OPS):
                # Цифра дескриптора перед перенаправлением (`2>`) — часть оператора,
                # не слово команды: слова нет вовсе.
                if c in "<>" and buf and "".join(buf).isdigit() and not subs:
                    return None
                break
            if c == "\\":
                if self.peek(1) == "\n":
                    self.i += 2
                    continue
                if self.i + 1 < len(s):
                    buf.append(s[self.i + 1])
                self.i += 2
                continue
            if c == "'":
                self.single_quoted(buf, ansi=False)
                continue
            if c == "$" and self.peek(1) == "'":
                self.i += 1
                self.single_quoted(buf, ansi=True)
                continue
            if c == '"':
                self.double_quoted(buf, subs)
                continue
            if c == "$" and self.dollar(buf, subs):
                continue
            if c == "`":
                self.i += 1
                subs.append(self.backtick_sub())
                buf.append(SUBST)
                continue
            buf.append(c)
            self.i += 1
        return _word("".join(buf), subs)


def lex(command: str) -> list:
    lx = Lexer(command)
    out = []
    while True:
        tok = lx.next_token()
        if tok is None:
            return out
        out.append(tok)


SEP = {"&&", "||", ";", ";;", "|", "&", "|&", "\n"}


SEP = {"&&", "||", ";", ";;", "|", "&", "|&", "\n"}


def simple_commands(src: str) -> list[list[Word]]:
    """Простые команды по порядку: разделители и скобки подоболочки сняты,
    перенаправления вместе с их целью из слов убраны. Подстановки — в `Word.subs`."""
    out: list[list[Word]] = []
    cur: list = []

    def flush() -> None:
        ws, i = [], 0
        while i < len(cur):
            w = cur[i]
            if not isinstance(w, Word) and w in REDIRECT:
                i += 2
                continue
            if isinstance(w, Word):
                ws.append(w)
            i += 1
        if ws:
            out.append(ws)
        cur.clear()

    for t in lex(src):
        if isinstance(t, Word):
            cur.append(t)
        elif t in SEP or t in ("(", ")"):
            flush()
        else:
            cur.append(t)
    flush()
    return out
