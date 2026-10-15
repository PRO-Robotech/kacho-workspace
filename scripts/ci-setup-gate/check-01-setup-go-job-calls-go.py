#!/usr/bin/env python3
"""check-01 — задание конвейера продукта, которое ставит Go, достигает команды Go.

ЧТО УТВЕРЖДАЕТ (ws#1099). В стволах `kacho` и `kaname` каждое задание с шагом
`uses: actions/setup-go` хотя бы одним шагом достигает команды Go: `go`, `gofmt`,
`golangci-lint`, `govulncheck`, `gosec`, `staticcheck` в позиции команды либо
`$(GO)` рецепта make. Задание с `setup-go` без единой такой команды — находка с
координатой `<репо>:<файл процесса>:<ключ задания>`.

ЦЕНА. Действие скачивается с codeload на шаге «Set up job», до первой команды
задания, и отказ скачивания роняет задание красным, которое о предмете изменения
ничего не говорит: «An action could not be found at the URI
'https://codeload.github.com/actions/setup-go/tar.gz/…'» и «Failed to download
archive … after 1 attempts» (kacho#3231, kacho#3244, kaname#815). Скачивание,
которому задание не нужно, — лишний жребий на красное.

ДОСТИЖИМОСТЬ — ТРАНЗИТИВНО, и формы названы, а не подразумеваются:
  * текст шага `run:` — команда Go в позиции команды (после начала строки, `;`,
    `|`, `&&`, `||`, `$(`, обратной кавычки, `then`/`do`/`else`, `xargs`, `exec`,
    `env`, `time`, присваиваний `ИМЯ=значение`);
  * `make <цель>` и `$(MAKE) <цель>` — рецепт цели и её предпосылки, рекурсивно;
    каталог Makefile — `-C <кат>`, `--dir <кат>` и `cd <кат> &&` той же
    логической строки, иначе каталог шага (`working-directory`, `defaults.run`);
    `${{ matrix.<ключ> }}` в имени цели раскрывается значениями матрицы задания;
  * скрипт, вызванный интерпретатором (`bash`, `sh`, `python3`, `node`) либо
    через `./` или `"$GITHUB_WORKSPACE/…"`, — его код, рекурсивно; у `.py` вызов
    Go — элемент `"go"` первым в списке аргументов (`["go", "list", …]`);
  * локальное составное действие (`uses: ./<путь>`) — его `runs.steps`: и
    `setup-go` внутри него, и его шаги `run:`.

ЧИТАЕТСЯ КОД, А НЕ ТЕКСТ: у оболочки снимаются комментарии, а слово `go` внутри
текста `echo` позицией команды не является. Дерево продукта читается со ствола
(`origin/main`, `git ls-tree` и `git cat-file`), а не с диска клона: клон продукта
рядом — чужая рабочая копия, переключённая на ветку полосы (ws#789).

ГРАНИЦЫ, НАЗВАННЫЕ ПРЯМО: `include` в Makefile не раскрывается; цель, имя которой
не раскрылось (переменная make, выражение вне матрицы), и скрипт, не найденный в
дереве, НЕ считаются вызовом Go — задание, у которого есть лишь такие пути,
краснит находкой с перечнем неразрешённого: молчание о неразобранном неотличимо
от чистоты. Вызов Go скриптом на другом языке (`.ts`, `.mjs`) не распознаётся.

ГДЕ ИЩЕТСЯ КЛОН — единственным способом, `scripts/lib/product_clone.py` (ws#1083):
`KACHO_HOME_<РЕПО>`, `KACHO_MONOREPO`, `<корень>/project/<репо>`, клоны канонической
копии для копии полосы под `tmp/`.

ИСХОДЫ: 0 — каждое задание с `setup-go` достигает Go; 1 — находка; 2 — клона или
ствола нет, процессов ноль либо заданий с `setup-go` ноль (предмет снят — снять и
проверку тем же изменением).
"""
import os
import re
import subprocess
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
CMD_POS = (r"(?:^|[\n;|&({]|\$\(|`|(?<![\w-])(?:then|else|elif|do|exec|time|xargs|env|sudo|if|while)(?![\w-]))"
           r"\s*(?:[-+@]\s*)?(?:[A-Za-z_]\w*=\S*\s+)*")
