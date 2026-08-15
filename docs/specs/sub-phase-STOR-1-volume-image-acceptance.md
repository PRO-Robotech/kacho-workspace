# Sub-phase STOR-1 (Volume block-lease + Image boot-image) — Acceptance

> Статус: **✅ APPROVED** (recorded by acceptance-reviewer verdict)
> Дата: 2026-07-20
> Ревьюер: acceptance-reviewer
> Эпик/тикет: KAC-STOR-1 (пересборка-2026, Phase-2 step 6 — `kacho-storage` first-class owner, B10)

## Обзор

STOR-1 приводит **`Volume`** (уже реализованный блочный ZONAL-диск с attach-CAS) к
редизайну-2026 и вводит **`Image`** — **новый** ресурс VM boot-образа (`img-`), из
которого материализуется boot-`Volume`. Volume-часть — **conformance** существующего
контракта (attach-CAS через `InternalVolumeService`, FK-delete-safety, derived-status
**уже есть** в `project/kacho`) плюс редизайн-дельты: `vol-`-prefix (B3), `used_by`
→ `common.v1.Referrer` (B1), новое поле `source_image_id` (boot-materialize из Image).
Image-часть — **net-new**: нет proto, нет таблицы, нет кода — новый flat-ресурс + новая
миграция. `kacho-storage` — жёсткая зависимость якоря-compute (boot-Volume / ImageCatalog);
**compute GA gated-by этой сходимостью** (unified §9 B10).

Заказчик к approve контракта не подключается — approve выставляет `acceptance-reviewer`;
заказчик проверяет только финальный smoke/e2e (DoD §e2e-smoke).

---

## Декомпозиция редизайна `kacho-storage` на под-фазы (STOR-1..N)

| Под-фаза | Deliverable (end-to-end) | Ключевое | Статус |
|---|---|---|---|
| **STOR-1** | **`Volume` (redesign-conformance) + `Image` (net-new)** | ZONAL block-lease, attach-CAS (idempotent free-or-mine), placement-coherent с Instance; `img-` VM boot-image, `storage.image` Referrer (⟂ registry `registry.image`, B13), boot-Volume материализация из Image | **этот док** |
| **STOR-2** | **`Snapshot` (redesign-conformance) + snapshot-schedule** | Point-in-time Volume (`snp-`, `source_volume_id` — **уже есть**); region-scoped restore; recurring snapshot-policy (net-new) | follow-up |
| **STOR-3** | **fgaproxy owner-tuple hardening + compute-compensation Delete (B12)** | `storage → iam RegisterResource` для `storage_image` (Volume/Snapshot — **уже CS-1 GAP-D**); idempotent storage-side `Delete` на compute launch-fail + sweeper-реклейм DETACHED-volume past TTL (unified §5.4 B12 backstop) | follow-up |
| **STOR-4** *(опц.)* | **DiskType Internal-admin CRUD + `VolumeInternal` infra-проекция** | admin-каталог DiskType на `Internal*`; наполнение зарезервированных infra-полей `VolumeInternal` (data-plane increment, сейчас `reserved`) | deferred |

> STOR-1 — **основа**: без сошедшегося Volume/Image compute не может GA (boot-Volume /
> ImageCatalog / attach-сага). STOR-2/3/4 расширяют, не переопределяют STOR-1.

---

## Scope (что STOR-1 покрывает сценариями — positive + ≥1 negative + edge каждая)

| # | Фича | Трассировка |
|---|---|---|
| F1 | `Volume` flat-lifecycle: мутации→`Operation` (`volumeId` в `metadata` сразу), `state=READY` немедленно (control-plane), derived `status`, immutable-набор, `size_bytes` increase-only, `UNIQUE(project,name)` | volume.proto (AS-IS); unified §1 conv-1/2, §2 storage |
| F2 | `Volume` id-prefix `vol-` + malformed-id первым стейтментом `[PHASE-0-GATED B3]` | unified §1 conv-12, §8 B3 |
| F3 | Attach-CAS через `InternalVolumeService.Attach` — idempotent free-or-mine (не TOCTOU); Detach идемпотентен; **concurrent-race** | data-integrity §attach-CAS/§5; internal_volume_service.proto (AS-IS) |
| F4 | Placement-coherence `Volume`↔`Instance` (та же зона, self-describing peer-validate, ацикличность); zone-existence на Create через geo `[geoconsumer PHASE-0-GATED]` | data-integrity §placement-coherence; unified §5 инв-2 |
| F5 | Delete-safety FK RESTRICT (`"Volume <id> is in use"`); `device_name` UNIQUE; ≤1 boot-том (EXCLUDE) | data-integrity §within-service; 0003_storage_domain.sql (AS-IS) |
| F6 | `autoDelete`-семантика: запись на attach, экспозиция на `attachments[].autoDelete` / `usedBy[].owned`; cascade-исполнение compute-driven (out-of-scope) | storage-spec §1.1/§3.4 |
| F7 | `Volume.usedBy` → `kacho.cloud.common.v1.Referrer` (AS-IS legacy `reference.Reference`) `[PHASE-0-GATED B1]` | unified §4 seam-C, §8 B1 |
| F8 | Two-projection: public `Volume` без infra; `InternalVolumeService.GetInternal` (:9091) `VolumeInternal`; internal НЕ на external | security §infra-sensitive; unified §5 инв-1 |
| F9 | **NET-NEW** `Volume.source_image_id` — материализация boot-Volume из `Image` (same-DB FK **ON DELETE SET NULL**, lineage-clear); mutual-exclusion с `source_snapshot_id`; regional-coherence zone∈image.region | unified §2 storage, §8 B13 |
| F10 | **NET-NEW** `Image` (`img-`) flat-ресурс: мутации→`Operation`, `UNIQUE(project,name)`, lifecycle, **новая миграция** `[PHASE-0-GATED B3 prefix]` | unified §2 storage (Image); net-new |
| F11 | **NET-NEW** `Image` как `storage.image` Referrer-цель — **ортогонален** registry `registry.image` (B13 imageKind-дискриминатор) `[PHASE-0-GATED B1/B13]` | unified §2 compute ImageCatalog, §8 B13 |
| F12 | **NET-NEW** `Image` source-oneof `{sourceSnapshotId\|sourceVolumeId}` exactly-one (blank DEFER); public `{sizeBytes°,minDiskBytes°,format°}` (`format°` native Kachō enum); two-projection (blob-layout/bucket/engineNamespace — Internal) | unified §2 registry (bucket/blob Internal), §5 инв-1 |
| F13 | Единый тон ошибок by-lane (INTERNAL-opaque, immutable-текст, malformed-first) `[reason-token PHASE-0-GATED]`; Image owner-tuple anti-BOLA (`storage_image:<id>`, emit в STOR-1, hardening→STOR-3) | unified §1 conv-11, §5 инв-5; edges/storage-to-iam-fgaproxy |
| F14 | **NET-NEW** `ImageService.List` — listauthz row-filter (anti-BOLA) + **pagination-validate ДО authz-short-circuit** (`page_size>1000`/garbage-token → INVALID_ARGUMENT) + cursor + `filter name=` | api-conventions §pagination/Gotcha; security инв-7; `make -C services/storage audit-list-filter` |

---

## Out-of-scope (явно НЕ в STOR-1)

- **Compute-сторона attach** — `Instance.AttachDisk/DetachDisk`-сага (compute-Operation,
  оркестрирующая `InternalVolumeService.Attach`), зеркала `Instance.boot_volume /
  secondary_volumes`, object-scoped authz на паре `instance_id`+`volume_id` — это редизайн
  **compute** (Phase-2 step 9). STOR-1 владеет **storage-стороной** attach (`InternalVolumeService.Attach/Detach/ListAttachments`).
- **`Snapshot` + snapshot-schedule** — STOR-2. (`Volume.source_snapshot_id` restore — **уже
  существует** в AS-IS; STOR-1 его не переопределяет, только добавляет параллельный `source_image_id`.)
- **fgaproxy hardening + compute-compensation Delete (B12)** — STOR-3. Owner-tuple emit для
  Volume/Snapshot **уже** CS-1 GAP-D; для Image STOR-1 добирает минимум для anti-BOLA (F13),
  полный sweeper-реклейм/compensation — STOR-3.
