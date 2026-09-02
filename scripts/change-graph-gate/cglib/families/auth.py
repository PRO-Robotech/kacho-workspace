"""cg.auth — post-cutover producer authority: событие внешнего авторитета.

Приёмка §4, вторая половина. Первая половина (bootstrap до cutover) — предмет
`cg.review`; здесь судится то, что §4 объявляет ПОСЛЕ cutover:

    «После cutover producer authority future reviews задаёт
    docs/changes/policy.yaml: append-only artifact ссылается на GitHub
    Issue/PR review/comment event, gate получает event через API, actor
    разрешён для роли policy allowlist, а event body/subject digests и verdict
    совпадают.»

и, дословно оттуда же, — «Самодекларированное role: без event не даёт
authority», «Недоступный API или ref — NOT_EXECUTED», «Role name в YAML —
coordinate, не доказательство личности».

**Почему это отдельное семейство, а не правила внутри cg.review.** Предмет
другой и авторитет другой. У bootstrap авторитет внешний по отношению к ещё не
созданному policy trust root и проверяется через permission ADMIN у publisher'а;
после cutover авторитет задаёт версионированный allowlist, а permission
publisher'а к делу не относится вовсе. Общего у двух половин ровно одно —
вердикт выпускает СОБЫТИЕ, а не строка в документе; всё остальное расходится,
включая словарь диагностик (`CG_BOOTSTRAP_*` против `CG_REVIEW_*`).

**Эпоха — условие ПРИМЕНИМОСТИ, а не находка.** Семейство судит только
post-cutover мир: до cutover авторитет задаёт bootstrap exception, и это
предмет `cg.review`. Поэтому эпоха читается применимостью, а не предикатом:
диагностики «эпоха не та» приёмка не объявляет, а заводить свою нельзя — её не
предъявил бы ни один кейс, и она осталась бы кодом без пробы. Мир иной эпохи не
получает от этого семейства вердикта вовсе (собственный отказ
`CG_SELF_WORLD_NOT_JUDGED`), и это верно: «не мой предмет» не есть «нарушений
нет».

**Объявленный порядок правил — от того, что делает последующие вопросы
бессмысленными, к тому, что они сравнивают:**

    1. доступность API            ответа нет вовсе; «не знаю» ≠ «нет»
    2. артефакт называет событие   запрашивать нечего: перед нами самодекларация
    3. событие процитируемо        ссылка непроверяема: сравнивать не с чем
    4. actor допущен политикой     событие получено, но не от допущенного лица
    5. роль события — требуемая    лицо допущено, но не для этой роли
    6. digest тела совпал          событие о другом теле
    7. digest предмета совпал      событие о другом предмете

Первое правило — единственное в семействе с категорией NOT_EXECUTED, и стоит
оно первым намеренно: неполученный ответ не есть находка, и отвечать краснотой
по неизвестному значило бы выдавать «не знаю» за «нет».

**Чего в семействе НЕТ и почему.** Правила «verdict не APPROVED» нет: приёмка
такой диагностики не объявляет. Полярность вердикта выводится из события —
семейство судит ПОЛНОМОЧИЕ (кто, для какой роли, о каком теле и предмете), а не
содержание вердикта. Нет и правила о permission publisher'а: после cutover
authority задаёт версионированный allowlist, и permission к нему отношения не
имеет (§4: «с момента cutover ... используют только versioned policy
authority»).

**Отсутствующая координата спрашивается через `has`, а не через `read`.**
`read` по несуществующему пути — собственный отказ испытуемого, то есть «мир не
описывает предмет»; а здесь отсутствие координаты и есть ФАКТ, о котором
выносится вердикт (снятый immutable node, снятая ссылка на событие). Поэтому
присутствие спрашивается отдельно, а значение читается только тогда, когда оно
есть.

**Короткого замыкания внутри предиката нет намеренно.** Предикат, ответивший по
первой же негодной координате, оставил бы остальные непрочитанными — и перепись
справедливо объявила бы вердикт заявлением шире осмотренного
(`CG_SELF_WORLD_FACT_UNREAD`). Поэтому координаты читаются ВСЕ, а решение
принимается после.
"""

from .. import outcome
from ..rules import Rule

FAMILY = "auth"

# §4: предмет семейства — авторитет ПОСЛЕ cutover.
POST_CUTOVER_EPOCH = "post-cutover"

# §4: «Недоступный API или ref — NOT_EXECUTED».
API_AVAILABLE = "available"

EPOCH = "epoch"
REQUIRED_ROLE = "required_role"
POLICY_ALLOWLIST = "policy_allowlist"
API_AVAILABILITY = "api.availability"

ARTIFACT_ROLE = "artifact.role"
ARTIFACT_EVENT_COORDINATE = "artifact.event_coordinate"
ARTIFACT_BODY_DIGEST = "artifact.body_sha256"
ARTIFACT_SUBJECT_DIGEST = "artifact.subject_sha256"

