# Sub-phase 2.0 (Kachō IAM — Account/Project + Zitadel + OpenFGA) — Overview Acceptance

**Документ:** acceptance / sub-phase 2.0 — epic-level overview
**YouTrack:** [KAC-104](https://prorobotech.youtrack.cloud/issue/KAC-104) (epic) + subtasks KAC-105 … KAC-110 (E0 … E5)
**Дата:** 2026-05-17
**Версия:** DRAFT v2 (was DRAFT v1 — review feedback от `acceptance-reviewer` 2026-05-17 применён, см. §Changelog)
**Статус:** Draft — ждёт повторного review `acceptance-reviewer`
**Автор-агент:** `acceptance-author`
**Источник требований:**
- DoD от заказчика (тело KAC-104).
- workspace `CLAUDE.md` запреты #1, #4, #6, #8, #10, #11; §«Кросс-доменные ссылки на ресурсы»; §«Внутри-сервисные refs — DB-уровень обязателен»; §«API contract — flat resources + Operations»; §«Инфра-чувствительные данные».
- `.claude/skills/evgeniy/SKILL.md` (новый сервис `kacho-iam` пишется по этому регламенту).
- `docs/specs/04-roadmap-and-phasing.md` §«Фаза 1 — AAA» (тут она конкретизируется в фазу 2.0).
- Текущий `kacho-resource-manager` (`internal/domain/{organization,cloud,folder}.go` + `internal/service/`) — deprecated в E5.
- Существующий proto `kacho-proto/proto/kacho/cloud/access/access.proto` — **messages-only** (без `service`-деклараций; содержит `Subject`, `AccessBinding`, `AccessPolicy`, `AccessPolicyBinding`, `BindAccessPolicy{Request,Metadata,Response}`, `UnbindAccessPolicy{Request,Metadata,Response}`, `UpdateAccessPolicyBindingParameters{Request,Metadata,Response}`, `SetAccessBindings{Request,Metadata}`, `UpdateAccessBindings{Request,Metadata}`, `AccessBindingDelta`, `AccessBindingsOperationResult`, `List{AccessBindings,AccessPolicyBindings}{Request,Response}`). Никем не используется как сервис на сегодня (нет `service { rpc ... }` блока). В E0 эти messages **мигрируют** в новый `kacho.cloud.iam.v1.access_binding.proto` (с эквивалентными или переименованными в kacho-стиле полями: `kacho.cloud.iam.v1.Subject`, `kacho.cloud.iam.v1.AccessBinding`, `kacho.cloud.iam.v1.AccessBindingDelta`); legacy `kacho.cloud.access.*` помечается `option deprecated = true;` на каждом message в E0 и **удаляется** в E5 (после миграции данных через `0001_seed_default_account.sql`/E5-миграцию). Никаких runtime-зависимостей от `kacho.cloud.access.*` в kacho-vpc/compute/loadbalancer/resource-manager на сегодня не зафиксировано (proto только в `kacho-proto`, не импортируется handlers'ами).
- Текущий `kacho-corelib/operations` (Operation row + Worker) — расширяется полем `Principal` в E4 (corelib-таск).

**Утверждение:** approve выставляет агент `acceptance-reviewer`. Каждый из E0…E5 имеет **собственный** `sub-phase-2.0-iam-E<n>-*-acceptance.md` с подробными GWT-сценариями; этот документ — overview-контракт, фиксирующий цели эпика, target-архитектуру, REBAC-модель, кросс-репо порядок и DoD. Без APPROVED-overview не стартуют per-эпиковые acceptance-документы (gating одного уровня, чтобы декомпозиция не разъехалась). Заказчик подключается только к финальному smoke на шаге 7 каждого sub-эпика (`04-roadmap-and-phasing.md` §2).

---

## 0. Цель эпика (1 абзац)

Сейчас платформа Kachō работает без auth/authz: api-gateway пускает любого, `Operation.created_by` = stub (фиксированный `"system"`), нет понятия «пользователь / сервис-аккаунт / роль / binding», иерархия — Organization → Cloud → Folder (kacho-resource-manager), которая по сути дублирует «account/project» из современных IaaS и не несёт собственной семантики кроме скоупа. Эпик **KAC-104** вводит полноценный AAA-слой: новый сервис `kacho-iam` (REBAC-control-plane: Account / Project / User / ServiceAccount / Group / Role / AccessBinding), внешний OIDC-provider **Zitadel** (источник identity, signup-flow, JWT-tokens, JWKS), внешний REBAC-engine **OpenFGA** (Zanzibar-модель, tuple-store, `Check`-API), и две interceptor-цепочки в `kacho-api-gateway` (auth → authz) перед маршрутизацией к backend-сервисам. После завершения эпика любой PUBLIC RPC сначала валидирует Bearer JWT через Zitadel JWKS, резолвит `Principal{Type, ID, DisplayName}` через `kacho-iam.SubjectService.Lookup`, проверяет право через `openfga.Check(subject, relation, object)` — и только потом проксирует к backend; полученный `Principal` пробрасывается в backend через gRPC-metadata, сохраняется в `operations.principal_*` (DoD #4), и иерархия меняется: место `Folder` занимает `Project`, место `Cloud` — `Account` (одно-к-одному переименование на проекте, под капотом — иной owner). UI получает блок «Identity and Access Management» (DoD #2,3): Service Accounts, Users, Groups, Roles (default `admin`/`viewer`/`editor` per-module + per-resource-type + custom), AccessBindings — наравне с VPC/Compute. `kacho-resource-manager` (E5) выключается полностью.

**Что НЕ входит в фазу 2.0 (явно отложено, см. §9):** MFA / WebAuthn (Zitadel-feature, не enforce'им), external identity federation (SAML / Google / GitHub — есть как Zitadel feature, не покрывается сценариями), cross-account ресурсный sharing (один Account = один tenant), audit storage (отдельный сервис `kacho-audit`, фаза 1 roadmap — здесь только principal в Operation), quota / billing, attribute-based access control (ABAC — поверх REBAC отдельной фазой если потребуется).

**Зафиксированные верхнеуровневые соглашения (resolved до review этого overview):**
- **Account** заменяет `Organization` + `Cloud` (двухуровневая иерархия Org→Cloud была лишней). На фазу 2.0 один Account = один tenant; cross-account binding'и отложены.
- **Project** заменяет `Folder`. Семантика идентична (скоуп ресурсов), переименование сквозное: `folder_id` → `project_id` в spec/handler/migration всех сервисов (E1).
- **Default Account / Default Project** создаётся при первом старте `kacho-iam` (по аналогии с текущим default-folder в resource-manager).
- **kacho-iam ID-префиксы** (crockford-base32, 3 chars, как в kacho-vpc — для api-gateway prefix-routing): `acc` (Account), `prj` (Project), `usr` (User), `sva` (ServiceAccount), `grp` (Group), `rol` (Role), `bnd` (AccessBinding). Префиксы регистрируются в `kacho-api-gateway/internal/restmux/prefix_routing.go`.
- **OIDC-issuer** — единый Zitadel-instance на dev-стенде (отдельная Postgres БД `zitadel`, не `kacho_iam`). На prod — managed Zitadel.
- **OpenFGA store** — единый `kacho-store` (отдельная Postgres БД `openfga`, не `kacho_iam`). Authorization-model — DSL-файл, version-managed (id записывается в `kacho_iam.fga_model_version`).
- **Зависимости БД (запрет #8):** четыре независимые БД — `kacho_iam` (наша), `zitadel` (Zitadel), `openfga` (OpenFGA), плюс per-service БД остальных сервисов. Никаких cross-DB FK.
- **`kacho-resource-manager` deprecation strategy** — не выключение «по флагу», а замена сервиса: api-gateway маршрутизирует `kacho.cloud.iam.v1.AccountService` / `ProjectService` на `kacho-iam`, старые REST-paths `/resource-manager/v1/{organizations,clouds,folders}` отдают `Gone 410` после E5. Данные мигрируются: `organizations` + `clouds` → `accounts`, `folders` → `projects` (single-shot SQL-миграция в E5).
- **principal на Operations (DoD #4) — корrelib-изменение, не per-service.** Добавляется в `kacho-corelib/operations/migrations/00X_add_principal.sql` (новая колонка `principal_type TEXT NOT NULL DEFAULT 'system'`, `principal_id TEXT NOT NULL DEFAULT ''`, `principal_display_name TEXT NOT NULL DEFAULT ''`) + расширение `operations.Repo.Create(...)` сигнатуры. Каждый сервис подтягивает обновлённый corelib и пробрасывает `Principal` из `ctx`-metadata в `operations.Create`.
- **Реактивность (DoD #5)** — без TTL-кэша и без перезапуска. OpenFGA tuple-writes (через `kacho-iam` в момент `Upsert AccessBinding`) видны в `Check` сразу же (consistency-mode `MINIMIZE_LATENCY`, не `HIGHER_CONSISTENCY` — для нашего sub-100ms-SLA достаточно). Subject-lookup-кеш в api-gateway имеет TTL 30s **и** invalidate-канал через `kacho-iam Internal.SubjectChangeNotificationService` (LISTEN/NOTIFY-pattern из corelib `outbox`, payload — subject_id). Acceptable end-to-end latency revoke → enforced DENY: ≤10s в worst-case (TTL), типично ≤1s (NOTIFY).

---

## 1. Definition of Done (нормативно)

Шесть DoD-пунктов от заказчика. Каждый покрывается GWT-сценариями в §7 (по 2 на пункт). Эпик не закрывается, пока все шесть не зелёные.

| # | DoD | Покрывается сценариями |
|---|-----|------------------------|
| 1 | UI: рабочая регистрация пользователя (signup-flow через Zitadel) | E4.GWT-01, E4.GWT-02 |
| 2 | UI: блок Identity and Access Management (по аналогии с VPC, Compute) | E4.GWT-03, E4.GWT-04 |
| 3 | UI-блоки: Service Accounts, Users, Groups, Roles (default `admin`/`viewer`/`editor` per-module + per-resource type + custom), AccessBinding'и | E4.GWT-05, E4.GWT-06 |
| 4 | Operation.principal отражает реального User/ServiceAccount, а не stub | E4.GWT-07, E4.GWT-08 |
| 5 | Изменение прав применяется реактивно (≤10s, без перезапуска, без многоминутного TTL) | E3.GWT-01 (revoke ≤10s), E3.GWT-02 (grant ≤1s), E3.GWT-03 (restart-resistance — новый pod не имеет stale-cache) |
| 6 | Репо `kacho-iam` (`project/kacho-iam`) live в kacho-deploy, schema `kacho_iam` создаётся мигратором | E0.GWT-01, E0.GWT-02 |

DoD-чек-лист до закрытия KAC-104 — §12.

---

## 2. Target architecture

### 2.1 Граф сервисов и edges (runtime, не build)

```
                              ┌────────────────────────┐
                              │      kacho-ui (SPA)    │
                              │  signup-flow ┐         │
                              │  IAM admin block       │
                              └──────────┬─────────────┘
                                         │ HTTPS (api-gateway public)
                                         │ + OIDC redirect to Zitadel for signup/login
                                         ▼
              ┌───────────────────────────────────────────────────┐
              │              kacho-api-gateway                    │
              │  ┌─────────────────────────────────────────────┐  │
              │  │ Interceptor 1: AUTH                         │  │
              │  │   - parse Bearer JWT                         │  │
              │  │   - validate via Zitadel JWKS (cached 1h)    │  │
              │  │   - resolve Subject via                      │  │
              │  │     kacho-iam.InternalSubjectService.Lookup  │  │
              │  │     via DIRECT gRPC к kacho-iam:9091         │  │
              │  │     (НЕ через свой REST mux — loop запрет;   │  │
              │  │      grpcclient в internal/clients/iam)      │  │
              │  │     (cached 30s + NOTIFY-invalidate)         │  │
              │  │   - inject Principal into gRPC ctx-metadata  │  │
              │  └─────────────────────────────────────────────┘  │
              │  ┌─────────────────────────────────────────────┐  │
              │  │ Interceptor 2: AUTHZ                        │  │
              │  │   - extract (subject, action, resource_id)  │  │
              │  │   - OpenFGA Check(subject, relation, object)│  │
              │  │   - on DENY → PermissionDenied              │  │
              │  └─────────────────────────────────────────────┘  │
              │           │                                       │
              │           ▼                                       │
              │   route to backend by ID-prefix                   │
              └────────┬────────┬────────┬────────┬───────────────┘
                       │        │        │        │
            ┌──────────┘        │        │        └────────────┐
            ▼                   ▼        ▼                     ▼
    ┌───────────────┐   ┌───────────┐  ┌───────────┐   ┌───────────────┐
    │   kacho-iam   │   │ kacho-vpc │  │kacho-compute│  │kacho-loadbal. │
    │ (NEW SERVICE) │   │           │  │           │   │               │
    │ Account/Proj  │   │ Network/  │  │ Instance/ │   │ NLB/TG        │
    │ User/SA/Group │   │ Subnet/…  │  │ Disk/…    │   │               │
    │ Role/Binding  │   └────┬──────┘  └────┬──────┘   └──────┬────────┘
    │ SubjectLookup │        │              │                 │
    └───┬───────────┘        │              │                 │
        │ FGA-write (tuples) │ project_id   │ project_id      │ project_id
        │ SubjectChangeNotify│ validation   │ validation      │ validation
        │ on AccessBinding   │ (via iam.    │ (via iam.       │ (via iam.
        │ Upsert/Delete      │ ProjectSvc)  │ ProjectSvc)     │ ProjectSvc)
        ▼                    ▼              ▼                 ▼
    ┌──────────────┐    (все consumer-сервисы зовут iam.ProjectService.Get
    │   OpenFGA    │     для валидации project_id на request-path —
    │ (Zanzibar)   │     §«Кросс-доменные ссылки на ресурсы»)
    │   store      │
    └──────────────┘
        ▲
        │ OIDC tokens issuance / JWKS
        │
    ┌──────────────┐
    │   Zitadel    │ ← signup / login UI, OAuth2/OIDC server
    │ (self-host)  │   JWKS endpoint, /.well-known/openid-configuration
    └──────────────┘
        │
        ▼
    ┌──────────────┐
    │  postgres    │ ← Zitadel БД (отдельный экземпляр, НЕ kacho_iam)
    └──────────────┘
```

Дополнительные БД:
- `kacho_iam` (Postgres, schema `kacho_iam`) — accounts, projects, users (mirror), service_accounts, groups, group_members, roles, access_bindings, fga_model_version, operations (per-service), subject_change_outbox.
- `zitadel` (Postgres, отдельный экземпляр) — Zitadel-internal state, не наш.
- `openfga` (Postgres, отдельный экземпляр) — OpenFGA tuple-store, не наш.

### 2.2 Внутри `kacho-iam` (evgeniy-style structure)

Из `evgeniy SKILL.md` §1 + §6:

```
project/kacho-iam/
├── cmd/
│   ├── kacho-iam/main.go            # API-server (public + internal gRPC)
│   └── migrator/main.go             # отдельный binary (cobra), apply migrations
├── internal/
│   ├── domain/                       # newtypes + Validate (D.2-D.6)
│   │   ├── account.go
│   │   ├── project.go
│   │   ├── user.go                   # mirror of Zitadel-user (external_id, email, display_name)
│   │   ├── service_account.go
│   │   ├── group.go
│   │   ├── role.go                   # default + custom; permissions []Permission
│   │   ├── access_binding.go
│   │   ├── subject.go                # Subject{Type, ID} envelope (user/sa/group)
│   │   └── types.go                  # newtypes (LabelKey, LabelVal, RoleID, …)
│   ├── apps/kacho/api/
│   │   ├── account/{handler,create,update,delete,list}.go
│   │   ├── project/{handler,…}.go
│   │   ├── user/{handler,sync_from_zitadel,…}.go
│   │   ├── service_account/{handler,create,…}.go     # create-flow + sa-credential issuance via Zitadel
│   │   ├── group/{handler,create,add_member,…}.go
│   │   ├── role/{handler,…}.go
│   │   ├── access_binding/{handler,upsert,delete,…}.go  # каждый upsert → FGA-write
│   │   └── subject_lookup/{handler,lookup,…}.go        # InternalSubjectService для api-gateway
│   ├── repo/kacho/pg/                # CQRS Reader/Writer (G.2-G.5)
│   ├── clients/
│   │   ├── zitadel_client.go         # OIDC discovery, JWKS, management-API for SA creation
│   │   └── openfga_client.go         # Write/Check tuples
│   ├── jobs/
│   │   ├── subject_change_notifier.go  # outbox → NOTIFY kacho_iam_subjects
│   │   └── zitadel_user_sync.go        # background drain Zitadel user changes
│   └── apps/migrator/                # bizlogic of migrator (goose wrapper)
├── migrations/
│   ├── 0001_initial_schema.sql       # accounts, projects, users, sa, groups, group_members, roles, access_bindings
│   ├── 0002_seed_default_roles.sql   # default admin/viewer/editor per-module
│   ├── 0003_seed_default_account.sql
│   └── 0004_subject_change_outbox.sql
└── proto-stubs (gen)                 # из kacho-proto/kacho/cloud/iam/v1
```

Внутри `kacho-corelib`:
```
operations/
├── migrations/00X_add_principal.sql  # principal_type/_id/_display_name columns
└── repo.go                            # signature: Create(ctx, op, principal Principal) → Operation
```

### 2.3 Иерархия ресурсов (новая модель)

```
Account (одно-к-одному tenant; на фазу 2.0 один Account == один deployment)
  └─ Project (заменяет Folder; скоуп для VPC/Compute/NLB ресурсов)
       ├─ vpc.Network
       │     └─ vpc.Subnet
       │     └─ vpc.SecurityGroup
       │     └─ …
       ├─ compute.Instance
       │     └─ compute.Disk
       │     └─ compute.NetworkInterface (внутри VPC)
       └─ loadbalancer.NLB

Subjects (orthogonal — живут на Account-уровне, не внутри Project):
  ├─ User (mirror of Zitadel user; external_id == Zitadel-user-id)
  ├─ ServiceAccount (Zitadel-managed credentials)
  └─ Group (set of User|ServiceAccount; nested groups not supported in 2.0)

Roles (orthogonal — глобальные внутри Account; на фазу 2.0 нет cross-account):
  ├─ default admin   (full access ко всем модулям + всем resource-type per project)
  ├─ default viewer  (read-only ко всем модулям)
  ├─ default editor  (CRUD кроме delete-cascade?)
  ├─ default <module>.admin / <module>.viewer / <module>.editor (per-module: vpc.admin, compute.viewer, …)
  ├─ default <resource>.admin / <resource>.viewer / <resource>.editor (per-resource-type: vpc.network.admin, compute.instance.viewer, …)
  └─ custom roles (созданные tenant'ом; список permissions из admin-набора возможного)

AccessBinding (триада):
  (Subject{Type, ID}, Role.ID, Scope{Account|Project|Resource})
  пример: (User:u_alice, Role:admin, Project:prj_dev)
          (Group:g_dev_team, Role:vpc.admin, Project:prj_dev)
          (ServiceAccount:sva_ci, Role:compute.editor, Project:prj_prod)
          (User:u_admin, Role:admin, Account:acc_default)  ← account-wide
          (User:u_alice, Role:vpc.network.admin, Resource:enpXXX) ← resource-level
```

---

## 3. Декомпозиция эпика — E0 … E5

Каждый sub-эпик имеет **отдельный** `sub-phase-2.0-iam-E<n>-<topic>-acceptance.md` с подробными GWT-сценариями. Этот overview-документ — контракт верхнего уровня; per-эпик-документы детализируют конкретные RPC, payload-поля, миграции, error-codes.

| ID  | KAC    | Тема                                                                                            | Acceptance file                                  | Status   |
|-----|--------|-------------------------------------------------------------------------------------------------|--------------------------------------------------|----------|
| E0  | KAC-105 | `kacho-iam` skeleton + ресурсная модель CRUD без auth/authz (Account/Project/User/SA/Group/Role/AccessBinding) | `sub-phase-2.0-iam-E0-skeleton-acceptance.md`     | Draft (параллельно) |
| E1  | KAC-106 | folder_id → project_id миграция в `kacho-vpc`, `kacho-compute`, `kacho-loadbalancer`. Deprecate `kacho-resource-manager` (но не выключение). | `sub-phase-2.0-iam-E1-folder-to-project-acceptance.md` | TBD |
| E2  | KAC-107 | Zitadel deploy (helm в `kacho-deploy`) + OIDC-client в `kacho-iam` + auth-interceptor в `kacho-api-gateway` (JWT validate, Principal в ctx) | `sub-phase-2.0-iam-E2-zitadel-oidc-acceptance.md` | TBD |
| E3  | KAC-108 | OpenFGA deploy + DSL authorization model + `Check`-interceptor в api-gateway + **реактивность** (DoD #5) | `sub-phase-2.0-iam-E3-openfga-rebac-acceptance.md` | TBD |
| E4  | KAC-109 | Signup-flow (UI ↔ Zitadel) + UI блок IAM (Service Accounts, Users, Groups, Roles, Bindings) + **principal в Operations** (DoD #1, #2, #3, #4) | `sub-phase-2.0-iam-E4-signup-ui-principal-acceptance.md` | TBD |
| E5  | KAC-110 | Выключение `kacho-resource-manager` (Gone 410, data-migration `organizations`+`clouds` → `accounts`, `folders` → `projects`) | `sub-phase-2.0-iam-E5-deprecate-rm-acceptance.md` | TBD |

### 3.1 Зависимости между sub-эпиками

```
E0 (skeleton CRUD) ──┬──→ E1 (folder→project migration)
                     │
                     └──→ E2 (Zitadel OIDC) ──→ E3 (OpenFGA REBAC) ──→ E4 (signup + UI + principal)
                                                                            │
                                                                            └──→ E5 (deprecate rm)
```

- E0 — фундамент; никаких внешних deps, чисто CRUD. Параллельно с этим overview готовится отдельным агентом.
- E1 — после E0 (нужны `Project`-resource-ы для миграции из `Folder`).
- E2 — после E0 (нужен `User` mirror, чтобы Zitadel-user мог быть резолвлен в `kacho-iam.UserService`).
- E3 — после E2 (нужен auth-interceptor, чтобы `Check` имел subject).
- E4 — после E3 (signup-flow требует и Zitadel, и OpenFGA для bootstrap первого user'а с default-admin-binding'ом; UI требует все CRUD endpoints + Principal pipeline).
- E5 — последний (после E1 + E4): нужны и project_id-миграции в backend-сервисах, и UI-блок IAM для управления Account/Project.

### 3.2 Кросс-репо порядок merge (топологическая сортировка)

Для каждого sub-эпика (повторяется паттерн `01-architecture-and-services.md` § кросс-репо):

```
1. kacho-proto      — новые .proto (iam.v1) + регенерация gen/, buf lint+breaking зелёные
2. kacho-corelib    — operations.Principal (E4), audit no-op interfaces (E4-E5)
3. kacho-iam        — реализация сервиса
   ИЛИ kacho-vpc/compute/loadbalancer (E1) — folder_id→project_id
4. kacho-api-gateway— регистрация iam.v1 RPC + interceptors (E2, E3)
5. kacho-deploy     — helm charts (Zitadel E2, OpenFGA E3, kacho-iam E0)
6. kacho-ui         — IAM UI block (E4)
7. kacho-workspace  — docs/specs + obsidian vault + KAC-N.md entries
```

`replace ../`-директивы в `go.mod` после E0:
- `kacho-iam/go.mod` имеет `replace ../kacho-corelib` + `replace ../kacho-proto`.
- `kacho-api-gateway/go.mod` дополнительно импортирует `kacho-proto/gen/go/kacho/cloud/iam/v1`.
- `kacho-vpc`, `kacho-compute`, `kacho-loadbalancer` — после E1 добавляют `internal/clients/iam_client.go` (типизированный grpc-клиент к `kacho-iam.ProjectService.Get` для валидации `project_id`).

---

## 4. REBAC модель (OpenFGA DSL — целиком)

Authorization-model для OpenFGA. Записывается в `kacho-iam/internal/apps/kacho/api/access_binding/fga_model.fga` (DSL), bootstrap'ится при первом старте `kacho-iam` (или `migrator fga-bootstrap`). Версия модели сохраняется в `kacho_iam.fga_model_version(version_id, created_at)`. При изменении DSL — новая запись + write new model в OpenFGA + дальнейшие `Check`/`Write` ссылаются на новую `authorization_model_id`.

```fga
model
  schema 1.1

# Identity types
type user
type service_account
type group
  relations
    define member: [user, service_account]

# Role: единица permission-grouping.
# default-роли (admin/viewer/editor + per-module + per-resource-type) предсоздаются seed-миграцией.
# custom-роли создаются tenant'ом — relations те же, но через grant_via_binding только.
type role
  relations
    define grants: [user, service_account, group#member]

# Account: верхний tenant-scope.
# admin-binding на Account даёт каскад на все Project + все ресурсы внутри.
type account
  relations
    define admin: [user, service_account, group#member]
    define member: [user, service_account, group#member] or admin

# Project: scope для ресурсов (заменяет Folder).
# Каждый Project принадлежит ровно одному Account.
# Account.admin наследуется как Project.admin.
type project
  relations
    define account: [account]
    define admin: [user, service_account, group#member] or admin from account
    define editor: [user, service_account, group#member] or admin
    define viewer: [user, service_account, group#member] or editor

# Per-resource permissions — vpc.network
# Каждая Network принадлежит ровно одному Project.
# Project.editor/viewer наследуется (computed relation).
# Resource-level binding'и (binding на конкретный enpXXX) — для тонкой раздачи.
type vpc_network
  relations
    define project: [project]
    define admin: [user, service_account, group#member] or admin from project
    define editor: [user, service_account, group#member] or admin or editor from project
    define viewer: [user, service_account, group#member] or editor or viewer from project
    define use: [user, service_account, group#member] or viewer  # «использовать» сеть (создать NIC в Subnet) — отдельная permission

type vpc_subnet
  relations
    define network: [vpc_network]
    define admin: [user, service_account, group#member] or admin from network
    define editor: [user, service_account, group#member] or admin or editor from network
    define viewer: [user, service_account, group#member] or editor or viewer from network
    define use: [user, service_account, group#member] or use from network

type vpc_security_group
  relations
    define network: [vpc_network]
    define admin: [user, service_account, group#member] or admin from network
    define editor: [user, service_account, group#member] or admin or editor from network
    define viewer: [user, service_account, group#member] or editor or viewer from network
    define use: [user, service_account, group#member] or use from network

type vpc_route_table
  relations
    define network: [vpc_network]
    define admin: [user, service_account, group#member] or admin from network
    define editor: [user, service_account, group#member] or admin or editor from network
    define viewer: [user, service_account, group#member] or editor or viewer from network

type vpc_address
  relations
    define project: [project]   # Address привязана к Project, не к Network (может быть unbound)
    define admin: [user, service_account, group#member] or admin from project
    define editor: [user, service_account, group#member] or admin or editor from project
    define viewer: [user, service_account, group#member] or editor or viewer from project

# Per-resource permissions — compute.instance
type compute_instance
  relations
    define project: [project]
    define admin: [user, service_account, group#member] or admin from project
    define editor: [user, service_account, group#member] or admin or editor from project
    define viewer: [user, service_account, group#member] or editor or viewer from project
    define start_stop: [user, service_account, group#member] or editor

type compute_disk
  relations
    define project: [project]
    define admin: [user, service_account, group#member] or admin from project
    define editor: [user, service_account, group#member] or admin or editor from project
    define viewer: [user, service_account, group#member] or editor or viewer from project

# Per-resource permissions — loadbalancer.nlb
type lb_nlb
  relations
    define project: [project]
    define admin: [user, service_account, group#member] or admin from project
    define editor: [user, service_account, group#member] or admin or editor from project
    define viewer: [user, service_account, group#member] or editor or viewer from project

type lb_target_group
  relations
    define project: [project]
    define admin: [user, service_account, group#member] or admin from project
    define editor: [user, service_account, group#member] or admin or editor from project
    define viewer: [user, service_account, group#member] or editor or viewer from project

# IAM-сами-resources (Role, AccessBinding) — НЕ FGA-объекты.
# Управление IAM (создать Role, выдать/отозвать AccessBinding, создать User/SA/Group) —
# проверяется через permissions на родительский Account/Project, не на отдельный role/binding.
# Mapping RPC → relation для iam.* RPC см. §4.2 (object = account, relation = admin).
# Reason: Role.account_id IS NULL для system-roles → tuple на role не построится;
# AccessBinding имеет scope account|project|resource — единый scope-узел невозможен.
# Source of truth для Role и AccessBinding — таблицы kacho_iam.roles / kacho_iam.access_bindings;
# OpenFGA получает только expanded permission-tuples (см. §4.1).
```

### 4.0 Role и AccessBinding — НЕ FGA-объекты (фиксируем явно)

**Решение (Decision #13, см. §5):** types `iam_role` / `iam_access_binding` **отсутствуют** в DSL. Причины:
1. **`Role.account_id IS NULL` для system-roles** — невозможно построить tuple `role:<id> account account:<NULL>`; альтернатива «отдельный тип `iam_system_role`» удваивает типы без выгоды.
2. **`AccessBinding` имеет scope `account` ИЛИ `project` ИЛИ `<resource_type>:<id>`** — единый relation `scope_account: [account]` ошибочно исключает project- и resource-scoped binding'и; добавлять три relation'а (`scope_account`, `scope_project`, `scope_resource`) — раздувание модели без выгоды (в FGA эти узлы никем не читаются для Check'а).
3. **Role-узлы и AccessBinding-узлы никем не запрашиваются через Check** — реальные permission-чеки идут на ресурсные типы (`vpc_network:N#viewer@user:U`), а не «может ли user читать role X».

Source-of-truth для Role и AccessBinding — таблицы `kacho_iam.roles` / `kacho_iam.access_bindings` (kacho-iam-БД). OpenFGA получает только **expanded permission-tuples**, генерируемые на момент `AccessBindingService.Upsert` (см. §4.1).

Управление самим IAM (`iam.RoleService.Create`, `iam.AccessBindingService.Upsert/Delete`, `iam.UserService.*`, `iam.GroupService.*` — admin-actions) авторизуется через permission на **родительский Account** (или Project, если binding project-scoped). Mapping RPC → (object, relation) — §4.2: `iam.AccessBindingService.Upsert` → `account#admin`, `iam.RoleService.Create` → `account#admin`, и т.д. Никаких отдельных `iam_role#admin` / `iam_access_binding#admin` tuples.

### 4.1 Mapping AccessBinding-таблицы → OpenFGA tuples (AccessBinding ↔ tuple lifecycle)

**Lifecycle.** Role и AccessBinding живут как данные в `kacho_iam.*`. OpenFGA получает только результирующие permission-tuples; role-узлов и binding-узлов в FGA нет (см. §4.0). Каждый `AccessBindingService.Upsert` разворачивает `role.permissions[]` в **N tuples** в FGA; каждый `Delete` пишет **N untuples**. Это даёт точное соответствие DoD #5 «реактивность ≤10s»: write-через kacho-iam → видно в Check OpenFGA сразу же (consistency `MINIMIZE_LATENCY`), end-to-end revoke ограничен только subject-cache TTL + NOTIFY-invalidate (см. §5 #7).

`kacho-iam` при `AccessBindingService.Upsert(binding)` транзакционно делает:
1. `INSERT INTO kacho_iam.access_bindings (id, subject_type, subject_id, role_id, scope_type, scope_id, ...)` в `kacho_iam`-БД.
2. Резолвит `role.permissions[]` → список tuples `(subject_fga, relation, object_fga)` (раскладывание см. ниже).
3. Для каждой tuple — `openfga.Write(tuple)` (в БД `openfga`; не FK с `kacho_iam`, разные БД — запрет #8).
4. `INSERT INTO kacho_iam.subject_change_outbox (subject_id, op='binding_upsert', tuples_json, created_at)` — для NOTIFY-invalidate subject-кеша api-gateway (см. §5 #8).
5. COMMIT `kacho_iam`-TX.

Шаги (1), (4), (5) — в одной Postgres-TX; шаг (3) — best-effort с retry (на failure тuple-write — outbox-row остаётся, worker дореализует). Это transactional-outbox-pattern; consistency: row в `access_bindings` без соответствующих tuples виден в FGA в течение ≤ 1 worker-tick'а (обычно <500ms).

**Раскладывание permissions → tuples.** Default-role `<module>.admin` (например `vpc.admin`) на Project-scope раскладывается в **одну** tuple `<subject_fga> admin project:<prj_id>` — computed-relations в DSL (`admin from project`) уже распространяют admin на все `vpc_network` / `vpc_subnet` / `vpc_security_group` под этим проектом без N+M tuple blow-up'а (см. §5 #9). Resource-scope binding `(User:u, Role:vpc.network.admin, Resource:vpc_network:N)` — одна tuple `user:u admin vpc_network:N`. Custom-роль с произвольным набором permissions — раскладывается в столько tuples, сколько (relation × scope-уровень) она purports — детали раскладывания + edge-cases в E3-acceptance.

**Пример.** Binding (`Subject{User, u_alice}`, `Role{vpc.admin}`, `Scope{Project, prj_dev}`) →
- одна FGA-tuple: `user:u_alice admin project:prj_dev`,
- одна row в `kacho_iam.access_bindings`,
- одна outbox-row на `subject_id=u_alice`.

При `AccessBindingService.Delete(binding_id)` — обратное (DELETE row + `openfga.Delete(tuples)` для всех tuples, записанных на Upsert (хранятся в `access_bindings.fga_tuples_json` для idempotent un-write) + outbox NOTIFY с `op='binding_delete'`).

### 4.2 `Check`-вызов на каждый RPC

api-gateway interceptor для каждой publically-exposed RPC формирует `Check(user: <principal>, relation: <action>, object: <type>:<resource_id>)`. Соответствие `RPC → relation` зашито в `kacho-api-gateway/internal/authz/rpc_permissions.go`:

| RPC                                       | Object type     | Relation     |
|-------------------------------------------|-----------------|--------------|
| `vpc.NetworkService.Create`               | `project`       | `editor`     |
| `vpc.NetworkService.Get`                  | `vpc_network`   | `viewer`     |
| `vpc.NetworkService.Update`               | `vpc_network`   | `editor`     |
| `vpc.NetworkService.Delete`               | `vpc_network`   | `admin`      |
| `vpc.NetworkService.List`                 | `project`       | `viewer`     |
| `vpc.SubnetService.Create`                | `vpc_network`   | `editor`     |
| `compute.InstanceService.Create`          | `project`       | `editor`     |
| `compute.InstanceService.Start`           | `compute_instance` | `start_stop` |
| `compute.InstanceService.Update`          | `compute_instance` | `editor`     |
| `iam.AccessBindingService.Upsert` (account-scope)  | `account`     | `admin`      |
| `iam.AccessBindingService.Upsert` (project-scope)  | `project`     | `admin`      |
| `iam.AccessBindingService.Upsert` (resource-scope) | `<resource_type>` (vpc_network/...) | `admin` |
| `iam.AccessBindingService.Delete`         | (как Upsert, по scope binding-а)    |             |
| `iam.RoleService.Create` (custom-role)    | `account`       | `admin`      |
| `iam.RoleService.Delete` (custom-role)    | `account`       | `admin`      |
| `iam.UserService.List`                    | `account`       | `viewer`     |
| `iam.ServiceAccountService.Create`        | `project`       | `admin`      |
| `iam.GroupService.Create`                 | `account`       | `admin`      |
| ... (полный mapping — в E3 acceptance)    |                 |              |

Note: для IAM admin-actions object = родительский Account (или Project / Resource — для scope-conditional Upsert/Delete binding'а), relation = `admin` или `viewer`. Отдельных `iam_role` / `iam_access_binding` FGA-типов нет (см. §4.0).

**Один Check на RPC** (non-functional requirement). Для List-операций — `Check(viewer on parent_scope)`, а не итерация по элементам (filtering — на стороне backend, либо через `openfga.ListObjects` если потребуется per-item filtering — это уже в Phase 2.1 если SLA не вытягивает).

---

## 5. Принципиальные решения

| # | Decision                                                                                         | Rationale                                                                                                                                  | Alternatives rejected                                                                              |
|---|--------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------|
| 1 | Использовать **Zitadel** как OIDC-provider (self-host)                                          | Open-source, готовый signup-flow, OIDC-compliant, поддерживает SA-credentials через management-API, активно развивается                  | (a) Keycloak — тяжелее в эксплуатации; (b) Ory Hydra/Kratos — fragmented, нет ready-made signup UI; (c) свой self-roll — out of scope MVP |
| 2 | Использовать **OpenFGA** (Zanzibar-style REBAC)                                                  | Готовая реализация Google Zanzibar model, sub-100ms `Check`, поддержка nested groups, computed relations, Go SDK; native Postgres tuple-store | (a) Keto (Ory) — менее зрелый, slower; (b) свой PG-based — переизобретение Zanzibar; (c) Casbin (RBAC) — нет первокласного REBAC                |
| 3 | **kacho-iam — отдельный сервис** (не модуль resource-manager)                                    | Чёткая separation of concerns; database-per-service (запрет #8); evgeniy-style scaffolding с нуля без legacy resource-manager долга         | (a) Расширить resource-manager — нарушает DB-per-service (новые IAM-таблицы попадут в `kacho_resource_manager`); (b) IAM как library в каждом сервисе — нарушает single-owner-per-resource |
| 4 | **Account/Project** заменяют **Organization/Cloud/Folder** (не parallel)                         | Org→Cloud двухуровневая иерархия избыточна; современные IaaS (AWS, GCP, Yandex Cloud в новой модели) сошлись на Account+Project двухуровне | (a) Сохранить Org/Cloud + добавить IAM поверх — два иерархических слоя, double-bookkeeping; (b) Account только (без Project) — теряем scope ресурсов внутри tenant |
| 5 | **User — mirror в `kacho_iam.users`** (источник истины Zitadel)                                  | Нужен local FK для AccessBinding.subject_id; denormalized display_name/email для UI без round-trip в Zitadel на каждый Operations.list   | (a) Хранить только Zitadel-id в bindings без mirror — каждый List бьёт Zitadel = N+1 round-trips; (b) Полный copy users в kacho_iam без Zitadel — теряем Zitadel signup-flow / MFA |
| 6 | **Principal в Operations** — расширение **corelib**, не per-service                              | Колонка одинаковая во всех сервисах; миграция через `kacho-corelib/migrations/common/` + `make sync-migrations` уже работает              | (a) В каждом сервисе своя миграция — drift риск; (b) Только в kacho-iam — теряем principal на vpc/compute/lb Operations (DoD #4 не выполнен) |
| 7 | **`Check`-кеш в api-gateway отсутствует**, но subject-кеш есть (30s TTL + NOTIFY-invalidate)    | OpenFGA `Check` уже <20ms p95; кеш `Check`-resultов даст stale-permissions при revoke и противоречит DoD #5; subject-lookup дороже (kacho-iam round-trip + JWKS validation) — оправдан кеш | (a) Кешировать `Check`-результаты — расходится с DoD #5; (b) Без subject-кеша — auth-interceptor добавит ~50ms на каждый RPC |
| 8 | **Реактивность via NOTIFY** (не TTL и не long-poll Watch)                                        | Patterns уже есть в corelib outbox; точечный invalidate; sub-second propagation; consistent с архитектурным стилем kacho-corelib          | (a) TTL only (≥10min как в YC) — расходится с DoD #5; (b) gRPC server-streaming Watch — выкинут с Phase 1.0 (см. workspace `CLAUDE.md` §«API contract») |
| 9 | **REBAC computed relations**, не explicit per-resource tuples                                    | `admin from project` — одна tuple для всего project; иначе при создании 100 Network на каждый — еще 100 tuples = O(N*M) blow-up           | (a) Materialize все tuples per-resource — write amplification на каждый ресурс; (b) ABAC (атрибуты в tokens) — heavier; нет ready-made engine с тем же UX |
| 10| **OIDC-issuer = self-hosted Zitadel** (не managed cloud)                                          | Dev-стенд должен работать локально без external deps; единая модель prod=dev (`helm install zitadel`); полный контроль над signup-flow UX | (a) Zitadel.cloud (managed) — внешняя зависимость для dev; (b) Auth0 — proprietary; (c) Keycloak — тяжелее ops |
| 11| **kacho-resource-manager выключается полностью** (не coexistance)                                | Поддерживать два source-of-truth для иерархии — split-brain; миграция данных одноразовая в E5; меньше cognitive load для tenant'а         | (a) Coexistance (rm для legacy folders, iam для new projects) — двойная иерархия, миграционный долг бесконечный |
| 12| **Account-wide bindings (Account-scope)** допустимы на фазу 2.0                                  | Default-admin (первый user после signup) получает binding `(User:u_first, Role:admin, Scope:Account:acc_default)` — иначе нечем bootstrap | Без account-wide — bootstrap требует один-binding-per-project, неудобно при создании нового project'а |
| 13| **Role и AccessBinding — НЕ FGA-объекты; OpenFGA получает только expanded permission-tuples**    | `Role.account_id IS NULL` для system-roles → tuple на role не построится; AccessBinding имеет scope account/project/resource → единый scope-узел невозможен; role/binding-узлы никем не Check'аются (Check идёт на ресурсные типы). Source-of-truth — `kacho_iam.roles`/`access_bindings`. Управление IAM авторизуется через `account#admin` или `project#admin` (см. §4.0, §4.2). | (a) Добавить отдельный тип `iam_system_role` + три scope-relation'а на `iam_access_binding` — раздувание DSL без выгоды; (b) tuple `role:<id> account account:<NULL>` — не строится; (c) единый `scope_account` — ошибочно исключает project/resource-scope binding'и |

---

## 6. Кросс-доменные правила (gating)

Перед написанием per-эпиковых acceptance — фиксируем правила, общие для всего эпика. Они **обязательны** во всех E0…E5 sub-эпиках, не повторяются в каждом отдельно.

### 6.1 Naming convention

- Proto package: `kacho.cloud.iam.v1`. Файлы: `account.proto`, `project.proto`, `user.proto`, `service_account.proto`, `group.proto`, `role.proto`, `access_binding.proto`, `subject.proto` (envelope), `internal_subject_service.proto` (для api-gateway lookup).
- Postgres database: `kacho_iam`. Schema: `kacho_iam` (не `public`).
- ENV: `KACHO_IAM_<NAME>` (например `KACHO_IAM_REPOSITORY__POSTGRES__URL`, `KACHO_IAM_ZITADEL__ISSUER`, `KACHO_IAM_OPENFGA__ENDPOINT`).
- REST paths (через api-gateway): `/iam/v1/{accounts,projects,users,serviceAccounts,groups,roles,accessBindings}`.
- ID prefixes (3-char crockford-base32 для prefix-routing): `acc` / `prj` / `usr` / `sva` / `grp` / `rol` / `bnd`.

### 6.2 Запреты, применимые ко всему эпику

- **Запрет #1 (acceptance gate)** — каждый sub-эпик E0…E5 имеет свой APPROVED acceptance-документ ДО старта кода. Этот overview — overview-уровень, не отменяет per-эпиковые approves.
- **Запрет #4 (нет cross-service cascade)** — удаление Account/Project не запускает cascade-удаление ресурсов в kacho-vpc / kacho-compute / kacho-loadbalancer; вместо этого — `FailedPrecondition "project has resources"` (best-effort usage-hint), ответственность tenant'а. Cross-DB FK невозможен (запрет #8).
- **Запрет #6 (Internal vs Public)** — `kacho-iam.InternalSubjectService`, `kacho-iam.InternalFGABootstrapService`, `kacho-iam.InternalSubjectChangeNotificationService` — НЕ публикуются на external TLS endpoint. Слушают на internal-port `9091` (cluster-internal listener) в `kacho-iam`. Routing двух категорий разделён, чтобы избежать loop'а auth-interceptor через собственный REST mux:
  - **`InternalSubjectService.Lookup` — gRPC-direct call от api-gateway** (используется auth-interceptor'ом, см. §2.1). api-gateway держит отдельный `grpcclient` в `kacho-api-gateway/internal/clients/iam_client.go`, dial-target `kacho-iam.kacho.svc.cluster.local:9091`. **НЕ регистрируется** в `kacho-api-gateway/internal/restmux/mux.go` — иначе auth-interceptor (на REST-входе) → REST-mux → backend `Lookup` → response через тот же REST-выход → возврат в auth-interceptor → infinite recursion. То же касается `InternalSubjectChangeNotificationService.Watch` (LISTEN/NOTIFY-channel, gRPC streaming напрямую).
  - **Admin-internal REST** — `/iam/v1/internal/users:upsertFromIdentity`, `/iam/v1/internal/fga:bootstrap`, `/iam/v1/internal/subjects:lookup` (для admin UI / тулинга, **не** для interceptor'а) — регистрируется в `kacho-api-gateway/internal/restmux/mux.go` под `iamInternalAddr` блоком на cluster-internal HTTP listener (по аналогии с `vpcInternalAddr`). Слушает только cluster-internal, не external TLS.
- **Запрет #8 (DB-per-service)** — `kacho-iam` имеет свою БД `kacho_iam`; Zitadel — свою БД `zitadel` (отдельный Postgres-экземпляр в dev, отдельный namespace в prod); OpenFGA — свою `openfga`. Никаких shared-tables.
- **Запрет #10 (within-service refs — DB-level)** — `kacho_iam.access_bindings.role_id → kacho_iam.roles(id) ON DELETE RESTRICT`, `.subject_id` (когда subject_type='user') соответствует `users(id)`, FK на partial conditional через triggers если нужно. Атомарный CAS на role.is_system (нельзя удалить system-role) — single-statement `DELETE … WHERE is_system=false RETURNING ...`. Concurrent AccessBinding.Upsert на одну (subject, role, scope)-тройку — UNIQUE constraint `access_bindings_subject_role_scope_uniq`. OpenFGA tuple write — отдельно через openfga-client, **не FK** (другая БД), но обёрнуто транзакционно через outbox-pattern: row + outbox-marker в одной TX, FGA-write в worker.
- **Запрет #11 (тесты в том же PR)** — каждый PR с новым RPC iam.v1 / новым полем / новой миграцией — содержит integration-тест (`internal/repo/*_integration_test.go`, testcontainers Postgres + testcontainers OpenFGA для FGA-зависимых тестов + testcontainers Zitadel для OIDC-зависимых) + newman-кейс (`tests/newman/cases/*.py` через api-gateway).

### 6.3 Кросс-доменные ссылки (новые edges) — phase shift по sub-эпикам

Соответствует регламенту workspace `CLAUDE.md` §«Кросс-доменные ссылки на ресурсы». **Phase shift**: edges появляются не одновременно, а постепенно — по мере merge'а E0…E5. Это важно: до E1 peer-сервисы (`kacho-vpc/compute/loadbalancer`) **ещё не зовут** `kacho-iam` (он stub-сервис без consumer'ов), они продолжают валидировать `folder_id` через `kacho-resource-manager.FolderService.Get`.

**Таблица «когда появляется / когда исчезает» edge:**

| Edge                                                                   | Появляется (sub-эпик) | Исчезает / меняется                  |
|------------------------------------------------------------------------|------------------------|---------------------------------------|
| `kacho-vpc → kacho-resource-manager.FolderService.Get`                 | (существует до KAC-104) | E1 — заменяется на `→ kacho-iam.ProjectService.Get` |
| `kacho-compute → kacho-resource-manager.FolderService.Get`             | (существует до KAC-104) | E1 — заменяется на `→ kacho-iam.ProjectService.Get` |
| `kacho-loadbalancer → kacho-resource-manager.FolderService.Get`        | (существует до KAC-104) | E1 — заменяется на `→ kacho-iam.ProjectService.Get` |
| `kacho-vpc → kacho-iam.ProjectService.Get` (валидация `project_id`)    | **E1** (KAC-106)        | — (стабильно)                         |
| `kacho-compute → kacho-iam.ProjectService.Get`                         | **E1** (KAC-106)        | —                                     |
| `kacho-loadbalancer → kacho-iam.ProjectService.Get`                    | **E1** (KAC-106)        | —                                     |
| `kacho-api-gateway → kacho-iam.InternalSubjectService.Lookup` (gRPC-direct) | **E2** (KAC-107)   | —                                     |
| `kacho-api-gateway → kacho-iam.InternalSubjectChangeNotificationService.Watch` (gRPC-direct stream) | **E3** (KAC-108) | — |
| `kacho-api-gateway → Zitadel` (JWKS, cached)                           | **E2** (KAC-107)        | —                                     |
| `kacho-iam → Zitadel` (OIDC discovery + management-API для SA)         | **E2** (KAC-107)        | —                                     |
| `kacho-api-gateway → OpenFGA.Check`                                    | **E3** (KAC-108)        | —                                     |
| `kacho-iam → OpenFGA.Write/Delete/Read` (tuples)                       | **E3** (KAC-108)        | —                                     |
| Любой edge `* → kacho-resource-manager.*`                              | (legacy)                | **E5** (KAC-110) — удаляется полностью |

**Фазовый профиль:**
- **E0 (KAC-105):** `kacho-iam` поднят как stub-CRUD, **никто не зовёт** (peer-сервисы ещё `→ kacho-resource-manager`).
- **E1 (KAC-106):** peer-сервисы переключают валидацию `folder_id → project_id` на `kacho-iam.ProjectService.Get`. Старый edge `* → kacho-resource-manager.FolderService.Get` остаётся как fallback до E5 — пока deprecated, но не удалён.
- **E2 (KAC-107):** api-gateway начинает звать `kacho-iam.InternalSubjectService` (gRPC-direct, §6.2) + Zitadel JWKS.
- **E3 (KAC-108):** api-gateway начинает звать OpenFGA `Check`; kacho-iam — `Write`/`Delete` на AccessBinding. NOTIFY-канал между kacho-iam и api-gateway активен.
- **E5 (KAC-110):** все edges `* → kacho-resource-manager.*` удаляются; `kacho-resource-manager` выключается полностью (REST → `Gone 410`).

**Циклы запрещены.** `kacho-iam` — leaf-owner identity/auth, обратные edges `kacho-iam → kacho-{vpc,compute,loadbalancer,api-gateway}` запрещены (как `kacho-resource-manager` был leaf-owner иерархии).

---

## 7. GWT-сценарии (epic-level, по 2 на DoD-пункт)

Сценарии ниже — overview-level. Каждый из них **раскрывается в подробный** GWT в соответствующем per-эпиковом acceptance-документе с конкретным payload, error-codes, edge-cases. Здесь — высокоуровневая проверка достижения DoD без углубления в реализационные детали.

Формат: `Scenario E<n>.GWT-<m>: <название>`.

### 7.1 DoD #1 — UI signup-flow

#### Scenario E4.GWT-01: First-time signup — нового пользователя нет, Zitadel создаёт + kacho-iam mirror'ит + first-user получает default-admin binding

**ID:** 2.0-E4-GWT-01
**REQ:** REQ-IAM-SIGNUP-01

**Given** `kacho-deploy` стенд поднят (`make dev-up`), сервисы `kacho-iam`, `kacho-api-gateway`, Zitadel, OpenFGA — healthy
**And** в Zitadel и `kacho_iam.users` нет ни одного user (свежий cluster)
**And** seed-миграция `0003_seed_default_account.sql` применена (`kacho_iam.accounts` содержит row `acc_default`; `kacho_iam.projects` содержит row `prj_default` со ссылкой на `acc_default`; `kacho_iam.roles` содержит `rol_default_admin`, `rol_default_viewer`, `rol_default_editor` + per-module variants — иначе «first user → default-admin binding» нечем выдавать)
**And** UI-вкладка `/signup` доступна на `https://api.kacho.local/signup`

**When** новый посетитель открывает `/signup`, заполняет email = `alice@example.com`, password (по Zitadel-policy), submit
**And** Zitadel принимает signup, отдаёт OIDC-callback на api-gateway с access_token
**And** api-gateway резолвит subject через `kacho-iam.InternalSubjectService.Lookup({external_id: "<zitadel-user-id>"})`
**And** `kacho-iam.UserService` не находит mirror-row → создаёт `users{id: "usr...", external_id: "<zitadel-user-id>", email: "alice@example.com", display_name: ...}`
**And** `kacho-iam` определяет «first user in default-account» → создаёт `access_bindings{subject_type: 'user', subject_id: 'usr...', role_id: 'rol_default_admin', scope_type: 'account', scope_id: 'acc_default'}`
**And** соответствующие OpenFGA tuples записаны (`user:usr... admin account:acc_default`)

**Then** UI редиректит на `/` (главная)
**And** в верхнем правом углу отображается email `alice@example.com` + кнопка logout
**And** `GET /iam/v1/users` (через UI с access_token) возвращает массив из одного user'а
**And** `GET /iam/v1/accessBindings?scope.type=account&scope.id=acc_default` возвращает binding (admin)
**And** при последующем `GET /vpc/v1/networks?projectId=prj_default` через api-gateway — статус 200 (admin наследует на все Project)

#### Scenario E4.GWT-02: Returning user — повторный логин уже-зарегистрированного user'а не дублирует mirror и не пере-выдаёт binding

**ID:** 2.0-E4-GWT-02
**REQ:** REQ-IAM-SIGNUP-02

**Given** `alice@example.com` уже зарегистрирована (GWT-01 выполнен)
**And** в `kacho_iam.users` ровно одна row для alice, `count(access_bindings WHERE subject_id='usr_alice') == 1`

**When** alice выходит (logout) и снова логинится через `/login` (Zitadel auth-flow)

**Then** Zitadel выдаёт новый access_token для того же `external_id`
**And** api-gateway резолвит subject через `kacho-iam.InternalSubjectService.Lookup` — находит существующий mirror, mirror **не** создаётся повторно
**And** `count(kacho_iam.users WHERE external_id=<zitadel-id>) == 1` (без duplicate)
**And** `count(kacho_iam.access_bindings WHERE subject_id='usr_alice') == 1` (без duplicate)
**And** UI снова показывает alice залогиненной, доступы те же

### 7.2 DoD #2 — UI IAM-блок (навигация / видимость)

#### Scenario E4.GWT-03: Owner видит IAM-блок в side-nav и может открыть child-pages

**ID:** 2.0-E4-GWT-03
**REQ:** REQ-IAM-UI-NAV-01

**Given** alice (`Role:admin` на `Account:acc_default` — из GWT-01) залогинена в UI

**When** alice смотрит на side-nav UI

**Then** в навигации виден блок «Identity and Access Management» (icon + label) — рядом с VPC, Compute, Load Balancer
**And** при клике на блок раскрываются child-pages: `Users`, `Service Accounts`, `Groups`, `Roles`, `Access Bindings`
**And** клик на каждую child-page открывает соответствующий list-view с заполненными данными (минимум — alice в Users, default-roles в Roles, alice's binding в Access Bindings)

#### Scenario E4.GWT-04: Viewer (default `viewer`-binding) видит блок только для read; не видит admin-actions

**ID:** 2.0-E4-GWT-04
**REQ:** REQ-IAM-UI-NAV-02

**Given** alice (admin) создала user `bob@example.com` через signup-flow + дала ему binding `(User:usr_bob, Role:viewer, Scope:Account:acc_default)` через `POST /iam/v1/accessBindings`

**When** bob залогинен в UI

**Then** в side-nav бoб видит IAM-блок, но при открытии `Users` / `Service Accounts` / `Groups` / `Roles` / `Access Bindings` кнопки `Create` / `Edit` / `Delete` **отсутствуют** (или disabled с tooltip «No permission»)
**And** попытка дёрнуть `POST /iam/v1/users` напрямую (через DevTools) возвращает `PermissionDenied`
**And** `GET /iam/v1/accessBindings` возвращает 200 с полным list (viewer имеет read-access)
**And** попытка `DELETE /iam/v1/accessBindings/{id_alice_binding}` — `PermissionDenied`

### 7.3 DoD #3 — SA/Users/Groups/Roles/Bindings CRUD

#### Scenario E4.GWT-05: Admin создаёт ServiceAccount + выдаёт ему `editor` на Project — SA-credentials работают через api-gateway

**ID:** 2.0-E4-GWT-05
**REQ:** REQ-IAM-SA-CREATE-01

**Given** alice (admin) залогинена
**And** существует Project `prj_dev` (создан alice'й через `POST /iam/v1/projects`)

**When** alice через UI «Service Accounts → Create» с `name = "ci-runner"`, `description = "GitHub Actions CI"`
**And** UI зовёт `POST /iam/v1/serviceAccounts` с payload, получает `Operation` → poll → `done=true` → `ServiceAccount{id: "sva...", name: "ci-runner"}`
**And** UI зовёт `POST /iam/v1/serviceAccounts/sva.../createKey` → возвращает `{key_id, private_key_pem, public_key_pem}` (приватный показывается один раз)
**And** alice через «Access Bindings → Create» создаёт `(Subject:ServiceAccount:sva..., Role:editor, Scope:Project:prj_dev)`

**Then** в OpenFGA появляется tuple `user_or_sa:sva... editor project:prj_dev` (computed via `service_account` type → mapped в FGA как `service_account:sva...`)
**And** в течение ≤1s SA с её ключом может вызвать `GET /vpc/v1/networks?projectId=prj_dev` через api-gateway, используя JWT-token (issued Zitadel SA-credential flow или direct ключ-based; механика — в E2-acceptance) → 200
**And** SA при попытке `DELETE /vpc/v1/networks/{id}` (admin-action) — получает `PermissionDenied` (editor != admin)

#### Scenario E4.GWT-06: Admin создаёт Group, добавляет users, привязывает Group к Role на Project — все members получают права через group computed relation

**ID:** 2.0-E4-GWT-06
**REQ:** REQ-IAM-GROUP-01

**Given** alice (admin) залогинена
**And** существуют users `bob@example.com` (usr_bob), `charlie@example.com` (usr_charlie) — оба signup'нулись
**And** существует Project `prj_dev`

**When** alice через UI «Groups → Create» с `name = "dev-team"`
**And** UI зовёт `POST /iam/v1/groups` → `Group{id: "grp..."}`
**And** alice через UI «Groups → grp... → Add member» добавляет usr_bob и usr_charlie (два вызова `POST /iam/v1/groups/grp.../members`)
**And** alice через UI «Access Bindings → Create» создаёт `(Subject:Group:grp..., Role:editor, Scope:Project:prj_dev)`

**Then** в OpenFGA появляются tuples:
- `group:grp... member user:usr_bob`
- `group:grp... member user:usr_charlie`
- `group:grp...#member editor project:prj_dev`
**And** в течение ≤1s bob может вызвать `POST /vpc/v1/networks` (editor-action) на prj_dev → 202 + Operation → done=true → Network создан
**And** charlie может то же самое (group computed-relation работает)
**And** alice удаляет usr_charlie из группы (`DELETE /iam/v1/groups/grp.../members/usr_charlie`) → в течение ≤10s charlie теряет editor-доступ на prj_dev → `POST /vpc/v1/networks` → `PermissionDenied`

### 7.4 DoD #4 — Principal в Operation

#### Scenario E4.GWT-07: Operation, созданный user'ом, показывает реального user'а в `operations.principal_*`

**ID:** 2.0-E4-GWT-07
**REQ:** REQ-IAM-PRINCIPAL-USER-01

**Given** alice залогинена (admin)
**And** существует Project `prj_dev`

**When** alice через UI «VPC → Networks → Create» создаёт Network `dev-net` в `prj_dev`
**And** api-gateway пропустил запрос через auth-interceptor (Principal в gRPC ctx-metadata = `{Type: USER, ID: usr_alice, DisplayName: alice@example.com}`)
**And** `kacho-vpc.NetworkService.Create` зовёт `corelib.operations.Create(ctx, ..., principalFromCtx(ctx))`

**Then** в `kacho_vpc.operations` появляется row с `principal_type='user'`, `principal_id='usr_alice'`, `principal_display_name='alice@example.com'`
**And** REST `GET /vpc/v1/operations/{id}` возвращает payload с полем `created_by: {type: 'USER', id: 'usr_alice', display_name: 'alice@example.com'}`
**And** UI на operations-странице отображает «Created by alice@example.com», не `system` и не stub

#### Scenario E4.GWT-08: Operation, созданный ServiceAccount, показывает SA в principal

**ID:** 2.0-E4-GWT-08
**REQ:** REQ-IAM-PRINCIPAL-SA-01

**Given** SA `ci-runner` (sva_ci) с binding editor на prj_dev (из GWT-05)
**And** SA-credentials работают

**When** CI-bot (используя SA-credentials) вызывает `POST /vpc/v1/networks` в `prj_dev` с `name = "ci-network"`
**And** api-gateway резолвит SA через `kacho-iam.SubjectLookup` → `Principal{Type: SERVICE_ACCOUNT, ID: sva_ci, DisplayName: 'ci-runner'}`

**Then** в `kacho_vpc.operations` появляется row с `principal_type='service_account'`, `principal_id='sva_ci'`, `principal_display_name='ci-runner'`
**And** UI отображает «Created by ServiceAccount: ci-runner» (с иконкой SA)
**And** при `GET /iam/v1/serviceAccounts/sva_ci/operations` (если такой endpoint существует) — endpoint возвращает все Operations этого SA

### 7.5 DoD #5 — Реактивность изменений прав

#### Scenario E3.GWT-01: Revoke role применяется к user'у в ≤10s (worst-case TTL) и обычно <1s (NOTIFY-invalidate)

**ID:** 2.0-E3-GWT-01
**REQ:** REQ-IAM-REACTIVE-01

**Given** bob имеет binding `(User:usr_bob, Role:editor, Scope:Project:prj_dev)` — может создавать Networks
**And** bob непрерывно делает `POST /vpc/v1/networks` в цикле каждые 500ms (или `kubectl exec` через debug-pod с `grpcurl`-loop)
**And** все запросы успешны (202 + Operation)

**When** в момент t0 alice (admin) вызывает `DELETE /iam/v1/accessBindings/{bob_editor_binding_id}`
**And** `kacho-iam.AccessBindingService.Delete` транзакционно (a) удаляет row, (b) пишет `openfga.Delete(tuple)`, (c) пишет outbox-row `subject_change` с `subject_id=usr_bob`
**And** `kacho-iam.SubjectChangeNotifier` job читает outbox → `pg_notify('kacho_iam_subjects', 'usr_bob')`
**And** api-gateway (subscriber на `kacho_iam_subjects`) получает NOTIFY → invalidate subject-cache entry для usr_bob

**Then** в момент `t0 + Δ` (Δ ≤ 1s типично, Δ ≤ 10s worst-case при потере NOTIFY и TTL-expiry) очередной запрос bob получает `PermissionDenied`
**And** `Δ` измеряется и логируется в тесте (assertion `Δ <= 10s`)
**And** Service-под `kacho-api-gateway` НЕ перезапускался (`kubectl get pods -n kacho` → restarts == 0)

#### Scenario E3.GWT-02: Grant role на Project виден сразу для всех ресурсов внутри Project (computed relation)

**ID:** 2.0-E3-GWT-02
**REQ:** REQ-IAM-REACTIVE-02

**Given** в `prj_dev` существуют 3 Network'а: `net-a`, `net-b`, `net-c`
**And** bob НЕ имеет никаких bindings; попытка `GET /vpc/v1/networks/{any}` возвращает `PermissionDenied`

**When** alice вызывает `POST /iam/v1/accessBindings` с `(User:usr_bob, Role:viewer, Scope:Project:prj_dev)`
**And** `kacho-iam` транзакционно создаёт row + `openfga.Write(tuple: user:usr_bob viewer project:prj_dev)`

**Then** в течение ≤1s bob может `GET /vpc/v1/networks/net-a`, `net-b`, `net-c` — все 200 (computed-relation `admin from project` раскрывается без extra tuples per-resource)
**And** также может `GET /vpc/v1/subnets/{any subnet в любой из этих 3 networks}` — 200 (computed через `viewer from network from project`)
**And** **не может** `POST /vpc/v1/networks` (создать новый — нужна `editor`)
**And** **не может** `DELETE /vpc/v1/networks/net-a` (нужна `admin`)
**And** UI у bob'а на странице `/vpc/networks` отображает все 3 network'а

#### Scenario E3.GWT-03: Restart api-gateway во время revoke ничего не теряет — новый pod не имеет stale-cache, DENY enforced сразу

**ID:** 2.0-E3-GWT-03
**REQ:** REQ-IAM-REACTIVE-03 (DoD #5 — restart-resistance)

**Given** bob имеет binding `(User:usr_bob, Role:viewer, Scope:vpc_network:net-N)` через резолв на `(Subject:User:usr_bob, Role:vpc.network.viewer, Scope:Resource:vpc_network:net-N)`
**And** в OpenFGA присутствует tuple `user:usr_bob viewer vpc_network:net-N`
**And** bob делает `GET /vpc/v1/networks/net-N` через api-gateway → 200 (cache-warm для subject usr_bob + Check'а)
**And** в момент t0 alice (admin) делает `DELETE /iam/v1/accessBindings/{bob_viewer_binding_id}` → tuple-untuple в OpenFGA + outbox NOTIFY

**When** в момент `t0 + Δ1` (Δ1 < 5s, гарантируем что NOTIFY ещё не обязательно дошёл) разработчик делает `kubectl rollout restart deployment/kacho-api-gateway -n kacho`
**And** ждёт `kubectl rollout status deployment/kacho-api-gateway -n kacho` → `successfully rolled out` (новый pod Ready, старый Terminated)
**And** bob делает повторный `GET /vpc/v1/networks/net-N`

**Then** ответ — `PermissionDenied` (либо HTTP 403, либо gRPC code 7)
**And** новый pod НЕ имеет stale subject-cache entries (cache — in-memory, при старте пустой)
**And** OpenFGA `Check(user:usr_bob, viewer, vpc_network:net-N)` возвращает `allowed=false` (tuple уже удалена в `t0`)
**And** `kubectl get pods -n kacho -l app=kacho-api-gateway -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}'` показывает 0 для нового pod'а (rolling restart, не crash-loop)
**And** ни один RPC bob'а после restart-а НЕ прошёл (тест ассертит, что revoke виден immediately в новом pod, без grace-period на «прогрев»)

### 7.6 DoD #6 — Репо `kacho-iam` live в `kacho-deploy`

#### Scenario E0.GWT-01: `make dev-up` поднимает `kacho-iam` pod с `healthy=true`

**ID:** 2.0-E0-GWT-01
**REQ:** REQ-IAM-DEPLOY-01

**Given** свежий рабочий dev-стенд (`make dev-down` если поднимался ранее)
**And** в `kacho-deploy/helm/umbrella/values.yaml` добавлен `kacho-iam` chart (с image-tag из CI build'а)
**And** в `kacho-deploy/helm/umbrella` присутствуют sub-charts для Zitadel + OpenFGA + Postgres-instance `kacho_iam`

**When** разработчик выполняет `cd project/kacho-deploy && make dev-up`

**Then** `kubectl get pods -n kacho` показывает:
- `kacho-iam-XXX` — `Running`, `Ready 1/1`
- `kacho-iam-postgres-0` — `Running`, `Ready 1/1`
- `zitadel-XXX` — `Running`, `Ready 1/1`
- `zitadel-postgres-0` — `Running`, `Ready 1/1`
- `openfga-XXX` — `Running`, `Ready 1/1`
- `openfga-postgres-0` — `Running`, `Ready 1/1`
- все остальные ранее существовавшие сервисы (`kacho-vpc`, `kacho-compute`, `kacho-loadbalancer`, `kacho-api-gateway`, `kacho-ui`, `kacho-resource-manager`) — `Running`
**And** `kubectl exec kacho-iam-XXX -- /healthz` → `200 OK`
**And** `grpcurl -plaintext kacho-iam.kacho.svc.cluster.local:9090 list` показывает `kacho.cloud.iam.v1.AccountService`, `ProjectService`, `UserService`, `ServiceAccountService`, `GroupService`, `RoleService`, `AccessBindingService`
**And** время от `make dev-up` до полной готовности ≤ 8 минут (на reference-машине)

#### Scenario E0.GWT-02: `bin/kacho-iam-migrator up` создаёт схему `kacho_iam` со всеми таблицами и default-roles

**ID:** 2.0-E0-GWT-02
**REQ:** REQ-IAM-DEPLOY-02

**Given** чистый Postgres экземпляр `kacho_iam_postgres` (база создана, схема `kacho_iam` пустая)
**And** есть собранный бинарь `bin/kacho-iam-migrator` (`cmd/migrator/main.go` через cobra — evgeniy §9 K.1)
**And** ENV `KACHO_IAM_REPOSITORY__POSTGRES__URL` установлен

**When** разработчик выполняет `bin/kacho-iam-migrator up --dialect=postgres`

**Then** в схеме `kacho_iam` присутствуют таблицы (минимум): `accounts`, `projects`, `users`, `service_accounts`, `groups`, `group_members`, `roles`, `access_bindings`, `fga_model_version`, `operations`, `subject_change_outbox`
**And** все FK / UNIQUE / CHECK constraints из миграций применены (`SELECT conname FROM pg_constraint WHERE conrelid::regclass::text LIKE 'kacho_iam.%'` показывает ожидаемое множество)
**And** в `kacho_iam.roles` есть default-roles: минимум `rol_default_admin`, `rol_default_viewer`, `rol_default_editor` + per-module (vpc.admin/viewer/editor, compute.admin/viewer/editor, loadbalancer.admin/viewer/editor, iam.admin/viewer/editor)
**And** в `kacho_iam.accounts` есть default `acc_default` (если миграция `0003_seed_default_account.sql` применена)
**And** в `kacho_iam.projects` есть default `prj_default` ссылающийся на `acc_default`
**And** `migrator status` показывает все миграции как `applied`

---

## 8. Нефункциональные требования

| ID | Требование | Метрика / Verification |
|----|------------|------------------------|
| NFR-1 | OIDC JWT validation latency p95 ≤ 5ms (JWKS-cached) | E2 integration-тест: 1000 requests, измерить interceptor-latency через histogram-метрики Prometheus |
| NFR-2 | OpenFGA Check latency p95 ≤ 20ms | E3 integration-тест: 1000 requests, измерить через api-gateway histogram |
| NFR-3 | ≤ 1 OpenFGA `Check` call на RPC | E3 integration-тест: assert counter `openfga_check_calls_per_rpc_total <= 1` для каждого RPC-type |
| NFR-4 | Operation.principal заполняется атомарно с insert Operation row | E4 integration-тест: при `operations.Create(ctx, op, principal)` row сразу содержит principal_*; concurrent тесты на consistency |
| NFR-5 | Subject lookup cache TTL 30s + invalidate via NOTIFY | E3 integration-тест: revoke binding + measure end-to-end Δ → assert Δ ≤ 10s в worst-case, ≤ 1s в typical (P95) |
| NFR-6 | OpenFGA store-write на AccessBinding.Upsert — sub-200ms p95 | E3 integration-тест |
| NFR-7 | Subject lookup cache hit-ratio ≥ 95% на steady-state (1000 RPC/s, ~100 active users) | E3 load-тест с k6 |
| NFR-8 | `kacho-iam` graceful shutdown ≤ 10s | E0 manual test: `kill -TERM`, ждать `Running → Terminating → 0/1`, измерить |
| NFR-9 | Zitadel + OpenFGA + kacho-iam helm-charts применимы независимо для smoke (можно поднять только Zitadel без OpenFGA для проверки OIDC отдельно), НО на full-stack `make dev-up` есть **жёсткий bootstrap-order**: `Zitadel postgres ready → Zitadel ready → kacho-iam` (config-load в kacho-iam **fails fast**, если `KACHO_IAM_ZITADEL__ISSUER` не отвечает на `/.well-known/openid-configuration` — нельзя поднимать kacho-iam до Zitadel). Этот ordering managed by Helm: chart `kacho-iam` имеет post-install `waitfor`-hook (`helm.sh/hook: post-install,post-upgrade`) с `kubectl wait --for=condition=ready pod -l app=zitadel --timeout=300s` либо аналогом через init-container в `kacho-iam` Deployment, который пингует Zitadel-issuer и не выходит до 200 OK. То же для OpenFGA: `kacho-iam` init-container ждёт OpenFGA HTTP-ready перед startup. | E0/E2/E3 deploy-тесты (cold-start `make dev-up` на чистом cluster) + явный smoke «kacho-iam без Zitadel — fail-fast на startup с понятной ошибкой в логе» |
| NFR-10| FGA-model bootstrap идемпотентен (повторный применение не дублирует tuples / model-version) | E3 integration-тест |

---

## 9. Out of scope (Phase 2.0 — явно отложено)

| Тема | Почему отложено | Когда планируется |
|------|------------------|--------------------|
| MFA / WebAuthn / TOTP | Zitadel поддерживает as-feature, но в minimum-viable signup-flow не enforce'им — иначе UX-блокер на dev-стенде | Phase 2.1 (опционально) — `kacho-iam-mfa-policy` ENUM (`OFF` / `OPTIONAL` / `REQUIRED`) |
| External identity federation (SAML, Google, GitHub OAuth) | Zitadel поддерживает as-feature, но bootstrap + UX-конфигурация выходят за рамки signup MVP | Phase 2.1+ или on-demand (managed Zitadel включает) |
| Cross-account ресурсный sharing (cross-account binding) | На фазу 2.0 один Account = один tenant; cross-account резерв-future requires Resource Manager-style sharing-invite flow | Phase 3.0 (multi-tenant marketplace, если потребуется) |
| Audit storage (immutable log всех IAM/Operations событий) | Отдельный сервис `kacho-audit` (workspace `01-architecture-and-services.md` Phase 1 roadmap); здесь только principal в Operations — короткий хвост | Отдельная sub-phase 2.1 — `kacho-audit` |
| Quota / Billing (per-Account quota на vCPU, RAM, IP, etc.) | Отдельная phase 3.x; требует metering pipeline | Phase 3.x |
| Attribute-Based Access Control (ABAC — атрибуты в JWT-claims, policies через CEL/Rego) | Поверх REBAC отдельной фазой если потребуется (REBAC покрывает 90% use-cases) | Phase 2.2+ on-demand |
| `kacho-yc-shim` compat-слой для IAM (yc-CLI ↔ kacho-iam) | Verbatim YC-parity отложена для всего проекта (workspace `CLAUDE.md` §«Что это за проект»); shim — отдельный поздний слой | Не запланировано на 2.0 |
| Импорт users из external LDAP/AD | Federation-feature Zitadel; not enforce'им | On-demand |
| Tagged-resource-based access (`tag:env=prod ⇒ editor`) | ABAC-like, нет в REBAC; OpenFGA можно расширить через conditional relations | Phase 2.2+ on-demand |
| `Custom-role permission editor` (UI tool для конструирования custom-roles) | Custom-roles создаются через API (DoD #3), но без визуального permission-builder в UI MVP — только text-based JSON-paste | Phase 2.1 (UX-улучшение) |

---

## 10. Связь с регламентом (запреты и evgeniy)

### 10.1 Запреты workspace `CLAUDE.md`

- **#1 (acceptance gate)**: каждый из E0…E5 имеет собственный APPROVED acceptance-документ. Этот overview сам должен быть APPROVED `acceptance-reviewer` до старта per-эпиковых acceptance — это **дополнительный** gate первого уровня (overview не обходит per-эпик approves, но синхронизирует архитектурное решение между ними).
- **#4 (no cross-service cascade)**: Account.Delete / Project.Delete не каскадируется в kacho-vpc/compute/lb; вместо этого `FailedPrecondition "project has resources"` (best-effort usage-hint). Cleanup ресурсов — забота tenant'а.
- **#6 (Internal vs Public)**: `InternalSubjectService`, `InternalFGABootstrapService`, `InternalSubjectChangeNotificationService` — НЕ на external TLS. Routing разделён по use-case (см. §6.2): (a) `InternalSubjectService.Lookup` и `InternalSubjectChangeNotificationService.Watch` — **gRPC-direct** к `kacho-iam:9091` (через `kacho-api-gateway/internal/clients/iam_client.go`), вне REST mux — чтобы auth-interceptor не зацикливался через собственный REST mux; (b) admin-internal REST (`/iam/v1/internal/{users:upsertFromIdentity, fga:bootstrap, subjects:lookup}`) — через `iamInternalAddr` блок в `kacho-api-gateway/internal/restmux/mux.go` на cluster-internal listener (для admin UI / тулинга, не для interceptor'а).
- **#8 (DB-per-service)**: четыре независимые БД — `kacho_iam`, `zitadel`, `openfga`, плюс per-service БД остальных. Никаких shared-tables / cross-DB FK.
- **#10 (within-service refs — DB-уровень)**: все ссылки внутри `kacho_iam` — FK / UNIQUE / partial UNIQUE / EXCLUDE / CHECK / atomic CAS. Concurrent AccessBinding.Upsert на одну (subject, role, scope)-тройку — `UNIQUE access_bindings_subject_role_scope_uniq`. SystemRole.Delete защищён `DELETE … WHERE is_system=false`. OpenFGA-write — отдельно через outbox-pattern (другая БД, FK невозможен; consistency через transactional outbox + idempotent FGA-write worker).
- **#11 (тесты в том же PR)**: каждый PR с новым iam.v1 RPC / новой миграцией / новой permission — содержит integration-тест (testcontainers Postgres + testcontainers OpenFGA + testcontainers Zitadel где нужно) + newman-кейс через api-gateway.

### 10.2 Evgeniy-regulation

`kacho-iam` — новый сервис, пишется **с нуля по evgeniy-style**, без legacy-долга:
- §1 (структура): `cmd/kacho-iam/`, `cmd/migrator/`, `internal/apps/kacho/api/<resource>/`, `internal/repo/kacho/pg/`, `pkg/domains/kacho/`.
- §2 (UseCases > Services): каждый use-case в своём файле (`create.go`, `update.go`, `delete.go`, …) per resource — НЕ один большой `AccountService.go`.
- §3 (table-driven DTO): generic `dto.Interface[F, T]` + `RegTransfer` + `Transfer` для всех domain↔proto + domain↔pg mappings.
- §4 (self-validating domain): newtypes (`RoleID`, `SubjectID`, `Email`, `DisplayName`, `RcLabels`) + `Validate() error` через `multierr`.
- §5 (DB-level invariants): см. §10.1 запрет #10 выше.
- §6 (CQRS Repository): `RepositoryReader`/`Writer` с separated TX.
- §7 (no TimeStamps в domain, no race-prone prechecks, no magic constants).
- §8 (config YAML + viper, no envconfig).
- §9 (cmd: отдельный migrator binary, cobra, `parallel.ExecAbstract` для public+internal gRPC).
- §10 (Operations — async через corelib, principal-context preservation в worker — corelib-fix параллельно).
- §13 review-checklist применяется на каждый PR в `kacho-iam`.

---

## 11. Артефакты (что появится после закрытия эпика)

### 11.1 Acceptance documents

- `docs/specs/sub-phase-2.0-iam-overview-acceptance.md` (этот файл) — APPROVED ДО старта E0…E5.
- `docs/specs/sub-phase-2.0-iam-E0-skeleton-acceptance.md` — параллельно с overview, ждёт APPROVED.
- `docs/specs/sub-phase-2.0-iam-E1-folder-to-project-acceptance.md` — после E0.
- `docs/specs/sub-phase-2.0-iam-E2-zitadel-oidc-acceptance.md` — после E0.
- `docs/specs/sub-phase-2.0-iam-E3-openfga-rebac-acceptance.md` — после E2.
- `docs/specs/sub-phase-2.0-iam-E4-signup-ui-principal-acceptance.md` — после E3.
- `docs/specs/sub-phase-2.0-iam-E5-deprecate-rm-acceptance.md` — после E1 + E4.

### 11.2 Репозитории и git-ветки

- **Новый репо** `github.com/PRO-Robotech/kacho-iam` (создаётся в E0).
- Ветки `KAC-105`…`KAC-110` в репозиториях по затронутости (см. §3.2). Эпик-ветка `KAC-104` в `kacho-workspace` для doc-обновлений.

### 11.3 Vault entries (`obsidian/kacho/`)

После каждого sub-эпика обновляется:
- `KAC/KAC-104.md` (epic), `KAC/KAC-105.md`…`KAC/KAC-110.md`.
- `resources/iam-account.md`, `resources/iam-project.md`, `resources/iam-user.md`, `resources/iam-service-account.md`, `resources/iam-group.md`, `resources/iam-role.md`, `resources/iam-access-binding.md`.
- `rpc/iam-account-service.md`, `rpc/iam-project-service.md`, `rpc/iam-user-service.md`, `rpc/iam-service-account-service.md`, `rpc/iam-group-service.md`, `rpc/iam-role-service.md`, `rpc/iam-access-binding-service.md`, `rpc/iam-internal-subject-service.md`.
- `packages/iam-internal-apps-kacho-api-*.md`, `packages/iam-internal-repo-kacho-pg.md`, `packages/iam-internal-clients-zitadel.md`, `packages/iam-internal-clients-openfga.md`.
- `edges/api-gateway-to-iam-subject-lookup.md`, `edges/api-gateway-to-zitadel-jwks.md`, `edges/api-gateway-to-openfga-check.md`, `edges/iam-to-zitadel-management.md`, `edges/iam-to-openfga-write.md`, `edges/vpc-to-iam-project-validate.md`, `edges/compute-to-iam-project-validate.md`, `edges/loadbalancer-to-iam-project-validate.md`.
- `architecture.md` — обновление с новым IAM-слоем.

### 11.4 Deployment

- `kacho-deploy/helm/umbrella/charts/kacho-iam/`
- `kacho-deploy/helm/umbrella/charts/zitadel/`
- `kacho-deploy/helm/umbrella/charts/openfga/`
- `kacho-deploy/helm/umbrella/charts/kacho-iam-postgres/`
- `kacho-deploy/helm/umbrella/charts/zitadel-postgres/`
- `kacho-deploy/helm/umbrella/charts/openfga-postgres/`
- `kacho-deploy/Makefile` — добавлены `make psql SVC=iam`, `make reload-svc SVC=iam`, `make logs-svc SVC=iam`.

### 11.5 Proto

- `kacho-proto/proto/kacho/cloud/iam/v1/` — новый package с 8+ файлами (см. §6.1).
- `kacho-proto/proto/kacho/cloud/access/access.proto` — мигрирует в `kacho.cloud.iam.v1.access_binding`, оригинальный access.proto deprecated (если не используется elsewhere) / удаляется в E5.

---

## 12. Definition of Done — чек-лист до закрытия эпика KAC-104

Перед переводом KAC-104 в `Done` в YouTrack — все пункты ниже отмечены:

### Functional
- [ ] **E0 APPROVED + merged**: `sub-phase-2.0-iam-E0-skeleton-acceptance.md` APPROVED; `kacho-iam` репо существует, скелет CRUD работает (E0.GWT-01, E0.GWT-02 зелёные через newman).
- [ ] **E1 APPROVED + merged**: folder_id → project_id миграция в kacho-vpc/compute/loadbalancer (data + handlers + clients + tests); все existing newman-кейсы проходят с `project_id` вместо `folder_id`.
- [ ] **E2 APPROVED + merged**: Zitadel deploy, auth-interceptor работает (E2 sub-acceptance-сценарии зелёные); JWT-validation метрика p95 ≤ 5ms (NFR-1).
- [ ] **E3 APPROVED + merged**: OpenFGA deploy, REBAC-model bootstrap'ится, Check-interceptor enforces permissions (E3.GWT-01, E3.GWT-02 зелёные); Check p95 ≤ 20ms (NFR-2).
- [ ] **E4 APPROVED + merged**: signup-flow работает (E4.GWT-01, E4.GWT-02); UI IAM-блок виден и функционален (E4.GWT-03..06); Operations.principal заполняется реально (E4.GWT-07, E4.GWT-08).
- [ ] **E5 APPROVED + merged**: `kacho-resource-manager` удалён из `kacho-deploy/helm/umbrella`; REST `/resource-manager/v1/*` отвечает `Gone 410`; данные `organizations`+`clouds` → `accounts`, `folders` → `projects` (data-migration validated).

### Non-functional
- [ ] NFR-1..NFR-10 — каждая зелёная (load/integration тесты).
- [ ] Все integration-тесты на каждом из 6 sub-эпиков зелёные в CI (testcontainers Postgres + OpenFGA + Zitadel где нужно).
- [ ] Все newman-кейсы через api-gateway зелёные (включая negative auth/authz).
- [ ] `make dev-up` поднимает full stack за ≤ 8 минут (включая Zitadel + OpenFGA + kacho-iam).

### Documentation / artefacts
- [ ] Все 6 per-эпиковых acceptance-документов в статусе APPROVED.
- [ ] Vault обновлён (см. §11.3): KAC-104..KAC-110 entries, resources/iam-*, rpc/iam-*, edges/*, architecture.md.
- [ ] Workspace `CLAUDE.md` — обновлена таблица сервисов (`kacho-iam` добавлен; `kacho-resource-manager` помечен как retired); §«Кросс-репо зависимости» — runtime-edge `kacho-{vpc,compute,loadbalancer} → kacho-iam` (`ProjectService.Get`), `kacho-api-gateway → kacho-iam/zitadel/openfga`.
- [ ] `docs/specs/01-architecture-and-services.md` — обновлён.
- [ ] `docs/specs/04-roadmap-and-phasing.md` — фаза 2.0 переведена из «planned» в «done».
- [ ] CHANGELOG в `docs/specs/CHANGELOG.md` — запись о KAC-104.

### YouTrack hygiene
- [ ] KAC-104 в `Done` со всеми артефактами в комментарии (ссылки на 6 PR per-эпиковых).
- [ ] KAC-105…KAC-110 — все в `Done`.
- [ ] Все ветки `KAC-104`..`KAC-110` в каждом затронутом репо удалены после merge (workspace `CLAUDE.md` §«git-флоу»).

### Architectural sanity
- [ ] Никаких `Internal*` методов `kacho-iam` на external TLS endpoint (запрет #6).
- [ ] Никаких cross-DB FK (запрет #8).
- [ ] Никаких software-side TOCTOU refchecks в `kacho-iam` (запрет #10) — все within-service refs на DB-level.
- [ ] Каждый PR с iam.v1 RPC имеет integration-тест + newman-кейс в том же PR (запрет #11).
- [ ] `kacho-iam` соответствует evgeniy-checklist §13 на финальном review.

---

**END of overview-acceptance document.**

---

## Changelog

### v2 — 2026-05-17 (применены правки blockers 1-4 + 3 nit'а per acceptance-review от `acceptance-reviewer` 2026-05-17)

**Blockers (нормативные исправления):**

- **B1 — REBAC DSL (§4):** удалены типы `iam_role` и `iam_access_binding` из FGA-модели. Причина: (a) `Role.account_id IS NULL` для system-roles → tuple `role:<id> account account:<NULL>` не строится; (b) AccessBinding имеет scope account/project/resource → единый relation `scope_account: [account]` ошибочно исключал project- и resource-scoped binding'и. Role и AccessBinding теперь — данные в `kacho_iam.roles`/`access_bindings`, FGA получает только **expanded permission-tuples** на момент `AccessBindingService.Upsert`. Добавлены: §4.0 («Role и AccessBinding — НЕ FGA-объекты»), переписана §4.1 («AccessBinding ↔ tuple lifecycle» с пошаговым описанием транзакционного outbox-flow), обновлена таблица §4.2 (IAM admin-actions → object = родительский Account/Project/Resource, а не отдельный `iam_*`-тип). В §5 (Decision Log) добавлена строка #13.
- **B2 — InternalSubjectService routing (§2.1, §6.2, §10.1):** разделён routing двух категорий internal-RPC. `InternalSubjectService.Lookup` + `InternalSubjectChangeNotificationService.Watch` (вызываются auth-interceptor'ом api-gateway) — **gRPC-direct** к `kacho-iam:9091` через `kacho-api-gateway/internal/clients/iam_client.go`, **НЕ** регистрируются в REST mux (иначе loop interceptor → REST → interceptor → REST → ...). Admin-internal REST (`/iam/v1/internal/{users:upsertFromIdentity, fga:bootstrap, subjects:lookup}` — для admin UI / тулинга) остаётся через `iamInternalAddr` блок в REST mux на cluster-internal listener. В ASCII-диаграмме §2.1 явно прописано «via DIRECT gRPC к kacho-iam:9091, НЕ через свой REST mux».
- **B3 — E3.GWT-03 restart-resistance (§7.5, §1 DoD-таблица):** добавлен новый сценарий E3.GWT-03: «Restart api-gateway во время revoke ничего не теряет — новый pod не имеет stale-cache, DENY enforced сразу». Включает шаги `kubectl rollout restart deployment/kacho-api-gateway` + assertion что новый pod возвращает `PermissionDenied` без grace-period на прогрев. Закрывает явный пробел в DoD #5 «без перезапуска». В §1 DoD-таблице пункт 5 расширен ссылкой на GWT-03.
- **B4 — Cross-service edges phase shift (§6.3):** добавлена таблица «когда появляется / когда исчезает» edge с явной разметкой по sub-эпикам (E0 = stub без consumer'ов; E1 = peer-сервисы переключают валидацию `folder_id → project_id` на `kacho-iam.ProjectService.Get`; E2 = api-gateway → kacho-iam.SubjectLookup + Zitadel JWKS; E3 = api-gateway → OpenFGA + Notify-канал; E5 = удаление всех `* → kacho-resource-manager` edges). До E1 peer-сервисы продолжают звать `kacho-resource-manager.FolderService.Get`.

**Nits (косметика, но применено):**

- **N1 (§0):** добавлена детализация — какие именно messages из старого `kacho.cloud.access.access.proto` мигрируют в `kacho.cloud.iam.v1` (`Subject`, `AccessBinding`, `AccessPolicy`, `BindAccessPolicy*`, `UnbindAccessPolicy*`, `UpdateAccessPolicyBindingParameters*`, `SetAccessBindings*`, `UpdateAccessBindings*`, `AccessBindingDelta`, `AccessBindingsOperationResult`, list-RPC requests/responses); messages-only proto (без `service`-блока); deprecated на каждый message в E0 + удаление в E5; runtime-зависимостей от `kacho.cloud.access.*` в handlers нет.
- **N2 (§8 NFR-9):** добавлено пояснение, что bootstrap-order Zitadel → kacho-iam **НЕ** обходится «independent helm-charts». `kacho-iam` config-load **fails-fast**, если `KACHO_IAM_ZITADEL__ISSUER` недоступен; ordering managed через Helm post-install hook (`kubectl wait`) или init-container в Deployment, пингующий issuer/OpenFGA HTTP-ready endpoint.
- **N3 (§7.1 GWT-01):** добавлено явное Given «seed-миграция `0003_seed_default_account.sql` применена» (`acc_default` + `prj_default` + default-roles в `kacho_iam.roles`) — иначе «first user → default-admin binding» нечем выдавать.

**Header (метаданные):**

- Версия документа: `DRAFT v1` → `DRAFT v2`.
- Статус: «Draft — ждёт review» → «Draft — ждёт повторного review».

**Не тронуто (как было в v1):** §3 (декомпозиция E0…E5), §11 (артефакты), §12 (DoD чек-лист), §«Открытые ridges» (Open Questions для повторного review). Содержательных изменений в этих разделах нет.

---

Открытые ridges (для acceptance-reviewer'а — что может потребовать уточнения):
1. **Account-wide bindings vs Project-only**: фиксировано «Account-wide допустимы на 2.0» (§5 #12), но если reviewer считает, что это лишнее усложнение для MVP, можно сузить до Project-only + special-cased default-admin через config-flag.
2. **Subject-cache TTL = 30s vs более короткий**: 30s выбраны как баланс между OIDC-validation cost и invalidate-latency. Reviewer может посчитать, что 60s или 10s лучше под NFR-7 / NFR-5.
3. **Default-roles per-resource-type granularity**: DoD #3 говорит «per-module + per-resource type». Сейчас в §2.3 перечислены оба уровня. Можно ограничить только per-module на MVP (8 ролей), per-resource — позже.
4. **OpenFGA `Check` consistency-mode**: фиксирован `MINIMIZE_LATENCY`. Если reviewer хочет strong-consistency для critical operations (например DELETE) — нужен flag в RPC permissions table (§4.2).
5. **Migration strategy in E5**: «single-shot SQL» (§0) — но если кому-то нужна возможность rollback'а на kacho-resource-manager, нужен plan для coexistance mode (отвергнут в §5 #11 — но reviewer может вернуться к этому).
6. **`kacho-yc-shim` для IAM** — out of scope (§9). Если будет требование от заказчика на yc-CLI совместимость, эпик потребует sub-phase 2.0b.
7. **Custom-role permission DSL**: фиксировано «JSON-paste в UI MVP, без visual builder» — reviewer может потребовать минимальный builder уже в 2.0 (тогда задача расширяется).
