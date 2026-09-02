"""Стабильный test seam к SUT и проба его capability.

Здесь живёт РАЗЛИЧЕНИЕ, ради которого приёмка §6 написана отдельным абзацем:
отсутствие capability у испытуемого — честный acceptance RED, открывающий
RED_PROVEN; а command-not-found, посторонний crash и infrastructure failure —
НЕ он и RED_PROVEN не открывают.

Различение построено на том, что ОТСУТСТВИЕ — положительное определение, а
СЛОМАННОСТЬ — отсутствие определения:

    SUT-файла нет вовсе                       -> ABSENT       -> capability RED
    SUT есть, объявил набор, нашего нет в нём -> NOT_CAPABLE   -> capability RED
    SUT есть, объявил набор, наш в нём есть   -> CAPABLE       -> сравнение тройки
    SUT есть, но проба сломалась              -> PROBE_BROKEN  -> harness, БЕЗ verdict

Последняя строка — несущая. «Не знаю» никогда не выдаётся за «нет»: неизвестный
исход не вправе открывать RED_PROVEN, потому что RED_PROVEN разрешает писать
implementation.
"""

import json
import os
import subprocess
import sys

from . import spec

SUT_RELPATH = os.path.join("scripts", "change-graph-gate", "run.py")

STATE_ABSENT = "ABSENT"
STATE_NOT_CAPABLE = "NOT_CAPABLE"
STATE_CAPABLE = "CAPABLE"
STATE_PROBE_BROKEN = "PROBE_BROKEN"

PROBE_TIMEOUT_SECONDS = 30
EVALUATE_TIMEOUT_SECONDS = 60


class ProbeResult:
    __slots__ = ("state", "detail", "sut_path", "capabilities")

    def __init__(self, state, detail, sut_path, capabilities=None):
        self.state = state
        self.detail = detail
        self.sut_path = sut_path
        self.capabilities = capabilities or []


def sut_path():
    """Путь к production SUT.

    Переопределение существует ТОЛЬКО для собственных проб harness'а
    (selfcheck), которые обязаны предъявить присутствующий SUT, не написав ни
    строки implementation. Матрица из 196 кейсов переменную не выставляет
    никогда, и это отдельно проверяется пробой harness'а.
    """
    override = os.environ.get("KACHO_CG_SUT")
    if override:
        return override
    return os.path.join(spec.repo_root(), SUT_RELPATH)


def probe(required_capability):
    """Устанавливает, способен ли SUT ответить на этот кейс."""
    target = sut_path()

    if not os.path.exists(target):
        return ProbeResult(
            STATE_ABSENT,
            "production SUT отсутствует: %s" % target,
            target,
        )

    try:
        completed = subprocess.run(
            [sys.executable, target, "--capabilities"],
            capture_output=True,
            text=True,
            timeout=PROBE_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        return ProbeResult(
            STATE_PROBE_BROKEN,
            "проба capability не уложилась в %d с" % PROBE_TIMEOUT_SECONDS,
            target,
        )
    except OSError as error:
        return ProbeResult(
            STATE_PROBE_BROKEN, "проба capability не запустилась: %s" % error, target
        )

    if completed.returncode != 0:
        return ProbeResult(
            STATE_PROBE_BROKEN,
            "проба capability вернула код %d; stderr: %s"
            % (completed.returncode, completed.stderr.strip()[:400]),
            target,
        )

    try:
        declared = json.loads(completed.stdout)
    except ValueError as error:
        return ProbeResult(
            STATE_PROBE_BROKEN,
            "ответ пробы capability не разбирается как JSON: %s" % error,
            target,
        )

    if not isinstance(declared, list) or not all(
        isinstance(item, str) for item in declared
    ):
        return ProbeResult(
            STATE_PROBE_BROKEN,
            "проба capability вернула не список строк: %r" % (declared,),
            target,
        )

    if required_capability not in declared:
        return ProbeResult(
            STATE_NOT_CAPABLE,
            "SUT объявил %d capability, требуемой %r среди них нет"
            % (len(declared), required_capability),
            target,
            declared,
        )

    return ProbeResult(
        STATE_CAPABLE,
        "SUT объявил требуемую capability %r" % required_capability,
        target,
        declared,
    )


class EvaluationError(Exception):
    """SUT вызван, но его ответ не удалось привести к тройке."""


def evaluate(world_path, case_id):
    """Вызывает SUT на мире кейса и возвращает его тройку.

    Ожидается, что последняя непустая строка stdout имеет форму
    `CATEGORY · DIAGNOSTIC · exit N`, а код возврата совпадает с названным в
    ней. Расхождение между напечатанным кодом и фактическим — не тройка, а
    противоречие: SUT сообщает о себе две разные вещи, и driver отказывается
    выбирать за него.
    """
    target = sut_path()
    try:
        completed = subprocess.run(
            [sys.executable, target, "--case-world", world_path, "--case", case_id],
            capture_output=True,
            text=True,
            timeout=EVALUATE_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        raise EvaluationError("SUT не уложился в %d с" % EVALUATE_TIMEOUT_SECONDS)
    except OSError as error:
        raise EvaluationError("SUT не запустился: %s" % error)

    lines = [line for line in completed.stdout.split("\n") if line.strip()]
    if not lines:
        raise EvaluationError(
            "SUT не напечатал ни одной строки; код %d; stderr: %s"
            % (completed.returncode, completed.stderr.strip()[:400])
        )

    try:
        triple = spec.parse_triple(lines[-1], "ответ SUT")
    except spec.SpecError as error:
        raise EvaluationError(str(error))

    if triple["exit"] != completed.returncode:
        raise EvaluationError(
            "SUT напечатал exit %d, а вернул код %d"
            % (triple["exit"], completed.returncode)
        )

    return triple
