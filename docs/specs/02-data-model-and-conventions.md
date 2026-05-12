# Kachō — Модель данных и конвенции

**Документ:** 02 / 5

## 1. Resource envelope

Все ресурсы Kachō имеют единый envelope:

```json
{
  "metadata": { ... },
  "spec":     { ... },
  "status":   { ... },
  "refs":     [ ... ]
}
```

| Блок | Кто пишет | Через что | Семантика |
|---|---|---|---|
| `metadata` | пользователь (часть полей) + сервер (часть полей) | разные RPC, см. ниже | identity + control signals + теги |
| `spec` | пользователь | `/upsert` | желаемая конфигурация ресурса |
| `status` | **только** reconciler | internal `/upd-status` | наблюдаемое состояние |
| `refs[]` | сервер | автоматически в `/list` и `/watch` ответах | обратные ссылки на связанные ресурсы (там где есть смысл) |

В `/upsert`-теле клиент НЕ может задать `status` или server-managed metadata-поля — они игнорируются (или отвечается `invalidArgument`, конкретное поведение — параметр сервиса).

## 2. Структура `metadata`

### 2.1 Поля `metadata` по уровню ресурса

| Поле | Тип | Кто пишет | Org | Cloud | Folder | Domain Resource |
|---|---|---|---|---|---|---|
| `uid` | UUID v4 | сервер при первом upsert | ✓ | ✓ | ✓ | ✓ |
| `name` | string (regex `^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$`) | пользователь | ✓ | ✓ | ✓ | ✓ |
| `organizationId` | UUID | сервер по контексту upsert | — | ✓ | ✓ | ✓ |
| `cloudId` | UUID | сервер | — | — | ✓ | ✓ |
| `folderId` | UUID | сервер | — | — | — | ✓ |
| `labels` | `map<string,string>` | пользователь | ✓ | ✓ | ✓ | ✓ |
| `annotations` | `map<string,string>` | пользователь | ✓ | ✓ | ✓ | ✓ |
| `creationTimestamp` | timestamp | сервер при создании | ✓ | ✓ | ✓ | ✓ |
| `resourceVersion` | string (decimal) | сервер при каждом write | ✓ | ✓ | ✓ | ✓ |
| `generation` | int64 | сервер при каждом spec-change | — | — | — | ✓ |
| `deletionTimestamp` | timestamp NULLABLE | сервер при `/delete` | ✓ | ✓ | ✓ | ✓ |
| `finalizers[]` | string[] | server-managed | — | — | — | ✓ (где есть cleanup) |
| `restartedAt` | timestamp NULLABLE | сервер при `/restart` | — | — | — | только Instance |

`organizationId`/`cloudId`/`folderId` денормализованы для быстрого filtering (selector по `folderId` без join). При upsert сервер заполняет цепочку, проверив существование parent.

### 2.2 Identification policy

Пользователь идентифицирует ресурс одним из двух способов в `/delete`, `/upd-status` (internal), `/restart`:

- **`metadata.uid`** — UUID, гарантированно уникальный.
- **Цепочка `metadata.name` + scope-ID-поля**:
  - Organization: `name`.
  - Cloud: `name + organizationId`.
  - Folder: `name + cloudId`.
  - Domain resource: `name + folderId`.

В `/upsert` upsert-семантика: если цепочка идентификации существует — обновление, иначе создание (новый `uid`).

### 2.3 Уникальность `name`

| Уровень | Уникален в пределах |
|---|---|
| Organization | глобально |
| Cloud | `organizationId` |
| Folder | `cloudId` |
| Domain resource | `folderId + resource_kind` |

Реализация: UNIQUE-constraint на уровне БД (см. секцию «Schema» ниже).

## 3. Структура `spec`

`spec` — конфигурация ресурса. Имена и типы полей берутся из соответствующего YC ресурса с camelCase JSON / snake_case proto. Полный список — отдельной структурой per-resource (приведу для примера один ресурс ниже; остальные следуют тому же паттерну).

### Пример: `Compute Instance.spec`

