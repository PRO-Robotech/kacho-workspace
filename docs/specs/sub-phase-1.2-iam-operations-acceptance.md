# Sub-phase 1.2 (IAM Operations visibility) — Acceptance

> **Статус:** ✅ APPROVED (ревизия 5 — закрыты BLOCK-2 (ревизия 4) + AUDIT-EXHAUSTIVENESS (sign-off раунд ревизии 4 → CHANGES REQUESTED); `acceptance-reviewer` дал финальный sign-off на ревизии 5. Перед стартом `superpowers:writing-plans` проставить KAC-номер вместо `KAC-TBD`.
> **BLOCK-2** (system-design lens): S1-категория (III) ложно объявляла SAKey/Condition op-метаданные «retired/не существуют» — на деле это LIVE public async-мутации (`grpc_register.go:48,54`), пишущие в общую `kacho_iam` `operations`-таблицу. Исправлено: SAKey-Issue/Revoke и Conditions-Create/Update/Delete переклассифицированы в **категорию (II) STAY `account_id IS NULL`** (narrow-scope, симметрично D-9 — доп. read не берётся); session-revocation переформулирован как **Internal-only** (`grpc_register.go:86`), НЕ retired; retired = только GDPR/SCIM-SAML/CAEP-feed (+ удалённые). Добавлен test-pinned 1.2-11f (+ smoke 1.2-30).
> **AUDIT-EXHAUSTIVENESS** (acceptance-reviewer на sign-off): re-audit прошлой ревизии ограничивался `registerPublicServices` и ложно утверждал «других пропущенных live-сервисов нет» — пропущены **четыре** LIVE Internal-only op-producer-сервиса, пишущие в ту же `operations`-таблицу: `InternalClusterService.Grant/RevokeAdmin`, `InternalIAMService.ForceLogout`, `InternalAuthorizeService.WriteTuples`, `InternalUserService.UpsertFromIdentity/OnRecoveryCompleted` (+ session-revocation). Исправлено: добавлена категория «Internal-only op-producers» в S1-таблицу + re-audit (сверено с `registerInternalServices`); их метаданные `account_id` НЕ несут → видны в cluster-wide Internal `ListIamOperations`, НЕ в account-scoped; 1.2-12 disambiguated + добавлен test-pinned 1.2-12a; ложное «других нет» исправлено на «классифицированы ВСЕ op-producing сервисы обоих листенеров».
> Сверено с ground-truth: `sa_key_service.proto:164-191`, `condition.proto:101-115`, `conditions_service.proto:51,69,89`, `sa_keys/usecases.go:188-199,544-555`, `grpc_register.go:48,54,63-87`, `cluster/grant_admin.go:149-163`, `internal_iam/force_logout.go:178-181`, `internal_authorize/handler.go:59-62`, `user/internal_upsert.go:116-124`, `user/internal_on_recovery.go:157-165`, `corelib/operations/repo.go:118-127,463-488`, `kacho-ui/App.tsx:374-389`)
> **Дата:** 2026-06-17
> **Автор:** `acceptance-author`
> **Ревьюер:** `acceptance-reviewer` — _✅ APPROVED (ревизия 5, финальный gate); coverage 100%, 31 сценарий, traceability двусторонняя; re-audit exhaustive против обоих листенеров `grpc_register.go`_
> **Эпик/тикет:** KAC-TBD (epic «IAM operations visibility»; per-repo subtask в `kacho-proto` / **`kacho-corelib`** / `kacho-iam` / `kacho-api-gateway` / `kacho-ui` / `kacho-deploy` — corelib попал из-за blast-radius `account_id`-колонки в общей `operations`-схеме, D-8). **Номер тикета проставляется до старта `writing-plans`** (фича → тикет СНАЧАЛА, `git-youtrack.md`); в финальном APPROVED-артефакте `KAC-TBD` не остаётся.
> **Источник требований:** требование заказчика «у iam модуля при создании ресурсов нету operations» — нет видимости операций в IAM-UI; ground-truth — `kacho-proto/proto/kacho/cloud/iam/v1/*`, `kacho-iam/internal/apps/kacho/...`, `kacho-corelib/operations`, `kacho-api-gateway/internal/{allowlist,middleware,opsproxy,restmux}`, `kacho-ui/src/{pages/OperationsPage.tsx,lib/service-modules.tsx,App.tsx}`. Образцы формата — `sub-phase-1.1-rm-list-operations-acceptance.md`, `sub-phase-2.1-iam-ui-vpc-parity-acceptance.md`, `sub-phase-vpc-redesign-kac239-acceptance.md`.

---

## Обзор

IAM-мутации уже асинхронны и возвращают `operation.Operation` (Account/Project/ServiceAccount/Group/Role — Create+Update+Delete; AccessBinding — Create+Delete; User — Delete + Invite), а операции пишутся в общую `operations`-таблицу (схема — `kacho-corelib/operations`, миграции — `kacho-corelib/migrations/common`) с одной денормализованной скоуп-колонкой `resource_id`. **Важно (ground-truth):** `resource_id` заполняется corelib-рефлексией `extractResourceID` (`operations/repo.go`), которая берёт **первое** поле метаданных с суффиксом `_id`. У каждого IAM-op-metadata-сообщения это единственное `<resource>_id`-поле (`CreateProjectMetadata.project_id`, `CreateGroupMetadata.group_id`, `CreateServiceAccountMetadata.service_account_id`, `CreateAccessBindingMetadata.access_binding_id`, `DeleteUserMetadata.user_id`, `CreateRoleMetadata.role_id`), а `account_id`-поле несут **только** `*AccountMetadata` и `InviteUserMetadata` (причём в `InviteUserMetadata` первым `_id`-полем идёт `user_id`, а не `account_id`). Per-resource `ListOperations` (sync read, REST `GET /iam/v1/<plural>/{id}/operations`, фильтр по `resource_id`, viewer-tier через api-gateway permission-catalog) **уже есть** для пяти ресурсов — Account, Project, ServiceAccount, Group, Role, — но **отсутствует** для **User** и **AccessBinding**. В UI вкладка «Операции» рендерится `ResourceShell`-движком для **всех** IAM-ресурсов, поэтому для User и AccessBinding она бьёт в несуществующий endpoint → 404 «ListOperations не реализован». Кроме того, у IAM-модуля **нет** module-level списка «Операции» в навигации (у VPC он есть как `/…/vpc/operations` — client-side fan-out).

Под-фаза закрывает две дыры:
1. **Per-resource паритет** — добавить `ListOperations` для User и AccessBinding (proto → iam → gateway), чтобы вкладка «Операции» работала на всех **7** IAM-ресурсах. Write-side `resource_id` для них **уже** пишется существующей рефлексией (`DeleteUserMetadata.user_id`, `*AccessBindingMetadata.access_binding_id`), нужен только read-RPC.
2. **Module-level IAM operations** — спроектировать и реализовать список «все операции account» с явной моделью скоупа (IAM-ресурсы **не** project-scoped, поэтому VPC-паттерн client-side-агрегации по `project_id` не переносится — см. §0 D-3/D-4). Поскольку `resource_id`-рефлексии для account-скоупа **недостаточно** (она вернёт `<resource>_id`, а не `account_id` — см. B1-фикс / D-5), под-фаза добавляет **явное non-first `account_id`-поле** в IAM op-metadata категории (I) — **исчерпывающий список — таблица в §6 S1** (7 ядровых CRUD + `InviteUserMetadata` + **`AddGroupMemberMetadata`/`RemoveGroupMemberMetadata`**); метаданные категории (II) (cluster-global Role, project/cluster-scoped AccessBinding, **а также LIVE public SAKey-Issue/Revoke и Conditions-Create/Update/Delete** — narrow-scope, BLOCK-2) намеренно остаются `account_id IS NULL` (видны per-resource + cluster-wide Internal, не в account-scoped списке) — то есть **НЕ «каждое подряд», а перечисленное по построению** — + nullable `account_id`-колонку в общую `operations`-схему corelib (additive, не ломает остальные сервисы), + UI nav-секцию «Операции» в IAM.

Документ описывает **только внешнее наблюдаемое поведение API и UI** (gRPC-коды, REST-формы, поведение экранов), не реализацию. Сценарии трассируются в имена integration- / newman- / UI-тестов через ID `1.2-<NN>`. Стандартные конвенции (`api-conventions.md` error-format / cursor-pagination / sync-read; `security.md` Internal-vs-public; `data-integrity.md` cross-domain dangling-ref) — нормативны и в тело не дублируются, только ссылками (§1).

---

## 0. Фиксированные дизайн-решения (предлагаются автором; подлежат approve ревьюером — затем НЕ переоткрывать)

