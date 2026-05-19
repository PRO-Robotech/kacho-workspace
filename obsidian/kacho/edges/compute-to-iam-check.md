---
title: "compute → iam: per-RPC OpenFGA Check (E3)"
aliases:
  - compute to iam check
  - compute authz check
category: edge
caller_repo: kacho-compute
callee_repo: kacho-iam
sync_async: sync
protocol: grpc-cluster-internal
status: active
related_tickets:
  - "[[KAC-104]]"
  - "[[KAC-108]]"
tags:
  - edge
  - kacho-compute
  - kacho-iam
  - cross-service
  - authz
  - e3
---

> [!success] Active since 2026-05-17 (KAC-108 E3, kacho-compute PR#23)
> kacho-compute на КАЖДОМ публичном RPC синхронно вызывает
> `kacho-iam.InternalIAMService.Check` через `internal/check/`-interceptor.

# compute → iam: per-RPC Check (E3)

**Caller:** `kacho-compute` (`internal/check/` — gRPC unary+stream interceptor поверх corelib `authz`).
**Callee:** `kacho-iam.InternalIAMService.Check` (port 9091).
**Protocol:** gRPC cluster-internal (direct dial).
**Sync/Async:** **sync** (на каждом public RPC, до handler'а).

## When invoked

- Все публичные RPC: DiskService, ImageService, SnapshotService, InstanceService
  (lifecycle-heavy: Start/Stop/Restart/Attach*/Detach*/AddOneToOneNat/…),
  DiskTypeService, ZoneService, RegionService, OperationService.Get/Cancel
  (40+ RPC, см. [[../packages/compute-internal-check]] permission_map).
- `Internal*` RPC — bypass (admin :9091 listener).

## Object types

`compute_disk`, `compute_image`, `compute_snapshot`, `compute_instance`,
`compute_operation`, `system`, `project`.

## Особенность: catalog-resources

`DiskType.{Get,List}`, `Zone.{Get,List}`, `Region.{Get,List}` — глобальные
read-only справочники без `project_id` в request'е. Резолвятся в один
well-known FGA-object `system:catalog`. E3-модель выдаёт всем authenticated
principal'ам `viewer on system:catalog` implicit'но (см. acceptance §4).
Это эквивалент `Public=true`, но через audit-trail в kacho-iam.

## Cache + revoke target

Та же схема, что [[vpc-to-iam-check]]: positive TTL=5s, push-invalidate через
`pg_notify('kacho_iam_subjects', subject_id)` (НЕ wired в MVP — KAC-108
follow-up), worst-case revoke ≤ 10s.

## Error handling — fail-closed

| Result         | gRPC code                                              |
| -------------- | ------------------------------------------------------ |
| allowed=true   | (continue)                                             |
| allowed=false  | `PermissionDenied`                                     |
| iam недоступен | `PermissionDenied "authorization service unavailable"` |
| no Principal   | `PermissionDenied`                                     |
| Unmapped RPC   | `PermissionDenied (rpc not mapped)`                    |
| Internal* RPC  | bypass                                                 |

## Configuration

```bash
KACHO_COMPUTE_AUTHZ_IAM_GRPC_ADDR=kacho-iam.kacho.svc.cluster.local:9091
KACHO_COMPUTE_AUTHZ_IAM_TLS=false
KACHO_COMPUTE_AUTHZ_BREAKGLASS=false
```

Если адрес пуст и breakglass=false → interceptor НЕ навешивается (dev mode).

## See also

[[../packages/compute-internal-check]] [[../packages/corelib-authz]]
[[iam-to-openfga-check]] [[vpc-to-iam-check]] [[../KAC/KAC-108]] [[../KAC/KAC-122]] (authz-deny newman suite)

#edge #kacho-compute #kacho-iam #cross-service #authz #e3
