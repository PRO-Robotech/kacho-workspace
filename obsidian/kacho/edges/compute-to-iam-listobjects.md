---
title: "compute → iam: AuthorizeService.ListObjects"
aliases:
  - compute listobjects
  - compute fga listobjects
category: edge
caller_repo: kacho-compute
callee_repo: kacho-iam
sync_async: sync
protocol: gRPC
status: done
related_tickets:
  - "[[KAC-127]]"
  - "[[compute-list-leak-fix]]"
tags:
  - edge
  - kacho-compute
  - cross-service
  - authz
  - fga
---

# compute → iam: AuthorizeService.ListObjects

**Caller**: `kacho-compute` List handlers (Instance / Disk / Image / Snapshot — 4 public List* RPCs).
**Callee**: `kacho-iam` AuthorizeService.ListObjects ([[../rpc/iam-authorize-service]]).
**Protocol**: gRPC.
**Status**: **Phase 4 planned**. Mirror of [[vpc-to-iam-listobjects]] for compute domain.

## Object types (Phase 4 compute scope)

| Object type | Relation | Phase 4 covered |
|---|---|---|
| `compute.instance` | `read` | yes |
| `compute.disk` | `read` | yes |
| `compute.image` | `read` (per-account + cluster system images) | yes |
| `compute.snapshot` | `read` | yes |
| `compute.disk_type` | catalog (no per-resource ACL — public read) | no, bypass |
| `compute.zone` | catalog | no, bypass |
| `compute.region` | catalog | no, bypass |

## Flow per-request

Identical to [[vpc-to-iam-listobjects]] — see that document for full pattern.

## Compute-specific quirks

- **Images** — dual scope: per-account user images + cluster system images (Ubuntu / Debian базовые). ListObjects merges both via OR-relation `read OR system_read`.
- **Snapshots** — могут принадлежать удалённой Disk (dangling-ref). Phase 4 grace-handles: returns snapshot если access binding на parent disk EVER existed (history tracked).
- **Instances** — параметры `network_interfaces[]` ссылаются на NIC из `kacho-vpc` (см. [[compute-to-vpc-nic-validate]]) — для List мы НЕ перепроверяем NIC permissions (would be O(n*m) lookup); вместо этого instance-level binding достаточен.

## Cache strategy

5s TTL keyed `(user, relation, project_id)` — same as VPC.

## Notes

- Phase 4 covers 4 public lists (Instance, Disk, Image, Snapshot). Catalogs (DiskType/Zone/Region) — public read no authz.
- Internal admin Lists (InternalInstance, InternalDisk) — **DEFERRED** (Phase 4 acceptance §"Out of scope") — proto types ещё не существуют в kacho-proto. Follow-up tracked in KAC-127 trail. (Прежний Hypervisor из этого списка удалён в KAC-36/79/80.)

## Identity source (subject) — единый с per-RPC Check

List handler берёт FGA-subject из **request Principal** (`authzfilter.SubjectFromPrincipal` →
`operations.PrincipalFromContext` → `type:id`), НЕ из gRPC-метадаты `x-kacho-subject*`. Это тот же
источник, что [[compute-to-iam-check]] и эталон kacho-vpc (`pbconv.SubjectFromContext`). **subject=""**
(system principal / нет identity) → **fail-closed** (пустой allow-list → пустой List), никогда не
bypass-all. `filter==nil` (FGA disabled config-gate) — осознанный bypass, не утечка. Cluster-admin/owner
видят всё, т.к. сам ListObjects(viewer) возвращает все id (owner→viewer FGA-каскад); compute-side
header-bypass (`x-kacho-admin`) удалён.

## History

- **2026-06-25 — subject-source over-show leak fix** ([[../KAC/compute-list-leak-fix]], `kacho-compute#65`).
  До фикса subject читался из несуществующих `x-kacho-subject*` → subject="" → `resolveListFilter`
  короткозамыкал на `bypass:true` → List возвращал **все** ресурсы проекта мимо list-authz (verified live
  fe3455). Фикс: principal-based subject + fail-closed на subject="". Acceptance:
  `docs/specs/sub-phase-compute-list-leak-fix-acceptance.md`.

## See also

[[vpc-to-iam-listobjects]] [[api-gateway-to-iam-authorize]] [[iam-to-openfga-check]] [[compute-to-iam-check]] [[../rpc/iam-authorize-service]] [[../packages/corelib-authz-listobjects]] [[../KAC/KAC-127]]

#edge #kacho-compute #cross-service #authz #fga
