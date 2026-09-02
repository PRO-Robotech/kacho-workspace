"""Сверка ПОЛОС одной диагностики между собой, а не по каждой отдельно.

`architecture.md` §«Параллельные полосы одного механизма обязаны сверяться
МЕЖДУ СОБОЙ»: свойство, обязательное для одной полосы, проверяется **сравнением
полос**, а не пробой каждой. Проба каждой полосы требует знать, каким свойство
ДОЛЖНО быть, — а это и есть спорный вопрос. Сравнение спрашивает другое:
**решал ли кто-нибудь, что полосы различаются.**

## Предмет: одна диагностика, разные миры

`CG_TRACE_ID_MISSING` производят ШЕСТЬ правил в ПЯТИ семействах, и миры у них
структурно разные. Единицы счёта названы, потому что они дают разные числа и
уже разошлись однажды:

| единица счёта | сколько | предикат |
|---|---:|---|
| кейсов, называющих диагностику | **6** | `grep -l CG_TRACE_ID_MISSING tests/testdata/*/case.yaml` |
| из них с предикатом семейства за спиной | **5** | те же минус `SDD-1-DRIVER-02`, чей SUT застаблен (`sut_stub`) |
| правил, производящих диагностику | **6** | `lanes()` ниже, обходом реестра |
| семейств-производителей | **5** | оно же, по `family` |
| КЛАССОВ мира | **3** | оно же, по `world_class()` |

Числа сняты на дереве этой рабочей копии и ПЕРЕМЕРЯЮТСЯ прогоном самого
модуля (`python3 selftest/laneparity.py`): он печатает перепись, а не эту
таблицу, поэтому расхождение между ними видно числом.

## Класс мира ВЫВОДИТСЯ из правила, а не объявляется списком

Класс — это отсортированный набор координат, о которых правило судит
(`Rule.subject_keys`). Рукописная таблица «семейство -> класс» была бы вторым
местом об одном предмете и разошлась бы с деревом молча; здесь класс берётся
у самого правила, поэтому новое семейство попадает в перепись само.

Различает полосы ровно то, что назвал разбор: у трассы эталонный набор
идентификаторов приёмки лежит В МИРЕ (`acceptance_ids`), поэтому сравнение
множеств прямое; у вызывающих эталона в мире нет ни одной координатой — там
лежит только перечень задач package. Это и есть два разных класса, и разные
предикаты у них законны.

## Что здесь находка

1. **класс произведён, но не объявлен** — новая полоса завела свой предикат под
   чужой диагностикой, и никто не решал, что он отличается;
2. **класс объявлен, но не производится** — запись ведомости, которой нечего
   объяснять; послабление обязано истекать само (`testing.md` §«Гейт на
   класс», п. 5);
3. **в классе две и более полосы, а корпуса сравнения нет** — сравнивать
   полосы нечем, то есть расхождение снова невидимо;
4. **корпус объявлен там, где полоса одна** — мёртвый корпус, тот же п. 5 с
   другой стороны;
5. **полосы одного класса разошлись** на входе корпуса — расхождение
   ВОЗНИКЛО, а не было решено.

Пятая находка называет вход и ответ КАЖДОЙ полосы: перечень имён без ответов
посылает читателя искать причину не там.

## Ответов у полосы ЧЕТЫРЕ, а не два

Полоса отвечает «находка», «молчит» либо **собственный отказ** — испытуемый не
понимает поданного. Схлопывание третьего во второй сделало бы сравнение слепым
ровно там, где оно нужнее всего: расхождение, найденное этим модулем при
заведении, было именно таким — на идентификаторе чужого change три реализации
дали три РАЗНЫХ ответа (отказ, находка, молчание).

Четвёртый — **поломка предиката**. Он не сводится ни к одному из трёх и
объявляется находкой сам по себе: полосы, упавшие ОДИНАКОВО, сравнение
проходят, потому что ответы у них совпали, — то есть поломка читалась бы как
согласие.

## Корпус сравнения ВЫВОДИТСЯ из дерева фикстур

Перечень входов не выписан: он собирается из идентификаторов кейсов приёмки,
разложенных по сериям текстовым отбрасыванием хвостового номера. Отбрасывание
намеренно НЕЙТРАЛЬНО — оно не пользуется грамматикой ни одной из сравниваемых
полос, иначе корпус подтверждал бы ту полосу, чью грамматику взял.

Ровно этот вывод и обнажил расхождение: серия `SDD-1-POST-NA` существует в
дереве, и три реализации разобрали её по-разному. Выписанный от руки корпус
такого входа не содержал бы — его придумать надо, а вывести достаточно.

Два входа корпуса вывести НЕЛЬЗЯ и они названы прямо: строка, не являющаяся
идентификатором кейса, и пустой перечень. Первого в дереве нет by construction
(фикстуры несут только годные идентификаторы), а он и есть тот вход, на котором
расходятся «не знаю» и «нет».
"""

