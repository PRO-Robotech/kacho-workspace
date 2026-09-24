#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""heavy-guard — тяжёлая команда без слота памяти не запускается.

Предмет: решение владельца 2026-09-24 «контроль за оперативной памятью не должна
переваливать за 45гб». Слот (`scripts/heavy-slot.sh`) держит потолок, только если
через него идут ВСЕ тяжёлые прогоны; команда в обход него — ровно та полоса,
которая «видела, что памяти хватает». Страж стоит на PreToolUse(Bash) и отказывает
такой команде с текстом, как запустить её правильно.

Судит РАЗОБРАННУЮ команду, а не текст: строка режется на простые команды по
управляющим операторам вне кавычек (включая `$(…)`, обратные кавычки, тела
`bash -c` с любыми слитными флагами — `-lc`, `-ec` — и heredoc, поданный оболочке),
прочие тела heredoc и комментарии выбрасываются, у каждой простой команды
снимаются присваивания и обёртки (`timeout`, `env`, `xargs`, `nice`, `sudo`,
`find -exec`, …), переменные строки (`R=-race; go test $R`, `export GOFLAGS=…`)
подставляются. Поэтому «go test -race» в сообщении коммита, в grep-образце или в
записываемом heredoc-файле не находка, а `cd x && timeout 900 go test -race ./...`
— находка.

