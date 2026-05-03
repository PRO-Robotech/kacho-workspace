# Sub-phase 0.5 (LoadBalancer — NLB + TargetGroup + Finalizer) — Acceptance

**Документ:** acceptance / sub-phase 0.5
**Дата:** 2026-05-03
**Статус:** Draft, раунд 2 (включены замечания acceptance-reviewer раунда 1)
**Источник требований:** `04-roadmap-and-phasing.md` §3 «Sub-итерация 0.5»; `01-architecture-and-services.md` §2.5, §5; `02-data-model-and-conventions.md` §2, §4, §6, §7, §9, §10, §14; `00-overview-and-scope.md`.
**Утверждение:** approve выставляет агент `acceptance-reviewer` (заказчик не подключается — он проверяет финальный smoke на шаге 7, см. `04-roadmap-and-phasing.md` §2).

---

## 0. Цель sub-итерации (1 абзац)

Sub-итерация 0.5 реализует сервис `kacho-loadbalancer` — control plane L4 Network Load Balancer — с асинхронным reconciler-ом, симулирующим жизненный цикл `NetworkLoadBalancer` (CREATING → ACTIVE, задержка 5–15 с) и синхронным переходом `TargetGroup` (CREATING → READY, без задержки). Сервис охватывает два ресурса: `NetworkLoadBalancer` (listeners + attachedTargetGroups как inline JSONB в spec) и `TargetGroup` (targets: subnet + address/instanceId). Reconciler координирует обработку между репликами через `pg_advisory_lock(uid_hash)`. Сервис выполняет cross-service gRPC-вызовы: loadbalancer → resource-manager (`FolderExists`), loadbalancer → vpc (`SubnetExists`), loadbalancer → compute (`InstanceExists`). Finalizer `loadbalancer.kacho.io/target-deregister` размещается **на Instance** (в `kacho-compute`) и обеспечивает удаление instance из всех TargetGroup перед физическим уничтожением Instance. API Gateway (sub-phase 0.6) **не существует** в данной итерации: все e2e-сценарии используют `kubectl port-forward`.

**Что НЕ входит в 0.5** (явно отложено):

- `kacho-api-gateway` и REST-mux — sub-phase 0.6.
- Реальный data plane (выделение IP на NLB, healthcheck-проверки бэкендов) — нет data plane по всей платформе.
- TargetGroup с targets cross-subnet (несколько subnetId внутри одной TargetGroup) — разрешено (см. OQ-2, закрыт inline).
- NLB IP-адреса (`status.external_ips`) — reconciler присваивает симулированный IP при переходе в ACTIVE (OQ-3, закрыт inline вариант B). Реальное выделение IP — нет data plane.
- AAA (auth, authorization, audit) — отдельная фаза.
- Пагинация глубже 1000 — зарезервирована архитектурно.

**Зафиксированные соглашения:**

- `ALREADY_EXISTS` не используется: upsert-семантика (`name + folderId` → create-or-update).
- `status` пишется **только** через `Internal.UpdateStatus` — запрет #6. Попытка передать `status` в `/upsert` возвращает `INVALID_ARGUMENT`.
- Симулированные задержки: NLB CREATING → ACTIVE: 5–15 с. TargetGroup CREATING → READY: мгновенно (синхронно в handler, без reconciler-а для TargetGroup).
- Изменение `spec` NLB: переход `ACTIVE → UPDATING → ACTIVE` с задержкой 5–15 с.
- `attachedTargetGroups[]` в spec NLB — **full-replace семантика**: при каждом Upsert список полностью перезаписывается.
- Finalizer `loadbalancer.kacho.io/target-deregister` добавляется **compute-сервисом** автоматически при создании Instance (аналогично `compute.kacho.io/disk-detach`). Compute читает finalizer через Internal RPC от loadbalancer при удалении Instance.
- Internal RPC `TargetGroupInternalService.RemoveTarget(instanceId)` вызывается из **compute-reconciler** (при обработке finalizer `loadbalancer.kacho.io/target-deregister`). Loadbalancer удаляет все targets с matching `instance_id` из всех TargetGroup.
- **Имена integration-тест-функций** следуют паттерну `Test<Resource>_<ScenarioID>_<ShortDesc>` (например, `TestTargetGroup_B1_UpsertWithTargets`). E2e bash-скрипты — `kacho-deploy/e2e/0.5/<ID>-<short-desc>.sh`.
- Все временны́е assertion-ы используют таймаут 60 секунд (4× максимальной симулированной задержки).

---

## 1. Группа A — kacho-proto/loadbalancer/v1 contracts

Сценарии группы A проверяют корректность proto-контрактов `kacho-proto/proto/kacho/cloud/loadbalancer/v1/`. Тесты — `buf lint` и `buf breaking` в CI kacho-proto.

> **Трассировка:** A1–A5 реализуются через шаги CI-пайплайна `kacho-proto/.github/workflows/ci.yaml`: `buf lint`, `buf breaking`, `buf generate` (проверка отсутствия диффа в `gen/`). Эти сценарии не имеют Go-функций вида `TestXxx` — они покрыты CI-шагами, а не unit-тестами.

### A1. buf lint проходит без предупреждений

**ID:** 0.5-A1

**Given** файлы `kacho-proto/proto/kacho/cloud/loadbalancer/v1/` содержат:
- `network_load_balancer.proto`
- `target_group.proto`
- `internal.proto`

**When** выполняется `buf lint proto/kacho/cloud/loadbalancer/v1/` в репо `kacho-proto`

**Then** команда завершается с кодом 0
**And** нет предупреждений о нарушении naming, field numbering, field type conventions
**And** package declaration во всех файлах — `package kacho.cloud.loadbalancer.v1;`
**And** go_package option — `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/loadbalancer/v1`

### A2. buf breaking не регрессирует после изменений

**ID:** 0.5-A2

**Given** в ветке `main` kacho-proto уже есть baseline с baseline-версией proto
**And** разработчик добавляет новое optional-поле в `NetworkLoadBalancer.Spec`

**When** выполняется `buf breaking --against 'https://github.com/PRO-Robotech/kacho-proto.git#branch=main'`

**Then** команда завершается с кодом 0 (добавление optional-поля — обратно совместимо)
**And** если поле удалено или его тип изменён — команда завершается с ненулевым кодом

### A3. proto NetworkLoadBalancer содержит обязательные RPC и message-типы

**ID:** 0.5-A3

**Given** файл `network_load_balancer.proto` скомпилирован

**When** разработчик проверяет сгенерированный Go-код в `gen/go/kacho/cloud/loadbalancer/v1/`

**Then** присутствуют типы:
- `NetworkLoadBalancerService` с методами `Upsert`, `Delete`, `List`, `Watch`
- `NetworkLoadBalancer` message с полями `metadata`, `spec`, `status`
- `NetworkLoadBalancerUpsertRequest` / `NetworkLoadBalancerUpsertResponse`
- `NetworkLoadBalancerDeleteRequest` / `NetworkLoadBalancerDeleteResponse`
- `NetworkLoadBalancerListRequest` / `NetworkLoadBalancerListResponse`
- `NetworkLoadBalancerWatchRequest`, `NetworkLoadBalancerWatchEvent` (server-streaming)
- `NetworkLoadBalancer.Spec` с полями:
  - `display_name string`
  - `description string`
  - `region_id string`
  - `listeners[]` (Listener: `name string`, `port int32`, `protocol` enum `TCP|UDP`)
  - `attached_target_groups[]` (AttachedTargetGroup: `target_group_id string`)
- `NetworkLoadBalancer.Status` с полями:
  - `state` enum: `CREATING`, `ACTIVE`, `UPDATING`, `ERROR`, `DELETING`
  - `state_last_transition_at` timestamp
  - `external_ips[]` (strings, может быть пустым; reconciler выставляет симулированный IP при ACTIVE)
  - `observed_generation int64` (reconciler записывает `metadata.generation` в момент завершения перехода; используется в J4 как сигнал pending update)
  - `conditions[]`

### A4. proto TargetGroup содержит обязательные RPC и message-типы

**ID:** 0.5-A4

**Given** файл `target_group.proto` скомпилирован

**When** разработчик проверяет сгенерированный Go-код

**Then** присутствуют типы:
- `TargetGroupService` с методами `Upsert`, `Delete`, `List`, `Watch`
- `TargetGroup` message с полями `metadata`, `spec`, `status`
- `TargetGroup.Spec` с полями:
  - `display_name string`
  - `description string`
  - `targets[]` (Target: `subnet_id string`, `address string` (IP), `instance_id string` (опционально))
- `TargetGroup.Status` с полями:
  - `state` enum: `CREATING`, `READY`, `UPDATING`, `DELETING`
  - `state_last_transition_at` timestamp
  - `observed_generation int64` (handler выставляет при синхронном переходе в READY)

### A5. proto internal.proto содержит Internal-методы loadbalancer

**ID:** 0.5-A5

**Given** файл `internal.proto` скомпилирован

**When** разработчик проверяет сгенерированный Go-код

**Then** присутствует сервис `LoadBalancerInternal` с методами:
- `NetworkLoadBalancerExists(req: {uid string}) → {exists: bool}`
- `TargetGroupExists(req: {uid string}) → {exists: bool}`
- `UpdateNetworkLoadBalancerStatus(req)` — reconciler пишет status NLB
- `UpdateTargetGroupStatus(req)` — reconciler пишет status TargetGroup
- `RemoveTarget(req: {instance_id string}) → {}` — compute вызывает при finalizer-cleanup; удаляет все targets с matching instance_id из всех TargetGroup

---

