# Kachō — Модель данных и конвенции

**Документ:** 02 / 5

Граф сервисов и runtime-зависимости описаны в `01-architecture-and-services.md`.
Здесь — нормативный reference по форме ресурса, naming, ошибкам, async-исполнению и
схеме БД, единый для всех доменов (IAM / VPC / Compute) и обязательный для каждого
нового ресурса или RPC. Это собственные конвенции продукта, а не подражание чужим
облакам.

## 1. Форма ресурса — плоский message + Operations

Каждый ресурс Kachō — **плоский** protobuf-message: domain-поля на верхнем уровне, без
вложенного K8s-envelope. Запрещены конструкции K8s-стиля: nested `spec`/`status`-объект,
version-cursor поля, generation-счётчик, cleanup-хуки, отдельный `uid`, soft-delete-метка.
`status` — это enum-поле верхнего уровня (lifecycle-состояние), а не вложенный объект.

```protobuf
message Instance {
  string id = 1;
  string project_id = 2;                       // owner — всегда project-level
  google.protobuf.Timestamp created_at = 3;    // truncate до секунд в ответе
  string name = 4;
  string description = 5;
  map<string,string> labels = 6;
  string zone_id = 7;
  Status status = 10;                           // enum, не nested message
  // ...domain-поля плоско: resources_spec, network_interfaces, ...
}
```

**Иерархия владения** — Account → Project. Все мутируемые domain-ресурсы — project-level:
`project_id` обязателен в `Create`, в БД это колонка-владелец `project_id`.

### Стандартные методы

`Get`/`List` — синхронны. `Create`/`Update`/`Delete` и domain-действия (`Start`,
`Stop`, `AttachDisk`, `:addCidrBlocks`, `Move`, …) — асинхронны, возвращают `Operation`.
Upsert-семантики нет. Публичного `Watch`-RPC нет (клиент поллит `List` каждые 2-5 c и
`OperationService.Get(id)` до `done=true`).

```protobuf
service InstanceService {
  rpc Get(GetInstanceRequest) returns (Instance);                    // sync
  rpc List(ListInstancesRequest) returns (ListInstancesResponse);    // sync
  rpc Create(CreateInstanceRequest) returns (operation.Operation);   // async
  rpc Update(UpdateInstanceRequest) returns (operation.Operation);   // async
  rpc Delete(DeleteInstanceRequest) returns (operation.Operation);   // async
  rpc Start(StartInstanceRequest) returns (operation.Operation);     // async, :verb
}
```

### Две проекции ресурса (public / internal)

Инфра-чувствительные данные (placement, underlay, host-wiring, числовой инфра-id) живут
**только** в `Internal*`-API на :9091, никогда на публичной поверхности. Публичный ресурс
показывает tenant-facing «намерение + результат»: id, name/labels, привязки, выделенный
адрес, `status`. Детали — `.claude/rules/security.md`.

## 2. ID-модель

Все id выдаёт `kacho-corelib/ids.NewID(<prefix>)`: **3-char prefix + 17-char
crockford-base32**. Тип ресурса читается по prefix; api-gateway маршрутизирует
`OperationService.Get(id)` именно по первым 3 символам. Колонки `id` в БД — `TEXT`.

| Домен | Prefix → ресурс |
|---|---|
| IAM | `acc` Account · `prj` Project · `usr` User · `sva` ServiceAccount · `grp` Group · `rol` Role · `acb` AccessBinding · `iop` Operation |
| VPC | `net` Network · `sub` Subnet · `adr` Address · `rtb` RouteTable · `sgr` SecurityGroup · `gtw` Gateway · `nic` NetworkInterface · `apl` AddressPool · `enp` Operation |
| Compute | `epd` Instance/Disk/Operation · `fd8` Image/Snapshot · литерал `network-ssd` для DiskType |
| Geo | литералы для Region/Zone (`ru-central1`, `ru-central1-a`) — admin-assigned id, leaf-домен `kacho-geo` |

Заметки по prefix-шарингу (умышленно):

- **Operation декаплен от ресурса** — иначе api-gateway-маршрутизация `OperationService.Get`
  конфликтует с основным сервисом (IAM: `iop`, не `acc`; VPC: `enp`; Compute: `epd`).
- Compute группирует prefix по домену: Instance/Disk → `epd`, Image/Snapshot → `fd8`.
  Все compute-операции получают `epd` независимо от ресурса; `ImageService.Create` вернёт
  operation `epd…`, внутри которого `response` = Image с id `fd8…`.
