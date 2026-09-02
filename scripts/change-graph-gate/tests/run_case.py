#!/usr/bin/env python3
"""Единственная matrix command pre-RED driver'а SDD-1.

    python3 scripts/change-graph-gate/tests/run_case.py --case <ID>

Драйвер принадлежит integration-tester (приёмка §6) и не содержит
implementation: он загружает fixture и вызывает SUT через стабильный test seam.

ПОРЯДОК ПРОВЕРОК НЕСУЩИЙ, а не стилистический. Проба capability стоит ПОСЛЕ
всей валидации fixture, поэтому сломанная fixture не может выдать себя за
`CASE_CAPABILITY_MISSING` — то есть не может открыть RED_PROVEN. Приёмка §6
требует ровно этого: command-not-found, посторонний crash и infrastructure
failure не подменяют честный acceptance RED.

Исходов у команды четыре, и четвёртый — не verdict:

    exit 0  · GREEN        holder
    exit 10 · RED          holder
    exit 20 · NOT_EXECUTED holder
    exit 40 · HARNESS      поломка самого driver'а, holder verdict НЕ выдан
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from caselib import delta as delta_module
from caselib import fixture as fixture_module
from caselib import seam as seam_module
from caselib import spec as spec_module
from caselib import verdict as verdict_module


class Reporter:
    """Печать хода проверки. Последняя строка — машиночитаемая тройка."""

    def __init__(self, quiet=False):
        self.quiet = quiet
        self.notes = []

    def note(self, text):
        self.notes.append(text)
        if not self.quiet:
            sys.stdout.write("  %s\n" % text)

    def headline(self, text):
        if not self.quiet:
            sys.stdout.write("%s\n" % text)


def finish(reporter, triple, as_json=False, payload=None):
    """Печатает финальную тройку и завершает процесс её кодом."""
    if as_json:
        document = {"verdict": triple.as_dict(), "notes": reporter.notes}
        if payload:
            document.update(payload)
        sys.stdout.write(json.dumps(document, ensure_ascii=False, indent=1) + "\n")
    sys.stdout.write(triple.render() + "\n")
    sys.stdout.flush()
    raise SystemExit(triple.exit_code)


def run(case_id, as_json=False, quiet=False):
    reporter = Reporter(quiet=quiet)
    reporter.headline("case %s" % case_id)

    # 1. Приёмка — единственный источник истины о кейсе.
    try:
        registry, _ = spec_module.load_registry()
    except spec_module.SpecError as error:
        reporter.note("приёмка: %s" % error)
        finish(
            reporter,
            verdict_module.harness(verdict_module.HARNESS_ACCEPTANCE_UNREADABLE),
            as_json,
        )

    entry = registry.get(case_id)
    if entry is None:
        reporter.note(
            "в приёмке нет такого case ID; всего разобрано %d" % len(registry)
        )
        finish(
            reporter,
            verdict_module.harness(verdict_module.HARNESS_CASE_UNKNOWN),
            as_json,
        )

    reporter.note("раздел: %s" % entry["section"])
    reporter.note("subject holder: %s" % entry["holder_type"])
    reporter.note("positive twin: %s" % (entry["twin"] or "— (базовый кейс)"))

    # 2. Fixture обязана дословно повторить то, что уже сказала приёмка.
    try:
        loaded = fixture_module.load(case_id, entry)
    except fixture_module.FixtureError as error:
        text = str(error)
        reporter.note("fixture: %s" % text)
        if "sut_stub" in text:
            diagnostic = verdict_module.HARNESS_STUB_NOT_PERMITTED
        elif "каталог fixture отсутствует" in text or "нет файла" in text:
            diagnostic = verdict_module.HARNESS_FIXTURE_MISSING
        elif "не совпадает с приёмкой" in text or "не совпадает с выводимым" in text:
            diagnostic = verdict_module.HARNESS_FIXTURE_SPEC_MISMATCH
        else:
            diagnostic = verdict_module.HARNESS_FIXTURE_MALFORMED
        finish(reporter, verdict_module.harness(diagnostic), as_json)

    reporter.note("fixture: %s" % os.path.relpath(loaded["directory"], spec_module.repo_root()))

    # 3. Planned holder coordinates обязаны существовать на диске.
    missing = fixture_module.check_planned_holders(entry)
    if missing:
        reporter.note("planned holder отсутствует: %s" % "; ".join(missing))
        finish(
            reporter,
            verdict_module.harness(verdict_module.HARNESS_PLANNED_HOLDER_MISSING),
            as_json,
        )
    reporter.note("planned holders на месте: %d" % len(entry["planned_holders"]))

    # 4. One-fact delta: driver ВЫЧИСЛЯЕТ её, а не верит объявлению.
    if entry["twin"]:
        try:
            twin_world = fixture_module.load_world(entry["twin"])
        except fixture_module.FixtureError as error:
            reporter.note("twin: %s" % error)
            finish(
                reporter,
                verdict_module.harness(verdict_module.HARNESS_TWIN_MISSING),
                as_json,
            )

        differences = delta_module.compute(twin_world, loaded["world"])
        if len(differences) != 1:
            reporter.note(
                "дельта относительно twin содержит %d фактов, а обязана один: %s"
                % (len(differences), delta_module.describe(differences))
            )
            finish(
                reporter,
                verdict_module.harness(verdict_module.HARNESS_TWIN_DELTA_NOT_SINGLE),
                as_json,
            )

        actual_delta = differences[0]
        if not delta_module.matches_declaration(actual_delta, loaded["delta"]):
            reporter.note(
                "фактическая дельта %s %s не совпадает с объявленной %s %s"
                % (
                    actual_delta["op"],
                    actual_delta["path"],
                    loaded["delta"].get("op"),
                    loaded["delta"].get("path"),
                )
            )
            finish(
                reporter,
                verdict_module.harness(verdict_module.HARNESS_TWIN_DELTA_UNDECLARED),
                as_json,
            )

        reporter.note(
            "one-fact delta подтверждена: %s %s — %s"
            % (actual_delta["op"], actual_delta["path"], loaded["delta"]["fact"])
        )

    assertion = verdict_module.Triple(
        entry["driver_assertion"]["category"],
        entry["driver_assertion"]["diagnostic"],
        entry["driver_assertion"]["exit"],
    )
    reporter.note("driver assertion: %s" % assertion.render())

    # 5. Только теперь — проба capability испытуемого.
    probe = seam_module.probe(loaded["required_capability"])
    reporter.note("SUT seam: %s" % probe.sut_path)
    reporter.note("проба capability: %s — %s" % (probe.state, probe.detail))

    if probe.state == seam_module.STATE_PROBE_BROKEN:
        # «Не знаю» не выдаётся за «нет»: неизвестный исход не открывает RED_PROVEN.
        finish(
            reporter,
            verdict_module.harness(verdict_module.HARNESS_SUT_PROBE_FAILED),
            as_json,
        )

    if probe.state in (seam_module.STATE_ABSENT, seam_module.STATE_NOT_CAPABLE):
        finish(
            reporter,
            verdict_module.holder(
                verdict_module.CATEGORY_RED, verdict_module.CASE_CAPABILITY_MISSING
            ),
            as_json,
        )

    # 6. Capability есть — получаем фактическую тройку SUT.
    if loaded["stub"] is not None:
        actual = {
            "category": loaded["stub"].get("category"),
            "diagnostic": loaded["stub"].get("diagnostic"),
            "exit": loaded["stub"].get("exit"),
        }
        reporter.note(
            "birth fixture драйвера: actual тройка взята из fixture, SUT не опрашивается"
        )
    else:
        try:
            actual = seam_module.evaluate(loaded["world_path"], case_id)
        except seam_module.EvaluationError as error:
            reporter.note("ответ SUT: %s" % error)
            finish(
                reporter,
                verdict_module.harness(
                    verdict_module.HARNESS_SUT_OUTPUT_UNPARSEABLE
                ),
                as_json,
            )

    actual_triple = verdict_module.Triple(
        actual["category"], actual["diagnostic"], actual["exit"]
    )
    reporter.note("фактическая тройка SUT: %s" % actual_triple.render())

    # 7. Сравнение по трём полям порознь — иначе неизвестно, ЧТО разошлось.
    if actual_triple.category != assertion.category:
        finish(
            reporter,
            verdict_module.holder(
                verdict_module.CATEGORY_RED,
                verdict_module.CASE_ASSERTION_CATEGORY_MISMATCH,
            ),
            as_json,
        )
    if actual_triple.diagnostic != assertion.diagnostic:
        finish(
            reporter,
            verdict_module.holder(
                verdict_module.CATEGORY_RED,
                verdict_module.CASE_ASSERTION_DIAGNOSTIC_MISMATCH,
            ),
            as_json,
        )
    if actual_triple.exit_code != assertion.exit_code:
        finish(
            reporter,
            verdict_module.holder(
                verdict_module.CATEGORY_RED,
                verdict_module.CASE_ASSERTION_EXIT_MISMATCH,
            ),
            as_json,
        )

    finish(
        reporter,
        verdict_module.holder(
            verdict_module.CATEGORY_GREEN, verdict_module.CASE_ASSERTION_MATCHED
        ),
        as_json,
    )


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="pre-RED driver одного кейса SDD-1"
    )
    parser.add_argument("--case", help="case ID из §13/§14 приёмки")
    parser.add_argument("--list", action="store_true", help="перечислить case IDs")
    parser.add_argument("--json", action="store_true", help="машиночитаемый отчёт")
    parser.add_argument("--quiet", action="store_true", help="только финальная тройка")
    args = parser.parse_args(argv)

    if args.list:
        registry, order = spec_module.load_registry()
        for case_id in order:
            sys.stdout.write("%s\n" % case_id)
        return 0

    if not args.case:
        parser.error("нужен --case <ID> либо --list")

    try:
        run(args.case, as_json=args.json, quiet=args.quiet)
    except SystemExit:
        raise
    except Exception as error:  # непредвиденная поломка самого driver'а
        sys.stdout.write("  внутренняя ошибка driver'а: %r\n" % (error,))
        triple = verdict_module.harness(verdict_module.HARNESS_INTERNAL)
        sys.stdout.write(triple.render() + "\n")
        raise SystemExit(triple.exit_code)


if __name__ == "__main__":
    main()
