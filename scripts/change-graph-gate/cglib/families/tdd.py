"""cg.tdd — граница реализации: что разрешено до RED_PROVEN и чем он открывается.

Приёмка §6 задаёт три разных предмета, и мир кейса называет ровно один из них.
Различает их состав координат, а не идентификатор кейса:

    stage · test_diff_owner · harness_contains_implementation
    diff_paths · evidence_plan_present            -> допустимость pre-RED diff'а

    driver · initial_holder · captured_outcome    -> чем открывается RED_PROVEN

    acceptance_ids · stage · red_proof_valid      -> допустимость implementation

**Несущее различение семейства — честный красный против поломки.** §6 говорит
это дословно: отсутствие capability даёт `RED · CASE_CAPABILITY_MISSING · exit
10`, и «Command-not-found, unrelated driver crash и infrastructure failure не
подменяют его: они не открывают RED_PROVEN». То есть RED_PROVEN открывает не
«что-то красное», а **ровно та тройка, снятая с работающего seam'а**. Отсюда
форма правил: испытуемый не спрашивает «красно ли», он спрашивает про ЧЕТЫРЕ
независимых свойства записанного исхода, и каждое имеет свою диагностику:

| что не так с записанным исходом | диагностика |
|---|---|
| исход снят не с seam'а, а синтезирован драйвером | CG_TEST_HARNESS_MASKS_CAPABILITY |
| снятое — не честный красный, а посторонний отказ | CG_RED_PROOF_INFRA_FAILURE |
| категория оказалась GREEN | CG_RED_PROOF_UNEXPECTED_GREEN |
| категория оказалась NOT_EXECUTED | CG_RED_PROOF_NOT_EXECUTED |

Первое объявлено раньше остальных намеренно: синтезированный драйвером исход
**не является наблюдением вовсе**, поэтому спрашивать о его категории значило
бы судить выдумку. Второе раньше третьего и четвёртого по той же причине: если
снятое — посторонний crash, его категория не относится к предмету.

Диагностики «неверная triple вообще» приёмка не объявляет, поэтому её здесь и
нет: правило `tdd.red-proof-capture` судит диагностику и код записанного холдера
вместе с самим фактом захвата — это одно утверждение «снят честный acceptance
RED», а не три с двумя невыговариваемыми диагностиками.

Порядок жизненного цикла взят из §5 ДОСЛОВНО и не выводится из имени стадии:
«достигнут ли RED_PROVEN» есть вопрос о положении в объявленной
последовательности, и отвечать на него сравнением строк с одним значением
значило бы краснеть на IMPLEMENTING, где реализация уже разрешена.
"""

from .. import outcome
from ..rules import Rule

FAMILY = "tdd"