## 2. Группа B — TargetGroup domain (Upsert / Delete / List / Watch + lifecycle CREATING→READY)

### B1. Upsert: создание нового TargetGroup с targets

**ID:** 0.5-B1

**Given** Folder `default` с `uid = <folder-uid>` существует в resource-manager
**And** Subnet `<subnet-uid>` существует в vpc
**And** Instance `<instance-uid>` с `uid = <instance-uid>` существует в compute

**When** клиент вызывает `kacho.cloud.loadbalancer.v1.TargetGroupService/Upsert` с payload:
- `target_groups[0].metadata.name = "my-tg-01"`
- `target_groups[0].metadata.folder_id = <folder-uid>`
- `target_groups[0].spec.targets[0].subnet_id = <subnet-uid>`
- `target_groups[0].spec.targets[0].address = "10.0.0.10"`
- `target_groups[0].spec.targets[0].instance_id = <instance-uid>`

**Then** ответ содержит `target_groups[0]` с заполненными:
- `metadata.uid` — непустой UUID v4
- `metadata.name = "my-tg-01"`
- `metadata.folder_id = <folder-uid>`
- `metadata.creation_timestamp` — не нулевое время
- `metadata.resource_version` — непустая строка с десятичным числом > 0
- `metadata.generation = 1`
**And** `status.state = "READY"` (TargetGroup переходит в READY синхронно)
**And** в БД `kacho_loadbalancer.target_groups` присутствует запись с `name = 'my-tg-01'`
**And** в `resource_events` есть событие `event_type = 'ADDED'`, `resource_kind = 'TargetGroup'`
**And** gRPC статус = OK

### B2. TargetGroup lifecycle: CREATING → READY синхронно (без reconciler-задержки)

**ID:** 0.5-B2

**Given** Folder `<folder-uid>`, Subnet `<subnet-uid>` существуют

**When** клиент вызывает `TargetGroupService/Upsert` для создания нового TargetGroup

**Then** в первом же ответе `status.state = "READY"` (handler сразу выставляет через `UpdateTargetGroupStatus`)
**And** в `resource_events` первое событие имеет `event_type = 'ADDED'` (не два отдельных события ADDED + MODIFIED для перехода CREATING→READY)
**And** `status.state_last_transition_at` заполнен

*Обоснование:* TargetGroup не требует reconciler-задержки — переход синхронный, аналогично VPC-ресурсам.

### B3. Upsert TargetGroup: идемпотентность (no-diff → no event)

**ID:** 0.5-B3

**Given** TargetGroup `"my-tg-01"` существует с `metadata.resource_version = <R>`

**When** клиент вызывает `TargetGroupService/Upsert` с тем же payload (те же `name`, `spec`, `folder_id`)

**Then** ответ содержит тот же `metadata.uid`
**And** handler сравнивает JSONB текущего spec в БД с новым spec запроса; если байты идентичны — UPDATE не выполняется, `resource_version` остаётся равным `<R>`
**And** в `resource_events` новых событий для данного uid не появилось

### B4. Upsert TargetGroup: обновление spec (изменение targets) → UPDATING → READY

**ID:** 0.5-B4

**Given** TargetGroup `"my-tg-01"` существует в состоянии `READY`
**And** `spec.targets[0].address = "10.0.0.10"`
**And** Watch стрим `TargetGroupService/Watch` открыт

**When** клиент вызывает `TargetGroupService/Upsert` с:
- `spec.targets[0].address = "10.0.0.10"` (прежний)
- `spec.targets[1].subnet_id = <subnet-uid>`, `spec.targets[1].address = "10.0.0.20"` (новый target добавлен)

**Then** ответ — OK, `metadata.resource_version` возрос, `metadata.generation` возрос
**And** `status.state = "READY"` (обновление TargetGroup тоже синхронное)
**And** Watch стрим получает событие `MODIFIED` с обновлёнными `spec.targets`

### B5. TargetGroup List: фильтр по folderId

**ID:** 0.5-B5

**Given** Существуют 3 TargetGroup: два с `folder_id = <folder-a>`, один с `folder_id = <folder-b>`

**When** клиент вызывает `TargetGroupService/List` с:
- `selectors[0].field_selector.folder_id = <folder-a>`

**Then** ответ содержит ровно 2 TargetGroup
**And** TargetGroup из `<folder-b>` не включена

### B6. Delete TargetGroup: мягкое удаление, finalizers пусты → физическое удаление

**ID:** 0.5-B6

**Given** TargetGroup `"my-tg-01"` существует в состоянии `READY`
**And** `metadata.finalizers[] = []` (нет finalizers)
**And** TargetGroup **не присоединена** ни к одному NLB

**When** клиент вызывает `TargetGroupService/Delete` с `target_groups[0].metadata.uid = <tg-uid>`

**Then** ответ — OK
**And** TargetGroup физически удалена из БД (finalizers пусты — удаление в той же транзакции)
**And** Watch стрим получает `DELETED` для данного TargetGroup

### B7. Delete TargetGroup, присоединённой к NLB — FAILED_PRECONDITION

**ID:** 0.5-B7

**Given** TargetGroup `"my-tg-01"` присоединена к NetworkLoadBalancer `"my-nlb-01"` через same-DB FK (запись в `network_load_balancers.spec.attached_target_groups` ссылается на `<tg-uid>`)

**When** клиент вызывает `TargetGroupService/Delete` с `target_groups[0].metadata.uid = <tg-uid>`

**Then** gRPC статус = `FAILED_PRECONDITION`
**And** `details[]` содержит `PreconditionFailure` с `violations[0].type = "TARGET_GROUP_IN_USE"`, `violations[0].subject = <tg-uid>`
**And** `violations[0].description` указывает `attached_to_nlb = <nlb-uid>`
**And** TargetGroup НЕ удалена

---

## 3. Группа C — TargetGroup target validation (cross-service vpc Subnet, compute Instance)

### C1. Upsert TargetGroup с несуществующим subnetId — NOT_FOUND

**ID:** 0.5-C1

**Given** Folder `<folder-uid>` существует
**And** Subnet с `uid = "00000000-0000-0000-0000-000000000001"` НЕ существует в vpc
**And** gRPC-вызов `VpcInternal/SubnetExists` возвращает `{exists: false}`

**When** клиент вызывает `TargetGroupService/Upsert` с:
- `target_groups[0].spec.targets[0].subnet_id = "00000000-0000-0000-0000-000000000001"`

**Then** gRPC статус = `NOT_FOUND`
**And** `details[]` содержит `ResourceInfo.resource_type = "Subnet"`, `resource_name = "00000000-0000-0000-0000-000000000001"`
**And** TargetGroup НЕ создана в БД

### C2. Upsert TargetGroup с несуществующим instanceId — NOT_FOUND

**ID:** 0.5-C2

**Given** Folder `<folder-uid>`, Subnet `<subnet-uid>` существуют
**And** Instance с `uid = "00000000-0000-0000-0000-000000000002"` НЕ существует в compute
**And** gRPC-вызов `ComputeInternal/InstanceExists` возвращает `{exists: false}`

**When** клиент вызывает `TargetGroupService/Upsert` с:
- `target_groups[0].spec.targets[0].subnet_id = <subnet-uid>`
- `target_groups[0].spec.targets[0].address = "10.0.0.5"`
- `target_groups[0].spec.targets[0].instance_id = "00000000-0000-0000-0000-000000000002"`

**Then** gRPC статус = `NOT_FOUND`
**And** `details[]` содержит `ResourceInfo.resource_type = "Instance"`, `resource_name = "00000000-0000-0000-0000-000000000002"`
**And** TargetGroup НЕ создана в БД

### C3. Upsert TargetGroup: targets с address без instanceId — OK (instanceId опционален)

**ID:** 0.5-C3

**Given** Folder `<folder-uid>`, Subnet `<subnet-uid>` существуют

**When** клиент вызывает `TargetGroupService/Upsert` с:
- `target_groups[0].spec.targets[0].subnet_id = <subnet-uid>`
- `target_groups[0].spec.targets[0].address = "10.0.0.7"`
- (instance_id не указан)

**Then** gRPC статус = OK
**And** TargetGroup создана с `spec.targets[0].instance_id = ""` (пусто)
**And** `status.state = "READY"`

### C4. Upsert TargetGroup: targets без address и без instanceId — INVALID_ARGUMENT

**ID:** 0.5-C4

**Given** Folder `<folder-uid>`, Subnet `<subnet-uid>` существуют

