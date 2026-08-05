---
title: "api-gateway → vpc (proxy + REST routing)"
aliases:
  - apigw to vpc
category: edge
caller_repo: kacho-api-gateway
callee_repo: kacho-vpc
sync_async: sync
protocol: grpc-gateway
status: active
tags:
  - edge
  - cross-service
  - kacho-apigw
  - kacho-vpc
verified_against: "координаты записки (файлы маршрутизации, REST-маршруты обоих listener'ов) сверены с деревом продукта 1653387b (2026-08-06); контракт форварда личности построчно не пересматривался"
---

# api-gateway → vpc (proxy + REST routing)

**Caller**: `kacho-api-gateway` (`internal/restmux/mux.go`)
**Callee**: `kacho-vpc:9090` (public gRPC) + `kacho-vpc:9091` (internal)
**Protocol**: grpc-gateway HandlerFromEndpoint (REST → gRPC)

## Registered services (public — на TLS edge)

| Proto service | RegisterHandler call | REST префикс |
|---|---|---|
| `NetworkService` | `vpcpb.RegisterNetworkServiceHandlerFromEndpoint(ctx, mux, vpcAddr, ...)` | `/vpc/v1/networks` |
| `SubnetService` | `RegisterSubnetServiceHandlerFromEndpoint` | `/vpc/v1/subnets` |
| `AddressService` | `RegisterAddressServiceHandlerFromEndpoint` | `/vpc/v1/addresses` |
| `RouteTableService` | `RegisterRouteTableServiceHandlerFromEndpoint` | `/vpc/v1/routeTables` |
| `SecurityGroupService` | `RegisterSecurityGroupServiceHandlerFromEndpoint` | `/vpc/v1/securityGroups` |
| `GatewayService` | `RegisterGatewayServiceHandlerFromEndpoint` | `/vpc/v1/gateways` |
| `NetworkInterfaceService` | `RegisterNetworkInterfaceServiceHandlerFromEndpoint` | `/vpc/v1/networkInterfaces` |

> [!note] Снята строка `PrivateEndpointService` и её маршрут (сверено 1653387b, 2026-08-06)
> Ресурса нет во всём монорепо (`git grep -il private_endpoint` → 0): ни proto, ни типа в
> модели прав, ни маршрута. Строка в таблице регистраций читается как «этот маршрут
> работает», поэтому и сам адрес здесь не воспроизводится координатой — цитата мёртвого
> маршрута в обратных кавычках остаётся живым утверждением о дереве.

(Backend addr `vpcAddr` = `vpc.kacho.svc.cluster.local:9090` — см. `mux.go` `addrs[]`.)

## Registered services (internal — cluster-internal listener only)

См. [[apigw-internal-vs-tls]].

- `InternalAddressPoolService` — `/vpc/v1/addressPools*` + `/vpc/v1/networks/{id}/addressPoolBinding`
- `InternalNetworkService` — internal Network admin

(`InternalCloudService` вместе со своим маршрутом выбора пула удалён в [[../KAC/KAC-266]];
сам адрес здесь не воспроизводится — цитата снятого маршрута координатой читается как
утверждение, что он есть.)

Выбор порта (внутренний `vpcInternalAddr` против публичного `vpcAddr`) делает шлюз при
регистрации маршрутов. Отдельного файла-«директора» в дереве нет: прежняя координата под
слоем прокси не резолвится и потому здесь не цитируется. Маршрутизация живёт в
`gateway/internal/restmux/mux.go` и `gateway/internal/restmux/internal_routes.go`,
проксирование — в `gateway/internal/proxy/shimproxy.go`, отказ внешнему origin'у — в
`gateway/internal/proxy/route_refusal.go`.

## Identity forwarding (production auth contract)

Gateway аутентифицирует end-user (Hydra-JWT / Kratos-session), авторизует per-RPC (FGA Check),
и форвардит identity в backend **только** как `x-kacho-principal-{type,id,display-name}` (+
`x-kacho-token-acr`) — см. `internal/restmux/mux.go` `buildPrincipalMetadata`. Gateway **НЕ**
форвардит legacy `x-kacho-project-id` (нет кода, вычисляющего project-access-list).

vpc's `TenantInterceptor` (production-mode) обязан признавать forwarded-принципал как
не-anonymous; project-scoping энфорсит per-object `authzIntr` (FGA Check, fatal-if-missing в
prod) + listFilter — не tenant-guard. `x-kacho-project-id`/`x-kacho-admin` — legacy scaffolding,
в проде пустые (gateway их не шлёт) → `AssertProjectOwnership` no-op'ит.

## History

- **2026-07-10** — fe3455 production-cutover вскрыл: vpc production tenant-guard считал
  `IsAnonymous` только по `x-kacho-project-id` → отвергал аутентиф.+авториз. запрос
  (`403 "AuthN required (production mode)"`) до authzIntr. CI/newman гоняют dev-mode (guard
  skipped) → путь был непокрыт. Фикс: guard принимает `x-kacho-principal-*` (mirror kacho-iam
  `authzguard.IsAnonymous`). `kacho-vpc#53` → PR `kacho-vpc#54` (merged). Аналог: [[apigw-to-compute]].

## See also

[[../packages/apigw-restmux]] [[../packages/apigw-proxy]] [[apigw-internal-vs-tls]]

#edge #cross-service #kacho-apigw #kacho-vpc
