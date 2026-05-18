---
title: vpc-apps-kacho-api-addresspool
category: package
repo: kacho-vpc
layer: use-case
tags:
  - packages
  - kacho-vpc
  - handler
  - addresspool
  - admin
---

# kacho-vpc/internal/apps/kacho/api/addresspool

**Path**: `kacho-vpc/internal/apps/kacho/api/addresspool/`
**Implements**: [[../rpc/vpc-internal-address-pool-service|InternalAddressPoolService]]

Admin-only — все RPC только на internal-listener (9091).

## Files

| File | Содержание |
|---|---|
| `handler.go` | gRPC adapter |
| `iface.go` | ports |
| `helpers.go` | CIDR validation, family check |
| `create.go` | split v4/v6 (KAC-71 миграция 0022); zone validate |
| `update.go` | replace_cidrs семантика |
| `delete.go` | RESTRICT если есть active bindings |
| `get.go` / `list.go` | std |
| `bindings.go` | bind/unbind для Network-default + Address-override |
| `resolve.go` | core resolution logic (per-Address → per-Network → cloud-selector → zone-default) |
| `check.go` | `Check` RPC — quick pool-availability check |
| `explain_resolution.go` | trace resolution chain (debug) |
| `utilization.go` | free/used count per CIDR |
| `usecase_test.go` | |

## See also

[[../rpc/vpc-internal-address-pool-service]] [[../resources/vpc-addresspool]] [[../rpc/vpc-internal-cloud-service]]

#packages #kacho-vpc #handler #addresspool #admin
