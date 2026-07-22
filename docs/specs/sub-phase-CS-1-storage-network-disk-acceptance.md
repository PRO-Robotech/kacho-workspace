# Sub-phase CS-1 (Storage network-disk foundation — Volume / VolumeAttachment / Snapshot / DiskType) — Acceptance

> Статус: ✅ APPROVED (acceptance-reviewer, round 2 — все CHANGES REQUESTED раунда 1 адресованы; gate ban #1 ОТКРЫТ). Эпик: kacho-workspace#132.
> Дата: 2026-07-15
> Ревьюер: acceptance-reviewer
> Эпик (tracking-issue, real): **`kacho-workspace#132`** — [EPIC] Storage-Compute IaaS
>   (`https://github.com/PRO-Robotech/kacho-workspace/issues/132`; alignment-док
>   `docs/plans/storage-compute-iaas-overview.md`). Per-repo KAC-тикет+ветка заводится на gate #2
>   (после APPROVED), привязывается subtask'ом к этому эпику.
> Владелец ресурсов: **kacho-storage** (Volume `vol`, Snapshot `snp`, DiskType slug, VolumeAttachment — sub-record)

## 0. Обзор

CS-1 фиксирует **фундамент сетевого блочного хранилища** Kachō как самостоятельного
владельца-домена `kacho-storage`: ресурсы **`Volume`** (персистентный блочный диск),
**`VolumeAttachment`** (join-запись Volume↔Instance, целиком принадлежит storage),
**`Snapshot`** (point-in-time копия тома) и **`DiskType`** (admin-каталог классов диска).
Это **production-grade** контракт, а не MVP: все within-service инварианты выражены
DB-конструкциями (FK RESTRICT / PK / partial UNIQUE / EXCLUDE / атомарный CAS), не
software-refcount (ban #10); мутации async через `Operation` (ban #9, исключение — admin
`DiskType` CRUD, см. §0.3); cross-service ссылки (`zone_id`→geo, `project_id`→iam,
`instance_id`→compute) — TEXT без FK, валидируются peer-API fail-closed либо self-describing
CAS (data-integrity.md).

Ключевой архитектурный тезис: **storage владеет ВСЕЙ attach-state**. Компьют её не держит —
привязка живёт строкой `volume_attachments` **рядом** с `volumes` в БД storage, поэтому
«диск нельзя удалить, пока он примонтирован» и «диск примонтирован ≤1 инстансу глобально»
это **настоящие DB-constraint'ы**, а не проверка-в-коде. Attach/Detach выставлены на
`InternalVolumeService` (:9091, mTLS) для cross-service саги compute (`Instance.AttachDisk`
→ `InternalVolumeService.Attach`); ребро **строго одностороннее** — storage валидирует свою
строку `volumes` из self-describing payload и **никогда не зовёт compute** (ацикличность,
ретроспектива KAC-266).

Границы CS-1: **single-attach** (PK=`volume_id`, ≤1 attachment на том) — это v1. Multi-attach /
RWX (composite-PK, `shareable`/`max_attachments`) — **заявленный рост, вне этой под-фазы**
(§0.3). Compute-сторона саги (`Instance.AttachDisk`/`DetachDisk`, зеркала на `Instance`,
graceful-degrade) — **не в CS-1**; она принята отдельным документом
`sub-phase-compute-storage-volume-attach-acceptance.md` (стадии S3–S5). CS-1 — это
storage-сторона (эквивалент стадий S1–S2 того документа), расширенная до полного CRUD
`DiskType`/`Snapshot`.

## 0.0. Отношение к companion-документу (supersession + amendment)

Существует **уже-APPROVED** companion — `docs/specs/sub-phase-compute-storage-volume-attach-acceptance.md`
(далее «companion»), покрывающий тот же раскол compute↔storage. Чтобы две APPROVED-спеки **не
управляли одной и той же Volume/attach-поверхностью** противоречиво, граница ответственности
фиксируется явно:

- **CS-1 замещает (supersedes) companion S1–S2** — всю **storage-сторону** контракта
  (`Volume` lifecycle + FK-инварианты; `InternalVolumeService` attach-CAS). Storage-поверхность
  Volume/VolumeAttachment/DiskType/Snapshot определяется **этим** документом.
- **Companion сохраняет силу для compute-стороны — S3–S5** (`Instance.AttachDisk`/`DetachDisk`
  сага, зеркала `bootVolume`/`secondaryVolumes` на `Instance`, graceful-degrade,
  `AttachNetworkInterface` vpc-плечо, `cpu_guarantee_percent`, resize-прозрачность). CS-1 их **не**
  переопределяет.
- **Compute-сага теперь потребляет `InternalVolumeService` из CS-1 как storage-примитив.** Companion
  S3 (`AttachDisk`) вызывает `InternalVolumeService.Attach`, чей контракт (payload, CAS-предикаты,
  error-тексты, идемпотентность) задаёт **CS-1 §S4**, а не companion S2. Companion S3-04 (zone
  mismatch) и S3-08 (delete-in-use) наблюдают storage-исход, **определённый здесь**.
- **При любом расхождении между CS-1 и companion по storage-поверхности — побеждает CS-1.**
  Конкретные расхождения, которые CS-1 **осознанно исправляет** относительно companion S1–S2:
  1. **DiskType ID** — CS-1 фиксирует **slug-PK** (см. §0.0.1 amendment), а не companion-`dtp`.
  2. **Attach placement-coherence error-тексты** — CS-1 §S4-05 разделяет zone-mismatch и
     project-mismatch на **два разных** нормативных текста; companion S2-04 схлопывал оба в
     zone-текст (вводящий в заблуждение — assert'ился бы «same zone» при реальном project-mismatch).
     CS-1-версия — нормативна; **companion S2-04 уже амендирован** в два раздельных текста (§0.0.1,
     discharge исполнен) — противоречие устранено.

### 0.0.1. Amendment: DiskType ID = slug (формально замещает companion `dtp`)

Companion §0.1/Q1 зафиксировал `DiskType`-префикс `dtp` («часть контракта»). Это **расходится** с
коммитнутым `kacho-proto/proto/kacho/cloud/storage/v1/disk_type.proto` (`id` = «a slug set
explicitly by an admin, e.g. `network-ssd`», PK, immutable), с overview §1 (`DiskType | slug`) и с
парити MachineType (тоже slug-каталог). **CS-1 закрывает это как slug** (не открытый вопрос):
`DiskType.id` — admin-assigned человекочитаемый slug (напр. `block-balanced`), **не** генерируемый
`ids.NewID`-префикс. `Snapshot`=`snp` и `Volume`=`vol` — без изменений (совпадают с proto и companion).

**Contract-note — РАЗРЕШЁН (companion правлен, а не отложен на тикет).** Чтобы два APPROVED-дока
не противоречили **уже сейчас** (до старта кода), companion-док
`docs/specs/sub-phase-compute-storage-volume-attach-acceptance.md` **амендирован механически**
(поведение не меняет — slug уже в proto) в тот же приём:
  1. **§0.1 (ID-префиксы)** — `DiskType`=`dtp`* → **`DiskType`=admin-slug** (с amendment-пометкой
     2026-07-15 и ссылкой на CS-1 §0.0.1 как авторитет).
  2. **Q1 (Решённые вопросы)** — «`dtp` принят» → «`DiskType`=admin-slug, `Snapshot`=`snp`».
  3. **§0.1 error-таблица + сценарий S2-04** — схлопнутый zone/project-текст **разделён на два**:
     `Volume and Instance must be in the same zone` (zone) **и** `Volume and Instance must be in the
     same project` (project), с amendment-пометкой.

Трекинг discharge — эпик **`kacho-workspace#132`** (governance-раздел тела). Т.е. contract-note
**исполнен**, а не оставлен как unbound-`KAC-<N>`: implementer, открыв companion, видит slug и два
раздельных текста, совпадающие с CS-1 — противоречие устранено at-source. (Пример-slug `dtp-std` в
companion-сценариях — иллюстративная admin-строка, читается как произвольный slug.)

---

## 0.1. Терминология и соглашения (для всех сценариев)

- **«Operation done»** = клиент опросил `OperationService.Get(<opId>)` (REST
  `GET /storage/v1/operations/{operationId}`) до `done=true`. **«Operation ok/response»** =
  `done=true`, `result` содержит `response` (`Any`, распакованный ресурс). **«Operation error»**
  = `done=true`, `result` содержит `google.rpc.Status` с указанным кодом. Watch RPC не существует —
  клиент поллит (`OperationService.Get` для in-flight, `List` 2–5 c).
- **«sync <code>»** = RPC вернул ошибку синхронно **до** создания `Operation` (fast-fail в
  handler/use-case). Так отдаются malformed-id, input-валидация (`size_bytes`/`name`),
  update_mask-нарушения, object-scoped authz и peer-validate на request-path (`zone_id`/`project_id`).
  Отказы, вскрывающиеся при доменной записи (FK RESTRICT, размер-CAS, from-snapshot), приходят
  как **Operation error** (проверяются в worker'е).
- **Control-plane semantics (нет data-plane).** LRO-worker выполняет доменную запись
  синхронно и сразу финализирует: `state`→`READY` мгновенно (нет промежуточного `CREATING`
  на wire для happy-path — Create-Operation завершается `done=true` с готовым ресурсом).
  Реальная провизионизация тома — будущий data-plane инкремент (§0.3).
- **ID-префиксы** (`ids.NewID`, 3-char): `Volume`=`vol`, `Snapshot`=`snp`, op-root storage=`sop`
  (opsproxy маршрутизирует `Operation.Get` по первым 3 символам). **`DiskType.id` — admin-assigned
  slug** (напр. `block-balanced`), НЕ генерируемый префикс: это PK-строка, задаваемая админом
  (grounded в `disk_type.proto`; формально замещает companion-`dtp` — см. §0.0.1 amendment).
  `VolumeAttachment` собственного id не имеет (идентифицируется `volume_id` — PK).
- **JSON — camelCase**: `volumeId`, `projectId`, `zoneId`, `diskTypeId`, `sizeBytes`, `blockSize`,
  `sourceSnapshotId`, `sourceVolumeId`, `snapshotId`, `deviceName`, `isBoot`, `autoDelete`,
  `instanceId`, `instanceName`, `performanceTier`, `zoneIds`, `usedBy`, `attachments`, `createdAt`,
  `updatedAt`, `status`.
- **REST-пути** (public, external TLS + :9090): `/storage/v1/volumes`, `/storage/v1/volumes/{volumeId}`,
  `/storage/v1/volumes/{volumeId}/operations`, `/storage/v1/snapshots`, `/storage/v1/snapshots/{snapshotId}`,
  `/storage/v1/diskTypes`, `/storage/v1/diskTypes/{diskTypeId}` (**read**). **Internal (:9091, mTLS,
  НЕ на external endpoint)**: `InternalVolumeService.Attach/Detach/ListAttachments/GetInternal`
  (gRPC service→service, без публичной REST-аннотации), `InternalDiskTypeService.Create/Update/Delete`
  (admin CRUD, проксируется на `/storage/v1/diskTypes` только через internal-mux).
- **Timestamps** усечены до секунд (`Truncate(time.Second)`) во ВСЕХ proto-ответах, включая
  под-записи (`VolumeAttachment.attachedAt`) — микросекунды с БД на wire не текут.
- **Error-тексты — часть контракта** (§0.2). Assert'ы на негативах — **behaviour-level**:
  проверяют И код, И точное сообщение (не только `codes.X`), согласно `testing.md`
  «regression-lock на уровне обсёрвабла».

## 0.2. Точные error-тексты (нормативны — часть контракта)

| Текст | gRPC-код | Триггер |
|---|---|---|
| `invalid volume id '<X>'` | `INVALID_ARGUMENT` (sync) | malformed `vol`-id первым стейтментом RPC (`Get`/`Update`/`Delete`/`Attach`/`Detach`/`ListOperations`) |
| `invalid snapshot id '<X>'` | `INVALID_ARGUMENT` (sync) | malformed `snp`-id первым стейтментом RPC |
| `Volume <id> not found` | `NOT_FOUND` | `Volume.Get`/`Update`/`Delete` well-formed-но-нет |
| `Snapshot <id> not found` | `NOT_FOUND` | `Snapshot.Get`/`Update`/`Delete` well-formed-но-нет |
| `DiskType <id> not found` | `NOT_FOUND` | `DiskType.Get`/admin `Update`/`Delete` well-formed-но-нет |
| `Illegal argument size_bytes` | `INVALID_ARGUMENT` (sync domain-validate; DB CHECK `size_bytes>0` `23514` — backstop) | `Volume.Create` `sizeBytes<=0` |
| `Illegal argument name` | `INVALID_ARGUMENT` (sync domain-validate) | `Volume`/`Snapshot`/`DiskType` name: >63 / uppercase / invalid-char (self-validating newtype) |
| `unknown zone id '<X>'` | `INVALID_ARGUMENT` (sync) | `Volume.Create` peer-validate `zoneId` через `geo.v1.ZoneService.Get` вернул NotFound/InvalidArgument |
| `Project <id> not found` | `FAILED_PRECONDITION` (sync) | `Volume.Create`/`Snapshot.Create` peer-validate `projectId` через `iam.v1.ProjectService.Get` вернул NotFound/InvalidArgument |
| `volume with name <n> already exists in project` | `ALREADY_EXISTS` | partial `UNIQUE(project_id,name) WHERE name<>''` (`23505`) на Create/Update |
| `snapshot with name <n> already exists in project` | `ALREADY_EXISTS` | partial `UNIQUE(project_id,name) WHERE name<>''` (`23505`) |
| `DiskType <id> already exists` | `ALREADY_EXISTS` | admin `DiskType.Create` дубликат PK-слага (`23505`) |
| `Volume size can only be increased` | `INVALID_ARGUMENT` (Operation error) | `Volume.Update` `sizeBytes` ≤ текущего (increase-only размер-CAS: 0-row + строка есть) |
| `<field> is immutable after Volume.Create` | `INVALID_ARGUMENT` (sync) | immutable-поле в `update_mask` (`zone_id`/`disk_type_id`/`block_size`/`source_snapshot_id`/`used_by`) |
| `<field> is immutable after Snapshot.Create` | `INVALID_ARGUMENT` (sync) | immutable-поле в `update_mask` (`source_volume_id`/`project_id`/`size_bytes`) |
| `Volume <id> is in use` | `FAILED_PRECONDITION` | (a) `Volume.Delete` привязанного тома (FK `volume_attachments.volume_id` RESTRICT `23503`, Operation error); (b) `Attach` на том, занятый другим инстансом |
| `DiskType <id> not found` | `FAILED_PRECONDITION` (Operation error) | `Volume.Create` с несуществующим `diskTypeId` — **same-DB** FK RESTRICT `23503` (не cross-service) |
| `Snapshot <id> not found` | `FAILED_PRECONDITION` (Operation error) | `Volume.Create` с несуществующим `sourceSnapshotId` — same-DB FK `23503` |
| `DiskType <id> is in use` | `FAILED_PRECONDITION` | admin `DiskType.Delete`, пока на тип ссылается `Volume` (FK RESTRICT `23503`) |
| `Volume is not available for attachment` | `FAILED_PRECONDITION` | `Attach` на том в `state != READY` (или тома нет) |
| `Volume and Instance must be in the same zone` | `FAILED_PRECONDITION` | `Attach`: `zone_id` тома ≠ `instance_zone_id` (zone-coherence CAS-предикат; **только** зона) |
| `Volume and Instance must be in the same project` | `FAILED_PRECONDITION` | `Attach`: `project_id` тома ≠ `project_id` в payload (project-coherence CAS-предикат; **отдельный** текст — не переиспользуется zone-текст) |
| `device <name> is already in use on Instance <id>` | `FAILED_PRECONDITION` | `Attach` с явным `deviceName`: `UNIQUE(instance_id,device_name)` (`23505`) |
| `no free device name on Instance <id>` | `FAILED_PRECONDITION` | `Attach` с пустым `deviceName`: пространство `sdb..sdz` исчерпано (все 25 имён заняты) — auto-allocation не нашла свободного после retry |
| `Instance <id> already has a boot volume` | `FAILED_PRECONDITION` | `Attach` второго boot-тома, `EXCLUDE (instance_id WITH =) WHERE is_boot` (`23P01`) |
| `Volume <id> is not ready` | `FAILED_PRECONDITION` (Operation error) | `Snapshot.Create` из тома в `state != READY` |
| `Volume <id> not found` | `FAILED_PRECONDITION` (Operation error) | `Snapshot.Create` из несуществующего `sourceVolumeId` (from-READY-CAS 0-row) |
| `permission denied` | `PERMISSION_DENIED` (sync) | authz-Check не прошёл: (a) object-scoped anti-BOLA — caller без `viewer`(read)/`editor`(мутация) на проект **целевого** ресурса (`Volume.Get/Update/Delete` scope `{storage_volume,volume_id}`; `Snapshot.Get/Update/Delete` scope `{storage_snapshot,snapshot_id}`); (b) `List{projectId=P}`, где caller без `viewer` на `P` (scope `{project,project_id}`). **Фикс. opaque-текст**, существование цели **не** раскрывается (одинаковый ответ, есть цель или нет — не existence-oracle, `security.md` hardening #5) |
| `internal error` | `INTERNAL` | дефолт-ветка mapper — **никогда** не эхает pgx/SQL-текст |

Пиры недоступны на `Create` (geo/iam `Unavailable`) → **`UNAVAILABLE`** (fail-closed для мутации);
сообщение opaque (код — часть контракта, текст — нет).

## 0.3. Инварианты-критерии (проверяются, не только Given-When-Then)

- **INV-1 — Ацикличность storage→compute (data-integrity cross-domain rule 2, `polyrepo.md`).**
  `kacho-storage/internal/clients/` **не импортирует** compute-stub. `Attach`/`Detach` — self-describing
  (payload несёт `instanceId`/`instanceName`/`instanceZoneId`/`projectId`), storage валидирует **свою**
  строку `volumes` атомарным CAS и **не зовёт** `compute.InstanceService.Get`. Критерий — build-time
  arch-guard + фиксация рёбер `storage→geo`/`storage→iam` в `polyrepo.md` как one-way.
- **INV-2 — Within-service инварианты на DB (ban #10).** «том привязан ≤1 инстансу»,
  «delete привязанного блокируется», «уникальный `device_name` в инстансе», «≤1 boot-том на инстанс»,
  «размер только растёт», «snapshot только из READY-тома», «том держит свой DiskType (нельзя удалить тип
  с томами)» — все на DB-уровне (PK / FK RESTRICT / partial UNIQUE / EXCLUDE / атомарный CAS), **не**
  `Get→check→write` (TOCTOU). Каждый спорный путь несёт integration-тест с concurrent goroutines (§DoD).
- **INV-3 — Мутации async через `Operation`** (ban #9): `Volume`/`Snapshot` `Create`/`Update`/`Delete`
  возвращают `operation.Operation`; reads (`Get`/`List`) sync. **Исключение (осознанное, по прецеденту):**
  admin `DiskType` CRUD (`InternalDiskTypeService.Create/Update/Delete`) — **синхронный**, возвращает
  ресурс, не Operation. Это не отклонение ad-hoc, а **установленный паттерн admin-каталога** Kachō:
  admin-справочник (нет реального провижининга → нечего оркестрировать LRO). Прецеденты (существующие,
  не гипотетические): **geo `Region`/`Zone`** — public read + Internal admin CRUD, синхронный
  (overview §1 «Public read + Internal admin CRUD»; `polyrepo.md` карта geo); **vpc `AddressPool`** —
  admin-only Internal-ресурс (`.claude/rules/api-conventions.md` «AddressPool — admin-only ресурс
  (Internal*)»). Решение зафиксировано в `project/kacho-storage/docs/architecture/overview.md`
  §«Async vs sync (api-conventions.md)» (запись **существует**: «DiskType: Get/List sync (public);
  admin CRUD (InternalDiskTypeService) СИНХРОНЕН … admin-справочник без LRO»). Grounded в
  коммитнутом `disk_type_service.proto` (`Create/Update/Delete returns (DiskType)`, не `Operation`).
- **INV-4 — Placement-coherence (data-integrity.md).** `Volume` — зональный ресурс (`zone_id`
  immutable, существование peer-validated через geo). Attach Volume↔Instance когерентен по зоне **и**
  по проекту: `volumes.zone_id = $instance_zone_id` **и** `volumes.project_id = $project_id`
  энфорсятся **внутри attach-CAS-предиката** (within-service, DB-уровень), не software-проверкой.
  Каждая некогерентность несёт **свой** нормативный текст (тексты — часть контракта, assert'ятся
  behaviour-level): zone-mismatch → `FAILED_PRECONDITION` `Volume and Instance must be in the same
  zone`; project-mismatch → `FAILED_PRECONDITION` `Volume and Instance must be in the same project`.
  Тексты **не** переиспользуются между причинами (zone-текст на project-mismatch = вводящий в
  заблуждение контракт — исправлено относительно companion S2-04, см. §0.0). Разрешение
  неоднозначности (какой из двух предикатов не сматчил) — disambiguation-SELECT в той же TX после
  0-row CAS (том READY, но zone/project не совпал). (Anycast/REGIONAL для томов — вне CS-1; том
  строго зонален.)
- **INV-5 — Derived status (нет дрейфа).** `Volume.status` `AVAILABLE`/`IN_USE` — **derived** из
  наличия строки `volume_attachments` (LEFT JOIN на чтении), НЕ отдельная колонка. `IN_USE`
  невозможно рассинхронизировать с attach-state by construction.
- **INV-6 — Lean public projection (ban #6 + infra-sensitive, `security.md`).** Публичный
  `Volume.Get`/`List` (`VolumeService`, external) **не несёт** инфра-полей (backend-LUN /
  NVMe-namespace / storage-node / pool-id / числовой инфра-id / ёмкость). Инфра-проекция живёт
  **только** на :9091 (`InternalVolumeService.GetInternal` — анкер, §0.3). Публичный `VolumeAttachment`
  (в `Volume.attachments[]`) несёт tenant-facing поля (`instanceId`/`instanceName`/`deviceName`/`isBoot`/
  `mode`/`autoDelete`/`attachedAt`), но **не** `projectId`/`zoneId` (self-describing placement — только
  на internal attach-пути). Проверяется CS1-S1-11.
- **INV-7 — Internal-vs-external (ban #6) + AuthN/AuthZ на :9091 (security.md hard-invariant).**
  `InternalVolumeService.*` и `InternalDiskTypeService.*` выставлены **только** на :9091 (mTLS) и
  **не маршрутизируются** на external endpoint. Каждый internal-RPC проходит **per-RPC**
  `InternalIAMService.Check` (мутации — `editor`/`system_admin`-tier + `scope_extractor` на целевой
  объект; read — `viewer`-tier), а не «mTLS достаточно». Assert: отсутствие на external mux (INV-7a)
  **и** caller без права → `PERMISSION_DENIED` (behaviour-level).
- **INV-8 — INTERNAL не эхает pgx/SQL.** Дефолт-ветка любого `mapErr` → фиксированный `"internal error"`;
  SQLSTATE логируется только на repo-границе. Regression-тест проверяет **сообщение**, не только код.
- **INV-9 — Timestamp truncate** до секунд на `Volume`/`Snapshot`/`VolumeAttachment.attachedAt`.
- **INV-10 — Public-surface authz: object-scoped анти-BOLA + listauthz-filter (security.md
  «AuthN+AuthZ ВЕЗДЕ — для public И internal правила ОДИНАКОВЫЕ», overview §2 tenant-isolation).**
  Публичные `VolumeService`/`SnapshotService` (:9090) — **не** «read = всем можно». Каждый public-RPC
  проходит per-RPC `InternalIAMService.Check` с proto-`scope_extractor` (коммитнуто):
    - **object-scoped (анти-BOLA):** `Volume.Get/Update/Delete` → `{storage_volume, volume_id}`;
      `Snapshot.Get/Update/Delete` → `{storage_snapshot, snapshot_id}`. Caller без
      `viewer`(read)/`editor`(мутация) на проект **целевого** объекта → `PERMISSION_DENIED`
      (проверка против **целевого** ресурса, а не только права метода — иначе BOLA). Ответ
      existence-non-revealing (один и тот же `permission denied`, есть цель или нет).
    - **list-scoped + result-filter (listauthz):** `Volume.List`/`Snapshot.List` → `{project,
      project_id}`. Caller без `viewer` на запрошенный `projectId` → `PERMISSION_DENIED`; при
      наличии — результат **отфильтрован** listauthz (CI-гейт `make audit-list-filter`) так, что
      caller, авторизованный на `prj-1`, **никогда** не видит ресурсы `prj-2` (кросс-проектной
      утечки нет by construction).
  Публичный `DiskType.Get/List` — `{cluster, *}` `viewer` (каталог cluster-wide, не project-scoped)
  → анти-BOLA/ per-project-filter к нему неприменимы by design. Assert — **behaviour-level** (код
  `PERMISSION_DENIED` + фикс. текст `permission denied`), не декларацией. Проверяется CS1-S1-13/14,
  CS1-S3-07/08 (public), в дополнение к INV-7 (internal :9091).

## 0.4. Non-goals — заявленный рост (граница by-design, НЕ tech-debt)

Ведут себя как «нет такого пути», а не «недоделано». Источник — overview §4 «Growth areas».

- **Multi-attach / RWX volumes** — v1 строго single-attach (PK=`volume_id`, ≤1 attachment/том).
  Composite-PK, `shareable`/`max_attachments`, RWX-семантика — отдельный эпик.
- **`InternalVolumeService.GetInternal` + инфра-проекция** (`VolumeInternal`: backend-LUN /
  NVMe-namespace / storage-node / pool-id / числовой инфра-id / ёмкость) — **stub в CS-1**: data-plane
  отсутствует, заполнять инфра-поля нечем. RPC зарегистрирован, `VolumeInternal` — скелет
  (`reserved 2..15`), реализация репо возвращает `UNIMPLEMENTED`. Вводится будущим data-plane
  инкрементом. В CS-1 фиксируется лишь **lean public projection** (INV-6).
- **QoS-rich `DiskType`** — `iops_*`/`throughput_*` bounds (min/max/step) — рост (overview §4). CS-1
  каталог несёт `performanceTier` (нативный tier-slug: `standard`/`balanced`/`fast`/`single`/`io-max`)
  + `zoneIds`-scoping; числовые QoS-границы **не** в контракте CS-1 (флаг для reviewer — см. §0.7 Q3).
- **`Volume.Relocate`** (смена зоны) — противоречит immutable `zone_id`; без data-plane ничего не
  «перемещает». Отдельный эпик.
- **Snapshot restore/clone/incremental/schedules, at-rest encryption + CMK** — рост. CS-1: `Snapshot`
  = point-in-time запись из READY-тома + CRUD + FK SET NULL; восстановление тома **из** снапшота
  моделируется только как `Volume.Create{sourceSnapshotId}` (existence-check в своей БД, CS1-S1-12),
  без переноса блоков (data-plane).
- **Boot-from-Volume канонический флоу, гостевой fs/partition grow** после ресайза, **local ephemeral
  disks** — data-plane/compute, вне CS-1.
- **Compute-сторона attach-саги** (`Instance.AttachDisk`/`DetachDisk`, зеркала `bootVolume`/
  `secondaryVolumes` на `Instance`, graceful-degrade, `auto_delete`-cascade при `Instance.Delete`) —
  в `sub-phase-compute-storage-volume-attach-acceptance.md` (S3–S5), не в CS-1. CS-1 предоставляет
  **только** внутренний attach-примитив (`InternalVolumeService`), потребляемый той сагой.
- **Storage-side liveness-sweep** привязок (storage спрашивает compute «жив ли инстанс») — создал бы
  ребро storage→compute = цикл. Dangling `instance_id` терпится; чистка compute-driven.

## 0.5. Traceability (overview + конвенции Kachō → сценарии CS-1)

| Источник | Тема | Сценарий(и) |
|---|---|---|
| overview §1 (Volume) / api-conventions | Volume flat + Operations CRUD | CS1-S1-01..06 |
| overview §1 (Volume grow-only), api-conv update_mask | size increase-only + immutable | CS1-S1-04, CS1-S1-05 |
| overview §1 (Volume FK), data-integrity | delete-in-use RESTRICT, DiskType/Snapshot FK | CS1-S1-07, CS1-S2-05, CS1-S3-06 |
| data-integrity cross-domain rule 2 | peer-validate zone/project fail-closed | CS1-S1-08, CS1-S1-09 |
| overview §1 (source_snapshot) | create-from-snapshot (existence в своей БД) | CS1-S1-10 |
| security.md (two-projection) | lean public projection (INV-6) | CS1-S1-11 |
| security.md (AuthZ ВЕЗДЕ) + overview §2 (listauthz) | public `List` listauthz-filter (INV-10) | CS1-S1-13, CS1-S3-07 |
| security.md (object-scoped, hardening #3) + overview §2 (anti-BOLA) | public object-scoped анти-BOLA (INV-10) | CS1-S1-14, CS1-S3-08 |
| api-conventions (Operation poll) | `Volume.ListOperations` (per-resource op-log) | CS1-S1-15 |
| overview §1 (DiskType), security.md (Internal admin) | admin catalog: public read + Internal CRUD | CS1-S2-01..05 |
| overview §1 (Snapshot from READY) | snapshot из READY-тома + CRUD + FK SET NULL | CS1-S3-01..06 |
| overview §2 (Disk-attach), data-integrity CAS | attach/detach single-attach, boot, device | CS1-S4-01..12 |
| data-integrity placement-coherence | zone-**и** project-coherence в attach-CAS (INV-4) | CS1-S4-05 |
| data-integrity §5 concurrency (ban #12) | double-attach race → ровно один | CS1-S4-10 |
| data-integrity §5 concurrency (ban #12) | auto-device-name contended-allocation → разные имена | CS1-S4-08 |
| security.md (:9091 authz + ban #6) | Internal-only + per-RPC Check | CS1-S4-11, INV-7 |

## 0.6. Существующий spike в `project/kacho-storage` — НЕ авторитетен (ban #1 + TDD)

**Этот документ авторизует поверхность вперёд.** APPROVE CS-1 — это то, что открывает кодинг-гейт
(lifecycle #1, ban #1), а **не** ратификация уже написанного кода. В `project/kacho-storage` уже
существует spike (скелет service-scaffolder + частичное наполнение), но он **не несёт никакой
контрактной силы**: контракт CS-1 стоит сам по себе (proto + правила Kachō + overview как источники),
и код обязан быть приведён к нему, а не наоборот.

**TDD RED→GREEN (`.claude/rules/testing.md`) применяется и к уже написанному коду.** Существующий
spike трактуется как **непроверенный до тех пор, пока под него не написаны падающие тесты**:
`integration-tester` первым делом пишет RED-тесты по сценариям CS-1 (integration testcontainers +
newman), прогоняет их против spike'а, и **любое расхождение spike'а с контрактом — это баг, чинимый
до GREEN**, а не «уже готово». В частности `DiskType` admin CRUD и `Snapshot` full CRUD, **которых
companion S1–S2 не покрывал**, авторизуются **этим** документом (§S2, §S3) — их наличие в spike'е не
заменяет acceptance-гейт и не освобождает от RED-до-GREEN.

Ниже — **инвентарь spike'а (информационный, не авторитетный)** — чтобы `integration-tester` знал, где
ожидать GREEN сразу, а где RED вскроет недоделку; ни одна строка ниже не является утверждением
«контракт выполнен»:

- **Есть в spike (ожидается близко к контракту, подтвердить RED-тестами):** `Volume`
  Create/Update/Delete (async Operation, worker пишет `state=READY` сразу) / Get / List (cursor
  `(created_at,id)` + `filter=name`); size increase-only CAS; FK RESTRICT `disk_type_id`; FK SET NULL
  `source_snapshot_id`; peer-validate zone→geo, project→iam; immutable-switch + update_mask;
  malformed-id-first; derived status; lean public projection. `InternalVolumeService` Attach
  (`INSERT … ON CONFLICT (volume_id) DO NOTHING` CAS) / Detach / ListAttachments; auto device_name
  (`sdb..sdz`). `Snapshot` from-READY-CAS Create / Update / Delete / Get / List; FK SET NULL обе
  стороны. `DiskType` public Get/List + Internal admin Create/Update/Delete (sync); seed tier-slug'ов;
  FK RESTRICT со стороны volumes. Outbox (`storage_outbox`) в writer-tx; `internal error`-mapping.
  — **Всё это подлежит RED-тесту первым; «есть в коде» ≠ «соответствует контракту».**
- **Осознанно заглушено (анкер, out-of-scope §0.4):** `InternalVolumeService.GetInternal`
  (infra-проекция) — репо `UNIMPLEMENTED`; `VolumeInternal` — скелет `reserved 2..15`. Единственный
  намеренно неполный путь; **не** tech-debt (data-plane отсутствует). RED-тест фиксирует именно
  `UNIMPLEMENTED` как контрактный ответ этого инкремента.
- **Требует подтверждения в проде (DoD, не «сделано»):** per-RPC `InternalIAMService.Check` активен на
  **обоих** листенерах (:9090 / :9091) fail-closed (не dev-passthrough); mTLS на :9091; public RPC в
  api-gateway public-mux, Internal RPC — **только** internal-mux. Public-поверхность **тоже** гейтится
  (не «read = всем»): object-scoped анти-BOLA + listauthz-filter на `VolumeService`/`SnapshotService`
  (INV-10). Проверяется поведенческими тестами — internal: CS1-S2-04, CS1-S4-11; **public: CS1-S1-13/14/15,
  CS1-S3-07/08** — не декларацией.

## 0.7. Решённые вопросы (зафиксированы; менять — только осознанно через тикет)

- **Q1 — snapshot-not-ready текст (РЕШЕНО: оставить отдельный текст).** `Snapshot.Create` из не-READY
  тома → `Volume <id> is not ready` (`FAILED_PRECONDITION`, Operation error) — **не**
  `Volume is not available for attachment` (тот зарезервирован под attach-путь). Разные домены
  (snapshot vs attach) несут разные тексты. Внесено: CS1-S3-02.
- **Q2 — DiskType ID (РЕШЕНО: slug-PK, не открытый вопрос).** `DiskType.id` — admin-assigned
  человекочитаемый slug (`block-balanced`), **не** генерируемый `dtp`-префикс. Grounded в коммитнутом
  `disk_type.proto` («a slug set explicitly by an admin»), overview §1 (`DiskType | slug`), парити
  MachineType. Формально **замещает** companion-`dtp` — см. §0.0.1 amendment (contract-note на правку
  companion). Больше не «предложение» — решение.
- **Q3 — числовые QoS-границы (РЕШЕНО: рост, вне CS-1).** `iops_*`/`throughput_*` (min/max/step) на
  `DiskType` — **рост** (overview §4). Коммитнутый `disk_type.proto` несёт только `performance_tier`
  (+ `zone_ids`); CS-1 = tier+zones. Числовые QoS вводятся будущим инкрементом (добавит proto-поля и
  сценарии) — в CS-1 их нет by construction (§0.4).
- **Q4 — delete-in-use семантика (РЕШЕНО: async Operation error).** `Volume.Delete` привязанного тома
  отдаёт **Operation error** `Volume <id> is in use` (FK RESTRICT `23503` вскрывается в worker'е), а
  не sync — симметрично прочим Delete-мутациям (`Delete` → `Operation`, ban #9). Внесено: CS1-S1-07.

---

# Стадия S1 — `Volume` lifecycle + FK-инварианты (kacho-storage, public :9090)

**DoD стадии:** proto+regen (buf lint/breaking зелёные) · миграция `volumes` (FK RESTRICT disk_type,
FK SET NULL snapshot, partial UNIQUE name, CHECK size>0, derived status) · repo (handwritten pgx,
size-CAS, outbox) · use-case (LRO, update_mask, peer-validate) · `ListOperations` (per-resource
op-log, CS1-S1-15) · integration-тесты (testcontainers, size-CAS 0-row disambiguation) · **newman
happy+negative + public-authz: `List` listauthz-filter (CS1-S1-13) и object-scoped анти-BOLA
`Get/Update/Delete/ListOperations` (CS1-S1-14/15) → `PERMISSION_DENIED`, behaviour-level (INV-10);
public RPC на public-mux с per-RPC Check** · vault-trail (`resources/kacho-storage-volume.md`,
`edges/storage-to-geo-zone-validate.md`, `edges/storage-to-iam-project-validate.md`).

## Сценарий CS1-S1-01: Create `Volume` — happy path (async → Operation, state READY сразу)

**ID:** CS1-S1-01

**Given** существует проект `prj-1` (kacho-iam) и зона `region-1-a` (kacho-geo)
**And** в каталоге есть `DiskType` `block-balanced`

**When** клиент вызывает `VolumeService.Create` (`POST /storage/v1/volumes`) с payload:
  - `projectId` = `prj-1`
  - `name` = `data-01`
  - `zoneId` = `region-1-a`
  - `diskTypeId` = `block-balanced`
  - `sizeBytes` = `10737418240` (10 GiB)

**Then** RPC возвращает `Operation` с `done=false`, `metadata.volumeId` заполнен префиксом `vol`
**And** после полла `OperationService.Get(<opId>)` до `done=true` — `result.response` распаковывается
        в `Volume` с `id` (`vol…`), `createdAt`/`updatedAt` (усечены до секунд), `blockSize=4096`
        (default), `status=AVAILABLE` (derived: attachment нет)
**And** последующий `VolumeService.Get(volumeId)` возвращает тот же `Volume`, `attachments` пуст,
        `usedBy` пуст

## Сценарий CS1-S1-02: `Volume.Get` — malformed id (sync) и well-formed-но-нет (NotFound)

**ID:** CS1-S1-02

**Given** валидных предусловий не требуется

**When** клиент вызывает `VolumeService.Get` с `volumeId` = `not-a-vol-id`
**Then** sync `INVALID_ARGUMENT` `invalid volume id 'not-a-vol-id'` (первым стейтментом, до repo)

**When** клиент вызывает `VolumeService.Get` с well-formed, но несуществующим `volumeId` = `vol00000000000000000`
**Then** `NOT_FOUND` `Volume vol00000000000000000 not found`

## Сценарий CS1-S1-03: `Volume.List` — cursor pagination + filter + project-scope

**ID:** CS1-S1-03

**Given** в проекте `prj-1` создано 3 тома (`a`, `b`, `c` по `createdAt`)

**When** клиент вызывает `VolumeService.List` (`GET /storage/v1/volumes?projectId=prj-1&pageSize=2`)
**Then** `INVALID_ARGUMENT` не возникает; возвращается ровно 2 тома в порядке `(createdAt,id) ASC` +
        непустой `nextPageToken`
**And** повторный `List` с этим `pageToken` возвращает оставшийся 1 том, `nextPageToken` пуст

**When** клиент вызывает `List` с `filter=name=b`
**Then** возвращается ровно том `b` (whitelist поля `name`)

**When** клиент вызывает `List` с garbage `pageToken`
**Then** `INVALID_ARGUMENT` (opaque page-token не декодируется)

**When** клиент вызывает `List` с `pageSize=5000`
**Then** `INVALID_ARGUMENT` (`page_size` > max 1000)

## Сценарий CS1-S1-04: `Volume.Update` — size increase-only (grow), online

**ID:** CS1-S1-04

**Given** том `vol-A` в `prj-1` с `sizeBytes=10737418240` (10 GiB), `status=AVAILABLE`

**When** клиент вызывает `VolumeService.Update` (`PATCH /storage/v1/volumes/vol-A`) с
        `updateMask=size_bytes`, `sizeBytes=21474836480` (20 GiB)
**Then** Operation ok; `Get(vol-A)` показывает `sizeBytes=21474836480`, `updatedAt` обновлён
**And** это работает **online** — статус тома не обязан меняться (derived), инстанс не участвует

**When** клиент вызывает `Update` с `updateMask=size_bytes`, `sizeBytes=5368709120` (5 GiB, shrink)
**Then** **Operation error** `INVALID_ARGUMENT` `Volume size can only be increased` (increase-only
        размер-CAS: `WHERE $new > size_bytes` → 0-row при строке-есть)

**When** клиент вызывает `Update` с `updateMask=size_bytes`, `sizeBytes=21474836480` (равно текущему)
**Then** **Operation error** `INVALID_ARGUMENT` `Volume size can only be increased` (не строго больше)

## Сценарий CS1-S1-05: `Volume.Update` — immutable-поля в mask (sync), пустой mask = full-PATCH

**ID:** CS1-S1-05

**Given** том `vol-A` в `prj-1`

**When** клиент вызывает `Update` с `updateMask=zone_id`, `zoneId=region-1-b`
**Then** sync `INVALID_ARGUMENT` `zone_id is immutable after Volume.Create` (immutable-switch **до**
        `UpdateMask`, api-conventions gotcha — иначе generic «unknown field»)
**And** тот же результат для `disk_type_id` / `block_size` / `source_snapshot_id` / `used_by`

**When** клиент вызывает `Update` с `updateMask=nonexistent_field`
**Then** sync `INVALID_ARGUMENT` (unknown field, known-set = {name,description,labels,size_bytes})

**When** клиент вызывает `Update` с **пустым** `updateMask` и телом `{name:"renamed", description:"d"}`
        (immutable `zoneId` в теле проигнорирован)
**Then** Operation ok — full-object PATCH: применяются mutable-поля тела; immutable из тела silently
        игнорируются; `size_bytes` при пустом mask и `sizeBytes<=0` **не трогается** (0 ≠ shrink-to-0)

## Сценарий CS1-S1-06: `Volume` — partial UNIQUE(project_id, name), безымянные легальны

**ID:** CS1-S1-06

**Given** том `vol-A` с `name=data-01` в `prj-1`

**When** клиент вызывает `Create` с `name=data-01`, `projectId=prj-1` (тот же проект)
**Then** **Operation error** `ALREADY_EXISTS` `volume with name data-01 already exists in project`
        (partial `UNIQUE(project_id,name) WHERE name<>''`, `23505`)

**When** клиент вызывает `Create` с `name=data-01` в **другом** проекте `prj-2`
**Then** Operation ok (уникальность scope'ится проектом)

**When** клиент создаёт два тома с пустым `name` в `prj-1`
**Then** оба Operation ok (partial UNIQUE не действует на `name=''`)

## Сценарий CS1-S1-07: `Volume.Delete` — safe-delete через FK RESTRICT (attached → блок)

**ID:** CS1-S1-07

**Given** том `vol-A` в `prj-1`, привязанный к инстансу (строка `volume_attachments` есть, `status=IN_USE`)

**When** клиент вызывает `VolumeService.Delete` (`DELETE /storage/v1/volumes/vol-A`)
**Then** **Operation error** `FAILED_PRECONDITION` `Volume vol-A is in use` (FK
        `volume_attachments.volume_id` RESTRICT `23503` — DB-enforced, не software refcount)
**And** `Get(vol-A)` по-прежнему возвращает том (не удалён)

**When** том детачат (строка attachments удалена) и повторяют `Delete`
**Then** Operation ok, `result.response=Empty`; `Get(vol-A)` → `NOT_FOUND` `Volume vol-A not found`

**When** клиент вызывает `Delete` на несуществующем well-formed `volumeId`
**Then** **Operation error** `NOT_FOUND` `Volume <id> not found` (0-row DELETE)

## Сценарий CS1-S1-08: `Volume.Create` — peer-validate `zoneId` (cross-service, fail-closed)

**ID:** CS1-S1-08

**Given** проект `prj-1` существует

**When** клиент вызывает `Create` с `zoneId=region-9-z` (нет в kacho-geo)
**Then** sync `INVALID_ARGUMENT` `unknown zone id 'region-9-z'` (peer `geo.v1.ZoneService.Get` →
        NotFound/InvalidArgument, request-path, per-call deadline)

**When** kacho-geo недоступен (peer down) и клиент вызывает `Create` с валидным `zoneId`
**Then** sync `UNAVAILABLE` (fail-closed для мутации; сообщение opaque)

## Сценарий CS1-S1-09: `Volume.Create` — peer-validate `projectId` (cross-service, fail-closed)

**ID:** CS1-S1-09

**Given** зона `region-1-a` существует

**When** клиент вызывает `Create` с `projectId=prj-nope` (нет в kacho-iam)
**Then** sync `FAILED_PRECONDITION` `Project prj-nope not found` (peer `iam.v1.ProjectService.Get`,
        request-path)

**When** kacho-iam недоступен и клиент вызывает `Create` с валидным `projectId`
**Then** sync `UNAVAILABLE` (fail-closed)

## Сценарий CS1-S1-10: `Volume.Create` — from-snapshot и same-DB FK на `diskTypeId`/`sourceSnapshotId`

**ID:** CS1-S1-10

**Given** зона/проект валидны; в каталоге есть `block-balanced`; в `prj-1` есть READY-`Snapshot` `snp-X`

**When** клиент вызывает `Create` с `sourceSnapshotId=snp-X`, `diskTypeId=block-balanced`, валидными zone/project
**Then** Operation ok; `Get` возвращает том с сохранённым (immutable) `sourceSnapshotId=snp-X`,
        `status=AVAILABLE` (перенос блоков — data-plane, не моделируется, §0.3)

**When** клиент вызывает `Create` с несуществующим `diskTypeId=block-unicorn` (валидные zone/project)
**Then** **Operation error** `FAILED_PRECONDITION` `DiskType block-unicorn not found` (**same-DB** FK
        RESTRICT `23503`, не cross-service peer-call)

**When** клиент вызывает `Create` с несуществующим `sourceSnapshotId=snp00000000000000000`
**Then** **Operation error** `FAILED_PRECONDITION` `Snapshot snp00000000000000000 not found` (same-DB FK `23503`)

## Сценарий CS1-S1-11: публичный `Volume.Get` — lean projection (нет инфра-полей) [INV-6]

**ID:** CS1-S1-11

**Given** том `vol-A`, привязанный к инстансу (`status=IN_USE`)

**When** клиент вызывает публичный `VolumeService.Get(vol-A)` (external TLS / :9090)
**Then** ответ содержит **только** tenant-facing поля: `id`, `projectId`, `createdAt`, `updatedAt`,
        `name`, `description`, `labels`, `zoneId`, `diskTypeId`, `sizeBytes`, `blockSize`,
        `sourceSnapshotId`, `status`, `attachments[]`, `usedBy[]`
**And** ответ **не содержит** инфра-полей (backend-LUN / NVMe-namespace / storage-node / pool-id /
        числовой инфра-id / ёмкость) — их нет в публичном message by construction
**And** элемент `attachments[0]` несёт `instanceId`/`instanceName`/`deviceName`/`isBoot`/`mode`/
        `autoDelete`/`attachedAt`, но **не** `projectId`/`zoneId` (self-describing placement — только
        на internal attach-пути)

## Сценарий CS1-S1-12: `Volume.Create` — input-валидация `sizeBytes`/`name` (sync)

**ID:** CS1-S1-12

**Given** валидные zone/project

**When** клиент вызывает `Create` с `sizeBytes=0`
**Then** sync `INVALID_ARGUMENT` `Illegal argument size_bytes` (self-validating domain; DB CHECK
        `size_bytes>0` — backstop)

**When** клиент вызывает `Create` с `name=Data_Uppercase` (uppercase), либо длиной >63, либо
        **unicode/не-ASCII** (`name=том` — кириллица; proto-pattern `[a-z]([-_a-z0-9]{0,61}[a-z0-9])?`
        допускает только lowercase-ASCII/`-`/`_`/цифры)
**Then** sync `INVALID_ARGUMENT` `Illegal argument name` (для каждого из перечисленных входов —
        включая явно `name=том` → `Illegal argument name`)

## Сценарий CS1-S1-13: публичный `Volume.List` — listauthz-filter (нет кросс-проектной утечки) [INV-10]

**ID:** CS1-S1-13

**Given** caller `alice` авторизована `viewer` на `prj-1`, но **не** имеет права на `prj-2`
**And** в `prj-1` есть тома `vol-a1`,`vol-a2`; в `prj-2` — том `vol-b1`

**When** `alice` вызывает публичный `VolumeService.List` (`GET /storage/v1/volumes?projectId=prj-1`)
**Then** sync-ответ содержит **только** `vol-a1`,`vol-a2` (тома `prj-1`) — `vol-b1` (`prj-2`)
        **не** появляется никогда (result отфильтрован listauthz; CI-гейт `make audit-list-filter`)

**When** `alice` вызывает `List` с `projectId=prj-2` (проект, на который у неё нет `viewer`)
**Then** sync `PERMISSION_DENIED` `permission denied` (scope_extractor `{project, project_id}` не
        прошёл per-RPC Check) — **не** пустой список и **не** утечка существования `prj-2`
        (assert **behaviour-level**: код И фикс. текст)

## Сценарий CS1-S1-14: публичный `Volume.Get/Update/Delete` — object-scoped анти-BOLA [INV-10]

**ID:** CS1-S1-14

**Given** том `vol-b1` принадлежит `prj-2`; caller `alice` имеет права **только** на `prj-1`
        (ни `viewer`, ни `editor` на `prj-2`)

**When** `alice` вызывает `VolumeService.Get(vol-b1)` (external :9090)
**Then** sync `PERMISSION_DENIED` `permission denied` (scope_extractor `{storage_volume, volume_id}`:
        Check против проекта **целевого** тома, не только права метода — анти-BOLA). Ответ
        **не** раскрывает существование `vol-b1` (тот же `permission denied`, что для несуществующего)

**When** `alice` вызывает `VolumeService.Update(vol-b1, …)` либо `VolumeService.Delete(vol-b1)`
**Then** sync `PERMISSION_DENIED` `permission denied` (тот же object-scoped gate `{storage_volume,
        volume_id}`, `editor`-tier) — мутация **не** доходит до создания `Operation`

**When** `alice` (с `editor` на `prj-1`) вызывает те же RPC на своём `vol-a1` (`prj-1`)
**Then** авторизация проходит (Get → `Volume`; Update/Delete → `Operation`) — gate не ложно-положителен

## Сценарий CS1-S1-15: `Volume.ListOperations` — per-resource op-log (happy + malformed-id)

**ID:** CS1-S1-15

**Given** том `vol-A`, по которому выполнены `Create` (done) и `Update` (done) операции

**When** клиент вызывает `VolumeService.ListOperations` (`GET /storage/v1/volumes/vol-A/operations?pageSize=10`)
**Then** sync-ответ `ListVolumeOperationsResponse` со списком `Operation` для `vol-A` (обе: create,
        update), каждый с `id` (`sop…`), `done=true`, `createdAt` (усечён), в порядке `(createdAt,id)`;
        cursor `nextPageToken` при переполнении страницы

**When** клиент вызывает `ListOperations` с malformed `volumeId=not-a-vol`
**Then** sync `INVALID_ARGUMENT` `invalid volume id 'not-a-vol'` (первым стейтментом, парити с Get)

**When** caller без `viewer` на проект `vol-A` вызывает `ListOperations`
**Then** sync `PERMISSION_DENIED` `permission denied` (scope_extractor `{storage_volume, volume_id}`,
        `viewer`-tier — INV-10 распространяется и на `ListOperations`)

---

# Стадия S2 — `DiskType` admin-каталог (public read + Internal admin CRUD :9091)

**DoD стадии:** proto (public `DiskTypeService.Get/List` + `InternalDiskTypeService.Create/Update/Delete`)
· миграция `disk_types` (slug PK, CHECK zone_ids array, seed) · repo · use-case (self-validating domain)
· integration-тесты (FK RESTRICT delete-in-use) · newman happy+negative (public read + admin CRUD через
internal-mux) · api-gateway: public read на public-mux, admin CRUD **только** на internal-mux (ban #6).

## Сценарий CS1-S2-01: `DiskType` — публичный read (Get/List, sync)

**ID:** CS1-S2-01

**Given** seed каталога: `block-standard`, `block-balanced`, `block-fast`, `block-single`, `block-io-max`

**When** клиент вызывает `DiskTypeService.List` (`GET /storage/v1/diskTypes`)
**Then** sync-ответ содержит ≥5 типов, каждый с `id` (slug), `name`, `description`, `zoneIds[]`,
        `performanceTier` (cursor-пагинация `(createdAt,id)`)

**When** клиент вызывает `DiskTypeService.Get(diskTypeId=block-balanced)`
**Then** sync `DiskType{ id:"block-balanced", performanceTier:"balanced", zoneIds:[] }`

**When** клиент вызывает `Get(diskTypeId=block-nope)`
**Then** `NOT_FOUND` `DiskType block-nope not found`

## Сценарий CS1-S2-02: `DiskType` — admin Create (Internal :9091, sync)

**ID:** CS1-S2-02

**Given** админ (`system_admin`) через internal-mux (:9091)

**When** админ вызывает `InternalDiskTypeService.Create` (`POST /storage/v1/diskTypes` на internal-mux)
        с `id=block-archive`, `name=block-archive`, `performanceTier=archive`, `zoneIds=["region-1-a"]`
**Then** **синхронный** ответ `DiskType` (не Operation — admin-справочник без LRO, INV-3 исключение)
**And** последующий публичный `Get(block-archive)` возвращает созданный тип

**When** админ вызывает `Create` с тем же `id=block-archive`
**Then** `ALREADY_EXISTS` `DiskType block-archive already exists` (`23505` PK-слаг)

**When** админ вызывает `Create` с пустым `id`
**Then** `INVALID_ARGUMENT` (`disk_type id is required` — self-validating domain до repo)

## Сценарий CS1-S2-03: `DiskType` — admin Update (Internal :9091, full-replace, БЕЗ FieldMask)

**ID:** CS1-S2-03

**Обоснование отклонения от update_mask-дисциплины (осознанное).** `UpdateDiskTypeRequest` в
коммитнутом `disk_type_service.proto` **не несёт `google.protobuf.FieldMask`** (в отличие от
`Volume`/`Snapshot` Update) — admin-каталог редактируется **full-replace** (PUT-семантика). Это тот
же паттерн, что у существующих admin-справочников Kachō (geo `Region`/`Zone`, vpc `AddressPool` —
Internal admin CRUD), и он зафиксирован в `project/kacho-storage/docs/architecture/overview.md`
§«Async vs sync». Следствие full-replace: **опущенные mutable-поля обнуляются** (тело — это полный
желаемый ресурс, не патч).

**Given** тип `block-archive` существует с `name=block-archive`, `description=cold tier`,
        `zoneIds=["region-1-a"]`, `performanceTier=archive`

**When** админ вызывает `InternalDiskTypeService.Update` (`PATCH /storage/v1/diskTypes/block-archive`)
        с телом `{name:"block-cold", zoneIds:["region-1-a","region-1-b"]}` (без `description`,
        без `performanceTier`)
**Then** sync `DiskType` с `name=block-cold`, `zoneIds=["region-1-a","region-1-b"]` (замещены целиком)
**And** **опущенные `description` и `performanceTier` обнулены до `""`** (full-replace, не патч —
        assert'ить пустоту явно) — `id` неизменен (immutable path-param)

**When** админ вызывает `Update` на несуществующем `diskTypeId=block-nope`
**Then** `NOT_FOUND` `DiskType block-nope not found` (0-row)

## Сценарий CS1-S2-04: `DiskType` — Internal-only (не на external) + per-RPC authz [INV-7]

**ID:** CS1-S2-04

**Given** развёрнутый api-gateway (external TLS + internal-mux)

**When** клиент обращается к admin `InternalDiskTypeService.Create/Update/Delete` через **external**
        endpoint
**Then** маршрут отсутствует (admin CRUD зарегистрирован **только** на internal-mux, ban #6) — метод
        не доступен на external поверхности

**When** caller без `system_admin`-права вызывает admin `Create` на internal-mux
**Then** `PERMISSION_DENIED` (per-RPC `InternalIAMService.Check`, `system_admin`-tier + `scope_extractor
        {cluster,*}` — «mTLS достаточно» запрещено, security.md)

## Сценарий CS1-S2-05: `DiskType.Delete` — FK RESTRICT со стороны `Volume`

**ID:** CS1-S2-05

**Given** тип `block-balanced`, на который ссылается хотя бы один `Volume` (`disk_type_id`)

**When** админ вызывает `InternalDiskTypeService.Delete(block-balanced)`
**Then** `FAILED_PRECONDITION` `DiskType block-balanced is in use` (FK `volumes.disk_type_id` RESTRICT
        `23503` — DB-enforced)

**When** все ссылающиеся тома удалены и админ повторяет `Delete`
**Then** sync ok (`DeleteDiskTypeResponse{}`); публичный `Get` → `NOT_FOUND`

---

# Стадия S3 — `Snapshot` lifecycle (from-READY-volume + CRUD + FK SET NULL)

**DoD стадии:** proto (`SnapshotService` CRUD) · миграция `snapshots` (partial UNIQUE name, FK SET NULL
обе стороны с `volumes`, CHECK) · repo (from-READY-CAS `INSERT…SELECT`, disambiguation) · use-case (LRO,
peer-validate project, immutable source_volume) · integration-тесты (from-non-READY, FK SET NULL) ·
**newman happy+negative + public-authz: `Snapshot.List` listauthz-filter (CS1-S3-07) и object-scoped
анти-BOLA `Get/Update/Delete` (CS1-S3-08) → `PERMISSION_DENIED`, behaviour-level (INV-10)** ·
vault (`resources/kacho-storage-snapshot.md`).

## Сценарий CS1-S3-01: `Snapshot.Create` — happy from-READY-volume (async → Operation)

**ID:** CS1-S3-01

**Given** том `vol-A` в `prj-1`, `status=AVAILABLE` (persisted `state=READY`), `sizeBytes=10 GiB`

**When** клиент вызывает `SnapshotService.Create` (`POST /storage/v1/snapshots`) с
        `projectId=prj-1`, `sourceVolumeId=vol-A`, `name=snap-01`
**Then** RPC возвращает `Operation` (`metadata.snapshotId` = `snp…`, `metadata.sourceVolumeId=vol-A`)
**And** Operation ok → `Snapshot{ id:"snp…", sourceVolumeId:"vol-A", sizeBytes=<vol-A.sizeBytes>
        (снят из тома на момент), status=READY, createdAt (усечён) }`
**And** `size_bytes` снапшота снят из `volumes` атомарным `INSERT…SELECT` (не из payload) — не TOCTOU

## Сценарий CS1-S3-02: `Snapshot.Create` — из не-READY / несуществующего тома

**ID:** CS1-S3-02

**Given** том `vol-B` в `state=CREATING` (или `DELETING`/`ERROR`)

**When** клиент вызывает `Snapshot.Create` с `sourceVolumeId=vol-B`
**Then** **Operation error** `FAILED_PRECONDITION` `Volume vol-B is not ready` (from-READY-CAS 0-row →
        том есть, но `state != READY`)

**When** клиент вызывает `Snapshot.Create` с несуществующим `sourceVolumeId=vol00000000000000000`
**Then** **Operation error** `FAILED_PRECONDITION` `Volume vol00000000000000000 not found`

## Сценарий CS1-S3-03: `Snapshot.Create` — peer-validate `projectId` + input-валидация (sync)

**ID:** CS1-S3-03

**When** клиент вызывает `Snapshot.Create` с `projectId=prj-nope` (нет в iam)
**Then** sync `FAILED_PRECONDITION` `Project prj-nope not found` (peer-validate request-path, fail-closed)

**When** kacho-iam недоступен
**Then** sync `UNAVAILABLE`

**When** клиент вызывает `Create` с `name=Bad_Name` (uppercase), либо над-длина (>63), либо
        **unicode/не-ASCII** (`name=снимок` — кириллица; тот же proto-pattern lowercase-ASCII)
**Then** sync `INVALID_ARGUMENT` `Illegal argument name` (для каждого входа — включая явно
        `name=снимок` → `Illegal argument name`)

## Сценарий CS1-S3-04: `Snapshot.Get`/`List` — malformed + NotFound + pagination

**ID:** CS1-S3-04

**When** клиент вызывает `Snapshot.Get(snapshotId=nope)`
**Then** sync `INVALID_ARGUMENT` `invalid snapshot id 'nope'`

**When** клиент вызывает `Get` на well-formed несуществующем `snp00000000000000000`
**Then** `NOT_FOUND` `Snapshot snp00000000000000000 not found`

**When** клиент вызывает `SnapshotService.List` (`GET /storage/v1/snapshots?projectId=prj-1&pageSize=2&filter=name=snap-01`)
**Then** sync-список, project-scoped, cursor `(createdAt,id)`, whitelist `name`; garbage `pageToken` → `INVALID_ARGUMENT`

## Сценарий CS1-S3-05: `Snapshot.Update` — mutable + immutable в mask (sync)

**ID:** CS1-S3-05

**Given** снапшот `snp-X`

**When** клиент вызывает `Update` с `updateMask=source_volume_id`
**Then** sync `INVALID_ARGUMENT` `source_volume_id is immutable after Snapshot.Create` (тот же результат
        для `project_id` / `size_bytes`)

**When** клиент вызывает `Update` с `updateMask=name,labels`, новыми значениями
**Then** Operation ok; `Get` показывает применённые `name`/`labels`
**And** конфликт `name` с другим снапшотом в проекте → **Operation error** `ALREADY_EXISTS`
        `snapshot with name <n> already exists in project`

**When** клиент вызывает `Update` на несуществующем well-formed `snapshotId`
**Then** **Operation error** `NOT_FOUND` `Snapshot <id> not found`

## Сценарий CS1-S3-06: `Snapshot.Delete` — FK SET NULL обе стороны (переживание)

**ID:** CS1-S3-06

**Given** снапшот `snp-X`, на который ссылается том `vol-Y` (`sourceSnapshotId=snp-X`)

**When** клиент вызывает `SnapshotService.Delete(snp-X)`
**Then** Operation ok, `result.response=Empty` (delete **не** блокируется — FK
        `volumes.source_snapshot_id` SET NULL, не RESTRICT)
**And** `Get(vol-Y)` возвращает том с `sourceSnapshotId=''` (обнулён, не dangling)

**When** обратная сторона: том `vol-A` — источник снапшота `snp-X`, том удаляют
**Then** `Volume.Delete(vol-A)` не блокируется снапшотом (FK `snapshots.source_volume_id` SET NULL);
        `Get(snp-X)` возвращает снапшот с `sourceVolumeId=''`

**When** клиент вызывает `Delete` на несуществующем well-formed `snapshotId`
**Then** **Operation error** `NOT_FOUND` `Snapshot <id> not found`

## Сценарий CS1-S3-07: публичный `Snapshot.List` — listauthz-filter (нет кросс-проектной утечки) [INV-10]

**ID:** CS1-S3-07

**Given** caller `alice` авторизована `viewer` на `prj-1`, но **не** на `prj-2`
**And** в `prj-1` есть снапшоты `snp-a1`,`snp-a2`; в `prj-2` — `snp-b1`

**When** `alice` вызывает публичный `SnapshotService.List` (`GET /storage/v1/snapshots?projectId=prj-1`)
**Then** sync-ответ содержит **только** `snp-a1`,`snp-a2` — `snp-b1` (`prj-2`) не появляется никогда
        (result отфильтрован listauthz; CI-гейт `make audit-list-filter`)

**When** `alice` вызывает `List` с `projectId=prj-2` (нет `viewer`)
**Then** sync `PERMISSION_DENIED` `permission denied` (scope_extractor `{project, project_id}`) —
        не пустой список, не утечка существования `prj-2` (assert код И фикс. текст)

## Сценарий CS1-S3-08: публичный `Snapshot.Get/Update/Delete` — object-scoped анти-BOLA [INV-10]

**ID:** CS1-S3-08

**Given** снапшот `snp-b1` принадлежит `prj-2`; caller `alice` имеет права только на `prj-1`

**When** `alice` вызывает `SnapshotService.Get(snp-b1)` (external :9090)
**Then** sync `PERMISSION_DENIED` `permission denied` (scope_extractor `{storage_snapshot,
        snapshot_id}`: Check против проекта **целевого** снапшота — анти-BOLA); существование
        `snp-b1` не раскрывается

**When** `alice` вызывает `SnapshotService.Update(snp-b1, …)` либо `Delete(snp-b1)`
**Then** sync `PERMISSION_DENIED` `permission denied` (тот же object-scoped gate, `editor`-tier) —
        мутация не доходит до `Operation`

**When** `alice` (с `editor` на `prj-1`) вызывает те же RPC на своём `snp-a1` (`prj-1`)
**Then** авторизация проходит (Get → `Snapshot`; Update/Delete → `Operation`)

---

# Стадия S4 — `VolumeAttachment` / `InternalVolumeService` attach-CAS (:9091, mTLS)

**DoD стадии:** proto (`InternalVolumeService.Attach/Detach/ListAttachments/GetInternal`, без public REST)
· миграция `volume_attachments` (PK volume_id + FK RESTRICT → volumes, UNIQUE(instance_id,device_name),
EXCLUDE one-boot, CHECK mode, self-describing zone/project в attach-CAS) · repo (атомарный
`INSERT … ON CONFLICT DO NOTHING` CAS + disambiguation с раздельными zone/project-текстами,
auto device_name retry-until-free) · use-case (malformed-id-first) · integration-тесты **с concurrent
goroutines** под `-race` — **два** race-класса: (a) double-attach одного тома разными инстансами →
ровно один (CS1-S4-10); (b) auto-device-name contended-allocation разных томов на один инстанс →
разные имена, `23505` ретраится и не вытекает (CS1-S4-08) — оба ban #12 · newman через compute-сагу
(или прямой internal-mux) · api-gateway: **только** internal-mux + per-RPC authz на обоих концах ·
vault (`edges/compute-to-storage-volume-attach.md`).

## Сценарий CS1-S4-01: `Attach` — happy CAS-insert, derived IN_USE, used_by

**ID:** CS1-S4-01

**Given** том `vol-A` в `prj-1`, зона `region-1-a`, `status=AVAILABLE`
**And** инстанс `ins-1` в том же проекте/зоне (self-describing placement из compute)

**When** compute вызывает `InternalVolumeService.Attach` (:9091) с payload:
  - `volumeId` = `vol-A`
  - `instanceId` = `ins-1`
  - `instanceName` = `web-1`
  - `instanceZoneId` = `region-1-a`
  - `projectId` = `prj-1`
  - `deviceName` = `sdb`
  - `isBoot` = `false`
  - `mode` = `READ_WRITE`

**Then** атомарный CAS-insert строки `volume_attachments` проходит; ответ `AttachVolumeResponse.volume`
        — `Volume` с `status=IN_USE` (derived), `attachments[0]` = `{instanceId:ins-1, instanceName:web-1,
        deviceName:sdb, mode:READ_WRITE, attachedAt (усечён)}`
**And** публичный `Volume.Get(vol-A)` показывает `status=IN_USE`, непустой `usedBy[]` (generic Reference)

## Сценарий CS1-S4-02: `Attach` — идемпотентный replay (тот же инстанс) → OK

**ID:** CS1-S4-02

**Given** `vol-A` уже привязан к `ins-1` (`sdb`)

**When** compute повторяет **тот же** `Attach` (`volumeId=vol-A`, `instanceId=ins-1`)
**Then** ok — идемпотентный replay: ровно одна строка `volume_attachments` (конфликт по PK `volume_id`
        → DO NOTHING → disambiguation видит owner=`ins-1` → OK); повторной вставки нет

## Сценарий CS1-S4-03: `Attach` — том уже занят ДРУГИМ инстансом (single-attach)

**ID:** CS1-S4-03

**Given** `vol-A` привязан к `ins-1`

**When** compute вызывает `Attach` с `volumeId=vol-A`, `instanceId=ins-2` (другой инстанс)
**Then** `FAILED_PRECONDITION` `Volume vol-A is in use` (PK `volume_id` → ≤1 attachment глобально;
        disambiguation: owner ≠ caller)
**And** это фиксирует **single-attach v1** — multi-attach = рост (§0.4)

## Сценарий CS1-S4-04: `Attach` — том не READY / не существует

**ID:** CS1-S4-04

**Given** том `vol-C` в `state=CREATING` (или `ERROR`)

**When** compute вызывает `Attach` с `volumeId=vol-C`
**Then** `FAILED_PRECONDITION` `Volume is not available for attachment` (CAS-предикат `v.state='READY'`
        не выполнен → 0-row → disambiguation: строки attachments нет, том не READY)

**When** compute вызывает `Attach` на несуществующем `volumeId=vol00000000000000000`
**Then** `FAILED_PRECONDITION` `Volume is not available for attachment` (тома нет в предикате CAS)

**When** compute вызывает `Attach` с malformed `volumeId=not-a-vol`
**Then** sync `INVALID_ARGUMENT` `invalid volume id 'not-a-vol'` (первым стейтментом, парити с Get)

## Сценарий CS1-S4-05: `Attach` — zone/project mismatch (placement-coherence в CAS) [INV-4]

**ID:** CS1-S4-05

Zone и project — **два разных** предиката в attach-CAS; каждая некогерентность несёт **свой**
нормативный текст (не переиспользуется zone-текст на project-mismatch — это исправление
относительно companion S2-04, см. §0.0). Какой предикат не сматчил — определяет disambiguation-SELECT
в той же TX после 0-row CAS.

**Given** том `vol-A` в зоне `region-1-a`, проект `prj-1`, `status=AVAILABLE`

**When** compute вызывает `Attach` с `instanceZoneId=region-1-b`, `projectId=prj-1` (расходится
        **только** зона)
**Then** `FAILED_PRECONDITION` `Volume and Instance must be in the same zone` (zone-предикат
        `v.zone_id = $instance_zone_id` не выполнен — **DB-уровень**, не software check-then-act)

**When** compute вызывает `Attach` с `instanceZoneId=region-1-a`, `projectId=prj-2` (расходится
        **только** проект)
**Then** `FAILED_PRECONDITION` `Volume and Instance must be in the same project` (project-предикат
        `v.project_id = $project_id` не выполнен — **отдельный** текст; assert **именно** этот текст,
        не zone-строку)

## Сценарий CS1-S4-06: `Attach` — коллизия `deviceName` в инстансе

**ID:** CS1-S4-06

**Given** инстанс `ins-1` с томом `vol-A` на `deviceName=sdb`

**When** compute вызывает `Attach` тома `vol-B` на `ins-1` с `deviceName=sdb` (то же имя устройства)
**Then** `FAILED_PRECONDITION` `device sdb is already in use on Instance ins-1` (`UNIQUE(instance_id,
        device_name)` `23505` — device-name уникально в пределах инстанса, не поглощается arbiter'ом
        PK `volume_id`)

## Сценарий CS1-S4-07: `Attach` — пустой `deviceName` → авто-назначение первого свободного имени

**ID:** CS1-S4-07

**Разрешение конфликта под конкуренцией (нормативно, data-integrity.md §5).** Auto-allocation имени
устройства — **contended-allocation путь** (первое-свободное `sdb..sdz` под конкурентными attach
**разных** томов на **один** инстанс). Механизм: repo вычисляет первое свободное имя из занятых для
`instance_id`, `INSERT` строки; при `23505` на `UNIQUE(instance_id, device_name)` (конкурент занял
это имя между выбором и вставкой) — **retry**: пересчитать следующее свободное имя и повторить
(bounded ≤25 попыток по числу имён `sdb..sdz`). Исход детерминирован: **retry-until-free**, `23505`
auto-пути **никогда** не всплывает наружу как ошибка (в отличие от явного `deviceName` в S4-06, где
коллизия — контрактный `FAILED_PRECONDITION`). Пространство исчерпано (все 25 заняты) →
`FAILED_PRECONDITION` `no free device name on Instance <id>`.

**Given** инстанс `ins-1` с томом `vol-A` на `sdb`

**When** compute вызывает `Attach` тома `vol-B` на `ins-1` с **пустым** `deviceName`
**Then** ok — auto-назначено первое свободное имя (`sdc`) из `sdb..sdz`; ответ показывает выделенный
        `deviceName=sdc`

## Сценарий CS1-S4-08: auto-device-name concurrency — два тома, один инстанс (race, ban #12)

**ID:** CS1-S4-08

**Given** инстанс `ins-1` с томом `vol-A` на `sdb`; два READY-тома `vol-B`, `vol-C` (та же зона/проект)

**When** два **конкурентных** `Attach{vol-B, ins-1}` и `Attach{vol-C, ins-1}`, оба с **пустым**
        `deviceName` (старт-гейт, не `time.Sleep`), integration-тест под `-race`
**Then** оба `done=ok`; тома получают **разные** имена (`sdc` и `sdd`) — lost-update нет,
        `UNIQUE(instance_id, device_name)` не даёт двум attach занять одно имя; проигравший `23505`
        **ретраит** до свободного (retry-until-free, S4-07), а не падает
**And** в БД — ровно две строки `volume_attachments` для `ins-1` (плюс исходная `vol-A`), все
        `device_name` различны; наружу `23505` не вытек

## Сценарий CS1-S4-09: `Attach` — второй boot-том на инстанс → EXCLUDE

**ID:** CS1-S4-09

**Given** инстанс `ins-1` с boot-томом `vol-boot` (`isBoot=true`)

**When** compute вызывает `Attach` тома `vol-boot2` на `ins-1` с `isBoot=true`
**Then** `FAILED_PRECONDITION` `Instance ins-1 already has a boot volume`
        (`EXCLUDE USING gist (instance_id WITH =) WHERE is_boot` `23P01` — ≤1 boot-том на инстанс)

**When** compute вызывает `Attach` data-тома (`isBoot=false`) на тот же `ins-1`
**Then** ok (EXCLUDE действует только на `is_boot=true`)

## Сценарий CS1-S4-10: double-attach race — ровно один побеждает (concurrency, ban #12)

**ID:** CS1-S4-10

**Given** том `vol-A`, `status=AVAILABLE`
**And** N (≥5) конкурентных `Attach` **разных** инстансов на `vol-A`, одинаковый `deviceName` (конфликт
        только по PK `volume_id`), стартующих одновременно (старт-гейт, не `time.Sleep`)

**When** все N `Attach` выполняются параллельно (integration-тест под `-race`)
**Then** **ровно один** проходит (ok, `status→IN_USE`); остальные получают `FAILED_PRECONDITION`
        `Volume vol-A is in use` (атомарный CAS + row-lock PK `volume_id` — не second-writer-wins)
**And** в БД — ровно одна строка `volume_attachments` для `vol-A`

## Сценарий CS1-S4-11: `Detach` — идемпотентный + Internal-only + authz [INV-7]

**ID:** CS1-S4-11

**Given** том `vol-A` привязан к `ins-1`

**When** compute вызывает `InternalVolumeService.Detach` (`volumeId=vol-A`, `instanceId=ins-1`)
**Then** ok — строка `volume_attachments` удалена; ответ `DetachVolumeResponse.volume` с
        `status=AVAILABLE` (derived: attachment нет)

**When** compute повторяет `Detach` (том уже отвязан)
**Then** ok — идемпотентно (0-row DELETE → OK, не ошибка)

**When** клиент обращается к `InternalVolumeService.Attach/Detach/ListAttachments` через **external**
        endpoint
**Then** маршрут отсутствует (Internal-only :9091, ban #6)

**When** caller без `editor`-права (мутации) / `viewer` (read) вызывает internal-RPC на :9091
**Then** `PERMISSION_DENIED` (per-RPC `InternalIAMService.Check` с `scope_extractor{storage_volume,
        volume_id}` для Attach/Detach; `{cluster,*}` `viewer` для ListAttachments — на **обоих**
        концах: gateway internal-mux + in-service interceptor)

## Сценарий CS1-S4-12: `ListAttachments` — батч (не N+1) + INTERNAL-leak guard

**ID:** CS1-S4-12

**Given** инстансы `ins-1` (тома `vol-A`,`vol-B`) и `ins-2` (том `vol-C`)

**When** compute вызывает `InternalVolumeService.ListAttachments` с `instanceIds=[ins-1, ins-2]`
**Then** один запрос возвращает плоский список из 3 `VolumeAttachmentInfo`, каждый несёт `volumeId` +
        `instanceId` (группируется вызывающим); нет N+1
**And** пустой `instanceIds` → пустой список (не ошибка)

**When** внутри repo возникает некатегоризированная pgx/SQL-ошибка на любом storage-RPC
**Then** наружу отдаётся `INTERNAL` `internal error` — **никогда** сырой pgx/driver/connection-текст
        (INV-8; assert на **сообщение**, не только код)

---

## Общий DoD инкремента CS-1 (приёмочный чеклист)

**Контракт / proto:**
- [ ] `storage/v1` proto: `Volume`/`Snapshot` flat + `Operation`-мутации; `DiskType` public read +
      `InternalDiskTypeService` admin CRUD (sync); `InternalVolumeService` Attach/Detach/ListAttachments
      (+ `GetInternal` анкер). `buf lint`/`buf breaking`/`buf validate` зелёные.
- [ ] REST-пути camelCase; suffix-actions отсутствуют (стандартные методы); public на public-mux,
      Internal — **только** internal-mux (api-gateway audit, ban #6).

**Данные / инварианты (INV-2, DB-уровень):**
- [ ] `volumes`: PK, FK `disk_type_id` RESTRICT, FK `source_snapshot_id` SET NULL, partial
      `UNIQUE(project_id,name) WHERE name<>''`, CHECK `size_bytes>0`/`block_size>0`, размер increase-only CAS.
- [ ] `volume_attachments`: PK `volume_id` + FK RESTRICT → volumes, `UNIQUE(instance_id,device_name)`,
      `EXCLUDE (instance_id WITH =) WHERE is_boot`, CHECK `mode`, self-describing zone/project в attach-CAS.
- [ ] `snapshots`: partial UNIQUE name, FK `source_volume_id` SET NULL (циклический ALTER с volumes),
      from-READY-CAS `INSERT…SELECT`. `disk_types`: slug PK, CHECK zone_ids array, seed 5 tier'ов.
- [ ] Derived status (INV-5): `AVAILABLE`/`IN_USE` из LEFT JOIN `volume_attachments`, не колонка.

**Поведение / async (INV-3):**
- [ ] `Volume`/`Snapshot` `Create`/`Update`/`Delete` → `Operation` (poll `OperationService.Get`);
      `DiskType` admin CRUD — sync (осознанное исключение, задокументировано).
- [ ] update_mask discipline (immutable-switch **до** UpdateMask; пустой mask = full-PATCH).
- [ ] malformed-id первым стейтментом; peer-validate zone→geo / project→iam fail-closed (`UNAVAILABLE`);
      per-call deadline на каждом peer-вызове.

**Безопасность (INV-6, INV-7, INV-10):**
- [ ] Lean public projection (публичный `Volume` без инфра-полей; attachment без project/zone).
- [ ] `GetInternal` — только :9091, инфра-поля reserved (out-of-scope §0.4, `UNIMPLEMENTED`).
- [ ] per-RPC `InternalIAMService.Check` активен на **обоих** листенерах fail-closed (не dev-passthrough);
      mTLS на :9091; object-scoped `scope_extractor` на attach-мутациях (анти-BOLA).
- [ ] **Public-surface authz (INV-10):** `Volume.List`/`Snapshot.List` listauthz-filtered
      (`make audit-list-filter`, кросс-проектной утечки нет — CS1-S1-13/CS1-S3-07); object-scoped
      анти-BOLA на public `Volume.Get/Update/Delete/ListOperations` и `Snapshot.Get/Update/Delete`
      (scope против **целевого** объекта → `PERMISSION_DENIED`, existence-non-revealing —
      CS1-S1-14/15, CS1-S3-08). Assert **behaviour-level** (код + фикс. `permission denied`).

**Тесты (ban #12, testing.md — RED до кода):**
- [ ] Integration (testcontainers Postgres): CRUD, FK RESTRICT/SET NULL, размер-CAS 0-row disambiguation,
      from-READY-CAS, **concurrent double-attach race** под `-race` (CS1-S4-10), **concurrent
      auto-device-name allocation** под `-race` (CS1-S4-08 — разные имена, `23505` не вытекает,
      retry-until-free), device/boot конфликты, zone-**и** project-mismatch раздельными текстами (CS1-S4-05).
- [ ] Newman: ≥1 happy + ≥1 negative на каждый ресурс (Volume/DiskType/Snapshot) + attach-путь;
      error-тексты (§0.2) assert'ятся **behaviour-level** (код И сообщение). Newman-provokable
      negatives (через public API): malformed-id, well-formed-not-found, size-shrink-reject,
      duplicate-name `ALREADY_EXISTS`, unknown-zone/project peer-validate, `PERMISSION_DENIED`
      (listauthz/анти-BOLA CS1-S1-13/14, CS1-S3-07/08). **Caveat (не over-claim):** негативы на
      **не-READY** Given-состояние тома (CS1-S4-04 attach-not-ready, CS1-S3-02 snapshot-not-ready)
      **не** воспроизводимы black-box через public API — control-plane `Create` финализирует в READY
      мгновенно (§0.1), не-READY достижимо **только** прямым DB-seed → эти пути покрываются
      **integration-тестом** (testcontainers), не newman-e2e; DoD «≥1 newman negative на ресурс»
      закрывается другими (перечисленными) newman-provokable негативами.
- [ ] INTERNAL-leak regression: `Message() == "internal error"` (INV-8).

**Trail / финализация:**
- [ ] vault: `resources/kacho-storage-{volume,snapshot,disktype}.md`, `rpc/kacho-storage-*.md`,
      `edges/storage-to-{geo,iam}-*.md`, `edges/compute-to-storage-volume-attach.md`; рёбра `storage→geo`/
      `storage→iam` в `polyrepo.md` (one-way, ацикличность INV-1).
- [ ] `go test ./... -race` + `golangci-lint run` + `govulncheck` + `make audit-list-filter` + newman зелёные.

---

## Изменения раунда 2 (адресация CHANGES REQUESTED раунда 1)

- **[CRITICAL — SECURITY/COVERAGE] Public-surface authz — добавлено.** Новый инвариант **INV-10**
  + сценарии: **listauthz-filter** public `Volume.List`/`Snapshot.List` (caller на `prj-1` не видит
  `prj-2`) — **CS1-S1-13**, **CS1-S3-07**; **object-scoped анти-BOLA** public
  `Volume.Get/Update/Delete` (scope `{storage_volume,volume_id}`) и `Snapshot.Get/Update/Delete`
  (scope `{storage_snapshot,snapshot_id}`) → `PERMISSION_DENIED`, existence-non-revealing —
  **CS1-S1-14**, **CS1-S3-08**. Assert behaviour-level (код + фикс. `permission denied`). Добавлены:
  error-row §0.2, traceability §0.5, DoD (S1/S3 + security-чеклист), §0.6.
- **[CRITICAL — GOVERNANCE] Companion contract-note исполнен, эпик привязан к реальному номеру.**
  Эпик → **`kacho-workspace#132`** ([EPIC] Storage-Compute IaaS) в шапке. Companion-док
  **амендирован механически** (не отложен на unbound-тикет): §0.1 и Q1 `dtp`→slug; error-таблица + S2-04
  zone/project-текст **разделён на два** (`…same zone` / `…same project`). CS-1 §0.0/§0.0.1 отражают
  discharge как исполненный.
- **[MINOR] `Volume.ListOperations`** — выделенный сценарий **CS1-S1-15** (happy + malformed-id +
  authz), RPC из коммитнутого proto.
- **[MINOR] Unicode-в-`name`** — явный пример: `name=том` / `name=снимок` → sync
  `Illegal argument name` (**CS1-S1-12**, **CS1-S3-03**).
- **[NOTE] Не-READY негативы (CS1-S4-04, CS1-S3-02)** — помечены в DoD как **integration-only**
  (достижимы лишь DB-seed, не black-box через public API); «≥1 newman negative на ресурс»
  закрывается другими newman-provokable негативами — over-claim снят.

## Вердикт acceptance-reviewer

_(заполняется `acceptance-reviewer`: `✅ APPROVED` / `❌ CHANGES REQUESTED` — статус дока → APPROVED
только после этого; кодинг-гейт lifecycle #1 до APPROVED закрыт.)_