- Read-only справочники Compute (DiskType) и Geo (Region/Zone) используют осмысленные литералы как id.

## 3. Naming convention

| Контекст | Значение |
|---|---|
| Бренд / README / UI | **Kachō** (макрон над `ō`) |
| ASCII-бренд / технические идентификаторы | **`kacho`** |
| Proto package | **`kacho.cloud.<domain>.v1`** (`kacho.cloud.compute.v1`) |
| gRPC method path | **`/kacho.cloud.<domain>.v1.<Service>/<Method>`** |
| Go-импорты stubs | `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/<domain>/v1` |
| Имена репо | **`kacho-<part>`** (дефис) |
| k8s namespace | **`kacho`** |
| k8s service name | `<domain>` (`compute`, `vpc`, `iam`) |
| Postgres database / schema | **`kacho_<domain>`** (подчёркивание) |
| Env-переменные | **`KACHO_<DOMAIN>_<NAME>`** |
| Docker image | `prorobotech/kacho-<svc>:<tag>` |
| JSON-поля (REST) | camelCase: `<resource>Id`, `projectId`, `labels`, `createdAt` |
| REST-пути | `/<service>/v1/<resource>`; suffix-action — `:verb` (`/subnets/{id}:addCidrBlocks`) |

## 4. Timestamps

В БД timestamps хранятся с микросекундной точностью (`TIMESTAMPTZ`). В proto-ответе они
**усекаются до секунд** (`CreatedAt.Truncate(time.Second)`) — стабильный контракт для
сравнения/idempotency на стороне клиента.

## 5. Error-format

gRPC: `status.Error(code, message)`. REST через grpc-gateway → `{code, message,
details[]}` + `google.rpc.Status`.

| Код | Когда |
|---|---|
| `INVALID_ARGUMENT` | формат/валидация поля; неизвестное поле в `update_mask`; immutable в mask |
| `NOT_FOUND` | id well-formed, но ресурса нет (через `repo.Get`) |
| `FAILED_PRECONDITION` | состояние ресурса не позволяет операцию; FK RESTRICT; CAS не matched; CIDR-overlap |
| `ALREADY_EXISTS` | нарушение UNIQUE (`23505`) в create-контексте |
| `UNAVAILABLE` | peer-сервис недоступен — **fail-closed** для мутаций |
| `INTERNAL` | непредвиденная ошибка; **фиксированный текст без leak'а pgx/SQL** |

**id-валидация**: malformed/нераспознанный prefix → sync `InvalidArgument "invalid <res>
id '<X>'"` первым стейтментом RPC (`corevalidate.ResourceID`); well-formed-но-нет →
`NotFound` через `repo.Get`.

**Канонические тексты** (часть контракта, меняются только осознанно через тикет):

- `"<Resource> %s not found"` — `"Route table %s not found"`, `"Project with id %s not found"`.
- `"<field> is immutable after <Resource>.Create"`.
- `"network is not empty"` · `"Subnet CIDRs can not overlap"` · `"The disk is being used"` ·
  `"Instance must be stopped"` · `"<resource> with name ... exists"` · `"internal database error"`.

Маппинг SQLSTATE→gRPC в сервисном слое: `23503`→FailedPrecondition, `23505`→AlreadyExists
или FailedPrecondition (по контексту), `23514`→InvalidArgument, `23P01`→FailedPrecondition.

## 6. update_mask discipline

`Update` принимает `google.protobuf.FieldMask update_mask`. Дисциплина едина для всех
ресурсов всех сервисов:

| Случай | Поведение |
|---|---|
| mask содержит **unknown** поле | `InvalidArgument` (`corevalidate.UpdateMask` с known-set) |
| mask содержит **hard-immutable** поле | `InvalidArgument` (`"<field> is immutable after <R>.Create"`) |
| mask **пустой** | full-object PATCH: применяются все mutable-поля, immutable из тела молча игнорируются |
| mask содержит mutable поле | применяется; валидируется теми же правилами, что и `Create` |

Hard-immutable поля задаются per-resource. Примеры: IAM — `Account.owner_user_id`,
`Project.account_id` (меняется через `Move`), `User.external_id`; VPC — `Subnet.network_id`,
`Subnet.zone_id`, `Address.*_address_spec`; Compute — `Disk.type_id`/`zone_id`/`block_size`,
`Instance.zone_id`/`boot_disk`. Полные таблицы — в `docs/architecture/` каждого сервиса.

