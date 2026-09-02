"""cg.pci — вызывающий на стороне продукта: чем он располагает и что он доказал.

Приёмка §11 и раздел «Authoritative callers и advisory hooks»: CI продукта —
один из четырёх блокирующих вызывающих. Он берёт change_id и pinned
workspace_revision из product ledger, ФЕТЧИТ публичный workspace на этой
ревизии, берёт product base/head из GitHub event и на этом исполняет гейт.

**Категория ответа выбирается по тому, ЧТО ИЗВЕСТНО, а не по тяжести.** Это то
же различение трёх исходов, что несёт весь корпус. Недоступный fetch,
нерезолвящаяся pinned-ревизия и отсутствующий product base — это отсутствие
УСЛОВИЯ исполнения: вердикта нет ни о чём, и такой исход отвечает
NOT_EXECUTED. Ledger без change_id и незакрытая пара кейсов — вердикты о
предмете, RED. Свести первое ко второму значило бы выдать «не знаю» за «нет».

**Отсюда объявленный порядок правил, и он назван, потому что вердикт берётся по
первому нарушению.** Сперва три условия исполнения, в порядке зависимости —
нельзя резолвить ревизию в workspace, который не сфетчен, и нельзя считать diff
без его начала; затем два вердикта о предмете, где ledger идёт раньше трассы:
ledger называет, КАКОЙ change судится, и без этого имени вопрос о покрытии его
acceptance-кейсов задан ни о чём.

**Отсутствие судится чтением ЗАПИСИ целиком, а не координаты.** Координаты,
которой нет, не прочитать: `read` по ней — собственный отказ испытуемого, а не
вердикт. Поэтому правило о ledger берёт ledger как запись и спрашивает, что она
называет; так же поступает правило о GitHub event. Обратная сторона названа
прямо: такое чтение покрывает и соседний лист записи, поэтому каждое из этих
правил обязано этот лист ПОТРЕБЛЯТЬ, а не просто задеть, — что оба и делают
(ledger сверяется на именование обеих своих величин, event — на то, что base и
head называют непустой интервал).

**Про `CG_TRACE_ID_MISSING` — здесь самое существенное, и это надо сказать
прямо.** Приёмка требует (§9): acceptance ID set обязан exact-set совпасть с
design, tasks и evidence plan, а недостача — RED. В мире этого семейства
эталонного acceptance ID set НЕТ ни одной координатой: вызывающий резолвит его
из того самого workspace, который фетчит, — и именно поэтому недоступность
fetch'а стоит выше и отвечает NOT_EXECUTED. Что остаётся проверяемым по самому
package tasks mapping — свойство, которое §7 требует от КАЖДОГО machine holder:

    «До eligibility каждый machine holder проходит birth inversion:
     1) known-good input даёт ожидаемый pass;
     2) однофактный injected defect даёт ожидаемый RED.»

Значит tasks-пакет, доказывающий вызывающего, обязан покрывать ОБЕ половины
пары: базовый кейс серии и хотя бы один производный. Пакет, назвавший только
базовый, доказывает, что вызывающий пропускает, и НИЧЕГО не говорит о том, что
он блокирует; пакет без базового доказывает обратное и столь же наполовину.
Недостающая половина — существующий acceptance-кейс, не покрытый tasks, то есть
ровно `CG_TRACE_ID_MISSING` по §9.

Граница этого предиката названа, чтобы её не приняли за полноту: он ловит
НЕЗАКРЫТУЮ ПАРУ, а не произвольную недостачу из полного acceptance ID set —
последнее в этом мире невыразимо, потому что эталона в нём нет. Расширять
предикат чтением дерева нельзя: полный набор кейсов приёмки содержит все 196
идентификаторов, и пакет одного вызывающего не покрывает и не обязан покрывать
их все.

**Судья при этом ОДИН на все четыре вызывающих семейства, и своей копии здесь
нет.** Инвариант выше — общий для WSPP, WSCI, PPRE и PCI, а исполняет его
`tasksmapping.lost_acceptance_id` в единственном экземпляре. Причина измерена, а
не предположена: четыре независимые реализации одного инварианта были заведены
и разошлись, причём прежняя ЗДЕШНЯЯ копия расходилась с остальными по двум осям
сразу — разбору идентификатора и ответу на неразбираемую запись, — и обе
разницы были невидимы. Довод, числа замера и границы инварианта — в шапке
общего судьи; здесь они не пересказываются, чтобы два места об одном предмете
снова не разошлись. Сверку полос между собой ведёт `selftest/laneparity.py`.
"""

from .. import outcome
from .. import tasksmapping
from ..rules import Rule

FAMILY = "pci"

# Ledger продукта: какой change судится и на какой ревизии workspace.
LEDGER = "product_ledger"
# Исход фетча публичного workspace и резолва запиненной ревизии.
FETCH = "workspace_fetch"
# Координаты product-диффа, приходящие из GitHub event.
EVENT = "github_event"
# Перечень acceptance-кейсов, покрытых задачами пакета.
MAPPING = "package_tasks_mapping"

SUBJECT_KEYS = (LEDGER, FETCH, EVENT, MAPPING)

AVAILABLE = "available"

ABSENT_MARKERS = (None, "", "none", "—")


def _absent(value):
    if value in ABSENT_MARKERS:
        return True
    return isinstance(value, str) and not value.strip()


