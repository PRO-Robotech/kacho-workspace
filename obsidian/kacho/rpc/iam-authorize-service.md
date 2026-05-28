---
title: AuthorizeService
aliases:
  - AuthorizeService (iam)
  - FGA Check
proto_file: kacho/cloud/iam/v1/authorize_service.proto
category: rpc
backend: kacho-iam
backend_port: 9090
visibility: public
domain: iam
related_resource: "[[resources/iam-access-binding]]"
methods_count: 5
async_methods: 0
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - rpc
  - kacho-iam
  - iam
  - fga
  - authz
---

# AuthorizeService (iam)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/authorize_service.proto` (Phase 3).
**Backend**: `kacho-iam:9090` (public mux + cluster-internal listener для api-gateway).
**Visibility**: **public** — per-RPC authorization-gate; consumers: api-gateway interceptor, vpc/compute List handlers, kacho-ui visibility filters.
**Status**: **Phase 3 planned**. Тонкая обёртка над OpenFGA REBAC API (Zanzibar Check + Expand) с Conditions-overlay + OPA cluster-deny gate.

## Methods (Phase 3, sync)

| Method | Description |
|---|---|
| Check | single-tuple boolean: `(user, relation, object) → allowed=bool`. SLO p95 ≤20ms (Phase 3 DoD). |
| BatchCheck | до 100 tuples в одном RPC (api-gateway batches per-request). Returns `[]CheckResult`. |
| ListObjects | "which `object_type:*` does `user` have `relation` to?" Возвращает strict-permission-ID set. Since KAC-215 (RBAC v2 / W2) response carries explicit `bool wildcard_grant` field — when true the caller MUST skip the WHERE-IN filter and return all rows; `resource_ids` empty in that case. p95 ≤100ms. |
| ListSubjects | "which users have `relation` to `object`?" — admin/UI permission diff. |
| ExpandRelations | Zanzibar-tree expand для debug/UI — рекурсивно разворачивает usersets. |

## Request flow (Check)

1. Extract caller identity (`user:usr_xxx` или `service_account:sva_xxx`) из DPoP-bound JWT claims.
2. Resolve relevant `AccessBindingCondition` (CEL params) + `JITEligibility` activation state.
3. Forward to OpenFGA `Check` API ([[../edges/iam-to-openfga-check]]).
4. OPA cluster-deny gate ([[../edges/iam-to-opa]]) — fail-closed override (org-wide policy / break-glass override).
5. Cache result (5s TTL) keyed on `(user, relation, object, condition_hash)`.

## REST mapping (public mux, Phase 3)

| HTTP | Method |
|---|---|
| `POST /iam/v1/authorize:check` | Check |
| `POST /iam/v1/authorize:batchCheck` | BatchCheck |
| `POST /iam/v1/authorize:listObjects` | ListObjects |
| `POST /iam/v1/authorize:listSubjects` | ListSubjects |
| `POST /iam/v1/authorize:expand` | ExpandRelations |

## Errors

- `PermissionDenied` — `allowed=false` (NB: Check returns boolean; PD only for caller-not-allowed-to-Check).
- `Unavailable` — OpenFGA / OPA недоступен → fail-closed для мутаций, fail-open behind flag для read.
- `InvalidArgument` — malformed tuple.

## Notes

- DPoP / mTLS-bound JWT verify происходит на api-gateway middleware ([[../packages/api-gateway-middleware-dpop]] + [[../packages/api-gateway-middleware-authz]]) до этого RPC.
- Write-path (tuple sync) — НЕ здесь, а через `InternalAuthorizeService.WriteTuples` ([[iam-internal-authorize-service]]).
- ListObjects pagination cursor opaque, signed → защита от tuple-store enumeration.

## See also

[[iam-internal-authorize-service]] [[iam-conditions-service]] [[../resources/iam-access-binding]] [[../resources/iam-access-binding-condition]] [[../edges/api-gateway-to-iam-authorize]] [[../edges/iam-to-openfga-check]] [[../edges/iam-to-opa]] [[../KAC/KAC-127]]

#rpc #kacho-iam #iam #fga #authz
