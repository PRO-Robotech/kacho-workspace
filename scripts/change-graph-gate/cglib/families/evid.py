"""cg.evid — доказательства: их наличие, годность и адресат.

Приёмка §7: «У required holder ровно один captured outcome: GREEN, RED или
NOT_EXECUTED. Missing output → NOT_EXECUTED». Приёмка §9: acceptance ID set
обязан exact-set совпасть с evidence plan, а «orphan» — RED.

Отсюда у семейства ДВА предмета, и они не пересекаются:

1. **агрегация исходов держателей** — что зафиксировано у тех, кого запускали;
2. **адресат плана доказательств** — не запланировано ли доказательство тому,
   чего никто не требовал.

**Категория ответа выбрана не по тяжести, а по тому, ЧТО известно.** Это то же
различение трёх исходов, что несёт весь корпус: «держатель ответил RED» —
вердикт о предмете; «держателя не исполнили» и «вывода держателя нет» —
ОТСУТСТВИЕ вердикта, и они отвечают NOT_EXECUTED, а не RED. Свести их к RED
значило бы выдать «не знаю» за «нет».

**Отсутствующий вывод и негодное происхождение — одна находка.** Вывод, чьё
происхождение не подтверждено, не является захваченным выводом: опереться на
него нельзя ровно так же, как на отсутствующий. Поэтому оба случая ведут к
`CG_REQUIRED_HOLDER_OUTPUT_MISSING`, а не заводят вторую диагностику, которой
приёмка не объявляет. Туда же попадает исход вне закрытой тройки: значение,
не являющееся ни GREEN, ни RED, ни NOT_EXECUTED, — не captured outcome.

**Порядок объявлен и несущий:** сперва «вывода нет», затем «не исполнили»,
затем «ответил RED». Держатель без вывода не имеет исхода вовсе, поэтому судить
его объявленный исход значило бы судить утверждение без подтверждения; а
NOT_EXECUTED стоит раньше RED, потому что «не выполнилось» никогда не
вычитается из вердикта и не подменяется красным.

**Чего это семейство НЕ судит — сказано прямо, чтобы предмет не размывался.**
`design_ids` и `tasks_ids` того же мира судит семейство трассы: их сверка с
acceptance — его предмет, и второе место об одном предмете разошлось бы с
первым молча. `driver_birth` — носитель фактической тройки самого драйвера, он
принадлежит birth-цепочке драйвера, а не доказательствам держателей. Оба
названы переписью поимённо, поэтому «не судим» здесь видно, а не подразумевается.

**Сирота ищется только в плане доказательств, и это односторонняя проверка.**
Обратная сторона — ID, который acceptance требует, а план не покрывает, —
принадлежит семейству трассы (`CG_TRACE_ID_MISSING`); заводить её здесь значило
бы объявить диагностику, которую в этом семействе не предъявит ни один кейс.
"""

from .. import outcome
from ..rules import Rule

FAMILY = "evid"

# Предмет 1: исходы держателей. Предмет 2: адресат плана доказательств.
OUTCOME_KEYS = ("required_holders", "captured_outputs", "provenance")
PLAN_KEYS = ("acceptance_ids", "evidence_plan_ids")

# §7: закрытая тройка захваченных исходов. Значение вне её captured outcome'ом
# не является.
CAPTURED_OUTCOMES = ("GREEN", "RED", "NOT_EXECUTED")
OUTCOME_RED = "RED"
OUTCOME_NOT_EXECUTED = "NOT_EXECUTED"

VALID_PROVENANCE = "valid"

ABSENT_MARKERS = (None, "", "none", "—")


def _absent(value):
    if value in ABSENT_MARKERS:
        return True
    return isinstance(value, str) and not value.strip()


def _holders_without_usable_output(world):
    """Держатели, на чей вывод опереться нельзя.

    Читаются ВСЕ три отображения: предмет правила — отношение между тем, кого
    требовали, что он оставил и откуда это взялось. Ответ «у всех всё на месте»,
    полученный по одному из трёх, был бы получен не глядя на остальные два.
    """
    holders = world.read_all("required_holders")
    outputs = world.read_all("captured_outputs")
    provenance = world.read_all("provenance")

    unusable = []
    for name in sorted(holders):
        if _absent(outputs.get(name)):
            unusable.append(name)
        elif provenance.get(name) != VALID_PROVENANCE:
            unusable.append(name)
        elif holders[name] not in CAPTURED_OUTCOMES:
            unusable.append(name)
    return unusable


def _output_missing(world):
    return bool(_holders_without_usable_output(world))


def _holder_not_executed(world):
    """Хотя бы один требуемый держатель не был исполнен.

    Читается набор требуемых держателей целиком: вопрос «есть ли среди них
    неисполненный» есть свойство набора, а не одной записи.
    """
    holders = world.read_all("required_holders")
    return any(value == OUTCOME_NOT_EXECUTED for value in holders.values())


def _holder_red(world):
    holders = world.read_all("required_holders")
    return any(value == OUTCOME_RED for value in holders.values())


def _evidence_plan_has_orphan(world):
    """План доказательств адресован тому, чего acceptance не требует.

    Оба набора читаются целиком: сирота есть отношение множеств, и по одной
    записи оно не решается.
    """
    required = world.read_all("acceptance_ids")
    planned = world.read_all("evidence_plan_ids")
    return bool([item for item in planned if item not in set(required)])


RULES = [
    Rule(
        rule_id="evid.output-missing",
        diagnostic="CG_REQUIRED_HOLDER_OUTPUT_MISSING",
        category=outcome.CATEGORY_NOT_EXECUTED,
        subject_keys=OUTCOME_KEYS,
        requires=OUTCOME_KEYS,
        predicate=_output_missing,
        why="§7 missing output -> NOT_EXECUTED; вывод без подтверждённого "
            "происхождения и исход вне закрытой тройки опоры не дают так же, "
            "как отсутствующий",
    ),
    Rule(
        rule_id="evid.holder-not-executed",
        diagnostic="CG_REQUIRED_HOLDER_NOT_EXECUTED",
        category=outcome.CATEGORY_NOT_EXECUTED,
        subject_keys=OUTCOME_KEYS,
        requires=OUTCOME_KEYS,
        predicate=_holder_not_executed,
        why="§7 captured outcome NOT_EXECUTED — отсутствие вердикта, а не "
            "красный вердикт; «не выполнилось» не вычитается и не подменяется",
    ),
    Rule(
        rule_id="evid.holder-red",
        diagnostic="CG_REQUIRED_HOLDER_RED",
        category=outcome.CATEGORY_RED,
        subject_keys=OUTCOME_KEYS,
        requires=OUTCOME_KEYS,
        predicate=_holder_red,
        why="§7 captured outcome RED у требуемого держателя даёт RED агрегата",
    ),
    Rule(
        rule_id="evid.plan-orphan",
        diagnostic="CG_TRACE_ID_ORPHAN",
        category=outcome.CATEGORY_RED,
        subject_keys=PLAN_KEYS,
        requires=PLAN_KEYS,
        predicate=_evidence_plan_has_orphan,
        why="§9 acceptance ID set обязан exact-set совпасть с evidence plan; "
            "orphan даёт RED. Обратная сторона (ID acceptance без плана) — "
            "предмет семейства трассы и здесь не дублируется",
    ),
]
