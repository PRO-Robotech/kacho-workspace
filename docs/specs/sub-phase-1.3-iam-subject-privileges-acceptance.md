# Sub-phase 1.3 (IAM Subject Privileges — видимость + grant) — Acceptance

> **Статус:** ✅ APPROVED (ревизия 1; `acceptance-reviewer` дал sign-off в первом раунде, 0 блокирующих, 6 non-blocking-замечаний учтены — см. §8. Перед стартом `superpowers:writing-plans` проставить KAC-номер вместо `KAC-TBD`.)
> **Дата:** 2026-06-18
> **Автор:** `acceptance-author`
> **Ревьюер:** `acceptance-reviewer` — _✅ APPROVED (ревизия 1); coverage 100% трёх verbatim-пунктов заказчика, 22 сценария, traceability через `1.3-NN`, ground-truth верифицирован против кода; все 6 open questions закрыты дефолт-рекомендациями._
> **Эпик/тикет:** KAC-TBD (фича «IAM subject privileges visibility + grant»; затронутые репо — `kacho-proto` / `kacho-iam` / `kacho-api-gateway` / `kacho-ui` / `kacho-deploy` / `kacho-workspace`(docs). **Номер тикета проставляется до старта `superpowers:writing-plans`** — фича → тикет СНАЧАЛА, `git-youtrack.md`; в финальном APPROVED-артефакте `KAC-TBD` не остаётся.)
> **Источник требований (verbatim intent заказчика):** «создание метода поиска подключенных ролей к пользователю или сервис аккаунту и выведи отдельным табом в ресурсы пользователи и сервис аккаунты и там же в табе привилегии выведи вверху кнопку добавить привилегии». То есть: (1) метод «найти роли, подключённые к User / ServiceAccount»; (2) вкладка «Привилегии» на странице деталей User И ServiceAccount; (3) вверху вкладки — кнопка «Добавить привилегии».
> **Ground-truth (сверено):** `kacho-proto/proto/kacho/cloud/iam/v1/access_binding_service.proto:95-104` (`ListBySubject` УЖЕ существует), `access_binding.proto:29-117` (форма AccessBinding), `role.proto:26-64` (Role, prefix `rol`), `kacho-iam/internal/apps/kacho/api/access_binding/{list_by_subject.go,helpers.go,create.go,delete.go}` (self-list policy + `requireGrantAuthority`), `internal/authzguard/authzguard.go` (`IsSelf`/`PermissionDenied`), `internal/repo/kacho/pg/access_binding_repo.go` (keyset `(created_at,id)` ASC, direct-only WHERE), `0001_initial.sql` (roles FK same-schema, group_members), `kacho-iam/CLAUDE.md §2.4/§3` (prefixes, strict-create), `kacho-ui/src/components/{ResourceShell.tsx,resource-detail-extensions.tsx,DetailShell.tsx}` (`ext.extraTabs` механизм, SecurityGroup «Правила» precedent), `kacho-ui/src/pages/iam/AccessBindingCreatePage.tsx:73-116` (preset через query-params), `kacho-ui/src/api/iam.ts:210-215` (`listAccessBindingsBySubject` уже есть), `kacho-ui/src/components/iam/IamRefLink.tsx` (lazy per-id resolve role name).
> **Образцы формата:** `sub-phase-1.2-iam-operations-acceptance.md`, `sub-phase-2.1-iam-ui-vpc-parity-acceptance.md`, `sub-phase-vpc-redesign-kac239-acceptance.md`.

---

## Обзор

Требуется дать оператору IAM-UI видимость «какие роли подключены к конкретному User или ServiceAccount» и быстрый путь «добавить привилегию» из контекста этого subject'а. Сегодня этого пути в продукте нет:

1. **Backend.** На `AccessBindingService` уже есть `ListBySubject(subject_type, subject_id)` (`access_binding_service.proto:95`), но он (a) **strict self-list** — `IsSelf`-guard в use-case (`list_by_subject.go:38-50`) пускает только запрос принципала про **самого себя** (для group — про группу, в которой он состоит); account-admin **не** может посмотреть привилегии другого члена своего account'а → `PermissionDenied`; (b) возвращает **сырые** `AccessBinding`-строки **без** resolved-имени роли и без человеко-читаемого scope; (c) **direct-only** (без group-производных). Таким образом «admin смотрит привилегии пользователя на странице деталей» текущим RPC **не реализуем**.
2. **UI.** Страницы деталей User и ServiceAccount рендерятся generic-движком `ResourceShell` (`App.tsx:447-464`); вкладки «Привилегии» нет ни на одной (есть только Обзор / Операции / JSON; у Group — members через `overviewBelow`). Кнопки «Добавить привилегии» с пресетом subject'а тоже нет: `AccessBindingCreatePage` умеет читать пресет из query-params, но **не блокирует** поле subject и **никто** его сейчас с пресетом subject'а не запускает.