def _workspace_fetch_unavailable(world):
    """Публичный workspace не сфетчен — исполнять гейт не на чем.

    Судится ЗНАЧЕНИЕ исхода, а не наличие ключа: запись, стоящая в мире с любым
    исходом, кроме «доступен», доступности не сообщает, и считать её доступной
    значило бы принять упоминание за факт.
    """
    return world.read(FETCH + ".outcome") != AVAILABLE


def _pinned_revision_unavailable(world):
    """Запиненная ledger'ом ревизия workspace не резолвится.

    Читаются обе стороны отношения: сам пин (его называет ledger) и исход его
    резолва. Ревизии, которой ledger не называет, резолвиться нечему — этот
    случай назван отдельной веткой, потому что «пина нет» и «пин не резолвится»
    для вызывающего означают одно: политики, на которой он обязан работать, у
    него нет.
    """
    resolves = world.read(FETCH + ".revision_resolves")
    if not world.has(LEDGER + ".workspace_revision"):
        return True
    pin = world.read(LEDGER + ".workspace_revision")
    return _absent(pin) or resolves != AVAILABLE


def _base_ref_missing(world):
    """GitHub event не называет начала product-диффа.

    Event читается ЗАПИСЬЮ целиком: отсутствие координаты нельзя прочитать по
    её координате, а сравнить начало с концом — можно только имея оба. Обе его
    величины потребляются: интервал, у которого начало совпало с концом, начала
    не называет так же, как интервал без начала вовсе.

    Про отсутствие ГОЛОВЫ это правило намеренно молчит: приёмка не объявляет
    для него диагностики в этом семействе, а заводить свою значило бы завести
    код, которого не предъявит ни один кейс.
    """
    event = world.read_all(EVENT)
    base = event.get("base_sha")
    if _absent(base):
        return True
    return base == event.get("head_sha")


def _ledger_change_id_missing(world):
    """Ledger продукта не называет судимый change.

    Ledger читается записью целиком по той же причине: правило судит ОТСУТСТВИЕ
    имени, а отсутствующую координату не прочитать. Вторая величина записи —
    пин ревизии — этим же чтением потребляется: ledger обязан назвать обе, и
    именно поэтому он читается как запись, а не как одно поле.
    """
    ledger = world.read_all(LEDGER)
    return _absent(ledger.get("change_id"))


def _tasks_mapping_leaves_case_uncovered(world):
    """Package tasks mapping не покрывает существующий acceptance-кейс.

    Судья ОБЩИЙ на все четыре вызывающих семейства
    (`tasksmapping.lost_acceptance_id`) — своей копии инварианта здесь нет
    намеренно, и почему, сказано в шапке модуля числами замера.

    Перечень читается целиком: покрытие — свойство набора, а не записи.
    Отсутствие перечня — тоже непокрытие, а не чистота: §7 прямо запрещает
    vacuous GREEN на пакете с нулём acceptance IDs.
    """
    if not world.has(MAPPING):
        return True
    return tasksmapping.lost_acceptance_id(world.read_all(MAPPING))


RULES = [
    Rule(
        rule_id="pci.workspace-fetch-unavailable",
        diagnostic="CG_PRODUCT_CI_WORKSPACE_FETCH_UNAVAILABLE",
        category=outcome.CATEGORY_NOT_EXECUTED,
        subject_keys=(FETCH,),
        requires=(FETCH + ".outcome",),
        predicate=_workspace_fetch_unavailable,
        why="§11 product CI исполняет гейт из публичного workspace; без фетча "
            "условия исполнения нет, и это отсутствие вердикта, а не вердикт",
    ),
    Rule(
        rule_id="pci.workspace-revision-unavailable",
        diagnostic="CG_PRODUCT_CI_WORKSPACE_REVISION_UNAVAILABLE",
        category=outcome.CATEGORY_NOT_EXECUTED,
        subject_keys=(FETCH, LEDGER),
        requires=(FETCH + ".revision_resolves",),
        predicate=_pinned_revision_unavailable,
        why="§11 workspace берётся на ЗАПИНЕННОЙ ревизии; нерезолвящийся пин "
            "оставляет вызывающего без политики, на которой он обязан работать",
    ),
    Rule(
        rule_id="pci.base-ref-missing",
        diagnostic="CG_PRODUCT_CI_BASE_REF_MISSING",
        category=outcome.CATEGORY_NOT_EXECUTED,
        subject_keys=(EVENT,),
        requires=(EVENT,),
        predicate=_base_ref_missing,
        why="§8 authoritative caller передаёт repo identity, base и head; без "
            "начала интервала diff не вычисляется, эвристика начального "
            "коммита запрещена",
    ),
    Rule(
        rule_id="pci.ledger-change-id-missing",
        diagnostic="CG_PRODUCT_LEDGER_CHANGE_ID_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=(LEDGER,),
        requires=(LEDGER,),
        predicate=_ledger_change_id_missing,
        why="§11 product ledger называет судимый change; ledger без change_id "
            "не адресует ни одного change и вердиктом о нём быть не может",
    ),
    Rule(
        rule_id="pci.tasks-mapping-pair-incomplete",
        diagnostic="CG_TRACE_ID_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=(MAPPING,),
        requires=(MAPPING,),
        predicate=_tasks_mapping_leaves_case_uncovered,
        why="§9 acceptance ID set обязан exact-set совпасть с tasks, недостача "
            "даёт RED; §7 требует от machine holder обеих половин birth "
            "inversion, поэтому незакрытая пара серии и есть непокрытый "
            "существующий acceptance-кейс",
    ),
]
