#!/usr/bin/env python3
"""check-06 — число в шапке скрипта набора либо несёт команду своего воспроизведения, либо краснит.

ЧТО УТВЕРЖДАЕТ (ws#760). В шапке каждого скрипта верхнего уровня каждого набора
всякое число-утверждение («N <единиц>») стоит в одном абзаце с процитированной
командой, которая ИСПОЛНЯЕТСЯ и выдаёт ровно это число. Число без команды и число,
разошедшееся с выводом своей команды, — находки с координатой.

ЦЕНА. Число, названное в шапке фактом о дереве, читается как факт и стареет молча:
его неверность не роняет ничего. Хуже — без объявленной единицы счёта оно не
опровержимо: шапка части инъекции rules-gate называла одно число осей, разметка
её секций давала другое, полоса, нашедшая расхождение, насчитала третье, — каждый
счёт добросовестен, ответы разные, и спор неразрешим. Команда воспроизведения
называет единицу счёта сама.

ЕДИНИЦА СЧЁТА ЭТОЙ ПРОВЕРКИ — объявлена, а не подразумевается:
  шапка          — у `.sh` — сплошной блок строк `#` от начала файла (после `#!`),
                   у `.py` — ведущие строки `#` и строка документации модуля;
  абзац          — строки шапки между пустыми строками комментария;
  число-утверждение — числительное (цифрами либо словом от «два» до «двадцать»
                   в любом падеже) перед существительным из закрытого словаря
                   ЕДИНИЦ либо после него («осей — N», «кейсов: N»); словарь
                   (`UNITS` ниже: проверки, наборы, пробы, оси, кейсы, файлы,
                   записки, агенты, правила, строки, задания, прогонщики, инъекции,
                   утверждения, прогоны, контексты, скилы, вызовы, коммиты, время).
                   Легенда кода («2 — без предмета»), номер задачи (#N), номер
                   проверки (check-NN), координата (:N), дата, версия — не
                   числа-утверждения: их отсекает граница токена;
  команда        — процитированная в обратных кавычках в том же абзаце, первое
                   слово `git`/`grep`/`find`/`ls`, звенья трубы — только из
                   `wc`/`grep`/`sort`/`uniq`/`cut`/`sed`/`awk`/`head`/`tail`/`tr`,
                   без `;` `&` `$` `(` `)` `<` `>` вне одинарных кавычек. Документ —
                   не место, откуда исполняется что угодно.
Числа вне словаря единиц не судятся и перечисляются в переписи отдельным числом.

ОБХОД. Скрипты ВЕРХНЕГО уровня каталогов наборов (`*.sh`, `*.py`) — шапки
исполняемых входов и библиотек набора — и все `*.sh`/`*.py` общей библиотеки наборов
`scripts/lib/` (прогонщик, вывод перечня, корень, перепись: круг 1 показал, что
число-утверждение о наборах в шапке `suite-runner.sh` проходило, не будучи прочитанным).
Файлы вложенных каталогов наборов (пакеты, фикстуры, пробы) в обход не входят и
названы в переписи числом; перечень наборов выведен переписью `scripts/lib/suites.py`.
Ноль скриптов — VOID.

ВНЕ ОБХОДА — НЕ СУДИТСЯ, НО СЧИТАЕТСЯ. Прочие `*.sh`/`*.py` под `scripts/`
(`compliance/`, `specs/`, `hooks/`, скрипты верхнего уровня `scripts/`…) разбираются тем
же распознавателем, и отдельная строка переписи называет, сколько там файлов по
каталогам и сколько чисел-утверждений в их шапках, — без исполнения команд. Иначе
«находок 0» для них неотличимо от «не осмотрено». Судить их здесь — значит править
файлы других областей.

Коды: 0 — каждое число шапки воспроизводится; 1 — находка; 2 — осматривать нечего.
"""
import ast
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _lib  # noqa: E402

NAME = "check-06-header-numbers-carry-their-predicate"
LIB = "scripts/lib/"

