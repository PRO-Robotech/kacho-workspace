# Sub-phase 0.3 (VPC — Network / Subnet / SecurityGroup / RouteTable / Address) — Acceptance

**Документ:** acceptance / sub-phase 0.3
**Дата:** 2026-05-03
**Статус:** Draft, round 2 (после ревью)
**Источник требований:** `04-roadmap-and-phasing.md` §3 «Sub-итерация 0.3»; `01-architecture-and-services.md` §2.3, §3, §4; `02-data-model-and-conventions.md` §2, §4, §6–10, §14; `00-overview-and-scope.md` §4.
**Утверждение:** approve выставляет агент `acceptance-reviewer` (заказчик не подключается — он проверяет финальный smoke на шаге 7, см. `04-roadmap-and-phasing.md` §2).

---

## 0. Цель sub-итерации (1 абзац)

Sub-итерация 0.3 реализует сервис `kacho-vpc` — control plane сетевых ресурсов: Network, Subnet, SecurityGroup (с inline-правилами SecurityGroupRule), RouteTable (с inline-маршрутами StaticRoute) и Address (с minimal lifecycle `RESERVED → IN_USE → RELEASED`). Для всех ресурсов lifecycle синхронный (без async reconciler): при Upsert status выставляется немедленно в той же транзакции. Добавляется cross-service gRPC-вызов vpc → resource-manager: при upsert любого VPC-ресурса сервис проверяет существование `metadata.folderId` через `ResourceManagerInternal/FolderExists`. Сервис использует готовые компоненты из kacho-corelib 0.2: Watch Hub, outbox, selector, common migrations. После завершения итерации разработчик может дёргать `NetworkService/Upsert`, `SubnetService/Upsert`, создать иерархию Network → Subnet, наблюдать Watch-события и убедиться, что удаление Network с зависимым Subnet возвращает `FAILED_PRECONDITION`. API Gateway (sub-phase 0.6) **не существует** в данной итерации: все e2e-сценарии используют `kubectl port-forward`.

**Что НЕ входит в 0.3** (явно отложено):
- `kacho-api-gateway` и REST-mux — sub-phase 0.6.
- Compute, LoadBalancer — sub-phase 0.4–0.5.
- Финализеры на VPC-ресурсах (`compute.kacho.io/disk-detach`, `loadbalancer.kacho.io/target-deregister`) — sub-phase 0.4–0.5.
- Cross-service validation из vpc в другие сервисы (compute → vpc) — ответственность sub-phase 0.4.
- SecurityGroup attachment к Instance (это cross-service) — sub-phase 0.4.
- Address lifecycle `IN_USE` (изменяется compute-сервисом при attach) — sub-phase 0.4.
- `Address.spec.address_type = INTERNAL` — отложено; в 0.3 поддерживается только `EXTERNAL`. Попытка создать INTERNAL Address → `INVALID_ARGUMENT`.
- CIDR overlap detection между Subnet внутри одной Network — не входит в 0.3, зарезервировано.
- Пагинация глубже 1000 — зарезервирована архитектурно.
- AAA — отдельная фаза.

**Зафиксированные соглашения:**
- `ALREADY_EXISTS` зарезервирован, но в upsert-only API **не используется**. Семантика: `name + folderId → create-or-update`.
- **Concurrent create-collision** (два вызова Upsert с одним и тем же `name+folderId`, попытка одновременного insert): сервер возвращает `ABORTED` проигравшему вызову (retry-семантика). `ALREADY_EXISTS` при concurrent upsert не применяется.
- **Server-managed поля** (`status`, `metadata.uid`, `metadata.creationTimestamp`, `metadata.resourceVersion`) **игнорируются на входе**: если клиент передаёт их в запросе, сервер не возвращает ошибку, но проставляет собственные значения, игнорируя клиентские. Это соответствует K8s-конвенции и решению 0.2-G1a.
- **`metadata.uid` при создании**: сервер всегда присваивает новый UUID v4, игнорируя uid в запросе (вариант A, аналогично 0.2-G1a). Ответ содержит server-assigned uid.
- **CIDR-валидация**: проверяется через `net.ParseCIDR`; host-bits-set отклоняется (`10.0.0.1/24` → `INVALID_ARGUMENT`, требуется network address `10.0.0.0/24`). Для Subnet — принимаются любые валидные CIDR (не только RFC 1918).
- **`status.allocated_ipv4` для Address**: сервер генерирует псевдослучайный IP из диапазона `203.0.113.0/24` (TEST-NET-3, RFC 5737). Уникальность обеспечивается UNIQUE constraint на уровне таблицы (`addresses.allocated_ipv4`).
- **SecurityGroupRule.id**: server-assigned UUID, генерируется заново при каждом Upsert (full-replace семантика). Клиент не передаёт `id` правил — они всегда пересоздаются.
- **SecurityGroupRule и StaticRoute** — дочерние ресурсы, хранятся в отдельных таблицах с same-DB FK CASCADE. Управляются через родительский Upsert (inline в `spec`). Нет отдельных `SecurityGroupRuleService` / `StaticRouteService` — правила upsert-ируются атомарно с родителем (DELETE + INSERT в одной транзакции).
- **Address**: при Upsert `status.state = "RESERVED"` выставляется сразу (синхронный переход, без reconciler).
- **Network/Subnet/SG/RouteTable**: при Upsert `status.state = "ACTIVE"` сразу.
- **`network_id` в FieldSelector** (для фильтрации Subnet/RouteTable по Network): передаётся через `FieldSelector.refs` с `kind = "Network"`, `uid = <net-uid>`. Расширение общего FieldSelector или введение VPC-специфичного типа **не требуется**; proto-изменений нет.
- **Имена integration-тест-функций** следуют паттерну `Test<Resource>_<ScenarioID>_<ShortDesc>` (например, `TestNetwork_B1_CreateHappyPath`). E2e bash-скрипты — `kacho-deploy/e2e/0.3/<ID>-<short-desc>.sh`.
- **kacho-vpc импортирует kacho-corelib**: используются пакеты `kacho-corelib/watch`, `kacho-corelib/outbox`, `kacho-corelib/selector`, `kacho-corelib/migrations/common` без дублирования per-service.

---

## 1. Группа A — kacho-proto/vpc/v1 contracts

Сценарии группы A проверяют корректность proto-контрактов `kacho-proto/proto/kacho/cloud/vpc/v1/`. Тесты — `buf lint` и `buf breaking` в CI kacho-proto. Дополнительно: unit-тесты на Go-generated stubs в kacho-vpc.

### A1. buf lint проходит без предупреждений

**ID:** 0.3-A1

**Given** файлы `kacho-proto/proto/kacho/cloud/vpc/v1/` содержат:
- `network.proto`
- `subnet.proto`
- `security_group.proto`
- `route_table.proto`
- `address.proto`
- `internal.proto`

**When** выполняется `buf lint proto/kacho/cloud/vpc/v1/` в репо `kacho-proto`

**Then** команда завершается с кодом 0
**And** нет предупреждений о нарушении naming, field numbering, field type conventions
**And** package declaration во всех файлах — `package kacho.cloud.vpc.v1;`
**And** go_package option — `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/vpc/v1`

*Трассируемость:* сценарий покрывается шагом `buf-lint` в `kacho-proto/.github/workflows/ci.yaml` (не Go-тестом).

### A2. buf breaking не регрессирует после изменений

**ID:** 0.3-A2

**Given** в ветке `main` kacho-proto уже есть baseline с baseline-версией proto
**And** разработчик вносит изменение (например, добавляет новое поле)

**When** выполняется `buf breaking --against 'https://github.com/PRO-Robotech/kacho-proto.git#branch=main'`

**Then** команда завершается с кодом 0 (обратная совместимость соблюдена)
**And** если поле удалено или переименовано — команда завершается с ненулевым кодом (регрессия обнаружена)

*Трассируемость:* сценарий покрывается шагом `buf-breaking` в `kacho-proto/.github/workflows/ci.yaml` (не Go-тестом).

### A3. proto Network содержит обязательные RPC и message-типы

**ID:** 0.3-A3

**Given** файл `network.proto` скомпилирован

**When** разработчик проверяет сгенерированный Go-код в `gen/go/kacho/cloud/vpc/v1/`

**Then** присутствуют типы:
- `NetworkService` с методами `Upsert`, `Delete`, `List`, `Watch`
- `Network` message с полями `metadata`, `spec`, `status`
- `NetworkUpsertRequest` / `NetworkUpsertResponse`
- `NetworkDeleteRequest` / `NetworkDeleteResponse`
- `NetworkListRequest` / `NetworkListResponse`
- `NetworkWatchRequest`, `NetworkWatchEvent` (server-streaming)
- `Network.Spec` с полями: `display_name string`, `description string`
- `Network.Status` с полем `state` (enum: `ACTIVE`, `DELETING`)

### A4. proto Subnet содержит обязательные поля spec

**ID:** 0.3-A4

**Given** файл `subnet.proto` скомпилирован

**When** разработчик проверяет сгенерированный Go-код

**Then** `Subnet.Spec` содержит поля:
- `network_id string` — обязательный, ссылка на Network.uid
- `cidr_block string` — CIDR (например, `"10.0.0.0/24"`)
- `zone_id string` — зональность (например, `"kacho-zone-a"`)
- `display_name string` — опциональный
- `description string` — опциональный
**And** `Subnet.Status` содержит поле `state` (enum: `ACTIVE`, `DELETING`)

### A5. proto SecurityGroup содержит SecurityGroupRule как вложенный список

**ID:** 0.3-A5

**Given** файл `security_group.proto` скомпилирован

**When** разработчик проверяет сгенерированный Go-код

