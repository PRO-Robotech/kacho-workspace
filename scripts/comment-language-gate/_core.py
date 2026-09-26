"""Прибор набора comment-language-gate: где в нашем Go проза комментария не по-русски.

ТРЕБОВАНИЕ ВЛАДЕЛЬЦА 2026-09-21, дословно: «комментарии только на русском.
Существующие правки привести к виду». Норма — `.claude/rules/00-kacho-core.md`,
строки `ban22-*`. Здесь только механизм; доводы и замеры — в архиве нормы
`.claude/backup/00-kacho-core.md` и в шапках файлов набора (README у набора нет).

── ЧТО ЗДЕСЬ РАЗБИРАЕТСЯ, А НЕ ИЩЕТСЯ ОБРАЗЦОМ ──────────────────────────────

`scan_go` — лексер Go, а не поиск по образцу. Он различает шесть состояний:
код, строчный комментарий, блочный комментарий, интерпретируемая строка,
сырая строка в обратных кавычках, руна. Поэтому ИСКЛЮЧЕНИЕ И6 (директива или
пример формата ВНУТРИ строкового литерала) исполняется BY CONSTRUCTION: в
выдачу попадают только узлы комментария, литералов прибор не видит вовсе.
Наивный строчный поиск на этом же дереве спотыкается: 1 127 директивных строк
из 3 366 он пропускает (хвостовая директива в конце строки кода, дефисный
токен без двоеточия, директива внутри литерала) — измерено разведкой.

── ЕДИНИЦА НАРУШЕНИЯ — СТРОКА КОММЕНТАРИЯ, А НЕ БЛОК ───────────────────────

Первая редакция критерия судила БЛОК (`*ast.CommentGroup`) со ступенью «есть
кириллица → русский». Опровержение показало цену: одна кириллическая руна
амнистирует произвольно длинный английский блок — 734 блока / 2 170 строк при
≤12 рунах, 47 блоков ровно с одной руной, максимум 84 строки, амнистированные
руной `с` в `Sync read с pagination`; 336 из этих строк лежат в файлах, которые
тот прибор объявлял ЧИСТЫМИ. Единица сужена до строки: блок называется в
находке для координаты, но судится строка. Смешанный комментарий остаётся
нормой by construction — латинский идентификатор внутри русской фразы стоит на
той же строке, что и кириллица.

── ОБЕ СТУПЕНИ ЧИТАЮТ ОДИН НОРМАЛИЗОВАННЫЙ ТЕКСТ ───────────────────────────

Второе опровержение: сторона прозы выбрасывала URL и спаны в обратных кавычках
как «не язык», а сторона кириллицы читала сырой текст и засчитывала кириллицу
ИМЕННО ОТТУДА. Два плеча одного решения читали разные тексты, и английский блок
любой длины становился русским от русского ярлыка в кавычках (2 блока / 45
строк, `corelib/listfiltergate/ownmodule_test.go:11`). Здесь нормализация
применяется ОДИН раз и до обоих плеч: спан, отброшенный как не-проза,
свидетельством языка быть не может.

── ДИРЕКТИВА ОПОЗНАЁТСЯ ПРИЗНАКОМ САМОГО GO, А НЕ СЛОВАРЁМ ИНСТРУМЕНТОВ ─────

`is_directive` повторяет правило `go/ast.IsDirective`: `//имя:...` без пробела
после `//`. Словарь инструментов не заводится и не ведётся — он амнистировал бы
английское обоснование, едущее на директиве (живой образец:
`corelib/baggage/baggage_test.go:163`, `//nolint:staticcheck // SA1012:
intentional nil for defensive check`). У директивной строки не судятся её
аргументы (это машинный вход, не проза) и судится обоснование после явного
разделителя ` // `, ` -- `, ` — `. Отсюда форма, которую дерево уже несёт:
ТОКЕН ДИРЕКТИВЫ — ЛАТИНИЦЕЙ, ОБОСНОВАНИЕ — ПО-РУССКИ.

── ПРОЗАИЧЕСКОЕ СЛОВО ОПРЕДЕЛЯЕТСЯ ФОРМОЙ, А НЕ СЛОВАРЁМ АНГЛИЙСКОГО ───────

Словарь английского стареет, форма — нет. Из токенов отбрасываются: с `. _ - /
:` внутри (dotted-путь, snake_case, слаг, путь, метка), с заглавной ВНУТРИ
(CamelCase), целиком заглавные длиной >1 (акроним, константа), короче двух
символов и ключевые слова Go. Остаток — голые строчные латинские слова.

ПОРОГ В ДВА СЛОВА не косметика: одно латинское слово (`// ok`, `// Network`)
прозой не является — это разделитель или хвост, а не изложение.
"""
import json
import os
import re
import subprocess

