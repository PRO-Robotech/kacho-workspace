"""Вычисление one-fact delta между fixture и её positive twin.

Приёмка §12 и DoD §15 требуют, чтобы negative/NOT_EXECUTED fixture отличалась
от существующего positive twin РОВНО ОДНИМ НАЗВАННЫМ фактом, а fixture,
меняющая больше одного факта, была invalid и НЕ давала holder verdict.

Здесь это МАШИННОЕ требование, а не обещание в комментарии: driver сам
вычисляет структурную дельту между twin.world и case.world и сверяет её с
дельтой, которую fixture ОБЪЯВЛЯЕТ. Расходятся — harness-исход, holder verdict
не производится.

Без такой сверки «ровно один факт» держалось бы вниманием автора fixture, а
проверить это было бы нечем.
"""

import re

OP_CHANGE = "change"
OP_ADD = "add"
OP_REMOVE = "remove"

VALID_OPS = (OP_CHANGE, OP_ADD, OP_REMOVE)

_ABSENT = object()


NODE_MARKER = "#type"

# Ключи этого дерева — пути и имена файлов, поэтому точка в ключе обычна
# (`AGENTS.md`, `ci.yaml`). Разделять путь по каждой точке нельзя: `AGENTS.md`
# распалось бы на два шага. Поэтому сегмент, содержащий точку или скобку,
# записывается в кавычках: `tracked_outputs['AGENTS.md']`.
#
# Кодировщик и разборщик живут ЗДЕСЬ в единственном экземпляре, и построитель
# fixtures импортирует их отсюда же. Две реализации одного синтаксиса разошлись
# бы молча — ровно там, где расхождение не видно: на ключе с точкой.
_NEEDS_QUOTING = re.compile(r"[.\[\]']")
_PATH_STEP = re.compile(r"\['((?:[^'])*)'\]|\[(\d+)\]|([^.\[\]]+)")


def encode_segment(key):
    """Кодирует ключ словаря как шаг пути."""
    if _NEEDS_QUOTING.search(str(key)):
        return "['%s']" % key
    return str(key)


def join_path(prefix, key):
    """Присоединяет шаг-ключ к пути."""
    segment = encode_segment(key)
    if not prefix:
        return segment
    if segment.startswith("["):
        return prefix + segment
    return "%s.%s" % (prefix, segment)


def parse_path(path):
    """Разбирает путь в последовательность шагов: str для ключа, int для индекса."""
    steps = []
    position = 0
    while position < len(path):
        if path[position] == ".":
            position += 1
            continue
        match = _PATH_STEP.match(path, position)
        if not match:
            raise ValueError("неразбираемый путь: %r" % path)
        if match.group(1) is not None:
            steps.append(match.group(1))
        elif match.group(2) is not None:
            steps.append(int(match.group(2)))
        else:
            steps.append(match.group(3))
        position = match.end()
    if not steps:
        raise ValueError("пустой путь")
    return steps


def flatten(value, prefix=""):
    """Разворачивает вложенную структуру в плоскую карту путь -> листовое значение.

    Список адресуется индексом (`items[0]`), словарь — ключом (`a.b`).

    У КАЖДОГО контейнера выпускается структурный маркер `<путь>.#type`, и это
    не украшение. Без него снятие последнего ключа словаря читалось бы как ДВА
    факта: исчез ключ и появился пустой словарь, — потому что пустой контейнер
    сам становился бы листом, а непустой нет. Такая асимметрия делала бы
    добросовестную one-fact fixture невалидной. С маркером «поле опустело» и
    «поле исчезло» по-прежнему различимы: у первого маркер остаётся, у второго
    пропадает.

    Ключи продукта символа `#` не содержат, поэтому маркер не может
    столкнуться с настоящим полем.
    """
    flat = {}
    if isinstance(value, dict):
        flat[join_path(prefix, NODE_MARKER)] = "dict"
        for key in value:
            flat.update(flatten(value[key], join_path(prefix, key)))
    elif isinstance(value, list):
        flat[join_path(prefix, NODE_MARKER)] = "list"
        for index, item in enumerate(value):
            flat.update(flatten(item, "%s[%d]" % (prefix, index)))
    else:
        flat[prefix] = value
    return flat


def compute(twin_world, case_world):
    """Возвращает список фактических отличий case от twin.

    Каждый элемент: {op, path, from, to}. Пустой список означает, что миры
    совпадают — для derived-кейса это тоже нарушение (ноль фактов не есть
    один факт).
    """
    twin_flat = flatten(twin_world)
    case_flat = flatten(case_world)
    differences = []
    for path in sorted(set(twin_flat) | set(case_flat)):
        before = twin_flat.get(path, _ABSENT)
        after = case_flat.get(path, _ABSENT)
        if before is _ABSENT:
            differences.append(
                {"op": OP_ADD, "path": path, "from": None, "to": after}
            )
        elif after is _ABSENT:
            differences.append(
                {"op": OP_REMOVE, "path": path, "from": before, "to": None}
            )
        elif before != after:
            differences.append(
                {"op": OP_CHANGE, "path": path, "from": before, "to": after}
            )
    return differences


def describe(differences, limit=6):
    """Человекочитаемая перепись отличий для текста находки."""
    if not differences:
        return "отличий нет (ноль фактов)"
    shown = differences[:limit]
    parts = [
        "%s %s (%r -> %r)" % (item["op"], item["path"], item["from"], item["to"])
        for item in shown
    ]
    if len(differences) > limit:
        parts.append("… ещё %d" % (len(differences) - limit))
    return "; ".join(parts)


def matches_declaration(actual, declared):
    """Сверяет ЕДИНСТВЕННОЕ фактическое отличие с объявленным в fixture.

    Сверяются операция и путь. Значения не сверяются намеренно: путь и
    операция однозначно называют ФАКТ, а его значения driver уже прочитал из
    самих миров — требовать их повторного дословного объявления значило бы
    завести второе место об одном предмете.
    """
    return actual["op"] == declared.get("op") and actual["path"] == declared.get("path")
