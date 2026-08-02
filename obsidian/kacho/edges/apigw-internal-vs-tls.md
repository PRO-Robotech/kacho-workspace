---
title: "api-gateway: TLS edge vs cluster-internal listener"
aliases:
  - apigw listener split
category: edge
caller_repo: kacho-api-gateway
callee_repo: kacho-api-gateway
sync_async: sync
protocol: http-listener
status: active
related_tickets:
  - "[[KAC/KAC-94]]"
  - "[[KAC/SEC-L-rest-internal-isolation]]"
tags:
  - edge
  - kacho-api-gateway
  - internal
  - security
---

# api-gateway: listener split (TLS edge vs cluster-internal)

**Repo**: `kacho-api-gateway`
**File**: `internal/restmux/mux.go` + `internal/proxy/director.go`
**KAC**: KAC-50 (initial split), KAC-15 (Geography move)

## Why two listeners

CLAUDE.md «Запреты» #6: `Internal*` методы **никогда** не должны попадать на публичный TLS edge (`api.kacho.local:443`). Они нужны admin-UI / impl-controllers / port-forward — отдельный cluster-internal listener.

> [!warning] Граница проводится по listener'у приёма, а не по разбору пути
> Один `httpSrv` обслуживает **оба** listener'а (plaintext `:8080` internal + TLS external),
> поэтому «internal» обязан быть свойством **соединения**, а не строки запроса: путь
> подделывается, порт приёма — нет. Метка ставится на приёме (`internal/listenerorigin`
> `ExternalListener` + `httpSrv.ConnContext`), dispatcher отдаёт **404** на `Internal*`-путь с
> external origin, а поимённый список исключений заменён предикатом «origin=internal И
> `<exempt>`». До SEC-L признак по пути выбирал лишь JSON-marshaller и **не отвергал ничего** —
> различение с формой, но без содержания. Разбор класса и что из него переиспользовать —
> в History ниже (SEC-L).

## Two endpoints

| Listener | Network exposure | Регистрируется |
|---|---|---|
| **public** (TLS) | `api.kacho.local:443` | tenant-facing RPCs (Network, Subnet, Address, …, RouteTable, SG, Gateway, PE, NI, + Folder/Cloud/Org/Operation/Instance/Disk/…) |
| **internal** (cluster) | `api-gateway.kacho.svc.cluster.local:80` или alias | + `Internal*` RPCs (AddressPool, InternalNetwork, InternalDiskType/Zone/Region для KAC-15; `InternalCloud` удалён KAC-266) |

## Routing logic (director.go)

REST path → выбор backend addr (`vpcAddr` vs `vpcInternalAddr`):
1. `/vpc/v1/addressPools[/...|:...]` → internal.
2. `/vpc/v1/networks/{id}/addressPoolBinding` → internal.
3. Всё остальное `/vpc/v1/...` → public vpc (9090).

(`/vpc/v1/addresses/{id}/addressPoolOverride` + `/vpc/v1/clouds/{cloud_id}/poolSelector` удалены в [[../KAC/KAC-266]].)

Аналогично для compute: `/compute/v1/regions`, `/compute/v1/zones`, `/compute/v1/diskTypes` админ-RPC → computeInternalAddr; остальные `/compute/v1/...` → computeAddr (9090).

## Operation proxy

`/operations/{operation_id}` — local handler ([[../packages/apigw-opsproxy]]) определяет по prefix-у id (vpc=enp, rm=b1g, compute=epd) backend и проксирует туда.

## See also

[[../packages/apigw-restmux]] [[../packages/apigw-proxy]] [[apigw-to-vpc]] [[apigw-to-compute]] [[apigw-to-rm]]

## History

- **SEC-L (2026-06-16)** — REST external-isolation **enforcement** (PR #78).

  **Класс: различение, которое ничего не разделяло.** Один `httpSrv` обслуживал оба
  listener'а, а `isInternalPath` выбирал по пути лишь **JSON-marshaller** — то есть
  «internal» был признаком **форматирования ответа**, а не границей доступа. Разделение
  выглядело существующим (функция есть, вызывается, имя говорит «internal»), но ни одного
  запроса не отклоняло. Ровно тот класс «проверка с формой, но без содержания», который
  описан в `testing.md` §«Гейт на класс»: чтобы это заметить, надо было спросить не
  «есть ли различение», а **«что оно
  отвергает»** — и ответ был «ничего». Вторым слоем шёл список исключений, который перечислял
  часть внутренних методов поимённо и потому переживал любое изменение маршрутизации.

  **Fix — граница проводится по listener'у, а не по строке пути:** external TLS sub-listener
  помечается на приёме соединения (`internal/listenerorigin` + `httpSrv.ConnContext`),
  dispatcher отдаёт **404** на `Internal*`-путь с external origin, `isInternalPath` доучен
  распознавать также `:internal`-суффикс глагола. Поимённый список исключений заменён на
  предикат «origin=internal И запись каталога `<exempt>`» — гейтованные `Internal*` (напр.
  `InternalClusterService`, D-11) по-прежнему проходят FGA Check на внутреннем listener'е.
  Внутренние потребители (UI/admin/port-forward/self-call, newman `baseUrl`=:18080→:8080) не
  затронуты.

  **Что отсюда переиспользовать:** (1) признак принадлежности к внутренней поверхности берётся
  из **того, куда пришло соединение**, а не из разбора строки — путь подделывается, порт
  приёма нет; (2) поимённый список внутренних методов — исключение, которое обязано
  «истекать само», иначе следующий добавленный метод унаследует слепую зону; (3) 404 (а не
  403) на внешнем origin — тот же hide-existence-контракт, что и везде: наличие внутренней
  поверхности не подтверждается снаружи.

#edge #kacho-api-gateway #internal #security
