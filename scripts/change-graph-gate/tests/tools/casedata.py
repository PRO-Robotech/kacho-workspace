# -*- coding: utf-8 -*-
"""Авторская часть fixtures: 48 базовых миров и 148 one-fact дельт.

Мир — МОДЕЛЬ состояния Change Graph, а не копия дерева. Значения намеренно
опознаваемы как fixture (`sha256:fixture-...`, `SDD-1-...`): правдоподобное
значение прячет дефект, который само же и кормит.

Дельта записывается декларативно (операция, путь, значение, названный факт).
Построитель применяет её к миру twin'а, а driver ПЕРЕСЧИТЫВАЕТ её независимо и
сверяет с объявлением — поэтому «ровно один факт» здесь проверяемое свойство, а
не обещание автора.

Правила, из которых миры собраны, и цена их нарушения:
  * коллекция, из которой кейс удаляет член, — словарь скаляров, а не список:
    удаление из середины списка перенумеровывает хвост и читается как два факта;
  * удаление из списка допускается только с конца;
  * добавляемый член — скаляр: добавление вложенного объекта дало бы два листа.
"""

WORKSPACE_REPO = "PRO-Robotech/kacho-workspace"
PRODUCT_REPO = "PRO-Robotech/kacho"

SHA_WORKSPACE_CUTOVER = "0123456789abcdef0123456789abcdef01234567"
SHA_PRODUCT_CUTOVER = "89abcdef0123456789abcdef0123456789abcdef"
SHA_BASE = "1111111111111111111111111111111111111111"
SHA_HEAD = "2222222222222222222222222222222222222222"
SHA_OTHER = "3333333333333333333333333333333333333333"
SHA_ABSENT = "4444444444444444444444444444444444444444"

TRIPLE_EVID_02 = "RED · CG_TRACE_ID_ORPHAN · exit 10"

