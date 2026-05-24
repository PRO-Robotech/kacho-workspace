---
title: nlb-clients-vpc
category: packages
repo: kacho-nlb
layer: clients
tags:
  - packages
  - kacho-nlb
  - clients
  - cross-service
  - vpc
---

# kacho-nlb/internal/clients/vpc

**Path**: `kacho-nlb/internal/clients/vpc/`
**Imports**: `kacho-proto/gen/go/kacho/cloud/vpc/v1`, [[corelib-retry]]
**Imported by**: [[nlb-apps-kacho-api-listener]] (VIP alloc / BYO), [[nlb-apps-kacho-api-targetgroup]] (Subnet + NIC resolve)

Typed peer-service gRPC client adapters для kacho-vpc.

## Files

| File | Содержание |
|---|---|
| `address_client.go` | wraps `vpcpb.AddressServiceClient.Get` + `InternalAddressServiceClient.{AllocateExternalIP, AllocateInternalIP, FreeIP, SetReference, ClearReference}` |
| `subnet_client.go` | wraps `vpcpb.SubnetServiceClient.Get` — для INTERNAL Listener + Target ip_ref CIDR check |
| `nic_client.go` | wraps `vpcpb.NetworkInterfaceServiceClient.Get` — для Target.nic_id resolve → primary IP |
| `subnet_cache.go` | LRU cache (positive 30s) |
| `*_test.go` | unit-tests (CAS race, FreeIP idempotent, NIC NotFound mapping) |

## Pattern

Port-interfaces в service-layer (`AddressClient`, `SubnetClient`, `NICClient`); adapter в `clients/vpc/` реализует через gRPC stub + `corelib/retry.OnUnavailable`.

## Address client surface

```go
type AddressClient interface {
    Get(ctx, addressID) (*Address, error)
    AllocateExternalIP(ctx, owner string) (*Address, error)
    AllocateInternalIP(ctx, subnetID, owner string) (*Address, error)
    FreeIP(ctx, addressID string) error  // idempotent
    SetReference(ctx, addressID, usedBy string) error  // CAS
    ClearReference(ctx, addressID, prevUsedBy string) error  // CAS
}
```

CAS pattern (SetReference/ClearReference) — vpc-side single-statement `UPDATE ... WHERE used_by IN ('', $prev) RETURNING ...`. 0 rows → conflict → `FailedPrecondition` (TOCTOU-free, workspace CLAUDE.md §«Within-service refs»).

## See also

[[../edges/nlb-to-vpc-vip-allocation]] [[../edges/nlb-to-vpc-byo-address]] [[../edges/nlb-to-vpc-subnet-validation]] [[../edges/nlb-to-vpc-nic-resolve]] [[nlb-apps-kacho-api-listener]] [[nlb-apps-kacho-api-targetgroup]]

#packages #kacho-nlb #clients #cross-service #vpc
