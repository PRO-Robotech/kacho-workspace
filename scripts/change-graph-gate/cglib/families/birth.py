"""cg.birth — доказательство рождения держателя.

Приёмка §7, дословно: «До eligibility каждый machine holder проходит birth
inversion: 1. known-good input даёт ожидаемый pass; 2. однофактный injected
defect даёт ожидаемый RED; 3. zero census не может дать GREEN».

**Ради чего это вообще существует.** Держатель, который никогда не падал,
неотличим от держателя, который падать НЕ УМЕЕТ. Оба молчат, у обоих переписи
одинаково зелёные, и разницу между ними нельзя увидеть чтением кода — только
подачей входа. Поэтому «рождение» здесь не метафора: держатель считается
существующим лишь после того, как показал ОБА своих исхода на объявленных
входах.

**Различают их ровно два правила, и ни одно поодиночке не различает:**

| что проверяется | что отсекает | что пропустило бы поодиночке |
|---|---|---|
| known-good даёт pass | держателя, отвергающего всё | держателя, принимающего всё |
| однофактный дефект даёт RED | держателя, принимающего всё | держателя, отвергающего всё |

Односторонняя проба зеленела бы на испытуемом, который отвергает вообще любой
вход, — то есть доказывала бы способность падать, ничего не говоря о
способности пройти. Поэтому оба правила объявлены отдельно, оба обязательны, и
ни одно не выводится из другого.

**Третье правило — про запись, а не про прогон.** Прогоны могли состояться, а
перепись их не покрыть; тогда GREEN опирается на то, чего в записи нет.
Нулевая перепись — предельный случай этого, а не отдельное явление: у неё
покрытых прогонов ноль. Отсюда предикат сравнивает ОХВАТ переписи с числом
объявленных прогонов, а не с нулём, — иначе перепись из одного прогона при двух
объявленных проходила бы молча.

**Почему читается версия держателя.** Рождение — свойство ТОЧНОЙ версии, а не
имени: перепись из двух прогонов, не отнесённая ни к какой версии, считает
прогоны ничьи. Вердикт GREEN над такой переписью утверждает о держателе,
которого перепись не называет.

**Объявленный порядок:** сперва оба правила о самих прогонах, затем правило о
записи. Причина: дефектный прогон делает GREEN неверным независимо от того,
посчитала его перепись или нет, — то есть находка о прогоне не зависит от
находки о записи, а обратное неверно.
"""

from .. import outcome
from ..rules import Rule

FAMILY = "birth"

SUBJECT_KEYS = ("holder_version", "birth_runs", "census_entry_count",
                "birth_verdict")
REQUIRES = SUBJECT_KEYS

# Имена объявленных прогонов рождения. Они же — координаты мира.
RUN_KNOWN_GOOD = "known-good-input"
RUN_INJECTED_DEFECT = "one-fact-injected-defect"

PASS_OUTCOME = "GREEN"
FAIL_OUTCOME = "RED"
GREEN_VERDICT = "GREEN"

ABSENT_MARKERS = (None, "", "none", "—")


def _absent(value):
    if value in ABSENT_MARKERS:
        return True
    return isinstance(value, str) and not value.strip()


def _known_good_did_not_pass(world):
    """Держатель обязан ПРОЙТИ на заведомо годном входе.

    Без этого «краснеет на дефекте» доказывало бы лишь то, что держатель
    краснеет вообще на всём.
    """
    return world.read("birth_runs.%s" % RUN_KNOWN_GOOD) != PASS_OUTCOME


def _injected_defect_was_not_detected(world):
    """Держатель обязан ПОКРАСНЕТЬ на однофактном дефекте.

    Без этого «проходит на годном входе» доказывало бы лишь то, что держатель
    зелен вообще на всём, — то есть ровно ту неотличимость, ради которой
    рождение и заведено.
    """
    return world.read("birth_runs.%s" % RUN_INJECTED_DEFECT) != FAIL_OUTCOME


def _census_does_not_cover_the_runs(world):
    """GREEN обязан опираться на перепись, покрывающую объявленные прогоны.

    Читается всё: версия (чьи прогоны считают), сам набор прогонов (сколько их
    объявлено), охват переписи и вынесенный вердикт. Чтение идёт ДО развилки,
    поэтому перепись мира не зависит от того, какой веткой пошёл предикат.
    """
    version = world.read("holder_version")
    runs = world.read_all("birth_runs")
    covered = world.read("census_entry_count")
    verdict = world.read("birth_verdict")

    if verdict != GREEN_VERDICT:
        # Предмет правила — GREEN поверх неполной записи. Не-GREEN вердикт
        # ничего не утверждает и находкой этого правила не является.
        return False
    if _absent(version):
        # Перепись считает прогоны ничьи: держателя, о котором вердикт, нет.
        return True
    return covered < len(runs)


RULES = [
    Rule(
        rule_id="birth.known-good-failed",
        diagnostic="CG_BIRTH_GOOD_INPUT_FAILED",
        category=outcome.CATEGORY_RED,
        subject_keys=SUBJECT_KEYS,
        requires=REQUIRES,
        predicate=_known_good_did_not_pass,
        why="§7 birth inversion п.1: known-good input даёт ожидаемый pass; без "
            "него способность краснеть не отличима от красноты на всём",
    ),
    Rule(
        rule_id="birth.defect-not-detected",
        diagnostic="CG_BIRTH_DEFECT_NOT_DETECTED",
        category=outcome.CATEGORY_RED,
        subject_keys=SUBJECT_KEYS,
        requires=REQUIRES,
        predicate=_injected_defect_was_not_detected,
        why="§7 birth inversion п.2: однофактный injected defect даёт ожидаемый "
            "RED; без него «держатель молчал» не отличимо от «не мог упасть»",
    ),
    Rule(
        rule_id="birth.census-does-not-cover-runs",
        diagnostic="CG_BIRTH_ZERO_CENSUS",
        category=outcome.CATEGORY_RED,
        subject_keys=SUBJECT_KEYS,
        requires=REQUIRES,
        predicate=_census_does_not_cover_the_runs,
        why="§7 birth inversion п.3: zero census не может дать GREEN; нулевая "
            "перепись — предельный случай непокрытых прогонов, а не отдельное "
            "явление, поэтому сравнивается охват, а не ноль",
    ),
]