**Then** `SecurityGroup.Spec` содержит:
- `description string`
- `rules repeated SecurityGroupRule`
**And** `SecurityGroupRule` содержит поля:
- `id string` — server-assigned уникальный идентификатор правила внутри группы
- `direction string` (INGRESS / EGRESS)
- `protocol string` (TCP / UDP / ICMP / ANY)
- `port_range_min int32`, `port_range_max int32`
- `cidr_blocks repeated string` — список CIDR-диапазонов источника/назначения
- `description string`
**And** `SecurityGroup.Status` содержит поле `state` (enum: `ACTIVE`, `DELETING`)

### A6. proto RouteTable содержит StaticRoute как вложенный список

**ID:** 0.3-A6

**Given** файл `route_table.proto` скомпилирован

**When** разработчик проверяет сгенерированный Go-код

**Then** `RouteTable.Spec` содержит:
- `network_id string` — ссылка на Network.uid (RouteTable принадлежит Network)
- `description string`
- `static_routes repeated StaticRoute`
**And** `StaticRoute` содержит:
- `destination_prefix string` — целевой CIDR (например, `"0.0.0.0/0"`)
- `next_hop_address string` — IP-адрес следующего хопа (например, `"10.0.0.1"`)
- `description string`
**And** `RouteTable.Status` содержит `state` (enum: `ACTIVE`, `DELETING`)

### A7. proto Address содержит lifecycle fields

**ID:** 0.3-A7

**Given** файл `address.proto` скомпилирован

**When** разработчик проверяет сгенерированный Go-код

**Then** `Address.Spec` содержит:
- `address_type string` (EXTERNAL / INTERNAL)
- `zone_id string`
- `description string`
**And** `Address.Status` содержит:
- `state string` (RESERVED / IN_USE / RELEASED)
- `allocated_ipv4 string` — server-assigned IP после резервирования

### A8. proto internal.proto содержит Exists-методы для всех VPC-ресурсов

**ID:** 0.3-A8

**Given** файл `internal.proto` скомпилирован

**When** разработчик проверяет сгенерированный Go-код

**Then** присутствует `VpcInternalService` с методами:
- `NetworkExists(NetworkExistsRequest) → ExistsResponse`
- `SubnetExists(SubnetExistsRequest) → ExistsResponse`
- `SecurityGroupExists(SecurityGroupExistsRequest) → ExistsResponse`
- `RouteTableExists(RouteTableExistsRequest) → ExistsResponse`
- `AddressExists(AddressExistsRequest) → ExistsResponse`
**And** каждый `<R>ExistsRequest` содержит поле `uid string`
**And** `ExistsResponse` содержит поле `exists bool`

---

## 2. Группа B — Network domain (Upsert / Delete / List / Watch)

Сценарии группы B покрывают `NetworkService`. Тесты — integration через testcontainers (gRPC handler + service + repo + outbox). Референс: `01-architecture-and-services.md` §2.3; `02-data-model-and-conventions.md` §2, §6.

### B1. Upsert: создание новой Network

**ID:** 0.3-B1

**Given** Postgres запущен с миграциями `kacho_vpc`
**And** Folder `"default"` существует с `uid = <folder-uid>`
**And** сервис `NetworkService` инициализирован
**And** mock `FolderExists(uid=<folder-uid>)` → `{exists: true}` для resource-manager client
**And** Network с именем `"net-prod"` в Folder `<folder-uid>` не существует

**When** клиент вызывает `kacho.cloud.vpc.v1.NetworkService/Upsert` с payload:
- `networks[0].metadata.name = "net-prod"`
- `networks[0].metadata.folderId = <folder-uid>`
- `networks[0].metadata.labels = {"env": "production"}`
- `networks[0].spec.display_name = "Production Network"`
- `networks[0].spec.description = "Main production network"`

**Then** ответ содержит `networks[0]` с заполненными:
- `metadata.uid` — непустой UUID v4
- `metadata.name = "net-prod"`
- `metadata.folderId = <folder-uid>`
- `metadata.creationTimestamp` — не нулевое
- `metadata.resourceVersion` — непустая десятичная строка > 0
- `metadata.labels = {"env": "production"}`
- `metadata.generation = 1`
**And** `status.state = "ACTIVE"` (синхронный переход)
**And** в таблице `networks` присутствует запись с `name = 'net-prod'`, `folder_id = <folder-uid>`
**And** в `resource_events` есть событие `event_type = 'ADDED'`, `resource_kind = 'Network'`, `resource_uid = <uid>`
**And** gRPC статус = OK

### B2. Upsert: обновление существующей Network (idempotent — no diff)

**ID:** 0.3-B2

**Given** Network `"net-prod"` создана (B1), её `metadata.uid = <uid>`, `metadata.resourceVersion = <rv>`

**When** клиент вызывает `NetworkService/Upsert` с тем же payload (те же name, folderId, labels, spec)

**Then** ответ содержит тот же `metadata.uid = <uid>`
**And** `metadata.resourceVersion` не изменился (no-op: нет diff)
**And** в `resource_events` новых событий для данного `uid` не появилось
**And** в БД ровно одна запись с `name = 'net-prod'` в данном `folder_id`

### B3. Upsert: изменение labels Network генерирует MODIFIED событие

**ID:** 0.3-B3

**Given** Network `"net-prod"` создана с `labels = {"env": "production"}`, `resourceVersion = <rv1>`

**When** клиент вызывает `NetworkService/Upsert` с:
- `networks[0].metadata.name = "net-prod"`
- `networks[0].metadata.folderId = <folder-uid>`
- `networks[0].metadata.labels = {"env": "production", "tier": "premium"}`

**Then** ответ содержит `metadata.labels = {"env": "production", "tier": "premium"}`
**And** `metadata.resourceVersion` > `<rv1>`
**And** в `resource_events` появляется событие `event_type = 'MODIFIED'`, `resource_kind = 'Network'`

### B4. Delete: удаление Network без зависимых Subnet

**ID:** 0.3-B4

**Given** Network `"net-empty"` с `uid = <uid>` существует
**And** в Network нет зависимых Subnet

**When** клиент вызывает `NetworkService/Delete` с:
- `networks[0].metadata.uid = <uid>`

**Then** gRPC статус = OK
**And** запись `networks` с `uid = <uid>` физически удалена из БД (нет finalizers — мгновенное удаление)
**And** в `resource_events` появляется событие `event_type = 'DELETED'`, `resource_uid = <uid>`
**And** повторный `Delete` с тем же uid возвращает `NOT_FOUND`

### B5. Delete: удаление Network с зависимым Subnet → FAILED_PRECONDITION

**ID:** 0.3-B5

**Given** Network `"net-with-subnet"` с `uid = <net-uid>` существует
**And** В этой Network существует Subnet `"subnet-a"` с `network_id = <net-uid>`

**When** клиент вызывает `NetworkService/Delete` с:
- `networks[0].metadata.uid = <net-uid>`

**Then** gRPC статус = `FAILED_PRECONDITION`
**And** `details[]` содержит `PreconditionFailure` с:
  - `violations[0].type = "HAS_DEPENDENT_RESOURCES"`
  - `violations[0].subject = <net-uid>`
  - `violations[0].description` содержит указание на наличие зависимых Subnet
**And** Network НЕ удалена из БД

*Реализация:* FK `RESTRICT` на уровне БД (`subnets.network_id → networks.uid ON DELETE RESTRICT`). Сервис перехватывает `pgcode.ForeignKeyViolation` и конвертирует в `FAILED_PRECONDITION` с заполненным `PreconditionFailure`.

### B6. List Networks: фильтр по folderId

**ID:** 0.3-B6

**Given** Folder `<folder-a>` и Folder `<folder-b>` существуют
**And** Network `"net-1"` в `<folder-a>`, Network `"net-2"` в `<folder-a>`, Network `"net-3"` в `<folder-b>`

**When** клиент вызывает `NetworkService/List` с:
- `selectors[0].field_selector.folder_id = <folder-a>`

**Then** ответ содержит ровно 2 Network: `"net-1"` и `"net-2"`
**And** `"net-3"` не включена
**And** ответ содержит `resourceVersion` — непустая десятичная строка

### B7. List Networks: фильтр по labels

**ID:** 0.3-B7

**Given** 3 Network в одном Folder:
- `"net-dev"` с `labels = {"env": "dev"}`
- `"net-prod"` с `labels = {"env": "prod"}`
- `"net-prod-ext"` с `labels = {"env": "prod", "tier": "external"}`

**When** клиент вызывает `NetworkService/List` с:
- `selectors[0].label_selector = {"env": "prod"}`

**Then** ответ содержит ровно 2 Network: `"net-prod"` и `"net-prod-ext"`
**And** `"net-dev"` не включена

### B8. Watch: получение ADDED, MODIFIED, DELETED событий для Network

**ID:** 0.3-B8

**Given** Watch Hub запущен
**And** Watch стрим открыт `NetworkService/Watch` с пустыми selectors, `resourceVersion = <текущий>`

**When** (шаг 1) `NetworkService/Upsert` создаёт Network `"watch-net"`
**And** (шаг 2) `NetworkService/Upsert` обновляет `"watch-net"` — добавляет label `{"updated": "true"}`
**And** (шаг 3) `NetworkService/Delete` удаляет `"watch-net"`

**Then** Watch стрим получает 3 события в правильном порядке:
1. `type = ADDED`, `network.metadata.name = "watch-net"`
2. `type = MODIFIED`, `network.metadata.labels["updated"] = "true"`
3. `type = DELETED`, `network.metadata.name = "watch-net"`
**And** каждое событие приходит в течение 500 мс после вызова

---

## 3. Группа C — Subnet domain (с cross-service Folder validation + Network parent)

Сценарии группы C покрывают `SubnetService`. Тесты — integration через testcontainers. Референс: `01-architecture-and-services.md` §2.3.

### C1. Upsert: создание Subnet с указанием networkId

**ID:** 0.3-C1

