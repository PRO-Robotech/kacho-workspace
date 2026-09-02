#!/usr/bin/env python3
"""Инъекция для cg.census и cg.policy: правила ОБЯЗАНЫ уметь упасть.

`prove.py` спрашивает «совпала ли тройка на fixture». Здесь спрашивается то,
чего fixture спросить не может: покраснеет ли правило на дефекте, которого в
матрице нет, и промолчит ли оно на ЗАКОННОМ близнеце той же формы. Без второй
половины проба ловила бы форму, а не существо: правило, отвергающее всё,
прошло бы одностороннюю инъекцию целиком.

Три предмета сверх этого, каждый со своей причиной:

* **ловушка точного множества.** В зарегистрированной политике путь приёмки
  отсутствует у 57 записей из 60, и отсутствие выражено первым классом
  (`acceptance_path: null` + названный `acceptance_absence_predicate`), а не
  пустой строкой. Предикат, требующий состав записи полным, покрасил бы их все.
  Здесь это проверено прямо: registry, чьи записи не несут пути, обязан
  остаться GREEN, а снятие КООРДИНАТЫ из того же контейнера — покраснеть;

* **порядок правил несущий, а не стилистический.** У двух швов cg.policy
  предикат последующего правила ИСТИНЕН на входе предыдущего, и только
  объявленный порядок даёт верную диагностику. Это проверяется и снаружи
  (тройка), и изнутри (предикат зовётся напрямую) — иначе «порядок работает»
  было бы совпадением;

* **обязанность прочитать весь предмет.** Факт, попавший в предмет семейства и
  не прочитанный ни одним применимым правилом, обязан дать собственный отказ, а
  не вердикт. Проверено инъекцией лишнего факта.

    python3 scripts/change-graph-gate/selftest/prove_census_policy.py

Исходов три: 0 — все утверждения прошли; 1 — есть провалившееся; 2 — проба
беспредметна (утверждений ноль либо миров осмотрено ноль).
"""

import copy
import os
import re
import subprocess
import sys
import tempfile

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
GATE_DIR = os.path.abspath(os.path.join(HERE, ".."))
SUT = os.path.join(GATE_DIR, "run.py")
TESTDATA = os.path.join(GATE_DIR, "tests", "testdata")

SELF_FAILURE_EXIT = 40
CENSUS_LINE = re.compile(
    r"фактов мира (\d+) · прочитано (\d+) · вне предмета семейства (\d+)"
)

sys.path.insert(0, GATE_DIR)
from cglib import families as families_package  # noqa: E402
from cglib import world as world_module  # noqa: E402
from cglib.families import policy as policy_family  # noqa: E402

PASSED = []
FAILED = []
WORLDS_SEEN = set()

WORKSPACE = "PRO-Robotech/kacho-workspace"
PRODUCT = "PRO-Robotech/kacho"


def check(name, condition, detail=""):
    if condition:
        PASSED.append(name)
        sys.stdout.write("  OK   %s\n" % name)
    else:
        FAILED.append(name)
        sys.stdout.write("  FAIL %s\n       %s\n" % (name, detail))


def fixture_world(case_id):
    return os.path.join(TESTDATA, case_id, "world.yaml")


