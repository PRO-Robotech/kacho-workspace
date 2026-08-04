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
| **public** (TLS) | `api.kacho.local:443` | tenant-facing RPC семи доменов: vpc (Network/Subnet/Address/RouteTable/SecurityGroup/Gateway/NetworkInterface), compute (Instance/MachineType), storage (Volume/Snapshot/Image/DiskType), geo (Region/Zone — read), nlb (LoadBalancer/Listener/TargetGroup), registry, iam (Account/Project/User/SA/Group/Role/AccessBinding/…), плюс Operation |
| **internal** (cluster) | `api-gateway.kacho.svc.cluster.local:80` или alias | + `Internal*` RPC: `InternalAddressPool`/`InternalNetwork` (vpc), `InternalMachineType` (compute), `InternalVolume`/`InternalDiskType`/`InternalImage` (storage), `InternalRegion`/`InternalZone` (geo), `InternalRegistry`, `InternalCluster`/`InternalIAM`/`InternalUser`/`InternalOperations`/`InternalInteractiveClient` (iam), `InternalResourceLifecycle` (nlb) |

> [!note] Строки `Folder`/`Cloud`/`Org` сняты — предмета нет
> Домен управления ресурсами упразднён, его поверхность заменена `Project`/`Account` у iam
> ([[apigw-to-rm]]). Перечень выше выведен из `grep -o "Register[A-Za-z]*ServiceHandler"` по
> `gateway/internal/restmux/` (46 регистраций), а не выписан по памяти.

## Routing logic (сверено 2026-08-05)

> [!note] Координата `internal/proxy/director.go` не резолвится
> Файла с таким именем в дереве нет. Разделение живёт в
> `gateway/internal/restmux/{mux.go,internal_routes.go}` (какой RPC на какой адрес
> зарегистрирован) и `gateway/internal/proxy/{shimproxy.go,route_refusal.go}` (отказ
> внутреннему пути, пришедшему на внешний listener).

REST path → выбор backend addr (`vpcAddr` vs `vpcInternalAddr`):
1. `/vpc/v1/addressPools[/...|:...]` → internal.
2. `/vpc/v1/networks/{id}/addressPoolBinding` → internal.
3. Всё остальное `/vpc/v1/...` → public vpc (9090).

(`/vpc/v1/addresses/{id}/addressPoolOverride` + `/vpc/v1/clouds/{cloud_id}/poolSelector` удалены в [[../KAC/KAC-266]] — здесь они оставлены как снятые, а не как маршруты.)

Аналогично для остальных доменов: у каждого свой публичный и внутренний адрес backend'а
(`{compute,iam,nlb,geo,registry,storage}{,Internal}Addr` в `gateway/internal/config`).
**Прежняя строка про `/compute/v1/{regions,zones,diskTypes}` неверна дважды**: этих маршрутов
нет, и владеют предметом другие сервисы — география у geo (`/geo/v1/*`), типы дисков у
storage (`/storage/v1/*`).

## Operation proxy

`/operations/{operation_id}` — локальный обработчик ([[../packages/apigw-opsproxy]]) выбирает
backend по префиксу id. Таблица префиксов **выведена из corelib там, где константа
экспортирована**, и продублирована именованными константами там, где нет (`e9b` — вторичный
префикс vpc, `iop` — iam, `geo` — geo); расхождение ловится пробой `TestPrefixToBackend_*`.
Префикс `b1g` снятого домена управления ресурсами backend'а **не имеет** и отвечает
`INVALID_ARGUMENT` — это закреплено пробой (`TestOpsProxy_Get_RmPrefixIs_InvalidArgument`), а
не подразумевается ([[apigw-to-rm]]). Единственный legacy-fallback в таблице — старая форма
id самого vpc.

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
