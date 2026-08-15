---
title: "nlb → vpc: link existing Address (SetReference CAS)"
aliases:
  - nlb byo address
  - nlb to vpc set reference
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
  - cas
  - vip
---

> [!warning] Линкуется LoadBalancer, не Listener
> Ветка `address_id` — один из трёх `VipSource` **`NetworkLoadBalancer.Create`** ([[nlb-to-vpc-vip-allocation]]).
> Прежняя форма (BYO-адрес на `Listener.Create`) не действует: листенер адреса не несёт.

# nlb → vpc: link existing Address (SetReference CAS)

**Caller**: `kacho-nlb` (`internal/clients/vpc`; `LoadBalancer.Create` worker + sync-precheck на request-path)
**Callee**: `kacho-vpc.AddressService.Get` (precheck) + `kacho-vpc.InternalAddressService` `AttachExisting`/`ClearReference`
**Protocol**: gRPC cluster-internal
**Sync/Async**: sync-precheck + **async** attach внутри Operation worker'а `LoadBalancer.Create`

## When invoked

`NetworkLoadBalancerService.Create` при `v4Source.address_id` / `v6Source.address_id`:

1. **Sync-precheck** (request-path, под identity тенанта) — `AddressService.Get(address_id)`:
   тот же `project_id`, семейство совпадает с полосой (v4/v6), kind соответствует `placement`
   (external ⟺ EXTERNAL); для INTERNAL дополнительно резолвится подсеть адреса → placement/регион/сеть/зона.
   Любой mismatch → **generic** `InvalidArgument "Illegal argument addressId"` (анти-oracle: чужой адрес
   не подтверждается ни существованием, ни свойствами); vpc недоступен → `Unavailable`.
2. **Attach** (worker) — `AttachExisting(address_id, owner="nlb_load_balancer:<lb-id>", owned=false)`:
   atomic CAS на `addresses.used_by` (vpc-side single-statement `UPDATE … WHERE used_by IN ('', $ours)
   RETURNING`). 0 rows → уже занят другим → generic `Illegal argument addressId`.
   `vip_origin=linked` → на Delete адрес **не** удаляется.

## Atomic CAS (anti-TOCTOU)

vpc-сторона использует CAS pattern (`data-integrity.md` §attach/смена ownership). Два конкурентных
attach к одному Address — только один проходит. Sync-precheck не является гейтом: authoritative —
именно CAS (precheck лишь fail-fast'ит до `Operation`).

## LoadBalancer.Delete — clear reference (без Delete адреса)

Inverse: `ClearReference(address_id)` — atomic CAS clear на vpc-стороне. Адрес остаётся у тенанта
(в free pool **не** возвращается — это отличие `linked` от `auto`). Та же ветка отрабатывает в
компенсации Create-саги и в free-ip-reconciler'е.

Auto-аллоцированные адреса (`vip_origin=auto`) → `ClearReference` + `FreeIP`: [[nlb-to-vpc-vip-allocation]].

## See also

[[../rpc/vpc-address-service]] [[../rpc/vpc-internal-address-service]] [[../resources/vpc-address]] [[../resources/nlb-load-balancer]] [[nlb-to-vpc-vip-allocation]]

#edge #kacho-nlb #kacho-vpc #cross-service #cas #vip
