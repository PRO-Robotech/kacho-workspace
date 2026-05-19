# Sub-phase 3.1 — IAM Foundation (KAC-127 / YT KAC-123) — Acceptance

> **Status**: DRAFT — awaiting `acceptance-reviewer` APPROVED.
> **Date**: 2026-05-19
> **YouTrack**: [KAC-123](https://prorobotech.youtrack.cloud/issue/KAC-123) — production-ready next-gen IAM (vault-label `KAC-127`).
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer` (gate per запрет #1, workspace `CLAUDE.md`).
> **Design doc**: `docs/superpowers/specs/2026-05-19-iam-prod-ready-next-gen-design.md` (Decision Log §1, Identity Model §3, OpenFGA v2 §4, Workload Identity §6, PIM/JIT §11, DoD §17).
> **Phase position**: §16 design doc "Migration plan", **Phase 1 of 13**.
> **Target repos**: `PRO-Robotech/kacho-proto` (proto + plugin + catalog) → `PRO-Robotech/kacho-corelib` (helpers, если потребуются) → `PRO-Robotech/kacho-iam` (миграции, domain, repo, seed).
> **Target DB**: `kacho_iam` (схема `kacho_iam`, существующий Postgres logical DB; миграции `0011..0014` поверх baseline KAC-105/108/125).

---

## 0. Преамбула — место этой sub-итерации в epic

Phase 1 — **первый код-производительный кусок KAC-127** (production-ready edition). Здесь
кладётся DB-фундамент под весь дальнейший production IAM:

1. **Identity-граф расширяется** новым top-level singleton'ом `Cluster` (для cluster-admin grants
   и emergency `break_glass`), опциональным `Organization` (B2B tier с SCIM/SAML/billing), и
   рефакторингом `Role` под multi-scope (cluster / organization / account / project).
2. **AccessBinding** получает lifecycle (`PENDING/ACTIVE/REVOKED`), Conditions overlay
   (ABAC поверх ReBAC), TTL (`expires_at`), и audit-метаданные (`granted_by` / `revoked_by`).
3. **Workload Identity Federation** (Class B, RFC 8693) — таблица `federation_trust_policies`
   для OIDC token exchange c GitHub Actions / AWS IRSA / GCP WIF / GitLab CI и т.д.
4. **PIM/JIT eligibility** — таблица `access_bindings_jit_eligibility` для self-elevation
   с approval workflow.
5. **CAEP outbox + subscriber registry + session_revocations** — стартует pipeline real-time
   revoke (RFC 8417 SET). Drainer + webhook delivery — Phase 8; здесь только storage.
6. **Audit outbox + signing batches + JWKS rotation tracking** — append-only event log + ключи
   подписи. Kafka producer + ClickHouse consumer + S3+Glacier writer — Phase 9; здесь только
   storage.
7. **SCIM mapping + GDPR erasure + Access reviews** — таблицы под Phase 6 (SCIM endpoint),
   Phase 7 (JIT + erasure + reviews). Хранение и invariants — здесь.
8. **Permission registry from proto** — новый `protoc-gen-kacho-permissions` plugin парсит
   аннотации `(kacho.iam.authz.permission)` из всех `.proto` в `kacho-proto/proto/kacho/cloud/*/v1/*.proto`,
   эмитит `gen/permission_catalog.json` (commit-ится), `kacho-iam` на старте seed-ит
   `system_role_permissions` (idempotent UPSERT).
9. **Bootstrap seed** — миграция создаёт `cluster_kacho_root` singleton + 2 system-роли
   (`kacho-system.admin` с `*.*.*`, `kacho-system.viewer` read-only); если задан
   `KACHO_IAM_BOOTSTRAP_ROOT_EMAIL` — enqueue FGA-tuple `cluster_admin` через `fga_outbox`.

**Phase 1 НЕ включает** (это Phases 2-13 одного и того же эпика — НЕ "deferred"):
- AuthN flows (Kratos WebAuthn + Hydra DPoP + recovery) — **Phase 2**.
- OpenFGA model v2 deploy + Conditions integration + OPA bundles — **Phase 3**.
- ListObjects integration per-service + cache invalidation — **Phase 4**.
- Federation Exchange RPC (трасты, по которым здесь только storage) + SA Hydra-clients — **Phase 5**.
- SCIM 2.0 endpoint + SAML bridge Boxyhq Jackson + Organization-UI — **Phase 6**.
- ActivateJIT RPC + approval workflow + Access Reviews automation + GDPR erasure cron — **Phase 7**.
- CAEP drainer + SET signing + webhook delivery + retry/backoff — **Phase 8**.
- Kafka audit topic + ClickHouse + S3+Glacier + HSM batch signing + independent verifier — **Phase 9**.
- SPIRE/SPIFFE + Cilium mesh — **Phase 10**.
- Multi-region active-active + `api.kacho.cloud` TLS + Argo CD + Grafana + Alertmanager — **Phase 11**.
- OWASP ASVS L3 conformance + fuzzing + chaos + pentest + bug bounty — **Phase 12**.
- Vault closeout (30+ files) — **Phase 13**.

Phase 1 — это **DB foundation + permission registry generator + bootstrap**, чтобы:
1. Зафиксировать **полную доменную модель** production IAM (все таблицы / FK / CHECK / UNIQUE /
   EXCLUDE / partial-UNIQUE / триггеры для bootstrap row guard'а) — base для всех 12 последующих
   phases.
2. Дать Phase 2 готовую таблицу `oidc_jwks_keys` для JWKS rotation tracking.
3. Дать Phase 3 готовую таблицу `access_binding_conditions` под Conditions overlay и готовое
   расширение `roles` под multi-scope.
4. Дать Phase 5 готовую `federation_trust_policies` для Token Exchange.
5. Дать Phase 7 готовые `access_bindings_jit_eligibility` / `access_reviews` /
   `gdpr_erasure_requests` / `cluster_break_glass_grants`.
6. Дать Phase 8 готовые `caep_outbox` / `caep_subscribers` / `session_revocations`.
7. Дать Phase 9 готовые `audit_outbox` / `audit_signing_batches`.
8. Дать всем сервисам (kacho-vpc / kacho-compute / kacho-loadbalancer / kacho-iam itself) единый
   **источник истины** для permissions — `permission_catalog.json` — генерируемый из proto и
   валидируемый CI на свежесть.

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** (workspace) — кодирование только после `acceptance-reviewer` APPROVED | этот документ — gate; статус выше `DRAFT` до APPROVED |
| **Запрет #2** — НЕ упоминать "yandex" | в коде / схеме / proto / комментариях / env-name не упоминается; стилистически следуем YC по форме error-text (см. §6), но **structurally** Cluster/Organization/multi-scope Role — наш дизайн |
| **Запрет #3** — НЕ ORM | только sqlc + handwritten pgx; CQRS Reader/Writer per use-case |
| **Запрет #4** — НЕ каскад через границу сервиса | все FK внутри `kacho_iam` — `ON DELETE RESTRICT`, кроме `caep_subscribers.account_id` (CASCADE — корректно, оба в `kacho_iam`) и `access_review_items.access_review_id` (CASCADE — child relation внутри одного агрегата); cross-service ref'ы — без FK (`access_bindings.resource_id` — soft-ref на ресурсы других сервисов; запрет #8) |
| **Запрет #5** — НЕ редактировать применённую миграцию | четыре **новых** файла: `0011_kac127_identity_extension.sql` / `0012_kac127_federation_jit_conditions.sql` / `0013_kac127_audit_caep_pipeline.sql` / `0014_kac127_scim_gdpr_reviews_jwks.sql`. Никаких правок в `0001..0010` — все правки через ALTER в новых файлах |
| **Запрет #6** — `Internal.*` НЕ на external TLS endpoint | в Phase 1 кода RPC новых нет, но новые таблицы (cluster_admin_grants / cluster_break_glass_grants / federation_trust_policies / audit_signing_batches / oidc_jwks_keys) — admin-only данные; их API в Phases 3/5/9 пойдёт через `Internal*`-сервисы на 9091, не через 9090 |
| **Запрет #7** — НЕ broker, пока in-process справляется | `audit_outbox` / `caep_outbox` — Postgres outbox tables, drainers (Phases 8-9) пишут в Kafka, но эта Phase сама **никаких broker'ов не поднимает**; в-process LISTEN/NOTIFY достаточно для unit-test'ов |
| **Запрет #8** — DB-per-service | всё в `kacho_iam`; cross-service ссылки (`access_bindings.resource_id`, `federation_trust_policies` external IDs) — без FK, software-validation отложена на consumer'ы |
| **Запрет #9** — async-only мутации | в Phase 1 нет новых RPC, только миграции + plugin + seed; CRUD по новым таблицам появится в последующих phase'ах через `Operation` |
| **Запрет #10** — within-service refs на DB-уровне | **полностью** — никаких software refcheck. Cluster singleton — `CHECK (id = 'cluster_kacho_root')` + trigger `BEFORE INSERT WHEN (SELECT count(*) FROM clusters) >= 1 RAISE`; multi-scope Role — `CHECK (...)` enforces ровно одного non-NULL scope; AccessBinding state machine — `CHECK (status IN (...))` + atomic conditional `UPDATE` для transitions; partial-UNIQUE на (issuer, subject_pattern) в `federation_trust_policies`; CAS на `oidc_jwks_keys.current` (только одна row с `current=true` per `alg`); см. §6 ниже |
| **Запрет #11** — тесты в том же PR | каждый из 4 migration-PR'ов содержит integration-test (testcontainers Postgres + `dbtest.New(t).MigrateAll()`) для всех CHECK / FK / UNIQUE / partial-UNIQUE / триггеров; для plugin-PR (kacho-proto) — golden-test `permission_catalog.json` против fixture-proto; seed-PR — `seed_idempotent_test.go` (применка → второй раз → diff пустой) |

---

## 2. Глоссарий / доменная модель Phase 1 (нормативно)

### 2.1 Сущности, добавляемые в Phase 1

- **Cluster** — singleton (`id='cluster_kacho_root'`). Корень иерархии:
  cluster → organization (optional) → account → project → resource. Используется как
  OpenFGA-объект для `cluster:cluster_kacho_root#system_admin@user:usr_xxx`.
- **ClusterAdminGrant** — permanent grant root-роли. Subject = user или service_account.
  Один источник истины для FGA-tuple `cluster_admin`. Удаление RESTRICT, чтобы не потерять
  audit trail (мягкий revoke — Phase 8 CAEP push, hard-delete только при GDPR erasure).
- **ClusterBreakGlassGrant** — temporary emergency grant (2-person approve, auto-expire ≤2h —
  enforced OPA в Phase 3; в Phase 1 хранение + state machine + `expires_at` NOT NULL).
  Состояния: `AWAITING_APPROVAL_A` → `AWAITING_APPROVAL_B` → `ACTIVE` → `EXPIRED|DENIED|REVOKED`.
- **Organization** — optional B2B tier (NULL для personal-account-only deployments). Несёт
  SCIM endpoint config + SAML metadata URL + domain-claim. Account опционально привязан к
  Organization (нулевой `organization_id` — personal-account, как сейчас).
- **Role (refactored, multi-scope)** — точно один из 4 scopes (mutually exclusive):
    - `is_system=true` + `cluster_id NOT NULL` — system role (`kacho-system.admin`, и т.д.).
    - `is_system=false` + `organization_id NOT NULL` — organization-scoped custom role.
    - `is_system=false` + `account_id NOT NULL` — account-scoped custom (legacy compatible).
    - `is_system=false` + `project_id NOT NULL` — project-scoped custom role.
  Enforced CHECK constraint (см. §6.4 ниже).
- **AccessBinding (extended)** — добавляются `status` ∈ {`PENDING`,`ACTIVE`,`REVOKED`},
  `condition_id` FK → `access_binding_conditions`, `expires_at TIMESTAMPTZ NULL`,
  `granted_by` FK → users, `revoked_at` / `revoked_by`. Lifecycle Phase 1: ACTIVE по default
  (миграция backfill для уже существующих rows); state machine transitions enforced
  conditional UPDATE'ом (Phase 3 service-слой использует — Phase 1 только тестирует
  что CHECK + transitions работают на raw SQL).
- **AccessBindingCondition** — таблица CEL-like выражений (`mfa_fresh`, `non_expired`,
  `source_ip_in_range`, `break_glass_window`, `jit_window`, `business_hours`,
  `device_compliant`). Хранится как `expression TEXT` (имя предиката из whitelisted set
  + параметры в `params JSONB`). CEL-validation — Phase 3 на write через protoc-validate
  embed; Phase 1 — schema-level whitelist через CHECK + JSONB shape.
- **FederationTrustPolicy** — OIDC trust для Token Exchange (RFC 8693). `issuer` +
  `subject_pattern` (regex-validated, **no wildcard `*`** — must be anchored constant or
  controlled regex; CHECK constraint), `audience`, `additional_claims_filter` JSONB,
  `conditions` JSONB (CIDR / business_hours), `max_token_ttl` INTERVAL ≤ 15min,
  `expires_at TIMESTAMPTZ NOT NULL` (max 1y enforced CHECK), `enabled` BOOL.
  UNIQUE (issuer, subject_pattern).
- **AccessBindingJITEligibility** — кто может self-activate какую role над каким resource,
  с `max_duration` (≤ 8h enforced CHECK), `approver_user_id` (NULL — auto-approve),
  `approval_required` BOOL.
- **AuditOutbox** — append-only event log (ULID id, `event_type`, `tenant_account_id`,
  `tenant_org_id NULL`, `event_payload JSONB`, `status` ∈ {`pending`,`in_flight`,`sent`,
  `failed`}). Drainer — Phase 9.
- **CAEPOutbox** — real-time revoke events (ULID id, `event_type` ∈ caep-event-types,
  `subject_id`, `account_id`, `payload JSONB`, `attempts INT`, `status` ∈ {`pending`,
  `in_flight`,`delivered`,`failed_terminal`}, `next_attempt_at`). Drainer — Phase 8.
- **CAEPSubscriber** — webhook registration (per-account). `endpoint_url` CHECK
  `^https://`, `signing_kid`, `expected_audience`, `event_types TEXT[]`, `enabled`,
  `failure_count`. CASCADE при удалении Account.
- **SessionRevocation** — fast lookup table by `token_jti` для api-gateway revoke check.
  Каждая row TTL = `ttl_expires_at` (30d по дефолту); фоновый cron-cleanup в Phase 8.
- **AuditSigningBatch** — HSM-signed batch manifest для tamper-evident S3 cold storage.
  Merkle-chain (`previous_batch_hash NULL` для первой, `batch_hash` для текущей).
  Phase 9 заполняет; Phase 1 только schema.
- **OIDCJwksKey** — JWKS rotation tracking (`kid`, `alg`, `public_key_pem`,
  `private_key_pem_encrypted`, `current BOOL`, `rotated_at`, `expires_at`). CAS-инвариант:
  ровно одна row с `current=true` per `alg`.
- **SCIMUserMapping** — для Phase 6 SCIM endpoint: `(organization_id, scim_external_id)` →
  `user_id`. UNIQUE (organization_id, scim_external_id).
- **GDPRErasureRequest** — Phase 7 pipeline (30d cool-off): `status` ∈ {`cool_off`,
  `in_progress`,`completed`,`cancelled`}, `requested_at`, `cool_off_until`,
  `processed_at`, `rationale`.
- **AccessReview** + **AccessReviewItem** — Phase 7 quarterly recertification:
  AccessReview {account_id, scheduled_at, status, reviewer_user_id}; AccessReviewItem
  {access_review_id, access_binding_id, decision ∈ {keep/revoke/unanswered}, decided_at,
  rationale}.

### 2.2 Resource id prefixes (новые)

Зарегистрировать в `kacho-corelib/ids/ids.go` (отдельным mini-PR в corelib, до миграционных PR'ов):

| Ресурс                           | Prefix const                       | Значение | Длина id |
|----------------------------------|------------------------------------|----------|----------|
| Cluster (singleton)              | `ids.PrefixCluster`                | `cluster` (literal `cluster_kacho_root` — НЕ crockford-postfix) | fixed |
| Organization                     | `ids.PrefixOrganization`           | `org`    | 20       |
| ClusterAdminGrant                | `ids.PrefixClusterAdminGrant`     | `cag`    | 20       |
| ClusterBreakGlassGrant           | `ids.PrefixBreakGlass`             | `bgg`    | 20       |
| FederationTrustPolicy            | `ids.PrefixFedTrustPolicy`         | `ftp`    | 20       |
| AccessBindingCondition           | `ids.PrefixCondition`              | `cond`   | 20       |
| AccessBindingJITEligibility      | `ids.PrefixJITEligibility`         | `jite`   | 20       |
| AuditOutboxEvent                 | `ids.PrefixAuditEvent`             | `evt`    | 26 (ULID) |
| CAEPOutboxEvent                  | `ids.PrefixCAEPEvent`              | `cev`    | 26 (ULID) |
| CAEPSubscriber                   | `ids.PrefixCAEPSubscriber`         | `cps`    | 20       |
| AuditSigningBatch                | `ids.PrefixAuditBatch`             | `aub`    | 26 (ULID) |
| OIDCJwksKey                      | `ids.PrefixJwksKey`                | `jwk`    | 20       |
| SCIMUserMapping                  | `ids.PrefixSCIMMap`                | `scim`   | 20       |
| GDPRErasureRequest               | `ids.PrefixGDPRRequest`            | `gdpr`   | 20       |
| AccessReview                     | `ids.PrefixAccessReview`           | `arv`    | 20       |
| AccessReviewItem                 | `ids.PrefixAccessReviewItem`       | `ari`    | 20       |

`SessionRevocation` — PK = `token_jti` (UUIDv7 строка), без префикса.

### 2.3 Multi-scope Role — CHECK formula (нормативно)

Role имеет 4 nullable scope-колонки: `cluster_id`, `organization_id`, `account_id` (existing),
`project_id`. CHECK constraint `roles_scope_xor`:

```
(
  -- system role: только cluster_id, остальные NULL
  (is_system = true
    AND cluster_id IS NOT NULL
    AND organization_id IS NULL
    AND account_id IS NULL
    AND project_id IS NULL)
  OR
  -- custom role: точно один из (organization_id | account_id | project_id), cluster_id NULL
  (is_system = false
    AND cluster_id IS NULL
    AND (
      (organization_id IS NOT NULL AND account_id IS NULL AND project_id IS NULL)
      OR
      (organization_id IS NULL AND account_id IS NOT NULL AND project_id IS NULL)
      OR
      (organization_id IS NULL AND account_id IS NULL AND project_id IS NOT NULL)
    )
  )
)
```

Partial UNIQUE индексы (один на scope):

```
CREATE UNIQUE INDEX roles_system_unique     ON roles(cluster_id, name)      WHERE is_system = true;
CREATE UNIQUE INDEX roles_org_custom_unique ON roles(organization_id, name) WHERE is_system = false AND organization_id IS NOT NULL;
CREATE UNIQUE INDEX roles_acc_custom_unique ON roles(account_id, name)      WHERE is_system = false AND account_id IS NOT NULL;
CREATE UNIQUE INDEX roles_prj_custom_unique ON roles(project_id, name)      WHERE is_system = false AND project_id IS NOT NULL;
```

### 2.4 AccessBinding state machine (нормативно)

| From → To         | Allowed via            | Backed by                                                  |
|-------------------|------------------------|------------------------------------------------------------|
| (insert) → PENDING | `INSERT … status='PENDING'` (Phase 7 JIT approval workflow) | CHECK status ∈ list |
| (insert) → ACTIVE  | `INSERT … status='ACTIVE'` (standard upsert flow) | CHECK |
| PENDING → ACTIVE   | `UPDATE … SET status='ACTIVE' WHERE status='PENDING' AND id=$1 RETURNING …` (conditional CAS) | проверка кардинальности RETURNING |
| ACTIVE → REVOKED   | `UPDATE … SET status='REVOKED', revoked_at=now(), revoked_by=$2 WHERE status='ACTIVE' AND id=$1 RETURNING …` | conditional CAS |
| PENDING → REVOKED  | `UPDATE … SET status='REVOKED', revoked_at=now(), revoked_by=$2 WHERE status='PENDING' AND id=$1 RETURNING …` | conditional CAS |
| REVOKED → *        | **denied** (terminal) — 0 rows из conditional UPDATE → `FailedPrecondition "AccessBinding %s is REVOKED and cannot be transitioned"` |  |
| ACTIVE → PENDING   | **denied** (illegal backward transition) — 0 rows из CAS → `FailedPrecondition "illegal transition ACTIVE → PENDING"` |  |

Phase 1 тестирует raw SQL transitions; service-слой (Phase 3) обернёт в RPC.

### 2.5 Federation trust policy subject_pattern (нормативно)

`subject_pattern` хранится как `TEXT`, CHECK constraint:

```
subject_pattern <> ''
AND subject_pattern !~ '\*'           -- no glob wildcards
AND length(subject_pattern) <= 512
```

Дополнительная validation (regex compile-able) — domain-layer (Phase 5); Phase 1
ловит только syntactic level (no `*`, non-empty, length cap).

Допустимые формы (документируются, не enforce-ятся CHECK-ом на этом уровне):
- Точное равенство: `repo:my-org/my-repo:ref:refs/heads/main`
- Anchored regex из whitelisted set, prefix `^` и suffix `$` обязательны:
  `^repo:my-org/.+:ref:refs/heads/main$`

`expires_at` NOT NULL CHECK `expires_at > created_at AND expires_at <= created_at + INTERVAL '1 year'`.

### 2.6 OIDC JWKS rotation invariant (нормативно)

```
CREATE UNIQUE INDEX oidc_jwks_keys_current_unique
    ON oidc_jwks_keys(alg)
    WHERE current = true;
```

Plus CHECK `(current = false OR rotated_at IS NULL)` — current key не имеет `rotated_at`.

Rotation flow (Phase 2 use-case) использует atomic two-statement TX:
```
UPDATE oidc_jwks_keys SET current=false, rotated_at=now() WHERE alg=$1 AND current=true;
INSERT INTO oidc_jwks_keys (kid, alg, ..., current=true) VALUES (...);
```
Postgres deferrable constraint ставится `INITIALLY DEFERRED`, чтобы TX commit'ил оба
statement'а без промежуточного нарушения уникальности.

### 2.7 Permission registry (нормативно)

**Proto annotation:**

```protobuf
import "kacho/iam/v1/authz.proto";

service NetworkService {
  rpc Create(CreateNetworkRequest) returns (operation.Operation) {
    option (kacho.iam.authz.permission)        = "vpc.networks.create";
    option (kacho.iam.authz.required_relation) = "editor";
    option (kacho.iam.authz.scope_extractor)   = { object_type: "project", from_request_field: "project_id" };
    option (kacho.iam.authz.required_acr_min)  = "2";
  }
}
```

**Plugin pipeline:**
1. `protoc-gen-kacho-permissions` (новый Go-binary в `kacho-proto/cmd/protoc-gen-kacho-permissions/`)
   парсит все `.proto` под `proto/kacho/cloud/*/v1/*.proto`.
2. Для каждой RPC извлекает 4 опции; собирает в `permission_catalog.json` (deterministic
   ordering: domain → resource → verb).
3. Файл commit-ится в `kacho-proto/gen/permission_catalog.json`; в CI воркфлоу
   `regen-catalog` запускает plugin и `git diff --exit-code` падает, если catalog stale.
4. `kacho-iam` на старте загружает catalog (embed.FS), идемпотентно UPSERT-ит в
   `system_role_permissions` (`(role_id, permission_id)` pairs), назначает permissions
   двум seed-ролям (`kacho-system.admin` ← все verbs; `kacho-system.viewer` ← только `*.read`,
   `*.list`, `*.get`).

CI gate: PR, добавляющий новую RPC без `(kacho.iam.authz.permission)` opcji →
`buf lint`-style плагин-валидатор падает с понятным сообщением.

### 2.8 Bootstrap seed (нормативно)

Миграция `0011_kac127_identity_extension.sql` в самом конце:

```
-- Cluster singleton
INSERT INTO clusters (id, name, description, created_at)
VALUES ('cluster_kacho_root', 'kacho-root', 'Root cluster for Kachō control plane', now())
ON CONFLICT (id) DO NOTHING;

-- Two system roles
INSERT INTO roles (id, cluster_id, is_system, name, description, permissions, created_at)
VALUES
  ('rol00000000000000sysad', 'cluster_kacho_root', true, 'kacho-system.admin',
   'Built-in system administrator (all permissions)',  '["*.*.*"]'::jsonb, now()),
  ('rol00000000000000sysvw', 'cluster_kacho_root', true, 'kacho-system.viewer',
   'Built-in system viewer (read-only)', '["*.*.read","*.*.list","*.*.get"]'::jsonb, now())
ON CONFLICT (id) DO NOTHING;
```

Bootstrap admin enqueue — отдельный block, guarded `KACHO_IAM_BOOTSTRAP_ROOT_EMAIL` env:
Phase 1 миграция **не** делает INSERT в `users` (Phase 2 OIDC creates user); вместо этого
после миграции `kacho-iam` boot-up sequence:

1. Lookup user where `email = $KACHO_IAM_BOOTSTRAP_ROOT_EMAIL`.
2. Если найден (Phase 2 cron up'd user) → INSERT `cluster_admin_grants` (granted_by='bootstrap')
   + INSERT `fga_outbox` (event_type='fga.tuple.write', tuple=`cluster:cluster_kacho_root#system_admin@user:<usr_id>`).
3. Если не найден → log "bootstrap admin user not registered yet"; idempotent retry on next boot.
4. Идемпотентно: повторный boot с уже существующим grant'ом — UPSERT `ON CONFLICT (subject_type,subject_id) DO NOTHING`.

---

## 3. Decision Log (Phase 1 specific)

| # | Decision | Rationale |
|---|---|---|
| P1-D1 | **Четыре отдельных миграционных файла** (`0011..0014`), а не один squashed | Tematic separation (identity / federation+JIT+conditions / audit+CAEP / SCIM+GDPR+reviews+JWKS); проще ревью / роллбэк; ни один файл не превышает ~400 строк |
| P1-D2 | **Cluster singleton enforced TWO ways**: `CHECK (id = 'cluster_kacho_root')` + `BEFORE INSERT` triggеr | CHECK ловит wrong id (PUTкомт сам); trigger ловит попытку INSERT при `count>=1` (для случая, если кто-то всё же подаст правильный id вручную) — defense-in-depth |
| P1-D3 | **Multi-scope Role: ровно один non-NULL scope** via composite CHECK | Альтернатива (отдельные таблицы `system_roles`/`org_roles`/`account_roles`/`project_roles`) — фрагментация identity; UNION ALL VIEW проще через one-table + CHECK; partial-UNIQUE покрывает name-uniqueness per scope |
| P1-D4 | **AccessBinding.condition_id — FK (1:1), не inline expression** | Outliner reuse: один Condition row может реиспользоваться многими bindings (`mfa_fresh-15min` — стандартный); проще CEL pre-validation на одном месте; trade-off — extra JOIN (acceptable, кешируется Phase 3) |
| P1-D5 | **AccessBinding.status DEFAULT 'ACTIVE' + backfill UPDATE для existing rows** | Backward compat: legacy bindings (KAC-105) до Phase 1 не имеют status — backfill миграцией ALTER `ADD COLUMN status TEXT NOT NULL DEFAULT 'ACTIVE'` атомарен |
| P1-D6 | **`expires_at NOT NULL` для federation_trust_policies (max 1y)** | Forced rotation hygiene — невозможно создать "вечную" trust policy; alerts (Phase 11) предупреждают ≤14d до expiry |
| P1-D7 | **`subject_pattern` regex-validated **без** wildcard `*`** | Subject pattern matching должна быть детерминирована и безопасна; wildcard `*` open для confused-deputy / pattern-collision атак — CHECK rejects |
| P1-D8 | **`session_revocations.token_jti` — PRIMARY KEY (не surrogate id)** | Lookup pattern на api-gateway — `WHERE token_jti = $1`; нет других consumer'ов; surrogate id только overhead |
| P1-D9 | **CAEP / Audit ID = ULID (26-char base32)** | Sortable by time, append-only event log natural fit; deterministic ordering для S3 cold-write |
| P1-D10 | **`current=true` invariant на oidc_jwks_keys — partial UNIQUE + deferred constraint** | Phase 2 rotation flow требует "atomic swap": old.current → false и new.current → true в одном TX. Deferred constraint позволяет промежуточно нарушать invariant, проверяя в COMMIT |
| P1-D11 | **Permission catalog plugin — отдельный binary в kacho-proto/cmd/, не go:generate** | Plugin переиспользуется CI freshness-check'ом + kacho-iam embed; standalone binary проще тестировать; `buf generate` config wire'ит как обычный protoc plugin |
| P1-D12 | **Catalog format — JSON, не sqlc-generated table** | Catalog static на момент билда; kacho-iam loads + idempotent UPSERT; альтернатива (Postgres-only seed via migration) требует migration на каждый proto change — не масштабируется |
| P1-D13 | **Bootstrap admin grant — через outbox row, не direct OpenFGA write** | Phase 1 не подключает OpenFGA (Phase 3); fga_outbox существует с Phase E3 (KAC-108); idempotent enqueue, Phase 3 drainer применит к OpenFGA |
| P1-D14 | **CAEPSubscriber.account_id — ON DELETE CASCADE (исключение из default RESTRICT)** | Subscriber — child of Account aggregate (как `group_members`); cleanup на удаление Account естественен; не нарушает запрет #4 — обе таблицы в `kacho_iam` |
| P1-D15 | **AccessReviewItem.access_review_id — ON DELETE CASCADE** | Items — composition of AccessReview (child within aggregate); cleanup при удалении review корректен |
| P1-D16 | **JIT max_duration ≤ 8h CHECK на DB-уровне** | OPA Phase 3 enforces 2h для break-glass; для обычного JIT 8h hard cap на DB-уровне — defense-in-depth (даже если service-слой compromised, нельзя самовыдать > 8h admin) |
| P1-D17 | **Все TEXT id-колонки имеют CHECK на `^[a-z]+_[0-9a-z]+$` либо точное pattern на префиксе** | Phase 1 валидирует id format на DB-уровне через CHECK (corelib `ids.IsValid` дублируется DB constraint'ом — defense-in-depth, запрет #10 чек-лист п.5) |

---

## 4. Target architecture (компактно)

```
kacho_iam schema (Postgres) — после Phase 1 (миграции 0001..0014 applied)

  clusters (singleton, 1 row only)
    │
    ├─ cluster_admin_grants ─── subject_type/id (user|service_account)
    ├─ cluster_break_glass_grants ─── state machine, 2-person, 2h max
    │
    └─ organizations (optional B2B tier, NULLABLE FK from accounts)
            │
            ├─ scim_user_mappings ─── (organization_id, scim_external_id) → user_id
            │
            └─ accounts (existing; +column organization_id NULL FK)
                    │
                    ├─ projects (existing)
                    ├─ service_accounts (+columns project_id NULL FK, enabled BOOL)
                    ├─ groups, group_members (existing)
                    ├─ access_reviews ─── access_review_items (CASCADE)
                    ├─ gdpr_erasure_requests (FK users)
                    ├─ caep_subscribers (CASCADE on account delete)
                    │
                    └─ roles (refactored: multi-scope:
                             cluster_id|organization_id|account_id|project_id — XOR)
                             │
                             └─ access_bindings (+columns status, condition_id, expires_at,
                                                  granted_by, revoked_at, revoked_by)
                                       │
                                       ├─ access_binding_conditions (1:1)
                                       └─ access_bindings_jit_eligibility (separate eligibility)
                                                                            ↑
                                                                            FK users (approver_user_id)

  federation_trust_policies ─── FK service_accounts (target SA)
  audit_outbox ─── append-only event log (ULID id)
  caep_outbox ─── real-time revoke events (ULID id)
  session_revocations ─── PK = token_jti (UUIDv7)
  audit_signing_batches ─── Merkle-chain (previous_batch_hash → batch_hash)
  oidc_jwks_keys ─── partial UNIQUE current=true per alg

  system_role_permissions (idempotent seed from permission_catalog.json)
```

---

## 5. Декомпозиция по компонентам

### 5.1 kacho-proto

- **`proto/kacho/iam/authz/v1/authz_options.proto`** (новый файл) — extension'ы:
  `kacho.iam.authz.permission` (`extend google.protobuf.MethodOptions { string permission = 50001; }`),
  `required_relation` (50002), `scope_extractor` (50003, message с `object_type` + `from_request_field`),
  `required_acr_min` (50004).
- **`cmd/protoc-gen-kacho-permissions/main.go`** (новый Go-binary) — plugin реализует protoc plugin
  protocol; парсит все .proto в `proto/kacho/cloud/*/v1/*.proto`; emit'ит JSON.
- **`gen/permission_catalog.json`** (commit'ится) — generated artifact.
- **`buf.gen.yaml`** — wire plugin для регенерации catalog при `buf generate`.
- **`.github/workflows/ci.yaml`** — добавить step `make verify-catalog` который запускает
  `buf generate` + `git diff --exit-code gen/permission_catalog.json`.

### 5.2 kacho-corelib

- **`ids/ids.go`** — добавить новые префиксы (см. §2.2).
- **`migrations/common/`** — никаких изменений (per-service миграции).

### 5.3 kacho-iam

- **`internal/migrations/0011_kac127_identity_extension.sql`** — Cluster, ClusterAdminGrant,
  ClusterBreakGlassGrant, Organization, accounts +organization_id, Role refactor,
  AccessBinding extension, ServiceAccount +project_id+enabled, system role seed,
  bootstrap admin outbox row.
- **`internal/migrations/0012_kac127_federation_jit_conditions.sql`** — federation_trust_policies,
  access_binding_conditions, access_bindings_jit_eligibility.
- **`internal/migrations/0013_kac127_audit_caep_pipeline.sql`** — audit_outbox, caep_outbox,
  caep_subscribers, session_revocations, audit_signing_batches.
- **`internal/migrations/0014_kac127_scim_gdpr_reviews_jwks.sql`** — scim_user_mappings,
  gdpr_erasure_requests, access_reviews, access_review_items, oidc_jwks_keys.
- **`internal/domain/`** — self-validating newtype'ы и domain-структуры:
  `Cluster`, `Organization` (+ `OrgDomain`, `SCIMEndpoint`, `SAMLMetadataURL` newtype'ы),
  `ClusterAdminGrant`, `ClusterBreakGlassGrant` (state machine), `Role` (с multi-scope
  invariant), `AccessBinding` (с state machine), `AccessBindingCondition` (+ `CELExpression`),
  `FederationTrustPolicy` (+ `OIDCIssuer`, `SubjectPattern`, `MaxTokenTTL`),
  `AccessBindingJITEligibility`, `AuditEvent`, `CAEPEvent`, `CAEPSubscriber`,
  `SessionRevocation`, `AuditSigningBatch`, `OIDCJwksKey`, `SCIMUserMapping`,
  `GDPRErasureRequest`, `AccessReview`, `AccessReviewItem`.
- **`internal/repo/kacho/pg/`** — per-entity repos с CQRS Reader/Writer split:
  по 1 файлу на entity (`cluster_writer.go` / `cluster_reader.go`, и т.д.).
- **`internal/apps/kacho/seed/`** (новый use-case package) — `seed.go` загружает
  `permission_catalog.json` (embed) + UPSERT в `system_role_permissions`; вызывается из
  `cmd/kacho-iam/main.go::serve` после migrator + ДО первого `Listen`.
- **`internal/apps/kacho/bootstrap/`** — `bootstrap_root_admin.go`: lookup user by email,
  INSERT cluster_admin_grant + fga_outbox.
- **`cmd/migrator/main.go`** — обновлений нет (existing pgx-based migrator уже выполняет
  `*.sql` в порядке имени файла).
- **`cmd/kacho-iam/main.go::wire()`** — после `pool := db.New(...)`, после `migrator.Up()`
  (если включён auto-run), вызвать `seed.Run(ctx, pool)` + `bootstrap.RootAdmin(ctx, pool,
  cfg.BootstrapRootEmail)`. Composition root, никакой бизнес-логики.

### 5.4 kacho-deploy

- ConfigMap `kacho-iam-bootstrap`: `KACHO_IAM_BOOTSTRAP_ROOT_EMAIL=...` (опционально per-env;
  prod-defaults в Phase 11).
- Helm chart обновляется (вкл. `permission_catalog.json` mount, либо embed — embed предпочтителен).

### 5.5 kacho-workspace

- Этот acceptance-doc.
- Vault updates (после реализации):
  - `obsidian/kacho/resources/iam-cluster.md` (new).
  - `obsidian/kacho/resources/iam-organization.md` (new).
  - `obsidian/kacho/resources/iam-role.md` (multi-scope refactor).
  - `obsidian/kacho/resources/iam-access-binding.md` (status + condition + expires_at).
  - `obsidian/kacho/resources/iam-service-account.md` (project_id + enabled).
  - `obsidian/kacho/resources/iam-federation-trust-policy.md` (new).
  - `obsidian/kacho/resources/iam-jit-eligibility.md` (new).
  - `obsidian/kacho/resources/iam-audit-outbox.md` (new).
  - `obsidian/kacho/resources/iam-caep-outbox.md` (new).
  - `obsidian/kacho/resources/iam-session-revocation.md` (new).
  - `obsidian/kacho/resources/iam-oidc-jwks-key.md` (new).
  - `obsidian/kacho/KAC/KAC-127.md` (trail update; PRs, DoD checkboxes).

---

## 6. Given-When-Then сценарии

### 6.1 Migrations idempotency

#### Scenario 6.1.1 — Первая применка миграций 0011..0014 на чистом baseline

**Given** Postgres-инстанс с уже применёнными миграциями `0001..0010` (KAC-105/108/125 baseline);
данные не содержат строк, которые будут конфликтовать с новыми CHECK constraint'ами.

**When** запускается `kacho-iam-migrator up` (или `make migrate-iam`).

**Then** все 4 миграции `0011_kac127_identity_extension.sql`, `0012_kac127_federation_jit_conditions.sql`,
`0013_kac127_audit_caep_pipeline.sql`, `0014_kac127_scim_gdpr_reviews_jwks.sql` применены без ошибок.
**And** в таблице `schema_migrations` появляются 4 новые row'и с правильными version.
**And** `\d kacho_iam.clusters` показывает 1 row (`cluster_kacho_root`).
**And** `\d kacho_iam.roles` показывает 2 row'и (`kacho-system.admin`, `kacho-system.viewer`) с
`is_system=true` и `cluster_id='cluster_kacho_root'`.
**And** все индексы (`roles_system_unique`, `roles_org_custom_unique`, и т.д.) присутствуют.

#### Scenario 6.1.2 — Повторная применка миграций идемпотентна

**Given** миграции `0011..0014` уже применены (Scenario 6.1.1).

**When** запускается `kacho-iam-migrator up` повторно.

**Then** ни одна миграция не выполняется заново (migrator detect'ит applied versions).
**And** exit code = 0.
**And** содержимое таблиц `clusters` / `roles` (system-role row'и) не меняется.

#### Scenario 6.1.3 — Применка миграций под нагрузкой защищена advisory lock'ом

**Given** Postgres-инстанс готов; миграции `0001..0010` применены.

**When** два процесса `kacho-iam-migrator up` запускаются одновременно (race).

**Then** ровно один процесс получает advisory lock (`pg_advisory_lock(<migrator-namespace>)`) и
выполняет миграции `0011..0014`.
**And** второй процесс ждёт освобождения lock'а, затем видит уже применённые версии и завершается
без ошибок.
**And** в DB нет partial-applied state (например, `clusters` создана, но `roles` ALTER не выполнен).

#### Scenario 6.1.4 — Откат при ошибке в SQL: вся транзакция миграции rolls back

**Given** искусственная injected error: миграция `0014` содержит синтаксически невалидный SQL
в последнем CREATE.

**When** применяется `0014`.

**Then** транзакция миграции `0014` rolls back полностью (Postgres все DDL внутри BEGIN/COMMIT,
если migrator wraps).
**And** таблицы `scim_user_mappings`, `gdpr_erasure_requests`, `access_reviews`,
`access_review_items`, `oidc_jwks_keys` НЕ существуют.
**And** в `schema_migrations` нет row'и для `0014`.
**And** миграции `0011..0013` остаются применёнными (они в отдельных TX'ах, успешно commit'нулись).

> Phase 1 reviewer проверяет: migrator wrap'ает каждый file в `BEGIN; ... COMMIT;` (либо
> используется существующая `kacho-corelib/db/migrator.go` логика; в любом случае atomic per
> file).

---

### 6.2 Cluster singleton constraint

#### Scenario 6.2.1 — Попытка вставить вторую row в clusters → CHECK / trigger fails

**Given** `clusters` содержит ровно одну row (`cluster_kacho_root`, seeded миграцией).

**When** выполняется raw SQL: `INSERT INTO kacho_iam.clusters (id, name) VALUES ('cluster_other', 'other');`

**Then** Postgres возвращает SQLSTATE `23514` (CHECK violation на `id = 'cluster_kacho_root'`),
ошибка `clusters_id_singleton_ck`.
**And** `count(*) FROM clusters = 1`.

#### Scenario 6.2.2 — Попытка обновить id существующей row → CHECK fails

**Given** `clusters` содержит row `cluster_kacho_root`.

**When** выполняется raw SQL: `UPDATE kacho_iam.clusters SET id = 'cluster_renamed' WHERE id = 'cluster_kacho_root';`

**Then** Postgres возвращает SQLSTATE `23514` (CHECK violation).
**And** row остаётся с `id = 'cluster_kacho_root'`.

---

### 6.3 Organization CRUD invariants

#### Scenario 6.3.1 — Создание Organization успешно

**Given** `organizations` пустая.

**When** выполняется raw SQL: `INSERT INTO kacho_iam.organizations (id, name, display_name, description, created_at) VALUES ('org_acme1234567890ab', 'acme-corp', 'ACME Corp', 'Test org', now());`

**Then** INSERT успешен, row создана.
**And** уникальный индекс `organizations_name_unique` на `name`.

#### Scenario 6.3.2 — UNIQUE на name отвергает дубликат

**Given** Organization `acme-corp` существует.

**When** второй INSERT с тем же `name='acme-corp'`, другим `id`.

**Then** Postgres возвращает SQLSTATE `23505` (unique violation `organizations_name_unique`).

#### Scenario 6.3.3 — Delete Organization при наличии привязанных Account'ов → RESTRICT

**Given** Organization `org_acme...` существует и есть Account `acc_xxx` с `organization_id = 'org_acme...'`.

**When** выполняется raw SQL: `DELETE FROM kacho_iam.organizations WHERE id = 'org_acme...';`

**Then** Postgres возвращает SQLSTATE `23503` (FK violation), constraint
`accounts_organization_fk` ON DELETE RESTRICT.
**And** Organization остаётся.

> Phase 3 service-слой обернёт это в `FailedPrecondition "Organization %s is referenced by accounts"`.

---

### 6.4 Multi-scope custom Role CHECK invariant

#### Scenario 6.4.1 — Valid custom role с project_id scope создаётся

**Given** Project `prj_xxx` существует.

**When** raw SQL: `INSERT INTO roles (id, project_id, is_system, name, description, permissions, created_at) VALUES ('rol00000000000000pj01', 'prj_xxx', false, 'deployer', 'deployer for project', '["compute.instances.*","vpc.networks.read"]'::jsonb, now());`

**Then** INSERT успешен.
**And** partial UNIQUE `roles_prj_custom_unique` allows another row с different name в том же project.

#### Scenario 6.4.2 — Valid custom role с account_id scope создаётся

**Given** Account `acc_xxx` существует.

**When** raw SQL: `INSERT INTO roles (id, account_id, is_system, name, ...) VALUES ('rol00000000000000ac01', 'acc_xxx', false, 'billing-admin', ...);`

**Then** INSERT успешен.

#### Scenario 6.4.3 — Valid custom role с organization_id scope создаётся

**Given** Organization `org_xxx` существует.

**When** raw SQL: `INSERT INTO roles (id, organization_id, is_system, name, ...) VALUES ('rol00000000000000og01', 'org_xxx', false, 'org-admin', ...);`

**Then** INSERT успешен.

#### Scenario 6.4.4 — Invalid: 2 non-NULL scope → CHECK fails

**Given** Account `acc_xxx` и Project `prj_yyy` существуют.

**When** raw SQL: `INSERT INTO roles (id, account_id, project_id, is_system, name, ...) VALUES ('rol00000000000000xx01', 'acc_xxx', 'prj_yyy', false, 'invalid-role', ...);`

**Then** Postgres возвращает SQLSTATE `23514`, CHECK constraint `roles_scope_xor` violation.
**And** row не создана.

> Покрыты также инвалидные комбинации: (organization_id + project_id), (cluster_id + account_id),
> (все 4 NULL для custom), (is_system=true с account_id NOT NULL). Все ловятся одним CHECK.

---

### 6.5 AccessBinding state machine

#### Scenario 6.5.1 — INSERT с status='ACTIVE' успешен (default flow)

**Given** Role `rol_xxx` (system или custom), User `usr_xxx`, target resource type/id указаны.

**When** raw SQL: `INSERT INTO access_bindings (id, subject_type, subject_id, role_id, resource_type, resource_id, status, granted_by, created_at) VALUES ('acb_xxx', 'user', 'usr_xxx', 'rol_xxx', 'project', 'prj_xxx', 'ACTIVE', 'usr_admin', now());`

**Then** row создана с `status='ACTIVE'`.
**And** UNIQUE на (subject_type, subject_id, role_id, resource_type, resource_id) препятствует
дубликату (повторный INSERT — `23505`, idempotent re-upsert обрабатывается Phase 3 use-case).

#### Scenario 6.5.2 — UPDATE PENDING → ACTIVE через conditional CAS успешен

**Given** AccessBinding `acb_xxx` со `status='PENDING'`.

**When** raw SQL: `UPDATE access_bindings SET status='ACTIVE' WHERE id='acb_xxx' AND status='PENDING' RETURNING id;`

**Then** RETURNING кардинальность = 1.
**And** `status='ACTIVE'`.

#### Scenario 6.5.3 — UPDATE ACTIVE → REVOKED через conditional CAS успешен

**Given** AccessBinding `acb_xxx` со `status='ACTIVE'`.

**When** raw SQL: `UPDATE access_bindings SET status='REVOKED', revoked_at=now(), revoked_by='usr_admin' WHERE id='acb_xxx' AND status='ACTIVE' RETURNING id;`

**Then** RETURNING кардинальность = 1.
**And** `status='REVOKED'`, `revoked_at IS NOT NULL`, `revoked_by='usr_admin'`.

#### Scenario 6.5.4 — Illegal transition REVOKED → ACTIVE: 0 rows из CAS

**Given** AccessBinding `acb_xxx` со `status='REVOKED'`.

**When** raw SQL: `UPDATE access_bindings SET status='ACTIVE' WHERE id='acb_xxx' AND status='REVOKED' RETURNING id;`

**Then** RETURNING кардинальность = 1 (transition formally возможен на raw SQL!).

> **Важно**: Phase 1 CHECK ограничивает только enum-membership (`status IN ('PENDING','ACTIVE','REVOKED')`).
> Запрет на REVOKED → ACTIVE — **service-слой** (Phase 3) через дополнительное WHERE condition:
> `WHERE id=$1 AND status='ACTIVE' RETURNING ...` (т.е. service конструирует CAS, который явно
> требует source state). Phase 1 интеграционный тест **проверяет**, что использование такого
> CAS-pattern'а (`UPDATE … WHERE id=$1 AND status='ACTIVE' RETURNING …`) возвращает 0 rows для
> source-state REVOKED.

#### Scenario 6.5.4-bis — Illegal transition denied via correct CAS pattern

**Given** AccessBinding `acb_xxx` со `status='REVOKED'`.

**When** raw SQL: `UPDATE access_bindings SET status='ACTIVE' WHERE id='acb_xxx' AND status IN ('PENDING','ACTIVE') RETURNING id;`

**Then** RETURNING кардинальность = 0 (CAS source-state не matches).

#### Scenario 6.5.5 — INSERT с invalid status → CHECK fails

**Given** Role / User существуют.

**When** raw SQL: `INSERT INTO access_bindings (..., status, ...) VALUES (..., 'GHOST', ...);`

**Then** Postgres возвращает SQLSTATE `23514`, CHECK constraint `access_bindings_status_ck`
violation.

---

### 6.6 Federation Trust Policy validation

#### Scenario 6.6.1 — Создание valid trust policy успешно

**Given** ServiceAccount `sva_ci` существует.

**When** raw SQL:
```
INSERT INTO federation_trust_policies (
  id, service_account_id, issuer, audience, subject_pattern,
  additional_claims_filter, conditions, max_token_ttl, enabled, expires_at,
  created_at, created_by
) VALUES (
  'ftp_github0000000000', 'sva_ci',
  'https://token.actions.githubusercontent.com',
  'https://api.kacho.cloud',
  'repo:my-org/my-repo:ref:refs/heads/main',
  '{}'::jsonb, '{"source_ip_cidrs":["10.0.0.0/8"]}'::jsonb,
  INTERVAL '15 minutes', true, now() + INTERVAL '6 months',
  now(), 'usr_admin'
);
```

**Then** INSERT успешен.
**And** UNIQUE (issuer, subject_pattern) активен.

#### Scenario 6.6.2 — subject_pattern с wildcard `*` отвергается CHECK'ом

**Given** ServiceAccount существует.

**When** raw SQL: `INSERT … subject_pattern = 'repo:my-org/*:ref:refs/heads/main' …`

**Then** Postgres возвращает SQLSTATE `23514`, CHECK constraint
`federation_trust_policies_subject_pattern_ck` violation.

#### Scenario 6.6.3 — expires_at = NULL отвергается NOT NULL constraint

**When** raw SQL без `expires_at`: `INSERT … (id, service_account_id, issuer, audience, subject_pattern, ..., enabled, created_at, created_by) VALUES (...);` (без expires_at).

**Then** Postgres возвращает SQLSTATE `23502` (NOT NULL violation на `expires_at`).

#### Scenario 6.6.4 — expires_at > 1 year от created_at → CHECK fails

**When** raw SQL: `INSERT … expires_at = created_at + INTERVAL '2 years' …`

**Then** Postgres возвращает SQLSTATE `23514`, CHECK constraint
`federation_trust_policies_expires_within_year_ck` violation.

#### Scenario 6.6.5 — Duplicate (issuer, subject_pattern) → AlreadyExists

**Given** Policy с (issuer='https://token.actions.githubusercontent.com', subject_pattern='repo:my-org/my-repo:ref:refs/heads/main') существует.

**When** второй INSERT с теми же значениями (другой id, другой sva).

**Then** Postgres возвращает SQLSTATE `23505`, UNIQUE
`federation_trust_policies_issuer_subject_unique` violation.

---

### 6.7 Conditions schema

#### Scenario 6.7.1 — Valid condition INSERT успешен

**Given** AccessBinding `acb_xxx` существует.

**When** raw SQL:
```
INSERT INTO access_binding_conditions (id, binding_id, expression, params, created_at)
VALUES ('cond_mfa_fresh_15m_01', 'acb_xxx',
        'mfa_fresh',
        '{"max_age_seconds":900,"required_amr":["webauthn"]}'::jsonb,
        now());
```

**Then** INSERT успешен.
**And** UNIQUE (binding_id) — каждый binding имеет ≤ 1 condition.

#### Scenario 6.7.2 — Invalid expression (не в whitelisted set) → CHECK fails

**When** raw SQL: `INSERT … expression = 'arbitrary_unknown_predicate' …`

**Then** Postgres возвращает SQLSTATE `23514`, CHECK constraint
`access_binding_conditions_expression_whitelist_ck` violation.

Whitelisted: `mfa_fresh`, `non_expired`, `source_ip_in_range`, `break_glass_window`,
`jit_window`, `business_hours`, `device_compliant`.

---

### 6.8 JIT eligibility

#### Scenario 6.8.1 — Создание eligibility row успешно

**Given** User `usr_alice`, Role `rol_xxx`, Project `prj_yyy` существуют.

**When** raw SQL:
```
INSERT INTO access_bindings_jit_eligibility (
  id, user_id, role_id, resource_type, resource_id, max_duration,
  approval_required, enabled, expires_at, created_at, created_by
) VALUES (
  'jite_alice_admin_001', 'usr_alice', 'rol_xxx', 'project', 'prj_yyy',
  INTERVAL '1 hour', false, true, now() + INTERVAL '90 days',
  now(), 'usr_admin'
);
```

**Then** INSERT успешен.

#### Scenario 6.8.2 — max_duration > 8 hours отвергается CHECK'ом

**When** raw SQL: `INSERT … max_duration = INTERVAL '10 hours' …`

**Then** Postgres возвращает SQLSTATE `23514`, CHECK constraint
`access_bindings_jit_eligibility_max_duration_ck` violation
(`max_duration <= INTERVAL '8 hours'`).

---

### 6.9 Permission registry from proto

#### Scenario 6.9.1 — `buf generate` производит свежий permission_catalog.json

**Given** kacho-proto репо со всеми текущими `.proto` под `proto/kacho/cloud/*/v1/*.proto`,
RPC которых аннотированы `(kacho.iam.authz.permission)` и т.д.

**When** запускается `cd kacho-proto && buf generate`.

**Then** генерируется `gen/permission_catalog.json` с deterministic ordering.
**And** для каждой RPC присутствует запись:
```json
{
  "domain": "vpc",
  "resource": "networks",
  "verb": "create",
  "permission": "vpc.networks.create",
  "rpc": "kacho.cloud.vpc.v1.NetworkService/Create",
  "required_relation": "editor",
  "scope_object_type": "project",
  "scope_from_request_field": "project_id",
  "required_acr_min": "2"
}
```
**And** все RPC из существующих сервисов покрыты (vpc, compute, loadbalancer, iam itself).

#### Scenario 6.9.2 — kacho-iam на старте seed-ит permissions идемпотентно

**Given** свежая `kacho_iam` БД с применёнными миграциями `0011..0014` (seed двух system-ролей);
`permission_catalog.json` embed'нут в binary.

**When** запускается `kacho-iam serve`.

**Then** в первой `seed.Run(ctx, pool)` фазе:
- `system_role_permissions` UPSERT'ит пары (system-role-id, permission-string) — все
  catalog-permissions присваиваются `kacho-system.admin`; read-only verbs (`*.read`,
  `*.list`, `*.get`) — `kacho-system.viewer`.
- Idempotent UPSERT (ON CONFLICT DO NOTHING либо `ON CONFLICT (role_id, permission) DO UPDATE
  SET ...` если есть metadata).
**And** последующий restart `kacho-iam serve` не меняет содержимое `system_role_permissions`
(0 diff из дополнительного `seed_idempotent_test.go`).
**And** count(*) FROM system_role_permissions WHERE role_id='rol...sysad' = количество всех
permissions в catalog.

#### Scenario 6.9.3 — CI падает при добавлении RPC без permission annotation

**Given** PR в kacho-proto добавляет новую RPC `vpc.SubnetService.NewMethod` без
`option (kacho.iam.authz.permission)`.

**When** CI workflow `verify-permissions-coverage` запускается.

**Then** валидатор (часть `protoc-gen-kacho-permissions`) падает с exit code != 0 и сообщением
`"kacho.cloud.vpc.v1.SubnetService/NewMethod: missing required option (kacho.iam.authz.permission)"`.
**And** PR не может быть merged до тех пор, пока annotation не добавлена.

> Альтернативно: если RPC намеренно public (no-auth, типа `OperationService.Get` на
> internal-port), используется явный opt-out `option (kacho.iam.authz.permission) = "<exempt>"` —
> валидатор пропускает.

---

### 6.10 Bootstrap seed

#### Scenario 6.10.1 — Bootstrap admin: user найден → grant создан + outbox enqueue

**Given** `KACHO_IAM_BOOTSTRAP_ROOT_EMAIL=root@kacho.cloud`; User
`(id='usr_root_admin_0001', email='root@kacho.cloud')` существует в `users`
(Phase 2 заполнила через OIDC; для Phase 1 integration test'а — manually INSERT'нуть в setup).

**When** запускается `kacho-iam serve` (после migration + seed).

**Then** `bootstrap.RootAdmin` ctx-job выполняется:
- INSERT в `cluster_admin_grants` row: `(id='cag_root_admin_xxx', subject_type='user',
  subject_id='usr_root_admin_0001', granted_by='bootstrap', granted_at=now())`.
- INSERT в `fga_outbox` row: `(event_type='fga.tuple.write', payload={"object":
  "cluster:cluster_kacho_root", "relation":"system_admin", "user":"user:usr_root_admin_0001"})`.
- audit_outbox row: `(event_type='iam.cluster_admin.granted', ...)`.

#### Scenario 6.10.2 — Bootstrap admin: повторный run идемпотентен

**Given** Scenario 6.10.1 прошёл — grant и fga_outbox row уже есть.

**When** `kacho-iam serve` рестартует.

**Then** `bootstrap.RootAdmin` детектит существующий grant через
`SELECT 1 FROM cluster_admin_grants WHERE subject_type='user' AND subject_id='usr_root_admin_0001'`
(или использует UNIQUE INDEX) и:
- НЕ создаёт второй grant.
- НЕ enqueue'ит дубликат fga_outbox row.
**And** `count(*) FROM cluster_admin_grants WHERE subject_id='usr_root_admin_0001' = 1`.

---

### 6.11 Audit / CAEP outbox atomicity

#### Scenario 6.11.1 — atomic INSERT в audit_outbox в той же TX, что и domain mutation

**Given** Phase 1 integration test: запускается transaction, делающий INSERT в `roles` (custom
role) + INSERT в `audit_outbox` (event_type='iam.role.created').

**When** TX COMMIT.

**Then** обе row'и созданы. Если симулировать ROLLBACK (`pgx.Begin` → `tx.Rollback`) — обе row
отсутствуют.
**And** в `audit_outbox` payload содержит правильные tenant_account_id / tenant_org_id (NULL,
если scope=project — наследуется через JOIN'ы в Phase 9 drainer).

#### Scenario 6.11.2 — NOTIFY 'audit_event' срабатывает после COMMIT

**Given** Phase 1 integration test: установлен `LISTEN audit_event` на отдельном connection.

**When** в другом connection: BEGIN; INSERT audit_outbox; COMMIT.

**Then** listener получает NOTIFY-payload с pid/channel/payload (мин: `{"event_id":"evt_xxx"}`).

> Trigger `audit_outbox_notify` (AFTER INSERT) — миграция `0013` создаёт. Phase 9 drainer
> подписывается на NOTIFY для real-time wake-up. Phase 1 только подтверждает, что NOTIFY
> диспетчится.

---

## 7. Definition of Done (Phase 1 closure)

### 7.1 Code / migrations

- [ ] Все 4 миграции (`0011_kac127_identity_extension.sql`, `0012_..._federation_jit_conditions.sql`,
      `0013_..._audit_caep_pipeline.sql`, `0014_..._scim_gdpr_reviews_jwks.sql`) applied на e2c825
      dev стенде идемпотентно (Scenarios 6.1.1 + 6.1.2 passed).
- [ ] Все integration-тесты зелёные:
    - `internal/repo/kacho/pg/cluster_repo_test.go` (Scenarios 6.2.x).
    - `internal/repo/kacho/pg/organization_repo_test.go` (6.3.x).
    - `internal/repo/kacho/pg/role_repo_test.go` (6.4.x).
    - `internal/repo/kacho/pg/access_binding_repo_test.go` (6.5.x, 6.7.x).
    - `internal/repo/kacho/pg/federation_trust_policy_repo_test.go` (6.6.x).
    - `internal/repo/kacho/pg/jit_eligibility_repo_test.go` (6.8.x).
    - `internal/repo/kacho/pg/audit_caep_outbox_repo_test.go` (6.11.x).
    - `internal/apps/kacho/seed/seed_test.go` (6.9.2).
    - `internal/apps/kacho/bootstrap/bootstrap_test.go` (6.10.x).
    - Concurrent race tests для `oidc_jwks_keys.current` swap и multi-scope Role UNIQUE
      (`go test -race`, 100 goroutines).
- [ ] kacho-proto plugin tests: `protoc-gen-kacho-permissions_test.go` golden-test против
      `testdata/sample.proto` (6.9.1).
- [ ] `permission_catalog.json` commited в `kacho-proto/gen/`; CI step `verify-catalog` зелёный
      (6.9.1 + 6.9.3).
- [ ] kacho-iam seed-ит system_role_permissions на старте без error (Scenario 6.9.2 — runtime check).
- [ ] Bootstrap cluster-admin grant + fga_outbox row создаются успешно для valid email (6.10.1).
- [ ] Bootstrap идемпотентный (6.10.2).

### 7.2 Quality gates

- [ ] CI grep check: 0 матчей `// TODO|// FIXME|// XXX|// HACK` в добавленных файлах
      (production edition).
- [ ] CI grep check: 0 матчей `"yandex"` в добавленных файлах (запрет #2).
- [ ] golangci-lint --strict проходит без waivers на новом коде.
- [ ] `buf lint` проходит для `kacho/iam/authz/v1/authz_options.proto`.
- [ ] `buf breaking` против main: только additive changes (новый proto файл, новые
      message-extension'ы) — breaking flag не triggered.
- [ ] gosec без High/Critical на новом коде.

### 7.3 Vault updates (после merge всех PR'ов)

- [ ] `obsidian/kacho/resources/iam-cluster.md` (новый).
- [ ] `obsidian/kacho/resources/iam-organization.md` (новый).
- [ ] `obsidian/kacho/resources/iam-role.md` — updated (multi-scope CHECK, 4 partial UNIQUE).
- [ ] `obsidian/kacho/resources/iam-access-binding.md` — updated (status / condition / expires_at /
      granted_by / revoked_by).
- [ ] `obsidian/kacho/resources/iam-service-account.md` — updated (project_id + enabled).
- [ ] `obsidian/kacho/resources/iam-federation-trust-policy.md` (новый).
- [ ] `obsidian/kacho/resources/iam-jit-eligibility.md` (новый).
- [ ] `obsidian/kacho/resources/iam-audit-outbox.md` (новый).
- [ ] `obsidian/kacho/resources/iam-caep-outbox.md` (новый).
- [ ] `obsidian/kacho/resources/iam-session-revocation.md` (новый).
- [ ] `obsidian/kacho/resources/iam-oidc-jwks-key.md` (новый).
- [ ] `obsidian/kacho/KAC/KAC-127.md` — обновлено: status=in-progress, PR-URL'ы каждой
      merged'ed части, чек-лист Phase 1 закрыт.

### 7.4 Cross-repo PR-chain merged (порядок — §8)

- [ ] PR #1 kacho-proto (authz_options.proto + plugin + catalog) — merged в main.
- [ ] PR #2 kacho-corelib (ids prefixes) — merged.
- [ ] PR #3 kacho-iam (миграции `0011..0014` + domain + repo + seed + bootstrap) — merged.
- [ ] PR #4 kacho-deploy (helm chart updates: env `KACHO_IAM_BOOTSTRAP_ROOT_EMAIL`) — merged.
- [ ] PR #5 kacho-workspace (этот acceptance-doc → APPROVED → status flip; vault updates) — merged.

---

## 8. Cross-repo PR-chain (порядок merge)

Согласно workspace `CLAUDE.md` §«Кросс-репо зависимости и порядок выполнения»,
топологическая сортировка graph'а build-зависимостей:

1. **kacho-proto** — new proto file `kacho/iam/authz/v1/authz_options.proto` + plugin
   `cmd/protoc-gen-kacho-permissions/` + `gen/permission_catalog.json` (commit'ится). CI'ы
   `buf lint`, `buf breaking`, `verify-catalog` — зелёные.
2. **kacho-corelib** — ids prefixes (`PrefixCluster`, `PrefixOrganization`, ...). Зависит от
   kacho-proto (replace ../kacho-proto, но для ids — не нужно; для consistency CI ref-pin).
3. **kacho-iam** — миграции `0011..0014`, domain/repo, seed package, bootstrap package, wiring
   в `cmd/kacho-iam/main.go`. Зависит от kacho-corelib (new ids prefixes) и kacho-proto (для
   embed permission_catalog.json).
4. **kacho-deploy** — helm values добавляют env `KACHO_IAM_BOOTSTRAP_ROOT_EMAIL`, ConfigMap mount
   для permission_catalog.json (если не embed).
5. **kacho-workspace** — этот acceptance-doc finalized → APPROVED → vault updates.

> Промежуточно: kacho-iam CI на feature branch пиннит `replace ../kacho-corelib` к feature
> branch corelib (см. CLAUDE.md §«Кросс-репо зависимости» — ref-pin in CI). После merge corelib
> ref → main, флоу разрешается.

---

## 9. Out-of-scope для этой phase (НО IN scope для дальнейших phases — НЕ "deferred")

| Item | Where | Why not here |
|---|---|---|
| Kratos WebAuthn + Hydra DPoP integration | **Phase 2** | AuthN flows + JWKS rotation use-case; зависит от готовой `oidc_jwks_keys` (есть после Phase 1) |
| OpenFGA model v2 deploy + Conditions CEL evaluator + OPA bundle signing | **Phase 3** | AuthZ engine + Rego rules; зависит от готовой `access_binding_conditions` |
| corelib/authz/listobjects.go + per-service rewrite | **Phase 4** | List filtering; зависит от Phase 3 |
| ServiceAccount IssueKey RPC (Class A Hydra client) + FederationExchangeService (Class B Token Exchange RFC 8693) | **Phase 5** | Workload Identity Federation; зависит от готовой `federation_trust_policies` |
| SCIM 2.0 endpoint + Boxyhq Jackson SAML bridge + per-Organization SSO UI + domain claim verification | **Phase 6** | Enterprise SSO; зависит от `scim_user_mappings` + `organizations` |
| ActivateJIT RPC + Approval workflow + Break-glass 2-person flow + Access Reviews quarterly cron + GDPR erasure 30d pipeline | **Phase 7** | PIM/JIT lifecycle; зависит от `access_bindings_jit_eligibility` / `cluster_break_glass_grants` / `access_reviews` / `gdpr_erasure_requests` |
| CAEP drainer + SET signing + webhook delivery + exponential backoff + internal receiver | **Phase 8** | Real-time revoke; зависит от `caep_outbox` / `caep_subscribers` / `session_revocations` |
| Kafka audit-topic + ClickHouse + S3+Glacier + HSM batch signing + Merkle chain + independent verifier + SIEM forwarders | **Phase 9** | Audit pipeline; зависит от `audit_outbox` / `audit_signing_batches` |
| SPIRE Server + Agent + Cilium service mesh + cosign image-signature attestor | **Phase 10** | In-cluster Workload Identity (Class C) |
| Multi-region active-active + api.kacho.cloud TLS + Cloudflare WAF + cert-manager + Argo CD + Grafana + Alertmanager + Runbooks | **Phase 11** | Production deployment + Observability |
| OWASP ASVS L3 conformance test + continuous fuzzing + chaos + pentest + bug bounty | **Phase 12** | Security verification |
| Vault closeout (30+ files) + production runbooks finalization | **Phase 13** | Documentation |

**Production edition note**: ничего из перечисленного выше не "deferred" / "follow-up" /
"future epic" — всё планируется и закрывается в рамках KAC-127. Phase 1 — DB-foundation,
которая разблокирует все остальные phases.

---

## 10. Open questions

Все open questions resolve'нуты inline до отправки на `acceptance-reviewer` (production edition,
запрет на "TBD"):

1. **Q**: Что делать, если `KACHO_IAM_BOOTSTRAP_ROOT_EMAIL` указан, но Phase 2 OIDC ещё не
   подключён (user не создан)? — **A**: см. §2.8 / Scenario 6.10.1: bootstrap логирует "user not
   registered yet" и retry на каждый boot; идемпотентность гарантируется UNIQUE(subject_type,
   subject_id) в `cluster_admin_grants`. По merge'у Phase 2, при следующем boot — grant создаётся.

2. **Q**: Multi-scope Role: что произойдёт с существующими (KAC-105 baseline) custom-ролями,
   которые имеют `account_id NOT NULL` под старой схемой? — **A**: backward compatible — старая
   схема имеет ровно `account_id NOT NULL` для custom, что подпадает под новую CHECK formula как
   "account-scoped custom" (см. §2.3). Никакой backfill UPDATE не нужен. Миграция `0011`
   просто `ALTER TABLE roles ADD COLUMN cluster_id ..., ADD COLUMN organization_id ...,
   ADD COLUMN project_id ...` (все NULL по дефолту), затем `ALTER TABLE … ADD CONSTRAINT
   roles_scope_xor CHECK (...)`. Existing rows проходят CHECK (custom + account_id NOT NULL).

3. **Q**: AccessBinding status backfill: existing rows (KAC-105) не имеют `status` колонки. — **A**:
   `ALTER TABLE access_bindings ADD COLUMN status TEXT NOT NULL DEFAULT 'ACTIVE'`. Postgres 11+
   делает это в metadata-only без table rewrite (default не nullable, но storage оптимизирован).
   Если на e2c825 dev стенде < 1M rows — допустим даже rewrite (минуты).

4. **Q**: `oidc_jwks_keys` создаётся пустой; кто INSERT'ит первую row? — **A**: Phase 2 первая
   операция — `JwksRotationUseCase.Bootstrap` на старте Hydra service. Phase 1 оставляет таблицу
   пустой; integration test для invariant — INSERT/UPDATE с симуляцией rotation flow.

5. **Q**: Conditions whitelist (`expression IN (...)`) — что если нужно добавить нового predicate
   позже? — **A**: новая миграция (например `0015_add_condition_X.sql`) ALTER'ит CHECK constraint
   (DROP + ADD). Phase 1 содержит 7 predicates (см. §2.5 design doc); Phase 3 может расширить.

6. **Q**: `subject_pattern` validation: regex compile-check на Phase 1 (DB-уровень) или Phase 5
   (service-слой)? — **A**: Phase 1 — только syntactic (no `*`, non-empty, length ≤ 512).
   Регекс-компилируемость требует Go-runtime — Phase 5 domain newtype `SubjectPattern.Validate()`
   делает `regexp.Compile(s)` и возвращает InvalidArgument при ошибке.

7. **Q**: ULID generation для audit_outbox / caep_outbox — server-side или client-side? — **A**:
   client-side (kacho-iam генерирует через `oklog/ulid`); server-side default через
   `gen_ulid()` extension недоступен в стандартном Postgres. ID generation в domain newtype
   `AuditEventID.New()`.

---

## 11. References

- Design doc: `docs/superpowers/specs/2026-05-19-iam-prod-ready-next-gen-design.md`
  (Decision Log §1 D-1..D-28, Identity Model §3, OpenFGA v2 §4, Workload Identity §6, JIT §11,
  Audit pipeline §9, CAEP pipeline §10, Production deploy §13, DoD §17, Migration plan §16).
- Baseline acceptance docs:
  - `docs/specs/sub-phase-2.0-iam-E0-skeleton-acceptance.md` — формат образец, KAC-105.
  - `docs/specs/sub-phase-2.0-iam-E3-openfga-rebac-acceptance.md` — fga_outbox, KAC-108.
  - `docs/specs/sub-phase-2.0-iam-KAC-119-role-model-acceptance.md` — Role model baseline.
  - `docs/specs/sub-phase-2.0-iam-KAC-121-yc-style-role-model-acceptance.md` — system roles seed.
- Workspace regulation:
  - `CLAUDE.md` §«Запреты» (#1, #4, #5, #8, #9, #10, #11).
  - `CLAUDE.md` §«Within-service refs — DB-уровень обязателен».
  - `CLAUDE.md` §«Кросс-доменные ссылки на ресурсы».
  - `CLAUDE.md` §«Obsidian vault».
- Project specs:
  - `docs/specs/00-overview-and-scope.md`
  - `docs/specs/01-architecture-and-services.md`
  - `docs/specs/02-data-model-and-conventions.md`
  - `docs/specs/03-deployment-and-operations.md`
  - `docs/specs/04-roadmap-and-phasing.md`
- RFCs:
  - RFC 7644 (SCIM 2.0): <https://datatracker.ietf.org/doc/rfc7644/>
  - RFC 8417 (Security Event Tokens): <https://datatracker.ietf.org/doc/rfc8417/>
  - RFC 8693 (OAuth 2.0 Token Exchange): <https://datatracker.ietf.org/doc/rfc8693/>
  - RFC 9449 (DPoP): <https://datatracker.ietf.org/doc/rfc9449/>
  - OpenID CAEP 1.0: <https://openid.net/specs/openid-caep-1_0.html>

---

**End of acceptance doc — Phase 1.** Кодирование начинается ПОСЛЕ APPROVED от
`acceptance-reviewer` (запрет CLAUDE.md #1). Production edition: никаких "follow-up" /
"TODO" / "deferred" — всё в scope KAC-127 в рамках 13 phases.
