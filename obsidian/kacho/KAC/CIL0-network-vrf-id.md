---
title: "CIL0: Network vrf_id alloc + InternalNetworkService.GetNetwork"
aliases:
  - CIL0
  - network vrf_id
ticket_id: CIL0
tracker: obsidian
category: kac
status: in-progress
type: feature
repos:
  - kacho-proto
  - kacho-vpc
  - kacho-iam
  - kacho-api-gateway
prs:
  - PRO-Robotech/kacho-proto#53
  - PRO-Robotech/kacho-vpc#144
  - PRO-Robotech/kacho-iam#103
  - PRO-Robotech/kacho-api-gateway#69
  - PRO-Robotech/kacho-workspace#75
  - PRO-Robotech/kacho-deploy#77
opened: 2026-06-13
tags:
  - kac
  - feature
  - kacho-vpc
  - experimental
  - planned
---

# CIL0: Network vrf_id alloc + InternalNetworkService.GetNetwork

**Status**: in-progress (acceptance ✅ APPROVED; код + тесты зелёные; PR'ы открыты)
**Type**: feature (трек **CIL** — Cilium SRv6 data-plane realization)
**Repos**: kacho-proto → kacho-vpc → kacho-iam → kacho-api-gateway
**Трекер**: **Obsidian** (этот файл — источник истины; YouTrack не используется).

## Что и зачем

VPC реализуется на Cilium SRv6 VRF (решение 2026-06-13: Cilium вытесняет kube-ovn).
Каждому Network нужен стабильный уникальный `uint32` VRF_ID. Эта фаза — control-plane:
аллокация `vrf_id` (bigint, sequence) при Network.Create + internal-only
`InternalNetworkService.GetNetwork`, отдающий vrf_id. Public Network не меняется
(инфра-идентификатор → только Internal*, `security.md`).

## Артефакты

- Acceptance (✅ APPROVED): `docs/specs/sub-phase-CIL0-network-vrf-id-internal-acceptance.md`
- Plan: `docs/plans/sub-phase-CIL0-network-vrf-id-plan.md`

## Затронутые сущности vault

- [[../resources/cilium-kachovpc]] — VRF_ID dimension, формат (string id ≠ uint32)
- [[../resources/vpc-network]] — +vrf_id (internal-only) — обновить после merge
- [[../rpc/vpc-internal-network-service]] — +GetNetwork — обновить после merge
- [[../edges/vpc-operator-to-cilium-realization]] — родительский дизайн
- [[../packages/kacho-vpc-cilium-compiler]] — потребитель vrf_id (Cilium-сторона)

## DoD-чеклист

- [x] Acceptance APPROVED (gate ban #1)
- [x] Implementation plan
- [x] Трекинг в Obsidian (этот файл; YouTrack не используется), ветки `cil0-network-vrf-id`
- [x] proto: GetNetwork + messages + http `:internal`, buf lint/breaking/gen зелёные (commit ba51a83)
- [x] vpc: миграция 0007 + repo/usecase/handler (commit 1a59089)
- [x] integration RED→GREEN: CIL0-02 concurrency uniqueness + 03/05/13 (testcontainers, -race чисто)
- [x] vpc unit: networkinternal GetNetwork (malformed/valid/notfound)
- [x] golangci-lint v2 — 0 issues; gofmt clean
- [x] iam: permission_catalog 2 зеркала синканы (commit 8534b8d); catalog-тесты зелёные
- [x] api-gateway: routing авто (service-level на vpcInternalAddr) + 3-е зеркало (commit ff1f774)
- [x] newman: 6 кейсов internal-network.py, validate-cases OK, gen зелёный (commit 9f22071)
- [x] newman E2E **GREEN** против стенда: 41 assertions, 0 failed (`make e2e-newman SVC=vpc COLLECTION=internal-network`)
- [x] финал govulncheck (0 vulns в коде)
- [x] vault-trail: resources/vpc-network, rpc/vpc-internal-network-service, cilium-kachovpc, edges
- [x] PR'ы (proto→vpc→iam→api-gateway→deploy→workspace) открыты
- [x] **воспроизводимый e2e-флоу** вшит: `make e2e-newman` (port-forward+seed+newman), не ручной

## Баги, пойманные newman e2e (закрыты)

- **api-gateway route resolution (CIL0-critical):** custom-verb `:internal` маршрут
  отсутствовал в `rest_route_table_gen.go` → authz-mw не находил catalog-entry →
  «no entry for method» deny. Фикс + regression-тест (kacho-api-gateway#69).
- **authz-fixtures wiring:** `setup.sh` не отдавал `existingProjectId` → VPC-сьюты
  ссылались на stale-project. Фикс: `existing*`-алиасы (kacho-workspace#75).
- **newman auth model:** `vpc.networks.delete` требует `admin` на network (cluster-admin
  НЕ каскадит) → cleanup-delete под `jwtAccountAdminA`; get_internal под `jwtBootstrap`.
- **token expiry:** runtime-mint в collection pre-request (kacho-vpc#144) — токены не протухают.

## Коммиты (ветки `cil0-network-vrf-id` в каждом репо)

| Репо | Commit | Что |
|---|---|---|
| kacho-proto | ba51a83 | GetNetwork RPC+messages, `:internal` path, regen, catalog |
| kacho-vpc | 1a59089 | migration 0007, repo/usecase/handler, integration+unit |
| kacho-iam | 8534b8d | permission_catalog sync (get_internal) |
| kacho-api-gateway | ff1f774 | catalog mirror sync |
| kacho-vpc (tests) | 9f22071 | 6 newman cases |

## CIL1 (продолжение трека, 2026-06-13)

Cilium-сторона: новый модуль **`PRO-Robotech/kacho-vpc-cilium`** (genesis на main).
CRD `KachoVPC` spec + чистый `compiler.CompileVRF` (→ `[]VRFEntry`, per-family,
overlapping-CIDR тенантинг). stdlib-only, unit CIL1-01..07 `-race` зелёные.
Acceptance: `docs/specs/sub-phase-CIL1-kachovpc-vrf-compiler-acceptance.md`.
См. [[../packages/kacho-vpc-cilium-compiler]].

**Граница верификации (СНЯТА 2026-06-13):** получен SRv6-capable кластер `fe3455-infra`
(ядро 6.8, Cilium 1.19.4). SRv6 **включён и верифицирован** через AddonValue
`cilium-custom` (`ipv6.enabled` + `extraConfig.enable-srv6`): `SRv6: Enabled`,
5 BPF-map'ов (`cilium_srv6_vrf_v4/v6`, `policy_v4/v6`, `sid`), 151/151 healthy,
argocd Synced. Runbook: [[../runbooks/cilium-enable-srv6-addonvalue]].

## CIL1b — датаплейн-адаптер ВЕРИФИЦИРОВАН (2026-06-13)

`srv6adapter` (`compiler.VRFEntry` → pinned `cilium_srv6_vrf_v4`, LPM, ABI зеркалит
`srv6map.VRFKey4`; импорт только `cilium/ebpf`, **не** кодовую базу cilium → живёт
параллельно). `cmd/srv6-verify` запущен privileged-подом на узле:
```
src=10.99.0.5 dst=10.0.0.0/16 -> vrf=42 ; src=10.99.0.6 dst=10.0.0.0/16 -> vrf=43
tenancy OK: overlapping destCIDR в разных VRF по source-endpoint ; PASS
```
**Тенантинг доказан на живом датаплейне** (overlapping CIDR в двух VRF). Cleanup
выполнен (map=0), cilium 151/151 healthy. PR `PRO-Robotech/kacho-vpc-cilium#1`,
образ `sgroups/kacho-vpc-cilium:cil1b-verify` (логин `sgroups`; prorobotech namespace
требует авторизованного логина). Unit: keyFor layout/overlap/v6-reject.

## CIL2 — node-local reconciler (DaemonSet) ВЕРИФИЦИРОВАН (2026-06-13)

`srv6-controller` (poll-loop, конвенция Kachō без Watch): list `KachoVPC` CRD +
поды узла с меткой `vpc.kacho.cloud/network` → `CompileVRF` → reconcile
`cilium_srv6_vrf_v4` (program desired, delete owned-stale). **Недостающий в OSS
SRv6 control-plane**, параллельно cilium-agent (CRD + RBAC + privileged DaemonSet).
Verified live: 2 KachoVPC (vrf 42/43, overlapping 10.0.0.0/16) + 2 пода →
`reconciled added=2`; pod-delete → `removed=1`; cleanup → map=0; cilium 151/151.
PR `kacho-vpc-cilium#2` (stack на #1), образ `sgroups/kacho-vpc-cilium:cil2-controller`.
DaemonSet оставлен задеплоен (no-op без помеченных подов).

**Дальше:** CIL3 (Subnet → IPAM-пул scoped к VRF — для настоящих overlapping pod-IP),
SID-аллокация + BGP L3VPN (cross-node/DC), SG→CNP intra-VRF, multi-NIC.

## Связанные

Депрекейтит трек OP (kube-ovn): [[../edges/vpc-operator-to-kubeovn]],
[[../edges/kube-ovn-to-bgp-fabric]].

#kac #feature #kacho-vpc #experimental #planned
