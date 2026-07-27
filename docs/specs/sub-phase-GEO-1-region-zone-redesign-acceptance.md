# Sub-phase GEO-1 (Region/Zone redesign) — Acceptance

> Статус: **✅ APPROVED** (ре-ревью раунд 2, acceptance-reviewer, 2026-07-20) — implementation-ready; 5 open questions разрешены как зафиксированные дефолты (см. §Дефолты, зафиксированные на review). Замечания при approve — non-blocking (см. review-комментарий).
> Дата: 2026-07-20
> Ревьюер: acceptance-reviewer (APPROVED 2026-07-20)
> Эпик/тикет: KAC-GEO-1 (Phase-1 leaf, redesign-2026; ничем не блокирован)
> Монорепо: `project/kacho` (`github.com/PRO-Robotech/kacho`) — легаси `project/kacho-*` не затрагивается.

## Обзор

GEO-1 — первый инкремент программы пересборки-2026. `kacho-geo` — leaf-владелец **оси
размещения** (Region/Zone); любая placement-coherence-проверка всего продукта резолвит
`zone.regionId` здесь. Под-фаза приводит owner-side проекции Region/Zone к целевому
tenant-facing дизайну (`docs/plans/kacho-redesign-2026/module-geo.md`) и общему хребту
(`00-unified-system-design.md` §1 конв-2/8/9/11/12, §5 инв-1/4/5): публичная поверхность
становится **чистой read-discovery оси размещения** с единственным actionable-сигналом
`openForPlacement°`; сырой admin-флаг `status` и весь `infra°`-блок уходят в **two-projection**
(`Internal*` :9091 — и readable, и writable); свежий ресурс поднимается `status=DOWN`
(fail-safe), а тихий no-op делается **громким** в `Operation.response`; admin-мутации
возвращают **синхронно-завершённый** `Operation{done:true}` (config-INSERT, без саги);
`id` остаётся человеко-осмысленным **slug** — THE ONE задокументированный carve-out.

Это **owner-side** под-фаза: сценарии описывают наблюдаемое поведение публичного
(`RegionService`/`ZoneService`) и internal (`InternalRegionService`/`InternalZoneService`)
API `kacho-geo`. Consumer-side placement-валидация и corelib-хелперы — отдельные под-фазы
(см. §Out-of-scope).

---

## Scope

Что GEO-1 покрывает сценариями (positive + negative + edge):

| # | Фича | Traceability |
|---|---|---|
| F1 | Two-projection: сырой `status` (UP/DOWN) и `infra°` — **только Internal**, и readable (`GetInternal`), и writable (`Internal*.Create`/`Update`) | module-geo rule 5/9; unified §1 conv-8, §5 инв-1 |
| F2 | Derived `openForPlacement°` — единственный публичный placement-сигнал (`zone.status==UP && region.status==UP`; Region: `status==UP`) | module-geo rule 3/6; unified §5 инв-1 |
| F3 | `placementBlockedReason° ∈ {NONE,ZONE_DOWN,REGION_DOWN}` — только на Zone (не на Region) | module-geo rule 3; unified §2 geo, §5 инв-1 (accepted carve-out) |
| F4 | Fresh-default fail-safe `status=DOWN`; тихий no-op сделан громким через `warnings°` в geo-owned `Operation.metadata` (НЕ public response) | module-geo rule 4/16, §Правила rule 11; unified §5 инв-4 |
| F5 | Async-форма: admin-мутации → синхронно-завершённый `Operation{done:true, metadata, response}`; internal REST под `/geo/v1/internal/…` | module-geo rule 4/6; unified §1 conv-2, §3 |
| F6 | Ambient public-read authz: project-scope **EXEMPT** (один зафиксированный механизм); admin-CRUD → `system_admin` | module-geo rule 5; unified §1 conv-9 (documented exception) |
| F7 | Discovery-item == полная public-проекция per item (Region: `countryCode°` + `openZoneCountHint°` read-time rollup); lean-subset убран | module-geo rule 15, Discovery-каталог; unified §1 conv-5 |
| F8 | slug-id carve-out; coupling `zone.id == regionId + "-" + <zoneSuffix>` (строгий startsWith); malformed slug → `INVALID_ARGUMENT` первым стейтментом | module-geo rule 7; unified §1 conv-12 |
| F9 | Ось (ZONAL/REGIONAL) **не эмитится полем** — `placementType`/`placementScope` отсутствуют на всех проекциях (derived-by-service) | module-geo rule 1; unified §2 geo |
| F10 | Тон ошибок by-lane `[PHASE-0-GATED]`: within-service create absent-parent → `NOT_FOUND "Region <id> not found"` + reason-token (gated); capacity-ошибка **обезличена** (без host-class — ungated) | module-geo rule 3/13; unified §1 conv-11, §5 инв-5 |
| F11 | Input-validation negatives: `name` обязателен (global-UNIQUE label); `countryCode°` формат ISO-3166 alpha-2 на Create/Update | module-geo rule 9/10, §Правила rule 11 |

## Out-of-scope (явно НЕ в GEO-1)

- **GEO-2** (net-new, отдельная под-фаза — вынесено на ре-ревью раунд 1): one-shot `Region`+`zoneSpecs`
  (atomic multi-row TX в одной Operation) и `validateOnly:true` sync dry-run (`resolved°`-echo +
  `warnings°`, без мутации/state-gate). Оба — spine conv-4/conv-6 (geo ✓ в unified §1), но вне 10
  обязательных фич GEO-1 и **net-new** (atomic multi-row + dry-run path). Перенесены из черновика
  GEO-1 (сценарии-кандидаты `GEO-2-01` one-shot / `GEO-2-02` validateOnly). Single-resource
  Create/Update покрывает fresh-DOWN + `warnings°` (F4) без zoneSpecs.
- **GEO-CORELIB** (отдельная под-фаза): приземление `corevalidate.GeoSlug` в `pkg/validate`
  (corelib), first-class kind `GEO_COORDINATE` в shared prefix→type-router, и
  `geoconsumer.ValidatePlacement(ctx, geoClient, zoneId|regionId)`. **Подтверждено**: `GeoSlug`
  в `pkg/` сейчас нет. GEO-1 использует **geo-local** slug-валидацию (`internal/domain.ValidateID`,
  уже существует), приведённую к целевому charset/coupling; централизация — GEO-CORELIB.
- **Consumer-side placement-edges** `vpc→geo` / `compute→geo` / `nlb→geo` (peer-validate,
  open-gate, per-call deadline, code/text-remap, reason-token conformance-lock через 3 ребра) —
  свои под-фазы каждого consumer'а. GEO-1 фиксирует **только geo-direct** тон ошибок и
  reason-token; cross-consumer byte-identity — не здесь.
