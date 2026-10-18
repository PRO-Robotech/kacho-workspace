#!/usr/bin/env python3
"""Перепись ловушек снятия временного каталога для check-26 (ws#1189, ws#1193).

Предмет — каждая строка файла оболочки, начинающаяся с `trap` (вне heredoc и
комментария). Единица разбора — ОПЕРАТОР целиком, а не строка: он собирается из
строк, пока `bash -n` не признает его законченным, поэтому многострочная
`trap '…\n…' EXIT` видна по открывающей строке. `trap имя EXIT` разбирается через
функцию `имя` из того же файла: исполняется её определение вместе с ловушкой.

Использование: cleanup_trap_statements.py <корень> <каталог-вывода> <файл>…
Вывод: <каталог>/index.tsv — строки `N<TAB>файл<TAB>строка<TAB>вид<TAB>форма<TAB>подробность`
и <каталог>/N.sh — текст оператора (для функции — определение и ловушка).
Вид: cleanup (судится: переменные в подробности через запятую) · other (не уборка:
без EXIT, сброс, без rm) · unknown (форма не распознана: причина в подробности —
находка, а не молчание).
"""
import os
import re
import shlex
import subprocess
import sys

LIMIT = 80
HEREDOC = re.compile(r"<<(?!<)-?\s*([\"']?)([A-Za-z_][A-Za-z_0-9]*)\1")
RM_VARS = re.compile(r'rm\s+-rf\s+(?:--\s+)?((?:"\$\{?[A-Za-z_][A-Za-z_0-9]*\}?"\s*)+)')
VAR = re.compile(r'"\$\{?([A-Za-z_][A-Za-z_0-9]*)\}?"')
NAME = re.compile(r"[A-Za-z_][A-Za-z_0-9-]*")


def complete(text):
    r = subprocess.run(["bash", "-n"], input=text.encode(), capture_output=True)
    return r.returncode == 0


def statement(lines, i):
    for j in range(i, min(len(lines), i + LIMIT)):
        text = "\n".join(lines[i : j + 1])
        if complete(text):
            return text, j
    return None, i


def heredoc_lines(lines):
    inside, skip, delim = set(), False, None
    for i, line in enumerate(lines):
        if skip:
            inside.add(i)
            if line.strip() == delim:
                skip = False
            continue
        if line.lstrip().startswith("#"):
            continue
        m = HEREDOC.search(line)
        if m:
            skip, delim = True, m.group(2)
    return inside


def tokens(text):
    lex = shlex.shlex(text, posix=True)
    lex.whitespace_split = True
    lex.commenters = "#"
    out = list(lex)
    cut = []
    for t in out:
        if t in ("&&", "||", ";", "|"):
            break
        cut.append(t.rstrip(";"))
        if t.endswith(";"):
            break
    return cut


def function_def(lines, name):
    pat = re.compile(r"^\s*(function\s+%s\b|%s\s*\(\s*\))" % (re.escape(name), re.escape(name)))
    for i, line in enumerate(lines):
        if pat.match(line):
            text, _ = statement(lines, i)
            if text is not None:
                return text
    return None


def judge(lines, i, text):
    """Возвращает (вид, форма, подробность, текст оператора)."""
    try:
        toks = tokens(text)
    except ValueError as e:
        return "unknown", "-", "оператор не разобран: %s" % e, text
    if not toks or toks[0] != "trap":
        return "unknown", "-", "оператор не начинается с trap", text
    rest = toks[1:]
    if not rest:
        return "other", "-", "trap без аргументов", text
    if rest[0].startswith("-"):
        return "other", "-", "сброс или перечень ловушек", text
    body, sigs = rest[0], rest[1:]
    if not sigs:
        return "unknown", "-", "нет списка сигналов", text
    if not any(s in ("EXIT", "0") for s in sigs):
        return "other", "-", "ловушка не на EXIT", text
    form = "multi" if "\n" in text else "single"
    run_text, search = text, body
    if NAME.fullmatch(body.strip()):
        form = "func"
        fn = function_def(lines, body.strip())
        if fn is None:
            return "unknown", form, "функция уборки не найдена в файле: %s" % body.strip(), text
        run_text, search = fn + "\n" + text, fn
    if not re.search(r"\brm\b", search):
        return "other", form, "EXIT-ловушка без rm", text
    names = []
    for m in RM_VARS.finditer(search):
        for v in VAR.findall(m.group(1)):
            if v not in names:
                names.append(v)
    if not names:
        return "unknown", form, 'не в форме: нет rm -rf "$ПЕРЕМЕННАЯ" (переменная в двойных кавычках)', text
    return "cleanup", form, ",".join(names), run_text


def main(argv):
    root, out, files = argv[1], argv[2], argv[3:]
    os.makedirs(out, exist_ok=True)
    rows = []
    for f in files:
        with open(os.path.join(root, f), encoding="utf-8", errors="replace") as fh:
            lines = fh.read().split("\n")
        skip = heredoc_lines(lines)
        for i, line in enumerate(lines):
            if i in skip or not re.match(r"\s*trap\b", line):
                continue
            text, _ = statement(lines, i)
            if text is None:
                rows.append((f, i + 1, "unknown", "-", "оператор не закончился за %d строк" % LIMIT, line))
                continue
            kind, form, detail, run_text = judge(lines, i, text)
            rows.append((f, i + 1, kind, form, detail, run_text))
    with open(os.path.join(out, "index.tsv"), "w", encoding="utf-8") as idx:
        for n, (f, ln, kind, form, detail, run_text) in enumerate(rows, 1):
            with open(os.path.join(out, "%d.sh" % n), "w", encoding="utf-8") as fh:
                fh.write(run_text + "\n")
            idx.write("%d\t%s\t%d\t%s\t%s\t%s\n" % (n, f, ln, kind, form, detail.replace("\t", " ")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
