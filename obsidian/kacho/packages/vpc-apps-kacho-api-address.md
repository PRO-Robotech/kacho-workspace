---
title: vpc-apps-kacho-api-address
category: package
repo: kacho-vpc
layer: use-case
tags:
  - packages
  - kacho-vpc
  - handler
  - address
  - ipam
---

# kacho-vpc/internal/apps/kacho/api/address

**Path**: `kacho-vpc/internal/apps/kacho/api/address/`
**Implements**: [[../rpc/vpc-address-service|AddressService]]

## Files

| File | Содержание |
|---|---|
| `handler.go` | gRPC adapter |
| `iface.go` | ports (AddressRepo + AddressPoolReader для IPAM) |
| `helpers.go` | address-value validation, IPv4/v6 parsing |
| `create.go` | IPAM-allocate (external/internal v4/v6); pool-resolution chain |
| `allocate.go` | dedicated allocate-from-pool path (low-level) |
| `update.go` | name/labels/desc/reserved-flag |
| `delete.go` | check `used_by == ''` |
| `get.go` | sync; lookup by id or by-value |
| `list.go` | filter + list-by-subnet |
| `move.go` | cross-folder |
| `usecase_test.go` | |

## See also

[[../rpc/vpc-address-service]] [[../rpc/vpc-internal-address-service]] [[../resources/vpc-address]] [[vpc-apps-kacho-services-addressref]]

#packages #kacho-vpc #handler #address #ipam
