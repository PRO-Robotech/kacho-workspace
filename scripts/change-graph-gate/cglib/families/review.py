"""cg.review — полномочия ревью и нецикличность одобрения.

Приёмка §4. Несущее в ней одно: **вердикт выпускает внешнее событие, а не
строка в документе**. Из этого следует и форма правил, и то, чего в семействе
нет.

Два разных предмета, и мир кейса называет ровно один. Различает их состав
координат, а не идентификатор кейса:

    bootstrap · subject · event · permission · artifact  -> effective approval
    history_mode · review_history · recorded_content     -> append-only история

**Нецикличность здесь не метафора, а два независимых запрета.** Первый: subject
всегда сохраняет статическую форму DRAFT — документ, переписавший себя в
APPROVED, одобрил себя сам. Второй: bootstrap artifact обязан ВОСПРОИЗВОДИТЬ
событие, а не утверждать сверх него; артефакт, называющий другого actor'а, —
это подпись, которой никто не ставил.

**Недоступность — NOT_EXECUTED, и это первое, о чём спрашивают.** §4 говорит
дословно: «Недоступный API или ref — NOT_EXECUTED», «Недоступность permission,
Issue, event или API даёт NOT_EXECUTED». Поэтому оба правила доступности
объявлены раньше всех красных: неполученный ответ не есть «нет», и отвечать
RED по неизвестному значило бы выдавать «не знаю» за находку. Дальше порядок
идёт по тому, что делает бессмысленными последующие вопросы:

    доступность события и permission   ничего не известно вовсе
    статическая форма subject          нет предмета, о котором вердикт
    epoch authority                    исключение уже недействительно
    принадлежность события Issue       событие не о нашем изменении
    ADMIN у publisher'а                событие не несёт полномочия
    воспроизведение события артефактом артефакт утверждает сверх события

**Чего в семействе НЕТ и почему.** Правила «verdict не APPROVED» здесь нет:
приёмка такой диагностики не объявляет, а заводить свою нельзя — её не
предъявил бы ни один кейс, и она осталась бы кодом без пробы. Семейство судит
ПОЛНОМОЧИЕ и ТОЧНОСТЬ воспроизведения, а полярность вердикта выводится из
события (§13 SDD-1-REVIEW-01: «SUT выводит APPROVED, не изменяя subject»).

**Координаты события читаются как условие его получения.** Событие без
immutable node/ref и без digest'а тела — это событие, которого мы не достали:
§4 требует, чтобы artifact ссылался на immutable node/URL и body digest, и
отсутствие любой из этих координат означает «ref недоступен», то есть
NOT_EXECUTED, а не красноту.
"""

from .. import outcome
from ..rules import Rule

FAMILY = "review"

# §4, дословно: до cutover authority у bootstrap внешняя и ограничена epoch'ой.
BOOTSTRAP_EPOCH = "pre-cutover"

# §4: acceptance subject всегда сохраняет статическую форму DRAFT.
SUBJECT_STATIC_FORM = "DRAFT"

# §4: GitHub API обязан подтвердить permission ADMIN на репозитории воркспейса.
REQUIRED_PERMISSION_LEVEL = "ADMIN"

LOOKUP_AVAILABLE = "available"

# §4: старый review artifact не редактируется и не удаляется.
APPEND_ONLY = "append-only"

# Координаты, без которых событие считается недостанным, а не негодным.
EVENT_IDENTITY_COORDINATES = ("node_id", "body_sha256")

# Соответствие «поле артефакта -> поле события». Артефакт не добавляет к
# событию ничего: он его воспроизводит, и всякое расхождение означает одно и то
# же — артефакт утверждает то, чего событие не говорило.
ARTIFACT_MIRRORS_EVENT = {
    "authorized_actor": "actor",
    "reviewer_role": "role",
    "subject_sha256": "subject_sha256",
    "verdict": "verdict",
}


def _event_not_obtained(world):
    """Событие не получено: lookup недоступен либо у него нет координат.

    Все координаты читаются ДО решения, а не по короткому замыканию. Иначе
    предикат, ответивший по первой же, оставил бы остальные непрочитанными — и
    перепись справедливо назвала бы вердикт заявлением шире осмотренного.
    """
    lookup = world.read("event.lookup")
    identity = [
        world.read("event.%s" % coordinate)
        for coordinate in EVENT_IDENTITY_COORDINATES
    ]
    return lookup != LOOKUP_AVAILABLE or not all(identity)


def _permission_not_obtained(world):
    return world.read("permission.lookup") != LOOKUP_AVAILABLE


def _subject_not_static(world):
    """Subject переписал себя либо уехал из-под собственного отпечатка.

    Читается subject ЦЕЛИКОМ, потому что предмет правила — сам subject как
    предмет вердикта: статическая форма и отпечаток, к которому событие
    привязано, — две половины одного утверждения о нём.
    """
    subject = world.read_all("subject")
    bound = world.read("event.subject_sha256")
    return (
        subject.get("static_form") != SUBJECT_STATIC_FORM
        or bound != subject.get("sha256")
    )


def _authority_epoch_expired(world):
    return world.read("bootstrap.epoch") != BOOTSTRAP_EPOCH


def _event_belongs_to_another_issue(world):
    return world.read("event.issue") != world.read("bootstrap.issue")


