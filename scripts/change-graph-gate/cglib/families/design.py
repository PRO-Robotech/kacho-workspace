"""cg.design — связь замысла с приёмкой: закрытый design и applicable reviews.

Приёмка §5, дословно: «DESIGN_APPROVED запрещён при TODO, TBD, open decision,
unmapped exposure, отсутствующем applicable review или stale revalidation».
Шесть условий, но не шесть семейств: unmapped exposure и stale revalidation —
предмет `cg.class`, а здесь остаются два, и приёмка объявляет им ровно две
диагностики.

**Почему правило о design'е читает запись ЦЕЛИКОМ, а не один маркер.** Вердикт
привязывается к отпечатку предмета (§4, §9): design без отпечатка нечем связать
с одобрением, и одобрять его значило бы одобрять «что-нибудь». Поэтому предикат
— условие допустимости ЗАПИСИ: она названа отпечатком и не содержит открытых
решений. Заводить второй диагностике имя, которого приёмка не объявляет, нельзя
— она не была бы предъявлена ни одним кейсом и осталась бы кодом без пробы; тот
же довод стоит в `cglib/families/boot.py`.

**Зарегистрированный состав applicable reviews.** Состав задаёт versioned
applicability registry (`docs/changes/policy.yaml`, §5), которого до cutover не
существует. Поэтому у единственного bootstrap change он зарегистрирован здесь —
ровно как `boot.py` регистрирует состав его допуска. Предикат снятия назван:
появится registry — состав читается из него, а константа уходит вместе с
bootstrap exception (§4).

**Почему состав, а не «все объявленные verified».** Мир объявляет отображение
«review → состояние», и снятая строка означает не «этот review не нужен», а
«его больше не спрашивают». Судить только по объявленным значило бы позволить
снять неудобный review вместо того, чтобы его пройти: проверка была бы формой
без содержания.

Порядок объявления: открытая запись сначала. Design с открытым решением не
может быть одобрен независимо от того, сколько ревью его прочитали, — вопрос о
полноте ревью на нём преждевременен.
"""

from .. import outcome
from ..rules import Rule

FAMILY = "design"

# §5: перечень applicable pre-code reviews единственного bootstrap change.
REGISTERED_PRECODE_REVIEWS = ("db-architect-reviewer", "proto-api-reviewer")

VERIFIED = "verified"

# §5 перечисляет открытые решения поимённо: TODO, TBD, open decision. Отсутствие
# маркера обязано быть выражено значением, а не пустотой, поэтому словарь
# «маркеров нет» назван явно и не угадывается по правдоподобию строки.
NO_OPEN_DECISIONS = (None, "", "none", "—")


def _design_record_not_closed(world):
    """Design не годен к одобрению: без отпечатка либо с открытым решением.

    Читается запись целиком: обе половины — условия одной допустимости, и
    приёмка объявляет им одну диагностику.
    """
    design = world.read_all("design")
    return (
        not design.get("content_digest")
        or design.get("open_decision_markers") not in NO_OPEN_DECISIONS
    )


def _precode_review_missing(world):
    """Хотя бы один зарегистрированный applicable review не пройден.

    Перебирается ЗАРЕГИСТРИРОВАННЫЙ состав, а не объявленный миром: снятая
    строка и строка в состоянии, отличном от verified, — одно и то же
    отсутствие пройденного ревью, и обе обязаны находиться одинаково.
    """
    declared = world.read_all("applicable_precode_reviews")
    return any(
        declared.get(review) != VERIFIED
        for review in REGISTERED_PRECODE_REVIEWS
    )


DESIGN_KEYS = ("design", "applicable_precode_reviews")

RULES = [
    Rule(
        rule_id="design.record-closed",
        diagnostic="CG_DESIGN_DECISION_OPEN",
        category=outcome.CATEGORY_RED,
        subject_keys=DESIGN_KEYS,
        requires=("design",),
        predicate=_design_record_not_closed,
        why="§5 DESIGN_APPROVED запрещён при TODO, TBD и open decision; §4 и §9 "
            "вердикт привязывается к отпечатку предмета, поэтому неназванный "
            "отпечаток делает одобрение беспредметным",
    ),
    Rule(
        rule_id="design.precode-reviews",
        diagnostic="CG_PRECODE_REVIEW_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=DESIGN_KEYS,
        requires=("applicable_precode_reviews",),
        predicate=_precode_review_missing,
        why="§5 DESIGN_APPROVED запрещён при отсутствующем applicable review; "
            "N/A допустим только по predicate ID из versioned applicability "
            "registry, а свободное умолчание evidence не является",
    ),
]
