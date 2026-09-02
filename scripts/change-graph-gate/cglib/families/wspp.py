"""cg.wspp — workspace pre-push как authoritative caller.

Приёмка §11: «Pre-push читает remote/local SHAs из stdin и получает sibling
workspace/product coordinates. Missing required repo или required ref →
NOT_EXECUTED», плюс общее для всех вызывающих: «у каждого реального caller есть
one-fact injection: valid fixture проходит, тот же input с одним invalid Change
Graph fact блокируется».

Предметов ЧЕТЫРЕ, и они не пересекаются:

1. **назван ли sibling product** — репозиторий и координата, ПАРОЙ;
2. **дошёл ли remote SHA** — со stdin и до базы поданного диапазона;
3. **дошёл ли local SHA** — со stdin и до головы поданного диапазона;
4. **годен ли граф** — package tasks mapping.

**Правила 2 и 3 судят ДОРОГУ ссылки, а не только её наличие.** Pre-push
получает пару SHA из stdin и подаёт их гейту как base/head. Значит у каждой
ссылки два конца, и оба обязаны сойтись: ссылка, прочитанная со stdin, но не
доехавшая до диапазона, для гейта отсутствует ровно так же, как непрочитанная, —
он судил бы не тот диапазон и не знал бы об этом. Проверка «пришло == подано»
эту подмену находит; проверка одного наличия — нет.

**Идентичность репозитория входит в правило о remote-ссылке.** Ссылка без
названного репозитория не разрешается ни в каком: искать её негде. Приёмка не
объявляет для этого семейства диагностики о неназванном репозитории workspace
(объявлена только `CG_WORKSPACE_PRE_PUSH_PRODUCT_REPO_MISSING` — про СОСЕДА),
поэтому заводить свою нельзя: она осталась бы кодом без пробы. Цена названа
прямо: на мире без идентичности репозитория вердикт назовёт remote ref. Это
граница словаря приёмки, а не маска — факт прочитан и судим, тогда как умолчать
о нём было бы хуже: непрочитанный факт делает вердикт заявлением шире
осмотренного.

**Sibling product назван ПАРОЙ.** Репозиторий и координата — две половины одного
имени: caller, назвавший репозиторий без координаты, не сказал, где этот
репозиторий лежит, и sibling product для гейта не назван. Поэтому правило одно,
а не два: приёмка объявляет одну диагностику
(`CG_WORKSPACE_PRE_PUSH_PRODUCT_REPO_MISSING`, SDD-1-WSPP-03), и неделимость
предмета здесь не уступка словарю, а свойство самого предмета.

**Порядок объявлен и несущий: три NOT_EXECUTED, затем RED.** «Не выполнилось»
никогда не вычитается из вердикта и не подменяется красным (тот же довод, что у
cg.evid): push, чей вход не собрался, о графе не узнал ничего. Внутри тройки
порядок §11 — сперва required repo, затем required refs, и среди ссылок сперва
remote (пара stdin читается remote-первой).

**Каждое чтение безусловно.** Предикаты вычисляют ВСЕ величины и складывают
ответ последним действием: сокращённое вычисление оставило бы хвост координат
непрочитанным, и краснота пришла бы от учёта фактов, а не от предиката.
"""

from .. import outcome
from .. import tasksmapping
from ..rules import Rule

FAMILY = "wspp"

STDIN_REMOTE_SHA = "stdin_ref_line.remote_sha"
STDIN_LOCAL_SHA = "stdin_ref_line.local_sha"
WORKSPACE_REPO = "workspace.repo"
WORKSPACE_BASE_SHA = "workspace.base_sha"
WORKSPACE_HEAD_SHA = "workspace.head_sha"
SIBLING_PRODUCT_REPO = "sibling_product.repo"
SIBLING_PRODUCT_COORDINATE = "sibling_product.coordinate"
PACKAGE_TASKS_MAPPING = "package_tasks_mapping"

# Якорь семейства: координаты, чьё отсутствие означает «этот мир не о вызове
# workspace pre-push». Мир без них вердикта НЕ получает — ядро отвечает
# собственным отказом «мир не судим». Якорем взято то, что есть в КАЖДОМ мире
# семейства, включая дефектные, и чего нет у соседей: `workspace` отсутствует у
# миров product pre-push, `stdin_ref_line` — у миров workspace CI. Судимые
# координаты (sibling product, сами SHA, mapping) в якорь НЕ входят: иначе их
# снятие превращало бы находку в собственный отказ, то есть «нет» в «не знаю».
FAMILY_ANCHOR = ("workspace", "stdin_ref_line")


def _value(world, coordinate):
    """Значение координаты либо пустая строка, если её не назвали.

    Отсутствие ключа и присутствие с пустым значением — ОДНО состояние: caller,
    приславший пустую строку, координаты не назвал.
    """
    if not world.has(coordinate):
        return ""
    return str(world.read(coordinate)).strip()


def _product_repo_missing(world):
    """§11: pre-push получает sibling product coordinates — репо И координату."""
    repository = _value(world, SIBLING_PRODUCT_REPO)
    coordinate = _value(world, SIBLING_PRODUCT_COORDINATE)
    return not (repository and coordinate)


def _remote_ref_missing(world):
    """§11: remote SHA прочитан со stdin и доехал до базы поданного диапазона."""
    repository = _value(world, WORKSPACE_REPO)
    remote_sha = _value(world, STDIN_REMOTE_SHA)
    base_sha = _value(world, WORKSPACE_BASE_SHA)
    return not (repository and remote_sha and remote_sha == base_sha)


def _local_ref_missing(world):
    """§11: local SHA прочитан со stdin и доехал до головы поданного диапазона."""
    local_sha = _value(world, STDIN_LOCAL_SHA)
    head_sha = _value(world, WORKSPACE_HEAD_SHA)
    return not (local_sha and local_sha == head_sha)


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
        rule_id="wspp.product-repo",
        diagnostic="CG_WORKSPACE_PRE_PUSH_PRODUCT_REPO_MISSING",
        category=outcome.CATEGORY_NOT_EXECUTED,
        subject_keys=("sibling_product",),
        requires=FAMILY_ANCHOR,
        predicate=_product_repo_missing,
        why="§11 pre-push получает sibling product coordinates; missing "
            "required repo → NOT_EXECUTED",
    ),
    Rule(
        rule_id="wspp.remote-ref",
        diagnostic="CG_PRE_PUSH_REMOTE_REF_MISSING",
        category=outcome.CATEGORY_NOT_EXECUTED,
        subject_keys=("stdin_ref_line", "workspace"),
        requires=FAMILY_ANCHOR,
        predicate=_remote_ref_missing,
        why="§11 pre-push читает remote SHA из stdin; missing required ref → "
            "NOT_EXECUTED",
    ),
    Rule(
        rule_id="wspp.local-ref",
        diagnostic="CG_PRE_PUSH_LOCAL_REF_MISSING",
        category=outcome.CATEGORY_NOT_EXECUTED,
        subject_keys=("stdin_ref_line", "workspace"),
        requires=FAMILY_ANCHOR,
        predicate=_local_ref_missing,
        why="§11 pre-push читает local SHA из stdin; missing required ref → "
            "NOT_EXECUTED",
    ),
    Rule(
        rule_id="wspp.graph-defect",
        diagnostic="CG_TRACE_ID_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=(PACKAGE_TASKS_MAPPING,),
        requires=FAMILY_ANCHOR,
        predicate=_graph_lost_acceptance_id,
        why="§11 one-fact injection: тот же input с одним invalid Change Graph "
            "fact блокируется; §9 потерянный downstream acceptance ID — RED",
    ),
]
