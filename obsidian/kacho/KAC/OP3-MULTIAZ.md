---
title: "OP3-MULTIAZ: cross-zone pod L3 within a VPC across 2 zonal kind clusters + isolation"
aliases:
  - OP3-MULTIAZ
ticket_id: KAC-PENDING
category: kac
status: test
type: feature
repos:
  - kacho-vpc-operator
  - kacho-deploy
prs:
  - https://github.com/PRO-Robotech/kacho-vpc-operator/pull/4
  - https://github.com/PRO-Robotech/kacho-deploy/pull/76
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

# OP3-MULTIAZ: cross-zone within-VPC L3 + isolation

**Status**: test (live end-to-end PROVEN; envtest+lint green; KAC# присваивает orchestrator).
**Repos**: kacho-vpc-operator (zone-aware operator + direct-OVN cross-routes), kacho-deploy (zonal clusters + operator bring-up).
**Branch**: `OP3-MULTIAZ` (оба репо). **Acceptance**: `docs/specs/sub-phase-OP3-MULTIAZ-cross-zone-vpc-acceptance.md` (APPROVED).

## Что и зачем

Цель: опорный kind = control-plane (Kachō компоненты); 2 зональных kind (zone A/B) =
data-plane с операторами; поды zone A ↔ zone B видят друг друга **в рамках одного VPC**
(Kachō Network), вне VPC — изоляция. Топология: один VPC-name = N независимых OVN LR
(не растянутый L2); cross-zone = routed L3 через общий underlay-бридж.

## Реализовано (оператор автоматизирует)

- **syncer** cross-cluster (NodePort control-plane :9090 + SEC-G mTLS, SERVERNAME pin):
  Subnet→KachoSubnet с `zone_id` (read-all всех зон).
- **zone-filter** материализации (`KACHO_VPCOPERATOR_ZONE_ID`): своя зона материализует
  kube-ovn Subnet+NAD, чужую — нет.
- **interconnect**: underlay-transit Subnet (`u2oInterconnection`, full bridge /16,
  u2oIP `172.31.0.<transitHost>` per zone из `KACHO_VPCOPERATOR_ZONES`) — дверь LR на
  бридж; **cross-routes ПРЯМО в OVN-NB** (`ovn-nbctl` exec в ovn-central, пакет
  `internal/ovnnb`) на remote /18 той же Network. НЕ пишет `Vpc.spec.staticRoutes`
  (kube-ovn#2 flaky-стрип + конфликт). owned-set diff (next-hop ∈ transit-IP зон).
- Изоляция структурна: cross-route только same-Network remote /18; single-zone VPC без transit.

## Live-результат (2026-06-13)

3 kind (`kacho`/`kacho-zonea`/`kacho-zoneb`), операторы РАБОТАЮТ непрерывно:
- оператор сам программирует cross-routes в OVN-NB; `Vpc.spec` пуст; LR-route стабилен.
- pod zoneA `192.168.88.2` ↔ zoneB `10.80.64.2` (VPC `netrpwd…`) — **0% loss bidirectional, стабильно**.
- single-zone VPC `netnqb…` — изолирован.

## Документация

- docs-site (Docusaurus 3) `kacho-vpc-operator/docs-site/` — **канонический** реф: конвертация
  Kachō VPC→kube-ovn/OVN (`architecture/conversion`) + max-detail multi-AZ interconnect со
  стендозависимыми переменными (`architecture/interconnect`) + reference/{kachosubnet,nic-attach,variables}.
  Build green, 0 broken links. Plain `docs/` (implementor) — dev-обзор, ссылается на docs-site.

## Затронутые сущности vault

- [[vpc-operator-to-kubeovn]] — zone-filter + interconnect (transit u2o + direct-OVN cross-route) аспект.
- [[kube-ovn-to-bgp-fabric]] — родственное (OP2-P-BGP); здесь underlay-transit, не BGP.
- Связано: [[OP2-P-BGP]] (mechanism research), [[SEC-G-operators-ovn-mtls]] (cross-cluster mTLS).

## DoD

- [x] APPROVED acceptance.
- [x] Оператор: ZoneID + Zones + zone-filter + transit(/16 u2o) + direct-OVN cross-route. envtest+unit RED→GREEN, lint green.
- [x] Deploy: zonal kind + `multiaz/operator-up.sh` (cross-cluster mTLS + pods/exec RBAC).
- [x] Live: 0% loss bidirectional cross-zone within VPC + isolation, операторы непрерывно.
- [x] PR'ы: kacho-vpc-operator#4, kacho-deploy#76.
- [ ] Merge + Done (orchestrator/owner).
- [ ] Prod-hardening (не блокер): full SSA, per-VPC VLAN (несколько multi-AZ VPC), pod remote-route через webhook NIC-attach, libovsdb вместо ovn-nbctl exec, fresh-stand reproducibility.

## Связанные

GitHub: kacho-vpc-operator#2 (kube-ovn strip — мотивация direct-OVN). Эпик OP2/OP3 (покрытие VPC оператором).
EOF
echo "trail written"