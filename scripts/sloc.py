#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""Строки кода по модулям дерева — рукописное отдельно от произведённого.

ЗАЧЕМ. Вопрос «сколько у нас кода» задаётся регулярно, а отвечать на него
чтением дерева каждый раз заново — значит каждый раз заново обжигаться на одних
и тех же трёх местах. Все три измерены на `kacho@16f3313f`:

  · ОДИН файл результатов нагрузочного прогона несёт 161 780 строк кода — больше,
    чем весь прод-код vpc и nlb вместе;
  · восемь `package-lock.json` сайтов документации несут 258 113 строк;
  · сгенерированные коллекции newman — 631 996 строк против 66 578 строк их
    собственного источника, то есть раздутие в 9.5 раза.

Смешать это с рукописным кодом значит завысить ответ втрое и не заметить.
Поэтому счётчик не даёт одного числа: он даёт МАТРИЦУ «модуль × вид», где
произведённое машиной, манифесты и артефакты прогонов стоят отдельными видами и
в итог рукописного кода не входят.

ЕДИНИЦА СЧЁТА. Строка файла, в которой после снятия комментариев остаётся
непробельный символ. Пустые строки и строки-комментарии не считаются; `//`
внутри строкового литерала комментарием НЕ является — разбор идёт конечным
автоматом по символам, а не поиском подстроки. Признать это важным пришлось на
Go: `url := "https://x//y" // хвост` — здесь одна строка кода, а наивный поиск
`//` объявил бы её комментарием целиком.

СОСТАВ ДЕРЕВА — ОТСЛЕЖИВАЕМЫЕ файлы (`git ls-files`), а не содержимое диска.
Замер есть утверждение о РЕПОЗИТОРИИ: чужая рабочая копия, распакованный архив
или черновик, лежащие внутри рабочего каталога, ответ менять не вправе — иначе
одно и то же дерево даёт разные числа на разных машинах. В воркспейсе это не
гипотеза: `git ls-files --others --exclude-standard` находит там 52 записи, из
которых две — целые рабочие копии продукта.

Ключ `--with-untracked` добавляет неотслеживаемое-неигнорируемое: он нужен, когда
меряют работу, которую ещё не закоммитили. Режим НАЗЫВАЕТСЯ в переписи — два
режима дают разные числа, и читатель обязан знать, какое перед ним.

ИСХОДОВ ТРИ, не два:
  0 — посчитано (числа напечатаны вместе с ревизией дерева);
  1 — САМОПРОВЕРКА НЕ СОШЛАСЬ: счётчик считает неверно, числам верить нельзя,
      и ничего не печатается, кроме разбора расхождения;
  2 — VOID, обход беспредметен (не репозиторий, ноль файлов). «Ноль строк» и
      «ноль прочитанного» обязаны быть различимы.

САМОПРОВЕРКА ВСТРОЕНА В ПУТЬ ИСПОЛНЕНИЯ и ключом не отключается. Счётчик, у
которого проверка живёт отдельным скриптом, проверяется ровно до тех пор, пока
о ней помнят; здесь она стоит перед каждым замером, стоит доли миллисекунды и
гоняет десять случаев с известным ответом — в обе стороны: файл из одних
комментариев обязан дать НОЛЬ (иначе счётчик завышает), файл из одного кода —
все свои строки (иначе занижает). Ловушки в наборе не выдуманы: каждая взята из
формы, которая в этом дереве встречается — raw-строка Go с `//` внутри,
docstring Python, многострочный блок, экранированная кавычка.

ЧЕГО ЭТОТ СЧЁТЧИК НЕ ДЕЛАЕТ — названо, чтобы «посчитано» не читалось шире:
  · не считает файлы языков, которых нет в таблице LANGS ниже; их число и
    расширения печатаются в переписи, а не проглатываются;
  · не отличает мёртвый код от живого — он про объём, а не про пользу;
  · не судит дерево и потому НЕ является гейтом: он ничего не роняет и в
    `scripts/*/run-all.sh` намеренно не заведён. Заведи его туда — и каждая
    отправка ветки станет платить за замер, который никого не блокирует.

