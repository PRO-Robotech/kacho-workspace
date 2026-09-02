"""cg.na — «неприменимо» как законный исход, а не как пропуск.

Приёмка §5, дословно: «N/A допустим только по predicate ID из versioned
applicability registry в policy.yaml и с evidence, удовлетворяющим этому
predicate. Свободный текст N/A не является evidence».

**Предмет семейства — отличить освобождение от умолчания.** «Держателя здесь
быть не должно» и «держателя здесь нет» выглядят одинаково: в обоих случаях
вердикта роли нет. Различает их ровно одно — ЗАРЕГИСТРИРОВАННЫЙ предикат,
который кто-то однажды объявил, и evidence, которое этот предикат выполняет.
Без обеих половин «неприменимо» есть пропуск, назвавший себя решением.

**Отсюда два правила, и второе не поглощает первое.** Предикат, которого нет в
реестре, вычислять не над чем: вопрос «выполняет ли evidence это условие»
задан об условии, которого никто не формулировал. Поэтому правило о
незарегистрированном предикате объявлено раньше, а правило о невыполненном
предикате на незарегистрированном молчит — иначе одна и та же находка
предъявлялась бы дважды двумя разными диагностиками.

**Освобождение всегда чьё-то.** Читается вся заявка целиком: она есть пара
«роль + предикат», и запись, не назвавшая роль, не освобождает никого — она
лишь выглядит освобождением. Реестр предикатов тоже читается целиком: членство
в реестре есть свойство реестра, а не одной записи, и ключ заявки приходит из
мира, поэтому по частям он не адресуется.

**Зарегистрированный предикат, которого испытуемый вычислить не умеет, — его
СОБСТВЕННЫЙ отказ, а не вердикт.** Ответить «выполнен» значило бы принять
условие и не посмотреть на него; ответить «не выполнен» — обвинить, не
проверив. Оба ответа хуже отсутствия ответа, поэтому здесь поднимается
собственный отказ: вердикта о предмете нет, и он не выдаётся ни за «да», ни за
«нет».
"""

from .. import outcome
from ..rules import Rule

FAMILY = "na"

SUBJECT_KEYS = ("applicability", "policy_predicates", "evidence")
REQUIRES = SUBJECT_KEYS

REGISTERED_MARKER = "registered"

# Что каждый зарегистрированный предикат означает как условие над evidence:
# координата evidence и значение, при котором предикат ИСТИНЕН.
PREDICATE_MEANING = {
    "no-migrations-in-change": ("migrations_touched", 0),
    "no-proto-in-change": ("proto_touched", 0),
}

ABSENT_MARKERS = (None, "", "none", "—")


def _absent(value):
    if value in ABSENT_MARKERS:
        return True
    return isinstance(value, str) and not value.strip()


def _claim_is_unregistered(world):
    """Заявка об освобождении не опирается на зарегистрированный предикат.

    Заявка читается целиком: она есть пара «чья обязанность снята» и «на каком
    основании», и половина пары освобождения не образует.
    """
    claim = world.read_all("applicability")
    registry = world.read_all("policy_predicates")

    if _absent(claim.get("role")):
        return True
    predicate_id = claim.get("predicate_id")
    if _absent(predicate_id):
        return True
    return registry.get(predicate_id) != REGISTERED_MARKER


def _registered_predicate_is_false(world):
    """Evidence не выполняет предикат, на который сослалась заявка.

    Evidence читается целиком: предикат объявляет, какая его координата и с
    каким значением делает его истинным, поэтому запись рассматривается как
    целое, а не выборкой одного заранее известного поля.
    """
    predicate_id = world.read("applicability.predicate_id")
    registry = world.read_all("policy_predicates")
    evidence = world.read_all("evidence")

    if registry.get(predicate_id) != REGISTERED_MARKER:
        # Незарегистрированный предикат вычислять не над чем; эта находка уже
        # объявлена правилом выше и здесь не предъявляется вторично.
        return False

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
        rule_id="na.predicate-unregistered",
        diagnostic="CG_NA_PREDICATE_UNREGISTERED",
        category=outcome.CATEGORY_RED,
        subject_keys=SUBJECT_KEYS,
        requires=REQUIRES,
        predicate=_claim_is_unregistered,
        why="§5 N/A допустим только по predicate ID из versioned applicability "
            "registry; заявка без роли не освобождает никого",
    ),
    Rule(
        rule_id="na.predicate-false",
        diagnostic="CG_NA_PREDICATE_FALSE",
        category=outcome.CATEGORY_RED,
        subject_keys=SUBJECT_KEYS,
        requires=REQUIRES,
        predicate=_registered_predicate_is_false,
        why="§5 evidence обязано удовлетворять этому predicate; свободный текст "
            "N/A не является evidence",
    ),
]
