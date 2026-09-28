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
без `-C`, `$PWD`, `Path(".")`. Спрашивается ИСХОД, и у получения корня ДВЕ ветки —
переопределение и расположение, — поэтому пар прогонов тоже две:

  ПЕРЕОПРЕДЕЛЕНИЕ. Проверку направляют на ПУСТОЕ дерево общим переопределением
  `GATE_ROOT` (`_lib.world_env`) и зовут дважды:
    A — рабочий каталог = корень осматриваемого дерева;
    B — рабочий каталог = то же пустое дерево.
  Проверка, читающая переопределение, в обоих прогонах судит пустое дерево, и
  исходы совпадают; проверка, берущая корень из рабочего каталога, в A судит
  настоящее дерево — и исход расходится.

  РАСПОЛОЖЕНИЕ. Переопределений нет вовсе (ни `GATE_ROOT`, ни `<НАБОР>_GATE_ROOT`),
  а копия проверки лежит в ДРУГОМ дереве — отдельном git-репозитории с копией её
  каталога набора (без `run-all.sh`: набором он там не считается) и `scripts/lib/`:
    C — рабочий каталог = корень осматриваемого дерева;
    D — рабочий каталог = пустое дерево.
  Проверка, выводящая корень из расположения, в обоих прогонах судит своё дерево-
  копию, и исходы совпадают. Форма «переопределение, иначе рабочий каталог»
  (`${GATE_ROOT:-$(git rev-parse --show-toplevel)}`) проходит пару A/B — там
  переопределение задано, и запасная ветка не исполняется ни разу, — а здесь
  исполняется именно она: в C судит настоящее дерево, в D пустое. Эта же пара
  ловит поломку ОБЩЕЙ ветки расположения (`scripts/lib/gate_root.py`), которой
  пользуется каждая проверка: без неё поломка видна только массовым отказом в
  полном прогоне, без координаты.

Находка называет файл проверки (координату), пару прогонов и строку, откуда корень
вероятнее всего взят, — строка названа ПОДСКАЗКОЙ, вердикт выносится по исходу.

ОБХОД ВЫВОДИТСЯ ИЗ ДЕРЕВА (`scripts/lib/suites.py`): набор, заведённый завтра,
попадает под проверку сам. Ноль наборов либо ноль проверок — VOID, а не «находок 0».

Коды: 0 — исход каждой проверки не зависит от рабочего каталога ни при
переопределении, ни без него; 1 — находка;
2 — осматривать нечего.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

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


def location_world(ws, suite):
    """Отдельный git-репозиторий с копией каталога набора (без `run-all.sh`) и
    `scripts/lib/`: здесь проверка, выводящая корень из расположения, судит себя."""
    d = tempfile.mkdtemp(prefix="location-world.")
    subprocess.run(["git", "-C", d, "init", "-q"], check=True, env=_lib.clean_env())
    shutil.copytree(os.path.join(ws, "scripts", suite), os.path.join(d, "scripts", suite),
                    ignore=shutil.ignore_patterns("run-all.sh", "__pycache__"))
    lib = os.path.join(ws, "scripts", "lib")
    if os.path.isdir(lib):
        shutil.copytree(lib, os.path.join(d, "scripts", "lib"),
                        ignore=shutil.ignore_patterns("__pycache__"))
    return d


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
    worlds = []
    try:
        env = _lib.world_env(empty)
        # Без переопределений вовсе: `world_env` снял `*GATE_ROOT` и указатели на
        # клоны продукта, общее переопределение снимается здесь.
        bare = {k: v for k, v in env.items() if k != "GATE_ROOT"}
        findings = []
        for s in names:
            there = location_world(ws, s)
            worlds.append(there)
            for rel in by_suite[s]:
                where = hint(ws, rel)
                tail = "; подсказка — " + where if where else ""
                a = _lib.run_check(ws, rel, ws, env)
                b = _lib.run_check(ws, rel, empty, env)
                if a != b:
                    findings.append(
                        "%s — исход зависит от рабочего каталога при переопределении: из корня "
                        "дерева код %s, из пустого каталога код %s при одном и том же "
                        "GATE_ROOT; корень взят не из переопределения%s" % (rel, a, b, tail))
                    continue
                c = _lib.run_check(there, rel, ws, bare)
                d = _lib.run_check(there, rel, empty, bare)
                if c != d:
                    findings.append(
                        "%s — без переопределения исход зависит от рабочего каталога: копия "
                        "проверки в другом дереве из корня дерева дала код %s, из пустого "
                        "каталога — код %s; корень при отсутствии переопределения взят не из "
                        "расположения проверки%s" % (rel, c, d, tail))
    finally:
        shutil.rmtree(empty, ignore_errors=True)
        for w in worlds:
            shutil.rmtree(w, ignore_errors=True)

    _lib.census(NAME, "наборов %d (%s); проверок %d; пар прогонов %d (по две на проверку — "
                "A/B при переопределении и C/D без него, копией в другом дереве; каждая пара — "
                "из корня и из пустого каталога); находок %d"
                % (len(names), ", ".join(names), total, 2 * total, len(findings)))
    if findings:
        for f in findings:
            _lib.finding(f)
        _lib.fail(NAME, "проверок, судящих дерево рабочего каталога: %d" % len(findings))
        return 1
    _lib.passed(NAME, "исход всех %d проверок в %d наборах не зависит от рабочего каталога — "
                "ни при переопределении корня, ни без него" % (total, len(names)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
