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
| `PrivateEndpointService` | `pepb.RegisterPrivateEndpointServiceHandlerFromEndpoint` | `/vpc/v1/endpoints` |
| `NetworkInterfaceService` | `RegisterNetworkInterfaceServiceHandlerFromEndpoint` | `/vpc/v1/networkInterfaces` |

(Backend addr `vpcAddr` = `vpc.kacho.svc.cluster.local:9090` — см. `mux.go` `addrs[]`.)

## Registered services (internal — cluster-internal listener only)

См. [[apigw-internal-vs-tls]].

- `InternalAddressPoolService` — `/vpc/v1/addressPools*` + `/vpc/v1/networks/{id}/addressPoolBinding`
- `InternalNetworkService` — internal Network admin

(`InternalCloudService` + `/vpc/v1/clouds/{id}/poolSelector` удалены в [[../KAC/KAC-266]].)

Director (`internal/proxy/director.go`) роутит requests на internal-port (`vpcInternalAddr`) или public-port (`vpcAddr`) в зависимости от пути.

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
