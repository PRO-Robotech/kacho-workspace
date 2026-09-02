"""cg.life — переход по стадиям: что обязано быть на месте и куда можно шагнуть.

Приёмка §5 объявляет линейную цепочку стадий:

    ISSUE_READY → ACCEPTANCE_APPROVED → CLASS_EXPOSURE_RECORDED →
    DESIGN_APPROVED → TASKS_READY → RED_PROVEN → IMPLEMENTING → CONVERGED →
    LANDED → ARCHIVED

и отдельно называет WITHDRAWN и SUPERSEDED терминальными БОКОВЫМИ состояниями.

Отсюда у семейства три правила и два предмета: **состоятельность текущей
стадии** (её артефакты и её вердикты) и **законность запрошенного шага**.

## Объявленный порядок: сперва текущая стадия, потом запрошенный шаг

Артефакт → вердикт → смежность. Причина не стилистическая: первые два говорят,
достигнута ли стадия, из которой шагают, а третье — законен ли сам шаг. Пока
стадия не состоялась, вопрос «куда дальше» вторичен, и вердикт обязан назвать
то, что чинится первым. Обратный порядок посылал бы читателя переписывать
запрос там, где не хватает артефакта.

Артефакт стоит раньше вердикта, потому что вердикт выносится ПО артефакту:
одобрения без предмета не бывает, поэтому отсутствие артефакта содержит в себе
непригодность вердикта, а не наоборот.

## Перечни объявлены ПО СТАДИЯМ, и незнакомая стадия — громкий отказ

Что обязано лежать на стадии и какие вердикты она связывает, известно не
вообще, а для конкретной стадии (§5 + §3 «Package layout»). Пустой перечень
здесь был бы всеразрешением: правило «ни одного обязательного артефакта не
пропущено» на пустом перечне зеленеет всегда и потому не проверяет ничего.

Поэтому перечень заведён таблицей по стадиям, и стадия, которой в таблице нет,
даёт СОБСТВЕННЫЙ ОТКАЗ испытуемого, а не молчаливое GREEN: «не знаю» никогда не
выдаётся за «нет». Таблица растёт вместе с кейсами, которые её осматривают;
выписать в неё стадии, которых не осматривает ни один кейс, значило бы завести
утверждение, которое никто не проверит.

## Присутствие и одобрение объявляются РОВНО ОДНИМ значением

`present` и `APPROVED` — закрытые метки, как закрыта тройка захваченных исходов
у держателей. Значение вне метки утверждением о присутствии (об одобрении) не
является: пустая строка, «missing», «CHANGES_REQUESTED» и незнакомое слово
одинаково не дают опоры. Иначе метка была бы не проверкой, а угадыванием по
правдоподобию строки.

## Чего это семейство НЕ судит — названо прямо

**Боковые состояния.** Запрос перехода в WITHDRAWN или SUPERSEDED смежностью
линейной цепочки не судится: они объявлены §5 боковыми, то есть лежат ВНЕ
цепочки, и мерить их шагом по ней значило бы объявлять незаконным то, что
приёмка разрешает. Законность самого отзыва и самого замещения — предмет
семейств отзыва и замещения (`CG_WITHDRAW_AFTER_LANDING`,
`CG_SUPERSEDE_CYCLE`), а не этого; здесь он не дублируется, иначе завелось бы
второе место об одном предмете.

**Появление tasks.md.** Обязательный writing-plans handoff после
DESIGN_APPROVED судит семейство задач (`CG_WRITING_PLANS_HANDOFF_MISSING`,
`CG_TASKS_BEFORE_DESIGN_APPROVAL`). Здесь стадия TASKS_READY — просто следующий
шаг цепочки, и что именно его наполняет, спрашивают там.
"""

from .. import outcome
from ..rules import Rule

FAMILY = "life"

# Предмет семейства — ОБЪЕДИНЕНИЕ предметов правил; у каждого правила он свой и
# уже: правило об артефактах о запрошенном шаге не судит и судить не вправе.

# §5, дословная линейная цепочка. Порядок здесь — сам предмет правила
# смежности, поэтому он выписан целиком, а не выведен из чего-то.
LIFECYCLE_ORDER = (
    "ISSUE_READY",
    "ACCEPTANCE_APPROVED",
    "CLASS_EXPOSURE_RECORDED",
    "DESIGN_APPROVED",
    "TASKS_READY",
    "RED_PROVEN",
    "IMPLEMENTING",
    "CONVERGED",
    "LANDED",
    "ARCHIVED",
)

# §5: «WITHDRAWN и SUPERSEDED — терминальные боковые состояния». Они лежат вне
# цепочки, поэтому шагом по ней не мерятся.
TERMINAL_SIDE_STATES = ("WITHDRAWN", "SUPERSEDED")

