#!/usr/bin/env python3
"""gate_root — корень дерева, которое судит проверка набора. ЕДИНСТВЕННЫЙ способ его получить.

ЗАЧЕМ ОДИН СПОСОБ. Проверка, взявшая корень из РАБОЧЕГО КАТАЛОГА, судит то дерево,
из которого её позвали, а не то, в котором она лежит. Ошибка односторонняя и тихая:
из чужого каталога такая проверка выходит нулём над чужим деревом, то есть «не
смотрел» превращается в «чисто» (ws#757; класс чинили в шести местах за один день).
Пока каждый набор выводил корень своей строкой, свойство держалось тем, что эти
строки написаны правильно, — вниманием. Здесь оно написано один раз.

ПОРЯДОК, И ОН НЕСУЩИЙ:
  1. переопределение НАБОРА (`TOOLING_GATE_ROOT`, `RULES_GATE_ROOT`, …) — имя
     передаёт вызывающий: его ставят инъекции набора, и оно обязано быть сильнее
     общего, иначе инъекция, запущенная под общим переопределением, судила бы не
     свою песочницу;
  2. общее переопределение `GATE_ROOT` — им проверку любого набора направляет на
     чужое дерево общая проба (`scripts/suites-gate/`), не зная имени переменной
     набора;
  3. РАСПОЛОЖЕНИЕ файла: `<корень>/scripts/<набор>/<файл>` — корень на три уровня
     выше. Файл вне `scripts/<набор>/` — отказ: вывести корень не из чего, а
     угадывать его значило бы вернуть ровно то, от чего этот модуль заведён.

РАБОЧИЙ КАТАЛОГ НЕ УЧАСТВУЕТ НИ НА ОДНОМ ШАГЕ. Держит это не этот текст, а
`scripts/suites-gate/check-01-check-root-is-not-the-working-directory.py`: он
направляет каждую проверку каждого набора на пустое дерево и сравнивает её исход
из двух рабочих каталогов.

Вызов из python: `from gate_root import gate_root; gate_root("DOCS_GATE_ROOT", __file__)`.
Вызов из bash:   `python3 <этот файл> TOOLING_GATE_ROOT "${BASH_SOURCE[0]}"` — печатает
корень; корень не выводится — строка `[VOID]` и код выхода 2. Реализация одна на оба
языка: вторая копия правила порядка разошлась бы с первой молча.
"""
import os
import sys

COMMON = "GATE_ROOT"


class RootUnresolved(Exception):
    """Корень не выводится: файл лежит вне scripts/<набор>/."""


def gate_root(suite_var, file):
    for var in (suite_var, COMMON):
        value = os.environ.get(var) if var else None
        if value:
            # Существование НЕ проверяется здесь: переопределение на несуществующий
            # каталог — предмет проверки («судить нечего», VOID), а не отказ модуля.
            return os.path.abspath(value)
    here = os.path.dirname(os.path.abspath(file))
    scripts = os.path.dirname(here)
    if os.path.basename(scripts) != "scripts":
        raise RootUnresolved(
            "%s лежит не в scripts/<набор>/ — корень из расположения не выводится"
            % os.path.abspath(file))
    return os.path.dirname(scripts)


def main(argv):
    if len(argv) != 3:
        print("использование: gate_root.py <ПЕРЕМЕННАЯ_НАБОРА|-> <файл проверки>",
              file=sys.stderr)
        return 2
    var = None if argv[1] == "-" else argv[1]
    try:
        print(gate_root(var, argv[2]))
    except RootUnresolved as exc:
        print("[VOID] gate_root — %s" % exc, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
