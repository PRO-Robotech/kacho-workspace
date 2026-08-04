---
title: vpc-apps-kacho-api-gateway
category: packages
repo: kacho-vpc
layer: use-case
tags:
  - packages
  - kacho-vpc
  - handler
  - gateway
status: stable
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# kacho-vpc/internal/apps/kacho/api/gateway

**Каталог**: `services/vpc/internal/apps/kacho/api/gateway/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-vpc/internal/apps/kacho/api/gateway/`)
**Implements**: [[../rpc/vpc-gateway-service|GatewayService]]

## Files

| File | Содержание |
|---|---|
| `handler.go` | gRPC adapter |
| `iface.go` | ports |
| `helpers.go` | type/config validation (only `SHARED_EGRESS_GATEWAY` сейчас) |
| `create.go` | folder validation + type config persistence |
| `update.go` | name/labels/desc; type immutable |
| `delete.go` | FailedPrecondition если в use в RouteTable static_routes |
| `get.go` / `list.go` / `move.go` | std |
| `usecase_test.go` | |

## See also

[[../rpc/vpc-gateway-service]] [[../resources/vpc-gateway]]

#packages #kacho-vpc #handler #gateway
