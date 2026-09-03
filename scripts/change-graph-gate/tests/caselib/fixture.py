"""Загрузка fixture и её сверка с приёмкой.

Fixture НЕ является вторым источником истины: всё, что уже сказано приёмкой
(twin, holder type, expected SUT, driver assertion), fixture обязана повторить
дословно, и driver это сверяет. Расхождение — harness-исход, а не выбор одной
из сторон.

Смысл такой избыточности в том, что fixture лежит рядом с миром, который она
описывает, и читается вместе с ним; но право решать остаётся за приёмкой.
"""

import json
import os
import re

import yaml

from . import spec

CASE_MANIFEST = "case.yaml"
WORLD_FILE = "world.yaml"
HOLDERS_FILE = "holders.yaml"
EVIDENCE_DIR = "evidence"
CASE_ASSERTION_EVIDENCE = os.path.join(EVIDENCE_DIR, "case-assertion.yaml")
GITHUB_EVENT_FILE = "github-event.json"

TESTDATA_RELPATH = os.path.join(
    "scripts", "change-graph-gate", "tests", "testdata"
)

# Ровно три birth fixtures драйвера вправе пиновать actual тройку напрямую:
# их предмет — сам компаратор driver'а, а не поведение SUT. Любая другая
# fixture с таким полем сделала бы всю матрицу вакуумной, поэтому список
# закрыт и проверяется.
#
# **Список НАВЯЗАН приёмкой, а не выбран harness'ом**, и это надо сказать
# прямо: иначе следующий читатель принимает его за послабление, заведённое
# ради удобства, и заводит задачу «снять стаб». §14 объявляет конструкцию
# дословно: «Три `DRIVER-*` birth fixtures МЕНЯЮТ ровно одно поле actual
# triple и ожидают final holder RED; остальные expected SUT RED/NOT_EXECUTED
# являются ожидаемым поведением fixture, а не красным тестом». То есть у этих
# трёх рядов колонка «Expected actual SUT» — тройка, СКОРМЛЕННАЯ фикстурой, а
# не наблюдение за испытуемым; у остальных 193 — наблюдение.
#
# **Что это не толкование, а единственное чтение, — измерено дважды** (замер
# 2026-09-02, оба предиката несут контроль в обратную сторону):
#
#   1. семейство правил ВЫВОДИТСЯ из идентификатора кейса (`registry.family_of`
#      у испытуемого, `capability_token` здесь), поэтому `SDD-1-DRIVER-0X`
#      судят правила `cg.driver` и только они. Кейсов, ожидающих диагностику,
#      которую их СОБСТВЕННОЕ семейство произвести не может, в приёмке ТРИ из
#      198 — ровно эти (ждут `CG_TRACE_ID_ORPHAN` / `CG_TRACE_ID_MISSING`,
#      предмет `cg.evid` и `cg.trace`); у остальных 195 диагностика
#      производима. Наблюдением такая колонка быть не может ни при каком мире.
#      Знаменатель — число РЯДОВ ПРИЁМКИ, а не фикстур на диске: он был 196,
#      пока двум рядам (`SDD-1-AUTH-09`, `SDD-1-DRIVER-04`) фикстур не хватало,
#      и это расхождение читалось как утверждение о приёмке;
#   2. код возврата выводится из категории (`cglib/outcome.py`), и приёмка
#      держит это соответствие в 987 своих тройках из 991. Четыре исключения —
#      `GREEN · … · exit 10` и `RED · … · exit 0` — стоят только в рядах
#      DRIVER-01 и DRIVER-03 (по два вхождения, §13 и §14).
#
# Предикаты, чтобы перемерить, а не поверить:
#
#     python3 - <<'PY'
#     import sys
#     sys.path.insert(0, "scripts/change-graph-gate")
#     sys.path.insert(0, "scripts/change-graph-gate/tests")
#     from cglib import registry, outcome
#     from caselib import spec
#     reg, order = spec.load_registry()
#     made = {f: {r.diagnostic for r in rs} | {outcome.DIAGNOSTIC_OK}
#             for f, rs in registry.load().items()}
#     print(sorted(c for c in order
#                  if reg[c]["expected_sut"]["diagnostic"]
#                  not in made.get(registry.family_of(c), set())))
#     PY
#
# Список длиннее этих трёх означает, что приёмка ждёт чужой диагностики ещё
# где-то; короче — что стаб пережил свой предмет и подлежит снятию.
#
# **Следствие, которое здесь же и названо, чтобы его не искали:** правила
# `cg.driver` не исполняет ни один кейс матрицы — мир этим трём кейсам
# испытуемому не передаётся вовсе. Предъявляются они парами C1/C2 и
# F-DRIVER-1/F-DRIVER-2 в `selftest/prove.py`. Это не остаток и не долг: у
# матрицы здесь другой предмет — сам компаратор.
STUB_PERMITTED_CASES = frozenset(
    ("SDD-1-DRIVER-01", "SDD-1-DRIVER-02", "SDD-1-DRIVER-03")
)