# --------------------------------------------------------------------------
# Базовые миры. Ключ — case ID кейса без twin.
# --------------------------------------------------------------------------
BASE_WORLDS = {
    "SDD-1-BOOT-01": {
        "bootstrap": {
            "change_id": "SDD-1",
            "issue": "%s#480" % WORKSPACE_REPO,
            "epoch": "pre-cutover",
            "recorded_exception": True,
        },
        "subject": {"static_form": "DRAFT"},
        "self_package_present": False,
    },
    "SDD-1-REVIEW-01": {
        "bootstrap": {"issue": "%s#480" % WORKSPACE_REPO, "epoch": "pre-cutover"},
        "subject": {
            "static_form": "DRAFT",
            "sha256": "sha256:fixture-subject-v4",
        },
        "event": {
            "issue": "%s#480" % WORKSPACE_REPO,
            "actor": "pointpu",
            "node_id": "IC_fixtureBootstrapNodeV4",
            "role": "acceptance-reviewer",
            "verdict": "APPROVED",
            "body_sha256": "sha256:fixture-body-v4",
            "subject_sha256": "sha256:fixture-subject-v4",
            "lookup": "available",
        },
        "permission": {"actor": "pointpu", "level": "ADMIN", "lookup": "available"},
        "artifact": {
            "authorized_actor": "pointpu",
            "reviewer_role": "acceptance-reviewer",
            "subject_sha256": "sha256:fixture-subject-v4",
            "verdict": "APPROVED",
        },
    },
    "SDD-1-REVIEW-03": {
        "history_mode": "append-only",
        "review_history": {
            "sha-3f1d9196": "sha256:fixture-record-changes-requested-1",
            "sha-aaeffb0a": "sha256:fixture-record-changes-requested-2",
            "sha-d1a0ee80": "sha256:fixture-record-changes-requested-3",
            "sha-47f5f98f": "sha256:fixture-record-approved-4",
        },
        "recorded_content": {
            "sha-3f1d9196": "sha256:fixture-record-changes-requested-1",
            "sha-aaeffb0a": "sha256:fixture-record-changes-requested-2",
            "sha-d1a0ee80": "sha256:fixture-record-changes-requested-3",
            "sha-47f5f98f": "sha256:fixture-record-approved-4",
        },
    },
    "SDD-1-AUTH-01": {
        "epoch": "post-cutover",
        "required_role": "acceptance-reviewer",
        "policy_allowlist": {
            "acceptance-reviewer": "pointpu",
            "convergence-reviewer": "pointpu",
        },
        "artifact": {
            "role": "acceptance-reviewer",
            "event_coordinate": "PRRC_fixtureAuthorityNodeV1",
            "body_sha256": "sha256:fixture-body-v1",
            "subject_sha256": "sha256:fixture-design-v1",
        },
        "event": {
            "node_id": "PRRC_fixtureAuthorityNodeV1",
            "url": "https://github.com/%s/pull/1#pullrequestreview-fixture" % WORKSPACE_REPO,
            "actor": "pointpu",
            "role": "acceptance-reviewer",
            "verdict": "APPROVED",
            "body_sha256": "sha256:fixture-body-v1",
            "subject_sha256": "sha256:fixture-design-v1",
            "timestamp": "2026-09-02T00:00:00Z",
        },
        "api": {"availability": "available"},
    },
    "SDD-1-TRUTH-01": {
        "owners": {
            "issue": "why/priority/owner/live-status",
            "acceptance": "observable-behavior-and-case-ids",
            "design": "technical-decisions",
            "tasks": "approved-execution-route",
            "change_yaml": "coordinates-and-hashes",
            "roadmap": "normative-lifecycle-consumer",
        },
        "roadmap_copies_observable_scope": False,
        "tasks_contains_live_status": False,
        "change_yaml_contains_requirement_prose": False,
        "duplicated_observable_requirement": "none",
        "second_owner_conflict": "none",
        "required_holders": {
            "human-semantic": "verified-external-event",
            "process-gate": "GREEN",
        },
    },
    "SDD-1-LIFE-01": {
        "stage": "DESIGN_APPROVED",
        "requested_transition": "TASKS_READY",
        "required_artifacts": {
            "acceptance": "present",
            "design": "present",
            "class-exposure-initial": "present",
            "class-exposure-revalidation": "present",
            "change-yaml": "present",
            "holders-yaml": "present",
        },
        "verdicts": {"acceptance": "APPROVED", "design": "APPROVED"},
    },
    "SDD-1-NONEMPTY-01": {
        "package_state": "active",
        "acceptance_ids": {"SDD-1-NONEMPTY-01": "declared"},
        "required_holders": {"process-gate": "GREEN"},
        "holder_subjects": {"process-gate": "sha256:fixture-subject-v1"},
    },
    "SDD-1-CLASS-01": {
        "acceptance_content_digest": "sha256:fixture-acceptance-v1",
        "records": {
            "class-exposure-initial": "reviews/class-exposure/initial/fixture-acceptance-v1.yaml"
        },
        "initial_bound_acceptance_hash": "sha256:fixture-acceptance-v1",
        "initial_role": "class-exposure-analyst",
        "initial_item_ids": "exposure-1,exposure-2",
    },
    "SDD-1-CLASS-04": {
        "design_content_digest": "sha256:fixture-design-v1",
        "records": {
            "class-exposure-revalidation": "reviews/class-exposure/revalidation/fixture-design-v1.yaml"
        },
        "revalidation_bound_design_hash": "sha256:fixture-design-v1",
        "revalidation_role": "class-exposure-analyst",
        "exposure_items": {
            "exposure-1": "design-decision-1",
            "exposure-2": "design-decision-2",
        },
        "external_calls": {"geo-zone-get": "mapped"},
        "async_paths": {"outbox-drainer": "mapped"},
        "sentinels": {"err-no-rows": "mapped"},
    },
    "SDD-1-DESIGN-01": {
        "design": {
            "content_digest": "sha256:fixture-design-v1",
            "open_decision_markers": "none",
        },
        "applicable_precode_reviews": {
            "proto-api-reviewer": "verified",
            "db-architect-reviewer": "verified",
        },
    },
    "SDD-1-NA-01": {
        "applicability": {
            "role": "db-architect-reviewer",
            "predicate_id": "no-migrations-in-change",
        },
        "policy_predicates": {
            "no-migrations-in-change": "registered",
            "no-proto-in-change": "registered",
        },
        "evidence": {"migrations_touched": 0},
    },
    "SDD-1-TASKS-01": {
        "design_stage": "DESIGN_APPROVED",
        "handoff": {"event": "writing-plans-handoff-verified", "produces": "tasks.md"},
        "tasks_present": True,
    },
    "SDD-1-TDD-01": {
        "stage": "pre-RED",
        "test_diff_owner": "integration-tester",
        "harness_contains_implementation": False,
        "diff_paths": {
            "scripts/change-graph-gate/tests/run_case.py": "test",
            "scripts/change-graph-gate/tests/testdata/SDD-1-TDD-01/case.yaml": "fixture",
        },
        "evidence_plan_present": True,
    },
    "SDD-1-TDD-02": {
        "driver": {
            "assertion_valid": True,
            "seam": "stable",
            "synthesizes_expected_triple": False,
        },
        "initial_holder": {
            "category": "RED",
            "diagnostic": "CASE_CAPABILITY_MISSING",
            "exit": 10,
        },
        "captured_outcome": "holder-red-capability-missing",
    },
    "SDD-1-TDD-06": {
        "acceptance_ids": {"SDD-1-TDD-06": "declared"},
        "stage": "RED_PROVEN",
        "red_proof_valid": True,
    },
    "SDD-1-HOLDER-01": {
        "holder": {
            "id": "process-gate",
            "owner": "integration-tester",
            "executable": "python3 scripts/change-graph-gate/run.py",
            "predicate": "acceptance-id-set-equals-evidence-plan-id-set",
            "subject_sha256": "sha256:fixture-subject-v1",
            "input_sha256": "sha256:fixture-input-v1",
            "output_sha256": "sha256:fixture-output-v1",
            "stdout_digest": "sha256:fixture-stdout-v1",
            "stderr_digest": "sha256:fixture-stderr-v1",
            "captured_category": "GREEN",
            "evidence_coordinate": "evidence/process-gate/fixture-subject-v1.yaml",
        },
        "observed_content": {
            "subject_sha256": "sha256:fixture-subject-v1",
            "input_sha256": "sha256:fixture-input-v1",
            "output_sha256": "sha256:fixture-output-v1",
            "stdout_digest": "sha256:fixture-stdout-v1",
            "stderr_digest": "sha256:fixture-stderr-v1",
        },
        "registered_commands": {
            "python3 scripts/change-graph-gate/run.py": "registered"
        },
    },
    "SDD-1-BIRTH-01": {
        "holder_version": "process-gate@fixture-v1",
        "birth_runs": {
            "known-good-input": "GREEN",
            "one-fact-injected-defect": "RED",
        },
        "census_entry_count": 2,
        "birth_verdict": "GREEN",
    },
    "SDD-1-HASH-01": {
        "manifest_hashes": {
            "acceptance": "sha256:fixture-acceptance-v1",
            "design": "sha256:fixture-design-v1",
        },
        "content_hashes": {
            "acceptance": "sha256:fixture-acceptance-v1",
            "design": "sha256:fixture-design-v1",
        },
        "approval_bound_subject": {
            "acceptance-reviewer": "sha256:fixture-acceptance-v1",
            "design-reviewer": "sha256:fixture-design-v1",
        },
    },
    "SDD-1-TRACE-01": {
        "acceptance_ids": ["SDD-1-TRACE-01", "SDD-1-TRACE-05"],
        "design_ids": ["SDD-1-TRACE-01", "SDD-1-TRACE-05"],
        "tasks_ids": ["SDD-1-TRACE-01", "SDD-1-TRACE-05"],
        "evidence_plan_ids": ["SDD-1-TRACE-01", "SDD-1-TRACE-05"],
        # Носитель фактической тройки для трёх birth fixtures драйвера.
        # Он живёт здесь, а не в манифесте, потому что цепочка
        # TRACE-01 -> EVID-02 -> DRIVER-0X обязана выводиться по одному факту
        # на шаг, а мир — единственное, что driver сравнивает.
        "driver_birth": {"actual_triple": TRIPLE_EVID_02},
    },
    "SDD-1-TRACE-05": {
        "acceptance_ids": ["SDD-1-TRACE-05"],
        "holders_for_id": {
            "process-gate": "evidence/process-gate/fixture-subject-v1.yaml",
            "adapter-contract": "evidence/adapter-contract/fixture-subject-v2.yaml",
        },
    },
    "SDD-1-EVID-01": {
        "required_holders": {"process-gate": "GREEN", "adapter-contract": "GREEN"},
        "captured_outputs": {
            "process-gate": "evidence/process-gate/fixture-out-1.yaml",
            "adapter-contract": "evidence/adapter-contract/fixture-out-2.yaml",
        },
        "provenance": {"process-gate": "valid", "adapter-contract": "valid"},
    },
    "SDD-1-DIFF-01": {
        "actual_changed_paths": {
            "scripts/change-graph-gate/run.py": "sha256:fixture-blob-1",
            "docs/changes/SDD-1/change.yaml": "sha256:fixture-blob-2",
        },
        "approved_diff_paths": {
            "scripts/change-graph-gate/run.py": "sha256:fixture-blob-1",
            "docs/changes/SDD-1/change.yaml": "sha256:fixture-blob-2",
        },
        "reviewed_diff_blobs": {
            "scripts/change-graph-gate/run.py": "sha256:fixture-blob-1",
            "docs/changes/SDD-1/change.yaml": "sha256:fixture-blob-2",
        },
        "second_active_change_claims": {},
    },
    "SDD-1-POST-01": {
        "content_digest": "sha256:fixture-content-v1",
        "applicable_roles": {
            "go-style-reviewer": "applicable",
            "db-architect-reviewer": "applicable",
        },
        "post_diff_records": {
            "go-style-reviewer": "reviews/post-diff/go-style-reviewer/fixture-content-v1.yaml",
            "db-architect-reviewer": "reviews/post-diff/db-architect-reviewer/fixture-content-v1.yaml",
        },
        "convergence_aggregator_specialists": "none",
    },
    "SDD-1-POST-04": {
        "content_digest": "sha256:fixture-content-v2",
        "distributed_surface": True,
        "post_diff_records": {
            "system-design-reviewer": "reviews/post-diff/system-design-reviewer/fixture-content-v2.yaml"
        },
    },
    "SDD-1-POST-NA-01": {
        "role": "db-architect-reviewer",
        "declared_predicate_id": "no-migrations-in-change",
        "policy_predicates": {"no-migrations-in-change": "registered"},
        "evidence": {"migrations_touched": 0},
    },
    "SDD-1-CONV-01": {
        "convergence": {
            "reviewer_role": "convergence-reviewer",
            "actor": "pointpu",
            "event_coordinate": "PRRC_fixtureConvergenceNodeV1",
            "content_digest": "sha256:fixture-content-v1",
        },
        "change_hashes": {
            "acceptance": "sha256:fixture-acceptance-v1",
            "design": "sha256:fixture-design-v1",
        },
        "repos": {
            "workspace_base_sha": SHA_BASE,
            "workspace_source_sha": SHA_HEAD,
            "product_base_sha": SHA_OTHER,
            "product_source_sha": SHA_PRODUCT_CUTOVER,
        },
        "policy_allowlist": {"convergence-reviewer": "pointpu"},
        "api": {"availability": "available"},
    },
    "SDD-1-LAND-01": {
        "convergence_content_digest": "sha256:fixture-content-v1",
        "landed": {
            "commit_sha": SHA_BASE,
            "canonical_content_digest": "sha256:fixture-content-v1",
        },
        "landed_blobs": {
            "scripts/change-graph-gate/run.py": "sha256:fixture-blob-1",
            "docs/changes/SDD-1/change.yaml": "sha256:fixture-blob-2",
        },
    },
    "SDD-1-WITHDRAW-01": {
        "event": {
            "actor": "pointpu",
            "reason": "владелец снял предмет до реализации",
            "subject_digest": "sha256:fixture-change-v1",
        },
        "source_state": "DESIGN_APPROVED",
        "policy_allowlist": {"owner": "pointpu"},
    },
    "SDD-1-SUPER-01": {
        "event": {"actor": "pointpu", "verdict": "SUPERSEDED"},
        "old_change": {
            "id": "SDD-1",
            "state": "active",
            "successor_coordinate": "SDD-2",
            "ancestors": "SDD-0",
        },
        "successor": {
            "id": "SDD-2",
            "backlink": "SDD-1",
            "evidence_coordinate": "evidence/SDD-2/fixture-successor-v1.yaml",
        },
        "old_evidence_coordinate": "evidence/SDD-1/fixture-old-v1.yaml",
    },
    "SDD-1-POLICY-01": {
        "policy_schema_version": 1,
        "repositories": {
            WORKSPACE_REPO: SHA_WORKSPACE_CUTOVER,
            PRODUCT_REPO: SHA_PRODUCT_CUTOVER,
        },
        "commit_exists_in": {
            SHA_WORKSPACE_CUTOVER: WORKSPACE_REPO,
            SHA_PRODUCT_CUTOVER: PRODUCT_REPO,
        },
        "api": {"commit_lookup": "available"},
    },
    "SDD-1-DAG-01": {
        "candidate": {
            "repo": WORKSPACE_REPO,
            "base_sha": SHA_BASE,
            "head_sha": SHA_HEAD,
        },
        "cutover_commit": SHA_WORKSPACE_CUTOVER,
        "relation": "base-is-ancestor-of-cutover",
        "registered_route": "legacy",
        "legacy_registry": {"%s#400" % WORKSPACE_REPO: "legacy"},
        "package_present": False,
    },
    "SDD-1-DAG-02": {
        "candidate": {
            "repo": WORKSPACE_REPO,
            "base_sha": SHA_WORKSPACE_CUTOVER,
            "head_sha": SHA_HEAD,
        },
        "cutover_commit": SHA_WORKSPACE_CUTOVER,
        "relation": "base-equals-cutover",
        "package_present": True,
        "package_diff_exact_mapped": True,
    },
    "SDD-1-DAG-04": {
        "candidate": {
            "repo": PRODUCT_REPO,
            "base_sha": SHA_BASE,
            "head_sha": SHA_HEAD,
        },
        "cutover_commit": SHA_PRODUCT_CUTOVER,
        "relation": "cutover-is-ancestor-of-base",
        "ref_lookup": {"base": "available", "head": "available"},
        "repo_membership": {"base_sha": PRODUCT_REPO, "head_sha": PRODUCT_REPO},
        "package_present": True,
    },
    "SDD-1-DAG-09": {
        "change_coordinate": "SDD-1 / %s#480" % WORKSPACE_REPO,
        "bootstrap_recorded": True,
        "creates_cutover_coordinates": True,
        "self_package_present": False,
    },
    "SDD-1-CENSUS-01": {
        "producer": "independent",
        "coverage": {
            "workspace-open-prs": "query=repo:%s+is:pr+is:open result=pr-481" % WORKSPACE_REPO,
            "product-open-prs": "query=repo:%s+is:pr+is:open result=pr-1500" % PRODUCT_REPO,
            "live-in-progress-issues": "query=label:status:in-progress+is:open result=issue-480",
        },
        "etag": "W/fixture-census-etag-v1",
        "timestamp": "2026-09-02T00:00:00Z",
        "freshness_predicate": "captured-within-24h",
        "response_digest": "sha256:fixture-census-v1",
        "api": {"availability": "available"},
    },
    "SDD-1-CENSUS-07": {
        "snapshot": {
            "%s#481" % WORKSPACE_REPO: "open-pr",
            "%s#1500" % PRODUCT_REPO: "open-pr",
        },
        "policy_registry": {
            "%s#481" % WORKSPACE_REPO: "issue+acceptance_path+route",
            "%s#1500" % PRODUCT_REPO: "issue+acceptance_path+route",
        },
    },
    "SDD-1-CENSUS-10": {
        "legacy_change": {
            "route": "legacy",
            "acceptance_hash": "sha256:fixture-legacy-v1",
            "observable_contract_hash": "sha256:fixture-contract-v1",
        },
        "post_cutover_observed": {
            "acceptance_hash": "sha256:fixture-legacy-v1",
            "observable_contract_hash": "sha256:fixture-contract-v1",
        },
    },
    "SDD-1-CENSUS-12": {
        "legacy_change": {"route": "migrate"},
        "package_present": True,
        "package_exact_maps_candidate_diff": True,
    },
    "SDD-1-CENSUS-14": {
        "acceptance": {"state": "closed", "closed_before_census": True},
        "snapshot_open_prs": {},
        "snapshot_live_issues": {},
        "backfill_required": False,
    },
    "SDD-1-WIRE-01": {
        "blocking_callers": {
            "workspace/scripts/hooks/pre-push": "calls-gate",
            "workspace/.github/workflows/ci.yaml": "calls-gate",
            "project/kacho/scripts/hooks/pre-push": "calls-gate",
            "project/kacho/.github/workflows/ci.yaml": "calls-gate",
        }
    },
    "SDD-1-WSPP-01": {
        "stdin_ref_line": {"remote_sha": SHA_BASE, "local_sha": SHA_HEAD},
        "workspace": {
            "repo": WORKSPACE_REPO,
            "base_sha": SHA_BASE,
            "head_sha": SHA_HEAD,
        },
        "sibling_product": {"repo": PRODUCT_REPO, "coordinate": "project/kacho"},
        "package_tasks_mapping": ["SDD-1-WSPP-01", "SDD-1-WSPP-02"],
    },
    "SDD-1-WSCI-01": {
        "workspace": {
            "repo": WORKSPACE_REPO,
            "base_sha": SHA_BASE,
            "head_sha": SHA_HEAD,
        },
        "sibling_product_coordinate": "project/kacho",
        "ref_lookup": {"base": "available", "head": "available"},
        "package_tasks_mapping": ["SDD-1-WSCI-01", "SDD-1-WSCI-02"],
    },
    "SDD-1-PPRE-01": {
        "stdin_ref_line": {"remote_sha": SHA_BASE, "local_sha": SHA_HEAD},
        "product": {"repo": PRODUCT_REPO, "base_sha": SHA_BASE, "head_sha": SHA_HEAD},
        "sibling_workspace": {
            "repo": WORKSPACE_REPO,
            "pinned_policy_revision": SHA_WORKSPACE_CUTOVER,
        },
        "package_tasks_mapping": ["SDD-1-PPRE-01", "SDD-1-PPRE-02"],
    },
    "SDD-1-PCI-01": {
        "product_ledger": {
            "change_id": "SDD-1",
            "workspace_revision": SHA_WORKSPACE_CUTOVER,
        },
        "workspace_fetch": {
            "outcome": "available",
            "revision_resolves": "available",
        },
        "github_event": {"base_sha": SHA_BASE, "head_sha": SHA_HEAD},
        "package_tasks_mapping": ["SDD-1-PCI-01", "SDD-1-PCI-02"],
    },
    "SDD-1-ADV-01": {
        "advisory_hook_outcome": "GREEN",
        "authoritative_callers": {
            "workspace/scripts/hooks/pre-push": "valid-graph",
            "workspace/.github/workflows/ci.yaml": "valid-graph",
            "project/kacho/scripts/hooks/pre-push": "valid-graph",
            "project/kacho/.github/workflows/ci.yaml": "valid-graph",
        },
        "graph_facts": {"trace-exact-set": "ok", "holders-complete": "ok"},
    },
}


