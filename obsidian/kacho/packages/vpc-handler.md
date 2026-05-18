---
title: vpc-handler
category: package
repo: kacho-vpc
layer: handler
tags:
  - packages
  - kacho-vpc
  - handler
  - internal
---

# kacho-vpc/internal/handler

**Path**: `kacho-vpc/internal/handler/`

Internal admin handlers (внутренний listener 9091) + общие gRPC-side компоненты (interceptors, error mapping, operation-handler).

## Files

| File | Содержание |
|---|---|
| `internal_address_allocate_handler.go` | gRPC adapter для [[../rpc/vpc-internal-address-service]] (Allocate* RPCs) — пробрасывает в [[vpc-apps-kacho-services-addressref]] |
| `internal_cloud_handler.go` | adapter для [[../rpc/vpc-internal-cloud-service]] |
| `internal_network_handler.go` | adapter для [[../rpc/vpc-internal-network-service]] (SetDefaultSecurityGroupId) → [[vpc-apps-kacho-services-networkinternal]] |
| `internal_watch_handler.go` | deprecated stub для [[../rpc/vpc-internal-watch-service]] (Watch выкинут с 1.0) |
| `internal_maperr.go` | internal-side error mapping |
| `operation_handler.go` | [[../rpc/operation-service]] adapter — `Get` / `Cancel` |
| `operation_handler_test.go` | |
| `address_handler_test.go` | |
| `mapping.go` | common type-mapping helpers (proto ↔ domain) |
| `handler_test.go` | |
| `mock_test.go` | |
| `tenant_interceptor.go` | gRPC unary-interceptor: extract tenant-context из metadata (auth-shim) |
| `tenant_interceptor_test.go` | |
| `SECURITY.md` | заметки про tenant isolation auditor |

## Position

В [[vpc-cmd-vpc]] wiring'е:
- Public listener (9090): handlers из `apps/kacho/api/<resource>/handler.go`.
- Internal listener (9091): handlers из этого пакета + [[vpc-apps-kacho-api-addresspool]] (тоже internal-only).

## See also

[[vpc-apps-kacho-services-addressref]] [[vpc-apps-kacho-services-networkinternal]] [[../rpc/operation-service]] [[../edges/apigw-internal-vs-tls]]

#packages #kacho-vpc #handler #internal