GO_CALL = re.compile(CMD_POS + r"(?:" + GO_TOOLS + r"|\$\(GO\)|\$\{GO\})(?=\s|$)", re.M)
MAKE_CALL = re.compile(r"(?<![\w./-])(?:make|\$\(MAKE\)|\$\{MAKE\})(?P<args>(?:[ \t]+[^\s;|&)]+)+)")
SCRIPT_CALL = re.compile(
    CMD_POS + r"(?:(?:/usr/bin/env\s+)?(?:bash|sh|python3?|node)\s+(?:-[A-Za-z]+\s+)*)?"
    r"[\"']?(?P<path>(?:\$\{?GITHUB_WORKSPACE\}?/|\./)?(?:[\w.-]+/)*[\w.-]+\.(?:sh|bash|py))[\"']?"
    r"(?![\w/-])", re.M)
PY_GO = re.compile(r"[\[(]\s*[\"']go[\"']\s*,")
COMMENT_SH = re.compile(r"(?m)(?<!\$)(?<![\w\"'`#])#(?![{(!]).*$")
MATRIX = re.compile(r"\$\{\{\s*matrix\.([\w.-]+)\s*\}\}")
EXPR = re.compile(r"\$\{\{(.*?)\}\}")
DIR_OF = re.compile(r"(?<![\w-])(?:--dir|cd)\s+[\"']?([\w./${}-]+)[\"']?")
# Текст `echo`/`printf` — слова до конца простой команды; строка в кавычках — одно
# слово целиком, и `;` внутри неё команду не кончает.
ECHO_TEXT = re.compile(r"(?<![\w-])(?:echo|printf)(?![\w-])"
                       r"(?:[ \t]+(?:\"(?:[^\"\\]|\\.)*\"|'[^']*'|[^\s;|&\"']+))*")


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

    def makedb(self, d):
        """Цели Makefile каталога `d`: имя → (предпосылки, рецепт)."""
        if d in self._make:
            return self._make[d]
        rel = os.path.join(d, "Makefile") if d else "Makefile"
        db = {}
        if rel in self.files:
            rule = re.compile(r"^([A-Za-z0-9][\w./%-]*(?:\s+[A-Za-z0-9][\w./%-]*)*)\s*:(?![=:])\s*(.*)$")
            cur, recipe = None, []

            def flush():
                if cur:
                    for n in cur[0]:
                        pre, rec = db.get(n, ([], ""))
                        db[n] = (pre + cur[1], rec + "\n".join(recipe) + "\n")
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


def code_of(text):
    """Код оболочки без комментариев и без текста `echo`/`printf`."""
    # Комментарий снимается ПО ФИЗИЧЕСКОЙ строке, до склейки продолжений: иначе `#`
    # одной строки рецепта съел бы весь склеенный остаток вместе с вызовами Go.
    text = COMMENT_SH.sub("", text or "")
    text = re.sub(r"\\[ \t]*\n", " ", text)
    return ECHO_TEXT.sub("echo", text)


