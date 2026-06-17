---
title: "compute → geo: Instance.zone_id validation (#82)"
aliases:
  - compute to geo zone validate
category: edge
caller_repo: kacho-compute
callee_repo: kacho-geo
sync_async: async
protocol: grpc-cluster-internal
status: in-progress
related_tickets:
  - "[[KAC/EPIC-geo-extraction]]"
tags:
  - edge
  - cross-service
  - kacho-compute
  - kacho-geo
  - geography
---

> [!note] New edge (эпик #82)
> До extract'а compute «владел» зонами и валидировал `Instance.zone_id` по собственной таблице
> `kacho_compute.zones`. После выноса Geography в `kacho-geo` compute стал обычным consumer'ом:
> валидация — peer-вызовом в geo, локальная таблица удалена.

# compute → geo: Instance.zone_id validation (#82)

**Caller**: `kacho-compute` (`internal/clients/geo_client.go`; прежние `ZoneRepoSource`/`ZoneRegistry`
по локальной таблице удалены).
**Callee**: `kacho-geo` (`geo.v1.ZoneService.Get`).
**Protocol**: gRPC cluster-internal (direct dial, mTLS).
**Sync/Async**: async (внутри Operation worker'а `Instance.Create`).

## When invoked

- `Instance.Create` — валидировать `zone_id` (зона существует в geo). `disks.zone_id` — аналогично.

## Error handling

| Result | gRPC code |
|---|---|
| zone OK | (continue) |
| zone not found (geo NotFound) | `InvalidArgument "zone_id: zone <id> not found"` |
| geo недоступен | `Unavailable` (fail-closed на мутации) |

Dangling-ref на чтении: `Instance.Get` существующего инстанса с удалённой зоной → OK
(zone не перепроверяется на read; id сохранён миграцией #82).

## See also

[[vpc-to-geo-zone-validate]] [[../rpc/geo-zone-service]] [[../packages/proto-geo]] [[compute-to-vpc-nic-validate]]

#edge #cross-service #kacho-compute #kacho-geo #geography
