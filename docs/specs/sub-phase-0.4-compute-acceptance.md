# Sub-phase 0.4 (Compute — Instance / Disk / Image / Snapshot + Reconciler) — Acceptance

**Документ:** acceptance / sub-phase 0.4
**Дата:** 2026-05-03
**Статус:** Draft, на ревью
**Источник требований:** `04-roadmap-and-phasing.md` §3 «Sub-итерация 0.4»; `01-architecture-and-services.md` §2.4, §5; `02-data-model-and-conventions.md` §3, §4, §9–11, §14; `00-overview-and-scope.md`.
**Утверждение:** approve выставляет агент `acceptance-reviewer` (заказчик не подключается — он проверяет финальный smoke на шаге 7, см. `04-roadmap-and-phasing.md` §2).

---

## 0. Цель sub-итерации (1 абзац)

Sub-итерация 0.4 реализует сервис `kacho-compute` — control plane виртуальных машин и блочных дисков — с асинхронным reconciler-ом, симулирующим жизненный цикл ресурсов. Сервис охватывает четыре ресурса: `Instance` (полный lifecycle с симулированными задержками 5–30 с), `Disk` (lifecycle CREATING → READY с симулированным disk-attach), `Image` (read-only каталог, всегда READY), `Snapshot` (прогресс 0–100% за 10–30 с). Reconciler координирует обработку между репликами через `pg_advisory_lock(uid_hash)`. Сервис выполняет cross-service gRPC-вызовы: compute → resource-manager (`FolderExists`) и compute → vpc (`SubnetExists`). Finalizer `compute.kacho.io/disk-detach` обеспечивает безопасное удаление Instance с прикреплёнными дисками. API Gateway (sub-phase 0.6) **не существует** в данной итерации: все e2e-сценарии используют `kubectl port-forward`.

**Что НЕ входит в 0.4** (явно отложено):
- `kacho-api-gateway` и REST-mux — sub-phase 0.6.
- LoadBalancer и finalizer `loadbalancer.kacho.io/target-deregister` — sub-phase 0.5.
- Finalizer `vpc.kacho.io/dependent-check` — ответственность kacho-vpc (sub-phase 0.3).
- SecurityGroup attachment к Instance (cross-service vpc) — частично в 0.4 (поле spec.networkInterfaces[].securityGroupIds валидируется только синтаксически, не через vpc-internal).
- Address lifecycle `IN_USE` — изменяется через compute, но публичные IP не выделяются автоматически (нет реального data plane).
- AAA (auth, authorization, audit) — отдельная фаза.
- Пагинация глубже 1000 — зарезервирована архитектурно.
- `Start` и `Stop` как отдельные RPC — реализуются через `spec.desiredPowerState` (upsert). CLI добавит aliases позже.

**Зафиксированные соглашения:**
- `ALREADY_EXISTS` не используется: upsert-семантика (name + folderId → create-or-update).
- `status` пишется **только** через `Internal.UpdateStatus` — запрет #6. Попытка передать `status` в `/upsert` возвращает `INVALID_ARGUMENT`.
- Симулированные задержки (см. §11 «Открытые вопросы»): PROVISIONING → RUNNING: 5–30 с; STOPPING → STOPPED: 5–15 с; STOPPED → STARTING → RUNNING: 5–15 с; RESTARTING (stop + start): ~10 с; CREATING (Disk): 3–10 с; SNAPSHOT прогресс: 10–30 с.
- **Имена integration-тест-функций** следуют паттерну `Test<Resource>_<ScenarioID>_<ShortDesc>` (например, `TestInstance_F1_ProvisioningToRunning`). E2e bash-скрипты — `kacho-deploy/e2e/0.4/<ID>-<short-desc>.sh`.
- Все временны́е assertion-ы в тестах используют таймаут 60 секунд (2× максимальной симулированной задержки), чтобы тесты были детерминированы.

---

## 1. Группа A — kacho-proto/compute/v1 contracts

Сценарии группы A проверяют корректность proto-контрактов `kacho-proto/proto/kacho/cloud/compute/v1/`. Тесты — `buf lint` и `buf breaking` в CI kacho-proto.

### A1. buf lint проходит без предупреждений

**ID:** 0.4-A1

**Given** файлы `kacho-proto/proto/kacho/cloud/compute/v1/` содержат:
- `instance.proto`
- `disk.proto`
- `image.proto`
- `snapshot.proto`
- `internal.proto`

**When** выполняется `buf lint proto/kacho/cloud/compute/v1/` в репо `kacho-proto`

**Then** команда завершается с кодом 0
**And** нет предупреждений о нарушении naming, field numbering, field type conventions
**And** package declaration во всех файлах — `package kacho.cloud.compute.v1;`
**And** go_package option — `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/compute/v1`

### A2. buf breaking не регрессирует после изменений

**ID:** 0.4-A2

**Given** в ветке `main` kacho-proto уже есть baseline с baseline-версией proto
**And** разработчик добавляет новое optional-поле в `Instance.Spec`

**When** выполняется `buf breaking --against 'https://github.com/PRO-Robotech/kacho-proto.git#branch=main'`

**Then** команда завершается с кодом 0 (добавление поля — обратно совместимо)
**And** если поле удалено или его тип изменён — команда завершается с ненулевым кодом

### A3. proto Instance содержит обязательные RPC и message-типы

**ID:** 0.4-A3

**Given** файл `instance.proto` скомпилирован

**When** разработчик проверяет сгенерированный Go-код в `gen/go/kacho/cloud/compute/v1/`

**Then** присутствуют типы:
- `InstanceService` с методами `Upsert`, `Delete`, `List`, `Watch`, `Restart`
- `Instance` message с полями `metadata`, `spec`, `status`
- `InstanceUpsertRequest` / `InstanceUpsertResponse`
- `InstanceDeleteRequest` / `InstanceDeleteResponse`
- `InstanceListRequest` / `InstanceListResponse`
- `InstanceWatchRequest`, `InstanceWatchEvent` (server-streaming)
- `InstanceRestartRequest` / `InstanceRestartResponse`
- `Instance.Spec` с полями: `display_name`, `description`, `platform_id`, `zone_id`, `resources` (ResourceSpec), `boot_disk` (AttachedDisk), `secondary_disks[]` (AttachedDisk), `network_interfaces[]` (NetworkInterface), `scheduling_policy`, `metadata` (user-data map), `fqdn`, `desired_power_state` (enum: `RUNNING`, `STOPPED`)
- `Instance.Status` с полями: `state` (enum), `state_last_transition_at`, `ips` (IPs), `fqdn`, `host_id`, `last_restart_completed_at`, `conditions[]`
- `Instance.Status.State` enum: `PROVISIONING`, `RUNNING`, `STOPPING`, `STOPPED`, `STARTING`, `RESTARTING`, `UPDATING`, `ERROR`, `DELETING`

### A4. proto Disk содержит обязательные поля spec и status

**ID:** 0.4-A4

**Given** файл `disk.proto` скомпилирован

**When** разработчик проверяет сгенерированный Go-код

**Then** `Disk.Spec` содержит поля:
- `disk_type_id string` — тип диска (например, `"network-ssd"`)
- `zone_id string` — зональность
- `size string` — размер в формате `"50Gi"`
- `image_id string` — опциональный (образ для инициализации)
- `display_name string`
- `description string`
**And** `Disk.Status` содержит поля:
- `state` (enum: `CREATING`, `READY`, `ATTACHING`, `DETACHING`, `ERROR`, `DELETING`)
- `state_last_transition_at`
- `attached_to_instance_id string` (nullable)
- `device_name string` (nullable)

### A5. proto Image и Snapshot содержат необходимые типы

**ID:** 0.4-A5

**Given** файлы `image.proto` и `snapshot.proto` скомпилированы

**When** разработчик проверяет сгенерированный Go-код

**Then** `ImageService` имеет методы `Get`, `List` (только read-only, без Upsert/Delete/Watch)
**And** `Image.Status.state` всегда `READY`
**And** `SnapshotService` имеет методы `Upsert`, `Delete`, `List`, `Watch`
**And** `Snapshot.Status` содержит поля `state` (enum: `CREATING`, `READY`, `ERROR`, `DELETING`) и `progress_percent int32` (0–100)
**And** `Snapshot.Spec` содержит поля `disk_id string` (ссылка на Disk.uid) и `display_name string`, `description string`

### A6. proto internal.proto содержит Internal-методы compute

**ID:** 0.4-A6

**Given** файл `internal.proto` скомпилирован

**When** разработчик проверяет сгенерированный Go-код

**Then** присутствует сервис `ComputeInternal` с методами:
- `InstanceExists(req: {uid string}) → {exists: bool}` — для cross-service из loadbalancer
- `UpdateInstanceStatus(req)` — reconciler пишет status Instance
- `UpdateDiskStatus(req)` — reconciler пишет status Disk
- `UpdateSnapshotStatus(req)` — reconciler пишет status Snapshot
- `UpdateInstanceMetadata(req)` — reconciler обновляет `metadata.finalizers[]` и `metadata.restartedAt`

---

## 2. Группа B — Disk domain (Upsert / Delete / List / Watch + lifecycle CREATING→READY)

### B1. Upsert: создание нового Disk

**ID:** 0.4-B1

**Given** Folder `default` с `uid = <folder-uid>` существует в resource-manager
**And** Сервис `DiskService` инициализирован

