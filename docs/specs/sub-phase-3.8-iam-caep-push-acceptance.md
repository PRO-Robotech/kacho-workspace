# Sub-phase 3.8 — IAM CAEP push pipeline (KAC-127 / YT KAC-129) — Acceptance

> **Status**: DRAFT — awaiting `acceptance-reviewer` APPROVED.
> **Date**: 2026-05-19
> **YouTrack**: [KAC-127](https://prorobotech.youtrack.cloud/issue/KAC-127) — production-ready next-gen IAM (vault-label `KAC-127`); Phase 8 subtask to be created.
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer` (gate per запрет #1, workspace `CLAUDE.md`).
> **Design doc**: `docs/superpowers/specs/2026-05-19-iam-prod-ready-next-gen-design.md` — Decision Log §1 (D-15 CAEP push ≤10s globally), Token shapes §5.1 (SET shape — RFC 8417 signed JWT), Validation pipeline §5.2 (`session_revocations` jti cache, 5s LISTEN-invalidated), §9 Audit/CAEP pipeline overview, §10 CAEP push pipeline production (subscriber registry, drainer, internal receiver), §13 SLOs (revoke propagation ≤10s p99), §14 Threat model (stolen refresh token, compromised account, mass data extraction — all CAEP push), §15 Migration plan (Phase 8 of 13), §17 DoD.
> **Plan doc**: `docs/superpowers/plans/2026-05-19-iam-prod-ready-next-gen-plan.md` — Phase 8 (tasks 8.1-8.6).
> **Phase position**: §16 design doc "Migration plan", **Phase 8 of 13**.
> **Predecessors (must be merged before code begin)**:
> - Phase 1 — Foundation (`sub-phase-3.1-iam-foundation-acceptance.md`): migration `0013_kac127_audit_caep_pipeline.sql` создала таблицы `caep_outbox`, `caep_subscribers`, `session_revocations`; `0014_kac127_jwks_keys.sql` создала `jwks_keys` (для SET signing key lookup); таблица `caep_subscribers` имеет CHECK `endpoint_url ~ '^https://'`, FK → `accounts(id) ON DELETE CASCADE`, `failure_count INTEGER >= 0`.
> - Phase 2 — AuthN core (`sub-phase-3.2-iam-authn-passkey-dpop-acceptance.md`): JWKS rotation, `Hydra` JWKS endpoint работает (kacho-iam использует тот же signing-key pool для SET — см. P8-D3); ID-token issuance flow живой → можно генерить session events.
> - Phase 3 — AuthZ core (`sub-phase-3.3-iam-authz-fga-conditions-opa-acceptance.md`): FGA outbox + ReBAC tuples → revoke binding генерит CAEP token-claims-change event (этим занимается Phase 3 emit, drainer — Phase 8).
> - Phase 4 — List filtering (`sub-phase-3.4-iam-list-filtering-acceptance.md`): `caep_outbox` rows читаются через `ListEvents` админ-инструментом для debugging — query pattern (account_id + event_type + status) уже выверен.
> - Phase 6 — Enterprise SSO (`sub-phase-3.6-iam-scim-saml-organization-acceptance.md`): SCIM lifecycle (`User.SUSPEND` / `User.DELETE`) emit'ит CAEP `credential-change` / `session-revoked` события — Phase 8 их драинит.
> - Phase 7 — JIT/break-glass/access-reviews/GDPR (`sub-phase-3.7-iam-jit-breakglass-reviews-gdpr-acceptance.md`): эмитят `token-claims-change` (JIT activate/expire), `session-revoked` (break-glass revoke, access review revoke, GDPR erasure cascade) — drainer'у Phase 8 надо обработать эти rows.
> **Target repos / merge order (топологическая сортировка graf'а)**:
> 1. `PRO-Robotech/kacho-proto` — `kacho.iam.v1.CaepSubscriberService` (public CRUD для admin-UI; mutating methods требуют `iam.caep_subscribers.upsert` permission), `kacho.iam.v1.CaepSubscriberService.TestDelivery` (action-method, admin tool); `kacho.iam.internal.v1.InternalCaepReceiverService` (internal-only — kacho-iam → api-gateway intra-cluster receive event); message `kacho.iam.v1.CaepSubscriber` (flat resource — id, account_id, endpoint_url, signing_kid, expected_audience, event_types[], enabled, failure_count, last_success_at, last_failure_at, last_failure_reason, created_at, created_by_user_id); messages `CreateCaepSubscriberRequest`, `UpdateCaepSubscriberRequest`, `DeleteCaepSubscriberRequest`, `GetCaepSubscriberRequest`, `ListCaepSubscribersRequest/Response`, `TestDeliveryRequest/Response`; internal `ReceiveCaepEventRequest/Response`.
> 2. `PRO-Robotech/kacho-corelib` — `corelib/set/` (новый пакет): `signer.go` (SET JWT signing — RS256/ES256, kid lookup из JWKS pool, embed events claim per RFC 8417), `verifier.go` (для unit-test consumer-side и для internal receiver `audience` validation), `set_testing.go` (in-memory key-pair для testcontainers). `corelib/caep/` (новый пакет): `event_types.go` (canonical constants для 5 event types — см. P8-D11), `payload.go` (CaepEventPayload struct + helpers `BuildSessionRevoked`, `BuildTokenClaimsChange`, ...).
> 3. `PRO-Robotech/kacho-iam` — `internal/apps/kacho/jobs/caep_drainer.go` (worker pool — `KACHO_IAM_CAEP_DRAINER_POOL_SIZE`=8 default; pick `FOR UPDATE SKIP LOCKED`; per-subscriber rate-limiter token-bucket — `KACHO_IAM_CAEP_RATE_LIMIT_PER_MIN`=100; exponential backoff schedule в `internal/apps/kacho/jobs/caep_backoff.go`); `internal/apps/kacho/api/caep_subscriber/{create,update,delete,get,list,test_delivery}.go`; `internal/domain/caep_subscriber.go` (self-validating type); `internal/repo/kacho/pg/caep_outbox_repo.go` + `caep_subscribers_repo.go`; `internal/clients/api_gateway_caep_receiver_client.go` (gRPC client → api-gateway internal receiver — used only для intra-cluster events; webhook-based events идут через HTTP); migration `0022_kac127_phase8_caep_indexes.sql` (доп. indexes для drainer scan производительности — `caep_outbox (status, next_attempt_at) WHERE status IN ('pending','in_flight')` partial index).
> 4. `PRO-Robotech/kacho-api-gateway` — `internal/caep/receiver.go` + `internal/caep/handler.go` (gRPC server для `InternalCaepReceiverService.ReceiveCaepEvent`); `internal/cache/session_revocations.go` (LRU cache с `pgx.Conn.LISTEN 'session_revoked'` подписка для cross-pod invalidation); `internal/restmux/mux.go` — регистрирует `CaepSubscriberService` (public) на public mux + `InternalCaepReceiverService` на `iamInternalAddr` блок (per запрет #6); добавляет HTTP-аутентикацию SET-Bearer для inbound webhook (только при subscriber-mode "incoming" — Phase 11; здесь api-gateway только outgoing receiver от kacho-iam).
> 5. `PRO-Robotech/kacho-ui` — `pages/iam/caep-subscribers/{SubscribersListPage,CreateSubscriberModal,SubscriberDetailPage}.tsx` (admin-UI: list per account, create form с endpoint_url HTTPS validation, detail с failure history + manual test-delivery button + enable/disable toggle).
> 6. `PRO-Robotech/kacho-test` — `tests/k6/caep_revoke_latency_kac127.js` (k6 load test — sustained 100 events/min × 10 subscribers × 30 min; SLA p95 ≤2s, p99 ≤5s webhook delivery; total revoke→cache-invalidate ≤10s); newman cases `tests/newman/cases/iam_caep_*.py`.
> 7. `PRO-Robotech/kacho-deploy` — secrets: `caep-set-signing-key` (если P8-D3 финализируется dedicated-key option — см. §3) или пинг shared Hydra signing-key (default); helm-values: `caep.drainer.{pool_size,rate_limit_per_min,max_attempts}`, `caep.receiver.cache_size`; CronJob template для drainer (kubernetes Deployment, не Job — long-lived worker); Prometheus alert rules (CAEP delivery failure rate > 5%, queue depth > 1000, p99 latency > 5s).
> 8. `PRO-Robotech/kacho-workspace` — vault: `obsidian/kacho/KAC/KAC-127.md` (Phase 8 update), `obsidian/kacho/resources/iam-caep-subscriber.md` (extended из Phase 1 stub под полный lifecycle), `obsidian/kacho/resources/iam-caep-outbox-event.md` (новый), `obsidian/kacho/resources/iam-session-revocation.md` (extended — описать LISTEN/NOTIFY contract), `obsidian/kacho/rpc/iam-caep-subscriber-service.md` (новый), `obsidian/kacho/rpc/apigw-internal-caep-receiver-service.md` (новый, internal-only-помечен), `obsidian/kacho/packages/corelib-set.md` (новый), `obsidian/kacho/packages/corelib-caep.md` (новый), `obsidian/kacho/packages/iam-jobs-caep-drainer.md` (новый), `obsidian/kacho/packages/apigw-caep-receiver.md` (новый), `obsidian/kacho/edges/iam-to-caep-subscriber-webhook.md` (новый — outbound HTTPS POST), `obsidian/kacho/edges/iam-to-apigw-internal-caep.md` (новый — intra-cluster gRPC; sync), `obsidian/kacho/edges/apigw-to-postgres-listen-session-revoked.md` (новый — LISTEN/NOTIFY cross-pod sync).

---

## 0. Преамбула — место этой sub-итерации в epic

Phase 8 — **восьмая код-генерирующая Phase** под KAC-127 и **первая phase «real-time security plane»**: до неё все revoke-флоу (admin force-block User, JIT/break-glass expire, GDPR erasure, SCIM user-disabled, FGA tuple delete) лишь **писали rows в `caep_outbox`** — теперь Phase 8 их **драинит**, **подписывает SET-токен**, **доставляет subscriber'у по HTTPS webhook**, и одновременно **посылает intra-cluster intent в api-gateway** который invalidate'ит token-jti cache на всех своих pod'ах через LISTEN/NOTIFY. Цель — **глобальная propagation revoke ≤ 10 секунд p99** (SLO §13.6).

К моменту начала Phase 8 уже есть:

- **DB-схема Phase 1**:
  - `caep_outbox` (id TEXT PK ULID, event_type TEXT, subject_id TEXT, account_id TEXT, payload JSONB, attempts INT DEFAULT 0, status TEXT CHECK IN `('pending','in_flight','delivered','failed_terminal')`, next_attempt_at TIMESTAMPTZ DEFAULT now(), created_at TIMESTAMPTZ DEFAULT now()) — events эмитят все upstream-фичи Phase 3-7.
  - `caep_subscribers` (id `cps_…` PK, account_id FK ACCOUNTS CASCADE, endpoint_url TEXT CHECK `^https://`, signing_kid TEXT, expected_audience TEXT, event_types TEXT[], enabled BOOL, failure_count INT >=0, last_success_at/last_failure_at/last_failure_reason, created_at, created_by_user_id) — реестр.
  - `session_revocations` (token_jti TEXT PK = UUIDv7, revoked_at TIMESTAMPTZ, reason TEXT, user_id TEXT, ttl_until TIMESTAMPTZ default `revoked_at + interval '30d'`) — Per design §5.2 cache на api-gateway; Phase 1 PK = `token_jti` (P1-D8).
  - `jwks_keys` (kid TEXT PK, alg TEXT, public_key TEXT, private_key_encrypted TEXT, status TEXT enum {`active`,`rotating`,`retired`}, ...) — Phase 1 заводит rotation table; Phase 8 использует key из status='active' для SET signing.
- **CAEP outbox writers**: Phase 3 (FGA-tuple-delete → token-claims-change), Phase 6 (SCIM user-disable → credential-change), Phase 7 (break-glass active/revoke → token-claims-change; JIT-activate/expire → token-claims-change; GDPR erasure cascade → session-revoked + credential-change). **Каждое из этих место уже пишет row в `caep_outbox`** — Phase 8 их сама **не генерит**, только консумит.

Phase 8 закладывает **CAEP-pipeline** во весь рост:

1. **Subscriber registry CRUD** — admin per Account регистрирует webhook endpoint: `POST /iam/v1/caepSubscribers { endpoint_url, signing_kid, expected_audience, event_types[] }`. UI — admin-page с list/create/edit/delete + test-delivery button. Все мутации требуют step-up `acr=2` (см. Phase 2) и permission `iam.caep_subscribers.upsert` на Account-level. **NIE Internal**: subscriber-registry — public-API (tenant сам управляет своими webhook'ами), но **только на собственный Account** (RBAC через OpenFGA tuple `account:<id>#admin@user:<id>`).

2. **SET signing** (`corelib/set/signer.go`) — Security Event Token по RFC 8417: signed JWT, header `{ alg: "RS256", typ: "secevent+jwt", kid: "<active-kid>" }`, claims `{ iss: "https://api.kacho.cloud", aud: subscriber.expected_audience, iat: <unix>, jti: "<uuid-v7>", events: { "<event-type-uri>": { subject: { format: "opaque", id: "<user_id>" }, ...event-specific-fields } } }`. Алгоритм — RS256 по default (FIPS 140-2 friendly); ES256 / EdDSA support через alg field в jwks_keys (P8-D4). **Private key** хранится encrypted в `jwks_keys.private_key_encrypted` (Phase 1 schema; decryption via `KMS_DATA_KEY` env, Phase 12 → HSM-backed); decrypt on hot-path в drainer, кэшируется в-памяти per `kid` (TTL 5 min).

3. **Drainer worker pool** (`internal/apps/kacho/jobs/caep_drainer.go`) — N=8 goroutine'ов (configurable). Каждая:
   - `SELECT … FOR UPDATE SKIP LOCKED LIMIT 1 WHERE status IN ('pending','in_flight') AND next_attempt_at <= now() ORDER BY next_attempt_at ASC` — берёт event;
   - `UPDATE caep_outbox SET status='in_flight', attempts = attempts + 1 WHERE id=$1` — атомарное claim;
   - Находит matching `caep_subscribers` (WHERE `account_id` matches AND `enabled=true` AND `event_type = ANY(event_types)`);
   - Per subscriber: check rate-limiter (см. P8-D6) → если deferred, `UPDATE next_attempt_at = now() + 1 minute` и continue;
   - SET sign → `POST <endpoint_url>` с `Authorization: Bearer <SET-JWT>`, `Content-Type: application/secevent+jwt`, timeout 10s;
   - 2xx → `UPDATE caep_outbox SET status='delivered', delivered_at=now()` (если single-subscriber) либо `caep_delivery_attempts` child-table row (если multi-subscriber per event — см. P8-D14);
   - 5xx / timeout / 429 → exponential backoff (P8-D5);
   - 4xx (кроме 429) → P8-D7 terminal failure.

4. **Per-subscriber rate-limit** — token-bucket на 100 events/min per subscriber (P8-D6). Защита от cascade-attack «admin удаляет 10000 users подряд → не убьём subscriber'у инфраструктуру». При over-limit drainer **не теряет** event — defer'ит `next_attempt_at += 60s`.

5. **Internal CAEP receiver** (`kacho-api-gateway/internal/caep/`) — отдельный путь параллельно webhook'ам: kacho-iam **сразу** после INSERT'a row в caep_outbox делает **synchronous gRPC-call** `InternalCaepReceiverService.ReceiveCaepEvent(event)` на api-gateway (intra-cluster, не через webhook). API-gateway:
   - `INSERT INTO session_revocations (token_jti, revoked_at, reason, user_id) VALUES ($1, now(), $2, $3) ON CONFLICT (token_jti) DO NOTHING` (idempotent);
   - `pg_notify('session_revoked', token_jti)` — все api-gateway pods подписаны на этот channel, invalidate'ят свой in-memory LRU cache (5s TTL по design §5.2);
   - возвращает `Ack { processed: true }` — kacho-iam использует это как signal что **intra-cluster effect ≤1s** достигнут. Latency budget: intra-cluster ≤1s + webhook ≤2s p95 ≤5s p99 + 4s buffer = 10s total revoke→effect.

6. **Test-delivery admin tool** — `POST /iam/v1/caepSubscribers/{id}:testDelivery` action-method генерит синтетический event (event_type=`<canonical>`, subject=`tester-synthetic-{uuid}`, claim `test=true`, JTI=fresh), подписывает SET и шлёт subscriber'у; возвращает `{ http_status, response_body_preview (first 256 bytes), latency_ms, attempts: 1 }` — UI отображает inline. Этот call **не пишет** в `caep_outbox` (это synthetic, не часть retry-loop). Per design — обязательная фича для onboarding subscriber'ов.

7. **Backoff schedule** (P8-D5) — `[1s, 5s, 30s, 5min, 1h, 6h, 24h, terminal]` — 7 retries после первой попытки, итого 8 attempts max. После 8-й неуспешной попытки `status='failed_terminal'`, admin alert (Slack `#security-ops` через `corelib/notify` Phase 7 — переиспользуется), subscriber'у incrementится `failure_count`. Если 3+ consecutive failed_terminal → `caep_subscribers.enabled` auto-flipped в false (subscribed admin получает email "your subscriber paused — please investigate"; ручной re-enable через UI).

8. **5 canonical event types** (per OpenID CAEP spec; P8-D11):
   - `https://schemas.openid.net/secevent/caep/event-type/session-revoked` — admin force-logout / GDPR erasure / break-glass cancel / mass-revoke.
   - `https://schemas.openid.net/secevent/caep/event-type/token-claims-change` — FGA binding revoke / JIT activate-expire / break-glass active-expire (changes `kacho_groups` / role claims).
   - `https://schemas.openid.net/secevent/caep/event-type/credential-change` — Passkey added/removed / password reset / MFA enrolled / SCIM user disabled.
   - `https://schemas.openid.net/secevent/caep/event-type/assurance-level-change` — ACR step-up / step-down (e.g., user сменил Passkey → temporary ACR=1 до verification).
   - `https://schemas.openid.net/secevent/caep/event-type/device-compliance-change` — device-attestation deviation (Phase 12 → MDM integration; Phase 8 заводит event_type в registry, drainer его обрабатывает, но эмиттеры — future).

9. **Subscriber-side replay protection** — каждый SET содержит `jti` (UUIDv7). Spec recommends subscriber dedupe by jti в-памяти на window ≥2 min (см. P8-D8). Наш test-suite **проверяет** что наш drainer **не posts** один jti дважды (ВНУТРИ нормального flow); и что subscriber-side dedup (если subscriber правильно реализовал — мы тестим mock-subscriber'ом) отвергает дубликат с HTTP 409. Это **subscriber-side responsibility** — наш drainer лишь **не создаёт** дубликаты в нормальном-fl, retry — другая story (см. P8-D8).

10. **Cross-account isolation** (P8-D17) — drainer выбирает subscribers с `WHERE caep_outbox.account_id = caep_subscribers.account_id` (плюс admin-level-overriding subscriber'ов нет — кажный subscriber per Account; cluster-admin может подписаться через специальный `cluster_break_glass_subscriber` который доходит до Phase 11 — out-of-scope Phase 8).

Phase 8 **НЕ включает** (это Phases 9-13 одного эпика — НЕ «deferred»):

- Full audit pipeline (Kafka + ClickHouse + S3 + HSM signing + SIEM forwarders) — **Phase 9**. Phase 8 пишет audit-events о CAEP delivery (`caep.delivery_succeeded` / `caep.delivery_failed`) в `audit_outbox` — drainer для audit_outbox — Phase 9.
- SPIFFE/SPIRE in-cluster mTLS (`api-gateway → subscriber` HTTP — пока plain TLS over kacho cluster egress; Phase 11 → mesh-mTLS via Cilium).
- Multi-region active-active CAEP failover — **Phase 11** (Phase 8 emit pattern эмит-ready, но **drainer single-region**; tests 6.13 проверяют что pattern совместим).
- Subscriber **inbound** webhook (mode «kacho-iam **receives** events from external IdP» — federation feature) — **out of scope KAC-127** (если потребуется в KAC-130).
- OpenID Shared Signals Framework (SSF) full compliance — **Phase 13**. Phase 8 реализует SET signing (RFC 8417) + CAEP event-types (OpenID CAEP 1.0) — это core SSF.

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** (workspace `CLAUDE.md`) — кодирование только после `acceptance-reviewer` APPROVED | этот документ — gate; статус выше остаётся `DRAFT` до APPROVED |
| **Запрет #2** — НЕ упоминать "yandex" | в коде / proto / Go / TypeScript / comments / env-names / Slack-сообщениях / email-templates / vault-записях / runbook'ах — не упоминается; YC-стилистика error-text сохраняется (`"CaepSubscriber %s not found"`, `"endpoint_url is immutable after CaepSubscriber.Create"`, `"Illegal argument event_types — must be non-empty"`) |
| **Запрет #3** — НЕ ORM | sqlc + handwritten pgx для всех новых таблиц-доступов (`caep_subscribers_repo.go`, `caep_outbox_repo.go`); `corelib/set` — stdlib `crypto/rsa`, `crypto/ecdsa`, `crypto/ed25519` + `gopkg.in/square/go-jose.v2` для JWT (не ORM) |
| **Запрет #4** — НЕ каскад через границу сервиса | `caep_subscribers.account_id` FK `ON DELETE CASCADE` — **внутри** `kacho_iam`, корректно; `caep_outbox` — без cross-service FK (event_type строки — soft-references на external schema URIs); revoke-cascade в **чужие** сервисы (kacho-vpc / kacho-compute) — через emit CAEP event, **не** cross-DB delete |
| **Запрет #5** — НЕ редактировать применённую миграцию | Phase 1 миграция `0013` уже создала `caep_outbox` / `caep_subscribers` / `session_revocations`; Phase 8 может добавить **новую** миграцию `0022_kac127_phase8_caep_indexes.sql` (partial index для drainer scan) — НЕ изменение `0013` |
| **Запрет #6** — `Internal.*` НЕ на external TLS endpoint | `InternalCaepReceiverService.ReceiveCaepEvent` регистрируется **только** на internal mux api-gateway (`iamInternalAddr` block), доступен из kacho-iam через cluster-internal listener; external TLS `api.kacho.local:443` его НЕ видит. **Public** `CaepSubscriberService` (CRUD + TestDelivery) — на public mux **с** acr=2 step-up + OpenFGA permission gate |
| **Запрет #7** — НЕ broker, пока in-process справляется | drainer — в-process worker pool в kacho-iam pod'е; `pg_notify` / `LISTEN` — Postgres native (НЕ Kafka); retry — в-DB через `next_attempt_at` (НЕ external queue); CAEP outbox — table в kacho_iam DB (Phase 9 drainer её consume'ит для audit-mirror, не дублирует) |
| **Запрет #8** — DB-per-service | `caep_outbox` / `caep_subscribers` / `session_revocations` — внутри `kacho_iam` schema; на api-gateway отдельной БД нет (session_revocations лежит в `kacho_iam`, api-gateway читает через intra-cluster pgx pool с RO-credentials per P8-D9) |
| **Запрет #9** — async-only мутации | `CaepSubscriberService.Create/Update/Delete` → `Operation` (async, see Phase 0); `Get` / `List` — sync read; `TestDelivery` — sync action-method (HTTP-like; возвращает immediate result — это admin-tool, не resource-mutating); внутренний drainer работает без RPC-handle'а |
| **Запрет #10** — within-service refs на DB-уровне | drainer pick — `SELECT FOR UPDATE SKIP LOCKED` (no software-mutex); `caep_outbox.status` transition `pending→in_flight→delivered/failed_terminal` — атомарный CAS UPDATE с RETURNING-кардинальностью; `caep_subscribers` partial UNIQUE `(account_id, endpoint_url, signing_kid) WHERE enabled=true` предотвращает дубликат-регистрацию идентичного endpoint'а; `session_revocations.token_jti` PK — INSERT idempotent через `ON CONFLICT DO NOTHING` |
| **Запрет #11** — тесты в том же PR | каждый PR Phase 8 содержит: kacho-proto — buf-lint + buf-breaking; corelib/set + corelib/caep — unit-tests (signed JWT verifiable, alg whitelist enforced, jti-uniqueness, payload schemas); kacho-iam — integration-tests testcontainer Postgres (drainer-race-tests; rate-limiter concurrent-test; CAS state-machine race; subscriber CRUD); kacho-api-gateway — integration-tests (LISTEN/NOTIFY cross-pod sync; session-revocations cache invalidation); newman cases (см. §7 DoD) — happy + negative для каждого RPC; k6 load (см. §6.11) — обязателен для SLA verification |

---

## 2. Глоссарий / доменная модель Phase 8 (нормативно)

### 2.1 Сущности, **расширенные** в Phase 8 (из Phase 1 stub'а)

- **CaepSubscriber** — webhook subscription per Account. Полная схема (от Phase 1 migration `0013`):
  - `id TEXT PRIMARY KEY` (prefix `cps_` + 17-char Crockford base32 → regex `^cps_[0-9a-hjkmnp-tv-z]{17}$`),
  - `account_id TEXT REFERENCES accounts(id) ON DELETE CASCADE NOT NULL`,
  - `endpoint_url TEXT NOT NULL CHECK (endpoint_url ~ '^https://' AND length(endpoint_url) BETWEEN 8 AND 1024)`,
  - `signing_kid TEXT NOT NULL CHECK (length(signing_kid) BETWEEN 1 AND 128)` — KID для SET signing verification на subscriber side; ссылается на `jwks_keys.kid`,
  - `expected_audience TEXT NOT NULL CHECK (length(expected_audience) BETWEEN 1 AND 512)` — попадает в SET `aud` claim,
  - `event_types TEXT[] NOT NULL CHECK (cardinality(event_types) > 0 AND event_types <@ ARRAY['https://schemas.openid.net/secevent/caep/event-type/session-revoked','https://schemas.openid.net/secevent/caep/event-type/token-claims-change','https://schemas.openid.net/secevent/caep/event-type/credential-change','https://schemas.openid.net/secevent/caep/event-type/assurance-level-change','https://schemas.openid.net/secevent/caep/event-type/device-compliance-change'])` — filter,
  - `enabled BOOL NOT NULL DEFAULT true`,
  - `failure_count INTEGER NOT NULL DEFAULT 0 CHECK (failure_count >= 0)`,
  - `last_success_at TIMESTAMPTZ`,
  - `last_failure_at TIMESTAMPTZ`,
  - `last_failure_reason TEXT CHECK (last_failure_reason IS NULL OR length(last_failure_reason) <= 2048)`,
  - `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`,
  - `created_by_user_id TEXT REFERENCES users(id) NOT NULL`.
  - **Lifecycle**: CREATED (enabled=true, failure_count=0) → DISABLED (manual или auto после 3+ failed_terminal — see P8-D10) → DELETED (admin manual или Account CASCADE).
  - **Mutable fields** (via Update + UpdateMask): `endpoint_url`, `signing_kid`, `expected_audience`, `event_types`, `enabled`. **Immutable**: `id`, `account_id`, `failure_count`, `last_success_at`, `last_failure_at`, `last_failure_reason`, `created_at`, `created_by_user_id`.
  - **DB-уровень инварианты**:
    - Partial UNIQUE `(account_id, endpoint_url, signing_kid) WHERE enabled = true` — нельзя дважды зарегистрировать один (URL, kid) под одним account (Phase 8 миграция 0022 — см. P8-D12).
    - CHECK `endpoint_url ~ '^https://'` — DB-enforced (Phase 1).
    - CHECK `cardinality(event_types) > 0` — без events нет смысла в subscriber'е.
    - CHECK `event_types <@ ARRAY[...]` — только whitelisted URIs (Phase 8 миграция 0022 расширяет CHECK; Phase 1 имеет менее strict version — допустимо менять CHECK через миграцию без edit applied 0013 — это **новая** миграция, не edit).

- **CaepOutboxEvent** — event-row для drainer'а. Полная схема (от Phase 1 migration `0013`):
  - `id TEXT PRIMARY KEY` (ULID, 26 chars — Crockford base32 = `^[0-7][0-9A-HJKMNP-TV-Z]{25}$`; UUIDv7 acceptable но ULID — design choice P8-D13),
  - `event_type TEXT NOT NULL CHECK (event_type ~ '^https://schemas\\.openid\\.net/secevent/caep/event-type/.+$')`,
  - `subject_id TEXT NOT NULL` — ID субъекта в формате `<resource>_<crockford>` (usr_…, sva_…),
  - `account_id TEXT NOT NULL` — для фильтрации subscriber'ов (cross-account isolation),
  - `payload JSONB NOT NULL` — event-specific claims (per OpenID CAEP schema; serialized в `events.<event-type-uri>` SET claim),
  - `attempts INT NOT NULL DEFAULT 0 CHECK (attempts >= 0 AND attempts <= 8)`,
  - `status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','in_flight','delivered','failed_terminal'))`,
  - `next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now()`,
  - `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`,
  - `delivered_at TIMESTAMPTZ` (set при delivered),
  - `failed_terminal_at TIMESTAMPTZ` (set при failed_terminal),
  - `last_error TEXT CHECK (last_error IS NULL OR length(last_error) <= 2048)` (трубка лога).
  - **Lifecycle**: pending → in_flight (during HTTP POST) → delivered OR (retry-loop with backoff) → failed_terminal.
  - **DB-уровень инварианты**:
    - CHECK `attempts <= 8` — hard cap, drainer **не имеет права** превысить.
    - Partial index `caep_outbox_pending_idx ON caep_outbox (next_attempt_at) WHERE status IN ('pending','in_flight')` — Phase 8 миграция 0022 (см. P8-D15).
    - Idempotent ID — ULID гарантирует unique; INSERT-on-conflict использует bare `ON CONFLICT (id) DO NOTHING` если есть в-flight retry от upstream emitter'а (rare; обычно ULID свежий).

- **CaepDeliveryAttempt** *(opt — child table per subscriber-attempt)* — если P8-D14 решает «multi-subscriber per event». Phase 8 enforces **multi-subscriber semantics**: один event может попасть к N subscriber'ам того же account'а (subscribed на этот event_type). Schema:
  - `id TEXT PRIMARY KEY` (`cda_…`),
  - `event_id TEXT REFERENCES caep_outbox(id) ON DELETE CASCADE NOT NULL`,
  - `subscriber_id TEXT REFERENCES caep_subscribers(id) ON DELETE CASCADE NOT NULL`,
  - `attempts INT DEFAULT 0`,
  - `status TEXT CHECK IN ('pending','in_flight','delivered','failed_terminal')`,
  - `next_attempt_at TIMESTAMPTZ`,
  - `last_http_status INT`,
  - `last_response_preview TEXT` (first 256 bytes),
  - `last_error TEXT`,
  - `delivered_at TIMESTAMPTZ`,
  - `failed_terminal_at TIMESTAMPTZ`,
  - UNIQUE `(event_id, subscriber_id)`.
  - Этой таблицы **нет в Phase 1**; Phase 8 миграция 0022 её **создаёт** (per P8-D14).

- **SessionRevocation** — token-jti revocation (used by api-gateway cache). Полная схема (от Phase 1 migration `0013`):
  - `token_jti TEXT PRIMARY KEY` (UUIDv7 from JWT `jti` claim),
  - `revoked_at TIMESTAMPTZ NOT NULL DEFAULT now()`,
  - `reason TEXT CHECK (length(reason) <= 256)` — `"admin_force_logout"`, `"jit_expired"`, `"break_glass_revoked"`, `"gdpr_erasure"`, `"scim_user_disabled"`, `"credential_changed"`,
  - `user_id TEXT REFERENCES users(id) ON DELETE CASCADE` (nullable — для SA-token может быть SA id, но в этой колонке тогда `sva_…` префикс; CHECK constraint на префикс — opt),
  - `ttl_until TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '30 days')` — TTL для cleanup-job'а (Phase 11 deploys cleanup CronJob; Phase 8 row остаются forever если не cleanup'нуть — design ok).
  - **NOTIFY trigger**: `AFTER INSERT ON session_revocations FOR EACH ROW EXECUTE FUNCTION notify_session_revoked()` — function `pg_notify('session_revoked', NEW.token_jti)`.

- **JwksKey** — Phase 1 schema (extended в Phase 8 для SET signing usage):
  - Phase 8 read-only: drainer берёт `WHERE status='active' AND alg IN ('RS256','ES256','EdDSA') ORDER BY rotated_at DESC LIMIT 1` → primary signing key (key rotation policy — Phase 1 background, Phase 8 не touch'ит).
  - Phase 8 кэширует `(kid, private_key, alg)` в-памяти 5 min; на rotation key — cache miss → fresh fetch.

### 2.2 Сущности, **используемые** read-only от Phase 1-7

- **User** (`users` table) — drainer ссылается на `subject_id` (но **не** JOIN'ит — payload self-contained).
- **Account** (`accounts` table) — `caep_subscribers.account_id` FK + drainer фильтрует events.
- **JwksKey** — для SET signing (read-only).
- **AccessBinding** — Phase 3 эмитит token-claims-change events при `status='REVOKED'` UPDATE'е (этот pathway Phase 3 строит, не Phase 8).
- **AuditOutbox** — Phase 8 пишет `caep.delivery_succeeded` / `caep.delivery_failed` audit events (drainer для audit_outbox — Phase 9).

### 2.3 Сущности, **создаваемые** в Phase 8 (vault `obsidian/kacho/`)

- `resources/iam-caep-subscriber.md` — расширить из Phase 1 stub (полный CRUD + lifecycle + Phase 8 gotchas).
- `resources/iam-caep-outbox-event.md` — новый (схема каноническая + ULID format + lifecycle).
- `resources/iam-caep-delivery-attempt.md` — новый (child table).
- `resources/iam-session-revocation.md` — extended (LISTEN/NOTIFY contract, TTL semantics).
- `rpc/iam-caep-subscriber-service.md` — новый (CRUD + TestDelivery).
- `rpc/apigw-internal-caep-receiver-service.md` — новый, internal-only-помечен.
- `packages/corelib-set.md` — новый.
- `packages/corelib-caep.md` — новый.
- `packages/iam-jobs-caep-drainer.md` — новый.
- `packages/apigw-caep-receiver.md` — новый.
- `edges/iam-to-caep-subscriber-webhook.md` — новый (outbound HTTPS POST; async-ish с retry; cross-tenant isolation rules).
- `edges/iam-to-apigw-internal-caep.md` — новый (intra-cluster gRPC; sync; latency ≤1s SLA).
- `edges/apigw-to-postgres-listen-session-revoked.md` — новый (LISTEN/NOTIFY pubsub for cross-pod cache invalidation).
- `KAC/KAC-127.md` — Phase 8 PR-list updated.

---

## 3. Decision Log (final per phase — no deferred)

Решения номеруются `P8-D<N>`. Каждое — **финальное** для Phase 8 production-edition (round 2: «no strict backward-compat»). Каждое решение имеет: **Контекст** → **Альтернативы** → **Выбор** → **Обоснование**.

### P8-D1: SET (RFC 8417 signed JWT) — не nested JWE, не custom envelope

**Контекст**: формат CAEP event при доставке subscriber'у. SET-JWT (signed) — open-standard; подписать-только vs sign-and-encrypt vs custom REST payload.

**Альтернативы**:
- (a) Plain JSON POST + HMAC header `X-Kacho-Signature: hmac-sha256=...` (Stripe / GitHub webhook style).
- (b) SET (RFC 8417): signed JWT, `typ=secevent+jwt`, public-key verification via JWKS.
- (c) SET-внутри-JWE (signed-then-encrypted): defends against passive sniffing **внутри TLS-end-to-end** — defence in depth.

**Выбор**: (b) signed-only SET-JWT.

**Обоснование**: signed-only SET — это что **OpenID CAEP spec** требует, что **Shared Signals Framework** требует, и что 99% subscriber'ов (Okta, Auth0, корпоративные SP) ожидают. JWE добавляет сложность ключа-обмена (subscriber должен пиблиш ключ-шифрования) и **double-encryption над TLS** — overhead без security benefit на realistic threat-model. HMAC (вариант a) — не-standard для CAEP, исключает interop с любым CAEP-compliant subscriber'ом. Финально: signed-only RFC 8417, content-type `application/secevent+jwt`.

### P8-D2: `endpoint_url` — HTTPS-only, regex `^https://`

**Контекст**: subscriber registry CRUD validation на endpoint_url.

**Альтернативы**:
- (a) Allow `http://` для dev/testing.
- (b) HTTPS-only enforced на DB-CHECK + service validation.
- (c) HTTPS-only + extra TLS-cert-pinning check (subscriber должен публиковать SHA-256 thumbprint).

**Выбор**: (b) HTTPS-only enforced (DB-CHECK + service validation).

**Обоснование**: SET содержит PII (`subject.id = usr_xxx`), не должно идти plain. Phase 1 уже enforced `endpoint_url ~ '^https://'` CHECK; service validation **дополнительно** проверяет parse-ability (URL.Parse, host ≠ localhost при NOT-dev-mode env). Cert-pinning (c) — overkill для Phase 8 (subscriber ротирует cert ежегодно — pinning ломается); может быть optional field в Phase 12 if pentest требует.

### P8-D3: SET signing key — shared с Hydra JWKS pool, не dedicated

**Контекст**: чем подписывать SET? Своим dedicated-CAEP-key или тем же ключом что Hydra использует для ID-token'ов?

**Альтернативы**:
- (a) Dedicated CAEP signing key (отдельный entry в `jwks_keys`), отдельный rotation cycle.
- (b) Reuse active Hydra signing-key (тот же `kid` что в ID-token'ах).
- (c) Hybrid: separate-kid но shared rotation policy.

**Выбор**: (b) reuse Hydra signing-key pool — same `jwks_keys` table, `status='active'`, `purpose IN ('jwt','set')` (multi-purpose).

**Обоснование**: subscriber фетчит JWKS по `iss=https://api.kacho.cloud/.well-known/jwks.json` (Phase 2 setup) → видит **все** active keys и проверяет SET по `kid` header → match'ит. Если dedicated kid — subscriber должен фетчить отдельный JWKS-URI (overhead, и admins забудут rotate'нуть). Phase 1 schema `jwks_keys.purpose ARRAY[]` уже допускает multi-purpose — Phase 8 пишет `{'jwt','set'}` для активных keys. **Если** security audit (Phase 12) потребует строгого isolation — миграция-добавить-`set`-only-key + drainer переключится на `purpose='set'` filter; это «не-strict backward-compat» (round 2 политика).

### P8-D4: Algorithm whitelist — RS256, ES256, EdDSA — no HS\*, no `none`

**Контекст**: какие JWS алгоритмы поддерживаем для SET signing.

**Альтернативы**:
- (a) RS256 only (FIPS 140-2 minimal compatible).
- (b) Allow `HS256` (symmetric — shared-secret).
- (c) Whitelist `RS256`, `ES256`, `EdDSA` (asymmetric only; rejects symmetric).

**Выбор**: (c) — RS256, ES256, EdDSA only.

**Обоснование**: SET — public-key flow (subscriber verifies через JWKS publication). `HS256` требует shared-secret per subscriber → ключ-management nightmare → исключаем. `none` — historical JWT-bug — **forbidden** (algorithm-confusion CVE family). `RS256` default (broadly supported), `ES256` для smaller payload, `EdDSA` future-proof. Все три enforced через `jwks_keys.alg` CHECK constraint и `corelib/set/signer.go` allow-list.

### P8-D5: Exponential backoff schedule — fixed `[1s, 5s, 30s, 5min, 1h, 6h, 24h, terminal]`, 8 max attempts

**Контекст**: retry schedule на 5xx / timeout / 429.

**Альтернативы**:
- (a) Adaptive backoff (per Retry-After header).
- (b) Geometric: 2^n × 1s (1s, 2s, 4s, 8s, 16s, 32s, …) — 10+ attempts, sub-day total.
- (c) Fixed schedule `[1s, 5s, 30s, 5min, 1h, 6h, 24h]` — 7 retries + initial = 8 attempts.

**Выбор**: (c) fixed schedule from design spec §10.

**Обоснование**: SLO §13.6 — revoke ≤10s **happy path**; retry schedule **за пределами SLO** — это disaster-recovery, не steady-state. Sub-30s window (3 attempts: 0s+1s+5s = 6s elapsed; +30s = 36s) покрывает realistic transient (DNS blip, load spike, container restart). 5min covers brief subscriber-outage; 1h/6h/24h covers extended subscriber-outage (но total 31h max — admin успевает заметить и manually re-trigger через `TestDelivery`). После 24h последняя attempt → `failed_terminal`. Retry-After (a) — добавляет complexity на parsing untrusted-server header (some subscriber'ы sending 9999); deferred to Phase 12 optional enhancement.

### P8-D6: Per-subscriber rate-limit — 100 events/min, token-bucket, defer-on-overflow (НЕ drop)

**Контекст**: subscriber может задыхаться от cascade-event'ов (admin удаляет 10000 users — 10000 каждых session-revoked events). Защищаем subscriber'а от storm'а.

**Альтернативы**:
- (a) No rate-limit — subscriber сам обязан handle (5xx → retry-backoff).
- (b) Soft limit: 100 ev/min token-bucket; over-limit → **defer** event (`next_attempt_at = now() + 60s`).
- (c) Hard limit: over-limit → drop event (data loss).
- (d) Per-tenant aggregate limit (across all events): 1000 ev/min per Account.

**Выбор**: (b) — soft per-subscriber, defer-on-overflow.

**Обоснование**: drop (c) — data loss → unacceptable for security events. No-limit (a) — кладёт subscriber, который тогда retry-backoff'ит → cascade-amplification + delayed delivery всех events. Defer (b) — event remains в queue, отложился на 1 минуту, drainer вернётся → eventually delivered (если subscriber не перманентно мёртвый). Token-bucket implementation — `golang.org/x/time/rate` per-subscriber in-memory `map[subscriber_id]*rate.Limiter`, capacity=100, refill=100/min — простая, lock-free. Per-tenant (d) — может комбинироваться в Phase 11 (cross-pod aggregation требует Redis), Phase 8 — per-subscriber достаточно. Implementation note: при `KACHO_IAM_CAEP_DRAINER_POOL_SIZE` > 1 рейт-лимитер shared в одном process'е через `sync.Map`; cross-pod — eventually consistent (по design ok — defer-overflow self-correcting).

### P8-D7: 4xx (кроме 429) → immediate failed_terminal, no retry

**Контекст**: subscriber отвечает HTTP 4xx — что делать?

**Альтернативы**:
- (a) Retry на все 4xx — может subscriber temporarily misconfigured.
- (b) Retry только 408 (Request Timeout) и 429 (Too Many Requests); все остальные 4xx → terminal.
- (c) Terminal на все 4xx включая 429.

**Выбор**: (b) — retry 408 + 429; все остальные 4xx → terminal.

**Обоснование**: 4xx — client-side error (наш SET malformed, subscriber URL gone — 410, NotFound — 404, AuthZ — 401/403, Bad Request — 400). Retry не поможет — каждая attempt будет fail'ить так же. Wasted cycles. 408 = transient (server timeout); 429 = explicit retry-instruction. Per design §10 чётко — «4xx (excluding 429) → failed_terminal». Phase 8 добавляет 408 в retry-set (минор-доп к design, по обсуждению эту edge-case можно ловить как timeout; финально — обращаемся к 408 как retry-able). Terminal → admin alert через `corelib/notify` (Slack `#security-ops` channel).

### P8-D8: Subscriber-side replay protection — recommend dedup-by-jti 2-min window; drainer guarantees uniqueness в "happy" path

**Контекст**: повторяющиеся SET delivery (drainer retry на network-blip → subscriber может видеть тот же event дважды).

**Альтернативы**:
- (a) Drainer guarantees exactly-once (heavy 2-phase commit с subscriber'ом).
- (b) Drainer guarantees at-least-once; subscriber dedup by `jti` (2-min in-memory cache).
- (c) Drainer guarantees at-most-once (only happy 2xx counts; lost-event-acceptable).

**Выбор**: (b) at-least-once + subscriber-side dedup recommended.

**Обоснование**: distributed exactly-once impossible (2-phase commit без 2-phase commit). At-most-once — security data loss → forbidden. At-least-once + dedup-by-`jti` — industry-standard pattern (Stripe / GitHub webhook delivery). Наш drainer **минимизирует** duplicates: один event имеет уникальный outbox `id` (ULID); per-subscriber attempt-row UNIQUE `(event_id, subscriber_id)` (P8-D14); retry shares `jti` (set at first attempt). Subscriber-side dedup-cache 2 min window — design §5.2 "DPoP jti not in replay cache (2min TTL)" — same number. Mock-subscriber в тестах **обязан** дедуп'ить — мы тестим что **наш drainer не creates** дубликат-jti в нормальном retry-flow (тест 6.9.2) **и** что subscriber-side dedup отвергает дубликат с 409 (тест 6.9.3).

### P8-D9: Api-gateway → kacho_iam DB read-only credentials (для session_revocations cache invalidation)

**Контекст**: api-gateway держит сессионный cache, инвалидирует его через `LISTEN 'session_revoked'`. Это требует чтобы api-gateway имел подключение к **kacho_iam** DB (cross-service DB-access).

**Альтернативы**:
- (a) RPC `InternalCaepReceiverService.ReceiveCaepEvent` only — no direct DB.
- (b) RPC + LISTEN на kacho_iam DB через RO-creds — гибрид.

**Выбор**: (b) — RPC for primary path (idempotent INSERT into `session_revocations`); LISTEN для cross-pod cache invalidation.

**Обоснование**: вариант (a) only-RPC — api-gateway получил event на одном pod'е, ему надо разослать invalidate'ы на остальные N pod'ов → нужен **внутри-cluster pubsub**. Можно использовать NATS — но запрет #7 запрещает broker'ы. Альтернатива — `pg_notify` на kacho_iam DB (Postgres native pubsub), все api-gateway pods `LISTEN` — works. Это **single-DB cross-service access** — нестандартно для DB-per-service, но (i) на read-side (LISTEN не пишет ничего), (ii) с dedicated RO-role `kacho_apigw_caep_reader` (GRANT SELECT ON session_revocations, USAGE ON SCHEMA), (iii) для cache-invalidation pattern (НЕ для business logic — все mutations через RPC). См. §запрет #8 — мы **формально** не нарушаем (api-gateway не **владеет** этими данными, только subscribe'ится). Документировано в edges/apigw-to-postgres-listen-session-revoked.md.

### P8-D10: Subscriber auto-disable after 3 consecutive failed_terminal

**Контекст**: subscriber endpoint мёртвый неделю — drainer continues пытаться (each event → 8 attempts → failed_terminal). Wasted load.

**Альтернативы**:
- (a) Manual disable only.
- (b) Auto-disable after **N consecutive** failed_terminal на этом subscriber (N=3).
- (c) Auto-disable after `failure_count > threshold` cumulative.

**Выбор**: (b) — 3 consecutive failed_terminal → flip `enabled=false`, email admin.

**Обоснование**: cumulative (c) — старая ошибка (failure 2 года назад) учитывается → лишнее. 3 consecutive failed_terminal = ~3 events × 31 hours backoff ≈ 4 дня subscriber dead — приличный grace. Implementation: трекер consecutive в `caep_subscribers.consecutive_failed_terminal_count` (новая колонка, Phase 8 миграция 0022), reset to 0 при first успешном delivered, increment на каждый failed_terminal. UPDATE `enabled=false WHERE consecutive_failed_terminal_count >= 3 AND enabled=true` (atomic) — manual re-enable via Update RPC.

### P8-D11: 5 canonical event-types — OpenID CAEP 1.0 spec verbatim

**Контекст**: какие event-types поддерживаем.

**Альтернативы**:
- (a) Только session-revoked + token-claims-change (minimum для Phase 8 emit).
- (b) Full OpenID CAEP 1.0 set (5 events).
- (c) Custom kacho-specific event-types (`kacho://event/account-suspended`).

**Выбор**: (b) — все 5 canonical OpenID CAEP event-types.

**Обоснование**: subscriber'ы (Okta, Auth0) ожидают canonical URIs — custom ломает interop. Phase 8 emit'ит первые 3 (session-revoked, token-claims-change, credential-change), но drainer-side support для всех 5 — minimal incremental (всё это просто строка). assurance-level-change emit'ится в Phase 8 на ACR change events (user re-enroll'ит Passkey); device-compliance-change reserved для Phase 12 MDM. CHECK constraint на `caep_outbox.event_type` enforces only-canonical URIs.

### P8-D12: Partial UNIQUE `(account_id, endpoint_url, signing_kid) WHERE enabled = true`

**Контекст**: один account случайно регистрирует identical (endpoint_url, signing_kid) subscriber дважды (`enabled=true`). Дубликат-delivery каждого event'а.

**Альтернативы**:
- (a) No constraint — admin sees list, удалит сам.
- (b) Strict UNIQUE on `(account_id, endpoint_url, signing_kid)` — нельзя даже disabled-clone.
- (c) Partial UNIQUE `WHERE enabled=true` — allow disabled-clones (история), но only-one-active.

**Выбор**: (c) partial UNIQUE — миграция 0022.

**Обоснование**: запрет #10 требует DB-level inv. Без uniq — race создаст дубликат + email-storm subscriber'у. Strict (b) запрещает legitimate use-case "subscriber переехал на новый URL, сохраню старый запись disabled для audit history" (round 2 политика: no backward-compat assumes мигрировать данные без труда — disabled cloning ok). На violation → `23505` → service maperr → `AlreadyExists`.

### P8-D13: Outbox event `id` — ULID (26 chars), не UUIDv7

**Контекст**: формат event-id в `caep_outbox`.

**Альтернативы**:
- (a) UUIDv7 (36 chars hex) — global standard.
- (b) ULID (26 chars Crockford base32) — lexicographically sortable, более компактный.
- (c) Custom prefix `cev_…` (как другие наши ресурсы).

**Выбор**: (b) — ULID, no prefix.

**Обоснование**: outbox event — internal-only, не показывается tenant'у (он видит SET-`jti` который **separate** UUIDv7). ULID — lexicographically sortable = drainer `ORDER BY id ASC` гарантированно ordered-by-creation-time без дополнительной timestamp column на ORDER BY (хотя есть `next_attempt_at` для retry-ordering; и `id` для FIFO внутри same `next_attempt_at`). Префикс не нужен — event_id никогда не появится в API-response (только internal logs / metrics labels). ULID generation — `github.com/oklog/ulid/v2` package.

### P8-D14: Multi-subscriber per event — child table `caep_delivery_attempts`

**Контекст**: один event → 0 / 1 / N subscribers (account-scoped). Где трекать per-subscriber delivery state?

**Альтернативы**:
- (a) Один `caep_outbox` row + JSONB `delivery_states[]` (массив per-subscriber state).
- (b) Child table `caep_delivery_attempts (event_id, subscriber_id, status, attempts, ...)` — Phase 8 migration 0022.
- (c) Денормализовать: эмитить N rows в `caep_outbox` (один per (event, subscriber)).

**Выбор**: (b) — child table.

**Обоснование**: JSONB-array (a) — невозможно атомарно CAS-обновить per-subscriber-state, race-prone. Per-event-per-subscriber rows (c) — раздувает outbox в N раз; и эмиттер (Phase 3-7) должен знать всех subscriber'ов на момент emit — это знание только у drainer'а. Child table (b) — clean: один `caep_outbox` row = «event existed», N `caep_delivery_attempts` rows = «status of delivery to each matching subscriber»; CAS UPDATE per-attempt-row атомарный (запрет #10 compliant). `caep_outbox.status` теперь aggregate — `'delivered'` если **все** subscribers delivered (или 0 subscribers matched), `'failed_terminal'` если **любой** subscriber failed_terminal (или admin alert flag в meta), `'in_flight'` иначе.

### P8-D15: Partial index `caep_outbox_pending_idx (next_attempt_at) WHERE status IN ('pending','in_flight')`

**Контекст**: drainer scan-pattern `WHERE status IN ('pending','in_flight') AND next_attempt_at <= now() ORDER BY next_attempt_at LIMIT 1`. Full-table scan на каждый pick = O(n) для table с millions of historical-delivered rows.

**Альтернативы**:
- (a) Full index on `(status, next_attempt_at)`.
- (b) Partial index `WHERE status IN ('pending','in_flight')`.
- (c) Архивная partition: historical-delivered → отдельная partition, retention по времени.

**Выбор**: (b) partial index — миграция 0022.

**Обоснование**: ~99% rows будут `'delivered'` — index size = N% of full. Drainer queries только non-terminal-states, partial-index size O(active queue) <<< O(total). Архивная partition (c) — Phase 11 enhancement (high-volume scenario), не для Phase 8 start.

### P8-D16: TestDelivery — synthetic event, не пишет в caep_outbox

**Контекст**: admin запускает `TestDelivery` для validation subscriber'а. Должен ли test попасть в outbox?

**Альтернативы**:
- (a) Write synthetic event в `caep_outbox` → drainer pick'нет нормальным path'ом.
- (b) Bypass outbox: TestDelivery handler **inline** generate SET + sync POST + return `{http_status, latency_ms, response_preview}`.

**Выбор**: (b) bypass outbox.

**Обоснование**: synthetic event в outbox смешивается с real events → metrics dirty, retry-storm если subscriber broken и admin раз 10 нажмёт test → 10 entries × 8 retries в outbox. TestDelivery sync inline — простой `corelib/set` sign + `http.Post` с timeout 10s + return — admin сразу видит результат. Эфемерный, не учитывается в SLO. Audit-emit нужен (`iam.caep.test_delivery_invoked` audit row) — он живёт в `audit_outbox`, не в caep_outbox.

### P8-D17: Cross-account isolation — DB-уровень JOIN, не software check

**Контекст**: subscriber Account A не должен получать events от Account B.

**Альтернативы**:
- (a) Drainer fetches all subscribers → fetches all events → application-level filter.
- (b) Drainer query: `SELECT ... FROM caep_outbox e JOIN caep_subscribers s ON s.account_id = e.account_id WHERE s.enabled AND e.event_type = ANY(s.event_types) AND ...`.

**Выбор**: (b) — DB-level JOIN.

**Обоснование**: запрет #10 — DB-level invariants. Software-filter (a) one-bug-away от cross-account leak (один if забыли → catastrophe). DB-уровень JOIN means filter невозможно случайно обойти. Integration test 6.14 проверяет cross-account isolation с testcontainers + fixtures.

### P8-D18: Internal CAEP receiver — synchronous RPC, fail-loud на api-gateway 5xx

**Контекст**: kacho-iam → api-gateway intra-cluster `ReceiveCaepEvent` call. Async-ok / sync-fail-loud?

**Альтернативы**:
- (a) Async (fire-and-forget; gRPC streaming).
- (b) Sync с retry; на final fail — emit audit `caep.intra_cluster_receiver_failed` но continue main flow (webhook delivery вне зависимости).
- (c) Sync с retry; на final fail — abort drainer flow (no webhook delivery either).

**Выбор**: (b) — sync с retry (3 attempts с backoff 100ms/500ms/2s); на fail — audit alert + continue webhook flow.

**Обоснование**: intra-cluster ≤1s — для **happy path**. Если api-gateway down → SLO violation (сессии остаются valid на cache 5s), но **webhook subscribers всё равно получат event** (independent path) → revoke effective через них. Aborting (c) — теряем ВСЕ delivery — too brittle. Async (a) — теряем confidence что api-gateway получил → SLO breach скрыт. Sync (b) — best mid-ground: best-effort intra-cluster + guaranteed-eventual webhook.

### P8-D19: TLS verification на outbound webhook — full chain, нет пользовательского self-signed CA

**Контекст**: subscriber endpoint TLS. Принимаем self-signed?

**Альтернативы**:
- (a) Full TLS verification (system CAs only).
- (b) Allow self-signed per-subscriber (subscriber пишет cert в registry).
- (c) Allow self-signed only в `KACHO_ENV=dev`; production strict.

**Выбор**: (c) — `KACHO_ENV=production` enforces full verification; dev allows insecure-skip-verify через env.

**Обоснование**: production subscriber обязан иметь valid cert (Let's Encrypt free; нет excuse). Self-signed → MITM risk. Dev env (developer тестирует subscriber на `https://localhost:8443` self-signed) — needed для DX. Implementation: `tls.Config.InsecureSkipVerify = (env == "dev" || env == "test")` only.

### P8-D20: Subscriber webhook timeout — 10 seconds connect+read total

**Контекст**: per-HTTP-POST timeout.

**Альтернативы**:
- (a) Aggressive (2s) — fast fail, more retries.
- (b) Moderate (10s) — design spec default.
- (c) Long (60s) — accommodate slow subscriber.

**Выбор**: (b) 10s total (connect 3s + headers 2s + read 5s).

**Обоснование**: SET payload ~500-1000 bytes (compressed JWT) — should respond instantly. Если subscriber не успел за 10s — overloaded → backoff better than holding socket. 60s (c) — DoS-ish (sustained 100 ev/min × 60s = 100 concurrent connections held). Aggressive (a) — кладёт subscriber'ы на legitimate slow-start (cold-start lambda spawn). 10s — industry standard for webhook delivery (Stripe / GitHub use 30s but they're lenient; security events prefer 10s).

---

## 4. Architecture (Phase 8 ASCII)

### 4.1 Event flow happy-path

```
┌───────────────────────────────────────────────────────────────────────────┐
│  Phase 3-7 emitter (FGA revoke / JIT expire / GDPR cascade / SCIM disable)│
│         │                                                                  │
│         │ INSERT caep_outbox (id, event_type, subject_id, account_id,     │
│         │   payload JSONB, status='pending', next_attempt_at=now())       │
│         │ + INSERT audit_outbox (event=<source>.<action>)                 │
│         ▼                                                                  │
│  kacho_iam.caep_outbox  ◄───────────────────────────────────┐             │
└───────────────┬──────────────────────────────────────────────┼─────────────┘
                │                                              │
                │  pg_notify('caep_event', event_id)           │
                │  (optional optimization — drainer wakes ASAP)│
                ▼                                              │
┌───────────────────────────────────────────────────────────┐  │
│  kacho-iam pod: caep_drainer (N=8 workers)                │  │
│    ┌───────────────────────────────────────────────────┐  │  │
│    │ worker N:                                          │  │  │
│    │   1. SELECT ... FOR UPDATE SKIP LOCKED LIMIT 1     │  │  │
│    │      WHERE status IN ('pending','in_flight')       │  │  │
│    │        AND next_attempt_at <= now()                │  │  │
│    │      ORDER BY next_attempt_at, id                  │  │  │
│    │   2. UPDATE caep_outbox SET status='in_flight',    │  │  │
│    │      attempts = attempts + 1 WHERE id=$1           │  │  │
│    │      RETURNING ...                                 │  │  │
│    │   3. Find matching caep_subscribers:               │  │  │
│    │      SELECT ... WHERE account_id=$1                │  │  │
│    │        AND enabled                                 │  │  │
│    │        AND $2 = ANY(event_types)                   │  │  │
│    │   4. For each subscriber:                          │  │  │
│    │      a. Token-bucket rate-limit check              │  │  │
│    │         (100 ev/min per subscriber)                │  │  │
│    │         - over → defer next_attempt_at += 60s      │  │  │
│    │      b. INSERT/UPSERT caep_delivery_attempts       │  │  │
│    │      c. Load active jwks_keys → cache 5min         │  │  │
│    │      d. Build SET-JWT (corelib/set/signer.go):     │  │  │
│    │         - header: {alg:RS256, typ:secevent+jwt,    │  │  │
│    │                    kid:<active>}                   │  │  │
│    │         - claims:{iss:https://api.kacho.cloud,     │  │  │
│    │                   aud:<subscriber.expected_aud>,   │  │  │
│    │                   iat:<unix>, jti:<uuidv7>,        │  │  │
│    │                   events:{<event-type>:<payload>}} │  │  │
│    │      e. HTTP POST endpoint_url:                    │  │  │
│    │         - Authorization: Bearer <SET-JWT>          │  │  │
│    │         - Content-Type: application/secevent+jwt   │  │  │
│    │         - timeout 10s, TLS strict (prod)           │  │  │
│    │      f. Update delivery_attempts.status:           │  │  │
│    │         - 2xx → delivered (CAS)                    │  │  │
│    │         - 408/429/5xx → in_flight + backoff        │  │  │
│    │         - other 4xx → failed_terminal              │  │  │
│    │      g. INSERT audit_outbox (caep.delivery_…)      │  │  │
│    │   5. If ALL subscribers delivered → UPDATE         │  │  │
│    │      caep_outbox.status='delivered' (CAS)          │  │  │
│    │      If ANY failed_terminal → admin alert          │  │  │
│    └─────────────────────────┬──────────────────────────┘  │  │
│                              │                              │  │
│                              ▼ ────────────────────────────►│  │ retry/defer
│           ┌──────────────────────────────┐                  │  │ remains pending
│           │  HTTP POST →                 │                  │  │
│           │  https://subscriber.kacho/.. │                  │  │
│           │     ↓ 2xx                    │                  │  │
│           │  done; subscriber dedup'ит   │                  │  │
│           │  по jti (2min window)        │                  │  │
│           └──────────────────────────────┘                  │  │
└────────────────────────────────────────────────────────────┘   │
                │                                                 │
                │ in parallel — synchronous gRPC call             │
                │ (within same drainer-transaction or right after)│
                ▼                                                 │
┌──────────────────────────────────────────────────────────┐     │
│ kacho-api-gateway pod (ONE of N — load-balanced)         │     │
│    InternalCaepReceiverService.ReceiveCaepEvent(event) {│     │
│      if event.type in {session-revoked,                  │     │
│                        token-claims-change}:             │     │
│        INSERT session_revocations(token_jti, ...)        │     │
│          ON CONFLICT (token_jti) DO NOTHING              │     │
│        → trigger pg_notify('session_revoked', jti)       │     │
│      return Ack{processed:true}                          │     │
│    }                                                     │     │
└─────────────────────────┬────────────────────────────────┘     │
                          │                                       │
                          │ pg_notify('session_revoked', jti)     │
                          ▼                                       │
┌──────────────────────────────────────────────────────────┐     │
│ ALL api-gateway pods (LISTEN session_revoked):           │     │
│   1. Receive NOTIFY payload (jti).                       │     │
│   2. Invalidate in-memory LRU cache entry for jti.       │     │
│   3. Next request with this jti → cache miss → check DB  │     │
│      → finds revocation → reject 401.                    │     │
│ p99 cache invalidation across N pods ≤ 1 second.         │     │
└──────────────────────────────────────────────────────────┘     │
                                                                  │
[Overall SLA] revoke event emit → all sessions denied: ≤ 10 sec  │
                                                                  ▼
                                                       (next pick by drainer)
```

### 4.2 Retry / backoff state machine

```
                  ┌─────────┐
                  │ pending │ ◄─────────────┐ initial INSERT
                  └─────┬───┘                │ from Phase 3-7
                        │ drainer pick       │ emitter
                        │ (FOR UPDATE        │
                        │  SKIP LOCKED)      │
                        ▼                    │
                  ┌──────────┐               │
                  │ in_flight│               │
                  └─────┬────┘               │
                        │                    │
        ┌───────────────┼───────────────┐    │
        │               │               │    │
        ▼ 2xx           ▼ 408/429/5xx   ▼ other 4xx
   ┌──────────┐    attempts < 8     attempts == 8
   │ delivered│         │               │
   └──────────┘         ▼               ▼
                ┌───────────────┐  ┌─────────────────┐
                │ in_flight,    │  │ failed_terminal │
                │ next_attempt  │  │ + admin alert    │
                │   = +backoff  │  └─────────────────┘
                │ (1s,5s,30s,   │           │
                │  5min,1h,6h,  │           │
                │  24h)         │           │ if consecutive=3
                └───────┬───────┘           │ on this subscriber
                        │                   ▼
                        │           caep_subscribers
                        │           SET enabled=false
                        │           email admin
                        └─── back to drainer pick loop
```

### 4.3 Components / packages

```
┌─────────────────────────────────────────────────────────────────┐
│ kacho-proto/proto/kacho/iam/v1/caep_subscriber.proto            │
│   service CaepSubscriberService { Create/Update/Delete/Get/     │
│     List/TestDelivery }                                         │
│ kacho-proto/proto/kacho/iam/internal/v1/                        │
│   internal_caep_receiver.proto                                  │
│   service InternalCaepReceiverService { ReceiveCaepEvent }      │
├─────────────────────────────────────────────────────────────────┤
│ kacho-corelib/                                                   │
│   set/signer.go        — Sign(claims) → JWT-string              │
│   set/verifier.go      — Verify(jwt, jwks) → claims OR error    │
│   set/set_testing.go   — InMemoryKeypair for unit tests         │
│   caep/event_types.go  — 5 canonical URI constants              │
│   caep/payload.go      — BuildSessionRevoked, etc.              │
├─────────────────────────────────────────────────────────────────┤
│ kacho-iam/                                                       │
│   internal/apps/kacho/api/caep_subscriber/                      │
│     create.go, update.go, delete.go, get.go, list.go,           │
│     test_delivery.go                                            │
│   internal/apps/kacho/jobs/                                     │
│     caep_drainer.go      — worker pool, claim, deliver          │
│     caep_backoff.go      — schedule table + next_attempt_at calc│
│     caep_rate_limiter.go — token-bucket per subscriber          │
│     caep_signer_cache.go — kid→privkey cache (5min TTL)         │
│   internal/domain/caep_subscriber.go      — self-validating     │
│   internal/repo/kacho/pg/caep_outbox_repo.go                    │
│   internal/repo/kacho/pg/caep_subscribers_repo.go               │
│   internal/repo/kacho/pg/caep_delivery_attempts_repo.go         │
│   internal/clients/api_gateway_caep_receiver_client.go          │
│   internal/migrations/0022_kac127_phase8_caep_indexes.sql       │
├─────────────────────────────────────────────────────────────────┤
│ kacho-api-gateway/                                               │
│   internal/caep/                                                │
│     receiver.go  — gRPC server impl ReceiveCaepEvent            │
│     handler.go   — INSERT session_revocations idempotent        │
│   internal/cache/                                               │
│     session_revocations.go — LRU + LISTEN cross-pod sync        │
│   internal/restmux/mux.go  — register CaepSubscriber (public)   │
│                              + InternalCaepReceiver (internal)  │
├─────────────────────────────────────────────────────────────────┤
│ kacho-ui/                                                        │
│   src/pages/iam/caep-subscribers/                               │
│     SubscribersListPage.tsx                                     │
│     CreateSubscriberModal.tsx                                   │
│     SubscriberDetailPage.tsx (incl. test-delivery button)       │
├─────────────────────────────────────────────────────────────────┤
│ kacho-test/                                                      │
│   tests/k6/caep_revoke_latency_kac127.js                        │
│   tests/newman/cases/iam_caep_*.py                              │
├─────────────────────────────────────────────────────────────────┤
│ kacho-deploy/                                                    │
│   helm/kacho/values.yaml: caep.{drainer,receiver}.*              │
│   prometheus-rules: CAEPDeliveryFailureRate, CAEPQueueDepth,    │
│                     CAEPp99Latency                              │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. Декомпозиция работ

Phase 8 разбит на 6 tasks (per plan §477-503). Каждая task имеет responsible role + acceptance criteria.

### Task 8.1 — Acceptance document (этот файл)

- **Role**: `acceptance-author` → `acceptance-reviewer` (APPROVED gate).
- **DoD**: документ покрывает 40+ GWT сценариев, 7 категорий (subscriber CRUD, SET signing, webhook happy, retry, 4xx terminal, rate-limit, internal receiver, event-types coverage, replay protection, SLA k6, test-delivery, cross-account isolation, vault).
- **Artefact**: `docs/specs/sub-phase-3.8-iam-caep-push-acceptance.md` (этот файл).

### Task 8.2 — kacho-iam: CAEP outbox drainer + SubscriberService + SET signing

- **Role**: `rpc-implementer` (для API CRUD) + `service-scaffolder` (для drainer worker pool) → `go-style-reviewer` + `db-architect-reviewer`.
- **Files**:
  - `internal/apps/kacho/jobs/caep_drainer.go` (worker pool, FOR UPDATE SKIP LOCKED claim, SET sign, HTTP POST loop);
  - `internal/apps/kacho/jobs/caep_backoff.go` (schedule [1s,5s,30s,5m,1h,6h,24h]);
  - `internal/apps/kacho/jobs/caep_rate_limiter.go` (token bucket per subscriber);
  - `internal/apps/kacho/jobs/caep_signer_cache.go` (kid→privkey 5min cache);
  - `internal/apps/kacho/api/caep_subscriber/{create,update,delete,get,list,test_delivery}.go`;
  - `internal/domain/caep_subscriber.go` (self-validating value-type);
  - `internal/repo/kacho/pg/caep_outbox_repo.go` (sqlc);
  - `internal/repo/kacho/pg/caep_subscribers_repo.go` (sqlc);
  - `internal/repo/kacho/pg/caep_delivery_attempts_repo.go` (sqlc);
  - `internal/clients/api_gateway_caep_receiver_client.go` (gRPC stub call);
  - `internal/migrations/0022_kac127_phase8_caep_indexes.sql` (partial index + child table `caep_delivery_attempts` + `consecutive_failed_terminal_count` column + extended CHECK constraints).
- **Integration tests (testcontainers Postgres)**:
  - concurrent drainer-pick race (запрет #10 — два worker'а pick'ают одну row → ровно один win'нет, second loops);
  - rate-limiter overflow: 200 events/min на один subscriber → ровно 100 delivered в первой minute, 100 deferred с increment'ом `next_attempt_at`;
  - CAS status machine: pending→in_flight, in_flight→delivered, in_flight→failed_terminal (concurrent updates рассматриваются);
  - subscriber partial UNIQUE: два concurrent Create'а с same (account_id, endpoint_url, signing_kid) → ровно один win, второй → AlreadyExists (23505);
  - signer kid-cache eviction: rotation in jwks_keys → drainer fetches new key in ≤5min.
- **DoD**:
  - сборка `make build` зелёная;
  - `make integration-test` зелёный (включая race tests);
  - newman cases (см. §6 / §7) зелёные;
  - drainer survives `SIGTERM` graceful (current claims released back to pending в-flight).

### Task 8.3 — kacho-api-gateway: Internal CAEP receiver + LISTEN/NOTIFY

- **Role**: `rpc-implementer` + `api-gateway-registrar` → `go-style-reviewer`.
- **Files**:
  - `internal/caep/receiver.go` (gRPC handler — idempotent INSERT session_revocations);
  - `internal/caep/handler.go` (validation, event-type dispatch);
  - `internal/cache/session_revocations.go` (LRU + LISTEN);
  - `internal/restmux/mux.go` (register `CaepSubscriberService` на public; `InternalCaepReceiverService` на `iamInternalAddr` — per запрет #6).
- **Integration tests**:
  - LISTEN/NOTIFY: pod-1 INSERT session_revocations → pod-2 invalidates cache ≤1s;
  - idempotent INSERT: same jti дважды → 0 errors, single row;
  - cache hit/miss: pre-revoke request → cache hit OK; post-revoke → cache miss → DB lookup → reject 401.
- **DoD**: integration test зелёный; api-gateway pod restart drops cache (acceptable — rebuild on demand).

### Task 8.4 — kacho-ui: Subscriber registry UI

- **Role**: `acceptance-author` style coordinate UI flows; UI eng → reviewers (UI team).
- **Files**:
  - `src/pages/iam/caep-subscribers/SubscribersListPage.tsx` (per Account list, filter by enabled/failures);
  - `src/pages/iam/caep-subscribers/CreateSubscriberModal.tsx` (form: endpoint_url HTTPS, signing_kid dropdown from active JWKS keys, expected_audience, event_types multi-select из 5 canonical);
  - `src/pages/iam/caep-subscribers/SubscriberDetailPage.tsx` (failure history table, TestDelivery button с inline-result, enable/disable toggle, delete).
- **DoD**: Playwright e2e test (`tests/e2e/iam-caep-subscriber-crud.spec.ts`) проходит full flow.

### Task 8.5 — k6 latency load test

- **Role**: `qa-test-engineer` (workspace) + service-specific `vpc-load-testing` skill (re-used pattern).
- **Files**: `tests/k6/caep_revoke_latency_kac127.js`.
- **Setup**: 10 mock-subscriber containers (Go HTTP server returning 200 immediately, recording timestamps); kacho-iam in load-test mode (drainer pool=8); k6 emit 100 events/min × 30 min uniform distribution.
- **Assertions**:
  - p95 webhook POST→response latency ≤ 2 seconds;
  - p99 webhook POST→response latency ≤ 5 seconds;
  - p99 end-to-end (event INSERT timestamp → subscriber received-at timestamp) ≤ 10 seconds;
  - 0% delivery loss (all events with `status='delivered'`);
  - sustained no-memory-leak (Go heap RSS stable);
  - sustained no-DB-lock-contention (drainer pick latency p95 ≤ 50ms).
- **DoD**: k6 report committed в `docs/qa/phase8-k6-revoke-latency-2026-MM-DD.md`.

### Task 8.6 — PR-chain + YouTrack

- **Role**: автор feature-set (lead).
- **Steps**:
  - YT KAC-127 subtask "Phase 8 CAEP push" создан и в текущем спринте;
  - PR'ы в порядке зависимостей (kacho-proto → corelib → kacho-iam → kacho-api-gateway → kacho-ui / kacho-test / kacho-deploy → kacho-workspace);
  - Каждый PR содержит integration-tests + newman cases (запрет #11);
  - PR-URLs комментариями в YT;
  - После всех merge — vault entries updated + KAC-127 ticket → Test/Done.

---

## 6. Сценарии Given-When-Then (47 GWT)

> Convention: scenario ID = `8-NN`. Каждый scenario имеет precise `When` (RPC + payload) + verifiable `Then` (gRPC code OR HTTP status OR DB state).

### 6.1 SET signing (5 scenarios)

#### Сценарий 8-01: SET-JWT generated with correct shape

**ID**: `8-01`

**Given** Active JWKS key exists: `(kid='kid_v3', alg='RS256', private_key=<encrypted>, status='active')` in `jwks_keys`
**And** Subscriber registered: `(id='cps_test01', expected_audience='https://subscriber.example.com/caep')`
**And** Caep outbox row: `(event_type='https://schemas.openid.net/secevent/caep/event-type/session-revoked', subject_id='usr_alice_acc_a1b2', account_id='acc_a1b2', payload={"reason":"admin_force_logout"})`

**When** Drainer picks row + signs SET via `corelib/set/signer.go`

**Then** Generated SET-JWT has:
  - Header: `{"alg":"RS256","typ":"secevent+jwt","kid":"kid_v3"}`
  - Claims: `{"iss":"https://api.kacho.cloud","aud":"https://subscriber.example.com/caep","iat":<within 10s of now>,"jti":"<valid uuidv7>","events":{"https://schemas.openid.net/secevent/caep/event-type/session-revoked":{"subject":{"format":"opaque","id":"usr_alice_acc_a1b2"},"reason":"admin_force_logout","event_timestamp":<unix>}}}`
**And** Signature verifiable with public key `kid_v3` (test invokes `corelib/set/verifier.go` on generated SET)
**And** `typ` claim absent in **payload** (only in header per RFC 7519 §5.1)
**And** No `exp` claim (SET RFC 8417 §2.2 — события — без expiry; subscriber dedup-by-jti — replay protection)

#### Сценарий 8-02: SET signed with current JWKS active key after rotation

**ID**: `8-02`

**Given** Active key was `kid_v3`, drainer's signer-cache holds `(kid_v3, privkey_v3)`
**And** Admin rotates: `UPDATE jwks_keys SET status='retired' WHERE kid='kid_v3'; INSERT jwks_keys ... (kid='kid_v4', status='active')`
**And** 5-minute cache TTL passes

**When** Drainer signs new SET

**Then** SET-JWT header `kid='kid_v4'`
**And** Signature verifiable with `kid_v4` public key
**And** Old cache entry `kid_v3` evicted on TTL expiry
**And** `corelib/set/signer.go` queries `WHERE status='active' ORDER BY rotated_at DESC LIMIT 1` correctly returns `kid_v4`

#### Сценарий 8-03: SET signed with previous (retired) key — transitional grace

**ID**: `8-03`

**Given** Active key was `kid_v3`, drainer cache contains `(kid_v3, privkey)` (cached at T=0)
**And** At T=2min: admin rotates → `kid_v4` becomes active, `kid_v3` becomes 'retired'
**And** At T=3min: drainer attempts sign (cache TTL not expired)

**When** Drainer signs SET

**Then** SET-JWT header `kid='kid_v3'` (cache hit, no refetch)
**And** Subscriber-side verification: subscriber fetches JWKS, sees both `kid_v3` (still in JWKS for 24h grace) and `kid_v4`; verifies with `kid_v3` — success
**And** At T=8min (cache TTL expired): next sign uses `kid_v4`
**Note**: `kid_v3` remains in published JWKS for 24h after status='retired' (Phase 1 spec §JWKS-Rotation); only after 24h key is hard-removed → status='destroyed'

#### Сценарий 8-04: SET signing fails — no active key in JWKS

**ID**: `8-04`

**Given** All keys in `jwks_keys` have `status IN ('retired','destroyed')` — DB-level guarantee FAILED (should never happen production); test simulates via direct UPDATE

**When** Drainer attempts sign

**Then** `corelib/set/signer.go` returns `ErrNoActiveSigningKey`
**And** Drainer marks event `status='in_flight'`, schedules backoff (treats as transient)
**And** Audit `caep.signing_key_missing` (CRITICAL severity)
**And** PagerDuty alert fires (`SET signing key absent — pipeline halted`)
**And** event remains pending up to 8 attempts; if persists → failed_terminal + escalation

#### Сценарий 8-05: SET signed with non-whitelisted algorithm rejected

**ID**: `8-05`

**Given** Buggy migration somehow inserted `(kid='kid_evil', alg='HS256', ...)` (DB-CHECK on `alg IN ('RS256','ES256','EdDSA')` should prevent — test bypasses via direct UPDATE for negative coverage)

**When** Drainer attempts use this key

**Then** `corelib/set/signer.go` rejects: returns `ErrUnsupportedAlgorithm: HS256`
**And** No SET emitted
**And** Audit emit + admin alert
**And** Phase 1 DB-CHECK на `jwks_keys.alg` — second-line defence; both layers caught

### 6.2 Subscriber CRUD (8 scenarios)

#### Сценарий 8-06: Create subscriber — happy path

**ID**: `8-06`

**Given** Authenticated user `usr_admin_alice` has step-up `acr=2` + permission `iam.caep_subscribers.upsert` on `acc_a1b2`
**And** Active JWKS keys include `kid_v3`

**When** Client POSTs `/iam/v1/accounts/acc_a1b2/caepSubscribers` (gRPC `CaepSubscriberService.Create`):

```json
{
  "account_id": "acc_a1b2",
  "endpoint_url": "https://subscriber.example.com/caep/inbox",
  "signing_kid": "kid_v3",
  "expected_audience": "https://subscriber.example.com/caep",
  "event_types": [
    "https://schemas.openid.net/secevent/caep/event-type/session-revoked",
    "https://schemas.openid.net/secevent/caep/event-type/token-claims-change"
  ]
}
```

**Then** Response = `Operation { done: true, response: CaepSubscriber { id: "cps_<17chars>", account_id: "acc_a1b2", endpoint_url, signing_kid, expected_audience, event_types, enabled: true, failure_count: 0, last_success_at: null, created_at: <within 10s>, created_by_user_id: "usr_admin_alice" } }`
**And** DB row: `SELECT * FROM caep_subscribers WHERE id = $1` returns matching row
**And** Audit `iam.caep_subscriber.created` emit with subject_id=cps_id, actor=usr_admin_alice
**And** ID prefix matches regex `^cps_[0-9a-hjkmnp-tv-z]{17}$`
**And** No SET delivery triggered (Create is config, not event)

#### Сценарий 8-07: Create — invalid endpoint_url (http://) rejected by DB CHECK

**ID**: `8-07`

**Given** Same actor as 8-06

**When** POST with `endpoint_url = "http://subscriber.example.com/caep"`

**Then** HTTP 400 INVALID_ARGUMENT, message `"Illegal argument endpoint_url: must match ^https://"`
**And** Service-layer validation catches before DB INSERT (defence-in-depth — DB CHECK is second line)
**And** No row in `caep_subscribers`

#### Сценарий 8-08: Create — invalid signing_kid (unknown JWKS key) rejected

**ID**: `8-08`

**Given** `signing_kid = "kid_nonexistent"`

**When** POST

**Then** HTTP 400 INVALID_ARGUMENT, message `"Illegal argument signing_kid: kid_nonexistent not present in active JWKS keys"`
**And** Validation queries `jwks_keys WHERE kid=$1 AND status='active'` → 0 rows
**And** No row in `caep_subscribers`

#### Сценарий 8-09: Create — empty event_types rejected by DB CHECK

**ID**: `8-09`

**Given** `event_types = []`

**When** POST

**Then** HTTP 400 INVALID_ARGUMENT, message `"Illegal argument event_types: must contain at least one canonical CAEP event-type URI"`
**And** DB CHECK `cardinality(event_types) > 0` enforces (23514 if reaches DB)

#### Сценарий 8-10: Create — non-whitelisted event_type rejected

**ID**: `8-10`

**Given** `event_types = ["https://schemas.openid.net/secevent/caep/event-type/session-revoked", "https://example.com/custom/event"]`

**When** POST

**Then** HTTP 400 INVALID_ARGUMENT, message `"Illegal argument event_types: URI https://example.com/custom/event not in canonical CAEP whitelist"`
**And** Service validation lists allowed URIs
**And** DB CHECK `event_types <@ ARRAY[...]` second line

#### Сценарий 8-11: Update — toggle enabled, mutable

**ID**: `8-11`

**Given** Subscriber `cps_xxx` exists with `enabled=true`

**When** PATCH `/iam/v1/caepSubscribers/cps_xxx` with `update_mask=enabled, enabled=false`

**Then** Response = `Operation { done: true, response: { enabled: false, ... } }`
**And** Audit `iam.caep_subscriber.updated`
**And** Drainer immediately stops selecting events for this subscriber (next pick excludes via `WHERE s.enabled=true`)
**And** In-flight events that already started POST → finish their POST cycle (transactional consistency)

#### Сценарий 8-12: Update — change endpoint_url, mutable

**ID**: `8-12`

**Given** Subscriber exists with `endpoint_url = "https://old.example.com/caep"`

**When** PATCH `update_mask=endpoint_url, endpoint_url="https://new.example.com/caep"`

**Then** Response = updated row
**And** Subsequent drainer picks POST to new URL
**And** Old in-flight POST to old URL completes (won't retry to old URL on backoff)

#### Сценарий 8-13: Update — failure_count immutable, attempt rejected

**ID**: `8-13`

**Given** Subscriber exists with `failure_count=42`

**When** PATCH `update_mask=failure_count, failure_count=0`

**Then** HTTP 400 INVALID_ARGUMENT, message `"failure_count is immutable after CaepSubscriber.Create"`
**And** DB row unchanged
**And** UpdateMask discipline enforced

#### Сценарий 8-14: Delete — cascade safe

**ID**: `8-14`

**Given** Subscriber `cps_xxx` exists
**And** 3 caep_outbox events were delivered to it (3 caep_delivery_attempts rows reference it)

**When** DELETE `/iam/v1/caepSubscribers/cps_xxx`

**Then** Response = `Operation { done: true }`
**And** Row deleted from caep_subscribers
**And** Child caep_delivery_attempts rows CASCADE deleted (per FK ON DELETE CASCADE)
**And** caep_outbox rows unaffected (status='delivered' historical data preserved)
**And** Audit `iam.caep_subscriber.deleted`

#### Сценарий 8-15: List per account — RBAC filter

**ID**: `8-15`

**Given** Account `acc_a` has 3 subscribers; account `acc_b` has 2 subscribers
**And** `usr_admin_alice` has perm only on `acc_a`

**When** GET `/iam/v1/accounts/acc_a/caepSubscribers`

**Then** Response contains 3 subscribers (acc_a only)
**And** GET `/iam/v1/accounts/acc_b/caepSubscribers` → 403 PermissionDenied
**And** Filter applied at handler-layer via OpenFGA Check

### 6.3 Webhook delivery — happy path (4 scenarios)

#### Сценарий 8-16: Single subscriber happy delivery

**ID**: `8-16`

**Given** Subscriber `cps_xxx` exists for `acc_a1b2`, event_types contains `session-revoked`, endpoint mock returns HTTP 200
**And** Caep_outbox row `evt_yyy` inserted (event_type=session-revoked, account_id=acc_a1b2)

**When** Drainer picks (within 100ms)

**Then** Mock subscriber receives `POST /caep/inbox` with:
  - `Authorization: Bearer <SET-JWT>`
  - `Content-Type: application/secevent+jwt`
  - Body = signed JWT (verifiable with kid_v3 public key)
**And** Caep_outbox row: `status='delivered'`, `delivered_at=now()`, `attempts=1`
**And** Caep_delivery_attempts row: `(event_id=evt_yyy, subscriber_id=cps_xxx, status='delivered', attempts=1, last_http_status=200)`
**And** caep_subscribers updated: `last_success_at=now()`, `failure_count=0`, `consecutive_failed_terminal_count=0`
**And** Audit `caep.delivery_succeeded`
**And** Total elapsed: insert → delivered ≤ 2 seconds (p95 SLA verified in scenario 8-39)

#### Сценарий 8-17: Multiple subscribers — broadcast to all matching

**ID**: `8-17`

**Given** Account `acc_a1b2` has 3 subscribers all subscribed to `session-revoked`: `cps_s1`, `cps_s2`, `cps_s3`
**And** Caep_outbox row inserted

**When** Drainer picks

**Then** 3 `caep_delivery_attempts` rows created (one per subscriber)
**And** 3 HTTP POSTs in parallel (or sequentially by drainer; tests both modes)
**And** All 3 mock subscribers receive same SET (same jti, same payload)
**And** When all 3 return 200: `caep_outbox.status='delivered'` (aggregate)
**And** Audit `caep.delivery_succeeded` ×3 (one per attempt)

#### Сценарий 8-18: Mixed result — partial delivery

**ID**: `8-18`

**Given** 3 subscribers; mock-s1 returns 200, mock-s2 returns 503, mock-s3 returns 200

**When** Drainer picks

**Then** delivery_attempts: s1=delivered, s2=in_flight (will retry), s3=delivered
**And** caep_outbox.status='in_flight' (aggregate — not all delivered yet)
**And** After s2 backoff retry succeeds → caep_outbox.status='delivered'
**And** If s2 never succeeds → after 8 attempts s2=failed_terminal, caep_outbox.status='failed_terminal' (any failed_terminal escalates)

#### Сценарий 8-19: Zero subscribers matching — event drained as no-op

**ID**: `8-19`

**Given** Account `acc_a1b2` has 0 subscribers (or all disabled, or none subscribed to this event_type)
**And** Caep_outbox row inserted

**When** Drainer picks

**Then** 0 `caep_delivery_attempts` created
**And** `caep_outbox.status='delivered'` immediately (no subscribers means "fully delivered" — degenerate empty-set)
**And** `delivered_at=now()`
**And** Audit `caep.delivery_no_subscribers` (info-level)
**And** No HTTP POST issued

### 6.4 Webhook delivery — retry / backoff (6 scenarios)

#### Сценарий 8-20: First retry after 503 — backoff exactly 1 second

**ID**: `8-20`

**Given** Subscriber mock returns 503 on first POST
**And** Test framework controls time

**When** Drainer attempts (attempt 1) at T=0

**Then** `caep_delivery_attempts`: attempts=1, status='in_flight', `next_attempt_at = T + 1s` (first backoff step)
**And** caep_outbox.status='in_flight'
**And** Second attempt occurs at T+1s±100ms (drainer scan freq)
**And** Mock returns 200 on second attempt → status='delivered', attempts=2
**And** Backoff schedule index: attempt N → schedule[N-1]: [1s, 5s, 30s, 5min, 1h, 6h, 24h]

#### Сценарий 8-21: Full backoff progression 1s/5s/30s/5min — all 5xx

**ID**: `8-21`

**Given** Mock returns 503 forever (until externally toggled)

**When** Drainer attempts repeatedly

**Then** Attempt timeline:
  - t=0: attempt 1, 503 → next at t=1s
  - t=1s: attempt 2, 503 → next at t=6s (t + 5s)
  - t=6s: attempt 3, 503 → next at t=36s (t + 30s)
  - t=36s: attempt 4, 503 → next at t=336s (5 min later)
  - t=336s: attempt 5, 503 → next at t=3936s (1 hour later)
  - t=3936s: attempt 6, 503 → next at t=25536s (6 hours later)
  - t=25536s: attempt 7, 503 → next at t=111936s (24 hours later)
  - t=111936s: attempt 8, 503 → status='failed_terminal'
**And** After 8 attempts: `caep_delivery_attempts.status='failed_terminal'`, `attempts=8`
**And** Total elapsed: ~31 hours
**And** `failed_terminal_at` populated
**And** `last_error="HTTP 503 after 8 attempts"`

#### Сценарий 8-22: 429 Too Many Requests — treated as retry-able

**ID**: `8-22`

**Given** Subscriber returns 429 (rate-limited)

**When** Drainer first attempt

**Then** Same backoff schedule as 503 (P8-D7)
**And** No special Retry-After parsing (Phase 8 ignores; P8-D5 fixed schedule)
**And** Audit `caep.delivery_retry` with reason='429'

#### Сценарий 8-23: 408 Request Timeout — retry-able

**ID**: `8-23`

**Given** Subscriber returns 408

**When** Drainer

**Then** Retry per backoff (P8-D7 includes 408 in retry set)

#### Сценарий 8-24: Connection timeout — treated as 5xx-equivalent, retry

**ID**: `8-24`

**Given** Subscriber endpoint never responds (TCP black hole)
**And** Drainer HTTP client timeout 10 seconds

**When** Attempt

**Then** Client returns context-deadline-exceeded
**And** Drainer treats as transient: status='in_flight', backoff per schedule
**And** Audit `caep.delivery_timeout`
**And** Same 8-attempt limit

#### Сценарий 8-25: Failed_terminal after 8 attempts → admin alert

**ID**: `8-25`

**Given** Subscriber returns 503 forever, all 8 attempts exhaust

**When** Attempt 8 fails

**Then** `caep_delivery_attempts.status='failed_terminal'`
**And** `caep_subscribers.consecutive_failed_terminal_count = 1` (incremented)
**And** Admin alert via `corelib/notify` (re-used from Phase 7): Slack `#security-ops` message with: `event_id`, `event_type`, `subscriber_id`, `endpoint_url`, `last_error`
**And** Audit `caep.delivery_failed_terminal`
**And** Subscriber **not** auto-disabled yet (need 3 consecutive — see scenario 8-30)

### 6.5 Webhook delivery — 4xx terminal (3 scenarios)

#### Сценарий 8-26: 410 Gone → immediate failed_terminal

**ID**: `8-26`

**Given** Subscriber returns 410 Gone (endpoint permanently moved)

**When** Drainer first attempt

**Then** `caep_delivery_attempts.status='failed_terminal'` immediately (no retry — per P8-D7)
**And** `attempts=1`, `last_http_status=410`
**And** `failed_terminal_at=now()`
**And** Admin alert (same as scenario 8-25)
**And** Saves ~31 hours of pointless retries

#### Сценарий 8-27: 404 Not Found → immediate failed_terminal

**ID**: `8-27`

**Given** Subscriber returns 404

**When** Drainer attempt

**Then** Same as 8-26: failed_terminal after 1 attempt

#### Сценарий 8-28: 401 Unauthorized → immediate failed_terminal (subscriber rejected our SET signature)

**ID**: `8-28`

**Given** Subscriber returns 401 (e.g., our SET signature failed to verify on their side — wrong kid, wrong audience, etc.)

**When** Attempt

**Then** failed_terminal immediately
**And** Audit `caep.delivery_failed_terminal` reason='subscriber_rejected_4xx_401'
**And** Admin alert includes hint: "check signing_kid + expected_audience configuration"

### 6.6 Per-subscriber rate-limit (3 scenarios)

#### Сценарий 8-29: 150 events/min on one subscriber — 100 delivered, 50 deferred

**ID**: `8-29`

**Given** Subscriber `cps_xxx` registered, mock returns 200 always
**And** 150 caep_outbox rows for `acc_a1b2` event_type=session-revoked inserted within 60 seconds

**When** Drainer processes for 60+ seconds

**Then** Within first 60 seconds: ≤ 100 HTTP POSTs to subscriber (rate-limiter caps at 100/min)
**And** 50 events have `next_attempt_at` deferred by 60 seconds (rate-limited)
**And** Second minute: remaining 50 events delivered (mock receives them with timestamps ≥ T+60s)
**And** Total delivery: 150/150 — **zero loss**
**And** Audit `caep.delivery_rate_limited` for each deferred event

#### Сценарий 8-30: 3 consecutive failed_terminal → subscriber auto-disabled

**ID**: `8-30`

**Given** Subscriber `cps_xxx` returns 503 always
**And** 3 different events occur (3 consecutive failed_terminal cycles, each ~31 hours)

**When** Third failed_terminal occurs

**Then** `caep_subscribers.consecutive_failed_terminal_count = 3`
**And** Atomic UPDATE: `enabled=false, last_disabled_at=now(), last_disabled_reason='3 consecutive failed_terminal'`
**And** Email to subscriber owner (via `created_by_user_id`): "Your CAEP subscriber `cps_xxx` was paused — please investigate <endpoint_url>"
**And** Audit `caep.subscriber_auto_disabled`
**And** Subsequent drainer picks for this subscriber: skipped (WHERE s.enabled=true filter)

#### Сценарий 8-31: Rate-limit per-subscriber isolated — two subscribers in parallel

**ID**: `8-31`

**Given** Subscribers `cps_a` and `cps_b` both subscribed to event_type X for acc_a1b2
**And** 200 events for acc_a1b2 inserted

**When** Drainer runs

**Then** `cps_a` receives 100 events in minute 1 (rate-limited per-subscriber)
**And** `cps_b` receives 100 events in minute 1 (independent token-bucket)
**And** Total 400 HTTP POSTs in minute 1 (200 events × 2 subscribers)
**And** Remaining 200 events (100 to each) in minute 2
**And** Per-subscriber isolation: one subscriber's rate-limit doesn't affect another

### 6.7 Internal CAEP receiver (4 scenarios)

#### Сценарий 8-32: Drainer emits intra-cluster call → api-gateway INSERT session_revocations

**ID**: `8-32`

**Given** Caep_outbox row inserted: event_type=session-revoked, subject_id=usr_alice, payload contains `token_jti=jti_zzz`

**When** Drainer processes (in parallel with webhook delivery)

**Then** Drainer makes synchronous gRPC call: `InternalCaepReceiverService.ReceiveCaepEvent(event)`
**And** Api-gateway handler executes:
  - INSERT session_revocations (token_jti='jti_zzz', revoked_at=now(), reason='admin_force_logout', user_id='usr_alice') ON CONFLICT (token_jti) DO NOTHING
  - Trigger pg_notify('session_revoked', 'jti_zzz')
  - Returns `Ack { processed: true }`
**And** All other api-gateway pods receive NOTIFY within 1 second
**And** Each pod invalidates in-memory LRU entry for `jti_zzz`
**And** Subsequent request with Bearer jti_zzz → cache miss → DB lookup → finds revocation → returns 401

#### Сценарий 8-33: Cross-pod cache invalidation timing — p99 ≤ 1 second

**ID**: `8-33`

**Given** 3 api-gateway pods running, LISTEN active on `session_revoked` channel
**And** Each pod has cached `jti_zzz → valid` (5s TTL)

**When** Pod-1 receives `ReceiveCaepEvent` + INSERT triggers NOTIFY

**Then** Pod-2 and Pod-3 receive NOTIFY payload within 1 second p99 (k6 test validates)
**And** Cache invalidation: pod marks entry stale, next access does DB lookup
**And** No false-positives: only `jti_zzz` evicted, other entries intact
**And** Metric `caep_listen_notify_latency_seconds` histogram exposed

#### Сценарий 8-34: Internal receiver — idempotent INSERT

**ID**: `8-34`

**Given** session_revocations already has row (token_jti='jti_zzz')
**And** Same event re-delivered (drainer retry)

**When** ReceiveCaepEvent called second time

**Then** INSERT ... ON CONFLICT DO NOTHING → 0 rows affected
**And** pg_notify still triggered (Postgres trigger fires on INSERT — but with CONFLICT, trigger may or may not fire; tests verify Postgres semantics)
**And** Ack returned (processed: true) — idempotency
**And** No error

**Note**: if Postgres BEFORE/AFTER trigger fires on conflict-no-op (it doesn't by default), we explicitly use `BEFORE INSERT` to detect existing-row → exit without NOTIFY. Test verifies no extra NOTIFY on conflict.

#### Сценарий 8-35: Api-gateway down — drainer continues webhook delivery

**ID**: `8-35`

**Given** Api-gateway internal endpoint unavailable (network partition / pod down)

**When** Drainer attempts ReceiveCaepEvent

**Then** gRPC call fails after 3 sync-retries (P8-D18: 100ms + 500ms + 2s = 2.6s total)
**And** Audit `caep.intra_cluster_receiver_failed` (CRITICAL)
**And** Slack alert to `#security-ops`
**And** Drainer **continues** webhook delivery (independent path — webhook subscribers still notified)
**And** Caep_outbox event status reflects webhook outcome only
**And** Session-jti invalidation **deferred** until api-gateway recovers (max 5s of stale-cache window per design §5.2)

### 6.8 Event-types coverage (5 scenarios)

#### Сценарий 8-36: session-revoked emit (admin force-logout)

**ID**: `8-36`

**Given** Admin clicks "Force logout user usr_alice" in UI

**When** kacho-iam handler:
  - revoke active access_bindings (set status=REVOKED)
  - emit caep_outbox row: event_type=session-revoked, subject_id=usr_alice, payload={"reason":"admin_force_logout","token_jti":"jti_xxx","revoked_by":"usr_admin_bob"}
  - call InternalCaepReceiverService

**Then** Subscribers subscribed to session-revoked receive SET with that payload
**And** Api-gateway adds jti_xxx to session_revocations
**And** Audit emit at each step
**And** All subscribed subscribers (across all matching subscribers) get the event

#### Сценарий 8-37: token-claims-change emit (FGA tuple revoke)

**ID**: `8-37`

**Given** Phase 3 FGA-tuple-deletion handler runs (e.g., access_binding REVOKED)
**And** Emits caep_outbox row: event_type=token-claims-change, subject_id=usr_alice, payload={"removed_bindings":["acb_xyz"]}

**When** Drainer processes

**Then** SET delivered to subscribed subscribers
**And** Subscribers receive event with removed_bindings claim
**And** Subscribers can update their cached principal claims
**And** Api-gateway intra-cluster: token-claims-change also triggers session_revocations INSERT (per design §5.2 — claim changes invalidate token jti)

#### Сценарий 8-38: credential-change emit (Passkey added)

**ID**: `8-38`

**Given** User adds new Passkey via Kratos webhook
**And** Phase 6 SCIM handler emits caep_outbox: event_type=credential-change, subject_id=usr_alice, payload={"credential_type":"webauthn","action":"added","credential_id":"cred_xxx"}

**When** Drainer processes

**Then** Subscribers subscribed to credential-change receive SET
**And** Api-gateway intra-cluster: depending on credential-change policy (Phase 8 conservative — invalidate all sessions for this user → triggers query `UPDATE session_revocations` for all active jti of user)

**Note**: Phase 8 emit pattern — credential-change includes optional bulk-invalidation hint. Conservative default: revoke only modified credential's sessions. Aggressive option (configurable per-tenant) — revoke all. Phase 8 implements conservative.

#### Сценарий 8-39: assurance-level-change emit (ACR step-down)

**ID**: `8-39`

**Given** User's MFA was de-enrolled (acr drops from 2 to 1)
**And** Phase 7 / Phase 2 handler emits: event_type=assurance-level-change, payload={"old_acr":"2","new_acr":"1","reason":"mfa_removed"}

**When** Drainer

**Then** Subscribers receive SET
**And** Subscribers can downgrade their assurance assumptions
**And** Api-gateway: assurance-level-change does NOT trigger jti invalidation (claim, not revocation; per OpenID CAEP semantics)

#### Сценарий 8-40: device-compliance-change emit (placeholder Phase 12)

**ID**: `8-40`

**Given** Phase 12 MDM emits via API: event_type=device-compliance-change, payload={"old_status":"attested","new_status":"partial","device_id":"dev_xxx"}
**And** Phase 8 has registered the URI in canonical CHECK constraint

**When** Drainer processes

**Then** Subscribers subscribed to device-compliance-change receive SET
**And** Drainer handles same as other event_types (no special logic)
**And** Phase 8 emits zero rows of this type in normal flow — placeholder for Phase 12

### 6.9 Subscriber-side replay protection (3 scenarios)

#### Сценарий 8-41: Drainer never re-uses jti within same retry-chain

**ID**: `8-41`

**Given** Caep_outbox event_id=evt_yyy, jti generated on first attempt = jti_aaa
**And** First attempt 503 → retry

**When** Drainer attempts 2

**Then** Second SET has SAME jti=jti_aaa (NOT regenerated)
**And** Subscriber dedup-by-jti recognises replay → returns 409 (or 200 idempotent — tests use mock that returns 409)
**And** Drainer treats 409 as "already-delivered" → marks status='delivered' (per P8-D8)

**Implementation**: jti stored in caep_delivery_attempts.jti column (Phase 8 migration 0022); first attempt generates UUIDv7, retries reuse.

#### Сценарий 8-42: Subscriber-side dedup window — same jti seen twice in 2 min → 409

**ID**: `8-42`

**Given** Mock subscriber implements 2-min sliding-window dedup cache (per design §5.2)
**And** Drainer delivers jti_aaa at T=0, mock returns 200, dedup cache now contains jti_aaa
**And** At T=30s: drainer (buggy or due to crash recovery) re-delivers SET with same jti_aaa

**When** Mock receives second POST

**Then** Mock returns HTTP 409 Conflict with body `{"error":"duplicate_event","jti":"jti_aaa"}`
**And** Drainer interprets 409 as "already-delivered" → status='delivered' (CAS UPDATE)
**And** Audit `caep.delivery_subscriber_dedup` (info-level)
**And** No retry-loop

#### Сценарий 8-43: Different events have different jtis (uniqueness guarantee)

**ID**: `8-43`

**Given** Two independent events: evt_aaa and evt_bbb (same account, same subscriber)

**When** Drainer processes both

**Then** Two SETs delivered with distinct jtis (`uuidv7` randomness — collision-free probabilistically)
**And** Subscriber dedup-cache contains both
**And** Test asserts: collected jtis distinct, both events delivered successfully

### 6.10 SET signature verification (4 scenarios)

#### Сценарий 8-44: Subscriber verifies SET with JWKS — success

**ID**: `8-44`

**Given** Subscriber implements RFC 8417 verification:
  - Fetch `https://api.kacho.cloud/.well-known/jwks.json` (Hydra-published JWKS)
  - Parse SET header, get `kid`
  - Find matching JWK
  - Verify signature with `kid_v3` public key
**And** Drainer delivers SET signed with `kid_v3`

**When** Subscriber verifies

**Then** Signature valid
**And** Subscriber proceeds to dedup-by-jti + process event
**And** Mock subscriber explicitly performs verification (test-grade)
**And** Audit on subscriber side: `set.verified`

#### Сценарий 8-45: Subscriber rejects SET signed with retired key — outside grace window

**ID**: `8-45`

**Given** Key `kid_v2` was retired 25 hours ago (outside 24h grace; JWKS no longer publishes it)
**And** Drainer's signer-cache (bug) still has `kid_v2` (theoretical — TTL should evict in 5min; test simulates via direct cache inject)

**When** Drainer signs with `kid_v2` and delivers

**Then** Subscriber verification fails: no `kid_v2` in JWKS
**And** Subscriber returns 401 Unauthorized
**And** Drainer treats as failed_terminal (P8-D7)
**And** Internal bug-alert fires (drainer should not use retired keys)

#### Сценарий 8-46: Subscriber rejects unsigned SET (alg=none) — defence in depth

**ID**: `8-46`

**Given** Mock subscriber attempts to test attack: drainer-generated SET artificially has alg=none (manual mode for tests)

**When** Subscriber verifies

**Then** Subscriber returns 401, message `"unsupported alg: none"`
**And** Mock library `corelib/set/verifier.go` explicitly rejects `alg=none`
**And** Same check on real subscriber: SDK level
**And** Defence-in-depth: kacho-iam-side `corelib/set/signer.go` rejects alg=none on SIGN side too (no way to even generate such SET unless bypass)

#### Сценарий 8-47: Subscriber rejects SET with invalid signature

**ID**: `8-47`

**Given** Drainer's mock-signer (test mode) signs with WRONG private key (test fixture; key doesn't match published JWKS)

**When** Subscriber verifies

**Then** Signature verification fails
**And** Subscriber returns 401
**And** Drainer marks failed_terminal
**And** Alert: subscriber may be under attack (someone forged kacho-signing-key) — security-team notified

### 6.11 k6 latency SLA (4 scenarios)

#### Сценарий 8-48: Steady-state — 100 events/min × 10 subscribers × 30 min

**ID**: `8-48`

**Given** k6 load test: `tests/k6/caep_revoke_latency_kac127.js`
**And** 10 mock-subscriber containers (Go HTTP servers returning 200)
**And** kacho-iam drainer pool=8, rate-limit=100/min per subscriber
**And** k6 inserts 100 caep_outbox rows per minute uniformly (each event subscribes to 1 of 10 subscribers — round-robin)

**When** Test runs for 30 minutes

**Then** All 3000 events have status='delivered'
**And** p95 (insert_at → subscriber_received_at): ≤ 2 seconds
**And** p99 same metric: ≤ 5 seconds
**And** p99 end-to-end (insert_at → all subscribers received): ≤ 10 seconds
**And** Drainer pick latency p95 ≤ 50ms
**And** Test report committed to `docs/qa/phase8-k6-revoke-latency-2026-MM-DD.md`

#### Сценарий 8-49: Burst load — 1000 events in 30 seconds

**ID**: `8-49`

**Given** Sudden burst: 1000 events inserted in 30 sec (3300 events/min instantaneous)
**And** 10 subscribers, each rate-limited 100/min

**When** Drainer processes

**Then** First 1000 events (10 subscribers × 100/min = 1000/min capacity): delivered within minute 1
**And** No event loss
**And** Drainer queue depth peaks at ~700 then drains
**And** No DB lock contention (FOR UPDATE SKIP LOCKED keeps it parallel)

#### Сценарий 8-50: Subscriber slow — high latency

**ID**: `8-50`

**Given** Mock subscriber returns 200 but adds artificial 5-second delay
**And** 100 events/min flow

**When** Test runs

**Then** Each event delivered (5s subscriber-side delay)
**And** Drainer thread waits up to 10s (timeout), then proceeds
**And** Throughput drops but no loss
**And** p99 latency reflects 5s+ delay (still within drainer timeout)

#### Сценарий 8-51: Drainer pod restart mid-load — no event loss

**ID**: `8-51`

**Given** Steady load 100 events/min
**And** Drainer pod receives SIGTERM at minute 15

**When** Pod restarts (new pod scheduled within 30 sec)

**Then** In-flight events (status='in_flight') remain in DB
**And** New drainer pod picks them up via FOR UPDATE SKIP LOCKED (existing locks released on pod death)
**And** Total event count delivered = 3000 (full 30 min) — zero loss
**And** Restart shows in audit `caep.drainer_restarted` + Prometheus metric

### 6.12 TestDelivery admin tool (3 scenarios)

#### Сценарий 8-52: TestDelivery synthetic event delivered

**ID**: `8-52`

**Given** Subscriber `cps_xxx` exists, endpoint mock returns 200
**And** Admin actor with permission `iam.caep_subscribers.test_delivery`

**When** POST `/iam/v1/caepSubscribers/cps_xxx:testDelivery`

**Then** Inline response within 10 seconds: `{ http_status: 200, latency_ms: <observed>, response_preview: "<first 256 bytes>", attempts: 1, jti: "<uuidv7>", set_kid: "kid_v3" }`
**And** Mock subscriber received synthetic event with:
  - event_type from request payload (or `session-revoked` default)
  - subject_id=`tester-synthetic-<uuid>`
  - payload claim `test=true`
  - fresh jti
**And** No caep_outbox row inserted (P8-D16 — bypass outbox)
**And** Audit `iam.caep.test_delivery_invoked` with actor + subscriber_id + result

#### Сценарий 8-53: TestDelivery against broken subscriber — reports error

**ID**: `8-53`

**Given** Subscriber endpoint returns 500
**And** Test invoked

**When** Drainer attempts inline

**Then** Inline response: `{ http_status: 500, latency_ms: <observed>, response_preview: "...", attempts: 1 }`
**And** No retry (single attempt — test is synchronous)
**And** No drainer-loop entry
**And** Admin sees error inline in UI

#### Сценарий 8-54: TestDelivery — signature valid (synthetic uses same signing)

**ID**: `8-54`

**Given** Mock subscriber verifies signature

**When** TestDelivery invoked

**Then** Synthetic SET signed with same active JWKS key (e.g., kid_v3)
**And** Subscriber verification: success
**And** Test mock asserts signature valid in response body

### 6.13 Multi-region failover (3 scenarios)

#### Сценарий 8-55: Phase 8 emit pattern compatible with Phase 11 multi-region

**ID**: `8-55`

**Given** Caep_outbox table designed for multi-region (Phase 11)
**And** Phase 8 single-region setup

**When** Phase 11 deploys secondary region

**Then** Schema unchanged (caep_outbox has no region-affinity column)
**And** Drainer in primary region holds FOR UPDATE SKIP LOCKED — secondary region drainer (when deployed) can pick concurrently
**And** Cross-region replication via Postgres logical replication / Patroni (Phase 11)
**And** Test in Phase 8 verifies SKIP LOCKED concurrency-safe (scenario 8-21 covered)

#### Сценарий 8-56: Primary region down — drainer in secondary takes over

**ID**: `8-56`

**Given** Phase 11 deployed (secondary region)
**And** Primary region drainer pod down
**And** caep_outbox replicated to secondary (logical replication lag ≤ 5s)

**When** Secondary drainer starts processing

**Then** Picks pending events with FOR UPDATE SKIP LOCKED (re-grants released by primary failover)
**And** Total event loss = 0 (logical replication preserved)
**And** SLO temporarily breached (failover latency adds 30-60s) — acceptable for region-down scenario

**Note**: Phase 8 doesn't deploy multi-region; this scenario verifies design-compatibility. Phase 11 acceptance doc has full multi-region tests.

#### Сценарий 8-57: Active-active — both regions deliver, no duplicate

**ID**: `8-57`

**Given** Both regions active (Phase 11)
**And** Same caep_outbox row visible from both via replication

**When** Both drainers attempt FOR UPDATE SKIP LOCKED concurrently

**Then** Postgres lock serialisation: one wins, other skips
**And** Single delivery per event-subscriber pair (no duplicate to subscriber)
**And** Phase 8 design unchanged

### 6.14 Cross-account isolation (3 scenarios)

#### Сценарий 8-58: Account A subscriber receives only Account A events

**ID**: `8-58`

**Given** Subscribers: `cps_a_main` (account=acc_a, event_types=[session-revoked]), `cps_b_main` (account=acc_b, event_types=[session-revoked])
**And** Caep_outbox rows: `evt_a1` (account_id=acc_a), `evt_b1` (account_id=acc_b)

**When** Drainer processes

**Then** `cps_a_main` receives only `evt_a1` (subject_id from acc_a's user; payload from acc_a context)
**And** `cps_b_main` receives only `evt_b1`
**And** Cross-delivery never occurs (DB JOIN filter `WHERE s.account_id = e.account_id` per P8-D17)
**And** Integration test verifies via testcontainer fixtures

#### Сценарий 8-59: Subscriber endpoint sees only subjects from own account

**ID**: `8-59`

**Given** Multi-tenant subscriber endpoint (cps_xxx for acc_a) actually serves multiple tenants
**And** It receives only events from acc_a

**When** Drainer delivers

**Then** All SET-payloads have `subject_id` that maps to acc_a's users (`usr_<id>_acc_a`)
**And** Subscriber side cannot leak acc_b data via this subscriber
**And** Test asserts: 100 events for acc_a delivered, 0 events for acc_b delivered (mock counts both)

#### Сценарий 8-60: Subscriber tries to subscribe to event_type filter on other account → rejected

**ID**: `8-60`

**Given** Tenant `usr_admin_alice` (acc_a admin) attempts to create subscriber: `POST /iam/v1/accounts/acc_b/caepSubscribers ...`

**When** OpenFGA Check evaluates `account:acc_b#admin@user:usr_admin_alice` → false

**Then** HTTP 403 PermissionDenied
**And** No row inserted
**And** Audit `iam.caep_subscriber.create_denied`
**And** Defence: RBAC at handler-layer; even if bypassed at handler (bug), DB has no FK constraint preventing — so RBAC is the line

---

## 7. Definition of Done (Phase 8)

### Functional

- [ ] **CaepSubscriber CRUD** — Create/Update/Delete/Get/List + TestDelivery public RPC реализованы, HTTPS validation enforced (DB CHECK + service), signing_kid validation against active JWKS, event_types whitelist enforced, immutable fields via UpdateMask, RBAC `iam.caep_subscribers.upsert` on Account per OpenFGA.
- [ ] **SET signing (corelib/set)** — RFC 8417 JWT; alg whitelist {RS256, ES256, EdDSA}; kid from active JWKS key; signer-cache 5min TTL; rejection of unsigned / `none` alg / unsupported alg; subscriber-side verification reference impl in test SDK.
- [ ] **Caep drainer** — worker pool N=8 (configurable env `KACHO_IAM_CAEP_DRAINER_POOL_SIZE`); FOR UPDATE SKIP LOCKED claim atomicity; CAS state machine pending→in_flight→delivered/failed_terminal; ULID event IDs; ORDER BY (next_attempt_at, id) FIFO; partial index for scan perf.
- [ ] **Webhook delivery** — HTTPS strict TLS (production env); timeout 10s; multi-subscriber broadcast via caep_delivery_attempts child table; 2xx → delivered; 4xx (except 408/429) → immediate failed_terminal; 5xx/408/429/timeout → backoff retry.
- [ ] **Backoff schedule** — fixed [1s, 5s, 30s, 5min, 1h, 6h, 24h]; max 8 attempts total; after 8 → failed_terminal + admin Slack alert.
- [ ] **Per-subscriber rate-limit** — token-bucket 100 events/min (configurable env `KACHO_IAM_CAEP_RATE_LIMIT_PER_MIN`); defer-on-overflow (next_attempt_at += 60s); zero event loss.
- [ ] **Auto-disable** — 3 consecutive failed_terminal → `caep_subscribers.enabled=false` + email + audit.
- [ ] **Internal CAEP receiver** — `InternalCaepReceiverService.ReceiveCaepEvent` on api-gateway internal port; idempotent INSERT into session_revocations; pg_notify trigger for cross-pod cache invalidation ≤ 1s p99.
- [ ] **5 canonical event-types** — session-revoked, token-claims-change, credential-change, assurance-level-change, device-compliance-change; CHECK constraint enforces only canonical URIs in caep_outbox.
- [ ] **TestDelivery** — admin action-method; bypasses outbox; synthetic event; inline response with http_status, latency_ms, response_preview, jti.

### DB / migrations

- [ ] **Migration 0022** (`kacho-iam/internal/migrations/0022_kac127_phase8_caep_indexes.sql`):
  - CREATE TABLE `caep_delivery_attempts` (per-subscriber child table — P8-D14).
  - CREATE INDEX `caep_outbox_pending_idx` ON `caep_outbox(next_attempt_at) WHERE status IN ('pending','in_flight')` (P8-D15).
  - ALTER TABLE caep_subscribers ADD COLUMN `consecutive_failed_terminal_count INT DEFAULT 0`, ADD COLUMN `last_disabled_at TIMESTAMPTZ`, ADD COLUMN `last_disabled_reason TEXT`.
  - ALTER TABLE caep_subscribers ADD CONSTRAINT `caep_subscribers_event_types_canonical_chk` CHECK `event_types <@ ARRAY[...]` (extends Phase 1 less-strict CHECK).
  - ALTER TABLE caep_subscribers ADD CONSTRAINT (partial UNIQUE) `caep_subscribers_no_dup_active_endpoint_chk` on `(account_id, endpoint_url, signing_kid) WHERE enabled = true` (P8-D12).
  - ALTER TABLE caep_outbox ADD COLUMN `delivered_at TIMESTAMPTZ`, ADD COLUMN `failed_terminal_at TIMESTAMPTZ`, ADD COLUMN `last_error TEXT`.
  - CREATE OR REPLACE FUNCTION `notify_session_revoked()` + TRIGGER on `session_revocations` AFTER INSERT.
- [ ] All Phase 1 migrations (`0013`, `0014`) unmodified (per запрет #5).

### Integration tests (testcontainers Postgres)

- [ ] `kacho-iam/internal/repo/kacho/pg/caep_outbox_repo_test.go`:
  - Race test: concurrent drainer FOR UPDATE SKIP LOCKED — exactly one worker picks each row.
  - CAS test: status transitions pending→in_flight, in_flight→delivered, in_flight→failed_terminal — race-safe.
  - Partial index: query plan uses `caep_outbox_pending_idx` (EXPLAIN ANALYZE).
- [ ] `kacho-iam/internal/repo/kacho/pg/caep_subscribers_repo_test.go`:
  - Partial UNIQUE violation: concurrent Create same (account, endpoint, kid) — exactly one wins.
  - Phase 1 CHECK enforcement: http:// rejected (23514).
- [ ] `kacho-iam/internal/apps/kacho/jobs/caep_drainer_integration_test.go`:
  - Happy delivery (mock subscriber returns 200) ≤ 2s.
  - Retry sequence (mock returns 503 then 200) — backoff timing correct.
  - 4xx terminal (mock returns 404) — single attempt → failed_terminal.
  - Rate-limit defer (mock receives ≤ 100/min when 150 events injected).
  - Auto-disable (3 consecutive failed_terminal → enabled=false).
- [ ] `kacho-iam/internal/apps/kacho/jobs/caep_rate_limiter_test.go`:
  - Token-bucket capacity 100; 100 events allowed in burst; 101st delayed.
- [ ] `kacho-corelib/set/signer_test.go`:
  - Sign+verify round-trip (RS256, ES256, EdDSA).
  - Reject alg=none.
  - Reject HS256.
  - Verify with rotated key (kid_v3 → kid_v4 transition).
- [ ] `kacho-corelib/caep/payload_test.go`:
  - Build helpers produce correct OpenID CAEP shapes.
- [ ] `kacho-api-gateway/internal/caep/receiver_integration_test.go`:
  - ReceiveCaepEvent → INSERT session_revocations.
  - Idempotent (same jti twice).
  - LISTEN/NOTIFY: 2 pods, NOTIFY received by both ≤ 1s.
  - Cache invalidation: cached entry evicted on NOTIFY.

### Newman cases (per запрет #11)

- [ ] `kacho-test/tests/newman/cases/iam_caep_subscriber_create_happy.py`
- [ ] `kacho-test/tests/newman/cases/iam_caep_subscriber_create_invalid_url_400.py`
- [ ] `kacho-test/tests/newman/cases/iam_caep_subscriber_create_invalid_kid_400.py`
- [ ] `kacho-test/tests/newman/cases/iam_caep_subscriber_create_invalid_event_types_400.py`
- [ ] `kacho-test/tests/newman/cases/iam_caep_subscriber_update_immutable_field_400.py`
- [ ] `kacho-test/tests/newman/cases/iam_caep_subscriber_update_toggle_enabled.py`
- [ ] `kacho-test/tests/newman/cases/iam_caep_subscriber_delete_cascade.py`
- [ ] `kacho-test/tests/newman/cases/iam_caep_subscriber_list_per_account_rbac.py`
- [ ] `kacho-test/tests/newman/cases/iam_caep_subscriber_test_delivery_happy.py`
- [ ] `kacho-test/tests/newman/cases/iam_caep_subscriber_test_delivery_broken_subscriber.py`
- [ ] `kacho-test/tests/newman/cases/iam_caep_cross_account_isolation.py`

### k6 load test

- [ ] `kacho-test/tests/k6/caep_revoke_latency_kac127.js` — fully implemented; runs in `make k6-test`.
- [ ] Test report `docs/qa/phase8-k6-revoke-latency-2026-MM-DD.md` committed with:
  - p95 webhook delivery ≤ 2s — pass/fail status.
  - p99 webhook delivery ≤ 5s — pass/fail.
  - p99 end-to-end (insert → all subscribers received) ≤ 10s — pass/fail.
  - Sustained 30-min run with 0% loss — pass/fail.
  - DB lock contention metric (drainer pick p95) ≤ 50ms — pass/fail.

### Observability

- [ ] Prometheus metrics (kacho-iam):
  - `caep_drainer_queue_depth_count` — gauge.
  - `caep_drainer_pick_latency_seconds` — histogram.
  - `caep_delivery_attempts_total{result="delivered|in_flight|failed_terminal"}` — counter.
  - `caep_delivery_latency_seconds{subscriber_id}` — histogram (label cardinality bounded by # of subscribers).
  - `caep_subscriber_failure_count{subscriber_id}` — gauge.
  - `caep_rate_limited_total{subscriber_id}` — counter.
  - `caep_signing_key_cache_hit_total / _miss_total` — counters.
- [ ] Prometheus metrics (kacho-api-gateway):
  - `caep_receiver_processed_total` — counter.
  - `caep_listen_notify_latency_seconds` — histogram.
  - `session_revocation_cache_hit / _miss` — counters.
- [ ] Alert rules (`kacho-deploy/prometheus-rules/caep.yaml`):
  - `CAEPDeliveryFailureRate > 5%` over 10 min — critical.
  - `CAEPQueueDepth > 1000` over 5 min — warning.
  - `CAEPp99Latency > 5s` over 10 min — critical (SLO violation).
  - `CAEPSigningKeyMissing` instant — critical (P1 / PagerDuty).

### UI

- [ ] `kacho-ui/src/pages/iam/caep-subscribers/SubscribersListPage.tsx`:
  - List per Account, columns: endpoint_url, event_types, enabled, failure_count, last_success_at, last_failure_at, created_at.
  - Filter by enabled / has_failures.
  - Sort by created_at DESC default.
- [ ] `kacho-ui/src/pages/iam/caep-subscribers/CreateSubscriberModal.tsx`:
  - Form with endpoint_url validation (https:// regex client-side).
  - signing_kid dropdown populated from `kacho.iam.v1.JwksKeyService.ListActiveKeys`.
  - expected_audience text input.
  - event_types multi-select from 5 canonical (sorted alphabetically by URI shortname).
- [ ] `kacho-ui/src/pages/iam/caep-subscribers/SubscriberDetailPage.tsx`:
  - Show all fields including failure history (last_failure_at + last_failure_reason).
  - TestDelivery button — inline result panel with http_status, latency_ms, response_preview, jti.
  - Enable/Disable toggle with confirmation modal.
  - Delete button with double-confirm.
- [ ] Playwright e2e: `kacho-ui/tests/e2e/iam-caep-subscriber-crud.spec.ts` — full CRUD + test-delivery flow.

### Documentation (vault)

- [ ] `obsidian/kacho/resources/iam-caep-subscriber.md` — extended из Phase 1 stub (полный CRUD, Phase 8 fields).
- [ ] `obsidian/kacho/resources/iam-caep-outbox-event.md` — new.
- [ ] `obsidian/kacho/resources/iam-caep-delivery-attempt.md` — new (child table).
- [ ] `obsidian/kacho/resources/iam-session-revocation.md` — extended (LISTEN/NOTIFY contract + TTL semantics).
- [ ] `obsidian/kacho/rpc/iam-caep-subscriber-service.md` — new.
- [ ] `obsidian/kacho/rpc/apigw-internal-caep-receiver-service.md` — new, internal-only-помечен.
- [ ] `obsidian/kacho/packages/corelib-set.md` — new.
- [ ] `obsidian/kacho/packages/corelib-caep.md` — new.
- [ ] `obsidian/kacho/packages/iam-jobs-caep-drainer.md` — new.
- [ ] `obsidian/kacho/packages/apigw-caep-receiver.md` — new.
- [ ] `obsidian/kacho/edges/iam-to-caep-subscriber-webhook.md` — new.
- [ ] `obsidian/kacho/edges/iam-to-apigw-internal-caep.md` — new.
- [ ] `obsidian/kacho/edges/apigw-to-postgres-listen-session-revoked.md` — new.
- [ ] `obsidian/kacho/KAC/KAC-127.md` — Phase 8 PR-list updated.

### Cross-repo verification

- [ ] kacho-proto: `buf lint` зелёный; `buf breaking` зелёный (Phase 1 wire-shape compatible).
- [ ] kacho-corelib: unit tests pass; no `replace` direction violations.
- [ ] kacho-iam: integration tests pass; migration `0022` reversible (verifies `migrate down`).
- [ ] kacho-api-gateway: integration tests pass; internal receiver registered ONLY на internal mux.
- [ ] kacho-ui: build green; Playwright e2e зелёный.
- [ ] kacho-test: newman cases pass on dev stand; k6 report committed.
- [ ] kacho-deploy: helm chart updated; secrets templated (caep-set-signing-key — pointer к existing JWKS-pool entry); Prometheus rules deployed.

### Compliance

- [ ] SET shape verified against RFC 8417 §2.2 (events claim required; structure correct).
- [ ] OpenID CAEP 1.0 event-type URIs verified against spec (exact canonical strings).
- [ ] No `yandex` mentions anywhere (запрет #2 grep-check).
- [ ] No ORM (запрет #3) — only sqlc + handwritten pgx + stdlib net/http.
- [ ] No cross-DB cascade (запрет #4).
- [ ] Phase 1 migrations не модифицированы (запрет #5).
- [ ] InternalCaepReceiverService not on public mux (запрет #6 — grep-check `kacho-api-gateway/internal/restmux/mux.go`).
- [ ] No broker (запрет #7) — only Postgres pgx pubsub.
- [ ] DB-per-service (запрет #8) — single cross-service DB-access (api-gateway → kacho_iam.session_revocations) documented + read-only role.
- [ ] All mutations async returning Operation (запрет #9).
- [ ] DB-level invariants for within-service refs (запрет #10) verified via integration race tests.
- [ ] All Phase 8 PRs include integration tests + newman cases (запрет #11).

---

## 8. Cross-repo PR-chain

Order (per topological build-dependency graph + plan §8.6):

1. **`PRO-Robotech/kacho-proto`** — PR `[KAC-XXX] proto: CAEP subscriber service + internal receiver`
   - Files: `proto/kacho/iam/v1/caep_subscriber.proto`, `proto/kacho/iam/internal/v1/internal_caep_receiver.proto`
   - Acceptance: `buf lint` + `buf breaking` green; Go stubs regenerated and committed.
   - Reviewer: `proto-api-reviewer`.
2. **`PRO-Robotech/kacho-corelib`** — PR `[KAC-XXX] corelib: SET signer + CAEP event helpers`
   - Files: `set/{signer,verifier,set_testing}.go`, `caep/{event_types,payload}.go`, unit tests.
   - Acceptance: unit tests green.
   - Reviewer: `go-style-reviewer`.
3. **`PRO-Robotech/kacho-iam`** — PR `[KAC-XXX] iam: CAEP drainer + SubscriberService + migration 0022`
   - Files: see §5 Task 8.2.
   - Acceptance: integration tests (testcontainers) green; race tests pass; migration reversible.
   - Reviewer: `go-style-reviewer` + `db-architect-reviewer`.
4. **`PRO-Robotech/kacho-api-gateway`** — PR `[KAC-XXX] apigw: Internal CAEP receiver + session-revoke cache + LISTEN/NOTIFY`
   - Files: see §5 Task 8.3.
   - Acceptance: integration tests; cross-pod NOTIFY < 1s p99 verified.
   - Reviewer: `go-style-reviewer` + `api-gateway-registrar`.
5. **`PRO-Robotech/kacho-ui`** — PR `[KAC-XXX] ui: CAEP subscriber registry pages`
   - Files: see §5 Task 8.4.
   - Acceptance: Playwright e2e green.
   - Reviewer: UI team.
6. **`PRO-Robotech/kacho-test`** — PR `[KAC-XXX] test: newman CAEP cases + k6 latency`
   - Files: see §6.11 + §7 Newman cases.
   - Acceptance: k6 report committed; newman green on dev.
   - Reviewer: `qa-test-engineer`.
7. **`PRO-Robotech/kacho-deploy`** — PR `[KAC-XXX] deploy: helm values + secrets + Prometheus rules`
   - Files: helm values, sealed-secrets templates, prometheus-rules/caep.yaml.
   - Acceptance: `helm template` green, deployed на dev stand, e2e smoke green.
   - Reviewer: SRE / `qa-test-engineer`.
8. **`PRO-Robotech/kacho-workspace`** — PR `[KAC-XXX] vault: Phase 8 CAEP push entries`
   - Files: vault entries §7 Documentation.
   - Acceptance: file-size discipline (≤ 3KB each); links valid.
   - Reviewer: lead.

Each PR ссылается на YouTrack KAC-127 (Phase 8 subtask); subtask ticket transitions To do → In Progress (PR opened) → Test (all merged, e2e green) → Done (vault updated).

---

## 9. Out of scope (явно)

Эти пункты — **explicitly не в Phase 8** (явно перенесены в Phases 9-13 одного эпика; **не "wontfix" / "later"**):

- **Audit pipeline (Kafka + ClickHouse + S3 + HSM signing + SIEM)** — Phase 9. Phase 8 пишет `caep.delivery_succeeded` / `caep.delivery_failed` / `caep.signing_key_missing` rows в `audit_outbox` (Phase 1 schema); drainer для audit_outbox — Phase 9. Тесты Phase 8 проверяют row appeared в audit_outbox с правильным event-type, но **не** Kafka delivery.
- **SPIFFE/SPIRE in-cluster mTLS** — Phase 10. Phase 8 outbound webhook к subscriber'у — plain TLS (kacho cluster egress + system CAs). Phase 10 deploys mesh-mTLS via Cilium — затронет внутрикластерный путь kacho-iam → kacho-api-gateway (intra-cluster gRPC), не внешний webhook.
- **Multi-region active-active CAEP** — Phase 11. Phase 8 design эмит-compatible (см. 8-55, 8-56, 8-57), но **drainer single-region**. Phase 11 deploys secondary region + Patroni / logical replication.
- **HSM-backed signing keys** — Phase 12. Phase 8 stores private key encrypted via KMS data-key (env-based encryption); decrypt on hot-path. Phase 12 migrates to HSM-only signing (signing operation в HSM, private key never exits HSM).
- **OpenID Shared Signals Framework (SSF) full compliance** — Phase 13. Phase 8 implements SET signing (RFC 8417) + CAEP event-types (OpenID CAEP 1.0). SSF additionally requires Stream Configuration Endpoint, Status Endpoint, Verification, Spec-discovery — Phase 13.
- **Subscriber inbound mode** (kacho-iam **receives** events from external IdP federation) — out of scope KAC-127; potential KAC-130 future epic.
- **PASETO v4 SET** — design doc §5 mentions "PASETO v4 ready"; Phase 8 ships RS256/ES256/EdDSA only. PASETO addition — Phase 13 (если security audit recommends).
- **Per-tenant rate-limit aggregate** (across all subscribers of an account) — P8-D6 recommended Phase 11 enhancement (requires cross-pod aggregation — Redis). Phase 8 per-subscriber only.
- **Per-subscriber custom backoff schedule** (subscriber configures own retry policy) — current Phase 8 is one-size-fits-all `[1s, 5s, 30s, 5min, 1h, 6h, 24h]`. Custom schedule — Phase 12 enhancement если pentest / customer feedback indicates.
- **Subscriber UI for receiving (kacho-ui-side mock subscriber)** — out of scope; subscribers are external clients managing own infrastructure.

---

## 10. Open Questions resolved

Все resolved до начала кодирования (per round 2 "no strict backward-compat"):

- **Q1**: SET shape — signed-only JWT (P8-D1) vs signed+encrypted? — **A**: signed-only RFC 8417, content-type `application/secevent+jwt`. No JWE.
- **Q2**: endpoint_url scheme — http:// allowed для dev? — **A**: HTTPS-only enforced в DB CHECK (P8-D2). Dev можеt использовать localhost-tunneling без modifying production CHECK.
- **Q3**: Signing key — shared с Hydra JWT pool или dedicated? — **A**: shared (P8-D3) — subscriber фетчит one JWKS, rotation policy unified. Phase 12 может перейти на dedicated, политика round 2.
- **Q4**: Algorithm whitelist — какие? — **A**: RS256, ES256, EdDSA (P8-D4). HS256, none, deprecated algs rejected.
- **Q5**: Backoff schedule — fixed или adaptive? — **A**: fixed `[1s, 5s, 30s, 5min, 1h, 6h, 24h]` (P8-D5). Retry-After header ignored Phase 8.
- **Q6**: Rate-limit — drop or defer? — **A**: defer (P8-D6) — token-bucket, over-limit → `next_attempt_at += 60s`. Zero loss.
- **Q7**: 4xx semantics — retry или terminal? — **A**: 408 + 429 retry; others terminal (P8-D7).
- **Q8**: Replay protection — drainer or subscriber side? — **A**: at-least-once + subscriber dedup-by-jti 2-min window (P8-D8); drainer minimises duplicates но не guarantees exactly-once.
- **Q9**: Api-gateway → kacho_iam direct DB connection — acceptable? — **A**: read-only role (P8-D9) для LISTEN only; primary path through gRPC RPC.
- **Q10**: Auto-disable threshold — N consecutive failed_terminal? — **A**: 3 consecutive (P8-D10).
- **Q11**: Event-types — minimum subset или full? — **A**: full 5 canonical OpenID CAEP URIs (P8-D11).
- **Q12**: Subscriber UNIQUE constraint — strict или partial? — **A**: partial `WHERE enabled=true` (P8-D12). Allows disabled-history.
- **Q13**: Outbox event ID — UUID or ULID? — **A**: ULID (P8-D13) — lexicographically sortable, more compact, no prefix needed (internal-only).
- **Q14**: Multi-subscriber state — JSONB array or child table? — **A**: child table `caep_delivery_attempts` (P8-D14).
- **Q15**: Index strategy — full или partial? — **A**: partial `WHERE status IN ('pending','in_flight')` (P8-D15).
- **Q16**: TestDelivery — through outbox or bypass? — **A**: bypass (P8-D16).
- **Q17**: Cross-account isolation — DB or software filter? — **A**: DB-level JOIN (P8-D17).
- **Q18**: Internal receiver — sync or async? — **A**: sync with retry + fail-loud audit (P8-D18). Webhook path independent.
- **Q19**: TLS verification on webhook — strict or relaxed? — **A**: strict в production env (P8-D19); dev only allows insecure-skip-verify.
- **Q20**: Webhook timeout — short or long? — **A**: 10s total (P8-D20).
- **Q21**: How does drainer claim event before HTTP POST? — **A**: 2 atomic UPDATEs — first claims (`status='in_flight'`, `attempts++`), then per-subscriber attempt-row with INSERT/UPSERT.
- **Q22**: How does drainer handle pod crash mid-HTTP? — **A**: row remains `status='in_flight'`; FOR UPDATE SKIP LOCKED-grant released on pod death; next drainer picks the row by `next_attempt_at <= now()` after backoff window. Idempotency via `jti` reuse + subscriber dedup.
- **Q23**: How does test verify "≤ 10s end-to-end"? — **A**: k6 records `insert_at` timestamp (in caep_outbox) and `received_at` in mock-subscriber; calculates delta; histogram p99 ≤ 10s asserted at end of 30-min run.
- **Q24**: What happens if 0 active JWKS keys exist? — **A**: scenario 8-04 — drainer marks event in_flight + backoff, audit critical, PagerDuty alert. Self-recoverable when admin adds key.
- **Q25**: What if subscriber endpoint URL DNS resolves to private IP (SSRF defence)? — **A**: drainer's HTTP client должен reject `127.0.0.0/8`, `10.0.0.0/8`, `192.168.0.0/16`, `169.254.169.254/32` (AWS metadata IMDS) in production. Phase 8 ship — yes, via `internal/clients/http_safe_dialer.go` (Go stdlib http.Transport.DialContext custom). Tests via fixture.
- **Q26**: ROW LOCK contention при large queue? — **A**: FOR UPDATE SKIP LOCKED — Postgres specifically designed для this; integration test (k6) verifies under load.

---

> **Reviewer focus**: P8-D9 (cross-service DB-LISTEN) — самая нестандартная decision; в design doc обоснована но дополнительный взгляд через `db-architect-reviewer`. P8-D14 (multi-subscriber semantics + child table) — затрагивает aggregate `caep_outbox.status` semantics, проверь что aggregate sees-all-children корректно. P8-D17 (cross-account isolation на DB-level JOIN) — security-critical, integration test 8-58/8-59/8-60 необходимы (НЕ только unit). SET shape (P8-D1, P8-D4) — RFC 8417 + OpenID CAEP 1.0 compliance; запросы к `proto-api-reviewer` если будут сомнения относительно canonical URIs.

#kacho-iam #kacho-api-gateway #kacho-proto #kacho-corelib #caep #set #rfc-8417 #openid #kac-127 #phase-8 #acceptance
