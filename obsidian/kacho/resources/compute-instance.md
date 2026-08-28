---
title: Instance (compute) — пересборка 2026
aliases:
  - Instance (compute)
  - compute Instance
  - instances
category: resource
domain: compute
id_prefix: "ins- (hyphen-канон B3; NewHyphenID)"
owner_table: kacho_compute.instances
owner_db: kacho_compute
project_level: false
status: done
verified_against: "ветка release/compute-production-api @ 451a56cd, сверено 2026-08-13 (instance.proto + миграции 0001..0034)"
related_rpc:
  - "[[rpc/compute-instance-service]]"
related_tickets:
  - "[[KAC/compute-redesign-2026]]"
  - "[[KAC/issue-158]]"
related_edges:
  - "[[edges/compute-to-registry-image-resolve]]"
  - "[[edges/compute-to-vpc-nic-validate]]"
  - "[[edges/compute-to-geo-zone-validate]]"
  - "[[edges/compute-to-storage-volume-resolve]]"
tags:
  - resource
  - kacho-compute
  - compute
  - done
---

# Instance (compute) — пересборка 2026

Унифицированный compute-unit: `instanceKind ∈ {VM | CONTAINER | BAREMETAL°growth}`. Держит **intent + read-only зеркала**; attach-state НЕ владеет. Полный дизайн: `docs/plans/compute-module-redesign-2026.md` (воркспейс).

> [!note] Как читать эту записку (сверка со стволом 2026-08-05)
> Она смешивает **замысел** (разделы «reference law», «5 дефектов», two-projection) и
> **сделанное** (раздел «Реализация — COMP-1 core»). Сверено по дереву:
> `proto/kacho/cloud/compute/v1/instance.proto` живой, `services/compute/internal/migrations/`
> дошли до `0026`, `message Instance` несёт `instance_kind`, `machine_type_id`,
> `boot_source`, `effective_resources`, `placement_group_id`, `status_reason` и
> `oneof {vm_spec | container_spec}` — то есть COMP-1 действительно приземлён.
>
> **Из замысла НЕ приземлено и предмета в дереве не имеет**: `InternalInstanceService`
> (его нет ни в proto, ни в карте RPC — из compute-internal живы
> `InternalMachineTypeService` и `InternalWatchService`), а также `PlacementGroup`
> как ресурс (см. предупреждение в [[compute-placementgroup]]).
>
> **Ссылки `[[rpc/compute-instance-service]]` и `[[rpc/compute-machinetype-service]]`
> заведены этой волной** (до неё они висели в пустоту).

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

**Deferred**: COMP-2 (attach-саги/materialize/power-ops/Reinstall), COMP-3 (PlacementGroup spread + ImageCatalog/VolumeType discovery + validateOnly), COMP-4 (Internal\* infra-проекции + legacy-RPC retire). Легаси power-ops (Start/Stop/AttachDisk/…) сохранены рабочими.

## Блочное хранение в compute — РЕТАЙРЕНО, и это удерживается гейтом

