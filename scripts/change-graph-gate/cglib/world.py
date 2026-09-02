"""Мир кейса: чтение, перечисление фактов и УЧЁТ ПРОЧИТАННОГО.

Учёт прочитанного здесь не диагностика, а механизм запрета
«принято-и-проигнорировано» (`api-conventions.md`): факт, который мир объявил,
а ни одно применимое правило не прочитало, делает вердикт заявлением шире
осмотренного. Поэтому непрочитанный факт внутри предмета семейства — не
предупреждение, а собственный отказ испытуемого.

Граница названа прямо: координата правила записывается точками, поэтому ключ,
СОДЕРЖАЩИЙ точку, правилом не адресуется — только целиком вместе с контейнером
(`read_all`). Такой запрос отвечает громким собственным отказом, а не тихой
пустотой; ключей с точкой в мирах этого дерева нет, и оговорка стоит здесь,
чтобы отсутствие не приняли за невозможность.

Учёт ведётся ПО ИСПОЛНЕНИЮ, а не по списку рядом с правилом: правило,
объявившее чтение и не выполнившее его, перепись не обманет. Обратное тоже
верно и тоже проверяется: правило, прочитавшее вне объявленного предмета
семейства, — находка, а не расширение.
"""

import re

from . import outcome

# Ключ, содержащий точку или скобку, записывается в кавычках, иначе путь
# распался бы не по тем шагам. Ключи миров этого дерева точек не содержат,
# но правило записано здесь, а не в допущении.
_NEEDS_QUOTING = re.compile(r"[.\[\]']")

EMPTY_MAPPING = "<пустое отображение>"
EMPTY_SEQUENCE = "<пустая последовательность>"

MISSING = object()


class WorldError(Exception):
    """Мир не читается либо не является отображением."""


def _encode(key):
    text = str(key)
    if _NEEDS_QUOTING.search(text):
        return "['%s']" % text
    return text


def _join(prefix, key):
    segment = _encode(key)
    if not prefix:
        return segment
    return "%s.%s" % (prefix, segment)


def _leaves(value, prefix, sink):
    """Разворачивает структуру в плоский перечень фактов.

    ПУСТОЙ контейнер сам является фактом: `holder_subjects: {}` утверждает о
    предмете ровно столько же, сколько непустой, и не может остаться
    неучтённым только оттого, что внутри ничего нет.
    """
    if isinstance(value, dict):
        if not value:
            sink[prefix] = EMPTY_MAPPING
            return
        for key in value:
            _leaves(value[key], _join(prefix, key), sink)
    elif isinstance(value, (list, tuple)):
        if not value:
            sink[prefix] = EMPTY_SEQUENCE
            return
        for index, item in enumerate(value):
            _leaves(item, "%s[%d]" % (prefix, index), sink)
    else:
        sink[prefix] = value


def load(path):
    """Читает мир кейса. Любая неудача — собственный отказ, а не вердикт."""
    try:
        import yaml
    except ImportError as error:  # pragma: no cover — среда без разборщика YAML
        raise outcome.SelfFailure(
            outcome.SELF_WORLD_UNREADABLE, "разборщик YAML недоступен: %s" % error
        )
    try:
        with open(path, encoding="utf-8") as handle:
            raw = handle.read()
    except OSError as error:
        raise outcome.SelfFailure(
            outcome.SELF_WORLD_UNREADABLE, "мир не читается: %s" % error
        )
    try:
        data = yaml.safe_load(raw)
    except yaml.YAMLError as error:
        raise outcome.SelfFailure(
            outcome.SELF_WORLD_MALFORMED, "мир не разбирается как YAML: %s" % error
        )
    if not isinstance(data, dict):
        raise outcome.SelfFailure(
            outcome.SELF_WORLD_MALFORMED,
            "мир обязан быть отображением, получено %s" % type(data).__name__,
        )
    return World(data, path)


class World:
    """Отображение фактов кейса с учётом того, что из них было прочитано."""

    def __init__(self, data, path="<в памяти>"):
        if not isinstance(data, dict):
            raise WorldError("мир обязан быть отображением")
        self._data = data
        self._path = path
        self._facts = {}
        _leaves(data, "", self._facts)
        self._read_prefixes = set()

    @property
    def path(self):
        return self._path

    def facts(self):
        """Плоский перечень фактов мира: путь -> листовое значение."""
        return dict(self._facts)

    def top_keys(self):
        return list(self._data)

    def has(self, path):
        """Присутствует ли координата. Присутствие НЕ считается чтением.

        Различие намеренное: применимость правила решается наличием координат,
        а прочитанным факт становится только тогда, когда правило взяло его
        значение. Иначе неприменимое правило «покрывало» бы факты, которых
        никто не судил.
        """
        return self._resolve(path) is not MISSING

    def read(self, path):
        """Берёт значение координаты и отмечает её прочитанной."""
        value = self._resolve(path)
        self._read_prefixes.add(path)
        if value is MISSING:
            raise outcome.SelfFailure(
                outcome.SELF_WORLD_MALFORMED,
                "мир не содержит координаты %s" % path,
            )
        return value

    def read_all(self, path):
        """Берёт контейнер целиком и отмечает прочитанным всё его поддерево.

        Зовётся правилом, которое ПОТРЕБЛЯЕТ контейнер целиком — сравнивает его
        с эталоном либо обходит все записи. Правило, которому нужна одна запись,
        обязано звать `read` по её координате, иначе перепись покроет то, чего
        никто не смотрел.
        """
        return self.read(path)

    def _resolve(self, path):
        node = self._data
        for step in path.split("."):
            if isinstance(node, dict) and step in node:
                node = node[step]
            else:
                return MISSING
        return node

    def read_prefixes(self):
        return set(self._read_prefixes)

    def was_read(self, fact_path):
        for prefix in self._read_prefixes:
            if fact_path == prefix or fact_path.startswith(prefix + "."):
                return True
            if fact_path.startswith(prefix + "["):
                return True
        return False
