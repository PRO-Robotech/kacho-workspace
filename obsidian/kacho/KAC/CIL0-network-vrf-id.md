---
title: "CIL0: Network vrf_id alloc + InternalNetworkService.GetNetwork"
aliases:
  - CIL0
  - network vrf_id
ticket_id: "KAC-<pending>"
category: kac
status: in-progress
type: feature
repos:
  - kacho-proto
  - kacho-vpc
  - kacho-api-gateway
prs:
  - PRO-Robotech/kacho-proto#53
  - PRO-Robotech/kacho-vpc#144
  - PRO-Robotech/kacho-iam#103
  - PRO-Robotech/kacho-api-gateway#69
  - PRO-Robotech/kacho-workspace#75
yt_url: "(pending — нет YouTrack-токена в сессии)"
opened: 2026-06-13
tags:
  - kac
  - feature
  - kacho-vpc
  - experimental
  - planned
---

# CIL0: Network vrf_id alloc + InternalNetworkService.GetNetwork

**Status**: in-progress (acceptance ✅ APPROVED; код — заблокирован окружением)
**Type**: feature (трек **CIL** — Cilium SRv6 data-plane realization)
**Repos**: kacho-proto → kacho-vpc → kacho-api-gateway
**YT**: pending (нет токена; KAC-номер присваивает orchestrator до старта кода — ban #1 gate)

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
- [ ] KAC-номер присвоен (блокер: YouTrack недоступен — ветки `cil0-network-vrf-id`)
- [x] proto: GetNetwork + messages + http `:internal`, buf lint/breaking/gen зелёные (commit ba51a83)
- [x] vpc: миграция 0007 + repo/usecase/handler (commit 1a59089)
- [x] integration RED→GREEN: CIL0-02 concurrency uniqueness + 03/05/13 (testcontainers, -race чисто)
- [x] vpc unit: networkinternal GetNetwork (malformed/valid/notfound)
- [x] golangci-lint v2 — 0 issues; gofmt clean
- [x] iam: permission_catalog 2 зеркала синканы (commit 8534b8d); catalog-тесты зелёные
- [x] api-gateway: routing авто (service-level на vpcInternalAddr) + 3-е зеркало (commit ff1f774)
- [x] newman: 6 кейсов internal-network.py, validate-cases OK, gen зелёный (commit 9f22071)
- [ ] newman E2E прогон против стенда (kind пересобран начисто 2026-06-13)
- [ ] финал govulncheck
- [x] vault-trail: resources/vpc-network, rpc/vpc-internal-network-service, cilium-kachovpc, edges
- [ ] PR'ы (proto→vpc→iam→api-gateway) + status→test/done

## Коммиты (ветки `cil0-network-vrf-id` в каждом репо)

| Репо | Commit | Что |
|---|---|---|
| kacho-proto | ba51a83 | GetNetwork RPC+messages, `:internal` path, regen, catalog |
| kacho-vpc | 1a59089 | migration 0007, repo/usecase/handler, integration+unit |
| kacho-iam | 8534b8d | permission_catalog sync (get_internal) |
| kacho-api-gateway | ff1f774 | catalog mirror sync |
| kacho-vpc (tests) | 9f22071 | 6 newman cases |

## Связанные

Депрекейтит трек OP (kube-ovn): [[../edges/vpc-operator-to-kubeovn]],
[[../edges/kube-ovn-to-bgp-fabric]].

#kac #feature #kacho-vpc #experimental #planned
