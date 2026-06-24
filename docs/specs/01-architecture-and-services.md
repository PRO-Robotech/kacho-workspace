# Kachō — Архитектура и сервисы

**Документ:** 01 / 5

Обзор (`00-overview-and-scope.md`) зафиксировал продукт, scope и принципы дизайна:
плоские ресурсы, асинхронные `Operation`, database-per-service, polyrepo. Эта глава
раскладывает их на конкретные сервисы — граф вызовов, ресурсная модель каждого
домена, стандартный API-контракт на ресурс, routing api-gateway и механику
асинхронного исполнения. Naming-таблица, каталог error-кодов и per-service DDL —
в `02-data-model-and-conventions.md` (single source of truth, здесь не дублируются).

## 1. Граф сервисов

Edge-сервис `kacho-api-gateway` принимает внешний трафик; каждый доменный сервис
владеет своей Postgres-БД и своим набором ресурсов. Между собой доменные сервисы
не зависят по build (database-per-service, общение только по API), но в runtime
делают синхронные gRPC-вызовы для валидации cross-domain ссылок.

```
                    внешние клиенты (TLS)
                              │
                              ▼
                  ┌───────────────────────┐
                  │   kacho-api-gateway   │  edge: gRPC-proxy + grpc-gateway REST
                  └───┬──────────┬────────┘   (без БД, без бизнес-логики)
        ┌─────────────┼──────────┼─────────────┐
        ▼             ▼          ▼              ▼
  ┌──────────┐  ┌──────────┐ ┌──────────┐ ┌──────────┐
  │ kacho-iam│  │ kacho-vpc│ │ kacho-   │ │ kacho-nlb│  (планируется)
  │          │  │          │ │ compute  │ │          │
  │ kacho_iam│  │ kacho_vpc│ │kacho_    │ │ kacho_nlb│
  └────▲─────┘  └──┬────▲──┘ │ compute  │ └──────────┘
       │           │    │    └──┬────▲──┘
       │  ProjectService.Get    │    │
       │  InternalIAMService    │    │
       └───────────┴────────────┘    │
       (* → iam)                      │
                   vpc → compute: ZoneService.Get (zone_id)
                   compute → vpc: Subnet/SG/Address (NIC-spec, IPAM)
```

**Runtime cross-domain edges** (синхронный gRPC service→service; НЕ build-зависимость,
вызовы напрямую, не через api-gateway; циклов нет):

