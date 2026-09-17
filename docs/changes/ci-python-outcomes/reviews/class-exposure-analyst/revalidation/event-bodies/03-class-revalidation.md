# CI-PY-1: class-exposure-analyst — REVALIDATED

Независимый review выполнен агентом `/root/e2e_audit` по документам автора `/root/hygiene_audit`. Оркестратор публикует фактически полученный вердикт через действующего GitHub actor `pointpu`, разрешённого versioned policy для этой роли. Это агентное review; личное рассмотрение владельцем здесь не заявляется.

```json
{
  "change_id": "ci-python-outcomes",
  "reviewer_role": "class-exposure-analyst",
  "verdict": "REVALIDATED",
  "subject_repo": "PRO-Robotech/kacho-workspace",
  "subject_path": "docs/specs/sub-phase-CI-PY-1-python-outcomes-design.md",
  "subject_sha256": "26ab94480f7c8c1fdb263d62dd8b060d5b4f9d698bc8ddd39f46c6f78424604d",
  "source_reviewer": "/root/e2e_audit",
  "source_review_sha256": "e8615cd7e3a4bc7b7a696f4149c554535f91f01d8d0fb4a7e2f908ab1cda5dde",
  "related_issues": [
    "PRO-Robotech/kacho#2281",
    "PRO-Robotech/kacho#2629",
    "PRO-Robotech/kacho#2705"
  ],
  "phase": "revalidation",
  "bound_acceptance_sha256": "427493262f75bcef467f1864c6327abde34661f03d4748029f26269ae95f658e",
  "bound_design_sha256": "26ab94480f7c8c1fdb263d62dd8b060d5b4f9d698bc8ddd39f46c6f78424604d",
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
  ],
  "unhandled_item_ids": []
}
```

Bound to design SHA256 above and the initial exposure list E1–E12.

| Exposure | Exact design mapping | Revalidation |
|---|---|---|
| E1 | D1, D3, D5, D6 | handled by explicit 0/1/2 and mandatory final |
| E2 | D1, D4 | handled by current structured result, not ambiguous exit code |
| E3 | D2 | handled by incomplete report outcome |
| E4 | D2, D5 | handled by separate census units and observed result |
| E5 | D2, section3 | handled by computed composition and parameterized twin |
| E6 | D3, section3 | handled by isolated SUT interpreter and valid reviewer prerequisites |
| E7 | D4, section3 | handled by temporary directory, invocation ID, atomic record and validation |
| E8 | D4, D5 | handled by failure precedence and later recipe scope |
| E9 | D5 | handled by dual-category aggregate |
| E10 | D6 | handled by always final required result consumer |
| E11 | D7 | handled by structured caller discovery and injection |
| E12 | D4 | handled by shared schema/implementation |

No unhandled item remains in this design-level mapping. No RPC, DB, external runtime edge or new retry policy is introduced. The local result file is a new asynchronous handoff in miniature; E7/E8 bind its identity and scope explicitly. Actual gate behavior remains to be proven.

Переход к реализации требует отдельного исполняемого holder и честного RED. Этим событием не заявляются реализация, доставка в main или закрытие задач. Статическая шапка предмета остаётся DRAFT; вердикт относится к указанному SHA-256.