```json
{
  "displayName":         "string",
  "description":         "string",
  "platformId":          "standard-v3",
  "zoneId":              "kacho-zone-a",
  "resources": {
    "cores":          4,
    "memory":         "8Gi",
    "coreFraction":   100,
    "gpus":           0
  },
  "bootDisk": {
    "diskId":          "<UUID>",
    "deviceName":      "boot",
    "autoDelete":      true
  },
  "secondaryDisks": [ { "diskId": "...", "deviceName": "...", "autoDelete": false } ],
  "networkInterfaces": [
    {
      "subnetId":        "<UUID>",
      "primaryV4Address": { "address": "10.0.0.5" },
      "primaryV6Address": null,
      "securityGroupIds": [ "<UUID>", ... ]
    }
  ],
  "schedulingPolicy":  { "preemptible": false },
  "metadata":          { "user-data": "..." },
  "fqdn":              "string",
  "desiredPowerState": "RUNNING"
}
```

Конкретные поля per ресурс — для всех Network/Subnet/SG/RouteTable/Address/Instance/Disk/Image/Snapshot/NLB/TargetGroup — будут описаны в детальном плане каждой sub-итерации (`04-roadmap-and-phasing.md`).

## 4. Структура `status`

`status` присутствует у ресурсов с lifecycle (`Instance`, `Disk`, `Snapshot`, `NLB`, `TargetGroup`) и у ресурсов с server-вычисляемыми полями (`Address.allocatedIPv4`).

### Пример: `Compute Instance.status`

```json
{
  "state":                    "RUNNING",
  "stateLastTransitionAt":    "2026-05-01T12:00:00Z",
  "ips": {
    "internal": "10.0.0.5",
    "external": "203.0.113.5"
  },
  "fqdn":                      "instance-foo.kacho.local",
  "hostId":                    "simulated-host-1",
  "lastRestartCompletedAt":    "2026-05-01T11:30:00Z",
  "conditions": [
    { "type": "Ready",       "status": "True",  "reason": "AllSystemsGo", "lastTransitionTime": "..." },
    { "type": "DiskAttached", "status": "True", "reason": "BootDiskAttached", "lastTransitionTime": "..." }
  ]
}
```

`conditions[]` — k8s-style массив текущих condition-ов. Полезно для диагностики и UI.

Lifecycle-state enum (`status.state`) per resource:

| Ресурс | enum |
|---|---|
| Instance | `PROVISIONING`, `RUNNING`, `STOPPING`, `STOPPED`, `STARTING`, `RESTARTING`, `UPDATING`, `ERROR`, `DELETING` |
| Disk | `CREATING`, `READY`, `ATTACHING`, `DETACHING`, `ERROR`, `DELETING` |
| Snapshot | `CREATING`, `READY`, `ERROR`, `DELETING` |
| Image | `READY` (read-only, всегда) |
| NLB | `CREATING`, `ACTIVE`, `UPDATING`, `ERROR`, `DELETING` |
| TargetGroup | `CREATING`, `READY`, `UPDATING`, `DELETING` |
| Address | `RESERVED`, `IN_USE`, `RELEASED` |
| Network/Subnet/SG/RouteTable | `ACTIVE`, `DELETING` (минимальный) |

## 5. Refs (обратные ссылки)

`refs[]` — server-populated, появляется только в ответах `/list` и `/watch`. Тип:

```json
{ "name": "...", "uid": "...", "kind": "Instance" /* enum */ }
```

Применимость per ресурс:
- `Network` → refs к `Subnet` (внутрисервисный refs, дешёвый), к `Instance` (cross-service, опционально и costly — может быть не включён по умолчанию).
- `Subnet` → refs к `Instance`.
- `SecurityGroup` → refs к `Instance`.
- `Folder` → refs к ресурсам в нём (агрегированно по типам и счётчикам, не по полному списку).

В первой реализации `refs[]` минимально, расширяется по требованию.

## 6. Стандартные API-методы

### 6.1 Public (через api-gateway)

