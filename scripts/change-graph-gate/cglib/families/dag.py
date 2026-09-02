"""cg.dag — где candidate стоит относительно cutover СВОЕГО Git DAG.

Приёмка §8 объявляет пять позиций, и у каждой свой исход:

    base — ancestor cutover_commit   pre-cutover, допустим ТОЛЬКО registered legacy
    base == cutover_commit           package required, кроме SDD-1/#480 bootstrap
    cutover_commit — ancestor base   package required
    histories incomparable           RED
    refs/API unavailable             NOT_EXECUTED

Плюс §8 отдельной строкой: «Не используется эвристика стартового коммита или
имени ветки». Поэтому эпоха здесь НЕ угадывается — она складывается из двух
разных источников, и разделение источников несущее:

* **равенство** base и cutover читается по САМИМ КООРДИНАТАМ. Обе они переданы,
  сравнить их можно без обхода DAG, и всякий обходной признак на этом месте был
  бы той самой эвристикой, которую §8 запрещает;
* **направление предшествования** (ancestor в ту или иную сторону, либо
  несравнимость) обходом DAG не вычисляется вовсе — ответ даёт authoritative
  caller, и правило читает его как факт, а не переизобретает.

**Мир этого семейства бывает ДВУХ форм, и это не небрежность фикстур.** Первая
форма описывает candidate (repo identity, base, head) и его положение
относительно cutover; вторая — саму границу cutover, на которой стоит
единственный bootstrap §1. Правила первой формы к миру второй неприменимы и
наоборот: их применимость решают координаты, объявленные миром, а не
идентификатор кейса. Пересечься формам нечем — ни одна координата не общая.

**Порядок объявления правил.** Применимые правила исполняются ВСЕ, а вердикт
берётся по первому нарушению в объявленном порядке (`cglib/rules.py`), поэтому
порядок здесь назван, а не получен случайно:

1. **недоступность lookup — раньше любого RED.** §8 ставит `NOT_EXECUTED` над
   всеми остальными позициями, и это не старшинство категории, а запрет
   выдавать «не знаю» за «нет»: ref, который не резолвился, не даёт права
   утверждать НИЧЕГО ни об эпохе, ни о принадлежности;
2. **привязка к repository — раньше эпохи.** Если названный repo не тот,
   которому принадлежат переданные коммиты, то cutover, с которым сравнивается
   base, взят из чужого DAG (§8: «у каждого DAG свой cutover»), и всякое
   суждение об эпохе оказалось бы суждением о другом репозитории;
3. **несравнимость — раньше требования package.** У несравнимых историй эпохи
   нет вовсе, значит нет и позиции §8, из которой требование package следует;
4. **package на границе** и 5. **package после границы** — взаимно исключающие
   by construction (обе спрашивают равенство base и cutover, одна утвердительно,
   другая отрицательно), поэтому порядок между ними ничего не решает и держать
   его вниманием не требуется;
6. **единственность bootstrap на границе** — правило второй формы мира, с
   правилами первой формы не пересекается.

**Чего это семейство НЕ судит, и почему это сказано вслух.** Целостность самого
legacy-реестра — сверка его с независимой переписью, лишние и недостающие
записи, изменившийся observable contract — предмет `cg.census` (§8, приёмка
§13 SDD-1-CENSUS-07…13) и его диагностик. Здесь реестр читается ровно затем,
чтобы ответить на вопрос ОБ ЭТОМ candidate: предъявил ли он регистрацию,
позволяющую ему оставаться до cutover. Вопрос «полон ли реестр» здесь не
задаётся и ответом на него это правило не притворяется.
"""

from .. import outcome
from ..rules import Rule

FAMILY = "dag"

# --- координаты первой формы мира: candidate и его положение -----------------
CANDIDATE = "candidate"
CANDIDATE_REPO_FIELD = "repo"
CANDIDATE_BASE = "candidate.base_sha"
CANDIDATE_HEAD = "candidate.head_sha"
CANDIDATE_REPO = "candidate.repo"
CUTOVER = "cutover_commit"
RELATION = "relation"
REF_LOOKUP = "ref_lookup"
REPO_MEMBERSHIP = "repo_membership"
PACKAGE_PRESENT = "package_present"
PACKAGE_EXACT_MAPPED = "package_diff_exact_mapped"
REGISTERED_ROUTE = "registered_route"
LEGACY_REGISTRY = "legacy_registry"

# --- координаты второй формы мира: сама граница cutover ---------------------
CHANGE_COORDINATE = "change_coordinate"
BOOTSTRAP_RECORDED = "bootstrap_recorded"
CREATES_CUTOVER_COORDINATES = "creates_cutover_coordinates"
SELF_PACKAGE_PRESENT = "self_package_present"

