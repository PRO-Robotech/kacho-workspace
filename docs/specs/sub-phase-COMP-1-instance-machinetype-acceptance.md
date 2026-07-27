# Sub-phase COMP-1 (Instance core + MachineType) — Acceptance

> Статус: **✅ APPROVED** (recorded by acceptance-reviewer verdict) (ре-ревью раунд 1 — адресованы 2 блокирующих + minor от acceptance-reviewer; 5 OQ разрешены как зафиксированные дефолты, см. §Дефолты, зафиксированные на review)
> Дата: 2026-07-20
> Ревьюер: acceptance-reviewer
> Эпик/тикет: KAC-COMP-1 (пересборка-2026, Phase-2 step 9 — `kacho-compute` ЭТАЛОН-ЯКОРЬ; зависит от vpc+geo+registry+storage+iam)
> Монорепо: `project/kacho` (`github.com/PRO-Robotech/kacho`) — легаси `project/kacho-*` не затрагивается.

## Обзор

COMP-1 — первый инкремент редизайна **`kacho-compute`**, ЭТАЛОН-ЯКОРЯ свода-2026.
Приводит **`Instance`** (единственный вычислительный ресурс) к целевому tenant-facing
дизайну (`docs/plans/kacho-redesign-2026/module-compute.md`) и общему хребту
(`00-unified-system-design.md` §1 conv-1/2/7/8/11/12, §5 инв-1/5/6) и вводит **`MachineType`** —
sync-каталог единственного канала sizing. COMP-1 — **массовый retire YC-cruft** легаси-инстанса:
`platform_id` / raw `ResourcesSpec{cores,core_fraction,gpus}` / `MetadataOptions{gce_*,aws_*}` /
`HostAffinityRule{yc.hostId}` / `scheduling_policy{preemptible}` / `gpu_settings` /
`reserved_instance_pool_id` / `application` — сносятся с публичной поверхности (ban #2), а размер
и boot-модель переводятся на **один канал** (`machineTypeId`) и **один вход ОС** (`bootSource{type,id}`
с `imageKind`-дискриминатором storage.image ≠ registry.image, B13).

COMP-1 — это **core-ресурс + каталог**: `Instance` как durable control-plane-запись с новой
identity/sizing/boot/kind-моделью + `MachineType` sync-каталог. **One-shot launch задан как
SKELETON**: launch-`*Specs` (NIC/Volume/ssh) на `Create` **принимаются и структурно валидируются**,
но реальные **attach-саги** (compute→vpc IPAM/NIC, compute→storage boot-Volume/secondary materialize,
compute→registry pull-resolve), **compensation-outbox** (B12), output-зеркала `networkInterfaces°`/
`secondaryVolumes°`/`bootSource.resolvedDigest°`/`materializedVolume°`, **power-ops** и **Reinstall** —
вынесены в **COMP-2** (§Декомпозиция / §Out-of-scope). `PlacementGroup` (spread-ось), `ImageCatalog`/
`VolumeType` discovery, `validateOnly:true` — **COMP-3**.

Заказчик к approve контракта не подключается — approve выставляет `acceptance-reviewer`; заказчик
проверяет только финальный smoke/e2e (DoD §e2e-smoke).

---

## Декомпозиция редизайна `kacho-compute` на под-фазы (COMP-1..N)

| Под-фаза | Deliverable (end-to-end) | Ключевое | Статус |
|---|---|---|---|
| **COMP-1** | **`Instance` core (identity/sizing/boot/kind) + `MachineType` sync-каталог** | `instanceKind∈{VM,CONTAINER}` oneof `vmSpec`/`containerSpec`; `machineTypeId` единственный канал sizing (retire raw `ResourcesSpec`/`platform_id`); `bootSource{type,id}`+`imageKind` (B13); `serviceAccountId` class-C `Referrer` (B2); unreachable-guard; **massive YC-cruft retire** (ban #2); launch-`*Specs` **SKELETON** (форма+структурная валидация, саги — COMP-2); `ins-` prefix (B3); CRUD + Update-mutability + List (listauthz+pagination-validate) | **этот док** |
| **COMP-2** | **One-shot launch attach-саги + compensation-outbox (B12) + power-ops + Reinstall** | Реальные `compute→vpc` (IPAM Address alloc + NIC `SetReference` CAS) / `compute→storage` (boot-Volume + secondary materialize) / `compute→registry` (tag→digest resolve + pull-grant precheck) саги в ОДНОЙ `Operation`; **compensation `Free`/`Delete` в `compute.compensation_outbox`** + sweeper-backstop (unified §5.4 B12); output-зеркала `networkInterfaces°`/`secondaryVolumes°`/`bootSource.resolvedDigest°`/`materializedVolume°`; `Start`/`Stop`/`Reboot` (atomic power-cycle)/`Reinstall`; STOPPED-gate **энфорсмент**; `GetInstanceOutput` (log/console); `zoneId` вывод из subnet.zone | follow-up |
| **COMP-3** | **`PlacementGroup` (spread-ось) + `ImageCatalog`/`VolumeType` discovery + `validateOnly`** | `PlacementGroup.spread∈{ZONE_SPREAD,HOST_SPREAD,PARTITION,PACK}` (derived `placementType°`, `maxSkew`, REQUIRED/PREFERRED, `members[]`, scheduler zone-assign для REQUIRED ZONE_SPREAD); `ImageCatalogService.List` (thin-проекция над `storage.image`+`registry.image`) + `VolumeTypeService.List`; `validateOnly:true` sync dry-run (bookability/coherence/satisfiability/pull-grant, БЕЗ STOPPED-gate); `CapabilityVocabularyService` + `requiredCapabilities` (gpu.* mutual-exclusion) | follow-up |
| **COMP-4** *(опц.)* | **Internal* infra-проекции + легаси-RPC deprecation + `fd8`-Image полный ретайр** | `InternalHostAffinityService` + node/host/scheduler/underlay/`topologyKey` проекции Instance (:9091); снос легаси RPC (`UpdateMetadata`/`AddOneToOneNat`/`Relocate`/`SimulateMaintenanceEvent`/`AttachFilesystem`/`reserved_instance_pool`/`gpu_cluster`); **полный ретайр compute-owned `fd8`-`Image`/`Snapshot`** → `ImageCatalog` как проекция над `storage.image` (координация STOR-1/STOR-2) | deferred |

> COMP-1 — **основа**: без сошедшегося core-`Instance` + `MachineType` невозможны ни launch-саги
> (COMP-2), ни spread-placement (COMP-3). COMP-2/3/4 расширяют, не переопределяют COMP-1.
> **B10 gate:** compute GA **gated-by storage convergence** (STOR-1) — COMP-2 launch-саги (boot-Volume /
> ImageCatalog) не стартуют до APPROVED+merge STOR-1 (unified §9 B10).

---

## Scope (что COMP-1 покрывает сценариями — positive + ≥1 negative + edge каждая)

| # | Фича | Трассировка |
|---|---|---|
| F1 | `instanceKind∈{VM,CONTAINER}` — сильный первый дискриминатор; oneof `vmSpec` XOR `containerSpec` (spoken-exclusion); immutable после Create; lifecycle по kind | module-compute rule 5; unified §2 compute, §1 conv-1 · **NET-NEW** |
| F2 | `machineTypeId` **единственный канал sizing** (mt-slug ИЛИ стабильное имя, canonical echo `mt-`; `effectiveResources°` mirror; `cpuGuaranteePercent{0..100}` family-gated); **RETIRE raw `ResourcesSpec`/`platform_id`/`core_fraction`** (ban #2) | module-compute rule 1/2; unified §2 compute · **NET-NEW + AS-IS retire** |
| F3 | `bootSource{type,id}` + `imageKind`-дискриминатор (`storage.image`≠`registry.image`, B13); grammar tag/digest **внутри** id; bare-untagged → 400; `name°`/`resolvedDigest°`/`materializedVolume°` — output-only (resolve/materialize → COMP-2) | module-compute rule 3; unified §2 compute, §8 B13 · **NET-NEW `[PHASE-0-GATED B1/B13]`** |
| F4 | `serviceAccountId` = class-C `Referrer{iam.service_account}` (graceful-dangling, B2); опционален для публичных образов | module-compute rule 10; unified §4 seam-C, §8 B2 · **`[PHASE-0-GATED B1]`** |
| F5 | Unreachable-guard: `instanceKind=VM` без `sshPublicKeys` И без external → sync `FAILED_PRECONDITION`, снимается `acknowledgeUnreachable:true` | module-compute rule 8; unified §5 · **NET-NEW** |
| F6 | Launch-`*Specs` **SKELETON**: `networkInterfaceSpecs` **ИЛИ** `useDefaultNetwork` (одно обязательно); `secondaryVolumeSpecs`/`sshPublicKeys` приняты+структурно валидированы; **саги/materialize/mirrors → COMP-2** | module-compute rule 4; unified §1 conv-4 · форма COMP-1, исполнение COMP-2 |
| F7 | `MachineType` sync-каталог: public `Get`/`List` (filter `name=`/`family=`/`minGpus=`); `effectiveResources°`; `family∈{STANDARD,COMPUTE,MEMORY,GPU}`; GPU = гранулярность каталога (не поле); `availableZones°`; `status∈{AVAILABLE,DEPRECATED,RETIRED}`; admin-CRUD на `Internal*` | module-compute rule 1/2/13, MachineType-каталог; unified §1 conv-5 · **NET-NEW** |
| F8 | `Instance` id-prefix `ins-` + malformed-id первым стейтментом | module-compute; unified §1 conv-12, §8 B3 · **`[PHASE-0-GATED B3]`** (AS-IS `epd`) |
| F9 | **YC-cruft retire → vendor-agnostic** (ban #2): `metadataOptions{metadataEndpoint,metadataTokenRequired}`; retire `MetadataOptions{gce_*,aws_*}`/`platform_id`/`scheduling_policy`/`gpu_settings`/`reserved_instance_pool_id`/`application`/`HostAffinityRule{yc.*}` (→ Internal* COMP-4) | module-compute rule 8; unified §5 инв-8 · **AS-IS massive removal** |
| F10 | `Instance` Update — mutability-классы: LIVE-mutable (`name`/`description`/`labels`); next-boot deferred (`vmSpec.userData`/`sshPublicKeys`); immutable (`instanceKind`/`zoneId`); Reinstall-only (`bootSource`); unknown-mask → 400 (STOPPED-gate **энфорсмент** → COMP-2) | module-compute rule 7, mutability-matrix; unified §5 инв-7 |
| F11 | Two-projection: public `Instance` без инфра (node/host/scheduler/`topologyKey`/numeric-infra; `host_group_id`/`host_id` уже reserved AS-IS); infra-проекция → `Internal*` :9091 (наполнение — COMP-4) | module-compute rule 11; security §infra-sensitive; unified §5 инв-1 |
| F12 | `UNIQUE(project,name)` partial (пустое `name` — id-only escape-hatch) + **concurrent name-race** (ровно один writer); BVA границы `name`/`description`/`labels` | data-integrity §within-service/§5; module-compute rule 13 |
| F13 | Единый тон ошибок by-lane: INTERNAL-opaque (без pgx/SQL-leak), immutable-текст, malformed-first, `ALREADY_EXISTS`; project/zone peer-validate fail-closed (`UNAVAILABLE`), authz-first толерантность | api-conventions §error-format; security §hardening инв-1; unified §1 conv-11, §5 инв-5 · `[reason-token PHASE-0-GATED]` |
| F14 | `InstanceService.List` — listauthz row-filter (anti-BOLA) + **pagination-validate ДО authz-short-circuit** (`page_size>1000`/garbage-token → 400) + cursor + `filter name=` (**единственное поле фазы**; любое другое → 400 с именем поля — см. §Reconcile F14 filter-whitelist) | api-conventions §pagination/Gotcha; security инв-7; `make audit-list-filter` |
| F15 | `InstanceService.Delete` — **hard-delete durable-row БЕЗ detach-саги** (launch-`*Specs` не материализуются в COMP-1) → `Get` `NOT_FOUND`; **name-recycle** (непустое `name` освобождается, F12 partial-UNIQUE); malformed-id first-statement / absent-id authz-first tolerant | api-conventions §error-format; data-integrity §within-service; module-compute rule 11 |

---

## Out-of-scope (явно НЕ в COMP-1)

- **COMP-2 — one-shot launch attach-саги + compensation + power-ops + Reinstall.** Реальное
  разворачивание attach-саг (`compute→vpc` IPAM Address alloc + NIC `SetReference` CAS; `compute→storage`
  boot-Volume + secondary materialize; `compute→registry` tag→digest resolve + pull-grant precheck) в
  ОДНОЙ `Operation`; **compute launch compensation-outbox** (B12, unified §5.4) + sweeper-backstop;
  output-зеркала `networkInterfaces°`/`secondaryVolumes°`/`bootSource.resolvedDigest°`/`materializedVolume°`;
  `Start`/`Stop`/`Reboot`/`Reinstall`; **STOPPED-gate энфорсмент** (нужен `Stop`); `GetInstanceOutput`
  (log/console); `zoneId` **вывод из subnet.zone**. COMP-1 владеет **формой** launch-request и его
  **структурной валидацией** (kind-oneof, sizing-канал, bootSource-grammar, unreachable-guard, spec-shape),
  но **не** peer-validate существования subnet/SG/image и **не** materialize.
- **COMP-3 — `PlacementGroup` (spread-ось) + discovery-каталоги + `validateOnly`.** `PlacementGroup`
  редизайн (`spread`/`scope`/`placementType°`/`maxSkew`/`members[]`/scheduler-zone-assign для REQUIRED
  ZONE_SPREAD); `ImageCatalogService.List` (thin-проекция storage.image+registry.image) +
  `VolumeTypeService.List`; `validateOnly:true` sync dry-run; `CapabilityVocabularyService` +
  `requiredCapabilities` (gpu.* mutual-exclusion). **`Instance.placementGroupId` в COMP-1 (OQ4-дефолт) =
  opaque-slug passthrough**: принимается, **сохраняется**, STOPPED-gated (F10) + immutable-семантика;
  валидируется **только формат** (well-formed `plg-`-slug ИЛИ пусто — malformed → `INVALID_ARGUMENT`
  first-statement), **БЕЗ existence/coherence-check**. COMP-1 **не резолвит** группу и **не** проверяет
  placement-когерентность: `Create{placementGroupId, zoneId}` принимаются **вместе без coherence-check**
  (иначе half-coherence — часть проверок без второй). Existence `PlacementGroup`, spread-когерентность,
  scheduler-zone-assign для REQUIRED ZONE_SPREAD (в т.ч. правило «`zoneId` MUST be empty») — **COMP-3**.
  Туда же — **фильтр `List` по placement-группе**: заводится вместе с ресурсом и **обязан прийти со
  своим partial-индексом** (`(project_id, placement_group_id, created_at, id) WHERE placement_group_id
  <> ''`), иначе `List` под нагрузкой вырождается в полное сканирование. Фильтр по `instanceKind`
  дополнительно требует enum-декодера в общем `pkg/filter` (колонка — INTEGER-ordinal, парсер даёт
  строку) — кросс-сервисное изменение, не compute-локальное. Обоснование — §Reconcile F14
  filter-whitelist.
- **COMP-4 — Internal* infra-проекции + легаси-RPC deprecation + `fd8`-Image полный ретайр.**
  `InternalHostAffinityService` + наполнение node/host/scheduler/`topologyKey`-проекций; снос легаси RPC
  (`UpdateMetadata`/`AddOneToOneNat`/`RemoveOneToOneNat`/`Relocate`/`SimulateMaintenanceEvent`/
  `AttachFilesystem`/`DetachFilesystem`/`UpdateNetworkInterface`); **полный ретайр compute-owned
  `fd8`-`Image`/`Snapshot`** → `ImageCatalog` проекция (см. `[CROSS-MODULE]` ниже).
- **Storage/vpc/geo/registry-стороны** (Volume/Image lifecycle — STOR-1; Subnet/SG/NIC/Address — vpc;
  Zone/Region — geo; OCI-pull — registry) — свои под-фазы/своды. COMP-1 их не переопределяет.
- **Data-plane** (гипервизор, реальный boot гостя, программирование ядра/underlay) — не моделируется
  (control-plane only).

---

## Traceability-легенда

`°` = output-only поле (server-derived, на вход не принимается). REST-пути: public
`/compute/v1/…` (:9090, external-safe); admin `InternalMachineTypeService` — самоописываемый
`/compute/v1/internal/machineTypes` (:9091, mTLS, `system_admin`, **НИКОГДА** на external mux — парити
GEO-1 `/geo/v1/internal/…`; ban #6); будущие `Internal*` infra-проекции (COMP-4) — там же :9091.
JSON — camelCase; `createdAt°` усечён
до секунд на wire. Async-мутации → `Operation` (поллинг `OperationService.Get` = `GET /compute/v1/operations/{id}`;
Watch RPC нет); id ресурса в `Operation.metadata` **сразу** (до `done`).

**AS-IS** = реальное текущее состояние кода `project/kacho` (`services/compute/`,
`proto/kacho/cloud/compute/v1/`). Подтверждено grep-сверкой: `Instance` — flat, но несёт
**YC-cruft** (`platform_id`, `Resources{memory,cores,core_fraction,gpus}`, `MetadataOptions{gce_http_*,
aws_v1_*,aws_v2_*}`, `PlacementPolicy.HostAffinityRule.key='yc.hostId'/'yc.hostGroupId'`,
`scheduling_policy.preemptible`, `gpu_settings.gpu_cluster_id`, `reserved_instance_pool_id`,
`application`, bare `string image`(#34) + `image_digest`(#35 output)); `cpu_guarantee_percent`(#36) **уже есть**;
`host_group_id`/`host_id` **уже reserved** (two-projection pass partial-done). **Нет** `machine_type.proto`,
**нет** `instance_kind`/`vm_spec`/`container_spec`, **нет** `boot_source`-message, **нет** `common.v1`-proto
(только legacy `reference/reference.proto`). Instance id-prefix — `epd` (**делит с Disk**), не `ins-`.
**Легаси не трогаем** (только `project/kacho`).

**`[PHASE-0-GATED]`** = сценарий/поле приземляется **только** после merge Phase-0 governance change-set
(unified §7/§9 MUST-close): **B1** (`kacho.cloud.common.v1` 3-way ref-типы `ResourceRef`/`Referrer`/`OciReferrer`),
**B3** (id-prefix hyphen `ins-`/`mt-` в `corevalidate`), **B13** (`imageKind` дискриминатор storage.image vs
registry.image), **by-lane reason-token** таблица. До merge — действует **AS-IS-форма** (см. Merge-gate в DoD).

**`[NET-NEW]`** = ресурс/поле/сообщение, которого нет в AS-IS (нет proto/таблицы/кода) — новый proto+regen
и **новая goose-миграция** (не редактируем применённые, ban #5).

**`[CROSS-MODULE]`** = поведение, требующее координации с другим сводом (STOR-1 storage.image, registry OCI,
Phase-0 governance change-set). COMP-1 фиксирует **compute-сторону** и merge-gate, но не владеет всей цепочкой.

**`[CROSS-MODULE] `fd8`-Image ретайр (locked design, координация STOR-1):** compute СЕЙЧАС владеет
`Image`/`Snapshot` с prefix **`fd8`** (folder-модель). Редизайн переносит VM-boot-`Image` в **storage**
(`img-`, STOR-1 F10/F11); compute `ImageCatalog` становится **тонкой проекцией** над `storage.image` +
`registry.image` (ownership не меняется). **COMP-1 не исполняет ретайр** (он координируется:
проекция-каталог = COMP-3, полный снос `fd8`-`Image`/`Snapshot` = COMP-4/STOR-2). До этого
`fd8`-Image (compute) и `img-` (storage) **сосуществуют** (разные БД/prefix). COMP-1 обязан лишь
**не** привязывать новую boot-модель к compute-owned `fd8`-Image: `bootSource.type=storage.image`
роутит в **storage** (`img-`), `bootSource.type=registry.image` — в **registry** (B13). COMP-1
**не** вводит новых зависимостей на compute-owned `fd8`-Image.

---

## F1 — `instanceKind∈{VM,CONTAINER}` oneof `vmSpec`/`containerSpec` (immutable; lifecycle по kind)

> `→ module-compute rule 5` · `→ unified §2 compute, §1 conv-1` · **NET-NEW**
> **AS-IS**: инстанс — «VM-only» (нет `instance_kind`, нет `vm_spec`/`container_spec`; VM-семантика
> зашита). Редизайн вводит `instanceKind` — **сильный первый required-дискриминатор**, гейтящий
> ОДИН вложенный блок: `vmSpec{userData,metadataOptions}` XOR `containerSpec{command,args,env,
> workingDir,ports,restartPolicy,exitCode°}`. CONTAINER — first-class job (`SUCCEEDED`/`FAILED`
> +`exitCode°`, `restartPolicy∈{NEVER,ON_FAILURE,ALWAYS}` default `NEVER`).

### Сценарий COMP-1-01 (positive): Create VM с vmSpec → Operation, instanceId в metadata сразу, Get отдаёт VM-проекцию

**ID:** COMP-1-01

**Given** проект `prj-acme` существует; зона `ru-central1-a` открыта; MachineType `std-v3-2` (mt-slug) в каталоге `AVAILABLE`
**And** вызывающий имеет `editor` на `prj-acme`

**When** клиент вызывает `InstanceService.Create` (`POST /compute/v1/instances`) с payload:
  - `projectId` = `"prj-acme"`
  - `name` = `"trainer-node-01"`
  - `instanceKind` = `"VM"`
  - `machineTypeId` = `"mt-7k3q9x2m4n8p1r5t"`
  - `bootSource` = `{ type: "storage.image", id: "img-9k2m4x7q1n8p:22.04-lts" }`
  - `zoneId` = `"ru-central1-a"`
  - `networkInterfaceSpecs` = `[ { subnetId: "sub-abc", securityGroupIds: ["scg-def"] } ]`
  - `sshPublicKeys` = `["ssh-ed25519 AAAA… ml@team"]`
  - `vmSpec` = `{ userData: "#cloud-config\n…", metadataOptions: { metadataEndpoint: "ENABLED", metadataTokenRequired: true } }`

**Then** ответ — `Operation`; `metadata` анмаршалится в `CreateInstanceMetadata` с непустым `instanceId` (префикс — см. F8) **до** `done` (unified §3 инвариант; id аллоцируется при Create)
**And** после poll `OperationService.Get` до `done==true && !error`, `result.response` анмаршалится в `Instance` (durable per ban #9; сага-materialize NIC/Volume + переход к `RUNNING` — COMP-2)
**And** последующий `InstanceService.Get` возвращает `Instance` с `instanceKind=="VM"`, `vmSpec` присутствует (`metadataOptions.metadataEndpoint=="ENABLED"`), `containerSpec` **отсутствует** (oneof), `createdAt°` усечён до секунд
**And** **resting-status пиннится** (OQ1-дефолт, не оставлять implementer'у выбор): после `Create`-`done` `Get.status == "PROVISIONING"` **persisted** — durable «инстанс закоммичен, ждёт materialize» (launch-сага NIC/Volume + переход `PROVISIONING → RUNNING` — COMP-2). `Operation.done` = **durability** записи Instance, НЕ видимость downstream side-effect (ban #9); COMP-1 не гейтит `done` на materialize

### Сценарий COMP-1-02 (positive): Create CONTAINER с containerSpec → CONTAINER-проекция, job-поля

**ID:** COMP-1-02

**Given** проект `prj-acme`; зона `ru-central1-b`; MachineType `gpu-a100-8` (`family=GPU`) в каталоге `AVAILABLE`

**When** `InstanceService.Create` с payload:
  - `projectId` = `"prj-acme"`, `name` = `"bert-finetune-run-42"`
  - `instanceKind` = `"CONTAINER"`
  - `machineTypeId` = `"mt-a1b2c3d4e5f6g7h8j"`
  - `bootSource` = `{ type: "registry.image", id: "ml/bert-trainer:cu121" }`
  - `zoneId` = `"ru-central1-b"`
  - `networkInterfaceSpecs` = `[ { subnetId: "sub-b", securityGroupIds: ["scg-b"] } ]`
  - `serviceAccountId` = `"sva-4k8m2q…"`
  - `containerSpec` = `{ command: ["python","train.py"], args: ["--epochs=3"], env: {"WANDB_MODE":"offline"}, restartPolicy: "ON_FAILURE" }`

**Then** после poll `done`, `InstanceService.Get` возвращает `instanceKind=="CONTAINER"`, `containerSpec` присутствует (`command==["python","train.py"]`, `restartPolicy=="ON_FAILURE"`, `exitCode°` пусто пока не терминал), `vmSpec` **отсутствует**
**And** `bootSource.materializedVolume°` **отсутствует** by construction (CONTAINER = ephemeral rootfs — mutability-matrix module-compute)

### Сценарий COMP-1-03 (negative): kind ↔ spec mismatch → INVALID_ARGUMENT (oneof XOR spoken)

**ID:** COMP-1-03

**Given** проект `prj-acme`, зона валидна, machineType валиден

**When** `InstanceService.Create` с `instanceKind="VM"` и заполненным `containerSpec` (вместо `vmSpec`)
**Then** синхронный `INVALID_ARGUMENT` с проговоренным mutual-exclusion: `"containerSpec is not allowed when instanceKind is VM"` (операция не пишется)

**When** `instanceKind="CONTAINER"` с заполненным `vmSpec`
**Then** синхронный `INVALID_ARGUMENT "vmSpec is not allowed when instanceKind is CONTAINER"`

**When** `instanceKind="VM"` с **обоими** `vmSpec` и `containerSpec`
**Then** синхронный `INVALID_ARGUMENT` (oneof: ровно один блок валиден)

**When** `instanceKind` **омитнут** (пустой/UNSPECIFIED)
**Then** синхронный `INVALID_ARGUMENT "instanceKind is required"` (сильный первый required-дискриминатор)

### Сценарий COMP-1-04 (edge): instanceKind immutable после Create

**ID:** COMP-1-04

**Given** `Instance ins-…` создан с `instanceKind="VM"`

**When** `InstanceService.Update` с `updateMask=["instanceKind"]`, `instanceKind="CONTAINER"`
**Then** синхронный `INVALID_ARGUMENT "instanceKind is immutable after Instance.Create"` (immutable-switch срабатывает **до** `corevalidate.UpdateMask`; смена kind сломала бы весь lifecycle/oneof)

---

## F2 — `machineTypeId` единственный канал sizing (retire raw `ResourcesSpec`/`platform_id`; `cpuGuaranteePercent` family-gated)

> `→ module-compute rule 1/2` · `→ unified §2 compute` · **NET-NEW + AS-IS retire (ban #2)**
> **AS-IS** (`instance.proto`, `instance_service.proto`): `CreateInstanceRequest` несёт
> `platform_id`(#6, **required**) + `ResourcesSpec resources_spec`(#7, **required**, `{memory,cores,
> core_fraction,gpus}`) — прямой YC-sizing. Редизайн: **единственный канал** — `machineTypeId`
> (mt-slug ИЛИ стабильное имя `std-v3-2`, резолв в scope проекта, **canonical echo всегда `mt-`**);
> `effectiveResources°{vCpu,memoryMiB,gpus,gpuType}` — output-only зеркало каталога. `platform_id`/
> `resources_spec`/`core_fraction` **удаляются с входа** (dead-XOR, LEAN). Единственный CPU-модулятор —
> `cpuGuaranteePercent{0..100}` (0=burstable; `cpu_guarantee_percent`(#36) **уже есть** в AS-IS —
> сохраняется), применим **только** к `family∈{STANDARD,COMPUTE,MEMORY}`.

### Сценарий COMP-1-05 (positive): machineTypeId → effectiveResources° из каталога; canonical echo mt-

**ID:** COMP-1-05

**Given** MachineType `mt-7k3q9x2m4n8p1r5t` (`name="std-v3-2"`, `family=STANDARD`, `effectiveResources{vCpu:2,memoryMiB:8192,gpus:0}`) `AVAILABLE`

**When** `InstanceService.Create` (VM, валидный payload) с `machineTypeId="mt-7k3q9x2m4n8p1r5t"`, `cpuGuaranteePercent=100`
**Then** после `done`, `InstanceService.Get` показывает `machineTypeId=="mt-7k3q9x2m4n8p1r5t"` (canonical mt-slug), `effectiveResources°=={vCpu:2, memoryMiB:8192, gpus:0, gpuType:""}` (output-only зеркало каталога, память в **MiB** не байты), `cpuGuaranteePercent==100`

### Сценарий COMP-1-06 (positive/edge): machineTypeId принимает стабильное имя → резолвится, echo всегда mt-

**ID:** COMP-1-06

**Given** MachineType `mt-7k3q9x2m4n8p1r5t` (`name="std-v3-2"`) `AVAILABLE`

**When** `InstanceService.Create` с `machineTypeId="std-v3-2"` (стабильное имя, не slug)
**Then** после `done`, `InstanceService.Get.machineTypeId == "mt-7k3q9x2m4n8p1r5t"` (server-side резолв имени в scope проекта; **canonical echo всегда `mt-`-slug**, даже если на входе было имя) — indirection List-lookup для IaC-шаблонов не обязателен

### Сценарий COMP-1-07 (negative): raw sizing retired; unknown/RETIRED machineType отвергнут

**ID:** COMP-1-07

**When** `InstanceService.Create` с `platform_id`/`resourcesSpec`/`coreFraction` в теле (легаси-поля)
**Then** синхронный `INVALID_ARGUMENT` — поля **удалены** из request-схемы (unknown field, ban #2 YC-cruft retire); единственный канал sizing — `machineTypeId`

**When** `InstanceService.Create` с `machineTypeId=""` (пусто)
**Then** синхронный `INVALID_ARGUMENT "machineTypeId is required"`

**When** `InstanceService.Create` с `machineTypeId="mt-nonexistent"` (well-formed, в каталоге нет)
**Then** `Operation.error` (или sync — см. by-lane F13) `FAILED_PRECONDITION "machine type mt-nonexistent not found"` (каталог-резолв; peer-класс — same-service catalog lookup)

**When** `InstanceService.Create` с `machineTypeId` каталожной записи в статусе `RETIRED`
**Then** reject `FAILED_PRECONDITION` — `RETIRED` не запускается на Create (`DEPRECATED` — можно на существующих, F7)

### Сценарий COMP-1-08 (edge): cpuGuaranteePercent {0..100} family-gated

**ID:** COMP-1-08

**Given** MachineType `std-v3-2` (`family=STANDARD`) и `gpu-a100-8` (`family=GPU`)

**When** `InstanceService.Create` (STANDARD) с `cpuGuaranteePercent=0` (burstable)
**Then** `done`; `Get.cpuGuaranteePercent==0` (0=best-effort/burstable, применяется к CPU-flavor)

**When** `InstanceService.Create` с `cpuGuaranteePercent=101` (вне {0..100})
**Then** синхронный `INVALID_ARGUMENT` (`CHECK 0..100`; отвергается, не clamp'ится)

**When** `InstanceService.Create` (GPU-flavor, `family=GPU`) с `cpuGuaranteePercent=50`
**Then** `done`; поле **принято-и-игнорируется** при `family=GPU` (`cpuGuaranteePercent` не применяется к GPU; `validateOnly`-note о том, что игнорируется — COMP-3). Значение на инстансе не влияет на `effectiveResources°`

---

## F3 — `bootSource{type,id}` + `imageKind`-дискриминатор (grammar tag/digest внутри id; bare-untagged → 400)

> `→ module-compute rule 3` · `→ unified §2 compute, §8 B13` · **NET-NEW `[PHASE-0-GATED B1/B13]`**
> **AS-IS**: boot-модель — bare `string image`(#34, только `registry.image`-OCI) + `boot_disk_spec`
> (`AttachedDiskSpec`) + output `image_digest`(#35). **Нет** дискриминатора storage vs registry, **нет**
> `bootSource`-message. Редизайн (B13): **один вход `{type,id}`**, `type∈{storage.image,registry.image}`
> (owner-дискриминатор ⇒ bare `imageId` **никогда** не двусмыслен между двумя owner'ами); tag/digest —
> **внутри `id`** (одна grammar на все входы). Output-only `name°`/`resolvedDigest°`/`materializedVolume°`
> **вложены под `bootSource`** — их **resolve/materialize — COMP-2** (compute→registry/storage сага).
> COMP-1 владеет **входной формой + grammar-валидацией + imageKind-роутингом** (без реального resolve).

### Сценарий COMP-1-09 (positive): bootSource {type,id} принят и эхается; imageKind роутит owner'а

**ID:** COMP-1-09 `[PHASE-0-GATED B1/B13]`

**Given** проект/зона/machineType валидны

**When** `InstanceService.Create` (VM) с `bootSource = { type: "storage.image", id: "img-9k2m4x7q1n8p:22.04-lts" }`
**Then** после `done`, `Get.bootSource.type=="storage.image"`, `bootSource.id=="img-9k2m4x7q1n8p:22.04-lts"` (эхо входа; `imageKind`-дискриминатор роутит резолв в **storage** — сам resolve COMP-2)

**When** `InstanceService.Create` (CONTAINER) с `bootSource = { type: "registry.image", id: "ml/bert-trainer:cu121" }`
**Then** после `done`, `Get.bootSource.type=="registry.image"`, `bootSource.id=="ml/bert-trainer:cu121"` (роутит в **registry**)
**And** `[PHASE-0-GATED B13]`: формальный `imageKind`-дискриминатор (`STORAGE_IMAGE`/`OCI_IMAGE` ИЛИ `Referrer.type` `storage.image`/`registry.image`) приземляется governance change-set'ом cross-module с storage/registry. **AS-IS до Phase-0** — bare `string image` (только registry). Merge-gate — §DoD

### Сценарий COMP-1-10 (negative): bare-untagged id → 400 с grammar; unknown type → 400

**ID:** COMP-1-10

**When** `InstanceService.Create` с `bootSource = { type: "storage.image", id: "img-9k2m4x7q1n8p" }` (без tag/digest)
**Then** синхронный `INVALID_ARGUMENT "bootSource.id needs a tag or digest, e.g. 'img-<base32>:<tag>' or 'img-<base32>@sha256:<hex>'; use ImageCatalog item.bootSource"` (grammar в тексте ошибки)

**When** `InstanceService.Create` с `bootSource = { type: "vm.image", id: "img-…:tag" }` (неизвестный type)
**Then** синхронный `INVALID_ARGUMENT` — `type` вне `{storage.image, registry.image}`

**When** `InstanceService.Create` с пустым `bootSource` (омитнут)
**Then** синхронный `INVALID_ARGUMENT "bootSource is required"`

### Сценарий COMP-1-11 (edge): bootSource на входе — только {type,id}; output-only поля отвергаются на входе

**ID:** COMP-1-11

**When** `InstanceService.Create` с `bootSource = { type:"storage.image", id:"img-…:tag", name:"ubuntu", resolvedDigest:"sha256:…", materializedVolume:{…} }` (output-only поля в теле)
**Then** синхронный `INVALID_ARGUMENT` — `name°`/`resolvedDigest°`/`materializedVolume°` server-derived, на вход не принимаются
**And** в happy-path `Get` (COMP-1) `bootSource.resolvedDigest°`/`materializedVolume°` **пусты** — их наполняет boot-resolve/materialize сага (**COMP-2**). COMP-1 фиксирует форму, не резолвит

---

## F4 — `serviceAccountId` = class-C `Referrer{iam.service_account}` (graceful-dangling; опционален)

> `→ module-compute rule 10` · `→ unified §4 seam-C, §8 B2` · **`[PHASE-0-GATED B1]`**
> **AS-IS**: `service_account_id`(#14/#18) — bare `string` (нет `common.v1`, только legacy
> `reference/reference.proto`). Редизайн (B2, решено): class-C **`Referrer{iam.service_account}`** —
> polymorphic, graceful-dangling (референт-SA удалён → DETACHED/degraded, не паника; unified §8 B2).
> Опционален для публичных образов; нужен для приватного `registry.image` pull (pull-grant precheck —
> **COMP-2**). `compute→iam` ребро **уже существует** (ProjectService.Get/Check) — class-C не добавляет цикла.

### Сценарий COMP-1-12 (positive/edge): serviceAccountId принят (опционален); эхается как Referrer

**ID:** COMP-1-12 `[PHASE-0-GATED B1]`

**When** `InstanceService.Create` (VM, storage.image публичный) **без** `serviceAccountId`
**Then** `done` — `serviceAccountId` опционален для публичных образов (`Get.serviceAccountId==""`)

**When** `InstanceService.Create` с `serviceAccountId="sva-4k8m2q…"`
**Then** после `done`, `Get.serviceAccountId=="sva-4k8m2q…"` (class-C `Referrer{type:"iam.service_account", id:"sva-…"}`; write-time-snapshot)
**And** `[PHASE-0-GATED B1]`: тип `Referrer` — из `kacho.cloud.common.v1` (3-way ref-набор). **AS-IS до Phase-0** — bare `string service_account_id`. Форма меняется только после merge B1-change-set; merge-gate — §DoD

### Сценарий COMP-1-13 (negative/edge): malformed SA id form; graceful-dangling (референт удалён)

**ID:** COMP-1-13

**When** `InstanceService.Create` с `serviceAccountId="not!!a!!sa!!id"` (malformed по SA-grammar)
**Then** синхронный `INVALID_ARGUMENT` — формат SA-id валидируется (own-side format-check foreign-id: **existence** peer-validate — COMP-2, class-C tolerant)

**Given** `Instance ins-…` с `serviceAccountId="sva-x"`; затем `sva-x` удалён в iam
**When** `InstanceService.Get(ins-…)`
**Then** `serviceAccountId` остаётся эхом `"sva-x"` (write-time snapshot) — **graceful-dangling** class-C (референт удалён → не паника; degraded-семантика; unified §4 seam-C). Компьют **не** каскадит по чужому удалению (ban #4)

---

## F5 — Unreachable-guard (`VM` без ssh И без external → sync FAILED_PRECONDITION; `acknowledgeUnreachable`)

> `→ module-compute rule 8` · `→ unified §5` · **NET-NEW**
> `'boots' ≠ 'usable'`: `instanceKind=VM` без `sshPublicKeys` И без external-достижимого NIC
> (`assignExternalAddress:false`) поднимется `RUNNING`-но-недостижим. Guard требует явного
> `acknowledgeUnreachable:true` (не блокирует легальный bastion-only кейс).

### Сценарий COMP-1-14 (negative→positive): VM без ssh и без external → guard; acknowledgeUnreachable снимает

**ID:** COMP-1-14

**Given** проект/зона/machineType/subnet валидны

**When** `InstanceService.Create` (VM) **без** `sshPublicKeys`, **без** `assignExternalAddress` (или `false`), `acknowledgeUnreachable` не задан
**Then** синхронный `FAILED_PRECONDITION "VM will be RUNNING but unreachable (no sshPublicKeys and no external address); set acknowledgeUnreachable:true to proceed"` (операция не пишется)

**When** тот же payload + `acknowledgeUnreachable=true`
**Then** `done` — guard подтверждён (bastion-only кейс); `Get` отдаёт инстанс

### Сценарий COMP-1-15 (edge): CONTAINER не под guard; VM с ssh ИЛИ external — OK

**ID:** COMP-1-15

**When** `InstanceService.Create` (**CONTAINER**) без ssh и без external
**Then** `done` — guard применим **только** к `instanceKind=VM` (CONTAINER нуждается в NIC для egress к реестру, но не в ssh/external-логине)

**When** `InstanceService.Create` (VM) с `sshPublicKeys=[…]` (без external)
**Then** `done` — достижим по ssh через internal-NIC (guard не срабатывает)

**When** `InstanceService.Create` (VM) с `assignExternalAddress=true` (без ssh)
**Then** `done` — external-достижим (guard не срабатывает; хотя без ssh залогиниться нельзя — это уже tenant-выбор, не guard-условие)

---

## F6 — Launch-`*Specs` SKELETON: `networkInterfaceSpecs` ИЛИ `useDefaultNetwork`; структурная валидация (саги → COMP-2)

> `→ module-compute rule 4` · `→ unified §1 conv-4` · форма COMP-1, исполнение COMP-2
> **AS-IS**: `network_interface_specs`(#11, **required**) + `boot_disk_spec`/`secondary_disk_specs`
> (`AttachedDiskSpec`). Редизайн one-shot: `networkInterfaceSpecs` **ИЛИ** `useDefaultNetwork:true`
> (одно обязательно); `secondaryVolumeSpecs[]`/`sshPublicKeys[]`. **COMP-1 принимает и структурно
> валидирует** форму (наличие обязательной сети, `sizeGiB>0`, `mountPath`, well-formed subnet/SG ids),
> но **peer-validate существования** subnet/SG/image + **IPAM/NIC/boot-Volume materialize** + output-зеркала
> `networkInterfaces°`/`secondaryVolumes°` — **COMP-2** (attach-саги). `useDefaultNetwork` до vpc-side
> default-subnet (B5) — форма есть, не функциональна (prerequisite-runbook, module-compute).

### Сценарий COMP-1-16 (negative): ни networkInterfaceSpecs, ни useDefaultNetwork → FAILED_PRECONDITION runbook

**ID:** COMP-1-16

**When** `InstanceService.Create` **без** `networkInterfaceSpecs` и **без** `useDefaultNetwork`
**Then** синхронный `FAILED_PRECONDITION "needs an existing subnet+SG in zone ru-central1-a; discover via SubnetService.List / SecurityGroupService.List, create via SubnetService.Create — or set useDefaultNetwork:true"` (actionable prerequisite-runbook в тексте; subnet/SG — vpc-owned, compute НЕ авто-создаёт — цикл-риск)

**When** `InstanceService.Create` с `networkInterfaceSpecs=[{subnetId:"sub-a", securityGroupIds:["scg-a"]}]`
**Then** форма принята (структурно валидна); happy-path COMP-1 (материализация NIC — COMP-2)

**When** `InstanceService.Create` с `useDefaultNetwork=true` (без явных specs)
**Then** форма принята структурно; фактический резолв project-default subnet+SG через `compute→vpc` — **COMP-2** (до vpc-side default-subnet B5 — не функционально)

### Сценарий COMP-1-17 (edge): secondaryVolumeSpecs / sshPublicKeys структурно валидируются

**ID:** COMP-1-17

**When** `InstanceService.Create` с `secondaryVolumeSpecs=[{ sizeGiB: 0, volumeTypeId:"vt-ssd", mountPath:"/data" }]` (`sizeGiB<=0`)
**Then** синхронный `INVALID_ARGUMENT` (structural: `sizeGiB>0`, human-scale GiB не байты)

**When** `InstanceService.Create` с `secondaryVolumeSpecs=[{ sizeGiB: 100, volumeTypeId:"vt-ssd", mountPath:"/data", autoDelete:false }]` + `sshPublicKeys=["ssh-ed25519 AAAA…"]`
**Then** форма принята структурно (`done`); реальный boot/secondary-Volume materialize + `secondaryVolumes°`-зеркало — **COMP-2**. COMP-1 фиксирует, что `secondaryVolumes°`/`networkInterfaces°` — **output-only** (на вход в теле Create отвергаются)

---

## F7 — `MachineType` sync-каталог (public `Get`/`List`; admin-CRUD на `Internal*`)

> `→ module-compute rule 1/2/13, MachineType-каталог` · `→ unified §1 conv-5` · **NET-NEW**
> **AS-IS**: `MachineType` **отсутствует** (нет `machine_type.proto`, таблицы, кода). Полностью
> net-new: flat proto + regen + **новая миграция**. Форма — spine-каноничная (flat, enum `Family`/
> `Status`, sync `Get`/`List`). Public read — **ambient** (project-scope EXEMPT, как geo-каталог:
> любой аутентифицированный tenant читает каталог, чтобы выбрать размер); наполнение каталога
> (admin-flavors) — `InternalMachineTypeService.Create/Update` **под самоописываемым путём
> `/compute/v1/internal/machineTypes`** (:9091, `system_admin`; парити GEO-1 `/geo/v1/internal/…` —
> internal-vs-public неотличимость снята **путём**, не только allowlist'ом) `[OQ3-дефолт: Internal
> admin-CRUD, НЕ seed-only]`. GPU-count = **гранулярность flavor'а** (`gpu-a100-1/-2/-4/-8`), НЕ
> отдельное поле.

### Сценарий COMP-1-18 (positive): MachineType.Get → flat public-проекция; ambient read

**ID:** COMP-1-18

**Given** MachineType `mt-7k3q9x2m4n8p1r5t` засеян (admin, `name="std-v3-2"`, `family=STANDARD`, `effectiveResources{vCpu:2,memoryMiB:8192,gpus:0,gpuType:""}`, `availableZones=["ru-central1-a","ru-central1-b"]`, `status=AVAILABLE`)
**And** свежесозданный zero-binding project с аутентифицированным tenant-принципалом (ambient read)

**When** `MachineTypeService.Get` (`GET /compute/v1/machineTypes/mt-7k3q9x2m4n8p1r5t`)
**Then** `200` public `MachineType` с `id`, `name`, `description`, `family=="STANDARD"`, `effectiveResources°`, `availableZones°`, `status`, `labels`, `createdAt°` (усечён); ambient — не требует project-scope viewer-tuple (module-compute каталог; unified §1 conv-9 documented-exception, как geo)

### Сценарий COMP-1-19 (positive): MachineType.List filter name=/family=/minGpus=; GPU-discovery

**ID:** COMP-1-19

**Given** каталог: `std-v3-2`(STANDARD,gpus:0), `mem-v2-4`(MEMORY,gpus:0), `gpu-a100-1`(GPU,gpus:1), `gpu-a100-8`(GPU,gpus:8)

**When** `MachineTypeService.List` (`GET /compute/v1/machineTypes?family=GPU`)
**Then** массив содержит `gpu-a100-1`, `gpu-a100-8` (не STANDARD/MEMORY) — так дискаверятся GPU-flavor'ы

**When** `MachineTypeService.List?family=GPU&minGpus=4`
**Then** массив содержит `gpu-a100-8` (`gpus=8>=4`), **не** `gpu-a100-1` (`gpus=1<4`) — count = гранулярность каталога, не поле запроса

**When** `MachineTypeService.List?name=std-v3-2`
**Then** ровно `std-v3-2` (filter whitelist — `name=`/`family=`/`minGpus=`)

### Сценарий COMP-1-20 (negative): malformed mt- id → INVALID_ARGUMENT первым стейтментом; well-formed-нет → NOT_FOUND

**ID:** COMP-1-20 `[id-prefix форма PHASE-0-GATED B3]`

**When** `MachineTypeService.Get` с `machineTypeId="bad!!id"`
**Then** синхронный `INVALID_ARGUMENT "invalid machine type id 'bad!!id'"` первым стейтментом (`corevalidate.ResourceID` до repo)

**When** `MachineTypeService.Get` с well-formed-но-несуществующим `mt-…`
**Then** `NOT_FOUND "MachineType <id> not found"` (тон контракта, через `repo.Get`)
**And** `[PHASE-0-GATED B3]`: форма префикса `mt-` зависит от B3 (`corevalidate`); код (first-statement `INVALID_ARGUMENT`) и тон — ungated

### Сценарий COMP-1-21 (edge): DEPRECATED usable на существующих; RETIRED отвергается на Create; admin-CRUD на Internal*

**ID:** COMP-1-21

**Given** MachineType `mt-old` в статусе `DEPRECATED`, `mt-gone` в статусе `RETIRED`

**When** `InstanceService.Create` с `machineTypeId="mt-old"` (DEPRECATED)
**Then** `done` — `DEPRECATED` разрешён на новых инстансах (совместимость; module-compute §62)

**When** `InstanceService.Create` с `machineTypeId="mt-gone"` (RETIRED)
**Then** reject `FAILED_PRECONDITION` — `RETIRED` не запускается (F2 COMP-1-07 контраст)

**When** `InternalMachineTypeService.Create` (`POST /compute/v1/internal/machineTypes`) на **external** TLS endpoint (:443/public)
**Then** запрос **не выполняет мутацию**: public REST-mux **не несёт route** на `/compute/v1/internal/…` (routing-miss) И `InternalMachineTypeService`-методы **отсутствуют** в public gRPC-allowlist → `Unimplemented` (не bare 404, не мутация). Admin-CRUD MachineType живёт **только** на `InternalMachineTypeService` (:9091, `/compute/v1/internal/machineTypes`, `system_admin`); public несёт лишь `Get`/`List` (ban #6; парити GEO-1-17; assert на e2e/api-gateway-уровне)

---

## F8 — `Instance` id-prefix `ins-` + malformed-id первым стейтментом `[PHASE-0-GATED B3]`

> `→ unified §1 conv-12, §8 B3` · **`[PHASE-0-GATED B3]`**
> **AS-IS** (`services/compute/docs/architecture/06-conventions.md`): `PrefixInstance="epd"`,
> **делит с `PrefixDisk="epd"`** (`Image`/`Snapshot`="fd8"). Op-prefix compute — `epd`
> (`PrefixOperationCompute==PrefixInstance`). Редизайн B3 фиксирует **hyphen-форму** `ins-`
> (Instance) в `corevalidate` prefix→type-router. До Phase-0 — текущий `epd`.

### Сценарий COMP-1-22 (negative) `[PHASE-0-GATED B3]`: malformed instance id → INVALID_ARGUMENT first-statement; well-formed-нет → NOT_FOUND

**ID:** COMP-1-22 `[id-prefix форма PHASE-0-GATED B3]`

**When** `InstanceService.Get` с `instanceId="not-an-ins-id!!"` (malformed)
**Then** синхронный `INVALID_ARGUMENT "invalid instance id 'not-an-ins-id!!'"` — **первым стейтментом** RPC (до любого repo-вызова)

**When** `InstanceService.Get` с well-formed-но-несуществующим id (правильный префикс+base32, строки нет)
**Then** `NOT_FOUND "Instance <id> not found"` (через `repo.Get`)

**When** *(OQ4 passthrough — format-only)* `InstanceService.Create` с `placementGroupId="not-a-plg!!"` (malformed slug)
**Then** синхронный `INVALID_ARGUMENT "invalid placement group id 'not-a-plg!!'"` — **только формат** (well-formed `plg-`-slug ИЛИ пусто); `placementGroupId=""` и well-formed `plg-…` **оба приняты БЕЗ existence/coherence-check** (резолв группы + spread-когерентность = COMP-3, §Out-of-scope)

**And** `[PHASE-0-GATED B3]`: **форма** валидного префикса меняется `epd` → `ins-` после приземления B3 в `corevalidate`. **AS-IS до Phase-0**: `epd` (делит с Disk). Merge-gate — §DoD. Код (`INVALID_ARGUMENT` first-statement) и тон (`"invalid instance id '<X>'"` / `"Instance <id> not found"`) — **ungated**

---

## F9 — YC-cruft retire → vendor-agnostic (ban #2 AS-IS massive removal)

> `→ module-compute rule 8` · `→ unified §5 инв-8` · **AS-IS massive removal**
> **AS-IS** несёт брендовый cruft (подтверждено grep): `MetadataOptions{gce_http_endpoint,
> aws_v1_http_endpoint, gce_http_token, aws_v1_http_token, aws_v2_http_endpoint, aws_v2_http_token}`;
> `PlacementPolicy.HostAffinityRule.key='yc.hostId'/'yc.hostGroupId'`; `platform_id`;
> `scheduling_policy.preemptible`; `gpu_settings.gpu_cluster_id`; `reserved_instance_pool_id`;
> `application`. Редизайн (ban #2): `metadataOptions{metadataEndpoint∈{ENABLED,DISABLED},
> metadataTokenRequired:bool}` (vendor-agnostic, под `vmSpec`); `HostAffinityRule` + `topologyKey` →
> **Internal*** (COMP-4); остальной cruft **удаляется** с публичной поверхности. Узнаваемость —
> **формой**, не брендом.

### Сценарий COMP-1-23 (edge): metadataOptions vendor-agnostic; gce_*/aws_* удалены

**ID:** COMP-1-23

**When** `InstanceService.Create` (VM) с `vmSpec.metadataOptions = { metadataEndpoint: "ENABLED", metadataTokenRequired: true }`
**Then** после `done`, `Get.vmSpec.metadataOptions.metadataEndpoint=="ENABLED"`, `metadataTokenRequired==true` (vendor-agnostic, без бренд-префиксов/версий)

**When** `InstanceService.Create` с легаси `metadataOptions.gceHttpEndpoint` / `awsV1HttpToken` в теле
**Then** синхронный `INVALID_ARGUMENT` — брендовые поля **удалены** из схемы (unknown field, ban #2)

### Сценарий COMP-1-24: assert field-absence всех retired YC-полей на публичном Instance

**ID:** COMP-1-24

**Given** `Instance ins-…` создан валидным redesign-payload

**When** `InstanceService.Get` / `List` на публичном :9090
**Then** сериализованное тело **не содержит** полей `platform_id`, `resources`/`resourcesSpec`, `coreFraction`, `schedulingPolicy`/`preemptible`, `gpuSettings`/`gpuClusterId`, `reservedInstancePoolId`, `application`, `hostAffinityRules`, `gceHttpEndpoint`/`awsV1HttpEndpoint`/`awsV2HttpToken` (assert field-absence — YC-cruft retired, ban #2)
**And** **NotContains** токенов `"yc.hostId"`, `"yc.hostGroupId"` (host-affinity → Internal* COMP-4, не на public)

---

## F10 — `Instance` Update — mutability-классы (LIVE / next-boot / immutable / Reinstall-only; STOPPED-gate → COMP-2)

> `→ module-compute rule 7, mutability-matrix` · `→ unified §5 инв-7`
> **AS-IS**: `UpdateInstanceRequest` мутабельно правит metadata/labels/…; STOPPED-gate/next-boot-deferral
> формально не выражены. Редизайн — exhaustive mutability-классы. **COMP-1 владеет и ЭНФОРСИТ все классы**:
> immutable-reject (`instanceKind`/`zoneId`, до `UpdateMask`), unknown-mask-reject, next-boot
> **acceptance-with-deferral**, LIVE-mutable применение, Reinstall-only-reject (`bootSource` через Update → отказ),
> **STOPPED-gate ЭНФОРСМЕНТ**. STOPPED-gated поля (`machineTypeId`/`cpuGuaranteePercent`/`placementGroupId`)
> **остаются в known-set** (unknown-mask-reject стабилен) И энфорсятся: реальный Update на **не-`STOPPED`**
> инстансе → sync `FAILED_PRECONDITION "instance must be STOPPED to change sizing or placement"`. В COMP-1
> любой инстанс **никогда не STOPPED** (`Stop` = COMP-2) ⇒ предусловие **недостижимо** ⇒ gate **всегда
> reject** — сценарий полностью COMP-1-тестируем без `Stop`. COMP-2 добавляет лишь **достижимость** STOPPED
> (через `Stop`) → успешный resize; сам gate уже энфорсится здесь. **`validateOnly:true` (COMP-3) НЕ
> триггерит STOPPED-gate** — pre-Stop capacity-check.

### Сценарий COMP-1-25 (positive): LIVE-mutable name/description/labels применяются

**ID:** COMP-1-25

**Given** `Instance ins-…` в стабильном состоянии

**When** `InstanceService.Update` с `updateMask=["name","labels"]`, `name="trainer-node-01b"`, `labels={"team":"ml","run":"42"}`
**Then** `Operation` `done`; `Get.name=="trainer-node-01b"`, `labels` обновлены (LIVE-mutable, применяются сразу)

### Сценарий COMP-1-26 (negative): immutable / unknown-mask → INVALID_ARGUMENT (immutable до UpdateMask)

**ID:** COMP-1-26

**When** `InstanceService.Update` с `updateMask=["zoneId"]`, `zoneId="ru-central1-c"`
**Then** синхронный `INVALID_ARGUMENT "zoneId is immutable after Instance.Create"` (immutable-switch **до** `corevalidate.UpdateMask`; смена зоны сломала бы placement-coherence всех привязок)
**And** то же для `instanceKind` (F1 COMP-1-04)

**When** `InstanceService.Update` с `updateMask=["fqdn"]` (output-only / unknown в known-set)
**Then** синхронный `INVALID_ARGUMENT` (`corevalidate.UpdateMask` known-set; unknown → reject)

### Сценарий COMP-1-27 (edge): next-boot deferral принято; bootSource через Update → Reinstall-only; STOPPED-gate → COMP-2

**ID:** COMP-1-27

**When** `InstanceService.Update` с `updateMask=["sshPublicKeys"]`, `sshPublicKeys=[…]` (или `vmSpec.userData`)
**Then** `Operation` `done`; изменение **принято с deferral** — `Get.statusReason` содержит `"takes effect on next boot"` (НЕ reject; next-boot deferred class)

**When** `InstanceService.Update` с `updateMask=["bootSource"]`
**Then** синхронный `INVALID_ARGUMENT "bootSource cannot be changed via Update; use Reinstall"` (Reinstall-only class; смена ОС — деструктив, **сам `Reinstall` — COMP-2**)

**When** `InstanceService.Update` с `updateMask=["machineTypeId"]`, `machineTypeId="mt-bigger"` (STOPPED-gated sizing) на **любом** COMP-1-инстансе
**Then** синхронный `FAILED_PRECONDITION "instance must be STOPPED to change sizing or placement"` — **gate ЭНФОРСИТСЯ в COMP-1**: инстанс никогда не `STOPPED` (`Stop`=COMP-2) ⇒ предусловие недостижимо ⇒ **всегда reject** (никогда «применяет sizing на живом»). Поле остаётся в known-set (`machineTypeId`/`cpuGuaranteePercent`/`placementGroupId` — unknown-mask-reject стабилен). COMP-2 добавляет лишь достижимость STOPPED (через `Stop`) → успешный resize; сам gate уже здесь. Полностью COMP-1-тестируемо без `Stop`

---

## F11 — Two-projection: public `Instance` без инфра; infra-проекция → `Internal*` (наполнение COMP-4)

> `→ module-compute rule 11` · `→ security §infra-sensitive` · `→ unified §5 инв-1`
> **AS-IS**: `host_group_id`(27)/`host_id`(28) **уже reserved** на public Instance (частичный
> two-projection pass done, KAC contract-authz 2026-07-05). Редизайн расширяет: node/host/scheduler/
> underlay/numeric-infra-id/`topologyKey`/`HostAffinityRule` — **только** `Internal*` :9091.
> Публичная поверхность = намерение + результат. **Наполнение** infra-проекции (`InternalHostAffinityService`,
> node/host) — **COMP-4**; COMP-1 фиксирует **инвариант отсутствия** инфра на public.

### Сценарий COMP-1-28: public Instance НЕ несёт инфра (assert field-absence)

**ID:** COMP-1-28

**When** `InstanceService.Get` / `List` на публичном :9090
**Then** сериализованное тело — public `Instance` (id/projectId/name/description/labels/createdAt/instanceKind/machineTypeId/cpuGuaranteePercent/effectiveResources°/bootSource/zoneId/placementGroupId/fqdn/serviceAccountId/vmSpec|containerSpec/status/statusReason + output-зеркала); **NotContains** инфра-токенов: `hostId`, `hostGroupId`, `nodeId`, `schedulerHint`, `topologyKey`, `numericInfraId`, `underlay` — assert field-absence (two-projection security-инвариант, **не** gated)

### Сценарий COMP-1-29 (edge): host_group_id/host_id остаются reserved; infra-проекция — только :9091

**ID:** COMP-1-29

**When** попытка задать `hostGroupId`/`hostId` в `CreateInstanceRequest` (легаси AS-IS reserved)
**Then** синхронный `INVALID_ARGUMENT` — поля reserved на public message (нельзя переиспользовать; AS-IS reserved 27/28 + names)
**And** будущая infra-проекция Instance (node/host/scheduler) и `InternalHostAffinityService` — **только** `Internal*` :9091, НЕ на external mux (ban #6; наполнение — COMP-4). COMP-1 фиксирует, что public-поверхность инфру не выставляет

---

## F12 — `UNIQUE(project,name)` partial + concurrent name-race + BVA границы

> `→ data-integrity §within-service/§5` · `→ module-compute rule 13`
> **AS-IS**: `name`(#4, pattern `|[a-z]([-_a-z0-9]{0,61}[a-z0-9])?` — допускает пустое). Редизайн:
> `UNIQUE(project_id,name) WHERE name<>''` (partial — пустое `name` = id-only escape-hatch;
> `AlreadyExists`-тон). Within-service инвариант — **на DB-уровне** (ban #10), не software check-then-act.

### Сценарий COMP-1-30 (negative+edge+CONCURRENCY): duplicate name → ALREADY_EXISTS; другой проект → OK; пустое имя → OK; concurrent-race

**ID:** COMP-1-30 `[concurrent-race — обязателен в DoD]`

**Given** `Instance` с `name="trainer-node-01"` в `prj-acme` уже существует

**When** второй `InstanceService.Create` с `name="trainer-node-01"` в `prj-acme`
**Then** `Operation.error` — `ALREADY_EXISTS` (partial `UNIQUE(project_id,name) WHERE name<>''`, SQLSTATE 23505; DB-backstop)
**And** `Create` с `name="trainer-node-01"` в **другом** проекте `prj-beta` → `done` без ошибки (UNIQUE scoped проектом)
**And** `Create` c пустым `name` **дважды** в одном проекте → оба `done` (partial-UNIQUE не ловит `name=''` — id-only escape-hatch)
**And** *(edge, CONCURRENCY)* **две конкурентные** `Create` с **одинаковым** непустым `name` в одном проекте → ровно одна `done`, другая `ALREADY_EXISTS` (UNIQUE-race на DB-уровне, integration `-race`, детерминированный — blocker держит слот, **не** `time.Sleep`; data-integrity §5)
**And** *(фикстур-дисциплина)* проигравшая `Create` несёт `Operation{done:true}` с `result.error=ALREADY_EXISTS`, но `metadata.instanceId` **всё равно заполнен** (id **pre-allocated** при Create, до async-фейла) — фикстура/тест обязаны проверять `!op.error` **перед** извлечением `instanceId` из `metadata` (иначе фантомный id несозданного инстанса; `testing.md` op.error-перед-metadata)

### Сценарий COMP-1-31 (negative, BVA): границы name / description / labels

**ID:** COMP-1-31

**Given** проект/зона/machineType валидны

**When** `InstanceService.Create` с `name` длиной **64** (граница 1..63 + 1)
**Then** синхронный `INVALID_ARGUMENT` (proto-pattern `name`); `name` длиной **63** → OK; `name=""` → OK (optional, partial-UNIQUE не применяется)

**When** `Create` с `description` длиной **257** (≤256 + 1)
**Then** синхронный `INVALID_ARGUMENT`; `description` 256 → OK

**When** `Create` с **65** парами `labels` (≤64 + 1), либо ключ/значение вне regex/длины
**Then** синхронный `INVALID_ARGUMENT` (`kacho_labels_valid` + proto-валидация); 64 валидных пары → OK

**When** *(edge, non-ASCII)* `Create` с `name="тренер-01"` (unicode/кириллица) или с emoji/пробелом
**Then** синхронный `INVALID_ARGUMENT` — `name` ограничен ASCII-паттерном `[a-z]([-_a-z0-9]{0,61}[a-z0-9])?` (non-ASCII не проходит proto-pattern)

---

## F13 — Единый тон ошибок by-lane (INTERNAL-opaque / immutable / malformed-first) + peer-validate fail-closed

> `→ api-conventions §error-format` · `→ security §hardening инв-1` · `→ unified §1 conv-11, §5 инв-5`
> **AS-IS**: compute маппит SQLSTATE→gRPC; INTERNAL-дефолт есть. `compute→iam` (`ProjectService.Get`/`Check`)
> и `compute→geo` (`ZoneService.Get`) **уже существуют** (peer-validate zone/project). Редизайн сохраняет
> тон, добавляет by-lane reason-token (Phase-0-gated).

### Сценарий COMP-1-32 (edge): INTERNAL никогда не эхает pgx/SQL

**ID:** COMP-1-32

**Given** нижележащая не-замапленная DB-ошибка на любом compute-RPC (Instance или MachineType)

**When** RPC возвращает `INTERNAL`
**Then** `status.Convert(err).Message() == "internal error"` (или `NotContains(msg, <pgx/host/port/db-текст>)`) — regression-lock на **сообщение**, не только код `codes.Internal` (обе листенера — internal :9091 не освобождён; security §hardening инв-1)

### Сценарий COMP-1-33 (negative): project/zone peer-validate reject; peer down → UNAVAILABLE (fail-closed); authz-first толерантность

**ID:** COMP-1-33

**Given** проекта `prj-ghost` в `kacho-iam` нет

**When** `InstanceService.Create` c `projectId="prj-ghost"`
**Then** reject — `oneOf([403, 400, 404])`: gateway scope_extractor на `project` (unscoped/well-formed-nonexistent) **короткозамыкается authz-first 403** ДО backend peer-validate (anti-BOLA); если authz прошёл — `compute→iam ProjectService.Get` не находит проект → reject (`INVALID_ARGUMENT`/by-lane `FAILED_PRECONDITION`, `[reason-token PHASE-0-GATED]`). Negative толерантен к authz-ordering (`testing.md` authz-first)

**When** `InstanceService.Create` c `zoneId="no-such-zone"` (в geo нет)
**Then** `Operation.error`/sync reject — `compute→geo ZoneService.Get` не находит зону (**AS-IS** зеркалит vpc→geo: `INVALID_ARGUMENT "unknown zone id '<X>'"`; by-lane `FAILED_PRECONDITION` — `[PHASE-0-GATED]`)

**When** `kacho-iam` (или `kacho-geo`) недоступен, `Create` с валидным `projectId`/`zoneId`
**Then** `Operation.error` — `UNAVAILABLE` (fail-closed для мутации; unified §4 seam-B) — инстанс с непроверенным владельцем/зоной **не** создаётся

---

## F14 — `InstanceService.List` — listauthz row-filter + pagination-validate ДО authz-short-circuit + cursor/filter

> `→ api-conventions §pagination/Gotcha` · `→ security инв-7` · `→ `make audit-list-filter``
> **AS-IS**: `InstanceService.List` есть, но подвержен **документированному рецидивирующему классу**
> (реальные инциденты compute disk/image/nlb): валидация `page_size`/`page_token` обязана идти **ДО**
> listauthz empty-grant short-circuit — иначе caller без грантов получает `200 {[]}` (или authz-403)
> на garbage-token/`page_size>1000` вместо `400`. vpc — эталон. Filter whitelist фазы —
> **`name=` и только он** (см. §Reconcile F14 filter-whitelist ниже); любое другое поле →
> `400 INVALID_ARGUMENT` с именем поля в сообщении.

#### Reconcile F14 filter-whitelist (2026-07-27) — фаза остаётся `name=`

Прежняя редакция F14/COMP-1-36 заявляла whitelist `name=`/`placementGroupId=`/`instanceKind=`.
Реализация whitelist'ит **только `name=`**, что совпадает с нормативным
`api-conventions.md` §pagination/filter («текущая фаза — `name=`»). Расхождение сведено
**в пользу кода**; расширение отложено в COMP-3 вместе с ресурсом `PlacementGroup`.

Основания (проверены на коде и на живой Postgres, не декларативно):

1. **Заявленное написание нереализуемо как есть.** `pkg/filter.Parse` подставляет имя поля в
   SQL **дословно** (`FilterAST.ToSQL`), а колонки — snake_case. Замер: `… AND instanceKind = $1`
   → `SQLSTATE 42703 column "instancekind" does not exist`; то же для `placementGroupId`. То есть
   camelCase-написание из дока дало бы `INTERNAL`, а не отфильтрованную страницу.
2. **`instanceKind` не фильтруется строкой в принципе.** `instances.instance_kind` — `INTEGER`
   (ordinal enum, миграция 0016), а парсер производит только строковое значение. Замер:
   `… AND instance_kind = 'CONTAINER'` → `SQLSTATE 22P02 invalid input syntax for type integer`.
   Нужен enum-декодер в общем парсере — кросс-сервисное изменение `pkg/filter`, не правка compute.
3. **Индекса под новые поля нет, и заводить его сейчас нечем оправдать.** Дополнительное поле
   фильтра без индекса превращает `List` в полное сканирование под нагрузкой. `instance_kind` —
   ≤3 значения (нулевая селективность), `placement_group_id` — `DEFAULT ''` практически на всех
   строках, а сам `PlacementGroup` как ресурс появляется только в **COMP-3**: индексировать
   поле, которое пока никто не населяет осмысленно, — это стоимость записи без выигрыша чтения.
4. **`placementGroupId` в COMP-1 — opaque passthrough** (OQ4, COMP-1-22): без existence/coherence.
   Фильтр по нему становится осмысленным одновременно с самим ресурсом — в COMP-3, где и
   заводится вместе со **своим partial-индексом** (`(project_id, placement_group_id, created_at, id)
   WHERE placement_group_id <> ''`).

Наблюдаемый контракт фазы (залочен, не «на честном слове»): любое не-`name` поле фильтра →
`400 INVALID_ARGUMENT "Bad expression at column 1. Unknown field: \"<field>\""` — **никогда**
молчаливое игнорирование (иначе caller получает чужие строки под фильтром, который он считает
применённым). Regression: `services/compute/internal/repo/list_filter_whitelist_test.go`
(Instance/Disk/Image/Snapshot × 6 полей, assert кода **и** сообщения) + newman
`INST-RD-LST-FILTER-UNKNOWN-FIELD-REJECTED`. Запись отклонения —
`services/compute/docs/architecture/07-known-divergences.md` §12.

### Сценарий COMP-1-34 (positive/negative): listauthz row-filter — caller видит только свои Instances (anti-BOLA)

**ID:** COMP-1-34

**Given** `prj-acme` содержит `ins-a`, `ins-b`; `prj-other` содержит `ins-x`; caller — `viewer` только на `prj-acme`

**When** `InstanceService.List(projectId="prj-acme")`
**Then** `200` с `ins-a`, `ins-b`; `ins-x` **отсутствует** (listauthz row-filter — результат отфильтрован per-object; security-инвариант + CI-гейт `make audit-list-filter` включает `compute.instances.list`)
**And** caller **без** грантов на `prj-acme` → пустая страница (empty-grant short-circuit) — но **после** pagination-validate (COMP-1-35)

### Сценарий COMP-1-35 (negative): pagination-validate ДО authz empty-grant short-circuit

**ID:** COMP-1-35

**Given** caller **без** грантов на проект (пустой grant → `AllowedIDs==0`)

**When** `InstanceService.List` с `pageSize=1001` (> max 1000)
**Then** `INVALID_ARGUMENT` (`corevalidate.PageSize` — **отвергается, не clamp'ится**) — **ДО** empty-grant short-circuit

**When** `InstanceService.List` с garbage `pageToken="!!!not-base64!!!"`
**Then** `INVALID_ARGUMENT` (`DecodePageToken` garbage→InvalidArgument) — тоже ДО authz-short-circuit. Порядок: **format-validate → authz-resolve → empty-grant short-circuit → repo**. Regression: unit на `ValidatePagination`

### Сценарий COMP-1-36 (positive/edge/negative): cursor-страница + filter `name=` + не-whitelisted поле отвергается

**ID:** COMP-1-36

**Given** `prj-acme` содержит 3 Instance (2 VM, 1 CONTAINER); caller — `viewer` на `prj-acme`

**When** `InstanceService.List(projectId="prj-acme", pageSize=2)`
**Then** 2 Instance (cursor `(created_at,id)` ASC) + непустой `nextPageToken`; следующая страница отдаёт 3-й + пустой `nextPageToken`

**When** `InstanceService.List(projectId="prj-acme", filter="name=\"<имя одного из них>\"")`
**Then** `200` ровно с этим Instance (whitelist фазы — **`name=` и только он**)

**When** `InstanceService.List(projectId="prj-acme", filter="name=\"no-match\"")`
**Then** `200` с пустым `instances[]` (не ошибка)

**When** `InstanceService.List(projectId="prj-acme", filter="instanceKind=\"CONTAINER\"")` — поле **вне** whitelist'а
**Then** `INVALID_ARGUMENT` (`400`) с сообщением `Bad expression at column 1. Unknown field: "instanceKind"` — неподдерживаемое поле **отвергается явно, НИКОГДА не игнорируется молча** (иначе caller получил бы нефильтрованную страницу под фильтром, который считает применённым). То же для `placementGroupId=` и для snake_case-написаний. Обоснование фазы и план расширения — §Reconcile F14 filter-whitelist

---

## F15 — `InstanceService.Delete` (durable-row-delete + name-recycle; negatives)

> `→ api-conventions §error-format` · `→ data-integrity §within-service` · `→ module-compute rule 11`
> **В COMP-1 `Delete` = durable-row-delete БЕЗ detach-саги**: launch-`*Specs` (NIC/Volume) **не
> материализуются** (COMP-2) ⇒ нет attach-state/cross-service teardown, который надо разбирать.
> `Delete` — **hard-delete** строки Instance (не soft/tombstone): `Get` после → `NOT_FOUND`,
> и непустое `name` **освобождается** — снова Create-able в том же проекте (завязано на partial
> `UNIQUE(project_id,name) WHERE name<>''`, F12). Реальный NIC/Volume detach-teardown + compensation
> на удаление привязанного инстанса — **COMP-2** (когда саги materialize'ят). Owner никого не спрашивает
> на Delete (ban #4 — нет cross-service cascade).

### Сценарий COMP-1-37 (positive/edge): Delete → Operation done → Get NOT_FOUND; name-recycle (hard-delete)

**ID:** COMP-1-37

**Given** `Instance ins-…` (`name="trainer-node-01"`, VM) в `prj-acme` создан и durable

**When** `InstanceService.Delete` (`DELETE /compute/v1/instances/ins-…`)
**Then** ответ — `Operation`; `metadata` несёт `instanceId` сразу; после poll `done==true && !error`, последующий `InstanceService.Get(ins-…)` → `NOT_FOUND "Instance ins-… not found"` (**hard-delete**, не tombstone)

**When** (**name-recycle**) `InstanceService.Create` с тем же `name="trainer-node-01"` в том же `prj-acme` (после hard-delete предыдущего)
**Then** `done` без ошибки — непустое `name` **освобождено** hard-delete'ом (partial `UNIQUE(project_id,name) WHERE name<>''` больше не занят удалённой строкой; F12 — db-review подтверждает, что удаление снимает UNIQUE-slot, а не soft-tombstone его держит)

### Сценарий COMP-1-38 (negative): malformed id → INVALID_ARGUMENT first-statement; absent id → authz-first tolerant

**ID:** COMP-1-38

**When** `InstanceService.Delete` с `instanceId="not-an-ins-id!!"` (malformed)
**Then** синхронный `INVALID_ARGUMENT "invalid instance id 'not-an-ins-id!!'"` — **первым стейтментом** RPC (до repo/authz-резолва)

**When** `InstanceService.Delete` с well-formed-но-несуществующим `ins-…` (строки нет)
**Then** `oneOf([403, 404])` — authz-first толерантность: gateway scope_extractor на `instance_id` (well-formed-nonexistent) может **короткозамкнуть 403** (scope_extractor не резолвит target→project, anti-BOLA) ДО backend `NOT_FOUND`; если authz прошёл — `NOT_FOUND "Instance ins-… not found"`. Negative толерантен к authz-ordering (`testing.md` authz-first; никогда `200`/успех на absent)

---

## Definition of Done

COMP-1 готова к merge только при выполнении ВСЕГО чек-листа (`ai-tooling.md` §lifecycle gate 4-7; `testing.md`):

**Traceability + тесты (1-to-1):**
- [ ] Каждый `COMP-1-NN` имеет зелёный **integration-тест** (testcontainers Postgres 16) — `Test<Resource>_COMP_1_NN` (напр. `TestInstance_COMP_1_01`, `TestMachineType_COMP_1_18`) — покрывающий SQL-сторону: `UNIQUE`/partial-index/CHECK/concurrent-race где применимо.
- [ ] **Concurrent-race обязателен** (data-integrity §5): `COMP-1-30` (дубль name-race) — integration `-race`, детерминированный (blocker держит UNIQUE-слот, backlog копится, ровно один writer выигрывает), **не** `time.Sleep`. **`op.error`-перед-`metadata`** дисциплина зафиксирована (`COMP-1-30`: pre-allocated `instanceId` на `done+error`).
- [ ] **STOPPED-gate ЭНФОРСМЕНТ** (`COMP-1-27`): реальный `Update{updateMask:["machineTypeId"]}` на COMP-1-инстансе (никогда не STOPPED) → sync `FAILED_PRECONDITION` — тест **не требует** `Stop` (предусловие недостижимо ⇒ always-reject); поле остаётся в known-set.
- [ ] **`Delete` hard-delete + name-recycle** (`COMP-1-37`): integration подтверждает, что hard-delete снимает partial-`UNIQUE(project,name)`-slot (не soft-tombstone) → тот же непустой `name` снова Create-able в проекте — **db-review** (db-architect-reviewer) на корректность DELETE + UNIQUE-slot-release.
- [ ] Каждый **public-наблюдаемый** `COMP-1-NN` (Instance CRUD **incl. `Delete` F15**, `InstanceService.List` F14, `MachineTypeService.Get/List`, field-absence F11/F24, BVA F31 **incl. non-ASCII name**) имеет зелёный **newman-кейс** `tests/newman/cases/*.py` c аннотацией `# verifies COMP-1-NN` — ≥1 happy + ≥1 negative на фичу; трассировка `COMP-1-NN ↔ Test<R>_COMP_1_NN ↔ cases/*.py`.
- [ ] **List-регрессия обязательна** (api-conventions Gotcha + security инв-7): unit на `ValidatePagination` для `InstanceService.List` (garbage-token / `pageSize>1000` → `InvalidArgument`) — **до** listauthz empty-grant short-circuit (`COMP-1-35`); listauthz row-filter покрыт (`COMP-1-34`) — `make audit-list-filter` включает `compute.instances.list`.
- [ ] **Internal-only** сценарии (`InternalMachineTypeService` admin-CRUD, `COMP-1-21`; future infra-проекция `COMP-1-29`) покрываются **integration + bufconn** (не newman-public); **отсутствие `InternalMachineTypeService` на external mux** — сам по себе assert (api-gateway-audit).
- [ ] TDD-порядок: RED (падает по нужной причине) ДО кода, пара RED→GREEN в PR.

**e2e-smoke (real gateway, заказчик проверяет — `make -C deploy e2e-test` / `grpcurl`):**
- [ ] `InstanceService.Create` (VM, минимальный redesign-payload) → poll `Operation` `done` → `Get` отдаёт `instanceKind=="VM"`, resolved `machineTypeId`+`effectiveResources°`, `bootSource{type,id}` через реальный api-gateway (материализация NIC/Volume + переход к `RUNNING` — COMP-2, не проверяется здесь).
- [ ] `MachineTypeService.List` читается **zero-binding** project'ом (ambient, `COMP-1-18`); GPU-discovery `family=GPU&minGpus=4` (`COMP-1-19`).
- [ ] `InstanceService.Delete` → poll `done` → `Get` `NOT_FOUND`; **name-recycle** — тот же непустое `name` снова Create-able в проекте (`COMP-1-37`) через реальный api-gateway.
- [ ] two-projection field-absence на **реальном** gateway-ответе: public `Instance` НЕ содержит YC-cruft/инфра (`COMP-1-24/28`).

**Deliverables редизайна (implementer обязан выполнить — иначе AS-IS остаётся):**
- [ ] **AS-IS retire (ban #2):** удалить с входа/публичной поверхности `platform_id`, `ResourcesSpec resources_spec`, `core_fraction`, `MetadataOptions{gce_*,aws_*}`, `PlacementPolicy.HostAffinityRule{yc.*}`, `scheduling_policy{preemptible}`, `gpu_settings{gpu_cluster_id}`, `reserved_instance_pool_id`, `application` (breaking proto — reserved field numbers+names). `host_group_id`/`host_id` — остаются reserved (AS-IS).
- [ ] **NET-NEW proto+regen** (`buf lint`/`breaking`/`validate` зелёные, proto-api-reviewer): `instance_kind` + `vm_spec`/`container_spec` (oneof); `machine_type_id` + `effectiveResources°`; `boot_source{type,id}` + output-only `name°`/`resolvedDigest°`/`materializedVolume°`; `machine_type.proto` + `machine_type_service.proto` + `internal_machine_type_service.proto`; `service_account_id` → `common.v1.Referrer` (`[B1]`); vendor-agnostic `metadataOptions{metadataEndpoint,metadataTokenRequired}`.
- [ ] **Новая goose-миграция** (не редактировать применённые, ban #5): таблица `machine_types` (`UNIQUE(name)`, `family`/`status` CHECK, `effective_*`, `available_zones`); столбцы Instance `instance_kind`/`machine_type_id`/`boot_source_*`/`vm_spec`/`container_spec`/`placement_group_id`(opaque-slug, format-only); `UNIQUE(project_id,name) WHERE name<>''` (partial — hard-delete освобождает slot, F15 name-recycle). DB-review (db-architect-reviewer) на UNIQUE-slot-release при DELETE + STOPPED-gate CAS-семантику.
- [ ] Public RPC (`InstanceService` Get/List/Create/Update/Delete, `MachineTypeService` Get/List) зарегистрированы в api-gateway (`api-gateway-registrar`); `InternalMachineTypeService` — **только** internal mux (ban #6).

**Проектные гейты (финальная верификация):**
- [ ] `go test ./... -race` · `golangci-lint run` · `govulncheck` · `make audit-list-filter` зелёные.
- [ ] `make -C gateway permission-catalog-check` byte-identical (новые RPC в каталоге, ambient MachineType read — exempt как geo); newman зелёные (все public `COMP-1-NN`).
- [ ] Vault-trail: обновить `resources/compute-instance.md` (instanceKind/machineTypeId/bootSource/Referrer, retire YC-cruft), создать `resources/compute-machinetype.md`, `rpc/compute-instance-service.md`, `rpc/compute-machinetype-service.md`; `KAC/COMP-1.md`.

**MERGE-GATE (`[PHASE-0-GATED]` + B10 — жёсткие кросс-фазовые блокеры):**
- [ ] **COMP-1 НЕ мёржится, пока Phase-0 governance change-set не приземлит** (unified §9 MUST-close):
  (a) **B1** — `kacho.cloud.common.v1` 3-way ref-типы (`Referrer` для `serviceAccountId` F4);
  (b) **B3** — id-prefix hyphen (`ins-`/`mt-`) в `corevalidate` (F8/F20);
  (c) **B13** — `imageKind` дискриминатор (`storage.image` vs `registry.image`) согласован cross-module с storage/registry (F3);
  (d) **by-lane reason-token** таблица (F13 code-lane).
  До merge change-set: `serviceAccountId` — bare `string`; префикс non-hyphen (`epd`); bootSource-роутинг без формального `imageKind`; peer-validate absent-zone/project — текущая форма (`INVALID_ARGUMENT`). **Ungated** части (instanceKind-oneof F1, machineType-sizing/cpuGuaranteePercent F2, bootSource-grammar/bare-untagged-reject F3, unreachable-guard F5, launch-spec-shape F6, MachineType-каталог F7 + `InternalMachineTypeService`, YC-cruft retire F9, Update-mutability **incl. STOPPED-gate enforcement** F10, two-projection field-absence F11, `UNIQUE(project,name)`+race F12, INTERNAL-opaque F13, `List` listauthz+pagination-validate F14, **`Delete` hard-delete + name-recycle F15**, `placementGroupId` format-only passthrough) строятся без ожидания.
- [ ] **B10 gate:** COMP-1 (core Instance + MachineType) может мёржиться независимо от COMP-2 launch-саг. Но **compute GA gated-by storage convergence** (unified §9 B10): COMP-2 attach-саги (boot-Volume/ImageCatalog materialize) не стартуют до APPROVED+merge STOR-1. COMP-1 не вводит новых зависимостей на compute-owned `fd8`-Image (`[CROSS-MODULE]` — `bootSource.type=storage.image` роутит в storage `img-`).

---

## Changelog — что этот док покрывает

- **F1** `instanceKind∈{VM,CONTAINER}` oneof `vmSpec` XOR `containerSpec` (spoken-exclusion); immutable; lifecycle по kind (COMP-1-01..04) · **NET-NEW**.
- **F2** `machineTypeId` единственный канал sizing (mt-slug/имя, canonical echo mt-; `effectiveResources°`; `cpuGuaranteePercent` family-gated); **retire raw ResourcesSpec/platform_id/core_fraction** (ban #2) (COMP-1-05..08).
- **F3** `bootSource{type,id}` + `imageKind` (B13); grammar tag/digest внутри id; bare-untagged→400; output-only resolve/materialize→COMP-2 `[PHASE-0-GATED B1/B13]` (COMP-1-09..11).
- **F4** `serviceAccountId` class-C `Referrer{iam.service_account}` (graceful-dangling, B2); опционален `[PHASE-0-GATED B1]` (COMP-1-12..13).
- **F5** unreachable-guard (VM без ssh И external → 400; `acknowledgeUnreachable`); CONTAINER exempt (COMP-1-14..15) · **NET-NEW**.
- **F6** launch-`*Specs` SKELETON: `networkInterfaceSpecs` ИЛИ `useDefaultNetwork`; структурная валидация; саги/materialize/mirrors→COMP-2 (COMP-1-16..17).
- **F7** `MachineType` sync-каталог: public Get/List (filter name=/family=/minGpus=); GPU=гранулярность; DEPRECATED/RETIRED; admin-CRUD на Internal* (COMP-1-18..21) · **NET-NEW**.
- **F8** `ins-` prefix + malformed-first `[PHASE-0-GATED B3]` (AS-IS `epd` делит с Disk) (COMP-1-22).
- **F9** YC-cruft retire → vendor-agnostic `metadataOptions`; assert field-absence gce_*/aws_*/yc.* (ban #2 AS-IS massive removal) (COMP-1-23..24).
- **F10** Update mutability-классы: LIVE / next-boot-deferred / immutable (до UpdateMask) / Reinstall-only; unknown-mask→400; **STOPPED-gate ЭНФОРСИТСЯ в COMP-1** (предусловие STOPPED недостижимо ⇒ always-reject; COMP-2 добавляет лишь достижимость через Stop) (COMP-1-25..27).
- **F11** two-projection: public Instance без инфра (assert field-absence); host_group/host_id reserved; infra→Internal* (наполнение COMP-4) (COMP-1-28..29).
- **F12** `UNIQUE(project,name)` partial + concurrent name-race + `op.error`-перед-metadata дисциплина + BVA name/description/labels (incl. non-ASCII) (COMP-1-30..31).
- **F13** by-lane тон (INTERNAL-opaque) + project/zone peer-validate fail-closed (UNAVAILABLE) + authz-first толерантность `[reason-token PHASE-0-GATED]` (COMP-1-32..33).
- **F14** `InstanceService.List` listauthz row-filter (anti-BOLA) + **pagination-validate ДО authz-short-circuit** + cursor + filter `name=` (единственное поле фазы; прочие → 400 с именем поля — §Reconcile F14 filter-whitelist) (COMP-1-34..36).
- **F15** `InstanceService.Delete` hard-delete durable-row (БЕЗ detach-саги — launch-`*Specs` не материализуются) → `Get` `NOT_FOUND`; **name-recycle** (partial-UNIQUE slot освобождается); malformed-first / absent authz-first tolerant (COMP-1-37..38).

Покрытие обязательного минимума (task): instanceKind oneof XOR ✓ (COMP-1-01/02/03) · single sizing channel + raw-retire ✓ (COMP-1-05/07) · bootSource+imageKind ✓ (COMP-1-09/10) · serviceAccountId Referrer ✓ (COMP-1-12) · unreachable-guard ✓ (COMP-1-14) · MachineType sync-каталог + GPU-granularity ✓ (COMP-1-18/19/21) · YC-cruft retire (platform_id/host_affinity/MetadataOptions) ✓ (COMP-1-23/24) · concurrent name-race ✓ (COMP-1-30) · **Delete + name-recycle ✓ (COMP-1-37)** · PHASE-0-GATED/CROSS-MODULE помечены (B1/B3/B13, fd8-retire). Каждая фича — positive + ≥1 negative + edge.

Что изменилось в ре-ревью раунд 1 (по замечаниям acceptance-reviewer): (a) **[Delete]** добавлена F15 (`COMP-1-37/38`) — hard-delete + name-recycle + malformed/absent negatives; (b) **[STOPPED-gate]** COMP-1-27 3-й When переписан: gate **ЭНФОРСИТСЯ в COMP-1** (always-reject, не «enforcement→COMP-2») — устранён опасный дефект «применяет sizing на живом»; F10-intro синхронизирован; (c) OQ1 → resting-status пин `Get.status=="PROVISIONING"` в COMP-1-01; (d) OQ3 → `InternalMachineTypeService` под `/compute/v1/internal/machineTypes` (парити GEO-1), COMP-1-21/F7/traceability скорректированы; (e) OQ4 → `placementGroupId` format-only passthrough (COMP-1-22 + Out-of-scope §COMP-3, без coherence); (f) minor: `string image` #34 (не #26), non-ASCII name negative (COMP-1-31), `op.error`-перед-metadata note (COMP-1-30).

---

## Дефолты, зафиксированные на review (ре-ревью раунд 1)

Все 5 прежних open questions **разрешены ревьюером** и вшиты в сценарии/DoD выше:

1. **OQ1 — happy-path Create = durable-персист БЕЗ materialize.** Подтверждён корректным COMP-1
   Create-контрактом (НЕ втягивать NIC-сагу — она требует compensation-outbox B12). **+ resting-status
   запиннен**: `COMP-1-01` фиксирует `Get.status=="PROVISIONING"` **persisted** после Create-`done`
   (не оставлено implementer'у на выбор). `Operation.done` = durability, не materialize-видимость (ban #9).
2. **OQ2 — STOPPED-gated поля остаются в known-set И энфорсятся.** См. `COMP-1-27` + F10-intro:
   реальный `Update{machineTypeId}` на COMP-1-инстансе → sync `FAILED_PRECONDITION` (предусловие STOPPED
   недостижимо ⇒ always-reject); COMP-2 добавляет лишь достижимость STOPPED через `Stop`. Поля НЕ
   исключаются из known-set (unknown-mask-reject стабилен).
3. **OQ3 — `InternalMachineTypeService` (:9091, `system_admin`), НЕ seed-only.** Самоописываемый путь
   `/compute/v1/internal/machineTypes` (парити GEO-1 `/geo/v1/internal/…` — internal-vs-public
   неотличимость снята путём). Отражено: F7-intro, `COMP-1-21` (routing-miss + `Unimplemented` на external),
   Traceability-легенда, DoD.
4. **OQ4 — `placementGroupId` = opaque-slug passthrough.** Принимается/сохраняется, STOPPED-gated +
   immutable-семантика; валидируется **только формат** (well-formed `plg-` ИЛИ пусто → malformed
   `INVALID_ARGUMENT` first-statement, `COMP-1-22`), **БЕЗ** existence/coherence. `Create{placementGroupId,
   zoneId}` принимаются вместе без coherence-check (иначе half-coherence). Existence/spread/scheduler-zone —
   **COMP-3** (§Out-of-scope явно).
5. **OQ5 — `bootSource` COMP-1 = только форма.** grammar + type-whitelist `{storage.image,registry.image}`
   + bare-untagged-reject + output-field-reject (`COMP-1-09/10/11`); `tag→digest` resolve + существование
   образа + pull-grant precheck — **COMP-2**. Подтверждён без правок.

Открытых вопросов к reviewer нет — док готов к быстрому ре-ревью.
