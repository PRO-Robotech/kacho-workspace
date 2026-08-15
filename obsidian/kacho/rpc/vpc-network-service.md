---
title: NetworkService
aliases:
  - NetworkService (vpc)
proto_file: kacho/cloud/vpc/v1/network_service.proto
category: rpc
backend: kacho-vpc
backend_port: 9090
visibility: public
domain: vpc
related_resource: "[[resources/vpc-network]]"
methods_count: 11
async_methods: 5
status: stable
verified_against: "ствол redesign/integration, сверено 2026-08-05"
tags:
  - rpc
  - kacho-vpc
  - network
---

# NetworkService (vpc)

**Proto**: `proto/kacho/cloud/vpc/v1/network_service.proto`
**Backend**: `kacho-vpc:9090` (public gRPC)
**Public/Internal**: public

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetNetworkRequest | Network | sync | NotFound → 404 |
| List | ListNetworksRequest | ListNetworksResponse | sync | filter + page_token |
| Create | CreateNetworkRequest | operation.Operation | **async** | metadata: CreateNetworkMetadata{network_id} |
| Update | UpdateNetworkRequest | operation.Operation | **async** | UpdateMask discipline |
| Delete | DeleteNetworkRequest | operation.Operation | **async** | `FailedPrecondition "network is not empty"` если subnets есть |
| AddCidrBlocks | AddNetworkCidrBlocksRequest | operation.Operation | **async** | супернет сети: добавить блок(и); через `Update` супернет не меняется |
| RemoveCidrBlocks | RemoveNetworkCidrBlocksRequest | operation.Operation | **async** | снять блок(и) |
| ListSubnets | ListNetworkSubnetsRequest | ListNetworkSubnetsResponse | sync | nav-helper |
| ListSecurityGroups | ListNetworkSecurityGroupsRequest | ListNetworkSecurityGroupsResponse | sync | nav |
| ListRouteTables | ListNetworkRouteTablesRequest | ListNetworkRouteTablesResponse | sync | nav |
| ListOperations | ListNetworkOperationsRequest | ListNetworkOperationsResponse | sync | per-resource ops history |

## REST mapping

| HTTP | Method |
|---|---|
| `GET /vpc/v1/networks/{network_id}` | Get |
| `GET /vpc/v1/networks` | List |
| `POST /vpc/v1/networks` | Create |
| `PATCH /vpc/v1/networks/{network_id}` | Update |
| `DELETE /vpc/v1/networks/{network_id}` | Delete |
| `POST /vpc/v1/networks/{network_id}:add-cidr-blocks` | AddCidrBlocks |
| `POST /vpc/v1/networks/{network_id}:remove-cidr-blocks` | RemoveCidrBlocks |
| `GET /vpc/v1/networks/{network_id}/subnets` | ListSubnets |
| `GET /vpc/v1/networks/{network_id}/security_groups` | ListSecurityGroups |
| `GET /vpc/v1/networks/{network_id}/route_tables` | ListRouteTables |
| `GET /vpc/v1/networks/{network_id}/operations` | ListOperations |

> [!note] Move удалён в KAC-266
> RPC `Move` + `POST /vpc/v1/networks/{network_id}:move` сняты (contract-removal). См. [[../KAC/KAC-266]].

> [!important] `List` объявлен `<exempt>` В PROTO — но авторизован сервисом, и это разные места
> Тонкость, на которой легко ошибиться, поэтому обе стороны названы явно (сверено
> 2026-08-05):
>
> - **В proto** `NetworkService/List` несёт `permission = "<exempt>"` — то есть
>   **край** per-RPC Check по этому методу не делает. Из шести списков vpc так объявлен
>   только он: `subnets`, `securityGroups`, `routeTables`, `networkInterfaces`,
>   `addresses` несут отношение `viewer`.
> - **В сервисе** запись всё равно есть и она обязательна: карта прав vpc
>   (`services/vpc/internal/apps/kacho/check/permission_map.go`) требует `viewer` на
>   `project:<project_id>` и **намеренно НЕ помечает** метод `ScopeFiltered`. Комментарий
>   у самой записи объясняет почему: фильтр по данным (`BatchCheck` поверх страницы)
>   **сужает** результат, но **не заменяет** проверку — при выключенном фильтре RPC
>   остался бы вовсе без гейта, и это давало бы перечисление чужих проектов.
>
> Мораль для чтения записок: «в proto exempt» **не равно** «без авторизации». Утверждать
> «отбор идёт только на уровне данных» здесь нельзя — за этим методом стоят **обе**
> линии, и именно так задумано.

> [!note] Порядок проверок в List — часть контракта
> Валидация `page_token` / `page_size` идёт **до** короткого замыкания по пустому гранту:
> иначе мусорный курсор при нулевом гранте вернул бы `200 []` вместо `400`. vpc — эталон
> этого порядка (7 из 7 List-хендлеров несут пробу порядка, а не юнит на валидатор), и
> свойство дерева держит AST-гейт в `internal/repohygiene`.

## See also

[[../packages/vpc-apps-kacho-api-network]] [[../resources/vpc-network]] [[vpc-internal-network-service]]

#rpc #kacho-vpc #network
