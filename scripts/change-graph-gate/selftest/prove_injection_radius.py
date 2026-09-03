#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Доказательство, что проверка радиуса инъекции семейства СПОСОБНА упасть.

Предмет проверки (`inject.py`, `check_family_injection_radius`, ws#510): радиус
инъекции семейства есть множество ОПРОШЕННЫХ кейсов этого семейства — тех, чья
fixture не пинует тройку, — и растит его полоса ФИКСТУР, а не полоса семейства.
Ведомость радиуса объявляет это множество, а проверка сверяет объявленное с
деревом ДО первого прогона инъекций. В этом весь предмет: без неё та же находка
приходит из пятнадцатиминутного прогона, обычно уже на конвейере, и адресована
не тому, кто её создал.

ЧЕМ ЭТО ДОКАЗЫВАЕТСЯ — инъекцией НАСТОЯЩИМ входом, а не прочтением. Входом
проверки служит дерево фикстур: проба строит рядом ссылочную копию настоящего
дерева, изменённую ровно на один факт, и подаёт её тем же выводом
(`prove.asked_cases_by_family`), каким проверка читает дерево. Каталог `tests/`
при этом не трогается ни разу — фикстуры принадлежат pre-RED diff.

ТРИ ПРОГОНА, И ТРЕТИЙ ОБЯЗАТЕЛЕН (`testing.md` §«Гейт на класс», п. 2в):

  * контроль — нетронутое дерево: и радиус, и соседняя проверка формы молчат;
  * инъекция НОВОГО — опрошенный кейс, которого ведомость не знает: краснеет
    ТОЛЬКО радиус, и находка НАЗЫВАЕТ кейс и семейство;
  * инъекция СУЩЕСТВУЮЩЕГО — сломанная форма ведомости: краснеет ТОЛЬКО она, а
    радиус остаётся зелёным. Без этого прогона молчание соседа было бы
    неотличимо от его смерти, а красное радиуса — от красного соседа.

ЗАКОННЫЙ БЛИЗНЕЦ у каждой оси стоит рядом и обязан МОЛЧАТЬ. Главный из них —
кейс, добавленный С ПИНОМ: он изолирует ровно дискриминатор (`sut_stub`), то
есть отвечает на вопрос «реагирует ли проверка на всякий новый кейс или только
на опрошенный». Законность самой такой фикстуры судит harness (утверждение `B4`
в `prove.py`, закрытый список `STUB_PERMITTED_CASES`), а не эта проверка, и это
названо здесь, чтобы близнец не приняли за предложение завести такую фикстуру.

    python3 scripts/change-graph-gate/selftest/prove_injection_radius.py

Исходов три: 0 — все утверждения прошли; 1 — есть провалившееся; 2 — проба
беспредметна (утверждений ноль либо дерево фикстур не читается).
"""

import contextlib
import io
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
GATE_DIR = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)

import inject as inject_module  # noqa: E402
import prove as prove_module  # noqa: E402

# Кейс, которого в дереве нет и не будет: имя выбрано ЗА пределами занятых
# номеров семейства, чтобы подстановка не могла случайно совпасть с живой
# фикстурой. Семейство `tdd` взято потому, что у него есть инъекция и десять
# опрошенных кейсов — то есть ведомость про него говорит непустое.
NEW_CASE = "SDD-1-TDD-97"
NEW_FAMILY = "tdd"

PASSED = []
FAILED = []


def check(name, condition, detail=""):
    if condition:
        PASSED.append(name)
        sys.stdout.write("  OK   %s\n" % name)
    else:
        FAILED.append(name)
        sys.stdout.write("  FAIL %s\n       %s\n" % (name, detail))


def run_check(**kwargs):
    """Зовёт проверку радиуса и возвращает пару (вердикт, напечатанное).

    Печать здесь — часть предмета, а не украшение: находка обязана НАЗЫВАТЬ
    кейс и семейство, иначе полоса фикстур получит вердикт без адреса и пойдёт
    искать причину в чужой инъекции — ровно то, ради устранения чего проверка и
    заведена.
    """
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer):
        verdict = inject_module.check_family_injection_radius(**kwargs)
    return verdict, buffer.getvalue()


def run_shape(**kwargs):
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer):
        verdict = inject_module.check_ledger_shape(**kwargs)
    return verdict, buffer.getvalue()


def mirrored_testdata(work, extra_case, extra_manifest):
    """Ссылочная копия НАСТОЯЩЕГО дерева фикстур плюс один кейс.

    Копируются ссылки, а не содержимое: дерево кейсов велико, а проверке нужен
    только состав и манифест. Настоящий каталог `tests/` при этом остаётся
    нетронутым — ни записи, ни правки.
    """
    root = os.path.join(work, "testdata-%s" % extra_case)
    os.mkdir(root)
    for name in os.listdir(prove_module.TESTDATA):
        source = os.path.join(prove_module.TESTDATA, name)
        if os.path.isdir(source):
            os.symlink(source, os.path.join(root, name))
    added = os.path.join(root, extra_case)
    os.mkdir(added)
    with open(os.path.join(added, "case.yaml"), "w", encoding="utf-8") as handle:
        handle.write(extra_manifest)
    return root


def main():
    sys.stdout.write("== Радиус инъекции семейства: способность упасть ==\n")

    tree = prove_module.asked_cases_by_family()
    families = sorted(inject_module.FAMILY_ASKED_ROSTER)
    # Предпосылка пробы называется ЧИСЛОМ и проверяется: на пустом дереве всё
    # нижеследующее зеленело бы вакуумно, «ноль находок» было бы неотличимо от
    # «ноль прочитанного».
    if not tree or not families or NEW_FAMILY not in tree:
        sys.stdout.write(
            "  проба беспредметна: семейств в дереве %d, записей радиуса %d, "
            "семейство %s в дереве %s\n"
            % (len(tree), len(families), NEW_FAMILY, NEW_FAMILY in tree)
        )
        return 2

    # --- контроль: нетронутое дерево -----------------------------------------
    verdict, printed = run_check()
    check(
        "R0 контроль: на нетронутом дереве радиус молчит",
        verdict and "FAIL" not in printed,
        printed.strip(),
    )
    # Перепись обязана печатать ОБЕ величины — прочитанное в дереве и
    # объявленное ведомостью. Одно число скрывает ровно тот случай, ради
    # которого проверка заведена.
    check(
        "R0-перепись объём осмотренного напечатан числами, и величин ОБЕ",
        "инъекций семейства" in printed
        and "опрошенных кейсов в дереве" in printed
        and "объявлено радиусом" in printed,
        printed.strip(),
    )

    with tempfile.TemporaryDirectory(prefix="cg-radius-") as work:
        # --- инъекция: опрошенный кейс, которого ведомость не знает ----------
        asked_root = mirrored_testdata(work, NEW_CASE, "{}\n")
        grown = prove_module.asked_cases_by_family(asked_root)
        check(
            "R1-предпосылка подстановка состоялась: кейс появился среди "
            "опрошенных",
            NEW_CASE in grown.get(NEW_FAMILY, ()),
            "опрошенные %s: %s" % (NEW_FAMILY, grown.get(NEW_FAMILY, ())),
        )
        verdict, printed = run_check(asked=grown)
        check(
            "R1 новый ОПРОШЕННЫЙ кейс семейства — находка",
            not verdict,
            printed.strip(),
        )
        check(
            "R1-адрес находка НАЗЫВАЕТ кейс и семейство, а не только итог",
            not verdict and NEW_CASE in printed and NEW_FAMILY in printed,
            printed.strip(),
        )

        # --- законный близнец: тот же кейс, но С ПИНОМ -----------------------
        pinned_root = mirrored_testdata(
            work,
            NEW_CASE + "-PIN",
            "sut_stub:\n  category: RED\n  diagnostic: CG_STUB\n  exit: 10\n",
        )
        # Имя каталога-близнеца отличается от имени кейса намеренно: пин
        # снимает кейс с опроса, поэтому проверка обязана молчать независимо от
        # того, как каталог называется, — и это видно по составу опрошенных.
        pinned = prove_module.asked_cases_by_family(pinned_root)
        check(
            "R2-предпосылка пиновавший кейс среди опрошенных НЕ появился",
            pinned.get(NEW_FAMILY, ()) == tree.get(NEW_FAMILY, ()),
            "опрошенные %s: %s" % (NEW_FAMILY, pinned.get(NEW_FAMILY, ())),
        )
        verdict, printed = run_check(asked=pinned)
        check(
            "R2 законный близнец: кейс, добавленный С ПИНОМ, молчание",
            verdict and "FAIL" not in printed,
            printed.strip(),
        )

    # --- самоистечение: имя в радиусе, которого дерево больше не опрашивает --
    vanished = dict(tree)
    dropped = inject_module.FAMILY_ASKED_ROSTER[NEW_FAMILY][0]
    vanished[NEW_FAMILY] = tuple(
        case for case in tree[NEW_FAMILY] if case != dropped
    )
    verdict, printed = run_check(asked=vanished)
    check(
        "R3 имя в радиусе, потерявшее предмет, — находка с именем кейса",
        not verdict and dropped in printed,
        printed.strip(),
    )

    # --- самоистечение: запись радиуса, у семейства которой инъекции нет -----
    orphan = dict(inject_module.FAMILY_ASKED_ROSTER)
    orphan["nonempty"] = ("SDD-1-NONEMPTY-01",)
    verdict, printed = run_check(roster=orphan)
    check(
        "R4 запись радиуса без инъекции — находка с именем семейства",
        not verdict and "nonempty" in printed,
        printed.strip(),
    )

    # --- семейство с инъекцией, но без записи радиуса ------------------------
    silent = {
        family: cases
        for family, cases in inject_module.FAMILY_ASKED_ROSTER.items()
        if family != NEW_FAMILY
    }
    verdict, printed = run_check(roster=silent)
    check(
        "R5 инъекция семейства без записи радиуса — находка с именем семейства",
        not verdict and NEW_FAMILY in printed,
        printed.strip(),
    )

    # --- ожидание, назвавшее кейс не из опрошенных этого семейства -----------
    stray = list(inject_module.INJECTIONS) + [
        (
            "синтетическая инъекция с ожиданием мимо радиуса",
            "cglib/families/tdd.py",
            "нечего заменять",
            "нечем заменять",
            ["B " + NEW_CASE],
        )
    ]
    verdict, printed = run_check(injections=stray)
    check(
        "R6 ожидание, назвавшее кейс не из опрошенных семейства, — находка",
        not verdict and NEW_CASE in printed,
        printed.strip(),
    )

    # --- предпосылка: модуль семейства, который не читается -------------------
    # Отказ предпосылки обязан быть НАХОДКОЙ с текстом, а не разбором стека:
    # разбор стека до первого прогона выглядит поломкой прогонщика, и его идут
    # чинить вместо того, что сломалось.
    absent = list(inject_module.INJECTIONS) + [
        (
            "синтетическая инъекция в несуществующий модуль семейства",
            "cglib/families/нет-такого-модуля.py",
            "нечего заменять",
            "нечем заменять",
            [],
        )
    ]
    verdict, printed = run_check(injections=absent)
    check(
        "R9 нечитаемый модуль семейства — находка с текстом, а не разбор стека",
        not verdict and "нет-такого-модуля" in printed,
        printed.strip(),
    )

    # Модуль БЕЗ объявления `FAMILY` — тот же отказ предпосылки. Отдельным
    # утверждением он стоит потому, что ломается иначе: сведи его в общую
    # корзину с семействами, и ключ `None` рядом со строками уронил бы
    # сортировку — то есть отказ предпосылки вышел бы разбором стека.
    nameless = list(inject_module.INJECTIONS) + [
        (
            "синтетическая инъекция в модуль без объявления семейства",
            "cglib/families/__init__.py",
            "нечего заменять",
            "нечем заменять",
            [],
        )
    ]
    verdict, printed = run_check(injections=nameless)
    check(
        "R9-близнец модуль без FAMILY — находка, а не падение сортировки",
        not verdict and "не объявил FAMILY" in printed,
        printed.strip(),
    )

    # --- пустой обход есть находка, а не успех -------------------------------
    verdict, printed = run_check(asked={})
    check(
        "R7 пустой обход — находка, и перепись при ней напечатана",
        not verdict and "обход пуст" in printed and "опрошенных кейсов" in printed,
        printed.strip(),
    )

    # --- п. 2в: инъекция СУЩЕСТВУЮЩЕГО контроля ------------------------------
    # Красное обязано приходить от НАЗВАННОГО, а не «откуда-нибудь из преамбулы».
    broken_ledger = list(inject_module.INJECTIONS) + [("склейка", "потерявшая", "поле")]
    shape_verdict, shape_printed = run_shape(injections=broken_ledger)
    radius_verdict, radius_printed = run_check()
    check(
        "R8 инъекция соседа: форма ведомости краснеет",
        not shape_verdict,
        shape_printed.strip(),
    )
    check(
        "R8-близнец при красном соседе радиус остаётся ЗЕЛЁНЫМ — красное "
        "приходит от названного",
        radius_verdict and "FAIL" not in radius_printed,
        radius_printed.strip(),
    )
    shape_verdict, shape_printed = run_shape()
    check(
        "R8-контроль на нетронутой ведомости молчит и сосед",
        shape_verdict and "FAIL" not in shape_printed,
        shape_printed.strip(),
    )

    total = len(PASSED) + len(FAILED)
    sys.stdout.write(
        "\n== перепись: утверждений %d · прошло %d · провалено %d; семейств с "
        "радиусом %d, опрошенных кейсов в них %d ==\n"
        % (
            total,
            len(PASSED),
            len(FAILED),
            len(families),
            sum(len(inject_module.FAMILY_ASKED_ROSTER[f]) for f in families),
        )
    )
    if total == 0:
        return 2
    return 1 if FAILED else 0


if __name__ == "__main__":
    raise SystemExit(main())
