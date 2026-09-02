"""cg.ppre — product pre-push как вызывающий: координаты, отказ и блокировка.

Приёмка §11 объявляет product `project/kacho/scripts/hooks/pre-push` одним из
четырёх blocking callers, а §13 (SDD-1-PPRE-01..04) описывает, ЧТО именно этот
вызывающий обязан сделать с гейтом:

    PPRE-01  читает remote/local SHAs из stdin, получает sibling workspace с
             pinned policy -> валидный push проходит
    PPRE-02  дефект графа -> push блокируется exit 10, и underlying диагностика
             гейта СОХРАНЯЕТСЯ, а не подменяется своей
    PPRE-03  нет sibling workspace repo -> NOT_EXECUTED, push блокируется
    PPRE-04  нет local SHA во входной строке -> NOT_EXECUTED, push блокируется

**Отсюда два РАЗНЫХ вида отказа, и путать их нельзя.** Отсутствие координаты —
это «гейт не может быть запущен»: вердикта о графе нет, и произносить его
значило бы выдать «не знаю» за «нет». Дефект графа — это вердикт о графе, и он
RED. Приёмка различает их категорией (NOT_EXECUTED против RED), поэтому и
правила здесь разные, а не одно с двумя ветками.

**Порядок объявления: сначала предусловия, потом вердикт о графе.** Гейт,
которому не хватило координат, о трассировке не высказывался вовсе — брать с
него RED значило бы обвинить граф в том, чего никто не смотрел. Порядок назван
здесь, а не получается случайно из порядка строк.

> [!important] Эталон трассировки: инвариант ВЫБРАН, а не возник — и он общий с соседями
> `CG_TRACE_ID_MISSING` предъявляют ШЕСТЬ кейсов приёмки, и миры у них
> структурно разные (единица счёта — кейс, у которого эта диагностика стоит в
> `expected_sut`; предикат: `grep -l CG_TRACE_ID_MISSING */case.yaml` в дереве
> фикстур). У двух — SDD-1-TRACE-02 и SDD-1-DRIVER-02 — эталонное множество
> acceptance IDs лежит в мире (`acceptance_ids`), поэтому сравнение множеств
> прямое. У четырёх вызывающих — WSPP-02, PPRE-02, PCI-02, WSCI-02 — эталона в
> мире НЕТ ни одной координатой: перепись верхнеуровневых координат PPRE-01
> даёт `stdin_ref_line`, `product`, `sibling_workspace`,
> `package_tasks_mapping`, и ни одна из них множеством acceptance IDs не
> является.
>
> Значит утверждение «удалён СУЩЕСТВУЮЩИЙ acceptance case ID» по самому миру
> неразрешимо, и всякая полоса вынуждена ввести СВОЙ инвариант — под ОДНОЙ и
> той же диагностикой. Четыре разных инварианта были бы расхождением, которое
> сведение волны не найдёт: кейсы зелёные у всех, и каждый предикат по
> отдельности верен.
>
> **Поэтому инвариант взят дословно у полосы, реализовавшей cg.pci:** перечень
> задач обязан покрыть ОБЕ половины инверсии рождения — базовый кейс серии и
> хотя бы один производный. Он не выдуман под фикстуру: §7 требует инверсии
> рождения от каждого machine holder — known-good вход даёт ожидаемый pass,
> однофактный injected defect даёт ожидаемый RED, — и перечень, оттрассировавший
> только базовый кейс, не оттрассировал ту половину, которой доказывается
> способность блокировать. Он же и мирозависим: никаких идентификаторов кейсов
> здесь не зарегистрировано, серии выводятся из самих записей перечня.
>
> **Отвергнутая альтернатива названа, чтобы её не переизобрели:** зарегистрировать
> эталонное множество идентификаторов константой модуля (как cg.wire регистрирует
> четвёрку §11, а cg.class — состав exposure items). Она работает на этих
> фикстурах и отвергнута по двум причинам: под общей диагностикой у четырёх
> вызывающих получилось бы четыре несогласованных реестра, и сама константа
> кодировала бы фикстуру, а не норму — приёмка нигде не объявляет, какие
> идентификаторы обязан покрывать перечень задач ЭТОГО вызывающего.
"""

import re

from ..rules import Rule
from .. import outcome

FAMILY = "ppre"

STDIN_REF_LINE = "stdin_ref_line"
PRODUCT = "product"
SIBLING_WORKSPACE = "sibling_workspace"
PACKAGE_TASKS_MAPPING = "package_tasks_mapping"

LOCAL_SHA = "local_sha"
HEAD_SHA = "head_sha"
REPO = "repo"

# Пустое значение обязано означать «пусто», поэтому словарь отсутствия назван
# явно, а не угадывается по правдоподобию строки.
ABSENT_MARKERS = (None, "", "none", "—")

# Идентификатор кейса приёмки: серия и порядковый номер внутри неё. Разбор тот
# же, каким harness выводит семейство из идентификатора; отдельной таблицы
# соответствий нет намеренно — она была бы вторым местом об одном предмете.
ACCEPTANCE_CASE_ID = re.compile(
    r"^(?P<series>SDD-1-[A-Z]+(?:-NA)?)-(?P<ordinal>\d+)$"
)