- **DiskType admin-CRUD редизайн + наполнение `VolumeInternal.infra°`** — STOR-4 (сейчас infra
  `reserved`, data-plane increment).
- **Data-plane** (реальный provisioning LUN/NVMe, online-grow гостевой ФС, blob-upload
  pipeline) — не моделируется (control-plane only).

---

## Traceability-легенда

`°` = output-only (server-derived, на вход не принимается). REST-пути: public
`/storage/v1/…` (:9090, external-safe); `InternalVolumeService`/`InternalImageService` —
**gRPC-only :9091** (mTLS, **нет** google.api.http, **не** на external mux; проверяются
через integration/bufconn). JSON — camelCase; `createdAt°`/`attachedAt°` усечены до
секунд на wire. op-id prefix storage — `sop`.

**AS-IS** = реальное текущее состояние кода `project/kacho` (монорепо; `services/storage/`,
`proto/kacho/cloud/storage/v1/`). Драфт `docs/plans/kacho-storage-volume-and-instance-attach-spec.md`
был pre-GA-черновиком — STOR-1 приводит его к своду-2026 (`00-unified-system-design.md`).
**Легаси не трогаем** (только `project/kacho`).

**`[PHASE-0-GATED]`** = сценарий/поле приземляется **только** после merge Phase-0 governance
change-set (unified §7/§9): **B1** (`kacho.cloud.common.v1` 3-way ref-типы `ResourceRef`/`Referrer`/`OciReferrer`),
**B3** (id-prefix hyphen в `corevalidate`), **B13** (`imageKind` дискриминатор storage.image vs
registry.image), **by-lane reason-token** таблица. До merge — действует AS-IS-форма (см. Merge-gate в DoD).

