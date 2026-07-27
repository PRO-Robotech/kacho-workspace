# Sub-phase REG-1 (Namespace + Repository redesign) — Acceptance

> ⛔ **SUPERSEDED by `sub-phase-REG-1-registry-repository-acceptance.md` (owner reverted Namespace→Registry, 2026-07-20).**
> Этот документ описывает **откачённую** Namespace-модель (rename `Registry→Namespace`, `globalSlug`,
> `RenameNamespace :rename`, `name` immutable, `registryId→namespaceId`). Owner развернул эти изменения:
> ресурс остаётся `Registry` (id-based, id immutable/URL-адресация ban #15), `name` — mutable косметический
> label, `globalSlug`/`:rename` полностью удалены. Актуальный контракт (база + F4 region + F5
> defaultRepositoryVisibility + F7 lifecycle) — в `sub-phase-REG-1-registry-repository-acceptance.md`.
> **Не использовать этот файл как источник истины.** Оставлен для истории/диффа.

> Статус: **✅ APPROVED** (acceptance-reviewer, 2026-07-20 — 100% spec coverage, 38 сценариев, O1-O4 ратифицированы; 5 non-blocking advisories учесть при реализации: B3-merge-gate landed → REG-1 добавляет ns-generation; conv-11 by-lane reason-tokens остаются PENDING → baseline-код до Phase-0; accountSlug-источник для globalSlug-derive сверить с ProjectService.Get; edge opt-in-slug rename + BVA name-charset опц.). gate ban #1 ОТКРЫТ.
> Дата: 2026-07-20
> Ревьюер: acceptance-reviewer (✅ APPROVED 2026-07-20)
> Эпик/тикет: KAC-REG-1 (Phase-2 owner, redesign-2026; блокирует compute boot-image pull)
> Монорепо: `project/kacho` (`github.com/PRO-Robotech/kacho`) — легаси `project/kacho-*` не затрагивается.

## Обзор

REG-1 — первый инкремент пересборки registry-2026. `kacho-registry` — Phase-2 owner
**OCI-namespace'ов** (группа образов); compute-эталон зависит от него для boot-image pull,
поэтому registry втянут в свод как first-class Phase-2 owner (`00-unified-system-design.md`
§2/§7). Под-фаза приводит два **DB-policy** ресурса (`Namespace`, `Repository`) к целевому
tenant-facing дизайну (`docs/plans/kacho-redesign-2026/module-registry.md`) и общему хребту
(unified §1 конв-1/2/8/10/12, §5 инв-6).

Центральное изменение — **крупный breaking rename `Registry` → `Namespace`**: слово
«registry» зарезервировано за serving-host'ом (`endpoint`), а группирующая единица образов
называется `Namespace` (индустриальная терминология; **`Namespace` ≠ Kubernetes Namespace**).
Rename затрагивает proto-message, RPC-имена, REST-пути и id-prefix (`reg` → `ns-`). Вдобавок:
идентичность Namespace разведена на два ортогональных поля (project-scoped `name` ⟂ derived
`globalSlug°`), `name` становится **immutable** (`:rename`-verb вместо Update), вводятся
`placementType`(always-REGIONAL) + `regionId`(peer-validate geo); у Repository натуральный ключ
переименован `registryId → namespaceId`, а протекающий durable-bool заменён авторитетным
output-only enum `lifecycle ∈ {DURABLE, EPHEMERAL}`.

Это **owner-side** под-фаза: сценарии описывают наблюдаемое поведение публичного
`RegistryService` (`kacho.cloud.registry.v1`) через api-gateway. Data-plane docker OCI-flow,
read-only проекции (`Tag`/`Image`/`OciReferrer`), discovery grant-templates и
`GetEffectiveAccess` — отдельные под-фазы (см. §Out-of-scope: REG-2/REG-3).

> ⚠ **AS-IS предупреждение (сверено с ground-truth `project/kacho/proto/kacho/cloud/registry/v1/`
> + `services/registry/internal/`):** ресурс сейчас называется **`Registry`** (message `Registry`,
> RPC `Get/List/Create/Update/Delete`, REST `/registry/v1/registries/…`, id-prefix `reg`); `name`
> сейчас **MUTABLE** через Update (`UpdateRegistryRequest.name`, use-case меняет имя); НЕТ полей
> `region_id`/`placement_type`/`global_slug`; Repository использует `registry_id` (не
> `namespace_id`) и НЕ несёт поля `lifecycle` (durable/ephemeral выводится неявно из наличия
> overlay-строки). REG-1 переворачивает всё перечисленное. Каждая фича несёт блок `> AS-IS:` с
> точным текущим поведением и что implementer обязан удалить/изменить.

---

## Scope

Что REG-1 покрывает сценариями (positive + negative + edge + concurrency):

| # | Фича | Traceability |
|---|---|---|
| F1 | **Resource-rename `Registry`→`Namespace`**: message/RPC/REST/id-prefix `ns-`; FGA-тип `registry_registry` **заморожен** (Rosetta) + `fgaObject°` echo (по id); field-absence (нет `displayName`/top-level `visibility`) | module-registry Ментальная-модель-1, Namespace, rule 15/16; unified §2 registry, §8 B7 |
| F2 | **`name` immutable + `RenameNamespace :rename`** (AS-IS: name mutable → удалить path) | module-registry Namespace Update-классы, rule 12; unified §1 conv-1 |
| F3 | **Two-identity**: project-scoped `name` (`UNIQUE(project,name)`) ⟂ derived `globalSlug°` (default `<accountSlug>-<name>`, `UNIQUE(global_slug)` global; bare-global opt-in → probe → collision) | module-registry Ментальная-модель-1, rule 8/15; unified §1 conv-12, §2 registry |
| F4 | **`placementType` always-REGIONAL const** (carve-out) + **`regionId`** (OPTIONAL на Create → server-default resolved-echo; peer-validate geo fail-closed) | module-registry Namespace, rule 9/14; unified §1 conv-10, §5 инв-2 |
| F5 | **`defaultRepositoryVisibility`** (rename `default_visibility`; admin-gated any-path-to-PUBLIC; сид новых Repository) | module-registry Namespace, rule 12; unified §2 registry |
| F6 | **Repository natural-key `(namespaceId,name)`** — rename `registryId→namespaceId`; PK/FK/UNIQUE (dup/rename-collision → `ALREADY_EXISTS`, concurrent-race); ACTIVE-guard | module-registry Repository, rule 8; unified §5 инв-6, `data-integrity.md` |
| F7 | **Repository `lifecycle ∈ {DURABLE,EPHEMERAL}`** output-only enum (заменил durable-bool); явный Create=DURABLE + опц. вход; overlay-set auto-promote EPHEMERAL→DURABLE (наблюдаемо; lifecycle-CAS) | module-registry Repository, rule 13/14; unified §2 registry |
| F8 | **Update mutability-классы + by-lane тон** `[PHASE-0-GATED]`; malformed-id первым стейтментом; INTERNAL-opaque; pagination-validate до authz | module-registry rule 10/12; unified §1 conv-11, §5 инв-5 |

## Out-of-scope (явно НЕ в REG-1)

- **REG-2** (read-only projections движка): `Tag`/`Image`/`OciReferrer` (unified §7 B1 — `Referrer`
  переименован в **`OciReferrer`**), drop `Tag.immutable`/`Tag.signed`, единый `Image.sizeBytes`,
  `architectures[]`-denorm, `manifests[]` для index; `GetImage`/`ListReferrers`/`DeleteTag`/`DeleteImage`;
  compute `bootSource` тонкий `ResourceRef{type:"registry.image", id:"<namespaceId>/<repo>@<digest>", name°}`
  (unified §8 B13 imageKind-дискриминатор). **B1 (`OciReferrer`-rename) НЕ гейтит REG-1**: AS-IS
  `Referrer`-message + `ListReferrers`-RPC уже существуют и REG-1 их **не трогает** (rename `Referrer→OciReferrer`
  происходит в REG-2 вместе с cross-module change-set). Namespace/Repository REG-1 не используют ни один
  ref-wrapper (`ResourceRef`/`Referrer`/`OciReferrer`) → B1 нерелевантен для REG-1.
- **REG-3** (docker access-control + discovery): data-plane OCI Bearer-challenge на `endpoint:443`
  (thin auth-proxy), grant-templates `namespaceGrantTemplate`/`repositoryGrantTemplate` (byte-identical
  тело `iam.AccessBindingService/Create`), `GetEffectiveAccess` **client-side** readiness-gate (unified §8
  B16 — не серверный барьер, ban #9), pull-identity precheck (unified §8 B6), anonymous public pull
  (`user:*` v_get ⟺ `visibility=PUBLIC`), reverse-audit `ListRepositoryGrants`/`ListEffectiveSubjects`,
  роли `registry.repoCreator`/`puller`/`pusher`/`admin`, **iam-side scope-alias `registry_namespace:`
  (unified §8 B7)**.
- **Data-plane docker** (push/pull/login OCI Distribution, `405` на data-plane DELETE, JWKS-verify) —
  целиком REG-3.
- **InternalRegistryService redesign** (`GetNamespaceStats`/`TriggerGarbageCollection`/`GetRepositoryInternal`
  — rename `RegistryStats→NamespaceStats`, two-projection infra-полей) — REG-4 (кандидат; сейчас
  AS-IS `internal_registry_service.proto` существует, REG-1 его не трогает кроме message-rename, если требуется
  buf-breaking-совместимостью — см. §Definition of Done open question O3).
- **Optional-server-default `regionId`** (module-registry rule 9: омит → account/project-default +
  resolved-echo `Operation.response.regionId`) — **отложено** до определения источника дефолт-региона
  (не существует в AS-IS/target: unified §2 iam НЕ несёт default-region на `Account`/`Project`; нужно новое
  iam-поле на Phase-1 ИЛИ cluster/registry-config-дефолт). REG-1 делает `regionId` обязательным на Create
  (F4, O1). Follow-up вернёт optional-омит после закрытия источника.
- **`validateOnly:true` sync dry-run** для Create/Update/Rename (`resolved°`-echo + `warnings[]`,
  `NAMESPACE_NAME_IS_GLOBAL`/`LIFECYCLE_DEFAULT_DURABLE`/`VISIBILITY_INHERITED` warnings) — REG-4 (spine
  conv-6; net-new sync-path вне ядра REG-1 rename). Single-shot Create покрывает derive/resolve-echo без
  dry-run.
- **Downstream FGA owner-tuple** (`registry_outbox` register-drainer/reconciler) материализуется
  eventually; REG-1 **не гейтит** `Operation.done` на его видимость (ban #9). Behaviour outbox не меняется.
- **Endpoint host `registry.kacho.local`→`registry.in-cloud.io`** и pull-path `endpoint/{globalSlug}/{repo}`
  — `Namespace.endpoint°` и `Repository.pullReference°` (derived `host/{globalSlug}/{repo}`) — оба
  derived-выход, **отложены в REG-3** (зависят от serving-host, а не только от `globalSlug`). REG-1 фиксирует
  только что `globalSlug` — первый сегмент пути (F3); полная data-plane pull-семантика — REG-3.

## Traceability-легенда

`°` = output-only поле (server-derived, на вход Create/Update не принимается). `⊘` = обязательный
immutable-after-Create вход. Каждый сценарий несёт ссылку `→ module-registry rule N` / `→ unified §X`
в заголовке фичи. REST-пути: public `/registry/v1/…` (:9090, external-safe). JSON — camelCase
(`namespaceId`, `projectId`, `globalSlug`, `defaultRepositoryVisibility`, `createdAt°`). `createdAt°`
усечён до секунд на wire. Мутации → `Operation` (prefix `epd`/`rop` — см. §Открытые вопросы O4); read — sync; Watch нет
(полл `OperationService.Get`). Async-Then формулируется как «`Operation.done && !error`, затем `Get`-проверка».

**Rosetta (tenant-имя → FGA object type; тип НЕ переименовывается — deployed/stability, unified §8 B7):**

| Tenant-ресурс | FGA object type | Читается как |
|---|---|---|
| `Namespace` | `registry_registry:<namespaceId>` | «the Namespace you created» |
| `Repository` | `registry_repository:<namespaceId>/<name>` | «this Repository» |

---

## F1 — Resource-rename `Registry`→`Namespace` (id `ns-`, FGA-тип заморожен, field-absence)

> `→ module-registry` Ментальная-модель-1, Namespace, rule 15/16 · `→ unified §2 registry, §8 B7`
> **AS-IS:** message `Registry`; RPC `Get/List/Create/Update/Delete` (`GetRegistryRequest`…); REST
> `/registry/v1/registries/{registry_id}`; id-prefix `reg` (`ids.PrefixRegistry`, `NewID`); `endpoint°`
> = `registry.kacho.local/<id>`; НЕТ полей `region_id`/`placement_type`/`global_slug`. У `Registry`
> **уже нет** `displayName` и top-level `visibility` (есть только `default_visibility`) — REG-1 их **не
> добавляет** и локает field-absence как инвариант.
> REG-1 переименовывает message → `Namespace`, RPC → `GetNamespace/ListNamespaces/CreateNamespace/
> UpdateNamespace/DeleteNamespace(+RenameNamespace)`, REST → `/registry/v1/namespaces/{namespaceId}`,
> id-prefix → `ns-`. **FGA object type остаётся `registry_registry`** (заморожен — deployed/stability;
> переименование tenant-понятия ≠ переименование FGA-типа; leak гасится Rosetta + inline-аннотацией).

### Сценарий REG-1-01 `[PHASE-0-GATED]` (частично): happy-path CreateNamespace → Operation → GetNamespace

**ID:** REG-1-01

**Given** project `prj-7h3n9k2m5p8q1` существует в iam (peer-validate `ProjectService.Get` проходит)
**And** вызывающий имеет `v_create@registry_registry`-эквивалент (editor на parent-project)
**And** регион `eu-north-1` существует в geo

**When** клиент вызывает `CreateNamespace` (`POST /registry/v1/namespaces`) с payload:
  - `projectId` = `"prj-7h3n9k2m5p8q1"`
  - `name` = `"payments"`
  - `regionId` = `"eu-north-1"`

**Then** ответ — `Operation` (async); `metadata` анмаршалится в `CreateNamespaceMetadata`; `metadata.namespaceId` заполнен **СРАЗУ** (до `done`) и имеет форму `ns-<base32>`
**And** полл `OperationService.Get(op.id)` (`GET /registry/v1/operations/{id}`) с inter-poll задержкой до `done==true`; `result` — `response` (не `error`)
**And** последующий `GetNamespace` (`GET /registry/v1/namespaces/ns-<…>`) возвращает `Namespace` с `id=="ns-<…>"`, `projectId=="prj-7h3n9k2m5p8q1"`, `name=="payments"`, `regionId=="eu-north-1"`, `placementType=="REGIONAL"`, `createdAt°` (усечён до секунд), `status.value=="ACTIVE"`, `endpoint°` (derived serving-host), `fgaObject°=="registry_registry:ns-<…>"`

> `[PHASE-0-GATED]`: конкретная **hyphen-форма prefix `ns-`** (vs `ns` без дефиса) и её регистрация в
> `corevalidate` prefix→type-router приземляются только после Phase-0 governance change-set (unified §9
> B3 — «id-prefix hyphen-форма зафиксирована в `corevalidate`/`api-conventions.md`»). До merge B3 —
> implementer не хардкодит дефис. Async-форма, `metadata.namespaceId`-сразу, поля ответа — **ungated**.

### Сценарий REG-1-02: GetNamespace field-absence — нет `displayName`, нет top-level `visibility`

**ID:** REG-1-02

**Given** namespace `ns-c9k2` создан как в REG-1-01

**When** клиент вызывает `GetNamespace` (`GET /registry/v1/namespaces/ns-c9k2`)

**Then** сериализованное тело **ОТСУТСТВУЕТ** поля `displayName` и `visibility` (top-level) — UI pretty-name живёт в `labels.displayName`, а авторитетный гейт видимости — на `Repository.visibility`; namespace несёт **только** `defaultRepositoryVisibility` (сид, F5)
**And** тело **не содержит** инфра-полей (`engineNamespace`, `bucketPrefix`, `storageDriver`, `numericInfraId`) — two-projection (те только Internal* :9091, REG-4)

### Сценарий REG-1-03: RPC/REST переименованы `registries`→`namespaces` (rename-lock)

**ID:** REG-1-03

**Given** api-gateway с зарегистрированными public RPC redesign-registry

**When** клиент вызывает `GetNamespace`/`ListNamespaces`/`CreateNamespace`/`UpdateNamespace`/`DeleteNamespace`/`RenameNamespace` по путям `/registry/v1/namespaces/…`

**Then** каждый резолвится (200/Operation); поля запроса именуются `namespaceId` (не `registryId`)
**And** старые REST-пути `/registry/v1/registries/…` и старые RPC-имена `Get/List/Create/Update/Delete` (Registry) — **удалены** (breaking rename; AS-IS путь больше не резолвится). Регистрация public-mux — территория `api-gateway-registrar` (e2e-assert)

### Сценарий REG-1-04: `fgaObject°` echo — `registry_registry:<namespaceId>` по id (не по name/globalSlug)

**ID:** REG-1-04

**Given** namespace `ns-c9k2` (`name="payments"`, `globalSlug="acme-payments"`)

**When** `GetNamespace(ns-c9k2)`

**Then** `fgaObject° == "registry_registry:ns-c9k2"` — построен по **id** (`ns-…`), НЕ по `name`/`globalSlug`; FGA-тип `registry_registry` заморожен (Rosetta: читается как «the Namespace you created»)
**And** `fgaObject°` — ready-to-paste scope-handle для `AccessBinding.scope` (потребитель не собирает scope из pull-пути)
**And** iam-side scope-alias `registry_namespace:` (unified §8 B7) — **out-of-scope REG-1** (going-forward cross-module governance; REG-1 эмитит замороженный `registry_registry:`)

---

## F2 — `name` immutable + `RenameNamespace :rename`

> `→ module-registry` Namespace Update-классы, rule 12 · `→ unified §1 conv-1`
> **AS-IS behavior-change:** `UpdateRegistryRequest.name` (field 5) сейчас **mutable** — use-case
> (`update.go`) применяет смену имени (DNS-safe re-validate, partial-UNIQUE conflict → `ALREADY_EXISTS`).
> REG-1 делает `name` **immutable через Update** и вводит `RenameNamespace :rename`-verb.
> Implementer обязан **удалить** name-update-путь из `UpdateNamespace` (поле остаётся только для
> immutable-reject, из `update_mask` known-set исключается) и добавить `RenameNamespace`.

### Сценарий REG-1-05: UpdateNamespace с `name` → INVALID_ARGUMENT (reject до UpdateMask)

**ID:** REG-1-05

**Given** namespace `ns-c9k2` (`name="payments"`)

**When** клиент вызывает `UpdateNamespace` (`PATCH /registry/v1/namespaces/ns-c9k2`) с `updateMask=["name"]`, `name="billing"`

**Then** **синхронный** `INVALID_ARGUMENT` с текстом `"name is immutable after Namespace.Create"` — immutable-switch срабатывает **ДО** `corevalidate.UpdateMask` (иначе `name` отвергся бы как generic unknown-field вместо конвенционного тона)
**And** namespace не изменён (`GetNamespace(ns-c9k2).name == "payments"`)

### Сценарий REG-1-06: happy-path RenameNamespace — name сменён, globalSlug re-derived

**ID:** REG-1-06

**Given** namespace `ns-c9k2` (`name="payments"`, `globalSlug="acme-payments"` derived-default)
**And** имя `"billing"` свободно в project (`UNIQUE(project,name)` не нарушено)

**When** клиент вызывает `RenameNamespace` (`POST /registry/v1/namespaces/ns-c9k2:rename`) с `newName="billing"`

**Then** ответ — `Operation`; полл до `done && !error`
**And** `GetNamespace(ns-c9k2).name == "billing"`; `id` не изменился (`ns-c9k2` — стабильный якорь)
**And** derived-default `globalSlug°` переслугован в `"acme-billing"` (`<accountSlug>-<newName>`); ре-derive применяется **только** к default-derived slug (bare-global opt-in slug — предмет отдельного verb-контракта, отмечается в тексте)

> Rename переписывает pull-ссылки (`endpoint/{globalSlug}/{repo}`) — дорогая операция; **id-based**
> ссылки (`bootSource.id = <namespaceId>/…`) переживают rename by construction (REG-2/compute-seam).

### Сценарий REG-1-07 (negative): RenameNamespace на занятое имя → ALREADY_EXISTS

**ID:** REG-1-07

**Given** namespace `ns-c9k2` (`name="payments"`); namespace `ns-a1b2` (`name="billing"`) — оба в project `prj-7h3n`

**When** `RenameNamespace(ns-c9k2, newName="billing")`

**Then** `Operation{done:true}` c `result.error`: код `ALREADY_EXISTS` (`UNIQUE(project_id,name)` среди живых, SQLSTATE 23505 — DB-backstop, ban #10)
**And** no-op / malformed `newName` (`newName == "payments"` текущее, либо не-DNS-safe) → **синхронный** `INVALID_ARGUMENT` (verb-guard первым стейтментом)

### Сценарий REG-1-37: DeleteNamespace → status-transition ACTIVE→DELETING (forward-only)

**ID:** REG-1-37

> **AS-IS:** `Delete` (Registry) уже forward-only (`RegistryStatus` DELETING терминальный, partial-UNIQUE
> освобождает имя). REG-1 — тот же контракт под именем `DeleteNamespace` + renamed поле `namespaceId`.

**Given** namespace `ns-c9k2` `status=ACTIVE`

**When** клиент вызывает `DeleteNamespace` (`DELETE /registry/v1/namespaces/ns-c9k2`)

**Then** ответ — `Operation`; `metadata` (`DeleteNamespaceMetadata`) несёт `namespaceId=="ns-c9k2"` **сразу** (до `done`)
**And** переход `status`: `ACTIVE→DELETING` (forward-only, DELETING терминальный — revert запрещён, иначе partial-`UNIQUE(project,name)` конфликтует с re-Create того же имени); имя немедленно освобождается для повторного `CreateNamespace` того же `(project,name)`
**And** повторный `DeleteNamespace(ns-c9k2)` на уже-`DELETING` → идемпотентно / `NOT_FOUND` (well-formed уже недоступен); downstream owner-tuple unregister — eventually через `registry_outbox` (не гейтит `done`, ban #9)

---

## F3 — Two-identity: project-scoped `name` ⟂ derived `globalSlug°`

> `→ module-registry` Ментальная-модель-1, rule 8/15 · `→ unified §1 conv-12, §2 registry`
> **AS-IS:** единственное имя-поле — `name` (DNS-safe, partial `UNIQUE(project_id,name) WHERE
> status<>'DELETING'`). НЕТ `global_slug`. REG-1 разводит идентичность: `name` остаётся project-scoped
> (spine-конформный `UNIQUE(project,name)` — сохранить partial-live-форму), а **новый** derived
> `globalSlug°` — первый сегмент глобального pull-пути с **глобальным** `UNIQUE(global_slug)`.
> Default (input опущен) → сервер деривит `<accountSlug>-<name>` (глобально-уникален by construction —
> account-slug уникален). Opt-in (input задан) → bare-global slug: **probe** глобальной доступности,
> коллизия → `ALREADY_EXISTS` с tenant-prefix-подсказкой (reason `NAMESPACE_NAME_IS_GLOBAL` — gated).
> **NB:** payload'ы F3 фокусируются на измерении `name`/`globalSlug` и опускают `regionId` для краткости —
> каждый несёт валидный `regionId` (обязателен, F4); иначе сработал бы REG-1-15 раньше.

### Сценарий REG-1-08: globalSlug опущен → derived `<accountSlug>-<name>` + echo

**ID:** REG-1-08

**Given** project `prj-7h3n` в аккаунте с `accountSlug="acme"`; регион `eu-north-1`

**When** `CreateNamespace` с `projectId="prj-7h3n"`, `name="payments"` (**без** `globalSlug`)

**Then** `Operation.done && !error`; `result.response` (и последующий `GetNamespace`) несёт `globalSlug° == "acme-payments"` (derived `<accountSlug>-<name>`, ECHO'нут — клиент scope-строку руками не собирает)
**And** `globalSlug°` глобально-уникален by construction (account-slug уникален ⇒ не гонишься с невидимым чужим тенантом)

### Сценарий REG-1-09: явный bare-global globalSlug (свободен) → принят

**ID:** REG-1-09

**Given** глобальный slug `"team-payments"` **не занят** ни одним namespace

**When** `CreateNamespace` с `projectId="prj-7h3n"`, `name="payments"`, `globalSlug="team-payments"` (opt-in bare-global)

**Then** `Operation.done && !error`; `GetNamespace.globalSlug° == "team-payments"` (bare-global разрешён явным opt-in)

> **Probe — best-effort UX, НЕ авторитетный гейт.** Пре-чек «занят ли globalSlug» может дать раннюю
> ошибку (лучший UX), но **авторитетная** уникальность — `UNIQUE(global_slug)` DB-CAS (REG-1-12); implementer
> НЕ строит TOCTOU probe-then-insert (ban #10) — вставка полагается на DB-констрейнт, probe лишь ускоряет
> сообщение.

### Сценарий REG-1-10 `[PHASE-0-GATED]` (частично): bare-global globalSlug занят → ALREADY_EXISTS + tenant-prefix hint

**ID:** REG-1-10

**Given** существует namespace с `globalSlug="payments"` (другой tenant, невидим вызывающему)

**When** `CreateNamespace` с `name="payments"`, `globalSlug="payments"` (explicit bare-global)

**Then** `Operation{done:true}` c `result.error`: код `ALREADY_EXISTS` (ungated — `UNIQUE(global_slug)`, 23505) + текст-подсказка дословно `"explicit globalSlug 'payments' is globally unique across ALL tenants and is already taken; omit globalSlug to auto-derive a tenant-prefixed slug (e.g. acme-payments), or choose a tenant-prefixed one"` (тон-контракт ungated, эмитится на **каждом** Create-пути — silent dead-slug недопустим)
**And** `[PHASE-0-GATED]` **только** detail `reason:"NAMESPACE_NAME_IS_GLOBAL"` в `google.rpc.Status.details` — сам механизм reason-token в `rpc.Status.details` приземляется после Phase-0 governance change-set (unified §9 DT / §5 инв-5, PROPOSED; тот же гейт, что GEO-1-05/REG-1-16/34). Код + hint-текст от гейта НЕ зависят

### Сценарий REG-1-11: `UNIQUE(project,name)` — project-scoped коллизия vs cross-project OK

**ID:** REG-1-11

**Given** namespace `ns-c9k2` (`name="payments"`) в project `prj-7h3n`

**When** `CreateNamespace` с `projectId="prj-7h3n"`, `name="payments"` (тот же project, дубль имени)

**Then** `Operation{done:true}` c `result.error`: `ALREADY_EXISTS` (`UNIQUE(project_id,name)` среди живых, 23505)

**When** `CreateNamespace` с `projectId="prj-DIFFERENT"`, `name="payments"` (другой project, то же имя)

**Then** `Operation.done && !error` — коллизия ловится **только** в своём проекте (spine-конформно; не гонишься с невидимым чужим тенантом по project-scoped имени)

**When** (concurrency) два конкурентных `CreateNamespace` в **одном** project `prj-7h3n` с **одним** `name="orders"` стартуют одновременно

**Then** **ровно один** → `done && !error`; **другой** → `result.error` `ALREADY_EXISTS` (partial `UNIQUE(project_id,name) WHERE status<>'DELETING'` — DB-CAS, ровно один writer выигрывает slot; concurrent-goroutines integration-тест обязателен, `data-integrity.md` чек-лист п.5 — на **каждый** спорный DB-инвариант)

### Сценарий REG-1-12 (concurrency): два Create с одинаковым bare-global globalSlug → ровно один

**ID:** REG-1-12

**Given** глобальный slug `"shared-slug"` свободен; два конкурентных `CreateNamespace` (разные project'ы, оба с explicit `globalSlug="shared-slug"`) стартуют одновременно

**When** обе Operation исполняются worker'ами

**Then** **ровно одна** → `done && !error` (её `GetNamespace.globalSlug° == "shared-slug"`); **другая** → `result.error` `ALREADY_EXISTS` (`UNIQUE(global_slug)` глобальный — DB-CAS, ровно один writer выигрывает slot; integration-тест с concurrent goroutines обязателен, `data-integrity.md` чек-лист п.5)

### Сценарий REG-1-13: globalSlug immutable через Update (rename-only)

**ID:** REG-1-13

**Given** namespace `ns-c9k2` (`globalSlug="acme-payments"`)

**When** `UpdateNamespace` с `updateMask=["globalSlug"]`, `globalSlug="acme-billing"`

**Then** **синхронный** `INVALID_ARGUMENT "globalSlug is immutable after Namespace.Create"` (reject до `UpdateMask`); меняется **только** через `RenameNamespace` (F2, re-derive default-slug)

---

## F4 — `placementType` always-REGIONAL const + `regionId` (peer-validate geo, required)

> `→ module-registry` Namespace, rule 9/14 · `→ unified §1 conv-10, §5 инв-2`
> **AS-IS:** `Registry` **не несёт** ни `region_id`, ни `placement_type` (OCI-контент трактовался
> зоне/регион-нейтрально). REG-1 вводит **always-REGIONAL** `placementType`-константу (осознанный
> LEAN carve-out ради spine placement-discriminator parity с compute; gloss «not a choice») и
> `regionId` (REGIONAL anycast — `zoneId` пуст by construction). `regionId` peer-validate
> `geo.v1.RegionService.Get` (fail-closed) — **новое runtime-ребро `registry → geo`** (ацикличность
> holds: geo — leaf, registry не зовётся обратно; см. §DoD deliverables + polyrepo.md).
>
> **Дизайн-отклонение REG-1 (обосновано, зафиксировать на review):** module-registry rule 9 делает
> `regionId` **OPTIONAL** на Create с server-default resolve-echo (опущен → account/project-default).
> Такого **источника дефолт-региона не существует ни в AS-IS, ни в target-дизайне** (unified §2 iam НЕ
> несёт default-region-поля на `Account`/`Project`; registry-config его не декларирует). Поэтому REG-1
> делает `regionId` **обязательным на Create** (всегда явный + peer-validate geo). Optional-server-default
> + resolved-echo (rule 9) — **отложено** в follow-up, гейтится **определением источника** дефолт-региона
> (кросс-фазовая зависимость: новое iam-поле default-region на Phase-1 ИЛИ cluster/registry-config-дефолт;
> см. §Out-of-scope + O1). До закрытия источника REG-1 не имитирует несуществующий resolve.

### Сценарий REG-1-14: placementType always-REGIONAL на всех проекциях; zoneId пуст

**ID:** REG-1-14

**Given** namespace `ns-c9k2` создан (любым путём)

**When** `GetNamespace(ns-c9k2)` и `ListNamespaces`

**Then** `placementType == "REGIONAL"` в каждой проекции (константа — «not a choice»; из зональной coherence-проверки исключён by construction, остаётся региональная)
**And** namespace **не несёт** `zoneId` (пусто/отсутствует) — registry-ресурсы зон не несут (`data-integrity.md` anycast-исключение)

### Сценарий REG-1-15 (negative): regionId обязателен на Create → омитнут → INVALID_ARGUMENT

**ID:** REG-1-15

**Given** project `prj-7h3n` существует

**When** `CreateNamespace` с `projectId="prj-7h3n"`, `name="payments"` (**без** `regionId`)

**Then** **синхронный** `INVALID_ARGUMENT "regionId is required"` первым стейтментом (REG-1: `regionId` обязателен — optional-server-default отложен, см. F4-intro дизайн-отклонение; операция не создаётся)

> Когда источник дефолт-региона будет определён (iam default-region / cluster-config), follow-up вернёт
> optional-омит + resolved-echo `Operation.response.regionId` (module-registry rule 9). REG-1 не имитирует
> несуществующий resolve.

### Сценарий REG-1-16 `[PHASE-0-GATED]` (частично): явный несуществующий regionId → отказ (peer-validate geo)

**ID:** REG-1-16

**Given** регион `eu-west-9` **не существует** в geo

**When** `CreateNamespace` с `name="payments"`, `regionId="eu-west-9"`

**Then** отказ на request-path через peer-validate `geo.v1.RegionService.Get` (fail-closed): **ungated** — отказ гарантирован (не создаётся namespace с висячим regionId)
**And** `[PHASE-0-GATED]` — конкретный **код**: peer-validate lane → `FAILED_PRECONDITION` (by-lane split, unified §5 инв-5 PROPOSED) vs direct `INVALID_ARGUMENT`; reason-token `REGION_NOT_FOUND` — приземляется после Phase-0 governance change-set. До merge — реализация даёт текущий baseline-код (implementer фиксирует единый до merge)

### Сценарий REG-1-17 (edge): geo недоступен на Create → UNAVAILABLE fail-closed

**ID:** REG-1-17

**Given** `geo.v1.RegionService.Get` недоступен (peer down)

**When** `CreateNamespace` с явным `regionId="eu-north-1"`

**Then** `UNAVAILABLE` (fail-closed для мутаций — owner недоступен, namespace НЕ создаётся; `data-integrity.md` cross-domain п.2). Per-call deadline на geo-вызове обязателен (`architecture.md` concurrency)

### Сценарий REG-1-18: regionId / placementType immutable после Create

**ID:** REG-1-18

**Given** namespace `ns-c9k2` (`regionId="eu-north-1"`, `placementType="REGIONAL"`)

**When** `UpdateNamespace` с `updateMask=["regionId"]`, `regionId="eu-central-1"`

**Then** **синхронный** `INVALID_ARGUMENT "regionId is immutable after Namespace.Create"` (перенос region сломал бы storage-locality блобов)
**And** то же для `placementType` в mask → `INVALID_ARGUMENT "placementType is immutable after Namespace.Create"`

---

## F5 — `defaultRepositoryVisibility` (rename + admin-gate)

> `→ module-registry` Namespace, rule 12 · `→ unified §2 registry`
> **AS-IS:** поле называется `default_visibility` (`Registry.default_visibility`, миграция 0005
> `registries.default_visibility TEXT DEFAULT 'PRIVATE' CHECK IN(PRIVATE,PUBLIC)`), mutable admin-gated,
> сид `Repository.visibility` на create. REG-1 переименовывает proto-поле → `defaultRepositoryVisibility`
> (единственный namespace-level visibility-рычаг; сам namespace top-level `visibility` НЕ несёт — F1).
> Семантика admin-gate any-path-to-PUBLIC — **не меняется**.

### Сценарий REG-1-19: defaultRepositoryVisibility сидит новый Repository при омитнутом visibility

**ID:** REG-1-19

**Given** namespace `ns-c9k2` с `defaultRepositoryVisibility.value=="PRIVATE"`

**When** `CreateRepository` под `ns-c9k2` **без** явного `visibility` (F6)

**Then** созданный Repository несёт `visibility.value=="PRIVATE"` (унаследован из `defaultRepositoryVisibility`)

**When** admin меняет `UpdateNamespace(ns-c9k2, updateMask=["defaultRepositoryVisibility"], defaultRepositoryVisibility=PUBLIC)`, затем создаёт **новый** repo без visibility

**Then** новый repo несёт `visibility.value=="PUBLIC"` (inherited-default); **существующие** repo НЕ перекрашиваются (per-repo `Repository.visibility` остаётся authoritative)

### Сценарий REG-1-20 (negative): не-admin ведёт defaultRepositoryVisibility→PUBLIC → PERMISSION_DENIED

**ID:** REG-1-20

**Given** вызывающий имеет `v_update@registry_registry`, но **не** registry admin
**And** namespace `ns-c9k2` c `defaultRepositoryVisibility=PRIVATE`

**When** `UpdateNamespace(ns-c9k2, updateMask=["defaultRepositoryVisibility"], defaultRepositoryVisibility=PUBLIC)`

**Then** `PERMISSION_DENIED` (any-path-to-PUBLIC требует registry admin, module-registry rule 14; caller уже доказал `v_update` → код честен, не existence-hiding). Текст называет нужную capability: `"setting default repository visibility to PUBLIC requires registry admin (role registry.admin) on registry_registry:ns-c9k2"`

---

## F6 — Repository natural-key `(namespaceId,name)` (rename `registryId→namespaceId`)

> `→ module-registry` Repository, rule 8 · `→ unified §5 инв-6`, `data-integrity.md`
> **AS-IS:** `Repository.registry_id` + `CreateRepositoryRequest.registry_id`; overlay-таблица
> `repository_configs (registry_id, name)` PK; FK `registry_id → registries(id) ON DELETE CASCADE`.
> REG-1 переименовывает поле/ключ `registryId → namespaceId` (message + все repo-scoped request'ы);
> DB-инварианты (PK/FK/CHECK) сохраняют форму, меняется имя колонки (новая миграция — **не** редактировать
> применённую 0005; ban #5). Natural-key (имя несёт `/`: `backend/api`) — spine-исключение, сохранено.
> **ACTIVE-guard (REG-1-25, DELETING→`FAILED_PRECONDITION`) — EXISTING** (AS-IS RG-1 A24: overlay-мутации в
> tx c `SELECT registries.status FOR UPDATE`); REG-1 не меняет поведение, только renamed текст `"namespace is
> being deleted"` (было `"registry is being deleted"`). `pullReference°` (derived `host/{globalSlug}/{repo}`)
> — output-выход Repository, **отложен в REG-3** вместе с `endpoint°`-host и data-plane pull-семантикой
> (зависит от serving-host, а не только от `globalSlug`); REG-1 его не эмитит.

### Сценарий REG-1-21: happy-path CreateRepository → GetRepository (namespaceId + fgaObject)

**ID:** REG-1-21

**Given** namespace `ns-c9k2` (`status=ACTIVE`); вызывающий с доступом

**When** `CreateRepository` (`POST /registry/v1/namespaces/ns-c9k2/repositories`) с `repository="backend/api"`, `description="Core API images"`

**Then** `Operation.done && !error` (`metadata.namespaceId=="ns-c9k2"`, `metadata.repository=="backend/api"` сразу)
**And** `GetRepository` (`GET /registry/v1/namespaces/ns-c9k2/repositories/backend/api`) возвращает `Repository` с `namespaceId=="ns-c9k2"` (renamed из `registryId`), `name=="backend/api"` (несёт `/`), `description=="Core API images"`, `createdAt°`, `fgaObject°=="registry_repository:ns-c9k2/backend/api"` (по namespaceId+name, НЕ по globalSlug)

### Сценарий REG-1-22 (negative): дубль (namespaceId,name) → ALREADY_EXISTS

**ID:** REG-1-22

**Given** durable Repository `ns-c9k2/backend/api` существует

**When** `CreateRepository(ns-c9k2, repository="backend/api")` повторно

**Then** `Operation{done:true}` c `result.error`: `ALREADY_EXISTS` (PK `(namespace_id,name)` 23505 — DB-backstop, ban #10)

### Сценарий REG-1-23 (concurrency): два Create одного (namespaceId,name) → ровно один

**ID:** REG-1-23

**Given** repo `ns-c9k2/web` не существует; два конкурентных `CreateRepository(ns-c9k2, "web")`

**When** обе Operation исполняются

**Then** **ровно одна** → `done && !error`; **другая** → `result.error` `ALREADY_EXISTS` (PK-CAS, ровно один writer; concurrent-goroutines integration-тест обязателен)

### Сценарий REG-1-24: namespaceId immutable у Repository

**ID:** REG-1-24

**Given** Repository `ns-c9k2/backend/api`

**When** `UpdateRepository` с `updateMask=["namespaceId"]` (перенос в другой namespace)

**Then** **синхронный** `INVALID_ARGUMENT "namespaceId is immutable after Repository.Create"` (reject до UpdateMask; cross-namespace move структурно невыразим — только через engine re-home, вне REG-1)

### Сценарий REG-1-25 (edge, ACTIVE-guard): namespace DELETING → overlay-мутация → FAILED_PRECONDITION

**ID:** REG-1-25

**Given** namespace `ns-c9k2` в состоянии `status=DELETING` (запущен `DeleteNamespace`)

**When** `CreateRepository(ns-c9k2, "backend/api")` (или `UpdateRepository`/`RenameRepository` под ним)

**Then** `Operation{done:true}` c `result.error`: `FAILED_PRECONDITION "namespace is being deleted"` — ACTIVE-guard в мутационной tx (`SELECT registries.status FOR UPDATE`; module-registry rule 8, `data-integrity.md`)

### Сценарий REG-1-38: RenameRepository под новым namespaceId (rename-lock + collision)

**ID:** REG-1-38

> **AS-IS:** `RenameRepository` (в пределах одного реестра, D-5) уже существует; REG-1 — тот же контракт
> под renamed полем `namespaceId` (было `registry_id`); durable → re-key overlay (UPDATE), ephemeral →
> auto-promote INSERT (F7 REG-1-28). Поведение unchanged, кроме поля-ключа.

**Given** durable Repository `ns-c9k2/backend/api`; имя `backend/api-v2` свободно в namespace `ns-c9k2`

**When** `RenameRepository` (`POST /registry/v1/namespaces/ns-c9k2/repositories/backend/api:rename`) с `newName="backend/api-v2"`

**Then** `Operation.done && !error`; `GetRepository(ns-c9k2, "backend/api-v2")` резолвит; старое имя `backend/api` → `NOT_FOUND`; поля запроса именуются `namespaceId` (renamed)
**And** целевое имя занято другим repo в том же `namespaceId` → `Operation{done:true}` `result.error` `ALREADY_EXISTS` (PK `(namespace_id,name)` 23505); cross-namespace rename структурно невыразим (D-5 — нет поля целевого namespace)

---

## F7 — Repository `lifecycle ∈ {DURABLE,EPHEMERAL}` output-only enum

> `→ module-registry` Repository, rule 13/14 · `→ unified §2 registry`
> **AS-IS:** `Repository` **не несёт** поля `lifecycle`. Класс (ephemeral/durable) выводится **неявно**
> из наличия overlay-строки `repository_configs`: durable = есть overlay (survives-empty), ephemeral =
> проекция без overlay (register-on-first-push, unregister-on-last-tag). REG-1 делает исчезаемость
> **авторитетным output-only enum** `lifecycle` (заменил протекающий implicit-bool): один сигнал вместо
> «задан ли overlay-field». Явный `CreateRepository` → `DURABLE` by default (explicit intent = сохранить
> каркас); опц. вход `lifecycle: DURABLE|EPHEMERAL` перекрывает; overlay-set на EPHEMERAL push-repo
> AUTO-PROMOTE'ит `EPHEMERAL→DURABLE` (наблюдаемо через enum). AS-IS auto-promote (overlay upsert на
> Update/Rename) уже существует — REG-1 делает его **наблюдаемым** через `lifecycle`.

### Сценарий REG-1-26: явный CreateRepository → lifecycle°=DURABLE (survives-empty)

**ID:** REG-1-26

**Given** namespace `ns-c9k2` ACTIVE

**When** `CreateRepository(ns-c9k2, "backend/api")` **без** поля `lifecycle`

**Then** `Operation.done && !error`; `GetRepository.lifecycle.value == "DURABLE"` (явный intent-create → DURABLE by default), gloss `displayName == "Kept even when it has no tags"`
**And** repo виден с `tagCount == 0` (survives-empty; durable-empty не исчезает — unregister-on-last-tag НЕ срабатывает)

### Сценарий REG-1-27: явный вход lifecycle=EPHEMERAL → lifecycle°=EPHEMERAL

**ID:** REG-1-27

**When** `CreateRepository(ns-c9k2, "scratch/tmp", lifecycle="EPHEMERAL")` (явный опц. вход перекрывает дефолт)

**Then** `Operation.done && !error`; `GetRepository.lifecycle.value == "EPHEMERAL"`, gloss `"Auto-removed when it has no tags"` (register-on-first-push семантика — предсказуемый эксплицитный рычаг вместо вывода из наличия overlay-field)

### Сценарий REG-1-28: overlay-set на EPHEMERAL push-repo → auto-promote → lifecycle°=DURABLE

**ID:** REG-1-28

**Given** ephemeral repo `ns-c9k2/pushed/img` (register-on-first-push, `lifecycle=EPHEMERAL`, overlay-строки нет)

**When** `UpdateRepository(ns-c9k2, "pushed/img", updateMask=["description"], description="now configured")` (устанавливает overlay-поле)

**Then** `Operation.done && !error`; `GetRepository.lifecycle.value == "DURABLE"` — установка overlay AUTO-PROMOTE'ит `EPHEMERAL→DURABLE` (наблюдаемо через enum); теперь survives-empty
**And** `RenameRepository` ephemeral-repo → тот же auto-promote (`EPHEMERAL→DURABLE`, INSERT overlay целевого имени)

### Сценарий REG-1-29: lifecycle output-only — в UpdateMask → INVALID_ARGUMENT

**ID:** REG-1-29

**When** `UpdateRepository` с `updateMask=["lifecycle"]`, `lifecycle="EPHEMERAL"`

**Then** **синхронный** `INVALID_ARGUMENT` (unknown/output-only поле в mask — `lifecycle` авторитетно управляется системой, не tenant'ом; тот же класс, что `tagCount`/`fgaObject`)

### Сценарий REG-1-30 (concurrency, lifecycle-CAS): конкурентный promote одного ephemeral-repo → идемпотентно DURABLE

**ID:** REG-1-30

**Given** ephemeral repo `ns-c9k2/pushed/img` без overlay
**And** два конкурентных `UpdateRepository(ns-c9k2, "pushed/img", …)`, оба промоутящих overlay

**When** обе Operation исполняются

**Then** обе сходятся к `lifecycle=DURABLE` **без** double-insert-ошибки: overlay-upsert — одностейтментная запись под PK-backstop (auto-promote INSERT ловит занятый ключ как idempotent-merge, не 23505-fail); финальный `GetRepository.lifecycle.value == "DURABLE"` (integration concurrent-race, `data-integrity.md` п.5)

---

## F8 — Update mutability-классы + by-lane тон + malformed-id + pagination

> `→ module-registry` rule 10/12 · `→ unified §1 conv-11, §5 инв-5`
> **AS-IS:** malformed namespace-id сейчас валидируется как `corevalidate.ResourceID("registry",
> ids.PrefixRegistry, id)` (текст `"invalid registry id '<X>'"`). REG-1 меняет на `("namespace",
> ids.PrefixNamespace, id)` → текст `"invalid namespace id '<X>'"`. by-lane code-split и reason-token —
> `[PHASE-0-GATED]` (unified §9 DT — PROPOSED до Phase-0 governance change-set).

### Сценарий REG-1-31 `[PHASE-0-GATED]` (частично): malformed namespace id → INVALID_ARGUMENT первым стейтментом

**ID:** REG-1-31

**When** `GetNamespace` (`GET /registry/v1/namespaces/NS!!!`) — id не проходит format-check

**Then** **синхронный** `INVALID_ARGUMENT "invalid namespace id 'NS!!!'"` — malformed ловится **первым стейтментом** RPC (до repo-резолва); тон-контракт `"invalid <res> id '<X>'"` — **ungated**
**And** well-formed-но-несуществующий (`GET /registry/v1/namespaces/ns-doesnotexist0`) → `NOT_FOUND "Namespace ns-doesnotexist0 not found"`
**And** `[PHASE-0-GATED]`: конкретный **prefix-литерал** `ns-` (что именно матчит format-check) зависит от B3 hyphen-формы в `corevalidate` (unified §9); тон и first-statement-контракт от гейта не зависят

### Сценарий REG-1-32 (negative): malformed repository name → INVALID_ARGUMENT

**ID:** REG-1-32

**When** `GetRepository(ns-c9k2, repository="Bad Name!")` — repo-имя нарушает OCI-charset

**Then** **синхронный** `INVALID_ARGUMENT "invalid repository name 'Bad Name!'"` первым стейтментом (natural-key format-check до repo-резолва); well-formed-но-нет → `NOT_FOUND "Repository <name> not found"`

### Сценарий REG-1-33: пустой update_mask → full PATCH mutable, immutable silently игнорируются

**ID:** REG-1-33

**Given** namespace `ns-c9k2` (`name="payments"`, `description="old"`)

**When** `UpdateNamespace(ns-c9k2)` с **пустым** `updateMask`, телом `{description:"new", labels:{team:"pay"}, name:"HACK", regionId:"eu-west-9"}`

**Then** `Operation.done && !error`; применены **mutable** поля (`description=="new"`, `labels` обновлены); immutable из тела (`name`, `regionId`) **silently игнорированы** (full-object PATCH-семантика, `api-conventions.md` update_mask discipline); `GetNamespace.name == "payments"`, `regionId` не изменён

### Сценарий REG-1-34 `[PHASE-0-GATED]`: CreateRepository под несуществующим namespace → NOT_FOUND (direct-read lane)

**ID:** REG-1-34

**Given** namespace `ns-absent00000000` **не существует**

**When** `CreateRepository(ns-absent00000000, repository="x/y")`

**Then** `[PHASE-0-GATED]` целевое: `NOT_FOUND "Namespace ns-absent00000000 not found"` (within-service direct-read lane — pre-flight resolve; by-lane split unified §5 инв-5) + detail reason `NAMESPACE_NOT_FOUND` — приземляются **только** после Phase-0 governance change-set
**And** до merge change-set: поведение остаётся **текущим baseline** (AS-IS namespace call-gate → existence-hiding `NOT_FOUND "repository not found"` / `<exempt>` handler-Check). Merge-gate — §Definition of Done

### Сценарий REG-1-35 (edge): INTERNAL никогда не эхает pgx/SQL-текст

**ID:** REG-1-35

**Given** некатегоризированная DB-ошибка на write-пути (симулируется в integration-слое)

**When** мутация (`CreateNamespace`/`CreateRepository`) упирается в неё

**Then** `result.error` — фиксированный opaque-текст (`"internal database error"`), **NotContains** driver/connection-текст (host/port/user/db) и pgx/SQLSTATE-детали; regression-lock проверяет **сообщение** (не только код `INTERNAL`), на обоих листенерах (`security.md` hardening-инвариант 1, `testing.md`)

### Сценарий REG-1-36 (negative): ListNamespaces garbage pageToken → INVALID_ARGUMENT ДО authz-short-circuit

**ID:** REG-1-36

**Given** аутентифицированный принципал (возможно с пустым listauthz-грантом)

**When** `ListNamespaces` (`GET /registry/v1/namespaces?projectId=prj-7h3n&pageToken=%%%not-base64%%%`)

**Then** `INVALID_ARGUMENT` — format-validate `pageToken`/`pageSize`/`projectId` **ДО** listauthz empty-grant short-circuit (иначе garbage-token при пустом гранте утёк бы в `200 {[]}`; `api-conventions.md` List-gotcha, `security.md` hardening-инвариант 7)
**And** `pageSize > 1000` → `INVALID_ARGUMENT` (отвергается, **не** clamp'ится)

---

## Definition of Done

REG-1 считается готовой к merge только при выполнении ВСЕГО чек-листа (`ai-tooling.md` §lifecycle
gate 4-7; `testing.md`):

**Traceability + тесты (1-to-1):**
- [ ] Каждый `REG-1-NN` имеет зелёный **integration-тест** (testcontainers Postgres 16) —
  `Test<Resource>_REG_1_NN` (напр. `TestNamespace_REG_1_01`, `TestRepository_REG_1_23`) — покрывающий
  SQL-сторону, включая concurrent-race на UNIQUE/PK/lifecycle-CAS (REG-1-12/23/30) и ACTIVE-guard (REG-1-25).
- [ ] Каждый `REG-1-NN` (наблюдаемый через api-gateway) имеет зелёный **newman-кейс**
  `tests/newman/cases/*.py` с аннотацией `# verifies REG-1-NN` — ≥1 happy + ≥1 negative per фича;
  трассировка `REG-1-NN ↔ Test<R>_REG_1_NN ↔ cases/*.py`. Newman обёрнут bounded-retry `retry_until_authorized`
  ТОЛЬКО на первый пост-create доступ к своему namespace/repo (owner-tuple EC, `testing.md`); фикстур-хелпер
  проверяет `!op.error` перед извлечением `namespaceId` из `metadata` (phantom-id guard, `testing.md`).
- [ ] TDD-порядок соблюдён: RED (падает по нужной причине) ДО кода, пара RED→GREEN в PR.

**e2e-smoke (real gateway, construction-verified):**
- [ ] `CreateNamespace` → полл Operation → `GetNamespace` возвращает `ns-…` + `placementType=REGIONAL` +
  derived `globalSlug°` (REG-1-01/08/14).
- [ ] field-absence на **реальном** gateway-ответе: `GetNamespace` НЕ содержит `displayName`/top-level
  `visibility`/infra-полей (REG-1-02).
- [ ] `RenameNamespace :rename` меняет `name`, `UpdateNamespace(name=…)` → `INVALID_ARGUMENT` immutable (REG-1-05/06).
- [ ] `CreateRepository` → `lifecycle=DURABLE` survives-empty; auto-promote ephemeral→durable наблюдаем (REG-1-26/28).

**Deliverables редизайна (implementer обязан выполнить — иначе старый путь остаётся):**
- [ ] **AS-IS удаления/изменения:** message `Registry`→`Namespace`; RPC `Get/List/Create/Update/Delete`→
  `GetNamespace/…`(+`RenameNamespace`); REST `/registry/v1/registries`→`/registry/v1/namespaces`; id-prefix
  `reg`→`ns-` (`ids.PrefixNamespace`, corevalidate router `[PHASE-0-GATED]` B3); **удалён name-update-путь**
  (`name` immutable, из UpdateMask known-set исключён); `default_visibility`→`defaultRepositoryVisibility`;
  Repository `registry_id`→`namespace_id`; malformed-id текст `"invalid registry id"`→`"invalid namespace id"`.
- [ ] **Новые поля:** `Namespace.regionId` (peer-validate geo, **обязателен на Create** в REG-1 —
  optional-server-default отложен, F4-intro/O1), `placementType` (always-REGIONAL const), `globalSlug°`
  (derived `<accountSlug>-<name>` при омитнутом входе, либо opt-in bare-global); `Repository.lifecycle`
  output-only enum.
- [ ] **Новая миграция** (`0006_*`; **не** редактировать применённые 0001-0005, ban #5): `registries` +
  `region_id NOT NULL`/`placement_type`/`global_slug` (**`UNIQUE(global_slug)` global**; сохранить partial
  `UNIQUE(project_id,name) WHERE status<>'DELETING'`); rename колонки `repository_configs.registry_id`→
  `namespace_id` (+ переименовать FK/PK/index под новое имя).
- [ ] **Судьба legacy `reg-`-строк (breaking-фаза, как GEO-1):** REG-1 — clean-slate reshape id-prefix
  (`reg`→`ns-`, B3) + FGA-tuple-формы, поэтому **каталог стартует пустым** в этой фазе (нет id-preserving
  backfill `reg-`→`ns-` — id immutable/PK, участвует в FGA owner-tuple и pull-path, in-place re-key
  невыразим). `NOT NULL region_id` / `global_slug` / `placement_type` вводятся без DEFAULT-backfill (пустой
  каталог безопасен). **Операционный data-cutover** legacy-namespace'ов (если prod-данные есть) — отдельный
  deploy-concern, **вне** API-behavior acceptance; format-check/router принимают **только** `ns-` (REG-1-31).
- [ ] **Новое runtime-ребро `registry → geo`** (`RegionService.Get` peer-validate) зафиксировано в
  `polyrepo.md` (runtime-edge) + vault `edges/registry-to-geo-region-validate.md`; ацикличность holds
  (geo leaf, не зовёт registry); per-call deadline на geo-вызове.
- [ ] Rosetta-аннотация (`registry_registry == the Namespace`) — inline у каждого `fgaObject°`-echo
  (godoc + JSON-comment), не только таблицей (unified §8 B7 mitigation-a).
- [ ] proto+regen: `buf lint`/`buf breaking`/`buf generate` зелёные (rename = **intentional breaking** —
  задекларировать в `buf.yaml` breaking-allow или bump proto major, см. open question O2).

**Проектные гейты (финальная верификация):**
- [ ] `go test ./... -race` · `golangci-lint run` · `govulncheck` зелёные. `make -C services/registry
      audit-list-filter` **гейтом пока не является**: рецепт печатает «реализуется вместе с
      `RegistryService.List`» и выходит с нулём (`services/registry/Makefile`) — цель есть, проверки нет.
- [ ] `make -C gateway permission-catalog-check` byte-identical (rename RPC → перегенерировать permission-catalog,
  обе embedded-копии iam-seed↔gateway); newman зелёные (все `REG-1-NN`).

**MERGE-GATE (`[PHASE-0-GATED]` — жёсткие кросс-фазовые блокеры):**
- [ ] **B3 (id-prefix hyphen):** REG-1 НЕ мёржит финальную `ns-`-форму, пока Phase-0 governance change-set
  не зафиксирует hyphen-форму в `corevalidate`/`api-conventions.md` (unified §9 MUST-close-1..3). До merge —
  prefix-литерал не хардкодится; REG-1-01/31 prefix-часть gated.
- [ ] **by-lane тон (conv-11 DT):** REG-1-16 (peer-validate region code) и REG-1-34 (within-service
  create-under-absent-namespace → `NOT_FOUND` direct-read lane) + reason-tokens (`REGION_NOT_FOUND`/
  `NAMESPACE_NOT_FOUND`) приземляются **только** после Phase-0 by-lane code-split + reason-token таблицы в
  `api-conventions.md`. До merge — текущий baseline (existence-hiding/FK-код). Ungated части (malformed→
  `INVALID_ARGUMENT`, dup→`ALREADY_EXISTS`, immutable-текст, INTERNAL-opaque, geo-down→`UNAVAILABLE`,
  ACTIVE-guard `FAILED_PRECONDITION`, field-absence, lifecycle-enum, two-name UNIQUE) — строятся без ожидания.
- [ ] **B1/B7 НЕ гейтят REG-1** (задокументировано): `OciReferrer`-rename (B1) — REG-2 (Referrer в REG-1 не
  трогается); iam scope-alias `registry_namespace:` (B7) — REG-3 (REG-1 эмитит замороженный `registry_registry:`
  + Rosetta). Эти блокеры перечислены для полноты, но не блокируют REG-1 merge.

---

## Открытые вопросы к reviewer (зафиксировать дефолт на review)

1. **O1 — regionId в REG-1 (RESOLVED на r1-review).** `regionId` — core-поле Namespace (REGIONAL placement +
   storage-locality + новое ребро `registry→geo`), включено в REG-1 (F4, REG-1-14..18). Reviewer одобрил
   включение **условно** на закрытии источника server-default региона, которого **нет** ни в AS-IS, ни в
   target (unified §2 iam не несёт default-region на Account/Project). **Разрешение: `regionId` сделан
   ОБЯЗАТЕЛЬНЫМ на Create** (всегда явный + peer-validate geo, REG-1-15/16/17); optional-server-default +
   resolved-echo (module-registry rule 9) **отложен** до определения источника дефолт-региона (кросс-фазовая
   зависимость — см. §Out-of-scope). Reviewer подтверждает разрешение.
2. **O2 — proto breaking-стратегия для rename.** `Registry`→`Namespace` — intentional-breaking (message/RPC/
   REST/id все меняются). Вариант A: breaking-allow в `buf.yaml` (тот же `kacho.cloud.registry.v1`, старые
   типы удаляются). Вариант B: bump proto major/новый package. Legacy `project/kacho-*` не трогается (монорепо
   `project/kacho`). **Дефолт: вариант A** (same package, breaking-allow — redesign-2026 фаза допускает breaking
   в пределах Phase-2). Территория `proto-api-reviewer` при реализации.
3. **O3 — InternalRegistryService rename в REG-1?** AS-IS `internal_registry_service.proto` несёт
   `RegistryStats`/`GetRegistryStats`. `buf breaking` может потребовать rename вместе с public. **Дефолт:
   минимальный message-rename в REG-1 (только чтобы buf прошёл), полный Internal* two-projection redesign →
   REG-4.** Reviewer подтверждает границу.
4. **O4 — Operation-prefix.** module-registry rule 2 называет `epd`; AS-IS использует `ids.PrefixOperationReg`
   (`rop`). **Дефолт: сохранить `rop`** (existing corelib prefix; `epd` в дизайне — иллюстративный, не
   контрактный). Reviewer подтверждает, что prefix — не часть tenant-контракта.

Открытых блокеров, требующих заказчика, нет — док готов к review.

## Changelog — что этот док покрывает

- **F1** rename `Registry`→`Namespace` (message/RPC/REST/id `ns-` `[PHASE-0-GATED]` B3); FGA-тип заморожен
  `registry_registry` + `fgaObject°` echo (по id); field-absence `displayName`/top-level `visibility`/infra
  (REG-1-01..04).
- **F2** `name` immutable (**AS-IS: mutable — удалить path**) + `RenameNamespace :rename`; collision→ALREADY_EXISTS;
  `DeleteNamespace` forward-only `ACTIVE→DELETING` (REG-1-05..07, REG-1-37).
- **F3** two-identity: project-scoped `name` (`UNIQUE(project,name)`) ⟂ derived `globalSlug°` (default
  `<accountSlug>-<name>`, `UNIQUE(global_slug)` global; bare-global opt-in → `ALREADY_EXISTS` + `[PHASE-0-GATED]`
  reason `NAMESPACE_NAME_IS_GLOBAL`); concurrency global-slug-CAS **и** project-name-CAS (REG-1-08..13).
- **F4** `placementType` always-REGIONAL const (carve-out) + `regionId` (**net-new**; **обязателен на Create** —
  optional-server-default отложен, O1; peer-validate geo fail-closed `UNAVAILABLE`; **новое ребро registry→geo**);
  immutable (REG-1-14..18).
- **F5** `default_visibility`→`defaultRepositoryVisibility` rename; сид новых repo; admin-gate→PUBLIC
  `PERMISSION_DENIED` (REG-1-19..20).
- **F6** Repository natural-key rename `registryId→namespaceId`; PK/FK dup→`ALREADY_EXISTS` + concurrency;
  namespaceId immutable; ACTIVE-guard DELETING→`FAILED_PRECONDITION` (EXISTING); `RenameRepository` под новым
  namespaceId + collision (REG-1-21..25, REG-1-38).
- **F7** `lifecycle ∈ {DURABLE,EPHEMERAL}` output-only enum (**net-new**, заменил implicit durable-bool);
  явный Create=DURABLE + опц. вход; auto-promote наблюдаем; lifecycle-CAS concurrency (REG-1-26..30).
- **F8** `[PHASE-0-GATED]` by-lane тон; malformed-id первым стейтментом (текст `"invalid namespace id"`);
  empty-mask full-PATCH; INTERNAL-opaque; pagination-validate до authz (REG-1-31..36).

Покрытие обязательного минимума (task): rename Registry→Namespace ✓ (F1) · name immutable+:rename ✓ (F2) ·
two-name UNIQUE-модель ✓ (F3) · placementType const + regionId ✓ (F4) · defaultRepositoryVisibility ✓ (F5) ·
Repository natural-key namespaceId ✓ (F6) · lifecycle enum + auto-promote ✓ (F7) · concurrent-race
UNIQUE(project,name) **и** UNIQUE(global_slug) **и** PK(namespace,name) **и** lifecycle-CAS ✓
(REG-1-11/12/23/30) · lifecycle-мутации замкнуты (Create→mutate→Delete: REG-1-37 DeleteNamespace,
REG-1-38 RenameRepository) · positive+negative+edge на каждую фичу · `[PHASE-0-GATED]` пометки
(B3 hyphen, by-lane conv-11 включая reason-token REG-1-10/16/34; B1/B7 отмечены как НЕ-гейтящие REG-1).

Что изменилось в r1-review (CHANGES REQUESTED → адресовано): (1) `regionId` сделан обязательным на Create
(источник server-default не существует — optional отложен, F4/O1/Out-of-scope); (2) REG-1-10 reason
`NAMESPACE_NAME_IS_GLOBAL` помечен `[PHASE-0-GATED]` (только reason-в-details; код+текст ungated —
консистентно с GEO-1-05/REG-1-16/34); (3) судьба legacy `reg-`-строк зафиксирована как fresh-catalog
breaking-фаза (убран id-preserving backfill; router принимает только `ns-`); (4) добавлен concurrent-race
на `UNIQUE(project,name)` (REG-1-11); (5) добавлены REG-1-37 `DeleteNamespace` + REG-1-38 `RenameRepository`;
(6) `Repository.pullReference°` явно отложен в REG-3 (F6 AS-IS + Out-of-scope); (7) минорные: xref O2→O4,
ACTIVE-guard помечен EXISTING, probe best-effort clause (REG-1-09).