Под-фаза закрывает дыру **новым read-RPC** `AccessBindingService.ListSubjectPrivileges` (sync, обогащённый: resolved role name + scope, broadened authz «self ИЛИ account-admin субъекта»), **не трогая** уже задеплоенный `ListBySubject` (его self-list-контракт остаётся как есть — обратная совместимость), + UI-вкладкой «Привилегии» на User и ServiceAccount + кнопкой «Добавить привилегии» (deep-link в `AccessBindingCreatePage` с залоченным subject'ом).

Документ описывает **только внешнее наблюдаемое поведение API и UI** (gRPC-коды, REST-формы, поведение экранов), не реализацию. Сценарии трассируются в имена integration- / newman- / UI-тестов через ID `1.3-<NN>`. Стандартные конвенции (`api-conventions.md` error-format / cursor-pagination / sync-read; `security.md` Internal-vs-public + AuthN+AuthZ везде; `data-integrity.md` cross-domain dangling-ref) нормативны и в тело не дублируются — только ссылками (§1).

---

## 0. Фиксированные дизайн-решения (предлагаются автором; подлежат approve ревьюером — затем НЕ переоткрывать)

| ID | Решение | Обоснование |
|---|---|---|
| **D-1** | **Новый RPC `AccessBindingService.ListSubjectPrivileges`** (sync read), **а НЕ** правка существующего `ListBySubject`. `ListBySubject` остаётся как есть (strict self-list, сырые строки) — никакого изменения его контракта/семантики. | `ListBySubject` уже задеплоен и потребляется (self-list инвариант — намеренная информационная защита, `list_by_subject.go:30-37`). Требование заказчика — admin-видимость привилегий **другого** subject'а с обогащённым выводом; это иной authz-tier и иная форма ответа. Менять self-list-контракт «на лету» = silent semantic break для текущих потребителей. Новый RPC — чистый additive, `buf breaking` зелёный. Размещение — на **`AccessBindingService`** (не отдельный `SubjectPrivilegesService`): subject-привилегия — это проекция AccessBinding'ов, паритет с уже живущими `ListByResource`/`ListBySubject`/`ListByAccount` на том же сервисе. |
| **D-2** | **Форма запроса.** `ListSubjectPrivilegesRequest { string subject_type (required, ≤32), string subject_id (required, ≤20), int64 page_size (≤1000), string page_token (≤100) }`. `subject_type ∈ {"user","service_account"}` для v1 (см. D-5 про group). | Паритет с `ListAccessBindingsBySubjectRequest`. cursor-pagination `(created_at,id)` ASC, opaque base64 `page_token`, `page_size` 0→default 50, max 1000 — как все list-RPC IAM (`api-conventions.md`, `access_binding_repo.go`). |
| **D-3** | **Форма ответа — обогащённая.** `ListSubjectPrivilegesResponse { repeated SubjectPrivilege privileges = 1; string next_page_token = 2 }`, где `SubjectPrivilege` — плоский message: `binding_id` (acb-…), `role_id` (rol-…), `role_name` (resolved), `resource_type`, `resource_id`, `scope` (enum CLUSTER/ACCOUNT/PROJECT), `created_at`, `status` (PENDING/ACTIVE/REVOKED), `granted_by_user_id`, `expires_at`, `derivation` (enum DIRECT для v1; зарезервировано GROUP — D-5). **Resolve `role_name` — JOIN `access_bindings ⋈ roles` в одной транзакции внутри той же `kacho_iam`** (FK `access_bindings_role_fk`, индекс `access_bindings_role_idx`, same-schema). Dangling role (роль удалена с `ON DELETE RESTRICT` — теоретически невозможно для активного binding, но REVOKED-binding может пережить) → `role_name=""` (UI fallback на raw id), без паники. | Заказчик просит видеть **имена ролей**, не сырые id (`IamRefLink` сейчас резолвит по одному per-row N+1 GET'ом — для вкладки это N round-trip'ов). Серверный JOIN дешевле и атомарен (within-service, `data-integrity.md`); не плодит N+1. **Только публично-безопасные поля** AccessBinding (id/role/scope/status/created_at/granted_by) — никаких инфра-чувствительных данных (`security.md`); `condition_id`/`builtin_condition` намеренно **не** включены в v1 (ABAC-overlay — отдельная поверхность, не требование заказчика). |
| **D-4** | **AuthZ-tier — broadened «self ИЛИ account-admin субъекта», НЕ cluster-admin-only, НЕ self-only.** Caller допускается, если EITHER: (a) `IsSelf(subject_id)` (свои привилегии); ИЛИ (b) caller — owner/`admin` **домашнего Account'а субъекта** (для User — `user.account_id`; для ServiceAccount — `serviceAccount.account_id`), резолв через зеркало уже существующей логики `requireGrantAuthority` (`helpers.go:59-119`: owner Account ИЛИ FGA `admin` на `account:<id>`). Иначе → `PermissionDenied` (gRPC `PERMISSION_DENIED`, REST 403). Анонимный → отклоняется первым (`RequireAuthenticated`). Permission FQN `iam.access_bindings_by_subjects.listSubjectPrivileges`, gateway permission-catalog entry с `required_relation:"viewer"`, `scope_extractor` cluster-floor + `required_acr_min:"2"` (паритет с `ListBySubject`); **реальный gate — in-handler self/account-admin policy** (catalog даёт ACR/anti-anon floor, точную авторизацию делает handler — как у `ListBySubject`/`Create`, где catalog `<exempt>`/cluster-floor, а handler авторитетен). | Требование заказчика помещает фичу на страницу деталей User/SA — это admin-контекст управления членами account'а. Self-only (как `ListBySubject`) фичу **не** реализует. Cluster-admin-only — слишком узко (account-owner не cluster-admin, но обязан видеть привилегии членов своего account). «self ИЛИ account-admin» — точный mirror установленного grant-authority-паттерна (тот же набор, что решает «кто может выдать/снять binding» в `Create`/`Delete`), значит «кто может выдать» == «кто может смотреть» — консистентно и минимально. **NB для impl/reviewer:** в `requireGrantAuthority` scope-объект — это **ресурс binding'а**; здесь scope-объект — **домашний Account субъекта** (`account:<subject.account_id>`), поэтому нужен предварительный `Users().Get`/`ServiceAccounts().Get` для резолва `account_id` (within-DB, same-schema) — это меняет цель Check, но не сам паттерн. |
| **D-5** | **v1 — DIRECT-only.** Возвращаются binding'и, где `subject_id` буквально равен запрошенному (как direct rows). **Group-производные** (effective) роли — **flagged follow-up** (`derivation=GROUP`-кейсы НЕ заполняются в v1; поле зарезервировано в proto для forward-compat). | Ground-truth: эффективные роли через членство дёшевы (single in-DB JOIN: `group_members WHERE member_type='user' AND member_id=$usr` → `access_bindings WHERE subject_type='group' AND subject_id IN (...)`; группы не вкладываются → ровно один уровень expansion, обе таблицы индексированы, same-schema). Но: (1) это **расширение семантики** ответа (UI должен различать «прямая роль» vs «через группу X»), (2) добавляет вопросы отображения и authz (видимость членства в чужих группах), (3) заказчик буквально просит «подключенные роли к пользователю» — DIRECT покрывает базовый кейс. Рекомендация: v1 DIRECT-only + `derivation`-enum зарезервирован; effective-roles — отдельная под-фаза (1.3b), где DIRECT-контракт расширяется additively (новые строки с `derivation=GROUP`), без breaking. **Решение фиксируется ревьюером: DIRECT-only v1 ИЛИ include-group-derived-now.** |
| **D-6** | **Subject-existence: well-formed-но-нет → `NOT_FOUND`** (НЕ empty-list). RPC первым делом резолвит subject (`Users().Get`/`ServiceAccounts().Get` для D-4 authz всё равно нужен) → если subject не существует → `NOT_FOUND "User usr-… not found"` / `"ServiceAccount sva-… not found"`. Subject существует, но 0 binding'ов → пустой `privileges` + пустой `next_page_token` (НЕ ошибка). | Отличие от `ListBySubject` (там empty-list для несуществующего — ground-truth: нет existence-precheck). Здесь existence-резолв **обязателен** для authz (D-4 читает `account_id` субъекта), поэтому NotFound «бесплатен» и даёт более точный контракт (паритет с `Get`-семантикой IAM «well-formed-но-нет → NotFound»). Это **осознанный** дизайн-выбор, не копирование `ListBySubject`. |
| **D-7** | **Malformed subject_id → sync `INVALID_ARGUMENT`** первым стейтментом RPC. `subject_id` должен соответствовать формату id IAM-субъекта **в зависимости от `subject_type`**: `subject_type="user"` ⇒ prefix `usr`; `subject_type="service_account"` ⇒ prefix `sva` (`corevalidate.ResourceID` / domain prefix-check). Несоответствие prefix↔type ⇒ `InvalidArgument "invalid <res> id '<X>'"`. `subject_type` вне `{user,service_account}` (v1) ⇒ `InvalidArgument "Illegal argument subject_type (allowed: user|service_account)"`. | `api-conventions.md`: malformed id → sync InvalidArgument первым стейтментом; well-formed-но-нет → NotFound. Жёсткая привязка prefix↔type предотвращает «sva-id под subject_type=user» (логическая каша) и делает контракт детерминированным. |
| **D-8** | **UI: вкладка «Привилегии» через `ext.extraTabs`** в `DetailExtension` для специй `users` и `service-accounts` (`resource-detail-extensions.tsx`), по precedent'у SecurityGroup «Правила» (`extraTabs: () => [{ id, label, count, render }]`, `ResourceShell.tsx:374`). Tab id — `privileges`, label — «Привилегии», `count` = число привилегий. Внутри — таблица (Роль / Scope / Статус / Создано), данные через **новый** `iamApi.listSubjectPrivileges(subject_type, subject_id)`-хелпер (`src/api/iam.ts`); строки роли резолвлены сервером (D-3), `IamRefLink` per-row **не** нужен. Empty-state «Привилегий нет». | Каноничный механизм добавления вкладки (`extraTabs`), без правки generic `ResourceShell`. `count` рендерится бейджем в rail-меню (`DetailShell.tsx:249`). Серверный resolve role_name убирает N+1. |
| **D-9** | **UI: кнопка «Добавить привилегии» вверху вкладки** → `navigate("/iam/access-bindings/create?subject_type=<t>&subject_id=<id>&lock_subject=1")`. `AccessBindingCreatePage` пре-заполняет subject из query-params (уже умеет, `:73-116`) **И блокирует** поля `subject_type`/`subject_id` (disabled `Select`, read-only) когда присутствует `lock_subject=1` — **новое поведение**, сегодня форма пресет не лочит. После успешного Create → возврат на вкладку «Привилегии» субъекта (`navigate(-1)` или deep-link назад) + рефетч списка (новая привилегия видна). Видимость кнопки — только если caller имеет grant-authority на субъекта (тот же D-4 tier; UI гейтит по `usePermissions()`/whoami, backend всё равно авторитетно отклонит). | Закрывает «кнопку добавить привилегии вверху таба». Subject-lock гарантирует, что админ создаёт binding **именно** для этого subject'а (не подменит из контекста чужого пользователя). Grant сам по себе — существующий `AccessBinding.Create` (async→Operation, strict-create), под-фаза его **не** меняет. |
| **D-10** | **Раскрытие чужих привилегий account-вьюеру — ОСОЗНАННОЕ ПРИНЯТОЕ решение** (паритет с D-12 под-фазы 1.2). account-admin/owner, смотрящий привилегии члена своего account'а, видит `role_name`, `scope`, `granted_by_user_id`, `created_at` этого члена. Это audit-видимость «кто и какие роли имеет внутри моего account» — НЕ leak. Кросс-account чтение блокируется D-4 (caller без admin на home-account субъекта → 403). | account — tenancy-граница IAM; админ account'а вправе видеть и аудировать привилегии своих членов (как он же вправе их выдавать/снимать — D-4 mirror). Записывается как conscious decision (`docs/architecture/` kacho-iam, не GitHub Issue). |

---

## 1. Связь с регламентом (нормативно; в тело не дублируется)

| Регламент | Где соблюдается |
|---|---|
| `api-conventions.md` — read **sync**, мутации async `Operation`; Watch не существует (polling) | §A (`ListSubjectPrivileges` — sync read); grant — существующий async `AccessBinding.Create` (§D) |
| `api-conventions.md` — cursor pagination `(created_at,id)` ASC, `page_token` opaque base64, `page_size` 0→default(50), max 1000 | 1.3-02, 1.3-09 |
| `api-conventions.md` — REST `/<service>/v1/<resource>`, suffix-action `:verb`; JSON camelCase (`subjectId`, `roleName`, `createdAt`, `nextPageToken`, `pageToken`) | §A REST-форма, §J smoke |
| `api-conventions.md` — error-format gRPC-коды; malformed id → sync `INVALID_ARGUMENT` первым стейтментом (`corevalidate.ResourceID`); well-formed-но-нет → `NOT_FOUND` (D-6, осознанно — existence-резолв нужен для authz) | 1.3-04, 1.3-05, 1.3-06 |
| `security.md` §AuthN+AuthZ ВЕЗДЕ — каждый RPC проходит per-RPC Check; read-RPC → viewer-tier floor + handler-авторитетная точная политика; анонимный fail-closed | 1.3-03 (self), 1.3-07/1.3-07a (account-admin), 1.3-08 (кросс-account 403), 1.3-10 (anon 401/403) |
| `security.md` §Internal-vs-external (ban #6) — RPC **публичный** (нужен tenant-UI на странице деталей), НЕ Internal; admin-видимость здесь = account-scoped, не cluster-wide → остаётся на public surface с handler-gate | §A (public, external endpoint); cluster-wide dump НЕ вводится (вне scope) |
| `security.md` §Инфра-чувствительные данные — публичная поверхность не светит инфра-поля | 1.3-11 (`SubjectPrivilege` несёт только id/role/scope/status/created_at/granted_by — никаких placement/underlay/condition-internals) |
| `data-integrity.md` §within-service — resolve role_name **JOIN на DB-уровне** (FK same-schema), не software N+1 fan-out | D-3, 1.3-01, 1.3-12 |
| `data-integrity.md` §cross-domain — consumer грациозно переживает dangling-ref | 1.3-13 (binding ссылается на удалённый/REVOKED-контекст — список/UI не падает, role_name fallback) |
| `00-kacho-core.md` ban #9 (мутации→Operation), #10 (within-DB инвариант на DB-уровне), #12 (TDD), #1 (APPROVED перед кодом) | §A read-only (read sync, не мутация); §D grant — существующий Operation-контракт; DoD §6 (RED→GREEN, integration+newman в том же PR) |
| `polyrepo.md` §порядок merge | §6 DoD: proto → iam → api-gateway → ui → deploy → workspace(docs) |

---

## 2. Глоссарий: текущее состояние (ground-truth) и дельта

| Сущность | id-prefix | Текущее состояние | Дельта под-фазы |
|---|---|---|---|
| `AccessBindingService.ListBySubject` | — | LIVE, public. **strict self-list** (`IsSelf`-guard); сырые `AccessBinding`; direct-only; несуществующий subject → empty-list | **НЕ меняется** (D-1) |
| `AccessBindingService.ListSubjectPrivileges` | — | **НЕ существует** | **НОВЫЙ** sync read-RPC (§A) |
| `AccessBinding` | `acb` | flat: id/subject/role_id/resource_type/resource_id/status/scope/created_at/granted_by_user_id/expires_at (… condition/builtin/revoked) | источник данных; не меняется |
| `Role` | `rol` | flat: id/name/description/permissions/is_system/scope-ids; same-schema FK от `access_bindings.role_id` (`access_bindings_role_fk`) | JOIN-источник `role_name` (D-3); не меняется |
| `User` | `usr` | flat; `account_id` (home account); `UserService.Get` существует | читается для existence (D-6) + authz home-account (D-4) |
| `ServiceAccount` | `sva` | flat; `account_id`; `ServiceAccountService.Get` существует | читается для existence + authz home-account |
| `AccessBinding.Create` | — | LIVE, public, async→Operation, strict-create (дубль активной 5-tuple → ALREADY_EXISTS) | **НЕ меняется**; используется кнопкой «Добавить привилегии» (§D) |
| UI вкладка «Привилегии» (User/SA) | — | **НЕ существует** (только Обзор/Операции/JSON) | **НОВАЯ** через `ext.extraTabs` (§B) |
| UI кнопка «Добавить привилегии» | — | **НЕ существует**; пресет subject не лочится | **НОВАЯ** + subject-lock в `AccessBindingCreatePage` (§C) |

---

## §A — Backend: новый RPC `AccessBindingService.ListSubjectPrivileges`

REST (public, external endpoint): `GET /iam/v1/accessBindings:listSubjectPrivileges?subjectType=<t>&subjectId=<id>&pageSize=&pageToken=`
gRPC: `kacho.cloud.iam.v1.AccessBindingService/ListSubjectPrivileges` (sync read — НЕ возвращает Operation).
JSON-ответ (camelCase): `{ "privileges": [ { "bindingId","roleId","roleName","resourceType","resourceId","scope","status","createdAt","grantedByUserId","expiresAt","derivation" } ], "nextPageToken": "" }`.

### Сценарий 1.3-01: Happy path — User с N привилегиями, имена ролей resolved

**ID:** `1.3-01`

**Given** существует account `acc-A` с owner-User `usr-OWNER`
**And** существует User `usr-MEMBER` с `account_id = acc-A`
**And** owner `usr-OWNER` выдал `usr-MEMBER` две привилегии: binding `acb-1` (role `rol-editor`, name «editor», scope PROJECT, resource `prj-X`) и binding `acb-2` (role `rol-viewer`, name «viewer», scope ACCOUNT, resource `acc-A`), обе ACTIVE
**And** caller — `usr-OWNER` (owner account'а субъекта)

**When** caller вызывает `GET /iam/v1/accessBindings:listSubjectPrivileges?subjectType=user&subjectId=usr-MEMBER`

**Then** sync-ответ `200 OK`, gRPC `OK`
**And** `privileges` содержит ровно 2 элемента, упорядоченных по `(createdAt, id)` ASC
**And** элемент для `acb-1` имеет `roleId="rol-editor"`, **`roleName="editor"`** (resolved сервером), `resourceType="project"`, `resourceId="prj-X"`, `scope="PROJECT"`, `status="ACTIVE"`, `derivation="DIRECT"`, непустой `createdAt`, `grantedByUserId="usr-OWNER"`
**And** элемент для `acb-2` имеет `roleName="viewer"`, `scope="ACCOUNT"`, `resourceId="acc-A"`
**And** `nextPageToken=""`

### Сценарий 1.3-02: Pagination — page_size=1 отдаёт страницу + курсор; вторая страница — остаток

**ID:** `1.3-02`

**Given** `usr-MEMBER` имеет 2 ACTIVE-привилегии (как 1.3-01), caller — `usr-OWNER`

**When** caller вызывает `…:listSubjectPrivileges?subjectType=user&subjectId=usr-MEMBER&pageSize=1`

**Then** `privileges` содержит 1 элемент (первый по `(createdAt,id)` ASC)
**And** `nextPageToken` — непустой opaque base64

**When** caller повторяет запрос с `&pageToken=<nextPageToken>` (тот же `pageSize=1`)

**Then** `privileges` содержит второй (оставшийся) элемент
**And** `nextPageToken=""` (страниц больше нет)

### Сценарий 1.3-03: Self-view — User смотрит СВОИ привилегии (без admin-роли)

**ID:** `1.3-03`

**Given** User `usr-SELF` (не owner, без admin на своём account) имеет 1 ACTIVE-привилегию `acb-s` (role «viewer»)
**And** caller — сам `usr-SELF`

**When** caller вызывает `…:listSubjectPrivileges?subjectType=user&subjectId=usr-SELF`

**Then** `200 OK`, `privileges` содержит `acb-s` с `roleName="viewer"` (self-доступ разрешён, D-4 path (a) `IsSelf`)

### Сценарий 1.3-04: Negative — malformed subject_id → INVALID_ARGUMENT (sync, первым стейтментом)

**ID:** `1.3-04`

**Given** аутентифицированный caller

**When** caller вызывает `…:listSubjectPrivileges?subjectType=user&subjectId=not-a-valid-id`

**Then** gRPC `INVALID_ARGUMENT`, REST `400`, message `"invalid user id 'not-a-valid-id'"`
**And** ответ синхронный, до любого обращения к репозиторию (D-7)

**When** caller вызывает `…:listSubjectPrivileges?subjectType=user&subjectId=sva-XXXXXXXXXXXXXXXXX` (валидный SA-id, но `subject_type=user`)

**Then** gRPC `INVALID_ARGUMENT`, message `"invalid user id 'sva-…'"` (prefix↔type mismatch, D-7)

### Сценарий 1.3-05: Negative — unknown subject_type → INVALID_ARGUMENT

**ID:** `1.3-05`

**Given** аутентифицированный caller

**When** caller вызывает `…:listSubjectPrivileges?subjectType=group&subjectId=grp-XXXXXXXXXXXXXXXXX`

**Then** gRPC `INVALID_ARGUMENT`, message `"Illegal argument subject_type (allowed: user|service_account)"` (v1 — group вне scope, D-5/D-7)

### Сценарий 1.3-06: Negative — well-formed-но-несуществующий subject → NOT_FOUND

**ID:** `1.3-06`

**Given** account-admin caller `usr-OWNER`
**And** не существует User с id `usr-GHOSTAAAAAAAAAAAA` (well-formed prefix `usr`, но нет в БД)

**When** caller вызывает `…:listSubjectPrivileges?subjectType=user&subjectId=usr-GHOSTAAAAAAAAAAAA`

**Then** gRPC `NOT_FOUND`, REST `404`, message `"User usr-GHOSTAAAAAAAAAAAA not found"` (D-6 — existence-резолв обязателен для authz)
**And** аналогично для `subjectType=service_account` с несуществующим `sva-…` → `"ServiceAccount sva-… not found"`

### Сценарий 1.3-07: AuthZ — account-admin (не owner, FGA `admin` на account) видит привилегии члена

**ID:** `1.3-07`

**Given** account `acc-A` (owner `usr-OWNER`), член `usr-MEMBER` (`account_id=acc-A`) с 1 привилегией
**And** caller — `usr-ADMIN`, который **не** owner `acc-A`, но имеет FGA `admin` relation на `account:acc-A`

**When** caller вызывает `…:listSubjectPrivileges?subjectType=user&subjectId=usr-MEMBER`

**Then** `200 OK`, `privileges` содержит привилегию `usr-MEMBER` (D-4 path (b) — delegated admin на home-account субъекта)

### Сценарий 1.3-07a: AuthZ — ServiceAccount-субъект, admin его home-account

**ID:** `1.3-07a`

**Given** ServiceAccount `sva-BOT` (`account_id=acc-A`) с привилегией `acb-bot` (role «editor»)
**And** caller — owner/admin `acc-A`

**When** caller вызывает `…:listSubjectPrivileges?subjectType=service_account&subjectId=sva-BOT`

**Then** `200 OK`, `privileges` содержит `acb-bot` с `roleName="editor"` (D-4 для SA-субъекта — home-account `sva-BOT.account_id`)

### Сценарий 1.3-08: Negative — кросс-account чтение запрещено (PERMISSION_DENIED)

**ID:** `1.3-08`

**Given** account `acc-A` (член `usr-MEMBER`) и **другой** account `acc-B` (owner `usr-B`)
**And** caller — `usr-B` (owner `acc-B`, без admin/owner на `acc-A`)

**When** caller вызывает `…:listSubjectPrivileges?subjectType=user&subjectId=usr-MEMBER` (член чужого account'а)

**Then** gRPC `PERMISSION_DENIED`, REST `403` (D-4 — ни self, ни admin на home-account субъекта)
**And** в ответе **нет** утечки данных о привилегиях `usr-MEMBER` (D-10 — кросс-account изоляция)

### Сценарий 1.3-09: Edge — subject существует, 0 привилегий → пустой список (не ошибка)

**ID:** `1.3-09`

**Given** User `usr-EMPTY` (`account_id=acc-A`) без единого AccessBinding
**And** caller — owner `acc-A`

**When** caller вызывает `…:listSubjectPrivileges?subjectType=user&subjectId=usr-EMPTY`

**Then** `200 OK`, `privileges=[]` (пустой массив), `nextPageToken=""` (D-6 — существующий subject с 0 binding ≠ NotFound)

### Сценарий 1.3-10: Negative — анонимный caller → fail-closed

**ID:** `1.3-10`

**Given** запрос без валидного principal (анонимный)

**When** вызывается `…:listSubjectPrivileges?subjectType=user&subjectId=usr-MEMBER`

**Then** запрос отклоняется fail-closed (gRPC `UNAUTHENTICATED`/`PERMISSION_DENIED`; REST `401`/`403` — паритет с anti-anonymous guard `RequireAuthenticated`), **до** возврата каких-либо данных

### Сценарий 1.3-11: Conformance — `SubjectPrivilege` несёт только публично-безопасные поля

**ID:** `1.3-11`

**Given** привилегия `acb-1` (как 1.3-01)

**When** caller (owner) читает её через `…:listSubjectPrivileges`

**Then** элемент содержит **только**: `bindingId`, `roleId`, `roleName`, `resourceType`, `resourceId`, `scope`, `status`, `createdAt`, `grantedByUserId`, `expiresAt`, `derivation`
**And** ответ **не** содержит инфра-чувствительных полей (placement/underlay/numeric-infra-id) и **не** включает `conditionId`/`builtinCondition`-internals (вне scope v1, `security.md`)

### Сценарий 1.3-12: Conformance — role_name резолвится сервером (не клиентом)

**ID:** `1.3-12`

**Given** `usr-MEMBER` с привилегией на role `rol-editor` (name «editor»)
**And** caller — owner

**When** caller вызывает `…:listSubjectPrivileges`

**Then** элемент **сразу** несёт `roleName="editor"` в одном ответе (без отдельного `GET /iam/v1/roles/{id}` — серверный JOIN, D-3)
**And** integration-тест подтверждает: один SQL-запрос/транзакция (`access_bindings ⋈ roles`), не N+1

### Сценарий 1.3-13: Edge — REVOKED-binding / dangling role gracefully (не падает)

**ID:** `1.3-13`

**Given** `usr-MEMBER` имеет binding `acb-r` в статусе REVOKED, чья role была удалена после revoke (роль `rol-gone` отсутствует в `roles`)
**And** caller — owner

**When** caller вызывает `…:listSubjectPrivileges?subjectType=user&subjectId=usr-MEMBER` (если контракт включает REVOKED — см. примечание)

**Then** RPC **не** падает (no panic, no INTERNAL leak); элемент `acb-r` (если попадает в выборку) несёт `roleName=""` (graceful fallback), `status="REVOKED"`
**And** _Примечание для ревьюера:_ открытый вопрос Q#2 (§5) — включать ли REVOKED в дефолтный вывод; рекомендация — **только ACTIVE/PENDING** по умолчанию (как `ListByAccount.include_revoked=false`), REVOKED — out-of-scope v1 (тогда `acb-r` в выборку не попадает, сценарий проверяет лишь no-panic при dangling role у ACTIVE-binding с теоретически удалённой ролью). Решение фиксируется ревьюером.

---

## §B — UI: вкладка «Привилегии» на User и ServiceAccount

### Сценарий 1.3-14: User detail — вкладка «Привилегии» показывает подключённые роли

**ID:** `1.3-14`

**Given** оператор-owner `acc-A` залогинен в UI
**And** открыта страница деталей `usr-MEMBER` (`/iam/users/usr-MEMBER`), у которого 2 ACTIVE-привилегии

**When** оператор кликает вкладку «Привилегии»

**Then** URL переходит на `/iam/users/usr-MEMBER/privileges`
**And** вкладка отображает таблицу из 2 строк: колонки «Роль» (resolved name, напр. «editor»/«viewer»), «Scope» (PROJECT/ACCOUNT), «Статус» (ACTIVE), «Создано» (createdAt)
**And** бейдж-`count` на вкладке = «2»
**And** данные получены ОДНИМ вызовом `…:listSubjectPrivileges` (без per-row `GET /roles/{id}`)

### Сценарий 1.3-15: ServiceAccount detail — та же вкладка «Привилегии»

**ID:** `1.3-15`

**Given** оператор-admin `acc-A`, открыта страница деталей `sva-BOT` (`/iam/service-accounts/sva-BOT`) с 1 привилегией

**When** оператор кликает вкладку «Привилегии»

**Then** URL → `/iam/service-accounts/sva-BOT/privileges`
**And** таблица показывает привилегию `sva-BOT` с resolved role name (паритет с User-вкладкой)

### Сценарий 1.3-16: Edge — subject без привилегий → empty-state

**ID:** `1.3-16`

**Given** открыта страница деталей `usr-EMPTY` (0 привилегий)

**When** оператор открывает вкладку «Привилегии»

**Then** вкладка показывает empty-state «Привилегий нет» (не ошибка, не спиннер навсегда)
**And** бейдж-`count` = «0» (или отсутствует)

### Сценарий 1.3-17: Edge — кросс-account оператор не видит привилегий (403 → понятное сообщение)

**ID:** `1.3-17`

**Given** оператор `usr-B` (owner `acc-B`) каким-то образом открыл детали `usr-MEMBER` (член `acc-A`)

**When** оператор открывает вкладку «Привилегии»

**Then** backend отдаёт `403`; вкладка показывает сообщение «Недостаточно прав для просмотра привилегий» (не сырой stack/JSON), приложение не падает (D-4/D-10)

---

## §C / §D — UI: кнопка «Добавить привилегии» + grant-flow с залоченным subject

### Сценарий 1.3-18: Кнопка «Добавить привилегии» вверху вкладки → форма с залоченным subject

**ID:** `1.3-18`

**Given** оператор-owner `acc-A` на вкладке «Привилегии» страницы `usr-MEMBER`

**When** оператор кликает кнопку «Добавить привилегии» (вверху вкладки)

**Then** происходит переход на `/iam/access-bindings/create?subject_type=user&subject_id=usr-MEMBER&lock_subject=1`
**And** форма создания AccessBinding пре-заполнена subject'ом (`subject_type=user`, `subject_id=usr-MEMBER`)
**And** поля subject **заблокированы** (disabled/read-only) — оператор не может изменить subject (D-9; новое поведение `lock_subject`)
**And** поля Role / Resource — редактируемые (оператор выбирает роль и scope)

### Сценарий 1.3-19: Happy path grant — Create binding → Operation done → привилегия появляется во вкладке

**ID:** `1.3-19`

**Given** оператор на форме `…/access-bindings/create?subject_type=user&subject_id=usr-MEMBER&lock_subject=1`
**And** выбрал role `rol-editor` и scope `project:prj-X`

**When** оператор сабмитит форму (`POST /iam/v1/accessBindings` body `{subjectType:"user", subjectId:"usr-MEMBER", roleId:"rol-editor", resourceType:"project", resourceId:"prj-X"}`)

**Then** возвращается `Operation` (async-контракт `AccessBinding.Create`, не меняется под-фазой)
**And** UI поллит `OperationService.Get(id)` до `done=true && !error`
**And** при успехе UI возвращает оператора на вкладку «Привилегии» `usr-MEMBER` и рефетчит список
**And** новая привилегия (role «editor», scope PROJECT) видна в таблице (трассируется к `…:listSubjectPrivileges`, паритет с 1.3-01)

### Сценарий 1.3-20: Negative grant — дубль активной привилегии → ALREADY_EXISTS (понятное сообщение)

**ID:** `1.3-20`

**Given** у `usr-MEMBER` уже есть ACTIVE-binding (role `rol-editor` на `project:prj-X`)
**And** оператор сабмитит идентичный grant через ту же форму

**When** `POST /iam/v1/accessBindings` с той же 5-tuple

**Then** backend → gRPC `ALREADY_EXISTS`, REST `409` (strict-create, дубль активной 5-tuple — `kacho-iam` §4.5, **существующее** поведение)
**And** UI показывает inline-предупреждение «Такая привилегия уже выдана» (не crash; паритет с текущим 409-handling `AccessBindingCreatePage`)

### Сценарий 1.3-21: Negative grant — оператор без grant-authority → кнопка скрыта / backend 403

**ID:** `1.3-21`

**Given** оператор `usr-B` (без admin/owner на home-account субъекта) смотрит детали `usr-MEMBER`

**When** оператор открывает вкладку «Привилегии»

**Then** кнопка «Добавить привилегии» **скрыта** (UI-гейт по grant-authority, D-9)
**And** даже при прямом переходе на `…/access-bindings/create?subject_type=user&subject_id=usr-MEMBER&lock_subject=1` сабмит отклоняется backend'ом `403` (`AccessBinding.Create` → `requireGrantAuthority`, **существующая** защита) — UI показывает «Недостаточно прав»

---

## §J — Smoke / e2e (заказчик: финальная верификация, шаг 7)

### Сценарий 1.3-22: e2e — grant → list shows it → REST/gRPC parity

**ID:** `1.3-22`

**Given** развёрнутый стенд (`make dev-up`), bootstrap account `acc-A` + owner
**When** owner создаёт binding для `usr-MEMBER` (`grpcurl`/REST `POST /iam/v1/accessBindings`), дожидается Operation done
**And** owner вызывает `GET /iam/v1/accessBindings:listSubjectPrivileges?subjectType=user&subjectId=usr-MEMBER`
**Then** ответ содержит созданную привилегию с resolved `roleName`
**And** gRPC `grpcurl … AccessBindingService/ListSubjectPrivileges` даёт эквивалентный набор (REST/gRPC parity)
**And** UI: на `/iam/users/usr-MEMBER/privileges` привилегия видна; кнопка «Добавить привилегии» работает end-to-end

---

## 5. Открытые вопросы (ЗАКРЫТЫ ревьюером на APPROVED — НЕ переоткрывать)

| # | Вопрос | Решение (ревизия 1, зафиксировано `acceptance-reviewer`) |
|---|---|---|
| **Q#1** | Новый RPC `ListSubjectPrivileges` (D-1) vs. расширение `ListBySubject`? | **ПРИНЯТО: новый RPC.** `ListBySubject` задеплоен с намеренным self-list-инвариантом; broadening его authz = silent semantic break. Additive RPC, `buf breaking` зелёный. |
| **Q#2** | Включать ли REVOKED-binding'и в дефолтный вывод? `include_revoked`-флаг? | **ЗАКРЫТО: только ACTIVE/PENDING по умолчанию** (паритет `ListByAccount.include_revoked=false`); `include_revoked`-флаг — out-of-scope v1 (additive позже). 1.3-13 → проверяет лишь no-panic при dangling role у ACTIVE-binding (REVOKED в дефолтный вывод НЕ входит). |
| **Q#3** | DIRECT-only (D-5) vs. include group-derived (effective) сейчас? | **ПРИНЯТО: DIRECT-only v1** + `derivation`-enum зарезервирован; effective — под-фаза 1.3b (single in-DB JOIN, additive-расширение без breaking). |
| **Q#4** | FGA object_type для permission-catalog `scope_extractor`? | **ПРИНЯТО: cluster-floor + handler-авторитетная политика** (паритет `ListBySubject`/`Create`): catalog даёт anti-anon + ACR floor, точную «self/account-admin» авторизацию делает handler (D-4). FGA object_type сверяется с моделью при impl. |
| **Q#5** | `subject_type` строго `{user,service_account}` для v1 (group исключён)? | **ПРИНЯТО: да** (заказчик: «пользователь или сервис аккаунт»). Group-subject привилегии — за `ListBySubject` / follow-up. |
| **Q#6** | UI: вкладка через `extraTabs` (отдельная) vs `overviewBelow` (секция)? | **ПРИНЯТО: `extraTabs`** (отдельная вкладка) — заказчик просит «отдельным табом… в табе привилегии вверху кнопку». Precedent — SecurityGroup «Правила». |

---

## 8. Non-blocking-замечания ревьюера (учесть в плане / impl; ре-ревью НЕ требуется)

1. **[ground-truth precision — D-7]** `corevalidate.ResourceID` (`kacho-corelib/validate/validate.go:377-388`) **family-agnostic** — проверяет лишь что 3-char prefix в known-set, НЕ соответствие prefix↔`subject_type`. Контракт 1.3-04 («`sva-…` под `subject_type=user` → INVALID_ARGUMENT») корректен как требование, но это **новая** валидация (prefix-of-id == prefix-for-subject_type), а не вызов готового хелпера. `rpc-implementer` не должен предполагать, что `corevalidate.ResourceID` это уже делает. Ожидаемый текст (`"invalid user id '<X>'"`) — корректен.
2. **[traceability]** В плане желательно зафиксировать имя теста (`Test…_1.3-NN_…`) на каждый ID (DoD S2 сейчас агрегирует «1.3-01..13»); `integration-tester` восстановит 1-to-1.
3. **[format — 1.3-13]** Убрать условность «(если контракт включает REVOKED…)» из Given/When при переносе в план — Q#2 закрыт (REVOKED out-of-scope v1); сценарий = чистый no-panic при dangling role у ACTIVE-binding.
4. **[scope]** D-4 `Users().Get`/`ServiceAccounts().Get` перед authz — within-`kacho_iam`, same-schema read, **НЕ** новый cross-domain edge (`polyrepo.md` не меняется). Подтверждено.
5. **[negative — для протокола]** Concurrent-сценарий отсутствует корректно: RPC read-only (без CAS/UNIQUE/OCC-мутации); grant — существующий `AccessBinding.Create` (strict-create покрыт в своей под-фазе). Не дефект.
6. **[UI — 1.3-21]** whoami-snapshot не содержит готового предиката «grant-authority на home-account *субъекта*» (UI знает роли caller'а в account'ах; subject.account_id виден на detail). Скрытие кнопки — best-effort маппинг; backend-403 авторитетен и покрывает корректность. Уточнить в UI-плане.

---

## 6. Definition of Done (на каждую стадию)

Кросс-репо порядок (`polyrepo.md`): **proto → iam → api-gateway → ui → deploy → workspace(docs)**. Стадии — самостоятельные deliverable'ы; CI нижестоящего пиннит sibling к feature-ветке до merge вышестоящего.

**S1 — proto (`kacho-proto`):**
- [ ] `ListSubjectPrivileges` RPC + `ListSubjectPrivilegesRequest`/`Response` + `SubjectPrivilege` message + `Derivation`-enum в `access_binding_service.proto`/`access_binding.proto` (форма D-2/D-3).
- [ ] gRPC sync-read (НЕ Operation); REST `GET …:listSubjectPrivileges`; permission/required_relation/scope_extractor/required_acr_min аннотации (D-4/Q#4).
- [ ] `buf lint` / `buf breaking` зелёные; `gen/go/...` регенерирован и закоммичен. Ревью — `proto-api-reviewer`.

**S2 — iam (`kacho-iam`):**
- [ ] RED integration-тесты (testcontainers) по сценариям 1.3-01..13 первыми → подтверждён красный → GREEN.
- [ ] Use-case `ListSubjectPrivileges`: subject prefix↔type validate (D-7) → existence-резолв (D-6, NotFound) → authz self|account-admin (D-4, mirror `requireGrantAuthority` на home-account субъекта) → repo JOIN `access_bindings ⋈ roles` (D-3, resolved role_name, keyset `(created_at,id)` ASC, direct-only).
- [ ] Error-mapping (`INVALID_ARGUMENT`/`NOT_FOUND`/`PERMISSION_DENIED`/`UNAUTHENTICATED`), без leak pgx.
- [ ] `ListBySubject` **не изменён** (регресс-тест подтверждает self-list-контракт). by-design D-10 — запись в `docs/architecture/`.
- [ ] Ревью — `db-architect-reviewer` (JOIN/индексы), `go-style-reviewer`, `system-design-reviewer` (read-only, без новых cross-domain edge — все читаемые ресурсы within `kacho_iam`).

**S3 — api-gateway (`kacho-api-gateway`):**
- [ ] Регистрация **public** `ListSubjectPrivileges` (allowlist + gRPC-director + REST mux на external) — НЕ Internal. Ревью / исполнение — `api-gateway-registrar`.
- [ ] permission-catalog entry (Q#4) embedded; authz-middleware делает реальный Check (anti-anon + ACR floor).
- [ ] newman happy (1.3-01) + negative (1.3-04, 1.3-06, 1.3-08, 1.3-10) через api-gateway, RED-first.

**S4 — ui (`kacho-ui`):**
- [ ] `iamApi.listSubjectPrivileges(subjectType, subjectId, q?)`-хелпер (`src/api/iam.ts`).
- [ ] `ext.extraTabs` «Привилегии» для специй `users` и `service-accounts` (`resource-detail-extensions.tsx`) — таблица + empty-state + count (D-8); сценарии 1.3-14..17.
- [ ] Кнопка «Добавить привилегии» вверху вкладки → deep-link с `lock_subject=1`; `AccessBindingCreatePage` лочит subject-поля при `lock_subject=1` (D-9); post-create возврат+рефетч; сценарии 1.3-18..21.
- [ ] UI-тесты по сценариям; кнопка-видимость гейтится grant-authority.

**S5 — deploy (`kacho-deploy`):** helm/compose без изменений (новый public RPC проходит существующим external endpoint); e2e-build-матрицы newman зелёные.

**S6 — workspace (docs/vault):** обновить vault `rpc/kacho-iam-access_binding_service.md` (новый RPC), `resources/kacho-iam-access_binding.md` (subject-privileges проекция), KAC-trail; этот acceptance-док → статус APPROVED.

**Финальная верификация (перед merge каждой Go-стадии):** `go test ./... -race` + `golangci-lint run` + `govulncheck` + `make audit-list-filter` (новый list-RPC должен фильтровать по scope) + newman зелёные.

---

## 7. Выход / запреты

- Единственный артефакт этого шага — настоящий markdown. **Никакого кода** (ни `.go`, ни `.sql`, ни `.proto`).
- Описано только наблюдаемое поведение API/UI; DB-инварианты (JOIN/индексы) — забота `db-architect-reviewer`/`rpc-implementer`.
- `ListBySubject` НЕ модифицируется (D-1); grant — существующий `AccessBinding.Create` (НЕ меняется).
- Без сравнений с чужими облаками — конвенции Kachō нормативны (`api-conventions.md`).
- Координация после APPROVED: `superpowers:writing-plans` → `integration-tester` (RED по 1.3-NN) → `rpc-implementer` → `proto-api-reviewer` (proto) / `db-architect-reviewer` (если индекс) / `api-gateway-registrar` (public RPC) → заказчик: финальный smoke (§J 1.3-22).