**When** клиент вызывает `TargetGroupService/Upsert` с:
- `target_groups[0].spec.targets[0].subnet_id = <subnet-uid>`
- (address пустой, instance_id пустой)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "target_groups[0].spec.targets[0].address"`
**And** описание уточняет: хотя бы одно из `address` или `instance_id` должно быть указано

### C5. Cross-service: loadbalancer → vpc SubnetExists — vpc UNAVAILABLE

**ID:** 0.5-C5

**Given** Сервис `kacho-vpc` недоступен (имитируется в integration-тесте)
**And** Folder `<folder-uid>` существует

**When** клиент вызывает `TargetGroupService/Upsert` с `targets[0].subnet_id = <subnet-uid>`

**Then** gRPC статус = `UNAVAILABLE`
**And** `details[]` содержит `RequestInfo` с непустым `request_id`
**And** TargetGroup НЕ создана в БД

### C6. Cross-service: loadbalancer → compute InstanceExists — compute UNAVAILABLE

**ID:** 0.5-C6

**Given** Сервис `kacho-compute` недоступен
**And** Folder `<folder-uid>`, Subnet `<subnet-uid>` существуют

**When** клиент вызывает `TargetGroupService/Upsert` с `targets[0].instance_id = <instance-uid>` (указан instanceId)

**Then** gRPC статус = `UNAVAILABLE`
**And** TargetGroup НЕ создана в БД

---

## 4. Группа D — NetworkLoadBalancer domain (Upsert / Delete / List / Watch)

### D1. Upsert: создание нового NLB с listeners и attachedTargetGroups

**ID:** 0.5-D1

**Given** Folder `default` с `uid = <folder-uid>` существует
**And** TargetGroup `"my-tg-01"` с `uid = <tg-uid>` существует в `kacho_loadbalancer`

**When** клиент вызывает `kacho.cloud.loadbalancer.v1.NetworkLoadBalancerService/Upsert` с payload:
- `network_load_balancers[0].metadata.name = "my-nlb-01"`
- `network_load_balancers[0].metadata.folder_id = <folder-uid>`
- `network_load_balancers[0].spec.region_id = "kacho-region-a"`
- `network_load_balancers[0].spec.listeners[0].name = "http"`
- `network_load_balancers[0].spec.listeners[0].port = 80`
- `network_load_balancers[0].spec.listeners[0].protocol = "TCP"`
- `network_load_balancers[0].spec.attached_target_groups[0].target_group_id = <tg-uid>`

**Then** ответ содержит `network_load_balancers[0]` с заполненными:
- `metadata.uid` — непустой UUID v4
- `metadata.name = "my-nlb-01"`
- `metadata.folder_id = <folder-uid>`
- `metadata.creation_timestamp` — не нулевое время
- `metadata.resource_version` — непустая строка с десятичным числом > 0
- `metadata.generation = 1`
**And** `status.state = "CREATING"` в первом ответе (reconciler ещё не запустил переход)
**And** в БД `kacho_loadbalancer.network_load_balancers` присутствует запись с `name = 'my-nlb-01'`
**And** в `resource_events` есть событие `event_type = 'ADDED'`, `resource_kind = 'NetworkLoadBalancer'`
**And** gRPC статус = OK

### D2. Upsert NLB: идемпотентность (no-diff → no event)

**ID:** 0.5-D2

**Given** NLB `"my-nlb-01"` существует в состоянии `ACTIVE` с `metadata.resource_version = <R>`

**When** клиент вызывает `NetworkLoadBalancerService/Upsert` с тем же payload (те же `name`, `spec`, `folder_id`)

**Then** ответ содержит тот же `metadata.uid`
**And** handler сравнивает JSONB текущего spec в БД с новым spec запроса; если байты идентичны — UPDATE не выполняется, `resource_version` остаётся равным `<R>`
**And** в `resource_events` новых событий для данного uid не появилось

### D3. NLB List: фильтр по folderId

**ID:** 0.5-D3

**Given** Существуют 3 NLB: два с `folder_id = <folder-a>`, один с `folder_id = <folder-b>`

**When** клиент вызывает `NetworkLoadBalancerService/List` с:
- `selectors[0].field_selector.folder_id = <folder-a>`

**Then** ответ содержит ровно 2 NLB
**And** NLB из `<folder-b>` не включён

### D4. Delete NLB: мягкое удаление — ACTIVE → DELETING → физическое удаление

**ID:** 0.5-D4

**Given** NLB `"my-nlb-01"` существует в состоянии `ACTIVE`
**And** `metadata.finalizers[] = []`
**And** Watch стрим `NetworkLoadBalancerService/Watch` открыт

**When** клиент вызывает `NetworkLoadBalancerService/Delete` с `network_load_balancers[0].metadata.uid = <nlb-uid>`

**Then** ответ — OK, `metadata.deletion_timestamp` выставлен
**And** Watch стрим получает `MODIFIED` с `metadata.deletion_timestamp != null` и `status.state = "DELETING"`
**And** в течение 30 секунд NLB физически удаляется (reconciler завершает DELETING)
**And** Watch стрим получает финальное событие `DELETED`
**And** `NetworkLoadBalancerService/List` больше не возвращает `"my-nlb-01"`

### D5. Delete NLB в состоянии CREATING — допустимо, reconciler завершает удаление

**ID:** 0.5-D5

**Given** NLB `"my-nlb-02"` существует в состоянии `CREATING`
**And** Reconciler ещё не завершил переход в `ACTIVE`

**When** клиент вызывает `NetworkLoadBalancerService/Delete`

**Then** ответ — OK, `metadata.deletion_timestamp` выставлен
**And** Reconciler обнаруживает `deletion_timestamp IS NOT NULL` и переходит к DELETING вместо ACTIVE
**And** Watch стрим получает `DELETED` в течение 30 секунд

### D6. Delete NLB: повторное удаление уже soft-deleted NLB — OK (идемпотентно)

**ID:** 0.5-D6

**Given** NLB `"deleted-nlb"` уже имеет `metadata.deletion_timestamp != null` (soft-deleted, ещё не удалена физически)

**When** клиент повторно вызывает `NetworkLoadBalancerService/Delete` с `uid = <nlb-uid>`

**Then** gRPC статус = OK (идемпотентный ответ: сервер обнаруживает, что deletion_timestamp уже выставлен, и возвращает OK без изменений)
**And** `metadata.deletion_timestamp` не изменяется (остаётся первоначальным значением)
**And** в `resource_events` новых событий не появляется

*Примечание (lock variant — OK idempotent):* подход улучшает UX по сравнению с `NOT_FOUND` / `FAILED_PRECONDITION` — клиент не обязан различать «ещё не удалена» и «уже удалена».

---

## 5. Группа E — NLB lifecycle (CREATING → ACTIVE; UPDATING → ACTIVE)

### E1. NLB lifecycle: CREATING → ACTIVE с симулированной задержкой

**ID:** 0.5-E1

**Given** NLB `"my-nlb-01"` создан (D1), `status.state = "CREATING"`
**And** Watch стрим `NetworkLoadBalancerService/Watch` открыт
**And** Reconciler запущен

**When** ожидается в течение 60 секунд

**Then** Watch стрим получает событие `MODIFIED` с `status.state = "ACTIVE"` в течение 60 секунд
**And** переход занимает от 5 до 15 секунд (в пределах симулированного диапазона)
**And** `status.state_last_transition_at` > `metadata.creation_timestamp`
**And** `metadata.resource_version` в финальном ACTIVE-событии > resourceVersion при создании
**And** `status.external_ips` содержит как минимум один IPv4-элемент (reconciler выставляет симулированный IP при переходе CREATING → ACTIVE, например из диапазона `10.255.X.X`)
**And** `status.observed_generation = metadata.generation`

### E2. NLB lifecycle: обновление spec → ACTIVE → UPDATING → ACTIVE

**ID:** 0.5-E2

**Given** NLB `"my-nlb-01"` находится в состоянии `ACTIVE`
**And** Watch стрим `NetworkLoadBalancerService/Watch` открыт

**When** клиент вызывает `NetworkLoadBalancerService/Upsert` с изменённым spec:
- `spec.listeners[1].name = "https"`
- `spec.listeners[1].port = 443`
- `spec.listeners[1].protocol = "TCP"` (добавлен новый listener)

**Then** ответ — OK, `metadata.resource_version` возрос, `metadata.generation` возрос
**And** `status.state = "UPDATING"` в ответе Upsert (или Watch выдаёт MODIFIED с UPDATING в течение 2 с)
**And** в течение 60 секунд Watch стрим получает событие `MODIFIED` с `status.state = "ACTIVE"`
**And** переход UPDATING → ACTIVE занимает от 5 до 15 секунд

### E3. NLB lifecycle: множественные rapid Upsert (изменения spec) — reconciler идемпотентен

**ID:** 0.5-E3

**Given** NLB `"my-nlb-01"` находится в состоянии `ACTIVE`

**When** клиент вызывает `NetworkLoadBalancerService/Upsert` три раза подряд с разными listeners

**Then** NLB в итоге переходит в `ACTIVE` ровно один раз после последнего изменения
**And** `spec` NLB отражает последнее записанное состояние (last-write-wins)
**And** В `resource_events` нет паразитных дублей MODIFIED

---

## 6. Группа F — NLB attachedTargetGroups (FK-валидация; full-replace; cascade-поведение)

### F1. Upsert NLB с несуществующим targetGroupId — INVALID_ARGUMENT

**ID:** 0.5-F1

**Given** Folder `<folder-uid>` существует
**And** TargetGroup с `uid = "00000000-0000-0000-0000-000000000010"` НЕ существует в `kacho_loadbalancer`

**When** клиент вызывает `NetworkLoadBalancerService/Upsert` с:
- `spec.attached_target_groups[0].target_group_id = "00000000-0000-0000-0000-000000000010"`

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "network_load_balancers[0].spec.attached_target_groups[0].target_group_id"`
**And** NLB НЕ создана / не обновлена в БД

*Обоснование:* `attached_target_groups` валидируется через same-DB FK (не cross-service). Если FK нарушен — `INVALID_ARGUMENT` (ссылка на несуществующий ресурс той же БД), а не `NOT_FOUND`.

### F2. Upsert NLB: full-replace semantics для attachedTargetGroups

**ID:** 0.5-F2

**Given** NLB `"my-nlb-01"` в состоянии `ACTIVE` с:
- `spec.attached_target_groups = [{target_group_id: <tg-a>}, {target_group_id: <tg-b>}]`

**When** клиент вызывает `NetworkLoadBalancerService/Upsert` с:
- `spec.attached_target_groups = [{target_group_id: <tg-c>}]` (только tg-c, tg-a и tg-b убраны)

