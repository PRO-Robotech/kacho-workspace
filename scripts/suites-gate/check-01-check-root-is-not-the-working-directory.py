#!/usr/bin/env python3
"""check-01 — ни одна проверка ни одного набора не берёт корень из рабочего каталога.

ЧТО УТВЕРЖДАЕТ (ws#757). Исход каждой проверки каждого набора не зависит от того,
из какого каталога её позвали: корень она берёт из переопределения либо из своего
расположения (`scripts/lib/gate_root.py`), а рабочий каталог не участвует.

ЦЕНА, РАДИ КОТОРОЙ ПРОВЕРКА ЗАВЕДЕНА. Проверка, взявшая корень из рабочего каталога,
молча судит чужое дерево и выходит нулём: «не смотрел» превращается в «чисто».
Ошибка односторонняя и тихая, и ловил её до сих пор человек.

ПРОБА ПОВЕДЕНЧЕСКАЯ, А НЕ ТЕКСТОВАЯ. Искать в исходнике `rev-parse --show-toplevel`
или `getcwd` значит ловить форму, а форм много: относительный путь, `git ls-files`
без `-C`, `$PWD`, `Path(".")`. Спрашивается ИСХОД. Каждую проверку направляют на
ПУСТОЕ дерево общим переопределением `GATE_ROOT` (`_lib.world_env`) и зовут дважды:
  A — рабочий каталог = корень осматриваемого дерева;
  B — рабочий каталог = то же пустое дерево.
Проверка, берущая корень как положено, в обоих прогонах судит пустое дерево, и
исходы совпадают. Проверка, берущая корень из рабочего каталога, в A судит
настоящее дерево — и исход расходится. Находка называет файл проверки (координату) и
строку, откуда корень вероятнее всего взят, — строка названа ПОДСКАЗКОЙ, вердикт
выносится по исходу.

ЧЕГО НЕ УТВЕРЖДАЕТ — названо прямо. Проверка, берущая корень из рабочего каталога
И выходящая нулём на пустом дереве, в A и B даст одинаковый ноль. Её ловит сосед —
`check-02-empty-tree-is-not-a-clean-verdict.py`: ноль на пустом дереве — его находка.
Вдвоём они не оставляют такой проверке зелёного исхода.

ОБХОД ВЫВОДИТСЯ ИЗ ДЕРЕВА (`scripts/lib/suites.py`): набор, заведённый завтра,
попадает под проверку сам. Ноль наборов либо ноль проверок — VOID, а не «находок 0».

Коды: 0 — исход каждой проверки не зависит от рабочего каталога; 1 — находка;
2 — осматривать нечего.
"""
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _lib  # noqa: E402

NAME = "check-01-check-root-is-not-the-working-directory"
# Подсказка, а не вердикт: где в файле корень вероятнее всего взят из рабочего каталога.
HINT = re.compile(r"rev-parse\s+--show-toplevel|os\.getcwd\(|Path\.cwd\(|\$PWD\b|\$\(pwd\)")


def hint(ws, rel):
    try:
        with open(os.path.join(ws, rel), encoding="utf-8", errors="replace") as fh:
            for i, line in enumerate(fh, 1):
                code = line.split("#", 1)[0] if not rel.endswith(".py") else line
                if HINT.search(code) and "-C" not in code.split("rev-parse")[0][-40:]:
                    return "%s:%d `%s`" % (rel, i, line.strip()[:100])
    except OSError:
        pass
    return None


def main():
    ws = _lib.root(__file__)
    names, by_suite = _lib.suite_census(NAME, ws)
    total = sum(len(v) for v in by_suite.values())
    if not names:
        _lib.void(NAME, "наборов scripts/*/run-all.sh в %s нет — осматривать нечего" % ws)
        return 2
    if total == 0:
        _lib.void(NAME, "наборов %d, проверок check-* в них 0 — осматривать нечего" % len(names))
        return 2

    empty = _lib.empty_world()
    try:
        env = _lib.world_env(empty)
        findings = []
        for s in names:
            for rel in by_suite[s]:
                a = _lib.run_check(ws, rel, ws, env)
                b = _lib.run_check(ws, rel, empty, env)
                if a != b:
                    where = hint(ws, rel)
                    findings.append(
                        "%s — исход зависит от рабочего каталога: из корня дерева код %s, "
                        "из пустого каталога код %s при одном и том же GATE_ROOT; корень "
                        "взят не из расположения проверки%s"
                        % (rel, a, b, "; подсказка — " + where if where else ""))
    finally:
        shutil.rmtree(empty, ignore_errors=True)

    _lib.census(NAME, "наборов %d (%s); проверок %d; прогонов %d (по два на проверку — "
                "из корня и из пустого каталога); находок %d"
                % (len(names), ", ".join(names), total, 2 * total, len(findings)))
    if findings:
        for f in findings:
            _lib.finding(f)
        _lib.fail(NAME, "проверок, судящих дерево рабочего каталога: %d" % len(findings))
        return 1
    _lib.passed(NAME, "исход всех %d проверок в %d наборах не зависит от рабочего каталога"
                % (total, len(names)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
