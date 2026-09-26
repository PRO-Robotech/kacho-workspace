#!/usr/bin/env python3
"""check-02 — ПРЕДПОСЫЛКА ПРИБОРА, без которой число `check-01` беспредметно.

Храповик судит по трём числам, и каждое из них есть функция предпосылок, ни одна
из которых не самоочевидна. Факт о дереве меняется — запрет становится ложью
МОЛЧА, и потолок при этом зеленеет. Проверяются четыре предпосылки, каждая
исходом, а не объявлением.

  1. ЛЕКСЕР ЧИТАЕТ КОММЕНТАРИЙ, А НЕ ТЕКСТ. Синтетика в `t.TempDir`-манере:
     одна и та же английская фраза стоит сперва строковым литералом, потом
     комментарием. Первая обязана быть невидима (это И6 by construction),
     вторая — найдена. Проверка на ЖИВОЙ записи дерева здесь негодна: она
     покраснела бы в день, когда дерево вычистят.

  2. ПРИЗНАК ПОРОЖДЁННОГО СХОДИТСЯ СО ВСТРЕЧНОЙ КОМАНДОЙ. Прибор снимает файл
     по шапке `// Code generated … DO NOT EDIT.`; встречный счёт — `git grep`
     по ТОЙ ЖЕ ревизии, что читает прибор (у продукта — ствол, у воркспейса —
     рабочая копия). Разошлись — значит прибор снимает не тот класс, что наши
     собственные гейты, читающие ту же строку дословно. Встречная команда по
     рабочей копии клона сверяла бы прибор с другим деревом.

  3. ИСКЛЮЧЕНИЕ ВВЕЗЁННОГО ВЫВОДИТСЯ ИЗ ДЕРЕВА. Признак не выписан координатой,
     поэтому истекает сам: сегодня он снимает ноль файлов `.go`, и это не
     находка, а отсутствие предмета. Находкой было бы обратное — ВЫПИСАННАЯ
     координата, которой в дереве нет. Здесь проверяется, что перечень
     по-прежнему выводится обходом, а не константой в исходнике.

  4. ОБХОД НЕПУСТ И НАЗЫВАЕТ ВСЕ ЧЕТЫРЕ ДЕРЕВА. Первая редакция критерия
     печатала число, полученное четырьмя деревьями, предъявляя цикл по трём:
     1632/51893 против объявленных 1633/51894. Оснастка воркспейса — наш код;
     обход, её не называющий, оставляет её вне переписи навсегда.

Исходы: 0 — предпосылки держатся; 1 — находка; 2 — считать не по чему.
"""
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "docs-gate"))
import _core  # noqa: E402
import _lib  # noqa: E402

NAME = "check-02-instrument-premise-holds"

SYNTHETIC = '''package x

const banner = "// static REST-path routing table for the middleware"

// static REST-path routing table for the middleware
func f() {}
'''


def premise_lexer():
    """Литерал невидим, комментарий найден. Один факт разницы — узел."""
    comments = _core.scan_go(SYNTHETIC)
    bodies = [b for _, b in comments]
    seen_literal = any("const banner" in b for b in bodies)
    found = [ln for ln, b in comments if _core.line_is_finding(b, True)]
    if seen_literal:
        return "лексер выдал текст СТРОКОВОГО ЛИТЕРАЛА за комментарий — И6 перестал " \
               "исполняться by construction"
    if len(comments) != 1:
        return "лексер вернул узлов комментария %d вместо 1 — разбор разошёлся с Go" \
               % len(comments)
    if not found:
        return "лексер НЕ нашёл английскую прозу в комментарии — прибор ослеп на " \
               "собственном предмете, и «находок 0» стало бы «ноль прочитанного»"
    return None


def premise_generated(root):
    out = []
    for name in _core.PRODUCTS + (_core.WORKSPACE,):
        repo = _core.clone(root, name)
        if repo is None:
            return None, "клона %s нет" % name
        rev, why = _core.tree_rev(repo, name)
        if why:
            return None, "%s: %s" % (name, why)
        grep = subprocess.run(
            ["git", "-C", repo, "grep", "-lE", r"^// Code generated .* DO NOT EDIT\.$"]
            + ([rev] if rev else []) + ["--", "*.go"], capture_output=True, text=True)
        counter = len([x for x in grep.stdout.split("\n") if x.strip()])
        m = _core.measure_tree(repo, name, rev)
        if "void" in m:
            return None, m["void"]
        out.append((name, m["generated"], counter, m))
    return out, None


def main():
    root = _lib.workspace_root()

    bad = premise_lexer()
    if bad:
        _lib.fail(NAME, "предпосылка 1 (лексер): " + bad)
        return 1

    trees, void = premise_generated(root)
    if void:
        _lib.void(NAME, "%s — предпосылки проверять не на чем" % void)
        return 2

    walked = sum(m["walked"] for _, _, _, m in trees)
    _lib.census("%s: деревьев %d, осмотрено `.go` %d; порождённых по шапке/по встречной "
                "команде %s; ввезённых снято %d"
                % (NAME, len(trees), walked,
                   ", ".join("%s %d/%d" % (n, g, c) for n, g, c, _ in trees),
                   sum(m["vendored"] for _, _, _, m in trees)))

    rc = 0
    if walked == 0:
        _lib.void(NAME, "обход ПУСТ — предпосылки проверены на пустом дереве")
        return 2
    for name, got, counter, _m in trees:
        if got != counter:
            _lib.fail(NAME, "предпосылка 2 (порождённое, %s): прибор снял %d, встречная "
                            "команда `git grep -lE '^// Code generated .* DO NOT EDIT\\.$'`"
                            " даёт %d — прибор снимает не тот класс, что читают наши "
                            "собственные гейты" % (name, got, counter))
            rc = 1

    src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "_core.py"),
               encoding="utf-8").read()
    body = src.split("def vendored_prefixes", 1)[-1].split("\ndef ", 1)[0]
    if re.search(r'"[a-z]+/[a-z]+/[a-z]+', body):
        _lib.fail(NAME, "предпосылка 3 (ввезённое): признак содержит ВЫПИСАННУЮ "
                        "координату поддерева. Выписанная координата переживает свой "
                        "предмет — ровно это нашло опровержение у "
                        "`corelib/internal/oauth2/PROVENANCE.md`; признак обязан "
                        "выводиться обходом")
        rc = 1

    names = [n for n, _, _, _ in trees]
    if set(names) != set(_core.PRODUCTS + (_core.WORKSPACE,)):
        _lib.fail(NAME, "предпосылка 4 (обход): названо %s, ожидалось четыре дерева"
                  % ", ".join(names))
        rc = 1

    if rc == 0:
        _lib.passed(NAME, "четыре предпосылки держатся: литерал невидим и комментарий "
                          "найден; счёт порождённого сошёлся со встречной командой; "
                          "признак ввезённого выводится обходом; названы все четыре дерева")
    return rc


if __name__ == "__main__":
    sys.exit(main())