**Then** ответ — OK, `metadata.resource_version` возрос
**And** в БД `spec.attached_target_groups` содержит **только** `<tg-c>` (full-replace, tg-a и tg-b удалены)
**And** Watch стрим получает `MODIFIED` с обновлённым spec

### F3. Upsert NLB: пустой attachedTargetGroups — допустимо

**ID:** 0.5-F3

**Given** Folder `<folder-uid>` существует

**When** клиент вызывает `NetworkLoadBalancerService/Upsert` с:
- `spec.attached_target_groups = []` (пустой список)
- `spec.listeners[0].name = "http"`, `spec.listeners[0].port = 80`, `spec.listeners[0].protocol = "TCP"`

**Then** gRPC статус = OK
**And** NLB создана с `spec.attached_target_groups = []`
**And** Reconciler переводит NLB в `ACTIVE` (NLB без target groups — валидный объект)

### F4. Upsert NLB: attachedTargetGroups указывает на TargetGroup другого Folder — INVALID_ARGUMENT

**ID:** 0.5-F4

**Given** NLB создаётся в `folder_id = <folder-a>`
**And** TargetGroup `<tg-b-uid>` существует в `folder_id = <folder-b>` (другой Folder)

**When** клиент вызывает `NetworkLoadBalancerService/Upsert` с:
- `metadata.folder_id = <folder-a>`
- `spec.attached_target_groups[0].target_group_id = <tg-b-uid>`

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "network_load_balancers[0].spec.attached_target_groups[0].target_group_id"`
**And** описание уточняет: TargetGroup и NLB должны принадлежать одному folder

---

## 7. Группа G — Cross-service validation (loadbalancer → resource-manager, vpc, compute)

### G1. Upsert NLB с несуществующим folderId — NOT_FOUND (cross-service: resource-manager)

**ID:** 0.5-G1

**Given** Folder с `uid = "00000000-0000-0000-0000-000000000020"` НЕ существует в resource-manager
**And** gRPC-вызов `ResourceManagerInternal/FolderExists` возвращает `{exists: false}`

**When** клиент вызывает `NetworkLoadBalancerService/Upsert` с:
- `network_load_balancers[0].metadata.folder_id = "00000000-0000-0000-0000-000000000020"`

**Then** gRPC статус = `NOT_FOUND`
**And** `details[]` содержит `ResourceInfo.resource_type = "Folder"`, `resource_name = "00000000-0000-0000-0000-000000000020"`
**And** NLB НЕ создана в БД

### G2. Upsert TargetGroup с несуществующим folderId — NOT_FOUND (cross-service: resource-manager)

**ID:** 0.5-G2

**Given** Folder с `uid = "00000000-0000-0000-0000-000000000021"` НЕ существует

**When** клиент вызывает `TargetGroupService/Upsert` с:
- `target_groups[0].metadata.folder_id = "00000000-0000-0000-0000-000000000021"`

**Then** gRPC статус = `NOT_FOUND`
**And** `details[]` содержит `ResourceInfo.resource_type = "Folder"`
**And** TargetGroup НЕ создана в БД

### G3. Cross-service: loadbalancer → resource-manager FolderExists — ресурс-менеджер UNAVAILABLE

**ID:** 0.5-G3

**Given** Сервис `kacho-resource-manager` недоступен (имитируется отключением в integration-тесте)

**When** клиент вызывает `NetworkLoadBalancerService/Upsert` с `folder_id = <valid-looking-folder-uid>`

**Then** gRPC статус = `UNAVAILABLE`
**And** `details[]` содержит `RequestInfo` с непустым `request_id`
**And** NLB НЕ создана в БД

### G4. Cross-service: loadbalancer → resource-manager FolderExists — ресурс-менеджер UNAVAILABLE при Upsert TargetGroup

**ID:** 0.5-G4

**Given** Сервис `kacho-resource-manager` недоступен

**When** клиент вызывает `TargetGroupService/Upsert` с `folder_id = <valid-looking-folder-uid>`

**Then** gRPC статус = `UNAVAILABLE`
**And** TargetGroup НЕ создана в БД

---

## 8. Группа H — Internal RPC (NLBExists, TargetGroupExists, RemoveTarget)

### H1. LoadBalancerInternal.NetworkLoadBalancerExists: существующий NLB → exists=true

**ID:** 0.5-H1

**Given** NLB `"my-nlb-01"` с `uid = <nlb-uid>` существует в `ACTIVE`

**When** вызывается `kacho.cloud.loadbalancer.v1.LoadBalancerInternal/NetworkLoadBalancerExists` с `uid = <nlb-uid>`

**Then** ответ: `{exists: true}`
**And** gRPC статус = OK

### H2. LoadBalancerInternal.NetworkLoadBalancerExists: несуществующий NLB → exists=false

**ID:** 0.5-H2

**Given** NLB с `uid = "00000000-0000-0000-0000-000000000030"` НЕ существует

**When** вызывается `LoadBalancerInternal/NetworkLoadBalancerExists` с `uid = "00000000-0000-0000-0000-000000000030"`

**Then** ответ: `{exists: false}`
**And** gRPC статус = OK

### H3. LoadBalancerInternal.TargetGroupExists: существующий TargetGroup → exists=true

**ID:** 0.5-H3

**Given** TargetGroup `"my-tg-01"` с `uid = <tg-uid>` существует

**When** вызывается `LoadBalancerInternal/TargetGroupExists` с `uid = <tg-uid>`

**Then** ответ: `{exists: true}`
**And** gRPC статус = OK

### H4. LoadBalancerInternal.TargetGroupExists: TargetGroup с deletionTimestamp → exists=false

**ID:** 0.5-H4

**Given** TargetGroup `"my-tg-old"` с `uid = <tg-uid>` имеет `deletion_timestamp != NULL` (soft-deleted)

**When** вызывается `LoadBalancerInternal/TargetGroupExists` с `uid = <tg-uid>`

**Then** ответ: `{exists: false}`
**And** gRPC статус = OK

*Обоснование:* TargetGroup в процессе удаления не должна рассматриваться как валидная ссылка для новых NLB.

### H5. LoadBalancerInternal.RemoveTarget: удаление всех targets с matching instanceId

**ID:** 0.5-H5

**Given** TargetGroup `"tg-with-instance"` содержит два targets:
- `targets[0].instance_id = <instance-uid>`, `targets[0].address = "10.0.0.5"`
- `targets[1].instance_id = <other-instance-uid>`, `targets[1].address = "10.0.0.6"`
**And** TargetGroup `"tg-also-with-instance"` содержит один target:
- `targets[0].instance_id = <instance-uid>`, `targets[0].address = "10.0.0.7"`

**When** вызывается `LoadBalancerInternal/RemoveTarget` с `instance_id = <instance-uid>`

**Then** gRPC статус = OK
**And** В БД: из `"tg-with-instance"` удалён `targets[0]` (с matching instance_id), `targets[1]` остался
**And** В БД: из `"tg-also-with-instance"` удалён единственный target
**And** Watch стрим получает событие `MODIFIED` для обеих TargetGroup (обновлён spec)
**And** `metadata.resource_version` обеих TargetGroup возрос

### H6. LoadBalancerInternal.RemoveTarget: instanceId не фигурирует ни в одном TargetGroup — no-op

**ID:** 0.5-H6

**Given** Ни одна TargetGroup не содержит `targets[].instance_id = "00000000-0000-0000-0000-000000000099"`

**When** вызывается `LoadBalancerInternal/RemoveTarget` с `instance_id = "00000000-0000-0000-0000-000000000099"`

**Then** gRPC статус = OK
**And** В `resource_events` нет новых событий (no-op, изменений нет)

### H7. LoadBalancerInternal.UpdateNetworkLoadBalancerStatus: reconciler обновляет status.state NLB

**ID:** 0.5-H7

**Given** NLB `"my-nlb-01"` с `status.state = "CREATING"` существует

**When** reconciler вызывает `LoadBalancerInternal/UpdateNetworkLoadBalancerStatus` с:
- `uid = <nlb-uid>`
- `status.state = "ACTIVE"`

**Then** в БД `network_load_balancers.status.state = "ACTIVE"`
**And** в `resource_events` событие `event_type = 'MODIFIED'`, `resource_kind = 'NetworkLoadBalancer'`
**And** `metadata.resource_version` NLB возрос

### H8. LoadBalancerInternal.UpdateNetworkLoadBalancerStatus: повторный вызов с тем же status — no-op

**ID:** 0.5-H8

**Given** NLB `"my-nlb-01"` с `status.state = "ACTIVE"`

**When** reconciler вызывает `LoadBalancerInternal/UpdateNetworkLoadBalancerStatus` с `status.state = "ACTIVE"` (нет изменений)

**Then** gRPC статус = OK
**And** В `resource_events` нет нового события для данного NLB
**And** `metadata.resource_version` не изменился

---

## 9. Группа I — Finalizer `loadbalancer.kacho.io/target-deregister` на Instance

### I1. Delete Instance с finalizer: compute вызывает RemoveTarget → finalizer снимается → Instance удаляется

**ID:** 0.5-I1

**Given** Instance `"web-vm"` с `uid = <instance-uid>` находится в состоянии `RUNNING`
**And** `metadata.finalizers[] = ["compute.kacho.io/disk-detach", "loadbalancer.kacho.io/target-deregister"]`
**And** TargetGroup `"web-tg"` содержит target с `instance_id = <instance-uid>`
**And** Watch стрим `InstanceService/Watch` открыт
**And** Watch стрим `TargetGroupService/Watch` открыт

**When** клиент вызывает `InstanceService/Delete` с `instances[0].metadata.uid = <instance-uid>`

**Then** ответ — OK (мягкое удаление: `metadata.deletion_timestamp` выставлен)
**And** Instance сразу не удалена физически (finalizers не пусты)
**And** Watch на InstanceService получает `MODIFIED` с `metadata.deletion_timestamp != null`, `status.state = "DELETING"`
**And** в течение 60 секунд compute-reconciler обрабатывает оба finalizer-а конкурентно (параллельно в двух горутинах):

  *Горутина A — `"loadbalancer.kacho.io/target-deregister"`:*
  1. Вызывает `LoadBalancerInternal/RemoveTarget` с `instance_id = <instance-uid>`
  2. Получает OK от loadbalancer
  3. Удаляет `"loadbalancer.kacho.io/target-deregister"` из `metadata.finalizers[]` прямым DB-update в той же транзакции внутри compute-сервиса (Internal RPC не нужен: compute владеет Instance напрямую)

  *Горутина B — `"compute.kacho.io/disk-detach"`:*
  1. Выполняет отвязку дисков
  2. Удаляет `"compute.kacho.io/disk-detach"` из `metadata.finalizers[]` прямым DB-update

  *После завершения обеих горутин:*
  7. `finalizers[]` пуст → Instance физически удаляется

  *Примечание (OQ-4, закрыт inline, вариант A):* finalizer-ы обрабатываются параллельно. Порядок снятия не гарантирован и не важен для control plane-only системы.
**And** Watch на TargetGroupService получает `MODIFIED` для `"web-tg"` (target с <instance-uid> удалён)
**And** Watch на InstanceService получает финальное событие `DELETED`
**And** `InstanceService/List` больше не возвращает `"web-vm"`
**And** `TargetGroupService/List` для `"web-tg"` показывает `spec.targets` без target с `instance_id = <instance-uid>`

### I2. Delete Instance: finalizer `loadbalancer.kacho.io/target-deregister`, но Instance не в любой TargetGroup — RemoveTarget no-op

**ID:** 0.5-I2

**Given** Instance `"isolated-vm"` с `uid = <instance-uid>` в состоянии `RUNNING`
**And** `metadata.finalizers[] = ["loadbalancer.kacho.io/target-deregister"]`
**And** Ни одна TargetGroup не содержит target с `instance_id = <instance-uid>`

**When** клиент вызывает `InstanceService/Delete`

**Then** compute-reconciler вызывает `LoadBalancerInternal/RemoveTarget` с `instance_id = <instance-uid>`
**And** Получает OK (no-op от loadbalancer — ничего не найдено)
**And** Finalizer удаляется, Instance физически удаляется
**And** Watch на InstanceService получает `DELETED` в течение 30 секунд

### I3. Finalizer добавляется compute при создании Instance автоматически

**ID:** 0.5-I3

**Given** sub-phase 0.5 задеплоена: оба сервиса `kacho-compute` (с обновлённым кодом) и `kacho-loadbalancer` запущены

**When** клиент вызывает `InstanceService/Upsert` для создания новой Instance (без явного указания finalizers)

**Then** в ответе `metadata.finalizers[]` содержит `"loadbalancer.kacho.io/target-deregister"`
**And** `metadata.finalizers[]` также содержит `"compute.kacho.io/disk-detach"` (добавлен ранее)
**And** Оба finalizer присутствуют с первого создания Instance

### I4. Delete Instance: loadbalancer-сервис недоступен при RemoveTarget — UNAVAILABLE, finalizer НЕ снимается

**ID:** 0.5-I4

**Given** Instance `"web-vm"` с `metadata.finalizers[] = ["loadbalancer.kacho.io/target-deregister"]`
**And** `metadata.deletion_timestamp` выставлен (мягкое удаление уже инициировано)
**And** Сервис `kacho-loadbalancer` недоступен

**When** compute-reconciler пытается выполнить finalizer-cleanup

**Then** вызов `LoadBalancerInternal/RemoveTarget` возвращает `UNAVAILABLE`
**And** compute-reconciler логирует ошибку и **не снимает** finalizer
**And** Instance остаётся в БД с `metadata.deletion_timestamp != null` и `finalizers = ["loadbalancer.kacho.io/target-deregister"]`
**And** compute-reconciler повторит попытку при следующем poll-цикле (eventual retry)

**When** Сервис `kacho-loadbalancer` восстанавливается
**And** ожидается до следующего poll-цикла reconciler (≤ 15 секунд)

**Then** compute-reconciler успешно вызывает `RemoveTarget`, снимает finalizer, Instance удаляется
**And** Watch получает финальное `DELETED` для Instance

---

## 10. Группа J — Reconciler properties (advisory lock, idempotency, recovery)

### J1. Reconciler: pg_advisory_lock предотвращает двойную обработку одного NLB

**ID:** 0.5-J1

**Given** 2 реплики `kacho-loadbalancer` запущены одновременно
**And** NLB `"contested-nlb"` в состоянии `CREATING` с `uid = <nlb-uid>`
**And** Обе реплики poll-ят одновременно

**When** Обе реплики обнаруживают `"contested-nlb"` в своём poll-запросе
**And** Обе пытаются взять `pg_advisory_lock(hashtext(<nlb-uid>))`

**Then** Только одна реплика успешно берёт lock
**And** Вторая реплика пропускает этот NLB (не может взять lock) и переходит к следующему
**And** NLB переходит в `ACTIVE` ровно один раз (нет дублей `MODIFIED (ACTIVE)` в Watch)
**And** В `resource_events` ровно одно событие `event_type = 'MODIFIED'`, `resource_kind = 'NetworkLoadBalancer'` с `status.state = 'ACTIVE'`

### J2. Reconciler: idempotent UpdateStatus — повторный вызов на уже ACTIVE NLB — no-op

**ID:** 0.5-J2

**Given** NLB `"my-nlb-01"` в состоянии `ACTIVE`
**And** Reconciler по какой-то причине повторно обрабатывает этот NLB

**When** Reconciler вызывает `LoadBalancerInternal/UpdateNetworkLoadBalancerStatus` с `status.state = "ACTIVE"` повторно

**Then** gRPC статус = OK (idempotent — H8)
**And** В `resource_events` нет нового события
**And** `metadata.resource_version` не изменился
**And** NLB остаётся в `ACTIVE` без побочных эффектов

### J3. Reconciler: recovery после сбоя сервиса — NLB в CREATING достигает ACTIVE

**ID:** 0.5-J3

**Given** NLB `"recovery-nlb"` находится в состоянии `CREATING`
**And** Сервис был убит во время обработки (имитируется записью состояния `CREATING` в БД, сервис убит)
**And** Advisory lock освобождён при завершении Postgres-сессии

**When** Сервис перезапускается и Reconciler делает первый poll

**Then** Reconciler находит NLB с `status.state = "CREATING"` (или NULL)
**And** Reconciler берёт advisory lock и выполняет симулированный переход
**And** Watch показывает `MODIFIED` с `status.state = "ACTIVE"` в течение 60 секунд
**And** NLB не застряла навсегда в `CREATING`

### J4. Reconciler: recovery — NLB в UPDATING достигает ACTIVE после рестарта

**ID:** 0.5-J4

**Given** NLB `"updating-nlb"` находится в состоянии `UPDATING` (spec изменён, reconciler начал обработку)
**And** Сервис упал в середине симулированной задержки

**When** Сервис перезапускается

**Then** Reconciler обнаруживает NLB с `status.state = "UPDATING"` и `metadata.generation > status.observed_generation` (поле `observed_generation` добавлено в `NetworkLoadBalancer.Status` — см. A3)
**And** Reconciler повторно выполняет переход UPDATING → ACTIVE
**And** NLB достигает `ACTIVE` в течение 60 секунд

### J5. Reconciler: параллельная обработка нескольких NLB в CREATING

**ID:** 0.5-J5

**Given** В БД 5 NLB одновременно в состоянии `CREATING`
**And** Reconciler использует SELECT с LIMIT для batch-обработки

**When** Reconciler делает один poll

**Then** Reconciler пытается взять `pg_advisory_lock` отдельно для каждого NLB
**And** Все 5 NLB в течение 60 секунд переходят в `ACTIVE`
**And** В `resource_events` ровно по одному `MODIFIED (ACTIVE)` для каждого NLB (без дублей)

### J6. Cleanup advisory lock: координация cleanup между reconciler-репликами

**ID:** 0.5-J6

**Given** 2 реплики сервиса `kacho-loadbalancer` запущены одновременно
**And** Cleanup горутина каждой реплики периодически пытается выполнить `DELETE FROM resource_events WHERE created_at < now() - interval '1 hour'`
**And** Обе реплики используют `pg_advisory_xact_lock(hashtext('kacho_loadbalancer_cleanup'))`

**When** Обе реплики одновременно пытаются выполнить cleanup

**Then** Только одна реплика в каждый момент выполняет cleanup
**And** Нет двойного удаления, нет deadlock

---

## 11. Группа K — Watch (ADDED/MODIFIED/DELETED для NLB и TargetGroup; lifecycle events)

### K1. Watch NLB: полный lifecycle CREATING → ACTIVE в одном стриме

**ID:** 0.5-K1

**Given** Watch стрим `NetworkLoadBalancerService/Watch` открыт с `resource_version = <текущий>` и пустым selectors
**And** Reconciler запущен

**When** клиент создаёт NLB `"watch-nlb"` с listeners и attachedTargetGroups

**Then** Watch стрим получает события в порядке:
1. `type = ADDED`, `network_load_balancer.status.state = "CREATING"`
2. `type = MODIFIED`, `network_load_balancer.status.state = "ACTIVE"` (в течение 60 с)
**And** события идут в порядке возрастания `metadata.resource_version`

### K2. Watch NLB: ACTIVE → UPDATING → ACTIVE при изменении spec

**ID:** 0.5-K2

**Given** NLB `"watch-nlb"` в состоянии `ACTIVE`
**And** Watch стрим `NetworkLoadBalancerService/Watch` открыт

**When** клиент вызывает `NetworkLoadBalancerService/Upsert` с изменённым `spec.listeners`

**Then** Watch стрим получает в порядке:
1. `type = MODIFIED`, `status.state = "UPDATING"`
2. `type = MODIFIED`, `status.state = "ACTIVE"`
**And** оба события приходят в течение 60 секунд

### K3. Watch NLB: фильтрация по folderId — клиент видит только свои ресурсы

**ID:** 0.5-K3

**Given** Watch стрим `NetworkLoadBalancerService/Watch` открыт с `selectors[0].field_selector.folder_id = <folder-a>`
**And** Существует NLB в `<folder-a>` и NLB в `<folder-b>`

**When** NLB в `<folder-b>` переходит в `ACTIVE`
**And** NLB в `<folder-a>` переходит в `ACTIVE`

**Then** Watch стрим получает только событие для NLB из `<folder-a>`
**And** Событие для NLB из `<folder-b>` не поступает в этот стрим

### K4. Watch TargetGroup: ADDED при создании, MODIFIED при обновлении targets

**ID:** 0.5-K4

**Given** Watch стрим `TargetGroupService/Watch` открыт с `resource_version = <текущий>`

**When** клиент создаёт TargetGroup `"watch-tg"` с одним target
**And** затем клиент обновляет её через Upsert (добавляет второй target)

**Then** Watch стрим получает события в порядке:
1. `type = ADDED`, `status.state = "READY"`
2. `type = MODIFIED`, обновлённый `spec.targets` (2 targets)
**And** события идут в порядке возрастания `metadata.resource_version`

### K5. Watch TargetGroup: MODIFIED при RemoveTarget (вызов из compute finalizer)

**ID:** 0.5-K5

**Given** TargetGroup `"auto-tg"` содержит target с `instance_id = <instance-uid>`
**And** Watch стрим `TargetGroupService/Watch` открыт

**When** вызывается `LoadBalancerInternal/RemoveTarget` с `instance_id = <instance-uid>`

**Then** Watch стрим получает `type = MODIFIED` для `"auto-tg"` с обновлённым `spec.targets` (target удалён)
**And** `metadata.resource_version` возрос

### K6. Watch Gone 410 при устаревшем resourceVersion

**ID:** 0.5-K6

**Given** В `resource_events` минимальная `resource_version = 5000` (старые события удалены cleanup)

**When** Watch-клиент подключается к `NetworkLoadBalancerService/Watch` с `resource_version = 100`

**Then** сервер возвращает gRPC ошибку `OUT_OF_RANGE` с message `"Gone: resourceVersion too old, please relist"`
**And** `details[]` содержит `ErrorInfo` с `reason = "RESOURCE_VERSION_EXPIRED"`
**And** `details[]` содержит `RequestInfo` с непустым `request_id`

*Примечание:* gRPC-код `OUT_OF_RANGE` используется для семантики HTTP 410 Gone (консистентно с sub-phase 0.2/0.3 acceptance). При подключении api-gateway (sub-phase 0.6) grpc-gateway маппит `OUT_OF_RANGE` → HTTP 416; HTTP 410 Gone будет явно добавлен через кастомный error mapping в api-gateway.

---

## 12. Группа L — Negative scenarios (INVALID_ARGUMENT, FAILED_PRECONDITION, ABORTED, status-in-upsert)

### L1. Upsert NLB с пустым именем — INVALID_ARGUMENT

**ID:** 0.5-L1

**Given** Folder `<folder-uid>` существует

**When** клиент вызывает `NetworkLoadBalancerService/Upsert` с:
- `network_load_balancers[0].metadata.name = ""` (пустая строка)
- `network_load_balancers[0].metadata.folder_id = <folder-uid>`

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "network_load_balancers[0].metadata.name"`

