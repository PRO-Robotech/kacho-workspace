#!/usr/bin/env python3
"""check-01 — задание конвейера продукта, которое ставит Go, достигает команды Go.

ЧТО УТВЕРЖДАЕТ (ws#1099). В стволах `kacho` и `kaname` каждое задание с шагом
`uses: actions/setup-go` хотя бы одним ИСПОЛНЯЕМЫМ шагом достигает команды Go:
`go`, `gofmt`, `golangci-lint`, `govulncheck`, `gosec`, `staticcheck` в позиции
команды либо `$(GO)` рецепта make. Задание с `setup-go` без единой такой команды —
находка с координатой `<репо>:<файл процесса>:<ключ задания>`.

ЦЕНА. Действие скачивается с codeload на шаге «Set up job», до первой команды
задания, и отказ скачивания роняет задание красным, которое о предмете изменения
ничего не говорит: «An action could not be found at the URI
'https://codeload.github.com/actions/setup-go/tar.gz/…'» и «Failed to download
archive … after 1 attempts» (kacho#3231, kacho#3244, kaname#815). Скачивание,
которому задание не нужно, — лишний жребий на красное.

ПРЕДМЕТ. Шаг `uses:` сравнивается без учёта регистра: владелец и имя репозитория
действия у хостинга регистронезависимы, и `Actions/Setup-Go@…` скачивается так
же. Скачивается он и под `if:` шага, поэтому такой шаг предмета не снимает;
задание с `if: false` не исполняется вовсе — оно не предмет и в переписи
считается отдельно.

ДОСТИЖИМОСТЬ — ТРАНЗИТИВНО, и формы названы, а не подразумеваются:
  * текст шага `run:` — команда Go в позиции команды (начало, `;`, `|`, `&&`,
    `||`, `(`, `$(`, обратная кавычка, `then`/`do`/`else`, `xargs`, `exec`, `env`,
    `time`, присваивания `ИМЯ=значение`); шаг с `if: false` не исполняется и не
    в счёт;
  * `make <цель>` и `$(MAKE) <цель>` — рецепт цели и её предпосылки, рекурсивно;
    каталог Makefile — `-C <кат>`, `--directory`, `--dir <кат>` той же команды,
    иначе ТЕКУЩИЙ каталог оболочки: `cd <кат>` действует до конца оболочки (шага
    `run:`, скрипта) и на следующих строках тоже, внутри `( … )` и `$( … )` — лишь
    до закрывающей скобки; у рецепта make каждая строка — своя оболочка; исходный
    каталог — `working-directory` шага либо `defaults.run`;
  * `${{ matrix.<ключ> }}` раскрывается СОЧЕТАНИЯМИ матрицы задания: произведение
    списков, минус `exclude`, плюс `include` (дополнение подходящих сочетаний либо
    новое сочетание) — так, как их строит хостинг;
  * скрипт, вызванный интерпретатором (`bash`, `sh`, `python3`, `node`) либо через
    `./` или `"$GITHUB_WORKSPACE/…"`, — его код, рекурсивно, в каталоге вызвавшего;
    `cd "$(dirname "$0")"` скрипта ведёт в его каталог; `bash -c '…'` и
    here-document, поданный `bash`/`sh`, — код;
  * у `.py` (файлом или here-document, поданным `python3`) вызов Go — список либо
    кортеж в КОДЕ, первым элементом которого строка `"go"` (`["go", "list", …]`):
    файл разбирается `ast`, и комментарий либо строка документации вызовом не
    являются;
  * локальное составное действие (`uses: ./<путь>`) — его `runs.steps`: и
    `setup-go` внутри него, и его шаги `run:`.

ЧИТАЕТСЯ КОД, А НЕ ТЕКСТ: разбор оболочки идёт по состояниям — комментарий,
одинарные и двойные кавычки, here-document. Текст в кавычках — одно слово и
позицией команды не является (`"…; go test"`), но подстановка `$( … )` внутри
двойных кавычек — код; тело here-document, поданного не оболочке (`cat <<E`), —
текст; слово `go` в тексте `echo`/`printf` — тоже текст. Дерево продукта читается
со ствола (`origin/main`, `git ls-tree` и `git cat-file`), а не с диска клона: клон
продукта рядом — чужая рабочая копия, переключённая на ветку полосы (ws#789).

ГРАНИЦЫ, НАЗВАННЫЕ ПРЯМО. Каждая из них краснит находкой с перечнем
неразрешённого, а не молчит: молчание о неразобранном неотличимо от чистоты.
  * `include` в Makefile не раскрывается, шаблонные цели (`%`) не сопоставляются;
  * цель, имя которой не раскрылось (переменная make, выражение вне матрицы,
    ключ, которого у сочетания нет), каталог, которого разбор не знает (`cd $X`),
    и скрипт, не найденный в дереве, вызовом Go не считаются;
  * скрипт на другом языке (`.mjs`, `.cjs`, `.js`, `.ts`) не читается: вызов Go
    из него не распознаётся, и он попадает в перечень неразрешённого;
  * условие шага или задания, отличное от литерала `false` (`if: ${{ … }}`),
    считается исполнимым: значение выражения до прогона не известно;
  * функции оболочки, `eval`, `source` чужого файла и `alias` не прослеживаются —
    их тело не читается как вызов.

ГДЕ ИЩЕТСЯ КЛОН — единственным способом, `scripts/lib/product_clone.py` (ws#1083):
`KACHO_HOME_<РЕПО>`, `KACHO_MONOREPO`, `<корень>/project/<репо>`, клоны канонической
копии для копии полосы под `tmp/`.

ИСХОДЫ: 0 — каждое задание с `setup-go` достигает Go; 1 — находка; 2 — клона или
ствола нет, процессов ноль либо заданий с `setup-go` ноль (предмет снят — снять и
проверку тем же изменением).
"""
import ast
import itertools
import os
import re
import sys