# Четыре дерева, а не три. Оснастка воркспейса (`.claude/hooks/**/*.go`) — наш
# код, и первая редакция критерия молча включила её в итог, не назвав в обходе:
# `for r in kacho kaname corelib` давал 1632/51893 против объявленных
# 1633/51894. Обход называет все четыре дерева поимённо.
PRODUCTS = ("kacho", "kaname", "corelib")
WORKSPACE = "workspace"

# Ствол продукта — одно объявление на все гейты воркспейса (`docs-gate/_lib.py`).
# Вызывающие кладут `docs-gate` в путь поиска до импорта этого модуля.
from _lib import TRUNK_REF  # noqa: E402

# Ключевые слова Go и универсальные сокращения. Это НЕ словарь английского и не
# словарь инструментов: перечень закрыт грамматикой Go плюс те сокращения,
# которые в нашем дереве встречаются как имена, а не как изложение.
STOP = frozenset("""
break case chan const continue default defer else fallthrough for func go goto if
import interface map package range return select struct switch type var
nil true false iota make new len cap append copy delete panic recover print
err ctx req res resp cfg arg args ok id ids db tx sql api rpc url uri uuid
str num idx ptr val vals buf fmt log msg mu wg fn cb src dst tmp env var
int uint int8 int16 int32 int64 uint8 uint16 uint32 uint64 float32 float64
byte rune string bool error any complex64 complex128 uintptr
http grpc json yaml proto pb pg pgx helm k8s ci cd os io net
""".split())

_CYR = re.compile(r"[Ѐ-ӿ]")
_URL = re.compile(r"\b(?:https?|ftp|file)://\S+")
_BACKTICK = re.compile(r"`[^`]*`")
_TOKEN = re.compile(r"[A-Za-z][A-Za-z0-9_.\-/:]*")
_HAS_UPPER_INSIDE = re.compile(r"[A-Za-z][A-Za-z0-9]*[A-Z]")
_SEPARATOR = re.compile(r"\s(?://|--|—|–)\s")
_TRIM = re.compile(r"^[^A-Za-z0-9]+|[^A-Za-z0-9]+$")
# И7: латинский ПРЕФИКС ИМЕНИ в начале блока — конвенция revive `exported` и
# staticcheck ST1000/ST1020. Сегодня она в трёх конфигах выключена (измерено),
# но разрешение записывается ЗАРАНЕЕ: иначе в день включения норма и линтер
# станут взаимоисключающими. Форма `// ИмяСущности — пояснение по-русски` уже
# живёт в дереве (`// VendoredNoticeFinding — координата находки.`).
_ENTITY_PREFIX = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*[—–-]\s")
# И2: машинно-читаемая метка соответствия с закрытым словарём OSI. Перевод
# идентификатора лицензии — не стилистика, а ложь о правообладании. Объём —
# 8 255 строк по трём стволам, держатель существует: `kacho`
# `internal/repohygiene/license_test.go` (TestSPDXHeadersPresent).
_LICENSE = re.compile(r"SPDX-License-Identifier|Copyright\s*\(c\)|All rights reserved")
# И3: порождённый файл. Признак — строка, которую читают дословно ДВА наших
# собственных гейта (`kaname` `internal/check/authz_wrapper_outcome_lanes.go:120`
# ПРОПУСКАЕТ по ней порождённые файлы, `internal/supplyhygiene/
# generator_coordinates_test.go:74` её ТРЕБУЕТ) и оба diff-гейта генерации.
_GENERATED = re.compile(r"^// Code generated .* DO NOT EDIT\.$", re.M)