| Ребро | Назначение |
|---|---|
| `vpc → geo` | валидация `zone_id` при `Create` Subnet/AddressPool через `geo.v1.ZoneService.Get` (Geography — домен geo, эпик #82) |
| `compute → geo` | валидация `Instance.zone_id` через `geo.v1.ZoneService.Get` |
| `nlb → geo` | валидация `region_id` LoadBalancer/TargetGroup через `geo.v1.RegionService.Get` (sync precheck) |
| `compute → vpc` | валидация NIC-spec инстанса (`SubnetService.Get` / `SecurityGroupService.Get` / `AddressService.Get`) + IPAM-аллокация Address |
| `nlb → compute` | резолв Instance-таргетов (`compute.v1.InstanceService.Get`); только Instance, НЕ geography |
| `geo → iam` | `InternalIAMService.Check` (per-RPC authz-gate; geo — leaf-консумер только iam) |
| `* → iam` | `ProjectService.Get` (existence + account lookup, leaf-owner) + `InternalIAMService.Check` (per-RPC authz-gate) |
| `nlb → vpc` | валидация `subnet_id` таргетов |

**Циклы запрещены**: если A зовёт B — B не зовёт A. Peer недоступен → мутация
fail-closed (`Unavailable`). Новое ребро фиксируется в `polyrepo.md`.

## 2. Сервисы

Каждый доменный сервис — единственный владелец своих типов ресурсов (канонический
CRUD + read-API). Consumer'ы ссылаются по id (TEXT, без cross-service FK) и
валидируют через API владельца на request-path.

### 2.1 `kacho-api-gateway`

**Роль:** единая точка входа для внешних клиентов. Без БД, без бизнес-логики.

- **gRPC-proxy** — по method-path `/kacho.cloud.<domain>.v1.<Service>/<Method>`
  определяет `<domain>` и проксирует на backend (`<svc>:9090`).
- **REST-фасад** (grpc-gateway): camelCase JSON ⇄ proto; пути `/<service>/v1/<resource>`,
  suffix-actions через `:verb` (`/subnets/{id}:addCidrBlocks`).
- **OperationService.Get(id)** — маршрутизируется по 3-char prefix id (тип ресурса
  читается по prefix), поэтому все операции домена идут в один backend.
- **Two-listener** (детали — §4): external TLS — публичные сервисы; cluster-internal
  `:9091` — `Internal*`-сервисы и admin-RPC (UI/admin-tooling/port-forward).

### 2.2 `kacho-iam`

**Роль:** identity & access. БД `kacho_iam`. Владелец иерархии владения
**Account → Project** (заместил упразднённый `resource-manager`, эпик `KAC-124`).

**Ресурсы:** `Account`, `Project`, `User`, `ServiceAccount`, `Group`, `Role`,
`AccessBinding`.

- **Account** — top-level tenant. Owner — единственный `User` (`owner_user_id`
  FK ON DELETE RESTRICT). Имя глобально уникально.
- **Project** — child Account-а, контейнер всех domain-ресурсов. Имя уникально
  per-Account. Имеет `Move` (atomic CAS UPDATE).
- **Role** — единица авторизации из `rules[]` (`{module, resources, verbs,
  selector}`); system (64 seed'ятся миграциями с детерминированными id) + custom
  (per-Account/Project, partial UNIQUE).
- **AccessBinding** — грант `(subjects[]) ↔ role ↔ scope`, где scope ∈
  {GLOBAL, ACCOUNT, PROJECT} — **граница материализации** (не корень
  наследования). Strict-create (дубль активного гранта → `ALREADY_EXISTS`).
  Доступ — явные per-object FGA-tuple (explicit RBAC, плоский индекс — без
  hierarchy-каскада); runtime-Check — через `InternalIAMService.Check`.

**Lifecycle:** нет (мгновенное применение внутри worker'а операции).
**Cross-service:** входящее ребро `* → iam` (`ProjectService.Get` — existence +
account lookup). Внутри-IAM ссылки защищены DB-уровнем (FK / UNIQUE / CAS / trigger).

### 2.3 `kacho-vpc`

**Роль:** control plane сетевых ресурсов. БД `kacho_vpc`.

**Ресурсы:** `Network`, `Subnet`, `SecurityGroup` (+ `SecurityGroupRule`),
`RouteTable` (+ `StaticRoute`), `Address`, `Gateway`, `NetworkInterface` (NIC —
first-class ENI-подобный ресурс, отдельно от Instance). Admin-only: `AddressPool`
(IPAM, Internal*).

- **Subnet** — IP-диапазон в Network; `v4_cidr_blocks` не обязателен на `Create`
  (добавляется позже через `:addCidrBlocks`/`:removeCidrBlocks`). CIDR не пересекаются —
  DB `EXCLUDE USING gist`. `zone_id` валидируется через compute.
- **Address** — IP-адрес, minimal lifecycle status; `used_by` — best-effort
  usage-hint (кто привязал).
- **NetworkInterface** — принадлежит `Subnet`; ссылается на `Address` по id
  (`v4_address_ids[]`/`v6_address_ids[]`, ≤1 v4 + ≤1 v6 — DB CHECK); несёт
  `security_group_ids[]`; `used_by` ставится `:attachToInstance`, чистится
  `:detachFromInstance`. `status ∈ {PROVISIONING, ACTIVE, AVAILABLE, FAILED, DELETING}`.
  Проекция — lean tenant-facing (без инфра/data-plane полей).

**Lifecycle:** Address и NetworkInterface несут status; Network/Subnet/SG/RouteTable —
без lifecycle (мгновенно).

**FK / dependency-цепочка (всё RESTRICT, same-DB):**

```
NetworkInterface → Address → Subnet → Network
```

- `Address.Delete` блокируется, пока на адрес ссылается NIC.
- `Subnet.Delete` блокируется, пока есть internal-Address (v4 или v6) или хоть один NIC.
- `Network.Delete` блокируется, пока есть Subnet / RouteTable / non-default SG
  (default-SG авто-создаётся и авто-удаляется в той же writer-TX) → `"network is not empty"`.

Net-effect: удаление снизу вверх — NIC → Address → Subnet → Network, с понятным
precondition-error на каждом уровне. Default-SG-связь: `Network.default_security_group_id`
FK ON DELETE SET NULL + partial UNIQUE «≤1 default-SG на сеть».

**Cross-service:** `Subnet.Create` валидирует `zone_id` (→ geo); ресурсы
compute/nlb валидируют свои VPC-ссылки вызовом в kacho-vpc.

### 2.4 `kacho-compute`

**Роль:** control plane вычислительных ресурсов. БД `kacho_compute`. Самый сложный
сервис — несёт reconciler с симулированным lifecycle.

**Ресурсы:** `Instance`, `Disk`, `Image`, `Snapshot`, read-only `DiskType`.
Geography (`Region`/`Zone`) вынесена в leaf-сервис `kacho-geo` (эпик #82); `Instance.zone_id`
валидируется peer-вызовом в `geo` (не по собственной таблице).

### 2.4a `kacho-geo`

**Роль:** владелец домена **Geography** (platform-топология). БД `kacho_geo`. Leaf-сервис
(как iam): ни от какого сервиса не зависит по build, в runtime зовёт только `iam`
(authz-Check). Вынесен из `kacho-compute` эпиком #82, чтобы убрать ложные «ради geography»
рёбра `vpc→compute` / `nlb→compute`.

**Ресурсы:** `Region` (id = literal, напр. `ru-central1`), `Zone` (id = literal, напр.
`ru-central1-a`; FK `region_id → regions(id) ON DELETE RESTRICT`, `status UP/DOWN`). Глобальная
топология (scope `cluster`, не привязана к Project/Account). `Get`/`List` — sync, read-only;
admin-CRUD — через `Internal*`-сервисы на :9091 (catalog-паттерн, ответ синхронный, как
`InternalDiskTypeService`).

- **Instance** — VM с полной state-машиной (control-plane имитация):
  `PROVISIONING, RUNNING, STOPPING, STOPPED, STARTING, RESTARTING, UPDATING, ERROR,
  CRASHED, DELETING`. Действия — отдельные async RPC: `Start`/`Stop`/`Restart`/`Move`/
  `AttachDisk`/`DetachDisk`/`AddOneToOneNat`/`RemoveOneToOneNat`/`UpdateNetworkInterface`/
  `UpdateMetadata`. Precondition не выполнено → `FailedPrecondition` со стабильным
  текстом (`"Instance must be stopped"`, `"The disk is being used"`).
- **Disk** — `CREATING, READY, ERROR, DELETING`; `Move`/`Relocate`. Источник —
  Image / Snapshot.
- **Image** — каталог родительских образов (download — заглушка, статус сразу `READY`).
- **Snapshot** — снимок Disk.
- **Region / Zone** — read-only справочник; admin CRUD только через Internal*.

**Lifecycle:** Instance/Disk/Image/Snapshot несут status; переходы детерминированы
внутри worker'а операции (нет гипервизора, нет реальных таймеров).

**FK contract (same-DB):**

- `attached_disks.disk_id → disks` ON DELETE RESTRICT (нельзя удалить attached Disk).
- `attached_disks.instance_id → instances` ON DELETE CASCADE.
- `instance_network_interfaces.instance_id → instances` ON DELETE CASCADE.
- `zones.region_id → regions` ON DELETE RESTRICT.
- `disks.source_image_id` / `source_snapshot_id`, `snapshots.source_disk_id` —
  **НЕ FK** (источник можно удалить; existence-check в worker'е Create).
- partial UNIQUE `(project_id, name) WHERE name <> ''`.

**Cross-service:** owner-проект → iam (`ProjectService.Get`); Instance NIC → vpc
(Subnet/SG/Address + `subnet.zone_id == instance.zone_id`). Входящее ребро vpc→compute
(`ZoneService.Get`). Освобождение one-to-one NAT при `Instance.Delete` — best-effort
(VPC недоступен → log warning, операция не падает).

### 2.5 `kacho-nlb` *(планируется)*

**Роль:** control plane Network Load Balancer (L4). БД `kacho_nlb`.

**Ресурсы:** `NetworkLoadBalancer`, `TargetGroup`.

**Cross-service (планируется):** `subnet_id` таргетов → vpc; `instance_id` таргетов →
compute; owner-проект → iam. Lifecycle — по образцу compute (status + worker).

## 3. Стандартный API-контракт на ресурс

Каждый ресурс следует единому паттерну (parity по форме между ресурсами обязателен).

### 3.1 Публичные RPC (наружу через api-gateway)

| Метод | REST | Семантика |
|---|---|---|
| `Get(id)` | `GET /<svc>/v1/<r>/{id}` | **sync** — возвращает ресурс |
| `List(req)` | `GET /<svc>/v1/<r>` | **sync** — cursor-пагинация `(created_at, id)`, `filter` (whitelist), result фильтруется через listauthz |
| `Create(req)` | `POST /<svc>/v1/<r>` | **async** → `Operation` |
| `Update(req)` | `PATCH /<svc>/v1/<r>/{id}` | **async** → `Operation`; `update_mask` discipline |
| `Delete(id)` | `DELETE /<svc>/v1/<r>/{id}` | **async** → `Operation` |
| domain-действие | `POST /<svc>/v1/<r>/{id}:verb` | **async** → `Operation` (`:addCidrBlocks`, `Start`, `Stop`, `AttachDisk`, …) |
| `ListOperations(id)` | `GET /<svc>/v1/<r>/{id}/operations` | **sync** — переживает удаление ресурса (см. ниже) |

Контракт мутаций (из `00-overview-and-scope.md`): мутации **не** возвращают ресурс
синхронно — только `Operation`. Клиент поллит `OperationService.Get(id)` до
`done=true`, читает `oneof result { error | response }`. Нет `upsert`, нет публичного
`Watch` (опрос вместо стриминга: `List` каждые 2-5 c или `Operation.Get` для in-flight).

**`update_mask` discipline:** unknown поле → `InvalidArgument`; hard-immutable поле →
`InvalidArgument`; пустой mask → full-object PATCH (immutable из тела игнорируются);
mutable поле → применяется, валидируется как при `Create`.

**`ListOperations` переживает удаление ресурса:** история операций (per-service
`operations`-таблица) не каскад-удаляется вместе с ресурсом — `ListOperations(id)`
работает после того, как ресурс удалён.

### 3.2 Internal RPC (между сервисами / admin, не наружу на external TLS)

| Пример | Назначение |
|---|---|
| `InternalIAMService.Check` | per-RPC authz-gate (vpc/compute зовут peer-to-peer) |
| `InternalAddressService.Allocate/Free` (vpc) | IPAM-аллокация Address |
| `InternalAddressPoolService` (vpc) | admin-CRUD пулов IPAM |
| `InternalRegionService` / `InternalZoneService` (geo) | admin-CRUD справочников Geography (Region/Zone) |
| `InternalDiskTypeService` (compute) | admin-CRUD справочника типов дисков |

Публичный API ресурса показывает только tenant-facing «намерение + результат» (id,
name/labels, привязки, выделенный адрес, status). Инфра-чувствительные данные
(placement / underlay / wiring / числовой инфра-id) — **только** в Internal*-проекции
(`security.md`). Любой admin-RPC, которого нет в публичном API, добавляется только в
`Internal*`-сервис.

## 4. Routing api-gateway (two-listener)

api-gateway — единственная edge-поверхность; backend каждого сервиса слушает gRPC
`:9090`. Маршрутизация разнесена на два listener'а:

- **External TLS** (advertised, для внешних клиентов) — только публичные сервисы и
  публичные RPC.
- **Cluster-internal `:9091`** — `Internal*`-сервисы и admin-RPC (UI, admin-tooling,
  port-forward).

`Internal.*` методы и `Internal*`-сервисы регистрируются **только** на internal mux
(ban #6). Текущие Internal admin-ресурсы: `AddressPool` (`/vpc/v1/addressPools`),
`Region`/`Zone`/`DiskType` (`/compute/v1/regions`, `/zones`, `/diskTypes`).
Ответственность за корректную регистрацию — агент `api-gateway-registrar`.

## 5. Асинхронное исполнение (Operation + outbox + polling)

Все мутации асинхронны и проходят через единый механизм (corelib `operations` +
`outbox`); без внешнего брокера (Kafka/NATS) — транзакционный outbox.

1. **Мутация создаёт `Operation`** — RPC возвращает `Operation` (id с per-service
   prefix), запись в `operations`-таблицу + INSERT в `outbox` — **в той же TX**, что
   и (будущая) запись ресурса. Никаких dual-write race conditions.
2. **Worker исполняет** — фоновая горутина-worker (corelib `operations.Worker`)
   подхватывает запись, выполняет переход, транзакционно обновляет ресурс + `Operation`
   (`done=true`, `result`) + outbox. Для iam/vpc — мгновенно; для compute —
   детерминированная state-машина внутри worker'а.
3. **Wake-up через `LISTEN/NOTIFY`** — INSERT в outbox шлёт `pg_notify` на
   per-service канал; worker просыпается без busy-poll (ticker — fallback).
4. **Клиент опрашивает** — `OperationService.Get(id)` до `done=true`; для списков —
   `List` каждые 2-5 c. Публичного `Watch`-стриминга нет.

**compute reconciler:** фоновый worker, который двигает state-машину Instance/Disk/
Snapshot к целевому состоянию. Координация multi-replica — `pg_advisory_lock` на
`resource_id` (защита от двойной обработки разными репликами); eventually-consistent.

Within-service инварианты на этом пути выражены DB-конструкциями (FK / partial-UNIQUE /
EXCLUDE / CHECK / атомарный CAS / xmin-OCC / `FOR UPDATE SKIP LOCKED`), а не software
check-then-act — детали в `02-data-model-and-conventions.md` и `data-integrity.md`.

---

Это раскладка сервисов и их контрактов. Следующая глава —
`02-data-model-and-conventions.md` — фиксирует naming-таблицу, форму ресурса,
error-каталог и per-service схемы данных, на которые ссылается этот документ.
