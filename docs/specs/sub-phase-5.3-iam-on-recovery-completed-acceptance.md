# Sub-phase 5.3 (kacho-iam — InternalUserService.OnRecoveryCompleted: Kratos password-recovery hook) — Acceptance

> Статус: ✅ APPROVED (acceptance-reviewer, 2026-06-16)
> Дата: 2026-06-16
> Ревьюер: acceptance-reviewer
> Эпик/тикет: KAC-127 (Phase-2 recovery flow) / Round-5 P1 — трекинг #122
>
> Все 4 открытых вопроса разрешены ревью (см. §«Решения ревьюера (резолюция
> открытых вопросов)» в конце дока). Можно начинать planning + implementation.

## Обзор

`InternalUserService.OnRecoveryCompleted` полностью описан в proto (с явной
KAC-127 Phase-2 семантикой: Ory Kratos зовёт webhook после успешного
self-service password-recovery), но `InternalHandler` его **не реализует** —
вызов падает на `UnimplementedInternalUserServiceServer` → `Unimplemented`,
из-за чего весь recovery-флоу нерабочий. Эта под-фаза реализует RPC
end-to-end: найти `User` по `external_id`, сверить `email`, re-enable (если
учётка была `BLOCKED`), отозвать все живые сессии/токены пользователя (recovery
= смена credential), записать durable audit-строку — **всё в одной writer-tx**
(запрет #10) — и сделать операцию **идемпотентной** на `(external_id,
recovery_jti)` для at-least-once доставки webhook'а Kratos.

Это волна **только реализации** уже-определённого RPC: proto-контракт не
меняется (RPC, request/response, `option permission = "<exempt>"`, регистрация
на internal listener, запись в `permission_catalog.json`, гейтинг в
`caller_policy`/`system_viewer_floor` — **уже на месте**, см. Ground-truth).
Новое — handler-метод, use-case, одна migration (idempotency-таблица) и тесты.

## Нормативные ссылки (не дублируются в тело сценариев)

- `.claude/rules/data-integrity.md` §«Within-service инварианты — ТОЛЬКО на
  DB-уровне» (запрет #10): re-enable + revoke-cutoff + audit-строка + idempotency-
  ключ коммитятся в ОДНОЙ writer-tx (commit-together-or-rollback-together);
  идемпотентность — DB-конструкцией (`ON CONFLICT DO NOTHING`), не software
  check-then-act.
- `.claude/rules/security.md` §«AuthN+AuthZ ВЕЗДЕ» + ban #6: RPC — на cluster-
  internal listener (:9091), не на external endpoint; caller-policy + floor-
  exemption — см. Ground-truth; в audit-payload не пишутся секреты / инфра-
  чувствительные данные.
- `.claude/rules/api-conventions.md`: мутация возвращает `Operation` (async);
  error-format и коды (`NOT_FOUND` / `INVALID_ARGUMENT` / `FAILED_PRECONDITION` /
  `UNAVAILABLE`); тексты сообщений стабильны.
- kacho-iam `CLAUDE.md` §2.x (principal-носитель, writer-tx паттерны, invite_status).

## Ground-truth (зафиксировано чтением кода — сценарии опираются на это, не на догадки)

**Proto-контракт** (`kacho-proto/proto/kacho/cloud/iam/v1/internal_user_service.proto`)
— **присутствует, не меняется**:
- `rpc OnRecoveryCompleted (OnRecoveryCompletedRequest) returns (operation.Operation)`
  с `option (kacho.cloud.api.operation) = { metadata: "OnRecoveryCompletedMetadata", response: "User" }`
  и `option (kacho.iam.authz.v1.permission) = "<exempt>"`.
- `OnRecoveryCompletedRequest` — поля: `external_id` (`required`, `<=128`),
  `recovery_jti` (`required`, `<=128`), `email` (`required`, `<=320`).
- `OnRecoveryCompletedMetadata` — `user_id` (string), `revoked_session_count` (int32).
- `response` LRO — `User`.

**Handler** (`internal/apps/kacho/api/user/handler.go`):
`InternalHandler` встраивает `iamv1.UnimplementedInternalUserServiceServer`,
реализует `UpsertFromIdentity` и `Get`, **но не** `OnRecoveryCompleted` → fallback
в `Unimplemented`. Эталон webhook-driven мутации — `UpsertFromIdentity` →
use-case `internal_upsert.go` (sync-резолв id → создать `Operation` →
`operations.Run` async-worker).

**Регистрация / гейтинг** (`cmd/kacho-iam/grpc_register.go`,
`internal/authzguard/`):
- `registerInternalServices` уже регистрирует `InternalUserService` на internal
  listener (`RegisterInternalUserServiceServer`) — **новой регистрации не нужно**.
- `OnRecoveryCompleted` уже в `GatewayFrontedInternalRPCs()` (caller_policy.go) →
  в prod вызывать может **только** api-gateway SA (Kratos бьёт в api-gateway,
  тот форвардит на :9091 своим mTLS-cert'ом). Прямой вызов другого модуля → DENY.
- `OnRecoveryCompleted` **отсутствует** в `ReadFloorRPCs()` (system_viewer_floor.go,
  INV-FLOOR-6) → **exempt** от `system_viewer`-floor: Kratos secret-authed, не
  kacho-seeded SA, relation-Check неприменим. dev/newman: оба гейта — no-op.
- В `permission_catalog.json` запись `kacho.cloud.iam.v1.InternalUserService/OnRecoveryCompleted`
  присутствует как `<exempt>` (authz-public-allowlist) — изменений не требует.
- В proto-docstring сказано «Kratos is the only authorized caller via secret-token
  … No per-RPC authz check» — это и есть caller-policy gateway-only + floor-exempt.

**Domain-модель User** (`internal/domain/user.go`):
- `InviteStatus` enum = `PENDING | ACTIVE | BLOCKED` (**нет** значения `DISABLED`).
  → **Расхождение proto-docstring**: docstring говорит «re-enables … if
  `invite_status` was `DISABLED`». Канонический enum — `BLOCKED`. В этой под-фазе
  **«re-enable» = `BLOCKED → ACTIVE`**; терминология «DISABLED» в proto-докстринге
  трактуется как `BLOCKED`. (Если ревью решит привести docstring к `BLOCKED` —
  это proto-doc-only правка через `proto-api-reviewer`, поведение не меняет.)
- Инвариант (DB CHECK `users_invite_status_consistency` + `User.Validate`):
  `PENDING ⇔ external_id="" ; ACTIVE/BLOCKED ⇔ external_id<>""`. Recovery
  работает по `external_id` → касается **только** `ACTIVE`/`BLOCKED`-rows;
  `PENDING`-row (external_id="") по `external_id` найден быть не может.
- Уникальность: partial UNIQUE `users_account_external_id_unique WHERE
  external_id <> ""` — `external_id` уникален per-Account среди не-PENDING rows.
  Одна Kratos-identity может иметь N User-rows (по одной на Account).

**Session-revocation** (built в 5.x):
- `internal/apps/kacho/api/session_revocations/` — `RevokeUseCase`,
  `InternalSessionRevocationsService` handler.
- `SessionRevocationsAdapter.RevokeAllUserTokens(ctx, userID, revokeBefore,
  reason, revokedBy)` → `UserTokenRevocationRepo.UpsertRevokeAll` — single-stmt
  `INSERT … ON CONFLICT (user_id) DO UPDATE SET revoke_before =
  GREATEST(existing, EXCLUDED)` (migration 0012). Cutoff **монотонен** (never
  moves backwards), идемпотентен на повторе. Refresh-hook сравнивает session
  `auth_time` с `revoke_before` и отказывает старым токенам. `reason` для recovery
  — `password-change` (per proto-docstring).
- Per-jti `session_revocations` row — для single-token logout; для recovery
  используется **per-user cutoff** (revoke-all), не per-jti.

**Audit** (Wave A / 5.2):
- Канонический паттерн: `EmitAuditEvent`-в-writer-tx (запрет #10), `audit_outbox`-
  строка коммитится iff мутация коммитится. `AuditEventType` —
  `^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$` (напр. `iam.access_binding.granted`).
- id-генератор audit-row → `evt_<22-char crockford-base32>` (CHECK
  `audit_outbox_id_check`: `^evt_[0-9A-HJKMNP-TV-Za-hjkmnp-tv-z]{20,30}$`).
- Таблица `kacho_iam.audit_outbox(id, event_type, tenant_account_id,
  event_payload jsonb, status, attempts, created_at, next_attempt_at)`;
  generic `AuditOutboxRepo.InsertTx(ctx, tx, AuditOutboxEntry)` — caller владеет tx.
- **EventType этой под-фазы:** `iam.user.recovery_completed` (per proto-docstring +
  Wave-A taxonomy `iam.<resource>.<action>`).

**CQRS-репо User** (`internal/repo/kacho/user/iface.go`,
`internal/repo/kacho/pg/`): `ReaderIface.FindActiveByExternalID`,
`WriterIface` (`ActivateInvite` / `InsertActive` / `Delete` …). Writer-tx
оркеструется через `shared.DoWithWriteTx(ctx, repo, fn)` (как в
`bootstrapNewIdentity`). Новые writer-методы (re-enable BLOCKED→ACTIVE; idempotency-
insert) — добавляются `rpc-implementer`/`migration-writer` под APPROVED-док.
> **⚠ Reader-нюанс (ground-truth, для `rpc-implementer`):** существующий
> `FindActiveByExternalID` (`user_repo.go:138`) фильтрует `WHERE invite_status =
> 'ACTIVE'` — **BLOCKED-row'ы он НЕ возвращает**. Recovery обязан находить и
> re-enable'ить именно `BLOCKED` → нельзя переиспользовать ACTIVE-only-запрос
> «как есть». Нужен **новый/расширенный reader** (напр.
> `FindByExternalIDInStatuses(ext, {ACTIVE, BLOCKED})` либо снятие фильтра в
> recovery-пути), иначе 5.3-01/5.3-09 (BLOCKED-ветка) не сработают. Контракт
> сценариев (re-enable BLOCKED) — корректен; это лишь предупреждение об имени
> метода в Ground-truth, чтобы не словить silent NOT_FOUND на BLOCKED-row.

**Идемпотентность — текущее состояние и пробел:**
- Cutoff `user_token_revocations` уже идемпотентен/монотонен — повтор не двигает
  cutoff назад. НО повторный webhook всё равно (а) заново выполнит revoke-cutoff
  (двигает `revoke_before` вперёд на *новое* now → может отозвать сессии,
  залогиненные **между** первым и вторым webhook'ом — регрессия монотонности
  относительно момента recovery), и (б) **задублирует audit-строку**.
- Таблицы/констрейнта для `recovery_jti` dedup **сейчас нет** (grep: ноль
  упоминаний `recovery_jti` в `internal/`/`migrations/`). → нужна **новая
  migration** с idempotency-таблицей (см. §«Idempotency mechanism»).

## Idempotency mechanism (нормативно для сценариев)

Дедуп — **DB-конструкцией** (запрет #10), ключ — `recovery_jti`:

- Новая таблица `kacho_iam.recovery_completions` (migration — **следующий
  свободный номер на момент реализации**; live-каталог `internal/migrations/`
  на дату дока топ = `0014_reader_sa_system_viewer.sql`, поэтому следующий
  свободный = `0015`, НО `migration-writer` обязан перепроверить top live-
  миграции в момент реализации и взять реально-свободный номер — НЕ хардкодить;
  файлы `0015..0025` в `docs/architecture/migrations-history/` — это **архив
  Wave-A/dead-code**, не live-каталог, путать нельзя; имя файла — на усмотрение
  `migration-writer`):
  `recovery_jti TEXT PRIMARY KEY`, `external_id TEXT NOT NULL`,
  `user_id TEXT NOT NULL`, `revoked_session_count INT NOT NULL`,
  `completed_at TIMESTAMPTZ NOT NULL DEFAULT now()`.
- В writer-tx **первым** шагом: `INSERT INTO kacho_iam.recovery_completions
  (recovery_jti, …) VALUES (…) ON CONFLICT (recovery_jti) DO NOTHING RETURNING …`.
  - **0 rows из RETURNING** → этот `recovery_jti` уже обработан → **idempotent
    no-op**: tx НЕ выполняет повторно ни re-enable, ни revoke-cutoff, ни audit;
    use-case читает сохранённый `user_id`/`revoked_session_count` из существующей
    row и возвращает их в `Operation.metadata` + `response: User` (повторная
    операция «успешна», но без побочных эффектов).
  - **1 row** (новый `recovery_jti`) → выполняем full-флоу (re-enable →
    revoke-cutoff → audit) в той же tx, затем commit.
- `recovery_jti` — глобально-уникальный flow-id Kratos (не per-Account); таблица —
  глобальная (не scoped по account_id). `external_id` может иметь N User-rows;
  idempotency-ключ — flow, а не (user_id) (один recovery-flow = одно событие).
- Row-lock на PK сериализует конкурентные доставки одного и того же `recovery_jti`:
  ровно один writer выигрывает INSERT, остальные видят 0-rows → no-op.

## Семантика OnRecoveryCompleted (что кодирует под-фаза)

`OnRecoveryCompleted(external_id, recovery_jti, email)`:

1. **Sync-валидация** (первыми стейтментами Execute): все три поля required +
   length per proto; невалидный формат → `INVALID_ARGUMENT` синхронно (до
   `Operation`-спавна). Дальше — async через `Operation` (мутация → LRO).
2. **Find User by external_id** (`FindActiveByExternalID`): среди ACTIVE/BLOCKED
   rows. Нет ни одной → `NOT_FOUND` (recovery — для существующей identity;
   **не** auto-create). Несколько (N Account'ов) — см. §сценарий 5.3-09.
3. **Verify email** совпадает с `users.email` (case-insensitive, как в IAM):
   mismatch → отклонить **без side-effects** (код — см. сценарий 5.3-04).
4. **Idempotency-insert** `recovery_jti` (ON CONFLICT DO NOTHING) — gate шага 5–7.
5. **Re-enable**: если `invite_status == BLOCKED` → `BLOCKED → ACTIVE`
   (идемпотентно; ACTIVE → no-op, не ошибка).
6. **Revoke all live tokens/sessions**: `RevokeAllUserTokens(userID,
   revokeBefore=<recovery time>, reason="password-change", revokedBy="")`.
7. **Emit audit** `iam.user.recovery_completed` в той же writer-tx
   (`tenant_account_id` = `User.AccountID`; payload — см. §audit payload).
8. **Commit** (шаги 4–7 атомарны). `Operation.metadata.user_id` = id User-row,
   `revoked_session_count` = число отозванных сессий (≥1 при реальном cutoff;
   при idempotent-replay — сохранённое значение). `response: User` (re-enabled).
9. **Auth**: Kratos secret-authed → api-gateway → :9091 (gateway-only caller-
   policy, floor-exempt). В dev/newman — оба гейта no-op.

### Audit payload (`iam.user.recovery_completed`)

JSON object, без секретов/инфра-данных: `{ "user_id", "external_id", "email",
"recovery_jti", "re_enabled" (bool), "revoked_session_count" }`. `actor` —
пусто/«system» (Kratos-driven, не end-user principal). `tenant_account_id` =
`User.AccountID`.

---

## Сценарий 5.3-01: Happy — BLOCKED-учётка восстанавливается (re-enable + revoke + audit + idempotency)

**ID:** 5.3-01

**Given** существует `User` U с `external_id="krt_alice"`, `email="alice@example.com"`,
`invite_status=BLOCKED`, `account_id=acc_a`
**And** у U есть живая сессия (refresh-токен, проходящий refresh-hook до recovery)
**And** в `recovery_completions` нет строки с `recovery_jti="rec_flow_001"`

**When** Kratos (через api-gateway) вызывает `InternalUserService.OnRecoveryCompleted`
(REST internal: `POST /iam/v1/internal/users:onRecoveryCompleted`) с payload:
  - external_id = `krt_alice`
  - recovery_jti = `rec_flow_001`
  - email = `alice@example.com`

**Then** RPC возвращает `Operation`; полл `OperationService.Get(id)` до `done=true`
**And** `Operation.error` не установлен (`done && !error`)
**And** `Operation.metadata` (`OnRecoveryCompletedMetadata`): `user_id` = id(U),
  `revoked_session_count` ≥ 1
**And** `Operation.response` (`User`): `invite_status=ACTIVE` (re-enabled), `id`,
  `createdAt`, `email` заполнены
**And** последующий `InternalUserService.Get(user_id=id(U))` отдаёт `invite_status=ACTIVE`
**And** в `user_token_revocations` для U существует cutoff `revoke_before ≈ recovery time`,
  `reason="password-change"` (старая сессия U теперь отклоняется refresh-hook'ом)
**And** в `audit_outbox` ровно одна строка `event_type="iam.user.recovery_completed"`,
  `tenant_account_id=acc_a`, `status="pending"`, валидный `id` (`evt_…`),
  `event_payload` содержит `user_id`/`external_id`/`recovery_jti`/`re_enabled=true`
**And** в `recovery_completions` существует строка `recovery_jti="rec_flow_001"`.

---

## Сценарий 5.3-02: Happy — ACTIVE-учётка восстанавливается (re-enable — no-op, revoke + audit есть)

**ID:** 5.3-02

**Given** существует `User` U с `external_id="krt_bob"`, `email="bob@example.com"`,
`invite_status=ACTIVE`, `account_id=acc_b`
**And** у U есть живая сессия
**And** в `recovery_completions` нет строки с `recovery_jti="rec_flow_002"`

**When** Kratos вызывает `OnRecoveryCompleted` с payload:
  - external_id = `krt_bob`
  - recovery_jti = `rec_flow_002`
  - email = `bob@example.com`

**Then** `Operation` → `done=true`, `!error`
**And** `Operation.response` (`User`): `invite_status=ACTIVE` (re-enable — no-op, статус не менялся, не ошибка)
**And** `Operation.metadata.revoked_session_count` ≥ 1
**And** в `user_token_revocations` для U установлен cutoff `reason="password-change"`
**And** в `audit_outbox` ровно одна строка `event_type="iam.user.recovery_completed"`,
  `event_payload.re_enabled=false`
**And** в `recovery_completions` существует строка `recovery_jti="rec_flow_002"`.

---

## Сценарий 5.3-03: Negative — неизвестный external_id → NOT_FOUND (no side-effects)

**ID:** 5.3-03

**Given** в БД нет ни одной ACTIVE/BLOCKED-row с `external_id="krt_ghost"`

**When** Kratos вызывает `OnRecoveryCompleted` с payload:
  - external_id = `krt_ghost`
  - recovery_jti = `rec_flow_003`
  - email = `ghost@example.com`

**Then** `Operation` завершается с ошибкой `NOT_FOUND` (`Operation.error.code = NOT_FOUND`,
  текст вида `"User krt_ghost not found"`) — либо sync `NOT_FOUND`, если найти можно до
  спавна worker (decision: реализация может делать lookup синхронно — тогда RPC
  возвращает `NOT_FOUND` напрямую; обязателен именно код `NOT_FOUND`)
**And** **никаких side-effects**: в `user_token_revocations` cutoff не появился,
  в `audit_outbox` строки `iam.user.recovery_completed` нет,
  в `recovery_completions` строки `rec_flow_003` нет.

---

## Сценарий 5.3-04: Negative — email mismatch → отклонено (no side-effects)

**ID:** 5.3-04

**Given** существует `User` U с `external_id="krt_carol"`, `email="carol@example.com"`,
`invite_status=ACTIVE`

**When** Kratos вызывает `OnRecoveryCompleted` с payload:
  - external_id = `krt_carol`
  - recovery_jti = `rec_flow_004`
  - email = `attacker@evil.example.com`   *(не совпадает с users.email)*

**Then** `Operation` завершается с ошибкой `FAILED_PRECONDITION`
  (учётка существует, но состояние/идентичность не позволяет применить recovery;
  текст вида `"recovery email does not match user"`)
  — RPC НЕ применяет recovery
**And** **никаких side-effects**: cutoff не записан, audit-строки нет,
  `recovery_completions` строки `rec_flow_004` нет, `invite_status` U не изменён.

> Решение по коду: email-mismatch — это «well-formed payload, но состояние/
> идентичность не позволяет» → `FAILED_PRECONDITION` (per `api-conventions.md`:
> FailedPrecondition = состояние ресурса не позволяет). `INVALID_ARGUMENT`
> зарезервирован за malformed-полями (сценарий 5.3-06). Это явный contract-выбор
> для defense-against-mismatched-payload из proto-докстринга.

---

## Сценарий 5.3-05: Edge — дубликат (external_id, recovery_jti) → идемпотентный no-op

**ID:** 5.3-05

**Given** сценарий 5.3-01 уже выполнен для `recovery_jti="rec_flow_001"`
  (U re-enabled, cutoff C1 записан в момент T1, ровно одна audit-строка, строка
  `recovery_completions(rec_flow_001)` существует)
**And** между T1 и повтором U залогинился заново (новая сессия с `auth_time > C1`)

**When** Kratos повторно доставляет тот же webhook (at-least-once) —
`OnRecoveryCompleted` с payload:
  - external_id = `krt_alice`
  - recovery_jti = `rec_flow_001`   *(тот же flow-id)*
  - email = `alice@example.com`

**Then** `Operation` → `done=true`, `!error` (повтор «успешен»)
**And** `Operation.metadata.user_id`/`revoked_session_count` = сохранённые значения
  из первой обработки (читаются из `recovery_completions`)
**And** **второй cutoff НЕ записан**: `user_token_revocations.revoke_before` для U
  остаётся = C1 (не двигается к новому now) → **новая сессия (auth_time > C1) НЕ
  отзывается** (нет regression монотонности относительно момента recovery)
**And** в `audit_outbox` по-прежнему **ровно одна** строка `iam.user.recovery_completed`
  для этого `recovery_jti` (дубль не создан)
**And** в `recovery_completions` по-прежнему ровно одна строка `rec_flow_001`.

---

## Сценарий 5.3-06: Negative — malformed/пустые поля → INVALID_ARGUMENT (sync)

**ID:** 5.3-06

**Given** валидный существующий `User` (для изоляции причины ошибки от 5.3-03)

**When** Kratos вызывает `OnRecoveryCompleted` с одним из невалидных payload'ов
(decision-table; каждый — отдельный кейс):
  - (a) external_id = `""` (пусто, нарушает `required`)
  - (b) recovery_jti = `""` (пусто, нарушает `required`)
  - (c) email = `""` (пусто, нарушает `required`)
  - (d) external_id длиной > 128 (нарушает `<=128`)
  - (e) email длиной > 320 (нарушает `<=320`)

**Then** каждый возвращает **синхронно** `INVALID_ARGUMENT` (валидация — первыми
  стейтментами Execute, до спавна `Operation`)
**And** **никаких side-effects**: ни `recovery_completions`, ни cutoff, ни audit-
  строка не записаны.

---

## Сценарий 5.3-07: Atomicity — сбой посреди writer-tx → полный rollback

**ID:** 5.3-07

**Given** существует `User` U (`BLOCKED`, валидный email-match)
**And** в writer-tx инъецируется сбой ПОСЛЕ re-enable/cutoff, но ДО commit
  (напр. audit-insert падает — fault-injection в integration-тесте, testcontainers)

**When** обрабатывается `OnRecoveryCompleted(krt_dan, rec_flow_007, dan@example.com)`

**Then** `Operation` завершается ошибкой (`Operation.error` установлен; код —
  `INTERNAL` с фиксированным текстом, без leak'а pgx/SQL)
**And** **полный rollback**: `invite_status` U остался `BLOCKED` (re-enable откатан),
  в `user_token_revocations` cutoff для U **не** появился/не сдвинулся,
  в `audit_outbox` строки нет, в `recovery_completions` строки `rec_flow_007` **нет**
  (т.е. повтор сможет обработать flow заново — частичного «занятого» idempotency-
  ключа без эффектов не остаётся).

> Нормативно: re-enable + cutoff + audit + idempotency-insert — **одна writer-tx**
> (запрет #10). Не допускается partial re-enable без revoke/audit и не допускается
> «застрявший» idempotency-ключ, блокирующий повторную обработку при откате эффектов.

---

## Сценарий 5.3-08: Auth — несекретный/несанкционированный caller → fail-closed (production-mode)

**ID:** 5.3-08

**Given** стенд в production AuthN-mode (caller-policy/floor энфорсятся)
**And** `OnRecoveryCompleted` — в `GatewayFrontedInternalRPCs` (gateway-only) и
  exempt от `system_viewer`-floor (INV-FLOOR-6)

**When** на :9091 приходит вызов `OnRecoveryCompleted` от **не-api-gateway** модуля
  (verified mTLS-cert другого SA, напр. kacho-vpc) — либо без verified module-cert

**Then** caller-policy отклоняет: `PERMISSION_DENIED` (фиксированный текст
  `"permission denied"`), handler не выполняется, side-effects отсутствуют

**And (под-кейс)** в dev/newman-mode (нет mTLS, FGA-on-internal off) — оба гейта
  no-op pass-through (back-compat), и поведение определяется бизнес-логикой
  (сценарии 5.3-01…07 зелёные через api-gateway).

> Транспорт: Kratos бьёт recovery-webspook в api-gateway (secret-token,
> сконфигурированный в Kratos webhooks). api-gateway re-dial'ит :9091 СВОИМ
> client-cert (SAN `…/sa/kacho-api-gateway`) → caller-policy пропускает только
> gateway SA. Per-RPC ReBAC end-user — НЕ выполняется (Kratos — не kacho-seeded SA).

---

## Сценарий 5.3-09: Edge — одна Kratos-identity в нескольких Account'ах

**ID:** 5.3-09

**Given** одна Kratos-identity `external_id="krt_eve"` имеет два `User`-row:
  U1 (`account_id=acc_x`, `BLOCKED`, `email="eve@example.com"`),
  U2 (`account_id=acc_y`, `ACTIVE`, `email="eve@example.com"`)
  (partial UNIQUE допускает один external_id per-Account среди non-PENDING rows)

**When** Kratos вызывает `OnRecoveryCompleted(krt_eve, rec_flow_009, eve@example.com)`

**Then** recovery применяется к **всем** rows этой identity, разделяющим
  `external_id` И совпадающий `email`: U1 re-enabled (`BLOCKED→ACTIVE`),
  обе учётки получают revoke-all cutoff `reason="password-change"`
**And** `Operation.metadata.revoked_session_count` отражает суммарное число отозванных
  сессий; `Operation.metadata.user_id` — детерминированный выбор (id первого row,
  как в `UpsertFromIdentity.resolveUserID`)
**And** в `audit_outbox` — одна строка `iam.user.recovery_completed` на identity-recovery
  (event скоупится на identity; payload содержит `external_id`), `recovery_completions`
  одна строка `rec_flow_009`.

> Reality-check: credential (пароль) — атрибут Kratos-identity, не per-Account-row.
> Recovery меняет credential identity целиком → revoke касается всех её живых сессий.
> Поведение «один webhook = одна identity-recovery» согласовано с idempotency-ключом
> `recovery_jti` (flow-scoped, не user_id-scoped).

---

## Traceability (сценарий ↔ имя теста ↔ кейс)

| ID | Integration-тест (testcontainers, `internal/repo/...integration_test.go` / use-case) | Newman-кейс (`tests/newman/cases/*.py`) |
|---|---|---|
| 5.3-01 | `TestOnRecoveryCompleted_S01_Blocked_ReEnable_Revoke_Audit_Idempotent` | `CONF-5.3-01-recovery-blocked-reenable` (happy) |
| 5.3-02 | `TestOnRecoveryCompleted_S02_Active_NoopReEnable_Revoke_Audit` | `CONF-5.3-02-recovery-active` (happy) |
| 5.3-03 | `TestOnRecoveryCompleted_S03_UnknownExternalID_NotFound_NoSideEffects` | `NEG-5.3-03-recovery-unknown-extid` |
| 5.3-04 | `TestOnRecoveryCompleted_S04_EmailMismatch_FailedPrecondition_NoSideEffects` | `NEG-5.3-04-recovery-email-mismatch` |
| 5.3-05 | `TestOnRecoveryCompleted_S05_DuplicateJTI_IdempotentNoop` (concurrent goroutines на один `recovery_jti`) | `IDM-5.3-05-recovery-duplicate-jti` |
| 5.3-06 | `TestOnRecoveryCompleted_S06_MalformedFields_InvalidArgument` (table-driven a..e) | `VAL-5.3-06-recovery-malformed` |
| 5.3-07 | `TestOnRecoveryCompleted_S07_MidTxFailure_FullRollback` (fault-injection) | — (white-box only) |
| 5.3-08 | `TestOnRecoveryCompleted_S08_CallerPolicy_GatewayOnly_FailClosed` (authzguard) | — (prod-mode auth; dev-mode no-op) |
| 5.3-09 | `TestOnRecoveryCompleted_S09_MultiAccountIdentity_RevokeAll` | `CONF-5.3-09-recovery-multi-account` |

Имена — нормативный hint для `integration-tester`; финальные имена допускают
суффиксы, но `5.3-NN`-трасса в имени/аннотации обязательна.

## DoD (Definition of Done под-фазы)

- [ ] **TDD integration-first**: для 5.3-01…09 сначала написаны падающие
      (RED) integration-тесты (testcontainers Postgres) + use-case unit-тесты
      (mock-порты), прогнаны, падают по нужной причине → затем код → GREEN. В
      PR показана пара RED→GREEN (запрет #12).
- [ ] **Идемпотентность**: integration-тест с конкурентными goroutine'ами на один
      `recovery_jti` — ровно один INSERT выигрывает, остальные → no-op (нет
      второго cutoff, нет дубля audit). (5.3-05).
- [ ] **Атомарность**: integration-тест fault-injection (сбой до commit) → полный
      rollback, без «застрявшего» idempotency-ключа (5.3-07).
- [ ] **Migration**: новая (не редактируется применённая) — таблица
      `recovery_completions` (PK `recovery_jti`, `ON CONFLICT DO NOTHING`-dedup);
      **номер = следующий свободный в `internal/migrations/` на момент реализации**
      (НЕ хардкодить «0016»; live-top на дату дока = `0014`, т.е. ожидаемо `0015`,
      но перепроверить); ревью `db-architect-reviewer` (запрет #10/#5).
- [ ] **Handler**: `InternalHandler.OnRecoveryCompleted` реализован (больше не
      `Unimplemented`); use-case по паттерну `UpsertFromIdentity` (sync-валидация +
      sync-lookup → `Operation` → async-worker; либо sync-NOT_FOUND до спавна).
- [ ] **Revoke**: `RevokeAllUserTokens(reason="password-change")` для всех
      затронутых rows identity, cutoff в той же writer-tx.
- [ ] **Audit**: `iam.user.recovery_completed` эмитится в той же writer-tx
      (`evt_…` id, валидный event_type, payload без секретов), `tenant_account_id`
      = `User.AccountID`.
- [ ] **Auth**: подтверждено, что RPC уже registered + gateway-only (caller_policy) +
      floor-exempt (INV-FLOOR-6) + `<exempt>` в permission_catalog — **изменений
      proto/registration/gateway не требуется** (если нужна правка proto-docstring
      `DISABLED→BLOCKED` — отдельный proto-doc PR через `proto-api-reviewer`).
- [ ] **Newman**: ≥1 happy + ≥1 negative (5.3-01/02/09 + 5.3-03/04/06) через
      api-gateway (`gen.py` → коллекция; `validate-cases.py` + CASES-INDEX).
- [ ] **Финальная верификация**: `go test ./... -race` + `golangci-lint run` +
      `govulncheck` + `gosec` зелёные; newman зелёные.
- [ ] **Vault-trail**: обновить `resources/kacho-iam-user.md` (re-enable
      lifecycle), `rpc/kacho-iam-internal-user-service.md` (OnRecoveryCompleted
      реализован), создать/обновить `edges/kratos-to-iam-recovery.md` +
      `resources/kacho-iam-recovery-completions.md`; KAC-127 / #122 KAC-trail.

## Решения ревьюера (резолюция открытых вопросов) — REVIEW-LOCKED

Все 4 вопроса разрешены `acceptance-reviewer` 2026-06-16 (ground-truth сверена с
кодом). Эти решения — **часть контракта**; менять только через новый review-round.

1. **`DISABLED` vs `BLOCKED` → re-enable = `BLOCKED → ACTIVE`.** Domain-enum
   (`internal/domain/user.go`) = `PENDING | ACTIVE | BLOCKED` — значения
   `DISABLED` **нет**. Proto-docstring (`internal_user_service.proto:52`
   «re-enables … if `invite_status` was `DISABLED`») — это doc-drift; трактуется
   как `BLOCKED`. **`PENDING` (неактивированный invite) recovery НЕ re-enable'ит**
   — recovery работает по `external_id`, а `PENDING`-row имеет `external_id=""`
   (DB CHECK `users_invite_status_consistency`) и по `external_id` найдена быть не
   может; только `BLOCKED → ACTIVE`, `ACTIVE → no-op`. Правка proto-docstring
   `DISABLED→BLOCKED` — **optional/non-blocking** proto-doc-only PR через
   `proto-api-reviewer`, **НЕ prerequisite** для этой iam-реализации (поведение от
   docstring не зависит). Reality-note: domain-docstring User.go называет `BLOCKED`
   «reserved … no RPC sets it today» — этот RPC становится первым consumer'ом
   `BLOCKED`-перехода (на чтение); set'ит `BLOCKED` по-прежнему отдельный
   admin-flow (вне scope этой под-фазы).

2. **email-mismatch → `FAILED_PRECONDITION`.** Well-formed payload (все 3 поля
   валидны по формату), но идентичность/состояние ресурса не совпадает →
   `FAILED_PRECONDITION` (per `api-conventions.md`). `INVALID_ARGUMENT`
   зарезервирован за malformed-полями (5.3-06). Текст — `"recovery email does not
   match user"` (часть контракта). См. 5.3-04.

3. **multi-account semantics (5.3-09) → revoke по ВСЕМ rows identity** (по
   `external_id` + совпадающий `email`). Credential (пароль) — атрибут Kratos-
   identity, не per-Account-row; recovery меняет credential целиком → revoke-all
   касается всех живых сессий identity. `metadata.user_id` — детерминированный
   выбор (id первого row по `created_at ASC`, как в `UpsertFromIdentity`); одна
   audit-строка на identity-recovery.

4. **idempotency-ключ → `recovery_jti` как глобальный PK.** Kratos генерирует
   уникальный `recovery_jti` на каждый recovery-flow → ключ flow-scoped, таблица
   `recovery_completions` глобальная (не scoped по account_id). `INSERT … ON
   CONFLICT (recovery_jti) DO NOTHING` — DB-level dedup-gate (запрет #10).
   Proto-docstring говорит «idempotent on `(external_id, recovery_jti)`» — это
   избыточная формулировка (composite); канон — **`recovery_jti` один**
   (`recovery_jti` уже глобально-уникален, `external_id` в ключе не нужен). User
   с N Account'ами всё равно имеет один user-level token-revocation cutoff —
   корректно (токены user-scoped).
   Audit-row `tenant_account_id = User.AccountID` (primary account первого row).
   **Номер migration** для `recovery_completions` — следующий свободный в
   `internal/migrations/` на момент реализации (live-top на дату дока = `0014`,
   ожидаемо `0015`; НЕ хардкодить «0016» — перепроверить; архив
   `docs/architecture/migrations-history/0015..0025` — НЕ live-каталог).