# Базовая половина инверсии рождения — первый кейс серии (known-good вход);
# всякий следующий номер серии производен от него (injected defect).
BASE_ORDINAL = 1


def _absent(value):
    if value in ABSENT_MARKERS:
        return True
    return isinstance(value, str) and not value.strip()


def _local_ref_not_established(world):
    """Локальная ссылка не установлена: гейту нечего брать за голову диапазона.

    Читается ПАРА целиком — то, что пришло по stdin, и то, что получил гейт:
    вопрос «полные ли координаты» есть отношение двух записей, и по одной он не
    решается. Судится при этом только ЛОКАЛЬНАЯ половина пары: у удалённой своя
    диагностика (`CG_PRE_PUSH_REMOTE_REF_MISSING`), которой этот раздел приёмки
    не объявляет, — завести её здесь значило бы завести код, который не
    предъявит ни один кейс. Граница названа, а не обойдена молчанием.

    Мимо ссылки прошедшая голова — тот же отказ, что и отсутствующая: гейт
    судил бы диапазон, которого никто не толкал.
    """
    ref_line = world.read_all(STDIN_REF_LINE)
    received = world.read_all(PRODUCT)

    local = ref_line.get(LOCAL_SHA)
    if _absent(local):
        return True
    return received.get(HEAD_SHA) != local


def _sibling_workspace_repo_absent(world):
    """Без sibling workspace repo policy не откуда взять — гейт не запускается.

    Запись читается целиком: пара «репозиторий + закреплённая ревизия policy»
    и есть координата соседа, и половина пары соседа не задаёт. Судится
    репозиторий: закреплённая ревизия без репозитория не разрешается ни во что,
    поэтому вопрос о ней задан об источнике, которого нет.
    """
    sibling = world.read_all(SIBLING_WORKSPACE)
    return _absent(sibling.get(REPO))


def _birth_inversion_untraced(world):
    """Перечень задач не покрывает обе половины инверсии рождения.

    Перечень читается целиком: покрытие есть свойство ВСЕГО отображения, и по
    одной записи оно не решается.

    Три состояния дают находку, и каждое означает одно и то же — половины
    инверсии в перечне нет:

    * запись, которая не разбирается как идентификатор кейса приёмки: она не
      трассирует ничего, и считать её трассировкой значило бы принять строку за
      вердикт;
    * пустой перечень: §7 «active package с 0 acceptance IDs даёт RED, не
      vacuous GREEN» — нулевое покрытие не есть полное;
    * серия без базового кейса либо без единого производного: у первой нет
      known-good половины, у второй — половины с injected defect, а инверсия
      рождения требует ОБЕИХ.
    """
    mapping = world.read_all(PACKAGE_TASKS_MAPPING)

    series = {}
    unparsed = []
    for item in mapping or []:
        match = ACCEPTANCE_CASE_ID.match(str(item))
        if match is None:
            unparsed.append(str(item))
            continue
        series.setdefault(match.group("series"), set()).add(
            int(match.group("ordinal"))
        )
    if unparsed:
        return True

    incomplete = [
        name
        for name, ordinals in sorted(series.items())
        if BASE_ORDINAL not in ordinals
        or not any(ordinal != BASE_ORDINAL for ordinal in ordinals)
    ]
    return not series or bool(incomplete)


RULES = [
    Rule(
        rule_id="ppre.local-ref-missing",
        diagnostic="CG_PRE_PUSH_LOCAL_REF_MISSING",
        category=outcome.CATEGORY_NOT_EXECUTED,
        subject_keys=(STDIN_REF_LINE, PRODUCT),
        requires=(STDIN_REF_LINE, PRODUCT),
        predicate=_local_ref_not_established,
        why="§13 SDD-1-PPRE-04: без local SHA во входной stdin ref line caller "
            "возвращает NOT_EXECUTED и блокирует push",
    ),
    Rule(
        rule_id="ppre.workspace-repo-missing",
        diagnostic="CG_PRODUCT_PRE_PUSH_WORKSPACE_REPO_MISSING",
        category=outcome.CATEGORY_NOT_EXECUTED,
        subject_keys=(SIBLING_WORKSPACE,),
        requires=(SIBLING_WORKSPACE,),
        predicate=_sibling_workspace_repo_absent,
        why="§13 SDD-1-PPRE-03: без sibling workspace repo caller возвращает "
            "NOT_EXECUTED и блокирует push",
    ),
    Rule(
        rule_id="ppre.trace-id-missing",
        diagnostic="CG_TRACE_ID_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=(PACKAGE_TASKS_MAPPING,),
        requires=(PACKAGE_TASKS_MAPPING,),
        predicate=_birth_inversion_untraced,
        why="§7 инверсия рождения требует обеих половин — known-good входа и "
            "injected defect; §13 SDD-1-PPRE-02: снятый из package tasks "
            "mapping существующий acceptance case ID блокирует push, и "
            "underlying CG_TRACE_ID_MISSING сохраняется",
    ),
]
