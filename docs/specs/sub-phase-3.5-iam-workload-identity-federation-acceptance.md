# Sub-phase 3.5 — IAM Workload Identity Federation (KAC-127 / Phase 5) — Acceptance

> **Status**: DRAFT — awaiting `acceptance-reviewer` APPROVED.
> **Date**: 2026-05-19
> **YouTrack**: [KAC-127](https://prorobotech.youtrack.cloud/issue/KAC-127) — production-ready next-gen IAM, epic.
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer` (gate per запрет #1, workspace `CLAUDE.md`).
> **Design doc**: `docs/superpowers/specs/2026-05-19-iam-prod-ready-next-gen-design.md` (§1 Decision Log D-8 / D-15, §3 Identity Model, §5.1 token shapes, **§6 Workload Identity — Class A & Class B**, §6 Out-of-scope Class C SPIFFE→Phase 10, §17 DoD).
> **Plan doc**: `docs/superpowers/plans/2026-05-19-iam-prod-ready-next-gen-plan.md` — **Phase 5 tasks 5.1–5.8**.
> **Phase position**: §16 design doc "Migration plan", **Phase 5 of 13** — после AuthZ core (Phase 3) и ListObjects (Phase 4).
> **Target repos** (порядок merge — топологическая сортировка кросс-репо графа из workspace `CLAUDE.md`):
> 1. `PRO-Robotech/kacho-proto` — новые .proto (`iam.v1.SAKeyService`, `iam.v1.FederationExchangeService`, `iam.v1.TrustPolicyService`) + регенерация `gen/`.
> 2. `PRO-Robotech/kacho-corelib` — `clients/hydra_admin.go` (extension; httptest mock), `clients/kratos_admin.go` (recovery-link production), `oidc/jwks_cache.go` (per-issuer JWKS with 24h TTL + LRU + kid-miss-refresh).
> 3. `PRO-Robotech/kacho-iam` — domain `ServiceAccountKey`/`FederationTrustPolicy`; service/repo для `SAKeyService` (Create/Delete/List/Rotate), `FederationExchangeService` (Exchange), `TrustPolicyService` (CRUD); migration `0015_kac127_federation_jit_indexes.sql` (rate-limit table + jti-replay table).
> 4. `PRO-Robotech/kacho-api-gateway` — public endpoint `/iam/v1/federations:exchange` + `/iam/v1/serviceAccounts/{sva_id}/keys` (REST mux); internal admin endpoints для `TrustPolicyService` (CRUD — admin-only, см. запрет #6).
> 5. `PRO-Robotech/kacho-ui` — `pages/iam/sa-keys/{SAKeysPage,IssueKeyModal,RotateKeyModal}.tsx`, `pages/iam/federations/{FederationPoliciesPage,CreatePolicyModal}.tsx`, docs snippets per provider.
> 6. `PRO-Robotech/kacho-workspace` — docs/specs (этот файл), vault `KAC/KAC-127.md` trail + `resources/iam-federation-trust-policy.md` + `rpc/iam-federation-exchange-service.md`.
> **Target DB**: `kacho_iam` (schema `kacho_iam`); таблицы `service_account_oauth_clients` и `federation_trust_policies` уже созданы Phase 1 миграцией `0012_kac127_federation_jit_conditions.sql` — здесь только новые indexes + новая `0015_kac127_federation_rate_limits.sql` (per-issuer rate-limit token-bucket + jti-replay cache).

---

## 0. Преамбула — место этой sub-итерации в epic

Phase 5 — **первый external-facing surface** KAC-127, открывающий `api.kacho.cloud` для двух
production workload-identity classes:

1. **Class A — Hydra OAuth2 `client_credentials`** (статические SA keys). ServiceAccount владелец
   `IssueKey` RPC создаёт пару `client_id / client_secret` в ORY Hydra, секрет возвращается
   ровно один раз в `Operation.response` и **никогда** не хранится в kacho-iam DB (только
   `hydra_client_id` mapping в `service_account_oauth_clients`). External CI/CD получает Kachō
   JWT через стандартный OAuth flow `POST /oauth2/token -u sva_xxx:<secret> -d grant_type=client_credentials`.

2. **Class B — Workload Identity Federation, RFC 8693 Token Exchange** (рекомендуемый для CI/CD).
   Tenant создаёт `FederationTrustPolicy` (issuer + subject_pattern + audience + claims_filter +
   conditions), привязывает её к своему `ServiceAccount`. External CI runner (GitHub Actions, AWS
   IRSA on EKS, GCP WIF, GitLab CI, Bitbucket Pipelines, CircleCI, Buildkite, Azure Workload
   Identity) выпускает свой OIDC `subject_token`, отправляет на `POST /iam/v1/federations:exchange`
   с `grant_type=urn:ietf:params:oauth:grant-type:token-exchange`. Kachō верифицирует подпись
   через JWKS issuer'а (cache 24h), match'ит trust policy, оценивает conditions, выпускает
   короткоживущий Kachō JWT (TTL ≤ policy.max_token_ttl, hard-cap 15min). **Никаких статических
   секретов на стороне CI** — это основной мотиватор класса B.

3. **Trust Policy CRUD** + auto-disable при `expires_at` истечении + per-SA / per-Account list
   pagination + immutable `subject_pattern` после create (mutable только `enabled` /
   `expires_at` / `conditions`).

4. **Audit + CAEP integration** — каждый exchange (success / denied) пишет в `audit_outbox`,
   каждое key-revoke / policy-disable шлёт SET в `caep_outbox` → CAEP webhook subscribers
   (Phase 8 drainer; здесь только storage emit).

5. **UI** — две страницы (`/iam/serviceAccounts/:sva/keys` и `/iam/federations`) + 8 docs snippets
   с готовыми `actions/cache.yml` / `aws-actions/configure-aws-credentials@v4` / etc. под каждого
   из 8 поддерживаемых провайдеров (copy-paste для customer).

**Phase 5 НЕ включает** (это последующие phases того же epic — НЕ "deferred"):

- **Class C SPIFFE/SPIRE in-cluster** — кросс-сервисная mTLS-identity через workload API socket и
  Cilium eBPF mesh — **Phase 10**. Class C предназначен для **межсервисной** identity внутри
  Kubernetes-кластера (kacho-iam ↔ kacho-vpc ↔ kacho-compute), а не для external CI/CD; в Phase 5
  его инфраструктура (SPIRE Server / Agent / federation bundles / Cilium policies) **не
  поднимается** — это отдельная работа Phase 10 (cluster bootstrap + helm chart + Argo CD).
- **Audit Kafka pipeline + ClickHouse + S3+Glacier + HSM-signed batches** — **Phase 9**. Phase 5
  пишет в локальный `audit_outbox` (Postgres table), drainer / Kafka producer / consumer'ы —
  Phase 9. Тесты Phase 5 проверяют **факт записи в `audit_outbox`** (row appears) и **shape
  события** (CADF-compatible JSONB); end-to-end delivery в ClickHouse / S3 / SIEM — Phase 9.
- **CAEP webhook delivery + SET signing + retry/backoff** — **Phase 8**. Phase 5 пишет в
  `caep_outbox` при key-revoke / policy-disable / exchange-denied (если subscriber подписан на
  event-type); drainer + webhook delivery — Phase 8. Тесты Phase 5 проверяют **row in
  `caep_outbox`** с правильным event-type и subject; end-to-end webhook → subscriber → ack —
  Phase 8.
- **Multi-region active-active** для exchange endpoint — **Phase 11**. Phase 5 — single-region
  (текущий dev-стенд `e2c825`); multi-region failover с Anycast + GeoDNS — отдельная инфра-работа.

Phase 5 — **production-ready external workload-identity surface**: Class A + Class B + Trust Policy
CRUD + 8 providers tested + UI + audit emit + CAEP emit. После APPROVED + merge — external CI/CD
сможет получать Kachō JWT **без статических секретов** через industry-standard RFC 8693 Token
Exchange, и tenant-admin сможет управлять trust policies / SA keys через UI и/или REST API.

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** (workspace) — кодирование только после `acceptance-reviewer` APPROVED | этот документ — gate; статус выше `DRAFT` до APPROVED. Phase 5 трогает 6 репо и 30+ файлов — гейт критичен |
| **Запрет #2** — НЕ упоминать "yandex" | в proto / handlers / UI / docs snippets — стилистически следуем YC по форме (Operation envelope, `Code`/`Message`/`Details`, `<Resource>%s not found`), **structurally** Federation Exchange — наш дизайн (RFC 8693 стандарт; нет YC аналога); никакого `yandex` в env-name, package-name, error-text |
| **Запрет #3** — НЕ ORM | sqlc + handwritten pgx; CQRS Reader/Writer per use-case (skill `evgeniy` + `godzila`); JWKS cache — `corelib/oidc/` использует stdlib `net/http` + `sync.Map`, никаких ORM |
| **Запрет #4** — НЕ каскад через границу сервиса | все Phase 5 FK — внутри `kacho_iam`: `service_account_oauth_clients.sva_id → service_accounts(id) ON DELETE RESTRICT` (из Phase 1), `federation_trust_policies.service_account_id → service_accounts(id) ON DELETE RESTRICT` (из Phase 1); никаких cross-service FK |
| **Запрет #5** — НЕ редактировать применённую миграцию | одна **новая** миграция `0015_kac127_federation_rate_limits.sql` (per-issuer rate-limit table + jti-replay cache + audit/caep partial indexes под `event_type='iam.federation.*'`). Никаких ALTER на `0011..0014` (Phase 1 / 2 / 3 / 4 — frozen) |
| **Запрет #6** — `Internal.*` НЕ на external TLS endpoint | **критично** для Phase 5: `FederationExchangeService.Exchange` — **public** (внешние CI вызывают напрямую через `api.kacho.cloud`); `TrustPolicyService.{Create,Update,Delete,List}` — **admin-only**: регистрируется как `InternalTrustPolicyService` на 9091, доступен только через cluster-internal listener (UI / admin-tooling); `SAKeyService.{Create,Delete,List,Rotate}` — **public** (tenant сам управляет своими SA keys в своих projects, после OPA project-admin check). Реestration в `kacho-api-gateway/internal/restmux/mux.go` — два разных блока (см. §5 ниже) |
| **Запрет #7** — НЕ broker, пока in-process справляется | Phase 5 пишет в `audit_outbox` / `caep_outbox` через `corelib/audit` + `corelib/caep` (existing Phase 1 packages); broker (Kafka audit-topic) — Phase 9 drainer; per-issuer rate-limit — Postgres token-bucket table, не Redis (in-process LISTEN/NOTIFY для cache invalidate достаточно) |
| **Запрет #8** — DB-per-service | всё в `kacho_iam`; **external issuer JWKS** (e.g. `https://token.actions.githubusercontent.com/.well-known/jwks.json`) — это **internet** ресурс, не DB; кэшируется в-process (`corelib/oidc/jwks_cache.go`) с 24h TTL, опционально материализуется в `kacho_iam.oidc_jwks_keys` для аудит-trail (см. §6.8) |
| **Запрет #9** — async-only мутации | `SAKeyService.{Create,Delete,Rotate}` — возвращают `operation.Operation` (Hydra POST + DB INSERT не моментальны: ~50-200ms p95); `TrustPolicyService.{Create,Update,Delete}` — `Operation`; `FederationExchangeService.Exchange` — **sync** (RFC 8693 требует синхронный `application/json` ответ с `access_token`; это стандарт OAuth2, не Kachō Operation envelope; явное исключение из запрета #9, обоснованное в §3 P5-D14) |
| **Запрет #10** — within-service refs на DB-уровне | **полностью**: `service_account_oauth_clients.sva_id` FK + UNIQUE (1:1 mapping, Phase 1); `federation_trust_policies.service_account_id` FK; partial UNIQUE `(issuer, subject_pattern)` (Phase 1); CHECK `subject_pattern_ck` no-wildcard (Phase 1); CHECK `expires_within_year_ck` (Phase 1); jti-replay таблица — partial UNIQUE на `(jti, issuer)` WHERE `expires_at > now()` (новая в `0015`); per-issuer rate-limit — atomic `INSERT … ON CONFLICT (issuer, bucket_start) DO UPDATE SET tokens = tokens - 1 WHERE tokens > 0 RETURNING tokens` (single-statement CAS); никаких software TOCTOU |
| **Запрет #11** — тесты в том же PR | каждый PR (proto / corelib / kacho-iam / api-gateway / ui) содержит **integration tests + newman cases** (см. §10 DoD checklist); kacho-iam PR — 30+ integration tests (testcontainers Postgres + httptest mock Hydra + httptest mock 8-providers JWKS endpoints) + 15+ newman cases (real api-gateway, mock issuer running как sidecar); api-gateway PR — mux registration tests + ensure `TrustPolicyService` НЕ зарегистрирован на public mux (regression test); UI PR — Playwright e2e (issue key happy-path + revoke key + create trust policy + exchange flow demo) |

---

## 2. Глоссарий / доменная модель Phase 5 (нормативно)

### 2.1 Сущности, релевантные Phase 5

> **No-schema-change note**: основные таблицы `service_account_oauth_clients` и
> `federation_trust_policies` уже созданы Phase 1 миграцией `0012_kac127_federation_jit_conditions.sql`
> со всеми FK / CHECK / UNIQUE / partial-UNIQUE. Phase 5 миграция `0015` добавляет **только** две
> новые таблицы (rate-limit + jti-replay) и partial indexes на `audit_outbox` / `caep_outbox`
> под фильтрацию по `event_type LIKE 'iam.federation.%'`. ALTER TABLE на существующие
> таблицы — **нет**.

- **ServiceAccountKey (Class A)** — public-facing именование Hydra OAuth2 client.
  Под капотом — row в `service_account_oauth_clients`:
    - `id` — Kachō id (`sak_<crockford>`, 21 chars). NEW в Phase 5 — переименование domain
      type из `ServiceAccountOAuthClient`→`ServiceAccountKey` без миграции БД (table остаётся
      `service_account_oauth_clients`, public proto имя — `ServiceAccountKey`).
    - `sva_id` — FK → `service_accounts(id) ON DELETE RESTRICT`; UNIQUE 1:1 (один SA — один key
      одновременно; rotate — двухстадийный, см. §6.4).
    - `hydra_client_id` — UNIQUE; формат `kacho-sak-<crockford>` (легко отличить от user-OAuth-app
      Hydra-client в Phase 6 SSO).
    - `description` — free-form (≤ 256 chars).
    - `created_by` — user или service_account who issued (audit trail).
    - `created_at`, `expires_at` (optional, NULL = no expiry; recommended ≤180d).
    - `last_used_at` — timestamp последнего успешного `client_credentials` flow в Hydra
      (обновляется async через Hydra introspection webhook; в Phase 5 — NULL stub, обновление
      кодится но без cron; полноценный Hydra→kacho-iam webhook — Phase 8 CAEP receiver).
- **FederationTrustPolicy (Class B)** — row в `federation_trust_policies`:
    - `id` — `ftp_<crockford>`, 21 chars.
    - `service_account_id` — FK → `service_accounts(id) ON DELETE RESTRICT`. Target SA (sub в
      выпускаемом Kachō JWT).
    - `issuer` — TEXT (e.g. `https://token.actions.githubusercontent.com`); индексируется для
      lookup на exchange-path.
    - `audience` — TEXT (e.g. `https://api.kacho.cloud`); обязан совпадать с aud в external JWT.
    - `subject_pattern` — TEXT; **strict exact-match** (no glob `*`); CHECK `subject_pattern_ck`
      Phase 1 миграции запрещает символы `*` `?` `[` `]` `{` `}` `\` `/` (кроме path-separator в
      `repo:my-org/my-repo:...`); regex anchoring неявное (always exact-match по всей строке —
      см. §6.5).
    - `additional_claims_filter` — JSONB; exact-match key→value по claim'ам external JWT
      (`{"workflow":"deploy.yml","environment":"production"}`). Case-sensitive. Не regex.
    - `conditions` — JSONB CEL-like:
        - `source_ip_cidrs` — list of CIDRs (e.g. `["10.0.0.0/8","192.168.0.0/16"]`); если
          непусто — match X-Forwarded-For начала request.
        - `business_hours` — `{"timezone":"Europe/Berlin","start_h":9,"end_h":18}`; если
          непусто — match `hour_of_day(now, tz)` в `[start_h, end_h)`.
        - `max_token_ttl_override` — INTERVAL (optional); если задан — override на
          `policy.max_token_ttl` для этого exchange (с hard-cap 15min).
    - `max_token_ttl` — INTERVAL; CHECK `max_token_ttl <= INTERVAL '15 minutes'` (hard cap из
      D-7 design + P5-D6 ниже).
    - `enabled` — BOOL; mutable через `UpdatePolicy`.
    - `expires_at` — TIMESTAMPTZ NOT NULL; CHECK `expires_at <= created_at + INTERVAL '1 year'`
      (Phase 1 — `expires_within_year_ck`). Auto-disable при истечении: тест Scenario 6.10.4
      ниже проверяет, что после `now() > expires_at` exchange отвечает `Unauthenticated`
      "federation policy %s expired" + emit `iam.federation.policy.expired` event.
    - `created_at`, `created_by`.
    - **Mutable fields after create**: `enabled`, `expires_at` (только uменьшение или продление в
      пределах ≤1y от **исходного** `created_at`), `conditions`. **Immutable**: `issuer`,
      `audience`, `subject_pattern`, `service_account_id`, `additional_claims_filter`,
      `max_token_ttl`. Попытка update иммутабельного поля → `InvalidArgument` "%s is immutable
      after FederationTrustPolicy.Create".
- **JwksCacheEntry (in-memory)** — per-issuer cache в `corelib/oidc/jwks_cache.go`:
    - Key: issuer URL.
    - Value: `{ fetched_at, keys [kid → JsonWebKey], ttl }`.
    - TTL: 24h.
    - Refresh trigger: (1) TTL expired; (2) `kid` requested не найден среди cached keys (force
      refresh — issuer мог сделать rotation).
    - Concurrency: `sync.RWMutex` per cache; `singleflight.Group` чтобы не делать N параллельных
      fetch'ей при кэш-miss'е.
    - Fallback: если issuer JWKS endpoint недоступен (HTTP 5xx / timeout / DNS fail) и в cache
      есть **expired** entry — используется expired (degraded mode) + emit Prometheus metric
      `iam_jwks_stale_fallback_total{issuer="..."}`.
    - Optional persistence: каждый fetched key материализуется в `kacho_iam.oidc_jwks_keys`
      (Phase 1 таблица) для аудит-trail (kid + issuer + alg + pem + fetched_at); это
      append-only log, не source-of-truth для verification (in-memory cache — source).
- **JtiReplayEntry** — partial UNIQUE на `(jti, issuer)` в новой таблице
  `federation_jti_replay` (миграция `0015`). При успешном exchange — INSERT row с
  `expires_at = now() + (external_token.exp - now())`. Если `jti` уже есть → exchange denied
  ("token already exchanged"). Old rows автоматически удаляются partial-index'ом WHERE
  `expires_at > now()` (фактически: cron-job `DELETE FROM federation_jti_replay WHERE
  expires_at < now()` каждые 5min — стандартный maintenance, обоснован тестом Scenario
  6.11.5).
- **RateLimitBucket** — token-bucket per `(issuer, bucket_start_minute)` в новой таблице
  `federation_exchange_rate_limits` (миграция `0015`). 100 exchanges per minute per issuer
  (anti-replay + anti-flood). При exchange — atomic single-statement
  `INSERT … ON CONFLICT (issuer, bucket_start) DO UPDATE SET tokens = tokens - 1 WHERE tokens > 0
  RETURNING tokens`; 0 rows → rate-limit exceeded, return `ResourceExhausted` "rate limit
  exceeded for issuer %s" + emit `iam.federation.rate_limit.exceeded` audit event.

### 2.2 Сущности, не меняющиеся в Phase 5

- `service_accounts` — Phase 1 schema, без изменений.
- `users` — без изменений.
- `accounts`, `projects` — без изменений.
- `audit_outbox`, `caep_outbox` — Phase 1 schema; Phase 5 пишет в эти tables (через
  `corelib/audit` / `corelib/caep`), не меняет schema.
- `roles`, `access_bindings`, `access_binding_conditions` — Phase 1 / 3, без изменений в Phase 5.
- `oidc_jwks_keys` — Phase 1 table; Phase 5 INSERT новые rows (per kid materialization).

### 2.3 Supported OIDC issuers (production-tested)

Trust policies могут указывать на **любой** OIDC issuer (RFC 8414 discovery via
`/.well-known/openid-configuration` → JWKS URL). В Phase 5 **протестированы и документированы**
8 провайдеров:

| # | Provider | Issuer URL | Subject pattern example |
|---|---|---|---|
| 1 | GitHub Actions | `https://token.actions.githubusercontent.com` | `repo:my-org/my-repo:ref:refs/heads/main` |
| 2 | AWS IRSA (EKS) | `https://oidc.eks.<region>.amazonaws.com/id/<cluster-id>` | `system:serviceaccount:my-ns:my-sa` |
| 3 | GCP Workload Identity Federation | `https://accounts.google.com` (or workload pool issuer) | `principal://iam.googleapis.com/projects/.../subject/...` |
| 4 | GitLab CI | `https://gitlab.com` (or self-hosted instance URL) | `project_path:my-group/my-project:ref_type:branch:ref:main` |
| 5 | Bitbucket Pipelines | `https://api.bitbucket.org/2.0/workspaces/<ws>/pipelines-config/identity/oidc` | `<workspace-uuid>:<repo-uuid>:<step-uuid>` |
| 6 | CircleCI | `https://oidc.circleci.com/org/<org-id>` | `<project-id>/<context-id>` |
| 7 | Buildkite | `https://agent.buildkite.com` | `organization:my-org:pipeline:my-pipeline:ref:refs/heads/main` |
| 8 | Azure Workload Identity | `https://login.microsoftonline.com/<tenant-id>/v2.0` | `<service-principal-object-id>` |

**No-allowlist policy**: tenant может создать trust policy на любой `issuer` (e.g. self-hosted
GitLab `https://gitlab.my-corp.com`). Однако Phase 5 OIDC discovery валидирует issuer-URL:
HTTPS обязателен (`http://` rejected), `.well-known/openid-configuration` обязан вернуть валидный
JSON с `jwks_uri`, `jwks_uri` обязан вернуть валидный JWKS. Невалидный issuer → `InvalidArgument`
"issuer %s OIDC discovery failed: %s" при `CreateTrustPolicy`.

### 2.4 Token shapes (production)

**External OIDC JWT (subject_token)** — формат каждого из 8 провайдеров чуть отличается; общий
shape:

```json
{
  "iss": "https://token.actions.githubusercontent.com",
  "sub": "repo:my-org/my-repo:ref:refs/heads/main",
  "aud": "https://api.kacho.cloud",
  "exp": 1716200000,
  "iat": 1716199400,
  "nbf": 1716199400,
  "jti": "<uuid>",
  "kid": "<key-id>",
  "alg": "RS256",
  "repository": "my-org/my-repo",
  "workflow": "deploy.yml",
  "environment": "production",
  "actor": "alice",
  "event_name": "push",
  "...": "provider-specific claims"
}
```

**Kachō JWT (issued by Exchange)** — federation-exchanged token; формат из design §5.1:

```json
{
  "iss": "https://hydra.kacho.cloud",
  "sub": "sva_ci_deployer",
  "aud": ["https://api.kacho.cloud"],
  "exp": <now + policy.max_token_ttl, hard-cap 15min>,
  "iat": <now>,
  "nbf": <now>,
  "jti": "<uuid-v7>",
  "scope": "kacho.vpc kacho.compute",
  "ext_claims": {
    "kacho_principal_type":    "federated_service_account",
    "kacho_account_id":        "acc_a1b2",
    "kacho_project_id":        "prj_default",
    "kacho_federation_policy": "ftp_github_main",
    "kacho_external_subject":  "repo:my-org/my-repo:ref:refs/heads/main",
    "kacho_external_issuer":   "https://token.actions.githubusercontent.com"
  }
}
```

**SA-key client_credentials token (Class A)** — стандартный Hydra-issued JWT, формат тоже из
design §5.1; `kacho_principal_type = "service_account"`, без `federation_policy`.

---

## 3. Decision Log Phase 5 (нормативно)

| # | Decision | Rationale | Связь с design D-* |
|---|---|---|---|
| P5-D1 | **Class A = Hydra OAuth2 `client_credentials` grant** (через `/oauth2/token` Hydra endpoint, standard RFC 6749 §4.4); kacho-iam НЕ выпускает Class A JWT сам — делегирует Hydra | Hydra production-grade (OAuth2.1 certified, OpenID Foundation); rotation / introspection / back-channel logout — встроены; kacho-iam отвечает только за SA→client mapping и permission gate | D-8 (workload identity), D-1 (Hydra stack) |
| P5-D2 | **Class B = RFC 8693 Token Exchange** — primary mechanism для CI/CD; kacho-iam выпускает Kachō JWT (sub=SA) после verify external OIDC token | Industry standard 2026 (RFC 8693 final 2020, mass adoption AWS/GCP/Azure/GitHub); zero static secrets на стороне CI; integrated `additional_claims_filter` + `conditions` overlay | D-8, design §6 Class B |
| P5-D3 | **JWKS cache per-issuer 24h TTL**, refresh on (a) TTL expired, (b) `kid` requested не найден среди cached keys | 24h — баланс между свежестью (issuer rotation period typically 30d-90d) и latency-sensitivity exchange-path (no extra HTTP fetch на каждый exchange); kid-miss-refresh ловит unscheduled rotation | design §6 Class B "cached JWKS per issuer, 24h TTL" |
| P5-D4 | **`subject_pattern` — strict exact-match, NO wildcard `*`**, validated на CreateTrustPolicy через CHECK (Phase 1 миграция) | Wildcard subject pattern — security hole (compromised repo может получить token назначенный другому repo); industry consensus (AWS IRSA, GCP WIF) запрещают wildcards в trust subject; admin может создать **N exact-match policies** для разных branches | design §6 Class B "strict no-wildcard pattern" |
| P5-D5 | **`additional_claims_filter` — exact-match, case-sensitive, NO regex** | Same rationale as D4 — regex в trust policy = privilege escalation surface; exact-match достаточен для production use-cases (environment="production", workflow="deploy.yml") | design §6 Class B "exact match on listed claims" |
| P5-D6 | **`max_token_ttl ≤ 15min` hard cap**; tenant может задать меньше, но не больше | NIST 800-63 short-lived tokens; уменьшает blast radius compromised CI runner; 15min достаточен для CI/CD operation (`terraform apply`, `kubectl apply`); пользователь refresh'ит через новый exchange call | design §6 Class B / D-7 Passkey-first |
| P5-D7 | **Conditions evaluated on each exchange call** (не на CreateTrustPolicy) — source_ip против X-Forwarded-For, business_hours против `now()`, max_token_ttl_override | Conditions — runtime (source_ip / time меняются); CreateTrustPolicy фиксирует **правила**, exchange — **evaluates** | design §6 Class B "Evaluate conditions" |
| P5-D8 | **`expires_at NOT NULL`, max 1y from `created_at`** (CHECK `expires_within_year_ck` — Phase 1) | Forced rotation hygiene — невозможно создать "вечную" trust policy; alerts (Phase 11) предупреждают ≤14d до expiry | design §6 Class B "expires_at TIMESTAMPTZ NOT NULL — mandatory; max 1y" |
| P5-D9 | **Auto-disable** при истечении `expires_at` — exchange отвечает `Unauthenticated` "federation policy %s expired" + emit `iam.federation.policy.expired` event | Hard fail (не silent ignore) чтобы tenant знал и обновил/продлил; emit в audit для compliance | новое — design подразумевает но явно не пишет |
| P5-D10 | **Per-issuer rate-limit: max 100 exchanges/min** (token-bucket в Postgres table, atomic INSERT…ON CONFLICT) | Anti-replay protection (jti cache 1y дорого; rate-limit дешевле); anti-flood (compromised CI key не может выкачать 1000 tokens/sec); per-issuer (не per-SA) чтобы один tenant не задушил другого через shared issuer | новое — production hardening |
| P5-D11 | **JTI replay protection** — partial UNIQUE `(jti, issuer)` WHERE `expires_at > now()`; INSERT на каждый успешный exchange; reuse → denied | RFC 8693 не требует, но industry best practice (AWS STS, GCP STS); защита от replay украденного external JWT (e.g. exfiltrated из GitHub Actions log) | новое — production hardening |
| P5-D12 | **SA-key secret one-shot** — возвращается **только** в `Operation.response` `IssueServiceAccountKeyResponse.client_secret`; **никогда** не хранится в kacho-iam DB (только `hydra_client_id`); revoke не показывает secret | Industry standard (AWS IAM access key creation, GCP SA key download); зашифровать-and-store — false sense of security; tenant обязан сохранить сам | новое — security hardening |
| P5-D13 | **subject_pattern immutable** после CreateTrustPolicy; mutable только `enabled` / `expires_at` (≤1y от **исходного** created_at) / `conditions` | Изменение `subject_pattern` после create эквивалентно созданию **новой** trust policy — должен пройти through CreateTrustPolicy (с full audit / OPA check); защита от silent privilege escalation | design подразумевает; явно фиксируем |
| P5-D14 | **Exchange — synchronous response** (исключение из запрета #9 "async-only мутации") | RFC 8693 OAuth Token Exchange — синхронный `application/json` ответ; clients (GitHub Actions, AWS STS) ожидают sync; Operation envelope здесь — anti-pattern. `SAKeyService.{Create,Delete,Rotate}` остаются async (наш CRUD), `Exchange` — sync OAuth flow | design §6 Class B implicit; новое — явная фиксация исключения |
| P5-D15 | **Audit emit** на каждый exchange (success + denied) — row в `audit_outbox` с `event_type ∈ {iam.federation.exchange.success, iam.federation.exchange.denied}` + reason | Full audit trail для compliance (SOC 2 CC6.7, ISO 27001 A.9.4) + forensics (compromised CI investigation) | design §9.1 CADF schema |
| P5-D16 | **CAEP emit** на key revoke / policy disable / policy expiry → row в `caep_outbox` с SET event-type `https://schemas.openid.net/secevent/caep/event-type/token-claims-change` или `credential-change` | Real-time revoke propagation: clients (CI runners, integrating services) получают webhook ≤ 10s (Phase 8 SLA) после revoke | design §10 CAEP push pipeline |
| P5-D17 | **Trust Policy CRUD = Internal admin-only**; CreateTrustPolicy / UpdateTrustPolicy / DeleteTrustPolicy зарегистрированы как `InternalTrustPolicyService` на 9091 (cluster-internal listener), доступны UI + admin tooling | Workload identity trust — security-critical surface; **никакой tenant self-serve API на 9090**; admin (project-admin role + OPA project-admin check) создаёт от лица tenant'а через UI | запрет #6 — Internal vs external |
| P5-D18 | **SA-key CRUD = public** (на 9090 `api.kacho.cloud`); tenant с project-admin role в `prj_X` может выпускать SA-keys для `sva` в этом project | SA — tenant-owned ресурс; UX требует self-serve (KAC-125 invite flow precedent); OPA project-admin check на каждый call | design §6 Class A "permission check (admin on parent project)" |
| P5-D19 | **`hydra_client_id` format**: `kacho-sak-<crockford>` (e.g. `kacho-sak-h7q3p5x9k2w8`); kacho-iam генерирует, передаёт в Hydra POST /admin/clients | Легко отличить SA-key Hydra-client от user-OAuth-app Hydra-client (Phase 6 SCIM/SAML) в audit log; deterministic format упрощает orphan-detection (Hydra-client без kacho-iam row → audit warning) | новое — operational hygiene |
| P5-D20 | **Rotation = atomic dual-key** + grace window: `RotateKey` создаёт **новый** Hydra-client, INSERT new row в `service_account_oauth_clients` (с `replaces_id` ref на старый), revoke старого через `expires_at = now() + 1h` (grace), CAEP emit на старый id; UNIQUE на `sva_id` **временно нарушается** — поэтому partial UNIQUE WHERE `replaces_id IS NULL` (active key only; replaced keys имеют `replaces_id` non-null и не считаются "active") | Atomic rotation без downtime — старый ключ валиден ещё 1h, новый сразу активен; tenant deploy'ит new credential, потом revoke old explicit или ждёт expiry | новое — production rotation pattern |
| P5-D21 | **Mock OIDC issuers** в integration tests — **httptest server per provider**, каждый имитирует `.well-known/openid-configuration` + `/jwks` endpoints + emits JWT с realistic claims через `github.com/lestrrat-go/jwx/v2`; ключи genned per-test (RSA-2048) | Воспроизводимые tests без external network (CI offline); реальные provider issuer URLs — только smoke-test phase 5 closure (см. §10 DoD smoke) | новое — testing strategy |
| P5-D22 | **8 providers tested** в integration tests (Task 5.5): GitHub Actions, AWS IRSA, GCP WIF, GitLab CI, Bitbucket, CircleCI, Buildkite, Azure Workload Identity. Каждый = 1 happy-path scenario (одна GWT в §6.6) | Production coverage — основные customer surfaces; добавление нового provider после Phase 5 — copy-paste pattern, тривиально | plan Task 5.5 |

---

## 4. Architecture diagrams

### 4.1 Class A — Hydra OAuth2 `client_credentials` flow

```
                            CI/CD external (e.g. local script)
                            │
                            │  POST /oauth2/token
                            │   -u sva_xxx:<secret>
                            │   -d grant_type=client_credentials
                            ▼
                ┌───────────────────────────────────────┐
                │     Hydra OAuth2 server (HA 3+)        │
                │   (kacho-iam НЕ участвует на этом     │
                │    request-path — pure OAuth flow)    │
                │                                        │
                │   1. Verify client_id+secret.          │
                │   2. Issue JWT (TTL 60min).            │
                │   3. Optionally notify Phase 8 CAEP   │
                │      receiver of `last_used_at`.       │
                └───────────┬────────────────────────────┘
                            │  access_token (JWT)
                            ▼
                            CI/CD external
                            │
                            │  Authorization: Bearer <jwt>
                            ▼
                ┌───────────────────────────────────────┐
                │     kacho-api-gateway (TLS)            │
                │   1. Validate JWT (Hydra JWKS).        │
                │   2. ext_claims.kacho_principal_type   │
                │      = "service_account".              │
                │   3. Build Principal.                  │
                │   4. Forward to kacho-vpc / kacho-...  │
                └───────────────────────────────────────┘

Issue path (admin user creates SA-key):

                            UI (or grpcurl)
                            │
                            │  IssueKey(sva_id, description, expires_at)
                            ▼
                ┌───────────────────────────────────────┐
                │     kacho-iam:SAKeyService.Create     │
                │                                        │
                │   1. OPA check (project-admin).        │
                │   2. Generate hydra_client_id +        │
                │      client_secret (random 32 bytes).  │
                │   3. Hydra POST /admin/clients         │
                │      (idempotent on 409 — see §6.1.2). │
                │   4. DB INSERT into                    │
                │      service_account_oauth_clients     │
                │      (atomic with Hydra response).    │
                │   5. audit_outbox INSERT               │
                │      iam.sa.key.created.               │
                │   6. Return Operation.response =       │
                │      { id, client_id,                  │
                │        client_secret_one_shot,         │
                │        expires_at }.                   │
                └───────────────────────────────────────┘
```

### 4.2 Class B — RFC 8693 Token Exchange flow

```
                            CI/CD external (e.g. GitHub Actions)
                            │
                            │  POST /iam/v1/federations:exchange
                            │  Content-Type: application/x-www-form-urlencoded
                            │   grant_type=urn:ietf:params:oauth:grant-type:token-exchange
                            │   subject_token=<external OIDC JWT>
                            │   subject_token_type=urn:ietf:params:oauth:token-type:jwt
                            │   audience=https://api.kacho.cloud
                            ▼
                ┌───────────────────────────────────────────────┐
                │     kacho-api-gateway (TLS, public)            │
                │   pass-through; no JWT validation               │
                │   (exchange — anonymous endpoint, validated   │
                │    by signature of subject_token внутри)       │
                └───────────────────────┬───────────────────────┘
                                        │  unary gRPC
                                        ▼
                ┌───────────────────────────────────────────────┐
                │     kacho-iam:FederationExchangeService        │
                │                                                │
                │   1. Parse subject_token JWT.                  │
                │   2. Extract iss, kid.                         │
                │   3. JWKS cache lookup (24h TTL).              │
                │      ├ HIT → use cached keys.                  │
                │      └ MISS / kid not found:                   │
                │           ├ HTTP GET issuer/.well-known/jwks   │
                │           ├ Update cache.                      │
                │           └ INSERT new rows в oidc_jwks_keys.  │
                │   4. Verify JWT signature, iss/aud/exp/nbf.    │
                │   5. Per-issuer rate-limit check (token-bucket │
                │      table; atomic INSERT…ON CONFLICT).         │
                │      └ Exceeded → ResourceExhausted.           │
                │   6. JTI replay check (federation_jti_replay   │
                │      partial UNIQUE).                          │
                │      └ Already exists → Unauthenticated.       │
                │   7. Lookup trust policy:                      │
                │      WHERE issuer=$1                           │
                │        AND audience=$2                         │
                │        AND enabled                             │
                │        AND expires_at > now()                  │
                │        AND subject_pattern = $3 (exact match)  │
                │      └ Not found → PermissionDenied.           │
                │   8. Apply additional_claims_filter (exact).   │
                │      └ Mismatch → PermissionDenied.            │
                │   9. Evaluate conditions:                      │
                │      ├ source_ip_cidrs (X-Forwarded-For).      │
                │      ├ business_hours (timezone-aware).        │
                │      └ Mismatch → PermissionDenied.            │
                │   10. Compute effective TTL =                  │
                │       min(15min, policy.max_token_ttl,         │
                │           conditions.max_token_ttl_override).  │
                │   11. Sign Kachō JWT (Hydra-admin-issued or    │
                │       local JWKS — see §6.6).                  │
                │   12. INSERT jti into federation_jti_replay.   │
                │   13. audit_outbox INSERT                      │
                │       iam.federation.exchange.success.         │
                │   14. Return JSON:                             │
                │       { "access_token":"<jwt>",                │
                │         "issued_token_type":"...:jwt",         │
                │         "token_type":"Bearer",                 │
                │         "expires_in": <seconds> }.             │
                └───────────────────────────────────────────────┘

Subsequent API calls — standard:

                            CI/CD external
                            │  Authorization: Bearer <kachō-jwt>
                            ▼
                            kacho-api-gateway → backend
                            (стандартный JWT validation path —
                             ничего special для federated tokens)
```

### 4.3 Compound flow — Trust Policy CRUD (admin) + Exchange (CI)

```
   Admin (Alice, project-admin of prj_default)
   │
   │  POST /iam/v1/internalTrustPolicies (internal listener 9091)
   │  CreateTrustPolicy(service_account_id, issuer, subject_pattern, ...)
   ▼
   kacho-iam:InternalTrustPolicyService.Create
   │  1. OPA check (project-admin role).
   │  2. Validate issuer OIDC discovery (HTTPS, .well-known/jwks works).
   │  3. Validate subject_pattern CHECK (no wildcard).
   │  4. Validate expires_at ≤ 1y CHECK.
   │  5. DB INSERT federation_trust_policies.
   │  6. audit_outbox INSERT iam.federation.policy.created.
   │  7. Return Operation.response = FederationTrustPolicy.
   ▼
   (Some time later — independent process)
   │
   GitHub Actions runner (sub=repo:my-org/my-repo:ref:refs/heads/main)
   │  Issues OIDC token (id-token write permission, GHA built-in).
   │  POST /iam/v1/federations:exchange (см. §4.2 above)
   ▼
   Kachō JWT (TTL ≤ 15min, sub=sva_ci_deployer)
   │
   ▼
   Standard API calls (kubectl-like Kachō CLI).
```

---

## 5. Декомпозиция работы (по репо, в порядке merge)

> Полный детальный план — `docs/superpowers/plans/2026-05-19-iam-prod-ready-next-gen-plan.md`
> Tasks 5.1–5.8. Здесь — high-level mapping на acceptance scenarios.

### 5.1 `kacho-proto` PR (#1)

**Файлы:**
- `proto/kacho/cloud/iam/v1/sa_key_service.proto` — `service SAKeyService { Create / Delete / List / Rotate / Get }`, message `ServiceAccountKey`, `IssueServiceAccountKeyResponse` (с `client_secret_one_shot`), все `*Request` / `*Response`.
- `proto/kacho/cloud/iam/v1/federation_exchange_service.proto` — `service FederationExchangeService { Exchange }`, message `ExchangeRequest` (urlencoded form передаётся как JSON через grpc-gateway), `ExchangeResponse` (RFC 8693 fields).
- `proto/kacho/cloud/iam/v1/trust_policy_service.proto` — `service InternalTrustPolicyService { Create / Update / Delete / Get / List }`; message `FederationTrustPolicy` (full с все поля).
- `gen/go/kacho/cloud/iam/v1/...` — регенерированные stubs (committed).
- `gen/permission_catalog.json` — обновлён `protoc-gen-kacho-permissions` plugin'ом (Phase 1) — новые permissions: `iam.serviceAccountKeys.{create,delete,list,rotate,get}`, `iam.federationTrustPolicies.{create,update,delete,get,list}`, `iam.federations.exchange` (anonymous → permission tag = `"public"`).

**Sanity**: `buf lint` зелёный, `buf breaking against=main` — нет breaking changes (только новые
файлы / messages / services), `make gen` пересоздаёт `gen/go/...` без diff.

### 5.2 `kacho-corelib` PR (#2)

**Файлы:**
- Create: `clients/hydra_admin.go` — typed wrapper над `POST/DELETE/GET /admin/clients`; httptest mock в `clients/hydra_admin_test.go`; idempotent на 409 (existing client_id с такими же settings → re-use).
- Modify: `clients/kratos_admin.go` — `CreateRecoveryLink(identity_id) (link, expires_at, err)` — full impl (KAC-125 stub → production); используется в Phase 7 access reviews, но логически принадлежит этому PR (расширение clients).
- Create: `oidc/jwks_cache.go` — `Cache` struct с per-issuer entries; `Get(ctx, issuer, kid) (jwk, error)`; TTL 24h; LRU eviction (max 100 issuers по умолчанию); kid-miss-refresh; `singleflight.Group` для concurrent fetches; metrics `iam_jwks_cache_hits_total`, `iam_jwks_cache_misses_total`, `iam_jwks_stale_fallback_total`.
- Create: `oidc/discovery.go` — `DiscoverOIDC(ctx, issuer) (config, error)` — fetches `.well-known/openid-configuration`, validates HTTPS, returns `jwks_uri` / `id_token_signing_alg_values_supported`.
- Tests: `oidc/jwks_cache_test.go` (TTL behaviour, concurrent gets, kid-miss-refresh, stale fallback), `oidc/discovery_test.go` (httptest mock).

### 5.3 `kacho-iam` PR (#3)

**Файлы:**
- Domain: `internal/domain/sa_key.go`, `internal/domain/federation_trust_policy.go`, `internal/domain/types.go` (newtypes: `IssuerURL`, `SubjectPattern`, `Audience`, `MaxTokenTTL`).
- Service / use-cases (slice-per-RPC per skill `godzila`):
    - `internal/apps/kacho/api/sa_key/create.go` — `CreateUseCase`; deps: HydraAdminClient + SAKeyRepoWriter + AuditWriter.
    - `internal/apps/kacho/api/sa_key/delete.go` — `DeleteUseCase`; deps: HydraAdminClient + SAKeyRepoWriter + CAEPWriter.
    - `internal/apps/kacho/api/sa_key/list.go` — `ListUseCase`; deps: SAKeyRepoReader.
    - `internal/apps/kacho/api/sa_key/rotate.go` — `RotateUseCase`; deps: HydraAdminClient + SAKeyRepoWriter + CAEPWriter.
    - `internal/apps/kacho/api/sa_key/get.go` — `GetUseCase`; deps: SAKeyRepoReader.
    - `internal/apps/kacho/api/federation/create_policy.go` — `CreatePolicyUseCase`; deps: TrustPolicyRepoWriter + OIDCDiscoveryClient + AuditWriter.
    - `internal/apps/kacho/api/federation/update_policy.go` — `UpdatePolicyUseCase`.
    - `internal/apps/kacho/api/federation/delete_policy.go` — `DeletePolicyUseCase`.
    - `internal/apps/kacho/api/federation/get_policy.go`, `list_policy.go`.
    - `internal/apps/kacho/api/federation/exchange.go` — **самый сложный** use-case; deps: TrustPolicyRepoReader + JwksCache + JtiReplayRepoWriter + RateLimitRepoWriter + KachoJWTSigner + AuditWriter + ClockProvider.
- Repo: `internal/repo/sa_key.go` (Reader + Writer per CQRS), `internal/repo/federation_trust_policy.go`, `internal/repo/jti_replay.go`, `internal/repo/exchange_rate_limit.go`.
- Handler (thin): `internal/handler/sa_key/handler.go`, `internal/handler/federation/handler.go`.
- Wiring в `cmd/kacho-iam/main.go` — public mux: `SAKeyService` + `FederationExchangeService`; internal mux: `InternalTrustPolicyService`.
- Migration: `internal/migrations/0015_kac127_federation_rate_limits.sql` — `federation_exchange_rate_limits` + `federation_jti_replay` + partial indexes на `audit_outbox.event_type LIKE 'iam.federation.%'` и `caep_outbox.event_type LIKE 'iam.federation.%'`.
- Integration tests (Task 5.5): `internal/apps/kacho/api/federation/exchange_integration_test.go` — 8 providers × happy-path; `internal/apps/kacho/api/federation/exchange_negative_test.go` — все negative scenarios; `internal/repo/jti_replay_integration_test.go`, `internal/repo/exchange_rate_limit_integration_test.go` (concurrent goroutines testing CAS).

### 5.4 `kacho-api-gateway` PR (#4)

**Файлы:**
- `internal/restmux/mux.go` — два новых блока:
    - **Public** (TLS endpoint, `iamPublicAddr`): `SAKeyServiceHandlerFromEndpoint` (registers `/iam/v1/serviceAccounts/{sva_id}/keys` and `:rotate`, `:revoke`), `FederationExchangeServiceHandlerFromEndpoint` (registers `/iam/v1/federations:exchange`).
    - **Internal** (`iamInternalAddr`): `InternalTrustPolicyServiceHandlerFromEndpoint` (registers `/iam/v1/internalTrustPolicies` CRUD).
- Regression test `internal/restmux/mux_test.go` — **assert** `InternalTrustPolicyServiceHandlerFromEndpoint` НЕ зарегистрирован на `iamPublicAddr` (запрет #6 enforcement test).

### 5.5 `kacho-ui` PR (#5)

**Файлы:**
- `src/pages/iam/sa-keys/SAKeysPage.tsx` — list keys per SA, with revoke / rotate actions.
- `src/pages/iam/sa-keys/IssueKeyModal.tsx` — modal create form (description, expires_at) → on submit shows one-shot secret with copy button + scary warning "this secret is shown ONLY ONCE".
- `src/pages/iam/sa-keys/RotateKeyModal.tsx` — modal rotate flow (shows old key id + new key id + new secret one-shot).
- `src/pages/iam/federations/FederationPoliciesPage.tsx` — list policies per SA / per Account.
- `src/pages/iam/federations/CreatePolicyModal.tsx` — full form (issuer + audience + subject_pattern + additional_claims_filter JSON editor + conditions JSON editor + max_token_ttl slider).
- `src/pages/iam/federations/docs/{github-actions,aws-irsa,gcp-wif,gitlab-ci,bitbucket,circleci,buildkite,azure}.mdx` — copy-paste CI snippets для каждого provider.
- Playwright e2e: `e2e/sa-keys.spec.ts`, `e2e/federation-policies.spec.ts`.

### 5.6 `kacho-workspace` PR (#6)

**Файлы:**
- `docs/specs/sub-phase-3.5-iam-workload-identity-federation-acceptance.md` (этот файл).
- `obsidian/kacho/KAC/KAC-127.md` — обновить `Status: in-progress`, добавить ссылки на PRs 1-5.
- `obsidian/kacho/resources/iam-federation-trust-policy.md` — domain доска FK / lifecycle / immutables.
- `obsidian/kacho/resources/iam-service-account-key.md` — domain доска Class A SA-key.
- `obsidian/kacho/rpc/iam-federation-exchange-service.md` — RPC table.
- `obsidian/kacho/rpc/iam-sa-key-service.md` — RPC table.
- `obsidian/kacho/edges/external-cicd-to-iam-federation-exchange.md` — external→Kachō runtime edge.

---

## 6. Given-When-Then сценарии (50+ GWT)

> **ID convention**: `3.5-<section>.<n>` (e.g. `3.5-6.1.3`).
> **Traceability**: каждый GWT → integration test name (file:func) + newman case (file).
> **Mock issuers**: per-provider httptest server в `internal/apps/kacho/api/federation/testhelpers_test.go`
> с готовыми RSA-2048 keypairs + realistic claims templates.

### 6.1 SA-key Create (Class A)

#### Scenario 6.1.1 — Happy path: admin создаёт первый SA-key

**ID:** 3.5-6.1.1
**Mapping:** integration `TestSAKeyCreate_HappyPath`; newman `cases/sa_key_create_happy.py`.

**Given** ServiceAccount `sva_ci_deployer` существует в `prj_default`, `acc_a1b2`.
**And** User `usr_alice` имеет роль `kacho-system.editor` на `prj_default` (project-admin
эквивалент для OPA check).
**And** Hydra production-instance запущен на `hydra-admin.kacho.internal:4445` (mock в integration
test — httptest).

**When** Alice вызывает (через UI или grpcurl):
```
POST /iam/v1/serviceAccounts/sva_ci_deployer/keys
{
  "description": "CI deployer for prod terraform",
  "expires_at": "2026-11-19T00:00:00Z"
}
```

**Then** Response — `Operation{ done=false, metadata: { service_account_key_id: "sak_..." } }`.

**And** В течение ≤2s polling `OperationService.Get(operation_id)` → `done=true`,
`response = ServiceAccountKey{ id: "sak_h7q3...", sva_id: "sva_ci_deployer", hydra_client_id:
"kacho-sak-h7q3p5x9k2w8", description, created_at, expires_at,
client_secret_one_shot: "<random-32-bytes-base64url>" }`.

**And** `SELECT … FROM service_account_oauth_clients WHERE id='sak_h7q3...'` — row exists,
**нет** колонки `client_secret` или подобного (sanity check: secret НЕ persisted).

**And** Hydra-admin GET `/admin/clients/kacho-sak-h7q3p5x9k2w8` → returns OAuth client info
(`token_endpoint_auth_method=client_secret_basic`, `grant_types=["client_credentials"]`).

**And** `SELECT event_type FROM audit_outbox WHERE event_type='iam.sa.key.created' ORDER BY id
DESC LIMIT 1` — row exists с
`payload->>'sa_key_id'='sak_h7q3...'`, `payload->>'actor_user_id'='usr_alice'`.

**Idempotency note**: повторный вызов с **тем же** `description` + `expires_at` — НЕ
идемпотентен (создаёт второй key); idempotency key (HTTP-header `Idempotency-Key`) — Phase 7
follow-up. В Phase 5 — каждый Create → новый key + UNIQUE violation на `sva_id` если уже есть
active key (см. Scenario 6.1.2).

---

#### Scenario 6.1.2 — Повторный Create при существующем active key → AlreadyExists

**ID:** 3.5-6.1.2
**Mapping:** integration `TestSAKeyCreate_DuplicateActive`; newman `cases/sa_key_create_dup.py`.

**Given** Scenario 6.1.1 прошёл — есть active row `sak_h7q3...` для `sva_ci_deployer`.

**When** Alice повторно вызывает `CreateKey(sva_ci_deployer, ...)` (новый description).

**Then** Operation `done=true`, `error = { code: ALREADY_EXISTS, message: "ServiceAccountKey
already exists for sva_ci_deployer; use Rotate or Delete first", details: [
{type: "service_account_key_id", value: "sak_h7q3..."} ] }`.

**And** SQLSTATE `23505` от `service_account_oauth_clients_sva_unique` (partial UNIQUE WHERE
`replaces_id IS NULL`) — repo-уровень catches, service-уровень мапит в `AlreadyExists`.

**And** В Hydra ничего не создаётся (rollback — Hydra POST вызывается **после** DB constraint
check; в текущей impl idempotency не нужна, т.к. UNIQUE поймает раньше Hydra call'а).

**And** audit emit `iam.sa.key.create.denied` с reason `already_exists`.

---

#### Scenario 6.1.3 — Hydra возвращает 409 (другой client с тем же id) → idempotent re-fetch

**ID:** 3.5-6.1.3
**Mapping:** integration `TestSAKeyCreate_HydraConflictIdempotent`.

**Given** ServiceAccount `sva_test` существует.
**And** В Hydra **руками** (через operator-tooling) был создан client с `client_id=
kacho-sak-h7q3p5x9k2w8` (тот же который kacho-iam собирается генерить — collision
маловероятен, ~6 × 10^15 entropy, но возможен).

**When** Alice вызывает `CreateKey(sva_test, ...)`, kacho-iam генерирует hash → совпадает с
существующим Hydra-client'ом.

**Then** Hydra POST `/admin/clients` возвращает 409 Conflict.

**And** kacho-iam НЕ retry с **тем же** id (это бы привело к infinite loop); вместо этого: GET
`/admin/clients/kacho-sak-h7q3p5x9k2w8` — проверяет, есть ли **kacho-iam row** для этого
hydra_client_id.
   - Есть kacho-iam row → НЕ должно случиться (UNIQUE поймало бы раньше) → return `Internal`
     с alert.
   - Нет kacho-iam row → **orphan Hydra client** (manual cleanup нужен) → return `FailedPrecondition`
     "hydra client %s exists без kacho-iam ownership; contact admin".

**And** audit emit `iam.sa.key.create.orphan_hydra_client` с reason — alert engineer.

---

#### Scenario 6.1.4 — Permission denied: не-admin user пытается issue ключ

**ID:** 3.5-6.1.4
**Mapping:** integration `TestSAKeyCreate_PermissionDenied`; newman `cases/sa_key_create_denied.py`.

**Given** User `usr_bob` имеет `viewer` (read-only) на `prj_default`.

**When** Bob вызывает `CreateKey(sva_ci_deployer, ...)`.

**Then** OpenFGA Check returns `false` для `prj_default#admin@usr_bob`; service-уровень → gRPC
`PermissionDenied`, message `"user usr_bob does not have iam.serviceAccountKeys.create on
project prj_default"`.

**And** **No** Hydra POST (deny **before** any external side-effect).

**And** **No** DB INSERT.

**And** audit emit `iam.sa.key.create.denied` с reason `permission_denied`.

---

#### Scenario 6.1.5 — User-rate-limit: >1 IssueKey/sec/user → 429

**ID:** 3.5-6.1.5
**Mapping:** integration `TestSAKeyCreate_UserRateLimit`.

**Given** User `usr_alice` (project-admin) уже вызвала `CreateKey` 1 раз в эту секунду.

**When** Сразу второй `CreateKey` (тот же user, разный SA).

**Then** Response `ResourceExhausted`, message `"rate limit exceeded for user usr_alice"`.

**And** Rate-limit реализован через `corelib/ratelimit/` (LRU per-user token bucket; 1 req/s; burst
of 2; Phase 1 готовый пакет).

**And** audit emit `iam.sa.key.create.rate_limited` с reason — нечасто.

---

### 6.2 SA-key Delete

#### Scenario 6.2.1 — Happy path: admin revoke ключ

**ID:** 3.5-6.2.1
**Mapping:** integration `TestSAKeyDelete_HappyPath`; newman `cases/sa_key_delete_happy.py`.

**Given** SA-key `sak_h7q3...` существует (Scenario 6.1.1).
**And** Alice — project-admin.

**When** Alice вызывает:
```
DELETE /iam/v1/serviceAccounts/sva_ci_deployer/keys/sak_h7q3...
```

**Then** Operation `done=true` в ≤2s, `response = google.protobuf.Empty`.

**And** В Hydra `/admin/clients/kacho-sak-h7q3p5x9k2w8` — отсутствует (DELETE прошёл).

**And** `SELECT … FROM service_account_oauth_clients WHERE id='sak_h7q3...'` — пустая (hard
delete, не soft; per design нет need в soft-delete для SA-keys — audit trail хранится в
`audit_outbox`).

**And** `SELECT event_type FROM caep_outbox WHERE event_type='iam.sa.key.revoked' AND
subject_id='sak_h7q3...' LIMIT 1` — row exists, payload содержит `{ "subject":{ "format":
"opaque", "id":"sak_h7q3..." }, "events": { "https://schemas.openid.net/secevent/caep/event-
type/credential-change": { ... } } }`.

**And** audit `iam.sa.key.revoked` row в `audit_outbox`.

---

#### Scenario 6.2.2 — Существующие JWT с этим client_id → rejected after Hydra introspect

**ID:** 3.5-6.2.2
**Mapping:** integration `TestSAKeyDelete_ExistingJWTsRejected`.

**Given** Перед Scenario 6.2.1 CI/CD получил JWT через `client_credentials` flow (валидный JWT с
TTL 60min осталось 30min).

**When** Scenario 6.2.1 выполняется (revoke); затем CI/CD пытается API call с этим JWT.

**Then** API call к `api.kacho.cloud/vpc/v1/networks` — kacho-api-gateway валидирует JWT через
Hydra introspection (NOT just signature — для revoked client introspection вернёт
`active=false`); response `Unauthenticated` "token revoked".

**And** Это **не моментально** (Hydra introspect cache 5min) — допустимо ≤5min задержка; для
real-time revoke — CAEP push (Phase 8 picks up `iam.sa.key.revoked` event from `caep_outbox`
→ webhook to kacho-api-gateway → forces session_revocations row); в Phase 5 проверяем только
**факт записи в `caep_outbox`**, end-to-end real-time SLA — Phase 8 test.

---

#### Scenario 6.2.3 — Delete non-existent key → NotFound

**ID:** 3.5-6.2.3
**Mapping:** integration `TestSAKeyDelete_NotFound`; newman `cases/sa_key_delete_notfound.py`.

**When** Alice вызывает `DeleteKey(sva_ci_deployer, sak_nonexistent)`.

**Then** Operation `done=true`, `error = { code: NOT_FOUND, message: "ServiceAccountKey
sak_nonexistent not found" }`.

**And** Hydra DELETE НЕ вызывается (sanity — kacho-iam checks DB row first; не делает
"speculative" Hydra DELETE без mapping).

---

#### Scenario 6.2.4 — Delete уже-rotated key (replaces_id non-null) → допустимо (graceful)

**ID:** 3.5-6.2.4
**Mapping:** integration `TestSAKeyDelete_PreviouslyRotated`.

**Given** `sak_h7q3...` имеет `replaces_id IS NOT NULL` (т.е. был заменён через Rotate; новый key
`sak_new...` уже active; старый — в grace window до `expires_at = now() + 1h` Scenario 6.4).

**When** Alice вызывает `DeleteKey(sva_ci_deployer, sak_h7q3...)` (revoke до grace expiry).

**Then** Happy path — Hydra DELETE + DB DELETE + caep emit.

**And** Active key `sak_new...` НЕ затронут.

---

### 6.3 SA-key List

#### Scenario 6.3.1 — Happy path: list keys for SA — no secrets in response

**ID:** 3.5-6.3.1
**Mapping:** integration `TestSAKeyList_HappyPath_NoSecrets`; newman `cases/sa_key_list.py`.

**Given** Два active SA-keys: `sak_h7q3...` (Scenario 6.1.1) и `sak_x8m4...` (для другого SA в
том же project).

**When** Alice вызывает `ListKeys(sva_ci_deployer, page_size=10)`.

**Then** Response `{ keys: [ ServiceAccountKey{ id, sva_id, hydra_client_id, description,
created_at, expires_at, last_used_at } ], next_page_token: "" }`.

**And** **No** `client_secret` field в proto message `ServiceAccountKey` (per design D-12);
sanity-test: assert `ServiceAccountKey.fields_by_name` НЕ содержит `client_secret*`.

**And** Сортировка по `created_at DESC`.

---

#### Scenario 6.3.2 — Pagination: page_size=1, next_page_token roundtrip

**ID:** 3.5-6.3.2
**Mapping:** integration `TestSAKeyList_Pagination`.

**Given** 3 keys в SA `sva_test`.

**When** `ListKeys(sva_test, page_size=1)` → response с `keys[0]` (newest) + `next_page_token=
"<base64-encoded-cursor>"`.

**And** `ListKeys(sva_test, page_size=1, page_token=<...>)` → response с `keys[0]` (middle) +
`next_page_token`.

**And** Third call → response с `keys[0]` (oldest), `next_page_token=""` (end of list).

**Then** Pagination opaque cursor — base64 encoded `(created_at, id)` tuple (standard YC-style);
не передавать через клиент детали.

---

### 6.4 SA-key Rotate

#### Scenario 6.4.1 — Happy path: atomic dual-key + grace window

**ID:** 3.5-6.4.1
**Mapping:** integration `TestSAKeyRotate_HappyPath`; newman `cases/sa_key_rotate.py`.

**Given** Active key `sak_h7q3...` (Scenario 6.1.1).

**When** Alice вызывает:
```
POST /iam/v1/serviceAccounts/sva_ci_deployer/keys/sak_h7q3...:rotate
{
  "description": "rotated 2026-05-19",
  "grace_period_seconds": 3600
}
```

**Then** Operation `done=true` в ≤2s, `response = { old_key_id: "sak_h7q3...",
old_expires_at: "<now+1h>", new_key: ServiceAccountKey{ id: "sak_new..., ...
client_secret_one_shot: "<new-secret>" } }`.

**And** В DB:
- Row `sak_h7q3...` — обновлён: `expires_at = now() + 1h` (grace window starts), `replaces_id`
  остаётся NULL (это **старый** key, не replaces ничего).
- Row `sak_new...` — INSERT'нут: `replaces_id = 'sak_h7q3...'` (т.е. new key replaces old).
- partial UNIQUE на `sva_id` WHERE `replaces_id IS NULL` — **по-прежнему** один active row
  (старый `sak_h7q3...` с `replaces_id IS NULL` ещё считается "active" пока в grace window;
  новый `sak_new...` с `replaces_id IS NOT NULL` — пока не считается primary active).
- На expiry old key (через 1h) — cron-job (NOT в Phase 5; Phase 8 lifecycle) меняет:
  `UPDATE … SET replaces_id = 'sak_new...' WHERE id = 'sak_h7q3...'` (старый теперь "replaces
  himself" — formally still in DB но не active); и **симметрично** `UPDATE … SET replaces_id =
  NULL WHERE id = 'sak_new...'` (новый теперь primary active). Phase 5 — это **manual
  Delete** через Scenario 6.2 или 6.4.2.

**And** Hydra — два client'а: `kacho-sak-h7q3...` (старый, ещё валиден 1h) и `kacho-sak-new...`
(новый, валиден до expires_at policy).

**And** audit emit `iam.sa.key.rotated` с `{ old: "sak_h7q3...", new: "sak_new...",
grace_period_seconds: 3600 }`.

**And** caep emit (NOT `iam.sa.key.revoked` — старый ещё валиден; вместо этого
`iam.sa.key.rotation_announced` — informational event для subscribers).

---

#### Scenario 6.4.2 — Explicit revoke old key before grace expiry

**ID:** 3.5-6.4.2
**Mapping:** integration `TestSAKeyRotate_ExplicitRevokeOld`.

**Given** Scenario 6.4.1 завершён, есть old `sak_h7q3...` в grace.

**When** Alice deploy'нула new credential в CI и вызывает `DeleteKey(sva_ci_deployer,
sak_h7q3...)` (явный revoke, не ждать 1h).

**Then** Standard delete flow (Scenario 6.2.1) — Hydra DELETE + DB DELETE + caep
`iam.sa.key.revoked`.

**And** New `sak_new...` не затронут.

**And** `UPDATE … SET replaces_id = NULL WHERE id = 'sak_new...'` (new key promotes to primary
active — partial UNIQUE WHERE `replaces_id IS NULL` теперь правильный count=1).

---

#### Scenario 6.4.3 — Rotate без active key (нет существующего) → FailedPrecondition

**ID:** 3.5-6.4.3
**Mapping:** integration `TestSAKeyRotate_NoActiveKey`.

**When** Alice вызывает `RotateKey(sva_no_keys, sak_unknown:rotate)`.

**Then** `FailedPrecondition` "no existing key sak_unknown for sva_no_keys; use CreateKey
instead".

---

#### Scenario 6.4.4 — Concurrent rotate: два admin вызывают Rotate одновременно

**ID:** 3.5-6.4.4
**Mapping:** integration `TestSAKeyRotate_ConcurrentSafeBy_partialUnique`.

**Given** Active `sak_h7q3...`.

**When** Two goroutines одновременно `RotateKey(sva_ci_deployer, sak_h7q3...:rotate)`.

**Then** Один request успешен (создал `sak_new1...` с `replaces_id='sak_h7q3...'`).

**And** Второй request падает с SQLSTATE `23505` на **partial UNIQUE** `service_account_oauth_clients
_replaces_target_unique` (новый partial UNIQUE в миграции `0015` на `replaces_id` WHERE
`replaces_id IS NOT NULL` — не более одной row "replaces" same target); service-уровень
маппит в `Aborted` "concurrent rotation in progress for sak_h7q3...; retry".

**And** Никаких inconsistent состояний в DB — atomic CAS гарантия.

---

### 6.5 Trust Policy CRUD (admin-only)

#### Scenario 6.5.1 — Happy path: admin создаёт policy для GitHub Actions

**ID:** 3.5-6.5.1
**Mapping:** integration `TestTrustPolicyCreate_GitHubHappy`; newman `cases/trust_policy_github.py`.

**Given** Alice — project-admin `prj_default`; ServiceAccount `sva_ci_deployer` существует.

**When** Alice вызывает (на internal endpoint 9091; через UI internal proxy):
```
POST /iam/v1/internalTrustPolicies
{
  "service_account_id": "sva_ci_deployer",
  "issuer": "https://token.actions.githubusercontent.com",
  "audience": "https://api.kacho.cloud",
  "subject_pattern": "repo:my-org/my-repo:ref:refs/heads/main",
  "additional_claims_filter": {
    "workflow": "deploy.yml",
    "environment": "production"
  },
  "conditions": {
    "source_ip_cidrs": []
  },
  "max_token_ttl": "900s",
  "expires_at": "2026-11-19T00:00:00Z"
}
```

**Then** Operation `done=true`, `response = FederationTrustPolicy{ id: "ftp_h3k9...", ..., enabled:
true }`.

**And** OIDC discovery validation: HTTP GET `https://token.actions.githubusercontent.com/.well-
known/openid-configuration` (через `corelib/oidc/discovery.go`) — returns `{"jwks_uri":
"https://...", ...}` — passes.

**And** `SELECT … FROM federation_trust_policies WHERE id='ftp_h3k9...'` — row exists с
правильными полями.

**And** audit emit `iam.federation.policy.created` с `{ ftp_id, issuer, subject_pattern, sva_id,
actor_user_id }`.

---

#### Scenario 6.5.2 — subject_pattern с wildcard `*` → InvalidArgument

**ID:** 3.5-6.5.2
**Mapping:** integration `TestTrustPolicyCreate_Wildcard`; newman `cases/trust_policy_wildcard.py`.

**When** Alice вызывает CreateTrustPolicy с `subject_pattern = "repo:my-org/*:ref:refs/heads/main"`.

**Then** Response `InvalidArgument` "subject_pattern contains forbidden glob characters (*, ?, [,
], {, }, \\); use exact match".

**And** Service-уровень **до** DB insert вызывает `domain.SubjectPattern.Validate()` (self-validating
newtype per skill `evgeniy`); rejects glob чтоб не полагаться **только** на DB CHECK (faster
error feedback + cleaner error message). DB CHECK — safety net (тестируется отдельно в Phase 1
Scenario 6.6.2, повторяться здесь не нужно).

---

#### Scenario 6.5.3 — expires_at > created_at + 1y → InvalidArgument

**ID:** 3.5-6.5.3
**Mapping:** integration `TestTrustPolicyCreate_ExpiresTooFar`; newman `cases/trust_policy_expires_too_far.py`.

**When** Alice вызывает с `expires_at = now() + 2y`.

**Then** Response `InvalidArgument` "expires_at exceeds maximum 1 year from creation".

---

#### Scenario 6.5.4 — Issuer OIDC discovery fails → InvalidArgument

**ID:** 3.5-6.5.4
**Mapping:** integration `TestTrustPolicyCreate_BadIssuer`.

**When** Alice вызывает с `issuer = "https://does-not-exist-12345.example.com"`.

**Then** OIDC discovery HTTP GET → DNS error / 404 / invalid JSON.
**And** Response `InvalidArgument` "issuer %s OIDC discovery failed: %s".

**And** **No** DB INSERT (validation before insert).

---

#### Scenario 6.5.5 — HTTP issuer (no TLS) → InvalidArgument

**ID:** 3.5-6.5.5
**Mapping:** integration `TestTrustPolicyCreate_HTTPIssuer`.

**When** Alice вызывает с `issuer = "http://oidc.local"`.

**Then** Response `InvalidArgument` "issuer must use https:// (got http://)".

---

#### Scenario 6.5.6 — Update: enabled + expires_at + conditions mutable

**ID:** 3.5-6.5.6
**Mapping:** integration `TestTrustPolicyUpdate_MutableFields`; newman `cases/trust_policy_update.py`.

**Given** `ftp_h3k9...` существует (Scenario 6.5.1).

**When** Alice вызывает:
```
PATCH /iam/v1/internalTrustPolicies/ftp_h3k9...
{
  "update_mask": "enabled,expires_at,conditions",
  "enabled": false,
  "expires_at": "2026-08-19T00:00:00Z",
  "conditions": {"source_ip_cidrs": ["10.0.0.0/8"]}
}
```

**Then** Operation `done=true`, `response = FederationTrustPolicy{ ..., enabled: false, expires_at:
2026-08-19, conditions: {source_ip_cidrs:[10.0.0.0/8]} }`.

**And** `subject_pattern`, `audience`, `issuer`, `service_account_id`, `additional_claims_filter`,
`max_token_ttl` — **не изменились**.

**And** audit `iam.federation.policy.updated` с `{ ftp_id, updated_fields: ["enabled","expires_at",
"conditions"] }`.

---

#### Scenario 6.5.7 — Update immutable field → InvalidArgument

**ID:** 3.5-6.5.7
**Mapping:** integration `TestTrustPolicyUpdate_Immutable`; newman `cases/trust_policy_update_immutable.py`.

**When** Alice вызывает с `update_mask: "subject_pattern"`, новый `subject_pattern =
"repo:my-org/my-repo:ref:refs/heads/develop"`.

**Then** Response `InvalidArgument` "subject_pattern is immutable after FederationTrustPolicy.Create".

**And** `update_mask: "issuer"`, `audience`, `service_account_id`, `additional_claims_filter`,
`max_token_ttl` — **одинаково** rejected (отдельный test case на каждый — параметризованный
test).

---

#### Scenario 6.5.8 — Update extends expires_at > 1y from **original** created_at → InvalidArgument

**ID:** 3.5-6.5.8
**Mapping:** integration `TestTrustPolicyUpdate_ExtendBeyondOriginalLimit`.

**Given** `ftp_h3k9...` создан `2026-05-19`, `expires_at = 2026-11-19`.

**When** Alice вызывает Update с `expires_at = 2027-08-19` (т.е. > 1y от created_at 2026-05-19).

**Then** Response `InvalidArgument` "expires_at exceeds maximum 1 year from creation
(2026-05-19); rotate policy through Delete+Create for further extension".

**And** DB CHECK `expires_within_year_ck` обеспечивает консистентность — даже если бы service
layer пропустил, DB поймала бы.

---

#### Scenario 6.5.9 — Delete trust policy → cascade emits

**ID:** 3.5-6.5.9
**Mapping:** integration `TestTrustPolicyDelete_HappyPath`; newman `cases/trust_policy_delete.py`.

**When** Alice вызывает `DeleteTrustPolicy(ftp_h3k9...)`.

**Then** Operation `done=true`.

**And** Row deleted из `federation_trust_policies`.

**And** audit `iam.federation.policy.deleted`.

**And** caep `iam.federation.policy.revoked` (informational; subscribers могут invalidate любые
cached principals из этой policy).

**And** Любой in-flight exchange с этой policy — Phase 5 атомарность: exchange reads policy
**within transaction**; если policy deleted **между** read и issue → exchange всё равно
завершается успехом (TX isolation); next exchange — `PermissionDenied` "policy not found".

---

#### Scenario 6.5.10 — List policies per SA, pagination

**ID:** 3.5-6.5.10
**Mapping:** integration `TestTrustPolicyList_Pagination`.

**Given** 5 policies для `sva_ci_deployer` (разные issuers / subject_patterns).

**When** `ListTrustPolicies(service_account_id="sva_ci_deployer", page_size=2)` —
roundtrip как в Scenario 6.3.2.

**Then** 3 calls (2 + 2 + 1) возвращают все policies; pagination cursor opaque.

---

### 6.6 Federation Exchange — happy path per provider (8 providers)

> Для каждого provider'а — 1 happy-path scenario, доказывающий что end-to-end flow работает.
> Подробное negative — §6.7 ниже, generic (не привязано к provider'у).

#### Scenario 6.6.1 — GitHub Actions happy path

**ID:** 3.5-6.6.1
**Mapping:** integration `TestExchange_GitHubActions_Happy`; newman `cases/exchange_github.py`.

**Given** Trust policy `ftp_gha_main`:
- `issuer = "https://token.actions.githubusercontent.com"`
- `audience = "https://api.kacho.cloud"`
- `subject_pattern = "repo:my-org/my-repo:ref:refs/heads/main"`
- `additional_claims_filter = {"workflow":"deploy.yml","environment":"production"}`
- `service_account_id = "sva_ci_deployer"`
- `max_token_ttl = 15min`
- `enabled = true`, `expires_at = 2026-11-19`.

**And** Mock GitHub OIDC issuer (httptest server) issues JWT:
```
{
  "iss": "https://token.actions.githubusercontent.com",
  "sub": "repo:my-org/my-repo:ref:refs/heads/main",
  "aud": "https://api.kacho.cloud",
  "exp": <now+10min>,
  "iat": <now>, "nbf": <now>, "jti": "<uuid>",
  "repository": "my-org/my-repo",
  "workflow": "deploy.yml",
  "environment": "production",
  "actor": "alice",
  "event_name": "push"
}
```
Signed with RSA-2048 key, kid embedded.

**When** Exchange вызов:
```
POST /iam/v1/federations:exchange
Content-Type: application/x-www-form-urlencoded

grant_type=urn:ietf:params:oauth:grant-type:token-exchange
&subject_token=<external-JWT>
&subject_token_type=urn:ietf:params:oauth:token-type:jwt
&audience=https://api.kacho.cloud
```

**Then** Response HTTP 200, body JSON:
```
{
  "access_token": "<kachō-jwt>",
  "issued_token_type": "urn:ietf:params:oauth:token-type:jwt",
  "token_type": "Bearer",
  "expires_in": 900
}
```

**And** Kachō JWT decode:
- `iss = "https://hydra.kacho.cloud"`
- `sub = "sva_ci_deployer"`
- `aud = ["https://api.kacho.cloud"]`
- `exp = now + 900s`
- `ext_claims.kacho_principal_type = "federated_service_account"`
- `ext_claims.kacho_federation_policy = "ftp_gha_main"`
- `ext_claims.kacho_external_subject = "repo:my-org/my-repo:ref:refs/heads/main"`
- `ext_claims.kacho_external_issuer = "https://token.actions.githubusercontent.com"`

**And** Subsequent API call с Kachō JWT — `kacho-vpc.ListNetworks(prj_default)` — успешен (FGA
проверяет `prj_default#editor@sva_ci_deployer` — passes).

**And** `SELECT … FROM federation_jti_replay WHERE jti = '<uuid-from-external-jwt>'` — row
exists.

**And** audit `iam.federation.exchange.success` с `{ ftp_id: "ftp_gha_main", external_iss,
external_sub, external_jti, kacho_jwt_jti, sva_id, expires_in }`.

---

#### Scenario 6.6.2 — AWS IRSA (EKS) happy path

**ID:** 3.5-6.6.2
**Mapping:** integration `TestExchange_AWSIRSA_Happy`; newman `cases/exchange_aws_irsa.py`.

**Given** Trust policy `ftp_aws_eks`:
- `issuer = "https://oidc.eks.eu-west-1.amazonaws.com/id/<cluster-id>"`
- `subject_pattern = "system:serviceaccount:my-ns:my-sa"`
- `additional_claims_filter = {}` (none).

**And** Mock AWS issuer JWT with claims:
```
{
  "iss": "https://oidc.eks.eu-west-1.amazonaws.com/id/<cluster-id>",
  "sub": "system:serviceaccount:my-ns:my-sa",
  "aud": "https://api.kacho.cloud",
  "exp": <now+1h>, "iat": <now>, "jti": "<uuid>",
  "kubernetes.io": { "namespace":"my-ns", "serviceaccount":{"name":"my-sa","uid":"..."} }
}
```

**When** Exchange.

**Then** Standard 200 with Kachō JWT, `kacho_external_subject = "system:serviceaccount:my-ns:my-sa"`,
`kacho_external_issuer = "https://oidc.eks.eu-west-1.amazonaws.com/id/<cluster-id>"`.

---

#### Scenario 6.6.3 — GCP Workload Identity Federation happy path

**ID:** 3.5-6.6.3
**Mapping:** integration `TestExchange_GCPWIF_Happy`; newman `cases/exchange_gcp_wif.py`.

**Given** Trust policy `ftp_gcp_wif`:
- `issuer = "https://iam.googleapis.com"` (workload pool federation issuer)
- `subject_pattern = "principal://iam.googleapis.com/projects/123456/locations/global/workloadIdentityPools/kacho-pool/subject/my-workload"`

**And** Mock GCP issuer JWT.

**When** Exchange.

**Then** Standard 200, claims preserved.

---

#### Scenario 6.6.4 — GitLab CI happy path

**ID:** 3.5-6.6.4
**Mapping:** integration `TestExchange_GitLabCI_Happy`; newman `cases/exchange_gitlab.py`.

**Given** Trust policy `ftp_gitlab_main`:
- `issuer = "https://gitlab.com"`
- `subject_pattern = "project_path:my-group/my-project:ref_type:branch:ref:main"`
- `additional_claims_filter = {"environment":"production"}`.

**And** Mock GitLab issuer JWT.

**When** Exchange.

**Then** Standard 200.

---

#### Scenario 6.6.5 — Bitbucket Pipelines happy path

**ID:** 3.5-6.6.5
**Mapping:** integration `TestExchange_Bitbucket_Happy`; newman `cases/exchange_bitbucket.py`.

**Given** Trust policy `ftp_bb_deploy`.

**And** Mock Bitbucket issuer JWT.

**When** Exchange.

**Then** Standard 200.

---

#### Scenario 6.6.6 — CircleCI happy path

**ID:** 3.5-6.6.6
**Mapping:** integration `TestExchange_CircleCI_Happy`; newman `cases/exchange_circleci.py`.

**Given** Trust policy `ftp_circle_prod`.

**And** Mock CircleCI issuer JWT.

**When** Exchange.

**Then** Standard 200.

---

#### Scenario 6.6.7 — Buildkite happy path

**ID:** 3.5-6.6.7
**Mapping:** integration `TestExchange_Buildkite_Happy`; newman `cases/exchange_buildkite.py`.

**Given** Trust policy `ftp_bk_main`.

**And** Mock Buildkite issuer JWT.

**When** Exchange.

**Then** Standard 200.

---

#### Scenario 6.6.8 — Azure Workload Identity happy path

**ID:** 3.5-6.6.8
**Mapping:** integration `TestExchange_AzureWI_Happy`; newman `cases/exchange_azure.py`.

**Given** Trust policy `ftp_azure_aks`:
- `issuer = "https://login.microsoftonline.com/<tenant-id>/v2.0"`
- `subject_pattern = "<service-principal-object-id>"`

**And** Mock Azure issuer JWT.

**When** Exchange.

**Then** Standard 200.

---

### 6.7 Federation Exchange — negative scenarios (generic)

#### Scenario 6.7.1 — subject_pattern mismatch → PermissionDenied

**ID:** 3.5-6.7.1
**Mapping:** integration `TestExchange_SubjectPatternMismatch`; newman `cases/exchange_subj_mismatch.py`.

**Given** Trust policy с `subject_pattern = "repo:my-org/my-repo:ref:refs/heads/main"`.

**When** External JWT with `sub = "repo:my-org/my-repo:ref:refs/heads/develop"` (different branch).

**Then** Response HTTP 403, JSON `{ "error": "permission_denied", "error_description": "subject
'repo:my-org/my-repo:ref:refs/heads/develop' does not match any trust policy for issuer
'https://token.actions.githubusercontent.com'" }` (RFC 8693 / RFC 6749 §5.2 error format).

**And** audit `iam.federation.exchange.denied` reason `subject_pattern_mismatch`.

**And** **No** Kachō JWT issued.

**And** **No** jti row in `federation_jti_replay` (denied — не trash таблицу).

---

#### Scenario 6.7.2 — Expired trust policy → Unauthenticated

**ID:** 3.5-6.7.2
**Mapping:** integration `TestExchange_ExpiredPolicy`; newman `cases/exchange_policy_expired.py`.

**Given** Trust policy с `expires_at = 2026-05-18T23:59:59Z` (вчера); `enabled = true` (но
expired).

**When** Exchange today.

**Then** Response HTTP 401, JSON `{ "error": "invalid_grant", "error_description": "federation
policy 'ftp_gha_main' expired at 2026-05-18T23:59:59Z" }`.

**And** Lookup query `WHERE expires_at > now()` сразу не matches → query returns 0 rows
→ same code path как Scenario 6.7.1 но с **более точным** reason field в audit:
`policy_expired`.

**And** caep emit `iam.federation.policy.expired` (если есть subscribers) — once-per-policy
(deduped by `caep_outbox.dedup_key='ftp_gha_main:expired'`).

---

#### Scenario 6.7.3 — additional_claims_filter mismatch → PermissionDenied

**ID:** 3.5-6.7.3
**Mapping:** integration `TestExchange_ClaimsFilterMismatch`; newman `cases/exchange_claims_mismatch.py`.

**Given** Trust policy с `additional_claims_filter = {"environment":"production"}`.

**When** External JWT with claim `"environment":"staging"`.

**Then** Response 403, reason `additional_claims_mismatch`, detail `{"failed_claims":
{"environment":{"expected":"production","got":"staging"}}}`.

---

#### Scenario 6.7.4 — Missing required claim → PermissionDenied

**ID:** 3.5-6.7.4
**Mapping:** integration `TestExchange_MissingClaim`.

**Given** Trust policy с `additional_claims_filter = {"environment":"production"}`.

**When** External JWT **без** claim `environment` (полностью отсутствует).

**Then** Response 403, reason `additional_claims_mismatch`, detail `{"failed_claims":
{"environment":{"expected":"production","got":null}}}` (case-sensitive missing).

---

#### Scenario 6.7.5 — source_ip outside CIDR → PermissionDenied

**ID:** 3.5-6.7.5
**Mapping:** integration `TestExchange_SourceIPDeny`; newman `cases/exchange_source_ip_deny.py`.

**Given** Trust policy с `conditions.source_ip_cidrs = ["10.0.0.0/8"]`.

**When** Exchange call с `X-Forwarded-For: 192.168.1.42` (outside CIDR).

**Then** Response 403, reason `source_ip_outside_allowed_cidrs`, detail `{"source_ip":"192.168.1.42",
"allowed_cidrs":["10.0.0.0/8"]}`.

**And** Source IP — берётся **первый** в `X-Forwarded-For` chain (left-most = client; правый —
прокси Cloudflare); production setup: Cloudflare передаёт `CF-Connecting-IP` — но Phase 5
полагается на `X-Forwarded-For` (стандартный) + проверяет первый IP `net.ParseIP(strings.
TrimSpace(strings.Split(x_forwarded_for, ",")[0]))`.

---

#### Scenario 6.7.6 — Tampered signature → Unauthenticated

**ID:** 3.5-6.7.6
**Mapping:** integration `TestExchange_TamperedSignature`; newman `cases/exchange_tampered.py`.

**When** External JWT с modified payload (изменён `sub`) и **оригинальной** signature (не
re-signed).

**Then** JWKS verify fails → Response HTTP 401, error `invalid_grant`, error_description
`"subject_token signature verification failed"`.

**And** audit reason `signature_invalid`.

---

#### Scenario 6.7.7 — JTI replay → Unauthenticated

**ID:** 3.5-6.7.7
**Mapping:** integration `TestExchange_JtiReplay`; newman `cases/exchange_jti_replay.py`.

**Given** Successful Exchange (Scenario 6.6.1) — jti `<uuid>` запомнен в `federation_jti_replay`.

**When** Повторный Exchange с **тем же** external JWT (тот же jti).

**Then** Response HTTP 401, error `invalid_grant`, error_description `"subject_token already
exchanged (jti replay)"`.

**And** Partial UNIQUE на `(jti, issuer)` ловит SQLSTATE 23505 при INSERT; service-уровень мапит
в Unauthenticated с этим текстом.

**And** audit reason `jti_replay`.

---

#### Scenario 6.7.8 — Future nbf → Unauthenticated

**ID:** 3.5-6.7.8
**Mapping:** integration `TestExchange_FutureNbf`.

**When** External JWT с `nbf = now() + 1h`.

**Then** Response 401, error_description `"subject_token not yet valid (nbf in future)"`.

**And** Clock skew tolerance ≤5min (standard) — `nbf > now()+5min` → reject; `nbf in [now()-5min,
now()+5min]` → accept.

---

#### Scenario 6.7.9 — Expired external JWT → Unauthenticated

**ID:** 3.5-6.7.9
**Mapping:** integration `TestExchange_ExternalExpired`.

**When** External JWT с `exp = now() - 1h`.

**Then** Response 401, error_description `"subject_token expired at ..."`.

---

#### Scenario 6.7.10 — Wrong audience → PermissionDenied

**ID:** 3.5-6.7.10
**Mapping:** integration `TestExchange_WrongAudience`; newman `cases/exchange_wrong_aud.py`.

**Given** Trust policy с `audience = "https://api.kacho.cloud"`.

**When** External JWT с `aud = "https://api.other-provider.com"` (не для Kachō).

**Then** Response 403, reason `audience_mismatch`, error_description `"subject_token audience
['https://api.other-provider.com'] does not match policy audience 'https://api.kacho.cloud'"`.

---

#### Scenario 6.7.11 — business_hours condition violation → PermissionDenied

**ID:** 3.5-6.7.11
**Mapping:** integration `TestExchange_BusinessHoursDeny`; newman `cases/exchange_business_hours.py`.

**Given** Trust policy с `conditions.business_hours = {"timezone":"Europe/Berlin","start_h":9,
"end_h":18}`.

**When** Exchange call в `02:30 UTC` (= `03:30 Berlin`, outside [9, 18)).

**Then** Response 403, reason `outside_business_hours`, detail `{"now_in_tz":"03:30 Europe/Berlin",
"allowed":"09-18"}`.

**And** Tests используют faketime через `clockProvider.SetNow(time.Date(...))` — не реальное
системное время.

---

#### Scenario 6.7.12 — Disabled policy → PermissionDenied

**ID:** 3.5-6.7.12
**Mapping:** integration `TestExchange_PolicyDisabled`; newman `cases/exchange_policy_disabled.py`.

**Given** Trust policy `ftp_gha_main` с `enabled = false` (выключен через Scenario 6.5.6 или
Phase 11 auto-disable).

**When** Exchange.

**Then** Lookup `WHERE enabled = true AND ...` — no match → Response 403, reason
`policy_disabled_or_not_found`.

---

#### Scenario 6.7.13 — Issuer JWKS endpoint unreachable → Unavailable (degraded if cached)

**ID:** 3.5-6.7.13
**Mapping:** integration `TestExchange_JWKSUnreachable_Degraded`.

**Given** Trust policy `ftp_gha_main`; JWKS cache **has** valid entry for GitHub (24h TTL не
истёк).

**When** Exchange + mock GitHub JWKS endpoint вернул 503 (simulated outage).

**Then** Verification использует **cached** JWKS keys → Exchange success (HTTP 200).

**And** Metric `iam_jwks_cache_hits_total{issuer="https://token.actions.githubusercontent.com"}`
incremented; **no** call to JWKS endpoint (cache hit).

---

#### Scenario 6.7.14 — Issuer JWKS endpoint unreachable + cache expired → Unavailable

**ID:** 3.5-6.7.14
**Mapping:** integration `TestExchange_JWKSUnreachable_NoCache`.

**Given** Trust policy; JWKS cache empty (никогда не fetch'или OR TTL истёк OR `kid` не найден).

**When** Exchange + JWKS endpoint вернул 503.

**Then** Response HTTP 503 Unavailable, error `temporarily_unavailable`, error_description
`"issuer JWKS unreachable; retry later"`.

**And** **Stale fallback**: если есть **expired** entry — используется, emit metric
`iam_jwks_stale_fallback_total{issuer="..."}` + WARN log. Если нет вообще — 503.

**And** audit reason `jwks_unavailable`.

---

### 6.8 JWKS cache behaviour

#### Scenario 6.8.1 — 24h TTL: cache hit within 24h, refresh after

**ID:** 3.5-6.8.1
**Mapping:** integration `TestJWKSCache_TTL`.

**Given** First Exchange call fetches JWKS at `T0`; cache entry stored с `fetched_at=T0`.

**When** Second Exchange call at `T0+23h59m` (within TTL).

**Then** Cache HIT — no HTTP fetch; metric `iam_jwks_cache_hits_total` incremented.

**And** Third Exchange call at `T0+24h01m` — cache MISS (TTL expired); HTTP fetch; metric
`iam_jwks_cache_misses_total` incremented; cache entry updated с `fetched_at=T0+24h01m`.

**And** Tests используют `clockProvider.SetNow(T0+24h01m)` — не реальное время.

---

#### Scenario 6.8.2 — kid miss → force refresh

**ID:** 3.5-6.8.2
**Mapping:** integration `TestJWKSCache_KidMissRefresh`.

**Given** Cache contains `{kid_old: <key>}`; TTL not expired.

**When** Exchange call с external JWT signed by `kid_new` (issuer сделал unscheduled rotation).

**Then** Cache lookup `kid_new` → not found → force refresh (HTTP fetch); cache updated с
`{kid_old, kid_new}` (oba); verify proceeds; Exchange success.

**And** Metric `iam_jwks_cache_kid_miss_refresh_total` incremented.

---

#### Scenario 6.8.3 — Concurrent kid miss — `singleflight` collapses

**ID:** 3.5-6.8.3
**Mapping:** integration `TestJWKSCache_Singleflight`.

**Given** Cache contains `{kid_old}`.

**When** 100 concurrent Exchange calls, все с `kid_new`.

**Then** Exactly **one** HTTP fetch (singleflight collapses concurrent requests); все 100
ожидают результат, потом все либо ✅ либо ❌ симметрично.

**And** Tests через httptest server counts requests — assert `requests_received == 1`.

---

#### Scenario 6.8.4 — Multiple issuers — independent caches

**ID:** 3.5-6.8.4
**Mapping:** integration `TestJWKSCache_PerIssuerIsolation`.

**Given** Cache has entries for `github`, `aws`, `gcp` (3 different issuers).

**When** Force refresh `github` (kid miss).

**Then** Только entry для `github` обновлена; `aws` / `gcp` — untouched.

---

#### Scenario 6.8.5 — LRU eviction at capacity

**ID:** 3.5-6.8.5
**Mapping:** integration `TestJWKSCache_LRUEviction`.

**Given** Cache max 100 issuers (config); сейчас 100 issuers.

**When** Exchange call с new issuer (101-й).

**Then** LRU eviction — least-recently-used issuer удалён, new — добавлен.

**And** Eviction metrics `iam_jwks_cache_evictions_total`.

---

### 6.9 subject_pattern validation (regex / format)

> Большая часть DB-уровня покрыта в Phase 1 Scenario 6.6.2-6.6.5; здесь — service-уровень
> (`domain.SubjectPattern.Validate()`) + edge cases.

#### Scenario 6.9.1 — Wildcard `*` rejected at create

**ID:** 3.5-6.9.1
**Mapping:** integration `TestSubjectPattern_WildcardRejected`.

**When** subject_pattern = `"repo:my-org/*:ref:refs/heads/main"`.

**Then** Service-layer `domain.NewSubjectPattern()` returns ErrInvalidSubjectPattern; gRPC
`InvalidArgument`.

---

#### Scenario 6.9.2 — Literal exact match accepted

**ID:** 3.5-6.9.2
**Mapping:** integration `TestSubjectPattern_LiteralExact`.

**When** subject_pattern = `"repo:my-org/my-repo:ref:refs/heads/main"`.

**Then** Accepted.

---

#### Scenario 6.9.3 — Path-like / colon-separated accepted

**ID:** 3.5-6.9.3
**Mapping:** integration `TestSubjectPattern_PathSeparators`.

**When** subject_pattern = `"system:serviceaccount:my-ns:my-sa"` (AWS IRSA), or `"<uuid>:<uuid>:
<uuid>"` (Bitbucket).

**Then** Accepted (forward-slash `/` и colon `:` разрешены — это path separators, не glob).

---

#### Scenario 6.9.4 — Empty subject_pattern → InvalidArgument

**ID:** 3.5-6.9.4
**Mapping:** integration `TestSubjectPattern_Empty`.

**When** subject_pattern = `""`.

**Then** `InvalidArgument` "subject_pattern is required".

---

#### Scenario 6.9.5 — Too-long subject_pattern → InvalidArgument

**ID:** 3.5-6.9.5
**Mapping:** integration `TestSubjectPattern_TooLong`.

**When** subject_pattern = `<1024 chars>`.

**Then** `InvalidArgument` "subject_pattern exceeds max 512 chars".

---

#### Scenario 6.9.6 — Special characters validated

**ID:** 3.5-6.9.6
**Mapping:** integration `TestSubjectPattern_SpecialChars`.

**When** subject_pattern содержит `\n`, `\t`, control chars, NUL byte.

**Then** `InvalidArgument` "subject_pattern contains control characters".

---

### 6.10 Audit + CAEP integration

#### Scenario 6.10.1 — Exchange success → audit row

**ID:** 3.5-6.10.1
**Mapping:** integration `TestExchange_AuditEmit_Success`.

**Given** Scenario 6.6.1 happy-path.

**Then** `SELECT * FROM audit_outbox WHERE event_type='iam.federation.exchange.success' ORDER
BY id DESC LIMIT 1` returns row с payload:
```json
{
  "event_type": "iam.federation.exchange.success",
  "actor": {"type":"federated_service_account","id":"sva_ci_deployer"},
  "target": {"type":"federation_trust_policy","id":"ftp_gha_main"},
  "outcome": "success",
  "external_iss": "https://token.actions.githubusercontent.com",
  "external_sub": "repo:my-org/my-repo:ref:refs/heads/main",
  "external_jti": "<uuid>",
  "kacho_jwt_jti": "<uuid-v7>",
  "expires_in": 900,
  "source_ip": "<X-Forwarded-For first>",
  "timestamp": "2026-05-19T..."
}
```

**And** Drainer (Phase 8) eventually forwards в Kafka; здесь только check row exists.

---

#### Scenario 6.10.2 — Exchange denied → audit row с reason

**ID:** 3.5-6.10.2
**Mapping:** integration `TestExchange_AuditEmit_Denied`.

**Given** Scenario 6.7.1 (subject_pattern_mismatch).

**Then** `audit_outbox` row с `event_type='iam.federation.exchange.denied'` + `payload->>'reason'
='subject_pattern_mismatch'`.

---

#### Scenario 6.10.3 — SA-key revoke → caep_outbox row

**ID:** 3.5-6.10.3
**Mapping:** integration `TestSAKeyDelete_CAEPEmit`.

**Given** Scenario 6.2.1 (key revoke).

**Then** `SELECT … FROM caep_outbox WHERE event_type='iam.sa.key.revoked'` row с payload
СET-формата:
```json
{
  "iss": "https://api.kacho.cloud",
  "iat": <now>, "jti":"<uuid>",
  "events": {
    "https://schemas.openid.net/secevent/caep/event-type/credential-change": {
      "subject": {"format":"opaque","id":"sak_h7q3..."},
      "credential_type": "service_account_oauth_client",
      "change_type": "revoke",
      "event_timestamp": <now>
    }
  }
}
```

---

#### Scenario 6.10.4 — Trust policy expiry → auto-disable + caep event (Phase 11 cron precursor)

**ID:** 3.5-6.10.4
**Mapping:** integration `TestTrustPolicyExpiry_AutoDisable`.

**Given** Policy `ftp_test` с `expires_at = now() - 1s` (expired).

**When** Exchange call (Scenario 6.7.2 = expired-policy 403).

**Then** **Inline** — Phase 5 не делает explicit `UPDATE … SET enabled = false` (это Phase 11
cron-job); вместо этого lookup `WHERE expires_at > now()` сам not-match → effective
auto-disable.

**And** caep emit `iam.federation.policy.expired` — once per (policy_id, day) — deduped
`caep_outbox.dedup_key = 'ftp_test:expired:2026-05-19'` (partial UNIQUE WHERE dedup_key IS NOT
NULL).

---

#### Scenario 6.10.5 — Trust policy created → audit + caep informational

**ID:** 3.5-6.10.5
**Mapping:** integration `TestTrustPolicyCreate_Emits`.

**Given** Scenario 6.5.1.

**Then** audit `iam.federation.policy.created`; caep `iam.federation.policy.created`
(informational; subscribers know new trust policy registered).

---

### 6.11 Per-issuer rate-limit + jti replay

#### Scenario 6.11.1 — Within limit: 99 exchanges/min — all succeed

**ID:** 3.5-6.11.1
**Mapping:** integration `TestRateLimit_WithinLimit`.

**Given** Trust policy `ftp_test`, mock issuer, valid subject_token.

**When** Loop 99 exchanges within 1 minute (each с unique jti).

**Then** Все 99 успешны; rate-limit bucket: `tokens` падает с 100 → 1.

---

#### Scenario 6.11.2 — Exceeded limit: 101-й exchange → 429

**ID:** 3.5-6.11.2
**Mapping:** integration `TestRateLimit_Exceeded`; newman `cases/exchange_rate_limit.py`.

**Given** Scenario 6.11.1 заполнил bucket (99 successful; bucket tokens=1).

**When** 100-й exchange — success (tokens=0); 101-й exchange — atomic INSERT…ON CONFLICT
returns 0 rows.

**Then** Response HTTP 429 Too Many Requests, error `temporarily_unavailable`,
error_description `"rate limit exceeded for issuer https://...; max 100 exchanges/min"`.

**And** Retry-After header `60` (seconds until next bucket).

**And** audit `iam.federation.rate_limit.exceeded` + warning log.

---

#### Scenario 6.11.3 — Bucket rollover: at minute boundary, fresh 100 tokens

**ID:** 3.5-6.11.3
**Mapping:** integration `TestRateLimit_BucketRollover`.

**Given** Bucket `(issuer, '2026-05-19T10:34:00Z')` exhausted (tokens=0).

**When** Exchange at `2026-05-19T10:35:00Z` (next minute).

**Then** New bucket row `(issuer, '2026-05-19T10:35:00Z')` created с `tokens=99`; exchange
succeeds.

**And** Старая row не удалена в Phase 5 (housekeeping cron — Phase 11 / Phase 8 follow-up);
partial-index handles efficiency.

---

#### Scenario 6.11.4 — Per-issuer isolation: GitHub limit exhausted, GitLab unaffected

**ID:** 3.5-6.11.4
**Mapping:** integration `TestRateLimit_PerIssuerIsolation`.

**Given** GitHub bucket exhausted.

**When** Exchange с GitLab issuer.

**Then** Separate bucket row `(issuer=gitlab.com, …)`; exchange succeeds.

---

#### Scenario 6.11.5 — JTI replay across minutes — protected

**ID:** 3.5-6.11.5
**Mapping:** integration `TestJTIReplay_AcrossMinutes`.

**Given** Successful exchange at `10:34:30` — `jti=X` записан в `federation_jti_replay` с
`expires_at = now() + external_token.exp_remaining` (e.g. 10min).

**When** Replay at `10:40:00` (still within external JWT validity).

**Then** Partial UNIQUE catches → 401 (Scenario 6.7.7).

---

#### Scenario 6.11.6 — JTI replay cleanup

**ID:** 3.5-6.11.6
**Mapping:** integration `TestJTIReplay_AutoCleanup`.

**Given** jti row inserted at `T0` с `expires_at = T0 + 10min`.

**When** At `T0+11min`, vacuum cron-job (Phase 11 follow-up) runs `DELETE FROM
federation_jti_replay WHERE expires_at < now()`.

**Then** Row deleted; subsequent INSERT с same jti — succeeds (token уже сам expired по `exp`,
повторный exchange всё равно fail на `exp` check Scenario 6.7.9; jti cleanup — для table size).

**And** In Phase 5 — cleanup cron не реализован, но **миграция `0015` создаёт partial index**:
```sql
CREATE INDEX federation_jti_replay_expires_idx ON federation_jti_replay (expires_at)
  WHERE expires_at < now();
```
Это позволяет efficient cron в Phase 11.

---

### 6.12 Conditions at exchange time

#### Scenario 6.12.1 — source_ip in CIDR allowed → success

**ID:** 3.5-6.12.1
**Mapping:** integration `TestConditions_SourceIPAllowed`.

**Given** Trust policy с `conditions.source_ip_cidrs = ["10.0.0.0/8","192.168.0.0/16"]`.

**When** Exchange call с `X-Forwarded-For: 10.42.13.7` (matches 10.0.0.0/8).

**Then** Success.

---

#### Scenario 6.12.2 — Multiple CIDRs: matches any one → success

**ID:** 3.5-6.12.2
**Mapping:** integration `TestConditions_MultipleCIDRs`.

**Given** Same as 6.12.1.

**When** Exchange call с `X-Forwarded-For: 192.168.1.42` (matches second CIDR).

**Then** Success.

---

#### Scenario 6.12.3 — business_hours within range → success

**ID:** 3.5-6.12.3
**Mapping:** integration `TestConditions_BusinessHoursInRange`.

**Given** Trust policy с `conditions.business_hours = {"timezone":"Europe/Berlin","start_h":9,
"end_h":18}`.

**When** Exchange at `2026-05-19T13:00:00Z` (15:00 Berlin, в range [9,18)).

**Then** Success.

---

#### Scenario 6.12.4 — business_hours boundary: start_h inclusive, end_h exclusive

**ID:** 3.5-6.12.4
**Mapping:** integration `TestConditions_BusinessHoursBoundary`.

**When** Exchange at exactly 09:00 Berlin → success (start_h inclusive).
**And** Exchange at exactly 18:00 Berlin → deny (end_h exclusive).

---

#### Scenario 6.12.5 — max_token_ttl_override reduces issued TTL

**ID:** 3.5-6.12.5
**Mapping:** integration `TestConditions_MaxTokenTTLOverride`.

**Given** Trust policy с `max_token_ttl = 15min` и
`conditions.max_token_ttl_override = "5m"`.

**When** Exchange.

**Then** Kachō JWT `exp = now() + 300s`; response `expires_in: 300`.

**And** Override **не может** увеличить — если override > max_token_ttl, эффективный TTL =
min(15min, override, max_token_ttl) = max_token_ttl (sanity).

---

#### Scenario 6.12.6 — Effective TTL = min(hard-cap-15min, policy.max_token_ttl, override)

**ID:** 3.5-6.12.6
**Mapping:** integration `TestConditions_EffectiveTTL`.

**Parameterized cases:**

| policy.max_token_ttl | override | hard cap | Expected exp |
|---|---|---|---|
| 15m | (none) | 15m | now + 900s |
| 10m | (none) | 15m | now + 600s |
| 15m | 5m | 15m | now + 300s |
| 15m | 20m | 15m | now + 900s (override ignored — > hard cap) |
| 10m | 30m | 15m | now + 600s (override > policy → ignored) |
| 5m | 1m | 15m | now + 60s |

---

#### Scenario 6.12.7 — No conditions block (empty `conditions` JSONB) → no condition check

**ID:** 3.5-6.12.7
**Mapping:** integration `TestConditions_EmptyAllowsAll`.

**Given** Trust policy с `conditions = {}`.

**When** Exchange.

**Then** Success (no source_ip / no business_hours checks).

---

### 6.13 Integration: end-to-end smoke

#### Scenario 6.13.1 — Full Class A flow: issue key → fetch JWT from Hydra → call kacho-vpc

**ID:** 3.5-6.13.1
**Mapping:** newman `cases/e2e_class_a.py` (full stack against real Hydra in `kacho-deploy` dev
stack).

**Given** Dev стенд (`make dev-up` в `kacho-deploy`) запущен — kacho-iam + kacho-vpc + kacho-api-
gateway + Hydra (real instance, не httptest).

**When**:
1. Admin issue SA-key (Scenario 6.1.1 path).
2. CI runner получает `client_id` + `client_secret` (one-shot из Operation.response).
3. CI runner вызывает Hydra `POST /oauth2/token -u client_id:client_secret -d
   grant_type=client_credentials -d audience=https://api.kacho.cloud` → получает Kachō JWT.
4. CI runner вызывает `GET /vpc/v1/networks` через `api.kacho.cloud` с `Authorization: Bearer
   <jwt>`.

**Then** API call HTTP 200; list networks для project, где SA имеет permissions.

---

#### Scenario 6.13.2 — Full Class B flow: mock GitHub OIDC → exchange → call kacho-vpc

**ID:** 3.5-6.13.2
**Mapping:** newman `cases/e2e_class_b.py` (mock GitHub issuer running as sidecar in dev stack).

**Given** Dev стенд + mock GitHub OIDC issuer (`docker-compose` адобавление в `kacho-deploy/dev-
compose.yml` — small Go binary `mock-github-oidc` бинарь housed in `kacho-iam/cmd/`).

**When**:
1. Admin create trust policy (Scenario 6.5.1).
2. CI runner получает external GH-style JWT от mock issuer.
3. CI runner вызывает `POST https://api.kacho.cloud/iam/v1/federations:exchange` (Scenario
   6.6.1).
4. CI runner получает Kachō JWT.
5. CI runner вызывает `GET /vpc/v1/networks` (тот же flow).

**Then** Все steps HTTP 200.

---

## 7. Definition of Done (Phase 5 closure)

### Functional

- [ ] Все 50+ GWT в §6 имеют integration test + (где помечено) newman case, все зелёные.
- [ ] `SAKeyService.{Create,Delete,List,Rotate,Get}` зарегистрированы на public mux 9090
  `kacho-api-gateway`.
- [ ] `FederationExchangeService.Exchange` зарегистрирован на public mux 9090, accepts
  `application/x-www-form-urlencoded` (RFC 8693 mandate) + JSON (для grpc-gateway).
- [ ] `InternalTrustPolicyService.{Create,Update,Delete,Get,List}` зарегистрированы на
  **internal** mux 9091 (запрет #6); regression test в `kacho-api-gateway` доказывает что
  на public mux НЕ зарегистрирован.
- [ ] UI pages `/iam/serviceAccounts/:sva/keys` + `/iam/federations` функциональны (Playwright
  e2e green); docs snippets для 8 providers — copy-paste ready (real CI snippets, не
  pseudo-code).
- [ ] e2e smoke (Scenarios 6.13.1 + 6.13.2) проходит в dev-стенде `make e2e-test`.

### Tests / CI

- [ ] **Integration tests** (testcontainers Postgres + httptest mock Hydra + httptest mocks для
  8 issuers) — все зелёные; coverage ≥ 80% line / ≥ 70% branch для пакетов `internal/apps/
  kacho/api/sa_key/*`, `internal/apps/kacho/api/federation/*`, `internal/repo/*` (rate_limit,
  jti_replay, sa_key, federation_trust_policy).
- [ ] **Newman cases** в `kacho-iam/tests/newman/cases/*.py`:
  - `sa_key_create_happy.py`, `sa_key_create_dup.py`, `sa_key_create_denied.py`,
    `sa_key_delete_happy.py`, `sa_key_delete_notfound.py`, `sa_key_list.py`,
    `sa_key_rotate.py`.
  - `trust_policy_github.py`, `trust_policy_wildcard.py`, `trust_policy_expires_too_far.py`,
    `trust_policy_update.py`, `trust_policy_update_immutable.py`, `trust_policy_delete.py`.
  - `exchange_github.py`, `exchange_aws_irsa.py`, `exchange_gcp_wif.py`, `exchange_gitlab.py`,
    `exchange_bitbucket.py`, `exchange_circleci.py`, `exchange_buildkite.py`, `exchange_azure.py`.
  - `exchange_subj_mismatch.py`, `exchange_policy_expired.py`, `exchange_claims_mismatch.py`,
    `exchange_source_ip_deny.py`, `exchange_tampered.py`, `exchange_jti_replay.py`,
    `exchange_wrong_aud.py`, `exchange_business_hours.py`, `exchange_policy_disabled.py`,
    `exchange_rate_limit.py`.
  - `e2e_class_a.py`, `e2e_class_b.py`.
  Все запускаются `make newman` зелёные.
- [ ] **Concurrent integration tests** — Scenario 6.4.4 (concurrent rotate via partial UNIQUE)
  и Scenario 6.8.3 (singleflight collapses) — N goroutines, проверяют что **exactly one**
  succeeds / **exactly one** HTTP fetch.
- [ ] **buf lint** + **buf breaking** зелёные на `kacho-proto`.
- [ ] **`make gen`** в `kacho-proto` — diff пустой (regenerated stubs committed).
- [ ] **`go vet` + golangci-lint** зелёные.
- [ ] **regression test**: `kacho-api-gateway` mux_test проверяет — `InternalTrustPolicyService`
  НЕ на public mux.

### Operational

- [ ] **Migration `0015_kac127_federation_rate_limits.sql`** applies cleanly: `make migrate-up`
  + `make migrate-down` + `make migrate-up` — no errors.
- [ ] **Bootstrap behaviour**: при первом запуске kacho-iam — нет issues (нет policies, нет
  keys; tables пустые — sanity test).
- [ ] **Hydra integration**: dev стенд имеет real Hydra; tests на real Hydra pass (через `make
  e2e-test`).
- [ ] **Metrics** exposed на `/metrics`:
  - `iam_sa_key_create_total{outcome}`, `iam_sa_key_delete_total`, `iam_sa_key_rotate_total`.
  - `iam_federation_exchange_total{outcome,issuer,reason}`.
  - `iam_jwks_cache_hits_total{issuer}`, `iam_jwks_cache_misses_total{issuer}`,
    `iam_jwks_cache_kid_miss_refresh_total{issuer}`, `iam_jwks_stale_fallback_total{issuer}`,
    `iam_jwks_cache_evictions_total`.
  - `iam_federation_rate_limit_exceeded_total{issuer}`.
  - `iam_federation_jti_replay_blocked_total`.
- [ ] **OTLP traces** на каждый exchange call (spans: parse_jwt, jwks_lookup, jwks_fetch,
  rate_limit_check, jti_check, policy_lookup, conditions_eval, kacho_jwt_sign,
  audit_emit).

### Security / Compliance

- [ ] **Audit emits** verified by integration tests — Scenarios 6.10.1-6.10.5.
- [ ] **CAEP emits** verified — Scenario 6.10.3, 6.10.4, 6.10.5.
- [ ] **Запрет #6 enforcement test** — Internal vs public mux separation.
- [ ] **Запрет #10 enforcement** — DB-уровень для всех refs / invariants (jti_replay partial
  UNIQUE, rate_limit CAS, sa_key partial UNIQUE WHERE `replaces_id IS NULL`).
- [ ] **JWT signing key** — managed по same rotation rules как Hydra (90d cycle через
  `oidc_jwks_keys` table — Phase 1 / Phase 11).
- [ ] **No secrets logged** — review handler/service code: `client_secret_one_shot` и
  `subject_token` payload не появляются в logs; OTLP spans помечены `sensitive=true`.

### Documentation

- [ ] **Acceptance doc** (этот файл) — APPROVED by `acceptance-reviewer`.
- [ ] **Vault updates** (см. §5.6).
- [ ] **Docs snippets** для 8 providers — каждый имеет:
  - YAML/HCL/JSON CI config example.
  - Step-by-step "as a customer engineer".
  - Common errors troubleshooting.
- [ ] **README** в `kacho-iam` — раздел "Workload Identity Federation" + ссылка на этот
  acceptance doc.

### Code quality (no tech debt)

- [ ] **No TODO / TBD / "follow-up" comments** в коде (per плану — production edition); если
  нужен follow-up — отдельный YT ticket (e.g. KAC-XXX "JWT signing rotation cron — Phase 11
  precursor").
- [ ] **No "phase 5 / phase 8 / phase 11 — TBD"** в кодовых комментариях — design стабилен; код
  завершён в рамках Phase 5 scope.
- [ ] **Self-validating domain newtypes** — `IssuerURL.Validate()`, `SubjectPattern.Validate()`,
  `MaxTokenTTL.Validate()`, `Audience.Validate()` — `domain` package, без deps на pgx /
  grpc-stubs / clients.
- [ ] **CQRS reader/writer split** — все repos (sa_key, federation_trust_policy, jti_replay,
  exchange_rate_limit) имеют отдельные `Reader` и `Writer` interfaces; tests против obeject /
  fakes без implicit shared state.
- [ ] **Slice-per-RPC use-case layout** (per skill `godzila`) — каждый RPC = свой `<RPC>UseCase`
  struct + `Execute(ctx, in) (out, err)` method; никаких fat-Service god-objects.

---

## 8. Cross-repo PR-chain (merge order — топологическая сортировка)

> Источник истины — workspace `CLAUDE.md` §«Кросс-репо зависимости и порядок выполнения».
> Pre-merge: каждый downstream PR пиннит upstream через `ref:` в `.github/workflows/ci.yaml`;
> после merge upstream — `ref:` убирается / возвращается на `main`.

```
1. PRO-Robotech/kacho-proto#NN  ([KAC-127-phase5-proto] iam: SAKeyService + FederationExchangeService + InternalTrustPolicyService)
        │
        ├ updates: gen/permission_catalog.json (new iam.* permissions)
        │
        ▼
2. PRO-Robotech/kacho-corelib#NN ([KAC-127-phase5-corelib] hydra_admin extension + oidc/jwks_cache)
        │ Blocked by kacho-proto#NN
        │
        ▼
3. PRO-Robotech/kacho-iam#NN     ([KAC-127-phase5-impl] SA-keys + Federation Exchange + Trust Policy CRUD + migration 0015)
        │ Blocked by kacho-proto#NN, kacho-corelib#NN
        │
        │ contains: 30+ integration tests, 25+ newman cases (running in CI mock issuers)
        │
        ▼
4. PRO-Robotech/kacho-api-gateway#NN ([KAC-127-phase5-mux] register iam services on public/internal mux)
        │ Blocked by kacho-iam#NN
        │
        ▼
5. PRO-Robotech/kacho-deploy#NN  ([KAC-127-phase5-deploy] dev-compose mock-github-oidc sidecar; e2e tests)
        │ Blocked by kacho-iam#NN
        │
        ▼
6. PRO-Robotech/kacho-ui#NN      ([KAC-127-phase5-ui] SA-keys + Federation Trust Policy pages + 8 docs snippets)
        │ Blocked by kacho-api-gateway#NN, kacho-deploy#NN
        │
        ▼
7. PRO-Robotech/kacho-workspace#NN ([KAC-127-phase5-docs] this acceptance doc + vault trail)
        │ Blocked by все остальные (последним мёрджится, чтобы зафиксировать финальное состояние)
```

Branches: `KAC-127` в каждом репо (epic branch — допустимо single across phases, см. workspace
`CLAUDE.md`; subtask`KAC-XXX` если subdivides epic).

YT subtasks per Task 5.1-5.8 в плане — каждый имеет state `To do → In Progress → Test → Done`
+ ссылку на PR(s) в комментарии.

---

## 9. Out of scope (Phase 5)

> **Production edition** — это **explicit deferred work с YT ссылками**, НЕ "TODO". Каждый
> пункт ниже — отдельный phase эпика KAC-127.

| # | Item | Owner phase | Rationale |
|---|---|---|---|
| 1 | **Class C — SPIFFE/SPIRE in-cluster + Cilium mesh** | Phase 10 (KAC-127-phase10) | Внутри-кластерная mTLS-identity не нужна для **external** CI/CD; SPIRE Server+Agent+Cilium policies — отдельная инфра-работа |
| 2 | **CAEP webhook delivery** | Phase 8 (KAC-127-phase8) | Phase 5 пишет в `caep_outbox`; drainer + retry + SET signing — Phase 8 |
| 3 | **Audit Kafka pipeline + ClickHouse + S3+Glacier + HSM-signed batches** | Phase 9 (KAC-127-phase9) | Phase 5 пишет в `audit_outbox`; broker + cold storage + Merkle-chain — Phase 9 |
| 4 | **Multi-region active-active for `:exchange`** | Phase 11 (KAC-127-phase11) | Single-region достаточен на dev/staging; Anycast + GeoDNS + cross-region jti_replay sync — Phase 11 |
| 5 | **JWKS rotation alerts** (≤14d to expiry) | Phase 11 (Phase 5 emits row в `oidc_jwks_keys`, alerts через Alertmanager — Phase 11) | Phase 5 — storage only; alerting rules — Phase 11 |
| 6 | **Hydra `last_used_at` async update** (introspection webhook) | Phase 8 (CAEP receiver picks up) | Phase 5 — `last_used_at` NULL stub в `service_account_oauth_clients`; auto-update Phase 8 |
| 7 | **JTI replay cleanup cron-job** | Phase 11 / Phase 8 | Partial index готов в Phase 5 migration `0015`; cron-job — Phase 11 maintenance |
| 8 | **Hydra orphan client detection** (cron сравнивает Hydra `/admin/clients` vs `service_account_oauth_clients`) | Phase 11 maintenance | Phase 5 — alert на orphan при single Create call (Scenario 6.1.3); bulk-scan cron — Phase 11 |
| 9 | **Idempotency-Key header** на CreateSAKey / CreateTrustPolicy | Phase 7 (общий idempotency layer для всех IAM mutations) | Phase 5 — duplicates ловятся через UNIQUE; explicit idempotency через header — Phase 7 |
| 10 | **OIDC issuer allowlist** (configurable per-Organization) | Phase 6 (Organization tier) | Phase 5 — любой issuer разрешён (subject_pattern strict + admin gate enough); per-Org allowlist — после Phase 6 |
| 11 | **Federation Exchange via gRPC native** (`exchange.proto` RPC через gRPC unary) | Phase 5 уже делает — синхронный gRPC, REST через grpc-gateway | clarified inline |
| 12 | **`subject_token_type` другие чем JWT** (e.g. `access_token`, `saml2`) | Phase 6 (SAML bridge) | Phase 5 — только JWT subject_token; SAML — после Phase 6 |
| 13 | **`requested_token_type` другие чем JWT** (e.g. SAML, opaque) | wontfix (out of scope KAC-127) | Kachō всегда выпускает JWT — design constraint |
| 14 | **Refresh-token rotation для Class A** | Phase 8 (KAC-127-phase8 CAEP передаёт revoke; refresh-token rotation встроена в Hydra) | clarified — Hydra сам это умеет; интегрируется автоматически |

---

## 10. Open Questions (resolved inline)

### Q1 — Должен ли Exchange валидировать `client_id` в DPoP header (RFC 9449)?

**Resolved**: НЕТ для Phase 5. DPoP — для **issuer-bound tokens** на UI / mobile (Phase 2); CI/CD
workflows традиционно не используют DPoP (нет persistent client key). Phase 5 Exchange —
открытый endpoint без DPoP requirement; security достигается через subject_token signature +
trust policy.

### Q2 — JWT signing key для выпускаемых Kachō JWT — общий с Hydra или отдельный?

**Resolved**: **Общий с Hydra**. kacho-iam использует Hydra-admin endpoint `POST /admin/oauth2/auth/
requests/login/accept` + `POST /admin/oauth2/auth/requests/consent/accept` для issue JWT через
существующий Hydra signing key. Это позволяет unified JWKS endpoint (`https://hydra.kacho.cloud/
.well-known/jwks.json`), который api-gateway уже валидирует. Никакого отдельного kacho-iam
signing key.

Alternative considered: kacho-iam local JWKS + отдельный signing. Rejected: дублирует rotation
overhead + два JWKS endpoint'а для клиентов.

### Q3 — Что делать если external JWT не имеет `jti` claim?

**Resolved**: **Reject** с `InvalidArgument` "subject_token missing required claim 'jti'".
Industry standard (GitHub Actions, AWS IRSA, GCP WIF, GitLab CI, Azure WI — все эмитят `jti`).
Если будущий provider не имеет `jti` — он не подходит для federation в Kachō по design.

### Q4 — Может ли `subject_pattern` содержать ANCHOR characters (`^` / `$`)?

**Resolved**: НЕТ. `subject_pattern` — **literal exact-match** строка (никаких anchors, никаких
regex). CHECK constraint Phase 1 запрещает `*`, `?`, `[`, `]`, `{`, `}`, `\`; добавить `^` и
`$` в forbidden — расширение constraint в новой миграции `0015` (через `ALTER` — это safe DDL,
не breaks existing rows т.к. exact-match не использует anchors).

### Q5 — Trust policy на один issuer для разных SA — допустимо?

**Resolved**: ДА. Partial UNIQUE Phase 1 — на `(issuer, subject_pattern)` (a не `(issuer)`); т.е.
**один и тот же issuer** может иметь N policies для разных subject_patterns / разных SA. Это
production use-case: monorepo с N micro-services, каждый со своим SA и subject_pattern
`repo:my-org/monorepo:ref:refs/heads/feature/svc-X`.

### Q6 — Можно ли disable policy через `enabled=false` вместо delete?

**Resolved**: ДА. `UpdateTrustPolicy(enabled=false)` — softer alternative к Delete (audit trail
сохраняется; легко re-enable). DeleteTrustPolicy — hard removal (audit row остаётся в
`audit_outbox`).

### Q7 — `audience` в request — игнорируется или валидируется?

**Resolved**: ВАЛИДИРУЕТСЯ. Request параметр `audience` (RFC 8693) обязан совпадать с
`policy.audience`; mismatch → `InvalidArgument` "audience parameter does not match policy". В
большинстве случаев request `audience = "https://api.kacho.cloud"` (== policy.audience), но
явная проверка — safety.

### Q8 — Что если несколько trust policies matches один subject_token?

**Resolved**: Partial UNIQUE Phase 1 гарантирует `(issuer, subject_pattern)` уникальность; для
ОДНОГО external JWT (один `iss`+`sub`) matches **максимум ОДНА** policy. Если matches >1 (что
было бы DB bug) — service-layer берёт первую по `created_at ASC` + emit alert
`iam.federation.policy.duplicate_match` (это указывает на нарушенный invariant).

### Q9 — Поддерживаем ли мы `actor_token` (RFC 8693 §2.1) для on-behalf-of сценариев?

**Resolved**: НЕТ для Phase 5 (out of scope #12). Может быть Phase 6 (SAML) или later. Если
request содержит `actor_token` — игнорируется (no error, no use), документация явно говорит
"actor_token field is not currently supported".

### Q10 — Что если external issuer JWKS rotation удалит kid пока есть active jti_replay rows?

**Resolved**: Не проблема. `federation_jti_replay` хранит `(jti, issuer)`, не kid. JWKS rotation
обновляет cache (Scenario 6.8.2 kid-miss-refresh); старые jti_replay rows остаются — но они
уже **expired** (external JWT exp прошло), partial-index handles cleanup.

### Q11 — Поддерживаем ли `code` grant в Hydra для SA-keys?

**Resolved**: НЕТ. Class A — только `client_credentials` (M2M). `authorization_code` — для user
flows (Phase 2). SA-key, который пытается `code` flow → Hydra сам reject (grant_types restrict
per-client; kacho-iam задаёт `grant_types=["client_credentials"]` при создании).

### Q12 — Должны ли admin SA-keys (для cluster-admin SAs) иметь дополнительные restrictions?

**Resolved**: Нет специальной обработки в Phase 5 — admin SAs управляются через OPA guardrails
(design §4 OPA Rego — "service accounts may not grant roles to users"); SA-key issuance для
cluster-admin SAs gated через `kacho-system.admin` permission (system role, не tenant). Это
operational concern, не Phase 5 functional.

### Q13 — Логируем ли мы sensitive payload (subject_token decoded claims) в audit?

**Resolved**: Selective. Audit payload содержит `external_iss`, `external_sub`, `external_jti`,
`external_aud`. **НЕ** содержит полный decoded JWT (privacy concern — некоторые claims могут
быть sensitive: `actor=alice@my-org.com` для GHA — PII). Полный JWT — только в trace span
(short retention, debug only); audit row — sanitized.

### Q14 — Что если Hydra недоступен при SA-key Create?

**Resolved**: `Unavailable` "hydra-admin temporarily unavailable; retry later". Идеальный
паттерн — Operation мог бы retry асинхронно (worker-pattern), но Phase 5 не делает retry
loops в worker'е — Operation падает сразу с error. Phase 8 follow-up: scheduled worker retries.

### Q15 — Какие default'ы для `max_token_ttl` при CreateTrustPolicy без явного значения?

**Resolved**: `max_token_ttl = 15min` (hard cap) если не указан. Lower bound: `1 second`
(no point in 0 TTL); CHECK `max_token_ttl >= INTERVAL '1 second'` в Phase 1 миграции уже
есть.

---

## 11. Traceability matrix (GWT → integration test → newman case)

| GWT ID | Integration test | Newman case |
|---|---|---|
| 3.5-6.1.1 | `TestSAKeyCreate_HappyPath` | `sa_key_create_happy.py` |
| 3.5-6.1.2 | `TestSAKeyCreate_DuplicateActive` | `sa_key_create_dup.py` |
| 3.5-6.1.3 | `TestSAKeyCreate_HydraConflictIdempotent` | — (rare path; integration only) |
| 3.5-6.1.4 | `TestSAKeyCreate_PermissionDenied` | `sa_key_create_denied.py` |
| 3.5-6.1.5 | `TestSAKeyCreate_UserRateLimit` | — (rate-limit hard to assert via newman) |
| 3.5-6.2.1 | `TestSAKeyDelete_HappyPath` | `sa_key_delete_happy.py` |
| 3.5-6.2.2 | `TestSAKeyDelete_ExistingJWTsRejected` | — (depends Hydra introspection cache; e2e) |
| 3.5-6.2.3 | `TestSAKeyDelete_NotFound` | `sa_key_delete_notfound.py` |
| 3.5-6.2.4 | `TestSAKeyDelete_PreviouslyRotated` | — (integration only) |
| 3.5-6.3.1 | `TestSAKeyList_HappyPath_NoSecrets` | `sa_key_list.py` |
| 3.5-6.3.2 | `TestSAKeyList_Pagination` | — (covered by happy-path with multiple keys) |
| 3.5-6.4.1 | `TestSAKeyRotate_HappyPath` | `sa_key_rotate.py` |
| 3.5-6.4.2 | `TestSAKeyRotate_ExplicitRevokeOld` | — (integration only) |
| 3.5-6.4.3 | `TestSAKeyRotate_NoActiveKey` | — (integration only) |
| 3.5-6.4.4 | `TestSAKeyRotate_ConcurrentSafeBy_partialUnique` | — (concurrency; integration only) |
| 3.5-6.5.1 | `TestTrustPolicyCreate_GitHubHappy` | `trust_policy_github.py` |
| 3.5-6.5.2 | `TestTrustPolicyCreate_Wildcard` | `trust_policy_wildcard.py` |
| 3.5-6.5.3 | `TestTrustPolicyCreate_ExpiresTooFar` | `trust_policy_expires_too_far.py` |
| 3.5-6.5.4 | `TestTrustPolicyCreate_BadIssuer` | — (integration; mock DNS) |
| 3.5-6.5.5 | `TestTrustPolicyCreate_HTTPIssuer` | — (integration) |
| 3.5-6.5.6 | `TestTrustPolicyUpdate_MutableFields` | `trust_policy_update.py` |
| 3.5-6.5.7 | `TestTrustPolicyUpdate_Immutable` | `trust_policy_update_immutable.py` |
| 3.5-6.5.8 | `TestTrustPolicyUpdate_ExtendBeyondOriginalLimit` | — (integration) |
| 3.5-6.5.9 | `TestTrustPolicyDelete_HappyPath` | `trust_policy_delete.py` |
| 3.5-6.5.10 | `TestTrustPolicyList_Pagination` | — (covered by happy-path with multiple policies) |
| 3.5-6.6.1 | `TestExchange_GitHubActions_Happy` | `exchange_github.py` |
| 3.5-6.6.2 | `TestExchange_AWSIRSA_Happy` | `exchange_aws_irsa.py` |
| 3.5-6.6.3 | `TestExchange_GCPWIF_Happy` | `exchange_gcp_wif.py` |
| 3.5-6.6.4 | `TestExchange_GitLabCI_Happy` | `exchange_gitlab.py` |
| 3.5-6.6.5 | `TestExchange_Bitbucket_Happy` | `exchange_bitbucket.py` |
| 3.5-6.6.6 | `TestExchange_CircleCI_Happy` | `exchange_circleci.py` |
| 3.5-6.6.7 | `TestExchange_Buildkite_Happy` | `exchange_buildkite.py` |
| 3.5-6.6.8 | `TestExchange_AzureWI_Happy` | `exchange_azure.py` |
| 3.5-6.7.1 | `TestExchange_SubjectPatternMismatch` | `exchange_subj_mismatch.py` |
| 3.5-6.7.2 | `TestExchange_ExpiredPolicy` | `exchange_policy_expired.py` |
| 3.5-6.7.3 | `TestExchange_ClaimsFilterMismatch` | `exchange_claims_mismatch.py` |
| 3.5-6.7.4 | `TestExchange_MissingClaim` | — (subset of 6.7.3) |
| 3.5-6.7.5 | `TestExchange_SourceIPDeny` | `exchange_source_ip_deny.py` |
| 3.5-6.7.6 | `TestExchange_TamperedSignature` | `exchange_tampered.py` |
| 3.5-6.7.7 | `TestExchange_JtiReplay` | `exchange_jti_replay.py` |
| 3.5-6.7.8 | `TestExchange_FutureNbf` | — (integration; clock-skew) |
| 3.5-6.7.9 | `TestExchange_ExternalExpired` | — (integration) |
| 3.5-6.7.10 | `TestExchange_WrongAudience` | `exchange_wrong_aud.py` |
| 3.5-6.7.11 | `TestExchange_BusinessHoursDeny` | `exchange_business_hours.py` |
| 3.5-6.7.12 | `TestExchange_PolicyDisabled` | `exchange_policy_disabled.py` |
| 3.5-6.7.13 | `TestExchange_JWKSUnreachable_Degraded` | — (integration; httptest mock) |
| 3.5-6.7.14 | `TestExchange_JWKSUnreachable_NoCache` | — (integration) |
| 3.5-6.8.1 | `TestJWKSCache_TTL` | — (corelib unit) |
| 3.5-6.8.2 | `TestJWKSCache_KidMissRefresh` | — (corelib unit) |
| 3.5-6.8.3 | `TestJWKSCache_Singleflight` | — (corelib concurrency unit) |
| 3.5-6.8.4 | `TestJWKSCache_PerIssuerIsolation` | — (corelib unit) |
| 3.5-6.8.5 | `TestJWKSCache_LRUEviction` | — (corelib unit) |
| 3.5-6.9.1 | `TestSubjectPattern_WildcardRejected` | — (domain unit) |
| 3.5-6.9.2 | `TestSubjectPattern_LiteralExact` | — (domain unit) |
| 3.5-6.9.3 | `TestSubjectPattern_PathSeparators` | — (domain unit) |
| 3.5-6.9.4 | `TestSubjectPattern_Empty` | — (domain unit) |
| 3.5-6.9.5 | `TestSubjectPattern_TooLong` | — (domain unit) |
| 3.5-6.9.6 | `TestSubjectPattern_SpecialChars` | — (domain unit) |
| 3.5-6.10.1 | `TestExchange_AuditEmit_Success` | — (audit-table assertion; integration) |
| 3.5-6.10.2 | `TestExchange_AuditEmit_Denied` | — (integration) |
| 3.5-6.10.3 | `TestSAKeyDelete_CAEPEmit` | — (caep_outbox assertion; integration) |
| 3.5-6.10.4 | `TestTrustPolicyExpiry_AutoDisable` | — (integration; clock-skew + caep) |
| 3.5-6.10.5 | `TestTrustPolicyCreate_Emits` | — (audit + caep assertion) |
| 3.5-6.11.1 | `TestRateLimit_WithinLimit` | — (integration; loop 99 calls) |
| 3.5-6.11.2 | `TestRateLimit_Exceeded` | `exchange_rate_limit.py` |
| 3.5-6.11.3 | `TestRateLimit_BucketRollover` | — (integration; clock skew) |
| 3.5-6.11.4 | `TestRateLimit_PerIssuerIsolation` | — (integration) |
| 3.5-6.11.5 | `TestJTIReplay_AcrossMinutes` | — (integration) |
| 3.5-6.11.6 | `TestJTIReplay_AutoCleanup` | — (integration; clock skew + manual DELETE call) |
| 3.5-6.12.1 | `TestConditions_SourceIPAllowed` | — (integration) |
| 3.5-6.12.2 | `TestConditions_MultipleCIDRs` | — (integration) |
| 3.5-6.12.3 | `TestConditions_BusinessHoursInRange` | — (integration; clock skew) |
| 3.5-6.12.4 | `TestConditions_BusinessHoursBoundary` | — (integration) |
| 3.5-6.12.5 | `TestConditions_MaxTokenTTLOverride` | — (integration) |
| 3.5-6.12.6 | `TestConditions_EffectiveTTL` (parameterized) | — (integration) |
| 3.5-6.12.7 | `TestConditions_EmptyAllowsAll` | — (integration) |
| 3.5-6.13.1 | — (e2e against real Hydra) | `e2e_class_a.py` |
| 3.5-6.13.2 | — (e2e with mock-github-oidc sidecar) | `e2e_class_b.py` |

**Total**: 73 GWT scenarios.

---

## 12. Approval signature

```
acceptance-reviewer status: ⬜ AWAITING REVIEW
reviewer-comment date:      _____________
reviewer-comment hash:      _____________
acceptance-author response: _____________
finalized:                  ⬜ APPROVED  ⬜ CHANGES REQUESTED
```

При APPROVED — статус документа выше меняется с DRAFT на APPROVED, далее запускается работа по
§5 декомпозиции (PR-chain), Tasks 5.2-5.8 плана.
