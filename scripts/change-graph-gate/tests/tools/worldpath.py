"""Адресация листа мира fixture по пути и применение one-fact операции.

Путь записывается так же, как его печатает caselib.delta: ключи словаря через
точку, элементы списка индексом в квадратных скобках. Один и тот же синтаксис
у построителя и у проверяющего — намеренно: если бы их было два, объявленная
дельта и вычисленная расходились бы молча.
"""

import copy
import os
import sys

sys.path.insert(
    0, os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
)

from caselib.delta import parse_path as parse  # noqa: E402


def _descend(root, steps):
    node = root
    for step in steps:
        node = node[step]
    return node


def apply_change(world, path, value):
    """Меняет значение существующего листа."""
    result = copy.deepcopy(world)
    steps = parse(path)
    parent = _descend(result, steps[:-1])
    last = steps[-1]
    if isinstance(parent, list):
        if not isinstance(last, int) or last >= len(parent):
            raise KeyError("change: нет элемента %s" % path)
    elif last not in parent:
        raise KeyError("change: нет ключа %s" % path)
    if parent[last] == value:
        raise ValueError("change: значение %s не изменилось" % path)
    parent[last] = value
    return result


def apply_add(world, path, value):
    """Добавляет отсутствующий лист (ключ словаря либо элемент в конец списка)."""
    result = copy.deepcopy(world)
    steps = parse(path)
    parent = _descend(result, steps[:-1])
    last = steps[-1]
    if isinstance(parent, list):
        if not isinstance(last, int):
            raise KeyError("add: в список нужен индекс, дан %r" % last)
        if last != len(parent):
            raise KeyError(
                "add: элемент добавляется только в конец, ожидался индекс %d"
                % len(parent)
            )
        parent.append(value)
    else:
        if last in parent:
            raise KeyError("add: ключ %s уже существует" % path)
        parent[last] = value
    return result


def apply_remove(world, path):
    """Снимает существующий лист."""
    result = copy.deepcopy(world)
    steps = parse(path)
    parent = _descend(result, steps[:-1])
    last = steps[-1]
    if isinstance(parent, list):
        if not isinstance(last, int) or last >= len(parent):
            raise KeyError("remove: нет элемента %s" % path)
        parent.pop(last)
    else:
        if last not in parent:
            raise KeyError("remove: нет ключа %s" % path)
        del parent[last]
    return result


def apply_operation(world, op, path, value=None):
    if op == "change":
        return apply_change(world, path, value)
    if op == "add":
        return apply_add(world, path, value)
    if op == "remove":
        return apply_remove(world, path)
    raise ValueError("неизвестная операция %r" % op)
