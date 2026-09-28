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

Здесь же — снятие префиксов перед исполняемой командой (`strip_prefixes`:
присваивания, ключевые слова, `time`, `env`, обёртки `builtin`, `command`, `exec`,
`nice`, `nohup`, `setsid`, `stdbuf`, `ionice`, `timeout`). Оно тоже одно на обоих
читателей: слово, которое страж считает исполняемой командой, гейт обязан считать
тем же.
"""
from __future__ import annotations

import os
import re

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

# ── снятие префиксов перед исполняемой командой ─────────────────────────────
# ОДНО на страж и гейт: страж по нему находит `git` и `cd`, гейт check-21 — позицию
# вызова соседа в хуке. Прежде оно жило в страже, и гейт считал вызовом любое слово
# после `then`, `{`, `command` (приёмка ws#714, круг 2): лексер общий, снятие — нет.

KEYWORDS = {"if", "then", "elif", "else", "do", "while", "until", "!", "{", "}", "fi",
            "done", "esac"}
ASSIGN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\+?=.*", re.S)

# Обёртка → (опции с аргументом, опции-флаги по шаблону, число позиционных до команды).
WRAPPERS = {
    # `builtin` исполняет встроенную команду оболочки: `builtin cd` меняет каталог ровно
    # как `cd` (приёмка ws#714, круг 2 — префикс не снимался, и stash после
    # `builtin cd <общая копия>` судился в каталоге, откуда команду подали).
    "builtin": (set(), set(), 0),
    "command": ({"-p"}, set(), 0),
    "exec": ({"-a"}, {"-c", "-l", "-cl", "-lc"}, 0),
    "nice": ({"-n", "--adjustment"}, set(), 0),
    "nohup": (set(), set(), 0),
    "setsid": (set(), {"-f", "-w", "-c", "--fork", "--wait", "--ctty"}, 0),
    "stdbuf": ({"-i", "-o", "-e", "--input", "--output", "--error"}, set(), 0),
    "ionice": ({"-c", "-n", "-p", "-P", "-u", "--class", "--classdata"}, {"-t"}, 0),
    "timeout": ({"-s", "--signal", "-k", "--kill-after"},
                {"--preserve-status", "--foreground", "-v", "--verbose"}, 1),
}


def strip_prefixes(words: list[str], here: str) -> tuple[list[str], dict, str]:
    """Снять присваивания, ключевые слова и обёртки перед исполняемой командой.

    → (слова команды, присваивания, каталог — `env -C` его меняет).
    """
    env: dict[str, str] = {}
    i = 0
    while i < len(words):
        w = words[i]
        if ASSIGN.fullmatch(w):
            k, _, v = w.partition("=")
            env[k.rstrip("+")] = v
            i += 1
            continue
        if w in KEYWORDS:
            i += 1
            continue
        if w == "time":
            i += 1
            if i < len(words) and words[i] == "-p":
                i += 1
            continue
        if w == "env":
            i += 1
            while i < len(words):
                a = words[i]
                if a in ("-C", "--chdir") and i + 1 < len(words):
                    here = os.path.normpath(os.path.join(here, os.path.expanduser(words[i + 1])))
                    i += 2
                elif a.startswith("--chdir="):
                    here = os.path.normpath(os.path.join(here, os.path.expanduser(a.split("=", 1)[1])))
                    i += 1
                elif a in ("-u", "--unset") and i + 1 < len(words):
                    i += 2
                elif a == "--":
                    i += 1
                    break
                elif a.startswith("-"):
                    i += 1
                elif ASSIGN.fullmatch(a):
                    k, _, v = a.partition("=")
                    env[k] = v
                    i += 1
                else:
                    break
            continue
        if w in WRAPPERS:
            with_arg, flags, positional = WRAPPERS[w]
            if w == "command" and i + 1 < len(words) and words[i + 1] in ("-v", "-V"):
                return [], env, here          # `command -v git` — поиск, не исполнение
            i += 1
            while i < len(words) and words[i].startswith("-") and words[i] != "-":
                a = words[i]
                if a == "--":
                    i += 1
                    break
                if a in with_arg:
                    i += 2
                elif a.split("=", 1)[0] in with_arg or a in flags:
                    i += 1
                elif w in ("nice", "stdbuf", "ionice") and len(a) > 2:
                    i += 1                     # `-n5`, `-oL`, `-c2` — значение слитно
                else:
                    i += 1
            i += positional
            continue
        break
    return words[i:], env, here