**When** клиент вызывает `kacho.cloud.compute.v1.DiskService/Upsert` с payload:
- `disks[0].metadata.name = "my-disk-01"`
- `disks[0].metadata.folderId = <folder-uid>`
- `disks[0].spec.diskTypeId = "network-ssd"`
- `disks[0].spec.zoneId = "kacho-zone-a"`
- `disks[0].spec.size = "50Gi"`

**Then** ответ содержит `disks[0]` с заполненными:
- `metadata.uid` — непустой UUID v4
- `metadata.name = "my-disk-01"`
- `metadata.folderId = <folder-uid>`
- `metadata.creationTimestamp` — не нулевое время
- `metadata.resourceVersion` — непустая строка с десятичным числом > 0
- `metadata.generation = 1`
**And** `status.state = "CREATING"` в первом ответе (reconciler ещё не запустил переход)
**And** в БД `kacho_compute.disks` присутствует запись с `name = 'my-disk-01'`
**And** в `resource_events` есть событие `event_type = 'ADDED'`, `resource_kind = 'Disk'`
**And** gRPC статус = OK

### B2. Disk lifecycle: CREATING → READY через reconciler

**ID:** 0.4-B2

**Given** Disk `"my-disk-01"` создан (B1), `status.state = "CREATING"`
**And** Reconciler запущен

**When** ожидается в течение 30 секунд

**Then** через Watch на `DiskService/Watch` приходит событие `MODIFIED` с `status.state = "READY"` для данного диска
**And** `status.state_last_transition_at` обновлено
**And** `metadata.resourceVersion` возрос

### B3. Disk Upsert: идемпотентность (no-diff → no event)

**ID:** 0.4-B3

**Given** Disk `"my-disk-01"` существует с `metadata.resourceVersion = <R>`

**When** клиент вызывает `DiskService/Upsert` с тем же payload (те же `name`, `spec`, `folderId`)

**Then** ответ содержит тот же `metadata.uid`
**And** `metadata.resourceVersion` не изменился (no-op, нет diff)
**And** в `resource_events` новых событий для данного uid не появилось

### B4. Disk List: фильтр по folderId

**ID:** 0.4-B4

**Given** Существуют 3 Disk: два с `folderId = <folder-a>`, один с `folderId = <folder-b>`

**When** клиент вызывает `DiskService/List` с:
- `selectors[0].field_selector.folder_id = <folder-a>`

**Then** ответ содержит ровно 2 Disk
**And** Disk из `<folder-b>` не включён

### B5. Disk Delete: переход в DELETING затем физическое удаление

**ID:** 0.4-B5

**Given** Disk `"my-disk-01"` в состоянии `READY` (не прикреплён к Instance)
**And** `metadata.finalizers[] = []`

**When** клиент вызывает `DiskService/Delete` с `disks[0].metadata.uid = <disk-uid>`

**Then** ответ — OK
**And** Disk физически удалён из БД (нет finalizers)
**And** в `resource_events` событие `event_type = 'DELETED'`
**And** повторный Delete с тем же uid возвращает `NOT_FOUND`

### B6. Disk Watch: получение ADDED / MODIFIED / DELETED событий

**ID:** 0.4-B6

**Given** Watch стрим открыт `DiskService/Watch` с `resourceVersion = <текущий>`

**When** (шаг 1) `DiskService/Upsert` создаёт Disk `"watch-disk"` → `status.state = CREATING`
**And** (шаг 2) Reconciler переводит Disk в `READY`
**And** (шаг 3) `DiskService/Delete` удаляет Disk `"watch-disk"`

**Then** Watch стрим получает события в правильном порядке:
1. `type = ADDED`, `disk.metadata.name = "watch-disk"`, `disk.status.state = "CREATING"`
2. `type = MODIFIED`, `disk.status.state = "READY"`
3. `type = DELETED`, `disk.metadata.name = "watch-disk"`

### B7. Upsert Disk с невалидным folderId — NOT_FOUND через resource-manager

**ID:** 0.4-B7

**Given** Folder с `uid = "00000000-0000-0000-0000-000000000001"` НЕ существует в resource-manager

**When** клиент вызывает `DiskService/Upsert` с:
- `disks[0].metadata.name = "orphan-disk"`
- `disks[0].metadata.folderId = "00000000-0000-0000-0000-000000000001"`
- `disks[0].spec.diskTypeId = "network-ssd"`, `spec.zoneId = "kacho-zone-a"`, `spec.size = "20Gi"`

**Then** gRPC статус = `NOT_FOUND`
**And** `details[]` содержит `ResourceInfo.resource_type = "Folder"`, `resource_name = "00000000-0000-0000-0000-000000000001"`
**And** Disk НЕ создан в БД

### B8. Upsert Disk с невалидным diskTypeId — INVALID_ARGUMENT

**ID:** 0.4-B8

**Given** Folder `<folder-uid>` существует

**When** клиент вызывает `DiskService/Upsert` с:
- `disks[0].spec.diskTypeId = "nonexistent-type"`

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "disks[0].spec.diskTypeId"`

### B9. Upsert Disk: попытка задать status — INVALID_ARGUMENT

**ID:** 0.4-B9

**Given** Folder `<folder-uid>` существует

**When** клиент вызывает `DiskService/Upsert` с payload, содержащим:
- `disks[0].status.state = "READY"` (попытка записать status через upsert)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "disks[0].status"`
**And** Disk НЕ создан в БД

---

## 3. Группа C — Image (read-only каталог)

### C1. Image List: возвращает seed-образы после миграции

**ID:** 0.4-C1

**Given** Применена миграция `0002_seed_catalogs.sql`, содержащая seed-образы
**And** Сервис `ImageService` инициализирован

**When** клиент вызывает `kacho.cloud.compute.v1.ImageService/List` с пустым `selectors[]`

**Then** ответ содержит как минимум 2 образа:
- объект с `metadata.name = "ubuntu-2204-lts"` и `status.state = "READY"`
- объект с `metadata.name = "debian-12"` и `status.state = "READY"`
**And** gRPC статус = OK

### C2. Image Get: получение образа по uid

**ID:** 0.4-C2

**Given** Образ `"ubuntu-2204-lts"` существует с `uid = <image-uid>`

**When** клиент вызывает `ImageService/Get` с `uid = <image-uid>`

**Then** ответ содержит `image.metadata.name = "ubuntu-2204-lts"` и `image.status.state = "READY"`
**And** gRPC статус = OK

### C3. Image Get: несуществующий образ — NOT_FOUND

**ID:** 0.4-C3

**Given** Образ с `uid = "00000000-0000-0000-0000-000000000099"` НЕ существует

**When** клиент вызывает `ImageService/Get` с `uid = "00000000-0000-0000-0000-000000000099"`

**Then** gRPC статус = `NOT_FOUND`
**And** `details[]` содержит `ResourceInfo.resource_type = "Image"`

### C4. Image не поддерживает Upsert / Delete — метод не существует

**ID:** 0.4-C4

**Given** Сервис `ImageService` запущен

**When** разработчик проверяет proto-контракт `ImageService`

**Then** методы `Upsert`, `Delete`, `Watch` **отсутствуют** в `ImageService`
**And** присутствуют только методы `Get` и `List`

### C5. Image List: фильтр по name возвращает один образ

**ID:** 0.4-C5

**Given** Существуют seed-образы `"ubuntu-2204-lts"` и `"debian-12"`

**When** клиент вызывает `ImageService/List` с:
- `selectors[0].field_selector.name = "debian-12"`

**Then** ответ содержит ровно 1 образ с `metadata.name = "debian-12"`
**And** `"ubuntu-2204-lts"` не включён в ответ

---

## 4. Группа D — Snapshot (lifecycle CREATING с progress → READY)

### D1. Upsert: создание Snapshot для существующего Disk

**ID:** 0.4-D1

**Given** Disk `"my-disk-01"` с `uid = <disk-uid>` в состоянии `READY` существует
**And** Folder `<folder-uid>` существует

**When** клиент вызывает `kacho.cloud.compute.v1.SnapshotService/Upsert` с payload:
- `snapshots[0].metadata.name = "snap-01"`
- `snapshots[0].metadata.folderId = <folder-uid>`
- `snapshots[0].spec.diskId = <disk-uid>`
- `snapshots[0].spec.displayName = "first snapshot"`

**Then** ответ содержит `snapshots[0]` с заполненными `metadata.uid`, `creationTimestamp`, `resourceVersion`
**And** `status.state = "CREATING"` в первом ответе
**And** `status.progress_percent = 0` в первом ответе
**And** в `resource_events` событие `event_type = 'ADDED'`, `resource_kind = 'Snapshot'`
**And** gRPC статус = OK

### D2. Snapshot lifecycle: CREATING с прогрессом → READY через reconciler

**ID:** 0.4-D2

**Given** Snapshot `"snap-01"` создан (D1), `status.state = "CREATING"`, `status.progress_percent = 0`
**And** Reconciler запущен

**When** Watch стрим `SnapshotService/Watch` открыт для данного snapshot
**And** ожидается в течение 60 секунд

**Then** Watch стрим получает несколько событий `MODIFIED` с нарастающим `status.progress_percent` (0 → промежуточное значение → 100)
**And** финальное событие `MODIFIED` содержит `status.state = "READY"` и `status.progress_percent = 100`
**And** переход CREATING → READY занимает от 10 до 30 секунд

