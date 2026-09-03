#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Построитель fixtures из приёмки и авторской части casedata.

Мир derived-кейса НЕ пишется отдельно: он ВЫЧИСЛЯЕТСЯ применением одной
объявленной операции к миру twin'а. Поэтому «ровно один факт» не может быть
нарушен по невнимательности — нарушить его можно только объявив операцию,
которой мир не допускает, и тогда построитель падает здесь же.

Построитель дополнительно пересчитывает дельту тем же кодом, которым её
пересчитывает driver, и отказывается писать fixture, если дельта не равна
одному объявленному факту. Это не дублирование проверки driver'а: driver судит
то, что лежит на диске, а построитель — то, что он собирается туда положить.
"""

import argparse
import os
import shutil
import sys

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..")))
sys.path.insert(0, HERE)

import casedata  # noqa: E402
import worldpath  # noqa: E402
from caselib import delta as delta_module  # noqa: E402
from caselib import fixture as fixture_module  # noqa: E402
from caselib import spec as spec_module  # noqa: E402

# Роль, под которой выпущен human-external verdict кейса. Берётся по разделу,
# а не выписывается по кейсам: перечень из 39 строк разошёлся бы с матрицей.
SECTION_ROLE = {
    "External verdict": "acceptance-reviewer",
    "External authority": "acceptance-reviewer",
    "Truth ownership": "human-semantic-reviewer",
    "Hash invalidation, trace и evidence": "acceptance-reviewer",
    "Diff ownership, post-diff review и convergence": "convergence-reviewer",
    "Landing и terminal states": "landing-reviewer",
    "Policy, dual-DAG cutover и legacy census": "landing-reviewer",
}
DEFAULT_ROLE = "acceptance-reviewer"


def resolution_order(registry):
    """Топологический порядок: twin материализуется раньше производного."""
    ordered = []
    seen = set()

    def visit(case_id, chain):
        if case_id in seen:
            return
        if case_id in chain:
            raise SystemExit("цикл twin: %s" % " -> ".join(chain + [case_id]))
        twin = registry[case_id]["twin"]
        if twin:
            visit(twin, chain + [case_id])
        seen.add(case_id)
        ordered.append(case_id)

    for case_id in registry:
        visit(case_id, [])
    return ordered


def build_world(case_id, entry, worlds):
    twin = entry["twin"]
    if twin is None:
        world = casedata.BASE_WORLDS.get(case_id)
        if world is None:
            raise SystemExit("нет базового мира для %s" % case_id)
        return world, None

    declaration = casedata.DERIVED.get(case_id)
    if declaration is None:
        raise SystemExit("нет дельты для %s" % case_id)
    operation, path, value, fact = declaration
    try:
        world = worldpath.apply_operation(worlds[twin], operation, path, value)
    except (KeyError, ValueError) as error:
        raise SystemExit(
            "%s: дельта не применяется к миру twin %s: %s" % (case_id, twin, error)
        )

    differences = delta_module.compute(worlds[twin], world)
    if len(differences) != 1:
        raise SystemExit(
            "%s: получилось %d фактов вместо одного: %s"
            % (case_id, len(differences), delta_module.describe(differences))
        )
    actual = differences[0]
    if actual["op"] != operation or actual["path"] != path:
        raise SystemExit(
            "%s: фактическая дельта %s %s не совпала с объявленной %s %s"
            % (case_id, actual["op"], actual["path"], operation, path)
        )
    return world, {"op": operation, "path": path, "fact": fact}


def write_yaml(path, document, header):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("# %s\n" % header)
        yaml.safe_dump(
            document,
            handle,
            allow_unicode=True,
            sort_keys=False,
            default_flow_style=False,
        )


def holder_kinds(holder_type):
    return [part.strip() for part in holder_type.split("+")]


def build_fixture(case_id, entry, world, declared_delta, root):
    directory = os.path.join(root, case_id)
    if os.path.isdir(directory):
        shutil.rmtree(directory)
    os.makedirs(directory)

    kinds = holder_kinds(entry["holder_type"])
    role = SECTION_ROLE.get(entry["section"], DEFAULT_ROLE)
    subject_digest = "sha256-fixture-subject-%s" % case_id.lower()

    manifest = {
        "schema_version": 1,
        "case_id": case_id,
        "title": entry["title"],
        "section": entry["section"],
        "positive_twin": entry["twin"],
        "holder_type": entry["holder_type"],
        "required_capability": fixture_module.capability_token(case_id),
        "expected_sut": dict(entry["expected_sut"]),
        "driver_assertion": dict(entry["driver_assertion"]),
        "expected_final_holder": dict(entry["expected_final_holder"]),
        "expected_initial_holder": dict(entry["expected_initial_holder"]),
    }
    if declared_delta:
        manifest["delta"] = declared_delta
    if case_id in fixture_module.STUB_PERMITTED_CASES:
        # Только три birth fixtures драйвера пиновывают фактическую тройку: их
        # предмет — компаратор driver'а, а не поведение SUT.
        manifest["sut_stub"] = dict(entry["expected_sut"])

    write_yaml(
        os.path.join(directory, "case.yaml"),
        manifest,
        "манифест кейса %s; сверяется с приёмкой при каждом запуске" % case_id,
    )
    write_yaml(
        os.path.join(directory, "world.yaml"),
        world,
        "моделируемый мир кейса %s; вход SUT через стабильный seam" % case_id,
    )

    holders = {
        "schema_version": 1,
        "case_id": case_id,
        "required_holders": {},
    }
    if "machine" in kinds:
        holders["required_holders"]["case-assertion"] = {
            "kind": "machine",
            "owner": "integration-tester",
            "executable": entry["driver_command"],
            "predicate": "фактическая тройка SUT равна driver assertion по трём полям",
            "evidence_coordinate": "evidence/%s.yaml" % case_id,
        }
    if "human-external" in kinds:
        holders["required_holders"]["external-verdict"] = {
            "kind": "human-external",
            "role": role,
            "event_coordinate": "github-event.json",
            "review_coordinate": "reviews/%s/%s.yaml" % (role, subject_digest),
        }
    write_yaml(
        os.path.join(directory, "holders.yaml"),
        holders,
        "required holder set кейса %s" % case_id,
    )

    write_yaml(
        os.path.join(directory, "evidence", "case-assertion.yaml"),
        {
            "schema_version": 1,
            "case_id": case_id,
            "holder": "case-assertion",
            "owner": "integration-tester",
            "driver_command": entry["driver_command"],
            "driver_assertion": dict(entry["driver_assertion"]),
            "expected_initial_holder": dict(entry["expected_initial_holder"]),
            "expected_final_holder": dict(entry["expected_final_holder"]),
            "captured_category": None,
            "note": (
                "captured_category пуст намеренно: до появления SUT capability "
                "фактический исход не снят, и записывать сюда ожидание значило бы "
                "выдать намерение за наблюдение"
            ),
        },
        "evidence plan holder case-assertion для %s" % case_id,
    )

    if "machine" in kinds:
        write_yaml(
            os.path.join(directory, "evidence", "%s.yaml" % case_id),
            {
                "schema_version": 1,
                "case_id": case_id,
                "subject": "world.yaml",
                "expected_sut": dict(entry["expected_sut"]),
                "captured_outcome": None,
                "note": (
                    "captured_outcome пуст, пока SUT не отвечает: пустое поле "
                    "означает «не снято», а не «снято пустым»"
                ),
            },
            "evidence machine holder для %s" % case_id,
        )

    if "human-external" in kinds:
        write_yaml(
            os.path.join(directory, "reviews", role, "%s.yaml" % subject_digest),
            {
                "schema_version": 1,
                "kind": "modelled_review_record",
                "case_id": case_id,
                "reviewer_role": role,
                "subject_sha256": subject_digest,
                "verdict": "APPROVED",
                "event_coordinate": "github-event.json",
                "note": (
                    "модель review record внутри fixture; production-координат "
                    "не утверждает"
                ),
            },
            "review record кейса %s" % case_id,
        )
        event_path = os.path.join(directory, "github-event.json")
        with open(event_path, "w", encoding="utf-8") as handle:
            import json

            json.dump(
                {
                    "schema_version": 1,
                    "kind": "modelled_github_event",
                    "case_id": case_id,
                    "role": role,
                    "actor": "pointpu",
                    "node_id": "FIXTURE_%s" % case_id.replace("-", "_"),
                    "subject_sha256": subject_digest,
                    "note": (
                        "модель события; настоящий GitHub API здесь не вызывается"
                    ),
                },
                handle,
                ensure_ascii=False,
                indent=1,
            )
            handle.write("\n")


def main():
    parser = argparse.ArgumentParser(description="построение fixtures SDD-1")
    parser.add_argument("--only", help="построить только один case ID")
    args = parser.parse_args()

    registry, _ = spec_module.load_registry()
    root = fixture_module.testdata_root()
    os.makedirs(root, exist_ok=True)

    worlds = {}
    deltas = {}
    for case_id in resolution_order(registry):
        world, declared = build_world(case_id, registry[case_id], worlds)
        worlds[case_id] = world
        deltas[case_id] = declared

    built = 0
    for case_id in sorted(registry):
        if args.only and case_id != args.only:
            continue
        build_fixture(case_id, registry[case_id], worlds[case_id], deltas[case_id], root)
        built += 1

    sys.stdout.write(
        "построено fixtures: %d; базовых миров %d; one-fact дельт %d\n"
        % (
            built,
            sum(1 for c in registry if registry[c]["twin"] is None),
            sum(1 for c in registry if registry[c]["twin"]),
        )
    )


if __name__ == "__main__":
    main()
