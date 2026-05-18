---
title: vpc-apps-kacho-api-subnet
category: package
repo: kacho-vpc
layer: use-case
tags:
  - packages
  - kacho-vpc
  - handler
  - subnet
---

# kacho-vpc/internal/apps/kacho/api/subnet

**Path**: `kacho-vpc/internal/apps/kacho/api/subnet/`
**Implements**: [[../rpc/vpc-subnet-service|SubnetService]]

## Files

| File | Содержание |
|---|---|
| `handler.go` | gRPC adapter |
| `iface.go` | ports |
| `helpers.go` | CIDR validation, host-bits check |
| `create.go` | EXCLUDE-constraint catch (SQLSTATE 23P01 → FailedPrecondition) |
| `delete.go` | RESTRICT-FK check via repo error mapping |
| `update.go` | name/labels/desc; CIDR — separate RPCs |
| `add_cidr_blocks.go` | extra v4/v6 CIDRs (KAC-71) |
| `remove_cidr_blocks.go` | sub'subnet check (no Address in removed CIDR) |
| `get.go` | sync |
| `list.go` | filter + pagination |
| `list_used_addresses.go` | IPAM-utilization (sync) |
| `move.go` | cross-folder |
| `relocate.go` | cross-zone (требует Zone validate через compute, [[../edges/vpc-to-compute-zone-validate]]) |
| `usecase_test.go` | |

## See also

[[../rpc/vpc-subnet-service]] [[../resources/vpc-subnet]] [[../edges/vpc-to-compute-zone-validate]]

#packages #kacho-vpc #handler #subnet
