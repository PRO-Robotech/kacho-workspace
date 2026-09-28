#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Полосы прогона оснастки контура: ЕДИНСТВЕННОЕ объявление и его исполнение.

ЗАЧЕМ ЭТОТ ФАЙЛ СУЩЕСТВУЕТ. До 2026-09-02 оснастку контура не звало НИЧТО — ни
хук отправки, ни конвейер (ws#504). Хук выводит свой перечень из дерева
(`git ls-files 'scripts/*/run-all.sh'`), поэтому каталог без прогонщика
оставался вне его *by construction*: молча и без строки в переписи. Цена
измерена, а не предположена — за один разбор нашлись две поломки, обе жившие на
стволе: `selftest/inject.py` падал `NameError` на любом полном вызове (ws#503), а
`selftest/prove_run_progress.py` был красен 6 из 8. Неисполняемая проверка
ломается молча, и её молчание неотличимо от «её давно не звали».

ПОЧЕМУ ПОЛОС ДВЕ, А НЕ ОДНА. Прямое включение всего контура в хук отправки
заплатило бы КАЖДОЙ отправкой воркспейса за прогон, которого она не касается.
Граница выбрана замером на `61fddcc` (одна машина, последовательно, свободная
очередь): полоса `hook` стоила порядка минуты, полоса `ci` — порядка четверти
часа, и основную её цену давал `selftest/inject.py`. Поимённые секунды и счёты
утверждений прежде стояли здесь таблицей и устаревали молча с каждой новой
пробой (ws#760); состав полос сегодня печатает
`python3 scripts/change-graph-gate/lanes.py --list`, а цену — сам прогон полосы.

ГРАНИЦА СОВПАЛА С ПРЕДМЕТОМ, И ЭТО НЕ СОВПАДЕНИЕ. Дешёвое отвечает на вопрос
«работает ли контур», дорогое — на вопрос «СПОСОБЕН ли контур упасть». Второе
дороже первого ровно потому, что доказательство падучести есть повторный прогон
испытуемого по разу на каждую инъекцию: полный прогон `prove.py` на каждую
инъекцию и даёт ту самую четверть часа. Полоса `ci` уходит на MR в ствол — туда,
где работа садится, и где её красное видно в перечне проверок PR.

ПОЛОСА `none` — НЕ ДЫРА, А РЕШЕНИЕ С ПРИЧИНОЙ. Точка входа, не являющаяся
пробой, обязана иметь строку с написанной причиной. Иначе перечень «что мы не
гоняем» жил бы в чьей-то голове, а новая точка входа выпадала бы из обеих полос
тем же способом, каким выпал весь контур.

Исходов три и у каждого свой код: 0 — прошло, 1 — находка, 2 — без предмета.
"""

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# Корень воркспейса. Переопределяется `CG_GATE_ROOT` — этим пользуется ТОЛЬКО
# песочница инъекций (`inject.sh`), чтобы доказать обе стороны каждой оси, не
# трогая рабочую копию.
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
from gate_root import gate_root  # noqa: E402  порядок и отказ рабочему каталогу — ws#757
ROOT = gate_root("CG_GATE_ROOT", __file__)

# Каталог оснастки контура относительно корня.
GATE_RELDIR = os.path.join("scripts", "change-graph-gate")

# Каталоги, где живут точки входа проб. Испытуемого (`run.py`) и саму полосовую
# оснастку (этот файл, `run-all.sh`, `prove-all.sh`, `check-*.sh`) признак не
# захватывает by construction: они лежат ВЫШЕ этих двух каталогов.
PROBE_SUBDIRS = ("selftest", "tests")

LANE_HOOK = "hook"
LANE_CI = "ci"
LANE_NONE = "none"

# ── ВЕДОМОСТЬ ПОЛОС ──────────────────────────────────────────────────────────
#
# (полоса, путь относительно каталога оснастки, аргументы после пути, причина).
# Для полос `hook`/`ci` причина — что именно проба утверждает; для `none` —
# почему точка входа пробой не является.
LANES = (
    (LANE_HOOK, "tests/run_matrix.py", ("final",),
     "все объявленные кейсы дают объявленный final holder"),
    (LANE_HOOK, "selftest/prove.py", (),
     "тройка испытуемого на каждом кейсе плюс собственные отказы ядра"),
    (LANE_HOOK, "selftest/prove_census_policy.py", (),
     "правила переписи и политики умеют упасть и молчат на законном близнеце"),
    (LANE_HOOK, "selftest/laneparity.py", (),
     "полосы одного механизма сверены между собой"),
    (LANE_HOOK, "tests/selfcheck/prove.sh", (),
     "birth inversion самого компаратора driver'а"),
    # Полоса `hook`, а не `ci`, и это решение: проба не гоняет испытуемого ни
    # разу — она сверяет ведомость радиуса с деревом фикстур и стоит доли
    # секунды. Её предмет — находка, которая обязана прийти ДО пятнадцати минут
    # инъекций; проба, живущая в дорогой полосе, приходила бы вместе с ними.
    (LANE_HOOK, "selftest/prove_injection_radius.py", (),
     "радиус инъекции семейства объявлен, сходится с деревом и умеет упасть"),
    # Полоса `hook`: проба строит песочницу из нескольких git-репозиториев и
    # стоит пару секунд. Её предмет — ноль непрочитанного дерева, выданный за
    # освобождение роли; такая находка обязана прийти с отправкой, а не через
    # пятнадцать минут дорогой полосы.
    (LANE_HOOK, "selftest/prove_applicability.py", (),
     "производитель свидетельства освобождений отказывает на непрочитанном дереве, "
     "читает коммит и клаузу hashes; сверка ловит чужой пакет в команде"),

    (LANE_CI, "selftest/inject.py", (),
     "prove.py СПОСОБЕН упасть — по каждой инъекции краснеют ровно названные утверждения"),
    (LANE_CI, "selftest/prove_run_progress.py", (),
     "долгий прогон инъекций не молчит: сброс буфера и объявление ДО прогона"),
    (LANE_CI, "tests/selfcheck/prove_matrix_listing.sh", (),
     "перечни матрицы выводит сама программа — сквозной прогон на сломанных кейсах"),
    (LANE_CI, "tests/selfcheck/inject.sh", (),
     "prove.sh СПОСОБЕН упасть — доказательство падучести проб harness'а"),

    (LANE_NONE, "run.py", (),
     "испытуемый контура, а не проба: вердикта 0/1/2 не выносит вовсе"),
    (LANE_NONE, "applicability.py", (),
     "производитель свидетельства освобождений, а не проба: вердикт о дереве выносит "
     "check-04, о собственной падучести — selftest/prove_applicability.py"),
    (LANE_NONE, "tests/run_case.py", (),
     "matrix command: исполняется по кейсу из run_matrix.py и отвечает holder-кодами 0/10/20/40"),
    (LANE_NONE, "tests/selfcheck/fake_sut.py", (),
     "подставной SUT для проб harness'а; достижим только через KACHO_CG_SUT"),
    (LANE_NONE, "tests/tools/build_fixtures.py", (),
     "генератор fixtures: перестраивает дерево кейсов, вердикта не выносит"),
)

RUNNABLE_LANES = (LANE_HOOK, LANE_CI)


def census(text):
    sys.stdout.write("[CENSUS] %s\n" % text)
    sys.stdout.flush()


def void(text):
    sys.stderr.write("[VOID] %s\n" % text)
    sys.stderr.flush()
    return 2


def fail(text):
    sys.stderr.write("[FAIL] %s\n" % text)
    sys.stderr.flush()


def gate_path(rel):
    return os.path.join(ROOT, GATE_RELDIR, rel)


def command_for(rel, extra):
    """Команда прогона. Расширение выбирает интерпретатор, а не бит исполнения:
    бит теряется при копировании и при выкладке архивом, и потерялся бы молча."""
    path = gate_path(rel)
    if rel.endswith(".py"):
        return [sys.executable, path] + list(extra)
    return ["bash", path] + list(extra)


def tracked_entry_points():
    """Точки входа проб контура, ВЫВЕДЕННЫЕ из дерева.

    Признак структурный, а не по имени: имя `laneparity.py` под соглашение
    `prove*`/`inject*` не подходит, и перечень по имени молча потерял бы пробу.
    Точкой входа считается ОТСЛЕЖИВАЕМЫЙ файл в `selftest/` либо `tests/`,
    который: для `.py` несёт `if __name__ ==`, для `.sh` начинается с шебанга.
    Библиотеки (`cglib/`, `tests/caselib/`, `tests/tools/*data*`) ни того, ни
    другого не несут и в перечень не попадают by construction.

    Возвращает (перечень, число прочитанных файлов) либо (None, причина).
    """
    try:
        out = subprocess.run(
            ["git", "-C", ROOT, "ls-files", "--", GATE_RELDIR],
            capture_output=True, text=True, check=False,
        )
    except OSError as exc:
        return None, "git недоступен (%s)" % exc
    if out.returncode != 0:
        return None, "git не отвечает в %s: %s" % (ROOT, out.stderr.strip())

    found = []
    read = 0
    prefix = GATE_RELDIR.replace(os.sep, "/") + "/"
    for line in out.stdout.split("\n"):
        rel = line.strip()
        if not rel.startswith(prefix):
            continue
        inner = rel[len(prefix):]
        head = inner.split("/", 1)[0]
        if head not in PROBE_SUBDIRS:
            continue
        if not (inner.endswith(".py") or inner.endswith(".sh")):
            continue
        try:
            with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
                text = fh.read()
        except OSError:
            continue
        read += 1
        if inner.endswith(".py"):
            if "if __name__ ==" in text:
                found.append(inner)
        elif text.startswith("#!"):
            found.append(inner)
    return sorted(found), read


# ── ПРОГОН ПОЛОСЫ ────────────────────────────────────────────────────────────

def run_lane(lane):
    rows = [r for r in LANES if r[0] == lane]
    if not rows:
        return void("полоса %r пуста — прогонять нечего" % lane)

    missing = [rel for _, rel, _, _ in rows if not os.path.isfile(gate_path(rel))]
    if missing:
        return void("полоса %s: в дереве нет %s — сверять не с чем"
                    % (lane, ", ".join(missing)))

    try:
        import yaml  # noqa: F401
    except ImportError:
        return void("полоса %s: разборщик YAML недоступен, а fixtures контура — YAML"
                    % lane)

    ok = bad = nosub = 0
    findings = []
    sys.stdout.write("=== полоса %s: проб %d ===\n" % (lane, len(rows)))
    sys.stdout.flush()
    for _, rel, extra, title in rows:
        # Объявление печатается ДО прогона и со сбросом буфера: пока прогон
        # молчит, «идёт» и «повис» неотличимы, а снятый своим пределом прогон
        # даёт третью категорию исхода, которую легко прочесть как красное.
        sys.stdout.write("  ИДЁТ %s — %s\n" % (rel, title))
        sys.stdout.flush()
        completed = subprocess.run(command_for(rel, extra), check=False)
        rc = completed.returncode
        if rc == 0:
            ok += 1
            sys.stdout.write("  OK   %s\n" % rel)
        elif rc == 2:
            nosub += 1
            sys.stdout.write("  БЕЗ ПРЕДМЕТА %s\n" % rel)
        else:
            # Код, отличный от 0/1/2, — это тоже находка, а не «не выполнилось»:
            # ровно так выглядела поломка ws#503, где inject.py падал NameError.
            # Код печатается, чтобы обрыв сигналом (137/143) был узнаваем.
            bad += 1
            findings.append("%s — код %d" % (rel, rc))
            sys.stdout.write("  ПРОВАЛЕНО %s (код %d)\n" % (rel, rc))
        sys.stdout.flush()

    census("полоса %s: проб %d, пройдено %d, провалено %d, без предмета %d"
           % (lane, len(rows), ok, bad, nosub))
    for f in findings:
        fail("полоса %s — %s" % (lane, f))
    if bad:
        return 1
    if nosub:
        return 2
    return 0


# ── ВЕДОМОСТЬ ПОКРЫВАЕТ ДЕРЕВО ───────────────────────────────────────────────

def audit_roster():
    entries, read = tracked_entry_points()
    if entries is None:
        return void("перечень точек входа не выведен: %s" % read)
    if not entries:
        return void("точек входа в %s/{%s} не найдено — предикат остался без предмета"
                    % (GATE_RELDIR, ",".join(PROBE_SUBDIRS)))

    declared = [rel for _, rel, _, _ in LANES]
    findings = []

    duplicates = sorted({rel for rel in declared if declared.count(rel) > 1})
    for rel in duplicates:
        findings.append("%s объявлен более чем одной строкой — полосы обязаны не пересекаться" % rel)

    # Испытуемый и всё, что лежит ВЫШЕ каталогов проб, признаком не ловится,
    # поэтому из сверки с деревом он исключается — но его строка в ведомости
    # обязана оставаться: без неё «почему run.py не гоняется» негде прочесть.
    declared_probe_scope = {
        rel for rel in declared if rel.split("/", 1)[0] in PROBE_SUBDIRS
    }
    for rel in sorted(set(entries) - declared_probe_scope):
        findings.append(
            "%s — точка входа в дереве есть, строки в ведомости полос нет: "
            "проба выпала бы из ОБЕИХ полос молча, ровно как выпал весь контур (ws#504)"
            % rel
        )
    for rel in sorted(declared_probe_scope - set(entries)):
        findings.append(
            "%s — строка в ведомости есть, точки входа в дереве нет: "
            "исключению нечего исключать" % rel
        )

    for lane, rel, _, reason in LANES:
        if not reason.strip():
            findings.append("%s — строка полосы %s без причины" % (rel, lane))
        if lane not in (LANE_HOOK, LANE_CI, LANE_NONE):
            findings.append("%s — неизвестная полоса %r" % (rel, lane))
        if not os.path.isfile(gate_path(rel)):
            findings.append("%s — ведомость называет путь, которого в дереве нет" % rel)

    for lane in RUNNABLE_LANES:
        if not any(r[0] == lane for r in LANES):
            findings.append("полоса %s пуста — прогон по ней ничего бы не утверждал" % lane)

    census("ведомость полос: прочитано файлов %d, точек входа %d, строк ведомости %d "
           "(hook %d · ci %d · none %d), находок %d"
           % (read, len(entries), len(declared),
              sum(1 for r in LANES if r[0] == LANE_HOOK),
              sum(1 for r in LANES if r[0] == LANE_CI),
              sum(1 for r in LANES if r[0] == LANE_NONE),
              len(findings)))
    for f in findings:
        fail(f)
    return 1 if findings else 0


# ── КОНВЕЙЕР ОБЪЯВЛЯЕТ ДОРОГУЮ ПОЛОСУ ────────────────────────────────────────

# Что конвейер обязан звать. Перечень из трёх, а не из одного: конвейер обязан
# быть НАДМНОЖЕСТВОМ хука, иначе отправка с `--no-verify` (законный и объявленный
# обход) прошла бы мимо дешёвой полосы, а вслед за ней мимо неё прошло бы и
# слияние — дешёвую полосу не гонял бы никто.
#
# Третье поле — чем ещё артефакт законно вызывается: выводом перечня наборов
# (`scripts/lib/run-suites.sh`, ws#753) — прогон набора всегда, доказательство —
# при `--proofs`. Дорогая полоса в перечень наборов не входит и зовётся поимённо.
RUN_ALL = "scripts/change-graph-gate/run-all.sh"
PROOF = "scripts/change-graph-gate/inject.sh"
CI_MUST_CALL = (
    (RUN_ALL, "дешёвая полоса: конвейер обязан быть надмножеством хука", "run"),
    (PROOF, "доказательство падучести самого набора", "proofs"),
    ("scripts/change-graph-gate/prove-all.sh",
     "дорогая полоса: доказательства падучести контура", None),
)

# Вывод перечня наборов — ОДИН дом вызова прогона и доказательства каждого набора
# (задание `gate-suites`). Набор попадает в вывод, только если он есть в переписи
# `scripts/lib/suites.py`; выпавший из неё набор выводом не исполняется, хотя
# строка вызова цела, — поэтому перепись здесь спрашивается, а не подразумевается.
DERIVED = "scripts/lib/run-suites.sh"
SUITE = os.path.basename(GATE_RELDIR)


def has_auto_trigger(doc):
    """Процесс поднимается СОБЫТИЕМ ДЕРЕВА, а не только руками."""
    on = doc.get("on", doc.get(True))
    if isinstance(on, str):
        on = {on: None}
    elif isinstance(on, list):
        on = {str(ev): None for ev in on}
    if not isinstance(on, dict):
        return False
    return any(str(ev) != "workflow_dispatch" for ev in on)


def fires_on_main(doc):
    """Процесс срабатывает на стволе — иначе его job'ы не производит никто."""
    import fnmatch
    # PyYAML разбирает голое `on:` как булево True (YAML 1.1, «on» = yes).
    on = doc.get("on", doc.get(True))
    if isinstance(on, str):
        on = {on: None}
    elif isinstance(on, list):
        on = {str(ev): None for ev in on}
    if not isinstance(on, dict):
        return False
    for event, spec in on.items():
        if str(event) not in ("push", "pull_request", "pull_request_target"):
            continue
        if not isinstance(spec, dict):
            return True          # без сужения срабатывает на каждой ветке
        branches = spec.get("branches")
        ignore = spec.get("branches-ignore")
        if branches:
            if any(fnmatch.fnmatch("main", str(p)) for p in branches):
                return True
        elif ignore:
            if not any(fnmatch.fnmatch("main", str(p)) for p in ignore):
                return True
        else:
            return True
    return False


def audit_ci_declaration():
    try:
        import yaml
    except ImportError:
        return void("разборщик YAML недоступен — объявление конвейера читать нечем")
    import suites as census_of_suites
    import ci_calls

    wf_dir = os.path.join(ROOT, ".github", "workflows")
    try:
        names = sorted(n for n in os.listdir(wf_dir)
                       if n.endswith(".yml") or n.endswith(".yaml"))
    except OSError:
        names = []
    if not names:
        return void("файлов конвейера в дереве нет — проверять нечего")
    try:
        in_census = SUITE in census_of_suites.suites(ROOT)
    except census_of_suites.CensusUnreadable as exc:
        return void("перепись наборов не снята (%s) — что исполняет вывод перечня, "
                    "не выводится" % exc)

    findings = []
    files_read = 0
    jobs_read = 0
    # АВТОЗАПУСК ХОТЬ ГДЕ-НИБУДЬ В ДЕРЕВЕ. Решением владельца 2026-09-20 конвейер
    # описан, но не поднимается ни одним событием; тогда «задание не срабатывает на
    # стволе» верно про КАЖДОЕ задание, и находка об этом перестаёт отличать
    # исправное дерево от испорченного — она стала бы вечной, а вечную находку
    # снимают вместе с проверкой. Ось остаётся живой ровно пока автозапуск есть.
    auto_anywhere = False
    literal = {rel: [] for rel, _, _ in CI_MUST_CALL}
    derived = []           # (процесс, задание, на стволе, с --proofs)
    uncounted = []         # (скрипт, ci_calls.Call) — вызов есть, вердикт не доходит

    for name in names:
        path = os.path.join(wf_dir, name)
        try:
            with open(path, encoding="utf-8") as fh:
                doc = yaml.safe_load(fh)
        except (OSError, yaml.YAMLError) as exc:
            findings.append("%s — объявление не разбирается как YAML: %s" % (name, exc))
            continue
        if not isinstance(doc, dict):
            continue
        files_read += 1
        on_main = fires_on_main(doc)
        if has_auto_trigger(doc):
            auto_anywhere = True
        jobs = doc.get("jobs") or {}
        if not isinstance(jobs, dict):
            continue
        jobs_read += sum(1 for job in jobs.values() if isinstance(job, dict))
        # Вызов узнаёт ОБЩИЙ распознаватель (`scripts/lib/ci_calls.py`, тот же, что
        # у suites-gate/check-04): путь в положении команды, вердикт доходит до
        # задания, задание и шаг безусловны. Незасчитанный вызов — находка с
        # причиной: `echo "…"`, `|| true`, `continue-on-error`, `if:` прежде
        # проходили подстрокой.
        for rel, _, _ in CI_MUST_CALL:
            for c in ci_calls.calls(doc, name, rel):
                if c.counted:
                    literal[rel].append((name, c.job, on_main))
                else:
                    uncounted.append((rel, c))
        for c in ci_calls.calls(doc, name, DERIVED):
            if c.counted:
                derived.append((name, c.job, on_main, "--proofs" in c.args))
            else:
                uncounted.append((DERIVED, c))

    for rel, c in uncounted:
        findings.append("%s — вызов %s не засчитан: %s" % (c.where, rel, c.why))

    def via_derived(how):
        if how == "run":
            return [(w, j, m) for w, j, m, _ in derived]
        if how == "proofs":
            return [(w, j, m) for w, j, m, p in derived if p]
        return []

    if derived and not in_census:
        findings.append(
            "конвейер зовёт вывод перечня (%s), но набора %s в переписи нет — "
            "%s не в индексе либо игнорируется: вывод его не исполнит, хотя строка "
            "вызова цела" % (", ".join("%s/%s" % (w, j) for w, j, _, _ in derived),
                             SUITE, RUN_ALL))
    if derived and not os.path.isfile(os.path.join(ROOT, DERIVED)):
        findings.append("%s — конвейер называет вывод перечня, которого в дереве нет" % DERIVED)

    homes = {}
    for rel, why, how in CI_MUST_CALL:
        by_name = literal[rel]
        by_list = via_derived(how) if in_census else []
        rows = by_name + by_list
        homes[rel] = (len(by_name), len(by_list))
        if not rows:
            findings.append(
                "ни одно задание конвейера не зовёт %s (%s) — ни поимённо%s; объявлено, но "
                "не исполняется никем — ровно то состояние, из-за которого заведена ws#504"
                % (rel, why, ", ни выводом перечня%s" % (" с --proofs" if how == "proofs" else "")
                   if how else ""))
        elif auto_anywhere and not any(on_main for _, _, on_main in rows):
            findings.append(
                "%s зовут только процессы, не срабатывающие на `main` (%s) — "
                "задание, которое не начинается, не зеленеет и не краснеет"
                % (rel, ", ".join("%s/%s" % (w, j) for w, j, _ in rows))
            )
        if by_name and by_list:
            findings.append(
                "%s зовётся дважды — поимённо (%s) и выводом перечня (%s): второй "
                "выписанный дом одного вызова, и расходятся они молча; дом один — вывод "
                "перечня" % (rel, ", ".join("%s/%s" % (w, j) for w, j, _ in by_name),
                             ", ".join("%s/%s" % (w, j) for w, j, _ in by_list)))
        if not os.path.isfile(os.path.join(ROOT, rel)):
            findings.append("%s — конвейер называет скрипт, которого в дереве нет" % rel)

    census("объявление конвейера: прочитано процессов %d, заданий %d, обязательных "
           "вызовов %d (%s); вывод перечня: %s, набор %s в переписи — %s; вызовов не "
           "засчитано %d; находок %d"
           % (files_read, jobs_read, len(CI_MUST_CALL),
              "; ".join("%s поимённо %d, выводом %d" % (os.path.basename(r), a, b)
                        for r, (a, b) in homes.items()),
              ", ".join("%s/%s%s" % (w, j, " --proofs" if p else "")
                        for w, j, _, p in derived) or "нет",
              SUITE, "да" if in_census else "нет", len(uncounted), len(findings)))
    if jobs_read == 0:
        return void("ни одного задания не разобрано — предикат остался без предмета")
    for f in findings:
        fail(f)
    return 1 if findings else 0


USAGE = """использование:
  lanes.py --run <hook|ci>   прогнать полосу
  lanes.py --audit           ведомость полос покрывает точки входа дерева
  lanes.py --ci-declares     конвейер объявляет дорогую полосу
  lanes.py --list [полоса]   напечатать ведомость
"""


def main(argv):
    if len(argv) < 2:
        sys.stderr.write(USAGE)
        return 1
    mode = argv[1]
    if mode == "--run":
        if len(argv) < 3 or argv[2] not in RUNNABLE_LANES:
            sys.stderr.write(USAGE)
            return 1
        return run_lane(argv[2])
    if mode == "--audit":
        return audit_roster()
    if mode == "--ci-declares":
        return audit_ci_declaration()
    if mode == "--list":
        want = argv[2] if len(argv) > 2 else None
        shown = 0
        for lane, rel, extra, reason in LANES:
            if want and lane != want:
                continue
            shown += 1
            sys.stdout.write("%-5s %-42s %s\n"
                             % (lane, rel + (" " + " ".join(extra) if extra else ""), reason))
        census("строк ведомости показано %d из %d" % (shown, len(LANES)))
        return 0
    sys.stderr.write(USAGE)
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