### D3. Snapshot Watch: прогресс виден через Watch

**ID:** 0.4-D3

**Given** Watch стрим `SnapshotService/Watch` открыт с пустым selectors

**When** создаётся Snapshot `"live-snap"` для Disk `<disk-uid>`

**Then** Watch стрим получает `ADDED` событие с `status.state = "CREATING"`
**And** в течение 60 секунд Watch стрим получает хотя бы одно промежуточное `MODIFIED` с `0 < status.progress_percent < 100`
**And** итоговое `MODIFIED` содержит `status.state = "READY"` и `status.progress_percent = 100`

### D4. Snapshot с несуществующим diskId — INVALID_ARGUMENT

**ID:** 0.4-D4

**Given** Disk с `uid = "00000000-0000-0000-0000-000000000002"` НЕ существует в `kacho_compute`

**When** клиент вызывает `SnapshotService/Upsert` с:
- `snapshots[0].spec.diskId = "00000000-0000-0000-0000-000000000002"`

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "snapshots[0].spec.diskId"`
**And** Snapshot НЕ создан

### D5. Snapshot Delete: мягкое удаление, затем физическое

**ID:** 0.4-D5

**Given** Snapshot `"snap-01"` в состоянии `READY` существует с `uid = <snap-uid>`

**When** клиент вызывает `SnapshotService/Delete` с `snapshots[0].metadata.uid = <snap-uid>`

**Then** ответ — OK
**And** Snapshot физически удалён (нет finalizers у Snapshot)
**And** в `resource_events` событие `event_type = 'DELETED'`

### D6. Создание Snapshot из Disk в состоянии не READY — FAILED_PRECONDITION

**ID:** 0.4-D6

**Given** Disk `"creating-disk"` с `uid = <disk-uid>` в состоянии `CREATING` (ещё не READY)

**When** клиент вызывает `SnapshotService/Upsert` с `snapshots[0].spec.diskId = <disk-uid>`

**Then** gRPC статус = `FAILED_PRECONDITION`
**And** `details[]` содержит `PreconditionFailure` с `violations[0].type = "DISK_NOT_READY"` и `violations[0].subject = <disk-uid>`

---

## 5. Группа E — Instance domain: создание (cross-service Folder.Exists + Subnet.Exists)

### E1. Upsert: создание Instance с bootDisk и сетевым интерфейсом

**ID:** 0.4-E1

**Given** Folder `default` с `uid = <folder-uid>` существует в resource-manager
**And** Subnet `"default-subnet"` с `uid = <subnet-uid>` существует в vpc, `status.state = "ACTIVE"`, CIDR `10.0.0.0/24`
**And** Disk `"boot-disk"` с `uid = <boot-disk-uid>` в состоянии `READY` существует в `kacho_compute`
**And** Platform `"standard-v3"` существует в seed-таблице `platforms`
**And** Zone `"kacho-zone-a"` существует в seed-таблице `zones`

**When** клиент вызывает `kacho.cloud.compute.v1.InstanceService/Upsert` с payload:
- `instances[0].metadata.name = "test-vm-01"`
- `instances[0].metadata.folderId = <folder-uid>`
- `instances[0].spec.platformId = "standard-v3"`
- `instances[0].spec.zoneId = "kacho-zone-a"`
- `instances[0].spec.resources.cores = 2`
- `instances[0].spec.resources.memory = "4Gi"`
- `instances[0].spec.bootDisk.diskId = <boot-disk-uid>`
- `instances[0].spec.bootDisk.deviceName = "boot"`
- `instances[0].spec.bootDisk.autoDelete = true`
- `instances[0].spec.networkInterfaces[0].subnetId = <subnet-uid>`
- `instances[0].spec.desiredPowerState = "RUNNING"`

**Then** ответ содержит `instances[0]` с заполненными:
- `metadata.uid` — непустой UUID v4
- `metadata.name = "test-vm-01"`
- `metadata.folderId = <folder-uid>`
- `metadata.creationTimestamp` — не нулевое время
- `metadata.resourceVersion` — непустая строка с десятичным числом > 0
- `metadata.generation = 1`
- `metadata.finalizers[]` содержит `"compute.kacho.io/disk-detach"` (автоматически добавлен)
**And** `status.state = "PROVISIONING"` в первом ответе
**And** в `resource_events` событие `event_type = 'ADDED'`, `resource_kind = 'Instance'`
**And** gRPC статус = OK

### E2. Upsert: обновление spec Instance (idempotent при отсутствии diff)

**ID:** 0.4-E2

**Given** Instance `"test-vm-01"` создана (E1), `metadata.uid = <uid>`, `metadata.resourceVersion = <R>`

**When** клиент вызывает `InstanceService/Upsert` с тем же payload (без изменений)

**Then** ответ содержит тот же `metadata.uid = <uid>`
**And** `metadata.resourceVersion` не изменился (no-op, нет diff)
**And** в `resource_events` новых событий для данного uid не появилось

### E3. Upsert: изменение labels Instance — MODIFIED событие

**ID:** 0.4-E3

**Given** Instance `"test-vm-01"` в состоянии `RUNNING` существует

**When** клиент вызывает `InstanceService/Upsert` с:
- `instances[0].metadata.name = "test-vm-01"`
- `instances[0].metadata.folderId = <folder-uid>`
- `instances[0].metadata.labels = {"env": "staging"}`
- (остальные поля spec без изменений)

**Then** ответ содержит `metadata.labels = {"env": "staging"}`
**And** `metadata.resourceVersion` больше предыдущего значения
**And** в `resource_events` событие `event_type = 'MODIFIED'`, `resource_kind = 'Instance'`

### E4. Upsert Instance с несуществующим folderId — NOT_FOUND (cross-service: resource-manager)

**ID:** 0.4-E4

**Given** Folder с `uid = "00000000-0000-0000-0000-000000000001"` НЕ существует в resource-manager
**And** gRPC-вызов `ResourceManagerInternal/FolderExists` возвращает `{exists: false}`

**When** клиент вызывает `InstanceService/Upsert` с:
- `instances[0].metadata.name = "orphan-vm"`
- `instances[0].metadata.folderId = "00000000-0000-0000-0000-000000000001"`
- (прочие поля заполнены корректно)

**Then** gRPC статус = `NOT_FOUND`
**And** `details[]` содержит `ResourceInfo.resource_type = "Folder"`, `resource_name = "00000000-0000-0000-0000-000000000001"`
**And** Instance НЕ создана в БД

### E5. Upsert Instance с несуществующим subnetId — NOT_FOUND (cross-service: vpc)

**ID:** 0.4-E5

**Given** Folder `<folder-uid>` существует
**And** Subnet с `uid = "00000000-0000-0000-0000-000000000002"` НЕ существует в vpc
**And** gRPC-вызов `VpcInternal/SubnetExists` возвращает `{exists: false}`

**When** клиент вызывает `InstanceService/Upsert` с:
- `instances[0].spec.networkInterfaces[0].subnetId = "00000000-0000-0000-0000-000000000002"`

**Then** gRPC статус = `NOT_FOUND`
**And** `details[]` содержит `ResourceInfo.resource_type = "Subnet"`, `resource_name = "00000000-0000-0000-0000-000000000002"`
**And** Instance НЕ создана в БД

### E6. Upsert Instance с несуществующим bootDisk.diskId — INVALID_ARGUMENT

**ID:** 0.4-E6

**Given** Folder `<folder-uid>` существует, Subnet `<subnet-uid>` существует
**And** Disk с `uid = "00000000-0000-0000-0000-000000000003"` НЕ существует в `kacho_compute`

**When** клиент вызывает `InstanceService/Upsert` с:
- `instances[0].spec.bootDisk.diskId = "00000000-0000-0000-0000-000000000003"`

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "instances[0].spec.bootDisk.diskId"`

### E7. Upsert Instance: попытка задать status — INVALID_ARGUMENT

**ID:** 0.4-E7

**Given** Folder `<folder-uid>` существует

**When** клиент вызывает `InstanceService/Upsert` с:
- `instances[0].status.state = "RUNNING"` (попытка записать status через upsert)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "instances[0].status"`

### E8. Upsert Instance с пустым именем — INVALID_ARGUMENT

**ID:** 0.4-E8

**Given** Folder `<folder-uid>` существует

**When** клиент вызывает `InstanceService/Upsert` с:
- `instances[0].metadata.name = ""` (пустая строка)
- `instances[0].metadata.folderId = <folder-uid>`

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "instances[0].metadata.name"`

### E9. Upsert Instance с невалидным platformId — INVALID_ARGUMENT

**ID:** 0.4-E9

**Given** Folder `<folder-uid>` существует