**Given** Network `"net-prod"` с `uid = <net-uid>` существует в Folder `<folder-uid>`
**And** mock `FolderExists(uid=<folder-uid>)` → `{exists: true}`
**And** Subnet `"subnet-a"` не существует

**When** клиент вызывает `kacho.cloud.vpc.v1.SubnetService/Upsert` с payload:
- `subnets[0].metadata.name = "subnet-a"`
- `subnets[0].metadata.folderId = <folder-uid>`
- `subnets[0].spec.network_id = <net-uid>`
- `subnets[0].spec.cidr_block = "10.0.0.0/24"`
- `subnets[0].spec.zone_id = "kacho-zone-a"`
- `subnets[0].spec.description = "Zone A subnet"`

**Then** ответ содержит `subnets[0]` с:
- `metadata.uid` — непустой UUID v4
- `metadata.name = "subnet-a"`
- `metadata.folderId = <folder-uid>`
- `metadata.creationTimestamp` — заполнен
- `metadata.resourceVersion` — непустая строка
- `metadata.generation = 1`
**And** `status.state = "ACTIVE"`
**And** в таблице `subnets` есть запись с `network_id = <net-uid>`, `folder_id = <folder-uid>`, `name = 'subnet-a'`
**And** в `resource_events` событие `event_type = 'ADDED'`, `resource_kind = 'Subnet'`
**And** gRPC статус = OK

### C2. Upsert: повторный Upsert Subnet без diff — no-op

**ID:** 0.3-C2

**Given** Subnet `"subnet-a"` создана (C1), `metadata.resourceVersion = <rv>`

**When** клиент вызывает `SubnetService/Upsert` с тем же payload

**Then** ответ содержит тот же `metadata.uid`
**And** `metadata.resourceVersion` не изменился
**And** в `resource_events` новых событий нет

### C3. Upsert: изменение spec.description Subnet генерирует MODIFIED

**ID:** 0.3-C3

**Given** Subnet `"subnet-a"` создана с `spec.description = "Zone A subnet"`, `resourceVersion = <rv1>`

**When** клиент вызывает `SubnetService/Upsert` с тем же `network_id`, `cidr_block`, `zone_id` но:
- `subnets[0].spec.description = "Updated description for Zone A"`

**Then** ответ содержит `spec.description = "Updated description for Zone A"`
**And** `metadata.resourceVersion` > `<rv1>`
**And** в `resource_events` событие `event_type = 'MODIFIED'`, `resource_kind = 'Subnet'`

### C4. Upsert Subnet с несуществующим networkId — NOT_FOUND

**ID:** 0.3-C4

**Given** Network с `uid = "00000000-0000-0000-0000-000000000010"` НЕ существует в БД
**And** mock `FolderExists` → `{exists: true}`

**When** клиент вызывает `SubnetService/Upsert` с:
- `subnets[0].metadata.name = "orphan-subnet"`
- `subnets[0].metadata.folderId = <valid-folder-uid>`
- `subnets[0].spec.network_id = "00000000-0000-0000-0000-000000000010"`
- `subnets[0].spec.cidr_block = "10.1.0.0/24"`
- `subnets[0].spec.zone_id = "kacho-zone-a"`

**Then** gRPC статус = `NOT_FOUND`
**And** `details[]` содержит `ResourceInfo.resource_type = "Network"`, `resource_name = "00000000-0000-0000-0000-000000000010"`
**And** Subnet НЕ создана в БД

### C5. Delete: удаление Subnet

**ID:** 0.3-C5

**Given** Subnet `"subnet-a"` с `uid = <subnet-uid>` существует

**When** клиент вызывает `SubnetService/Delete` с:
- `subnets[0].metadata.uid = <subnet-uid>`

**Then** gRPC статус = OK
**And** запись в таблице `subnets` с `uid = <subnet-uid>` физически удалена
**And** в `resource_events` событие `event_type = 'DELETED'`

### C6. List Subnets: фильтр по network_id (через FieldSelector.refs)

**ID:** 0.3-C6

**Given** Network `"net-a"` с `uid = <net-a>` и Network `"net-b"` с `uid = <net-b>` существуют
**And** Subnet `"sub-1"` в `<net-a>`, Subnet `"sub-2"` в `<net-a>`, Subnet `"sub-3"` в `<net-b>`

**When** клиент вызывает `SubnetService/List` с:
```json
{
  "selectors": [{
    "field_selector": {
      "refs": [{"kind": "Network", "uid": "<net-a>"}]
    }
  }]
}
```

**Then** ответ содержит ровно 2 Subnet: `"sub-1"` и `"sub-2"`
**And** `"sub-3"` не включена

*Реализация:* `network_id` фильтруется через `FieldSelector.refs[0].uid` где `kind = "Network"`. Расширение общего FieldSelector и введение VPC-специфичного типа не требуются — proto-изменений нет.

### C7. Watch Subnet: получение ADDED события при Upsert

**ID:** 0.3-C7

**Given** Watch Hub запущен
**And** Watch стрим открыт `SubnetService/Watch` с пустыми selectors, `resourceVersion = <текущий>`

**When** `SubnetService/Upsert` создаёт Subnet `"subnet-b"` в Network `<net-uid>`

**Then** Watch стрим получает событие в течение 500 мс:
- `type = ADDED`
- `subnet.metadata.name = "subnet-b"`
- `subnet.metadata.uid` — непустой UUID
- `subnet.spec.network_id = <net-uid>`
- `subnet.spec.cidr_block` — заполнен
- `subnet.status.state = "ACTIVE"`

### C8. Watch Subnet: ADDED, MODIFIED, DELETED

**ID:** 0.3-C8

**Given** Watch стрим открыт `SubnetService/Watch` с selector `field_selector.folder_id = <folder-uid>`

**When** (шаг 1) `SubnetService/Upsert` создаёт Subnet `"sub-watch"` в `<folder-uid>`
**And** (шаг 2) `SubnetService/Upsert` изменяет её description
**And** (шаг 3) `SubnetService/Delete` удаляет `"sub-watch"`

**Then** Watch стрим получает 3 события: ADDED → MODIFIED → DELETED
**And** Subnet в другом Folder не генерирует события в этот стрим

### C9. Watch Subnet: catch-up при подключении с resourceVersion в прошлом

**ID:** 0.3-C9

**Given** 5 Subnet созданы и каждая имеет `resource_version` 1..5 (или sequential)
**And** outbox retention не истёк

**When** клиент открывает Watch стрим `SubnetService/Watch` с `resourceVersion = 2`

**Then** стрим сначала отправляет catch-up события (ADDED) для Subnet с version 3, 4, 5
**And** затем стрим переходит в live-режим
**And** новые события поступают в реальном времени

### C10. Watch Subnet: Gone при устаревшем resourceVersion

**ID:** 0.3-C10

**Given** cleanup удалил события с `resource_version < 1000`
**And** минимальный `resource_version` в `resource_events = 1000`

**When** клиент открывает Watch стрим `SubnetService/Watch` с `resourceVersion = 50`

**Then** сервер закрывает стрим с gRPC статусом `OUT_OF_RANGE` и message `"Gone: resourceVersion too old, please relist"`
**And** `details[]` содержит `ErrorInfo` с `reason = "RESOURCE_VERSION_EXPIRED"`, `domain = "kacho.cloud"`
**And** `details[]` содержит `RequestInfo` с непустым `request_id`

*Примечание:* HTTP 410 Gone (REST через grpc-gateway, sub-phase 0.6) маппится в gRPC `OUT_OF_RANGE` на нативном уровне grpc-gateway.

---

## 4. Группа D — SecurityGroup + SecurityGroupRule (с intra-domain cascade)

Сценарии группы D покрывают `SecurityGroupService` и inline-управление правилами `SecurityGroupRule`. Тесты — integration через testcontainers. Референс: `02-data-model-and-conventions.md` §10 `kacho_vpc`.

### D1. Upsert: создание SecurityGroup без правил

**ID:** 0.3-D1

**Given** Folder `<folder-uid>` существует, mock `FolderExists` → `{exists: true}`
**And** SecurityGroup `"sg-default"` не существует

**When** клиент вызывает `kacho.cloud.vpc.v1.SecurityGroupService/Upsert` с payload:
- `security_groups[0].metadata.name = "sg-default"`
- `security_groups[0].metadata.folderId = <folder-uid>`
- `security_groups[0].spec.description = "Default security group"`
- `security_groups[0].spec.rules = []` (пустой список правил)

**Then** ответ содержит `security_groups[0].metadata.uid` — непустой UUID
**And** `status.state = "ACTIVE"`
**And** в таблице `security_groups` запись с `name = 'sg-default'`
**And** в таблице `security_group_rules` нет записей для данного `security_group_id`
**And** в `resource_events` событие `event_type = 'ADDED'`, `resource_kind = 'SecurityGroup'`

### D2. Upsert: создание SecurityGroup с inline-правилами

**ID:** 0.3-D2

**Given** Folder `<folder-uid>` существует, mock `FolderExists` → `{exists: true}`

**When** клиент вызывает `SecurityGroupService/Upsert` с:
- `security_groups[0].metadata.name = "sg-web"`
- `security_groups[0].metadata.folderId = <folder-uid>`
- `security_groups[0].spec.description = "Web tier security group"`
- `security_groups[0].spec.rules[0].direction = "INGRESS"`
- `security_groups[0].spec.rules[0].protocol = "TCP"`
- `security_groups[0].spec.rules[0].port_range_min = 80`
- `security_groups[0].spec.rules[0].port_range_max = 80`
- `security_groups[0].spec.rules[0].cidr_blocks = ["0.0.0.0/0"]`
- `security_groups[0].spec.rules[0].description = "Allow HTTP"`
- `security_groups[0].spec.rules[1].direction = "INGRESS"`
- `security_groups[0].spec.rules[1].protocol = "TCP"`
- `security_groups[0].spec.rules[1].port_range_min = 443`
- `security_groups[0].spec.rules[1].port_range_max = 443`
- `security_groups[0].spec.rules[1].cidr_blocks = ["0.0.0.0/0"]`
- `security_groups[0].spec.rules[1].description = "Allow HTTPS"`