# §5 + §3: что обязано лежать в package на стадии, из которой шагают.
# Ключи — те же, которыми мир называет артефакты.
STAGE_REQUIRED_ARTIFACTS = {
    "DESIGN_APPROVED": (
        "acceptance",
        "design",
        "class-exposure-initial",
        "class-exposure-revalidation",
        "change-yaml",
        "holders-yaml",
    ),
}

# §4 + §5: какие вердикты связывает стадия, из которой шагают.
STAGE_REQUIRED_VERDICTS = {
    "DESIGN_APPROVED": ("acceptance", "design"),
}

# Закрытые метки присутствия и одобрения.
PRESENT_MARKER = "present"
APPROVED_VERDICT = "APPROVED"


def _registered_for_stage(table, stage, what):
    """Перечень стадии либо ГРОМКИЙ собственный отказ, а не тихая пустота.

    Стадия, которой в таблице нет, означает, что семейство не знает, что на ней
    обязано лежать. Ответить на это «нарушений нет» значило бы выдать «не знаю»
    за «нет» — то самое, что весь корпус запрещает.
    """
    if stage not in table:
        raise outcome.SelfFailure(
            outcome.SELF_WORLD_NOT_JUDGED,
            "перечень «%s» объявлен для стадий %s; стадия %r среди них не "
            "значится, поэтому судить её нечем"
            % (what, sorted(table), stage),
        )
    return table[stage]


def _required_artifact_missing(world):
    """На стадии не хватает объявленного ею артефакта.

    Читаются стадия (чей перечень применять) и весь набор артефактов целиком:
    вопрос «всё ли на месте» есть свойство набора, а не одной записи.
    """
    stage = world.read("stage")
    declared = world.read_all("required_artifacts")
    required = _registered_for_stage(
        STAGE_REQUIRED_ARTIFACTS, stage, "обязательные артефакты стадии"
    )
    return any(declared.get(name) != PRESENT_MARKER for name in required)


def _stage_verdict_not_approved(world):
    """Стадия связывает вердикт, которого нет либо который не одобрение."""
    stage = world.read("stage")
    declared = world.read_all("verdicts")
    required = _registered_for_stage(
        STAGE_REQUIRED_VERDICTS, stage, "обязательные вердикты стадии"
    )
    return any(declared.get(role) != APPROVED_VERDICT for role in required)


def _requested_transition_not_adjacent(world):
    """Запрошен шаг, который не является следующим в цепочке.

    Боковое терминальное состояние шагом по цепочке не является и потому этим
    правилом не судится. Стадия вне цепочки — собственный отказ: следующего у
    неё не существует, и «нарушения нет» было бы утверждением без основания.
    """
    stage = world.read("stage")
    requested = world.read("requested_transition")
    if requested in TERMINAL_SIDE_STATES:
        return False
    if stage not in LIFECYCLE_ORDER:
        raise outcome.SelfFailure(
            outcome.SELF_WORLD_NOT_JUDGED,
            "стадия %r не значится в объявленной цепочке %s; следующего шага у "
            "неё нет, поэтому смежность неизмерима"
            % (stage, list(LIFECYCLE_ORDER)),
        )
    position = LIFECYCLE_ORDER.index(stage)
    successor = (
        LIFECYCLE_ORDER[position + 1]
        if position + 1 < len(LIFECYCLE_ORDER)
        else None
    )
    return requested != successor


RULES = [
    Rule(
        rule_id="life.required-artifact-missing",
        diagnostic="CG_REQUIRED_ARTIFACT_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=("stage", "required_artifacts"),
        requires=("stage", "required_artifacts"),
        predicate=_required_artifact_missing,
        why="§5 переход запрещён, пока обязательный артефакт стадии не на "
            "месте; присутствие объявляется ровно одной закрытой меткой",
    ),
    Rule(
        rule_id="life.stage-verdict-not-approved",
        diagnostic="CG_LIFECYCLE_TRANSITION_INVALID",
        category=outcome.CATEGORY_RED,
        subject_keys=("stage", "verdicts"),
        requires=("stage", "verdicts"),
        predicate=_stage_verdict_not_approved,
        why="§5 переход запрещён при отсутствующем одобрении стадии: одобрение "
            "объявляется ровно одной закрытой меткой, всё прочее опоры не даёт",
    ),
    Rule(
        rule_id="life.transition-not-adjacent",
        diagnostic="CG_LIFECYCLE_TRANSITION_INVALID",
        category=outcome.CATEGORY_RED,
        subject_keys=("stage", "requested_transition"),
        requires=("stage", "requested_transition"),
        predicate=_requested_transition_not_adjacent,
        why="§5 цепочка стадий линейна: законен только следующий шаг, пропуск "
            "обязательной стадии отвергается",
    ),
]