**When** клиент вызывает `InstanceService/Upsert` с:
- `instances[0].spec.platformId = "nonexistent-platform"`

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "instances[0].spec.platformId"`

---

## 6. Группа F — Instance lifecycle (PROVISIONING → RUNNING через reconciler)

### F1. Instance lifecycle: PROVISIONING → RUNNING с симулированной задержкой

**ID:** 0.4-F1

**Given** Instance `"test-vm-01"` создана (E1), `status.state = "PROVISIONING"`
**And** `spec.desiredPowerState = "RUNNING"`
**And** Watch стрим `InstanceService/Watch` открыт для данной Instance
**And** Reconciler запущен

**When** ожидается в течение 60 секунд

**Then** Watch стрим получает событие `MODIFIED` с `status.state = "RUNNING"` в течение 60 секунд
**And** переход занимает от 5 до 30 секунд (в пределах симулированного диапазона)
**And** `status.state_last_transition_at` > `metadata.creationTimestamp`
**And** `status.ips.internal` не пустой (IP назначен из подсети)
**And** `metadata.resourceVersion` в финальном RUNNING-событии > resourceVersion при создании

### F2. Instance с bootDisk + secondaryDisk: оба диска в ATTACHING → READY при RUNNING

**ID:** 0.4-F2

**Given** Disk `"boot-disk"` с `uid = <boot-uid>` в состоянии `READY` существует
**And** Disk `"data-disk"` с `uid = <data-uid>` в состоянии `READY` существует
**And** Folder `<folder-uid>` и Subnet `<subnet-uid>` существуют

**When** клиент создаёт Instance `"vm-with-two-disks"` с:
- `spec.bootDisk.diskId = <boot-uid>`
- `spec.secondaryDisks[0].diskId = <data-uid>`
- `spec.desiredPowerState = "RUNNING"`
**And** ожидается в течение 60 секунд

**Then** Watch на `DiskService/Watch` показывает: Disk `<boot-uid>` переходит `READY → ATTACHING → READY (attached)` в течение 30 секунд
**And** Watch на `DiskService/Watch` показывает: Disk `<data-uid>` аналогично переходит `READY → ATTACHING → READY (attached)` в течение 30 секунд
**And** Watch на `InstanceService/Watch` показывает: Instance переходит `PROVISIONING → RUNNING` в течение 60 секунд
**And** `disk.status.attached_to_instance_id` = `<instance-uid>` для обоих дисков в финальном состоянии

### F3. Instance List: фильтр по folderId

**ID:** 0.4-F3

**Given** Существуют 3 Instance: две с `folderId = <folder-a>`, одна с `folderId = <folder-b>`

**When** клиент вызывает `InstanceService/List` с:
- `selectors[0].field_selector.folder_id = <folder-a>`

**Then** ответ содержит ровно 2 Instance
**And** Instance из `<folder-b>` не включена

---

## 7. Группа G — Instance power-state (desiredPowerState diff → STOPPED / RUNNING transitions)

### G1. desiredPowerState = STOPPED: RUNNING → STOPPING → STOPPED

**ID:** 0.4-G1

**Given** Instance `"test-vm-01"` в состоянии `RUNNING` (`spec.desiredPowerState = "RUNNING"`)
**And** Watch стрим `InstanceService/Watch` открыт

**When** клиент вызывает `InstanceService/Upsert` с:
- `instances[0].metadata.name = "test-vm-01"`
- `instances[0].metadata.folderId = <folder-uid>`
- `instances[0].spec.desiredPowerState = "STOPPED"` (изменение)
- (прочие поля spec без изменений)

**Then** ответ — OK, `metadata.resourceVersion` возрос, `spec.desiredPowerState = "STOPPED"`
**And** в течение 60 секунд Watch стрим получает события в порядке:
  1. `MODIFIED` с `status.state = "STOPPING"`
  2. `MODIFIED` с `status.state = "STOPPED"`
**And** переход STOPPING → STOPPED занимает от 5 до 15 секунд

### G2. desiredPowerState = RUNNING: STOPPED → STARTING → RUNNING

**ID:** 0.4-G2

**Given** Instance `"test-vm-01"` в состоянии `STOPPED` (`spec.desiredPowerState = "STOPPED"`)
**And** Watch стрим открыт

**When** клиент вызывает `InstanceService/Upsert` с `spec.desiredPowerState = "RUNNING"`

**Then** в течение 60 секунд Watch стрим получает события в порядке:
  1. `MODIFIED` с `status.state = "STARTING"`
  2. `MODIFIED` с `status.state = "RUNNING"`
**And** переход STARTING → RUNNING занимает от 5 до 15 секунд

### G3. Reconciler не переводит Instance в RUNNING если desiredPowerState = STOPPED

**ID:** 0.4-G3

**Given** Instance создаётся с `spec.desiredPowerState = "STOPPED"` (уже при создании хотим STOPPED)
**And** `status.state = "PROVISIONING"` после создания

**When** ожидается в течение 60 секунд

**Then** Watch стрим НЕ получает `MODIFIED` с `status.state = "RUNNING"`
**And** Instance в итоге переходит в `STOPPED` (PROVISIONING → STOPPED минуя RUNNING)

### G4. desiredPowerState diff: reconciler повторно сходится после сбоя

**ID:** 0.4-G4

**Given** Instance `"test-vm-02"` в состоянии `RUNNING`, `spec.desiredPowerState = "STOPPED"`
**And** Reconciler переместил Instance в `STOPPING`
**And** Сервис был перезапущен (имитация сбоя в середине перехода)

**When** Reconciler снова запускается после рестарта сервиса
**And** ожидается в течение 60 секунд

**Then** Instance достигает состояния `STOPPED` через Watch
**And** Reconciler повторно взял advisory lock и завершил незаконченный переход (idempotent)

---

## 8. Группа H — Instance Restart RPC

### H1. Restart: metadata.restartedAt выставляется, инициирует stop+start цикл

**ID:** 0.4-H1

**Given** Instance `"test-vm-01"` в состоянии `RUNNING`
**And** `status.lastRestartCompletedAt` отсутствует (null) или `< T_before_restart`
**And** Watch стрим `InstanceService/Watch` открыт

**When** клиент вызывает `kacho.cloud.compute.v1.InstanceService/Restart` с:
- `instances[0].metadata.uid = <instance-uid>`
**And** пусть `T_restart = now()` в момент вызова

**Then** ответ содержит Instance с `metadata.restartedAt = T_restart` (заполнено сервером)
**And** `metadata.resourceVersion` возрос
**And** в течение 60 секунд Watch стрим получает события в порядке:
  1. `MODIFIED` с `status.state = "STOPPING"` (начало stop-фазы)
  2. `MODIFIED` с `status.state = "STARTING"` (начало start-фазы)
  3. `MODIFIED` с `status.state = "RUNNING"` и `status.lastRestartCompletedAt = metadata.restartedAt`
**And** итоговый цикл занимает около 10 секунд (stop 5 с + start 5 с)

### H2. Restart: повторный Restart до завершения первого — новый цикл начинается после завершения текущего

**ID:** 0.4-H2

**Given** Instance `"test-vm-01"` в процессе первого Restart (`status.state = "STOPPING"`)
**And** `metadata.restartedAt = T1`

**When** клиент вызывает `InstanceService/Restart` ещё раз, теперь `metadata.restartedAt = T2 > T1`

**Then** Reconciler завершает первый цикл Restart
**And** после достижения `RUNNING` Reconciler обнаруживает `T2 > status.lastRestartCompletedAt` и инициирует второй stop+start цикл
**And** итоговое `status.lastRestartCompletedAt = T2`

### H3. Restart на STOPPED Instance — FAILED_PRECONDITION

**ID:** 0.4-H3

**Given** Instance `"test-vm-01"` в состоянии `STOPPED`

**When** клиент вызывает `InstanceService/Restart` с `instances[0].metadata.uid = <instance-uid>`

**Then** gRPC статус = `FAILED_PRECONDITION`
**And** `details[]` содержит `PreconditionFailure` с `violations[0].type = "INVALID_STATE_FOR_RESTART"` и `violations[0].subject = <instance-uid>`
**And** `violations[0].description` указывает, что Restart возможен только из состояния `RUNNING`

### H4. Restart: идентичный restartedAt (повтор того же запроса) — no-op

**ID:** 0.4-H4

**Given** Instance `"test-vm-01"` в состоянии `RUNNING`
**And** `metadata.restartedAt = T` и `status.lastRestartCompletedAt = T` (предыдущий restart завершён)

**When** клиент вызывает `InstanceService/Restart` снова, но сервер присваивает тот же `T` (edge case: timestamp с гранулярностью секунды, запросы < 1 с)

**Then** Reconciler проверяет: `metadata.restartedAt == status.lastRestartCompletedAt` → условие не выполнено (no pending restart)
**And** Instance остаётся в состоянии `RUNNING` без нового stop+start цикла

---

## 9. Группа I — Instance finalizer (disk-detach при Delete)

### I1. Delete Instance с прикреплённым bootDisk: finalizer срабатывает, диск отвязывается

**ID:** 0.4-I1

**Given** Instance `"test-vm-01"` в состоянии `RUNNING`
**And** `metadata.finalizers[] = ["compute.kacho.io/disk-detach"]`
**And** Disk `<boot-uid>` прикреплён как bootDisk, `disk.status.attached_to_instance_id = <instance-uid>`
**And** Watch стрим `InstanceService/Watch` открыт

**When** клиент вызывает `InstanceService/Delete` с `instances[0].metadata.uid = <instance-uid>`

**Then** ответ — OK (мягкое удаление: `metadata.deletionTimestamp` выставлен)
**And** Instance сразу не удалена физически (finalizers не пусты)
**And** Watch стрим получает `MODIFIED` с `metadata.deletionTimestamp != null`, `status.state = "DELETING"`
**And** в течение 30 секунд Reconciler выполняет:
  1. Отвязывает все прикреплённые диски (UPDATE disk: `attached_to_instance_id = NULL`, `status.state = DETACHING → READY`)
  2. Удаляет `"compute.kacho.io/disk-detach"` из `metadata.finalizers[]`
  3. Instance физически удаляется из БД
**And** Watch стрим получает финальное событие `DELETED` для Instance
**And** `disk.status.attached_to_instance_id` = null после отвязки
**And** Watch на `DiskService/Watch` показывает `MODIFIED` с `status.state = "DETACHING"` затем `MODIFIED` с `status.state = "READY"`

### I2. Delete Instance: autoDelete=true на bootDisk → диск удаляется после detach

**ID:** 0.4-I2

**Given** Instance `"vm-auto-delete"` в состоянии `RUNNING`
**And** `spec.bootDisk.autoDelete = true`, `spec.bootDisk.diskId = <boot-uid>`
**And** `spec.secondaryDisks[0].autoDelete = false`, `spec.secondaryDisks[0].diskId = <data-uid>`

**When** клиент вызывает `InstanceService/Delete`

**Then** в течение 30 секунд Reconciler:
  1. Отвязывает оба диска
  2. Удаляет только `<boot-uid>` (autoDelete=true) через `DELETE FROM disks`
  3. Оставляет `<data-uid>` (autoDelete=false) в состоянии `READY` (не удаляет)
**And** Watch на `DiskService/Watch` показывает `DELETED` для `<boot-uid>` и `MODIFIED (READY)` для `<data-uid>`

### I3. Delete Instance без Disk: finalizer удаляется, Instance уходит немедленно

**ID:** 0.4-I3

**Given** Instance `"vm-no-disk"` создана без secondaryDisks, только с bootDisk `<boot-uid>`
**And** Disk `<boot-uid>` уже был удалён (orphaned instance)
**And** `metadata.finalizers[] = ["compute.kacho.io/disk-detach"]`

**When** клиент вызывает `InstanceService/Delete`

**Then** Reconciler обнаруживает: дисков для detach нет (FK-join пуст или дисков с attachment на эту instance нет)
**And** Reconciler удаляет finalizer без ожидания
**And** Instance физически удаляется
**And** Watch показывает `DELETED` в течение 10 секунд

### I4. Повторный Delete Instance с deletionTimestamp — NOT_FOUND или no-op

**ID:** 0.4-I4

**Given** Instance `"test-vm-01"` физически удалена (после завершения finalizer-а)

**When** клиент вызывает `InstanceService/Delete` с тем же uid снова

**Then** gRPC статус = `NOT_FOUND`
**And** `details[]` содержит `ResourceInfo.resource_type = "Instance"`, `resource_name = <instance-uid>`

---

## 10. Группа J — Reconciler properties (multi-replica, idempotency, recovery)

### J1. Advisory lock: два reconciler-а на одной Instance — только один реально обрабатывает

**ID:** 0.4-J1

**Given** Запущены 2 реплики `kacho-compute` (имитируется двумя goroutines reconciler в integration-тесте)
**And** Обе реплики обнаружили Instance `"shared-vm"` с `status.state = "PROVISIONING"` для обработки

**When** Обе реплики одновременно пытаются взять `pg_advisory_lock(hash(<instance-uid>))`

**Then** Только одна реплика получает lock и выполняет переход
**And** Вторая реплика блокируется на `pg_advisory_lock` или получает false от `pg_try_advisory_lock` и пропускает ресурс
**And** Instance переходит в `RUNNING` ровно один раз (нет двойного перехода)
**And** В `resource_events` ровно одно событие `MODIFIED` с `status.state = "RUNNING"` для данной Instance

### J2. Reconciler идемпотентен: повторный запуск на уже RUNNING Instance — no-op

**ID:** 0.4-J2

**Given** Instance `"stable-vm"` в состоянии `RUNNING`, `spec.desiredPowerState = "RUNNING"` (no diff)
**And** Reconciler делает новый poll (например, после перезапуска)

**When** Reconciler обнаруживает Instance в БД и проверяет условия

**Then** `status.state == desired → no pending work` → Reconciler не выполняет никаких действий
**And** В `resource_events` нет новых событий для данной Instance
**And** `metadata.resourceVersion` Instance не изменился

### J3. Reconciler recovery: Instance застряла в STOPPING после краша сервиса

**ID:** 0.4-J3

**Given** Instance `"stuck-vm"` имеет `status.state = "STOPPING"` и `spec.desiredPowerState = "STOPPED"`
**And** Сервис был убит во время обработки (имитируется прямой записью статуса в БД в integration-тесте через testcontainers)
**And** Advisory lock был освобождён при краше сессии Postgres

**When** Сервис перезапускается и Reconciler делает первый poll

**Then** Reconciler находит Instance с `status.state = "STOPPING"` и `spec.desiredPowerState = "STOPPED"`
**And** Reconciler продолжает переход: ждёт симулированное время, затем устанавливает `status.state = "STOPPED"`
**And** Watch показывает `MODIFIED` с `status.state = "STOPPED"` в течение 60 секунд
**And** Instance не застряла навсегда

### J4. Reconciler: одновременный poll нескольких Instance с разными lock-ами

**ID:** 0.4-J4

**Given** В БД 5 Instance одновременно в состоянии `PROVISIONING`
**And** Reconciler использует SELECT с LIMIT для batch-обработки (например, LIMIT 10)

**When** Reconciler делает один poll

**Then** Reconciler пытается взять `pg_advisory_lock` отдельно для каждой Instance
**And** Все 5 Instance в течение 60 секунд переходят в `RUNNING`
**And** В `resource_events` ровно по одному `MODIFIED (RUNNING)` для каждой Instance (без дублей)

### J5. Cleanup advisory lock: координация cleanup между reconciler-репликами

**ID:** 0.4-J5

**Given** 2 реплики сервиса `kacho-compute` запущены одновременно
**And** Cleanup горутина каждой реплики периодически пытается выполнить `DELETE FROM resource_events WHERE created_at < now() - interval '1 hour'`
**And** Обе реплики используют `pg_advisory_xact_lock(hashtext('kacho_compute_cleanup'))`

**When** Обе реплики одновременно пытаются выполнить cleanup

**Then** Только одна реплика в каждый момент выполняет cleanup
**And** Нет двойного удаления, нет deadlock

---

## 11. Группа K — Internal RPC и cross-service из compute

### K1. Internal.InstanceExists: существующая Instance возвращает exists=true

**ID:** 0.4-K1

**Given** Instance `"test-vm-01"` с `uid = <instance-uid>` существует

**When** вызывается `kacho.cloud.compute.v1.ComputeInternal/InstanceExists` с `uid = <instance-uid>`

**Then** ответ: `{exists: true}`
**And** gRPC статус = OK

### K2. Internal.InstanceExists: несуществующая Instance возвращает exists=false

**ID:** 0.4-K2

**Given** Instance с `uid = "00000000-0000-0000-0000-000000000099"` НЕ существует

**When** вызывается `ComputeInternal/InstanceExists` с `uid = "00000000-0000-0000-0000-000000000099"`

**Then** ответ: `{exists: false}`
**And** gRPC статус = OK (не NOT_FOUND — это Exists-метод)

### K3. Internal.InstanceExists: Instance с deletionTimestamp → exists=false

**ID:** 0.4-K3

**Given** Instance `"zombie-vm"` с `uid = <instance-uid>` имеет `deletion_timestamp != NULL` (soft-deleted, finalizer ещё не выполнен)

**When** вызывается `ComputeInternal/InstanceExists` с `uid = <instance-uid>`

**Then** ответ: `{exists: false}`
**And** gRPC статус = OK

*Обоснование:* Instance в процессе удаления не должна использоваться как target в TargetGroup (sub-phase 0.5). `Exists` = false для soft-deleted ресурсов — единообразно с политикой resource-manager (сценарий F5 в 0.2).

### K4. Cross-service: compute → resource-manager FolderExists — ресурс-менеджер UNAVAILABLE

**ID:** 0.4-K4

**Given** Сервис `kacho-resource-manager` недоступен (имитируется отключением в integration-тесте)
**And** Клиент пытается создать Instance в Folder

**When** клиент вызывает `InstanceService/Upsert` с валидным `folderId` (который существовал бы при доступном ресурс-менеджере)

**Then** gRPC статус = `UNAVAILABLE`
**And** `details[]` содержит `RequestInfo` с непустым `request_id`
**And** message содержит указание на недоступность вышестоящего сервиса
**And** Instance НЕ создана в БД

### K5. Cross-service: compute → vpc SubnetExists — vpc UNAVAILABLE

**ID:** 0.4-K5

**Given** Сервис `kacho-vpc` недоступен
**And** Folder `<folder-uid>` существует (resource-manager доступен)

**When** клиент вызывает `InstanceService/Upsert` с валидным `subnetId`

**Then** gRPC статус = `UNAVAILABLE`
**And** Instance НЕ создана в БД

### K6. Internal.UpdateStatus: reconciler корректно обновляет status.state Instance

**ID:** 0.4-K6

**Given** Instance `"test-vm-01"` с `status.state = "PROVISIONING"` существует

**When** reconciler вызывает `ComputeInternal/UpdateInstanceStatus` с:
- `uid = <instance-uid>`
- `status.state = "RUNNING"`
- `status.ips.internal = "10.0.0.5"`

**Then** в БД `instances.status.state = "RUNNING"` и `status.ips.internal = "10.0.0.5"`
**And** в `resource_events` событие `event_type = 'MODIFIED'`, `resource_kind = 'Instance'`
**And** `metadata.resourceVersion` Instance возрос

### K7. Internal.UpdateStatus: повторный вызов с тем же status — no-op

**ID:** 0.4-K7

**Given** Instance `"test-vm-01"` с `status.state = "RUNNING"`

**When** reconciler вызывает `ComputeInternal/UpdateInstanceStatus` с `status.state = "RUNNING"` (нет изменений)

**Then** gRPC статус = OK
**And** В `resource_events` нет нового события для данной Instance
**And** `metadata.resourceVersion` не изменился

---

## 12. Группа L — Watch (события по lifecycle для Instance, Snapshot progress)

### L1. Watch Instance: полный lifecycle PROVISIONING → RUNNING в одном стриме

**ID:** 0.4-L1

**Given** Watch стрим `InstanceService/Watch` открыт с `resourceVersion = <текущий>` и пустым selectors
**And** Reconciler запущен

**When** клиент создаёт Instance `"watch-vm"` с `spec.desiredPowerState = "RUNNING"`

**Then** Watch стрим получает события в порядке:
1. `type = ADDED`, `instance.status.state = "PROVISIONING"`
2. `type = MODIFIED`, `instance.status.state = "RUNNING"` (в течение 60 с)
**And** события идут в порядке возрастания `metadata.resourceVersion`

### L2. Watch Instance: фильтрация по folderId — клиент видит только свои ресурсы

**ID:** 0.4-L2

**Given** Watch стрим открыт с `selectors[0].field_selector.folder_id = <folder-a>`
**And** Существуют Instance в `<folder-a>` и в `<folder-b>`

**When** Instance в `<folder-b>` переходит в `RUNNING`
**And** Instance в `<folder-a>` переходит в `RUNNING`

**Then** Watch стрим получает только одно событие (для Instance в `<folder-a>`)
**And** событие для Instance в `<folder-b>` NOT поступает в этот стрим

### L3. Watch Snapshot: прогресс CREATING → промежуточные → READY

**ID:** 0.4-L3

**Given** Watch стрим `SnapshotService/Watch` открыт

**When** создаётся Snapshot для Disk в состоянии READY

**Then** Watch стрим получает событие `ADDED` с `status.state = "CREATING"` и `status.progress_percent = 0`
**And** Watch стрим получает хотя бы одно `MODIFIED` с `0 < status.progress_percent < 100`
**And** Watch стрим получает `MODIFIED` с `status.state = "READY"` и `status.progress_percent = 100`

### L4. Watch Instance: catch-up для отстающего клиента

**ID:** 0.4-L4

**Given** 5 Instance созданы и перешли в RUNNING, их события в outbox с `resource_version` 1..10
**And** Retention не истёк

**When** новый Watch-клиент открывает стрим `InstanceService/Watch` с `resourceVersion = 2`

**Then** стрим сначала отправляет catch-up события с `resource_version > 2` (события 3..10)
**And** затем стрим переходит в live-режим

### L5. Watch Instance: Gone 410 при устаревшем resourceVersion

**ID:** 0.4-L5

**Given** Cleanup удалил события с `resource_version < 5000` из `resource_events`
**And** Минимальная `resource_version` в outbox = 5000

**When** клиент открывает Watch стрим с `resourceVersion = 100` (заведомо устаревший)

**Then** сервер закрывает стрим с gRPC статусом `OUT_OF_RANGE` и message `"Gone: resourceVersion too old, please relist"`
**And** `details[]` содержит `ErrorInfo` с `reason = "RESOURCE_VERSION_EXPIRED"` и `domain = "kacho.cloud"`
**And** `details[]` содержит `RequestInfo` с непустым `request_id`

---

## 13. Группа M — Negative scenarios

### M1. Concurrent Upsert Instance — ABORTED (OCC protection)

**ID:** 0.4-M1

**Given** Instance `"shared-vm"` существует с `metadata.resourceVersion = <R>`

**When** два параллельных `InstanceService/Upsert` для одной Instance отправляются одновременно:
- вызов A: `spec.resources.cores = 2`
- вызов B: `spec.resources.cores = 4`

**Then** ровно один вызов завершается с gRPC статусом `OK`
**And** второй завершается с gRPC статусом `ABORTED`
**And** В БД ровно одна запись `"shared-vm"` с cores победившего вызова

### M2. Upsert Instance с невалидным desiredPowerState — INVALID_ARGUMENT

**ID:** 0.4-M2

**Given** Folder `<folder-uid>` существует

**When** клиент вызывает `InstanceService/Upsert` с:
- `instances[0].spec.desiredPowerState = "TURBO"` (несуществующий enum)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "instances[0].spec.desiredPowerState"`

