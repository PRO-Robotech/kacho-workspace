# Sub-phase 2.0 — IAM E4: signup-flow + UI IAM-блок + Operation.principal — Acceptance

> **Status**: APPROVED v2 — UI-block-only (E0-compatible)
> **Date**: 2026-05-17
> **YouTrack**: [KAC-109](https://prorobotech.youtrack.cloud/issue/KAC-109) — child of epic [KAC-104](https://prorobotech.youtrack.cloud/issue/KAC-104)
>
> **v2 scope adjustment (2026-05-17)** — addressing reviewer blockers:
>
> **Blocker B-1 (Zitadel/OpenFGA not deployed on e2c825)**: текущий стенд e2c825 разворачивает только E0 IAM CRUD; `zitadel`, `openfga`, `pg-zitadel`, `pg-openfga` отключены в overrides (см. `kacho-deploy/clusters/e2c825/overrides.yaml`). Signup-flow (`/signup`, `/login`, OIDC-callback, `InternalAuthService.SignupComplete`) — **отложен до merge KAC-107 (E2) + KAC-108 (E3)**; в данном PR (KAC-109) реализуется **только UI-block** (CRUD-страницы 7 IAM-ресурсов + sidebar + Operations principal column). DoD #1 (signup-flow) — переносится в follow-up KAC-tickets под E2/E3 (этот PR закрывает DoD #2, #3, #4, #7).
>
> **Blocker B-2 (RTK Query mismatch)**: проект `kacho-ui` использует **`@tanstack/react-query`** (см. `kacho-ui/CLAUDE.md` §1), не Redux Toolkit Query. v2 заменяет упоминания «RTK Query» на «@tanstack/react-query polling + queryClient.invalidateQueries». Реактивность (D-5) реализуется через `useQuery({refetchInterval})` + `invalidateQueries(["iam", "<resource>"])` на mutation success — функционально эквивалентно RTK tag-based invalidation.
>
> **Blocker B-3 (no auth → no /signup landing)**: на E0 api-gateway допускает анонимный доступ (`createdBy: "anonymous"` в Operation, `principalType/Id/DisplayName` пустые). UI шлёт запросы без Bearer. `Login`/`Signup` страницы — placeholder-stub (информационный экран «Auth-flow доступен после деплоя Zitadel/OpenFGA») в этой итерации; реальные OIDC-страницы — KAC-107/KAC-108.
>
> **Blocker B-4 (acceptance не описывает работу без default account)**: на e2c825 нет seed-Account `acc_default` (E0 миграция `0003_seed_default_account.sql` не применена). UI должен корректно работать с пустым списком Account — `AccountsListPage` шапка-CTA «Создать Account» доступна сразу; child-resource pages (Projects/SAs/Groups) показывают «Выберите Account» empty-state до выбора. Users — отдельный leaf-list независимо от Account.
>
> Остальные пункты v1 (Decision Log, 25 GWT, DoD, Cross-repo PR chain) сохраняются без изменений; что относится к UI-block-only — выполняется в KAC-109; signup-flow — переносится.
> **Parent overview**: [[sub-phase-2.0-iam-overview-acceptance]]
> **Blocked by**:
> - [KAC-105 (E0)](https://prorobotech.youtrack.cloud/issue/KAC-105) merged — IAM 7 ресурсов CRUD доступны на backend.
> - [KAC-107 (E2)](https://prorobotech.youtrack.cloud/issue/KAC-107) merged — Zitadel OIDC, auth-interceptor, Principal в ctx, lazy-mirror `UpsertFromIdentity`.
> - [KAC-108 (E3)](https://prorobotech.youtrack.cloud/issue/KAC-108) merged — OpenFGA REBAC + Check-interceptor + реактивность ≤10s.
> **Blocks**: [KAC-110 (E5)](https://prorobotech.youtrack.cloud/issue/KAC-110) — RM нельзя выключать, пока UI не предоставил замены для управления Account/Project через IAM-блок.
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer`

---

## 0. Преамбула — что эта sub-итерация

Это **полноразмерный acceptance** заключительного sub-эпика **E4**, открытого после APPROVED + merged E0 + E2 + E3. E4 — финальный гейт, закрывающий DoD #1, #2, #3, #4 эпика KAC-104 (DoD #5 закрыт в E3, DoD #6 — в E0).

E4 поставляет:

1. **Public signup-flow** — landing-page `/signup` в `kacho-ui` → редирект на Zitadel signup → OIDC-callback на `kacho-api-gateway` (`/iam/v1/auth/callback` — handler уже введён в E2) → `kacho-iam.InternalAuthService.SignupComplete` (новый RPC на E4) → атомарный bootstrap нового User + (если нужно) новый Account + default Project + owner-binding'и + FGA-tuples → cookie-session установлена → редирект на UI `/` залогиненного пользователя.
2. **UI IAM-блок** в side-nav `kacho-ui` — раздел «Identity and Access Management» наравне с VPC / Compute / NLB; child-pages: `Accounts`, `Projects`, `Users`, `Service Accounts`, `Groups`, `Roles`, `Access Bindings`.
3. **Полный CRUD per resource** через UI: list-view (table + pagination + filter), detail-view, create-form, edit-form, delete-confirm — для каждого из 7 IAM ресурсов; UI вызывает E0 IAM RPCs через api-gateway (`/iam/v1/*`).
4. **AccessBinding UI** — управляемый dropdown-flow: Subject (User/SA/Group) → Role (system + custom) → Resource scope (Account/Project/конкретный resource); revoke одним кликом; bulk-actions для admin.
5. **Custom-role builder (MVP)** — text-area JSON-paste для `permissions[]` массива (визуальный builder — Phase 2.1).
6. **Реактивность UI** — после `Upsert/Delete` AccessBinding → UI invalidate'ит RTK Query кеш по тегу `AccessBinding` + связанные ресурсные теги; пользователь в группе через ≤10s видит вновь grant'ned ресурс в своих list-views (end-to-end DoD #5 через UI surface).
7. **Operations principal UI** — Operations table показывает column «Created by» с иконкой типа subject (USER / SERVICE_ACCOUNT) и читаемым display_name; источник — `operations.principal_*` колонки уже заполняются с E2.
8. **Permission-aware UI heuristic** — UI скрывает / disable'ит Create/Edit/Delete-кнопки, если у текущего subject'а нет соответствующего permission; источник — один `iam.AccessBindingService.ListBySubject(me)` на page-load.
9. **Concurrent signup race-safety** — два signup'а одной OIDC `external_id` одновременно — ровно один winner (atomic CAS на UNIQUE `users.external_id`); второй получает existing mirror (overview-уровень GWT-02).

После E4 платформа функционально-полная по AAA: signup → auto-bootstrap → CRUD IAM из UI → реактивные права → principal trail во всех Operation. Остаётся только убрать legacy `kacho-resource-manager` (E5).

**E4 НЕ включает** (явные out-of-scope, §9):
- MFA / WebAuthn — Zitadel feature, Phase 2.1.
- External invite via email — Phase 2.1.
- Cross-Account sharing — Phase 3.0.
- Quota / billing UI — Phase 3.x.
- Audit log UI — отдельный `kacho-audit` сервис.
- Visual permission-builder для custom-roles — Phase 2.1.
- PAT-токены для users — Phase 2.1+.
- Account-switcher (multi-Account) — Phase 3.0; на 2.0 один Account.

---

## 1. Связь с регламентом и запретами (нормативно)

| # | Запрет / правило (workspace `CLAUDE.md`) | Применение в E4 |
|---|------------------------------------------|-----------------|
| 1 | НЕ начинать кодинг до APPROVED acceptance | Этот документ + reviewer cycle → APPROVED → `superpowers:writing-plans` → integration-tester → rpc-implementer + UI scaffold |
| 2 | НЕ упоминать `yandex` | Все error-text'ы / переменные / комментарии — `kacho.cloud.*` / `KACHO_*`; UI labels — Kachō branding |
| 3 | НЕ использовать ORM | `kacho-iam` использует sqlc + pgx (продолжение E0); UI api-client — типизированные fetch wrappers (`src/api/client.ts`), не ORM |
| 4 | НЕ каскадно удалять через границу сервиса | Account.Delete / Project.Delete возвращают `FailedPrecondition` если есть owned-resources в peer-сервисах (см. §4.3); UI отрисовывает удобный error «Project has 3 VPC Networks, please delete first» |
| 5 | НЕ редактировать применённую миграцию | Новые миграции: `kacho-iam/migrations/0008_signup_bootstrap_lock.sql` (advisory-lock для first-user race); `kacho-iam/migrations/0009_users_external_id_unique.sql` если E0 ещё не создал UNIQUE (overview §6.1: должен быть, но E4 проверяет идемпотентно) |
| 6 | `Internal.*` не на external endpoint | `InternalAuthService.SignupComplete` — port 9091, gRPC-direct от api-gateway; **НЕ** регистрируется в restmux; rationale — same loop-prevention как `InternalSubjectService.Lookup` в E2 §3.3 |
| 7 | НЕ broker (Kafka/NATS) до in-process | UI реактивность через RTK Query invalidation + backend NOTIFY (E3); никакого broker'а в E4 |
| 8 | НЕ cross-DB FK | UI читает `users` mirror из `kacho_iam`; Zitadel users (external) — отдельная БД, link только по `external_id` строковому |
| 9 | НЕ sync возврат ресурса из мутаций | `InternalAuthService.SignupComplete` возвращает `Operation` (corelib pattern); UI поллит `operations.Get(id)` до `done=true`; signup-flow на UI ждёт максимум 10s (NFR-3) |
| 10 | НЕ software refcheck для within-service инвариантов | First-user race-safety — атомарный CAS на `accounts.owner_user_id IS NULL` (§4.2) ПЛЮС UNIQUE `users.external_id`; group-member dedup — UNIQUE `(group_id, subject_id, subject_type)` (из E0) |
| 11 | НЕ мёрджить новый RPC / новое поле / новый ресурс без тестов в том же PR | Каждый PR (kacho-proto / kacho-iam / kacho-api-gateway / kacho-ui / kacho-deploy / kacho-workspace) обязан содержать integration + newman + UI-test для добавляемого функционала; explicit чек-лист в §6 DoD |

**Связь с evgeniy** (skill `evgeniy`):
- §2 use-case pattern — `internal/apps/kacho/api/auth/signup_complete.go` (использует UseCase, не fat-service); `internal/apps/kacho/api/access_binding/list_by_subject.go` (новый use-case для permission heuristic в UI).
- §4 self-validating domain — `Email`, `ExternalID` newtypes с `Validate()` остаются из E0; добавляется `domain/principal_view.go` для UI-friendly serialization.
- §5 DB-level invariants — `users_external_id_uniq` UNIQUE (E0; re-affirm в E4); `accounts_owner_user_id_idx` partial index `WHERE owner_user_id IS NOT NULL`.
- §6 CQRS Reader/Writer — `auth_writer.go` (signup transaction) vs `auth_reader.go` (find existing user).
- §16 outbox + LISTEN/NOTIFY — UI dependent: backend NOTIFY (E3) → api-gateway invalidate cache → UI request получает уже-обновлённые permissions.

---

## 2. Decision Log (зафиксированные решения этого sub-эпика)

| ID  | Decision                                                                                                                            | Rationale                                                                                                                                                       | Alternatives rejected                                                                                                                                              |
|-----|--------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| D-1 | **Signup OIDC через Zitadel** (no email/password в kacho-iam напрямую)                                                              | Zitadel — выбран в E2 как единый IdP; повторное хранение паролей в kacho-iam = удвоение secrets-surface, синхронизационный долг                              | (a) Email/password в kacho-iam — utility-плохо; (b) federated-only (без своего signup-form) — теряем control над UX                                                |
| D-2 | **Account + Project + owner-binding atomic в одном Operation** (не три отдельных)                                                  | Atomic bootstrap: failure на любом шаге → rollback всего; user видит либо «success + access» либо «error retry» без частичного состояния                       | (a) Три separate Operations — частичный success при failure (User создан, Project нет → orphan user без projects); (b) saga с compensation — overkill для bootstrap |
| D-3 | **Custom role permissions UI = JSON-paste textarea на E4 MVP**; visual builder — Phase 2.1                                          | Визуальный builder требует UI/UX design + permission matrix component — отдельный sub-phase; JSON-paste достаточен для admin'ов (которые понимают модель)      | (a) Visual builder MVP — раздувание scope E4 (≈+2 недели UI работы); (b) text-only без validation — слишком rough                                                  |
| D-4 | **Sidebar visibility check = frontend через `iam.AccessBindingService.ListBySubject(me)`** на page-load (cached в session-storage 5min) | UI heuristic — backend остаётся source of truth (PermissionDenied всё равно вернётся при попытке); 1 запрос per session, не N+1                                | (a) Check per UI-button — N+1 round-trip; (b) JWT-embedded permissions claim — out-of-date после revoke (revoke не aware к JWT TTL)                                |
| D-5 | **Реактивность = RTK Query invalidate tags + backend NOTIFY (E3)**                                                                  | RTK Query — стандарт для современных React SPA; tag-based invalidation работает out-of-box; backend NOTIFY уже из E3 (нет нового кода в backend для UI)        | (a) WebSocket push в UI — выкинут с Phase 1.0 (workspace CLAUDE.md §«API contract»); (b) Polling 5s — load + UX delay; (c) SSE — лишний transport в gateway        |
| D-6 | **Concurrent signup race = atomic UNIQUE external_id + atomic CAS on accounts.owner_user_id**                                       | DB-level invariant (запрет #10); explicit (not optimistic-UI-only) гарантирует exactly-one-winner; second-comer получает existing mirror, не fail                | (a) Optimistic UI race-handling — расходится с #10; (b) Mutex на handler — single-pod-only, не distributed; (c) Application-level lock — TOCTOU                  |
| D-7 | **Default Account + Default Project существуют с E0** (seed-миграция `0003_seed_default_account.sql`); E4 НЕ создаёт **новые** account'ы для новых signup'ов | На фазу 2.0 — один Account = один tenant (overview §0 «one Account = one tenant»); все signup-up users присоединяются к `acc_default`; first-user становится owner | (a) Создать новый Account per-signup — multi-tenant из коробки, нарушает overview §0; (b) Manual provisioning per signup — admin overhead, плохо для public signup |
| D-8 | **First user → owner-binding на `acc_default` + `prj_default`; subsequent users → no binding (admin grants manually)**                | Bootstrap-only: пока нет первого user'а, **нечем** управлять; first-user становится «root admin»; последующие — стандартный invite-flow (admin даёт binding) | (a) All signups = admin — security hole (любой случайный signup получает full access); (b) All signups = viewer-default — UX broken для bootstrap (first user без admin не может никого invite) |
| D-9 | **Signup-form UI minimal — only email + Zitadel handles password/MFA**; никаких extra fields в kacho-iam-form                       | Zitadel signup-flow уже rich (email validation, password complexity, MFA-prompt если enabled); duplicate form в kacho-ui = двойной UX/translation maintenance | (a) Полный signup-form в kacho-ui — дублирует Zitadel; (b) только редирект на Zitadel без своего `/signup` landing — теряем branding control                       |
| D-10 | **Cookie-session для UI (D5 из E2) — продолжается, никаких изменений в E4**                                                        | Cookie-session уже работает с E2; UI читает email/display_name через `/iam/v1/auth/me` (новый GET endpoint в E4)                                              | (a) Перевод на Bearer-only — ломает existing UI sessions; (b) WebStorage — XSS risk                                                                                |
| D-11 | **Operations principal UI = column «Created by» + filter `?principal.id=me`**                                                       | UI «My operations» tab — частый use-case; backend filter `WHERE principal_id = $1` (E4 добавляет в OperationsService.List); column в table — стандартный      | (a) Только column без filter — UI делает client-side filtering, не масштабируется; (b) Отдельная страница «My operations» — лишний nav                          |
| D-12 | **e2e UI testing infrastructure = Playwright + headless Chromium в `kacho-test`**                                                  | Playwright — стандарт de-facto для modern SPA e2e; first-class TypeScript support; параллельный run; интеграция с trace-viewer для debug                       | (a) Cypress — single-tab, slower; (b) Puppeteer — meta-library без test runner; (c) Только Newman API tests без UI — DoD #1/#2/#3 не покрывается                  |
| D-13 | **Permission-heuristic in UI fails-open на error**: если `ListBySubject` returns error (e.g. iam-down) → UI assumes admin-default, не показывает stale `disabled` | UX-priority: не блокировать UI на iam-down; user всё равно получит PermissionDenied на real request если нет прав. Альтернатива (fail-closed) превращает iam-down в полный UI-blackout | (a) Fail-closed (всё disabled на iam-error) — UX-broken на transient iam-down; (b) Block UI до retry — пользователь не понимает что происходит                     |
| D-14 | **Custom-role permissions validation — strict reject на E4** (`InvalidArgument` если permission не в supported-list)                  | Self-validating domain (evgeniy §4); permission-list whitelisted, иначе FGA-tuple writer не знает как раскладывать; permissive accept = silent failure       | (a) Permissive — silent failure при granty (создан role, но не работает permissions); (b) Skip unsupported с warning — UI должен показывать warning, complexity   |
| D-15 | **«Created by» в Operations показывает иконку типа subject** (Lucide-icon `User` или `Bot` для SA; `Settings` для system)         | Visual differentiation (3 типа) — UX-clarity; icons из существующего Lucide-set, без extra assets                                                              | (a) Только text — accessibility OK, но визуально однообразно; (b) Custom icons — extra asset maintenance                                                          |

---

## 3. Target architecture (компактно)

### 3.1 Signup-flow graph (новое на E4)

```
                  ┌────────────────────────────────────┐
                  │  Browser (user opens /signup)      │
                  └─────────────────┬──────────────────┘
                                    │ HTTPS GET /signup
                                    ▼
                  ┌────────────────────────────────────┐
                  │ kacho-ui SPA  (Vite served via     │
                  │ kacho-api-gateway static-mux)      │
                  │   /signup page renders:            │
                  │   - Kachō logo + "Sign up" CTA     │
                  │   - "Already have account? Log in" │
                  └─────────────────┬──────────────────┘
                                    │ user clicks "Sign up with Zitadel"
                                    │ window.location = Zitadel /signup
                                    │   ?client_id=kacho-ui
                                    │   &redirect_uri=/iam/v1/auth/callback
                                    │   &response_type=code
                                    │   &scope=openid+email+profile
                                    ▼
                  ┌────────────────────────────────────┐
                  │   Zitadel (signup-form)            │
                  │   email + password (+ MFA if cfg)  │
                  └─────────────────┬──────────────────┘
                                    │ POST callback w/ code
                                    ▼
                  ┌────────────────────────────────────┐
                  │ kacho-api-gateway                  │
                  │   /iam/v1/auth/callback (E2)       │
                  │   - exchange code → access_token   │
                  │   - call iam:9091                  │
                  │     InternalAuthService.SignupComplete │  (NEW in E4)
                  └─────────────────┬──────────────────┘
                                    │ gRPC direct
                                    ▼
                  ┌────────────────────────────────────┐
                  │ kacho-iam                          │
                  │   InternalAuthService.SignupComplete   │
                  │   {external_id, email, display_name}   │
                  │                                    │
                  │   TX:                              │
                  │   1) UPSERT users (race-safe via   │
                  │      ON CONFLICT external_id)      │
                  │   2) IF first-user CAS on          │
                  │      accounts.owner_user_id IS NULL│
                  │      AND id='acc_default':         │
                  │      - UPDATE accounts SET owner_user_id=$usr_id  │
                  │      - INSERT access_bindings (owner role, acc)   │
                  │      - INSERT access_bindings (admin role, prj)   │
                  │      - INSERT outbox (FGA-write tuples)           │
                  │      - INSERT subject_change_outbox               │
                  │   3) RETURN Operation{ done=true,                 │
                  │      response: SignupResult{user_id, account_id,  │
                  │              project_id, is_first_user} }         │
                  └─────────────────┬──────────────────┘
                                    │ Operation done=true
                                    │ (sync from gateway's POV — bootstrap fast <500ms)
                                    ▼
                  ┌────────────────────────────────────┐
                  │ kacho-api-gateway (continued)      │
                  │   - Set-Cookie: kacho_session=...  │
                  │   - 302 Redirect: UI /             │
                  └─────────────────┬──────────────────┘
                                    │
                                    ▼
                  ┌────────────────────────────────────┐
                  │ kacho-ui SPA loads / page          │
                  │   - GET /iam/v1/auth/me            │
                  │   - GET /iam/v1/accessBindings     │
                  │     ?subject.id=usr_new            │
                  │   - render: email in header,       │
                  │     IAM sidebar visible (admin)    │
                  └────────────────────────────────────┘
```

### 3.2 UI structure (новое на E4)

```
kacho-ui/src/
├── pages/
│   ├── (existing)/
│   │   ├── DashboardPage.tsx
│   │   ├── ...VPC/Compute pages
│   ├── auth/
│   │   ├── SignupPage.tsx         (NEW) — landing /signup
│   │   ├── LoginPage.tsx          (NEW) — landing /login (same flow без is-first-user logic)
│   │   ├── CallbackPage.tsx       (NEW) — handles ?code= from Zitadel (or backend returns 302 directly — see D-10)
│   │   └── LogoutPage.tsx         (NEW) — clears cookie, redirects to Zitadel logout
│   └── iam/                       (NEW)
│       ├── AccountsListPage.tsx
│       ├── AccountDetailPage.tsx
│       ├── ProjectsListPage.tsx
│       ├── ProjectDetailPage.tsx
│       ├── ProjectCreatePage.tsx
│       ├── UsersListPage.tsx
│       ├── UserDetailPage.tsx
│       ├── ServiceAccountsListPage.tsx
│       ├── ServiceAccountDetailPage.tsx
│       ├── ServiceAccountCreatePage.tsx
│       ├── GroupsListPage.tsx
│       ├── GroupDetailPage.tsx
│       ├── GroupCreatePage.tsx
│       ├── GroupMembersPanel.tsx       (subcomponent — add/remove members)
│       ├── RolesListPage.tsx
│       ├── RoleDetailPage.tsx
│       ├── RoleCreatePage.tsx          (JSON-paste permissions textarea — D-3)
│       ├── AccessBindingsListPage.tsx
│       ├── AccessBindingCreateDialog.tsx
│       └── AccessBindingDetailPage.tsx
├── components/
│   ├── (existing)/
│   ├── auth/
│   │   ├── UserMenu.tsx           (NEW) — header dropdown: email, "My account", "Logout"
│   │   ├── PermissionGate.tsx     (NEW) — wraps children; hides if subject lacks permission (D-4, D-13)
│   │   └── SignupErrorBanner.tsx  (NEW) — Zitadel error display (e.g. "email already registered")
│   └── iam/
│       ├── SubjectPicker.tsx      (NEW) — autocomplete (User/SA/Group) для binding creation
│       ├── RolePicker.tsx         (NEW) — autocomplete (system + custom roles)
│       ├── ScopePicker.tsx        (NEW) — Account/Project/Resource picker
│       ├── AccessBindingTable.tsx (NEW) — list-view with filter by subject/role/scope
│       └── CreatedByCell.tsx      (NEW) — render principal (icon + display_name)
├── api/
│   ├── (existing)/
│   ├── iam/
│   │   ├── auth.ts               (NEW) — /auth/me, /auth/logout endpoints
│   │   ├── accounts.ts           (NEW) — RTK Query slice
│   │   ├── projects.ts
│   │   ├── users.ts
│   │   ├── serviceAccounts.ts
│   │   ├── groups.ts
│   │   ├── roles.ts
│   │   └── accessBindings.ts
│   └── permissions.ts            (NEW) — wraps ListBySubject(me), cached в session
└── hooks/
    └── usePermissionCheck.ts     (NEW) — hook: usePermissionCheck("iam.users", "viewer") → bool
```

### 3.3 Что добавляется в каждый репо

| Repo                 | Что добавляется                                                                                                                                                            |
|----------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `kacho-proto`        | `kacho.cloud.iam.v1.internal_auth_service.proto`: `rpc SignupComplete(SignupCompleteRequest) returns (operation.Operation)`; request `{external_id, email, display_name}`; response (через Operation.Any) `{user_id, account_id, project_id, is_first_user bool}`. `kacho.cloud.iam.v1.auth_service.proto`: `rpc Me(MeRequest) returns (MeResponse)` — публичный, для UI «who am I»; response `{principal: Principal, effective_account_id, effective_project_ids}`. Расширение `operations_service.proto`: filter `?principal.id=<id>` (request field `principal_filter`) |
| `kacho-corelib`      | НЕ меняется в E4 (operations.Principal уже из E2; UI не импортирует corelib)                                                                                              |
| `kacho-iam`          | `internal/apps/kacho/api/auth/signup_complete.go` (use-case: atomic bootstrap); `internal/apps/kacho/api/auth/me.go` (use-case: return Principal + denormalized effective scope); `internal/apps/kacho/api/access_binding/list_by_subject.go` (new use-case для UI permission heuristic); `internal/repo/kacho/pg/auth_writer.go` (TX bootstrap method); миграция `0008_signup_bootstrap_lock.sql` (advisory-lock для first-user CAS, см. §4.2); миграция `0009_operations_principal_filter_idx.sql` (index для filter `?principal.id=$1`) |
| `kacho-api-gateway`  | `/iam/v1/auth/callback` handler в E2 уже создан; **расширяется** на E4: после `oidc.exchange` зовёт `InternalAuthService.SignupComplete` (gRPC-direct, port 9091), на success Set-Cookie + 302. Новый endpoint `/iam/v1/auth/me` (REST → gRPC `AuthService.Me`); `/iam/v1/auth/logout` (clear cookies + Zitadel revoke). Регистрация в restmux `iamPublicAddr`. **НЕ регистрируется** `InternalAuthService` (loop-prevention, запрет #6) |
| `kacho-ui`           | См. §3.2 — full new SPA structure: 5 auth-pages, 7×3=21+ IAM pages, 7 components, 7 api-slices. Также: header rework (UserMenu в правом углу), sidebar update (IAM section добавляется наравне с VPC/Compute/Load Balancer), route guards (redirect to /login если не залогинен), error boundary для signup-failures |
| `kacho-deploy`       | helm `kacho-ui` chart — обновление static-files-build (Vite production build); helm `kacho-api-gateway` chart — env `KACHO_API_GATEWAY_AUTH__SIGNUP_REDIRECT=/` (default redirect after signup); helm `zitadel-bootstrap-job` — enable signup-flow в Zitadel project config (`signupAllowed=true`, `passwordResetAllowed=true`); helm `kacho-iam` — env `KACHO_IAM_BOOTSTRAP__FIRST_USER_ADMIN=true` (default; toggle для testing scenarios) |
| `kacho-test`         | Playwright e2e tests (D-12): `e2e/signup.spec.ts`, `e2e/iam-crud.spec.ts`, `e2e/permission-reactivity.spec.ts`; npm scripts `make e2e-ui` через docker-compose с headless Chromium; CI integration в `kacho-test/.github/workflows/e2e-ui.yaml` |
| `kacho-workspace`    | этот acceptance; vault entries: `obsidian/kacho/edges/api-gateway-to-iam-signup-complete.md`, `edges/ui-to-api-gateway-iam.md`, `edges/ui-to-api-gateway-auth.md`, `resources/iam-user.md` (signup section update), `packages/ui-pages-iam.md`, `packages/ui-api-iam.md`, `packages/iam-internal-apps-auth.md`; KAC-tracker `obsidian/kacho/KAC/KAC-109.md` (in-progress → done) |

### 3.4 Cross-repo runtime edges (новые на E4)

| Edge                                                                  | Protocol      | Sync/async   | Purpose                                                          |
|-----------------------------------------------------------------------|---------------|--------------|------------------------------------------------------------------|
| `Browser → kacho-ui SPA → kacho-api-gateway`                          | HTTPS         | sync         | All UI navigation, including new IAM pages                       |
| `Browser → Zitadel signup form`                                       | HTTPS         | sync         | Zitadel-hosted signup page (no kacho-ui code involved)           |
| `Zitadel → kacho-api-gateway /iam/v1/auth/callback`                   | HTTPS POST    | sync         | OIDC redirect with `code`                                        |
| `kacho-api-gateway → kacho-iam:9091 InternalAuthService.SignupComplete` | gRPC direct   | sync (≤500ms) | Atomic bootstrap; new RPC in E4                                  |
| `kacho-api-gateway → kacho-iam:9090 AuthService.Me`                   | gRPC          | sync         | UI «who am I» on every page load (cached client-side 5min)       |
| `kacho-ui → kacho-api-gateway → kacho-iam (all 7 IAM RPCs)`           | HTTPS/gRPC    | sync         | Standard CRUD via grpc-gateway REST                              |
| `kacho-ui → kacho-api-gateway → kacho-iam AccessBindingService.ListBySubject` | HTTPS/gRPC | sync       | Permission heuristic (D-4); cached client-side 5min              |

> **Запрет #6**: `InternalAuthService.SignupComplete` — gRPC-direct port 9091, **НЕ** регистрируется в `kacho-api-gateway/internal/restmux/mux.go` (loop-prevention: auth-callback handler работает на REST-входе и должен звать SignupComplete до того, как auth-interceptor сможет его validate'нуть — circular). `AuthService.Me` — публичный (port 9090), регистрируется через restmux под `iamPublicAddr`.

---

## 4. Декомпозиция по компонентам (что именно реализуется)

### 4.1 kacho-iam — InternalAuthService.SignupComplete (use-case)

**Файл:** `kacho-iam/internal/apps/kacho/api/auth/signup_complete.go`

**Структура UseCase (evgeniy §2):**

```go
type SignupCompleteUseCase struct {
    authWriter    domain.AuthWriter
    operationsRepo operations.Writer
    bootstrapCfg  BootstrapConfig
}

type SignupCompleteInput struct {
    ExternalID  domain.ExternalID  // newtype, validated as non-empty
    Email       domain.Email
    DisplayName domain.DisplayName
}

type SignupCompleteOutput struct {
    UserID      domain.UserID
    AccountID   domain.AccountID
    ProjectID   domain.ProjectID
    IsFirstUser bool
    Operation   *operations.Operation // done=true (sync bootstrap)
}

func (uc *SignupCompleteUseCase) Execute(ctx context.Context, in SignupCompleteInput) (SignupCompleteOutput, error) {
    // 1. Validate input (newtypes already validated; here — additional cross-field checks)
    // 2. Open TX
    // 3. UPSERT users (race-safe via ON CONFLICT external_id DO UPDATE … RETURNING …)
    //    if existing row returned with same external_id → not-first-user path
    // 4. IF is_new_user AND bootstrap.FirstUserAdmin enabled:
    //    a. Acquire advisory lock (pg_try_advisory_xact_lock(BOOTSTRAP_LOCK_ID))
    //       — single-writer guarantee for first-user race; if lock-acquired-elsewhere
    //         (concurrent signup), wait (BLOCKING) — fast (other signup completes in <500ms),
    //         then re-check `accounts.owner_user_id IS NOT NULL` → take subsequent-user path
    //    b. SELECT … FROM accounts WHERE id='acc_default' AND owner_user_id IS NULL
    //    c. IF row found (CAS-style):
    //       - UPDATE accounts SET owner_user_id=$user_id WHERE id='acc_default' AND owner_user_id IS NULL
    //         (RETURNING — must return 1 row, else race lost)
    //       - INSERT access_bindings (subject_type='user', subject_id=$user_id,
    //                                role_id='rol_default_admin', scope_type='account', scope_id='acc_default')
    //       - INSERT access_bindings (subject_type='user', subject_id=$user_id,
    //                                role_id='rol_default_admin', scope_type='project', scope_id='prj_default')
    //       - INSERT outbox (event_type='fga.tuple.write', payload={user, owner, account:acc_default}; …)
    //       - INSERT outbox (event_type='fga.tuple.write', payload={user, admin, project:prj_default})
    //       - INSERT subject_change_outbox (subject_id=$user_id, op='binding_upsert')
    //       - is_first_user=true
    //    d. ELSE (CAS lost): is_first_user=false (subsequent user; no binding)
    // 5. INSERT operations row (done=true, response.Any={SignupResult}, principal_type='user', principal_id=user_id)
    // 6. COMMIT TX
    // 7. Return SignupCompleteOutput
}
```

**Race-safety (D-6, §4.2 §4.3):**

Два concurrent signup'а с одной `external_id`:
- Оба входят в TX;
- Один (winner) выполняет `INSERT … ON CONFLICT (external_id) DO UPDATE … RETURNING …`, видит `xmax = txid_current()` → новая row;
- Второй (loser) выполняет тот же INSERT, видит existing row (xmax=0) → таким же ON CONFLICT возвращает existing row;
- Оба попадают в если is_new (но **только один** — winner — имеет `is_new=true` через `RETURNING (xmax = 0) AS is_new`);
- Loser идёт в subsequent-user path → возвращает существующий user без binding-creation;
- Net result: ровно один new mirror, ровно одно (если first) account.owner_user_id update.

Два concurrent signup'а с **разными** `external_id` оба-первые-в-systeme:
- Оба входят в TX;
- Каждый UPSERT-ит свою row;
- Оба пытаются acquire advisory lock `pg_try_advisory_xact_lock(BOOTSTRAP_LOCK_ID)`;
- Один acquires → выполняет CAS на `accounts.owner_user_id IS NULL` → succeeds → admin-binding создан;
- Второй ждёт lock (lock — TX-scoped, освобождается на COMMIT первого);
- Первый COMMIT → второй acquires lock → CAS на `accounts.owner_user_id IS NULL` → **fails** (уже NOT NULL) → no admin-binding для второго.

**Result:** exactly-one-first-user invariant сохранён независимо от race timing.

### 4.2 Миграция 0008 — signup_bootstrap_lock + accounts.owner_user_id

**Файл:** `kacho-iam/migrations/0008_signup_bootstrap_lock.sql`

```sql
-- Add owner_user_id column to accounts (nullable; populated by first signup CAS).
-- E0 created accounts table without owner_user_id; E4 introduces ownership.
ALTER TABLE kacho_iam.accounts
    ADD COLUMN owner_user_id text NULL REFERENCES kacho_iam.users(id) ON DELETE SET NULL;

-- Partial unique index: at most one account per user as primary owner.
-- (On 2.0 — one Account total, but constraint defends future.)
CREATE UNIQUE INDEX accounts_owner_user_id_uniq
    ON kacho_iam.accounts (owner_user_id)
    WHERE owner_user_id IS NOT NULL;

-- Index for partial filter (used in CAS query: WHERE owner_user_id IS NULL).
CREATE INDEX accounts_owner_user_id_null_idx
    ON kacho_iam.accounts (id)
    WHERE owner_user_id IS NULL;

-- No DDL needed for advisory locks — they're acquired via pg_try_advisory_xact_lock(int) at runtime.
-- Reserve lock ID 4096 (arbitrary, documented in kacho-iam/internal/apps/kacho/api/auth/signup_complete.go).
-- COMMENT: bootstrap signup-flow uses pg_try_advisory_xact_lock(4096) before CAS on accounts.owner_user_id IS NULL.
```

**Файл:** `kacho-iam/migrations/0009_operations_principal_filter_idx.sql`

```sql
-- Index for OperationsService.List filter by principal_id (UI «My operations» tab).
-- principal_id column already exists from E2 (corelib operations migration).
CREATE INDEX operations_principal_id_idx
    ON kacho_iam.operations (principal_id)
    WHERE principal_id <> '';

-- Same in each per-service DB (kacho-vpc, kacho-compute, kacho-loadbalancer)
-- — distributed as common corelib migration (kacho-corelib/migrations/common/0006_operations_principal_id_idx.sql,
-- synced into each service via `make sync-migrations`).
-- Note: this migration in kacho-iam already covers iam's own operations table.
```

### 4.3 kacho-iam — AuthService.Me (use-case)

**Файл:** `kacho-iam/internal/apps/kacho/api/auth/me.go`

```go
type MeUseCase struct {
    accessBindingReader domain.AccessBindingReader
    accountReader       domain.AccountReader
}

type MeInput struct {
    Principal domain.Principal // from ctx (set by auth-interceptor in E2)
}

type MeOutput struct {
    Principal           domain.Principal
    EffectiveAccountID  domain.AccountID
    EffectiveProjectIDs []domain.ProjectID
    IsAdmin             bool // shortcut for UI: any admin-role binding on account
}

func (uc *MeUseCase) Execute(ctx context.Context, in MeInput) (MeOutput, error) {
    // 1. Get all bindings for principal (uses access_binding_reader.ListBySubject)
    // 2. For each binding:
    //    - If scope_type=account: add to effective_account_ids
    //    - If scope_type=project: add to effective_project_ids
    //    - If role is admin (rol_default_admin OR custom-role with all permissions): is_admin=true
    // 3. On 2.0 (single-Account): effective_account_id = first (or 'acc_default' if none)
    // 4. Return MeOutput
}
```

**REST endpoint:** `GET /iam/v1/auth/me` → MeResponse JSON.

**UI usage:** SPA вызывает `GET /auth/me` на app-bootstrap (`App.tsx` useEffect); cached в `session-storage` с TTL=5min; используется для:
- Header (display email);
- Sidebar (показать «IAM» section если is_admin OR has any binding на IAM resources);
- Route guards (redirect to /login если 401).

### 4.4 kacho-iam — AccessBindingService.ListBySubject (new use-case)

**Файл:** `kacho-iam/internal/apps/kacho/api/access_binding/list_by_subject.go`

```go
type ListBySubjectUseCase struct {
    reader domain.AccessBindingReader
}

type ListBySubjectInput struct {
    SubjectType domain.SubjectType
    SubjectID   domain.SubjectID
    // optional filters
    ScopeType  domain.ScopeType // optional
    PageSize   int32
    PageToken  string
}

type ListBySubjectOutput struct {
    Bindings      []domain.AccessBinding
    NextPageToken string
}
```

**REST:** `GET /iam/v1/accessBindings?subject.type=USER&subject.id=usr_alice&scope.type=PROJECT&pageSize=100`.

**UI usage (D-4 permission heuristic):**
- UI calls `ListBySubject(me)` on page-load;
- Builds `Set<(scope_type, scope_id, role_id)>` in memory;
- For each UI-button (e.g. `<CreateNetworkButton>`):
  - `usePermissionCheck("vpc.network", "editor")` hook returns true if any binding has role with `vpc.network` permission AND `editor`-level;
- Hook implementation:
  ```ts
  function usePermissionCheck(resource: string, action: string): boolean {
    const bindings = useAppSelector(selectMyBindings);
    const roles = useAppSelector(selectAllRoles); // also cached
    return bindings.some(b => {
      const role = roles.find(r => r.id === b.roleId);
      return role?.permissions.some(p =>
        p.resource === resource && permissionGrantedAction(p.action, action)
      );
    });
  }
  ```

### 4.5 kacho-api-gateway — auth-callback handler extension

**Файл:** `kacho-api-gateway/internal/middleware/auth.go` (extended) или `internal/apps/auth/callback.go` (new use-case).

**E2 уже создал:**
- `/iam/v1/auth/callback` endpoint;
- exchange `code` → `access_token` через `oidc.Client.Exchange()`;
- call `iam.InternalIamService.UpsertFromIdentity(external_id, email, display_name)` для lazy-mirror;
- Set-Cookie session.

**E4 расширяет:**

```go
func (h *CallbackHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
    code := r.URL.Query().Get("code")
    token, err := h.oidc.Exchange(ctx, code)
    if err != nil { http.Error(w, "oidc exchange failed", 400); return }

    // E2 path: parse JWT → external_id, email, display_name
    claims := h.oidc.ParseClaims(token.AccessToken)

    // E4 NEW: call SignupComplete (idempotent — handles both first-time signup and returning login)
    // gRPC-direct (port 9091), NOT through restmux (loop-prevention)
    op, err := h.iamInternalClient.SignupComplete(ctx, &iam.SignupCompleteRequest{
        ExternalID:  claims.Subject,
        Email:       claims.Email,
        DisplayName: claims.Name,
    })
    if err != nil {
        // Handle error: redirect to UI /signup?error=signup_failed
        http.Redirect(w, r, "/signup?error=signup_failed", 302)
        return
    }

    // Operation.done is always true for SignupComplete (sync bootstrap)
    result := &iam.SignupResult{}
    if err := op.Response.UnmarshalTo(result); err != nil { … }

    // Set cookies (already done in E2)
    h.setCookies(w, token)

    // Redirect to UI / (or /welcome?first=true if result.IsFirstUser)
    redirectURL := "/"
    if result.IsFirstUser {
        redirectURL = "/welcome?first=true" // UI shows tour for first-user
    }
    http.Redirect(w, r, redirectURL, 302)
}
```

**Note:** E2 уже звал `UpsertFromIdentity`, который только создавал mirror. E4 заменяет на `SignupComplete`, который **дополнительно** создаёт first-user bindings. Это NOT breaking E2 — `UpsertFromIdentity` остаётся как separate RPC для admin tooling (например, manual user import); auth-callback handler переключается на `SignupComplete` exclusively.

### 4.6 kacho-ui — Pages, components, API slices

**Routing structure (React Router v6):**

```
/                       → DashboardPage (existing)
/signup                 → SignupPage (NEW)
/login                  → LoginPage (NEW)
/logout                 → LogoutPage (NEW)
/welcome                → WelcomePage (NEW) — first-user tour
/auth/callback          → CallbackPage (NEW; rarely used — backend handles 302)
/vpc/...                → existing
/compute/...            → existing
/iam                    → redirect to /iam/projects (default)
/iam/accounts           → AccountsListPage (NEW)
/iam/accounts/:id       → AccountDetailPage
/iam/projects           → ProjectsListPage
/iam/projects/:id       → ProjectDetailPage
/iam/projects/new       → ProjectCreatePage
/iam/users              → UsersListPage
/iam/users/:id          → UserDetailPage
/iam/service-accounts   → ServiceAccountsListPage
/iam/service-accounts/:id → ServiceAccountDetailPage
/iam/service-accounts/new → ServiceAccountCreatePage
/iam/groups             → GroupsListPage
/iam/groups/:id         → GroupDetailPage
/iam/groups/new         → GroupCreatePage
/iam/roles              → RolesListPage
/iam/roles/:id          → RoleDetailPage
/iam/roles/new          → RoleCreatePage (JSON-paste textarea)
/iam/access-bindings    → AccessBindingsListPage
/iam/access-bindings/:id → AccessBindingDetailPage
```

**Auth guard (route middleware):**

```tsx
function ProtectedRoute({ children }: { children: ReactNode }) {
  const { data: me, isLoading } = useGetMeQuery();
  if (isLoading) return <Spinner />;
  if (!me) return <Navigate to="/login" replace />;
  return <>{children}</>;
}

// в App.tsx:
<Route element={<ProtectedRoute><Layout /></ProtectedRoute>}>
  <Route path="/" element={<DashboardPage />} />
  <Route path="/iam/*" element={<IamRoutes />} />
  ...
</Route>
<Route path="/signup" element={<SignupPage />} />
<Route path="/login" element={<LoginPage />} />
```

**RTK Query slice example (`api/iam/accessBindings.ts`):**

```ts
export const accessBindingsApi = createApi({
  reducerPath: 'accessBindingsApi',
  baseQuery: fetchBaseQuery({ baseUrl: '/iam/v1/' }),
  tagTypes: ['AccessBinding', 'MyBindings'],
  endpoints: (builder) => ({
    listAccessBindings: builder.query<ListResponse, ListParams>({
      query: (params) => ({ url: 'accessBindings', params }),
      providesTags: (res) =>
        res ? [...res.items.map(b => ({ type: 'AccessBinding' as const, id: b.id })), 'AccessBinding']
            : ['AccessBinding'],
    }),
    listBySubject: builder.query<ListResponse, { subjectId: string; subjectType: string }>({
      query: (p) => ({ url: 'accessBindings', params: { 'subject.id': p.subjectId, 'subject.type': p.subjectType } }),
      providesTags: ['MyBindings'],
    }),
    upsertAccessBinding: builder.mutation<Operation, UpsertParams>({
      query: (b) => ({ url: 'accessBindings', method: 'POST', body: b }),
      invalidatesTags: ['AccessBinding', 'MyBindings'],
    }),
    deleteAccessBinding: builder.mutation<Operation, { id: string }>({
      query: (p) => ({ url: `accessBindings/${p.id}`, method: 'DELETE' }),
      invalidatesTags: ['AccessBinding', 'MyBindings'],
    }),
  }),
});
```

**Реактивность (D-5):**
- Mutation `upsertAccessBinding` invalidates `AccessBinding` + `MyBindings` tags;
- All queries with these tags auto-refetch;
- Backend NOTIFY (E3) → api-gateway cache invalidated → next request returns updated data;
- End-to-end: user A grants B viewer-on-network N → B's `listNetworks` query (если активен) refetches via RTK Query subscription if explicitly invalidated by client OR через next page-load (5-10s reactivity).

### 4.7 OperationsTable — CreatedBy column

**Файл:** `kacho-ui/src/components/OperationsTable.tsx` (extended).

```tsx
function CreatedByCell({ op }: { op: Operation }) {
  const principal = op.principal; // { type, id, displayName }
  const icon = principal.type === 'USER' ? <UserIcon /> :
               principal.type === 'SERVICE_ACCOUNT' ? <BotIcon /> :
               <SettingsIcon />; // SYSTEM
  return (
    <Tooltip content={`${principal.type}: ${principal.id}`}>
      <div className="flex items-center gap-1">
        {icon}
        <span>{principal.displayName || principal.id}</span>
      </div>
    </Tooltip>
  );
}

// table columns extended:
const columns = [
  ...existingColumns,
  { id: 'createdBy', header: 'Created by', cell: (op) => <CreatedByCell op={op} /> },
];
```

**Filter:** UI кладёт `?principal.id=me` (resolved via `useGetMeQuery().principal.id`) при click на «My operations» tab.

### 4.8 SignupPage component

**Файл:** `kacho-ui/src/pages/auth/SignupPage.tsx`

```tsx
export function SignupPage() {
  const { data: me } = useGetMeQuery(undefined, { skip: false });
  if (me) return <Navigate to="/" replace />; // already logged in

  const handleSignup = () => {
    // Build Zitadel signup URL
    const zitadelSignupURL = new URL(`${ZITADEL_ISSUER}/signup`);
    zitadelSignupURL.searchParams.set('client_id', 'kacho-ui');
    zitadelSignupURL.searchParams.set('redirect_uri', `${ORIGIN}/iam/v1/auth/callback`);
    zitadelSignupURL.searchParams.set('response_type', 'code');
    zitadelSignupURL.searchParams.set('scope', 'openid email profile');
    window.location.href = zitadelSignupURL.toString();
  };

  return (
    <div className="min-h-screen flex items-center justify-center">
      <Card className="w-96 p-8">
        <KachoLogo />
        <h1 className="text-2xl font-bold mt-4">Sign up for Kachō</h1>
        <p className="text-sm text-muted-foreground mt-2">
          Create your account to access VPC, Compute, and Load Balancer resources.
        </p>
        <Button onClick={handleSignup} className="w-full mt-6">
          Sign up with Zitadel
        </Button>
        <p className="text-sm text-center mt-4">
          Already have an account? <Link to="/login">Log in</Link>
        </p>
        <SignupErrorBanner /> {/* shows ?error= query param messages */}
      </Card>
    </div>
  );
}
```

---

## 5. GWT-сценарии (25)

### 5.1 Signup happy paths (3 сценария)

#### Scenario E4.GWT-01: First-user signup — fresh cluster, atomic bootstrap (DoD #1)

**ID:** 2.0-E4-GWT-01
**REQ:** REQ-IAM-SIGNUP-FIRST-01

**Given** свежий `make dev-up` cluster, `kacho_iam.users` пустой, `accounts.owner_user_id IS NULL` для `acc_default`
**And** Zitadel up, OpenFGA up, `kacho-iam` healthy
**And** seed-миграции applied: `acc_default`, `prj_default`, `rol_default_admin` существуют

**When** browser opens `https://api.kacho.local/signup`
**And** UI renders SignupPage; user clicks "Sign up with Zitadel"
**And** browser redirected to Zitadel `/signup?client_id=kacho-ui&...`
**And** user fills email=`alice@example.com`, password, submits
**And** Zitadel POSTs callback to `/iam/v1/auth/callback?code=XXX`
**And** api-gateway exchanges code → access_token, parses JWT (external_id=zitadel_user_id, email, name)
**And** api-gateway calls `kacho-iam:9091 InternalAuthService.SignupComplete({external_id, email, display_name})`
**And** kacho-iam executes atomic TX (see §4.1)

**Then** TX succeeds: `users` has 1 row for alice; `accounts.owner_user_id='usr_alice'`; `access_bindings` has 2 rows (admin@acc_default, admin@prj_default); `outbox` has 2 rows (FGA-write events); `subject_change_outbox` has 1 row
**And** `operations` table has row with `principal_type='user', principal_id='usr_alice', done=true, response.SignupResult{user_id, account_id, project_id, is_first_user=true}`
**And** api-gateway sets cookies (`kacho_session=<jwt>; HttpOnly; Secure; SameSite=Strict; Max-Age=900`)
**And** api-gateway 302 redirects to `/welcome?first=true`
**And** WelcomePage renders, shows email in header
**And** within ≤5s (NFR-3): user is fully bootstrapped, IAM sidebar visible, can navigate `/iam/users` and see alice listed
**And** within ≤2s (E3 outbox SLA): OpenFGA contains tuples `user:usr_alice admin account:acc_default`, `user:usr_alice admin project:prj_default`
**And** `GET /iam/v1/auth/me` returns `{principal: {type: USER, id: usr_alice, displayName: alice@example.com}, isAdmin: true, effectiveAccountId: acc_default}`

#### Scenario E4.GWT-02: Subsequent-user signup — existing first-admin, new user joins без binding

**ID:** 2.0-E4-GWT-02
**REQ:** REQ-IAM-SIGNUP-SUBSEQUENT-01

**Given** alice уже first-user-admin (GWT-01 executed)
**And** `accounts.owner_user_id='usr_alice'`

**When** новый user `bob@example.com` opens `/signup`, completes Zitadel signup
**And** callback received, `SignupComplete` called

**Then** TX succeeds: `users` has 2 rows (alice + bob); `accounts.owner_user_id` остался `usr_alice` (CAS не сработал — already NOT NULL)
**And** **никакие** access_bindings не созданы для bob (subsequent-user path)
**And** Operation response `{user_id: usr_bob, is_first_user: false}`
**And** api-gateway sets cookies + 302 to `/` (не `/welcome`)
**And** UI renders Dashboard; in header: bob@example.com; в sidebar IAM section **не виден** (D-4: ListBySubject returns empty → permission heuristic = no IAM permission)
**And** попытка bob открыть `/iam/users` напрямую (через URL) → ProtectedRoute проверяет me ≠ null (OK, logged in), но `GET /iam/v1/users` через UI returns `PermissionDenied` → UI shows ErrorBanner «You don't have permission»
**And** bob может видеть только public/no-permission pages (e.g. `/` dashboard with empty resources)
**And** alice (через UI as admin) видит bob в `/iam/users` list, может grant bob role через `/iam/access-bindings/new`

#### Scenario E4.GWT-03: OIDC callback race — concurrent signup of same external_id

**ID:** 2.0-E4-GWT-03
**REQ:** REQ-IAM-SIGNUP-RACE-01

**Given** свежий cluster, никаких users
**And** test environment: same browser is opened in two tabs simultaneously (or two requests via grpcurl/curl)
**And** оба окна одновременно нажимают "Sign up", одновременно завершают Zitadel signup (same email, same external_id)
**And** Zitadel issues two callbacks with same `code` (idempotent code exchange)

**When** обе callbacks одновременно POSTed to `/iam/v1/auth/callback`
**And** api-gateway exchanges both codes (one succeeds, second fails — Zitadel code reuse error) ИЛИ оба succeed (Zitadel returns same access_token)
**And** оба handler'а одновременно вызывают `SignupComplete` с одинаковыми `{external_id, email}`

**Then** kacho-iam two concurrent TX:
- Один TX UPSERT-ит users (winner); RETURNING xmax=0 → is_new=true
- Второй TX UPSERT-ит users (loser); RETURNING (xmax = previous_txid) → is_new=false; finds existing row
**And** оба пытаются acquire advisory lock 4096
**And** winner acquires, выполняет CAS на accounts.owner_user_id → UPDATE returns 1 row → admin-binding создан → is_first_user=true → COMMIT → lock released
**And** loser ждёт lock (TX-scoped); после release acquires → CAS UPDATE returns **0 rows** (already NOT NULL) → is_first_user=false → COMMIT
**And** Результат: ровно 1 mirror в users, ровно 1 admin-binding в access_bindings (никаких duplicates)
**And** Оба клиента получают success-redirect; для winner — `/welcome?first=true`, для loser — `/` (но фактически это **тот же** user, оба клиента указывают на одну сессию)
**And** Test assertion: `SELECT COUNT(*) FROM users WHERE external_id=$1` = 1; `SELECT COUNT(*) FROM access_bindings WHERE subject_id=$1 AND role_id='rol_default_admin'` = 2 (one per scope: account + project, but exactly one each, not 4)

### 5.2 OnFirstLogin atomic (3 сценария)

#### Scenario E4.GWT-04: Atomic bootstrap — все 4 шага в одной TX

**ID:** 2.0-E4-GWT-04
**REQ:** REQ-IAM-BOOTSTRAP-ATOMIC-01

**Given** свежий cluster, no users
**And** Test setup: integration test in `kacho-iam/internal/apps/kacho/api/auth/signup_complete_integration_test.go`
**And** mock-disabled FGA worker (manually controlled drain в тесте)

**When** test calls `SignupComplete({external_id=zid_alice, email, name})` через mock-gRPC

**Then** SELECT после TX:
- `users` (1 row) — alice
- `accounts.owner_user_id` (acc_default) — usr_alice
- `access_bindings` (2 rows) — owner@account + admin@project
- `outbox` (2 rows) — FGA-write events для каждой binding
- `subject_change_outbox` (1 row) — invalidation
- `operations` (1 row) — `done=true, principal_id=usr_alice, response={SignupResult}`
**And** все 6 INSERT'ов + 1 UPDATE — в одной TX (verified via TX-id в pg_stat_activity captured в тесте)
**And** Test injects failure после 4-го INSERT (mock через debug-hook) → TX rolls back полностью:
- `users` остаётся empty
- `accounts.owner_user_id` остаётся NULL
- `access_bindings` empty
- `outbox` empty
- `operations` empty (Operation row тоже roll-back)

#### Scenario E4.GWT-05: Rollback при failure — частичный success не сохраняется

**ID:** 2.0-E4-GWT-05
**REQ:** REQ-IAM-BOOTSTRAP-ROLLBACK-01

**Given** Mid-TX failure simulated через test-hook (e.g. inject `pgx error` after 3rd INSERT)
**And** kacho-iam SignupComplete in-progress

**When** failure injected
**And** TX rolls back

**Then** No data persisted; clean state как до signup
**And** Operation row тоже не вставлена (если она внутри TX — иначе orphan); тест проверяет `SELECT COUNT(*) FROM operations WHERE principal_id=usr_alice` = 0
**And** Caller (api-gateway) получает gRPC `Internal: "signup bootstrap failed"` error
**And** api-gateway redirects browser to `/signup?error=signup_failed`
**And** Метрика `kacho_iam_signup_failures_total` инкрементируется
**And** Retry: user clicks "Sign up" again — flow proceeds successfully (idempotent на retry — нет half-state, который мешает)

#### Scenario E4.GWT-06: Idempotency on retry — повторный signup того же external_id не дублирует

**ID:** 2.0-E4-GWT-06
**REQ:** REQ-IAM-BOOTSTRAP-IDEMPOTENT-01

**Given** alice уже signed up (GWT-01)
**And** alice logs out (cookie cleared)
**And** alice clicks "Sign up" again (или просто "Log in" с тем же Zitadel-account)

**When** Zitadel callback с тем же `external_id=zid_alice`
**And** api-gateway calls `SignupComplete` again

**Then** TX:
- UPSERT users finds existing row; is_new=false
- Skip advisory lock CAS (т.к. is_new=false)
- Operation вставлена (новая Operation, новый id) с `is_first_user=false, user_id=usr_alice`
**And** No duplicate users / access_bindings / outbox events
**And** Test: `SELECT COUNT(*) FROM users WHERE external_id=zid_alice` = 1 (unchanged); `COUNT(*) FROM access_bindings WHERE subject_id=usr_alice` = 2 (unchanged from GWT-01)
**And** alice залогинена, cookie установлен, redirected to `/`

### 5.3 Sidebar visibility (2 сценария)

#### Scenario E4.GWT-07: Owner видит IAM sidebar — все child-pages доступны (DoD #2)

**ID:** 2.0-E4-GWT-07
**REQ:** REQ-IAM-UI-SIDEBAR-OWNER-01

**Given** alice залогинена (admin@acc_default)
**And** UI loaded, RTK Query `ListBySubject(me)` returned [admin@account, admin@project]

**When** UI renders Sidebar

**Then** Sidebar содержит section "Identity and Access Management" с иконкой `ShieldCheck` (Lucide)
**And** Section expandable; на click показывает 7 child-links: Accounts, Projects, Users, Service Accounts, Groups, Roles, Access Bindings
**And** click на любой child → navigates to соответствующий ListPage
**And** ListPage successfully fetches data через RTK Query (alice has admin → 200)
**And** "Create" button visible (D-4: usePermissionCheck("iam.users", "editor") = true для admin)
**And** "Edit"/"Delete" buttons visible в table row actions

#### Scenario E4.GWT-08: Viewer/no-permission user — IAM sidebar скрыт

**ID:** 2.0-E4-GWT-08
**REQ:** REQ-IAM-UI-SIDEBAR-NOPERM-01

**Given** bob signed up (GWT-02), no bindings
**And** UI loaded, RTK Query `ListBySubject(me)` returned []

**When** UI renders Sidebar

**Then** Sidebar содержит "Dashboard" + "VPC" + "Compute" + "Load Balancer" (basic public)
**And** Section "Identity and Access Management" **НЕ виден** (D-4: usePermissionCheck("iam.users", "viewer") returns false → PermissionGate hides element)
**And** Test: попытка navigate to `/iam/users` напрямую (URL) → ProtectedRoute passes (logged in), но page makes request to `/iam/v1/users` → backend returns `PermissionDenied` → UI ErrorBanner "You don't have permission to view this page"
**And** Sidebar также скрывает Create/Edit/Delete buttons в VPC/Compute pages если bob нет соответствующих прав

### 5.4 CRUD страницы (7 сценариев — по одной на ресурс)

#### Scenario E4.GWT-09: Accounts CRUD — owner может read; create/delete disabled на 2.0

**ID:** 2.0-E4-GWT-09
**REQ:** REQ-IAM-UI-CRUD-ACCOUNT-01

**Given** alice (admin) на `/iam/accounts`

**When** UI renders AccountsListPage

**Then** Table показывает 1 row: `acc_default` с полями id, name, owner_user_id, created_at
**And** "Create Account" button **disabled** с tooltip "Multi-account not supported on Phase 2.0" (D-7: один Account = один tenant)
**And** click на row → AccountDetailPage показывает full account info + список projects (1: prj_default) + список members (alice + bob)
**And** "Delete Account" button **hidden** (нельзя удалить root account)
**And** Negative test: попытка `DELETE /iam/v1/accounts/acc_default` напрямую (через grpcurl as admin) → `FailedPrecondition: "cannot delete root account on Phase 2.0"`

#### Scenario E4.GWT-10: Projects CRUD — create new project, list, edit, delete

**ID:** 2.0-E4-GWT-10
**REQ:** REQ-IAM-UI-CRUD-PROJECT-01

**Given** alice (admin) на `/iam/projects`

**When** alice clicks "Create Project", filling form: name="prj-dev", description="Dev project"
**And** UI POSTs `/iam/v1/projects { account_id: acc_default, name: "prj-dev", description: "..." }`
**And** kacho-iam returns Operation done=true with Project{id: prj_dev}

**Then** Table refreshes (RTK Query invalidates `Project` tag); now 2 rows: prj_default, prj_dev
**And** click prj_dev → ProjectDetailPage; "Edit" + "Delete" buttons available
**And** alice clicks "Edit" → form pre-filled; alice changes description → Save → POST /iam/v1/projects/prj_dev?updateMask=description
**And** UI shows updated description
**And** Negative: alice clicks "Delete" on prj_dev → confirm dialog → DELETE /iam/v1/projects/prj_dev → success (empty project)
**And** Negative-fail: alice creates VPC Network in prj_dev → tries to delete prj_dev → `FailedPrecondition: "project has resources"` (cross-service hint) → UI ErrorBanner с link "View VPC Networks in this project"

#### Scenario E4.GWT-11: Users CRUD — list users, view detail; delete via admin

**ID:** 2.0-E4-GWT-11
**REQ:** REQ-IAM-UI-CRUD-USER-01

**Given** alice (admin) на `/iam/users`; existing users: alice + bob

**When** UI renders UsersListPage

**Then** Table: 2 rows (alice, bob) с email, display_name, external_id (truncated), created_at
**And** "Create User" button **hidden** (users created via Zitadel signup, not admin invite — D-1; users invite — Phase 2.1)
**And** click bob row → UserDetailPage; shows bob's bindings (если есть), groups membership, last_login (если tracked)
**And** "Delete" button visible для alice (admin); click → confirm dialog "Are you sure? This removes bob from Kachō but NOT from Zitadel" → DELETE /iam/v1/users/usr_bob
**And** kacho-iam: cascade удаление bindings (FK CASCADE из E0); bob больше не в users; Zitadel — нет (out of scope; для full revoke admin должен manual в Zitadel)
**And** Negative: bob (viewer) — `/iam/users` shows ErrorBanner или is hidden via sidebar (GWT-08)

#### Scenario E4.GWT-12: Service Accounts CRUD — create SA, generate key, view, revoke

**ID:** 2.0-E4-GWT-12
**REQ:** REQ-IAM-UI-CRUD-SA-01

**Given** alice (admin) на `/iam/service-accounts`

**When** alice clicks "Create Service Account": name="ci-runner", description="CI bot"
**And** UI POSTs `/iam/v1/serviceAccounts {account_id: acc_default, name: "ci-runner", description: "..."}`
**And** Operation returns SA{id: sva_ci}
**And** UI на success: opens KeyGenerationDialog "Generate key for ci-runner?"
**And** alice clicks "Generate" → POST `/iam/v1/serviceAccounts/sva_ci/keys`
**And** Backend (E2 logic — sa_keys table + Zitadel management-API call) creates key, returns `{key_id, public_key_pem, private_key_pem}`
**And** UI shows private_key_pem in modal **ONE TIME**, with "Download" + "Copy" + warning "This key will not be shown again"

**Then** SA in list; KeyDetailPage shows public_key_pem only
**And** Test: SA with private_key_pem authenticates via OIDC `private_key_jwt` flow → gets Zitadel access_token → calls `/vpc/v1/networks` → 200 OK (если SA has binding)
**And** "Revoke Key" button → POST `/iam/v1/serviceAccounts/sva_ci/keys/{key_id}/revoke` → SA loses access within ≤30s (Zitadel introspection cache)
**And** Negative: create SA without permission → PermissionDenied; UI shows error

#### Scenario E4.GWT-13: Groups CRUD — create, add/remove members, list

**ID:** 2.0-E4-GWT-13
**REQ:** REQ-IAM-UI-CRUD-GROUP-01

**Given** alice (admin) на `/iam/groups`; users: alice, bob, charlie

**When** alice clicks "Create Group": name="dev-team"
**And** UI POSTs `/iam/v1/groups {account_id: acc_default, name: "dev-team"}`
**And** Operation returns Group{id: grp_dev}

**Then** Group в list; click row → GroupDetailPage
**And** GroupDetailPage показывает 2 tabs: "Members" + "Bindings"
**And** Members tab: empty initially; alice clicks "Add Member" → SubjectPicker autocomplete (User/SA/Group) → выбирает bob, charlie → POSTs `/iam/v1/groups/grp_dev/members` (2 raz)
**And** Members table now has 2 rows: bob, charlie
**And** alice clicks "Remove" on charlie → DELETE /iam/v1/groups/grp_dev/members/usr_charlie → table refreshes
**And** Test: попытка добавить duplicate (bob второй раз) → `AlreadyExists` (UNIQUE constraint в E0); UI ErrorBanner "bob is already a member"
**And** Test: попытка добавить subject from другого account → `InvalidArgument` (scope check)

#### Scenario E4.GWT-14: Roles CRUD — list system + custom, create custom role (JSON-paste)

**ID:** 2.0-E4-GWT-14
**REQ:** REQ-IAM-UI-CRUD-ROLE-01

**Given** alice (admin) на `/iam/roles`

**When** UI renders RolesListPage

**Then** Table показывает system roles (rol_default_admin, rol_default_viewer, rol_default_editor + per-module variants) — все с label "System" и **disabled** Edit/Delete buttons (D-14: system roles read-only)
**And** "Create Role" button visible
**And** alice clicks → RoleCreatePage; form has fields: name, description, permissions (JSON textarea — D-3)
**And** alice enters name="vpc-network-readonly", description, permissions=`[{"resource": "vpc.network", "action": "viewer"}, {"resource": "vpc.subnet", "action": "viewer"}]`
**And** UI POSTs `/iam/v1/roles {name, description, permissions}`
**And** kacho-iam validates permissions (D-14): all permission strings must be in supported-list; reject if not (`InvalidArgument: "unsupported permission: foo.bar"`)
**And** Valid → Operation returns Role{id: rol_custom_xxx, is_system: false}

**Then** Role visible in list; can be selected in AccessBindingCreateDialog RolePicker
**And** Negative: alice tries `permissions=[{"resource": "vpc.network", "action": "DESTROY_PLANET"}]` → InvalidArgument; UI ErrorBanner "Unsupported permission: vpc.network/DESTROY_PLANET"
**And** Negative: bob (viewer) — RoleCreatePage не доступен (Create button hidden, page guard)

#### Scenario E4.GWT-15: Access Bindings CRUD — list, create via dropdowns, revoke

**ID:** 2.0-E4-GWT-15
**REQ:** REQ-IAM-UI-CRUD-BINDING-01

**Given** alice (admin) на `/iam/access-bindings`; existing bindings: 2 (alice's from signup)

**When** UI renders AccessBindingsListPage

**Then** Table: 2 rows с columns Subject, Role, Scope, Created
**And** "Create Binding" button visible; click → AccessBindingCreateDialog
**And** Dialog has 3 pickers: SubjectPicker (User/SA/Group), RolePicker (system + custom), ScopePicker (Account/Project/Resource)
**And** alice selects: subject=bob, role=vpc-viewer, scope=Project:prj_dev → click "Create"
**And** UI POSTs `/iam/v1/accessBindings { subject: {type: USER, id: usr_bob}, roleId: rol_default_vpc_viewer, scope: {type: PROJECT, id: prj_dev}}`
**And** Operation returns AccessBinding{id: bnd_xxx}

**Then** Binding в list (3 rows now); within ≤2s (E3 outbox SLA) — OpenFGA contains tuple
**And** Test: bob's `usePermissionCheck("vpc.network", "viewer")` теперь returns true → UI updates (см. GWT-22 реактивность)
**And** alice clicks "Revoke" on bnd_xxx → confirm dialog → DELETE /iam/v1/accessBindings/bnd_xxx → row removed
**And** within ≤10s (E3 NFR-5) — OpenFGA tuple removed, bob loses permission

### 5.5 AccessBinding UI (3 сценария)

#### Scenario E4.GWT-16: Grant User-Role-Project — User:bob получает editor@prj_dev одним кликом

**ID:** 2.0-E4-GWT-16
**REQ:** REQ-IAM-UI-BINDING-USER-01

**Given** alice (admin) on AccessBindingCreateDialog
**And** existing users: alice, bob; existing project: prj_dev

**When** alice opens dialog, fills:
- Subject: type=User, id (selected via autocomplete dropdown showing all users) = bob
- Role: selected via autocomplete (system+custom) = "vpc.editor" (system role)
- Scope: type=Project, id (selected via project-picker showing 2 projects) = prj_dev
**And** clicks "Create"
**And** UI POSTs `POST /iam/v1/accessBindings`
**And** Operation done=true → binding created

**Then** Binding visible in `/iam/access-bindings` list
**And** within ≤2s — FGA tuple `user:usr_bob editor project:prj_dev` written via E3 outbox
**And** Test: bob (new browser session) → `/vpc/networks` → page loads, можно `POST /vpc/v1/networks` в prj_dev → success
**And** Test: bob cannot access prj_other (no binding) → `PermissionDenied` on read
**And** Дополнительно: NFR-2 для binding-creation latency p95 ≤ 200ms (E3)

#### Scenario E4.GWT-17: Grant Group-Role-Resource — Group получает viewer на конкретный VPC Network

**ID:** 2.0-E4-GWT-17
**REQ:** REQ-IAM-UI-BINDING-GROUP-RESOURCE-01

**Given** alice (admin); group "dev-team" с members [bob, charlie]; VPC Network "net-shared" в prj_dev

**When** alice opens AccessBindingCreateDialog:
- Subject: type=Group, id=grp_dev
- Role: vpc.network.viewer (per-resource-type system role)
- Scope: type=Resource, resourceType=vpc_network, id=net-shared
**And** clicks "Create"

**Then** Binding created; FGA tuples:
- `group:grp_dev#member viewer vpc_network:net-shared`
**And** within ≤10s — bob и charlie (через group#member computed relation in DSL) могут `GET /vpc/v1/networks/net-shared` → 200
**And** Test: bob не может GET другой network в prj_dev (нет project-wide binding) → PermissionDenied
**And** Test: alice removes charlie from group (`DELETE /iam/v1/groups/grp_dev/members/usr_charlie`) → within ≤10s charlie теряет access на net-shared (subject_change_outbox для charlie сгенерирован в kacho-iam group-remove handler — E3 §11 OQ-2)
**And** bob продолжает access (всё ещё in group)

#### Scenario E4.GWT-18: Revoke binding — UI и backend синхронны, реактивно

**ID:** 2.0-E4-GWT-18
**REQ:** REQ-IAM-UI-BINDING-REVOKE-01

**Given** bob has binding bnd_xxx (editor@prj_dev из GWT-16)
**And** alice (admin) на `/iam/access-bindings`

**When** alice clicks "Revoke" on bnd_xxx → confirm dialog "Revoke editor@project:prj_dev for bob?" → click "Confirm"
**And** UI sends DELETE /iam/v1/accessBindings/bnd_xxx
**And** kacho-iam atomic TX: DELETE row + INSERT outbox (delete-tuple) + INSERT subject_change_outbox

**Then** Operation done=true; UI invalidates `AccessBinding` tag; list refetches; bnd_xxx removed from table
**And** within ≤2s — FGA tuple deleted (E3 outbox worker)
**And** within ≤10s — bob's next RPC получает PermissionDenied (E3 NFR-5)
**And** E2E test (Playwright): bob's open tab on `/vpc/networks` (with auto-poll каждые 10s OR manual refresh) — after ≤10s page shows empty / "No permission" state
**And** Метрика `kacho_authz_revoke_propagation_seconds` measured ≤10s

### 5.6 Operations principal UI (2 сценария)

#### Scenario E4.GWT-19: Operation от User — UI показывает email + User icon

**ID:** 2.0-E4-GWT-19
**REQ:** REQ-IAM-UI-OPS-USER-01

**Given** alice (admin@prj_dev) on `/vpc/networks`
**And** alice creates Network "test-net" via "Create" button

**When** kacho-vpc.NetworkService.Create executed; Operation inserted with `principal_type='user', principal_id='usr_alice', principal_display_name='alice@example.com'` (from corelib via E2 ctx propagation)
**And** UI navigates to `/operations` (or auto-shows toast with link)

**Then** OperationsTable shows row для Network create:
- ID: op_xxx
- Type: vpc.NetworkService.Create
- Status: DONE
- **Created by**: User icon (Lucide) + "alice@example.com"
- Created: timestamp
**And** Hover on "Created by" cell shows tooltip "USER: usr_alice"
**And** click on row → OperationDetailPage shows full Operation incl. principal
**And** Filter `?principal.id=usr_alice` (UI button "My operations") shows только alice's operations

#### Scenario E4.GWT-20: Operation от Service Account — UI показывает SA name + Bot icon

**ID:** 2.0-E4-GWT-20
**REQ:** REQ-IAM-UI-OPS-SA-01

**Given** SA `ci-runner` (sva_ci) с key, editor@prj_dev binding
**And** CI-bot uses SA-credentials → calls `POST /vpc/v1/networks` через api-gateway

**When** kacho-vpc creates Network; Operation inserted with `principal_type='service_account', principal_id='sva_ci', principal_display_name='ci-runner'`
**And** alice (admin) opens `/operations`

**Then** Table shows Network create op:
- Created by: Bot icon (Lucide) + "ci-runner"
**And** Hover tooltip: "SERVICE_ACCOUNT: sva_ci"
**And** Test: filter `?principal.type=SERVICE_ACCOUNT` → only SA operations
**And** Test: filter `?principal.id=sva_ci` → only ci-runner operations
**And** На странице SA `/iam/service-accounts/sva_ci` — link "View operations" → goes to filtered operations view

### 5.7 Реактивность e2e (3 сценария)

#### Scenario E4.GWT-21: Grant role → bob видит ресурс в UI через ≤10s

**ID:** 2.0-E4-GWT-21
**REQ:** REQ-IAM-UI-REACT-GRANT-01

**Given** Two browser sessions (Playwright two contexts): tab-alice (admin), tab-bob (no bindings)
**And** alice has Network "net-a" в prj_dev
**And** bob's `/vpc/networks` page is open, currently shows empty (no permission) — UI shows "You don't have access to any networks"

**When** alice in tab-alice goes to `/iam/access-bindings/new`, creates binding (bob, vpc-viewer, prj_dev) → submit
**And** UI confirms creation (Operation done=true)
**And** Time T0 recorded; E3 outbox propagates tuple to FGA in ≤2s; subject_change_outbox notifies api-gateway cache invalidate

**Then** В tab-bob: пользователь видит изменение в течение ≤10s. Механизм:
- bob's RTK Query subscription для `listNetworks` (если active) выполняет refetch через subscription invalidation (RTK Query auto-refetches when tab gets focus OR на keepUnusedDataFor timeout)
- ИЛИ user clicks "Refresh" button → page reloads, ListBySubject(bob) returns binding → permission heuristic updates → networks query fires → returns net-a
- ИЛИ полностью reload tab (worst-case if user не делает explicit action)
**And** Playwright assertion: within 15s (slight buffer над NFR-5 для UI render time) — tab-bob shows net-a in list
**And** Test measures Δ = first_visible_at - T0; Δ ≤ 15s (NFR: 10s backend + 5s UI render budget)

#### Scenario E4.GWT-22: Revoke role → bob теряет доступ в UI через ≤10s

**ID:** 2.0-E4-GWT-22
**REQ:** REQ-IAM-UI-REACT-REVOKE-01

**Given** bob has viewer@prj_dev (granted в GWT-21)
**And** tab-bob open на `/vpc/networks/net-a` — page показывает network detail

**When** alice in tab-alice does DELETE /iam/v1/accessBindings/{bob_binding} → success
**And** Time T0 recorded

**Then** В tab-bob: within ≤10s:
- next auto-refetch (RTK Query polling 5s) OR manual refresh OR page navigation triggers backend Check → PermissionDenied → UI shows ErrorBanner "You no longer have access to this network"
- Sidebar IAM section (если был visible) updates: ListBySubject(bob) returns empty → permission heuristic → IAM section hidden
**And** Playwright assertion: within 15s, tab-bob shows error state OR redirects to home
**And** Test verifies NO grace-period — old data not shown after backend says deny

#### Scenario E4.GWT-23: Restart-resistance UI — page-reload после revoke shows correct state

**ID:** 2.0-E4-GWT-23
**REQ:** REQ-IAM-UI-REACT-RESTART-01

**Given** bob had viewer@prj_dev; alice revoked во время AJAX-in-flight
**And** UI было mid-fetch (e.g. bob clicked "Networks", request in flight)

**When** Revoke completes; bob's pending request reaches backend; backend Check returns PermissionDenied
**And** UI receives 403 from /vpc/v1/networks
**And** UI shows ErrorBanner; user clicks reload (F5)

**Then** Full page reload: SPA bootstraps fresh; ListBySubject(bob) returns empty; IAM section hidden; networks page denied
**And** No stale state в session-storage (5min TTL OR explicit invalidation on 403)
**And** session-storage permission cache cleared on receiving 403 (defensive — D-13 не маскирует backend deny)
**And** Test: opening DevTools → Application → Session Storage shows empty permission-cache after 403

### 5.8 Custom Role (2 сценария)

#### Scenario E4.GWT-24: Create custom role via JSON-paste, use in binding

**ID:** 2.0-E4-GWT-24
**REQ:** REQ-IAM-UI-CUSTOMROLE-01

**Given** alice (admin) on `/iam/roles/new`

**When** alice fills:
- name: "vpc-readonly-network-only"
- description: "Read-only access to VPC Networks (no Subnets, no SGs)"
- permissions (textarea): `[{"resource":"vpc.network","action":"viewer"}]`
**And** clicks "Create"

**Then** Backend validates permissions (D-14): each permission must be в supported list
- `vpc.network/viewer` — supported → OK
- Test alt input: `vpc.network/viewer, vpc.network/DELETE` → UI ErrorBanner: "vpc.network/DELETE is not supported"
**And** Role created, Role{id: rol_custom_xxx, is_system: false}
**And** Role visible in `/iam/roles` list with "Custom" label
**And** Role available in RolePicker on AccessBindingCreateDialog
**And** alice creates binding (bob, rol_custom_xxx, prj_dev)
**And** Backend FGA tuple writer (E3) expands permissions[] → tuples (for single-permission role, this is 1 tuple: `user:usr_bob viewer vpc_network:* via project:prj_dev` resolved through DSL)
**And** Test: bob can `GET /vpc/v1/networks` в prj_dev (200) — but cannot `GET /vpc/v1/subnets` (PermissionDenied, no subnet permission)

#### Scenario E4.GWT-25: Edit custom role — add permission, validate, re-apply tuples

**ID:** 2.0-E4-GWT-25
**REQ:** REQ-IAM-UI-CUSTOMROLE-EDIT-01

**Given** alice has custom role rol_custom_xxx (network-viewer only); bob has binding via this role

**When** alice on `/iam/roles/rol_custom_xxx` clicks "Edit"
**And** Adds permission: `vpc.subnet/viewer`
**And** Submits

**Then** Backend validates new permissions list (still all in supported); accepts
**And** Backend updates role; **also** re-generates FGA tuples for all bindings using this role:
- For each binding (subject, role=rol_custom_xxx, scope) → recompute tuples → outbox writes (delete-old, write-new — OR diff-based for efficiency)
- Race-safety: backend uses idempotent FGA writes; no missing-tuple window
**And** UI confirms; within ≤10s bob can GET subnets in prj_dev (additional permission applied reactively)
**And** Test: bob's GET /vpc/v1/subnets returns 200 after delay; previously returned PermissionDenied
**And** Negative: alice tries to remove permission → bob's access shrinks via same mechanism (≤10s revoke)
**And** Negative: alice tries to add unsupported permission → InvalidArgument; role not modified; bob's existing access unchanged

---

## 6. Definition of Done (E4 closure)

| # | DoD пункт                                                                                                  | Verification                                                                                                                                                            |
|---|-------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 1 | `/signup` end-to-end working: новый user → registers → auto-bootstrap (Account+Project+owner-binding) → залогинен в UI с email в header | Playwright e2e `signup.spec.ts`; newman `e4-signup-end-to-end`; integration test `signup_complete_integration_test.go::TestFirstUserBootstrap` |
| 2 | Sidebar IAM section visible owner, hidden viewer без iam.read permission (D-4)                              | Playwright e2e `sidebar-visibility.spec.ts`; UI unit-test `<PermissionGate>.test.tsx`                                                                                  |
| 3 | CRUD pages for всех 7 ресурсов: Accounts (read-only on 2.0), Projects, Users, ServiceAccounts, Groups, Roles, AccessBindings — все CRUD operations working | Playwright e2e `iam-crud-{account,project,user,sa,group,role,binding}.spec.ts` × 7; integration tests per resource в kacho-iam (extended from E0)                       |
| 4 | AccessBinding UI: grant Subject-Role-Resource одним кликом (User/SA/Group × system/custom role × Account/Project/Resource) | Playwright `iam-binding-grant.spec.ts`; covers GWT-16, GWT-17, GWT-18                                                                                                  |
| 5 | Operations principal: UI отображает USER icon + email OR SA icon + name; filter `?principal.id=me` работает | Playwright `operations-principal.spec.ts`; UI unit-test `<CreatedByCell>.test.tsx`                                                                                       |
| 6 | Реактивность ≤10s: granted role visible в UI у нового user через ≤10s (worst-case), типично <2s            | Playwright `permission-reactivity.spec.ts` measures Δ = grant_time - first_visible_in_ui_time; assert Δ ≤ 15s (10s backend + 5s UI render budget); covers GWT-21,22,23 |
| 7 | E2E smoke: new user → signup → Account+Project owner → creates SA + Group → grants viewer-role на vpc_network → user в group sees that network в /vpc/networks list, NOT other (что не grant'ил) | Playwright `e2e-smoke.spec.ts` (full happy-path); newman `e4-smoke-multi-actor`                                                                                          |
| 8 | Concurrent signup race: 2 параллельных signup с одинаковым external_id → ровно 1 Account/user created; second получает existing | Integration test `signup_race_integration_test.go::TestConcurrentSameExternalID`; goroutines race + assertion `COUNT == 1`                                              |
| 9 | Custom role: create via JSON-paste, validate permissions, use in binding, edit propagates tuples            | Playwright `custom-role.spec.ts` (covers GWT-24, GWT-25); integration test `role_custom_permissions_integration_test.go`                                                |
| 10 | Permission heuristic UI cached в session-storage 5min, fail-open on error (D-13)                          | UI unit-test `usePermissionCheck.test.ts`; integration test mocks iam-down → assert UI not blocked, render mode permissive                                              |

**Артефакты:**
- Все integration tests зелёные в `kacho-iam`, `kacho-api-gateway`, `kacho-corelib` (operations principal — already from E2).
- Все Playwright e2e зелёные в `kacho-test` (новый infra; см. D-12).
- Все newman cases зелёные (минимум: e4-signup, e4-iam-crud-{7-resources}, e4-binding-grant, e4-binding-revoke, e4-operations-principal, e4-smoke-multi-actor, e4-custom-role).
- UI build (Vite production) passes без warnings; bundle size < 500KB gzipped (NFR-7).
- Все vault entries обновлены (см. §3.3).
- KAC-109.md финализирован: `Status: done`, все PR ссылки, чек-лист DoD заполнен.

---

## 7. Cross-repo PR-chain (порядок merge)

Топологический порядок (по `replace ../` graph из workspace `CLAUDE.md`):

| # | Repo                | Branch        | PR scope                                                                                                  | Зависит от  |
|---|---------------------|---------------|------------------------------------------------------------------------------------------------------------|-------------|
| 1 | `kacho-proto`       | KAC-109       | `iam.v1.internal_auth_service.proto` (SignupComplete); `iam.v1.auth_service.proto` (Me, Logout); расширение `iam.v1.access_binding_service.proto` (ListBySubject RPC); `operation_service.proto` filter `principal_filter` | (none)      |
| 2 | `kacho-iam`         | KAC-109       | миграции 0008-0009; `internal/apps/kacho/api/auth/{signup_complete,me}.go`; `internal/apps/kacho/api/access_binding/list_by_subject.go`; integration + unit tests | PR #1       |
| 3 | `kacho-api-gateway` | KAC-109       | `/auth/callback` handler extension (call SignupComplete); `/auth/me` REST endpoint; `/auth/logout`; restmux register | PR #1, #2 (gRPC stubs) |
| 4 | `kacho-deploy`      | KAC-109       | helm `kacho-ui` update (new build); helm `kacho-api-gateway` env update; helm `zitadel-bootstrap` enable signup-flow; helm `kacho-iam` env `KACHO_IAM_BOOTSTRAP__FIRST_USER_ADMIN=true` | PR #3 (image-tag of api-gateway) |
| 5 | `kacho-ui`          | KAC-109       | full IAM UI: 5 auth pages + 7×3=21 IAM pages + 7 RTK Query slices + 7 components; sidebar update; permission heuristic; Operations CreatedBy column; tests | PR #3 (REST contracts via api-gateway) |
| 6 | `kacho-test`        | KAC-109       | Playwright e2e suite (`signup.spec.ts`, `iam-crud.spec.ts`, `permission-reactivity.spec.ts`, `e2e-smoke.spec.ts`); docker-compose with headless Chromium; CI workflow | PR #5 (UI deployed) |
| 7 | `kacho-workspace`   | KAC-109       | этот acceptance APPROVED → DRAFT→APPROVED; vault entries; KAC-109.md → done; KAC-104 epic → 4/6 DoD checked | After all |

**Параллельность:**
- PR #1 → blocks #2, #3
- PR #2, #3 — параллельны после #1
- PR #4 — после #3 (image-tags)
- PR #5 — может start параллельно с #2/#3 (mock backend in UI dev-mode), но full integration требует #3
- PR #6 — последний (требует deployed UI)

**CI pinning:**
- В `.github/workflows/ci.yaml` каждого зависимого репо временно `ref: KAC-109` для upstream sibling'ов; снимается на merge upstream.
- Пример: kacho-ui PR CI pins `kacho-api-gateway` ref:KAC-109 → после kacho-api-gateway merged → snap to `ref: main`.

---

## 8. Risks & Mitigations

| Risk                                                                                            | Mitigation                                                                                                                                                       |
|-------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| First-user race на свежем cluster — два concurrent signup'а попадают одновременно                | Decision D-6: atomic CAS на `accounts.owner_user_id IS NULL` + advisory lock 4096 + UNIQUE `users.external_id`. Integration test `TestConcurrentFirstUserSignup` (10 goroutines simultaneously call SignupComplete with different external_ids; assert exactly 1 admin-binding created) |
| Zitadel `code` re-use во время race (D-1 OIDC) — оба handlers get same code, second exchange fails | Zitadel issues different codes per browser tab (state param differs); если same code re-used — exchange fails с specific error → api-gateway redirects to /signup?error=code_reuse. Test: simulate manual code-replay via curl |
| Custom-role permissions validation drift — frontend list != backend list                         | Single source of truth: kacho-iam exports `GET /iam/v1/permissions` (returns supported permissions list); UI fetches at app-bootstrap, uses for textarea validation hint (не enforcement; backend is source of truth) |
| Permission heuristic cache stale → UI shows enabled-button while backend says deny             | Defensive: backend always wins (PermissionDenied returned); UI heuristic — UX-hint, not enforcement (D-4 — explicit acceptance). When 403 received → invalidate cache + show ErrorBanner; user sees correct state after one stale-click |
| RTK Query polling load — UI re-fetches lists too often, drowns backend                          | Default `keepUnusedDataFor: 60s`; `refetchOnFocus: true` (re-fetch on tab focus); no aggressive interval polling. UI permission cache TTL 5min (D-4); subject lookup cache в gateway уже 30s+NOTIFY (E2/E3). Net: per-tab ≤ 1 ListBySubject per 5min = negligible |
| Playwright flakiness — timing-sensitive reactivity tests (NOTIFY propagation jitter)            | Polling assertion (Playwright's `expect(...).toPass({ timeout: 15000 })`) вместо fixed-sleep; assertion checks specific DOM state, not arbitrary delay |
| UI bundle size grows — adding 21+ pages may break NFR-7 (<500KB gzipped)                       | Code-splitting per route (React.lazy + Suspense); IAM module loaded only when /iam/* accessed; tree-shake Lucide icons (named imports). Measure via `vite build --report` |
| Cookie management cross-domain — UI на `api.kacho.local`, Zitadel на `login.kacho.local`        | Same parent-domain `kacho.local` для cookie scope; CORS-headers configured в kacho-api-gateway для Zitadel-callback origin; test cross-origin flow в Playwright |
| First-user-admin disable — admin может accidentally revoke alice's binding и lock self out      | UI safeguard: при DELETE binding с `subject_id == me && role == admin && scope == account` — confirm dialog «WARNING: this will lock you out». Backend safeguard: `kacho-iam.AccessBindingService.Delete` validates что хотя бы 1 admin@account binding existes до allow delete — иначе `FailedPrecondition: "cannot remove last admin"` |

---

## 9. Out of Scope (явно отложено)

| Тема                                                                | Куда вынесено                                  |
|----------------------------------------------------------------------|------------------------------------------------|
| MFA / WebAuthn / TOTP enrollment via UI                             | Phase 2.1 (Zitadel feature; UI shows static link to Zitadel MFA settings) |
| External invite via email (admin sends email с signup-link)         | Phase 2.1                                      |
| Cross-Account sharing (binding subject from account A to project в account B) | Phase 3.0                                      |
| Quota / billing UI                                                  | Phase 3.x                                      |
| Audit log UI (показ событий из kacho-audit)                         | Phase 2.1 (после `kacho-audit` сервис)         |
| Visual custom-role permission builder (drag-drop / checkboxes)      | Phase 2.1                                      |
| Personal Access Tokens (PAT) для users — alternative to cookie-session for CLI use | Phase 2.1+                                |
| Account-switcher (multi-Account user)                               | Phase 3.0                                      |
| UI internationalization (i18n)                                      | Phase 2.1+                                     |
| Dark mode for IAM pages (existing dark mode applies, но IAM не tested) | Phase 2.1 (test pass)                          |
| Real-time WebSocket subscription для UI list-views                  | Phase 3+ (Watch API revival or SSE)            |
| Profile page для user — edit display_name, avatar                   | Phase 2.1 (Zitadel manages user info; UI links to Zitadel profile) |
| `Audit` field в Operation table (who, when, what changed before/after) | Phase 2.1 (kacho-audit)                        |
| Group nesting (groups containing groups)                            | Phase 2.1+ (FGA DSL supports, но complexity)   |
| RBAC + tags (tag-based scope: `tag:env=prod`)                       | Phase 2.2+ (ABAC)                              |

---

## 10. Связь с регламентом (повтор для reviewer)

- **Запрет #1** (acceptance before code): этот документ + reviewer cycle до APPROVED.
- **Запрет #2** (no yandex): все error-texts / env / proto-fields / UI labels — kacho-namespace / Kachō.
- **Запрет #4** (no cross-service cascade): Account.Delete / Project.Delete возвращают `FailedPrecondition` если есть owned-resources; UI отрисовывает удобный hint.
- **Запрет #6** (Internal not on external TLS): `InternalAuthService.SignupComplete` — :9091 cluster-internal; gRPC-direct от api-gateway; **НЕ** в restmux; rationale same loop-prevention как E2 §3.3.
- **Запрет #7** (no broker): RTK Query invalidation + backend NOTIFY (E3 reuse) для реактивности; никакого Kafka.
- **Запрет #8** (DB-per-service): kacho_iam, openfga, zitadel — раздельные БД; users mirror в kacho_iam, Zitadel users в zitadel DB (link только по external_id строке).
- **Запрет #9** (no sync resource return): `SignupComplete` возвращает Operation (corelib); UI handles полл.
- **Запрет #10** (DB-уровень refcheck): first-user race — atomic CAS + advisory lock (§4.2); UNIQUE `users.external_id` (E0); UNIQUE `accounts.owner_user_id` (partial).
- **Запрет #11** (tests-required в том же PR): §6 DoD каждый пункт линкуется на конкретный test-файл (integration / newman / Playwright).

**evgeniy regulation:**
- §2 (use-case pattern): `internal/apps/kacho/api/auth/{signup_complete,me}.go`; `internal/apps/kacho/api/access_binding/list_by_subject.go` — каждый use-case в отдельном файле.
- §4 (self-validating domain): `Email`, `ExternalID`, `DisplayName` newtypes уже из E0; добавляется `PermissionStr` newtype для custom-role validation.
- §5 (DB-level invariants): см. §10 запрет #10 выше.
- §6 (CQRS Reader/Writer): `auth_writer.go` (TX bootstrap) vs `access_binding_reader.go::ListBySubject` (read query).
- §16 (outbox + LISTEN): backend NOTIFY уже из E3 (subject_change_outbox + fga_tuple_writer outbox); UI consumes results via RTK Query refetch on focus.

---

## 11. Open Questions (для acceptance-reviewer)

1. **Cookie scope cross-domain**: UI на `api.kacho.local`, Zitadel на `login.kacho.local`. Cookie scope `Domain=.kacho.local`? Это включает оба sub-domain. Безопасно ли (зависит от какие ещё sub-domains есть). **Предложение**: на dev — ок (полный контроль); на prod — separate cookie per origin, exchange через explicit callback. Уточнить в reviewer.

2. **Welcome page для first-user — что показывать**: tour, quick-start, или просто landing с link на docs? **Предложение**: minimal `/welcome` с congratulations + 3-link tour: "Create your first VPC Network" + "Invite team members" + "Create Service Account for CI"; full onboarding — Phase 2.1.

3. **Bob (subsequent user без bindings) — что показывать на /**: empty dashboard + ErrorBanner "Contact admin to get access" или explicit `/no-access` page? **Предложение**: explicit `/no-access` page; cleaner UX для subsequent-user state.

4. **Permission cache TTL для UI**: 5min достаточно? Если admin grants role, user должен явно reload (5min stale-window). Альтернатива — TTL 30s (более responsive, но больше backend load). **Предложение**: TTL 5min + invalidation on focus (RTK Query default) — net result типично <1min между refetch'ами при active использовании.

5. **Custom-role permission validation — strict vs permissive**: D-14 strict reject. Альтернатива — accept role, skip unsupported permissions при FGA-expansion (с warning в response). **Предложение**: strict (D-14) на E4; permissive — Phase 2.1 с UI warning UX. Уточнить.

6. **Playwright in CI vs manual**: e2e tests slow (минуты), run on every PR vs только nightly? **Предложение**: PR — smoke subset (signup + 1 CRUD per resource = ~3min); nightly — full suite (~15min). CI pipeline split в `kacho-test/.github/workflows/`.

7. **«Last admin» safeguard backend OR UI-only?** Risks-table mentions: «admin может accidentally revoke self». Backend safeguard надёжнее (catches API-direct via grpcurl), UI-only — UX-only. **Предложение**: оба — UI confirm + backend `FailedPrecondition` если delete-binding оставит acc_default без admin@account.

8. **Operations principal filter — UI или backend default?** UI «My operations» tab applies `?principal.id=me`. Также «All operations» tab (admin sees все). Backend должен принимать filter — это уже в proto (E4 PR #1). **Предложение**: backend supports filter; UI выбор tab.

9. **Что показывать в Header для SA-issued requests?** Operations created by SA — clear; но SA не logs into UI (SA — programmatic). Header показывает только UI-logged-in user. **Решение**: clear — header — user only; SA visible only в Operations table «Created by».

10. **`kacho-yc-shim` для signup-CLI**: будущий `yc init` / `yc auth login` flow? Out-of-scope (overview §9: «yc-shim» = Phase 2.1+); E4 focus только на UI signup.

---

## 12. Changelog

- **2026-05-17 — DRAFT v1**: первая полноразмерная версия (`acceptance-author` agent). Расширение STUB-предшественника (170 lines) в полный GWT-разбор: 25 сценариев (3+3+2+7+3+2+3+2 = 25), 10 DoD пунктов, Decision Log из 15 пунктов, Cross-repo PR-chain (7 репо), Risks/Mitigations, Out-of-Scope (15+ items), Open Questions (10). Awaiting `acceptance-reviewer`.
