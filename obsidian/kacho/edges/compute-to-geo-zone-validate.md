---
title: "compute → geo: Instance.zone_id validation (#82)"
aliases:
  - compute to geo zone validate
category: edge
caller_repo: kacho-compute
callee_repo: kacho-geo
sync_async: async
protocol: grpc-cluster-internal
status: active
related_tickets:
  - "[[KAC/EPIC-geo-extraction]]"
tags:
  - edge
  - cross-service
  - kacho-compute
  - kacho-geo
  - geography
verified_against: "ветка release/compute-production-api @ 451a56cd, сверено 2026-08-13"
---

> [!note] Landed: клиент в дереве — `services/compute/internal/clients/geo_client.go`.
> Сверено 2026-08-13 на `451a56cd`: три вопроса владельцу Geography, не два.
>
> - `GetZone` — существование зоны машины;
> - `RegionOfZone` — авторитетный регион зоны; спрашивается ТОЛЬКО когда машина названа
>   группой размещения, чтобы не платить обращением к соседу на каждом создании;
> - `GetRegion` — существование региона у **региональной** группы размещения. Появился
>   2026-08-13 вместе с ресурсом группы: у регионального якоря зоны нет by construction,
>   и проверить его зональным вопросом нельзя.
>
> Регион НИКОГДА не выводится из имени зоны: имена произвольны, а строковая деривация
> молча отдаёт пустоту и превращает проверку когерентности в тождественно-истинную.
> Носитель, не отвечающий на вопрос о регионе, — **отказ в старте** компоненты, а не
> тихая деградация.
> Статус `in-progress` снят. Связь «зона → её регион» берётся **резолвом у владельца**, а не
> разбором имени: строковая деривация запрещена директивой владельца (она молча возвращает
> пустую строку на ресурсе без зоны и превращает проверку когерентности в тождественно
> истинную).

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