# Adapter-миры выделены отдельно: canonical inputs и generated coordinates —
# СПИСКИ, потому что два кейса меняют элемент на месте (uppercase-вариант пути и
# machine-absolute path). В словаре такая правка была бы сменой ключа, то есть
# двумя фактами.
_ADAPTER_TRACKED_OUTPUTS = {
    "AGENTS.md": "sha256:fixture-adapter-out-1",
    ".agents/skills/evgeniy/SKILL.md": "sha256:fixture-adapter-out-2",
    ".codex/agents/evgeniy.toml": "sha256:fixture-adapter-out-3",
    ".codex/hooks.json": "sha256:fixture-adapter-out-4",
}

_ADAPTER_CANONICAL_INPUTS = [
    "CLAUDE.md",
    ".claude/adapters.yaml",
    ".claude/agents",
    ".claude/hooks",
    ".claude/rules",
    ".claude/skills",
    ".claude/settings.json",
]

_ADAPTER_GENERATED_COORDINATES = [
    "AGENTS.md",
    ".agents/skills/evgeniy/SKILL.md",
    ".codex/agents/evgeniy.toml",
    ".codex/hooks.json",
]


def _adapter_world():
    return {
        "manifest_path": ".claude/adapters.yaml",
        "manifest_owned_outputs": {
            "AGENTS.md": "owned",
            ".agents/skills/evgeniy/SKILL.md": "owned",
            ".codex/agents/evgeniy.toml": "owned",
            ".codex/hooks.json": "owned",
        },
        "canonical_inputs": list(_ADAPTER_CANONICAL_INPUTS),
        "generated_coordinates": list(_ADAPTER_GENERATED_COORDINATES),
        "tracked_outputs": dict(_ADAPTER_TRACKED_OUTPUTS),
        "regenerated_outputs": dict(_ADAPTER_TRACKED_OUTPUTS),
        "second_regeneration_outputs": dict(_ADAPTER_TRACKED_OUTPUTS),
        "nested_assets": {
            ".agents/skills/evgeniy/references/EXAMPLES.md": "present",
            ".agents/skills/hardening-audit-loop/references/audit-round.workflow.js": "present",
        },
        "design_decision_outputs": "tracked",
    }


