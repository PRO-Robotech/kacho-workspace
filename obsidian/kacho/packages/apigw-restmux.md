---
title: apigw-restmux
category: package
repo: kacho-api-gateway
layer: handler
tags:
  - packages
  - kacho-apigw
  - restmux
---

# kacho-api-gateway/internal/restmux

**Path**: `kacho-api-gateway/internal/restmux/`

REST → gRPC mux (grpc-gateway). Регистрирует HandlerFromEndpoint для каждого сервиса.

## Files

- `mux.go` — `Build(ctx, addrs map[string]string) (*runtime.ServeMux, error)` — единственная точка регистрации всех `RegisterXxxServiceHandlerFromEndpoint`.
- `mux_test.go` — smoke routes.

## Registered services (см. подробно)

- VPC public: см. [[../edges/apigw-to-vpc]].
- VPC internal: `InternalAddressPoolService`, `InternalNetworkService` (только при `vpcInternalAddr != ""`; `InternalCloudService` удалён в [[../KAC/KAC-266]]).
- RM: см. [[../edges/apigw-to-rm]].
- OrganizationManager.
- Compute public + Internal (если `computeInternalAddr != ""`): см. [[../edges/apigw-to-compute]].
- OperationService — **локальный** handler (`RegisterOperationServiceHandlerServer`) через [[apigw-opsproxy]] (без dial — proxy сам решает per-domain).

## Path routing для internal

Implemented в [[apigw-proxy]] `director.go`:
1. `/vpc/v1/addressPools[/...|:...]` → internal.
2. `/vpc/v1/networks/{id}/addressPoolBinding` → internal.

(`/vpc/v1/addresses/{id}/addressPoolOverride` + `/vpc/v1/clouds/{id}/poolSelector` удалены в [[../KAC/KAC-266]].)

## See also

[[apigw-proxy]] [[apigw-opsproxy]] [[../edges/apigw-internal-vs-tls]] [[../edges/apigw-to-vpc]] [[../edges/apigw-to-compute]] [[../edges/apigw-to-rm]]

#packages #kacho-apigw #restmux