### L2. Upsert NLB: попытка задать status — INVALID_ARGUMENT

**ID:** 0.5-L2

**Given** Folder `<folder-uid>` существует

**When** клиент вызывает `NetworkLoadBalancerService/Upsert` с:
- `network_load_balancers[0].status.state = "ACTIVE"` (попытка записать status через upsert)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "network_load_balancers[0].status"`

### L3. Upsert TargetGroup: попытка задать status — INVALID_ARGUMENT

**ID:** 0.5-L3

**Given** Folder `<folder-uid>` существует

**When** клиент вызывает `TargetGroupService/Upsert` с:
- `target_groups[0].status.state = "READY"` (попытка записать status через upsert)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "target_groups[0].status"`

### L4. Upsert NLB с невалидным протоколом listener — INVALID_ARGUMENT

**ID:** 0.5-L4

**Given** Folder `<folder-uid>` существует

**When** клиент вызывает `NetworkLoadBalancerService/Upsert` с:
- `spec.listeners[0].protocol = "HTTP"` (не TCP/UDP)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "network_load_balancers[0].spec.listeners[0].protocol"`
**And** описание перечисляет допустимые значения: `TCP`, `UDP`

### L5. Upsert NLB с портом вне допустимого диапазона — INVALID_ARGUMENT

**ID:** 0.5-L5

**Given** Folder `<folder-uid>` существует

**When** клиент вызывает `NetworkLoadBalancerService/Upsert` с:
- `spec.listeners[0].port = 0` (за пределами диапазона 1–65535)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "network_load_balancers[0].spec.listeners[0].port"`

