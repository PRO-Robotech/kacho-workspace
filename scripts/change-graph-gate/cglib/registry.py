"""Реестр семейств правил — ВЫВОДИТСЯ из дерева, а не выписывается.

Рукописный перечень семейств был бы вторым местом об одном предмете и разошёлся
бы с деревом молча: в этом корпусе так уже случалось трижды с перечнями
репозиториев. Поэтому объявление признаков собирается обходом каталога
`families/`: положил модуль — признак появился, снял — исчез. Проверяется это
инъекцией, а не обещанием.

Побочное и намеренное следствие: параллельные полосы, каждая со своими
семействами, не правят один общий список и потому не сталкиваются на нём.

**Сломанный модуль семейства роняет ОБЪЯВЛЕНИЕ ЦЕЛИКОМ — это решение, а не
недосмотр, и чинить его «пропуском сломанного» нельзя.** Пропуск выглядит
мягче, но превращает поломку сборки в «признака нет», а драйвер отвечает на
отсутствие признака честным acceptance RED, который открывает RED_PROVEN.
Приёмка §6 запрещает ровно это: посторонний crash не подменяет
`CASE_CAPABILITY_MISSING`. Цена названа прямо: пока чужой модуль семейства не
импортируется, признаков не объявляет НИКТО, и все кейсы получают harness-исход
вместо вердикта — то есть поломка видна сразу и целиком, а не растворяется в
одной полосе.
"""

import importlib
import pkgutil
import re

from . import families as families_package
from . import outcome

CAPABILITY_PREFIX = "cg."

# Тот же разбор идентификатора кейса, что у harness'а: семейство ВЫВОДИТСЯ из
# ID, а не ведётся отдельной таблицей соответствий. Форма суффикса взята у
# harness'а дословно (`(?:-NA)?`) и намеренно НЕ обобщена: обобщение развело бы
# два разбора одного предмета, а один из них лежит в pre-RED diff и правке не
# подлежит.
#
# Полей ТРИ, и различать их обязательно:
#
# * **семейство** — чьи ПРАВИЛА судят кейс. У `SDD-1-POST-01` и
#   `SDD-1-POST-NA-01` оно одно: освобождение роли судит то же семейство, что и
#   её вердикт, отдельного модуля у него нет;
# * **серия** — чья ИНВЕРСИЯ РОЖДЕНИЯ считается. Здесь их ДВЕ: у серии с
#   суффиксом свой базовый кейс и свои производные. Считать их одной группой
#   значит принять две базы за пару «база + производный» — то есть не заметить
#   потерю производного (ложноотрицательный исход, задача #495);
# * **порядковый номер** — которая половина инверсии: базовая либо производная.
#
# Грамматика живёт ЗДЕСЬ в единственном экземпляре: второй её дом разошёлся бы
# с первым молча, а разошёлся бы он именно там, где расхождение не видно, —
# на входе, которого ни одна фикстура не производит.
_CASE_ID = re.compile(
    r"^SDD-1-(?P<family>[A-Z]+)(?P<suffix>-NA)?-(?P<ordinal>\d+)$"
)
_FAMILY_NAME = re.compile(r"^[a-z][a-z0-9]*$")


def _parse(case_id):
    """Разбор идентификатора кейса. Неразбираемый — собственный отказ."""
    match = _CASE_ID.match(str(case_id))
    if not match:
        raise outcome.SelfFailure(
            outcome.SELF_CASE_ID_UNPARSEABLE,
            "идентификатор кейса не разбирается: %r" % (case_id,),
        )
    return match


def family_of(case_id):
    """Семейство кейса — чьи правила его судят.

    Суффикс серии сюда НЕ входит намеренно: правила у обеих серий общие, и
    драйвер обязан найти модуль семейства по обеим. Кому принадлежит инверсия
    рождения — отвечает `series_of`, а не эта функция.
    """
    return _parse(case_id).group("family").lower()


def series_of(case_id):
    """Серия кейса — чья инверсия рождения им считается.

    Серия с суффиксом от серии без него отличается: у каждой свой базовый кейс
    и свои производные. Ключ строится из ОБОИХ полей, поэтому две серии одного
    семейства в одну группу не сходятся.
    """
    match = _parse(case_id)
    return (match.group("family") + (match.group("suffix") or "")).lower()


def ordinal_of(case_id):
    """Порядковый номер кейса внутри его серии."""
    return int(_parse(case_id).group("ordinal"))


def capability_token(family):
    return CAPABILITY_PREFIX + family


def load():
    """Собирает отображение семейство -> правила обходом каталога модулей."""
    collected = {}
    seen_rule_ids = set()
    for module_info in pkgutil.iter_modules(families_package.__path__):
        name = module_info.name
        if name.startswith("_"):
            continue
        try:
            module = importlib.import_module(
                "%s.%s" % (families_package.__name__, name)
            )
        except Exception as error:
            raise outcome.SelfFailure(
                outcome.SELF_REGISTRY_BROKEN,
                "модуль семейства %s не импортируется: %r" % (name, error),
            )
        family = getattr(module, "FAMILY", None)
        rules = getattr(module, "RULES", None)
        if not isinstance(family, str) or not _FAMILY_NAME.match(family):
            raise outcome.SelfFailure(
                outcome.SELF_REGISTRY_BROKEN,
                "модуль %s объявил негодное имя семейства: %r" % (name, family),
            )
        if not isinstance(rules, (list, tuple)) or not rules:
            raise outcome.SelfFailure(
                outcome.SELF_REGISTRY_BROKEN,
                "семейство %s не объявило ни одного правила" % family,
            )
        if family in collected:
            raise outcome.SelfFailure(
                outcome.SELF_REGISTRY_BROKEN,
                "семейство %s объявлено более чем одним модулем" % family,
            )
        for rule in rules:
            if rule.rule_id in seen_rule_ids:
                raise outcome.SelfFailure(
                    outcome.SELF_REGISTRY_BROKEN,
                    "идентификатор правила %s не уникален" % rule.rule_id,
                )
            seen_rule_ids.add(rule.rule_id)
        collected[family] = list(rules)
    if not collected:
        raise outcome.SelfFailure(
            outcome.SELF_REGISTRY_BROKEN,
            "в каталоге семейств не найдено ни одного модуля — объявлять нечего",
        )
    return collected


def capabilities():
    """Отсортированный перечень объявленных признаков."""
    return sorted(capability_token(family) for family in load())
