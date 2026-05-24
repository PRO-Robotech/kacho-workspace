---
title: "nlb → compute: Instance resolve (Target.instance_id)"
aliases:
  - nlb instance resolve
category: edge
caller_repo: kacho-nlb
callee_repo: kacho-compute
sync_async: async
protocol: grpc-cluster-internal
status: active
related_tickets:
  - "[[KAC-141]]"
  - "[[KAC-154]]"
tags:
  - edge
  - kacho-nlb
  - kacho-compute
  - cross-service
  - instance
---

> [!success] Active since 2026-05-24 (KAC-141, kacho-nlb PR#10)
> Edge активен; для Target identity-type `instance_id` worker зовёт `compute.InstanceService.Get` → primary NIC → primary IP.

# nlb → compute: Instance resolve (Target.instance_id)

**Caller**: `kacho-nlb` (`internal/clients/compute/instance_client.go`; TargetGroup.AddTargets worker)
**Callee**: `kacho-compute.InstanceService.Get`
**Protocol**: gRPC cluster-internal
**Sync/Async**: **async** (внутри AddTargets worker'а)

## When invoked

- `TargetGroup.AddTargets` worker (per-target loop), для targets с identity-type `instance_id`:
  - `InstanceService.Get(instance_id)` → проверка existence + same project + primary NIC + primary IP.
  - Resolved IP кэшируется в worker (не persisted в targets row; persisted остаётся `instance_id`).

## Validation rules

- Instance существует (NotFound → InvalidArgument per-target).
- Same project (cross-project Instance → InvalidArgument).
- Instance.network_interfaces[0] должен иметь `primary_v4_address.address` (или v6 по `target_group.health_check.ip_version`).

## Error handling

| Result | gRPC code | Note |
|---|---|---|
| Instance OK + primary IP | (continue) | per-target validate pass |
| Instance not found | `InvalidArgument "instance_id ..."` | |
| wrong project | `InvalidArgument "instance belongs to different project"` | |
| no NIC / no primary IP | `InvalidArgument "instance has no primary <ipver>"` | |
| compute недоступен | `Unavailable` | retry, eventual ops.error |

## See also

[[../rpc/compute-instance-service]] [[../resources/nlb-target]] [[nlb-to-vpc-nic-resolve]] [[nlb-to-compute-region-validation]]

#edge #kacho-nlb #kacho-compute #cross-service #instance
