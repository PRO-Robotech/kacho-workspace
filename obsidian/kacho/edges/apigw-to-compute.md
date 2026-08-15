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
verified_against: "координаты записки (REST-маршруты обоих listener'ов) сверены с деревом продукта 1653387b (2026-08-06); контракт форварда личности построчно не пересматривался"
---

# api-gateway → compute (proxy)

**Caller**: `kacho-api-gateway` (`internal/restmux/mux.go`)
**Callee**: `kacho-compute:9090` (public) + `kacho-compute:9091` (internal)
**Protocol**: grpc-gateway HandlerFromEndpoint

> [!warning] Пять из семи маршрутов больше не принадлежат compute (сверено 1653387b, 2026-08-06)
> Таблица перечисляла диски, образы, снимки, типы дисков, зоны и регионы как поверхность
> compute. Ни один из этих маршрутов у compute не резолвится: блочное хранение уехало в
> **storage**, география — в **geo** (`/geo/v1/regions` и `/geo/v1/zones`; админский CRUD —
> `/geo/v1/internal/regions`, `/geo/v1/internal/zones`), а compute-дубль снят миграцией
> `0021_drop_block_storage_duplicates.sql`. Механическая перепись хука свежести по этой
> записке дала шесть несуществующих REST-координат.
>
> Прежняя редакция этого же предупреждения переносила geo-маршруты **фигурной формой**
> (`{regions,zones}` одной строкой). Такой записи в дереве не соответствует ничего:
> сокращение читается человеком, но резолвится как один несуществующий маршрут — то есть
> абзац, объясняющий чужую мёртвую координату, заводил свою. Домены-владельцы называем
> словом, маршруты — по одному.

## Registered services (public) — по `gateway/internal/restmux/mux.go`

| Proto service | REST префикс |
|---|---|
| `InstanceService` | `/compute/v1/instances` |
| `MachineTypeService` | `/compute/v1/machineTypes` |

(Backend addr `computeAddr` = `compute.kacho.svc.cluster.local:9090`.)

## Registered services (internal — cluster-internal only)

| Proto service | Notes |
|---|---|
| `InternalMachineTypeService` | админский CRUD каталога типов машин |

Прежние `InternalDiskType/Zone/Region` здесь — это поверхность **других** сервисов
(storage и geo); см. [[apigw-internal-vs-tls]] про разделение слушателей.

## Identity forwarding (production auth contract)

Как [[apigw-to-vpc]]: gateway форвардит identity **только** как `x-kacho-principal-*`
(trust-gated в operations-carrier `UnaryTrustedPrincipalExtract`), не legacy
`x-kacho-project-id`. compute `TenantInterceptor` (production) обязан признавать
forwarded-принципал не-anonymous; per-object `authzIntr` (FGA Check) + listFilter — реальный гейт.

## History

- **2026-07-10** — тот же production tenant-guard баг, что и в vpc: guard считал
  `IsAnonymous` только по `x-kacho-project-id` → отвергал аутентиф.+авториз. compute-запрос
  (`403 "AuthN required (production mode)"`) до authzIntr. Фикс: guard принимает
  `x-kacho-principal-*` (mirror kacho-iam `authzguard.IsAnonymous`). `kacho-compute#103` →
  PR `kacho-compute#104` (merged, image `main-1678f62c`). Детали: [[apigw-to-vpc]].

## See also

[[../packages/apigw-restmux]] [[apigw-to-vpc]]

#edge #cross-service #kacho-apigw #kacho-compute