**Then** ответ содержит `security_groups[0].metadata.uid = <sg-uid>`
**And** в таблице `security_group_rules` ровно 2 записи с `security_group_id = <sg-uid>`
**And** каждая запись имеет server-assigned `id`
**And** в `resource_events` событие `event_type = 'ADDED'`, `resource_kind = 'SecurityGroup'`
**And** gRPC статус = OK

### D3. Upsert: обновление правил SecurityGroup (полная замена)

**ID:** 0.3-D3

**Given** SecurityGroup `"sg-web"` с `uid = <sg-uid>` создана с 2 правилами (D2)

**When** клиент вызывает `SecurityGroupService/Upsert` с тем же `name`, `folderId`, но:
- `security_groups[0].spec.rules` содержит только 1 правило: INGRESS TCP 80 `"0.0.0.0/0"`

**Then** в таблице `security_group_rules` ровно 1 запись для `<sg-uid>` (старые 2 удалены, новая 1 добавлена)
**And** новая запись имеет новый server-assigned `id` (UUID, отличный от предыдущих — ID не сохраняются при full-replace)
**And** `metadata.resourceVersion` > предыдущего значения
**And** в `resource_events` событие `event_type = 'MODIFIED'`, `resource_kind = 'SecurityGroup'`

*Реализация:* при Upsert SecurityGroup — `DELETE FROM security_group_rules WHERE security_group_id = $uid`, затем `INSERT` новые правила с server-assigned UUID. Атомарно в одной транзакции. `SecurityGroupRule.id` генерируется заново при каждом Upsert.

### D4. Delete SecurityGroup — каскадно удаляет SecurityGroupRule (same-DB CASCADE)

**ID:** 0.3-D4

**Given** SecurityGroup `"sg-web"` с `uid = <sg-uid>` существует с 2 правилами

**When** клиент вызывает `SecurityGroupService/Delete` с:
- `security_groups[0].metadata.uid = <sg-uid>`

**Then** gRPC статус = OK
**And** запись в `security_groups` с `uid = <sg-uid>` удалена
**And** в `security_group_rules` нет записей с `security_group_id = <sg-uid>` (каскадное удаление через same-DB FK CASCADE)
**And** в `resource_events` событие `event_type = 'DELETED'`, `resource_kind = 'SecurityGroup'`

### D5. List SecurityGroups: возвращает группы с inline-правилами

**ID:** 0.3-D5

**Given** SecurityGroup `"sg-web"` с 2 правилами существует в Folder `<folder-uid>`

**When** клиент вызывает `SecurityGroupService/List` с:
- `selectors[0].field_selector.folder_id = <folder-uid>`

**Then** ответ содержит `security_groups[0]` с заполненным `spec.rules` (2 правила)
**And** каждое правило содержит все поля (direction, protocol, port_range_min, port_range_max, cidr_blocks)

### D6. Watch SecurityGroup: ADDED событие при создании

**ID:** 0.3-D6

**Given** Watch стрим открыт `SecurityGroupService/Watch` с пустыми selectors
**And** `resourceVersion = <текущий>`

**When** `SecurityGroupService/Upsert` создаёт SecurityGroup `"sg-watch-test"` с 1 правилом

**Then** Watch стрим получает событие в течение 500 мс:
- `type = ADDED`
- `security_group.metadata.name = "sg-watch-test"`
- `security_group.spec.rules` содержит 1 правило

---

## 5. Группа E — RouteTable + StaticRoute (с intra-domain cascade)

Сценарии группы E покрывают `RouteTableService` и inline-управление `StaticRoute`. Тесты — integration через testcontainers.

### E1. Upsert: создание RouteTable с StaticRoutes

**ID:** 0.3-E1

**Given** Network `"net-prod"` с `uid = <net-uid>` существует
**And** Folder `<folder-uid>` существует, mock `FolderExists` → `{exists: true}`

**When** клиент вызывает `kacho.cloud.vpc.v1.RouteTableService/Upsert` с payload:
- `route_tables[0].metadata.name = "rt-main"`
- `route_tables[0].metadata.folderId = <folder-uid>`
- `route_tables[0].spec.network_id = <net-uid>`
- `route_tables[0].spec.description = "Main route table"`
- `route_tables[0].spec.static_routes[0].destination_prefix = "0.0.0.0/0"`
- `route_tables[0].spec.static_routes[0].next_hop_address = "10.0.0.1"`
- `route_tables[0].spec.static_routes[0].description = "Default route"`
- `route_tables[0].spec.static_routes[1].destination_prefix = "192.168.0.0/16"`
- `route_tables[0].spec.static_routes[1].next_hop_address = "10.0.0.254"`
- `route_tables[0].spec.static_routes[1].description = "VPN route"`

**Then** ответ содержит `route_tables[0].metadata.uid = <rt-uid>`
**And** `status.state = "ACTIVE"`
**And** в таблице `route_tables` запись с `name = 'rt-main'`, `network_id = <net-uid>`
**And** в таблице `static_routes` ровно 2 записи с `route_table_id = <rt-uid>`
**And** в `resource_events` событие `event_type = 'ADDED'`, `resource_kind = 'RouteTable'`

### E2. Upsert: обновление StaticRoutes RouteTable (полная замена)

**ID:** 0.3-E2

**Given** RouteTable `"rt-main"` с `uid = <rt-uid>` создана с 2 маршрутами (E1)

**When** клиент вызывает `RouteTableService/Upsert` с тем же `name`, `folderId`, `network_id`, но:
- `route_tables[0].spec.static_routes` содержит только 1 маршрут: `"10.0.0.0/8"` → `"10.0.0.1"`

**Then** в таблице `static_routes` ровно 1 запись для `<rt-uid>` (2 старых удалены, 1 новый добавлен)
**And** `metadata.resourceVersion` > предыдущего
**And** в `resource_events` событие `event_type = 'MODIFIED'`, `resource_kind = 'RouteTable'`

### E3. Delete RouteTable — каскадно удаляет StaticRoutes (same-DB CASCADE)

**ID:** 0.3-E3

**Given** RouteTable `"rt-main"` с `uid = <rt-uid>` существует с 2 маршрутами

**When** клиент вызывает `RouteTableService/Delete` с:
- `route_tables[0].metadata.uid = <rt-uid>`

**Then** gRPC статус = OK
**And** запись в `route_tables` с `uid = <rt-uid>` удалена
**And** в `static_routes` нет записей с `route_table_id = <rt-uid>` (same-DB FK CASCADE)
**And** в `resource_events` событие `event_type = 'DELETED'`, `resource_kind = 'RouteTable'`

### E4. Upsert RouteTable с несуществующим networkId — NOT_FOUND

**ID:** 0.3-E4

**Given** Network с `uid = "00000000-0000-0000-0000-000000000020"` НЕ существует
**And** mock `FolderExists` → `{exists: true}`

**When** клиент вызывает `RouteTableService/Upsert` с:
- `route_tables[0].metadata.name = "rt-orphan"`
- `route_tables[0].metadata.folderId = <valid-folder-uid>`
- `route_tables[0].spec.network_id = "00000000-0000-0000-0000-000000000020"`

**Then** gRPC статус = `NOT_FOUND`
**And** `details[]` содержит `ResourceInfo.resource_type = "Network"`, `resource_name = "00000000-0000-0000-0000-000000000020"`

### E5. List RouteTables: фильтр по folderId

**ID:** 0.3-E5

**Given** RouteTable `"rt-1"`, `"rt-2"` в Folder `<folder-a>` и `"rt-3"` в Folder `<folder-b>`

**When** клиент вызывает `RouteTableService/List` с `field_selector.folder_id = <folder-a>`

**Then** ответ содержит ровно 2 RouteTable: `"rt-1"` и `"rt-2"`
**And** `"rt-3"` не включена

---

## 6. Группа F — Address (lifecycle RESERVED → IN_USE → RELEASED)

Сценарии группы F покрывают `AddressService` и minimal lifecycle. Тесты — integration через testcontainers. Референс: `02-data-model-and-conventions.md` §4 (lifecycle enum).

### F1. Upsert: создание Address — status.state = RESERVED

**ID:** 0.3-F1

**Given** Folder `<folder-uid>` существует, mock `FolderExists` → `{exists: true}`
**And** Address `"addr-prod-ip"` не существует

**When** клиент вызывает `kacho.cloud.vpc.v1.AddressService/Upsert` с payload:
- `addresses[0].metadata.name = "addr-prod-ip"`
- `addresses[0].metadata.folderId = <folder-uid>`
- `addresses[0].spec.address_type = "EXTERNAL"`
- `addresses[0].spec.zone_id = "kacho-zone-a"`
- `addresses[0].spec.description = "Production external IP"`

**Then** ответ содержит `addresses[0].metadata.uid` — непустой UUID
**And** `status.state = "RESERVED"` (синхронный переход при создании)
**And** `status.allocated_ipv4` — непустая строка, содержащая валидный IPv4 из диапазона `203.0.113.1`–`203.0.113.254` (TEST-NET-3, RFC 5737; server-assigned симулированный IP; значение уникально — UNIQUE constraint на `addresses.allocated_ipv4`)
**And** в таблице `addresses` запись с `name = 'addr-prod-ip'`
**And** в `resource_events` событие `event_type = 'ADDED'`, `resource_kind = 'Address'`

### F2. Upsert Address без diff — no-op

**ID:** 0.3-F2

**Given** Address `"addr-prod-ip"` создана (F1), `resourceVersion = <rv>`

**When** клиент вызывает `AddressService/Upsert` с тем же payload