# Ответы authoritative caller'а о предшествовании (§8). Равенство сюда НЕ
# входит намеренно: его устанавливают координаты, а не ответ о DAG.
RELATION_BASE_BEFORE_CUTOVER = "base-is-ancestor-of-cutover"
RELATION_CUTOVER_BEFORE_BASE = "cutover-is-ancestor-of-base"
RELATION_INCOMPARABLE = "incomparable"

REF_AVAILABLE = "available"
LEGACY_ROUTE = "legacy"

# Разделитель координаты change'а в legacy-реестре: `<repo>#<номер>`. Реестр
# общий на оба DAG, а cutover у каждого DAG свой (§8), поэтому запись соседнего
# репозитория этот candidate не оправдывает.
CHANGE_COORDINATE_SEPARATOR = "#"

# §1 и §8: единственное bootstrap-исключение долговечно ограничено парой
# «Issue #480 + этот acceptance», собственного package не фабрикует и именно оно
# создаёт координаты cutover. Всякое отличие от этого набора означает одно и то
# же — перед нами не то единственное исключение, которое зарегистрировано, — и
# потому судится ОДНИМ правилом с одной диагностикой, а не конъюнкцией четырёх
# проверок с диагностиками, которых приёмка не объявляет. Тот же приём, что у
# cg.boot, и по той же причине.
REGISTERED_BOUNDARY_BOOTSTRAP = {
    CHANGE_COORDINATE: "SDD-1 / PRO-Robotech/kacho-workspace#480",
    BOOTSTRAP_RECORDED: True,
    CREATES_CUTOVER_COORDINATES: True,
    SELF_PACKAGE_PRESENT: False,
}


def _base_equals_cutover(world):
    """§8, позиция «base == cutover_commit» — по самим координатам.

    Обе координаты переданы caller'ом, равенство читается прямо, и никакой
    производный признак (имя ветки, стартовый коммит) для этого не нужен —
    §8 их прямо запрещает.
    """
    return str(world.read(CANDIDATE_BASE)) == str(world.read(CUTOVER))


def _base_before_cutover(world):
    """§8, позиция «base — ancestor cutover_commit».

    Предшествование берётся ответом authoritative caller'а: обход DAG не предмет
    гейта. Равенство исключается отдельно — «предок» и «тот же коммит» у §8
    РАЗНЫЕ позиции с разными исходами, и слить их значило бы дать одному входу
    два имени.
    """
    return (
        world.read(RELATION) == RELATION_BASE_BEFORE_CUTOVER
        and not _base_equals_cutover(world)
    )


def _cutover_before_base(world):
    """§8, позиция «cutover_commit — ancestor base». Равенство исключается там же
    и по той же причине, что в позиции выше."""
    return (
        world.read(RELATION) == RELATION_CUTOVER_BEFORE_BASE
        and not _base_equals_cutover(world)
    )


def _registered_legacy_route(world):
    """§8: до cutover candidate допустим ТОЛЬКО зарегистрированным legacy-маршрутом.

    Проверяется предъявление регистрации ЭТИМ candidate'ом: маршрут, который он
    называет, обязан быть legacy и обязан быть зарегистрирован в реестре ЕГО
    репозитория. Запись соседнего DAG не оправдывает: у каждого DAG свой cutover
    и свой legacy-периметр (§8).

    Мир, не назвавший ни маршрута, ни реестра, регистрации не предъявил — а для
    этой линии «не предъявлена» и «не зарегистрирована» одно и то же: §8
    разрешает остаться до cutover только предъявившему её. Обратное прочтение
    («не назвал — значит можно») открыло бы пребывание до cutover каждому, кто
    промолчал.
    """
    if not world.has(REGISTERED_ROUTE) or not world.has(LEGACY_REGISTRY):
        return False
    repo = str(world.read(CANDIDATE_REPO))
    declared = str(world.read(REGISTERED_ROUTE))
    registry = world.read_all(LEGACY_REGISTRY)
    registered_here = {
        str(route)
        for coordinate, route in registry.items()
        if str(coordinate).split(CHANGE_COORDINATE_SEPARATOR, 1)[0] == repo
    }
    return declared == LEGACY_ROUTE and LEGACY_ROUTE in registered_here