import os
import sys

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
GATE_DIR = os.path.abspath(os.path.join(HERE, ".."))
TESTDATA = os.path.join(GATE_DIR, "tests", "testdata")

if GATE_DIR not in sys.path:
    sys.path.insert(0, GATE_DIR)

from cglib import outcome  # noqa: E402
from cglib import registry  # noqa: E402
from cglib import world as world_module  # noqa: E402

# Диагностика, чьи полосы сверяются. Одна на модуль намеренно: сверка есть
# отношение полос ОДНОГО имени, и складывать в неё вторую диагностику значило
# бы сравнивать несравнимое.
DIAGNOSTIC = "CG_TRACE_ID_MISSING"

ANSWER_FINDING = "находка"
ANSWER_SILENT = "молчит"
ANSWER_REFUSAL = "собственный отказ"
# Четвёртый ответ: предикат УПАЛ. Он не сводится ни к одному из трёх и
# объявляется находкой сам по себе — иначе четыре полосы, упавшие ОДИНАКОВО,
# читались бы как «расхождений нет», то есть поломка выдавалась бы за согласие.
ANSWER_BROKEN = "поломка предиката"

# Вход корпуса, который из дерева не выводится, и почему: фикстуры несут только
# годные идентификаторы, поэтому неразбираемой записи в них нет by
# construction — а она и есть тот вход, на котором расходятся «не знаю» и «нет».
UNPARSEABLE_ENTRY = "не идентификатор кейса"


class Lane(object):
    """Одна полоса: семейство, правило и предикат, которым оно судит."""

    __slots__ = ("family", "rule_id", "world_class", "predicate")

    def __init__(self, family, rule_id, world_class, predicate):
        self.family = family
        self.rule_id = rule_id
        self.world_class = world_class
        self.predicate = predicate

    def __repr__(self):
        return "<полоса %s>" % self.rule_id


class ClassEntry(object):
    """Объявленный класс мира: почему он ОТДЕЛЬНЫЙ и чем сравнивать его полосы.

    `corpus` — вызываемое, возвращающее перечень пар «имя входа, подстановка».
    Подстановка задаёт значения координат класса; всё остальное берётся из
    фикстуры семейства. `None` означает «полоса одна, сравнивать не с чем» — и
    если полос станет две, отсутствие корпуса будет находкой, а не тишиной.
    """

    __slots__ = ("why", "corpus")

    def __init__(self, why, corpus=None):
        self.why = why
        self.corpus = corpus


def series_of(case_id):
    """Серия кейса: всё до хвостового номера, ТЕКСТОВЫМ отбрасыванием.

    Грамматика сравниваемых полос здесь не применяется намеренно: корпус,
    собранный грамматикой одной из них, подтверждал бы именно её.
    """
    text = str(case_id)
    head, _, tail = text.rpartition("-")
    if not head or not tail.isdigit():
        return None
    return head