## 7. Pagination / filter

- **Cursor-based**, ключ курсора — `(created_at, id)`, `ORDER BY created_at, id ASC`.
- `page_token` — opaque base64 `{created_at, id}`; garbage-token → `InvalidArgument`.
- `page_size` через `corevalidate.PageSize`: `0` → default 50, max 1000.
- `filter` — `kacho-corelib/filter.Parse` с whitelist полей (текущая фаза — `name=`).
- Публичный `List` дополнительно фильтруется через listauthz (CI-гейт `make audit-list-filter`).

```sql
WHERE (created_at, id) > ($lastCreatedAt, $lastId)
ORDER BY created_at, id ASC
LIMIT $pageSize;
```

## 8. Async-исполнение: Operation + outbox

Мутация не возвращает ресурс синхронно — она создаёт `Operation` и запускает worker.

### Operation

```protobuf
message Operation {                              // kacho.cloud.operation.v1
  string id = 1;
  string description = 2;
  google.protobuf.Timestamp created_at = 3;
  bool done = 4;
  google.protobuf.Any metadata = 5;
  oneof result {
    google.rpc.Status error = 6;                 // при ошибке
    google.protobuf.Any response = 7;            // готовый ресурс при успехе
  }
}
```

Клиент поллит `OperationService.Get(id)` до `done=true`. `ListOperations(resource_id)`
переживает удаление самого ресурса (история операций не каскадится).

### Транзакционный outbox (без внешнего брокера)

Источник истины — Postgres; журнал событий — outbox-таблица, пишется **в той же
транзакции**, что и мутация (никакого dual-write race). После commit — `LISTEN/NOTIFY`
как wake-up-сигнал; worker дренирует outbox.

```sql
-- per-service outbox (имя: <svc>_outbox)
CREATE TABLE compute_outbox (
  id           BIGSERIAL   PRIMARY KEY,
  resource_id  TEXT        NOT NULL,
  event_type   TEXT        NOT NULL,      -- created | updated | deleted
  payload      JSONB       NOT NULL,      -- encoded resource snapshot
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  published_at TIMESTAMPTZ                -- NULL пока не доставлено
);
-- AFTER INSERT/UPDATE/DELETE-trigger вызывает pg_notify('<svc>_outbox', '') (wake-up без payload)
```

Один writer-TX:

1. меняет ресурсную таблицу + таблицу `operations`;
2. `INSERT` в `<svc>_outbox`;
3. после commit — `pg_notify('<svc>_outbox', '')`.

Внутренний стрим (UI / cross-service) идёт через `Internal*Watch`-сервис на :9091 поверх
outbox + `LISTEN/NOTIFY` — это **не** публичный Watch (его нет на external-поверхности).

### Таблица `operations` (LRO)

Общий corelib-pattern (`operations`: Repo + Worker): по строке на каждую async-мутацию.

```sql
CREATE TABLE operations (
  id           TEXT        PRIMARY KEY,    -- prefix per-domain: iop / enp / epd
  resource_id  TEXT        NOT NULL,
  description  TEXT        NOT NULL,
  done         BOOLEAN     NOT NULL DEFAULT false,
  metadata     JSONB,
  response     JSONB,                      -- при успехе
  error        JSONB,                      -- google.rpc.Status при ошибке
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  done_at      TIMESTAMPTZ
);
```

IAM расширяет `operations` тремя principal-полями (`principal_type`/`principal_id`/
`principal_display_name`) для audit-trail.

### Lifecycle ресурса

Переходы `status` — детерминированная server-side state-машина **внутри worker'а
операции**: для IAM/VPC переход мгновенный, для Compute — симуляция (нет гипервизора;
например `PROVISIONING → RUNNING`). Compute дополнительно держит фоновый reconciler,
защищённый `pg_advisory_lock` от двойной обработки между репликами.

## 9. Per-service schemas (sketches)

Полные SQL — в `internal/migrations/` каждого сервиса. Здесь — структурный обзор;
все таблицы flat, все мутируемые ресурсы несут колонку `project_id`.

### `kacho_iam`

