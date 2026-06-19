# Epic «Resource-scoped AccessBinding» — Sub-phase α (target-в-binding) — Acceptance

> **Статус:** ✅ APPROVED (`acceptance-reviewer`, 2026-06-19)
> **Дата:** 2026-06-19
> **Автор:** `acceptance-author`
> **Ревьюер:** `acceptance-reviewer` — ✅ APPROVED (round-3: единственный блокер round-2 — стале strict-parity в rationale D-11 — закрыт; D-11 теперь явно read-side scope-проекция, НЕ Create-time containment-гейт, консистентно с α-14/α-07/D-5/D-14)._
> **Эпик/тикет:** epic «Resource-scoped AccessBinding» (вариант C — selector-based grants), под-фаза **α**. **Номер KAC проставляется ДО старта `superpowers:writing-plans`** (фича → эпик СНАЧАЛА, `git-youtrack.md`: `[EPIC]` + Subtask α/β/γ). Затронутые репо под-фазы α: `kacho-proto` / `kacho-iam` / `kacho-api-gateway` / `kacho-ui` / `kacho-deploy` / `kacho-workspace`(docs/vault).
> **Источник требований (verbatim intent заказчика):** «Чтобы дать субъекту доступ к ОДНОМУ конкретному ресурсу, сейчас нужно завести custom Role с permission `compute.instance.<id>.start` (4-й сегмент = id объекта) И отдельный AccessBinding — два ресурса, причём роль перестаёт быть переиспользуемой. Корень: 4-сегментная грамматика permission склеила "что можно делать" (reusable) с "над чем" (instance-specific). Решение: Role = чистый verb-bundle (`module.resource.verb`), КОНКРЕТНАЯ ЦЕЛЬ переезжает в `AccessBinding.target` (oneof). Один binding + одна reusable роль + N точечных объектов.»
> **Ground-truth (сверено против кода/proto/vault 2026-06-19):**
> - `kacho-proto/proto/kacho/cloud/iam/v1/access_binding.proto:29-117` — `AccessBinding{ id, subject_type, subject_id, role_id, resource_type(string, НЕ enum), resource_id, created_at, status(PENDING/ACTIVE/REVOKED), condition_id, expires_at, granted_by_user_id, revoked_at, revoked_by_user_id, builtin_condition, scope(enum CLUSTER/ACCOUNT/PROJECT = 15) }`; prefix `acb-`. Поле 16 свободно. `scope`-validation comment §97-116 (CLUSTER⇒`cluster`/`cluster_kacho_root`, ACCOUNT⇒`account`/`acc…`, PROJECT⇒`project`/`prj…`).
> - `access_binding_service.proto` — 8 RPC: `Get`/`ListByResource`/`ListBySubject`/`ListSubjectPrivileges`/`ListAssignableRoles`(1.5)/`ListByAccount`/`ListOperations` sync; `Create`/`Delete` async→Operation. **`AddTargetResources`/`RemoveTargetResources`/`ListGrantableResources` НЕ существуют** (grep по `iam/v1/` — 0 совпадений `target`/`grantable`/`selector`/`AccessTarget`/`ResourceRef`).
> - **kacho-iam: ЦЕЛЬ binding'а сегодня живёт в `role.permissions`, НЕ в binding.** `internal/service/fga_tuple_writer_v2.go:9-128` §3.5 матрица: `M.R.<resourceName>.V + any scope → fga_type(M,R):<resourceName>#tier(V)@<subject>` — **источник `<resourceName>` = 4-й сегмент permission'а роли** (`authzmap.SplitGrants(in.Permissions)`). `M.R.*.V → tier-tuple на scope anchor` (account/project/cluster). Per-object таргетинг сегодня требует concrete-`resourceName` в роли (= не-reusable роль).
> - `internal/authzmap/fga_types.go:1-30` — **закрытая таблица** `ObjectType(module, resource) → fga_object_type` (`compute.instance`→`compute_instance`, `vpc.subnet`→`vpc_subnet`, `vpc.network`→`vpc_network`, …); `ok=false` на неизвестную пару → консервативный fallback на tier-tuple. Это и есть закрытый словарь типов для `ResourceRef.type` (см. D-3).
> - `internal/apps/kacho/api/access_binding/create.go` — sync-часть `Create`: authenticated + `domain.AccessBinding.Validate()` (scope↔resource_id prefix, cluster-singleton) + `requireGrantAuthority`; роль читается в async-worker'е `doCreate` (FGA-derivation + **с 1.5** scope-enforcement `domain.IsRoleAssignable`); затем INSERT + outbox в writer-tx.
> - **sub-phase 1.5 (APPROVED 2026-06-18) уже живёт:** `domain.IsRoleAssignable(role, resource_type, resource_id)` — единый предикат scope-валидности (`internal/domain/role_scope.go`), общий для `ListAssignableRoles` (фильтр) и `Create` (enforcement, mis-scoped → `Operation.error` FAILED_PRECONDITION); STRICT-матрица (Q#1). `ListAssignableRoles(resource_type, resource_id)` sync read + `requireGrantAuthority`. **Эта под-фаза НЕ ломает 1.5** (D-4 ниже).
> - `internal/apps/kacho/api/access_binding/helpers.go` — `requireGrantAuthority(resource_type, resource_id)`: owner владеющего Account/Project ИЛИ FGA `admin` на scope-объект; cluster — только FGA `admin@cluster:cluster_kacho_root`.
> - `resources/iam-access-binding.md` (vault) — owner table `kacho_iam.access_bindings`; `access_bindings_unique` UNIQUE (subject_type, subject_id, role_id, resource_type, resource_id); partial UNIQUE `access_bindings_active_grant_uniq` WHERE `revoked_at IS NULL` (strict-create, миграция 0003); `resource_id` — soft-ref cross-DB (запрет #8); Delete физически удаляет row + FGA-revoke + `subject_change_outbox`.
> - `kacho-iam/CLAUDE.md` §4.5 — strict-create INSERT (без `ON CONFLICT`); §7 — НЕ возвращать silent ON-CONFLICT upsert.
> **Образцы формата:** `sub-phase-1.5-assignable-roles-acceptance.md`, `sub-phase-1.3-iam-subject-privileges-acceptance.md`, `sub-phase-vpc-redesign-kac239-acceptance.md`.

---

## Обзор

Сегодня, чтобы выдать субъекту права на **один конкретный объект** (напр. «start только инстанса `inst-abc`»), оператор обязан завести **custom Role**, в permission которой 4-й сегмент `resourceName` равен id объекта (`compute.instance.inst-abc.start`), **и** отдельный `AccessBinding` на эту роль. Получается **два** ресурса; и роль перестаёт быть переиспользуемой — на каждый новый объект нужна новая роль. Корень проблемы: 4-сегментная грамматика permission (`module.resource.resourceName.verb`) склеила **«что можно делать»** (reusable verb-bundle) с **«над чем»** (instance-specific цель). FGA-эмиссия per-object tuple'а (`fga_tuple_writer_v2.go` §3.5) сегодня берёт `<resourceName>` именно из permission роли.

Эпик переносит **цель** из роли в binding: `Role` — чистый verb-bundle, КОНКРЕТНАЯ ЦЕЛЬ переезжает в новое поле `AccessBinding.target` (oneof). Итог: **один binding + одна reusable роль + N точечных объектов**. Эмиссия per-object tuple'ов переиспользует существующий `fga_tuple_writer_v2.go` §3.5, но источником `resourceName` становится `binding.target`, а не `role.permissions`.

**Под-фаза α (этот документ)** вводит `AccessBinding.target` (oneof) с **двумя рабочими ветками**:
- **`all_in_scope`** — сегодняшнее поведение wildcard'а: грант на весь тип ресурса в пределах `scope` anchor;
- **`resources[]`** — per-object таргетинг по списку `ResourceRef{type,id}` (явный список объектов).

Третья ветка **`selector`** (label/tag-selector — рабочий вариант C) — **forward-declared** в proto, но на α **reject'ится `UNIMPLEMENTED`**: её реализация — под-фаза γ. Governance-managed IAM Tags (новые ресурсы `Tag`/`TagBinding`) — под-фаза β (см. §0.1 карта эпика). Под-фаза α НЕ вводит ни Tag-ресурсов, ни selector-материализации.

Документ описывает **только внешнее наблюдаемое поведение API и UI** (gRPC-коды, REST-формы, поведение экранов), не реализацию. Сценарии трассируются в имена integration-/newman-/UI-тестов через ID `α-<NN>`. Стандартные конвенции (`api-conventions.md`, `security.md`, `data-integrity.md`) нормативны и в тело не дублируются — только ссылками (§1).

---

## 0.1 Карта эпика (контекст/декомпозиция — детальные сценарии ТОЛЬКО для α)

| Под-фаза | Содержание | Статус в этом доке |
|---|---|---|
| **α** (ЭТОТ док) | `AccessBinding.target` oneof: `all_in_scope` (= сегодняшний wildcard на весь тип в scope) + `resources[]` (per-object по id). Ветка `selector` forward-declared в proto, reject'ится `UNIMPLEMENTED`. Set-мутации `AddTargetResources`/`RemoveTargetResources`. Новый read `ListGrantableResources`. Forward-only backfill legacy bindings. Role-coverage гейт (target.type ⊆ role-types). | **Сценарии α-01..α-24 ниже** (α-05 изъят → γ) |
| **β** (future — упомянуть) | Governance-managed **IAM Tags**: новые ресурсы `Tag`/`TagBinding` в kacho-iam (НЕ resource-labels владельцев — иначе privilege-escalation: tenant, правящий label своего ресурса, расширял бы себе доступ). Назначение тега под отдельным permission (напр. `iam.tags.bind`). Источник истины membership тегов — IAM same-DB. | **Вне scope α** (forward-ref) |
| **γ** (future — упомянуть) | Реализация ветки **`selector`** (`matchTags` + `types`): materialized reconciler разворачивает selector → per-object FGA tuples (+ outbox), eager-revoke per-object tuple при снятии тега. Это и есть рабочий вариант C. | **Вне scope α** (forward-ref); α лишь объявляет `selector` в proto и reject'ит `UNIMPLEMENTED` |

> **Важно для α:** `selector` в proto — пустой forward-declared message-каркас (см. D-3), достаточный, чтобы β/γ его наполнили без breaking-change. α **не** реализует tag-membership и **не** материализует selector. Любой `Create`/`Update` с непустым `selector` → `UNIMPLEMENTED` (α-13).

---

## 0. Фиксированные дизайн-решения (предлагаются автором; подлежат approve ревьюером — затем НЕ переоткрывать)

| ID | Решение | Обоснование |
|---|---|---|
| **D-1** | **`AccessBinding.target` — новое поле (`AccessTarget target = 16`)**, `AccessTarget` — `oneof target { bool all_in_scope = 1; ResourceRefList resources = 2; ResourceSelector selector = 3; }`. Поле `scope` (15, CLUSTER/ACCOUNT/PROJECT) **ОСТАЁТСЯ** как anchor иерархии/authz. `target` additive (новый field number), не ломает существующие сообщения (`buf breaking` зелёный). | Цель переезжает из `role.permissions` в `binding.target` — Role становится reusable verb-bundle. `scope` сохраняется: для `all_in_scope` он — anchor tier-tuple'а (как сегодня); для `resources[]` — sanity-guard «объекты обязаны лежать под scope» (D-5). Oneof — естественная форма «один из трёх способов задать цель» (`api-conventions.md` §«oneof/replace там, где удобнее»). |
| **D-2** | **`all_in_scope=true` ≡ сегодняшнее поведение wildcard-роли** (tier-tuple на scope anchor). При `target.all_in_scope`, FGA-эмиссия = текущая `M.R.*.V → tier-tuple` ветка `fga_tuple_writer_v2.go` §3.5 на `scope:<resource_id>`. Это **дефолт обратной совместимости** (D-8 backfill проецирует legacy bindings как `all_in_scope`). | `all_in_scope` — формализация «весь тип ресурса в этом scope», что сегодня выражается wildcard-`resourceName` в роли. Поведение и emitted tuples **идентичны** pre-α для этой ветки (нет регрессии). |
| **D-3** | **`message ResourceRef { string type = 1; string id = 2; }`**; `message ResourceRefList { repeated ResourceRef resources = 1; }`. `type` — ключ **закрытой таблицы** `authzmap.ObjectType` (`compute.instance`, `vpc.subnet`, `vpc.network`, `iam.project`, …; ground-truth `fga_types.go`); неизвестный `type` → `INVALID_ARGUMENT`. `id` — opaque object id (любой prefix); **`*` в `id` запрещён** (для «весь тип» есть `all_in_scope`) → `INVALID_ARGUMENT`. `message ResourceSelector { repeated string types = 1; map<string,string> match_tags = 2; }` — **forward-declared каркас** для γ; на α непустой `selector` → `UNIMPLEMENTED`. | `type` из закрытого словаря — детерминирует FGA-object-type для per-object tuple (`fga_type(M,R):<id>`); открытая строка ломала бы emission (unknown → fallback на tier, тихая дыра). `*`-в-`id` запрещён, чтобы единственный способ «весь тип» был `all_in_scope` (нет двух семантик одного). `selector`-каркас объявлен сейчас, чтобы γ не делал breaking-change. |
| **D-4** | **Грань с 1.5 (НЕ ломать).** `domain.IsRoleAssignable(role, scope-resource_type, scope-resource_id)` (scope-tier enforcement из 1.5) **сохраняется без изменений** — он гейтит role-vs-**scope** (account/project/cluster anchor), как сегодня. α добавляет **второй** независимый IAM-side гейт — **role-coverage** (D-13): `target.resources[].type` ⊆ типов ресурса в `role.permissions`. Оба гейта читаются из same-DB (роль + permissions в `kacho_iam`), детерминированы, без peer-call. Target-**containment** («объект физически под scope») в α **НЕ** энфорсится (D-14 — peer-call iam→compute/vpc = цикл, запрещён) и вынесен в γ. | 1.5 решает «какую роль можно привязать на scope», D-13 решает «покрывает ли роль типы объектов в target». Обе оси IAM-локальны (same-DB), не вводят cross-domain ребра. Явное разделение предотвращает регрессию 1.5-контракта и не создаёт цикл в графе. |
| **D-5** | **Target-валидация на α — БЕЗ peer-call (нет ребра iam→compute/vpc).** Для каждого `ResourceRef{type,id}` валидация ограничена IAM-side: (a) `type` ∈ закрытой таблицы `authzmap.ObjectType` (D-3) → иначе sync `INVALID_ARGUMENT`; (b) формальная проверка формата `id` (well-formedness — sync допустима); (c) `id` — **opaque soft-ref БЕЗ existence-валидации**: IAM **НЕ** звонит владельцу (как сегодняшний `AccessBinding.resource_id`, запрет #8), dangling-объект переживается graceful (α-12). **Existence и containment («объект под scope») на α НЕ проверяются** — это потребовало бы ребра `iam→compute/vpc`, а оно создаёт **цикл** (`compute→iam`/`vpc→iam` уже существуют — `polyrepo.md`, non-negotiable «циклы запрещены»). Containment вынесен в γ (D-14, known-limitation §0). | `resource_id` уже сегодня cross-DB opaque soft-ref (`access_binding.proto:48`, vault §Polymorphic refs) — `resources[].id` наследует **ту же** дисциплину: без FK, без peer-existence, dangling переживается на чтении (`data-integrity.md` §cross-domain п.4). Никакого нового runtime-ребра α не вводит. Privilege-boundary в α держится на scope-level grant-authority (D-12) + role-coverage (D-13); полноценный containment — γ. |
| **D-6** | **Per-object FGA tuples переиспользуют `fga_tuple_writer_v2.go` §3.5**, но **источник `resourceName` = `binding.target.resources[]`, не `role.permissions`.** Для каждого `(verb-tier роли) × (ResourceRef)` → `fga_type(ref.type):<ref.id>#tier(verb)@subject`. Role теперь несёт wildcard-`resourceName` (`M.R.*.V`) — verb-bundle; конкретику даёт target. Эмиссия — в той же writer-tx, что INSERT binding + outbox (атомарно, ban #10). | Ключевое решение эпика на уровне эмиссии. §3.5-матрица уже умеет concrete-`resourceName` per-object tuple — α лишь меняет, **откуда** берётся `<resourceName>`: с роли на target. Атомарность (tuple-emission ⊕ binding INSERT в одной tx через outbox) — существующий паттерн kacho-iam, не новый. |
| **D-7** | **Async-контракт (ban #9).** `Create` / `AddTargetResources` / `RemoveTargetResources` возвращают **`Operation`**. Ошибки **состояния** на α — через **`Operation.error`** `FAILED_PRECONDITION`: mis-scoped role-1.5 (D-4), role-coverage fail (D-13, α-24), last-element guard (D-10), add-к-all_in_scope (α-18). **`UNAVAILABLE` и object-not-found/containment в α НЕ возникают** (peer-call отсутствует — D-5/D-14). Ошибки **формата** (malformed `subject_id`/`role_id`/`ref.id`, unknown `ref.type`, `*` в `ref.id`, оба `all_in_scope` и `resources` заданы) — **sync `INVALID_ARGUMENT`** первым стейтментом RPC. `selector` непустой → **sync `UNIMPLEMENTED`** (форматный отказ до постановки Operation). | Симметрия с 1.5 Q#3 (одна error-поверхность для async мутации: формат — sync, состояние — `Operation.error`). Без peer-call у target нет ни `UNAVAILABLE`, ни state-not-found на α. `UNIMPLEMENTED` для selector — «метод-ветка не реализована», форматный отказ — допустимо sync. |
| **D-8** | **Forward-only backfill (стиль 1.5 D-11).** Legacy bindings (созданные до α — с целью-в-роли через concrete-`resourceName`, ИЛИ wildcard-роль) **читаются как `all_in_scope`** через backfill-проекцию: row без target-строк ⇒ `target.all_in_scope=true` в ответе. **НЕТ migration-revoke**, **НЕТ перезаписи** старых custom-ролей с concrete-`resourceName` (они продолжают работать как раньше — их per-object tuple остаётся). α не вычищает и не мигрирует существующие гранты. | Граничный инвариант миграции. Ретроактивная перезапись ломала бы текущий доступ операторов (silent privilege change). Паритет с graceful-деградацией (`data-integrity.md` §cross-domain) и с 1.5 D-11. Чистка/миграция legacy concrete-`resourceName`-ролей в reusable+target — отдельный осознанный data-migration тикет (вне α). |
| **D-9** | **DB-форма (ориентир для `db-architect-reviewer`).** Дочерняя таблица `kacho_iam.access_binding_targets`: `binding_id` FK → `access_bindings(id)` **ON DELETE CASCADE** (same-DB, ban #4 разрешает same-DB cascade), `type` TEXT, `id` TEXT, `UNIQUE(binding_id, type, id)` (идемпотентность add/dedup). `all_in_scope` ⇒ **отсутствие строк** в `access_binding_targets` для этого binding (флаг по факту пустоты). Add/Remove — INSERT … ON CONFLICT DO NOTHING / DELETE; idempotent by-construction. | Within-service инвариант на DB-уровне (ban #10): FK CASCADE гарантирует, что target-строки умирают с binding'ом без software-cascade; `UNIQUE` — идемпотентность повторного add. `all_in_scope`=пустота — не нужен отдельный nullable-флаг (одна row-семантика). Точная DDL — `migration-writer`/`db-architect-reviewer`, здесь только наблюдаемый контракт. |
| **D-10** | **«Убрать последний resource из `resources[]`» → НЕ авто-конверсия в `all_in_scope`; binding остаётся с пустым target-набором, что = НЕВАЛИДНОЕ состояние → `RemoveTargetResources` последнего элемента reject'ится `FAILED_PRECONDITION` «binding must target at least one resource or all_in_scope; use Delete to revoke».** Чтобы «снять все цели» — оператор делает `Delete` binding'а (revoke). Переключение `resources[]` ⇄ `all_in_scope` — через `Delete`+`Create` (binding immutable по форме target, как `AccessBinding` целиком immutable, §4.3 kacho-iam). | Без этого правила «удалил последний resource» имел бы двусмысленную семантику (пустой грант = доступ ни к чему = мёртвая строка, ИЛИ тихо «весь scope» = privilege escalation). Явный reject + «используй Delete» однозначен и безопасен. Авто-конверсия в `all_in_scope` — **запрещена** (тихое расширение прав). |
| **D-11** | **Новый sync read `ListGrantableResources(resource_type=scope-type, scope-id, object_type)`** — «какие конкретные объекты типа `object_type` доступны под scope для таргетинга». Дополняет 1.5 `ListAssignableRoles` (роли) симметричным «объекты». Authz-gate — **тот же `requireGrantAuthority`**, что Create/`ListAssignableRoles` на scope. Возвращает lean-проекцию объектов (id + name, output-only зеркало владельца) под scope. Cursor-paged `(created_at,id)`. | Симметрия с 1.5: UI grant-форме (resource-first) после выбора роли нужен picker конкретных объектов под scope. `ListGrantableResources` — read-side scope-проекция (helper для UI-picker'а), а **НЕ** Create-time containment-гейт: `Create`/`Add` в α принимают любой well-formed opaque `id` (D-5; containment вынесен в γ, D-14). Это **намеренно НЕ** строгий parity «read-set == accept-set» (в отличие от 1.5 `ListAssignableRoles`↔`Create`) — т.к. containment в α не энфорсится. Output-only зеркало (`data-integrity.md` §cross-domain п.3) — не источник истины, source = owner-сервис. |
| **D-12** | **AuthZ — `requireGrantAuthority(scope-resource_type, scope-resource_id)`** на всех новых путях (`Create` с target, `AddTargetResources`, `RemoveTargetResources`, `ListGrantableResources`) — **тот же gate**, что у `Create`/`ListByResource`/`ListAssignableRoles` на scope. Анонимный → fail-closed первым (`RequireAuthenticated`). НЕ требуется отдельная per-object authority в α (grant-authority на scope покрывает таргетинг объектов **под** этим scope). | Симметрия со всем AccessBinding-API: «кто может грантить на scope» == «кто может задавать/менять target под этим scope». Per-object authority в α не требуется (D-15 / Q#B зафиксировано). |
| **D-13** | **Role-coverage гейт (НОВЫЙ — ТРЕТИЙ независимый гейт на Create/Add).** Каждый `target.resources[].type` обязан **покрываться** хотя бы одним типом ресурса в `permissions` роли: тип объекта в target ⊆ типов, на которые роль вообще даёт verb'ы. Иначе → `Operation.error` `FAILED_PRECONDITION` `"role <id> does not grant any verb on <type>"`; binding не создан. Гейт **детерминирован** (читается из `role.permissions` — same-DB, без peer-call, нет TOCTOU). | Без этого можно создать binding с target на `vpc.subnet`, привязав роль, у которой verb'ы только на `compute.*` — грант был бы пустой/бессмысленный (или вёл бы к неэмитируемым tuple'ам). Проверка target.type ⊆ role-types — чисто IAM-side (роль и её permissions живут в `kacho_iam` same-DB), детерминирована, не race-prone. Это третий ортогональный гейт к role-scope (1.5, D-4) и target-containment (вынесен в γ, D-14). |
| **D-14** | **Target-containment («объект лежит под scope») — НЕ энфорсится на α; вынесен в под-фазу γ как known-limitation.** На IAM-стороне `inst-abc.project_id == prj-P` авторитетно знает только владелец (kacho-compute, cross-DB), а peer-call IAM→compute/vpc **запрещён** (был бы цикл — `compute→iam`/`vpc→iam` уже существуют, `polyrepo.md`, non-negotiable «циклы запрещены»). Поэтому в α `target.resources[].id` — **opaque soft-ref БЕЗ existence- и БЕЗ containment-валидации** (как сегодняшний `AccessBinding.resource_id`, запрет #8): IAM не звонит владельцу, dangling переживается graceful (α-12). Энфорсмент containment — owner-side либо под-фаза γ (когда появится не-цикличный механизм, напр. tag-membership в IAM same-DB). | Запрет цикла в графе — non-negotiable; «положить чужой объект под свой scope» в α технически возможно, но это **зафиксированная known-limitation** (privilege-boundary держится на scope-level grant-authority D-12 + role-coverage D-13). γ закрывает containment без нового ребра. |
| **D-15** | **Зафиксированные решения по бывшим открытым вопросам (родитель/ревьюер сняли).** **(Q#A/Q#C)** `target.resources[].id` — opaque soft-ref, **без** peer-existence и **без** containment-валидации, **без** нового cross-domain ребра `iam→compute/vpc` (был бы цикл); containment → γ (D-14). **(Q#B)** scope-level grant-authority (D-12) + отсутствие containment-энфорса в α достаточны; per-object authority в α НЕ требуется. **(Q#D)** forward-only backfill — **read-time проекция** (0 target-строк ⇒ `all_in_scope`), без migration-revoke (D-8). **(Q#E)** строго oneof (`resources` XOR `all_in_scope` XOR `selector`), без смешения/fallback. **(Q#F)** имя дока descriptor-стиль (как есть), scenario-ID-префикс `α-NN` (как есть). | Эти решения были «Открытыми вопросами §5» в первой редакции; родитель и ревьюер их сняли — раздел §5 закрыт. Фиксируется здесь, чтобы НЕ переоткрывать. |

---

## 1. Связь с регламентом (нормативно; в тело не дублируется)

| Регламент | Где соблюдается |
|---|---|
| `api-conventions.md` — read **sync**, мутации async `Operation`; Watch не существует (polling) | §A (`ListGrantableResources` sync read); §C (`Create`/`Add`/`Remove` async Operation) |
| `api-conventions.md` — flat message + oneof где удобно; `AccessBinding.target` oneof (D-1) | D-1, D-3, α-01..α-03 |
| `api-conventions.md` — REST `/<service>/v1/<resource>`, suffix-action `:verb`; JSON camelCase (`allInScope`, `resources`, `target`, `objectType`, `nextPageToken`) | §A/§C REST-формы, §J smoke |
| `api-conventions.md` — error-format; malformed → sync `INVALID_ARGUMENT` первым стейтментом; состояние-не-позволяет → `FAILED_PRECONDITION` (для async — через `Operation.error`, ban #9). На α **нет** `UNAVAILABLE`-пути для target (peer-call отсутствует — D-5/D-14) | D-5, D-7, D-13, α-08..α-13, α-17, α-24 |
| `api-conventions.md` — cursor pagination `(created_at,id)` ASC, `page_token` opaque base64, `page_size` 0→default(50), max 1000 | D-11, α-15 |
| `data-integrity.md` §within-service — `access_binding_targets` FK CASCADE (same-DB) + `UNIQUE(binding_id,type,id)` идемпотентность; concurrent add/remove → integration-тест | D-9, α-04, α-18, α-19 |
| `data-integrity.md` §cross-domain — `resources[].id` — opaque soft-ref (без FK, без peer-existence, запрет #8); НЕ создаёт ребра `iam→compute/vpc` (был бы цикл); dangling-ref переживается на чтении (п.4); output-only зеркало в `ListGrantableResources` | D-5, D-14, D-11, α-12, α-17, α-21 |
| `security.md` §AuthN+AuthZ ВЕЗДЕ — каждый RPC per-RPC Check; `requireGrantAuthority`; анонимный fail-closed | D-12, α-10, α-11 |
| `security.md` §Internal-vs-external (ban #6) — все новые RPC **публичные** (tenant-UI на grant-форме), НЕ Internal | §A/§C (public external endpoint) |
| `security.md` §Инфра-чувствительные данные — `ListGrantableResources` отдаёт только tenant-facing id/name (зеркало), без инфра-полей | D-11, α-16 |
| `00-kacho-core.md` ban #9 (мутации→Operation), #10 (within-DB инвариант), #4 (same-DB cascade ОК), #8 (нет shared БД), #12 (TDD), #1 (APPROVED перед кодом) | §C async; D-9 FK CASCADE same-DB; D-5 cross-DB soft-ref; §6 DoD (RED→GREEN) |
| forward-only миграция enforcement (паритет 1.5 D-11 / `data-integrity.md` §cross-domain «грациозно переживать») | D-8, α-20, α-21 |
| `polyrepo.md` §порядок merge | §6 DoD: proto → iam → api-gateway → ui → deploy → workspace(docs) |
| sub-phase 1.5 (APPROVED) — `IsRoleAssignable` / `ListAssignableRoles` / Create scope-enforcement сохраняются | D-4, α-22 (1.5-parity non-regression) |
| ТРИ независимых гейта: (1) role-scope 1.5, (2) role-coverage (D-13), (3) target-containment [вынесен в γ] — (1)+(2) на α | D-4, D-13, D-14, §2.2, α-22, α-24 |

---

## 2. Target-модель и предикаты (нормативно — D-1/D-3/D-4/D-5)

### 2.1 Форма `AccessTarget` (proto-ориентир — финал за `proto-api-reviewer`)

```
message ResourceRef     { string type = 1; string id = 2; }
message ResourceRefList  { repeated ResourceRef resources = 1; }
message ResourceSelector { repeated string types = 1; map<string,string> match_tags = 2; }   // forward-declared (γ)

message AccessTarget {
  oneof target {
    bool             all_in_scope = 1;   // = сегодняшний wildcard на весь тип в scope (D-2)
    ResourceRefList  resources    = 2;   // per-object по id (α)
    ResourceSelector selector     = 3;   // label/tag-selector — UNIMPLEMENTED на α (γ)
  }
}

// AccessBinding additive:
//   AccessTarget target = 16;   // scope (15) ОСТАЁТСЯ anchor
```

### 2.2 ТРИ независимых гейта (D-4/D-13/D-14 — не путать)

На Create/Add действуют **три** ортогональных гейта. **Два** из них — на α; третий (containment) вынесен в γ:

| # | Гейт | Ось | Источник истины | Где | Поведение при провале |
|---|---|---|---|---|---|
| **(1)** | **role-scope (1.5, БЕЗ изменений)** | роль ↔ **scope** anchor (account/project/cluster) | `domain.IsRoleAssignable(role, scope_type, scope_id)` (same-DB) | **α** | mis-scoped роль → `Operation.error` `FAILED_PRECONDITION` (1.5 Q#3) |
| **(2)** | **role-coverage (α, НОВЫЙ — D-13)** | `target.resources[].type` ⊆ типов ресурса в `role.permissions` | `role.permissions` (same-DB, детерминирован, без TOCTOU) | **α** | формат/unknown-type → sync `INVALID_ARGUMENT`; тип не покрыт ролью → `Operation.error` `FAILED_PRECONDITION` `"role <id> does not grant any verb on <type>"` (α-24) |
| **(3)** | **target-containment (вынесен в γ — D-14)** | объекты `resources[]` физически лежат **под** `scope` | владелец (kacho-compute/vpc, cross-DB) — требует механизма без цикла | **γ** (НЕ α) | на α **не** энфорсится: `target.resources[].id` opaque soft-ref, IAM не звонит владельцу (known-limitation §0, D-14/D-15) |

> **Гейты (1) и (2) — оба в α**, оба IAM-локальны (same-DB, без peer-call). Гейт (3) (containment) в α **отсутствует** — он требовал бы ребра `iam→compute/vpc`, создающего цикл (`polyrepo.md`, non-negotiable); закрывается в γ.

### 2.3 Матрица `target` × поведение (α)

| `target` | Валидность на α | FGA-эмиссия | Примечание |
|---|---|---|---|
| `all_in_scope = true` | ✅ | tier-tuple на `scope:<resource_id>` (= pre-α wildcard, D-2) | дефолт back-compat; backfill-проекция legacy (D-8) |
| `resources = [ref…]` (≥1, типы из closed-table, покрыты ролью D-13) | ✅ | per-`ref` direct tuple `fga_type(ref.type):<ref.id>#tier(verb)@subj` (D-6) | per-object таргетинг — суть эпика; `id` — opaque soft-ref (без existence/containment-проверки, D-5) |
| `resources` c `type`, НЕ покрытым `role.permissions` | ❌ `Operation.error` `FAILED_PRECONDITION` | — | role-coverage гейт (D-13, α-24) — async (читается role) |
| `resources = []` (пусто) | ❌ `INVALID_ARGUMENT` | — | пустой target бессмысленен (D-10) |
| `resources` c `*` в `ref.id` | ❌ `INVALID_ARGUMENT` | — | «весь тип» = `all_in_scope`, не `*` (D-3) |
| `resources` c unknown `ref.type` | ❌ `INVALID_ARGUMENT` | — | тип вне `authzmap.ObjectType` closed-table (D-3) |
| и `all_in_scope`, и `resources` заданы | ❌ `INVALID_ARGUMENT` | — | oneof — ровно одна ветка |
| `selector` непустой | ❌ `UNIMPLEMENTED` | — | forward-declared, реализация — γ (D-3, α-13) |
| `target` вообще не задан (legacy/back-compat вход) | ✅ трактуется как `all_in_scope` | tier-tuple (D-2/D-8) | back-compat: старый клиент без target |

---

## 3. Глоссарий: текущее состояние (ground-truth) и дельта α

| Сущность | id-prefix | Текущее состояние | Дельта под-фазы α |
|---|---|---|---|
| `AccessBinding.target` (`AccessTarget`) | — | **НЕ существует**; цель кодируется в `role.permissions` concrete-`resourceName` (`fga_tuple_writer_v2.go` §3.5) | **НОВОЕ** поле 16, oneof `all_in_scope`/`resources`/`selector` (D-1/D-3) |
| `AccessBinding.Create` | `acb` | LIVE async→Operation; scope-enforcement 1.5 (`IsRoleAssignable`); цель из роли | **принимает `target`**; per-object эмиссия из target (D-6); гейты role-scope (1.5, D-4) + role-coverage (D-13); target.id — opaque soft-ref (без existence/containment, D-5/D-14); back-compat: нет target ⇒ `all_in_scope` |
| `AddTargetResources` / `RemoveTargetResources` | — | **НЕ существуют** | **НОВЫЕ** async→Operation set-мутации target.resources[] (idempotent; D-10 last-element guard) |
| `ListGrantableResources` | — | **НЕ существует** | **НОВЫЙ** sync read — объекты типа под scope, доступные для таргетинга (D-11) |
| `ResourceSelector` (ветка selector) | — | **НЕ существует** | **forward-declared** каркас в proto; на α → `UNIMPLEMENTED` (γ реализует) |
| `Role` | `rol` | verb-bundle + concrete-`resourceName` для per-object | НЕ меняется как ресурс; per-object цель уходит в target → роль становится чисто reusable verb-bundle (поведенчески, без миграции старых ролей — D-8) |
| `IsRoleAssignable` / `ListAssignableRoles` (1.5) | — | LIVE; role-vs-scope предикат + sync read | **сохраняются без изменений** (D-4); α добавляет ортогональный target-уровень |
| `access_binding_targets` (таблица) | — | **НЕ существует** | **НОВАЯ** дочерняя таблица (FK CASCADE same-DB, `UNIQUE(binding_id,type,id)`; D-9) |
| `authzmap.ObjectType` closed-table | — | LIVE (`fga_types.go`) — `(module,resource)→fga_object_type` | источник валидных `ResourceRef.type` (D-3); НЕ меняется |

---

## §A — Backend: read `ListGrantableResources`

REST (public): `GET /iam/v1/accessBindings:listGrantableResources?resourceType=<scope-type>&resourceId=<scope-id>&objectType=<closed-table-type>&pageSize=&pageToken=`
gRPC: `kacho.cloud.iam.v1.AccessBindingService/ListGrantableResources` (sync read — НЕ Operation).
JSON-ответ (camelCase): `{ "resources": [ { "type","id","name" } ], "nextPageToken": "" }` (`name` — output-only зеркало владельца, D-11).

### Сценарий α-14: Happy path — ListGrantableResources отдаёт объекты типа под scope

**ID:** `α-14`

**Given** account `acc-A` c проектом `prj-P` (owner `usr-OWNER`)
**And** под `prj-P` существуют compute-инстансы `inst-1`, `inst-2` (владелец — kacho-compute)
**And** caller — `usr-OWNER` (grant-authority на `prj-P`)

**When** caller вызывает `…:listGrantableResources?resourceType=project&resourceId=prj-P&objectType=compute.instance`

**Then** sync `200 OK`, gRPC `OK`
**And** `resources` содержит `{type:"compute.instance", id:"inst-1", name:…}` и `inst-2` (объекты под `prj-P`)
**And** **НЕ** содержит инстансы другого проекта/account'а (read-side scope-фильтр output-only зеркала владельца, D-11 — это read-проекция, НЕ Create-time containment-энфорсмент, который вынесен в γ D-14)
**And** упорядочено по `(createdAt,id)` ASC; `nextPageToken=""`

### Сценарий α-15: Pagination — pageSize=1 отдаёт страницу + курсор

**ID:** `α-15`

**Given** под `prj-P` ≥2 grantable объекта типа `compute.instance`, caller — owner

**When** caller вызывает `…:listGrantableResources?resourceType=project&resourceId=prj-P&objectType=compute.instance&pageSize=1`
**Then** `resources` = 1 элемент (первый по `(createdAt,id)` ASC); `nextPageToken` непустой opaque base64

**When** caller повторяет с `&pageToken=<nextPageToken>`
**Then** следующий элемент; в конце `nextPageToken=""`

### Сценарий α-16: Conformance — grantable-объект несёт только tenant-facing поля (зеркало)

**ID:** `α-16`

**Given** grantable `inst-1` под `prj-P`, caller — owner

**When** caller читает через `…:listGrantableResources`

**Then** элемент содержит **только** `type`, `id`, `name` (output-only зеркало; source = owner-сервис)
**And** ответ **не** содержит инфра-чувствительных полей (placement/underlay/wiring — `security.md`)

### Сценарий α-10: AuthZ — caller без grant-authority на scope → PERMISSION_DENIED

**ID:** `α-10`

**Given** `prj-P` (owner `usr-OWNER`) и сторонний `usr-X` без grant-authority на `prj-P`
**And** caller — `usr-X`

**When** caller вызывает `…:listGrantableResources?resourceType=project&resourceId=prj-P&objectType=compute.instance`

**Then** gRPC `PERMISSION_DENIED`, REST `403` (D-12 — тот же gate, что Create/ListAssignableRoles)
**And** утечки списка объектов `prj-P` нет

### Сценарий α-11: Negative — анонимный caller → fail-closed

**ID:** `α-11`

**Given** запрос без валидного principal (анонимный)

**When** вызывается любой из `…:listGrantableResources` / `POST accessBindings` (с target) / `…:addTargetResources`

**Then** отклоняется fail-closed (gRPC `UNAUTHENTICATED`/`PERMISSION_DENIED`; REST `401`/`403` — `RequireAuthenticated`), **до** данных/мутации

### Сценарий α-09: Negative — unknown objectType / scope mismatch → INVALID_ARGUMENT (sync)

**ID:** `α-09`

**Given** аутентифицированный caller, grant-authority на `prj-P`

**When** caller вызывает `…:listGrantableResources?resourceType=project&resourceId=prj-P&objectType=foo.bar`
**Then** gRPC `INVALID_ARGUMENT`, REST `400`, message `"Illegal argument objectType (unknown resource type)"` (тип вне `authzmap.ObjectType` closed-table, D-3) — синхронно, до репозитория

**When** caller вызывает `…:listGrantableResources?resourceType=account&resourceId=not-a-valid-id&objectType=compute.instance`
**Then** gRPC `INVALID_ARGUMENT`, message `"invalid account id 'not-a-valid-id'"` (malformed scope id, sync)

---

## §C — Backend: `AccessBinding.Create` с target + set-мутации

REST: `POST /iam/v1/accessBindings` (body несёт `target`); `POST /iam/v1/accessBindings/{access_binding_id}:addTargetResources`; `POST /iam/v1/accessBindings/{access_binding_id}:removeTargetResources`.
gRPC: `Create`/`AddTargetResources`/`RemoveTargetResources` — все **async → Operation** (ban #9).

### Сценарий α-01: Happy path — Create с resources[] (один объект) + reusable role → per-object tuple

**ID:** `α-01`

**Given** account `acc-A` c проектом `prj-P` (owner `usr-OWNER`)
**And** reusable SYSTEM-роль `rol-computeeditor` (verb-bundle, `compute.instance.*.…`; assignable на `prj-P` по 1.5)
**And** под `prj-P` существует инстанс `inst-abc` (kacho-compute)
**And** caller — `usr-OWNER`

**When** caller вызывает `POST /iam/v1/accessBindings` с payload:
  - `subjectType` = `"user"`, `subjectId` = `"usr-MEMBER"`
  - `roleId` = `"rol-computeeditor"`
  - `resourceType` = `"project"`, `resourceId` = `"prj-P"`  (scope anchor, 15)
  - `scope` = `PROJECT`
  - `target` = `{ "resources": { "resources": [ { "type":"compute.instance", "id":"inst-abc" } ] } }`

**Then** RPC возвращает `Operation`; клиент поллит `OperationService.Get(id)` до `done=true`
**And** Operation `done && !error`; `response` несёт `AccessBinding` c `id` (acb-…), `createdAt`, `target.resources=[{compute.instance,inst-abc}]`, `scope=PROJECT`
**And** эмитится per-object FGA tuple `compute_instance:inst-abc#<tier>@user:usr-MEMBER` (D-6 — источник resourceName = target, не role)
**And** `Get(acb-…)` отдаёт binding c тем же target

### Сценарий α-02: Happy path — Create с несколькими object refs

**ID:** `α-02`

**Given** как α-01; под `prj-P` инстансы `inst-1`, `inst-2`, `inst-3`

**When** caller вызывает `Create` c `target.resources = [ {compute.instance,inst-1}, {compute.instance,inst-2}, {compute.instance,inst-3} ]`

**Then** Operation `done && !error`; binding несёт все 3 ref'а
**And** эмитится **по одному** per-object tuple на каждый ref (3 tuple'а; D-6)
**And** `Get` отдаёт binding c 3 target-объектами (порядок стабильный по `(type,id)`)

### Сценарий α-03: Happy path — Create с all_in_scope → tier-tuple (= сегодняшнее wildcard-поведение)

**ID:** `α-03`

**Given** как α-01, reusable роль `rol-computeeditor`, scope `PROJECT prj-P`

**When** caller вызывает `Create` c `target = { "allInScope": true }`, `scope=PROJECT`, `resourceId=prj-P`

**Then** Operation `done && !error`; binding несёт `target.allInScope=true`, 0 target-строк (D-9)
**And** эмитится tier-tuple на `project:prj-P` (= pre-α wildcard ветка §3.5, D-2) — **не** per-object tuple
**And** поведение/emitted-tuples идентичны pre-α binding'у на wildcard-роль (нет регрессии)

### Сценарий α-04: Idempotency — повторный Create с тем же (subject, role, resource, target) → existing

**ID:** `α-04`

**Given** binding из α-01 уже создан (`subject=usr-MEMBER, role=rol-computeeditor, project=prj-P, target=[compute.instance:inst-abc]`)

**When** caller повторяет тот же `Create` (тот же subject/role/resource/target) → poll Operation

**Then** Operation `done && !error`; metadata `accessBindingId` = **существующий** acb-id (idempotent re-create, как сегодня — UNIQUE 5-tuple + active-grant partial UNIQUE; vault §Notes / kacho-iam §4.5)
**And** дублирующих target-строк не появляется (`UNIQUE(binding_id,type,id)`, D-9); FGA-tuple-set не растёт

### Сценарий α-17: Negative — malformed target ref id → sync INVALID_ARGUMENT (existence НЕ проверяется)

**ID:** `α-17`

**Given** scope `PROJECT prj-P`, reusable роль, caller — owner

**When** caller вызывает `Create` c `target.resources=[{compute.instance, "%%bad-id%%"}]` где `id` **malformed** (нарушает формат object-id) → синхронно
**Then** sync `INVALID_ARGUMENT`, message `"invalid compute.instance id '%%bad-id%%'"` первым стейтментом RPC (`api-conventions.md`; форматный отказ до Operation, D-5(b)); binding **не** создан

**When** caller вызывает `Create` c `target.resources=[{compute.instance, inst-GHOST}]` где `inst-GHOST` **well-formed-но-не-существует** во владельце → poll Operation
**Then** Operation `done && !error`; binding **принимается** — `inst-GHOST` сохраняется как **opaque soft-ref** (D-5: IAM НЕ звонит владельцу, existence НЕ проверяется, как сегодняшний `resource_id`, запрет #8). Отсутствие/удаление объекта переживается graceful на чтении — основное negative-покрытие отсутствия объекта см. **α-12** (dangling-ref).

> **Примечание (D-5/D-14):** ветки «well-formed-несуществующий → FAILED_PRECONDITION» и «владелец недоступен → UNAVAILABLE» **удалены** — обе требовали бы peer-call `iam→compute/vpc`, создающего цикл в графе (`polyrepo.md`, non-negotiable). На α existence объекта не проверяется; containment («объект под scope») — γ (D-14). Семантика отсутствующего/dangling объекта покрыта α-12.

### α-05: ИЗЪЯТ — target-containment вынесен в γ (known-limitation, НЕ enforced на α)

**ID:** `α-05` — _изъят как enforced-сценарий._

Прежняя формулировка требовала, чтобы IAM проверял «объект `inst-other` лежит под `scope=prj-P`». Авторитет «`inst.project_id == prj-P`» живёт только у владельца (kacho-compute, cross-DB), а peer-call `iam→compute` создал бы **цикл** в графе (`compute→iam` уже есть — `polyrepo.md`, non-negotiable). Поэтому:

> **Known-limitation (зафиксировано в §0, D-14/D-15):** на α `target.resources[].id` **не** проверяется на принадлежность scope. Положить объект чужого проекта под свой scope технически возможно — privilege-boundary в α держится на scope-level grant-authority (D-12) + role-coverage (D-13). Полноценный containment-энфорсмент — **owner-side либо под-фаза γ** (когда появится не-цикличный механизм). ID `α-05` остаётся зарезервированным под containment-сценарий в γ-acceptance.

### Сценарий α-08: Negative — malformed/конфликтный target → INVALID_ARGUMENT (sync)

**ID:** `α-08`

**Given** аутентифицированный caller, grant-authority на scope

**When** `Create` c `target.resources=[{type:"foo.bar", id:"x"}]` (unknown type) → **Then** sync `INVALID_ARGUMENT` `"Illegal argument target.resources[].type (unknown resource type)"` (D-3), до Operation
**When** `Create` c `target.resources=[{type:"compute.instance", id:"*"}]` → **Then** sync `INVALID_ARGUMENT` `"Illegal argument target.resources[].id (wildcard not allowed; use all_in_scope)"` (D-3)
**When** `Create` c `target.resources=[]` (пустой список) → **Then** sync `INVALID_ARGUMENT` `"target must specify all_in_scope or at least one resource"` (D-10)
**When** `Create` c заданными И `allInScope:true` И непустым `resources` → **Then** sync `INVALID_ARGUMENT` `"target: exactly one of all_in_scope|resources|selector"` (oneof)
**When** `Create` c malformed `subjectId`/`roleId` → **Then** sync `INVALID_ARGUMENT "invalid <res> id '<X>'"` первым стейтментом (`api-conventions.md`)

### Сценарий α-13: Negative — selector-ветка → UNIMPLEMENTED (forward-declared, γ)

**ID:** `α-13`

**Given** аутентифицированный caller, grant-authority на scope

**When** caller вызывает `Create` c `target = { "selector": { "types":["compute.instance"], "matchTags":{"env":"prod"} } }`

**Then** gRPC `UNIMPLEMENTED`, REST `501`, message `"target.selector is not implemented (planned: resource-scoped-access-binding γ)"` (D-3/D-7 — sync форматный отказ, до Operation)
**And** binding **не** создан; никакой материализации selector не происходит (α не реализует tag-membership)

### Сценарий α-22: Conformance — 1.5 role-scope enforcement сохраняется ПОВЕРХ target-гейта (non-regression)

**ID:** `α-22`

**Given** scope `ACCOUNT acc-A` (owner `usr-OWNER`); чужая ACCOUNT-роль `rol-bcustom` (`account_id=acc-B`) — НЕ assignable на `acc-A` (1.5 D-8)
**And** под `acc-A` валидный объект для target

**When** caller вызывает `Create` c `roleId=rol-bcustom`, `scope=ACCOUNT, resourceId=acc-A`, любой валидный `target` → poll Operation

**Then** Operation `done && error.code = FAILED_PRECONDITION`, message `"role rol-bcustom is not assignable on account:acc-A"` (**1.5-предикат `IsRoleAssignable` срабатывает первым** — D-4; α не ослабляет 1.5)
**And** target-гейт даже не оценивается, если роль mis-scoped (role-scope — самостоятельный гейт); binding не создан

### Сценарий α-24: Negative — target.type НЕ покрыт ролью → FAILED_PRECONDITION (role-coverage, D-13)

**ID:** `α-24`

**Given** scope `PROJECT prj-P` (owner `usr-OWNER`, caller)
**And** reusable роль `rol-computeonly`, у которой `permissions` дают verb'ы **только** на `compute.*` (нет ни одного verb'а на `vpc.subnet`)
**And** роль assignable на `prj-P` по 1.5 (гейт (1) проходит)

**When** caller вызывает `Create` c `roleId=rol-computeonly`, `scope=PROJECT, resourceId=prj-P`, `target.resources=[{type:"vpc.subnet", id:"fpn-abc"}]` → poll Operation

**Then** Operation `done && error.code = FAILED_PRECONDITION`, message `"role rol-computeonly does not grant any verb on vpc.subnet"` (role-coverage гейт D-13: `target.type` ⊄ типов в `role.permissions`; детерминирован, читается same-DB, без TOCTOU)
**And** binding **не** создан; никакие FGA-tuple'ы не эмитятся
**And** _Примечание:_ гейт (2) (role-coverage) ортогонален гейту (1) (role-scope 1.5) — здесь роль scope-assignable, но не покрывает тип объекта; оба гейта в α (§2.2).

### Сценарий α-18: AddTargetResources — idempotent add нового и повторного ref

**ID:** `α-18`

**Given** binding `acb-1` из α-01 (`target.resources=[compute.instance:inst-abc]`), caller — owner с grant-authority

**When** caller вызывает `POST …/acb-1:addTargetResources` c `resources=[{compute.instance, inst-def}]` → poll Operation
**Then** Operation `done && !error`; `Get(acb-1).target.resources` = `[inst-abc, inst-def]`; эмитится per-object tuple для `inst-def` (D-6)

**When** caller повторяет тот же `:addTargetResources` c `[{compute.instance, inst-def}]` (уже есть) → poll Operation
**Then** Operation `done && !error` (idempotent — `UNIQUE(binding_id,type,id)` ON CONFLICT DO NOTHING, D-9); target-набор и FGA-tuple-set **не** растут

**When** caller вызывает `:addTargetResources` на binding'е, который был создан как `all_in_scope` → poll Operation
**Then** Operation `done && error.code = FAILED_PRECONDITION` `"cannot add resources to an all_in_scope binding"` (нельзя смешивать ветки oneof — D-1/D-10; смена ветки = Delete+Create)

### Сценарий α-19: RemoveTargetResources — idempotent remove; снятие последнего reject'ится

**ID:** `α-19`

**Given** binding `acb-2` c `target.resources=[inst-1, inst-2]`, caller — owner

**When** caller вызывает `POST …/acb-2:removeTargetResources` c `resources=[{compute.instance, inst-2}]` → poll Operation
**Then** Operation `done && !error`; `Get(acb-2).target.resources=[inst-1]`; per-object tuple для `inst-2` **удалён** (D-6 revoke)

**When** caller повторяет remove `inst-2` (уже нет) → poll Operation
**Then** Operation `done && !error` (idempotent remove — no-op, не ошибка)

**When** caller вызывает `:removeTargetResources` c `[{compute.instance, inst-1}]` (последний оставшийся) → poll Operation
**Then** Operation `done && error.code = FAILED_PRECONDITION` `"binding must target at least one resource or all_in_scope; use Delete to revoke"` (D-10 — пустой target запрещён; авто-конверсии в all_in_scope НЕТ); `inst-1` остаётся, tuple не снят

### Сценарий α-19b: Concurrency — конкурентные Add/Remove одного ref → ровно один эффект, без дублей и без отрицательного состояния

**ID:** `α-19b`

**Given** binding `acb-3` c `target.resources=[inst-1]`, caller — owner

**When** оператор запускает **две конкурентные** `:addTargetResources [{compute.instance, inst-9}]` (один и тот же ref) → poll обе Operation
**Then** **обе** Operation `done && !error`; в `target.resources` ровно **один** `inst-9` (не два) — `UNIQUE(binding_id,type,id)` сериализует (D-9); FGA-tuple для `inst-9` ровно один

**When** оператор запускает конкурентно `:addTargetResources [{compute.instance, inst-X}]` и `:removeTargetResources [{compute.instance, inst-X}]`
**Then** обе Operation `done` без паники/leak'а; финальное состояние детерминировано присутствием/отсутствием row (last-writer на row-lock'е), не «полу-записанным» (`data-integrity.md` §within-service — concurrent integration-тест ≥2 goroutine обязателен, п.5)
**And** _Обоснование контракта (для `integration-tester`/`db-architect-reviewer`):_ `access_binding_targets` — INSERT … ON CONFLICT DO NOTHING / DELETE на одной row; идемпотентность и отсутствие дублей гарантируются `UNIQUE(binding_id,type,id)` + row-lock (не software check-then-act, ban #10). Concurrent-non-regression тест (testcontainers, ≥2 goroutine) ОБЯЗАТЕЛЕН (RED-first, планируется в S2 DoD).

### Сценарий α-12: Cross-service — dangling target-ref переживается на чтении (graceful)

**ID:** `α-12`

**Given** binding `acb-4` c `target.resources=[compute.instance:inst-zz]`; затем `inst-zz` **удалён** во владельце (kacho-compute) — cross-DB, без cascade в IAM (запрет #4)

**When** caller читает `Get(acb-4)` / `ListByResource` на scope

**Then** `200 OK`; binding отдаётся с `target.resources=[compute.instance:inst-zz]` как раньше (dangling-ref **не** вызывает панику; IAM не спрашивал consumer'а — `data-integrity.md` §cross-domain п.4)
**And** `name`-зеркало в `ListGrantableResources` для `inst-zz` отсутствует (его уже нет у владельца), но это не ломает read binding'а (graceful degradation)

### Сценарий α-23: Delete — снятие binding'а каскадом убирает target-строки и per-object tuples

**ID:** `α-23`

**Given** binding `acb-5` c `target.resources=[inst-1, inst-2]` (2 per-object tuple), caller — owner

**When** caller вызывает `DELETE /iam/v1/accessBindings/acb-5` → poll Operation

**Then** Operation `done && !error`; binding удалён; **все** `access_binding_targets`-строки удалены (FK CASCADE same-DB, D-9 — не software-cascade)
**And** **оба** per-object FGA tuple'а удалены (revoke, как сегодняшний Delete; vault §Lifecycle); последующий `Get(acb-5)` → `NOT_FOUND`/`PERMISSION_DENIED` (existence-leak prevention, как сегодня)

---

## §B — UI: resource-first grant-форма с object-picker (target)

> α расширяет grant-форму (после 1.5 resource-first): после выбора scope + reusable-роли оператор выбирает **режим цели** (весь scope vs. конкретные объекты), и для «конкретные объекты» получает picker из `ListGrantableResources`.

### Сценарий α-06: Форма — выбор режима цели (all_in_scope vs. конкретные объекты)

**ID:** `α-06`

**Given** оператор на grant-форме (resource-first, 1.5): subject + тип ресурса + ресурс (scope) + reusable-роль выбраны

**When** форма отрендерила секцию «Цель»

**Then** доступны два режима: **«Весь scope»** (`all_in_scope`) и **«Конкретные объекты»** (`resources[]`)
**And** при «Конкретные объекты» появляется picker типа объекта (из closed-table) + multi-select объектов
**And** ветка selector в UI **не** показывается на α (forward-declared; не предлагается оператору)

### Сценарий α-07: Object-picker зовёт ListGrantableResources и рендерит серверный набор

**ID:** `α-07`

**Given** оператор выбрал scope `project:prj-P`, reusable-роль, режим «Конкретные объекты», тип объекта `compute.instance`

**When** picker открывается

**Then** форма делает **один** вызов `…:listGrantableResources?resourceType=project&resourceId=prj-P&objectType=compute.instance`
**And** picker рендерит **ровно** вернувшиеся объекты (id + name), без клиентской фильтрации scope/containment (вся логика серверная — паритет с 1.5 D-9)
**And** объекты чужого scope в picker'е отсутствуют (трассируется к α-14)
**And** submit отправляет `Create` c `target.resources=[выбранные ref…]` (α-01/α-02)

### Сценарий α-20: UI back-compat — существующая grant-форма без target работает (legacy путь)

**ID:** `α-20`

**Given** оператор использует grant-форму как до α (выбрал scope + роль, режим цели по умолчанию «Весь scope»)

**When** оператор сабмитит без явного выбора конкретных объектов

**Then** отправляется `Create` c `target.allInScope=true` (UI-дефолт = back-compat поведение, D-2/D-8)
**And** результат идентичен pre-α binding'у (tier-tuple); никакой регрессии существующего flow

---

## §J — Smoke / e2e (заказчик: финальная верификация, шаг 7)

### Сценарий α-21: e2e — per-object grant end-to-end + forward-only legacy (REST + gRPC + UI)

**ID:** `α-21`

**Given** развёрнутый стенд (`make dev-up`), bootstrap `acc-A` + `prj-P` + owner; reusable SYSTEM-роль; под `prj-P` инстансы `inst-1`, `inst-2`; **legacy** binding `acb-LEGACY`, созданный до α (concrete-`resourceName` в custom-роли ИЛИ wildcard-роль)

**When** owner вызывает `GET …:listGrantableResources?resourceType=project&resourceId=prj-P&objectType=compute.instance`
**Then** ответ содержит `inst-1`, `inst-2` (объекты под scope); чужих нет

**When** owner создаёт binding на `inst-1` (REST `POST accessBindings` c `target.resources=[{compute.instance,inst-1}]`, poll Operation)
**Then** Operation `done`; эмитится per-object tuple `compute_instance:inst-1#tier@subject`; `InternalIAMService.Check` на `inst-1` → allowed, на `inst-2` → НЕ allowed (точечность таргетинга)
**And** `grpcurl … AddTargetResources` на `inst-2` → Operation done → Check на `inst-2` → теперь allowed (set-мутация без пересоздания binding)
**And** `:removeTargetResources` на `inst-1` → Check на `inst-1` → больше НЕ allowed

**When** проверяется forward-only: `Get(acb-LEGACY)` / `ListByResource`
**Then** `acb-LEGACY` присутствует как раньше, проецируется как `target.allInScope=true` (D-8 backfill); его custom-роль НЕ перезаписана; `Delete(acb-LEGACY)` отзывает беспрепятственно (паритет 1.5 D-11)

**And** UI: grant-форма (resource-first) → выбор scope `prj-P` + роль + режим «Конкретные объекты» → picker рендерит `inst-1`/`inst-2` из `ListGrantableResources` → submit создаёт per-object binding; ветка selector в UI не предлагается

---

## 5. Открытые вопросы — ЗАКРЫТО

Открытых вопросов нет. Все ранее открытые (Q#A–Q#F) сняты родителем/ревьюером и
перенесены в §0 как зафиксированные дизайн-решения **D-15** (со ссылками на D-5/D-8/D-13/D-14):

- **Q#A/Q#C** (peer-existence/containment, новое ребро) → **D-5/D-14**: `target.id` — opaque soft-ref, без peer-call, без нового ребра; containment → γ.
- **Q#B** (уровень authority) → **D-15**: scope-level grant-authority (D-12) достаточен; per-object authority в α не требуется.
- **Q#D** (backfill) → **D-8/D-15**: read-time проекция (0 строк ⇒ `all_in_scope`), без migration-revoke.
- **Q#E** (форма target) → **D-15**: строго oneof, без смешения/fallback.
- **Q#F** (имя/префикс) → **D-15**: descriptor-стиль имени + `α-NN` приняты как есть.

---

## 6. Definition of Done (на каждую стадию)

Кросс-репо порядок (`polyrepo.md`): **proto → iam → api-gateway → ui → deploy → workspace(docs)**. Стадии — самостоятельные deliverable'ы; CI нижестоящего пиннит sibling к feature-ветке до merge вышестоящего.

**S1 — proto (`kacho-proto`):**
- [ ] `AccessTarget` (oneof `all_in_scope`/`resources`/`selector`) + `ResourceRef`/`ResourceRefList`/`ResourceSelector`(forward-declared каркас) + `AccessBinding.target = 16` (D-1/D-3, форма §2.1).
- [ ] RPC `AddTargetResources`/`RemoveTargetResources` (async→Operation) + `ListGrantableResources` (sync read) + request/response messages; REST `:addTargetResources`/`:removeTargetResources`/`:listGrantableResources`; permission/required_relation/scope_extractor(scope-полиморфный)/required_acr_min аннотации (D-12, паритет `ListByResource`/`ListAssignableRoles`).
- [ ] `buf lint` / `buf breaking` зелёные (additive field 16 + новые RPC — не breaking); `gen/go/...` регенерирован и закоммичен. Ревью — `proto-api-reviewer`.

**S2 — iam (`kacho-iam`):**
- [ ] RED integration-тесты (testcontainers) по α-01..α-24 первыми (α-05 изъят → γ), **включая α-19b (concurrent add/remove), α-22 (1.5 non-regression), α-24 (role-coverage), α-21 (forward-only legacy)** → подтверждён красный → GREEN.
- [ ] Миграция: дочерняя `access_binding_targets` (FK CASCADE same-DB, `UNIQUE(binding_id,type,id)`; D-9). Ревью — `db-architect-reviewer`. **Не редактировать применённые** (новая миграция, ban #5).
- [ ] Use-case `Create` принимает `target`: oneof-разбор → формат-валидация sync (`INVALID_ARGUMENT`: unknown type, malformed/`*`-id, пустой/конфликтный oneof; `UNIMPLEMENTED` selector — D-3/D-7) → **гейт (1) role-scope 1.5** (`IsRoleAssignable`, D-4) → **гейт (2) role-coverage** (`target.type` ⊆ `role.permissions`-типов, `Operation.error` FAILED_PRECONDITION — D-13, α-24) → `target.id` сохраняется как **opaque soft-ref БЕЗ peer-existence/containment** (D-5/D-14 — НЕТ peer-client, НЕТ ребра iam→compute/vpc) → INSERT binding + target-строки + per-object/tier FGA-эмиссия из target (D-6) **в одной writer-tx + outbox** (атомарно, ban #10).
- [ ] `AddTargetResources`/`RemoveTargetResources`: idempotent (ON CONFLICT DO NOTHING / DELETE; D-9); last-element guard (`FAILED_PRECONDITION`, D-10); add-к-all_in_scope reject (α-18); FGA per-object add/revoke в writer-tx.
- [ ] `ListGrantableResources`: scope-validate (D-12 authz) → objectType∈closed-table (D-3) → объекты под scope (output-only зеркало, D-11) → keyset `(created_at,id)`.
- [ ] **Concurrent-non-regression тест (testcontainers, ≥2 goroutine, α-19b):** конкурентные add/remove одного ref → ровно один эффект, без дублей/отрицательного состояния (`data-integrity.md` §within-service п.5 — обязателен, RED-first).
- [ ] **Forward-only (D-8):** legacy binding без target-строк проецируется как `all_in_scope` (read-time, без backfill-миграции — per Q#D); legacy concrete-`resourceName`-роли НЕ трогаются. Регресс-тест α-21.
- [ ] Error-mapping (`INVALID_ARGUMENT`/`FAILED_PRECONDITION`/`UNIMPLEMENTED`/`PERMISSION_DENIED`/`UNAUTHENTICATED`), без leak pgx. **`UNAVAILABLE` для target в α НЕ применяется** (нет peer-call — D-5/D-14).
- [ ] by-design D-1/D-4/D-5/D-6/D-8/D-10/D-13/D-14 — запись в `docs/architecture/` kacho-iam (target-в-binding; гейты role-scope ⊥ role-coverage, containment вынесен в γ; FGA resourceName из target; opaque soft-ref без peer-call; forward-only backfill).
- [ ] Ревью — `db-architect-reviewer` (`access_binding_targets` FK CASCADE/UNIQUE, idempotent add/remove), `go-style-reviewer`, `system-design-reviewer` (атомарность tuple-emission⊕binding в outbox-tx; **подтвердить, что α НЕ вводит ребра iam→compute/vpc** — ацикличность графа сохранена).

**S3 — api-gateway (`kacho-api-gateway`):**
- [ ] Регистрация **public** `AddTargetResources`/`RemoveTargetResources`/`ListGrantableResources` (allowlist + gRPC-director + REST mux на external) — НЕ Internal. Исполнение — `api-gateway-registrar`.
- [ ] permission-catalog entries (D-12) embedded; authz-middleware реальный Check (anti-anon + ACR floor; scope-полиморфный extractor).
- [ ] newman happy (α-01, α-02, α-03, α-14, α-18) + negative (α-08, α-09, α-10, α-11, α-13, α-17 sync-malformed, α-24 role-coverage) + parity/forward (α-21, α-22) через api-gateway, RED-first. _(α-05 containment — НЕ покрывается на α, перенесён в γ-acceptance.)_

**S4 — ui (`kacho-ui`):**
- [ ] `iamApi.listGrantableResources(...)` + `addTargetResources`/`removeTargetResources`-хелперы; типы `AccessTarget`/`ResourceRef`.
- [ ] grant-форма: секция «Цель» (режим all_in_scope vs. конкретные объекты, α-06); object-picker зовёт `listGrantableResources`, рендерит серверный набор (α-07); selector-ветка скрыта (α-06).
- [ ] back-compat: дефолт «Весь scope» = `allInScope:true` (α-20); UI-инварианты 1.5 (resource-first, named control, grid, tag-wrap) сохранены.
- [ ] UI-тесты (vitest/playwright) по α-06/α-07/α-20.

**S5 — deploy (`kacho-deploy`):** helm/compose без изменений (новые public RPC через существующий external endpoint); e2e-build-матрицы newman зелёные.

**S6 — workspace (docs/vault):** обновить vault `rpc/iam-access-binding-service.md` (3 новых RPC + Create-target дельта), `resources/iam-access-binding.md` (`target`-поле + `access_binding_targets` таблица + FGA-source = target + target.id opaque soft-ref), новый `resources/iam-access-binding-target.md` (если нужен узкий файл), KAC-trail; этот acceptance-док → статус APPROVED. **НЕ заводить `edges/iam-to-compute`/`iam-to-vpc`** — α НЕ вводит cross-domain ребра (peer-call отсутствует, D-5/D-14).

**Финальная верификация (перед merge каждой Go-стадии):** `go test ./... -race` + `golangci-lint run` + `govulncheck` + `make audit-list-filter` (новый `ListGrantableResources` должен фильтровать по grant-authority) + newman зелёные.

---

## 7. Выход / запреты

- Единственный артефакт этого шага — настоящий markdown. **Никакого кода** (ни `.go`, ни `.sql`, ни `.proto`).
- Описано только наблюдаемое поведение API/UI; DB-форма (`access_binding_targets`, индексы, idempotent add/remove) — забота `db-architect-reviewer`/`migration-writer`/`rpc-implementer`.
- **sub-phase 1.5 НЕ модифицируется** (D-4): `IsRoleAssignable`/`ListAssignableRoles`/Create role-scope-enforcement сохраняются; α добавляет ортогональный target-уровень.
- **Под-фазы β (IAM Tags) и γ (selector-материализация) — вне scope α**: `selector` лишь forward-declared в proto и reject'ится `UNIMPLEMENTED` (α-13). Tag-ресурсов α не вводит.
- Без сравнений с чужими облаками — конвенции Kachō нормативны (`api-conventions.md`).
- Координация после APPROVED: тикет/эпик KAC + `superpowers:writing-plans` → `integration-tester` (RED по α-NN) → `rpc-implementer` → `proto-api-reviewer` (proto) / `db-architect-reviewer` (`access_binding_targets`) / `system-design-reviewer` (outbox-атомарность tuple-emission⊕binding; подтвердить отсутствие ребра iam→compute/vpc — ацикличность) / `api-gateway-registrar` (public RPC) → заказчик: финальный smoke (§J α-21).
