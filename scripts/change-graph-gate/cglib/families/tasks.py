"""cg.tasks — чем и после чего появляется tasks.md.

Приёмка §5, дословно: «DESIGN_APPROVED запрещён при TODO, TBD, open decision,
unmapped exposure, отсутствующем applicable review или stale revalidation.
После него обязательный writing-plans handoff производит tasks.md; затем
возможен TASKS_READY».

В одном предложении названы ДВА разных требования, и они чинятся по-разному:

* **порядок** — задачи появляются ПОСЛЕ утверждения design, а не до него;
* **производитель** — их производит объявленный writing-plans handoff, а не
  что попало; и производит он именно tasks.md.

## Объявленный порядок правил и почему он такой

Сперва порядок, потом производитель.

Handoff, состоявшийся до утверждения design, handoff'ом по §5 не является
вовсе: там сказано «после него», то есть утверждение — предпосылка, а не
соседнее условие. Поэтому находка о порядке содержит в себе находку о
производителе, а обратное неверно, и вердикт обязан назвать ту, которая
объясняет остальное.

## Событие и продукт — закрытые метки, а не «что-нибудь похожее»

Handoff признаётся состоявшимся по объявленному имени ПРОВЕРЕННОГО события и по
тому, что он произвёл именно tasks.md. Свободная строка на месте события
объявлением не является ровно по той же причине, по какой §5 отказывает
свободному тексту в роли evidence для N/A: имя события — координата, а не
доказательство, и незнакомое имя опоры не даёт.

Отсутствующее событие и событие с чужим именем — ОДНА находка: и в том и в
другом случае проверенного writing-plans handoff нет. Заводить им две
диагностики значило бы предъявлять одну находку дважды, а приёмка объявляет для
этого ровно одну.

## Чего это семейство НЕ судит — названо прямо

Смежность стадий (`DESIGN_APPROVED → TASKS_READY`), обязательные артефакты
стадии и её вердикты — предмет семейства жизненного цикла
(`CG_LIFECYCLE_TRANSITION_INVALID`, `CG_REQUIRED_ARTIFACT_MISSING`). Здесь
стадия design читается только как ПРЕДПОСЫЛКА появления задач, и вопрос «а
законен ли сам шаг цепочки» задаётся не тут — иначе завелось бы второе место об
одном предмете.
"""

from .. import outcome
from ..rules import Rule

FAMILY = "tasks"

SUBJECT_KEYS = ("design_stage", "handoff", "tasks_present")

# §5: задачи производятся только после утверждения design.
DESIGN_APPROVED_STAGE = "DESIGN_APPROVED"

# §5: обязательный writing-plans handoff и его продукт. Обе метки закрыты:
# значение вне метки объявлением состоявшегося handoff не является.
VERIFIED_HANDOFF_EVENT = "writing-plans-handoff-verified"
HANDOFF_PRODUCT = "tasks.md"


def _tasks_produced_before_design_approval(world):
    """Задачи уже есть, а design не утверждён.

    Читаются обе координаты: находка есть ОТНОШЕНИЕ между тем, что произведено,
    и тем, разрешено ли было производить. Ответ по одной из них был бы получен,
    не взглянув на вторую.
    """
    stage = world.read("design_stage")
    produced = world.read("tasks_present")
    return bool(produced) and stage != DESIGN_APPROVED_STAGE


def _verified_writing_plans_handoff_missing(world):
    """Проверенного writing-plans handoff, производящего tasks.md, нет.

    Запись handoff потребляется ЦЕЛИКОМ: она утверждает и событие, и его
    продукт, и обе половины входят в одну находку. Отсутствующее событие,
    событие с чужим именем и запись, произведшая не tasks.md, одинаково
    означают, что объявленного §5 производителя задач не было.
    """
    record = world.read_all("handoff")
    if record.get("event") != VERIFIED_HANDOFF_EVENT:
        return True
    return record.get("produces") != HANDOFF_PRODUCT


RULES = [
    Rule(
        rule_id="tasks.before-design-approval",
        diagnostic="CG_TASKS_BEFORE_DESIGN_APPROVAL",
        category=outcome.CATEGORY_RED,
        subject_keys=("design_stage", "tasks_present"),
        requires=("design_stage", "tasks_present"),
        predicate=_tasks_produced_before_design_approval,
        why="§5 задачи производятся ПОСЛЕ DESIGN_APPROVED; произведённые "
            "раньше опираются на design, который ещё могут не утвердить",
    ),
    Rule(
        rule_id="tasks.writing-plans-handoff-missing",
        diagnostic="CG_WRITING_PLANS_HANDOFF_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=("handoff",),
        requires=("handoff",),
        predicate=_verified_writing_plans_handoff_missing,
        why="§5 обязательный writing-plans handoff производит tasks.md; "
            "отсутствующее событие, чужое имя события и чужой продукт — одна "
            "находка: объявленного производителя задач не было",
    ),
]
