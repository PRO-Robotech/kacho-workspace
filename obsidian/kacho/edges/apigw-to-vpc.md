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

- `InternalAddressPoolService` — `/vpc/v1/addressPools*`
- `InternalCloudService` — `/vpc/v1/clouds/{id}/poolSelector`
- `InternalNetworkService` — internal Network admin

Director (`internal/proxy/director.go`) роутит requests на internal-port (`vpcInternalAddr`) или public-port (`vpcAddr`) в зависимости от пути.

## See also

[[../packages/apigw-restmux]] [[../packages/apigw-proxy]] [[apigw-internal-vs-tls]]

#edge #cross-service #kacho-apigw #kacho-vpc