| RPC | Описание |
|---|---|
| `Upsert(<R>UpsertRequest)` → `<R>UpsertResponse` | Batch payload `<r>: [<R>{metadata, spec}, ...]`. Возвращает массив с заполненными `metadata.uid`/`creationTimestamp`/`resourceVersion`. |
| `Delete(<R>DeleteRequest)` → `<R>DeleteResponse` | Batch payload `<r>: [{metadata: {uid \| name+scope}}, ...]`. Сервер выставляет `metadata.deletionTimestamp`. Если `finalizers[]` пуст — ресурс физически удаляется в той же транзакции; иначе помечен и финальное удаление после finalizers cleanup. |
| `List(<R>ListRequest)` → `<R>ListResponse` | `selectors[]` (см. ниже). Возвращает массив + `resourceVersion` (snapshot version) для последующего Watch. |
| `Watch(<R>WatchRequest)` → server-stream `<R>WatchEvent` | `selectors[]` + `resourceVersion`. Стрим событий `{type: ADDED|MODIFIED|DELETED, <r>: <R>}`. |
| `Restart(<R>RestartRequest)` → `<R>RestartResponse` | Только для Instance. Server выставляет `metadata.restartedAt`. |

### 6.2 Internal (между сервисами, не наружу)

| RPC | Описание |
|---|---|
| `<R>Internal.UpdateStatus(<R>UpdateStatusRequest)` | Reconciler пишет в `status`. Идемпотентен (повторный вызов с тем же status — no-op). |
| `<R>Internal.Exists(req: {uid})` → `{exists: bool}` | Cross-service ref-validation. |
| `<R>Internal.HasDependents(req: {uid})` → `{hasDependents: bool, kinds: [...]}` | Для валидации удаления. |

`api-gateway` НЕ маршрутизирует `Internal.*` методы наружу (allowlist-фильтр в gateway-конфиге).

## 7. Селекторы

```protobuf
message Selector {
  FieldSelector field_selector = 1;
  map<string, string> label_selector = 2;
}

message FieldSelector {
  string name             = 1;
  string organization_id  = 2;
  string cloud_id         = 3;
  string folder_id        = 4;
  repeated ResourceRef refs = 5;
}

message <R>ListRequest {
  repeated Selector selectors = 1;
  // pagination
  string  page_token = 10;
  int32   page_size  = 11;
}
```

Логика комбинирования:
- **Внутри одного `Selector`** — `field_selector` AND `label_selector` (все указанные поля должны совпасть).
- **Между `selectors[]`** — OR (ресурс попадает, если соответствует хотя бы одному).

Реализация фильтра в SQL — генерация `WHERE`-clause по AST селектора. Параметризованные запросы (никакой конкатенации). Парсер живёт в `kacho-corelib/selector/`.

### Пагинация

Курсор-based: `page_token` = base64(json{`last_resource_version`, `last_uid`}). Серверный SQL: `WHERE (resource_version, uid) > ($lastRV, $lastUID) ORDER BY resource_version, uid LIMIT $pageSize`.

`page_size` ≤ 1000.

## 8. resourceVersion и Watch

### 8.1 resourceVersion

Per-database монотонная sequence:

```sql
CREATE SEQUENCE resource_version_seq;
```

Каждое мутирующее действие (insert/update/delete-tombstone) на любой ресурс сервиса поднимает `resource_version` через `nextval('resource_version_seq')`. В рамках одной service-БД — монотонно возрастающая глобальная версия.

Хранится:
- В колонке `resource_version BIGINT` каждой ресурсной таблицы — последняя версия этого ресурса.
- В outbox-таблице `resource_events.resource_version BIGINT PRIMARY KEY` — версия конкретного события.

Возвращается клиенту в `metadata.resourceVersion` (как decimal-строка, K8s-style).

### 8.2 Outbox таблица

В каждой service-БД:

