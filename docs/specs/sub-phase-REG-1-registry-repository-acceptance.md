# Sub-phase REG-1 (Registry + Repository — regional placement, defaultRepositoryVisibility, explicit lifecycle) — Acceptance

> **Статус:** ✅ **APPROVED** (acceptance-reviewer, 2026-07-20) — 100% покрытие post-revert scope, 32 сценария REG-1-01..32, O1-O4 ратифицированы (дефолты приняты). gate ban #1 ОТКРЫТ → planning/implementation. AS-IS сверен с `60e2827` (proto/domain — grounded). Non-blocking advisories (учесть при реализации, не блокируют approve): (1) остаточное слово «namespace» в прозе REG-1-12/13 («namespace НЕ создаётся») и в описании F5 («namespace-level рычаг») — заменить на «registry/реестр» (контракт-поверхности — message/RPC/REST/id-prefix/тон-ошибок — чисты); (2) REG-1-06 name-format и REG-1-22 lifecycle-invalid сформулированы как «sync-reject ЛИБО result.error / DURABLE ЛИБО INVALID_ARGUMENT» — implementer фиксирует единообразно по указанным дефолтам (own-field name-format предпочтительно sync-first как malformed-id; UNSPECIFIED→DURABLE как omit-equivalent); (3) BVA name-charset/max-length — опц. добавить явный edge-кейс (сейчас покрыт ссылкой на Create-правила в REG-1-06); (4) graceful dangling-ref regionId после удаления региона в geo — satisfied by-construction (registry не зеркалит region-name/status, regionId — opaque stored TEXT; Get не ре-валидирует), явного сценария не требует.
> **Дата:** 2026-07-20
> **Ревьюер:** `acceptance-reviewer` (единственный approve-gate, ban #1)
> **Эпик/тикет:** KAC-REG-1 (Phase-2 owner, redesign-2026; блокирует compute boot-image pull)
> **Монорепо:** `project/kacho` (`github.com/PRO-Robotech/kacho`) — легаси `project/kacho-*` не затрагивается.
> **Repos (порядок build-графа):** `kacho-proto` → `kacho-corelib` (при необходимости) →
> `kacho-geo` (leaf-owner региона; уже есть) → `kacho-registry` (регион/visibility/lifecycle) →
> `kacho-api-gateway` (permission-catalog regen) → `kacho-deploy` → `kacho-workspace` (docs/vault).
> **Формат:** Given-When-Then (только markdown — без кода).
> **Нормативка (не дублируется в тело — ссылки):**
> - `.claude/rules/00-kacho-core.md` — non-negotiables, **core rule #15** (внешняя/URL-адресация только по immutable id).
> - `.claude/rules/api-conventions.md` — flat-resource + async `Operation`, error-format/тон, **by-lane code-split + reason-token** (нормативно), update_mask discipline, camelCase, timestamp-truncate, pagination.
> - `.claude/rules/data-integrity.md` — within-service инварианты на DB-уровне (UNIQUE/CHECK/CAS, ban #10); cross-domain peer-validate fail-closed `UNAVAILABLE`; **placement-coherence** (REGIONAL-anycast исключение).
> - `.claude/rules/security.md` — Internal-vs-external, инфра-чувствительные данные (two-projection), hardening-инварианты (#1 INTERNAL-no-leak, #3 object-scoped authz, #6 hide-existence byte-identical, #7 format-validate до authz).
> - `.claude/rules/testing.md` — TDD RED-до-кода, integration + newman в том же PR, behaviour-level regression, EC read-your-writes retry.

---

## Обзор

REG-1 — производственно-полный additive-инкремент над **уже id-based** ресурсом `Registry`
(`kacho.cloud.registry.v1`). `kacho-registry` — Phase-2 owner OCI-реестров; compute-эталон зависит от
него для boot-image pull. Под-фаза добавляет к существующей модели три ортогональных фичи и **явно
фиксирует identity-контракт** реестра как acceptance-инвариант:

1. **F4 — региональное размещение:** `regionId` (обязателен на Create, peer-validate `geo.v1.RegionService.Get`,
   fail-closed) + `placementType` всегда `REGIONAL` (registry — regional-anycast). Оба immutable.
2. **F5 — `defaultRepositoryVisibility`** (переименование поля `default_visibility`): единственный
   namespace-level рычаг видимости, сид `Repository.visibility` на create, any-path-to-PUBLIC admin-gated.
3. **F7 — `Repository.lifecycle ∈ {DURABLE, EPHEMERAL}`** — авторитетный output-only enum, заменивший
   протекающий implicit «есть overlay-строка» сигнал; `CreateRepositoryRequest.lifecycle` opt-in;
   reject в update_mask; наблюдаемый auto-promote `EPHEMERAL→DURABLE`; concurrent lifecycle-CAS.

### Identity-контракт `Registry` (фиксируется REG-1 как инвариант; ban #15)

- **`id` (prefix `reg`) — immutable PK и ЕДИНСТВЕННАЯ идентичность/адресация.** Операции смены `id`
  **не существует** (нет `:rename`, нет «rename id»). Внешняя и URL-адресация — **только по `id`**
  (core rule #15): pull-путь `$domain/$registryId/$repository:$tag` — средний сегмент = `id` реестра,
  глобально-уникальный на всё облако; `endpoint°` derived как `<serving-host>/<registryId>`.
- **`name` — косметический project-scoped label** (`UNIQUE(project,name)`), **НЕ** идентичность,
  **НЕ** в URL. Меняется обычным `Update` по стандартной update_mask-дисциплине. Смена `name`
  **не затрагивает** `id`/`endpoint°`/pull-путь — образы остаются доступны по неизменному id.
- **`globalSlug` — отсутствует** (нет поля). Деривация человекочитаемого слага в URL запрещена
  (ban #15) — URL несёт immutable id, а не имя/слаг. Зависимости от accountSlug нет.
- **FGA object-типы `registry_registry` / `registry_repository`** — консистентны с tenant-именами
  (никакой Rosetta-маскировки); scope-handle строится по `id`: `registry_registry:<registryId>`,
  `registry_repository:<registryId>/<name>`.

Это **owner-side** под-фаза: сценарии описывают наблюдаемое поведение публичного `RegistryService`
(:9090) через api-gateway. Data-plane docker OCI-flow (push/pull/login, anonymous public pull), overlay
config-lifecycle (Create/Update/Delete/Rename Repository, visibility flip, `ListReferrers`) — **уже
APPROVED и реализуются в RG-1** (`docs/specs/sub-phase-RG-1-registry-repository-overlay-acceptance.md`);
REG-1 их **не переопределяет**, а лишь добавляет F4/F5-rename/F7 и локает identity. Пересечения помечены
блоком `> EXISTING (RG-1):`.

> **AS-IS база (сверено с `git show 60e2827:proto/kacho/cloud/registry/v1/registry.proto` +
> `services/registry/internal/domain/registry.go`):** message `Registry{id;project_id;name;description;
> labels;endpoint°;repository_count°;status;default_visibility}`; RPC `Get/List/Create/Update/Delete`
> (`GetRegistryRequest`…); REST `/registry/v1/registries/{registry_id}`; id-prefix `reg` (immutable PK);
> `name` **MUTABLE** через `UpdateRegistryRequest.name` (partial `UNIQUE(project_id,name) WHERE
> status<>'DELETING'`); `endpoint°` = `<host>/<id>`. **НЕТ** полей `region_id`/`placement_type`/`global_slug`.
> `Repository` натуральный ключ `(registry_id, name)`, overlay⟂projection, **без** поля `lifecycle`.
> REG-1 добавляет `region_id`/`placement_type` (F4), переименовывает `default_visibility →
> defaultRepositoryVisibility` (F5), добавляет `Repository.lifecycle` output-only enum + опц. вход (F7).
> Каждая фича несёт блок `> AS-IS:` с текущим состоянием и что implementer обязан изменить/добавить.

---

## Scope

| # | Фича | Тип | Traceability |
|---|---|---|---|
| F1 | **Registry identity-lock**: `id` immutable PK + ЕДИНСТВЕННАЯ URL/pull-адресация; НЕТ `:rename`/`globalSlug`/top-level `visibility`/`displayName`; FGA-тип `registry_registry` по id; two-projection field-absence | lock (AS-IS-confirm) | core rule #15; `api-conventions.md` id-prefix; `security.md` two-projection |
| F2 | **`name` — mutable косметический label**: `UNIQUE(project,name)`; смена через `Update`; **rename `name` НЕ ломает pull-URL** (URL по id); cross-project same-name OK; `DeleteRegistry` forward-only | lock + AS-IS | `api-conventions.md` update_mask; `data-integrity.md` partial-UNIQUE |
| F4 | **`regionId` required + peer-validate geo** (ребро `registry→geo`, fail-closed `UNAVAILABLE`); **`placementType` always-REGIONAL**; оба immutable; registry — regional-anycast (`zoneId` отсутствует) | **net-new** | `data-integrity.md` placement-coherence; `api-conventions.md` by-lane; `polyrepo.md` runtime-edge |
| F5 | **`defaultRepositoryVisibility`** (rename `default_visibility`); сид новых Repository; any-path-to-PUBLIC admin-gate | **net-new (rename)** | `data-integrity.md` authz; RG-1 D-6 |
| F6 | **Repository natural-key `(registryId, name)`** (сохранён, НЕ namespaceId); overlay⟂projection; PK/FK; ACTIVE-guard `DELETING→FAILED_PRECONDITION` | lock (EXISTING RG-1) | RG-1 D-1/D-3; `data-integrity.md` |
| F7 | **`Repository.lifecycle ∈ {DURABLE,EPHEMERAL}`** output-only enum (заменил implicit durable-bool); явный Create=DURABLE + опц. вход; reject в mask; auto-promote наблюдаем; lifecycle-CAS | **net-new** | RG-1 D-2; `data-integrity.md` CAS |
| F8 | **Update-дисциплина + hardening**: malformed-id первым стейтментом (reason-token); by-lane NOT_FOUND vs FAILED_PRECONDITION; empty-mask full-PATCH; INTERNAL-opaque; pagination-validate до authz; existence-hiding | lock | `api-conventions.md` by-lane; `security.md` #1/#6/#7 |

## Out-of-scope (явно НЕ в REG-1)

- **RG-1 overlay data-plane / config-lifecycle** (`CreateRepository`/`UpdateRepository`/`DeleteRepository`/
  `RenameRepository`/`GetRepository`/`ListReferrers`, `visibility` flip, anonymous public pull `docker pull`,
  register-on-first-push / unregister-on-last-tag, existence-hiding 404) — **уже APPROVED** в
  `sub-phase-RG-1-registry-repository-overlay-acceptance.md`. REG-1 переиспользует их как EXISTING и меняет
  **только** сид-источник (`default_visibility → defaultRepositoryVisibility`, F5) и добавляет `lifecycle`
  (F7). Полные overlay-сценарии (A01..A24, B01..B0N) не дублируются.
- **REG-2** (read-only projections движка редизайн): `Tag`/`Image` реформа, `Referrer → OciReferrer`
  **rename** (`api-conventions.md` §Reference-типы — OCI-граф), drop `Tag.immutable`/`Tag.signed`, единый
  `Image.sizeBytes`, `manifests[]`, `GetImage`/`DeleteImage`, compute `bootSource` `ResourceRef{type,id,name°}`.
  AS-IS `Referrer`-message + `ListReferrers`-RPC уже существуют и REG-1 их **не трогает**.
- **id-prefix hyphen-миграция `reg → reg-`** (`api-conventions.md` B3 going-forward). REG-1 сохраняет
  **legacy слитную форму `reg`** (`NewID` эмитит её; router принимает обе формы аддитивно). Миграция
  генерации prefix `reg→reg-` — **отдельный** редизайн-инкремент (кандидат REG-2+), **не** гейтит REG-1.
- **InternalRegistryService two-projection full redesign** (`RegistryStats`/`GetRegistryStats`/
  `TriggerGarbageCollection`, инфра-поля `engineNamespace`/`bucket`/`host`/`numericInfraId`) — REG-4.
  REG-1 не расширяет Internal* (F4-инфра региона не вводит новых Internal-полей; `regionId` — tenant-facing).
- **Optional-server-default `regionId`** (омит → account/project-default + resolved-echo). Источника
  дефолт-региона нет ни в AS-IS, ни в target (iam не несёт default-region на Account/Project). REG-1 делает
  `regionId` **обязательным** на Create; optional-омит — follow-up после определения источника (O1).
- **Downstream FGA owner-tuple** (`registry_outbox` register-drainer/reconciler) материализуется
  eventually; REG-1 **не гейтит** `Operation.done` на его видимость (ban #9). Behaviour outbox не меняется.

## Traceability-легенда

`°` = output-only (server-derived, на вход Create/Update не принимается). `⊘` = обязательный
immutable-after-Create вход. REST public `/registry/v1/…` (:9090, external-safe). JSON — camelCase
(`registryId`, `projectId`, `regionId`, `placementType`, `defaultRepositoryVisibility`, `createdAt°`).
`createdAt°` усечён до секунд на wire. Мутации → `Operation` (клиент поллит `OperationService.Get(id)`;
Watch нет). Async-Then формулируется как «`Operation.done && !error`, затем `Get`-проверка». Каждый
negative указывает точный gRPC-код + `reason`-token (`api-conventions.md` by-lane таблица) там, где линия
резолва это определяет.

**FGA object-типы (консистентны с tenant-именами — Rosetta не нужна):**

| Tenant-ресурс | FGA object type | scope-handle |
|---|---|---|
| `Registry` | `registry_registry:<registryId>` | по immutable `id` (не по `name`) |
| `Repository` | `registry_repository:<registryId>/<name>` | по `id`+`name` |

---

## F1 — Registry identity-lock: `id` immutable, URL/pull только по `id`, field-absence

> `→ core rule #15` (внешняя/URL-адресация только по immutable id) · `→ api-conventions.md` id-prefix, error-format · `→ security.md` two-projection
> **AS-IS:** модель уже id-based — `Registry.id` (prefix `reg`, immutable PK); `endpoint°` = `<host>/<id>`;
> НЕТ `globalSlug`/`displayName`/top-level `visibility`; RPC `Get/List/Create/Update/Delete` (без `:rename`).
> REG-1 **ничего не переименовывает** — фиксирует identity-контракт как acceptance-инвариант и добавляет
> F4/F5/F7-поля в ответ. Implementer **не** вводит `globalSlug`, `:rename`-verb, top-level `visibility`.

### Сценарий REG-1-01: happy-path CreateRegistry → Operation → GetRegistry

**ID:** REG-1-01

**Given** project `prj-7h3n9k2m5p8q1` существует в iam (peer-validate `ProjectService.Get` проходит)
**And** вызывающий имеет `editor` на parent-project (`registry.registries.create`)
**And** регион `eu-north-1` существует в geo (peer-validate `RegionService.Get` проходит)

**When** клиент вызывает `Create` (`POST /registry/v1/registries`) с payload:
  - `projectId` = `"prj-7h3n9k2m5p8q1"`
  - `name` = `"payments"`
  - `regionId` = `"eu-north-1"`
  - `description` = `"payment service images"`

**Then** ответ — `Operation` (async); `metadata` анмаршалится в `CreateRegistryMetadata`; `metadata.registryId` заполнен **СРАЗУ** (до `done`) и имеет форму `reg<crockford-base32>`
**And** полл `OperationService.Get(op.id)` с inter-poll задержкой до `done==true`; `result` — `response` (не `error`)
**And** последующий `Get` (`GET /registry/v1/registries/reg…`) возвращает `Registry` с `id=="reg…"`, `projectId=="prj-7h3n9k2m5p8q1"`, `name=="payments"`, `regionId=="eu-north-1"`, `placementType=="REGIONAL"`, `defaultRepositoryVisibility=="PRIVATE"` (fail-safe дефолт), `status=="ACTIVE"`, `createdAt°` (усечён до секунд), `endpoint°=="<serving-host>/reg…"` (derived по **id**)

### Сценарий REG-1-02: GetRegistry field-absence — нет `globalSlug`, `displayName`, top-level `visibility`, infra-полей

**ID:** REG-1-02

**Given** registry `reg-c9k2` создан как в REG-1-01

**When** клиент вызывает `Get` (`GET /registry/v1/registries/reg-c9k2`)

**Then** сериализованное тело **НЕ содержит** поля `globalSlug` (F3 глобального слага откачен — ban #15; человекочитаемый слаг в URL запрещён), `displayName` (UI pretty-name живёт в `labels`), `visibility` (top-level — авторитетный гейт видимости на `Repository.visibility`; registry несёт только `defaultRepositoryVisibility`, F5)
**And** тело **НЕ содержит** инфра-полей (`engineNamespace`, `bucketPrefix`, `storageDriver`, `numericInfraId`) — two-projection (те живут только в Internal* :9091, `security.md`; REG-4)

### Сценарий REG-1-03: URL/pull-путь привязан к immutable `id`, не к `name`

**ID:** REG-1-03

**Given** registry `reg-c9k2` (`name="payments"`) c ≥1 repository `backend/api`

**When** клиент читает `Get(reg-c9k2)` и формирует pull-ссылку образа

**Then** `endpoint°` derived как `<serving-host>/reg-c9k2` — средний сегмент = **`id`** (`reg-c9k2`), НЕ `name`
**And** полная pull-форма образа — `$domain/$registryId/$repository:$tag` (напр. `<host>/reg-c9k2/backend/api:v1`) — `$registryId` глобально-уникален на всё облако (id уникален by construction); клиент адресует контент **только** по id (core rule #15)
**And** `registry_registry`-scope-handle для `AccessBinding.scope` — `"registry_registry:reg-c9k2"` (по id, ready-to-paste; потребитель не собирает scope из имени/слага)

### Сценарий REG-1-04: `id` immutable — операции смены нет; `id` в update_mask → INVALID_ARGUMENT

**ID:** REG-1-04

**Given** registry `reg-c9k2` создан

**When** клиент пытается сменить `id`:
  - (a) вызывает несуществующий `POST /registry/v1/registries/reg-c9k2:rename` — маршрута **нет** (verb `:rename` на Registry не зарегистрирован)
  - (b) вызывает `Update` (`PATCH …/reg-c9k2`) с `updateMask=["id"]`, телом `{id:"reg-hacked00000000"}`

**Then** (a) → маршрут не резолвится (`404`/`Not Implemented` на gateway-уровне; endpoint `:rename` для Registry **отсутствует** by construction — id-смены нет, core rule #15)
**And** (b) → **синхронный** `INVALID_ARGUMENT "id is immutable after Registry.Create"` (immutable-switch до `corevalidate.UpdateMask`; `id` в known-set update_mask отсутствует), reason-token `INVALID_RESOURCE_ID`-класса immutable; registry не изменён

### Сценарий REG-1-05: FGA object-type `registry_registry:<id>` по id (консистентно, без Rosetta)

**ID:** REG-1-05

**Given** registry `reg-c9k2` (`name="payments"`)

**When** любой authz-путь (`Get`/`Update`/`Delete`/repository-scoped) резолвит scope

**Then** scope-объект — `registry_registry:reg-c9k2`, построен по **id** (`reg-c9k2`), НЕ по `name`
**And** FGA-тип `registry_registry` **совпадает** с tenant-именем ресурса (`Registry`) — Rosetta-маскировка НЕ нужна (rename `Registry→Namespace` откачен); godoc/JSON-comment не несут alias-таблицы

---

## F2 — `name` — mutable косметический label; rename `name` НЕ ломает pull-URL

> `→ api-conventions.md` update_mask discipline · `→ data-integrity.md` partial-UNIQUE
> **AS-IS:** `name` **уже MUTABLE** через `UpdateRegistryRequest.name` (field 5) — use-case применяет смену
> (DNS-safe re-validate, partial `UNIQUE(project_id,name) WHERE status<>'DELETING'`, конфликт → `ALREADY_EXISTS`).
> REG-1 **сохраняет** mutable-семантику (обоснование ниже) — `RenameNamespace :rename` **не** вводится.
>
> **Дизайн-решение REG-1 (обосновать на review): `name` остаётся MUTABLE через стандартный `Update`.**
> Owner-решение п.5 допускает mutable ЛИБО immutable — выбран **mutable**, консистентно с base + api-conventions:
> (1) идентичность несёт **`id`** (immutable, F1), а `name` объявлен **косметическим project-scoped label** —
> label-подобные поля по конвенции mutable (как `labels`/`description`); делать его immutable — беспричинное
> ограничение без identity-обоснования; (2) base уже mutable — сохранение = zero-behaviour-change для этого поля;
> (3) mutable `name` **позволяет прямо продемонстрировать** ключевой инвариант «rename `name` НЕ ломает pull-URL»
> (REG-1-07) — URL по id, поэтому переименование безопасно. Отдельный `:rename`-verb не нужен: смена косметического
> имени — обычный `Update` под update_mask-дисциплиной (re-validate + `UNIQUE(project,name)` конфликт).

### Сценарий REG-1-06: UpdateRegistry name → OK (mutable, стандартный update_mask)

**ID:** REG-1-06

**Given** registry `reg-c9k2` (`name="payments"`); имя `"billing"` свободно в project (`UNIQUE(project,name)` не нарушено)

**When** клиент вызывает `Update` (`PATCH /registry/v1/registries/reg-c9k2`) с `updateMask=["name"]`, `name="billing"`

**Then** ответ — `Operation`; полл до `done && !error`
**And** `Get(reg-c9k2).name == "billing"` (name mutable, re-validated DNS-safe); `id` не изменился (`reg-c9k2` — стабильный якорь)
**And** `name`-mutation валидируется теми же правилами, что Create (DNS-safe, длина); невалидное имя (`"Bad Name!"`) в mask → `Operation{done:true}` `result.error` `INVALID_ARGUMENT` (либо sync-reject первым стейтментом, если проверяется до LRO)

### Сценарий REG-1-07 (ключевой): rename `name` НЕ меняет `id`/`endpoint°`/pull-URL

**ID:** REG-1-07

**Given** registry `reg-c9k2` (`name="payments"`, `endpoint°="<host>/reg-c9k2"`) c repository `backend/api` (тег `v1`)

**When** клиент вызывает `Update(reg-c9k2, updateMask=["name"], name="billing")` → `done && !error`

**Then** `Get(reg-c9k2)`: `name=="billing"`, но `id=="reg-c9k2"` **не изменился**, `endpoint°=="<host>/reg-c9k2"` **не изменился** (derived по id, не по name)
**And** pull-ссылка `<host>/reg-c9k2/backend/api:v1` **по-прежнему резолвится** (образы адресуются по immutable id — переименование косметического `name` их не ломает, core rule #15); FGA-scope `registry_registry:reg-c9k2` не изменился
**And** контраст с откачённой Namespace-моделью: НЕТ re-derive `globalSlug` (поля нет), НЕТ переписывания pull-ссылок — rename `name` дёшев и безопасен by construction

### Сценарий REG-1-08: `UNIQUE(project,name)` — коллизия в project vs cross-project OK vs concurrent

**ID:** REG-1-08

**Given** registry `reg-c9k2` (`name="payments"`) в project `prj-7h3n`

**When** `Create` с `projectId="prj-7h3n"`, `name="payments"`, `regionId="eu-north-1"` (тот же project, дубль имени)

**Then** `Operation{done:true}` c `result.error`: `ALREADY_EXISTS` (partial `UNIQUE(project_id,name) WHERE status<>'DELETING'`, SQLSTATE 23505 — DB-backstop, ban #10)

**When** `Create` с `projectId="prj-DIFFERENT"`, `name="payments"`, `regionId="eu-north-1"` (другой project, то же имя)

**Then** `Operation.done && !error` — коллизия ловится **только** в своём проекте (spine-конформно; не гонишься с чужим невидимым тенантом по project-scoped имени)

**When** (concurrency) два конкурентных `Create` в **одном** project `prj-7h3n` с **одним** `name="orders"` стартуют одновременно

**Then** **ровно один** → `done && !error`; **другой** → `result.error` `ALREADY_EXISTS` (partial `UNIQUE` DB-CAS, ровно один writer выигрывает slot; concurrent-goroutines integration-тест обязателен — `data-integrity.md` чек-лист п.5)

### Сценарий REG-1-09: DeleteRegistry → forward-only ACTIVE→DELETING; имя освобождается

**ID:** REG-1-09

> **EXISTING (AS-IS):** `Delete` уже forward-only (`RegistryStatus` DELETING терминальный, partial-UNIQUE
> освобождает имя). REG-1 не меняет поведение — фиксирует как acceptance-сценарий.

**Given** registry `reg-c9k2` `status=ACTIVE`

**When** клиент вызывает `Delete` (`DELETE /registry/v1/registries/reg-c9k2`)

**Then** ответ — `Operation`; `metadata` (`DeleteRegistryMetadata`) несёт `registryId=="reg-c9k2"` **сразу** (до `done`)
**And** переход `status`: `ACTIVE→DELETING` (forward-only, DELETING терминальный — revert запрещён, иначе partial-`UNIQUE(project,name)` конфликтует с re-Create того же имени); имя немедленно освобождается для повторного `Create` того же `(project,name)`
**And** повторный `Delete(reg-c9k2)` на уже-`DELETING` → идемпотентно / `NOT_FOUND` (well-formed уже недоступен); downstream owner-tuple unregister — eventually через `registry_outbox` (не гейтит `done`, ban #9)

---

## F4 — `regionId` (peer-validate geo, required) + `placementType` always-REGIONAL

> `→ data-integrity.md` placement-coherence (REGIONAL-anycast исключение) · `→ api-conventions.md` by-lane · `→ polyrepo.md` runtime-edge
> **AS-IS:** `Registry` **не несёт** ни `region_id`, ни `placement_type` (OCI-контент трактовался
> регион-нейтрально). REG-1 вводит **always-REGIONAL** `placementType`-константу (осознанный LEAN carve-out
> ради spine placement-discriminator parity — «not a choice») и `regionId` (REGIONAL anycast — `zoneId` пуст
> by construction). `regionId` peer-validate `geo.v1.RegionService.Get` (fail-closed) — **новое runtime-ребро
> `registry → geo`** (ацикличность holds: geo — leaf, registry не зовётся обратно). Optional-server-default —
> отложен (нет источника, O1); REG-1 делает `regionId` обязательным на Create.

### Сценарий REG-1-10: placementType always-REGIONAL на всех проекциях; zoneId отсутствует

**ID:** REG-1-10

**Given** registry `reg-c9k2` создан (любым путём)

**When** `Get(reg-c9k2)` и `List`

**Then** `placementType == "REGIONAL"` в каждой проекции (константа — «not a choice»; из зональной coherence-проверки исключён by construction, остаётся региональная — `data-integrity.md` anycast-исключение)
**And** registry **не несёт** `zoneId` (пусто/отсутствует) — regional-anycast ресурс зоне-независим

### Сценарий REG-1-11 (negative): regionId обязателен на Create → омитнут → INVALID_ARGUMENT

**ID:** REG-1-11

**Given** project `prj-7h3n` существует

**When** `Create` с `projectId="prj-7h3n"`, `name="payments"` (**без** `regionId`)

**Then** **синхронный** `INVALID_ARGUMENT "regionId is required"` первым стейтментом (own-field validation; операция не создаётся); reason-token `INVALID_ARGUMENT`-класса
**And** (follow-up, O1) когда источник дефолт-региона будет определён — optional-омит + resolved-echo `Operation.response.regionId`; REG-1 не имитирует несуществующий resolve

### Сценарий REG-1-12 (negative): несуществующий regionId → peer-validate geo → FAILED_PRECONDITION

**ID:** REG-1-12

**Given** регион `eu-west-9` **не существует** в geo

**When** `Create` с `name="payments"`, `regionId="eu-west-9"`

**Then** отказ на request-path через peer-validate `geo.v1.RegionService.Get` (peer-validate lane): `FAILED_PRECONDITION` c reason-token **`PEER_RESOURCE_MISSING`** (`api-conventions.md` by-lane: foreign id не существует у владельца → НЕ NOT_FOUND, consumer не «не нашёл своё», а «предусловие на чужой ресурс не выполнено»); namespace НЕ создаётся с висячим regionId
**And** клиент машинно различает линию по `reason`-token в `rpc.Status.details` (`ErrorInfo.domain="registry.kacho.cloud"`, `metadata={resource_type:"geo.region", resource_id:"eu-west-9"}`) — не парся прозу message

### Сценарий REG-1-13 (edge): geo недоступен на Create → UNAVAILABLE fail-closed

**ID:** REG-1-13

**Given** `geo.v1.RegionService.Get` недоступен (peer down)

**When** `Create` с явным `regionId="eu-north-1"`

**Then** `UNAVAILABLE` c reason-token **`PEER_UNAVAILABLE`** (fail-closed для мутаций — owner недоступен, namespace НЕ создаётся; `data-integrity.md` cross-domain п.2)
**And** per-call deadline на geo-вызове обязателен (`architecture.md` concurrency — не сырой request-ctx на `http.DefaultClient`)

### Сценарий REG-1-14: regionId / placementType immutable после Create

**ID:** REG-1-14

**Given** registry `reg-c9k2` (`regionId="eu-north-1"`, `placementType="REGIONAL"`)

**When** `Update` с `updateMask=["regionId"]`, `regionId="eu-central-1"`

**Then** **синхронный** `INVALID_ARGUMENT "regionId is immutable after Registry.Create"` (immutable-switch до `UpdateMask`; перенос региона сломал бы storage-locality блобов)
**And** то же для `placementType` в mask → `INVALID_ARGUMENT "placementType is immutable after Registry.Create"`

---

## F5 — `defaultRepositoryVisibility` (rename `default_visibility` + admin-gate)

> `→ data-integrity.md` authz · `→ RG-1 D-6`
> **AS-IS:** поле называется `default_visibility` (`Registry.default_visibility`, миграция 0005 TEXT DEFAULT
> 'PRIVATE' CHECK IN(PRIVATE,PUBLIC)), mutable admin-gated, сид `Repository.visibility` на create. REG-1
> переименовывает proto-поле → `defaultRepositoryVisibility` (единственный namespace-level visibility-рычаг;
> сам registry top-level `visibility` НЕ несёт — F1). Семантика admin-gate any-path-to-PUBLIC **не меняется**
> (EXISTING RG-1 D-6/B10/B11/B12) — REG-1 меняет только **имя поля**.

### Сценарий REG-1-15: defaultRepositoryVisibility сидит новый Repository при омитнутом visibility

**ID:** REG-1-15

**Given** registry `reg-c9k2` с `defaultRepositoryVisibility=="PRIVATE"`

**When** `CreateRepository` под `reg-c9k2` **без** явного `visibility`

**Then** созданный Repository несёт `visibility=="PRIVATE"` (унаследован из `defaultRepositoryVisibility`)

**When** admin меняет `Update(reg-c9k2, updateMask=["defaultRepositoryVisibility"], defaultRepositoryVisibility=PUBLIC)`, затем создаёт **новый** repo без visibility

**Then** новый repo несёт `visibility=="PUBLIC"` (inherited-default — gate-at-default: admin уже авторизовал «путь к PUBLIC», RG-1 D-6/B12); **существующие** repo НЕ перекрашиваются (per-repo `Repository.visibility` остаётся authoritative)

### Сценарий REG-1-16 (negative): не-admin ведёт defaultRepositoryVisibility→PUBLIC → PERMISSION_DENIED

**ID:** REG-1-16

**Given** вызывающий имеет `v_update@registry_registry:reg-c9k2`, но **не** registry admin
**And** registry `reg-c9k2` c `defaultRepositoryVisibility=PRIVATE`

**When** `Update(reg-c9k2, updateMask=["defaultRepositoryVisibility"], defaultRepositoryVisibility=PUBLIC)`

**Then** `PERMISSION_DENIED` (any-path-to-PUBLIC требует registry admin, RG-1 D-6/B10; caller уже доказал `v_update` → код честен, НЕ existence-hiding `security.md` #5). Текст называет нужную capability: `"setting default repository visibility to PUBLIC requires registry admin (role registry.admin) on registry_registry:reg-c9k2"`
**And** тот же caller с `updateMask=["description"]` (без visibility-поля) → Operation OK (editor-путь не сломан; admin-gate узок — только на переход →PUBLIC)

---

## F6 — Repository natural-key `(registryId, name)` (сохранён, overlay⟂projection, ACTIVE-guard)

> `→ RG-1 D-1/D-3` · `→ data-integrity.md`
> **EXISTING (AS-IS RG-1):** `Repository.registry_id` + `CreateRepositoryRequest.registry_id`; overlay-таблица
> `repository_configs (registry_id, name)` PK; FK `registry_id → registries(id) ON DELETE CASCADE`; overlay⟂
> projection; ACTIVE-guard (мутации в реестре `DELETING` → `FAILED_PRECONDITION "registry is being deleted"`,
> RG-1 A24). REG-1 **сохраняет** natural-key `(registryId, name)` — rename `registryId→namespaceId` **откачен**
> (Namespace-модель отменена). Поле остаётся `registryId`; DB-инварианты не трогаются. REG-1 добавляет только
> `lifecycle` (F7). Сценарии ниже — lock ключевых инвариантов, полный overlay-lifecycle — RG-1.

### Сценарий REG-1-17: happy CreateRepository → GetRepository (registryId + fgaObject по id+name)

**ID:** REG-1-17

**Given** registry `reg-c9k2` (`status=ACTIVE`); вызывающий с `v_create@registry_registry:reg-c9k2`

**When** `CreateRepository` (`POST /registry/v1/registries/reg-c9k2/repositories`) с `repository="backend/api"`, `description="Core API images"`

**Then** `Operation.done && !error` (`metadata.registryId=="reg-c9k2"`, `metadata.repository=="backend/api"` сразу)
**And** `GetRepository` (`GET /registry/v1/registries/reg-c9k2/repositories/backend/api`) возвращает `Repository` с `registryId=="reg-c9k2"` (НЕ namespaceId — rename откачен), `name=="backend/api"` (несёт `/`), `description=="Core API images"`, `createdAt°`, `fgaObject°=="registry_repository:reg-c9k2/backend/api"` (по registryId+name, консистентный FGA-тип)

### Сценарий REG-1-18 (negative + concurrency): дубль `(registryId,name)` → ALREADY_EXISTS; concurrent → ровно один

**ID:** REG-1-18

**Given** durable Repository `reg-c9k2/backend/api` существует

**When** `CreateRepository(reg-c9k2, repository="backend/api")` повторно

**Then** `Operation{done:true}` c `result.error`: `ALREADY_EXISTS "repository already exists"` (PK `(registry_id,name)` 23505 — DB-backstop, ban #10)

**When** (concurrency) два конкурентных `CreateRepository(reg-c9k2, "web")` (имя `web` свободно) стартуют одновременно

**Then** **ровно один** → `done && !error`; **другой** → `result.error` `ALREADY_EXISTS` (PK-CAS, ровно один writer; concurrent-goroutines integration-тест обязателен — `data-integrity.md` п.5)

### Сценарий REG-1-19: registryId immutable у Repository

**ID:** REG-1-19

**Given** Repository `reg-c9k2/backend/api`

**When** `UpdateRepository` с `updateMask=["registryId"]` (перенос в другой registry)

**Then** **синхронный** `INVALID_ARGUMENT "registryId is immutable after Repository.Create"` (reject до UpdateMask; cross-registry move структурно невыразим — только через engine re-home, вне REG-1)

### Сценарий REG-1-20 (edge, ACTIVE-guard): registry DELETING → overlay-мутация → FAILED_PRECONDITION

**ID:** REG-1-20

> **EXISTING (RG-1 A24):** ACTIVE-guard в мутационной tx (`SELECT registries.status FOR UPDATE`). REG-1 не
> меняет поведение — тон `"registry is being deleted"` сохранён (без rename на «namespace»).

**Given** registry `reg-c9k2` в состоянии `status=DELETING` (запущен `Delete`); caller видит реестр и держит нужный verb

**When** `CreateRepository(reg-c9k2, "backend/api")` (или `UpdateRepository`/`RenameRepository`/`DeleteRepository` под ним)

**Then** `Operation{done:true}` c `result.error`: `FAILED_PRECONDITION "registry is being deleted"` — ACTIVE-guard в мутационной tx (`data-integrity.md`; FK гарантирует существование строки реестра, но не статус → status-guard в use-case)
**And** это **не** existence-oracle: caller уже доказал доступ к видимому реестру → `FAILED_PRECONDITION` честен коду; невидимый/чужой реестр даёт `NOT_FOUND` (existence-hiding, `security.md` #5/#6)

---

## F7 — `Repository.lifecycle ∈ {DURABLE, EPHEMERAL}` output-only enum

> `→ RG-1 D-2` · `→ data-integrity.md` CAS
> **AS-IS:** `Repository` **не несёт** поля `lifecycle`. Класс (ephemeral/durable) выводится **неявно** из
> наличия overlay-строки `repository_configs`: durable = есть overlay (survives-empty), ephemeral = проекция
> без overlay (register-on-first-push, unregister-on-last-tag). REG-1 делает исчезаемость **авторитетным
> output-only enum** `lifecycle` (заменил протекающий implicit-сигнал): один наблюдаемый признак вместо
> «задан ли overlay-field». Явный `CreateRepository` → `DURABLE` by default (explicit intent = сохранить
> каркас); опц. вход `CreateRepositoryRequest.lifecycle: DURABLE|EPHEMERAL` перекрывает; установка overlay
> на EPHEMERAL push-repo AUTO-PROMOTE'ит `EPHEMERAL→DURABLE` (наблюдаемо через enum; AS-IS overlay-upsert
> на Update/Rename уже существует — REG-1 делает его наблюдаемым).

### Сценарий REG-1-21: явный CreateRepository → lifecycle°=DURABLE (survives-empty)

**ID:** REG-1-21

**Given** registry `reg-c9k2` ACTIVE

**When** `CreateRepository(reg-c9k2, "backend/api")` **без** поля `lifecycle`

**Then** `Operation.done && !error`; `GetRepository.lifecycle == "DURABLE"` (явный intent-create → DURABLE by default)
**And** repo виден с `tagCount == 0` (survives-empty; durable-empty не исчезает — unregister-on-last-tag НЕ срабатывает)

### Сценарий REG-1-22: явный вход lifecycle=EPHEMERAL → lifecycle°=EPHEMERAL

**ID:** REG-1-22

**When** `CreateRepository(reg-c9k2, "scratch/tmp", lifecycle="EPHEMERAL")` (явный опц. вход перекрывает дефолт)

**Then** `Operation.done && !error`; `GetRepository.lifecycle == "EPHEMERAL"` (register-on-first-push семантика — предсказуемый эксплицитный рычаг вместо вывода из наличия overlay-field)
**And** invalid-вход (`lifecycle="REPOSITORY_LIFECYCLE_UNSPECIFIED"` явно, либо out-of-range) на Create → трактуется как омит (DURABLE by default) ИЛИ `INVALID_ARGUMENT` — implementer фиксирует единообразно (дефолт: UNSPECIFIED → DURABLE)

### Сценарий REG-1-23: overlay-set на EPHEMERAL push-repo → auto-promote → lifecycle°=DURABLE

**ID:** REG-1-23

**Given** ephemeral repo `reg-c9k2/pushed/img` (register-on-first-push, `lifecycle=EPHEMERAL`, overlay-строки нет)

**When** `UpdateRepository(reg-c9k2, "pushed/img", updateMask=["description"], description="now configured")` (устанавливает overlay-поле)

**Then** `Operation.done && !error`; `GetRepository.lifecycle == "DURABLE"` — установка overlay AUTO-PROMOTE'ит `EPHEMERAL→DURABLE` (наблюдаемо через enum); теперь survives-empty
**And** `RenameRepository` ephemeral-repo → тот же auto-promote (`EPHEMERAL→DURABLE`, INSERT overlay целевого имени — RG-1 A23 parity)

### Сценарий REG-1-24: lifecycle output-only — в UpdateMask → INVALID_ARGUMENT

**ID:** REG-1-24

**When** `UpdateRepository` с `updateMask=["lifecycle"]`, `lifecycle="EPHEMERAL"`

**Then** **синхронный** `INVALID_ARGUMENT` (output-only поле в mask — `lifecycle` авторитетно управляется системой, не tenant'ом; тот же класс, что `tagCount`/`createdAt`; reject до применения). Понижение `DURABLE→EPHEMERAL` через API **не выразимо** — durable снимается только `DeleteRepository`

### Сценарий REG-1-25 (concurrency, lifecycle-CAS): конкурентный promote одного ephemeral-repo → идемпотентно DURABLE

**ID:** REG-1-25

**Given** ephemeral repo `reg-c9k2/pushed/img` без overlay
**And** два конкурентных `UpdateRepository(reg-c9k2, "pushed/img", …)`, оба промоутящих overlay

**When** обе Operation исполняются

**Then** обе сходятся к `lifecycle=DURABLE` **без** double-insert-ошибки: overlay-upsert — одностейтментная запись под PK-backstop (`INSERT … ON CONFLICT` идемпотентный merge, не 23505-fail); финальный `GetRepository.lifecycle == "DURABLE"` (integration concurrent-race, `data-integrity.md` п.5)

---

## F8 — Update-дисциплина + hardening (malformed-id, by-lane, empty-mask, INTERNAL, pagination, existence-hiding)

> `→ api-conventions.md` by-lane + malformed-first + update_mask · `→ security.md` #1/#6/#7
> **AS-IS:** malformed registry-id уже валидируется как `corevalidate.ResourceID("registry", ids.PrefixRegistry, id)`
> (текст `"invalid registry id '<X>'"`). REG-1 **сохраняет** этот контракт (rename на namespace откачен) и
> добавляет reason-token (`api-conventions.md` by-lane таблица — теперь нормативна, не PROPOSED).

### Сценарий REG-1-26: malformed registry id → INVALID_ARGUMENT первым стейтментом; absent → NOT_FOUND (by-lane)

**ID:** REG-1-26

**When** `Get` (`GET /registry/v1/registries/REG!!!`) — id не проходит format-check

**Then** **синхронный** `INVALID_ARGUMENT "invalid registry id 'REG!!!'"` — malformed ловится **первым стейтментом** RPC (до repo-резолва); reason-token **`INVALID_RESOURCE_ID`** (sync-format lane)
**And** well-formed-но-несуществующий (`GET /registry/v1/registries/regdoesnotexist0`) → `NOT_FOUND "Registry regdoesnotexist0 not found"` (direct-read lane — own-owned id, строки в своей БД нет), reason-token **`RESOURCE_NOT_FOUND`**
**And** format-check применяется к own-owned id по prefix `reg` (router принимает legacy слитную форму; hyphen-миграция `reg→reg-` — Out-of-scope)

### Сценарий REG-1-27 (negative): malformed repository name → INVALID_ARGUMENT

**ID:** REG-1-27

**When** `GetRepository(reg-c9k2, repository="Bad Name!")` — repo-имя нарушает OCI-charset (`[a-z0-9]+(?:[._-/][a-z0-9]+)*`)

**Then** **синхронный** `INVALID_ARGUMENT "invalid repository name 'Bad Name!'"` первым стейтментом (natural-key format-check до repo-резолва); well-formed-но-нет → `NOT_FOUND "repository not found"` (existence-hiding, RG-1 A08)

### Сценарий REG-1-28: пустой update_mask → full PATCH mutable, immutable silently игнорируются

**ID:** REG-1-28

**Given** registry `reg-c9k2` (`name="payments"`, `description="old"`, `regionId="eu-north-1"`)

**When** `Update(reg-c9k2)` с **пустым** `updateMask`, телом `{description:"new", labels:{team:"pay"}, name:"billing", regionId:"eu-west-9", id:"reg-hacked"}`

**Then** `Operation.done && !error`; применены **mutable** поля (`description=="new"`, `labels` обновлены, `name=="billing"` — mutable косметический label, F2); **immutable** из тела (`id`, `regionId`, `placementType`) **silently игнорированы** (full-object PATCH-семантика, `api-conventions.md` update_mask discipline); `Get.id=="reg-c9k2"`, `regionId` не изменён

### Сценарий REG-1-29: CreateRepository под несуществующим/невидимым registry → NOT_FOUND (existence-hiding)

**ID:** REG-1-29

> **EXISTING (RG-1 X04):** namespace call-gate — невидимый/absent реестр → uniform `NOT_FOUND "repository
> not found"` (existence-hiding, репозиторий-scoped RPC gateway `<exempt>`, per-repo Check в handler'е).

**Given** registry `reg-absent00000000` **не существует** ИЛИ существует, но caller его **не видит**

**When** `CreateRepository(reg-absent00000000, repository="x/y")`

**Then** `NOT_FOUND "repository not found"` — existence-hiding (byte-identical для absent и unauthorized-namespace; `security.md` #6 — не existence-oracle); Operation НЕ создаётся
**And** для **видимого** own-owned registry, которого нет в своей БД по well-formed id на direct-read Registry-RPC (`Get`/`Update`/`Delete`) — `NOT_FOUND "Registry <id> not found"` reason `RESOURCE_NOT_FOUND` (REG-1-26); различие линий (repository call-gate existence-hiding vs Registry direct-read) — намеренное

### Сценарий REG-1-30 (edge): INTERNAL никогда не эхает pgx/SQL-текст

**ID:** REG-1-30

**Given** некатегоризированная DB-ошибка на write-пути (симулируется в integration-слое)

**When** мутация (`Create`/`CreateRepository`) упирается в неё

**Then** `result.error` — фиксированный opaque-текст (`"internal database error"`), **NotContains** driver/connection-текст (host/port/user/db) и pgx/SQLSTATE-детали; regression-lock проверяет **сообщение** (не только код `INTERNAL`), на обоих листенерах (`security.md` hardening-инвариант 1, `testing.md`)

### Сценарий REG-1-31 (negative): ListRegistries garbage pageToken → INVALID_ARGUMENT ДО authz-short-circuit

**ID:** REG-1-31

**Given** аутентифицированный принципал (возможно с пустым listauthz-грантом)

**When** `List` (`GET /registry/v1/registries?projectId=prj-7h3n&pageToken=%%%not-base64%%%`)

**Then** `INVALID_ARGUMENT` — format-validate `pageToken`/`pageSize`/`projectId` **ДО** listauthz empty-grant short-circuit (иначе garbage-token при пустом гранте утёк бы в `200 {[]}`; `api-conventions.md` List-gotcha, `security.md` #7)
**And** `pageSize > 1000` → `INVALID_ARGUMENT` (отвергается, **не** clamp'ится)

### Сценарий REG-1-32 (authz-matrix): per-RPC Check на каждом Registry-RPC

**ID:** REG-1-32

**Given** registry `reg-c9k2` в project `prj-7h3n`; принципалы с разными грантами

**When** вызовы разными субъектами:
  - (a) `Get(reg-c9k2)` субъектом **без** `v_get` на `registry_registry:reg-c9k2`
  - (b) `Create` субъектом **без** `editor` на parent-project `prj-7h3n`
  - (c) `Update`/`Delete(reg-c9k2)` субъектом **без** `v_update`/`v_delete`
  - (d) `List(projectId=prj-7h3n)` субъектом с частичным грантом

**Then** (a) → hide-existence `NOT_FOUND "Registry reg-c9k2 not found"` (byte-identical реальному miss, `security.md` #6 — unauthorized неотличим от absent)
**And** (b) → мутация fail-closed отвергнута (`PERMISSION_DENIED`, либо hide-existence по project-scope при невидимом project); e2e-негатив толерирует `oneOf([400,403,404])` (authz-first, `testing.md`)
**And** (c) → аналогично hide-existence `NOT_FOUND` (Registry direct-read scope-gate); Operation НЕ создаётся
**And** (d) → `List` scope-filtered через iam `ListObjects` (v_list) — возвращает **только** видимые реестры (listauthz row-filter, `security.md` «публичный List обязан фильтровать»; гейт `audit-list-filter`)

---

## Definition of Done

REG-1 готова к merge только при выполнении всего чек-листа (`ai-tooling.md` §lifecycle gate 4-7; `testing.md`):

**Traceability + тесты (1-to-1):**
- [ ] Каждый `REG-1-NN` имеет зелёный **integration-тест** (testcontainers Postgres 16) —
  `Test<Resource>_REG_1_NN` (напр. `TestRegistry_REG_1_01`, `TestRepository_REG_1_25`) — покрывающий
  SQL-сторону, включая concurrent-race на partial-UNIQUE / PK / lifecycle-CAS (REG-1-08/18/25) и
  ACTIVE-guard (REG-1-20).
- [ ] Каждый `REG-1-NN` (наблюдаемый через api-gateway) имеет зелёный **newman-кейс** `tests/newman/cases/*.py`
  с аннотацией `# verifies REG-1-NN` — ≥1 happy + ≥1 negative per фича. Newman обёрнут bounded-retry
  `retry_until_authorized` ТОЛЬКО на первый пост-create доступ к своему registry/repo (owner-tuple EC,
  `testing.md`); фикстур-хелпер проверяет `!op.error` перед извлечением `registryId` из `metadata`
  (phantom-id guard).
- [ ] TDD-порядок соблюдён: RED (падает по нужной причине) ДО кода, пара RED→GREEN в PR.

**e2e-smoke (real gateway, construction-verified):**
- [ ] `Create` → полл Operation → `Get` возвращает `reg…` + `placementType=REGIONAL` + `regionId` (REG-1-01/10).
- [ ] field-absence на **реальном** gateway-ответе: `Get` НЕ содержит `globalSlug`/`displayName`/top-level
  `visibility`/infra-полей (REG-1-02).
- [ ] rename `name` через `Update` НЕ меняет `id`/`endpoint°`; pull-ссылка по id остаётся валидной (REG-1-06/07).
- [ ] `CreateRepository` → `lifecycle=DURABLE` survives-empty; auto-promote ephemeral→durable наблюдаем (REG-1-21/23).

**Deliverables (implementer обязан выполнить):**
- [ ] **Новые поля:** `Registry.regionId` (peer-validate geo, обязателен на Create, immutable),
  `Registry.placementType` (always-REGIONAL const, immutable); `Repository.lifecycle` output-only enum
  `{REPOSITORY_LIFECYCLE_UNSPECIFIED, DURABLE, EPHEMERAL}` + `CreateRepositoryRequest.lifecycle` опц. вход.
- [ ] **Rename поля:** `Registry.default_visibility → defaultRepositoryVisibility` (proto + миграция колонки
  ИЛИ proto-only rename при сохранении column-имени — на усмотрение db-review; **новая** миграция, не
  редактировать применённые 0001-0005, ban #5).
- [ ] **Явно НЕ вводить:** `globalSlug`-поле, `RenameNamespace`/`:rename`-verb на Registry, top-level
  `visibility`, `displayName`, rename `Registry→Namespace`, rename `registryId→namespaceId`. id-prefix
  остаётся `reg` (legacy форма; hyphen-миграция — Out-of-scope).
- [ ] **Новая миграция** (`0006_*`): `registries` += `region_id NOT NULL` / `placement_type` (CHECK
  `placement_type='REGIONAL' AND region_id<>'' AND zone_id=''` — anycast, `data-integrity.md` placement-anchor);
  `repository_configs` += `lifecycle` (либо derive из overlay-presence — db-review решает: materialized column
  vs computed; concurrent lifecycle-CAS обязан быть DB-safe, REG-1-25). Пустой каталог безопасен для NOT NULL
  region_id (нет DEFAULT-backfill — legacy `reg-`-строки, если есть prod-данные, — отдельный deploy-concern
  data-cutover, вне API-behavior acceptance).
- [ ] **Новое runtime-ребро `registry → geo`** (`RegionService.Get` peer-validate) зафиксировано в
  `polyrepo.md` (runtime-edge) + vault `edges/registry-to-geo-region-validate.md`; ацикличность holds
  (geo — leaf, не зовёт registry); per-call deadline на geo-вызове.
- [ ] proto+regen: `buf lint` / `buf breaking` / `buf generate` зелёные. Rename `default_visibility →
  defaultRepositoryVisibility` — **breaking** (задекларировать в `buf.yaml` breaking-allow или согласовать
  с `proto-api-reviewer`, O2). Добавление `region_id`/`placement_type`/`lifecycle` — additive (не breaking).
- [ ] `permission-catalog` регенерирован (`make -C gateway permission-catalog`, byte-identical iam-seed↔gateway; CI
  drift-gate `make -C gateway permission-catalog-check`) — новых public RPC REG-1 не вводит (F4/F5/F7 — поля на
  существующих RPC), но rename поля не должен ломать catalog.

**Проектные гейты (финальная верификация):**
- [ ] `go test ./... -race` · `golangci-lint run` · `govulncheck` зелёные. `make -C services/registry
      audit-list-filter` **гейтом пока не является**: рецепт печатает «реализуется вместе с
      `RegistryService.List`» и выходит с нулём (`services/registry/Makefile`) — цель есть, проверки нет.
- [ ] newman зелёные (все `REG-1-NN`); RG-1 overlay-suite не регрессировал (REG-1 additive).

---

## Открытые вопросы к reviewer (зафиксировать дефолт на review)

1. **O1 — regionId обязателен (RESOLVED-дефолт).** Источника server-default региона нет ни в AS-IS, ни в
   target (iam не несёт default-region на Account/Project). Дефолт: `regionId` **обязателен на Create** +
   peer-validate geo (F4, REG-1-11/12/13); optional-server-default + resolved-echo — follow-up после
   определения источника. Reviewer подтверждает границу.
2. **O2 — proto breaking-стратегия для rename `default_visibility → defaultRepositoryVisibility`.** Вариант A:
   breaking-allow в `buf.yaml` (same package `kacho.cloud.registry.v1`, старое имя поля удаляется). Вариант B:
   держать proto field-name, менять только JSON `json_name`. **Дефолт: вариант A** (redesign-2026 Phase-2
   допускает breaking; JSON-имя camelCase `defaultRepositoryVisibility` — часть tenant-контракта). Территория
   `proto-api-reviewer`.
3. **O3 — `name` mutable vs immutable (RESOLVED-дефолт: MUTABLE).** Owner-решение п.5 допускает оба; выбран
   **mutable через стандартный `Update`** (консистентно с base + `api-conventions.md`; `name` — косметический
   label, идентичность несёт immutable `id`; enables REG-1-07 «rename не ломает URL»). Reviewer подтверждает,
   что mutable-выбор согласуется с identity-контрактом (id — единственная идентичность).
4. **O4 — `Repository.lifecycle` materialized column vs computed.** F7 делает lifecycle **наблюдаемым**;
   реализация — materialized `lifecycle` column в `repository_configs` ЛИБО computed из overlay-presence на
   read. **Дефолт: materialized** (concurrent lifecycle-CAS REG-1-25 требует DB-safe write; computed-on-read
   не выражает auto-promote атомарно). Территория `db-architect-reviewer`.

Открытых блокеров, требующих заказчика, нет — док готов к review.

## Changelog — что этот док покрывает (и что откачено vs Namespace-модель)

**Откачено (owner revert Namespace→Registry, 2026-07-20) — УДАЛЕНО из контракта:**
- rename `Registry → Namespace` (message/RPC/REST/id-prefix `ns-`) — **откачен**; ресурс остаётся `Registry`,
  RPC `Get/List/Create/Update/Delete`, REST `/registry/v1/registries`, id-prefix `reg`.
- `globalSlug°` (two-identity derived-slug, `<accountSlug>-<name>`, `UNIQUE(global_slug)`, bare-global opt-in,
  reason `NAMESPACE_NAME_IS_GLOBAL`) — **ПОЛНОСТЬЮ УДАЛЁН** (нет поля; деривация слага в URL запрещена ban #15;
  зависимость от accountSlug снята).
- `RenameNamespace` / `:rename`-verb на реестре + `name` immutable — **откачены**; `name` остаётся **mutable**
  косметическим label через стандартный `Update`.
- Rosetta-маскировка (tenant-имя → замороженный FGA-тип) — **не нужна** (FGA `registry_registry`/
  `registry_repository` консистентны с tenant-именами).
- rename Repository natural-key `registryId → namespaceId` — **откачен**; ключ остаётся `(registryId, name)`.
- Все `[PHASE-0-GATED]` пометки (B3 hyphen, by-lane conv-11 PROPOSED) — **сняты**: id-prefix `reg` legacy-форма
  валидна сейчас; by-lane code-split + reason-token теперь **нормативны** в `api-conventions.md`.

**Сохранено (ортогональные добавки REG-1, валидны):**
- **F4** `regionId` (net-new; обязателен на Create; peer-validate geo fail-closed `UNAVAILABLE`/reason
  `PEER_UNAVAILABLE`, miss → `FAILED_PRECONDITION`/`PEER_RESOURCE_MISSING`; **новое ребро registry→geo**) +
  `placementType` always-REGIONAL const; оба immutable; registry — regional-anycast (`zoneId` отсутствует)
  (REG-1-10..14).
- **F5** `default_visibility → defaultRepositoryVisibility` rename; сид новых repo; admin-gate→PUBLIC
  `PERMISSION_DENIED` (REG-1-15..16).
- **F7** `Repository.lifecycle ∈ {DURABLE,EPHEMERAL}` output-only enum (net-new, заменил implicit durable-bool);
  явный Create=DURABLE + опц. вход; reject в mask; auto-promote наблюдаем; lifecycle-CAS concurrency (REG-1-21..25).
- **F6** Repository natural-key `(registryId, name)` (EXISTING RG-1, natural-key сохранён); overlay⟂projection;
  PK dup→`ALREADY_EXISTS` + concurrency; registryId immutable; ACTIVE-guard `DELETING→FAILED_PRECONDITION`
  (REG-1-17..20).

**Зафиксировано как identity-инвариант (F1/F2/F8):** id immutable PK + единственная URL/pull-адресация
(core rule #15, REG-1-01/03/04); rename `name` НЕ ломает pull-URL (REG-1-07); field-absence globalSlug/
displayName/top-level-visibility/infra (REG-1-02); `UNIQUE(project,name)` project-scoped + concurrency
(REG-1-08); forward-only Delete (REG-1-09); malformed-id первым стейтментом + by-lane NOT_FOUND vs
FAILED_PRECONDITION + reason-token (REG-1-26/29); empty-mask full-PATCH (REG-1-28); INTERNAL-opaque
(REG-1-30); pagination-validate до authz (REG-1-31); per-RPC authz-matrix + list-filter (REG-1-32).

Покрытие обязательного минимума: identity id-immutable + URL-by-id ✓ (F1) · name mutable-но-не-в-URL ✓ (F2) ·
globalSlug отсутствует ✓ (F1-02) · regionId required + peer-validate geo + placementType const ✓ (F4) ·
defaultRepositoryVisibility ✓ (F5) · Repository (registryId,name) natural-key ✓ (F6) · lifecycle enum +
auto-promote ✓ (F7) · concurrent-race partial-UNIQUE(project,name) **и** PK(registryId,name) **и**
lifecycle-CAS ✓ (REG-1-08/18/25) · positive+negative+edge на каждую фичу · authz на каждом RPC ·
DB-инварианты ban #10 · фикс. тон ошибок · two-projection · EC/Operation.done.
