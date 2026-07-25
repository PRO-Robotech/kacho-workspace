---
title: Instance (compute) — пересборка 2026
aliases:
  - Instance (compute)
  - compute Instance
  - instances
category: resource
domain: compute
id_prefix: ins
owner_table: kacho_compute.instances
owner_db: kacho_compute
folder_level: false
status: planned
related_rpc:
  - "[[rpc/compute-instance-service]]"
related_tickets:
  - "[[KAC/compute-redesign-2026]]"
related_edges:
  - "[[edges/compute-to-registry-image-resolve]]"
  - "[[edges/compute-to-vpc-nic-validate]]"
  - "[[edges/compute-to-geo-zone-validate]]"
tags:
  - resource
  - kacho-compute
  - compute
  - planned
---

# Instance (compute) — пересборка 2026

Унифицированный compute-unit: `instanceKind ∈ {VM | CONTAINER | BAREMETAL°growth}`. Держит **intent + read-only зеркала**; attach-state НЕ владеет. Полный дизайн: `docs/plans/compute-module-redesign-2026.md`.

> [!important] Alignment-doc (ban #1) — НЕ код
> Перед реализацией — `acceptance-author` → `acceptance-reviewer` (Given-When-Then APPROVED). Замещает `storage-compute-iaas-overview.md §1` (compute) и разбирает YC-derived cruft текущего `instance.proto` (`platform_id`, `host_affinity_rules{yc.hostId}`, `MetadataOptions{gce_*/aws_*}`, free-form `Resources` — ban #2).

## The reference law (спина дизайна — фикс defect «все ссылки через reference»)
Единообразие **закона**, не wire-формы. 3 класса указателей:
- **A. within-service** (цель в compute-БД) → flat `<x>Id` + **DB FK** (ban #10): `machineTypeId`(RESTRICT), `placementGroupId`(SET NULL), `capabilityKey`. Граф = сама БД.
- **B. scope/placement-координата** (cross-service, фикс. тип, кормит authz-scope/coherence-CHECK) → flat slug/id, peer-validate fail-closed, **hard-fail** (не graceful-dangling): `projectId`, `zoneId`/`regionId`, `serviceAccountId`.
- **C. dependency-указатель** (cross-service на owned-ресурс, читаем name/lineage/status, graceful-dangling, polymorphic, кормит `usedBy`) → forward `reference.Referrer{type,id,name°}` / reverse `reference.Reference{referrer,type,owned}`: `bootSource`, `bootVolume`, `secondaryVolumes[].volume`, `networkInterfaces[].nic`, `usedBy`.

Референсифицировать `machineTypeId`/`zoneId` **отвергнуто** — uniformity-ради-uniformity (спрятало бы FK, сломало coherence). Ноль нового proto (`Referrer` forward / `Reference` reverse — реальные типы).

## 5 дефектов → фиксы
1. **image vs boot_volume** → `bootSource⊘` (polymorphic Referrer: `registry.image`|`storage.snapshot`|`storage.volume`) = ИСТОЧНИК → materialized `bootVolume°` (storage-owned, VM only; CONTAINER = ephemeral rootfs, поля НЕТ). Развязка по lifecycle, не по полю.
2. **digest + tag** → один immutable `bootSourceDigest⊘` (резолв tag→digest на Create через registry, fail-closed); `bootSourceTag°` — provenance-echo, не пин.
3. **placement** → `placementGroupId` (class-A FK) → [[resources/compute-placementgroup]] с композируемыми constraints.
4. **node_selector течёт на гиперы** → `capabilityRequirements[]` над curated `CapabilityVocabulary` (декларируешь ЧТО нужно, не КУДА). Node-targeting **невыразим by construction**; capability→host-label маппинг только на :9091.
5. **ref-разнобой** → the reference law выше.

## Two-projection (security.md)
Public — lean (id/name/labels/bindings/intent/`status(11-state)`). **Internal\*** (`InternalInstanceService.GetInternal`, :9091) — `placement{nodeId,hostClass,nodePoolId,numericInfraId,failureDomainAssignments[],schedulerState}` + `materialization{bootBackend,wiringStatus}` + `fqdn`. Ни одно infra-поле не добавляется на public additively (gateway projection-audit гейтит).

## Lifecycle / gotchas
- Мутации → `Operation` (`epd`). `Update` sizing/capability/placement — **только STOPPED**; immutable-switch ДО UpdateMask.
- `Reinstall` = единственный путь «сменить ОС» (re-pin bootSource → re-materialize boot-Volume).
- `Delete` — crash-safe idempotent saga: MarkDeleting → detach NIC(vpc) → detach volumes(storage, autoDelete honored) → release slot → delete row last.
- `AttachDisk`/`AttachNetworkInterface` — object-scoped authz на **оба** id (anti-BOLA); attach-state у owner'а (storage/vpc), compute — read-only mirror.
- **Ацикличность**: compute зовёт storage/vpc/geo/registry/iam — никто не зовёт compute обратно.
- **Placement-coherence**: Instance⇄Volume⇄NIC одна зона (кроме REGIONAL/anycast); DB-CHECK биконд. `placementType`.
- `Operation.done` = row durable, НЕ downstream-видимость (ban #9).

## Реализация — COMP-1 core (landed 2026-07-20, `project/kacho`)

**Landed** (`services/compute/internal/{domain,repo,service,handler,protoconv}/instance*`, proto `instance*.proto`, migration `0016_instance_redesign.sql`):
- `instanceKind∈{VM,CONTAINER}` oneof `vmSpec`/`containerSpec` (immutable; kind-oneof XOR sync-reject).
- `machineTypeId` **единственный** канал sizing — резолвит `effectiveResources°` из каталога [[resources/compute-machinetype]] (slug ИЛИ имя, canonical `mt-` echo; RETIRED→FailedPrecondition, DEPRECATED ok). `cpuGuaranteePercent{0..100}` family-gated.
- `bootSource{type,id}`+`imageKind°` **form-only** (grammar + type-whitelist `{storage.image,registry.image}` + bare-untagged→400 + output-field-reject). Resolve/materialize (`resolvedDigest°`/`materializedVolume°`) — COMP-2.
- `serviceAccountId` → **class-C `reference.Referrer{iam.service_account}`** (graceful-dangling), per APPROVED acceptance F4. *(Divergence: §reference-law выше числит его class-B hard-fail; acceptance переклассифицировал в class-C — реализация следует acceptance.)*
- vendor-agnostic `metadataOptions{metadataEndpoint,metadataTokenRequired}` под `vmSpec`; **massive vendor-cruft retire** (ban 2): `platform_id`/`resources`/`scheduling_policy`/`gpu_settings`/`reserved_instance_pool_id`/`application`/`metadata_options{gce_*,aws_*}`/`placement_policy`/bare `image` — reserved (buf-breaking намеренный).
- unreachable-guard (VM без ssh И external → FailedPrecondition; `acknowledgeUnreachable` снимает; CONTAINER exempt).
- launch-`*Specs` **skeleton** (`networkInterfaceSpecs` ИЛИ `useDefaultNetwork`; `secondaryVolumeSpecs` structural `sizeGiB>0`) — materialize/attach-саги COMP-2.
- `placementGroupId` opaque passthrough (format-only `plg-`, БЕЗ existence/coherence — COMP-3).
- Create rests **PROVISIONING** (durable). Update mutability-классы (LIVE / next-boot deferred `statusReason "takes effect on next boot"` / immutable camelCase / Reinstall-only bootSource / **STOPPED-gate always-reject** — STOPPED недостижим до COMP-2 `Stop`). Delete **hard-delete + name-recycle** (partial `UNIQUE(project,name) WHERE name<>''`). id-prefix `ins-` (B3).
- **compute НЕ реализует storage внутри себя**: 0 новых Image/Volume-таблиц, 0 новых зависимостей на legacy compute-owned `fd8`-Image; ссылки на storage/registry/iam — только Referrer.

**Deferred**: COMP-2 (attach-саги/materialize/power-ops/Reinstall), COMP-3 (PlacementGroup spread + ImageCatalog/VolumeType discovery + validateOnly), COMP-4 (Internal\* infra-проекции + legacy-RPC retire + `fd8`-Image full retire). Легаси power-ops (Start/Stop/AttachDisk/…) сохранены рабочими до COMP-2/4.

Trail: [[KAC/compute-redesign-2026]]. Acceptance: `docs/specs/sub-phase-COMP-1-instance-machinetype-acceptance.md`.

#resource #kacho-compute #compute #planned