```sql
CREATE TABLE resource_events (
  resource_version BIGINT      PRIMARY KEY DEFAULT nextval('resource_version_seq'),
  event_type       TEXT        NOT NULL CHECK (event_type IN ('ADDED', 'MODIFIED', 'DELETED')),
  resource_kind    TEXT        NOT NULL,
  resource_uid     UUID        NOT NULL,
  data             BYTEA,                    -- protobuf-encoded full resource (NULL для DELETED-tombstone после finalizers)
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX resource_events_kind_rv_idx
  ON resource_events (resource_kind, resource_version);
CREATE INDEX resource_events_cleanup_idx
  ON resource_events (created_at);
```

Каждый `/upsert`, `/delete`, `/upd-status` в **одной транзакции**:
1. Меняет ресурсную таблицу.
2. INSERT в `resource_events` с `event_type` и encoded `data`.
3. После commit: `pg_notify('kacho_<svc>', '')` (только wake-up, без payload).

### 8.3 In-process Watch Hub

В каждой реплике сервиса при старте поднимается одна горутина — Watch Hub:

```
Hub state:
  cursorRV       int64                       // last delivered resource_version
  ringBuffer     [1024]Event                 // recent events for fast-replay
  subscribers    map[subscriberID]channel    // Watch streams

Hub loop:
  select {
    case <- pgNotifyCh:        // got pg_notify
    case <- time.Tick(100ms):  // poll fallback
  }
  events := SELECT * FROM resource_events
            WHERE resource_version > cursorRV
            ORDER BY resource_version ASC
            LIMIT 1000
  for ev in events:
    ringBuffer.append(ev)
    cursorRV = ev.resource_version
    for sub in subscribers:
      if matches(ev, sub.selectors):
        non-blocking send to sub.channel
```

Watch Endpoint:

```
Watch(req):
  // 1. Catch-up phase
  if req.resourceVersion < cursorRV - 1024:
    // out of ring, query outbox
    rows := SELECT * FROM resource_events
            WHERE resource_kind = X
              AND resource_version > req.resourceVersion
            ORDER BY resource_version ASC
            LIMIT 10000
    if no rows AND req.resourceVersion < (SELECT min(resource_version) FROM resource_events):
      return error.Gone(410)  // outbox retention exceeded, client must relist
    stream rows to client
  else:
    // in ring buffer
    stream ring slice to client

  // 2. Subscribe to live updates
  ch := make chan Event, 100
  hub.subscribe(ch)
  for ev := range ch:
    if matches(ev, req.selectors):
      stream ev to client
```

Ring buffer (1024 события) ускоряет catch-up для близких отстающих клиентов без хождения в outbox.

### 8.4 Cleanup

Фоновая горутина в каждой реплике сервиса, защищённая `pg_advisory_xact_lock(<svc>_cleanup_lockid)` для координации между репликами (только одна реплика в момент времени реально выполняет cleanup):

```sql
SELECT pg_advisory_xact_lock(hashtext('kacho_<svc>_cleanup'));
DELETE FROM resource_events WHERE created_at < now() - interval '1 hour';
```

Запускается каждые 5 минут.

Retention 1 час обеспечивает покрытие большинства реальных дисконнектов клиентов (рестарт сервиса, временные network glitches). Клиент с устаревшим `resourceVersion` получает `Gone 410` → должен делать `/list` → новый `/watch` от полученной snapshot-version.

### 8.5 Multi-replica behavior

Каждая реплика имеет независимый Watch Hub. Они **не координируют** state между собой:
- Каждая независимо опрашивает БД (через свой cursor + NOTIFY).
- Watch-клиенты ходят через api-gateway → load balancer → любая реплика.
- Eventually consistent (типичная разница между репликами — миллисекунды).
- При scale-out (3 реплики на сервис) пропорционально растёт количество concurrent watchers.

## 9. Soft-delete и finalizers

При `/delete`:

1. Сервер выставляет `metadata.deletionTimestamp = now()` в одной транзакции с outbox-event типа `MODIFIED`.
2. Если `metadata.finalizers[]` пуст:
   - Сразу удаляет ресурс из БД (тот же tx).
   - В outbox добавляется второй event типа `DELETED`.
