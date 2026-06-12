---
title: "OP2-P-BGP: subnet routing via kube-ovn-speaker BGP (replaces stripped Vpc.staticRoutes)"
aliases:
  - OP2-P-BGP
ticket_id: KAC-PENDING
category: kac
status: test
type: feature
repos:
  - kacho-vpc-operator
  - kacho-deploy
prs:
  - https://github.com/PRO-Robotech/kacho-vpc-operator/pull/3
  - https://github.com/PRO-Robotech/kacho-deploy/pull/75
yt_url: https://prorobotech.youtrack.cloud/issue/KAC-PENDING
opened: 2026-06-12
tags:
  - kac
  - feature
  - kacho-vpc-operator
  - kacho-deploy
  - kube-ovn
  - experimental
---

# OP2-P-BGP: subnet routing via kube-ovn-speaker BGP

**Status**: test (код + envtest RED→GREEN + golangci-lint зелёные; live-PoC подтверждён на
kind-kacho; KAC# присваивает orchestrator).
**Type**: feature
**Repos**: kacho-vpc-operator (BGP-аннотация на kube-ovn Subnet), kacho-deploy (speaker DS +
GoBGP route-reflector + bgp-up.sh + runbook).
**Branch**: `OP2-P-BGP` (оба репо).
**Acceptance**: `docs/specs/sub-phase-OP2-P-BGP-kubeovn-speaker-acceptance.md` (APPROVED).

## Что и зачем

Под-фаза эпика OP2. `Vpc.spec.staticRoutes` (OP2-P2 + multi-AZ механизм) **стрипается**
kube-ovn v1.16.1 на custom-VPC за ~1-5с (issue kacho-vpc-operator#2). Решение: доставлять
CIDR Kachō-подсетей в маршрутизацию через **BGP (kube-ovn-speaker)**, минуя стрипаемый
`Vpc.spec`. Speaker анонсирует CIDR подсети по аннотации `ovn.kubernetes.io/bgp=cluster`
(её ставит оператор на каждой материализуемой kube-ovn Subnet) → route-reflector учит
маршрут (персистит). Также prod-тир multi-AZ inter-zone L3 (design-doc §3.2).

## Реализовано

- **kacho-vpc-operator**: `internal/kubeovn` — `AnnotationBGP`/`BGPPolicyCluster`/
  `SubnetBGPAnnotations()` (единый источник, S3-05). `applyChild` — field-scoped
  `mergeAnnotations` (parity с `mergeLabels`): Subnet несёт BGP-аннотацию, NAD — нет;
  идемпотентно, без клобера чужих/kube-ovn-дефолтных аннотаций. Withdraw — аннотация уходит
  с объектом на prune/teardown. TDD `internal/controller/bgp_annotation_test.go` (envtest).
- **kacho-deploy**: `argo-apps/kube-ovn/bgp/{speaker.yaml,route-reflector.yaml,README.md}` +
  `scripts/bgp-up.sh` (kind-dev-safe; label gateway-ноды, RR pod-IP → speaker neighbor).
  ASN private 65001/65000; announce-cluster-ip=false; auth опционально через Secret.

## Live-verification (kind-kacho, kube-ovn v1.16.1, 2026-06-12)

- BGP session Established speaker↔RR (S2-01). ✓
- Оператор аннотирует все материализуемые подсети `cluster` (S3-01). ✓
- **Custom-VPC subnet-анонс РАБОТАЕТ** (S4-03 ИСХОД A — главный риск снят): RR учит CIDR
  `192.168.88/89.0/24` (`netrpwd…`), `29.62.0.0/16` (`netnqb…`) + Kachō-NIC /32 (`.88.12`/`.88.39`). ✓
- Маршрут **персистит** ≥60с (S3-03) ≠ стрип `Vpc.staticRoutes` (#2). ✓
- Withdraw на снятие аннотации (S3-04). ✓
- v6-анонс вне scope (стенд `NET_STACK ipv4`) — задокументировано.

## Затронутые сущности vault

- [[vpc-operator-to-kubeovn]] — новый egress-аспект (BGP-аннотация на Subnet) + #2-обход.
- [[kube-ovn-to-bgp-fabric]] — **новое** data-plane ребро (speaker↔RR, BGP/TCP-179, вне mTLS).
- Связано: [[OP2-P2-routetable]] (стрипаемый staticRoutes — мотивация BGP), [[SEC-G-operators-ovn-mtls]] (mTLS только gRPC).

## DoD

- [x] APPROVED acceptance (acceptance-reviewer).
- [x] TDD envtest RED→GREEN (BGP-аннотация) + операторный suite зелёный `-race`.
- [x] golangci-lint зелёный (operator).
- [x] Live-PoC: session Established, custom-VPC CIDR выучен+персистит, withdraw, оператор авто-аннотирует.
- [x] Deploy-манифесты + bgp-up.sh + runbook (kacho-deploy).
- [x] Vault trail (edges + KAC) + acceptance committed.
- [x] PR'ы: kacho-vpc-operator#3, kacho-deploy#75.
- [ ] Merge обоих PR + перевод в Done (orchestrator/owner).
- [ ] (follow-on) Multi-AZ S6 — отдельная под-фаза, gated на §4-решения design-doc.

## Связанные тикеты

- Эпик OP2 (покрытие VPC-ресурсов оператором). Под-фазы: OP1 (KachoSubnet), [[OP2-P2-routetable]], OP2-P-BGP (этот).
- GitHub: kacho-vpc-operator#2 (strip-блокер — мотивация).
