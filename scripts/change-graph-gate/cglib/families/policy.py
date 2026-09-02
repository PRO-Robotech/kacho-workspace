"""cg.policy — версионированная политика и две координаты cutover.

Приёмка §8: `docs/changes/policy.yaml` имеет schema_version 1 и несёт ОТДЕЛЬНЫЕ
entries на каждый DAG — по одному cutover-коммиту на repository. Приёмка §4: с
момента cutover вся authority читается отсюда, поэтому неверная координата
cutover — не косметика, а потеря корня доверия.

**Версия схемы — ПРИМЕНИМОСТЬ семейства, а не его находка**, и это решение.
Правила ниже написаны для формы версии 1; политика версии 2 ими не судима, и
ответить о ней GREEN или RED значило бы высказаться о документе, чьего смысла
испытуемый не знает. Ядро на такой мир отвечает собственным отказом «мир не
судим» — «правил не нашлось» и «нарушений не найдено» здесь, как и везде,
разные вещи. Тот же приём, что у cg.nonempty, где предметом правил объявлен
только active package.

**Диагностика выбирается ЛИНИЕЙ, на которой координата отпала, а не тем, что
не сошлось** — иначе один и тот же вход получал бы разные имена в зависимости
от порядка проверок:

    lookup недоступен            -> NOT_EXECUTED, и НИКОГДА не «не найден»
    множество repo не то         -> координата отсутствует
    строка не 40 lowercase hex   -> лексически не SHA
    SHA годен, но его нет        -> коммит не найден
    SHA есть, но в чужом repo    -> привязка к repository нарушена

**Швы между линиями закрыты ДВУМЯ разными способами, и путать их нельзя.**

Шов «недоступность lookup ↔ всё остальное» закрыт ПОРЯДКОМ, и порядок здесь
несущий: на мире, где lookup недоступен И commit не найден, истинны оба
предиката, и только объявленный первым даёт `NOT_EXECUTED`. §13
SDD-1-POLICY-06 требует этого дословно — «SUT возвращает NOT_EXECUTED, не
NOT_FOUND»: неполученный ответ не есть «нет». Доказано инъекцией
(`selftest/prove_census_policy.py`, утверждение D5 с законным близнецом D6).

Шов «форма SHA ↔ существование ↔ привязка» закрыт иначе — САМИМИ ПРЕДИКАТАМИ:
правило существования пропускает лексически негодную строку, правило привязки
пропускает несуществующий SHA. Поэтому на одном входе истинно ровно одно из
трёх, и диагностика не зависит от порядка вовсе. Это строже порядка: перестановка
правил здесь ничего не меняет, тогда как порядок пришлось бы удерживать
вниманием. Тот же приём, что у cg.hash, где правило манифеста пропускает случай
«манифест согласен с вердиктом» как предмет соседнего правила.

Здесь стояло обратное — «форма объявлена раньше существования, потому что
правило существования сработало бы на не-SHA тоже». Это было ложью о
собственном коде: `continue` по негодной форме стоит в самом предикате, и
инъекция показала, что на SDD-1-POLICY-03 предикат существования возвращает
False. Утверждение о порядке, у которого нет предмета, — тот же класс, что
корпус ловит в документах; поэтому оно не поправлено молча, а названо.

Множество repository — зарегистрированная истина, как `REGISTERED_BOOTSTRAP` у
cg.boot: приёмка §8 объявляет ровно две координаты, и всякое отличие от них,
в обе стороны, означает одно — перед нами не та политика, которую
зарегистрировали. Отдельной диагностики на «лишний repository» приёмка не
объявляет, и заводить её значило бы положить в дерево код без предъявляющего
его кейса.
"""

import re

from .. import outcome
from ..rules import Rule

FAMILY = "policy"

REGISTERED_SCHEMA_VERSION = 1

# §8: у каждого DAG свой cutover; координат ровно две.
REGISTERED_REPOSITORIES = frozenset(
    ("PRO-Robotech/kacho-workspace", "PRO-Robotech/kacho")
)

# §13 SDD-1-POLICY-03: 40 lowercase hex, и никак иначе.
COMMIT_SHA = re.compile(r"^[0-9a-f]{40}$")

AVAILABLE = "available"


def _schema_is_registered(world):
    """Применимость всего семейства: правила написаны под версию 1."""
    return world.read("policy_schema_version") == REGISTERED_SCHEMA_VERSION


def _commit_lookup_unavailable(world):
    """§8: refs/API unavailable — NOT_EXECUTED."""
    return world.read("api.commit_lookup") != AVAILABLE


