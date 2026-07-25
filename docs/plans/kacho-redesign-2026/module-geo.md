# Kachō · Geo (`kacho-geo`) — целевой tenant-facing дизайн

> Домен `kacho.cloud.geo.v1` · leaf-сервис (зовёт только iam). Публичная поверхность — **чистая read-discovery** оси размещения; запись топологии — **admin-only `Internal*` :9091** под самоописываемым `/geo/v1/internal/…`-путём. Форма — тот же хребет, что compute-эталон: flat-resource, sync-read/каталоги, reference-law по классам, two-projection (инфра **и readable, и writable** только на internal-плоскости), единый тон ошибок с **by-lane machine-readable reason-token**, и полностью spine-совместимая async-обёртка мутаций (Operation `done:true` сразу — без саги, без carve-out). Единственное продуктовое исключение домена — **slug-id** placement-координаты, приземлённый в `api-conventions.md` id-section вместе с `corevalidate.GeoSlug` (corelib) и его shared prefix→type-router-веткой `GEO_COORDINATE`.

## Ментальная модель

1. **Geo — единственный владелец оси размещения (placement axis).** Region и Zone — не «ресурсы облака», а **координаты**, на которые ссылается ВЕСЬ продукт. Источник истины containment-графа `zone → region` — колонка `kacho_geo.zones.region_id` (class-A within-service DB-FK, RESTRICT). Любая placement-coherence-проверка в vpc/compute/nlb резолвит `zone.regionId` **здесь** и нигде больше. **Сама ось (ZONAL/REGIONAL) НЕ эмитится полем**: consumer выводит её из вызванного сервиса (`ZoneService` ⇒ зональная координата, `RegionService` ⇒ региональная/anycast) и из типа своего ресурса. Хранимый дискриминатор `placementType` живёт **исключительно на Subnet-якоре**, где он реально варьируется и хранится — geo его не дублирует (константа-по-типу = ноль бит + одноимённость с Subnet-семантикой вводит consumer'а в заблуждение).

2. **Публичная поверхность geo = discovery, не CRUD.** У tenant'а НЕТ ни одной мутации в geo — он только **читает каталог** «куда я могу размещать». `ZoneService.List`/`RegionService.List` (sync) сидят рядом с launch'ем ЛЮБОГО размещаемого ресурса (Subnet.zoneId, Instance.zoneId, LoadBalancer.regionId выбираются отсюда). **Discovery item == полная публичная проекция** (несёт `name`, для Region — `countryCode°`/`openZoneCountHint°`, для Zone — `placementBlockedReason°`) — picker рисует лейблы без +N `Get`. `openForPlacement°` — единственный actionable сигнал, но **advisory, не lease**: между discovery и Create зона может закрыться (TOCTOU присущ async-модели) → на отказе **re-discover**, не полагаться на кэш выбора.

3. **slug-id — ЕДИНСТВЕННЫЙ carve-out, приземлённый в `api-conventions.md` + corelib.** Region/Zone несут **человеко-осмысленный immutable slug** (`ru-central1`, `ru-central1-a`), а не `reg-01H…`, потому что id ЯВЛЯЕТСЯ координатой: её пишут руками в каждый Create любого сервиса и читают в URL/логах/токенах. **THE ONE** намеренное отклонение от 3-char-prefix+crockford-base32, физически задокументированное в id-section `api-conventions.md` и приземлённое как **`corevalidate.GeoSlug` в CORELIB** (не geo-local) + first-class kind `GEO_COORDINATE` в shared prefix→type-router. Coupling **`zone.id == regionId + "-" + <zoneSuffix>`** (`zoneSuffix ∈ [a-z0-9]+`; строго `startsWith(regionId+"-")`, НЕ голый `startsWith` — иначе `ru-central10-a` ложно «префиксуется» `ru-central1`). Один авторитетный источник — carve-out стоит ОДНУ центральную ветку, импортируемую всеми consumer'ами, а не N локальных special-case'ов.

4. **Catalog-мутации возвращают синхронно-завершённый Operation — spine-preserving, НЕ carve-out.** Топология — cluster-scoped **config** в одной БД без provision-саги (один INSERT). Поэтому `Create/Update/Delete` возвращают `Operation{done:true, metadata:{<res>Id}, response:<Region|Zone>}` — **уже завершённый**, persisted в per-service `operations`-таблице (corelib), pollable через `OperationService.Get`, но поллить не нужно (unwrap `.response` даёт полное тело — ноль повода звать `OperationService.Get`). Инвариант «любая мутация Kachō → Operation» **держится буквально**; generic `await-any-mutation` SDK/IaC видит `done:true`, извлекает `response`, никогда не re-поллит. Byte-identical `InternalDiskTypeService`. Eventually-consistent остаётся у **downstream FGA-catalog-tuple** (`geo_outbox`), не у ответа RPC — гейтить `done` на его видимость запрещено (ban #9).

5. **Two-projection жёстче обычного; fresh-ресурс закрыт by default, но немо не молчит.** Tenant видит `id/name/openForPlacement°/…`. **Сырой admin-флаг `status` (UP/DOWN)** и вся инфра (`numericInfraId`, `hostClasses`, `failureDomainCount`, `underlayAnchor`, `capacityHint`) — admin-plane: и **readable, и writable** только через `Internal*` :9091 (`GetInternal` + `Internal*.Create/Update` принимают `infra°`-блок — никаких readable-but-unwritable дыр). **Fresh Region/Zone поднимаются `status=DOWN` (fail-safe)** — admin ЯВНО открывает. Но тихий no-op «создал закрытую топологию» делается **громким в той же `Operation.response`**: если результат резолвится в `openForPlacement°=false` / `openZoneCountHint°==0`, ответ несёт top-level `warnings°`-запись. Источник истины инфра-проекции — `security.md`: даже скомпрометированный публичный API не раскроет физику ДЦ, host-классы и не даст отличать «выведено» на уровне сырого флага — включая **обезличенную public capacity-ошибку** (см. rule 3/13).

---

## Region

Региональный (anycast) якорь. Cluster-scoped catalog-ресурс — вне Project/Account.

```jsonc
{
  "id": "ru-central1",              // slug PK, admin-assigned, IMMUTABLE (carve-out: не 3-char prefix; corevalidate.GeoSlug)
                                     //   — координата REGIONAL-scope; пишется в LoadBalancer.regionId и т.п.
  "name": "RU Central 1",           // human-readable label; LIVE-mutable (Internal Update). Глобально UNIQUE
  "countryCode°": "RU",             // ° ISO-3166 alpha-2; output-only descriptor, non-sensitive → на public.
                                     //   LIVE-mutable через Internal Update (gates nothing — опечатку чиним, не draining)
  "openForPlacement°": true,        // ° ЕДИНСТВЕННЫЙ actionable placement-сигнал.
                                     //   = status==UP. АДМИНИСТРАТИВНАЯ availability, НЕ гарантия ёмкости (rule 3).
                                     //   Region: если false — причина ВСЕГДА REGION_DOWN by construction
                                     //   (нет placementBlockedReason° на Region — enum схлопнулся бы в биекцию флага)
  "openZoneCountHint°": 3,          // ° ADVISORY read-time COUNT-rollup зон с openForPlacement°=true (НЕ persisted).
                                     //   authoritative source = ZoneService.List?openForPlacement=true — расхождение
                                     //   возможно, инвариант на нём строить нельзя (picker всё равно зовёт ListZones)
  "createdAt°": "2026-06-17T09:00:00Z"  // ° server-set, truncate-to-seconds
}
```

- **Ось НЕ эмитится полем:** «регион ⇒ REGIONAL» consumer знает по вызванному `RegionService` — тавтологического constant-by-type `placementType°` на проекции нет (удалён; хранимый дискриминатор — только на Subnet).
- **`geographyHint°` удалён** — дублировал residency-намерение `countryCode°` и не гейтился программно; coarse UI-группировку выводи read-time маппером из `countryCode°`.
- **`placementBlockedReason°` НЕ на Region** — для региона enum схлопывается в `{NONE|REGION_DOWN}` = чистая биекция `openForPlacement°`. Диагностика живёт только на Zone (там различает ZONE_DOWN vs REGION_DOWN). Godoc `openForPlacement°` явно гласит: «Region: when false, cause is always REGION_DOWN by construction».
- **Raw admin `status` + infra** — admin-plane: settable `InternalRegionService.Create/Update`, readable `GetInternal`. На публичной проекции их нет.
- **Delete-инвариант:** регион с зонами удалить нельзя — `zones.region_id` FK RESTRICT (within-service, ban #10). `InternalRegionService.Delete` → `FAILED_PRECONDITION "region ru-central1 is not empty"`.
- **Cross-service:** consumer'ы (nlb) хранят `regionId` TEXT без FK, валидируют через corelib-хелпер `geoconsumer.ValidatePlacement` (peer `RegionService.Get` + open-gate + per-call deadline + code/text-remap — rule 12).

---

## Zone

Зональный якорь — availability-zone внутри Region. Cluster-scoped catalog-ресурс.

```jsonc
{
  "id": "ru-central1-a",            // slug PK, admin-assigned, IMMUTABLE; coupling id == regionId + "-" + <zoneSuffix>.
                                     //   startsWith(regionId+"-") строго; corevalidate.GeoSlug ПЕРВЫМ стейтментом.
                                     //   resolve region via regionId field, NEVER by string-stripping id
  "regionId": "ru-central1",        // class-A within-service FK → regions(id) ON DELETE RESTRICT.
                                     //   IMMUTABLE после Create (reject до UpdateMask); id обязан нести этот префикс.
                                     //   перенос зоны между регионами сломал бы coherence всех размещённых ресурсов.
                                     //   resolve region via regionId field, NEVER by string-stripping id
  "name": "RU Central 1 — Zone A",  // human-readable; LIVE-mutable (Internal Update). Глобально UNIQUE
  "openForPlacement°": true,        // ° ЕДИНСТВЕННЫЙ actionable сигнал.
                                     //   = zone.status==UP && region.status==UP.
                                     //   АДМИНИСТРАТИВНАЯ availability, НЕ гарантия ёмкости (capacity — Internal-only);
                                     //   Create МОЖЕТ упасть FAILED_PRECONDITION на ёмкости в schedule-time (rule 3).
                                     //   если false — см. placementBlockedReason°
  "placementBlockedReason°": "NONE", // ° enum {NONE|ZONE_DOWN|REGION_DOWN} — почему false в ОДНОМ вызове
                                     //   (не нужен второй RegionService.Get, чтобы отличить zone-down от region-down).
                                     //   precedence: zone.status==DOWN⇒ZONE_DOWN; иначе region.status==DOWN⇒REGION_DOWN
  "createdAt°": "2026-06-17T09:00:00Z"  // ° truncate-to-seconds
}
```

- **Ось НЕ эмитится полем:** «зона ⇒ ZONAL» consumer знает по вызванному `ZoneService`. Constant-by-type `placementType°` удалён.
- **Raw admin `status` + infra** — admin-plane (см. Internal-проекцию); и readable, и writable только через `Internal*`.

**Internal-проекция** (`InternalZoneService.GetInternal`, :9091 — НЕ на публичной поверхности; `infra°` **принимается** на `Internal*.Create` целиком и на `Update` как mutable-subset):

```jsonc
{
  "id": "ru-central1-a",
  "regionId": "ru-central1",
  "status": "UP",                   // GeoStatus (admin maintenance-флаг) — сырой флаг ТОЛЬКО здесь:
                                     //   UP "принимает размещение" · DOWN "выведена/новая, размещение запрещено".
                                     //   fresh zone = DOWN by default (fail-safe). LIVE-mutable Internal Update
  "infra°": {                       // ° всё infra-sensitive — ТОЛЬКО здесь (two-projection, security.md).
                                     //   ПРИНИМАЕТСЯ на InternalZoneService.Create; Update — mutable-subset
    "numericInfraId°": 10402,       // числовой инфра-идентификатор зоны; IMMUTABLE после Create
    "hostClasses°": ["std-v3", "mem-v2", "gpu-a1"],   // инвентарь host-классов (mutable). НИКОГДА на public —
                                     //   в т.ч. НЕ встраивается в public capacity-ошибку (rule 3)
    "failureDomainCount°": 3,       // число failure-domain внутри зоны (mutable)
    "underlayAnchor°": "fd00:ru1a::/48",              // carrier/underlay-координата (mutable)
    "capacityHint°": "AMPLE"        // enum {AMPLE|CONSTRAINED|FULL} — scheduler/infra-сигнал (mutable), НИКОГДА на public
  }
}
```

**Internal-проекция Region** (`InternalRegionService.GetInternal`, :9091):

```jsonc
{
  "id": "ru-central1",
  "name": "RU Central 1",
  "status": "UP",                   // GeoStatus (admin maintenance-флаг) — сырой флаг ТОЛЬКО здесь
  "infra°": {                       // ° принимается на InternalRegionService.Create (numericInfraId°)
    "numericInfraId°": 900,         // числовой инфра-идентификатор региона; IMMUTABLE после Create
    "capacityHint°": "AMPLE"        // ° read-time rollup из zone-infra capacityHint° (НЕ persisted, не settable);
                                     //   scheduler-сигнал, никогда не на public
  }
}
```

---

## RPC surface

### Public — read-discovery (`:9090`, external-safe)

| Service.Method | Sync/Async | REST | authz-floor |
|---|---|---|---|
| `RegionService.Get` | **sync** | `GET /geo/v1/regions/{regionId}` | project-scope **EXEMPT** (rule 5) |
| `RegionService.List` | **sync** | `GET /geo/v1/regions?openForPlacement=` | project-scope **EXEMPT** |
| `ZoneService.Get` | **sync** | `GET /geo/v1/zones/{zoneId}` | project-scope **EXEMPT** |
| `ZoneService.List` | **sync** | `GET /geo/v1/zones?regionId=&openForPlacement=` | project-scope **EXEMPT** |

Ни одной мутации на публичном листенере. Cursor-pagination `(created_at,id)`; фильтры whitelisted (`regionId`, `openForPlacement` bool — **заменяет** прежний `status=UP`; сырого `status` на public нет). Format-validate (`pageSize`/`pageToken`/id-slug через `corevalidate.GeoSlug`) **до** authz-short-circuit.

### Internal — admin catalog-CRUD + infra-projection (`:9091`, ban #6, **самоописываемый `/geo/v1/internal/…`-путь**, никогда на external)

> **Каждая мутация ниже возвращает синхронно-завершённый `Operation` (`done:true` немедленно, `response` = полное тело ресурса — unwrap `.response`, НЕ поллить `OperationService.Get`).**
> **By-construction инвариант: любой `/geo/v1/internal/…`-путь резолвится ТОЛЬКО на :9091 под `system_admin`; external host его не резолвит и отдаёт понятный method-not-available, не bare 404** (устраняет визуальную неотличимость `POST /geo/v1/regions` от public `GET`).

| Service.Method | Sync/Async | REST (internal mux only) | authz |
|---|---|---|---|
| `InternalRegionService.Create` | **Operation** (done:true сразу) | `POST /geo/v1/internal/regions` | `system_admin` |
| `InternalRegionService.Update` | **Operation** (done:true сразу) | `PATCH /geo/v1/internal/regions/{regionId}` | `system_admin` (`status`/`countryCode`/`infra°`-subset) |
| `InternalRegionService.Delete` | **Operation** (done:true сразу) | `DELETE /geo/v1/internal/regions/{regionId}` | `system_admin` (RESTRICT если есть зоны) |
| `InternalZoneService.Create` | **Operation** (done:true сразу) | `POST /geo/v1/internal/zones` | `system_admin` (принимает `infra°`) |
| `InternalZoneService.Update` | **Operation** (done:true сразу) | `PATCH /geo/v1/internal/zones/{zoneId}` | `system_admin` (`status`/`name`/`infra°`-subset) |
| `InternalZoneService.Delete` | **Operation** (done:true сразу) | `DELETE /geo/v1/internal/zones/{zoneId}` | `system_admin` |
| `InternalRegionService.GetInternal` | **sync → InternalRegion** | `GET /geo/v1/internal/regions/{regionId}` | `system_admin` |
| `InternalZoneService.GetInternal` | **sync → InternalZone** | `GET /geo/v1/internal/zones/{zoneId}` | `system_admin` |
| `OperationService.Get` | **sync → Operation** | `GET /geo/v1/internal/operations/{operationId}` | `system_admin` |

**One-shot Region+Zones** (`zoneSpecs` разворачиваются в ОДНОЙ транзакции — не заставляем admin'а делать 1+N вызовов; `status` опционален и на регионе, и на каждой зоне; `infra°` принимается на зонах и на регионе):

```jsonc
// POST /geo/v1/internal/regions   (InternalRegionService.Create → Operation done:true)
{
  "id": "ru-central1",
  "name": "RU Central 1",
  "countryCode": "RU",
  "status": "UP",                   // optional; DEFAULT "DOWN" (fail-safe) если опущен → регион остаётся закрытым
  "infra°": { "numericInfraId°": 900 },   // region-level infra принимается здесь (numericInfraId° immutable)
  "zoneSpecs": [                    // под-ресурсы разворачиваются атомарно в той же TX; infra° per-zone
    { "id": "ru-central1-a", "name": "RU Central 1 — Zone A", "status": "UP",
      "infra°": { "numericInfraId°": 10401, "hostClasses°": ["std-v3","mem-v2"], "failureDomainCount°": 3,
                  "underlayAnchor°": "fd00:ru1a::/48", "capacityHint°": "AMPLE" } },
    { "id": "ru-central1-b", "name": "RU Central 1 — Zone B", "status": "UP",
      "infra°": { "numericInfraId°": 10402, "hostClasses°": ["std-v3"], "failureDomainCount°": 3,
                  "underlayAnchor°": "fd00:ru1b::/48", "capacityHint°": "AMPLE" } },
    { "id": "ru-central1-d", "name": "RU Central 1 — Zone D" }                 // status опущен → DOWN, dark; infra позже
  ]
}
// → 200 Operation{
//     "done": true,
//     "metadata": { "regionId": "ru-central1" },       // id доступен сразу
//     "response": {                                     // ПОЛНОЕ тело созданного ресурса — unwrap здесь
//       "id": "ru-central1", "name": "RU Central 1",
//       "countryCode°": "RU", "openForPlacement°": true,   // status:UP задан явно ⇒ open
//       "openZoneCountHint°": 2,                            // a,b открыты (UP); d поднялась DOWN
//       "createdAt°": "2026-07-15T10:00:00Z"
//     },
//     "warnings°": [                                    // no-op делается ГРОМКИМ, а не немым success:
//       "zone ru-central1-d created but CLOSED to placement (status DOWN); no tenant can place here — Internal Update status=UP to open"
//     ]
//   }
// Если "status" опустить и на регионе → response.openForPlacement°:false, openZoneCountHint°:0, и warnings° несёт:
//   "region ru-central1 created but CLOSED to placement (status DOWN); no tenant can place here — Internal Update status=UP to open"
// (fail-safe DOWN сохранён; тихий no-op сделан наблюдаемым в ТОЙ ЖЕ Operation.response — см. rule 4/16).
```

**validateOnly dry-run** (sync, БЕЗ мутации/state-gate; spine-shape — `resolved°`-echo выведенных значений + `warnings°` поверх; `placementType°` в echo НЕ несётся — удалён):

```jsonc
// POST /geo/v1/internal/zones?validateOnly=true
{ "id": "ru-central1-c", "regionId": "ru-central1", "name": "Zone C" }
// → 200 {
//     "valid": true,
//     "resolved°": {                    // echo выведенных значений (spine parity с прочими validateOnly)
//       "id": "ru-central1-c",
//       "regionId": "ru-central1",
//       "openForPlacement°": false,     // fresh zone default DOWN
//       "placementBlockedReason°": "ZONE_DOWN"
//     },
//     "warnings°": [
//       "zone slug 'ru-central1-c' близок к существующей 'ru-central1-d'",
//       "zone will be created CLOSED to placement (status DOWN by default) — set status=UP to open"
//     ]
//   }   — ничего не создано
```

---

## Discovery-каталог (placement-launch)

geo — **сам по себе** discovery-каталог продукта: `ZoneService.List` сидит рядом с launch'ем ЛЮБОГО зонального ресурса. **Item каталога == полная публичная проекция ресурса** (несёт `name`, диагностику) — picker/UI рисует лейблы без +N `Get`. Item **не несёт `use°`-обёртку**: для координатного ресурса `item.id` ЯВЛЯЕТСЯ координатой, а целевое поле (`zoneId`/`regionId`) известно из контекста Create consumer'а — single-field-wrapper под другим ключом был бы церемонией. `placementType°` в item'ах отсутствует (ось выводится из вызванного сервиса).

```jsonc
// GET /geo/v1/zones?regionId=ru-central1&openForPlacement=true   (sync, «зоны, куда я могу разместить»)
{
  "zones": [
    {
      "id": "ru-central1-a",        // ← это и есть координата: подставить как Subnet/Instance/Disk.zoneId
      "regionId": "ru-central1",
      "name": "RU Central 1 — Zone A",   // полный public-shape: name присутствует (не reduced-subset)
      "openForPlacement°": true,
      "placementBlockedReason°": "NONE",
      "createdAt°": "2026-06-17T09:00:00Z"
    },
    {
      "id": "ru-central1-b",
      "regionId": "ru-central1",
      "name": "RU Central 1 — Zone B",
      "openForPlacement°": true,
      "placementBlockedReason°": "NONE",
      "createdAt°": "2026-06-17T09:00:00Z"
    }
  ],
  "nextPageToken°": ""
}
```

```jsonc
// GET /geo/v1/regions?openForPlacement=true   (sync) → item.id = координата regionId для LoadBalancer/TargetGroup.Create
{
  "regions": [
    {
      "id": "ru-central1",          // ← координата regionId
      "name": "RU Central 1",
      "countryCode°": "RU",         // полный public Region-shape
      "openForPlacement°": true,
      "openZoneCountHint°": 3,       // advisory hint; точный счёт — ListZones?openForPlacement=true
      "createdAt°": "2026-06-17T09:00:00Z"
    }
  ],
  "nextPageToken°": ""
}
```

Фильтр `openForPlacement=true` = «открыто для размещения» (учитывает статус родит-региона через derived-флаг) — **единственный** placement-фильтр, сырого `?status=UP` больше нет. Каталог **advisory, не lease**: `openForPlacement°=true` в момент discovery не гарантирует, что зона открыта/ёмка к моменту Create — на отказе **re-discover**.

---

## Правила

1. **Единый владелец оси размещения; ось выводится из вызванного сервиса, не эмитится полем.** Region/Zone и containment `zone.regionId` — источник истины ТОЛЬКО в `kacho_geo`. Consumer'ы (vpc/compute/nlb) хранят `zoneId`/`regionId` как flat TEXT **без cross-service FK** и валидируют peer-вызовом на request-path, fail-closed. Зеркал строк топологии consumer не держит. **`placementType°` из geo-проекций (Region/Zone/discovery/validateOnly-echo) удалён** — тавтологическое constant-by-type поле (Region ВСЕГДА REGIONAL, Zone ВСЕГДА ZONAL): consumer выводит ось по вызванному сервису (`ZoneService`⇒зональная, `RegionService`⇒региональная) и по типу своего ресурса. Хранимый дискриминатор `placementType` остаётся **исключительно на Subnet-якоре**, где ВАРЬИРУЕТСЯ и хранится; переиспользование его имени на geo-константе провоцировало ошибку у consumer'а, пишущего coherence-код. Понадобится позже machine-hint «это зональная координата» — отдельное имя (`axisKind`), НЕ семантика Subnet-дискриминатора.

2. **Placement-coherence якорится здесь И энфорсится consumer'ом через ЕДИНЫЙ corelib-хелпер.** Ось выводится по типу (Zone⇒зональный, Region⇒региональный/anycast). Coherence-проверка ресурса-consumer'а (Instance⇄Subnet, NLB⇄Subnet) резолвит `zone.regionId` через geo; зона `∈` регион peer'а — критерий зонально↔регионального сравнения. **Placement-gate + peer-miss remap мандатированы одним corelib-хелпером `geoconsumer.ValidatePlacement(ctx, geoClient, zoneId|regionId)`**: format-validate (`corevalidate.GeoSlug` первым) → peer-`Get` с per-call deadline → open-gate → code/text-remap (`NOT_FOUND`→`FAILED_PRECONDITION "Zone <id> not found"`; not-open→`FAILED_PRECONDITION "zone <id> is not open for placement"`). Все три consumer'а (vpc/compute/nlb) ОБЯЗАНЫ звать его — coherence держится **by construction**, а conformance-lock охраняет ХЕЛПЕР, а не полицирует три byte-identical копии. geo — self-describing payload, **не** зовёт consumer'ов обратно (ацикличность).

3. **`openForPlacement°` — АДМИНИСТРАТИВНЫЙ availability, НЕ гарантия ёмкости; public capacity-fail ОБЕЗЛИЧЕН.** `openForPlacement° = zone.status==UP && region.status==UP` (для Region = `status==UP`). Godoc в точке использования обязан нести формулу: «administratively open; NOT a capacity/health guarantee — Create may still fail on capacity at schedule time; if false — see placementBlockedReason° (Region: cause always REGION_DOWN by construction)». Ёмкость и host-классы (`capacityHint`, `hostClasses`) — scheduler/infra-сигнал, **Internal-only** (two-projection), на public НЕ течёт. Единственный canonical capacity-fail — **видимый tenant-facing outcome через `op.error`**, но **без конкретного host-класса**: `FAILED_PRECONDITION "zone ru-central1-a has insufficient capacity for the requested configuration"` (retriable). Конкретный host-class (`std-v3`) остаётся **ТОЛЬКО** в Internal scheduler-логах / `GetInternal.infra°.hostClasses°` — встраивание его в публичную ошибку нарушало бы собственный two-projection-инвариант продукта (разведка host-классов по зонам). Regression-lock: public capacity-error `NotContains` ни один hostClass-токен. Discovery — **advisory, не lease**: TOCTOU присущ async-модели, зелёный-в-discovery → прошёл-gate → упал-на-ёмкости — валидный путь с видимым (обезличенным) op.error.

4. **Admin-мутации возвращают синхронно-завершённый Operation — spine-preserving, unwrap `.response`.** Топология — cluster config в одной БД без provision-саги (один INSERT), но обёртка — полноценный `Operation{done:true, metadata:{<res>Id}, response:<Region|Zone>}`, persisted в per-service `operations`-таблице, pollable через `OperationService.Get`. Инвариант «любая мутация Kachō → Operation» **держится буквально** — generic `await-any-mutation` SDK/IaC видит `done:true`, извлекает `response`, никогда не re-поллит. `response°` несёт **ПОЛНОЕ тело** — ноль повода звать `OperationService.Get`. Admin-facing curl/IaC-примеры ДОСЛОВНО показывают unwrap `.response` + «done:true always immediate; response carries the full body — no poll ever needed» (снимает ложную ментальную модель «это async»). Byte-identical `InternalDiskTypeService`. Downstream FGA-catalog-tuple материализуется eventually через `geo_outbox` — не гейтить admin-ответ на его видимость (ban #9); «создал регион → сразу Check» покрывается bounded client-retry.

5. **Discovery-read — project-scope EXEMPT (один зафиксированный механизм); admin-CRUD — `system_admin`.** geo — единственный ресурс, который КАЖДЫЙ tenant в КАЖДОМ проекте обязан прочитать, чтобы launch'ить что-либо (`zoneId`/`regionId` берутся отсюда). Механизм ambient-доступа зафиксирован ОДИН (снят прежний either/or): **public-read geo EXEMPT от project-scope** — переиспользует уже приземлённый documented-exception паттерн (как internal JWKS-route, `security.md`), а не изобретает auto-grant `system_viewer`. Пин — в acceptance-доке + `api-conventions.md` + `security.md`. **e2e (construction-verified, не described):** fresh zero-binding project МОЖЕТ `List`/`Get` regions/zones. Без этого plain project-tenant ловит немой `403` на единственном каталоге, от которого зависит любой Create — opaque platform-wide onboarding-cliff. Admin-CRUD → `system_admin`; `scope_extractor` резолвит well-known `system:catalog` (не target→project, geo вне Project). iam недоступен → `PERMISSION_DENIED "authorization service unavailable"`, никогда allow. mTLS (service→service) / TLS+JWT (user→edge) везде, включая :9091.

6. **Публичная поверхность — read-only, ОДИН actionable placement-сигнал; admin-write самоописываем в пути.** У tenant'а нет мутаций в geo. Public read отдаёт **единственный** actionable сигнал `openForPlacement°` (+ диагностику `placementBlockedReason°` — только на Zone; на Region она биекция флага и удалена). **Сырой admin-флаг `status` (UP/DOWN) — admin-plane**: settable `Internal*.Create/Update`, readable `GetInternal`, на public его нет. Public List фильтрует `openForPlacement` (bool), а не `status=UP` — два перекрывающихся сигнала на один вопрос схлопнуты by construction. Запись топологии — исключительно `Internal*` :9091 под **явным `/geo/v1/internal/…`-сегментом** (by-construction: любой internal-путь = :9091/`system_admin`, external его НЕ резолвит, отдаёт clear method-not-available, не bare 404) через `*InternalAddr`-блок api-gateway; ни один admin-RPC не появляется на external (ban #6).

7. **slug-id, immutable — ЕДИНСТВЕННЫЙ carve-out; приземлён в `api-conventions.md` + `corevalidate.GeoSlug` (corelib) + shared prefix→type router.** `id` Region/Zone — admin-assigned человеко-осмысленный slug (`corevalidate.GeoSlug`: charset `[a-z0-9-]`). geo placement-координаты (`regionId`/`zoneId`) — **THE ONE** намеренное исключение из 3-char-prefix base32, **физически задокументированное в id-section `api-conventions.md`** и **приземлённое как `corevalidate.GeoSlug` в CORELIB** (не geo-local) + классифицируемое shared prefix→type-router'ом как first-class kind `GEO_COORDINATE` (не reject) — carve-out стоит ОДНУ центральную ветку, импортируемую всеми consumer'ами, а не N локальных special-case'ов. Immutable после Create. **Coupling `zone.id == regionId + "-" + <zoneSuffix>`** (`zoneSuffix ∈ [a-z0-9]+`; строго `startsWith(regionId+"-")`, НЕ голый `startsWith` — контрпример `ru-central10-a` под `ru-central1` → **REJECT**): несоответствие → **ПЕРВЫМ стейтментом RPC** `INVALID_ARGUMENT "zone id 'ru-central1-a' must be prefixed by its regionId 'eu-west1'"` (charset + region-prefix проверяются `GeoSlug` ДО любого FK-резолва). Эргономика: `zone.id` выводится server-side из `regionId + zoneSuffix` (`"a"`), снимая ручную синхронизацию двойного кодирования региона. Директива у ОБОИХ полей: «resolve region via regionId field, NEVER by string-stripping id». Malformed slug → `INVALID_ARGUMENT "invalid zone id 'ZZ!'"`; well-formed-но-нет (direct-read) → `NOT_FOUND`.

8. **reference-law соблюдён по классам, без референсификации ради единообразия.** `zone.regionId` — class-A (within-service, flat `<x>Id` + DB-FK RESTRICT), НЕ `Referrer`. Cluster-scope → нет `projectId`. geo не ссылается на чужие owned-ресурсы → класса C (`Referrer{type,id,name°}`) в домене нет by construction.

9. **Two-projection обязательна; сырой `status` и вся инфра — только Internal, И readable, И writable там.** Public Region = `id/name/countryCode°/openForPlacement°/openZoneCountHint°/createdAt°`; public Zone = `id/regionId/name/openForPlacement°/placementBlockedReason°/createdAt°`. Сырой `status` (`GeoStatus`) и `infra°` (`numericInfraId`, `hostClasses`, `failureDomainCount`, `underlayAnchor`, `capacityHint`) — ТОЛЬКО `Internal*`: **readable через `GetInternal` И writable через `Internal*.Create` (полный `infra°`-блок) / `Update` (mutable-subset)** — никаких readable-but-unwritable дыр (авторинг host-классов/ёмкости — ЯДРО admin-задачи «поднять зону»). `numericInfraId°` immutable-after-create; остальное infra — mutable. `countryCode°` — non-sensitive structured geo-descriptor → на public. `geographyHint°` **удалён** (дублировал `countryCode°`). Ни одно инфра-поле и ни `status` не добавляется на public additively (gateway projection-audit гейтит); **public capacity-ошибка тоже не эхает host-class** (rule 3).

10. **Update mutability-классы единообразно.** LIVE-mutable: `name` (public label, UNIQUE); `status` (`GeoStatus` admin maintenance-флаг — `Internal*.Update`, немедленно); `countryCode` (output-only descriptor, gates nothing → correctable, не immutable); `infra°`-subset (`hostClasses`/`failureDomainCount`/`underlayAnchor`/`capacityHint` — `Internal*.Update`). Immutable (reject **до** `corevalidate.UpdateMask`, тон `"<field> is immutable after <R>.Create"`): `id`, `zone.regionId`, `infra°.numericInfraId`. Immutable-switch — до `UpdateMask`. Классы next-boot-deferred / STOPPED-gated / power-state — N/A (catalog без lifecycle-машины; `status` — admin-флаг, не power-state).

11. **Within-service инварианты — на DB-уровне (ban #10).** `regions_pkey`/`zones_pkey` PK на slug; `zones.region_id` FK RESTRICT; UNIQUE(`name`) глобально на обоих (нет project-scope → нет UNIQUE(project,name); `name` обязателен как label). `openZoneCountHint°` (Region) и Region-infra `capacityHint°` — **read-time rollup** (COUNT/aggregate из zones/zone-infra), НЕ persisted denormalized-поля (advisory, ноль staleness-обязательства, authoritative source = `ZoneService.List`). Standalone `Zone.Create` с absent `regionId` → **pre-flight resolve → `NOT_FOUND`** (rule 13); FK RESTRICT остаётся DB-backstop и для create-race, и для delete-non-empty. Единый `GeoStatus`-enum {UNSPECIFIED, UP, DOWN} для Region и Zone; fresh row default DOWN (fail-safe).

12. **Consumer→geo — per-call deadline, fail-closed; immutable-факты кэшируемы, `openForPlacement°` — свежий.** `ZoneService.Get`/`RegionService.Get` — синхронная, fail-closed зависимость на placement-Create. Каждое consumer-ребро ОБЯЗАНО нести `context.WithTimeout(ctx, …)` на geo-вызове (architecture.md per-call-deadline) → breach = `UNAVAILABLE` (fail-closed для мутаций), не подвисание. **Кэш-политика раздельная (снимает platform-wide SPOF на пути ВСЕХ размещений):** consumer МОЖЕТ держать короткий-TTL кэш **иммутабельных фактов** (existence zone/region + coupling `zone.regionId` — immutable by design), но `openForPlacement°` — **синхронно-свежий, НЕкэшируемый** (placement-gate обязан видеть актуальный `status`, иначе «не launch'ить в DOWN-зону» ломается). Coherence-резолв zone→region кэшируется; open-gate — нет → availability compute/vpc/nlb развязывается с availability geo там, где безопасно. Coupling `openForPlacement°`-cross-field документирован у обоих Get.

13. **Единый тон ошибок (часть контракта), by-lane code-distinction + stable reason-token; malformed ловится локально ДО peer-hop.** Одно логическое «нет такой зоны/региона» даёт разные коды **только по lane (границе)**, и это **продуктовый инвариант всех доменов** (by-lane, не geo-причуда), задокументированный таблицей в `api-conventions.md`: **direct-read lane** (прямой geo-read / within-service create absent-parent) → `NOT_FOUND`; **peer-validate lane** (consumer peer-validate / zone-not-open / capacity) → `FAILED_PRECONDITION`. Клиентский cognitive-tax снижен **стабильным machine-readable reason-token в `google.rpc.Status` details** (`reason:"ZONE_NOT_FOUND"` / `"REGION_NOT_FOUND"` / `"ZONE_NOT_OPEN"` / `"CAPACITY_UNAVAILABLE"`), **ИДЕНТИЧНЫМ через geo-direct И все три consumer** — клиент ключуется на detail, не на top-level код (предсказуемость by-lane, не by-luck). Split документирован у **CONSUMER Create-доков**, где интегратор бьётся, не только в geo. **Malformed на consumer-пути:** каждый consumer валидирует ФОРМАТ `zoneId`/`regionId` через shared `corevalidate.GeoSlug` **ПЕРВЫМ стейтментом** → `INVALID_ARGUMENT "invalid zone id 'ZZ!'"` **ДО** peer-вызова geo (мигрант из индустрии ждёт 400 на плохой вход; slug ловится локально без geo round-trip); well-formed-но-нет остаётся `FAILED_PRECONDITION` (spine-граница, НЕ industry-400). Документировано у обоих consumer-Get: «malformed → 400 первым стейтментом; well-formed-absent → FAILED_PRECONDITION». Standalone `Zone.Create` с absent `regionId` → pre-flight resolve → `NOT_FOUND "Region ru-central1 not found"` (raw-23503-как-FAILED_PRECONDITION-путь на create упразднён; FK — backstop). **Conformance-lock тест** ассертит byte-identity кода + текста + reason-token через все три consumer-ребра И geo-direct. Полный тон-лист:
    - `"Region ru-central1 not found"` — `NOT_FOUND` (direct/within-service), `reason:REGION_NOT_FOUND`
    - `"Zone ru-central1-a not found"` — `FAILED_PRECONDITION` (consumer peer-miss), `reason:ZONE_NOT_FOUND`
    - `"region ru-central1 is not empty"` — `FAILED_PRECONDITION` (RESTRICT, delete)
    - `"zone ru-central1-a is not open for placement"` — `FAILED_PRECONDITION` (consumer-gate), `reason:ZONE_NOT_OPEN`
    - `"zone ru-central1-a has insufficient capacity for the requested configuration"` — `FAILED_PRECONDITION` (op.error, retriable), `reason:CAPACITY_UNAVAILABLE` · **NotContains host-class-токен** (rule 3)
    - `"zone id 'ru-central1-a' must be prefixed by its regionId 'eu-west1'"` — `INVALID_ARGUMENT` (first-statement)
    - `"invalid zone id 'ZZ!'"` — `INVALID_ARGUMENT` (malformed, first-statement, в т.ч. на consumer-пути)
    - `"regionId is immutable after Zone.Create"` — `INVALID_ARGUMENT`
    - peer geo недоступен для consumer'а → `UNAVAILABLE` (fail-closed)
    - `INTERNAL` — фиксированный opaque-текст, никогда pgx/SQL-leak.

14. **JSON camelCase; timestamps truncate-to-seconds; vendor-agnostic.** `regionId`/`zoneId`/`countryCode`/`openForPlacement`/`placementBlockedReason`/`openZoneCountHint`/`createdAt`; `createdAt°` усечён до секунд на wire (БД хранит микросекунды). Никаких брендов чужих облаков в полях/типах/enum-значениях (ban #2) — узнаваемость через знакомую форму (`ru-central1-a`), не бренд.

15. **Discovery рядом с launch, item == public projection, lean-но-полный.** `ZoneService.List`/`RegionService.List` (sync) — каталог «что можно выбрать» для placement всех доменов; фильтр `openForPlacement=true` + derived `openForPlacement°` (учитывает статус родит-региона) = «открыто для размещения». **Item каталога == полная публичная проекция** (несёт `name`, диагностику; для Region — `countryCode°`/`openZoneCountHint°`; `placementType°` не несёт — удалён) — picker рисует лейблы без +N `Get`. Item **не несёт `use°`-обёртку**: `item.id` ЯВЛЯЕТСЯ координатой. `openZoneCountHint°` — advisory-hint для region-лейбла без второго вызова; authoritative счёт picker получает из `ListZones?openForPlacement=true` бесплатно (инвариант на hint не строить). Каталог **advisory, не lease** — на отказе re-discover.

16. **Fail-safe DOWN by default, но тихий no-op — ГРОМКИЙ в Operation.response.** Fresh Region/Zone поднимаются `status=DOWN` (security-обоснованный fail-safe; admin ЯВНО открывает). Но самый частый admin-вызов (omit optional `status`) НЕ должен молча возвращать `200 Operation{done:true}` для полностью созданной топологии, в которую НИ ОДИН tenant не может разместиться. Когда результат резолвится в `openForPlacement°=false` (или `openZoneCountHint°==0`), `Operation.response` несёт top-level `warnings°`-запись: `"<Resource> <id> created but CLOSED to placement (status DOWN); no tenant can place here — Internal Update status=UP to open"`. `warnings°` уже в spine (validateOnly) — переиспользуем канал, дефолт не трогаем. Держит предсказуемый инвариант «создал X ⇒ либо X работает, либо мне громко сказали почему нет» — ошибка не всплывает лишь через немой placement-fail в другом модуле.
