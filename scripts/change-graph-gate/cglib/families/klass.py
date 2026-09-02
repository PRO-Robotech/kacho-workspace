"""cg.class — обнажение классов: две durable записи и applicability mapping'а.

Приёмка §5 объявляет у class exposure ДВЕ разные durable записи, и это не
удвоение одной, а две разные привязки с разным сроком жизни:

    initial analysis      привязана к exact acceptance hash, хранит items
    revalidation          привязана к exact design hash, требует mapping'а

    «Изменение design инвалидирует только revalidation и downstream; initial
     history остаётся.»

Отсюда состав миров: мир кейса называет либо стадию initial, либо стадию
revalidation, и различает их состав координат, а не идентификатор кейса:

    acceptance_content_digest · records · initial_bound_acceptance_hash
    initial_role · initial_item_ids                        -> initial analysis

    design_content_digest · records · revalidation_bound_design_hash
    revalidation_role · exposure_items
    external_calls · async_paths · sentinels               -> revalidation

**Четыре последние координаты — предмет именно этого семейства, и это надо
сказать прямо.** Тот же мир судит и cg.hash — там предметом объявлена только
привязка отпечатков, поэтому `exposure_items`, `external_calls`, `async_paths`
и `sentinels` в его переписи стоят строкой «вне предмета». Если бы их не читало
и это семейство, они не были бы прочитаны НИКЕМ, а вердикт о mapping'е выносился
бы, не взглянув на то, что маппится. §5 перечисляет источники обнажения
дословно: «Новый external call, async path либо sentinel является новым exposure
item и требует mapping + revalidation» — по одному правилу и по одной
диагностике на источник, как их объявляет приёмка.

**Зарегистрированный состав: что здесь константа и почему.** До cutover
versioned applicability registry (`docs/changes/policy.yaml`, §5) не существует —
он появляется вместе с ним. Поэтому состав initial items у единственного
bootstrap change зарегистрирован здесь, ровно как `cglib/families/boot.py`
регистрирует состав его допуска. Константа НЕ выписана из одной fixture: она
скрепляет обе стадии — мир стадии initial объявляет тот же состав полем
`initial_item_ids`, и правило `class.initial-record` сверяет его с ней. Ошибись
константа — покраснел бы и положительный кейс стадии initial, то есть у неё есть
контроль, а не одна сторона.

**Предикат снятия константы назван:** как только applicability registry
существует, состав items читается из самой initial-записи, и `REGISTERED_*`
уходит вместе с bootstrap exception (§4: «с момента cutover bootstrap exception
недействителен»).

Порядок объявления идёт от находки, содержащей в себе последующие, к частной:
отсутствующая запись делает бессмысленным вопрос о её привязке, устаревшая
привязка — вопрос о том, что по ней смаплено.
"""

from .. import outcome
from ..rules import Rule

# Имя модуля — `klass`, потому что `class` в Python зарезервировано; семейство
# при этом называется `class`, как того требует идентификатор кейса
# `SDD-1-CLASS-NN`. Имя семейства объявляется здесь, а не выводится из имени
# файла, — и это то самое место, где вывод из имени был бы неверен.
FAMILY = "class"

# §5: обе durable записи ведёт ОДНА и та же class-exposure role.
CLASS_EXPOSURE_ROLE = "class-exposure-analyst"

INITIAL_RECORD_KEY = "class-exposure-initial"
REVALIDATION_RECORD_KEY = "class-exposure-revalidation"

# Зарегистрированный состав initial items единственного bootstrap change.
# Скрепляет обе стадии: стадия initial объявляет его полем `initial_item_ids`,
# стадия revalidation обязана смапить каждый из них в design decision.
REGISTERED_INITIAL_ITEM_IDS = ("exposure-1", "exposure-2")

# §5: источник обнажения считается покрытым, только если он смаплен. Пустое
# значение обязано означать «пусто», поэтому словарь отсутствия назван явно, а
# не угадывается по правдоподобию строки.
MAPPED = "mapped"
ABSENT_MARKERS = (None, "", "none", "unmapped", "—")


def _absent(value):
    return value in ABSENT_MARKERS


def _declared_item_ids(raw):
    """Состав items, объявленный записью. Перечень через запятую."""
    if isinstance(raw, (list, tuple)):
        parts = [str(item).strip() for item in raw]
    else:
        parts = [part.strip() for part in str(raw or "").split(",")]
    return tuple(part for part in parts if part)


def _unmapped_sources(sources):
    """Источники обнажения, не имеющие mapping'а."""
    return [name for name, state in sources.items() if state != MAPPED]


def _initial_record_not_registered(world):
    """Initial analysis отсутствует либо это не та запись, что зарегистрирована.

    Предикат — сверка ЗАЯВЛЕННОЙ записи с зарегистрированной, а не конъюнкция
    трёх проверок с тремя диагностиками, двух из которых приёмка не объявляет.
    Запись, ведённая другой ролью либо назвавшая другой состав items, — это не
    повреждённая initial analysis, а её отсутствие: зарегистрированной среди
    объявленного нет.
    """
    records = world.read_all("records")
    role = world.read("initial_role")
    item_ids = _declared_item_ids(world.read("initial_item_ids"))
    return (
        not records.get(INITIAL_RECORD_KEY)
        or role != CLASS_EXPOSURE_ROLE
        or item_ids != REGISTERED_INITIAL_ITEM_IDS
    )


