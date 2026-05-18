# Sub-phase 2.0 — IAM KAC-125: User-Invite-Flow + User-per-Account + Cascader-driven AccessBindings — Acceptance

> **Status**: DRAFT v4 — awaiting `acceptance-reviewer` round 4 APPROVED (после v3-round-3 review: 3 новых blocker'а NEW-B9/B10/B11 + 2 major'а MAJ-1/2 + 1 minor MIN-1 закрыты).
> **Date**: 2026-05-18
> **YouTrack**: KAC-125 (vault label, YT-counter будет заведён отдельно). Predecessors: [KAC-123](https://prorobotech.youtrack.cloud/issue/KAC-123) (Group default-deny + UI AccessBindings visibility + AccountCrumb fix), [KAC-124](https://prorobotech.youtrack.cloud/issue/KAC-124) (resource-manager removal). Parent epic: [KAC-104](https://prorobotech.youtrack.cloud/issue/KAC-104).
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer` (gate per запрет #1 workspace `CLAUDE.md`).
> **Target repos**: `kacho-iam`, `kacho-proto`, `kacho-api-gateway` (минорно — internal mux), `kacho-ui`, `kacho-test` (Playwright).
> **Target cluster**: `e2c825` (dev) после deploy.

---

## 0. Преамбула — что эта итерация

KAC-125 — финальный недостающий кусок IAM-эпика KAC-104: **invite-flow** (admin Project'а приглашает другого user'а по e-mail) + **переход User-row'ов на per-Account scope** + **UI «Права доступа» с AntD-Cascader** (`<module>/<resource>/<verb>`) вместо плоского role-dropdown. После KAC-123 (default-deny на all-subject list RPC) и KAC-124 (removal kacho-resource-manager) платформа умеет cовершенно изолированных tenant'ов, но **не умеет принимать новых сотрудников в существующий Account** — это «дыра» UX, на которую обращает внимание заказчик: «не могу пригласить коллегу к себе в Project». Эта итерация её закрывает.

### 0.1 Scope (что входит)

1. **Schema migration kacho_iam** — `users.account_id` (FK to accounts NOT NULL), `users.invite_status` (enum), `users.invited_by` (nullable self-FK), drop `UNIQUE(external_id)` global → `UNIQUE(account_id, external_id)`, добавить `UNIQUE(account_id, email)`. Greenfield reset допустим (см. §5).
2. **Новый RPC** `kacho.cloud.iam.v1.UserService.Invite(account_id, email, role_id?, project_id?)` — invite-or-bind use-case.
3. **Изменение существующего RPC** `InternalUserService.UpsertFromIdentity` — теперь PENDING-aware: ищет PENDING-row по email перед созданием нового Account.
4. **Изменение default-deny matrix** — `UserService.List` по умолчанию scope'ится `account_id IN (accounts where principal is member)`.
5. **Keto-relation `member` на namespace `account`** — Account-membership tuple для каждого active User-row.
6. **UI** — новая страница `/iam/access` (rename из `/iam/access-bindings`, redirect старого URL): табы Облако (Account) / Каталог (Project), модалка «Выдача доступа» с email-autocomplete + AntD-Cascader для ролей + invite-fallback CTA при ненайденном email.
7. **Playwright** e2e в `kacho-test`: 5 сценариев под invite-flow + cascader-выбор + cross-Account isolation.

### 0.2 НЕ-scope (явно отложено)

- **E-mail доставка** (D-1). Magic-link генерируется Kratos recovery flow, но **никуда не отправляется** автоматически. Admin вручную копирует ссылку из UI / API-response либо ждёт, когда invitee сам зайдёт на `/registration` и Kratos смэтчит по email. SMTP-интеграция — отдельный последующий тикет.
- **MFA / WebAuthn на invitee** — поверх Kratos идёт «как есть», не enforce'им WebAuthn на первом login.
- **Cross-Account invite** (e-mail invitee уже принадлежит другому Account как owner) — допускается через создание **второй** User-row для того же Kratos identity (новый Account-scope), см. сценарий §7.S-03.
- **Bulk-invite** (CSV-загрузка) — отложено; UI принимает одного user'а за раз.
- **Invite-revoke / resend** — отложено (только PENDING→ACTIVE, без PENDING→CANCELLED API). Удаление PENDING-row делается через стандартный `UserService.Delete`.
- **Custom-roles UI** — таб «Свои роли» в Cascader присутствует, но **read-only пустой** до отдельной фичи кастом-ролей (KAC-122+).
- **Group-invite** — invite только индивидуального user'а; добавление в Group делается отдельно через `GroupService.AddMember` после Activation.

### 0.3 Decisions (зафиксированы до review)

| ID  | Decision | Rationale |
|-----|----------|-----------|
| **D-1** | Invite **БЕЗ email-sending**. Backend генерирует Kratos recovery flow (magic-link), но НЕ доставляет — admin копирует URL вручную ИЛИ invitee сам идёт на `/registration` с тем же email (Kratos матчит PENDING-row). | SMTP-интеграция требует MTA-инфры (SES/SendGrid). На фазу 2.0 — out-of-scope (см. overview-acceptance §9). Email-stub закладывает интерфейс, не блокирует UX. |
| **D-2** | UI выбор ролей — **AntD Cascader** (`<module>/<resource>/<verb>`), не flat Select. | Source role-catalog (KAC-121/KAC-122) — 54+ system-role, плоский dropdown нечитаем. Cascader позволяет показать hierarchy + drilldown + многократный выбор через chip-list. |
| **D-3** | **User-row per Account, не per Project**. Один Kratos identity → N User-row (по одному per Account). Внутри Account user может быть в M Project через AccessBinding. | Account = tenant-граница (KAC-118 default-deny). Per-Project user сделал бы invite на каждый Project бессмысленным (он бы создавал N rows для одного Account). Per-Account — оптимальный grain. |
| **D-4** | **Bootstrap-account remain unchanged**. Самостоятельная регистрация через `/registration` без pending-invite → continue auto-create новый Account + Project (KAC-117). Меняется только code-path, когда PENDING-row уже есть. | Не ломаем существующий self-signup-flow KAC-117. |
| **D-5** | **System-roles tab отделен от custom-roles tab** в модалке. Custom-tab — пустой stub на E0 (until KAC-122+). | UX: разделение «готовые роли (54 system)» vs «свои роли (0 пока)» — снижает когнитивную нагрузку. |
| **D-6** | URL rename `/iam/access-bindings → /iam/access` + 301 redirect. | YC-парность по форме ([CLAUDE.md](../../CLAUDE.md) «YC-стилистика — да, структура — по делу»). `/iam/access-bindings` оставался техническим именем raw-таблицы; «Права доступа» — user-facing раздел. |
| **D-7** | **invited-only-user НЕ получает свой собственный Account по умолчанию**: после `UpsertFromIdentity` если есть PENDING-row(s) — они активируются, а bootstrap-Account **skip**-ается (даже если у user'a нет ACTIVE-row нигде). Чтобы получить свой Account, user должен явно нажать «Создать организацию» в UI (`POST /iam/v1/accounts`). | Резолвит race с KAC-117 self-signup: если invitee имеет PENDING-invite в acc-A и идёт на `/registration`, мы НЕ должны создать ему **третий** auto-Account (acc-Y) поверх активации PENDING. Активация PENDING — primary intent. Self-Account создаётся **только** если invitee явно его попросит (отдельным CTA в UI). Mitigation для R-5: однозначный приоритет PENDING-активации над bootstrap-create. |
| **D-8** | **`UserService.Create` deprecated, не удалён**: в proto ставится `option deprecated = true;` (не удаляется → `buf breaking` зелёный); gRPC handler возвращает `FailedPrecondition "Use UserService.Invite instead"`. REST `POST /iam/v1/users` возвращает `410 Gone`. После 1 release-cycle (когда все клиенты обновлены) — удаляется в KAC-126-followup. **D-8 затрагивает только публичный `UserService.Create` (public-port 9090)** — internal bootstrap-path `InternalUserService.UpsertFromIdentity → bootstrapNewIdentity` (internal-port 9091) НЕ deprecated, это самостоятельный flow для self-signup новых identities (см. §3.2 step 3, S-06). | `buf breaking` остаётся зелёным (deprecation — non-breaking); клиенты получают чёткое сообщение «миграция на Invite». Не ломаем backward-compat на proto-level прямо сейчас. |
| **D-9** | **Cascade в коде + post-invite primary context**. (1) **Authz model**: cascade `owner > admin > editor > viewer → member` реализуется **client-side в Go-helper'е** `KetoClient.relationsImplying` (existing pattern из KAC-119/120/121, не меняется). Keto держит **прямые tuples** (`account:<id>#<rel>@user:<id>`). `UserService.Invite` вызывает `CanInviteUsers(principal, account)` — это **один Check call** с relation `"editor"`; `relationsImplying("editor") = ["editor","admin","owner"]` — cascade-traversal внутри helper'а покрывает все три relations. `viewer` invite'ить не может (cascade-выше editor нет). OPL **НЕ используется**, namespace-config Keto остаётся в существующей **flat form** `namespaces: [{id, name}]` (`kacho-deploy/helm/umbrella/values.dev.yaml`). Permission `iam.user.create` — docstring-marker в proto (semantic), не Keto-construct. (2) **Post-invite primary context**: после `UpsertFromIdentity` response.user возвращает **first-activated User-row** (PENDING→ACTIVE). UI на post-login flow читает это поле и автоматически переключает context на тот Account. Если у user есть и existing ACTIVE-row в другом Account, и новые activated — приоритет у новых (assumption: invitee только что pressed "Accept Invite", вероятно его primary intent — посмотреть новую среду). User в UI может вручную переключить context через BreadcrumbSelector. | (1) Cascade в коде уже реализован в KAC-119+ (`relationsImplying`); расширять Keto-config'ом subject-set rewrite избыточно и нарушает существующую архитектуру. Один Check call с cascade-traversal в helper'е — минимальное изменение, race-safe, и сразу integration-tested. (2) UX: invitee только что кликнул на magic-link — primary intent смотреть новую среду; если переключение нужно сделать вручную, теряется flow. |

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** (workspace) — code только после `acceptance-reviewer` APPROVED | этот документ — gate; статус сейчас DRAFT |
| **Запрет #2** — НЕ «yandex» | формулировки в proto/UI/ошибках следуют YC-стилю **формы** (не структуры — см. §2.5); ни одного `yandex` в коде |
| **Запрет #3** — НЕ ORM | sqlc + handwritten pgx; новые методы Repo через evgeniy §6 (Reader/Writer split) |
| **Запрет #5** — НЕ редактировать применённую миграцию | новая миграция `000N_user_per_account_invite.sql` поверх существующих |
| **Запрет #6** — Internal.* НЕ на external TLS endpoint | `InternalUserService.UpsertFromIdentity` остаётся на internal-port 9091; новый `UserService.Invite` — публичный (рядом с Create/Get/List) на 9090 |
| **Запрет #8** — DB-per-service | `users.account_id` FK — within-`kacho_iam`; cross-service `project_id` (если invite с pre-bind на Project) — soft-ref, валидация через `ProjectService.Get` peer-call (own service же, не cross-DB) |
| **Запрет #9** — async-only мутации | `UserService.Invite` возвращает `operation.Operation` (LRO); Activate-on-first-login через `InternalUserService.UpsertFromIdentity` — тоже async (как сейчас) |
| **Запрет #10** — within-service refs на DB-уровне | `users.account_id FK ON DELETE RESTRICT` + `UNIQUE(account_id, email)` + `UNIQUE(account_id, external_id)` — атомарный INSERT с conflict-resolution через `INSERT ... ON CONFLICT (account_id, email) DO UPDATE` для idempotency; никаких software check-then-act |
| **Запрет #11** — тесты в том же PR | каждый PR содержит: integration-tests (testcontainers, concurrent invite race), newman happy + negative, Playwright e2e (5 сценариев из §7) |
| **evgeniy skill §2** (UseCases vs Services) | Invite — отдельный файл `internal/apps/kacho/api/user/invite.go` (не дописываем в `create.go`) |
| **evgeniy skill §4** (self-validating domain) | новые newtypes `InviteStatus` (`PENDING`/`ACTIVE`/`BLOCKED` enum), `Email` (RFC 5321 lite, уже есть) — `Validate()` на каждом |
| **evgeniy skill §5** (DB-уровень валидации) | `users_invite_status_check`, `users_invited_by_consistency_check` (`invite_status='PENDING'` ⇒ `external_id=''`; `invite_status='ACTIVE'` ⇒ `external_id <> ''`) |

---

## 2. Глоссарий / доменная модель (нормативно)

### 2.1 Изменение модели User

**До KAC-125** (current): `users.id` PK; `users.external_id` UNIQUE globally (Kratos `sub` claim); один Kratos identity = одна User-row глобально; auto-create Account + Project + 3 self-grant AB при первой регистрации (KAC-117).

**После KAC-125**: `users.id` PK; **`users.account_id` NOT NULL FK** → `accounts(id)` ON DELETE RESTRICT; `users.external_id` MAY быть `''` (пустая строка) пока invite-status=`PENDING`; UNIQUE `(account_id, email)` + UNIQUE `(account_id, external_id) WHERE external_id <> ''`. Один Kratos identity → **N User-rows** (один per Account, в который invited или которым владеет).

```
До:
   Kratos identity X  ←→  User(usr-X) (1:1 global)
        ↓ owns
     Account A
     Account B  ← НЕ возможно (один user может owner'ить N Accounts, но User-row один)

После:
   Kratos identity X  ←→  User(usr-X-in-A) → Account A
                          User(usr-X-in-B) → Account B
                          User(usr-X-in-C) → Account C  (invited)
```

### 2.2 Поле invite_status (enum)

```sql
CREATE TYPE kacho_iam.invite_status AS ENUM ('PENDING', 'ACTIVE', 'BLOCKED');
```

- **PENDING** — User-row создан через `UserService.Invite`, но invitee ещё не сделал first-login. `external_id=''`, `email` указан, `display_name=email` (placeholder). НЕ участвует в Keto member-tuples (default-deny).
- **ACTIVE** — User-row либо создан через self-signup (`UpsertFromIdentity` без pending-invite), либо PENDING-row активирован при first-login (matched by email). `external_id <> ''`. Participates в Keto member-tuple `account#member`.
- **BLOCKED** — admin Account'а заблокировал user'а (reserved для будущей фичи; на E0 поле есть, но никакой RPC не выставляет `BLOCKED`).

### 2.3 Поле invited_by (nullable self-FK)

```sql
invited_by TEXT NULL REFERENCES kacho_iam.users(id) ON DELETE SET NULL
```

- При self-signup → `invited_by IS NULL`.
- При invite → `invited_by = <user.id of admin who invoked Invite>`.
- При delete invited_by-user → `SET NULL` (не cascade, не RESTRICT — invite-trail сохраняется как «приглашение от удалённого admin'а»).

### 2.4 Изменения в Schema (миграция)

Файл: `kacho-iam/internal/repo/kacho/pg/migrations/0009_user_per_account_invite_kac125.sql` (порядковый номер после `0001_initial.sql`, `0002_fga_outbox.sql`, …, `0007/0008_role_catalog`; точный — после baseline-аудита).

```sql
-- 1. invite_status enum
CREATE TYPE kacho_iam.invite_status AS ENUM ('PENDING', 'ACTIVE', 'BLOCKED');

-- 2. drop global UNIQUE on external_id (it becomes per-account uniqueness)
ALTER TABLE kacho_iam.users DROP CONSTRAINT users_external_id_unique;

-- 2a. relax existing CHECK on external_id to allow empty string for PENDING-rows
--     (PENDING-row имеет external_id='' до first-login).
ALTER TABLE kacho_iam.users DROP CONSTRAINT IF EXISTS users_external_id_check;
ALTER TABLE kacho_iam.users
    ADD CONSTRAINT users_external_id_check CHECK (length(external_id) BETWEEN 0 AND 256);

-- 3. add account_id (NOT NULL; greenfield — no backfill, см. §5),
--    плюс invite_status / invited_by.
--    account_id FK — DEFERRABLE INITIALLY DEFERRED, потому что bootstrap-flow
--    делает (INSERT user → INSERT account) в одной TX (см. §2.4.5).
ALTER TABLE kacho_iam.users
    ADD COLUMN account_id TEXT NOT NULL
        REFERENCES kacho_iam.accounts(id) ON DELETE RESTRICT
        DEFERRABLE INITIALLY DEFERRED,
    ADD COLUMN invite_status kacho_iam.invite_status NOT NULL DEFAULT 'ACTIVE',
    ADD COLUMN invited_by TEXT NULL REFERENCES kacho_iam.users(id) ON DELETE SET NULL;

-- 3a. сделать существующий accounts.owner_user_id FK тоже DEFERRABLE
--     (иначе bootstrap-INSERT account первым ловит FK violation на owner_user_id).
ALTER TABLE kacho_iam.accounts
    DROP CONSTRAINT accounts_owner_fk;
ALTER TABLE kacho_iam.accounts
    ADD CONSTRAINT accounts_owner_fk
        FOREIGN KEY (owner_user_id) REFERENCES kacho_iam.users(id) ON DELETE RESTRICT
        DEFERRABLE INITIALLY DEFERRED;

-- 4. new uniqueness:
--    - email уникален в Account (case-insensitive),
--    - external_id уникален в Account ТОЛЬКО для ACTIVE-rows (где external_id<>'').
--      PENDING-rows имеют external_id='' и НЕ конфликтуют между собой
--      благодаря partial-UNIQUE WHERE clause.
CREATE UNIQUE INDEX users_account_email_unique
    ON kacho_iam.users (account_id, lower(email));
CREATE UNIQUE INDEX users_account_external_id_unique
    ON kacho_iam.users (account_id, external_id)
    WHERE external_id <> '';

-- 5. consistency CHECK: PENDING ⇔ external_id='' ; ACTIVE/BLOCKED ⇔ external_id<>''
ALTER TABLE kacho_iam.users
    ADD CONSTRAINT users_invite_status_consistency CHECK (
        (invite_status = 'PENDING' AND external_id = '') OR
        (invite_status IN ('ACTIVE','BLOCKED') AND external_id <> '')
    );

-- 6. index for email-based lookup (cross-account, для UpsertFromIdentity)
CREATE INDEX users_email_lower_idx ON kacho_iam.users (lower(email));
```

### 2.4.5 Bootstrap-TX и DEFERRABLE FK (chicken-and-egg)

**Проблема**: `users.account_id NOT NULL FK → accounts(id)` ↔ `accounts.owner_user_id FK → users(id)` — cyclic FK. Создать первый user / первый account невозможно последовательно: какой бы insert ни шёл первым, FK target не существует.

**Решение** (зафиксировано в SQL §2.4 шаги 3, 3a): оба FK помечены `DEFERRABLE INITIALLY DEFERRED`. Это значит, что FK-check выполняется не на каждой строке-инсерте, а на `COMMIT` транзакции. Внутри одной TX можно insert'ить «пока неконсистентные» строки и сделать их консистентными к моменту commit.

> **Pseudo-code note** (M5): записи вида `repo.Writer(ctx).Transact(func(w Writer) error { ... })` ниже и далее в этом acceptance — упрощённая нотация. Реальная реализация — через `corelib/db.Transactor.InTx(ctx, func(tx pgx.Tx) error { ... })`, где `tx` передаётся в writer-методы (`w := repo.WriterWithTx(tx)`). См. existing pattern в `kacho-iam/internal/apps/kacho/api/account/create.go::doCreate`.

**`bootstrapNewIdentity` (use-case)** оборачивается в одну TX:

```go
func (uc *UpsertFromIdentityUseCase) bootstrapNewIdentity(ctx, payload) (*User, error) {
    return uc.repo.Writer(ctx).Transact(func(w Writer) error {
        accountID := ids.NewAccountID()     // pre-generate UUID
        userID    := ids.NewUserID()        // pre-generate UUID
        projectID := ids.NewProjectID()     // pre-generate UUID for default project
        isBootstrapAdmin := strings.HasSuffix(payload.Email, "@prorobotech.ru")

        // 3.1. INSERT user первым: account_id указывает на ещё-не-существующий account.
        //      FK check отложен до COMMIT.
        if err := w.InsertUser(ctx, User{
            ID:           userID,
            AccountID:    accountID,        // <-- forward reference
            ExternalID:   payload.ExternalID,
            Email:        payload.Email,
            DisplayName:  payload.DisplayName,
            InviteStatus: "ACTIVE",
            InvitedBy:    "",
        }); err != nil { return err }

        // 3.2. INSERT account: owner_user_id указывает на userID, account.id = accountID.
        if err := w.InsertAccount(ctx, Account{
            ID:          accountID,
            OwnerUserID: userID,
            Name:        "Personal cloud",
        }); err != nil { return err }

        // 3.3. INSERT default project (KAC-117 preserve).
        if err := w.InsertProject(ctx, Project{
            ID:        projectID,
            AccountID: accountID,
            Name:      "default",
        }); err != nil { return err }

        // 3.4. INSERT 2 self-grant AccessBinding rows в той же TX
        //      (KAC-117 self-signup preserve, B7 fix).
        //      ВСЕГДА 2 rows (account-admin + project-admin), regardless of bootstrap-admin.
        //      System-admin marker для bootstrap-admin'а — НЕ AccessBinding, а
        //      Keto-tuple kacho_system:root#admin@user:<id> (см. step 3.5).
        //
        //      Role-IDs вычисляются через sysRoleID(name) = "rol" + md5(name).hex.first(17)
        //      — детерминированно из catalog seed (KAC-122 миграция 0008_role_catalog_kac122.sql).
        //      "rol-iam-account-admin" / "rol-iam-project-admin" / "rol-system-admin"
        //      — placeholder-имена; реальные ID получаются из catalog'а.
        abs := []AccessBinding{
            {SubjectType: "user", SubjectID: userID, RoleID: sysRoleID("iam.account.admin"),
             ResourceType: "account", ResourceID: accountID},
            {SubjectType: "user", SubjectID: userID, RoleID: sysRoleID("iam.project.admin"),
             ResourceType: "project", ResourceID: projectID},
        }
        for _, ab := range abs {
            if err := w.InsertAccessBinding(ctx, ab); err != nil { return err }
        }

        // 3.5. EnqueueOutboxEvents в той же TX (Keto-writer worker picks up async, idempotent).
        //      Explicit member-tuple для idempotency + test-determinism (cascade
        //      реализуется client-side в Go-helper'е relationsImplying §2.6, прямой
        //      tuple даёт детерминированную проверку и упрощает unit-tests + keto-cli).
        //      bootstrap-admin (email matches @prorobotech.ru) → +1 Keto-tuple на
        //      kacho_system:root (НЕ extra AccessBinding — system-admin marker ONLY Keto-tuple).
        ketoEvents := []OutboxEvent{
            {Type: "keto_write", Tuple: "account:" + accountID + "#admin@user:" + userID},
            {Type: "keto_write", Tuple: "account:" + accountID + "#member@user:" + userID},
            {Type: "keto_write", Tuple: "project:" + projectID + "#admin@user:" + userID},
        }
        if isBootstrapAdmin {
            ketoEvents = append(ketoEvents, OutboxEvent{
                Type: "keto_write", Tuple: "kacho_system:root#admin@user:" + userID,
            })
        }
        for _, e := range ketoEvents {
            if err := w.EnqueueOutboxEvent(ctx, e); err != nil { return err }
        }

        // 3.6. COMMIT — все FK-связи становятся валидными одновременно,
        //      DEFERRABLE FK-check проходит на COMMIT.
        return nil
    })
}

// sysRoleID — детерминированный lookup из KAC-122 catalog seed.
// Алгоритм: "rol" + md5(name).hex.first(17). Реальные значения seed-ятся
// миграцией 0008_role_catalog_kac122.sql и доступны через repo.Roles().GetByName(ctx, name).
// Никаких hardcoded "rol-iam-account-admin" — это placeholder для читаемости.
func sysRoleID(name string) string { /* lookup в role-catalog */ }
```

**Invite-flow** (UpsertPendingInvite) — НЕ затрагивается этим механизмом: account уже существует к моменту invite (admin invite'ит в свой Account), `accounts.owner_user_id` уже валиден, новый PENDING-user-row имеет `account_id = <existing acc>`. FK-check можно было бы оставить immediate, но единообразный DEFERRABLE проще на уровне schema (никаких per-statement `SET CONSTRAINTS IMMEDIATE`).

**D-8 boundary clarification** (B7): `UserService.Create` deprecated **только** в публичном `UserService` (public-port 9090). Internal bootstrap-path `InternalUserService.UpsertFromIdentity → bootstrapNewIdentity` (internal-port 9091) — НЕ deprecated, это самостоятельный self-signup flow для новых Kratos identities. Шаги 3.1-3.6 выше — это путь self-signup, который выполняется только если `!activatedAny && existing == nil` (см. §3.2 step 3).

### 2.5 Изменения в proto

Файл: `kacho-proto/proto/kacho/cloud/iam/v1/user_service.proto`.

```protobuf
// EXISTING messages:
message User {
  string id = 1;
  string external_id = 2;
  string email = 3;
  string display_name = 4;
  google.protobuf.Timestamp created_at = 5;
  // NEW fields (KAC-125)
  string account_id = 6;
  InviteStatus invite_status = 7;
  string invited_by = 8;   // user.id of admin; "" if self-signup
}

enum InviteStatus {
  INVITE_STATUS_UNSPECIFIED = 0;
  PENDING = 1;
  ACTIVE = 2;
  BLOCKED = 3;
}

// NEW RPC:
rpc Invite(InviteUserRequest) returns (operation.Operation);

message InviteUserRequest {
  string account_id = 1;                            // required (target Account)
  string email = 2;                                  // required (RFC 5321 lite)
  // optional pre-bind to a Project — if set, после Activate user сразу получит AB
  string project_id = 3;
  string role_id = 4;                                // required IFF project_id set
  string display_name = 5;                           // optional, defaults to email-local
}

message InviteUserMetadata {
  string user_id = 1;
  string account_id = 2;
  // NEW (D-1, R-1): Kratos recovery flow URL.
  // Admin копирует ссылку вручную (SMTP-delivery out of scope, см. D-1).
  // Если invitee уже ACTIVE в этом Account (idempotent re-invite) — поле пустое.
  string magic_link_url = 3;
}

// CHANGED ListUsersRequest (default-deny):
message ListUsersRequest {
  // EXISTING:
  int64 page_size = 1;
  string page_token = 2;
  // NEW: filter by account; defaults to "all accounts where principal is member"
  string account_id = 3;
}

// CHANGED UserService.Create — deprecated (D-8).
// Метод остаётся в proto с `option deprecated = true;`,
// gRPC handler возвращает FailedPrecondition с подсказкой использовать Invite,
// REST `POST /iam/v1/users` возвращает 410 Gone.
// `buf breaking` остаётся зелёным (deprecation — non-breaking).
rpc Create(CreateUserRequest) returns (operation.Operation) {
  option deprecated = true;
}
```

**Naming** соответствует YC-стилю формы (`InviteUserRequest`/`InviteUserMetadata`/глагол на верхнем уровне сервиса), как `CreateUserRequest`/`CreateUserMetadata`.

### 2.6 Keto authz model — cascade в коде (без OPL / subject-set rewrite)

Файл: `kacho-iam/internal/clients/keto_client.go` (Go-cascade helper) + namespace config `kacho-deploy/helm/umbrella/values.dev.yaml` (existing flat list).

**Архитектура**: KAC-119/120/121 закрепили подход — Keto держит **прямые tuples** (`account:<id>#<rel>@user:<id>`, `project:<id>#<rel>@user:<id>`, и т.п.); cascade `admin > editor > viewer → member` реализуется **client-side в Go-helper'ах** (`kacho-iam/internal/clients/keto_client.go::relationsImplying`). Этот подход **сохраняется** в KAC-125 — НЕ требует config-upgrade Keto-сервера, НЕ требует build-pipeline OPL→compile→apply.

**Текущий namespace-config Keto** (`kacho-deploy/helm/umbrella/values.dev.yaml:432-477`) — **flat form** `namespaces: [{id, name}]`, БЕЗ `relations:` / `union:` / `computed_subjectset`. Этот config не меняется в KAC-125.

**Relations в namespace `account`** (логические, реализованные client-side; existing flat namespace config + новая `member`-семантика):
- `owner` — implicit single owner (`accounts.owner_user_id`; этот relation **не пишется** в Keto явно — owner-check делается через SQL-чтение `accounts`-row).
- `admin` — full control (создавать/удалять Projects, invite users, manage roles).
- `editor` — управляет ресурсами (cascade включает member-доступ к Account).
- `viewer` — read-only (cascade включает member).
- `member` — **NEW в KAC-125** — базовый indicator «user belongs to this Account». Cascade реализуется client-side: при `Check(user:X, member, account:A)` helper делает OR над `Check(admin) || Check(editor) || Check(viewer) || direct-member-check`.

**`relationsImplying` (existing Go-helper, расширяется в KAC-125)**:

```go
// kacho-iam/internal/clients/keto_client.go (existing pattern, extended).
//
// relationsImplying возвращает список relations, которые implication-сильнее заданной
// (т.е. если у user есть любая из них, то и заданная — гарантирована).
// Cascade определён в коде; Keto держит только прямые tuples.
func relationsImplying(rel string) []string {
    switch rel {
    case "viewer": return []string{"viewer", "editor", "admin", "owner"}
    case "editor": return []string{"editor", "admin", "owner"}
    case "admin":  return []string{"admin", "owner"}
    case "owner":  return []string{"owner"}
    case "member": return []string{"member", "viewer", "editor", "admin", "owner"} // NEW
    default:       return []string{rel}
    }
}

// CanInviteUsers — один Check call, который через cascade покрывает {editor, admin, owner}.
//
// Helper выбирает relation "editor" т.к. relationsImplying("editor") = ["editor","admin","owner"];
// внутри Check helper'а итерируется по этому списку и возвращает true на первом allowed.
// viewer cascade-выше editor НЕТ — поэтому viewer Invite-доступ не получает.
func (c *KetoClient) CanInviteUsers(ctx context.Context, principalID, accountID string) (bool, error) {
    return c.Check(ctx, "user:"+principalID, "editor", "account:"+accountID)
}
```

(Optimization vs наивная двойная проверка: один `Check(editor)` cascade-discovers admin/owner, не нужно отдельных `Check(admin)`/`Check(owner)`-call'ов.)

**Outbox events при ActivateInvite / bootstrapNewIdentity** (что пишется напрямую в Keto):
1. `account:<acc-id>#admin@user:<usr-id>` (если bootstrap-flow, см. §2.4.5) — для прямой проверки admin-доступа.
2. `account:<acc-id>#member@user:<usr-id>` — для test-determinism и diagnostic queries (даже если cascade из admin даёт true, explicit member-tuple упрощает unit-tests и `keto-cli list`-проверки).
3. `project:<prj-id>#admin@user:<usr-id>` (если bootstrap-flow) — owner of default Project.
4. Для bootstrap-admin (email `@prorobotech.ru`) — дополнительно `kacho_system:root#admin@user:<usr-id>` (system-admin marker; НЕ AccessBinding, ТОЛЬКО Keto-tuple).

**Семантика `member`-tuple**:
- При активации PENDING-row (PENDING→ACTIVE) — outbox event → Keto write `account:<acc-id>#member@user:<usr-id>`.
- При удалении User-row — outbox event → Keto delete `account:<acc-id>#member@user:<usr-id>`.
- `member` используется в tenant-isolation queries `UserService.List` / `GroupService.List`.

**Permission-семантика `iam.user.create`** — НЕ хранится как Keto-relation/tuple, а как **docstring-comment** в proto (semantic marker). Физическая проверка — relation-based Keto `Check` (subject, relation, object), OPL **НЕ используется** (D-9). Описание в use-case: один `CanInviteUsers` helper-call → одна `Check(editor)` через cascade покрывает {editor, admin, owner}; `viewer` invite'ить не может.

**Документировать в proto-comment / handler-doc**: «`UserService.Invite` требует relation `editor`, `admin` ИЛИ `owner` (но НЕ `viewer`) на target Account через cascade в Go-helper'е `KetoClient.CanInviteUsers`. Permission-семантика `iam.user.create` — semantic marker в docstring, физически — один Check call с cascade-traversal.» (Отражено также в §6 error mapping.)

### 2.7 Cascader spec для UI

UI Cascader source — фиксированная 3-level структура, derive'ится из role-catalog (KAC-122) на frontend без отдельного RPC. **Verbs и naming точно соответствуют catalog'у KAC-122**: `admin/edit/view` (НЕ `editor/viewer`), role-names БЕЗ `roles/` prefix.

```
Уровень 1 — module:
  iam
  vpc
  compute
  loadbalancer
  *           (system-wide wildcard, e.g. "admin" → kacho_system:root#admin)

Уровень 2 — resource (в зависимости от модуля; точно из catalog KAC-122):
  iam:           account, project, user, service_account, group, role, access_binding, *
  vpc:           network, subnet, address, security_group, route_table, gateway,
                 private_endpoint, network_interface, *
  compute:       instance, disk, image, snapshot, disk_type, zone, region, *
  loadbalancer:  network_load_balancer, target_group, *

Уровень 3 — verb (catalog KAC-122 verbs):
  admin, edit, view, *
```

Cascader value = `[module, resource, verb]` (массив из 3 строк) → derive **role-name** `<module>.<resource>.<verb>` (БЕЗ `roles/` prefix, напр. `"vpc.network.admin"`, `"compute.instance.view"`) → derive role-id через preloaded role-catalog map name→id (см. §4.4). ID-format KAC-122: `rol` + first 17 chars of md5(name) hex; в коде НЕ hardcoded, всегда смотреть в response от `listRoles`.

Множественный выбор реализуется через AntD Cascader `multiple={true}` + chip-list ниже.

---

## 3. Изменения в RPC (нормативно)

### 3.1 Новый RPC: `UserService.Invite`

**Endpoint**: public-port 9090, REST mapping `POST /iam/v1/users:invite`.

**Bodyflow** (use-case `invite.go`):

```go
type InviteUseCase struct {
    repo   user.Repository
    abRepo accessbinding.Repository
    opRepo operation.Repository
    ...
}

func (uc *InviteUseCase) Invite(ctx context.Context, req InviteRequest) (*operation.Operation, error) {
    // 1. validate principal — caller must have relation `editor`, `admin` ИЛИ `owner`
    //    on the target Account через cascade `relationsImplying` в Go-helper'е (D-9: relation-based Check, не OPL).
    //    `viewer` не может invite'ить (cascade-выше editor НЕТ).
    //    Permission-семантика "iam.user.create" — docstring-marker в proto, не Keto-construct.
    principal := principalFromCtx(ctx)
    allowed, err := uc.keto.CanInviteUsers(ctx, principal.ID, req.AccountID)
    // helper делает ОДИН Check(editor); relationsImplying("editor") = ["editor","admin","owner"]
    // — cascade-traversal внутри helper'а покрывает все три relations;
    // см. kacho-iam/internal/clients/keto_client.go (§2.6).
    if err != nil  { return nil, fmt.Errorf("keto check: %w", err) }
    if !allowed    { return nil, ErrPermissionDenied }

    // 2. validate email format (domain.Email.Validate)
    // 3. validate role_id ∧ project_id consistency
    if req.ProjectID != "" && req.RoleID == "" {
        return nil, fmt.Errorf("role_id required when project_id is set: %w", ErrInvalidArgument)
    }
    if req.ProjectID != "" {
        // peer-validate project belongs to account
        prj, err := uc.projects.Get(ctx, req.ProjectID)
        if err != nil { return nil, err }
        if prj.AccountID != req.AccountID {
            return nil, fmt.Errorf("project belongs to different account: %w", ErrFailedPrecondition)
        }
    }

    // 4. atomic INSERT user PENDING OR find existing
    op, err := uc.repo.Writer(ctx).Transact(func(w user.Writer) error {
        u, err := w.UpsertPendingInvite(ctx, user.InvitePayload{
            AccountID:  req.AccountID,
            Email:      req.Email,
            DisplayName: defaultDisplayName(req),
            InvitedBy:  principalUserID(ctx),
        })
        // SQL: INSERT ... ON CONFLICT (account_id, lower(email)) DO UPDATE
        //      SET display_name = EXCLUDED.display_name
        //      RETURNING id, invite_status, (xmax = 0) AS inserted
        if err != nil { return err }

        // 5. emit member-outbox event (only if NEW PENDING — `inserted=true`)
        //    or skip if existing ACTIVE/PENDING (idempotent)
        //    NOTE: PENDING does NOT yet write `account#member` tuple — only on Activate

        // 6. if project_id+role_id supplied → INSERT AccessBinding (also idempotent on UNIQUE)
        if req.ProjectID != "" {
            _, err := w.AccessBindings().Upsert(ctx, accessbinding.Payload{
                SubjectType: "user",
                SubjectID:   u.ID,
                RoleID:      req.RoleID,
                ResourceType: "project",
                ResourceID:  req.ProjectID,
            })
            if err != nil { return err }
        }

        // 7. enqueue Operation row + Kratos magic-link generation outbox event
        ...
    })
    return op, err
}
```

**SQL** для UpsertPendingInvite (атомарный, без TOCTOU):

```sql
WITH ins AS (
    INSERT INTO kacho_iam.users (id, account_id, external_id, email, display_name,
                                  invite_status, invited_by, created_at)
    VALUES ($1, $2, '', $3, $4, 'PENDING', $5, NOW())
    ON CONFLICT (account_id, lower(email))
    DO NOTHING
    RETURNING id, invite_status, (xmax = 0) AS inserted
)
SELECT id, invite_status, inserted FROM ins
UNION ALL
SELECT id, invite_status, false FROM kacho_iam.users
 WHERE account_id = $2 AND lower(email) = lower($3)
   AND NOT EXISTS (SELECT 1 FROM ins)
LIMIT 1;
```

- `inserted=true` → новый PENDING-row, нужно эмитнуть outbox + Kratos magic-link.
- `inserted=false, invite_status='ACTIVE'` → user уже active в этом Account — return idempotent (op.done=true сразу, без side-effects кроме AB-upsert). **display_name НЕ перезаписывается** (DO NOTHING) — re-invite ACTIVE user не должен перезатереть его настоящее имя placeholder'ом.
- `inserted=false, invite_status='PENDING'` → re-invite (re-trigger Kratos magic-link выгодно для UX — admin может «дёрнуть» приглашение повторно). display_name тоже не трогаем (admin может уже его поправить).

### 3.2 Изменение RPC: `InternalUserService.UpsertFromIdentity`

**Endpoint**: internal-port 9091 (без изменений).

**Изменённый bodyflow** (в `internal_upsert_from_identity.go`):

```go
func (uc *UpsertFromIdentityUseCase) Upsert(ctx, payload) (*User, error) {
    // payload: external_id (Kratos sub), email, display_name

    // step 1: search for PENDING-row(s) by email across ALL accounts and activate them.
    pendings, err := uc.repo.Reader(ctx).FindPendingByEmail(ctx, payload.Email)
    if err != nil { return nil, err }

    activatedAny := false
    var firstActivated *User
    for _, p := range pendings {
        u, err := uc.repo.Writer(ctx).ActivateInvite(ctx, p.ID, payload.ExternalID, payload.DisplayName)
        // SQL: UPDATE users SET external_id=$1, display_name=COALESCE(NULLIF($2,''), display_name),
        //                       invite_status='ACTIVE'
        //              WHERE id=$3 AND invite_status='PENDING'
        //              RETURNING ...
        if err != nil { return nil, err }
        if u != nil {
            activatedAny = true
            if firstActivated == nil { firstActivated = u }
            // emit account#member outbox event for Keto
        }
    }

    // step 2: look up ACTIVE user-rows для этого external_id (по всем Account'ам).
    existing, err := uc.repo.Reader(ctx).FindActiveByExternalID(ctx, payload.ExternalID)
    if err != nil { return nil, err }

    // D-7 (workspace acceptance §0.3): bootstrap-Account создаётся ТОЛЬКО ЕСЛИ
    //   на step 1 НЕ активировано ни одной PENDING-row,
    //   И на step 2 НЕ найдено ни одной ACTIVE-row с этим external_id.
    // Если activated хотя бы одна PENDING-row — invitee получает доступ только в
    // те Account'ы, куда он invited, и НЕ получает auto-bootstrap Account.
    // Чтобы получить свой собственный Account, user должен явно нажать
    // «Создать организацию» в UI (POST /iam/v1/accounts).
    if !activatedAny && existing == nil {
        // step 3: brand-new identity без PENDING-invite → KAC-117 bootstrap-flow.
        return uc.bootstrapNewIdentity(ctx, payload)
    }

    // return приоритетно first activated (новые invitations важнее старого active state),
    // иначе — existing ACTIVE row.
    if firstActivated != nil { return firstActivated, nil }
    return existing, nil
}
```

**Ключевые инварианты**:
1. `UpsertFromIdentity` НЕ создаёт duplicate User-row в Account, где user уже ACTIVE — это гарантируется UNIQUE-индексом `(account_id, external_id) WHERE external_id<>''` (23505 → service-level idempotent return).
2. **D-7**: `bootstrapNewIdentity` skip-ается, если хотя бы одна PENDING-row активирована **или** уже существует хотя бы одна ACTIVE-row с тем же `external_id`. Это резолвит race с self-signup (R-5): invitee, у которого есть PENDING в acc-A, не получает третий auto-Account при first-login.

### 3.3 Изменение RPC: `UserService.List` (default-deny)

```go
func (uc *ListUseCase) List(ctx, req) (*Users, error) {
    principal := principalFromCtx(ctx)
    if principal == nil || principal.Type == "anonymous" {
        return &Users{}, nil // empty
    }
    if principal.Type == "system" {
        // unfiltered (admin tooling)
        return uc.repo.Reader(ctx).ListAll(ctx, req.PageSize, req.PageToken)
    }
    // type=user — scope to accounts where principal is member
    accounts, err := uc.repo.Reader(ctx).ListAccountsForUser(ctx, principal.ID)
    if err != nil { return nil, err }
    if req.AccountID != "" {
        // explicit filter — must be in accounts list, else return empty
        if !slices.Contains(accounts, req.AccountID) { return &Users{}, nil }
        return uc.repo.Reader(ctx).ListByAccount(ctx, req.AccountID, req.PageSize, req.PageToken)
    }
    return uc.repo.Reader(ctx).ListByAccounts(ctx, accounts, req.PageSize, req.PageToken)
}
```

Эта правка **дополняет** KAC-123 (Group default-deny) — теперь User тоже tenant-isolated.

### 3.4 Principal-tracking при N-User-per-identity (OperationService impact)

С введением D-3 (один Kratos identity → N User-row, по одной per Account) меняется семантика поля `operations.principal_id`. До KAC-125 этот id однозначно соответствовал Kratos identity (1:1 с User.id). После KAC-125:

- **`operations.principal_id` = User.ID той row, в context'е которой вызван RPC** (resolved через api-gateway auth middleware из `account_id` request-context'а — какой Account user сейчас «выбрал» в BreadcrumbSelector). Т.е. invite в acc-A создаёт Operation с `principal_id = usr-admin-in-acc-A`; если тот же admin переключится на acc-B и сделает invite там — Operation запишется с `principal_id = usr-admin-in-acc-B`.
- **`OperationService.List` фильтрует по `principal_id = ctx.user.id` (per-User-row)**, НЕ aggregating по external_id. Это означает: переключение между Accounts — фактически переключение между разными history-trails. История из acc-A не «протекает» в context acc-B.
- **Это by-design**: соответствует tenant-isolation regime KAC-118/123. Operation, выполненный в context'е acc-A, виден только member'ам acc-A; admin'у того же Kratos identity, переключившемуся на acc-B, она невидима — её можно увидеть, только вернувшись в acc-A.

Документирование UX: UI side эпизодически показывает «История операций» под текущий Account-scope; чтобы увидеть все operations через все Account'ы — нужен отдельный multi-Account view (out-of-scope KAC-125, follow-up тикет).

### 3.5 Сводная таблица изменений RPC

| RPC | Тип изменения | Endpoint | Async/Sync |
|-----|---------------|----------|------------|
| `UserService.Invite` | NEW | public 9090 | async (Operation) |
| `UserService.List` | CHANGED — default-deny + `account_id` filter | public 9090 | sync |
| `UserService.Get` | UNCHANGED (NotFound на cross-Account user — реализовано в KAC-118) | public 9090 | sync |
| `UserService.Create` | DEPRECATED (D-8): `option deprecated = true;` в proto; gRPC handler returns `FailedPrecondition "Use UserService.Invite instead"`; REST `POST /iam/v1/users` returns 410 Gone | public 9090 | sync (но immediate-error) |
| `UserService.Delete` | UNCHANGED, scope-check `account_id IN principal.accounts` | public 9090 | async |
| `InternalUserService.UpsertFromIdentity` | CHANGED — PENDING-aware | internal 9091 | async |

---

## 4. UI changes (нормативно)

### 4.1 Route rename и redirect

| Старый URL | Новый URL | HTTP |
|------------|-----------|------|
| `/iam/access-bindings` | `/iam/access` | 301 redirect SPA-side (React Router) |
| `/iam/access-bindings/:id` | `/iam/access/:id` | 301 |
| `/iam/access-bindings?...filter` | `/iam/access?...filter` | 301 |

### 4.2 Страница `/iam/access` — структура

Из скринов в `kacho-ui/tmp/`:

**Заголовок**: `<Typography.Title level={3}>Права доступа</Typography.Title>`

**Tabs** (AntD Radio.Group YC-style): `[Облако] [Каталог]` — выбирает scope.
- **Облако** = Account-level (resource_type=`account`, resource_id=current Account from BreadcrumbSelector).
- **Каталог** = Project-level (resource_type=`project`, resource_id=current Project from BreadcrumbSelector).
- Default — текущий контекст из BreadcrumbSelector (если выбран Project — `Каталог`, иначе `Облако`).

**Action button**: `<Button type="primary" icon={<UnlockOutlined/>}>Настроить доступ</Button>` — открывает модалку «Выдача доступа» (см. §4.3).

**Filter bar**:
- Input «Имя или идентификатор пользователя» (autocomplete по `UserService.List?accountId=<acc>`).
- Select «Тип аккаунта» (multiselect: Пользовательские / Сервисные / Группы / Приглашённые).
- Select «Все пользователи» (filter dropdown).
- Toggle «Наследуемые роли» — показывает AB унаследованные с Account-уровня в Project-tab.

**Таблица AB-rows**:
| Колонка | Источник |
|---------|----------|
| Пользователь | `User.display_name + User.email` (для subject_type=user) |
| Роли | `Role.name` (через JOIN ab.role_id → roles) |
| Идентификатор | `User.id` (subject_id) |
| Федерация | `User.external_id` или `—` для PENDING |
| `...` | RowActionsMenu: «Изменить роли» / «Отозвать доступ» |

PENDING-user отображается с тегом `<Tag color="orange">Приглашён</Tag>` рядом с display_name.

### 4.3 Модалка «Выдача доступа»

Из скринов `image copy.png`, `image copy 2.png`, `image copy 3.png`:

**Заголовок**: `<Title level={4}><UserAddOutlined/> Выдача доступа</Title>`

**Layout**: AntD horizontal Form, `labelCol={{ flex: "180px" }}`, `wrapperCol={{ flex: "auto" }}`, `colon={false}`, ⭐ справа (§4.3 ui-CLAUDE.md).

**Поле «Ресурс»** (read-only):
```
[icon] <name> <Tag>Облако/Каталог</Tag>
```
Берётся из текущего таба (Облако = Account, Каталог = Project).

**Поле «Кому выдать доступ»** *required*, info-tooltip — combobox:
- **Категории** (left-list sticky):
  - Все
  - Пользовательские аккаунты (subject_type=user, invite_status=ACTIVE)
  - Сервисные аккаунты (subject_type=service_account)
  - Группы (subject_type=group)
  - Приглашённые аккаунты (subject_type=user, invite_status=PENDING)
  - Системные группы (только `roles/system.*` namespace на E0 — пустой stub)
  - Публичные группы (reserved — пустой stub)
- **Right pane**: autocomplete `<Select showSearch />` с опциями `{avatar, display_name, email, subject_id, invite_status}`.
- **Trigger search**: `>= 1 char` → debounced API call.
- **Поиск идёт по** `UserService.List?accountId=<current-account>` (для табов «Все», «Пользовательские», «Приглашённые») + `GroupService.List?accountId=<current-account>` + `ServiceAccountService.List?projectId=<…>`.

**Fallback на email-miss**:
- Если введён валидный email (regex match) и `UserService.List` вернул 0 results → показать справа CTA-блок (как в `image copy 3.png`):
  ```
  Пользователь с адресом <email> не найден в вашей организации.
  Вы можете отправить ему приглашение для присоединения к организации.
  [Кнопка] Пригласить пользователя
  ```
- Клик на «Пригласить пользователя» → второй экран модалки (или дочерняя модалка) «Приглашение пользователя» с полями: email (read-only, pre-filled), display_name (optional), role (Cascader, см. §4.4) + кнопки `Отменить / Пригласить`.
- При нажатии `Пригласить` → `POST /iam/v1/users:invite` → Operation polling → toast «Приглашение отправлено» → return на main модалку «Выдача доступа», новый PENDING-user уже в autocomplete.

**Поле «Роли»** *required*, отключено пока «Кому» пусто (см. `image copy.png` плашка «Чтобы назначить роли, выберите, кому предоставить доступ»):
- **AntD Cascader** `multiple={true}`, options derive из §2.7 fixed-tree.
- Выбранные роли отображаются ниже как `<Tag closable>vpc.network.admin</Tag>` chip-list.
- **Tabs** в области cascader (D-5):
  - **Системные роли** — fixed tree из §2.7 (54 roles).
  - **Свои роли** — read-only пустой placeholder «Свои роли появятся после создания через API» (until KAC-122+).

**Кнопки**: `[Отменить] [Сохранить]` (primary, disabled пока «Кому» + «Роли» обе пусты).

**Submit action**:
- For каждой выбранной role → `POST /iam/v1/access-bindings` с payload `{subject, role_id, resource_type, resource_id}`.
- N requests параллельно → wait all done → toast «N ролей назначено» → close modal + refetch table.
- На ошибке хотя бы одного — toast error + НЕ закрывать модалку (§3.5 ui-CLAUDE.md).

### 4.4 Cascader implementation note

```tsx
// Verbs точно совпадают с catalog KAC-122: admin/edit/view (НЕ editor/viewer).
const cascaderOptions = [
  {
    value: "iam", label: "IAM", children: [
      { value: "account", label: "Account", children: [
        { value: "admin", label: "admin" },
        { value: "edit",  label: "edit"  },
        { value: "view",  label: "view"  },
      ]},
      { value: "project", label: "Project", children: [/* admin/edit/view */] },
      // … 7 IAM resources × 3 verbs
    ]
  },
  { value: "vpc",          label: "VPC",           children: [/* … */] },
  { value: "compute",      label: "Compute",       children: [/* … */] },
  { value: "loadbalancer", label: "Load Balancer", children: [/* … */] },
  { value: "*", label: "Система (все модули)", children: [
    { value: "*", label: "*", children: [
      { value: "admin", label: "admin (super-admin)" },
      { value: "view",  label: "view (read-only всё)" },
    ]}
  ]},
];

// AntD Cascader — derive role-NAME (no `roles/` prefix), затем lookup role-ID
// в preloaded role-catalog map (см. §4.4 ниже про preload).
<Cascader
  options={cascaderOptions}
  multiple
  showSearch={{ filter: customFilter }}
  placeholder="Выберите модуль / ресурс / роль"
  onChange={(values) => {
    // values: [["iam","account","admin"], ["vpc","network","edit"], ...]
    const roleIds: string[] = [];
    for (const [m, r, v] of values) {
      const roleName = `${m}.${r}.${v}`;            // напр. "vpc.network.admin"
      const role = roles?.find(rl => rl.name === roleName);
      if (!role) {
        // role не найдена в catalog'е — error UX (toast), submit-кнопка остаётся disabled
        // на этом chip-state. См. сценарий S-26 (CascaderRoleSyncWithCatalog).
        showToast(`Role "${roleName}" not found in catalog`);
        continue;
      }
      roleIds.push(role.id);
    }
    setSelectedRoleIds(roleIds);
  }}
/>
```

**`roleNameToId` — preload через role-catalog API, НЕ hardcoded таблица** (M-4 решение). На mount AccessPage:

```tsx
const { data: roles } = useSWR(
  ["roles", accountId],
  () => iamApi.listRoles({ account_id: accountId, page_size: 500 }),
  { revalidateOnFocus: false }
);

// Single source of truth — server-side role-catalog (54 system + custom).
// roleNameToId — derived map name→id из загруженного списка.
// КЛЮЧ: точные имена из catalog'а KAC-122 БЕЗ `roles/` prefix
// (напр. "vpc.network.admin", "compute.instance.view").
const roleNameToId = useMemo(
  () => Object.fromEntries((roles?.roles ?? []).map(r => [r.name, r.id])),
  [roles]
);
```

Это исключает class «hardcoded таблица в UI» + «БД seed разошлись», что было бы скрытым багом. Если `roles` ещё не загружены (`loading=true`) — `Cascader` disabled с `<Spin/>` плейсхолдером, submit на сломанный request не возможен (см. сценарий S-26).

> **Pagination note** (m6): если `roles.length >= page_size (500)` — fetch next page (loop until `next_page_token=''`). Дефолт 500 покрывает 54 system + 446 custom slots; для tenants с большим catalog'ом (E1+ когда появятся kacho-vpc / kacho-compute custom-roles) — auto-paginate в React-query (`useSWRInfinite` либо явный while-loop в `iamApi.listRoles`). Сейчас на E0 — 54 < 500, реально pagination не срабатывает, но код должен это поддерживать.

**Custom-tab** в Cascader (D-5) на E0 показывает `roles.filter(r => !r.is_system && r.account_id === accountId)`. На E0 custom-roles ещё нет (Role.Create RPC появится в KAC-122+), но UI готов к их появлению — placeholder «Свои роли появятся после создания через API» отрисовывается из `roles.filter(...).length === 0`.

---

## 5. Migration plan / backfill

**Текущее состояние** (на 2026-05-18, dev cluster `e2c825`):
- `kacho_iam.users` имеет N-row'ов (admin@prorobotech.ru + несколько test users).
- Все они `external_id <> ''` (ACTIVE-эквивалент).
- `accounts` имеет N+1 row (по одному auto-create per user через KAC-117 + bootstrap admin Account).
- Соответствие `users.id ↔ accounts.owner_user_id` устанавливается через `accounts_owner_fk`.

**Стратегия миграции — greenfield reset**:

На dev/staging — **полный DB-wipe** через `kacho-deploy/scripts/wipe-iam-db.sh`. Скрипт выполняет:

```sql
DROP SCHEMA kacho_iam CASCADE;
CREATE SCHEMA kacho_iam;
```

После чего сервис `kacho-iam` на старте применяет миграции **последовательно**. Реальный список файлов в `kacho-iam/internal/migrations/` на 2026-05-18 (промежуточных `0003-0006` НЕ существует — это нумерация per-feature, не строго плотная):

```
1. 0001_initial.sql                          (E0 baseline: users, accounts, projects, …,
                                              FK accounts.owner_user_id → users.id)
2. 0002_fga_outbox.sql                       (KAC-115/116 outbox infra — Keto-writer worker)
3. 0007_role_catalog_kac121.sql              (KAC-121 role catalog v1)
4. 0008_role_catalog_kac122.sql              (KAC-122 role catalog v2 — naming + IDs)
5. 0009_user_per_account_invite_kac125.sql   ← НОВАЯ (этого PR — KAC-125)
```

Принимаем потерю dev-данных как стоимость (greenfield — см. CLAUDE.md «новая БД на каждую крупную итерацию»). Миграция `0009` применяется поверх свежесозданной schema (`DROP+CREATE`), без необходимости backfill — все таблицы пустые, account_id NOT NULL не падает, потому что users тоже пуст.

Production — N/A (Kachō ещё не в production, KAC-104 не closed).

**Альтернатива backfill (если потребуется)** — не делаем в этой итерации, но фиксируем как fallback:

```sql
-- backfill users.account_id from existing accounts.owner_user_id 1:1
UPDATE kacho_iam.users u
   SET account_id = a.id,
       invite_status = 'ACTIVE'
  FROM kacho_iam.accounts a
 WHERE a.owner_user_id = u.id;

-- если user НЕ owner ни одного Account — DELETE (orphan; не должно случаться при текущей schema, но defense-in-depth)
DELETE FROM kacho_iam.users WHERE account_id IS NULL;
```

Эта SQL fallback'нется только если будет принято решение «не reset DB». Сейчас — reset.

---

## 6. Error mapping (нормативно)

| Ситуация | gRPC code | Сообщение (YC-style формы) |
|----------|-----------|----------------------------|
| `Invite` без `account_id` | INVALID_ARGUMENT | `"Illegal argument account_id: required"` |
| `Invite` с невалидным email (regex fail) | INVALID_ARGUMENT | `"Illegal argument email: must match RFC 5321"` |
| `Invite` с `project_id` без `role_id` | INVALID_ARGUMENT | `"Illegal argument role_id: required when project_id is set"` |
| `Invite` с `project_id` принадлежащим другому Account | FAILED_PRECONDITION | `"project_id belongs to different account"` |
| `Invite` от principal без relation `admin` / `editor` на Account (e.g. от `viewer` или anonymous) | PERMISSION_DENIED | `"Permission denied to invite users in account <acc>"` (D-9: helper `CanInviteUsers` returns false) |
| `Invite` для уже-ACTIVE user в этом Account (с указанием project_id+role_id) | OK (idempotent) | возвращает existing user + bound AccessBinding |
| `Invite` для уже-PENDING user (без project_id+role_id) | OK (idempotent) | возвращает existing user (re-trigger Kratos magic-link если нужно) |
| `UpsertFromIdentity` — ACTIVE user пытается login повторно | OK | idempotent return existing |
| `UserService.Get` — cross-Account user-row | NOT_FOUND | `"User <id> not found"` (не leak'ает существование) |
| `UserService.Delete` — cross-Account user-row | NOT_FOUND | то же |
| `UserService.Delete` — user является `accounts.owner_user_id` хотя бы одного Account | FAILED_PRECONDITION | `"User <id> is owner of accounts"` (FK RESTRICT) |
| PENDING-user пытается login до Activate (Kratos magic-link не attempted) | N/A | Kratos сам отдаст generic-401; backend не пишет ничего |
| `Invite` дёрнули concurrently на один email | OK (один INSERT, второй CONFLICT → DO NOTHING + SELECT existing) | гарантия `UNIQUE(account_id, lower(email))` |
| Клиент вызывает deprecated `UserService.Create` (gRPC) | FAILED_PRECONDITION | `"UserService.Create deprecated; use UserService.Invite"` (D-8) |
| Клиент вызывает deprecated REST `POST /iam/v1/users` | HTTP 410 Gone | body: `{"code": 9, "message": "UserService.Create deprecated; use UserService.Invite"}` |

---

## 7. Given-When-Then сценарии

> 31 GWT-сценариев (S-01…S-30 + S-07b). ID: `KAC-125.S-<NN>`. Базовые S-01…S-22 — backend + UI + cross-cutting; v2 добавил S-23…S-29 (D-7 self-Account skip, D-8 Create-deprecated, Keto-tuple end-to-end, Cascader-role-catalog-sync, OperationService scope, R-5 re-signup mitigation); v3 добавил **S-07b** (editor-invites — D-9 cascade) и **S-30** (BootstrapTxDeferrableFKCheck — M6 negative проба DEFERRABLE); **v4 уточнил без добавления сценариев**: S-07/S-07b/S-10 переписаны под один `Check(editor)` через cascade-traversal (MAJ-1/MAJ-2); S-02/S-03/S-06/S-16/S-17/S-21/S-26 — role-IDs derived через `sysRoleID(name)` + verbs `admin/edit/view` (NEW-B11); S-06 bootstrap-TX — 2 AB always + 1 Keto-tuple для `@prorobotech.ru` (NEW-B10/MIN-1).

### 7.1 Backend / RPC сценарии

#### KAC-125.S-01 — InviteNewUser (email отсутствует в Account)

**Given** Account `acc-A` существует, principal `admin@example.com` (User `usr-admin`) имеет `iam.user.admin@account:acc-A` через AccessBinding.
**And** Email `newbie@example.com` НЕ существует ни в одной User-row.

**When** `admin@example.com` вызывает `POST /iam/v1/users:invite` payload:
```json
{ "account_id": "acc-A", "email": "newbie@example.com", "display_name": "Newbie Smith" }
```

**Then** response = Operation (done=true after polling), metadata = `{user_id: "usr-X", account_id: "acc-A"}`.
**And** в `kacho_iam.users` появляется row `{id:"usr-X", account_id:"acc-A", email:"newbie@example.com", external_id:"", invite_status:"PENDING", invited_by:"usr-admin"}`.
**And** в `kacho_iam.access_bindings` НЕТ новых row (project_id/role_id не указаны).
**And** в Keto **НЕТ** tuple `account:acc-A#member@user:usr-X` (PENDING ≠ member).

#### KAC-125.S-02 — InviteNewUser+BindToProject

**Given** `acc-A` + admin как в S-01.
**And** Project `prj-default` существует, `prj-default.account_id = acc-A`.
**And** Role с `name="vpc.network.view"` — system-role в catalog (KAC-122; БЕЗ `roles/` prefix). ID computed `"rol" + md5("vpc.network.view").hex.first(17)` либо dynamic lookup в response от `listRoles`. В тесте — resolved via UI preload или explicit GetByName.

**When** admin вызывает Invite с `{account_id:"acc-A", email:"newbie@example.com", project_id:"prj-default", role_id:<resolved-id-of-vpc.network.view>}`.

**Then** User PENDING создан как в S-01.
**And** в `access_bindings` появляется row `{subject_type:"user", subject_id:"usr-X", role_id:<resolved>, resource_type:"project", resource_id:"prj-default"}`.
**And** в Keto outbox enqueue'ится 1 event (для AB), но НЕ `account#member` (user всё ещё PENDING).
**And** UI таблица `/iam/access?prj=prj-default` показывает newbie с tag «Приглашён» + роль `vpc.network.view` (БЕЗ `roles/` prefix).

#### KAC-125.S-03 — InviteExistingUser-InSameAccount (idempotent)

**Given** `acc-A`, admin как в S-01.
**And** User `usr-Y` уже ACTIVE в acc-A, email=`existing@example.com`.
**And** Role с `name="vpc.network.edit"` — system-role в catalog (KAC-122 verb `edit`, НЕ `editor`).

**When** admin вызывает `Invite{account_id:"acc-A", email:"existing@example.com", project_id:"prj-default", role_id:<resolved-id-of-vpc.network.edit>}`.

**Then** OK (operation done=true). НЕТ нового User-row.
**And** в `access_bindings` появляется новая row для (usr-Y, `<vpc.network.edit-id>`, project:prj-default) — UNIQUE constraint на (subject, role, resource) НЕ нарушен (это новый AB).
**And** если повторно тот же Invite → второй AB-INSERT идёт через UPSERT (см. KAC-105 acceptance) — idempotent.

#### KAC-125.S-04 — InviteEmailFromDifferentAccount (cross-Account, new row)

**Given** Account `acc-A` (admin) и Account `acc-B` (другой user).
**And** User `usr-Z` ACTIVE в `acc-B` с email=`shared@example.com` (он owner acc-B через self-signup).
**And** В `acc-A` нет User-row с email=`shared@example.com`.

**When** admin вызывает `Invite{account_id:"acc-A", email:"shared@example.com"}`.

**Then** Создаётся **новая** User-row в `acc-A` (id `usr-Z-in-A`, отдельная от `usr-Z`), `invite_status="PENDING"`, `external_id=""`.
**And** При first login Kratos identity X (sub=Kratos-uid-of-usr-Z), `UpsertFromIdentity` найдёт PENDING-row в `acc-A` и сразу же activate'нёт его (без auto-create нового Account, потому что есть PENDING-invite).
**And** В итоге Kratos identity X имеет 2 User-rows: `usr-Z` в `acc-B` (owner) + `usr-Z-in-A` в `acc-A` (invited).
**And** **D-9 post-invite primary context**: `UpsertFromIdentity` return-value `response.user.id = usr-Z-in-A` (first-activated row, не existing `usr-Z` в acc-B). UI на post-login flow читает `response.user.account_id = acc-A` и автоматически переключает BreadcrumbSelector на acc-A. Пользователь видит новую среду — это его primary intent после нажатия magic-link. Чтобы вернуться в acc-B, нужно вручную переключить BreadcrumbSelector.

#### KAC-125.S-05 — InviteEmailFromDifferentAccount-FirstLogin (PENDING→ACTIVE)

**Given** State после S-04: `usr-Z-in-A` PENDING в `acc-A`.
**And** Kratos identity X ещё не делал first login в `acc-A` (но может уже залогинен в `acc-B`).

**When** В Kratos session active session принадлежит X → next request приходит в api-gateway → auth interceptor вызывает `InternalUserService.UpsertFromIdentity{external_id:"X", email:"shared@example.com", display_name:"…"}`.

**Then** `FindPendingByEmail("shared@example.com")` возвращает `[{usr-Z-in-A, acc-A}]`.
**And** `ActivateInvite(usr-Z-in-A, "X", "…")` → SQL UPDATE rows=1.
**And** Keto outbox enqueue → `account:acc-A#member@user:usr-Z-in-A`.
**And** `accounts_owner_fk` НЕ меняется — `usr-Z-in-A` НЕ owner `acc-A` (он invited, owner остаётся admin).

#### KAC-125.S-06 — SelfSignup (no pending-invite) — KAC-117 behaviour preserved (extended)

**Given** Kratos identity Y (sub=Kratos-uid-newuser), email=`fresh@example.com`. НЕТ PENDING-row нигде.

**When** Kratos `/registration` → callback `UpsertFromIdentity{external_id:"Y", email:"fresh@example.com", display_name:"Fresh User"}`.

**Then** `FindPendingByEmail` → empty.
**And** `FindActiveByExternalID("Y")` → nil.
**And** Идёт path `bootstrapNewIdentity` (одна TX с DEFERRABLE FK, §2.4.5):

1. INSERT user `usr-Y` (`account_id=acc-Y`, `external_id="Y"`, `invite_status="ACTIVE"`).
2. INSERT account `acc-Y` (`owner_user_id=usr-Y`, `name="Personal cloud"`).
3. INSERT project `prj-default-Y` (`account_id=acc-Y`, `name="default"`).
4. INSERT **2 self-grant AccessBinding rows always** (regardless of bootstrap-admin):
   - `(subject=user, subject_id=usr-Y, role_id=sysRoleID("iam.account.admin"), resource=account:acc-Y)`.
   - `(subject=user, subject_id=usr-Y, role_id=sysRoleID("iam.project.admin"),  resource=project:prj-default-Y)`.

   `sysRoleID(name)` = `"rol"` + md5(name).hex.first(17) — детерминированный lookup в catalog'е KAC-122 (миграция 0008). Никаких `rol-iam-account-admin` placeholder'ов в коде.

   **Bootstrap-admin (email matches `@prorobotech.ru`)** — НЕ получает extra AccessBinding. System-admin marker реализуется ТОЛЬКО как Keto-tuple (см. step 5).
5. EnqueueOutboxEvents **3 Keto-write events always; bootstrap-admin → +1 (всего 4)**:
   - `keto_write: account:acc-Y#admin@user:usr-Y`.
   - `keto_write: account:acc-Y#member@user:usr-Y` (explicit для test-determinism; cascade в `relationsImplying` §2.6 уже включает admin→member client-side, но прямой tuple упрощает diagnostic queries и unit-tests).
   - `keto_write: project:prj-default-Y#admin@user:usr-Y`.
   - **Если bootstrap-admin** → +1: `keto_write: kacho_system:root#admin@user:usr-Y` (system-admin marker, НЕ AccessBinding).
6. COMMIT.

**And** На COMMIT DEFERRABLE FK-check проходит (S-30 verification).
**And** Outbox-drainer worker async picks up Keto-events и пишет tuples в Keto (S-25 verification).

**And** **D-9 post-invite primary context**: `UpsertFromIdentity` returns `usr-Y` (single User-row, она же first-activated/first-created). UI устанавливает BreadcrumbSelector на acc-Y/prj-default-Y.

#### KAC-125.S-07 — InviteWithoutPermission (PERMISSION_DENIED — viewer)

**Given** Account `acc-A`. User `usr-viewer` имеет AccessBinding с role `iam.account.view` (verb `view`) — read-only relation `viewer` на `account:acc-A`, НЕТ admin/editor/owner.

**When** `usr-viewer` вызывает `Invite{account_id:"acc-A", email:"x@example.com"}`.

**Then** Use-case вызывает `keto.CanInviteUsers(usr-viewer, acc-A)`:
- Helper делает **один `Check(user:usr-viewer, "editor", account:acc-A)`** (cascade traversal через `relationsImplying("editor") = ["editor","admin","owner"]`).
- Ни один из tuples `account:acc-A#editor@user:usr-viewer`, `account:acc-A#admin@user:usr-viewer`, `account:acc-A#owner@user:usr-viewer` НЕ существует → helper returns `allowed=false`.

**And** Use-case returns `ErrPermissionDenied`.
**And** gRPC `PERMISSION_DENIED`, body `"Permission denied to invite users in account acc-A"`.
**And** Нет нового user-row.
**And** Operation НЕ создан (validation fail до `repo.Writer.Transact`).

#### KAC-125.S-07b — EditorInvitesSuccessfully (D-9 cascade)

**Given** Account `acc-A`. User `usr-editor` имеет AccessBinding с role `iam.account.edit` (verb `edit`) — relation `editor` на `account:acc-A`.
**And** Email `newcomer@example.com` НЕ существует в acc-A.

**When** `usr-editor` вызывает `Invite{account_id:"acc-A", email:"newcomer@example.com"}`.

**Then** Use-case вызывает `keto.CanInviteUsers(usr-editor, acc-A)`:
- Helper делает **один `Check(user:usr-editor, "editor", account:acc-A)`** (cascade traversal через `relationsImplying("editor") = ["editor","admin","owner"]`).
- Tuple `account:acc-A#editor@user:usr-editor` existing → helper returns `allowed=true` на первом hit'е cascade-итерации.

**And** Operation done=true, metadata `{user_id:"usr-newcomer-pending-A", account_id:"acc-A"}`.
**And** PENDING-row создана `{account_id:"acc-A", email:"newcomer@example.com", invite_status:"PENDING", invited_by:"usr-editor"}`.
**And** Это доказывает: **editor может invite** (D-9 cascade в Go-helper'е `relationsImplying` уже покрывает editor/admin/owner одним Check call'ом); только `viewer` не может (S-07).

#### KAC-125.S-08 — InviteAcrossAccount-ProjectMismatch (FAILED_PRECONDITION)

**Given** Account `acc-A`, Project `prj-other` принадлежит **другому** Account `acc-B`.
**And** admin имеет `iam.user.admin@acc-A`.

**When** admin вызывает `Invite{account_id:"acc-A", email:"x@example.com", project_id:"prj-other", role_id:"rol…"}`.

**Then** gRPC `FAILED_PRECONDITION`, `"project_id belongs to different account"`.
**And** PENDING-user **НЕ создан** (peer-validation проекта в use-case до INSERT).

#### KAC-125.S-09 — UserListDefaultDeny (tenant isolation)

**Given** Account `acc-A` (admin + 3 invited users), Account `acc-B` (другой owner + 2 invited).

**When** admin@acc-A вызывает `GET /iam/v1/users` (без accountId).

**Then** 200 OK, в ответе **4 users** (admin + 3 invited из acc-A), НЕ видит acc-B users.

**When** admin@acc-A вызывает `GET /iam/v1/users?accountId=acc-B`.

**Then** 200 OK, ответ empty (admin не member acc-B).

**When** system principal (admin tool, через internal-port или bootstrap) вызывает то же.

**Then** все 6 users видны.

#### KAC-125.S-10 — KetoMemberRelationCascade

**Given** Account `acc-A` с user `usr-X` имеющим AB `{subject:user:usr-X, role:<vpc.network.admin-id>, resource:project:prj-default}`.
**And** В acc-A `prj-default.account_id = acc-A`.
**And** Post-activation, **explicit tuple `account:acc-A#member@user:usr-X` записан в Keto** через outbox-эмит при activation PENDING→ACTIVE (S-25 verification).

**When** Go-helper в kacho-iam вызывает `KetoClient.Check(user:usr-X, "member", account:acc-A)` для tenant-isolation в `UserService.List`.

**Then** Helper делает **cascade-traversal** через `relationsImplying("member") = ["member","viewer","editor","admin","owner"]`:
- Iter 1: `direct_check(account:acc-A#member@user:usr-X)` → **allowed=true** (explicit tuple записан outbox-эмитом). Helper short-circuit'ит на first hit и returns `true`.

**And** Если explicit member-tuple отсутствует (e.g. hypothetical scenario, где user имеет только admin/editor/viewer) — cascade продолжает:
- Iter 2: `direct_check(viewer)` → false.
- Iter 3: `direct_check(editor)` → false.
- Iter 4: `direct_check(admin)` → false (admin role записан на project, не на account, см. Given).
- Iter 5: `direct_check(owner)` → false.
- Result: `allowed=false`.

**И именно поэтому** explicit member-tuple emit'ится outbox-эмитом при activation: чтобы member-check был детерминированным **без зависимости** от наличия admin/editor/viewer-tuples на этом Account'е. Cascade — defensive fallback.

**And** Если AB удалить → Keto-tuple на admin remove'ится (separate outbox-event), но `member`-tuple остаётся (user всё ещё в Account; member отвязан от AB).

**Реализация cascade — client-side в `KetoClient.Check`/`relationsImplying`** (Go-helper, файл `kacho-iam/internal/clients/keto_client.go`). Cascade `admin → member` Keto-config-side НЕ используется (out of KAC-125 scope; namespace-config Keto остаётся flat — `namespaces: [{id, name}]`).

#### KAC-125.S-11 — ConcurrentInvite (race-safe)

**Given** Empty Account `acc-A` + admin.

**When** Два goroutine одновременно вызывают `Invite{account_id:"acc-A", email:"race@example.com"}`.

**Then** **Один** из двух SQL INSERT попадает, второй idempotent через `ON CONFLICT (account_id, lower(email)) DO UPDATE`. Финально **одна** PENDING-row.
**And** Обе response — Operation с `done=true` и одинаковым `user_id` в metadata.
**And** Newman + integration race-test в одном PR.

#### KAC-125.S-12 — DeleteOwnerUser (FAILED_PRECONDITION)

**Given** User `usr-owner` владеет `acc-A` (через `accounts.owner_user_id`).

**When** admin (себя сам, либо другой admin) вызывает `UserService.Delete{id:"usr-owner"}`.

**Then** gRPC `FAILED_PRECONDITION`, `"User usr-owner is owner of accounts"` (от FK `accounts_owner_fk` RESTRICT → 23503 → service maperr).

#### KAC-125.S-13 — DeletePendingUser (allowed)

**Given** PENDING-user `usr-X` в `acc-A` (создан через Invite, ещё не активирован).

**When** admin@acc-A вызывает `UserService.Delete{id:"usr-X"}`.

**Then** OK (operation done=true). User-row удалён.
**And** Никаких Keto tuples invalidate (PENDING не имел tuples).
**And** Если был AB c subject_id=usr-X (через S-02) — он остаётся orphan (polymorphic ref без FK, как KAC-105 acceptance). Worker по schedule (или E3+ cleanup-job) разгребёт; на E0 принимаем dangling-state.

### 7.2 UI сценарии (Playwright)

#### KAC-125.S-14 — RouteRedirect

**Given** Кэш SPA уже загружен.

**When** User navigates `/iam/access-bindings`.

**Then** SPA-redirect (React Router) на `/iam/access`. URL обновляется.

#### KAC-125.S-15 — AccessPageTabs

**Given** User logged in, BreadcrumbSelector — `acc-A / prj-default`.

**When** Open `/iam/access`.

**Then** Tabs `[Облако] [Каталог]` отрисованы.
**And** Default tab — `Каталог` (т.к. в selector выбран Project).
**And** Таблица показывает AB-rows для resource=`project:prj-default`.

**When** Click `Облако`.

**Then** Таблица обновляется, теперь AB-rows для resource=`account:acc-A`.

#### KAC-125.S-16 — InviteModalOpen + CascaderRoles

**Given** Open `/iam/access?tab=Каталог`.

**When** Click `Настроить доступ`.

**Then** Модалка «Выдача доступа» открыта.
**And** Поле «Ресурс» read-only показывает `<icon> prj-default Каталог`.
**And** Поле «Роли» disabled, плашка «Чтобы назначить роли, выберите, кому предоставить доступ».

**When** В «Кому» ввести `admin@example.com` → выбрать option.
**And** Открыть Cascader → раскрыть VPC → Network → admin → ✓.
**And** Также раскрыть Compute → Instance → edit → ✓.

**Then** Chip-list ниже cascader показывает `<Tag closable>vpc.network.admin</Tag> <Tag closable>compute.instance.edit</Tag>`.
**And** Кнопка `Сохранить` enabled.

**When** Click `Сохранить`.

**Then** Два API call параллельно: `POST /iam/v1/access-bindings` для каждой роли.
**And** Toast «2 роли назначены».
**And** Modal closes. Таблица обновлена (2 новых rows).

#### KAC-125.S-17 — InviteFallback CTA

**Given** Open `/iam/access` модалка «Выдача доступа».

**When** В поле «Кому» ввести email `unknown@example.com` (не существует в Account).

**Then** Autocomplete results = empty.
**And** Справа появляется CTA-блок (как `image copy 3.png`): `Пользователь с адресом unknown@example.com не найден в вашей организации. Вы можете отправить ему приглашение… [Пригласить пользователя]`.

**When** Click `Пригласить пользователя`.

**Then** Открывается дочерняя форма «Приглашение пользователя» с email pre-filled.
**And** Поля: display_name (optional), Cascader для роли (required).

**When** Заполнить display_name=`Unknown User`, выбрать роль `vpc.network.view` (verb `view` из catalog KAC-122), click `Пригласить`.

**Then** `POST /iam/v1/users:invite{account_id, email, display_name, project_id:<current>, role_id:<…>}`.
**And** Operation done=true → toast «Приглашение отправлено».
**And** UI возвращает на main модалку. В autocomplete уже есть PENDING-user.
**And** Закрытие модалки → таблица показывает нового user с tag «Приглашён».

#### KAC-125.S-18 — SystemRolesTab vs CustomRolesTab

**Given** Cascader-блок open.

**When** Click таб `Системные роли`.

**Then** Cascader-tree содержит 54 system-role (отрисованных из fixed-tree §2.7).

**When** Click таб `Свои роли`.

**Then** Empty-state placeholder `Свои роли появятся после создания через API` (until KAC-122+).

#### KAC-125.S-19 — InviteIdempotent (re-invite не дублирует row)

**Given** User `usr-X` PENDING в `acc-A` (создан в S-01).

**When** Admin снова вызывает `Invite{account_id:"acc-A", email:"newbie@example.com"}` (тот же email).

**Then** Operation done=true.
**And** В `users` всё ещё **одна** row `usr-X` (UPSERT no-op).
**And** Backend re-эмитит Kratos magic-link event (для admin re-send-able UX).

#### KAC-125.S-20 — InviteWithEmailCaseInsensitive

**Given** Empty acc-A. Admin invite `Newbie@example.com` (mixed case).

**When** Admin позже invite `newbie@example.com` (lowercase).

**Then** Second invite — idempotent (один user-row, UPSERT-match через `lower(email)` UNIQUE-индекс).

### 7.3 Cross-cutting / E2E

#### KAC-125.S-21 — Full E2E: Invite → Magic-link → Activate → Visible in UI

**Given** Empty cluster e2c825 с admin@prorobotech.ru. Создан Account+Project.

**When** Admin invites `newbie@test.com` в Project `prj-default` с role `vpc.network.view` (resolved через role-catalog API).

**Then** PENDING-row создан. AB created. Kratos magic-link generated (URL логируется в admin-UI или viewable через `Operation.metadata.magic_link_url`).

**When** Manually копируем URL → открываем incognito tab → Kratos `/registration` или `/recovery` flow → задаём password → submit.

**Then** Kratos identity Y создан. Session active. Frontend перенаправляет на dashboard.
**And** `UpsertFromIdentity{external_id:"Y", email:"newbie@test.com"}` — PENDING-row активирован.
**And** UI: newbie@test.com заходит на `/iam/access?tab=Каталог` — видит **себя** (без admin AB он не может выдать access, но видит свою row через тенант default-deny: invited users в собственный Account).
**And** Admin заходит на `/iam/access?tab=Каталог` — видит newbie без tag «Приглашён» (теперь ACTIVE).

#### KAC-125.S-22 — Tenant Isolation Doesn't Leak Across Accounts

**Given** Account A (admin@a.com), Account B (admin@b.com). admin@a invited `shared@example.com` в acc-A (PENDING). admin@b invited тот же email в acc-B (PENDING).

**When** `shared@example.com` делает first login Kratos.

**Then** **Обе** PENDING-row активируются (две User-row, одна в каждом Account).
**And** В UI `shared@example.com` видит BreadcrumbSelector с двумя Account: acc-A + acc-B.
**And** `UserService.List` from acc-A context — `shared@example.com` видит только `usr-admin-A` + себя (`usr-shared-in-A`). НЕ видит users из acc-B.
**And** Switch BreadcrumbSelector на acc-B → таблица AB обновляется на acc-B.
**And** `GET /iam/v1/users?account_id=acc-B` `Authorization: Bearer <shared-user-token>` → `response.users` НЕ содержит `admin@a.com` (`account_id` filter обеспечивает isolation на server-side, не только UI-фильтрация).

### 7.4 Сценарии для D-7 / D-8 / Keto-tuple / Cascader-sync / m-3

#### KAC-125.S-23 — InvitedOnlyUserNoSelfAccount

**Given** Account `acc-A` (admin@a.com — owner). Kratos identity `X` ещё НЕ существует (никаких User-row в БД).
**And** Admin@a.com invite'ит email `invitee@example.com` в acc-A через `UserService.Invite`. PENDING-row создан (`usr-X-pending-A`, `account_id=acc-A`, `invite_status=PENDING`, `external_id=''`).
**And** `invitee@example.com` НЕ имеет ACTIVE-row ни в одном Account.

**When** `invitee@example.com` идёт на Kratos `/registration`, регистрируется, получает Kratos identity `X` (`sub=X`).
**And** Frontend вызывает `InternalUserService.UpsertFromIdentity{external_id:"X", email:"invitee@example.com", display_name:"Invitee"}`.

**Then** Step 1 (`FindPendingByEmail`) returns `[usr-X-pending-A]`.
**And** `ActivateInvite(usr-X-pending-A, "X", "Invitee")` → User-row `usr-X-pending-A` становится ACTIVE (`external_id="X"`).
**And** Step 2 (`FindActiveByExternalID("X")`) returns 1 row (только что активированную).
**And** **D-7**: `activatedAny=true` → `bootstrapNewIdentity` **НЕ вызывается** → новый bootstrap-Account `acc-X` НЕ создаётся.
**And** Финальное состояние БД: одна User-row `usr-X-pending-A`, один Account `acc-A`, invitee имеет доступ ТОЛЬКО к acc-A (через Keto-tuple, эмиченный через outbox).
**And** **D-9 post-invite primary context**: `UpsertFromIdentity` return-value `response.user.id = usr-X-pending-A` (first-activated row). UI на post-login flow читает `response.user.account_id = acc-A` и автоматически устанавливает BreadcrumbSelector на acc-A.
**And** В UI invitee видит ОДИН Account в BreadcrumbSelector — acc-A. У него НЕТ собственного «Personal cloud».

#### KAC-125.S-24 — InvitedOnlyUserCreatesOwnAccountExplicitly

**Given** Состояние после S-23: invitee — ACTIVE в acc-A, своего Account не имеет.

**When** Invitee в UI нажимает кнопку «Создать организацию» → frontend вызывает `POST /iam/v1/accounts {name:"My Cloud"}`.

**Then** `AccountService.Create` создаёт новый Account `acc-X-self` с `owner_user_id` указывающим на **новую** User-row `usr-X-in-self` (one Account → one User-row, cross-Account pattern из D-3, реализуется через тот же UpsertFromIdentity+bootstrap-path, но в режиме «explicit», а не auto).
**And** Финальное состояние: invitee имеет 2 User-row для одного Kratos identity `X`: `usr-X-pending-A` (в acc-A, invited) + `usr-X-in-self` (в acc-X-self, owner).
**And** В UI BreadcrumbSelector показывает оба Account.

#### KAC-125.S-25 — KetoMemberTupleAfterActivate

**Given** PENDING-row `usr-Z-in-A` (acc-A) активирован в S-05 (через `UpsertFromIdentity` → `ActivateInvite`).
**And** В `kacho_iam.outbox_events` enqueued event типа `keto_write` с payload `{tuple: "account:acc-A#member@user:usr-Z-in-A"}`.

**When** Outbox-drainer worker (poll 100ms tick, см. KAC-116 corelib `authz/keto`) подбирает event.
**And** Worker делает Keto `WriteRelationTuples` HTTP call с payload tuple.

**Then** Keto-test-container содержит relation-tuple `account:acc-A#member@user:usr-Z-in-A`.
**And** Verification: `keto-cli relation-tuples list --namespace account --subject user:usr-Z-in-A` returns tuple.
**And** Subsequent `Keto.Check{Subject:"user:usr-Z-in-A", Relation:"member", Object:"account:acc-A"}` returns `allowed=true`.
**And** `outbox_events.delivered_at IS NOT NULL` (drained).

**And worker idempotency** (m7): если первая Keto-write succeeded но `outbox_events.delivered_at` UPDATE failed (e.g. DB connection drop между Keto-call'ом и DB-write) → retry на next-tick (worker не видит `delivered_at IS NOT NULL` → re-emit) → Keto returns 200 OK на duplicate tuple (idempotent write, `WriteRelationTuples` upsert-style на same `(namespace, object, relation, subject)`) → `outbox_events.delivered_at` UPDATE succeed на retry → row marked delivered. Ссылка на `kacho-corelib/authz/keto`-tests (KAC-116). Integration-test S-25 включает negative-инъекцию: kill DB-connection между keto-write и delivered_at-update → expect retry → expect Keto-tuple count `= 1` (не 2).

Integration-test (`outbox_drainer_integration_test.go`) обязан проверить полный flow: ActivateInvite → outbox event written → worker pickup → Keto member-tuple verified + idempotency negative-инъекция.

#### KAC-125.S-26 — CascaderRoleSyncWithCatalog

**Given** Browser открывает `/iam/access?tab=Каталог`.
**And** Component на mount вызывает `iamApi.listRoles({account_id: "acc-A", page_size: 500})`.
**And** Server returns 54 system-roles + 0 custom (E0 baseline).

**When** User кликает «Настроить доступ» → выбирает Cascader-path `[iam, user, admin]`.

**Then** UI находит `role.name === "iam.user.admin"` среди загруженных 54 ролей (точное совпадение по name, БЕЗ `roles/` prefix; не derived из path).
**And** `roleNameToId["iam.user.admin"]` resolved через server response = `"rol" + md5("iam.user.admin").hex.first(17)` (актуальный ID из catalog'а KAC-122 миграции 0008; в коде НЕ hardcoded).
**And** Submit запрос `POST /iam/v1/access-bindings` содержит `role_id` = именно этот id, не captured-локально из hardcoded таблицы.

**Negative**: если role-catalog ещё loading (`listRoles` in-flight), Cascader отрисован с `disabled={true}` + `<Spin/>`-spinner. Submit-кнопка disabled — user физически не может кликнуть и сломать request.

#### KAC-125.S-27 — UserCreateDeprecated

**Given** kacho-iam запущен с миграцией `0009_user_per_account_invite_kac125.sql` (KAC-125 applied).
**And** kacho-proto содержит `UserService.Create` с `option deprecated = true;` (D-8).

**When** Клиент (старый CLI / curl) вызывает `POST /iam/v1/users {email: "x@example.com"}`.

**Then** HTTP response: `410 Gone`.
**And** Body: `{"code": 9, "message": "UserService.Create deprecated; use UserService.Invite"}` (gRPC code 9 = FAILED_PRECONDITION).

**When** Клиент вызывает gRPC `UserService.Create` напрямую (bypass api-gateway).

**Then** gRPC status `FAILED_PRECONDITION` (code 9), message `"UserService.Create deprecated; use UserService.Invite"`.
**And** `buf breaking --against` остаётся зелёным (deprecation — non-breaking), потому что method/messages из proto не удалены.

#### KAC-125.S-28 — OperationsScopedPerAccountRow

**Given** Admin (один Kratos identity, `external_id="X"`) invited в acc-A (имеет ACTIVE-row `usr-X-in-A`) и в acc-B (имеет ACTIVE-row `usr-X-in-B`).
**And** Admin currently залогинен через Kratos session — две User-row, обе ACTIVE.

**When** Admin в UI переключается на acc-A (BreadcrumbSelector → acc-A). Делает `POST /iam/v1/users:invite{account_id:"acc-A", email:"newbie@example.com"}`.

**Then** `operations.principal_id = usr-X-in-A` (User-row для acc-A-context'а).

**When** Admin переключается на acc-B (BreadcrumbSelector → acc-B). Вызывает `GET /iam/v1/operations`.

**Then** Server-side filter `WHERE principal_id = ctx.user.id` → `principal_id = usr-X-in-B`.
**And** Invite-Operation из acc-A (с `principal_id=usr-X-in-A`) НЕ matches filter → НЕ возвращается в этом response.
**And** Document'у: чтобы увидеть эту Operation, admin должен переключиться обратно на acc-A.

#### KAC-125.S-29 — InviteeWithActiveInAnotherAccountReturnsToSelfSignup (R-5 mitigation)

**Given** User X (Kratos identity `external_id="X"`) уже ACTIVE в acc-A (owner of acc-A, через self-signup в прошлом).
**And** В acc-B (или любом другом Account) у X нет PENDING-invite.

**When** X идёт на `/registration` снова (re-signup без context, например, очистил cookies и пытается «начать заново»).
**And** Kratos identifier matching по email возвращает существующего identity X → frontend вызывает `UpsertFromIdentity{external_id:"X", email:"x@example.com"}`.

**Then** Step 1 `FindPendingByEmail` returns empty (нет PENDING-invite).
**And** `activatedAny=false`.
**And** Step 2 `FindActiveByExternalID("X")` returns 1 row (`usr-X-in-A`).
**And** **D-7**: `activatedAny=false && existing != nil` → `bootstrapNewIdentity` **НЕ вызывается** (нет new auto-Account).
**And** Function returns `existing` (= `usr-X-in-A`).
**And** Финально: user остаётся в acc-A, никаких новых Account/User-row не создано. UI показывает один Account в BreadcrumbSelector.

#### KAC-125.S-30 — BootstrapTxDeferrableFKCheck (M6)

**Given** Schema migration `0009_user_per_account_invite_kac125.sql` applied на fresh DB.
**And** FK constraints `users_account_fk` (на `users.account_id → accounts(id)`) и `accounts_owner_fk` (на `accounts.owner_user_id → users(id)`) — оба `DEFERRABLE INITIALLY DEFERRED` (см. §2.4 шаги 3, 3a).
**And** Pre-generated UUIDs: `accountID := uuid.New()`, `userID := uuid.New()`.

**When** `bootstrapNewIdentity` TX выполняется в следующей последовательности внутри одной TX:
1. `INSERT INTO users (id, account_id, external_id, email, ...) VALUES (userID, accountID, 'X', 'fresh@example.com', ...)`.
   — на этот момент row `accounts(id=accountID)` НЕ существует; FK `users_account_fk` нарушен, но check отложен.
2. `INSERT INTO accounts (id, owner_user_id, name) VALUES (accountID, userID, 'Personal cloud')`.
   — теперь обе FK становятся валидными.
3. `INSERT INTO projects (...)` + `INSERT INTO access_bindings (...)` + `INSERT INTO outbox_events (...)`.
4. `COMMIT`.

**Then** `COMMIT` succeeds (FK check на commit-стадии проходит — оба row существуют).
**And** Verification: `SELECT id, account_id FROM users WHERE id=$userID` returns row; `SELECT id, owner_user_id FROM accounts WHERE id=$accountID` returns row; `accounts.owner_user_id = users.id` И `users.account_id = accounts.id` (cyclic FK satisfied).

**Negative-проба** (доказательство необходимости DEFERRABLE):
**When** Тот же flow с `SET CONSTRAINTS ALL IMMEDIATE` в начале TX:
```sql
BEGIN;
SET CONSTRAINTS users_account_fk, accounts_owner_fk IMMEDIATE;
INSERT INTO users (id, account_id, ...) VALUES (userID, accountID, ...);  -- здесь падает
```

**Then** Immediate FK check срабатывает на шаге 1 (insert user с не-существующим account_id) → SQLSTATE `23503` (foreign_key_violation), error `"insert or update on table "users" violates foreign key constraint "users_account_fk""`.
**And** Это доказывает: DEFERRABLE INITIALLY DEFERRED **необходим** для bootstrap-flow; без него single-TX bootstrap невозможен.

Integration-test `bootstrap_tx_deferrable_test.go` (testcontainers Postgres) выполняет оба пути и asserts:
- happy path COMMIT succeeds, two rows visible.
- negative path с `SET CONSTRAINTS IMMEDIATE` падает с SQLSTATE 23503 на первом INSERT.

---

## 8. Definition of Done

### 8.1 Backend (kacho-iam)

- [ ] Migration `0009_user_per_account_invite_kac125.sql` applied на dev cluster (после greenfield wipe, последовательно поверх 0001…0008).
- [ ] FK `users.account_id` и `accounts.owner_user_id` помечены `DEFERRABLE INITIALLY DEFERRED` (см. §2.4.5).
- [ ] Newtypes `InviteStatus`, `domain.User` обновлены, `Validate()` зелёный.
- [ ] Use-case `internal/apps/kacho/api/user/invite.go` создан.
- [ ] `internal/apps/kacho/api/internal_user/upsert_from_identity.go` rewritten под PENDING-aware logic + D-7 (skip bootstrap if activatedAny || existing).
- [ ] Use-case `internal/apps/kacho/api/user/list.go` rewritten под default-deny + `account_id` filter.
- [ ] `UserService.Create` handler возвращает `FailedPrecondition "Use UserService.Invite instead"` (D-8).
- [ ] api-gateway REST `POST /iam/v1/users` возвращает 410 Gone (D-8).
- [ ] Keto namespace-config **НЕ меняется** (остаётся flat `namespaces: [{id, name}]` в `kacho-deploy/helm/umbrella/values.dev.yaml:432-477`). Cascade `admin > editor > viewer → member` реализуется client-side в Go-helper'е `relationsImplying` (existing pattern KAC-119/120/121).
- [ ] Helper `KetoClient.relationsImplying` расширен case'ом `"member"` → `["member","viewer","editor","admin","owner"]` (D-9, см. §2.6).
- [ ] Helper `KetoClient.CanInviteUsers(ctx, principalID, accountID)` добавлен в `kacho-iam/internal/clients/keto_client.go` — **один `Check(editor)` call** через cascade-traversal покрывает {editor, admin, owner}.
- [ ] Bootstrap-TX (`bootstrapNewIdentity` use-case) вставляет **2 AccessBinding rows always** (account-admin + project-admin); bootstrap-admin (`@prorobotech.ru`) — без extra AB, только +1 Keto-tuple `kacho_system:root#admin@user:<id>`.
- [ ] Все role-IDs в коде / тестах используют `sysRoleID(name) = "rol" + md5(name).hex.first(17)` lookup из catalog'а KAC-122 (миграция 0008). Никаких hardcoded `"rol-iam-account-admin"` / `"rol00000000000000vpcvw"`.
- [ ] Integration tests (testcontainers Postgres + Keto-container):
  - [ ] S-01 happy path.
  - [ ] S-04 cross-Account scenario.
  - [ ] S-05 activate-on-first-login.
  - [ ] S-06 self-signup bootstrap-flow (**2 AB always; +1 Keto-tuple для bootstrap-admin**; 3-4 outbox events).
  - [ ] **S-07b EditorInvitesSuccessfully** (D-9 cascade: один Check(editor) → can invite через cascade-traversal).
  - [ ] S-09 tenant isolation default-deny.
  - [ ] S-11 concurrent-invite race-test.
  - [ ] S-13 delete PENDING-user.
  - [ ] **S-23 InvitedOnlyUserNoSelfAccount** (D-7).
  - [ ] **S-24 InvitedOnlyUserCreatesOwnAccountExplicitly** (D-7 part 2).
  - [ ] **S-25 KetoMemberTupleAfterActivate** — `outbox_drainer_integration_test`: ActivateInvite → outbox event written → worker pickup → Keto member-tuple verified + idempotency negative-инъекция (m7).
  - [ ] **S-27 UserCreateDeprecated** — gRPC + REST 410.
  - [ ] **S-28 OperationsScopedPerAccountRow** — principal_id filter.
  - [ ] **S-29 ReSignupNoBootstrap** (R-5).
  - [ ] **S-30 BootstrapTxDeferrableFKCheck** — `bootstrap_tx_deferrable_test.go`: happy path COMMIT + negative path с `SET CONSTRAINTS IMMEDIATE` падает 23503 (M6).
- [ ] sqlc queries сгенерированы, `make generate` зелёный.

### 8.2 Proto (kacho-proto)

- [ ] `kacho/cloud/iam/v1/user_service.proto`: новые message `InviteUserRequest`, `InviteUserMetadata` (с `magic_link_url` field 3), `InviteStatus` enum + поля в `User` (`account_id`, `invite_status`, `invited_by`).
- [ ] `UserService.Create` помечен `option deprecated = true;` (не удалён — D-8).
- [ ] `buf lint` зелёный.
- [ ] `buf breaking --against` **зелёный** (Adding optional fields + deprecation — non-breaking; Create оставлен в proto, поэтому method-removal warning не срабатывает).
- [ ] `gen/go/` regenerated и committed.

### 8.3 Api-gateway

- [ ] Новый RPC `UserService.Invite` зарегистрирован в public mux (REST: `POST /iam/v1/users:invite`).
- [ ] `UserService.List` — `account_id` query-param пробрасывается.
- [ ] Internal mux без изменений (UpsertFromIdentity уже внутри).
- [ ] REST `POST /iam/v1/users` (Create) перехватывается middleware и возвращает 410 Gone до проксирования на upstream (D-8).

### 8.4 UI (kacho-ui)

- [ ] Route `/iam/access` + redirect `/iam/access-bindings`.
- [ ] AccessPage с tabs Облако/Каталог + кнопкой «Настроить доступ».
- [ ] Модалка «Выдача доступа» (combobox с категориями + autocomplete + invite-fallback CTA).
- [ ] **Cascader role-catalog preload** через `iamApi.listRoles({account_id, page_size:500})` — НЕ hardcoded таблица (M-4).
- [ ] Cascader-tree derived из role-catalog (54 system-roles на E0) + chip-list selected roles + System/Custom tabs; Custom-tab = `roles.filter(r => !r.is_system && r.account_id === accountId)` (m-1).
- [ ] Cascader disabled + spinner пока role-catalog в loading (no broken submit, S-26).
- [ ] Invite sub-modal (email pre-filled + display_name + role + submit).
- [ ] PENDING-user отображается tag «Приглашён».
- [ ] CTA «Создать организацию» в UI для invited-only users (D-7, S-24).
- [ ] `npx tsc --noEmit` зелёный.
- [ ] Visual review модалок vs `image copy.png` / `image copy 2.png` / `image copy 3.png` (manual).

### 8.5 Tests (kacho-test + newman)

- [ ] Newman cases (`tests/newman/cases/iam_invite.py`):
  - [ ] Invite happy + idempotent re-invite.
  - [ ] Invite negative: missing role_id when project_id set.
  - [ ] Invite negative: cross-Account project_id.
  - [ ] Invite negative: no permission (viewer → `CanInviteUsers` cascade returns allowed=false; helper делает один Check(editor) который falls through cascade {editor,admin,owner}).
  - [ ] **Deprecated UserService.Create returns 410 / FAILED_PRECONDITION (S-27).**
- [ ] Playwright (`kacho-test/e2e/iam-invite.spec.ts`):
  - [ ] S-14 route redirect.
  - [ ] S-15 tabs Облако/Каталог.
  - [ ] S-16 cascader multi-select → N AB created.
  - [ ] S-17 invite-fallback CTA flow.
  - [ ] S-21 full E2E: invite → magic-link → activate.
  - [ ] **S-26 cascader role-catalog sync (loading-state + exact name-match)**.
  - [ ] **S-24 invited-only-user сначала видит один Account, нажимает «Создать организацию» → получает второй**.

### 8.6 Vault

- [ ] `obsidian/kacho/resources/iam-user.md` обновлён: `account_id`, `invite_status`, `invited_by` fields + lifecycle (PENDING → ACTIVE).
- [ ] `obsidian/kacho/rpc/iam-user-service.md` обновлён: новый Invite RPC.
- [ ] `obsidian/kacho/edges/iam-to-keto-tuples.md` обновлён: новая relation `member`.
- [ ] `obsidian/kacho/KAC/KAC-125.md` создаст user отдельно — НЕ в этом acceptance.

### 8.7 Roll-out

- [ ] Wipe `kacho_iam` DB на dev cluster e2c825 (greenfield).
- [ ] Build + push images (api-gateway, kacho-iam, kacho-ui) с tag `kacho-<ts>`.
- [ ] `helm upgrade` + `kubectl rollout` зелёный.
- [ ] Smoke (`make smoke-iam`) → S-01, S-02, S-09, S-21 проходят manually либо через Newman runner.
- [ ] Заказчик подключается к финальной верификации (workspace CLAUDE.md §«Coordination» — step 7).

---

## 9. Risks / открытые вопросы

| # | Risk | Mitigation |
|---|------|------------|
| R-1 | Kratos magic-link генерируется но не доставляется → invitee не знает, что приглашён | UI показывает админу URL после Invite через `Operation.metadata.magic_link_url`. Admin копирует вручную. (Принято — D-1) |
| R-2 | Cross-Account user видит две User-row в BreadcrumbSelector → может запутаться | UI tooltip «Вы участник нескольких организаций» + label `<Account.name>` рядом с своим именем. Документация UX в KAC-125 wrap-up. |
| R-3 | Greenfield wipe ломает dev-данные admins тестирующих E0-E5 | Notification в Slack за 24h до wipe. Alternative — backfill SQL (§5). Принято wipe. |
| R-4 | Cascader UX перегружен (5 модулей × 9 ресурсов × 4 verb = до 180 leaves) | Search-filter в Cascader (`showSearch={{filter}}`). Если показывается убогим — fallback на двухступенчатый Select (module → role). KAC-125 follow-up. |
| R-5 | PENDING-row создаётся в acc-A, но при first login Kratos identity Y с email=X auto-create новый Account через KAC-117 ↔ конфликт двух code-path | `UpsertFromIdentity` сначала `FindPendingByEmail` (step 1 §3.2), потом `FindActiveByExternalID` (step 2), потом bootstrap. PENDING побеждает над auto-create. Integration test S-04+S-05 проверяет именно эту последовательность. |

---

## 10. Changelog

- **v1 (2026-05-18)** — initial draft. Передан `acceptance-reviewer` на review.
- **v2 (2026-05-18)** — fix-list по review v1 (`❌ CHANGES REQUESTED`). Изменения:
  - **B-1**: added D-7 (invited-only-user — NO bootstrap-Account); added scenarios S-23, S-24; rewrote §3.2 logic to make bootstrap-skip explicit (`!activatedAny && existing == nil`).
  - **B-2**: added §2.4.5 chicken-and-egg FK resolution via `DEFERRABLE INITIALLY DEFERRED` on both `users.account_id` and `accounts.owner_user_id`; documented bootstrap-TX flow (pre-generated UUIDs).
  - **B-3**: rewrote §3.1 Keto-check to use Ory permission protocol (`Permission: "iam.user.create"`, not relation); added Keto namespace `account` declarative config with permits.iam.user.create = admin OR editor (viewer cannot invite); added `magic_link_url` field to `InviteUserMetadata`.
  - **B-4**: added explicit `DROP CONSTRAINT users_external_id_check + ADD CONSTRAINT (length 0..256)` to allow `external_id=''` for PENDING; clarified partial-UNIQUE `WHERE external_id <> ''` semantics (PENDING-rows не конфликтуют).
  - **B-5**: added D-8 (`UserService.Create` deprecated, not removed); added scenario S-27; updated §3.5 RPC table, §6 error mapping, §8.2 proto checklist (`buf breaking` зелёный).
  - **M-1**: added §3.4 Principal-tracking + scenario S-28 (`operations.principal_id` per-User-row, OperationService.List filtered per-Account-context).
  - **M-2**: renamed migration `0004_*` → `0009_user_per_account_invite_kac125.sql`; documented sequential apply order (0001…0008 → 0009) in §5.
  - **M-3**: added scenario S-25 KetoMemberTupleAfterActivate (end-to-end outbox→worker→Keto).
  - **M-4**: rewrote §4.4 Cascader to preload via `iamApi.listRoles({account_id})` instead of hardcoded table; added scenario S-26 (loading-state + exact name-match).
  - **m-1**: clarified Custom-tab filter (`!r.is_system && r.account_id === ctx.accountId`).
  - **m-2**: SQL UPSERT changed from `DO UPDATE SET display_name=...` to `DO NOTHING + SELECT existing` (preserve display_name on re-invite).
  - **m-3**: added scenario S-29 (R-5 mitigation: re-signup with existing ACTIVE returns to that ACTIVE, no new bootstrap).
  - **m-4**: rewrote final then-step of S-22 to assert `GET /iam/v1/users?account_id=acc-B` server-side filter (not just UI).
  - **Total GWT scenarios**: 22 → 29.
- **v3 (2026-05-18)** — fix-list по review v2 round 2 (`❌ CHANGES REQUESTED`: 3 blockers + 3 majors + 4 minors). Изменения:
  - **B6** (OPL невыполним): added **D-9** decision (relation-based Keto Check, не OPL); rewrote §2.6 — заменён OPL `.ts`-block на YAML-style namespace-config с subject-set cascade `admin/editor/viewer → member`; rewrote §3.1 use-case pseudo-code на `keto.CanInviteUsers` helper (admin OR editor via two Check calls); added **S-07b** EditorInvitesSuccessfully (D-9 cascade demonstrated).
  - **B7** (D-8 ломает KAC-117 bootstrap): added explicit clarification в D-8: deprecation касается ТОЛЬКО публичного `UserService.Create`, internal bootstrap-path не затронут; extended §2.4.5 `bootstrapNewIdentity` TX до 6 шагов (user + account + project + 3-4 self-grant AB + 3-4 Keto outbox events + COMMIT); extended **S-06 SelfSignup** до full 3-4 AB + 3-4 outbox events с bootstrap-admin branch.
  - **B8** (migration sequence): rewrote §5 — реальный список миграций `0001, 0002, 0007, 0008, 0009` (промежуточных 0003-0006 нет на disk); убран ellipsis «0003…».
  - **M5** (corelib transactor): added pseudo-code note в §2.4.5 — `repo.Writer(ctx).Transact(...)` это упрощённая нотация над `corelib/db.Transactor.InTx(ctx, fn(tx pgx.Tx))`.
  - **M6** (DEFERRABLE FK integration test): added **S-30** BootstrapTxDeferrableFKCheck — happy path COMMIT + negative проба `SET CONSTRAINTS IMMEDIATE` падает с SQLSTATE 23503; added `bootstrap_tx_deferrable_test.go` в §8.1 DoD.
  - **M7** (post-invite primary context): added second clause to **D-9** — `UpsertFromIdentity` returns first-activated row, UI auto-switches BreadcrumbSelector; updated S-04 + S-23 last-then-step.
  - **m5**: removed duplicate `viewer` row в §6 error mapping table (объединено в одну строку с reference на D-9 helper).
  - **m6**: added pagination footnote в §4.4 — auto-paginate `listRoles` при `roles.length >= 500` (loop until `next_page_token=''`).
  - **m7**: added outbox idempotency clause в **S-25** — retry-on-DB-failure→Keto-200-on-duplicate→delivered_at UPDATE succeed; included negative-инъекция в integration test.
  - **m8** (Keto subject-set rewrite): added YAML namespace-config с `union: [this, computed_subjectset(admin/editor/viewer)]` в §2.6.
  - **Total GWT scenarios**: 29 → 31.
- **v4 (2026-05-18)** — fix-list по review v3 round 3 (`❌ CHANGES REQUESTED`: 3 NEW blockers + 2 majors + 1 minor; B8/M5/M6/M7 закрыты, B6/B7 частично). Изменения:
  - **NEW-B9** (§2.6 YAML namespace-config факт неверен): existing `kacho-deploy/helm/umbrella/values.dev.yaml:432-477` — это **flat form** `namespaces: [{id, name}]` БЕЗ `relations:`/`union:`/`computed_subjectset`. Удалён вымышленный YAML-block из §2.6. Полностью переписан §2.6 — cascade `admin > editor > viewer → member` реализуется **client-side в Go-helper'е** `KetoClient.relationsImplying` (existing pattern KAC-119/120/121); Keto-config не меняется; `relationsImplying("member") = ["member","viewer","editor","admin","owner"]` — это новое расширение helper'а (только в коде). Обновлены D-9 entry в §0.3, DoD §8.1 и changelog framing.
  - **NEW-B10** (bootstrap role-IDs не существуют в catalog): убраны hardcoded placeholder'ы `"rol-iam-account-admin"` / `"rol-iam-project-admin"` / `"rol-system-admin"`. Введён хелпер `sysRoleID(name) = "rol" + md5(name).hex.first(17)` (детерминированный lookup из KAC-122 catalog seed, миграция 0008_role_catalog_kac122.sql). System-admin marker = **только Keto-tuple** `kacho_system:root#admin@user:<id>`, **НЕ** AccessBinding. §2.4.5 step 3.4 и §7.S-06 step 4 переписаны: **2 AB always** (`iam.account.admin` + `iam.project.admin`), bootstrap-admin (`@prorobotech.ru`) — без extra AB, только +1 Keto-tuple. DoD §8.1 обновлён.
  - **NEW-B11** (Cascader verbs `admin/editor/viewer` обсолетны; реальные `admin/edit/view` без `roles/` prefix): §2.7 Cascader spec обновлён — verbs точно из KAC-122 catalog (`admin/edit/view`); role-names БЕЗ `roles/` prefix (`vpc.network.admin`, НЕ `roles/vpc.network.admin`); resources синхронизированы с catalog (`security_group`, `route_table`, `network_load_balancer`, `target_group`, etc — underscored form). §4.4 frontend Cascader rewritten: derive `roleName = `${m}.${r}.${v}`` БЕЗ prefix, lookup в preloaded role-map. S-02/S-03 role-IDs: resolved через `<role-name>` lookup, не hardcoded `rol00000000000000vpcvw`. S-16/S-17/S-21 verb `editor`→`edit`, `viewer`→`view`. S-26 ID resolution описан как `"rol" + md5(name).hex.first(17)` (dynamic, не hardcoded).
  - **MAJ-1** (CanInviteUsers редундантный double-check): §2.6 `CanInviteUsers` упрощён до **одного `Check(editor)` call** — `relationsImplying("editor") = ["editor","admin","owner"]` cascade-traversal внутри helper'а покрывает все три relations. §3.1 use-case pseudo-code обновлён (один Check, не два). §7.S-07 / §7.S-07b переписаны под one-Check-cascade semantics.
  - **MAJ-2** (S-10 KetoMemberRelationCascade framing): §7.S-10 полностью переписан — explicit `account#member@user` tuple emit'ится outbox-эмитом при activation (S-25 verification); `KetoClient.Check(user, "member", account)` returns true через direct tuple lookup на first cascade-iter; client-side cascade `["member","viewer","editor","admin","owner"]` — defensive fallback. Cascade `admin → member` Keto-config-side НЕ используется (out of KAC-125 scope; namespace-config Keto остаётся flat).
  - **MIN-1** (count drift §2.4.5 vs S-06): §2.4.5 step 3.4 — «3 self-grant AB» → «2 self-grant AB always; bootstrap-admin gets +0 AB +1 Keto-tuple»; S-06 wording синхронизирован.
  - **Total GWT scenarios**: 31 → 31 (no scenarios added/removed, только уточнения existing).

#kac #iam #invite-flow #user-per-account #cascader
