---
title: "api-gateway → compute (proxy)"
aliases:
  - apigw to compute
category: edge
caller_repo: kacho-api-gateway
callee_repo: kacho-compute
sync_async: sync
protocol: grpc-gateway
status: active
tags:
  - edge
  - cross-service
  - kacho-apigw
  - kacho-compute
---

# api-gateway → compute (proxy)

**Caller**: `kacho-api-gateway` (`internal/restmux/mux.go`)
**Callee**: `kacho-compute:9090` (public) + `kacho-compute:9091` (internal)
**Protocol**: grpc-gateway HandlerFromEndpoint

## Registered services (public)

| Proto service | REST префикс |
|---|---|
| `DiskService` | `/compute/v1/disks` |
| `ImageService` | `/compute/v1/images` |
| `SnapshotService` | `/compute/v1/snapshots` |
| `InstanceService` | `/compute/v1/instances` |
| `DiskTypeService` | `/compute/v1/diskTypes` |
| `ZoneService` | `/compute/v1/zones` (после KAC-15 — owner = compute) |
| `RegionService` | `/compute/v1/regions` |

(Backend addr `computeAddr` = `compute.kacho.svc.cluster.local:9090`.)

## Registered services (internal — cluster-internal only)

| Proto service | Notes |
|---|---|
| `InternalDiskTypeService` | admin DiskType CRUD |
| `InternalZoneService` | admin Zone CRUD (KAC-15) |
| `InternalRegionService` | admin Region CRUD (KAC-15) |

См. [[apigw-internal-vs-tls]] про разделение.

## Identity forwarding (production auth contract)

Как [[apigw-to-vpc]]: gateway форвардит identity **только** как `x-kacho-principal-*`
(trust-gated в operations-carrier `UnaryTrustedPrincipalExtract`), не legacy
`x-kacho-project-id`. compute `TenantInterceptor` (production) обязан признавать
forwarded-принципал не-anonymous; per-object `authzIntr` (FGA Check) + listFilter — реальный гейт.

## History

- **2026-07-10** — тот же production tenant-guard баг, что и в vpc: guard считал
  `IsAnonymous` только по `x-kacho-project-id` → отвергал аутентиф.+авториз. compute-запрос
  (`403 "AuthN required (production mode)"`) до authzIntr. Фикс: guard принимает
  `x-kacho-principal-*` (mirror kacho-iam `authzguard.IsAnonymous`). `kacho-compute#103` →
  PR `kacho-compute#104` (merged, image `main-1678f62c`). Детали: [[apigw-to-vpc]].

## See also

[[../packages/apigw-restmux]] [[apigw-to-vpc]]

#edge #cross-service #kacho-apigw #kacho-compute
