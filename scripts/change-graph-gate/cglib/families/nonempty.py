"""cg.nonempty — пустой обход не есть чистота.

Приёмка §7, дословно: «Active package с 0 acceptance IDs, 0 required holders
или отсутствующим subject/input → RED, не vacuous GREEN».

Правила применимы ТОЛЬКО к active package, и это не оговорка, а предмет: у
неактивного package переписи нет вовсе, и отвечать на неё GREEN значило бы
объявить чистым то, чего не смотрели. Мир, объявивший другое состояние, до
вердикта не доходит — ядро отвечает собственным отказом «мир не судим», потому
что «правил не нашлось» и «нарушений не найдено» — разные вещи.
"""

from .. import outcome
from ..rules import Rule

FAMILY = "nonempty"

ACTIVE_PACKAGE_STATE = "active"


def _package_is_active(world):
    return world.read("package_state") == ACTIVE_PACKAGE_STATE


def _acceptance_ids_empty(world):
    return not world.read_all("acceptance_ids")


def _required_holders_empty(world):
    return not world.read_all("required_holders")


def _holder_without_subject(world):
    """Предмет правила — ОТНОШЕНИЕ двух наборов, поэтому читаются оба.

    Читать только required holders было бы неверно вдвойне: перепись объявила бы
    непрочитанным набор subjects, а сам ответ «все subjects на месте» получался
    бы, не взглянув на них.
    """
    holders = world.read_all("required_holders")
    subjects = world.read_all("holder_subjects")
    missing = [name for name in holders if not subjects.get(name)]
    return bool(missing)


RULES = [
    Rule(
        rule_id="nonempty.acceptance-ids",
        diagnostic="CG_ACCEPTANCE_IDS_EMPTY",
        category=outcome.CATEGORY_RED,
        subject_keys=("package_state", "acceptance_ids"),
        requires=("package_state", "acceptance_ids"),
        applicability=_package_is_active,
        predicate=_acceptance_ids_empty,
        why="§7 active package с 0 acceptance IDs даёт RED, не vacuous GREEN",
    ),
    Rule(
        rule_id="nonempty.required-holders",
        diagnostic="CG_REQUIRED_HOLDERS_EMPTY",
        category=outcome.CATEGORY_RED,
        subject_keys=("package_state", "required_holders"),
        requires=("package_state", "required_holders"),
        applicability=_package_is_active,
        predicate=_required_holders_empty,
        why="§7 active package с 0 required holders даёт RED",
    ),
    Rule(
        rule_id="nonempty.holder-subject",
        diagnostic="CG_HOLDER_SUBJECT_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=("package_state", "required_holders", "holder_subjects"),
        requires=("package_state", "required_holders", "holder_subjects"),
        applicability=_package_is_active,
        predicate=_holder_without_subject,
        why="§7 отсутствующий subject/input у required holder даёт RED",
    ),
]