def _valid_package_missing(world):
    """§8/§13: требуется не «package вообще», а ВАЛИДНЫЙ package.

    Приёмка формулирует положительные кейсы дословно как «valid package
    exact-mapped diff присутствует» (SDD-1-DAG-02) и «valid package
    присутствует» (SDD-1-DAG-04). Там, где мир объявляет exact-mapping diff'а,
    оно и есть та часть валидности, которую мир смоделировал: package,
    присутствующий и не отображающий diff точно, требования §8 не удовлетворяет
    — иначе «package есть» означало бы наличие каталога, а не покрытие
    изменения. Там, где мир exact-mapping не объявляет, читать нечего, и
    домысливать его отсутствие значило бы судить о том, чего мир не сказал.

    Обе координаты читаются ДО того, как из них складывается ответ. Запись
    `present and bool(world.read(...))` выглядела бы тем же самым и была бы
    неверна: `and` не вычисляет правую часть на ложной левой, поэтому на мире
    без package exact-mapping осталось бы непрочитанным — и вердикт стал бы
    заявлением шире осмотренного. Это не догадка: ядро поймало ровно это на
    SDD-1-DAG-03 при первой редакции правила.
    """
    present = bool(world.read(PACKAGE_PRESENT))
    if world.has(PACKAGE_EXACT_MAPPED):
        exact_mapped = bool(world.read(PACKAGE_EXACT_MAPPED))
        present = present and exact_mapped
    return not present


def _candidate_ref_unavailable(world):
    """§8: refs/API unavailable — NOT_EXECUTED, и никогда RED.

    Читается ВЕСЬ отчёт lookup'а: недоступность любого из переданных ref'ов
    лишает гейт права утверждать что-либо о candidate, поэтому предмет —
    состав отчёта целиком, а не отдельная его запись.
    """
    lookup = world.read_all(REF_LOOKUP)
    return any(str(state) != REF_AVAILABLE for state in lookup.values())


def _candidate_repository_mismatch(world):
    """§8: caller передаёт ТРОЙКУ (repo identity, base SHA, head SHA), и гейт
    проверяет, что переданные коммиты существуют именно в названном repo.

    Тройка потребляется целиком: предмет правила — она как ОДНО заявление
    caller'а, а не отдельная её запись; судится каждая переданная координата
    коммита, а не заранее выписанный их список — выписанный разошёлся бы с тем,
    что caller прислал на самом деле.

    Мир объявляет принадлежность отдельной записью. Мир, её не объявивший,
    привязку не ОСПАРИВАЕТ — он её не моделирует, и RED здесь означал бы «не
    знаю», выданное за «нет». Линия, на которой гейт не смог узнать, судится
    своим правилом и своей категорией (NOT_EXECUTED выше).
    """
    passed = world.read_all(CANDIDATE)
    if not world.has(REPO_MEMBERSHIP):
        return False
    membership = world.read_all(REPO_MEMBERSHIP)
    repo = str(passed.get(CANDIDATE_REPO_FIELD))
    return any(
        str(membership.get(field)) != repo
        for field in sorted(passed)
        if field != CANDIDATE_REPO_FIELD
    )


def _histories_incomparable(world):
    """§8: histories incomparable — RED. Эпохи у такого candidate нет вовсе."""
    return world.read(RELATION) == RELATION_INCOMPARABLE


def _package_required_at_cutover(world):
    """§8: на границе cutover обязателен package.

    Границу candidate занимает двумя способами, и §8 приводит оба к одному
    требованию:

    * base РАВЕН cutover_commit — прямая позиция §8;
    * base ещё до cutover, но candidate не предъявил зарегистрированного
      legacy-маршрута. Другого способа остаться до cutover §8 не даёт
      («pre-cutover, допустим ТОЛЬКО registered legacy»), поэтому такой
      candidate стоит на границе наравне с первым.

    Bootstrap-исключение §8 («кроме SDD-1/#480») к этой линии не относится: оно
    живёт на собственной границе, описывается второй формой мира и судится своим
    правилом ниже. Дублировать его здесь значило бы завести второе место об
    одном предмете.

    Оба слагаемых и отсутствие package вычисляются ДО решения: короткое
    замыкание оставило бы координаты непрочитанными, и перепись объявила бы
    находку там, где её нет.
    """
    at_boundary = _base_equals_cutover(world)
    off_registered_legacy = (
        _base_before_cutover(world) and not _registered_legacy_route(world)
    )
    missing = _valid_package_missing(world)
    return (at_boundary or off_registered_legacy) and missing


def _package_required_after_cutover(world):
    """§8: cutover_commit — ancestor base, package обязателен.

    Исключений у этой позиции §8 не объявляет ни одного: bootstrap ограничен
    собственной границей, а legacy-маршрут — эпохой ДО cutover.
    """
    missing = _valid_package_missing(world)
    return _cutover_before_base(world) and missing


def _declared_boundary_bootstrap(world):
    """Набор фактов, которым мир второй формы заявляет себя bootstrap'ом."""
    return {
        CHANGE_COORDINATE: world.read(CHANGE_COORDINATE),
        BOOTSTRAP_RECORDED: world.read(BOOTSTRAP_RECORDED),
        CREATES_CUTOVER_COORDINATES: world.read(CREATES_CUTOVER_COORDINATES),
        SELF_PACKAGE_PRESENT: world.read(SELF_PACKAGE_PRESENT),
    }


