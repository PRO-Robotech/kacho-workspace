---
title: "nlb → compute: Region validation"
aliases:
  - nlb region validate
category: edge
caller_repo: kacho-nlb
callee_repo: kacho-compute
sync_async: sync
protocol: grpc-cluster-internal
status: deprecated
related_tickets:
  - "[[KAC-141]]"
  - "[[KAC-151]]"
  - "[[KAC/EPIC-geo-extraction]]"
tags:
  - edge
  - kacho-nlb
  - kacho-compute
  - cross-service
  - region
  - deprecated
---

> [!warning] Superseded by [[nlb-to-geo-region-validate]] (эпик #82)
> Geography вынесена из `kacho-compute` в leaf-сервис `kacho-geo`. region-валидация теперь
> `nlb → geo` (`geo.v1.RegionService.Get`). Ложное ребро `nlb→compute (region)` удалено;
> `clients/compute/region_client.go` заменён на `clients/geo/region_client.go`. Ребро
> `nlb → compute` остаётся **только** для Instance-таргетов (см. [[nlb-to-compute-instance-resolve]]).

# nlb → compute: Region validation — SUPERSEDED

**Caller**: `kacho-nlb` (`internal/clients/compute/region_client.go` — *удалён*; LoadBalancer.Create + TargetGroup.Create handlers)
**Callee**: `kacho-compute.RegionService.Get` (Geography domain — KAC-15)
**Protocol**: gRPC cluster-internal
**Sync/Async**: **sync** на request-path (soft precheck до `ops.Insert`)

## When invoked

- `LoadBalancer.Create` handler: проверка `region_id` существует. Mismatch → `InvalidArgument "region_id <id> not found"`.
- `TargetGroup.Create` handler: то же.
- `NLB.AttachTargetGroup` handler: same-region check (LB.region_id == TG.region_id — DB CHECK, но sync precheck даёт UX-friendly error до DB-fail).

## Cache

TTL+LRU 60s (regions редко меняются), реализован в `regions_cache.go` (pattern из kacho-vpc/clients/compute_client.go).

## Error handling

| Result | gRPC code | Note |
|---|---|---|
| region OK | (continue) | cache positive 60s |
| region not found | `InvalidArgument "region_id ..."` | NotFound маппинг на InvalidArgument (kacho-конвенция) |
| compute недоступен | `Unavailable` | fail-closed на request-path |

## History

- **2026-06-17** (эпик #82, [[KAC/EPIC-geo-extraction]]): Geography вынесена в `kacho-geo`; это ребро
  удалено, заменено на [[nlb-to-geo-region-validate]] (`nlb → geo`). `nlb → compute` сохраняется только
  для Instance-таргетов ([[nlb-to-compute-instance-resolve]]).
- 2026-05-24 (KAC-141, kacho-nlb PR#9): edge initial — nlb валидировал region через compute.

## See also

[[nlb-to-geo-region-validate]] (преемник) [[../rpc/geo-region-service]] [[../resources/nlb-load-balancer]] [[../resources/nlb-target-group]] [[nlb-to-compute-instance-resolve]]

#edge #kacho-nlb #kacho-compute #cross-service #region #deprecated
