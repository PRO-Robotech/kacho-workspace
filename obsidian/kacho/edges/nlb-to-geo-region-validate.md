---
title: "nlb → geo: Region validation (#82)"
aliases:
  - nlb to geo region validate
category: edge
caller_repo: kacho-nlb
callee_repo: kacho-geo
sync_async: sync
protocol: grpc-cluster-internal
status: active
related_tickets:
  - "[[KAC/EPIC-geo-extraction]]"
tags:
  - edge
  - cross-service
  - kacho-nlb
  - kacho-geo
  - region
---

> [!note] Landed (сверено 2026-08-05, дерево `96b2879a`): клиент в дереве — `services/nlb/internal/clients/geo/{region_client.go,zone_client.go,zone_region_client.go}`.
> Статус `in-progress` снят. Связь «зона → её регион» берётся **резолвом у владельца**, а не
> разбором имени: строковая деривация запрещена директивой владельца (она молча возвращает
> пустую строку на ресурсе без зоны и превращает проверку когерентности в тождественно
> истинную).

> [!note] Replaces [[nlb-to-compute-region-validation]] (эпик #82)
> Geography вынесена в leaf-сервис `kacho-geo`; nlb валидирует `region_id` напрямую в geo.

# nlb → geo: Region validation (#82)

**Caller**: `kacho-nlb` (`internal/clients/geo/region_client.go`; заменил снятый клиент региона в каталоге compute —
LoadBalancer.Create + TargetGroup.Create handlers).
**Callee**: `kacho-geo` (`geo.v1.RegionService.Get`).
**Protocol**: gRPC cluster-internal (direct dial, mTLS).
**Sync/Async**: **sync** на request-path (soft precheck до `ops.Insert`).

## When invoked

- `LoadBalancer.Create` / `TargetGroup.Create`: проверка `region_id` существует.
- `NLB.AttachTargetGroup`: same-region check (LB.region_id == TG.region_id — DB CHECK; sync precheck даёт UX-friendly error).

## Cache

**Нет кэша** — stateless pass-through через `retry.OnUnavailable` (вводить кэш — вне scope extract'а #82).
Прежний кэш с коротким сроком годности удалён вместе с тем клиентом (координата снятого файла здесь намеренно не воспроизводится: в обратных кавычках она читается как утверждение о дереве).

## Error handling

| Result | gRPC code | Note |
|---|---|---|
| region OK | (continue) | |
| region not found | `InvalidArgument "region_id <id> not found"` | geo NotFound → InvalidArgument |
| geo недоступен | `Unavailable` | fail-closed на request-path |

## See also

[[../rpc/geo-region-service]] [[../resources/nlb-load-balancer]] [[../resources/nlb-target-group]] [[nlb-to-compute-instance-resolve]]

#edge #cross-service #kacho-nlb #kacho-geo #region
