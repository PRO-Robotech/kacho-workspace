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
from cglib import registry as registry_module  # noqa: E402

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


def fixture_expectation(case_id):
    path = os.path.join(TESTDATA, case_id, "case.yaml")
    with open(path, encoding="utf-8") as handle:
        manifest = yaml.safe_load(handle)
    expected = manifest["expected_sut"]
    return "%s · %s · exit %d" % (
        expected["category"], expected["diagnostic"], expected["exit"]
    )


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
    check(
        "A5 снятие модуля семейства снимает признак — перечень выведен из дерева",
        "cg.boot" in parsed and "cg.boot" not in injected,
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
    sys.stdout.write("\n== B. Тройка испытуемого равна объявленной приёмкой ==\n")
    cases = declared_cases()
    if not cases:
        return 0
    matched = 0
    for case_id in cases:
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
        matched == len(cases),
        "совпало %d из %d" % (matched, len(cases)),
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
        ("SDD-1-SUPER-01", "SDD-1-SUPER-04", "CG_SUPERSEDE_CYCLE"),
        ("SDD-1-HOLDER-01", "SDD-1-HOLDER-06",
         "CG_HOLDER_SUBJECT_HASH_MISMATCH"),
        ("SDD-1-BIRTH-01", "SDD-1-BIRTH-03", "CG_BIRTH_DEFECT_NOT_DETECTED"),
        ("SDD-1-EVID-01", "SDD-1-EVID-03", "CG_REQUIRED_HOLDER_RED"),
        ("SDD-1-NA-01", "SDD-1-NA-03", "CG_NA_PREDICATE_FALSE"),
        ("SDD-1-TDD-02", "SDD-1-TDD-03", "CG_RED_PROOF_UNEXPECTED_GREEN"),
        ("SDD-1-REVIEW-01", "SDD-1-REVIEW-06", "CG_BOOTSTRAP_ACTOR_SPOOFED"),
        ("SDD-1-CLASS-04", "SDD-1-CLASS-05", "CG_CLASS_ITEM_UNMAPPED"),
        ("SDD-1-DESIGN-01", "SDD-1-DESIGN-03", "CG_PRECODE_REVIEW_MISSING"),
        ("SDD-1-CENSUS-01", "SDD-1-CENSUS-03", "CG_CENSUS_STALE"),
        ("SDD-1-POLICY-01", "SDD-1-POLICY-02", "CG_POLICY_REPOSITORY_MISSING"),
        ("SDD-1-DAG-04", "SDD-1-DAG-05", "CG_PACKAGE_REQUIRED_AFTER_CUTOVER"),
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
def expect_self_failure(name, argv, marker=None):
    completed, lines = run_sut(argv)
    stdout_empty = not lines
    right_code = completed.returncode == SELF_FAILURE_EXIT
    named = marker is None or marker in completed.stderr
    check(
        name,
        stdout_empty and right_code and named,
        "код %d, stdout=%r, stderr=%s"
        % (completed.returncode, completed.stdout[:120],
           completed.stderr.strip()[:240]),
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
    expect_self_failure(
        "D7 ни одно правило не применимо -> собственный отказ, а НЕ vacuous GREEN",
        ["--case-world", inactive_path, "--case", "SDD-1-NONEMPTY-01"],
        "CG_SELF_WORLD_NOT_JUDGED",
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
    expect_self_failure(
        "D8 непрочитанный факт внутри предмета -> собственный отказ",
        ["--case-world", unread_path, "--case", "SDD-1-HASH-01"],
        "CG_SELF_WORLD_FACT_UNREAD",
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
    sys.stdout.write(
        "\n== F. Парность правил и объявленный порядок (holder/birth/evid/na) ==\n"
    )

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


def main():
    with tempfile.TemporaryDirectory(prefix="cg-selftest-") as work:
        declared = section_capabilities(work)
        cases = section_cases()
        section_world_decides()
        section_self_failure(work)
        section_census()
        section_rule_pairing()

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
