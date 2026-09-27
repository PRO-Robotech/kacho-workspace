#!/usr/bin/env python3
"""Страж команды Bash до исполнения (`PreToolUse`): два запрета, которые держались вниманием.

# Предмет

1. `git stash` в ОБЩЕЙ рабочей копии (ws#602). Общая копия — рабочее дерево, которым
   пользуются несколько агентов сразу: корень воркспейса и клон продукта. `pop` в ней
   вынимает ЧУЖОЙ схрон, а незакоммиченная чужая работа существует в единственном
   экземпляре. Запрет стоял в теле `git-operator`, `landing-reviewer`, `scout` и в
   архивном своде — и за одну сессию (2026-09-08) нарушен дважды.
2. `git push` полосы, чья база НЕ ЗНАЕТ проверок ствола (ws#717). Набор гейтов обходит
   свой каталог и печатает «рассмотрено N» по тому, что НАШЁЛ. Отставшая база даёт
   зелёный на меньшем числе проверок, и он неотличим от зелёного на полном: код один,
   число никто не сверяет. Новая проверка ствола не судит полосу, пока до неё не
   доберётся база, — и этого момента не наблюдает никто.

# Признаки — из git, а не из списка путей

«Общая копия» — ГЛАВНОЕ рабочее дерево (`--git-dir` совпадает с `--git-common-dir`)
репозитория, у которого есть хотя бы одно присоединённое. Своя копия полосы —
присоединённое дерево в `tmp/`: там `stash` законен и полезен, и запрет его не трогает.

«База не знает проверки ствола» — файл `scripts/<набор>-gate/check-*` есть на
`origin/main`, его нет в отправляемой ревизии И нет в их общей базе. Последнее
условие отличает ОТСТАВАНИЕ (ствол завёл проверку после развилки) от СНЯТИЯ (полоса
сама удалила проверку, которая была в базе): второе — решение полосы, и страж его
не судит.

# Обход — явный и видимый

Обход — присваивание в самой команде: `KACHO_STASH_SHARED=1 git stash …`,
`KACHO_PUSH_LAGGING=1 git push …`. Он остаётся в тексте команды, то есть в ленте
сессии, и исполнитель обязан назвать его в возврате (строка нормы в `ai-tooling.md`).

# Граница, объявленная, а не умолчанная

- Судится текст команды, разобранный СВОИМ лексером оболочки (`lex` ниже), а не
  построчно: кавычки, `$(…)`, обратные кавычки и тело heredoc распознаются ДО того,
  как перевод строки становится разделителем. Прежняя редакция резала команду по
  строкам до `shlex`, и штатная форма коммита — `-m "$(cat <<'EOF' … EOF)"` — давала
  «не разобрана», а отправка в той же команде проходила несуженной.
- Разделители — `&&`, `||`, `;`, `|`, `&`, `|&` и перевод строки вне кавычек и вне
  тела heredoc. Тело heredoc — данные, не команды.
- Каталог выводится из `cd`, `pushd`/`popd` и `git -C`; подоболочка `( … )` каталог
  наружу не переносит. Команды внутри `$( … )`, обратных кавычек и `<( … )` судятся
  как вложенные, с каталогом точки подстановки.
- Префиксы перед git, которые исполняют его же: присваивания `ИМЯ=…`, слова `if`,
  `then`, `elif`, `else`, `do`, `while`, `until`, `!`, `{`, `time [-p]` и обёртки
  `env` (включая `-C <каталог>`), `command`, `exec`, `nice`, `nohup`, `setsid`,
  `stdbuf`, `ionice`, `timeout`.
- НЕ различается и этого страж не утверждает: команда, собранная иначе (`eval`,
  `bash -c '…'`, `sh -c`, имя подкоманды или каталог из переменной — переменные не
  раскрываются, алиас git, функция оболочки), обёртки `sudo`, `xargs`, `find -exec`,
  `watch`, `parallel`.
- Отправку не через `git push` (`gh pr create`, догоняющая отправку ветки) страж не видит.
- Ствол — локальная ссылка `origin/main`: страж не делает `fetch`, и отставание судится
  от ствола, каким его видела последняя выборка. Ссылки нет — отставание не судится
  (канала, которым сказать это агенту без отказа, у `PreToolUse` нет).
- Общий на все деревья репозитория список схронов (`refs/stash`) страж не судит: `pop`
  без явной ссылки в СВОЕЙ копии тоже может вынуть чужое.
- Команда, которую не разобрать (незакрытая кавычка или подстановка), — код 1: её не
  исполнит и сама оболочка, а страж, не понявший команду, не вправе её останавливать.

Исходы: 0 — пропустить; 2 — отказ (stderr уходит агенту, команда не исполняется);
1 — поломка самого стража (stderr видит человек, команда НЕ блокируется: страж,
упавший на своей ошибке, не вправе останавливать чужую работу).
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys

TRUNK = "origin/main"
CHECK = re.compile(r"^scripts/[^/]+-gate/check-[^/]+$")
BYPASS_STASH = "KACHO_STASH_SHARED"
BYPASS_PUSH = "KACHO_PUSH_LAGGING"
STASH_READONLY = {"list", "show"}


def git(cwd: str, *args: str) -> tuple[int, str]:
    try:
        p = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return 128, ""
    return p.returncode, p.stdout.strip()


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

    Выдаёт поток: `Word` (кавычки сняты, подстановка оставлена меткой `\x00`, её
    исходник — в `Word.subs`) и операторы строкой, перевод строки — `"\n"`. Тело
    heredoc пропускается целиком. Незакрытая кавычка или подстановка — `ValueError`.
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

    def brace_param(self) -> None:
        """`${` съеден: до парной `}`."""
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
                    return
                depth -= 1
            self.i += 1
        raise self.error("незакрытое ${…}")

    def dollar(self, buf: list[str], subs: list[str]) -> bool:
        """На `$`: подстановка команды, арифметика или параметр. True — съедено."""
        nxt = self.peek(1)
        if nxt == "(" and self.peek(2) == "(":
            self.i += 3
            self.arith_sub()
            buf.append("\x00")
            return True
        if nxt == "(":
            self.i += 2
            subs.append(self.paren_sub())
            buf.append("\x00")
            return True
        if nxt == "{":
            self.i += 2
            self.brace_param()
            buf.append("\x00")
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
                buf.append("\x00")
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
                return _word("\x00", [sub])
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
                buf.append("\x00")
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
KEYWORDS = {"if", "then", "elif", "else", "do", "while", "until", "!", "{", "}", "fi",
            "done", "esac"}
ASSIGN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\+?=.*", re.S)

# Обёртка → (опции с аргументом, опции-флаги по шаблону, число позиционных до команды).
WRAPPERS = {
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


def commands(command: str, cwd: str) -> list[tuple[list[str], str, dict]]:
    """→ [(слова простой команды, каталог её исполнения, присваивания перед ней)] —
    вложенные подстановки тоже.

    Каталог ведётся по `cd`, `pushd`/`popd`; подоболочка `( … )` возвращает его на
    выходе. Перенаправления и их цели из слов команды сняты.
    """
    out: list[tuple[list[str], str, dict]] = []
    here = cwd
    oldpwd = cwd
    dirstack: list[str] = []
    frames: list[tuple[str, str, list[str]]] = []
    words: list = []
    toks = lex(command)

    def flush() -> None:
        nonlocal here, oldpwd, words
        ws, i = [], 0
        while i < len(words):
            w = words[i]
            if isinstance(w, str) and not isinstance(w, Word) and w in REDIRECT:
                i += 2                          # оператор и его цель
                continue
            ws.append(w)
            i += 1
        words = []
        for w in ws:
            for sub in getattr(w, "subs", ()):
                out.extend(commands(sub, here))
        argv, env, at = strip_prefixes([str(w) for w in ws], here)
        if not argv:
            return
        name = argv[0]
        if name == "cd":
            args = [a for a in argv[1:] if not (a.startswith("-") and a != "-")]
            dest = args[0] if args else os.path.expanduser("~")
            new = oldpwd if dest == "-" else os.path.normpath(
                os.path.join(here, os.path.expanduser(dest)))
            oldpwd, here = here, new
            return
        if name == "pushd":
            args = [a for a in argv[1:] if not a.startswith("-")]
            if args and not re.fullmatch(r"[+-]\d+", args[0]):
                dirstack.append(here)
                oldpwd, here = here, os.path.normpath(
                    os.path.join(here, os.path.expanduser(args[0])))
            return
        if name == "popd":
            if dirstack:
                oldpwd, here = here, dirstack.pop()
            return
        out.append((argv, at, env))

    for t in toks:
        if isinstance(t, Word):
            words.append(t)
            continue
        if t == "(" and not words:
            frames.append((here, oldpwd, list(dirstack)))
            continue
        if t == ")":
            flush()
            if frames:
                here, oldpwd, dirstack = frames.pop()
            continue
        if t in SEP:
            flush()
            continue
        words.append(t)                          # перенаправление: снимется во flush
    flush()
    return out


GIT_OPT_WITH_ARG = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}


def parse_git(tokens: list[str], cwd: str) -> tuple[str, str, list[str], dict]:
    """→ (подкоманда, каталог, аргументы, присваивания окружения) либо ('', …)."""
    tokens, env, cwd = strip_prefixes(tokens, cwd)
    if not tokens or os.path.basename(tokens[0]) != "git":
        return "", cwd, [], env
    i = 1
    d = cwd
    while i < len(tokens) and tokens[i].startswith("-"):
        t = tokens[i]
        if t == "-C" and i + 1 < len(tokens):
            d = os.path.normpath(os.path.join(d, os.path.expanduser(tokens[i + 1])))
            i += 2
            continue
        if t in GIT_OPT_WITH_ARG and i + 1 < len(tokens):
            i += 2
            continue
        i += 1
    if i >= len(tokens):
        return "", d, [], env
    return tokens[i], d, tokens[i + 1:], env


def shared_copy(d: str) -> tuple[bool, str]:
    rc, top = git(d, "rev-parse", "--show-toplevel")
    if rc != 0:
        return False, ""
    _, gd = git(d, "rev-parse", "--path-format=absolute", "--git-dir")
    _, cd = git(d, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if not gd or not cd:
        return False, top
    if os.path.realpath(gd) != os.path.realpath(cd):
        return False, top            # присоединённое дерево — своя копия полосы
    _, wl = git(d, "worktree", "list", "--porcelain")
    n = sum(1 for ln in wl.split("\n") if ln.startswith("worktree "))
    return n > 1, top


def checks_at(d: str, ref: str) -> set[str]:
    rc, out = git(d, "ls-tree", "-r", "--name-only", ref, "--", "scripts")
    if rc != 0:
        return set()
    return {p for p in out.split("\n") if CHECK.match(p)}


def push_source(d: str, args: list[str]) -> tuple[str, str]:
    """→ (ревизия, почему пропущено). Удаление, теги и зеркало не судятся."""
    pos = []
    skip_next = False
    for a in args:
        if skip_next:
            skip_next = False
            continue
        if a in ("--delete", "-d", "--tags", "--mirror", "--prune"):
            return "", f"`git push {a}` — не отправка ревизии полосы"
        if a in ("-o", "--push-option", "--repo", "--receive-pack", "--exec"):
            skip_next = True
            continue
        if a.startswith("-"):
            continue
        pos.append(a)
    refspecs = pos[1:]
    if not refspecs:
        return "HEAD", ""
    src = refspecs[0].lstrip("+").split(":", 1)[0]
    if not src:
        return "", "refspec `:<ветка>` — удаление"
    rc, sha = git(d, "rev-parse", "--verify", "--quiet", src + "^{commit}")
    if rc != 0:
        return "HEAD", ""
    return sha, ""


def judge_stash(d: str, args: list[str], env: dict) -> str:
    action = next((a for a in args if not a.startswith("-")), "push")
    if action in STASH_READONLY:
        return ""
    shared, top = shared_copy(d)
    if not shared or env.get(BYPASS_STASH) == "1":
        return ""
    return (f"`git stash {action}` в ОБЩЕЙ рабочей копии {top} — это главное дерево "
            "репозитория с присоединёнными копиями, им пользуются несколько агентов. "
            "`pop` вынимает ЧУЖОЙ схрон, а чужая незакоммиченная работа — в единственном "
            "экземпляре (ws#602). Своя копия полосы — присоединённое дерево в tmp/: там "
            f"stash законен. Обход, если он осознан: `{BYPASS_STASH}=1 git stash …` — и "
            "строка об этом в возврате.")


def judge_push(d: str, args: list[str], env: dict) -> str:
    rc, _ = git(d, "rev-parse", "--verify", "--quiet", TRUNK + "^{commit}")
    if rc != 0:
        return ""               # ствола нет — отставание судить не по чему
    src, _why = push_source(d, args)
    if not src:
        return ""
    _, head = git(d, "rev-parse", "--verify", "--quiet", src + "^{commit}")
    if not head:
        return ""
    rc, base = git(d, "merge-base", head, TRUNK)
    if rc != 0 or not base:
        return ""
    lag = sorted(checks_at(d, TRUNK) - checks_at(d, head) - checks_at(d, base))
    if not lag or env.get(BYPASS_PUSH) == "1":
        return ""
    _, top = git(d, "rev-parse", "--show-toplevel")
    shown = ", ".join(lag[:6]) + (f" и ещё {len(lag) - 6}" if len(lag) > 6 else "")
    return (f"`git push` из {top}: база полосы НЕ ЗНАЕТ проверок ствола — {len(lag)} "
            f"({shown}). Они заведены на {TRUNK} после развилки; наборы полосы "
            "печатают «рассмотрено N» по тому, что нашли, и зелёный на меньшем N "
            "неотличим от зелёного на полном (ws#717). Прежде отправки — влить ствол в "
            "ветку (git-operator) и прогнать наборы. Обход, если он осознан: "
            f"`{BYPASS_PUSH}=1 git push …` — и строка об этом в возврате.")


RULES = {"stash": judge_stash, "push": judge_push}


def judge(command: str, cwd: str) -> list[str]:
    denials: list[str] = []
    for argv, here, pre in commands(command, cwd):
        sub, d, args, env = parse_git(argv, here)
        env = {**pre, **env}
        rule = RULES.get(sub)
        if rule:
            msg = rule(d, args, env)
            if msg:
                denials.append(msg)
    return denials


def main() -> int:
    try:
        ev = json.load(sys.stdin)
    except Exception:  # noqa: BLE001
        sys.stderr.write("bash-guard СЛОМАН: вход не разобран как JSON — команда НЕ судилась "
                         "(пропущена). → tooling-maintainer\n")
        return 1
    if ev.get("tool_name") not in (None, "Bash"):
        return 0
    ti = ev.get("tool_input") or {}
    command = ti.get("command") or ""
    cwd = ti.get("cwd") or ev.get("cwd") or os.getcwd()
    try:
        denials = judge(command, cwd)
    except ValueError as e:
        # Незакрытая кавычка и подобное: команду не разобрать — не судим, но говорим.
        sys.stderr.write(f"bash-guard: команда не разобрана ({e}) — не судилась. "
                         "Запреты stash в общей копии и push с отставшей базой к ней не применены.\n")
        return 1
    if not denials:
        return 0
    sys.stderr.write("╔══ bash-guard: команда НЕ исполнена ══════════════════════════════\n")
    for d in denials:
        sys.stderr.write(f"║ {d}\n")
    sys.stderr.write("╚═════════════════════════════════════════════════════════════════\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
