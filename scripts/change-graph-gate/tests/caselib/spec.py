"""Реестр кейсов, ВЫВЕДЕННЫЙ из приёмки, а не выписанный рядом с ней.

Приёмка §2 объявляет acceptance.md единственным предметом истины для
observable behavior и case IDs. Поэтому driver парсит §13 и §14 приёмки на
каждом запуске и НЕ держит собственную копию матрицы: копия — второе место об
одном предмете, и разойтись она может молча.

Цена решения названа честно: разбор 222 КБ markdown на каждый вызов кейса.
Замерено — десятки миллисекунд; за устранение целого класса расхождений это
дёшево.

Приёмку драйвер только ЧИТАЕТ. Verdict приёмки привязан к её точному отпечатку,
поэтому harness не вправе её править.
"""

import os
import re

ACCEPTANCE_RELPATH = os.path.join(
    "docs", "specs", "sub-phase-SDD-1-kacho-change-graph-acceptance.md"
)

SEPARATOR = "·"

_HEADING_CASE = re.compile(r"^#### (SDD-1-[A-Z0-9-]+) — (.*)$")
_TRIPLE = re.compile(
    r"^(GREEN|RED|NOT_EXECUTED)\s*%s\s*([A-Z0-9_]+)\s*%s\s*exit\s*(\d+)$"
    % (SEPARATOR, SEPARATOR)
)
_EMPTY_MARKERS = ("—", "-", "")

_FIELD_LABELS = {
    "Positive twin": "twin",
    "Holder type": "holder_type",
    "Expected SUT": "expected_sut",
    "Driver assertion": "driver_assertion",
    "Expected final holder": "expected_final_holder",
}


class SpecError(Exception):
    """Приёмка не читается либо её форма не разбирается."""


def repo_root():
    # caselib/ лежит на scripts/change-graph-gate/tests/caselib — до корня четыре уровня.
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(here, "..", "..", "..", ".."))


def acceptance_path():
    override = os.environ.get("KACHO_CG_ACCEPTANCE")
    if override:
        return override
    return os.path.join(repo_root(), ACCEPTANCE_RELPATH)


def parse_triple(text, where):
    match = _TRIPLE.match(text.strip())
    if not match:
        raise SpecError("неразбираемая тройка в %s: %r" % (where, text))
    return {
        "category": match.group(1),
        "diagnostic": match.group(2),
        "exit": int(match.group(3)),
    }


def _blank(value):
    return value.strip() in _EMPTY_MARKERS


def _section_bounds(lines, start_heading, end_heading):
    start = end = None
    for index, line in enumerate(lines):
        if line.startswith(start_heading):
            start = index
        elif line.startswith(end_heading):
            end = index
            break
    if start is None or end is None:
        raise SpecError("не найдены границы %r..%r" % (start_heading, end_heading))
    return start, end


def _parse_cases(lines):
    """Разбирает §13: атомарные Given-When-Then кейсы."""
    start, end = _section_bounds(lines, "## 13.", "## 14.")
    cases = {}
    order = []
    section = None
    current = None

    def flush(entry):
        if entry is not None:
            cases[entry["id"]] = entry
            order.append(entry["id"])

    for line in lines[start:end]:
        if line.startswith("### "):
            section = line[4:].strip()
            continue
        heading = _HEADING_CASE.match(line)
        if heading:
            flush(current)
            current = {
                "id": heading.group(1),
                "title": heading.group(2).strip(),
                "section": section,
                "twin": None,
                "holder_type": None,
                "expected_sut": None,
                "driver_assertion": None,
                "expected_final_holder": None,
                "given": None,
                "when": None,
                "then": None,
            }
            continue
        if current is None:
            continue
        stripped = line.strip()
        for label, key in _FIELD_LABELS.items():
            match = re.match(r"^\*\*%s:?\*\*\s*(.*?)\s*$" % re.escape(label), stripped)
            if match:
                value = match.group(1)
                current[key] = None if _blank(value) else value.strip()
        for keyword in ("Given", "When", "Then"):
            match = re.match(r"^\*\*%s\*\*\s*(.*?)\s*$" % keyword, stripped)
            if match:
                current[keyword.lower()] = match.group(1).strip()
    flush(current)
    if not order:
        raise SpecError("в §13 не разобрано ни одного кейса")
    return cases, order


