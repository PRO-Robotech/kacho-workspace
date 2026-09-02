"""cg.wsci — workspace CI как authoritative caller.

Приёмка §11: «Workspace callers передают repo identity/base/head и sibling
product coordinates», «Missing required repo или required ref → NOT_EXECUTED», и
«у каждого реального caller есть one-fact injection: valid fixture проходит, тот
же input с одним invalid Change Graph fact блокируется».

Отсюда у семейства ТРИ предмета, и они не пересекаются:

1. **названа ли координата соседнего репозитория продукта** — без неё job'у
   нечего сверять, и это НЕ ВЫПОЛНИЛОСЬ, а не находка о графе;
2. **разрешается ли поданный диапазон изменения** — идентичность репозитория,
   обе метки и их резолвинг; тоже «не выполнилось»;
3. **годен ли граф, поданный caller'ом** — package tasks mapping; вот это
   находка о предмете, и caller обязан её СОХРАНИТЬ, а не проглотить
   (SDD-1-WSCI-02 ждёт underlying `CG_TRACE_ID_MISSING`).

**Порядок объявлен и несущий: сперва оба NOT_EXECUTED, потом RED.** Причина та
же, что у cg.evid: «не выполнилось» никогда не вычитается из вердикта и не
подменяется красным. Job, которому не назвали координату либо не разрешили
ссылку, о графе не узнал НИЧЕГО, и объявлять его граф негодным значило бы выдать
«не знаю» за «нет». Внутри пары NOT_EXECUTED порядок идёт от того, что caller
называет сам, к тому, что он получает резолвингом: координата соседа приходит из
окружения job'а, а разрешение ссылок — уже обращение к репозиторию.

**Каждое чтение безусловно.** Предикаты вычисляют ВСЕ свои величины и лишь потом
складывают ответ: сокращённое вычисление (`and`, обрывающее цепочку) оставило бы
хвост координат непрочитанным, и ядро ответило бы собственным отказом
«факт не прочитан» — то есть краснота пришла бы от учёта фактов, а не от
предиката.

> [!important] Граница словаря приёмки названа прямо, чтобы её не приняли за маску
> Приёмка объявляет для этого семейства РОВНО ОДНУ диагностику о неразрешённой
> ссылке — `CG_WORKSPACE_CI_BASE_REF_UNAVAILABLE` (SDD-1-WSCI-04), — и НИ ОДНОЙ
> о неназванной идентичности репозитория либо о неразрешённой head. Поэтому
> предмет правила о диапазоне неделим: диапазон разрешается целиком либо не
> разрешается. Завести вторую диагностику нельзя — приёмка её не объявляет, и
> такая диагностика осталась бы кодом без пробы (контракт модуля семейства).
> Цена решения: на мире, где не разрешается head, вердикт назовёт base. Это
> ограничение словаря, а не послабление проверки: факт прочитан и СУДИМ, тогда
> как умолчать о нём было бы хуже — непрочитанный факт делает вердикт
> заявлением шире осмотренного. Появится в приёмке отдельная диагностика —
> правило расщепится вместе с ней.
"""

from .. import outcome
from .. import tasksmapping
from ..rules import Rule

FAMILY = "wsci"

WORKSPACE_REPO = "workspace.repo"
WORKSPACE_BASE_SHA = "workspace.base_sha"
WORKSPACE_HEAD_SHA = "workspace.head_sha"
SIBLING_PRODUCT_COORDINATE = "sibling_product_coordinate"
REF_LOOKUP_BASE = "ref_lookup.base"
REF_LOOKUP_HEAD = "ref_lookup.head"
PACKAGE_TASKS_MAPPING = "package_tasks_mapping"

# §11: ссылка считается полученной, только если lookup её РАЗРЕШИЛ. Всякое
# другое значение — то же самое состояние, что её отсутствие: сверять нечего.
REF_AVAILABLE = "available"

