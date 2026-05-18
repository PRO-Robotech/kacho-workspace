---
title: "compute → vpc: NIC validate + attach (CAS)"
aliases:
  - compute to vpc NIC validate
category: edge
caller_repo: kacho-compute
callee_repo: kacho-vpc
sync_async: async
protocol: grpc-cluster-internal
status: active
related_tickets:
  - "[[KAC/KAC-94]]"
tags:
  - edge
  - cross-service
  - kacho-compute
  - kacho-vpc
  - ni
---

# compute → vpc: NIC validation + attach

**Caller**: `kacho-compute` (Instance.Create / .UpdateNetworkInterfaces)
**Callee**: `kacho-vpc` (`NetworkInterfaceService.AttachToInstance` + `SubnetService.Get` + `SecurityGroupService.Get`)
**Protocol**: gRPC cluster-internal
**Sync/Async**: async (внутри Compute Operation worker'а)

## When invoked

- **Instance.Create** с NIC-spec:
  - Если `existing_network_interface_id` → `NetworkInterfaceService.AttachToInstance` (CAS на `used_by_id`).
  - Если inline NIC-spec → `NetworkInterfaceService.Create` → `AttachToInstance`.
  - Для каждого NIC валидируется `subnet_id` (Subnet.Get) + `security_group_ids` (SG.Get для каждой).
- **Instance.Delete** — `DetachFromInstance` через vpc → освобождает NIC.

## Attach race (KAC-52)

Внутри vpc — CAS-update, см. [[../resources/vpc-networkinterface]]. Compute должен **ждать** успешного `AttachToInstance.Operation.done=true`, не должен предполагать, что NIC свободен.

## IPAM

Inline-NIC primary_v4 — vpc-сторона аллоцирует IP из Subnet через [[../rpc/vpc-internal-address-service]] `AllocateInternalIP` (тоже cluster-internal call, см. [[../edges/apigw-internal-vs-tls]]).

## Error handling

| Result | gRPC code |
|---|---|
| NIC уже attached к другому | `FailedPrecondition "ni in use"` |
| Subnet not found | `InvalidArgument "subnet_id ..."` |
| SG not found | `InvalidArgument "security_group_ids ..."` |
| vpc недоступен | `Unavailable` (retry) |

## See also

[[../rpc/vpc-networkinterface-service]] [[../rpc/vpc-internal-address-service]] [[../resources/vpc-networkinterface]]

#edge #cross-service #kacho-compute #kacho-vpc #ni
