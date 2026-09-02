"""cg.conv — итоговая сходимость: кто её выдал, чем подтверждена и что собрала.

Приёмка §«Diff ownership, post-diff review и convergence» описывает ДВА разных
предмета, и у мира от этого две формы. Смешивать их нельзя: каждая отвечает на
свой вопрос, и правила одной к миру другой неприменимы by construction.

**Форма первая — само событие сходимости** (`convergence`, `change_hashes`,
`repos`, `policy_allowlist`, `api`). Сходимость выдаёт человек, поэтому её
подтверждение — верифицированное внешнее событие, а запись обязана называть
предмет так, чтобы его нельзя было подменить: точные хеши изменения, пару
base/source по КАЖДОМУ репозиторию и отпечаток содержимого.

**Форма вторая — агрегат специалистов** (`content_digest`, `applicable_roles`,
`post_diff_records`, `convergence_aggregator_specialists`). Здесь предмет иной:
сходимость обязана ссылаться на точный набор отдельных записей специалистов, и
проверяется РАВЕНСТВО трёх наборов, а не наличие хотя бы одного.

**Порядок объявлен и несущий — «не знаю» никогда не становится «нет».**

1. `conv.event-unavailable` (NOT_EXECUTED) — авторитет события недоступен. Пока
   он молчит, о существовании события и о личности актора не известно НИЧЕГО;
   ответить здесь красным значило бы выдать неполученный ответ за отрицательный;
2. `conv.event-missing` (RED) — авторитет ответил, события нет. Это уже знание;
3. `conv.owner-unauthorized` (RED) — событие есть, но актор не в списке роли.
   Стоит после отсутствия события: без события личность актора не подтверждена
   ничем, и судить её было бы судить непроверенное утверждение;
4. `conv.content-identity-missing` (RED) — полнота записи. Она не зависит от
   доступности авторитета: это факт о самой записи, читаемый без него, — поэтому
   правило доступностью НЕ гейтится и читает свои координаты всегда;
5. `conv.specialist-set-mismatch` (RED) — вторая форма мира, к первой
   неприменима.

**Каждое правило читает свои координаты ДО решения, а не после.** Предикат,
вышедший рано, оставил бы факты мира непрочитанными, и вердикт стал бы
заявлением шире осмотренного — ядро отвечает на это собственным отказом. Ровно
поэтому гейтящие правила сперва берут значения, и лишь затем решают.

**Требуемые репозитории ВЫВОДЯТСЯ из мира, а не выписываются.** Рукописный
перечень «workspace и product» был бы вторым местом об одном предмете и
разошёлся бы с деревом молча — в этом корпусе так уже случалось с перечнями
репозиториев трижды. Поэтому имя репозитория получается снятием суффикса
`_base_sha`/`_source_sha`, и от каждого увиденного репозитория требуются ОБЕ
половины пары: одна половина хуже отсутствия обеих, потому что выглядит
заполненной.

**Запись специалиста адресуется парой «роль · предмет».** Координата записи
несёт и роль, и отпечаток содержимого, поэтому запись, привязанная к другому
предмету, записью ЭТОГО изменения не является и в набор не входит. Так
отпечаток содержимого действительно потребляется, а не «читается для вида».
"""

from .. import outcome
from ..rules import Rule

FAMILY = "conv"

# --- форма первая: событие сходимости ---------------------------------------
CONVERGENCE = "convergence"
CHANGE_HASHES = "change_hashes"
REPOS = "repos"
POLICY_ALLOWLIST = "policy_allowlist"
API = "api"

REVIEWER_ROLE = "convergence.reviewer_role"
ACTOR = "convergence.actor"
EVENT_COORDINATE = "convergence.event_coordinate"
RECORD_CONTENT_DIGEST = "convergence.content_digest"
API_AVAILABILITY = "api.availability"

AVAILABLE = "available"
BASE_SUFFIX = "_base_sha"
SOURCE_SUFFIX = "_source_sha"

# --- форма вторая: агрегат записей специалистов ------------------------------
CONTENT_DIGEST = "content_digest"
APPLICABLE_ROLES = "applicable_roles"
POST_DIFF_RECORDS = "post_diff_records"
AGGREGATOR = "convergence_aggregator_specialists"