**Then** ответ содержит тот же `metadata.uid`
**And** `metadata.resourceVersion` не изменился
**And** `status.state = "RESERVED"` (без изменений)
**And** в `resource_events` новых событий нет

### F3. Internal UpdateStatus: переход Address в IN_USE

**ID:** 0.3-F3

**Given** Address `"addr-prod-ip"` с `uid = <addr-uid>` в состоянии `RESERVED`
**And** (future: compute сервис захватывает Address при создании Instance)

**When** вызывается `VpcInternalService/UpdateStatus` с:
- `addresses[0].metadata.uid = <addr-uid>`
- `addresses[0].status.state = "IN_USE"`

**Then** в `addresses` запись обновлена: `status.state = "IN_USE"`
**And** в `resource_events` событие `event_type = 'MODIFIED'`, `resource_kind = 'Address'`
**And** `metadata.resourceVersion` > предыдущего значения
**And** gRPC статус = OK

*Примечание:* В sub-phase 0.3 `IN_USE` transition вызывается только через integration-тест напрямую; реальный compute-сервис появится в 0.4.

### F4. Internal UpdateStatus: переход Address в RELEASED

**ID:** 0.3-F4

**Given** Address `"addr-prod-ip"` с `uid = <addr-uid>` в состоянии `IN_USE`

**When** вызывается `VpcInternalService/UpdateStatus` с:
- `addresses[0].metadata.uid = <addr-uid>`
- `addresses[0].status.state = "RELEASED"`

**Then** в `addresses` запись обновлена: `status.state = "RELEASED"`
**And** в `resource_events` событие `event_type = 'MODIFIED'`, `resource_kind = 'Address'`

### F5. Internal UpdateStatus: идемпотентность (повторный вызов с тем же status — no-op)

**ID:** 0.3-F5

**Given** Address `"addr-prod-ip"` в состоянии `RESERVED`, `resourceVersion = <rv>`

**When** вызывается `VpcInternalService/UpdateStatus` дважды подряд с одним и тем же `status.state = "RESERVED"`

**Then** первый вызов — OK, `resourceVersion` обновился
**And** второй вызов — OK, `resourceVersion` НЕ изменился (no-op при отсутствии diff в status)
**And** в `resource_events` ровно одно событие `MODIFIED` (не дублируется)

### F6. Delete Address в состоянии RESERVED

**ID:** 0.3-F6

**Given** Address `"addr-temp"` с `uid = <addr-uid>` в состоянии `RESERVED`

**When** клиент вызывает `AddressService/Delete` с:
- `addresses[0].metadata.uid = <addr-uid>`

**Then** gRPC статус = OK
**And** запись в `addresses` физически удалена
**And** в `resource_events` событие `event_type = 'DELETED'`

### F7. Delete Address в состоянии IN_USE — FAILED_PRECONDITION

**ID:** 0.3-F7

**Given** Address `"addr-in-use"` с `uid = <addr-uid>` в состоянии `IN_USE`

**When** клиент вызывает `AddressService/Delete` с:
- `addresses[0].metadata.uid = <addr-uid>`

**Then** gRPC статус = `FAILED_PRECONDITION`
**And** `details[]` содержит `PreconditionFailure` с:
  - `violations[0].type = "CONFLICTING_STATE"`
  - `violations[0].subject = <addr-uid>`
  - `violations[0].description` содержит указание на то, что Address в состоянии `IN_USE` не может быть удалён

### F8. Watch Address: получение ADDED события при Upsert

**ID:** 0.3-F8

**Given** Watch стрим открыт `AddressService/Watch` с пустыми selectors

**When** `AddressService/Upsert` создаёт Address `"addr-watch"`

**Then** Watch стрим получает событие в течение 500 мс:
- `type = ADDED`
- `address.metadata.name = "addr-watch"`
- `address.status.state = "RESERVED"`
- `address.status.allocated_ipv4` — заполнен

---

## 7. Группа G — Internal RPC (Network.Exists, Subnet.Exists, etc.)

Сценарии группы G покрывают Internal-методы `VpcInternalService`. В sub-phase 0.3 вызываются из integration-тестов и будут использоваться compute/loadbalancer в 0.4–0.5. Референс: `01-architecture-and-services.md` §3.2.

### G1. NetworkExists: существующий Network возвращает exists=true

**ID:** 0.3-G1

**Given** Network `"net-prod"` с `uid = <net-uid>` существует в БД

**When** вызывается `kacho.cloud.vpc.v1.VpcInternalService/NetworkExists` с:
- `uid = <net-uid>`

**Then** ответ: `{exists: true}`
**And** gRPC статус = OK

### G2. NetworkExists: несуществующий Network возвращает exists=false

**ID:** 0.3-G2

**Given** Network с `uid = "00000000-0000-0000-0000-000000000099"` НЕ существует

**When** вызывается `VpcInternalService/NetworkExists` с:
- `uid = "00000000-0000-0000-0000-000000000099"`

**Then** ответ: `{exists: false}`
**And** gRPC статус = OK (не NOT_FOUND — это Exists-метод, который всегда возвращает bool)

### G3. SubnetExists: существующий Subnet возвращает exists=true

**ID:** 0.3-G3

**Given** Subnet `"subnet-a"` с `uid = <subnet-uid>` существует

**When** вызывается `VpcInternalService/SubnetExists` с `uid = <subnet-uid>`

**Then** ответ: `{exists: true}`
**And** gRPC статус = OK

### G4. SubnetExists: несуществующий Subnet возвращает exists=false

**ID:** 0.3-G4

**Given** Subnet с `uid = "00000000-0000-0000-0000-000000000088"` НЕ существует

**When** вызывается `VpcInternalService/SubnetExists` с `uid = "00000000-0000-0000-0000-000000000088"`

**Then** ответ: `{exists: false}`
**And** gRPC статус = OK

### G5. SecurityGroupExists: существующая SecurityGroup возвращает exists=true

**ID:** 0.3-G5

**Given** SecurityGroup `"sg-web"` с `uid = <sg-uid>` существует

**When** вызывается `VpcInternalService/SecurityGroupExists` с `uid = <sg-uid>`

**Then** ответ: `{exists: true}`
**And** gRPC статус = OK

### G6. AddressExists: существующий Address возвращает exists=true

**ID:** 0.3-G6

**Given** Address `"addr-prod-ip"` с `uid = <addr-uid>` существует

**When** вызывается `VpcInternalService/AddressExists` с `uid = <addr-uid>`

**Then** ответ: `{exists: true}`
**And** gRPC статус = OK

### G7. SubnetExists: Subnet с deletionTimestamp (soft-deleted) — возвращает exists=false

**ID:** 0.3-G7

**Given** Subnet `"zombie-subnet"` с `uid = <subnet-uid>` имеет `deletion_timestamp != NULL`

**When** вызывается `VpcInternalService/SubnetExists` с `uid = <subnet-uid>`

**Then** ответ: `{exists: false}`
**And** gRPC статус = OK

*Обоснование:* симметрично с 0.2-F5 — ресурс с `deletionTimestamp != NULL` не должен использоваться как parent-ref в compute/loadbalancer.

---

## 8. Группа H — Cross-service validation (vpc → resource-manager Folder.Exists)

Сценарии группы H покрывают cross-service gRPC-вызов vpc → resource-manager при upsert VPC-ресурсов. Тесты — integration с mock resource-manager client (через interface). Референс: `01-architecture-and-services.md` §1 (граф сервисов), §2.3.

### H1. Upsert Network с несуществующим folderId — INVALID_ARGUMENT

**ID:** 0.3-H1

**Given** mock `FolderExists(uid="00000000-0000-0000-0000-000000000050")` → `{exists: false}` (resource-manager отвечает false)

**When** клиент вызывает `NetworkService/Upsert` с:
- `networks[0].metadata.name = "net-orphan"`
- `networks[0].metadata.folderId = "00000000-0000-0000-0000-000000000050"`
- `networks[0].spec.display_name = "Orphan Network"`

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "networks[0].metadata.folderId"`
**And** `field_violations[0].description` содержит указание, что Folder с указанным uid не существует
**And** Network НЕ создана в БД
**And** в `resource_events` нет новых событий

### H2. Upsert Subnet с несуществующим folderId — INVALID_ARGUMENT

**ID:** 0.3-H2

**Given** mock `FolderExists(uid="00000000-0000-0000-0000-000000000051")` → `{exists: false}`
**And** Network `<net-uid>` существует в БД

**When** клиент вызывает `SubnetService/Upsert` с:
- `subnets[0].metadata.name = "subnet-orphan"`
- `subnets[0].metadata.folderId = "00000000-0000-0000-0000-000000000051"`
- `subnets[0].spec.network_id = <net-uid>`
- `subnets[0].spec.cidr_block = "10.99.0.0/24"`
- `subnets[0].spec.zone_id = "kacho-zone-a"`

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "subnets[0].metadata.folderId"`
**And** Subnet НЕ создана в БД

### H3. Upsert SecurityGroup с несуществующим folderId — INVALID_ARGUMENT

**ID:** 0.3-H3

**Given** mock `FolderExists(uid="00000000-0000-0000-0000-000000000052")` → `{exists: false}`

**When** клиент вызывает `SecurityGroupService/Upsert` с:
- `security_groups[0].metadata.name = "sg-orphan"`
- `security_groups[0].metadata.folderId = "00000000-0000-0000-0000-000000000052"`

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** SecurityGroup НЕ создана

### H4. resource-manager недоступен при Upsert — UNAVAILABLE

**ID:** 0.3-H4

**Given** resource-manager client возвращает gRPC ошибку `UNAVAILABLE` (симулируем сбой downstream через mock)

**When** клиент вызывает `NetworkService/Upsert` с:
- `networks[0].metadata.name = "net-test"`
- `networks[0].metadata.folderId = <any-folder-uid>`