```
accounts        (id PK, owner_user_id FK→users RESTRICT, name UNIQUE, description,
                 labels JSONB, created_at)
projects        (id PK, account_id FK→accounts RESTRICT, name, labels, created_at,
                 UNIQUE (account_id, name))                 -- Move = atomic CAS
users           (id PK, external_id UNIQUE,                 -- Zitadel sub (mirror identity)
                 email, display_name, created_at)
service_accounts(id PK, account_id FK→accounts RESTRICT, name, ...,
                 UNIQUE (account_id, name))
groups          (id PK, account_id FK→accounts RESTRICT, name, ...)
group_members   (group_id FK→groups CASCADE, member_type, member_id)   -- ref-trigger
roles           (id PK, account_id NULL FK→accounts RESTRICT, is_system, name,
                 permissions JSONB CHECK iam_permissions_valid(), ...,
                 partial UNIQUE (account_id, name) WHERE is_system=false)  -- 12 system seed
access_bindings (id PK, subject_type, subject_id, role_id FK→roles RESTRICT,
                 resource_type, resource_id,                -- resource_id: cross-DB, без FK
                 UNIQUE (subject_type,subject_id,role_id,resource_type,resource_id))  -- идемпотентный Create
operations      (см. §8; + principal_*)
iam_outbox
```

### `kacho_vpc`

```
networks         (id PK, project_id, name, labels, created_at,
                  default_security_group_id NULL FK→security_groups ON DELETE SET NULL,
                  partial UNIQUE «≤1 default-SG на сеть»)
subnets          (id PK, network_id FK→networks RESTRICT, project_id, zone_id (TEXT, без FK),
                  v4_cidr_blocks / v6_cidr_blocks, ...,
                  EXCLUDE gist subnets_no_overlap_v4/_v6)
addresses        (id PK, project_id, internal_subnet_id (generated, FK→subnets RESTRICT),
                  internal_ipv4 / internal_ipv6 NULL, used_by JSONB)   -- external: без Subnet
security_groups  (id PK, network_id FK→networks RESTRICT, project_id, ...)
security_group_rules (id PK, security_group_id FK→security_groups CASCADE, ...)
route_tables     (id PK, network_id FK→networks RESTRICT, project_id, ...)
network_interfaces (id PK, subnet_id FK→subnets RESTRICT, project_id,
                  v4_address_ids / v6_address_ids (≤1+≤1, CHECK jsonb_array_length<=1),
                  security_group_ids, mac_address (output-only, cloud-wide UNIQUE),
                  used_by JSONB, status)
address_pools    (id PK, v4_cidr_blocks / v6_cidr_blocks, kind, zone_id (TEXT, без FK),
                  is_default, selector_*, EXCLUDE gist per-kind)        -- admin-only (Internal*)
operations       (см. §8) · vpc_outbox
```

FK-цепочка `kacho_vpc` — RESTRICT снизу вверх: удалять `NetworkInterface → Address →
Subnet → Network`; default-SG авто-удаляется в writer-TX при `Network.Delete`. Внешний
`Address` — project-level без Subnet. `Gateway` — project-level (shared egress). `zone_id`
хранится как TEXT и валидируется вызовом `geo.v1.ZoneService.Get`.

### `kacho_geo`

