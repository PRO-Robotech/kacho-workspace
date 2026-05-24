---
title: "nlb → vpc: NIC resolve (Target.nic_id)"
aliases:
  - nlb nic resolve
category: edge
caller_repo: kacho-nlb
callee_repo: kacho-vpc
sync_async: async
protocol: grpc-cluster-internal
status: active
related_tickets:
  - "[[KAC-141]]"
  - "[[KAC-154]]"
tags:
  - edge
  - kacho-nlb
  - kacho-vpc
  - cross-service
  - ni
---

> [!success] Active since 2026-05-24 (KAC-141, kacho-nlb PR#10)
> Edge активен; для Target identity-type `nic_id` worker зовёт `vpc.NetworkInterfaceService.Get` → primary IP.

# nlb → vpc: NIC resolve (Target.nic_id)

**Caller**: `kacho-nlb` (`internal/clients/vpc/nic_client.go`; TargetGroup.AddTargets worker, per-target peer-validate)
**Callee**: `kacho-vpc.NetworkInterfaceService.Get`
**Protocol**: gRPC cluster-internal
**Sync/Async**: **async** (внутри AddTargets worker'а)

## When invoked

- `TargetGroup.AddTargets` worker (per-target loop), для targets с identity-type `nic_id`:
  - `NetworkInterfaceService.Get(nic_id)` → проверка existence + same project + primary IPv4 / IPv6 address resolved.
  - Resolved primary IP кэшируется (worker-local) на длительность Operation; persisted target row сохраняет `nic_id`, не raw IP (LB data-plane при необходимости resolve'ит сам).

## Validation rules

- NIC должен существовать (NotFound → InvalidArgument per-target).
- NIC.subnet → resolved subnet должна быть в same project (cross-project NIC → InvalidArgument).
- NIC.primary_v4 / primary_v6 (по target_group.health_check.ip_version) должен быть set; иначе `InvalidArgument "nic has no primary <ipver> address"`.

## Error handling

| Result | gRPC code | Note |
|---|---|---|
| NIC OK + primary IP resolved | (continue) | per-target validate pass |
| NIC not found | `InvalidArgument "nic_id ..."` | |
| wrong project | `InvalidArgument "nic belongs to different project"` | |
| no primary IP | `InvalidArgument "nic has no primary <ipver>"` | |
| vpc недоступен | `Unavailable` | retry, eventual ops.error |

## See also

[[../rpc/vpc-networkinterface-service]] [[../resources/vpc-networkinterface]] [[../resources/nlb-target]] [[nlb-to-compute-instance-resolve]]

#edge #kacho-nlb #kacho-vpc #cross-service #ni