def _parse_matrix(lines):
    """Разбирает §14: holder matrix, по одному row на case ID."""
    start, end = _section_bounds(lines, "## 14.", "## 15.")
    header = None
    rows = {}
    for line in lines[start:end]:
        if not line.startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if set("".join(cells)) <= set("-: "):
            continue
        if header is None:
            header = cells
            continue
        row = dict(zip(header, cells))
        case_id = row.get("Case ID")
        if not case_id:
            raise SpecError("row матрицы без Case ID")
        if case_id in rows:
            raise SpecError("в матрице более одного row для %s" % case_id)
        rows[case_id] = row
    if not rows:
        raise SpecError("в §14 не разобрано ни одного row")
    return rows


def load_registry(path=None):
    """Возвращает реестр кейсов, сверенный между §13 и §14.

    Расхождение §13 и §14 — находка о приёмке, а не повод выбрать одну из
    сторон: driver отказывается работать, пока они не согласованы.
    """
    target = path or acceptance_path()
    try:
        with open(target, encoding="utf-8") as handle:
            lines = handle.read().split("\n")
    except OSError as error:
        raise SpecError("приёмка не читается: %s" % error)

    cases, order = _parse_cases(lines)
    rows = _parse_matrix(lines)

    missing_in_matrix = sorted(set(cases) - set(rows))
    missing_in_cases = sorted(set(rows) - set(cases))
    if missing_in_matrix or missing_in_cases:
        raise SpecError(
            "§13 и §14 не совпадают по составу: нет в матрице %s; нет в §13 %s"
            % (missing_in_matrix, missing_in_cases)
        )

    registry = {}
    for case_id in order:
        case = cases[case_id]
        row = rows[case_id]

        matrix_twin = None if _blank(row["Positive twin"]) else row["Positive twin"]
        if case["twin"] != matrix_twin:
            raise SpecError(
                "%s: twin расходится §13=%r §14=%r"
                % (case_id, case["twin"], matrix_twin)
            )
        if case["holder_type"] != row["Subject holder"]:
            raise SpecError(
                "%s: holder type расходится §13=%r §14=%r"
                % (case_id, case["holder_type"], row["Subject holder"])
            )

        sut_column = "Expected actual SUT category %s diagnostic %s exit" % (
            SEPARATOR, SEPARATOR,
        )
        expected_sut = parse_triple(row[sut_column], "%s §14 expected SUT" % case_id)
        if case["expected_sut"] is not None:
            from_cases = parse_triple(case["expected_sut"], "%s §13 Expected SUT" % case_id)
            if from_cases != expected_sut:
                raise SpecError(
                    "%s: Expected SUT расходится §13=%r §14=%r"
                    % (case_id, from_cases, expected_sut)
                )

        assertion = parse_triple(row["Driver assertion"], "%s §14 assertion" % case_id)
        if case["driver_assertion"] is not None:
            from_cases = parse_triple(
                case["driver_assertion"], "%s §13 Driver assertion" % case_id
            )
            if from_cases != assertion:
                raise SpecError(
                    "%s: Driver assertion расходится §13=%r §14=%r"
                    % (case_id, from_cases, assertion)
                )

        final_holder = parse_triple(
            row["Expected final holder"], "%s §14 final holder" % case_id
        )
        if case["expected_final_holder"] is not None:
            from_cases = parse_triple(
                case["expected_final_holder"], "%s §13 final holder" % case_id
            )
            if from_cases != final_holder:
                raise SpecError(
                    "%s: Expected final holder расходится §13=%r §14=%r"
                    % (case_id, from_cases, final_holder)
                )

        registry[case_id] = {
            "id": case_id,
            "title": case["title"],
            "section": case["section"],
            "twin": case["twin"],
            "holder_type": case["holder_type"],
            "expected_sut": expected_sut,
            "driver_assertion": assertion,
            "expected_final_holder": final_holder,
            "expected_initial_holder": parse_triple(
                row["Expected initial holder"], "%s §14 initial holder" % case_id
            ),
            "fixture_coordinate": row["Fixture coordinate"],
            "planned_holders": [
                part.strip() for part in row["Planned holder coordinate"].split(";")
            ],
            "driver_command": row["Driver command"],
            "given": case["given"],
            "when": case["when"],
            "then": case["then"],
        }

    dangling = sorted(
        entry["twin"]
        for entry in registry.values()
        if entry["twin"] and entry["twin"] not in registry
    )
    if dangling:
        raise SpecError("twin ссылается на несуществующий case: %s" % dangling)

    return registry, order
