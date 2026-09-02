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
# Имя утверждения берётся ЦЕЛИКОМ. Первая редакция отсекала хвост после «->»
# — форма была перенесена из вывода ЭТОГО прогонщика, где стрелка и правда
# хвост («имя -> покраснело ровно N»). У prove.py стрелка стоит ВНУТРИ имени
# («D1 мира по пути нет -> собственный отказ»), поэтому перечень выводился
# обрезанным, а сравнивался с полными именами из FAIL — и все тринадцать
# утверждений объявлялись «лишними». Читать чужой вывод своей формой нельзя.
OK_LINE = re.compile(r"^  OK   (.+)$")

# Маркер «все утверждения о собственном отказе», раскрываемый по КОНТРОЛЬНОМУ
# прогону, а не выписанный именами.
#
# Инъекция, подменяющая собственный отказ вердиктом, обязана уронить КАЖДОЕ
# утверждение этого класса, а класс растёт: своё утверждение о собственном
# отказе заводит всякая полоса, которой оно нужно. Рукописный перечень делал
# ожидание вторым местом об одном предмете — и ломал инъекцию у следующей же
# полосы: она отчитывалась «покраснело лишнее» о том, что покраснеть было
# ОБЯЗАНО, то есть находка приходила о механизме там, где менялся его предмет.
#
# Признак класса — в самом имени утверждения: «собственный отказ». Это не
# эвристика, а контракт ядра: три собственных отказа названы так дословно, и
# всякое утверждение о них обязано это слово нести, иначе читатель прогона не
# отличит их от вердиктов о предмете.
EVERY_SELF_FAILURE = "<все утверждения о собственном отказе>"
SELF_FAILURE_MARK = "собственный отказ"

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
        [EVERY_SELF_FAILURE],
    ),
    (
        "неосмотренный мир объявляется чистым",
        "cglib/rules.py",
        "    if not applicable:",
        "    if False and not applicable:",
        ["D7 ни одно правило не применимо -> собственный отказ, а НЕ vacuous GREEN",
         # Якорь вызывающих семейств утверждает ровно ту же половину
         # различения, что D1..D9: «не знаю» не выдаётся за «нет».
         # Инъекция, стирающая это различение, обязана уронить и его —
         # иначе список ожидаемого был бы у́же того, что она ломает.
         "G-ANCHOR SDD-1-WSCI-01: чужой мир под ID вызывающего даёт "
         "собственный отказ, а НЕ вердикт",
         "G-ANCHOR SDD-1-WSPP-01: чужой мир под ID вызывающего даёт "
         "собственный отказ, а НЕ вердикт",
         "D7 ни одно правило не применимо -> собственный отказ, а НЕ vacuous "
         "GREEN",
         "F-WITHDRAW-1 отзыв не от владельца даёт собственный отказ, а НЕ "
         "зелёный вердикт"],
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
        # Неполнота выражена СВОЙСТВОМ, а не списком имён, и это решение.
        #
        # Здесь стоял выписанный перечень из четырёх имён — второе место об
        # одном предмете, растущее вместе с деревом (задача #487). Замер
        # показал, что заявленный механизм порчи не тот: подмена, доведённая
        # «до полного списка», A5 НЕ зеленит — cg.boot остаётся в ответе после
        # снятия модуля, и утверждение краснеет так же. Опасна другая правка,
        # выглядящая столь же безобидно: перечень БЕЗ cg.boot. Он тоже роняет
        # A5 — но по чужой причине («признак не объявлен вовсе»), и инъекция
        # становится вакуумной, оставаясь на вид рабочей.
        #
        # Поэтому подмена больше не называет ни одного семейства. Она меняет
        # СВОЙСТВО ответа: объявление, однажды вычисленное, запоминается рядом
        # с модулем и переживает своё основание — снятый модуль семейства из
        # ответа не уходит. Что бы ни выросло в дереве, подстановка остаётся
        # верной: она не знает состава и не может от него отстать.
        #
        # Половина A5, отвечающая за «чужую причину», разведена отдельным
        # утверждением A5-контроль: подмена, потерявшая cg.boot, роняет его, и
        # прогонщик сообщает «покраснело лишнее» вместо ложного «доказано».
        "объявление признаков отвечает из памяти, а не из обхода дерева",
        "cglib/registry.py",
        "    return sorted(capability_token(family) for family in load())",
        '    import json\n'
        '    import os\n'
        '    memo = os.path.join(\n'
        '        os.path.dirname(os.path.abspath(__file__)), "capabilities.memo"\n'
        '    )\n'
        '    if os.path.exists(memo):\n'
        '        with open(memo, encoding="utf-8") as handle:\n'
        '            return json.load(handle)\n'
        '    tokens = sorted(capability_token(family) for family in load())\n'
        '    with open(memo, "w", encoding="utf-8") as handle:\n'
        '        json.dump(tokens, handle)\n'
        '    return tokens',
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
    # --- по инъекции на семейство полосы сходимости/отзыва/драйвера ---------
    # Каждая снимает ОДИН предикат и сохраняет его ЧТЕНИЯ: снятое чтение уронило
    # бы испытуемого собственным отказом «факт не прочитан», и краснота пришла бы
    # от учёта фактов, а не от снятого предиката (п. 2в `testing.md` §«Гейт на
    # класс»).
    (
        "сходимость перестала сверять актора со списком его роли",
        "cglib/families/conv.py",
        "    return actor not in allowed",
        "    actor not in allowed\n    return False",
        ["B SDD-1-CONV-02",
         B1,
         "C1 SDD-1-CONV-01: дефектный мир под положительным ID даёт "
         "CG_CONVERGENCE_OWNER_UNAUTHORIZED"],
    ),
    (
        "отзыв приземлённого изменения перестал быть находкой",
        "cglib/families/withdraw.py",
        "    return str(world.read(SOURCE_STATE)).strip() == LANDED_STATE",
        "    str(world.read(SOURCE_STATE)).strip()\n    return False",
        ["B SDD-1-WITHDRAW-02",
         B1,
         "C1 SDD-1-WITHDRAW-01: дефектный мир под положительным ID даёт "
         "CG_WITHDRAW_AFTER_LANDING"],
    ),
    (
        # Ожидаемая краснота здесь ОДНА, и это само по себе измерение: матрица
        # трёх кейсов cg.driver испытуемого о мире не спрашивает (fixture пинует
        # тройку), поэтому снятие его предиката матрицу не трогает вовсе.
        # Единственный, кто это видит, — пара секции C.
        "birth-запись драйвера перестала сверять код возврата с категорией",
        "cglib/families/driver.py",
        "    if exit_code != outcome.SUBJECT_EXIT_CODES[category]:\n"
        "        return True\n",
        "",
        ["C1 SDD-1-DRIVER-02: дефектный мир под положительным ID даёт "
         "CG_DRIVER_BIRTH_TRIPLE_INVALID"],
    ),
    (
        # Исключение из секции B обязано быть немаскируемым: расширь его — и B
        # перестанет спрашивать испытуемого вовсе, оставаясь зелёной, потому что
        # «совпало 0 из 0» есть истина. Ловит это только сверка с закрытым
        # списком harness'а — сигналом, которого секция не производит сама.
        "исключение из секции B расширено за пределы закрытого списка",
        "selftest/prove.py",
        '        if manifest.get("sut_stub") is None:',
        "        if False:",
        ["B2 скормленная тройка дословно равна объявленной приёмкой",
         "B4 исключены только кейсы из закрытого списка harness'а — "
         "исключение немаскируемо"],
    ),
    (
        # Снимается ТОЛЬКО решение: оба чтения (эпоха и валидность package)
        # остаются на месте, иначе прогон упал бы собственным отказом «факт не
        # прочитан» и краснота пришла бы от учёта фактов, а не от снятого
        # предиката (п. 2в `testing.md` §«Гейт на класс»).
        "cg.dag перестал требовать package после cutover",
        "cglib/families/dag.py",
        "    return _cutover_before_base(world) and missing",
        "    _cutover_before_base(world)\n    return False",
        ["B SDD-1-DAG-05",
         B1,
         "C1 SDD-1-DAG-04: дефектный мир под положительным ID даёт "
         "CG_PACKAGE_REQUIRED_AFTER_CUTOVER"],
    ),
    (
        # Владение diff'ом перестало судиться. Инъекция снимает ТОЛЬКО решение и
        # сохраняет оба чтения: сняв их, она уронила бы прогон собственным
        # отказом «факт не прочитан», и краснота пришла бы от учёта фактов, а не
        # от снятого предиката (п. 2в `testing.md` §«Гейт на класс»).
        "cg.diff перестал судить принадлежность фактического содержимого",
        "cglib/families/diff.py",
        "    return any(approved.get(path) != blob for path, blob in actual.items())",
        "    [approved.get(path) for path in actual]\n    return False",
        # Мир с лишним путём краснит и владение, и сходимость. Со снятым
        # владением вердикт съезжает на сходимость — то есть тройка меняется,
        # а объявленный порядок перестаёт быть наблюдаемым.
        ["B SDD-1-DIFF-02",
         B1,
         "C1 SDD-1-DIFF-01: дефектный мир под положительным ID даёт "
         "CG_DIFF_PATH_UNCLAIMED",
         "F-DIFF-1 незаявленный путь краснит владение И сходимость, вердикт — "
         "по объявленному порядку"],
    ),
    (
        # Покрытие пары кейсов перестало судиться. Снимается ровно решение о
        # незакрытой паре; ветки «перечень пуст» и «запись не идентификатор»
        # остаются на месте, поэтому краснеет то и только то, что предъявляет
        # кейс с изъятым acceptance-кейсом.
        "cg.pci перестал требовать обеих половин birth inversion от tasks",
        "cglib/families/pci.py",
        "        if len(ordinals) < 2 or BASE_CASE_ORDINAL not in ordinals:\n"
        "            return True",
        "        if False and (\n"
        "            len(ordinals) < 2 or BASE_CASE_ORDINAL not in ordinals\n"
        "        ):\n"
        "            return True",
        ["B SDD-1-PCI-02",
         B1,
         "C1 SDD-1-PCI-01: дефектный мир под положительным ID даёт "
         "CG_TRACE_ID_MISSING"],
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
    # --- по инъекции на семейство полосы трассы/жизненного цикла/задач -------
    # Каждая снимает ОДИН предикат и сохраняет его ЧТЕНИЯ: инъекция, убравшая
    # заодно и чтение, роняла бы испытуемого собственным отказом
    # (CG_SELF_WORLD_FACT_UNREAD), то есть краснота приходила бы от учёта
    # фактов, а не от снятого предиката, и проверяемое свойство осталось бы
    # неизмеренным (`testing.md` §«Гейт на класс», п. 2в).
    (
        "cg.trace перестал различать направление расхождения множеств",
        "cglib/families/trace.py",
        "    return any(\n"
        "        missing and orphan for missing, orphan in "
        "_divergence(world).values()\n"
        "    )",
        "    _divergence(world)\n    return False",
        # Односторонние правила при этом целы, поэтому C1 (сирота) остаётся
        # зелёной — и видно, что покраснело именно различение направлений, а
        # не полоса трассы целиком.
        ["B SDD-1-TRACE-04", B1,
         "F-TRACE-1 двустороннее расхождение краснит только своё правило"],
    ),
    (
        "cg.life перестал отвергать пропуск обязательной стадии",
        "cglib/families/life.py",
        "    return requested != successor",
        "    return False",
        ["B SDD-1-LIFE-02", B1,
         "C1 SDD-1-LIFE-01: дефектный мир под положительным ID даёт "
         "CG_LIFECYCLE_TRANSITION_INVALID",
         "F-LIFE-2-близнец пропуск обязательной стадии краснит только правило "
         "о смежности"],
    ),
    (
        "cg.tasks перестал требовать проверенного writing-plans handoff",
        "cglib/families/tasks.py",
        '    if record.get("event") != VERIFIED_HANDOFF_EVENT:\n'
        "        return True\n"
        '    return record.get("produces") != HANDOFF_PRODUCT',
        '    record.get("event")\n'
        '    record.get("produces")\n'
        "    return False",
        ["B SDD-1-TASKS-02", B1,
         "C1 SDD-1-TASKS-01: дефектный мир под положительным ID даёт "
         "CG_WRITING_PLANS_HANDOFF_MISSING",
         "F-TASKS-2-близнец отсутствие проверенного handoff краснит только "
         "правило о производителе"],
    ),
    # --- по инъекции на семейство полосы вызывающих и advisory ---------------
    # Каждая снимает ОДИН предикат и сохраняет его ЧТЕНИЯ: инъекция, убравшая
    # заодно чтение, роняла бы испытуемого собственным отказом
    # (CG_SELF_WORLD_FACT_UNREAD), и краснота приходила бы от учёта фактов, а не
    # от снятого предиката (`testing.md` §«Гейт на класс», п. 2в).
    (
        "потерянный в поданном графе acceptance ID перестал судиться (workspace CI)",
        "cglib/families/wsci.py",
        "    return tasksmapping.lost_acceptance_id(\n"
        "        world.read_all(PACKAGE_TASKS_MAPPING)\n"
        "    )",
        "    tasksmapping.lost_acceptance_id(\n"
        "        world.read_all(PACKAGE_TASKS_MAPPING)\n"
        "    )\n"
        "    return False",
        # Среди ожидаемого стоит и G-CALLERS: снятие предиката у ОДНОГО из двух
        # вызывающих семейств обязано быть найдено пробой, которая подаёт им
        # общий mapping, — иначе расхождение между ними осталось бы
        # неизмеренным ровно так, как описано в шапке `cglib/tasksmapping.py`.
        ["B SDD-1-WSCI-02",
         B1,
         "C1 SDD-1-WSCI-01: дефектный мир под положительным ID даёт "
         "CG_TRACE_ID_MISSING",
         "G-WSCI-2 нулевая перепись mapping — потеря, а не vacuous GREEN",
         "G-WSCI-4 неполная пара среди полных найдена — счёт идёт по сериям",
         "G-WSCI-5 потерянный базовый кейс серии найден так же, как потерянный "
         "производный",
         "G-WSCI-6 два базовых кейса РАЗНЫХ серий одного семейства — неполнота, "
         "а не пара",
         "G-CALLERS неполный mapping судится ОДИНАКОВО у cg.wsci и cg.wspp"],
    ),
    (
        # Снимается РАЗЛИЧЕНИЕ серий, и только оно: ключ группы схлопывается до
        # семейства ровно так, как было до задачи #495. Тогда две базы разных
        # серий читаются парой «база + производный», и потеря производного не
        # находится. Инъекция роняет ОДНО утверждение — то, ради которого
        # заведена; близнец G-WSCI-7 обязан остаться зелёным, иначе краснота
        # приходила бы от разбора, отвергающего суффикс серии целиком, а не от
        # снятого различения.
        "различение серий схлопнуто до семейства",
        "cglib/registry.py",
        '    return (match.group("family") + (match.group("suffix") or "")).lower()',
        '    return match.group("family").lower()',
        ["G-WSCI-6 два базовых кейса РАЗНЫХ серий одного семейства — неполнота, "
         "а не пара"],
    ),
    (
        "дорога remote-ссылки от stdin до диапазона перестала судиться",
        "cglib/families/wspp.py",
        "    return not (repository and remote_sha and remote_sha == base_sha)",
        "    return False and not (\n"
        "        repository and remote_sha and remote_sha == base_sha\n"
        "    )",
        # C1 этого семейства опирается на правило о графе и потому обязан
        # остаться зелёным: инъекция роняет ТОЛЬКО проверяемое.
        ["B SDD-1-WSPP-04",
         B1,
         "G-WSPP-3 граница словаря приёмки названа: без идентичности "
         "репозитория ссылку негде разрешать"],
    ),
    (
        "authoritative evidence перестала складываться в вердикт",
        "cglib/families/adv.py",
        "    return callers_short or facts_dirty",
        "    return False and (callers_short or facts_dirty)",
        ["B SDD-1-ADV-02",
         B1,
         "C1 SDD-1-ADV-01: дефектный мир под положительным ID даёт "
         "CG_AUTHORITATIVE_GATE_BLOCKED",
         "G-ADV-2-близнец снятый advisory НЕ отменяет находку authority",
         "G-ADV-3 недостающий authoritative caller блокирует так же, как "
         "грязный graph fact"],
    ),
    # --- по инъекции на семейство полосы вызывающего/review/landing ---------
    # Каждая снимает ОДНО решение и сохраняет ЧТЕНИЯ фактов: снятое чтение
    # уронило бы прогон собственным отказом «факт не прочитан», и краснота
    # пришла бы от учёта фактов, а не от снятого предиката, — проверяемое
    # свойство осталось бы неизмеренным (п. 2в `testing.md` §«Гейт на класс»).
    (
        "cg.ppre перестал требовать трассировки зарегистрированной задачи",
        "cglib/families/ppre.py",
        "    return not series or bool(incomplete)",
        "    series, incomplete\n    return False",
        ["B SDD-1-PPRE-02",
         B1,
         "C1 SDD-1-PPRE-01: дефектный мир под положительным ID даёт "
         "CG_TRACE_ID_MISSING",
         "G-PPRE-2-близнец при полных координатах дефект графа даёт RED, а не "
         "NOT_EXECUTED"],
    ),
    (
        "cg.post перестал требовать записи от applicable role",
        "cglib/families/post.py",
        "    return bool(unreviewed)",
        "    unreviewed\n    return False",
        ["B SDD-1-POST-02",
         B1,
         "C1 SDD-1-POST-01: дефектный мир под положительным ID даёт "
         "CG_POST_DIFF_REVIEW_MISSING",
         "G-POST-2-близнец отсутствующую запись ловит правило о ней — и "
         "правило ownership на ней молчит"],
    ),
    (
        "cg.land перестал сверять применённое содержимое с одобренным",
        "cglib/families/land.py",
        "    return dict(applied) != canonical",
        "    dict(applied)\n    return False",
        ["B SDD-1-LAND-02",
         B1,
         "C1 SDD-1-LAND-01: дефектный мир под положительным ID даёт "
         "CG_LANDED_CONTENT_DRIFT",
         "G-LAND-2-близнец уехавший blob при том же заявленном отпечатке даёт "
         "RED"],
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
    failed, passed = [], []
    for line in completed.stdout.split("\n"):
        match = FAIL_LINE.match(line)
        if match:
            failed.append(match.group(1).strip())
            continue
        match = OK_LINE.match(line)
        if match:
            passed.append(match.group(1).strip())
    return completed.returncode, failed, passed


def check_ledger_shape():
    """Форма ведомости инъекций: ровно пять полей у каждой записи.

    Заведено ценой прогона. Сведение волны склеило две записи в одну, потеряв
    разделитель между ними, и РАЗБОР ЭТО ПРОПУСТИЛ: кортеж из десяти элементов
    синтаксически безупречен. Ошибка проявилась только распаковкой в цикле —
    то есть после того, как контрольный прогон уже отработал впустую.

    Склейка, случайно давшая пять полей, не проявилась бы и там. Поэтому форма
    проверяется здесь, до первого прогона, а не подразумевается.
    """
    wrong = [
        (index, len(entry))
        for index, entry in enumerate(INJECTIONS)
        if not isinstance(entry, tuple) or len(entry) != 5
    ]
    if wrong:
        sys.stdout.write(
            "  FAIL форма ведомости: записей с числом полей, отличным от пяти "
            "— %d %s\n" % (len(wrong), wrong)
        )
        return False
    sys.stdout.write(
        "  OK   форма ведомости: записей %d, у каждой ровно пять полей\n"
        % len(INJECTIONS)
    )
    return True


def main():
    passed = 0
    broken = 0
    if check_ledger_shape():
        passed += 1
    else:
        broken += 1
        return 1
    with tempfile.TemporaryDirectory(prefix="cg-inject-") as work:
        control_root = prepare(work, "control")
        code, failed, control_passed = run_prove(control_root)
        # Перечень утверждений о собственном отказе ВЫВОДИТСЯ отсюда: на чистом
        # дереве они все зелёные, поэтому именно контрольный прогон и знает их
        # состав. Пустой перечень — находка, а не «нечего разворачивать».
        self_failure_assertions = sorted(
            name for name in control_passed if SELF_FAILURE_MARK in name
        )
        if code == 0 and not failed:
            passed += 1
            sys.stdout.write("  OK   контроль: нетронутое дерево зелено\n")
        else:
            broken += 1
            sys.stdout.write(
                "  FAIL контроль: нетронутое дерево дало код %d и находки %s\n"
                % (code, failed)
            )

        # Отбор по подстроке имени. Полный прогон — 38 инъекций, каждая с
        # собственным прогоном доказательств, то есть больше часа; проверить
        # правку ОДНОЙ инъекции иначе нельзя, и это толкает не проверять её
        # вовсе. Перепись при отборе печатает, сколько инъекций осмотрено из
        # скольких объявленных, — «доказано 1 из 1» не должно читаться как
        # «доказаны все».
        global selected_count
        selected = [
            entry for entry in INJECTIONS
            if not sys.argv[1:] or sys.argv[1] in entry[0]
        ]
        selected_count = selected
        if sys.argv[1:] and not selected:
            sys.stdout.write(
                "  FAIL отбор %r не совпал ни с одной инъекцией из %d\n"
                % (sys.argv[1], len(INJECTIONS))
            )
            return 1
        for index, (name, relpath, needle, replacement, expected) in enumerate(
            selected
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

            code, failed, _ = run_prove(root)
            if EVERY_SELF_FAILURE in expected:
                if not self_failure_assertions:
                    broken += 1
                    sys.stdout.write(
                        "  FAIL %s: перечень утверждений о собственном отказе "
                        "ПУСТ — раскрывать нечего, инъекция беспредметна\n" % name
                    )
                    continue
                expected = [item for item in expected if item != EVERY_SELF_FAILURE]
                expected = expected + self_failure_assertions
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
    if sys.argv[1:]:
        sys.stdout.write(
            "ОТБОР %r: осмотрено инъекций %d из %d объявленных — вердикт "
            "относится к отобранным, не ко всем\n"
            % (sys.argv[1], len(selected_count), len(INJECTIONS))
        )
    if total == 0:
        sys.stdout.write("проба беспредметна: инъекций ноль\n")
        return 2
    return 1 if broken else 0


if __name__ == "__main__":
    raise SystemExit(main())
