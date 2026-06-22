# RBAC rules-model 2026 — под-фаза G (Permission Catalog) — Acceptance (Given-When-Then)

> **Статус:** ✅ **APPROVED** (`acceptance-reviewer`, раунд 3, 2026-06-22) — можно planning + implementation (под-фаза G; A–F не затронуты).
> **Дата:** 2026-06-22
> **Автор:** `acceptance-author`
> **Ревьюер:** `acceptance-reviewer` — раунд 1 ❌ CHANGES REQUESTED (2 blocking + 3 recommended) → раунд 2 ❌ (1 blocking: `iam.condition` hasListEndpoint mis-classified) → **раунд 3 ✅ APPROVED** (14 сценариев, 100% покрытие, ground-truth выверен по `kacho-api-gateway/internal/restmux/mux.go`). Non-blocking: backend `hasListEndpoint`-таблица обязана быть в lockstep с public-mux-регистрацией (parity-тест G-08).
> **Эпик/тикет:** KAC-`<N>` `[EPIC]` «RBAC rules-model 2026», Subtask «sub-phase G — backend-driven permission catalog» (номер проставляется до старта `superpowers:writing-plans`). Затронутые репо: `kacho-proto` / `kacho-iam` / `kacho-api-gateway` / `kacho-ui` / `kacho-deploy`(если нужен mux-config) / `kacho-workspace`(docs).
> **Источник истины (читан целиком):**
> - **Backend ground-truth (нормативно — каталог отражает РОВНО это):** `kacho-iam/internal/authzmap/fga_types.go` → `objectTypes` (closed `(module,resource)→FGA object_type`) + `TypeHasVerbRelations(fgaType)` (verb-bearing leaf vs tier-only ancestor) + `objectTypes`-комментарий «extending requires lockstep with `fga_model.fga`»; `kacho-iam/internal/domain/rule_verbs.go` → `ClosedVerbs = {get,list,create,update,delete}` + verb-`*` разворот (O-3). Компилятор правил fail-closed-SKIP'ает любой `(module,resource)` не из `objectTypes` (грант = no-op).
> - **Текущий UI-hardcode (заменяется):** `kacho-ui/src/api/permissionCatalog.ts` (`PERMISSION_CATALOG` константа + `MODULE_OPTIONS`/`CLOSED_VERBS`/`VERB_OPTIONS` + `resourcesForModules`/`isKnownModule` + drift-guard `permissionCatalog.test.ts`). Шапка файла сама фиксирует follow-up «backend-driven catalog (public catalog-RPC), PRO-Robotech/kacho-ui#105» — эта под-фаза его и закрывает.
> - **Существующий internal-stub (НЕ переиспользуется как публичный каталог):** `kacho-iam/internal/apps/kacho/api/internal_iam/list_permissions.go` → `InternalIAMService.ListPermissions` игнорирует `subject_id`/`resource` и возвращает весь `permission_catalog.json` (`module.resource.verb`-строки RPC-enforcement, не rule-токены) — false-assurance stub на :9091. Фиксится/удаляется отдельно (вне scope G); НОВЫЙ catalog-RPC — честное **публичное** чтение grantable-таксономии БЕЗ subject.
> - **Эпик-acceptance (формат/нумерация/тон):** `docs/specs/rbac-rules-model-2026-acceptance.md` (под-фазы A–F, §2.2 wildcard-политика R-3, §2.4 feed-registry O-4, §2.5 стабильные тексты, §3 глоссарий), `docs/specs/rbac-rules-model-2026-design.md`.
> - **Образцы формата:** под-фазы A/D/E/F в эпик-acceptance; `sub-phase-vpc-redesign-kac239-acceptance.md`.

---

## Обзор

Под-фаза G делает выпадающие списки редактора правил роли (`modules → resources`, набор verbs, политику wildcard) **backend-driven** вместо захардкоженной клиентской константы. Сегодня UI несёт ручную копию backend-таксономии (`permissionCatalog.ts`) с drift-guard-тестом — каждый новый grantable `(module,resource)` требует ручного sync в трёх местах (backend `objectTypes` + `fga_model.fga` + UI-константа + её drift-test). G вводит **один публичный sync read-RPC**, отдающий честную grantable-таксономию (модули → ресурсы с per-`(module,resource)` флагами, важными редактору: поддерживает ли тип verb-relations или это tier-only ancestor, разрешён ли wildcard) + закрытый набор verbs (`ClosedVerbs`); UI грузит опции из живого RPC (react-query, loading/error/empty-состояния), а захардкоженный каталог и drift-test ретайрятся. Дополнительно: arm «По именам» (`resourceNames`) становится picker'ом по **реальным инстансам ресурса** (Select из видимых caller'у объектов с display-name, value=opaque id) вместо ручного ввода id, с fallback в free-text для типов без per-object List endpoint.

Каталог — **не** инфраструктурно-чувствительные данные (`security.md` §infra-sensitive): это grantable-token-метаданные модели авторизации (имена модулей/ресурсов/verbs + политические флаги), не placement/underlay/wiring/числовые инфра-id. Поэтому RPC живёт на **публичном** листенере с authenticated-floor (`system_viewer`-tier) — любой аутентифицированный principal вправе читать платформенную метаданность; анонимный fail-closed.

Документ описывает **только наблюдаемое внешнее поведение API/UI** (gRPC-коды, REST-формы, экраны, состояния), не реализацию. Сценарии трассируются в имена integration/newman/vitest-тестов через ID `G-<NN>`.