EVENT_ACTOR = "event.actor"
EVENT_ROLE = "event.role"
EVENT_BODY_DIGEST = "event.body_sha256"
EVENT_SUBJECT_DIGEST = "event.subject_sha256"

# Координаты, без которых полученное событие не является ПРОЦИТИРУЕМОЙ записью:
# по ним событие адресуется (immutable node, постоянная ссылка) и по ним оно
# датируется и называет свой вердикт. Отсутствие любой означает одно и то же —
# ссылку, которую нельзя перепроверить, — поэтому и диагностика одна.
EVENT_CITATION_COORDINATES = ("node_id", "url", "verdict", "timestamp")


def _judges_post_cutover_world(world):
    """Применимость семейства: мир объявлен post-cutover.

    Эпоха читается здесь, а не в предикате, потому что она не находка, а
    условие: до cutover авторитет задаёт bootstrap exception, и такой мир судит
    `cg.review`. Мир иной эпохи остаётся без вердикта этого семейства — это
    честнее, чем ответить о предмете, которого семейство не знает.
    """
    return world.read(EPOCH) == POST_CUTOVER_EPOCH


def _as_actor_set(value):
    """Запись allowlist — либо одно имя, либо перечень имён."""
    if isinstance(value, (list, tuple, set)):
        return {str(item).strip() for item in value}
    return {str(value).strip()}


def _roles_allowing(allowlist, actor):
    """Роли, для которых allowlist допускает этого actor'а.

    Таблица обходится ЦЕЛИКОМ, и это не расточительность: ответ «actor допущен»
    неотделим от ответа «допущен ДЛЯ ЭТОЙ роли». Строка соседней роли — тоже
    часть предмета, потому что именно она делает возможной подмену «допущен
    где-то» на «допущен здесь», а §4 такую подмену запрещает прямо: role name в
    YAML — coordinate, не доказательство личности.
    """
    allowed = set()
    for role in allowlist:
        if actor in _as_actor_set(allowlist[role]):
            allowed.add(str(role))
    return allowed


def _api_unavailable(world):
    """§4: недоступный API — NOT_EXECUTED, а не RED и не APPROVED."""
    return world.read(API_AVAILABILITY) != API_AVAILABLE


def _role_declared_without_event(world):
    """§4: самодекларированное role без event не даёт authority.

    Предмет правила — заявленная артефактом роль, не подпёртая внешним
    событием. Читаются обе половины: сама роль (её и отвергают) и ссылка на
    событие. Ссылки может не быть вовсе — тогда её отсутствие и есть факт,
    поэтому присутствие спрашивается через `has`.
    """
    claimed_role = str(world.read(ARTIFACT_ROLE)).strip()
    if not claimed_role:
        # Артефакт роли не заявляет — подпирать событием нечего, и находки
        # этого правила здесь нет. Приёмка диагностики «артефакт без роли» не
        # объявляет, поэтому заводить её нельзя (она осталась бы кодом без
        # пробы), а выдавать её за самодекларацию — врать о предмете.
        return False
    if not world.has(ARTIFACT_EVENT_COORDINATE):
        return True
    return not str(world.read(ARTIFACT_EVENT_COORDINATE)).strip()


def _event_reference_unverifiable(world):
    """§4: ссылка обязана быть immutable и перепроверяемой.

    Читаются ВСЕ координаты цитирования и только потом принимается решение:
    короткое замыкание на первой негодной оставило бы остальные непрочитанными,
    и перепись объявила бы вердикт заявлением шире осмотренного.
    """
    citable = []
    for coordinate in EVENT_CITATION_COORDINATES:
        path = "event.%s" % coordinate
        if not world.has(path):
            citable.append(False)
            continue
        citable.append(bool(str(world.read(path)).strip()))
    return not all(citable)


def _actor_not_allowed_by_policy(world):
    """§4: actor разрешён для роли policy allowlist.

    Сравнивается не «есть ли такое имя в таблице», а «допускает ли таблица это
    имя ДЛЯ ТРЕБУЕМОЙ роли»: допуск, выданный под другую роль, полномочия здесь
    не даёт.
    """
    allowlist = world.read_all(POLICY_ALLOWLIST)
    required = str(world.read(REQUIRED_ROLE)).strip()
    actor = str(world.read(EVENT_ACTOR)).strip()
    return required not in _roles_allowing(allowlist, actor)


def _event_registered_for_another_role(world):
    """§4: SUT не подменяет требуемую роль другой.

    Actor может быть безупречен и при этом зарегистрировать событие под чужой
    ролью — тогда полномочия для ТРЕБУЕМОЙ роли нет, и находка именно об этом.
    """
    return str(world.read(EVENT_ROLE)).strip() != str(
        world.read(REQUIRED_ROLE)
    ).strip()


