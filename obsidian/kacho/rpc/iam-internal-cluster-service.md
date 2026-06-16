---
title: InternalClusterService
aliases:
  - InternalClusterService (iam)
proto_file: kacho/cloud/iam/v1/internal_cluster_service.proto
category: rpc
backend: kacho-iam
backend_port: 9091
visibility: internal
domain: iam
related_resource: "[[resources/iam-cluster]]"
methods_count: 4
async_methods: 2
status: done
related_tickets:
  - "[[KAC-127]]"
  - "[[KAC-196]]"
tags:
  - rpc
  - kacho-iam
  - iam
  - internal
---

# InternalClusterService (iam)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/internal_cluster_service.proto` (KAC-196).
**Backend**: `kacho-iam:9091` (**internal-only**; workspace §запрет #6 — НЕ публиковать на external TLS endpoint).
**Visibility**: **internal** — зарегистрирован в `api-gateway/internal mux` под `/iam/v1/internal/cluster/...` (KAC-196 PR #44).
**Status**: **Phase 2 — DONE** (cluster-admin enforcement, [[../KAC/KAC-196]]). Phase 7 (break-glass `RequestBreakGlass` / `Approve/Deny/RevokeBreakGlass`) — planned.

## Methods (Phase 2 DONE + Phase 7 planned)

| Method | Phase | Sync/Async | Status | Note |
|---|---|---|---|---|
| Get | 2 | sync | **done** | get cluster singleton |
| GrantAdmin | 2 | async (Operation) | **done** | INSERT/Reactivate cluster_admin_grants + fga_outbox + **audit_outbox `iam.cluster_admin.granted`** (sub-phase 5.2, atomic in tx; no-op repeat emits nothing) |
| RevokeAdmin | 2 | async (Operation) | **done** | atomic CAS UPDATE granted_until=now (D-5 self / D-6 last / D-12 not-active) + **audit_outbox `iam.cluster_admin.revoked`** (sub-phase 5.2, atomic in tx) |
| ListAdmins | 2 | sync | **done** | active permanent admins (JOIN users for denormalised email/display_name) |
| RequestBreakGlass | 7 | async | INSERT cluster_break_glass_grant (state=AWAITING_APPROVAL_A) |
| ApproveBreakGlass | 7 | async | CAS UPDATE state-transitions |
| DenyBreakGlass | 7 | async | CAS UPDATE → DENIED |
| RevokeBreakGlass | 7 | async | CAS UPDATE → REVOKED |
| ListBreakGlass | 7 | sync | active break-glass grants |

## REST mapping (internal mux only)

| HTTP | Method | Phase |
|---|---|---|
| `GET /iam/v1/internal/cluster` | Get | 2 |
| `POST /iam/v1/internal/cluster/admins` | GrantAdmin | 2 |
| `DELETE /iam/v1/internal/cluster/admins/{subject_id}` | RevokeAdmin | 2 |
| `GET /iam/v1/internal/cluster/admins` | ListAdmins | 2 |
| `POST /iam/v1/internal/cluster/breakGlass:request` | RequestBreakGlass | 7 |
| `POST /iam/v1/internal/cluster/breakGlass/{id}:approve` | ApproveBreakGlass | 7 |
| `POST /iam/v1/internal/cluster/breakGlass/{id}:deny` | DenyBreakGlass | 7 |
| `POST /iam/v1/internal/cluster/breakGlass/{id}:revoke` | RevokeBreakGlass | 7 |
| `GET /iam/v1/internal/cluster/breakGlass` | ListBreakGlass | 7 |

## Notes (Phase 1)

- Phase 1 не реализует RPC; bootstrap-seed создаёт singleton row через [[../packages/iam-seed]] `bootstrap_admin.go`.
- Все методы — `Internal*` per workspace §запрет #6: cluster-admin enforcement — не tenant-facing.
- Break-glass требует 2-person approve: Phase 7 service-CHECK `approver_b ∉ {requested_by, approver_a}`.

## See also

[[../resources/iam-cluster]] [[../resources/iam-cluster-admin-grant]] [[../resources/iam-cluster-break-glass-grant]] [[../resources/iam-audit-outbox]] [[../packages/iam-seed]] [[../KAC/KAC-127]]

#rpc #kacho-iam #iam #internal
