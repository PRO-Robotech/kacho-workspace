"""cg.post — post-diff review: чей вердикт, о каком содержимом и кто освобождён.

Приёмка §13, раздел «Diff ownership, post-diff review и convergence», объявляет
пять поведений и один законный вид отсутствия вердикта:

    POST-01  два applicable roles держат ОТДЕЛЬНЫЕ verified records
             `post-diff/<role>/<content-digest>.yaml` на один digest
    POST-02  у applicable role записи нет                -> REVIEW_MISSING
    POST-03  запись второй роли указывает на файл первой -> REVIEW_OVERWRITTEN
    POST-04  distributed surface повторно reviewed отдельной system-design
             записью на EXACT content digest
    POST-05  distributed surface без такой записи        -> REREVIEW_MISSING
    POST-NA  освобождение роли по зарегистрированному предикату и evidence

**Запись принадлежит РОЛИ, и это не деталь хранения.** Координата записи несёт
имя роли своим предпоследним сегментом, поэтому «запись есть» и «запись этой
роли» — разные утверждения. Запись, чей владелец другой, означает, что вердикт
одной роли записан поверх вердикта другой: файл один, ролей две, и вторая
половина ответа не сохранилась. Отсюда диагностика OVERWRITTEN, а не «набор не
тот»: оператору говорится, ЧТО именно произошло с чужим вердиктом.

**Запись принадлежит ещё и ОТПЕЧАТКУ.** §9: вердикт связан с конкретным subject
digest, новый subject получает новый artifact, старый вердикт не переносится.
Поэтому запись, лежащая по другому digest, для этого содержимого не существует
— это отсутствие вердикта, а не его наличие в неудобном месте.

**Порядок объявления идёт от находки, содержащей в себе последующую.**
Отсутствующую запись бессмысленно спрашивать о владельце: вопрос «чья она»
задан о том, чего нет. Поэтому правило об отсутствии объявлено раньше правила о
владельце, и правило о владельце на отсутствующей записи МОЛЧИТ — иначе одна
находка предъявлялась бы двумя диагностиками.

**Distributed surface — отдельная полоса, а не частный случай первых двух.**
Там нет перечня applicable roles вовсе: обязанность возникает из СВОЙСТВА
изменения, а не из чьей-то отметки «applicable». Правило поэтому спрашивает
свою координату и на мирах без распределённой поверхности не применимо by
construction.

**Освобождение — одно правило, а не два.** cg.na различает «предикат не
зарегистрирован» и «evidence его не выполняет» двумя диагностиками, потому что
обе объявлены приёмкой для ЕГО полосы. Здесь приёмка объявляет одну —
`CG_POST_DIFF_NA_FALSE`, — и заводить вторую значило бы завести код, который не
предъявит ни один кейс. Оба состояния означают для post-diff одно и то же:
заявленное освобождение ничем не подкреплено, то есть N/A ложно.
"""

from ..rules import Rule
from .. import outcome
from .na import PREDICATE_MEANING, REGISTERED_MARKER

FAMILY = "post"

CONTENT_DIGEST = "content_digest"
APPLICABLE_ROLES = "applicable_roles"
POST_DIFF_RECORDS = "post_diff_records"
DISTRIBUTED_SURFACE = "distributed_surface"
ROLE = "role"
DECLARED_PREDICATE_ID = "declared_predicate_id"
POLICY_PREDICATES = "policy_predicates"
EVIDENCE = "evidence"

APPLICABLE = "applicable"
SYSTEM_DESIGN_ROLE = "system-design-reviewer"

DIGEST_PREFIX = "sha256:"
RECORD_SUFFIX = ".yaml"
PATH_SEPARATOR = "/"

# Пустое значение обязано означать «пусто»: словарь отсутствия назван явно,
# чтобы «none» не пришлось угадывать по правдоподобию строки.
ABSENT_MARKERS = (None, "", "none", "—")


def _absent(value):
    if value in ABSENT_MARKERS:
        return True
    return isinstance(value, str) and not value.strip()


def _subject_of_digest(digest):
    """Имя subject'а, под которым содержимое лежит в координате записи."""
    text = str(digest)
    if text.startswith(DIGEST_PREFIX):
        return text[len(DIGEST_PREFIX):]
    return text