import yaml

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, "..", "lib"))
sys.path.insert(0, os.path.join(_HERE, "..", "docs-gate"))
from gate_root import gate_root  # noqa: E402
import product_clone  # noqa: E402
import _lib  # noqa: E402

NAME = "check-01-setup-go-job-calls-go"
REPOS = ("kacho", "kaname")
SETUP = "actions/setup-go"

GO_TOOLS = r"(?:go|gofmt|golangci-lint|govulncheck|gosec|staticcheck)"
# Позиция команды: начало, разделитель, подстановка, ключевое слово либо
# префикс-исполнитель; затем необязательные присваивания `ИМЯ=значение`.
CMD_POS = (r"(?:^|[\n;|&({!]|\$\(|`|(?<![\w-])(?:then|else|elif|do|exec|time|xargs|env|sudo|if|while|until)(?![\w-]))"
           r"\s*(?:[-+@]\s*)?(?:[A-Za-z_]\w*=\S*\s+)*")
GO_CALL = re.compile(CMD_POS + r"(?:" + GO_TOOLS + r"|\$\(GO\)|\$\{GO\})(?=\s|$|[;|&)])", re.M)
MAKE_CALL = re.compile(r"(?<![\w./-])(?:make|\$\(MAKE\)|\$\{MAKE\})(?P<args>(?:[ \t]+[^\s;|&()]+)*)")
SCRIPT_CALL = re.compile(
    CMD_POS + r"(?:(?:/usr/bin/env\s+)?(?:bash|sh|python3?|node)\s+(?:-[A-Za-z]+\s+)*)?"
    r"(?P<path>(?:\$\{?GITHUB_WORKSPACE\}?/|\./)?(?:[\w.-]+/)*[\w.-]+\.(?P<ext>sh|bash|py|mjs|cjs|js|ts))"
    r"(?![\w/-])", re.M)
FOREIGN_EXT = ("mjs", "cjs", "js", "ts")
MATRIX = re.compile(r"\$\{\{\s*matrix\.([\w.-]+)\s*\}\}")
EXPR = re.compile(r"\$\{\{(.*?)\}\}", re.S)
HEREDOC = re.compile(r"<<(-?)[ \t]*(?:'([^'\n]*)'|\"([^\"\n]*)\"|\\?([A-Za-z_][\w-]*))")
# Текст `echo`/`printf` — слова до конца простой команды (кавычки к этому моменту
# уже сняты разбором и стали одним словом-заполнителем).
ECHO_TEXT = re.compile(r"(?<![\w-])(?:echo|printf)(?![\w-])(?:[ \t]+[^\s;|&()`]+)*")
QUOTED = "\x01Q\x01"
SELF_DIR = re.compile(r"\$\(\s*dirname\s+\"?\$(?:0|\{0\}|\{BASH_SOURCE(?:\[0\])?\}|BASH_SOURCE)\"?\s*\)")
LEAD = re.compile(r"^\s*(?:[-+@!]\s*)*(?:(?:then|else|elif|do|if|while|until|exec|time|env|sudo)\s+)*"
                  r"(?:[A-Za-z_]\w*=\S*\s+)*")
