---
title: kacho-vpc-cilium compiler
aliases:
  - vpc cilium compiler
  - cilium-vpc-module
  - srv6 vrf manager
category: packages
repo: cilium
layer: operator-cell
status: experimental
repo_url: "https://github.com/PRO-Robotech/kacho-vpc-cilium"
tags:
  - packages
  - kacho-vpc
  - experimental
  - planned
---

# kacho-vpc-cilium compiler

> [!check] CIL1 реализован (2026-06-13) — репо `PRO-Robotech/kacho-vpc-cilium` (genesis на main)
> CRD `KachoVPC` spec (`apis/vpc.kacho.cloud/v1`) + чистый `compiler.CompileVRF`
> (KachoVPC+endpoints → `[]VRFEntry`, per-family, overlapping CIDR безопасны через
> VRFID = тенантинг). stdlib-only, unit-тесты CIL1-01..07 `-race` зелёные. `pkg/srv6adapter`
> — задокументированная граница (VRFEntry→`srv6map.VRFKey/VRFValue`), **gated на SRv6-ядро**
> (CIL1b). Hive-cell/reconciler — CIL2. Acceptance: `docs/specs/sub-phase-CIL1-…`.

Встраиваемый модуль в Cilium: компиляция CRD `vpc.kacho.cloud/v1` → нативный
**SRv6 L3VPN датаплейн**. Не форк — отдельный Go-модуль, подмешиваемый в Hive
(operator-cell + agent-cell).

## Что делает (control plane для существующего SRv6-датаплейна)

OSS Cilium имеет SRv6 BPF + map'ы (`pkg/maps/srv6map`, cell `srv6map.Cell`,
`enable-srv6`), но **не имеет** control-surface, который их populating. Модуль —
этот недостающий control plane:

- берёт **VRF_ID** (uint32) из `KachoVPC.vrfId` — аллоцирован control-plane
  (`kacho_vpc.networks.vrf_id`, mesh-global-уникально); модуль НЕ аллоцирует;
- assignment endpoint→VRF по метке `vpc.kacho.cloud/network`;
- аллоцирует **SID** (locator) на VPC/subnet;
- пишет `cilium_srv6_vrf_v4/v6`, `cilium_srv6_sid`, `cilium_srv6_policy` через
  провайдеры `srv6map.Cell` (не открывает map'ы напрямую, не трогает `bpf/`);
- driving BGP CP (OSS) для анонса SID/VPN-маршрутов кросс-ДЦ.

## Точка встраивания

```go
// cilium-operator + cilium-agent hive composition
cell.Group(
    srv6map.Cell,             // существующий OSS-провайдер map'ов
    ipam.Cell(), bgp.Cell(),
    kachovpc.Cell(),          // ← единственная строка интеграции
)
```

Паттерн как у `operator/pkg/ipam/cell.go` / `pkg/maps/srv6map/cell.go`.

## Layout

```
kacho-vpc-cilium/
  apis/vpc.kacho.cloud/v1/   # KachoVPC/Subnet/SecurityGroup/RouteTable/NIC
  pkg/compiler/              # чистые функции intent→datapath-намерение (unit без кластера)
    vpc_to_vrf.go            # KachoVPC → VRF_ID + SID alloc (фаза 1)
    subnet_to_ippool.go      # IPAM-пул scoped к VRF (ф2)
    sg_to_policy.go          # CNP intra-VRF (ф3)
    routetable_to_srv6.go    # SID-policy + BGP L3VPN (ф4)
  pkg/manager/               # agent-side SRv6/VRF manager (populating srv6map)
  pkg/cell/cell.go           # watch vpc.* → reconcile VRF/SID/policy + cilium.io CRD
```

## Гарантии «модуль, не переработка»

- 0 изменений в `bpf/`/`pkg/maps/srv6map` ядра — используем существующие провайдеры map'ов.
- `compiler/` — чистые функции, полное unit-покрытие без кластера; `manager`/`cell` — тонкие.
- Удаление модуля = удаление cell'а + CRD; SRv6-датаплейн возвращается в idle (никто не пишет VRF-map).

## See also

[[../resources/cilium-kachovpc]] [[../edges/vpc-operator-to-cilium-realization]]

#packages #kacho-vpc #experimental #planned