def _initial_binding_stale(world):
    """Initial analysis привязана к отпечатку, который уже не acceptance."""
    digest = world.read("acceptance_content_digest")
    bound = world.read("initial_bound_acceptance_hash")
    return bound != digest


def _revalidation_record_missing(world):
    """Revalidation отсутствует либо ведена не class-exposure role."""
    records = world.read_all("records")
    role = world.read("revalidation_role")
    return not records.get(REVALIDATION_RECORD_KEY) or role != CLASS_EXPOSURE_ROLE


def _revalidation_binding_stale(world):
    """Design изменён после revalidation: привязка указывает на прежний design."""
    digest = world.read("design_content_digest")
    bound = world.read("revalidation_bound_design_hash")
    return bound != digest


def _item_not_mapped(world):
    """Хотя бы один зарегистрированный item не смаплен в design decision.

    §5 требует exact mapping КАЖДОГО item'а, поэтому предикат перебирает
    зарегистрированный состав, а не заглядывает в таблицу mapping'а: снятая
    строка таблицы и строка с пустым значением — одно и то же отсутствие
    mapping'а, и обе обязаны находиться одинаково.
    """
    mapping = world.read_all("exposure_items")
    return any(
        _absent(mapping.get(item)) for item in REGISTERED_INITIAL_ITEM_IDS
    )


def _new_external_call(world):
    return bool(_unmapped_sources(world.read_all("external_calls")))


def _new_async_path(world):
    return bool(_unmapped_sources(world.read_all("async_paths")))


def _new_sentinel(world):
    return bool(_unmapped_sources(world.read_all("sentinels")))


INITIAL_KEYS = (
    "acceptance_content_digest", "records", "initial_bound_acceptance_hash",
    "initial_role", "initial_item_ids",
)
REVALIDATION_KEYS = (
    "design_content_digest", "records", "revalidation_bound_design_hash",
    "revalidation_role",
)

RULES = [
    Rule(
        rule_id="class.initial-record",
        diagnostic="CG_CLASS_INITIAL_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=INITIAL_KEYS,
        requires=("records", "initial_role", "initial_item_ids"),
        predicate=_initial_record_not_registered,
        why="§5 initial analysis — durable запись class-exposure role, хранящая "
            "items; объявлена раньше правила о привязке, потому что у "
            "отсутствующей записи привязки нет вовсе",
    ),
    Rule(
        rule_id="class.initial-binding",
        diagnostic="CG_CLASS_INITIAL_STALE",
        category=outcome.CATEGORY_RED,
        subject_keys=INITIAL_KEYS,
        requires=("acceptance_content_digest", "initial_bound_acceptance_hash"),
        predicate=_initial_binding_stale,
        why="§5 initial analysis связывается с exact acceptance hash; правка "
            "acceptance делает прежнюю привязку устаревшей",
    ),
    Rule(
        rule_id="class.revalidation-record",
        diagnostic="CG_CLASS_REVALIDATION_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=REVALIDATION_KEYS,
        requires=("records", "revalidation_role"),
        predicate=_revalidation_record_missing,
        why="§5 перед DESIGN_APPROVED тот же class-exposure role revalidate-ит "
            "design; объявлена раньше остальных правил стадии, потому что без "
            "записи ни привязка, ни mapping не существуют",
    ),
    Rule(
        rule_id="class.revalidation-binding",
        diagnostic="CG_CLASS_REVALIDATION_STALE",
        category=outcome.CATEGORY_RED,
        subject_keys=REVALIDATION_KEYS,
        requires=("design_content_digest", "revalidation_bound_design_hash"),
        predicate=_revalidation_binding_stale,
        why="§5 изменение design инвалидирует revalidation и downstream, "
            "сохраняя initial history; DESIGN_APPROVED запрещён при stale "
            "revalidation",
    ),
    Rule(
        rule_id="class.item-mapping",
        diagnostic="CG_CLASS_ITEM_UNMAPPED",
        category=outcome.CATEGORY_RED,
        subject_keys=("exposure_items",),
        requires=("exposure_items",),
        predicate=_item_not_mapped,
        why="§5 revalidation происходит после exact mapping каждого item → "
            "design decision; DESIGN_APPROVED запрещён при unmapped exposure",
    ),
    Rule(
        rule_id="class.external-call",
        diagnostic="CG_CLASS_NEW_EXTERNAL_CALL",
        category=outcome.CATEGORY_RED,
        subject_keys=("external_calls",),
        requires=("external_calls",),
        predicate=_new_external_call,
        why="§5 новый external call является новым exposure item и требует "
            "mapping + revalidation",
    ),
    Rule(
        rule_id="class.async-path",
        diagnostic="CG_CLASS_NEW_ASYNC_PATH",
        category=outcome.CATEGORY_RED,
        subject_keys=("async_paths",),
        requires=("async_paths",),
        predicate=_new_async_path,
        why="§5 новый async path является новым exposure item и требует "
            "mapping + revalidation",
    ),
    Rule(
        rule_id="class.sentinel",
        diagnostic="CG_CLASS_NEW_SENTINEL",
        category=outcome.CATEGORY_RED,
        subject_keys=("sentinels",),
        requires=("sentinels",),
        predicate=_new_sentinel,
        why="§5 новый sentinel является новым exposure item и требует "
            "mapping + revalidation",
    ),
]
