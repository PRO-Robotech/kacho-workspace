#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ПРИБОР: сколько в оснастке утверждений о ПОВЕДЕНИИ НАЗВАННОЙ ПРОВЕРКИ и
сколько из них можно уличить в устаревании иначе, чем прочитав глазами.

НЕ ГЕЙТ. Вердикта о дереве не выносит, ни в один `run-all.sh` не подключён (имя
намеренно не `check-*`), красным не бывает. Код 0 — замер исполнен; код 2 —
мерить оказалось не на чем. Заведён потому, что число, названное в тексте,
устаревает молча: этот прибор его ПРОИЗВОДИТ обходом дерева на каждом прогоне.

# ЧТО СЧИТАЕТСЯ ОДНИМ УТВЕРЖДЕНИЕМ — единица объявлена, иначе число не читается

Одно утверждение — один текстовый элемент, который НАЗЫВАЕТ конкретную проверку
(именем пробы, координатой скрипта, номером `check-NN`, именем набора) И
утверждает о ней что-то, что может стать неправдой:

  A  поле ДЕРЖАТЕЛЯ строки-нормы корпуса `.claude/rules/*.md` — «эту норму
     держит вот эта проверка». Поле `red:` той же строки считается ЧАСТЬЮ того
     же утверждения, а не вторым: оно говорит, на чём тот же держатель краснеет.
     Считать его отдельно значило бы удвоить число, не изменив вывода.
  B  колонка «чем соблюдение обеспечено» таблицы `.claude/rules/MANIFEST.md`.
  C  абзац прозы либо сплошной блок комментария (в агенте, скиле, `CLAUDE.md`,
     конвейере, файлах наборов), называющий проверку и утверждающий о её
     поведении — «ловит», «молчит», «краснеет», «измерено», «якорей N».
  D  ИСПОЛНЯЕМАЯ координата проверки в конвейере — шаг `run:` и путь в нём.

Не считаются: строки-нормы с объявленным долгом (`ЗАВЕСТИ …`, «КАНДИДАТ НА
ГЕЙТ») и с держателем «вниманием» — они утверждают, что машинного держателя НЕТ,
и устареть в сторону лжи о поведении не могут.

# ПРОВЕРЯЕМОСТЬ УСТАНОВЛЕНА ОПЫТОМ, А НЕ ЧТЕНИЕМ КОДА

Вопрос «существует ли способ узнать, что утверждение устарело» решается
подменой: вносим в утверждение дефект и смотрим, заговорит ли хоть один набор.
Замер 2026-09-21, контроль — rules=0 skills=2 (беспредметен без дерева продукта)
tooling=0:

  1  имя пробы в поле держателя заменено на несуществующее   → 0 / 2 / 0  НЕТ
  2  путь в поле держателя заменён на несуществующий          → 0 / 2 / 0  НЕТ
  7  в колонке MANIFEST названа несуществующая проверка       → 0 / 2 / 0  НЕТ
  8  в теле агента названа несуществующая проверка            → 0 / 2 / 0  НЕТ
  4  проза шапки гейта вывернута наизнанку                    → 0 / 2 / 0  НЕТ
  6  число внутри шапки гейта («якорей 12») переписано        → 0 / 2 / 0  НЕТ
  3  число рядом с ИСПОЛНЯЕМОЙ цитатой в `ai-tooling.md`      → 0 / 1 / 0  ДА
  5  путь проверки в конвейере заменён на несуществующий      → 0 / 2 / 1  ДА

Держателей у проверяемых двое, и оба узкие:
  · `scripts/skills-gate/check-07-declared-counts-match-tree.sh` — ИСПОЛНЯЕТ
    процитированную рядом с числом команду `git …` и сверяет вывод. Область —
    один файл `.claude/rules/ai-tooling.md`;
  · `scripts/tooling-gate/check-01-workflow-paths.sh` — резолвит КАЖДУЮ
    координату пути в `.github/workflows/**`. Держит только СУЩЕСТВОВАНИЕ
    проверки по названному адресу, не её поведение.

