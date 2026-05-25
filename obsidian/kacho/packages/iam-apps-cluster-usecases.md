---
title: iam apps cluster use-cases
repo: kacho-iam
layer: usecase
category: packages
related_rpc:
  - "[[rpc/iam-internal-cluster-service]]"
related_tickets:
  - "[[KAC-196]]"
tags:
  - packages
  - kacho-iam
  - usecase
  - internal
---

# `kacho-iam` cluster use-cases (KAC-196)

4 use-cases для InternalClusterService — реализованы по evgeniy §2 (use-case per file) + §6 (Reader/Writer split):

## Use-cases

| Use-case | Sync/Async | Reader/Writer | Guards |
|---|---|---|---|
| `GetClusterUseCase` | sync | Reader (ClusterReader) | — |
| `GrantAdminUseCase` | **async** (Operation envelope) | Writer (GrantWriter.Grant + Reactivate) | D-2 USER only, D-4 idempotent (ON CONFLICT + Reactivate), D-9 user exists |
| `RevokeAdminUseCase` | **async** | Writer (GrantWriter.Revoke) | D-5 self / D-6 last / D-12 active-only (атомарный CAS) |
| `ListAdminsUseCase` | sync | Reader (GrantReader.ListActive) | — |

## Port-interfaces (ports.go)

| Port | Implementation |
|---|---|
| `ClusterReader` | `pg.ClusterReader` |
| `GrantReader` | `pg.ClusterAdminGrantReader` |
| `GrantWriter` | `pg.ClusterAdminGrantWriter` (Grant + Revoke + Reactivate) |
| `UserLookup` | `pg.UserExistenceChecker` |
| `FGAOutboxEmitter` | `pg.FGAOutboxEmitter` (existing) |
| `AuditOutboxEmitter` | `services.auditOutbox` (existing) |
| `Transactor` | `services.txr` (existing) |
| `OperationsWriter` | `services.operationsWriter` (existing) |

## Atomic-emit-in-TX contract (godzila §16)

GrantAdmin/RevokeAdmin делают всё в одной DB-TX:
1. cluster_admin_grants INSERT/UPDATE
2. fga_outbox INSERT (`fga.tuple.write` / `fga.tuple.delete` для `system_admin@cluster:cluster_kacho_root#user:<id>`)
3. audit_outbox INSERT (`cluster_admin_granted` / `cluster_admin_revoked`)
4. operations INSERT (Enqueue с metadata)

→ Все commit'ятся together; OpenFGA tuple eventually pushed FGAOutboxDrainer.

## D-13 OpenFGA outage

DB row persists (TX независим от OpenFGA reachability). Drainer retries → eventually tuple pushed. Если drainer fails окончательно — Operation становится terminal `error.code=Unavailable`. Acceptance §6.17.

## See also

[[iam-handler-internal-cluster]] [[../rpc/iam-internal-cluster-service]] [[../resources/iam-cluster-admin-grant]] [[../KAC/KAC-196]]

#packages #kacho-iam #usecase #internal