Способность считать верно доказывается `scripts/sloc-inject.sh` — он ломает
счётчик по одной оси за раз и требует, чтобы самопроверка это увидела.
"""
import argparse
import collections
import json
import os
import re
import subprocess
import sys

# ─────────────────────────────────────────────────────────────────────────────
# ЯЗЫКИ. line — линейные маркеры, block — пары блочных, quotes — кавычки строк,
# raw — кавычки строк БЕЗ экранирования (Go `…`, JS-шаблоны), esc — действует ли
# обратная косая внутри обычной строки.
# ─────────────────────────────────────────────────────────────────────────────
_C = dict(line=("//",), block=(("/*", "*/"),), quotes=("'", '"'), raw=(), esc=True)
_HASH = dict(line=("#",), block=(), quotes=("'", '"'), raw=(), esc=True)

LANGS = {
    ".go":    dict(_C, quotes=('"', "'"), raw=("`",)),
    ".proto": _C,
    ".ts":    dict(_C, raw=("`",)),
    ".tsx":   dict(_C, raw=("`",)),
    ".js":    dict(_C, raw=("`",)),
    ".mjs":   dict(_C, raw=("`",)),
    ".cjs":   dict(_C, raw=("`",)),
    ".css":   dict(line=(), block=(("/*", "*/"),), quotes=("'", '"'), raw=(), esc=True),
    ".tf":    dict(line=("#", "//"), block=(("/*", "*/"),), quotes=('"',), raw=(), esc=True),
    ".hcl":   dict(line=("#", "//"), block=(("/*", "*/"),), quotes=('"',), raw=(), esc=True),
    ".sql":   dict(line=("--",), block=(("/*", "*/"),), quotes=("'", '"'), raw=(), esc=False),
    ".sh":    _HASH,
    ".bash":  _HASH,
    ".bats":  _HASH,
    # Тройные кавычки Python объявлены БЛОКОМ намеренно: docstring — это
    # выражение, но считать его кодом значит записывать документацию в объём
    # реализации. Так же поступает cloc, и сравнимость с ним дороже буквализма.
    ".py":    dict(line=("#",), block=(('"""', '"""'), ("'''", "'''")), quotes=("'", '"'), raw=(), esc=True),
    ".yaml":  _HASH,
    ".yml":   _HASH,
    ".json":  dict(line=(), block=(), quotes=('"',), raw=(), esc=True),
    ".html":  dict(line=(), block=(("<!--", "-->"),), quotes=("'", '"'), raw=(), esc=False),
    ".conf":  _HASH,
    ".rego":  _HASH,
    ".fga":   _HASH,
    ".tpl":   dict(line=("#",), block=(("{{/*", "*/}}"),), quotes=('"',), raw=(), esc=True),
    ".dockerfile": _HASH,
    ".mk":    _HASH,
}
BY_NAME = {"Dockerfile": ".dockerfile", "Makefile": ".mk", "pre-push": ".sh"}

# Документация комментариев не несёт: считается каждая непустая строка.
DOC_EXT = {".md", ".mdx", ".txt"}
PLAIN = dict(line=(), block=(), quotes=(), raw=(), esc=False)

LOCKS = ("package-lock.json", "go.sum", "yarn.lock", "pnpm-lock.yaml", "Cargo.lock")

# ─────────────────────────────────────────────────────────────────────────────
# ВИДЫ. Ключ латиницей — его набирают в командной строке (`--files newman-gen`);
# заголовок русский — его читают. FUNCTIONAL перечисляет виды, входящие в итог
# рукописного кода; всё прочее печатается ниже отдельным блоком.
# ─────────────────────────────────────────────────────────────────────────────
KIND_TITLE = {
    "code":       "код",
    "tests":      "пробы",
    "gates":      "гейты",
    "newman":     "newman",
    "ui":         "ui",
    "ui-tests":   "ui-пробы",
    "stubs":      "сген-стабы",
    "newman-gen": "newman-сген",
    "deploy":     "развёртывание",
    "ci":         "конвейер",
    "docs":       "доки",
    "lock":       "манифест-lock",
    "artifact":   "артефакт-прогона",
}
FUNCTIONAL = ("code", "tests", "gates", "newman", "ui", "ui-tests")
PRODUCED = ("stubs", "newman-gen", "lock", "artifact", "deploy", "ci", "docs")


def kind_of(rel):
    """Вид файла. ПОРЯДОК ПРАВИЛ ЗНАЧИМ — возвращается первое совпавшее.

    Два места, где порядок решает исход, и оба стоили разбора:

    · `internal/repohygiene` и `tools` идут ДО правила про `_test.go`. Гейты
      дерева написаны как тесты by construction — иначе их нечем запускать, — но
      судят они дерево, а не поведение продукта. Оставь их в пробах, и 96 905
      строк гейтов молча запишутся в покрытие;
    · манифесты и артефакты прогонов идут ПЕРВЫМИ, до всего. Иначе
      `package-lock.json` внутри `ui-future/` уедет в ui, а результаты k6 внутри
      `services/vpc/tests/` — в пробы, и обе величины будут неотличимы от
      написанного руками.
    """
    base = os.path.basename(rel)
    p = "/" + rel

    if base in LOCKS:
        return "lock"
    if "/results/" in p or "/scalegrid/" in p or base.startswith("REPORT-"):
        return "artifact"
    if rel.startswith("internal/repohygiene/") or rel.startswith("tools/"):
        return "gates"
    if rel.startswith("pkg/api/") or rel.endswith(".pb.go") or rel.endswith(".pb.gw.go"):
        return "stubs"
    if "/tests/newman/" in p:
        # Коллекции — вывод gen.py, закоммиченный рядом с источником.
        if "/collections/" in p and rel.endswith(".json"):
            return "newman-gen"
        return "newman"
    if rel.startswith("ui-future/e2e/"):
        return "ui-tests"
    if rel.startswith("ui-future/"):
        if ".test." in base or ".spec." in base or "/test/" in p or "/__tests__/" in p:
            return "ui-tests"
        return "ui"
    if rel.endswith("_test.go") or "/testdata/" in p:
        return "tests"
    if rel.startswith("tests/"):
        return "tests"
    if rel.startswith(".github/"):
        return "ci"
    if rel.startswith("deploy/") or "/deploy/" in p or "/helm/" in p:
        return "deploy"
    if os.path.splitext(rel)[1] in DOC_EXT:
        return "docs"
    if "/docs/" in p or rel.startswith("obsidian/"):
        return "docs"
    return "code"


def module_of(rel):
    """Модуль = первый сегмент, кроме services/ и ui-future/ — там второй.

    Для них первый сегмент — это «все сервисы» и «вся консоль», то есть ответ на
    вопрос, которого никто не задаёт.
    """
    parts = rel.split("/")
    if len(parts) == 1:
        return "<корень>"
    if parts[0] in ("services", "ui-future"):
        return parts[0] + "/" + (parts[1] if len(parts) > 2 else "<корень>")
    return parts[0]


def count_text(src, spec):
    """(всего строк, строк кода). Конечный автомат по символам.

    Строковый литерал — не комментарий, и это несущее свойство: без него `//`
    внутри URL съедает строку целиком, а `#` внутри значения YAML — половину
    файла.
    """
    line_marks, blocks = spec["line"], spec["block"]
    quotes, raws, esc = spec["quotes"], spec["raw"], spec["esc"]

    # БЫСТРЫЙ ПУТЬ. Автомат посимвольно по миллиону строк стоит минуту; строка,
    # в которой нет НИ ОДНОГО символа, способного открыть комментарий или
    # литерал, разобрана быть не может — её исход решает `strip()`. Такова
    # большая часть кода, поэтому выигрыш не косметический: 57 с → 12 с на
    # дереве продукта. Множество «интересных» символов ВЫВОДИТСЯ из правил
    # языка, а не выписывается: выпишешь — забудешь дописать при добавлении
    # языка, и быстрый путь начнёт глотать комментарии молча.
    fast = spec.get("_fast")
    if fast is None:
        # Язык без маркеров комментариев (JSON — 903 тыс. строк дерева) разбору
        # не подлежит вовсе: защищать кавычками нечего, и код там — это просто
        # непустая строка. Автомат на нём тратил треть всего времени замера.
        interesting = set()
        if not line_marks and not blocks:
            spec["_fast"] = None
            fast = None
        for m in line_marks:
            interesting.add(m[0])
        for b in blocks:
            interesting.add(b[0][0])
        interesting.update(q[0] for q in quotes)
        interesting.update(r[0] for r in raws)
        if "_fast" not in spec:
            fast = (re.compile("[" + re.escape("".join(sorted(interesting))) + "]").search
                    if interesting else None)
            spec["_fast"] = fast

    total = code = 0
    in_block = None   # закрывающий маркер активного блочного комментария
    in_str = None     # активная кавычка
    in_raw = False

    for ln in src.split("\n"):
        total += 1
        if in_block is None and in_str is None and (fast is None or not fast(ln)):
            if ln.strip():
                code += 1
            continue
        i, n, has_code = 0, len(ln), False
        while i < n:
            if in_block is not None:
                j = ln.find(in_block, i)
                if j < 0:
                    i = n
                else:
                    i, in_block = j + len(in_block), None
                continue
            if in_str is not None:
                if esc and not in_raw and ln[i] == "\\":
                    i += 2
                elif ln.startswith(in_str, i):
                    i += len(in_str)
                    in_str, in_raw = None, False
                else:
                    i += 1
                has_code = True
                continue
            ch = ln[i]
            if ch in " \t\r":
                i += 1
                continue
            if any(ln.startswith(m, i) for m in line_marks):
                break                       # остаток строки — комментарий
            b = next((b for b in blocks if ln.startswith(b[0], i)), None)
            if b:
                i, in_block = i + len(b[0]), b[1]
                continue
            r = next((r for r in raws if ln.startswith(r, i)), None)
            if r:
                i, in_str, in_raw, has_code = i + len(r), r, True, True
                continue
            q = next((q for q in quotes if ln.startswith(q, i)), None)
            if q:
                i, in_str, in_raw, has_code = i + len(q), q, False, True
                continue
            has_code = True
            i += 1
        if has_code:
            code += 1

    if src.endswith("\n"):
        total -= 1
    return total, code


# ─────────────────────────────────────────────────────────────────────────────
# САМОПРОВЕРКА. Девять случаев с известным ответом, в обе стороны. Правишь
# count_text — правь и это: расхождение обязано остановить замер, а не украсить
# его примечанием.
# ─────────────────────────────────────────────────────────────────────────────
SELFTEST = [
    # (имя, расширение, текст, ожидаемых строк кода)
    ("одни комментарии дают НОЛЬ", ".go",
     "// один\n// два\n\n/* три\n четыре */\n", 0),
    ("одни строки кода не занижаются", ".go",
     "package m\nvar a=1\nvar b=2\nvar c=3\nvar d=4\n", 5),
    ("две косые в литерале — не комментарий", ".go",
     'package m\nvar u = "https://x//y" // хвост\n', 2),
    ("raw-строка Go: содержимое считается кодом", ".go",
     "package m\nvar q = `a\n// внутри raw\n`\n", 4),
    ("блок переносится через строки", ".go",
     "package m\n/* открыт\nвнутри\n*/\nvar z=1\n", 2),
    ("экранированная кавычка не закрывает строку", ".go",
     'package m\nvar s = "он \\" // не коммент"\nvar t=2\n', 3),
    ("docstring и shebang Python — не код", ".py",
     '#!/usr/bin/env python3\n"""doc\nstr"""\nimport os  # хвост\nx = "# не коммент"\n', 2),
    # НАЙДЕНО ИНЪЕКЦИЕЙ (ось E). Без этого случая самопроверка НЕ различала
    # снятие кавычек Go: во всех прочих случаях код стоит ДО литерала, поэтому
    # построчный счёт не менялся и сломанный счётчик выглядел исправным. Здесь
    # литерал ЗАКРЫВАЕТ собой открывающий блок — сними кавычки, и `/*` съест три
    # последующие строки, превратив 4 в 2.
    ("литерал не открывает блочный комментарий", ".go",
     'package m\nvar s = "/* не блок"\nvar t = 2\nvar u = 3\n', 4),
    ("SQL: два дефиса и блок", ".sql",
     "-- миграция\nCREATE TABLE t (\n  id text -- ключ\n);\n/* блок */\n", 3),
    ("JSX-комментарий внутри разметки", ".tsx",
     'import R from "r"\n\nexport const A = () => (\n  <div>{/* к */}</div>\n)\n', 4),
]


def selftest():
    """[] если счётчик считает верно, иначе перечень расхождений."""
    bad = []
    for name, ext, src, want in SELFTEST:
        got = count_text(src, LANGS[ext])[1]
        if got != want:
            bad.append("%s (%s): ожидалось %d, получено %d" % (name, ext, want, got))
    return bad


def tree_files(root, with_untracked):
    """Состав дерева глазами git. None — каталог не является репозиторием."""
    args = ["ls-files", "--cached", "--others", "--exclude-standard"] \
        if with_untracked else ["ls-files"]
    try:
        out = subprocess.run(["git", "-C", root] + args,
                             capture_output=True, text=True, check=True).stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    return sorted(set(f for f in out.split("\n") if f))


def head_of(root):
    try:
        r = subprocess.run(["git", "-C", root, "rev-parse", "--short", "HEAD"],
                           capture_output=True, text=True, check=True)
        return r.stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return "?"


def spec_for(rel):
    """(ключ языка, правила) либо (None, None) — язык не описан."""
    key = BY_NAME.get(os.path.basename(rel), os.path.splitext(rel)[1].lower())
    if key in LANGS:
        return key, LANGS[key]
    if key in DOC_EXT:
        return key, PLAIN
    return None, None


def measure(root, with_untracked):
    """Замер одного дерева -> словарь (или None, если это не репозиторий)."""
    files = tree_files(root, with_untracked)
    if files is None:
        return None

    by_module = collections.defaultdict(lambda: collections.defaultdict(lambda: [0, 0, 0]))
    by_lang = collections.defaultdict(lambda: [0, 0, 0])
    paths = collections.defaultdict(list)
    read = unreadable = 0
    skipped = collections.Counter()

    for rel in files:
        key, spec = spec_for(rel)
        if spec is None:
            skipped[os.path.splitext(rel)[1].lower() or "<без расширения>"] += 1
            continue
        try:
            with open(os.path.join(root, rel), "r", encoding="utf-8",
                      errors="replace") as fh:
                src = fh.read()
        except OSError:
            unreadable += 1
            continue
        total, code = count_text(src, spec)
        read += 1
        kind = kind_of(rel)
        cell = by_module[module_of(rel)][kind]
        cell[0] += 1
        cell[1] += total
        cell[2] += code
        lang = by_lang[key]
        lang[0] += 1
        lang[1] += total
        lang[2] += code
        paths[kind].append((rel, code))

    return {
        "root": root,
        "head": head_of(root),
        "census": {
            "состав": "отслеживаемые + неотслеживаемые" if with_untracked
                      else "отслеживаемые",
            "файлов": len(files),
            "прочитано": read,
            "язык не описан": sum(skipped.values()),
            "нечитаемо": unreadable,
            "расширения без правил": dict(skipped.most_common(12)),
        },
        "by_module": {m: dict(d) for m, d in by_module.items()},
        "by_lang": dict(by_lang),
        "paths": dict(paths),
    }


def num(x):
    return "{:,}".format(x).replace(",", " ") if x else "·"


def render(res, show_langs):
    c = res["census"]
    print("ДЕРЕВО %s @ %s" % (res["root"], res["head"]))
    print("ПЕРЕПИСЬ: %s — файлов %d, прочитано %d, язык не описан %d, нечитаемо %d"
          % (c["состав"], c["файлов"], c["прочитано"], c["язык не описан"],
             c["нечитаемо"]))
    if c["расширения без правил"]:
        print("          без правил: %s" % ", ".join(
            "%s %d" % (k, v) for k, v in c["расширения без правил"].items()))
    print()

    kinds = [k for k in FUNCTIONAL
             if any(k in d for d in res["by_module"].values())]
    if not kinds:
        print("рукописного кода не найдено")
    else:
        width = max([len(m) for m in res["by_module"]] + [12]) + 2
        head = "".join("%10s" % KIND_TITLE[k] for k in kinds)
        print("РУКОПИСНЫЙ КОД (строк без комментариев и пустых)")
        print("%-*s%s%11s" % (width, "модуль", head, "ИТОГО"))
        print("─" * (width + 10 * len(kinds) + 11))
        rows = []
        for m, d in res["by_module"].items():
            vals = [d.get(k, [0, 0, 0])[2] for k in kinds]
            if sum(vals):
                rows.append((m, vals))
        totals = [0] * len(kinds)
        for m, vals in sorted(rows, key=lambda r: -sum(r[1])):
            print("%-*s%s%11s" % (width, m,
                                  "".join("%10s" % num(v) for v in vals),
                                  num(sum(vals))))
            for i, v in enumerate(vals):
                totals[i] += v
        print("─" * (width + 10 * len(kinds) + 11))
        print("%-*s%s%11s" % (width, "ВСЕГО",
                              "".join("%10s" % num(v) for v in totals),
                              num(sum(totals))))

    other = collections.defaultdict(lambda: [0, 0])
    for d in res["by_module"].values():
        for k in PRODUCED:
            if k in d:
                other[k][0] += d[k][0]
                other[k][1] += d[k][2]
    if other:
        print("\nЗА ПРЕДЕЛАМИ рукописного кода (машинный вывод, манифесты, тексты):")
        for k, (f, code) in sorted(other.items(), key=lambda x: -x[1][1]):
            print("  %-18s файлов %5d   строк %10s" % (KIND_TITLE[k], f, num(code)))

    if show_langs:
        print("\nПО ЯЗЫКАМ (файлов · всего строк · код):")
        for k, v in sorted(res["by_lang"].items(), key=lambda x: -x[1][2]):
            print("  %-12s %5d %10s %10s" % (k, v[0], num(v[1]), num(v[2])))


def main():
    ap = argparse.ArgumentParser(
        description="Строки кода по модулям: рукописное отдельно от произведённого.")
    ap.add_argument("roots", nargs="*", metavar="ПУТЬ",
                    help="деревья для замера; без аргументов — воркспейс и "
                         "project/kacho, если он резолвится")
    ap.add_argument("--with-untracked", action="store_true",
                    help="добавить неотслеживаемое-неигнорируемое (умолчание — "
                         "только отслеживаемые: замер о репозитории, не о диске)")
    ap.add_argument("--languages", action="store_true", help="разрез по языкам")
    ap.add_argument("--json", action="store_true", help="машинный вывод")
    ap.add_argument("--files", metavar="ВИД",
                    help="перечислить файлы вида, крупнейшие сверху: %s"
                         % ", ".join(sorted(KIND_TITLE)))
    args = ap.parse_args()

    bad = selftest()
    if bad:
        print("[FAIL] sloc — САМОПРОВЕРКА НЕ СОШЛАСЬ, замер не выполнялся:",
              file=sys.stderr)
        for b in bad:
            print("  " + b, file=sys.stderr)
        print("Счётчик считает неверно; правь count_text либо SELFTEST, но не "
              "числа в отчёте.", file=sys.stderr)
        return 1

    workspace = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    roots = args.roots
    if not roots:
        roots = [workspace]
        product = os.path.join(workspace, "project", "kacho")
        if os.path.exists(os.path.join(product, ".git")):
            roots.insert(0, product)

    results = []
    for root in roots:
        res = measure(os.path.abspath(root), args.with_untracked)
        if res is None:
            print("[VOID] sloc — %s не является git-репозиторием" % root,
                  file=sys.stderr)
            return 2
        if res["census"]["прочитано"] == 0:
            print("[VOID] sloc — в %s не прочитано НИ ОДНОГО файла (файлов в "
                  "составе %d). Ноль строк и ноль прочитанного — разные вещи."
                  % (root, res["census"]["файлов"]), file=sys.stderr)
            return 2
        results.append(res)

    if args.json:
        print(json.dumps(results, ensure_ascii=False, indent=1))
        return 0

    if args.files:
        if args.files not in KIND_TITLE:
            print("[VOID] sloc — вида «%s» нет; известны: %s"
                  % (args.files, ", ".join(sorted(KIND_TITLE))), file=sys.stderr)
            return 2
        for res in results:
            rows = res["paths"].get(args.files, [])
            print("%s @ %s — вид «%s»: файлов %d, строк %s"
                  % (res["root"], res["head"], KIND_TITLE[args.files], len(rows),
                     num(sum(c for _, c in rows))))
            for rel, code in sorted(rows, key=lambda r: -r[1])[:40]:
                print("  %8s  %s" % (num(code), rel))
            print()
        return 0

    for i, res in enumerate(results):
        if i:
            print("\n" + "═" * 78 + "\n")
        render(res, args.languages)
    return 0


if __name__ == "__main__":
    sys.exit(main())