def _boundary_bootstrap_not_unique(world):
    """§1/§8: исключение на границе выдано не «изменению вообще», а ровно этому.

    Предикат — равенство ЗАЯВЛЕННОГО набора ЗАРЕГИСТРИРОВАННОМУ. Всякое отличие,
    в какой бы координате оно ни было, означает одно: перед нами второе
    bootstrap-исключение, а второго не бывает.
    """
    return _declared_boundary_bootstrap(world) != REGISTERED_BOUNDARY_BOOTSTRAP


CANDIDATE_POSITION_KEYS = (CANDIDATE, CUTOVER, RELATION, PACKAGE_PRESENT,
                           PACKAGE_EXACT_MAPPED)
CANDIDATE_POSITION_REQUIRES = (CANDIDATE_BASE, CUTOVER, RELATION,
                               PACKAGE_PRESENT)
BOUNDARY_KEYS = (CHANGE_COORDINATE, BOOTSTRAP_RECORDED,
                 CREATES_CUTOVER_COORDINATES, SELF_PACKAGE_PRESENT)

RULES = [
    Rule(
        rule_id="dag.candidate-ref-unavailable",
        diagnostic="CG_CANDIDATE_REF_UNAVAILABLE",
        category=outcome.CATEGORY_NOT_EXECUTED,
        subject_keys=(REF_LOOKUP,),
        requires=(REF_LOOKUP,),
        predicate=_candidate_ref_unavailable,
        why="§8 refs/API unavailable даёт NOT_EXECUTED; объявлено первым, "
            "потому что нерезолвившийся ref лишает права утверждать что-либо "
            "об эпохе и о принадлежности (SDD-1-DAG-07)",
    ),
    Rule(
        rule_id="dag.candidate-repository-mismatch",
        diagnostic="CG_CANDIDATE_REPOSITORY_MISMATCH",
        category=outcome.CATEGORY_RED,
        subject_keys=(CANDIDATE, REPO_MEMBERSHIP),
        requires=(CANDIDATE_REPO, CANDIDATE_BASE, CANDIDATE_HEAD),
        predicate=_candidate_repository_mismatch,
        why="§8 gate проверяет, что переданные commits существуют именно в "
            "названном repo; объявлено раньше эпохи, потому что у каждого DAG "
            "свой cutover и сравнение шло бы с чужим (SDD-1-DAG-08)",
    ),
    Rule(
        rule_id="dag.cutover-history-incomparable",
        diagnostic="CG_CUTOVER_HISTORY_INCOMPARABLE",
        category=outcome.CATEGORY_RED,
        subject_keys=(RELATION,),
        requires=(RELATION,),
        predicate=_histories_incomparable,
        why="§8 histories incomparable — RED; объявлено раньше требований "
            "package, потому что у несравнимых историй нет эпохи, из которой "
            "эти требования следуют (SDD-1-DAG-06)",
    ),
    Rule(
        rule_id="dag.package-required-at-cutover",
        diagnostic="CG_PACKAGE_REQUIRED_AT_CUTOVER",
        category=outcome.CATEGORY_RED,
        subject_keys=CANDIDATE_POSITION_KEYS + (REGISTERED_ROUTE,
                                                LEGACY_REGISTRY),
        requires=CANDIDATE_POSITION_REQUIRES,
        predicate=_package_required_at_cutover,
        why="§8 base == cutover_commit требует package; та же граница у "
            "pre-cutover candidate'а, не предъявившего registered legacy "
            "route (SDD-1-DAG-01, SDD-1-DAG-03)",
    ),
    Rule(
        rule_id="dag.package-required-after-cutover",
        diagnostic="CG_PACKAGE_REQUIRED_AFTER_CUTOVER",
        category=outcome.CATEGORY_RED,
        subject_keys=CANDIDATE_POSITION_KEYS,
        requires=CANDIDATE_POSITION_REQUIRES,
        predicate=_package_required_after_cutover,
        why="§8 cutover_commit — ancestor base требует package без исключений "
            "(SDD-1-DAG-05)",
    ),
    Rule(
        rule_id="dag.boundary-bootstrap-not-unique",
        diagnostic="CG_BOOTSTRAP_NOT_UNIQUE",
        category=outcome.CATEGORY_RED,
        subject_keys=BOUNDARY_KEYS,
        requires=BOUNDARY_KEYS,
        predicate=_boundary_bootstrap_not_unique,
        why="§1 единственный bootstrap ограничен парой #480 + этот acceptance; "
            "§8 исключение на границе cutover выдано ровно ему "
            "(SDD-1-DAG-09, SDD-1-DAG-10)",
    ),
]
