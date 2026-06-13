---
title: "vpc-operator → cilium (VPC realization module)"
aliases:
  - vpc-operator to cilium
  - kacho vpc cilium module
category: edge
caller_repo: kacho-vpc-operator
callee_repo: cilium
sync_async: async
protocol: k8s-crd
status: planned
tags:
  - edge
  - cross-service
  - kacho-vpc
  - experimental
  - planned
---

# vpc-operator → cilium (VPC realization module)

**Caller**: `kacho-vpc-operator` (sibling, вне build-графа control-plane)
**Callee**: Cilium data-plane (новый встраиваемый модуль в `cilium-operator` + agent)
**Protocol**: проекция в k8s CRD (kube-apiserver), reconcile-loop

> [!note] Replacement data-plane после kube-ovn-эпохи
> Старая модель (`vpn_id` в [[../resources/vpc-network]], удалён migration 0023) — kube-ovn.
> Новый датаплейн — Cilium SRv6 L3VPN. Control-plane не меняется; реализация — внешний модуль.

## Принцип: тенантинг через SRv6 VRF, НЕ изоляция через политику

> [!important] CCNP ≠ VPC
> ipcache Cilium мапит IP→identity **плоско и глобально** → два VPC с одинаковым CIDR
> коллапсируют. CiliumNetworkPolicy = микросегментация поверх общего адресного
> пространства, **не тенантинг**. Перекрывающиеся CIDR + per-tenant routing требуют
> отдельного routing-домена.

Нативный механизм тенантинга = **SRv6 L3VPN (VRF)**. В OSS-дереве есть SRv6-датаплейн
(`enable-srv6`, `srv6-encap-mode`) + map'ы `pkg/maps/srv6map/{vrf,sid,policy}.go`
(cell `srv6map.Cell`). Ключ VRF-map: `(VRF_ID[32b] + SourceIP + DestCIDR)` → LPM,
lookup **VRF-scoped** → overlapping CIDR работают на уровне BPF. RFC 9252; чистый
IPv6-underlay L3 (L2 не тянем).

**Шов для модуля:** SRv6 датаплейн+map-менеджеры есть в OSS, но control-surface
(CRD, аллокация VRF/SID, assignment endpoint→VRF, BGP L3VPN) **отсутствует** (была
enterprise-надстройка). Модуль = недостающий control plane для существующего
SRv6-VRF датаплейна; `bpf/` не трогаем (driving существующих map'ов через `srv6map.Cell`).

## Карта: Kachō VPC → нативный Cilium (tenancy-first)

| Kachō | Нативный Cilium | Механизм |
|---|---|---|
| Network (VPC) | **SRv6 VRF** (VRF_ID + `cilium_srv6_vrf` + SID) | tenancy-домен; overlapping CIDR; per-tenant routing |
| Subnet | IPAM-пул scoped к VRF | CIDR внутри тенанта |
| SecurityGroup | `CiliumNetworkPolicy` **внутри VRF** | микросегментация *внутри* тенанта |
| RouteTable | SRv6 SID-policy + BGP L3VPN | inter-VRF leak / default / cross-DC анонс |
| NetworkInterface | endpoint, привязан к VRF, свой IP | |
| multi-NIC (без Multus) | под с интерфейсами в ≥2 VRF | per-interface VRF assignment |
| cross-DC/cluster | SRv6 encap + BGP-анонс SID поверх ClusterMesh | нативный L3VPN-stretch, без L2 |

Разделение: **VRF = тенантинг/изоляция-по-построению; SG = микросегментация внутри тенанта.**

## Решения (design)

- Тенантинг — **SRv6 VRF** (а не CCNP-граница и не Geneve-VNI). Перекрывающиеся CIDR — обязательны.
- Фаза 1 = `KachoVPC` → аллокация VRF_ID + agent-side SRv6/VRF-manager (single-cluster).
  DoD: 2 VPC с одинаковым 10.0.0.0/16 на одной ноде, разведены по VRF без route-leak.
- Порядок фаз: Network(VRF) → Subnet → SG → RouteTable → NIC → multi-NIC.

## Control-plane prerequisite (kacho-vpc): аллокация vrf_id + Internal Get

VRF_ID = **числовой инфра-идентификатор** → по `security.md` живёт ТОЛЬКО в `Internal*`.

- **Аллокация**: `kacho_vpc.networks.vrf_id bigint` + SEQUENCE (`START 1 MAXVALUE
  4294967295 NO CYCLE`) + `UNIQUE` + `CHECK 1..4294967295`. `DEFAULT nextval` → атомарно
  на INSERT (ban #10, без TOCTOU). `bigint` т.к. PG `integer` = signed int32 < uint32.
  Монотонно, без reuse, immutable (в `update_mask` → InvalidArgument).
- **Чтение**: новый `InternalNetworkService.GetNetwork` (:9091) → `GetInternalNetworkResponse{
  Network network = 1; uint32 vrf_id = 2; }`. Public `Network`/`NetworkService.Get/List`
  **не несут** vrf_id. Регистрация в api-gateway — только internal mux.
- **Gate**: фича (новый RPC + поле + миграция) → ban #1 acceptance + ban #12 TDD
  (concurrent-Create уникальность). Кросс-репо: proto → vpc → api-gateway(internal).

## History

- 2026-06-13 — design v1 (isolation via CCNP) **отвергнут**: это микросегментация, не тенантинг.
- 2026-06-13 — design v2: тенантинг через нативный SRv6 VRF (OSS датаплейн + недостающий
  control-plane модулем). Без эпика, vault-only trail. Фаза 1 = VPC→VRF.
- 2026-06-13 — субстрат **зафиксирован: SRv6 VRF** (Linux-VRF и Geneve-VNI отвергнуты).
  Предпосылки стенда: IPv6-underlay + ядро с SRv6 End.DT4/DT6 (≥5.10), `enable-srv6=true`.
- 2026-06-13 — **решение заказчика: Cilium SRv6 вытесняет kube-ovn+Multus** как канон
  data-plane. [[vpc-operator-to-kubeovn]] + [[kube-ovn-to-bgp-fabric]] → `deprecated`
  (контент сохранён для миграции). Acceptance CIL0 (vrf_id) — `docs/specs/sub-phase-CIL0-…`.
  Карта миграции фич kube-ovn→Cilium: см. callout в [[vpc-operator-to-kubeovn]].

## See also

[[../resources/cilium-kachovpc]] [[../packages/kacho-vpc-cilium-compiler]] [[../resources/vpc-network]] [[apigw-to-vpc]]

#edge #cross-service #kacho-vpc #experimental #planned
