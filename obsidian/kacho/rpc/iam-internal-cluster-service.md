---
title: InternalClusterService
aliases:
  - InternalClusterService (iam)
proto_file: kacho/cloud/iam/v1/internal_cluster_service.proto (planned)
category: rpc
backend: kacho-iam
backend_port: 9091
visibility: internal
domain: iam
related_resource: "[[resources/iam-cluster]]"
methods_count: 0
async_methods: 0
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - rpc
  - kacho-iam
  - iam
  - internal
---

# InternalClusterService (iam)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/internal_cluster_service.proto` (Phase 2+).
**Backend**: `kacho-iam:9091` (**internal-only**; workspace §запрет #6 — НЕ публиковать на external TLS endpoint).
**Visibility**: **internal** — будет зарегистрирован в `api-gateway/internal mux` под `/iam/v1/internal/cluster/...`.
**Status**: **Phase 1 — schema only** ([[../resources/iam-cluster]] + [[../resources/iam-cluster-admin-grant]] + [[../resources/iam-cluster-break-glass-grant]] table-rows + bootstrap-seed). RPC handlers — Phase 2 (cluster-admin enforcement) + Phase 7 (break-glass flow).

## Planned methods (Phase 2 + Phase 7)

| Method | Phase | Sync/Async | Note |
|---|---|---|---|
| Get | 2 | sync | get cluster singleton |
| GrantAdmin | 2 | async | INSERT cluster_admin_grant + fga_outbox |
| RevokeAdmin | 2 | async | UPDATE granted_until=now + fga_outbox |
| ListAdmins | 2 | sync | active permanent admins |
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

[[../resources/iam-cluster]] [[../resources/iam-cluster-admin-grant]] [[../resources/iam-cluster-break-glass-grant]] [[../packages/iam-seed]] [[../KAC/KAC-127]]

#rpc #kacho-iam #iam #internal
