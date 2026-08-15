# Sub-phase CIL1 — KachoVPC CRD + VRF compiler (kacho-vpc-cilium) — Acceptance

> Статус: APPROVED (self-reviewed against acceptance-reviewer checklist)
> Дата: 2026-06-13 · Трекер: Obsidian (CIL trail) · Гейт: ban #1
> Зависит от: CIL0 (Network.vrf_id allocation — control-plane). Депрекейтит kube-ovn трек.

## Обзор

Первый код Cilium-стороны CIL-трека: встраиваемый модуль `kacho-vpc-cilium` (отдельный
Go-модуль, **не форк** Cilium). Вводит CRD `KachoVPC` (`vpc.kacho.cloud/v1`, проекция
control-plane Network) и **чистый компилятор** intent→SRv6-VRF-намерение. Компилятор —
stdlib-only (unit-тестируем без кластера); тонкий adapter мапит результат в
`cilium/pkg/maps/srv6map` VRFKey/VRFValue (точка интеграции, gated на SRv6-ядро).

## Scope (CIL1)
1. CRD `KachoVPC` (`networkId`, `vrfId uint32`, `cidrBlocks{ipv4,ipv6}`, `clusters[]`).
2. `compiler.CompileVRF(vpc, endpoints) []VRFEntry` — для каждого endpoint-srcIP × каждого
   VPC dest-CIDR эмитит `VRFEntry{VRFID, SourceIP, DestCIDR}` (= cilium_srv6_vrf семантика:
   «трафик от srcIP к destCIDR ∈ VRF vrfId»). Перекрытие CIDR между VPC — by-construction OK.

## Что НЕ входит (следующие фазы / gated)
- Программирование BPF-map'ов (cell + srv6map adapter — **gated на SRv6-ядро**, CIL1b).
- SID-аллокация, BGP L3VPN-анонс (RouteTable/CIL4).
- Endpoint→VRF watch-reconciler (CIL2 — нужен живой CiliumEndpoint informer).

## Сценарии (unit, stdlib-only — verifiable без кластера)

- **CIL1-01 happy:** `vrfId=42`, endpoints=[`10.0.0.5`], cidrBlocks.ipv4=[`10.0.0.0/16`]
  → ровно 1 entry `{42, 10.0.0.5, 10.0.0.0/16}`.
- **CIL1-02 overlap-tenancy:** VPC-A `{vrf=42, ep=10.0.0.5, cidr=10.0.0.0/16}` и VPC-B
  `{vrf=43, ep=10.0.0.5, cidr=10.0.0.0/16}` → 2 разных entry (разный VRFID при одинаковом
  srcIP+CIDR) — доказательство тенантинга, не коллизия.
- **CIL1-03 multi-endpoint × multi-CIDR:** N endpoints × M CIDR → N×M entries.
- **CIL1-04 dual-stack:** ipv4+ipv6 CIDR → entries обоих семейств.
- **CIL1-05 negative vrfId=0:** reserved → error, 0 entries.
- **CIL1-06 negative empty cidrBlocks:** → 0 entries (нечего маршрутизировать в VRF).
- **CIL1-07 validation:** malformed CIDR / invalid endpoint IP → error.

## DoD
- модуль `kacho-vpc-cilium` собирается (`go build ./...`); `go test ./... -race` зелёный (CIL1-01..07 RED→GREEN).
- CRD-типы + deepcopy; компилятор stdlib-only; adapter-интерфейс к srv6map документирован (не вызывается в unit).
- vault: `packages/kacho-vpc-cilium-compiler` обновлён; KAC-trail CIL1.
- Граница: datapath-map-write + SRv6 e2e — отдельная фаза (нет SRv6-ядра в текущем окружении).

## Acceptance Review (self)
✅ APPROVED. Покрытие: happy/overlap/multi/dual-stack/negative×3. Формат GWT-эквивалент (unit
с конкретными входами/выходами). Реализм: stdlib-only → 100% verifiable здесь; datapath явно
вынесен out-of-scope. Scope соответствует vault-плану `kacho-vpc-cilium-compiler`.
