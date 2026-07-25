---
title: "nlb → vpc: VIP acquire/release (LoadBalancer)"
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

> [!warning] Якорь VIP — LoadBalancer, не Listener
> Ребро висит на `NetworkLoadBalancer.Create`/`.Delete`. Прежняя форма (аллокация в `Listener.Create`,
> release в `Listener.Delete`) **не действует**: листенер адреса не несёт — см. [[../resources/nlb-listener]].

# nlb → vpc: VIP acquire/release (LoadBalancer)

**Caller**: `kacho-nlb` (`internal/clients/vpc` — `InternalAddressService` + public `AddressService`;
вызывается из `LoadBalancer.Create`/`.Delete` worker'ов и free-ip-reconciler'а)
**Callee**: `kacho-vpc.InternalAddressService` (`:9091`) + `AddressService.Get` (link-precheck)
**Sync/Async**: sync-precheck на request-path + **async** acquire/release внутри Operation worker'а

## Acquire — per-family, по `VipSource` oneof

LB несёт максимум один Address на семейство. Источник задаётся на Create отдельно для v4 и v6:

| `VipSource` | Режим | Вызов | `vip_origin` |
|---|---|---|---|
| `subnet_id` | INTERNAL | `AllocateInternalIP` / `AllocateInternalIPv6` | `auto` |
| `public {}` | EXTERNAL | `AllocateExternalIP` / `AllocateExternalIPv6`; underlay-зона деривится из региона (первая по сортировке) и наружу **не** отдаётся | `auto` |
| `address_id` | оба | `AttachExisting` (`SetReference` CAS, `owned=false`) | `linked` |

owner = `nlb_load_balancer:<lb-id>`. Результат (`address_id` + IP) персистится CAS-attach'ем
`AttachVIP` в собственном commit'е на семейство.

**Sync-precheck ДО Operation** (fail-fast, request-path): placement подсети == placement LB,
region-coherence, dualstack same-network/same-zone; для `address_id` — проект/семейство/kind через
public `AddressService.Get` под identity тенанта. vpc недоступен → `Unavailable` (fail-closed).

## Release — по `vip_origin`, три пути

- `LoadBalancer.Delete` (после того как листенеры удалены — FK RESTRICT + sync precheck);
- **компенсация Create-саги**: падение после acquire, но до финализации — освобождает уже добытые
  адреса в обратном порядке и снимает `CREATING`-handle;
- **free-ip-reconciler**: скан `load_balancers` в `CREATING`/`DELETING` дольше порога
  (`load_balancers_reconcile_idx`) — backstop на краш worker'а между acquire и persist.

Ветка выбирается дискриминатором: `auto` → `ClearReference` **затем** `FreeIP`; `linked` → только
`ClearReference` (адрес остаётся у тенанта). Two-step для `auto` обязателен — `FreeIP` (== Delete
адреса) упёрся бы в собственный guard на owned-референсе. Все шаги идемпотентны (NotFound = успех).

## Error handling

| Result | Наружу | Note |
|---|---|---|
| пул исчерпан / подсеть не резолвится | `FailedPrecondition "could not allocate load balancer address"` | намеренно лосси (анти-oracle) — **реальная причина логируется** (`load_balancer_vip_acquire_failed`), иначе отказ неатрибутируем (CWE-778) |
| link-конфликт / чужой адрес / mismatch | `InvalidArgument "Illegal argument addressId"` | generic, не подтверждает существование/свойства |
| double-claim в регионе (23505) | `FailedPrecondition "could not assign address to load balancer"` | владельца адреса не раскрываем |
| семейство уже несёт другой адрес | `FailedPrecondition "load balancer already has an address for this family"` | `AttachVIP` CAS вернул 0 rows |
| vpc недоступен | `Unavailable` | fail-closed для мутаций |

## See also

[[../rpc/vpc-internal-address-service]] [[../resources/vpc-address]] [[../resources/nlb-load-balancer]] [[../resources/nlb-listener]] [[nlb-to-vpc-byo-address]] [[../packages/nlb-clients-vpc]]

#edge #kacho-nlb #kacho-vpc #cross-service #vip
