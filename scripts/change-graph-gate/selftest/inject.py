#!/usr/bin/env python3
"""Доказательство, что prove.py СПОСОБЕН упасть — инъекцией, а не прочтением.

`testing.md` §«Гейт на класс», п. 2: гейт доказывается инъекцией в обе стороны.
(а) верни дефект — проба краснеет И называет координату; (б) поставь рядом
законный близнец — проба молчит. Без (б) проба ловила бы форму, а не существо.

П. 2в того же раздела: инъекция обязана ронять ТОЛЬКО проверяемое. Поэтому по
каждой инъекции здесь названо, какие утверждения обязаны покраснеть, и
проверяется, что покраснели ИМЕННО они, — иначе краснота могла бы приходить от
соседа, а проверяемое утверждение оставаться вакуумным.

Отдельно проверяется, что сама инъекция состоялась: подстановка, ничего не
заменившая, дала бы «зелёный контроль» на неизменённом дереве и была бы
доказательством наоборот.

    python3 scripts/change-graph-gate/selftest/inject.py

Исходов три: 0 — все инъекции доказаны; 1 — есть недоказанная; 2 — инъекций
ноль, проба беспредметна.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
GATE_DIR = os.path.abspath(os.path.join(HERE, ".."))

FAIL_LINE = re.compile(r"^  FAIL (.+)$")

sys.path.insert(0, GATE_DIR)
from cglib import registry as registry_module  # noqa: E402


def declared_case_count():
    """Сколько кейсов осматривает prove.py. Число ВЫВОДИТСЯ, а не выписано.

    Имя утверждения B1 несёт перепись осмотренного, поэтому меняется вместе с
    деревом: положили модуль семейства — число выросло. Выписанное здесь
    число было бы вторым местом об одном предмете и разошлось бы с деревом
    молча, а расхождение выглядело бы недоказанной инъекцией, то есть
    находкой о механизме там, где менялся только его предмет. Ровно это и
    случилось при заведении семейств cg.tdd/cg.review/cg.class/cg.design:
    ведомость называла 17 при 50 в дереве.

    Считается тем же обходом, что и в prove.py: каталог testdata, чьё
    семейство испытуемый объявил.
    """
    families = set(registry_module.load())
    testdata = os.path.join(GATE_DIR, "tests", "testdata")
    total = 0
    for case_id in os.listdir(testdata):
        if not os.path.isdir(os.path.join(testdata, case_id)):
            continue
        try:
            family = registry_module.family_of(case_id)
        except Exception:
            continue
        if family in families:
            total += 1
    return total


B1_ASSERTION = (
    "B1 все %d объявленных кейса дали объявленную тройку И совпавший код"
    % declared_case_count()
)

# (имя, относительный путь, что заменить, на что, какие утверждения обязаны пасть)
INJECTIONS = [
    (
        "I1 предикат семейства перестал судить мир",
        "cglib/families/boot.py",
        "    return _declared_admission(world) != REGISTERED_ADMISSION",
        "    _declared_admission(world)\n    return False",
        # Проба обязана НАЗВАТЬ координату, а не только объявить итог, поэтому
        # среди ожидаемого стоит и поимённая строка кейса.
        ["B SDD-1-BOOT-02",
         B1_ASSERTION,
         "C1 SDD-1-BOOT-01: дефектный мир под положительным ID даёт "
         "CG_BOOTSTRAP_NOT_UNIQUE"],
    ),
    (
        "I2 собственный отказ выдаётся за вердикт о предмете",
        "run.py",
        '    sys.stderr.flush()\n    return outcome_module.SELF_FAILURE_EXIT',
        '    sys.stderr.flush()\n'
        '    sys.stdout.write("GREEN · CG_OK · exit 0\\n")\n'
        '    return 0',
        ["D1 мира по пути нет -> собственный отказ, stdout пуст",
         "D2 мир не разбирается как YAML -> собственный отказ",
         "D3 мир не отображение -> собственный отказ",
         "D4 идентификатор кейса не разбирается -> собственный отказ",
         "D5 семейство кейса не объявлено -> собственный отказ, НЕ вердикт",
         "D6 без обязательных аргументов -> собственный отказ",
         "D7 ни одно правило не применимо -> собственный отказ, а НЕ vacuous GREEN",
         "D8 непрочитанный факт внутри предмета -> собственный отказ",
         "D9 роль вердикта не приводится к artifact -> собственный отказ"],
    ),
    (
        "I3 неосмотренный мир объявляется чистым",
        "cglib/rules.py",
        "    if not applicable:",
        "    if False and not applicable:",
        ["D7 ни одно правило не применимо -> собственный отказ, а НЕ vacuous GREEN"],
    ),
    (
        "I4 непрочитанный факт мира перестал быть находкой",
        "cglib/rules.py",
        "    if unread:",
        "    if False and unread:",
        ["D8 непрочитанный факт внутри предмета -> собственный отказ"],
    ),
    # I6..I9 — по одной инъекции на семейство этой полосы. Предмет у них общий:
    # предикат, переставший судить мир, обязан быть НАЙДЕН, а не пережить
    # прогон молча. Инъекция снимает ТОЛЬКО решение и сохраняет чтение фактов:
    # снятое чтение уронило бы прогон собственным отказом «факт не прочитан», и
    # краснота пришла бы от ядра, а не от проверяемого правила (п. 2в
    # `testing.md` §«Гейт на класс»).
    (
        "I6 cg.tdd перестал отличать unexpected GREEN от честного красного",
        "cglib/families/tdd.py",
        '    return world.read("initial_holder.category") == outcome.CATEGORY_GREEN',
        '    world.read("initial_holder.category")\n    return False',
        ["B SDD-1-TDD-03",
         B1_ASSERTION,
         "C1 SDD-1-TDD-02: дефектный мир под положительным ID даёт "
         "CG_RED_PROOF_UNEXPECTED_GREEN"],
    ),
    (
        "I7 cg.review перестал сверять artifact с событием",
        "cglib/families/review.py",
        "    return artifact != mirrored",
        "    return False",
        ["B SDD-1-REVIEW-06",
         B1_ASSERTION,
         "C1 SDD-1-REVIEW-01: дефектный мир под положительным ID даёт "
         "CG_BOOTSTRAP_ACTOR_SPOOFED"],
    ),
    (
        "I8 cg.class перестал требовать mapping каждого exposure item",
        "cglib/families/klass.py",
        "    return any(\n"
        "        _absent(mapping.get(item)) for item in REGISTERED_INITIAL_ITEM_IDS\n"
        "    )",
        "    return False",
        ["B SDD-1-CLASS-05",
         B1_ASSERTION,
         "C1 SDD-1-CLASS-04: дефектный мир под положительным ID даёт "
         "CG_CLASS_ITEM_UNMAPPED"],
    ),
    (
        "I9 cg.design перестал требовать пройденных applicable reviews",
        "cglib/families/design.py",
        "    return any(\n"
        "        declared.get(review) != VERIFIED\n"
        "        for review in REGISTERED_PRECODE_REVIEWS\n"
        "    )",
        "    return False",
        ["B SDD-1-DESIGN-03",
         B1_ASSERTION,
         "C1 SDD-1-DESIGN-01: дефектный мир под положительным ID даёт "
         "CG_PRECODE_REVIEW_MISSING"],
    ),
    (
        "I5 перечень признаков выписан списком вместо обхода дерева",
        "cglib/registry.py",
        "    return sorted(capability_token(family) for family in load())",
        '    load()\n    return ["cg.boot", "cg.hash", "cg.nonempty", "cg.truth"]',
        ["A5 снятие модуля семейства снимает признак — перечень выведен из дерева"],
    ),
]


def prepare(work, name):
    destination = os.path.join(work, name)
    shutil.copytree(
        GATE_DIR, destination,
        ignore=shutil.ignore_patterns("__pycache__", "tests"),
    )
    # Дерево проб копируется отдельно и только чтением: fixtures принадлежат
    # pre-RED diff, и трогать их здесь нельзя даже во временной копии.
    os.symlink(os.path.join(GATE_DIR, "tests"), os.path.join(destination, "tests"))
    return destination


def run_prove(root):
    completed = subprocess.run(
        [sys.executable, os.path.join(root, "selftest", "prove.py")],
        capture_output=True, text=True, timeout=600,
    )
    failed = []
    for line in completed.stdout.split("\n"):
        match = FAIL_LINE.match(line)
        if match:
            failed.append(match.group(1).strip())
    return completed.returncode, failed, completed.stdout


def main():
    passed = 0
    broken = 0
    with tempfile.TemporaryDirectory(prefix="cg-inject-") as work:
        control_root = prepare(work, "control")
        code, failed, _ = run_prove(control_root)
        if code == 0 and not failed:
            passed += 1
            sys.stdout.write("  OK   контроль: нетронутое дерево зелено\n")
        else:
            broken += 1
            sys.stdout.write(
                "  FAIL контроль: нетронутое дерево дало код %d и находки %s\n"
                % (code, failed)
            )

        for index, (name, relpath, needle, replacement, expected) in enumerate(
            INJECTIONS
        ):
            root = prepare(work, "inject-%d" % index)
            target = os.path.join(root, relpath)
            with open(target, encoding="utf-8") as handle:
                source = handle.read()
            if needle not in source:
                broken += 1
                sys.stdout.write(
                    "  FAIL %s: подстановка не состоялась — образец не найден в %s\n"
                    % (name, relpath)
                )
                continue
            with open(target, "w", encoding="utf-8") as handle:
                handle.write(source.replace(needle, replacement, 1))

            code, failed, output = run_prove(root)
            missing = [item for item in expected if item not in failed]
            extra = [item for item in failed if item not in expected]
            if code == 1 and not missing and not extra:
                passed += 1
                sys.stdout.write(
                    "  OK   %s -> покраснело ровно %d ожидаемых утверждений\n"
                    % (name, len(expected))
                )
            else:
                broken += 1
                sys.stdout.write(
                    "  FAIL %s: код %d; не покраснело %s; покраснело лишнее %s\n"
                    % (name, code, missing, extra)
                )

    total = passed + broken
    sys.stdout.write("\n=== перепись инъекций ===\n")
    sys.stdout.write(
        "инъекций с контролем: %d · доказано: %d · не доказано: %d\n"
        % (total, passed, broken)
    )
    if total == 0:
        sys.stdout.write("проба беспредметна: инъекций ноль\n")
        return 2
    return 1 if broken else 0


if __name__ == "__main__":
    raise SystemExit(main())