BASE_WORLDS["SDD-1-ADAPTER-01"] = _adapter_world()

# ADAPTER-04 — тот же контракт adapter'а плюс ЧУЖОЙ runtime package рядом.
# Он не входит в manifest и не обязан входить: предмет кейса — что чужой пакет
# не считается adapter output и не маскирует drift.
BASE_WORLDS["SDD-1-ADAPTER-04"] = dict(
    _adapter_world(),
    foreign_runtime_packages={".agents/skills/superpowers": "not-adapter-owned"},
)

BASE_WORLDS["SDD-1-ADAPTER-12"] = {
    "manifest_skills": {
        "evgeniy": "full-package",
        "hardening-audit-loop": "full-package",
        "obsidian-markdown": "full-package",
    },
    "package_contents": {
        ".agents/skills/hardening-audit-loop/references/audit-round.workflow.js": "present",
        ".agents/skills/evgeniy/references/EXAMPLES.md": "present",
        ".agents/skills/obsidian-markdown/references/obsidian-syntax.md": "present",
    },
    "matches_actual_tree": True,
}


# --------------------------------------------------------------------------
# Дельты. Ключ — case ID; значение — (операция, путь, значение, названный факт).
# Для операции remove значение не используется и записывается как None.
# --------------------------------------------------------------------------
DERIVED = {
    # --- Bootstrap ---------------------------------------------------------
    "SDD-1-BOOT-02": (
        "change", "bootstrap.change_id", "SDD-9-second-bootstrap",
        "bootstrap change_id закреплён за #480, подменён на другой change",
    ),
    # --- External verdict --------------------------------------------------
    "SDD-1-REVIEW-02": (
        "change", "subject.static_form", "APPROVED",
        "статическая форма subject переписана с DRAFT на APPROVED",
    ),
    "SDD-1-REVIEW-04": (
        "change", "recorded_content.sha-3f1d9196",
        "sha256:fixture-record-changes-requested-1-mutated-one-byte",
        "содержимое одного старого review artifact изменено на один байт",
    ),
    "SDD-1-REVIEW-05": (
        "change", "permission.level", "WRITE",
        "GitHub permission publisher понижен с ADMIN на WRITE",
    ),
    "SDD-1-REVIEW-06": (
        "change", "artifact.authorized_actor", "not-the-publisher",
        "authorized_actor artifact не равен publisher event",
    ),
    "SDD-1-REVIEW-07": (
        "change", "event.issue", "%s#481" % WORKSPACE_REPO,
        "parent Issue coordinate event сменена с #480 на #481",
    ),
    "SDD-1-REVIEW-08": (
        "change", "permission.lookup", "unavailable",
        "GitHub permission lookup недоступен",
    ),
    "SDD-1-REVIEW-09": (
        "change", "event.lookup", "unavailable",
        "lookup event Issue #480 недоступен",
    ),
    "SDD-1-REVIEW-10": (
        "change", "bootstrap.epoch", "post-cutover",
        "authority epoch сменён с pre-cutover на post-cutover",
    ),
    # --- External authority ------------------------------------------------
    "SDD-1-AUTH-02": (
        "remove", "artifact.event_coordinate", None,
        "event coordinate снята, role в artifact оставлена",
    ),
    "SDD-1-AUTH-03": (
        "change", "event.actor", "outsider-not-in-allowlist",
        "actor event отсутствует в policy allowlist",
    ),
    "SDD-1-AUTH-04": (
        "change", "event.body_sha256", "sha256:fixture-body-v1-divergent",
        "body digest event не совпадает с artifact",
    ),
    "SDD-1-AUTH-05": (
        "change", "event.subject_sha256", "sha256:fixture-design-v1-divergent",
        "subject digest event не совпадает с artifact",
    ),
    "SDD-1-AUTH-06": (
        "remove", "event.node_id", None,
        "immutable node ID event снят",
    ),
    "SDD-1-AUTH-07": (
        "change", "event.role", "go-style-reviewer",
        "event зарегистрирован не для required role",
    ),
    "SDD-1-AUTH-08": (
        "change", "api.availability", "unavailable",
        "GitHub API недоступен",
    ),
    # --- Truth ownership ---------------------------------------------------
    "SDD-1-TRUTH-02": (
        "change", "duplicated_observable_requirement", "design.md",
        "второй artifact копирует observable requirement acceptance",
    ),
    "SDD-1-TRUTH-03": (
        "change", "second_owner_conflict", "tasks.md противоречит acceptance",
        "утверждение второго owner конфликтует с первым",
    ),
    "SDD-1-TRUTH-04": (
        "change", "tasks_contains_live_status", True,
        "в tasks добавлен live status, то есть tasks стал tracker'ом",
    ),
    "SDD-1-TRUTH-05": (
        "change", "change_yaml_contains_requirement_prose", True,
        "в change.yaml добавлен requirement paragraph",
    ),
    "SDD-1-TRUTH-06": (
        "remove", "required_holders.human-semantic", None,
        "required human semantic holder снят, machine result оставлен",
    ),
    # --- Lifecycle ---------------------------------------------------------
    "SDD-1-LIFE-02": (
        "change", "requested_transition", "LANDED",
        "запрошен transition через обязательную stage",
    ),
    "SDD-1-LIFE-03": (
        "remove", "required_artifacts.design", None,
        "снят один required artifact текущей stage",
    ),
    # --- Non-vacuity -------------------------------------------------------
    "SDD-1-NONEMPTY-02": (
        "remove", "acceptance_ids.SDD-1-NONEMPTY-01", None,
        "acceptance ID set очищен",
    ),
    "SDD-1-NONEMPTY-03": (
        "remove", "required_holders.process-gate", None,
        "required holder set очищен",
    ),
    "SDD-1-NONEMPTY-04": (
        "remove", "holder_subjects.process-gate", None,
        "снят subject одного holder",
    ),
    # --- Class exposure ----------------------------------------------------
    "SDD-1-CLASS-02": (
        "remove", "records.class-exposure-initial", None,
        "initial class-exposure record снят",
    ),
    "SDD-1-CLASS-03": (
        "change", "acceptance_content_digest", "sha256:fixture-acceptance-v2",
        "acceptance hash изменён, initial record остался связан со старым",
    ),
    "SDD-1-CLASS-05": (
        "remove", "exposure_items.exposure-2", None,
        "снят mapping одного exposure item в design decision",
    ),
    "SDD-1-CLASS-06": (
        "remove", "records.class-exposure-revalidation", None,
        "revalidation record снят",
    ),
    "SDD-1-CLASS-07": (
        "change", "revalidation_bound_design_hash", "sha256:fixture-design-v0",
        "revalidation связана с design hash, предшествующим текущему",
    ),
    "SDD-1-CLASS-08": (
        "add", "external_calls.new-peer-call", "unmapped",
        "заведён один external call без mapping и revalidation",
    ),
    "SDD-1-CLASS-09": (
        "add", "async_paths.new-async-path", "unmapped",
        "заведён один async path без mapping и revalidation",
    ),
    "SDD-1-CLASS-10": (
        "add", "sentinels.new-sentinel", "unmapped",
        "заведён один sentinel без mapping и revalidation",
    ),
    # --- Design and tasks --------------------------------------------------
    "SDD-1-DESIGN-02": (
        "change", "design.open_decision_markers", "TODO: формат ещё не выбран",
        "в design добавлен один открытый decision marker",
    ),
    "SDD-1-DESIGN-03": (
        "remove", "applicable_precode_reviews.db-architect-reviewer", None,
        "снят один applicable pre-code review",
    ),
    "SDD-1-NA-02": (
        "change", "applicability.predicate_id", "unregistered-predicate",
        "predicate ID отсутствует в versioned applicability registry",
    ),
    "SDD-1-NA-03": (
        "change", "evidence.migrations_touched", 3,
        "evidence делает зарегистрированный predicate ложным",
    ),
    "SDD-1-TASKS-02": (
        "remove", "handoff.event", None,
        "снят verified writing-plans handoff event",
    ),
    "SDD-1-TASKS-03": (
        "change", "design_stage", "DESIGN_DRAFT",
        "design stage не утверждена, а tasks уже произведены",
    ),
    # --- Pre-RED и implementation boundary ---------------------------------
    "SDD-1-TDD-03": (
        "change", "initial_holder.category", "GREEN",
        "initial holder outcome изменён на GREEN",
    ),
    "SDD-1-TDD-04": (
        "change", "initial_holder.category", "NOT_EXECUTED",
        "initial holder outcome изменён на NOT_EXECUTED",
    ),
    "SDD-1-TDD-05": (
        "change", "captured_outcome", "unrelated-driver-infrastructure-crash",
        "captured outcome стал посторонним crash'ем driver/infrastructure",
    ),
    "SDD-1-TDD-07": (
        "change", "stage", "TASKS_READY",
        "RED_PROVEN отсутствует, а implementation уже идёт",
    ),
    "SDD-1-TDD-08": (
        "add", "diff_paths['scripts/change-graph-gate/tests/caselib/production_rule.py']",
        "implementation",
        "внутрь tests/** внесено одно implementation behavior",
    ),
    "SDD-1-TDD-09": (
        "change", "driver.synthesizes_expected_triple", True,
        "driver синтезирует ожидаемую SUT triple вместо обращения к seam",
    ),
    "SDD-1-TDD-10": (
        "change", "test_diff_owner", "rpc-implementer",
        "verified owner test diff не integration-tester",
    ),

    # --- Machine-holder provenance ----------------------------------------
    "SDD-1-HOLDER-02": (
        "remove", "holder.id", None, "снят holder ID",
    ),
    "SDD-1-HOLDER-03": (
        "change", "holder.executable", "true",
        "executable подменён тривиальной командой true",
    ),
    "SDD-1-HOLDER-04": (
        "change", "holder.executable", "unregistered-command --run",
        "executable указывает на незарегистрированную команду",
    ),
    "SDD-1-HOLDER-05": (
        "remove", "holder.predicate", None, "снят predicate holder'а",
    ),
    "SDD-1-HOLDER-06": (
        "change", "holder.subject_sha256", "sha256:fixture-subject-v1-divergent",
        "subject hash holder'а не совпал с наблюдаемым содержимым",
    ),
    "SDD-1-HOLDER-07": (
        "change", "holder.input_sha256", "sha256:fixture-input-v1-divergent",
        "input hash holder'а не совпал с наблюдаемым содержимым",
    ),
    "SDD-1-HOLDER-08": (
        "change", "holder.output_sha256", "sha256:fixture-output-v1-divergent",
        "output hash holder'а не совпал с наблюдаемым содержимым",
    ),
    "SDD-1-HOLDER-09": (
        "change", "holder.stdout_digest", "sha256:fixture-stdout-v1-divergent",
        "stdout digest holder'а не совпал с наблюдаемым",
    ),
    "SDD-1-HOLDER-10": (
        "change", "holder.stderr_digest", "sha256:fixture-stderr-v1-divergent",
        "stderr digest holder'а не совпал с наблюдаемым",
    ),
    "SDD-1-HOLDER-11": (
        "remove", "holder.captured_category", None, "снята captured category",
    ),
    "SDD-1-HOLDER-12": (
        "remove", "holder.evidence_coordinate", None, "снята evidence coordinate",
    ),
    "SDD-1-HOLDER-13": (
        "remove", "holder.owner", None, "снят owner holder'а",
    ),
    "SDD-1-BIRTH-02": (
        "change", "birth_runs.known-good-input", "RED",
        "known-good input перестал давать ожидаемый pass",
    ),
    "SDD-1-BIRTH-03": (
        "change", "birth_runs.one-fact-injected-defect", "GREEN",
        "однофактный injected defect перестал давать ожидаемый RED",
    ),
    "SDD-1-BIRTH-04": (
        "change", "census_entry_count", 0,
        "census birth-run обнулён при сохранённом GREEN verdict",
    ),
    # --- Hash invalidation, trace, evidence --------------------------------
    "SDD-1-HASH-02": (
        "change", "manifest_hashes.design", "sha256:fixture-design-v9",
        "manifest hash одного artifact разошёлся с его content hash",
    ),
    "SDD-1-HASH-03": (
        "change", "content_hashes.design", "sha256:fixture-design-v2",
        "содержимое subject изменено, approval остался связан со старым hash",
    ),
    "SDD-1-HASH-04": (
        "change", "content_hashes.acceptance", "sha256:fixture-acceptance-v2",
        "содержимое acceptance изменено после downstream approvals",
    ),
    "SDD-1-HASH-05": (
        "change", "design_content_digest", "sha256:fixture-design-v2",
        "содержимое design изменено, initial acceptance-bound analysis сохранён",
    ),
    "SDD-1-TRACE-02": (
        "remove", "evidence_plan_ids[1]", None,
        "из evidence plan снят один acceptance ID",
    ),
    "SDD-1-TRACE-03": (
        "add", "evidence_plan_ids[2]", "SDD-1-TRACE-99",
        "в evidence plan добавлен один несуществующий acceptance ID",
    ),
    "SDD-1-TRACE-04": (
        "change", "design_ids[1]", "SDD-1-TRACE-88",
        "один downstream ID заменён другим, cardinality не изменилась",
    ),
    "SDD-1-EVID-02": (
        "add", "evidence_plan_ids[2]", "SDD-1-EVID-99",
        "в evidence plan добавлен один несуществующий acceptance ID",
    ),
    "SDD-1-EVID-03": (
        "change", "required_holders.process-gate", "RED",
        "один required holder outcome стал RED",
    ),
    "SDD-1-EVID-04": (
        "change", "required_holders.process-gate", "NOT_EXECUTED",
        "один required holder outcome стал NOT_EXECUTED",
    ),
    "SDD-1-EVID-05": (
        "remove", "captured_outputs.process-gate", None,
        "снят captured output одного required holder",
    ),
    "SDD-1-DRIVER-01": (
        "change", "driver_birth.actual_triple", "GREEN · CG_TRACE_ID_ORPHAN · exit 10",
        "фактическая тройка отличается от driver assertion только категорией",
    ),
    "SDD-1-DRIVER-02": (
        "change", "driver_birth.actual_triple", "RED · CG_TRACE_ID_MISSING · exit 10",
        "фактическая тройка отличается от driver assertion только диагностикой",
    ),
    "SDD-1-DRIVER-03": (
        "change", "driver_birth.actual_triple", "RED · CG_TRACE_ID_ORPHAN · exit 0",
        "фактическая тройка отличается от driver assertion только кодом возврата",
    ),
    # --- Diff ownership, post-diff, convergence ----------------------------
    "SDD-1-DIFF-02": (
        "add", "actual_changed_paths['scripts/unclaimed-change.py']",
        "sha256:fixture-blob-9",
        "фактически изменён один path вне approved diff set",
    ),
    "SDD-1-DIFF-03": (
        "add", "approved_diff_paths['docs/changes/SDD-1/orphan-claim.md']",
        "sha256:fixture-blob-8",
        "заявлен один path, которого нет в фактическом diff",
    ),
    "SDD-1-DIFF-04": (
        "add", "second_active_change_claims['scripts/change-graph-gate/run.py']", "SDD-2",
        "один path дополнительно заявлен вторым active change",
    ),
    "SDD-1-DIFF-05": (
        "change", "reviewed_diff_blobs['scripts/change-graph-gate/run.py']",
        "sha256:fixture-blob-1-drifted",
        "один final blob разошёлся с reviewed diff set",
    ),
    "SDD-1-POST-02": (
        "remove", "post_diff_records.db-architect-reviewer", None,
        "снят post-diff record одного applicable role",
    ),
    "SDD-1-POST-03": (
        "change", "post_diff_records.db-architect-reviewer",
        "reviews/post-diff/go-style-reviewer/fixture-content-v1.yaml",
        "coordinate второго role указывает на файл первого role",
    ),
    "SDD-1-POST-05": (
        "remove", "post_diff_records.system-design-reviewer", None,
        "снят post-diff system-design record при distributed surface",
    ),
    "SDD-1-POST-NA-02": (
        "change", "evidence.migrations_touched", 2,
        "evidence делает predicate role истинным, то есть N/A ложным",
    ),
    "SDD-1-CONV-02": (
        "change", "convergence.actor", "outsider-not-convergence-reviewer",
        "actor event не разрешён для роли convergence-reviewer",
    ),
    "SDD-1-CONV-03": (
        "remove", "convergence.event_coordinate", None,
        "снята event coordinate convergence record",
    ),
    "SDD-1-CONV-04": (
        "change", "api.availability", "unavailable",
        "GitHub API response недоступен",
    ),
    "SDD-1-CONV-05": (
        "remove", "repos.product_source_sha", None,
        "снят source SHA одного repo",
    ),
    "SDD-1-CONV-06": (
        "change", "convergence_aggregator_specialists",
        "go-style-reviewer,db-architect-reviewer",
        "aggregator ссылается на exact coordinates всех applicable specialist records",
    ),
    "SDD-1-CONV-07": (
        "change", "convergence_aggregator_specialists", "go-style-reviewer",
        "из aggregator снята одна specialist coordinate",
    ),
    # --- Landing и terminal states -----------------------------------------
    "SDD-1-LAND-02": (
        "change", "landed_blobs['scripts/change-graph-gate/run.py']",
        "sha256:fixture-blob-1-drifted",
        "один landed blob разошёлся с convergence content digest",
    ),
    "SDD-1-LAND-03": (
        "change", "landed.commit_sha", SHA_OTHER,
        "commit SHA новый, canonical content set прежний",
    ),
    "SDD-1-WITHDRAW-02": (
        "change", "source_state", "LANDED",
        "source state уже LANDED, а запрошен withdraw",
    ),
    "SDD-1-WITHDRAW-03": (
        "remove", "event.reason", None, "снят reason withdraw event",
    ),
    "SDD-1-SUPER-02": (
        "remove", "old_change.successor_coordinate", None,
        "снята successor coordinate",
    ),
    "SDD-1-SUPER-03": (
        "remove", "successor.backlink", None, "снят backlink successor'а",
    ),
    "SDD-1-SUPER-04": (
        "change", "old_change.successor_coordinate", "SDD-0",
        "successor coordinate указывает на ancestor, образуя цикл",
    ),
    "SDD-1-SUPER-05": (
        "change", "successor.evidence_coordinate",
        "evidence/SDD-1/fixture-old-v1.yaml",
        "successor переиспользует evidence, связанный со старым subject",
    ),

    # --- Policy, dual-DAG cutover, legacy census ---------------------------
    "SDD-1-POLICY-02": (
        "remove", "repositories.%s" % WORKSPACE_REPO, None,
        "снят repository entry workspace из policy",
    ),
    "SDD-1-POLICY-03": (
        "change", "repositories.%s" % WORKSPACE_REPO, "not-a-valid-40-hex-sha",
        "workspace cutover commit перестал быть валидным 40-hex",
    ),
    "SDD-1-POLICY-04": (
        "change", "repositories.%s" % WORKSPACE_REPO, SHA_ABSENT,
        "workspace cutover — валидный 40-hex, отсутствующий в repo по healthy API",
    ),
    "SDD-1-POLICY-05": (
        "change", "repositories.%s" % WORKSPACE_REPO, SHA_PRODUCT_CUTOVER,
        "workspace cutover указывает на существующий product SHA вне workspace DAG",
    ),
    "SDD-1-POLICY-06": (
        "change", "api.commit_lookup", "unavailable",
        "GitHub commit API недоступен",
    ),
    "SDD-1-DAG-03": (
        "change", "package_present", False,
        "package снят при base, равном cutover_commit",
    ),
    "SDD-1-DAG-05": (
        "change", "package_present", False,
        "package снят при cutover, предшествующем base",
    ),
    "SDD-1-DAG-06": (
        "change", "relation", "incomparable",
        "candidate base несравним с cutover_commit",
    ),
    "SDD-1-DAG-07": (
        "change", "ref_lookup.head", "unavailable",
        "lookup head ref недоступен",
    ),
    "SDD-1-DAG-08": (
        "change", "candidate.repo", WORKSPACE_REPO,
        "repo identity названа так, что base/head ей не принадлежат",
    ),
    "SDD-1-DAG-10": (
        "change", "change_coordinate", "SDD-9 / %s#999" % WORKSPACE_REPO,
        "change coordinate bootstrap сменена с #480 на другой change",
    ),
    "SDD-1-CENSUS-02": (
        "change", "api.availability", "unavailable",
        "GitHub API census producer недоступен",
    ),
    "SDD-1-CENSUS-03": (
        "change", "timestamp", "2026-08-01T00:00:00Z",
        "timestamp census вышел за versioned freshness predicate",
    ),
    "SDD-1-CENSUS-04": (
        "remove", "coverage.product-open-prs", None,
        "снят product open-PR query вместе с его результатом",
    ),
    "SDD-1-CENSUS-05": (
        "remove", "coverage.workspace-open-prs", None,
        "снят workspace open-PR query вместе с его результатом",
    ),
    "SDD-1-CENSUS-06": (
        "remove", "coverage.live-in-progress-issues", None,
        "снят live in-progress Issue query вместе с его результатом",
    ),
    "SDD-1-CENSUS-08": (
        "remove", "policy_registry.%s#481" % WORKSPACE_REPO, None,
        "из policy registry снят один active snapshot change",
    ),
    "SDD-1-CENSUS-09": (
        "add", "policy_registry.%s#9999" % PRODUCT_REPO,
        "issue+acceptance_path+route",
        "в policy registry добавлен entry, отсутствующий в snapshot",
    ),
    "SDD-1-CENSUS-11": (
        "change", "post_cutover_observed.observable_contract_hash",
        "sha256:fixture-contract-v2",
        "observable contract зарегистрированного legacy изменился после cutover",
    ),
    "SDD-1-CENSUS-13": (
        "change", "package_present", False,
        "у change с route migrate снят Change Graph package",
    ),
    # --- Tracked adapter ---------------------------------------------------
    "SDD-1-ADAPTER-02": (
        "change", "tracked_outputs['AGENTS.md']",
        "sha256:fixture-adapter-out-1-drifted",
        "один байт tracked adapter-owned output разошёлся с регенерацией",
    ),
    "SDD-1-ADAPTER-03": (
        "remove",
        "nested_assets['.agents/skills/evgeniy/references/EXAMPLES.md']",
        None,
        "снят один nested asset полного skill package",
    ),
    "SDD-1-ADAPTER-05": (
        "add", "tracked_outputs['.codex/hooks/extra-generated.sh']",
        "sha256:fixture-adapter-out-9",
        "в owned namespace добавлен tracked output вне manifest exact set",
    ),
    "SDD-1-ADAPTER-06": (
        "remove", "tracked_outputs['.codex/hooks.json']", None,
        "снят один manifest-owned tracked output",
    ),
    "SDD-1-ADAPTER-07": (
        "change", "design_decision_outputs", "runtime-untracked-only",
        "design decision переведено с tracked outputs на runtime/untracked-only",
    ),
    "SDD-1-ADAPTER-08": (
        "change", "canonical_inputs[2]", ".Claude/agents",
        "один canonical path записан с uppercase-вариантом .Claude",
    ),
    "SDD-1-ADAPTER-09": (
        "change", "generated_coordinates[0]",
        "/home/fixture/absolute/AGENTS.md",
        "одна generated coordinate записана machine-absolute путём",
    ),
    "SDD-1-ADAPTER-10": (
        "add", "canonical_inputs[7]", "docs/extra-non-canonical-input.md",
        "добавлен input вне root CLAUDE.md и tracked .claude/**",
    ),
    "SDD-1-ADAPTER-11": (
        "change", "second_regeneration_outputs['AGENTS.md']",
        "sha256:fixture-adapter-out-1-second-run",
        "вторая регенерация при тех же input hashes дала другой output",
    ),
    "SDD-1-ADAPTER-13": (
        "change", "tracked_outputs['AGENTS.md']",
        "sha256:fixture-adapter-out-1-drifted",
        "при неизменном foreign package изменён один байт adapter-owned output",
    ),
    # --- Authoritative callers и advisory hooks ----------------------------
    "SDD-1-WIRE-02": (
        "remove", "blocking_callers.workspace/scripts/hooks/pre-push", None,
        "снят вызов gate из workspace scripts/hooks/pre-push",
    ),
    "SDD-1-WIRE-03": (
        "remove", "blocking_callers['workspace/.github/workflows/ci.yaml']", None,
        "снят вызов gate из workspace .github/workflows/ci.yaml",
    ),
    "SDD-1-WIRE-04": (
        "remove", "blocking_callers.project/kacho/scripts/hooks/pre-push", None,
        "снят вызов gate из product scripts/hooks/pre-push",
    ),
    "SDD-1-WIRE-05": (
        "remove", "blocking_callers['project/kacho/.github/workflows/ci.yaml']", None,
        "снят вызов gate из product .github/workflows/ci.yaml",
    ),
    "SDD-1-WSPP-02": (
        "remove", "package_tasks_mapping[1]", None,
        "из package tasks mapping снят один существующий acceptance case ID",
    ),
    "SDD-1-WSPP-03": (
        "remove", "sibling_product.repo", None,
        "снят sibling product repo",
    ),
    "SDD-1-WSPP-04": (
        "remove", "stdin_ref_line.remote_sha", None,
        "снят remote SHA во входной stdin ref line",
    ),
    "SDD-1-WSCI-02": (
        "remove", "package_tasks_mapping[1]", None,
        "из package tasks mapping снят один существующий acceptance case ID",
    ),
    "SDD-1-WSCI-03": (
        "remove", "sibling_product_coordinate", None,
        "снята sibling product coordinate",
    ),
    "SDD-1-WSCI-04": (
        "change", "ref_lookup.base", "unavailable",
        "lookup base ref недоступен",
    ),
    "SDD-1-PPRE-02": (
        "remove", "package_tasks_mapping[1]", None,
        "из package tasks mapping снят один существующий acceptance case ID",
    ),
    "SDD-1-PPRE-03": (
        "remove", "sibling_workspace.repo", None,
        "снят sibling workspace repo",
    ),
    "SDD-1-PPRE-04": (
        "remove", "stdin_ref_line.local_sha", None,
        "снят local SHA во входной stdin ref line",
    ),
    "SDD-1-PCI-02": (
        "remove", "package_tasks_mapping[1]", None,
        "из package tasks mapping снят один существующий acceptance case ID",
    ),
    "SDD-1-PCI-03": (
        "change", "workspace_fetch.outcome", "unavailable",
        "fetch public workspace недоступен",
    ),
    "SDD-1-PCI-04": (
        "change", "workspace_fetch.revision_resolves", "unavailable",
        "pinned workspace revision не резолвится",
    ),
    "SDD-1-PCI-05": (
        "remove", "github_event.base_sha", None,
        "снят product base SHA в GitHub event",
    ),
    "SDD-1-PCI-06": (
        "remove", "product_ledger.change_id", None,
        "снят change_id из product ledger",
    ),
    "SDD-1-ADV-02": (
        "change", "graph_facts.trace-exact-set", "orphan-id-present",
        "изменён один graph fact при сохранённом GREEN advisory outcome",
    ),
    "SDD-1-ADV-03": (
        "remove", "advisory_hook_outcome", None,
        "снят advisory hook при неизменных authoritative inputs",
    ),
}
