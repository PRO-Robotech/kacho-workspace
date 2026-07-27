## kacho-storage — блочное хранение (Volume / Snapshot / Image / DiskType)

> Один продукт Kachō, форма якорится на compute-эталоне: flat-ресурс без envelope, `Get`/`List` sync, мутации → `Operation`, two-projection (public lean / `Internal*` :9091), единый тон ошибок, reference-law по классу ссылки. Домен `kacho.cloud.storage.v1`, схема `kacho_storage`, id-префиксы `vol`/`snp`/`img`, op-root `sop`. Рёбра наружу — **только исходящие**: `storage → geo` (существование зоны/региона + резолв «зона → её регион») и `storage → iam` (существование проекта, per-RPC Check, регистрация owner-tuple). Ни одного вызова в compute — **ацикличность держится by construction** (в `services/storage` ноль Go-импортов `computev1`).
>
> **Чем этот документ отличается от соседей по папке.** Соседние `module-*.md` описывают целевую форму. Здесь — **описание того, что реально стоит в коде** ветки `redesign/integration` (снимок пинится коммитом `5c53ad9`, 2026-07-27 — документ описывает дерево на этом коммите и ни на каком другом), выведенное из `services/storage` (миграции, домен, use-case, repo, clients, handler, composition root) и из protobuf-контракта `proto/kacho/cloud/storage/v1`. Всё, чего в коде нет, вынесено в раздел **«Осознанно не сделано»** и **не** переписано в будущее время. Разделы «Решения и обоснование», «Given-When-Then», «Негативы и граничные значения», «DoD» и «Out-of-scope» добавлены сверх формы соседей — они несут ту же информацию, что и их разделы «Правила», но в проверяемом виде.

Легенда: `°` — **output-only** (сервер выставляет, на write игнорируется). Все JSON — camelCase через REST-шлюз. Cross-service ссылки (`projectId`, `zoneId`, `regionId`, `instanceId`) — TEXT **без FK**, валидируются peer-API владельца; within-service ссылки (`diskTypeId`, `sourceSnapshotId`, `sourceImageId`, `sourceVolumeId`, `volumeId` в привязке) — **настоящие FK** в одной БД.

---

## Цель домена и его граница

**Что storage обязан гарантировать.** Быть **единственным владельцем** блочного состояния: том существует, имеет размер и тип, лежит в зоне, может быть снят в снимок, может засеваться из снимка или образа и может быть **примонтирован ровно к одной машине**. Все инварианты этого списка — реляционные («том привязан не более чем один раз», «пока привязан — не удаляется», «имя устройства в машине уникально», «загрузочный том в машине один»), поэтому все они выражены **конструкциями Postgres в БД владельца**, а не проверками в коде потребителя.

**Чего storage не делает вовсе (граница).** Он не размещает данные на железе, не програмирует LUN/NVMe-namespace, не знает про хосты и пулы. Публичная поверхность несёт **намерение и результат** (`id`, `name`, `labels`, привязка к проекту/зоне/типу, размер, статус); физика зарезервирована в `Internal*`-проекциях и в этом инкременте **не заполняется** (см. «Осознанно не сделано»). Он также **не принимает решения о доступе** — решение принимает модель прав в iam, storage лишь спрашивает (`Check` на каждом RPC, `BatchCheck` на странице списка) и **кормит** её owner-tuple'ами через очередь регистраций.

---

## Ментальная модель

Пять опор, у каждой ровно один источник истины.

1. **Volume — зональная единица блочного состояния и единственный носитель размера.** Строка `kacho_storage.volumes` — истина «этот том есть, столько байт, в этой зоне, такого типа». Зона (`zoneId`) — **immutable** якорь размещения, проверяемый у владельца Geography. Размер — **increase-only** и меняется атомарным CAS, а не «прочитал → сравнил → записал».

2. **Привязка — отдельная строка у владельца тома, а не поле у потребителя.** `kacho_storage.volume_attachments` — **источник истины** факта «том смонтирован к машине». Её первичный ключ — сам `volume_id`, поэтому «не более одной привязки на том» держится **глобально и by construction**, а не рефкаунтом. `instanceId` — ссылка через границу сервиса (TEXT, без FK): storage владеет привязкой, но **не** владеет машиной.

3. **Статус тома — производная, а не колонка.** В БД живёт `state` (жизненный цикл), а `AVAILABLE`/`IN_USE` **вычисляются на чтении** из наличия строки привязки (`DeriveStatus`). Поэтому статус физически не может разойтись с привязкой: расходиться нечему — второй записи о том же факте не существует.

4. **Image — региональный (anycast) посевной материал, Volume — зональный потребитель.** У образа нет зоны вовсе (`placementType` всегда `REGIONAL`), поэтому зональное сравнение к нему **неприменимо by construction** — остаётся региональное: зона тома обязана принадлежать региону образа. Регион зоны **всегда резолвится у geo** и никогда не выводится разбором имени.

