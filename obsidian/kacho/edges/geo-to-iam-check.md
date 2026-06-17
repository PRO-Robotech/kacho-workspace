---
title: "geo → iam: per-RPC OpenFGA Check (#82)"
aliases:
  - geo to iam check
  - geo authz check
category: edge
caller_repo: kacho-geo
callee_repo: kacho-iam
sync_async: sync
protocol: grpc-cluster-internal
status: in-progress
related_tickets:
  - "[[KAC/EPIC-geo-extraction]]"
tags:
  - edge
  - cross-service
  - kacho-geo
  - kacho-iam
  - authz
---

> [!note] New edge (эпик #82)
> Новый leaf-сервис `kacho-geo` обязан гейтить КАЖДЫЙ RPC обоих листенеров (public :9090 + internal :9091)
> через `InternalIAMService.Check` — internal НЕ освобождён (`security.md` authN+authZ-инвариант).

# geo → iam: per-RPC Check (#82)

**Caller**: `kacho-geo` (`internal/check/`-interceptor поверх corelib `authz`, parity с compute/vpc).
**Callee**: `kacho-iam.InternalIAMService.Check` (:9091).
**Protocol**: gRPC cluster-internal (direct dial, mTLS).
**Sync/Async**: **sync** (на каждом RPC, до handler'а).

## When invoked

- Public read: `RegionService.Get/List`, `ZoneService.Get/List` → **viewer-tier** (`system_viewer`-floor).
  Catalog-resources резолвятся в well-known FGA-object (как `system:catalog` в compute).
- Admin-CRUD (`InternalRegionService` / `InternalZoneService`, :9091) → **`system_admin`**.

## Error handling — fail-closed

| Result | gRPC code |
|---|---|
| allowed=true | (continue) |
| allowed=false | `PermissionDenied` |
| iam недоступен | `PermissionDenied "authorization service unavailable"` |
| no Principal / mTLS-провал | `PermissionDenied` / транспортный отказ |

## leaf-консумер

`kacho-geo` зовёт **только** iam (authz-Check) — больше ни от какого сервиса в runtime не зависит.
Это держит geo leaf'ом (как iam) и сохраняет ацикличность графа (`all → geo`, `geo → iam`).

## See also

[[compute-to-iam-check]] [[vpc-to-iam-check]] [[../rpc/geo-region-service]] [[../rpc/geo-zone-service]] [[../packages/corelib-authz]]

#edge #cross-service #kacho-geo #kacho-iam #authz