### L6. Upsert NLB без listeners — INVALID_ARGUMENT

**ID:** 0.5-L6

**Given** Folder `<folder-uid>` существует

**When** клиент вызывает `NetworkLoadBalancerService/Upsert` с:
- `spec.listeners = []` (пустой список)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "network_load_balancers[0].spec.listeners"`
**And** описание указывает: требуется хотя бы один listener

### L7. Delete NLB: несуществующий uid — NOT_FOUND

**ID:** 0.5-L7

**Given** NLB с `uid = "00000000-0000-0000-0000-000000000099"` НЕ существует

**When** клиент вызывает `NetworkLoadBalancerService/Delete` с `uid = "00000000-0000-0000-0000-000000000099"`

**Then** gRPC статус = `NOT_FOUND`
**And** `details[]` содержит `ResourceInfo.resource_type = "NetworkLoadBalancer"`, `resource_name = "00000000-0000-0000-0000-000000000099"`

### L8. Delete TargetGroup: несуществующий uid — NOT_FOUND

**ID:** 0.5-L8

**Given** TargetGroup с `uid = "00000000-0000-0000-0000-000000000098"` НЕ существует

**When** клиент вызывает `TargetGroupService/Delete` с `uid = "00000000-0000-0000-0000-000000000098"`

**Then** gRPC статус = `NOT_FOUND`
**And** `details[]` содержит `ResourceInfo.resource_type = "TargetGroup"`

### L9. Concurrent Upsert одного NLB — ABORTED при OCC failure

**ID:** 0.5-L9

**Given** NLB `"concurrent-nlb"` существует с `resource_version = <R>`
**And** Два клиента одновременно читают NLB с `resource_version = <R>`

**When** Оба клиента одновременно вызывают `NetworkLoadBalancerService/Upsert` с изменёнными spec (разными изменениями)
**And** В handler используется `SELECT FOR UPDATE` для защиты от concurrent write

**Then** Один клиент получает gRPC статус = OK
**And** Второй клиент получает gRPC статус = `ABORTED`
**And** `ABORTED`-клиент должен выполнить retry (повторно прочитать ресурс и применить изменение)

### L10. List NLB с невалидным page_size — INVALID_ARGUMENT

**ID:** 0.5-L10

**Given** Сервис `NetworkLoadBalancerService` запущен

**When** клиент вызывает `NetworkLoadBalancerService/List` с `page_size = 5000` (> 1000)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[].field_violations[0].field = "page_size"`
**And** описание содержит максимальное значение 1000

### L11. Watch NLB с невалидным resourceVersion — INVALID_ARGUMENT

**ID:** 0.5-L11

**Given** Сервис `NetworkLoadBalancerService` запущен

**When** клиент открывает Watch стрим с `resource_version = "not-a-number"`

**Then** сервер немедленно возвращает ошибку `INVALID_ARGUMENT`
**And** `details[].field_violations[0].field = "resource_version"`

### L12. Upsert TargetGroup с невалидным IP-адресом — INVALID_ARGUMENT

**ID:** 0.5-L12

**Given** Folder `<folder-uid>`, Subnet `<subnet-uid>` существуют

**When** клиент вызывает `TargetGroupService/Upsert` с:
- `target_groups[0].spec.targets[0].subnet_id = <subnet-uid>`
- `target_groups[0].spec.targets[0].address = "not-an-ip"` (невалидный IP)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "target_groups[0].spec.targets[0].address"`

### L13. Upsert NLB: дублирующийся port+protocol в listeners одного NLB — INVALID_ARGUMENT

**ID:** 0.5-L13

**Given** Folder `<folder-uid>` существует

**When** клиент вызывает `NetworkLoadBalancerService/Upsert` с:
- `spec.listeners[0].name = "http"`, `spec.listeners[0].port = 80`, `spec.listeners[0].protocol = "TCP"`
- `spec.listeners[1].name = "http-dup"`, `spec.listeners[1].port = 80`, `spec.listeners[1].protocol = "TCP"` (дубликат port+protocol)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "network_load_balancers[0].spec.listeners"` (или указывает на конкретный индекс `listeners[1]`)
**And** описание уточняет: комбинация `port=80, protocol=TCP` уже используется другим listener-ом данного NLB
**And** NLB НЕ создана / не обновлена в БД