Тяжесть make-цели и скрипта ВЫВОДИТСЯ из дерева, а не из словаря: страж читает
Makefile (цель, её предпосылки, `$(MAKE)`-вызовы, include, переменные файла и
вызова) и текст скрипта (`bash x.sh`, `./x.sh`, `source x.sh`) и судит их строки
тем же разбором. Словарь шёл бы в одну сторону — цель, которой в нём нет, проходила
молча (опыт ws#832: `make -C deploy build-services`, `bash deploy/kind/create-
cluster.sh`). make страж НЕ зовёт: `make -n` исполняет строки рецепта с `$(MAKE)`
по-настоящему (замер 2026-09-24: `make -n -C deploy dev-up` поднял узел kind), и
та же семантика учтена в разборе `-n/-t/-q`. Класс выведенного — с наибольшим
бюджетом из найденных (RANK — порядок бюджетов слота, сверяет prove.sh).

Команда слота (`heavy-slot.sh <класс> -- …`) законна целиком: хвост после `--` —
его аргументы. В строке команды она не несёт ручек HEAVY_SLOT_* кроме WAIT_S,
POLL_S и потолка: свой каталог, синтетический meminfo, бюджет и ограничитель —
для проб слота, в живом вызове они снимают очередь или предел.

Исходы: 0 без вывода — пропуск; 2 и текст в stderr — отказ (текст видит тот, кто
звал Bash: исполнитель, у диспетчера Bash нет); 0 и additionalContext «СЛОМАН» —
страж не смог судить. Последнее — пропуск, а не отказ, намеренно: сломанный страж,
отказывающий всему, остановил бы каждую полосу на любой команде; но молчать о
поломке он не вправе, и слово доходит до модели.

Граница: `$(command -v go)`, текст в `| bash`, программа или каталог в переменной,
присвоенной не в судимой строке (`cd "$d" && ./run.sh`), переменная make из
`$(shell …)` (страж её не исполняет — пусто), `python3 -c "os.system(…)"`,
`go env -w`, docker API без клиента (testcontainers, compose — их держит слот).
"""

import glob
import json
import os
import re
import shlex
import sys

# Имена классов — те же, что у слота (`heavy-slot.sh --classes`), в обе стороны, и
# в порядке убывания бюджета: из нескольких найденных берётся первый (сверяет prove.sh).
RANK = ("go-race", "ci-local", "integration", "lint", "stand", "docker", "newman")

# Скрипт, чей класс не выводится из текста: ci-local — исключительный класс слота
# (golangci-lint по одному), а по тексту вышел бы go-race; newman-parallel зовёт
# run.sh наборов из вычисляемого каталога (`cd "$d" && ./scripts/run.sh`). Запись
# без файла в дереве продукта находит prove.sh.
SCRIPTS = {"ci-local.sh": "ci-local", "newman-parallel.sh": "newman"}

WRAPPERS_NOARG = {"nohup", "command", "exec", "time", "setsid", "builtin", "!", "{",
                  "do", "then", "else", "elif", "if", "while", "until"}
# обёртка → опции, берущие значение отдельным словом
WRAPPERS_OPTS = {
    "timeout": {"-s", "--signal", "-k", "--kill-after"},
    "nice": {"-n", "--adjustment"},
    "ionice": {"-c", "-n", "-p", "--class", "--classdata"},
    "stdbuf": {"-i", "-o", "-e"},
    "sudo": {"-u", "-g", "-C", "-D", "-h", "-p", "-r", "-t", "-U"},
    "xargs": {"-a", "-d", "-E", "-I", "-L", "-n", "-P", "-s", "--arg-file", "--delimiter",
              "--max-args", "--max-procs", "--max-lines", "--max-chars"},
    "npx": {"-p", "--package"},
    "chrt": set(),
    "taskset": set(),
}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
DECLARE = {"export", "declare", "typeset", "readonly", "local"}
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_.-]*)\1")
VARREF = re.compile(r"\$(?:\{([A-Za-z_][A-Za-z0-9_]*)(?::?-([^}]*))?\}|([A-Za-z_][A-Za-z0-9_]*))")
TRUE = {"1", "t", "T", "true", "TRUE", "True"}  # strconv.ParseBool — разбор флагов go

CAP_GIB = 45  # решение владельца 2026-09-24; слот держит то же число сам (CAP_MIB)


def bad_knob(e):
    """Ручка слота, которой нет места в строке команды: всё, кроме ожидания и
    потолка не выше 45 ГиБ."""
    n, _, v = e.partition("=")
    if not n.startswith("HEAVY_SLOT_") or n in ("HEAVY_SLOT_WAIT_S", "HEAVY_SLOT_POLL_S"):
        return False
    cap = {"HEAVY_SLOT_LIMIT_GIB": CAP_GIB, "HEAVY_SLOT_LIMIT_MIB": CAP_GIB * 1024}.get(n)
    return not (cap and v.isdigit() and int(v) <= cap)


MAX_LEVEL = 5          # вложенность файлов: скрипт → скрипт → make → …
MAX_READS = 80         # файлов за один вызов стража
MAX_BYTES = 1 << 20


class Ctx:
    """Состояние одного суждения: прочитанные файлы и их итог."""

    def __init__(self):
        self.reads = 0
        self.files = {}   # путь → множество классов (None — в работе: цикл)
        self.makes = {}   # путь → разобранный Makefile


def strip_heredocs(text):
    """Тела heredoc — данные, а не команды: (текст без тел, [(строка, тело)])."""
    out, bodies, lines, i = [], [], text.split("\n"), 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        ends = [m.group(2) for m in HEREDOC.finditer(line) if "<<<" not in line[max(0, m.start() - 1):m.start() + 3]]
        i += 1
        for word in ends:
            body = []
            while i < len(lines) and lines[i].strip() != word:
                body.append(lines[i])
                i += 1
            i += 1
            bodies.append((line, "\n".join(body)))
    return "\n".join(out), bodies


def split_commands(text):
    """Режет строку на простые команды вне кавычек; тела `$(…)` и `…` — отдельно."""
    parts, cur, i, n = [], [], 0, len(text)
    quote = None
    while i < n:
        c = text[i]
        if quote == "'":
            cur.append(c)
            if c == "'":
                quote = None
            i += 1
            continue
        if c == "\\" and i + 1 < n:
            cur.append(text[i:i + 2])
            i += 2
            continue
        if c == "$" and text[i + 1:i + 2] == "(" and text[i + 2:i + 3] != "(":
            depth, j = 1, i + 2
            while j < n and depth:
                depth += {"(": 1, ")": -1}.get(text[j], 0)
                j += 1
            parts.extend(split_commands(text[i + 2:j - 1]))
            cur.append("__SUBST__")
            i = j
            continue
        if c == "`":
            j = text.find("`", i + 1)
            j = n if j < 0 else j
            parts.extend(split_commands(text[i + 1:j]))
            cur.append("__SUBST__")
            i = j + 1
            continue
        if quote == '"':
            cur.append(c)
            if c == '"':
                quote = None
            i += 1
            continue
        if c in "'\"":
            quote = c
            cur.append(c)
            i += 1
            continue
        if c == "#" and (not cur or cur[-1] in " \t"):
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c == "&" and (text[i - 1:i] in ("<", ">") or text[i + 1:i + 2] == ">"):
            cur.append(c)  # 2>&1, >&2, &>файл — перенаправление, а не фон
            i += 1
            continue
        if c in ";&|\n()":
            parts.append("".join(cur))
            cur = []
            i += 1
            continue
        cur.append(c)
        i += 1
    parts.append("".join(cur))
    return [p.strip() for p in parts if p.strip()]


REDIR_OP = re.compile(r"^(\d*|&)(<<<|<<-?|<>|>>|>\||<|>)&?$")
REDIR_WORD = re.compile(r"^(\d*|&)(<<<|<<-?|<>|>>|>\||<|>)&?\S")


def words(segment):
    """Слова простой команды без перенаправлений (`<<EOF`, `2>&1`, `> f`)."""
    try:
        ws = shlex.split(segment, posix=True)
    except ValueError:
        ws = segment.split()
    out, skip = [], False
    for w in ws:
        if skip:
            skip = False
        elif REDIR_OP.match(w):
            skip = True
        elif not REDIR_WORD.match(w):
            out.append(w)
    return out


def expand_words(ws, env):
    """Подставляет переменные, присвоенные раньше в той же строке, и умолчания `${X:-y}`."""
    known = dict(e.split("=", 1) for e in env)

    def sub(m):
        name = m.group(1) or m.group(3)
        if name in known:
            return known[name]
        return m.group(2) if m.group(2) is not None else m.group(0)  # ${X:-умолчание}
    out = []
    for w in ws:
        v = VARREF.sub(sub, w) if "$" in w else w
        out.extend(v.split() if v != w else [w])
    return out


def unwrap(argv):
    """Снимает присваивания и обёртки. Возвращает (присваивания, argv команды)."""
    env, i = [], 0
    while i < len(argv):
        w = argv[i]
        if ASSIGN.match(w):
            env.append(w)
            i += 1
            continue
        base = os.path.basename(w)
        if base in WRAPPERS_NOARG:
            i += 1
            continue
        if base == "env":
            i += 1
            while i < len(argv) and (argv[i].startswith("-") or ASSIGN.match(argv[i])):
                if ASSIGN.match(argv[i]):
                    env.append(argv[i])
                i += 2 if argv[i] in ("-u", "--unset", "-C", "--chdir") else 1
            continue
        if base in WRAPPERS_OPTS:
            opts, i = WRAPPERS_OPTS[base], i + 1
            while i < len(argv) and argv[i].startswith("-"):
                i += 2 if argv[i] in opts else 1
            if base == "timeout" and i < len(argv):
                i += 1  # длительность
            if base in ("chrt", "taskset") and i < len(argv):
                i += 1  # приоритет / маска
            continue
        break
    return env, argv[i:]


def shell_args(args):
    """Разбор `bash [опции] …`: (строка -c | None, скрипт | None, его аргументы, stdin).

    -c узнаётся и слитным (`-lc`, `-ec`, `-xc`); значения -o/-O/+o, --rcfile —
    отдельным словом; строка команды — первое слово после опций.
    """
    k, has_c, stdin = 0, False, False
    while k < len(args):
        a = args[k]
        if a == "--":
            k += 1
            break
        if a in ("--rcfile", "--init-file"):
            k += 2
            continue
        if a.startswith("--"):
            k += 1
            continue
        if len(a) > 1 and a[0] in "-+":
            has_c = has_c or (a[0] == "-" and "c" in a[1:])
            stdin = stdin or (a[0] == "-" and "s" in a[1:])
            k += 1 + a[1:].count("o") + a[1:].count("O")
            continue
        break
    rest = args[k:]
    if has_c:
        return (rest[0] if rest else None), None, [], False
    if stdin or not rest:
        return None, None, [], True
    return None, rest[0], rest[1:], False


def flag_value(args, names):
    """Значения флага в формах `-f v`, `-f=v`, `--f v`, `--f=v`."""
    vals = []
    for k, a in enumerate(args):
        for nm in names:
            if a == nm and k + 1 < len(args):
                vals.append(args[k + 1])
            elif a.startswith(nm + "="):
                vals.append(a[len(nm) + 1:])
    return vals


def go_test_class(args, env):
    """args — после `go test`."""
    goflags = " ".join(e.split("=", 1)[1] for e in env if e.startswith("GOFLAGS="))
    allargs = args + goflags.split()
    tags = ",".join(flag_value(allargs, ("-tags", "--tags")))
    if "integration" in re.split(r"[,\s]+", tags):
        return "integration"
    for a in allargs:
        if a in ("-race", "--race"):
            return "go-race"
        if a.startswith(("-race=", "--race=")) and a.split("=", 1)[1] in TRUE:
            return "go-race"
    return None


def repo_top(path):
    p = os.path.abspath(path)
    while True:
        if os.path.exists(os.path.join(p, ".git")):
            return p
        up = os.path.dirname(p)
        if up == p:
            return None
        p = up


def push_runs_ci_local(path):
    """git push тяжёл там, где pre-push клона зовёт ci-local.sh (признак — дерево)."""
    top = repo_top(path)
    if not top or not os.path.isfile(os.path.join(top, "scripts", "ci-local.sh")):
        return False
    try:
        with open(os.path.join(top, "scripts", "hooks", "pre-push"), encoding="utf-8") as fh:
            return "ci-local.sh" in fh.read()
    except OSError:
        return False


DOCKER_GLOBAL_VALUE = {"--context", "-c", "-H", "--host", "--config", "-l", "--log-level",
                       "--tlscacert", "--tlscert", "--tlskey"}
DOCKER_HEAVY = {"run", "create", "start", "build"}
COMPOSE_HEAVY = {"up", "run", "build", "start", "create"}


def docker_class(args, ctx, level):
    """args — после `docker`. Класс тоньше `docker`, если внутри go test."""
    i = 0
    while i < len(args) and args[i].startswith("-"):
        i += 2 if args[i] in DOCKER_GLOBAL_VALUE else 1
    rest = args[i:]
    if not rest:
        return None
    sub, tail = rest[0], rest[1:]
    if sub in ("container", "image", "buildx", "builder") and tail:
        sub, tail = tail[0], tail[1:]
    if sub == "compose":
        heavy = any(t in COMPOSE_HEAVY for t in tail if not t.startswith("-"))
        return "docker" if heavy else None
    if sub not in DOCKER_HEAVY:
        return None
    if sub == "run":
        # Команда контейнера — хвост после образа, либо строка `sh -c '…'` в нём.
        # Её класс уточняет бюджет: go test -race в golang — это go-race, а с
        # docker.sock внутри — integration (testcontainers ходят в dockerd машины).
        env = [a.split("=", 1)[1] if a.startswith("--env=") else a for a in tail if "GOFLAGS=" in a]
        sock = any("docker.sock" in a for a in tail)
        for k, a in enumerate(tail):
            if a == "go" and tail[k + 1:k + 2] == ["test"]:
                inner = go_test_class(tail[k + 2:], env)
            elif a in SHELLS:
                cmd, _, _, _ = shell_args(tail[k + 1:])
                if cmd is None:
                    continue
                inner = best(classes_in(cmd, None, ctx, level))
            else:
                continue
            if inner in ("go-race", "integration"):
                return "integration" if sock else inner
    return "docker"


def best(classes):
    """Из найденных — с наибольшим бюджетом."""
    for c in RANK:
        if c in classes:
            return c
    return None


def resolve(path, cwd, alt):
    """Путь к файлу из слова команды; None — не представим (переменная, подстановка)."""
    if not path or "$" in path or "__SUBST__" in path:
        return None
    p = os.path.expanduser(path)
    bases = [""] if os.path.isabs(p) else [cwd or os.getcwd()] + ([alt] if alt else [])
    for b in bases:
        q = os.path.normpath(os.path.join(b, p))
        if os.path.isfile(q):
            return q
    return None


def read_text(p, ctx):
    if ctx.reads >= MAX_READS:
        return None
    ctx.reads += 1
    try:
        if os.path.getsize(p) > MAX_BYTES:
            return None
        with open(p, "rb") as fh:
            data = fh.read()
    except OSError:
        return None
    if b"\0" in data[:4096]:
        return None
    return data.decode("utf-8", "replace")


def file_classes(path, cwd, ctx, level, alt, shell):
    """Классы скрипта по его тексту; shell=False — только если это скрипт оболочки."""
    p = resolve(path, cwd, alt)
    if p is None or level >= MAX_LEVEL:
        return set()
    if p in ctx.files:
        return ctx.files[p] or set()
    ctx.files[p] = None
    text = read_text(p, ctx)
    got = set()
    if text is not None:
        first = text.split("\n", 1)[0]
        is_sh = shell or p.endswith((".sh", ".bash")) or (
            first.startswith("#!") and re.search(r"\b(ba|z|da|k)?sh\b", first))
        if is_sh:
            got = classes_in(text, cwd, ctx, level + 1, os.path.dirname(p))
    ctx.files[p] = got
    return got


# ── make: разбор Makefile без запуска make ────────────────────────────────────
MK_ASSIGN = re.compile(r"^(?:(?:export|override|private)\s+)*([A-Za-z0-9_.-]+)\s*(:::=|::=|:=|\?=|\+=|!=|=)\s*(.*)$")
MK_RULE = re.compile(r"^([^:=#\s][^:=#]*?)\s*::?(?!=)\s*(.*)$")
MK_DEFINE = re.compile(r"^(?:(?:export|override)\s+)?define\s+([A-Za-z0-9_.-]+)\s*(=|:=|::=|\?=|\+=)?\s*$")
MK_DIRECTIVES = {"ifeq", "ifneq", "ifdef", "ifndef", "else", "endif"}
MK_SILENT_FUNCS = {"shell", "error", "warning", "info", "eval", "file", "origin", "flavor", "value"}
MK_DRY = {"--dry-run", "--just-print", "--recon", "--touch", "--question"}


def mk_strip_comment(line):
    m = re.search(r"(?<!\\)#", line)
    return line[:m.start()] if m else line


def parse_makefile(p, ctx):
    """(присваивания [(имя, оп, значение)], правила {цель: [предпосылки, рецепт]},
    цели по порядку, include) — без раскрытия."""
    if p in ctx.makes:
        return ctx.makes[p]
    text = read_text(p, ctx)
    if text is None:
        ctx.makes[p] = None
        return None
    phys, logical, i = text.split("\n"), [], 0
    while i < len(phys):
        line = phys[i]
        i += 1
        while line.endswith("\\") and i < len(phys):
            nxt = phys[i]
            i += 1
            line = line[:-1] + " " + (nxt[1:] if nxt.startswith("\t") else nxt.lstrip())
        logical.append(line)
    assigns, rules, order, includes, cur, define = [], {}, [], [], None, None
    for line in logical:
        if define is not None:
            if line.strip() == "endef":
                assigns.append((define[0], define[1], "\n".join(define[2])))
                define = None
            else:
                define[2].append(line)
            continue
        if line.startswith("\t"):
            if cur:
                for t in cur:
                    rules[t][1].append(line[1:])
            continue
        s = mk_strip_comment(line).strip()
        if not s:
            continue
        head = s.split()[0]
        if head in MK_DIRECTIVES:
            continue
        m = MK_DEFINE.match(s)
        if m:
            define, cur = [m.group(1), m.group(2) or "=", []], None
            continue
        if head in ("include", "-include", "sinclude"):
            includes.append(s[len(head):].strip())
            cur = None
            continue
        m = MK_ASSIGN.match(s)
        if m:
            assigns.append(m.groups())
            cur = None
            continue
        m = MK_RULE.match(s)
        if not m:
            cur = None
            continue
        rest, inline = m.group(2), None
        if ";" in rest:
            rest, inline = rest.split(";", 1)
        ma = MK_ASSIGN.match(rest.strip())
        if ma and inline is None:
            assigns.append(ma.groups())  # переменная цели — в общий словарь
            cur = None
            continue
        cur = m.group(1).split()
        for t in cur:
            r = rules.setdefault(t, [[], []])
            r[0].extend(w for w in rest.split() if w != "|")
            if inline:
                r[1].append(inline)
            if not t.startswith(".") and "%" not in t and t not in order:
                order.append(t)
    ctx.makes[p] = (assigns, rules, order, includes)
    return ctx.makes[p]


def mk_expand(s, vs, auto=None, depth=0):
    """Раскрытие переменных make текстом: $(X), ${X}, $X, $$; функции — их аргументы."""
    if depth > 10 or "$" not in s:
        return s
    out, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if c != "$" or i + 1 >= n:
            out.append(c)
            i += 1
            continue
        nx = s[i + 1]
        if nx == "$":
            out.append("$")
            i += 2
            continue
        if nx in "({":
            close, j, lvl = ")" if nx == "(" else "}", i + 2, 1
            while j < n and lvl:
                if s[j] == nx:
                    lvl += 1
                elif s[j] == close:
                    lvl -= 1
                j += 1
            out.append(mk_ref(s[i + 2:j - 1], vs, auto, depth))
            i = j
            continue
        out.append((auto or {}).get(nx, "") if nx in "@<^+*?%" else mk_expand(vs.get(nx, ""), vs, auto, depth + 1))
        i += 2
    return "".join(out)[:200000]


def mk_ref(inner, vs, auto, depth):
    name, _, args = inner.partition(" ")
    if not args and "," not in inner:
        vn = inner.split(":", 1)[0]
        if vn and vn[0] in "@<^+*?%":
            return (auto or {}).get(vn[0], "")
        return mk_expand(vs.get(vn, ""), vs, auto, depth + 1)
    if name in MK_SILENT_FUNCS:
        return ""
    if name == "call":
        parts = mk_args(args)
        bound = dict(vs, **{str(k): mk_expand(a, vs, auto, depth + 1) for k, a in enumerate(parts) if k})
        return mk_expand(vs.get(parts[0].strip(), ""), bound, auto, depth + 1)
    return mk_expand(" ".join(mk_args(args)), vs, auto, depth + 1)


def mk_args(s):
    """Аргументы функции make: запятые верхнего уровня, не внутри $(…)."""
    parts, cur, lvl = [], [], 0
    for c in s:
        if c in "({":
            lvl += 1
        elif c in ")}":
            lvl -= 1
        if c == "," and lvl == 0:
            parts.append("".join(cur))
            cur = []
            continue
        cur.append(c)
    parts.append("".join(cur))
    return parts


def make_class(env, args, cwd, ctx, level):
    """Класс вызова make: рецепты целей и их предпосылок, прочитанные из Makefile."""
    dirs, files, goals, over, dry, k = [], [], [], {}, False, 0
    for e in env:
        n, v = e.split("=", 1)
        if n == "MAKEFLAGS" and re.match(r"^-?[a-zA-Z]*[ntq]", v.split(" ")[0] if v else ""):
            dry = True
    while k < len(args):
        a = args[k]
        nxt = args[k + 1] if k + 1 < len(args) else ""
        if a in ("-C", "--directory"):
            dirs.append(nxt)
            k += 2
            continue
        if a in ("-f", "--file", "--makefile"):
            files.append(nxt)
            k += 2
            continue
        if a.startswith(("--directory=", "--file=", "--makefile=")):
            (dirs if a.startswith("--directory=") else files).append(a.split("=", 1)[1])
        elif a.startswith("-C") and len(a) > 2:
            dirs.append(a[2:])
        elif a.startswith("-f") and len(a) > 2:
            files.append(a[2:])
        elif a in ("-I", "-o", "-W", "--include-dir", "--old-file", "--assume-old",
                   "--what-if", "--new-file", "--assume-new"):
            k += 1
        elif a in ("-j", "-l", "--jobs", "--load-average") and nxt.replace(".", "").isdigit():
            k += 1
        elif a in MK_DRY or (a.startswith("-") and not a.startswith("--") and set(a[1:]) & set("ntq")):
            dry = True
        elif not a.startswith("-"):
            if "=" in a:
                over[a.split("=", 1)[0]] = a.split("=", 1)[1]
            else:
                goals.append(a)
        k += 1
    d = cwd or os.getcwd()
    for x in dirs:
        if "$" in x or "__SUBST__" in x:
            return None
        d = os.path.normpath(os.path.join(d, os.path.expanduser(x)))
    mfiles = [os.path.normpath(os.path.join(d, f)) for f in files] or \
        [os.path.join(d, f) for f in ("GNUmakefile", "makefile", "Makefile") if os.path.isfile(os.path.join(d, f))][:1]
    if not mfiles or level >= MAX_LEVEL:
        return None
    vs = {"MAKE": "make", "CURDIR": d, "SHELL": "/bin/sh"}
    vs.update(e.split("=", 1) for e in env)
    rules, default, seen_inc = {}, [], set()

    def load(p):
        if p in seen_inc:
            return
        seen_inc.add(p)
        pm = parse_makefile(p, ctx)
        if pm is None:
            return
        assigns, prules, order, includes = pm
        for name, op, val in assigns:
            if name in over or (op == "?=" and name in vs):
                continue
            if op == "+=":
                vs[name] = (vs.get(name, "") + " " + val).strip()
            elif op == "!=":
                vs[name] = ""
            elif op in (":=", "::=", ":::="):
                vs[name] = mk_expand(val, vs)
            else:
                vs[name] = val
        for t, (pre, rec) in prules.items():
            for tt in (mk_expand(t, vs).split() if "$" in t else [t]):
                r = rules.setdefault(tt, [[], []])
                r[0].extend(pre)
                r[1].extend(rec)
        default.extend(t for t in order if not default)
        for inc in includes:
            for w in mk_expand(inc, vs).split():
                for q in sorted(glob.glob(os.path.join(d, w))):
                    load(os.path.normpath(q))

    for mf in mfiles:
        load(mf)
    vs.update(over)
    found, visited = set(), set()

    def walk(t):
        if t in visited or t not in rules:
            return
        visited.add(t)
        pre, rec = rules[t]
        pre = [w for p in pre for w in mk_expand(p, vs).split()]
        for p in pre:
            walk(p)
        auto = {"@": t, "<": pre[0] if pre else "", "^": " ".join(pre), "+": " ".join(pre), "?": " ".join(pre)}
        for raw in rec:
            body = raw.lstrip()
            plus = body.lstrip("@-").startswith("+")
            if dry and not plus and "$(MAKE)" not in raw and "${MAKE}" not in raw:
                continue
            line = mk_expand(body, vs, auto).lstrip("@-+ \t")
            found.update(classes_in(line, d, ctx, level + 1, d, ["MAKEFLAGS=n"] if dry else []))

    for g in goals or default[:1]:
        walk(mk_expand(g, vs))
    return best(found)


def classify_argv(env, argv, cwd, ctx, level, alt):
    """Класс простой команды или None."""
    if not argv:
        return None
    base = os.path.basename(argv[0])
    args = argv[1:]
    if base == "heavy-slot.sh":
        return None
    if base in SHELLS:
        cmd, script, _, _ = shell_args(args)
        if cmd is not None:
            return best(classes_in(cmd, cwd, ctx, level, alt, env))
        if script is None or os.path.basename(script) == "heavy-slot.sh":
            return None
        if os.path.basename(script) in SCRIPTS:
            return SCRIPTS[os.path.basename(script)]
        return best(file_classes(script, cwd, ctx, level, alt, True))
    if base in (".", "source"):
        return best(file_classes(args[0], cwd, ctx, level, alt, True)) if args else None
    if base == "eval":
        return best(classes_in(" ".join(args), cwd, ctx, level, alt, env))
    if base in ("make", "gmake"):
        return make_class(env, args, cwd, ctx, level)
    if base in SCRIPTS:
        return SCRIPTS[base]
    if base == "find":
        for k, a in enumerate(args):
            if a in ("-exec", "-execdir", "-ok", "-okdir"):
                sub = []
                for w in args[k + 1:]:
                    if w in (";", "+"):
                        break
                    sub.append(w)
                c = classify_argv(env, sub, cwd, ctx, level, alt)
                if c:
                    return c
        return None
    if base == "go" and args[:1] == ["test"]:
        return go_test_class(args[1:], env)
    if base == "golangci-lint" and "run" in args:
        return "lint"
    if base in ("govulncheck", "gosec"):
        return "lint"
    if base == "docker":
        return docker_class(args, ctx, level)
    if base == "docker-compose" and any(a in COMPOSE_HEAVY for a in args):
        return "docker"
    if base == "kind" and args[:2] == ["create", "cluster"]:
        return "stand"
    if base == "helm" and args[:1] and args[0] in ("install", "upgrade"):
        return "stand"
    if base == "newman" and args[:1] == ["run"]:
        return "newman"
    if base == "git":
        k, where = 0, None
        while k < len(args) and args[k].startswith("-"):
            if args[k] == "-C" and k + 1 < len(args):
                where = args[k + 1]
                k += 2
            elif args[k] in ("-c", "--git-dir", "--work-tree", "--namespace"):
                k += 2
            else:
                k += 1
        if args[k:k + 1] == ["push"] and "--no-verify" not in args:
            base_dir = cwd or os.getcwd()
            path = os.path.join(base_dir, os.path.expanduser(where)) if where else base_dir
            if push_runs_ci_local(path):
                return "ci-local"
        return None
    if "/" in argv[0]:
        return best(file_classes(argv[0], cwd, ctx, level, alt, False))
    return None


def scan(text, cwd, ctx, level=0, alt=None, env0=None):
    """Простые команды строки по порядку: ("heavy", класс, env, argv) либо
    ("knob", присваивание, env, argv) — ручка слота в строке команды."""
    cur, line_env = cwd, list(env0 or [])
    stripped, bodies = strip_heredocs(text)
    for intro, body in bodies:
        # heredoc, поданный оболочке (`bash <<EOF`, `sh -s <<EOF`), — её команды
        for seg in split_commands(intro):
            _, argv = unwrap(words(seg))
            if argv and os.path.basename(argv[0]) in SHELLS and shell_args(argv[1:])[3]:
                yield from scan(body, cur, ctx, level, alt, line_env)
                break
    loops = {}
    for ws in (v for seg in split_commands(stripped) for v in loop_variants(words(seg), loops, cur)):
        env, argv = unwrap(expand_words(ws, line_env))
        if not argv:
            line_env.extend(env)  # `R=-race` отдельной командой
            continue
        base = os.path.basename(argv[0])
        if base in ("cd", "pushd") and len(argv) > 1 and "__SUBST__" not in argv[1] and "$" not in argv[1]:
            cur = os.path.join(cur or os.getcwd(), os.path.expanduser(argv[1]))
            continue
        if base in DECLARE:
            line_env.extend(a for a in argv[1:] if ASSIGN.match(a))
            continue
        allenv = line_env + env
        if level == 0 and slot_call(argv):
            for e in allenv:
                if bad_knob(e):
                    yield "knob", e, allenv, argv
                    break
            continue
        inline = shell_args(argv[1:])[0] if base in SHELLS else " ".join(argv[1:]) if base == "eval" else None
        if level == 0 and inline:
            yield from (h for h in scan(inline, cur, ctx, 0, alt, allenv) if h[0] == "knob")
        c = classify_argv(allenv, argv, cur, ctx, level, alt)
        if c:
            yield "heavy", c, allenv, argv


def loop_variants(ws, loops, cwd):
    """`for V in <слова и шаблоны>` запоминает значения V; команда с $V — по разу на
    значение (`for sh in e2e/*.sh; do bash "$sh"` — это каждый из скриптов)."""
    if ws[:1] == ["for"] and len(ws) > 3 and ws[2] == "in":
        vals = []
        for w in ws[3:]:
            hits = sorted(glob.glob(os.path.join(cwd or os.getcwd(), w))) if re.search(r"[*?[]", w) else []
            vals.extend(hits or [w])
        loops[ws[1]] = vals[:50]
        return []
    out = [ws]
    for var, vals in loops.items():
        ref = re.compile(r"\$(\{%s\}|%s\b)" % (var, var))
        if any(ref.search(w) for w in ws):
            out = [[ref.sub(lambda _m, v=v: v, w) for w in o] for o in out for v in vals][:100]
    return out


def slot_call(argv):
    base = os.path.basename(argv[0])
    if base == "heavy-slot.sh":
        return True
    if base in SHELLS:
        script = shell_args(argv[1:])[1]
        return bool(script) and os.path.basename(script) == "heavy-slot.sh"
    return False


def classes_in(text, cwd, ctx, level=0, alt=None, env0=None):
    return {c for kind, c, _, _ in scan(text, cwd, ctx, level, alt, env0) if kind == "heavy"}


def find_heavy(text, cwd, ctx=None):
    for hit in scan(text, cwd, ctx or Ctx()):
        return hit
    return None


REDIRECT = re.compile(r"^(\d*|&)(>>?|<)&?[\w./-]*$")


def show(ws):
    return " ".join(w if REDIRECT.match(w) else shlex.quote(w) for w in ws)


def clip(s, n):
    return s if len(s) <= n else s[:n] + " …"


def deny(cls, env, argv, slot):
    shown = show(argv)
    fixed = clip(" ".join([show(env), slot, cls, "--", shown]).strip(), 400)
    sys.stderr.write(
        "HEAVY-GUARD: отказ — тяжёлая команда без слота памяти (класс «%s»).\n"
        "  найдено: %s\n"
        "Машина держит ≤ 45 ГиБ на всё (решение владельца 2026-09-24); тяжёлое входит только\n"
        "через слот: он ждёт памяти, а не отнимает её у соседних полос, и держит команду\n"
        "под жёстким пределом бюджета класса.\n"
        "Как запустить правильно (остальная строка — как была):\n"
        "  %s\n"
        "  · ожидание слота — до 30 мин: долгий прогон — с run_in_background: true;\n"
        "  · классы и бюджеты: %s --classes · кто занял: %s --status;\n"
        "  · коды: 75 — слот не выдан, 76 — оборвано пределом памяти: оба «не выполнилось»,\n"
        "    не красное; иначе — код самой команды.\n"
        "Быстрое по своим пакетам (go test без -race, go vet, gofmt) слота не требует.\n"
        % (cls, clip(shown, 300), fixed, slot, slot))
    sys.exit(2)


def deny_knob(knob, env, argv):
    keep = [e for e in env if not bad_knob(e)]
    fixed = clip(" ".join([show(keep), show(argv)]).strip(), 400)
    sys.stderr.write(
        "HEAVY-GUARD: отказ — вызов слота несёт ручку «%s».\n"
        "Ручки HEAVY_SLOT_* кроме WAIT_S, POLL_S и потолка (не выше 45 ГиБ) — для проб слота\n"
        "над синтетическим meminfo (scripts/heavy-slot-inject.sh): в живом вызове свой каталог\n"
        "уводит из общей очереди, синтетический meminfo снимает потолок, бюджет и ограничитель —\n"
        "предел класса (решение владельца 2026-09-24: ≤ 45 ГиБ на машину).\n"
        "Как запустить правильно:\n"
        "  %s\n" % (knob, fixed))
    sys.exit(2)


def broken(why):
    msg = ("HEAVY-GUARD СЛОМАН: %s. Тяжёлые команды этим вызовом НЕ проверялись — это не "
           "«чисто». Тяжёлое (go test -race, integration, ci-local, golangci-lint, docker run, "
           "стенд, newman) всё равно запускай через scripts/heavy-slot.sh <класс> -- <команда>; "
           "починка — tooling-maintainer." % why)
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                             "additionalContext": msg}}, ensure_ascii=False))
    sys.exit(0)


