---
title: "OP2-P2: KachoRouteTable CRD + RouteTable → Vpc.staticRoutes materialization"
aliases:
  - OP2-P2
  - OP2-P2-routetable
ticket_id: KAC-PENDING
category: kac
status: superseded
verified_against: "предмет сверен с PRO-Robotech/kacho@58913d0e (2026-08-05); текст записки построчно не пересматривался"
type: feature
repos:
  - kacho-vpc-operator
  - kacho-deploy
prs: []
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

# OP2-P2: KachoRouteTable CRD + RouteTable → Vpc.staticRoutes

> [!warning] Предмет проверен по дереву 2026-08-05 (`PRO-Robotech/kacho@58913d0e`) — записка переведена в историю
> в дереве монорепо нет ни операторного каталога (0 файлов по имени компонента), ни CRD
> `KachoRouteTable`/`KachoVpc` (0 вхождений). След оператора в правах снят миграцией
> `services/iam/internal/migrations/0076_retire_operator_dead_fanout.sql`. Тот же замер — у
> [[SEC-G-operators-ovn-mtls]] и [[OP3-MULTIAZ]]. Текст ниже оставлен как есть: разбор верен как прошлое.
> Правило закрытия — [[KAC/README]].

**Состояние на момент записи**: test (код готов, `go test ./... -race` + golangci-lint + envtest зелёные; KAC#
присваивает orchestrator).
**Type**: feature
**Repos**: kacho-vpc-operator (код CRD + ingress + egress), kacho-deploy (CRD/RBAC install — out-of-band).
**Branch**: `OP2-P2-routetable` (kacho-vpc-operator).
**Acceptance**: `docs/specs/sub-phase-OP2-P2-routetable-staticroutes-acceptance.md` (APPROVED).

## Что и зачем

Под-фаза эпика OP2 (покрытие VPC-ресурсов оператором). Материализует Kachō RouteTable →
kube-ovn `Vpc.spec.staticRoutes[]` через промежуточный CRD `KachoRouteTable` (parity с OP1
KachoSubnet): два контура (ingress poll-reflect, egress controller-runtime Reconciler).
Целевой sink — тот же Vpc, что держит Network-ingress → **field-scoped + element-scoped merge**
(никогда whole-spec/whole-array replace, иначе OCC hot-loop, прецедент OP1). НЕТ ownerRef-
каскада (staticRoutes — под-поля Vpc); teardown = finalizer + element-prune.

## Реализовано

- `api/v1/kachoroutetable_types.go` — CRD (cluster-scoped, spec зеркало 1:1, status
  conditions + observedRoutes + materializedRoutes applied-state, printcolumns) + deepcopy + CRD-манифест.
- `internal/controller/route_desired.go` — desired-union builder (multi-RT aggregation, дедуп,
  детерминированный conflict-winner, gatewayId/invalid классификация). + unit-тесты.
- `internal/controller/kachoroutetable_controller.go` — egress Reconciler (field/element-scoped
  merge, owned-union prune через status.materializedRoutes, retry-on-conflict, finalizer-teardown,
  degraded-conditions). + envtest (12 сценариев).
- `internal/syncer/route_ingress.go` — ingress 1:1 reflect RouteTable → CR (БЕЗ zone-filter —
  network-global), orphan-cleanup, fail-closed listErr. + unit-тесты.
- `internal/upstream/client.go` — RouteTableSvc клиент. `cmd/main.go` — wiring egress.
- RBAC: kubebuilder-маркеры kachoroutetables(all) + vpcs(get;list;watch;update;patch — least-priv,
  без create/delete); hand-maintained `config/rbac/role.yaml` синхронизирован; CRD в `config/crd`
  (config/dev ссылается на ../crd-директорию — авто-pickup). role.yaml остаётся out-of-band.
- envtest testdata: `internal/controller/testdata/crds/kubeovn.io_vpcs.yaml`.

## Затронутые сущности vault

- [[resources/kacho-vpc-operator-KachoRouteTable]] (новый CRD-контракт)
- [[edges/vpc-operator-to-kubeovn]] (новый OP2-P2 поток + история)
- [[resources/kacho-vpc-operator-KachoSubnet]] (parity-референс, OP1)

## DoD

- [x] CRD cluster-scoped, camelCase, printcolumns, status subresource — ставится в live-кластер.
- [x] ingress 1:1 reflect (create/update/delete), no zone-filter, fail-closed listErr.
- [x] egress field/element-scoped merge; multi-RT union + дедуп + детерминированный conflict.
- [x] element-prune (cidr,nextHopIP) — только свои; foreign/base spec нетронуты.
- [x] gatewayId→GatewayUnresolved; invalid CIDR/next-hop→InvalidRoute; нет Vpc→VpcNotFound+requeue.
- [x] finalizer-teardown без ownerRef + dedup-aware.
- [x] field-scoped no-clobber RED→GREEN (envtest mechanics; реальный hot-loop — живой стенд, как OP1).
- [x] `go test ./... -race` + golangci-lint + `make manifests generate` (no drift) зелёные.
- [ ] PR-ссылка + KAC# (orchestrator).
- [ ] Живой стенд: 0 OCC-конфликтов после RouteTable-материализации (S4, ручной чек как OP1).

## Связанные

- Эпик OP2 (kacho-vpc-operator покрытие VPC-ресурсов). Предшественники: OP1 (KachoSubnet),
  OP2-P0 (NIC-webhook fix). Зависит: [[KAC/SEC-G-operators-ovn-mtls]] (mTLS не тронут).
- gatewayId-next-hop gated на Gateway-фазу P4 (резолв gatewayId→IP).

#kac #feature #kacho-vpc-operator #kube-ovn #experimental