def clone(root, name):
    """Путь клона продукта либо None. Тот же порядок, что у foundation-candidates."""
    if name == WORKSPACE:
        return root
    env = os.environ.get("KACHO_HOME_" + name.upper().replace("-", "_"))
    if env and os.path.exists(os.path.join(env, ".git")):
        return env
    guess = os.path.join(root, "project", name)
    if os.path.exists(os.path.join(guess, ".git")):
        return guess
    return None


# ── ИСТОЧНИК ДЕРЕВА: РЕВИЗИЯ ПРОДУКТА, РАБОЧАЯ КОПИЯ ВОРКСПЕЙСА ─────────────
#
# ДЕРЕВО ПРОДУКТА ЧИТАЕТСЯ С РЕВИЗИИ, А НЕ С ДИСКА КЛОНА (ws#789). Клон продукта
# рядом с воркспейсом — чужая рабочая копия: её переключают на ветку полосы, в
# ней лежат незакоммиченные правки. Прибор, читавший её индекс и неотслеживаемые
# файлы, выносил вердикт о том, на что клон переключён: клон kaname на ветке
# полосы давал другой вход, чем `origin/main`, и вердикт воркспейса зависел от
# чужого `git checkout`. Поэтому у продукта вход — `git ls-tree` и `git cat-file`
# по ревизии: ствол (`origin/main`) либо закреплённая в ведомости ревизия.
#
# ВОРКСПЕЙС — ПО ИНДЕКСУ И РАБОЧЕЙ КОПИИ, как прежде и как его судят остальные
# гейты воркспейса: это дерево, в котором гейт живёт, и незакоммиченный файл
# обязан судиться ровно в том изменении, где его заводят. Посторонний каталог
# рядом на вердикт не влияет — пути берутся из индекса git, а не обходом диска.

class Source(object):
    """Состав и содержимое одного дерева. `rev` None — рабочая копия."""

    def __init__(self, repo, rev=None):
        self.repo, self.rev = repo, rev
        self._blobs = {}

    def paths(self, suffix):
        """Отсортированные пути, кончающиеся `suffix`; None — git не отработал."""
        if self.rev is None:
            out = subprocess.run(
                ["git", "-C", self.repo, "ls-files", "-z", "--cached", "--others",
                 "--exclude-standard", "*" + suffix],
                capture_output=True)
            if out.returncode != 0:
                return None
            return sorted(set(p.decode("utf-8", "surrogateescape")
                              for p in out.stdout.split(b"\0")
                              if p and p.decode("utf-8", "surrogateescape").endswith(suffix)))
        out = subprocess.run(
            ["git", "-C", self.repo, "ls-tree", "-r", "-z", "--full-tree", self.rev],
            capture_output=True)
        if out.returncode != 0:
            return None
        res = []
        for rec in out.stdout.split(b"\0"):
            if not rec:
                continue
            meta, path = rec.split(b"\t", 1)
            mode, kind, sha = meta.decode().split()
            path = path.decode("utf-8", "surrogateescape")
            # Символьная ссылка несёт в блобе ПУТЬ цели, а не текст файла: прочесть
            # её как Go значило бы судить строку пути. Цель внутри дерева судится
            # своей записью. Замер 2026-09-26: `.go`-ссылок на стволах 0.
            if kind != "blob" or mode == "120000" or not path.endswith(suffix):
                continue
            self._blobs[path] = sha
            res.append(path)
        return sorted(res)

    def read(self, rel):
        """Текст файла либо None."""
        if self.rev is None:
            try:
                with open(os.path.join(self.repo, rel), encoding="utf-8",
                          errors="replace") as fh:
                    return fh.read()
            except OSError:
                return None
        sha = self._blobs.get(rel)
        if sha is None:
            return None
        out = subprocess.run(["git", "-C", self.repo, "cat-file", "blob", sha],
                             capture_output=True)
        if out.returncode != 0:
            return None
        return out.stdout.decode("utf-8", "replace")

    def read_many(self, rels):
        """{путь: текст} одним `git cat-file --batch` — у ревизии; у копии — по файлу."""
        if self.rev is None:
            return dict((r, self.read(r)) for r in rels)
        shas = [self._blobs[r] for r in rels if r in self._blobs]
        if not shas:
            return {}
        out = subprocess.run(["git", "-C", self.repo, "cat-file", "--batch"],
                             input=("\n".join(shas) + "\n").encode(),
                             capture_output=True)
        if out.returncode != 0:
            return {}
        data, pos, by_sha = out.stdout, 0, {}
        while pos < len(data):
            nl = data.index(b"\n", pos)
            head = data[pos:nl].decode().split()
            if len(head) < 3 or head[1] == "missing":
                pos = nl + 1
                continue
            size = int(head[2])
            by_sha[head[0]] = data[nl + 1:nl + 1 + size].decode("utf-8", "replace")
            pos = nl + 1 + size + 1
        return dict((r, by_sha.get(self._blobs.get(r))) for r in rels)