# Якорь семейства: координаты, чьё отсутствие означает «этот мир не о вызове
# workspace CI». Мир без них вердикта НЕ получает — ядро отвечает собственным
# отказом «мир не судим», потому что «правил не нашлось» и «нарушений не
# найдено» разные вещи. Якорем взято то, что есть в КАЖДОМ мире семейства,
# включая дефектные, и чего нет у соседей: `workspace` отсутствует у миров
# product-вызывающих, `ref_lookup` — у миров workspace pre-push. Судимые
# координаты (координата соседа, сами ссылки, mapping) в якорь НЕ входят: иначе
# их снятие превращало бы находку в собственный отказ, то есть «нет» в «не знаю».
FAMILY_ANCHOR = ("workspace", "ref_lookup")


def _named(world, coordinate):
    """Названа ли координата непустым значением.

    Отсутствие ключа и присутствие с пустым значением — ОДНО состояние: caller,
    приславший пустую строку, координаты не назвал. Тот же довод, что у cg.wire
    про «упоминание не есть вызов».
    """
    if not world.has(coordinate):
        return False
    return bool(str(world.read(coordinate)).strip())


def _lookup_resolves(world, coordinate):
    """Разрешил ли lookup ссылку по этой координате."""
    if not world.has(coordinate):
        return False
    return str(world.read(coordinate)).strip() == REF_AVAILABLE


def _product_coordinate_missing(world):
    """§11: workspace caller передаёт sibling product coordinates."""
    return not _named(world, SIBLING_PRODUCT_COORDINATE)


def _change_range_unresolved(world):
    """§11: repo identity/base/head, и обе ссылки обязаны разрешиться.

    Величины вычисляются ВСЕ до складывания ответа — см. врезку о безусловном
    чтении в шапке модуля.
    """
    repository_named = _named(world, WORKSPACE_REPO)
    base_named = _named(world, WORKSPACE_BASE_SHA)
    head_named = _named(world, WORKSPACE_HEAD_SHA)
    base_resolves = _lookup_resolves(world, REF_LOOKUP_BASE)
    head_resolves = _lookup_resolves(world, REF_LOOKUP_HEAD)
    return not (
        repository_named
        and base_named
        and head_named
        and base_resolves
        and head_resolves
    )


def _graph_lost_acceptance_id(world):
    """§9 + §11: поданный caller'ом граф потерял acceptance ID.

    Отсутствующий mapping — тоже потеря, а не чистота: приёмка §7 запрещает
    vacuous GREEN на нулевой переписи.
    """
    if not world.has(PACKAGE_TASKS_MAPPING):
        return True
    return tasksmapping.lost_acceptance_id(
        world.read_all(PACKAGE_TASKS_MAPPING)
    )


RULES = [
    Rule(
        rule_id="wsci.product-coordinate",
        diagnostic="CG_WORKSPACE_CI_PRODUCT_COORDINATE_MISSING",
        category=outcome.CATEGORY_NOT_EXECUTED,
        subject_keys=(SIBLING_PRODUCT_COORDINATE,),
        requires=FAMILY_ANCHOR,
        predicate=_product_coordinate_missing,
        why="§11 workspace callers передают sibling product coordinates; "
            "missing required repo → NOT_EXECUTED",
    ),
    Rule(
        rule_id="wsci.change-range",
        diagnostic="CG_WORKSPACE_CI_BASE_REF_UNAVAILABLE",
        category=outcome.CATEGORY_NOT_EXECUTED,
        subject_keys=("workspace", "ref_lookup"),
        requires=FAMILY_ANCHOR,
        predicate=_change_range_unresolved,
        why="§11 workspace callers передают repo identity/base/head; "
            "missing required ref → NOT_EXECUTED",
    ),
    Rule(
        rule_id="wsci.graph-defect",
        diagnostic="CG_TRACE_ID_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=(PACKAGE_TASKS_MAPPING,),
        requires=FAMILY_ANCHOR,
        predicate=_graph_lost_acceptance_id,
        why="§11 one-fact injection: тот же input с одним invalid Change Graph "
            "fact блокируется; §9 потерянный downstream acceptance ID — RED",
    ),
]