def declared_case_ids():
    """Идентификаторы кейсов приёмки — обходом дерева фикстур, не списком."""
    if not os.path.isdir(TESTDATA):
        raise outcome.SelfFailure(
            outcome.SELF_WORLD_MALFORMED,
            "дерева фикстур нет по пути %s — корпус сравнения выводить не из "
            "чего" % TESTDATA,
        )
    return sorted(
        name
        for name in os.listdir(TESTDATA)
        if os.path.isdir(os.path.join(TESTDATA, name))
    )


def mapping_corpus():
    """Корпус для класса «перечень задач package».

    На каждую серию дерева — две половины инверсии рождения: полная пара
    (базовый кейс и производный) и один базовый. Плюс два входа, которые из
    дерева не выводятся: неразбираемая запись и пустой перечень.
    """
    series = {}
    for case_id in declared_case_ids():
        name = series_of(case_id)
        if name is None:
            continue
        series.setdefault(name, []).append(case_id)
    corpus = []
    for name in sorted(series):
        members = sorted(series[name])
        if len(members) < 2:
            # Серия из одного кейса пары не даёт: полная половина корпуса на
            # ней невыразима, и подавать её значило бы сравнивать полосы на
            # входе, который ни одна из них не обязана считать полным.
            continue
        pair = [members[0], members[1]]
        corpus.append(("полная пара серии %s" % name, list(pair)))
        corpus.append(("только базовый кейс серии %s" % name, [members[0]]))
    # Годная пара берётся ИЗ ДЕРЕВА, а не выписывается: выписанная пара была бы
    # единственным местом модуля, где предмет назван литералом, — и учила бы
    # следующего делать так же там, где это уже опасно.
    sound_pair = next(
        (value for name, value in corpus if name.startswith("полная пара")), []
    )
    corpus.append(("неразбираемая запись рядом с годной парой",
                   list(sound_pair) + [UNPARSEABLE_ENTRY]))
    corpus.append(("пустой перечень", []))
    return [
        (name, {"package_tasks_mapping": value}) for name, value in corpus
    ]


# Ведомость КЛАССОВ мира: почему класс отдельный и чем сравнивать его полосы.
#
# Ключ — отсортированный набор координат, о которых судит правило. Записи здесь
# ОБЪЯВЛЯЮТ решение: «эти полосы различаются, и вот почему». Класс, которого в
# ведомости нет, — находка: значит расхождение возникло, а не было решено.
LANE_CLASS_LEDGER = {
    ("package_tasks_mapping",): ClassEntry(
        why="вызывающий подаёт гейту перечень задач своего package'а, и "
            "эталонного набора acceptance ID в его мире нет НИ ОДНОЙ "
            "координатой: утверждение «удалён существующий кейс приёмки» по "
            "такому миру неразрешимо прямым сравнением множеств, и полосы "
            "судят внутренний инвариант перечня — покрытие обеих половин "
            "инверсии рождения",
        corpus=mapping_corpus,
    ),
    ("acceptance_ids", "design_ids", "evidence_plan_ids", "tasks_ids"):
        ClassEntry(
            why="эталонный набор идентификаторов приёмки лежит В МИРЕ, поэтому "
                "сравнение множеств прямое по §9; сужать этот предикат до "
                "инварианта перечня было бы потерей — он не отличает потерю "
                "объявленного ID от добавления чужого",
        ),
    ("acceptance_ids", "holders_for_id"): ClassEntry(
        why="полоса держателей: тот же эталон в мире, но судится прослеженность "
            "объявленного ID до держателя, а не совпадение нижележащих наборов",
    ),
}


def lanes(diagnostic=DIAGNOSTIC):
    """Полосы диагностики — обходом реестра, а не перечнем.

    Реестр собирается обходом каталога семейств, поэтому положенное туда
    семейство попадает в сверку само, а снятое — исчезает из неё само.
    """
    collected = []
    for family, rules in sorted(registry.load().items()):
        for rule in rules:
            if rule.diagnostic != diagnostic:
                continue
            collected.append(
                Lane(family, rule.rule_id, world_class(rule), rule.predicate)
            )
    return collected