*Примечание (OQ-1, закрыт inline, вариант A):* дублирование `port + protocol` внутри одного NLB запрещено — семантически некорректная конфигурация для L4-балансировщика.

### L14. Upsert NLB: невалидное имя (нарушение regex `^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$`) — INVALID_ARGUMENT

**ID:** 0.5-L14

**Given** Folder `<folder-uid>` существует

**When** клиент вызывает `NetworkLoadBalancerService/Upsert` с:
- `network_load_balancers[0].metadata.name = "Bad_Name"` (содержит заглавные буквы и подчёркивание)
- `network_load_balancers[0].metadata.folder_id = <folder-uid>`

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "network_load_balancers[0].metadata.name"`
**And** `field_violations[0].description` содержит подсказку о допустимом формате: `^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$`
**And** NLB НЕ создана в БД

### L15. Upsert NLB: невалидный UUID в folder_id — INVALID_ARGUMENT

**ID:** 0.5-L15

**Given** Сервис `NetworkLoadBalancerService` запущен

**When** клиент вызывает `NetworkLoadBalancerService/Upsert` с:
- `network_load_balancers[0].metadata.name = "valid-name"`
- `network_load_balancers[0].metadata.folder_id = "not-a-valid-uuid"` (не UUID v4 формат)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "network_load_balancers[0].metadata.folder_id"`
**And** `field_violations[0].description` уточняет: значение должно быть UUID v4 (формат `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`)
**And** NLB НЕ создана в БД (валидация выполняется до обращения к resource-manager)

### L16. Concurrent Upsert одного TargetGroup — ABORTED при OCC failure

**ID:** 0.5-L16

**Given** TargetGroup `"concurrent-tg"` существует с `resource_version = <R>`
**And** Два клиента одновременно читают TargetGroup с `resource_version = <R>`

**When** Оба клиента одновременно вызывают `TargetGroupService/Upsert` с изменёнными spec (разными targets)
**And** В handler используется `SELECT FOR UPDATE` для защиты от concurrent write

**Then** Один клиент получает gRPC статус = OK
**And** Второй клиент получает gRPC статус = `ABORTED`
**And** `ABORTED`-клиент должен выполнить retry (повторно прочитать ресурс и применить изменение)

---

## 13. Группа M — End-to-end smoke (port-forward; full flow)

### M1. Full flow: Folder → Network → Subnet → Instance → TargetGroup → NLB → Watch lifecycle

**ID:** 0.5-M1

**Given** `kacho-resource-manager`, `kacho-vpc`, `kacho-compute`, `kacho-loadbalancer` Pod-ы запущены в namespace `kacho`
**And** `kubectl port-forward svc/resource-manager 9090:9090 -n kacho` активен
**And** `kubectl port-forward svc/vpc 9091:9090 -n kacho` активен
**And** `kubectl port-forward svc/compute 9092:9090 -n kacho` активен
**And** `kubectl port-forward svc/loadbalancer 9093:9090 -n kacho` активен

**When** выполняется скрипт `kacho-deploy/e2e/0.5/M1-full-flow.sh`:
```bash
# Шаг 1: получить default Folder uid
FOLDER_UID=$(grpcurl -plaintext -d '{}' localhost:9090 \
  kacho.cloud.resourcemanager.v1.FolderService/List \
  | jq -r '.folders[0].metadata.uid')

# Шаг 2: создать Network
NET_UID=$(grpcurl -plaintext \
  -d "{\"networks\":[{\"metadata\":{\"name\":\"e2e-lb-net\",\"folderId\":\"$FOLDER_UID\"}}]}" \
  localhost:9091 kacho.cloud.vpc.v1.NetworkService/Upsert \
  | jq -r '.networks[0].metadata.uid')

# Шаг 3: создать Subnet
SUBNET_UID=$(grpcurl -plaintext \
  -d "{\"subnets\":[{\"metadata\":{\"name\":\"e2e-lb-subnet\",\"folderId\":\"$FOLDER_UID\"},\"spec\":{\"networkId\":\"$NET_UID\",\"cidrBlock\":\"10.1.0.0/24\",\"zoneId\":\"kacho-zone-a\"}}]}" \
  localhost:9091 kacho.cloud.vpc.v1.SubnetService/Upsert \
  | jq -r '.subnets[0].metadata.uid')

# Шаг 4: создать Disk и Instance
DISK_UID=$(grpcurl -plaintext \
  -d "{\"disks\":[{\"metadata\":{\"name\":\"e2e-lb-disk\",\"folderId\":\"$FOLDER_UID\"},\"spec\":{\"diskTypeId\":\"network-ssd\",\"zoneId\":\"kacho-zone-a\",\"size\":\"20Gi\"}}]}" \
  localhost:9092 kacho.cloud.compute.v1.DiskService/Upsert \
  | jq -r '.disks[0].metadata.uid')

# Шаг 5: дождаться READY для Disk (до 30 с)
# ...watch loop...

INST_UID=$(grpcurl -plaintext \
  -d "{\"instances\":[{\"metadata\":{\"name\":\"e2e-lb-vm\",\"folderId\":\"$FOLDER_UID\"},\"spec\":{\"platformId\":\"standard-v3\",\"zoneId\":\"kacho-zone-a\",\"resources\":{\"cores\":2,\"memory\":\"4Gi\"},\"bootDisk\":{\"diskId\":\"$DISK_UID\",\"autoDelete\":true},\"networkInterfaces\":[{\"subnetId\":\"$SUBNET_UID\"}],\"desiredPowerState\":\"RUNNING\"}}]}" \
  localhost:9092 kacho.cloud.compute.v1.InstanceService/Upsert \
  | jq -r '.instances[0].metadata.uid')

# Шаг 6: дождаться RUNNING через Watch (до 60 с)
# ...watch loop...

# Шаг 7: создать TargetGroup
TG_UID=$(grpcurl -plaintext \
  -d "{\"targetGroups\":[{\"metadata\":{\"name\":\"e2e-tg\",\"folderId\":\"$FOLDER_UID\"},\"spec\":{\"targets\":[{\"subnetId\":\"$SUBNET_UID\",\"address\":\"10.1.0.10\",\"instanceId\":\"$INST_UID\"}]}}]}" \
  localhost:9093 kacho.cloud.loadbalancer.v1.TargetGroupService/Upsert \
  | jq -r '.targetGroups[0].metadata.uid')

# Шаг 8: создать NLB
NLB_UID=$(grpcurl -plaintext \
  -d "{\"networkLoadBalancers\":[{\"metadata\":{\"name\":\"e2e-nlb\",\"folderId\":\"$FOLDER_UID\"},\"spec\":{\"regionId\":\"kacho-region-a\",\"listeners\":[{\"name\":\"http\",\"port\":80,\"protocol\":\"TCP\"}],\"attachedTargetGroups\":[{\"targetGroupId\":\"$TG_UID\"}]}}]}" \
  localhost:9093 kacho.cloud.loadbalancer.v1.NetworkLoadBalancerService/Upsert \
  | jq -r '.networkLoadBalancers[0].metadata.uid')

# Шаг 9: дождаться ACTIVE через Watch (до 60 с)
# ...watch loop...

# Шаг 10: проверить List
grpcurl -plaintext \
  -d "{\"selectors\":[{\"fieldSelector\":{\"folderId\":\"$FOLDER_UID\"}}]}" \
  localhost:9093 kacho.cloud.loadbalancer.v1.NetworkLoadBalancerService/List
```

**Then** шаги 1–7 возвращают gRPC OK с заполненными uid
**And** `TargetGroup` сразу возвращается со `status.state = "READY"` (шаг 7)
**And** на шаге 9 NLB достигает `ACTIVE` в течение 60 секунд
**And** шаг 10 возвращает массив с `"name": "e2e-nlb"` и `status.state = "ACTIVE"`
**And** Instance `"e2e-lb-vm"` содержит в `metadata.finalizers` `"loadbalancer.kacho.io/target-deregister"`

### M2. e2e Finalizer: Delete Instance → target deregistered → NLB TargetGroup обновлена → Instance удалена

**ID:** 0.5-M2

**Given** Instance `"e2e-lb-vm"` в состоянии `RUNNING`, входит в TargetGroup `"e2e-tg"` (из M1)
**And** Watch стрим на InstanceService открыт в фоне
**And** Watch стрим на TargetGroupService открыт в фоне

**When** выполняется скрипт `kacho-deploy/e2e/0.5/M2-finalizer.sh`:
```bash
grpcurl -plaintext \
  -d "{\"instances\":[{\"metadata\":{\"uid\":\"$INST_UID\"}}]}" \
  localhost:9092 kacho.cloud.compute.v1.InstanceService/Delete
```

**Then** команда возвращает gRPC OK с `metadata.deletion_timestamp` выставленным
**And** в течение 60 секунд:
  1. Watch на TargetGroupService получает `MODIFIED` для `"e2e-tg"` с удалённым target
  2. Watch на InstanceService получает `DELETED` для `"e2e-lb-vm"`
**And** `TargetGroupService/List` для `"e2e-tg"` показывает пустой `spec.targets`
**And** `InstanceService/List` не содержит `"e2e-lb-vm"`

### M3. e2e NLB spec update: добавление listener → UPDATING → ACTIVE

**ID:** 0.5-M3

**Given** NLB `"e2e-nlb"` в состоянии `ACTIVE` (из M1)
**And** Watch стрим на NLBService открыт

