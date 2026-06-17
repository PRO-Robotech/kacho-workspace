---
title: "vpc → geo: zone_id validation (#82)"
aliases:
  - vpc to geo zone validate
category: edge
caller_repo: kacho-vpc
callee_repo: kacho-geo
sync_async: async
protocol: grpc-cluster-internal
status: in-progress
related_tickets:
  - "[[KAC/EPIC-geo-extraction]]"
tags:
  - edge
  - cross-service
  - kacho-vpc
  - kacho-geo
  - geography
---

> [!note] Replaces [[vpc-to-compute-zone-validate]] (эпик #82)
> Geography вынесена в leaf-сервис `kacho-geo`; vpc валидирует `zone_id` напрямую в geo.

# vpc → geo: zone_id validation (#82)

**Caller**: `kacho-vpc` (`internal/clients/geo_client.go` — заменяет `GetZone`/`ListZones` из `compute_client.go`).
**Callee**: `kacho-geo` (`geo.v1.ZoneService.Get`).
**Protocol**: gRPC cluster-internal (direct dial, mTLS).
**Sync/Async**: async (внутри Operation worker'а Subnet.Create) / sync precheck для AddressPool.

## When invoked

- `Subnet.Create` — валидировать `zone_id` (зона существует в geo).
- `AddressPool.Create` — `address_pools.zone_id` (zonal pool); `zone_id=""` (global default) → без geo-вызова.

## Error handling

| Result | gRPC code |
|---|---|
| zone OK | (continue) |
| zone not found (geo NotFound) | `InvalidArgument "zone_id: zone <id> not found"` |
| geo недоступен | `Unavailable` (fail-closed для мутаций, `data-integrity.md`) |

Dangling-ref на чтении: `Subnet.Get`/`AddressPool.Get` существующего ресурса с удалённой зоной → OK
(zone не перепроверяется на read).

## See also

[[../packages/vpc-clients]] [[compute-to-geo-zone-validate]] [[../rpc/geo-zone-service]] [[../packages/corelib-retry]]

#edge #cross-service #kacho-vpc #kacho-geo #geography
