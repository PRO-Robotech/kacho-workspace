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
status: experimental
tags:
  - rpc
  - kacho-iam
  - iam
  - authz
---

# ConditionsService (iam)

**Proto**: `proto/kacho/cloud/iam/v1/conditions_service.proto`. **Backend**: `kacho-iam:9090`.
**Visibility**: public — mounted on the api-gateway external mux and in the gRPC allowlist.

## Methods

| Method | Sync/Async | REST | Scope checked |
|---|---|---|---|
| `Get` | sync | `GET /iam/v1/conditions/{condition_id}` | `viewer` @ `iam_condition:<id>` |
| `List` | sync | `GET /iam/v1/conditions?projectId=…` | `viewer` @ `project:<projectId>` |
| `Create` | async | `POST /iam/v1/conditions` | `editor` @ `project:<projectId>` |
| `Update` | async | `PATCH /iam/v1/conditions/{condition_id}` | `editor` @ `iam_condition:<id>`, acr ≥ 2 |
| `Delete` | async | `DELETE /iam/v1/conditions/{condition_id}` | `editor` @ `iam_condition:<id>`, acr ≥ 2 |
| `Evaluate` | sync | `POST /iam/v1/conditions/{condition_id}:evaluate` | `viewer` @ `iam_condition:<id>` |

Scope field is **`projectId`** on `Create` and `List`. It was `folderId` — the one pre-redesign name left in the product — until the rename; a client following the platform convention sent `projectId`, the REST bridge dropped the unknown key, the required scope stayed empty and the gateway fail-closed on `project:*`.

## Reality check — what is NOT wired

> [!warning] The resource is reachable; the feature is not
> - `AccessBindingService.Create` declares `condition_id` / `builtin_condition` and **reads neither** — the generated getters have no callers. `Update` cannot set them either (`abMutableFields` = `deletion_protection`, `labels`).
> - `AccessBinding.condition_id` is typed `^cond_…` and FK'd to **`access_binding_conditions`** — a different table and id space from `conditions` (`^cnd…`). The two designs were never joined.
> - `access_binding_conditions` has **no production INSERT** anywhere; its only production reader is the refcount in `ConditionsRepo.CountReferences`, which is therefore structurally always 0.
> - `Evaluate` is a **substring matcher**, not CEL — `cel-go` is not a dependency. A free-form expression returns `ErrUnsupportedExpression`, which the use-case swallows into `200 {allowed:false}` — a silent deny presented as an evaluation.
> - The model declares six FGA conditions; only `mfa_fresh` is referenced by any relation, and no production writer ever attaches a condition to a tuple.
>
> Treat this service as a standalone CRUD surface until those joints exist.

## Notes

- Mutations return `Operation` with the iam op prefix **`iop`** (not `epd`).
- `Create` co-commits the `project` hierarchy pointer into `fga_outbox`; `Delete` retracts it. See [[../resources/iam-condition]] §Authorization.
- `name` and `project_id` are immutable after Create (rejected in `update_mask`).

## See also

[[../resources/iam-condition]] [[../resources/iam-access-binding-condition]] [[../resources/iam-access-binding]] [[iam-authorize-service]]

#rpc #kacho-iam #iam #authz