def _publisher_lacks_admin(world):
    """Полномочие проверяется У ТОГО, кто событие опубликовал.

    §4: gate каждый раз проверяет permission через API, а не доверяет
    записанному имени. Значит недостаточно «кому-то выдан ADMIN» — ADMIN обязан
    быть выдан publisher'у события, поэтому читаются оба имени.
    """
    level = world.read("permission.level")
    checked_actor = world.read("permission.actor")
    publisher = world.read("event.actor")
    return level != REQUIRED_PERMISSION_LEVEL or checked_actor != publisher


def _artifact_does_not_mirror_event(world):
    """Артефакт утверждает не то, что сказало событие.

    Предикат — равенство артефакта ВЫВЕДЕННОМУ из события отображению, а не
    конъюнкция четырёх проверок с четырьмя диагностиками, трёх из которых
    приёмка не объявляет. Всякое расхождение означает одно и то же: перед нами
    не запись события, а самостоятельное утверждение о полномочии.
    """
    artifact = world.read_all("artifact")
    mirrored = {
        field: world.read("event.%s" % source)
        for field, source in ARTIFACT_MIRRORS_EVENT.items()
    }
    return artifact != mirrored


def _history_not_append_only(world):
    """История ревью append-only: содержимое записи равно её отпечатку.

    Читаются ОБА отображения целиком: append-only — отношение между тем, что
    записано, и тем, под каким отпечатком оно записано; по одной записи такого
    отношения не установить, а появление и исчезновение записи — такое же
    нарушение, как правка байта.
    """
    mode = world.read("history_mode")
    recorded = world.read_all("review_history")
    content = world.read_all("recorded_content")
    return mode != APPEND_ONLY or content != recorded


APPROVAL_KEYS = ("bootstrap", "subject", "event", "permission", "artifact")
HISTORY_KEYS = ("history_mode", "review_history", "recorded_content")

RULES = [
    Rule(
        rule_id="review.event-obtained",
        diagnostic="CG_BOOTSTRAP_EVENT_UNAVAILABLE",
        category=outcome.CATEGORY_NOT_EXECUTED,
        subject_keys=APPROVAL_KEYS,
        requires=APPROVAL_KEYS,
        predicate=_event_not_obtained,
        why="§4 недоступный API или ref даёт NOT_EXECUTED, не APPROVED и не "
            "RED: неполученный ответ не есть находка",
    ),
    Rule(
        rule_id="review.permission-obtained",
        diagnostic="CG_BOOTSTRAP_PERMISSION_UNAVAILABLE",
        category=outcome.CATEGORY_NOT_EXECUTED,
        subject_keys=APPROVAL_KEYS,
        requires=APPROVAL_KEYS,
        predicate=_permission_not_obtained,
        why="§4 недоступность permission даёт NOT_EXECUTED",
    ),
    Rule(
        rule_id="review.subject-static",
        diagnostic="CG_ACCEPTANCE_SUBJECT_MUTATED",
        category=outcome.CATEGORY_RED,
        subject_keys=APPROVAL_KEYS,
        requires=APPROVAL_KEYS,
        predicate=_subject_not_static,
        why="§4 acceptance subject всегда сохраняет статическую форму DRAFT; "
            "объявлено раньше правил о полномочии, потому что у переписавшего "
            "себя subject'а нет предмета, о котором вердикт выносится",
    ),
    Rule(
        rule_id="review.authority-epoch",
        diagnostic="CG_BOOTSTRAP_AUTHORITY_EXPIRED",
        category=outcome.CATEGORY_RED,
        subject_keys=APPROVAL_KEYS,
        requires=APPROVAL_KEYS,
        predicate=_authority_epoch_expired,
        why="§4 с момента cutover bootstrap exception недействителен и не "
            "продлевается: дальше authority задаёт только versioned policy",
    ),
    Rule(
        rule_id="review.event-issue",
        diagnostic="CG_BOOTSTRAP_ISSUE_MISMATCH",
        category=outcome.CATEGORY_RED,
        subject_keys=APPROVAL_KEYS,
        requires=APPROVAL_KEYS,
        predicate=_event_belongs_to_another_issue,
        why="§4 event принадлежит ровно Issue #480; событие о другом изменении "
            "полномочия этому изменению не даёт",
    ),
    Rule(
        rule_id="review.publisher-admin",
        diagnostic="CG_BOOTSTRAP_ACTOR_NOT_ADMIN",
        category=outcome.CATEGORY_RED,
        subject_keys=APPROVAL_KEYS,
        requires=APPROVAL_KEYS,
        predicate=_publisher_lacks_admin,
        why="§4 GitHub API обязан подтвердить publisher'у permission ADMIN; "
            "gate проверяет permission через API, а не доверяет имени",
    ),
    Rule(
        rule_id="review.artifact-mirrors-event",
        diagnostic="CG_BOOTSTRAP_ACTOR_SPOOFED",
        category=outcome.CATEGORY_RED,
        subject_keys=APPROVAL_KEYS,
        requires=APPROVAL_KEYS,
        predicate=_artifact_does_not_mirror_event,
        why="§4 bootstrap artifact ссылается на событие и его body digest; "
            "role name в YAML — coordinate, не доказательство личности",
    ),
    Rule(
        rule_id="review.history-append-only",
        diagnostic="CG_REVIEW_HISTORY_MUTATED",
        category=outcome.CATEGORY_RED,
        subject_keys=HISTORY_KEYS,
        requires=HISTORY_KEYS,
        predicate=_history_not_append_only,
        why="§4 старый review artifact не редактируется и не удаляется; новый "
            "subject получает новый sibling artifact",
    ),
]
