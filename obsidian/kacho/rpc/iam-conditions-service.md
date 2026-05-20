---
title: ConditionsService
aliases:
  - ConditionsService (iam)
  - CEL Conditions CRUD
proto_file: kacho/cloud/iam/v1/conditions_service.proto
category: rpc
backend: kacho-iam
backend_port: 9090
visibility: public
domain: iam
related_resource: "[[resources/iam-condition]]"
methods_count: 6
async_methods: 3
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - rpc
  - kacho-iam
  - iam
  - authz
---

# ConditionsService (iam)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/conditions_service.proto` (Phase 3).
**Backend**: `kacho-iam:9090`.
**Visibility**: **public** — admin / account-owner CRUD + sandboxed Evaluate.
**Status**: **Phase 3 planned**. CRUD reusable CEL-like conditions, ссылаемых на через [[../resources/iam-access-binding-condition]].

## Methods (Phase 3)

| Method | Sync/Async | Description |
|---|---|---|
| CreateCondition | async (Operation) | INSERT в `conditions` table. Body: `expression` (CEL string), `params_schema` (JSON Schema), `kind` (`time` / `ip` / `mfa` / `request_attr` / `resource_attr` / `composite`). |
| GetCondition | sync | by id (`cond_…`) |
| UpdateCondition | async | mutable: `description`, `expression`, `params_schema`, `enabled`. Immutable: `kind`, `id`. |
| DeleteCondition | async | RESTRICT pendant references из `access_binding_conditions` (см. iam-access-binding-condition FK contract). |
| ListConditions | sync | filter by `account_id` / `kind` / `enabled`. Pagination cursor. |
| **Evaluate** | sync | dry-run: `(condition_id, params, request_context) → allowed=bool, trace=[]`. Sandboxed CEL evaluator (no I/O). Покрывается e2e тестами Phase 3 §Conditions. |

## REST mapping (public mux)

| HTTP | Method |
|---|---|
| `POST /iam/v1/conditions` | CreateCondition |
| `GET /iam/v1/conditions/{id}` | GetCondition |
| `PATCH /iam/v1/conditions/{id}` | UpdateCondition |
| `DELETE /iam/v1/conditions/{id}` | DeleteCondition |
| `GET /iam/v1/conditions` | ListConditions |
| `POST /iam/v1/conditions/{id}:evaluate` | Evaluate |

## Notes

- CEL evaluator — `github.com/google/cel-go` (sandboxed: no `net`, no `os`, no `time.Now()` outside of provided context).
- `expression` parse-validate в `Create`/`Update` — failure → `InvalidArgument`.
- `params_schema` — JSON Schema (draft 2020-12); валидируется server-side при привязке condition к AccessBinding (Phase 3 §Conditions).
- Conditions глобальны по умолчанию (cluster-scope) либо account-scoped (`account_id` field). Per-binding-overlay живёт в `access_binding_conditions` (см. [[../resources/iam-access-binding-condition]]).

## See also

[[../resources/iam-condition]] [[../resources/iam-access-binding-condition]] [[../resources/iam-access-binding]] [[iam-authorize-service]] [[../KAC/KAC-127]]

#rpc #kacho-iam #iam #authz