APPLICABLE = "applicable"
AGGREGATOR_SEPARATOR = ","
DIGEST_SEPARATOR = ":"

EVENT_SUBJECT = (CONVERGENCE, CHANGE_HASHES, REPOS, POLICY_ALLOWLIST, API)
EVENT_REQUIRES = (CONVERGENCE, CHANGE_HASHES, REPOS, POLICY_ALLOWLIST,
                  API_AVAILABILITY)

SET_SUBJECT = (CONTENT_DIGEST, APPLICABLE_ROLES, POST_DIFF_RECORDS, AGGREGATOR)
SET_REQUIRES = SET_SUBJECT


def _blank(value):
    """Отсутствующее либо пустое значение. Пробелы значением не считаются."""
    if value is None:
        return True
    return not str(value).strip()


def _authority_available(world):
    """Отвечает ли авторитет внешнего события."""
    return str(world.read(API_AVAILABILITY)).strip() == AVAILABLE


def _event_coordinate(world):
    """Координата внешнего события либо None, если её нет.

    Отсутствующая координата читается ХОЗЯИНОМ своего предмета: объявить её
    обязательной в `requires` значило бы замолчать ровно на том мире, ради
    которого правило написано.
    """
    if not world.has(EVENT_COORDINATE):
        return None
    return world.read(EVENT_COORDINATE)


def _allowed_actors(world, role):
    """Акторы, которым разрешена названная роль.

    Читается ОДНА запись списка — та, чью роль правило и потребляет. Список
    целиком не берётся: перепись покрыла бы записи, которых никто не смотрел.
    """
    coordinate = "%s.%s" % (POLICY_ALLOWLIST, role)
    if not world.has(coordinate):
        return set()
    declared = world.read(coordinate)
    if isinstance(declared, (list, tuple, set)):
        return {str(item).strip() for item in declared}
    return {str(declared).strip()}


def _event_unavailable(world):
    """Авторитет события недоступен — вердикта о предмете нет."""
    return not _authority_available(world)


def _event_missing(world):
    """Авторитет ответил, а события сходимости нет."""
    available = _authority_available(world)
    coordinate = _event_coordinate(world)
    if not available:
        # Молчание авторитета — не отрицание: об отсутствии события ничего не
        # известно, и находкой это стать не вправе.
        return False
    return _blank(coordinate)


def _owner_unauthorized(world):
    """Сходимость выдана актором вне списка своей роли."""
    role = str(world.read(REVIEWER_ROLE)).strip()
    actor = str(world.read(ACTOR)).strip()
    allowed = _allowed_actors(world, role)
    available = _authority_available(world)
    coordinate = _event_coordinate(world)
    if not available or _blank(coordinate):
        # Без подтверждённого события личность актора ничем не удостоверена.
        return False
    return actor not in allowed


def _declared_repositories(shas):
    """Имена репозиториев, ВЫВЕДЕННЫЕ из объявленных координат."""
    names = set()
    for key in shas:
        for suffix in (BASE_SUFFIX, SOURCE_SUFFIX):
            if key.endswith(suffix):
                names.add(key[: -len(suffix)])
    return names


def _content_identity_missing(world):
    """Запись сходимости не называет предмет полностью.

    Предмет назван, когда есть отпечаток содержимого, хеши изменения и по
    КАЖДОМУ репозиторию обе половины пары base/source. Половина пары не сужает
    ничего: по одному концу диапазон изменений не восстанавливается.
    """
    digest = world.read(RECORD_CONTENT_DIGEST)
    hashes = world.read_all(CHANGE_HASHES)
    shas = world.read_all(REPOS)

    if _blank(digest):
        return True
    if not isinstance(hashes, dict) or not hashes:
        return True
    if any(_blank(value) for value in hashes.values()):
        return True
    if not isinstance(shas, dict):
        return True
    repositories = _declared_repositories(shas)
    if not repositories:
        return True
    for name in sorted(repositories):
        for suffix in (BASE_SUFFIX, SOURCE_SUFFIX):
            if _blank(shas.get(name + suffix)):
                return True
    return False


