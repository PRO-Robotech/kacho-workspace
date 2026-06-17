---
title: "nlb → geo: Region validation (#82)"
aliases:
  - nlb to geo region validate
category: edge
caller_repo: kacho-nlb
callee_repo: kacho-geo
sync_async: sync
protocol: grpc-cluster-internal
status: in-progress
related_tickets:
  - "[[KAC/EPIC-geo-extraction]]"
tags:
  - edge
  - cross-service
  - kacho-nlb
  - kacho-geo
  - region
---

> [!note] Replaces [[nlb-to-compute-region-validation]] (эпик #82)
> Geography вынесена в leaf-сервис `kacho-geo`; nlb валидирует `region_id` напрямую в geo.

# nlb → geo: Region validation (#82)

**Caller**: `kacho-nlb` (`internal/clients/geo/region_client.go` — заменяет `clients/compute/region_client.go`;
LoadBalancer.Create + TargetGroup.Create handlers).
**Callee**: `kacho-geo` (`geo.v1.RegionService.Get`).
**Protocol**: gRPC cluster-internal (direct dial, mTLS).
**Sync/Async**: **sync** на request-path (soft precheck до `ops.Insert`).

## When invoked

- `LoadBalancer.Create` / `TargetGroup.Create`: проверка `region_id` существует.
- `NLB.AttachTargetGroup`: same-region check (LB.region_id == TG.region_id — DB CHECK; sync precheck даёт UX-friendly error).

## Cache

**Нет кэша** — stateless pass-through через `retry.OnUnavailable` (вводить кэш — вне scope extract'а #82).
Прежний 60s TTL+LRU удалён вместе с `compute/region_client.go`.

## Error handling

| Result | gRPC code | Note |
|---|---|---|
| region OK | (continue) | |
| region not found | `InvalidArgument "region_id <id> not found"` | geo NotFound → InvalidArgument |
| geo недоступен | `Unavailable` | fail-closed на request-path |

## See also

[[../rpc/geo-region-service]] [[../resources/nlb-load-balancer]] [[../resources/nlb-target-group]] [[nlb-to-compute-instance-resolve]]

#edge #cross-service #kacho-nlb #kacho-geo #region