SINGLE_WORD = re.compile(r"^[\w./${}\[\]:@%+=,~\x01-]*$")


def is_false(cond):
    """Литерал `false` условия (`false`, `${{ false }}`, `'false'`), иначе — исполнимо."""
    if cond is False:
        return True
    if not isinstance(cond, str):
        return False
    c = cond.strip()
    m = re.match(r"^\$\{\{(.*)\}\}$", c, re.S)
    if m:
        c = m.group(1).strip()
    return c.lower() == "false"


def py_reaches(body):
    """Код python зовёт Go: список/кортеж, первый элемент — строка "go". None — не разобран."""
    try:
        tree = ast.parse(body or "")
    except (SyntaxError, ValueError):
        return None
    for node in ast.walk(tree):
        if isinstance(node, (ast.List, ast.Tuple)) and node.elts:
            first = node.elts[0]
            if isinstance(first, ast.Constant) and first.value == "go":
                return True
    return False


def _sub_end(text, i):
    """Конец подстановки `$( … )`, открытой перед `i`: индекс за закрывающей скобкой."""
    depth, n = 1, len(text)
    while i < n:
        c = text[i]
        if c == "\\":
            i += 2
            continue
        if c == "'":
            j = text.find("'", i + 1)
            i = n if j < 0 else j + 1
            continue
        if c == '"':
            i = _dq(text, i + 1)[2]
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return n


def _dq(text, i):
    """Двойные кавычки с `i`: (содержимое, подстановки внутри, индекс за кавычкой)."""
    n, out, subs = len(text), [], []
    while i < n:
        c = text[i]
        if c == "\\" and i + 1 < n:
            out.append(text[i + 1] if text[i + 1] in '"$`\\' else text[i:i + 2])
            i += 2
            continue
        if c == '"':
            return "".join(out), subs, i + 1
        if text.startswith("$(", i) and not re.match(r"\$\([A-Za-z_]\w*\)", text[i:]):
            e = _sub_end(text, i + 2)
            subs.append(text[i + 2:e - 1])
            out.append(text[i:e])
            i = e
            continue
        if c == "`":
            j = text.find("`", i + 1)
            j = n if j < 0 else j
            subs.append(text[i + 1:j])
            out.append(text[i:j + 1])
            i = j + 1
            continue
        out.append(c)
        i += 1
    return "".join(out), subs, n


def _cmd_word(tail):
    """Первое слово последней простой команды в уже выписанном тексте."""
    seg = re.split(r"[;&|(\n]", tail)[-1]
    seg = LEAD.sub("", seg)
    w = seg.split()
    return os.path.basename(w[0]) if w else ""


