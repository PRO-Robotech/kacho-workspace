# Sub-phase W2.C — Stream C: Block F API tokens (`kat_…`) — Acceptance

> **Status**: DRAFT (awaiting `acceptance-reviewer` per workspace `CLAUDE.md` §Запреты #1).
> **Date**: 2026-05-24
> **YouTrack**: KAC-W2.C (subtask of [KAC-134](https://prorobotech.youtrack.cloud/issue/KAC-134) epic "kacho-iam → production-ready"; the per-subtask KAC issue is created by controller after this doc reaches APPROVED).
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer`
> **Target repos**:
>   - **Primary**: `PRO-Robotech/kacho-proto` —
>     - `proto/kacho/cloud/iam/v1/api_token.proto` (NEW message: `ApiToken`, `ApiTokenScope`)
>     - `proto/kacho/cloud/iam/v1/api_token_service.proto` (NEW: public `ApiTokenService` + internal `InternalApiTokenService`)
>     - regen `gen/go/kacho/cloud/iam/v1/api_token*.pb.go`, `*_grpc.pb.go`
>   - **Primary**: `PRO-Robotech/kacho-iam` —
>     - `internal/migrations/0026_w2c_api_tokens.sql` (table `api_tokens` + partial UNIQUE on `prefix`, indices, FK to `users`/`service_accounts`)
>     - `internal/domain/api_token.go` (newtypes: `ApiTokenID`, `ApiTokenPlaintext`, `ApiTokenPrefix`, `ApiTokenHash`, `ApiTokenScope`; `Validate()` cumulative-multierr)
>     - `internal/repo/kacho/api_token/{iface,pg/repo,repomock/repo}.go` (CQRS Reader/Writer; partial-UNIQUE retry on prefix collision; CAS on Revoke)
>     - `internal/apps/kacho/api/api_token/{handler,usecases,redactor}.go` (slice-per-RPC: Create / List / Get / Delete; secret-once redaction parity with W1.6 #11 SA-key pattern)
>     - `internal/apps/kacho/api/api_token/internal_handler.go` (InternalApiTokenService — GetPrefix lookup for gateway; emits `subject_change_outbox` on Delete via existing W1.2 writer)
>     - `cmd/kacho-iam/main.go` (wiring + audit hook into B.9 pipeline iff B.9 merged; else no-op AuditLogger interface respected)
>   - **Primary**: `PRO-Robotech/kacho-api-gateway` —
>     - `internal/middleware/auth.go` — extend Bearer path: `kat_<…>` branch → `InternalApiTokenService.GetPrefix(prefix)` → argon2id-verify (constant-time) → inject Principal of token's subject + token-scope into ctx
>     - `internal/middleware/api_token_cache.go` (NEW): per-prefix cache (TTL 60s; invalidated by existing W1.2 `subject_change_outbox` drainer when event_type=`api_token_revoke`)
>     - `internal/middleware/authz.go` — token-scope gate: if request has `kacho_token_scopes` in ctx, deny when called RPC ∉ scopes (PermissionDenied 403)
>     - register `InternalApiTokenService` gRPC client (cluster-internal, port 9091, parity W1.2 InternalAuthzCacheService)
>   - **Touched**: `PRO-Robotech/kacho-api-gateway/internal/restmux/mux.go` — register **public** `ApiTokenService` on REST (`/iam/v1/apiTokens*`); `InternalApiTokenService` registered ONLY on internal listener (запрет #6).
>   - **NOT touched**: `kacho-corelib` (no new helper required — argon2id from `golang.org/x/crypto/argon2`; `subject_change_outbox` writer port lives in `kacho-iam/internal/repo/.../access_binding/iface.go` and is already extended by W1.2 for arbitrary event_type values — `api_token_revoke` is a new enum value, not a new code path).
> **Branch (all repos)**: `KAC-W2C`.
> **Parent epic plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-master.md` Wave 2 Stream C.
> **Wave plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-wave2-streamC.md` (TBD — written at impl-start, this doc is the spec it executes against).
> **Predecessors (must be `main`-merged before impl starts)**:
> - **W1.2 — subject_change cache invalidation** (KAC-138) — **MERGED**. W2.C reuses (a) `subject_change_outbox` table + drainer to invalidate gateway cache on token revoke; (b) the per-prefix gateway cache pattern (parity with per-subject cache, just keyed by `kat_<7>` instead of `<subject_id>`).
> - **W1.3 — gateway authz fail-closed** (KAC-139) — **MERGED**. Without it, a token whose `GetPrefix` lookup transiently fails would fall through to anonymous → 403 ≠ Unauthenticated semantics; fail-closed makes the gateway return 503 (Unavailable) instead. Same shape applies to api-token authn-lookup failure.
> - **W1.4 — principal propagation** (KAC-140) — **MERGED**. The Principal injected by api-token branch must propagate cross-service (so downstream iam/vpc/compute see `user:<id>` or `service_account:<id>` set on behalf of the token, not the gateway's own SVID).
> - **W1.6 — Remediation Chunk 2** (KAC-164) — **MERGED**. Provides (a) anti-anon explicit read-only allowlist (Create/Delete/List/Get of ApiToken go through it — Create/Delete/List require authenticated principal; Get currently considered read-only but is gated by self-only handler check, see §6.6), (b) the SA-key Issue-secret-once + post-return redaction pattern (W1.6 #11 in `sa_keys/usecases.go::scheduleSecretRedact`) which `api_token/usecases.go::Create` replicates verbatim for `kat_…` plaintext, (c) `authzguard.PrincipalUserID(ctx)` helper used for `created_by_user_id` stamping (parity with W1.6 #53), (d) Operation.Get NotFound-for-anonymous (W1.6 #9) — ensures the Operation row carrying `kat_…` plaintext returned by `Create` is not GET-able by anonymous via op-id leak.
> - **Optional**: B.9 audit-pipeline (Wave 2 Stream B). If B.9 merged → token-usage audit emits to VictoriaLogs+vector.dev. If not → AuditLogger interface present, impl is no-op; W2.C does not block on B.9.

---

## 0. Преамбула — что эта sub-итерация (précis)

W2.C добавляет в kacho-iam **новый ресурс** `ApiToken` (`kat_…` — Kachō API Token), который позволяет
пользователю / service-account'у создать **долго-живущий** Bearer-токен с **уже-обмененным
identity-проверкой** (presented prefix → argon2id-verify → cached principal). Заменяет нынешнюю
симуляцию в `tests/newman/cases/authz-sa-apitoken.py` реальной фичей.

**Что NEW в этой sub-итерации:**

1. **Proto**: `kacho.cloud.iam.v1.ApiToken` (плоский ресурс), `ApiTokenScope` (RPC-allowlist),
   `ApiTokenService` (public CRUD: Create/List/Get/Delete) + `InternalApiTokenService`
   (cluster-internal: `GetPrefix` — для gateway authn lookup; запрет #6 строго).
2. **Migration**: `api_tokens` table в schema `kacho_iam` — `id, prefix, hash, subject_type,
   subject_id, scopes[], expires_at, last_used_at, created_at, revoked_at, created_by_user_id,
   description`. Партишн UNIQUE на `prefix WHERE revoked_at IS NULL` (hot-path collision guard).
   FK на `users(id)`/`service_accounts(id)` через `subject_id` (within-iam-DB; запрет #10 — DB-level
   refcheck).
3. **Usecase** kacho-iam slice-per-RPC `internal/apps/kacho/api/api_token/`:
   - **Create**: generate `kat_<24-char-base32>` via `crypto/rand`, argon2id-hash, persist row
     with `prefix=kat_<first-7-base32-chars>` + `hash` + `subject_*` + `scopes` + `expires_at`;
     return plaintext **ONCE** in `Operation.response.token` field; secret redacted post-return via
     W1.6 #11 pattern (single-statement `jsonb_set`).
   - **Delete**: soft-revoke via single-statement CAS `UPDATE api_tokens SET revoked_at=now()
     WHERE id=$id AND revoked_at IS NULL RETURNING …` (idempotent re-revoke = NotFound on 0-rows);
     emits `subject_change_outbox` row with `event_type='api_token_revoke'`, `subject_id=<prefix>`
     (so gateway W1.2 drainer can invalidate per-prefix cache).
   - **List**: by `(subject_type, subject_id)` — caller self-only (handler check `IsSelf(ctx,
     subject_id)` OR `account-admin` via `requireGrantAuthority`-parity); filters by `revoked_at`.
   - **Get**: by id; **redacted** (no `hash`, no `plaintext`; only metadata fields).
4. **Gateway authn path** (`kacho-api-gateway/internal/middleware/auth.go`):
   - In `validateJWT`/`authorize` flow, **before** JWT-parse, check `if strings.HasPrefix(bearer,
     "kat_")`. If true → branch to `apiTokenAuthn(ctx, bearer)`.
   - Extract `prefix = bearer[:11]` (`"kat_" + 7 base32 chars`); call
     `InternalApiTokenService.GetPrefix(prefix)` via cluster-internal gRPC (port 9091).
   - Receive `(hash, subject_type, subject_id, scopes, expires_at, revoked_at)`. Constant-time
     verify `argon2id.Verify(presentedFullToken, hash)`. If revoked / expired → `Unauthenticated`
     (HTTP 401, not 403 — authN failure precedes authZ; same as W1.6 KAC-127 pre-gate, see
     `auth.go::authorize` JWT-validation-failure block).
   - On match: inject `Principal{Type: subject_type, ID: subject_id}` AND
     `kacho_token_scopes = scopes` into ctx (carried via metadata
     `x-kacho-token-scopes` to backend; cross-service propagation via W1.4).
   - **Cache lookup** (`api_token_cache.go`): per-prefix LRU with TTL=60s; invalidated via
     `subject_change_outbox` drainer (W1.2) when event_type=`api_token_revoke`, with
     `subject_id=<prefix>` → cache eviction. Backstop: TTL=60s ensures full convergence even if
     drainer-event missed (parity with W1.2 §0 latency promise).
5. **Gateway scope-gate** (`authz.go`): after auth-resolved, if ctx has `kacho_token_scopes` set,
   gate the RPC against scopes — request RPC's FullMethod (or its catalog `permission` string,
   §4.4 decision OQ-W2.C-1) must be in scopes; else `PermissionDenied` 403. **Least-privilege —
   token ⊆ subject** (master plan OQ-2 decision: F.5(b)). Even if subject has broader rights, the
   token narrows them; scope grammar — §4.5 (canonical: `<service>.<resource>.<verb>` matching
   catalog).
6. **Audit**: token-usage logged (token-id, RPC FullMethod, ts, principal) via `AuditLogger`
   interface; concrete impl (VictoriaLogs+vector.dev) wired by B.9 if merged, no-op otherwise.

### 0.1 W2.C НЕ включает

- **Token introspection RPC** (OAuth-style `/oauth2/introspect`) — NOT in scope. Inspection of
  metadata via own `ApiTokenService.Get` only (returns redacted token row); third-party token
  introspection is a Hydra-flow feature (SA-keys handle that already).
- **Refresh tokens** — NOT in scope. `kat_…` tokens are **non-refreshable, fixed-expiry**. Client
  rotation = explicit Create + Delete dance (or rely on expires_at and create-then-delete-old).
  Refresh-token semantics add complexity (refresh-token-revoke, refresh-token-rotation,
  refresh-grant flow) — separate feature ticket if needed post-prod.
- **Per-RPC quota / rate-limit** — NOT in scope. Token has no rate limit beyond what gateway
  global rate-limit applies (WS-7.6 in production-launch-plan.md). Quota / per-token RPS — separate
  feature.
- **Token rotation API** (Create-new-then-revoke-old in single RPC) — NOT in scope. Client does
  it manually.
- **Multi-subject tokens** (one token authorising N subjects) — NOT in scope. Each token has
  **exactly one** subject (user or service_account); MVP simplicity.
- **Token scopes carrying conditions** (ABAC predicates) — NOT in scope. Scope = RPC allowlist
  (string list, FullMethod or catalog-permission per §4.5). Conditions can come later via
  `ConditionsService`.
- **Per-tenant token quota** (max active tokens per subject / per account) — NOT in scope.
  Recommended default 50/subject — enforced softly via a `service_quotas` lookup (no schema; if
  exceeded, return FailedPrecondition). Decision OQ-W2.C-4.
- **Auto-revoke on subject delete via app code** — replaced by `FK ON DELETE CASCADE` (DB-level;
  see §3 schema). Subject delete cascades to tokens via FK; cascade emits N revoke-events into
  outbox via post-delete trigger (§3.2). No app-code worker needed.
- **Federation login → kat issuance flow** — NOT in scope. Tokens come from `ApiTokenService.Create`
  alone (subject-direct).
- **B.9 audit-pipeline implementation** — separate stream (B); W2.C wires the `AuditLogger` port,
  default no-op adapter. If B is merged first, wiring uses real adapter; else no-op.

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** (workspace) — кодирование только после `acceptance-reviewer` APPROVED | данный doc — gate; статус `DRAFT` выше. |
| **Запрет #2** — НЕ упоминать "yandex" | в коде/комментариях/тестах не упоминается. |
| **Запрет #3** — НЕ ORM | только handwritten pgx + sqlc если потребуется. Repo — CQRS (`Reader`/`Writer` interfaces в `iface.go`, pgxpool impl в `pg/repo.go`). |
| **Запрет #4** — НЕ cross-service cascade delete | FK `api_tokens.subject_id → users(id) / service_accounts(id) ON DELETE CASCADE` — **within-iam-DB** (одна схема `kacho_iam`); разрешено per §«Within-service refs — DB-уровень обязателен». |
| **Запрет #5** — НЕ редактировать применённую миграцию | новая миграция `0026_w2c_api_tokens.sql`; не трогаем 0001-0025. |
| **Запрет #6** — Internal.* НЕ на external TLS endpoint | `InternalApiTokenService.GetPrefix` регистрируется **только** на internal listener (port 9091, mTLS — gateway calls it cluster-internally). Public `ApiTokenService` (Create/List/Get/Delete) — на external listener. Регистрация в restmux разделена через `iamInternalAddr` блок (parity с W1.2 InternalAuthzCacheService). |
| **Запрет #7** — broker отсутствует | LISTEN/NOTIFY через `subject_change_outbox` (W1.2 reused) — Postgres-native, не Kafka/NATS. |
| **Запрет #8** — DB-per-service | gateway не держит pool на kacho_iam DB; вместо этого зовёт `InternalApiTokenService.GetPrefix` через gRPC. |
| **Запрет #9** — мутации возвращают Operation | `ApiTokenService.Create`, `Delete` возвращают `*operation.Operation`. `List`, `Get`, `InternalApiTokenService.GetPrefix` — sync read. |
| **Запрет #10** — within-service refs DB-level | (a) `subject_id → users(id) / service_accounts(id) ON DELETE CASCADE` (FK); (b) `created_by_user_id → users(id) ON DELETE SET NULL`; (c) partial `UNIQUE (prefix) WHERE revoked_at IS NULL` — гарантирует prefix-uniqueness среди активных токенов (collision-detect на INSERT); (d) Delete = atomic CAS `UPDATE … WHERE revoked_at IS NULL RETURNING …` — idempotent re-revoke = 0-rows → NotFound (race-free); (e) Create retries N times (default 3) на 23505 prefix-collision (cryptographically rare с 24 chars random, но enforced на DB-уровне). |
| **Запрет #11** — НИКАКОГО ТЕХ. ДОЛГА / TODO | doc не оставляет открытых TODO; out-of-scope features перечислены в §0.1 и §9 явно; defensive guards (cache TTL, rate-limit) — либо реализованы, либо вынесены в separate ticket с обоснованием «not in MVP». |
| **Запрет #12** — Test-first (TDD строгий) | каждый из feature-fragments открывается **RED**-тестом (integration + newman), затем кодом. См. §5 RED phase commit. |
| **Запрет #13** (test-only PR rules) | не применимо: W2.C — feature PR с тестами + кодом в том же PR. |
| **CLAUDE.md §Принцип переиспользования через kacho-corelib** | argon2id — внешняя библиотека (`golang.org/x/crypto/argon2`); НЕ заводим обёртку в corelib (used by single feature for now). Если в будущем второй сервис захочет argon2id — выделить тогда. |
| **CLAUDE.md §«Within-service refs DB-уровень обязателен»** | §3 schema полностью — FK + partial UNIQUE + CAS-on-revoke. |
| **CLAUDE.md §«Инфра-чувствительные данные»** | `hash` — НИКОГДА не возвращается в **публичных** ответах (`ApiTokenService.Get`/`List` mappers strip it). `plaintext` token (`kat_…`) — НИКОГДА не хранится в DB (только в Operation.response.token jsonb на время до первого Op.Get, потом замещается `<redacted>`). `InternalApiTokenService.GetPrefix` — internal-only, возвращает hash для argon2id-verify в gateway; gateway держит его in-memory кратко в cache (60s) и НЕ логирует. |
| **CLAUDE.md §«API contract — flat resources + Operations»** | `ApiToken` — плоский message; `Create`/`Delete` — async via Operation; `List`/`Get` — sync. Никаких nested resource структур. |
| **Vault discipline** | KAC-W2C.md trail; NEW `resources/iam-api-token.md`, NEW `rpc/iam-api-token-service.md`, NEW `packages/iam-apps-api-token.md`; UPDATE `packages/apigw-middleware.md` (extend Bearer flow), UPDATE `edges/iam-to-apigw-cache-invalidation.md` (api_token_revoke emit). |

---

## 2. Глоссарий

- **`kat_` prefix** — Kachō API Token literal prefix. Plaintext token format: `kat_<24 chars
  base32-no-padding>`. `prefix` column stores `kat_<first 7 chars>` (11 chars total) — used as
  cache-key + lookup-key by gateway authn branch.
- **`base32-no-padding`** — RFC 4648 base32 alphabet, lowercase, no `=`-padding. 24 chars
  ≈ 120 bits of entropy after base32-decode. Random source: `crypto/rand.Read`.
- **`argon2id`** — hashing algorithm (memory-hard; recommended by OWASP for password storage in
  2024+). Parameters (default): time=1, memory=64 MiB, threads=4, keyLen=32, saltLen=16.
  Constant-time verify via `subtle.ConstantTimeCompare` after re-derivation. Persisted hash
  format: `argon2id$<params>$<salt>$<hash>` (PHC standard).
- **`scope`** — RPC allowlist string; matches against catalog-permission (e.g.
  `"iam.accounts.get"`, `"vpc.networks.list"`). Multiple scopes — token granted intersection of
  subject-rights AND scope-list (per OQ-2 master decision F.5(b) — least-privilege subset).
- **`scope subset rule`** (master plan OQ-2 / F.5(b)): принципал имеет permissions `Pₛ`; токен
  имеет scopes `Pₜ`. Эффективные permissions токена = `Pₛ ∩ Pₜ` (intersection). Если scope не
  в `Pₛ` — gateway даёт DENY (от scope-gate); если в `Pₛ` но не в `Pₜ` — DENY (от token-scope
  gate). Если в обоих — ALLOW.
- **`prefix collision`** — два токена с одинаковым `kat_<7>`. Cryptographically rare (24-char
  random ⇒ first-7 collision probability ≈ 1/32⁷ ≈ 3.4e-11 per pair); enforced by partial
  `UNIQUE` index on `prefix WHERE revoked_at IS NULL`. Create-usecase retries 3 times on `23505`
  (PG unique-violation) — virtually never triggers in practice but ensures correctness.
- **`token redaction` (parity W1.6 #11)** — после успешного `Create` → Operation.MarkDone с
  `response.token = "kat_<plaintext>"`; через 20-200ms `scheduleTokenRedact` goroutine
  обновляет `operations.response.token` → `"<redacted>"` через single-statement `jsonb_set`.
  Idempotent.
- **`audit-event shape`** — `{event_type: "api_token.use", token_id: "<id>", subject_type,
  subject_id, rpc_full_method, ts, source_ip}`. Эмиттится AuditLogger interface (no-op default;
  B.9 wiring activates real shipping).
- **`api_token_revoke` event** — `subject_change_outbox` row, `event_type='api_token_revoke'`,
  `subject_id=<token.prefix>` (NOT `<subject_id>` — prefix is the gateway's cache key for
  api_token_cache). Drainer W1.2 picks it up → invalidates gateway per-prefix cache entry.

---

## 3. Data model — миграция `0026_w2c_api_tokens.sql` (kacho-iam, NEW)

### 3.1 Полный DDL (in scope)

```sql
-- 0026_w2c_api_tokens.sql
-- KAC-W2C — Block F API tokens.
-- Establishes the api_tokens table with: partial-UNIQUE prefix (active),
-- FK to user/service-account subject (within-iam-DB only — запрет #4 OK),
-- soft-revoke via revoked_at, audit-friendly created_by_user_id (FK with
-- SET NULL on user delete). Cascade delete from subject auto-revokes via
-- trigger that emits subject_change_outbox events.

SET search_path TO kacho_iam, public;

CREATE TABLE kacho_iam.api_tokens (
    id                  text         NOT NULL PRIMARY KEY,            -- kat<17-char-tail>
    prefix              text         NOT NULL,                        -- kat_<7-base32> (11 chars)
    hash                text         NOT NULL,                        -- argon2id PHC string
    subject_type        text         NOT NULL,                        -- 'user' | 'service_account'
    subject_id          text         NOT NULL,                        -- FK polymorphic; checked below
    scopes              text[]       NOT NULL DEFAULT '{}',           -- catalog-permission strings
    description         text         NOT NULL DEFAULT '',             -- ≤256 chars
    expires_at          timestamptz,                                  -- NULL → no expiry
    last_used_at        timestamptz,                                  -- updated by gateway (soft-write best-effort)
    created_by_user_id  text,                                         -- FK users(id) ON DELETE SET NULL
    created_at          timestamptz  NOT NULL DEFAULT now(),
    revoked_at          timestamptz,                                  -- soft-revoke marker

    CONSTRAINT api_tokens_subject_type_check
        CHECK (subject_type IN ('user', 'service_account')),
    CONSTRAINT api_tokens_prefix_format_check
        CHECK (prefix ~ '^kat_[a-z2-7]{7}$'),
    CONSTRAINT api_tokens_id_prefix_check
        CHECK (id ~ '^kat[a-zA-Z0-9]{17}$'),
    CONSTRAINT api_tokens_description_length_check
        CHECK (char_length(description) <= 256),
    CONSTRAINT api_tokens_scopes_count_check
        CHECK (array_length(scopes, 1) IS NULL OR array_length(scopes, 1) <= 100),
    CONSTRAINT api_tokens_created_by_fk
        FOREIGN KEY (created_by_user_id) REFERENCES kacho_iam.users(id) ON DELETE SET NULL
);

-- Polymorphic FK via triggers (subject_type → users.id OR service_accounts.id).
-- Function checks referenced row exists at INSERT/UPDATE; ON DELETE of parent
-- cascades to api_tokens via a separate AFTER-DELETE trigger on users/service_accounts.

CREATE OR REPLACE FUNCTION kacho_iam.api_tokens_subject_exists()
RETURNS trigger AS $$
DECLARE
    found boolean;
BEGIN
    IF NEW.subject_type = 'user' THEN
        SELECT true INTO found FROM kacho_iam.users WHERE id = NEW.subject_id;
    ELSIF NEW.subject_type = 'service_account' THEN
        SELECT true INTO found FROM kacho_iam.service_accounts WHERE id = NEW.subject_id;
    ELSE
        RAISE EXCEPTION 'api_tokens: unknown subject_type %', NEW.subject_type
            USING ERRCODE = '23514'; -- check_violation → service maps to InvalidArgument
    END IF;
    IF found IS NULL THEN
        RAISE EXCEPTION 'api_tokens: subject %/% not found', NEW.subject_type, NEW.subject_id
            USING ERRCODE = '23503'; -- foreign_key_violation → FailedPrecondition
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER api_tokens_subject_exists_trg
    BEFORE INSERT OR UPDATE OF subject_id, subject_type ON kacho_iam.api_tokens
    FOR EACH ROW EXECUTE FUNCTION kacho_iam.api_tokens_subject_exists();

-- Cascade on subject delete: AFTER DELETE on users/service_accounts → revoke
-- tokens + emit subject_change_outbox event (for gateway cache invalidation).
CREATE OR REPLACE FUNCTION kacho_iam.api_tokens_cascade_revoke_on_subject_delete()
RETURNS trigger AS $$
DECLARE
    tok record;
    sub_type text;
BEGIN
    sub_type := TG_ARGV[0];  -- 'user' or 'service_account'
    FOR tok IN
        SELECT id, prefix
          FROM kacho_iam.api_tokens
         WHERE subject_type = sub_type
           AND subject_id = OLD.id
           AND revoked_at IS NULL
    LOOP
        UPDATE kacho_iam.api_tokens
           SET revoked_at = now()
         WHERE id = tok.id;
        -- Emit cache-invalidation event via subject_change_outbox (W1.2 reuse).
        INSERT INTO kacho_iam.subject_change_outbox
            (subject_id, op, event_type, payload)
        VALUES (tok.prefix, 'api_token_revoke', 'api_token_revoke',
                jsonb_build_object('token_id', tok.id,
                                   'subject_type', sub_type,
                                   'cascade_from', 'subject_delete'));
    END LOOP;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_delete_revoke_api_tokens_trg
    AFTER DELETE ON kacho_iam.users
    FOR EACH ROW EXECUTE FUNCTION kacho_iam.api_tokens_cascade_revoke_on_subject_delete('user');

CREATE TRIGGER sa_delete_revoke_api_tokens_trg
    AFTER DELETE ON kacho_iam.service_accounts
    FOR EACH ROW EXECUTE FUNCTION kacho_iam.api_tokens_cascade_revoke_on_subject_delete('service_account');

-- Hot-path lookup index: gateway authn calls GetPrefix with prefix string.
-- Partial UNIQUE on active tokens — guarantees collision-detect on INSERT
-- AND keeps the index small (revoked tokens drop out automatically).
CREATE UNIQUE INDEX api_tokens_prefix_active_uniq
    ON kacho_iam.api_tokens (prefix)
    WHERE revoked_at IS NULL;

-- ListByOwner hot-path: includes revoked filter as predicate field.
CREATE INDEX api_tokens_subject_active_idx
    ON kacho_iam.api_tokens (subject_type, subject_id, revoked_at);

-- Audit / last-used updates index (gateway best-effort writes).
CREATE INDEX api_tokens_last_used_idx
    ON kacho_iam.api_tokens (last_used_at DESC NULLS LAST)
    WHERE revoked_at IS NULL;
```

### 3.2 Invariants delivered (mapped to запрет #10)

| # | Invariant | DB mechanism |
|---|---|---|
| I-01 | `prefix` уникален среди активных токенов | partial `UNIQUE (prefix) WHERE revoked_at IS NULL` (=`api_tokens_prefix_active_uniq`) |
| I-02 | `subject_id` ссылается на существующий user/service_account | trigger `api_tokens_subject_exists` (BEFORE INSERT/UPDATE) → ERRCODE 23503 на dangling |
| I-03 | Subject delete revokes own tokens + emits cache-invalidation events | trigger `*_delete_revoke_api_tokens_trg` (AFTER DELETE) → soft-revoke + outbox-emit |
| I-04 | `prefix` format = `kat_<7 base32>` | CHECK `api_tokens_prefix_format_check` (regex) → 23514 → InvalidArgument |
| I-05 | `id` format = `kat<17 alphanumeric>` | CHECK `api_tokens_id_prefix_check` → 23514 → InvalidArgument |
| I-06 | Revoke is idempotent + race-free | CAS `UPDATE … WHERE revoked_at IS NULL RETURNING …` (single statement); 0-rows → NotFound |
| I-07 | `description` length ≤256 | CHECK `api_tokens_description_length_check` |
| I-08 | `scopes` count ≤100 | CHECK `api_tokens_scopes_count_check` |
| I-09 | `created_by_user_id` clears on user delete (audit-preserving) | FK `ON DELETE SET NULL` |

SQLSTATE→sentinel mapping (parity with §«Within-service refs» CLAUDE.md table):
- 23503 → `ErrFailedPrecondition` (subject not found / FK violation)
- 23505 → `ErrAlreadyExists` (prefix collision; usecase retries 3 times then surfaces)
- 23514 → `ErrInvalidArgument` (CHECK violation: prefix/id format, description length)

---

## 4. Implementation steps (per file/component)

### 4.1 Proto — `proto/kacho/cloud/iam/v1/api_token.proto` (NEW)

```protobuf
syntax = "proto3";

package kacho.cloud.iam.v1;

import "google/protobuf/timestamp.proto";

option go_package = "github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/iam/v1;iamv1";

// ApiToken — Kachō API Token (kat_<…>) — long-lived Bearer credential
// representing a User or ServiceAccount with a least-privilege scope subset.
// Plaintext token returned ONCE in ApiTokenService.Create response (oneshot);
// kacho-iam stores only the argon2id hash + first-7-char prefix for lookup.
message ApiToken {
  // kacho-iam-generated id (kat<17-alphanumeric>); stable, opaque.
  string id = 1;
  // First 11 chars of plaintext token (`kat_<7 base32>`); used as gateway
  // authn lookup key. Safe to expose — does not enable token impersonation
  // without the full 28-char plaintext + argon2id verify.
  string prefix = 2;
  // Token subject — either a User (`subject_type="user"`) or a
  // ServiceAccount (`subject_type="service_account"`).
  string subject_type = 3;
  string subject_id = 4;
  // RPC scopes — catalog-permission strings (e.g. "iam.accounts.get"). Empty
  // list means token has ZERO permissions (defensive least-privilege default;
  // see ApiTokenService.Create §4.4 — Create validates non-empty unless
  // explicit `allow_zero_scope=true` flag set).
  repeated string scopes = 5;
  // Human-readable description (≤256 chars).
  string description = 6;
  // ISO timestamp when token expires; null/zero → no expiry.
  google.protobuf.Timestamp expires_at = 7;
  // Last successful authn use (best-effort gateway write; precision ~1min).
  google.protobuf.Timestamp last_used_at = 8;
  // User-id of the principal who created the token (audit field).
  string created_by_user_id = 9;
  google.protobuf.Timestamp created_at = 10;
  // Non-null timestamp → soft-revoked. Revoked tokens are returned by
  // ApiTokenService.Get/List with revoked_at set; gateway authn rejects them.
  google.protobuf.Timestamp revoked_at = 11;
  // NEVER set on Get/List responses — only on Create's Operation.response.
  // Plaintext token string `kat_<24 base32>`; redacted to "<redacted>" after
  // first Operation.Get return (W1.6 #11 pattern).
  string plaintext = 12;
}
```

### 4.2 Proto — `proto/kacho/cloud/iam/v1/api_token_service.proto` (NEW)

```protobuf
syntax = "proto3";

package kacho.cloud.iam.v1;

import "google/api/annotations.proto";
import "kacho/cloud/api/operation.proto";
import "kacho/cloud/iam/v1/api_token.proto";
import "kacho/cloud/operation/operation.proto";
import "kacho/cloud/validation.proto";
import "kacho/iam/authz/v1/authz_options.proto";

option go_package = "github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/iam/v1;iamv1";

// ApiTokenService — public CRUD for kat_<…> long-lived API tokens.
//
// Authority model (least-privilege; master plan OQ-2 = F.5(b)):
//   - Create: caller (authenticated principal) creates a token for
//     `subject_type+subject_id` IF caller `IsSelf(subject_id)` OR
//     caller `account-admin` on subject's account (parity W1.6 #13 —
//     requireGrantAuthority on subject's owning account).
//   - List / Get: same self-or-admin rule.
//   - Delete: same self-or-admin rule; idempotent (re-revoke = NotFound).
//
// Gateway authn (api-gateway/middleware/auth.go) bypasses public CRUD path
// and uses InternalApiTokenService.GetPrefix to resolve the principal from
// a presented Bearer `kat_<…>`.
service ApiTokenService {
  // Create mints a new token; returns Operation whose response carries
  // plaintext exactly ONCE.
  rpc Create (CreateApiTokenRequest) returns (operation.Operation) {
    option (google.api.http) = { post: "/iam/v1/apiTokens" body: "*" };
    option (kacho.cloud.api.operation) = {
      metadata: "CreateApiTokenMetadata"
      response: "CreateApiTokenResponse"
    };
    // Handler enforces self-or-admin (cannot express as single scope-extractor
    // because subject_type+subject_id is polymorphic). Gateway exempts; iam
    // handler is authoritative.
    option (kacho.iam.authz.v1.permission) = "<exempt>";
  }

  // List own tokens (or admin can list subject's tokens).
  rpc List (ListApiTokensRequest) returns (ListApiTokensResponse) {
    option (google.api.http) = { get: "/iam/v1/apiTokens" };
    option (kacho.iam.authz.v1.permission) = "<exempt>";
  }

  // Get returns a single token row (without hash, without plaintext).
  rpc Get (GetApiTokenRequest) returns (ApiToken) {
    option (google.api.http) = { get: "/iam/v1/apiTokens/{api_token_id}" };
    option (kacho.iam.authz.v1.permission) = "<exempt>";
  }

  // Delete soft-revokes; idempotent — re-revoke returns NotFound (CAS 0-rows).
  rpc Delete (DeleteApiTokenRequest) returns (operation.Operation) {
    option (google.api.http) = { delete: "/iam/v1/apiTokens/{api_token_id}" };
    option (kacho.cloud.api.operation) = {
      metadata: "DeleteApiTokenMetadata"
      response: "DeleteApiTokenResponse"
    };
    option (kacho.iam.authz.v1.permission) = "<exempt>";
  }
}

// InternalApiTokenService — cluster-internal RPC for gateway authn
// (port 9091 only; запрет #6). Returns hash + subject + scopes so gateway
// can argon2id-verify and inject principal.
service InternalApiTokenService {
  rpc GetPrefix (GetApiTokenByPrefixRequest) returns (GetApiTokenByPrefixResponse) {
    // NOT registered on public REST mux. Internal listener gRPC only.
  }
  // TouchLastUsed — best-effort gateway sends after successful authn for
  // last_used_at column update. Returns empty on success; transient errors
  // ignored by gateway (cosmetic field).
  rpc TouchLastUsed (TouchLastUsedRequest) returns (TouchLastUsedResponse) {
  }
}

message CreateApiTokenRequest {
  string subject_type = 1 [(required) = true];      // "user" | "service_account"
  string subject_id   = 2 [(required) = true, (length) = "<=20"];
  string description  = 3 [(length) = "<=256"];
  // Lifetime in seconds; 0 → no expiry (default — see OQ-W2.C-3 — may be
  // forbidden via config).
  int64 ttl_seconds = 4 [(value) = ">=0"];
  // Catalog-permission strings (e.g. "iam.accounts.get"). Empty → InvalidArgument
  // unless `allow_zero_scope=true` (safety-by-default).
  repeated string scopes = 5 [(length) = "<=100"];
  bool allow_zero_scope = 6;
}

message CreateApiTokenResponse {
  ApiToken token = 1;   // includes `plaintext` (only here, only ONCE)
}

message CreateApiTokenMetadata {
  string api_token_id = 1;
  string subject_type = 2;
  string subject_id = 3;
}

message ListApiTokensRequest {
  string subject_type = 1;          // optional filter (default = caller's type)
  string subject_id   = 2 [(length) = "<=20"];   // optional (default = caller's id)
  bool   include_revoked = 3;
  int64  page_size       = 4 [(value) = "<=1000"];
  string page_token      = 5 [(length) = "<=100"];
}

message ListApiTokensResponse {
  repeated ApiToken tokens = 1;
  string next_page_token = 2;
}

message GetApiTokenRequest {
  string api_token_id = 1 [(required) = true, (length) = "<=20"];
}

message DeleteApiTokenRequest {
  string api_token_id = 1 [(required) = true, (length) = "<=20"];
}

message DeleteApiTokenResponse {
  string api_token_id = 1;
  google.protobuf.Timestamp revoked_at = 2;
}

message DeleteApiTokenMetadata {
  string api_token_id = 1;
}

// Internal lookup (gateway authn use only).
message GetApiTokenByPrefixRequest {
  string prefix = 1 [(required) = true, (length) = "==11"];
}

message GetApiTokenByPrefixResponse {
  string id = 1;
  string hash = 2;                  // argon2id PHC — gateway runs Verify
  string subject_type = 3;
  string subject_id = 4;
  repeated string scopes = 5;
  google.protobuf.Timestamp expires_at = 6;
  google.protobuf.Timestamp revoked_at = 7;
}

message TouchLastUsedRequest {
  string api_token_id = 1 [(required) = true];
  google.protobuf.Timestamp at = 2;
}

message TouchLastUsedResponse {}
```

### 4.3 Usecase — `internal/apps/kacho/api/api_token/usecases.go` (Create) — pseudo-code

```
// Create
  validate(req)                            // subject_type, scopes-non-empty unless allow_zero_scope
  authority := authzguard.PrincipalUserID(ctx)
  if authority == "" → PermissionDenied
  // Authority: self OR account-admin on subject's account
  if !IsSelf(ctx, req.subject_id):
      require requireGrantAuthority(ctx, repo, "account", lookupSubjectAccountID(req.subject_id))
  // Generate token
  plaintext, prefix, hashStr := generateToken()        // crypto/rand + argon2id
  id := domain.NewKac127ID("kat")
  op := operations.NewFromContext(ctx, "kat", "Create API token", &iamv1.CreateApiTokenMetadata{...})
  opsRepo.Create(op)
  operations.Run(ctx, opsRepo, op.ID, func(ctx) (*anypb.Any, error):
      // Retry on 23505 prefix collision (cryptographically rare; 3 attempts).
      for attempt := 1..maxCreateRetries:
          tok, err := repo.Insert(ctx, tx, domain.ApiToken{...with prefix/hash/...})
          if err is unique_violation (23505) on prefix → regenerate plaintext/prefix/hash, retry
          else → break
      if err → mapPGErr(err)
      resp := &iamv1.CreateApiTokenResponse{
          Token: apiTokenToProto(persisted, /*includePlaintext=*/true, plaintext),
      }
      // W1.6 #11 redaction — schedule
      go scheduleTokenRedact(op.ID)
      return anypb.New(resp), nil
  )
  return op

// scheduleTokenRedact — mirror sa_keys/usecases.go::scheduleSecretRedact:
//   poll opsRepo.Get(opID) until Done == true (max 100x at 20ms = 2s),
//   then opsRepo.RedactResponseField(opID, []string{"token","plaintext"}, `"<redacted>"`).
```

### 4.4 Usecase — Delete / List / Get — pseudo-code

```
// Delete
  authority := authzguard.PrincipalUserID(ctx)
  if authority == "" → PermissionDenied
  tok, err := repo.Get(ctx, id)
  if err is NotFound → NotFound
  // Self OR account-admin on subject's account
  if !IsSelf(ctx, tok.SubjectID):
      require requireGrantAuthority(ctx, repo, "account", lookupSubjectAccountID(tok.SubjectID))
  op := operations.NewFromContext(...)
  opsRepo.Create(op)
  operations.Run(ctx, opsRepo, op.ID, func(ctx) (*anypb.Any, error):
      // Atomic CAS — idempotent re-revoke detected via 0 rows
      revoked, err := repo.RevokeCAS(ctx, tx, id)
      if err is NotFound → return nil, ErrNotFound  // (idempotent on already-revoked)
      // Emit subject_change_outbox for gateway cache invalidation
      err = repo.EmitSubjectChangeEvent(ctx, tx, SubjectChangeEvent{
          SubjectID:   tok.Prefix,           // KEY by prefix (gateway cache key)
          Op:          "api_token_revoke",
          EventType:   "api_token_revoke",
          Payload:     {"token_id": tok.ID, "subject_type": tok.SubjectType},
      })
      tx.Commit()
      return anypb.New(&iamv1.DeleteApiTokenResponse{ApiTokenId: id, RevokedAt: ...})
  )
  return op

// List
  authority := authzguard.PrincipalUserID(ctx)
  if authority == "" → PermissionDenied
  // Default: list own tokens.
  if req.SubjectID == "" or IsSelf(ctx, req.SubjectID):
      filter = (caller.Type, caller.ID, includeRevoked)
  else:
      // Admin: requires admin on subject's account
      require requireGrantAuthority(ctx, repo, "account", lookupSubjectAccountID(req.SubjectID))
      filter = (req.SubjectType, req.SubjectID, includeRevoked)
  rows, next := repo.List(ctx, filter, pageSize, pageToken)
  resp := mapEach(rows, apiTokenToProto(...with includePlaintext=false, "")) // strip hash + plaintext
  return resp

// Get
  authority := authzguard.PrincipalUserID(ctx)
  if authority == "" → PermissionDenied
  tok := repo.Get(ctx, id)
  if !IsSelf(ctx, tok.SubjectID):
      require requireGrantAuthority(ctx, repo, "account", lookupSubjectAccountID(tok.SubjectID))
  return apiTokenToProto(tok, includePlaintext=false, "")   // hash/plaintext stripped
```

### 4.5 Gateway middleware — `auth.go` extension — pseudo-code

```
// inside authorize(ctx, fullMethod) — BEFORE the existing JWT path
bearer := extractBearer(ctx)
if bearer == "":
    ... existing behaviour (anonymous in dev / 401 in production-strict)
else if strings.HasPrefix(bearer, "kat_"):
    return apiTokenAuthn(ctx, bearer, fullMethod)
else:
    ... existing JWT validate path

// apiTokenAuthn(ctx, bearer, fullMethod) (context.Context, error):
    if len(bearer) != 28 or not regex `^kat_[a-z2-7]{24}$`:
        return Unauthenticated("malformed API token")     // 401, no info leak
    prefix := bearer[:11]
    // Cache lookup
    if cached := cache.Get(prefix); cached.Valid && cached.NotExpired:
        record := cached
    else:
        resp, err := internalApiTokenClient.GetPrefix(ctx, prefix)
        if err is NotFound:
            return Unauthenticated("token invalid")        // 401
        if err is Unavailable AND mode == production:
            return Unavailable("token lookup failed")      // 503 — fail-closed (W1.3)
        cache.Put(prefix, resp, TTL=60s)
        record = resp
    if record.RevokedAt != nil:
        return Unauthenticated("token revoked")            // 401
    if record.ExpiresAt != nil && now > record.ExpiresAt:
        return Unauthenticated("token expired")            // 401
    if !argon2id.Verify(bearer, record.Hash):              // constant-time
        return Unauthenticated("token invalid")            // 401 — same wording as not-found
    // Inject Principal + token-scope into ctx
    ctx = injectPrincipal(ctx, record.SubjectType, record.SubjectID, /*displayName=*/record.SubjectID)
    ctx = injectTokenScopes(ctx, record.Scopes, record.ID)
    // Best-effort touch last_used_at (fire-and-forget; bounded ctx 2s)
    go internalApiTokenClient.TouchLastUsed(...)
    return ctx, nil

// injectTokenScopes — sets metadata "x-kacho-token-scopes" + "x-kacho-token-id".
// W1.4 principal propagation also propagates these to backend.
```

### 4.6 Gateway middleware — `authz.go` scope-gate — pseudo-code

```
// inside per-RPC authz middleware, AFTER auth-resolved principal:
scopes, ok := tokenScopesFromCtx(ctx)
if ok:
    // Token-bound request → scope subset rule (least-privilege)
    perm := lookupCatalogPermission(fullMethod)  // existing W2.A unified catalog
    if perm == "":
        // RPC has no catalog mapping → fail-closed (W1.3)
        return PermissionDenied("RPC %s has no permission mapping", fullMethod)
    if !containsAny(scopes, perm, perm-wildcard-broader-match):
        log("authz_token_scope_denied", method=fullMethod, perm=perm)
        return PermissionDenied("token scope does not permit %s (perm=%s)", fullMethod, perm)
    // continue to existing principal-side FGA Check (intersection enforcement)
... existing flow ...
```

### 4.7 Gateway cache — `api_token_cache.go` (NEW) + integration with W1.2 drainer

```
type apiTokenCache struct {
    lru *lru.Cache[string, cachedToken]    // capacity 4096; eviction LRU
    mu  sync.RWMutex
    ttl time.Duration                       // 60s default (configurable)
    now func() time.Time
}

type cachedToken struct {
    expiresAt time.Time   // cache expiry, not token expiry
    rec       GetApiTokenByPrefixResponse
}

func (c *apiTokenCache) Get(prefix string) (cachedToken, bool):
    rec, ok := lru.Get(prefix)
    if !ok || c.now().After(rec.expiresAt): return zero, false
    return rec, true

func (c *apiTokenCache) Put(prefix string, rec GetApiTokenByPrefixResponse):
    lru.Add(prefix, cachedToken{c.now().Add(c.ttl), rec})

func (c *apiTokenCache) Invalidate(prefix string):
    lru.Remove(prefix)

// Integration with W1.2 drainer (kacho-api-gateway side):
// The existing subject_change_outbox drainer (W1.2 §4.5) routes events by
// event_type. Extend the dispatcher:
//   case "api_token_revoke":
//       apiTokenCache.Invalidate(evt.SubjectID)  // SubjectID == token.prefix here
//   case "binding_revoke", "binding_grant", ... existing W1.2 cases
```

### 4.8 Audit — AuditLogger port (no-op default, B.9 wires real adapter)

```
// internal/apps/kacho/api/api_token/audit.go (or wired in cmd/main.go)
type AuditLogger interface {
    LogTokenUse(ctx context.Context, evt TokenUseEvent)
}
type TokenUseEvent struct {
    TokenID, SubjectType, SubjectID, RPCFullMethod, SourceIP string
    At time.Time
}

// nopAuditLogger satisfies the port when B.9 is not yet merged.
type nopAuditLogger struct{}
func (nopAuditLogger) LogTokenUse(_ context.Context, _ TokenUseEvent) {}

// Gateway calls AuditLogger.LogTokenUse on successful api-token authn (right
// after argon2id verify, before injecting Principal). This is on the request
// hot path — keep cheap (single struct{} → channel send in real impl; B.9
// vector.dev consumes from VictoriaLogs file sink).
```

---

## 5. Test discipline (запрет #12) — RED first

PR обязан содержать **в указанном порядке**:

1. **RED phase commit** (test-only): all §6 integration tests + §6.5 newman cases written and
   committed BEFORE any production code (proto/migration/usecase/handler/gateway). CI red on this
   commit (compile-fail for missing proto + runtime fail for missing tables / unimplemented RPCs).
2. **GREEN phase commits** (logical, per-feature-fragment):
   - 2.1 proto + regen — RED proto-compile fixed → GREEN compile
   - 2.2 migration — RED missing-table tests fixed → GREEN insert/select works
   - 2.3 domain + repo (Reader/Writer + pg impl + repomock + integration tests) — RED repo tests
     fixed → GREEN
   - 2.4 usecase Create + redaction — RED usecase tests fixed → GREEN
   - 2.5 usecase Delete (CAS + outbox emit) + concurrent re-revoke race test — RED → GREEN
   - 2.6 usecase List + Get + handler-side authority check — RED → GREEN
   - 2.7 gateway middleware extension + cache + scope-gate — RED gateway integration tests fixed
     → GREEN
   - 2.8 audit-logger port + no-op wiring — RED audit-emit test (verifies LogTokenUse called)
     → GREEN
3. **Newman cases** added to `project/kacho-iam/tests/newman/cases/iam-api-token.py` (NEW); plus
   negative cases extended in `authz-deny.py` (anonymous Create/List rejected); regenerate via
   `gen.py`; verify `run.sh` includes new suite; verify coverage gate (W0.1) still 100%.
4. **Per-finding RED→GREEN evidence** in PR description: for each §6 scenario, show test name +
   before-output (RED) + after-output (GREEN).
5. **Concurrent re-revoke race test obligatory** (§6.6 EDGE-2): goroutines × 8 calling Delete on
   same token; assert exactly one ALLOW, 7× NotFound; FGA / subject_change_outbox emit happens
   exactly once.
6. **Prefix collision retry test obligatory** (§6.6 EDGE-1): inject deterministic plaintext
   generator returning duplicate prefix N times then unique; assert Create succeeds at attempt N+1
   without retry-exhaustion.
7. **Subject-delete cascade test obligatory** (§6.6 EDGE-3): create user with 3 active tokens,
   DELETE user, assert all 3 tokens revoked_at set, 3 subject_change_outbox rows emitted with
   event_type=api_token_revoke.

---

## 6. Сценарии (Given-When-Then) — основа интеграционных тестов

> All scenarios use Postgres testcontainer (kacho-iam migrations 0001-0026 applied) + bufconn
> gRPC server with `AntiAnonymousUnary` interceptor (W1.6 #43) + `InternalApiTokenService` server
> mounted on internal gRPC mux + fake api-gateway middleware client (NewTestGateway helper).

### 6.1 POSITIVE — Create returns plaintext once; token authn allows in-scope RPC

#### Scenario W2.C-CREATE-HAPPY — basic Create returns kat_ plaintext

**ID**: W2.C-CREATE-HAPPY

**Given** authenticated principal `usr_alice` (member of account `acc_a`)
**And** scope catalog has permission `iam.accounts.get` mapped to RPC
       `/kacho.cloud.iam.v1.AccountService/Get`

**When** `usr_alice` calls `ApiTokenService.Create(subject_type="user",
       subject_id="usr_alice", scopes=["iam.accounts.get"], ttl_seconds=3600,
       description="test")`

**Then** returns `Operation` with `done=false` initially
**And** within 100ms the Operation completes (`done=true`)
**And** `Operation.response.token.plaintext` matches regex `^kat_[a-z2-7]{24}$`
**And** `Operation.response.token.id` matches regex `^kat[a-zA-Z0-9]{17}$`
**And** `Operation.response.token.prefix` equals `plaintext[:11]`
**And** DB row exists in `api_tokens` with `revoked_at IS NULL`,
       `hash LIKE 'argon2id$%'`, `subject_id='usr_alice'`,
       `scopes={'iam.accounts.get'}`, `created_by_user_id='usr_alice'`

---

#### Scenario W2.C-CREATE-REDACT — plaintext redacted post-first-return

**ID**: W2.C-CREATE-REDACT (parity with W1.6-11-REDACT)

**Given** `usr_alice` just called `Create` → returned op_id with plaintext

**When** `usr_alice` calls `OperationService.Get(op_id)` immediately (first read)

**Then** response contains `token.plaintext = "kat_<original 24 chars>"` (still readable on
       Operation envelope from worker's MarkDone)

**When** between 20ms and 2s elapses (redact goroutine completes)
**And** `usr_alice` calls `OperationService.Get(op_id)` AGAIN

**Then** response contains `token.plaintext = "<redacted>"`
**And** anonymous call to `OperationService.Get(op_id)` returns `NotFound` (W1.6 #9 carry-over)

---

#### Scenario W2.C-AUTHN-HAPPY — token authn injects principal + scope, allows in-scope RPC

**ID**: W2.C-AUTHN-HAPPY

**Given** active token `tok_1` with `subject="usr_alice"`,
       `scopes=["iam.accounts.get"]`, `expires_at = now+1h`
**And** an Account `acc_a` exists with viewer-binding for `usr_alice`

**When** API request `GET /iam/v1/accounts/acc_a` with header
       `Authorization: Bearer kat_<plaintext>`

**Then** gateway extracts prefix → `InternalApiTokenService.GetPrefix(prefix)` returns hash etc.
**And** argon2id Verify succeeds
**And** ctx has Principal{Type:"user", ID:"usr_alice"} injected
**And** ctx has `x-kacho-token-scopes=["iam.accounts.get"]` metadata
**And** scope-gate passes (RPC `Account.Get` maps to `iam.accounts.get`, in scopes)
**And** principal-side FGA Check passes (viewer-binding present)
**And** response is HTTP 200 with Account `acc_a` body
**And** within 5s, DB row `api_tokens.last_used_at` updated (>= request time - 1s)

---

### 6.2 POSITIVE — List excludes revoked by default; Get redacts hash

#### Scenario W2.C-LIST-EXCLUDES-REVOKED — default List omits revoked tokens

**ID**: W2.C-LIST-EXCLUDES-REVOKED

**Given** `usr_alice` has 3 tokens: `tok_a`, `tok_b` (both active), `tok_c` (revoked yesterday)

**When** `ApiTokenService.List(subject_type="user", subject_id="usr_alice",
       include_revoked=false)`

**Then** response contains 2 tokens (`tok_a`, `tok_b`)
**And** none have `plaintext` set
**And** none have `hash` field present in proto-serialised output (field is not in proto schema)

---

#### Scenario W2.C-LIST-INCLUDES-REVOKED — include_revoked=true returns all

**ID**: W2.C-LIST-INCLUDES-REVOKED

Same setup as above; `include_revoked=true` → 3 tokens returned, `tok_c.revoked_at` non-zero.

---

#### Scenario W2.C-GET-REDACTED — Get strips hash + plaintext

**ID**: W2.C-GET-REDACTED

**Given** `usr_alice` owns `tok_a`

**When** `ApiTokenService.Get(api_token_id="tok_a")`

**Then** response has all metadata fields (id, prefix, subject_*, scopes, …)
**And** `plaintext` field is empty string
**And** proto has no `hash` field (compile-time guarantee)

---

### 6.3 POSITIVE — Revoke invalidates cache within TTL; subsequent authn fails

#### Scenario W2.C-REVOKE-TTL — pre-revoke authn allowed; post-revoke + drainer-event → 401 immediately

**ID**: W2.C-REVOKE-TTL

**Given** active token `tok_x`; gateway cache has lookup record for `tok_x.prefix` (TTL 60s,
       freshly inserted < 1s ago)
**And** `subject_change_outbox` drainer (W1.2) is running

**When** `usr_alice` calls `ApiTokenService.Delete(api_token_id="tok_x")`
**And** waits 500ms (drainer claim + RPC InvalidateSubject typical latency)

**Then** DB row `tok_x.revoked_at` is set (CAS UPDATE)
**And** `subject_change_outbox` has new row `event_type='api_token_revoke',
       subject_id=tok_x.prefix`
**And** within 1s, gateway `api_token_cache` no longer holds entry for `tok_x.prefix`
**And** subsequent `Authorization: Bearer kat_<tok_x plaintext>` → HTTP 401 "token revoked"
       (re-lookup hits DB, sees revoked_at set, returns Unauthenticated)

---

#### Scenario W2.C-REVOKE-TTL-FALLBACK — drainer-down case, cache TTL still saves us

**ID**: W2.C-REVOKE-TTL-FALLBACK

**Given** drainer goroutine stopped (simulated by killing); gateway cache has stale entry for
       `tok_y.prefix`
**And** `tok_y.revoked_at` was just set in DB

**When** request with `Bearer kat_<tok_y>` arrives within 60s

**Then** gateway returns 200 (stale cache wins — known limitation)

**When** ≥ 60s passed since cache.Put

**Then** cache expires; re-lookup hits DB; sees revoked_at; returns 401

> This scenario documents the TTL safety-net (parity with W1.2 §0 latency promise: drainer for
> sub-second consistency; TTL for HA-replica convergence within ≤ 60s here, ≤ 30s in W1.2).

---

### 6.4 NEGATIVE — Token authn rejects out-of-scope, expired, revoked, malformed

#### Scenario W2.C-AUTHN-OUT-OF-SCOPE — token authn allows in-scope; rejects out-of-scope (403)

**ID**: W2.C-AUTHN-OUT-OF-SCOPE

**Given** active token `tok_2` with `subject="usr_alice"`,
       `scopes=["iam.accounts.get"]` (does NOT include `iam.accounts.update`)

**When** `PATCH /iam/v1/accounts/acc_a` with `Bearer kat_<tok_2 plaintext>` and a valid
       update_mask payload

**Then** gateway authn succeeds (token valid + matches subject)
**And** scope-gate denies: RPC `Account.Update` maps to `iam.accounts.update`, NOT in scopes
**And** response is HTTP 403 Forbidden with body referencing `iam.accounts.update`

> **Note**: this is 403 (PermissionDenied), NOT 401 — the token is valid, the request is just
> outside its scope. Authn succeeded, authz denied.

---

#### Scenario W2.C-AUTHN-EXPIRED — expired token → 401 "token expired"

**ID**: W2.C-AUTHN-EXPIRED

**Given** token `tok_3` with `expires_at = now - 1s` (just-expired)

**When** request with `Bearer kat_<tok_3 plaintext>`

**Then** gateway returns HTTP 401 with body containing `"token expired"`
**And** `WWW-Authenticate: Bearer error="invalid_token", error_description="token expired"`

---

#### Scenario W2.C-AUTHN-REVOKED — revoked token → 401 "token revoked"

**ID**: W2.C-AUTHN-REVOKED

**Given** token `tok_4` was revoked (revoked_at non-null in DB; cache invalidated)

**When** request with `Bearer kat_<tok_4 plaintext>`

**Then** gateway returns HTTP 401 with body containing `"token revoked"`

---

#### Scenario W2.C-AUTHN-MALFORMED-PREFIX — random `kat_xxx` not in DB → 401 (no info leak)

**ID**: W2.C-AUTHN-MALFORMED-PREFIX

**Given** no token in DB matches presented prefix (random `kat_aaaaaaa...` 28 chars)

**When** request with `Bearer kat_<fake plaintext>`

**Then** gateway calls `InternalApiTokenService.GetPrefix(...)` → NotFound
**And** gateway returns HTTP 401 with body `"token invalid"` (same wording as failed verify)
**And** **does NOT distinguish** "unknown prefix" from "wrong hash" (anti-info-leak parity with
       W1.6 #9)

---

#### Scenario W2.C-AUTHN-MALFORMED-FORMAT — prefix bypass attempt (`kat_short`) → 401 fast-fail

**ID**: W2.C-AUTHN-MALFORMED-FORMAT

**Given** Bearer header `Bearer kat_short` (wrong length, not 28 chars)

**When** request hits gateway

**Then** gateway returns HTTP 401 with body `"malformed API token"` BEFORE any DB lookup
**And** no `InternalApiTokenService.GetPrefix` call is made (fast path)

---

#### Scenario W2.C-AUTHN-WRONG-SECRET — correct prefix, wrong plaintext → 401 (constant-time)

**ID**: W2.C-AUTHN-WRONG-SECRET

**Given** active token `tok_5`, prefix `kat_abcdefg`, plaintext known
**And** attacker presents `Bearer kat_abcdefg<wrong 17 chars>`

**When** gateway processes

**Then** prefix-lookup returns hash record; argon2id Verify returns false (constant-time)
**And** gateway returns HTTP 401 with body `"token invalid"`
**And** verify duration is within ±20% of correct-secret verify duration (timing-attack guard
       via subtle.ConstantTimeCompare; mean of 10 runs)

---

### 6.5 NEGATIVE — Create/Delete authority + identity-spoofing fixes

#### Scenario W2.C-CREATE-SPOOF-DENY — caller cannot Create token for someone else (non-admin)

**ID**: W2.C-CREATE-SPOOF-DENY (parity with W1.6 #53 spoof-deny)

**Given** principal `usr_alice` (NOT admin of `usr_bob`'s account)

**When** `usr_alice` calls `Create(subject_type="user", subject_id="usr_bob", scopes=[...])`

**Then** returns `codes.PermissionDenied`
**And** NO row inserted into `api_tokens`

---

#### Scenario W2.C-CREATE-ADMIN-ALLOW — account-admin can Create token for any user in account

**ID**: W2.C-CREATE-ADMIN-ALLOW

**Given** `usr_corp_admin` has FGA admin-relation on `account:acc_corp`
**And** `usr_bob` is member of `acc_corp`

**When** `usr_corp_admin` calls `Create(subject_type="user", subject_id="usr_bob", scopes=[...])`

**Then** Operation succeeds; token row has `subject_id="usr_bob"`,
       `created_by_user_id="usr_corp_admin"` (audit field — admin attribution)

---

#### Scenario W2.C-CREATE-ANON-DENY — anonymous cannot Create

**ID**: W2.C-CREATE-ANON-DENY

**Given** ctx anonymous

**When** `Create(...)` called

**Then** `AntiAnonymousUnary` interceptor (W1.6 #43) returns `codes.PermissionDenied` BEFORE
       handler reached

---

#### Scenario W2.C-CREATE-EMPTY-SCOPE-DENY — empty scopes rejected (safety-by-default)

**ID**: W2.C-CREATE-EMPTY-SCOPE-DENY

**Given** principal `usr_alice`

**When** `Create(subject_type="user", subject_id="usr_alice", scopes=[])`

**Then** `codes.InvalidArgument` with body `"scopes required (or set allow_zero_scope=true)"`

---

#### Scenario W2.C-CREATE-ALLOW-ZERO-SCOPE — explicit empty-scope opt-in allowed

**ID**: W2.C-CREATE-ALLOW-ZERO-SCOPE

**Given** principal `usr_alice`

**When** `Create(..., scopes=[], allow_zero_scope=true)`

**Then** Operation succeeds; token created with empty scopes (will deny every RPC except those
       in gateway public-allowlist)

---

#### Scenario W2.C-DELETE-STRANGER-DENY — stranger cannot Delete another user's token

**ID**: W2.C-DELETE-STRANGER-DENY (parity W1.6 #13)

**Given** `tok_z` owned by `usr_alice`
**And** principal `usr_random` (not self, not account-admin)

**When** `Delete(api_token_id="tok_z")`

**Then** `codes.PermissionDenied`
**And** DB row `tok_z.revoked_at` remains NULL

---

#### Scenario W2.C-DELETE-ANON-DENY — anonymous cannot Delete

**ID**: W2.C-DELETE-ANON-DENY

`AntiAnonymousUnary` denies (W1.6 #43).

---

#### Scenario W2.C-LIST-FOREIGN-DENY — caller cannot list other user's tokens

**ID**: W2.C-LIST-FOREIGN-DENY (parity W1.6 #12)

**Given** `usr_alice` owns tokens; principal `usr_bob` (not admin)

**When** `List(subject_type="user", subject_id="usr_alice", ...)`

**Then** `codes.PermissionDenied`

---

#### Scenario W2.C-GET-FOREIGN-DENY — caller cannot Get another user's token

**ID**: W2.C-GET-FOREIGN-DENY

Symmetric to LIST-FOREIGN-DENY.

---

### 6.6 EDGE cases

#### Scenario W2.C-EDGE-PREFIX-COLLISION — Create retries on 23505 collision

**ID**: W2.C-EDGE-PREFIX-COLLISION (closes EDGE-1)

**Given** deterministic plaintext generator (test seam) that yields:
  - attempt 1: `kat_aaaaaaaXXXXXXXXXXXXXXXX` (prefix `kat_aaaaaaa` — colliding)
  - attempt 2: same as 1 (still colliding — partial UNIQUE blocks)
  - attempt 3: `kat_zzzzzzzYYYYYYYYYYYYYYYY` (prefix `kat_zzzzzzz` — unique)
**And** a row already exists with active prefix `kat_aaaaaaa`

**When** `Create(...)` called

**Then** internal repo.Insert returns 23505 on attempts 1 and 2; succeeds on attempt 3
**And** Operation completes with token having prefix `kat_zzzzzzz`
**And** integration log shows 2 collision retries
**And** with `maxCreateRetries=3` if attempt 3 also collided → returns
       `codes.AlreadyExists` "prefix collision after N attempts" (highly improbable; tested via
       generator returning collisions × 4)

---

#### Scenario W2.C-EDGE-CONCURRENT-REVOKE — N goroutines Delete same token; CAS ensures one wins

**ID**: W2.C-EDGE-CONCURRENT-REVOKE (closes EDGE-2; parity W1.5 / запрет #10)

**Given** active token `tok_race`
**And** 8 goroutines all call `Delete(api_token_id="tok_race")` concurrently

**When** all goroutines run

**Then** exactly **1** goroutine sees a successful Operation with `revoked_at` set
**And** **7** goroutines receive `codes.NotFound` (CAS 0-rows; idempotent re-revoke semantics)
**And** **exactly 1** row in `subject_change_outbox` with
       `event_type='api_token_revoke', subject_id=tok_race.prefix` (no duplicate events)

---

#### Scenario W2.C-EDGE-SUBJECT-DELETE-CASCADE — subject delete revokes all owned tokens + emits events

**ID**: W2.C-EDGE-SUBJECT-DELETE-CASCADE (closes EDGE-3)

**Given** `usr_to_delete` has 3 active tokens `tok_p, tok_q, tok_r`

**When** `usr_to_delete` is DELETEd from `users` (via `UserService.Delete` or direct SQL)

**Then** all 3 tokens have `revoked_at` set (`AFTER DELETE` trigger fires)
**And** 3 new rows in `subject_change_outbox` with
       `event_type='api_token_revoke', subject_id IN (tok_p.prefix, tok_q.prefix, tok_r.prefix)`
**And** payload includes `cascade_from='subject_delete'` for audit traceability
**And** gateway cache invalidates all 3 prefixes within drainer-cycle latency (sub-second)

---

#### Scenario W2.C-EDGE-DANGLING-SUBJECT-REJECTED — Create with non-existent subject_id → 23503 → InvalidArgument

**ID**: W2.C-EDGE-DANGLING-SUBJECT-REJECTED

**Given** no user with `id="usr_nonexistent"` exists

**When** `Create(subject_type="user", subject_id="usr_nonexistent", ...)`

**Then** repo.Insert raises 23503 (FK trigger violation) → maps to `codes.FailedPrecondition`
       (or InvalidArgument per maperr; OQ-W2.C-2)
**And** no row inserted

---

#### Scenario W2.C-EDGE-CREATE-ZERO-TTL — ttl_seconds=0 → no-expiry token

**ID**: W2.C-EDGE-CREATE-ZERO-TTL

**Given** principal `usr_alice`

**When** `Create(..., ttl_seconds=0)`

**Then** Operation succeeds; DB row `expires_at IS NULL`
**And** authn 1 year later still allows (no expiry — see OQ-W2.C-3 for config-flag default)

---

#### Scenario W2.C-EDGE-CACHE-LRU-EVICTION — cache LRU evicts under load; re-lookup works

**ID**: W2.C-EDGE-CACHE-LRU-EVICTION

**Given** cache capacity = 100; 200 distinct tokens used in rotation

**When** all 200 tokens used twice in a row

**Then** at any point, ≤ 100 entries in cache (LRU bounded)
**And** every request still authenticates correctly (re-lookup falls back to DB on cache miss)

---

### 6.7 Newman E2E (full CRUD + 6 negative)

> Suite: `iam-api-token` (NEW). Location: `project/kacho-iam/tests/newman/cases/iam-api-token.py`.
> Style: parity with `sa_keys`/`access_binding` cases (declarative `Case`/`Step` → `gen.py` →
> Postman collection).

#### Newman W2.C-NM-01 — `CREATE-HAPPY-PLAINTEXT-ONCE`

POST `/iam/v1/apiTokens` with valid body → 200 OK with Operation; poll until done; verify
`response.token.plaintext` non-empty + matches `kat_<28>`. Second poll → `plaintext="<redacted>"`.

#### Newman W2.C-NM-02 — `AUTHN-WITH-KAT-OK`

GET `/iam/v1/accounts/<own_acc>` with `Authorization: Bearer kat_<plaintext from NM-01>` → 200.

#### Newman W2.C-NM-03 — `AUTHN-OUT-OF-SCOPE-403`

PATCH `/iam/v1/accounts/<own_acc>` (update RPC out of token scopes) with same Bearer → 403.

#### Newman W2.C-NM-04 — `AUTHN-EXPIRED-401`

Create token with `ttl_seconds=1`, sleep 2s, GET account with Bearer → 401 + body
`"token expired"`.

#### Newman W2.C-NM-05 — `AUTHN-MALFORMED-401`

GET with `Bearer kat_short` → 401 + body `"malformed API token"`.

#### Newman W2.C-NM-06 — `AUTHN-WRONG-SECRET-401`

GET with `Bearer kat_<valid prefix from NM-01><wrong 17 chars>` → 401 + body `"token invalid"`.

#### Newman W2.C-NM-07 — `LIST-EXCLUDES-REVOKED`

GET `/iam/v1/apiTokens?include_revoked=false` → response excludes the NM-04 expired token if
revoked; verify `revoked_at` filter (this case Create + Delete one of the tokens, then List).

#### Newman W2.C-NM-08 — `GET-REDACTS-HASH-PLAINTEXT`

GET `/iam/v1/apiTokens/<id>` → `plaintext=""`; no `hash` field in JSON.

#### Newman W2.C-NM-09 — `DELETE-IDEMPOTENT`

DELETE same `<id>` twice → first 200 (Op done); second 404 NotFound.

#### Newman W2.C-NM-10 — `DELETE-STRANGER-DENY`

INV (user B) DELETE `<userA's token id>` → 403.

#### Newman W2.C-NM-11 — `LIST-FOREIGN-DENY`

INV (user B) GET `/iam/v1/apiTokens?subject_id=<userA>` → 403.

#### Newman W2.C-NM-12 — `CREATE-ANON-DENY`

Anonymous POST `/iam/v1/apiTokens` → 403 (or 401 in strict mode; verify both modes covered by
suite split).

#### Newman W2.C-NM-13 — `REVOKE-INVALIDATES-CACHE`

Sequence: NM-01 Create → NM-02 authn-OK; then DELETE token → sleep 2s (drainer + RPC time);
then authn → 401 "token revoked". Verify within 5s end-to-end.

#### Newman W2.C-NM-14 — `AUDIT-EMIT` (only when B.9 merged; conditional)

If `KACHO_AUDIT_ENABLED=true`: AAA uses token → check VictoriaLogs query
`{event_type="api_token.use", token_id="<id>"}` returns 1 row within 5s. If B.9 not merged →
test skipped with explicit `pytest.skip("B.9 audit pipeline not yet merged")`.

> **DoD**: post-merge `iam-api-token` suite: 13 cases GREEN (14 if B.9 merged). Total newman
> baseline: 1144 → 1144 + 13 = 1157 cases (or 1158 with B.9). Coverage gate (W0.1) still 100%
> across all suites.

---

## 7. Definition of Done

- [ ] `acceptance-reviewer` ✅ APPROVED данного doc; all OQs (§9) resolved
- [ ] Branch `KAC-W2C` создан в `kacho-proto`, `kacho-iam`, `kacho-api-gateway`
- [ ] **RED phase commit** in each repo: §6 integration tests + §6.7 newman cases committed
      first, CI red — RED evidence in PR description per fragment
- [ ] **GREEN phase commits** (§5 ordered):
  - [ ] proto messages + services + buf lint + buf breaking (vs main) clean
  - [ ] gen/ regenerated and committed
  - [ ] migration 0026 applied via testcontainers + idempotent re-apply test
  - [ ] domain (newtypes + Validate) + repo (Reader/Writer + pg + repomock) + integration tests
        GREEN (FK trigger + partial UNIQUE + CAS revoke + cascade trigger)
  - [ ] usecase Create + redaction (parity W1.6 #11) + collision-retry — GREEN
  - [ ] usecase Delete (CAS + outbox emit) + concurrent-revoke race test — GREEN
  - [ ] usecase List + Get + handler authority (self-or-admin) — GREEN
  - [ ] gateway middleware Bearer kat_ branch + cache + scope-gate — GREEN
  - [ ] subject_change_outbox drainer handles `api_token_revoke` event_type — GREEN
  - [ ] AuditLogger port + no-op default + Audit-emit integration test — GREEN
  - [ ] Newman suite `iam-api-token` (13 cases) GREEN; coverage gate 100%
- [ ] kacho-iam CI green (unit + integration + race + lint + gosec + govulncheck)
- [ ] kacho-api-gateway CI green (same suite)
- [ ] kacho-proto CI green (buf lint + breaking + gen committed)
- [ ] `make e2e` smoke on dev-kind:
  - [ ] Create token → use it → GET own account (200)
  - [ ] Use token for out-of-scope RPC → 403
  - [ ] Delete token → use it 2s later → 401 "token revoked"
  - [ ] Anonymous Create → 403
- [ ] PRs merged in order: kacho-proto → kacho-iam → kacho-api-gateway (per
      workspace CLAUDE.md §Кросс-репо зависимости)
- [ ] Vault обновлён:
  - [ ] `obsidian/kacho/KAC/KAC-W2C.md` — trail + PRs + acceptance checklist
  - [ ] NEW `obsidian/kacho/resources/iam-api-token.md` — fields, lifecycle, FK contract,
        prefix-format, redaction note, cascade trigger, partial UNIQUE
  - [ ] NEW `obsidian/kacho/rpc/iam-api-token-service.md` — RPC table (Create/List/Get/Delete +
        InternalApiTokenService.GetPrefix/TouchLastUsed), REST mapping, sync/async, authority rule
  - [ ] NEW `obsidian/kacho/packages/iam-apps-api-token.md` — exported types, port-interfaces,
        wiring location
  - [ ] UPDATE `obsidian/kacho/packages/apigw-middleware.md` — Bearer `kat_` branch + cache
  - [ ] UPDATE `obsidian/kacho/edges/iam-to-apigw-cache-invalidation.md` — new `api_token_revoke`
        event_type, drainer dispatch entry
  - [ ] UPDATE `obsidian/kacho/resources/iam-user.md` + `iam-service-account.md` — `AFTER DELETE`
        trigger cascade-revokes own api_tokens
- [ ] YouTrack KAC-W2C:
  - [ ] In Progress on impl start
  - [ ] PR links commented per repo
  - [ ] Done on merge + smoke + newman 13 cases GREEN
- [ ] Wave 2 tracker `2026-05-23-iam-prod-ready-wave2-streamC.md` updated: stream C → ✅ done +
      date; master tracker `2026-05-23-iam-prod-ready-master.md` updated row "W2 stream C"
- [ ] Pre-W3 unblock signal: W3 stream needs all W2 streams done; this closes one of 4

---

## 8. Decisions taken (within this acceptance)

| ID | Decision | Source / rationale |
|---|---|---|
| **D-W2.C-1** | OQ-2 from master plan → **least-privilege subset** (F.5(b)): token effective permissions = `subject_rights ∩ token_scopes`. Reasoning: spec-policy alignment with OWASP API security top-10 (broken object-level + function-level authorization). | master plan §Open decisions OQ-2 |
| **D-W2.C-2** | Hash algorithm: **argon2id** (not bcrypt / scrypt / pbkdf2). Reason: (a) memory-hard → harder offline GPU attack; (b) PHC-format string self-describes parameters → allows future cost-tuning without DB migration; (c) FIPS-irrelevant for current kachō scope; (d) `golang.org/x/crypto/argon2` is well-maintained stdlib-adjacent. Default params: t=1, m=64MiB, p=4, keyLen=32, saltLen=16. | argon2id verify timing on dev: ~5ms per call → cache TTL=60s amortises ≈1 verify per 6000 reqs/min/token. |
| **D-W2.C-3** | Prefix length = **11 chars** (`kat_` + 7 base32 = 11). Rationale: 7 chars base32 ≈ 35 bits → 1/2^35 ≈ 3e-11 chance of collision per pair. Partial UNIQUE catches the rare event. Storage: 11 bytes per row vs 4 bytes (`kat_`) is negligible; selectivity 7 chars >> 4 chars makes index lookup O(1) effectively. | Industry parity: GitHub `ghp_…` first 7 chars = same selectivity. |
| **D-W2.C-4** | Plaintext token length = **24 base32 chars** after prefix. Rationale: 24 * 5 = 120 bits of entropy from random source. Total token = 28 chars. | Crypto: 120 bits >> 80-bit security margin recommended by NIST SP 800-131A. |
| **D-W2.C-5** | Subject delete → **DB-trigger cascade** (not app-worker). Rationale: запрет #10 — within-iam-DB FK invariant; trigger ensures atomicity AND outbox-emit in single tx; no risk of "user deleted but tokens forgotten". | parity with kacho_iam group_members_member_exists_trg pattern. |
| **D-W2.C-6** | Cache TTL = **60s** (LRU 4096). Rationale: matches W1.2 cache layer pattern; 60s acceptable bounded staleness for revoke (and W1.2 drainer brings sub-second invalidation on best-case). Production-tunable via env. | parity W1.2 §0 promise (sub-second best-case, ≤60s worst-case). |
| **D-W2.C-7** | Bearer-prefix `kat_` is **lowercase** (not `KAT_`); base32 chars are **lowercase** (`a-z2-7` — RFC 4648 base32hex-ish, lowercase). Rationale: case-insensitive comparison is error-prone; lowercase reduces footgun. | Industry parity (`ghp_`, `pat_`, `sk-`). |
| **D-W2.C-8** | `created_by_user_id` is **server-stamped from principal** (not from request body). Parity with W1.6 #53 (sa_keys spoof-fix). | запрет #11 + W1.6 anti-spoof rule extension. |
| **D-W2.C-9** | Scope validation on Create: **non-empty unless `allow_zero_scope=true`** (safety-by-default; secure-default). Token with zero scope is legitimately useful for "identity-only" use cases (federation bootstrap) but should be opt-in. | OWASP secure-default principle. |
| **D-W2.C-10** | Internal lookup RPC = `InternalApiTokenService.GetPrefix` (not extension of `InternalIAMService`). Rationale: keep per-resource Internal services per kacho convention (parity `InternalUserService`, `InternalAuthzCacheService`); avoids `InternalIAMService` god-object growth. | CLAUDE.md §Принцип переиспользования (single-purpose ports). |

---

## 9. Open questions (DECISION-NEEDED) — resolve before impl-start

| ID | Question | Author recommendation |
|---|---|---|
| **OQ-W2.C-1** | Scope grammar: token scope strings reference **catalog permissions** (`iam.accounts.get`) or **gRPC FullMethod** (`/kacho.cloud.iam.v1.AccountService/Get`)? | **Catalog permissions** (`iam.accounts.get`). Rationale: (a) human-readable; (b) version-resilient (RPC FullMethod changes with proto refactor; permission string is stable); (c) reuses W2.A unified catalog (Chunk 3). Gateway scope-gate resolves FullMethod → permission via existing W2.A catalog lookup, then matches against scopes. Fail-closed: RPC without catalog mapping → DENY. |
| **OQ-W2.C-2** | Scope grammar: wildcards permitted? E.g. `iam.accounts.*` matches all RPCs in `iam.accounts.<verb>`. | **Yes — at trailing position only** (verb-wildcard). E.g. `iam.accounts.*` valid; `iam.*.get` invalid (forbidden — resource-wildcard makes least-privilege porous). Validated in Create handler; rejection on parse-error with InvalidArgument. |
| **OQ-W2.C-3** | Token `name` field? UI may want a human-label apart from `description`. | **No separate `name` field**; `description` doubles as name. Reason: kacho convention (sa_keys also uses description-only). UI can use prefix as id, description as label. |
| **OQ-W2.C-4** | Default `ttl_seconds=0` (no expiry) — allow or forbid? | **Allow** (no expiry). Justification: long-running service-account tokens need indefinite lifetime; revoke is the kill-switch. Document `KACHO_IAM_API_TOKEN_MAX_TTL_SECONDS` env-var (default 0 = no cap; ops can set 7776000 = 90 days for stricter posture). |
| **OQ-W2.C-5** | Maximum active tokens per subject? | **Soft limit 50** (configurable via env `KACHO_IAM_API_TOKEN_MAX_PER_SUBJECT=50`); Create returns `FailedPrecondition` "token quota exhausted; revoke one to mint another" when reached. Default 50 enough for any reasonable use case; protects against runaway scripts minting tokens in a loop. |
| **OQ-W2.C-6** | argon2id params tunable via env? | **Yes** — `KACHO_IAM_ARGON2_TIME` / `MEMORY` / `THREADS` env-vars; defaults t=1, m=64MiB, p=4. Allows future cost-tuning without code change (and rotation: re-hash on next use if params changed — defer to follow-up KAC ticket). |
| **OQ-W2.C-7** | `TouchLastUsed` rate-limit: gateway sends on every successful authn (`last_used_at`) — DB-write storm risk? | **Best-effort, throttled at gateway**: only send `TouchLastUsed` if last touch >60s ago (in-memory map per gateway replica). Reduces DB-writes from N/sec to ≈1/min/token. Loss of precision acceptable (last_used_at is cosmetic). |
| **OQ-W2.C-8** | Verb-suffix `:revoke` (parity SA-keys `DELETE /iam/v1/serviceAccounts/{sa}/keys/{kid}`) vs `DELETE /iam/v1/apiTokens/{id}` (plain REST)? | **Plain DELETE** `/iam/v1/apiTokens/{id}` (resource-style, kacho convention for top-level CRUD). SA-keys use sub-resource only because they're scoped under SA; api_tokens are first-class. |
| **OQ-W2.C-9** | Audit-pipeline integration: how does AuditLogger receive events from gateway (which runs in a different process)? | **Gateway-side AuditLogger writes locally** (file sink → vector.dev tails → VictoriaLogs). Not a network RPC to iam. Reason: hot path; network audit-emit per request unacceptable latency. iam-side Create/Delete also emit audit-events to local sink; aggregation happens downstream. Default no-op when `KACHO_AUDIT_ENABLED=false`. |
| **OQ-W2.C-10** | Anti-anon allowlist (W1.6 #43) — verify suffix matching: `Create`/`Delete` (mutations) require authenticated principal ✓; `List`/`Get` matched as read-only via `List`/`Get` suffix ✓. But: `GetPrefix` (Internal) — what suffix? Internal service should be mTLS-gated on cluster-internal listener; do we still need anti-anon? | **Yes** — internal listener defence-in-depth. `GetPrefix` suffix is `Get*` → allowlisted by W1.6 allowlist policy (read-only). Internal service additionally gated by mTLS SVID requirement; combination = double-gate. No change to W1.6 allowlist required. |
| **OQ-W2.C-11** | `subject_change_outbox.subject_id` re-purpose: schema column called `subject_id` carries a **token prefix** (`kat_<7>`) for `api_token_revoke` events. Semantically inconsistent — should we add a separate `prefix` or `cache_key` column? | **Re-use `subject_id` as opaque cache-key field**; document in §3.1 schema comment that for `api_token_revoke` event_type the column carries token prefix. Reason: avoid schema migration churn; W1.2 drainer dispatches by `event_type`, not by `subject_id` semantics. Long-term: rename `subject_id → cache_key` is a wave-3 refactor if needed. |
| **OQ-W2.C-12** | Authority for List/Get: **self-only** vs **self-or-admin**? Admin convenience (account-admin sees all tokens of own users) vs least-privilege (only owner sees own tokens). | **Self-or-admin** (parity W1.6 #12 / #13). Account-admin can list tokens of users in their account (security visibility); cannot create tokens for other users without admin-FGA (parity W2.C-CREATE-ADMIN-ALLOW). |

> **Ответы на OQ — за `acceptance-reviewer`.** Critical: OQ-W2.C-1 (scope grammar — drives gateway
> scope-gate impl), OQ-W2.C-4 (TTL=0 — drives Create validation), OQ-W2.C-5 (quota — drives
> additional pre-Create check), OQ-W2.C-9 (audit-pipeline — drives wiring). Implementation-detail:
> the rest, acceptance-reviewer can accept recommendation without re-debate.

---

## 10. Out of scope (явно — отдельные тикеты или follow-up)

| Item | Where | Why |
|---|---|---|
| Token rotation API (single-call new-then-old-revoke) | follow-up KAC-W2C-FOLLOWUP | Client can compose Create + Delete; not critical for MVP |
| Refresh tokens / refresh-grant flow | NOT in roadmap | `kat_` is non-refreshable by design |
| Per-RPC quota / per-token RPS limit | WS-7.6 (production-launch-plan) | Global rate-limit at gateway covers basic protection |
| Multi-subject tokens | NOT planned | One token = one identity (KISS) |
| Token scopes carrying ABAC conditions | depend on ConditionsService maturity | Scope = RPC allowlist string list only in MVP |
| OAuth2 introspection endpoint | NOT planned | Use `ApiTokenService.Get` for own tokens; third-party intro is Hydra flow |
| Token UI in kacho-ui | post-W2.C UX task | Backend complete first; UI iterates after |
| Federation login → kat issuance | NOT planned | Tokens come from `Create` alone |
| Token usage metrics (RED) | WS-6.1 | Add `kacho_api_token_authn_total{result=...}` post-merge |
| Catalog mapping for non-iam services (vpc, compute) | W2.A Chunk 3 (parallel stream) | scope-gate depends on unified catalog; W2.C wires the gate, W2.A populates the catalog |
| `last_used_at` precision < 60s | deferred — current 60s throttle (OQ-W2.C-7) is acceptable | Cosmetic field |
| argon2id parameter rotation (re-hash on verify if newer params set) | follow-up KAC ticket | Not required for MVP; params can rotate later |

---

## 11. Traceability — feature-fragment ↔ scenario-id ↔ source-impl ↔ test-name

| Fragment | Implementation spec ref | GWT Scenarios | Newman | Integration test name |
|---|---|---|---|---|
| Proto messages + services | §4.1 / §4.2 | (compile-time only) | — | `Test_Proto_Api_Token_BufLint`, `Test_Proto_Api_Token_BufBreaking` |
| Migration 0026 | §3.1 / §3.2 | W2.C-EDGE-PREFIX-COLLISION, W2.C-EDGE-DANGLING-SUBJECT-REJECTED, W2.C-EDGE-SUBJECT-DELETE-CASCADE | — | `Test_Migration_0026_Idempotent`, `Test_ApiTokens_PartialUniquePrefixActive`, `Test_ApiTokens_FK_Trigger_RejectsDangling`, `Test_ApiTokens_Cascade_OnSubjectDelete_RevokesTokens` |
| Usecase Create (+ collision retry + redaction) | §4.3 | W2.C-CREATE-HAPPY, W2.C-CREATE-REDACT, W2.C-EDGE-PREFIX-COLLISION, W2.C-CREATE-SPOOF-DENY, W2.C-CREATE-ADMIN-ALLOW, W2.C-CREATE-ANON-DENY, W2.C-CREATE-EMPTY-SCOPE-DENY, W2.C-CREATE-ALLOW-ZERO-SCOPE, W2.C-EDGE-CREATE-ZERO-TTL | NM-01, NM-12 | `Test_ApiToken_Create_ReturnsPlaintextOnce`, `Test_ApiToken_Create_RetriesOnPrefixCollision`, `Test_ApiToken_Create_AuthoritySelfOrAdmin`, `Test_ApiToken_Create_RedactsPlaintextPostFirstReturn` |
| Usecase Delete (CAS + outbox emit) | §4.4 | W2.C-EDGE-CONCURRENT-REVOKE, W2.C-DELETE-STRANGER-DENY, W2.C-DELETE-ANON-DENY | NM-09, NM-10 | `Test_ApiToken_Delete_CAS_IdempotentRevoke`, `Test_ApiToken_Delete_ConcurrentSingleWinner`, `Test_ApiToken_Delete_EmitsSubjectChangeEvent` |
| Usecase List / Get + handler authority | §4.4 | W2.C-LIST-EXCLUDES-REVOKED, W2.C-LIST-INCLUDES-REVOKED, W2.C-GET-REDACTED, W2.C-LIST-FOREIGN-DENY, W2.C-GET-FOREIGN-DENY | NM-07, NM-08, NM-11 | `Test_ApiToken_List_ExcludesRevokedByDefault`, `Test_ApiToken_Get_RedactsHashPlaintext`, `Test_ApiToken_List_ForeignSubjectDenied`, `Test_ApiToken_Get_ForeignSubjectDenied` |
| Gateway Bearer-kat branch + cache | §4.5 / §4.7 | W2.C-AUTHN-HAPPY, W2.C-REVOKE-TTL, W2.C-REVOKE-TTL-FALLBACK, W2.C-AUTHN-EXPIRED, W2.C-AUTHN-REVOKED, W2.C-AUTHN-MALFORMED-PREFIX, W2.C-AUTHN-MALFORMED-FORMAT, W2.C-AUTHN-WRONG-SECRET, W2.C-EDGE-CACHE-LRU-EVICTION | NM-02, NM-04, NM-05, NM-06, NM-13 | `Test_Gateway_ApiToken_AuthnHappy`, `Test_Gateway_ApiToken_AuthnExpired_401`, `Test_Gateway_ApiToken_AuthnRevoked_401_NoInfoLeak`, `Test_Gateway_ApiToken_Cache_TTL_60s`, `Test_Gateway_ApiToken_Cache_InvalidateOnRevokeEvent`, `Test_Gateway_ApiToken_LRU_Eviction` |
| Gateway scope-gate | §4.6 | W2.C-AUTHN-OUT-OF-SCOPE | NM-03 | `Test_Gateway_ApiToken_ScopeGate_DeniesOutOfScope`, `Test_Gateway_ApiToken_ScopeGate_AllowsInScope` |
| Audit (port + no-op + B.9 wiring) | §4.8 | (covered by NM-14 if B.9 merged) | NM-14 (conditional) | `Test_Gateway_ApiToken_AuditLogger_NopByDefault`, `Test_Gateway_ApiToken_AuditLogger_EmitsOnUse` |
| subject_change_outbox drainer (W1.2 reuse) | §4.7 | W2.C-REVOKE-TTL | NM-13 | `Test_Drainer_DispatchesApiTokenRevokeEvent` |

---

## 12. Ссылки

- Workspace правила: `../../CLAUDE.md` (запреты #1/#6/#10/#11/#12; vault discipline; security-sensitivity; API contract — flat resources + Operations)
- IAM-specific: `../../project/kacho-iam/CLAUDE.md`
- Master plan: `../superpowers/plans/2026-05-23-iam-prod-ready-master.md` — §Open decisions OQ-2 (least-privilege subset decision adopted as D-W2.C-1); Wave 2 stream split
- Production launch plan: `../superpowers/plans/2026-05-21-production-launch-plan.md` — WS-6.1 metrics, WS-7.6 rate limiting (referenced as out-of-scope)
- Predecessor acceptance docs:
  - `sub-phase-W1.2-subject-change-cache-invalidation-acceptance.md` — drainer pattern + cache-invalidate via subject_change_outbox + per-prefix cache pattern
  - `sub-phase-W1.3-gateway-authz-failclosed-acceptance.md` — fail-closed semantics for lookup failures
  - `sub-phase-W1.4-principal-propagation-acceptance.md` — cross-service Principal propagation (token-injected principal must propagate)
  - `sub-phase-W1.6-remediation-chunk2-in-service-authz-acceptance.md` — anti-anon allowlist (#43), Operation.Get NotFound-for-anonymous (#9), spoof-deny pattern (#53), SA-key Issue secret-once + redaction (#11) — VERBATIM replicated for api-token Create
- Reference impls / parity sources:
  - kacho-iam `internal/apps/kacho/api/sa_keys/usecases.go::scheduleSecretRedact` — secret redaction pattern (W1.6 #11)
  - kacho-iam `internal/apps/kacho/api/sa_keys/handler.go::Issue` — created_by stamping from principal (W1.6 #53)
  - kacho-iam `internal/apps/kacho/api/access_binding/delete.go` — `requireGrantAuthority` for Delete (W1.6 #13)
  - kacho-api-gateway `internal/middleware/auth.go::authorize` — Bearer extension point (W2.C inserts `kat_` branch BEFORE JWT validate)
  - kacho-iam `internal/migrations/0023_kac138_subject_change_outbox_v2.sql` — event_type column + drainer payload pattern
  - kacho-corelib `outbox/drainer` — generic Drainer[T] reused by api-token-revoke dispatch
- Vault entries to update (DoD §7):
  - `obsidian/kacho/KAC/KAC-W2C.md` (NEW)
  - `obsidian/kacho/resources/iam-api-token.md` (NEW)
  - `obsidian/kacho/rpc/iam-api-token-service.md` (NEW)
  - `obsidian/kacho/packages/iam-apps-api-token.md` (NEW)
  - `obsidian/kacho/packages/apigw-middleware.md` (UPDATE — Bearer `kat_` branch)
  - `obsidian/kacho/edges/iam-to-apigw-cache-invalidation.md` (UPDATE — `api_token_revoke` event)
  - `obsidian/kacho/resources/iam-user.md` + `iam-service-account.md` (UPDATE — cascade trigger)

---

## 13. End-state diagram (text)

```
User / SA  ─ Create ─►  ApiTokenService
                          │
                          ├─ generate kat_<28>, argon2id-hash, partial-UNIQUE-insert
                          ├─ Op.MarkDone(response.token.plaintext = kat_<28>)  ─ ONCE ─►  Client
                          └─ scheduleTokenRedact → operations.response.token = "<redacted>"

User / SA  ─ HTTP req ──────────────► api-gateway
       Bearer kat_<28>                 │
                                       ├─ Bearer.HasPrefix("kat_")? → apiTokenAuthn
                                       │     ├─ cache.Get(prefix)  ── hit ──►  use record
                                       │     └─ miss → InternalApiTokenService.GetPrefix(prefix)
                                       │           │
                                       │     ◄─────┘  {hash, subject_*, scopes, expires_at, revoked_at}
                                       │     ├─ revoked_at? expired? → 401
                                       │     ├─ argon2id.Verify(plaintext, hash) → 401 if fail
                                       │     ├─ cache.Put(prefix, record, ttl=60s)
                                       │     └─ injectPrincipal + injectTokenScopes(ctx)
                                       │
                                       ├─ authz-middleware
                                       │     ├─ if tokenScopes in ctx → scope-gate
                                       │     │     └─ catalogPerm(fullMethod) ∈ scopes? else 403
                                       │     └─ FGA Check(subject, perm, scope) → 403 if deny
                                       │
                                       └─ forward to backend (Principal propagates via W1.4)

User  ─ Delete ─►  ApiTokenService
                    │
                    ├─ authority check (self-or-admin)
                    ├─ CAS UPDATE api_tokens SET revoked_at=now() WHERE id=$id AND revoked_at IS NULL
                    │     └─ 0 rows → NotFound (idempotent)
                    └─ subject_change_outbox INSERT (event_type=api_token_revoke, subject_id=prefix)
                          │
                          └─ W1.2 Drainer LISTEN/NOTIFY  ─►  InvalidateApiTokenCache(prefix)  ─►  gateway cache eviction

User-or-SA DELETE  →  AFTER DELETE trigger
                       │
                       └─ for each active token of subject:
                            ├─ UPDATE revoked_at = now()
                            └─ INSERT subject_change_outbox (event_type=api_token_revoke, subject_id=token.prefix, payload={cascade_from='subject_delete'})
```
