---
title: "vpc → compute: zone_id validation (KAC-15)"
aliases:
  - vpc to compute zone validate
category: edge
caller_repo: kacho-vpc
callee_repo: kacho-compute
sync_async: async
protocol: grpc-cluster-internal
status: deprecated
related_tickets:
  - "[[KAC/KAC-94]]"
  - "[[KAC/EPIC-geo-extraction]]"
tags:
  - edge
  - cross-service
  - kacho-vpc
  - kacho-compute
  - geography
  - deprecated
---

> [!warning] Superseded by [[vpc-to-geo-zone-validate]] (эпик #82)
> Geography вынесена из `kacho-compute` в leaf-сервис `kacho-geo`. vpc больше не зовёт compute
> «ради zone» — валидация теперь `vpc → geo` (`geo.v1.ZoneService.Get`). Ложное ребро `vpc→compute`
> удалено; `compute_client.go` `GetZone`/`ListZones` заменены на `geo_client.go`.

# vpc → compute: zone_id validation (KAC-15) — SUPERSEDED

**Caller**: `kacho-vpc` (`internal/clients/compute_client.go`) — *удалён, см. [[vpc-to-geo-zone-validate]]*
**Callee**: `kacho-compute` (`compute.v1.ZoneService.Get`)
**Protocol**: gRPC cluster-internal
**Sync/Async**: async (внутри Operation worker'а)

## When invoked

- `Subnet.Create` — валидировать `zone_id` (после переноса Geography в compute, KAC-15).
- `Subnet.Relocate` — cross-zone move.
- `AddressPool.Create` — pool ассоциирован с zone (если zonal).

## Direction reversal (KAC-15)

**Раньше** было обратно: `kacho-compute → kacho-vpc` (compute проксировал zones из vpc). После KAC-15 владелец Geography — compute, и ребро развёрнуто. Mirror-таблица `compute.zones` в kacho-compute была seeded из vpc до миграции; убрана (см. CLAUDE.md §«Карта владельцев доменов»).

## Error handling

| Result | gRPC code |
|---|---|
| zone OK | (continue) |
| zone not found | `InvalidArgument "zone_id: zone <id> not found"` |
| compute недоступен | `Unavailable "zone check: <err>"` (retry) |

## History

- **2026-06-17** (эпик #82, [[KAC/EPIC-geo-extraction]]): Geography вынесена в `kacho-geo`; это ребро
  удалено, заменено на [[vpc-to-geo-zone-validate]] (`vpc → geo`). vpc больше не зависит от compute.
- 2026-… (KAC-15): Geography перенесена vpc → compute, ребро развёрнуто на `vpc → compute`.

## See also

[[vpc-to-geo-zone-validate]] (преемник) [[../packages/vpc-clients]] [[../packages/corelib-retry]]

#edge #cross-service #kacho-vpc #kacho-compute #geography #deprecated