> **Декомпозиция.** Под-фаза G — самостоятельный end-to-end deliverable со своим DoD, в кросс-репо порядке `proto → iam → gateway → ui → deploy → docs` (`polyrepo.md`). G «зелёная» только при RED→GREEN: iam integration + newman (catalog-parity и authz) и ui vitest (dropdown render + names-picker) в соответствующих PR (ban #12).

---

## 0. Фиксированные решения под-фазы G (НЕ переоткрывать; ревьюер подтверждает scope)

> Решения зафиксированы здесь как контрактные предпосылки сценариев (опираются на уже-принятые эпик-решения R-3/O-3/O-4/§2.4). Ревьюер проверяет покрытие, не переоткрывает выбор.

| ID | Решение | Сценарии |
|---|---|---|
| **G-D1** | **Форма контракта — выделенный `PermissionCatalogService.ListPermissionCatalog`** (НЕ расширение `RoleService`, НЕ переиспользование internal `ListPermissions`-stub). Обоснование: каталог — grantable-token-метаданность модели, не ресурс роли (нет owner/scope/lifecycle, не CRUD); честное публичное чтение БЕЗ subject ≠ internal `InternalIAMService.ListPermissions` (тот на :9091, агрегирует/игнорирует subject, оперирует `module.resource.verb`-permission-строками RPC-enforcement, а не rule-токенами `(module,resource)`). Отдельный сервис держит публичную rule-token-таксономию изолированной и единообразной (flat-response, sync read). | G-01, G-D-секция |
| **G-D2** | **Sync read, НЕ Operation** (`api-conventions.md`: read — sync). Каталог immutable-в-рантайме (закрытая `objectTypes`-таблица + `ClosedVerbs`), кэшируется UI через react-query; мутаций нет. Расширяется только новым релизом backend (новый `(module,resource)` в `objectTypes` lockstep с `fga_model.fga`) — не RPC-мутацией. | G-01, G-09 |
| **G-D3** | **Публичный листенер, authenticated-floor (`system_viewer`-tier).** Каталог несёт grantable-token-метаданность — НЕ infra/placement (`security.md` §infra-sensitive подтверждён: нет host/underlay/wiring/numeric-infra-id). Каждый аутентифицированный principal вправе читать (платформенная метаданность, общая для всех тенантов). Анонимный → fail-closed. Каталог **не** scope-фильтруется per-tenant (одна таксономия для всей платформы) — в отличие от `Role.List`/`List<Resource>` (per-object D-фильтр). | G-02, G-03 |
| **G-D4** | **Каталог отражает РОВНО backend grantable-set** — `objectTypes` (ключи `module.resource`) + per-тип `TypeHasVerbRelations` + verb-набор `ClosedVerbs` + verb-`*` (R-3/O-3, bounded). Никакой токен вне `objectTypes` не появляется в каталоге (он был бы fail-closed-SKIP no-op в компиляторе). `iam.account`/`iam.project` ВКЛЮЧЕНЫ (в `objectTypes`), но помечены `tier_only` (`TypeHasVerbRelations=false`) — ARM_ANCHOR/ARM_LABELS на них fail-closed-SKIP, доступ выражается через ARM_NAMES/tier-роли. Не-в-`objectTypes` типы (`geo.region`/`geo.zone`/`compute.diskType`) в каталоге **отсутствуют**. | G-04, G-05, G-06 |
| **G-D5** | **Wildcard-политика в каталоге = паритет с R-3/§2.2.** `verb-*` помечен grantable-в-custom (bounded «все verbs типа», O-3); `module-*`/`resource-*` помечены `system-only` (в custom-роли → `INVALID_ARGUMENT`, §2.5). UI рендерит verb-`*` доступным, module/resource-`*` disabled для custom (паритет с F-22). | G-07 |
| **G-D6** | **resourceNames-picker = реальные инстансы через per-object filtered `List`** (под-фаза D, R-10): для `(module,resource)` с живым **публичным** per-object-filtered List endpoint (на external-листенере) UI рендерит Select видимых caller'у инстансов (display-name + value=opaque id); для типов без публичного List endpoint (или чтобы запинить невидимый id) — free-text fallback. Каталог несёт флаг `hasListEndpoint` (имя поля зафиксировано — не «или эквивалент»), чтобы UI знал, рендерить picker или free-text. | G-08, G-08b, G-11, G-12, G-13 |
| **G-D7** | **Форма контракта — выделенный `PermissionCatalogService.ListPermissionCatalog`** (G-Q1 закрыт): НЕ метод на `RoleService`, НЕ переиспользование internal `ListPermissions`-stub. Каталог не ресурс роли (нет owner/scope/CRUD); метод на `RoleService` смешал бы role-CRUD с платформенной метаданностью. Дублирует/уточняет G-D1 — здесь зафиксировано как итог открытого вопроса. | G-01 |
| **G-D8** | **`hasListEndpoint` — флаг В КАТАЛОГЕ (backend — единый источник истины)** (G-Q2 закрыт): UI НЕ держит вторую копию «у каких типов есть публичный List» (иначе тот же ручной-sync-долг, что у самого каталога). Источник `hasListEndpoint` — закрытая backend-таблица «(module,resource) → есть ли публичный per-object filtered List на external-листенере»; Internal-only List (:9091) НЕ считается публичным → `hasListEndpoint=false`. | G-08, G-08b |
| **G-D9** | **Каталог НЕ несёт compiled `permissions[]` / FGA-relation-имён** (G-Q3 закрыт): только tenant-facing grantable-токены (`(module,resource)` + verbs) + редакторские/политические флаги. Compiled-форма (`module.resource.verb`-permission-строки), FGA-relation-имена (`v_*`/`scope_grant`/`sg_*`), внутренняя машинерия модели — НЕ на публичной поверхности (`security.md`, паритет R-7/§infra-sensitive). | §2.1, G-01 |
| **G-D10** | **Internal `InternalIAMService.ListPermissions`-stub — ВНЕ scope G** (G-Q4 закрыт): фиксится/удаляется отдельным тикетом; НОВЫЙ публичный каталог его НЕ замещает (разные таксономии: rule-токены `(module,resource)` vs `module.resource.verb`-permission-строки RPC-enforcement; разные листенеры :9091 vs public). G лишь не зависит от stub'а и не дублирует его на external. | §3, §6 |

> **Hand-off-флаг (gate).** `KAC-<N>`/`[EPIC]`-placeholder (шапка) ОБЯЗАН быть заменён реальным номером Subtask «sub-phase G» до `superpowers:writing-plans` / старта кода (`git-youtrack.md`: тикет + ветка + KAC-trail). Это единственный незакрытый organizational-блокер; технических открытых вопросов в сценариях нет (G-Q1..G-Q4 закрыты → G-D7..G-D10).

---

## 1. Связь с регламентом (нормативно; в тело не дублируется)

| Регламент | Где соблюдается |
|---|---|
| `api-conventions.md` — read **sync** (`ListPermissionCatalog` — sync, НЕ Operation); Watch не существует (UI кэширует через react-query, не поллит) | G-01, G-D2 |
| `api-conventions.md` — REST `/<service>/v1/<resource-or-collection>`, JSON camelCase (`modules`, `resources`, `verbs`, `closedVerbs`, `hasVerbRelations`, `wildcardPolicy`, `hasListEndpoint`) | G-01, §smoke |
| `api-conventions.md` — error-format: анонимный fail-closed → `UNAUTHENTICATED`; стабильные тексты (часть контракта) | G-02, §2.x |
| `security.md` §Internal-vs-external (ban #6) — каталог **публичен** (tenant-UI, grantable-token-метаданность); internal `ListPermissions`-stub остаётся на :9091 и НЕ замещается публичным (разные таксономии/семантика) | G-D1, G-D3 |
| `security.md` §Инфра-чувствительные данные — каталог НЕ несёт placement/underlay/wiring/numeric-infra-id; только имена модулей/ресурсов/verbs + политические флаги → публичная поверхность допустима | G-D3 |
| `security.md` §AuthN+AuthZ ВЕЗДЕ — per-RPC authz-gate; authenticated-floor (`system_viewer`-tier); анонимный fail-closed | G-02, G-03 |
| `security.md` §публичный List фильтрует (listauthz) — **НЕ применяется к каталогу** (G-D3: одна платформенная таксономия, не per-tenant set); применяется к **resourceNames-picker'у** (он читает реальные инстансы через per-object filtered List, D-фильтр) | G-D3, G-11 |
| `data-integrity.md` §cross-domain — каталог-RPC чисто-read из in-process backend-таблицы (`objectTypes`), **НЕ вводит нового cross-service ребра**; resourceNames-picker UI читает инстансы через **существующие** публичные `List<Resource>` (per-domain), не новое iam→consumer ребро | §6 |
| `00-kacho-core.md` ban #1 (APPROVED перед кодом), #2 (без упоминания чужих облаков), #12 (TDD RED→GREEN integration+newman/vitest в том же PR) | весь документ; DoD |
| `polyrepo.md` §порядок merge | DoD: proto → iam → api-gateway → ui → deploy → docs |
| `architecture.md` — каталог-проекция из `domain`/`authzmap` (закрытая таблица), тонкий handler; UI — react-query hook + form-schema | DoD |

---

## 2. Нормативные определения (источник истины для сценариев)

### 2.1. Форма ответа каталога (нормативно)

`ListPermissionCatalogResponse` (flat, sync) несёт:
- `modules[]` — упорядоченный список grantable-модулей (1-й сегмент токена): производный из ключей `objectTypes` (`iam`, `vpc`, `compute`, `loadbalancer`, …). Порядок детерминирован.
- для каждого модуля — `resources[]`, каждый ресурс несёт:
  - `resource` — 2-й сегмент токена **как в backend `objectTypes`** (camelCase singular `securityGroup`/`routeTable`/`networkInterface`/`serviceAccount`/`accessBinding`, либо pluralized для loadbalancer `networkLoadBalancers`/`targetGroups`/`listeners` — токен идёт на провод как есть, не переименовывается);
  - `hasVerbRelations` (bool) — `true` для verb-bearing leaf-типов; `false` для tier-only ancestors (`iam.account`/`iam.project`). Зеркало `authzmap.TypeHasVerbRelations(objectType)`.
  - `hasListEndpoint` (bool, имя поля зафиксировано) — `true` если у типа есть **публичный** per-object filtered `List` **на external-листенере** (под-фаза D) → resourceNames-picker рендерит Select инстансов; `false` (нет публичного List, или List только Internal-only на :9091) → free-text fallback (G-D6/G-D8). Источник — закрытая backend-таблица «(module,resource) → публичный List?» (не угадывается UI).
- `closedVerbs[]` — `["get","list","create","update","delete"]` (зеркало `domain.ClosedVerbs`, порядок фиксирован).
- `wildcardPolicy` — политические флаги (G-D5/§2.2):
  - `verbWildcardAllowedInCustom = true` (verb-`*` bounded, R-3/O-3);
  - `moduleWildcardSystemOnly = true`, `resourceWildcardSystemOnly = true` (module/resource-`*` system-only).

> **Каталог НЕ несёт** `permissions[]`-compiled-форму, FGA-relation-имена (`v_*`/`scope_grant`/`sg_*`), внутреннюю машинерию модели — только tenant-facing grantable-токены + редакторские флаги (паритет с `security.md` §infra-sensitive + §публичный ответ Role несёт только `rules[]`).

### 2.2. Каталог = backend grantable-set (G-D4, нормативно)

| Источник backend | Проекция в каталог |
|---|---|
| `authzmap.objectTypes` (ключи `module.resource`) | `modules[]` × `resources[].resource` — РОВНО эти пары, не больше |
| `authzmap.TypeHasVerbRelations(fgaType)` | `resources[].hasVerbRelations` |
| `domain.ClosedVerbs` | `closedVerbs[]` |
| verb-`*` (R-3/O-3) | `wildcardPolicy.verbWildcardAllowedInCustom = true` |
| module/resource-`*` (§2.2 system-only) | `wildcardPolicy.{module,resource}WildcardSystemOnly = true` |

Тип НЕ в `objectTypes` → **отсутствует** в каталоге (был бы no-op). Добавление `(module,resource)` в backend `objectTypes` (lockstep с `fga_model.fga`) → автоматически появляется в каталоге без правки UI (G-09).

### 2.3. Стабильные тексты ошибок (часть контракта — `api-conventions.md`)

| Ситуация | Код | Текст |
|---|---|---|
| анонимный (нет identity) запрос каталога | `UNAUTHENTICATED` | (fail-closed; стандартный auth-interceptor-текст, не leak) |
| backend/IAM недоступен для UI (transport) | n/a (UI error-state) | UI рендерит error-state, НЕ крэшит (G-10) |

> Каталог-RPC не принимает payload (нет id/filter в v1) → нет `INVALID_ARGUMENT`-путей по входу в v1. resourceNames-picker — это UI-консумер публичных `List<Resource>`, его ошибки покрываются контрактом соответствующего List (D-46 garbage page_token → `INVALID_ARGUMENT`).

---

## 3. Глоссарий: ground-truth и дельта

| Сущность | Ground-truth | Дельта под-фазы G |
|---|---|---|
| `authzmap.objectTypes` | СУЩЕСТВУЕТ — closed `(module.resource)→FGA object_type` | **источник** каталога (read-only проекция; не меняется) |
| `authzmap.TypeHasVerbRelations` | СУЩЕСТВУЕТ — verb-bearing leaf vs tier-only ancestor | проецируется в `hasVerbRelations` |
| `domain.ClosedVerbs` | СУЩЕСТВУЕТ — `{get,list,create,update,delete}` | проецируется в `closedVerbs[]` |
| `PermissionCatalogService.ListPermissionCatalog` | **НЕ существует** | **НОВЫЙ** sync public read-RPC (G-D1) |
| `InternalIAMService.ListPermissions` (stub) | СУЩЕСТВУЕТ — :9091, игнорит subject, `module.resource.verb`-permission-строки | **НЕ затрагивается G** (фиксится/удаляется отдельно); НЕ замещается публичным каталогом (разные таксономии) |
| `kacho-ui/src/api/permissionCatalog.ts` | СУЩЕСТВУЕТ — hardcoded `PERMISSION_CATALOG` + drift-test | **РЕТАЙРИТСЯ** — заменяется react-query hook'ом на каталог-RPC; drift-test удаляется (G-13) |
| `RulesEditor` resourceNames arm | СУЩЕСТВУЕТ — hand-typed id (free-text) | **picker реальных инстансов** через per-object filtered List (G-D6/G-11/G-12) |

---

## 3a. Трассировка сценарий → тест (G-NN ↔ integration / newman / vitest)

> Имена тестов — целевые (integration-tester создаёт RED по ним; ban #12: тесты в том же PR). Слой выбран по природе сценария: контракт/parity/authz каталога → `kacho-iam` integration + api-gateway newman; UI-поведение → `kacho-ui` vitest. SECURITY-якоря (G-02, G-08b) — обязательны.

| Сценарий | Слой | Целевое имя теста / кейса |
|---|---|---|
| **G-01** Happy (sync, без Operation) | iam integration + newman | `TestListPermissionCatalog_ReturnsGrantableTaxonomy` (iam) · newman `CONF-G-01-catalog-happy` (200, modules/resources/closedVerbs/wildcardPolicy, camelCase) |
| **G-02** анонимный fail-closed | newman (authz) | newman `NEG-G-02-catalog-anonymous-unauthenticated` (401/`UNAUTHENTICATED`, no leak) |
| **G-03** authenticated-floor, не per-tenant | iam integration + newman | `TestListPermissionCatalog_AuthenticatedFloor_NoTenantScope` (iam) · newman `CONF-G-03-catalog-member-vs-admin-identical` |
| **G-04** каталог == `objectTypes` (set-equality) | iam integration | `TestListPermissionCatalog_SetEqualsObjectTypes` (двусторонний set-equality `objectTypes`↔ответ) + `TestListPermissionCatalog_ClosedVerbsEqualDomainClosedVerbs` |
| **G-05** tier-only `hasVerbRelations=false` | iam integration | `TestListPermissionCatalog_HasVerbRelations_MirrorsTypeHasVerbRelations` (parity по всему `objectTypes`; `iam.account`/`iam.project`→false) |
| **G-06** типы вне `objectTypes` отсутствуют | iam integration | `TestListPermissionCatalog_ExcludesNonGrantableTypes` (`geo.*`/`compute.diskType` отсутствуют; модуль `geo` нет в `modules[]`) |
| **G-07** wildcard-политика == R-3/§2.2 | iam integration + newman | `TestListPermissionCatalog_WildcardPolicyParity` (iam) · newman `CONF-G-07-wildcard-flags` + `NEG-G-07-custom-module-wildcard-invalid` (`INVALID_ARGUMENT`, согласован с A-05) |
| **G-08** `hasListEndpoint` присутствует/детерминирован | iam integration | `TestListPermissionCatalog_HasListEndpoint_FromClosedTable` (`vpc.subnet`/`compute.instance`/`iam.role`→true; `iam.condition`→false — RPC есть в proto, но не зарегистрирован на external gateway) |
| **G-08b** `vpc.addressPool` grantable+verb-bearing но `hasListEndpoint=false` (SECURITY) | iam integration + vitest | `TestListPermissionCatalog_AddressPool_GrantableButInternalOnlyList` (iam: `vpc.addressPool` ∈ каталог, `hasVerbRelations==true && hasListEndpoint==false`) · vitest `RulesEditor.names-arm renders free-text (never Select) for addressPool` |
| **G-09** новый `(module,resource)` без UI-редеплоя | iam integration | `TestListPermissionCatalog_NewObjectType_AppearsWithoutUIChange` (добавить пару в `objectTypes`-фикстуру → присутствует в ответе, UI-код не правится) |
| **G-10** UI backend-недоступен → error-state | vitest | `RulesEditor shows loading skeleton while catalog pending` · `RulesEditor shows error-state with retry on catalog query reject` · `RulesEditor renders options on catalog success` |
| **G-11** dropdown'ы из живого RPC | vitest | `RulesEditor module/resource/verb dropdowns render from catalog RPC (not bundled constant)` · `resource dropdown cascades module→resources with dedup` |
| **G-12** resourceNames picker инстансов (`hasListEndpoint=true`) | vitest | `RulesEditor names-arm renders instance Select for subnet (display-name, value=opaque id)` · `selecting instance writes opaque id into resourceNames` |
| **G-13** free-text fallback + ретайр hardcoded-каталога | vitest + grep-гейт | `RulesEditor names-arm renders free-text when hasListEndpoint=false` · `RulesEditor accepts arbitrary id when hasListEndpoint=true` · grep/lint-гейт `no import of removed PERMISSION_CATALOG constant in RulesEditor` (+ удаление `permissionCatalog.test.ts`) |

---

# ПОД-ФАЗА G — backend-driven permission catalog + resourceNames-picker

**Deliverable:** новый `PermissionCatalogService.ListPermissionCatalog` (proto, sync public read) → backend-проекция `objectTypes`/`TypeHasVerbRelations`/`ClosedVerbs`/wildcard-политики → api-gateway public mux → UI грузит dropdown-опции из живого RPC (react-query, loading/error/empty), drift-test + hardcoded каталог ретайрятся → resourceNames arm = picker реальных инстансов.
**Порядок:** `kacho-proto` (новый сервис/сообщения, sync read, buf clean) → `kacho-iam` (handler + проекция из `authzmap`) → `kacho-api-gateway` (public mux) → `kacho-ui` (react-query hook + RulesEditor + names-picker; ретайр константы/drift-test) → `kacho-deploy`(если нужен mux-config) → docs.

## Сценарий G-01: Happy — ListPermissionCatalog отдаёт grantable-таксономию (sync, без Operation)

**ID:** G-01

**Given** аутентифицированный caller (любой `system_viewer`-floor principal)

**When** клиент вызывает `PermissionCatalogService.ListPermissionCatalog` (`GET /iam/v1/permissionCatalog`) без payload

**Then** RPC возвращает ответ **синхронно** (НЕ `Operation`, ban #9 не применим к read — `api-conventions.md`)
**And** ответ несёт `modules[]` (≥ `iam`,`vpc`,`compute`,`loadbalancer`), для каждого `resources[]` с полями `resource`/`hasVerbRelations`/`hasListEndpoint`
**And** `closedVerbs == ["get","list","create","update","delete"]` (порядок фиксирован, зеркало `domain.ClosedVerbs`)
**And** `wildcardPolicy` несёт `verbWildcardAllowedInCustom=true`, `moduleWildcardSystemOnly=true`, `resourceWildcardSystemOnly=true`
**And** REST-форма camelCase; повторный вызов идемпотентен (тот же набор — каталог immutable-в-рантайме)

## Сценарий G-02: AuthZ — анонимный запрос fail-closed

**ID:** G-02

**Given** анонимный (без валидной identity) запрос

**When** `ListPermissionCatalog`

**Then** отклоняется → `UNAUTHENTICATED` (fail-closed, `security.md` §AuthN+AuthZ ВЕЗДЕ); каталог НЕ отдаётся анонимно
**And** никакой grantable-token-метаданности не leak'ается до аутентификации

## Сценарий G-03: AuthZ — authenticated-floor, любой `system_viewer`-principal читает (не per-tenant scope)

**ID:** G-03

**Given** (a) аутентифицированный tenant-principal БЕЗ admin-роли (только базовый member); (b) аутентифицированный admin

**When** оба вызывают `ListPermissionCatalog`

**Then** оба получают **идентичный** полный каталог (платформенная метаданность, authenticated-floor `system_viewer`-tier — G-D3)
**And** каталог **не** scope-фильтруется per-tenant (в отличие от `Role.List`/`List<Resource>` D-фильтра): одна таксономия для всей платформы; tenant без ролей всё равно видит полный grantable-set (он нужен, чтобы автор правил роли видел доступные токены)

## Сценарий G-04: Каталог == backend `objectTypes` (parity — ни больше, ни меньше)

**ID:** G-04  ·  *(G-D4, CRITICAL — traceability к ground-truth)*

**Given** backend `authzmap.objectTypes` (closed-таблица)

**When** клиент вызывает `ListPermissionCatalog`

**Then** множество пар `(module, resource)` в ответе **== ровно** множество ключей `objectTypes` (`module.resource`), без добавлений и без пропусков
**And** integration-тест parity (в `kacho-iam`): итерирует `authzmap.objectTypes` и assert'ит, что каждая пара присутствует в ответе каталога И каждая пара ответа есть в `objectTypes` (двусторонний set-equality) — drift backend↔каталог ловится тестом, не ручным sync
**And** `closedVerbs` ответа **== `domain.ClosedVerbs`** (set+order); тот же parity-тест assert'ит

## Сценарий G-05: tier-only ancestors помечены `hasVerbRelations=false`

**ID:** G-05  ·  *(G-D4)*

**Given** backend: `iam.account`/`iam.project` — tier-only ancestors (`TypeHasVerbRelations=false`); прочие (`compute.instance`, `vpc.subnet`, `iam.role`, …) — verb-bearing (`true`)

**When** `ListPermissionCatalog`

**Then** `iam.account` и `iam.project` присутствуют в каталоге (они в `objectTypes`) с `hasVerbRelations=false`
**And** `compute.instance`/`vpc.subnet`/`iam.role`/`loadbalancer.networkLoadBalancers` (и все verb-bearing) несут `hasVerbRelations=true`
**And** значение каждого `hasVerbRelations` **== `authzmap.TypeHasVerbRelations(objectType)`** (parity-тест по всему `objectTypes`)

## Сценарий G-06: типы вне `objectTypes` отсутствуют в каталоге

**ID:** G-06  ·  *(G-D4)*

**Given** `geo.region`/`geo.zone`/`compute.diskType` — НЕ в `objectTypes` (read-only/leaf, не grantable per-object → rule был бы fail-closed-SKIP no-op)

**When** `ListPermissionCatalog`

**Then** ни `geo.*`, ни `compute.diskType` **не появляются** в каталоге (каталог отражает только grantable-set — G-D4)
**And** контр-проверка: модуль `geo` отсутствует в `modules[]` (нет ни одной grantable geo-пары в `objectTypes`)

## Сценарий G-07: wildcard-политика в каталоге = паритет R-3/§2.2

**ID:** G-07  ·  *(G-D5)*

**Given** эпик-политика (§2.2/R-3): verb-`*` допустим в custom (bounded), module/resource-`*` system-only

**When** `ListPermissionCatalog`

**Then** `wildcardPolicy.verbWildcardAllowedInCustom == true` (UI рендерит verb-`*` опцию доступной для custom)
**And** `wildcardPolicy.moduleWildcardSystemOnly == true` И `resourceWildcardSystemOnly == true` (UI рендерит module/resource-`*` disabled для custom)
**And** паритет с реальным энфорсментом: попытка `RoleService.Create` custom-роли с `modules:["*"]` → `INVALID_ARGUMENT "Illegal argument modules (wildcard '*' is system-only)"` (§2.5, A-05) — каталог-флаг и backend-валидация согласованы (один источник политики)

## Сценарий G-08: каталог несёт `hasListEndpoint` для resourceNames-picker

**ID:** G-08  ·  *(G-D6/G-D8)*

**Given** часть типов имеет **публичный** per-object filtered `List`, **зарегистрированный на external-листенере api-gateway** (`vpc.subnet`, `compute.instance`, `vpc.network`, `iam.role` — `RegisterRoleServiceHandlerFromEndpoint` в public REST mux + allowlist); часть — публичного per-object List на external НЕ имеет. **`hasListEndpoint` определяется регистрацией маршрута на external-листенере gateway, а НЕ наличием RPC в proto:** напр. `iam.condition` — `ConditionsService.List` существует в proto (`GET /iam/v1/conditions`), но НЕ зарегистрирован на external mux/allowlist gateway (под-фаза D *фильтрует* существующие публичные List per-object — она НЕ обязуется *регистрировать* новые публичные маршруты), → `hasListEndpoint=false` (второй false-case наряду с `vpc.addressPool`, G-08b)

**When** `ListPermissionCatalog`

**Then** каждый `resources[]`-элемент несёт `hasListEndpoint` (bool): `true` для типов с публичным per-object filtered List на external-листенере, `false` иначе
**And** значение детерминировано из закрытой backend-таблицы «(module,resource) → есть ли публичный per-object filtered List на external?» (G-D8), не угадывается UI
**And** для tier-only ancestors (`iam.account`/`iam.project`, G-05) `hasListEndpoint` отражает наличие соответствующего публичного List (`account`/`project` List существуют → `true`), но picker для них применяется только в ARM_NAMES-арме (G-D4)

## Сценарий G-08b: `hasListEndpoint=false` для grantable-типа с ТОЛЬКО Internal-only List (`vpc.addressPool` — каноничный false-case)

**ID:** G-08b  ·  *(G-D6/G-D8, SECURITY — Internal-vs-public boundary)*

**Given** `vpc.addressPool` ∈ `objectTypes` (grantable, verb-bearing: `authzmap.objectTypes["vpc.addressPool"]="vpc_address_pool"`, `TypeHasVerbRelations("vpc_address_pool")=true`) → пара ПОЯВИТСЯ в публичном каталоге с `hasVerbRelations=true`
**And** при этом единственный `List` для AddressPool — `InternalAddressPoolService.List` на **cluster-internal :9091** (`REST GET /vpc/v1/addressPools`, Internal mux), AddressPool — admin-Internal-only ресурс (`security.md` §Internal admin-resources; kacho-ui ban #8): **публичного** per-object filtered List на external-листенере НЕТ

**When** `ListPermissionCatalog`

**Then** `vpc.addressPool` присутствует в каталоге (в `modules[]`→`vpc`, `resources[]`, `hasVerbRelations=true`) — он grantable и verb-bearing
**And** его `hasListEndpoint == false` (List существует **только** на Internal-листенере :9091, не на external; G-D8: Internal-only List НЕ считается публичным)
**And** **SECURITY-инвариант (нормативно для implementer + backend `hasListEndpoint`-таблицы):** при `hasListEndpoint=false` resourceNames-picker рендерит **free-text** input (hand-typed opaque id) и **НИКОГДА** Select, бэкенящийся несуществующим публичным List — UI не должен вызывать внешний List addressPools (его на external нет; вызов был бы 404/route-not-allowed, либо засветил бы admin-поверхность). Это явная и однозначная false-ветка: grantable-в-каталоге ≠ есть-публичный-List
**And** integration/parity-тест assert'ит конкретно: `catalog.vpc.addressPool.hasVerbRelations==true && catalog.vpc.addressPool.hasListEndpoint==false` (ground-truth-якорь — не выводится из других флагов)

## Сценарий G-09: новый backend `(module,resource)` появляется в каталоге БЕЗ UI-редеплоя

**ID:** G-09  ·  *(G-D2/G-D4, CRITICAL — мотивация фичи)*

**Given** UI развёрнут и грузит каталог из RPC (hardcoded-константа удалена, G-13)

**When** backend добавляет новый grantable `(module,resource)` в `objectTypes` (lockstep с `fga_model.fga`) и редеплоится (UI **не** пересобирается)

**Then** следующий `ListPermissionCatalog` от UI содержит новую пару; dropdown ресурсов соответствующего модуля показывает новый ресурс **без** UI-редеплоя (live-driven — закрывает ручной-sync-долг трёх мест)
**And** integration-тест демонстрирует: добавление записи в `objectTypes`-фикстуру → ответ каталога включает её (без правки UI-кода/теста)

## Сценарий G-10: UI — backend недоступен → error-state, не крэш

**ID:** G-10  ·  *(UI negative)*

**Given** UI открывает RulesEditor; каталог-RPC недоступен (transport error / 5xx / timeout)

**When** react-query-запрос каталога фейлится

**Then** RulesEditor рендерит **error-state** (сообщение + retry-кнопка), НЕ крэшит и НЕ рендерит пустые молчаливые dropdown'ы как «нет ресурсов»
**And** module/resource-dropdown'ы disabled пока каталог не загружен (loading-state — spinner/skeleton); пустой ответ (теоретически) → empty-state «каталог недоступен», не silent
**And** vitest: (a) loading-state рендерится во время pending; (b) error-state рендерится на rejected query (retry доступен); (c) success-state рендерит опции из ответа

## Сценарий G-11: UI — RulesEditor dropdown'ы грузятся из живого RPC

**ID:** G-11  ·  *(UI happy — основное требование заказчика)*

**Given** каталог-RPC отдаёт grantable-таксономию (G-01); react-query-кэш заполнен

**When** пользователь открывает RulesEditor (Role-create / grant-форма) и выбирает модуль

**Then** module-dropdown показывает `modules[]` из ответа RPC (НЕ из bundled-константы)
**And** при выборе модуля resource-dropdown каскадно показывает `resources[]` этого модуля из ответа (cascade module→resources, дедуп при нескольких модулях — паритет с прежним `resourcesForModules`)
**And** verb-dropdown показывает `closedVerbs` + verb-`*` опцию (verb-`*` доступна для custom — `wildcardPolicy.verbWildcardAllowedInCustom`, G-07); module/resource-`*` disabled для custom
**And** vitest рендерит RulesEditor с mock'нутым каталог-ответом и assert'ит опции (module/resource/verb) против ответа, НЕ против константы

## Сценарий G-12: UI — resourceNames arm = picker реальных инстансов (`hasListEndpoint=true`)

**ID:** G-12  ·  *(UI happy — resourceNames-picker, G-D6)*

**Given** правило в режиме `arm=names`, выбран `(module,resource)` с `hasListEndpoint=true` (напр. `vpc.subnet`)

**When** пользователь раскрывает resourceNames-picker

**Then** UI рендерит **Select реальных инстансов** ресурса, видимых caller'у (через публичный per-object filtered `List<Resource>` соответствующего домена, под-фаза D): отображается **display-name**, value = **opaque id**
**And** список — только инстансы, которые caller имеет право видеть (read==enforce D-фильтр; чужие/невидимые объекты не leak'аются в picker)
**And** выбранные элементы кладут в `resourceNames[]` именно **opaque id** (value), не display-name (токен идёт на провод как id — паритет с C-24 материализацией по id)
**And** vitest: picker рендерит инстансы из mock'нутого List-ответа; выбор кладёт id в `resourceNames`

## Сценарий G-13: UI — free-text fallback (`hasListEndpoint=false` или pin-невидимого-id) + ретайр hardcoded-каталога

**ID:** G-13  ·  *(UI edge + cleanup, G-D6)*

**Given** (a) `(module,resource)` с `hasListEndpoint=false` (тип без публичного per-object List на external — каноничный пример `vpc.addressPool`, G-08b); (b) пользователь хочет запинить id, которого он не видит в List (legit — заранее знает id создаваемого позже объекта)

**When** пользователь работает с resourceNames arm

**Then** (a) при `hasListEndpoint=false` UI рендерит **free-text** input (hand-typed opaque id), НЕ Select (нет источника инстансов)
**And** (b) при `hasListEndpoint=true` UI всё равно даёт **free-text-режим/добавление произвольного id** наряду с Select (запинить невидимый id) — picker не блокирует ручной ввод
**And** **cleanup (CRITICAL)**: hardcoded `PERMISSION_CATALOG`-константа и drift-guard `permissionCatalog.test.ts` **удалены** (каталог теперь live-driven, drift ловится backend-parity-тестом G-04, а не UI-зеркалом); `MODULE_OPTIONS`/`VERB_OPTIONS`/`resourcesForModules`/`isKnownModule` переписаны поверх react-query-данных или удалены, если больше не нужны
**And** vitest: (a) free-text рендерится при `hasListEndpoint=false`; (b) свободный id принимается при `hasListEndpoint=true`; (c) нет импорта удалённой константы в RulesEditor (статический assert / grep-гейт)

---

## 4. Кросс-репо порядок и реюз (сводка)

| Репо | Что |
|---|---|
| `kacho-proto` | новый `PermissionCatalogService.ListPermissionCatalog` (sync read) + `ListPermissionCatalogResponse`/`CatalogModule`/`CatalogResource`/`WildcardPolicy` сообщения; append-only (новый сервис — не breaking); `buf lint`/`breaking`/`generate` зелёные |
| `kacho-iam` | handler `ListPermissionCatalog` + проекция из `authzmap.objectTypes`/`TypeHasVerbRelations`/`domain.ClosedVerbs` + wildcard-политика + per-тип `hasListEndpoint` (закрытая таблица); тонкий handler, проекция в `domain`/`authzmap` (не PL/pgSQL — данные из кода) |
| `kacho-api-gateway` | регистрация `ListPermissionCatalog` в **public** mux (НЕ Internal*); `GET /iam/v1/permissionCatalog`; `api-gateway-registrar` |
| `kacho-ui` | react-query hook `usePermissionCatalog()` → RulesEditor dropdown'ы из RPC; resourceNames-picker (Select инстансов / free-text fallback); **ретайр** `permissionCatalog.ts`-константы + `permissionCatalog.test.ts` |
| `kacho-deploy` | mux-config (если нужен явный route-allowlist); FGA не трогается (нет нового tuple/relation) |
| `kacho-workspace` | docs-site Role-глава (catalog-RPC + backend-driven editor); vault-trail (`rpc/iam-*`, `edges/`-нет нового, UI-vault) |

**Реюз (НЕ переписывать):** `authzmap.objectTypes`/`TypeHasVerbRelations`/`SplitObjectType`, `domain.ClosedVerbs`, `RulesEditor`-каркас UI, react-query-инфра, публичные `List<Resource>` всех доменов (per-object filtered, под-фаза D) для resourceNames-picker. **Новое:** `PermissionCatalogService` + проекция-handler, UI react-query catalog-hook, resourceNames-picker, backend↔каталог parity-тест.

---

## 5. Открытые вопросы — ЗАКРЫТЫ (резолюции промотнуты в §0 как фиксированные решения)

> Раунд 1 review: эти 4 вопроса были candidates-to-close; резолюции подтверждены и **перенесены в §0** как фиксированные решения G-D7..G-D10 (НЕ переоткрывать). Таблица оставлена для traceability вопрос→решение.

| # | Вопрос | Резолюция (FIXED) | §0 |
|---|---|---|---|
| **G-Q1** | Отдельный `PermissionCatalogService` vs метод на `RoleService`? | **Отдельный сервис** — каталог не ресурс роли (нет owner/scope/CRUD); метод на `RoleService` смешал бы role-CRUD с платформенной метаданностью. | **G-D7** |
| **G-Q2** | `hasListEndpoint` — флаг в каталоге vs UI выводит сам? | **Флаг в каталоге** — единый backend-источник; UI не держит вторую копию (иначе тот же ручной-sync-долг). Internal-only List → `false`. | **G-D8** |
| **G-Q3** | Расширять каталог `permissions[]`-compiled / FGA-relation-именами? | **Нет** — только tenant-facing grantable-токены + редакторские флаги; compiled/internal-машинерия не на публичной поверхности. | **G-D9** |
| **G-Q4** | Что с internal `InternalIAMService.ListPermissions`-stub? | **Вне scope G** — фиксится/удаляется отдельным тикетом; публичный каталог его НЕ замещает (разные таксономии/листенеры). | **G-D10** |

> Технических открытых блокеров в сценариях нет. Единственный незакрытый organizational-item — `KAC-<N>`-placeholder (см. §0 hand-off-флаг): проставить реальный номер Subtask до gate-перехода (`writing-plans` / код).

---

## 6. Соответствие cross-domain графу (`polyrepo.md` / `data-integrity.md`)

- **Нет нового cross-service ребра.** `ListPermissionCatalog` — чисто-read из in-process backend-таблицы (`authzmap.objectTypes` + `domain.ClosedVerbs` — это Go-код в `kacho-iam`, не peer-call); IAM никого не зовёт для каталога.
- **resourceNames-picker** (UI) читает реальные инстансы через **существующие** публичные `List<Resource>` per-domain (api-gateway REST), per-object filtered (под-фаза D) — не новое iam→consumer ребро, не цикл.
- **FGA не трогается** — каталог не эмитит tuple/relation, не меняет `fga_model.fga`.
- **Публичный листенер** — каталог не infra-sensitive (G-D3); internal `ListPermissions`-stub остаётся на :9091 (ban #6 соблюдён — публичный каталог его не дублирует на external для admin-нужд, это разные RPC/таксономии).
- Каталог — read sync (`api-conventions.md`); мутаций нет (расширение только новым релизом backend, не RPC-мутацией).

---

## 7. Smoke / e2e (заказчик — финальная верификация, шаг 7)

- `grpcurl`/REST: `GET /iam/v1/permissionCatalog` аутентифицированно → 200 с `modules[]`/`resources[]`/`closedVerbs`/`wildcardPolicy`; анонимно → 401/`UNAUTHENTICATED`.
- UI smoke: открыть Role-create → RulesEditor → module/resource/verb dropdown'ы заполнены из RPC (не из bundled); arm=names на `vpc.subnet` → Select реальных subnet'ов (display-name, value=id); arm=names на типе без List → free-text.
- backend-driven proof: добавить `(module,resource)` в backend `objectTypes` на стенде, redeploy iam (НЕ ui) → новый ресурс появляется в dropdown без UI-редеплоя (G-09).