def mask(text, py_bodies):
    """Код оболочки: без комментариев, текст в кавычках — одно слово, here-document разобран.

    Разбор по состояниям, а не выражением: `#` и `;` внутри кавычек — текст, тело
    here-document — текст, если его читает не оболочка, а подстановка `$( … )` в
    двойных кавычках и `bash -c '…'` — код. Продолжение строки (`\\` перед концом
    строки) склеивается; продолжение внутри комментария комментарий не продлевает.
    """
    o, i, n = [], 0, len(text)
    pending, word_start = [], True

    def emit_quoted(content, subs):
        tail = "".join(o[-200:])
        m = re.search(r"(?<![\w-])(?:bash|sh)((?:[ \t]+-[A-Za-z]+)+)[ \t]*$", tail)
        if m and "c" in m.group(1).replace(" ", "").replace("-", ""):
            o.append(";(" + mask(content, py_bodies) + ");")
        elif SINGLE_WORD.match(content):
            o.append(content)
        else:
            o.append(QUOTED + "".join(";$(" + mask(s, py_bodies) + ");" for s in subs))

    while i < n:
        c = text[i]
        if c == "\\" and i + 1 < n:
            if text[i + 1] == "\n":
                o.append(" ")
            else:
                o.append(text[i:i + 2])
                word_start = False
            i += 2
            continue
        if c == "\n":
            o.append("\n")
            i += 1
            for delim, strip, kind in pending:
                body = []
                while i < n:
                    j = text.find("\n", i)
                    j = n if j < 0 else j
                    ln, i = text[i:j], min(j + 1, n)
                    if (ln.lstrip("\t") if strip else ln) == delim:
                        break
                    body.append(ln)
                b = "\n".join(body)
                if kind == "sh":
                    o.append(mask(b, py_bodies) + "\n")
                elif kind == "py":
                    py_bodies.append(b)
            pending, word_start = [], True
            continue
        if c == "#" and word_start:
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == "'":
            j = text.find("'", i + 1)
            j = n if j < 0 else j
            emit_quoted(text[i + 1:j], [])
            i, word_start = j + 1, False
            continue
        if c == '"':
            content, subs, i = _dq(text, i + 1)
            emit_quoted(content, subs)
            word_start = False
            continue
        if text.startswith("<<<", i):
            o.append("<<<")
            i += 3
            word_start = True
            continue
        if text.startswith("<<", i):
            m = HEREDOC.match(text, i)
            if m:
                delim = m.group(2) if m.group(2) is not None else (m.group(3) if m.group(3) is not None else m.group(4))
                w = _cmd_word("".join(o[-200:]))
                kind = "sh" if w in ("bash", "sh") else ("py" if re.match(r"^python3?$", w) else "text")
                pending.append((delim, m.group(1) == "-", kind))
                o.append(" ")
                i, word_start = m.end(), False
                continue
        o.append(c)
        word_start = c in " \t;|&()<>"
        i += 1
    return "".join(o)


def code_of(text, py_bodies):
    """Код оболочки: разобран `mask`, текст `echo`/`printf` снят."""
    text = EXPR.sub(lambda e: "${{" + re.sub(r"\s+", "", e.group(1)) + "}}", text or "")
    return ECHO_TEXT.sub("echo", mask(text, py_bodies))


def commands(line):
    """Простые команды строки: (текст, глубина), `(`/`)` — смена области `cd`."""
    out, buf, i, n = [], [], 0, len(line)
    while i < n:
        c = line[i]
        if line.startswith("${", i):
            e = line.find("}}", i) + 2 if line.startswith("${{", i) else line.find("}", i) + 1
            e = n if e <= i else e
            buf.append(line[i:e])
            i = e
            continue
        m = re.match(r"\$\([A-Za-z_]\w*\)", line[i:])
        if m:
            buf.append(m.group(0))
            i += m.end()
            continue
        if c in ";|&()`":
            out.append(("".join(buf), None))
            buf = []
            if c in "()":
                out.append(("", c))
            i += 1
            continue
        buf.append(c)
        i += 1
    out.append(("".join(buf), None))
    return out


class Tree(object):
    """Ствол одного репозитория: состав и содержимое по ревизии."""

    def __init__(self, repo, ref):
        self.repo, self.ref = repo, ref
        self.files = _lib.trunk_files(repo, ref)
        self._text = {}
        self._make = {}

    def read(self, rel):
        if rel not in self._text:
            self._text[rel] = _lib.trunk_show(self.repo, self.ref, rel) or ""
        return self._text[rel]

    def makefile(self, d):
        return os.path.join(d, "Makefile") if d else "Makefile"

    def makedb(self, d):
        """Цели Makefile каталога `d`: имя → (предпосылки, строки рецепта)."""
        if d in self._make:
            return self._make[d]
        rel = self.makefile(d)
        db = {}
        if rel in self.files:
            rule = re.compile(r"^([A-Za-z0-9][\w./%-]*(?:\s+[A-Za-z0-9][\w./%-]*)*)\s*:(?![=:])\s*(.*)$")
            cur, recipe = None, []

            def flush():
                if cur:
                    for name in cur[0]:
                        pre, rec = db.get(name, ([], []))
                        db[name] = (pre + cur[1], rec + recipe)
            for ln in self.read(rel).splitlines():
                if ln.startswith("\t"):
                    if cur:
                        recipe.append(ln[1:])
                    continue
                if ln.endswith("\\") and cur is None:
                    continue
                flush()
                cur, recipe = None, []
                if ln.lstrip().startswith("#"):
                    continue
                m = rule.match(ln)
                if m:
                    cur = (m.group(1).split(), [p for p in m.group(2).split("#")[0].split()
                                                if not p.startswith("$") and p != "|"])
            flush()
        self._make[d] = db
        return db