def _specialist_set_mismatch(world):
    """Агрегат сходимости не равен точному набору применимых специалистов.

    Сравниваются ТРИ набора сразу: кому роль применима, чья запись привязана к
    этому предмету и кого перечислил агрегат. Равенство всех трёх и есть
    предмет: «есть хотя бы одна запись» — утверждение о другом.
    """
    digest = world.read(CONTENT_DIGEST)
    roles = world.read_all(APPLICABLE_ROLES)
    records = world.read_all(POST_DIFF_RECORDS)
    aggregated = world.read(AGGREGATOR)

    if not isinstance(roles, dict) or not isinstance(records, dict):
        return True
    if _blank(digest):
        return True

    token = str(digest).rsplit(DIGEST_SEPARATOR, 1)[-1].strip()
    applicable = {
        name for name, state in roles.items()
        if str(state).strip() == APPLICABLE
    }
    bound = set()
    for name, coordinate in records.items():
        text = str(coordinate)
        if name in text and token in text:
            bound.add(name)
    return not (applicable == bound == _named_specialists(aggregated))


def _named_specialists(aggregated):
    """Роли, перечисленные агрегатом.

    Набор законно записывается ДВУМЯ формами — строкой через запятую и
    последовательностью, — и распознаватель обязан знать обе: форма, о которой
    он не знает, не даёт ни красного, ни зелёного, она даёт молчание.
    """
    if isinstance(aggregated, (list, tuple, set)):
        items = [str(item) for item in aggregated]
    else:
        items = str(aggregated).split(AGGREGATOR_SEPARATOR)
    return {item.strip() for item in items if item.strip()}


RULES = [
    Rule(
        rule_id="conv.event-unavailable",
        diagnostic="CG_CONVERGENCE_EVENT_UNAVAILABLE",
        category=outcome.CATEGORY_NOT_EXECUTED,
        subject_keys=EVENT_SUBJECT,
        requires=EVENT_REQUIRES,
        predicate=_event_unavailable,
        why="недоступный авторитет события — отсутствие вердикта, а не "
            "отрицательный вердикт: неполученный ответ не есть «нет»",
    ),
    Rule(
        rule_id="conv.event-missing",
        diagnostic="CG_CONVERGENCE_EVENT_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=EVENT_SUBJECT,
        requires=EVENT_REQUIRES,
        predicate=_event_missing,
        why="сходимость подтверждается ВЕРИФИЦИРОВАННЫМ внешним событием; без "
            "него запись утверждает решение, которого никто не принимал",
    ),
    Rule(
        rule_id="conv.owner-unauthorized",
        diagnostic="CG_CONVERGENCE_OWNER_UNAUTHORIZED",
        category=outcome.CATEGORY_RED,
        subject_keys=EVENT_SUBJECT,
        requires=EVENT_REQUIRES,
        predicate=_owner_unauthorized,
        why="сходимость выдаёт актор из списка своей роли; чужой актор выдал бы "
            "себе право, которого ему не давали",
    ),
    Rule(
        rule_id="conv.content-identity-missing",
        diagnostic="CG_CONVERGENCE_CONTENT_IDENTITY_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=EVENT_SUBJECT,
        requires=EVENT_REQUIRES + (RECORD_CONTENT_DIGEST,),
        predicate=_content_identity_missing,
        why="запись обязана называть предмет точно: хеши изменения, обе половины "
            "пары base/source по каждому репозиторию и отпечаток содержимого — "
            "иначе сходимость выдана неизвестно чему",
    ),
    Rule(
        rule_id="conv.specialist-set-mismatch",
        diagnostic="CG_CONVERGENCE_SPECIALIST_SET_MISMATCH",
        category=outcome.CATEGORY_RED,
        subject_keys=SET_SUBJECT,
        requires=SET_REQUIRES,
        predicate=_specialist_set_mismatch,
        why="агрегат ссылается на ТОЧНЫЙ набор записей применимых специалистов; "
            "запись, не вошедшая в агрегат, не участвовала в сходимости, хотя "
            "её роль была применима",
    ),
]