def main():
    if sys.argv[1:] == ["--classes"]:
        print("\n".join(RANK))
        return
    if sys.argv[1:] == ["--scripts"]:
        print("\n".join(sorted(SCRIPTS)))
        return
    if sys.argv[1:2] == ["--classify"] and len(sys.argv) == 4:
        # --classify <команда> <cwd> — класс строки для переписи дерева (prove.sh)
        hit = find_heavy(sys.argv[2], sys.argv[3])
        print(hit[1] if hit and hit[0] == "heavy" else "-")
        return
    try:
        data = json.load(sys.stdin)
    except (ValueError, OSError) as exc:
        broken("вход хука не разобран как JSON (%s)" % exc)
    if data.get("tool_name") not in (None, "Bash"):
        return
    cmd = (data.get("tool_input") or {}).get("command")
    if not isinstance(cmd, str):
        broken("у вызова Bash нет tool_input.command")
    ws = os.environ.get("CLAUDE_PROJECT_DIR") or os.path.dirname(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    slot = os.path.join(ws, "scripts", "heavy-slot.sh")
    hit = find_heavy(cmd, data.get("cwd") or os.getcwd())
    if hit and hit[0] == "knob":
        deny_knob(hit[1], hit[2], hit[3])
    if hit:
        deny(hit[1], hit[2], hit[3], slot)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001 — страж обязан сказать о своей поломке
        broken("%s: %s" % (type(exc).__name__, exc))
