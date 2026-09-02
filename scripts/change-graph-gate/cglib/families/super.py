"""cg.super — терминальное боковое состояние SUPERSEDED.

Приёмка §«Landing и terminal states»: WITHDRAWN и SUPERSEDED — терминальные
боковые состояния. Авторизованное событие связывает ДЕЙСТВУЮЩЕЕ старое
изменение с ОТЛИЧНЫМ преемником взаимными ссылками и НОВЫМ evidence; старое
закрывается, обе истории сохраняются.

Отсюда четыре независимых предмета, каждый со своей диагностикой:

    successor_coordinate   старое изменение называет преемника
    backlink               преемник называет старое изменение в ответ
    цикл                   преемник не есть предок и не есть само старое
    evidence               преемник несёт СВОЁ свидетельство, а не чужое

**Событие читается, а не подразумевается.** Все четыре правила спрашивают
`event` целиком и состояние старого изменения: предмет каждого — не «ссылка
отсутствует вообще», а «запрошен переход SUPERSEDED, и при нём ссылки нет».
Читать событие через применимость было бы нельзя — наличие координаты чтением
не считается, и факт остался бы неучтённым: вердикт стал бы заявлением шире
осмотренного.

**Отсутствующая координата читается ХОЗЯИНОМ своего предмета, а не по
`requires`.** Правило, объявившее `successor_coordinate` обязательной для своей
применимости, замолчало бы ровно на том мире, ради которого написано, — и
вместе с ним замолчали бы соседи, оставив факты непрочитанными. Поэтому
применимость правила решает присутствие КОНТЕЙНЕРОВ, а отсутствие конкретной
координаты — это и есть находка, вычисляемая предикатом.

**Цикл судится по предкам, а не по имени.** Совпадение преемника с предком
устанавливается членством в объявленной родословной; вывод отношения из формы
идентификатора (`SDD-0` «раньше» `SDD-2`) запрещён тем же доводом, что и
деривация региона из имени зоны в `data-integrity.md`: строковый вывод молча
возвращает пустоту на первом же имени, устроенном иначе.
"""

from .. import outcome
from ..rules import Rule

FAMILY = "super"

EVENT = "event"
OLD_CHANGE = "old_change"
SUCCESSOR = "successor"
OLD_EVIDENCE = "old_evidence_coordinate"

OLD_ID = "old_change.id"
OLD_STATE = "old_change.state"
OLD_SUCCESSOR_COORDINATE = "old_change.successor_coordinate"
OLD_ANCESTORS = "old_change.ancestors"
SUCCESSOR_ID = "successor.id"
SUCCESSOR_BACKLINK = "successor.backlink"
SUCCESSOR_EVIDENCE = "successor.evidence_coordinate"

SUPERSEDED_VERDICT = "SUPERSEDED"
ACTIVE_STATE = "active"

SUBJECT = (EVENT, OLD_CHANGE, SUCCESSOR, OLD_EVIDENCE)
CONTAINERS = (EVENT, OLD_CHANGE, SUCCESSOR)


def _supersede_requested(world):
    """Запрошен ли переход, о котором судит семейство.

    Читает событие ЦЕЛИКОМ (актор и вердикт — обе координаты характеризуют
    авторизованное событие) и состояние старого изменения: переход осмыслен
    только для действующего изменения.
    """
    event = world.read_all(EVENT)
    state = world.read(OLD_STATE)
    return event.get("verdict") == SUPERSEDED_VERDICT and state == ACTIVE_STATE


def _ancestry(world):
    """Объявленная родословная старого изменения — как множество."""
    declared = world.read(OLD_ANCESTORS)
    if isinstance(declared, (list, tuple)):
        return {str(item) for item in declared}
    return {str(declared)}


def _successor_missing(world):
    """Старое изменение не называет преемника."""
    if not _supersede_requested(world):
        return False
    if not world.has(OLD_SUCCESSOR_COORDINATE):
        return True
    return not str(world.read(OLD_SUCCESSOR_COORDINATE)).strip()


def _backlink_missing(world):
    """Преемник не называет старое изменение в ответ.

    Взаимность — часть предмета: ссылка, ведущая не туда, связью не является,
    поэтому сравнивается со ЗНАЧЕНИЕМ идентификатора старого изменения, а не
    проверяется на непустоту.
    """
    if not _supersede_requested(world):
        return False
    old_id = str(world.read(OLD_ID))
    if not world.has(SUCCESSOR_BACKLINK):
        return True
    return str(world.read(SUCCESSOR_BACKLINK)) != old_id


def _supersede_cycle(world):
    """Преемник есть предок либо само старое изменение.

    Родословная читается ВСЕГДА, в том числе на мире без преемника: иначе факт
    остался бы непрочитанным ровно там, где предметом является другая находка.
    """
    ancestry = _ancestry(world)
    old_id = str(world.read(OLD_ID))
    successor_id = str(world.read(SUCCESSOR_ID))
    if not _supersede_requested(world):
        return False
    if successor_id == old_id:
        return True
    if not world.has(OLD_SUCCESSOR_COORDINATE):
        return False
    coordinate = str(world.read(OLD_SUCCESSOR_COORDINATE))
    return coordinate in ancestry or coordinate == old_id


def _evidence_reused(world):
    """Преемник предъявил свидетельство старого изменения.

    §7 связывает evidence с subject: свидетельство, привязанное к прежнему
    предмету, о преемнике не утверждает ничего, и переиспользование его
    означает, что преемник не доказан вовсе.
    """
    old_evidence = str(world.read(OLD_EVIDENCE))
    successor_evidence = str(world.read(SUCCESSOR_EVIDENCE))
    if not _supersede_requested(world):
        return False
    return successor_evidence == old_evidence


RULES = [
    Rule(
        rule_id="super.successor-missing",
        diagnostic="CG_SUPERSEDE_SUCCESSOR_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=SUBJECT,
        requires=CONTAINERS + (OLD_STATE,),
        predicate=_successor_missing,
        why="SUPERSEDED связывает старое изменение с преемником; без successor "
            "coordinate связи нет, и старое закрывать не на что",
    ),
    Rule(
        rule_id="super.backlink-missing",
        diagnostic="CG_SUPERSEDE_BACKLINK_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=SUBJECT,
        requires=CONTAINERS + (OLD_STATE, OLD_ID),
        predicate=_backlink_missing,
        why="ссылки взаимны: без backlink история преемника не называет того, "
            "кого он заместил, и обе истории перестают сходиться",
    ),
    Rule(
        rule_id="super.cycle",
        diagnostic="CG_SUPERSEDE_CYCLE",
        category=outcome.CATEGORY_RED,
        subject_keys=SUBJECT,
        requires=CONTAINERS + (OLD_STATE, OLD_ID, OLD_ANCESTORS, SUCCESSOR_ID),
        predicate=_supersede_cycle,
        why="преемник обязан быть ОТЛИЧНЫМ: замещение предком либо самим собой "
            "образует цикл, и терминальное состояние перестаёт быть терминальным",
    ),
    Rule(
        rule_id="super.evidence-reused",
        diagnostic="CG_SUPERSEDE_EVIDENCE_REUSED",
        category=outcome.CATEGORY_RED,
        subject_keys=SUBJECT,
        requires=CONTAINERS + (OLD_STATE, SUCCESSOR_EVIDENCE, OLD_EVIDENCE),
        predicate=_evidence_reused,
        why="§7 evidence привязан к subject; свидетельство прежнего предмета о "
            "преемнике не утверждает ничего",
    ),
]