**Then** gRPC статус = `UNAVAILABLE`
**And** `details[]` содержит `RequestInfo` с непустым `request_id`
**And** Network НЕ создана в БД

### H5. Upsert с пустым folderId — INVALID_ARGUMENT (без cross-service вызова)

**ID:** 0.3-H5

**Given** сервис `NetworkService` запущен

**When** клиент вызывает `NetworkService/Upsert` с:
- `networks[0].metadata.name = "net-no-folder"`
- `networks[0].metadata.folderId = ""` (пустая строка)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "networks[0].metadata.folderId"`
**And** cross-service вызов к resource-manager НЕ выполняется (validation до вызова)

---

## 9. Группа I — Negative scenarios (INVALID_ARGUMENT, NOT_FOUND, FAILED_PRECONDITION, ABORTED)

Сценарии группы I покрывают все граничные ошибочные случаи. Коды ошибок согласно `02-data-model-and-conventions.md` §14.

### I1. Upsert Network с невалидным name — INVALID_ARGUMENT

**ID:** 0.3-I1

**Given** сервис `NetworkService` запущен

**When** клиент вызывает `NetworkService/Upsert` с:
- `networks[0].metadata.name = "Net_PROD!"` (uppercase, спецсимволы)
- `networks[0].metadata.folderId = <folder-uid>`

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "networks[0].metadata.name"`
**And** `field_violations[0].description` содержит правило (`^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$`)

### I2. Upsert Subnet с невалидным cidr_block — INVALID_ARGUMENT

**ID:** 0.3-I2

**Given** Network `<net-uid>` существует, mock `FolderExists` → true

**When** клиент вызывает `SubnetService/Upsert` с:
- `subnets[0].metadata.name = "subnet-bad-cidr"`
- `subnets[0].metadata.folderId = <folder-uid>`
- `subnets[0].spec.network_id = <net-uid>`
- `subnets[0].spec.cidr_block = "not-a-cidr"` (невалидный CIDR)
- `subnets[0].spec.zone_id = "kacho-zone-a"`

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "subnets[0].spec.cidr_block"`
**And** `field_violations[0].description` описывает ожидаемый формат CIDR

### I3. Upsert Subnet с отсутствующим cidr_block — INVALID_ARGUMENT

**ID:** 0.3-I3

**Given** Network `<net-uid>` существует, mock `FolderExists` → true

**When** клиент вызывает `SubnetService/Upsert` с:
- `subnets[0].metadata.name = "subnet-no-cidr"`
- `subnets[0].metadata.folderId = <folder-uid>`
- `subnets[0].spec.network_id = <net-uid>`
- `subnets[0].spec.cidr_block = ""` (пустая строка)
- `subnets[0].spec.zone_id = "kacho-zone-a"`

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "subnets[0].spec.cidr_block"`

### I4. Upsert Subnet с отсутствующим zone_id — INVALID_ARGUMENT

**ID:** 0.3-I4

**Given** Network `<net-uid>` существует, mock `FolderExists` → true

**When** клиент вызывает `SubnetService/Upsert` с:
- `subnets[0].spec.cidr_block = "10.0.0.0/24"`
- `subnets[0].spec.zone_id = ""` (пустая строка)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "subnets[0].spec.zone_id"`

### I5. Upsert Network с пустым name — INVALID_ARGUMENT

**ID:** 0.3-I5

**Given** сервис `NetworkService` запущен

**When** клиент вызывает `NetworkService/Upsert` с:
- `networks[0].metadata.name = ""` (пустая строка)
- `networks[0].metadata.folderId = <folder-uid>`

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "networks[0].metadata.name"`

### I6. Delete несуществующего Network — NOT_FOUND

**ID:** 0.3-I6

**Given** Network с `uid = "00000000-0000-0000-0000-000000000077"` НЕ существует

**When** клиент вызывает `NetworkService/Delete` с:
- `networks[0].metadata.uid = "00000000-0000-0000-0000-000000000077"`

**Then** gRPC статус = `NOT_FOUND`
**And** `details[]` содержит `ResourceInfo.resource_type = "Network"`, `resource_name = "00000000-0000-0000-0000-000000000077"`

### I7. Delete несуществующего Subnet — NOT_FOUND

**ID:** 0.3-I7

**Given** Subnet с `uid = "00000000-0000-0000-0000-000000000078"` НЕ существует

**When** клиент вызывает `SubnetService/Delete` с:
- `subnets[0].metadata.uid = "00000000-0000-0000-0000-000000000078"`

**Then** gRPC статус = `NOT_FOUND`
**And** `details[]` содержит `ResourceInfo.resource_type = "Subnet"`

### I8. Upsert SecurityGroupRule с невалидным direction — INVALID_ARGUMENT

**ID:** 0.3-I8

**Given** mock `FolderExists` → true

**When** клиент вызывает `SecurityGroupService/Upsert` с:
- `security_groups[0].metadata.name = "sg-bad-rule"`
- `security_groups[0].metadata.folderId = <folder-uid>`
- `security_groups[0].spec.rules[0].direction = "SIDEWAYS"` (невалидный direction)
- `security_groups[0].spec.rules[0].protocol = "TCP"`
- `security_groups[0].spec.rules[0].port_range_min = 80`
- `security_groups[0].spec.rules[0].port_range_max = 80`

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "security_groups[0].spec.rules[0].direction"`
**And** допустимые значения: INGRESS, EGRESS

### I9. Upsert SecurityGroupRule с невалидным cidr_block в правиле — INVALID_ARGUMENT

**ID:** 0.3-I9

**Given** mock `FolderExists` → true

**When** клиент вызывает `SecurityGroupService/Upsert` с:
- `security_groups[0].spec.rules[0].direction = "INGRESS"`
- `security_groups[0].spec.rules[0].protocol = "TCP"`
- `security_groups[0].spec.rules[0].cidr_blocks = ["not-a-cidr"]`
- `security_groups[0].spec.rules[0].port_range_min = 80`
- `security_groups[0].spec.rules[0].port_range_max = 80`

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "security_groups[0].spec.rules[0].cidr_blocks[0]"`

### I10. Upsert StaticRoute с невалидным destination_prefix — INVALID_ARGUMENT

**ID:** 0.3-I10

**Given** Network `<net-uid>` существует, mock `FolderExists` → true

**When** клиент вызывает `RouteTableService/Upsert` с:
- `route_tables[0].spec.network_id = <net-uid>`
- `route_tables[0].spec.static_routes[0].destination_prefix = "bad-prefix"` (невалидный CIDR)
- `route_tables[0].spec.static_routes[0].next_hop_address = "10.0.0.1"`

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "route_tables[0].spec.static_routes[0].destination_prefix"`

### I11. Upsert StaticRoute с невалидным next_hop_address — INVALID_ARGUMENT

**ID:** 0.3-I11

**Given** Network `<net-uid>` существует, mock `FolderExists` → true

**When** клиент вызывает `RouteTableService/Upsert` с:
- `route_tables[0].spec.static_routes[0].destination_prefix = "10.0.0.0/8"`
- `route_tables[0].spec.static_routes[0].next_hop_address = "not-an-ip"` (невалидный IP)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "route_tables[0].spec.static_routes[0].next_hop_address"`

### I12. Upsert Address с невалидным address_type — INVALID_ARGUMENT

**ID:** 0.3-I12

**Given** mock `FolderExists` → true

**When** клиент вызывает `AddressService/Upsert` с:
- `addresses[0].metadata.name = "addr-bad-type"`
- `addresses[0].metadata.folderId = <folder-uid>`
- `addresses[0].spec.address_type = "FLOATING"` (невалидный тип)
- `addresses[0].spec.zone_id = "kacho-zone-a"`

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "addresses[0].spec.address_type"`
**And** допустимые значения в 0.3: только `EXTERNAL` (`INTERNAL` не поддерживается в 0.3 — отложено)

### I13. Concurrent update Network — ABORTED (OCC protection)

**ID:** 0.3-I13

**Given** Network `"shared-net"` существует с `metadata.resourceVersion = <R>`

**When** два параллельных gRPC-вызова `NetworkService/Upsert` для одной и той же Network отправляются одновременно:
- вызов A: `spec.description = "Version A"`
- вызов B: `spec.description = "Version B"`

**Then** ровно один вызов завершается с gRPC статусом `OK`
**And** второй вызов завершается с gRPC статусом `ABORTED`
**And** в БД ровно одна запись `"shared-net"` с description победившего вызова

### I14. Upsert с клиентски заданным metadata.uid — сервер игнорирует

**ID:** 0.3-I14

**Given** сервис `NetworkService` запущен
**And** Network с именем `"net-test-uid"` не существует

**When** клиент вызывает `NetworkService/Upsert` с:
- `networks[0].metadata.name = "net-test-uid"`
- `networks[0].metadata.folderId = <folder-uid>`
- `networks[0].metadata.uid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeef"` (клиент задаёт uid)

**Then** gRPC статус = OK
**And** `metadata.uid` в ответе **не равен** `"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeef"` — сервер присвоил новый UUID v4, проигнорировав клиентский
**And** Network создана в БД с server-assigned uid
**And** в `resource_events` событие `event_type = 'ADDED'` с server-assigned uid

*Зафиксировано:* вариант A (игнорирование), аналогично 0.2-G1a. Server-managed поля (`metadata.uid`, `metadata.creationTimestamp`, `metadata.resourceVersion`, `status`) сервер всегда выставляет самостоятельно, клиентские значения не применяются и не вызывают ошибки.

### I15. List с невалидным page_size — INVALID_ARGUMENT

**ID:** 0.3-I15

**Given** сервис `NetworkService` запущен