3. Если `metadata.finalizers[]` непуст:
   - Ресурс остаётся в БД с `deletionTimestamp != NULL`.
   - Reconciler-ы, отвечающие за каждый finalizer, выполняют cleanup и удаляют свой finalizer из списка через `Internal.UpdateMetadata`.
   - Когда `finalizers[]` стал пустым — ресурс физически удаляется (новый event `DELETED`).

Finalizers в текущей фазе:
- `compute.kacho.io/disk-detach` (на Instance — отвязать disks перед удалением).
- `loadbalancer.kacho.io/target-deregister` (на Instance — снять с TargetGroup).
- `vpc.kacho.io/dependent-check` (на Network — убедиться нет зависимых Subnet/Instance).

Конкретные finalizers — детализируются в соответствующих под-фазах (см. `04-roadmap-and-phasing.md`).

## 10. Per-service schemas (sketches)

Полные SQL-схемы — в миграциях каждого сервиса. Здесь — структурный обзор.

### `kacho_resource_manager`

```
organizations (uid PK, name UNIQUE, labels JSONB, annotations JSONB,
               creation_timestamp, resource_version, deletion_timestamp NULL,
               spec JSONB)
clouds        (uid PK, organization_id FK→organizations, name,
               labels, annotations, creation_timestamp, resource_version,
               deletion_timestamp NULL, spec JSONB,
               UNIQUE (organization_id, name))
folders       (uid PK, cloud_id FK→clouds, organization_id, name,
               labels, annotations, creation_timestamp, resource_version,
               deletion_timestamp NULL, spec JSONB,
               UNIQUE (cloud_id, name))
resource_events  (см. секцию 8.2)
```

### `kacho_vpc`

```
networks      (uid PK, folder_id, cloud_id, organization_id, name,
               labels, annotations, creation_timestamp, resource_version,
               deletion_timestamp NULL, generation, finalizers TEXT[],
               spec JSONB, status JSONB,
               UNIQUE (folder_id, name))
subnets       (uid PK, network_id FK→networks, folder_id, cloud_id, organization_id,
               name, ..., spec JSONB, status JSONB,
               UNIQUE (folder_id, name))
security_groups (...)
security_group_rules (uid PK, security_group_id FK→security_groups CASCADE,
                      ..., spec JSONB)
route_tables  (...)
static_routes (uid PK, route_table_id FK→route_tables CASCADE, ..., spec JSONB)
addresses     (...)
resource_events
```

### `kacho_compute`

> **Geography (Region/Zone) — домен kacho-compute** (перенесено из kacho-vpc, эпик `KAC-15`).
> Таблицы `regions` / `zones` живут в схеме `kacho_compute`; в `kacho_vpc` их **нет** —
> `subnets.zone_id`, `address_pools.zone_id` и т.п. хранят zone-id как обычную строку без FK и
> валидируют существование вызовом `compute.v1.ZoneService.Get` на request-path (см. CLAUDE.md
> §«Кросс-доменные ссылки на ресурсы»).

```
instances     (uid PK, folder_id, cloud_id, organization_id, name,
               labels, annotations, creation_timestamp, resource_version,
               deletion_timestamp NULL, generation, finalizers TEXT[], restarted_at NULL,
               spec JSONB, status JSONB,
               UNIQUE (folder_id, name))
disks         (...)
images        (...)        -- read-only seed
snapshots     (...)
regions       (id PK, name, created_at)               -- seed: ru-central1
zones         (id PK, region_id FK→regions RESTRICT,  -- seed: ru-central1-{a,b,d}
               name, status, created_at)
disk_types    (...)        -- seed: network-hdd, network-ssd, network-ssd-nonreplicated
platforms     (...)        -- seed: standard-v1, standard-v2, standard-v3
images_catalog(...)        -- seed: ubuntu-2204-lts, debian-12, и т.д.
resource_events
```

### `kacho_loadbalancer`

```
network_load_balancers (uid PK, folder_id, ..., spec JSONB, status JSONB)
target_groups          (uid PK, folder_id, ..., spec JSONB, status JSONB)
resource_events
```