**When** выполняется `NetworkLoadBalancerService/Upsert` с дополнительным listener (port=443, protocol=TCP)

**Then** Watch получает `MODIFIED (UPDATING)` затем `MODIFIED (ACTIVE)` в течение 60 секунд
**And** `NetworkLoadBalancerService/List` для `"e2e-nlb"` показывает два listeners (port 80 и 443)

### M4. e2e full-replace attachedTargetGroups: отсоединение одной TargetGroup

**ID:** 0.5-M4

**Given** NLB `"e2e-nlb"` в состоянии `ACTIVE` с двумя attachedTargetGroups: `<tg-a>` и `<tg-b>`

**When** выполняется `NetworkLoadBalancerService/Upsert` с `spec.attached_target_groups = [{target_group_id: <tg-a>}]` (только tg-a)

**Then** ответ — OK
**And** `NetworkLoadBalancerService/List` для `"e2e-nlb"` показывает `spec.attached_target_groups` только с `<tg-a>`
**And** TargetGroup `<tg-b>` по-прежнему существует (не удалена, только отсоединена от NLB)

### M5. e2e Helm chart kacho-loadbalancer деплоится и проходит readiness probe

**ID:** 0.5-M5

**Given** `kind`-кластер поднят (`make dev-up`)
**And** В `kacho-deploy/helm/` присутствует chart для `loadbalancer`
**And** Image `prorobotech/kacho-loadbalancer:0.5.0` доступен

**When** выполняется `helm upgrade --install loadbalancer kacho-deploy/helm/loadbalancer/ -n kacho --values kacho-deploy/helm/loadbalancer/values.dev.yaml`

**Then** Pod `loadbalancer-*` переходит в статус `Running` и `Ready 1/1` в течение 90 секунд
**And** `kubectl exec -n kacho ... -- grpc_health_probe -addr :9090` возвращает `status: SERVING`
**And** Лог Pod содержит строку `"reconciler started"` или аналогичную
**And** БД `kacho_loadbalancer` содержит таблицы `network_load_balancers`, `target_groups`, `regions`, `resource_events`

### M6. e2e seed: регион kacho-region-a присутствует в БД после миграции

**ID:** 0.5-M6

**Given** Postgres запущен с применёнными миграциями `kacho-loadbalancer`

**When** разработчик выполняет `SELECT id FROM regions`

**Then** результат содержит как минимум `"kacho-region-a"`
**And** Seed идемпотентен: повторное применение миграции не создаёт дубликаты

---

## 14. Группа N — Definition of Done

Sub-итерация 0.5 считается **завершённой**, когда **все** условия выполнены:

1. **Все сценарии §1–§13** (A1–A5, B1–B7, C1–C6, D1–D6, E1–E3, F1–F4, G1–G4, H1–H8, I1–I4, J1–J6, K1–K6, L1–L16, M1–M6) покрыты исполняемыми тестами:
   - Integration-тесты (testcontainers-Postgres) в `kacho-loadbalancer/internal/service/*_acceptance_test.go` — все зелёные.
   - E2E bash-скрипты в `kacho-deploy/e2e/0.5/*.sh` — все зелёные при запуске `make e2e-test PHASE=0.5`.

2. **Proto** `kacho-proto/proto/kacho/cloud/loadbalancer/v1/` содержит:
   - `network_load_balancer.proto` — `NetworkLoadBalancerService` с Upsert, Delete, List, Watch; все message-типы включая `Listener`, `AttachedTargetGroup`, `NetworkLoadBalancer.Status.State` enum
   - `target_group.proto` — `TargetGroupService` с Upsert, Delete, List, Watch; `Target` message; `TargetGroup.Status.State` enum
   - `internal.proto` — `LoadBalancerInternal` с `NetworkLoadBalancerExists`, `TargetGroupExists`, `UpdateNetworkLoadBalancerStatus`, `UpdateTargetGroupStatus`, `RemoveTarget`
   - `buf lint` и `buf breaking` — зелёные

3. **kacho-loadbalancer** реализован с Clean Architecture:
   - `cmd/loadbalancer/main.go` — composition root (единственное место wiring)
   - `internal/domain/` — entity-типы `NetworkLoadBalancer`, `TargetGroup` (импортирует только stdlib и kacho-proto)
   - `internal/service/` — use-cases с port-интерфейсами (`NLBRepo`, `TargetGroupRepo`, `FolderClient`, `SubnetClient`, `InstanceClient`); бизнес-логика reconciler; **никакого pgx/sqlc в service/**
   - `internal/repo/` — sqlc-generated queries + handwritten filter-builder
   - `internal/clients/` — gRPC-клиенты для resource-manager, vpc, compute
   - `internal/reconciler/` — фоновая горутина reconciler, `pg_advisory_lock`, симулированные переходы NLB
   - `internal/handler/` — тонкий transport-слой
   - `internal/handler/internal_handler.go` — Internal RPC, включая `RemoveTarget` (не регистрируется в api-gateway)
   - `migrations/` — `0001_initial.sql` (схема), `0002_seed_regions.sql` (seed-данные)
   - `deploy/` — Dockerfile, Helm chart values

4. **kacho-compute обновлён** (минимальные изменения для finalizer):
   - При создании Instance автоматически добавляется finalizer `"loadbalancer.kacho.io/target-deregister"` в `metadata.finalizers[]`
   - compute-reconciler обрабатывает этот finalizer: вызывает `LoadBalancerInternal/RemoveTarget`, затем удаляет finalizer из metadata
   - Клиент `LoadBalancerClient` добавлен в `internal/clients/` compute

5. **Reconciler**:
   - Использует `pg_advisory_lock(uid_hash)` per-resource для координации multi-replica
   - Симулирует задержки (из config): NLB CREATING → ACTIVE: 5–15 с; NLB UPDATING → ACTIVE: 5–15 с
   - TargetGroup не требует reconciler: переход CREATING → READY выполняется синхронно в handler
   - Идемпотентен: повторный запуск на уже ACTIVE NLB — no-op
   - Recovery: после сбоя сервиса находит NLB в промежуточных состояниях и завершает переходы

6. **Cross-service validation**:
   - При Upsert NLB/TargetGroup с folderId → gRPC `ResourceManagerInternal/FolderExists`
   - При Upsert TargetGroup с subnetId → gRPC `VpcInternal/SubnetExists`
   - При Upsert TargetGroup с instanceId → gRPC `ComputeInternal/InstanceExists`
   - При недоступности downstream → `UNAVAILABLE`
   - `attachedTargetGroups[].targetGroupId` валидируется через same-DB FK (не cross-service gRPC)

7. **Finalizer `loadbalancer.kacho.io/target-deregister`**:
   - Автоматически добавляется compute-сервисом при Upsert Instance
   - compute-reconciler вызывает `LoadBalancerInternal/RemoveTarget` при finalizer-cleanup
   - При недоступности loadbalancer-сервиса — retry без снятия finalizer

8. **Helm chart** для `loadbalancer` добавлен в `kacho-deploy/helm/` и в `helm/umbrella/Chart.yaml`.

9. **CI** всех затронутых репо зелёный:
   - `kacho-proto`: `buf-lint`, `buf-breaking`, `buf-generate` (без диффа в gen/)
   - `kacho-loadbalancer`: `golangci-lint`, `go test ./...` (включая integration с testcontainers)
   - `kacho-compute`: `golangci-lint`, `go test ./...` (регрессия финалайзера покрыта тестами)
   - `kacho-deploy`: `helm lint`

10. **Naming conventions** соблюдены:
    - Proto package: `kacho.cloud.loadbalancer.v1`
    - DB: `kacho_loadbalancer`
    - Env: `KACHO_LOADBALANCER_*`
    - k8s service: `loadbalancer.kacho.svc.cluster.local`
    - Docker image: `prorobotech/kacho-loadbalancer:0.5.0`
    - Finalizer: `loadbalancer.kacho.io/target-deregister`

11. **Clean Architecture** соблюдена (проверяется `go-style-reviewer`):
    - `domain/` и `service/` не импортируют `pgx`, `sqlc`-типы, grpc-stubs
    - Бизнес-логика отсутствует в `handler/`
    - Глобальных синглтонов нет вне `cmd/`

12. `kacho-workspace/docs/specs/CHANGELOG.md` содержит запись о завершении sub-phase 0.5.

13. Тег `kacho-loadbalancer:0.5.0` поставлен на `main`.

---

## 15. Открытые вопросы (§11)

> **Все OQ закрыты в данном раунде.** Секция оставлена для истории.

**OQ-1. Уникальность listener по порту/протоколу внутри одного NLB** — ✅ ЗАКРЫТ (вариант A)

Дублирование `port + protocol` внутри одного NLB запрещено: INVALID_ARGUMENT при Upsert. Добавлен сценарий L13.

**OQ-2. TargetGroup с targets, принадлежащими разным subnet** — ✅ ЗАКРЫТ (разрешено)

Несколько targets с разными `subnet_id` внутри одного TargetGroup допустимы. Ограничения data plane за пределами scope.

**OQ-3. NLB `status.external_ips` — откуда берётся IP?** — ✅ ЗАКРЫТ (вариант B)

Reconciler присваивает симулированный IP из диапазона `10.255.X.X` при переходе CREATING → ACTIVE. Добавлена проверка в E1 и K1. Поле `external_ips[]` присутствует в A3.

**OQ-4. Порядок снятия finalizer-ов при удалении Instance** — ✅ ЗАКРЫТ (вариант A)

Оба finalizer обрабатываются параллельно в двух горутинах compute-reconciler-а. Порядок снятия не гарантирован и не важен для control plane-only системы. Обновлён I1.