def _body_digest_diverges(world):
    """§4: event body digest совпадает с тем, на который ссылается артефакт."""
    return str(world.read(EVENT_BODY_DIGEST)).strip() != str(
        world.read(ARTIFACT_BODY_DIGEST)
    ).strip()


def _subject_digest_diverges(world):
    """§4: event subject digest совпадает с предметом, к которому привязан.

    Совпадение тела и совпадение предмета — РАЗНЫЕ утверждения, и приёмка даёт
    им разные диагностики: событие может нести неизменное тело и при этом быть
    привязано к чужому предмету.
    """
    return str(world.read(EVENT_SUBJECT_DIGEST)).strip() != str(
        world.read(ARTIFACT_SUBJECT_DIGEST)
    ).strip()


RULES = [
    Rule(
        rule_id="auth.api-available",
        diagnostic="CG_REVIEW_API_UNAVAILABLE",
        category=outcome.CATEGORY_NOT_EXECUTED,
        subject_keys=(EPOCH, "api"),
        requires=(EPOCH, API_AVAILABILITY),
        applicability=_judges_post_cutover_world,
        predicate=_api_unavailable,
        why="§4 недоступный API или ref даёт NOT_EXECUTED; объявлено первым, "
            "потому что неполученный ответ не есть находка, и всякий "
            "последующий вопрос задавался бы о том, чего мы не получали",
    ),
    Rule(
        rule_id="auth.artifact-names-event",
        diagnostic="CG_REVIEW_EVENT_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=(EPOCH, "artifact"),
        requires=(EPOCH, ARTIFACT_ROLE),
        applicability=_judges_post_cutover_world,
        predicate=_role_declared_without_event,
        why="§4 самодекларированное role без event не даёт authority; "
            "объявлено раньше правил о самом событии, потому что у артефакта, "
            "не назвавшего события, запрашивать нечего",
    ),
    Rule(
        rule_id="auth.event-citable",
        diagnostic="CG_REVIEW_EVENT_IDENTITY_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=(EPOCH, "event"),
        requires=(EPOCH, "event"),
        applicability=_judges_post_cutover_world,
        predicate=_event_reference_unverifiable,
        why="§4 artifact ссылается на immutable node/URL события; ссылка, "
            "которую нельзя перепроверить, делает бессмысленным всякое "
            "последующее сравнение — поэтому правило объявлено раньше них",
    ),
    Rule(
        rule_id="auth.actor-allowed",
        diagnostic="CG_REVIEW_ACTOR_UNAUTHORIZED",
        category=outcome.CATEGORY_RED,
        subject_keys=(EPOCH, POLICY_ALLOWLIST, REQUIRED_ROLE, "event"),
        requires=(EPOCH, POLICY_ALLOWLIST, REQUIRED_ROLE, EVENT_ACTOR),
        applicability=_judges_post_cutover_world,
        predicate=_actor_not_allowed_by_policy,
        why="§4 после cutover actor разрешён для роли versioned policy "
            "allowlist; допуск под другую роль полномочия здесь не даёт",
    ),
    Rule(
        rule_id="auth.role-authorized",
        diagnostic="CG_REVIEW_ROLE_UNAUTHORIZED",
        category=outcome.CATEGORY_RED,
        subject_keys=(EPOCH, REQUIRED_ROLE, "event"),
        requires=(EPOCH, REQUIRED_ROLE, EVENT_ROLE),
        applicability=_judges_post_cutover_world,
        predicate=_event_registered_for_another_role,
        why="§4 SUT не подменяет acceptance-reviewer другой ролью; объявлено "
            "после допуска actor'а, потому что роль чужого лица не обсуждается",
    ),
    Rule(
        rule_id="auth.body-digest",
        diagnostic="CG_REVIEW_BODY_DIGEST_MISMATCH",
        category=outcome.CATEGORY_RED,
        subject_keys=(EPOCH, "artifact", "event"),
        requires=(EPOCH, ARTIFACT_BODY_DIGEST, EVENT_BODY_DIGEST),
        applicability=_judges_post_cutover_world,
        predicate=_body_digest_diverges,
        why="§4 event body digest совпадает с тем, на который ссылается "
            "артефакт: иначе полномочие предъявлено по другому телу",
    ),
    Rule(
        rule_id="auth.subject-digest",
        diagnostic="CG_REVIEW_SUBJECT_DIGEST_MISMATCH",
        category=outcome.CATEGORY_RED,
        subject_keys=(EPOCH, "artifact", "event"),
        requires=(EPOCH, ARTIFACT_SUBJECT_DIGEST, EVENT_SUBJECT_DIGEST),
        applicability=_judges_post_cutover_world,
        predicate=_subject_digest_diverges,
        why="§4 event subject digest совпадает с предметом; событие с "
            "неизменным телом всё ещё может быть привязано к чужому предмету, "
            "поэтому диагностика отдельная от digest'а тела",
    ),
]