def world_class(rule):
    """Класс мира правила: отсортированный набор судимых им координат."""
    return tuple(sorted(rule.subject_keys))


def _base_case_of(family):
    """Базовый кейс семейства — тот, чью фикстуру берут основой мира.

    Берётся ФИКСТУРА, а не выдуманный мир: предикат вызывающего читает и
    соседние координаты (якорь семейства, координаты ссылок), и мир без них
    заставил бы его отвечать о том, чего не подавали.
    """
    best = None
    for case_id in declared_case_ids():
        try:
            if registry.family_of(case_id) != family:
                continue
        except outcome.SelfFailure:
            continue
        if best is None or case_id < best:
            best = case_id
    if best is None:
        raise outcome.SelfFailure(
            outcome.SELF_WORLD_MALFORMED,
            "у семейства %s нет ни одной фикстуры — мир для сверки полос "
            "строить не из чего" % family,
        )
    return best


_FIXTURE_CACHE = {}


def _fixture_document(family):
    """Документ мира базового кейса семейства. Читается один раз на семейство.

    Кэш — про скорость, а не про смысл: без него один и тот же файл разбирался
    бы на каждый ответ (входов корпуса десятки, полос — единицы). Возвращаемое
    копируется вызывающим, поэтому подстановка кэш не портит.
    """
    if family not in _FIXTURE_CACHE:
        path = os.path.join(TESTDATA, _base_case_of(family), "world.yaml")
        with open(path, encoding="utf-8") as handle:
            _FIXTURE_CACHE[family] = yaml.safe_load(handle) or {}
    return _FIXTURE_CACHE[family]


def answer(lane, substitution):
    """Ответ полосы на подставленный вход.

    Исходов ЧЕТЫРЕ: находка, молчание, собственный отказ и поломка предиката.
    Первые три — то, что полоса СКАЗАЛА; четвёртый — то, что она сказать не
    смогла, и схлопывать его в остальные нельзя (почему — в шапке модуля).

    Документ фикстуры читается целиком, а не плоским перечнем фактов:
    предикаты берут контейнеры (`read_all`), и плоский перечень их бы не дал.
    """
    document = dict(_fixture_document(lane.family))
    document.update(substitution)
    world = world_module.World(document, path="<сверка полос>")
    try:
        return ANSWER_FINDING if lane.predicate(world) else ANSWER_SILENT
    except outcome.SelfFailure as failure:
        return "%s (%s)" % (ANSWER_REFUSAL, failure.diagnostic)
    except Exception as error:  # noqa: BLE001 — поломка тоже ответ, см. выше
        return "%s (%s: %s)" % (ANSWER_BROKEN, type(error).__name__, error)


def answer_table(class_lanes, corpus):
    """Ответы всех полос класса на всех входах корпуса — ОДНИМ проходом.

    Возвращает перечень `(имя входа, {правило: ответ})` по КАЖДОМУ входу, а не
    только по разошедшимся: разные находки читают эту таблицу по-разному
    (расхождение — по числу различных ответов, поломка — по виду ответа), и
    второй проход означал бы второй вызов предиката на том же входе.
    """
    table = []
    for name, substitution in corpus:
        answers = {}
        for lane in class_lanes:
            answers[lane.rule_id] = answer(lane, substitution)
        table.append((name, answers))
    return table


def disagreements(class_lanes, corpus):
    """Входы, на которых полосы одного класса ответили ПО-РАЗНОМУ.

    Ответ каждой полосы назван: перечень имён без ответов посылает читателя
    искать причину не там.
    """
    return [
        (name, answers)
        for name, answers in answer_table(class_lanes, corpus)
        if len(set(answers.values())) > 1
    ]


