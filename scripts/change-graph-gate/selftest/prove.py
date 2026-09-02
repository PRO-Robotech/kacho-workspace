#!/usr/bin/env python3
"""Birth inversion самого испытуемого: он ОБЯЗАН уметь упасть.

Приёмка §7 требует birth inversion от каждого machine holder: known-good вход
даёт ожидаемый pass, однофактный injected defect даёт ожидаемый RED, нулевая
перепись не может дать GREEN. Испытуемый — тоже machine holder, и те же три
требования предъявляются здесь ему самому.

Предмет проб, которого НЕТ у матрицы кейсов: матрица спрашивает «совпала ли
тройка», а здесь спрашивается то, чего она спросить не может, —

  * вердикт есть функция МИРА, а не идентификатора кейса (иначе испытуемый был
    бы таблицей соответствий, зелёной по построению);
  * собственный отказ испытуемого НИКОГДА не выдаётся за вердикт о предмете,
    и обе стороны этого различения доказаны инъекцией;
  * КАЖДЫЙ собственный отказ ядра проверен утверждением с законным близнецом —
    включая тот, у которого нет производителя среди фикстур (правило, читающее
    вне объявленного предмета своего семейства): его вход производится здесь,
    прямым вызовом ядра, и это названо, а не подразумевается;
  * перепись объёма печатается, поэтому «нарушений ноль» отличимо от
    «не прочитано ничего»;
  * объявление признаков ВЫВОДИТСЯ из дерева, а не выписано списком.

Каждое утверждение проверяется в обе стороны: рядом с инъекцией стоит законный
близнец, на котором испытуемый обязан вести себя иначе. Односторонняя проба
зеленела бы на испытуемом, который отвергает всё.

    python3 scripts/change-graph-gate/selftest/prove.py

Исходов три: 0 — все утверждения прошли; 1 — есть провалившееся; 2 — проба
беспредметна (утверждений ноль либо кейсов объявленных семейств ноль).
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
GATE_DIR = os.path.abspath(os.path.join(HERE, ".."))
SUT = os.path.join(GATE_DIR, "run.py")
TESTDATA = os.path.join(GATE_DIR, "tests", "testdata")

SELF_FAILURE_EXIT = 40
SUBJECT_EXIT_CODES = (0, 10, 20)
TRIPLE = re.compile(r"^(GREEN|RED|NOT_EXECUTED) · ([A-Z0-9_]+) · exit (\d+)$")

sys.path.insert(0, GATE_DIR)
from cglib import outcome as outcome_module  # noqa: E402
from cglib import registry as registry_module  # noqa: E402
from cglib import rules as rules_module  # noqa: E402
from cglib import world as world_module  # noqa: E402

# --- признаки КЛАССА утверждения, ставимые помощником ------------------------
# Инъекция, снимающая ветвь ЯДРА, роняет утверждения всех полос, которые на эту
# ветвь опираются, — и перечень ожидаемого у неё обязан ВЫВОДИТЬСЯ, а не
# выписываться именами (`multi-agent-flow.md` §14, четвёртый вид столкновения).
#
# Признак живёт в имени утверждения, потому что инъекция видит от прогона ровно
# имена: строки `  OK   <имя>` и `  FAIL <имя>`. Но признаком служит НЕ проза
# имени, а метка, которую ставит САМ ПОМОЩНИК — тот же, что делает проверку.
# Разница несущая и оплачена: прежний признак был прозаическим («собственный
# отказ» внутри имени), и он одинаково накрывал утверждения, проверяющие РАЗНОЕ,
# — вердикт испытуемого на stdout и отказ ядра внутри процесса. Метка,
# производимая помощником, разойтись с тем, что помощник проверяет, не может
# by construction: забыть её нельзя, потому что её никто не пишет руками.
#
# Метки обязаны быть ВЗАИМНО РАЗЛИЧИМЫ: если одна оказывается подстрокой
# другой, перечень одного класса поглощает перечень второго, и две инъекции
# начинают ожидать одного и того же. Различимость проверяется опытом в
# `selftest/inject.py` — структурно (ни одна не подстрока другой) и поведенчески
# (раскрытия попарно не равны и ни одно не пусто).
CLASS_SUT_SELF_FAILURE = "[класс: отказ испытуемого]"
CLASS_CORE_WORLD_NOT_JUDGED = "[класс: мир не судим]"
CLASS_CORE_FACT_UNREAD = "[класс: факт не прочитан]"
CLASS_CORE_READ_OUTSIDE_SUBJECT = "[класс: чтение вне предмета]"

# Отличительная часть разбора ЯДРА. Диагностика для различения производителя не
# годится: `CG_SELF_WORLD_NOT_JUDGED` поднимает и ядро (`cglib/rules.py`), и
# семейство жизненного цикла (`cglib/families/life.py`) — на стадии, которой нет
# в его таблице. Утверждения о них ломаются РАЗНЫМИ инъекциями, поэтому в один
# класс их сводить нельзя, а разводит их именно текст разбора.
CORE_NOT_JUDGED_DETAIL = "не применимо к миру"
CORE_FACT_UNREAD_DETAIL = "не прочитало ни одно применимое правило"

CORE_CLASS_BY_DETAIL = (
    (CORE_NOT_JUDGED_DETAIL, CLASS_CORE_WORLD_NOT_JUDGED),
    (CORE_FACT_UNREAD_DETAIL, CLASS_CORE_FACT_UNREAD),
)
from cglib import tasksmapping as tasksmapping_module  # noqa: E402
import laneparity  # noqa: E402

# Закрытый список кейсов, чья fixture вправе пиновать тройку, принадлежит
# harness'у и здесь только ЧИТАЕТСЯ. Своя копия списка была бы вторым местом об
# одном предмете и разошлась бы молча; а без независимого сигнала исключение из
# секции B стало бы маскируемым — расширь его, и B перестала бы спрашивать
# испытуемого, оставаясь зелёной.
sys.path.insert(0, os.path.join(GATE_DIR, "tests"))
from caselib import fixture as harness_fixture_module  # noqa: E402

PASSED = []
FAILED = []


def check(name, condition, detail=""):
    if condition:
        PASSED.append(name)
        sys.stdout.write("  OK   %s\n" % name)
    else:
        FAILED.append(name)
        sys.stdout.write("  FAIL %s\n       %s\n" % (name, detail))


def run_sut(argv, sut=SUT):
    completed = subprocess.run(
        [sys.executable, sut] + argv, capture_output=True, text=True, timeout=60
    )
    lines = [line for line in completed.stdout.split("\n") if line.strip()]
    return completed, lines


def last_triple(lines):
    if not lines:
        return None
    return TRIPLE.match(lines[-1])


def write_world(directory, name, document):
    path = os.path.join(directory, name)
    with open(path, "w", encoding="utf-8") as handle:
        yaml.safe_dump(document, handle, allow_unicode=True, sort_keys=False)
    return path


def fixture_world(case_id):
    return os.path.join(TESTDATA, case_id, "world.yaml")


def fixture_manifest(case_id):
    path = os.path.join(TESTDATA, case_id, "case.yaml")
    with open(path, encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def render_triple(declared):
    return "%s · %s · exit %d" % (
        declared["category"], declared["diagnostic"], declared["exit"]
    )


def fixture_expectation(case_id):
    return render_triple(fixture_manifest(case_id)["expected_sut"])


def triple_producible(declared):
    """Может ли испытуемый вообще напечатать такую тройку.

    Код возврата выводится ИЗ категории (`cglib/outcome.py`), поэтому пара
    «GREEN · exit 10» невыразима by construction. Тройка, которую испытуемый
    напечатать не может, утверждением о его поведении не является.
    """
    expected = outcome_module.SUBJECT_EXIT_CODES.get(declared["category"])
    return expected is not None and expected == declared["exit"]


def declared_cases():
    """Кейсы, чьё семейство испытуемый объявил. Перечень ВЫВОДИТСЯ из дерева."""
    families = set(registry_module.load())
    found = []
    for case_id in sorted(os.listdir(TESTDATA)):
        if not os.path.isdir(os.path.join(TESTDATA, case_id)):
            continue
        try:
            family = registry_module.family_of(case_id)
        except Exception:
            continue
        if family in families:
            found.append(case_id)
    return found


# --- A. Объявление признаков -------------------------------------------------
def section_capabilities(work):
    sys.stdout.write("\n== A. Объявление признаков ==\n")
    completed, lines = run_sut(["--capabilities"])
    check(
        "A1 --capabilities выходит нулём",
        completed.returncode == 0,
        "код %d, stderr: %s" % (completed.returncode, completed.stderr.strip()[:200]),
    )
    parsed = None
    try:
        parsed = json.loads(completed.stdout)
    except ValueError as error:
        parsed = None
        detail = str(error)
    else:
        detail = ""
    check(
        "A2 на stdout ТОЛЬКО JSON-перечень строк (перепись ушла на stderr)",
        isinstance(parsed, list)
        and parsed
        and all(isinstance(item, str) for item in parsed),
        "stdout=%r %s" % (completed.stdout[:200], detail),
    )
    check(
        "A3 перечень отсортирован и непуст",
        parsed == sorted(parsed or []) and bool(parsed),
        "получено %r" % (parsed,),
    )

    # Инъекция: перечень ВЫВОДИТСЯ из дерева, а не выписан списком.
    copy_root = os.path.join(work, "gate-copy")
    shutil.copytree(
        GATE_DIR, copy_root,
        ignore=shutil.ignore_patterns("tests", "selftest", "__pycache__"),
    )
    control_completed, _ = run_sut(["--capabilities"], sut=os.path.join(copy_root, "run.py"))
    control = json.loads(control_completed.stdout)
    check(
        "A4-близнец нетронутая копия объявляет тот же перечень",
        control == parsed,
        "копия объявила %r" % (control,),
    )
    os.remove(os.path.join(copy_root, "cglib", "families", "boot.py"))
    shutil.rmtree(os.path.join(copy_root, "cglib", "__pycache__"), ignore_errors=True)
    shutil.rmtree(
        os.path.join(copy_root, "cglib", "families", "__pycache__"), ignore_errors=True
    )
    injected_completed, _ = run_sut(
        ["--capabilities"], sut=os.path.join(copy_root, "run.py")
    )
    injected = json.loads(injected_completed.stdout or "[]")
    # Половины разведены поимённо, и это не косметика. Одной строкой
    # «cg.boot объявлен И после снятия исчез» краснота приходит с ДВУХ сторон:
    # от перечня, переживающего снятие (проверяемое свойство), и от перечня,
    # где cg.boot не объявлен ВОВСЕ (чужая причина). Второе делает инъекцию
    # вакуумной при исправном виде: она отчитывается «покраснело ожидаемое»,
    # ничего не измерив. Разведённые половины различают эти случаи машинно —
    # подмена, потерявшая cg.boot, роняет КОНТРОЛЬ, и прогонщик инъекций
    # сообщает «покраснело лишнее».
    check(
        "A5-контроль снимаемое семейство объявлено ДО снятия",
        "cg.boot" in parsed,
        "объявлено %r" % (parsed,),
    )
    check(
        "A5 снятие модуля семейства снимает признак — перечень выведен из дерева",
        "cg.boot" not in injected,
        "было %r, стало %r" % (parsed, injected),
    )

    # Диагностика собственного отказа не может стать диагностикой предмета.
    subject_diagnostics = []
    for rules in registry_module.load().values():
        subject_diagnostics.extend(rule.diagnostic for rule in rules)
    check(
        "A6 ни одна диагностика предмета не носит префикс собственного отказа",
        subject_diagnostics
        and not any(name.startswith("CG_SELF_") for name in subject_diagnostics),
        "диагностик предмета %d: %s" % (len(subject_diagnostics), subject_diagnostics),
    )
    return len(parsed or [])


# --- B. Birth inversion по каждому объявленному кейсу ------------------------
def section_cases():
    """Тройка испытуемого равна объявленной приёмкой — у кейсов, которых СПРАШИВАЮТ.

    Посылка секции («колонка `expected_sut` есть утверждение о поведении
    испытуемого») верна не для всех рядов, и это сказано самой приёмкой §14:
    «Три `DRIVER-*` birth fixtures меняют ровно одно поле actual triple». У этих
    рядов колонка — тройка, СКОРМЛЕННАЯ компаратору драйвера, а не ответ
    испытуемого; драйвер их мира испытуемому не передаёт вовсе (замер обёрткой,
    считающей вызовы: у fixture без пина вызовов два — `--capabilities` и
    `--case-world`, у пиновавшей один — только `--capabilities`).

    Ровно поэтому две из трёх таких троек испытуемый НАПЕЧАТАТЬ НЕ МОЖЕТ:
    `GREEN · … · exit 10` и `RED · … · exit 0` невыразимы by construction. Ждать
    их от него значило бы требовать невозможного и объявлять это находкой.

    **Исключение выведено из ФИКСТУРЫ, а не из перечня идентификаторов**: оно
    самоистекает — сними пин из fixture, и кейс вернётся под B1 и обязан будет
    совпасть. Перечень имён здесь не выписывается намеренно: он разошёлся бы с
    деревом молча.
    """
    sys.stdout.write("\n== B. Тройка испытуемого равна объявленной приёмкой ==\n")
    cases = declared_cases()
    if not cases:
        return 0

    asked = []
    pinned = []
    for case_id in cases:
        manifest = fixture_manifest(case_id)
        if manifest.get("sut_stub") is None:
            asked.append(case_id)
        else:
            pinned.append(case_id)

    matched = 0
    for case_id in asked:
        expected = fixture_expectation(case_id)
        completed, lines = run_sut(
            ["--case-world", fixture_world(case_id), "--case", case_id]
        )
        actual = lines[-1] if lines else "(без вывода)"
        match = last_triple(lines)
        agrees = (
            actual == expected
            and match is not None
            and int(match.group(3)) == completed.returncode
        )
        if agrees:
            matched += 1
        else:
            check(
                "B %s" % case_id,
                False,
                "ждали %r, имеем %r (код %d)" % (expected, actual, completed.returncode),
            )
    # Число осмотренных кейсов стоит в ДЕТАЛИ и в итоговой переписи, но НЕ в
    # имени утверждения. Имя, несущее число, меняется от каждого нового
    # семейства, а `selftest/inject.py` перечисляет ожидаемые имена дословно —
    # то есть счёт в имени сталкивал бы параллельные полосы by construction, и
    # столкновение выглядело бы как недоказанная инъекция.
    check(
        "B1 каждый объявленный кейс дал объявленную приёмкой тройку И совпавший "
        "код",
        matched == len(asked),
        "совпало %d из %d" % (matched, len(asked)),
    )

    # Пин обязан быть ТОЙ ЖЕ тройкой, что названа приёмкой: fixture вправе
    # избавить испытуемого от опроса, но не вправе подменить объявленное.
    mismatched_pins = []
    for case_id in pinned:
        pin = fixture_manifest(case_id).get("sut_stub")
        # Пин, не являющийся тройкой, — тоже расхождение, а не повод упасть:
        # проба обязана НАЗВАТЬ находку, а не оборваться на ней.
        if not isinstance(pin, dict) or render_triple(pin) != fixture_expectation(
            case_id
        ):
            mismatched_pins.append(case_id)
    check(
        "B2 скормленная тройка дословно равна объявленной приёмкой",
        not mismatched_pins,
        "разошлись: %s" % (", ".join(mismatched_pins) or "нет"),
    )

    # Причина исключения названа числом, а не прозой: тройка, которую испытуемый
    # напечатать не может, утверждением о его поведении не является.
    impossible = [
        case_id for case_id in pinned
        if not triple_producible(fixture_manifest(case_id)["expected_sut"])
    ]
    check(
        "B3 среди исключённых есть тройки, невыразимые испытуемым by "
        "construction",
        not pinned or impossible,
        "исключено %d, из них невыразимых %d" % (len(pinned), len(impossible)),
    )

    # Исключение обязано быть НЕМАСКИРУЕМЫМ: расширь его — и B перестанет
    # спрашивать испытуемого вовсе, оставаясь зелёной. Поэтому состав
    # исключённых сверяется с ЗАКРЫТЫМ списком самого harness'а — сигналом,
    # который эта секция не производит и потому не может подделать.
    outside_closed_list = sorted(
        set(pinned) - set(harness_fixture_module.STUB_PERMITTED_CASES)
    )
    check(
        "B4 исключены только кейсы из закрытого списка harness'а — "
        "исключение немаскируемо",
        asked and not outside_closed_list,
        "опрошено %d; исключено вне списка: %s"
        % (len(asked), ", ".join(outside_closed_list) or "нет"),
    )

    sys.stdout.write(
        "       перепись B: объявленных кейсов %d · опрошен SUT %d · "
        "тройка скормлена fixture %d (из них невыразимых испытуемым %d)\n"
        % (len(cases), len(asked), len(pinned), len(impossible))
    )
    return len(cases)


# --- C. Вердикт есть функция МИРА, а не идентификатора -----------------------
def section_world_decides():
    sys.stdout.write("\n== C. Решает мир, а не идентификатор кейса ==\n")
    # По паре на объявленное семейство: утверждение проверяется там, где оно
    # может быть неверно. Семейство без своей пары осталось бы доказанным лишь
    # односторонне — матрицей, которая спрашивает «совпала ли тройка» и не
    # спрашивает, ЧТО её произвело; молчание такой матрицы неотличимо от
    # таблицы соответствий «ID -> ответ».
    pairs = [
        ("SDD-1-BOOT-01", "SDD-1-BOOT-02", "CG_BOOTSTRAP_NOT_UNIQUE"),
        ("SDD-1-NONEMPTY-01", "SDD-1-NONEMPTY-02", "CG_ACCEPTANCE_IDS_EMPTY"),
        ("SDD-1-HASH-01", "SDD-1-HASH-03", "CG_APPROVAL_SUBJECT_STALE"),
        ("SDD-1-TRUTH-01", "SDD-1-TRUTH-04", "CG_HUMAN_TASKS_TRACKER"),
        ("SDD-1-ADAPTER-01", "SDD-1-ADAPTER-02", "CGA_DERIVED_DRIFT"),
        ("SDD-1-WIRE-01", "SDD-1-WIRE-02", "CG_CALLER_WORKSPACE_PRE_PUSH_MISSING"),
        # Вызывающие семейства и advisory hook — §13 «Authoritative callers и
        # advisory hooks». У двух первых отрицательный близнец несёт ОДНУ и ту
        # же диагностику, и это не совпадение: приёмка требует от каждого
        # реального caller сохранять UNDERLYING находку графа, а не заводить
        # свою.
        ("SDD-1-WSPP-01", "SDD-1-WSPP-02", "CG_TRACE_ID_MISSING"),
        ("SDD-1-WSCI-01", "SDD-1-WSCI-02", "CG_TRACE_ID_MISSING"),
        ("SDD-1-ADV-01", "SDD-1-ADV-02", "CG_AUTHORITATIVE_GATE_BLOCKED"),
        ("SDD-1-SUPER-01", "SDD-1-SUPER-04", "CG_SUPERSEDE_CYCLE"),
        ("SDD-1-HOLDER-01", "SDD-1-HOLDER-06",
         "CG_HOLDER_SUBJECT_HASH_MISMATCH"),
        ("SDD-1-BIRTH-01", "SDD-1-BIRTH-03", "CG_BIRTH_DEFECT_NOT_DETECTED"),
        ("SDD-1-EVID-01", "SDD-1-EVID-03", "CG_REQUIRED_HOLDER_RED"),
        ("SDD-1-NA-01", "SDD-1-NA-03", "CG_NA_PREDICATE_FALSE"),
        ("SDD-1-TDD-02", "SDD-1-TDD-03", "CG_RED_PROOF_UNEXPECTED_GREEN"),
        ("SDD-1-REVIEW-01", "SDD-1-REVIEW-06", "CG_BOOTSTRAP_ACTOR_SPOOFED"),
        ("SDD-1-AUTH-01", "SDD-1-AUTH-03", "CG_REVIEW_ACTOR_UNAUTHORIZED"),
        ("SDD-1-CLASS-04", "SDD-1-CLASS-05", "CG_CLASS_ITEM_UNMAPPED"),
        ("SDD-1-DESIGN-01", "SDD-1-DESIGN-03", "CG_PRECODE_REVIEW_MISSING"),
        ("SDD-1-CENSUS-01", "SDD-1-CENSUS-03", "CG_CENSUS_STALE"),
        ("SDD-1-POLICY-01", "SDD-1-POLICY-02", "CG_POLICY_REPOSITORY_MISSING"),
        ("SDD-1-DAG-04", "SDD-1-DAG-05", "CG_PACKAGE_REQUIRED_AFTER_CUTOVER"),
        ("SDD-1-DIFF-01", "SDD-1-DIFF-02", "CG_DIFF_PATH_UNCLAIMED"),
        ("SDD-1-PCI-01", "SDD-1-PCI-02", "CG_TRACE_ID_MISSING"),
        ("SDD-1-TRACE-01", "SDD-1-TRACE-03", "CG_TRACE_ID_ORPHAN"),
        ("SDD-1-LIFE-01", "SDD-1-LIFE-02", "CG_LIFECYCLE_TRANSITION_INVALID"),
        ("SDD-1-TASKS-01", "SDD-1-TASKS-02",
         "CG_WRITING_PLANS_HANDOFF_MISSING"),
        ("SDD-1-CONV-01", "SDD-1-CONV-02", "CG_CONVERGENCE_OWNER_UNAUTHORIZED"),
        ("SDD-1-WITHDRAW-01", "SDD-1-WITHDRAW-02", "CG_WITHDRAW_AFTER_LANDING"),
        # У cg.driver это ЕДИНСТВЕННОЕ место, где его правила вообще
        # исполняются: матрица трёх его кейсов испытуемого о мире не
        # спрашивает (см. §B и `cglib/families/driver.py`). Пара взята внутри
        # семейства: мир DRIVER-02 несёт согласованную тройку, мир DRIVER-01 —
        # тройку, чей код не следует из категории.
        ("SDD-1-DRIVER-02", "SDD-1-DRIVER-01", "CG_DRIVER_BIRTH_TRIPLE_INVALID"),
        ("SDD-1-PPRE-01", "SDD-1-PPRE-02", "CG_TRACE_ID_MISSING"),
        ("SDD-1-POST-01", "SDD-1-POST-02", "CG_POST_DIFF_REVIEW_MISSING"),
        ("SDD-1-LAND-01", "SDD-1-LAND-02", "CG_LANDED_CONTENT_DRIFT"),
    ]
    # Перечень ОБЪЯВЛЕН, а не выведен: выведенный шёл бы за деревом и потому
    # молчал бы ровно тогда, когда признак тихо сужается. Цена объявления —
    # оно стареет; поэтому его согласие с деревом проверяется здесь же.
    # Семейство, объявленное испытуемым и не получившее пары, доказано лишь
    # односторонне, и без этой проверки о нём никто не узнал бы: перечень
    # рукописный, а его расхождение с деревом ничем не читалось. Наблюдалось
    # на сведении волны — 7 пар при 9 признаках, и каждая следующая полоса
    # добавляла молчаливый пропуск.
    covered = {registry_module.family_of(positive) for positive, _, _ in pairs}
    orphans = sorted(set(registry_module.load()) - covered)
    check(
        "C0 у каждого объявленного семейства есть своя пара",
        not orphans,
        "без пары: %s" % (", ".join(orphans) or "нет"),
    )
    for positive, negative, diagnostic in pairs:
        _, lines = run_sut(
            ["--case-world", fixture_world(negative), "--case", positive]
        )
        check(
            "C1 %s: дефектный мир под положительным ID даёт %s" % (positive, diagnostic),
            bool(lines) and lines[-1] == "RED · %s · exit 10" % diagnostic,
            "получено %r" % (lines[-1] if lines else None),
        )
        _, lines = run_sut(
            ["--case-world", fixture_world(positive), "--case", negative]
        )
        check(
            "C2-близнец %s: чистый мир под отрицательным ID молчит" % negative,
            bool(lines) and lines[-1] == "GREEN · CG_OK · exit 0",
            "получено %r" % (lines[-1] if lines else None),
        )


# --- D. Собственный отказ НИКОГДА не выдаётся за вердикт ---------------------
def core_class_omitted(name, stderr):
    """Классы отказа ЯДРА, которые разбор показывает, а имя не называет.

    Метку ставит помощник, но ВЫБИРАЕТ помощника автор — и вот этот выбор
    проверяется здесь, по разбору, который печатает само ядро. Иначе «возьми
    своего помощника» осталось бы пожеланием: забывший его получил бы зелёное
    утверждение, выпавшее из выведенного перечня своего класса, и инъекция ядра
    снова отчиталась бы «покраснело лишнее» — тот самый класс, ради которого
    перечни и выводятся.

    Судит разбор, а не диагностика: `CG_SELF_WORLD_NOT_JUDGED` поднимают и ядро,
    и семейство жизненного цикла, и утверждения о них ломаются разными
    инъекциями.
    """
    return sorted(
        mark for detail, mark in CORE_CLASS_BY_DETAIL
        if detail in stderr and mark not in name
    )


def expect_self_failure(name, argv, marker=None, detail=None):
    """Испытуемый не отвечает о предмете: stdout пуст, код 40, разбор назван.

    Метку класса ставит помощник: утверждение проверяет ВЫВОД ИСПЫТУЕМОГО, и
    именно это ломает инъекция, подменяющая собственный отказ вердиктом. Проба,
    зовущая ядро в своём процессе, до run.py не доходит и потому такой метки не
    получает — иначе она попала бы в чужое ожидание и объявила его невыполненным.
    """
    completed, lines = run_sut(argv)
    stdout_empty = not lines
    right_code = completed.returncode == SELF_FAILURE_EXIT
    named = marker is None or marker in completed.stderr
    explained = detail is None or detail in completed.stderr
    omitted = core_class_omitted(name, completed.stderr)
    check(
        "%s %s" % (name, CLASS_SUT_SELF_FAILURE),
        stdout_empty and right_code and named and explained and not omitted,
        "код %d, stdout=%r, класс не назван %s, stderr=%s"
        % (completed.returncode, completed.stdout[:120], omitted,
           completed.stderr.strip()[:240]),
    )


def expect_core_world_not_judged(name, argv):
    """Мир, к которому НИ ОДНО правило семейства не применимо, вердикта не даёт.

    Помощник сверяет не только диагностику, но и разбор ядра: ту же диагностику
    поднимает семейство жизненного цикла на незнакомой стадии, а её утверждения
    роняет другая инъекция. Утверждение, ошибочно взявшее этого помощника,
    покраснеет на разборе — то есть признак класса ЭНФОРСИТСЯ, а не обещается.
    """
    expect_self_failure(
        "%s %s" % (name, CLASS_CORE_WORLD_NOT_JUDGED),
        argv,
        outcome_module.SELF_WORLD_NOT_JUDGED,
        CORE_NOT_JUDGED_DETAIL,
    )


def expect_core_fact_unread(name, argv):
    """Факт мира внутри предмета семейства, не прочитанный ни одним правилом."""
    expect_self_failure(
        "%s %s" % (name, CLASS_CORE_FACT_UNREAD),
        argv,
        outcome_module.SELF_WORLD_FACT_UNREAD,
        CORE_FACT_UNREAD_DETAIL,
    )


def judge_synthetic_subject(subject_keys):
    """Прогон ЯДРА на синтетическом правиле: предмет объявлен, чтения заданы.

    ПРОИЗВОДИТЕЛЬ ВХОДА У ЭТОГО ОТКАЗА ТОЛЬКО ЗДЕСЬ, и это факт дерева, а не
    удобство: ни одно правило ни одного семейства вне своего предмета не
    читает — координаты их чтений записаны литералами, а две динамические
    (`birth_runs.%s`, `event.%s`) верхний сегмент не меняют. Значит подать
    испытуемому такой мир нельзя НИ ОДНОЙ фикстурой: правило пришлось бы
    переписать, то есть внести инъекцию, а инъекция утверждением не является.
    Поэтому ядро зовётся напрямую — и поэтому же метки класса «отказ
    испытуемого» это утверждение не несёт: run.py в нём не участвует.

    Правило объявляет предметом `subject_keys`, а читает ОБЕ координаты мира.
    Сузив объявление, получаем чтение вне предмета; объявив обе — законного
    близнеца, на котором ядро обязано молчать.
    """
    def predicate(world):
        world.read("own")
        world.read("foreign")
        return False

    rule = rules_module.Rule(
        rule_id="probe.subject-boundary",
        diagnostic="CG_PROBE_SUBJECT_BOUNDARY",
        subject_keys=subject_keys,
        requires=("own",),
        predicate=predicate,
        why="проба границы предмета: правило читает шире, чем объявило",
    )
    world = world_module.World({"own": "значение", "foreign": "значение"})
    return rules_module.evaluate("probe", [rule], world)


def expect_core_read_outside_subject(name, subject_keys, coordinate):
    """Правило прочитало вне предмета семейства — ядро вердикта не выносит.

    Предмет — собственный отказ `CG_SELF_RULE_READ_OUTSIDE_SUBJECT`. Диагностика
    названа в комментарии, а сверяется по константе: комментарий у проверки
    обязан называть то, что она стережёт, иначе её снимут как непонятную, — а
    вторая исполняемая копия строки разошлась бы со словарём молча.

    Проверяется не только диагностика, но и то, что отказ НАЗЫВАЕТ прочитанную
    координату: без неё читатель прогона знает, что вердикта нет, и не знает,
    какое чтение его отняло.
    """
    raised = None
    try:
        judge_synthetic_subject(subject_keys)
    except outcome_module.SelfFailure as failure:
        raised = failure
    check(
        "%s %s" % (name, CLASS_CORE_READ_OUTSIDE_SUBJECT),
        raised is not None
        and raised.diagnostic == outcome_module.SELF_RULE_READ_OUTSIDE_SUBJECT
        and coordinate in raised.detail,
        "поднято %r"
        % ((raised.diagnostic, raised.detail) if raised is not None else None,),
    )


def expect_subject_verdict(name, argv):
    completed, lines = run_sut(argv)
    match = last_triple(lines)
    check(
        name,
        match is not None
        and completed.returncode in SUBJECT_EXIT_CODES
        and int(match.group(3)) == completed.returncode,
        "код %d, stdout=%r" % (completed.returncode, completed.stdout[:200]),
    )


def section_self_failure(work):
    sys.stdout.write(
        "\n== D. Собственный отказ отделён от отказа предмета, обе стороны ==\n"
    )
    expect_self_failure(
        "D1 мира по пути нет -> собственный отказ, stdout пуст",
        ["--case-world", os.path.join(work, "нет-такого.yaml"),
         "--case", "SDD-1-BOOT-01"],
        "CG_SELF_WORLD_UNREADABLE",
    )

    broken = os.path.join(work, "broken.yaml")
    with open(broken, "w", encoding="utf-8") as handle:
        handle.write("не: [YAML\n  - и не\n")
    expect_self_failure(
        "D2 мир не разбирается как YAML -> собственный отказ",
        ["--case-world", broken, "--case", "SDD-1-BOOT-01"],
        "CG_SELF_WORLD_MALFORMED",
    )

    not_mapping = write_world(work, "not-mapping.yaml", ["не", "отображение"])
    expect_self_failure(
        "D3 мир не отображение -> собственный отказ",
        ["--case-world", not_mapping, "--case", "SDD-1-BOOT-01"],
        "CG_SELF_WORLD_MALFORMED",
    )

    expect_self_failure(
        "D4 идентификатор кейса не разбирается -> собственный отказ",
        ["--case-world", fixture_world("SDD-1-BOOT-01"), "--case", "не-кейс"],
        "CG_SELF_CASE_ID_UNPARSEABLE",
    )

    expect_self_failure(
        "D5 семейство кейса не объявлено -> собственный отказ, НЕ вердикт",
        ["--case-world", fixture_world("SDD-1-BOOT-01"), "--case", "SDD-1-NOSUCH-01"],
        "CG_SELF_FAMILY_UNDECLARED",
    )

    expect_self_failure(
        "D6 без обязательных аргументов -> собственный отказ",
        ["--case", "SDD-1-BOOT-01"],
        "CG_SELF_USAGE",
    )

    # Нулевая перепись не может дать GREEN: мир, к которому не применимо ни одно
    # правило семейства, вердикта не получает вовсе.
    inactive = yaml.safe_load(open(fixture_world("SDD-1-NONEMPTY-01"), encoding="utf-8"))
    inactive["package_state"] = "archived"
    inactive_path = write_world(work, "inactive.yaml", inactive)
    expect_core_world_not_judged(
        "D7 ни одно правило не применимо -> собственный отказ, а НЕ vacuous GREEN",
        ["--case-world", inactive_path, "--case", "SDD-1-NONEMPTY-01"],
    )
    expect_subject_verdict(
        "D7-близнец тот же мир в состоянии active даёт вердикт о предмете",
        ["--case-world", fixture_world("SDD-1-NONEMPTY-01"), "--case",
         "SDD-1-NONEMPTY-01"],
    )

    # Факт мира внутри предмета семейства, который не прочитало ни одно
    # применимое правило, делает вердикт заявлением шире осмотренного.
    unread = yaml.safe_load(open(fixture_world("SDD-1-HASH-01"), encoding="utf-8"))
    unread["design_content_digest"] = "sha256:fixture-design-v1"
    unread_path = write_world(work, "unread.yaml", unread)
    expect_core_fact_unread(
        "D8 непрочитанный факт внутри предмета -> собственный отказ",
        ["--case-world", unread_path, "--case", "SDD-1-HASH-01"],
    )
    expect_subject_verdict(
        "D8-близнец тот же мир без лишнего факта даёт вердикт о предмете",
        ["--case-world", fixture_world("SDD-1-HASH-01"), "--case", "SDD-1-HASH-01"],
    )

    # Связь роли вердикта с artifact выводится из имени — и потому обязана быть
    # ГРОМКОЙ: неразрешимая роль не пропускается молча.
    stray = yaml.safe_load(open(fixture_world("SDD-1-HASH-01"), encoding="utf-8"))
    stray["approval_bound_subject"]["mystery"] = "sha256:fixture-design-v1"
    stray_path = write_world(work, "stray-role.yaml", stray)
    expect_self_failure(
        "D9 роль вердикта не приводится к artifact -> собственный отказ",
        ["--case-world", stray_path, "--case", "SDD-1-HASH-01"],
        "CG_SELF_APPROVAL_ROLE_UNRESOLVED",
    )
    resolvable = yaml.safe_load(open(fixture_world("SDD-1-HASH-01"), encoding="utf-8"))
    resolvable["approval_bound_subject"]["design-reviewer"] = (
        "sha256:fixture-design-v1"
    )
    resolvable_path = write_world(work, "resolvable-role.yaml", resolvable)
    expect_subject_verdict(
        "D9-близнец разрешимая роль даёт вердикт о предмете",
        ["--case-world", resolvable_path, "--case", "SDD-1-HASH-01"],
    )

    # Третий собственный отказ ядра. Он ловит правило, которое вынесло бы
    # суждение о том, чего его семейство не касается: предмет объявлен, а
    # прочитано шире объявленного. До этой пары отказ не был проверен НИЧЕМ —
    # снятие его ветви не роняло ни одного утверждения (перемерено: код 0,
    # находок 0), то есть он мог быть мёртв, и заметить это было неоткуда:
    # собственный отказ печатает на stdout ноль строк, поэтому его отсутствие
    # неотличимо от его молчания.
    expect_core_read_outside_subject(
        "D10 правило прочитало вне объявленного предмета -> собственный отказ, "
        "а НЕ вердикт о том, чего семейство не касается",
        ("own",),
        "foreign",
    )
    # Законный близнец: то же чтение, но предмет объявлен целиком. Без него
    # D10 зеленело бы и на ядре, которое отвергает ВСЯКОЕ чтение, — то есть
    # утверждало бы форму отказа, а не его существо.
    twin_verdict = None
    twin_census = None
    twin_failure = None
    try:
        twin_verdict, twin_census = judge_synthetic_subject(("own", "foreign"))
    except outcome_module.SelfFailure as failure:
        twin_failure = failure
    check(
        "D10-близнец то же чтение при объявленном предмете даёт вердикт, а "
        "прочитанным считается ровно осмотренное",
        twin_failure is None
        and twin_verdict == outcome_module.green()
        and twin_census.facts_read == 2
        and twin_census.facts_outside == 0,
        "отказ %r; вердикт %r; прочитано %r; вне предмета %r"
        % (
            twin_failure and twin_failure.diagnostic,
            twin_verdict and twin_verdict.render(),
            twin_census and twin_census.facts_read,
            twin_census and twin_census.facts_outside,
        ),
    )

    # Признак класса ЭНФОРСИТСЯ, а не обещается. Разбор берётся ЖИВЫМ прогоном:
    # выписанная сюда строка была бы вторым местом об одном предмете и разошлась
    # бы с ядром молча — а расхождение здесь означает, что дискриминатор
    # перестал срабатывать, то есть перечень класса тихо усох.
    # Метку класса эти двое несут САМИ, и это не оговорка, а следствие: их вход
    # производит та же ветвь ядра, поэтому её снятие обязано их ронять — как
    # роняет D7 и якоря вызывающих. Помощника у них нет (они судят не вывод
    # испытуемого, а дискриминатор), значит класс объявляет автор; проверено
    # опытом — без метки инъекция ядра отчитывалась о них «покраснело лишнее».
    core_refusal, _ = run_sut(
        ["--case-world", inactive_path, "--case", "SDD-1-NONEMPTY-01"]
    )
    check(
        "D11 отказ ЯДРА при имени без метки класса — находка, а не молчание %s"
        % CLASS_CORE_WORLD_NOT_JUDGED,
        core_class_omitted("утверждение без метки", core_refusal.stderr)
        == [CLASS_CORE_WORLD_NOT_JUDGED],
        "разбор=%s" % core_refusal.stderr.strip()[:240],
    )
    check(
        "D11-близнец тот же разбор при названном классе находкой не является %s"
        % CLASS_CORE_WORLD_NOT_JUDGED,
        core_class_omitted(
            "утверждение %s" % CLASS_CORE_WORLD_NOT_JUDGED, core_refusal.stderr
        )
        == [],
        "разбор=%s" % core_refusal.stderr.strip()[:240],
    )
    # Второй близнец, и он несущий: ту же диагностику поднимает СЕМЕЙСТВО
    # жизненного цикла на стадии, которой нет в его таблице. Её утверждения
    # роняет другая инъекция, поэтому дискриминатор обязан на ней МОЛЧАТЬ —
    # иначе классы слились бы, и два ожидания стали бы одним.
    family_stage = yaml.safe_load(
        open(fixture_world("SDD-1-LIFE-01"), encoding="utf-8")
    )
    family_stage["stage"] = "IMPLEMENTING"
    family_stage["requested_transition"] = "CONVERGED"
    family_refusal, _ = run_sut(
        ["--case-world", write_world(work, "life-family-refusal.yaml", family_stage),
         "--case", "SDD-1-LIFE-01"],
    )
    check(
        "D11-близнец-2 ту же диагностику от СЕМЕЙСТВА дискриминатор классом "
        "ядра не объявляет",
        outcome_module.SELF_WORLD_NOT_JUDGED in family_refusal.stderr
        and core_class_omitted("утверждение без метки", family_refusal.stderr) == [],
        "разбор=%s" % family_refusal.stderr.strip()[:240],
    )


# --- E. Перепись объёма ------------------------------------------------------
def section_census():
    sys.stdout.write("\n== E. Перепись объёма осмотренного ==\n")
    completed, _ = run_sut(
        ["--case-world", fixture_world("SDD-1-BOOT-01"), "--case", "SDD-1-BOOT-01"]
    )
    check(
        "E1 на чистом мире перепись всё равно печатается",
        "фактов мира" in completed.stderr and "прочитано" in completed.stderr,
        "stderr=%s" % completed.stderr.strip()[:240],
    )
    completed, _ = run_sut(
        ["--case-world", fixture_world("SDD-1-HASH-05"), "--case", "SDD-1-HASH-05"]
    )
    check(
        "E2 факты вне предмета семейства названы поимённо",
        "вне предмета cg.hash" in completed.stderr
        and "exposure_items" in completed.stderr,
        "stderr=%s" % completed.stderr.strip()[:400],
    )
    completed, lines = run_sut(
        ["--case-world", fixture_world("SDD-1-HASH-04"), "--case", "SDD-1-HASH-04"]
    )
    check(
        "E3 при двух нарушениях назван порядок, по которому взят вердикт",
        "нарушений 2" in completed.stderr
        and "по первому нарушению в объявленном порядке" in completed.stderr
        and lines[-1] == "RED · CG_DOWNSTREAM_STALE_FROM_ACCEPTANCE · exit 10",
        "stderr=%s" % completed.stderr.strip()[:400],
    )


# --- F. Парность правил и объявленный порядок -------------------------------
def _judge(case_id):
    """Прогон испытуемого на мире кейса. Возвращает (stderr, последняя строка)."""
    completed, lines = run_sut(
        ["--case-world", fixture_world(case_id), "--case", case_id]
    )
    return completed.stderr, (lines[-1] if lines else "(без вывода)")


def section_rule_pairing():
    """Что B спросить НЕ МОЖЕТ: какое правило дало вердикт и почему именно оно.

    B сверяет тройку и слепо к тому, чем она получена: тройка сошлась бы и у
    правила, срабатывающего на всём подряд. Здесь спрашивается перепись —
    ИМЕНА сработавших правил, — поэтому «правило есть» отличимо от «правило
    судит», а объявленный порядок отличим от порядка, получившегося случайно.
    """
    # Перечня семейств в заголовке нет НАМЕРЕННО: он был бы вторым местом об
    # одном предмете и старел бы от каждой новой полосы молча — перечисление
    # «holder/birth/evid/na» пережило появление diff и pci ровно так, как этот
    # класс и описан в корпусе. Что здесь проверяется, видно по именам
    # утверждений, и они выводятся из самих проверок, а не из заголовка.
    sys.stdout.write("\n== F. Парность правил и объявленный порядок ==\n")

    # Тривиальная команда незарегистрирована и потому краснит ОБА правила об
    # executable. Вердикт обязан быть взят по объявленному порядку, а не по
    # тому, какое сработало первым случайно.
    stderr, verdict = _judge("SDD-1-HOLDER-03")
    check(
        "F-HOLDER-1 на команде true краснеют оба правила, вердикт — по "
        "объявленному порядку",
        "нарушений 2" in stderr
        and "holder.executable-trivial" in stderr
        and "holder.executable-unregistered" in stderr
        and "по первому нарушению в объявленном порядке: "
            "holder.executable-trivial" in stderr
        and verdict == "RED · CG_HOLDER_EXECUTABLE_TRIVIAL · exit 10",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )
    # Близнец: без него F-HOLDER-1 зеленел бы на правиле, краснящем на всякой
    # команде вообще.
    stderr, verdict = _judge("SDD-1-HOLDER-04")
    check(
        "F-HOLDER-2-близнец на незарегистрированной команде краснеет только "
        "правило о ней",
        "нарушений 1" in stderr
        and "holder.executable-unregistered" in stderr
        and "holder.executable-trivial" not in stderr
        and verdict == "RED · CG_HOLDER_EXECUTABLE_UNKNOWN · exit 10",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )

    # Ядро замысла рождения: держатель, который краснеет на всём, и держатель,
    # который зелен на всём, — РАЗНЫЕ дефекты, и каждое правило ловит ровно тот,
    # который второе пропускает. Ни одно поодиночке их не различает.
    stderr, verdict = _judge("SDD-1-BIRTH-02")
    check(
        "F-BIRTH-1 держателя, краснеющего на всём, ловит правило known-good — и "
        "только оно",
        "нарушений 1" in stderr
        and "birth.known-good-failed" in stderr
        and "birth.defect-not-detected" not in stderr
        and verdict == "RED · CG_BIRTH_GOOD_INPUT_FAILED · exit 10",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )
    stderr, verdict = _judge("SDD-1-BIRTH-03")
    check(
        "F-BIRTH-2 держателя, зелёного на всём, ловит правило injected defect — "
        "и только оно",
        "нарушений 1" in stderr
        and "birth.defect-not-detected" in stderr
        and "birth.known-good-failed" not in stderr
        and verdict == "RED · CG_BIRTH_DEFECT_NOT_DETECTED · exit 10",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )
    stderr, verdict = _judge("SDD-1-BIRTH-01")
    check(
        "F-BIRTH-3-близнец держатель, показавший ОБА исхода, рождён: нарушений 0",
        "нарушений 0" in stderr and verdict == "GREEN · CG_OK · exit 0",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )

    # «Не выполнилось» не подменяется красным и наоборот: обе стороны сразу,
    # иначе утверждение зеленело бы на семействе, отвечающем одной категорией.
    stderr, verdict = _judge("SDD-1-EVID-04")
    check(
        "F-EVID-1 неисполненный держатель даёт NOT_EXECUTED, а не RED",
        verdict == "NOT_EXECUTED · CG_REQUIRED_HOLDER_NOT_EXECUTED · exit 20",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )
    stderr, verdict = _judge("SDD-1-EVID-03")
    check(
        "F-EVID-2-близнец держатель, ответивший RED, даёт RED, а не NOT_EXECUTED",
        verdict == "RED · CG_REQUIRED_HOLDER_RED · exit 10",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )
    # Граница предмета названа переписью, а не подразумевается: трассу design и
    # tasks судит семейство трассы, birth-запись драйвера — его собственное.
    stderr, verdict = _judge("SDD-1-EVID-02")
    check(
        "F-EVID-3 не судимые этим семейством координаты названы переписью "
        "поимённо",
        "вне предмета cg.evid" in stderr
        and "design_ids" in stderr
        and "tasks_ids" in stderr
        and "driver_birth.actual_triple" in stderr,
        "stderr=%s" % stderr.strip()[:400],
    )

    # Незарегистрированный предикат вычислять не над чем — одна находка не
    # предъявляется двумя диагностиками.
    stderr, verdict = _judge("SDD-1-NA-02")
    check(
        "F-NA-1 незарегистрированный предикат даёт ОДНУ находку, а не две",
        "нарушений 1" in stderr
        and "na.predicate-unregistered" in stderr
        and "na.predicate-false" not in stderr
        and verdict == "RED · CG_NA_PREDICATE_UNREGISTERED · exit 10",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )
    stderr, verdict = _judge("SDD-1-NA-03")
    check(
        "F-NA-2-близнец зарегистрированный, но невыполненный предикат краснит "
        "правило о evidence",
        "нарушений 1" in stderr
        and "na.predicate-false" in stderr
        and "na.predicate-unregistered" not in stderr
        and verdict == "RED · CG_NA_PREDICATE_FALSE · exit 10",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )

    # cg.dag: две ветви §8, у которых среди fixtures НЕТ отрицательного мира.
    # DAG-01 — единственный pre-cutover мир, и он предъявляет registered legacy;
    # DAG-02/03 — единственные миры с exact-mapping, и оно там истинно. Ветвь,
    # у которой нет производителя входа, неотличима от мёртвой: она не краснеет
    # и не зеленеет, она молчит. Производитель заводится здесь — миром, собранным
    # на месте, — и рядом ставится законный близнец, отличающийся ОДНИМ фактом:
    # без него утверждение зеленело бы на правиле, краснящем на всём подряд.
    # Идентификатор кейса тут вторичен намеренно: он выбирает семейство, а
    # отвечает мир.
    with tempfile.TemporaryDirectory(prefix="cg-dag-") as dag_work:
        base_of_pre_cutover = {
            "candidate": {
                "repo": "PRO-Robotech/kacho-workspace",
                "base_sha": "1" * 40,
                "head_sha": "2" * 40,
            },
            "cutover_commit": "0123456789abcdef0123456789abcdef01234567",
            "relation": "base-is-ancestor-of-cutover",
            "registered_route": "migrate",
            "legacy_registry": {"PRO-Robotech/kacho-workspace#400": "legacy"},
            "package_present": False,
        }
        path = write_world(dag_work, "dag-off-legacy.yaml", base_of_pre_cutover)
        completed, lines = run_sut(
            ["--case-world", path, "--case", "SDD-1-DAG-01"]
        )
        check(
            "F-DAG-1 pre-cutover без registered legacy route требует package",
            bool(lines)
            and lines[-1] == "RED · CG_PACKAGE_REQUIRED_AT_CUTOVER · exit 10"
            and "dag.package-required-at-cutover" in completed.stderr,
            "вердикт %r; stderr=%s"
            % (lines[-1] if lines else None, completed.stderr.strip()[:400]),
        )
        twin_of_pre_cutover = dict(base_of_pre_cutover, registered_route="legacy")
        path = write_world(dag_work, "dag-on-legacy.yaml", twin_of_pre_cutover)
        _, lines = run_sut(["--case-world", path, "--case", "SDD-1-DAG-01"])
        check(
            "F-DAG-2-близнец тот же pre-cutover мир с registered legacy route "
            "молчит",
            bool(lines) and lines[-1] == "GREEN · CG_OK · exit 0",
            "получено %r" % (lines[-1] if lines else None),
        )

        cutover_sha = "0123456789abcdef0123456789abcdef01234567"
        base_at_boundary = {
            "candidate": {
                "repo": "PRO-Robotech/kacho-workspace",
                "base_sha": cutover_sha,
                "head_sha": "2" * 40,
            },
            "cutover_commit": cutover_sha,
            "relation": "base-equals-cutover",
            "package_present": True,
            "package_diff_exact_mapped": False,
        }
        path = write_world(dag_work, "dag-package-not-exact.yaml", base_at_boundary)
        completed, lines = run_sut(
            ["--case-world", path, "--case", "SDD-1-DAG-02"]
        )
        check(
            "F-DAG-3 package, не отображающий diff точно, требования границы не "
            "удовлетворяет",
            bool(lines)
            and lines[-1] == "RED · CG_PACKAGE_REQUIRED_AT_CUTOVER · exit 10"
            and "dag.package-required-at-cutover" in completed.stderr,
            "вердикт %r; stderr=%s"
            % (lines[-1] if lines else None, completed.stderr.strip()[:400]),
        )
        twin_at_boundary = dict(base_at_boundary, package_diff_exact_mapped=True)
        path = write_world(dag_work, "dag-package-exact.yaml", twin_at_boundary)
        _, lines = run_sut(["--case-world", path, "--case", "SDD-1-DAG-02"])
        check(
            "F-DAG-4-близнец тот же мир с exact-mapped package молчит",
            bool(lines) and lines[-1] == "GREEN · CG_OK · exit 0",
            "получено %r" % (lines[-1] if lines else None),
        )
    # Владение и сходимость — разные предметы, и лишний фактический путь
    # нарушает ОБА сразу: его не заявлял никто, и в отрецензированном наборе его
    # быть не могло. Вердикт обязан браться по объявленному порядку (владение
    # раньше сходимости), а не по тому, какое правило сработало первым случайно.
    stderr, verdict = _judge("SDD-1-DIFF-02")
    check(
        "F-DIFF-1 незаявленный путь краснит владение И сходимость, вердикт — "
        "по объявленному порядку",
        "нарушений 2" in stderr
        and "diff.path-unclaimed" in stderr
        and "diff.reviewed-set-mismatch" in stderr
        and "по первому нарушению в объявленном порядке: "
            "diff.path-unclaimed" in stderr
        and verdict == "RED · CG_DIFF_PATH_UNCLAIMED · exit 10",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )
    # Близнец: без него F-DIFF-1 зеленел бы на правиле владения, краснящем на
    # всяком мире вообще. Здесь заявка и дерево совпадают, а разошлась ТОЛЬКО
    # рецензия — краснеть обязано ровно правило сходимости.
    stderr, verdict = _judge("SDD-1-DIFF-05")
    check(
        "F-DIFF-2-близнец при дрейфе одной рецензии краснеет только правило "
        "сходимости",
        "нарушений 1" in stderr
        and "diff.reviewed-set-mismatch" in stderr
        and "diff.path-unclaimed" not in stderr
        and verdict == "RED · CG_REVIEWED_DIFF_SET_MISMATCH · exit 10",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )

    # Правило о GitHub event читает ЗАПИСЬ целиком (отсутствующую координату не
    # прочитать), и это чтение не вправе цеплять чужие находки: краснеть обязано
    # ровно оно одно.
    stderr, verdict = _judge("SDD-1-PCI-05")
    check(
        "F-PCI-1 событие без base краснит ровно правило о base, чтение записи "
        "целиком чужих находок не порождает",
        "нарушений 1" in stderr
        and "pci.base-ref-missing" in stderr
        and verdict == "NOT_EXECUTED · CG_PRODUCT_CI_BASE_REF_MISSING · exit 20",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )
    # Близнец: без него F-PCI-1 зеленел бы на правиле, краснящем на всяком
    # событии. Здесь событие полное, а снят change_id — «не выполнилось» не
    # подменяет красного и наоборот.
    stderr, verdict = _judge("SDD-1-PCI-06")
    check(
        "F-PCI-2-близнец при полном событии правило о base молчит, а ledger "
        "даёт RED, а не NOT_EXECUTED",
        "нарушений 1" in stderr
        and "pci.ledger-change-id-missing" in stderr
        and "pci.base-ref-missing" not in stderr
        and verdict == "RED · CG_PRODUCT_LEDGER_CHANGE_ID_MISSING · exit 10",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )
    # Допуск лица и допуск роли — РАЗНЫЕ находки, и различить их может только
    # пара: мир, где лицо чужое при верной роли, и мир, где лицо своё при чужой
    # роли. Правило, срабатывающее на обоих, «работало» бы одинаково зелено в
    # матрице — она сверяет тройку и слепа к тому, чем тройка получена.
    stderr, verdict = _judge("SDD-1-AUTH-03")
    check(
        "F-AUTH-1 чужой actor при верной роли краснит только правило о допуске",
        "нарушений 1" in stderr
        and "auth.actor-allowed" in stderr
        and "auth.role-authorized" not in stderr
        and verdict == "RED · CG_REVIEW_ACTOR_UNAUTHORIZED · exit 10",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )
    stderr, verdict = _judge("SDD-1-AUTH-07")
    check(
        "F-AUTH-2-близнец допущенный actor при чужой роли краснит только "
        "правило о роли",
        "нарушений 1" in stderr
        and "auth.role-authorized" in stderr
        and "auth.actor-allowed" not in stderr
        and verdict == "RED · CG_REVIEW_ROLE_UNAUTHORIZED · exit 10",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )
    # «Не выполнилось» этого семейства: недоступный API не есть находка о
    # предмете. Обратная сторона утверждения стоит выше — F-AUTH-1 и F-AUTH-2
    # показывают, что то же семейство умеет отвечать краснотой; без них это
    # зеленело бы и на семействе, отвечающем одним лишь NOT_EXECUTED.
    stderr, verdict = _judge("SDD-1-AUTH-08")
    check(
        "F-AUTH-3 недоступный API даёт NOT_EXECUTED, а не RED",
        "нарушений 1" in stderr
        and "auth.api-available" in stderr
        and verdict == "NOT_EXECUTED · CG_REVIEW_API_UNAVAILABLE · exit 20",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )
    section_trace_life_tasks_pairing()


# --- F (продолжение). Полосы трассы, жизненного цикла и задач ----------------
def section_trace_life_tasks_pairing():
    """То же, что F выше, для cg.trace / cg.life / cg.tasks.

    Три диагностики трассы производит ОДИН и тот же вид мира — набор
    идентификаторов, — поэтому «тройка сошлась» ещё не значит, что различение
    направлений живо: правило, краснящее на всяком расхождении, дало бы ту же
    тройку на своём кейсе и молчаливо неверную на соседнем. Здесь спрашивается
    перепись — ИМЕНА сработавших правил, — чего матрица спросить не может.

    Отдельно доказывается способность упасть у тех правил, под которые в
    приёмке нет отрицательного кейса: держатели одного ID. Без синтетического
    входа они были бы правилами, зелёными по построению.
    """
    sys.stdout.write(
        "\n== F (продолжение). Полосы трассы, жизненного цикла и задач ==\n"
    )

    def judge_world(path, case_id):
        completed, lines = run_sut(["--case-world", path, "--case", case_id])
        return completed.stderr, (lines[-1] if lines else "(без вывода)")

    # Направление расхождения, а не его мощность: набор, потерявший ОДИН ID и
    # добавивший ОДИН чужой, обязан назваться двусторонним расхождением, и
    # односторонние правила при этом обязаны молчать.
    stderr, verdict = _judge("SDD-1-TRACE-04")
    check(
        "F-TRACE-1 двустороннее расхождение краснит только своё правило",
        "нарушений 1" in stderr
        and "trace.downstream-set-mismatch" in stderr
        and "trace.downstream-id-missing" not in stderr
        and "trace.downstream-id-orphan" not in stderr
        and verdict == "RED · CG_TRACE_SET_MISMATCH · exit 10",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )
    # Близнец: без него F-TRACE-1 зеленел бы на правиле, краснящем на всяком
    # расхождении вообще.
    stderr, verdict = _judge("SDD-1-TRACE-02")
    check(
        "F-TRACE-2-близнец односторонняя потеря краснит только правило о потере",
        "нарушений 1" in stderr
        and "trace.downstream-id-missing" in stderr
        and "trace.downstream-set-mismatch" not in stderr
        and "trace.downstream-id-orphan" not in stderr
        and verdict == "RED · CG_TRACE_ID_MISSING · exit 10",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )

    # Граница предмета названа переписью, а не подразумевается, и названа
    # ИЗМЕРЕННО: координата ровно одна и она поимённая. Утверждение о числе
    # стоит рядом с именем намеренно — без него «названа поимённо» осталось бы
    # верным и на мире, где вне предмета оказались бы заодно и множества
    # идентификаторов, то есть при молчаливо сузившемся предмете трассы.
    stderr, verdict = _judge("SDD-1-TRACE-01")
    check(
        "F-TRACE-3 вне предмета трассы ровно одна координата и она названа",
        "вне предмета семейства 1" in stderr
        and "вне предмета cg.trace (судит другое семейство): "
            "driver_birth.actual_triple" in stderr
        and verdict == "GREEN · CG_OK · exit 0",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )

    with tempfile.TemporaryDirectory(prefix="cg-selftest-tlt-") as work:
        # У полосы держателей отрицательного кейса в приёмке нет: §9 объявляет
        # разрешение («одному ID разрешены несколько независимых holders»), а
        # не запрет. Правило без синтетического входа осталось бы зелёным по
        # построению, поэтому вход подаётся здесь.
        holderless = yaml.safe_load(
            open(fixture_world("SDD-1-TRACE-05"), encoding="utf-8")
        )
        holderless["holders_for_id"] = {}
        stderr, verdict = judge_world(
            write_world(work, "trace-no-holder.yaml", holderless),
            "SDD-1-TRACE-05",
        )
        check(
            "F-TRACE-4 объявленный ID без единого держателя — находка",
            "trace.id-without-holder" in stderr
            and verdict == "RED · CG_TRACE_ID_MISSING · exit 10",
            "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
        )

        collapsed = yaml.safe_load(
            open(fixture_world("SDD-1-TRACE-05"), encoding="utf-8")
        )
        holders = collapsed["holders_for_id"]
        shared = holders[sorted(holders)[0]]
        for name in holders:
            holders[name] = shared
        stderr, verdict = judge_world(
            write_world(work, "trace-collapsed.yaml", collapsed),
            "SDD-1-TRACE-05",
        )
        check(
            "F-TRACE-5 два держателя на одной координате доказательства — "
            "находка",
            "trace.holder-evidence-not-own" in stderr
            and verdict
            == "RED · CG_HOLDER_EVIDENCE_COORDINATE_MISSING · exit 10",
            "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
        )
        # Близнец обеих находок: тот же мир нетронутым обязан молчать, иначе
        # обе предыдущие проверки зеленели бы на правилах, краснящих на всём.
        stderr, verdict = _judge("SDD-1-TRACE-05")
        check(
            "F-TRACE-6-близнец два независимо названных держателя с раздельным "
            "доказательством сохранены: нарушений 0",
            "нарушений 0" in stderr and verdict == "GREEN · CG_OK · exit 0",
            "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
        )

        # Жизненный цикл: состоятельность текущей стадии и законность шага —
        # разные находки, и каждая обязана краснить своё правило, а не оба.
        stderr, verdict = _judge("SDD-1-LIFE-03")
        check(
            "F-LIFE-1 нехватка артефакта краснит только правило об артефактах",
            "нарушений 1" in stderr
            and "life.required-artifact-missing" in stderr
            and "life.transition-not-adjacent" not in stderr
            and verdict == "RED · CG_REQUIRED_ARTIFACT_MISSING · exit 10",
            "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
        )
        stderr, verdict = _judge("SDD-1-LIFE-02")
        check(
            "F-LIFE-2-близнец пропуск обязательной стадии краснит только "
            "правило о смежности",
            "нарушений 1" in stderr
            and "life.transition-not-adjacent" in stderr
            and "life.required-artifact-missing" not in stderr
            and verdict == "RED · CG_LIFECYCLE_TRANSITION_INVALID · exit 10",
            "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
        )
        # §5 называет WITHDRAWN и SUPERSEDED БОКОВЫМИ состояниями: они лежат вне
        # линейной цепочки, и мерить их шагом по ней значило бы отвергать то,
        # что приёмка разрешает. Пара с F-LIFE-2 показывает, что правило
        # отличает боковое состояние от пропуска, а не пропускает всё подряд.
        aside = yaml.safe_load(
            open(fixture_world("SDD-1-LIFE-01"), encoding="utf-8")
        )
        aside["requested_transition"] = "WITHDRAWN"
        stderr, verdict = judge_world(
            write_world(work, "life-aside.yaml", aside), "SDD-1-LIFE-01"
        )
        check(
            "F-LIFE-3 боковое терминальное состояние не судится смежностью",
            "нарушений 0" in stderr and verdict == "GREEN · CG_OK · exit 0",
            "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
        )
        # Стадия, для которой перечень обязательного не объявлен, — «не знаю», и
        # оно никогда не выдаётся за «нет»: вердикта о предмете нет вовсе.
        unknown_stage = yaml.safe_load(
            open(fixture_world("SDD-1-LIFE-01"), encoding="utf-8")
        )
        unknown_stage["stage"] = "IMPLEMENTING"
        unknown_stage["requested_transition"] = "CONVERGED"
        expect_self_failure(
            "F-LIFE-4 стадия без объявленного перечня -> собственный отказ, а "
            "НЕ vacuous GREEN",
            ["--case-world",
             write_world(work, "life-unknown-stage.yaml", unknown_stage),
             "--case", "SDD-1-LIFE-01"],
            "CG_SELF_WORLD_NOT_JUDGED",
        )

    # Задачи: порядок и производитель — разные находки. Без пары «порядок»
    # зеленел бы на правиле, краснящем на всяком мире с задачами.
    stderr, verdict = _judge("SDD-1-TASKS-03")
    check(
        "F-TASKS-1 задачи до утверждения design краснят только правило о порядке",
        "нарушений 1" in stderr
        and "tasks.before-design-approval" in stderr
        and "tasks.writing-plans-handoff-missing" not in stderr
        and verdict == "RED · CG_TASKS_BEFORE_DESIGN_APPROVAL · exit 10",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )
    stderr, verdict = _judge("SDD-1-TASKS-02")
    check(
        "F-TASKS-2-близнец отсутствие проверенного handoff краснит только "
        "правило о производителе",
        "нарушений 1" in stderr
        and "tasks.writing-plans-handoff-missing" in stderr
        and "tasks.before-design-approval" not in stderr
        and verdict == "RED · CG_WRITING_PLANS_HANDOFF_MISSING · exit 10",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )


# --- G. Вызывающие семейства и advisory hook --------------------------------
def _world_of(case_id):
    """Копия мира фикстуры, пригодная к правке."""
    with open(fixture_world(case_id), encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def _verdict_at(path, case_id):
    _, lines = run_sut(["--case-world", path, "--case", case_id])
    return lines[-1] if lines else "(без вывода)"


def section_callers_and_advisory(work):
    """Что B и C спросить НЕ МОГУТ: знаки предикатов, которых нет в фикстурах.

    Фикстуры этих трёх семейств предъявляют по одному знаку на правило, и
    молчание остальных знаков неотличимо от их отсутствия: правило, не
    предъявленное ни одной фикстурой, мёртвым и рабочим выглядит одинаково.
    Здесь спрашивается ровно то, чего в фикстурах нет, — второй знак advisory,
    половина предиката о четырёх вызывающих, правило о local SHA, нулевая
    перепись mapping — и главное: что вердикт о mapping есть функция СТРУКТУРЫ
    поданного, а не совпадения с идентификатором кейса.
    """
    sys.stdout.write(
        "\n== G. Вызывающие и advisory: знаки, которых нет в фикстурах ==\n"
    )

    # --- cg.adv: вердикт не меняется от advisory НИ В ОДНУ сторону -----------
    # Фикстуры дают только advisory=GREEN (ADV-01, ADV-02) и его отсутствие
    # (ADV-03). Второй знак — advisory, объявивший RED, — не предъявлен ни
    # одной, поэтому «advisory не блокирует» ими не доказано.
    advisory_red = _world_of("SDD-1-ADV-01")
    advisory_red["advisory_hook_outcome"] = "RED"
    path = write_world(work, "adv-advisory-red.yaml", advisory_red)
    check(
        "G-ADV-1 advisory RED при чистой authority НЕ блокирует",
        _verdict_at(path, "SDD-1-ADV-01") == "GREEN · CG_OK · exit 0",
        "получено %r" % _verdict_at(path, "SDD-1-ADV-01"),
    )
    no_advisory_dirty = _world_of("SDD-1-ADV-02")
    del no_advisory_dirty["advisory_hook_outcome"]
    path = write_world(work, "adv-no-advisory-dirty.yaml", no_advisory_dirty)
    check(
        "G-ADV-2-близнец снятый advisory НЕ отменяет находку authority",
        _verdict_at(path, "SDD-1-ADV-01")
        == "RED · CG_AUTHORITATIVE_GATE_BLOCKED · exit 10",
        "получено %r" % _verdict_at(path, "SDD-1-ADV-01"),
    )
    # Половина предиката о ЧЕТЫРЁХ вызывающих ни одной фикстурой не
    # предъявлена: ADV-02 портит только graph fact. Без этого утверждения
    # правило судило бы одну свою половину, и это было бы незаметно.
    caller_short = _world_of("SDD-1-ADV-01")
    del caller_short["authoritative_callers"]["project/kacho/.github/workflows/ci.yaml"]
    path = write_world(work, "adv-caller-short.yaml", caller_short)
    check(
        "G-ADV-3 недостающий authoritative caller блокирует так же, как "
        "грязный graph fact",
        _verdict_at(path, "SDD-1-ADV-01")
        == "RED · CG_AUTHORITATIVE_GATE_BLOCKED · exit 10",
        "получено %r" % _verdict_at(path, "SDD-1-ADV-01"),
    )

    # --- cg.wspp: правило о local SHA и ДОРОГА ссылки ------------------------
    # Диагностику CG_PRE_PUSH_LOCAL_REF_MISSING приёмка объявляет (SDD-1-PPRE-04),
    # а фикстуры ЭТОГО семейства не предъявляют: §11 требует от pre-push обеих
    # ссылок, и правило о второй иначе осталось бы кодом без пробы.
    no_local = _world_of("SDD-1-WSPP-01")
    del no_local["stdin_ref_line"]["local_sha"]
    path = write_world(work, "wspp-no-local.yaml", no_local)
    check(
        "G-WSPP-1 снятый local SHA даёт NOT_EXECUTED, а не молчание",
        _verdict_at(path, "SDD-1-WSPP-01")
        == "NOT_EXECUTED · CG_PRE_PUSH_LOCAL_REF_MISSING · exit 20",
        "получено %r" % _verdict_at(path, "SDD-1-WSPP-01"),
    )
    local_not_delivered = _world_of("SDD-1-WSPP-01")
    local_not_delivered["workspace"]["head_sha"] = "3" * 40
    path = write_world(work, "wspp-local-not-delivered.yaml", local_not_delivered)
    check(
        "G-WSPP-2 ссылка, прочитанная со stdin и НЕ доехавшая до диапазона, "
        "для гейта отсутствует",
        _verdict_at(path, "SDD-1-WSPP-01")
        == "NOT_EXECUTED · CG_PRE_PUSH_LOCAL_REF_MISSING · exit 20",
        "получено %r" % _verdict_at(path, "SDD-1-WSPP-01"),
    )
    no_repository = _world_of("SDD-1-WSPP-01")
    del no_repository["workspace"]["repo"]
    path = write_world(work, "wspp-no-repo.yaml", no_repository)
    check(
        "G-WSPP-3 граница словаря приёмки названа: без идентичности "
        "репозитория ссылку негде разрешать",
        _verdict_at(path, "SDD-1-WSPP-01")
        == "NOT_EXECUTED · CG_PRE_PUSH_REMOTE_REF_MISSING · exit 20",
        "получено %r" % _verdict_at(path, "SDD-1-WSPP-01"),
    )

    # --- cg.wsci: граница словаря и НЕ-таблица соответствий ------------------
    head_unresolved = _world_of("SDD-1-WSCI-01")
    head_unresolved["ref_lookup"]["head"] = "unavailable"
    path = write_world(work, "wsci-head-unresolved.yaml", head_unresolved)
    check(
        "G-WSCI-1 граница словаря приёмки названа: неразрешённая head отвечает "
        "единственной объявленной диагностикой о ссылке",
        _verdict_at(path, "SDD-1-WSCI-01")
        == "NOT_EXECUTED · CG_WORKSPACE_CI_BASE_REF_UNAVAILABLE · exit 20",
        "получено %r" % _verdict_at(path, "SDD-1-WSCI-01"),
    )
    empty_mapping = _world_of("SDD-1-WSCI-01")
    empty_mapping["package_tasks_mapping"] = []
    path = write_world(work, "wsci-empty-mapping.yaml", empty_mapping)
    check(
        "G-WSCI-2 нулевая перепись mapping — потеря, а не vacuous GREEN",
        _verdict_at(path, "SDD-1-WSCI-01") == "RED · CG_TRACE_ID_MISSING · exit 10",
        "получено %r" % _verdict_at(path, "SDD-1-WSCI-01"),
    )
    # Несущее: mapping ЧУЖОГО семейства, полный по структуре, обязан молчать, а
    # неполный — краснеть. Пара доказывает, что судится структура поданного, а
    # не совпадение с идентификатором кейса; таблица соответствий «ID -> ответ»
    # обе эти пробы провалила бы.
    foreign_complete = _world_of("SDD-1-WSCI-01")
    foreign_complete["package_tasks_mapping"] = ["SDD-1-BOOT-01", "SDD-1-BOOT-02"]
    path = write_world(work, "wsci-foreign-complete.yaml", foreign_complete)
    check(
        "G-WSCI-3-близнец полная пара ЧУЖОГО семейства в mapping молчит",
        _verdict_at(path, "SDD-1-WSCI-01") == "GREEN · CG_OK · exit 0",
        "получено %r" % _verdict_at(path, "SDD-1-WSCI-01"),
    )
    foreign_partial = _world_of("SDD-1-WSCI-01")
    foreign_partial["package_tasks_mapping"] = [
        "SDD-1-BOOT-01", "SDD-1-BOOT-02", "SDD-1-TRACE-01",
    ]
    path = write_world(work, "wsci-foreign-partial.yaml", foreign_partial)
    check(
        "G-WSCI-4 неполная пара среди полных найдена — счёт идёт по сериям",
        _verdict_at(path, "SDD-1-WSCI-01") == "RED · CG_TRACE_ID_MISSING · exit 10",
        "получено %r" % _verdict_at(path, "SDD-1-WSCI-01"),
    )
    # Вторая половина инверсии рождения: фикстуры теряют ПРОИЗВОДНЫЙ кейс, а
    # потерю БАЗОВОГО не предъявляет ни одна. Без этого утверждения половина
    # предиката была бы мертва незаметно.
    base_lost = _world_of("SDD-1-WSCI-01")
    base_lost["package_tasks_mapping"] = ["SDD-1-CENSUS-02", "SDD-1-CENSUS-03"]
    path = write_world(work, "wsci-base-lost.yaml", base_lost)
    check(
        "G-WSCI-5 потерянный базовый кейс серии найден так же, как потерянный "
        "производный",
        _verdict_at(path, "SDD-1-WSCI-01") == "RED · CG_TRACE_ID_MISSING · exit 10",
        "получено %r" % _verdict_at(path, "SDD-1-WSCI-01"),
    )
    # Серия — не то же самое, что семейство, и путать их нельзя. У семейства
    # `post` серий ДВЕ: `SDD-1-POST-NN` и `SDD-1-POST-NA-NN`; правила у них
    # общие, а инверсия рождения — своя у каждой. Перечень из двух БАЗОВЫХ
    # кейсов разных серий несёт два известно-хороших входа и ни одного
    # производного, то есть неполон; сложенные в одну группу, они выглядят
    # парой «база + производный», и потеря производного не находится.
    #
    # Пара обязательна: одно отрицание зеленело бы на разборе, который
    # отвергает суффикс серии целиком, — тогда законная пара второй серии
    # объявлялась бы неполной. Поэтому близнец подаёт базу и производный
    # ИМЕННО серии с суффиксом.
    mixed_bases = _world_of("SDD-1-WSCI-01")
    mixed_bases["package_tasks_mapping"] = ["SDD-1-POST-01", "SDD-1-POST-NA-01"]
    path = write_world(work, "wsci-mixed-series-bases.yaml", mixed_bases)
    check(
        "G-WSCI-6 два базовых кейса РАЗНЫХ серий одного семейства — неполнота, "
        "а не пара",
        _verdict_at(path, "SDD-1-WSCI-01") == "RED · CG_TRACE_ID_MISSING · exit 10",
        "получено %r" % _verdict_at(path, "SDD-1-WSCI-01"),
    )
    suffixed_pair = _world_of("SDD-1-WSCI-01")
    suffixed_pair["package_tasks_mapping"] = [
        "SDD-1-POST-NA-01", "SDD-1-POST-NA-02",
    ]
    path = write_world(work, "wsci-suffixed-series-pair.yaml", suffixed_pair)
    check(
        "G-WSCI-7-близнец база и производный ОДНОЙ серии с суффиксом молчат",
        _verdict_at(path, "SDD-1-WSCI-01") == "GREEN · CG_OK · exit 0",
        "получено %r" % _verdict_at(path, "SDD-1-WSCI-01"),
    )

    # --- предикат о mapping ОДИН на ЧЕТЫРЕ вызывающих семейства -------------
    # Здесь один и тот же mapping подаётся ДВУМ вызывающим — через край, то
    # есть вместе с их порядком правил и якорями семейства. Полнота этого
    # сравнения ограничена по построению и названа прямо: вызывающих ЧЕТЫРЕ, а
    # полос диагностики ШЕСТЬ, и два семейства из шести полос молчат ровно там,
    # где расхождение и завелось — у двух других. Сверку ВСЕХ полос ведёт
    # секция H (`selftest/laneparity.py`), выводя их обходом реестра; здесь
    # остаётся то, чего она не даёт: проверка сквозь край, с вердиктом целиком.
    for name, mapping, expected in (
        ("неполный", ["SDD-1-CENSUS-02", "SDD-1-CENSUS-03"],
         "RED · CG_TRACE_ID_MISSING · exit 10"),
        ("полный", ["SDD-1-CENSUS-01", "SDD-1-CENSUS-02"],
         "GREEN · CG_OK · exit 0"),
    ):
        ci_world = _world_of("SDD-1-WSCI-01")
        ci_world["package_tasks_mapping"] = list(mapping)
        ci_path = write_world(work, "callers-ci-%s.yaml" % name, ci_world)
        pp_world = _world_of("SDD-1-WSPP-01")
        pp_world["package_tasks_mapping"] = list(mapping)
        pp_path = write_world(work, "callers-pp-%s.yaml" % name, pp_world)
        ci_verdict = _verdict_at(ci_path, "SDD-1-WSCI-01")
        pp_verdict = _verdict_at(pp_path, "SDD-1-WSPP-01")
        check(
            "G-CALLERS %s mapping судится ОДИНАКОВО у cg.wsci и cg.wspp"
            % name,
            ci_verdict == expected and pp_verdict == expected,
            "cg.wsci дал %r, cg.wspp дал %r, ждали %r"
            % (ci_verdict, pp_verdict, expected),
        )

    # Якорь семейства: мир, не описывающий вызов, вердикта не получает вовсе.
    # Без этого утверждения правила вызывающих семейств (все применимы всегда,
    # чтобы находить НЕНАЗВАННУЮ координату) отвечали бы тройкой на любой мир,
    # включая чужой, — то есть выдавали бы «не знаю» за «нет».
    for case_id in ("SDD-1-WSCI-01", "SDD-1-WSPP-01"):
        expect_core_world_not_judged(
            "G-ANCHOR %s: чужой мир под ID вызывающего даёт собственный отказ, "
            "а НЕ вердикт" % case_id,
            ["--case-world", fixture_world("SDD-1-BOOT-01"), "--case", case_id],
        )
    expect_subject_verdict(
        "G-ANCHOR-близнец свой мир под своим ID вердикт о предмете даёт",
        ["--case-world", fixture_world("SDD-1-WSCI-01"), "--case",
         "SDD-1-WSCI-01"],
    )
    section_lane_rule_pairing()


def section_lane_rule_pairing():
    """То же для conv/withdraw/driver: «не знаю» не становится «нет».

    Секция C доказывает, что вердикт даёт МИР; здесь спрашивается то, чего она
    спросить не может: КАКОЕ правило сработало и почему вердикт взят именно им.
    Три несущих свойства этой полосы:

      * недоступность авторитета события отвечает NOT_EXECUTED и НЕ подменяется
        красным — в том числе на мире, где события заодно и нет;
      * отзыв, не запрошенный уполномоченным владельцем, семейство не судит
        вовсе и говорит это громко, а не отвечает GREEN;
      * birth-запись драйвера с диагностикой собственного отказа — находка, и
        эта ветвь предиката не предъявляется ни одним кейсом матрицы.
    """
    sys.stdout.write(
        "\n== F'. Парность правил полосы (conv/withdraw/driver) ==\n"
    )

    stderr, verdict = _judge("SDD-1-CONV-04")
    check(
        "F-CONV-1 недоступный авторитет даёт NOT_EXECUTED, и правило об "
        "отсутствии события молчит",
        "нарушений 1" in stderr
        and "conv.event-unavailable" in stderr
        and "conv.event-missing" not in stderr
        and verdict == "NOT_EXECUTED · CG_CONVERGENCE_EVENT_UNAVAILABLE · exit 20",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )
    stderr, verdict = _judge("SDD-1-CONV-03")
    check(
        "F-CONV-2-близнец отвечающий авторитет и отсутствующее событие краснят "
        "правило о событии — и только его",
        "нарушений 1" in stderr
        and "conv.event-missing" in stderr
        and "conv.event-unavailable" not in stderr
        and verdict == "RED · CG_CONVERGENCE_EVENT_MISSING · exit 10",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )

    work = tempfile.mkdtemp(prefix="cg-lane-")
    try:
        # Оба дефекта сразу: авторитет молчит И координаты события нет. Без
        # объявленного порядка вердикт стал бы красным, то есть неполученный
        # ответ был бы выдан за отрицательный.
        silent = yaml.safe_load(
            open(fixture_world("SDD-1-CONV-04"), encoding="utf-8")
        )
        silent["convergence"].pop("event_coordinate")
        silent_path = write_world(work, "conv-silent.yaml", silent)
        completed, lines = run_sut(
            ["--case-world", silent_path, "--case", "SDD-1-CONV-01"]
        )
        verdict = lines[-1] if lines else "(без вывода)"
        check(
            "F-CONV-3 при молчащем авторитете отсутствие события не становится "
            "находкой",
            "нарушений 1" in completed.stderr
            and "conv.event-unavailable" in completed.stderr
            and "conv.event-missing" not in completed.stderr
            and verdict
            == "NOT_EXECUTED · CG_CONVERGENCE_EVENT_UNAVAILABLE · exit 20",
            "вердикт %r; stderr=%s" % (verdict, completed.stderr.strip()[:400]),
        )

        # Отзыв, запрошенный не владельцем: семейство его не судит и говорит
        # это громко. GREEN здесь объявил бы неавторизованный отзыв законным.
        stranger = yaml.safe_load(
            open(fixture_world("SDD-1-WITHDRAW-01"), encoding="utf-8")
        )
        stranger["event"]["actor"] = "outsider-not-owner"
        stranger_path = write_world(work, "withdraw-stranger.yaml", stranger)
        expect_core_world_not_judged(
            "F-WITHDRAW-1 отзыв не от владельца даёт собственный отказ, а НЕ "
            "зелёный вердикт",
            ["--case-world", stranger_path, "--case", "SDD-1-WITHDRAW-01"],
        )
        expect_subject_verdict(
            "F-WITHDRAW-2-близнец тот же мир с владельцем из списка даёт "
            "вердикт о предмете",
            ["--case-world", fixture_world("SDD-1-WITHDRAW-01"), "--case",
             "SDD-1-WITHDRAW-01"],
        )

        # Ветвь предиката драйвера, которой нет ни у одного кейса матрицы:
        # записанная тройка несёт диагностику СОБСТВЕННОГО отказа, то есть
        # объявляет поломку испытуемого свойством мира.
        self_named = yaml.safe_load(
            open(fixture_world("SDD-1-DRIVER-02"), encoding="utf-8")
        )
        self_named["driver_birth"]["actual_triple"] = (
            "RED · CG_SELF_WORLD_MALFORMED · exit 10"
        )
        self_named_path = write_world(work, "driver-self.yaml", self_named)
        _, lines = run_sut(
            ["--case-world", self_named_path, "--case", "SDD-1-DRIVER-02"]
        )
        verdict = lines[-1] if lines else "(без вывода)"
        check(
            "F-DRIVER-1 birth-запись с диагностикой собственного отказа — "
            "находка",
            verdict == "RED · CG_DRIVER_BIRTH_TRIPLE_INVALID · exit 10",
            "вердикт %r" % (verdict,),
        )
        _, lines = run_sut(
            ["--case-world", fixture_world("SDD-1-DRIVER-02"), "--case",
             "SDD-1-DRIVER-02"]
        )
        verdict = lines[-1] if lines else "(без вывода)"
        check(
            "F-DRIVER-2-близнец согласованная birth-запись молчит",
            verdict == "GREEN · CG_OK · exit 0",
            "вердикт %r" % (verdict,),
        )
    finally:
        shutil.rmtree(work, ignore_errors=True)


def section_caller_and_landing(work):
    """Что B спросить НЕ МОЖЕТ у полос вызывающего, review и landing.

    B сверяет тройку и слеп к тому, ЧЕМ она получена: тройка сошлась бы и у
    правила, срабатывающего на всём подряд, и у семейства, где две находки
    предъявляются одной. Здесь спрашивается перепись — имена сработавших правил
    и объём прочитанного, — поэтому «правило есть» отличимо от «правило судит».
    """
    sys.stdout.write(
        "\n== G. Категория отказа, парность правил и прочитанное "
        "(ppre/post/land) ==\n"
    )

    # Гейт, которому не хватило координат, о графе не высказывался вовсе.
    # Категория здесь несущая: RED обвинил бы граф в том, чего никто не смотрел.
    stderr, verdict = _judge("SDD-1-PPRE-03")
    check(
        "G-PPRE-1 нехватка координат даёт NOT_EXECUTED, а не RED о графе",
        "нарушений 1" in stderr
        and "ppre.workspace-repo-missing" in stderr
        and "ppre.trace-id-missing" not in stderr
        and verdict
        == "NOT_EXECUTED · CG_PRODUCT_PRE_PUSH_WORKSPACE_REPO_MISSING · exit 20",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )
    # Близнец: без него G-PPRE-1 зеленел бы на семействе, отвечающем одной
    # категорией на всё.
    stderr, verdict = _judge("SDD-1-PPRE-02")
    check(
        "G-PPRE-2-близнец при полных координатах дефект графа даёт RED, а не "
        "NOT_EXECUTED",
        "нарушений 1" in stderr
        and "ppre.trace-id-missing" in stderr
        and "ppre.workspace-repo-missing" not in stderr
        and verdict == "RED · CG_TRACE_ID_MISSING · exit 10",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )

    # Отсутствие записи и её чужое владение — РАЗНЫЕ дефекты, и каждое правило
    # ловит ровно тот, который второе обязано пропустить. Ни одно поодиночке их
    # не различает, а вместе они не имеют права удваивать одну находку.
    stderr, verdict = _judge("SDD-1-POST-03")
    check(
        "G-POST-1 запись, принадлежащую другой роли, ловит правило ownership — "
        "и только оно",
        "нарушений 1" in stderr
        and "post.review-overwritten" in stderr
        and "post.review-missing" not in stderr
        and verdict == "RED · CG_POST_DIFF_REVIEW_OVERWRITTEN · exit 10",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )
    stderr, verdict = _judge("SDD-1-POST-02")
    check(
        "G-POST-2-близнец отсутствующую запись ловит правило о ней — и правило "
        "ownership на ней молчит",
        "нарушений 1" in stderr
        and "post.review-missing" in stderr
        and "post.review-overwritten" not in stderr
        and verdict == "RED · CG_POST_DIFF_REVIEW_MISSING · exit 10",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )
    # Граница предмета названа переписью, а не подразумевается: состав
    # aggregator'а судит семейство convergence.
    stderr, _ = _judge("SDD-1-POST-01")
    check(
        "G-POST-3 не судимые этим семейством координаты названы переписью "
        "поимённо",
        "вне предмета cg.post" in stderr
        and "convergence_aggregator_specialists" in stderr,
        "stderr=%s" % stderr.strip()[:400],
    )

    # Новое ИМЯ записи при прежнем содержимом дрейфом не является. Утверждение
    # без переписи было бы вакуумным: «нарушений 0» получилось бы и у правила,
    # которое commit SHA вообще не читало, — поэтому проверяется, что мир
    # прочитан ЦЕЛИКОМ и при этом вердикт зелёный.
    stderr, verdict = _judge("SDD-1-LAND-03")
    check(
        "G-LAND-1 сменившийся commit SHA прочитан и вердикт stale НЕ делает",
        "нарушений 0" in stderr
        and "фактов мира 5 · прочитано 5" in stderr
        and verdict == "GREEN · CG_OK · exit 0",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )
    stderr, verdict = _judge("SDD-1-LAND-02")
    check(
        "G-LAND-2-близнец уехавший blob при том же заявленном отпечатке даёт "
        "RED",
        "нарушений 1" in stderr
        and "land.content-drift" in stderr
        and verdict == "RED · CG_LANDED_CONTENT_DRIFT · exit 10",
        "вердикт %r; stderr=%s" % (verdict, stderr.strip()[:400]),
    )

    # Обе полосы опираются на ЗАРЕГИСТРИРОВАННЫЙ эталон (канонический набор
    # landing, реестр предикатов освобождения), и у обеих есть ветвь «эталона
    # для этого входа у меня нет». Ни один кейс приёмки её не предъявляет —
    # значит без этих двух утверждений она была бы кодом без пробы, а её
    # молчание неотличимо от исправной работы. Спрашивается ровно то, что
    # отличает «не знаю» от «нет»: stdout пуст, код 40, вердикт НЕ вынесен.
    unknown_digest = write_world(
        work,
        "land-unknown-digest.yaml",
        {
            "convergence_content_digest": "sha256:fixture-content-неизвестный",
            "landed": {
                "commit_sha": "1" * 40,
                "canonical_content_digest": "sha256:fixture-content-неизвестный",
            },
            "landed_blobs": {"scripts/change-graph-gate/run.py": "sha256:blob"},
        },
    )
    expect_self_failure(
        "G-LAND-3 нераскрываемый отпечаток -> собственный отказ, а НЕ «дрейфа "
        "нет»",
        ["--case-world", unknown_digest, "--case", "SDD-1-LAND-01"],
        "CG_SELF_INTERNAL",
    )
    unknown_predicate = write_world(
        work,
        "post-unknown-predicate.yaml",
        {
            "role": "db-architect-reviewer",
            "declared_predicate_id": "предиката-такого-нет-в-коде",
            "policy_predicates": {"предиката-такого-нет-в-коде": "registered"},
            "evidence": {"migrations_touched": 0},
        },
    )
    expect_self_failure(
        "G-POST-4 зарегистрированный, но невычислимый предикат -> собственный "
        "отказ, а НЕ «освобождение принято»",
        ["--case-world", unknown_predicate, "--case", "SDD-1-POST-NA-01"],
        "CG_SELF_INTERNAL",
    )


def _ledger_with(ledger, world_class, entry):
    """Копия ведомости с добавленной записью. Ключ — кортеж, не строка."""
    extended = dict(ledger)
    extended[world_class] = entry
    return extended


def section_lane_parity():
    """Полосы одной диагностики сверяются МЕЖДУ СОБОЙ, а не каждая отдельно.

    `architecture.md` §«Параллельные полосы одного механизма обязаны сверяться
    МЕЖДУ СОБОЙ»: проба каждой полосы требует знать, каким свойство ДОЛЖНО
    быть, — а это и есть спорный вопрос. Сравнение спрашивает другое: решал ли
    кто-нибудь, что полосы различаются.

    Секция G выше уже подавала один и тот же mapping ДВУМ вызывающим. Этого
    мало по построению: вызывающих ЧЕТЫРЕ, а полос диагностики ШЕСТЬ, и
    сравнение двух из шести молчит ровно там, где расхождение и завелось — у
    двух других. Здесь полосы ВЫВОДЯТСЯ обходом реестра, поэтому новое
    семейство попадает в сверку само, а не по чьей-то памяти.
    """
    sys.stdout.write("\n== H. Полосы одной диагностики сверяются между собой ==\n")

    findings, census = laneparity.audit()
    check(
        "H-PARITY-1 полосы одного класса отвечают ОДИНАКОВО на выведенном из "
        "дерева корпусе",
        not findings,
        "находки: %s" % "; ".join(findings),
    )
    # Перепись: «находок ноль» обязано быть отличимо от «сравнено ноль».
    check(
        "H-PARITY-2 перепись сверки непуста: сравнивать было что",
        census["полос"] >= 2
        and census["сравнено полос"] >= 2
        and census["входов корпуса"] > 0,
        "перепись: %s" % laneparity.census_line(census),
    )
    sys.stdout.write("       перепись сверки полос: %s\n"
                     % laneparity.census_line(census))

    # --- способность упасть доказывается СИНТЕТИКОЙ ------------------------
    # На настоящем дереве расхождения больше нет by construction: у четырёх
    # вызывающих судья ОДИН. Значит красноту сверки нельзя доказать деревом —
    # только поданными полосами. Ниже по каждой оси стоит пара: дефект и
    # законный близнец, на котором сверка обязана молчать.
    synthetic_class = ("package_tasks_mapping",)
    synthetic_ledger = {
        synthetic_class: laneparity.ClassEntry(
            why="синтетический класс пробы",
            corpus=laneparity.mapping_corpus,
        ),
    }

    def strict(world):
        return tasksmapping_module.lost_acceptance_id(
            world.read_all("package_tasks_mapping")
        )

    def strict_other_code(world):
        # Тот же ответ, ДРУГОЙ код: сверка обязана судить поведение, а не текст.
        mapping = list(world.read_all("package_tasks_mapping"))
        verdict = tasksmapping_module.lost_acceptance_id(mapping)
        return True if verdict else False

    def lenient(world):
        # Расходится ровно на неразбираемой записи: находка вместо отказа.
        try:
            return tasksmapping_module.lost_acceptance_id(
                world.read_all("package_tasks_mapping")
            )
        except outcome_module.SelfFailure:
            return True

    def lane(rule_id, predicate):
        return laneparity.Lane("wspp", rule_id, synthetic_class, predicate)

    diverging = [lane("проба.строгая", strict), lane("проба.мягкая", lenient)]
    findings, census = laneparity.audit(
        found_lanes=diverging, ledger=synthetic_ledger
    )
    named_input = any("неразбираемая запись" in item for item in findings)
    named_answers = any(
        "проба.строгая ->" in item and "проба.мягкая ->" in item
        for item in findings
    )
    check(
        "H-PARITY-3 разошедшиеся полосы найдены, и находка называет вход И "
        "ответ КАЖДОЙ полосы",
        bool(findings) and named_input and named_answers,
        "находки: %s" % "; ".join(findings),
    )
    check(
        "H-PARITY-3-близнец полосы с РАЗНЫМ кодом и одинаковым поведением "
        "сверку не роняют",
        not laneparity.audit(
            found_lanes=[lane("проба.первая", strict),
                         lane("проба.вторая", strict_other_code)],
            ledger=synthetic_ledger,
        )[0],
        "находки: %s" % "; ".join(
            laneparity.audit(
                found_lanes=[lane("проба.первая", strict),
                             lane("проба.вторая", strict_other_code)],
                ledger=synthetic_ledger,
            )[0]
        ),
    )

    # Третий ответ не схлопнут во второй: полоса, ОТКАЗАВШАЯСЯ отвечать,
    # отличима от молчащей. Без этого утверждения сверка была бы слепа ровно
    # там, где расхождение нашлось при заведении, — на неразбираемой записи.
    #
    # Имя утверждения намеренно НЕ несёт зарезервированной пометки класса
    # «собственный отказ». Пометка принадлежит утверждениям, наблюдающим отказ
    # ИСПЫТУЕМОГО через вердикт — их разворачивает по контрольному прогону
    # инъекция, подменяющая отказ вердиктом. Здесь предмет другой: сверка
    # классифицирует ответ ПОЛОСЫ, предикат зовётся напрямую, и engine в этом
    # не участвует, — поэтому та инъекция это утверждение не роняет и ронять не
    # обязана. Носи оно пометку, инъекция ждала бы красноты, которой неоткуда
    # взяться.
    answers = {
        laneparity.answer(lane("проба.строгая", strict),
                          {"package_tasks_mapping": ["не идентификатор"]}),
        laneparity.answer(lane("проба.мягкая", lenient),
                          {"package_tasks_mapping": ["не идентификатор"]}),
    }
    check(
        "H-PARITY-4 полоса, ОТКАЗАВШАЯСЯ отвечать, отличима от молчащей и от "
        "нашедшей",
        len(answers) == 2
        and any(item.startswith(laneparity.ANSWER_REFUSAL) for item in answers)
        and laneparity.ANSWER_FINDING in answers,
        "ответы: %s" % sorted(answers),
    )

    # --- ведомость классов истекает сама, в обе стороны ---------------------
    unknown_class = ("выдуманная_координата",)
    findings, _ = laneparity.audit(
        found_lanes=[laneparity.Lane("wspp", "проба.новая", unknown_class, strict)],
        ledger=synthetic_ledger,
    )
    check(
        "H-PARITY-5 класс мира, произведённый и НЕ объявленный, — находка: "
        "расхождение возникло, а не было решено",
        any("НЕ объявлен" in item for item in findings),
        "находки: %s" % "; ".join(findings),
    )
    findings, _ = laneparity.audit(
        found_lanes=[lane("проба.строгая", strict), lane("проба.вторая", strict_other_code)],
        ledger=_ledger_with(
            synthetic_ledger,
            ("никем_не_судимая",),
            laneparity.ClassEntry(why="запись без предмета"),
        ),
    )
    check(
        "H-PARITY-6 объявленный класс без единого производителя — находка: "
        "записи нечего объяснять",
        any("не производит ни одна полоса" in item for item in findings),
        "находки: %s" % "; ".join(findings),
    )
    findings, _ = laneparity.audit(
        found_lanes=diverging,
        ledger={synthetic_class: laneparity.ClassEntry(why="без корпуса")},
    )
    check(
        "H-PARITY-7 две полосы одного класса без корпуса сравнения — находка, "
        "а не тишина",
        any("корпуса сравнения не объявлено" in item for item in findings),
        "находки: %s" % "; ".join(findings),
    )
    findings, _ = laneparity.audit(
        found_lanes=diverging,
        ledger={synthetic_class: laneparity.ClassEntry(
            why="пустой корпус", corpus=lambda: []
        )},
    )
    check(
        "H-PARITY-8 пустой корпус — находка «сверка беспредметна», а НЕ "
        "«расхождений нет»",
        any("сверка беспредметна" in item for item in findings),
        "находки: %s" % "; ".join(findings),
    )

    # Поломка предиката не есть согласие. Без этого утверждения ветвь была бы
    # кодом без пробы, а её предмет — самый тихий из возможных: полосы, упавшие
    # ОДИНАКОВО, сравнение проходят, потому что ответы у них совпали.
    def broken(world):
        raise ValueError("предикат синтетической полосы упал намеренно")

    findings, _ = laneparity.audit(
        found_lanes=[lane("проба.первая", broken), lane("проба.вторая", broken)],
        ledger=synthetic_ledger,
    )
    check(
        "H-PARITY-10 полосы, упавшие ОДИНАКОВО, дают находку «поломка не есть "
        "согласие», а не тишину",
        any("УПАЛА" in item for item in findings)
        and not any("РАЗОШЛИСЬ" in item for item in findings),
        "находки: %s" % "; ".join(findings),
    )
    check(
        "H-PARITY-10-близнец полосы, которые НЕ падают, находки о поломке не "
        "дают",
        not any("УПАЛА" in item for item in laneparity.audit(
            found_lanes=[lane("проба.первая", strict),
                         lane("проба.вторая", strict_other_code)],
            ledger=synthetic_ledger,
        )[0]),
        "находки о поломке там, где никто не падал",
    )

    # --- корпус ВЫВОДИТСЯ из дерева, а не выписан --------------------------
    # Выписанный корпус не содержал бы входа, на котором расхождение и
    # нашлось: серию с добавочным сегментом надо придумать, а вывести —
    # достаточно. Считается независимым обходом каталога фикстур.
    series = {}
    for case_id in os.listdir(TESTDATA):
        if not os.path.isdir(os.path.join(TESTDATA, case_id)):
            continue
        head, _, tail = case_id.rpartition("-")
        if head and tail.isdigit():
            series.setdefault(head, []).append(case_id)
    pairable = [name for name in series if len(series[name]) >= 2]
    corpus = laneparity.mapping_corpus()
    extra_segment = [name for name in pairable if name.count("-") > 2]
    check(
        "H-PARITY-11 корпус ВЫВЕДЕН из дерева: входов ровно по числу серий, и "
        "среди них есть серия с добавочным сегментом",
        len(corpus) == 2 * len(pairable) + 2
        and bool(extra_segment)
        and any(extra_segment[0] in name for name, _ in corpus),
        "входов корпуса %d при %d парных сериях; серии с добавочным сегментом: %s"
        % (len(corpus), len(pairable), extra_segment),
    )


# --- I. Диагностика берётся из ПРИЁМКИ, а не заводится реализацией ----------
#
# Норма контура: диагностику правила объявляет ПРИЁМКА. Реализация своей не
# заводит — иначе контракт пишет исполнитель, а рецензент судит то, чего не
# утверждал. До ws#502 норму не держала НИ ОДНА проверка: ни эта проба, ни
# `inject.py`, ни `tests/caselib` не сверяли два множества, и единственное
# отступление в дереве (ws#494) нашла честность автора полосы, а не механизм.
#
# Класс тихий by construction: код, которого приёмка не объявляет, матрица
# кейсов НЕ ПРЕДЪЯВЛЯЕТ — её кейсы выводятся из приёмки, — поэтому такой код не
# краснеет ничем и от законного неотличим.

# Имя файла приёмки, а НЕ путь: путь выводится. Проба живёт и в песочнице
# инъекций, где над каталогом оснастки корня воркспейса нет вовсе, и выписанный
# `../../docs/...` там указывал бы в пустоту — то есть проба объявляла бы
# «диагностик приёмки 0» и краснела на собственной раскладке.
ACCEPTANCE_BASENAME = "sub-phase-SDD-1-kacho-change-graph-acceptance.md"

# Ручка для песочницы: дочерний прогон в копии дерева получает путь приёмки
# готовым, потому что вывести его сам он не может. Ставит её тот, кто песочницу
# создал (`inject.py`, `prove_run_progress.py`), — через `acceptance_environment`.
ACCEPTANCE_ENV = "CG_ACCEPTANCE_DOC"

# Диагностика — токен `CG_…` либо `CGA_…`. Образец взят дословно из тела задач
# #494/#502, чтобы число этой пробы воспроизводилось их предикатом, а не
# расходилось с ним молча на второй форме записи.
DIAGNOSTIC_TOKEN = re.compile(r"\bCGA?_[A-Z0-9_]+")

# ── ВЕДОМОСТЬ ОТСТУПЛЕНИЙ ────────────────────────────────────────────────────
#
# Код, который правила объявляют, а приёмка — нет. Ключ — диагностика, значение
# — причина и ПРЕДИКАТ СНЯТИЯ командой, а не словами.
#
# Ведомость САМОИСТЕКАЕТ: запись, которой нечего исключать, — находка
# (`testing.md` §«Гейт на класс», п. 5). Идеал ведомости — ПУСТОТА, и пустая она
# проходит: превращать достигнутую цель в поломку значило бы подталкивать
# держать запись ради зелёного (§«Проба не имеет права падать на ДОСТИЖЕНИИ
# СВОЕЙ ЦЕЛИ»).
SPEC_DIAGNOSTIC_EXEMPTIONS = {
    # ws#494. Приёмка для `cg.driver` не объявляет НИ ОДНОЙ диагностики: коды в
    # её рядах `DRIVER-*` принадлежат соседям, а взять чужой значило бы завести
    # второго производителя одного кода и назвать находку неверным именем.
    # Автор полосы завёл свой и назвал цену в модуле — прощение стоит здесь
    # ровно потому, что цена названа, а не потому, что код удобен.
    #
    # ПРЕДИКАТ СНЯТИЯ — командой, а не словами:
    #
    #   grep -c CG_DRIVER_BIRTH_TRIPLE_INVALID \
    #     docs/specs/sub-phase-SDD-1-kacho-change-graph-acceptance.md
    #
    # Не ноль — предмет прощения исчез, и ЭТА запись обязана покраснеть здесь
    # утверждением I2 как запись без предмета. Снятие идёт кругом рецензии по
    # приёмке (правка приёмки отзывает её вердикт), а не правкой реализации.
    "CG_DRIVER_BIRTH_TRIPLE_INVALID":
        "ws#494: у семейства cg.driver собственной диагностики приёмка не "
        "объявляет; снимается кругом рецензии по приёмке",
}


def acceptance_path():
    """Путь приёмки, выведенный, а не выписанный. None — приёмка недосягаема.

    Порядок: ручка окружения (её ставит создавший песочницу) → обход вверх от
    каталога оснастки. Обратный порядок сделал бы ручку недействующей ровно
    там, где она единственный источник.
    """
    override = os.environ.get(ACCEPTANCE_ENV)
    if override:
        return override if os.path.isfile(override) else None
    node = GATE_DIR
    while True:
        candidate = os.path.join(node, "docs", "specs", ACCEPTANCE_BASENAME)
        if os.path.isfile(candidate):
            return candidate
        parent = os.path.dirname(node)
        if parent == node:
            return None
        node = parent


def acceptance_environment(base=None):
    """Окружение для дочернего прогона в песочнице: путь приёмки разрешён здесь.

    Песочница инъекций — копия ОДНОГО каталога оснастки; воркспейса над ней нет,
    поэтому обход вверх в ней не находит ничего. Разрешение делает тот, кто ещё
    стоит в настоящем дереве, и передаёт готовый путь вниз. Ручка, уже стоящая в
    окружении, ПЕРЕЖИВАЕТ вложение: `prove_run_progress.py` кладёт песочницу в
    песочницу, и на втором этаже выводить путь неоткуда.
    """
    env = dict(os.environ if base is None else base)
    resolved = acceptance_path()
    if resolved:
        env[ACCEPTANCE_ENV] = resolved
    return env


def rule_diagnostics():
    """Диагностики, которые объявляют ПРАВИЛА — обходом реестра, не перечнем."""
    return {
        rule.diagnostic
        for rules in registry_module.load().values()
        for rule in rules
    }


def spec_diagnostics(path):
    """Диагностики, которые объявляет ПРИЁМКА. Приёмки нет — пустое множество."""
    if not path:
        return set()
    with open(path, encoding="utf-8") as handle:
        return set(DIAGNOSTIC_TOKEN.findall(handle.read()))


def audit_spec_diagnostics(codes, spec, exemptions):
    """Сверка двух множеств. Возвращает (находки, перепись).

    Находка — пара (вид, текст): вид нужен, чтобы утверждения были отдельными и
    инъекция роняла НАЗВАННОЕ, а не «что-нибудь из секции».

    НАПРАВЛЕНИЯ РАЗВЕДЕНЫ, и это несущее решение. `codes - spec` — находка:
    контракт написала реализация. `spec - codes` — СТРОКА ПЕРЕПИСИ, но не
    находка: `CG_OK` производителя не имеет by construction (это исход «правило
    не нарушено», а не правило), и смешение двух направлений дало бы проверку,
    красную ВСЕГДА, — то есть её отключили бы первой.
    """
    findings = []
    undeclared = sorted(codes - spec)
    unproduced = sorted(spec - codes)
    unexcused = [code for code in undeclared if code not in exemptions]
    stale = sorted(code for code in exemptions if code not in undeclared)

    # Пустой обход — НАХОДКА «беспредметно», а не «чисто»: без этой ветви
    # недосягаемая приёмка дала бы `codes - spec` величиной во весь реестр, а
    # непрочитанный реестр — ноль находок, то есть зелёное на непрочитанном.
    if not codes or not spec:
        findings.append((
            "беспредметно",
            "обход беспредметен: диагностик правил %d, диагностик приёмки %d — "
            "о предмете прочитано не всё, и это НЕ «нарушений нет»"
            % (len(codes), len(spec)),
        ))
    for code in unexcused:
        findings.append((
            "мимо приёмки",
            "%s — правило объявляет диагностику, которой приёмка НЕ объявляет: "
            "контракт написала реализация, и рецензент судил бы то, чего не "
            "утверждал" % code,
        ))
    for code in stale:
        findings.append((
            "прощение без предмета",
            "%s — записи ведомости нечего исключать: либо приёмка код объявила, "
            "либо правило его больше не производит. Прощение пережило свой "
            "предмет — снимите запись" % code,
        ))

    census = {
        "диагностик правил": len(codes),
        "диагностик приёмки": len(spec),
        "мимо приёмки": len(undeclared),
        "из них прощено ведомостью": len(undeclared) - len(unexcused),
        "без производителя": len(unproduced),
    }
    return findings, census


def spec_census_line(census):
    """Перепись ОБЕИМИ величинами.

    Одно число скрывает ровно тот случай, ради которого проверка заведена:
    множества разошлись, а размер не изменился — на стволе их было 134 и 134.
    """
    return " · ".join("%s %d" % (key, census[key]) for key in (
        "диагностик правил", "диагностик приёмки", "мимо приёмки",
        "из них прощено ведомостью", "без производителя",
    ))


def _findings_of(findings, kind):
    return [text for found_kind, text in findings if found_kind == kind]


def section_spec_diagnostics():
    """Диагностика правил объявлена приёмкой — сверкой двух множеств.

    Способность упасть доказана здесь же СИНТЕТИКОЙ: на настоящем дереве
    отступление одно и оно прощено, поэтому красноту нельзя показать деревом —
    только поданными множествами. По каждой оси стоит пара: дефект и законный
    близнец, на котором сверка обязана МОЛЧАТЬ. Односторонняя проба зеленела бы
    на сверке, которая отвергает всё.

    Инъекцией по НАСТОЯЩЕМУ дереву та же способность доказана отдельно —
    `selftest/inject.py`, отбор «диагностика мимо приёмки».
    """
    sys.stdout.write(
        "\n== I. Диагностика берётся из приёмки, а не из реализации ==\n"
    )

    path = acceptance_path()
    codes = rule_diagnostics()
    spec = spec_diagnostics(path)
    findings, census = audit_spec_diagnostics(
        codes, spec, SPEC_DIAGNOSTIC_EXEMPTIONS
    )
    sys.stdout.write("       перепись сверки диагностик: %s\n"
                     % spec_census_line(census))

    check(
        "I1 каждая диагностика правил объявлена приёмкой либо прощена "
        "ведомостью с предикатом снятия",
        not _findings_of(findings, "мимо приёмки"),
        "; ".join(_findings_of(findings, "мимо приёмки")),
    )
    check(
        "I2 у каждой записи ведомости есть предмет: прощение не переживает "
        "своей причины",
        not _findings_of(findings, "прощение без предмета"),
        "; ".join(_findings_of(findings, "прощение без предмета")),
    )
    check(
        "I3 обход непуст: приёмка найдена, реестр прочитан",
        not _findings_of(findings, "беспредметно")
        and census["диагностик правил"] > 0
        and census["диагностик приёмки"] > 0,
        "приёмка=%s; перепись: %s" % (path, spec_census_line(census)),
    )

    # --- способность упасть: пара «дефект / законный близнец» по каждой оси ---
    defect, _ = audit_spec_diagnostics(
        {"CG_MADE_UP_BY_IMPLEMENTATION"}, {"CG_OK"}, {}
    )
    named = [
        text for text in _findings_of(defect, "мимо приёмки")
        if "CG_MADE_UP_BY_IMPLEMENTATION" in text
    ]
    check(
        "I4 дефект: код мимо приёмки — находка, и находка НАЗЫВАЕТ код",
        len(named) == 1,
        "находки: %s" % defect,
    )
    twin, _ = audit_spec_diagnostics(
        {"CG_DECLARED_BY_ACCEPTANCE"}, {"CG_DECLARED_BY_ACCEPTANCE", "CG_OK"}, {}
    )
    check(
        "I4-близнец код, приёмкой объявленный, — молчание",
        not twin,
        "находки: %s" % twin,
    )

    stale, _ = audit_spec_diagnostics(
        {"CG_DECLARED_BY_ACCEPTANCE"}, {"CG_DECLARED_BY_ACCEPTANCE", "CG_OK"},
        {"CG_DECLARED_BY_ACCEPTANCE": "прощение, у которого предмет исчез"},
    )
    named = [
        text for text in _findings_of(stale, "прощение без предмета")
        if "CG_DECLARED_BY_ACCEPTANCE" in text
    ]
    check(
        "I5 дефект: записи ведомости нечего исключать — находка с именем кода",
        len(named) == 1,
        "находки: %s" % stale,
    )
    live, _ = audit_spec_diagnostics(
        {"CG_MADE_UP_BY_IMPLEMENTATION"}, {"CG_OK"},
        {"CG_MADE_UP_BY_IMPLEMENTATION": "прощение с живым предметом"},
    )
    check(
        "I5-близнец запись, у которой предмет ЖИВ, — молчание",
        not live,
        "находки: %s" % live,
    )
    empty_ledger, _ = audit_spec_diagnostics(
        {"CG_DECLARED_BY_ACCEPTANCE"}, {"CG_DECLARED_BY_ACCEPTANCE", "CG_OK"}, {}
    )
    check(
        "I5-близнец ПУСТАЯ ведомость — молчание, а не поломка: пустота и есть "
        "её цель",
        not empty_ledger,
        "находки: %s" % empty_ledger,
    )

    absent, absent_census = audit_spec_diagnostics(
        {"CG_DECLARED_BY_ACCEPTANCE"},
        {"CG_DECLARED_BY_ACCEPTANCE", "CG_OK"}, {},
    )
    check(
        "I6 «без производителя» — строка переписи, а НЕ находка: иначе сверка "
        "красна всегда, потому что CG_OK правилом не производится",
        not absent and absent_census["без производителя"] == 1,
        "находки=%s; перепись: %s" % (absent, spec_census_line(absent_census)),
    )

    void_codes, _ = audit_spec_diagnostics(set(), {"CG_OK"}, {})
    void_spec, _ = audit_spec_diagnostics({"CG_DECLARED_BY_ACCEPTANCE"}, set(), {})
    check(
        "I7 пустой обход — находка «беспредметно» с ОБЕИХ сторон, а не «чисто»",
        len(_findings_of(void_codes, "беспредметно")) == 1
        and len(_findings_of(void_spec, "беспредметно")) == 1,
        "реестр пуст -> %s; приёмка пуста -> %s" % (void_codes, void_spec),
    )
    check(
        "I7-близнец непустые множества беспредметности не объявляют",
        not _findings_of(
            audit_spec_diagnostics(
                {"CG_DECLARED_BY_ACCEPTANCE"},
                {"CG_DECLARED_BY_ACCEPTANCE"}, {},
            )[0],
            "беспредметно",
        ),
        "непустой вход объявлен беспредметным",
    )


def main():
    with tempfile.TemporaryDirectory(prefix="cg-selftest-") as work:
        declared = section_capabilities(work)
        cases = section_cases()
        section_world_decides()
        section_self_failure(work)
        section_census()
        section_rule_pairing()
        section_callers_and_advisory(work)
        section_caller_and_landing(work)
    section_lane_parity()
    section_spec_diagnostics()

    total = len(PASSED) + len(FAILED)
    sys.stdout.write("\n=== перепись проб испытуемого ===\n")
    sys.stdout.write(
        "утверждений: %d · прошло: %d · провалено: %d\n"
        % (total, len(PASSED), len(FAILED))
    )
    sys.stdout.write(
        "объявлено признаков: %d · кейсов объявленных семейств осмотрено: %d\n"
        % (declared, cases)
    )
    if total == 0 or cases == 0 or declared == 0:
        sys.stdout.write(
            "проба беспредметна: объявлять или осматривать оказалось нечего\n"
        )
        return 2
    return 1 if FAILED else 0


if __name__ == "__main__":
    raise SystemExit(main())