def load_world(case_id):
    with open(fixture_world(case_id), encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def run_sut(world_path, case_id):
    completed = subprocess.run(
        [sys.executable, SUT, "--case-world", world_path, "--case", case_id],
        capture_output=True, text=True, timeout=60,
    )
    lines = [line for line in completed.stdout.split("\n") if line.strip()]
    WORLDS_SEEN.add(world_path)
    return completed, (lines[-1] if lines else "(без вывода)")


def judge(work, name, case_id, document):
    """Кладёт мир во временный каталог и возвращает тройку испытуемого."""
    path = os.path.join(work, "%s.yaml" % name)
    with open(path, "w", encoding="utf-8") as handle:
        yaml.safe_dump(document, handle, allow_unicode=True, sort_keys=False)
    return run_sut(path, case_id)


def expect_triple(work, name, case_id, document, expected):
    completed, actual = judge(work, name, case_id, document)
    check(
        name,
        actual == expected and completed.returncode == int(expected.rsplit(" ", 1)[1]),
        "ждали %r, имеем %r (код %d)" % (expected, actual, completed.returncode),
    )


def expect_self_failure(work, name, case_id, document, marker):
    completed, actual = judge(work, name, case_id, document)
    check(
        name,
        completed.returncode == SELF_FAILURE_EXIT
        and not completed.stdout.strip()
        and marker in completed.stderr,
        "код %d, stdout=%r, stderr=%s"
        % (completed.returncode, completed.stdout[:120],
           completed.stderr.strip()[:260]),
    )


GREEN = "GREEN · CG_OK · exit 0"


# --- A. cg.census: артефакт переписи -----------------------------------------
def section_census_artifact(work):
    sys.stdout.write("\n== A. cg.census — артефакт переписи ==\n")
    base = load_world("SDD-1-CENSUS-01")

    expect_triple(work, "A0-близнец нетронутый артефакт молчит",
                  "SDD-1-CENSUS-01", copy.deepcopy(base), GREEN)

    world = copy.deepcopy(base)
    world["producer"] = "self"
    expect_triple(work, "A1 producer не independent -> COVERAGE_INCOMPLETE",
                  "SDD-1-CENSUS-01", world,
                  "RED · CG_CENSUS_COVERAGE_INCOMPLETE · exit 10")

    world = copy.deepcopy(base)
    world["etag"] = None
    expect_triple(work, "A2 ETag отсутствует -> COVERAGE_INCOMPLETE",
                  "SDD-1-CENSUS-01", world,
                  "RED · CG_CENSUS_COVERAGE_INCOMPLETE · exit 10")

    world = copy.deepcopy(base)
    world["response_digest"] = ""
    expect_triple(work, "A3 response digest пуст -> COVERAGE_INCOMPLETE",
                  "SDD-1-CENSUS-01", world,
                  "RED · CG_CENSUS_COVERAGE_INCOMPLETE · exit 10")

    world = copy.deepcopy(base)
    world["coverage"]["product-open-prs"] = ""
    expect_triple(work, "A4 query объявлен и пуст -> COVERAGE_INCOMPLETE",
                  "SDD-1-CENSUS-01", world,
                  "RED · CG_CENSUS_COVERAGE_INCOMPLETE · exit 10")

    world = copy.deepcopy(base)
    world["coverage"]["releases"] = "query=/releases result=none"
    expect_triple(work, "A5 лишний query -> COVERAGE_INCOMPLETE (множество точное)",
                  "SDD-1-CENSUS-01", world,
                  "RED · CG_CENSUS_COVERAGE_INCOMPLETE · exit 10")

    # Свежесть: горизонт настоящий, а не «значение отличается от fixture».
    world = copy.deepcopy(base)
    world["timestamp"] = "2026-09-03T11:06:27Z"   # ровно +24 ч от registered
    expect_triple(work, "A6-близнец иной timestamp РОВНО на горизонте молчит",
                  "SDD-1-CENSUS-01", world, GREEN)

    world = copy.deepcopy(base)
    world["timestamp"] = "2026-09-03T11:06:28Z"   # горизонт + 1 с
    expect_triple(work, "A7 горизонт + одна секунда -> CENSUS_STALE",
                  "SDD-1-CENSUS-01", world, "RED · CG_CENSUS_STALE · exit 10")

    world = copy.deepcopy(base)
    world["freshness_predicate"] = "captured-within-72h"
    expect_self_failure(work, "A8 неизвестный предикат свежести -> собственный отказ",
                        "SDD-1-CENSUS-01", world, "CG_SELF_WORLD_MALFORMED")

    # Недоступность producer'а объявлена раньше свежести и полноты.
    world = copy.deepcopy(base)
    world["api"]["availability"] = "unavailable"
    world["timestamp"] = "2026-08-01T00:00:00Z"
    del world["coverage"]["product-open-prs"]
    expect_triple(
        work,
        "A9 порядок: недоступный producer перебивает и полноту, и свежесть",
        "SDD-1-CENSUS-01", world,
        "NOT_EXECUTED · CG_CENSUS_PRODUCER_UNAVAILABLE · exit 20",
    )


# --- B. cg.census: точное множество и ЛОВУШКА состава записи ------------------
def section_census_registry(work):
    sys.stdout.write("\n== B. cg.census — точное множество registry ==\n")
    base = load_world("SDD-1-CENSUS-07")

    expect_triple(work, "B0-близнец совпавшее множество молчит",
                  "SDD-1-CENSUS-07", copy.deepcopy(base), GREEN)

    # ЛОВУШКА: в policy.yaml путь приёмки отсутствует у 57 записей из 60.
    world = copy.deepcopy(base)
    for coordinate in world["policy_registry"]:
        world["policy_registry"][coordinate] = "issue+route"
    expect_triple(
        work,
        "B1-близнец запись БЕЗ acceptance_path (57 из 60 в policy) молчит",
        "SDD-1-CENSUS-07", world, GREEN,
    )

    world = copy.deepcopy(base)
    for coordinate in world["policy_registry"]:
        world["policy_registry"][coordinate] = None
    expect_triple(
        work,
        "B2-близнец состав записи не судится вовсе — null молчит",
        "SDD-1-CENSUS-07", world, GREEN,
    )

    world = copy.deepcopy(base)
    del world["policy_registry"][PRODUCT + "#1500"]
    expect_triple(
        work,
        "B3 тот же контейнер краснеет на снятой КООРДИНАТЕ -> MISSING_ACTIVE",
        "SDD-1-CENSUS-07", world,
        "RED · CG_LEGACY_REGISTRY_MISSING_ACTIVE · exit 10",
    )

    world = copy.deepcopy(base)
    world["policy_registry"][PRODUCT + "#7"] = "issue+route"
    expect_triple(work, "B4 лишняя координата -> EXTRA_ENTRY",
                  "SDD-1-CENSUS-07", world,
                  "RED · CG_LEGACY_REGISTRY_EXTRA_ENTRY · exit 10")

    # Порядок внутри полосы множества несущий: оба предиката истинны разом.
    world = copy.deepcopy(base)
    del world["policy_registry"][WORKSPACE + "#481"]
    world["policy_registry"][PRODUCT + "#7"] = "issue+route"
    expect_triple(
        work,
        "B4а порядок: пропущенная и лишняя разом -> вердикт MISSING_ACTIVE",
        "SDD-1-CENSUS-07", world,
        "RED · CG_LEGACY_REGISTRY_MISSING_ACTIVE · exit 10",
    )

    # Решает мир, а не идентификатор кейса.
    _, actual = run_sut(fixture_world("SDD-1-CENSUS-08"), "SDD-1-CENSUS-07")
    check(
        "B5 дефектный мир под положительным ID даёт MISSING_ACTIVE",
        actual == "RED · CG_LEGACY_REGISTRY_MISSING_ACTIVE · exit 10",
        "получено %r" % (actual,),
    )
    _, actual = run_sut(fixture_world("SDD-1-CENSUS-07"), "SDD-1-CENSUS-08")
    check(
        "B6-близнец чистый мир под отрицательным ID молчит",
        actual == GREEN, "получено %r" % (actual,),
    )

    # Факт внутри предмета, не прочитанный ни одним применимым правилом.
    world = copy.deepcopy(base)
    world["producer"] = "independent"
    expect_self_failure(
        work,
        "B7 лишний факт внутри предмета -> собственный отказ, не вердикт",
        "SDD-1-CENSUS-07", world, "CG_SELF_WORLD_FACT_UNREAD",
    )


# --- C. cg.census: legacy contract, migration, backfill ----------------------
def section_census_routes(work):
    sys.stdout.write("\n== C. cg.census — route legacy, migrate и backfill ==\n")

    base = load_world("SDD-1-CENSUS-10")
    expect_triple(work, "C0-близнец неизменённый contract молчит",
                  "SDD-1-CENSUS-10", copy.deepcopy(base), GREEN)
    world = copy.deepcopy(base)
    world["post_cutover_observed"]["acceptance_hash"] = "sha256:fixture-legacy-v2"
    expect_triple(
        work,
        "C1 вторая половина пары (acceptance hash) тоже судится -> CONTRACT_CHANGED",
        "SDD-1-CENSUS-10", world, "RED · CG_LEGACY_CONTRACT_CHANGED · exit 10",
    )

    base = load_world("SDD-1-CENSUS-12")
    expect_triple(work, "C2-близнец migrate с package молчит",
                  "SDD-1-CENSUS-12", copy.deepcopy(base), GREEN)
    world = copy.deepcopy(base)
    world["package_exact_maps_candidate_diff"] = False
    expect_triple(
        work,
        "C3 package есть, но не exact-maps diff -> MIGRATION_PACKAGE_MISSING",
        "SDD-1-CENSUS-12", world,
        "RED · CG_MIGRATION_PACKAGE_MISSING · exit 10",
    )

    base = load_world("SDD-1-CENSUS-14")
    expect_triple(work, "C4-близнец backfill не требуется — молчит",
                  "SDD-1-CENSUS-14", copy.deepcopy(base), GREEN)
    world = copy.deepcopy(base)
    world["backfill_required"] = True
    expect_triple(
        work,
        "C5 backfill закрытой приёмки -> EXTRA_ENTRY",
        "SDD-1-CENSUS-14", world,
        "RED · CG_LEGACY_REGISTRY_EXTRA_ENTRY · exit 10",
    )
    world = copy.deepcopy(base)
    world["backfill_required"] = True
    world["snapshot_open_prs"] = {WORKSPACE + "#1": "open-pr"}
    expect_triple(
        work,
        "C6-близнец приёмка ЕСТЬ в снимке — требование записи законно, молчит",
        "SDD-1-CENSUS-14", world, GREEN,
    )


# --- D. cg.policy: линии и ПОРЯДОК -------------------------------------------
def section_policy(work):
    sys.stdout.write("\n== D. cg.policy — линии координат и объявленный порядок ==\n")
    base = load_world("SDD-1-POLICY-01")

    expect_triple(work, "D0-близнец зарегистрированная политика молчит",
                  "SDD-1-POLICY-01", copy.deepcopy(base), GREEN)

    world = copy.deepcopy(base)
    world["repositories"]["PRO-Robotech/kacho-legacy"] = "a" * 40
    world["commit_exists_in"]["a" * 40] = "PRO-Robotech/kacho-legacy"
    expect_triple(
        work,
        "D1 лишняя координата repository -> REPOSITORY_MISSING (множество точное)",
        "SDD-1-POLICY-01", world,
        "RED · CG_POLICY_REPOSITORY_MISSING · exit 10",
    )

    world = copy.deepcopy(base)
    world["repositories"][PRODUCT] = "89ABCDEF0123456789abcdef0123456789abcdef"
    expect_triple(work, "D2 uppercase hex -> CUTOVER_SHA_INVALID",
                  "SDD-1-POLICY-01", world,
                  "RED · CG_CUTOVER_SHA_INVALID · exit 10")

    world = copy.deepcopy(base)
    world["repositories"][PRODUCT] = "0123456789abcdef0123456789abcdef01234567"
    expect_triple(
        work,
        "D3 product взял workspace SHA -> WRONG_REPOSITORY (та же линия, другая сторона)",
        "SDD-1-POLICY-01", world,
        "RED · CG_CUTOVER_COMMIT_WRONG_REPOSITORY · exit 10",
    )

    world = copy.deepcopy(base)
    world["repositories"][WORKSPACE] = "b" * 40
    world["commit_exists_in"]["b" * 40] = WORKSPACE
    expect_triple(
        work,
        "D4-близнец иной SHA, существующий в СВОЁМ repo, молчит",
        "SDD-1-POLICY-01", world, GREEN,
    )

    # Порядок I: недоступность lookup перебивает несуществующий commit.
    world = copy.deepcopy(load_world("SDD-1-POLICY-06"))
    world["repositories"][WORKSPACE] = "c" * 40
    expect_triple(
        work,
        "D5 порядок: lookup недоступен + commit не найден -> NOT_EXECUTED, не NOT_FOUND",
        "SDD-1-POLICY-06", world,
        "NOT_EXECUTED · CG_COMMIT_LOOKUP_UNAVAILABLE · exit 20",
    )
    world["api"]["commit_lookup"] = "available"
    expect_triple(
        work,
        "D6-близнец тот же мир с живым lookup -> COMMIT_NOT_FOUND",
        "SDD-1-POLICY-06", world,
        "RED · CG_CUTOVER_COMMIT_NOT_FOUND · exit 10",
    )

    # Шов II закрыт НЕ порядком, а самими предикатами: на негодной форме
    # соседи молчат, поэтому истинно ровно одно правило и перестановка
    # правил ничего не изменила бы. Спрашивается изнутри — снаружи
    # «молчание соседа» и «его перебил порядок» дают одну и ту же тройку.
    invalid = world_module.load(fixture_world("SDD-1-POLICY-03"))
    check(
        "D7 шов формы закрыт предикатом: сосед по существованию молчит на не-SHA",
        policy_family._cutover_commit_not_found(invalid) is False,
        "предикат существования вернул True — тогда шов держится только порядком",
    )
    invalid = world_module.load(fixture_world("SDD-1-POLICY-03"))
    check(
        "D8 и сосед по привязке молчит на не-SHA тоже",
        policy_family._cutover_commit_wrong_repository(invalid) is False,
        "предикат привязки вернул True на строке, которая SHA не является",
    )
    _, actual = run_sut(fixture_world("SDD-1-POLICY-03"), "SDD-1-POLICY-03")
    check(
        "D8а вердикт называет линию, на которой координата отпала",
        actual == "RED · CG_CUTOVER_SHA_INVALID · exit 10",
        "получено %r" % (actual,),
    )

    # Версия схемы — применимость семейства, а не находка.
    world = copy.deepcopy(base)
    world["policy_schema_version"] = 2
    expect_self_failure(
        work,
        "D9 неизвестная версия схемы -> мир не судим, а не GREEN",
        "SDD-1-POLICY-01", world, "CG_SELF_WORLD_NOT_JUDGED",
    )


# --- E. Перепись прочитанного по всем мирам обоих семейств -------------------
def section_read_accounting():
    sys.stdout.write("\n== E. Весь предмет прочитан на каждом мире ==\n")
    cases = sorted(
        name for name in os.listdir(TESTDATA)
        if os.path.isdir(os.path.join(TESTDATA, name))
        and ("-CENSUS-" in name or "-POLICY-" in name)
    )
    incomplete = []
    for case_id in cases:
        completed, _ = run_sut(fixture_world(case_id), case_id)
        match = CENSUS_LINE.search(completed.stderr)
        if match is None:
            incomplete.append("%s: переписи нет вовсе" % case_id)
            continue
        total, read, outside = (int(group) for group in match.groups())
        if total == 0 or read != total or outside != 0:
            incomplete.append(
                "%s: фактов %d, прочитано %d, вне предмета %d"
                % (case_id, total, read, outside)
            )
    check(
        "E1 на всех %d мирах прочитан ВЕСЬ предмет и ничего вне него" % len(cases),
        bool(cases) and not incomplete,
        "; ".join(incomplete) or "миров ноль",
    )
    return len(cases)


def main():
    declared = sorted(
        module for module in os.listdir(os.path.join(GATE_DIR, "cglib", "families"))
        if module in ("census.py", "policy.py")
    )
    if len(declared) != 2:
        sys.stdout.write(
            "проба беспредметна: модулей проверяемых семейств найдено %d\n"
            % len(declared)
        )
        return 2

    with tempfile.TemporaryDirectory(prefix="cg-census-policy-") as work:
        section_census_artifact(work)
        section_census_registry(work)
        section_census_routes(work)
        section_policy(work)
        worlds = section_read_accounting()

    total = len(PASSED) + len(FAILED)
    sys.stdout.write("\n=== перепись инъекций cg.census и cg.policy ===\n")
    sys.stdout.write(
        "утверждений: %d · прошло: %d · провалено: %d\n"
        % (total, len(PASSED), len(FAILED))
    )
    sys.stdout.write(
        "миров осмотрено: %d · fixture-миров обоих семейств: %d\n"
        % (len(WORLDS_SEEN), worlds)
    )
    if total == 0 or worlds == 0:
        sys.stdout.write("проба беспредметна: утверждать или осматривать нечего\n")
        return 2
    return 1 if FAILED else 0


if __name__ == "__main__":
    raise SystemExit(main())