5. **Права материализуются очередью, а не синхронной записью в модель.** Создание/переименование-меток/удаление ресурса пишут **намерение** (`fga_register_outbox`) в **той же транзакции**, что и сам ресурс — один commit, без dual-write. Применяет намерение отдельный дренаж через iam (`RegisterResource`/`UnregisterResource`), плюс синхронный регистратор сразу после коммита как оптимизация окна. `Operation.done` **не** ждёт видимости права (ban #9).

> **Сквозные механики, которые нужно держать в голове одновременно с ресурсами:** derive-on-read статуса и `usedBy°` · атомарный CAS вместо check-then-act на **каждом** спорном пути (attach, size, посев из источника) · project-когерентность источника **внутри того же INSERT** · hide-existence (отказ по чужому ресурсу байт-в-байт равен настоящему промаху) · two-projection (public vs `Internal*`) · страничная проверка видимости списка (`BatchCheck`, не «перечисли вселенную») · очередь регистраций с per-resource FIFO на уровне claim'а · production boot-guard, отказывающийся стартовать на небезопасной конфигурации.

---

## Volume

ID prefix `vol` · таблица `kacho_storage.volumes` · REST `/storage/v1/volumes` · зональный.

```jsonc
{
  "id": "vol7k2m4x9q1n8t3r5",          // ° prefix vol + crockford-base32
  "projectId": "prjb3n7k1x9q2m5t8",    // scope-координата → iam.ProjectService.Get (peer, fail-closed); immutable
  "createdAt": "2026-07-20T08:14:22Z", // ° truncate → секунды
  "updatedAt": "2026-07-20T09:02:11Z", // ° truncate → секунды
  "name": "app-data",                   // partial UNIQUE(projectId,name) при непустом; пустое имя легально
  "description": "primary data volume",  // ≤256
  "labels": { "team": "platform" },     // ≤64 ключей; смена меток ПЕРЕЭМИТИТ зеркало прав (см. «Материализация прав»)
  "zoneId": "ru-central1-a",            // → geo.ZoneService.Get (peer, fail-closed); IMMUTABLE
  "diskTypeId": "block-balanced",       // within-service FK → disk_types(id) ON DELETE RESTRICT; IMMUTABLE
  "sizeBytes": 107374182400,             // >0; Update — ТОЛЬКО увеличение (атомарный CAS)
  "blockSize": 4096,                     // default 4096; IMMUTABLE
  "sourceSnapshotId": "",                // within-service FK → snapshots ON DELETE SET NULL (происхождение); IMMUTABLE
  "sourceImageId": "img3k7m2q9x4n1t8",  // within-service FK → images ON DELETE SET NULL (происхождение); IMMUTABLE
                                         //   взаимоисключение с sourceSnapshotId — том засевается из ОДНОГО источника
  "status": "IN_USE",                   // ° DERIVED: READY+привязка → IN_USE, READY без привязки → AVAILABLE
  "attachments": [ /* см. ниже */ ],    // ° derive-on-read из volume_attachments (0..1 — PK volume_id)
  "usedBy": [                            // ° обобщённая проекция attachments для единообразного анализа зависимостей
    { "referrer": { "type": "compute.instance", "id": "ins-...", "name": "web-01" },
      "type": "USED_BY", "owned": false }
  ]
  // инфра (LUN / namespace / storage-node / pool / ёмкость) — НЕ здесь. Только Internal* :9091 (и там зарезервировано).
}
```

- **`status` не хранится.** В БД есть `state ∈ {CREATING, READY, DELETING, ERROR}` (CHECK); `AVAILABLE`/`IN_USE` — чистая функция `(state, есть ли привязка)`. Это фиксация решения «не заводить вторую запись одного факта»: колонка-статус и таблица-привязка неизбежно разъезжаются, производная — нет.
- **Размер меняется одним стейтментом.** `UPDATE … WHERE id=$1 AND ($5::bigint IS NULL OR $5 > size_bytes)`. Ноль строк дизамбигуируется **в той же транзакции**: строка есть ⇒ CAS отверг ⇒ `INVALID_ARGUMENT "Volume size can only be increased"`; строки нет ⇒ `NOT_FOUND "Volume <id> not found"`. Равный размер — тоже отказ (строгое `>`).
- **Пустая маска = full-object PATCH**, но `sizeBytes = 0` при пустой маске **не** трактуется как «уменьшить до нуля» — поле просто не участвует.
- **Immutable-набор** (отвергается **до** проверки маски, конвенционным текстом `"<field> is immutable after Volume.Create"`): `zone_id`, `disk_type_id`, `block_size`, `source_snapshot_id`, `source_image_id`, `used_by`, `attachments`. Mutable-набор маски: `name`, `description`, `labels`, `size_bytes`.
- **Удаление привязанного тома не проходит** — FK `volume_attachments.volume_id → volumes(id) ON DELETE RESTRICT` → 23503 → `FAILED_PRECONDITION "Volume <id> is in use"`. Это не программная проверка «а вдруг привязан», а невозможность удалить строку, на которую ссылаются.
- **Список фильтруется по `name=`** (whitelist corelib-парсера — `filter.Parse(p.Filter, []string{"name"})`, `internal/service/volume/volume.go:212`). Поле `orderBy` объявлено во **всех трёх** List-запросах (`volume_service.proto:152`, `snapshot_service.proto:133`, `image_service.proto:153`) и сервисом **не читается вовсе** (`grep -rn OrderBy services/storage --include=*.go` — пусто), а объявленное рядом умолчание — «`"id asc"` if omitted» — **не совпадает** с фактическим порядком `created_at ASC, id ASC` (`volume_repo.go:148`, `snapshot_repo.go:103`, `image_repo.go:107`). Это **два** расхождения контракта, а не одно: поле принимается и молча игнорируется, и документированное умолчание неверно. **Исход — задача #81 (а)**, критерий приёмки — в «Незакрытое», п. 9.

### VolumeAttachment — источник истины привязки

Дочерняя запись тома; на публичной проекции она вложена в `Volume.attachments` и **не несёт** `projectId`/`zoneId` (они существуют в строке БД и приезжают только внутренним attach-payload'ом).

```jsonc
{
  "instanceId": "ins-9k2m4x7n1p8q3r5t", // cross-service, БЕЗ FK (владелец Instance — compute)
  "instanceName": "web-01",              // ° снимок имени НА МОМЕНТ привязки; storage никогда не перечитывает его у compute
  "deviceName": "sdb",                   // UNIQUE в пределах инстанса; пустой на входе → авто-назначение sdb..sdz
  "isBoot": false,                       // ≤1 boot-привязка на инстанс (EXCLUDE)
  "mode": "READ_WRITE",                  // READ_WRITE | READ_ONLY (CHECK)
  "autoDelete": false,                   // проецируется в usedBy[].owned
  "attachedAt": "2026-07-20T09:02:11Z"   // ° truncate → секунды (усечение действует и на под-запись)
}
```

---

## Snapshot

ID prefix `snp` · таблица `kacho_storage.snapshots` · REST `/storage/v1/snapshots` · без собственного размещения (наследует его от источника фактически, но полем не несёт).

```jsonc
{
  "id": "snp4t8n2q0m5v9h1k3",
  "projectId": "prjb3n7k1x9q2m5t8",     // → iam (peer, fail-closed); immutable
  "createdAt": "2026-07-20T08:20:00Z",  // ° truncate → секунды
  "name": "app-data-2026-07-20",         // partial UNIQUE(projectId,name) при непустом
  "description": "",                     // ≤256
  "labels": {},                          // смена меток переэмитит зеркало прав
  "sourceVolumeId": "vol7k2m4x9q1n8t3r5", // within-service FK → volumes ON DELETE SET NULL; IMMUTABLE; ОБЯЗАТЕЛЕН на Create
  "sizeBytes": 107374182400,             // ° снимается с исходного тома В ТОМ ЖЕ INSERT
  "status": "READY"                      // ° 1:1 из state (у снимка нет производных состояний)
}
```

- **Создание — атомарная «вставка-если-можно»**: `INSERT … SELECT … FROM volumes v WHERE v.id=$6 AND v.project_id=$2 AND v.state='READY'`. Никакого «прочитал том → проверил → вставил»: том мог смениться между чтением и записью.
- **Project-предикат обязателен, и это не косметика.** Без него можно было бы снять снимок с **чужого приватного тома** и вычитать его содержимое. Ноль строк дизамбигуируется **тоже project-scoped**: том не резолвится в проекте → `FAILED_PRECONDITION "Volume <id> not found"`; свой, но не READY → `"Volume <id> is not ready"`. Неограниченный резолв выдавал бы на чужой не-READY том отличимый текст — это был бы оракул существования/состояния.
- **Снимок переживает свой том**: FK `SET NULL`, поэтому удаление тома не блокируется снимком и не удаляет снимок — обнуляется происхождение.
- Immutable-набор: `source_volume_id`, `project_id`, `size_bytes`. Mutable: `name`, `description`, `labels`.
- **У Snapshot нет `ListOperations`**, хотя у Volume (`volume_service.proto:107`) и Image (`image_service.proto:108`) есть — асимметрия публичного контракта между тремя ресурсами одного домена. **Заведённой задачи под неё нет; требуется отдельная** — критерий в «Незакрытое», п. 12.

---

## Image

ID prefix `img` · таблица `kacho_storage.images` · REST `/storage/v1/images` · **REGIONAL (anycast)**.

```jsonc
{
  "id": "img3k7m2q9x4n1t8v6",
  "projectId": "prjb3n7k1x9q2m5t8",     // → iam (peer, fail-closed); immutable
  "createdAt": "2026-07-20T08:30:00Z",  // ° truncate → секунды
  "updatedAt": "2026-07-20T08:30:00Z",  // °
  "name": "base-linux",                  // partial UNIQUE(projectId,name) при непустом
  "description": "",                     // ≤256
  "labels": {},
  "regionId": "ru-central1",             // → geo.RegionService.Get (peer, fail-closed); IMMUTABLE; ЗОНЫ У ОБРАЗА НЕТ
  "placementType": "REGIONAL",           // ° константа домена (единственное значение enum кроме UNSPECIFIED)
  "sourceSnapshotId": "snp4t8n2q0m5v9h1k3", // FK → snapshots ON DELETE SET NULL; IMMUTABLE
  "sourceVolumeId": "",                  // FK → volumes ON DELETE SET NULL; IMMUTABLE; взаимоисключение со снимком
  "sizeBytes": 107374182400,             // ° снимается с источника В ТОМ ЖЕ INSERT
  "minDiskBytes": 107374182400,          // ° минимальный размер принимающего тома; ГРАНИЦА ВКЛЮЧИТЕЛЬНА
  "format": "STANDARD",                  // ° собственный single-tier формат Kachō (CHECK IN ('STANDARD'))
  "status": "READY"                      // ° 1:1 из state
}
```

- **Ровно один источник — на входе, «не более одного» — в БД.** «Ровно один» энфорсится доменом синхронно (`Image source is required` / `an image source must be either a snapshot or a volume, not both`), а DB-CHECK ловит только «оба непусты». Это **согласованная пара**, а не небрежность: FK происхождения — `SET NULL`, и «ровно один» в CHECK ронял бы 23514 **при удалении источника**. Образ обязан переживать источник (блочные данные уже материализованы), поэтому DB-инвариант ослаблен ровно до того, что `SET NULL` нарушить не может.
- **Удаление образа, из которого засеян том, проходит** — `volumes.source_image_id` `SET NULL`: у тома очищается происхождение, данные целы. Контраст с привязкой (`RESTRICT`) намеренный: привязка — живая зависимость, происхождение — историческая.
- Immutable-набор: `region_id`, `source_snapshot_id`, `source_volume_id`, `format`, `placement_type`, `size_bytes`, `min_disk_bytes`. Mutable: `name`, `description`, `labels`.

---

## DiskType

Slug-PK каталог · таблица `kacho_storage.disk_types` · публичный read `/storage/v1/diskTypes` + admin-CRUD на `InternalDiskTypeService` (:9091) — **на внешнем слушателе admin-CRUD недостижим; механизм, которым это держится, — в «Поверхность admin-CRUD каталога» ниже**.

```jsonc
{
  "id": "block-balanced",                // slug, назначает администратор; PK; immutable
  "name": "block-balanced",
  "description": "Balanced general-purpose durable volume",  // ≤256
  "zoneIds": [],                          // объявленные зоны доступности; [] = без ограничения
  "performanceTier": "balanced"          // собственный класс Kachō
}
```

- Посев (миграция 0004, идемпотентный): `block-standard`, `block-balanced`, `block-fast`, `block-single`, `block-io-max`.
- **Admin-CRUD синхронен** и возвращает ресурс, а не `Operation` — осознанное отступление от «мутация → Operation» для cluster-scoped справочника без саги (то же решение, что у `InternalRegion/ZoneService` в geo). Обновление — **full-replace** (в контракте нет `FieldMask`).
- **Тип с томами не удаляется** — FK `volumes.disk_type_id RESTRICT` → `FAILED_PRECONDITION "DiskType <id> is in use"`.
- **`zoneIds` ничего не ограничивает — это описательное поле, а не инвариант.** Список хранится (`disk_types.zone_ids` jsonb, CHECK «массив»), пишется admin-CRUD'ом и отдаётся в каталоге, но `Volume.Create` его **не читает**: единственные потребители `ZoneIDs` во всём сервисе — CRUD самого каталога и его чтение (`handler/internal.go:137,151`, `repo/pg/disk_type_repo.go`, `protoconv.go:158`), в ветке создания тома обращения нет ни одного. Том типа с непустым списком зон создаётся в **любой** зоне; расхождение не ловится ничем, потому что посев объявляет `[]` («без ограничения») и невыполнимый случай на стенде не возникает. **Исход — задача #81 (б)**, критерий приёмки — в «Незакрытое», п. 10.
- Каталог **не проходит** через пофайловый фильтр видимости: это ambient cluster-scoped чтение (`viewer` на кластерном синглтоне), per-object грантов у него нет.

#### Поверхность admin-CRUD каталога — изоляция по паре (метод, путь)

Три admin-RPC каталога (`InternalDiskTypeService.Create/Update/Delete`) объявлены cluster-internal, и **на уровне маршрутизации это теперь подтверждается**: на внешнем слушателе все три дают `404` **до** обработчика. Прежняя редакция этого документа описывала обратное — и была права на своём коммите; расхождение закрыто (`c58fd3d`), поэтому здесь описан действующий механизм, а не прошлое состояние.

**Почему классификация по одной строке пути здесь не работает by construction.** Admin-CRUD каталога делит REST-путь с **публичным** чтением (`GET /storage/v1/diskTypes[/{id}]` — `DiskTypeService`) и отличается от него **только HTTP-методом**. Классификатор, читающий лишь путь, эти биндинги различить не может в принципе: он либо уводит admin-мутации на публичный mux, либо закрывает вместе с ними публичное чтение. Происходило первое.

**Что стоит сейчас — три звена.**

| Звено | Где | Что делает |
|---|---|---|
| Решение по **паре** `(метод, путь)` | `isInternalRoute` (`gateway/internal/restmux/mux.go:214-215`) | `isInternalPath(path) \|\| matchesInternalRESTBinding(method, path)`. Path-shaped правила не заменены — остаются **вторым** слоем (`isInternalPath`, `mux.go:228`, включая `allowlist.HasInternalSuffix` на `:268`) |
| Таблица **выводится из proto-дескрипторов** | `buildInternalRoutes` (`gateway/internal/restmux/internal_routes.go:76-106`); матч — `matchesInternalRESTBinding` (`:182`) | обход `protoregistry.GlobalFiles` по пакетам `kacho.*`, отбор сервисов предикатом `isInternalServiceName` (`:67`), чтение `google.api.http` **включая `additional_bindings`**. Ручного списка форм пути больше нет — дрейфовать от proto нечему |
| Отказ стартовать на пустой таблице | `NewMux` (`gateway/internal/restmux/mux.go:329-330`) | `internal REST route table is empty: Internal*Service descriptors not linked — refusing to serve without external-listener isolation`. Пустая таблица означала бы «обслуживаем без изоляции» — процесс не поднимается вовсе |

Внешний запрос, классифицированный как internal, получает `404` **до** обработчика (`http.NotFound`, `mux.go:804`; ветка `listenerorigin.IsExternal` — `:803`), то есть existence-hiding, а не отказ по правам.

**Залочено четырьмя тестами** (`gateway/internal/restmux/internal_catalog_isolation_test.go`), и замок утверждает **обе** стороны размена, а не только запрет:

- `TestExternalListener_RejectsDiskTypeAdminRoutes` (`:60`) — строгий `404` для **всех шести** маршрутов **двух** доменов: `POST /storage/v1/diskTypes`, `PATCH`/`DELETE /storage/v1/diskTypes/{id}` и те же три на `/compute/v1/diskTypes` (у compute сервис называется так же — `InternalDiskTypeService`, `proto/kacho/cloud/compute/v1/internal_catalog_service.proto:33`). До фикса все шесть доходили до обработчика;
- `TestInternalListener_ServesDiskTypeAdminRoutes` (`:84`) — на внутреннем слушателе те же шесть по-прежнему обслуживаются;
- `TestExternalListener_DiskTypePublicReadsStillServed` (`:110`) — **публичное чтение на тех же путях не задето**: правка обязана сужать, а не расширять. Без этого утверждения «починка» могла бы закрыть каталог целиком и осталась бы зелёной;
- `TestAllInternalRESTBindings_ClassifiedInternal` (`:140`) — **гейт дрейфа**: обходит REST-биндинги **каждого** `Internal*`-сервиса **каждого** домена и падает, если роутер счёл хоть один публичным. Обход в тесте — независимая реализация, а не вызов `buildInternalRoutes`, поэтому гейт проверяет роутер, а не сам себя; на пустом списке он падает явно (`no Internal*Service REST bindings discovered — descriptor walk broken, gate would be vacuous`), а не проходит вакуумно.

**Комментарии в обоих контрактах теперь описывают механизм, а не намерение** (`proto/kacho/cloud/storage/v1/disk_type_service.proto:49-59`, `proto/kacho/cloud/compute/v1/internal_catalog_service.proto:19-27`): что изоляция keyed на пару (метод, путь), что источник истины — дескрипторы, и что новый RPC этих сервисов изолируется автоматически. Прежде комментарий утверждал изоляцию, которой не было.

**Что осталось на чёрном ящике.** Newman-кейсы `DT-CR-NEG-EXTERNAL-ABSENT` / `DT-UPD-NEG-EXTERNAL-ABSENT` / `DT-DEL-NEG-EXTERNAL-ABSENT` (`services/storage/tests/newman/cases/disk-type.py:85-126`) этим коммитом **не тронуты**: они всё ещё принимают `oneOf([400,403,404,405,501])` и несут комментарий про «на external он ДОСТИЖИМ», который больше не описывает код. Ужесточение — в сценарии CS1-S2-04 ниже.

---

## Жизненный цикл и переходы состояний

**Что объявлено.** Колонка `state` у `volumes`/`snapshots`/`images` ограничена CHECK'ом `IN ('CREATING','READY','DELETING','ERROR')`; wire-enum'ы несут те же значения (плюс `AVAILABLE`/`IN_USE` у тома как производные).

**Что реально происходит.** В этом инкременте **записывается только `READY`**: каждый INSERT перечисляет колонку `state` явно и подставляет литерал `'READY'` (дефолт `'CREATING'` в определении таблицы поэтому недостижим), а удаление — жёсткий `DELETE` строки, не перевод в `DELETING`. Значит:

| Ресурс | Реально наблюдаемые состояния | Объявленные, но не производимые |
|---|---|---|
| Volume | `AVAILABLE` ⇄ `IN_USE` (производные от привязки) | `CREATING`, `DELETING`, `ERROR` |
| Snapshot | `READY` | `CREATING`, `DELETING`, `ERROR` |
| Image | `READY` | `CREATING`, `DELETING`, `ERROR` |

Причина одна и та же: **data-plane отсутствует**, поэтому нет фазы, в которой ресурс «создаётся» дольше одной транзакции. Это не заглушка ради зелёного теста, а следствие границы домена — но и не право утверждать, будто машина состояний работает. Единственные наблюдаемые переходы сегодня:

```
Volume.Create ──commit──> AVAILABLE ──Attach(CAS)──> IN_USE ──Detach──> AVAILABLE ──Delete──> (строки нет)
                                              ↑ Delete здесь FAILED_PRECONDITION (FK RESTRICT)
Snapshot.Create ──commit──> READY ──Delete──> (строки нет)
Image.Create   ──commit──> READY ──Delete──> (строки нет; у засеянных томов обнуляется происхождение)
```

Асинхронность при этом **настоящая**: `Create`/`Update`/`Delete` возвращают `Operation` (prefix `sop`) сразу, id ресурса лежит в `Operation.metadata` **до** `done`, доменная запись выполняется фоновым worker'ом corelib, клиент поллит `OperationService.Get`. `Operation.done` означает «строка закоммичена» и **ничего** не говорит о видимости downstream-эффектов (owner-tuple в модели прав) — гейтить его на них запрещено.

---

## Инварианты на уровне БД — что и каким механизмом

Каждый within-service инвариант выражен конструкцией Postgres. Ни один из них не держится проверкой в Go «прочитал → сравнил → записал».

| Инвариант | Механизм | Наблюдаемый исход при нарушении |
|---|---|---|
| Том привязан **не более одного раза** (глобально) | `volume_attachments.volume_id` — **PRIMARY KEY** | второй привязчик получает `FAILED_PRECONDITION "Volume <id> is in use"` |
| Привязанный том **не удаляется** | FK `volume_attachments.volume_id → volumes(id) ON DELETE RESTRICT` | 23503 → `FAILED_PRECONDITION "Volume <id> is in use"` |
| Имя устройства уникально **в пределах инстанса** | `UNIQUE (instance_id, device_name)` | явное имя → `FAILED_PRECONDITION "device <n> is already in use on Instance <id>"`; авто-имя → пересчёт и повтор |
| **≤1 загрузочный** том на инстанс | `EXCLUDE USING gist (instance_id WITH =) WHERE (is_boot)` (расширение `btree_gist`) | 23P01 → `FAILED_PRECONDITION "Instance <id> already has a boot volume"` |
| Привязать можно только **READY-том своей зоны и своего проекта** | предикат **внутри** `INSERT … SELECT … FROM volumes v WHERE v.id=$1 AND v.state='READY' AND v.zone_id=$5 AND v.project_id=$4` + `ON CONFLICT (volume_id) DO NOTHING` | 0 строк → дизамбигуация в **три разных** текста (см. ниже) |
| Размер тома **только растёт** | `UPDATE … WHERE id=$1 AND ($5::bigint IS NULL OR $5 > size_bytes)` | `INVALID_ARGUMENT "Volume size can only be increased"` |
| Имя уникально в проекте, **если задано** | partial `UNIQUE (project_id, name) WHERE name <> ''` — по одному на volumes/snapshots/images | `ALREADY_EXISTS "<resource> with name <n> already exists in project"` |
| Тип диска **с томами** не удаляется | FK `volumes.disk_type_id → disk_types(id) ON DELETE RESTRICT` | `FAILED_PRECONDITION "DiskType <id> is in use"` |
| Источник посева принадлежит **тому же проекту** | предикат `EXISTS (… AND s.project_id = $2)` **в том же** `INSERT … SELECT` (volumes и images), либо `WHERE v.project_id = $2` (snapshots) | `FAILED_PRECONDITION "<Resource> <id> not found"` — **байт-в-байт** как настоящий промах |
| Зона boot-тома принадлежит **региону образа** | вторая полоса того же INSERT: CTE `src` требует `i.region_id = $12`, где `$12` — регион зоны, **разрешённый geo** | `FAILED_PRECONDITION "Image <id> not found"` (образ вызывающему мог быть не виден — причину не называем) |
| Том **не меньше** `min_disk_bytes` образа | третья полоса того же INSERT: `EXISTS (SELECT 1 FROM src WHERE src.min_disk_bytes <= $8)` | `INVALID_ARGUMENT "Volume size %d is less than image min_disk_bytes %d"` — образ **уже виден**, поэтому причина называется вслух |
| Снимок снимается **только с READY-тома своего проекта** | `INSERT … SELECT … FROM volumes v WHERE v.id=$6 AND v.project_id=$2 AND v.state='READY'` | `"Volume <id> not found"` либо `"Volume <id> is not ready"` (оба project-scoped) |
| Происхождение **переживает** удаление источника | `ON DELETE SET NULL` на `volumes.source_snapshot_id`, `volumes.source_image_id`, `images.source_snapshot_id`, `images.source_volume_id`, `snapshots.source_volume_id` | удаление источника проходит, ссылка зануляется |
| Форма меток | `CHECK kacho_storage.kacho_labels_valid(labels)` — ≤64 ключей, regex ключа, значение ≤63 | 23514 → `INVALID_ARGUMENT` |
| Форма имени / длина описания / положительность размера | `CHECK` на каждой таблице (`*_name_check`, `*_description_check`, `*_size_bytes_check`, `volumes_block_size_check`) | 23514 → `INVALID_ARGUMENT`; тот же инвариант продублирован self-validating типом в домене (быстрый и точный текст) |
| Домен типов событий очереди | `CHECK (event_type IN ('fga.register','fga.unregister'))` | недостижимо из кода; страховка от чужой записи |
| Забор строки очереди **ровно один раз** между репликами | `UPDATE … WHERE sent_at IS NULL AND attempt_count < $max … FOR UPDATE SKIP LOCKED RETURNING` (corelib) | конкурирующая реплика не заберёт ту же строку |
| **FIFO внутри одного объекта** в очереди | claim не берёт строку, пока в её партиции (`resource_id`) есть доставляемый предшественник с меньшим id | без этого переставленная устаревшая регистрация **воскрешала** зеркало удалённого ресурса — навсегда |

**Циклические FK разрешены порядком, а не отложенностью.** `volumes ↔ snapshots` — обе таблицы создаются без взаимных FK, затем оба `ALTER TABLE … ADD CONSTRAINT`. `images` создаётся позже (уже с inline-FK на существующие `snapshots`/`volumes`), после чего `ALTER volumes` добавляет FK на `images`. `DEFERRABLE` не понадобился ни разу: на момент каждого `ADD` обе стороны существуют.

**Дизамбигуация нуля строк — часть контракта, а не отладка.** Ноль строк из attach-CAS разбирается **в той же транзакции** и даёт ровно один из исходов: конфликтующая строка нашего же инстанса → идемпотентный OK; чужого → `"Volume <id> is in use"`; строки нет и том не READY/не существует → `"Volume is not available for attachment"`; расходится зона → `"Volume and Instance must be in the same zone"`; расходится проект → **свой отдельный** `"Volume and Instance must be in the same project"` (текст зоны намеренно не переиспользован); всё остальное → непрозрачный `INTERNAL`.

---

## Граница владения: почему привязка живёт у storage и почему обратного вызова нет

### Почему таблица привязок — у владельца тома

Все инварианты привязки — это инварианты **тома**, а не машины:

- «том привязан не более одного раза» — свойство тома;
- «привязанный том не удаляется» — правило удаления **тома**;
- «имя устройства уникально в машине» и «загрузочный том один» — свойства машины, но они выражаются над **набором привязок**, который целиком лежит в одной таблице.

Если бы таблица жила у потребителя (как раньше жила `attached_disks` в compute), то первые два правила пришлось бы держать **через границу сервиса**: FK туда невозможен (база на сервис), значит остаётся программный рефкаунт с окном между проверкой и записью — ровно тот класс, который однажды уже дал двух победителей на одной строке. Перенос таблицы к владельцу превращает четыре программных правила в четыре констрейнта: PK, FK RESTRICT, UNIQUE, EXCLUDE. Миграция compute `0013_drop_attached_disks` сносит прежнюю таблицу **без переноса данных** (голый `DROP TABLE`, ни одного `INSERT`) — раскол изначально спроектирован как «пишем правильно с нуля», а не как копирование.

### Почему инициатор — compute, и почему обратного звонка нет

Инициатором остаётся **compute**: это он знает, что машина создаётся/меняется, и это его `Operation` держит tenant-facing асинхронность. Но запрос **самоописывающийся**: `AttachVolumeRequest` несёт `instance_id`, `instance_name`, `instance_zone_id`, `project_id`, `device_name`, `is_boot`, `mode`, `auto_delete`. Storage валидирует **свою** строку `volumes` против этих значений одним CAS и **никогда не звонит в compute**:

```
compute (InstanceService.Create / AttachDisk, async Operation)
   │  self-describing payload: instanceId, instanceName, instanceZoneId, projectId, device…
   ▼
storage InternalVolumeService.Attach  (:9091, mTLS, per-RPC Check, СИНХРОННЫЙ CAS)
   │  INSERT … SELECT FROM volumes WHERE state='READY' AND zone_id=$ AND project_id=$
   ▼
kacho_storage.volume_attachments   ← источник истины
   ▲
   │  batched ListAttachments(instanceIds[])      ← compute перечитывает для зеркала на Instance.Get/List
compute (read-only зеркало, мягкая деградация при недоступности storage)
```

Проверяемое следствие: в `services/storage` **ноль** Go-импортов `computev1`. Цикл `compute ↔ storage` невозможен не по договорённости, а по отсутствию направления вызова. Обратная сторона размена названа честно: `instanceName` — **снимок на момент привязки**, storage его не обновляет; переименование машины в зеркале тома не отражается.

**Attach синхронен, и это не нарушает «мутации асинхронны».** CAS мгновенен, а tenant-facing мутация — это `AttachDisk` на стороне compute, которая и возвращает `Operation`. Внутреннее ребро не обязано заворачиваться во вторую LRO ради формы.

**Идемпотентность на повторе.** Тот же том к тому же инстансу → конфликт по PK → `DO NOTHING` → дизамбигуация видит **свою** строку → OK. Это важно именно потому, что вызывающий — саговый воркер с повторами.

**Авто-имя устройства — повтор-до-свободного, а не «прочитал занятые и вставил».** Пустой `deviceName` → выбирается первое свободное из `sdb..sdz`; если конкурент занял его между выбором и вставкой, приходит 23505 на `UNIQUE(instance_id, device_name)`, имя пересчитывается и попытка повторяется (ограничено 25 — размером пространства имён). Наружу этот 23505 **не всплывает**: чтение занятых — эвристика, источник истины — констрейнт. Пространство исчерпано → `FAILED_PRECONDITION "no free device name on Instance <id>"`.

---

## Когерентность размещения и исключение для регионального/эникаст

| Пара | Правило | Где энфорсится |
|---|---|---|
| Volume ↔ Instance (привязка) | **та же зона** и **тот же проект** | предикат внутри attach-CAS (`v.zone_id = $5 AND v.project_id = $4`) |
| Volume (ZONAL) ↔ Image (REGIONAL) | зона тома ∈ **регион образа** | полоса `src` внутри insert-CAS: `AND i.region_id = $12` |
| Volume ↔ Snapshot | только **тот же проект** (снимок не несёт размещения) | предикат внутри insert-CAS |
| Image (REGIONAL) ↔ его источник (ZONAL) | зона источника ∈ **регион образа**; для источника-снимка — по происхождению (зона тома, с которого снят снимок) | полоса `AND lv.zone_id = ANY($10::text[])` / `AND v.zone_id = ANY($10::text[])` внутри `imageInsertCoherentSQL` (`image_repo.go:181-188`); список зон региона резолвится у geo **до** постановки Operation |
| `zoneId` / `regionId` существуют | peer-вызов geo (`ZoneService.Get` / `RegionService.Get`), 3 s на вызов, fail-closed | `internal/clients/geo_client.go` |

**Исключение эникаст.** У образа зоны нет вовсе (`placement_type` всегда `REGIONAL`, колонки `zone_id` в `images` не существует), поэтому зональное сравнение к нему **неприменимо by construction** — сравнивать не с чем. Остаётся региональная проверка, и она выполняется.

**Регион зоны берётся только у владельца Geography.** `GeoClient.RegionOfZone` вызывает `ZoneService.Get` и читает поле региона из ответа. Отрезание суффикса зоны, срез по последнему дефису, префиксное сравнение имён — **запрещены**: имена региона и зоны произвольны, а строковый вывод молча возвращает пустую строку на ресурсе без зоны и превращает проверку в no-op. Здесь это учтено буквально: пустой резолв региона делает полосу образа несматчиваемой (**fail-closed**), а не пропускающей.

**Почему проверка стоит внутри INSERT, а не перед ним.** Разрешённый образ и вставляемый том должны сверяться атомарно — иначе между «проверил регион» и «вставил» образ может исчезнуть или смениться. Все три полосы (проект, регион, ёмкость) вычисляются в **одном** стейтменте, а стейтмент **всегда возвращает ровно одну строку-дискриминатор**: либо успешную вставку, либо `(NULL, NULL, min_disk_bytes разрешённого образа)`. Различие двух отказов принципиально: `min_disk IS NULL` ⟺ образ не разрешился (чужой проект/регион) ⟹ **скрываем существование**; `min_disk NOT NULL` ⟺ образ свой и виден ⟹ отказ по размеру **называется вслух** вместе с числом.

---

## Материализация прав: очередь регистраций

### Что эмитится и когда

| Событие | Тип строки | Payload | Почему так |
|---|---|---|---|
| `Volume/Snapshot/Image.Create` | `fga.register` | tuple + `labels` + `parent_project_id` + `source_version` | владелец обязан немедленно получить доступ к своему ресурсу, а шлюз — резолвить объект → проект (анти-BOLA) |
| `Update` **со сменой меток** | `fga.register` (UPSERT зеркала) | tuple + **новые** labels | доступ, выданный по селектору меток, отзывается **снятием метки**; без переэмита зеркало застывало на моменте создания и грант переживал метку |
| `Update` **без** меток (переименование) | ничего | — | селектору переименование ничего не сообщает, а лишняя строка — трафик, который голова партиции обязана разгрести раньше настоящего намерения |
| **Полное снятие** меток | `fga.register` с **пустыми** метками | tuple + `{}` | это **не** `unregister`: ресурс жив и сохраняет owner-tuple, он лишь перестаёт матчиться селектором. Unregister отобрал бы доступ у самого владельца |
| `Delete` | `fga.unregister` | tuple + `source_version` как **надгробие** | без версии удаление не матчит версионированную строку зеркала, зеркало переживает ресурс, а level-triggered реконсайлер вечно ре-материализует его права |

Форма tuple: `project:<projectId> #project @storage_volume|storage_snapshot|storage_image:<id>`. Типы объектов storage **не изобретает** — они уже объявлены в каталоге прав и в извлекателях области шлюза; сервис лишь кормит существующие типы.

### Как это доезжает

1. **Намерение — в той же транзакции**, что и доменная запись (`emitFGARegister` вызывается внутри `pgx.BeginFunc`). Один commit ⇒ «строка есть, а намерения нет» невозможно by construction.
2. **`source_version` штампуется часами БД** прямо в INSERT (`jsonb_set(payload,'{source_version}', to_jsonb(now()))`) — внутри writer-транзакции, монотонно на объект: позднее закоммиченная транзакция несёт строго больший штамп.
3. **Триггер `pg_notify`** на канал `kacho_storage_fga_register_outbox` будит дренаж на каждом INSERT.
4. **Синхронный регистратор** после успешного коммита `Create` делает тот же `RegisterResource` немедленно (5 s на вызов) — это **оптимизация окна**, а не путь доставки: его ошибка логируется WARN и **не роняет** `Create`, потому что durable-намерение уже лежит в очереди.
5. **Дренаж** (corelib) применяет каждое намерение через `InternalIAMService.RegisterResource`/`UnregisterResource` по mTLS, идемпотентно, at-least-once.

### Почему claim берёт только голову партиции

Таблица несёт **и** регистрацию, **и** снятие одного и того же объекта, а материализация на стороне iam версионирована лишь **частично**: LWW по `source_version` защищает ветку обновления зеркала, а снятие — жёсткое удаление без надгробия в самой строке. Переставленная **устаревшая** регистрация не находит, с чем сравниться, уходит в ветку вставки и **воскрешает** зеркало удалённого ресурса — навсегда, потому что реконсайлер level-triggered и самоисцеления нет.

Перестановка возникает **без всякой конкурентности**: claim сортирует `ORDER BY (attempt_count, id)`, поэтому предшественник, у которого счётчик попыток подрос из-за кратковременной недоступности iam, проигрывает свежему преемнику даже при одном применителе — и попадает в **более поздний** батч. Поэтому порядок держится на уровне **забора строки**, а не группировкой при применении:

```sql
AND NOT EXISTS (SELECT 1 FROM kacho_storage.fga_register_outbox p
                 WHERE p.sent_at IS NULL AND p.attempt_count < $max
                   AND p.id < t.id AND p.resource_id = t.resource_id)
```

Ключ партиции — `resource_id` (id-половина `tuple.Object`, глобально уникальная по построению): «одна партиция» = «один объект зеркала». Разные объекты дренятся параллельно.

### Три миграции, которые делают этот claim жизнеспособным

- **0008** — partial-индекс `(resource_id, id) WHERE sent_at IS NULL` под коррелированный `NOT EXISTS`. Без него анти-join — последовательное сканирование на каждую строку-кандидата, то есть квадратично по глубине очереди.
- **0009** — partial-индекс `(attempt_count, id) WHERE sent_at IS NULL` под **внешний** `ORDER BY`. Без него планировщик вообще не доходит до вложенного цикла, ради которого построен 0008: он сканирует весь незавершённый бэклог, сортирует его и хэш-анти-джойнит со **вторым** полным сканированием того же бэклога. Это не «медленнее», это **инверсия пропускной способности**: чем глубже очередь, тем медленнее каждый забор, тем глубже очередь. Замер на однотипной очереди iam (Postgres 16, живой стенд): 5 000 строк — 11.7 ms против 0.81 ms; 20 000 — 61.6 ms против 0.72 ms; 80 000 — 327 ms против 0.82 ms.
- **0010** — per-table autovacuum (`scale_factor = 0`, порог 1000) + немедленный `ANALYZE`. Очередь **почти всегда пуста**, поэтому последний анализ почти всегда случался на нулевом бэклоге, и в всплеск планировщик входит с оценкой «одна строка» — на такой оценке он **отбрасывает** оба partial-индекса. Замер на той же очереди iam: 2 495 строк на устаревшей статистике — 4 488 ms; 7 849 строк после `ANALYZE` — 3.6 ms. Индекс без свежей статистики необходим, но **недостаточен**.

### Классификация ошибок дренажа

`InvalidArgument` **и** `PermissionDenied` → **перманентная** (строка отравляется); всё остальное — недоступность, дедлайн, транспорт, состояние пира — временная (`internal/clients/iam_register_applier.go:121-148`; тот же контракт в corelib — `pkg/outbox/drainer/classify.go:141`).

**Почему отказ по правам терминален, хотя выглядит как «пир ещё не досеян».** Решение об авторизации — функция от (вызывающий, отношение, объект); повтор не меняет ни одного из трёх, поэтому идентичный повтор пройти не может. «Временная» классификация здесь не покупает будущий успех, а **ломает порядок**: дренаж намеренно держит временную строку на единицу **ниже** порога отравления, поэтому она никогда не покидает блокирующий набор claim-запроса, а партиция — это ресурс, и снятие регистрации стоит в очереди **за** регистрацией. Заклиненная голова означает **грант, переживший удаление ресурса**. Отравление, наоборот, отказывает закрыто: отвергнутая запись не состоялась, партиция разблокирована. Ровно эта пара (отказ в правах + per-resource FIFO) однажды опустошила очередь другого сервиса — 198 строк, ни одна не доставлена.

**Отравление само по себе не самоисцеляется, поэтому идёт в паре с redrive-бэкстопом.** Недоставленная регистрация оставляет ресурс без mirror-строки в iam, а значит без owner-tuple, и реконсайлер такой объект вообще не перечисляет — ресурс становится невидим для authz до ручной правки БД. Периодический `RedrivePoisoned` (5 минут, паритет с compute/vpc/nlb — `cmd/storage/redrive_backstop.go`) превращает отравление в **ограниченную паузу**: причина, которая была временной (не досеянный грант `fga_writer` на свежем стенде), отработает на следующем круге; причина, которая действительно постоянна (отношение вне принимаемого набора), отравится снова — и это видно счётчиком отравлений, а не тишиной.

**Залочено на трёх уровнях** (не комментарием): `TestClassify_PermissionDeniedIsPermanent` (`pkg/outbox/drainer/classify_test.go:85`) и `TestClassifyRegisterErr` (`services/storage/internal/clients/iam_register_applier_test.go:91`) — классификация; `Test_PermissionDeniedHead_DoesNotWedgePartition` (`pkg/outbox/drainer/permission_denied_terminal_integration_test.go:48`) — поведение партиции под живым Postgres, то есть утверждается **последствие**, а не только код возврата; `TestRedriveOnly_RefusesTheStatePasses` и соседи (`pkg/outbox/reconciler/redrive_only_test.go`) — что бэкстоп переигрывает **только** отравленные строки и не трогает чужую ответственность.

**Что здесь остаётся вопросом принимающей стороны, а не дренажа.** Набор эмитируемых отношений обязан приниматься **закрытым списком iam**; сверка «эмитим то, что владелец примет» — часть контракта регистрации, а не классификации ошибок (правило `data-integrity.md` §«Межсервисное намерение»). Наблюдается метрикой отравлений: устойчиво растущий `kacho_storage_outbox_poisoned_total` при работающем redrive означает именно непринимаемое отношение.

---

## Видимость списков: страница → проверка страницы

Публичные `Volume.List` / `Snapshot.List` / `Image.List` работают **в два слоя**, и оба обязательны:

1. **Область** — `projectId` обязателен (проверяется первым стейтментом use-case, до всего остального), запрос к БД сужается `WHERE project_id = $`. Шлюз независимо гейтит тот же `projectId` извлекателем области.
2. **Пообъектная видимость** — прочитанная курсором страница целиком уезжает в iam **батчами ≤100** (`AuthorizeService.BatchCheck`) и спрашивается **ровно на том отношении, которым гейтится `Get`** — `viewer` (`services/storage/internal/authzfilter/filter.go:84`; зеркало каталога — `internal/check/permission_map.go:88`).

### «Список не показывает того, чего не отдаст `Get`» — как это держится сегодня

**Было и исправлено (закрыто задачей #75).** Фильтр спрашивал **союз** `viewer ∪ v_list`, а `Get` гейтился только `viewer`, поэтому субъект с узким грантом видел на странице идентификатор, который открыть не мог, — оракул существования, выданный самим read-path'ом. Прежняя редакция этого документа утверждала при этом обратное («видно в списке ⟺ `Get` разрешён»), и тот же ложный текст стоял в трёх местах кода. Сегодня в дереве:

- `visibilityRelations = [...]string{"viewer"}` — **одно** отношение, с записанным запретом расширять набор: «видно в перечне, но без содержимого» — это отдельная усечённая проекция ответа, а не более широкий предикат видимости на полных строках;
- инвариант залочен **двумя** тестами, а не комментарием: `TestVisibilityRelationsMatchCatalogGetRelation` (`internal/authzfilter/filter_get_parity_test.go:34` — набор фильтра сверяется с отношением `Get` из **каталога**, а не с литералом в тесте) и `TestListNeverShowsWhatGetWouldRefuse` (`:73`); отказ `viewer` теперь окончателен — `TestFGAFilter_ViewerDenialIsFinal` (`filter_test.go:139`) заменил прежний `TestFGAFilter_VListPicksUpWhatViewerDenied`, который локал **дефект**;
- ничего по грантам при этом не потерялось: реконсайлер iam на **каждый** материализованный объект пишет, помимо `v_*`, back-compat tier-tuple (`add(tier)`, «Always emitted» — `services/iam/internal/apps/kacho/api/access_binding/reconcile/tuples.go:82-84`), а `viewer: … or editor`, `editor: … or admin` резолвят любой из трёх. То есть `v_list` без резолвящегося `viewer` — не выданный доступ, а недоматериализованное состояние, и показывать по нему нечего.

**Внутрисервисная карта зеркалит каталог — это теперь проверяемо, а не декларируется.** Появился общий пакет `pkg/authz/catalogparity`: он сверяет in-process `authz.RPCMap` сервиса с **сгенерированным** `permission_catalog.json` (артефактом, который энфорсит шлюз) по **двум** осям — `required_relation` и `object_type` области. Тест `TestPermissionMapMirrorsCatalog` стоит в **шести** сервисах, у которых такая карта вообще есть: `services/{compute,geo,nlb,registry,storage}/internal/check/catalog_parity_test.go` и `services/vpc/internal/apps/kacho/check/catalog_parity_test.go`. Седьмой сервис — **iam** — внутрисервисной карты не несёт вовсе (`grep -rl "authz.RPCMap" services/` даёт ровно шесть файлов реализации, ни одного в `services/iam`): он сам является владельцем решения о правах, зеркалить ему нечего. Так что «во всех семи» здесь означает **6 сверок + 1 обоснованное отсутствие предмета**, и это записано, чтобы «шесть из семи» не читалось как пропущенный сервис.

Прежний тест зеркальности проверял **один** RPC и сравнивал с литералами, переписанными в сам тест, — форма проверки без содержания; он заменён обходом всех записей домена против артефакта.

### Что осталось — read-over-grant, и он шире storage

Расхождение, **не** закрытое #75 и не покрытое ни одной другой заведённой задачей: storage гейтит read на **tier**-отношении `viewer`, тогда как compute/vpc/nlb/registry — на **verb**-отношении `v_get`/`v_list` (инвентарь `required_relation` по доменам: storage — `v_get`/`v_list` **ноль**, `viewer` ×13; compute — `v_get` ×10, `v_list` ×9; vpc — ×8/×18; nlb — ×4/×3; registry — ×1/×1; geo — объектно-скоупленной read-поверхности нет, публичный read Region/Zone — задокументированный `<exempt>`). Тип `storage_volume` при этом **verb-bearing** (`services/iam/internal/authzmap/fga_types.go:175-177`), то есть iam честно материализует ему `v_get`/`v_list` — просто storage их не спрашивает.

Следствие наблюдаемое: грант с verbs `["update"]` материализует `v_update`+`v_delete`+**tier `editor`**, а `viewer: … or editor` ⟹ на storage такой субъект **читает** ресурс; на compute тот же субъект получает `403` на `Get`, потому что `v_get` ему не выдан. Это ровно тот класс, который миграция iam `0040_edit_roles_include_read_verbs.sql` закрывала («editor больше не implies viewer»), — в storage связка не разорвана.

**Задача не заведена, требуется отдельная** (номер не выдумывается): #75 закрыт по своему предмету — паритет фильтра и карты с каталогом, — и перевод каталога на Design-B в него не входил. **Критерий приёмки будущей задачи:** `Get`→`v_get`, `List`→`v_list`, `Create`→`v_create`, `Update`→`v_update`, `Delete`→`v_delete` в proto-аннотациях storage, в `internal/check/permission_map.go` и в обеих embedded-копиях каталога; наблюдается — `make -C gateway permission-catalog-check` зелёный, `TestPermissionMapMirrorsCatalog` и `TestVisibilityRelationsMatchCatalogGetRelation` зелёные **после** перевода (они сверяются с каталогом, поэтому переживают смену отношения), и поведенческая регрессия в коллекции `authz`: субъект с verbs `["update"]` — `Get` **403** (сегодня 200, RED пишется первым), с verbs `["get","list"]` — 200; закрытие — `run.sh` **9 из 9** коллекций, `assertions.failed == 0`.

**Почему именно так, а не «перечисли всё разрешённое и сузь этим SQL».** У перечисления объектов жёсткий серверный предел без продолжения: ответ молча усекается произвольным префиксом, предел действует **на тип во всём кластере**, и на долгоживущем сторе собственный ресурс тенанта выпадает за префикс и становится **невидимым навсегда** при живых правах. Просьба «дай больше» предел не поднимает — это обрезка уже усечённого ответа. Здесь такого вопроса нет ни на одном пути.

**Дисциплина фильтра (всё — по коду):**

- **Порядок проверок фиксирован**: `projectId` → `page_size` → `filter` → чтение страницы (там же декодируется и проверяется маркер страницы) → фильтр. Поэтому мусорный маркер и `page_size > 1000` дают `INVALID_ARGUMENT` **независимо от того, есть ли у вызывающего гранты**, а не пустую страницу.
- **Пустой субъект → пустая страница**, не обход. Запрос без личности вызывающего (системный принципал, потерянный проброс) не перечисляет чужое. Пустой ответ, а не ошибка — существование чужих ресурсов остаётся непознаваемым.
- **Fail-closed по умолчанию**: ошибка iam → `UNAVAILABLE`, страница **никогда** не отдаётся нефильтрованной. Есть ручка деградации (`…_LIST_FILTER_FAIL_OPEN`), и каждое её срабатывание пишет audit-WARN — она обязана быть громкой.
- **Кэшируются только положительные вердикты** (TTL 5 s, LRU на 10 000). Отрицательные — никогда: иначе отзыв залипал бы на TTL, а свежесозданный ресурс оставался бы невидимым владельцу весь TTL.
- **Ограниченный веер 5 параллельных батчей.** Число выведено из контракта, а не подобрано: максимум страницы 1000 при батче 100 даёт **10** батчей, а отношение теперь **одно** (`viewer`), поэтому `worstCaseDepth = len(visibilityRelations) × ceil(10/5)` = **2 волны** — 5 ровно делит 10, без рваного хвоста. Глубина в 2 волны **освобождает** бюджет под реалистичный per-call дедлайн (1 s — `DefaultConfig.Timeout`, `filter.go:153`), а не пилит его под число последовательных хопов; всплеск на пира ограничен 5 одновременными `BatchCheck` (≤500 проверок в полёте) на запрос. Это не ослабление проверки: тот же предикат, те же батчи ≤100, тот же fail-closed — меняется только порядок ожидания ответов.
- **Бюджет всей операции** выводится из дедлайна вызова и веера с запасом ×3/2 — потолок, который в здоровом режиме не срабатывает; срабатывать должны per-call дедлайны.
- **Расхождение длины ответа с длиной запроса — ошибка, а не «считаем отказом»**: молчаливое смещение индексов выдало бы вердикт одного объекта за другой.
- **Каталог `DiskType` через фильтр не проходит** — ambient cluster-scoped чтение.
- **Production boot-guard требует включённого фильтра** — выключить его на развёрнутом стенде нельзя.

---

## RPC surface

### Public — `kacho-storage:9090` → REST шлюза

| RPC | REST | Синхронность | Область проверки | Отношение |
|---|---|---|---|---|
| `VolumeService.Get` | `GET /storage/v1/volumes/{volumeId}` | sync | объект `storage_volume` | `viewer` |
| `VolumeService.List` | `GET /storage/v1/volumes` | sync | родитель `project` | `viewer` |
| `VolumeService.Create` | `POST /storage/v1/volumes` | → `Operation` | родитель `project` | `editor` |
| `VolumeService.Update` | `PATCH /storage/v1/volumes/{volumeId}` | → `Operation` | объект `storage_volume` | `editor` |
| `VolumeService.Delete` | `DELETE /storage/v1/volumes/{volumeId}` | → `Operation` | объект `storage_volume` | `editor` |
| `VolumeService.ListOperations` | `GET /storage/v1/volumes/{volumeId}/operations` | sync | объект `storage_volume` | `viewer` |
| `SnapshotService.Get/List/Create/Update/Delete` | `/storage/v1/snapshots[/{snapshotId}]` | read sync, мутации → `Operation` | `project` (List/Create) / `storage_snapshot` (остальное) | `viewer`/`editor` |
| `ImageService.Get/List/Create/Update/Delete/ListOperations` | `/storage/v1/images[/{imageId}][/operations]` | read sync, мутации → `Operation` | `project` (List/Create) / `storage_image` (остальное) | `viewer`/`editor` |
| `DiskTypeService.Get/List` | `/storage/v1/diskTypes[/{diskTypeId}]` | sync | кластерный синглтон | `viewer` |
| `OperationService.Get/Cancel` | `/operations/{id}` · `/operations/{id}:cancel` | sync | **вне** ReBAC-Check (`{Public: true}`); владение энфорсится предикатом в SQL, а **бесключевой запрос отсекается до предиката** (`OwnerFromContext`), см. разбор ниже | — |

### Internal — `kacho-storage:9091` (mTLS)

Колонка «внешний слушатель» — **проверенное** поведение шлюза, а не намерение контракта.

| RPC | Путь через шлюз | Внешний слушатель | Область | Отношение |
|---|---|---|---|---|
| `InternalVolumeService.Attach` | `POST /kacho.cloud.storage.v1.InternalVolumeService/Attach` | **404** — маршрута нет | объект `storage_volume` | `editor` |
| `InternalVolumeService.Detach` | `…/Detach` | **404** | объект `storage_volume` | `editor` |
| `InternalVolumeService.ListAttachments` | `…/ListAttachments` | **404** | кластерный синглтон | `viewer` |
| `InternalVolumeService.GetInternal` | `…/GetInternal` | **404** | объект `storage_volume` | `viewer` |
| `InternalImageService.GetInternal` | `POST /kacho.cloud.storage.v1.InternalImageService/GetInternal` | **404** | объект `storage_image` | `viewer` |
| `InternalDiskTypeService.Create/Update/Delete` | `POST/PATCH/DELETE /storage/v1/diskTypes[/{diskTypeId}]` | **404** — ловится по паре (метод, путь) | кластерный синглтон | `system_admin` |

Четыре `InternalVolumeService`-метода и `InternalImageService.GetInternal` не имеют REST-аннотаций, поэтому получают default-путь `/<package>.<Service>/<Method>` — его ловит path-shaped слой (`isInternalPath` → `allowlist.HasInternalSuffix`), и на внешнем слушателе он даёт 404. Последняя строка приходит с **другой** стороны того же диспетчера: у неё человекочитаемая аннотация на публичном пути, поэтому её ловит не путь, а **пара (метод, путь)**, выведенная из proto-дескрипторов, — разобрано в «Поверхность admin-CRUD каталога» (DiskType).

**404 из первых пяти строк залочен, но ДВУМЯ разными тестами в двух файлах — это не педантизм, а условие того, чтобы гейт наблюдал заявленное.** Четыре `InternalVolumeService`-маршрута утверждает `TestStorage_InternalVolumeService_ExternalListenerRejected` (`gateway/internal/restmux/storage_test.go:114-139`; в файле ровно 139 строк). Пятый, `InternalImageService/GetInternal`, утверждает **другой** тест — `TestRedesign_InternalRoutes_ExternalListenerRejected` (`gateway/internal/restmux/redesign_reg_test.go:110-134`), которого фильтр `-run TestStorage` **не матчит**. Прежняя редакция приписывала все пять одному тесту и одному фильтру: тогда гейт DoD №2 покрывал 4 маршрута из 5, а документ засчитывал 5 — ровно та «форма без содержания», которую документ сам объявляет провалом. Команда гейта приведена в соответствие: `-run 'TestStorage|TestRedesign_InternalRoutes'` (проверено — зелёная, покрывает обе функции). Строка `diskTypes` утверждается **третьим** файлом — `internal_catalog_isolation_test.go` (`TestExternalListener_RejectsDiskTypeAdminRoutes`, `:60`), которого не матчит ни один из двух прежних префиксов; поэтому фильтр гейта №2 расширен и на него.

**Карта прав обязана покрывать каждый обслуживаемый RPC обоих слушателей**: интерсептор corelib fail-closed'ит непокрытый метод («rpc not mapped»), то есть пропуск в карте = RPC, не работающий ни при каких грантах. Полноту стережёт тест, обходящий protobuf-дескрипторы пакета `kacho.cloud.storage.v1`.

**`OperationService` зарегистрирован на обоих слушателях** и снят с ReBAC-Check записью `{Public: true}` в карте прав (`internal/check/permission_map.go:167-168`) — типа объекта «операция» в модели нет. Что именно его закрывает — надо назвать точно; прежняя редакция называла механизм, которого в коде не было, и **этот механизм с тех пор появился**.

**Ключ владельца выводится функцией, которая СООБЩАЕТ о наличии принципала.** `OwnerFromContext(ctx) (Owner, bool)` (`pkg/operations/owner.go:48-54`) построена не на `PrincipalFromContext`, а на `PrincipalFromContextOK`, и отдаёт **нулевой** `Owner{}` с `ok=false`, если принципала не было, он был явно снят транспортом (`WithoutPrincipal`) либо у него пуст `ID`/`Type`. Различение идёт по **наличию носителя в контексте**, а не сравнением с какой-либо личностью — поэтому `SystemPrincipal()`-fallback, который `PrincipalFromContext` по-прежнему отдаёт на write-пути, в ключ владельца больше не попадает by construction. Прежняя опасная композиция `OwnerFromPrincipal(PrincipalFromContext(ctx))` в дереве отсутствует полностью (в проде остался единственный вызов `OwnerFromPrincipal` — внутри самой `OwnerFromContext`), а её godoc несёт явный запрет так делать.

**Отказ неотличим от отказа постороннему.** Все шесть сервисов, выставляющих полл операций, отвергают запрос без ключа **тем же** ответом, что и чужому: `status.Errorf(codes.NotFound, "operation %s not found", id)`. У storage это `internal/handler/operation_handler.go:54-57` (`Get`) и `:81-84` (`Cancel`); арм «чужая операция» — `mapOpErr` (`:98-99`) — несёт **тот же** код, тот же конструктор, ту же форматную строку и то же подставляемое значение. Байт-идентичность утверждается тестом напрямую, а не выводится рассуждением.

**Репозиторий отсекает анонимного владельца ДО построения предиката** — второй, независимый слой: `Owner.IsAnonymous()` (`pkg/operations/owner.go:68`) проверяется первым стейтментом в `GetOwned` (`pkg/operations/repo.go:533`) и `CancelOwned` (`:557`), оба возвращают `ErrNotFound`, и в `ListOwned` (`:358`), который возвращает **пустую страницу с `nil`-ошибкой** — списочный аналог «своих операций нет», а не «нет такой коллекции». Возвращаемые значения у трёх методов **разные**, и формулировка «репозиторий отдаёт not-found на пустой ключ» верна только для двух из них. Гейт стоит выше `fmt.Sprintf`-сборки запроса, поэтому вызывающий, проигнорировавший флаг, всё равно не доедет до `ownerPredicateSQL` (`:205`) — godoc предиката это фиксирует прямо: он значим только для непустого ключа.

**Что сузилось — анонимность, а не системная личность.** Явно установленный системный принципал на доверенном internal-пути остаётся владельцем своих операций: `withTrustedPrincipal` (`pkg/grpcsrv/cert_identity.go:253`, **не менялась**) на доверенном пире кладёт личность в носитель через `WithPrincipal`, поэтому `ok=true`; на недоверенном — вызывает `WithoutPrincipal`, и тогда ключа нет вовсе. Именно эту пару ветвей воспроизводят тесты, а не синтетический контекст.

> [!note] Список доверенных форвардеров storage по-прежнему пуст — и это осознанно принимаемый размен
> `services/storage/cmd/storage/serve.go:203` — `forwarders := []string{}`, поэтому `principalIsTrusted` (`pkg/grpcsrv/cert_identity.go:280-299`) на mTLS-слушателе уходит в ветку `len(cfg.forwarders) > 0 → false` и возвращает `true`: **любой верифицированный пир считается доверенным форвардером**. Приемлемо потому, что оба слушателя требуют mTLS (в контур не попасть без клиентского сертификата, выпущенного internal-CA), периметр cluster-internal, а storage **не производит** строк с системным владельцем: все девять созданий операции — `NewFromContext` в `Create`/`Update`/`Delete` Volume/Snapshot/Image, каждое гейчено реальным отношением (`viewer`/`editor`), а системный субъект резолвится в `user:bootstrap` и отвергается `Check`'ом iam (`AllowSystemPrincipal` выключен). Это и есть та «запись в документе», которой требовал прежний критерий приёмки — альтернатива (пин SAN'а шлюза в production-конфиге) остаётся возможной, но не обязательной.
> **Осторожно с комментарием в коде:** `internal/check/permission_map.go` (блок `:145-166`) утверждает, что при пустом списке «forwarded-principal не принимается ни от кого». Код говорит обратное (см. `cert_identity.go:294-298`). На вывод это не влияет — от анонимности защищает `OwnerFromContext`, а не список форвардеров, — но повторять эту формулировку в документе нельзя.

Что **остаётся верным** из прежней редакции: чужой и несуществующий id дают **одинаковый** `NOT_FOUND` — прямая ссылка на объект не становится оракулом. Изменилось то, что теперь тем же ответом отвечает и **бесключевой** запрос, а не только чужой.

---

## Решения и их обоснование

1. **Статус тома — производная, а не колонка.** Единственная запись факта «привязан» — строка привязки. Колонка-дубль неизбежно разъезжается с ней (и разъезжалась в предыдущем поколении); производная разъехаться не может.
2. **Таблица привязок — у владельца тома.** Инварианты привязки — это инварианты тома; выразить их констрейнтами можно только в его базе. У потребителя они выродились бы в программный рефкаунт через границу сервиса.
3. **Инициатор — compute, но запрос самоописывающийся.** Так снимается потребность в обратном звонке: storage проверяет **свою** строку против присланных координат. Ацикличность держится отсутствием направления вызова, а не соглашением.
4. **Каждый спорный путь — атомарный CAS.** Привязка, увеличение размера, посев из источника — «вставка/обновление-если-можно» одним стейтментом. Ни одного `Get → check → write`.
5. **Отказ по чужому ресурсу байт-в-байт равен настоящему промаху.** Иначе различимый текст превращается в оракул: «чужой ресурс существует». По той же причине дизамбигуация снимка резолвит том **в проекте** — иначе чужой не-READY том выдал бы себя текстом «не готов».
6. **Отказ по размеру, наоборот, называется вслух** — потому что образ на этом пути уже разрешился и вызывающему **виден**; скрывать его минимум незачем, а не назвать его — значит заставить гадать.
7. **`Operation.done` = «строка закоммичена», и только.** Гейтить его на видимость owner-tuple запрещено: это переопределяет предмет операции и на fail-closed рождает ресурс-фантом (строка есть, имя занято, операция в ошибке).
8. **Синхронный регистратор — оптимизация окна, а не путь доставки.** Его ошибка не роняет `Create`, потому что durable-намерение уже в очереди; путь доставки — дренаж.
9. **Полное снятие меток эмитит регистрацию с пустыми метками, а не снятие регистрации.** Ресурс жив; снятие отобрало бы доступ у самого владельца.
10. **Порядок в очереди держится на заборе строки, а не при применении.** Группировка при применении не знает про строки, попавшие в другой батч; перестановка происходит и при одном применителе.
11. **Admin-CRUD каталога синхронен.** Cluster-scoped справочник без саги — одна вставка; LRO здесь была бы формой без содержания (то же решение принято в geo).
12. **Доменный поток событий снят, а не оставлен «на будущее».** Очередь `storage_outbox` писалась в каждой транзакции и **не читалась никем** (заголовок 0005 утверждал наличие потребителя — это было ложное заявление: owner-tuple идёт через отдельную таблицу, а единственная подписка сервиса слушает другой канал). Строки копились вечно, каждая мутация платила лишнюю вставку, триггер и уведомление в канал без слушателей. Очередь корректно вводится **вместе со своим потребителем**, поэтому она удалена отдельной миграцией 0011 (применённую 0005 не редактируем).
13. **Boot-guard отказывается стартовать, а не предупреждает.** Прежде режим авторизации был объявлен и **никогда не читался** — сервис поднимался небезопасно в «production» с одним WARN. Теперь `Validate()` гейтит ровно те три-четыре измерения, которые composition root реально разводит по конфигу, поэтому «валидация прошла» ⟺ «поднимется безопасно».

---

## Поведенческие контракты (Given-When-Then)

Сценарии описывают **наблюдаемое поведение уже стоящего кода** — это форма записи контракта, а не план работ.

**Имена в «Трассировке» — существующие, имена в критериях приёмки — предписанные.** Все `Test…` и newman-кейсы в строках **Трассировка** проверены присутствием в дереве (`grep -rq "func Test…(" --include=*_test.go` и поиск по `services/storage/tests/newman/cases/`); имена, встречающиеся **в критериях приёмки** незакрытых пунктов (`SNP-CR-BVA-DESC-OVER-257`, `VOL-CR-NEG-DISKTYPE-ZONE`, `SNP-OPS-LIST-OK`, `SNP-UPD-VAL-NAME-UPPERCASE`, `VOL-LST-ORDERBY-*`, `*-UPD-BVA-DESC-OVER-257`), в наборе **ещё отсутствуют** — это предписание, как назвать будущий кейс, а не ссылка. Смешивать эти два вида ссылок нельзя: именно так «инвентарь» и выдаёт себя за покрытие.

**Идентификаторы — только из живых пространств, своего документ не заводит.** Прежняя редакция нумеровала сценарии как `STOR-GWT-01..27`; `grep -rn "STOR-GWT"` по монорепо давал **ноль** вхождений — ни в Go-тестах, ни в девяти newman-наборах, ни в acceptance-доках. Это было третье, ни с чем не связанное пространство имён. Здесь каждый сценарий якорится на **существующий** id из acceptance-дока (`CS1-S*` — `docs/specs/sub-phase-CS-1-storage-network-disk-acceptance.md`; `STOR-1-*` — `docs/specs/sub-phase-STOR-1-volume-image-acceptance.md`) и несёт строку **Трассировка** с конкретным Go-тестом и/или newman-кейсом. Сценарий без покрытия помечен явно — это дыра, а не умолчание.

**CS1-S1-01 — создание тома (happy).**
Трассировка: `TestVolumeCreateGetDerivedStatus`, `TestCreateLROInsertsAndMarksDone` · newman `VOL-CR-CRUD-OK`.
**Given** существуют проект `P` (в iam) и зона `Z` (в geo), и тип диска `block-balanced` есть в каталоге.
**When** клиент вызывает `POST /storage/v1/volumes` с `projectId=P`, `zoneId=Z`, `diskTypeId=block-balanced`, `sizeBytes=10737418240`.
**Then** ответ — `Operation` с `metadata.volumeId` уже заполненным и `done=false`.
**And** поллинг `OperationService.Get(id)` доходит до `done=true` без `error`.
**And** `GET /storage/v1/volumes/{id}` отдаёт `status=AVAILABLE`, `blockSize=4096`, `createdAt` с точностью до секунды, пустые `attachments`/`usedBy`.

**STOR-1-06 / CS1-S4-01 — привязка тома (happy, инициирует compute).**
Трассировка: `TestAttachHappyDerivedInUse`, `TestListAttachmentsBatched` · black-box нет by design (путь только на :9091 под mTLS — см. шапку `cases/internal-volume.py`).
**Given** том `V` в зоне `Z` проекта `P` со `state=READY` и без привязок.
**When** compute вызывает `InternalVolumeService.Attach` с `volumeId=V`, `instanceId=I`, `instanceZoneId=Z`, `projectId=P`, пустым `deviceName`.
**Then** ответ несёт `Volume` со `status=IN_USE` и ровно одной привязкой, `deviceName=sdb`.
**And** storage **не совершает** ни одного вызова в compute.

**STOR-1-08 / CS1-S4-02 — повтор привязки идемпотентен.**
Трассировка: `TestAttachIdempotentReplay`, `TestDetachIdempotent`.
**Given** том `V` уже привязан к инстансу `I`.
**When** тот же `Attach` повторяется с теми же значениями.
**Then** вызов завершается успешно, привязка остаётся одна, `attachedAt` не меняется.

**STOR-1-07 / CS1-S4-03 — привязка чужой машиной отвергается.**
Трассировка: `TestAttachDoubleRace` (конкурентный, под `-race`: ровно один победитель), `TestAttachVolumeNotReady`.
**Given** том `V` привязан к инстансу `I1`.
**When** приходит `Attach(volumeId=V, instanceId=I2)`.
**Then** `FAILED_PRECONDITION` с текстом `Volume <V> is in use`.

**STOR-1-10 / CS1-S4-05 — зона машины не совпадает с зоной тома.**
Трассировка: `TestAttachZoneProjectMismatch` (утверждает точный текст, не только код).
**Given** том `V` в зоне `Z1`.
**When** приходит `Attach(volumeId=V, instanceZoneId=Z2, projectId=P)` при совпадающем проекте.
**Then** `FAILED_PRECONDITION` с текстом `Volume and Instance must be in the same zone`.

**STOR-1-10 / CS1-S4-05 — проект машины не совпадает с проектом тома.**
Трассировка: `TestAttachZoneProjectMismatch` — та же полоса CAS, **отдельный** ожидаемый текст.
**Given** том `V` в проекте `P1`, зона совпадает.
**When** приходит `Attach(volumeId=V, projectId=P2)`.
**Then** `FAILED_PRECONDITION` с **отдельным** текстом `Volume and Instance must be in the same project` (не текстом про зону).

**STOR-1-09 / CS1-S4-09 — второй загрузочный том в машине.**
Трассировка: `TestAttachSecondBoot`, `TestMapVolumeErrSecondBoot`.
**Given** у инстанса `I` уже есть привязка с `isBoot=true`.
**When** приходит `Attach` другого тома с `isBoot=true` к тому же `I`.
**Then** `FAILED_PRECONDITION` с текстом `Instance <I> already has a boot volume` (нарушение EXCLUDE).

**STOR-1-09 / CS1-S4-06,07,08 — явное имя устройства занято.**
Трассировка: `TestAttachDeviceCollision`, `TestMapVolumeErrDeviceCollision`, `TestAttachAutoDeviceName`, `TestAttachAutoDeviceNameRace` (под `-race`), `TestAttachNoFreeDevice`.
**Given** у инстанса `I` есть привязка с `deviceName=sdb`.
**When** приходит `Attach` с явным `deviceName=sdb`.
**Then** `FAILED_PRECONDITION` с текстом `device sdb is already in use on Instance <I>`.
**And** при **пустом** `deviceName` вместо отказа выбирается следующее свободное имя.

**STOR-1-12 / CS1-S1-07 — удаление привязанного тома.**
Трассировка: `TestVolumeDeleteFKRestrict` · newman `VOL-DEL-CRUD-OK` (позитивная ветка после detach).
**Given** том `V` привязан.
**When** клиент вызывает `DELETE /storage/v1/volumes/{V}`.
**Then** `Operation` завершается с `error`, код `FAILED_PRECONDITION`, текст `Volume <V> is in use`.
**And** строка тома остаётся на месте.

**CS1-S1-04 — размер только растёт.**
Трассировка: `TestVolumeSizeIncreaseOnly` · newman `VOL-UPD-SIZE-EQUAL-REJECT`, `VOL-UPD-SIZE-SHRINK-REJECT`, `VOL-UPD-SIZE-GROW-OK`.
**Given** том `V` размером 10 GiB.
**When** `PATCH /storage/v1/volumes/{V}` с `updateMask=[size_bytes]`, `sizeBytes` = 10 GiB (равный) либо меньше.
**Then** `Operation` завершается с `error`, код `INVALID_ARGUMENT`, текст `Volume size can only be increased`.
**And** при большем значении операция успешна и `Get` отдаёт новый размер.

**CS1-S1-05 — иммутабельное поле в маске.**
Трассировка: `TestUpdateImmutableField` (все три ресурса), `TestUpdateSourceImageImmutable` · newman `VOL-UPD-MASK-IMMUTABLE-ZONE`, `-DISKTYPE`, `-BLOCKSIZE`, `-SOURCESNAPSHOT`, `VOL-UPD-MASK-UNKNOWN-FIELD`.
**Given** том `V`.
**When** `PATCH` с `updateMask=[zone_id]`.
**Then** синхронный `INVALID_ARGUMENT` с текстом `zone_id is immutable after Volume.Create` (**не** generic «unknown field»: иммутабельные отвергаются до проверки known-set).

**CS1-S1-10 — посев из чужого приватного снимка.**
Трассировка: `TestSourceCrossProjectHiddenAsNotFound`, `TestVolumeDiskTypeAndSnapshotFK` · newman `VOL-CR-NEG-SNAPSHOT-NOTFOUND`, `VOL-CR-NEG-DISKTYPE-NOTFOUND`.
**Given** снимок `S` принадлежит проекту `P2`, вызывающий работает в `P1`.
**When** `POST /storage/v1/volumes` с `projectId=P1`, `sourceSnapshotId=S`.
**Then** `Operation` завершается с `error`, код `FAILED_PRECONDITION`, текст `Snapshot <S> not found` — **байт-в-байт** тот же, что при несуществующем id.

**STOR-1-19 — boot-том из образа чужого региона.**
Трассировка: `TestVolumeSourceImageForeignRegionRejected`, `TestVolumeSourceImageSameRegionSeeded`, `TestCreateBootVolume_ZoneRegionUnavailable_FailsClosed`, `TestVolumeWithoutSourceUnaffectedByRegion`.
**Given** образ `IMG` в регионе `R1`, зона `Z` принадлежит региону `R2`.
**When** `POST /storage/v1/volumes` с `zoneId=Z`, `sourceImageId=IMG`, размером ≥ `minDiskBytes`.
**Then** `Operation` завершается с `error`, код `FAILED_PRECONDITION`, текст `Image <IMG> not found` (образ вызывающему мог быть невиден — причину не раскрываем).

**STOR-1-18 / STOR-1-19 — boot-том меньше минимума образа.**
Трассировка: `TestVolumeSourceImageBelowMinDiskRejected`, `TestVolumeSourceImageAtMinDiskSeeded` (граница включительна), `TestVolumeSourceImageCrossProjectStillHidesMinDisk` (чужой образ **не** раскрывает число), `TestVolumeSourceSnapshotUnaffectedByMinDisk`.
**Given** образ `IMG` в регионе зоны `Z`, того же проекта, `minDiskBytes = 10 GiB`.
**When** `POST /storage/v1/volumes` с `zoneId=Z`, `sourceImageId=IMG`, `sizeBytes` = 5 GiB.
**Then** `Operation` завершается с `error`, код `INVALID_ARGUMENT`, текст `Volume size 5368709120 is less than image min_disk_bytes 10737418240`.
**And** при `sizeBytes` **ровно** `minDiskBytes` создание проходит (граница включительна).

**STOR-1-19 — два источника сразу (Volume).**
Трассировка: `TestCreateSourceMutualExclusion`, `TestVolumeValidate` · newman `IMG-VOL-CR-SOURCE-XOR`.
**Given** любой валидный проект и зона.
**When** `POST /storage/v1/volumes` одновременно с `sourceSnapshotId` и `sourceImageId`.
**Then** синхронный `INVALID_ARGUMENT` `a volume is seeded from either a snapshot or an image, not both` — до любого обращения к peer'ам и БД.

**STOR-1-24 — образ ровно из одного источника.**
Трассировка: `TestCreateSourceExactlyOne`, `TestCreateRejectsMissingSource`, `TestImageSourceMutualExclusionDBCheck` (DB-backstop ловит только «оба непусты») · newman `IMG-CR-VAL-SOURCE-NONE`, `IMG-CR-VAL-SOURCE-BOTH`.
**Given** валидные проект и регион.
**When** `POST /storage/v1/images` **без** обоих источников → синхронный `INVALID_ARGUMENT` `Image source is required`.
**And** с обоими → `an image source must be either a snapshot or a volume, not both`.

**CS1-S3-01 / CS1-S3-02 — снимок только с готового тома своего проекта.**
Трассировка: `TestSnapshotCreateFromReadyVolume`, `TestSnapshotCreateSourceNotReady`, `TestSnapshotCreateSourceMissing` · newman `SNP-CR-CRUD-OK`, `SNP-CR-VAL-SOURCE-REQUIRED`, `SNP-CR-NEG-SOURCE-MISSING`.
**Given** том `V` в проекте `P`.
**When** `POST /storage/v1/snapshots` с `sourceVolumeId=V`, `projectId=P` — операция успешна, `sizeBytes` снимка равен размеру тома.
**And** тот же вызов с томом чужого проекта → `FAILED_PRECONDITION "Volume <V> not found"`.

**STOR-1-28 — удаление источника не ломает потомка.**
Трассировка: `TestImageDeleteSetsVolumeSourceImageNull`, `TestImageSourceSnapshotDeleteSetNull`, `TestImageSourceVolumeDeleteSetNull`, `TestSnapshotDeleteFKSetNull` · newman `IMG-DEL-SETNULL-VOLUME-INTACT`.
**Given** образ `IMG` засеял том `V`; снимок `S` засеял образ.
**When** удаляются `S`, затем `IMG`.
**Then** обе операции успешны.
**And** `GET` тома `V` отдаёт `sourceImageId=""`, данные и размер тома не изменились.

**CS1-S2-05 — тип диска в использовании.**
Трассировка: `TestDiskTypeDeleteFKRestrict`, `TestDiskTypeDeleteFKRestrictRace` (конкурентный).
**Given** существует хотя бы один том типа `block-fast`.
**When** администратор вызывает `DELETE /storage/v1/diskTypes/block-fast` на internal-mux.
**Then** `FAILED_PRECONDITION "DiskType block-fast is in use"`.

> [!important] Три следующих сценария — про **слой**, и прежняя редакция путала слои
> `List` гейтится per-RPC Check **на шлюзе, раньше бэкенда**: `viewer` на области `project:{project_id}` (`proto/kacho/cloud/storage/v1/volume_service.proto:34-44`; зеркало — `internal/check/permission_map.go:84`). Значит вызывающий **без единого гранта в проекте** до сервисной логики вообще не доходит — он получает отказ по правам, и никакая сервисная гарантия на нём не наблюдаема (это задокументированное authz-first поведение платформы, `testing.md` §«negative-authz-ordering толерантность»). Прежние формулировки задавали `Given` «ни одного гранта» и требовали сервисный исход — такой сценарий не может пройти **никогда**, и его «зелёность» означала бы, что проверяют не то. Ниже `Given` приведён к тому уровню, на котором утверждение реально наблюдаемо: **project-tier `viewer` есть, per-object грантов нет**. Ровно так устроены и живые кейсы: `VOL-LST-PAGE-TOKEN-GARBAGE` шлёт мусорный маркер **дефолтным актором** (у него editor на проект сюиты), а `_assert_absent` в `cases/authz.py:215-228` принимает `200` **или** `403` и в обеих ветках требует отсутствия чужого id.

**CS1-S1-13 / STOR-1-31 — видимость списка пообъектная.**
Трассировка: `TestList_HidesVolumesWithoutPerObjectGrant`, `TestList_HidesSnapshotsWithoutPerObjectGrant`, `TestList_HidesImagesWithoutPerObjectGrant`, `TestList_KeepsGrantedVolumesInCursorOrder`, `TestFGAFilter_FiltersPageAndPreservesOrder` · newman `AUTHZ-VOL-LST-OVERSHOW-LEAK-GUARD`, `AUTHZ-SNP-…`, `AUTHZ-IMG-…`, `AUTHZ-VOL-LIST-OWN-ALLOW-NOLEAK`.
**Given** в проекте `P` три тома, и вызывающий имеет **project-tier `viewer` на `P`** (иначе шлюз отвергнет `List` до фильтра).
**And** per-object грант выдан **только на один** из трёх томов.
**When** `GET /storage/v1/volumes?projectId=P`.
**Then** страница содержит **ровно один** том — тот, на который есть грант; двух остальных id в ответе нет.
**And** порядок курсора сохранён — фильтр не переупорядочивает страницу.
**And** страница может вернуться неполной — это нормально для курсорной пагинации: маркер следующей страницы берётся от последней **просмотренной** строки, поэтому обход не пропускает строк.
**And** известный размен (не дефект): `nextPageToken` может кодировать строку, недоступную вызывающему — содержимое всё равно закрыто, это цена курсорной семантики без пропусков.

**CS1-S1-03 / STOR-1-32 — формат проверяется раньше пообъектных прав.**
Трассировка: `TestList_PaginationValidatedBeforeVisibilityShortCircuit`, `TestList_PageTokenValidatedBeforeVisibilityShortCircuit`, `TestList_PageSizeValidatedBeforeVisibilityShortCircuit`, `TestList_EmptyPageSkipsIAM`, `TestListValidatePagination`, `TestListRequiresProjectID` · newman `VOL-LST-PAGE-TOKEN-GARBAGE`, `VOL-LST-BVA-PAGESIZE-OVER-MAX`, `VOL-LST-VAL-PROJECT-REQUIRED` (и паритетные `SNP-`/`IMG-`/`DT-`).
**Given** вызывающий прошёл project-tier Check на `P` (`viewer` на `project:P`), но **не имеет ни одного per-object гранта** внутри `P`.
**When** `GET /storage/v1/volumes?projectId=P&pageToken=<мусор>` либо `pageSize=1001`.
**Then** `INVALID_ARGUMENT` — формат отвергается **независимо** от того, что пообъектный грант пуст.
**And** это **не** пустая страница `200 {[]}`: порядок в use-case фиксирован и виден построчно — `projectId` (`internal/service/volume/volume.go:201-203`) → `page_size` (`:204-208`) → `filter` (`:211-217`) → чтение страницы курсором, где repo декодирует и проверяет маркер (`:218`) → фильтр видимости (`:233-239`). Прежняя редакция приписывала все пять шагов диапазону `:201-217`, в который два последних не входят — а именно они и решают, что мусорный маркер отвергается раньше пустого гранта. Поэтому empty-grant short-circuit не может обогнать валидацию.
**And** уровень наблюдения: сервисный (unit/handler) — там гарантия полная; на REST-пути она наблюдаема только для вызывающего, прошедшего project-tier Check, что и делают перечисленные newman-кейсы.

**STOR-1-31 (fail-closed ветка) — недоступность владельца прав не раскрывает список.**
Трассировка: `TestFGAFilter_IAMErrorFailsClosed`, `TestList_FilterErrorIsFailClosed` (все три ресурса), `TestFGAFilter_EmptySubjectFailsClosed`, `TestFGAFilter_ResponseLengthMismatchFailsClosed`, `TestFGAFilter_OperationBudgetCapsHangingPeer`, `TestFGAFilter_FirstErrorWinsAndCancelsSiblings`, `TestFGAFilter_FailOpenReturnsUnfilteredPage` (ветка явной ручки деградации).
**Given** iam не отвечает **на пообъектном `BatchCheck`**, режим по умолчанию (fail-closed).
**When** сервис исполняет `Volume.List` для вызывающего, чей project-tier Check уже прошёл.
**Then** `UNAVAILABLE`; нефильтрованная страница не отдаётся ни при каких условиях.
**And** уровень наблюдения: сервисный. На REST-пути полная недоступность iam роняет **и** per-RPC Check самого шлюза, поэтому клиент увидит отказ шлюза, а не эту ветку — сценарий проверяется unit-тестами фильтра с подставным клиентом iam, а не e2e-обрывом сети.
**And** деградация возможна **только** явной ручкой (`…_LIST_FILTER_FAIL_OPEN`), каждое срабатывание пишет audit-WARN, а production boot-guard вообще не даёт стартовать с выключенным фильтром.

**STOR-1-27 / задача #73 — снятие метки отзывает выданный по ней доступ.**
Трассировка: `TestVolumeUpdate_LabelChange_ReEmitsRegisterIntentWithNewLabels`, `TestSnapshotUpdate_LabelChange_…`, `TestImageUpdate_LabelChange_…`, `TestVolumeUpdate_LabelsCleared_UpsertsEmptyNotUnregister`, `TestVolumeUpdate_WithoutLabels_EmitsNothing`.
**Given** доступ к тому `V` выдан селектором по метке `team=platform`.
**When** `PATCH /storage/v1/volumes/{V}` с `updateMask=[labels]` и телом без этой метки.
**Then** операция успешна, и в очередь регистраций уходит **регистрация** (не снятие) с новым набором меток.
**And** после дренажа доступ, выданный по снятой метке, перестаёт действовать; owner-доступ владельца сохраняется.

**STOR-1-27 (delete-ветка) — удаление снимает регистрацию с надгробием.**
Трассировка: `TestVolumeDelete_EmitsFGAUnregisterIntent`, `TestSnapshotDelete_EmitsFGAUnregisterIntent`, `Test_RegisterApplier_ForwardsTombstoneOnUnregister`, `Test_RegisterApplier_UnregisterZeroSourceVersion_ForwardsNil`, `TestVolumeInsert_FailedFK_NoFGAIntent`, `TestFGARegisterOutbox_PartitionHeadIndexCreated` · newman `SECD-DEL-NEG-NOT-FOUND`.
**Given** том `V` существует и зарегистрирован.
**When** `DELETE /storage/v1/volumes/{V}` успешно завершается.
**Then** в очередь уходит строка `fga.unregister` с непустым `source_version`.
**And** после дренажа зеркало объекта в iam не воскресает при доставке более старой регистрации того же объекта.

**STOR-1-11 / STOR-1-29 — недоступность geo/iam не пропускает мутацию.**
Трассировка: `TestCreatePeerValidatesZone`, `TestCreatePeerValidatesRegion`, `TestCreatePeerValidatesProject`, `TestCreatePeerValidatesProjectUnavailable`, `TestCreateBootVolume_ZoneRegionUnavailable_FailsClosed`, `TestCreatePlainVolume_DoesNotResolveZoneRegion` (лишнего вызова geo нет) · newman `VOL-CR-NEG-ZONE-UNKNOWN`, `VOL-CR-NEG-PROJECT-NOTFOUND`, `IMG-CR-NEG-REGION-UNKNOWN`, `IMG-CR-NEG-PROJECT-NOTFOUND`.
**Given** geo (или iam) не отвечает.
**When** `POST /storage/v1/volumes` с валидным телом.
**Then** синхронный `UNAVAILABLE` (`geo zone validation unavailable` / `iam project validation unavailable`); строка не создаётся.

**Без acceptance-id (покрыт только newman) — чужая операция неотличима от несуществующей.**
Трассировка: newman `OP-GET-CONF-NF-TEXT`, `OP-GET-NEG-NOTFOUND-VALID-PREFIX`, `OP-GET-NEG-UNKNOWN-PREFIX`, `OP-CANCEL-NEG-NOTFOUND`, `OP-CANCEL-NEG-UNKNOWN-PREFIX`, `OP-CANCEL-NEG-ALREADY-DONE`, `OP-GET-CRUD-OK`, `OP-GET-CRUD-FAILED-OP`. Acceptance-сценария на ownership операции **нет ни в одном** из двух доков (`CS1-S1-15` — это `Volume.ListOperations`, другой предмет); Go-теста на ownership-предикат в storage тоже нет — он живёт в corelib (`pkg/operations`). Пробел в трассировке назван, а не замаскирован подходящим по звучанию id.
**Given** операция `sop…` создана **другим тенантным принципалом** (`user:usr-…`).
**When** вызывающий поллит `OperationService.Get(sop…)`.
**Then** `NOT_FOUND` — тот же ответ, что и на выдуманный id (решает ownership-предикат в SQL, `pkg/operations/repo.go:201-205`).

**Без acceptance-id (покрыт только Go) — анонимный контекст против операции системного владельца.**
Трассировка: `TestOperationGet_AnonymousContextGetsNotFound`, `TestOperationGet_ExplicitlyClearedPrincipalGetsNotFound`, `TestOperationCancel_AnonymousContextGetsNotFound`, `TestOperationGet_AuthenticatedOwnerStillServed`, `TestOperationGet_ExplicitSystemPrincipalStillServed` (`services/storage/internal/handler/operation_ownership_test.go:87,105,117,132,152`) · на уровне corelib — `TestOwnerFromContext_AnonymousYieldsNoOwner`, `TestOwnerFromContext_ClearedPrincipalYieldsNoOwner`, `TestOwnerFromContext_ExplicitPrincipalYieldsOwner`, `TestOwnerFromContext_ExplicitSystemPrincipalYieldsOwner`, `TestOwnedRepo_ZeroOwnerNeverReachesPredicate` (`pkg/operations/owner_anonymous_test.go:27,35,44,54,66`). Newman-покрытия нет by design: путь требует контекста **без** принципала, а внешний REST-путь всегда аутентифицирован шлюзом.
**Given** операция принадлежит `{system,bootstrap}` (фикстура `systemOwnedRepo` строит ровно такую строку — это то, что производит фоновая запись).
**When** `Get`/`Cancel` вызывается с контекстом без принципала — либо с контекстом после `WithoutPrincipal` (форма, которую даёт недоверенный форвардер).
**Then** `NOT_FOUND` с текстом `operation <id> not found` — **байт-в-байт** тот же, что получает посторонний; `Cancel` при этом **ничего не отменяет** (утверждается флагом `cancelled == false`, а не только кодом ответа).
**And** сужение проверено с обеих сторон: подлинный владелец и **явно** установленный системный принципал по-прежнему получают свою операцию — правка обязана сужать, а не ломать.
**And** репозиторный бэкстоп доказан устройством теста: `TestOwnedRepo_ZeroOwnerNeverReachesPredicate` конструирует репозиторий с **nil-пулом**, поэтому попадание в SQL было бы паникой, а не тихим прохождением.

**Без acceptance-id (покрыт только Go) — небезопасная конфигурация не стартует.**
Трассировка: `TestValidate_productionRefusesInsecure`, `TestValidate_productionRequiresMTLS`, `TestValidate_productionRequiresAuthz`, `TestValidate_productionRequiresDBSSL`, `TestValidate_productionRequiresListFilter`, `TestValidate_productionStrictRequiresStrictSSL`, `TestValidate_productionSecureOK`, `TestValidate_unknownMode`, `TestLoad_defaultAuthModeProduction`, `TestBootPosture_Production`, `TestBootPosture_EmittedFromTheLiveBootPath`, `TestBootPosture_InsecureIsReportedHonestly`.
**Given** `AUTH_MODE=production` и любое из: mTLS выключен на одном из слушателей, не задан адрес авторизации, `DB_SSLMODE=disable`, выключен пообъектный фильтр списков.
**When** процесс стартует.
**Then** процесс **отказывается подниматься** с перечислением всех нарушений; слушатели не открываются.
**And** самоотчёт о посадке берётся **с живого boot-пути** и читает `db_sslmode` из строки подключения, реально уходящей в пул (`TestBootPosture_EmittedFromTheLiveBootPath`) — «под Ready» доказательством посадки не является.

**CS1-S2-04 — admin-CRUD каталога не исполняется внешним тенантом.**
Трассировка: `TestExternalListener_RejectsDiskTypeAdminRoutes`, `TestInternalListener_ServesDiskTypeAdminRoutes`, `TestExternalListener_DiskTypePublicReadsStillServed`, `TestAllInternalRESTBindings_ClassifiedInternal` (`gateway/internal/restmux/internal_catalog_isolation_test.go:60,84,110,140`) · newman `DT-CR-NEG-EXTERNAL-ABSENT`, `DT-UPD-NEG-EXTERNAL-ABSENT`, `DT-DEL-NEG-EXTERNAL-ABSENT`.
**Given** вызывающий — внешний тенант без `system_admin` на кластерном синглтоне.
**When** он шлёт `POST /storage/v1/diskTypes` (пустой `id`) либо `PATCH`/`DELETE /storage/v1/diskTypes/<несуществующий>` на **внешний** слушатель.
**Then** запрос отвергается **никогда не 200 и без единой мутации каталога**; на уровне маршрутизации гарантия строгая — `404` **до** обработчика (`http.NotFound`, `mux.go:804`), и именно её утверждает Go-замок.
**And** ожидание чёрного ящика — `oneOf([401,403,404])`, и это **ужесточение** нынешнего `oneOf([400,403,404,405,501])` в кейсах: `400`, `405` и `501` теперь **недостижимы by construction** — диспетчер 404-ит пару (метод, путь) раньше, чем какой-либо обработчик успел бы провалидировать тело (сопутствующая ветка `if code === 400 → json().code === 3` в `disk-type.py:104` становится мёртвой). Строгий `404` в чёрном ящике **некорректен**: `authzMW.HTTP` обёрнут **снаружи** REST-диспетчера, поэтому для аутентифицированного не-админа `403` приходит **раньше** 404-гейта, а для запроса без учётных данных — `401`. Это то самое authz-first упорядочение, которое платформа уже документирует.
**And** если кейс всё же нужен строго на `404`, он обязан различать **два разных** 404: existence-hiding от диспетчера — `text/plain`, тело `404 page not found`; отказ модели прав — `application/json` с `{"code":5}`. Без этого различения «404» не доказывает отсутствия маршрута.

**CS1-S3-03 (недостающая ветка) — синхронная валидация описания и меток на создании снимка.**
Покрытия нет ни в Go, ни в newman, и **самой проверки тоже нет**: `Snapshot.Create` не вызывает ни `validate.Description`, ни `validate.Labels` (у тома — `volume.go:259,262`, у образа — `image.go:235,238`). Сценарий якорится на **существующий** `CS1-S3-03` («`Snapshot.Create` — peer-validate `projectId` + input-валидация (sync)»), который сегодня описывает только форму имени. Требуемый RED (пишется первым): **Given** валидный проект и READY-том своего проекта; **When** `POST /storage/v1/snapshots` с `description` длиной 257 (либо 65 ключей меток); **Then** синхронный `INVALID_ARGUMENT` **до** peer-вызова в iam и до постановки `Operation` — сегодня возвращается `Operation`, а отказ приезжает позже как `Operation.error "Illegal argument"` без имени поля. Это **дыра, а не умолчание**; исход — задача #80, критерий приёмки — в «Незакрытое», п. 8.

**STOR-1-19 (обратное направление) — образ и зона его источника когерентны.**
Трассировка: `TestImageSourceVolumeForeignRegionRejected`, `TestImageSourceVolumeSameRegionSeeded`, `TestImageSourceSnapshotFollowsLineageRegion`, `TestImageSourceSnapshotSameRegionSeeded`, `TestImageSourceSnapshotWithoutLineageUnaffected` (`internal/repo/pg/image_source_region_integration_test.go`) · newman — шаг `pre-zone-region-coherent-*` в коллекции `image`.
**Given** том `V` в зоне `Z`, принадлежащей региону `R1`.
**When** `POST /storage/v1/images` с `regionId=R2`, `sourceVolumeId=V`.
**Then** `Operation` завершается с `error` — образ не создан: полоса CAS требует, чтобы зона живой строки источника входила в список зон региона образа.
**And** при `regionId=R1` образ создаётся; для источника-снимка сверяется зона **тома происхождения**, а снимок с занулённым происхождением (источник удалён) проверкой не затрагивается.
**And** список зон региона берётся у geo (`ZonesOfRegion`) **до** постановки `Operation` — недоступность geo видна синхронно (`UNAVAILABLE`), а не прячется в асинхронный отказ; и спрашивается **только** когда источник задан: без источника сверять нечего, и образ без источника не становится заложником доступности geo.

---

## Негативные сценарии и граничные значения

| Вход | Граница | Исход |
|---|---|---|
| `pageSize` | `0` | подставляется значение по умолчанию |
| `pageSize` | `1000` / `1001` | принимается / `INVALID_ARGUMENT` (**отвергается, не обрезается**) |
| `pageToken` | мусор | `INVALID_ARGUMENT` (до обращения к правам) |
| `projectId` в List | пусто | синхронный `INVALID_ARGUMENT "projectId is required"` — иначе вернулись бы строки всех проектов |
| `filter` | `name=<v>` / любое другое поле | принимается / `INVALID_ARGUMENT` (whitelist) |
| `name` | пусто | легально; partial UNIQUE не действует, два безымянных тома в проекте допустимы |
| `name` | 63 / 64 символа, верхний регистр, не-ASCII | принимается / `INVALID_ARGUMENT` — **текст зависит от слоя**, см. ниже |
| `description` на **Create** Volume / Image | 256 / 257 | принимается / `INVALID_ARGUMENT` **синхронно**, до peer-вызовов и БД |
| `description` на **Create Snapshot** | 256 / 257 | принимается / `INVALID_ARGUMENT` **асинхронно** и **без имени поля** (`Operation.error "Illegal argument"`) — задача #80, см. ниже |
| `description` на **Update** (все три) | 256 / 257 | принимается / `INVALID_ARGUMENT` **асинхронно** — приезжает как `Operation.error`, задача #78, см. ниже |
| `labels` на **Create** Volume / Image | 64 / 65 ключей, значение 63 / 64 | принимается / `INVALID_ARGUMENT` синхронно |
| `labels` на **Create Snapshot** | 64 / 65 ключей | принимается / `INVALID_ARGUMENT` **асинхронно**, обобщённый текст — задача #80 |
| `labels` на **Update** (все три) | 64 / 65 ключей | принимается / `INVALID_ARGUMENT` **асинхронно**, задача #78 |
| `name` на **Update** Volume / Image | форма | `INVALID_ARGUMENT "Illegal argument name"` **синхронно** |
| `name` на **Update Snapshot** | форма | `INVALID_ARGUMENT "Illegal argument"` **асинхронно, без имени поля** — задачи нет, см. п. 13 «Незакрытое» |
| `sizeBytes` на Create | `0` или отрицательное | `INVALID_ARGUMENT` — текст зависит от слоя, см. ниже |
| `sizeBytes` на Update | равный текущему | `INVALID_ARGUMENT "Volume size can only be increased"` (строгое `>`) |
| `sizeBytes` vs `minDiskBytes` | ровно равен / на байт меньше | принимается / `INVALID_ARGUMENT` с обоими числами |
| id ресурса | неверный префикс/форма | синхронный `INVALID_ARGUMENT "invalid volume id '<X>'"` **первым стейтментом** |
| id ресурса | форма верна, строки нет | `NOT_FOUND "<Resource> <id> not found"` |
| `updateMask` | неизвестное поле | `INVALID_ARGUMENT` (known-set) |
| `updateMask` | иммутабельное поле | `INVALID_ARGUMENT "<field> is immutable after <Resource>.Create"` — **раньше** проверки known-set |
| `updateMask` | пустой | full-object PATCH; иммутабельные из тела молча игнорируются |
| имена устройств | 25 занятых (`sdb..sdz`) | `FAILED_PRECONDITION "no free device name on Instance <id>"` |
| страница фильтра | >100 id | режется на батчи ≤100; расхождение длины ответа — ошибка, не «отказ» |
| некатегоризированная ошибка БД | любой неизвестный SQLSTATE | наружу фиксированное `internal error`; SQLSTATE и имя констрейнта пишутся **только** в лог |

### Какой слой производит какую строку — тексты объявлены контрактом, значит различать обязательно

Один и тот же инвариант ловится **двумя** слоями, и они дают **разные** строки. Прежняя редакция таблицы приписывала точный доменный текст обоим — это делало контракт непроверяемым (регрессия, ждущая `"Illegal argument size_bytes"` от DB-полосы, красная навсегда).

| Инвариант | Доменный слой (sync, точный текст) | DB-backstop (23514, обобщённый текст) |
|---|---|---|
| `sizeBytes > 0` | `INVALID_ARGUMENT "Illegal argument size_bytes"` (`internal/domain/volume.go:38-40`) | `INVALID_ARGUMENT "Illegal argument"` — **без имени поля** (`internal/repo/pg/errmap.go:88`) |
| форма `name` | `INVALID_ARGUMENT "Illegal argument name"` (там же) | `"Illegal argument"` — там же; для snapshot `errmap.go:141`, для image `errmap.go:200` |
| длина `description`, форма `labels` | `INVALID_ARGUMENT` с текстом corelib-валидатора | `"Illegal argument"` |

> [!warning] «Синхронный слой стоит на Create всех трёх ресурсов» — это было третье описание несуществующего механизма
> Здесь стояло: «Доменный слой стоит на `Create` **всех трёх** ресурсов и на `name` в `Update`». **Кодом это не держится ни в одной половине.** Проверено построчно (`grep -n "validate\." services/storage/internal/service/*/[a-z]*.go`) — синхронная валидация распределена так:
>
> | Ресурс | `Create`: `name` | `Create`: `description` / `labels` | `Update`: `name` | `Update`: `description` / `labels` |
> |---|---|---|---|---|
> | Volume | ✅ домен (`volume.go:254` → `VolumeName`) | ✅ `volume.go:259,262` | ✅ `volume.go:455-458` | ❌ |
> | Image | ✅ домен (`image.go:229` → `ImageName`) | ✅ `image.go:235,238` | ✅ `image.go:376-379` | ❌ |
> | **Snapshot** | ✅ домен (`snapshot.go:201` → `SnapshotName`) | ❌ **не вызывается вовсе** | ❌ **`resolveUpdate` (`snapshot.go:298-324`) не валидирует даже имя** | ❌ |
>
> `Snapshot.Create` зовёт только `s.Validate()` (`internal/domain/snapshot.go:81-92`: `project_id`, `source_volume_id`, форма `name`, диапазон статуса) — ни `validate.Description`, ни `validate.Labels` в файле нет. Опасность формулировки ровно та, которую документ сам объявляет провалом: «на Create валидируется» звучит как гарантия и снимает вопрос, а для снимка гарантии нет.

**Когда срабатывает какой — по факту.** Всё, что не отмечено ✅ выше, доезжает до `INSERT`/`UPDATE`, ловится DB-CHECK'ом уже в **асинхронном воркере** и возвращается клиенту как `Operation.error` с обобщённым `"Illegal argument"` — **без имени поля** и после постановки операции. Наблюдаемо и по чёрному ящику: BVA-кейсы на превышение описания/меток есть только у образа (`IMG-CR-BVA-DESC-OVER-257`, `IMG-CR-BVA-LABELS-OVER-65`), у тома проверка в коде есть, а кейса нет, у снимка нет ни того ни другого (`SNP-CR-BVA-NAME-OVER-64` — единственный BVA снимка на Create). Go-тест на эту границу тоже один — `TestCreateBVADescriptionLabels` (только image).

Отсюда **три разных исхода, и они не сливаются в один**:

1. **`Snapshot.Create` не валидирует `description`/`labels`** — том и образ валидируют. **Исход — задача #80.** Критерий приёмки (формулируется **прямо**, а не «как на Create» — для снимка «как на Create» означает «никак»): в `Snapshot.Create`, **до** peer-вызова в iam и до постановки `Operation`, вызываются `validate.Description("description", …)` и `validate.Labels("labels", …)` — те же два вызова, что стоят в `volume.go:259,262` и `image.go:235,238`; RED пишется первым — unit `TestCreateBVADescriptionLabels` в `internal/service/snapshot` (описание 257 символов и 65 ключей меток при валидном источнике → sync `INVALID_ARGUMENT`, сегодня возвращается `Operation` с `done=false`); чёрный ящик — два новых кейса `SNP-CR-BVA-DESC-OVER-257` / `SNP-CR-BVA-LABELS-OVER-65` по образцу образа, плюс парные `VOL-CR-BVA-*` (проверка есть, кейса нет); закрытие — прогон `go test ./services/storage/internal/service/... -count=1` зелёный и коллекция `snapshot` в `run.sh` зелёная (`assertions.failed == 0`). Сценарий якорится на **существующий** id `CS1-S3-03` («`Snapshot.Create` — peer-validate + input-валидация (sync)»), в который добавляются строки про описание и метки; нового пространства имён не заводится.
2. **`Update` не валидирует `description`/`labels` ни у одного из трёх ресурсов** — расхождение Create↔Update. **Исход — задача #78 (STOR-VAL-1).** Критерий приёмки: `resolveUpdate` **каждого** из трёх ресурсов вызывает `validate.Description`/`validate.Labels` для полей, попавших в маску (и для всех mutable-полей при пустой маске); RED первым — `PATCH` с `description` в 257 символов даёт **синхронный** `INVALID_ARGUMENT` до постановки операции (сегодня приходит `Operation.error`); закрытие — три unit-теста (по одному на ресурс) зелёные в прогоне `go test ./services/storage/internal/service/... -count=1` + кейсы `VOL-/SNP-/IMG-UPD-BVA-DESC-OVER-257` зелёные в своих коллекциях. DB-CHECK остаётся backstop'ом, его обобщённый текст сохраняется как есть — он не должен называть поле, чтобы не дублировать доменный словарь.
3. **`Snapshot.Update` не валидирует и `name`** — у тома и образа `resolveUpdate` прогоняет доменный newtype, у снимка нет, поэтому `PATCH` с `name=Bad_Name` даёт не sync `"Illegal argument name"`, а асинхронный обобщённый `"Illegal argument"` из DB-CHECK. Этого **нет ни в #80** (он про `Create`), **ни в #78** (он про `description`/`labels`) — пункт **требует отдельной задачи, она не заведена**; номер не выдумывается. Критерий будущей задачи: `resolveUpdate` снимка вызывает `domain.SnapshotName(name).Validate()` в ветке `apply("name")` — паритет с `volume.go:455-458`; RED первым (`PATCH` снимка с uppercase-именем → sync `INVALID_ARGUMENT "Illegal argument name"`), закрытие — кейс `SNP-UPD-VAL-NAME-UPPERCASE` зелёный в коллекции `snapshot` и unit зелёный в `./services/storage/internal/service/snapshot/`.

---

## Наблюдаемость и посадка процесса

- **Boot-guard** (`Config.Validate`) в `production` / `production-strict` отказывает в старте, если: `DB_SSLMODE` пуст или `disable` (в strict — не из `require|verify-ca|verify-full`); mTLS выключен **на любом** из двух слушателей; не задан адрес авторизации (иначе интерсептор `Check` просто не подключится); выключен пообъектный фильтр списков. Режим по умолчанию — `production`.
- **Самоотчёт о посадке** пишется при старте и берёт `db_sslmode` **из строки подключения, реально уходящей в пул**, а не из поля конфига: смысл самоотчёта — рассказывать об исходе, а не о намерении.
- **Диагностический HTTP** отдаёт `/healthz` (адрес настраивается, пустой — выключает).
- **Аудит-след ошибок**: непереведённые SQLSTATE логируются с кодом и именем констрейнта на границе repo, наружу уходит фиксированный текст.
- **Дренаж очереди** логируется отдельным компонентом; каждое срабатывание деградации фильтра списков пишет WARN.
- **Graceful shutdown**: оба слушателя останавливаются мягко, затем до 30 s дренажа незавершённых LRO — чтобы асинхронная мутация не осталась `done=false` навсегда.
- **Метрики есть, и монитор указывает на путь, который процесс действительно обслуживает** (закрыто задачей #76, дефект 3). Реестр **приватный** (`prometheus.NewRegistry`, не глобальный default — `internal/observability/metrics/metrics.go:69-95`), выставлен на **том же** диагностическом слушателе, что и `/healthz` (`ports.metrics: 9095`, cluster-internal; `cmd/storage/serve.go:248`), и объявлен в чарте портом `metrics` (`deploy/templates/service.yaml:19-21`, `deployment.yaml:103-104`) — именно его и скрейпит `ServiceMonitor`. Серии ведутся от рисков очереди регистраций, а не «на всякий случай»: `kacho_storage_outbox_backlog_depth`, `kacho_storage_outbox_oldest_pending_age_seconds`, `kacho_storage_outbox_poisoned_rows`, `kacho_storage_outbox_poisoned_total`. `ServiceMonitor` по умолчанию **выключен** (`values.yaml:92`) — включение остаётся решением эксплуатации, но теперь оно не приводит к сбору пустоты.
  Залочено тремя тестами, причём третий утверждает **соответствие шаблона процессу**, а не наличие файла: `TestDiagnosticListenerServesMetricsAndHealth`, `TestMetricsEndpointExposesOutboxSeries`, `TestServiceMonitorMatchesWhatTheProcessServes` (`cmd/storage/diagnostic_metrics_test.go:48,60,88`).

---

## Декомпозиция — что как приземлено

| Срез | Состав | Состояние по коду |
|---|---|---|
| Схема и инварианты | 0001–0004 (операции, домен, посев каталога) | приземлено; все инварианты — констрейнтами |
| Публичный CRUD Volume/Snapshot | use-case + repo + handler + LRO | приземлено |
| Привязка (S2) | `volume_attachments`, attach/detach/list на :9091, зеркало у compute | приземлено; `attached_disks` у compute снят миграцией 0013 |
| Каталог DiskType | публичный read + admin CRUD на :9091 (синхронный) | приземлено |
| Образ (STOR-1) | 0007: `images` + `volumes.source_image_id`, публичный CRUD, `InternalImageService` | приземлено; инфра-поля зарезервированы; когерентность «зона источника ∈ регион образа» — внутри insert-CAS (#76-1) |
| Материализация прав | 0006 очередь + дренаж + синхронный регистратор + переэмит зеркала на смене меток | приземлено |
| Порядок и пропускная способность очереди | 0008 (индекс партиции), 0009 (индекс порядка), 0010 (autovacuum + ANALYZE) | приземлено |
| Пообъектная видимость списков | `authzfilter` (`viewer` — отношение `Get`) + требование в boot-guard | приземлено; паритет с каталогом залочен `TestVisibilityRelationsMatchCatalogGetRelation` / `TestPermissionMapMirrorsCatalog` (#75) |
| Наблюдаемость очереди регистраций | приватный prometheus-реестр + 4 серии на диагностическом слушателе; redrive-бэкстоп отравленных строк | приземлено (#76-2, #76-3) |
| Снятие мёртвой очереди | 0011 (`storage_outbox` без потребителя) | приземлено |
| Data-plane | инфра-проекции, реальные состояния жизненного цикла | **не начато — граница домена**, задачи нет by design («Осознанно не сделано», п. 1-3) |
| Завершение раскола с compute | ретайр дубля Disk/Image/Snapshot/DiskType | **не начато — задачи #37 (порядок фаз) и #61 (гейт удаления таблиц)**, критерий в «Незакрытое», п. 6 |

---

## DoD — наблюдаемые «пройдено / не пройдено»

Прежняя редакция этого раздела перечисляла **существующие артефакты** («тесты покрывают…», «кейсы: volume, snapshot…»). Такое утверждение остаётся истинным, даже если работа сломана или откачена: оно про наличие файлов, а не про исход прогона. На фоне уже наступавших у нас классов «прогонщик печатает GREEN при красном» и «набор рапортует зелёное, не выполнив коллекции» это не DoD, а инвентарь. Ниже — **гейты**: чем гонять, что обязано быть зелёным, что именно наблюдается и как отличить настоящий зелёный от ложного.

**Рабочий каталог и окружение — часть команды, а не подразумеваемый контекст.** Все команды ниже исполняются **из корня монорепо** (`project/kacho`); модуль один (`go.mod` в корне), поэтому `./services/…` и `./gateway/…` — пути одного модуля. Два условия проверены исполнением, а не предположены:

- **`GOWORK=off` обязателен в polyrepo-раскладке.** Рядом с монорепо лежит `project/go.work` (`use ./kacho-proto`, `./kacho-corelib`, … — старая polyrepo-раскладка). Go подхватывает его **из родительского каталога**, и любая go-команда в монорепо падает ещё до компиляции: `directory gateway/internal/restmux is contained in a module that is not one of the workspace modules listed in go.work` → `FAIL [setup failed]`. Это не «тест красный», это **тест не выполнялся** — ровно тот исход, который DoD обязан отличать от зелёного. В CI (single-repo checkout) go.work отсутствует, поэтому там префикс не нужен; локально — нужен всегда.
- **`make`-цели живут в подкаталогах, и вызов из корня без `-C` не существует.** Проверено: `make audit-list-filter` в корне → `make: *** No rule to make target 'audit-list-filter'` (корневого `Makefile` в монорепо нет вовсе). Команды ниже несут `-C` явно.

| # | Гейт (команда) | Порог | Что именно наблюдается / как ловится ложный зелёный |
|---|---|---|---|
| 1 | `GOWORK=off go test ./services/storage/... -race -count=1` | **0 fail**, ненулевое число выполненных пакетов | **Без `-short`**: флаг скипает testcontainers-слой, и весь integration-ярус (attach-CAS, FK/EXCLUDE/UNIQUE, полосы insert-CAS, индекс головы партиции) молча не исполняется. «129 пакетов зелёные» под `-short` — уже маскировало регрессию. `-race` обязателен: четыре конкурентных теста (`TestAttachDoubleRace`, `TestAttachAutoDeviceNameRace`, `Test*NameUniqueRace` ×3, `TestDiskTypeDeleteFKRestrictRace`) без него вырождаются в последовательные и ничего не доказывают. **Что наблюдает CI — не эта команда, и разницу надо знать:** job `build · vet · gofmt · test -race` гоняет `go test ./... -race -short` (`.github/workflows/ci.yaml:55`) — то есть **с** `-short`; testcontainers-ярус поднимает отдельный job `integration (storage)` матрицы, и он берёт **только** пакеты, чей путь содержит `internal/repo` или `internal/clients` (отбор — `ci.yaml:95`, прогон — `ci.yaml:98`); у storage под этот отбор попадают ровно **два** пакета — `internal/clients` и `internal/repo/pg` (проверено `go list` по тому же фильтру). Значит `internal/service/*`, `internal/authzfilter`, `internal/check`, `tools` в CI видны только под `-short`; локальный полный прогон этой строки — единственное место, где они идут в полной форме. |
| 2 | `GOWORK=off go test ./gateway/internal/restmux/ -run 'TestStorage\|TestRedesign_InternalRoutes\|TestExternalListener\|TestInternalListener\|TestAllInternalRESTBindings' -count=1` | **12 PASS из 12** тест-функций, 0 fail | Прогнано при написании этой строки: **12/12 PASS, 0 fail, 0.051 s**. Фильтр обязан покрывать **три** файла, и каждое расширение вызвано тем, что предыдущая форма молча недосчитывала маршруты. `TestStorage*` (`storage_test.go:35`, `:81`, `:114`) — регистрация публичных маршрутов, обслуживание `InternalVolumeService` на внутреннем и внешний **404** для его **четырёх** методов. Пятый `Internal*`-маршрут, `InternalImageService/GetInternal`, лежит в `TestRedesign_InternalRoutes_ExternalListenerRejected` (`redesign_reg_test.go:110-134`), и `-run TestStorage` его **не запускает** — редакция до прошлой засчитывала 5/5 при реально исполняемых 4/5. Admin-CRUD каталога утверждается **третьим** файлом (`internal_catalog_isolation_test.go`) под именами `TestExternalListener_*` / `TestInternalListener_*` / `TestAllInternalRESTBindings_*`, которых не матчит ни один из двух прежних префиксов, — поэтому в фильтре теперь пять альтернатив. Заодно фильтр подхватывает пред-существующие `TestExternalListener_RejectsInternalPaths_404` / `TestInternalListener_ServesInternalPaths` / `TestExternalListener_PublicPathsStillServed` (`external_isolation_test.go`) — это не шум, а тот же инвариант на остальных доменах. В ячейке таблицы `\|` экранирован — при копировании экранирование снимается: в `-run` Go трактует `\|` как **литеральный** символ, и фильтр не матчит ничего (гейт молча выполнил бы ноль тестов). Гейт больше **не** частичный по поверхности `Internal*`: `TestAllInternalRESTBindings_ClassifiedInternal` обходит REST-биндинги каждого `Internal*`-сервиса каждого домена и падает явно на пустом обходе, а не проходит вакуумно. |
| 3 | `make -C gateway permission-catalog-check` | **byte-identical**, роняет сборку при дрейфе | Цель объявлена **только** в `gateway/Makefile:67-73`, из корня без `-C` её нет. Требует `buf` в `PATH` (артефакт генерируется, а не сравнивается «как есть»). **Что реально наблюдает CI:** job `authz-artifacts`, шаг `permission-catalog staleness + copy-drift` с `working-directory: gateway` (`ci.yaml:199-201`) — та же цель, тот же пин `buf 1.69.0` (`ci.yaml:181-183`), поэтому local-vs-CI дифф не фантомный. Обе embedded-копии (seed iam ↔ middleware шлюза) сверяются побайтно (`gateway/Makefile:69-72`). **Известное ослабление самого гейта:** сверка копии iam обёрнута в `if [ -f $(IAM_CATALOG) ]` (`:71`) — при отсутствующем файле шаг молча проходит, то есть «зелёный» здесь не доказывает наличия второй копии, только её несдвинутость. Непокрытый RPC = `catalog: no entry for method` = fail-closed 403 в рантайме, то есть RPC, не работающий ни при каких грантах. |
| 4 | `GOWORK=off go test ./services/storage/internal/check/ -run TestPermissionMap -count=1` | **6 PASS из 6**, 0 fail | Прогнано при написании строки: `TestPermissionMap_CoversEveryServedStorageRPC`, `…_InternalImageGetInternal_MirrorsGatewayCatalog`, `…_ObjectAndProjectScope`, `…_CatalogRPCsStayClusterScoped`, `…_ImageService_Mapped`, `…_CoreServices_Mapped` — **6/6 PASS, 0.005 s** (фильтр матчит шесть функций, а не три, как перечисляла прежняя редакция). Полнота карты доказывается обходом protobuf-дескрипторов пакета `kacho.cloud.storage.v1`, а не ревью списка. **Зеркальность каталогу проверяет отдельный тест — и уже по артефакту, а не по литералам:** `TestPermissionMapMirrorsCatalog` (`internal/check/catalog_parity_test.go:34`, общий движок `pkg/authz/catalogparity`) сверяет **каждую** запись домена в сгенерированном `permission_catalog.json` с in-process картой по двум осям — отношение и тип области. Прежняя проверка покрывала **один** RPC и сравнивалась с литералами, переписанными в сам тест (форма без содержания); заменена в рамках #75. |
| 5 | `make -C services/storage audit-list-filter` (+ `TestAuditListFilter`, `TestAuditListFilter_RealTreePasses` в гейте №1) | `audit-list-filter: OK`, `rc=0` | **Команда исправлена**: `make audit-list-filter` из корня падает `No rule to make target` (цель живёт в `services/storage/Makefile:46-47`) — прежняя редакция записывала неисполнимую строку. С `-C` прогнано: `audit-list-filter: OK`. **Что реально наблюдает CI:** тот же job `authz-artifacts`, шаг `listauthz — публичный List фильтрует по объекту (4 сервиса)` (`ci.yaml:226-235`), который в цикле зовёт `make -C services/${svc} audit-list-filter` для `compute nlb storage vpc` и агрегирует `fail`. Комментарий в `services/storage/Makefile:44-45` («Гейт дублируется в go test …, т.к. CI-workflow этот make-таргет не вызывает») **устарел и противоречит `ci.yaml:226-235`** — вызывает; дубль в go-тесте при этом полезен (он идёт в гейте №1) и остаётся. Правка комментария — часть задачи #81 (в). Проверяется два измерения: project-scope сужения и прогон прочитанной страницы через пообъектный фильтр; `TestAuditListFilter_RealTreePasses` гоняет проверку **по реальному дереву**, а не по синтетической фикстуре — иначе гейт проверял бы сам себя. |
| 6 | `services/storage/tests/newman/scripts/run.sh` | **9 из 9** коллекций, `assertions.failed == 0` **и** `rc == 0` **у каждой** | Вердикт выводится **из отчётов**: `aggregate_verdict` (`run.sh:86-113`) печатает таблицу и возвращает 1, если у любого stem нет `out/<stem>.json` (**MISSING** — newman не выполнился), либо `failed > 0`, либо `rc != 0`. Отсутствие отчёта = провал, **не** «0 failed». Перед прогоном `out/*.json` удаляются, чтобы устаревший отчёт не подменил невыполненную коллекцию; drift-guard подхватывает сгенерированную коллекцию, которой нет в списке. Ожидаемые девять stem: `volume`, `snapshot`, `image`, `disk-type`, `internal-volume`, `operation`, `authz`, `authz-catalog`, `sec-d`. |
| 7 | `golangci-lint run` · `govulncheck ./...` | **0 findings** | Статический ярус; `//nolint` допустим только с записанной причиной (контрактные тексты `errmap`/домена — единственный легитимный случай в storage). |
| 8 | Посадка процесса на поднятом стенде | `auth_mode=production`, `db_sslmode` не `disable`, `pg_stat_ssl` подтверждает шифрование | Проверяется **живой процесс** (самоотчёт с boot-пути) и **сторона БД**, а не ConfigMap: настройки приезжают через `envFrom`, читаются один раз при старте, и правка ConfigMap без `checksum/config` под не перекатывает — boot-guard тогда просто не запускается. «Под Ready» доказательством посадки не является. |

**Четыре места, где гейты сегодня частичные — записано, а не скрыто.** У каждого назван номер задачи, которая его закрывает; ни одно не остаётся «известным, но никуда не ведущим». (Прежние строки про внешний 404 admin-маршрутов и про анонимный контекст ушли отсюда в «Закрыто в этом круге» — теперь у обеих есть замки, см. гейт №2 и `operation_ownership_test.go`.)

| Что гейты **не** наблюдают | Гейт | Закрывает |
|---|---|---|
| read-over-grant: субъект с грантом verbs `["update"]` **читает** том на storage (на compute — 403), потому что каталог storage гейтит read на tier-`viewer` | №1, №6 | задача не заведена, см. «Незакрытое», п. 14 |
| синхронный BVA описания/меток на `Snapshot.Create` — ни Go-теста, ни newman-кейса (у образа есть оба, у тома проверка без кейса) | №1, №6 | #80 |
| фактический порядок сортировки против объявленного умолчания и игнорируемый `orderBy` — не утверждает ни один кейс | №6 | #81 (а) |
| зональное ограничение типа диска — сценария нет, потому что ограничение не энфорсится | №1, №6 | #81 (б) |

**Что считается регрессией — поведение, а не код.** Тексты ошибок из таблиц выше объявлены частью контракта, поэтому утверждать надо **строку**, а не только gRPC-код: `TestAttachZoneProjectMismatch` различает пять исходов attach-CAS по текстам; `TestMapVolumeErrLeakGuard` / `TestMapImageErrLeakGuard` проверяют, что наружу уходит фиксированный текст **без** pgx/SQL/имени констрейнта; `TestVolumeValidateSizeMessage` фиксирует точный доменный текст. Тест, утверждающий только код, оставит suite зелёным после рефактора, вернувшего утечку.

---

## Осознанно не сделано (5), закрыто в этом круге (6) и незакрытое с исходом (9)

**Правило раздела:** «отмечено» исходом не считается. Каждый пункт несёт либо **номер заведённой задачи + проверяемый критерий приёмки**, либо прямую запись «**задача не заведена, требуется отдельная**» с тем же критерием. Номера не выдумываются: если задачи нет — так и написано.

**Отсутствует намеренно — граница домена.** Это не долг: предмета нет, пока нет data-plane. У каждого пункта назван **триггер пересмотра** — условие, при котором он перестаёт быть границей и становится работой.

| # | Пункт | Исход |
|---|---|---|
| 1 | **Data-plane целиком.** Ни блоков, ни LUN/namespace, ни узлов хранения, ни пулов, ни ёмкости. `VolumeInternal`/`ImageInternal` объявлены с **зарезервированным** диапазоном полей и несут только публичную проекцию: `InternalVolumeService.GetInternal` отвечает `UNIMPLEMENTED` (repo-заглушка, залочено `TestVolumeGetInternalUnimplemented`), `InternalImageService.GetInternal` возвращает публичный образ в internal-обёртке. Инфра-поля не «забыты» — их **нечем** заполнять | **Задача не нужна: граница домена.** Триггер пересмотра — появление контракта data-plane; тогда заводится под-фаза, и п. 1-3 закрываются вместе |
| 2 | **Состояния `CREATING`/`DELETING`/`ERROR` не производятся** — объявлены в CHECK и wire-enum, записывается только `READY`, удаление жёсткое | **Задача не нужна: следствие п. 1.** Фиктивную фазу «создаётся» не вводим. Триггер — тот же |
| 3 | **Пустая загрузка образа (blank upload)** — образ создаётся ровно из снимка или тома, загрузка блоба принадлежит data-plane | **Задача не нужна: граница.** Триггер — тот же |
| 4 | **Watch/стриминг событий домена.** Контракта `Watch`/`InternalWatch` в `storage.v1` нет; доменная очередь, которая могла бы его кормить, **снята** (0011) | **Задача не нужна: правило 18** («очередь вводится вместе со своим потребителем»). Триггер — появление потребителя; очередь возвращается **в том же** PR, что и он |
| 5 | **Уменьшение размера, восстановление «на месте», клонирование** — отдельных RPC нет; восстановление выражается созданием нового тома из снимка | **Задача не нужна: решение о форме API.** Триггер — продуктовое требование на in-place restore; это новый acceptance, а не долг |

**Закрыто в этом круге — шесть пунктов, ушедших из этого списка в код.** Ниже они уже описаны как действующий механизм (а не как долг), поэтому здесь только сводка «что закрыто и чем это наблюдается». Два последних закрылись **после** прежней редакции этого документа (коммиты `c58fd3d`, `5c53ad9`) — их прежние критерии приёмки содержали посылку «сегодня тест красный, поэтому пишется первым», которая перестала быть верной: прогон даёт зелёное сразу, и критерий больше ничего не проверяет. Поэтому вместо предписаний здесь стоят **ссылки на действующие замки**.

| Было | Задача | Как стоит сейчас | Наблюдается |
|---|---|---|---|
| фильтр списка спрашивал `viewer ∪ v_list`, `Get` гейтился `viewer` → страница показывала id, который не открыть | **#75** | `visibilityRelations = {"viewer"}` — ровно то отношение, что энфорсит `Get`; сверка с **каталогом**, а не с литералом; общий `pkg/authz/catalogparity` | `TestVisibilityRelationsMatchCatalogGetRelation`, `TestListNeverShowsWhatGetWouldRefuse`, `TestFGAFilter_ViewerDenialIsFinal`, `TestPermissionMapMirrorsCatalog` в **6** сервисах (седьмой, iam, in-service карты не несёт) |
| `Image.Create` не сверял размещение источника с регионом образа | **#76-1** | зоны региона резолвятся у geo **только при заданном источнике** и сверяются с живой строкой источника **внутри** insert-CAS, включая происхождение снимка | 5 integration-тестов `TestImageSource*Region*` + шаг `pre-zone-region-coherent-*` в коллекции `image` |
| отказ в правах считался временным → голова партиции заклинивала, снятие не доезжало | **#76-2** | `PermissionDenied` **терминален** (и в сервисе, и в corelib), отравление разблокирует партицию, поверх — периодический redrive-бэкстоп | `TestClassify_PermissionDeniedIsPermanent`, `TestClassifyRegisterErr`, `Test_PermissionDeniedHead_DoesNotWedgePartition` (под живым Postgres), `redrive_only_test.go` |
| монитор объявлял сбор по `/metrics`, которого процесс не обслуживал | **#76-3** | приватный реестр + 4 серии очереди на том же диагностическом слушателе, что и `/healthz`; порт чарта совпадает с тем, что слушает процесс | `TestDiagnosticListenerServesMetricsAndHealth`, `TestMetricsEndpointExposesOutboxSeries`, `TestServiceMonitorMatchesWhatTheProcessServes` |
| admin-CRUD каталога дисков был достижим на внешнем слушателе: диспетчер классифицировал запрос по одной строке пути, а admin-мутации делят путь с публичным чтением и отличаются **только** HTTP-методом. Защита держалась одним слоем (модель прав) вместо двух | **#77** (STOR-SURF-1) | решение принимается по паре **(метод, путь)** (`isInternalRoute`); таблица внутренних REST-биндингов **выводится из proto-дескрипторов** (`buildInternalRoutes`), а не ведётся руками, поэтому дрейфовать от proto нечему; `NewMux` **отказывается стартовать** на пустой таблице. Path-shaped правила остались вторым слоем. Комментарии в обоих контрактах переписаны под механизм | `TestExternalListener_RejectsDiskTypeAdminRoutes` — строгий 404 для **шести** маршрутов **двух** доменов (storage + compute); `TestInternalListener_ServesDiskTypeAdminRoutes`; `TestExternalListener_DiskTypePublicReadsStillServed` — публичное чтение на тех же путях не задето (правка сужает, а не расширяет); `TestAllInternalRESTBindings_ClassifiedInternal` — гейт дрейфа по **каждому** `Internal*`-сервису **каждого** домена, с явным падением на пустом обходе |
| анонимный контекст резолвился в `{system,bootstrap}` и матчился предикатом владельца операции — а `Get`/`Cancel` короткозамыкают per-RPC Check, поэтому владение было решающим гейтом, а не подстраховкой. Класс платформенный: та же пара строк в шести сервисах | **#79** (STOR-OPS-1) | ключ владельца выводится `OwnerFromContext`, которая **сообщает о наличии** принципала и на его отсутствии отдаёт нулевой `Owner` — различение по наличию носителя в контексте, а не сравнением с личностью; бесключевой запрос получает `NOT_FOUND`, **байт-в-байт** равный отказу постороннему; репозиторий отсекает пустой ключ **до** построения предиката (`GetOwned`/`CancelOwned` → `ErrNotFound`, `ListOwned` → пустая страница); раскатано во **все шесть** сервисов. Явно установленный системный принципал на доверенном пути сохранён — сузилась анонимность, не личность | `TestOperationGet_AnonymousContextGetsNotFound` (утверждает **текст**, не только код), `TestOperationGet_ExplicitlyClearedPrincipalGetsNotFound`, `TestOperationCancel_AnonymousContextGetsNotFound` (+ `cancelled == false`), `TestOperationGet_AuthenticatedOwnerStillServed`, `TestOperationGet_ExplicitSystemPrincipalStillServed`; в corelib — `TestOwnerFromContext_*` (×4) и `TestOwnedRepo_ZeroOwnerNeverReachesPredicate` (nil-пул как доказательство, что до SQL не доходит) |

**Незакрытое — каждый пункт с исходом (задача + критерий приёмки).**

6. **Раскол с compute не завершён; дубль жив.** `kacho-compute` продолжает обслуживать **свои** `DiskService` / `ImageService` / `SnapshotService` / `DiskTypeService` на публичном порту и держит **свои** таблицы `disks` / `images` / `snapshots` / `disk_types` (миграция `services/compute/internal/migrations/0001_initial.sql` их создаёт, ни одна последующая Up-миграция не удаляет). По четырём типам ресурсов правило «один владелец на тип» сейчас **нарушено**. Что уже единолично: **привязка** — `attached_disks` дропнута (0013), `volume_attachments` у storage единственный источник истины, `Instance.boot_volume`/`secondary_volumes` — read-only зеркало, пересчитываемое на чтении.
   **Исход — задача #37** (порядок Ф0 снять мёртвое → Ф1 EXPAND → Ф2 MIGRATE → Ф3 CONTRACT), гейт удаления таблиц — **задача #61**.
   **Критерий приёмки:** (а) публичных маршрутов `/compute/v1/{disks,images,snapshots,diskTypes}` в таблице маршрутов шлюза **ноль**; (б) FGA-типов `compute_disk`/`compute_image`/`compute_snapshot` в каноничной модели и в `verbBearingTypes` **нет**, гейт дрейфа модели зелёный; (в) обе embedded-копии каталога прав пересобраны **byte-identical**; (г) новая миграция compute дропает четыре таблицы, и **до** неё машинный счётчик `SELECT count(*)` по `kacho_compute.{disks,images,snapshots}` даёт **ноль** на локальном стенде **и** на промышленном кластере (решает второй) — рассуждение «переносить нечего по построению» гейтом не является; (д) newman-носители, сегодня использующие compute-диск (`operation.py`, `sec-d.py`, `authz-deny.py`), переведены на storage-том и зелёные.
7. **Валидация `description`/`labels` асимметрична между Create и Update** — разобрано в «Какой слой производит какую строку». **Исход — задача #78 (STOR-VAL-1)**, критерий приёмки там же.

**Открыто в этом круге — три контрактных расхождения (#80, #81) и три пункта, под которые задача НЕ заведена:**

8. **`Snapshot.Create` не валидирует описание и метки синхронно** — том и образ валидируют (`volume.go:259,262`, `image.go:235,238`), снимок не вызывает ни `validate.Description`, ни `validate.Labels` вовсе; отказ приезжает из DB-CHECK в асинхронном воркере как `Operation.error "Illegal argument"` — **поздно и без имени поля**. Полный разбор и матрица по трём ресурсам — в «Какой слой производит какую строку».
    **Исход — задача #80.**
    **Критерий приёмки** (сформулирован **прямо**, а не «как на Create» — для снимка «как на Create» означает «никак»): в `Snapshot.Create`, **до** peer-вызова в iam и до постановки `Operation`, стоят вызовы `validate.Description("description", …)` и `validate.Labels("labels", …)`; RED первым — `TestCreateBVADescriptionLabels` в `internal/service/snapshot` (описание 257 символов и 65 ключей меток при валидном источнике → sync `INVALID_ARGUMENT`); закрытие наблюдается: `GOWORK=off go test ./services/storage/internal/service/snapshot/ -count=1` — 0 fail, и коллекция `snapshot` в `run.sh` — `assertions.failed == 0`, `rc == 0` с новыми кейсами `SNP-CR-BVA-DESC-OVER-257` / `SNP-CR-BVA-LABELS-OVER-65` (сегодня в наборе снимка есть **один** BVA-кейс на Create — `SNP-CR-BVA-NAME-OVER-64`). Сценарий якорится на существующий id `CS1-S3-03`; нового пространства имён не заводится.
9. **`orderBy` принимается и молча игнорируется, а объявленное умолчание неверно.** Поле есть во всех трёх List-запросах (`volume_service.proto:152`, `snapshot_service.proto:133`, `image_service.proto:153`) с комментарием «`"id asc"` if omitted»; `grep -rn OrderBy services/storage --include=*.go` — **пусто**, ни один handler его не пробрасывает, фактический порядок — `created_at ASC, id ASC` (курсорный, `volume_repo.go:148`, `snapshot_repo.go:103`, `image_repo.go:107`). Клиент, полагающийся на документированное умолчание, получает **другой** порядок и не узнаёт об этом.
    **Исход — задача #81 (а).**
    **Критерий приёмки:** одно из двух, но не «оставить как есть» — (а) поле удаляется из трёх List-запросов (buf-breaking внутри домена, в UI не используется — проверяется `grep -rn orderBy ui-future/`), либо (б) остаётся, но **исполняется**: whitelist `createdAt asc|desc, id asc|desc`, значение вне whitelist → sync `INVALID_ARGUMENT`, и форма маркера страницы приводится в соответствие выбранному порядку (иначе курсор пропускает строки). В обеих ветках комментарий про умолчание переписывается под фактический `created_at asc, id asc`. RED первым: `List` с `orderBy=createdAt desc` возвращает порядок, отличный от `orderBy` пустого (ветка б) либо `INVALID_ARGUMENT` на неизвестное поле запроса (ветка а). Закрытие наблюдается прогоном `run.sh` — **9 из 9** коллекций зелёные, и новым кейсом `VOL-LST-ORDERBY-*` в коллекции `volume`.
10. **`DiskType.zoneIds` ничего не ограничивает.** Список хранится, пишется admin-CRUD'ом и отдаётся в каталоге, но `Volume.Create` его не читает (обращений к `ZoneIDs` вне CRUD каталога нет) — том типа с непустым списком зон создаётся в **любой** зоне. Разобрано в разделе DiskType.
    **Исход — задача #81 (б).**
    **Критерий приёмки:** одно из двух — (а) `Volume.Create` сверяет `zoneId` тома со списком зон типа **внутри того же insert-CAS** (полоса `AND (dt.zone_ids = '[]'::jsonb OR dt.zone_ids ? $zone)`, не check-then-act, ban #10), отказ — `FAILED_PRECONDITION` с контрактным текстом вида `"DiskType <id> is not available in zone <z>"`; либо (б) поле помечается в контракте как **описательное** (комментарий в `disk_type.proto` + запись в `docs/architecture/` storage), и тогда admin-CRUD перестаёт принимать непустой список, чтобы не обещать невыполнимого. RED первым: integration-тест — тип с `zoneIds=["zone-a"]`, том в `zone-b` → отказ (сегодня создаётся). Закрытие: `GOWORK=off go test ./services/storage/internal/repo/pg/ -race -count=1` — 0 fail, + кейс `VOL-CR-NEG-DISKTYPE-ZONE` зелёный в коллекции `volume`.
11. **Команда гейта listauthz не исполнялась из объявленного каталога.** В прежней редакции DoD стояло `make audit-list-filter`; из корня монорепо это `make: *** No rule to make target` — цель живёт в `services/storage/Makefile:46-47`. Отдельно: комментарий `services/storage/Makefile:44-45` утверждает, что «CI-workflow этот make-таргет не вызывает», хотя `ci.yaml:226-235` вызывает его для четырёх сервисов — ложное утверждение о механизме, того же класса, что закрытые выше.
    **Исход — задача #81 (в).**
    **Критерий приёмки:** команда в DoD исправлена на `make -C services/storage audit-list-filter` (**сделано в этой редакции**, прогнано: `audit-list-filter: OK`); комментарий в `services/storage/Makefile:44-45` приведён в соответствие с `ci.yaml:226-235`; закрытие наблюдается прогоном самой команды (`rc == 0`) и наличием шага `listauthz — публичный List фильтрует по объекту (4 сервиса)` в логе CI-job'а `authz-artifacts` для storage.
12. **`Snapshot.ListOperations` отсутствует, у Volume и Image есть** (`volume_service.proto:107`, `image_service.proto:108`; в `snapshot_service.proto` метода нет). Асимметрия публичного контракта между тремя ресурсами одного домена: клиент, написанный по образцу тома, на снимке получает несуществующий маршрут.
    **Задача не заведена, требуется отдельная** — под это расхождение нет ни одного из #75-#81; номер не выдумывается.
    **Критерий приёмки будущей задачи:** либо RPC добавляется (proto + handler + запись в `internal/check/permission_map.go` с `viewer` на `storage_snapshot` + newman-кейс `SNP-OPS-LIST-OK`), либо асимметрия фиксируется как решение — комментарий в `snapshot_service.proto` и запись в `docs/architecture/` storage с причиной. В обеих ветках закрытие наблюдается: `GOWORK=off go test ./services/storage/internal/check/ -run TestPermissionMap -count=1` зелёный (полнота карты по дескрипторам) и коллекция `snapshot` в `run.sh` зелёная.
13. **`Snapshot.Update` не валидирует `name`** — `resolveUpdate` снимка (`snapshot.go:298-324`) не вызывает доменный newtype, в отличие от тома (`volume.go:455-458`) и образа (`image.go:376-379`); `PATCH` с `name=Bad_Name` даёт не sync `"Illegal argument name"`, а асинхронный обобщённый `"Illegal argument"`.
    **Задача не заведена, требуется отдельная** — #80 про `Create`, #78 про `description`/`labels`; ни один не покрывает этот случай.
    **Критерий приёмки будущей задачи:** в ветке `apply("name")` снимка стоит `domain.SnapshotName(name).Validate()` — паритет с `volume.go:455-458`; RED первым (`PATCH` снимка с uppercase-именем → sync `INVALID_ARGUMENT "Illegal argument name"`, сегодня приходит `Operation.error`); закрытие — `GOWORK=off go test ./services/storage/internal/service/snapshot/ -count=1` 0 fail + кейс `SNP-UPD-VAL-NAME-UPPERCASE` зелёный в коллекции `snapshot`.

14. **Каталог storage гейтит read на tier-отношении `viewer`, тогда как пять доменов — на verb `v_get`/`v_list`.** Следствие наблюдаемое: грант с verbs `["update"]` материализует `v_update`+`v_delete`+tier `editor`, а `viewer: … or editor` ⟹ на storage такой субъект **читает** ресурс; на compute тот же субъект получает `403` на `Get`. Это класс, который миграция iam `0040_edit_roles_include_read_verbs.sql` закрывала («editor больше не implies viewer»), — в storage связка не разорвана. Разобрано в «Что осталось — read-over-grant».
    **Задача не заведена, требуется отдельная** — #75 закрыт по своему предмету (паритет фильтра и карты с каталогом), перевод каталога на Design-B в него не входил; номер не выдумывается.
    **Критерий приёмки будущей задачи:** `Get`→`v_get`, `List`→`v_list`, `Create`→`v_create`, `Update`→`v_update`, `Delete`→`v_delete` в proto-аннотациях storage, в `internal/check/permission_map.go` и в обеих embedded-копиях каталога; наблюдается — `make -C gateway permission-catalog-check` зелёный, `TestPermissionMapMirrorsCatalog` и `TestVisibilityRelationsMatchCatalogGetRelation` зелёные **после** перевода (оба сверяются с каталогом, поэтому переживают смену отношения), и поведенческая регрессия в коллекции `authz`: субъект с verbs `["update"]` — `Get` **403** (сегодня 200, RED пишется первым), с verbs `["get","list"]` — 200; закрытие — `run.sh` **9 из 9** коллекций, `assertions.failed == 0`.

---

## Правила (нормативно)

1. **Flat-ресурс без envelope.** Доменные поля на верхнем уровне; никаких `spec`/`status`/`metadata`/`resourceVersion`. Output-only помечено `°` и на write игнорируется. Timestamps усекаются до секунд **на каждом ресурсе и на каждой под-записи** (включая `attachedAt` внутри привязки).
2. **Read — sync, мутации — `Operation`.** `Get`/`List` синхронны; `Create`/`Update`/`Delete` возвращают `Operation` (prefix `sop`), id ресурса доступен в `metadata` **до** `done`. `Operation.done` означает «строка закоммичена» и **никогда** не гейтится на видимость downstream-эффекта. Единственное задокументированное отступление — синхронный admin-CRUD каталога `DiskType`.
3. **Каждый within-service инвариант — конструкцией БД.** PK/FK/UNIQUE/partial-UNIQUE/EXCLUDE/CHECK или атомарный CAS в одном стейтменте. `Get → check → write` запрещён на всех спорных путях; новое ссылочное поле обязано принести свой констрейнт и конкурентный интеграционный тест.
4. **Cross-service ссылка — TEXT без FK + peer-валидация на пути запроса**, fail-closed (`UNAVAILABLE`), собственный дедлайн на каждый вызов (сейчас 3 s), проброс личности вызывающего. Владелец `Instance` — compute, `Project` — iam, `Zone`/`Region` — geo.
5. **Ацикличность — по построению.** Storage не вызывает compute ни на одном пути; входящий attach-запрос самоописывающийся. Появление импорта `computev1` в `services/storage` — нарушение, а не оптимизация.
6. **Placement-когерентность обязательна.** Зональное с зональным — та же зона; зональное с региональным — зона ∈ регион. Региональный (эникаст) ресурс из зонального сравнения исключён by construction. Регион зоны **только** от geo; любая деривация разбором строки запрещена.
7. **Отказ по недоступному вызывающему ресурсу байт-в-байт равен настоящему промаху.** Различимый текст = оракул существования. Отказ по ресурсу, который вызывающему **уже виден**, наоборот, называет причину и числа.
8. **Ошибка наружу — из фиксированного словаря.** Тексты из таблиц выше — часть контракта. Сырой pgx/SQL/адрес пира не утекает: некатегоризированное → `internal error`, диагностика только в лог.
9. **Порядок проверок в List фиксирован**: обязательный `projectId` → `page_size` → `filter` → чтение страницы (декод маркера) → пообъектный фильтр. Формат отвергается **независимо** от состояния грантов.
10. **Видимость спрашивается о странице, а не о вселенной.** Перечисление всех разрешённых объектов запрещено на всех путях: у него внешний предел без продолжения, действующий на тип во всём кластере. `Get` вообще не задаёт списочного вопроса.
11. **Фильтр видимости fail-closed**; пустой субъект → пустая страница, не обход; кэшируются только положительные вердикты; деградация — только явной ручкой и только громко.
12. **AuthN + AuthZ на обоих слушателях.** Внутренний :9091 не освобождён: mTLS + per-RPC `Check`. Карта прав обязана покрывать **каждый** обслуживаемый RPC; полнота стережётся тестом по дескрипторам. `{Public: true}` (сегодня — только `OperationService.Get/Cancel`, для которых типа объекта в модели нет) снимает **исключительно** ReBAC-Check и **обязан** сопровождаться отсечением анонимности **в коде**, проверяемым тестом «контекст без принципала → `NOT_FOUND`», а не комментарием о том, что «anti-anon сохраняется». Сегодня это выполняется: ключ владельца выводится `OwnerFromContext`, которая сообщает о наличии принципала, бесключевой запрос получает тот же `NOT_FOUND`, что и посторонний, а репозиторий отвергает пустой ключ до построения предиката. Ветка `{Public: true}` короткозамыкает интерсептор **до** извлечения субъекта — поэтому анти-анонимность обязана жить в обработчике, и полагаться на предикат владельца как на анти-анонимный барьер **запрещено**: он различает владельцев, а не наличие вызывающего.
13. **`Internal.*` — никогда на внешнем эндпоинте** (нормативно). Соответствие проверяется **утверждением о 404 на внешнем слушателе** для каждого `Internal*`-RPC, а не наличием слова «Internal» в имени сервиса и не комментарием в контракте. Классификация запроса идёт по паре **(метод, путь)**, а не по одной строке пути: `Internal*Service` с человекочитаемой `google.api.http`-аннотацией на публичном пути отличается от публичного чтения **только методом**, и path-only предикат такие биндинги не различает в принципе. Источник истины — REST-биндинги `Internal*`-сервисов, **выведенные из proto-дескрипторов**, поэтому новый RPC такого сервиса изолируется автоматически, а не «обязан принести свою запись в список». Два условия делают это правилом, а не намерением: мультиплексор **не стартует** на пустой выведенной таблице, и гейт дрейфа обходит все домены, падая явно, если хоть один `Internal*`-биндинг классифицирован как публичный. Инфра-чувствительное живёт только во внутренней проекции; публичный ресурс не несёт его даже как output-only.
14. **Намерение о правах пишется в той же транзакции, что и ресурс.** Синхронный регистратор — оптимизация окна, его ошибка не роняет мутацию. Снятие меток эмитит **регистрацию с пустыми метками**, удаление — **снятие с надгробием**.
15. **Порядок в очереди держится на заборе строки** (голова партиции по `resource_id`), а не группировкой при применении, и опирается на индексы 0008/0009 и свежую статистику 0010 — все три части обязательны, любая одна недостаточна.
16. **Production-посадка обязательна везде.** Boot-guard отказывает в старте при небезопасной конфигурации; «объявлено, но не читается» — запрещённая форма контроля.
17. **Применённая миграция не редактируется.** Снятие ошибочного объекта — только новой миграцией, с записанной причиной (образец — 0011).
18. **Очередь вводится вместе со своим потребителем.** Таблица, в которую пишут и которую никто не читает, — утечка, а не задел на будущее.