### M3. Upsert Instance: spec.resources.cores = 0 — INVALID_ARGUMENT

**ID:** 0.4-M3

**Given** Folder `<folder-uid>` существует

**When** клиент вызывает `InstanceService/Upsert` с:
- `instances[0].spec.resources.cores = 0`

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "instances[0].spec.resources.cores"`
**And** `description` содержит требование cores ≥ 1

### M4. Upsert Disk с невалидным zoneId — INVALID_ARGUMENT

**ID:** 0.4-M4

**Given** Folder `<folder-uid>` существует

**When** клиент вызывает `DiskService/Upsert` с:
- `disks[0].spec.zoneId = "nonexistent-zone"`

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "disks[0].spec.zoneId"`

### M5. Delete Disk прикреплённого к Instance — FAILED_PRECONDITION

**ID:** 0.4-M5

**Given** Disk `"attached-disk"` с `status.attached_to_instance_id = <instance-uid>` (состояние READY, но помечен как attached)

**When** клиент вызывает `DiskService/Delete` с `disks[0].metadata.uid = <disk-uid>`

**Then** gRPC статус = `FAILED_PRECONDITION`
**And** `details[]` содержит `PreconditionFailure` с `violations[0].type = "DISK_ATTACHED_TO_INSTANCE"` и `violations[0].subject = <disk-uid>`
**And** `violations[0].description` указывает `attached_to_instance_id = <instance-uid>`
**And** Disk НЕ удалён