## 11. БД-конвенции

- **`spec` и `status` — JSONB** колонки. Это даёт гибкость без миграции при добавлении новых полей. Денормализованные «горячие» поля (folder_id, name) — отдельные колонки для индексирования.
- **labels — JSONB + GIN-индекс** (`USING GIN (labels jsonb_path_ops)`) для эффективного label-selector-а.
- **NOT NULL по умолчанию** везде где можно. NULL только для опциональных полей (`deletion_timestamp`, `restarted_at`).
- **Update-trigger для `resource_version`**: триггер `BEFORE UPDATE` устанавливает `resource_version = nextval('resource_version_seq')`. INSERT тоже использует sequence через DEFAULT.
- **`pg_advisory_lock(uid_hash)`** для координации reconciler-репик — берётся в начале обработки конкретного ресурса.
- **`SELECT FOR UPDATE`** в read-modify-write транзакциях — защита от concurrent update.
- **`statement_timeout = '30s'`** на всех соединениях — защита pool-а.

## 12. sqlc + миграции

- **sqlc** генерирует типизированные методы для CRUD. Аннотированные `*.sql` в `internal/repo/queries/`.
- **goose** миграции в `migrations/`. Формат `0001_initial.sql` (sequential, не timestamp).
- **Common migrations** (`resource_events` + sequence + cleanup-функция) — шаблоны в `kacho-corelib/migrations/common/`, синхронизируются в каждое сервисное репо через `make sync-migrations`.
- **Filter/selector queries** — handwritten SQL с динамическим WHERE-builder поверх sqlc-generated базовых методов.
- **Init-container** в каждом Pod-е выполняет `<svc> migrate up` перед стартом основного контейнера. Тот же Docker-image содержит и сервис, и миграции (через `//go:embed migrations/*.sql`).

## 13. Naming convention (полная таблица)

| Контекст | Значение |
|---|---|
| Бренд / маркетинг / README / UI | **Kachō** |
| ASCII-бренд / технические идентификаторы | **`kacho`** |
| Proto package | **`kacho.cloud.<domain>.v1`** |
| gRPC method path | **`/kacho.cloud.<domain>.v1.<Service>/<Method>`** |
| Go-модули, импорты | `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/<domain>/v1` |
| Имена репо | **`kacho-<part>`** (с дефисом) |
| k8s namespace | **`kacho`** |
| k8s service name | `<domain>` (`compute`, `vpc`, ...) |
| Postgres database / schema | **`kacho_<domain>`** (с подчёркиванием) |
| Env-переменные | **`KACHO_<DOMAIN>_<NAME>`** |
| Docker image | `prorobotech/kacho-<svc>:<tag>` |

## 14. Коды ошибок

`google.rpc.Status` со стандартными gRPC-кодами:

| Код | Когда |
|---|---|
| `OK` | успех |
| `INVALID_ARGUMENT` | валидация полей не прошла, неверный selector, отсутствует обязательное поле |
| `NOT_FOUND` | ресурс не существует (по uid или name+scope) |
| `ALREADY_EXISTS` | uniqueness-violation при upsert (нарушение уникальности `name` в scope при попытке create) |
| `FAILED_PRECONDITION` | удаление при наличии зависимых ресурсов; conflicting state-transition |
| `ABORTED` | concurrent update (OCC failure после `SELECT FOR UPDATE`) — клиент должен retry |
| `RESOURCE_EXHAUSTED` | quota (зарезервировано, не используется в текущей фазе) |
| `UNAVAILABLE` | downstream-сервис недоступен |
| `INTERNAL` | unexpected server error |
| `GONE` (410) | watch-клиент с `resourceVersion` за пределами outbox-retention |

`details[]` содержит:
- `BadRequest` (для invalid_argument с list-field-violations).
- `PreconditionFailure` (для failed_precondition с list-причин).
- `RequestInfo` (`request_id` всегда заполнен — для trace).
- `ResourceInfo` (для not_found / already_exists, с указанием конкретного uid/name).
