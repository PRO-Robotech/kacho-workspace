---
title: KachoVPC (cilium CRD)
aliases:
  - KachoVPC
  - vpc.kacho.cloud KachoVPC
category: resource
domain: vpc
id_prefix: enp
owner_table: "n/a (k8s CRD, не Postgres)"
folder_level: false
status: planned
related_packages:
  - "[[packages/kacho-vpc-cilium-compiler]]"
tags:
  - resource
  - kacho-vpc
  - network
  - experimental
  - planned
---

# KachoVPC (cilium CRD)

**Тип**: data-plane CRD `vpc.kacho.cloud/v1`, cluster-scoped (НЕ Postgres-ресурс).
**Истина**: control-plane [[vpc-network]] (`kacho_vpc.networks`, prefix `enp`).
`KachoVPC` — её проекция, рендерится `kacho-vpc-operator`
(см. [[../edges/vpc-operator-to-cilium-realization]]).

> [!important] VPC = SRv6 VRF (тенантинг), не CCNP-граница (изоляция)
> ipcache Cilium плоский (IP→identity глобально), поэтому политика не даёт тенантинг.
> VPC реализуется как **SRv6 VRF** — отдельный routing-домен с перекрывающимися CIDR.

## Spec (первый cut, фаза 1)

| Field | Type | Note |
|---|---|---|
| `networkId` | string | ref на control-plane Network (`enp…`), истина |
| `clusters` | []string | span VPC по clustermesh (фаза 1: хранится, использ. локальный) |
| `cidrBlocks.ipv4/ipv6` | []cidr | L3-план VRF; **может перекрываться с другими VPC** |
| `vrfId` | uint32 | дименсия тенантинга; **аллоцируется control-plane** (`kacho_vpc.networks.vrf_id`), CRD только несёт |

> [!warning] Качо-id ≠ VRF_ID (формат)
> Network.id = `enp`+17 crockford-base32 (~85 бит, строка); SRv6 VRF_ID = `uint32`
> (`VRFValue.ID`/`PolicyKey.VRFID`/`SIDValue.VRFID`). Прямо использовать нельзя,
> хешировать нельзя (коллизия uint32 = два VPC в одном VRF = пробой тенантинга).
> Решение: `kacho_vpc.networks.vrf_id INTEGER UNIQUE` — атомарная аллокация при Create
> (ban #10, DB-level), reserved `0`. Владелец = control-plane (нужна mesh-global
> уникальность: VRFID входит в ключ SID/policy и в cross-DC L3VPN).

(`isolation`-поле v1 удалено — изоляция теперь by-construction через VRF, не posture.)

## Компиляция → нативный Cilium (фаза 1, single-cluster)

1. **Аллокация VRF_ID** — старшие 32 бита ключа `cilium_srv6_vrf_v4/v6`.
2. **`enable-srv6`** + agent-side SRv6/VRF-manager cell (недостающий в OSS control-plane)
   populating VRF-map из assignment endpoint→VRF (по метке `vpc.kacho.cloud/network`).
3. **SID-аллокация** (locator) на VPC для cross-node/cross-DC L3VPN.
4. clustermesh-scope: `clusters ⊆ mesh` валидируется (`⊄` → `status=Invalid`).

> [!example] DoD-доказательство тенантинга (не deny)
> Два `KachoVPC` с одинаковым `10.0.0.0/16`, поды на одной ноде → трафик разведён по
> VRF, route-leak отсутствует, один IP сосуществует в двух VPC. CCNP для этого не нужен.

## L3-only, без L2

SRv6 = чистый IPv6-underlay L3-encap. Никакого растягивания broadcast-домена;
VPC тянется кросс-ДЦ анонсом SID по BGP (фаза RouteTable).

## Не входит в фазу 1

Subnet-пулы scoped-к-VRF (ф2), CNP intra-VRF (ф3), SID-policy+BGP L3VPN (RouteTable/ф4),
NIC (ф5), multi-NIC (ф6), mesh fan-out (под-фаза 1b).

## See also

[[vpc-network]] [[../packages/kacho-vpc-cilium-compiler]] [[../edges/vpc-operator-to-cilium-realization]]

#resource #vpc #network #experimental #planned
