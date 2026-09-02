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

# Сводное утверждение прогона кейсов. Числа в имени нет НАМЕРЕННО: счёт кейсов
# растёт от каждого нового семейства, а ожидания инъекций перечисляют имена
# дословно — то есть счёт в имени сталкивал бы параллельные полосы by
# construction, и столкновение выглядело бы как недоказанная инъекция. Обе
# ТРИ полосы сведения нашли этот класс независимо и починили по-разному: две
# вывели число из дерева (одна — своим обходом, то есть копией обхода
# prove.py), третья убрала его из имени. Оставлено третье —
# выведенное число вычисляется на НЕТРОНУТОМ дереве, а prove.py печатает его по
# ИНЪЕЦИРОВАННОМУ, поэтому инъекция, меняющая состав семейств, разошлась бы
# сама с собой.
B1 = "B1 каждый объявленный кейс дал объявленную приёмкой тройку И совпавший код"

# (имя, относительный путь, что заменить, на что, какие утверждения обязаны пасть)
# Имя инъекции — БЕЗ порядкового номера, и это решение, а не небрежность.
# Номер нигде не читается (он не адресует ни утверждение, ни ожидание — только
# печатается), зато занимается монотонно: три параллельные полосы независимо
# взяли I6, и сведение получило три разных инъекции под одним именем. Ярлык,
# ничего не дающий и сталкивающий полосы by construction, снят целиком.
# Уникальность держит предмет: две инъекции, снимающие разные предикаты,
# описываются разными фразами сами собой.
INJECTIONS = [
    (
        "предикат семейства перестал судить мир",
        "cglib/families/boot.py",
        "    return _declared_admission(world) != REGISTERED_ADMISSION",
        "    _declared_admission(world)\n    return False",
        # Проба обязана НАЗВАТЬ координату, а не только объявить итог, поэтому
        # среди ожидаемого стоит и поимённая строка кейса.
        ["B SDD-1-BOOT-02",
         B1,
         "C1 SDD-1-BOOT-01: дефектный мир под положительным ID даёт "
         "CG_BOOTSTRAP_NOT_UNIQUE"],
    ),
    (
        "собственный отказ выдаётся за вердикт о предмете",
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
        "неосмотренный мир объявляется чистым",
        "cglib/rules.py",
        "    if not applicable:",
        "    if False and not applicable:",
        ["D7 ни одно правило не применимо -> собственный отказ, а НЕ vacuous GREEN"],
    ),
    (
        "непрочитанный факт мира перестал быть находкой",
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
        "cg.tdd перестал отличать unexpected GREEN от честного красного",
        "cglib/families/tdd.py",
        '    return world.read("initial_holder.category") == outcome.CATEGORY_GREEN',
        '    world.read("initial_holder.category")\n    return False',
        ["B SDD-1-TDD-03",
         B1,
         "C1 SDD-1-TDD-02: дефектный мир под положительным ID даёт "
         "CG_RED_PROOF_UNEXPECTED_GREEN"],
    ),
    (
        "cg.review перестал сверять artifact с событием",
        "cglib/families/review.py",
        "    return artifact != mirrored",
        "    return False",
        ["B SDD-1-REVIEW-06",
         B1,
         "C1 SDD-1-REVIEW-01: дефектный мир под положительным ID даёт "
         "CG_BOOTSTRAP_ACTOR_SPOOFED"],
    ),
    (
        # Снимается ОДНО решение — сверка actor'а с versioned policy allowlist,
        # — а чтения таблицы, требуемой роли и actor'а события остаются выше по
        # телу предиката. Инъекция, убравшая заодно и чтение, уронила бы прогон
        # собственным отказом «факт не прочитан», и краснота пришла бы от учёта
        # фактов, а не от снятого предиката (п. 2в `testing.md` §«Гейт на класс»).
        "cg.auth перестал сверять actor с versioned policy allowlist",
        "cglib/families/auth.py",
        "    return required not in _roles_allowing(allowlist, actor)",
        "    _roles_allowing(allowlist, actor)\n    return False",
        ["B SDD-1-AUTH-03",
         B1,
         "C1 SDD-1-AUTH-01: дефектный мир под положительным ID даёт "
         "CG_REVIEW_ACTOR_UNAUTHORIZED",
         "F-AUTH-1 чужой actor при верной роли краснит только правило о допуске"],
    ),
    (
        "cg.class перестал требовать mapping каждого exposure item",
        "cglib/families/klass.py",
        "    return any(\n"
        "        _absent(mapping.get(item)) for item in REGISTERED_INITIAL_ITEM_IDS\n"
        "    )",
        "    return False",
        ["B SDD-1-CLASS-05",
         B1,
         "C1 SDD-1-CLASS-04: дефектный мир под положительным ID даёт "
         "CG_CLASS_ITEM_UNMAPPED"],
    ),
    (
        "cg.design перестал требовать пройденных applicable reviews",
        "cglib/families/design.py",
        "    return any(\n"
        "        declared.get(review) != VERIFIED\n"
        "        for review in REGISTERED_PRECODE_REVIEWS\n"
        "    )",
        "    return False",
        ["B SDD-1-DESIGN-03",
         B1,
         "C1 SDD-1-DESIGN-01: дефектный мир под положительным ID даёт "
         "CG_PRECODE_REVIEW_MISSING"],
    ),
    (
        # Сама C0 — проверка перечня, поэтому обязана уметь упасть: иначе она
        # экземпляр ровно того класса, который ловит. Инъекция снимает ОДНУ
        # пару и оставляет остальные — тогда краснеет только C0, и видно, что
        # она читает согласие перечня с деревом, а не своё объявление.
        "семейство выпало из перечня пар и об этом не сообщается",
        "selftest/prove.py",
        '        ("SDD-1-POLICY-01", "SDD-1-POLICY-02", '
        '"CG_POLICY_REPOSITORY_MISSING"),\n',
        "",
        ["C0 у каждого объявленного семейства есть своя пара"],
    ),
    (
        "перечень признаков выписан списком вместо обхода дерева",
        "cglib/registry.py",
        "    return sorted(capability_token(family) for family in load())",
        '    load()\n    return ["cg.boot", "cg.hash", "cg.nonempty", "cg.truth"]',
        ["A5 снятие модуля семейства снимает признак — перечень выведен из дерева"],
    ),
    # --- по инъекции на семейство полосы адаптера/провязки/замещения ---------
    # Каждая снимает ОДИН предикат и сохраняет его ЧТЕНИЯ. Инъекция, убравшая
    # заодно и чтение, роняла бы испытуемого собственным отказом
    # (CG_SELF_WORLD_FACT_UNREAD) — то есть краснота приходила бы от учёта
    # фактов, а не от снятого предиката, и проверяемое свойство осталось бы
    # неизмеренным (`testing.md` §«Гейт на класс», п. 2в).
    (
        "расхождение производного перестало судиться",
        "cglib/families/adapter.py",
        "    for coordinate in sorted(owned):\n"
        "        if _is_foreign(coordinate, foreign):",
        "    for coordinate in []:\n"
        "        if _is_foreign(coordinate, foreign):",
        ["B SDD-1-ADAPTER-02",
         "B SDD-1-ADAPTER-13",
         B1,
         "C1 SDD-1-ADAPTER-01: дефектный мир под положительным ID даёт "
         "CGA_DERIVED_DRIFT"],
    ),
    (
        "отсутствие обязательного вызывающего перестало судиться",
        "cglib/families/wire.py",
        "        declared = world.read_all(BLOCKING_CALLERS)\n"
        "        return declared.get(coordinate) != CALLS_GATE",
        "        declared = world.read_all(BLOCKING_CALLERS)\n"
        "        return False and declared.get(coordinate) != CALLS_GATE",
        ["B SDD-1-WIRE-02",
         "B SDD-1-WIRE-03",
         "B SDD-1-WIRE-04",
         "B SDD-1-WIRE-05",
         B1,
         "C1 SDD-1-WIRE-01: дефектный мир под положительным ID даёт "
         "CG_CALLER_WORKSPACE_PRE_PUSH_MISSING"],
    ),
    (
        "цикл замещения перестал судиться",
        "cglib/families/super.py",
        "    return coordinate in ancestry or coordinate == old_id",
        "    return False and (coordinate in ancestry or coordinate == old_id)",
        ["B SDD-1-SUPER-04",
         B1,
         "C1 SDD-1-SUPER-01: дефектный мир под положительным ID даёт "
         "CG_SUPERSEDE_CYCLE"],
    ),
    (
        "отпечаток манифеста перестал сверяться с содержимым",
        "cglib/families/holder.py",
        "        return declared != observed",
        "        declared != observed\n        return False",
        # Читать координаты правило продолжает — иначе краснота пришла бы от
        # переписи непрочитанного, а не от снятой сверки.
        ["B SDD-1-HOLDER-06", "B SDD-1-HOLDER-07", "B SDD-1-HOLDER-08",
         "B SDD-1-HOLDER-09", "B SDD-1-HOLDER-10", B1,
         "C1 SDD-1-HOLDER-01: дефектный мир под положительным ID даёт "
         "CG_HOLDER_SUBJECT_HASH_MISMATCH"],
    ),
    (
        "команда, не умеющая отказать, перестала быть находкой",
        "cglib/families/holder.py",
        "    return str(executable).strip() in TRIVIAL_EXECUTABLES",
        "    str(executable).strip()\n    return False",
        ["B SDD-1-HOLDER-03", B1,
         "F-HOLDER-1 на команде true краснеют оба правила, вердикт — по "
         "объявленному порядку"],
    ),
    (
        "держатель перестал быть обязан краснеть на injected defect",
        "cglib/families/birth.py",
        '    return world.read("birth_runs.%s" % RUN_INJECTED_DEFECT) '
        "!= FAIL_OUTCOME",
        '    world.read("birth_runs.%s" % RUN_INJECTED_DEFECT)\n    return False',
        # Ровно тот дефект, ради которого рождение и заведено: держатель,
        # который не может упасть, становится неотличим от молчавшего.
        ["B SDD-1-BIRTH-03", B1,
         "C1 SDD-1-BIRTH-01: дефектный мир под положительным ID даёт "
         "CG_BIRTH_DEFECT_NOT_DETECTED",
         "F-BIRTH-2 держателя, зелёного на всём, ловит правило injected "
         "defect — и только оно"],
    ),
    (
        "«не выполнилось» подменяется красным вердиктом",
        "cglib/families/evid.py",
        '        diagnostic="CG_REQUIRED_HOLDER_NOT_EXECUTED",\n'
        "        category=outcome.CATEGORY_NOT_EXECUTED,",
        '        diagnostic="CG_REQUIRED_HOLDER_NOT_EXECUTED",\n'
        "        category=outcome.CATEGORY_RED,",
        ["B SDD-1-EVID-04", B1,
         "F-EVID-1 неисполненный держатель даёт NOT_EXECUTED, а не RED"],
    ),
    (
        "отсутствующий вывод держателя перестал быть находкой",
        "cglib/families/evid.py",
        "    return bool(_holders_without_usable_output(world))",
        "    _holders_without_usable_output(world)\n    return False",
        ["B SDD-1-EVID-05", B1],
    ),
    (
        "evidence перестало проверяться на выполнение predicate",
        "cglib/families/na.py",
        "    return evidence[coordinate] != satisfying_value",
        "    evidence[coordinate]\n    return False",
        ["B SDD-1-NA-03", B1,
         "C1 SDD-1-NA-01: дефектный мир под положительным ID даёт "
         "CG_NA_PREDICATE_FALSE",
         "F-NA-2-близнец зарегистрированный, но невыполненный предикат краснит "
         "правило о evidence"],
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