def combos_of(matrix):
    """Сочетания матрицы так, как их строит хостинг; None — матрица не раскрывается."""
    if not isinstance(matrix, dict):
        return None
    base = {k: v for k, v in matrix.items() if k not in ("include", "exclude")}
    if any(not isinstance(v, list) for v in base.values()):
        return None
    keys = sorted(base)
    combos = [dict(zip(keys, vals)) for vals in itertools.product(*[base[k] for k in keys])] if keys else []
    excl = matrix.get("exclude") or []
    incl = matrix.get("include") or []
    if not isinstance(excl, list) or not isinstance(incl, list):
        return None

    def same(a, b):
        return str(a) == str(b) if not isinstance(a, (dict, list)) else a == b
    combos = [c for c in combos
              if not any(isinstance(e, dict) and e and all(k in c and same(c[k], v) for k, v in e.items())
                         for e in excl)]
    for e in incl:
        if not isinstance(e, dict):
            return None
        hit = False
        for c in combos[:len(combos)]:
            if all(same(c[k], v) for k, v in e.items() if k in base):
                if any(k not in base and k in c and not same(c[k], v) for k, v in e.items()):
                    continue
                c.update({k: v for k, v in e.items() if k not in base})
                hit = True
        if not hit:
            combos.append(dict(e))
    return combos


def lookup(combo, key):
    v = combo
    for part in key.split("."):
        if not isinstance(v, dict) or part not in v:
            return None
        v = v[part]
    return v if isinstance(v, (str, int, float)) and not isinstance(v, bool) else None