WORDS = {}
for value, forms in {
    2: "два две двух двум двумя", 3: "три трёх трех трём трем тремя",
    4: "четыре четырёх четырех четырём четырем четырьмя", 5: "пять пяти пятью",
    6: "шесть шести шестью", 7: "семь семи семью", 8: "восемь восьми восемью",
    9: "девять девяти девятью", 10: "десять десяти десятью",
    11: "одиннадцать одиннадцати", 12: "двенадцать двенадцати",
    13: "тринадцать тринадцати", 14: "четырнадцать четырнадцати",
    15: "пятнадцать пятнадцати", 16: "шестнадцать шестнадцати",
    17: "семнадцать семнадцати", 18: "восемнадцать восемнадцати",
    19: "девятнадцать девятнадцати", 20: "двадцать двадцати",
}.items():
    for f in forms.split():
        WORDS[f] = value

UNITS = (r"провер(?:ка|ки|ке|ку|кой|ок|кам|ками|ках)|набор(?:а|у|ом|е|ы|ов|ам|ами|ах)?"
         r"|проб(?:а|ы|е|у|ой|ам|ами|ах)?|ос(?:ь|и|ей|ям|ями|ях)"
         r"|кейс(?:а|у|ом|е|ы|ов|ам|ами|ах)?|файл(?:а|у|ом|е|ы|ов|ам|ами|ах)?"
         r"|записк(?:а|и|е|у|ой|ам|ами|ах)|записок|агент(?:а|у|ом|е|ы|ов|ам|ами|ах)?"
         r"|правил(?:о|а|у|ом|е|ам|ами|ах)?|строк(?:а|и|е|у|ой|ам|ами|ах)?"
         r"|задани(?:е|я|ю|ем|и|й|ям|ями|ях)|job(?:'?\w*)?"
         r"|прогонщик(?:а|у|ом|е|и|ов|ам|ами|ах)?|инъекци(?:я|и|ю|ей|й|ям|ями|ях)"
         r"|утверждени(?:е|я|ю|ем|и|й|ям|ями|ях)|прогон(?:а|у|ом|е|ы|ов|ам|ами|ах)?"
         r"|контекст(?:а|у|ом|е|ы|ов|ам|ами|ах)?|скил(?:а|у|ом|е|ы|ов|ам|ами|ах)?"
         r"|вызов(?:а|у|ом|е|ы|ам|ами|ах)?|коммит(?:а|у|ом|е|ы|ов|ам|ами|ах)?"
         r"|секунд(?:а|ы|у|ой|ам|ами|ах)?|сек|с|мин|минут(?:а|ы|у|ой|ам|ами|ах)?")
NUMTOK = r"(\d+(?:[.,]\d+)?|" + "|".join(sorted(WORDS, key=len, reverse=True)) + r")"
CLAIM = re.compile(r"(?<![\w#.:/\-≥≤<>=~@+])" + NUMTOK + r"(?![\w.:/\-%])"
                   r"\s+(?:[^\W\d_]+(?:-[^\W\d_]+)*\s+)?(" + UNITS + r")(?![\w])", re.I)
# Обратная форма («осей — 3», «кейсов: 196», «утверждений три», «Наборов 8.» —
# точка в конце предложения числа не отменяет; круг 1: такая шапка проходила). Отсекаются
# формы, которые числом-утверждением не являются: легенда кода («прогонщиков:
# 0 — прошло»), номер с ведущим нулём («проверки 02» — адрес проверки) и голая
# одиночная цифра без разделителя («набор 1» — код исхода).
CLAIM_REV = re.compile(r"(?<![\w\-])(" + UNITS + r")(\s*(?:—|–|:|=)\s*|\s+)" + NUMTOK
                       + r"(?![\w:/\-%])(?![.,]\d)(?!\s*[—–])", re.I)
NUMBER_ANY = re.compile(r"(?<![\w#.:/\-])\d+(?![\w.:/\-])")
COMMAND = re.compile(r"`([^`\n]+)`")
FIRST = ("git", "grep", "find", "ls")
PIPED = ("wc", "grep", "sort", "uniq", "cut", "sed", "awk", "head", "tail", "tr")
UNSAFE = set(";&$()<>`")


