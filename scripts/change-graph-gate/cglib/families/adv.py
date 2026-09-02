"""cg.adv — advisory hook не является authority.

Приёмка §11, дословно: «Advisory hooks не являются authority и не заменяют любой
из четырёх callers». §13, SDD-1-ADV-01: «SUT возвращает GREEN только по
authoritative evidence».

Три кейса семейства доказывают это утверждение с трёх сторон сразу, и потому
предмет здесь ОДИН, а не два: advisory GREEN при чистой authority даёт GREEN
(ADV-01) · advisory GREEN при найденном дефекте даёт RED, то есть advisory
НЕ СПАСАЕТ (ADV-02) · advisory снят вовсе при неизменной authority даёт GREEN,
то есть его отсутствие НЕ БЛОКИРУЕТ (ADV-03). Утверждение выполняется тогда и
только тогда, когда advisory outcome не входит в вычисление вердикта ни одним
знаком.

**Правило одно, и это решение, а не свёртка от лени.** Приёмка объявляет для
семейства РОВНО ОДНУ диагностику — `CG_AUTHORITATIVE_GATE_BLOCKED`, — потому что
здесь судится не «кого именно недостаёт» (это предмет cg.wire с его четырьмя
диагностиками), а «сложилась ли authoritative evidence целиком». Заводить
вторую диагностику нельзя: приёмка её не объявляет, и она осталась бы кодом без
пробы. Тот же довод, что записан в cg.boot про неделимое допущение.

**Advisory outcome ЧИТАЕТСЯ и отбрасывается ЯВНО.** Оба требования корпуса
действуют здесь одновременно и тянут в разные стороны: §11 требует, чтобы
advisory не участвовал в authority, а ядро — чтобы всякий факт предмета был
прочитан (непрочитанный факт делает вердикт заявлением шире осмотренного).
Явный отбор authoritative фактов — единственная форма, где выполнены оба:
advisory берётся из мира и в набор, формирующий вердикт, НЕ включается.
Молчаливое неучастие (не читать вовсе) выглядело бы так же, но означало бы
другое — «правило про него забыло», — и тогда ADV-03 проходил бы не потому, что
advisory не авторитетен, а потому, что его никто не смотрел. Различить эти два
состояния по зелёному вердикту нельзя ничем.

**Четверо вызывающих спрашиваются ПОИМЁННО, по своим координатам.** Отсюда
следует §11 «не заменяют любой из четырёх» by construction, а не проверкой:
никакая другая запись переписи, как бы она ни называлась — advisory hook в том
числе, — ни одного из четырёх требований не удовлетворяет. Координаты берутся из
cg.wire, где они объявлены по §11: второй список тех же четырёх адресов разошёлся
бы с первым молча, а сломанный импорт виден сразу и целиком.

**Отсутствие координаты и присутствие с чужим значением — одно состояние.**
Вызывающий, чья запись говорит не «valid-graph», valid graph не получал;
считать его получившим значило бы принять упоминание за исход.
"""

from .. import outcome
from ..rules import Rule
from .wire import PRODUCT_CI, PRODUCT_PRE_PUSH, WORKSPACE_CI, WORKSPACE_PRE_PUSH

FAMILY = "adv"

ADVISORY_HOOK_OUTCOME = "advisory_hook_outcome"
AUTHORITATIVE_CALLERS = "authoritative_callers"
GRAPH_FACTS = "graph_facts"

# §11: те же четыре blocking callers, что объявлены в cg.wire. Здесь
# спрашивается не «зовёт ли он гейт», а «что гейт ему ответил».
AUTHORITATIVE_CALLER_COORDINATES = (
    WORKSPACE_PRE_PUSH,
    WORKSPACE_CI,
    PRODUCT_PRE_PUSH,
    PRODUCT_CI,
)

VALID_GRAPH = "valid-graph"
FACT_OK = "ok"


def _authoritative_evidence(world):
    """Отбирает из мира ТОЛЬКО authoritative факты — и показывает отбор.

    Возвращает ПАРУ наборов, а не их объединение: у вызывающих и у graph facts
    свои словари ключей, и объединение молча потеряло бы запись при совпадении
    имени. Advisory outcome читается здесь же и ни в один из наборов НЕ
    попадает: см. врезку в шапке модуля о том, почему прочитать и отбросить
    явно — не то же самое, что не читать.
    """
    callers = world.read_all(AUTHORITATIVE_CALLERS)
    facts = world.read_all(GRAPH_FACTS)
    if world.has(ADVISORY_HOOK_OUTCOME):
        world.read(ADVISORY_HOOK_OUTCOME)
    return callers, facts


def _authority_blocked(world):
    """Сложилась ли authoritative evidence целиком и чисто.

    Обе половины вычисляются ДО складывания ответа: сокращённое вычисление
    оставило бы вторую координату непрочитанной, и краснота пришла бы от учёта
    фактов, а не от предиката.
    """
    callers, facts = _authoritative_evidence(world)
    callers_short = any(
        callers.get(coordinate) != VALID_GRAPH
        for coordinate in AUTHORITATIVE_CALLER_COORDINATES
    )
    facts_dirty = any(value != FACT_OK for value in facts.values())
    return callers_short or facts_dirty


RULES = [
    Rule(
        rule_id="adv.authoritative-evidence",
        diagnostic="CG_AUTHORITATIVE_GATE_BLOCKED",
        category=outcome.CATEGORY_RED,
        subject_keys=(ADVISORY_HOOK_OUTCOME, AUTHORITATIVE_CALLERS, GRAPH_FACTS),
        requires=(AUTHORITATIVE_CALLERS, GRAPH_FACTS),
        predicate=_authority_blocked,
        why="§11 advisory hooks не являются authority и не заменяют любой из "
            "четырёх callers; SDD-1-ADV-01 «GREEN только по authoritative "
            "evidence»",
    ),
]