class Walk(object):
    def __init__(self, tree, combos):
        self.tree, self.combos = tree, combos
        self.seen = set()
        self.unresolved = []
        self.targets = 0
        self.scripts = 0

    def expand(self, word):
        """Слово под каждым сочетанием матрицы; нераскрытое — в перечень неразрешённого."""
        keys = MATRIX.findall(word)
        if not keys:
            return [word]
        if not self.combos:
            self.unresolved.append("слово %s (матрицы нет либо она не раскрывается)" % word)
            return []
        out = []
        for c in self.combos:
            vals = {k: lookup(c, k) for k in keys}
            if any(v is None for v in vals.values()):
                self.unresolved.append("слово %s (у сочетания %s ключа нет)" % (word, c))
                continue
            w = MATRIX.sub(lambda m: str(vals[m.group(1)]), word)
            if w not in out:
                out.append(w)
        return out

    def join(self, wd, d):
        """Каталог `d` относительно `wd`; None — разбор каталога не знает."""
        if d is None:
            return None
        d = d.strip("\"'")
        if QUOTED in d:
            return None
        m = re.match(r"^\$\{?GITHUB_WORKSPACE\}?/?", d)
        if m:
            wd, d = "", d[m.end():]
        if wd is None or not d or d.startswith(("$", "/", "~", "-")) or "${{" in d:
            return None
        j = os.path.normpath(os.path.join(wd, d)) if wd else os.path.normpath(d)
        if j.startswith(".."):
            return None
        return "" if j == "." else j

    def shell(self, text, wd, depth=0, self_dir=None):
        """Достигает ли код Go. Обходит make и скрипты рекурсивно, следит за `cd`."""
        if depth > 14:
            return False
        if self_dir is not None:
            text = SELF_DIR.sub(lambda m: "./" + self_dir if self_dir else ".", text or "")
        py_bodies = []
        code = code_of(text, py_bodies)
        if GO_CALL.search(code):
            return True
        for b in py_bodies:
            r = py_reaches(b)
            if r:
                return True
            if r is None:
                self.unresolved.append("here-document python не разбирается")
        cur = wd
        for line in code.split("\n"):
            stack = []
            for seg, paren in commands(line):
                if paren == "(":
                    stack.append(cur)
                    continue
                if paren == ")":
                    cur = stack.pop() if stack else cur
                    continue
                body = LEAD.sub("", seg)
                words = body.split()
                if words and words[0] in ("cd", "pushd"):
                    cur = self.join(cur, words[1]) if len(words) > 1 else None
                    continue
                if self.make(seg, cur, depth):
                    return True
                if self.script(seg, cur, depth):
                    return True
        return False

    def make(self, seg, cur, depth):
        for m in MAKE_CALL.finditer(seg):
            args = re.split(r"\s+[0-9]*[<>]", " " + m.group("args"))[0].split()
            d = cur
            # `--dir X -- make` обёртки той же команды — каталог make.
            pre = re.findall(r"(?<![\w-])--dir\s+(\S+)", seg[:m.start()])
            if pre:
                d = self.join(cur, pre[-1])
            names, skip_next = [], False
            for a in args:
                if skip_next:
                    d = self.join(cur, a)
                    skip_next = False
                    continue
                if a in ("-C", "--directory", "-f", "--file", "--makefile"):
                    if a in ("-f", "--file", "--makefile"):
                        self.unresolved.append("make %s (свой файл правил не читается)" % a)
                        return False
                    skip_next = True
                    continue
                if a.startswith("--directory="):
                    d = self.join(cur, a.split("=", 1)[1])
                    continue
                if a.startswith("-C") and len(a) > 2:
                    d = self.join(cur, a[2:])
                    continue
                if a.startswith("-") or "=" in a:
                    continue
                names.append(a)
            for a in names:
                for t in self.expand(a):
                    if self.target(d, t, depth):
                        return True
        return False

    def script(self, seg, cur, depth):
        for m in SCRIPT_CALL.finditer(seg):
            p = m.group("path")
            rel = self.resolve(p, cur)
            if m.group("ext") in FOREIGN_EXT:
                self.unresolved.append("скрипт %s (язык не читается: вызов Go из него не распознаётся)"
                                       % (rel or p))
                continue
            if rel is None:
                self.unresolved.append("скрипт %s (в дереве не найден либо каталог не раскрыт)" % p)
                continue
            if ("script", rel, cur) in self.seen:
                continue
            self.seen.add(("script", rel, cur))
            self.scripts += 1
            body = self.tree.read(rel)
            if rel.endswith(".py"):
                r = py_reaches(body)
                if r:
                    return True
                if r is None:
                    self.unresolved.append("скрипт %s не разбирается" % rel)
                continue
            if self.shell(body, cur, depth + 1, self_dir=os.path.dirname(rel)):
                return True
        return False

    def resolve(self, p, cur):
        m = re.match(r"^\$\{?GITHUB_WORKSPACE\}?/", p)
        if m:
            c = os.path.normpath(p[m.end():])
            return c if c in self.tree.files else None
        if cur is None:
            return None
        p = p[2:] if p.startswith("./") else p
        c = os.path.normpath(os.path.join(cur, p)) if cur else os.path.normpath(p)
        return c if c in self.tree.files else None

    def target(self, d, t, depth):
        if d is None:
            self.unresolved.append("цель ?/Makefile::%s (каталог не раскрыт)" % t)
            return False
        key = ("target", d, t)
        if key in self.seen:
            return False
        self.seen.add(key)
        db = self.tree.makedb(d)
        mk = self.tree.makefile(d)
        if t not in db:
            if mk not in self.tree.files:
                self.unresolved.append("цель %s::%s (Makefile нет)" % (mk, t))
            elif "$" in t:
                self.unresolved.append("цель %s::%s (имя не раскрыто)" % (mk, t))
            else:
                self.unresolved.append("цель %s::%s (в Makefile не найдена)" % (mk, t))
            return False
        self.targets += 1
        pre, rec = db[t]
        # Строка рецепта (вместе с продолжениями `\`) — своя оболочка: `cd` одной
        # строки на следующую не действует, а внутри склеенной — действует, даже
        # если продолжение прошло через строку-комментарий.
        cmd = []
        for ln in rec + [""]:
            cmd.append(ln)
            if ln.endswith("\\"):
                continue
            if self.shell("\n".join(cmd).replace("$$", "$"), d, depth + 1):
                return True
            cmd = []
        return any(self.target(d, p, depth + 1) for p in pre)


def is_setup(step):
    return str(step.get("uses") or "").split("@")[0].strip().lower() == SETUP


def steps_of(tree, steps, depth=0):
    """Шаги задания с раскрытием локальных составных действий."""
    out = []
    for s in steps or []:
        if not isinstance(s, dict):
            continue
        out.append(s)
        uses = str(s.get("uses") or "")
        if uses.startswith("./") and depth < 4:
            base = uses[2:].rstrip("/")
            for name in ("action.yml", "action.yaml"):
                rel = base + "/" + name
                if rel in tree.files:
                    try:
                        doc = yaml.safe_load(tree.read(rel)) or {}
                    except yaml.YAMLError:
                        doc = {}
                    inner = steps_of(tree, ((doc.get("runs") or {}).get("steps")), depth + 1)
                    # Шаг составного действия под `if: false` вызывающего не исполняется.
                    if is_false(s.get("if")):
                        inner = [dict(x, **{"if": False}) if "run" in x else x for x in inner]
                    out.extend(inner)
                    break
    return out


