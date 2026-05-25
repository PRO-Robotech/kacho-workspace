---
title: iam handler internal_cluster
repo: kacho-iam
layer: handler
category: packages
related_rpc:
  - "[[rpc/iam-internal-cluster-service]]"
related_tickets:
  - "[[KAC-196]]"
tags:
  - packages
  - kacho-iam
  - handler
  - internal
---

# `kacho-iam/internal/apps/kacho/api/cluster/`

Thin gRPC handler + 4 use-case files для `InternalClusterService` ([[../rpc/iam-internal-cluster-service]]). Зарегистрирован ТОЛЬКО на internal listener `:9091` ([[../KAC/KAC-196]] D-10, workspace §запрет #6).

## Layout (evgeniy §2 use-case pattern)

| File | Содержимое |
|---|---|
| `handler.go` | `Handler` struct (4 use-case полей) + gRPC методы `parseReq → uc.Run → buildResp` (без бизнес-логики) |
| `ports.go` | port-interfaces: `ClusterReader`, `GrantReader`, `GrantWriter`, `UserLookup`, `FGAOutboxEmitter`, `AuditOutboxEmitter`, `Transactor`, `OperationsWriter` |
| `get.go` | `GetClusterUseCase.Run(ctx) (domain.Cluster, error)` — reader-TX, SELECT singleton |
| `grant_admin.go` | `GrantAdminUseCase.Run(ctx, subjectType, subjectID) (*Operation, error)` — Validate / userExists / writer.Grant (+ Reactivate если revoked) / EmitWriteTx / audit / operations.Enqueue |
| `revoke_admin.go` | `RevokeAdminUseCase.Run(ctx, subjectID) (*Operation, error)` — Validate / writer.Revoke (atomic CAS) / EmitDeleteTx / audit / operations.Enqueue; sentinel→gRPC (ErrSelfRevoke/ErrLastAdmin → FailedPrecondition, ErrNotFound → NotFound) |
| `list_admins.go` | `ListAdminsUseCase.Run(ctx) ([]ClusterAdminEntry, error)` — reader-TX, JOIN users |
| `helpers.go` | `subjectIDRe` regex helper |

## Exported types

- `Handler` — gRPC server implementation (4 RPC methods).
- `Deps` — struct DI container для wiring (used in `cmd/kacho-iam/wiring.go`).

## Imports

- `domain` — `Cluster`, `ClusterAdminGrant`, `SubjectID`
- `service` — `Tx`, `FGATuple`, `Transactor`
- `iamv1` — proto stubs (kacho-proto gen)
- `operation` — Operation envelope
- `errs` — sentinels (`ErrNotFound`, `ErrSelfRevoke`, `ErrLastAdmin`, `ErrFailedPrecondition`)

## Imported by

- `cmd/kacho-iam/wiring.go` — `cluster.NewHandler(Deps{...})`
- `cmd/kacho-iam/grpc_register.go` — `iamv1.RegisterInternalClusterServiceServer(srv, clusterHandler)` на internal listener

## See also

[[iam-apps-cluster-usecases]] [[../rpc/iam-internal-cluster-service]] [[../resources/iam-cluster-admin-grant]] [[../KAC/KAC-196]]

#packages #kacho-iam #handler #internal