class Walk(object):
    def __init__(self, tree, matrix):
        self.tree, self.matrix = tree, matrix
        self.seen = set()
        self.unresolved = []
        self.targets = 0
        self.scripts = 0

    def expand(self, word):
        keys = MATRIX.findall(word)
        if not keys:
            return [word]
        out = [word]
        for k in keys:
            vals = self.matrix.get(k)
            if not isinstance(vals, list) or not vals:
                return []
            nxt = []
            for w in out:
                for v in vals:
                    sv = v if isinstance(v, (str, int, float)) else None
                    if sv is None:
                        return []
                    nxt.append(MATRIX.sub(lambda m, k=k, sv=sv: str(sv) if m.group(1) == k else m.group(0), w, count=0))
            out = nxt
        return out

    def shell(self, text, wd, depth=0):
        """Достигает ли код Go. Обходит make и скрипты рекурсивно."""
        if depth > 14:
            return False
        code = code_of(text)
        if GO_CALL.search(code):
            return True
        for line in code.split("\n"):
            # `${{ выражение }}` — одно слово: иначе имя цели рвётся по пробелам.
            line = EXPR.sub(lambda e: "${{" + re.sub(r"\s+", "", e.group(1)) + "}}", line)
            for m in MAKE_CALL.finditer(line):
                args = re.split(r"\s+[0-9]*[<>]", " " + m.group("args"))[0].split()
                d = wd
                # Каталог — из ТОЙ ЖЕ простой команды (`cd X && make`, `--dir X -- make`):
                # `cd` прежней команды рецепта, склеенного продолжениями, не в счёт.
                dirs = DIR_OF.findall(re.split(r";|\|\||(?<![|])\|(?![|])", line[:m.start()])[-1])
                if dirs:
                    d = self.join(wd, dirs[-1])
                skip_next = False
                for i, a in enumerate(args):
                    if skip_next:
                        d = self.join(wd, a)
                        skip_next = False
                        continue
                    if a == "-C":
                        skip_next = True
                        continue
                    a = a.strip("\"'")
                    if not a or a.startswith("-") or "=" in a:
                        continue
                    for t in self.expand(a):
                        if self.target(d, t, depth):
                            return True
        for m in SCRIPT_CALL.finditer(code):
            p = re.sub(r"^\$\{?GITHUB_WORKSPACE\}?/", "", m.group("path"))
            rel = self.resolve(p, wd)
            if rel is None:
                if not p.startswith("$"):
                    self.unresolved.append("скрипт " + p)
                continue
            if rel in self.seen:
                continue
            self.seen.add(rel)
            self.scripts += 1
            body = self.tree.read(rel)
            if rel.endswith(".py"):
                if PY_GO.search(body):
                    return True
                continue
            if self.shell(body, os.path.dirname(rel), depth + 1):
                return True
        return False

    def join(self, wd, d):
        d = re.sub(r"^\$\{?GITHUB_WORKSPACE\}?/?", "", d.strip("\"'"))
        if d.startswith("$"):
            return wd
        j = os.path.normpath(os.path.join(wd, d)) if wd else os.path.normpath(d)
        return "" if j == "." else j

    def resolve(self, p, wd):
        p = p[2:] if p.startswith("./") else p
        for c in ([os.path.normpath(os.path.join(wd, p))] if wd else []) + [os.path.normpath(p)]:
            if c in self.tree.files:
                return c
        return None

    def target(self, d, t, depth):
        key = (d, t)
        if key in self.seen:
            return False
        self.seen.add(key)
        db = self.tree.makedb(d)
        if t not in db:
            if "$" in t or t.startswith("${{"):
                self.unresolved.append("цель %s/Makefile::%s" % (d or ".", t))
            elif not db:
                self.unresolved.append("цель %s/Makefile::%s (Makefile нет)" % (d or ".", t))
            else:
                self.unresolved.append("цель %s/Makefile::%s" % (d or ".", t))
            return False
        self.targets += 1
        pre, rec = db[t]
        if self.shell(rec, d, depth + 1):
            return True
        return any(self.target(d, p, depth + 1) for p in pre)


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
                    out.extend(steps_of(tree, ((doc.get("runs") or {}).get("steps")), depth + 1))
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

    wf_n = jobs_n = setup_n = reached = runs_n = targets_n = scripts_n = 0
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
                steps = steps_of(tree, job.get("steps"))
                if not any(str(s.get("uses") or "").split("@")[0] == SETUP for s in steps):
                    continue
                setup_n += 1
                matrix = ((job.get("strategy") or {}).get("matrix") or {})
                matrix = matrix if isinstance(matrix, dict) else {}
                jwd = (((job.get("defaults") or {}).get("run") or {}).get("working-directory") or "")
                walk = Walk(tree, matrix)
                hit = False
                for s in steps:
                    if "run" not in s:
                        continue
                    runs_n += 1
                    wd = str(s.get("working-directory") or jwd).strip().strip("/")
                    wd = "" if wd in (".", "./") else wd
                    if walk.shell(str(s["run"]), wd):
                        hit = True
                        break
                targets_n += walk.targets
                scripts_n += walk.scripts
                if hit:
                    reached += 1
                    continue
                extra = ""
                if walk.unresolved:
                    extra = "; неразрешено (Go за ним не судится): " + ", ".join(sorted(set(walk.unresolved))[:6])
                findings.append("%s:%s:%s — шаг uses: %s есть, команды Go задание не достигает "
                                "(шагов run осмотрено, целей make %d, скриптов %d)%s"
                                % (name, wf, jk, SETUP, walk.targets, walk.scripts, extra))

    _lib.census("%s: стволов %d (%s); процессов %d; заданий %d; с %s — %d, из них достигают Go %d; "
                "шагов run осмотрено %d, целей make %d, скриптов %d"
                % (NAME, len(trees), ", ".join("%s@%s" % (n, trees[n].ref) for n in REPOS),
                   wf_n, jobs_n, SETUP, setup_n, reached, runs_n, targets_n, scripts_n))
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