def _record_owner_and_subject(coordinate):
    """Владелец записи и subject, о котором она. Оба — из самой координаты.

    Форма координаты объявлена приёмкой: `post-diff/<role>/<content-digest>`.
    Владелец — предпоследний сегмент, subject — имя файла без расширения.
    Координата, не имеющей этой формы, не даёт ни того, ни другого, и это
    возвращается ЯВНО (парой None), а не тихой пустотой: молчание здесь
    означало бы «владелец совпал».
    """
    text = str(coordinate)
    segments = text.split(PATH_SEPARATOR)
    if len(segments) < 2:
        return None, None
    filename = segments[-1]
    if not filename.endswith(RECORD_SUFFIX):
        return segments[-2], None
    return segments[-2], filename[: -len(RECORD_SUFFIX)]


def _applicable_role_names(declared):
    """Роли, чья обязанность объявлена. Судится ЗНАЧЕНИЕ, а не наличие ключа.

    Роль, стоящая в переписи с другим значением, обязанности не несёт; считать
    её обязанной значило бы принять упоминание за назначение (тот же разбор,
    что у cg.wire про упоминание против вызова).
    """
    return [name for name in sorted(declared) if declared[name] == APPLICABLE]


def _applicable_review_missing(world):
    """У applicable role нет verified record на ЭТОТ content digest.

    Читаются оба отображения и сам digest: вопрос есть отношение трёх фактов —
    кто обязан, что записано и о каком содержимом, — и по одному он не решается.
    Запись, лежащая по другому subject, отсутствием вердикта и является (§9).
    """
    digest = world.read(CONTENT_DIGEST)
    declared = world.read_all(APPLICABLE_ROLES)
    records = world.read_all(POST_DIFF_RECORDS)

    subject = _subject_of_digest(digest)
    unreviewed = []
    for role in _applicable_role_names(declared):
        coordinate = records.get(role)
        if _absent(coordinate):
            unreviewed.append(role)
            continue
        _, record_subject = _record_owner_and_subject(coordinate)
        if record_subject != subject:
            unreviewed.append(role)
    return bool(unreviewed)


def _applicable_review_overwritten(world):
    """Запись applicable role принадлежит ДРУГОЙ роли — вердикт затёрт.

    На отсутствующей записи правило молчит намеренно: её отсутствие уже
    объявлено правилом выше, и предъявлять одну находку двумя диагностиками
    значило бы удвоить её, а не уточнить.
    """
    declared = world.read_all(APPLICABLE_ROLES)
    records = world.read_all(POST_DIFF_RECORDS)

    overwritten = []
    for role in _applicable_role_names(declared):
        coordinate = records.get(role)
        if _absent(coordinate):
            continue
        owner, _ = _record_owner_and_subject(coordinate)
        if owner != role:
            overwritten.append(role)
    return bool(overwritten)


def _system_design_rereview_missing(world):
    """Distributed surface без отдельной system-design записи на этот digest.

    Обязанность возникает из свойства изменения, а не из чьей-то отметки, и
    записи прежней роли её не удовлетворяют: спрашивается ИМЕННО координата
    system-design-роли, привязанная к текущему содержимому.
    """
    distributed = world.read(DISTRIBUTED_SURFACE)
    digest = world.read(CONTENT_DIGEST)
    records = world.read_all(POST_DIFF_RECORDS)

    if not distributed:
        return False
    coordinate = records.get(SYSTEM_DESIGN_ROLE)
    if _absent(coordinate):
        return True
    owner, record_subject = _record_owner_and_subject(coordinate)
    return owner != SYSTEM_DESIGN_ROLE or record_subject != _subject_of_digest(digest)


