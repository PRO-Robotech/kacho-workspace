"""cg.wire — провязка: кто вызывает гейт и откуда.

Приёмка §11: blocking callers ровно ЧЕТЫРЕ, по два на репозиторий —

    workspace   scripts/hooks/pre-push            .github/workflows/ci.yaml
    product     project/kacho/scripts/hooks/pre-push
                project/kacho/.github/workflows/ci.yaml

**Правил тоже четыре, а не одно.** Соблазн свернуть их в равенство множеств
(как это сделано в cg.boot, где предмет — одно неделимое допущение) здесь
неверен: приёмка объявляет ЧЕТЫРЕ РАЗНЫЕ диагностики, по одной на вызывающего,
и вердикт обязан называть, КОГО именно недостаёт. Свёрнутое правило ответило бы
«набор не тот» — и оператору пришлось бы искать пропажу самому.

**Отсутствие и присутствие-без-вызова — одно состояние.** Координата, стоящая
в переписи со значением, отличным от «зовёт гейт», гейта не вызывает; считать
её вызывающей значило бы принять упоминание за вызов. Поэтому предикат судит
ЗНАЧЕНИЕ, а не наличие ключа.

**Advisory hook не подменяет ни одного из четверых** — by construction, а не
проверкой: каждое правило спрашивает СВОЮ координату, поэтому никакая другая
запись переписи, как бы она ни называлась, ни одно из четырёх требований не
удовлетворяет.

Порядок объявления — порядок §11 (workspace pre-push, workspace CI, product
pre-push, product CI). Он назван, потому что на мире, где недостаёт двоих,
вердикт берётся по первому, и брать его в порядке случайном значило бы менять
диагностику от перестановки строк в файле.
"""

from .. import outcome
from ..rules import Rule

FAMILY = "wire"

BLOCKING_CALLERS = "blocking_callers"
CALLS_GATE = "calls-gate"

WORKSPACE_PRE_PUSH = "workspace/scripts/hooks/pre-push"
WORKSPACE_CI = "workspace/.github/workflows/ci.yaml"
PRODUCT_PRE_PUSH = "project/kacho/scripts/hooks/pre-push"
PRODUCT_CI = "project/kacho/.github/workflows/ci.yaml"


def _caller_absent(coordinate):
    """Предикат «этого вызывающего нет», замкнутый на его координате."""

    def predicate(world):
        declared = world.read_all(BLOCKING_CALLERS)
        return declared.get(coordinate) != CALLS_GATE

    return predicate


RULES = [
    Rule(
        rule_id="wire.workspace-pre-push",
        diagnostic="CG_CALLER_WORKSPACE_PRE_PUSH_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=(BLOCKING_CALLERS,),
        requires=(BLOCKING_CALLERS,),
        predicate=_caller_absent(WORKSPACE_PRE_PUSH),
        why="§11 blocking caller: workspace scripts/hooks/pre-push",
    ),
    Rule(
        rule_id="wire.workspace-ci",
        diagnostic="CG_CALLER_WORKSPACE_CI_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=(BLOCKING_CALLERS,),
        requires=(BLOCKING_CALLERS,),
        predicate=_caller_absent(WORKSPACE_CI),
        why="§11 blocking caller: workspace .github/workflows/ci.yaml",
    ),
    Rule(
        rule_id="wire.product-pre-push",
        diagnostic="CG_CALLER_PRODUCT_PRE_PUSH_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=(BLOCKING_CALLERS,),
        requires=(BLOCKING_CALLERS,),
        predicate=_caller_absent(PRODUCT_PRE_PUSH),
        why="§11 blocking caller: product project/kacho/scripts/hooks/pre-push",
    ),
    Rule(
        rule_id="wire.product-ci",
        diagnostic="CG_CALLER_PRODUCT_CI_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=(BLOCKING_CALLERS,),
        requires=(BLOCKING_CALLERS,),
        predicate=_caller_absent(PRODUCT_CI),
        why="§11 blocking caller: product project/kacho/.github/workflows/ci.yaml",
    ),
]