def main():
    root = gate_root("CI_SETUP_GATE_ROOT", __file__)
    trees, missing = {}, []
    for name in REPOS:
        path = product_clone.clone(root, name)
        if path is None:
            missing.append(name)
            continue
        ref = _lib.trunk(path)
        if not ref:
            missing.append(name + " (ствол не резолвится)")
            continue
        trees[name] = Tree(path, ref)
    if missing:
        _lib.void(NAME, "клонов нет либо ствол не резолвится: %s — судить задания не по чему. "
                        "Условие создаётся клоном в project/<репо>, KACHO_HOME_<РЕПО> либо "
                        "KACHO_MONOREPO (порядок — scripts/lib/product_clone.py)" % ", ".join(missing))
        return 2

    wf_n = jobs_n = off_n = setup_n = reached = runs_n = off_runs = targets_n = scripts_n = 0
    findings = []
    for name in REPOS:
        tree = trees[name]
        wfs = sorted(p for p in tree.files if re.match(r"^\.github/workflows/[^/]+\.ya?ml$", p))
        for wf in wfs:
            try:
                doc = yaml.safe_load(tree.read(wf)) or {}
            except yaml.YAMLError as e:
                findings.append("%s:%s — процесс не разбирается: %s" % (name, wf, str(e).split("\n")[0]))
                continue
            wf_n += 1
            jobs = doc.get("jobs") if isinstance(doc, dict) else None
            for jk, job in (jobs or {}).items():
                if not isinstance(job, dict):
                    continue
                jobs_n += 1
                if is_false(job.get("if")):
                    off_n += 1
                    continue
                steps = steps_of(tree, job.get("steps"))
                if not any(is_setup(s) for s in steps):
                    continue
                setup_n += 1
                combos = combos_of((job.get("strategy") or {}).get("matrix") or {})
                jwd = (((job.get("defaults") or {}).get("run") or {}).get("working-directory") or "")
                walk = Walk(tree, combos)
                hit, job_runs, job_off = False, 0, 0
                for s in steps:
                    if "run" not in s:
                        continue
                    if is_false(s.get("if")):
                        job_off += 1
                        continue
                    job_runs += 1
                    wd = str(s.get("working-directory") or jwd).strip().strip("/")
                    wd = "" if wd in ("", ".", "./") else walk.join("", wd)
                    if walk.shell(str(s["run"]), wd):
                        hit = True
                        break
                runs_n += job_runs
                off_runs += job_off
                targets_n += walk.targets
                scripts_n += walk.scripts
                if hit:
                    reached += 1
                    continue
                extra = ""
                if walk.unresolved:
                    extra = "; неразрешено (Go за ним не судится): " + ", ".join(sorted(set(walk.unresolved))[:6])
                findings.append("%s:%s:%s — шаг uses: %s есть, команды Go задание не достигает "
                                "(шагов run осмотрено %d, под if: false %d, целей make %d, скриптов %d)%s"
                                % (name, wf, jk, SETUP, job_runs, job_off, walk.targets, walk.scripts, extra))

    _lib.census("%s: стволов %d (%s); процессов %d; заданий %d (под if: false %d); с %s — %d, "
                "из них достигают Go %d; шагов run осмотрено %d (под if: false %d), целей make %d, скриптов %d"
                % (NAME, len(trees), ", ".join("%s@%s" % (n, trees[n].ref) for n in REPOS),
                   wf_n, jobs_n, off_n, SETUP, setup_n, reached, runs_n, off_runs, targets_n, scripts_n))
    if findings:
        for f in findings:
            _lib.fail(NAME, f)
        return 1
    if wf_n == 0:
        _lib.void(NAME, "процессов конвейера в стволах ноль — судить нечего")
        return 2
    if setup_n == 0:
        _lib.void(NAME, "заданий с %s в стволах ноль — предмет снят, проверку снять тем же изменением" % SETUP)
        return 2
    _lib.passed(NAME, "заданий с %s %d, каждое достигает команды Go" % (SETUP, setup_n))
    return 0


if __name__ == "__main__":
    sys.exit(main())