**Resolved design-defaults** (7 OQ **разрешены** ревьюером — внесены как подтверждённые дефолты):
OQ1 `Image` placement **REGIONAL** (`placementType°==REGIONAL` const; regional-coherence enforcement
через `geoconsumer` — Phase-0-gated); OQ2 source **oneof `{sourceSnapshotId|sourceVolumeId}` exactly-one**
(blank-upload **DEFER** до data-plane blob-pipeline); OQ3 public `{sizeBytes°, minDiskBytes°, format°}`,
`format°` = **native Kachō enum** (ban #2, single-tier default); OQ4 `img-` **claim за storage** +
**ретайр compute `fd8`-Image** (координация: `[B3]` prefix-registry + `[B13]` imageKind + compute-redesign #13);
OQ5 `source_image_id` **ON DELETE SET NULL** (parity с `source_snapshot_id`); OQ6 owner-tuple **emit в STOR-1**
(reuse CS-1 GAP-D outbox, `storage_image` — anti-BOLA correctness); OQ7 materialization **READY немедленно**
(durable `Operation.done` сразу, ban #9 — не гейтит downstream).

**`[NET-NEW]`** = ресурс/поле, которого нет в AS-IS (нет proto/таблицы/кода) — новый proto+regen
и **новая goose-миграция** (не редактируем применённые `0001`–`0006`, ban #5).

---

## F1 — `Volume` flat-lifecycle: `Operation` / derived-status / immutables / size increase-only / UNIQUE(project,name)

> `→ unified §1 conv-1/2, §2 storage` · `→ volume.proto` (AS-IS)
> **AS-IS** (`volume.proto`, `0003_storage_domain.sql`): `Volume` уже flat (id/projectId/
> createdAt/updatedAt/name/description/labels/zoneId/diskTypeId/sizeBytes/blockSize/
> sourceSnapshotId/status/attachments[]/usedBy). `state ∈ {CREATING,READY,DELETING,ERROR}`
> хранится; `status ∈ {AVAILABLE,IN_USE}` **derived** из наличия `volume_attachments`-строки
> (дрейф невозможен). `Create` → `state=READY` **сразу** (control-plane, provisioning нет).
> `Update` mutable: name/description/labels/sizeBytes(рост); immutable: zoneId/diskTypeId/
> blockSize/sourceSnapshotId. STOR-1 **сохраняет** контракт, добавляет F9 (`source_image_id`).

### Сценарий STOR-1-01 (positive): Create → Operation (volumeId в metadata сразу), poll, Get отдаёт READY→AVAILABLE

**ID:** STOR-1-01

**Given** проект `prj-acme` существует; зона `ru-central1-a` открыта; DiskType `block-balanced` в каталоге
**And** вызывающий имеет `editor` на `prj-acme`

**When** клиент вызывает `VolumeService.Create` (`POST /storage/v1/volumes`) с payload:
  - `projectId` = `"prj-acme"`
  - `name` = `"data-vol-01"`
  - `zoneId` = `"ru-central1-a"`
  - `diskTypeId` = `"block-balanced"`
  - `sizeBytes` = `10737418240`

**Then** ответ — `Operation`; `metadata` анмаршалится в `CreateVolumeMetadata` с непустым `volumeId` **до** `done` (unified §3 инвариант)
**And** после poll `OperationService.Get` до `done==true && !error`, `result.response` анмаршалится в `Volume`
**And** последующий `VolumeService.Get` возвращает `Volume` с `id` (префикс — см. F2), `projectId=="prj-acme"`, `createdAt°` усечён до секунд, `sizeBytes==10737418240`, `blockSize==4096` (default), `status==AVAILABLE` (derived: `state=READY` без attachment), `attachments==[]`, `usedBy==[]`

### Сценарий STOR-1-02 (negative): невалидный вход — sizeBytes≤0 → INVALID_ARGUMENT; неизвестный diskTypeId → FAILED_PRECONDITION

**ID:** STOR-1-02

**Given** проект `prj-acme`, зона `ru-central1-a`

**When** `VolumeService.Create` с `sizeBytes = 0`
**Then** синхронный `INVALID_ARGUMENT` (proto-валидация `sizeBytes>0`); операция не пишется

**When** `VolumeService.Create` с `diskTypeId = "no-such-type"` (well-formed slug, в каталоге нет)
**Then** после `done`, `Operation.error` — `FAILED_PRECONDITION` (same-DB FK `disk_type_id → disk_types` RESTRICT `23503`); текст **обезличен** (без pgx/SQL-leak)

### Сценарий STOR-1-03 (edge): Update — sizeBytes increase-only; immutable-поля отвергаются ДО UpdateMask

**ID:** STOR-1-03

**Given** `Volume vol-…` с `sizeBytes == 10737418240`

**When** `VolumeService.Update` c `updateMask=["sizeBytes"]`, `sizeBytes = 5368709120` (меньше текущего)
**Then** `INVALID_ARGUMENT "Volume size can only be increased"` (increase-only CAS, не software-compare)

**When** `VolumeService.Update` c `updateMask=["zoneId"]` (immutable)
**Then** синхронный `INVALID_ARGUMENT "zoneId is immutable after Volume.Create"` (immutable-switch срабатывает **до** `corevalidate.UpdateMask`)
**And** то же для `diskTypeId` / `blockSize` / `sourceSnapshotId` / `sourceImageId` (F9)

### Сценарий STOR-1-04 (negative+edge): duplicate name в проекте → ALREADY_EXISTS; то же имя в другом проекте → OK

**ID:** STOR-1-04

**Given** `Volume` с `name="data-vol-01"` в `prj-acme` уже существует

**When** второй `Create` с `name="data-vol-01"` в `prj-acme`
**Then** `Operation.error` — `ALREADY_EXISTS` (partial `UNIQUE(project_id,name) WHERE name<>''`)
**And** `Create` с `name="data-vol-01"` в **другом** проекте `prj-beta` → `done` без ошибки (UNIQUE scoped проектом)
**And** `Create` c пустым `name` дважды в одном проекте → оба `done` (partial-UNIQUE не ловит `name=''`)
**And** *(edge, non-blocking)* **две конкурентные** `Create` с **одинаковым** `name` в одном проекте → ровно одна `done`, другая `ALREADY_EXISTS` (UNIQUE-race на DB-уровне, не software check-then-act)

### Сценарий STOR-1-30 (negative, BVA): границы `name` / `description` / `labels` (Volume и Image)

**ID:** STOR-1-30

**Given** проект `prj-acme`, зона/регион валидны

**When** `Create` (Volume или Image) с `name` длиной **64** символа (граница 1..63 + 1)
**Then** синхронный `INVALID_ARGUMENT` (proto-паттерн `name`); `name` длиной **63** → OK; `name=""` → OK (optional, partial-UNIQUE не применяется)

**When** `Create` с `description` длиной **257** (≤256 + 1)
**Then** синхронный `INVALID_ARGUMENT`; `description` 256 → OK

**When** `Create` с **65** парами `labels` (≤64 + 1), либо ключ не по regex, либо значение >63
**Then** синхронный `INVALID_ARGUMENT` (`kacho_labels_valid` CHECK + proto-валидация); 64 валидных пары → OK

---

## F2 — `Volume` id-prefix `vol-` + malformed-id первым стейтментом `[PHASE-0-GATED B3]`

> `→ unified §1 conv-12, §8 B3`
> **AS-IS** (`domain/volume.go`): `PrefixVolume = "vol"` (**без** дефиса), `PrefixSnapshot="snp"`,
> op-root `"sop"`. Редизайн B3 фиксирует **hyphen-форму** (`vol-`/`img-`/`snp-`) в `corevalidate`
> prefix→type-router. До Phase-0 — текущая non-hyphen форма.

### Сценарий STOR-1-05 (negative) `[PHASE-0-GATED B3]`: malformed volume id → INVALID_ARGUMENT первым стейтментом; well-formed-но-нет → NOT_FOUND

**ID:** STOR-1-05 `[id-prefix форма PHASE-0-GATED B3]`

**When** `VolumeService.Get` с `volumeId = "not-a-vol-id!!"` (malformed)
**Then** синхронный `INVALID_ARGUMENT "invalid volume id 'not-a-vol-id!!'"` — **первым стейтментом** RPC (`corevalidate.ResourceID` до любого repo-вызова)

**When** `VolumeService.Get` с well-formed-но-несуществующим id (правильный префикс+base32, строки нет)
**Then** `NOT_FOUND "Volume <id> not found"` (через `repo.Get`)

**And** `[PHASE-0-GATED B3]`: **форма** валидного префикса меняется `vol` → `vol-` после приземления B3 в `corevalidate`. **AS-IS** до Phase-0: префикс `vol` (non-hyphen). Merge-gate — §Definition of Done. Код (`INVALID_ARGUMENT` first-statement) и тон (`"invalid volume id '<X>'"` / `"Volume <id> not found"`) — **ungated**

---

## F3 — Attach-CAS через `InternalVolumeService.Attach` (idempotent free-or-mine, не TOCTOU) + concurrent-race

> `→ data-integrity §attach-CAS/§5` · `→ internal_volume_service.proto`, `0003_storage_domain.sql` (AS-IS)
> **AS-IS**: `InternalVolumeService.Attach/Detach/ListAttachments/GetInternal` **реализованы**
> (:9091, mTLS, per-RPC authz-Check, scope_extractor на `volume_id`). Attach — атомарный
> `INSERT … ON CONFLICT (volume_id) DO NOTHING` CAS: том `state='READY'`, свободен ИЛИ уже наш →
> вставка; конфликт → disambiguation-SELECT → sentinel. `volume_attachments.volume_id` PK+FK
> RESTRICT ⇒ **один attachment на том глобально** (ZONAL block-lease). storage **никогда** не
> зовёт compute (self-describing payload; ацикличность, KAC-266). STOR-1 **верифицирует** контракт
> (redesign не меняет CAS-механику).

> **Scope-примечание:** attach/detach — Internal :9091, **не** на external mux ⇒ покрываются
> **integration (testcontainers) + bufconn**, а НЕ newman-public. Отсутствие на external — сам по
> себе assert (api-gateway-audit). Tenant-facing async-мутация живёт в compute-`AttachDisk` (out-of-scope).

### Сценарий STOR-1-06 (positive): Attach happy — CAS, derived IN_USE, usedBy заполнен

**ID:** STOR-1-06

**Given** `Volume vol-data01` в `AVAILABLE` (`state=READY`, без attachment), зона `ru-central1-a`, проект `prj-acme`

**When** воркер compute вызывает `InternalVolumeService.Attach` (:9091) с self-describing payload:
  - `volumeId` = `"vol-data01"`
  - `instanceId` = `"ins-web01"`, `instanceName` = `"web01"`
  - `instanceZoneId` = `"ru-central1-a"`, `projectId` = `"prj-acme"`
  - `deviceName` = `"sdb"`, `mode` = `READ_WRITE`, `isBoot` = `false`, `autoDelete` = `false`

**Then** ответ — `AttachVolumeResponse` с обновлённым `Volume`; `status==IN_USE` (derived из наличия строки)
**And** `VolumeService.Get(vol-data01).attachments` = 1 запись `{instanceId:"ins-web01", deviceName:"sdb", mode:READ_WRITE, attachedAt°(усечён)}`
**And** `usedBy` = 1 ссылка на инстанс (форма — см. F7)

### Сценарий STOR-1-07 (negative, **CONCURRENCY**): двойной attach одного тома → ровно один проходит

**ID:** STOR-1-07 `[concurrent-race — обязателен в DoD]`

**Given** `Volume vol-data01` в `AVAILABLE`

**When** **две конкурентные** `InternalVolumeService.Attach` на `vol-data01` с **разными** `instanceId` (`ins-a`, `ins-b`), стартуют одновременно

**Then** **ровно одна** возвращает успех (`status==IN_USE`, её `instanceId` в `attachments[0]`)
**And** вторая → `FAILED_PRECONDITION` c **сообщением** `"Volume vol-data01 is in use"` (behaviour-level assert текста, не только кода)
**And** тест — integration `-race`, детерминированный (blocker держит слот CAS, backlog копится), **не** `time.Sleep` (data-integrity §5: single-statement `INSERT … ON CONFLICT` под row-lock на PK `volume_id`)

### Сценарий STOR-1-08 (edge, idempotency): re-attach того же инстанса → OK; двойной detach → идемпотентный OK

**ID:** STOR-1-08

**Given** `vol-data01` уже примонтирован к `ins-web01`

**When** повтор `InternalVolumeService.Attach(vol-data01, instanceId=ins-web01, deviceName=sdb, …)` (те же данные)
**Then** идемпотентный успех (`ON CONFLICT` + «уже наш» → OK), состояние не меняется — покрывает replay воркера после краха до MarkDone

**When** `InternalVolumeService.Detach(vol-data01, instanceId=ins-web01)`, затем повтор `Detach`
**Then** первый — `done` (строка удалена, `status→AVAILABLE` derived); повтор → идемпотентный OK (0 rows deleted, без ошибки)

### Сценарий STOR-1-09 (negative): attach на не-READY / device-collision / второй boot-том

**ID:** STOR-1-09

**Given** `vol-creating` в `state=CREATING` (или `DELETING`)
**When** `Attach(vol-creating, …)`
**Then** `FAILED_PRECONDITION "Volume is not available for attachment"` (CAS-SELECT `v.state='READY'` не матчит)

**Given** `ins-web01` уже несёт устройство `deviceName="sdb"` (том `vol-a`)
**When** `Attach(vol-b, instanceId=ins-web01, deviceName="sdb")`
**Then** `FAILED_PRECONDITION "device sdb is already in use on Instance ins-web01"` (`UNIQUE(instance_id,device_name)` `23505`)

**Given** `ins-web01` уже несёт boot-том (`isBoot=true`)
**When** `Attach(vol-c, instanceId=ins-web01, isBoot=true, deviceName="sda2")`
**Then** `FAILED_PRECONDITION` — у инстанса уже есть boot-том (`EXCLUDE USING gist (instance_id WITH =) WHERE is_boot` `23P01`)

---

## F4 — Placement-coherence `Volume`↔`Instance` (та же зона, self-describing, ацикличность) + zone-existence на Create

> `→ data-integrity §placement-coherence` · `→ unified §5 инв-2`
> **AS-IS**: attach-CAS уже несёт zone-coherence (`v.zone_id = $zone_id` из self-describing
> payload) → disambiguation `"Volume and Instance must be in the same zone"`. Том **всегда
> ZONAL** (anycast-тома нет) ⇒ zone-check безусловен. Редизайн-дельта: within-service zone-check
> остаётся DB-CAS (ungated); zone-**existence** на `Volume.Create` унифицируется через corelib
> `geoconsumer.ValidatePlacement` (Phase-0 helper, gated).

### Сценарий STOR-1-10 (negative): attach тома чужой зоны → FAILED_PRECONDITION; storage не зовёт compute

**ID:** STOR-1-10

**Given** `Volume vol-z2` в зоне `ru-central1-b`; payload инстанса несёт `instanceZoneId="ru-central1-a"`

**When** `InternalVolumeService.Attach(vol-z2, instanceZoneId="ru-central1-a", …)`
**Then** `FAILED_PRECONDITION "Volume and Instance must be in the same zone"` (CAS-SELECT `v.zone_id=$zone_id` не матчит; storage валидирует **свою** строку по self-describing payload)
**And** payload с чужим `projectId` (том проекта `prj-acme`, payload `projectId="prj-other"`) → `FAILED_PRECONDITION "Volume and Instance must be in the same project"` (CAS-SELECT `v.project_id=$project_id` не матчит — AS-IS `disambiguateAttach` эмитит **обе** placement-предиката)
**And** ацикличность: storage **не** вызывает `compute.InstanceService.Get` — `internal/clients/` НЕ импортирует compute-stub (arch-test assert; ребро `compute→storage` one-way в `polyrepo.md`)

### Сценарий STOR-1-11 `[PHASE-0-GATED geoconsumer]`: Create с неизвестной зоной → peer-validate reject; geo недоступен → UNAVAILABLE (fail-closed)

**ID:** STOR-1-11 `[by-lane код PHASE-0-GATED]`

**Given** зоны `no-such-zone` в `kacho-geo` нет

**When** `VolumeService.Create` с `zoneId="no-such-zone"`
**Then** `Operation.error` — reject (storage→geo `ZoneService.Get` не находит зону)
**And** `[PHASE-0-GATED]`: **код** — by-lane peer-validate lane `FAILED_PRECONDITION` **после** Phase-0 by-lane-таблицы; **AS-IS до Phase-0** — текущая форма (`INVALID_ARGUMENT "unknown zone id '<X>'"`, зеркалит vpc/compute→geo). Merge-gate — §DoD

**When** `kacho-geo` недоступен, `VolumeService.Create` с валидной `zoneId`
**Then** `Operation.error` — `UNAVAILABLE` (fail-closed для мутации; unified §4 seam-B) — том с непроверенной зоной **не** создаётся

### Сценарий STOR-1-29 (negative): project-existence peer-validate (Volume.Create/Image.Create) — unknown project reject; iam down → UNAVAILABLE; authz-first толерантность

**ID:** STOR-1-29

**Given** проекта `prj-ghost` в `kacho-iam` нет

**When** `VolumeService.Create` (или `ImageService.Create`) c `projectId="prj-ghost"`
**Then** reject — `oneOf([403, 400, 404])`: gateway scope_extractor на `project` (unscoped/well-formed-nonexistent) **короткозамыкается authz-first 403** ДО backend peer-validate (anti-BOLA); если authz прошёл — storage→iam `ProjectService.Get` не находит проект → reject (`INVALID_ARGUMENT`/by-lane `FAILED_PRECONDITION`, `[PHASE-0-GATED]`). Negative толерантен к authz-ordering (`testing.md` authz-first)

**When** `kacho-iam` недоступен, `Create` с валидным `projectId`
**Then** `Operation.error` — `UNAVAILABLE` (fail-closed для мутации; unified §4 `*→iam` seam-B) — ресурс с непроверенным владельцем **не** создаётся. **AS-IS**: `IAMClient.EnsureProjectExists` уже энфорсит fail-closed на Volume.Create; STOR-1 распространяет на Image.Create

---

## F5 — Delete-safety FK RESTRICT + device-UNIQUE + one-boot EXCLUDE (within-service DB-enforced)

> `→ data-integrity §within-service` · `→ 0003_storage_domain.sql` (AS-IS)
> **AS-IS**: `volume_attachments.volume_id → volumes ON DELETE RESTRICT` ⇒ `Volume.Delete`
> примонтированного тома блокируется на DB-уровне (не software-refcount, не TOCTOU).

### Сценарий STOR-1-12 (negative→positive): Delete примонтированного тома блокируется; после Detach — проходит

**ID:** STOR-1-12

**Given** `vol-data01` примонтирован к `ins-web01`

**When** `VolumeService.Delete(vol-data01)` (`DELETE /storage/v1/volumes/vol-data01`)
**Then** `Operation.error` — `FAILED_PRECONDITION` с **сообщением** `"Volume vol-data01 is in use"` (FK RESTRICT `23503`, behaviour-level assert)

**When** `InternalVolumeService.Detach(vol-data01, ins-web01)`, затем `VolumeService.Delete(vol-data01)`
**Then** `Operation` `done` без ошибки; последующий `VolumeService.Get(vol-data01)` → `NOT_FOUND`

---

## F6 — `autoDelete`-семантика: запись на attach, экспозиция; cascade-исполнение compute-driven

> `→ storage-spec §1.1/§3.4`
> **AS-IS**: `VolumeAttachment.auto_delete` (bool) есть; означает «удалить том при удалении
> инстанса». **Исполнение** каскада — на `Instance.Delete` (compute-driven, out-of-scope; нет
> cross-service cascade, ban #4). STOR-1 владеет **записью и экспозицией** флага storage-стороной.

### Сценарий STOR-1-13 (positive/edge): autoDelete записывается на attach и экспонируется; storage сам каскад НЕ исполняет

**ID:** STOR-1-13

**Given** `vol-eph` в `AVAILABLE`

**When** `InternalVolumeService.Attach(vol-eph, instanceId=ins-web01, autoDelete=true, …)`
**Then** `VolumeService.Get(vol-eph).attachments[0].autoDelete == true`
**And** `usedBy[0].owned == true` (F7: `owned` мапится из `auto_delete`)
**And** storage **не** удаляет том сам (нет storage→compute liveness-sweep — цикл); при исчезновении инстанса dangling `instanceId` терпится (реальная чистка — compute-driven `DetachDisk`/delete-сага, out-of-scope; sweeper-реклейм DETACHED past-TTL — STOR-3, unified §5.4 B12)

---

## F7 — `Volume.usedBy` → `kacho.cloud.common.v1.Referrer` `[PHASE-0-GATED B1]`

> `→ unified §4 seam-C, §8 B1`
> **AS-IS** (`volume.proto:88`): `repeated kacho.cloud.reference.Reference used_by` — **legacy**
> тип. Редизайн B1 вводит 3-way ref-набор в `kacho.cloud.common.v1` (`ResourceRef`/`Referrer`/
> `OciReferrer`); `usedBy` мигрирует на generic **`Referrer{type,id,name°}`** (graceful-dangling
> cross-owner handle). Output-only проекция `attachments` (тот же источник — таблица
> `volume_attachments`), на вход не принимается.

### Сценарий STOR-1-14 (positive) `[PHASE-0-GATED B1]`: usedBy = Referrer{compute.instance}; owned=autoDelete

**ID:** STOR-1-14 `[PHASE-0-GATED B1]`

**Given** `vol-data01` примонтирован к `ins-web01` (`instanceName="web01"`, `autoDelete=false`)

**When** `VolumeService.Get(vol-data01)`
**Then** `usedBy` = 1 `Referrer` с `type=="compute.instance"`, `id=="ins-web01"`, `name°=="web01"` (write-time snapshot), `owned==false` (из `auto_delete`)
**And** `[PHASE-0-GATED]`: тип `Referrer` приходит из `kacho.cloud.common.v1` (B1). **AS-IS до Phase-0** — legacy `kacho.cloud.reference.Reference` (`referrer={type,id,name}`, `type=USED_BY`, `owned`). Форма поля меняется только после merge B1-change-set; merge-gate — §DoD. `device_name`/`mode`/`is_boot` живут **только** на `attachments[]` (rich domain), НЕ на `usedBy`

### Сценарий STOR-1-15 (negative): usedBy/attachments на входе Create/Update отвергаются

**ID:** STOR-1-15

**When** `VolumeService.Create` / `Update` с непустым `usedBy` (или `attachments`) в теле
**Then** `INVALID_ARGUMENT "used_by is immutable after Volume.Create"` (output-only проекция; attach-state меняется только через `InternalVolumeService.Attach/Detach`, F3)

---

## F8 — Two-projection: public `Volume` без infra; `InternalVolumeService.GetInternal` (:9091); internal НЕ на external

> `→ security §infra-sensitive` · `→ unified §5 инв-1` · `→ internal_volume_service.proto` (AS-IS)
> **AS-IS**: `VolumeInternal` (`GetInternal`) — skeleton, embeds public `Volume`, infra-поля
> (backend-LUN/NVMe-namespace/storage-node/pool-id/numeric-infra-id/capacity) объявлены `reserved
> 2 to 15` (data-plane increment, STOR-4). STOR-1 фиксирует **инвариант**: public `Volume`
> никогда не несёт infra; `GetInternal` — только :9091.

### Сценарий STOR-1-16 (positive): public Volume НЕ несёт infra; GetInternal доступен только на :9091

**ID:** STOR-1-16

**When** `VolumeService.Get` / `List` на публичном листенере (:9090)
**Then** сериализованное тело — public `Volume` (id/projectId/createdAt/updatedAt/name/description/labels/zoneId/diskTypeId/sizeBytes/blockSize/sourceSnapshotId/sourceImageId/status/attachments/usedBy); **NotContains** infra-токенов (`backendLun`/`nvmeNamespace`/`storageNode`/`poolId`/`numericInfraId`) — assert field-absence

**When** `InternalVolumeService.GetInternal(vol-data01)` на :9091 (mTLS)
**Then** `VolumeInternal` embeds public `Volume`; infra-поля `reserved` (не заполнены этим инкрементом — STOR-4)

### Сценарий STOR-1-17 (edge): InternalVolumeService НЕ маршрутизируется на external endpoint

**ID:** STOR-1-17

**When** попытка достучаться до `InternalVolumeService.Attach/Detach/GetInternal` через **external** api-gateway (`api.kacho.local:443`)
**Then** routing-miss (метод не зарегистрирован на external mux; ban #6) — internal-only surface; assert отсутствия на external — часть api-gateway-audit

---

## F9 — `[NET-NEW]` `Volume.source_image_id` — материализация boot-Volume из `Image` (mutual-exclusion с snapshot; regional-coherence)

> `→ unified §2 storage, §8 B13` · net-new (нет в AS-IS)
> **AS-IS** (`volume.proto:76`): «There is no source-image field (the OS comes from an OCI
> image, not the volume)». Редизайн-2026 (§2 storage, B13) **вводит storage-side `Image`** как
> VM boot-образ ⇒ boot-`Volume` материализуется **из Image** (не только из snapshot). Нужно
> **новое поле** `source_image_id` (immutable, same-DB FK → `images` **ON DELETE SET NULL** —
> parity с существующим `source_snapshot_id ON DELETE SET NULL`; boot-Volume независим от Image
> после засева — provenance, не live-dependency) + **новая миграция** (колонка + FK + partial-index).
> Взаимоисключение с `source_snapshot_id` (том засевается из **одного** источника).

### Сценарий STOR-1-18 (positive) `[NET-NEW]`: Create с sourceImageId → boot-Volume засеян из Image

**ID:** STOR-1-18 `[NET-NEW]`

**Given** `Image img-ubuntu24` в `READY`, регион `ru-central1` (см. F10/F12); зона `ru-central1-a` ∈ `ru-central1`

**When** `VolumeService.Create` c `projectId="prj-acme"`, `zoneId="ru-central1-a"`, `diskTypeId="block-balanced"`, `sizeBytes=21474836480`, `sourceImageId="img-ubuntu24"`
**Then** `Operation` `done`; `VolumeService.Get` показывает `sourceImageId=="img-ubuntu24"`, `status==AVAILABLE`, `sizeBytes>=` минимального размера образа (см. F12 `minDiskBytes°`)
**And** `sourceImageId` immutable (F1/F9: mask с ним → `INVALID_ARGUMENT "sourceImageId is immutable after Volume.Create"`)
**And** same-DB FK `volumes.source_image_id → images(id) ON DELETE SET NULL` (provenance, lineage-clear на удаление Image — см. STOR-1-28)

### Сценарий STOR-1-19 (negative+edge): source_image XOR source_snapshot; unknown image; regional-coherence zone∉image.region

**ID:** STOR-1-19

**When** `Create` c **обоими** `sourceImageId` и `sourceSnapshotId` непустыми
**Then** синхронный `INVALID_ARGUMENT` — mutual-exclusion, «a volume is seeded from either a snapshot or an image, not both» (spoken-exclusion, unified §5 инв-5)

**When** `Create` c `sourceImageId="img-missing"` (в БД storage нет)
**Then** `Operation.error` — same-DB FK `23503` → `FAILED_PRECONDITION "Image img-missing not found"` (тон контракта)

**When** `Create` c `sourceImageId="img-ubuntu24"` (регион `ru-central1`), но `zoneId` из **другого** региона (`ru-central2-a`)
**Then** `Operation.error` — placement-coherence regional: `FAILED_PRECONDITION` «Volume zone and Image must be in the same region» (zonal↔regional: `zone.region_id == image.region_id`; `zone.region_id` — peer geo `ZoneService.Get`, `image.region_id` — local; unified §5 инв-2)

### Сценарий STOR-1-28 (positive/edge) `[NET-NEW]`: Image.Delete → source_image_id SET NULL (provenance-clear, boot-Volume не затронут)

**ID:** STOR-1-28

**Given** `Image img-ubuntu24` в `READY` засеял `Volume vol-boot` (`vol-boot.sourceImageId == "img-ubuntu24"`, `vol-boot` в `AVAILABLE`)

**When** `ImageService.Delete(img-ubuntu24)` (`DELETE /storage/v1/images/img-ubuntu24`)
**Then** `Operation` `done` **без ошибки** — Image удаляется, даже если засел в томе (FK `ON DELETE SET NULL`, **не** RESTRICT: boot-Volume — provenance, не live-dependency)
**And** `VolumeService.Get(vol-boot).sourceImageId == ""` (lineage-clear); `vol-boot` **не затронут** (`status==AVAILABLE`, `sizeBytes` неизменен — блочные данные уже засеяны, независимы от Image)
**And** `ImageService.Get(img-ubuntu24)` → `NOT_FOUND` (hard-delete)

> Контраст с F5 (Volume-attach — **live** FK RESTRICT: примонтированный том нельзя удалить):
> Image→Volume — **provenance** (SET NULL), attachment→Volume — **live-dependency** (RESTRICT).
> Осознанно разные политики (`data-integrity` §within-service).

---

## F10 — `[NET-NEW]` `Image` (`img-`) flat-ресурс: мутации→Operation, UNIQUE(project,name), lifecycle, новая миграция `[PHASE-0-GATED B3 prefix]`

> `→ unified §2 storage (Image)` · net-new (нет proto/таблицы/кода)
> **AS-IS**: `Image` **отсутствует** — нет `image.proto`, нет `image_service.proto`, нет таблицы
> `images`, нет domain/service/repo. Полностью net-new: новый flat proto + regen + **новая
> goose-миграция** (`images` + `Volume.source_image_id` из F9). Форма — spine-каноничная (flat,
> enum `Status`, мутации→`Operation`, sync Get/List). **placement REGIONAL** (OQ1 confirmed):
> anycast, `regionId`, `placementType° == REGIONAL` const — симметрично registry-образам
> (region-scoped, unified §1 conv-10), coherent с ZONAL boot-Volume через `zone.region ∈ image.region`
> (F9 STOR-1-19). Regional-coherence enforcement через corelib `geoconsumer` — Phase-0-gated (как F4).
> **Prefix-registry координация (OQ4, `[PHASE-0-GATED B3 + B13 + compute-redesign #13]`):** `img-`
> **claim'ится за storage** (`storage.image`); легаси compute `PrefixImage="fd8"` (compute Image/Snapshot)
> **ретайрится** — `ImageCatalog` compute становится **проекцией** над `storage.image` (grammar
> `img-<base32>:<tag>`; module-compute ImageCatalog). Направление locked дизайном; программная
> координация — B3 (prefix-registry `img-` не коллизит с легаси `fd8`) + B13 (imageKind storage.image
> ≠ registry.image) + ретайр compute `fd8`-Image в проекцию (compute-redesign step 9). Merge-gate — §DoD.

### Сценарий STOR-1-20 (positive) `[NET-NEW]` `[PHASE-0-GATED B3 prefix]`: Image.Create → Operation, imageId в metadata сразу, Get отдаёт READY

**ID:** STOR-1-20 `[NET-NEW; id-prefix форма PHASE-0-GATED B3]`

**Given** проект `prj-acme`; регион `ru-central1` открыт
**And** вызывающий имеет `editor` на `prj-acme`

**When** `ImageService.Create` (`POST /storage/v1/images`) с payload:
  - `projectId` = `"prj-acme"`
  - `name` = `"ubuntu-24-04"`
  - `regionId` = `"ru-central1"`
  - `sourceSnapshotId` = `"snp-golden"` (см. F12 source-модель)

**Then** ответ — `Operation`; `metadata` (`CreateImageMetadata`) несёт непустой `imageId` (префикс `img-`, `[PHASE-0-GATED B3]`) **до** `done`
**And** после poll до `done && !error`, `ImageService.Get` возвращает `Image` со `status==READY` (control-plane, provisioning нет), `createdAt°` усечён, `sizeBytes°` / `minDiskBytes°` (F12), `regionId=="ru-central1"`, `placementType° == "REGIONAL"`
**And** `[PHASE-0-GATED B3]`: форма префикса `img-` зависит от B3. Merge-gate — §DoD

### Сценарий STOR-1-21 (negative): duplicate name → ALREADY_EXISTS; malformed image id → INVALID_ARGUMENT первым стейтментом

**ID:** STOR-1-21 `[id-prefix форма PHASE-0-GATED B3]`

**Given** `Image` с `name="ubuntu-24-04"` в `prj-acme` уже есть

**When** второй `ImageService.Create` c `name="ubuntu-24-04"` в `prj-acme`
**Then** `Operation.error` — `ALREADY_EXISTS` (partial `UNIQUE(project_id,name) WHERE name<>''`); то же имя в `prj-beta` → OK

**When** `ImageService.Get` с `imageId="bad!!id"`
**Then** синхронный `INVALID_ARGUMENT "invalid image id 'bad!!id'"` первым стейтментом; well-formed-но-нет → `NOT_FOUND "Image <id> not found"`

### Сценарий STOR-1-22 (edge): Image.Update — mutable name/description/labels; immutable source/region/format

**ID:** STOR-1-22

**Given** `Image img-ubuntu24` в `READY`

**When** `ImageService.Update` c `updateMask=["labels","description"]`
**Then** `Operation` `done`; изменения применены

**When** `ImageService.Update` c `updateMask=["regionId"]` (immutable)
**Then** синхронный `INVALID_ARGUMENT "regionId is immutable after Image.Create"` (до UpdateMask); то же для `sourceSnapshotId`/`sourceVolumeId`/`format` (F12)

---

## F11 — `[NET-NEW]` `Image` как `storage.image` Referrer-цель — ортогонален registry `registry.image` (B13) `[PHASE-0-GATED B1/B13]`

> `→ unified §2 compute ImageCatalog, §8 B13`
> **AS-IS**: дискриминатора нет. Редизайн B13: bootSource compute несёт `imageKind∈{STORAGE_IMAGE,
> OCI_IMAGE}` (или `Referrer.type` `storage.image`/`registry.image`) ⇒ bare `imageId` **никогда**
> не двусмыслен между двумя owner'ами (storage VM-boot vs registry OCI). STOR-1 владеет
> **storage-концом**: `Image` адресуется как `Referrer{type:"storage.image", id:"img-…"}`;
> `imageKind`-поле на bootSource — cross-module (compute), gated.

### Сценарий STOR-1-23 (positive/edge) `[PHASE-0-GATED B1/B13]`: Image адресуем как storage.image Referrer; ⟂ registry.image

**ID:** STOR-1-23 `[PHASE-0-GATED B1/B13]`

**Given** `Image img-ubuntu24` (storage, `prj-acme`) существует
**And** отдельно существует registry OCI-Image с тем же коротким токеном (другой owner)

**When** consumer (compute ImageCatalog) резолвит boot-source через `Referrer{type:"storage.image", id:"img-ubuntu24"}`
**Then** роутинг ведёт в **storage** (`storage.image` token) — **не** в registry; `img-ubuntu24` и registry-образ **не** коллизят (разные `Referrer.type`)
**And** `[PHASE-0-GATED B1]`: `Referrer` — из `kacho.cloud.common.v1` (3-way ref-набор). `[PHASE-0-GATED B13]`: согласование `imageKind` (`STORAGE_IMAGE` vs `OCI_IMAGE`) — cross-module (compute bootSource / ImageCatalog), приземляется governance change-set'ом. storage-обязательство: `Image` **всегда** выражается токеном `storage.image`. Merge-gate — §DoD

---

## F12 — `[NET-NEW]` `Image` source-oneof `{sourceSnapshotId|sourceVolumeId}` exactly-one + two-projection (blob-layout — Internal)

> `→ unified §2 registry (bucket/blob Internal), §5 инв-1`
> **AS-IS**: нет. **Confirmed defaults** (OQ2/OQ3): (a) **source oneof exactly-one** — `Image`
> создаётся из `sourceSnapshotId` (snapshot тома) **ЛИБО** `sourceVolumeId` (прямой том), ровно один;
> **blank-upload DEFER** (под будущий data-plane blob-pipeline — вне STOR-1); (b) public-поля —
> `sizeBytes°` (virtual disk size, байты), `minDiskBytes°` (мин. размер тома-получателя, байты),
> `format°` — **native Kachō enum** (ban #2: НЕ `qcow2`/`vmdk`-литерал; single-tier default в STOR-1);
> (c) **two-projection**: blob-layout / bucket / engineNamespace / storage-node — **только**
> `InternalImageService.GetInternal` (:9091), никогда на public `Image` (зеркалит registry
> engineNamespace/bucket/blob-layout, unified §2).
> **Output-echo координация `minDiskBytes°`↔compute (non-gating, important):** storage экспонирует
> `minDiskBytes°` в **байтах**; compute деривит GiB и энфорсит `bootVolumeSizeGiB ≥ image.minSizeGiB`
> (module-compute §596). storage — источник истины размера; compute — потребитель-деривер. Единица
> (байты storage → GiB compute) фиксируется как output-echo контракт.

### Сценарий STOR-1-24 (positive/edge): Image.Create source-oneof (snapshot XOR volume, exactly-one); minDiskBytes° derived

**ID:** STOR-1-24

**Given** `Snapshot snp-golden` в `READY` (STOR-2 ресурс — существующий AS-IS `snapshots`)

**When** `ImageService.Create` c `sourceSnapshotId="snp-golden"`
**Then** `Image` `READY`; `sizeBytes°` / `minDiskBytes°` (байты) выведены из размера источника; `format°` — native Kachō enum (single-tier default)
**And** `Create` c `sourceVolumeId="vol-golden"` (том напрямую) → `READY` аналогично
**And** взаимоисключение (**exactly-one**): оба `sourceSnapshotId`+`sourceVolumeId` → `INVALID_ARGUMENT` (spoken-exclusion); **ни одного** (blank) → `INVALID_ARGUMENT` «Image source is required» (blank-upload DEFER до data-plane, OQ2)
**And** неизвестный `sourceSnapshotId`/`sourceVolumeId` → same-DB FK `23503` → `FAILED_PRECONDITION "<Resource> <id> not found"` (тон контракта)

### Сценарий STOR-1-25 (positive): public Image НЕ несёт blob-layout; InternalImageService.GetInternal несёт

**ID:** STOR-1-25

**When** `ImageService.Get` / `List` на публичном :9090
**Then** public `Image` — только tenant-facing (id/projectId/createdAt/name/description/labels/regionId/status/sizeBytes°/minDiskBytes°/format°); **NotContains** `blobLayout`/`bucket`/`engineNamespace`/`storageNode` (assert field-absence — two-projection security-инвариант, **не** gated)

**When** `InternalImageService.GetInternal(img-ubuntu24)` на :9091 (mTLS)
**Then** `ImageInternal` embeds public `Image` + infra-проекция (blob-layout/bucket/engineNamespace) — internal-only; НЕ на external mux (ban #6)

---

## F13 — Единый тон ошибок by-lane (INTERNAL-opaque / immutable / malformed-first) + Image owner-tuple anti-BOLA

> `→ unified §1 conv-11, §5 инв-5` · `→ edges/storage-to-iam-fgaproxy`
> **AS-IS**: storage уже маппит SQLSTATE→gRPC, INTERNAL-дефолт `"internal error"`. fgaproxy
> owner-tuple для `storage_volume`/`storage_snapshot` — **CS-1 GAP-D done** (outbox `fga_register_outbox`
> + register-drainer + sync-registrar). STOR-1 добирает **Image**: `storage_image:<id>` owner-tuple
> (тот же outbox), чтобы gateway scope_extractor `{storage_image, image_id}` резолвил target→project
> (anti-BOLA). Полный hardening/compensation — STOR-3.

### Сценарий STOR-1-26 (edge): INTERNAL никогда не эхает pgx/SQL

**ID:** STOR-1-26

**Given** нижележащая не-замапленная DB-ошибка на любом storage-RPC (Volume или Image)

**When** RPC возвращает `INTERNAL`
**Then** `status.Convert(err).Message() == "internal error"` (или `NotContains(msg, <pgx/host/port/db-текст>)`) — regression-lock на **сообщение**, не только код `codes.Internal` (обе листенера — internal :9091 не освобождён)

### Сценарий STOR-1-27 `[PHASE-0-GATED / cross-ref STOR-3]`: Image owner-tuple эмитится → scope_extractor резолвит target→project (anti-BOLA)

**ID:** STOR-1-27 `[owner-tuple materialization EC; cross-ref STOR-3]`

**Given** `editor` на `prj-acme` создаёт `Image img-ubuntu24`

**When** тот же subject сразу вызывает `ImageService.Get(img-ubuntu24)` / `Update`
**Then** после **bounded client-retry** на кратком `403`/`404`-окне (owner-tuple `project:prj-acme #project @storage_image:img-ubuntu24` материализуется eventually-consistent через `fga_register_outbox` + drainer; unified §5 инв-4) — доступ разрешён; scope_extractor `{storage_image, image_id}` резолвит target→project
**And** subject **без** прав на `img-ubuntu24` → DENY (object-scoped Check против целевого объекта, не только метода — anti-BOLA; security §object-scoped)
**And** `[cross-ref STOR-3]`: полный owner-tuple hardening (forward-fast-path, revoke-sticking) + compute-compensation Delete — STOR-3. STOR-1 обеспечивает **emit** (reuse CS-1 GAP-D outbox, object_type `storage_image`) — иначе Image недоступен создателю

---

## F14 — `[NET-NEW]` `ImageService.List` — listauthz row-filter (anti-BOLA) + pagination-validate ДО authz-short-circuit + cursor/filter

> `→ api-conventions §pagination/Gotcha, §Gotcha'и (List validate)` · `→ security инв-7` · `→ unified §5 инв-3`
> **AS-IS**: `Image.List` **отсутствует** (net-new public surface). Форма зеркалит `VolumeService.List`
> (AS-IS: cursor `(created_at,id)`, `filter name=`, listauthz row-filter, `page_size≤1000`). **Документированный
> рецидивирующий класс** (api-conventions Gotcha + security инв-7, реальные инциденты compute disk/image/nlb):
> валидация `page_size`/`page_token` обязана идти **ДО** listauthz empty-grant short-circuit — иначе caller без
> грантов получает `200 {[]}` (или authz-403) на garbage-token/`page_size>1000` вместо `400`. vpc — эталон.

### Сценарий STOR-1-31 (positive/negative): listauthz row-filter — caller видит только свои Images (anti-BOLA)

**ID:** STOR-1-31

**Given** проект `prj-acme` содержит `img-a`, `img-b`; проект `prj-other` содержит `img-x`; caller — `viewer` только на `prj-acme`

**When** `ImageService.List(projectId="prj-acme")`
**Then** 200 с `img-a`, `img-b`; `img-x` **отсутствует** (listauthz row-filter — результат отфильтрован per-object; security-инвариант + CI-гейт `make -C services/storage audit-list-filter`)
**And** caller **без** грантов на `prj-acme` → пустая страница (empty-grant short-circuit) — но **после** pagination-validate (STOR-1-32)

### Сценарий STOR-1-32 (negative): pagination-validate ДО authz empty-grant short-circuit

**ID:** STOR-1-32

**Given** caller **без** грантов на проект (пустой grant → `AllowedIDs==0`)

**When** `ImageService.List` с `pageSize = 1001` (> max 1000)
**Then** `INVALID_ARGUMENT` (`corevalidate.PageSize` — **отвергается, не clamp'ится**) — **ДО** empty-grant short-circuit (иначе утекло бы в `200 {[]}` — расхождение с конвенцией)

**When** `ImageService.List` с garbage `pageToken = "!!!not-base64!!!"`
**Then** `INVALID_ARGUMENT` (`DecodePageToken` garbage→InvalidArgument) — тоже ДО authz-short-circuit. Порядок: **format-validate → authz-resolve → empty-grant short-circuit → repo**. Regression: unit на `ValidatePagination`

### Сценарий STOR-1-33 (positive/edge): cursor-страница + `filter name=` + пустой список

**ID:** STOR-1-33

**Given** `prj-acme` содержит 3 Image; caller — `viewer` на `prj-acme`

**When** `ImageService.List(projectId="prj-acme", pageSize=2)`
**Then** 2 Image (cursor `(created_at,id)` ASC) + непустой `nextPageToken`; следующая страница отдаёт 3-й + пустой `nextPageToken`

**When** `ImageService.List(projectId="prj-acme", filter="name=img-none")` (нет совпадений)
**Then** 200 с пустым `images[]` (не ошибка); `filter` whitelist — только `name=` (текущая фаза)

---

## Definition of Done

STOR-1 готова к merge только при выполнении ВСЕГО чек-листа (`ai-tooling.md` §lifecycle gate 4-7; `testing.md`):

**Traceability + тесты (1-to-1):**
- [ ] Каждый `STOR-1-NN` имеет зелёный **integration-тест** (testcontainers Postgres 16) — `Test<Resource>_STOR_1_NN` — покрывающий SQL-сторону: CAS/FK-RESTRICT/UNIQUE/EXCLUDE.
- [ ] **Concurrent-race обязателен** (data-integrity §5): `STOR-1-07` (двойной attach) — integration `-race`, детерминированный (blocker держит CAS-слот, backlog копится, ровно один writer выигрывает), **не** `time.Sleep`. Аналогично любой спорный CAS-путь Image, если добавлен.
- [ ] Каждый **public-наблюдаемый** `STOR-1-NN` (Volume/Image CRUD, `ImageService.List` F14, delete-safety через public `Delete`, Image.Delete SET NULL `STOR-1-28`, field-absence, BVA) имеет зелёный **newman-кейс** `tests/newman/cases/*.py` c аннотацией `# verifies STOR-1-NN` — ≥1 happy + ≥1 negative на фичу.
- [ ] **List-регрессия обязательна** (api-conventions Gotcha + security инв-7): unit на `ValidatePagination` для `ImageService.List` (garbage-token / `pageSize>1000` → `InvalidArgument`) — **до** listauthz empty-grant short-circuit (`STOR-1-32`); listauthz row-filter покрыт (`STOR-1-31`) — `make -C services/storage audit-list-filter` включает `storage.images.list`.
- [ ] **Internal-only** сценарии (attach-CAS F3, GetInternal F8, InternalImageService F12) покрываются **integration + bufconn** (не newman-public); **отсутствие `InternalVolumeService`/`InternalImageService` на external mux** — сам по себе assert (`STOR-1-17`, api-gateway-audit).
- [ ] TDD-порядок: RED (падает по нужной причине) ДО кода, пара RED→GREEN в PR. Трассировка `STOR-1-NN ↔ Test<R>_STOR_1_NN ↔ cases/*.py`.

**e2e-smoke (real gateway, заказчик проверяет):**
- [ ] `VolumeService.Create` → poll `Operation` `done` → `Get` `AVAILABLE` через реальный api-gateway (`make -C deploy e2e-test` / `grpcurl`).
- [ ] `ImageService.Create` (net-new) → `Get` `READY`; `VolumeService.Create{sourceImageId}` → boot-Volume `AVAILABLE` (F9/`STOR-1-18`); `ImageService.Delete` засевшего Image → `vol-boot.sourceImageId==""`, том цел (`STOR-1-28`).
- [ ] two-projection field-absence на **реальном** gateway-ответе: public `Volume`/`Image` НЕ содержат infra/blob-layout (`STOR-1-16/25`).

**Deliverables редизайна (implementer обязан выполнить — иначе AS-IS остаётся):**
- [ ] **Volume-дельты:** `used_by` тип `reference.Reference` → `common.v1.Referrer` (F7, breaking proto — `[B1]`); id-prefix `vol` → `vol-` (F2, `[B3]`); **новое поле** `source_image_id` (immutable, F9).
- [ ] **Image net-new:** новый `image.proto` + `image_service.proto` + `internal_image_service.proto` (`buf lint`/`breaking`/`validate` зелёные, proto-api-reviewer); regen `gen/`.
- [ ] **Новая goose-миграция** (не редактировать применённые `0001`–`0006`, ban #5): таблица `images` (`UNIQUE(project_id,name) WHERE name<>''`, state CHECK, `region_id`, source-oneof cols `source_snapshot_id`/`source_volume_id` с FK → snapshots/volumes, `format` native-enum CHECK, `size_bytes`/`min_disk_bytes`); колонка `volumes.source_image_id` + FK → `images` **ON DELETE SET NULL** (parity `source_snapshot_id`; provenance, НЕ RESTRICT) + partial-index; DB-review (db-architect-reviewer).
- [ ] **fgaproxy Image:** `storage_image:<id>` owner-tuple через существующий `fga_register_outbox` (F13/F27); permission-catalog запись `{storage_image, image_id}` scope_extractor; `make -C gateway permission-catalog` regen → обе embedded-копии byte-identical (`make -C gateway permission-catalog-check`).
- [ ] Public RPC (`ImageService` Get/List/Create/Update/Delete) зарегистрированы в api-gateway (`api-gateway-registrar`); `InternalImageService` — **только** internal mux (ban #6).

**Проектные гейты (финальная верификация):**
- [ ] `go test ./... -race` · `golangci-lint run` · `govulncheck` · `make -C services/storage audit-list-filter` зелёные.
- [ ] `make -C gateway permission-catalog-check` byte-identical; newman зелёные (все public `STOR-1-NN`).
- [ ] Vault-trail: обновить `resources/storage-volume.md` (source_image_id, Referrer), создать `resources/storage-image.md`, `rpc/storage-image-service.md`; `edges/storage-to-iam-fgaproxy.md` (+ storage_image); `KAC/STOR-1.md`.

**MERGE-GATE (`[PHASE-0-GATED]` — жёсткий кросс-фазовый блокер):**
- [ ] **STOR-1 НЕ мёржится, пока Phase-0 governance change-set не приземлит** (unified §9 MUST-close):
  (a) **B1** — `kacho.cloud.common.v1` 3-way ref-типы (`Referrer` для `Volume.usedBy` F7, `Image` как `storage.image`-цель F11);
  (b) **B3** — id-prefix hyphen (`vol-`/`img-`/`snp-`) в `corevalidate` (F2/F10);
  (c) **B13** — `imageKind` дискриминатor (`storage.image` vs `registry.image`) согласован cross-module с compute/registry (F11); **+ ретайр compute `fd8`-Image** в проекцию `ImageCatalog` над `storage.image` (compute-redesign step 9, OQ4);
  (d) **by-lane reason-token** таблица (F11/F4 code-lane).
  До merge change-set: `usedBy` остаётся legacy `reference.Reference`; префиксы non-hyphen (`vol`/`snp`); F11-роутинг — без формального `imageKind`. **Ungated** части (attach-CAS F3, delete-safety F5, derived-status F1, INTERNAL-opaque `STOR-1-26`, immutable-текст, `NotContains` infra F8/`STOR-1-16`/`STOR-1-25`, Image CRUD/UNIQUE/BVA F10/`STOR-1-30`, **Image.Delete SET NULL** `STOR-1-28`, **`ImageService.List` listauthz+pagination-validate** F14, project/zone peer-validate fail-closed) строятся без ожидания.
- [ ] **B10 gate:** STOR-1 — предпосылка **compute GA** (boot-Volume/ImageCatalog). Compute Phase-2 не стартует до APPROVED+merge STOR-1.

---

## Changelog — что этот док покрывает

- **F1** Volume flat-lifecycle: Operation (`volumeId` в metadata сразу), `state=READY` немедленно, derived `status`, immutable-набор, size increase-only, `UNIQUE(project,name)` (+ concurrent name-race); **BVA** name/description/labels для Volume+Image (STOR-1-01..04, STOR-1-30).
- **F2** `vol-` prefix + malformed-first `[PHASE-0-GATED B3]` (STOR-1-05).
- **F3** attach-CAS `InternalVolumeService.Attach` idempotent free-or-mine + **concurrent-race** + Detach идемпотентен + не-READY/device-collision/one-boot (STOR-1-06..09).
- **F4** placement-coherence Volume↔Instance та же зона+проект (self-describing, ацикличность) + zone-existence peer-validate `[geoconsumer PHASE-0-GATED]` + **project-existence peer-validate** (iam-down UNAVAILABLE, authz-first толерантность) (STOR-1-10..11, STOR-1-29).
- **F5** delete-safety FK RESTRICT `"Volume <id> is in use"` (STOR-1-12).
- **F6** autoDelete запись+экспозиция; cascade compute-driven (STOR-1-13).
- **F7** `usedBy` → `common.v1.Referrer` `[PHASE-0-GATED B1]`; output-only (STOR-1-14..15).
- **F8** two-projection Volume; internal НЕ на external (STOR-1-16..17).
- **F9** `[NET-NEW]` `source_image_id` boot-Volume материализация из Image; mutual-exclusion; regional-coherence; **Image.Delete → SET NULL** provenance-clear (том цел) (STOR-1-18..19, STOR-1-28).
- **F10** `[NET-NEW]` `Image` (`img-`) flat + Operation + UNIQUE(project,name) + новая миграция; **REGIONAL const (OQ1)**; `img-` prefix-registry + ретайр compute `fd8` (OQ4) `[PHASE-0-GATED B3/B13]` (STOR-1-20..22).
- **F11** `[NET-NEW]` `Image` = `storage.image` Referrer ⟂ registry `registry.image` (B13) `[PHASE-0-GATED B1/B13]` (STOR-1-23).
- **F12** `[NET-NEW]` Image source-oneof `{snapshot|volume}` exactly-one (blank DEFER); `format°` native Kachō enum; two-projection blob-layout Internal; `minDiskBytes°`↔compute output-echo (STOR-1-24..25).
- **F13** by-lane тон (INTERNAL-opaque) + Image owner-tuple anti-BOLA emit в STOR-1 (hardening→STOR-3) (STOR-1-26..27).
- **F14** `[NET-NEW]` `ImageService.List` — listauthz row-filter (anti-BOLA) + **pagination-validate ДО authz-short-circuit** (garbage-token/`pageSize>1000`→INVALID_ARGUMENT) + cursor + `filter name=` + пустой список (STOR-1-31..33).