def header(path, text):
    """[(номер строки, текст строки шапки без маркера комментария)]."""
    lines = text.split("\n")
    out = []
    i = 1 if lines and lines[0].startswith("#!") else 0
    while i < len(lines) and lines[i].startswith("#"):
        out.append((i + 1, lines[i][1:]))
        i += 1
    if path.endswith(".py"):
        try:
            mod = ast.parse(text)
        except SyntaxError:
            return out
        if mod.body and isinstance(mod.body[0], ast.Expr) \
                and isinstance(getattr(mod.body[0], "value", None), ast.Constant) \
                and isinstance(mod.body[0].value.value, str):
            first = mod.body[0].lineno
            last = getattr(mod.body[0], "end_lineno", first)
            for n in range(first, last + 1):
                out.append((n, lines[n - 1]))
    return out


def paragraphs(head):
    """Абзацы шапки: [(текст абзаца, [(смещение, номер строки)])]."""
    paras, cur, offsets = [], [], []
    for n, line in head:
        if not line.strip():
            if cur:
                paras.append((" ".join(cur), offsets))
            cur, offsets = [], []
            continue
        offsets.append((sum(len(c) + 1 for c in cur), n))
        cur.append(line.strip())
    if cur:
        paras.append((" ".join(cur), offsets))
    return paras


def line_at(offsets, pos):
    n = offsets[0][1]
    for off, ln in offsets:
        if off <= pos:
            n = ln
    return n


def safe_command(cmd):
    """Команда исполнима по политике проверки: первое слово и звенья — из закрытых
    перечней, опасные знаки только внутри одинарных кавычек."""
    quote = False
    outside = []
    for ch in cmd:
        if ch == "'":
            quote = not quote
            continue
        if not quote:
            outside.append(ch)
    if quote or UNSAFE & set(outside):
        return False
    stages = "".join(outside).split("|")
    words = [s.split() for s in stages]
    if not words or not words[0] or words[0][0] not in FIRST:
        return False
    return all(w and w[0] in PIPED for w in words[1:])


def execute(ws, cmd, cache):
    if cmd not in cache:
        try:
            out = subprocess.run(["bash", "-c", cmd], cwd=ws, capture_output=True, text=True,
                                 timeout=60, env=_lib.clean_env())
            val = out.stdout.strip()
            cache[cmd] = (out.returncode, val)
        except (OSError, subprocess.SubprocessError) as exc:
            cache[cmd] = (None, str(exc))
    return cache[cmd]


def short(out):
    """Вывод команды в находке: первая строка, не длиннее строки отчёта."""
    first = out.split("\n", 1)[0]
    more = " …" if "\n" in out or len(first) > 60 else ""
    return first[:60] + more


def value_of(token):
    t = token.lower().replace(",", ".")
    if t in WORDS:
        return WORDS[t]
    try:
        return float(t) if "." in t else int(t)
    except ValueError:
        return None


def claims_in(para):
    """[(смещение, число, фраза)] — числа-утверждения абзаца шапки."""
    found = [(m.start(), m.group(1), m.group(0)) for m in CLAIM.finditer(para)
             if not (m.group(1)[0] == "0" and len(m.group(1)) > 1)]
    taken = {m.start(1) for m in CLAIM.finditer(para)}
    for m in CLAIM_REV.finditer(para):
        tok, sep = m.group(3), m.group(2).strip()
        if tok[0] == "0" and len(tok) > 1:
            continue
        if not sep and not re.match(r"\s*(?:[,.;:)]|$)", para[m.end():]):
            continue           # «проверок три разных исхода» — число не при этой единице
        if m.start(3) not in taken:
            found.append((m.start(), tok, m.group(0)))
    return found


def read(ws, rel):
    with open(os.path.join(ws, rel), encoding="utf-8", errors="replace") as fh:
        return fh.read()