def _declared_na_is_false(world):
    """Заявленное освобождение роли ничем не подкреплено.

    Читается вся заявка: она есть тройка «чья обязанность снята», «на каком
    зарегистрированном основании» и «чем это основание выполнено». Реестр
    предикатов и evidence берутся целиком — членство есть свойство реестра, а
    координату evidence называет сам предикат, поэтому по частям они не
    адресуются.

    Реестр предикатов ОДИН на платформу (§8 `applicability_predicates` в
    policy.yaml), поэтому его значение импортируется из cg.na, а не копируется:
    две копии одного реестра разошлись бы молча, и разошлись бы именно там, где
    расхождение не видно, — на предикате, который одна полоса умеет вычислить,
    а другая нет.

    Зарегистрированный предикат, которого испытуемый вычислить не умеет, — его
    СОБСТВЕННЫЙ отказ, а не вердикт: «выполнен» значило бы принять условие и не
    посмотреть на него, «не выполнен» — обвинить, не проверив.
    """
    role = world.read(ROLE)
    predicate_id = world.read(DECLARED_PREDICATE_ID)
    registry = world.read_all(POLICY_PREDICATES)
    evidence = world.read_all(EVIDENCE)

    if _absent(role) or _absent(predicate_id):
        # Освобождение всегда чьё-то и всегда на основании: запись без роли не
        # освобождает никого, запись без основания — ничем не подкреплена.
        return True
    if registry.get(predicate_id) != REGISTERED_MARKER:
        # §5: N/A допустим только по predicate ID из versioned applicability
        # registry. Незарегистрированное основание основанием не является.
        return True

    meaning = PREDICATE_MEANING.get(predicate_id)
    if meaning is None:
        raise outcome.SelfFailure(
            outcome.SELF_INTERNAL,
            "предикат %r зарегистрирован в policy, но испытуемый не умеет его "
            "вычислить; известные ему предикаты: %s. Ответить «выполнен» "
            "значило бы принять условие и не посмотреть на него, ответить «не "
            "выполнен» — обвинить, не проверив"
            % (predicate_id, sorted(PREDICATE_MEANING)),
        )

    coordinate, satisfying_value = meaning
    if coordinate not in evidence:
        # Свободный текст N/A не является evidence: записи, о которой предикат
        # говорит, в ней нет вовсе, значит предикат ею не выполнен.
        return True
    return evidence[coordinate] != satisfying_value


RULES = [
    Rule(
        rule_id="post.review-missing",
        diagnostic="CG_POST_DIFF_REVIEW_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=(CONTENT_DIGEST, APPLICABLE_ROLES, POST_DIFF_RECORDS),
        requires=(CONTENT_DIGEST, APPLICABLE_ROLES, POST_DIFF_RECORDS),
        predicate=_applicable_review_missing,
        why="§13 SDD-1-POST-02: aggregator сверяет exact role set, и у каждого "
            "applicable role обязан быть verified record на этот content digest",
    ),
    Rule(
        rule_id="post.review-overwritten",
        diagnostic="CG_POST_DIFF_REVIEW_OVERWRITTEN",
        category=outcome.CATEGORY_RED,
        subject_keys=(APPLICABLE_ROLES, POST_DIFF_RECORDS),
        requires=(APPLICABLE_ROLES, POST_DIFF_RECORDS),
        predicate=_applicable_review_overwritten,
        why="§13 SDD-1-POST-03: aggregator проверяет ownership — запись роли "
            "обязана принадлежать ей, иначе один вердикт записан поверх другого",
    ),
    Rule(
        rule_id="post.system-design-rereview-missing",
        diagnostic="CG_SYSTEM_DESIGN_REREVIEW_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=(DISTRIBUTED_SURFACE, CONTENT_DIGEST, POST_DIFF_RECORDS),
        requires=(DISTRIBUTED_SURFACE, CONTENT_DIGEST, POST_DIFF_RECORDS),
        predicate=_system_design_rereview_missing,
        why="§13 SDD-1-POST-05: distributed surface требует отдельного "
            "post-diff system-design record на exact content digest",
    ),
    Rule(
        rule_id="post.na-unbacked",
        diagnostic="CG_POST_DIFF_NA_FALSE",
        category=outcome.CATEGORY_RED,
        subject_keys=(ROLE, DECLARED_PREDICATE_ID, POLICY_PREDICATES, EVIDENCE),
        requires=(ROLE, DECLARED_PREDICATE_ID, POLICY_PREDICATES, EVIDENCE),
        predicate=_declared_na_is_false,
        why="§5 и §13 SDD-1-POST-NA-02: N/A допустим только по registered "
            "predicate с evidence, которое его выполняет; иначе освобождение "
            "ложно",
    ),
]