Воспроизвести любую строку таблицы: внести подмену, прогнать
`bash scripts/<набор>-gate/run-all.sh; echo $?` по трём наборам, вернуть дерево.
"""
import ast
import collections
import glob
import os
import re
import subprocess
import sys

WS = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PROD = os.path.join(WS, "project")

NAMES = re.compile(
    r"\b(?:(?:Test|Benchmark|Fuzz)[A-Z][A-Za-z0-9_]{3,}"
    r"|check-\d\d[A-Za-z0-9_-]*|inject-\d\d[A-Za-z0-9_-]*"
    r"|[a-z]+-gate|run-all\.sh|inject\.sh|assert-suites-green\.sh"
    r"|[a-z0-9_]+_test\.go|measure-monotonicity\.sh|branch-audit\.sh"
    r"|merge-readiness\.sh|exec-coverage\.py)\b")
BEHAV = re.compile(
    r"(ловит|ловится|краснеет|краснел|молчит|молчал|падает|падал|печатает"
    r"|печатал|зелён|зелен|зеленел|выходит|код [0-9]\b|кодом [0-9]|находок \d"
    r"|проверок \d|утверждений \d|якорей \d+|проб \d|осмотрено \d|прочитано \d"
    r"|измерено|замер|перемерено|слеп|не видит|НЕ ловит|не ловит|НЕ держит"
    r"|не держит|вердикт|доказ|инъекци|судит|сторожит|держит)")
TOK = re.compile(r"\b((?:Test|Benchmark|Fuzz)[A-Z][A-Za-z0-9_]{3,})\b")
DIR = re.compile(r"\b((?:scripts|internal|tools|tests|gateway|services|corelib"
                 r"|pkg|deploy|ui-future|docs|cmd)/[A-Za-z0-9_*./-]+)")
# Голое имя файла проверки — такая же координата, как путь: `assert-suites-green.sh`
# адресует ровно один артефакт дерева. Считать его прозой значило бы объявить
# непроверяемое проверяемым по свойству разборщика.
BARE = re.compile(r"\b([a-z0-9][A-Za-z0-9_.-]*\.(?:sh|py|go|awk|ts))\b")
COORD = re.compile(r"(scripts/[A-Za-z0-9_.*/-]+|\.github/workflows/[A-Za-z0-9_.-]+)")


def repos():
    if not os.path.isdir(PROD):
        return []
    return [r for r in sorted(os.listdir(PROD))
            if os.path.isdir(os.path.join(PROD, r, ".git"))]


def go_probe_names(rs):
    names = set()
    for r in rs:
        out = subprocess.run(
            ["git", "-C", os.path.join(PROD, r), "grep", "-hoE",
             r"func (Test|Benchmark|Fuzz)[A-Za-z0-9_]+"],
            capture_output=True, text=True).stdout
        names |= set(re.findall(r"func ((?:Test|Benchmark|Fuzz)[A-Za-z0-9_]+)", out))
    return names


def path_resolves(p, rs):
    """Путь резолвится в воркспейсе либо в любом дереве продукта. Знаки
    подстановки НЕ вычищаются, а отдаются `git ls-files`: `services/*/x.sql` —
    законная координата класса, и вычистить звезду значило бы объявить её
    висячей по свойству разборщика."""
    p = p.rstrip(".,;)`")
    if not p:
        return False
    if os.path.exists(os.path.join(WS, p)):
        return True
    if "*" in p:
        if subprocess.run(["git", "-C", WS, "ls-files", "--", p],
                          capture_output=True, text=True).stdout.strip():
            return True
    for r in rs:
        root = os.path.join(PROD, r)
        if os.path.exists(os.path.join(root, p)):
            return True
        head, _, tail = p.partition("/")
        if head == r and tail and os.path.exists(os.path.join(root, tail)):
            return True
        if subprocess.run(["git", "-C", root, "ls-files", "--", p],
                          capture_output=True, text=True).stdout.strip():
            return True
    return False


def file_resolves(base, rs):
    """Голое имя файла ищется по индексу git — своего дерева и каждого дерева
    продукта. По диску искать нельзя: посторонний файл рядом с репозиторием
    сделал бы утверждение «резолвится» свойством рабочего каталога."""
    for root in [WS] + [os.path.join(PROD, r) for r in rs]:
        if subprocess.run(["git", "-C", root, "ls-files", "--", "*" + base],
                          capture_output=True, text=True).stdout.strip():
            return True
    return False


def gate_number(script, pattern):
    """Число берётся у ТОГО, КТО ЕГО ПРОИЗВОДИТ: прибор прогоняет проверку и
    читает её перепись. Свой второй счёт был бы вторым представлением одной
    величины и разошёлся бы молча (`ai-tooling.md`, at-two-numbers-one-predicate)."""
    out = subprocess.run(["bash", os.path.join(WS, script)], cwd=WS,
                         capture_output=True, text=True).stdout
    m = re.search(pattern, out)
    return int(m.group(1)) if m else None


def field(line, i):
    parts = line.split(" · ")
    return parts[i].strip() if len(parts) > i else ""


def blocks(path):
    """Единица прозы: абзац .md, сплошной блок комментария, СТРОКА ДОКУМЕНТАЦИИ.

    ТРЕТЬЯ ФОРМА ДОБАВЛЕНА ПОСЛЕ ЗАМЕРА, А НЕ ПРИДУМАНА. Первая редакция брала у
    `.py` только строки с решёткой — и не видела ни одной шапки python-проверки,
    потому что все они написаны тройными кавычками. Прибор при этом печатал
    число и молчал о пропущенном: ровно тот дефект, который он и считает.
    Обнаружено тем, что прибор насчитал НОЛЬ утверждений в собственной шапке.
    """
    text = open(path, encoding="utf-8", errors="replace").read()
    lines = text.split("\n")
    cur, out = [], []

    def flush():
        if cur:
            out.append("\n".join(cur))
            cur.clear()

    comment = path.endswith((".sh", ".py", ".awk", ".yaml", ".yml"))
    for ln in lines:
        head = ln.lstrip()
        keep = head.lstrip("#").strip() if comment else ln.strip()
        if (head.startswith("#") if comment else bool(ln.strip())):
            cur.append(keep)
        else:
            flush()
    flush()

    if path.endswith(".py"):
        try:
            tree = ast.parse(text)
        except SyntaxError:
            return out
        for node in ast.walk(tree):
            if not isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef,
                                     ast.AsyncFunctionDef)):
                continue
            doc = ast.get_docstring(node)
            if not doc:
                continue
            # Абзац строки документации — та же единица, что абзац markdown.
            for para in re.split(r"\n\s*\n", doc):
                if para.strip():
                    out.append(para.strip())
    return out


def main():
    rs = repos()
    names = go_probe_names(rs)
    tracked = set(subprocess.run(["git", "-C", WS, "ls-files"],
                                 capture_output=True, text=True).stdout.split("\n"))

    # ── A: поле держателя строки-нормы ──────────────────────────────────────
    rows = []
    for f in sorted(glob.glob(os.path.join(WS, ".claude/rules/*.md"))):
        rel = os.path.relpath(f, WS)
        for i, ln in enumerate(open(f, encoding="utf-8"), 1):
            ln = ln.rstrip("\n")
            if " · " in ln:
                rows.append((rel, i, ln))

    cls = collections.Counter()
    a_claims, dangling = 0, []
    for rel, i, ln in rows:
        h = field(ln, 2)
        if not h:
            cls["поле держателя отсутствует"] += 1
            continue
        if h in ("—", "-"):
            cls["держателя нет («—»)"] += 1
            continue
        if h.startswith("ЗАВЕСТИ") or "КАНДИДАТ НА ГЕЙТ" in h:
            cls["объявленный долг: держателя НЕТ и это сказано"] += 1
            continue
        if re.match(r"^вниманием\b", h):
            cls["«вниманием»: машинного держателя нет и это сказано"] += 1
            continue
        toks, paths = TOK.findall(h), DIR.findall(h)
        bares = [b for b in BARE.findall(h) if not any(b in p for p in paths)]
        if not (toks or paths or bares):
            cls["проза: держатель назван словами, не координатой"] += 1
            continue
        a_claims += 1
        cls["НАЗВАНА проверка координатой — утверждение класса"] += 1
        bad = []
        if names:
            bad += ["проба " + t for t in toks
                    if t not in names and not any(n.startswith(t) for n in names)]
        bad += ["путь " + p for p in paths if not path_resolves(p, rs)]
        bad += ["файл " + b for b in bares if not file_resolves(b, rs)]
        if bad:
            dangling.append((rel, i, field(ln, 0), "; ".join(bad)))

    # ── B: колонка «чем соблюдение обеспечено» таблицы MANIFEST ─────────────
    # Число строк таблицы производит check-03 — у него оно и берётся.
    b_claims = gate_number("scripts/rules-gate/check-03-manifest-row-is-complete.sh",
                           r"строк таблицы разобрано (\d+)")

    # ── C: проза, называющая проверку и утверждающая о её поведении ─────────
    areas = {
        "агенты .claude/agents": sorted(glob.glob(os.path.join(WS, ".claude/agents/*.md"))),
        "скилы .claude/skills (не rule-*)": sorted(
            p for p in glob.glob(os.path.join(WS, ".claude/skills/*/SKILL.md"))
            if not os.path.basename(os.path.dirname(p)).startswith("rule-")),
        "общий протокол CLAUDE.md": [os.path.join(WS, "CLAUDE.md")],
        "конвейер .github/workflows": sorted(glob.glob(os.path.join(WS, ".github/workflows/*.y*ml"))),
        "хуки .claude/hooks": sorted(
            p for p in glob.glob(os.path.join(WS, ".claude/hooks/**"), recursive=True)
            if os.path.isfile(p) and os.path.relpath(p, WS) in tracked),
        "наборы scripts/*-gate": sorted(
            p for p in glob.glob(os.path.join(WS, "scripts/*-gate/**"), recursive=True)
            if os.path.isfile(p) and os.path.relpath(p, WS) in tracked
            and p.endswith((".sh", ".py", ".awk", ".md"))),
    }
    # ОСТАЛЬНАЯ ОСНАСТКА БЕРЁТСЯ ВЫЧИТАНИЕМ, А НЕ ПЕРЕЧНЕМ КАТАЛОГОВ. Перечень
    # («scripts/*», «scripts/hooks», …) — тот самый способ пропустить каталог
    # молча: ровно так родилось утверждение «гейта не существует» при двух
    # каталогах проверок. Здесь обход берёт ВЕСЬ `scripts/` из индекса git и
    # вычитает уже осмотренные наборы; каталог, заведённый завтра, попадает в
    # замер сам.
    seen = {os.path.abspath(p) for fs in areas.values() for p in fs}
    areas["прочая оснастка scripts/** (вне наборов)"] = sorted(
        os.path.join(WS, rel) for rel in tracked
        if rel.startswith("scripts/")
        and os.path.isfile(os.path.join(WS, rel))
        and os.path.abspath(os.path.join(WS, rel)) not in seen
        and rel.endswith((".sh", ".py", ".awk", ".md")))
    c_by_area, c_claims, c_blocks, c_self = {}, 0, 0, 0
    me = os.path.abspath(__file__)
    for area, files in areas.items():
        n = 0
        for f in files:
            if not os.path.isfile(f):
                continue
            for b in blocks(f):
                c_blocks += 1
                if NAMES.search(b) and BEHAV.search(b):
                    n += 1
                    if os.path.abspath(f) == me:
                        c_self += 1
        c_by_area[area] = (len(files), n)
        c_claims += n

    # ── D: исполняемые координаты проверок в конвейере ──────────────────────
    d_coords = set()
    for f in sorted(glob.glob(os.path.join(WS, ".github/workflows/*.y*ml"))):
        for m in COORD.findall(open(f, encoding="utf-8").read()):
            d_coords.add(m.rstrip(".,;)`"))
    d_claims = len(d_coords)

    # ── E: числа, объявленные рядом с исполняемой цитатой ───────────────────
    # Число производит сам держатель — check-07 skills-gate, он же их и сверяет.
    e_claims = gate_number(
        "scripts/skills-gate/check-07-declared-counts-match-tree.sh",
        r"из них с объявленным числом (\d+)")

    total = a_claims + b_claims + c_claims + d_claims + e_claims
    verifiable = d_claims + e_claims

    if b_claims is None or e_claims is None:
        print("ОТКАЗ — перепись держателя не прочитана: check-03 дал %r,"
              " check-07 дал %r. Считать эти слои своим счётом значило бы завести"
              " второе представление одной величины." % (b_claims, e_claims))
        return 2

    if not rows or not areas["наборы scripts/*-gate"]:
        print("ОТКАЗ — обход пуст: строк-норм %d, файлов наборов %d. Замер"
              " беспредметен." % (len(rows), len(areas["наборы scripts/*-gate"])))
        return 2

    print("ПЕРЕПИСЬ: утверждения о поведении НАЗВАННОЙ проверки")
    print("деревьев продукта прочитано: %d (%s); имён Go-проб в индексе: %d"
          % (len(rs), ", ".join(rs) or "нет", len(names)))
    if not names:
        print("  ВНИМАНИЕ: деревьев продукта нет — ось «имя пробы резолвится»"
              " НЕ ИЗМЕРЕНА, и ноль висячих здесь означал бы «не смотрели»")
    print()
    print("A  поле держателя строки-нормы корпуса .claude/rules/*.md")
    print("   строк-норм всего: %d" % len(rows))
    for k, n in cls.most_common():
        print("     %5d  %s" % (n, k))
    print("B  колонка «чем соблюдение обеспечено» таблицы MANIFEST.md: %d" % b_claims)
    print("C  проза, называющая проверку и утверждающая о её поведении"
          " (блоков осмотрено %d):" % c_blocks)
    for area, (nf, n) in c_by_area.items():
        print("     %5d  %-38s файлов %d" % (n, area, nf))
    print("     из них в шапке САМОГО ЭТОГО ПРИБОРА: %d — он утверждает о"
          " проверках наравне с прочими и себя не вычитает: вычесть значило бы"
          " завести первую строку ведомости исключений." % c_self)
    print("D  исполняемые координаты проверок в конвейере: %d" % d_claims)
    print("E  числа рядом с исполняемой цитатой-предикатом: %d" % e_claims)
    print()
    print("ИТОГО утверждений класса: %d" % total)
    print("ПРОВЕРЯЕМЫХ (существует машинный способ уличить в устаревании): %d"
          " — D держит tooling-gate/check-01 (только СУЩЕСТВОВАНИЕ адреса),"
          " E держит skills-gate/check-07 (исполняет цитату)." % verifiable)
    print("НЕПРОВЕРЯЕМЫХ: %d из %d (%.1f%%) — ни один набор на подмену не"
          " реагирует, таблица опытов в шапке этого файла."
          % (total - verifiable, total, 100.0 * (total - verifiable) / total))
    print()
    print("УЖЕ ЛОЖНЫХ в слое A (координата держателя не резолвится): %d"
          % len(dangling))
    for rel, i, idd, why in dangling:
        print("   %s:%d  %-34s %s" % (rel, i, idd, why))
    return 0


if __name__ == "__main__":
    sys.exit(main())