**When** клиент вызывает `NetworkService/List` с:
- `page_size = 9999` (> 1000)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[].field_violations[0].field = "page_size"`
**And** `field_violations[0].description` содержит максимальное значение 1000

### I16. Watch с невалидным resourceVersion — INVALID_ARGUMENT

**ID:** 0.3-I16

**Given** сервис `SubnetService` запущен

**When** клиент открывает Watch стрим с:
- `resourceVersion = "abc"` (не десятичное число)

**Then** сервер немедленно возвращает `INVALID_ARGUMENT`
**And** `details[].field_violations[0].field = "resource_version"`

### I17. Upsert Network с заполненным полем status — сервер игнорирует

**ID:** 0.3-I17

**Given** сервис `NetworkService` запущен
**And** Network с именем `"net-status-test"` не существует

**When** клиент вызывает `NetworkService/Upsert` с:
- `networks[0].metadata.name = "net-status-test"`
- `networks[0].metadata.folderId = <folder-uid>`
- `networks[0].spec.display_name = "Test Network"`
- `networks[0].status.state = "DELETING"` (клиент пытается установить status)

**Then** gRPC статус = OK
**And** `status.state` в ответе = `"ACTIVE"` (сервер выставил корректный статус, проигнорировал клиентский `"DELETING"`)
**And** Network создана в БД с `status.state = "ACTIVE"`
**And** в `resource_events` событие `event_type = 'ADDED'`

*Зафиксировано:* `status` — server-managed поле, игнорируется на входе (не вызывает `INVALID_ARGUMENT`). Сервер всегда выставляет статус самостоятельно согласно бизнес-логике. Это соответствует K8s-конвенции и политике server-managed fields из §0.

### I18. Concurrent create-collision (одно имя, один folderId) — ABORTED

**ID:** 0.3-I18

**Given** сервис `NetworkService` запущен
**And** Network с именем `"race-net"` в Folder `<folder-uid>` **не существует**

**When** два параллельных gRPC-вызова `NetworkService/Upsert` одновременно пытаются **создать** Network с одним и тем же `name = "race-net"` и `folderId = <folder-uid>`:
- вызов A: `spec.display_name = "Race A"`
- вызов B: `spec.display_name = "Race B"`

**Then** ровно один вызов завершается с gRPC статусом `OK` (Network создана с его display_name)
**And** второй вызов завершается с gRPC статусом `ABORTED` (concurrent create collision на UNIQUE constraint `(folder_id, name)`)
**And** в БД ровно одна запись `"race-net"` в данном Folder
**And** `ALREADY_EXISTS` **не используется** — только `ABORTED` с retry-семантикой

*Реализация:* сервер перехватывает `pgcode.UniqueViolation` при INSERT и конвертирует в `ABORTED`. Клиент должен повторить запрос (reread → retry).

### I19. Upsert Subnet с cidr_block где установлены host-bits — INVALID_ARGUMENT

**ID:** 0.3-I19

**Given** Network `<net-uid>` существует, mock `FolderExists` → true

**When** клиент вызывает `SubnetService/Upsert` с:
- `subnets[0].metadata.name = "subnet-host-bits"`
- `subnets[0].metadata.folderId = <folder-uid>`
- `subnets[0].spec.network_id = <net-uid>`
- `subnets[0].spec.cidr_block = "10.0.0.1/24"` (host-bits установлены: network address должен быть `10.0.0.0/24`)
- `subnets[0].spec.zone_id = "kacho-zone-a"`

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "subnets[0].spec.cidr_block"`
**And** `field_violations[0].description` указывает на требование сетевого адреса (`10.0.0.0/24`)

*Реализация:* валидация через `net.ParseCIDR`; если `ip != network` (host-bits set) — `INVALID_ARGUMENT`.

---

## 10. Группа J — End-to-end smoke (port-forward, full flow)

Сценарии группы J выполняются через `kubectl port-forward` против реального кластера kind. Bash-скрипты в `kacho-deploy/e2e/0.3/`. **API Gateway отсутствует в 0.3** — прямой gRPC через `localhost:9090`.

### J1. Создание Network → List показывает новую Network

**ID:** 0.3-J1

**Given** `kacho-vpc` Pod запущен в namespace `kacho` и прошёл readiness probe
**And** `kacho-resource-manager` Pod запущен (для cross-service вызова FolderExists)
**And** Port-forward на vpc: `kubectl port-forward svc/vpc 9090:9090 -n kacho` активен
**And** Default Folder существует с `uid = <folder-uid>` (получен через resource-manager port-forward)

**When** выполняется скрипт `kacho-deploy/e2e/0.3/J1-network-upsert-list.sh`:
```bash
# шаг 1: получить folder uid через resource-manager
FOLDER_UID=$(grpcurl -plaintext -d '{}' localhost:9091 \
  kacho.cloud.resourcemanager.v1.FolderService/List \
  | jq -r '.folders[0].metadata.uid')

# шаг 2: создать Network
grpcurl -plaintext \
  -d "{\"networks\":[{\"metadata\":{\"name\":\"e2e-net\",\"folder_id\":\"$FOLDER_UID\"},\"spec\":{\"display_name\":\"E2E Network\"}}]}" \
  localhost:9090 \
  kacho.cloud.vpc.v1.NetworkService/Upsert

# шаг 3: List и проверить
grpcurl -plaintext \
  -d "{\"selectors\":[{\"field_selector\":{\"folder_id\":\"$FOLDER_UID\"}}]}" \
  localhost:9090 \
  kacho.cloud.vpc.v1.NetworkService/List
```

**Then** шаг 1 возвращает непустой FOLDER_UID
**And** шаг 2 возвращает gRPC OK с заполненным `metadata.uid` и `status.state = "ACTIVE"`
**And** шаг 3 содержит массив `networks[]` с объектом `"name": "e2e-net"`

### J2. Network → Subnet full flow

**ID:** 0.3-J2

**Given** `kacho-vpc` запущен и `port-forward` активен
**And** Default Folder существует (`<folder-uid>`)

**When** выполняется скрипт `kacho-deploy/e2e/0.3/J2-network-subnet-flow.sh`:
```bash
# шаг 1: создать Network
NET_UID=$(grpcurl -plaintext \
  -d "{\"networks\":[{\"metadata\":{\"name\":\"e2e-net-full\",\"folder_id\":\"$FOLDER_UID\"},\"spec\":{}}]}" \
  localhost:9090 kacho.cloud.vpc.v1.NetworkService/Upsert \
  | jq -r '.networks[0].metadata.uid')

# шаг 2: создать Subnet в этой Network
grpcurl -plaintext \
  -d "{\"subnets\":[{\"metadata\":{\"name\":\"e2e-subnet-a\",\"folder_id\":\"$FOLDER_UID\"},\"spec\":{\"network_id\":\"$NET_UID\",\"cidr_block\":\"10.10.0.0/24\",\"zone_id\":\"kacho-zone-a\"}}]}" \
  localhost:9090 kacho.cloud.vpc.v1.SubnetService/Upsert

# шаг 3: List Subnets
grpcurl -plaintext \
  -d "{\"selectors\":[{\"field_selector\":{\"folder_id\":\"$FOLDER_UID\"}}]}" \
  localhost:9090 kacho.cloud.vpc.v1.SubnetService/List
```

**Then** шаг 1 возвращает непустой NET_UID
**And** шаг 2 возвращает gRPC OK, `subnets[0].status.state = "ACTIVE"`, `subnets[0].spec.network_id = $NET_UID`
**And** шаг 3 возвращает массив с `"name": "e2e-subnet-a"`

### J3. Delete Network с зависимым Subnet → FAILED_PRECONDITION

**ID:** 0.3-J3

**Given** Network `"e2e-net-full"` с `uid = <net-uid>` и Subnet `"e2e-subnet-a"` с `network_id = <net-uid>` созданы (J2)

**When** выполняется скрипт `kacho-deploy/e2e/0.3/J3-delete-blocked.sh`:
```bash
# попытка удалить Network с зависимым Subnet
grpcurl -plaintext \
  -d "{\"networks\":[{\"metadata\":{\"uid\":\"$NET_UID\"}}]}" \
  localhost:9090 kacho.cloud.vpc.v1.NetworkService/Delete
```

**Then** команда завершается с ненулевым кодом
**And** stdout/stderr содержит `FAILED_PRECONDITION`
**And** содержит `HAS_DEPENDENT_RESOURCES`

### J4. Watch Subnet показывает события при создании

**ID:** 0.3-J4

**Given** `kacho-vpc` запущен и `port-forward` активен

**When** выполняется скрипт `kacho-deploy/e2e/0.3/J4-watch-subnet.sh`:
```bash
# Запускаем Watch в фоне
grpcurl -plaintext -d '{}' localhost:9090 \
  kacho.cloud.vpc.v1.SubnetService/Watch \
  > /tmp/watch_subnet.json &
WATCH_PID=$!
sleep 1

# Создаём Subnet
grpcurl -plaintext \
  -d "{\"subnets\":[{\"metadata\":{\"name\":\"watch-subnet-01\",\"folder_id\":\"$FOLDER_UID\"},\"spec\":{\"network_id\":\"$NET_UID\",\"cidr_block\":\"10.20.0.0/24\",\"zone_id\":\"kacho-zone-a\"}}]}" \
  localhost:9090 kacho.cloud.vpc.v1.SubnetService/Upsert

# Изменяем description
grpcurl -plaintext \
  -d "{\"subnets\":[{\"metadata\":{\"name\":\"watch-subnet-01\",\"folder_id\":\"$FOLDER_UID\"},\"spec\":{\"network_id\":\"$NET_UID\",\"cidr_block\":\"10.20.0.0/24\",\"zone_id\":\"kacho-zone-a\",\"description\":\"Updated\"}}]}" \
  localhost:9090 kacho.cloud.vpc.v1.SubnetService/Upsert

# Удаляем
grpcurl -plaintext \
  -d "{\"subnets\":[{\"metadata\":{\"name\":\"watch-subnet-01\",\"folder_id\":\"$FOLDER_UID\"}}]}" \
  localhost:9090 kacho.cloud.vpc.v1.SubnetService/Delete

sleep 1
kill $WATCH_PID
```

