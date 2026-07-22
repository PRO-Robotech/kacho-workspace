# Sub-phase compute-storage-volume-attach — Acceptance

> Статус: **APPROVED** (acceptance-reviewer, 2026-07-12)
> Дата: 2026-07-12
> Ревьюер: acceptance-reviewer (gate #1 — APPROVED до старта кода, ban #1)
> Эпик/тикет: `compute → storage decomposition`, инкремент 1 (`KAC-<TBD>` — тикет+ветку заведём **до кода**, gate #2; минор — намеренная пометка)
> Сервисы: **kacho-storage** (новый, `kacho.cloud.storage.v1`) · **kacho-compute** (attach-срез, `kacho.cloud.compute.v1`) · **kacho-vpc** (NIC-attach revival) · **kacho-proto** · **kacho-api-gateway** · **kacho-ui**
> Источник истины (спека): `docs/plans/kacho-storage-volume-and-instance-attach-spec.md` (§0–§7; ссылки на §N ниже — на этот файл)
> Конвенции (нормативно, не дублируются в теле): `.claude/rules/api-conventions.md`, `.claude/rules/data-integrity.md`, `.claude/rules/security.md`; коды ошибок — `docs/specs/02-data-model-and-conventions.md` §14
> Vault: `[[resources/vpc-networkinterface]]`, `[[edges/compute-to-vpc-nic-validate]]` (ребро NIC-attach, разорванное в KAC-266, оживает здесь); новые узлы под создание — `[[edges/storage-to-geo-zone-validate]]`, `[[edges/storage-to-iam-project-validate]]` (§4.3 спеки)

---

## 0. Обзор

Первый инкремент раскола монолитной модели диска на два владельца:

1. **kacho-storage** — новый сервис. Ресурс `Volume` (блочный диск, prefix `vol`) с полным
   CRUD (`Get`/`List` sync; `Create`/`Update`/`Delete` async → `Operation`) и внутренней
   координацией attach (`InternalVolumeService.Attach`/`Detach`/`ListAttachments`, :9091,
   mTLS). Join-таблица привязки `volume_attachments` живёт **в БД storage рядом с `volumes`**,
   поэтому «нельзя удалить примонтированный диск» и «диск примонтирован ≤1 инстансу» —
   **настоящие DB-constraint'ы** (FK RESTRICT / PK / UNIQUE / EXCLUDE), а не software-refcount.
   Сопутствующие ресурсы: `DiskType` (FK RESTRICT со стороны `Volume`), `Snapshot`
   (FK SET NULL в обе стороны). `status` тома `IN_USE`/`AVAILABLE` — **derived** из наличия
   attachment (не отдельная колонка), дрейф невозможен (§1.3).

2. **kacho-compute** — attach-срез `Instance`: `AttachDisk`/`DetachDisk` и
   `AttachNetworkInterface`/`DetachNetworkInterface` как **async саги** (compute-Operation,
   координирующая storage / vpc). Компьют локальных attach-таблиц **не держит** —
   `boot_volume`/`secondary_volumes`/`network_interfaces` на `Instance` это **read-only
   зеркала**, source of truth = storage / vpc, пересчитываются на чтении с graceful-degrade.
   Дополнительно: `cpu_guarantee_percent` (0..100), а ресайз диска — **только** через
   `Volume.Update{size_bytes}` (increase-only), не через RPC на инстансе.

Ключевой инвариант: **`compute → storage` и `compute → vpc` строго односторонни** — attach
self-describing (запрос несёт `instance_id/name/zone/project`), owner валидирует **свою**
строку атомарным CAS и **никогда не зовёт compute** (иначе цикл, ретроспектива KAC-266, §3.7/§7).

Все мутации возвращают `operation.Operation` (async LRO, ban #9); клиент поллит
`OperationService.Get(<opId>)` до `done=true`. Watch RPC не существует.

---

## 0.1. Терминология и соглашения (для всех сценариев)

- **«Operation done»** = клиент опросил `OperationService.Get(<opId>)` (REST
  `GET /<service>/v1/operations/{id}`) до `done=true`. **«Operation error»** = `done=true`
  и `result` содержит `google.rpc.Status` с указанным кодом; **«Operation ok/response»** =
  `done=true`, `result` содержит `response` (`Any`, распакованный ресурс).
- **«sync <code>»** = RPC вернул ошибку синхронно **до** создания `Operation` (fast-fail в
  handler/use-case). Именно так отдаются malformed-id и object-scoped authz. Все остальные
  отказы attach/detach/resize/delete приходят как **Operation error** (проверяются в worker'е).
- **ID-префиксы**: `Volume`=`vol`, `Instance`=`ins`, `NetworkInterface`=`enp`,
  **`DiskType`=admin-assigned slug** (напр. `block-balanced`; PK-строка, не генерируемый префикс),
  `Snapshot`=`snp`, op-root storage=`sop`, op-root compute=`epd`
  (opsproxy маршрутизирует по первым 3 символам op-id). (**Amendment 2026-07-15, механическая,
  поведение не меняет:** `DiskType` — slug, а не `dtp`-префикс; grounded в коммитнутом
  `disk_type.proto` («a slug set explicitly by an admin»), overview §1, парити MachineType.
  Замещает прежний `dtp`. Авторитет — `sub-phase-CS-1-storage-network-disk-acceptance.md` §0.0/§0.0.1,
  трекинг — `kacho-workspace#132`. `Snapshot`=`snp` без изменений.)
- **JSON — camelCase** (`volumeId`, `deviceName`, `isBoot`, `autoDelete`, `sizeBytes`,
  `projectId`, `zoneId`, `diskTypeId`, `sourceSnapshotId`, `instanceId`, `nicId`,
  `cpuGuaranteePercent`, `bootVolume`, `secondaryVolumes`, `networkInterfaces`, `usedBy`,
  `createdAt`).
- **REST-пути**: `/storage/v1/volumes`, `/storage/v1/volumes/{volumeId}`; suffix-actions
  compute через `:verb` (`/compute/v1/instances/{instanceId}:attachDisk`).
- **Timestamps** в proto-ответах усечены до секунд (`Truncate(time.Second)`) — на `Volume`,
  `Instance` **и** под-записях (`VolumeAttachment.attached_at`, `AttachedVolume.attached_at`).
- **Error-тексты — часть контракта** (§1.7). Assert'ы на негативах — **behaviour-level**:
  проверяют и код, И точное сообщение (не только `codes.X`), согласно `.claude/rules/testing.md`
  «regression-lock на уровне обсёрвабла».

### Точные error-тексты (нормативны — часть контракта; строки Q1–Q7 зафиксированы reviewer'ом, см. «Решённые вопросы»)

| Текст | gRPC-код | Триггер |
|---|---|---|
| `invalid volume id '<X>'` | `INVALID_ARGUMENT` (sync) | malformed `vol`-id первым стейтментом |
| `invalid instance id '<X>'` | `INVALID_ARGUMENT` (sync) | malformed `ins`-id первым стейтментом |
| `invalid network interface id '<X>'` | `INVALID_ARGUMENT` (sync) | malformed `enp`-id первым стейтментом (**verbatim** kacho-vpc `corevalidate.ResourceID`, `niResource="network interface"`, формат `invalid %s id '%s'` — Q7) |
| `Volume <id> not found` | `NOT_FOUND` | `Get` well-formed-но-нет (паттерн `"<Resource> %s not found"` — Q2) |
| `Instance <id> not found` | `NOT_FOUND` | `Get`/attach-target well-formed-но-нет (Q2) |
| `unknown zone id '<X>'` | `INVALID_ARGUMENT` | `Volume.Create` peer-validate `zone_id` через `geo.v1.ZoneService.Get` не прошёл (зеркалит vpc/compute→geo, §4.3 — критика #1) |
| `Illegal argument size_bytes` | `INVALID_ARGUMENT` (sync domain-validate; DB-backstop CHECK `size_bytes>0` `23514`) | `Volume.Create` `sizeBytes<=0` (важное #1) |
| `Illegal argument name` | `INVALID_ARGUMENT` (sync domain-validate) | `Volume.Create`/`Update` name too-long(>63)/uppercase/invalid-char (self-validating newtype, важное #2) |
| `volume with name <n> already exists in project` | `ALREADY_EXISTS` | partial `UNIQUE(project_id,name) WHERE name<>''` (`23505`); **одна стабильная строка** (Q3) |
| `Volume <id> is in use` | `FAILED_PRECONDITION` | delete привязанного тома (FK RESTRICT `23503`) **и** attach на том, уже занятый другим инстансом |
| `Volume is not available for attachment` | `FAILED_PRECONDITION` | attach на том в `state != READY` |
| `Volume and Instance must be in the same zone` | `FAILED_PRECONDITION` | attach: `zone_id` тома ≠ zone инстанса (**только** зона; zone-предикат CAS не сматчил) |
| `Volume and Instance must be in the same project` | `FAILED_PRECONDITION` | attach: `project_id` тома ≠ project payload'а (**отдельный** текст; project-предикат CAS не сматчил — не переиспользуется zone-строка) **(Amendment 2026-07-15: разделено на два текста, авторитет CS-1 §0.0/INV-4, `kacho-workspace#132`)** |
| `device <name> is already in use on Instance <id>` | `FAILED_PRECONDITION` | `UNIQUE(instance_id, device_name)` (`23505`) |
| `DiskType <id> not found` | `FAILED_PRECONDITION` | `Volume.Create` с несуществующим `diskTypeId` — **same-DB** FK RESTRICT `23503` (Operation error; НЕ cross-service, Q4) |
| `DiskType <id> is in use` | `FAILED_PRECONDITION` | `DiskType.Delete`, пока на него ссылается `Volume` (FK RESTRICT `23503`, Q4) |
| `Instance <id> already has a boot volume` | `FAILED_PRECONDITION` | второй boot-том, `EXCLUDE (instance_id WITH =) WHERE is_boot` `23P01` (Q5) |
| `Volume size can only be increased` | `INVALID_ARGUMENT` | `Update` `size_bytes` меньше/равно текущему (increase-only CAS `23514`/0-row) |
| `<field> is immutable after Volume.Create` | `INVALID_ARGUMENT` (sync) | immutable-поле в `update_mask` |
| `boot volume cannot be detached` | `FAILED_PRECONDITION` | `DetachDisk` boot-тома (Q6) |
| `Instance must be RUNNING or STOPPED` | `FAILED_PRECONDITION` | attach/detach-гейт: инстанс не в `{RUNNING, STOPPED}` |
| `Illegal argument cpu_guarantee_percent` | `INVALID_ARGUMENT` | `cpu_guarantee_percent` вне `[0..100]` (CHECK `23514`, Q6) |
| `Instance must be STOPPED to change sizing` | `FAILED_PRECONDITION` | `Update` `vcpus`/`memory_bytes`/`cpu_guarantee_percent` при не-`STOPPED` (Q6) |
| `<field> is immutable after Instance.Create` | `INVALID_ARGUMENT` (sync) | immutable Instance-поле в `update_mask` (Q6) |
| `NetworkInterface is in use` | `FAILED_PRECONDITION` | attach NIC, занятого другим инстансом |
| `network interface <id> is still attached to <kind> <id>; detach it first` | `FAILED_PRECONDITION` | `NetworkInterfaceService.Delete` привязанного NIC (**verbatim** существующий kacho-vpc `delete.go`, params `id, used_by_type, used_by_id` — Q7) |
| `NetworkInterface subnet is in zone <z1>, instance zone is <z2>` | `FAILED_PRECONDITION` | ZONAL-subnet NIC ≠ зона инстанса |
| `internal error` | `INTERNAL` | дефолт-ветка mapper — **никогда** не эхает pgx/SQL |

Пиры недоступны на `Create` (geo/iam/storage/vpc `Unavailable`) → `UNAVAILABLE` (fail-closed для
мутации, §4.1/§4.2/§4.3) — код, не строка (сообщение opaque).

---

## 0.2. Инварианты-критерии (проверяются, не только сценарии)

Помимо Given-When-Then ниже, документ фиксирует набор архитектурных критериев приёмки:

- **INV-1 — Ацикличность (§3.7, §7).** `kacho-storage/internal/clients/` **не импортирует**
  compute-stub; `kacho-vpc` **не импортирует** compute-stub на NIC-attach-пути. Owner
  валидирует свою строку из self-describing payload и **не зовёт** `compute.InstanceService.Get`.
  Критерий — arch-test (build-time guard) + фиксация ребра в `polyrepo.md` как one-way.
- **INV-1a — Peer-owner рёбра нового сервиса one-way (§4.3, `data-integrity` cross-domain rule 2 +
  `polyrepo.md` `*→iam`).** kacho-storage как любой сервис зовёт **geo** (валидация `zone_id`
  на `Volume.Create`, `ZoneService.Get`) и **iam** (`ProjectService.Get` existence/owner +
  `InternalIAMService.Check` authz + fgaproxy `RegisterResource`/`UnregisterResource` owner-tuple).
  Оба ребра **односторонни** (geo/iam — листья, storage их не звонит обратно; циклов нет);
  регистрируются в `polyrepo.md` (runtime-edges `storage→geo`, `storage→iam`) + vault
  `edges/storage-to-geo-zone-validate`, `edges/storage-to-iam-project-validate`. Fail-closed:
  peer `Unavailable` на `Create` → мутация `UNAVAILABLE`.
- **INV-7 — Lean public projection (ban #6 + инфра-sensitive, `.claude/rules/security.md`).**
  Публичный `Volume.Get`/`List` (`VolumeService`, :9090/external) **не несёт** инфра-полей
  (backend-LUN / NVMe-namespace / storage-node / pool-id / числовой инфра-id / ёмкость) — они
  живут **только** в internal-проекции на :9091 (см. §0.3 out-of-scope, GetInternal — будущий
  data-plane инкремент). Assert: публичный ответ содержит лишь tenant-facing поля (id/name/labels/
  project/zone/diskType/size/status/attachments/usedBy). Проверяется сценарием S1-13.
- **INV-2 — Internal-vs-external (ban #6, `.claude/rules/security.md`).** `InternalVolumeService.*`
  (storage) и `InternalNetworkInterfaceService.Attach/Detach/ListByInstance` (vpc) выставлены
  **только** на :9091 (mTLS) и **не маршрутизируются** на external endpoint. Их отсутствие на
  external REST mux — сам по себе assert (api-gateway audit).
- **INV-2a — AuthN+AuthZ на :9091 ВЕЗДЕ (не только mTLS-транспорт; `.claude/rules/security.md`
  «AuthN+AuthZ ВЕЗДЕ» — hard invariant, internal-листенер :9091 **не** освобождён).** Каждый из 3+3
  внутренних RPC — `InternalVolumeService.Attach/Detach/ListAttachments` (storage) и
  `InternalNetworkInterfaceService.Attach/Detach/ListByInstance` (vpc) — проходит **per-RPC**
  `InternalIAMService.Check` на **обоих** концах (gateway internal-mux `scope_extractor` **и**
  in-service authz-interceptor цепочки :9091), а не только mTLS. Мутации — writer/editor-tier +
  `scope_extractor` на целевой объект (`volume_id` storage / `nic_id` vpc); read
  (`ListAttachments`/`ListByInstance`) — viewer-tier. proto **уже** несёт аннотации (vpc:
  `Attach`/`Detach` `permission=vpc.network_interfaces.attach|detach`, `required_relation=editor`,
  `scope_extractor{vpc_network_interface, nic_id}`; `ListByInstance`
  `permission=vpc.network_interfaces.listByInstance`, `required_relation=viewer`,
  `scope_extractor{cluster, *}`). **Assert:** caller без права → `PERMISSION_DENIED` (behaviour-level,
  не только «отсутствует на external mux», INV-2). Покрывается S2-* (storage :9091) и S4-06 / S3-07
  (object-scoped анти-BOLA на `nic_id`/`volume_id`).
- **INV-3 — Within-service инварианты на DB (ban #10).** «том привязан ≤1 инстансу»,
  «delete привязанного блокируется», «уникальный `device_name` в инстансе», «≤1 boot-том»,
  «увеличение размера» — все на DB-уровне (PK/FK RESTRICT/UNIQUE/EXCLUDE/CAS), **не** через
  `Get→check→write` (TOCTOU). Каждый спорный путь несёт integration-тест с concurrent goroutines.
- **INV-4 — Timestamp truncate** на `Volume`/`Instance`/под-записях (см. 0.1).
- **INV-5 — Мутации async через `Operation`** (ban #9); reads sync; Watch отсутствует.
- **INV-6 — Один владелец свойства (§3b, §7).** Размер диска ресайзится **только** со стороны
  storage (`Volume.Update{size_bytes}`); RPC `:resizeDisk` на `Instance` **не существует**.

---

## 0.3. Out of scope (граница — by-design, НЕ tech-debt)

Сознательно **не** реализуется в этом инкременте; ведёт себя как «нет такого пути», а не «недоделано»:

- **`Instance.Create` inline-attach** (`attach_volume_ids[]` / inline data-volume specs /
  `attach_nic_ids[]`) — те же attach-механики внутри саги создания, но здесь — **только**
  явные `AttachDisk`/`AttachNetworkInterface` на **уже существующих** инстансе, томе и NIC (§2.2).
- **`Volume.Relocate`** (смена зоны) — противоречит immutable `zone_id`, без data-plane
  ничего не «перемещает» (§7). Отдельный эпик.
- **Storage-side liveness-sweep** привязок (storage спрашивает compute «жив ли инстанс») —
  создал бы ребро storage→compute = цикл. Dangling `instance_id` терпится; чистка
  compute-driven (`DetachDisk`/delete-сага) (§3.4, §7).
- **`Instance.Delete` auto-delete-сага** (удаление томов с `auto_delete`, detach всех NIC,
  строка инстанса удаляется последней, список — в `Operation.metadata` для replay, M2) —
  относится к delete-срезу инстанса, здесь только фиксируется delete-safety-инвариант (см. S4-05).
- **Гостевой fs/partition grow** после ресайза — data-plane, не моделируется (§3b).
- **Полный CRUD `DiskType`/`Snapshot`** (admin-поверхность, пагинация, фильтры) — здесь
  покрыты **только** FK-инварианты (RESTRICT / SET NULL), т.к. они затрагивают `Volume` (S1-08/S1-09).
- **`InternalVolumeService.GetInternal` + инфра-проекция** (backend-LUN / NVMe-namespace /
  storage-node / pool-id / числовой инфра-id / ёмкость, §1.1/§1.6 спеки) — **вне этого
  инкремента** (критика #2, вариант b): data-plane отсутствует, заполнять инфра-поля **нечем**;
  RPC и поля вводятся будущим data-plane инкрементом. В **этом** инкременте фиксируется лишь
  инвариант **lean public projection** (INV-7): публичный `Volume` инфра-полей не несёт (S1-13).
  Attach-координация (`Attach`/`Detach`/`ListAttachments`) на :9091 — **в scope** (S2), а
  `GetInternal` — нет.
- **OCI-доставка ОС** (`image`/`image_digest`), rootfs, container/bucket — родительский концепт (§2).

---

## 0.4. Traceability (сценарии спеки A1–A13 → сценарии этого документа)

| Спека | Тема | Сценарий(и) |
|---|---|---|
| A1 | attach happy-path | **S3-01** (+ S2-01 storage-side) |
| A2 | double-attach race (ровно один) | **S2-05** |
| A3 | delete примонтированного блокируется | **S1-07**, **S3-08** (e2e) |
| A4 | zone mismatch | **S3-04** (+ S2-04) |
| A5 | attach на неподходящем статусе | **S3-03** |
| A6 | идемпотентный detach | **S3-06** (+ S2-08) |
| A7 | storage down не роняет `Instance.Get` | **S5-01** |
| A8 | size increase-only + immutable | **S1-04**, **S1-05** |
| A9 | object-scoped authz (анти-BOLA) | **S3-07** (+ S4-06) |
| A10 | несколько NIC на инстанс | **S4-01** (+ S4-02 concurrency) |
| A11 | NIC занят / delete привязанного NIC | **S4-04**, **S4-05** |
| A12 | resize со стороны storage, прозрачно | **S5-04** |
| A13 | NIC zone-coherence + anycast-исключение | **S4-03** |

Добор (нет в A1–A13, требуется по `testing.md`/`data-integrity.md`/`security.md`): базовый CRUD
`Volume` (S1-01..03, S1-06), DiskType/Snapshot FK (S1-08/09), **peer-validate zone/project +
fail-closed** (S1-10, критика #1), **input-валидация size/name** (S1-11), **from-snapshot** (S1-12),
**lean public projection** (S1-13, критика #2), storage-CAS disambiguation (S2-02/03/04/06/07/10),
compute-saga malformed/unavailable/replay/attach-vs-delete/**auto-device-name** (S3-02/05/09/10/11),
NIC auto-index concurrency/idempotent+alt-arm/unavailable (S4-02/06/07),
mirrors output-only/graceful-degrade-List/cpu-guarantee/immutables (S5-01/02/03/05).

---

# Стадия S1 — kacho-storage: `Volume` lifecycle + FK-инварианты

Самостоятельный deliverable: сервис kacho-storage с ресурсом `Volume`, публичным
`VolumeService`, DiskType/Snapshot FK. По графу proto→corelib→storage→api-gateway→deploy→ui.

## Сценарий S1-01: Create `Volume` — happy path (async → Operation), state READY сразу

**Given** проект `P` (существует в kacho-iam), зона `Z` (валидна в kacho-geo), `DiskType` `dtp-std`

**When** клиент вызывает `POST /storage/v1/volumes` с payload:
- `projectId` = `P`
- `name` = `vol-data-1`
- `zoneId` = `Z`
- `diskTypeId` = `dtp-std`
- `sizeBytes` = `10737418240`

**Then** RPC синхронно возвращает `Operation` (op-id с префиксом `sop`), `done=false`
**And** `Operation.metadata` = `CreateVolumeMetadata{volumeId}` с непустым `volumeId` (префикс `vol`)
**And** после полла `OperationService.Get` → `done=true && !error`; `response` — `Volume`
**And** `Get /storage/v1/volumes/{volumeId}` → `Volume` с: `id` (префикс `vol`), `projectId=P`,
  `name=vol-data-1`, `zoneId=Z`, `diskTypeId=dtp-std`, `sizeBytes=10737418240`,
  `blockSize=4096` (default), `createdAt` заполнен и усечён до секунд
**And** `status == AVAILABLE` — derived: `state=READY` (Create переводит сразу, реального
  провижининга нет, §1.4) и attachment'а нет (§1.3)
**And** `attachments` пуст; `usedBy` пуст

## Сценарий S1-02: `Volume.Get` — malformed id (sync) и well-formed-но-нет (NotFound)

**Given** сервис kacho-storage поднят

**When** `GET /storage/v1/volumes/not-a-vol-id`
**Then** **sync** `INVALID_ARGUMENT`, сообщение `invalid volume id 'not-a-vol-id'` (первым
  стейтментом RPC, до repo — §1.6, `.claude/rules/api-conventions.md` malformed-id gotcha)

**When** `GET /storage/v1/volumes/vol00000000000000000` (well-formed, отсутствует)
**Then** `NOT_FOUND`, сообщение `Volume vol00000000000000000 not found`
  (конвенц-паттерн `"<Resource> %s not found"`; точная строка — Q2)

## Сценарий S1-03: `Volume.List` — listauthz-filtered, cursor pagination, filter

**Given** в проекте `P` три тома; вызывающий имеет `viewer` на `P`; в проекте `P2` (нет доступа) — один том

**When** `GET /storage/v1/volumes?projectId=P&pageSize=2`
**Then** sync `ListVolumesResponse`; ≤2 тома, ORDER BY `(created_at, id)` ASC; `nextPageToken` непуст;
  том из `P2` **не** присутствует (listauthz-фильтрация, `.claude/rules/security.md`)

**When** повтор с `pageToken=<nextPageToken>`
**Then** оставшийся том проекта `P`; курсор консистентен, дублей/пропусков нет

**When** `GET /storage/v1/volumes?projectId=P&filter=name=vol-data-1`
**Then** только том с `name=vol-data-1`

**When** `GET /storage/v1/volumes?projectId=P&pageToken=%%%garbage%%%`
**Then** sync `INVALID_ARGUMENT` (битый opaque-токен, `corevalidate`)

## Сценарий S1-04: `Volume.Update` — size increase-only

**Given** том `vol-1` в `AVAILABLE`, `sizeBytes = S` (10 GiB)

**When** `PATCH /storage/v1/volumes/vol-1` с `sizeBytes = S+Δ` (20 GiB), `updateMask=size_bytes`
**Then** Operation `done && !error`; `Get.sizeBytes == S+Δ`; `updatedAt` обновлён

**When** `PATCH /storage/v1/volumes/vol-1` с `sizeBytes = S` меньше текущего (5 GiB)
**Then** Operation error `INVALID_ARGUMENT`, сообщение `Volume size can only be increased`
  (DB-CAS increase-only, не software-compare, §3b; equal-size тоже отклоняется)

## Сценарий S1-05: `Volume.Update` — immutable-поля в mask (sync), пустой mask = full-PATCH

**Given** том `vol-1`

**When** `PATCH /storage/v1/volumes/vol-1` с `updateMask=zone_id`, `zoneId=<other>`
**Then** **sync** `INVALID_ARGUMENT`, сообщение `zone_id is immutable after Volume.Create`
  (immutable-switch **до** `UpdateMask`, §1.6 / api-conventions gotcha)

**And** то же для `updateMask=disk_type_id` → `disk_type_id is immutable after Volume.Create`
**And** для `updateMask=block_size` → `block_size is immutable after Volume.Create`
**And** для `updateMask=source_snapshot_id` → `source_snapshot_id is immutable after Volume.Create`
**And** для `updateMask=used_by` → `used_by is immutable after Volume.Create` (output-only, §1.5)

**When** `PATCH` с **пустым** mask и телом, где заданы `name`/`description`/`labels` (mutable) и
  `zoneId` (immutable)
**Then** Operation done; mutable-поля применены; `zoneId` **silently проигнорирован** (full-object
  PATCH — immutable из тела игнорируются, api-conventions update_mask discipline)

## Сценарий S1-06: `Volume.Update` mutable + partial UNIQUE(project_id, name)

**Given** в проекте `P` тома `vol-a` (`name=alpha`) и `vol-b` (`name=beta`)

**When** `PATCH /storage/v1/volumes/vol-b` с `name=alpha`, `updateMask=name`
**Then** Operation error `ALREADY_EXISTS` (partial `UNIQUE(project_id,name) WHERE name<>''`,
  `23505`; текст — конвенц-паттерн, Q3)

**When** `PATCH /storage/v1/volumes/vol-b` с `name=`, `updateMask=name` (очистка имени)
**Then** Operation done (partial-UNIQUE не действует на пустое имя); повтор на `vol-a` с `name=`
  тоже проходит (два безымянных тома допустимы)

## Сценарий S1-07: `Volume.Delete` — safe-delete через FK RESTRICT [A3]

**Given** том `vol-1` **привязан** к инстансу `ins-1` (есть строка `volume_attachments`)

**When** `DELETE /storage/v1/volumes/vol-1`
**Then** Operation error `FAILED_PRECONDITION`, сообщение **точно** `Volume vol-1 is in use`
  (FK `volume_attachments.volume_id → volumes RESTRICT` `23503`, §3.6 — DB-constraint в своей
  БД, не software-refcount); `Get(vol-1)` по-прежнему возвращает том

**When** после `DetachDisk` (том отвязан) — повтор `DELETE /storage/v1/volumes/vol-1`
**Then** Operation done; `Get(vol-1)` → `NOT_FOUND`

**When** `DELETE /storage/v1/volumes/vol-unattached` (том в `AVAILABLE`, без привязок)
**Then** Operation done; `Get` → `NOT_FOUND`

## Сценарий S1-08: `DiskType` FK RESTRICT (со стороны `Volume`)

**Given** `DiskType` `dtp-std`, на который ссылается том `vol-1` (`diskTypeId=dtp-std`)

**When** `Volume.Create` с `diskTypeId=dtp-nonexistent` (well-formed, отсутствует)
**Then** Operation error `FAILED_PRECONDITION` (`volumes.disk_type_id → disk_types RESTRICT`
  `23503`; текст — конвенц-паттерн `"DiskType %s not found"`, Q4)

**When** `Delete` `DiskType` `dtp-std`, пока `vol-1` на него ссылается
**Then** Operation error `FAILED_PRECONDITION` (RESTRICT блокирует, `23503`; текст
  `"DiskType dtp-std is in use"`, конвенц-паттерн, Q4); `DiskType.Get(dtp-std)` цел

## Сценарий S1-09: `Snapshot` FK SET NULL (обе стороны)

**Given** `Snapshot` `snp-1` (создан из тома `vol-src`, `sourceVolumeId=vol-src`); том `vol-2`
  создан из снапшота (`sourceSnapshotId=snp-1`)

**When** `Delete` `Snapshot` `snp-1` (том `vol-2` на него ссылается)
**Then** Operation done (не блокируется — `volumes.source_snapshot_id → snapshots SET NULL`, §1.2);
  `Get(vol-2).sourceSnapshotId` → пусто; `vol-2` цел

**When** `Delete` том `vol-src` (снапшот `snp-1` ссылается через `source_volume_id`)
**Then** Operation done (`snapshots.source_volume_id → volumes SET NULL`); `Snapshot.Get(snp-1)`
  цел, `sourceVolumeId` → пусто (том-источник больше не гейтит удаление снапшота)

## Сценарий S1-10: `Volume.Create` — peer-validate `zone_id`/`project_id` (cross-service, §4.3)

Ссылки `zone_id` (→ kacho-geo) и `project_id` (→ kacho-iam) — cross-service TEXT-refs **без FK**;
валидируются на **request-path Create** (fail-closed), не только на attach (`data-integrity`
cross-domain rule 2, `polyrepo.md` `*→iam`). Оба ребра one-way (см. INV-1a).

**Given** проект `P` (существует в iam), зона `Z` (валидна в geo), `DiskType` `dtp-std`

**When** `Volume.Create` с `zoneId=z-nonexistent` (well-formed, отсутствует в geo)
**Then** owner-валидация geo (`geo.v1.ZoneService.Get`) не прошла → `INVALID_ARGUMENT`, сообщение
  `unknown zone id 'z-nonexistent'` (зеркалит vpc/compute→geo; sync на request-path до Operation)

**When** `Volume.Create` с `projectId=p-nonexistent` (well-formed, отсутствует в iam)
**Then** owner-валидация iam (`ProjectService.Get`) не прошла → ошибка (`INVALID_ARGUMENT`/
  `FAILED_PRECONDITION` по конвенции `* → iam`; project не существует — том не создаётся)

**When** `Volume.Create` при недоступном kacho-geo **или** kacho-iam
**Then** `UNAVAILABLE` (fail-closed для мутации, §4.3 — как S3-05/S4-07 для storage/vpc);
  том не создаётся, полу-состояния нет

## Сценарий S1-11: `Volume.Create` — input-валидация (`size_bytes`, `name`-формат)

**Given** проект `P`, зона `Z`, `DiskType` `dtp-std`

**When** `Volume.Create` с `sizeBytes = 0` (или отрицательным)
**Then** **sync** `INVALID_ARGUMENT`, сообщение `Illegal argument size_bytes` (self-validating
  domain newtype; DB-backstop `CHECK (size_bytes > 0)` `23514` — важное #1)

**When** `Volume.Create` с `name` длиной >63 символов
**Then** **sync** `INVALID_ARGUMENT`, сообщение `Illegal argument name` (1..63, важное #2)

**When** `Volume.Create` с `name` содержащим uppercase (`Vol-Data`) **или** невалидный символ (`vol_data!`)
**Then** **sync** `INVALID_ARGUMENT`, сообщение `Illegal argument name` (lowercase + допустимый charset)

## Сценарий S1-12: `Volume.Create` — from-snapshot (existence-check в своей БД)

**Given** `Snapshot` `snp-1` (существует в БД storage); проект `P`, зона `Z`, `DiskType` `dtp-std`

**When** `Volume.Create` с `sourceSnapshotId=snp-1` (restore из снапшота, §1.6)
**Then** Operation `done && !error`; `Get.sourceSnapshotId == snp-1`; `state=READY` сразу;
  existence-check `source_snapshot_id` — **в своей БД** (same-DB FK → snapshots, не cross-service)

**When** `Volume.Create` с `sourceSnapshotId=snp-nonexistent` (well-formed, отсутствует)
**Then** ошибка (`FAILED_PRECONDITION`, `volumes.source_snapshot_id → snapshots` FK `23503`;
  снапшот-источник не существует — том не создаётся)

## Сценарий S1-13: публичный `Volume.Get` — lean projection (нет инфра-полей) [INV-7]

**Given** том `vol-1` создан (kacho-storage поднят с data-plane-заглушкой)

**When** `GET /storage/v1/volumes/vol-1` (публичный external endpoint)
**Then** ответ содержит **только** tenant-facing поля (`id`, `projectId`, `name`, `description`,
  `labels`, `zoneId`, `diskTypeId`, `sizeBytes`, `blockSize`, `createdAt`, `updatedAt`, `status`,
  `attachments`, `usedBy`); **не** содержит инфра-полей (backend-LUN / NVMe-namespace /
  storage-node / pool-id / числовой инфра-id / ёмкость) — они только в internal-проекции :9091
  (`.claude/rules/security.md`, §0.3 out-of-scope; `GetInternal` — будущий data-plane инкремент)

> **`VolumeService.ListOperations`** (`GET /storage/v1/volumes/{volumeId}/operations`, §1.6) —
> **corelib-standard boilerplate** (общая `operations`-таблица + reader из `kacho-corelib/operations`,
> идентично прочим ресурсам всех сервисов). Отдельный поведенческий сценарий не пишется; покрывается
> corelib-контрактом + один smoke-assert в newman S1-01 (после `Create` — `ListOperations` возвращает
> ту самую op). Малформед `vol`-id → sync `invalid volume id '<X>'` (как S1-02).

> **DoD S1:** proto+regen (`buf lint`/`breaking` зелёные); goose-миграции storage (volumes,
> volume_attachments, disk_types, snapshots — FK RESTRICT/SET NULL, partial-UNIQUE, CHECK
> `size_bytes>0`, derived-status view/logic); repo (sqlc + handwritten pgx, без ORM); use-case +
> thin handler; self-validating domain newtypes (`name` 1..63 lowercase, `size_bytes>0`);
> geo-client + iam-client (peer-validate `zone_id`/`project_id` на request-path, per-call timeout,
> mTLS, fail-closed `Unavailable`) + fgaproxy `RegisterResource`/`UnregisterResource` owner-tuple
> (transactional-outbox); outbox-транзакционный Operation; integration-тест (testcontainers: CRUD,
> size-CAS, immutable, partial-UNIQUE-collision, FK RESTRICT/SET NULL, `size_bytes>0` CHECK,
> from-snapshot FK) RED→GREEN; newman **S1-01** happy + **S1-02** (malformed/not-found) + **S1-03**
> (List: listauthz + cursor + `filter=name` + garbage-token) + **S1-04** (size increase-only) +
> **S1-05** (immutable) + **S1-06** (name-collision `ALREADY_EXISTS`) + **S1-07** (safe-delete) +
> **S1-08** (DiskType FK) + **S1-10** (peer-validate zone/project/unavailable) + **S1-11**
> (input-validation) + **S1-13** (lean projection); api-gateway REST-регистрация `VolumeService`
> (public); ацикличность/one-way рёбра `storage→geo`/`storage→iam` в `polyrepo.md`; vault
> (`resources/storage-volume`, `rpc/storage-volume-service`, `edges/storage-to-geo-zone-validate`,
> `edges/storage-to-iam-project-validate`).

---

# Стадия S2 — kacho-storage: `InternalVolumeService` attach-CAS (:9091)

Внутренняя координация attach: атомарный CAS на `volume_attachments` (§3.2). Тестируется через
integration/bufconn; на external mux **не** выставлена (INV-2). Все сценарии — за счёт
self-describing payload (`volume_id, instance_id, instance_name, instance_zone_id, project_id,
device_name, is_boot, mode, auto_delete`); storage **не** зовёт compute.

## Сценарий S2-01: `Attach` — happy CAS-insert, derived IN_USE, used_by

**Given** том `vol-1` в `state=READY` (`AVAILABLE`), зона `Z`, проект `P`

**When** `InternalVolumeService.Attach{volumeId=vol-1, instanceId=ins-1, instanceName="web-1",
  instanceZoneId=Z, projectId=P, deviceName="sdb", mode=READ_WRITE}`
**Then** sync OK (CAS-insert прошёл, 1 row); `Get(vol-1).status == IN_USE` (derived);
  `attachments[0]` = `{instanceId=ins-1, instanceName="web-1", deviceName="sdb", isBoot=false,
  mode=READ_WRITE, attachedAt=<truncated-sec>}`
**And** `usedBy` = 1 ref `{referrer:{type:"compute.instance", id:ins-1, name:"web-1"},
  type:USED_BY, owned:false}` (derive-on-read из `volume_attachments`, §1.5)

## Сценарий S2-02: `Attach` — идемпотентный replay (тот же инстанс) → OK

**Given** `vol-1` уже привязан к `ins-1`

**When** повтор `Attach{volumeId=vol-1, instanceId=ins-1, ...те же параметры}`
**Then** sync OK (conflict-строка есть и `instance_id` = наш → идемпотентный OK, §3.2);
  ровно одна строка `volume_attachments`; дубля нет

## Сценарий S2-03: `Attach` — том не READY → FailedPrecondition

**Given** том `vol-creating` в `state=CREATING` (или `DELETING`/`ERROR`)

**When** `Attach{volumeId=vol-creating, ...}`
**Then** `FAILED_PRECONDITION`, сообщение `Volume is not available for attachment`
  (CAS `WHERE state='READY'` не сматчил; disambiguation, §3.2)

## Сценарий S2-04: `Attach` — zone/project mismatch → FailedPrecondition (два раздельных текста)

> **Amendment 2026-07-15 (механическая, поведение не меняет):** zone- и project-mismatch несут
> **разные** нормативные тексты — прежняя схлопнутая формулировка (оба → zone-текст) была
> вводящей в заблуждение (assert'ился бы «same zone» при реальном project-mismatch). Авторитет —
> `sub-phase-CS-1-storage-network-disk-acceptance.md` §0.0/INV-4 (CS1-S4-05); трекинг `kacho-workspace#132`.

**Given** том `vol-1` в зоне `Z1`, проект `P`

**When** `Attach{volumeId=vol-1, instanceZoneId=Z2, projectId=P, ...}` (расходится **только** зона)
**Then** `FAILED_PRECONDITION`, сообщение `Volume and Instance must be in the same zone`
  (zone-предикат CAS `zone_id=$zone` не сматчил при `state=READY`; §3.2)

**When** `Attach{volumeId=vol-1, instanceZoneId=Z1, projectId=P2, ...}` (расходится **только** проект)
**Then** `FAILED_PRECONDITION`, сообщение **`Volume and Instance must be in the same project`**
  (project-предикат CAS `project_id=$project` не сматчил — **отдельный** текст, assert **именно**
  его, не zone-строку; disambiguation-SELECT в той же TX после 0-row, §3.2)

## Сценарий S2-05: double-attach race — ровно один (CAS, concurrency) [A2]

**Given** том `vol-1` в `AVAILABLE`, два разных инстанса `ins-a`, `ins-b` (та же зона/проект)

**When** две **конкурентные** `Attach{vol-1, ins-a}` и `Attach{vol-1, ins-b}`
**Then** **ровно одна** возвращает OK (её `instance_id` в `volume_attachments`); другая →
  `FAILED_PRECONDITION`, сообщение `Volume vol-1 is in use` (`INSERT … ON CONFLICT (volume_id)
  DO NOTHING` → 0 rows → disambiguation видит чужую строку, §3.2; PK row-lock на `volume_id`)
**And** integration-тест под `-race`, детерминированно (blocker держит слот, backlog, **не**
  `time.Sleep`), `.claude/rules/data-integrity.md` чек-лист п.5

## Сценарий S2-06: `Attach` — коллизия device_name в инстансе → FailedPrecondition

**Given** к `ins-1` привязан `vol-1` с `deviceName="sdb"`

**When** `Attach{volumeId=vol-2, instanceId=ins-1, deviceName="sdb", ...}` (тот же инстанс, то же имя)
**Then** `FAILED_PRECONDITION`, сообщение **точно** `device sdb is already in use on Instance ins-1`
  (`UNIQUE(instance_id, device_name)` `23505`, §3.2)

## Сценарий S2-07: `Attach` — второй boot-том на инстанс → FailedPrecondition (EXCLUDE)

**Given** к `ins-1` привязан boot-том `vol-boot1` (`isBoot=true`)

**When** `Attach{volumeId=vol-boot2, instanceId=ins-1, isBoot=true, deviceName="sdc", ...}`
**Then** `FAILED_PRECONDITION` (`EXCLUDE (instance_id WITH =) WHERE is_boot` `23P01`, §1.2/§3.2;
  ≤1 boot-том на инстанс; текст `"Instance ins-1 already has a boot volume"`, конвенц-паттерн, Q5)

## Сценарий S2-08: `Detach` — идемпотентный [A6]

**Given** том `vol-1` привязан к `ins-1`

**When** `Detach{volumeId=vol-1, instanceId=ins-1}`
**Then** sync OK; строка `volume_attachments` удалена; `Get(vol-1).status == AVAILABLE` (derived)

**When** повтор `Detach{volumeId=vol-1, instanceId=ins-1}` (уже отвязан)
**Then** sync OK, no-op (DELETE 0 rows → идемпотентный OK, §3.3); без ошибки

## Сценарий S2-09: `ListAttachments` — batched (не N+1)

**Given** привязки: `vol-1→ins-1`, `vol-2→ins-1`, `vol-3→ins-2`

**When** `ListAttachments{instanceIds=[ins-1, ins-2]}` (один batched-вызов)
**Then** sync-ответ: для `ins-1` — 2 attachment'а (`vol-1`, `vol-2`), для `ins-2` — 1 (`vol-3`);
  один запрос на всё множество (для зеркала `Instance.Get/List`, §1.6/§3.5)

## Сценарий S2-10: INTERNAL-leak guard (behaviour-level)

**Given** искусственно вызванная не-замапленная repo/DB-ошибка на пути `Attach`

**When** `Attach{...}`
**Then** `INTERNAL`, сообщение **ровно** `internal error` (`NotContains(msg, <raw pgx/SQL текст>)`,
  без host/port/user/db — §1.7 / `.claude/rules/security.md` hardening-инвариант #1); правило и на :9091

> **DoD S2:** proto `InternalVolumeService` (Internal, :9091); CAS-логика (INSERT…ON CONFLICT +
> disambiguation-SELECT в одной TX); SQLSTATE→gRPC mapper (`23503`/`23505`/`23P01`→
> FailedPrecondition, default→фикс. `internal error`); integration (testcontainers: CAS-insert,
> idempotent-replay, not-READY, zone/project-mismatch, **concurrent double-attach `-race`**,
> device-collision, boot-EXCLUDE, idempotent-detach, batched-list, leak-guard) RED→GREEN;
> mTLS+authz-Check на :9091 (writer-tier + `scope_extractor` на `volume_id`); api-gateway audit —
> отсутствие на external mux; vault (`rpc/storage-internal-volume-service`,
> `edges/compute-to-storage-attach`).

---

# Стадия S3 — kacho-compute: `AttachDisk` / `DetachDisk` (async сага)

Сага координирует storage (§3.1). Sync-фаза: malformed-id + object-scoped authz → возврат
`Operation`. Async-worker: compute-local CAS-гейт (`state IN {RUNNING,STOPPED}`) → storage
`Attach` (per-call timeout, mTLS, retry-on-Unavailable, fail-closed) → `MarkDone`/`MarkError`.

## Сценарий S3-01: `AttachDisk` — happy end-to-end [A1]

**Given** инстанс `ins-1` в `RUNNING`, зона `Z`, проект `P`; том `vol-1` в `AVAILABLE`, зона `Z`, проект `P`

**When** `POST /compute/v1/instances/ins-1:attachDisk` с payload:
- `volumeId` = `vol-1`
- `deviceName` = `sdb`
- `mode` = `READ_WRITE`
- `isBoot` = `false`

**Then** RPC синхронно возвращает `Operation` (op-id префикс `epd`), `metadata`
  = `AttachInstanceDiskMetadata{instanceId=ins-1, volumeId=vol-1}`
**And** после полла — `done=true && !error`, `response` = `Instance`
**And** `storage Volume.Get(vol-1).status == IN_USE`; `attachments[0].instanceId == ins-1`
**And** `compute Instance.Get(ins-1).secondaryVolumes` содержит `{volumeId=vol-1, deviceName="sdb",
  isBoot=false, mode=READ_WRITE, attachedAt=<sec>}` (зеркало, пересчитано на чтении)
**And** `Volume.usedBy` = 1 ref `{compute.instance, ins-1}`

## Сценарий S3-02: `AttachDisk` — malformed id (sync, до Operation)

**Given** инстанс `ins-1` в `RUNNING`

**When** `POST /compute/v1/instances/not-an-ins:attachDisk {volumeId:vol-1}`
**Then** **sync** `INVALID_ARGUMENT`, сообщение `invalid instance id 'not-an-ins'` (первым
  стейтментом, §3.1)

**When** `POST /compute/v1/instances/ins-1:attachDisk {volumeId:"bad-vol"}`
**Then** **sync** `INVALID_ARGUMENT`, сообщение `invalid volume id 'bad-vol'` (§3.1)

## Сценарий S3-03: `AttachDisk` — инстанс не в {RUNNING, STOPPED} [A5]

**Given** инстанс `ins-1` в `PROVISIONING` (или `DELETING`/`STOPPING`/`STARTING`/`ERROR`); том `vol-1` в `AVAILABLE`

**When** `POST /compute/v1/instances/ins-1:attachDisk {volumeId:vol-1}`
**Then** Operation error `FAILED_PRECONDITION`, сообщение `Instance must be RUNNING or STOPPED`
  (compute-local CAS-гейт `WHERE state IN ('RUNNING','STOPPED')` → 0 rows, §3.1); строка
  `volume_attachments` **не** создана (storage не вызван)

## Сценарий S3-04: `AttachDisk` — zone mismatch [A4]

**Given** инстанс `ins-1` в зоне `Z1` (`RUNNING`); том `vol-2` в зоне `Z2` (`AVAILABLE`)

**When** `POST /compute/v1/instances/ins-1:attachDisk {volumeId:vol-2}`
**Then** Operation error `FAILED_PRECONDITION`, сообщение `Volume and Instance must be in the
  same zone` (storage CAS zone-coherence из self-describing payload; compute **не** сообщает
  storage состояние тома — storage валидирует свою строку, §3.2)

## Сценарий S3-05: `AttachDisk` — storage `Unavailable` → fail-closed

**Given** инстанс `ins-1` в `RUNNING`, том `vol-1` в `AVAILABLE`; kacho-storage недоступен

**When** `POST /compute/v1/instances/ins-1:attachDisk {volumeId:vol-1}`
**Then** worker ретраит `Attach` (per-call `context.WithTimeout`, retry-on-Unavailable); всё
  ещё недоступен → Operation error `UNAVAILABLE` (fail-closed для мутации, §3.1/§4.1);
  полу-состояния нет — compute локально ничего не пишет, storage при неуспешном CAS не коммитит

## Сценарий S3-06: `DetachDisk` — идемпотентный + запрет detach boot [A6]

**Given** к `ins-1` (`RUNNING`) привязан data-том `vol-1` (`deviceName=sdb`, `isBoot=false`)

**When** `POST /compute/v1/instances/ins-1:detachDisk {volumeId:vol-1}`
**Then** Operation done; `Volume.Get(vol-1).status == AVAILABLE`; `Instance.secondaryVolumes` не содержит `vol-1`

**When** повтор `POST …:detachDisk {volumeId:vol-1}` (уже отвязан)
**Then** Operation done, no-op (идемпотентно, §3.3), без ошибки

**When** `DetachDisk` **по alt-arm** `deviceName=sdb` (oneof-ветка `device_name`, не `volume_id`) для
  повторно привязанного data-тома `vol-1` (`deviceName=sdb`)
**Then** Operation done; `Volume.Get(vol-1).status == AVAILABLE`; `Instance.secondaryVolumes` не
  содержит `vol-1` — обе oneof-ветки (`volume_id` / `device_name`) **эквивалентны** по эффекту (§2.2)

**When** `DetachDisk` с телом без `volumeId` и без `deviceName` (или оба заданы)
**Then** **sync** `INVALID_ARGUMENT` (oneof `exactly_one` нарушен, §2.2)

**When** `DetachDisk` boot-тома (`isBoot=true`)
**Then** Operation error `FAILED_PRECONDITION` (boot не отвязывается, §2.2/§3.3; текст
  `"boot volume cannot be detached"`, конвенц-паттерн, Q6)

## Сценарий S3-07: object-scoped authz — анти-BOLA (sync) [A9]

**Given** вызывающий имеет writer-право на `ins-1` (свой проект `P`), но **не** имеет права на
  `vol-x` (чужой проект `P2`)

**When** `POST /compute/v1/instances/ins-1:attachDisk {volumeId:vol-x}`
**Then** **sync** `PERMISSION_DENIED` — per-RPC `Check` с `scope_extractor` на **обоих** целевых
  объектах (`instance_id` compute.instance **и** `volume_id` storage.volume); нельзя attach'ить
  чужой том в свой инстанс (§3.1 шаг 3, `.claude/rules/security.md` object-scoped authz);
  `Operation` **не** создаётся, storage **не** вызывается

## Сценарий S3-08: delete-in-use e2e — compute attach → storage delete-guard [A3]

**Given** том `vol-1` привязан к `ins-1` через `AttachDisk` (Operation done)

**When** `DELETE /storage/v1/volumes/vol-1`
**Then** Operation error `FAILED_PRECONDITION`, сообщение `Volume vol-1 is in use` (см. S1-07;
  DB-constraint в БД storage, не cross-service-handshake)

**When** `POST /compute/v1/instances/ins-1:detachDisk {volumeId:vol-1}` → done; затем `DELETE …/vol-1`
**Then** Operation done; `Volume.Get(vol-1)` → `NOT_FOUND`

## Сценарий S3-09: worker crash-replay — идемпотентность саги

**Given** `AttachDisk` для `vol-1`/`ins-1`; worker падает **после** storage-`Attach`, но **до** `MarkDone`

**When** corelib `operations` Reconciler повторяет `fn(ctx)`
**Then** гейт-CAS проходит (инстанс всё ещё `RUNNING`/`STOPPED`); `Attach` повторно →
  `ON CONFLICT DO NOTHING` + «уже наш» → идемпотентный OK → `MarkDone`; ровно одна строка
  `volume_attachments`; финальный `Operation` `done && !error` (§3.4)

## Сценарий S3-10: attach-vs-delete race (сага против Instance.Delete)

**Given** инстанс `ins-1` в `RUNNING`; конкурентно инициированы `AttachDisk{vol-1}` и `Instance.Delete(ins-1)`

**When** `Instance.Delete` первым переводит инстанс в `DELETING`
**Then** `AttachDisk`-worker: compute-local гейт `WHERE state IN ('RUNNING','STOPPED')` → 0 rows →
  Operation error `FAILED_PRECONDITION` `Instance must be RUNNING or STOPPED` (§3.1 — тот же
  гейт закрывает attach-vs-delete гонку); осиротевшей привязки не остаётся (storage не вызван)

## Сценарий S3-11: `AttachDisk` — пустой `deviceName` → авто-назначение уникального имени

**Given** инстанс `ins-1` в `RUNNING`, зона `Z`, проект `P`; том `vol-1` в `AVAILABLE`, зона `Z`,
  проект `P`; на `ins-1` **нет** привязок с `deviceName` (или занято `sdb`)

**When** `POST /compute/v1/instances/ins-1:attachDisk {volumeId:vol-1}` (**без** `deviceName`)
**Then** Operation `done && !error`; storage присваивает **первое свободное** уникальное имя
  устройства в инстансе (§2.2 `device_name` optional — авто-назначение если пусто);
  `Volume.Get(vol-1).attachments[0].deviceName` непуст и **уникален** в пределах `ins-1`
  (`UNIQUE(instance_id, device_name)` не нарушен); `Instance.secondaryVolumes` несёт это имя

**When** повтор `AttachDisk {volumeId:vol-2}` (без `deviceName`) на тот же `ins-1`
**Then** Operation done; `vol-2` получает **другое** свободное имя (коллизии device_name нет)

> **DoD S3:** proto `AttachDisk`/`DetachDisk` (Operation, REST `:attachDisk`/`:detachDisk`,
> `AttachedDiskSpec`, `DetachDisk` oneof `exactly_one`); compute-local гейт-CAS
> (`instances … WHERE state IN (…) RETURNING`); storage-client (port в use-case, impl в
> `clients/`, per-call timeout, mTLS, retry-on-Unavailable, fail-closed); saga-worker
> idempotent+replay; object-scoped authz (`scope_extractor` на `instance_id`+`volume_id`);
> integration (гейт-CAS, unavailable-fail-closed, replay, auto-device-name) + unit (fake-порты,
> malformed/authz) RED→GREEN; newman S3-01/S3-11 happy (attach + auto-device-name) +
> S3-02/03/04/06/07/08 negative (incl. S3-06 detach-by-deviceName alt-arm); api-gateway REST-регистрация
> (public `:attachDisk`/`:detachDisk`); vault (`rpc/compute-instance-service` attach-методы,
> `edges/compute-to-storage-attach`).

---

# Стадия S4 — kacho-compute: `AttachNetworkInterface` / `DetachNetworkInterface`

Симметрично disk-attach, но владелец привязки — **kacho-vpc** (NIC first-class, §3a). Оживляет
ребро `compute → vpc`, разорванное в KAC-266 (`[[edges/compute-to-vpc-nic-validate]]`). Привязка
живёт на строке NIC (`used_by_id`/`used_by_kind` уже есть + новый `used_by_index`). **Несколько
NIC на инстанс**; NIC → ≤1 инстанс (CAS `used_by_id='' OR =наш`, **нет** глобального
`UNIQUE(used_by_id)` — урок миграций vpc 0016/0017).

## Сценарий S4-01: несколько NIC на инстанс — happy [A10]

**Given** инстанс `ins-1` в `STOPPED`, зона `Z`, проект `P`; два NIC `enp-1`, `enp-2` в состоянии
  DETACHED (`used_by_id=''`), в ZONAL-subnet зоны `Z`, проект `P`

**When** `POST /compute/v1/instances/ins-1:attachNetworkInterface {nicId:enp-1}` → done, затем
  `POST …:attachNetworkInterface {nicId:enp-2}` → done
**Then** оба Operation `done && !error`; `Instance.Get(ins-1).networkInterfaces` = 2 элемента с
  `index` 0 и 1 (авто-назначение первого свободного слота, §3a.2); зеркала несут `nicId`,
  `subnetId`, `primaryV4Address`, … (source of truth = vpc, §2.1)
**And** `vpc NetworkInterface.Get(enp-1).usedById == ins-1`, `usedByKind == instance`, `usedByIndex == 0`;
  `enp-2 → usedByIndex == 1` (подтверждает multi-NIC — нет глобального `UNIQUE(used_by_id)`)

## Сценарий S4-02: auto-index concurrency — два NIC, один инстанс (race)

**Given** инстанс `ins-1` (`STOPPED`); два DETACHED NIC `enp-a`, `enp-b` (та же зона/проект), оба без явного `index`

**When** две **конкурентные** `AttachNetworkInterface{ins-1, enp-a}` и `{ins-1, enp-b}` (index не задан)
**Then** оба `done`; **распределены разные слоты** `used_by_index` (0 и 1), lost-update нет
  (partial `UNIQUE(used_by_id, used_by_index) WHERE used_by_id<>''`; single-statement CAS row-lock,
  §3a.1); integration `-race`, детерминированно

## Сценарий S4-03: NIC zone-coherence + anycast-исключение [A13]

**Given** инстанс `ins-1` в зоне `Z1` (`STOPPED`), проект `P`; NIC `enp-z1` в **ZONAL**-subnet зоны
  `Z1`; NIC `enp-z2` в **ZONAL**-subnet зоны `Z2`; NIC `enp-any` в **REGIONAL**-subnet (anycast, зоны нет)
**And** ZONAL/REGIONAL-subnet — **существующая** placement-схема vpc (не вводится в S4): колонки
  `subnets.placement_type` IN (`ZONAL`,`REGIONAL`) + `region_id`, CHECK `subnets_placement_payload_chk`
  (`ZONAL`⇒`zone_id<>'' AND region_id=''` / `REGIONAL`⇒`zone_id='' AND region_id<>''`) — **применённая**
  миграция `0012_subnet_placement`, `domain/subnet.go` (`PlacementZonal`/`PlacementRegional`). S4
  новых subnet-полей не добавляет — zone-coherence-CAS лишь **читает** `placement_type`/`zone_id` (§3a.1)

**When** `POST /compute/v1/instances/ins-1:attachNetworkInterface {nicId:enp-z2}`
**Then** Operation error `FAILED_PRECONDITION`, сообщение `NetworkInterface subnet is in zone Z2,
  instance zone is Z1` (ZONAL-subnet: `s.zone_id == instance_zone_id` не сматчил; зона NIC —
  производная от subnet, §3a.1)

**When** `POST …:attachNetworkInterface {nicId:enp-any}` (REGIONAL/anycast)
**Then** Operation done — zone-check **пропущен** (`placement_type=REGIONAL`, `zone_id=''`, сравнивать
  не с чем; ровно «исключение anycast», §3a.1)

**When** `POST …:attachNetworkInterface {nicId:enp-z1}` (ZONAL, зона `Z1`)
**Then** Operation done (`subnet.zone_id == instance.zone_id`)
**And** инвариант: Instance + Disk + NIC — в одной зоне, кроме NIC на REGIONAL-subnet

## Сценарий S4-04: NIC занят другим инстансом [A11a]

**Given** NIC `enp-1` уже привязан к `ins-1` (`used_by_id=ins-1`); инстанс `ins-2` в `STOPPED` (та же зона/проект)

**When** `POST /compute/v1/instances/ins-2:attachNetworkInterface {nicId:enp-1}`
**Then** Operation error `FAILED_PRECONDITION`, сообщение `NetworkInterface is in use`
  (CAS `WHERE used_by_id='' OR used_by_id=$instance_id` → 0 rows; disambiguation видит чужой
  инстанс, §3a.1)

**When** две **конкурентные** `AttachNetworkInterface{enp-free}` на `ins-1` и `ins-2`
**Then** ровно одна `done`; другая → `FAILED_PRECONDITION` `NetworkInterface is in use`
  (single-statement CAS row-lock; NIC → ≤1 инстанс)

## Сценарий S4-05: NIC delete-safety [A11b]

**Given** NIC `enp-1` привязан к `ins-1` (`used_by_id` непуст)

**When** `DELETE /vpc/v1/networkInterfaces/enp-1`
**Then** Operation error `FAILED_PRECONDITION`, сообщение **точно** `network interface enp-1 is
  still attached to instance ins-1; detach it first` (**verbatim** существующий kacho-vpc
  `networkinterface/delete.go`: `"network interface %s is still attached to %s %s; detach it first"`,
  params `id, used_by_type, used_by_id` — Q7 закрыт; delete при непустом `used_by_id` запрещён,
  `[[resources/vpc-networkinterface]]` §Lifecycle); `NetworkInterface.Get(enp-1)` цел

**When** `DetachNetworkInterface(ins-1, enp-1)` → done; затем `DELETE …/enp-1`
**Then** Operation done; NIC удалён (delete-safety снят после detach)

## Сценарий S4-06: `DetachNetworkInterface` идемпотентный + malformed + authz

**Given** NIC `enp-1` привязан к `ins-1` (`STOPPED`)

**When** `POST /compute/v1/instances/ins-1:detachNetworkInterface {nicId:enp-1}`
**Then** Operation done; `vpc NetworkInterface.Get(enp-1).usedById == ''`, `usedByIndex` очищен;
  `Instance.networkInterfaces` не содержит `enp-1`

**When** `…:detachNetworkInterface {index:0}` **по alt-arm** `index` (oneof-ветка `index`, не `nic_id`)
  для повторно привязанного NIC `enp-1` (`usedByIndex=0`)
**Then** Operation done; `vpc NetworkInterface.Get(enp-1).usedById == ''`, `usedByIndex` очищен —
  обе oneof-ветки (`nic_id` / `index`) **эквивалентны** по эффекту (§2.2)

**When** повтор `…:detachNetworkInterface {nicId:enp-1}` (уже отвязан)
**Then** Operation done, no-op (идемпотентно, §3a.2), без ошибки

**When** `…:detachNetworkInterface` с телом без `nicId` и без `index` (или оба)
**Then** **sync** `INVALID_ARGUMENT` (oneof `exactly_one`, §2.2)

**When** `…:attachNetworkInterface {nicId:"bad-nic"}`
**Then** **sync** `INVALID_ARGUMENT`, сообщение **точно** `invalid network interface id 'bad-nic'`
  (§3a.2; malformed `enp`-id первым стейтментом — **verbatim** kacho-vpc `corevalidate.ResourceID`,
  `niResource="network interface"`, формат `invalid %s id '%s'` — Q7 закрыт)

**When** вызывающий имеет writer на `ins-1`, но **не** на `enp-x` (чужой проект)
**Then** **sync** `PERMISSION_DENIED` (object-scoped `Check` на `instance_id` **и** `nic_id`, §3a.2)

## Сценарий S4-07: vpc `Unavailable` → fail-closed

**Given** инстанс `ins-1` (`STOPPED`), NIC `enp-1` (DETACHED, та же зона/проект); kacho-vpc недоступен

**When** `POST /compute/v1/instances/ins-1:attachNetworkInterface {nicId:enp-1}`
**Then** worker ретраит; всё ещё недоступен → Operation error `UNAVAILABLE` (fail-closed, §3a.2/§4.2);
  полу-состояния нет (compute локально не пишет)

> **DoD S4:** proto `AttachNetworkInterface`/`DetachNetworkInterface` (Operation, REST-verbs,
> `AttachedNicSpec`, `DetachNetworkInterface` oneof); vpc goose-миграция — **новая** миграция S4 =
> **только** `used_by_index` + partial `UNIQUE(used_by_id, used_by_index) WHERE used_by_id<>''`
> (placement-схема subnet — **pre-existing**, применённая миграция `0012_subnet_placement`:
> `placement_type` IN (`ZONAL`,`REGIONAL`) / `region_id` / CHECK `subnets_placement_payload_chk`;
> zone-coherence-CAS её лишь **читает**, в placement ничего не добавляя); restore vpc
> `InternalNetworkInterfaceService.Attach/Detach/ListByInstance` (:9091, mTLS SEC-M **+ per-RPC
> authz-Check** — не только mTLS, симметрично DoD S2: `Attach`/`Detach` writer/editor-tier +
> `scope_extractor` на `nic_id`, `ListByInstance` viewer-tier/cluster-scoped; proto-аннотации
> `internal_network_interface_service.proto` **уже присутствуют** — энфорс на обоих концах) с
> zone-coherence+anycast CAS; compute saga-worker + vpc-client (per-call timeout, fail-closed);
> object-scoped authz на `instance_id`+`nic_id`; integration (CAS, **auto-index concurrency `-race`**,
> **nic-in-use concurrency `-race`**, zone/anycast, delete-safety, **per-RPC Check deny→PERMISSION_DENIED
> на :9091**, INV-2a) + unit (malformed/authz) RED→GREEN; newman S4-01 happy + S4-03/04/05/06 negative;
> api-gateway REST-регистрация (public compute-verbs; vpc Internal.* — **не** на external, **и**
> per-RPC Check на internal-mux); vault (`edges/compute-to-vpc-nic-validate` → revived,
> `resources/vpc-networkinterface` `used_by_index`, `rpc/vpc-internal-networkinterface-service`;
> **follow-up trail:** `resources/vpc-subnet` устарела — записка **чисто зональная**, подлежит
> обновлению под placement-схему `placement_type`/`region_id` (миграция `0012_subnet_placement` уже
> в коде — записка отстала от реальности).

---

# Стадия S5 — Зеркала, graceful-degrade, ресайз, cpu_guarantee

Read-only проекции attach-состояния на `Instance` (source of truth = storage/vpc), устойчивость
к недоступности owner'а, ресайз только со стороны storage, `cpu_guarantee_percent`.

## Сценарий S5-01: storage/vpc down → `Instance.Get`/`List` graceful-degrade [A7]

**Given** инстанс `ins-1` с примонтированным томом `vol-1` и NIC `enp-1`; kacho-storage **недоступен**

**When** `GET /compute/v1/instances/ins-1`
**Then** инстанс возвращается **успешно** (не падает); disk-зеркало (`bootVolume`/`secondaryVolumes`)
  **опущено/помечено stale** (best-effort, ban #4 — consumer грациозно переживает dangling, §3.5)

**When** kacho-vpc недоступен
**Then** `Get(ins-1)` успешен; NIC-зеркало (`networkInterfaces`) опущено/stale; Get не падает (§3a.3)

**When** `GET /compute/v1/instances?projectId=P` при недоступном storage/vpc
**Then** список инстансов возвращается; зеркала опущены/stale; **один batched** `ListAttachments`/
  `ListByInstance` (не N+1, §3.5), деградация не роняет `List`

## Сценарий S5-02: зеркала output-only (не принимаются на вход)

**Given** инстанс `ins-1`

**When** `Instance.Update` с телом, содержащим `bootVolume`/`secondaryVolumes`/`networkInterfaces`
  (в mask или в full-PATCH)
**Then** зеркала **silently проигнорированы** (output-only, mask не применяет; source of truth =
  storage/vpc, §2.1) — реальное attach-состояние меняется **только** через
  `AttachDisk`/`AttachNetworkInterface`, не через `Instance.Update`

## Сценарий S5-03: `cpu_guarantee_percent` bounds + sizing только при STOPPED

**Given** инстанс `ins-1`

**When** `Instance.Create`/`Update` с `cpuGuaranteePercent = 0`
**Then** OK — `0` = best-effort/burstable (без гарантии, §2.1)

**When** `cpuGuaranteePercent = 50` (инстанс `STOPPED`)
**Then** OK — гарантированный baseline 50% на vCPU

**When** `cpuGuaranteePercent = 101` (или `-1`)
**Then** `INVALID_ARGUMENT` (`CHECK 0..100` `23514`; текст — конвенц-паттерн `"Illegal argument
  cpu_guarantee_percent"`, Q6)

**When** `Update` `cpuGuaranteePercent` (или `vcpus`/`memory_bytes`) при инстансе в `RUNNING`
**Then** Operation error `FAILED_PRECONDITION` — sizing меняется **только** при `STOPPED` (§2.1/§5;
  текст `"Instance must be STOPPED to change sizing"`, конвенц-паттерн, Q6)

## Сценарий S5-04: ресайз диска со стороны storage, прозрачно для инстанса [A12]

**Given** том `vol-1` в `IN_USE` (примонтирован к `ins-1`), `sizeBytes = S`

**When** `PATCH /storage/v1/volumes/vol-1 {sizeBytes: S+Δ}` (том в IN_USE)
**Then** Operation done; `Volume.Get(vol-1).sizeBytes == S+Δ`; том остаётся `IN_USE` (CAS не смотрит
  на attachment — online-grow примонтированного тома разрешён, §3b); **никакого RPC на `Instance`**
  не требуется; на `Instance` **нет** `:resizeDisk` (INV-6)
**And** инстанс видит новый размер на следующем `Volume.Get` через своё зеркало (`AttachedVolume`
  не несёт `size`; size читается с `Volume`, §3b)

**When** `PATCH …/vol-1 {sizeBytes: S-1}` (уменьшение)
**Then** Operation error `INVALID_ARGUMENT`, сообщение `Volume size can only be increased` (см. S1-04)

## Сценарий S5-05: `Instance` immutable-поля

**Given** инстанс `ins-1`

**When** `Instance.Update` с `updateMask=zone_id`
**Then** **sync** `INVALID_ARGUMENT`, сообщение `zone_id is immutable after Instance.Create`
  (immutable-switch до UpdateMask; текст по конвенц-паттерну, Q6)

**When** `Instance.Create`/`Update` с заданным `imageDigest`
**Then** `imageDigest` **не принимается на вход** (output-only digest-pin, §2.1) — на входе
  игнорируется/отвергается; заполняется системой из `image`

> **DoD S5:** зеркало-резолвер на `Instance.Get`/`List` (batched `ListAttachments`/`ListByInstance`,
> graceful-degrade при `Unavailable`); зеркала output-only в mask/handler; proto
> `cpu_guarantee_percent` (`CHECK 0..100`) + sizing-STOPPED-guard; size-CAS increase-only на
> IN_USE (см. S1/S2); integration (degrade-Get/List, resize-on-IN_USE, cpu-bounds, sizing-guard) +
> unit (immutable/output-only) RED→GREEN; newman S5-03/04 (bounds/resize) + degrade-негатив; UI —
> отображение зеркал `bootVolume`/`secondaryVolumes`/`networkInterfaces` + форма
> `cpuGuaranteePercent`; vault (`resources/compute-instance`, `edges/compute-to-storage-attach`).

---

## Решённые вопросы (Q1–Q7 — зафиксированы acceptance-reviewer'ом)

Все строки/решения ниже — **финализированы** и внесены в error-таблицу (§0.1) и сценарии.
Больше не «открыты»; менять — только осознанно через тикет (тексты — часть контракта).

- **Q1 — ID-префиксы (Amendment 2026-07-15): `DiskType`=admin-slug, `Snapshot`=`snp`.**
  `DiskType.id` — admin-assigned человекочитаемый slug (напр. `block-balanced`), PK-строка, **не**
  генерируемый `dtp`-префикс (grounded в `disk_type.proto`, overview §1, парити MachineType).
  Замещает прежнее «`dtp` принят». `Snapshot`=`snp`, `Volume`=`vol`, op-root storage=`sop`,
  compute=`epd` — без изменений. Авторитет правки — `sub-phase-CS-1-…-acceptance.md` §0.0.1;
  трекинг `kacho-workspace#132`. (Пример-slug `dtp-std` в сценариях ниже — иллюстративная
  admin-строка, читать как произвольный slug, не как префикс.)
- **Q2 — not-found:** `Volume <id> not found` / `Instance <id> not found` (`NOT_FOUND`, паттерн
  `"<Resource> %s not found"`). Внесено: S1-02.
- **Q3 — partial-UNIQUE name-collision:** `ALREADY_EXISTS`, **одна стабильная строка**
  `volume with name <n> already exists in project` (`23505`). Внесено: S1-06.
- **Q4 — DiskType (семантический пин): same-DB FK RESTRICT, БЕЗ sync-precheck.** `Volume.Create`
  с несуществующим `diskTypeId` → **Operation error** `FAILED_PRECONDITION` `DiskType <id> not
  found` (`23503`); `DiskType.Delete` in-use → `FAILED_PRECONDITION` `DiskType <id> is in use`.
  Это **within-service** (same-DB FK), **не** cross-service peer-validate (не путать с критикой #1
  / S1-10). Внесено: S1-08.
- **Q5 — второй boot-том (EXCLUDE `23P01`):** `FAILED_PRECONDITION` `Instance <id> already has a
  boot volume`. Внесено: S2-07.
- **Q6 — compute-side строки:** detach-boot `boot volume cannot be detached`; cpu-guarantee bounds
  `Illegal argument cpu_guarantee_percent`; sizing-STOPPED `Instance must be STOPPED to change
  sizing`; immutable `<field> is immutable after Instance.Create`. Внесено: S3-06, S5-03, S5-05.
- **Q7 — NIC (verbatim из kacho-vpc, вписаны дословно):**
  - delete-safety: `network interface <id> is still attached to <kind> <id>; detach it first`
    (`networkinterface/delete.go`, params `id, used_by_type, used_by_id`). Внесено: S4-05.
  - malformed `enp`-id: `invalid network interface id '<X>'` (`corevalidate.ResourceID`,
    `niResource="network interface"`, формат `invalid %s id '%s'`). Внесено: S4-06.

---

## Общий DoD инкремента

- Все 5 стадий merged (по графу proto → corelib → storage/compute/vpc → api-gateway → deploy →
  docs; `.claude/rules/polyrepo.md`); тикет+ветка `KAC-<N>` в каждом затронутом репо (gate #2).
- **Ацикличность (INV-1/INV-1a)** подтверждена arch-test (storage/vpc не импортируют compute-stub);
  рёбра зафиксированы в `polyrepo.md` как one-way: `compute→storage` (новое) + revived one-way
  `compute→vpc` NIC-attach + **новый сервис-consumer `storage→geo`** (zone-validate) и
  **`storage→iam`** (`ProjectService.Get` + `InternalIAMService.Check` + fgaproxy owner-tuple) —
  все односторонни (geo/iam/vpc/storage не звонят consumer'ов обратно), циклов нет.
- **Internal-only (INV-2)** подтверждён api-gateway audit: `InternalVolumeService.*` и vpc
  `InternalNetworkInterfaceService.Attach/Detach/ListByInstance` отсутствуют на external mux.
- Строгий TDD: integration (testcontainers) + newman (happy + negative) в тех же PR; concurrency
  (`-race`, детерминированно, blocker-slot не `time.Sleep`) на S2-05, S4-02, S4-04.
- Behaviour-level assert'ы на всех негативах (код **и** точный текст; leak-guard `internal error`).
- Финальная верификация: `go test ./... -race` + `golangci-lint run` + `govulncheck` +
  `make audit-list-filter` + newman зелёные.
- vault-trail обновлён (`resources/storage-volume`, `resources/compute-instance`,
  `resources/vpc-networkinterface`; `rpc/storage-volume-service`, `rpc/storage-internal-volume-service`,
  `rpc/compute-instance-service`, `rpc/vpc-internal-networkinterface-service`;
  `edges/compute-to-storage-attach`, `edges/compute-to-vpc-nic-validate`,
  **`edges/storage-to-geo-zone-validate`**, **`edges/storage-to-iam-project-validate`**; `KAC/KAC-<N>`).
- Заказчик — только финальный smoke/e2e (`make e2e-test` / `grpcurl`), не участвует в APPROVE контракта.

---

## Rejected alternatives (осознанно отклонено — детали в спеке §7, не дублируются)

`attached_disks` на стороне compute (теряется FK, TOCTOU) · storage спрашивает compute «жив ли
инстанс» (цикл) · отдельная CAS-колонка `IN_USE` (дрейф; status derived) · `used_by` отдельной
таблицей within-service (избыточно) · hard cross-service delete-block (цикл; within-service — HARD
FK RESTRICT, cross-service — SOFT) · `Volume.Relocate` в этот scope · `:resizeDisk` на `Instance`
(двойное владение размером) · глобальный `UNIQUE(used_by_id)` на NIC (ломает multi-NIC; урок vpc
0016/0017) · NIC-attach на стороне compute (теряется vpc-CAS/delete-gate).

---

## Вердикт acceptance-reviewer

**✅ APPROVED** (acceptance-reviewer, 2026-07-12) — раунд 2, после точечных правок.

**Немедленный green-light:** **S4-vpc** — `kacho-vpc InternalNetworkInterfaceService`
(миграция `used_by_index` + partial `UNIQUE(used_by_id, used_by_index) WHERE used_by_id<>''`;
sync `Attach`/`Detach`/`ListByInstance` CAS с zone-coherence+anycast; per-RPC authz-Check на :9091).
Можно кодить строгим TDD (RED → GREEN) через `rpc-implementer` + `migration-writer` + `integration-tester`.

**Документ как контракт** (S1–S5) — APPROVED; каждая стадия управляется своим DoD, gate #2
(тикет+ветка `KAC-<N>` в каждом затронутом репо) применяется до кода каждой стадии.

**Покрытие S4 (NIC-attach):** [A10] S4-01/02 · [A11] S4-04/05 · [A13] S4-03 + добор
S4-06 (idempotent detach + alt-arm `index` + oneof-`exactly_one` + malformed + object-scoped authz)
и S4-07 (Unavailable fail-closed). Positive/negative/edge/concurrency(`-race`)/idempotency/authz — все классы.

**Оба замечания раунда 1 закрыты:**
1. **[SCOPE/REALISM]** placement-схема subnet для anycast-плеча S4-03 — источник установлен
   (pre-existing применённая миграция `0012_subnet_placement`; S4 новых subnet-полей не вводит,
   CAS только читает). Магическая предпосылка устранена.
2. **[SECURITY]** per-RPC authz-Check на vpc :9091 — зафиксирован INV-2a + DoD S4 (симметрично S2,
   behaviour-level `PERMISSION_DENIED` deny-assert в integration). Соответствует `security.md`
   «AuthN+AuthZ ВЕЗДЕ».

**Note (non-blocking, к TDD-RED):** verbatim-строки S4-05/S4-06 (`network interface <id> is still
attached to <kind> <id>; detach it first`, `invalid network interface id '<X>'`) сверить дословно
с реальным кодом kacho-vpc (`networkinterface/delete.go`, `corevalidate.ResourceID`) первым RED-тестом
(репо локально не склонировано — из vault подтверждён факт delete→FailedPrecondition, но не дословный текст).
Записка `resources/vpc-subnet` устарела (pre-geo, без placement-полей) — обновить в vault-trail.

**Следующий шаг:** `superpowers:writing-plans` → per-stage plan (S4-vpc), затем TDD-имплементация.
