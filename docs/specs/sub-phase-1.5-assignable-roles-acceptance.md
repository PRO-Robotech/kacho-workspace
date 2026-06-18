# Sub-phase 1.5 (IAM Assignable Roles — backend-driven grant form) — Acceptance

> **Статус:** ✅ APPROVED (`acceptance-reviewer`, 2026-06-18)
> **Дата:** 2026-06-18
> **Автор:** `acceptance-author`
> **Ревьюер:** `acceptance-reviewer` — ✅ APPROVED (все замечания закрыты: D-11 forward-only + 1.5-21, 1.5-12b concurrent, Q#3 async Operation.error; §5 резолюции зафиксированы)._
> **Эпик/тикет:** sub-phase 1.5 (no KAC ticket — tracked by acceptance doc + vault, MCP unavailable) (фича «backend-driven assignable roles для grant-формы AccessBinding»; затронутые репо — `kacho-proto` / `kacho-iam` / `kacho-api-gateway` / `kacho-ui` / `kacho-deploy` / `kacho-workspace`(docs). **Номер тикета проставляется до старта `superpowers:writing-plans`** — фича → тикет СНАЧАЛА, `git-youtrack.md`; в финальном APPROVED-артефакте `sub-phase 1.5 (no KAC ticket — tracked by acceptance doc + vault, MCP unavailable)` не остаётся.)
> **Источник требований (verbatim intent заказчика):** «logic of which roles are valid for a resource сейчас живёт во фронте — это диссонанс и неправильный слой. Перенести в backend: фронт тонкий, рендерит то, что вернул сервер. Форма grant переупорядочивается RESOURCE-FIRST (выбрал ресурс → роли). Backend computes validity, frontend renders.»
> **Ground-truth (сверено против кода 2026-06-18):**
> - `kacho-proto/proto/kacho/cloud/iam/v1/role.proto:9-64` — `Role{ id, account_id, name, description, permissions, is_system, created_at, cluster_id, organization_id(legacy), project_id }`; scope = **4-way XOR** через `cluster_id`/`organization_id`/`account_id`/`project_id`, НЕ enum-поле; prefix `rol-`.
> - `role_service.proto:33-37` — `RoleService.List` `<exempt>` (tenant-wide read), `filter` поддерживает только `is_system`/`account_id`/`name`; **нет** `project_id`/`scope`-фильтра; нет `ListByScope`/`ListSystem` вариантов.
> - `access_binding.proto:29-117` — `AccessBinding{ …, resource_type(string, НЕ enum), resource_id, scope(enum CLUSTER/ACCOUNT/PROJECT), status, … }`; scope-validation comment §97-109 (CLUSTER⇒`cluster`/`cluster_kacho_root`, ACCOUNT⇒`account`/`acc…`, PROJECT⇒`project`/`prj…`).
> - `access_binding_service.proto` — 7 RPC (`Get`/`ListByResource`/`ListBySubject`/`ListSubjectPrivileges`/`ListByAccount`/`ListOperations` sync; `Create`/`Delete` async→Operation). **`ListAssignableRoles` НЕ существует** (grep `assignable` по всему `iam/v1/` — 0 совпадений).
> - **kacho-iam `AccessBinding.Create` СЕГОДНЯ ПЕРМИССИВЕН по role-vs-resource scope** (`internal/apps/kacho/api/access_binding/create.go:66-88`): валидирует authenticated + `domain.AccessBinding.Validate()` (cluster-singleton, scope↔resource_id prefix) + `requireGrantAuthority`; роль читается ТОЛЬКО в async-worker'е `doCreate:161-169` и ТОЛЬКО для derivation FGA-relations из `role.Permissions`. **Нет ни одной ветки, сверяющей scope роли с ресурсом.** Единственный role-гейт — FK `access_bindings_role_fk` (existence, RESTRICT). См. §0 D-2.
> - `internal/repo/kacho/pg/role_repo.go:38` — `roleCols` **опускает** `cluster_id`/`project_id` → после любого read `domain.Role.ProjectID`/`ClusterID` пусты (impl-note для §6, не контракт).
> - `internal/domain/role.go:31-66` — `Role.Validate()` дублирует XOR (system⇒cluster_id only; custom⇒exactly one of account_id|project_id).
> - `internal/migrations/0008_drop_organizations.sql:47-64` — `roles_scope_xor` CHECK (org-ветка дропнута, KAC-223).
> - `internal/domain/constants_extended.go:24` — `ClusterSingletonID = "cluster_kacho_root"`; `internal/domain/types.go:71-95` — `validResourceTypes` (`cluster`/`account`/`project`/…/`*`).
> - `kacho-iam/internal/apps/kacho/api/access_binding/helpers.go:59-119` — `requireGrantAuthority(resource_type, resource_id)`: owner владеющего Account/Project ИЛИ FGA `admin` на scope-объект; `cluster` — только FGA `admin@cluster:cluster_kacho_root`.
> - `kacho-ui/src/components/iam/AccessBindingCreateForm.tsx` — форма **subject-first** (`subject_type→subject_id→role_ids→resource_type→resource_id`); грузит ВСЕ роли (`listRoles({pageSize:"1000"})`, :334-338) и партиционирует **только по `is_system`** (`isSystemRole`, RolePicker :124-145; `roleCascader.ts:26-82`) — **scope-фильтрации НЕТ**; reconcile (lockedSubject) пред-выбирает текущие DIRECT-роли через `listSubjectPrivileges` (:440-500) и применяет add→create / remove→revoke (:535-566); UI-инварианты — named `Form.Item name="role_ids"` + horizontal grid (labelCol 200px / maxWidth 720), flex-column tag-wrap (`minWidth:0`), full-name tags (`roleTagName`/`displayRender`).
> - `kacho-ui/src/components/resource-detail-extensions.tsx:263-312` — `privilegesExtension(subjType)` embeds форму в `childCreate` таба «Привилегии» User/SA/Group; `src/pages/system/ClusterAdminsPage.tsx:265` — deep-link `…/create?resource_type=cluster&resource_id=cluster_kacho_root&role_id=roles/admin`.
> **Образцы формата:** `sub-phase-1.3-iam-subject-privileges-acceptance.md`, `sub-phase-1.2-iam-operations-acceptance.md`, `sub-phase-vpc-redesign-kac239-acceptance.md`.

---

## Обзор

Логика «какие роли можно привязать к выбранному ресурсу» сегодня живёт во фронте grant-формы AccessBinding и при этом **неполна и не подкреплена бэкендом**:

1. **Frontend.** `AccessBindingCreateForm` грузит **все** роли (`listRoles`) и группирует их **только** по `is_system` (системные/кастомные) — никакой scope-фильтрации по выбранному ресурсу. Свежедобавленные (но не подключённые) хелперы `scopeOfRole`/`roleAccountId`/`roleProjectId` (`iam.ts`, dead-code) были попыткой решить это **в клиенте** — что и есть «диссонанс и неправильный слой».
2. **Backend.** `RoleService.List` over-the-wire возвращает **все** роли (`filter` по `is_system`/`account_id`/`name`; в handler даже эти не прокинуты) — нет endpoint'а «дай роли, валидные для (resource_type, resource_id)». А `AccessBinding.Create` **пермиссивен**: не сверяет scope роли с ресурсом вовсе. Значит, даже если фронт честно отфильтрует, прямой API-вызов / deep-link примет mis-scoped binding — контракт не держит инвариант.

Под-фаза **переносит логику валидности ролей в backend** и закрывает обе дыры:

- **Новый sync read-RPC** `AccessBindingService.ListAssignableRoles(resource_type, resource_id)` → возвращает **только** роли, валидные для этого ресурса, каждая аннотирована **серверно-вычисленным** `scope_group` (SYSTEM / ACCOUNT / PROJECT) — фронт группирует БЕЗ собственной логики.
- **Предикат валидности фиксируется как единый источник истины** (§0 D-2) и **энфорсится в `AccessBinding.Create`** — так список «можно привязать» (ListAssignableRoles) **строго совпадает** с тем, что Create принимает: UI не может предложить роль, которую Create отклонит, и обратно — никакой обход через прямой API.
- **Frontend становится тонким** (явная цель): форма переупорядочена RESOURCE-FIRST (Subject → Тип ресурса → Ресурс → Роли), после выбора ресурса зовёт `ListAssignableRoles` и рендерит ровно вернувшийся набор, сгруппированный по `scope_group`; вся клиентская scope-логика (включая dead-code хелперы и `is_system`-партицию) удаляется. Reconcile (вкладка «Привилегии»), submit (create per added / revoke per removed) и UI-инварианты сохраняются.

Документ описывает **только внешнее наблюдаемое поведение API и UI** (gRPC-коды, REST-формы, поведение экранов), не реализацию. Сценарии трассируются в имена integration- / newman- / UI-тестов через ID `1.5-<NN>`. Стандартные конвенции (`api-conventions.md`, `security.md`, `data-integrity.md`) нормативны и в тело не дублируются — только ссылками (§1).

---

## 0. Фиксированные дизайн-решения (предлагаются автором; подлежат approve ревьюером — затем НЕ переоткрывать)

| ID | Решение | Обоснование |
|---|---|---|
| **D-1** | **Новый RPC `AccessBindingService.ListAssignableRoles`** (sync read), размещён на **`AccessBindingService`** (не отдельный сервис, не `RoleService`). НЕ правка `RoleService.List`. | Assignable-roles — это проекция «какие роли можно **привязать** на ресурсе» — паритет с уже живущими на `AccessBindingService` `ListByResource`/`ListSubjectPrivileges` (тот же сервис, тот же authz-паттерн `requireGrantAuthority`). `RoleService.List` — generic role-каталог (`<exempt>`, tenant-wide), его контракт меняется неосознанно расширением; assignable-семантика resource-scoped и привязана к grant-authority, что неестественно для `RoleService`. Additive RPC, `buf breaking` зелёный. |
| **D-2** | **Предикат валидности ролей — ЕДИНЫЙ источник истины, общий для `ListAssignableRoles` И `AccessBinding.Create`.** Под-фаза вводит формальный предикат `isRoleAssignable(role, resource_type, resource_id)` (см. §2 матрица), который (a) `ListAssignableRoles` применяет как WHERE-фильтр; (b) `AccessBinding.Create` **начинает энфорсить** (сегодня пермиссивен — ground-truth `create.go`) → mis-scoped role → отклонение через **`Operation.error` с кодом `FAILED_PRECONDITION`** (async-контракт Create сохраняется, ban #9; см. D-7, Q#3). Enforcement — **forward-only**: гейтит только новые Create, не трогает legacy строки (см. **D-11**). Within-service list⇔create parity (D-2) **НЕ** выражается DB CHECK — это use-case JOIN-предикат (role-scope vs resource); детерминирован per role-row+resource (нет TOCTOU-окна, см. сценарий 1.5-12), концерн его недопущения — integration-тест на конкурентные Create (`data-integrity.md` §within-service / `testing.md`). | **Ключевое решение под-фазы.** Если ListAssignableRoles фильтрует, а Create — нет, то deep-link/прямой gRPC-вызов создаст binding, который UI бы не предложил → инвариант не держится, фронт «обещает» фильтр, которого нет на сервере. Перенос логики в backend = backend становится авторитетным: «что можно показать» == «что можно создать». Это within-`kacho_iam` инвариант (role и binding в одной схеме), но он не выразим чистым DB CHECK (role-scope vs resource — JOIN-предикат, не однострочный CHECK), поэтому энфорсится в use-case Create перед записью (см. §6 impl-note; FK existence остаётся DB-уровнем). |
| **D-3** | **Форма запроса.** `ListAssignableRolesRequest { string resource_type (required, ≤32), string resource_id (required, ≤64), int64 page_size (≤1000), string page_token (≤100) }`. `resource_type ∈ {"account","project","cluster"}` для v1. `resource_id` для cluster = `cluster_kacho_root` (singleton). | Паритет с `ListAccessBindingsByResourceRequest` (resource_type/resource_id). Cursor-pagination `(created_at,id)` ASC, opaque base64 `page_token`, `page_size` 0→default 50, max 1000 — как все list-RPC IAM (`api-conventions.md`). О пагинации для размера набора ролей — см. D-10. |
| **D-4** | **Форма ответа — обогащённая.** `ListAssignableRolesResponse { repeated AssignableRole roles = 1; string next_page_token = 2 }`, где `AssignableRole` — плоский message: `role_id` (rol-…), `name` (resolved role name), `description`, `is_system`, `scope_group` (enum `ScopeGroup` SYSTEM/ACCOUNT/PROJECT), `created_at`. **`scope_group` вычисляет сервер** из (is_system, account_id, project_id) роли (§2). Не включаются `permissions` (для grant-формы не нужны; крупный массив; assignable-список — это picker, не role-detail). | Заказчик: «фронт рендерит то, что вернул сервер, группирует без логики». `scope_group` — серверный групп-маркер: UI рисует секции «Системные / Account-роли / Project-роли» напрямую по полю, без чтения is_system/account_id/project_id. `name` resolved (фронт не зовёт `GET /roles/{id}` повторно). Только публично-безопасные поля роли (`security.md`); инфра-полей у Role нет, но `permissions` намеренно опущены (lean picker). |
| **D-5** | **AuthZ-tier — `requireGrantAuthority(resource_type, resource_id)`** (тот же gate, что и `AccessBinding.Create` на этом ресурсе): caller допускается, если он owner владеющего Account/Project ресурса ИЛИ держит FGA `admin` на scope-объекте (`account:<id>`/`project:<id>`/`cluster:cluster_kacho_root`). Иначе → `PERMISSION_DENIED`. Анонимный → отклоняется первым (`RequireAuthenticated`). Permission-catalog entry с `required_relation:"viewer"`, `scope_extractor{object_type:"project" from_request_field:"resource_id" object_type_from_request_field:"resource_type"}` + `required_acr_min:"2"` (паритет с `ListByResource`); **реальный gate — in-handler `requireGrantAuthority`** (catalog даёт ACR/anti-anon floor, точную авторизацию делает handler — как у `Create`/`ListByResource`). | **Симметрия с D-2.** «Кто может **привязать** роль на ресурсе» == «кому показываем assignable-роли на ресурсе». ListAssignableRoles — это «что я могу здесь грантить», и видеть его вправе ровно тот, кто может грантить (`requireGrantAuthority` — тот же набор, что решает Create). Viewer-only был бы слабее (любой viewer ресурса увидел бы grant-палитру, не имея права грантить — рассинхрон с UI-кнопкой «Добавить привилегии», скрытой по grant-authority, 1.3-D9). **NB для impl/reviewer:** scope-extractor в catalog — scope-полиморфный (как `ListByResource` после Bug A 2026-06-14, vault), чтобы account/cluster-scoped запрос не проверялся статически как `project:`. |
| **D-6** | **Malformed/unknown resource → sync `INVALID_ARGUMENT`** первым стейтментом RPC. (a) `resource_type` вне `{account,project,cluster}` (v1) → `InvalidArgument "Illegal argument resource_type (allowed: account\|project\|cluster)"`. (b) malformed `resource_id` (не подходит под prefix для типа: account⇒`acc`, project⇒`prj`; cluster⇒ровно `cluster_kacho_root`) → `InvalidArgument "invalid <res> id '<X>'"` / для cluster `InvalidArgument "Illegal argument resource_id (expected cluster_kacho_root)"`. | `api-conventions.md`: malformed id → sync InvalidArgument первым стейтментом; жёсткая привязка resource_id-prefix↔resource_type детерминирует контракт (паритет с `AccessBinding.Validate` cluster-singleton-guard, `access_binding.go:47-54`). |
| **D-7** | **Well-formed-но-несуществующий ресурс → `NOT_FOUND`** (НЕ empty-list). RPC `ListAssignableRoles` (sync read) резолвит ресурс (account/project существование within-`kacho_iam`; cluster — синглтон, всегда существует) → нет → синхронный `NOT_FOUND "Account acc-… not found"` / `"Project prj-… not found"`. Ресурс существует, но 0 assignable-ролей → пустой `roles` + пустой `next_page_token` (НЕ ошибка). **Mis-scoped role в `Create` (D-2 enforcement) → `FAILED_PRECONDITION` ЧЕРЕЗ `Operation.error`** (async — Create сохраняет единый async-контракт, ban #9; **НЕ** второй, sync, класс ошибки для того же RPC) с текстом вида `"role <id> is not assignable on <resource_type>:<resource_id>"`. Контрактная поверхность ошибки — **`Operation.error.code = FAILED_PRECONDITION`** (клиент поллит Operation → `done` → читает `error`). Sync pre-check предиката в use-case `Execute` ДОПУСТИМ как оптимизация (быстрый отказ до постановки Operation), но он **не меняет контракт**: контрактный класс/код/текст ошибки декларируется на `Operation.error`. | Existence-резолв нужен для authz (D-5 читает owner ресурса) → NotFound «бесплатен» и точнее, чем empty-list (паритет с `Get`-семантикой IAM «well-formed-но-нет → NotFound», и с D-6 под-фазы 1.3). Mis-scoped role — это **состояние** (роль из чужого scope), не формат → `FAILED_PRECONDITION` (`api-conventions.md`: «состояние ресурса не позволяет»). Surface на `Operation.error` (а не sync InvalidArgument/FailedPrecondition) — чтобы у одного RPC (`Create`) была **одна** error-поверхность, а не две конкурирующих (ban #9: мутации → Operation; sync pre-check — внутренняя оптимизация, не контракт). |
| **D-8** | **Custom role visibility = home-account ресурса (account-isolation).** ACCOUNT-scoped роль assignable на `account:<A>` **iff** `role.account_id == A`. PROJECT-scoped роль assignable на `project:<P>` **iff** `role.project_id == P`. SYSTEM-роли (is_system, cluster-scoped) assignable **всегда** (на любой account/project/cluster). На `cluster:cluster_kacho_root` — **только SYSTEM-роли**. (Полная матрица — §2.) | Custom-роли — scoped (DB `roles_scope_xor`); привязка кастом-роли из account B на ресурс account A была бы кросс-account leak / бессмыслица (роль не принадлежит этому tenancy). Account — tenancy-граница IAM. Это ровно то, что предотвращало бы клиентская логика — теперь авторитетно на сервере. |
| **D-9** | **UI: форма RESOURCE-FIRST + тонкий рендер.** Порядок `Form.Item`: **Subject (locked/selected) → Тип ресурса → Ресурс → Роли**. После выбора `resource_type`+`resource_id` форма зовёт `iamApi.listAssignableRoles(resource_type, resource_id)` и рендерит **ровно** вернувшийся набор, сгруппированный по серверному `scope_group` (секции «Системные» / «Account-роли» / «Project-роли»). **Удаляется вся клиентская scope-логика**: dead-code `scopeOfRole`/`roleAccountId`/`roleProjectId` (`iam.ts`), безусловный `listRoles({pageSize:"1000"})` как источник picker'а, `is_system`-партиция в RolePicker, scope/tree-building в `roleCascader.ts` (в части, делающей решения о валидности). Смена ресурса → ре-фетч assignable-ролей + **сброс уже выбранных ролей, ставших невалидными** для нового ресурса. **Сохраняются UI-инварианты:** named `Form.Item name="role_ids"`, horizontal grid (labelCol 200px / maxWidth 720), tag-wrap в колонке (`minWidth:0`), full-name tags. | Прямая реализация требования «фронт тонкий, рендерит серверный ответ, resource-first». `scope_group` убирает клиентское решение о группировке; assignable-набор убирает клиентское решение о валидности. Ре-фетч-на-смене-ресурса — естественное следствие resource-first (роли зависят от ресурса). |
| **D-10** | **Pagination: single-page допустима по умолчанию, но контракт cursor-paged.** RPC реализует cursor-пагинацию (D-3) для форм-паритета и forward-safety, НО для типового размера набора (system-роли ~десятки + custom account/project — единицы-десятки) UI запрашивает `page_size` достаточный для одной страницы (как `listRoles({pageSize:"1000"})` сегодня). Если набор превысит страницу — `next_page_token` непуст, UI дотягивает (или ограничивает picker, см. UI-план). | Паритет с прочими IAM list-RPC (cursor — стандарт `api-conventions.md`); single-page-в-UI — прагматика (picker, не бесконечный список), но контракт не закрывает дверь росту. Сценарий 1.5-04 покрывает paging на DB-уровне. |
| **D-11** | **D-2 enforcement — FORWARD-ONLY: гейтит ТОЛЬКО новые `Create`-вызовы; legacy mis-scoped bindings остаются валидны.** Сегодня `AccessBinding.Create` пермиссивен (ground-truth `create.go`) → в `kacho_iam` могут УЖЕ лежать активные mis-scoped bindings, созданные до 1.5 (напр. account-роль, привязанная к cluster; или роль чужого account'а). D-2 начинает энфорсить `isRoleAssignable` (§2) — но **строго forward-only**: (a) **НЕТ migration-time revoke** — никакой backfill-зачистки существующих строк; (b) **НЕТ read-time hiding** — `ListSubjectPrivileges` / `ListByResource` продолжают показывать legacy mis-scoped bindings как раньше; (c) `ListAssignableRoles` **НЕ ретро-фильтрует** уже-выданные bindings (он отвечает «что можно привязать СЕЙЧАС», не «что уже привязано»); (d) **`Delete`** существующего mis-scoped binding работает как прежде (revoke беспрепятственно). Enforcement касается **исключительно** новых `Create`-путей. | Граничный инвариант миграции пермиссивного гейта в строгий. Ретроактивный revoke/hide ломал бы текущий доступ операторов без их участия (silent privilege loss) и противоречил бы принципу graceful-деградации (`data-integrity.md` §cross-domain «consumer обязан грациозно переживать dangling-ref»): тот же дух — система **переживает** ранее-валидные-теперь-несоответствующие строки, не паникует и не вычищает их. Чистка legacy — отдельное осознанное решение (data-cleanup тикет), не побочный эффект включения enforcement. Симметрия read⇔create (D-2) — это про **новые** Create, а не про историю. |

---

## 1. Связь с регламентом (нормативно; в тело не дублируется)

| Регламент | Где соблюдается |
|---|---|
| `api-conventions.md` — read **sync**, мутации async `Operation`; Watch не существует (polling) | §A (`ListAssignableRoles` — sync read); grant — существующий async `AccessBinding.Create` (§D) |
| `api-conventions.md` — cursor pagination `(created_at,id)` ASC, `page_token` opaque base64, `page_size` 0→default(50), max 1000 | 1.5-04, D-10 |
| `api-conventions.md` — REST `/<service>/v1/<resource>`, suffix-action `:verb`; JSON camelCase (`resourceType`, `resourceId`, `roleId`, `scopeGroup`, `isSystem`, `createdAt`, `nextPageToken`, `pageToken`) | §A REST-форма, §J smoke |
| `api-conventions.md` — error-format gRPC-коды; malformed id → sync `INVALID_ARGUMENT` первым стейтментом; well-formed-но-нет → `NOT_FOUND`; состояние-не-позволяет → `FAILED_PRECONDITION` (для async `Create` — через `Operation.error`, ban #9) | 1.5-05, 1.5-06, 1.5-07, 1.5-12, 1.5-12b, 1.5-13 |
| `data-integrity.md` §within-service чек-лист п.5 — конкурентный спорный путь → integration-тест (testcontainers, ≥2 goroutine) | 1.5-12b (concurrent mis-scoped Create) |
| graceful forward-only миграция enforcement (паритет `data-integrity.md` §cross-domain «грациозно переживать dangling-ref») | D-11, 1.5-21 |
| `security.md` §AuthN+AuthZ ВЕЗДЕ — каждый RPC проходит per-RPC Check; read-RPC → catalog floor + handler-авторитетная точная политика (`requireGrantAuthority`); анонимный fail-closed | 1.5-03, 1.5-08 (deny), 1.5-09 (anon) |
| `security.md` §Internal-vs-external (ban #6) — RPC **публичный** (нужен tenant-UI на grant-форме), НЕ Internal; assignable = resource-scoped grant-палитра → public surface с handler-gate | §A (public external endpoint) |
| `security.md` §Инфра-чувствительные данные — публичная поверхность не светит инфра-поля | 1.5-11 (`AssignableRole` несёт только role_id/name/description/is_system/scope_group/created_at) |
| `data-integrity.md` §within-service — assignable-фильтр и Create-enforcement читают role-scope в той же `kacho_iam` (FK same-schema); единый предикат (D-2); concurrent-non-regression тест на спорный путь | D-2, 1.5-01, 1.5-12, 1.5-12b |
| `data-integrity.md` §cross-domain — НЕ вводит новых cross-domain edge: account/project/role/binding — все within `kacho_iam`; cluster-singleton — within | §6 (system-design-review подтверждает) |
| `00-kacho-core.md` ban #9 (мутации→Operation), #10 (within-DB инвариант), #12 (TDD), #1 (APPROVED перед кодом) | §A read-only sync; §D grant — существующий Operation-контракт (+D-2 enforcement); DoD §6 (RED→GREEN, integration+newman в том же PR) |
| `polyrepo.md` §порядок merge | §6 DoD: proto → iam → api-gateway → ui → deploy → workspace(docs) |

---

## 2. Предикат валидности ролей `isRoleAssignable` (единый источник истины — D-2)

> Это **нормативное** определение, общее для `ListAssignableRoles` (WHERE-фильтр) и `AccessBinding.Create` (enforcement). «Role R assignable на resource (type T, id ID)»:

Scope роли (ground-truth `roles_scope_xor`, `role.go`): ровно один признак —
**SYSTEM** (`is_system=true`, `cluster_id` set) · **ACCOUNT** (`is_system=false`, `account_id` set) · **PROJECT** (`is_system=false`, `project_id` set).

| resource_type | resource_id | SYSTEM role (is_system) | ACCOUNT-scoped role (account_id=X) | PROJECT-scoped role (project_id=Y) |
|---|---|---|---|---|
| `account` | `acc-A` | ✅ assignable (всегда) | ✅ **iff** `X == acc-A` | ❌ нет (project-роль не на account) |
| `project` | `prj-P` | ✅ assignable (всегда) | ❌ нет (account-роль НЕ якорится на project — STRICT, Q#1; см. примечание) | ✅ **iff** `Y == prj-P` |
| `cluster` | `cluster_kacho_root` | ✅ assignable (только SYSTEM) | ❌ нет | ❌ нет |

`scope_group` в ответе (D-4): SYSTEM-role → `SYSTEM`; ACCOUNT-scoped → `ACCOUNT`; PROJECT-scoped → `PROJECT`.

**Примечание по строке `project` × ACCOUNT-role (РЕШЕНО — Q#1 STRICT):** account-scoped кастом-роль на **проект внутри того же account'а** → **НЕ assignable** (строка `project` × ACCOUNT-role в матрице = ❌). Принята **строгая (STRICT) трактовка**: роль ↔ ровно свой scope-объект (account-роль только на свой `account`, project-роль только на свой `project`, system — везде). Hierarchy-down («account-роль валидна на проектах своего account») — additive follow-up отдельной под-фазы. **Важно:** role-scope (что валидно привязать) ≠ account→project authz-каскад (наследование прав при evaluation в FGA) — последний отдельный концерн, этой под-фазой не затрагивается. Решение зафиксировано (§5 Q#1); матрица выше и сценарий 1.5-02b отражают STRICT.

**Critical realism note (ground-truth):** сегодня публичный Role API минтит **только** account-scoped кастом-роли (`role/create.go`; `CreateRoleRequest` имеет лишь `account_id`), а seeds — только SYSTEM. PROJECT-scoped роли существуют лишь как схематическая возможность (никем не создаются через публичный путь). Поэтому в v1 строка PROJECT-role фактически пуста, но предикат и `scope_group=PROJECT` **определены** (forward-safe: когда project-scoped роли появятся, контракт уже корректен). Это не повод опускать PROJECT из матрицы.

---

## 3. Глоссарий: текущее состояние (ground-truth) и дельта

| Сущность | id-prefix | Текущее состояние | Дельта под-фазы |
|---|---|---|---|
| `AccessBindingService.ListAssignableRoles` | — | **НЕ существует** | **НОВЫЙ** sync read-RPC (§A) |
| `AccessBinding.Create` | — | LIVE, public, async→Operation; **пермиссивен по role-vs-resource scope** (только FK existence + grant-authority) | **D-2: начинает энфорсить `isRoleAssignable`** → mis-scoped → `FAILED_PRECONDITION` через `Operation.error` (async-контракт сохранён, §D); **forward-only** — legacy mis-scoped bindings не трогаются (D-11, 1.5-21) |
| `Role` | `rol` | flat: id/name/description/permissions/is_system/account_id/cluster_id/project_id (+ legacy `organization_id`); scope = 4-way XOR (`roles_scope_xor`, org-ветка дропнута) | источник `isRoleAssignable` (§2); legacy `organization_id` **игнорируется** `ScopeGroup` (Q#4); не меняется как ресурс |
| `RoleService.List` | — | LIVE, public `<exempt>`, возвращает ВСЕ роли (handler фильтры не прокинуты) | **НЕ меняется** (D-1) |
| `Account`/`Project` | `acc`/`prj` | flat; owner_user_id; `Get` within `kacho_iam` | читается для existence (D-7) + authz owner (D-5) |
| Cluster | `cluster_kacho_root` (singleton) | литеральный id, не Crockford | resource_type=cluster якорь; всегда существует |
| UI grant-форма `AccessBindingCreateForm` | — | subject-first; грузит все роли, партиция по `is_system`; нет scope-фильтра | **resource-first + thin render по `scope_group`** (§B); клиентская scope-логика удалена |
| UI хелперы `scopeOfRole`/`roleAccountId`/`roleProjectId` | — | dead-code (`iam.ts`, не подключены) | **удаляются** (логика на backend, D-9) |

---

## §A — Backend: новый RPC `AccessBindingService.ListAssignableRoles`

REST (public, external endpoint): `GET /iam/v1/accessBindings:listAssignableRoles?resourceType=<t>&resourceId=<id>&pageSize=&pageToken=`
gRPC: `kacho.cloud.iam.v1.AccessBindingService/ListAssignableRoles` (sync read — НЕ возвращает Operation).
JSON-ответ (camelCase): `{ "roles": [ { "roleId","name","description","isSystem","scopeGroup","createdAt" } ], "nextPageToken": "" }`.

### Сценарий 1.5-01: Happy path — account-ресурс отдаёт SYSTEM + свои ACCOUNT-роли, с scope_group

**ID:** `1.5-01`

**Given** существует account `acc-A` (owner `usr-OWNER`)
**And** в каталоге есть SYSTEM-роли (`is_system=true`, cluster-scoped), напр. `rol-sysadmin` (name «iam.admin»), `rol-sysviewer` (name «iam.viewer»)
**And** в `acc-A` создана ACCOUNT-scoped кастом-роль `rol-accustom` (name «my-account-role», `account_id=acc-A`)
**And** в **другом** account `acc-B` есть ACCOUNT-scoped кастом-роль `rol-bcustom` (`account_id=acc-B`)
**And** caller — `usr-OWNER` (owner `acc-A`)

**When** caller вызывает `GET /iam/v1/accessBindings:listAssignableRoles?resourceType=account&resourceId=acc-A`

**Then** sync-ответ `200 OK`, gRPC `OK`
**And** `roles` содержит SYSTEM-роли с `scopeGroup="SYSTEM"`, `isSystem=true`, resolved `name`
**And** `roles` содержит `rol-accustom` с `scopeGroup="ACCOUNT"`, `isSystem=false`, `name="my-account-role"`
**And** `roles` **НЕ** содержит `rol-bcustom` (чужой account — D-8 account-isolation)
**And** упорядочено по `(createdAt, id)` ASC; `nextPageToken=""`

### Сценарий 1.5-02: Happy path — project-ресурс отдаёт SYSTEM + PROJECT-роли проекта

**ID:** `1.5-02`

**Given** account `acc-A` с проектом `prj-P` (owner `usr-OWNER`)
**And** существуют SYSTEM-роли
**And** (если в каталоге появилась) PROJECT-scoped роль `rol-pcustom` (name «my-project-role», `project_id=prj-P`)
**And** caller — owner `acc-A`/`prj-P`

**When** caller вызывает `…:listAssignableRoles?resourceType=project&resourceId=prj-P`

**Then** `200 OK`; `roles` содержит SYSTEM-роли (`scopeGroup="SYSTEM"`)
**And** содержит `rol-pcustom` с `scopeGroup="PROJECT"` (если такая роль существует; §2 critical-note — в v1 PROJECT-роли публично не минтятся, тогда `roles` = только SYSTEM, что валидно)
**And** **НЕ** содержит PROJECT-роль другого проекта и **НЕ** содержит ACCOUNT-scoped кастом-роль `acc-A` (STRICT, Q#1 РЕШЕНО; см. 1.5-02b)

### Сценарий 1.5-02b: Edge/conformance — account-scoped роль НЕ assignable на проект (STRICT, Q#1 РЕШЕНО)

**ID:** `1.5-02b`

**Given** account `acc-A` с проектом `prj-P` и ACCOUNT-scoped кастом-ролью `rol-accustom` (`account_id=acc-A`)
**And** caller — owner `acc-A`

**When** caller вызывает `…:listAssignableRoles?resourceType=project&resourceId=prj-P`

**Then** `roles` **НЕ** содержит `rol-accustom` (account-роль не якорится на project — STRICT, §2/Q#1 РЕШЕНО)
**And** _Примечание:_ hierarchy-down («account-роль валидна на проектах своего account») — additive follow-up отдельной под-фазы, в v1 не реализуется (Q#1 зафиксирован как STRICT, §5).

### Сценарий 1.5-03: Happy path — cluster-ресурс отдаёт ТОЛЬКО SYSTEM-роли

**ID:** `1.5-03`

**Given** SYSTEM-роли в каталоге + ACCOUNT/PROJECT-кастом-роли где-либо
**And** caller — cluster-admin (FGA `admin@cluster:cluster_kacho_root`)

**When** caller вызывает `…:listAssignableRoles?resourceType=cluster&resourceId=cluster_kacho_root`

**Then** `200 OK`; `roles` содержит **только** SYSTEM-роли (`scopeGroup="SYSTEM"`)
**And** ни одна кастом-роль (ACCOUNT/PROJECT) не присутствует (§2 — cluster ⇒ только SYSTEM)

### Сценарий 1.5-04: Pagination — page_size=1 отдаёт страницу + курсор; вторая страница — остаток

**ID:** `1.5-04`

**Given** на `acc-A` assignable ≥2 роли (SYSTEM + ACCOUNT), caller — owner

**When** caller вызывает `…:listAssignableRoles?resourceType=account&resourceId=acc-A&pageSize=1`

**Then** `roles` содержит 1 элемент (первый по `(createdAt,id)` ASC); `nextPageToken` — непустой opaque base64

**When** caller повторяет с `&pageToken=<nextPageToken>` (тот же `pageSize=1`)

**Then** `roles` содержит следующий элемент; в конце `nextPageToken=""`

### Сценарий 1.5-05: Negative — unknown resource_type → INVALID_ARGUMENT (sync)

**ID:** `1.5-05`

**Given** аутентифицированный caller

**When** caller вызывает `…:listAssignableRoles?resourceType=instance&resourceId=epd-XXXX`

**Then** gRPC `INVALID_ARGUMENT`, REST `400`, message `"Illegal argument resource_type (allowed: account|project|cluster)"` (v1; D-6)
**And** ответ синхронный, до обращения к репозиторию

### Сценарий 1.5-06: Negative — malformed resource_id (prefix↔type mismatch) → INVALID_ARGUMENT

**ID:** `1.5-06`

**Given** аутентифицированный caller

**When** caller вызывает `…:listAssignableRoles?resourceType=account&resourceId=not-a-valid-id`

**Then** gRPC `INVALID_ARGUMENT`, message `"invalid account id 'not-a-valid-id'"` (D-6)

**When** caller вызывает `…:listAssignableRoles?resourceType=cluster&resourceId=cluster-wrong`

**Then** gRPC `INVALID_ARGUMENT`, message `"Illegal argument resource_id (expected cluster_kacho_root)"` (cluster-singleton guard, D-6)

**When** caller вызывает `…:listAssignableRoles?resourceType=account&resourceId=prj-XXXXXXXXXXXXXXXXX` (валидный project-id под resource_type=account)

**Then** gRPC `INVALID_ARGUMENT`, message `"invalid account id 'prj-…'"` (prefix↔type mismatch, D-6)

### Сценарий 1.5-07: Negative — well-formed-но-несуществующий ресурс → NOT_FOUND

**ID:** `1.5-07`

**Given** аутентифицированный account-admin caller
**And** не существует Account с id `acc-GHOSTAAAAAAAAAAA` (well-formed prefix `acc`)

**When** caller вызывает `…:listAssignableRoles?resourceType=account&resourceId=acc-GHOSTAAAAAAAAAAA`

**Then** gRPC `NOT_FOUND`, REST `404`, message `"Account acc-GHOSTAAAAAAAAAAA not found"` (D-7 — existence-резолв нужен для authz)
**And** аналогично `resourceType=project` с несуществующим `prj-…` → `"Project prj-… not found"`

### Сценарий 1.5-08: AuthZ — caller без grant-authority на ресурс → PERMISSION_DENIED

**ID:** `1.5-08`

**Given** account `acc-A` (owner `usr-OWNER`) и **другой** account `acc-B` (owner `usr-B`)
**And** caller — `usr-B` (ни owner `acc-A`, ни FGA `admin@account:acc-A`)

**When** caller вызывает `…:listAssignableRoles?resourceType=account&resourceId=acc-A`

**Then** gRPC `PERMISSION_DENIED`, REST `403` (D-5 — `requireGrantAuthority` на `acc-A` не проходит)
**And** в ответе **нет** утечки role-каталога `acc-A`

### Сценарий 1.5-09: Negative — анонимный caller → fail-closed

**ID:** `1.5-09`

**Given** запрос без валидного principal (анонимный)

**When** вызывается `…:listAssignableRoles?resourceType=account&resourceId=acc-A`

**Then** запрос отклоняется fail-closed (gRPC `UNAUTHENTICATED`/`PERMISSION_DENIED`; REST `401`/`403` — `RequireAuthenticated`), **до** возврата данных

### Сценарий 1.5-10: Edge — ресурс существует, 0 assignable-ролей → пустой список (не ошибка)

**ID:** `1.5-10`

**Given** свежий стенд **без** seed SYSTEM-ролей (теоретический edge) ИЛИ account, где applicable-набор пуст
**And** caller — owner ресурса

**When** caller вызывает `…:listAssignableRoles?resourceType=account&resourceId=acc-A`

**Then** `200 OK`, `roles=[]` (пустой массив), `nextPageToken=""` (существующий ресурс с 0 assignable ≠ NotFound, D-7)

### Сценарий 1.5-11: Conformance — `AssignableRole` несёт только публично-безопасные поля + scope_group вычислен сервером

**ID:** `1.5-11`

**Given** assignable-роль `rol-accustom` на `acc-A` (как 1.5-01)

**When** caller (owner) читает её через `…:listAssignableRoles`

**Then** элемент содержит **только**: `roleId`, `name`, `description`, `isSystem`, `scopeGroup`, `createdAt`
**And** `scopeGroup` присутствует и вычислен сервером (`ACCOUNT` для `rol-accustom`, `SYSTEM` для system-роли) — клиент не вычисляет scope
**And** ответ **не** содержит `permissions`, инфра-чувствительных полей, и не требует отдельного `GET /roles/{id}` для `name` (D-4)

### Сценарий 1.5-12: Conformance — `AssignableRole` set == то, что принимает `AccessBinding.Create` (D-2 единый предикат)

**ID:** `1.5-12`

**Given** account `acc-A` (owner `usr-OWNER`), ACCOUNT-scoped роль `rol-accustom` (`account_id=acc-A`), и чужая ACCOUNT-роль `rol-bcustom` (`account_id=acc-B`)
**And** caller — owner `acc-A`

**When** caller вызывает `…:listAssignableRoles?resourceType=account&resourceId=acc-A`
**Then** `rol-accustom` присутствует, `rol-bcustom` отсутствует

**When** caller вызывает `POST /iam/v1/accessBindings` с `{subjectType:"user", subjectId:"usr-M", roleId:"rol-accustom", resourceType:"account", resourceId:"acc-A"}` → poll Operation
**Then** Operation `done && !error` (assignable → Create принимает)

**When** caller вызывает `POST /iam/v1/accessBindings` с `{…, roleId:"rol-bcustom", resourceType:"account", resourceId:"acc-A"}` (НЕ assignable — чужой account) → poll Operation
**Then** Operation завершается `error.code = FAILED_PRECONDITION` (через `Operation.error`, async-контракт Create сохранён — ban #9, Q#3), message `"role rol-bcustom is not assignable on account:acc-A"` (D-2 enforcement — Create начинает энфорсить `isRoleAssignable`; binding не создан)
**And** integration-тест подтверждает: **тот же предикат** даёт «нет в ListAssignableRoles» ⇔ «отклонено в Create» (нет пути обхода через прямой API)

### Сценарий 1.5-12b: Concurrency — два конкурентных Create с mis-scoped ролью → ОБА отклонены (нет TOCTOU-окна)

**ID:** `1.5-12b`

**Given** account `acc-A` (owner `usr-OWNER`), чужая ACCOUNT-роль `rol-bcustom` (`account_id=acc-B`) — НЕ assignable на `account:acc-A` (D-8)
**And** caller — owner `acc-A`

**When** caller запускает **две конкурентные** `POST /iam/v1/accessBindings` с одинаковым `{…, roleId:"rol-bcustom", resourceType:"account", resourceId:"acc-A"}` (разные subjectId или один — обе с mis-scoped ролью) → poll обе Operation

**Then** **ОБЕ** Operation завершаются `error.code = FAILED_PRECONDITION` (`"role rol-bcustom is not assignable on account:acc-A"`); **ни один** binding не создан — нет окна, где одна из конкурентных Create «проскакивает» enforcement
**And** _Обоснование контракта (для `integration-tester`/`db-architect-reviewer`):_ предикат `isRoleAssignable` **детерминирован per role-row + resource** — он читает scope роли (immutable после Create роли) и тип/id ресурса, не зависит от наблюдаемого состояния других bindings, поэтому TOCTOU-окна нет by-design и **DB-конструкция (CHECK/CAS) не требуется**. НО list⇔create parity (D-2) — within-service инвариант, НЕ выраженный DB CHECK (use-case JOIN-предикат), поэтому **concurrent-non-regression integration-тест (testcontainers, ≥2 goroutine) ОБЯЗАН быть написан явно** (`data-integrity.md` §within-service чек-лист п.5 / `testing.md`): подтвердить, что при конкурентных mis-scoped Create оба rejection детерминированы и ни один binding не записан. Этот тест планируется в S2 DoD, чтобы `integration-tester` его реализовал (RED-first).

### Сценарий 1.5-13: Negative — mis-scoped role на cluster через Create → FAILED_PRECONDITION

**ID:** `1.5-13`

**Given** cluster-admin caller; ACCOUNT-scoped роль `rol-accustom`

**When** caller вызывает `POST /iam/v1/accessBindings` с `{…, roleId:"rol-accustom", resourceType:"cluster", resourceId:"cluster_kacho_root"}` → poll Operation

**Then** Operation завершается `done && error.code = FAILED_PRECONDITION` (ошибка через `Operation.error` — Create сохраняет async-контракт, ban #9 / Q#3; одна error-поверхность), message `"role rol-accustom is not assignable on cluster:cluster_kacho_root"` (§2 — cluster ⇒ только SYSTEM; D-2); binding не создан
**And** `…:listAssignableRoles?resourceType=cluster&resourceId=cluster_kacho_root` НЕ содержал `rol-accustom` (паритет предиката)

---

## §B — UI: resource-first grant-форма + thin render по scope_group

### Сценарий 1.5-14: Форма RESOURCE-FIRST — порядок полей Subject → Тип ресурса → Ресурс → Роли

**ID:** `1.5-14`

**Given** оператор открыл grant-форму (standalone `/iam/access-bindings/create` или embedded в табе «Привилегии»)

**When** форма отрендерилась

**Then** поля `Form.Item` идут в порядке: **Subject** (тип + id) → **Тип ресурса** → **Ресурс** → **Роли**
**And** поле «Роли» **пусто/disabled**, пока не выбран ресурс (роли зависят от ресурса)
**And** сохранены UI-инварианты: named `Form.Item name="role_ids"`, horizontal grid (label 200px / maxWidth 720), tag-wrap в колонке, full-name tags

### Сценарий 1.5-15: После выбора ресурса форма зовёт ListAssignableRoles и рендерит серверный набор по scope_group

**ID:** `1.5-15`

**Given** оператор-owner `acc-A` на форме, subject выбран

**When** оператор выбирает `Тип ресурса = account`, `Ресурс = acc-A`

**Then** форма делает **один** вызов `…:listAssignableRoles?resourceType=account&resourceId=acc-A`
**And** picker ролей рендерит **ровно** вернувшиеся роли, сгруппированные по серверному `scopeGroup`: секции «Системные» (SYSTEM) / «Account-роли» (ACCOUNT) / «Project-роли» (PROJECT, если есть)
**And** UI **не** грузит весь `listRoles` для picker'а и **не** выполняет клиентскую scope-фильтрацию/группировку (вся логика — серверная, D-9)
**And** роли чужого account'а в picker'е отсутствуют (трассируется к 1.5-01)

### Сценарий 1.5-16: Смена ресурса → ре-фетч assignable + сброс ставших невалидными выбранных ролей

**ID:** `1.5-16`

**Given** оператор выбрал `account:acc-A`, picker показал роли, оператор отметил `rol-accustom` (ACCOUNT-роль `acc-A`)

**When** оператор меняет ресурс на `project:prj-P` (того же account'а)

**Then** форма ре-фетчит `…:listAssignableRoles?resourceType=project&resourceId=prj-P`
**And** picker обновляется на assignable-набор `prj-P`
**And** ранее выбранная `rol-accustom`, если она **не** assignable на `prj-P` (STRICT, Q#1 — account-роль не на project), **сбрасывается** из выбранных (не остаётся «висящей» невалидной роли в payload)
**And** SYSTEM-роли, выбранные ранее, остаются (они assignable на оба ресурса)

### Сценарий 1.5-17: Reconcile (embedded таб «Привилегии») — пред-выбор текущих ролей сохранён

**ID:** `1.5-17`

**Given** оператор-owner `acc-A` на табе «Привилегии» `usr-MEMBER` (lockedSubject), у которого есть DIRECT-binding role `rol-accustom` на `account:acc-A`

**When** оператор открывает grant-форму и выбирает ресурс `account:acc-A`

**Then** форма пред-выбирает текущие DIRECT-роли субъекта на этом ресурсе (через существующий `listSubjectPrivileges`, как сегодня — поведение reconcile не меняется)
**And** assignable-набор (новый `listAssignableRoles`) и пред-выбранные текущие роли совместно корректны: пред-выбранная роль присутствует в picker'е (она была assignable, раз binding существует)

### Сценарий 1.5-18: Submit reconcile — create per added / revoke per removed (поведение не меняется)

**ID:** `1.5-18`

**Given** на табе «Привилегии» `usr-MEMBER`, ресурс `account:acc-A`, пред-выбрана `rol-accustom`; оператор добавляет SYSTEM-роль `iam.viewer` и снимает `rol-accustom`

**When** оператор сабмитит форму

**Then** UI делает `POST /iam/v1/accessBindings` для добавленной (`iam.viewer`) и `DELETE /iam/v1/accessBindings/{bindingId}` для снятой (`rol-accustom`) — существующее reconcile-поведение, не меняется
**And** каждая мутация — async `Operation`, UI поллит до `done`; 409 ALREADY_EXISTS на create трактуется как success (существующее поведение)
**And** при успехе таб «Привилегии» рефетчит список (трассируется к `listSubjectPrivileges`)

### Сценарий 1.5-19: Back-compat — standalone deep-link (lock_subject) и cluster-admin deep-link работают

**ID:** `1.5-19`

**Given** существующий cluster-admin deep-link `…/access-bindings/create?resource_type=cluster&resource_id=cluster_kacho_root&role_id=roles/admin` (`ClusterAdminsPage.tsx:265`)

**When** оператор переходит по нему

**Then** форма открывается с пресетом ресурса `cluster:cluster_kacho_root`
**And** форма зовёт `…:listAssignableRoles?resourceType=cluster&resourceId=cluster_kacho_root` → picker показывает **только** SYSTEM-роли (1.5-03)
**And** пресет роли применяется, если она входит в assignable-набор (system `admin` — входит); subject-lock (`lock_subject=1`) и пресет subject продолжают работать (поведение 1.3-D9 не регрессирует)

---

## §J — Smoke / e2e (заказчик: финальная верификация, шаг 7)

### Сценарий 1.5-20: e2e — assignable-set ⇔ Create-accept parity end-to-end (REST + gRPC)

**ID:** `1.5-20`

**Given** развёрнутый стенд (`make dev-up`), bootstrap account `acc-A` + owner, seed SYSTEM-роли, кастом-роль `rol-accustom` в `acc-A`
**When** owner вызывает `GET /iam/v1/accessBindings:listAssignableRoles?resourceType=account&resourceId=acc-A`
**Then** ответ содержит SYSTEM-роли (`scopeGroup=SYSTEM`) + `rol-accustom` (`scopeGroup=ACCOUNT`), без чужих ролей
**And** `grpcurl … AccessBindingService/ListAssignableRoles` даёт эквивалентный набор (REST/gRPC parity)
**And** owner создаёт binding `rol-accustom` на `acc-A` (REST `POST`, poll Operation) → done; попытка binding чужой роли на `acc-A` → Operation `done && error.code=FAILED_PRECONDITION` (через `Operation.error`, 1.5-12 parity)
**And** UI: на grant-форме (resource-first) выбор `account:acc-A` рендерит ровно этот набор по группам, чужие роли не предлагаются

### Сценарий 1.5-21: Edge/back-compat — legacy mis-scoped binding (pre-1.5) переживает включение enforcement (forward-only, D-11)

**ID:** `1.5-21`

**Given** в `kacho_iam` существует **активный** AccessBinding `acb-LEGACY`, созданный **до 1.5** (когда `Create` был пермиссивен), c **mis-scoped** ролью — напр. ACCOUNT-scoped роль `rol-accustom` (`account_id=acc-A`), привязанная к `cluster:cluster_kacho_root` (по §2 — НЕ assignable: cluster ⇒ только SYSTEM), ЛИБО роль чужого account'а `rol-bcustom` (`account_id=acc-B`), привязанная к `account:acc-A`
**And** под-фаза 1.5 задеплоена (D-2 enforcement активен; **БЕЗ** migration-time revoke — D-11)
**And** caller — owner/cluster-admin с grant-authority на соответствующий ресурс

**When** caller читает binding'и ресурса через `GET /iam/v1/accessBindings:listByResource?resourceType=cluster&resourceId=cluster_kacho_root` (и/или `…:listSubjectPrivileges` субъекта `acb-LEGACY`)

**Then** `200 OK`; `acb-LEGACY` **присутствует** в выдаче как и раньше — read-time hiding отсутствует, паники нет (D-11 b: enforcement не трогает legacy на чтении)
**And** `…:listAssignableRoles?resourceType=cluster&resourceId=cluster_kacho_root` **не** содержит `rol-accustom` (он не assignable «сейчас») — но это **никак не влияет** на отображение уже-существующего `acb-LEGACY` (ListAssignableRoles ≠ ретро-фильтр выданных bindings, D-11 c)

**When** caller вызывает `DELETE /iam/v1/accessBindings/acb-LEGACY` → poll Operation

**Then** Operation `done && !error` — legacy mis-scoped binding **успешно отзывается** как раньше (D-11 d: Delete не гейтится enforcement'ом)
**And** integration-тест подтверждает: enforcement `isRoleAssignable` срабатывает **только** на новом `Create`-пути; pre-1.5 строки (read через ListByResource/ListSubjectPrivileges, revoke через Delete) ведут себя идентично pre-1.5 — forward-only, никакого backfill/migration-revoke/read-hide (D-11). Граничный паритет с graceful dangling-ref правилом (`data-integrity.md` §cross-domain).

---

## 5. Резолюции дизайн-вопросов (зафиксированы ревьюером на APPROVED — НЕ переоткрывать)

> Эти вопросы **разрешены** на ревью acceptance-дока и зафиксированы как обязательные решения под-фазы. Не переоткрывать в коде/плане — изменение любого из них требует новой ревизии acceptance-дока (`acceptance-author` → `acceptance-reviewer`).

| # | Решение (РЕЗОЛЮЦИЯ) | Обоснование |
|---|---|---|
| **Q#1 (РЕШЕНО)** | **STRICT scope-match.** `project`-ресурс: account-scoped роль assignable **ТОЛЬКО** на свой `account`, **НЕ** на его проекты (никакого hierarchy-down в v1). Role ↔ ровно свой scope-объект (account-роль → `account:<own>`; project-роль → `project:<own>`; system → везде). | Минимально и однозначно. Hierarchy-down («account-роль валидна на проектах своего account») — additive follow-up (отдельная под-фаза). **Важно:** role-scope (что валидно привязать) — это НЕ то же, что account→project authz-каскад (наследование прав по иерархии при evaluation) — последний живёт в authz-слое (FGA) и отдельным решением не затрагивается этой под-фазой. §2 / 1.5-02b написаны под STRICT. |
| **Q#2 (РЕШЕНО)** | **NO permissions в `AssignableRole`** (lean picker). `AssignableRole` несёт только `role_id`/`name`/`description`/`is_system`/`scope_group`/`created_at` (D-4, 1.5-11). | Grant-форме для выбора нужны id/name/scope_group, не permission-массив (крупный, picker ≠ role-detail). Если UI понадобится tooltip с permissions — additive `RoleService.Get` per-row или follow-up поле, вне scope 1.5. |
| **Q#3 (РЕШЕНО)** | **Create scope-enforcement surface = `Operation.error` (async), код `FAILED_PRECONDITION`.** Create сохраняет **единый async-контракт** (ban #9) — нет второго, sync, класса ошибки для одного RPC. Sync pre-check предиката в use-case `Execute` ДОПУСТИМ как оптимизация, но **контрактная** error-поверхность — `Operation.error.code = FAILED_PRECONDITION` (клиент поллит Operation → `done` → `error`). | mis-scope — это **состояние** (роль из чужого scope), не формат запроса → `FAILED_PRECONDITION` (`api-conventions.md`). Поверхность на `Operation.error` — чтобы у `Create` была ОДНА error-поверхность, а не две конкурирующих (D-7, 1.5-12/1.5-12b/1.5-13). |
| **Q#4 (РЕШЕНО)** | **`ScopeGroup = {SCOPE_GROUP_UNSPECIFIED, SYSTEM, ACCOUNT, PROJECT}`** — **без ORGANIZATION.** Org-ветка дропнута на DB-уровне (migration `0008_drop_organizations.sql`, `roles_scope_xor` без org). | proto `Role` всё ещё несёт legacy-поле `organization_id` (ground-truth `role.proto`), но `ScopeGroup`/`isRoleAssignable` его **игнорируют** (org-scope не минтится, не валиден). Возврат ORGANIZATION — только при возврате домена Organization (вне scope). |
| **Q#5 (РЕШЕНО)** | **RPC на `AccessBindingService`, REST `accessBindings:listAssignableRoles`** (НЕ `RoleService`, НЕ `roles:assignable`). | D-1: паритет `ListByResource`/`ListSubjectPrivileges` (тот же сервис, тот же authz `requireGrantAuthority`). `roles:assignable` подразумевал бы `RoleService` (generic-каталог, `<exempt>`) — неверный authz-слой. |

---

## 6. Definition of Done (на каждую стадию)

Кросс-репо порядок (`polyrepo.md`): **proto → iam → api-gateway → ui → deploy → workspace(docs)**. Стадии — самостоятельные deliverable'ы; CI нижестоящего пиннит sibling к feature-ветке до merge вышестоящего.

**S1 — proto (`kacho-proto`):**
- [ ] `ListAssignableRoles` RPC + `ListAssignableRolesRequest`/`Response` + `AssignableRole` message + `ScopeGroup` enum (`SCOPE_GROUP_UNSPECIFIED/SYSTEM/ACCOUNT/PROJECT`) в `access_binding_service.proto`/`access_binding.proto` (форма D-3/D-4).
- [ ] gRPC sync-read (НЕ Operation); REST `GET …:listAssignableRoles`; permission/required_relation(`viewer`)/scope_extractor(scope-полиморфный)/required_acr_min аннотации (D-5).
- [ ] `buf lint` / `buf breaking` зелёные; `gen/go/...` регенерирован и закоммичен. Ревью — `proto-api-reviewer`.

**S2 — iam (`kacho-iam`):**
- [ ] RED integration-тесты (testcontainers) по сценариям 1.5-01..13, **1.5-12b (concurrent), 1.5-21 (forward-only legacy)** первыми → подтверждён красный → GREEN.
- [ ] Use-case `ListAssignableRoles`: resource_type↔resource_id validate (D-6) → existence-резолв (D-7, NotFound) → authz `requireGrantAuthority` (D-5) → repo фильтр ролей по `isRoleAssignable` (§2, keyset `(created_at,id)` ASC) → `scope_group` derivation (D-4). `ScopeGroup` игнорирует legacy `organization_id` (Q#4).
- [ ] **D-2 enforcement в `AccessBinding.Create`**: `isRoleAssignable(role, resource_type, resource_id)` проверяется перед записью binding → mis-scoped → **`FAILED_PRECONDITION` через `Operation.error`** (Q#3 — async-контракт сохранён, ban #9; sync pre-check в `Execute` допустим как оптимизация, но контрактная поверхность = `Operation.error`; код+текст+«не создан»). **Единый предикат** разделяется ListAssignableRoles и Create (один пакет/функция в `kacho-iam`, не дубль). impl-note: `roleCols` (`role_repo.go:38`) **расширить** на `cluster_id`/`project_id` (сейчас опущены → scope не читается); регресс-тест существующих role-read.
- [ ] **D-11 forward-only:** enforcement гейтит ТОЛЬКО новые `Create`; **НЕТ** migration-time revoke, **НЕТ** read-time hiding. Регресс-тест: pre-1.5 mis-scoped binding читается через `ListByResource`/`ListSubjectPrivileges` и отзывается через `Delete` как раньше (1.5-21).
- [ ] **Concurrent-non-regression тест (testcontainers, ≥2 goroutine, 1.5-12b):** два конкурентных mis-scoped `Create` → ОБА `FAILED_PRECONDITION`, ни один binding не записан (`data-integrity.md` §within-service п.5 — обязателен, RED-first). Предикат детерминирован per role-row+resource → DB-конструкция не требуется, но тест явно планируется здесь.
- [ ] Error-mapping (`INVALID_ARGUMENT`/`NOT_FOUND`/`FAILED_PRECONDITION`/`PERMISSION_DENIED`/`UNAUTHENTICATED`), без leak pgx.
- [ ] by-design D-2/D-8/D-11 — запись в `docs/architecture/` kacho-iam (Create стал авторитетным по scope; account-isolation custom-ролей; forward-only enforcement — legacy mis-scoped bindings сохраняются, чистка — отдельный data-cleanup тикет).
- [ ] Ревью — `db-architect-reviewer` (фильтр/индексы, role-scope read), `go-style-reviewer`, `system-design-reviewer` (единый предикат, нет нового cross-domain edge — всё within `kacho_iam`).

**S3 — api-gateway (`kacho-api-gateway`):**
- [ ] Регистрация **public** `ListAssignableRoles` (allowlist + gRPC-director + REST mux на external) — НЕ Internal. Ревью / исполнение — `api-gateway-registrar`.
- [ ] permission-catalog entry (D-5) embedded; authz-middleware делает реальный Check (anti-anon + ACR floor; scope-полиморфный extractor).
- [ ] newman happy (1.5-01, 1.5-03) + negative (1.5-05, 1.5-06, 1.5-07, 1.5-08, 1.5-09) + parity (1.5-12 Create-reject через `Operation.error`=FAILED_PRECONDITION) + forward-only legacy (1.5-21 — read+delete pre-1.5 binding) через api-gateway, RED-first.

**S4 — ui (`kacho-ui`):**
- [ ] `iamApi.listAssignableRoles(resourceType, resourceId, q?)`-хелпер (`src/api/iam.ts`); тип `AssignableRole`/`ScopeGroup`.
- [ ] `AccessBindingCreateForm` reorder RESOURCE-FIRST (Subject → Тип ресурса → Ресурс → Роли); picker зовёт `listAssignableRoles` по выбору ресурса, рендерит по `scopeGroup` (D-9); сценарии 1.5-14..16.
- [ ] **Удалить клиентскую scope-логику**: dead-code `scopeOfRole`/`roleAccountId`/`roleProjectId` (`iam.ts`); безусловный `listRoles` как picker-источник; `is_system`-партиция; scope/tree-building в `roleCascader.ts` (часть, решающая валидность). Сохранить UI-инварианты (named control, grid, tag-wrap, full-name tags).
- [ ] Reconcile (`listSubjectPrivileges` пред-выбор) и submit (create/revoke) сохранены; смена ресурса сбрасывает невалидные роли; сценарии 1.5-17..18.
- [ ] Back-compat deep-link (standalone lock_subject, cluster-admin) — 1.5-19; UI-тесты (vitest/playwright) по сценариям.

**S5 — deploy (`kacho-deploy`):** helm/compose без изменений (новый public RPC проходит существующим external endpoint); e2e-build-матрицы newman зелёные.

**S6 — workspace (docs/vault):** обновить vault `rpc/iam-access-binding-service.md` (новый RPC + Create-enforcement дельта через `Operation.error`), `resources/iam-role.md` (assignable-проекция / `isRoleAssignable`; `ScopeGroup` игнорирует legacy org), `resources/iam-access-binding.md` (Create стал scope-авторитетным forward-only — legacy mis-scoped bindings сохраняются), KAC-trail; этот acceptance-док → статус APPROVED.

**Финальная верификация (перед merge каждой Go-стадии):** `go test ./... -race` + `golangci-lint run` + `govulncheck` + `make audit-list-filter` (новый list-RPC должен фильтровать по grant-authority) + newman зелёные.

---

## 7. Выход / запреты

- Единственный артефакт этого шага — настоящий markdown. **Никакого кода** (ни `.go`, ни `.sql`, ни `.proto`).
- Описано только наблюдаемое поведение API/UI; DB-инварианты (фильтр/индексы, role-scope read) — забота `db-architect-reviewer`/`rpc-implementer`.
- `RoleService.List` НЕ модифицируется (D-1); reconcile-поведение и `AccessBinding.Create` async-контракт сохраняются (Create добавляет только scope-enforcement, D-2 — не меняет sync/async форму ответа, кроме нового negative-кода).
- Без сравнений с чужими облаками — конвенции Kachō нормативны (`api-conventions.md`).
- Координация после APPROVED: `superpowers:writing-plans` → `integration-tester` (RED по 1.5-NN) → `rpc-implementer` → `proto-api-reviewer` (proto) / `db-architect-reviewer` (фильтр/role-read) / `system-design-reviewer` (единый предикат D-2) / `api-gateway-registrar` (public RPC) → заказчик: финальный smoke (§J 1.5-20).
