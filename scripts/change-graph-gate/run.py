#!/usr/bin/env python3
"""Kachō Change Graph gate — испытуемый pre-RED driver'а SDD-1.

Две команды, и обе задаёт стабильный test seam
(`scripts/change-graph-gate/tests/caselib/seam.py`):

    run.py --capabilities
        печатает на stdout JSON-перечень объявленных признаков и выходит нулём;

    run.py --case-world <путь> --case <ID>
        печатает ПОСЛЕДНЕЙ строкой stdout тройку `КАТЕГОРИЯ · ДИАГНОСТИКА ·
        exit N` и выходит ровно этим кодом.

**Собственный отказ отделён от отказа предмета по построению.** Вердикт о
предмете — единственная строка на stdout с кодом из категории. Собственный
отказ не печатает на stdout НИЧЕГО: разбор уходит на stderr, код возврата 40.
Драйвер, не найдя тройки, отвечает harness-исходом, который не входит в тройку
holder-кодов и потому не читается как вердикт. Так «не знаю» не выдаётся ни за
«да», ни за «нет».

**Вердикт производится предикатом над фактами мира, а не идентификатором
кейса.** ID выбирает семейство правил — и только его; ответ дают правила,
читающие мир. Иначе испытуемый был бы таблицей соответствий, зелёной по
построению.

**Перепись объёма печатается всегда**, в том числе на чистом мире: без неё
«нарушений ноль» неотличимо от «не прочитано ничего».
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from cglib import outcome as outcome_module  # noqa: E402
from cglib import registry as registry_module  # noqa: E402
from cglib import rules as rules_module  # noqa: E402
from cglib import world as world_module  # noqa: E402

CENSUS_PREFIX = "[CG]"


def _census(text):
    """Перепись и разбор идут на stderr: stdout несёт только вердикт."""
    sys.stderr.write("%s %s\n" % (CENSUS_PREFIX, text))


def _fail(diagnostic, detail):
    """Собственный отказ: ни одной строки на stdout, код 40."""
    sys.stderr.write(
        "%s собственный отказ испытуемого: %s\n%s %s\n"
        % (CENSUS_PREFIX, diagnostic, CENSUS_PREFIX, detail)
    )
    sys.stderr.write(
        "%s вердикт о предмете НЕ вынесен — этот исход не открывает RED_PROVEN\n"
        % CENSUS_PREFIX
    )
    sys.stderr.flush()
    return outcome_module.SELF_FAILURE_EXIT


def report_capabilities():
    """Объявление признаков. На stdout — только JSON, его читает проба seam."""
    tokens = registry_module.capabilities()
    sys.stdout.write(json.dumps(tokens) + "\n")
    sys.stdout.flush()
    _census("объявлено признаков: %d (%s)" % (len(tokens), ", ".join(tokens)))
    return 0


def judge(world_path, case_id):
    family = registry_module.family_of(case_id)
    declared = registry_module.load()
    if family not in declared:
        raise outcome_module.SelfFailure(
            outcome_module.SELF_FAMILY_UNDECLARED,
            "семейство %s не объявлено; объявлены: %s"
            % (registry_module.capability_token(family),
               ", ".join(registry_module.capabilities())),
        )

    # Кейс и мир называются ДО вычисления: разбор собственного отказа обязан
    # нести координаты, иначе находка посылает читателя искать не там.
    _census("кейс %s · семейство %s · мир %s"
            % (case_id, registry_module.capability_token(family), world_path))

    subject_world = world_module.load(world_path)
    verdict, census = rules_module.evaluate(
        family, declared[family], subject_world
    )

    for line in census.lines():
        _census(line)
    if len(census.violations) > 1:
        _census(
            "вердикт взят по первому нарушению в объявленном порядке: %s"
            % census.violations[0].rule_id
        )

    sys.stdout.write(verdict.render() + "\n")
    sys.stdout.flush()
    return verdict.exit_code


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Kachō Change Graph gate", add_help=True
    )
    parser.add_argument(
        "--capabilities", action="store_true",
        help="напечатать JSON-перечень объявленных признаков",
    )
    parser.add_argument("--case-world", help="путь к world.yaml кейса")
    parser.add_argument("--case", help="идентификатор кейса из §13/§14 приёмки")
    args = parser.parse_args(argv)

    try:
        if args.capabilities:
            return report_capabilities()
        if not args.case_world or not args.case:
            return _fail(
                outcome_module.SELF_USAGE,
                "нужен либо --capabilities, либо пара --case-world <путь> "
                "--case <ID>",
            )
        return judge(args.case_world, args.case)
    except outcome_module.SelfFailure as failure:
        return _fail(failure.diagnostic, failure.detail)
    except Exception as error:  # непредвиденная поломка самого испытуемого
        return _fail(
            outcome_module.SELF_INTERNAL,
            "непредвиденная поломка: %r" % (error,),
        )


if __name__ == "__main__":
    raise SystemExit(main())
