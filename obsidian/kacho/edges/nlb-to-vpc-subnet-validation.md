---
title: "nlb → vpc: Subnet validation (INTERNAL Listener + Target ip_ref)"
aliases:
  - nlb subnet validation
category: edge
caller_repo: kacho-nlb
callee_repo: kacho-vpc
sync_async: async
protocol: grpc-cluster-internal
status: active
related_tickets:
  - "[[KAC-141]]"
  - "[[KAC-152]]"
  - "[[KAC-153]]"
tags:
  - edge
  - kacho-nlb
  - kacho-vpc
  - cross-service
  - subnet
---

> [!success] Active since 2026-05-24 (KAC-141, kacho-nlb PR#8, PR#10)
> Edge активен; nlb валидирует `subnet_id` (для INTERNAL Listener и Target.ip_ref) через `vpc.SubnetService.Get` + IP ∈ CIDR check.

# nlb → vpc: Subnet validation

**Caller**: `kacho-nlb` (`internal/clients/vpc/subnet_client.go`; Listener.Create + Target validate workers)
**Callee**: `kacho-vpc.SubnetService.Get`
**Protocol**: gRPC cluster-internal
**Sync/Async**: **async** (внутри Operation worker'ов)

## When invoked

- **Listener.Create (INTERNAL LB)** worker: validates `subnet_id` существует + same `project_id` + same `region_id` (через zone→region resolve). Без него INTERNAL LB не может быть создан (sync precheck в `AllocateInternalIP` тоже зовёт Subnet).
- **TargetGroup.AddTargets** worker (`ip_ref` identity): для каждого target с `ip_ref.subnet_id` → Subnet.Get → IP ∈ (`v4_cidr_primary` ∪ `v4_cidr_blocks` ∪ v6 эквивалент). Out-of-CIDR → `InvalidArgument`.

## IP ∈ CIDR check (Target ip_ref)

```go
// nlb worker (simplified)
subnet, err := vpcSubnet.Get(ctx, &subnet_pb.GetSubnetRequest{SubnetId: ipRef.SubnetID})
if err != nil { return mapErr(err) }
ip, _ := netip.ParseAddr(ipRef.Address)
for _, cidrStr := range append([]string{subnet.V4CidrPrimary}, subnet.V4CidrBlocks...) {
    pfx, _ := netip.ParsePrefix(cidrStr)
    if pfx.Contains(ip) { return nil } // OK
}
return status.Error(codes.InvalidArgument, "target ip not in subnet CIDR")
```

## Error handling

| Result | gRPC code | Note |
|---|---|---|
| subnet OK + IP in CIDR | (continue) | |
| subnet not found | `InvalidArgument "subnet_id ..."` | dangling-ref грациозен на read |
| wrong project | `InvalidArgument "subnet belongs to different project"` | |
| IP not in subnet CIDR | `InvalidArgument "target ip not in subnet CIDR"` | per-target reason в ops.error |
| vpc недоступен | `Unavailable` | retry |

## See also

[[../rpc/vpc-subnet-service]] [[../resources/vpc-subnet]] [[../resources/nlb-listener]] [[../resources/nlb-target]] [[nlb-to-vpc-vip-allocation]]

#edge #kacho-nlb #kacho-vpc #cross-service #subnet
