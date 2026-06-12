---
title: KachoSubnet (CRD оператора)
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

# KachoSubnet — промежуточный CRD vpc-operator'а

`kacho.io/v1`, **cluster-scoped**. ПЕРВЫЙ собственный CRD оператора (до OP1 источник
истины VPC-ресурсов — БД kacho-vpc через gRPC, своих CRD не было). Зеркало одной
Kachō Subnet 1:1; egress-контур материализует его в N×(kube-ovn Subnet + Multus NAD)
по одному на CIDR. Введён в OP1 (KachoSubnet CRD redesign), см. [[vpc-operator-to-kubeovn]].

## GVK / scope

- Group/Version/Kind: `kacho.io` / `v1` / `KachoSubnet` (plural `kachosubnets`, short `ksub`).
- **scope=Cluster** (обязательно): ownerRef KachoSubnet каскадит И на cluster-scoped
  kube-ovn Subnet, И на namespaced NAD. K8s допускает cluster-owner у namespaced
  dependent, но НЕ namespaced-owner у cluster-scoped dependent → namespaced KachoSubnet
  не смог бы владеть kube-ovn Subnet.
- Имя CR = upstream Subnet id (1:1, ключ корреляции ingress↔egress).

## Spec (зеркало Kachō Subnet, camelCase)

| Поле | Тип | Назначение |
|---|---|---|
| `id` (required) | string | kacho Subnet id (`sub…`); ключ корреляции |
| `projectId` | string | kacho Project id (`prj…`) |
| `networkId` | string | kacho Network id (`net…`) → `spec.vpc` child'а (пусто → `ovn-cluster`) |
| `name` | string | база stable-by-CIDR имён child'ов (пусто → `id`) |
| `v4CidrBlocks` | []string | каждый → 1 single-family kube-ovn Subnet `protocol=IPv4` |
| `v6CidrBlocks` | []string | каждый → 1 single-family kube-ovn Subnet `protocol=IPv6` |
| `projectNamespace` | string | namespace проекта; NAD'ы создаются ИМЕННО в нём |

Оба CIDR-списка пустые — валидно (ноль child'ов, не ошибка). Решение A: combine в
dual-stack `protocol=Dual`/`"v4,v6"` НЕ используется.

## Status

- `observedGeneration` int64.
- `conditions[]` (`Ready`): `False`/`CIDRInUse` (teardown заблокирован реальными
  pod-аллокациями) | `False`/`InvalidCIDR` (битый CIDR в списке) | `True`/`Reconciled`.

## Child naming + ownerRef

- Child kube-ovn Subnet + NAD: имя `<name>-<shorthash(canonical(cidr))>`
  (`netip.ParsePrefix().Masked()` перед хешем; ≤63, усекается base а не хеш).
  **НЕ index-based** — стабильно по содержимому CIDR.
- Каждый child: `SetControllerReference(KachoSubnet)` (controller=true) + labels
  `managed-by`/`project-id`/`upstream-id`/`upstream-name`/`kacho.io/cidr`
  (CIDR в label закодирован DNS-safe: `/`→`_`, `:`→`-`).

## Lifecycle / deletion (gotchas)

- **finalizer** `kacho.io/kachosubnet-teardown` — controller-driven teardown в
  Terminating: контроллер сам удаляет free child'ы (GC по ownerRef не стартует пока
  владелец жив), снимает finalizer когда чисто → GC завершает каскад.
- **in-use guard**: НЕ удалять kube-ovn Subnet child с `.status.v4usingIPs`/
  `.status.v6usingIPs > 0` (kube-ovn **v1.16.1** — имена version-pinned, выверены по
  CRD-схеме чарта в kacho-deploy; gateway/excludeIps не считаются in-use).
- **element-prune fail-safe**: desired-set только из валидных CIDR; битый CIDR не
  удаляет child'ы соседних валидных CIDR.
- NAD прунится только with/after своей Subnet (у NAD своего usingIPs нет).

## Код

- Типы: `kacho-vpc-operator/api/v1/kachosubnet_types.go` (+ `zz_generated.deepcopy.go`).
- CRD: `config/crd/bases/kacho.io_kachosubnets.yaml`; install через `config/dev` overlay + `config/crd`.
- Egress: `internal/controller/kachosubnet_controller.go` (+ `naming.go`, `desired.go`).
- Ingress: `internal/syncer/syncer.go` (`upsertKachoSubnet` / `cleanupOrphanKachoSubnets`).
- Shared: `internal/kubeovn/kubeovn.go`. RBAC: `config/rbac/role.yaml` (ручная) + маркеры в controller.

#resource #kacho-vpc-operator #kube-ovn #experimental
