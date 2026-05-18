---
title: vpc-apps-kacho-api-privateendpoint
category: package
repo: kacho-vpc
layer: use-case
tags:
  - packages
  - kacho-vpc
  - handler
  - privateendpoint
---

# kacho-vpc/internal/apps/kacho/api/privateendpoint

**Path**: `kacho-vpc/internal/apps/kacho/api/privateendpoint/`
**Implements**: [[../rpc/vpc-privateendpoint-service|PrivateEndpointService]]

## Files

| File | Содержание |
|---|---|
| `handler.go` | gRPC adapter |
| `iface.go` | ports |
| `helpers.go` | service_kind validation |
| `create.go` | subnet+address bind через [[vpc-apps-kacho-services-addressref]] |
| `update.go` | description/labels/address (re-bind) |
| `delete.go` | RESTRICT-FK на Address (0024) → unbind address first |
| `get.go` / `list.go` | std |
| `usecase_test.go` | |

## See also

[[../rpc/vpc-privateendpoint-service]] [[../resources/vpc-privateendpoint]] [[vpc-apps-kacho-services-addressref]]

#packages #kacho-vpc #handler #privateendpoint
