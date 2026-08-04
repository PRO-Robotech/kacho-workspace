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

> [!important] `List` объявлен `<exempt>` в каталоге прав
> `NetworkService/List` несёт `permission = "<exempt>"`, то есть край **не** делает
> per-RPC project-scope Check. Это не «без авторизации»: аутентификация остаётся
> обязательной, а отбор идёт **на уровне данных** — страница читается курсором из своей
> БД, права проверяются на идентификаторы этой страницы. У списка, чей ответ касается
> объектов с индивидуальными владельцами, единого объекта для «одного вопроса» нет by
> construction (`security.md` §«Отношение, выполнимое подстановочным знаком»).
> Прочие списки vpc (`subnets`, `securityGroups`, `routeTables`, `networkInterfaces`,
> `addresses`) объявлены с отношением `viewer` — сверено по `google.api.http` и
> `kacho.iam.authz.v1` в proto 2026-08-05.

> [!note] Порядок проверок в List — часть контракта
> Валидация `page_token` / `page_size` идёт **до** короткого замыкания по пустому гранту:
> иначе мусорный курсор при нулевом гранте вернул бы `200 []` вместо `400`. vpc — эталон
> этого порядка (7 из 7 List-хендлеров несут пробу порядка, а не юнит на валидатор), и
> свойство дерева держит AST-гейт в `internal/repohygiene`.

## See also

[[../packages/vpc-apps-kacho-api-network]] [[../resources/vpc-network]] [[vpc-internal-network-service]]

#rpc #kacho-vpc #network