- **Actual capacity-fail emission** at schedule-time — consumer-side (compute Instance.Create).
  GEO-1 владеет только **контрактом** обезличенной capacity-строки (текст + `reason` +
  regression `NotContains host-class`) и two-projection-гарантией, что host-class физически
  не выходит на public. geo сам capacity-ошибку не эмитит (config-INSERT, нет scheduler).
- **Downstream FGA-catalog-tuple** (`geo_outbox` register-drainer/reconciler) — материализуется
  eventually; GEO-1 не гейтит admin-ответ на его видимость (ban #9). Behaviour outbox — не меняется.

## Traceability-легенда

`°` = output-only поле (server-derived, на вход не принимается). Каждый сценарий несёт
ссылку `→ module-geo rule N` / `→ unified §X` в теле. REST-пути: public `/geo/v1/…` (:9090,
external-safe); admin `/geo/v1/internal/…` (:9091, НИКОГДА на external). JSON — camelCase.
`createdAt°` усечён до секунд на wire.

---

## F1 — Two-projection: `status` + `infra°` только Internal (read+write)

> `→ module-geo` rule 5/9 · `→ unified §1 conv-8, §5 инв-1`
> AS-IS: `Zone.status` (UP/DOWN) сейчас на **публичном** `Zone`-message (leak); `Region`
> **вовсе не несёт** `status`; ни `infra°`, ни `GetInternal` не существуют. GEO-1 закрывает
> two-projection и readable-but-unwritable дыру.
> **Two-projection через РАЗНЫЕ messages, НЕ runtime-omit (дефолт review):** публичные `Zone`/`Region`
> и internal `InternalZone`/`InternalRegion` — отдельные proto-messages; сырой `status` + `infra°`
> физически существуют **только** в internal-message. Удаление поля `status` из публичного `Zone` —
> **breaking** proto-change (см. §Definition of Done, AS-IS-удаления); для Region `status`/`infra°`
> вводятся сразу только в `InternalRegion`.

### Сценарий GEO-1-01: infra° принимается на `InternalZoneService.Create` и читается через GetInternal

**ID:** GEO-1-01

**Given** регион `ru-central1` существует со `status=UP`
**And** вызывающий — `system_admin`, запрос идёт на internal-листенер (:9091)

**When** клиент вызывает `InternalZoneService.Create` (`POST /geo/v1/internal/zones`) с payload:
  - `id` = `"ru-central1-a"`
  - `regionId` = `"ru-central1"`
  - `name` = `"RU Central 1 — Zone A"`
  - `status` = `"UP"`
  - `infra` = `{ numericInfraId: 10402, hostClasses: ["std-v3","mem-v2"], failureDomainCount: 3, underlayAnchor: "fd00:ru1a::/48", capacityHint: "AMPLE" }`

**Then** ответ — `Operation{done:true}`; `metadata.zoneId == "ru-central1-a"`; `result.response` анмаршалится в **public** `Zone` (см. GEO-1-02 состав)
**And** последующий `InternalZoneService.GetInternal` (`GET /geo/v1/internal/zones/ru-central1-a`) возвращает `InternalZone` со `status=="UP"` и полным `infra` (`numericInfraId==10402`, `hostClasses==["std-v3","mem-v2"]`, `failureDomainCount==3`, `underlayAnchor=="fd00:ru1a::/48"`, `capacityHint=="AMPLE"`)

### Сценарий GEO-1-02: публичный ZoneService.Get НЕ содержит `status` и `infra°` (assert отсутствия полей)

**ID:** GEO-1-02

**Given** зона `ru-central1-a` создана как в GEO-1-01 (`status=UP`, полный `infra`)

**When** клиент вызывает `ZoneService.Get` (`GET /geo/v1/zones/ru-central1-a`) на публичном листенере

**Then** ответ — public `Zone` **строго** с полями: `id`, `regionId`, `name`, `openForPlacement°`, `placementBlockedReason°`, `createdAt°`
**And** в ответе **ОТСУТСТВУЮТ** поля `status`, `infra`, `numericInfraId`, `hostClasses`, `failureDomainCount`, `underlayAnchor`, `capacityHint` (assert field-absence — сырой admin-флаг и инфра не текут на public)
**And** `openForPlacement° == true` (derived: `zone.status==UP && region.status==UP`)

### Сценарий GEO-1-03: публичный RegionService.Get НЕ содержит `status` и `infra°`

**ID:** GEO-1-03

**Given** регион `ru-central1` создан со `status=UP` и region-infra `{ numericInfraId: 900 }`

**When** клиент вызывает `RegionService.Get` (`GET /geo/v1/regions/ru-central1`)

**Then** ответ — public `Region` **строго** с полями: `id`, `name`, `countryCode°`, `openForPlacement°`, `openZoneCountHint°`, `createdAt°`
**And** в ответе **ОТСУТСТВУЮТ** `status`, `infra`, `numericInfraId`, `capacityHint`

### Сценарий GEO-1-04: infra° мутабельна через Internal Update; numericInfraId° immutable-after-create

**ID:** GEO-1-04

**Given** зона `ru-central1-a` создана с `infra.numericInfraId==10402`, `capacityHint="AMPLE"`

**When** клиент (`system_admin`) вызывает `InternalZoneService.Update` (`PATCH /geo/v1/internal/zones/ru-central1-a`) с `updateMask=["infra.capacityHint","infra.hostClasses"]` и `infra.capacityHint="CONSTRAINED"`, `infra.hostClasses=["std-v3"]`

**Then** ответ `Operation{done:true}`; `GetInternal` показывает `capacityHint=="CONSTRAINED"`, `hostClasses==["std-v3"]`

**When** тот же admin вызывает `InternalZoneService.Update` с `updateMask=["infra.numericInfraId"]` и `infra.numericInfraId=99999`

**Then** синхронный `INVALID_ARGUMENT` с текстом `"numericInfraId is immutable after Zone.Create"` (immutable-switch срабатывает **до** `corevalidate.UpdateMask`)

### Сценарий GEO-1-05 (edge): capacity-контракт обезличен — host-class физически не на public

**ID:** GEO-1-05

**Given** зона `ru-central1-a` создана с `infra.hostClasses=["std-v3","gpu-a1"]`, `capacityHint="FULL"`

**When** любой публичный запрос (`ZoneService.Get`, `ZoneService.List`, `RegionService.Get/List`) возвращает эту зону/её регион

**Then** сериализованное тело ответа **NotContains** ни один host-class-токен (`"std-v3"`, `"gpu-a1"`) и не содержит `capacityHint` — это **two-projection security-инвариант, НЕ Phase-0-gated** (действует в GEO-1 безусловно)
**And** канонический обезличенный текст capacity-ошибки контракта — `"zone ru-central1-a has insufficient capacity for the requested configuration"` (`FAILED_PRECONDITION`, retriable) — **NotContains** host-class-токен (текст + NotContains — ungated)
**And** `[PHASE-0-GATED]` только detail `reason:"CAPACITY_UNAVAILABLE"` в `google.rpc.Status.details` — приземляется после Phase-0 reason-token таблицы (см. §Definition of Done merge-gate); текст и `NotContains host-class` от гейта НЕ зависят

> Примечание scope: сам capacity-fail эмитится consumer'ом на schedule-time (out-of-scope). GEO-1
> владеет two-projection-гарантией (host-class только в `GetInternal.infra°`) и **контрактом текста**
> обезличенной ошибки (regression-lock `NotContains`). `→ module-geo` rule 3.

---

## F2 — Derived `openForPlacement°` (единственный публичный placement-сигнал)

> `→ module-geo` rule 3/6 · `→ unified §5 инв-1`
> Формула деривации несётся godoc в точке использования: «administratively open; NOT a
> capacity/health guarantee — Create may still fail on capacity at schedule time».

### Сценарий GEO-1-06: openForPlacement° = zone.status==UP && region.status==UP (оба UP)

**ID:** GEO-1-06

**Given** регион `ru-central1` `status=UP`; зона `ru-central1-a` `status=UP`

**When** `ZoneService.Get(ru-central1-a)`

**Then** `openForPlacement° == true`; `placementBlockedReason° == "NONE"`

### Сценарий GEO-1-07: зона UP, но регион DOWN → openForPlacement°=false, reason=REGION_DOWN

**ID:** GEO-1-07

**Given** регион `ru-central1` `status=DOWN` (admin вывёл регион на обслуживание)
**And** зона `ru-central1-a` `status=UP`

**When** `ZoneService.Get(ru-central1-a)`

**Then** `openForPlacement° == false` (region.status!=UP ⇒ AND-формула false)
**And** `placementBlockedReason° == "REGION_DOWN"` (precedence: zone.status==DOWN⇒ZONE_DOWN; иначе region.status==DOWN⇒REGION_DOWN)

### Сценарий GEO-1-08: зона DOWN, регион UP → openForPlacement°=false, reason=ZONE_DOWN

**ID:** GEO-1-08

**Given** регион `ru-central1` `status=UP`; зона `ru-central1-a` `status=DOWN`

**When** `ZoneService.Get(ru-central1-a)`

**Then** `openForPlacement° == false`; `placementBlockedReason° == "ZONE_DOWN"`

### Сценарий GEO-1-09: Region.openForPlacement° = region.status==UP

**ID:** GEO-1-09

**Given** регион `ru-central1` `status=DOWN`

**When** `RegionService.Get(ru-central1)`

**Then** `openForPlacement° == false` (Region: derived напрямую из `status==UP`)
**And** Region-проекция **не** несёт `placementBlockedReason°` (см. F3/GEO-1-11)

---

## F3 — `placementBlockedReason°` только на Zone (не на Region)

> `→ module-geo` rule 3 · `→ unified §2 geo` (accepted two-projection carve-out)

### Сценарий GEO-1-10: Zone несёт placementBlockedReason° во всех состояниях

**ID:** GEO-1-10

**Given** зоны: `z-up` (openForPlacement°=true), `z-zonedown` (zone DOWN), `z-regiondown` (region DOWN)

**When** `ZoneService.Get` каждой

**Then** `z-up.placementBlockedReason° == "NONE"`; `z-zonedown == "ZONE_DOWN"`; `z-regiondown == "REGION_DOWN"` — один вызов различает zone-down vs region-down без второго `RegionService.Get`

### Сценарий GEO-1-11: Region НЕ несёт placementBlockedReason° (assert field-absence)

**ID:** GEO-1-11

**Given** регион `ru-central1` `status=DOWN`

**When** `RegionService.Get(ru-central1)`

**Then** ответ **не содержит** поля `placementBlockedReason` (на Region enum схлопнулся бы в биекцию `openForPlacement°` — удалён by construction; godoc `openForPlacement°` гласит «Region: when false, cause is always REGION_DOWN by construction»)

---

## F4 — Fresh-default fail-safe DOWN + громкий no-op через `warnings°`

> `→ module-geo` rule 4/16, §Правила rule 11 · `→ unified §5 инв-4`
> AS-IS: сейчас Zone.Create с омитнутым `status` коэрсится в **UP** (`zone.go` use-case:
> `if st==Unspecified { st = Up }`), DB-DEFAULT тоже `'UP'`. GEO-1 инвертирует дефолт в **DOWN**
> (implementer обязан **удалить** UP-коэрсинг и сменить DB-DEFAULT на `'DOWN'`).
> **Дефолт (review): `warnings°` живут в geo-owned metadata-message** (`CreateRegionMetadata` /
> `CreateZoneMetadata` получают `repeated string warnings`), **НЕ** в shared `Operation`-proto и
> **НЕ** в public `Region`/`Zone` response (иначе warnings утекут в публичный `Get`).

### Сценарий GEO-1-12: свежая зона без status поднимается DOWN + громкий warning

**ID:** GEO-1-12

**Given** регион `ru-central1` `status=UP`; вызывающий — `system_admin`

**When** `InternalZoneService.Create` (`POST /geo/v1/internal/zones`) с payload **без** `status`:
  - `id` = `"ru-central1-d"`
  - `regionId` = `"ru-central1"`
  - `name` = `"RU Central 1 — Zone D"`

**Then** `Operation{done:true}`; `result.response` — **public** Zone с `openForPlacement° == false` (fresh default `status=DOWN`); `result.response` **НЕ** несёт поля `warnings` (не утечёт в публичный Get)
**And** `GetInternal(ru-central1-d).status == "DOWN"` (persisted fail-safe)
**And** `Operation.metadata` анмаршалится в `CreateZoneMetadata`; `metadata.warnings[0]` дословно `"zone ru-central1-d created but CLOSED to placement (status DOWN); no tenant can place here — Internal Update status=UP to open"` (warnings° в geo-owned metadata-message, НЕ в shared Operation-proto, НЕ в public response)

### Сценарий GEO-1-13: свежий регион без status поднимается DOWN + громкий warning

**ID:** GEO-1-13

**When** `InternalRegionService.Create` (`POST /geo/v1/internal/regions`) с payload **без** `status`:
  - `id` = `"eu-west1"`
  - `name` = `"EU West 1"`
  - `countryCode` = `"NL"`

**Then** `Operation{done:true}`; `result.response.openForPlacement° == false`; `openZoneCountHint° == 0`; `result.response` **НЕ** несёт `warnings`
**And** `GetInternal(eu-west1).status == "DOWN"`
**And** `Operation.metadata` анмаршалится в `CreateRegionMetadata`; `metadata.warnings[0]` дословно `"region eu-west1 created but CLOSED to placement (status DOWN); no tenant can place here — Internal Update status=UP to open"`

### Сценарий GEO-1-14: явный status=UP → open, без warning

**ID:** GEO-1-14

**When** `InternalRegionService.Create` с `id="ru-central1"`, `name="RU Central 1"`, `countryCode="RU"`, `status="UP"`, `infra={numericInfraId:900}`

**Then** `Operation{done:true}`; `result.response.openForPlacement° == true`
**And** `Operation.metadata` (`CreateRegionMetadata`) несёт **пустой** `warnings` (результат резолвится в open ⇒ no-op не тихий)

### Сценарий GEO-1-15: admin ЯВНО открывает DOWN-зону через Update status=UP

**ID:** GEO-1-15

**Given** зона `ru-central1-d` существует со `status=DOWN` (из GEO-1-12); регион `ru-central1` `status=UP`

**When** `InternalZoneService.Update` (`PATCH /geo/v1/internal/zones/ru-central1-d`) с `updateMask=["status"]`, `status="UP"`

**Then** `Operation{done:true}`; последующий `ZoneService.Get(ru-central1-d).openForPlacement° == true`

---

## F5 — Async-форма: синхронно-завершённый `Operation{done:true}`; internal path `/geo/v1/internal/…`

> `→ module-geo` rule 4/6 · `→ unified §1 conv-2, §3`
> AS-IS: сейчас Internal Create/Update/Delete возвращают `Operation{done:false}` (async LRO,
> клиент поллит); REST на `/geo/v1/regions`, `/geo/v1/zones`. GEO-1: **done:true немедленно**,
> unwrap `.response`; internal REST переезжает под самоописываемый `/geo/v1/internal/…`.

### Сценарий GEO-1-16: happy-path Create — done:true немедленно, unwrap .response

**ID:** GEO-1-16

**Given** вызывающий — `system_admin` на :9091

**When** `InternalRegionService.Create` (`POST /geo/v1/internal/regions`) с `id="ru-central1"`, `name="RU Central 1"`, `countryCode="RU"`, `status="UP"`

**Then** **в том же** ответе: `Operation.done == true` (config-INSERT, без саги)
**And** `Operation.metadata` анмаршалится в `CreateRegionMetadata{regionId:"ru-central1"}` (id доступен сразу)
**And** `Operation.result` — `response` (не `error`); анмаршал даёт **полное** тело public `Region` (`id`, `name`, `countryCode°=="RU"`, `openForPlacement°==true`, `openZoneCountHint°==0`, `createdAt°` усечён до секунд)
**And** повторный `OperationService.Get(op.id)` (`GET /geo/v1/internal/operations/{id}`) возвращает тот же `done:true` (поллить не требуется — unwrap `.response` достаточно)

### Сценарий GEO-1-17: internal-путь НЕ резолвится на external endpoint

**ID:** GEO-1-17

**Given** api-gateway с раздельными public (:9090) и internal (:9091) mux

**When** клиент шлёт `POST /geo/v1/internal/regions` на **external** TLS endpoint (:443/public)

**Then** запрос **не выполняет мутацию**; «method-not-available» конкретно = public REST-mux **не несёт route** на `/geo/v1/internal/…` (routing-miss) **И** `InternalRegionService`-методы **отсутствуют** в public gRPC-allowlist → `Unimplemented` (не bare 404, не мутация)
**And** `/geo/v1/internal/…` резолвится ТОЛЬКО на :9091 под `system_admin` (ban #6); ассерт на **e2e-уровне** (территория `api-gateway-registrar`)

### Сценарий GEO-1-18: Delete непустого региона → op.error FAILED_PRECONDITION "region … is not empty"

**ID:** GEO-1-18

**Given** регион `ru-central1` c ≥1 зоной (`ru-central1-a`)

**When** `InternalRegionService.Delete` (`DELETE /geo/v1/internal/regions/ru-central1`)

**Then** `Operation{done:true}` с `result.error` (не `response`): код `FAILED_PRECONDITION`, текст `"region ru-central1 is not empty"` (within-service FK RESTRICT `zones.region_id`, ban #10 — DB-backstop, не software-precheck)

### Сценарий GEO-1-19: malformed id на Create → синхронный INVALID_ARGUMENT (операция не пишется)

**ID:** GEO-1-19

**When** `InternalRegionService.Create` с `id="ZZ!"` (не-slug)

**Then** **синхронный** `INVALID_ARGUMENT` (не Operation) с текстом `"invalid region id 'ZZ!'"` — malformed ловится первым стейтментом, LRO-строка не создаётся

---

## F6 — Ambient public-read authz (project-scope EXEMPT); admin-CRUD system_admin

> `→ module-geo` rule 5 · `→ unified §1 conv-9` (documented exception, как iam JWKS-route)
> AS-IS: public read сейчас `required_relation="viewer"`, `scope_extractor{object_type:"cluster",
> from_request_field:"*"}` — требует cluster#viewer-tuple. GEO-1 фиксирует **ОДИН** механизм:
> **project-scope EXEMPT** — любой аутентифицированный принципал читает каталог (не auto-grant
> `system_viewer`, не either/or).
> **Дефолт (review): механизм = снять `required_relation` + `scope_extractor` у 4 read-RPC**
> (`RegionService.Get/List`, `ZoneService.Get/List`) → **authN-only** (отклонён alt-вариант
> auto-satisfied `cluster`-viewer). permission-catalog regen обязан остаться **byte-identical**
> (iam-seed ↔ gateway-middleware); documented-exception дописывается в `security.md` (как note про
> JWKS-route) — это **deliverable GEO-1** (см. §Definition of Done).

### Сценарий GEO-1-20: fresh zero-binding project читает regions/zones (ambient)

**ID:** GEO-1-20

**Given** свежесозданный project **без единого AccessBinding** (zero-binding); аутентифицированный tenant-принципал этого проекта (валидный JWT)
**And** 4 read-RPC (`RegionService.Get/List`, `ZoneService.Get/List`) объявлены **project-scope EXEMPT**: у них снят `required_relation` + `scope_extractor` (authN-only)
**And** каталог содержит `ru-central1` + `ru-central1-a`

**When** принципал вызывает `RegionService.List` (`GET /geo/v1/regions`) и `ZoneService.Get` (`GET /geo/v1/zones/ru-central1-a`)

**Then** оба — `200 OK` (не `403`): per-RPC authz-Check не требует ни viewer-tuple, ни project-scope; каждый tenant обязан читать каталог, чтобы launch'ить любой размещаемый ресурс (`zoneId`/`regionId` берутся отсюда)
**And** e2e construction-verified (не описательно): zero-binding принципал реально получает каталог через api-gateway

### Сценарий GEO-1-21: неаутентифицированный запрос → отказ (EXEMPT ≠ anonymous)

**ID:** GEO-1-21

**Given** запрос без валидного JWT/mTLS-identity

**When** `RegionService.List`

**Then** отказ на AuthN-уровне (`UNAUTHENTICATED`) — project-scope EXEMPT снимает **authZ** project-скоуп, но **authN** обязателен на каждом листенере (unified §1 conv-9); anonymous-full-access запрещён

### Сценарий GEO-1-22: admin-CRUD требует system_admin

**ID:** GEO-1-22

**Given** аутентифицированный tenant-принципал **без** `system_admin`

**When** принципал вызывает `InternalRegionService.Create` на internal-листенере

**Then** `PERMISSION_DENIED` — admin-CRUD гейтится `system_admin` (`scope_extractor` резолвит well-known `system:catalog`, не target→project — geo вне Project)

### Сценарий GEO-1-23 (edge): iam недоступен на admin-мутации → fail-closed

**ID:** GEO-1-23

**Given** `InternalIAMService.Check` недоступен (peer down)

**When** `InternalRegionService.Create`

**Then** `PERMISSION_DENIED "authorization service unavailable"` — fail-closed, **никогда** allow (Internal-листенер не освобождён от authz-Check)

---

## F7 — Discovery-item == полная public-проекция; убран lean-subset

> `→ module-geo` rule 15, Discovery-каталог · `→ unified §1 conv-5`

### Сценарий GEO-1-24: ListZones item несёт полный public-shape (name присутствует)

**ID:** GEO-1-24

**Given** зоны `ru-central1-a` (UP), `ru-central1-b` (UP), `ru-central1-d` (DOWN) в регионе `ru-central1` (UP)

**When** `ZoneService.List` (`GET /geo/v1/zones?regionId=ru-central1&openForPlacement=true`)

**Then** массив `zones[]` содержит `ru-central1-a`, `ru-central1-b` (не `ru-central1-d` — отфильтрована `openForPlacement=true`)
**And** каждый item несёт **полную** public-проекцию: `id`, `regionId`, `name` (не reduced-subset), `openForPlacement°`, `placementBlockedReason°`, `createdAt°`
**And** ни один item **не** несёт `status`/`infra`/`placementType`

### Сценарий GEO-1-25: ListRegions item несёт countryCode° + openZoneCountHint° read-time rollup

**ID:** GEO-1-25

**Given** регион `ru-central1` (UP, `countryCode=RU`) c зонами: 2 UP (`-a`,`-b`) + 1 DOWN (`-d`)

**When** `RegionService.List` (`GET /geo/v1/regions?openForPlacement=true`)

**Then** item `ru-central1` несёт `id`, `name`, `countryCode° == "RU"`, `openForPlacement° == true`, `openZoneCountHint° == 2` (read-time COUNT зон с `openForPlacement°=true`; **не** persisted denorm-поле), `createdAt°`
**And** `openZoneCountHint°` — **advisory-hint**: authoritative source = `ZoneService.List?openForPlacement=true` (расхождение возможно, инвариант на hint не строить)

### Сценарий GEO-1-26: openForPlacement=true фильтр учитывает статус родит-региона

**ID:** GEO-1-26

**Given** регион `ru-central1` `status=DOWN`; его зоны `ru-central1-a`,`-b` со `status=UP`

**When** `ZoneService.List` (`GET /geo/v1/zones?regionId=ru-central1&openForPlacement=true`)

**Then** массив `zones[]` **пуст** — derived `openForPlacement°` каждой зоны false (region DOWN), фильтр их исключает; сырого `?status=UP` на public нет (единственный placement-фильтр — `openForPlacement`)

### Сценарий GEO-1-27 (negative): garbage page_token → INVALID_ARGUMENT ДО authz-short-circuit

**ID:** GEO-1-27

**Given** аутентифицированный принципал

**When** `ZoneService.List` (`GET /geo/v1/zones?pageToken=%%%not-base64%%%`)

**Then** `INVALID_ARGUMENT` (format-validate `pageToken`/`pageSize`/id-slug **до** authz-short-circuit; `pageSize>1000` → `INVALID_ARGUMENT`, отвергается не clamp'ится)

---

## F8 — slug-id carve-out + coupling `zone.id == regionId + "-" + <zoneSuffix>`

> `→ module-geo` rule 7 · `→ unified §1 conv-12`
> GEO-1 использует geo-local slug-валидацию (`domain.ValidateID`, charset `^[a-z][a-z0-9]*(-[a-z0-9]+)*$`,
> ≤63); coupling-check и его текст — **новые** (сейчас не энфорсятся). Централизация в
> `corevalidate.GeoSlug` + kind `GEO_COORDINATE` — GEO-CORELIB (out-of-scope).
> **AS-IS behavior-change (GEO-1-32):** `UpdateZoneRequest.region_id` + zone use-case СЕЙЧАС позволяют
> менять `regionId` (mutable, COALESCE-update). Redesign делает `regionId` **immutable**; implementer
> обязан **удалить** regionId-update-путь (поле остаётся только для immutable-reject, из mask known-set
> исключается).
> **AS-IS behavior-change (GEO-1-19/31):** текст malformed-id меняется с
> `"<field> must be a lowercase slug (…)"` (текущий `domain.ValidateID`) на конвенционный
> `"invalid <res> id '<X>'"` (`api-conventions.md` тон) — implementer правит текст.

### Сценарий GEO-1-28: slug-id принимается как human-координата (не 3-char base32)

**ID:** GEO-1-28

**When** `InternalRegionService.Create` с `id="ru-central1"`; затем `InternalZoneService.Create` с `id="ru-central1-a"`, `regionId="ru-central1"`

**Then** оба `Operation{done:true}` — `id` человеко-осмысленный slug принят (THE ONE carve-out из 3-char-prefix+crockford-base32); immutable после Create

### Сценарий GEO-1-29 (negative): coupling нарушен — zone.id не префиксован своим regionId

**ID:** GEO-1-29

**Given** регион `eu-west1` существует

**When** `InternalZoneService.Create` с `id="ru-central1-a"`, `regionId="eu-west1"`

**Then** **синхронный** `INVALID_ARGUMENT` первым стейтментом, текст `"zone id 'ru-central1-a' must be prefixed by its regionId 'eu-west1'"` (проверка charset + region-prefix ДО любого FK-резолва)

### Сценарий GEO-1-30 (edge): строгий startsWith — контрпример `ru-central10-a` под `ru-central1` REJECT

**ID:** GEO-1-30

**Given** регион `ru-central1` существует; регион `ru-central10` НЕ существует

**When** `InternalZoneService.Create` с `id="ru-central10-a"`, `regionId="ru-central1"`

**Then** `INVALID_ARGUMENT "zone id 'ru-central10-a' must be prefixed by its regionId 'ru-central1'"` — строгий `startsWith(regionId + "-")`, а **не** голый `startsWith(regionId)`: `ru-central10-a` не начинается на `ru-central1-` (следующий символ `0`, не `-`) ⇒ REJECT (иначе ложно «префиксуется»)

### Сценарий GEO-1-31 (negative): malformed slug → INVALID_ARGUMENT первым стейтментом

**ID:** GEO-1-31

**When** `ZoneService.Get` (`GET /geo/v1/zones/ZZ!`) — id с недопустимым charset

**Then** синхронный `INVALID_ARGUMENT "invalid zone id 'ZZ!'"` (malformed ловится **до** repo-резолва)
**And** для well-formed-но-несуществующего (`GET /geo/v1/zones/ru-central1-x`) → `NOT_FOUND "Zone ru-central1-x not found"` (direct-read lane)

### Сценарий GEO-1-32: zone.regionId immutable после Create

**ID:** GEO-1-32

**Given** зона `ru-central1-a` (regionId=`ru-central1`)

**When** `InternalZoneService.Update` с `updateMask=["regionId"]`, `regionId="eu-west1"`

**Then** синхронный `INVALID_ARGUMENT "regionId is immutable after Zone.Create"` (immutable-switch до `UpdateMask`; перенос зоны между регионами сломал бы coherence всех размещённых ресурсов)

---

## F9 — Ось не эмитится полем (placementType/placementScope отсутствуют)

> `→ module-geo` rule 1 · `→ unified §2 geo`
> AS-IS **подтверждено**: в текущем geo-proto **нет** `placementType`/`placementScope`/
> `placement_scope` (grep — пусто). GEO-1 фиксирует это как инвариант (regression-lock:
> redesign НЕ добавляет ось-поле; consumer выводит ось из вызванного сервиса).
> **Решение (обосновано):** `placementType°` НЕ эмитится **вовсе** — ни на public, ни на
> internal, ни в discovery-item, ни в validateOnly-echo. Constant-by-type (Region ВСЕГДА
> REGIONAL, Zone ВСЕГДА ZONAL) = ноль бит; переиспользование имени Subnet-дискриминатора
> `placementType` ввело бы consumer'а, пишущего coherence-код, в заблуждение. Хранимый
> дискриминатор остаётся исключительно на Subnet-якоре (vpc).

### Сценарий GEO-1-33: ни одна geo-проекция не несёт placementType/placementScope

**ID:** GEO-1-33

**When** любой из: `ZoneService.Get/List`, `RegionService.Get/List`, `InternalZoneService.GetInternal`, `InternalRegionService.GetInternal`

**Then** сериализованное тело **не содержит** поля `placementType`, `placementScope`, `placement_type`, `placement_scope` (ось derived-by-service, не эмитится)

---

## F10 — Тон ошибок by-lane; within-service create absent-parent → NOT_FOUND

> `→ module-geo` rule 13, §Правила rule 11 · `→ unified §1 conv-11, §5 инв-5`
> AS-IS: сейчас standalone Zone.Create с несуществующим `regionId` доезжает FK 23503 →
> `FAILED_PRECONDITION` (async op.error). GEO-1 (by-lane §5): within-service create
> absent-parent — **direct-read lane** → `NOT_FOUND "Region <id> not found"` через pre-flight
> resolve; FK RESTRICT остаётся DB-backstop (create-race + delete-non-empty).
> **`[PHASE-0-GATED]`**: by-lane code-split (direct-read→`NOT_FOUND` / peer-validate→`FAILED_PRECONDITION`)
> и reason-token — **PROPOSED** до Phase-0 governance change-set (`00-unified §9 DT`); GEO-1-34 и
> `reason`-детали помечены гейтом (см. §Definition of Done merge-gate). **Уже-landed** (ungated) и
> остаются в GEO-1 безусловно: geo-direct absent→`NOT_FOUND "<Resource> <id> not found"` (БЕЗ reason),
> malformed→`INVALID_ARGUMENT`, dup→`ALREADY_EXISTS`, INTERNAL-opaque, immutable-текст.
> **AS-IS behavior-change (GEO-1-36):** `UNIQUE(name)` СЕЙЧАС НЕТ (`name TEXT NOT NULL DEFAULT ''`);
> redesign добавляет global `UNIQUE(name)` на обоих + делает `name` **обязательным** (новая миграция;
> каталог стартует пустым → backfill безопасен).

### Сценарий GEO-1-34 `[PHASE-0-GATED]`: standalone Zone.Create с несуществующим regionId → NOT_FOUND

**ID:** GEO-1-34

**Given** регион `eu-west1` НЕ существует

**When** `InternalZoneService.Create` с `id="eu-west1-a"`, `regionId="eu-west1"`, `name="Zone A"` (coupling валиден: id префиксован regionId)

**Then** `Operation{done:true}` c `result.error`: код `NOT_FOUND`, текст `"Region eu-west1 not found"`, detail `reason:"REGION_NOT_FOUND"` (within-service direct-read lane — pre-flight resolve; НЕ FAILED_PRECONDITION)

> `[PHASE-0-GATED]`: как by-lane code (`NOT_FOUND` вместо текущего `FAILED_PRECONDITION`-через-FK), так и
> `reason`-token приземляются **только** после Phase-0 governance change-set (by-lane split + reason-token
> таблица в `api-conventions.md`). До merge change-set поведение остаётся текущим FK-`FAILED_PRECONDITION`.
> Merge-gate — §Definition of Done.

### Сценарий GEO-1-35 `[PHASE-0-GATED]` (частично): geo-direct read несуществующего региона → NOT_FOUND + reason-token

**ID:** GEO-1-35

**When** `RegionService.Get` (`GET /geo/v1/regions/eu-west1`) — well-formed, отсутствует

**Then** `NOT_FOUND "Region eu-west1 not found"` — **ungated, уже-landed** (geo-direct absent — `serviceerr` уже маппит `ErrNotFound`→`NotFound`)
**And** `[PHASE-0-GATED]` только detail `reason:"REGION_NOT_FOUND"` — приземляется после Phase-0 reason-token таблицы (см. §Definition of Done merge-gate)

### Сценарий GEO-1-36: duplicate name → ALREADY_EXISTS (global UNIQUE label)

**ID:** GEO-1-36

**Given** регион `ru-central1` создан с `name="RU Central 1"`
**And** `name` — глобально UNIQUE label (нет project-scope ⇒ нет UNIQUE(project,name); `name` обязателен)

**When** `InternalRegionService.Create` с `id="ru-central2"`, `name="RU Central 1"` (дубль имени)

**Then** `Operation{done:true}` c `result.error`: `ALREADY_EXISTS` (UNIQUE(name), SQLSTATE 23505; DB-backstop)

### Сценарий GEO-1-37 (edge): INTERNAL никогда не эхает pgx/SQL-текст

**ID:** GEO-1-37

**Given** некатегоризированная DB-ошибка на write-пути (симулируется в integration-слое)

**When** admin-мутация упирается в неё

**Then** `result.error` — фиксированный opaque-текст (`"internal database error"`), **NotContains** driver/connection-текст (host/port/user/db); regression-lock проверяет **сообщение**, не только код

---

## F11 — Input-validation negatives (name / countryCode)

> `→ module-geo` rule 9/10, §Правила rule 11 · `→ unified §1 conv-11`
> `name` становится обязательным глобально-UNIQUE label (F10 AS-IS); `countryCode°` — LIVE-mutable
> ISO-3166 alpha-2, валидируемый на входе Internal Create/Update.

### Сценарий GEO-1-38 (negative): Create с пустым name → INVALID_ARGUMENT

**ID:** GEO-1-38

**Given** вызывающий — `system_admin`

**When** `InternalRegionService.Create` (`POST /geo/v1/internal/regions`) с `id="ru-central1"`, `countryCode="RU"`, **без** `name` (пустая строка)

**Then** **синхронный** `INVALID_ARGUMENT` первым стейтментом с текстом `"region name is required"` — `name` обязателен (global-UNIQUE label; операция в таблицу не пишется)
**And** то же для `InternalZoneService.Create` с пустым `name` → `INVALID_ARGUMENT "zone name is required"`

### Сценарий GEO-1-39 (negative): Create/Update с невалидным countryCode → INVALID_ARGUMENT

**ID:** GEO-1-39

**Given** вызывающий — `system_admin`

**When** `InternalRegionService.Create` с `id="ru-central1"`, `name="RU Central 1"`, `countryCode="RUS"` (3 буквы, не ISO-3166 alpha-2)

**Then** **синхронный** `INVALID_ARGUMENT` с текстом `"countryCode must be an ISO-3166 alpha-2 code"` (формат валидируется на входе: ровно 2 uppercase-буквы; варианты `"ru"`, `"R1"`, `""`-непустой-мусор — тот же отказ)
**And** тот же контракт на `InternalRegionService.Update` с `updateMask=["countryCode"]`, `countryCode="RUS"` (`countryCode°` LIVE-mutable, формат энфорсится и на Update)

---

## Definition of Done

GEO-1 считается готовой к merge только при выполнении ВСЕГО чек-листа (`ai-tooling.md` §lifecycle
gate 4-7; `testing.md`):

**Traceability + тесты (1-to-1):**
- [ ] Каждый `GEO-1-NN` имеет зелёный **integration-тест** (testcontainers Postgres) — `Test<Resource>_<ID>`
  (напр. `TestZone_GEO_1_01`) — покрывающий SQL-сторону, включая CAS/UNIQUE/FK/concurrent-race где применимо.
- [ ] Каждый `GEO-1-NN` (наблюдаемый через api-gateway) имеет зелёный **newman-кейс** `tests/newman/cases/*.py`
  с аннотацией `# verifies GEO-1-NN` — ≥1 happy + ≥1 negative per фича; трассировка `GEO-1-NN ↔ Test<R>_<ID> ↔ cases/*.py`.
- [ ] TDD-порядок соблюдён: RED (падает по нужной причине) ДО кода, пара RED→GREEN в PR.

**e2e-smoke (real gateway, construction-verified):**
- [ ] fresh **zero-binding** project читает каталог (`RegionService.List`/`ZoneService.Get`) → `200` (GEO-1-20).
- [ ] admin one-shot bootstrap: `InternalRegionService.Create(status=UP)` + N зон → каталог наполнен; `openForPlacement°` derived верно.
- [ ] two-projection field-absence на **реальном** gateway-ответе: public `Zone`/`Region` НЕ содержат `status`/`infra`/host-class (GEO-1-02/03/05/33).

**Deliverables редизайна (implementer обязан выполнить — иначе старый путь остаётся):**
- [ ] **AS-IS удаления/изменения:** снят UP-коэрсинг fresh-default (→ DOWN, DB-DEFAULT `'DOWN'`); удалён
  `regionId`-update-путь (immutable); public `Zone` теряет `status` (**breaking** proto — отдельный `InternalZone`-message);
  `Region` получает `status`/`infra°` только в `InternalRegion`; malformed-id текст → `"invalid <res> id '<X>'"`.
- [ ] Новая миграция: global `UNIQUE(name)` на `regions`/`zones`, `name` NOT NULL без DEFAULT (required); каталог
  пуст → backfill безопасен. **Не** редактировать применённые миграции (`0001`/`0002`/`0003`).
- [ ] `warnings°` реализованы как `repeated string warnings` в `CreateRegionMetadata`/`CreateZoneMetadata` (geo-owned
  metadata), НЕ в shared Operation-proto, НЕ в public response.
- [ ] Ambient-read: catalog-записи 4 read-RPC (`RegionService.Get/List`, `ZoneService.Get/List`) меняются на **exempt**
  (снят `required_relation`+`scope_extractor`); `make -C gateway permission-catalog` regen → обе embedded-копии **byte-identical**
  (`make -C gateway permission-catalog-check` зелёный); documented-exception дописан в `security.md` (note рядом с JWKS-route).

**Проектные гейты (финальная верификация):**
- [ ] `go test ./... -race` · `golangci-lint run` · `govulncheck` · `make audit-list-filter` зелёные.
- [ ] `make -C gateway permission-catalog-check` byte-identical; newman зелёные (все `GEO-1-NN`).

**MERGE-GATE (`[PHASE-0-GATED]` — жёсткий блокер, единственная кросс-фазовая зависимость):**
- [ ] **GEO-1 НЕ мёржится, пока Phase-0 governance change-set не приземлит в `api-conventions.md`:**
  (a) by-lane code-split таблицу (**direct-read → `NOT_FOUND`** / **peer-validate → `FAILED_PRECONDITION`**);
  (b) reason-token таблицу (`REGION_NOT_FOUND`/`ZONE_NOT_FOUND`/`ZONE_NOT_OPEN`/`CAPACITY_UNAVAILABLE`).
  До merge change-set: GEO-1-34 (within-service create absent-parent) остаётся текущим FK-`FAILED_PRECONDITION`;
  `reason`-детали GEO-1-05/34/35 не приземляются. Ungated части (geo-direct absent→`NOT_FOUND "<R> <id> not found"`
  БЕЗ reason, malformed→`INVALID_ARGUMENT`, dup→`ALREADY_EXISTS`, INTERNAL-opaque, immutable-текст, `NotContains host-class`)
  строятся в GEO-1 без ожидания.

---

## Changelog — что этот док покрывает

- **F1** two-projection: `status`+`infra°` только Internal (read+write), assert field-absence на public (GEO-1-01..05); capacity-контракт обезличен, `NotContains` host-class (GEO-1-05).
- **F2** derived `openForPlacement°` формула во всех 4 состояниях zone×region (GEO-1-06..09).
- **F3** `placementBlockedReason°` только на Zone; assert отсутствия на Region (GEO-1-10..11).
- **F4** fresh-default инвертирован UP→**DOWN** (fail-safe); громкий no-op через `warnings°` в **geo-owned `Operation.metadata`** (`CreateRegionMetadata`/`CreateZoneMetadata`, НЕ shared Operation-proto, НЕ public response); explicit-open path (GEO-1-12..15).
- **F5** async-форма: `Operation{done:true}` немедленно, unwrap `.response`; internal REST `/geo/v1/internal/…` не на external (routing-miss + `Unimplemented`); Delete-non-empty; malformed sync-reject (GEO-1-16..19).
- **F6** ambient public-read (project-scope EXEMPT = снят `required_relation`+`scope_extractor` у 4 read-RPC, authN-only); authN обязателен; admin→`system_admin`; iam-down fail-closed (GEO-1-20..23).
- **F7** discovery-item == полная public-проекция; `countryCode°`+`openZoneCountHint°` (advisory) rollup; `openForPlacement` фильтр учитывает регион; pagination-validate до authz (GEO-1-24..27).
- **F8** slug-id carve-out; coupling строгий `startsWith(regionId+"-")` + контрпример `ru-central10-a`; malformed first-statement (текст → `"invalid <res> id"`); immutable regionId (**AS-IS: сейчас mutable — удалить путь**) (GEO-1-28..32).
- **F9** ось не эмитится — `placementType°` НЕ эмитится вовсе; assert отсутствия `placementType`/`placementScope` на всех проекциях (GEO-1-33).
- **F10** `[PHASE-0-GATED]` by-lane тон: within-service create absent-parent → `NOT_FOUND "Region <id> not found"`+reason-token (gated); duplicate name → `ALREADY_EXISTS` (AS-IS: `UNIQUE(name)` net-new); INTERNAL opaque (GEO-1-34..37).
- **F11** input-validation negatives: `name` обязателен → `INVALID_ARGUMENT`; `countryCode°` формат ISO-3166 alpha-2 на Create/Update (GEO-1-38..39).

Покрытие обязательного минимума (task): two-projection field-absence ✓ (GEO-1-02/03/33) · fresh-DOWN ✓ (GEO-1-12/13) · capacity-anonymization `NotContains` host-class ✓ (GEO-1-05, ungated) · ambient-read ✓ (GEO-1-20) · slug malformed ✓ (GEO-1-31) · coupling-нарушение ✓ (GEO-1-29/30). Каждая фича — positive + ≥1 negative + edge.

Что изменилось в ре-ревью раунд 1: warnings° → geo-owned metadata (не shared Operation, не public); F11 one-shot/validateOnly вынесены в GEO-2; `openZoneCount°`→`openZoneCountHint°`; by-lane reason-token помечены `[PHASE-0-GATED]` (GEO-1-05 reason, 34, 35); ambient-read = authN-only (снят relation+extractor); добавлены AS-IS behavior-changes (regionId-mutable, UNIQUE(name) net-new, malformed-текст, breaking status-drop через отдельные messages); добавлены negatives (пустой name, countryCode); добавлен §Definition of Done с merge-gate.

## Дефолты, зафиксированные на review (ре-ревью раунд 1)

Все 5 прежних open questions разрешены ревьюером и вшиты в сценарии/DoD выше:

1. **`warnings°`-канал → geo-owned metadata** (НЕ shared Operation, НЕ public response). `repeated string
   warnings` в `CreateRegionMetadata`/`CreateZoneMetadata`. Отражено: F4-intro, GEO-1-12/13/14, DoD. Не кладём
   warnings в public `Region`/`Zone` (утекло бы в `Get`).
2. **F11 one-shot `zoneSpecs` + `validateOnly` → вынесены в GEO-2** (net-new: atomic multi-row TX + sync
   dry-run path; вне 10 обязательных фич). Отражено: §Out-of-scope (GEO-2, сценарии-кандидаты `GEO-2-01/02`).
   Single-resource Create покрывает fresh-DOWN + `warnings°`.
3. **`placementType°` — НЕ эмитить вовсе** (constant-by-type, module-geo rule 1). GEO-1-33 локает field-absence
   на всех проекциях.
4. **by-lane reason-token → `[PHASE-0-GATED]`** (единственная кросс-фазовая зависимость). Помечены GEO-1-34,
   GEO-1-35 и `reason`-часть GEO-1-05; жёсткий merge-gate в §Definition of Done. `NotContains host-class`
   (GEO-1-05) — two-projection security-инвариант, **НЕ** gated. Уже-landed конвенции (direct-read absent→
   `NOT_FOUND` БЕЗ reason, malformed→`INVALID_ARGUMENT`, dup→`ALREADY_EXISTS`, INTERNAL-opaque, immutable-текст)
   — без гейта.
5. **ambient-read → project-scope EXEMPT** (отклонён auto-satisfied-viewer): снят `required_relation`+
   `scope_extractor` у 4 read-RPC → authN-only. Отражено: F6-intro, GEO-1-20/21; DoD (permission-catalog regen
   byte-identical + documented-exception в `security.md`).

Открытых вопросов к reviewer нет — док готов к повторному review.
