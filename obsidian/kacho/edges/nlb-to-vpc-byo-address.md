---
title: "nlb → vpc: BYO Address validation + SetReference CAS"
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
  - byo
---

> [!success] Active since 2026-05-24 (KAC-141, kacho-nlb PR#8)
> Edge активен; BYO `address_id` flow Listener.Create использует `AddressService.Get` (валидация) + `InternalAddressService.SetReference` (atomic CAS).

# nlb → vpc: BYO Address validation + SetReference

**Caller**: `kacho-nlb` (`internal/clients/vpc/address_client.go` + InternalAddressService client; Listener.Create worker)
**Callee**: `kacho-vpc.AddressService.Get` + `kacho-vpc.InternalAddressService.SetReference`
**Protocol**: gRPC cluster-internal
**Sync/Async**: **async** (внутри Operation worker'а Listener.Create)

## When invoked

- `ListenerService.Create` worker, если `address_id` передан client'ом (BYO mode):
  1. **Validation step** — `AddressService.Get(address_id)`:
     - Same `project_id` как у Listener.LB (иначе `InvalidArgument`)
     - `used_by` пустой OR `used_by="nlb_listener:<our-id>"` (idempotent re-attach)
  2. **Reservation step** — `InternalAddressService.SetReference(address_id, used_by="nlb_listener:<id>")`:
     - Atomic CAS на `addresses.used_by` через single-statement `UPDATE ... WHERE used_by IN ('', $ours) RETURNING ...` (vpc-side).
     - 0 rows → conflict (другой ресурс уже резервирует) → `FailedPrecondition`.

## Atomic CAS (anti-TOCTOU)

vpc-сторона использует CAS pattern (workspace CLAUDE.md §«Within-service refs»). Два конкурентных `SetReference` к одному Address — только один проходит, второй получает `FailedPrecondition`. Race-safe.

## Error handling

| Result | gRPC code | Note |
|---|---|---|
| address OK + reserved | (continue worker) | listener.address_id := given |
| address not found | `InvalidArgument "address_id ..."` | |
| wrong project | `InvalidArgument "address belongs to different project"` | |
| used_by conflict | `FailedPrecondition "address already in use"` | CAS rejected |
| vpc недоступен | `Unavailable` | retry |

## Listener.Delete — clear BYO reference

Inverse: на `Listener.Delete` worker'а для BYO Address:
- `vpc.InternalAddressService.ClearReference(address_id, prev_used_by="nlb_listener:<id>")` — atomic CAS clear (vpc-side).
- Address остаётся в tenant pool (НЕ free pool); IP сохраняется за tenant'ом.

Auto-allocated → отдельный flow [[nlb-to-vpc-vip-allocation]] (`FreeIP` → возврат в pool).

## See also

[[../rpc/vpc-address-service]] [[../rpc/vpc-internal-address-service]] [[../resources/vpc-address]] [[../resources/nlb-listener]] [[nlb-to-vpc-vip-allocation]]

#edge #kacho-nlb #kacho-vpc #cross-service #cas #byo
