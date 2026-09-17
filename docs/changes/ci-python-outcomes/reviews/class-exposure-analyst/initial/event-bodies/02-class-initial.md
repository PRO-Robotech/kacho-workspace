# CI-PY-1: class-exposure-analyst — RECORDED

Независимый review выполнен агентом `/root/e2e_audit` по документам автора `/root/hygiene_audit`. Оркестратор публикует фактически полученный вердикт через действующего GitHub actor `pointpu`, разрешённого versioned policy для этой роли. Это агентное review; личное рассмотрение владельцем здесь не заявляется.

```json
{
  "change_id": "ci-python-outcomes",
  "reviewer_role": "class-exposure-analyst",
  "verdict": "RECORDED",
  "subject_repo": "PRO-Robotech/kacho-workspace",
  "subject_path": "docs/specs/sub-phase-CI-PY-1-python-outcomes-acceptance.md",
  "subject_sha256": "427493262f75bcef467f1864c6327abde34661f03d4748029f26269ae95f658e",
  "source_reviewer": "/root/e2e_audit",
  "source_review_sha256": "e8615cd7e3a4bc7b7a696f4149c554535f91f01d8d0fb4a7e2f908ab1cda5dde",
  "related_issues": [
    "PRO-Robotech/kacho#2281",
    "PRO-Robotech/kacho#2629",
    "PRO-Robotech/kacho#2705"
  ],
  "phase": "initial",
  "bound_acceptance_sha256": "427493262f75bcef467f1864c6327abde34661f03d4748029f26269ae95f658e",
  "exposure_item_ids": [
    "E1",
    "E2",
    "E3",
    "E4",
    "E5",
    "E6",
    "E7",
    "E8",
    "E9",
    "E10",
    "E11",
    "E12"
  ]
}
```

Bound to acceptance SHA256 above. The following independent exposure list is accepted as the initial analysis, preceding design revalidation.

| ID | Decision / exposure | Checkable implementation condition | Required holder |
|---|---|---|---|
| E1 | Three outcomes collapse into success/finding; code-authoring, Third outcome | Missing pytest is separately typed; only complete nonempty execution returns full green | CI-PY-01..04,12 |
| E2 | Sentinel collision: Python argparse2 and Make2 | Category comes from a validated current result, never raw code2 or a substring | CI-PY-09,11 |
| E3 | Fallback fabricates a fact; absent report read as zero failures | Missing/unreadable report adds unmet, never executed or successful instances | CI-PY-06 |
| E4 | Declared/attempted count mistaken for observation | AST declarations, JUnit instances, script calls, selftest calls and top-level checks have distinct named units | CI-PY-05,07,10 |
| E5 | Historical constant becomes truth | Counts derive from actual tracked composition and observed outcomes; parameterization remains lawful | CI-PY-07 |
| E6 | Fixture failure mistaken for RED | Reviewer/test harness has pytest; only child SUT lacks it; setup failure cannot authorize implementation | CI-PY-01..04,10 |
| E7 | Decision and consequence separated; stale or neighbour record | Fresh external temporary directory, per-invocation identity, atomic result, validation before classification | CI-PY-11 |
| E8 | Unification broadens narrow exception | Only confirmed current incomplete-without-finding may replace failure with unmet; subsequent Make recipe failure cannot inherit earlier success | CI-PY-08..11 |
| E9 | One favourable polarity hides the other | Finding and unmet coexist in summary; finding wins aggregate rc; neither is counted as passed | CI-PY-08 |
| E10 | Collected declaration mistaken for executed outcome | Always-final validates complete required results, not collector step conclusion | CI-PY-12 |
| E11 | Input surfaces incomplete; comment/job mistaken for caller | Parsed workflow+actual commands+Make edges establish all callers; zero population fails | CI-PY-13 |
| E12 | Duplicate classification drifts | One stdlib JSON schema/reader/writer; human and machine summary derive from same result | CI-PY-09..12 |

These are checkable conditions, not claims of already present protection. The new holders are proposed, not implemented; they must be executable and RED-proven before source edits.

Independent tree measurements at exact kacho main: 8 tracked Python probe files under the two declared patterns; 34 top-level pytest function declarations; 6 script-main files; pattern population 6+2. The global selftest declaration lists 89 paths, all present in that revision; this is a declaration count, NOT proof 89 discovered or executed. Parsed all 13 workflow YAML files: three actual relevant steps in ci.yaml (authz-artifacts direct producer/selftest, helm gate-self-test, helm helm-manifest-test). Manually read Make dependency and ci-local invocation. `tree-census.json` records coordinates. Full caller execution and full helm runtime are not measured by this review.

Переход к реализации требует отдельного исполняемого holder и честного RED. Этим событием не заявляются реализация, доставка в main или закрытие задач. Статическая шапка предмета остаётся DRAFT; вердикт относится к указанному SHA-256.
