---
title: inservice-authz-scope-parity-2026-07-22
category: kac
tags:
  - kac
  - fix
  - security
  - kacho-storage
  - kacho-registry
status: done
type: fix
---

# In-service authz map must mirror gateway catalog scope+relation (2026-07-22)

**Status**: DONE — production-mode newman (#59). GitHub #62 (storage) + registry-Create + #61 (Image BVA) closed.
**Type**: fix (authz-scope parity + sync BVA)
**Repos**: kacho (monorepo, `redesign/integration`) — services/storage, services/registry
**Trigger**: production-mode newman found a project-scoped `editor` SA got 403 on storage List/Create in its OWN project while VPC/compute honored it.

## Класс дефекта (durable lesson)

Каждый сервис энфорсит authz на ДВУХ плоскостях: api-gateway permission-catalog
(генерится из proto `required_relation`+`scope_extractor`) И собственный in-service
`check.PermissionMap` (defense-in-depth на :9090/:9091, `pkg/authz`). **Оба ОБЯЗАНЫ
резолвить один и тот же (relation, object)** — иначе gateway allow + in-service deny =
403 у легитимного принципала (или наоборот — leak).

Два инстанса этого класса, найдены+пофикшены:

1. **storage (#62)** — in-service `PermissionMap` гейтил ВСЕ tenant-RPC на
   cluster-синглтоне (`cluster:cluster_kacho_root`) через static extractor. Project-scoped
   `editor` (есть `project#editor`, нет cluster-грантов) → 403; bootstrap-суиты маскировали
   через iam cluster-admin short-circuit (FGA-resolve DENY → fallback cluster#system_admin).
   Фикс: List/Create → `project:<project_id>`; object-self Get/Update/Delete/ListOps →
   `storage_<res>:<res_id>` (зеркалит gateway-catalog + compute). DiskType/InternalDiskType/
   ListAttachments остаются cluster (глобальный каталог / admin).

2. **registry (Create)** — in-service Create использовал `v_create@project`, а proto+gateway =
   `editor@project`. iam-реконсайлер материализует `edit@project` как `[editor, v_get, v_list,
   v_update]` — **НЕ v_create/v_delete** (это account-level «создать сам project»). Create-child
   (создать registry В проекте) — это `editor`-tier на РОДИТЕЛЕ (как compute/vpc/storage), не verb.
   Фикс: `domain.FGARelationEditor`; Create → `editor@project`.

## Побочно: #61 sync BVA

Image.Create (+ Volume.Create для парити) не отвергали over-limit `description`(>256)/`labels`(>64)
синхронно → 200 Operation вместо 400. Фикс: `validate.Description`/`validate.Labels` на request-edge
до peer/DB-вызовов (зеркалит остальные ресурсы).

## Newman test-fix (authz-first tolerance)

После #62 empty `projectId` на storage List/Create fail-close 403 (`authz: empty object id`) — как
compute/vpc (проверено live: compute disks/images List no-proj → 403; vpc networks → 403). Cases
`*-VAL-PROJECT-REQUIRED` (strict 400) → `assert_unscoped_rejected()` (oneOf[400,403], code oneOf[3,7]).

## Результат (production-mode)

- storage: **5/7 → 7/7 collections green** (authz 27/0, image 296/0, volume 242/0, snapshot 108/0, …).
- registry: editor Create больше не 403 (доходит до regionId-валидации); main `registry` collection
  в основном зелёный. Остаток (repository-overlay 403/404, `list-ops-bad-token` → 500 вместо 400)
  — отдельный registry-overlay effort.
- compute: machineType self-seed через InternalMachineTypeService работает (создан `mt-` live;
  instance-redesign self-seeds) — «machineType blocker» снят прежним backend-map фиксом 742b49e.

## Затронутые сущности vault

- resources: [[registry-repository]]
- edges: [[storage-to-iam-fgaproxy]]

## Residuals (honest)

- **nlb** production-mode green — нужен `prodseed_nlb_ext` (cross-domain subnet/address/AddressPool/
  instance, placement-coherent, 2 региона, v4/v6/used/cross-project). Отдельный effort (NLB-редизайн).
- **iam** — большинство коллекций user-principal (apiToken/acr step-up) → #59 production-user-gated
  (matrix не чеканит human-User токены by design).
- **registry** — `list-ops-bad-token` → 500 (должно быть 400 InvalidArgument): registry ListOperations
  garbage page-token leak-class bug; repository-overlay (docker-push path) authz — отдельный effort.