> [!important] Дубля Volume/Snapshot/Image/DiskType в compute больше нет
> Перепись по стволу 2026-08-05. Миграции, снявшие дубль:
> `0013_drop_attached_disks.sql`, `0021_drop_block_storage_duplicates.sql`,
> `0022_drop_disk_types.sql`. Перечень живых таблиц, снятый в тот день, был **семь**:
> `instances`, `machine_types`, `instance_network_interfaces`, `operations`,
> `compute_outbox`, `compute_fga_register_outbox`, `compute_watch_cursors`.
>
> > [!warning] Этот перечень УСТАРЕЛ — перемерено 2026-08-28, и в обе стороны
> > `compute_watch_cursors` **снята** — таблица серверных курсоров подписки, у которой
> > не было ни одного прод-читателя за всю жизнь; миграция
> > `20260823221500_drop_watch_cursors.sql`, задача `kacho#1046`, **влито в ствол**.
> > Снята она не за то, что мертва: позиция подписки принадлежит клиенту, и таблица
> > курсоров *по подписчику* читается как указание обратного. Три её сестры у vpc, nlb
> > и iam снимаются задачей [[KAC/issue-1148]].
> >
> > В другую сторону перечень тоже разошёлся: домен с 5 августа вырос. Обход
> > Up-секций миграций на стволе `a9be7df26` даёт **13** живых таблиц — число здесь
> > **ориентир, а не гейт**, предикат грубый (считает `CREATE TABLE` / `DROP TABLE` в
> > Up-секциях цепочки) и назван затем, чтобы его можно было повторить и опровергнуть.
> > Перечень поимённо здесь не переписывается: он не предмет этой записки и разойдётся
> > снова — предмет записки ниже, и он про ретайр блочного хранения.
>
> Удерживает ретайр **гейт** `services/compute/internal/check/retired_block_storage_test.go`
> (и парный в iam). Он проверяет **обе половины**, потому что каждая по отдельности
> оставляет продукт хуже, чем если бы не начинали:
>
> - **достижимость** — ни один REST-маршрут, ни одна запись каталога прав (в **обеих**
>   встроенных копиях), ни один allowlist края, ни один proto-сервис, ни один
>   сгенерённый стаб и ничто в compute не называет снятые authz-типы объектов;
> - **хранилище** — ни один непробный путь compute не шлёт SQL к `disks` / `images` /
>   `snapshots` / `disk_types`.
>
> Формулировка самого гейта стоит цитирования как правило: «поверхность без таблицы
> обещает вызывающему то, чего продукт не может выполнить; таблица без поверхности —
> данные, до которых никто не дотянется и которые никто не поддерживает». История
> миграций из «хранилищной» половины **намеренно исключена** — применённую миграцию не
> редактируют, поэтому `CREATE TABLE` в baseline остаётся и находкой не является.
>
> Раздел «карта владельцев» в `data-integrity.md` несёт предупреждение о незавершённом
> расколе, датированное 2026-07-25; по этому дереву раскол **завершён**. Владелец
> блочного хранения — **storage**.
>
> Также сняты `regions`/`zones` (`0003_geography_owner.sql` → `0011_drop_geography.sql`):
> Geography принадлежит **geo**, и message `Region`/`Zone` в compute-контракте нет.

## Что изменилось волнами 1-3 (2026-08-13, ветка release/compute-production-api)

**Снято с контракта** (номера И имена зарезервированы, буф-ломающее намеренно): восемь
методов — правка интерфейса, две операции NAT, перенос, правка карты данных, три метода
выдачи прав; девять полей машины; поле представления у чтения; **свободная карта
`metadata`** (принималась, писалась в базу и не возвращалась НИКОГДА — читателя ей сняла
волна 1, а приём остался); ручка обязательности сессионного токена (ручка, которой можно
отключить защиту, однажды будет отключена); числовой параметр разнесения.

**Заведено:**

- `guest_access_key_ids` — ссылки на [[resources/compute-guestaccesskey]] по неизменяемым
  идентификаторам; набор заменяется целиком и НЕ входит в состав полей полной правки;
- `placement_group_id` стал настоящей ссылкой на [[resources/compute-placementgroup]]
  (внешний ключ, `ON DELETE RESTRICT`, отсутствие — NULL, а не пустая строка);
  когерентность якоря проверяется ВНУТРИ вставки и правки;
- **наблюдаемое состояние** — отдельные колонки от намерения (`observed_state`,
  `observed_sequence_no`, `observed_at`, `observed_reason`), заполняются только отчётом
  узла на внутреннем слушателе; на публичную проекцию не выходят;
- **владение узлом** — таблица привязки с атомарным обменом и арендой;
- **журнал действий** в той же транзакции, что мутация;
- **предел числа машин на проект** — списывается тем же стейтментом, что вставляет машину.

Trail: [[KAC/compute-redesign-2026]], [[KAC/issue-158]].
Acceptance: `docs/specs/sub-phase-COMP-1-instance-machinetype-acceptance.md`,
`sub-phase-COMP-E1a-acceptance.md`, `sub-phase-COMP-E1b-acceptance.md`.

#resource #kacho-compute #compute #done
