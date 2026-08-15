# Spec — `Volume` (block disk) + `Instance` disk-attach

> Статус: **draft (pre-GA)**, часть эпика «compute→storage decomposition».
> Скоуп этого документа — ресурс `Volume` (диск) и **срез `Instance`, отвечающий за
> подключение ресурсов**: attach/detach диска (§3), attach/detach **сетевого интерфейса**
> (§3a, несколько NIC на инстанс, владелец kacho-vpc), **ресайз диска** (§3b, storage-side),
> и `cpu_guarantee_percent` (гарантия CPU в %). Container / Bucket / OCI-delivery целиком /
> миграция — в родительском концепте, не здесь.
>
> Владельцы: `Volume` → **kacho-storage** (`kacho.cloud.storage.v1`);
> `Instance` → **kacho-compute** (`kacho.cloud.compute.v1`).
> Оба — control-plane only (data-plane не моделируется).

---

## 0. Ключевая идея (attach через границу сервиса, без cross-service FK)

`Volume` и `Instance` живут в **разных БД** (DB-per-service, ban #8) — прямой FK
между ними невозможен (ban #4). Тем не менее инвариант «нельзя удалить
примонтированный диск» и «диск примонтирован ≤1 инстансу» остаются **настоящими
DB-constraint'ами**, потому что **join-таблица `volume_attachments` живёт в БД
storage, рядом с `volumes`**. Attach — **компьют-инициируемый и self-describing**:
запрос несёт `instance_id / instance_name / instance_zone_id / project_id`, а storage
валидирует по **своей** строке `volumes` и делает атомарный CAS. **storage никогда
не зовёт compute** (иначе цикл compute↔storage, ретроспектива KAC-266).

```
        AttachDisk (async Operation)
compute ────────────────────────────▶ storage.InternalVolumeService.Attach
  │  (self-describing payload)           │  atomic CAS on volumes/volume_attachments
  │                                      ▼
  │                              volume_attachments (STORAGE DB)  ── FK RESTRICT ─▶ volumes
  ▼
Instance.boot_volume / secondary_volumes  ← read-only mirror (batched read, graceful-degrade)
        source of truth = Volume.attachments
```

---

## 1. `Volume` — ресурс диска (kacho-storage, `storage.v1`)

Блочный том. Zone-level. Standalone lifecycle: может жить в `AVAILABLE` вечно с
нулём подключений. ОС на нём **не хранится** (доставка ОС — OCI-образ на boot'е
инстанса); `Volume` — чистое персистентное блочное состояние.

### 1.1 Flat proto message

```protobuf
package kacho.cloud.storage.v1;

message Volume {
  string id = 1;                                     // prefix "vol"; immutable
  string project_id = 2;                             // owner; immutable; peer → kacho-iam
  google.protobuf.Timestamp created_at = 3;          // Truncate(time.Second)
  google.protobuf.Timestamp updated_at = 4;          // Truncate(time.Second)
  string name = 5;                                    // 1..63, lowercase; partial UNIQUE (project_id,name) WHERE name<>''
  string description = 6;                             // ≤256
  map<string, string> labels = 7;                     // ≤64 пар

  string zone_id = 8;                                 // TEXT → kacho-geo (peer-validated, no FK); immutable
  string disk_type_id = 9;                            // TEXT → DiskType (SAME-DB FK RESTRICT); immutable
  int64  size_bytes = 10;                             // >0; Update — только увеличение
  int64  block_size = 11;                             // default 4096; immutable
  string source_snapshot_id = 12;                     // optional; SAME-DB FK → snapshots ON DELETE SET NULL; immutable
                                                      //   пусто = свежий том. ИСТОЧНИКА-ОБРАЗА НЕТ (ОС из OCI).

  Status status = 13;                                 // enum (см. 1.4). IN_USE/AVAILABLE — DERIVED (см. 1.3)
  repeated VolumeAttachment attachments = 14;         // AUTHORITATIVE attach-state (public, lean)
  repeated kacho.cloud.reference.Reference used_by = 15;  // generic derived projection of attachments (см. 1.5)

  enum Status {
    STATUS_UNSPECIFIED = 0;
    CREATING = 1;
    AVAILABLE = 2;   // ready, не подключён
    IN_USE = 3;      // ready, подключён к инстансу (derived)
    DELETING = 4;
    ERROR = 5;
  }
}

message VolumeAttachment {              // sub-record; source of truth для одной привязки
  string instance_id = 1;              // TEXT, БЕЗ cross-service FK (compute owns Instance)
  string instance_name = 2;            // write-time snapshot (заполняется на Attach; storage НЕ читает из compute)
  string device_name = 3;              // уникален в пределах инстанса
  bool   is_boot = 4;                  // персистентный root-overlay (обычно false для data-диска)
  Mode   mode = 5;                     // READ_WRITE | READ_ONLY
  bool   auto_delete = 6;              // удалить том при удалении инстанса
  google.protobuf.Timestamp attached_at = 7;   // Truncate(time.Second) — усечение и на под-записи

  enum Mode { MODE_UNSPECIFIED = 0; READ_WRITE = 1; READ_ONLY = 2; }
}
```

**Internal-only проекция** (`InternalVolumeService`, :9091 — не на external):
backend-LUN / NVMe-namespace / storage-node / pool-id, числовой инфра-id, ёмкость.
Никогда на публичном `Volume` (ban #6 + инфра-sensitive).

### 1.2 DB-схема (kacho-storage)

```sql
CREATE TABLE volumes (
  id                 text        PRIMARY KEY,
  project_id         text        NOT NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  name               text        NOT NULL DEFAULT '',
  description        text        NOT NULL DEFAULT '',
  labels             jsonb       NOT NULL DEFAULT '{}',
  zone_id            text        NOT NULL,
  disk_type_id       text        NOT NULL REFERENCES disk_types(id) ON DELETE RESTRICT,   -- M3: same-DB FK
  size_bytes         bigint      NOT NULL CHECK (size_bytes > 0),
  block_size         bigint      NOT NULL DEFAULT 4096,
  source_snapshot_id text                 REFERENCES snapshots(id)  ON DELETE SET NULL,   -- M3
  state              text        NOT NULL DEFAULT 'CREATING'                              -- {CREATING,READY,DELETING,ERROR}
                     CHECK (state IN ('CREATING','READY','DELETING','ERROR'))
);
CREATE UNIQUE INDEX volumes_name_uniq          ON volumes (project_id, name) WHERE name <> '';
CREATE INDEX        volumes_disk_type_idx      ON volumes (disk_type_id);        -- DiskType.used_by derive
CREATE INDEX        volumes_source_snapshot_idx ON volumes (source_snapshot_id); -- Snapshot.used_by derive

CREATE TABLE volume_attachments (            -- STORAGE DB (co-located с volumes → FK снова настоящий)
  volume_id     text        PRIMARY KEY REFERENCES volumes(id) ON DELETE RESTRICT,  -- ①
  instance_id   text        NOT NULL,        -- cross-service, БЕЗ FK
  instance_name text        NOT NULL DEFAULT '',
  project_id    text        NOT NULL,
  zone_id       text        NOT NULL,
  device_name   text        NOT NULL,
  is_boot       boolean     NOT NULL DEFAULT false,
  mode          text        NOT NULL DEFAULT 'READ_WRITE',
  auto_delete   boolean     NOT NULL DEFAULT false,
  attached_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (instance_id, device_name),                          -- ② уникальное имя устройства в инстансе
  EXCLUDE (instance_id WITH =) WHERE (is_boot)                -- ③ ≤1 boot-том на инстанс
);
CREATE INDEX volume_attachments_instance_idx ON volume_attachments (instance_id);  -- batched ListAttachments
```

- **①** `volume_id` PK + FK `RESTRICT` → **один attachment на том глобально** *и*
  `Volume.Delete` блокируется, пока том примонтирован — оба инварианта **DB-enforced,
  в БД storage** (не software refcount, не TOCTOU — ban #10).
- **②③** — instance-scoped уникальности (device_name, единственный boot); storage
  их энфорсит, т.к. `instance_id` — локальная колонка.

### 1.3 `status` = DERIVED (фикс B3: не два представления одного факта)

Хранится **`state ∈ {CREATING, READY, DELETING, ERROR}`**. Прото-`Status` **вычисляется**,
чтобы `status` и наличие attachment не могли разойтись:

| `state` | attachment есть? | wire `Status` |
|---|---|---|
| CREATING | — | `CREATING` |
| DELETING | — | `DELETING` |
| ERROR | — | `ERROR` |
| READY | нет | `AVAILABLE` |
| READY | да | `IN_USE` |

Нет отдельной CAS-колонки `IN_USE`; `Attach`/`Detach` меняют только строки
`volume_attachments`, а `status` следует из их наличия. Дрейф невозможен.

### 1.4 Жизненный цикл

`Create` → `state=READY` **сразу** (control-plane, реального провижининга нет; том
представляется готовым моментально). Attach → derived `IN_USE`. Detach → derived
`AVAILABLE`. `Delete` → `state=DELETING` → строка удаляется (если не attached).

### 1.5 `used_by` (обобщение существующего `reference.Reference`, режим within-service)

`Volume.used_by` — **output-only** generic-проекция `attachments` (тот же источник —
таблица `volume_attachments`, отдельного хранения нет). Форма — `repeated
kacho.cloud.reference.Reference` (переиспользуем существующий тип, не изобретаем
`UsedByRef`): `referrer = {type:"compute.instance", id: instance_id, name: instance_name}`,
`type = USED_BY`, `owned = auto_delete`. `device_name`/`mode`/`is_boot` живут только
на `attachments[]` (rich domain); `used_by` — для единообразного dependents/impact-tooling.
Delete-safety — **HARD** через FK `volume_attachments.volume_id → volumes RESTRICT`
(режим within-service). `used_by` в `Create`/`Update` не принимается; mask с `used_by`
→ `InvalidArgument "used_by is immutable after Volume.Create"`.

> Ретайрится legacy `Disk.instance_ids repeated string` → типизированный
> `Volume.used_by repeated reference.Reference` (self-describing kind/name/owned).

### 1.6 RPC-поверхность

**`VolumeService`** (public :9090; REST `/storage/v1/volumes`):

| RPC | sync/async | Заметки |
|---|---|---|
| `Get` | sync | `GET /storage/v1/volumes/{volume_id}`; malformed id → `InvalidArgument "invalid volume id '<X>'"` |
| `List` | sync | `GET /storage/v1/volumes?projectId=`; **listauthz-filtered**; cursor `(created_at,id)`; filter `name=` |
| `Create` | async → `Operation` | metadata `CreateVolumeMetadata{volume_id}`, response `Volume`. `state→READY` сразу. `source_snapshot_id` → restore из снапшота (existence-check в своей БД). op-id prefix `sop` |
| `Update` | async → `Operation` | mutable: `name`/`description`/`labels`/`size_bytes`(только рост). immutable: `zone_id`/`disk_type_id`/`block_size`/`source_snapshot_id`. immutable-switch **до** `UpdateMask` |
| `Delete` | async → `Operation` | response `Empty`. Attached → `FailedPrecondition "Volume <id> is in use"` (FK RESTRICT `23503`) |
| `ListOperations` | sync | `GET /storage/v1/volumes/{volume_id}/operations` |

**`InternalVolumeService`** (Internal :9091 **только**, mTLS; НЕ на external) —
координация attach + internal-проекция:

| RPC | sync/async | Заметки |
|---|---|---|
| `Attach` | **sync** (CAS мгновенный) | вызывается воркером compute внутри его Operation (см. §3). self-describing payload |
| `Detach` | **sync** | идемпотентный |
| `ListAttachments` | **sync**, **batched** | `ListAttachments(instance_ids[])` → attachments по инстансам (для зеркала `Instance.Get/List`, M4) |
| `GetInternal` | sync | full-проекция с инфра-полями (internal-only) |

> `Attach`/`Detach` — internal-RPC-детали координации (как compute→vpc IPAM):
> tenant-facing мутация остаётся async через **compute**-Operation (`AttachDisk`),
> поэтому ban #9 не нарушен. Задокументировано как sanctioned internal-coordination.

### 1.7 Error-тексты (часть контракта; нативный Kachō-нейминг, clean boundary)

```
"invalid volume id '<X>'"                          (malformed id, sync InvalidArgument)
"Volume <id> is in use"                            (delete/relocate attached — FailedPrecondition)
"Volume size can only be increased"                (Update size shrink — InvalidArgument)
"<field> is immutable after Volume.Create"         (immutable в mask — InvalidArgument)
"Volume is not available for attachment"           (state != READY на Attach — FailedPrecondition)
"Volume and Instance must be in the same zone"     (zone mismatch — FailedPrecondition)
"device <name> is already in use on Instance <id>" (UNIQUE(instance_id,device_name) — FailedPrecondition)
```

INTERNAL никогда не эхает pgx/SQL — дефолт-ветка mapper → фикс. `"internal error"`.

---

## 2. `Instance` — срез attach (kacho-compute, `compute.v1`)

Показан **только** attach-релевантный контур. ОС инстанса грузится из **OCI-образа**
(`image`/`image_digest`); rootfs эфемерный (data-plane, не моделируется).
Персистентное состояние = **подключённые `Volume`**.

### 2.1 Flat proto message (attach + delivery поля)

```protobuf
package kacho.cloud.compute.v1;

message Instance {
  string id = 1;                                     // prefix "ins"
  string project_id = 2;                             // immutable
  google.protobuf.Timestamp created_at = 3;          // Truncate(sec)
  google.protobuf.Timestamp updated_at = 4;          // Truncate(sec)
  string name = 5;
  string description = 6;
  map<string,string> labels = 7;
  string zone_id = 8;                                 // TEXT → kacho-geo; immutable

  string image = 9;                                   // INPUT: OCI-ref в kacho-registry (доставка ОС)
  string image_digest = 10;                           // OUTPUT: immutable digest-pin (не принимается на input)

  int32  vcpus = 11;                                   // кол-во vCPU
  int64  memory_bytes = 12;
  int32  cpu_guarantee_percent = 13;                   // гарантированный baseline на каждый vCPU:
                                                       //   0 = best-effort/burstable (без гарантии);
                                                       //   1..100 = гарантированный %; CHECK 0..100; per-platform-набор.
                                                       //   sizing → менять только при STOPPED

  // read-only attach-ЗЕРКАЛА (M4): source of truth = storage Volume.attachments / vpc NetworkInterface;
  // пересчитываются на чтении batched-запросами; graceful-degrade при недоступности owner-сервиса
  AttachedVolume          boot_volume = 20;           // optional персистентный root-overlay (обычно отсутствует)
  repeated AttachedVolume secondary_volumes = 21;
  repeated AttachedNetworkInterface network_interfaces = 22;   // 0..N NIC; source of truth = kacho-vpc

  Status status = 30;

  enum Status {
    STATUS_UNSPECIFIED = 0;
    PROVISIONING = 1; RUNNING = 2; STOPPING = 3; STOPPED = 4;
    STARTING = 5; DELETING = 6; ERROR = 7;
  }
}

message AttachedVolume {              // output-only зеркало (НЕ input, mask игнорирует)
  string volume_id = 1;
  string device_name = 2;
  bool   is_boot = 3;
  Mode   mode = 4;                     // READ_WRITE | READ_ONLY
  bool   auto_delete = 5;
  google.protobuf.Timestamp attached_at = 6;   // Truncate(sec)
  enum Mode { MODE_UNSPECIFIED = 0; READ_WRITE = 1; READ_ONLY = 2; }
}

message AttachedNetworkInterface {    // output-only зеркало NIC; source of truth = kacho-vpc NetworkInterface
  int32  index = 1;                    // слот в инстансе (eth0=0, eth1=1, …); уникален в пределах инстанса
  string nic_id = 2;                   // → kacho-vpc NetworkInterface (prefix "enp"); TEXT, БЕЗ cross-service FK
  // denorm-зеркала vpc-полей (output-only, «source of truth = vpc NetworkInterface»):
  string subnet_id = 3;
  string primary_v4_address = 4;
  string primary_v6_address = 5;
  repeated string security_group_ids = 6;
  string mac_address = 7;
}
```

Компьют **не хранит** локальные attach-таблицы (ни дисков, ни NIC) — зеркала берутся у owner'ов
(`storage.InternalVolumeService.ListAttachments` / `vpc.InternalNetworkInterfaceService.ListByInstance`).
Поэтому нечего «осиротить» на стороне compute.

### 2.2 Attach-RPC (на `InstanceService`)

| RPC | sync/async | REST | Заметки |
|---|---|---|---|
| `AttachDisk` | async → `Operation` | `POST /compute/v1/instances/{instance_id}:attachDisk` | body `AttachedDiskSpec{volume_id, device_name?, mode?, is_boot?, auto_delete?}`. precondition `status ∈ {RUNNING, STOPPED}`. metadata `AttachInstanceDiskMetadata{instance_id, volume_id}`, response `Instance`. **object-scoped authz** на `instance_id` **и** `volume_id` (scope_extractor, M5). op-id prefix `epd` (compute op-root) |
| `DetachDisk` | async → `Operation` | `POST /compute/v1/instances/{instance_id}:detachDisk` | body `oneof {volume_id, device_name}` (`exactly_one`). precondition `status ∈ {RUNNING, STOPPED}`; не boot. metadata `DetachInstanceDiskMetadata`, response `Instance` |
| `AttachNetworkInterface` | async → `Operation` | `POST /compute/v1/instances/{instance_id}:attachNetworkInterface` | body `AttachedNicSpec{nic_id, index?}`. precondition `status ∈ {RUNNING, STOPPED}`. **несколько NIC** на инстанс. metadata `AttachInstanceNicMetadata{instance_id, nic_id}`, response `Instance`. object-scoped authz на `instance_id` **и** `nic_id`. op-id prefix `epd` |
| `DetachNetworkInterface` | async → `Operation` | `POST /compute/v1/instances/{instance_id}:detachNetworkInterface` | body `oneof {nic_id, index}` (`exactly_one`). precondition `status ∈ {RUNNING, STOPPED}`. metadata `DetachInstanceNicMetadata`, response `Instance` |

`AttachDisk` body:
```protobuf
message AttachedDiskSpec {
  string volume_id = 1;                // существующий Volume (pre-created)
  string device_name = 2;             // optional; авто-назначение если пусто
  AttachedVolume.Mode mode = 3;       // default READ_WRITE
  bool   is_boot = 4;                 // default false (data-диск)
  bool   auto_delete = 5;             // default false
}
```

`AttachNetworkInterface` body:
```protobuf
message AttachedNicSpec {
  string nic_id = 1;                   // существующий kacho-vpc NetworkInterface (prefix "enp")
  int32  index = 2;                    // optional слот; авто-назначение (первый свободный) если не задан
}
```

> `Instance.Create` может принять `attach_volume_ids[]` / inline data-volume specs / `attach_nic_ids[]` —
> те же attach-механики внутри саги создания (out of scope этого документа; здесь — явные
> `AttachDisk`/`AttachNetworkInterface` на существующих инстансе, томе и NIC).
>
> **NIC-attach оживляет отложенную в KAC-266 «явную привязку NIC↔Instance»** (авто-NIC на Create
> был снят там же). NIC остаётся first-class CRUD-ресурсом kacho-vpc — Instance его только
> ссылает и зеркалит, не владеет.

---

## 3. Механика attach (crux) — пошагово

### 3.1 `AttachDisk` — сага (async compute-Operation, координирует storage)

**Sync-фаза (handler/use-case, до LRO):**
1. `corevalidate.ResourceID(instance_id, "ins")` → malformed → `InvalidArgument "invalid instance id '<X>'"` (первый стейтмент).
2. `corevalidate.ResourceID(volume_id, "vol")` → malformed → `InvalidArgument "invalid volume id '<X>'"`.
3. **Object-scoped authz** (M5): per-RPC `Check` с `scope_extractor` на `instance_id` (compute.instance) **и** `volume_id` (storage.volume) — вызывающий обязан иметь writer-право на **оба** целевых объекта (анти-BOLA: нельзя attach'ить чужой том в свой инстанс).
4. Создать compute-Operation (`ids.NewID(op-root "epd")`), вернуть `Operation` немедленно.

**Async-фаза (worker `fn(ctx)`):**
```
1. Compute-local CAS-гейт на инстансе:
     UPDATE instances SET updated_at=now()
      WHERE id=$iid AND state IN ('RUNNING','STOPPED')
      RETURNING zone_id, project_id, name;
   0 rows → FailedPrecondition "Instance must be RUNNING or STOPPED".
   (Это же закрывает гонку attach-vs-delete: Delete первым переводит инстанс в DELETING → attach отклоняется.)

2. storage.InternalVolumeService.Attach(
        volume_id, instance_id, instance_name, instance_zone_id, project_id,
        device_name, is_boot, mode, auto_delete)
   — sync internal-RPC, per-call context.WithTimeout, mTLS, retry-on-Unavailable.
   Всё ещё Unavailable → MarkError(Unavailable)  (fail-closed для мутации).

3. (storage выполняет CAS — §3.2; возвращает обновлённый Volume / ack.)

4. MarkDone(response = Instance с пересчитанным зеркалом).
   Компьют локальной attach-строки НЕ пишет → сиротить нечего.
```

### 3.2 Storage-side atomic CAS (`InternalVolumeService.Attach`, одна TX)

```sql
-- Атомарная вставка-если-можно (CAS): том READY, та же зона/проект, свободен ИЛИ уже наш
INSERT INTO volume_attachments
      (volume_id, instance_id, instance_name, project_id, zone_id, device_name, is_boot, mode, auto_delete)
SELECT $volume_id, $instance_id, $instance_name, $project_id, $zone_id, $device_name, $is_boot, $mode, $auto_delete
  FROM volumes v
 WHERE v.id = $volume_id
   AND v.state = 'READY'
   AND v.zone_id   = $zone_id       -- zone-coherence (из self-describing payload; НЕ звоним в compute)
   AND v.project_id = $project_id   -- project-coherence
ON CONFLICT (volume_id) DO NOTHING
RETURNING volume_id;
```

Разбор 0-row исхода (в той же TX, disambiguation-SELECT) → корректный sentinel:

| Что видно | Итог |
|---|---|
| вставка прошла (1 row) | **OK** — attached |
| conflict-строка есть и `instance_id` = наш | **OK** — идемпотентный replay |
| conflict-строка есть, `instance_id` другой | `FailedPrecondition "Volume <id> is in use"` |
| conflict нет, но `volumes.state != READY` | `FailedPrecondition "Volume is not available for attachment"` |
| conflict нет, `state=READY`, но zone/project не совпал | `FailedPrecondition "Volume and Instance must be in the same zone"` |

Single-statement `INSERT … ON CONFLICT` защищён row-lock'ом на PK `volume_id`:
две конкурентные `Attach` на один том — одна вставляет, вторая ловит `ON CONFLICT
DO NOTHING` → 0 rows → disambiguation видит чужую строку → `FailedPrecondition`.
Никакого `Get→check→INSERT` (TOCTOU, ban #10) — только CAS.

**SQLSTATE → gRPC** (storage `mapRepoErr`):

| SQLSTATE | Constraint | gRPC |
|---|---|---|
| `23505` | `UNIQUE(instance_id, device_name)` | `FailedPrecondition "device <name> is already in use on Instance <id>"` |
| `23P01` | `EXCLUDE … WHERE is_boot` | `FailedPrecondition` (у инстанса уже есть boot-том) |
| `23503` | `volume_attachments.volume_id → volumes RESTRICT` (на `Volume.Delete`) | `FailedPrecondition "Volume <id> is in use"` |
| default | — | фикс. `INTERNAL "internal error"` (без leak'а pgx) |

### 3.3 `DetachDisk` (идемпотентно)

```sql
DELETE FROM volume_attachments
 WHERE volume_id=$volume_id AND instance_id=$instance_id
 RETURNING volume_id;                                 -- 0 rows → уже отвязан → идемпотентный OK
```
`status` тома возвращается к `AVAILABLE` автоматически (derived, §1.3). precondition
на compute: `status ∈ {RUNNING, STOPPED}`, том не boot.

### 3.4 Idempotency / partial-failure / reconciliation

- **Крэш воркера до `MarkDone`:** corelib `operations` Reconciler повторяет `fn` →
  гейт-CAS проходит (инстанс уже RUNNING/STOPPED) → `Attach` снова → `ON CONFLICT DO
  NOTHING` + «уже наш» → идемпотентный OK → `MarkDone`.
- **storage `Unavailable`:** retry внутри `fn`; всё ещё down → `MarkError(Unavailable)`.
  Полу-состояния нет: compute локально ничего не пишет, storage при неуспешном CAS
  ничего не коммитит.
- **Единственный источник истины** — `volume_attachments` в storage; зеркало на
  Instance пересчитывается на чтении → **дуал-райта нет, reconciliation-между-БД не
  нужен**. **Нет storage-side liveness-sweep** (M1) — он потребовал бы storage→compute
  (цикл). Dangling `instance_id` после исчезновения инстанса терпится; реальная
  чистка — compute-driven `DetachDisk`/delete-сага (том с `auto_delete` удаляется на
  Instance.Delete; строка инстанса удаляется **последней**, список томов — в
  `Operation.metadata` для идемпотентного replay — M2).

### 3.5 `Instance.Get`/`List` — зеркало и graceful-degrade (M4)

- `Get` → `InternalVolumeService.ListAttachments([instance_id])` → заполняет
  `boot_volume`/`secondary_volumes`. storage `Unavailable` → зеркало **опускается/
  помечается stale**, `Get` **не падает** (данные диска — best-effort; ban #4 —
  consumer грациозно переживает dangling).
- `List` → **один batched** `ListAttachments(instance_ids[])` (не N+1).

### 3.6 Delete-safety

`Volume.Delete` примонтированного тома → FK `volume_attachments.volume_id → volumes
RESTRICT` → `23503` → `FailedPrecondition "Volume <id> is in use"`. **DB-constraint в
своей БД**, не cross-service-handshake, не software-refcount.

### 3.7 Ацикличность (инвариант #1)

`compute → storage` строго односторонне: `Attach`-запрос self-describing
(несёт `instance_id/name/zone/project`), storage валидирует **свою** строку и
**никогда** не зовёт `compute.InstanceService.Get`. Guard: `internal/clients/` в
kacho-storage не импортирует compute-stub (arch-test). Ребро фиксируется в
`polyrepo.md` как one-way.

---

## 3a. Механика attach сетевого интерфейса (NIC) — симметрично диску, владелец kacho-vpc

Полностью повторяет disk-attach, но **владелец привязки — kacho-vpc** (NIC — его
first-class ресурс). Привязка `NIC↔Instance` живёт на строке NIC (не в compute):
`used_by_id` + `used_by_kind` (**уже есть**) + новый `used_by_index` (слот в инстансе).
Оживляет отложенную в KAC-266 явную привязку.

### 3a.1 vpc-side состояние + CAS (в БД vpc)

```sql
-- kacho_vpc.network_interfaces (уже существует): добавляем used_by_index новой миграцией
ALTER TABLE network_interfaces ADD COLUMN used_by_index integer;         -- новая goose-миграция (ban #5)
CREATE UNIQUE INDEX ni_used_by_index_uniq
    ON network_interfaces (used_by_id, used_by_index) WHERE used_by_id <> '';  -- уникальный слот в инстансе

-- Attach CAS (self-describing; vpc валидирует СВОИ строки ni+subnet, НЕ зовёт compute):
UPDATE network_interfaces ni
   SET used_by_id = $instance_id, used_by_kind = 'instance', used_by_index = $index
  FROM subnets s
 WHERE ni.id = $nic_id
   AND s.id = ni.subnet_id
   AND (ni.used_by_id = '' OR ni.used_by_id = $instance_id)   -- свободен ИЛИ уже наш (идемпотентно)
   AND ni.project_id = $project_id                            -- project-coherence (из payload)
   AND ( s.placement_type = 'REGIONAL'                        -- ANYCAST-ИСКЛЮЧЕНИЕ: зоны нет (DB-CHECK zone_id='')
         OR s.zone_id = $instance_zone_id )                   -- ZONAL: та же зона, что у инстанса
RETURNING ni.id;                                              -- 0 rows → disambiguation
```

**Zone-coherence + anycast-исключение (закрывает GAP из аудита compute).** Зона NIC —
**производная от subnet** (у NIC нет своего `zone_id`; `network_interface.proto` — только
`subnet_id`). Subnet несёт `placement_type`:
- **ZONAL** (`zone_id` задан, `region_id=''` — DB-CHECK `subnets_placement_payload_chk`) →
  привязка требует `subnet.zone_id == instance.zone_id`, иначе `FailedPrecondition
  "NetworkInterface subnet is in zone %s, instance zone is %s"`.
- **REGIONAL = anycast** (`region_id` задан, `zone_id=''`) → «region-scoped, без зональности»
  → **zone-check пропускается** (сравнивать не с чем). Ровно это и есть «исключение anycast-адрес».

Disambiguation 0-row: conflict-строка чужого инстанса → `"NetworkInterface is in use"`;
zone mismatch (ZONAL) → zone-текст; project mismatch → object-scoped authz ловит раньше (M5).

- **Несколько NIC на инстанс**: уникальность — на **NIC** (`used_by_id='' OR =наш`), а НЕ
  глобальный `UNIQUE(used_by_id)`. Именно это ограничение (миграция 0016) было **откачено
  (0017)** ровно ради multi-NIC. Слот-уникальность — partial `UNIQUE(used_by_id, used_by_index)`.
- **NIC→≤1 инстанс** (CAS), **инстанс→много NIC** (нет обратного unique).
- Single-statement CAS row-lock защищает конкурентные attach.
- **Инвариант целиком**: Instance + Disk + NIC — **в одной зоне**; исключение — NIC на
  **REGIONAL (anycast) subnet** (у него зоны нет). Disk-плечо уже энфорсится
  (§3.2 `v.zone_id=$zone_id`; тома всегда зональные — anycast-тома нет); NIC-плечо — этот CAS.

### 3a.2 Сага `AttachNetworkInterface` (async compute-Operation)

Идентична disk-саге (§3.1):
1. sync: malformed-id (`ins`/`enp`) → `InvalidArgument`; object-scoped authz на `instance_id` **и** `nic_id`; создать compute-Operation, вернуть.
2. worker: compute-local CAS-гейт (`state IN ('RUNNING','STOPPED')`) → `vpc.InternalNetworkInterfaceService.Attach(nic_id, instance_id, instance_name, instance_zone_id, project_id, index)` — sync internal-RPC, per-call timeout, mTLS (SEC-M), fail-closed `Unavailable`; index не задан → vpc берёт первый свободный слот атомарно.
3. vpc выполняет §3a.1 CAS.
4. `MarkDone(Instance с пересчитанным NIC-зеркалом)`. Compute локально ничего не пишет.

`DetachNetworkInterface` симметрично: `UPDATE network_interfaces SET used_by_id='', used_by_kind='', used_by_index=NULL WHERE id=$nic AND used_by_id=$instance_id RETURNING` (идемпотентно).

### 3a.3 Инварианты NIC

- **Delete-safety**: `NIC.Delete` с непустым `used_by_id` → `FailedPrecondition` (уже в vpc: «Delete → FailedPrecondition если used_by_id непустой»).
- **`Instance.Delete`**: compute-driven detach всех NIC (аналог delete-саги диска); NIC, созданные под инстанс, могут авто-удаляться (политика), но **без** cross-service cascade (ban #4).
- **Ацикличность**: `compute → vpc` one-way (то же живое ребро NIC-spec-validate + IPAM, SEC-M mTLS); vpc валидирует свою строку, **не зовёт** compute. Restore `Internal*`-attach-RPC — на :9091 (не на external, ban #6).
- **Зеркало** `Instance.network_interfaces[]` — read-only, source of truth = vpc; batched `ListByInstance`; graceful-degrade при vpc `Unavailable` (Get не падает, M4).

---

## 3b. Ресайз диска — на стороне storage (владелец Volume), НЕ на инстансе

**Решение: resize = `Volume.Update{size_bytes}` (increase-only), owner = kacho-storage.**
Размер — свойство `Volume`; инстанс им **не владеет**. Resize-RPC на `Instance` = двойное
владение одним свойством → нарушает «один владелец на ресурс/свойство» + добавил бы лишний
прокси `compute→storage`. Поэтому инстанс-сайд resize **не делаем**.

- **DB-CAS (increase-only, ban #10)**: `UPDATE volumes SET size_bytes=$new, updated_at=now()
  WHERE id=$id AND size_bytes < $new RETURNING;` 0 rows → `InvalidArgument "Volume size can
  only be increased"`. Не software-compare.
- **Работает и на `IN_USE`**: CAS не смотрит на attachment — online-grow примонтированного тома
  разрешён. `state` тома не важен для размера (важен для delete/attach, не для роста).
- **Инстанс видит новый размер** через своё read-only зеркало (`AttachedVolume` не несёт size;
  size читается с `Volume.Get`) — на следующем чтении, без операции на стороне compute.
- **Гостевая ОС / расширение ФС** (partition/filesystem grow внутри гостя) — **data-plane**,
  вне control-plane (в реальном стеке online-grow триггерит rescan гипервизора; здесь не
  моделируется).
- **Уменьшение** запрещено (`InvalidArgument`), как и в текущем контракте.

> Итог: диск ресайзится **со стороны диска** (`PATCH /storage/v1/volumes/{id}` с `size_bytes`),
> прозрачно для примонтированного инстанса. Никакого `:resizeDisk` на `Instance`.

---

## 4. Cross-domain edges (attach)

**4.1 `kacho-compute → kacho-storage` (disk attach)**

| Аспект | Значение |
|---|---|
| Направление | one-way compute→storage (storage не зовёт compute) |
| RPC | `InternalVolumeService.Attach/Detach/ListAttachments` (:9091, mTLS) |
| Sync/async | internal-RPC **sync** (CAS мгновенный); tenant-мутация **async** через compute-`AttachDisk`-Operation |
| Timeout | per-call `context.WithTimeout` (configured), не сырой request-ctx |
| Fail-closed | storage `Unavailable` → мутация `Unavailable` (не проходит на unknown состоянии) |
| AuthZ | object-scoped `Check` на обоих концах; storage-RPC несёт writer-tier + `scope_extractor` на `volume_id` (не `<exempt>`) |

**4.2 `kacho-compute → kacho-vpc` (NIC attach)** — то же **живое** ребро (NIC-spec validate + IPAM, SEC-M mTLS), к которому возвращается attach:

| Аспект | Значение |
|---|---|
| Направление | one-way compute→vpc (vpc не зовёт compute — не воссоздаём выпиленный в KAC-266 обратный путь) |
| RPC | `InternalNetworkInterfaceService.Attach/Detach/ListByInstance` (:9091, mTLS SEC-M) |
| Sync/async | internal-RPC **sync** (CAS на `used_by_id`); tenant-мутация **async** через compute-`AttachNetworkInterface`-Operation |
| Fail-closed | vpc `Unavailable` → мутация `Unavailable` |
| AuthZ | object-scoped `Check`; writer-tier + `scope_extractor` на `nic_id` |

**4.3 `kacho-storage → kacho-geo` / `kacho-storage → kacho-iam` (owner-валидация нового сервиса)** — обязательны для любого сервиса (`data-integrity` cross-domain rule 2 + `polyrepo.md` `*→iam`):

| Ребро | Назначение | Sync/async | Fail-closed |
|---|---|---|---|
| **storage → geo** | `Volume.Create`/restore: валидация `zone_id` (`geo.v1.ZoneService.Get`); несуществующая зона → `InvalidArgument "unknown zone id '<X>'"` (зеркалит vpc/compute→geo) | sync (request-path) | geo `Unavailable` → мутация `Unavailable` |
| **storage → iam** | `Volume.Create`: existence/owner `project_id` (`ProjectService.Get`) + per-RPC `InternalIAMService.Check` (оба листенера) + fgaproxy `RegisterResource`/`UnregisterResource` (owner-tuple `storage_volume/…`, transactional-outbox) | sync / outbox | iam `Unavailable` → мутация `Unavailable` |

> `zone_id`/`project_id` — cross-service TEXT-refs без FK; проверяются **на request-path Create** (fail-closed), не только на attach. Оба ребра — one-way (geo/iam — листья, storage их не звонит обратно) → **регистрируются в `polyrepo.md` + vault `edges/`**.

---

## 5. Конвенц-конформанс (чек-лист)

- **Flat message**, enum `Status`, без k8s-envelope. ✔
- **Reads sync / mutations async** через `Operation`; polling `OperationService.Get`; без Watch. ✔
- **Within-service инварианты — на DB** (FK RESTRICT, UNIQUE, EXCLUDE, CAS); attach — CAS, не TOCTOU. ✔
- **Cross-service — по id + peer-validate**, без FK; fail-closed `Unavailable`. ✔
- **Timestamp `Truncate(time.Second)`** на `Volume`, `Instance` **и** под-записях `VolumeAttachment`/`AttachedVolume`. ✔
- **NIC-attach — владелец kacho-vpc** (привязка на `used_by_id/kind/index`); несколько NIC на инстанс (NIC→≤1 инстанс); `compute→vpc` one-way, self-describing, ацикличность сохранена. ✔
- **`cpu_guarantee_percent`** ∈ [0..100] (CHECK), 0=burstable; sizing (vcpus/memory/guarantee) меняется только при `STOPPED`. ✔
- **Resize диска — только storage-side** (`Volume.Update{size_bytes}` increase-only via DB-CAS); нет resize-RPC на `Instance` (один владелец свойства). ✔
- **malformed-id — первым стейтментом** (`vol`/`ins`); well-formed-но-нет → `NotFound`. ✔
- **update_mask**: immutable-switch **до** `UpdateMask`; `used_by`/зеркало — output-only, mask их отвергает/игнорирует. ✔
- **Cursor pagination** `(created_at,id)`; `List` — listauthz-filtered. ✔
- **ID** = `ids.NewID(prefix)`; storage op-root `sop`, compute op-root `epd` (opsproxy routes by first 3 chars). ✔
- **authN(mTLS)+authZ(Check)** на обоих листенерах; object-scoped scope_extractor. ✔

---

## 6. Acceptance (Given-When-Then) — гейт под TDD

**A1 — attach happy-path**
- *Given* инстанс `ins-…` в `RUNNING` в зоне `Z` и том `vol-…` в `AVAILABLE` в зоне `Z`, project `P`
- *When* `POST /compute/v1/instances/{ins}:attachDisk {volume_id, device_name:"sdb"}`
- *Then* Operation `done=true`; `Volume.Get.status == IN_USE`; `Volume.attachments[0].instance_id == ins`; `Instance.Get.secondary_volumes` содержит `{volume_id, device_name:"sdb"}`; `Volume.used_by` = 1 ref `{compute.instance, ins}`.

**A2 — double-attach проигрывает чисто (race, CAS)**
- *Given* том `vol` в `AVAILABLE`
- *When* две конкурентные `AttachDisk` на `vol` (разные инстансы)
- *Then* ровно одна `done`; вторая → `FailedPrecondition "Volume <id> is in use"`. (integration `-race`, blocker держит слот, не `time.Sleep`.)

**A3 — delete примонтированного тома блокируется**
- *Given* `vol` привязан к `ins`
- *When* `DELETE /storage/v1/volumes/{vol}`
- *Then* Operation `error`; код `FailedPrecondition`, **сообщение** `"Volume <id> is in use"` (behaviour-level assert, не только код). После `DetachDisk` — delete проходит.

**A4 — zone mismatch**
- *Given* инстанс в зоне `Z1`, том в зоне `Z2`
- *When* `AttachDisk`
- *Then* `FailedPrecondition "Volume and Instance must be in the same zone"`.

**A5 — attach на не-подходящем статусе инстанса**
- *Given* инстанс в `PROVISIONING`
- *When* `AttachDisk`
- *Then* `FailedPrecondition "Instance must be RUNNING or STOPPED"`.

**A6 — идемпотентный detach**
- *Given* том уже отвязан от `ins`
- *When* повтор `DetachDisk`
- *Then* Operation `done` (no-op), без ошибки.

**A7 — storage down на чтении не роняет `Instance.Get`** (M4)
- *Given* storage `Unavailable`
- *When* `Instance.Get`
- *Then* инстанс возвращается; disk-зеркало опущено/помечено stale; **Get не падает**.

**A8 — size Update только рост; immutable-поля**
- *When* `Update` тома с `size_bytes` меньше текущего → `InvalidArgument "Volume size can only be increased"`; mask с `zone_id`/`disk_type_id`/`block_size` → `InvalidArgument "<field> is immutable after Volume.Create"`.

**A9 — object-scoped authz (анти-BOLA)** (M5)
- *Given* вызывающий имеет право на `ins`, но НЕ на `vol` (чужой проект)
- *When* `AttachDisk`
- *Then* `PermissionDenied` (Check против целевого `vol`, не только метода).

**A10 — несколько NIC на инстанс**
- *Given* инстанс `ins` в `STOPPED`, два NIC `enp-1`, `enp-2` (DETACHED, тот же project/zone)
- *When* `AttachNetworkInterface{nic_id:enp-1}` затем `{nic_id:enp-2}`
- *Then* оба Operation `done`; `Instance.network_interfaces` = 2 (index 0 и 1); vpc `NetworkInterface.Get(enp-1).used_by_id == ins`. (Подтверждает multi-NIC — нет глобального `UNIQUE(used_by_id)`.)

**A11 — NIC занят другим инстансом / delete примонтированного NIC**
- *When* `AttachNetworkInterface(enp-1)` на второй инстанс, пока `enp-1.used_by_id != ''` → `FailedPrecondition "NetworkInterface is in use"`; `vpc.NetworkInterface.Delete(enp-1)` при непустом `used_by_id` → `FailedPrecondition`.

**A12 — resize диска со стороны storage, прозрачно для инстанса**
- *Given* `vol` в `IN_USE` (примонтирован к `ins`), `size_bytes = S`
- *When* `PATCH /storage/v1/volumes/{vol} {size_bytes: S+Δ}`
- *Then* Operation `done`; `Volume.Get.size_bytes == S+Δ` (том остаётся `IN_USE`); никакого RPC на `Instance` не требуется. `size_bytes < S` → `InvalidArgument "Volume size can only be increased"`.

**A13 — NIC zone-coherence + anycast-исключение**
- *Given* инстанс `ins` в зоне `Z1`; NIC `enp-z2` в **ZONAL**-subnet зоны `Z2`; NIC `enp-any` в **REGIONAL**-subnet
- *When* `AttachNetworkInterface(enp-z2)` → `FailedPrecondition` (subnet зоны `Z2` ≠ зона инстанса `Z1`)
- *And When* `AttachNetworkInterface(enp-any)` (REGIONAL/anycast) → `done` (zone-check пропущен — у REGIONAL subnet зоны нет)
- *And* NIC в ZONAL-subnet зоны `Z1` → `done`. (Инвариант: instance+disk+nic одна зона, кроме anycast.)

Каждый сценарий → integration (testcontainers, storage-/vpc-side CAS/FK/EXCLUDE + `-race`
для A2/A10) **и** newman (black-box через api-gateway, ≥1 happy + negatives), в том же PR.
Internal `Attach/Detach` (storage и vpc) — через integration/bufconn (не на external mux;
отсутствие на external — само по себе assert в api-gateway-audit).

---

## 7. Rejected alternatives (осознанно отклонено)

- **Держать `attached_disks` на стороне compute** → потерять FK `disk_id→volumes`
  (cross-DB невозможен) → «in-use»-гарантия скатывается в software check-then-act
  (TOCTOU, ban #10). Отклонено: join-таблица переезжает в storage.
- **storage спрашивает compute «жив ли инстанс»** (liveness-sweep / attach-validate
  через `InstanceService.Get`) → ребро storage→compute → цикл (KAC-266). Отклонено:
  attach self-describing, чистка compute-driven.
- **Отдельная CAS-колонка `IN_USE`** параллельно `attachments[]` → два представления
  одного факта, дрейф. Отклонено: `status` derived из наличия attachment.
- **Хранить `used_by` отдельной таблицей для within-service** → избыточность (forward-FK
  и есть индекс). Отклонено: derive-on-read.
- **Хардовый cross-service delete-block** «нельзя удалить, пока used_by непусто» для
  консюмеров из другого сервиса → требует owner→consumer confirm = цикл. Для
  within-service (Volume↔attachment) — да, HARD (FK RESTRICT); cross-service — SOFT.
- **`Relocate` тома** в этот скоуп не входит (противоречит immutable `zone_id` и без
  data-plane ничего не «перемещает») — решается отдельно в родительском концепте.
- **Resize диска со стороны `Instance`** (`:resizeDisk` на инстансе) → двойное владение
  размером тома (свойство `Volume`, owner storage) + лишний прокси `compute→storage`.
  Отклонено: resize = `Volume.Update{size_bytes}` (§3b), прозрачно для примонтированного инстанса.
- **Глобальный `UNIQUE(used_by_id)` на NIC** → ложно запрещает несколько NIC на инстанс
  (реальный урок: миграция vpc 0016 добавила, 0017 откатила). Отклонено: уникальность на
  **NIC** (CAS `used_by_id='' OR =наш`) + `UNIQUE(used_by_id, used_by_index)` для слота.
- **NIC-attach на стороне compute (локальная таблица привязки)** → потерять vpc-side CAS/
  delete-gate на `used_by_id`; дублировать состояние. Отклонено: привязка живёт на NIC (vpc),
  compute — зеркало (симметрично disk↔storage).
```
