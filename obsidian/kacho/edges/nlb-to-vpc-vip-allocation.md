---
title: "nlb → vpc: VIP allocation (External/Internal)"
aliases:
  - nlb vip allocation
  - nlb to vpc allocate ip
category: edge
caller_repo: kacho-nlb
callee_repo: kacho-vpc
sync_async: async
protocol: grpc-cluster-internal
status: active
related_tickets:
  - "[[KAC-141]]"
  - "[[KAC-152]]"
tags:
  - edge
  - kacho-nlb
  - kacho-vpc
  - cross-service
  - vip
---

> [!success] Active since 2026-05-24 (KAC-141, kacho-nlb PR#8)
> Edge активен; nlb worker аллоцирует VIP через `vpc.InternalAddressService.AllocateExternalIP/AllocateInternalIP` при Listener.Create (auto mode).

# nlb → vpc: VIP allocation (auto mode)

**Caller**: `kacho-nlb` (`internal/clients/vpc/address_client.go` — InternalAddressService client; вызывается из Listener.Create worker)
**Callee**: `kacho-vpc.InternalAddressService.AllocateExternalIP` / `AllocateInternalIP` (port 9091)
**Protocol**: gRPC cluster-internal (direct dial; не через api-gateway)
**Sync/Async**: **async** (внутри Operation worker'а Listener.Create)

## When invoked

- `ListenerService.Create` (worker, после Validate + LB.Get sync prechecks):
  - Если `address_id` пустой → auto-mode → `AllocateExternalIP` (для EXTERNAL LB) или `AllocateInternalIP` (для INTERNAL LB, с `subnet_id`).
  - owner = `nlb_listener:<id>` (для tracking + Free на Delete).

## Allocation result

- vpc возвращает свежий `Address` с резолвленным IP-string + assigned `address_id`.
- nlb сохраняет в `listeners.allocated_address` + `listeners.address_id` (auto-allocated, kacho-managed).

## Error handling

| Result | gRPC code | Note |
|---|---|---|
| pool exhausted | `ResourceExhausted "no free addresses in pool"` | client retry, ops.error |
| invalid subnet (INTERNAL) | `InvalidArgument "subnet_id ..."` | sync precheck в [[nlb-to-vpc-subnet-validation]] |
| vpc недоступен | `Unavailable` | retry через `corelib/retry.OnUnavailable` |

## Compensation

Defer worker pattern: если `listeners.Insert` упал после успешного `AllocateXxxIP` → best-effort `vpc.InternalAddressService.FreeIP(address_id)`. Если FreeIP тоже упал — alert через `jobs/free_ip_runner.go` retry-loop.

## Listener.Delete — VIP release

Inverse path: на `Listener.Delete` worker'а:
- Auto-allocated → `vpc.InternalAddressService.FreeIP(address_id)` (возврат в pool).
- BYO — отдельный flow [[nlb-to-vpc-byo-address]] (clear `used_by`, IP остаётся за tenant'ом).

## See also

[[../rpc/vpc-internal-address-service]] [[../resources/vpc-address]] [[../resources/nlb-listener]] [[nlb-to-vpc-byo-address]] [[../packages/nlb-clients-vpc]]

#edge #kacho-nlb #kacho-vpc #cross-service #vip
