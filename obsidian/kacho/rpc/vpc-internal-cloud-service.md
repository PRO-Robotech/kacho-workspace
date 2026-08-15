---
title: InternalCloudService (removed)
aliases:
  - InternalCloudService (vpc)
proto_file: ""
category: rpc
backend: kacho-vpc
backend_port: 9091
visibility: internal
domain: vpc
status: deprecated
related_resource: "[[resources/vpc-addresspool]]"
methods_count: 0
async_methods: 0
tags:
  - rpc
  - kacho-vpc
  - internal
  - deprecated
---

# InternalCloudService (vpc) — REMOVED

> [!warning] Удалён целиком в KAC-266
> Сервис управлял cloud-level pool-selector'ом (`SetPoolSelector` / `GetPoolSelector` /
> `UnsetPoolSelector`) — шаг `cloud_pool_selector` в IPAM resolution chain. В [[KAC-266]] этот
> шаг убран: cascade сведён к трём шагам (`network_default` → `zone_default` → `global_default`).
> RPC + proto-сервис `InternalCloudService` + REST-маршруты `/vpc/v1/clouds/{cloud_id}/poolSelector`
> удалены. Заметка оставлена как tombstone, чтобы wikilinks не ломались.

Прежде (до KAC-266) — internal admin-сервис: привязка AddressPool selector'а к Cloud →
per-Cloud default pool в resolution chain. См. [[vpc-internal-address-pool-service]] (KEEP:
`BindAsNetworkDefault` / `UnbindNetworkDefault`).

## See also

[[vpc-internal-address-pool-service]] [[../resources/vpc-addresspool]] [[../KAC/KAC-266]]

#rpc #kacho-vpc #internal #deprecated
