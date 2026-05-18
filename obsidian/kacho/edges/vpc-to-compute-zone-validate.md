---
title: "vpc → compute: zone_id validation (KAC-15)"
aliases:
  - vpc to compute zone validate
category: edge
caller_repo: kacho-vpc
callee_repo: kacho-compute
sync_async: async
protocol: grpc-cluster-internal
status: active
related_tickets:
  - "[[KAC/KAC-94]]"
tags:
  - edge
  - cross-service
  - kacho-vpc
  - kacho-compute
  - geography
---

# vpc → compute: zone_id validation (KAC-15)

**Caller**: `kacho-vpc` (`internal/clients/compute_client.go`)
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

## See also

[[../packages/vpc-clients]] [[../packages/corelib-retry]]

#edge #cross-service #kacho-vpc #kacho-compute #geography