**Then** `/tmp/watch_subnet.json` содержит минимум 3 события:
1. `{"type":"ADDED", "subnet":{"metadata":{"name":"watch-subnet-01",...},"status":{"state":"ACTIVE"}}}`
2. `{"type":"MODIFIED", ...}`
3. `{"type":"DELETED", ...}`
**And** events идут в порядке возрастания `resourceVersion`

### J5. Address Upsert → List → Delete full flow

**ID:** 0.3-J5

**Given** `kacho-vpc` запущен, port-forward активен, `<folder-uid>` получен

**When** выполняется скрипт `kacho-deploy/e2e/0.3/J5-address-flow.sh`:
```bash
# создать Address
ADDR_UID=$(grpcurl -plaintext \
  -d "{\"addresses\":[{\"metadata\":{\"name\":\"e2e-addr-01\",\"folder_id\":\"$FOLDER_UID\"},\"spec\":{\"address_type\":\"EXTERNAL\",\"zone_id\":\"kacho-zone-a\"}}]}" \
  localhost:9090 kacho.cloud.vpc.v1.AddressService/Upsert \
  | jq -r '.addresses[0].metadata.uid')

# List проверка
grpcurl -plaintext \
  -d "{\"selectors\":[{\"field_selector\":{\"folder_id\":\"$FOLDER_UID\"}}]}" \
  localhost:9090 kacho.cloud.vpc.v1.AddressService/List

# Delete
grpcurl -plaintext \
  -d "{\"addresses\":[{\"metadata\":{\"uid\":\"$ADDR_UID\"}}]}" \
  localhost:9090 kacho.cloud.vpc.v1.AddressService/Delete
```

**Then** Upsert возвращает gRPC OK с `addresses[0].status.state = "RESERVED"` и `addresses[0].status.allocated_ipv4` не пустым
**And** List содержит Address с `"name": "e2e-addr-01"`
**And** Delete возвращает gRPC OK

### J6. Helm chart vpc деплоится и проходит readiness probe

**ID:** 0.3-J6

**Given** `kind`-кластер поднят (`make dev-up`)
**And** В `kacho-deploy/helm/` присутствует chart для `vpc`
**And** Image `prorobotech/kacho-vpc:0.3.0` доступен (через `kind load` или локальный registry)

**When** выполняется `helm upgrade --install vpc kacho-deploy/helm/vpc/ -n kacho --values kacho-deploy/helm/vpc/values.dev.yaml`

**Then** Pod `vpc-*` переходит в статус `Running` и `Ready 1/1` в течение 60 секунд
**And** `kubectl exec -n kacho ... -- grpc_health_probe -addr :9090` возвращает `status: SERVING`
**And** БД `kacho_vpc` содержит таблицы `networks`, `subnets`, `security_groups`, `security_group_rules`, `route_tables`, `static_routes`, `addresses`, `resource_events`

---

## 11. Definition of Done

Sub-итерация 0.3 считается **завершённой**, когда **все** условия выполнены:

1. **Все сценарии §1–§10** (A1–A8, B1–B8, C1–C10, D1–D6, E1–E5, F1–F8, G1–G7, H1–H5, I1–I19, J1–J6) покрыты исполняемыми тестами:
   - Integration-тесты (testcontainers-Postgres) в `kacho-vpc/internal/service/*_acceptance_test.go` — все зелёные.
   - E2E bash-скрипты в `kacho-deploy/e2e/0.3/*.sh` — все зелёные при запуске `make e2e-test PHASE=0.3`.
   - A1 и A2 трассируются через CI-шаги `buf-lint` / `buf-breaking` в `kacho-proto/.github/workflows/ci.yaml` (не Go-тест-функции).

2. **Proto** `kacho-proto/proto/kacho/cloud/vpc/v1/` содержит:
   - `network.proto` — Network, NetworkUpsert/Delete/List/WatchRequest/Response
   - `subnet.proto` — Subnet с `spec.network_id`, `spec.cidr_block`, `spec.zone_id`
   - `security_group.proto` — SecurityGroup + SecurityGroupRule (inline)
   - `route_table.proto` — RouteTable + StaticRoute (inline)
   - `address.proto` — Address с lifecycle status (RESERVED/IN_USE/RELEASED) и `status.allocated_ipv4`
   - `internal.proto` — `VpcInternalService` с методами NetworkExists, SubnetExists, SecurityGroupExists, RouteTableExists, AddressExists + UpdateStatus для Address
   - `buf lint` и `buf breaking` — зелёные

3. **kacho-vpc** реализован:
   - `cmd/vpc/main.go` — composition root
   - `internal/domain/` — entity-типы для всех 5 ресурсов + SecurityGroupRule + StaticRoute
   - `internal/service/` — NetworkService, SubnetService, SecurityGroupService, RouteTableService, AddressService (use-case логика с port-интерфейсами)
   - `internal/clients/` — `ResourceManagerClient` (реализует port-интерфейс FolderExistsChecker), импортирует grpc-stubs из kacho-proto
   - `internal/repo/` — sqlc-generated queries + handwritten filter-builder
   - `internal/handler/handler.go` — gRPC-хендлеры для публичных RPC (thin transport layer)
   - `internal/handler/internal_handler.go` — гRPC-хендлеры для Internal RPC; **не регистрируется** в api-gateway
   - `migrations/` — миграции `kacho_vpc` включая sync из corelib/migrations/common/
   - `deploy/` — Dockerfile, Helm chart values

4. **Clean Architecture** соблюдена:
   - `domain/` не импортирует pgx, grpc-stubs, sqlc-типы
   - `service/` определяет port-интерфейсы (`NetworkRepo`, `SubnetRepo`, `FolderExistsChecker`) и импортирует только `domain`
   - `handler/` — тонкий транспортный слой, никакой бизнес-логики
   - Единственное место wiring — `cmd/vpc/main.go`

5. **Cross-service validation** работает:
   - При Upsert любого VPC-ресурса вызывается `FolderExists` через resource-manager gRPC-client
   - При недоступности resource-manager возвращается `UNAVAILABLE`
   - При `exists=false` возвращается `INVALID_ARGUMENT` с полем `metadata.folderId`

6. **Address lifecycle** синхронный:
   - При Upsert `status.state = "RESERVED"` выставляется сразу в той же транзакции
   - `status.allocated_ipv4` назначается сервером (симулированный IP)

7. **Intra-domain cascade** работает:
   - Delete SecurityGroup → SecurityGroupRule удалены (same-DB FK CASCADE)
   - Delete RouteTable → StaticRoute удалены (same-DB FK CASCADE)
   - Upsert SecurityGroup/RouteTable — правила/маршруты атомарно заменяются

8. **Helm chart** для `vpc` добавлен в `kacho-deploy/helm/` и в `helm/umbrella/Chart.yaml`

9. **CI** всех затронутых репо зелёный:
   - `kacho-proto`: `buf-lint`, `buf-breaking`, `buf-generate` (без диффа в gen/)
   - `kacho-vpc`: `golangci-lint`, `go test ./...` (включая integration с testcontainers)
   - `kacho-deploy`: `helm lint`

10. **Naming conventions** соблюдены:
    - Proto package: `kacho.cloud.vpc.v1`
    - DB: `kacho_vpc`
    - Env: `KACHO_VPC_*`
    - k8s service: `vpc.kacho.svc.cluster.local`
    - Docker image: `prorobotech/kacho-vpc:0.3.0`

11. `kacho-workspace/docs/specs/CHANGELOG.md` содержит запись о завершении sub-phase 0.3.

12. Тег `kacho-vpc:0.3.0` поставлен на `main` каждого затронутого репо.

13. **kacho-corelib reuse**: `kacho-vpc` импортирует `kacho-corelib/{watch,outbox,selector,migrations/common}` без дублирования per-service. Проверяется через `go mod graph` — нет собственных копий этих компонентов.

---

## 12. Вопросы к acceptance-reviewer (Open questions)

*Все вопросы из round 1 закрыты. Открытых вопросов нет.*

| Вопрос | Решение | Зафиксировано в |
|--------|---------|-----------------|
| Q1: `network_id` в FieldSelector | Вариант (c): через `FieldSelector.refs[kind=Network, uid=<net-uid>]` | §0 соглашения, C6 |
| Q2: CIDR-валидация | `net.ParseCIDR` + host-bits-set → `INVALID_ARGUMENT` | §0 соглашения, I2, I19 |
| Q3: симулированный IP | `203.0.113.0/24` (TEST-NET-3, RFC 5737) + UNIQUE constraint | §0 соглашения, F1 |
| Q4: SecurityGroupRule.id | Server-assigned UUID, регенерируется при каждом Upsert (full-replace) | §0 соглашения, D3 |
| Q5: concurrent create → ABORTED | `ABORTED` (retry); `ALREADY_EXISTS` не используется | §0 соглашения, I18 |
| Q6: INTERNAL Address | Не входит в 0.3; только `EXTERNAL` поддерживается | §0 «Что НЕ входит», I12 |

---

**После approve этого документа:**
- Конвертация сценариев в тесты — задача субагента `integration-tester`.
- План реализации — `kacho-workspace/docs/plans/sub-phase-0.3-vpc-plan.md` (через `superpowers:writing-plans`), каждый шаг плана ссылается на идентификаторы сценариев из этого документа.
- Proto-контракт `kacho-proto/proto/kacho/cloud/vpc/v1/` проверяет субагент `proto-api-reviewer` после реализации.
- Схема миграций `kacho_vpc` проверяет субагент `db-architect-reviewer` после реализации.
- После реализации и code-review — финальный smoke через `make e2e-test PHASE=0.3` выполняет заказчик.