# §5, дословный порядок стадий. Перечень нужен целиком: вопрос правила — не
# «равна ли стадия RED_PROVEN», а «достигнут ли RED_PROVEN», и после него
# идут ещё четыре стадии, на которых реализация законна.
LIFECYCLE = (
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
RED_PROVEN_STAGE = "RED_PROVEN"
# Стадии, на которых RED_PROVEN уже достигнут. Стадия вне перечня — в том числе
# рабочее «pre-RED» — означает «не достигнут»: закрытость множества здесь
# намеренная, иначе неизвестное имя стадии молча открывало бы реализацию.
STAGES_WITH_RED_PROVEN = frozenset(
    LIFECYCLE[LIFECYCLE.index(RED_PROVEN_STAGE):]
)

# §6: pre-RED test diff принадлежит integration-tester, и его собственный
# артефакт — evidence plan. Владелец без своего артефакта не «объявлен», а не
# подтверждён: §13 SDD-1-TDD-10 спрашивает про VERIFIED owner.
TEST_DIFF_OWNER = "integration-tester"

# §6: классификация пути в diff'е. Значение говорит, ЧЕМ является путь, поэтому
# запрет «независимо от пути» выражается предикатом над значением, а не над
# именем каталога.
IMPLEMENTATION_KIND = "implementation"

# §6: честный acceptance RED — ровно эта тройка, снятая со стабильного seam'а.
HONEST_RED_DIAGNOSTIC = "CASE_CAPABILITY_MISSING"
HONEST_RED_EXIT = 10
HONEST_RED_CAPTURE = "holder-red-capability-missing"

STABLE_SEAM = "stable"


def _red_proven_reached(stage):
    return stage in STAGES_WITH_RED_PROVEN


def _pre_red_diff_carries_implementation(world):
    """До RED_PROVEN ни один путь diff'а не вправе быть implementation.

    Читается ВЕСЬ diff целиком: запрет §6 звучит «независимо от пути», то есть
    предмет правила — множество путей, а не одна подозрительная запись. И
    читается ДО решения о стадии, а не после: короткое замыкание на достигнутом
    RED_PROVEN оставило бы факты diff'а непрочитанными, и вердикт стал бы
    заявлением шире осмотренного.
    """
    stage = world.read("stage")
    declared = world.read("harness_contains_implementation")
    paths = world.read_all("diff_paths")
    carries = bool(declared) or any(
        kind == IMPLEMENTATION_KIND for kind in paths.values()
    )
    return carries and not _red_proven_reached(stage)


def _pre_red_owner_not_verified(world):
    """Владелец pre-RED diff'а подтверждён СВОИМ артефактом, а не именем.

    Evidence plan — артефакт integration-tester (§6, §12). Объявленное имя
    владельца без него есть самодекларация, а §4 прямо говорит, что
    самодекларация authority не даёт.

    Стадия читается вместе с остальным и НЕ замыкает предикат накоротко: см.
    разбор в правиле выше.
    """
    stage = world.read("stage")
    owner = world.read("test_diff_owner")
    evidence_plan = world.read("evidence_plan_present")
    unverified = owner != TEST_DIFF_OWNER or not evidence_plan
    return unverified and not _red_proven_reached(stage)


def _capture_is_masked(world):
    """Исход синтезирован драйвером, а не снят со стабильного seam'а.

    Читается весь driver: маскировка — свойство ТРАКТА получения исхода, а не
    одного флажка, и «seam нестабилен» маскирует ровно так же, как «triple
    синтезирована».
    """
    driver = world.read_all("driver")
    return (
        bool(driver.get("synthesizes_expected_triple"))
        or driver.get("seam") != STABLE_SEAM
        or not driver.get("assertion_valid")
    )


def _capture_is_not_the_honest_red(world):
    """Снятое — не честный acceptance RED, а посторонний отказ.

    §6 перечисляет подменыши поимённо: command-not-found, unrelated driver
    crash, infrastructure failure. Общее у них не категория, а то, что снятое
    НЕ ЕСТЬ тройка отсутствующей capability, — поэтому судится и захват, и
    диагностика с кодом, а не одна лишь категория (её судят правила ниже).
    """
    captured = world.read("captured_outcome")
    diagnostic = world.read("initial_holder.diagnostic")
    exit_code = world.read("initial_holder.exit")
    return (
        captured != HONEST_RED_CAPTURE
        or diagnostic != HONEST_RED_DIAGNOSTIC
        or exit_code != HONEST_RED_EXIT
    )


def _capture_category_is_green(world):
    return world.read("initial_holder.category") == outcome.CATEGORY_GREEN


def _capture_category_is_not_executed(world):
    return world.read("initial_holder.category") == outcome.CATEGORY_NOT_EXECUTED


def _implementation_without_red_proof(world):
    """Реализация появилась там, где валидного RED_PROVEN нет.

    Три условия, и все три — одно утверждение §6 «после валидного RED_PROVEN
    implementation разрешён; до него — RED»: acceptance set должен быть непуст
    (пустой обход не есть доказательство, §7), доказательство — валидным, а
    стадия — достигшей RED_PROVEN.
    """
    acceptance_ids = world.read_all("acceptance_ids")
    proof_valid = world.read("red_proof_valid")
    stage = world.read("stage")
    return (
        not acceptance_ids
        or not proof_valid
        or not _red_proven_reached(stage)
    )


PRE_RED_DIFF_KEYS = (
    "stage", "test_diff_owner", "harness_contains_implementation",
    "diff_paths", "evidence_plan_present",
)
RED_PROOF_KEYS = ("driver", "initial_holder", "captured_outcome")
IMPLEMENTATION_KEYS = ("acceptance_ids", "stage", "red_proof_valid")

RULES = [
    Rule(
        rule_id="tdd.harness-implementation",
        diagnostic="CG_TEST_HARNESS_CONTAINS_IMPLEMENTATION",
        category=outcome.CATEGORY_RED,
        subject_keys=PRE_RED_DIFF_KEYS,
        requires=("stage", "harness_contains_implementation", "diff_paths"),
        predicate=_pre_red_diff_carries_implementation,
        why="§6 harness, содержащий либо маскирующий implementation, запрещён "
            "независимо от пути; до RED_PROVEN implementation diff даёт RED",
    ),
    Rule(
        rule_id="tdd.diff-owner",
        diagnostic="CG_TEST_DIFF_OWNER_INVALID",
        category=outcome.CATEGORY_RED,
        subject_keys=PRE_RED_DIFF_KEYS,
        requires=("stage", "test_diff_owner", "evidence_plan_present"),
        predicate=_pre_red_owner_not_verified,
        why="§6 tests/** и fixtures до RED_PROVEN назначены integration-tester; "
            "§4 самодекларация роли без своего артефакта authority не даёт",
    ),
    Rule(
        rule_id="tdd.harness-masks-capability",
        diagnostic="CG_TEST_HARNESS_MASKS_CAPABILITY",
        category=outcome.CATEGORY_RED,
        subject_keys=RED_PROOF_KEYS,
        requires=RED_PROOF_KEYS,
        predicate=_capture_is_masked,
        why="§6 masked capability даёт holder RED; синтезированный драйвером "
            "исход не есть наблюдение, поэтому объявлен раньше правил о самом "
            "исходе — иначе судилась бы выдумка",
    ),
    Rule(
        rule_id="tdd.red-proof-capture",
        diagnostic="CG_RED_PROOF_INFRA_FAILURE",
        category=outcome.CATEGORY_RED,
        subject_keys=RED_PROOF_KEYS,
        requires=RED_PROOF_KEYS,
        predicate=_capture_is_not_the_honest_red,
        why="§6 command-not-found, unrelated crash и infrastructure failure не "
            "подменяют честный acceptance RED и не открывают RED_PROVEN; "
            "объявлено раньше правил о категории, потому что у постороннего "
            "отказа категория к предмету не относится",
    ),
    Rule(
        rule_id="tdd.red-proof-unexpected-green",
        diagnostic="CG_RED_PROOF_UNEXPECTED_GREEN",
        category=outcome.CATEGORY_RED,
        subject_keys=RED_PROOF_KEYS,
        requires=RED_PROOF_KEYS,
        predicate=_capture_category_is_green,
        why="§6 unexpected SUT GREEN даёт holder RED и не открывает RED_PROVEN",
    ),
    Rule(
        rule_id="tdd.red-proof-not-executed",
        diagnostic="CG_RED_PROOF_NOT_EXECUTED",
        category=outcome.CATEGORY_RED,
        subject_keys=RED_PROOF_KEYS,
        requires=RED_PROOF_KEYS,
        predicate=_capture_category_is_not_executed,
        why="§6 NOT_EXECUTED не есть acceptance RED: «не выполнилось» не "
            "вычитается из вердикта и не открывает RED_PROVEN",
    ),
    Rule(
        rule_id="tdd.implementation-before-red",
        diagnostic="CG_IMPLEMENTATION_BEFORE_RED",
        category=outcome.CATEGORY_RED,
        subject_keys=IMPLEMENTATION_KEYS,
        requires=IMPLEMENTATION_KEYS,
        predicate=_implementation_without_red_proof,
        why="§6 implementation diff разрешён после валидного RED_PROVEN, до "
            "него — RED; §5 порядок стадий читается по объявленному "
            "жизненному циклу, а не по имени стадии",
    ),
]
