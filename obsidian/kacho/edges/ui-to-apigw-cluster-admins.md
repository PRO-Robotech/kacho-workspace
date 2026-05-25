---
title: kacho-ui → kacho-api-gateway cluster-admins REST
caller_repo: kacho-ui
callee_repo: kacho-api-gateway
sync_async: mixed
protocol: REST/JSON
status: done
category: edge
related_rpc:
  - "[[rpc/iam-internal-cluster-service]]"
related_tickets:
  - "[[KAC-196]]"
tags:
  - edge
  - kacho-ui
  - kacho-api-gateway
  - internal
  - cross-service
---

# Edge: kacho-ui → kacho-api-gateway (cluster admins)

UI page `/system/cluster/admins` ([[../packages/iam-handler-internal-cluster]]) — REST вызовы на api-gateway internal mux, который проксирует к `InternalClusterService` в kacho-iam:9091 ([[../rpc/iam-internal-cluster-service]]).

## REST contract

| HTTP | RPC | Sync/Async | UI usage |
|---|---|---|---|
| `GET /iam/v1/internal/cluster` | `Get` | sync | (not currently used by UI; reserved) |
| `GET /iam/v1/internal/cluster/admins` | `ListAdmins` | sync | initial table load + invalidate after grant/revoke |
| `POST /iam/v1/internal/cluster/admins` body `{subjectType:"USER", subjectId}` | `GrantAdmin` | **async (Operation)** | GrantAdminModal submit → poll Operation → toast |
| `DELETE /iam/v1/internal/cluster/admins/{subjectId}` | `RevokeAdmin` | **async (Operation)** | Popconfirm submit → poll Operation → toast |

## Authorization

- **Gate**: api-gateway catalog (`required_relation: "admin"` D-11 computed alias `system_admin OR emergency_admin`).
- **Ordinary user** → HTTP 403; UI renders `<ErrorResult cluster-admins-forbidden>`.
- **Admin user** (S system_admin / emergency_admin) → 200.

## Error handling

- 200 + Operation `{done:false}` → poll → if `done:true` + `result.response` → success toast; if `done:true` + `result.error` → error toast с message из gRPC error.
- 400 InvalidArgument (e.g. `"User %s not found"`) → red toast.
- 403 PermissionDenied → forbidden page.
- 404 NotFound (Revoke на не-admin / уже-revoked — D-12) → toast `"User is not an active cluster admin"`.
- 409/412 FailedPrecondition (self/last-admin) → toast YC-style.

## Defense-in-depth

UI **also** disables Revoke button when:
- `row.subjectId === currentUserId` (D-5 self-revoke guard) — tooltip "Cannot revoke self"
- `admins.length === 1` (D-6 last-admin guard) — tooltip "Cannot revoke last admin"

Backend по-прежнему атомарно гардит — UI lock is UX, не безопасность.

## History

- **KAC-196 (2026-05-25)** — initial implementation. PRs: kacho-iam#70 (handler), kacho-api-gateway#44 (catalog+restmux), kacho-ui#59 (page+Playwright).

## See also

[[../rpc/iam-internal-cluster-service]] [[../packages/iam-handler-internal-cluster]] [[../packages/iam-apps-cluster-usecases]] [[../KAC/KAC-196]]

#edge #kacho-ui #kacho-api-gateway #internal #cross-service
