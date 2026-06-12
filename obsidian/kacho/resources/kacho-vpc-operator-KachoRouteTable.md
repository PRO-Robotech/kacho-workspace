---
title: KachoRouteTable (CRD оператора)
category: resource
domain: vpc
id_prefix: n/a
owner_table: n/a (k8s CRD, не Postgres)
folder_level: cluster
status: experimental
related_rpc: []
related_packages:
  - kacho-vpc-operator-controller
tags:
  - resource
  - kacho-vpc-operator
  - kube-ovn
  - experimental
---

# KachoRouteTable — промежуточный CRD vpc-operator'а

`kacho.io/v1`, **cluster-scoped**. ВТОРОЙ собственный CRD оператора (после
[[resources/kacho-vpc-operator-KachoSubnet]]). Зеркало одной Kachō RouteTable 1:1;
egress-контур материализует её маршруты **field-scoped** в `Vpc.spec.staticRoutes[]`
целевого Network'а. Введён в OP2-P2, см. [[edges/vpc-operator-to-kubeovn]].

## Spec (зеркало Kachō RouteTable 1:1, camelCase)

- `id` (required) — kacho RouteTable id (`enp…`); имя CR = id; ключ корреляции ingress↔egress.
- `projectId`, `networkId` — kacho Project/Network id. `networkId` → имя целевого Vpc
  (`kubeovn.VpcNameFor`). Пустой networkId → degraded `VpcNotFound` (нет Vpc).
- `name` — человекочитаемое (наблюдаемость; в ключе маршрута не участвует).
- `staticRoutes[]` — `{ destinationPrefix (CIDR), nextHopAddress?, gatewayId?, labels? }`.
  Пустой `staticRoutes=[]` валиден (RouteTable без маршрутов → ноль наших элементов).

## Status

`observedGeneration`, `observedRoutes` (число материализованных валидных маршрутов
ЭТОГО RT, printcolumn `Routes`), `conditions[]` (тип `Ready`), `materializedRoutes[]`
(applied-state: ключи `<cidr>|<nextHopIP>`, записанные этим RT — для element-prune).
Reasons: `Reconciled` / `GatewayUnresolved` / `RouteConflict` / `InvalidRoute` / `VpcNotFound`.
Printcolumns: Network, Routes, Ready, Age.

## Маппинг → Vpc.staticRoutes (egress)

`StaticRoute{destinationPrefix, nextHopAddress}` → `Vpc.staticRoutes{cidr, nextHopIP}`.
`policy/ecmpMode/bfdId/routeTable` НЕ выставляются оператором — kube-ovn дефолтит их
(live: `policy=policyDst` на наш же элемент). Целевой Vpc = `VpcNameFor(networkId)` (тот
же, что держит Network-ingress) — **разделяемый** объект.

## Gotchas / инварианты (≠ KachoSubnet)

- **НЕТ ownerRef-каскада** — staticRoutes это под-поля одного Vpc (владелец — Network-ingress),
  не отдельные объекты. ownerRef на элемент массива невозможен. Teardown =
  finalizer `kacho.io/kachoroutetable-teardown` + **element-prune** (снять ровно свои элементы).
- **field-scoped + element-scoped merge** в Vpc — НИКОГДА whole-spec/whole-array replace
  (иначе передефолт kube-ovn → OCC hot-loop, прецедент OP1 ~1877 конфл/мин). Базовый spec
  Vpc, чужие элементы и kube-ovn-дефолты наших элементов сохраняются (reuse существующего
  элемента по ключу). retry-on-conflict.
- **owned-route identity** = `(cidr, nextHopIP)`; `policy` — **observe-only** (kube-ovn
  дефолтит, матч по policy спровоцировал бы leak/double-write). Элемент структурно неотличим →
  applied-state в `status.materializedRoutes`; prune = (∪ materializedRoutes live-RT ∪
  desired) \ desired; foreign (ключ ∉ owned) не трогаются.
- **multi-RT aggregation** — Network ↔ много RouteTable, один `Vpc.staticRoutes[]` → AGGREGATE
  union всех RT того же networkId (НЕ default-RT only). Дедуп идентичных; конфликт (один cidr,
  разный nextHop) → детерминированный winner `(routeTableId,cidr,nextHopIP)`, проигравший →
  degraded `RouteConflict`. dedup-aware teardown.
- **gatewayId next-hop** → degraded `GatewayUnresolved` + skip (gated Gateway-фаза P4).
  **invalid CIDR / оба-или-ни-одного next-hop** → degraded `InvalidRoute` + skip (prune-fail-safe).
- RBAC vpcs egress — **least-priv** get/list/watch/update/patch (БЕЗ create/delete: Vpc —
  владение Network-ingress).

#resource #kacho-vpc-operator #kube-ovn #experimental