def audit(diagnostic=DIAGNOSTIC, found_lanes=None, ledger=None):
    """Полная сверка: находки и перепись осмотренного.

    Возвращает `(findings, census)`. `findings` — перечень строк, каждая
    называет предмет находки. `census` — числа, по которым «находок ноль»
    отличимо от «осмотрено ноль».

    **`found_lanes` и `ledger` существуют ради СИНТЕТИКИ, и это надо сказать
    прямо.** Оба по умолчанию выводятся из дерева, и настоящий прогон их не
    подаёт. Но сверка — тоже гейт, и её собственная способность упасть обязана
    доказываться входом, а не прочтением: на настоящем дереве расхождения
    больше нет by construction (судья у вызывающих один), поэтому доказать
    красноту можно только поданными полосами. Подделка сюда не проходит: сверка
    зовётся из `prove.py` без аргументов, а с аргументами — только из
    утверждений, которые ТРЕБУЮТ находки.
    """
    if found_lanes is None:
        found_lanes = lanes(diagnostic)
    if ledger is None:
        ledger = LANE_CLASS_LEDGER
    by_class = {}
    for lane in found_lanes:
        by_class.setdefault(lane.world_class, []).append(lane)

    findings = []
    compared_lanes = 0
    corpus_inputs = 0

    for world_class_key in sorted(by_class):
        entry = ledger.get(world_class_key)
        members = by_class[world_class_key]
        if entry is None:
            findings.append(
                "класс мира %s производит диагностику %s и НЕ объявлен в "
                "ведомости: расхождение предикатов возникло, а не было решено "
                "(полосы: %s)"
                % (list(world_class_key), diagnostic,
                   ", ".join(lane.rule_id for lane in members))
            )
            continue
        if len(members) > 1 and entry.corpus is None:
            findings.append(
                "класс мира %s несёт %d полос(ы), а корпуса сравнения не "
                "объявлено: сравнивать полосы между собой нечем"
                % (list(world_class_key), len(members))
            )
            continue
        if len(members) == 1 and entry.corpus is not None:
            findings.append(
                "класс мира %s объявил корпус сравнения при ОДНОЙ полосе: "
                "корпусу нечего сравнивать" % (list(world_class_key),)
            )
            continue
        if entry.corpus is None:
            continue
        corpus = entry.corpus()
        if not corpus:
            findings.append(
                "корпус класса %s пуст: сверка беспредметна"
                % (list(world_class_key),)
            )
            continue
        corpus_inputs += len(corpus)
        compared_lanes += len(members)
        for name, answers in answer_table(members, corpus):
            if len(set(answers.values())) > 1:
                findings.append(
                    "полосы класса %s РАЗОШЛИСЬ на входе «%s»: %s"
                    % (list(world_class_key), name,
                       "; ".join("%s -> %s" % (rule_id, answers[rule_id])
                                 for rule_id in sorted(answers)))
                )
            for rule_id in sorted(answers):
                if answers[rule_id].startswith(ANSWER_BROKEN):
                    findings.append(
                        "полоса %s УПАЛА на входе «%s»: %s — поломка не есть "
                        "согласие" % (rule_id, name, answers[rule_id])
                    )

    for world_class_key in sorted(ledger):
        if world_class_key not in by_class:
            findings.append(
                "класс мира %s объявлен в ведомости, а диагностику %s не "
                "производит ни одна полоса: записи нечего объяснять"
                % (list(world_class_key), diagnostic)
            )

    census = {
        "полос": len(found_lanes),
        "семейств": len({lane.family for lane in found_lanes}),
        "классов мира": len(by_class),
        "сравнено полос": compared_lanes,
        "входов корпуса": corpus_inputs,
        "находок": len(findings),
    }
    return findings, census


def census_line(census):
    return " · ".join("%s %d" % (key, census[key]) for key in (
        "полос", "семейств", "классов мира", "сравнено полос",
        "входов корпуса", "находок",
    ))


if __name__ == "__main__":
    result, numbers = audit()
    for line in result:
        sys.stdout.write("  НАХОДКА %s\n" % line)
    sys.stdout.write("=== перепись сверки полос ===\n%s\n"
                     % census_line(numbers))
    raise SystemExit(1 if result else 0)