### M6. Restart несуществующей Instance — NOT_FOUND

**ID:** 0.4-M6

**Given** Instance с `uid = "00000000-0000-0000-0000-000000000099"` НЕ существует

**When** клиент вызывает `InstanceService/Restart` с `instances[0].metadata.uid = "00000000-0000-0000-0000-000000000099"`

**Then** gRPC статус = `NOT_FOUND`
**And** `details[]` содержит `ResourceInfo.resource_type = "Instance"`

### M7. Restart на Instance в состоянии PROVISIONING — FAILED_PRECONDITION

**ID:** 0.4-M7

**Given** Instance `"new-vm"` в состоянии `PROVISIONING`

**When** клиент вызывает `InstanceService/Restart`

**Then** gRPC статус = `FAILED_PRECONDITION`
**And** `details[]` содержит `PreconditionFailure` с `violations[0].type = "INVALID_STATE_FOR_RESTART"`
**And** Restart применяется только из состояния `RUNNING`

### M8. Upsert Instance с pустым networkInterfaces — INVALID_ARGUMENT

**ID:** 0.4-M8

**Given** Folder `<folder-uid>` существует, Disk `<boot-disk-uid>` в состоянии READY

**When** клиент вызывает `InstanceService/Upsert` с:
- `instances[0].spec.networkInterfaces = []` (пустой список)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "instances[0].spec.networkInterfaces"`
**And** Требуется хотя бы один сетевой интерфейс

### M9. List Instance с невалидным page_size — INVALID_ARGUMENT

**ID:** 0.4-M9

**Given** Сервис `InstanceService` запущен

**When** клиент вызывает `InstanceService/List` с `page_size = 9999` (> 1000 лимита)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[].field_violations[0].field = "page_size"`
**And** `description` содержит максимальное значение 1000

### M10. Watch с невалидным resourceVersion — INVALID_ARGUMENT

**ID:** 0.4-M10

**Given** Сервис `InstanceService` запущен

**When** клиент открывает Watch стрим с `resourceVersion = "not-a-number"`

**Then** сервер немедленно возвращает ошибку `INVALID_ARGUMENT`
**And** `details[].field_violations[0].field = "resource_version"`

---

## 14. Группа N — Seed-таблицы (zones, disk_types, platforms, images_catalog)

### N1. Миграция 0002_seed_catalogs.sql создаёт seed zones

**ID:** 0.4-N1

**Given** Postgres запущен с применёнными миграциями `0001_initial.sql` и `0002_seed_catalogs.sql`

**When** разработчик выполняет `SELECT name FROM zones`

**Then** результат содержит как минимум:
- `"kacho-zone-a"`
- `"kacho-zone-b"`
**And** каждая запись имеет поле `region_id = "kacho-region-a"`

### N2. Миграция создаёт seed disk_types

**ID:** 0.4-N2

**Given** Применена миграция `0002_seed_catalogs.sql`

**When** разработчик выполняет `SELECT id FROM disk_types`

**Then** результат содержит как минимум:
- `"network-hdd"`
- `"network-ssd"`
- `"network-ssd-nonreplicated"`

### N3. Миграция создаёт seed platforms

**ID:** 0.4-N3