_ID_PREFIX = re.compile(r"^SDD-1-([A-Z]+)(?:-NA)?-\d+$")


class FixtureError(Exception):
    """Fixture отсутствует, не разбирается либо расходится с приёмкой."""


def testdata_root():
    override = os.environ.get("KACHO_CG_TESTDATA")
    if override:
        return override
    return os.path.join(spec.repo_root(), TESTDATA_RELPATH)


def fixture_dir(case_id):
    return os.path.join(testdata_root(), case_id)


def capability_token(case_id):
    """Токен capability семейства кейса.

    Семейство берётся из самого ID, поэтому токен ВЫВОДИТСЯ, а не ведётся
    отдельным списком, который разошёлся бы с матрицей молча.
    """
    match = _ID_PREFIX.match(case_id)
    if not match:
        raise FixtureError("не разбирается семейство case ID: %s" % case_id)
    return "cg.%s" % match.group(1).lower()


def _read_yaml(path, label):
    if not os.path.exists(path):
        raise FixtureError("нет файла %s: %s" % (label, path))
    try:
        with open(path, encoding="utf-8") as handle:
            return yaml.safe_load(handle)
    except OSError as error:
        raise FixtureError("файл %s не читается: %s" % (label, error))
    except yaml.YAMLError as error:
        raise FixtureError("файл %s не разбирается как YAML: %s" % (label, error))


def planned_holder_paths(entry):
    """Абсолютные пути planned holders из координат матрицы.

    Координаты с плейсхолдерами (`{role}`, `{subject}`) матрица объявляет
    шаблоном; на диске им отвечает каталог, а не файл, поэтому такие
    координаты проверяются существованием каталога.
    """
    root = spec.repo_root()
    data_root = testdata_root()
    resolved = []
    for coordinate in entry["planned_holders"]:
        relative = coordinate
        is_directory = False
        if "{" in relative:
            # Координата с плейсхолдером — шаблон; ей отвечает каталог.
            relative = relative.split("{", 1)[0].rstrip("/")
            is_directory = True
        # Координаты fixture разрешаются от КОРНЯ TESTDATA, а не от корня репо.
        # Иначе harness неперемещаем: перенеси дерево проб в другой каталог — и
        # planned holders «исчезнут», хотя лежат рядом с fixture. Ровно на этом
        # собственная проба harness'а давала ложное красное на КОНТРОЛЬНОМ
        # прогоне, где дефекта не было вовсе.
        if relative.startswith(TESTDATA_RELPATH):
            tail = relative[len(TESTDATA_RELPATH):].lstrip("/")
            absolute = os.path.join(data_root, tail) if tail else data_root
        else:
            absolute = os.path.join(root, relative)
        resolved.append((absolute, is_directory, coordinate))
    return resolved


