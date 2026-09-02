"""cg.truth — владение истиной.

Приёмка §2 объявляет таблицу «артефакт -> единственный предмет истины» и прямо
говорит, что semantic duplication, tracker-like tasks, open design decisions и
смысловые конфликты судит HUMAN semantic holder, а machine gate не заявляет,
что понимает смысл: он проверяет наличие, authority, subject binding и verdict
зарегистрированного человека.

Отсюда форма правил этого семейства. Испытуемый НЕ читает прозу и не решает,
дублирование ли перед ним: он читает ЗАФИКСИРОВАННЫЙ человеком факт (мир несёт
исход semantic review) и блокирует переход по нему. Последнее правило —
зеркало того же принципа с другой стороны: смысловое утверждение, у которого
остался только machine holder, отвергается, потому что автоматического
понимания смысла не существует.
"""

from .. import outcome
from ..rules import Rule

FAMILY = "truth"

# §2, дословный состав таблицы владения.
REGISTERED_OWNERS = {
    "issue": "why/priority/owner/live-status",
    "acceptance": "observable-behavior-and-case-ids",
    "design": "technical-decisions",
    "tasks": "approved-execution-route",
    "change_yaml": "coordinates-and-hashes",
    "roadmap": "normative-lifecycle-consumer",
}

HUMAN_SEMANTIC_HOLDER = "human-semantic"
VERIFIED_EXTERNAL_EVENT = "verified-external-event"

# Пустое значение обязано означать «пусто»: словарь отсутствия назван явно,
# чтобы «none» не пришлось угадывать по правдоподобию строки.
ABSENT_MARKERS = (None, "", "none", "—")


def _absent(value):
    return value in ABSENT_MARKERS


def _observable_requirement_duplicated(world):
    """§1: roadmap ссылается на acceptance и НЕ копирует observable scope."""
    duplicate = world.read("duplicated_observable_requirement")
    roadmap_copies = world.read("roadmap_copies_observable_scope")
    return (not _absent(duplicate)) or bool(roadmap_copies)


def _owners_conflict(world):
    """§2: у каждого предмета истины ровно один владелец.

    Читается ВСЯ таблица владения, а не одна запись: конфликт есть отношение
    между владельцами, и решить его по одной строке нельзя.
    """
    declared_conflict = world.read("second_owner_conflict")
    owners = world.read_all("owners")
    subjects = list(owners.values())
    shared_subject = len(set(subjects)) != len(subjects)
    return (not _absent(declared_conflict)) or shared_subject or owners != REGISTERED_OWNERS


def _tasks_became_tracker(world):
    """§2: tasks владеет approved execution route и не является tracker'ом."""
    return bool(world.read("tasks_contains_live_status"))


def _manifest_carries_prose(world):
    """§2: change.yaml владеет координатами и хэшами, а не требованиями."""
    return bool(world.read("change_yaml_contains_requirement_prose"))


def _human_semantic_holder_absent(world):
    """§2 и §7: смысловое утверждение требует человека с verified event.

    Обходится ВЕСЬ набор required holders: предмет правила — сам набор, и
    ответ «человека нет» получается перебором, а не заглядыванием под один ключ.
    """
    holders = world.read_all("required_holders")
    backed = [
        name
        for name, backing in holders.items()
        if name == HUMAN_SEMANTIC_HOLDER and backing == VERIFIED_EXTERNAL_EVENT
    ]
    return not backed


RULES = [
    Rule(
        rule_id="truth.duplication",
        diagnostic="CG_HUMAN_TRUTH_DUPLICATION",
        category=outcome.CATEGORY_RED,
        subject_keys=("duplicated_observable_requirement",
                      "roadmap_copies_observable_scope"),
        requires=("duplicated_observable_requirement",
                  "roadmap_copies_observable_scope"),
        predicate=_observable_requirement_duplicated,
        why="§1 roadmap не копирует observable scope; §2 semantic duplication "
            "судит human semantic holder",
    ),
    Rule(
        rule_id="truth.owner-conflict",
        diagnostic="CG_HUMAN_TRUTH_CONFLICT",
        category=outcome.CATEGORY_RED,
        subject_keys=("second_owner_conflict", "owners"),
        requires=("second_owner_conflict", "owners"),
        predicate=_owners_conflict,
        why="§2 у каждого артефакта единственный предмет истины; смысловые "
            "конфликты судит human semantic holder",
    ),
    Rule(
        rule_id="truth.tasks-tracker",
        diagnostic="CG_HUMAN_TASKS_TRACKER",
        category=outcome.CATEGORY_RED,
        subject_keys=("tasks_contains_live_status",),
        requires=("tasks_contains_live_status",),
        predicate=_tasks_became_tracker,
        why="§2 tasks — approved execution route, не tracker",
    ),
    Rule(
        rule_id="truth.manifest-prose",
        diagnostic="CG_HUMAN_MANIFEST_PROSE",
        category=outcome.CATEGORY_RED,
        subject_keys=("change_yaml_contains_requirement_prose",),
        requires=("change_yaml_contains_requirement_prose",),
        predicate=_manifest_carries_prose,
        why="§2 change.yaml владеет координатами и хэшами, а не требованиями",
    ),
    Rule(
        rule_id="truth.human-holder-required",
        diagnostic="CG_HUMAN_HOLDER_REQUIRED",
        category=outcome.CATEGORY_RED,
        subject_keys=("required_holders",),
        requires=("required_holders",),
        predicate=_human_semantic_holder_absent,
        why="§2 machine gate не объявляет, что понимает смысл; §7 human "
            "semantic holder — verified event + append-only artifact",
    ),
]