**Given** Применена миграция `0002_seed_catalogs.sql`

**When** разработчик выполняет `SELECT id FROM platforms`

**Then** результат содержит как минимум:
- `"standard-v1"`
- `"standard-v2"`
- `"standard-v3"`

### N4. Миграция создаёт seed images_catalog

**ID:** 0.4-N4

**Given** Применена миграция `0002_seed_catalogs.sql`

**When** разработчик выполняет `SELECT name FROM images_catalog`

**Then** результат содержит как минимум:
- `"ubuntu-2204-lts"`
- `"debian-12"`
**And** каждая запись имеет `status = 'READY'`

### N5. Миграция seed idempotentна: повторное применение не создаёт дубли

**ID:** 0.4-N5

**Given** Postgres запущен с применёнными миграциями `0001` и `0002`

**When** миграция откатывается (`goose down`) и применяется заново (`goose up`)

**Then** `SELECT count(*) FROM zones WHERE name = 'kacho-zone-a'` = 1 (нет дублей)
**And** `SELECT count(*) FROM platforms` = ожидаемое количество seed-записей (без дублей)

---

## 15. Группа O — End-to-end smoke (port-forward, full flow)

### O1. Full flow: Folder → Network → Subnet → Disk → Instance → Watch lifecycle

**ID:** 0.4-O1

**Given** `kacho-resource-manager`, `kacho-vpc`, `kacho-compute` Pod-ы запущены в namespace `kacho`
**And** `kubectl port-forward svc/resource-manager 9090:9090 -n kacho` активен
**And** `kubectl port-forward svc/vpc 9091:9090 -n kacho` активен
**And** `kubectl port-forward svc/compute 9092:9090 -n kacho` активен

**When** выполняется скрипт `kacho-deploy/e2e/0.4/O1-full-flow.sh`:
```bash
# Шаг 1: получить default Folder uid
FOLDER_UID=$(grpcurl -plaintext -d '{}' localhost:9090 \
  kacho.cloud.resourcemanager.v1.FolderService/List \
  | jq -r '.folders[0].metadata.uid')

# Шаг 2: создать Network
NET_UID=$(grpcurl -plaintext \
  -d "{\"networks\":[{\"metadata\":{\"name\":\"e2e-net\",\"folderId\":\"$FOLDER_UID\"}}]}" \
  localhost:9091 kacho.cloud.vpc.v1.NetworkService/Upsert \
  | jq -r '.networks[0].metadata.uid')

# Шаг 3: создать Subnet
SUBNET_UID=$(grpcurl -plaintext \
  -d "{\"subnets\":[{\"metadata\":{\"name\":\"e2e-subnet\",\"folderId\":\"$FOLDER_UID\"},\"spec\":{\"networkId\":\"$NET_UID\",\"cidrBlock\":\"10.0.0.0/24\",\"zoneId\":\"kacho-zone-a\"}}]}" \
  localhost:9091 kacho.cloud.vpc.v1.SubnetService/Upsert \
  | jq -r '.subnets[0].metadata.uid')

# Шаг 4: создать Disk
DISK_UID=$(grpcurl -plaintext \
  -d "{\"disks\":[{\"metadata\":{\"name\":\"e2e-boot-disk\",\"folderId\":\"$FOLDER_UID\"},\"spec\":{\"diskTypeId\":\"network-ssd\",\"zoneId\":\"kacho-zone-a\",\"size\":\"30Gi\"}}]}" \
  localhost:9092 kacho.cloud.compute.v1.DiskService/Upsert \
  | jq -r '.disks[0].metadata.uid')

# Шаг 5: дождаться READY для Disk (до 30 с)
# ...watch loop...

# Шаг 6: создать Instance
INST_UID=$(grpcurl -plaintext \
  -d "{\"instances\":[{\"metadata\":{\"name\":\"e2e-vm\",\"folderId\":\"$FOLDER_UID\"},\"spec\":{\"platformId\":\"standard-v3\",\"zoneId\":\"kacho-zone-a\",\"resources\":{\"cores\":2,\"memory\":\"4Gi\"},\"bootDisk\":{\"diskId\":\"$DISK_UID\",\"autoDelete\":true},\"networkInterfaces\":[{\"subnetId\":\"$SUBNET_UID\"}],\"desiredPowerState\":\"RUNNING\"}}]}" \
  localhost:9092 kacho.cloud.compute.v1.InstanceService/Upsert \
  | jq -r '.instances[0].metadata.uid')

# Шаг 7: дождаться RUNNING через Watch (до 60 с)
# ...watch loop...

# Шаг 8: проверить List
grpcurl -plaintext \
  -d "{\"selectors\":[{\"fieldSelector\":{\"folderId\":\"$FOLDER_UID\"}}]}" \
  localhost:9092 kacho.cloud.compute.v1.InstanceService/List
```

**Then** шаг 1 возвращает непустой `FOLDER_UID`
**And** шаги 2–4 возвращают gRPC OK с заполненными uid
**And** на шаге 5 Disk достигает `READY` в течение 30 секунд
**And** на шаге 7 Instance достигает `RUNNING` в течение 60 секунд
**And** шаг 8 возвращает массив с `"name": "e2e-vm"` и `status.state = "RUNNING"`

### O2. e2e Restart: metadata.restartedAt, RESTARTING цепочка через Watch

**ID:** 0.4-O2

**Given** Instance `"e2e-vm"` в состоянии `RUNNING` (из O1)
**And** Watch стрим на Instance открыт в фоне

**When** выполняется скрипт `kacho-deploy/e2e/0.4/O2-restart.sh`:
```bash
grpcurl -plaintext \
  -d "{\"instances\":[{\"metadata\":{\"uid\":\"$INST_UID\"}}]}" \
  localhost:9092 kacho.cloud.compute.v1.InstanceService/Restart
```

**Then** команда возвращает gRPC OK с заполненным `metadata.restartedAt`
**And** в течение 60 секунд Watch стрим получает: `MODIFIED(STOPPING) → MODIFIED(STARTING) → MODIFIED(RUNNING)`
**And** итоговое событие содержит `status.lastRestartCompletedAt == metadata.restartedAt`

### O3. e2e power-state: desiredPowerState = STOPPED → reconciler переводит в STOPPED

**ID:** 0.4-O3

**Given** Instance `"e2e-vm"` в состоянии `RUNNING`

**When** выполняется `InstanceService/Upsert` с изменением `spec.desiredPowerState = "STOPPED"`

**Then** в течение 30 секунд через Watch наблюдается цепочка: `MODIFIED(STOPPING) → MODIFIED(STOPPED)`

### O4. e2e Delete Instance с finalizer: диск отвязывается, Instance удаляется

**ID:** 0.4-O4

**Given** Instance `"e2e-vm"` в состоянии `STOPPED` с `metadata.finalizers = ["compute.kacho.io/disk-detach"]`
**And** Disk `"e2e-boot-disk"` прикреплён (`spec.bootDisk.autoDelete = true`)

**When** выполняется `InstanceService/Delete` для Instance

**Then** в течение 30 секунд:
  1. Watch на InstanceService показывает `MODIFIED` с `metadata.deletionTimestamp` и `DELETING`
  2. Watch на DiskService показывает `MODIFIED(DETACHING) → MODIFIED(READY)` для boot-диска, затем `DELETED` (autoDelete=true)
  3. Watch на InstanceService показывает `DELETED`
**And** `InstanceService/List` больше не возвращает `"e2e-vm"`

### O5. e2e Snapshot: создание, прогресс, READY

**ID:** 0.4-O5

**Given** Disk `"e2e-boot-disk"` (или новый диск) в состоянии `READY`
**And** Watch стрим на SnapshotService открыт в фоне

**When** выполняется `SnapshotService/Upsert` для создания Snapshot

**Then** в течение 60 секунд Watch показывает: `ADDED (progress=0) → MODIFIED (0 < progress < 100) → MODIFIED (state=READY, progress=100)`

### O6. Helm chart kacho-compute деплоится и проходит readiness probe

**ID:** 0.4-O6

**Given** `kind`-кластер поднят (`make dev-up`)
**And** В `kacho-deploy/helm/` присутствует chart для `compute`
**And** Image `prorobotech/kacho-compute:0.4.0` доступен

**When** выполняется `helm upgrade --install compute kacho-deploy/helm/compute/ -n kacho --values kacho-deploy/helm/compute/values.dev.yaml`

**Then** Pod `compute-*` переходит в статус `Running` и `Ready 1/1` в течение 90 секунд
**And** `kubectl exec -n kacho ... -- grpc_health_probe -addr :9090` возвращает `status: SERVING`
**And** Лог Pod содержит строку `"reconciler started"` или аналогичную
**And** БД `kacho_compute` содержит таблицы `instances`, `disks`, `images`, `snapshots`, `zones`, `disk_types`, `platforms`, `images_catalog`, `resource_events`

---

## 16. Группа P — Definition of Done

Sub-итерация 0.4 считается **завершённой**, когда **все** условия выполнены:

1. **Все сценарии §1–§15** (A1–A6, B1–B9, C1–C5, D1–D6, E1–E9, F1–F3, G1–G4, H1–H4, I1–I4, J1–J5, K1–K7, L1–L5, M1–M10, N1–N5, O1–O6) покрыты исполняемыми тестами:
   - Integration-тесты (testcontainers-Postgres) в `kacho-compute/internal/service/*_acceptance_test.go` — все зелёные.
   - E2E bash-скрипты в `kacho-deploy/e2e/0.4/*.sh` — все зелёные при запуске `make e2e-test PHASE=0.4`.