def _repositories_not_registered(world):
    """§8: ровно две объявленные координаты repository, не больше и не меньше.

    Читается ВСЁ отображение: предмет — его состав, и решить о составе по одной
    записи нельзя.
    """
    declared = world.read_all("repositories")
    return set(declared) != set(REGISTERED_REPOSITORIES)


def _cutover_sha_invalid(world):
    """§8: cutover_commit — 40 lowercase hex."""
    declared = world.read_all("repositories")
    for repo in sorted(declared):
        if not COMMIT_SHA.match(str(declared[repo])):
            return True
    return False


def _cutover_commit_not_found(world):
    """§8: commit обязан существовать; healthy API подтверждает его отсутствие.

    Лексически негодная строка сюда не относится — её судит правило формы,
    объявленное раньше, и повторять её находку здесь значило бы дать одному
    входу два имени.
    """
    declared = world.read_all("repositories")
    known = world.read_all("commit_exists_in")
    for repo in sorted(declared):
        sha = str(declared[repo])
        if not COMMIT_SHA.match(sha):
            continue
        if sha not in known:
            return True
    return False


def _cutover_commit_wrong_repository(world):
    """§8: SHA привязан к repo НАМЕРЕННО — валидный SHA соседа отвергается.

    Несуществующий SHA сюда не относится: у него нет repo, с которым можно
    сравнивать, и его находку объявляет правило существования.
    """
    declared = world.read_all("repositories")
    known = world.read_all("commit_exists_in")
    for repo in sorted(declared):
        sha = str(declared[repo])
        if not COMMIT_SHA.match(sha) or sha not in known:
            continue
        if known[sha] != repo:
            return True
    return False


SCHEMA_KEY = "policy_schema_version"
COORDINATE_KEYS = (SCHEMA_KEY, "repositories", "commit_exists_in")

RULES = [
    Rule(
        rule_id="policy.commit-lookup-unavailable",
        diagnostic="CG_COMMIT_LOOKUP_UNAVAILABLE",
        category=outcome.CATEGORY_NOT_EXECUTED,
        subject_keys=(SCHEMA_KEY, "api"),
        requires=(SCHEMA_KEY, "api.commit_lookup"),
        applicability=_schema_is_registered,
        predicate=_commit_lookup_unavailable,
        why="§8 refs/API unavailable даёт NOT_EXECUTED; §13 SDD-1-POLICY-06 "
            "требует NOT_EXECUTED, а НЕ NOT_FOUND",
    ),
    Rule(
        rule_id="policy.repository-missing",
        diagnostic="CG_POLICY_REPOSITORY_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=(SCHEMA_KEY, "repositories"),
        requires=(SCHEMA_KEY, "repositories"),
        applicability=_schema_is_registered,
        predicate=_repositories_not_registered,
        why="§8 policy несёт отдельные entries на оба DAG; отсутствие "
            "координаты repository оставляет DAG без корня доверия "
            "(SDD-1-POLICY-02)",
    ),
    Rule(
        rule_id="policy.cutover-sha-invalid",
        diagnostic="CG_CUTOVER_SHA_INVALID",
        category=outcome.CATEGORY_RED,
        subject_keys=(SCHEMA_KEY, "repositories"),
        requires=(SCHEMA_KEY, "repositories"),
        applicability=_schema_is_registered,
        predicate=_cutover_sha_invalid,
        why="§8 cutover_commit — 40 lowercase hex; линия отделена от "
            "существования не порядком, а предикатом соседа, который негодную "
            "форму пропускает (SDD-1-POLICY-03)",
    ),
    Rule(
        rule_id="policy.cutover-commit-not-found",
        diagnostic="CG_CUTOVER_COMMIT_NOT_FOUND",
        category=outcome.CATEGORY_RED,
        subject_keys=COORDINATE_KEYS,
        requires=COORDINATE_KEYS,
        applicability=_schema_is_registered,
        predicate=_cutover_commit_not_found,
        why="§8 gate проверяет, что commits существуют именно в названном repo "
            "(SDD-1-POLICY-04)",
    ),
    Rule(
        rule_id="policy.cutover-commit-wrong-repository",
        diagnostic="CG_CUTOVER_COMMIT_WRONG_REPOSITORY",
        category=outcome.CATEGORY_RED,
        subject_keys=COORDINATE_KEYS,
        requires=COORDINATE_KEYS,
        applicability=_schema_is_registered,
        predicate=_cutover_commit_wrong_repository,
        why="§8 SHA привязан к repo намеренно: одинаково валидный по форме SHA "
            "другого repo обязан отвергаться (SDD-1-POLICY-05)",
    ),
]