def load(case_id, entry):
    """Читает fixture кейса и сверяет её с реестром приёмки."""
    directory = fixture_dir(case_id)
    if not os.path.isdir(directory):
        raise FixtureError("каталог fixture отсутствует: %s" % directory)

    manifest = _read_yaml(os.path.join(directory, CASE_MANIFEST), CASE_MANIFEST)
    if not isinstance(manifest, dict):
        raise FixtureError("%s не является отображением" % CASE_MANIFEST)

    if manifest.get("case_id") != case_id:
        raise FixtureError(
            "case_id fixture %r не совпадает с запрошенным %r"
            % (manifest.get("case_id"), case_id)
        )

    declared_twin = manifest.get("positive_twin")
    if declared_twin in ("", "—"):
        declared_twin = None
    if declared_twin != entry["twin"]:
        raise FixtureError(
            "positive_twin fixture %r не совпадает с приёмкой %r"
            % (declared_twin, entry["twin"])
        )

    if manifest.get("holder_type") != entry["holder_type"]:
        raise FixtureError(
            "holder_type fixture %r не совпадает с приёмкой %r"
            % (manifest.get("holder_type"), entry["holder_type"])
        )

    for field in ("expected_sut", "driver_assertion"):
        declared = manifest.get(field)
        if not isinstance(declared, dict):
            raise FixtureError("поле %s отсутствует либо не отображение" % field)
        normalised = {
            "category": declared.get("category"),
            "diagnostic": declared.get("diagnostic"),
            "exit": declared.get("exit"),
        }
        if normalised != entry[field]:
            raise FixtureError(
                "%s fixture %r не совпадает с приёмкой %r"
                % (field, normalised, entry[field])
            )

    required_capability = manifest.get("required_capability")
    expected_capability = capability_token(case_id)
    if required_capability != expected_capability:
        raise FixtureError(
            "required_capability fixture %r не совпадает с выводимым из ID %r"
            % (required_capability, expected_capability)
        )

    stub = manifest.get("sut_stub")
    if stub is not None and case_id not in STUB_PERMITTED_CASES:
        raise FixtureError(
            "fixture объявляет sut_stub, но кейс %s не входит в закрытый список "
            "birth fixtures драйвера %s" % (case_id, sorted(STUB_PERMITTED_CASES))
        )

    declared_delta = manifest.get("delta")
    if entry["twin"] is None:
        if declared_delta is not None:
            raise FixtureError(
                "базовый кейс без twin не может объявлять delta"
            )
    else:
        if not isinstance(declared_delta, dict):
            raise FixtureError("derived-кейс обязан объявлять delta")
        for field in ("op", "path", "fact"):
            if not declared_delta.get(field):
                raise FixtureError("в delta отсутствует поле %s" % field)

    world = _read_yaml(os.path.join(directory, WORLD_FILE), WORLD_FILE)
    if world is None:
        raise FixtureError("%s пуст" % WORLD_FILE)

    return {
        "case_id": case_id,
        "directory": directory,
        "manifest": manifest,
        "world": world,
        "world_path": os.path.join(directory, WORLD_FILE),
        "required_capability": required_capability,
        "delta": declared_delta,
        "stub": stub,
    }


def check_planned_holders(entry):
    """Проверяет, что каждая planned holder coordinate существует на диске.

    §12: planned coordinates не утверждают, что production-файлы существуют —
    но координаты, объявленные ВНУТРИ fixture, обязаны существовать, иначе
    matrix ссылается в пустоту.
    """
    missing = []
    for path, is_directory, coordinate in planned_holder_paths(entry):
        ok = os.path.isdir(path) if is_directory else os.path.exists(path)
        if not ok:
            missing.append(coordinate)
    return missing


def load_world(case_id):
    """Читает только мир кейса — нужно для twin при вычислении дельты."""
    path = os.path.join(fixture_dir(case_id), WORLD_FILE)
    world = _read_yaml(path, "%s/%s" % (case_id, WORLD_FILE))
    if world is None:
        raise FixtureError("%s/%s пуст" % (case_id, WORLD_FILE))
    return world