2. **Proto** `kacho-proto/proto/kacho/cloud/compute/v1/` содержит:
   - `instance.proto` — `InstanceService` с Upsert, Delete, List, Watch, Restart; все message-типы
   - `disk.proto` — `DiskService` с Upsert, Delete, List, Watch; Disk.Spec и Disk.Status
   - `image.proto` — `ImageService` с Get и List (только); Image.Status.state = READY
   - `snapshot.proto` — `SnapshotService` с Upsert, Delete, List, Watch; Snapshot.Status с progress_percent
   - `internal.proto` — `ComputeInternal` с InstanceExists, UpdateInstanceStatus, UpdateDiskStatus, UpdateSnapshotStatus, UpdateInstanceMetadata
   - `buf lint` и `buf breaking` — зелёные

3. **kacho-compute** реализован с Clean Architecture:
   - `cmd/compute/main.go` — composition root (единственное место wiring)
   - `internal/domain/` — entity-типы Instance, Disk, Image, Snapshot (импортирует только stdlib и kacho-proto)
   - `internal/service/` — use-cases с port-интерфейсами (`InstanceRepo`, `DiskRepo`, `FolderClient`, `SubnetClient`); бизнес-логика reconciler; **никакого pgx/sqlc в service/**
   - `internal/repo/` — sqlc-generated queries + handwritten filter-builder (реализует port-интерфейсы service)
   - `internal/clients/` — gRPC-клиенты для resource-manager и vpc (реализуют port-интерфейсы service)
   - `internal/reconciler/` — фоновая горутина reconciler, `pg_advisory_lock`, симулированные переходы
   - `internal/handler/` — тонкий transport-слой (parse-request → service → format-response, никакой бизнес-логики)
   - `internal/handler/internal_handler.go` — Internal RPC (не регистрируется в api-gateway)
   - `migrations/` — `0001_initial.sql` (scheme), `0002_seed_catalogs.sql` (seed-данные)
   - `deploy/` — Dockerfile, Helm chart values

4. **Reconciler**:
   - Использует `pg_advisory_lock(uid_hash)` per-resource для координации multi-replica
   - Симулирует задержки (константы из config или hardcoded): PROVISIONING→RUNNING 5–30 с, STOPPING→STOPPED 5–15 с, STARTING→RUNNING 5–15 с, SNAPSHOT progress 10–30 с
   - Идемпотентен: повторный запуск на уже завершённом ресурсе — no-op
   - Recovery: после сбоя сервиса находит ресурсы в промежуточных состояниях и завершает переходы

5. **Cross-service validation**:
   - При Upsert Instance/Disk с folderId → gRPC `ResourceManagerInternal/FolderExists`
   - При Upsert Instance с subnetId → gRPC `VpcInternal/SubnetExists`
   - При недоступности downstream → `UNAVAILABLE`

6. **Finalizer `compute.kacho.io/disk-detach`**:
   - Автоматически добавляется сервером при Upsert Instance (при наличии дисков)
   - Reconciler корректно выполняет detach всех дисков перед физическим удалением Instance
   - `autoDelete=true` → диск удаляется после detach

7. **Helm chart** для `compute` добавлен в `kacho-deploy/helm/` и в `helm/umbrella/Chart.yaml`.

8. **CI** всех затронутых репо зелёный:
   - `kacho-proto`: `buf-lint`, `buf-breaking`, `buf-generate` (без диффа в gen/)
   - `kacho-compute`: `golangci-lint`, `go test ./...` (включая integration с testcontainers)
   - `kacho-deploy`: `helm lint`

9. **Naming conventions** соблюдены:
   - Proto package: `kacho.cloud.compute.v1`
   - DB: `kacho_compute`
   - Env: `KACHO_COMPUTE_*`
   - k8s service: `compute.kacho.svc.cluster.local`
   - Docker image: `prorobotech/kacho-compute:0.4.0`
   - Finalizer: `compute.kacho.io/disk-detach`

10. **Clean Architecture** соблюдена (проверяется `go-style-reviewer`):
    - `domain/` и `service/` не импортируют `pgx`, `sqlc`-типы, grpc-stubs
    - Бизнес-логика отсутствует в `handler/`
    - Глобальных синглтонов (`var globalPool`, `init()`-side-effects) нет вне `cmd/`

11. `kacho-workspace/docs/specs/CHANGELOG.md` содержит запись о завершении sub-phase 0.4.

12. Тег `kacho-compute:0.4.0` поставлен на `main`.

---

## 17. Открытые вопросы к acceptance-reviewer (§11)

**OQ-1. Точные интервалы симулированных задержек**

В задании задан диапазон «5–30 с» для PROVISIONING → RUNNING. Для детерминированного тестирования предлагается:
- Задержки параметризуются через env-переменные: `KACHO_COMPUTE_SIM_PROVISIONING_MIN_MS`, `KACHO_COMPUTE_SIM_PROVISIONING_MAX_MS` и т.д.
- В unit/integration тестах значения переопределяются до минимума (например, 100 мс), чтобы тесты не тормозили.
- E2E тесты используют prod-диапазоны с timeout 60 с.

*Вопрос:* Согласны ли с таким подходом? Или фиксируем конкретные значения в конфиге (без диапазона)?

**OQ-2. Политика инкрементов Snapshot progress_percent**

Как часто reconciler эмитирует промежуточные события progress? Варианты:
- (A) Фиксированные шаги: 0 → 25 → 50 → 75 → 100, одно событие каждые ~25% от общего времени.
- (B) Один тик в секунду: каждую секунду progress увеличивается на `100 / total_seconds`.
- (C) Случайные инкременты: reconciler спит случайное время, затем атомарно переходит в READY.

*Вопрос:* Какой вариант предпочтителен? Сценарий D2 и L3 предполагают хотя бы одно промежуточное значение, поэтому вариант C (одного прыжка) не подходит.

**OQ-3. Политика disk-attach для Instance в PROVISIONING**

Когда именно reconciler меняет Disk.status.state на `ATTACHING`? Варианты:
- (A) В начале PROVISIONING: сразу ставит диски в ATTACHING, затем RUNNING → диски READY (attached).
- (B) Диски остаются READY до перехода Instance в RUNNING, затем атомарно помечаются attached.
- (C) Отдельная фаза: PROVISIONING → (disk ATTACHING, затем READY) → RUNNING.

Сценарий F2 предполагает вариант A или C (переходы ATTACHING → READY видны через Watch до RUNNING Instance).

*Вопрос:* Подтвердить выбранную политику.

**OQ-4. Поле status.ips.internal — как назначается IP?**

Instance получает `status.ips.internal` при переходе в RUNNING. Варианты назначения:
- (A) Reconciler берёт `spec.networkInterfaces[0].primaryV4Address.address` (если задан клиентом).
- (B) Reconciler генерирует псевдослучайный IP из CIDR подсети (cross-service: надо знать CIDR из vpc).
- (C) Reconciler присваивает статически предопределённый IP (например, `10.0.0.X` где X = hash(uid) % 250 + 2).

*Вопрос:* В 0.4 нет реального IPAM — предлагается вариант C (детерминированный псевдо-IP). Подтвердить.

**OQ-5. Image catalog versioning в List**

`ImageService/List` возвращает `resourceVersion` как snapshot-version. Поскольку Images — read-only seed без runtime-изменений, `resourceVersion` для Images может не иметь смысла. Вопрос: нужен ли `Watch` на Images? Сценарий A5 фиксирует отсутствие Watch у ImageService. Подтвердить, что это намеренное решение.

**OQ-6. Restart RPC: что возвращается в ответе?**

Спецификация говорит: «сервер выставляет `metadata.restartedAt = now()`». Вопрос: `InstanceRestartResponse` возвращает полный объект Instance (с обновлённым `metadata.restartedAt`) или только `metadata`? Предлагается возвращать полный Instance — единообразно с другими мутирующими RPC.

**OQ-7. Поведение reconciler при накопленных переходах (desiredPowerState меняется несколько раз подряд)**

Instance RUNNING → desiredPowerState=STOPPED (reconciler начал STOPPING) → через 2 с клиент меняет обратно desiredPowerState=RUNNING. Reconciler в данный момент в середине STOPPING. Варианты:
- (A) Reconciler завершает текущий переход (→ STOPPED), затем на следующем цикле начинает STARTING → RUNNING.
- (B) Reconciler прерывает текущий переход (сложнее, требует cancellation).

*Вопрос:* Подтвердить вариант A (проще, достаточно для control plane симуляции).

---

**После approve этого документа:**
- Конвертация сценариев в тесты — задача субагента `integration-tester`.
- План реализации — `kacho-workspace/docs/plans/sub-phase-0.4-compute-plan.md` (через `superpowers:writing-plans`), каждый шаг плана ссылается на ID сценариев из этого документа.
- Proto-контракт `kacho-proto/proto/kacho/cloud/compute/v1/` проверяет субагент `proto-api-reviewer` после реализации.
- Схема миграций `kacho_compute` проверяет субагент `db-architect-reviewer` после реализации.
- Clean Architecture соответствие проверяет субагент `go-style-reviewer` после реализации.
