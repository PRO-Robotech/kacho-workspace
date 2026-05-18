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

## See also

[[../packages/apigw-restmux]] [[apigw-to-vpc]]

#edge #cross-service #kacho-apigw #kacho-compute