| ID | Решение | Обоснование |
|---|---|---|
| D-1 | Per-resource `ListOperations` для **User** и **AccessBinding** копирует форму уже существующих пяти: req `{<resource>_id (required, ≤20), page_size (≤1000, default 100), page_token (≤100)}` → resp `{repeated operation.Operation operations, string next_page_token}`; sync read; cursor `(created_at,id)` ASC; фильтр по денормализованному `resource_id`. | Полный паритет ресурсов (`api-conventions.md` «parity по форме между ресурсами обязателен»). Write-side `resource_id` для User/AB **уже** пишется (`DeleteUserMetadata.user_id`, `*AccessBindingMetadata.access_binding_id`) — нужен только read-RPC + проводка. |
| D-2 | Permission-catalog entry (`kacho-proto/gen/permission_catalog.json`, embed в api-gateway `internal/middleware/embed/permission_catalog.json`) для `UserService/ListOperations`: `permission="iam.user_operationses.listOperations"`, `required_relation="viewer"`, `scope_extractor={object_type:"iam_user", from_request_field:"user_id"}`, `required_acr_min="2"` — дословный паритет с существующим `UserService/Get` (`object_type:"iam_user"`, `from_request_field:"user_id"`). Для `AccessBindingService/ListOperations`: `permission="iam.access_binding_operationses.listOperations"`, `required_relation="viewer"`, `scope_extractor` от `access_binding_id`, `required_acr_min="2"`. | Паритет с viewer-tier read-gate существующих per-resource RPC (`security.md` §AuthZ «read-RPC гейтить viewer-tier»). Энфорсмент — api-gateway authz-middleware делает реальный per-user FGA Check по `required_relation` из catalog-entry (не «inert»), см. D-10. **FGA object_type сверяется с FGA-моделью при impl** (`UserService/Get` уже использует `iam_user` → объект существует; для `access_binding` — проверить наличие `viewer`-relation на `iam_access_binding` в FGA-модели; если нет — fallback на родительский `account`-скоуп, фиксируется в impl-тикете, наблюдаемое поведение не меняется). Закрыто §5 Q#3. |
| D-3 | **Module-level IAM operations — это НОВЫЙ backend RPC, а НЕ client-side агрегация** (как у VPC). | Ground-truth: VPC `/…/vpc/operations` — чисто фронтовая агрегация (enumerate project-scoped ресурсы → fan-out per-resource `ListOperations`). IAM-ресурсы **не** project-scoped и имеют разнородных родителей (Account, Project∈Account, cluster-global Role, User, AccessBinding); fan-out по `project_id` невозможен, а User/AccessBinding/Role вообще не покрылись бы. Поэтому нужен серверный фильтр. |
| D-4 | **Модель скоупа — двухуровневая**: (a) **account-scoped публичный** `AccountService.ListAllOperations` (REST `GET /iam/v1/accounts/{account_id}/operations:all`) — все IAM-операции, чей ресурс принадлежит данному account и у которых на op-строке проставлен `account_id` (см. D-5/D-8 о том, какие операции это); (b) **cluster-wide админский** `InternalOperationsService.ListIamOperations` (Internal-only :9091, REST через internal mux `GET /iam/v1/internal/operations`) — все IAM-операции кластера, для admin-UI. **Размещение account-scoped RPC — на `AccountService`** (метод `ListAllOperations`, suffix-action `:all`), НЕ на отдельном `IamOperationsService`. | account — естественная единица tenancy IAM (как project у VPC); метод на `AccountService` даёт паритет с существующим scope_extractor-механизмом (object `account`, relation `viewer`, `from_request_field:"account_id"`) и FQN-формой `iam.account_operationses.*` (рядом с уже существующим `iam.account_operationses.listOperations`). cluster-wide = админ-видимость → по `security.md` живёт **только** на Internal*-поверхности (admin-only RPC на Internal-сервисе, ban #6). Публичная поверхность отдаёт только скоуп account вызывающего. **Закрыто §5 Q#1.** |
| D-5 | Серверный фильтр account-скоупа добавляет в corelib `operations.ListFilter` поле **`AccountID`**, маппящееся на **новую денормализованную `account_id`-колонку** строки `operations`. **Механизм заполнения — НЕ reflection-suffix-loop** (он вернул бы `<resource>_id`, а для `InviteUserMetadata` — `user_id`, см. B1-ground-truth). Вместо этого: (1) в IAM `*Metadata`-сообщения **категории (I)** (исчерпывающий список — таблица §6 S1: 7 ядровых CRUD + Invite + AddGroupMember/RemoveGroupMember) добавляется **явное поле `account_id`**; категория (II) (Role, project/cluster-scoped AB) остаётся `account_id IS NULL`; (2) corelib читает `account_id` **по точному имени поля** `account_id` (а НЕ по суффиксу `_id`) — **отдельный additive-экстрактор рядом с `resource_id`-reflection, НЕ расширение `_id`-suffix-loop** (`repo.go:477-488` остаётся как есть и продолжает возвращать первое `_id`-поле как `resource_id`); (3) **`account_id` обязан быть non-first полем** в каждом `*Metadata` (поле 1 = `<res>_id`), иначе suffix-loop вернул бы `account_id` вместо id ресурса и сломал бы `resource_id`-денормализацию; (4) каждый use-case заполняет `Metadata.account_id` синхронно на op-creation — account_id там уже в scope (D-8). | Симметрия «по суффиксу» физически не работает для account-скоупа (ground-truth `extractResourceID` — pure first-`_id`-suffix, не читает по имени). Явное non-first поле + отдельный экстрактор по точному имени детерминированы и не ломают существующий `resource_id`-путь. Фильтрация на DB-уровне (`data-integrity.md` within-service — индекс, не software-агрегация); не плодит N+1 fan-out. Точная схема колонки/индекса — `migration-writer`/`db-architect-reviewer` (D-8 blast-radius). |
| D-6 | Все существующие per-resource `ListOperations` (5 шт) и поведение `OperationService.Get`/`Cancel` (prefix `iop`→iam, ownership-gated per-creator) **не меняются**. Новые RPC только добавляются; новое `account_id`-поле в `*Metadata` и `account_id`-колонка в `operations` — additive/nullable (`buf breaking` и cross-service back-compat зелёные, D-8). | Минимизация поверхности изменений; никакого регресса контракта. |
| D-7 | UI: вкладка «Операции» (`ResourceShell`) работает для всех 7 IAM-ресурсов; новая IAM-nav секция «Операции» (`/iam/operations`) показывает account-scoped публичный список, где account берётся из **context-store** (`useContext((s)=>s.account)`, surfaced как пилюля `ContextBreadcrumb` в шапке — НЕ отдельный «account-selector»-компонент, такого нет; см. B4-ground-truth); cluster-wide Internal-список — отдельный admin-only экран под `/system/*` (D-11). | Закрывает оба пункта требования заказчика; nav-паритет с VPC «Операции», но скоуп — account (из context-store), а не project (IAM flat `/iam/*`, без project-context — `service-modules.tsx`). |
| D-8 | **account_id заполняется синхронно на op-creation в единственном `opsRepo.Create`-INSERT** (corelib `operations.Repo.Create`, `repo.go`), НЕ в worker'е (worker делает только `MarkDone`/`MarkError`). Для **всех** IAM-мутаций кроме AccessBinding-non-account и account-less User-Delete owning `account_id` уже в scope перед `Create`: Project/Group/SA Create — из входного `*.AccountID` (валидируется до op-create); Project/Group/SA Update/Delete — из загруженного sync `current.AccountID`/`acct`; **Group AddMember/RemoveMember — из загруженного sync `g.AccountID`** (use-case уже грузит группу+account для authz: `add_member.go:56,61` / `remove_member.go:55,60` — account в scope ДО op-create, BLOCK-1 fix 1.2-11e); Account Create — сам новый `accID`; User Delete — из загруженного sync `target.AccountID` (может быть `""` для account-less user → пишется как SQL `NULL` через `nullableString`). AccessBinding — см. D-9. **Blast radius:** колонка `account_id` живёт в общей corelib-`operations`-схеме (`migrations/common`) + write-path `operations/repo.go`, потребляемой vpc/compute/nlb/apps тоже → изменение **corelib + common-migration**, затрагивает ВСЕ сервисы (CI-пиннинг siblings по `polyrepo.md` merge-порядку), НЕ «забота только migration-writer внутри iam». Делается **additive/nullable**: nullable-колонка, проставляется только когда пишущий use-case передал `Metadata.account_id`; partial cursor-индекс `(account_id, created_at, id) WHERE account_id IS NOT NULL`. Не-IAM операции продолжают писаться с `account_id IS NULL`, поведение прочих сервисов не меняется. | Атомарность и синхронность подтверждены ground-truth (single INSERT, account_id in-scope). Nullable+partial-index — additive, без регресса для не-IAM consumer'ов corelib. |
| D-9 | **AccessBinding owning-account — NARROW-SCOPE семантика.** Ground-truth: `auditTenantAccountID` (`access_binding/helpers.go`) детерминированно отдаёт account **только** для `ResourceType=="account"`; для project/cluster/cross-service scope owning account на op-creation НЕ удержан (резолвится лишь транзиентно внутри `requireGrantAuthority`). Решение: account-scoped список (D-4a) включает операции **только тех** AccessBinding'ов, что **на account-ресурсе** (`ResourceType=="account"` → `account_id=ResourceID`). Операции project/cluster/cross-service-scoped binding'ов **видны через per-resource `AccessBindingService.ListOperations`** (фильтр по `resource_id=acb-…`, §A) **и через cluster-wide Internal** (D-4b), но НЕ в account-scoped публичном списке. | Дополнительный Project-read на op-creation ради резолва owning-account для project-scoped binding — НЕ дёшев и добавляет cross-read на mutation-path (Unavailable/NotFound-обработка, лишний round-trip); narrow-scope не требует доп. read и детерминирован. Tradeoff: project-scoped binding-операции не агрегируются в account-список (компенсируется per-resource + Internal). **Закрыто §5 (новый Q о AccessBinding-скоупе).** |
| D-10 | **Cluster-wide Internal RPC admin-tier энфорсится permission-catalog + authz-middleware api-gateway, НЕ листенером-как-таковым.** Ground-truth: internal-листенер сам по себе делает только listener-origin gate (exempt-bypass для `<exempt>`-RPC); admin-tier для gateway-fronted Internal RPC = catalog-entry `required_relation:"system_admin"`, `scope_extractor.object_type:"cluster"` (→ singleton `cluster_kacho_root`), `required_acr_min:"2"` (паритет с `InternalClusterService/*`, `InternalAddressPoolService/*`) + реальный per-user FGA Check в `internal/middleware/authz.go` (даже на internal-листенере gated-Internal RPC проходит полный Check, не bypass'ится). | Без catalog-entry RPC деградирует до read под exempt/viewer-floor → любой module-SA с минимальным доступом смог бы вытащить cluster-wide dump на :9091. Catalog-entry — единственное место энфорса admin-tier. |
| D-11 | **Admin cluster-wide UI — IN SCOPE** (заказчик явно просит module-level видимость). Реализуется как admin-экран под `/system/*` (precedent: AddressPool/Region/Zone), компонент-страница в `AdminLayout`-табе, gate — `usePermissions().isSystemAdmin` (← `whoami.system_admin` из `GET /iam/v1/me`; route-wrapper `RequireAdmin` отсутствует — gate на видимости таба, паритет с AddressPool/Cluster-admins табами), потребляет Internal `GET /iam/v1/internal/operations` через internal mux generic `api.list` (precedent: `cluster.ts`/addressPools). | Закрывает оба пункта требования. Не bloat: переиспользует существующий `AdminLayout`+`isSystemAdmin`-паттерн, новый сервис не нужен. (Если ревьюер сочтёт скоуп раздутым — fallback: §4 Non-goal, оставив только backend Internal RPC + newman smoke 1.2-28; но рекомендуется in-scope.) |
| D-12 | **Сдвиг приватности per-creator → per-scope-viewer — осознанно ПРИНЯТ.** Ground-truth: существующие 5 per-resource `ListOperations` и новые (User/AB per-resource + account-scoped + Internal) **НЕ** применяют per-creator ownership-фильтр — они гейтятся только viewer-tier scope (per-resource — viewer на ресурс; account-scoped — viewer на account) и возвращают операции **любого** principal'а в скоупе, включая `principalId` / `principalDisplayName` (email/имя) через `shared.OperationToProto`. Per-id-путь `OperationService.Get/Cancel` остаётся ownership-gated (per-creator → `NotFound` для чужой op). Решение: account-scoped + per-resource списки **не** фильтруют по создателю (паритет с 5 существующими); within-account приватность — только viewer-scope; раскрытие `principalId`/`principalDisplayName` других членов account account-вьюеру — **ОСОЗНАННОЕ ПРИНЯТОЕ решение** (audit-видимость «кто что менял внутри моего account»), НЕ leak. | Паритет с уже задеплоенными 5 RPC (иначе пришлось бы менять их семантику — вне scope, D-6). account — tenancy-граница: член account вправе видеть аудит-операции внутри своего account. Записано как conscious decision (`git-youtrack.md` §by-design в `docs/architecture/`, не GitHub Issue). |

---

## 1. Связь с регламентом (нормативно; в тело не дублируется)

| Регламент | Где соблюдается |
|---|---|
| `api-conventions.md` — read sync, мутации async `Operation`; **Watch не существует** (polling) | весь §A/§B (ListOperations — sync read; операции — от async-мутаций) |
| `api-conventions.md` — cursor pagination `(created_at,id)` ASC, `page_token` opaque base64, `page_size` 0→default, max 1000 | 1.2-02, 1.2-06, 1.2-09, 1.2-11, 1.2-17 |
| `api-conventions.md` — REST `/<service>/v1/<resource>`, suffix-action `:verb`; JSON camelCase (`accountId`, `createdAt`, `nextPageToken`, `pageToken`) | §A, §B (REST-формы), §J (smoke) |
| `api-conventions.md` — error-format gRPC-коды; malformed id → sync `INVALID_ARGUMENT` первым стейтментом (`corevalidate.ResourceID`); well-formed-но-нет → empty-list (паритет IAM, D-6) | 1.2-03, 1.2-04, 1.2-09, 1.2-13 |
| `security.md` §Internal-vs-external (ban #6) — Internal.* не на external endpoint; admin-only RPC на Internal*-сервисе | 1.2-12, 1.2-12a, 1.2-15, 1.2-28 (cluster-wide — Internal-only :9091, `external_isolation_test`; Internal-only op-producers видны только тут) |
| `security.md` §AuthN+AuthZ ВЕЗДЕ — каждый RPC обоих листенеров проходит per-RPC Check; read-RPC → viewer-tier; admin-tier — реальный per-user FGA Check (не inert); **iam internal-листенер обязан включать authz-Check для `InternalOperationsService.ListIamOperations` (caller, минующий api-gateway, отклоняется без `system_admin` — catalog-entry сам по себе недостаточен)** | 1.2-05 (per-resource viewer), 1.2-14 (account-scoped viewer), 1.2-15/1.2-15a (Internal admin-tier через permission-catalog + backend-листенер, D-10) |
| `security.md` §Инфра-чувствительные данные — публичная поверхность не светит инфра-поля | 1.2-16 (operations не несут placement/underlay; account-scoped список не раскрывает чужие account'ы) |
| `security.md` §within-account приватность — viewer-scope, без per-creator-фильтра (осознанный сдвиг per-creator→per-scope-viewer) | D-12, §1.2-16a (account-вьюер видит ops других членов account incl. principalDisplayName) |
| `data-integrity.md` §within-service — фильтрация инвариантно на DB-уровне (resource_id-фильтр + новый partial-индекс `account_id`, не software check-then-act/агрегация) | D-5, D-8, 1.2-11, 1.2-18a |
| `data-integrity.md` §cross-domain — consumer грациозно переживает dangling-ref | 1.2-25 (op ссылается на удалённый ресурс — список/UI не падает) |
| `00-kacho-core.md` ban #9 (мутации→Operation), #12 (TDD), #1 (APPROVED перед кодом) | весь док — гейт; DoD §6 (RED→GREEN, integration+newman в том же PR) |
| `polyrepo.md` §порядок merge + CI-пиннинг siblings (corelib-изменение → пин vpc/compute/nlb/apps к feature-ветке до merge) | §6 DoD: proto → **corelib (blast-radius)** → iam → api-gateway → ui → deploy → workspace(docs) |

---

## 2. Глоссарий: текущее состояние операций по IAM-ресурсам (ground-truth)

| Ресурс | id-prefix | Async-мутации (→`Operation`, op-prefix `iop`) | `*Metadata`: первое `_id`-поле (= write-side `resource_id`, ground-truth) | `*Metadata` несёт `account_id` СЕЙЧАС? (→ цель D-5: добавить во все) | per-resource `ListOperations` сейчас |
|---|---|---|---|---|---|
| Account | `acc` | Create / Update / Delete | `account_id` | **ДА** (`*AccountMetadata.account_id`) | **ЕСТЬ** (`GET /iam/v1/accounts/{account_id}/operations`) |
| Project | `prj` | Create / Update / Delete | `project_id` | **НЕТ** → добавить `account_id` (S1) | **ЕСТЬ** (`…/projects/{project_id}/operations`) |
| ServiceAccount | `sva` | Create / Update / Delete | `service_account_id` | **НЕТ** → добавить `account_id` (S1) | **ЕСТЬ** (`…/serviceAccounts/{service_account_id}/operations`) |
| Group | `grp` | Create / Update / Delete **+ AddMember / RemoveMember** (все 5 — async→`Operation`, public, live-registered: `group_service.proto:92,109`; allowlist `list.go:175-176`; `grpc_register.go:34-36`) | `group_id` (в `*GroupMetadata` **и** в `AddGroupMemberMetadata`/`RemoveGroupMemberMetadata` — поле 1, `group.proto:63-83`) | **НЕТ** → добавить `account_id` в `Create/Update/DeleteGroupMetadata` **И** в `AddGroupMemberMetadata`/`RemoveGroupMemberMetadata` (S1; account доступен sync на op-creation — `g.AccountID` грузится для authz, см. 1.2-11b/11e) | **ЕСТЬ** (`…/groups/{group_id}/operations`) — покрывает и member-change ops (фильтр по `resource_id=grp-…`) |
| Role | `rol` | Create / Update / Delete | `role_id` | **НЕТ** (cluster-global Role — account-родителя нет, `account_id` останется пуст → Internal-only, см. §5) | **ЕСТЬ** (`…/roles/{role_id}/operations`) |
| **User** | `usr` | **Delete** (+ Invite); **нет публичного Create** | `user_id` (в `DeleteUserMetadata`); **в `InviteUserMetadata` первым `_id`-полем тоже идёт `user_id`** (поля: `user_id`, `account_id`, `magic_link_url`) → Invite-op имеет `resource_id=usr-W` | `DeleteUserMetadata`: **НЕТ** → добавить `account_id` (S1); `InviteUserMetadata`: **ДА** (но читать по точному имени, не суффиксу) | **НЕТ → добавляем (§A)** |
| **AccessBinding** | `acb` | **Create / Delete** (нет Update) | `access_binding_id` | **НЕТ** → добавить `account_id` (S1), но проставляется только для `ResourceType=="account"` (narrow-scope, D-9) | **НЕТ → добавляем (§A)** |

**Дополнительные LIVE public op-producing IAM-сервисы (BLOCK-2, ground-truth `grpc_register.go:48,54`)** — НЕ среди 7 «ядровых» ресурсов выше, но пишут в ту же `kacho_iam` `operations`-таблицу и потому ДОЛЖНЫ быть классифицированы:

| Сервис | Async-мутации (→`Operation`) | `*Metadata`: первое `_id`-поле (= `resource_id`) | Несёт `account_id`? | Категория / видимость |
|---|---|---|---|---|
| **`SAKeyService`** (`grpc_register.go:54`) | Issue / Revoke | `service_account_id` (`Issue/RevokeSAKeyMetadata`, поле 1) | **НЕТ** (и НЕ добавляем — narrow-scope) | **(II)** `account_id IS NULL`: per-resource `sva-…` ListOperations + cluster-wide Internal, НЕ account-scoped (1.2-11f) |
| **`ConditionsService`** (`grpc_register.go:48`) | Create / Update / Delete | `condition_id` (`*ConditionMetadata`, поле 1) | **НЕТ** (и НЕ добавляем — narrow-scope) | **(II)** `account_id IS NULL`: per-resource `cnd-…` + cluster-wide Internal, НЕ account-scoped (1.2-11f) |

Это LIVE сервисы — **НЕ retired** (ретайрнуты только GDPR/SCIM-SAML/CAEP-feed + удалённые, `kacho-iam` CLAUDE.md §1 «Retired»).

**Internal-only op-producers (LIVE, `registerInternalServices`, `grpc_register.go:63-87`)** — тоже пишут `iop`-op в общую `kacho_iam` `operations`-таблицу, метаданные `account_id` НЕ несут → видны в cluster-wide Internal `ListIamOperations` (1.2-12/1.2-12a), НЕ в account-scoped публичном списке, account_id-стамп не добавляется (симметрично D-9): `InternalClusterService.Grant/RevokeAdmin`, `InternalIAMService.ForceLogout`, `InternalAuthorizeService.WriteTuples` (нет `_id`-поля → `resource_id=""`), `InternalUserService.UpsertFromIdentity/OnRecoveryCompleted`, `InternalSessionRevocationsService`. Полная классификация — re-audit в §6 S1. Все Internal-only :9091, НЕ retired (вне публичного account-scoped списка by-design).

Module-level «все операции IAM»: **НЕ существует** ни в каком виде (`OperationService` = только `Get`/`Cancel` by-id; никакого `List`). UI IAM nav (`service-modules.tsx`) **не содержит** entry «Операции». → добавляем (§B, §C).

---

## §A. Per-resource ListOperations для User и AccessBinding (proto + iam + gateway)

**Целевое:** новый RPC `UserService.ListOperations` и `AccessBindingService.ListOperations`, форма дословно как у пяти существующих (D-1), viewer-gate (D-2), REST `GET /iam/v1/users/{user_id}/operations` и `GET /iam/v1/accessBindings/{access_binding_id}/operations`, фильтр по уже пишущемуся `resource_id`.

### 1.2-01 (positive — User.ListOperations отдаёт операции пользователя)
**Given** существует User `usr-W` (через Invite → активирован)
**And** над `usr-W` выполнен Delete-flow ИЛИ существуют ≥1 операции с `resource_id=usr-W` в `operations` IAM
**And** существуют операции другого пользователя `usr-V` (`resource_id=usr-V`)

**When** клиент вызывает `UserService.ListOperations` (REST `GET /iam/v1/users/usr-W/operations`) с `page_size=50`

**Then** ответ — gRPC `OK` / HTTP `200`, тело `{ operations:[…], nextPageToken:"" }`
**And** возвращаются **только** операции с `resource_id=usr-W` (операции `usr-V` отсутствуют)
**And** каждый элемент — `operation.Operation` с `id` (prefix `iop`), `createdAt`, `done`, `metadata`; JSON camelCase

### 1.2-02 (positive — AccessBinding.ListOperations отдаёт create+delete операции binding'а)
**Given** существует AccessBinding `acb-B`
**And** над `acb-B` есть Create-операция; затем Delete(revoke)-операция (обе с `resource_id=acb-B`)

**When** клиент вызывает `AccessBindingService.ListOperations` (REST `GET /iam/v1/accessBindings/acb-B/operations`)

**Then** `OK`/`200`, возвращаются ровно 2 операции (create + delete) с `resource_id=acb-B`, отсортированные cursor-стабильно `(created_at,id)` ASC
**And** `nextPageToken==""` (помещаются в страницу)

### 1.2-03 (negative — malformed id → INVALID_ARGUMENT, синхронно первым стейтментом)
**Given** клиент

**When** вызывается `GET /iam/v1/users/not-a-valid-id/operations` (или AccessBinding с мусорным id)

**Then** gRPC `INVALID_ARGUMENT` / HTTP `400`, сообщение формы `"invalid user id '…'"` (`corevalidate.ResourceID` / `shared.ValidateResourceID`), без обращения к БД

### 1.2-04 (negative — well-formed но несуществующий ресурс)
> **Решение паритета:** существующие 5 per-resource `ListOperations` в IAM **НЕ** делают предварительный `Get` ресурса (handler сразу зовёт use-case, фильтрующий `operations` по `resource_id`). Поэтому User/AccessBinding **зеркалят** это поведение: well-formed-но-несуществующий id → **`OK` с пустым списком**, НЕ `NOT_FOUND`. (Это осознанный паритет с текущими IAM-ListOperations; отличается от RM-фазы 1.1, где handler делал `Get`. Если ревьюер требует `NOT_FOUND`-семантику — это меняет и существующие 5, что вне scope; фиксируем паритет.)

**Given** User `usr-MISSING` отсутствует, но id well-formed (prefix `usr`, ≤20)

**When** `GET /iam/v1/users/usr-MISSING/operations`

**Then** `OK`/`200`, `{ operations:[], nextPageToken:"" }` (пустой список, не ошибка) — паритет с Account/Project/etc.

### 1.2-05 (authz — viewer-tier gate энфорсится)
**Given** caller без `viewer`-доступа к User `usr-W` (или к scope, в который он входит)

**When** `GET /iam/v1/users/usr-W/operations`

**Then** authz-Check (`InternalIAMService.Check`, permission `iam.user_operationses.listOperations`, relation `viewer`) → отказ → gRPC `PERMISSION_DENIED` / HTTP `403`
**And** аналогично для `iam.access_binding_operationses.listOperations`
**And** caller с `viewer`+ — `OK`

### 1.2-06 (positive — pagination cursor)
**Given** User `usr-W` с 120 операциями (`resource_id=usr-W`)

**When** `GET /iam/v1/users/usr-W/operations?pageSize=50`
**Then** возвращается 50 операций, `nextPageToken != ""`

**When** повторно с этим `pageToken`
**Then** следующие 50, `nextPageToken != ""`

**When** третий вызов с новым `pageToken`
**Then** оставшиеся 20, `nextPageToken == ""`

### 1.2-07 (edge — нулевые операции → пустой список)
**Given** AccessBinding `acb-EMPTY` без операций (или User без Delete-операций)

**When** `GET /iam/v1/accessBindings/acb-EMPTY/operations`

**Then** `OK`/`200`, `{ operations:[], nextPageToken:"" }` — без ошибки

### 1.2-08 (edge — User имеет Invite + Delete операции, нет Create)
**Given** User `usr-W` (создан через Invite, не публичный Create), над которым есть Invite-операция и Delete-операция

**When** `GET /iam/v1/users/usr-W/operations`

**Then** возвращается ≥2 операции; в наборе **нет** операции типа Create user (публичного Create нет — §2)
**And** Invite-операция **присутствует** — её `resource_id == usr-W` (ground-truth: `InviteUserMetadata` первое `_id`-поле — `user_id`, поэтому `extractResourceID` денормализует `usr-W`; это не гипотеза, а текущее поведение)

### 1.2-09 (negative — garbage page_token → INVALID_ARGUMENT)
**Given** валидный `user_id`

**When** `GET /iam/v1/users/usr-W/operations?pageToken=%%%not-base64%%%`

**Then** gRPC `INVALID_ARGUMENT` / HTTP `400` (`corevalidate`/`operations.Repo` отвергает мусорный курсор), список не возвращается

### 1.2-10 (gateway — RPC зарегистрированы public, REST-route есть)
**Given** api-gateway собран

**Then** allowlist содержит `/kacho.cloud.iam.v1.UserService/ListOperations` и `/kacho.cloud.iam.v1.AccessBindingService/ListOperations`
**And** REST-route-таблица содержит `GET /iam/v1/users/{user_id}/operations` → `…UserService/ListOperations` и `GET /iam/v1/accessBindings/{access_binding_id}/operations` → `…AccessBindingService/ListOperations`
**And** оба RPC — **public** (на external endpoint; это per-resource read tenant-facing, не admin) — НЕ Internal

---

## §B. Module-level IAM operations (account-scoped public + cluster-wide Internal)

**Целевое:** D-3/D-4/D-5/D-8/D-9/D-10 — серверный скоуп-фильтр по новой `account_id`-колонке вместо client-side fan-out. Два RPC:
- **Public account-scoped:** `AccountService.ListAllOperations` (D-4: размещение **зафиксировано на `AccountService`**) — REST `GET /iam/v1/accounts/{account_id}/operations:all`; req `{account_id (required), page_size, page_token}`; resp `{repeated operation.Operation operations, string next_page_token}`; фильтр по денормализованной `account_id`-колонке (D-5/D-8).
- **Internal cluster-wide:** `InternalOperationsService.ListIamOperations` — Internal-only :9091, REST через **internal** mux `GET /iam/v1/internal/operations` (path convention version-first `/<service>/v1/internal/...`, паритет с существующими `/iam/v1/internal/cluster`, `/iam/v1/internal/iam:check`); req `{page_size, page_token, (опц.) account_id filter}`; resp как выше; **не публикуется на external endpoint** (ban #6).

> **Зафиксировано (D-4, §5 Q#1 закрыт):** account-scoped RPC — метод на `AccountService` (`ListAllOperations`), НЕ отдельный `IamOperationsService`. Обоснование — паритет со scope_extractor (object `account`, relation `viewer`, `from_request_field:"account_id"`) и FQN-формой `iam.account_operationses.*` рядом с существующим `iam.account_operationses.listOperations`.

### 1.2-11 (positive — account-scoped список агрегирует операции всех ресурсов account по `account_id`-колонке)
**Given** account `acc-X`; в нём ≥1 Project `prj-Y`, ≥1 ServiceAccount `sva-Z`, ≥1 Group `grp-G` (с ≥1 AddMember/RemoveMember-операцией), ≥1 AccessBinding **на ресурс account** (`ResourceType=="account"`); над каждым выполнены async-мутации (Create и т.д.), каждая op-строка получила денормализованный `account_id=acc-X` на op-creation (D-5/D-8)
**And** существует другой account `acc-OTHER` со своими операциями (их op-строки имеют `account_id=acc-OTHER`)

**When** клиент вызывает `GET /iam/v1/accounts/acc-X/operations:all?pageSize=100`

**Then** `OK`/`200`, `{ operations:[…], nextPageToken }`
**And** в наборе присутствуют операции `acc-X` (собственная Create/Update), `prj-Y`, `sva-Z`, `grp-G` (включая **member-change-операции** AddMember/RemoveMember — 1.2-11e), и account-scoped AccessBinding'ов account `acc-X` — **все** отфильтрованы по колонке `account_id=acc-X`
**And** операции `acc-OTHER` **отсутствуют** (изоляция по `account_id`-колонке)
**And** операции отсортированы cursor-стабильно `(created_at, id)` **ASC** (паритет с per-resource ListOperations; UI сортирует «свежие сверху» на отображении, контракт пагинации — ASC)

### 1.2-11a (propagation — Project op получает `account_id` на op-creation)
> Верифицирует B1-фикс: явное `account_id`-поле в `*ProjectMetadata` + синхронное заполнение из `p.AccountID`/`current.AccountID` (D-8), а НЕ suffix-reflection (которая вернула бы `project_id`).

**Given** account `acc-X`; Project `prj-Y ∈ acc-X`
**When** выполняется `Project.Create`/`Update`/`Delete` (async → `Operation`), затем `GET /iam/v1/accounts/acc-X/operations:all`
**Then** соответствующая Project-операция присутствует в наборе (её op-строка имеет `account_id=acc-X`)
**And** в per-resource `GET /iam/v1/projects/prj-Y/operations` та же операция тоже видна (фильтр по `resource_id=prj-Y` не сломан — `account_id` additive)

### 1.2-11b (propagation — ServiceAccount / Group CRUD op получают `account_id`)
**Given** account `acc-X`; ServiceAccount `sva-Z ∈ acc-X`, Group `grp-G ∈ acc-X`
**When** над каждым выполнены async CRUD-мутации (Create/Update/Delete), затем `GET /iam/v1/accounts/acc-X/operations:all`
**Then** SA- и Group-CRUD-операции присутствуют (op-строки `account_id=acc-X`, заполнено из `sa.AccountID`/`g.AccountID`, D-8)

### 1.2-11e (propagation — Group AddMember / RemoveMember op получают `account_id`; BLOCK-1 fix)
> Закрывает BLOCK-1 (option a — COVER): member-change-операции группы должны всплывать в account-scoped списке наравне с Group-CRUD. Ground-truth: `AddMember`/`RemoveMember` — async→`Operation`, public (`group_service.proto:92,109`; allowlist `list.go:175-176`), а их metadata (`AddGroupMemberMetadata`/`RemoveGroupMemberMetadata`, `group.proto:63-83`) до фикса несут только `group_id`(1)/`member_type`(2)/`member_id`(3) → без `account_id` op-строка получает `account_id IS NULL` и не видна в `/iam/operations` (подтверждённый ask заказчика B — module-level видимость). Owning account доступен sync на op-creation: оба use-case грузят группу через `repo.Get` и сам Account для authz (`add_member.go:56` `g, _ := rd.Groups().Get(ctx, in.GroupID)` → `:61` `acct, _ := rd.Accounts().Get(ctx, g.AccountID)`; `remove_member.go:55`/`:60`) — `g.AccountID` уже в scope в момент `operations.NewFromContext`.

**Given** account `acc-X`; Group `grp-G ∈ acc-X` (`g.AccountID == acc-X`); member `usr-M`/`sva-M`
**When** выполняется `GroupService.AddMember` (`POST /iam/v1/groups/grp-G:addMember`), затем `GroupService.RemoveMember` (`:removeMember`) — обе async→`Operation`; затем `GET /iam/v1/accounts/acc-X/operations:all`
**Then** обе member-change-операции присутствуют в account-scoped наборе (op-строки `account_id=acc-X`, заполнено из загруженного для authz `g.AccountID`, D-8)
**And** те же операции видны в per-resource `GET /iam/v1/groups/grp-G/operations` (фильтр по `resource_id=grp-G` не сломан — `account_id` additive; `extractResourceID` по-прежнему берёт первое `_id`-поле `group_id`, т.к. `account_id` — non-first поле)
**And edge:** если группа окажется без owning account (`g.AccountID==""`, патологический/account-less случай) → use-case пишет SQL `NULL` (helper `nullableString`, S2/D-8), op-строка `account_id IS NULL` → в account-scoped список не попадает, но видна per-resource и в cluster-wide Internal (паритет с 1.2-11c account-less edge)

### 1.2-11c (propagation — User.Delete получает `account_id` владеющего account)
**Given** User `usr-W ∈ acc-X` (загружается sync, `target.AccountID=acc-X`)
**When** `User.Delete` (async → `Operation`), затем `GET /iam/v1/accounts/acc-X/operations:all`
**Then** Delete-операция `usr-W` присутствует (op-строка `account_id=acc-X` из `target.AccountID`)
**And edge:** если у удаляемого User'а `AccountID==""` (account-less) → use-case передаёт **SQL `NULL`** (helper `nullableString`: пустая строка → `NULL`, не `''`), чтобы partial-индекс `WHERE account_id IS NOT NULL` (D-8) такую строку **исключал**; op-строка с `account_id IS NULL`, в account-scoped список не попадает (видна в per-resource `usr-W` и cluster-wide Internal)

### 1.2-11d (propagation — AccessBinding.Create/Delete: account-scoped binding получает `account_id`, project/cluster-scoped — нет)
> Верифицирует B2-решение (D-9 narrow-scope).

**Given** account `acc-X`; AccessBinding `acb-ACC` на account-ресурс (`ResourceType=="account"`, `ResourceID=acc-X`); AccessBinding `acb-PRJ` на project-ресурс (`ResourceType=="project"`)
**When** над обоими выполнены Create/Delete (async → `Operation`), затем `GET /iam/v1/accounts/acc-X/operations:all`
**Then** операции `acb-ACC` **присутствуют** (op-строка `account_id=acc-X`, проставлен т.к. `ResourceType=="account"`)
**And** операции `acb-PRJ` **отсутствуют** в account-scoped списке (op-строка `account_id IS NULL` — owning account project-scoped binding'а на op-creation не резолвится, D-9)
**And** операции `acb-PRJ` **видны** через per-resource `GET /iam/v1/accessBindings/acb-PRJ/operations` (фильтр по `resource_id`) и через cluster-wide Internal (1.2-12)

### 1.2-11f (propagation — SAKey-Issue / Condition-op: narrow-scope (II), видны per-resource + Internal, ОТСУТСТВУЮТ в account-scoped списке; BLOCK-2)
> Закрывает BLOCK-2 (зеркало 1.2-11d AccessBinding narrow-scope). Ground-truth: `SAKeyService.Issue/Revoke` (`grpc_register.go:54`) и `ConditionsService.Create/Update/Delete` (`grpc_register.go:48`) — LIVE public async→`Operation`, пишут в общую `kacho_iam` `operations`-таблицу через `operations.NewFromContext`+`opsRepo.Create` (`sa_keys/usecases.go:188-199,544-555`). Их metadata несут только `service_account_id`(1) / `condition_id`(1) (нет `account_id`) → `extractResourceID` денормализует `resource_id=sva-…` / `cnd-…`, а `account_id` остаётся `NULL` (категория II, narrow-scope: owning account резолвится лишь доп. read — не берётся, консистентно с D-9). **Эти op-метаданные НЕ ретайрнуты** — falsely-retired в прошлых ревизиях, исправлено в S1-таблице/§5-Q4.

**Given** account `acc-X`; ServiceAccount `sva-Z ∈ acc-X`; над `sva-Z` выполнен `SAKeyService.Issue` (`POST /iam/v1/serviceAccounts/sva-Z/keys`, async→`Operation`, metadata `IssueSAKeyMetadata{service_account_id=sva-Z}`)
**And** (опц.) существует Condition `cnd-C`, над которым выполнен `ConditionsService.Create` (async→`Operation`, metadata `CreateConditionMetadata{condition_id=cnd-C}`)
**When** клиент вызывает `GET /iam/v1/accounts/acc-X/operations:all`
**Then** SAKey-Issue-операция (и Condition-операция, если покрывается) **ОТСУТСТВУЮТ** в account-scoped наборе (op-строки `account_id IS NULL` — use-case намеренно не стампит `account_id`, категория II)
**And** SAKey-Issue-операция **видна** через per-resource `GET /iam/v1/serviceAccounts/sva-Z/operations` (фильтр по `resource_id=sva-Z` — ground-truth: первое `_id`-поле `service_account_id` денормализуется в `resource_id`)
**And** (если покрывается Condition) Condition-операция видна через per-resource `GET /iam/v1/conditions/cnd-C/operations` (фильтр по `resource_id=cnd-C`)
**And** обе операции **видны** через cluster-wide Internal `GET /iam/v1/internal/operations` (1.2-12)
**And** изоляция: account-scoped список `acc-X` не содержит этих op независимо от того, что `sva-Z ∈ acc-X` (account_id-колонка пуста, а не filtered out по чужому account)

### 1.2-12 (positive — cluster-wide Internal список покрывает то, чего нет в account-scoped: cluster-global Role + project-scoped AccessBinding + SAKey/Condition)
**Given** существуют операции по ресурсам нескольких account'ов (`account_id` проставлен) **и** операции cluster-global Role `rol-R` (`account_id IS NULL`, нет account-родителя) **и** операции project-scoped AccessBinding `acb-PRJ` (`account_id IS NULL`, D-9) **и** операции SAKey-Issue/Condition (`account_id IS NULL`, категория II — 1.2-11f) **и** операции Internal-only op-producers (GrantClusterAdmin / ForceLogout / WriteTuples / UpsertFromIdentity — `account_id IS NULL`, S1 Internal-only-row)

**When** admin-tooling/UI вызывает Internal `GET /iam/v1/internal/operations` (через internal mux, :9091)

**Then** `OK`/`200`; возвращаются операции **всех** IAM-ресурсов кластера, включая Role-операции, project-scoped AccessBinding-операции, SAKey-Issue/Revoke + Condition-Create/Update/Delete операции **и операции Internal-only op-producers** (Grant/RevokeClusterAdmin, ForceLogout, WriteTuples, Upsert/OnRecovery) — всё категории II/Internal-only, ничего из этого нет ни в одном account-scoped списке. Cluster-wide Internal список — единственная поверхность, агрегирующая все genuine cluster IAM-операции, включая op-строки с пустым `resource_id` (WriteTuples)
**And** ответ — тот же `operation.Operation`-envelope
**And** ответ **пагинируется** так же, как публичные списки (cursor `(created_at,id)` ASC, `next_page_token` opaque base64): `page_size` через `corevalidate.PageSize` (0 → default; **max 1000** — больший игнорируется/клампится, не отдаёт unbounded cluster-wide dump одним ответом); garbage `page_token` → `INVALID_ARGUMENT`. Cluster-wide объём обязан читаться постранично, без single-shot выгрузки всего кластера

### 1.2-12a (propagation — Internal-only op-producer: видна в cluster-wide Internal, ОТСУТСТВУЕТ в account-scoped; disambiguates 1.2-12)
> Закрывает AUDIT-EXHAUSTIVENESS: явно фиксирует, что op-строки Internal-only op-producers (`InternalIAMService.ForceLogout`, `InternalClusterService.Grant/RevokeAdmin`, `InternalAuthorizeService.WriteTuples`, `InternalUserService.Upsert/OnRecovery`) попадают в cluster-wide Internal список (genuine cluster IAM-ops), но не в account-scoped публичный (account_id не стампится). Ground-truth: все пишут `iop`-op через `operations.NewFromContext`+`opsRepo.Create`, метаданные без `account_id` (`force_logout.go:178-181`, `cluster/grant_admin.go:149-163`, `internal_authorize/handler.go:59-62`, `user/internal_upsert.go:116-124`).

**Given** account `acc-X`; над `usr-W ∈ acc-X` выполнен `InternalIAMService.ForceLogout` (async→`Operation`, metadata `ForceLogoutMetadata{user_id=usr-W}`, нет `account_id`)
**And** выполнен `InternalClusterService.GrantAdmin` (metadata `GrantClusterAdminMetadata{cluster_admin_grant_id, subject_id}`, нет `account_id`)
**When** admin вызывает Internal `GET /iam/v1/internal/operations`; обычный account-вьюер вызывает `GET /iam/v1/accounts/acc-X/operations:all`
**Then** ForceLogout- и GrantAdmin-операции **присутствуют** в cluster-wide Internal списке
**And** обе **ОТСУТСТВУЮТ** в account-scoped списке `acc-X` (op-строки `account_id IS NULL` — use-case намеренно не стампит `account_id`)
**And** ForceLogout-op видна per-resource по `resource_id=usr-W` (`GET /iam/v1/users/usr-W/operations` — `_id`-поле `user_id` денормализуется), а WriteTuples-op (если бы тестировалась) per-resource НЕ видна (нет `_id`-поля → `resource_id=""`), но видна в cluster-wide Internal

### 1.2-13 (negative — module account-list для несуществующего account)
**Given** `acc-MISSING` отсутствует, id well-formed

**When** `GET /iam/v1/accounts/acc-MISSING/operations:all`

**Then** паритет с §1.2-04: `OK`/`200` с пустым списком (фильтр по `account_id` не находит строк), НЕ `NOT_FOUND`
**And** malformed `account_id` → `INVALID_ARGUMENT`/`400` (первым стейтментом)

### 1.2-14 (authz — account-scoped list гейтится viewer на account, distinct permission FQN)
**Given** caller без `viewer` на `acc-X`

**When** `GET /iam/v1/accounts/acc-X/operations:all`

**Then** `PERMISSION_DENIED`/`403` — permission-catalog entry для `AccountService/ListAllOperations`: **distinct** permission FQN `iam.account_operationses.listAll` (1:1 RPC→permission, НЕ переиспользует `…listOperations` существующего `AccountService/ListOperations`), `required_relation="viewer"`, `scope_extractor={object_type:"account", from_request_field:"account_id"}`, `required_acr_min="2"`; api-gateway authz-middleware делает реальный per-user FGA Check
**And** caller с `viewer` на `acc-X` видит **только** операции `acc-X` (фильтр по `account_id`-колонке), не других account'ов (изоляция — серверный фильтр + scope-gate)

### 1.2-15 (security — cluster-wide список ТОЛЬКО на Internal, admin-tier через permission-catalog, НЕ на external)
**Given** развёрнутый стенд

**When** клиент пытается достучаться до cluster-wide списка через **external** endpoint (public REST/gRPC)

**Then** маршрут отсутствует на external (404 / unknown method) — `InternalOperationsService.ListIamOperations` зарегистрирован **только** в **internal** restmux-блоке (`iamInternalAddr` в `internal/restmux/mux.go`), gRPC-director блокирует любой `InternalService`-suffix на external (`HasInternalSuffix`), а REST-dispatcher отдаёт 404 для `/…/internal/…`-путей на external-листенере; ответственность — `api-gateway-registrar` (`security.md` ban #6, §Admin-UI правило)
**And** admin-tier энфорсится **permission-catalog entry** (D-10): `required_relation="system_admin"`, `scope_extractor.object_type="cluster"` (→ singleton `cluster_kacho_root`), `required_acr_min="2"` — паритет с `InternalClusterService/*` / `InternalAddressPoolService/*`; api-gateway authz-middleware делает **реальный per-user FGA Check** даже на internal-листенере (gated-Internal RPC НЕ bypass'ится listener-origin-gate'ом — bypass только для `<exempt>`-entry)

### 1.2-15a (security — non-admin / module-SA НЕ может вытащить cluster-wide dump)
> Верифицирует B6: без admin-tier RPC деградировал бы до viewer/exempt-read.

**Given** caller — обычный аутентифицированный пользователь БЕЗ `system_admin` на `cluster`
**When** `GET /iam/v1/internal/operations` через api-gateway internal mux
**Then** `PERMISSION_DENIED`/`403` (per-user FGA Check по `system_admin` @ `cluster:cluster_kacho_root` не проходит)

**Given** module-SA с минимальным доступом, обращающийся **напрямую** на iam :9091 (минуя api-gateway)
**When** вызывает `InternalOperationsService/ListIamOperations`
**Then** **DENY** — backend iam-листенер тоже под authz-Check (internal НЕ освобождён, `security.md` §AuthN+AuthZ ВЕЗДЕ); SA без `system_admin` отклоняется

### 1.2-16 (security — операции не несут инфра-чувствительных данных)
**Given** любой из списков §B

**Then** возвращаемые `operation.Operation` содержат tenant-facing intent+result (id, description, createdAt, done, metadata с tenant-id'шками, result/error) и **не** раскрывают placement/underlay/wiring/числовые инфра-id (`security.md` §Инфра-чувствительные данные) — операции IAM таких полей не несут by-construction; account-scoped список не показывает операции чужих account'ов

### 1.2-16a (invariant — within-account приватность = viewer-scope, БЕЗ per-creator-фильтра; D-12)
> Верифицирует B5: осознанный сдвиг per-creator → per-scope-viewer. Account-scoped и per-resource списки НЕ фильтруют по создателю (паритет с 5 существующими), per-id `Get/Cancel` — ownership-gated.

**Given** account `acc-X`; в нём двое principal'ов — `usr-A` и `usr-B` (у обоих есть viewer на `acc-X`); каждый создал какие-то IAM-мутации в `acc-X` (op-строки с `principalDisplayName` = email каждого)
**And** account `acc-OTHER` со своими операциями
**When** `usr-A` (viewer на `acc-X`) вызывает `GET /iam/v1/accounts/acc-X/operations:all`
**Then** в наборе присутствуют операции, созданные **и** `usr-A`, **и** `usr-B` (per-creator-фильтра нет — ожидаемо, НЕ leak)
**And** каждый элемент несёт `principalId` и `principalDisplayName` создателя (включая email/имя `usr-B`) — это **принятое** раскрытие within-account (D-12)
**And** операции `acc-OTHER` отсутствуют (изоляция по `account_id`)
**And** при попытке `usr-A` сделать `OperationService.Get(<op созданной usr-B>)` по id → `NOT_FOUND` (per-id путь остаётся ownership-gated, не меняется — D-6)

### 1.2-17 (edge — module list пагинируется)
**Given** `acc-X` с 250 операциями суммарно по всем ресурсам

**When** `GET /iam/v1/accounts/acc-X/operations:all?pageSize=100` → затем по `pageToken` дважды

**Then** 100 + 100 + 50; финальный `nextPageToken==""`; курсор стабилен при конкурентной вставке новой операции (новые не «протекают» назад в уже отданные страницы — cursor `(created_at,id)`)

### 1.2-18 (edge — account без операций → пустой список)
**Given** свежесозданный `acc-NEW` без дочерних ресурсов/операций (кроме, возможно, собственной Create)

**When** `GET /iam/v1/accounts/acc-NEW/operations:all`

**Then** `OK`/`200`, либо `[]`, либо ровно операция(и) самого `acc-NEW` — без ошибки

### 1.2-18a (corelib blast-radius — не-IAM op пишется с `account_id IS NULL`, прочие сервисы не сломаны; D-8)
> Верифицирует B3: `account_id`-колонка живёт в общей corelib-`operations`-схеме (`migrations/common`), потребляемой vpc/compute/nlb/apps. Изменение additive/nullable; corelib-integration-тест (testcontainers).

**Given** corelib `operations.Repo` с применённой новой миграцией (`account_id` nullable + partial-индекс `(account_id, created_at, id) WHERE account_id IS NOT NULL`)
**When** не-IAM consumer (vpc/compute/nlb/apps) пишет Operation через `opsRepo.Create` **без** `Metadata.account_id` (его metadata это поле не несёт)
**Then** INSERT успешен; op-строка имеет `account_id IS NULL`
**And** существующий `resource_id`-reflection и per-resource `List(ResourceID=…)` других сервисов работают без изменений (поведение прочих consumer'ов corelib не затронуто — back-compat)
**And** IAM-op с переданным `Metadata.account_id` — строка получает `account_id`-значение; фильтр `List(AccountID=acc-X)` возвращает только IAM-строки этого account, не «протекая» в чужие сервисы (у тех `account_id IS NULL`)

---

## §C. UI — вкладка «Операции» (7 ресурсов) + IAM-nav секция «Операции»

> UI-поведение проверяется component/e2e-тестами фронта; REST-контракт, на который опирается UI, — newman (§J). Backend-правки UI не вносит (ban #13).

### 1.2-19 (positive — вкладка «Операции» работает для всех 7 IAM-ресурсов)
**Given** на стенде есть Account/Project/ServiceAccount/Group/Role **и** User, AccessBinding с ≥1 операцией каждый
**And** ни один IAM-ресурс не скрывает таб «Операции» (ground-truth: ни один IAM `detailExtension` в `resource-detail-extensions.tsx` не ставит `hideOperations:true` → `ResourceShell` рендерит OperationsTab для всех 7)
**When** пользователь открывает деталь каждого ресурса и переходит на path-based таб `…/operations`
**Then** для **всех 7** (включая User `/iam/users/:uid/operations` и AccessBinding `/iam/access-bindings/:uid/operations`) таблица операций рендерится (колонки: `Операция`/description, `Статус` (done/в процессе/ошибка), `Создана`/createdAt, `ID` (`CopyableId`)) — **без 404 «ListOperations не реализован»**
**And** ранее ломавшиеся User и AccessBinding теперь отдают список (бьют в новые REST-routes §A)

### 1.2-20 (edge — вкладка «Операции» при нуле операций)
**Given** ресурс без операций
**Then** таб «Операции» показывает empty-state «нет операций», без ошибки/белого экрана

### 1.2-21 (positive — IAM-nav секция «Операции» появилась)
**Given** пользователь в разделе `/iam`, в шапке через пилюлю `ContextBreadcrumb` (context-store) выбран account `acc-X`
**When** смотрит на IAM-навигацию (sidebar `service-modules.tsx`, IAM-модуль `items` — сейчас БЕЗ «Операции»; добавляем entry)
**Then** присутствует пункт «Операции» (иконка истории), ведущий на `/iam/operations` (flat `iamSeg`, **без** `requiresProject` — IAM живёт на `/iam/*`, не под `/projects/:id/`)
**And** route `/iam/operations` зарегистрирован в `App.tsx` **ДО** блока `IAM_DETAIL_SPECS.map` `/:uid`-роутов (иначе literal `operations` будет захвачен как `accounts/:uid` — тот же класс бага, что уже отмечен комментом для `create`/`invite`)
**And** клик открывает страницу module-level операций

### 1.2-22 (positive — module-level страница показывает account-scoped операции, account из context-store)
**Given** `/iam/operations`; account `acc-X` выбран в context-store (страница читает его `useContext((s)=>s.account)` — тот же механизм, что `IamScopedListShell`/`AccessBindingsPage`)
**When** страница загружается
**Then** вызывается **один** backend RPC `GET /iam/v1/accounts/acc-X/operations:all` (НЕ client-side fan-out по ресурсам, в отличие от VPC `OperationsPage` — D-3); таблица показывает агрегированные операции `acc-X`, свежие сверху; пагинация по `nextPageToken`
**And** операции других account'ов не видны (серверная изоляция по `account_id`)

### 1.2-23 (edge — module page без выбранного account в context-store)
**Given** `/iam/operations`; account в context-store НЕ выбран (`useContext((s)=>s.account)` → `null`)
**Then** показан IAM-appropriate empty/hint «выберите Account» (паритет с guard'ом `IamScopedListShell`/`AccessBindingsPage` при `!account`); list НЕ запрашивается до выбора account (`enabled: !!accountId`, не падает, не зовёт RPC без скоупа)

### 1.2-24 (positive — admin cluster-wide экран под `/system/*`, gated isSystemAdmin)
> B7: экран полностью wired (D-11 — IN SCOPE). Precedent — AddressPool/Region/Zone/Cluster-admins под `AdminLayout`.

**Given** пользователь с `whoami.system_admin == true` (`usePermissions().isSystemAdmin`, из `GET /iam/v1/me`)
**When** он переходит на admin-route `/system/operations` (новый таб в `AdminLayout`, рядом с Регионы/Зоны/Пулы адресов/Cluster admins; nav-блок `system` в `service-modules.tsx`)
**Then** рендерится admin-страница cluster-wide IAM-операций, потребляющая Internal `GET /iam/v1/internal/operations` через api-gateway internal mux обычным generic `api.list` (precedent: `cluster.ts` / addressPools)
**And** таб виден только при `isSystemAdmin` (gate на видимости таба, паритет с AddressPool/Cluster-admins табами; route-wrapper `RequireAdmin` отсутствует by-design)
**And** при нахождении на `/system/operations` нижний nav-пункт «Администрирование» **подсвечивается** — для этого в `COMMON_BOTTOM` `system`-matcher (`service-modules.tsx:229`, сейчас `/^\/system\/(regions|zones|address-pools|cluster\/admins)/`) добавлен сегмент `operations` (иначе literal `operations` не матчится и nav не highlight'ится — тот же класс упущения, что отмечен для других сегментов)

**Given** обычный (не-admin) пользователь (`isSystemAdmin == false`)
**Then** таб «Операции (кластер)» в `AdminLayout` НЕ виден; прямой переход на `/system/operations` не даёт данных (Internal RPC всё равно вернёт `403` по admin-tier FGA Check — 1.2-15a, defense-in-depth)

### 1.2-25 (edge — dangling op в UI graceful)
**Given** в списке операция, чей ресурс уже удалён (`resource_id` указывает на removed)
**Then** строка рендерится по данным операции (description/id/created/status), без обращения к удалённому ресурсу падением; cross-domain/within-service dangling-ref грациозен (`data-integrity.md` §4)

---

## §J. e2e smoke (через api-gateway, newman; ≥1 happy + ≥1 negative на новый контракт)

### 1.2-26 (smoke — User/AccessBinding ListOperations happy+negative)
**Given** seed: User `usr-W` с Delete-flow-операцией; AccessBinding `acb-B` с create+delete
**When** `GET /iam/v1/users/usr-W/operations` и `GET /iam/v1/accessBindings/acb-B/operations`
**Then** оба `200`, JSON `{operations:[…],nextPageToken}` camelCase
**And** negative: `GET /iam/v1/users/garbage/operations` → `400`; `…?pageToken=bad` → `400`; (если authz активен в suite) без viewer → `403`

### 1.2-27 (smoke — module account-scoped list happy+negative)
**Given** seed account `acc-X` с дочерними ресурсами+операциями
**When** `GET /iam/v1/accounts/acc-X/operations:all?pageSize=100`
**Then** `200`, агрегированный набор операций `acc-X`; пагинация по `nextPageToken` работает (2-я страница)
**And** negative: `acc-MISSING` (well-formed) → `200` пустой; malformed → `400`; чужой account без viewer → `403`

### 1.2-28 (smoke — Internal cluster-wide НЕ на external; isolation-test обновлён)
**Given** стенд
**When** `GET /iam/v1/internal/operations` через **external** endpoint
**Then** недоступно на external (404/unknown); тот же путь через internal mux (admin, isSystemAdmin) → `200`
**And** path `/iam/v1/internal/operations` добавлен в `internalRESTPaths` теста `kacho-api-gateway/internal/restmux/external_isolation_test.go` — RED (отсутствует) → GREEN (после регистрации в internal mux), P0 ban#6-гейт (см. §6 S4 DoD)

### 1.2-29 (smoke — async write → виден в per-resource И account-scoped ListOperations)
**Given** `POST /iam/v1/accessBindings {resourceType:"account", resourceId:"acc-X", …}` → `Operation`; polling `GET /operations/{id}` → `done:true`
**When** затем `GET /iam/v1/accessBindings/{id}/operations` и `GET /iam/v1/accounts/acc-X/operations:all`
**Then** только что созданная операция присутствует в per-resource списке (цикл async-мутация → `resource_id`-денормализация → ListOperations)
**And** та же операция присутствует в account-scoped списке `acc-X` (цикл async-мутация → синхронная `account_id`-денормализация на op-creation → ListAllOperations) — поскольку binding на account-ресурс (D-9)

### 1.2-30 (smoke — SAKey-Issue op: per-resource + Internal видна, account-scoped НЕ видна; BLOCK-2)
**Given** seed account `acc-X` с `sva-Z ∈ acc-X`; `POST /iam/v1/serviceAccounts/sva-Z/keys` → `Operation`; polling `GET /operations/{id}` → `done:true`
**When** `GET /iam/v1/serviceAccounts/sva-Z/operations` (per-resource), `GET /iam/v1/accounts/acc-X/operations:all` (account-scoped), `GET /iam/v1/internal/operations` (Internal, admin)
**Then** SAKey-Issue-операция **присутствует** в per-resource списке `sva-Z` и в Internal cluster-wide списке
**And** SAKey-Issue-операция **отсутствует** в account-scoped списке `acc-X` (категория II, `account_id IS NULL` — narrow-scope, 1.2-11f)

---

## 3. Матрица трассируемости (сценарий → область → артефакт)

| Сценарии | Область | Затрагиваемые артефакты | Репо |
|---|---|---|---|
| 1.2-01..09 | User/AB per-resource ListOperations (proto+iam) | `iam/v1/user.proto`, `access_binding.proto` (новые RPC+msg); iam handler/use-case (зеркало `shared/list_operations.go`); regen `gen/` | kacho-proto, kacho-iam |
| 1.2-10, 26 | gateway public-регистрация per-resource | `allowlist/list.go` + `rest_route_table_gen.go` + `restmux/mux.go` public; permission_catalog entry (viewer, `iam_user`/`iam_access_binding`) | kacho-api-gateway, kacho-proto (catalog-gen) |
| 1.2-11, 11a..11e, 13,14, 17,18, 27 | module account-scoped public RPC + `account_id`-фильтр + явное `account_id`-поле в metadata (исчерпывающая энумерация — S1) | proto `AccountService.ListAllOperations` (D-4) + **`account_id` non-first поле в IAM `*Metadata` категории (I)** (вкл. `AddGroupMemberMetadata`/`RemoveGroupMemberMetadata` — BLOCK-1); iam use-cases стампят `Metadata.account_id` sync (D-8); permission_catalog `iam.account_operationses.listAll`; gateway public | kacho-proto, kacho-iam, kacho-api-gateway |
| **1.2-11a..11e, 18a, S2** | **corelib blast-radius: `account_id`-колонка + read-by-exact-name + common-migration** | corelib `operations/repo.go` (читать `account_id` по точному имени поля — отдельный additive-экстрактор, НЕ расширять `_id`-suffix-loop; стампить в single `Create`-INSERT, не в worker); `operations.ListFilter.AccountID`; **`migrations/common`** nullable-колонка + partial cursor-индекс `(account_id, created_at, id) WHERE account_id IS NOT NULL`; затрагивает **vpc/compute/nlb/apps** (CI-пиннинг siblings) | **kacho-corelib** (+ все consumer-репо для CI) |
| 1.2-12, 12a, 15,15a,16, 24, 28 | cluster-wide Internal RPC + admin-tier (включает Internal-only op-producers: GrantClusterAdmin/ForceLogout/WriteTuples/Upsert — категория Internal-only, `account_id IS NULL`) | proto `InternalOperationsService.ListIamOperations` (Internal-only); iam impl на :9091 — фильтр без `account_id`-ограничения возвращает все IAM-op-строки, включая op-метаданные Internal-only-сервисов (proto-метаданные тех сервисов НЕ трогаются); **internal** restmux-блок (`iamInternalAddr`, `mux.go`); permission_catalog `system_admin`/`cluster`/`acr=2`; `internalRESTPaths` в `external_isolation_test.go` — `api-gateway-registrar` | kacho-proto, kacho-iam, kacho-api-gateway |
| **1.2-11f, 30 (BLOCK-2)** | **SAKey/Condition op — категория (II) narrow-scope: per-resource + Internal, НЕ account-scoped** | iam use-cases SAKey-Issue/Revoke (`sa_keys/usecases.go:188-199,544-555`) + Conditions-Create/Update/Delete — `Metadata.account_id` **намеренно НЕ** стампится (категория II); `resource_id` денормализуется существующей reflection (`sva-…`/`cnd-…`) → видны per-resource `ServiceAccount`/`Condition` ListOperations + cluster-wide Internal (1.2-12); proto-метаданные `IssueSAKeyMetadata`/`RevokeSAKeyMetadata`/`*ConditionMetadata` **не трогаются** (account_id не добавляется) | kacho-iam (+ kacho-proto: подтвердить, что метаданные остаются без `account_id`) |
| 1.2-16a (privacy) | within-account viewer-scope без per-creator-фильтра | **обязательная** by-design запись в `kacho-iam/docs/architecture/` (D-12 — S3 DoD-артефакт, физически написан, не только упомянут); newman/integration — viewer видит ops других члена account | kacho-iam (+ docs/architecture) |
| 1.2-19..23, 25 | UI вкладка «Операции» (7) + nav «Операции» + account-scoped module page | `service-modules.tsx` (IAM `items` += «Операции»), `App.tsx` (route `/iam/operations` ПЕРЕД `IAM_DETAIL_SPECS.map`), новая module-ops page (читает account из `context-store`, один RPC, НЕ fan-out), `ResourceShell` ops-tab покрывает User/AB (никто не ставит `hideOperations`) | kacho-ui |
| **1.2-24 (admin UI)** | **admin cluster-wide экран `/system/operations`** | `App.tsx` (route под `AdminLayout`), `AdminLayout.tsx` (новый таб, `visible: isSystemAdmin`), новая admin-ops page (generic `api.list` на `/iam/v1/internal/operations`), `service-modules.tsx` `system`-блок + **`COMMON_BOTTOM` `system`-matcher regex (`:229`) += `operations`** (nav-highlight) | kacho-ui |
| 1.2-29 | e2e полный цикл async→per-resource+account-scoped ListOperations | newman cases | kacho-api-gateway / kacho-test |
| все | deploy/seed для smoke | helm/compose без новых сервисов; seed-данные | kacho-deploy |

---

## 4. Out-of-scope / Non-goals

- **Изменение существующих 5 per-resource `ListOperations`** (Account/Project/SA/Group/Role) поведенчески — не трогаем (D-6); их «no-Get → empty-list» семантика и отсутствие per-creator-фильтра принимаются как паритет (§1.2-04, D-12). (Примечание: они получат `account_id`-стамп через изменения metadata/use-case, но контракт их ответа не меняется.)
- **Изменение `OperationService.Get`/`Cancel`** (prefix `iop`→iam, ownership-gated per-creator) — не трогаем.
- **Watch/стриминг операций** — нет (конвенция: polling, Watch не существует).
- **client-side fan-out агрегация для account-scoped module-list** (как у VPC `OperationsPage`) — осознанно отвергнута (D-3) в пользу серверного скоупа по `account_id`-колонке; VPC/NLB-страницы не трогаем.
- **Резолв owning-account для project/cluster/cross-service AccessBinding на op-creation** (доп. Project-read) — отвергнут (D-9 narrow-scope); такие binding-операции в account-scoped публичный список не попадают (видны per-resource + Internal).
- **SAKey-Issue/Revoke и Condition-Create/Update/Delete операции — НЕ в account-scoped публичном списке** (видны per-resource на owning ServiceAccount / Condition + cluster-wide Internal). Зеркало AccessBinding narrow-scope (D-9): резолв owning-account для этих метаданных требовал бы доп. SA-read / Condition-read на mutation-path (`service_account_id`/`condition_id` несут только id ресурса, не account) — отвергнут как недешёвый; категория (II), `account_id IS NULL` (BLOCK-2, 1.2-11f). **SAKey/Conditions при этом НЕ ретайрнуты** — это LIVE public сервисы (`grpc_register.go:48,54`); ретайрнуты только GDPR/SCIM-SAML/CAEP-feed (+ прочие из CLAUDE.md §1 «Retired»), а `InternalSessionRevocationsService` — Internal-only, не retired.
- **Новые типы операций / новые async-мутации IAM** — нет; работаем с уже существующими.
- **Изменение FGA-модели** сверх добавления permission_catalog-entries (viewer-gate для 2 новых per-resource RPC; `viewer`-scope для account-scoped module-RPC; `system_admin`/`cluster` для Internal cluster-wide RPC). Если для `iam_access_binding` нет `viewer`-relation — fallback на `account`-scope (D-2), без правки FGA-модели.
- **Project-scoped IAM module-list** — нет (IAM не project-scoped; скоуп — account + cluster-wide-Internal, D-4).
- **NLB `/nlb/operations`** (nav-stub без route) — вне scope этой IAM-фазы.

---

## 5. Решённые вопросы (ранее открытые — закрыты автором до APPROVED; ревьюер подтверждает)

Все вопросы предыдущего раунда закрыты дизайн-решениями D-1…D-12 после сверки с ground-truth (corelib `operations/repo.go`, iam use-cases, api-gateway authz/permission-catalog/restmux, kacho-ui context-store). Ниже — финальные решения, НЕ переоткрывать после APPROVED.

1. **Размещение account-scoped module-RPC — РЕШЕНО: метод `AccountService.ListAllOperations`** (REST `GET /iam/v1/accounts/{account_id}/operations:all`), НЕ отдельный `IamOperationsService` (D-4). Rationale: паритет scope_extractor (`object_type:"account"`, `from_request_field:"account_id"`, relation `viewer`) и FQN-формы `iam.account_operationses.listAll` (1:1 RPC→permission, distinct от существующего `…listOperations`). cluster-wide — отдельный `InternalOperationsService.ListIamOperations` (Internal-only).
2. **Семантика несуществующего ресурса — РЕШЕНО: паритет с существующими 5 IAM-ListOperations** — well-formed-но-нет → `OK` с пустым списком (НЕ `Get`/`NOT_FOUND`), malformed → `INVALID_ARGUMENT` первым стейтментом (§1.2-04, §1.2-13). Ground-truth: shared-helper фильтрует по `resource_id`/`account_id` без предварительного `Get`. Требование `NOT_FOUND` сменило бы и 5 существующих → вне scope (D-6).
3. **FGA `object_type` для viewer-gate — РЕШЕНО (D-2): `iam_user`** (подтверждено — `UserService/Get` уже использует `iam_user` в permission_catalog → объект существует); **`access_binding`** — проверить наличие `viewer`-relation на `iam_access_binding` в FGA-модели при impl, fallback на родительский `account`-scope, если объекта нет (наблюдаемое поведение не меняется). account-scoped module-RPC — `object_type:"account"`, relation `viewer` (существует).
4. **Денормализация `account_id` для ВСЕХ account-owned IAM-операций — РЕШЕНО (D-5/D-8, заменяет фиктивную reflection-симметрию B1; исчерпывающая энумерация — S1-таблица, «каждое» из прошлой ревизии устранено):** добавить **явное non-first `account_id`-поле** в IAM `*Metadata` категории (I) — Project/SA/Group CRUD + **AddGroupMember/RemoveGroupMember** (BLOCK-1 fix) + DeleteUser + Create/DeleteAccessBinding; `*Account` и `InviteUser` его уже имеют. corelib читает `account_id` **по точному имени поля** (отдельный additive-экстрактор, не суффикс `_id`), use-case стампит синхронно на op-creation. Покрытие (GWT): Project 1.2-11a; SA/Group-CRUD 1.2-11b; **Group member-change 1.2-11e**; User-Delete 1.2-11c; AccessBinding 1.2-11d. **STAY `account_id IS NULL` (категория II):** cluster-global **Role** — account-родителя нет → Internal-only (1.2-12); **project/cluster-scoped AccessBinding** — owning account на op-creation не резолвится (narrow-scope D-9) → Internal + per-resource; **SAKey-Issue/Revoke** и **Conditions-Create/Update/Delete** — LIVE public async-мутации (BLOCK-2, ground-truth `grpc_register.go:48,54`; metadata `service_account_id`/`condition_id`, owning account резолвится лишь доп. read), категория (II) консистентна с D-9 (доп. read не берётся) → видны per-resource (owning SA / Condition) + cluster-wide Internal, НЕ в account-scoped списке (1.2-11f). **RETIRED (категория III) — ТОЛЬКО:** GDPR-erasure / SCIM-SAML / CAEP-push-feed (`kacho-iam` CLAUDE.md §1 строки 61-63) + JIT-PIM/Break-glass/Access-review/Compliance/TrustPolicy/OpaBundle/FederationExchange (не зарегистрированы). **Session-revocation (`InternalSessionRevocationsService`) — Internal-only (`grpc_register.go:86`), НЕ retired** — не входит в публичный account-scoped список by-design (ban #6), это другое основание, чем «ретайрнут». **Internal-only op-producers (AUDIT-EXHAUSTIVENESS, `registerInternalServices`):** `InternalClusterService.Grant/RevokeAdmin`, `InternalIAMService.ForceLogout`, `InternalAuthorizeService.WriteTuples`, `InternalUserService.UpsertFromIdentity/OnRecoveryCompleted` — LIVE, пишут op в общую таблицу, метаданные без `account_id` → видны в cluster-wide Internal `ListIamOperations` (1.2-12/1.2-12a), НЕ в account-scoped; account_id-стамп не добавляется (симметрично D-9). Re-audit классифицирует ВСЕ op-producing сервисы обоих листенеров (§6 S1).
5. **AccessBinding owning-account — РЕШЕНО (D-9): NARROW-SCOPE.** account-scoped список включает только binding'и на account-ресурс (`ResourceType=="account"`); project/cluster/cross-service binding-операции — через per-resource `ListOperations` + cluster-wide Internal. Tradeoff (доп. Project-read на mutation-path отвергнут как недешёвый) задокументирован.
6. **Приватность within-account — РЕШЕНО (D-12): viewer-scope без per-creator-фильтра** (паритет с 5 существующими); раскрытие `principalId`/`principalDisplayName` других членов account account-вьюеру — осознанно принято (by-design в `kacho-iam/docs/architecture/`), per-id `Get/Cancel` остаётся ownership-gated.
7. **Admin cluster-wide UI — РЕШЕНО (D-11): IN SCOPE**, экран `/system/operations` под `AdminLayout`, gate `isSystemAdmin`, потребляет Internal `/iam/v1/internal/operations` (fallback на §4 Non-goal — только если ревьюер сочтёт скоуп раздутым).

---

## 6. Definition of Done (по стадиям; порядок — build-граф `polyrepo.md`)

**Гейт:** документ получает `✅ APPROVED` от `acceptance-reviewer` до старта `superpowers:writing-plans` → `integration-tester` (RED-тесты) → `rpc-implementer`. Открытые вопросы §5 закрыты в APPROVED-версии.

**S1 — proto (`kacho-proto`):** новые RPC/msg `UserService.ListOperations`, `AccessBindingService.ListOperations` (§A); module-RPC `AccountService.ListAllOperations` (account-scoped public, `:all`-suffix) + `InternalOperationsService.ListIamOperations` (Internal cluster-wide) с http/permission/required_relation/scope_extractor/required_acr_min аннотациями.

**Исчерпывающая энумерация `account_id`-полей в IAM `*Metadata` (по построению полная — implementer НЕ угадывает; «каждое» из прошлой ревизии заменено явным списком).** Каждое `*Metadata`-сообщение попадает ровно в одну из трёх категорий:

| Категория | `*Metadata`-сообщения | Действие в S1 | Источник `account_id` на op-creation (S3) |
|---|---|---|---|
| **(I) GET `account_id`** (попадают в account-scoped список D-4a) | `CreateAccountMetadata`/`UpdateAccountMetadata`/`DeleteAccountMetadata` (**уже** есть `account_id`); `CreateProjectMetadata`/`UpdateProjectMetadata`/`DeleteProjectMetadata`; `CreateServiceAccountMetadata`/`UpdateServiceAccountMetadata`/`DeleteServiceAccountMetadata`; `CreateGroupMetadata`/`UpdateGroupMetadata`/`DeleteGroupMetadata`; **`AddGroupMemberMetadata`/`RemoveGroupMemberMetadata`** (BLOCK-1 fix: COVER); `InviteUserMetadata` (**уже** есть `account_id`); `DeleteUserMetadata`; `CreateAccessBindingMetadata`/`DeleteAccessBindingMetadata` (**но** проставляется только при `ResourceType=="account"` — narrow-scope D-9) | добавить явное поле `account_id` тем, у кого его нет (всё кроме `*AccountMetadata` и `InviteUserMetadata`) | Account: новый `accID`; Project/SA/Group(CRUD): `*.AccountID` / `current.AccountID`; **Group AddMember/RemoveMember: `g.AccountID`** (загружается sync для authz — `add_member.go:56,61` / `remove_member.go:55,60`); User.Delete: `target.AccountID` (может быть `""`); AccessBinding: `ResourceID` при `ResourceType=="account"`, иначе пусто (D-9) |
| **(II) STAY `account_id IS NULL`** (видны только Internal cluster-wide + per-resource) | `CreateRoleMetadata`/`UpdateRoleMetadata`/`DeleteRoleMetadata` (cluster-global Role — account-родителя нет); `Create/DeleteAccessBindingMetadata` при `ResourceType != "account"` (project/cluster/cross-service binding — owning account на op-creation не резолвится, D-9); **`IssueSAKeyMetadata`/`RevokeSAKeyMetadata`** (LIVE public `SAKeyService`, `grpc_register.go:54`; metadata несёт `service_account_id`(1), owning account резолвится лишь доп. SA-read на mutation-path — тот же cost, что D-9 отвергает → narrow-scope, BLOCK-2); **`CreateConditionMetadata`/`UpdateConditionMetadata`/`DeleteConditionMetadata`** (LIVE public `ConditionsService`, `grpc_register.go:48`; op-write site `internal/service/conditions_crud_service.go:151,298,360` — **ВНЕ `internal/apps/`**; metadata несёт `condition_id`(1), owning account резолвится лишь доп. read → narrow-scope, BLOCK-2) | поле `account_id` **может** присутствовать в proto (для формальной симметрии), но use-case его **не** заполняет → колонка `NULL`. **SAKey/Conditions — НЕ retired:** их op-строки получают `resource_id` (`sva-…` / `cnd-…`) через существующую reflection и видны в per-resource `ServiceAccount`/`Condition` ListOperations + cluster-wide Internal, но НЕ в account-scoped публичном списке (1.2-11f, BLOCK-2; (II) — осознанный выбор, симметричный D-9, доп. read **не** берётся) | — (намеренно не проставляется) |
| **(III) RETIRED / OUT OF SCOPE** (не зарегистрированы в `grpc_register.go` — proto-only/удалены) | **только** GDPR-erasure / SCIM-SAML / CAEP-push session-revocation **feed** (RFC 8417) + JIT-PIM / Break-glass / Access-review / Compliance-report / TrustPolicy / OpaBundle / FederationExchange (`kacho-iam` CLAUDE.md §1 «Retired», KAC-198/214/222) | **не существуют** как live RPC — в этой фазе не создаются и не трогаются | — |
| **(Internal-only op-producers, не (III))** — LIVE на internal-листенере (`registerInternalServices`, `grpc_register.go:63-87`), пишут `iop`-op-строки в общую `kacho_iam` `operations`-таблицу, метаданные `account_id` НЕ несут | `InternalClusterService.Grant/RevokeAdmin` (`Grant/RevokeClusterAdminMetadata{cluster_admin_grant_id,subject_id}`); `InternalIAMService.ForceLogout` (`ForceLogoutMetadata{user_id}`); `InternalAuthorizeService.WriteTuples` (`WriteTuplesMetadata{idempotency_key}` — нет `_id`-поля → `resource_id=""`); `InternalUserService.UpsertFromIdentity/OnRecoveryCompleted` (`*Metadata{user_id,…}`); `InternalSessionRevocationsService` (KAC-127) | **Internal-only** (:9091, ban #6) — НЕ retired; `account_id`-стамп НЕ добавляется (резолв owning-account = доп. read, не берётся, симметрично D-9); proto-метаданные не трогаются | **видны в cluster-wide Internal `ListIamOperations`** (genuine cluster IAM-ops, D-4b/1.2-12); НЕ в account-scoped публичном списке; per-resource — по `resource_id` где `_id`-поле есть (`cluster_admin_grant_id`/`user_id`), для WriteTuples — нет |

`account_id` — **non-first** поле в каждом `*Metadata` категории (I) (поле 1 остаётся `<res>_id`: `project_id`/`group_id`/`user_id`/`access_binding_id`/…), чтобы corelib `extractResourceID` (first-`_id`-suffix match, `repo.go:463-488`) по-прежнему вернул id ресурса, а НЕ `account_id`. corelib читает `account_id` по **точному имени** (additive-экстрактор, S2 — НЕ расширять suffix-loop). **Экстрактор добавляется в `CreateWithPrincipal` (`repo.go:118` — туда же, где вызывается `extractResourceID(op.Metadata)` на строке 127), а НЕ в `Create` (`repo.go:76`): IAM use-case'ы зовут принципал-несущий путь, поэтому `Create` делегирует в `CreateWithPrincipal` — экстрактор по точному имени `account_id` обязан жить в `CreateWithPrincipal`, иначе при вызове через `Create` он не выполнится (BLOCK-2 implementer-note).** permission_catalog gen — distinct FQN `iam.account_operationses.listAll` + `system_admin`/`cluster`/`acr=2` для Internal RPC. regen `gen/go` + `gen/permission_catalog.json`; `buf lint`+`buf breaking`+`buf validate` зелёные (добавление поля/RPC — **чисто additive**, breaking остаётся green); ревью `proto-api-reviewer`. DoD: buf зелёный, additive, энумерация исчерпывающая.

> **Исчерпывающий re-audit category-покрытия (ревизия 4, BLOCK-2) — сверено с `grpc_register.go registerPublicServices`.** Каждый публичный сервис, чьи RPC возвращают `operation.Operation`, классифицирован в (I) или (II) с явной причиной; (III) — **только** не-зарегистрированные/удалённые; session-revocation — Internal-only, НЕ (III):
> - **(I) GET `account_id`:** `AccountService` (Create/Update/Delete), `ProjectService` (Create/Update/Delete), `ServiceAccountService` (Create/Update/Delete), `GroupService` (Create/Update/Delete + AddMember/RemoveMember), `UserService` (Delete + Invite), `AccessBindingService` (Create/Delete — только при `ResourceType=="account"`, D-9). **Причина:** owning account удержан sync на op-creation без доп. read.
> - **(II) STAY `account_id IS NULL`:** `RoleService` (Create/Update/Delete — cluster-global, нет account-родителя); `AccessBindingService` при `ResourceType != "account"` (D-9); **`SAKeyService` (Issue/Revoke)** и **`ConditionsService` (Create/Update/Delete)** — оба LIVE public (BLOCK-2), owning account резолвится лишь доп. read на mutation-path (тот же cost, что D-9 отвергает) → narrow-scope; видны per-resource (owning `sva-…` / `cnd-…`) + cluster-wide Internal. **Причина:** доп. read не берётся (консистентно с D-9).
> - **(III) RETIRED:** GDPR / SCIM-SAML / CAEP-push-feed / JIT-PIM / Break-glass / Access-review / Compliance-report / TrustPolicy / OpaBundle / FederationExchange — **не зарегистрированы** (proto-файлы `access_review_service.proto`/`compliance_report_service.proto`/`trust_policy_service.proto` ещё лежат в `kacho-proto`, но сервисы НЕ в `grpc_register.go` → не live).
> - **Internal-only op-producers (НЕ (III), `account_id IS NULL`)** — сверено с `registerInternalServices` (`grpc_register.go:63-87`); пишут `iop`-op-строки в ту же `kacho_iam` `operations`-таблицу через `operations.NewFromContext`+`opsRepo.Create`, метаданные `account_id` **НЕ** несут (verified) → никогда не в account-scoped списке; **включаются в cluster-wide Internal `ListIamOperations`** (это genuine cluster IAM-операции, D-4b/1.2-12):
>   - `InternalClusterService.GrantAdmin/RevokeAdmin` (`cluster/grant_admin.go:149-163`, `revoke_admin.go:125`) — metadata `Grant/RevokeClusterAdminMetadata{cluster_admin_grant_id(1), subject_id(2)}` → `resource_id=cluster_admin_grant_id`.
>   - `InternalIAMService.ForceLogout` (`internal_iam/force_logout.go:178-181`) — metadata `ForceLogoutMetadata{user_id(1)}` → `resource_id=user_id`.
>   - `InternalAuthorizeService.WriteTuples` (`internal_authorize/handler.go:59-62`) — metadata `WriteTuplesMetadata{idempotency_key(1)}` — **нет `_id`-поля вообще** → `extractResourceID` вернёт `""` (op-строка с пустым `resource_id` — это уже текущее поведение, не регресс; видна только в cluster-wide Internal, не per-resource).
>   - `InternalUserService.UpsertFromIdentity/OnRecoveryCompleted` (`user/internal_upsert.go:116-124`, `internal_on_recovery.go:157-165`) — metadata `UpsertFromIdentityMetadata{user_id(1),created(2)}` / `OnRecoveryCompletedMetadata{user_id(1),revoked_session_count(2)}` → `resource_id=user_id`.
>   - `InternalSessionRevocationsService` (`grpc_register.go:86`, KAC-127) — Internal-only, аналогично.
>   Все — Internal-only (ban #6); в публичный account-scoped список не входят by-design; account_id-стамп **не** добавляется (резолв owning-account потребовал бы доп. read — не берётся, симметрично D-9). proto-метаданные этих RPC **не трогаются**.
>
> `AuthorizeService` — публичный, но его RPC **не** возвращают `Operation` (sync authz-check) → не op-producing, вне category-таблицы. `OperationService` (Get/Cancel) — sync by-id, не List, не производит новых op-строк. **Итог re-audit: классифицированы ВСЕ op-producing IAM-сервисы обоих листенеров — public (I)/(II) выше + Internal-only op-producers (этот блок); (III) — только незарегистрированные/удалённые. Других неклассифицированных live op-producing сервисов нет.**

**S2 — corelib (`kacho-corelib`) [BLAST-RADIUS: затрагивает vpc/compute/nlb/apps]:** `operations.ListFilter.AccountID`; в `operations/repo.go` — читать `account_id` **по точному имени поля** (additive к существующему `resource_id`-suffix-reflection; НЕ переиспользовать `_id`-suffix-loop — он вернёт `user_id` для InviteUserMetadata), **экстрактор размещается в `CreateWithPrincipal` (`repo.go:118`, рядом с вызовом `extractResourceID(op.Metadata)` на `:127`), а НЕ в `Create` (`:76`): IAM use-case'ы идут через принципал-несущий путь, `Create` делегирует в `CreateWithPrincipal` — экстрактор в `Create` был бы обойдён** (implementer-note); стампить в **единственном `Create`-INSERT** синхронно (не в worker); **common-миграция** (`migrations/common`): `account_id` **nullable**-колонка + partial cursor-индекс `(account_id, created_at, id) WHERE account_id IS NOT NULL` — `migration-writer` → `db-architect-reviewer` (не редактировать применённые). DoD (TDD RED→GREEN): integration-тест (testcontainers) — (a) фильтр `List(AccountID=…)` + cursor-пагинация; (b) **back-compat: не-IAM op без `Metadata.account_id` пишется успешно с `account_id IS NULL`, существующий `resource_id`-путь не сломан** (1.2-18a). Merge ДО сервисов; CI siblings временно пиннятся к feature-ветке corelib (`polyrepo.md`).

**S3 — iam (`kacho-iam`):** handler+use-case для User/AB per-resource ListOperations (зеркало `shared/list_operations.go`); use-case `AccountService.ListAllOperations` (фильтр `AccountID`) + `InternalOperationsService.ListIamOperations`; **каждый mutation-use-case стампит `Metadata.account_id` синхронно на op-creation** из in-scope account (Project/SA/Group: `*.AccountID`; Account: новый `accID`; User.Delete: `target.AccountID`; AccessBinding: только `ResourceType=="account"` → `ResourceID`, иначе пусто — D-9; **Group AddMember/RemoveMember: `g.AccountID`**, загружаемый для authz — 1.2-11e; account-less → `nullableString`→SQL `NULL`, не `''`). **SAKey-Issue/Revoke (`sa_keys/usecases.go:188-199,544-555`) и Conditions-Create/Update/Delete (`internal/service/conditions_crud_service.go:151,298,360` — op-write site ЖИВЁТ ВНЕ `internal/apps/`, не перепутать пакет) — `Metadata.account_id` НЕ стампится (категория II narrow-scope, BLOCK-2)**: их op-строки получают `account_id IS NULL` и видны per-resource (`sva-…`/`cnd-…`) + cluster-wide Internal, но не в account-scoped списке (1.2-11f); proto-метаданные этих RPC не меняются. **Internal-only op-producers (`InternalClusterService.Grant/RevokeAdmin` `cluster/grant_admin.go:149-163`/`revoke_admin.go:125`; `InternalIAMService.ForceLogout` `force_logout.go:178-181`; `InternalAuthorizeService.WriteTuples` `internal_authorize/handler.go:59-62`; `InternalUserService.UpsertFromIdentity/OnRecoveryCompleted` `user/internal_upsert.go:116-124`/`internal_on_recovery.go:157-165`; session-revocation) — `Metadata.account_id` тоже НЕ стампится (AUDIT-EXHAUSTIVENESS)**: их op-строки `account_id IS NULL`, видны в cluster-wide Internal `ListIamOperations`, НЕ в account-scoped (1.2-12a); proto-метаданные этих сервисов не меняются. **AB per-resource `ListOperations` НЕ деградирует ниже viewer-tier**, если ни один объект не резолвится (никакого exempt/no-gate fallback) — сверить с `fga_model.fga` при S4-импле (D-2 fallback-на-`account`-scope, но всё равно ≥viewer, не bypass). **Обязательный артефакт S3 (DoD, не опционально):** by-design запись о privacy-модели (D-12 — сдвиг per-creator→per-scope-viewer, осознанное раскрытие `principalId`/`principalDisplayName` within-account) **физически написана** в `kacho-iam/docs/architecture/` (новый/дополненный .md), а не только упомянута в этом доке; PR без неё не считается done. Строгий TDD: integration-тесты §A/§B (включая propagation 1.2-11a..11e, privacy 1.2-16a) RED → GREEN в том же PR. `go test ./... -race`+`golangci-lint`+`govulncheck` зелёные.

**S4 — api-gateway (`kacho-api-gateway`):** `allowlist/list.go` + REST-route (`rest_route_table_gen.go`) + public restmux (`mux.go`) для User/AB ListOperations и `AccountService.ListAllOperations` (`api-gateway-registrar`); permission_catalog-entries (viewer для per-resource; `iam.account_operationses.listAll` viewer для account-scoped; `system_admin`/`cluster`/`acr=2` для Internal); Internal cluster-wide RPC — **только** internal mux (`iamInternalAddr`-блок), НЕ external (ban #6); **добавить `/iam/v1/internal/operations` в `internalRESTPaths` теста `internal/restmux/external_isolation_test.go`** (RED→GREEN, P0 ban#6). **iam internal-листенер: цепочка интерсепторов ОБЯЗАНА включать authz-Check для `InternalOperationsService.ListIamOperations`** (`security.md` «AuthN+AuthZ ВЕЗДЕ»; gateway catalog-entry сам по себе недостаточен — если caller обходит api-gateway и бьёт напрямую на iam :9091, backend-листенер обязан отклонить без `system_admin`, 1.2-15a). `make audit-list-filter` зелёный. newman §J (happy+negative) RED→GREEN.

**S5 — ui (`kacho-ui`):** вкладка «Операции» работает для всех 7 (User/AB больше не 404; никто не ставит `hideOperations`); IAM-nav «Операции» (`/iam/operations`, route ПЕРЕД `IAM_DETAIL_SPECS.map` `/:uid`) account-scoped page — account из **context-store** (`useContext((s)=>s.account)`), один RPC `…/operations:all`, не fan-out, guard при `!account`; **admin cluster-wide экран `/system/operations`** под `AdminLayout` (новый таб, `visible: isSystemAdmin`), generic `api.list` на Internal `/iam/v1/internal/operations`; **route `/system/operations` обязан стоять ВНУТРИ блока `<Route element={<AdminLayout/>}>` (`App.tsx:374-389`, рядом с `/system/regions`/`/system/zones`/`/system/address-pools`/`/system/cluster/admins`)** — иначе экран не получит admin-табы layout'а (implementer-note); **расширить `COMMON_BOTTOM` `system`-matcher regex (`service-modules.tsx:229`) сегментом `operations`** (иначе nav «Администрирование» не highlight'ится на `/system/operations`); empty/dangling-edge'и. `npx tsc --noEmit` + сборка + UI component/e2e RED→GREEN. Backend-контракт не трогается (ban #13).

**S6 — deploy (`kacho-deploy`):** helm/compose без новых сервисов; seed для smoke; `make dev-up` + reload-svc iam/api-gateway; smoke §J через port-forward.

**S7 — workspace/vault:** vault обновлён — `rpc/kacho-iam-*` (новые ListOperations + module-RPC), `edges/` если меняется gateway-routing, `KAC/KAC-<N>.md` («Затронутые сущности vault» + PR-URL); тикет Test→Done с артефактами. Финальная верификация: все newman зелёные, `go test ./... -race`/lint/vuln зелёные во всех затронутых репо.

**Заказчик** — финальный smoke/e2e (шаг 7): открыть деталь User/AccessBinding → таб «Операции» показывает список; открыть `/iam/operations` → account-scoped операции; `grpcurl`/`make e2e-test` на новые REST-пути.