def main():
    ws = _lib.root(__file__)
    names, _ = _lib.suite_census(NAME, ws)
    if not names:
        _lib.void(NAME, "наборов scripts/*/run-all.sh в %s нет — осматривать нечего" % ws)
        return 2
    top, nested = [], 0
    for s in names:
        for rel in _lib.S.suite_files(ws, s):
            if rel.count("/") != 2:
                nested += 1
            elif rel.endswith((".sh", ".py")):
                top.append(rel)
    if not top:
        _lib.void(NAME, "наборов %d, скриптов верхнего уровня 0 — осматривать нечего" % len(names))
        return 2
    try:
        under = [r for r in _lib.S.tracked(ws, "scripts/") if r.endswith((".sh", ".py"))]
    except _lib.S.CensusUnreadable as exc:
        _lib.void(NAME, "перепись scripts/ не снята: %s" % exc)
        return 2
    # Общая библиотека наборов — часть их устройства: прогонщик, вывод перечня,
    # корень, перепись. Её шапки судятся наравне со скриптами наборов.
    lib = [r for r in under if r.startswith(LIB)]
    top += lib
    suite_dirs = tuple("scripts/%s/" % s for s in names)
    outside = [r for r in under if not r.startswith(LIB) and not r.startswith(suite_dirs)]

    findings = []
    claims = paired = others = header_lines = 0
    cache = {}
    for rel in top:
        try:
            with open(os.path.join(ws, rel), encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError as exc:
            findings.append("%s — не читается: %s" % (rel, exc))
            continue
        head = header(rel, text)
        header_lines += len(head)
        for para, offsets in paragraphs(head):
            found = claims_in(para)
            others += max(0, len(NUMBER_ANY.findall(para))
                          - sum(1 for _, tok, _ in found if tok[0].isdigit()))
            if not found:
                continue
            cmds = [c for c in COMMAND.findall(para) if safe_command(c)]
            results = [(c,) + execute(ws, c, cache) for c in cmds]
            for start, token, phrase in found:
                claims += 1
                n = line_at(offsets, start)
                want = value_of(token)
                ok = [c for c, rc, out in results
                      if rc == 0 and out.isdigit() and want == int(out)]
                if ok:
                    paired += 1
                    continue
                if results:
                    got = "; ".join("`%s` → %s" % (c, short(out) if rc == 0 else "отказ (код %s)" % rc)
                                    for c, rc, out in results)
                    findings.append("%s:%d — «%s»: объявлено %s, команды абзаца дают другое: %s"
                                    % (rel, n, phrase, token, got))
                else:
                    findings.append("%s:%d — «%s»: число названо фактом, а команды его "
                                    "воспроизведения в абзаце нет — единица счёта не объявлена, "
                                    "и число стареет молча" % (rel, n, phrase))

    # Вне обхода — не судится, но СЧИТАЕТСЯ тем же распознавателем: «ноль находок»
    # отличим от «не осмотрено», и число утверждений там названо.
    out_claims = {}
    for rel in outside:
        try:
            text = read(ws, rel)
        except OSError:
            continue
        n = sum(len(claims_in(para)) for para, _ in paragraphs(header(rel, text)))
        if n:
            key = rel.split("/")[1] if rel.count("/") > 1 else "scripts/"
            out_claims[key] = out_claims.get(key, 0) + n
    by_dir = {}
    for rel in outside:
        key = rel.split("/")[1] if rel.count("/") > 1 else "scripts/"
        by_dir[key] = by_dir.get(key, 0) + 1

    _lib.census(NAME, "наборов %d; скриптов %d (верхнего уровня наборов %d, общей библиотеки "
                "%s %d), строк шапок %d; чисел-утверждений %d, из них воспроизведено "
                "командой %d; прочих чисел в шапках (вне словаря единиц, не судятся) %d; "
                "файлов во вложенных каталогах наборов вне обхода %d; находок %d"
                % (len(names), len(top), len(top) - len(lib), LIB, len(lib), header_lines,
                   claims, paired, others, nested, len(findings)))
    _lib.census(NAME, "ВНЕ ОБХОДА под scripts/ (не наборы и не %s) — не судится, считается: "
                "файлов .sh/.py %d%s; чисел-утверждений в их шапках %d%s"
                % (LIB, len(outside),
                   " (%s)" % ", ".join("%s %d" % kv for kv in sorted(by_dir.items()))
                   if by_dir else "",
                   sum(out_claims.values()),
                   " (%s)" % ", ".join("%s %d" % kv for kv in sorted(out_claims.items()))
                   if out_claims else ""))
    if findings:
        for f in findings:
            _lib.finding(f)
        _lib.fail(NAME, "чисел в шапках без воспроизведения: %d" % len(findings))
        return 1
    _lib.passed(NAME, "каждое из %d чисел-утверждений в шапках %d скриптов воспроизведено "
                "своей командой" % (claims, len(top)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