Geo — owner Geography (Region/Zone вынесены из `kacho-compute`, эпик #82). Leaf-домен.

```
regions  (id TEXT PK = literal напр. 'ru-central1', name, created_at)
zones    (id TEXT PK = literal напр. 'ru-central1-a', region_id FK→regions(id) ON DELETE RESTRICT,
          status TEXT (UNSPECIFIED|UP|DOWN), name, created_at)
geo_outbox (audit на admin-мутациях — parity с compute_outbox/vpc_outbox)
```

Within-service инвариант: регион с зонами удалить нельзя (FK RESTRICT, DB-уровень). Cross-service
ссылки (`Instance.zone_id`, `Subnet.zone_id`, `address_pools.zone_id`, NLB `region_id`) — TEXT без
cross-service FK, валидируются peer-вызовом в geo; dangling-ref на чтении переживается грациозно.

### `kacho_compute`

Compute — Instance/Disk/Image/Snapshot/DiskType. Geography (Region/Zone) больше не здесь —
вынесена в `kacho_geo` (эпик #82); `zone_id`/`region_id` валидируются peer-вызовом в geo.

```
instances        (id PK, project_id, name, labels, zone_id, status, created_at,
                  boot_disk_id (диск из attached_disks c is_boot), ...,
                  partial UNIQUE (project_id, name) WHERE name<>'')
instance_network_interfaces (id PK, instance_id FK→instances CASCADE,
                  subnet_id, primary_v4_address, one_to_one_nat.address_id?, security_group_ids)
disks            (id PK, project_id, type_id (→ disk_types), zone_id, size, status,
                  source_image_id / source_snapshot_id — НЕ FK (existence-check в worker'е))
attached_disks   (instance_id FK→instances CASCADE, disk_id FK→disks RESTRICT,
                  auto_delete, is_boot)                     -- M:N
images           (id PK, project_id, family, ..., status READY)   -- download — заглушка
snapshots        (id PK, project_id, source_disk_id (НЕ FK), ..., status)
disk_types       (id PK литерал, ...)                       -- seed: network-hdd/ssd/...
operations       (см. §8; prefix epd) · compute_outbox · compute_watch_cursors
```

> Региона/зоны (`regions`/`zones`) в `kacho_compute` больше нет — вынесены в `kacho_geo`
> (эпик #82); `instances.zone_id`/`disks.zone_id` — TEXT-ссылки, валидируемые peer-вызовом в geo.

`disks.source_*`/`snapshots.source_disk_id` — без FK (источник можно удалить, ссылка
остаётся как «откуда создан», existence-check на Create). `attached_disks.disk_id` RESTRICT
(нельзя удалить присоединённый диск); `Instance.Delete` worker по `auto_delete` решает
судьбу дисков, затем CASCADE чистит NIC и строки attach.

## 10. БД-конвенции (within-service инварианты)

Инварианты внутри одной БД сервиса выражаются **только** DB-конструкциями (не
software-side check-then-act). Сервисный слой лишь маппит SQLSTATE → gRPC.

| Инвариант | DB-механизм |
|---|---|
| id обязан существовать в той же БД | `FK REFERENCES … ON DELETE {RESTRICT\|CASCADE\|SET NULL}` |
| поле уникально | `UNIQUE` / `CREATE UNIQUE INDEX` |
| уникально только если поле непусто | partial `UNIQUE … WHERE <cond>` |
| range не пересекается (CIDR) | `EXCLUDE USING gist (… WITH &&)` |
| простой предикат | `CHECK (…)` |
| атомарный compare-and-swap (attach/Move) | `UPDATE … WHERE <expected> RETURNING …` + проверка кардинальности |
| read-modify-write OCC без version-колонки | `xmin::text` snapshot + `UPDATE … WHERE xmin::text=$exp` |
| уникальная аллокация из пула (IPAM v4) | `FOR UPDATE SKIP LOCKED LIMIT 1` + `DELETE … RETURNING` |
| сериализовать read-modify-write набора | `SELECT … FOR UPDATE` перед merge+write |

Прочее: `labels` — JSONB + GIN-индекс; `NOT NULL` по умолчанию (NULL только для реально
опциональных полей); cross-service ссылки — TEXT без FK (валидация через peer-API на
request-path). Cross-service FK/cascade запрещены (database-per-service). Каждый спорный
конкурентный путь покрывается integration-тестом с goroutine-гонкой (testcontainers).

## 11. sqlc + миграции

- **Без ORM** — `sqlc` генерирует типизированные методы поверх аннотированных `*.sql`;
  динамический фильтр/pagination — handwritten pgx с параметризованным WHERE-builder.
- **goose**-миграции в `internal/migrations/*.sql` (`embed.FS`), формат `0001_initial.sql`
  (sequential, не timestamp). **Применённую миграцию не редактируют — только новая.**
- Каждый сервис стартует с `0001_initial.sql` (squashed baseline: таблицы, FK/UNIQUE/
  EXCLUDE/CHECK, триггеры outbox, seed справочников), дальше — инкрементальные миграции.
- Миграции применяет **отдельный `cmd/migrator`** (cobra-CLI, тот же образ через
  `//go:embed`), не основной serve-бинарь.

## 12. Config

Конфигурация — **YAML через viper** (skill `evgeniy`), не разбор env через struct-tags.
Секреты — через `secretKeyRef`/env-мост, не в YAML/ConfigMap. Env-переменные следуют
`KACHO_<DOMAIN>_<NAME>`. Clean Architecture (`domain ← use-case ← repo/clients/handler`,
`cmd` — composition root) и распределённые аспекты — `01-architecture-and-services.md`
и `.claude/rules/architecture.md`.

Развёртывание, миграции в кластере и эксплуатация — `03-deployment-and-operations.md`.