def resolve(repo, rev):
    """Полная ревизия коммита либо None — её в клоне нет."""
    out = subprocess.run(["git", "-C", repo, "rev-parse", "--verify", "--quiet",
                          rev + "^{commit}"], capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 and out.stdout.strip() else None


def is_ancestor(repo, older, newer):
    return subprocess.run(["git", "-C", repo, "merge-base", "--is-ancestor",
                           older, newer], capture_output=True).returncode == 0


# ── ЛЕКСЕР ──────────────────────────────────────────────────────────────────

class ScanError(Exception):
    """Разбор не состоялся. Отличимо от «комментариев нет»: см. перепись."""


def scan_go(text):
    """[(строка, текст)] — узлы комментария. Литералов в выдаче НЕТ (И6).

    Возвращает строчные комментарии по одной записи на строку и блочные — по
    записи на каждую их строку, чтобы единицей суждения была СТРОКА.
    """
    out = []
    i, n, line = 0, len(text), 1
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            i += 1
        elif c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            if j < 0:
                j = n
            out.append((line, text[i + 2:j]))
            i = j
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            if j < 0:
                raise ScanError("незакрытый блочный комментарий на строке %d" % line)
            body = text[i + 2:j]
            for k, part in enumerate(body.split("\n")):
                out.append((line + k, part))
            line += body.count("\n")
            i = j + 2
        elif c == '"':
            i += 1
            while i < n and text[i] != '"':
                if text[i] == "\\":
                    i += 1
                elif text[i] == "\n":
                    raise ScanError("перевод строки внутри строки на строке %d" % line)
                i += 1
            if i >= n:
                raise ScanError("незакрытая строка на строке %d" % line)
            i += 1
        elif c == "`":
            j = text.find("`", i + 1)
            if j < 0:
                raise ScanError("незакрытая сырая строка на строке %d" % line)
            line += text.count("\n", i, j)
            i = j + 1
        elif c == "'":
            i += 1
            while i < n and text[i] != "'":
                if text[i] == "\\":
                    i += 1
                elif text[i] == "\n":
                    raise ScanError("перевод строки внутри руны на строке %d" % line)
                i += 1
            if i >= n:
                raise ScanError("незакрытая руна на строке %d" % line)
            i += 1
        else:
            i += 1
    return out


def groups(comments):
    """Смежные строки комментария — один блок. Блок нужен для КООРДИНАТЫ
    находки; судится строка."""
    res, cur = [], []
    prev = None
    for ln, body in comments:
        if prev is not None and ln != prev + 1:
            res.append(cur)
            cur = []
        cur.append((ln, body))
        prev = ln
    if cur:
        res.append(cur)
    return res


# ── ПРИЗНАКИ ────────────────────────────────────────────────────────────────

def normalize(body):
    """ОДНА нормализация для ОБОИХ плеч решения: URL и спаны в обратных
    кавычках выбрасываются ДО проверки языка, а не только со стороны прозы."""
    return _BACKTICK.sub(" ", _URL.sub(" ", body))


def is_directive(body):
    """Признак самого Go (`go/ast.IsDirective`): `//имя:...` без пробела."""
    if not body or body[:1].isspace():
        return False
    head = body.split(None, 1)[0]
    return ":" in head and head.split(":", 1)[0].isalnum()


def judged_text(body, first_of_block):
    """Что из строки подлежит суждению. None — строка вне предмета."""
    if _LICENSE.search(body):
        return None                                   # И2
    if is_directive(body):
        m = _SEPARATOR.search(body)                   # И1: судится обоснование,
        if not m:                                     # аргументы директивы — нет
            return None
        body = body[m.end():]
    body = normalize(body)                            # И6: пример в кавычках снят
    if first_of_block:
        body = _ENTITY_PREFIX.sub(" ", body, count=1)  # И7
    return body


def has_cyrillic(text):
    return bool(_CYR.search(text))


def is_prose_word(t):
    """Голое латинское слово: форма токена, не словарь английского."""
    if not t or not _TOKEN.fullmatch(t):
        return False
    if any(ch in t for ch in "._-/:"):
        return False                      # dotted-путь, snake_case, слаг, метка
    if _HAS_UPPER_INSIDE.match(t):
        return False                      # CamelCase — имя сущности
    if len(t) > 1 and t.isupper():
        return False                      # акроним, константа
    if len(t) < 2:
        return False
    return t.lower() not in STOP


MIN_PROSE = 2


def prose_run(text):
    """Длиннейшая цепочка прозаических слов, стоящих ПОДРЯД.

    СОСЕДСТВО, А НЕ СУММА ПО СТРОКЕ, и это не тонкость, а отделение изложения от
    ПЕРЕЧИСЛЕНИЯ ЗНАЧЕНИЙ. Сумма по строке краснила машинно-читаемые перечни,
    где слова разделены не пробелом, а разделителем колонок:
    `// "read" | "declared" | "mount"`, `// local | host | hostssl | hostnossl`.
    Это не проза и переводу не подлежит — перевод сделал бы их ложью о формате
    (И6). Изложение же склеивает слова пробелом: `intentional nil for defensive
    check` даёт цепочку `defensive check`, `should be a pass-through` — `should
    be`. Тот же признак снимает хвост из одного слова (`— operator-controlled
    path`): одно слово прозой не является, и это тот самый порог в два слова,
    только считанный по соседству.
    """
    best = run = 0
    for chunk in text.split():
        if is_prose_word(_TRIM.sub("", chunk)):
            run += 1
            best = max(best, run)
        else:
            run = 0
    return best


def line_is_finding(body, first_of_block):
    j = judged_text(body, first_of_block)
    if j is None:
        return False
    if has_cyrillic(j):
        return False
    return prose_run(j) >= MIN_PROSE


# ── ИСКЛЮЧЕНИЯ, ВЫВОДИМЫЕ ИЗ ДЕРЕВА ─────────────────────────────────────────

def vendored_prefixes(src):
    """И4 — ввезённое поддерево. Признак ВЫВОДИТСЯ ИЗ ДЕРЕВА, а не выписан
    координатой: выписанная координата переживает свой предмет (опровержение
    нашло ровно это — `corelib/internal/oauth2/PROVENANCE.md` на объявленной
    ревизии отсутствует вовсе), а выведенная исчезает вместе с ним сама.

    Два признака, оба читаются командой:
      · путь числится в каком-либо `vendor-provenance.json` дерева — там
        происхождение доказано ПОБАЙТОВЫМ отпечатком и перечнем подстановок;
        перевод одной строки комментария даёт немедленный exit 1 гейта
        происхождения, и позеленеть он может только объявлением каждой
        переведённой строки расхождением с оригиналом — навсегда, на каждом
        обновлении апстрима;
      · каталог-предок несёт `PROVENANCE.md` — координата апстрима и сверяющий
        скрипт рядом.
    """
    prefixes, files = set(), set()
    for rel in src.paths("PROVENANCE.md") or ():
        prefixes.add(os.path.dirname(rel) + "/")
    manifests = src.paths("vendor-provenance.json") or ()
    for rel, text in src.read_many(manifests).items():
        if text is None:
            continue
        try:
            doc = json.loads(text)
        except ValueError:
            continue
        for item in _walk_json_paths(doc):
            files.add(item)
    return prefixes, files


def _walk_json_paths(node):
    if isinstance(node, dict):
        for k, v in node.items():
            if k in ("path", "file", "target") and isinstance(v, str):
                yield v.lstrip("./")
            else:
                for x in _walk_json_paths(v):
                    yield x
    elif isinstance(node, list):
        for v in node:
            for x in _walk_json_paths(v):
                yield x


def is_vendored(rel, prefixes, files):
    if rel in files:
        return True
    return any(rel.startswith(p) for p in prefixes)


# ── ЗАМЕР ───────────────────────────────────────────────────────────────────

def measure_tree(repo, name, rev=None):
    """Перепись по одному дереву на ревизии `rev` (None — рабочая копия).
    Ключ `void` — считать не по чему (это НЕ зелёное)."""
    src = Source(repo, rev)
    paths = src.paths(".go")
    if paths is None:
        return {"void": "`git %s` в %s не отработал"
                        % ("ls-files" if rev is None else "ls-tree " + rev, repo)}
    prefixes, vfiles = vendored_prefixes(src)
    res = {"tree": name, "rev": rev, "walked": 0, "parsefail": [], "generated": 0,
           "vendored": 0, "files": set(), "lines": 0, "blocks": 0,
           "findings": [], "comment_lines": 0}
    texts = src.read_many(paths)
    for rel in paths:
        text = texts.get(rel)
        if text is None:
            continue
        res["walked"] += 1
        if _GENERATED.search(text):
            res["generated"] += 1            # И3
            continue
        if is_vendored(rel, prefixes, vfiles):
            res["vendored"] += 1             # И4
            continue
        try:
            comments = scan_go(text)
        except ScanError as exc:
            res["parsefail"].append("%s: %s" % (rel, exc))
            continue
        res["comment_lines"] += len(comments)
        for block in groups(comments):
            hit = []
            for k, (ln, body) in enumerate(block):
                if line_is_finding(body, k == 0):
                    hit.append(ln)
            if hit:
                res["blocks"] += 1
                res["lines"] += len(hit)
                res["files"].add(rel)
                res["findings"].append((rel, hit[0], len(hit),
                                        _sample(block, hit[0])))
    return res


def _sample(block, ln):
    for bl, body in block:
        if bl == ln:
            return ("//" + body).strip()[:120]
    return ""


def tree_rev(repo, name):
    """Ревизия, по которой судится дерево: у продукта — полная ревизия ствола
    `origin/main`, у воркспейса — None (рабочая копия). (ревизия, отказ)."""
    if name == WORKSPACE:
        return None, None
    rev = resolve(repo, TRUNK_REF)
    if rev is None:
        return None, "ствол %s не резолвится" % TRUNK_REF
    return rev, None


def measure(root):
    """Замер по ВСЕМ четырём деревьям. `void` — хоть одного клона либо ствола нет."""
    trees, total = [], {"walked": 0, "files": 0, "lines": 0, "blocks": 0,
                        "generated": 0, "vendored": 0, "comment_lines": 0}
    parsefail, missing, findings = [], [], []
    for name in PRODUCTS + (WORKSPACE,):
        repo = clone(root, name)
        if repo is None:
            missing.append(name)
            continue
        rev, why = tree_rev(repo, name)
        if why:
            missing.append("%s (%s)" % (name, why))
            continue
        m = measure_tree(repo, name, rev)
        if "void" in m:
            missing.append("%s (%s)" % (name, m["void"]))
            continue
        m["repo"] = repo
        trees.append(m)
        parsefail.extend(m["parsefail"])
        findings.extend((name,) + f for f in m["findings"])
        for k in ("walked", "lines", "blocks", "generated", "vendored",
                  "comment_lines"):
            total[k] += m[k]
        total["files"] += len(m["files"])
    if missing:
        return {"void": "клонов нет: " + ", ".join(missing)}
    total["trees"] = trees
    total["parsefail"] = parsefail
    total["findings"] = findings
    return total
