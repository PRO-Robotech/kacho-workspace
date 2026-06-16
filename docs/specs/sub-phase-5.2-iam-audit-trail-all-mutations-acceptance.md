# Sub-phase 5.2 (kacho-iam — durable audit-trail on all security-relevant mutations) — Acceptance

> Статус: APPROVED
> Дата: 2026-06-16
> Ревьюер: acceptance-reviewer (✅ APPROVED, round 2)
> Эпик/тикет: KAC-122 (Round-5 P1 — IAM compliance audit-trail)

## Обзор

Для IAM control-plane запись «кто создал / выдал / отозвал что, кому и когда» — это
обязательный, **durable** compliance-факт. Сегодня `audit_outbox`-строку атомарно (в
writer-tx) эмитят только `AccessBinding.Create`/`Delete`. Все остальные
security-relevant мутации (cluster-admin grant/revoke, session revoke / force-logout,
CRUD над Account/Project/User/ServiceAccount/Group/Role, SAKey issue/revoke) **не пишут
ничего** — audit-trail неполон. Эта волна расширяет существующий паттерн
`EmitAuditEvent`-в-writer-tx (запрет #10) на ВСЕ перечисленные мутации, не меняя
поведение/контракт ответов самих RPC (чисто аддитивный audit), и добавляет
regression-guard на латентный баг #126 (17-char id проваливал `audit_outbox_id_check`).

**Это волна ТОЛЬКО emit-стороны** (writer-tx audit-строки). Drainer/export-pipeline
(`AuditOutboxRepo`, статус-машина `pending→in_flight→sent`) уже существует и НЕ
меняется. Поведение и return-контракты мутаций НЕ меняются — добавляется только
audit-строка в той же транзакции.

## Нормативные ссылки (не дублируются в тело сценариев)

- `.claude/rules/data-integrity.md` §«Within-service инварианты — ТОЛЬКО на DB-уровне»
  (запрет #10): audit-строка коммитится в ТОЙ ЖЕ транзакции, что и мутация —
  commit-together-or-rollback-together; никакого best-effort side-channel, который может
  потерять запись при закоммиченной мутации.
- `.claude/rules/security.md`: cluster-admin / force-logout — Internal* RPC (:9091),
  не на external endpoint; инфра-чувствительные и секретные данные — не на публичной
  поверхности и **не в audit-payload**.
- `.claude/rules/api-conventions.md`: error-format, sync-vs-async, Operation-контракт.
- kacho-iam `CLAUDE.md` §2.5 (principal-носитель), §4.x (writer-tx паттерны).

## Ground-truth (зафиксировано — сценарии опираются на это, не на догадки)

- **Канонический паттерн (шаблон):** `internal/apps/kacho/api/access_binding/create.go` /
  `delete.go` зовут `w.AccessBindingsW().EmitAuditEvent(ctx, AuditEvent{…})` ВНУТРИ
  `doCreate`/`doDelete`, в одной writer-tx с самой мутацией, перед `w.Commit(ctx)`.
- **Репо-уровень:** `abWriter.EmitAuditEvent` (`internal/repo/kacho/pg/access_binding_repo.go`)
  делает один `INSERT INTO kacho_iam.audit_outbox (...) VALUES (...)` с
  `status='pending'`, `id = newAuditEventID()`. Существует и обобщённый
  `AuditOutboxRepo.InsertTx(ctx, tx, AuditOutboxEntry)`
  (`internal/repo/kacho/pg/audit_session_revocation_repos.go`) — caller контролирует tx.
- **id-генератор:** `newAuditEventID()` → `evt_<22-char crockford-base32>`, удовлетворяет
  `audit_outbox_id_check` (`^evt_[0-9A-HJKMNP-TV-Za-hjkmnp-tv-z]{20,30}$`). `domain.NewKac127ID`
  (17-char body) **проваливает** CHECK — это и был латентный баг #126 (hook-emit silently
  no-op). Domain-валидация: `domain.AuditEventID.Validate()` / `EventTypeName.Validate()`.
- **Таблица:** `kacho_iam.audit_outbox(id, event_type, tenant_account_id, event_payload jsonb,
  status, attempts, created_at, next_attempt_at)` + CHECK'и: `audit_outbox_id_check`,
  `audit_outbox_event_type_check` (`^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$`, длина 1..128),
  `audit_outbox_payload_object_ck` (payload — JSON object), `audit_outbox_status_check`.
- **Principal/actor:** источник — `authzguard.PrincipalUserID(ctx)` (анти-spoofing; НИКОГДА
  из тела запроса). Тот же principal, что Operations пишет в `principal_type/principal_id/
  principal_display_name` (CLAUDE.md §2.5). Для async-мутаций principal захватывается
  **синхронно в Execute** (до спавна worker), как `actor` в `delete.go`.
- **Per-mutation реальность writer-tx** (важно для DoD — без этого atomicity недостижима):

  | Use-case | RPC / сервис | Sync/Async | Транзакция сегодня | actor сегодня |
  |---|---|---|---|---|
  | cluster GrantAdmin | `InternalClusterService.GrantAdmin` (Internal) | sync (`Operation.done=true`) | `txb.Begin → pgx.Tx`, `relations.EmitWriteTx(ctx,tx,…)`, `tx.Commit` | `PrincipalUserID(ctx)` sync |
  | cluster RevokeAdmin | `InternalClusterService.RevokeAdmin` (Internal) | sync | `txb.Begin → pgx.Tx`, `relations.EmitDeleteTx(ctx,tx,…)`, `tx.Commit` | `PrincipalUserID(ctx)` sync |
  | session Revoke | `SessionRevocationsService.Revoke` (public + Internal) | sync | adapter single-stmt upsert (`Revoke`/`RevokeAllUserTokens`) — **нет caller-tx, доступного use-case** | `RevokeInput.RevokedBy` (из principal) |
  | force-logout | `InternalIAMService.ForceLogout` (Internal) | sync | adapter `RevokeAllUserTokens` single-stmt | `PrincipalUserID(ctx)` sync |
  | SAKey Issue | `SAKeyService.IssueSAKey` (public) | **async** (`operations.Run`) | `tx.Begin → pgx.Tx` в worker | сейчас не захватывается → нужно захватить sync |
  | SAKey Revoke | `SAKeyService.RevokeSAKey` (public) | **async** | `tx.Begin → pgx.Tx` в worker | сейчас не захватывается → нужно захватить sync |
  | Account/Project/User/SA/Group/Role Create/Update/Delete | публичные `*Service` | **async** (`operations.Run`) | writer-tx (`repo.Writer(ctx)` → `Commit/Rollback`) внутри worker | `PrincipalUserID(ctx)` sync |

  **Следствие для дизайна:** для use-case, где сегодня НЕТ caller-видимой транзакции
  (session Revoke, force-logout — single-statement adapter), атомарный audit-emit требует
  **обернуть мутацию + audit-INSERT в одну транзакцию** (расширить adapter tx-scoped
  вариантом). Это — часть DoD соответствующих суб-PR (см. per-event сценарии 5.2-03/04/05
  и сквозные atomicity-сценарии 5.2-34/35).
- **Audit-emitter availability:** метод `EmitAuditEvent` сегодня есть ТОЛЬКО на
  `access_binding` Writer-iface. Обобщённая инфра — `AuditOutboxRepo.InsertTx(ctx,tx,…)`.
  Дизайн-решение этой волны: ввести **обобщённый audit-emit порт** (newtype-payload в
  repo-iface, как `access_binding.AuditEvent`), вызываемый из каждого writer-tx через
  `AuditOutboxRepo.InsertTx` с `id = newAuditEventID()`. Конкретную форму порта определяет
  `rpc-implementer`/`db-architect-reviewer`; контракт acceptance — только наблюдаемый
  результат (строка с нужными `event_type`/payload/actor, атомарно).

---

## EventType-таксономия (полная таблица — нормативно)

`event_type` = `iam.<resource>.<action>`, snake_case-сегменты, удовлетворяет
`audit_outbox_event_type_check`. Существующие два значения (`iam.access_binding.granted`/
`iam.access_binding.revoked`) НЕ меняются. Новые:

| Use-case (RPC) | `event_type` |
|---|---|
| `AccessBinding.Create` (существует) | `iam.access_binding.granted` |
| `AccessBinding.Delete` (существует) | `iam.access_binding.revoked` |
| `InternalClusterService.GrantAdmin` | `iam.cluster_admin.granted` |
| `InternalClusterService.RevokeAdmin` | `iam.cluster_admin.revoked` |
| `SessionRevocationsService.Revoke` (single jti) | `iam.session.revoked` |
| `SessionRevocationsService.Revoke` (revoke_all_user_tokens=true) | `iam.session.all_revoked` |
| `InternalIAMService.ForceLogout` | `iam.session.force_logout` |
| `AccountService.Create` | `iam.account.created` |
| `AccountService.Update` | `iam.account.updated` |
| `AccountService.Delete` | `iam.account.deleted` |
| `ProjectService.Create` | `iam.project.created` |
| `ProjectService.Update` | `iam.project.updated` |
| `ProjectService.Delete` | `iam.project.deleted` |
| `ProjectService.Move` (если RPC существует¹) | `iam.project.moved` |
| `UserService.Create` / `InternalUserService.UpsertFromIdentity` (insert) | `iam.user.created` |
| `UserService.Update` / Upsert (update) | `iam.user.updated` |
| `UserService.Delete` | `iam.user.deleted` |
| `ServiceAccountService.Create` | `iam.service_account.created` |
| `ServiceAccountService.Update` | `iam.service_account.updated` |
| `ServiceAccountService.Delete` | `iam.service_account.deleted` |
| `GroupService.Create` | `iam.group.created` |
| `GroupService.Update` | `iam.group.updated` |
| `GroupService.Delete` | `iam.group.deleted` |
| `GroupService.AddMember` (если RPC существует¹) | `iam.group.member_added` |
| `GroupService.RemoveMember` (если RPC существует¹) | `iam.group.member_removed` |
| `RoleService.Create` | `iam.role.created` |
| `RoleService.Update` | `iam.role.updated` |
| `RoleService.Delete` | `iam.role.deleted` |
| `SAKeyService.IssueSAKey` | `iam.sa_key.issued` |
| `SAKeyService.RevokeSAKey` | `iam.sa_key.revoked` |

¹ Помечены `(если RPC существует)` те мутации, наличие которых `rpc-implementer` ОБЯЗАН
сверить с актуальными proto/use-case (`ProjectService.Move`, `Group` member-RPC,
публичный `UserService.Create` vs только internal Upsert). Если RPC нет в текущей
поверхности — строка таксономии НЕ реализуется (нет мутации → нет audit-события); это
фиксируется в DoD как «N/A — RPC отсутствует», а не угадывается. Поведение и контракт
мутаций не меняются — только добавляется audit.

---

## Payload (нормативно)

`event_payload` — JSON object (CHECK), camelCase-ключи. Обязательный минимум для каждого
события:

- `actor` — объект `{ "principalType": "<user|service_account|system>", "principalId":
  "<usr…|sva…|system>", "principalDisplayName": "<email|name>" }`. Источник —
  `PrincipalFromContext` (анти-spoofing). Если caller-identity неизвестен (system/bootstrap
  путь) — `principalId="system"`/`bootstrap`, НЕ выдуманный; поле не пустое и не сфабриковано.
- `resourceType` / `resourceId` — тип и id ресурса, над которым выполнена мутация
  (`acc…`/`prj…`/`usr…`/`sva…`/`grp…`/`rol…`/`acb…`/`soc…`/`<cluster_admin_grant id>`).
- `subjectId` / `subjectType` — для событий «над субъектом» (cluster-admin grant/revoke →
  целевой `usr…`; session/force-logout → целевой `user_id`; group member → member-id+type).
- `tenantAccountId` — Account-scope, когда известен (для per-account audit-запросов);
  иначе отсутствует/NULL в `tenant_account_id`-колонке.
- ключевые domain-поля события: для Create — `name`; для Update — что изменилось
  (см. ниже §Update-семантика); для Role — id роли (НЕ обязательно весь permissions-набор);
  для session — `reason`, `tokenJti`(если single)/флаг all; для SAKey — `keyId`, `keyAlgorithm`.
- `eventTime`/`when` — берётся из `audit_outbox.created_at` (server `now()` внутри tx);
  отдельным полем дублировать не обязательно (created_at — источник истины «когда»).

**Запрет на секреты (нормативно, проверяется сценарием 5.2-36):** в payload НИКОГДА не
попадают: private-key material SAKey (`privateKeyPem`), client_secret/Hydra-секрет,
session/refresh/access-токены (`tokenJti` — это идентификатор отозванного токена, не сам
токен; допустимо), пароли. SAKey-события несут только `keyId`, `serviceAccountId`,
`keyAlgorithm`, опц. `publicKeyPem` — но не секрет.

---

## Coverage-matrix (resource × action → emit)

Для каждой ячейки `✓` действует пара требований: **(E)** успешная мутация эмитит ровно
одну `audit_outbox`-строку с правильным `event_type` + `actor` + `resourceId`, атомарно в
writer-tx; **(¬E)** провалившаяся/откатанная мутация НЕ оставляет audit-строки (см.
atomicity-сценарии 5.2-34/35). `—` = действие не применимо/RPC отсутствует.

| Resource \ Action | Create | Update | Delete | Grant | Revoke | Issue | Member± | Force-logout |
|---|---|---|---|---|---|---|---|---|
| AccessBinding (regression) | ✓¹ | — | ✓¹ | — | — | — | — | — |
| cluster_admin | — | — | — | ✓ | ✓ | — | — | — |
| session | — | — | ✓ (revoke) | — | ✓ (all) | — | — | ✓ |
| Account | ✓ | ✓ | ✓ | — | — | — | — | — |
| Project | ✓ | ✓ | ✓ | — | — | — | — | — |
| User | ✓ | ✓ | ✓ | — | — | — | — | — |
| ServiceAccount | ✓ | ✓ | ✓ | — | — | — | — | — |
| Group | ✓ | ✓ | ✓ | — | — | — | ✓¹ | — |
| Role | ✓ | ✓ | ✓ | — | — | — | — | — |
| SAKey | — | — | ✓ (revoke) | — | — | ✓ | — | — |

¹ Уже реализовано (AccessBinding) либо «если RPC существует» (Group member, Project Move) —
регрессионно проверяется/реализуется только при наличии RPC.

---

## Сценарии

### Группа A — Highest-sensitivity (cluster-admin + session) — суб-PR #1

#### Сценарий 01: GrantAdmin эмитит durable audit-строку

**ID:** 5.2-01

**Given** существует пользователь `usr…X` в `kacho_iam.users`
**And** caller — аутентифицированный principal `usr…ADMIN` с `system_admin@cluster`

**When** клиент вызывает `InternalClusterService.GrantAdmin` (:9091) с payload:
  - `subjectType` = `USER`
  - `subjectId` = `usr…X`

**Then** возвращается `Operation` c `done=true`, `error` не выставлен (контракт RPC не изменён)
**And** в `kacho_iam.audit_outbox` появляется ровно одна строка с `event_type =
  "iam.cluster_admin.granted"`
**And** её `event_payload.actor.principalId = "usr…ADMIN"` (захваченный caller, не из тела)
**And** `event_payload.subjectId = "usr…X"`, `resourceType` отражает cluster-admin grant,
  `resourceId` = id созданного `cluster_admin_grant`
**And** строка имеет `status = "pending"` и `id`, матчащий `^evt_…{20,30}$`
**And** строка закоммичена в той же транзакции, что и grant + fga-outbox-строка (запрет #10)

> **Reactivate-дефолт (решено):** повторный `GrantAdmin` для пользователя с revoked-history
> (код-ветка `Reactivate` — update-in-place revoked-row) эмитит ТОТ ЖЕ `event_type =
> "iam.cluster_admin.granted"`, что и fresh grant (с точки зрения compliance «admin снова
> выдан»). Отдельный `reactivated`-тип НЕ вводится. Идемпотентный повтор, который ничего не
> изменил в row (grant уже активен → нет write), audit-строку НЕ эмитит (нет закоммиченной
> мутации — Сценарий 5.2-41).

#### Сценарий 02: RevokeAdmin эмитит durable audit-строку

**ID:** 5.2-02

**Given** активный cluster-admin grant для `usr…X`
**And** caller — `usr…ADMIN` с `system_admin@cluster`

**When** клиент вызывает `InternalClusterService.RevokeAdmin` с `subjectId` = `usr…X`

**Then** возвращается `Operation.done=true`, без `error`
**And** в `audit_outbox` появляется ровно одна строка `event_type = "iam.cluster_admin.revoked"`
  с `actor.principalId = "usr…ADMIN"`, `subjectId = "usr…X"`
**And** строка атомарна с revoke + fga-delete-outbox (одна транзакция)

#### Сценарий 03: session Revoke (single jti) эмитит audit-строку

**ID:** 5.2-03

**Given** caller-principal `usr…ADMIN`

**When** клиент вызывает `SessionRevocationsService.Revoke` с payload:
  - `tokenJti` = `<jti>`
  - `userId` = `usr…X`
  - `reason` = `"compromised"`

**Then** возвращается `Operation.done=true`, метаданные (`revokedCount`) не изменены
**And** в `audit_outbox` появляется одна строка `event_type = "iam.session.revoked"`
**And** payload содержит `subjectId = "usr…X"`, `reason = "compromised"`, `tokenJti` = `<jti>`,
  `actor.principalId = "usr…ADMIN"`
**And** payload НЕ содержит самого токена/секрета (только `tokenJti`-идентификатор)
**And** audit-строка коммитится атомарно с `session_revocations`-записью (одна транзакция —
  adapter расширен tx-scoped вариантом; см. DoD)

#### Сценарий 04: session Revoke (revoke_all_user_tokens) эмитит all-revoked audit

**ID:** 5.2-04

**Given** caller-principal `usr…ADMIN`

**When** клиент вызывает `SessionRevocationsService.Revoke` с payload:
  - `userId` = `usr…X`
  - `revokeAllUserTokens` = `true`

**Then** возвращается `Operation.done=true`
**And** в `audit_outbox` появляется одна строка `event_type = "iam.session.all_revoked"`
  с `subjectId = "usr…X"`, `actor.principalId = "usr…ADMIN"`, `reason`
**And** audit-строка атомарна с `user_token_revocations`-cutoff-записью

#### Сценарий 05: ForceLogout эмитит audit-строку

**ID:** 5.2-05

**Given** caller-principal `usr…ADMIN`

**When** клиент вызывает `InternalIAMService.ForceLogout` (:9091) с `userId` = `usr…X`

**Then** возвращается `Operation.done=true`, контракт не изменён
**And** в `audit_outbox` появляется одна строка `event_type = "iam.session.force_logout"`
  с `subjectId = "usr…X"`, `actor.principalId = "usr…ADMIN"`
**And** строка атомарна с revoke-all cutoff-записью

### Группа B — CRUD-ресурсы (Account/Project/User/ServiceAccount/Group/Role) — суб-PR #2

#### Сценарий 10: Account.Create эмитит created-событие

**ID:** 5.2-10

**Given** аутентифицированный principal `usr…OWNER`

**When** клиент вызывает `AccountService.Create` с payload:
  - `name` = `"acme"`
  - `description` = `"…"`

**Then** мутация возвращает `Operation`; полл `OperationService.Get(id)` до `done=true`,
  `error` не выставлен; `Get` отдаёт Account с `id=acc…`, `createdAt`, `name="acme"`
  (контракт ответа не изменён)
**And** в `audit_outbox` появляется одна строка `event_type = "iam.account.created"` с
  `resourceType="account"`, `resourceId="acc…"`, `name="acme"`, `actor.principalId="usr…OWNER"`
**And** audit-INSERT закоммичен в той же writer-tx (в async-worker), что и INSERT Account'а

#### Сценарий 11: Account.Update эмитит updated-событие с описанием изменений

**ID:** 5.2-11

**Given** существует Account `acc…A`; caller — его owner

**When** клиент вызывает `AccountService.Update` с `id=acc…A`, `updateMask=["description"]`,
  `description="renamed"`

**Then** полл `Operation` до `done=true`, без `error`; `Get` отдаёт обновлённое `description`
**And** в `audit_outbox` одна строка `event_type = "iam.account.updated"` с `resourceId="acc…A"`,
  `actor`, и полем `changedFields` (список применённых mutable-полей — здесь `["description"]`)
  (см. §Update-семантика)

#### Сценарий 12: Account.Delete эмитит deleted-событие

**ID:** 5.2-12

**Given** существует пустой Account `acc…A`; caller — owner

**When** клиент вызывает `AccountService.Delete` с `id=acc…A`

**Then** полл `Operation` до `done=true`, без `error`
**And** в `audit_outbox` одна строка `event_type = "iam.account.deleted"`, `resourceId="acc…A"`,
  `actor`, атомарно с DELETE

#### Сценарий 13: Project Create/Update/Delete эмитят соответствующие события

**ID:** 5.2-13

**Given** существует Account `acc…A`; caller — owner

**When** клиент последовательно вызывает `ProjectService.Create` (→ `prj…P`),
  `ProjectService.Update` (`updateMask=["name"]`), `ProjectService.Delete(prj…P)`

**Then** каждая операция доходит до `done=true` без `error`
**And** в `audit_outbox` появляются три строки: `iam.project.created` (с `accountId="acc…A"`,
  `name`), `iam.project.updated` (`changedFields=["name"]`), `iam.project.deleted` —
  все с `resourceId="prj…P"` и корректным `actor`, каждая атомарна со своей мутацией
**And** (если `ProjectService.Move` существует¹) Move эмитит `iam.project.moved` с
  `event_payload.fromAccountId` и `toAccountId`

#### Сценарий 14: User insert/update/delete эмитят события (Upsert + Delete пути)

**ID:** 5.2-14

**Given** существует Account-контекст для bootstrap-пути; для update-ветки — уже
  замиррренный `usr…U` (`external_id` = `<sub>`)

**When** выполняется `InternalUserService.UpsertFromIdentity` (:9091) с `externalId="<sub>"`:
  - insert-ветка: `<sub>` ранее не существовал → создаётся `usr…U`
  - update-ветка: `<sub>` существует → обновляются mirror-поля (`email`/`displayName`)

  И (если публичный `UserService.Delete` существует¹) `UserService.Delete(usr…U)`

**Then** для insert-ветки эмитится одна строка `iam.user.created` с `resourceId="usr…U"`,
  payload `email`/`displayName`; для update-ветки — `iam.user.updated` с `changedFields`
  (применённые mirror-поля); для delete — `iam.user.deleted` — каждая атомарна с мутацией
**And** для Upsert через Kratos/OIDC-bootstrap actor — `principalType="system"`,
  `principalId="bootstrap"`/`system` (Kratos provision-hook не несёт user-principal);
  фиксируется как `system`, НЕ выдумывается; для admin-tooling-Upsert с JWT — реальный principal

#### Сценарий 15: ServiceAccount Create/Update/Delete эмитят события

**ID:** 5.2-15

**Given** существует Account `acc…A`; caller — его owner `usr…OWNER`

**When** клиент вызывает `ServiceAccountService.Create` (`name="ci-bot"`, `accountId="acc…A"`)
  → `sva…S`, затем `ServiceAccountService.Update(sva…S, updateMask=["description"])`,
  затем `ServiceAccountService.Delete(sva…S)`

**Then** каждая операция доходит до `done=true` без `error`
**And** эмитятся три строки: `iam.service_account.created` (`resourceId="sva…S"`,
  `accountId="acc…A"`, `name="ci-bot"`), `iam.service_account.updated`
  (`changedFields=["description"]`), `iam.service_account.deleted` — каждая с `actor.principalId
  ="usr…OWNER"`, атомарна со своей мутацией

#### Сценарий 16: Group Create/Update/Delete (+ member±) эмитят события

**ID:** 5.2-16

**Given** существует Account `acc…A`; caller — owner `usr…OWNER`; существует `usr…M`

**When** клиент вызывает `GroupService.Create` (`name="devs"`, `accountId="acc…A"`) → `grp…G`,
  затем `GroupService.AddMember(grp…G, memberId="usr…M", memberType=USER)`,
  затем `GroupService.RemoveMember(grp…G, memberId="usr…M")`,
  затем `GroupService.Update(grp…G, updateMask=["description"])`,
  затем `GroupService.Delete(grp…G)`

**Then** эмитятся `iam.group.created` (`resourceId="grp…G"`, `name="devs"`),
  `iam.group.member_added` (payload `memberId="usr…M"`, `memberType="user"`, `groupId="grp…G"`),
  `iam.group.member_removed` (те же поля), `iam.group.updated` (`changedFields=["description"]`),
  `iam.group.deleted` — каждая с `actor`, атомарна со своей мутацией
**And** member-RPC (`AddMember`/`RemoveMember`) существуют в текущей поверхности¹ — реализуются;
  если отсутствуют — N/A

#### Сценарий 17: Role Create/Update/Delete эмитят события (без раздувания payload)

**ID:** 5.2-17

**Given** caller — owner Account `acc…A`

**When** клиент вызывает `RoleService.Create` (custom-role, `name="vpc-reader"`,
  `permissions=["vpc.network.get"]`) → `rol…R`, затем `RoleService.Update(rol…R,
  updateMask=["permissions"])`, затем `RoleService.Delete(rol…R)`

**Then** эмитятся `iam.role.created`/`updated`/`deleted` с `resourceId="rol…R"`, `accountId="acc…A"`,
  `actor`, атомарно с мутацией
**And** для Update payload фиксирует факт изменения permissions (`changedFields=["permissions"]`);
  весь permissions-массив в payload — допустим, но не требуется (минимум — id роли + actor +
  changedFields)

### Группа C — SAKey (long-lived credential material) — суб-PR #3

#### Сценарий 20: SAKey Issue эмитит issued-событие БЕЗ key-material

**ID:** 5.2-20

**Given** существует ServiceAccount `sva…S`; caller — аутентифицированный principal

**When** клиент вызывает `SAKeyService.IssueSAKey` с `serviceAccountId="sva…S"`

**Then** мутация async — полл `Operation` до `done=true`, без `error`; ответ содержит
  key-material (private PEM) ровно как сейчас (контракт не изменён; redaction в ops-row
  не трогается)
**And** в `audit_outbox` одна строка `event_type = "iam.sa_key.issued"` с
  `event_payload.keyId="soc…"`, `serviceAccountId="sva…S"`, `keyAlgorithm`, `actor.principalId`
**And** `event_payload` НЕ содержит `privateKeyPem` / client_secret / любого секрета
  (проверяется сценарием 5.2-36)
**And** audit-INSERT закоммичен в той же writer-tx (в worker), что и persist key-mapping

#### Сценарий 21: SAKey Revoke эмитит revoked-событие

**ID:** 5.2-21

**Given** существует выданный SAKey `soc…K` для `sva…S`

**When** клиент вызывает `SAKeyService.RevokeSAKey` с `keyId="soc…K"`

**Then** полл `Operation` до `done=true`, без `error`
**And** в `audit_outbox` одна строка `event_type = "iam.sa_key.revoked"` с `keyId="soc…K"`,
  `serviceAccountId="sva…S"`, `actor.principalId`, атомарно с revoke-мутацией
**And** payload не содержит секретов

### Группа D — Сквозные инварианты (применяются ко ВСЕМ событиям выше)

#### Сценарий 34: Atomicity — commit-together (audit-строка есть ⇔ мутация закоммичена)

**ID:** 5.2-34

**Given** любая security-relevant мутация из групп A/B/C

**When** мутация успешно коммитится

**Then** в `audit_outbox` присутствует ровно одна соответствующая строка
**And** обратное: запрос `audit_outbox` после успешной мутации всегда находит её событие
  (audit-строка и мутация коммитятся в одной транзакции — никогда не одна без другой)

#### Сценарий 35: Atomicity — rollback не оставляет orphan audit-строку

**ID:** 5.2-35

**Given** мутация, чья writer-tx откатывается ПОСЛЕ того, как audit-INSERT уже выполнен в
  той же транзакции (напр. последующий statement в той же tx падает на FK/UNIQUE/CHECK —
  `Account.Create` с дублирующимся `name` → 23505, или injected-failure перед `Commit`)

**When** транзакция откатывается (`Rollback`)

**Then** мутация-ресурс НЕ создан/не изменён (контракт ошибки RPC не изменён — тот же код,
  что и сегодня: `ALREADY_EXISTS`/`FAILED_PRECONDITION`/…)
**And** в `audit_outbox` НЕТ строки для этой попытки (no orphan — audit-строка откатилась
  вместе с мутацией)
**And** integration-тест (testcontainers) подтверждает: после rollback `SELECT count(*)
  FROM audit_outbox WHERE …` = 0

#### Сценарий 36: No-secrets-in-payload (negative — обязательный)

**ID:** 5.2-36

**Given** успешные `SAKeyService.IssueSAKey` и `SessionRevocationsService.Revoke`

**When** читается `event_payload` соответствующих `audit_outbox`-строк

**Then** payload — валидный JSON object (CHECK `audit_outbox_payload_object_ck`)
**And** payload НЕ содержит ключей/значений с private-key material (`privateKeyPem`,
  PEM-блоков `BEGIN … PRIVATE KEY`), client_secret/Hydra-секрета, refresh/access-токенов,
  паролей
**And** допустимы только не-секретные идентификаторы: `keyId`, `serviceAccountId`,
  `keyAlgorithm`, `publicKeyPem`(опц.), `tokenJti`(идентификатор, не токен)
**And** integration-тест ассертит отсутствие секрет-паттернов в сериализованном payload

#### Сценарий 37: id-format regression-guard (#126 — 22-char, не 17-char)

**ID:** 5.2-37

**Given** любой новый audit-emit путь из групп A/B/C

**When** эмитится audit-строка

**Then** её `id` матчит `^evt_[0-9A-HJKMNP-TV-Za-hjkmnp-tv-z]{20,30}$` (использован
  `newAuditEventID()` — 22-char body), а не 17-char `domain.NewKac127ID`
**And** INSERT не отклоняется `audit_outbox_id_check` (ровно тот баг #126 — silent no-op
  от 17-char id; здесь явный regression-guard)
**And** integration-тест: для каждого нового event_type фактически вставленная строка
  читается из `audit_outbox` (доказывает, что CHECK прошёл, а не silently dropped)

#### Сценарий 38: event_type удовлетворяет CHECK для всех новых значений

**ID:** 5.2-38

**Given** полная EventType-таблица выше

**When** каждое значение вставляется как `audit_outbox.event_type`

**Then** все матчат `^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$` (длина 1..128) и проходят
  `audit_outbox_event_type_check` (включая 3-сегментные с underscore: `iam.cluster_admin.granted`,
  `iam.sa_key.issued`, `iam.session.all_revoked`, `iam.group.member_added`)

#### Сценарий 39: Мутация-поведение не меняется (purely additive)

**ID:** 5.2-39

**Given** существующие newman/integration happy+negative-кейсы для всех затронутых RPC

**When** прогоняются после добавления audit-emit

**Then** return-контракты, gRPC-коды, метаданные `Operation`, форма ресурсов в `Get`/`List`
  — байт-в-байт прежние (audit — чисто аддитивный side-effect в той же tx; никакого нового
  кода ошибки, никакого изменения латентности контракта)

#### Сценарий 40: actor никогда не из тела запроса (anti-spoofing)

**ID:** 5.2-40

**Given** мутация, где тело запроса содержит поле, похожее на actor (напр. legacy
  `revokedBy` / `grantedBy` в payload, либо подставленное произвольное значение)

**When** мутация выполняется аутентифицированным principal `usr…REAL`

**Then** `event_payload.actor.principalId = "usr…REAL"` (из `PrincipalFromContext`), а НЕ
  значение из тела запроса — даже если тело пыталось подставить другой id

#### Сценарий 41: Idempotent no-op мутация НЕ эмитит audit-строку (emit-per-committed-change)

**ID:** 5.2-41

**Given** уже-активный cluster-admin grant для `usr…X` (повторный `GrantAdmin` — no-op,
  grant активен → нет write); ИЛИ session `Revoke` того же `tokenJti`, не меняющий row

**When** клиент повторяет мутацию, которая НЕ изменяет состояние row (idempotent no-op:
  grant уже активен; revocation-row идентична)

**Then** возвращается тот же успешный `Operation`-контракт (поведение не изменено)
**And** в `audit_outbox` НЕ появляется НОВАЯ строка для no-op-повтора (audit = журнал
  фактически закоммиченных изменений состояния, не запись на каждый RPC-вызов)
**And** напротив — повтор, который реально изменил row (reactivate revoked grant; upsert,
  обновивший `reason`/`ttl`), эмитит audit-строку (закоммиченное изменение)

#### Сценарий 42: Конкурентный idempotent-upsert (session Revoke того же jti) — детерминированный audit-исход

**ID:** 5.2-42

**Given** caller-principal `usr…ADMIN`; пустая `session_revocations` для `<jti>`

**When** две goroutine конкурентно вызывают `SessionRevocationsService.Revoke` с одним и тем
  же `tokenJti=<jti>`, `userId=usr…X` (путь `ON CONFLICT (token_jti) DO UPDATE`)

**Then** обе операции успешны (idempotent upsert — без race-ошибки)
**And** в `audit_outbox` число строк `iam.session.revoked` для `<jti>` детерминировано и
  совпадает с числом фактически закоммиченных upsert-транзакций, изменивших row
  (контракт «emit-per-committed-change» из 5.2-41) — ни одна транзакция не оставляет orphan,
  ни одна закоммиченная не теряет audit-строку
**And** integration-тест (testcontainers, concurrent goroutines — `data-integrity.md §5`)
  фиксирует ожидаемое число audit-строк и атомарность каждой с её upsert-транзакцией

---

## Update-семантика (решено, не оставлено открытым)

Для всех `Update`-событий (`iam.<resource>.updated`):
- payload ОБЯЗАН содержать `resourceId` + `actor` (минимум — «кто и над чем»).
- payload ОБЯЗАН содержать `changedFields` — массив имён применённых mutable-полей
  (производных от `update_mask`; для пустого mask = full-PATCH → список фактически
  изменённых mutable-полей). Это даёт «что изменилось» без раздувания payload «было→стало».
- Хранить before/after-значения НЕ требуется в этой волне (избегаем PII/секретов в audit;
  diff-значения — отдельная фаза при необходимости). Для Role permissions-массив допустим,
  но не обязателен — достаточно `changedFields=["permissions"]`.

---

## Traceability (сценарий ↔ integration-функция ↔ newman/integration-кейс)

Двусторонняя трассировка для `integration-tester`/`qa-test-engineer`. Integration-функции —
`Test<Resource>_<ID>_<ShortDesc>` (placement: `internal/repo/kacho/pg/*_audit_outbox_integration_test.go`
по resource-группе). Internal-only RPC (cluster/force-logout/SAKey — :9091, не на external)
покрываются integration-ом, а не newman (newman ходит только через публичный api-gateway).

| ID | RPC | Integration-функция (testcontainers) | Newman / integration-кейс |
|---|---|---|---|
| 5.2-01 | GrantAdmin | `TestClusterAudit_5_2_01_GrantAdminEmits` | integration-only (Internal :9091) |
| 5.2-02 | RevokeAdmin | `TestClusterAudit_5_2_02_RevokeAdminEmits` | integration-only (Internal :9091) |
| 5.2-03 | session Revoke (jti) | `TestSessionAudit_5_2_03_RevokeJtiEmits` | integration-only (or newman if public Revoke exposed) |
| 5.2-04 | session Revoke (all) | `TestSessionAudit_5_2_04_RevokeAllEmits` | integration-only |
| 5.2-05 | ForceLogout | `TestSessionAudit_5_2_05_ForceLogoutEmits` | integration-only (Internal :9091) |
| 5.2-10 | Account.Create | `TestAccountAudit_5_2_10_CreateEmits` | `iam-account-audit-create` (happy) |
| 5.2-11 | Account.Update | `TestAccountAudit_5_2_11_UpdateEmits` | `iam-account-audit-update` (happy) |
| 5.2-12 | Account.Delete | `TestAccountAudit_5_2_12_DeleteEmits` | `iam-account-audit-delete` (happy) |
| 5.2-13 | Project C/U/D(/Move¹) | `TestProjectAudit_5_2_13_CrudEmits` | `iam-project-audit-crud` (happy) |
| 5.2-14 | User upsert/delete | `TestUserAudit_5_2_14_UpsertDeleteEmits` | integration-only (Upsert Internal); delete newman if public¹ |
| 5.2-15 | ServiceAccount C/U/D | `TestServiceAccountAudit_5_2_15_CrudEmits` | `iam-sa-audit-crud` (happy) |
| 5.2-16 | Group C/U/D + member± | `TestGroupAudit_5_2_16_CrudMemberEmits` | `iam-group-audit-crud` (happy) |
| 5.2-17 | Role C/U/D | `TestRoleAudit_5_2_17_CrudEmits` | `iam-role-audit-crud` (happy) |
| 5.2-20 | SAKey Issue | `TestSAKeyAudit_5_2_20_IssueEmitsNoSecret` | integration-only (no-secret assert) |
| 5.2-21 | SAKey Revoke | `TestSAKeyAudit_5_2_21_RevokeEmits` | integration-only |
| 5.2-34 | atomicity commit-together | `TestAudit_5_2_34_CommitTogether` | covered by happy кейсы (audit-row read-back) |
| 5.2-35 | atomicity rollback-no-orphan | `TestAudit_5_2_35_RollbackNoOrphan` | `iam-*-audit-rollback` (negative, ≥1 per group) |
| 5.2-36 | no-secrets-in-payload | `TestAudit_5_2_36_NoSecretsInPayload` | integration-only (payload-scan) |
| 5.2-37 | 22-char id guard (#126) | `TestAudit_5_2_37_EventIdFormatGuard` | integration-only (CHECK pass read-back) |
| 5.2-38 | event_type CHECK | `TestAudit_5_2_38_EventTypeCheckAll` | integration-only |
| 5.2-39 | purely additive | (re-run existing newman+integration green) | existing `iam-*` suites |
| 5.2-40 | anti-spoofing actor | `TestAudit_5_2_40_ActorFromPrincipalNotBody` | `iam-*-audit-actor-spoof` (negative) |
| 5.2-41 | idempotent no-op no-emit | `TestAudit_5_2_41_NoOpNoEmit` | integration-only |
| 5.2-42 | concurrent upsert audit count | `TestSessionAudit_5_2_42_ConcurrentRevokeAuditCount` | integration-only (concurrent goroutines) |

¹ Имена функций/кейсов для `(если RPC существует)`-строк (Project.Move, Group member±,
публичный User.Create/Delete) реализуются только при наличии RPC; иначе помечаются N/A в DoD
суб-PR. Имена выше — целевой контракт; `integration-tester` сохраняет `5_2_NN`-токен в имени
для обратной трассировки к этому документу.

---

## Scope boundaries (явно)

- **Только emit-сторона** (writer-tx audit-строки). Drainer/export (`AuditOutboxRepo`
  статус-машина, Kafka-fan-out) уже существует — НЕ меняется.
- **Поведение/контракт мутаций НЕ меняется** — чисто аддитивный audit-side-effect в той же
  транзакции (Сценарий 5.2-39). Никаких новых кодов ошибок, новых полей в ответах RPC.
- **Idempotency / retry:** выравнивается с AccessBinding — drainer дедупит по `id`; повтор
  мутации (напр. идемпотентный cluster GrantAdmin reactivate) эмитит новое audit-событие на
  каждую фактически закоммиченную мутацию (audit = журнал попыток, не дедуп-набор состояний).
- **Recommended суб-ordering** (можно дробить на суб-PR по группам ресурсов):
  1. **Суб-PR #1 (highest-sensitivity):** cluster-admin grant/revoke + session revoke/all +
     force-logout (сценарии 5.2-01..05). Здесь же — расширение session/force-logout-adapter
     tx-scoped вариантом ради атомарности.
  2. **Суб-PR #2 (CRUD):** Account/Project/User/ServiceAccount/Group/Role
     Create/Update/Delete (+ member/Move если RPC есть) (5.2-10..17). Здесь же — обобщённый
     audit-emit порт на writer-iface каждого ресурса.
  3. **Суб-PR #3 (SAKey):** Issue/Revoke (5.2-20..21) + no-secrets-guard (5.2-36).
  - Сквозные инварианты (5.2-34..40) проверяются в КАЖДОМ суб-PR для его событий.

---

## Definition of Done (на каждый суб-PR; строгий TDD)

- [ ] **TDD integration-first:** для каждого нового event_type — падающий
      integration-тест (testcontainers Postgres) ДО кода, ассертящий, что успешная мутация
      вставляет ровно одну `audit_outbox`-строку с корректным `event_type`/`actor`/payload,
      и что строка читается обратно (CHECK прошёл) — RED → GREEN.
- [ ] **Atomicity-тест (rollback):** integration-тест на rollback-путь (5.2-35) — после
      отката транзакции в `audit_outbox` нет orphan-строки; audit-строка коммитится строго
      вместе с мутацией (5.2-34).
- [ ] **Concurrent-emit тест (5.2-42, `data-integrity.md §5`):** для idempotent-upsert путей
      (session Revoke) — concurrent goroutines, детерминированное число audit-строк
      (emit-per-committed-change), без orphan и без потерь. Idempotent no-op не эмитит (5.2-41).
- [ ] **No-secrets-тест (5.2-36):** ассерт отсутствия private-key/секрет-паттернов в payload
      для SAKey/session событий.
- [ ] **id-regression-guard (5.2-37):** ассерт `id` матчит 22-char `evt_…` формат и не
      использует 17-char генератор; покрывает баг #126.
- [ ] **Newman happy+negative** (`tests/newman/cases/iam-*.py` → `gen.py`) для затронутых
      публичных RPC: ≥1 happy (мутация → audit-строка читаема через admin-read, если есть
      Internal audit-read RPC) + ≥1 negative (rollback → нет audit-строки). Для Internal-only
      RPC (cluster/force-logout) — integration-покрытие.
- [ ] **Поведение мутаций не изменилось** (5.2-39): существующие newman/integration зелёные.
- [ ] **Финальная верификация:** `go test ./... -race` + `golangci-lint run` + `gosec`/
      `govulncheck` зелёные.
- [ ] **Vault-trail:** обновить `obsidian/kacho/resources/kacho-iam-audit-outbox.md`
      (новые event_type, payload-форма, atomic-emit инвариант), `rpc/kacho-iam-*.md`
      затронутых сервисов (audit-side-effect), `edges/` если затронут drainer-контракт.
- [ ] **KAC-trail:** `obsidian/kacho/KAC/KAC-122.md` — Status, затронутые сущности vault,
      PR-URL'ы, DoD-чеклист; тикет переведён To do → In Progress → Test → Done с артефактами.
