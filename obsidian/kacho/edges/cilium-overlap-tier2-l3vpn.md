---
title: "VPC overlap на Cilium — решение (Tier 2 / real L3VPN)"
category: edge
tags:
  - edge
  - kacho-vpc
  - experimental
  - srv6
  - cilium
---

# VPC overlap на Cilium — определённое решение

Вопрос: могут ли два Kachō Network иметь **перекрывающиеся CIDR** (один pod-IP в двух VPC), изолированные VRF.

## Корень ограничения

ipcache Cilium keyed = `PrefixCluster` = **(IP-prefix, cluster-id)** — внутри одного
кластера только по IP. Два endpoint'а с одним IP невозможны. IPAM (даже свой) выбирает
*какие* IP, но overlap не решает — это **слой ipcache/датаплейна**, не IPAM. Подтверждено
эмпирически: multi-pool-аллокатор не выдаёт перекрывающиеся CIDR; «overlap», что работает
(CIL1b) — перекрытие **dest-CIDR** в SRv6 VRF-map (routing target), НЕ source/pod-IP.

## Tiers (решение)

- **Tier 1 (default, ship today, no fork):** control-plane Kachō как источник истины IPAM
  выдаёт каждому Network **непересекающийся** срез глобального плана; изоляция — VRF (SRv6),
  адресация — multi-pool/custom-IPAM. «Overlap» = исключён координацией. С IPv6 — практически
  безлимит. CIL0-3 это дают. Стандарт продакшна.
- **Tier 2 (chosen для настоящего overlap) — real L3VPN, underlay/overlay split:**
  - **underlay** = уникальный primary cilium-IP (eth0, в ipcache, как есть).
  - **overlay** = tenant-NIC (net1) с IP из CIDR VPC — **перекрывается**; в ipcache Cilium НЕ
    попадает (живёт в НАШЕМ SRv6 VRF-датаплейне).
  - **VRF по ingress-endpoint (интерфейсу), НЕ по srcIP** — иначе перекрывающиеся src
    коллизируют в VRF-map. Наш BPF на tenant-NIC тегирует VRF по endpoint-id.
  - forwarding overlay — целиком в наших VRF/SID/policy-map'ах (overlap-safe, VRF-keyed) +
    SRv6 encap/`End.DT4/DT6` cross-node.
  - **«модуль, не форк»**: cilium держит underlay; наш модуль — overlay (tenant-NIC + SRv6
    BPF через `CiliumDatapathPlugin` + custom-IPAM). ipcache cilium не трогаем.
  - закрывает СРАЗУ: overlap + multi-NIC (№4, tenant-NIC) + fixed-IP NIC (№5, custom-IPAM).
- Tier 3 (cluster-per-tenant): ipcache несёт cluster-id → overlap между кластерами; тяжело,
  cross-VPC routing конфликтует с clustermesh.

## Компоненты Tier 2 (порядок постройки)

1. **overlay-IPAM** (`pkg/overlayipam`, ✅ unit-`race`): per-VRF адресные пространства,
   один IP в разных VRF одновременно (overlap-инвариант), fixed-IP. Фундамент.
2. **tenant-NIC injection** (CNI-chain/webhook) — net1 с overlay-IP (= multi-NIC №4).
3. **наш SRv6 BPF** (`CiliumDatapathPlugin`) — endpoint→VRF tagging + SID/policy + decap;
   e2e на стабильном **≥2-узловом** стенде (single-node не покрывает cross-node L3VPN).

## Статус / границы

- overlay-IPAM ✅ (PR `kacho-vpc-cilium#4`). SRv6 VRF steering ✅ (CIL1b/CIL2, live).
- Датаплейн-BPF (endpoint→VRF, decap) — отложен: высокий риск live, нужен стабильный 2-узел.
- **Инцидент 2026-06-14**: ноды флапали по `Unauthorized` (SA-токен при ротации control-plane,
  ребут восстановил) — НЕ datapath-конфиг. Урок: live-эксперименты с cilium на managed-кластере
  — осторожно; тяжёлый BPF-эпик делать на изолированном/стабильном стенде.

См. [[vpc-operator-to-cilium-realization]], [[../packages/kacho-vpc-cilium-compiler]],
[[../runbooks/cilium-enable-srv6-addonvalue]].

#edge #kacho-vpc #experimental #srv6 #cilium
