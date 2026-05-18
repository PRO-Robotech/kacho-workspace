# Sub-phase 2.0 — IAM E2: Zitadel OIDC deploy + auth-interceptor + SA key-flow — Acceptance

> **Status**: DRAFT v1 — awaiting `acceptance-reviewer` APPROVED
> **Date**: 2026-05-17
> **YouTrack**: [KAC-107](https://prorobotech.youtrack.cloud/issue/KAC-107) — child of epic [KAC-104](https://prorobotech.youtrack.cloud/issue/KAC-104)
> **Parent overview**: [[sub-phase-2.0-iam-overview-acceptance]]
> **Blocked by**: [KAC-105 (E0)](https://prorobotech.youtrack.cloud/issue/KAC-105) merged — нужны `kacho_iam.users` mirror + `InternalIamService.LookupSubject`; helm-stubs для Zitadel/OpenFGA уже добавлены в `kacho-deploy/helm/umbrella/values.dev.yaml` (E0)
> **Blocks**: [KAC-108 (E3)](https://prorobotech.youtrack.cloud/issue/KAC-108) — OpenFGA `Check`-interceptor работает только если `subject` определён auth-interceptor'ом
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer`

---

## 0. Преамбула

E2 — третий код-производительный кусок эпика IAM (после E0/E1). Цель: подключить
**внешний OIDC-provider Zitadel** как источник identity, заменить заглушку
`auth_noop`-interceptor в `kacho-api-gateway` на реальный auth-interceptor
с JWT-валидацией через JWKS, и реализовать **ServiceAccount key-flow**
(приватный ключ → подписанный JWT-assertion → access_token Zitadel).

После E2 каждый PUBLIC RPC через api-gateway будет:
1. Парсить `Authorization: Bearer <JWT>` (или cookie-session для UI).
2. Валидировать подпись JWT через Zitadel JWKS (cached 30min).
3. Резолвить `Subject` в `kacho_iam.users` / `kacho_iam.service_accounts` через
   gRPC-direct `kacho-iam.InternalIamService.LookupSubject` (cached 30s).
4. Прокидывать `Principal{Type, ID, DisplayName}` в gRPC ctx через corelib
   helpers `principal.WithPrincipal(ctx, p)` / `principal.FromContext(ctx)`.
5. Backend-сервисы (vpc/compute/lb/iam) при создании `Operation` через
   `corelib.operations.CreateWithPrincipal(ctx, ...)` будут записывать реальный
   principal в `operations.principal_*` (DoD #4 — финально закрывается в E4 для UI,
   но E2 уже делает principal **корректным** на backend уровне).

**E2 НЕ включает** (явные out-of-scope, см. §9):
- OpenFGA `Check`-interceptor (E3) — `Authz`-interceptor временно no-op pass-through.
- DoD #5 «реактивность» — частично: NOTIFY-listener в api-gateway добавляется здесь,
  но invalidate-источник (publisher в kacho-iam) — E3 (AccessBinding-write).
- Signup-UI / IAM UI блок (E4).
- MFA / WebAuthn / external federation (Phase 2.1).
- Прод-grade TLS для Zitadel (dev — self-signed; prod — отдельная фаза 3).

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** — кодирование только после `acceptance-reviewer` APPROVED | данный документ — gate; статус выше `DRAFT v1` |
| **Запрет #2** — НЕ упоминать "yandex" | в коде и docs нет; стилистически YC-style error-text (`"missing Bearer token"`, `"token expired"`, `"subject not found"`) |
| **Запрет #6** — Internal vs Public | `InternalIamService.LookupSubject` — **gRPC-direct only**, НЕ через restmux (loop-prevention, см. §3.4 ниже); `InternalUserService.UpsertFromIdentity` остаётся под `iamInternalAddr` REST mux для admin/тулинга |
| **Запрет #8** — DB-per-service | Zitadel хранит state в БД `zitadel` (отдельный pg-zitadel экземпляр); `kacho_iam` не знает ничего о Zitadel-internal таблицах |
| **Запрет #10** — within-service refs DB-level | E2 добавляет таблицу `kacho_iam.sa_keys` с FK на `service_accounts(id) ON DELETE CASCADE`; UNIQUE constraint на `(service_account_id, key_id)`; `revoked_at` partial-uniqueness для активных ключей |
| **Запрет #11** — тесты в том же PR | каждый PR (kacho-iam OIDC client + sa_keys; kacho-api-gateway auth-interceptor; kacho-deploy zitadel-init job; kacho-corelib principal/) — integration-тест на testcontainers (Zitadel image `ghcr.io/zitadel/zitadel:v2`) + newman-кейс через api-gateway |

---

## 2. Decision Log (зафиксированные решения этого sub-эпика)

Решения, специфичные для E2. Общие epic-level решения — в overview §5.

| #  | Decision                                                                                                                  | Rationale                                                                                                                              | Alternatives rejected                                                                                              |
|----|----------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------|
| D1 | **Zitadel self-hosted** (helm sub-chart, version-pinned)                                                                 | Один и тот же артефакт на dev и prod; полный контроль над signup-UX; нет внешних deps в dev-стенде                                     | (a) Zitadel.cloud (managed) — внешняя зависимость для dev; (b) Keycloak — тяжелее ops, нет первокласного SA-API     |
| D2 | **OIDC-библиотека: `github.com/zitadel/oidc/v3`** (vendor-native)                                                          | Vendor-tested; полная поддержка `private_key_jwt` (RFC 7523), JWKS-cache из коробки, structured introspection                          | (a) `coreos/go-oidc` — более generic, но `private_key_jwt` для SA нужно собирать руками; (b) свой verifier — risky |
| D3 | **JWKS-cache: централизованно в api-gateway** (не per-service)                                                            | Все JWT-проверки идут через api-gateway; backend-сервисы видят уже `Principal` в ctx, не JWT; meньше hot HTTP-vector'ов в Zitadel       | (a) JWKS-cache в каждом сервисе — multiplies HTTP traffic к Zitadel, sync-сложности; (b) JWKS в `kacho-iam` — лишний hop |
| D4 | **`authn.mode = dev \| production \| production-strict`** (config toggle)                                                | Гладкая миграция: `dev` (backwards-compat — anonymous, как сейчас) → `production` (allow Bearer + anonymous-fallback) → `production-strict` (reject without Bearer) | (a) Hard switch — ломает все existing newman-кейсы single-shot; (b) Feature-flag на каждый RPC — раздувание config |
| D5 | **Session: cookie для UI + Bearer для API**                                                                                | UI хранит access_token в `httpOnly secure SameSite=Strict` cookie (XSS-safe, CSRF mitigated через `SameSite=Strict`); CLI/grpcurl шлёт `Authorization: Bearer` | (a) localStorage — XSS-vector; (b) только cookie — CLI неудобно; (c) только Bearer — нужен JS-storage = XSS-risk    |
| D6 | **SA key-flow: `private_key_jwt`** (RFC 7523 JWT-assertion grant)                                                          | Стандарт; не требует client-secret-rotation; ключ создаётся kacho-iam'ом в Zitadel через management-API; private возвращается tenant'у **один раз** | (a) ROPC (username/password для SA) — устаревший и небезопасный grant; (b) client_secret — нужна rotation, leak-risk |
| D7 | **`kacho_iam.sa_keys` — local mirror публичных ключей**                                                                  | FK для AccessBinding (subject_type='service_account'); revoke-флаг для быстрого DENY без round-trip в Zitadel; audit trail              | Хранить только в Zitadel — каждая revoke-проверка = round-trip; CASCADE delete на ServiceAccount работает локально   |
| D8 | **Mode toggle через ENV `KACHO_API_GATEWAY_AUTHN__MODE`**                                                                 | Один источник правды в config (viper/koanf), не разбросанный по interceptor'ам; testable                                              | Per-RPC toggle — раздувание; build-tag — нельзя toggle'ить runtime для CI                                            |
| D9 | **OIDC-callback endpoint живёт в api-gateway** на `/iam/v1/auth/callback` (POST)                                          | Zitadel редиректит на тот же origin, что и UI redirect; api-gateway знает publicURL; экономит один сервис на пути                      | (a) В kacho-iam — Zitadel должен достучаться напрямую до iam, лишний ingress-rule; (b) в UI — secret exchange на клиенте = leak |
| D10| **Unknown subject behaviour: lazy-mirror — `auto-upsert` в auth-interceptor**                                            | Если JWT валидный и Zitadel-user существует, но локального mirror'а нет — `InternalIamService.LookupSubject` зовёт `UpsertFromIdentity` внутри. Tenant УЖЕ прошёл Zitadel signup, mirror просто отстал | (a) Reject `Unauthenticated` — ломает signup-flow E4 (user пройдёт signup, но первый запрос упадёт); (b) `PermissionDenied` — путаница: token валидный, но access denied — UX confusion |
| D11| **JWT TTL 15min, refresh-token-flow через api-gateway proxy**                                                              | Короткий TTL → быстрый эффект revoke (≤15min worst-case даже без NOTIFY); refresh-token идёт через api-gateway (proxy к Zitadel `/oauth/token`) — backend сервисы не знают про refresh | (a) Длинный TTL (8h) — медленный revoke; (b) UI напрямую к Zitadel для refresh — лишний CORS-headache, утечка Zitadel-URL в client |
| D12| **`Principal` в gRPC ctx — через corelib `principal/` package** (typed value, не raw metadata)                            | Типизация; единая helper'ы; снимает с handler'ов парсинг metadata-headers; backwards-compat через ctx-value-key                       | (a) Три отдельных header'а в metadata — каждый handler парсит сам; (b) JSON-encoded header — overhead парсинга; (c) protobuf-binary header — codec в каждом backend |
| D13| **NOTIFY-listener для subject-cache invalidate — добавляется здесь** (но publisher — в E3)                                | Чтобы E3 мог сразу writeFGA + NOTIFY и subject-cache в api-gateway моментально invalidate'ил                                          | Откладывать listener на E3 — потребует второй прогон тестов auth-interceptor с реактивным сбросом                  |

---

## 3. Target architecture (компактно)

### 3.1 Граф edges (новые на E2)

```
                    ┌─────────────┐
                    │  kacho-ui   │
                    └──────┬──────┘
                           │ HTTPS + Cookie session
                           ▼
              ┌─────────────────────────────┐
              │     kacho-api-gateway       │
              │  ┌───────────────────────┐  │
              │  │ AUTH interceptor (E2) │  │
              │  │  Bearer / Cookie      │  │
              │  │  → JWKS validate      │──┼──── HTTPS /keys ───► Zitadel
              │  │  → SubjectLookup      │──┼──── gRPC-direct ───► kacho-iam:9091
              │  │  → Principal in ctx   │  │
              │  └───────────────────────┘  │
              │  ┌───────────────────────┐  │
              │  │ AUTHZ interceptor     │  │
              │  │  (no-op pass-through) │  │      (E3 заполнит OpenFGA Check)
              │  └───────────────────────┘  │
              │  ┌───────────────────────┐  │
              │  │ SubjectChangeListener │──┼──── gRPC stream ───► kacho-iam:9091
              │  │ (NOTIFY-invalidate)   │  │       InternalSubjectChangeNotificationService
              │  └───────────────────────┘  │      (publisher: E3; listener: E2)
              └──────────────┬──────────────┘
                             │  + Principal in ctx
                             ▼
                    backend services (vpc/compute/lb/iam)
                             │
                             ▼
                    corelib.operations.CreateWithPrincipal(ctx, ...)
                             │
                             ▼
                    operations.principal_{type,id,display_name} ← реальный USER/SA

              ┌─────────────────────────────┐
              │       kacho-iam             │
              │  ┌───────────────────────┐  │
              │  │ OIDC client           │──┼──── HTTPS /.well-known ─► Zitadel
              │  │  (discovery, JWKS,    │  │  + management API:
              │  │   management API)     │  │     POST /management/v1/users/{id}/keys
              │  └───────────────────────┘  │     (SA key creation)
              │  ┌───────────────────────┐  │
              │  │ /auth/callback handler│  │    (POST endpoint;
              │  │  → UpsertFromIdentity │  │     Zitadel redirects здесь
              │  │  → return session     │  │     с auth-code,
              │  └───────────────────────┘  │     handler exchanges на token
              │                              │     и upsertit User mirror)
              └──────────────────────────────┘
                             │
                             ▼
                    ┌──────────────┐
                    │   Zitadel    │
                    │  (self-host) │
                    └──────┬───────┘
                           ▼
                    ┌──────────────┐
                    │   zitadel    │ (Postgres БД)
                    └──────────────┘
```

### 3.2 Что добавляется в каждый репо (краткий обзор; детальные RPC — §4)

| Репо                | Что добавляется                                                                                                                             |
|---------------------|---------------------------------------------------------------------------------------------------------------------------------------------|
| `kacho-proto`       | `kacho.cloud.iam.v1.service_account_key.proto` (CreateKey/Get/List/Revoke); `kacho.cloud.iam.v1.auth.proto` (Token/RefreshToken/Logout — REST-only через grpc-gateway); расширение `InternalIamService` методом `Validate{AccessToken→Subject}` |
| `kacho-corelib`     | `principal/` package — `Principal{Type, ID, DisplayName}` + `WithPrincipal(ctx, p)` + `FromContext(ctx) (Principal, bool)`; `operations.CreateWithPrincipal(ctx, op)` (читает principal из ctx, фолбэк `system`) |
| `kacho-iam`         | `internal/clients/zitadel_client.go` (OIDC discovery, JWKS fetch, management API wrapper); `internal/apps/kacho/api/auth_callback/handler.go` (REST POST `/iam/v1/auth/callback`); `internal/apps/kacho/api/service_account_key/{create,get,list,revoke}.go`; миграция `0002_sa_keys.sql`; `internal/jobs/zitadel_management_bootstrap.go` (post-install создаёт machine-user для kacho-iam в Zitadel) |
| `kacho-api-gateway` | `internal/middleware/auth.go` (replaces `auth_noop`); `internal/middleware/cookie_session.go` (cookie→Bearer); `internal/clients/iam_subject_client.go` (gRPC-direct к `kacho-iam:9091`); `internal/cache/subject_cache.go` (LRU + TTL 30s); `internal/clients/zitadel_jwks_client.go` (JWKS-cache 30min); `internal/jobs/subject_change_listener.go` (gRPC-stream listener + invalidate); удаление `auth_noop` файла |
| `kacho-deploy`      | helm sub-chart hooks: `post-install/zitadel-bootstrap-job.yaml` (создаёт `kacho` Org в Zitadel, master-admin user, machine-user `kacho-iam` с PAT для management API; PAT сохраняется в Secret `kacho-iam-zitadel-pat`); ingress `https://login.kacho.local` уже добавлен в E0 stubs |
| `kacho-ui`          | минимальный shim: login-button → redirect на Zitadel `/login?redirect_uri=...&client_id=kacho-ui`; обработка `/auth/callback?code=...` (передача `code` в api-gateway, получение cookie); полноценный IAM-блок — E4 |

### 3.3 Loop prevention для `InternalIamService.LookupSubject` (запрет #6)

**Проблема:** auth-interceptor api-gateway работает на REST-входе (через
grpc-gateway HTTP-mux). Если `InternalIamService.LookupSubject` зарегистрирован
в том же REST-mux'е (даже на cluster-internal listener) — попытка interceptor'а
проксировать запрос на backend пройдёт **через тот же REST-mux**, который снова
вызовет auth-interceptor → recursion → стек-оверфлоу.

**Решение (D3, overview §6.2):**
- `LookupSubject` и `ValidateAccessToken` — **gRPC-direct only**: api-gateway держит
  свой `grpcclient` в `internal/clients/iam_subject_client.go` (dial-target
  `kacho-iam.kacho.svc.cluster.local:9091`), вызывает напрямую через generated stub.
- **НЕ регистрируется** в `kacho-api-gateway/internal/restmux/mux.go`.
- Остальные internal-методы (`InternalUserService.UpsertFromIdentity` — для admin),
  `InternalFGABootstrapService` — могут регистрироваться в restmux под
  `iamInternalAddr` блоком (cluster-internal HTTP listener), как другие
  admin-tooling endpoints.

Аналогично `SubjectChangeNotificationService.Watch` — gRPC server-streaming прямо
к `kacho-iam:9091`, не через mux.

### 3.4 Cookie-session vs Bearer (D5)

Сценарии для api-gateway:

1. **UI (browser)**: после signup/login через Zitadel callback на api-gateway
   `/iam/v1/auth/callback`, handler устанавливает cookie:
   ```
   Set-Cookie: kacho_session=<access_token>;
               Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=900
   ```
   На каждый последующий REST-запрос UI шлёт cookie автоматически.
   `cookie_session.go` middleware на входе REST читает cookie и **переписывает**
   `Authorization: Bearer <token>` header в gRPC metadata перед auth-interceptor.
2. **CLI / gRPC / SA**: шлёт `Authorization: Bearer <jwt>` напрямую — никаких cookies.
3. **Refresh**: cookie экспайрится за 15min (Max-Age=900) **или** UI делает proactive
   refresh за 1min до истечения через `POST /iam/v1/auth/refresh` (передаёт
   `refresh_token` cookie `kacho_refresh=<rt>; HttpOnly; Path=/iam/v1/auth/refresh; ...`).
4. **Logout**: `POST /iam/v1/auth/logout` — handler в api-gateway зовёт Zitadel
   `revocation_endpoint`, очищает оба cookie.

CSRF mitigation:
- `SameSite=Strict` — браузер не шлёт cookie на cross-site навигации.
- Для state-changing API (POST/DELETE/PATCH через cookie-only клиента) — дополнительный
  CSRF-token header `X-CSRF-Token` (issued в `/auth/callback`, хранится в non-HttpOnly cookie
  `kacho_csrf`, UI читает и шлёт обратно как header — standard double-submit pattern).

---

## 4. Декомпозиция по компонентам (что именно реализуется)

### 4.1 Zitadel deploy (kacho-deploy)

E0 уже добавил helm-stub в `values.dev.yaml` (zitadel sub-chart, ExternalDomain,
postgres backend, ingress `zitadel.kacho.local`). E2 доводит до production-grade:

1. **TLS на dev**: ingress использует self-signed cert (helm-managed Secret
   `zitadel-tls`). Tenant'ы /etc/hosts'ом мапят `zitadel.kacho.local` на kind-нод.
2. **Persistence**: `pg-zitadel` PVC enabled для prod-values (dev — emptyDir,
   как сейчас).
3. **Secrets через Helm Secrets**: `masterkey` (32 chars), `zitadel-admin-password`,
   `zitadel-iam-machine-user-pat` — генерируются bootstrap-job'ом, сохраняются в
   kubernetes Secrets, никогда не commit'ятся в values.yaml.
4. **Bootstrap-job**: `templates/zitadel-bootstrap-job.yaml` (Helm post-install hook,
   `hook-weight: 5`):
   - Ждёт Zitadel healthy (curl `/debug/healthz`).
   - Через admin-API создаёт Org `kacho` (`POST /admin/v1/orgs`).
   - Создаёт master-admin human-user `kacho-bootstrap@local` с паролем из Secret
     (для emergency console-доступа).
   - Создаёт machine-user `kacho-iam@kacho` (Zitadel SA для management API
     операций kacho-iam), генерирует PAT, сохраняет в Secret
     `kacho-iam-zitadel-pat` (consumed kacho-iam'ом как
     `KACHO_IAM_EXTAPI__ZITADEL__MGMT_PAT`).
   - Регистрирует **два OAuth-приложения** в Org `kacho`:
     - `kacho-ui` (Application type: Web, PKCE flow, redirect URIs:
       `https://api.kacho.local/iam/v1/auth/callback`, `http://localhost:5173/auth/callback`).
     - `kacho-api-gateway` (Application type: API/Service, JWT validation profile;
       client_id используется auth-interceptor'ом как `audience` для проверки `aud`-claim).
5. **Login UI**: используется default Zitadel login UI; кастомизация бренда —
   логотип Kachō, цветовая схема (через Zitadel management API в bootstrap-job).
   Расширенная кастомизация (full theme) — phase 2.1.

### 4.2 kacho-iam OIDC client + SA key-flow

**`internal/clients/zitadel_client.go`** (new):

```go
package clients

type ZitadelClient interface {
    // OIDC discovery (cached forever — issuer URL не меняется).
    DiscoveryDocument(ctx context.Context) (*oidc.DiscoveryConfiguration, error)
    // JWKS fetch (для admin/тулинга; auth-interceptor api-gateway использует свой кеш — §4.3).
    JWKS(ctx context.Context) (jose.JSONWebKeySet, error)
    // Management API: создать SA key для Zitadel-machine-user.
    CreateMachineKey(ctx context.Context, machineUserID string, expirationDays int) (*MachineKeyResponse, error)
    // Management API: revoke SA key.
    RevokeMachineKey(ctx context.Context, machineUserID, keyID string) error
    // Management API: создать Zitadel-user для kacho User mirror'а.
    CreateHumanUser(ctx context.Context, email, displayName string) (string /* zitadel user id */, error)
    // Token exchange: SA private_key_jwt → access_token.
    ExchangeJWTAssertion(ctx context.Context, assertion string) (*TokenResponse, error)
}
```

Реализация — обёртка над `github.com/zitadel/oidc/v3/pkg/client` и
`github.com/zitadel/zitadel-go/v3/pkg/client/management` (или прямые REST-вызовы
если SDK слишком тяжёл).

**`internal/apps/kacho/api/auth_callback/handler.go`** (new):

REST POST `/iam/v1/auth/callback` (НЕ gRPC — это OAuth redirect, у Zitadel
форма-encoded body; регистрируется в grpc-gateway как custom HTTP handler):

Использует `ZitadelClient` (см. §4.2 выше) и `InternalUserService.UpsertFromIdentity`
для создания / обновления mirror'а; возвращает cookie-сессию (D5).

**`internal/apps/kacho/api/service_account_key/`** (4 use-case):

- `create.go` — `ServiceAccountKeyService.Create({serviceAccountId, expirationDays=365})`:
  1. Sync validate: SA существует (`Reader.GetServiceAccount(ctx, id)`); user может (через `ctx.Principal`)
     создавать ключи (для E2 — заглушка `principal.Type == admin`; полный authz — E3).
  2. Async: zitadel.CreateMachineKey → ответ содержит `{key_id, private_key (PEM), expiration_date}`.
  3. INSERT в `kacho_iam.sa_keys (service_account_id, key_id, algorithm='RSA-2048', public_pem,
     created_at, expires_at, revoked_at=NULL)`.
  4. Возврат `ServiceAccountKey{id, key_id, algorithm, created_at, expires_at, private_key_pem}`
     — `private_key_pem` отдаётся **один раз**, далее НЕ хранится у нас.
- `get.go`, `list.go` — read-only, без private_key.
- `revoke.go` — sync UPDATE `revoked_at = now()` (CAS: `WHERE revoked_at IS NULL`); async
  zitadel.RevokeMachineKey.

**`internal/jobs/zitadel_management_bootstrap.go`** (new): на старте kacho-iam
проверяет `KACHO_IAM_EXTAPI__ZITADEL__MGMT_PAT` — если задан, делает test-call
`POST /management/v1/users/_search` (with PAT) → 200; если PAT отсутствует / 401 —
log warning, kacho-iam стартует в degraded mode (CreateKey/UpsertFromIdentity отдают
`Unavailable`).

**`internal/repo/kacho/pg/sa_key.go`** + **`internal/migrations/0002_sa_keys.sql`** (new):

```sql
CREATE TABLE kacho_iam.sa_keys (
    id                 TEXT      PRIMARY KEY,         -- 'sak<17chars>'
    service_account_id TEXT      NOT NULL REFERENCES kacho_iam.service_accounts(id) ON DELETE CASCADE,
    key_id             TEXT      NOT NULL,            -- Zitadel-internal key-id
    algorithm          TEXT      NOT NULL CHECK (algorithm IN ('RSA-2048','RSA-4096')),
    public_pem         TEXT      NOT NULL,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at         TIMESTAMPTZ NOT NULL,
    revoked_at         TIMESTAMPTZ,                    -- NULL = active
    CONSTRAINT sa_keys_zitadel_key_unique UNIQUE (service_account_id, key_id)
);
-- Partial UNIQUE: один active key per SA это **не** инвариант (multi-active ok);
-- но индекс по active-keys нужен для fast lookup.
CREATE INDEX sa_keys_active_by_sa ON kacho_iam.sa_keys (service_account_id)
    WHERE revoked_at IS NULL;
```

### 4.3 kacho-api-gateway auth-interceptor

**`internal/middleware/auth.go`** (replaces `auth_noop.go`):

```go
package middleware

type AuthInterceptor struct {
    mode          AuthMode             // dev / production / production-strict
    jwksClient    *jwks.Client         // §4.3.1
    subjectClient *iamclient.Subject   // §4.3.2 (gRPC-direct к kacho-iam:9091)
    subjectCache  *cache.LRU           // §4.3.3
    expectedAud   string               // "kacho-api-gateway" (от Zitadel)
    expectedIss   string               // "https://zitadel.kacho.local"
    logger        *slog.Logger
    metrics       *metrics.AuthMetrics
}

func (i *AuthInterceptor) Unary() grpc.UnaryServerInterceptor { ... }
func (i *AuthInterceptor) Stream() grpc.StreamServerInterceptor { ... }
```

Логика (unary):

1. Парс `Authorization: Bearer <jwt>` из incoming metadata.
   - Если **пусто** и `mode == dev` → пробрасывает с `Principal{Type:"system",ID:"anonymous",DisplayName:""}`
     в ctx (backward-compat).
   - Если **пусто** и `mode == production` → пробрасывает anonymous (для public-endpoints
     типа `/iam/v1/auth/callback`), кладёт в ctx флаг `principal.IsAnonymous(ctx) == true`.
     downstream handler сам решит, нужен ли auth (auth-callback не нужен).
   - Если **пусто** и `mode == production-strict` → `Unauthenticated "missing Bearer token"`.
2. JWT parse + validate через `jwksClient.Verify(token, expectedIss, expectedAud)`:
   - JWKS lookup по `kid` (cached 30min).
   - Подпись через `jose.ParseSigned` + public key.
   - Проверка `exp`, `nbf`, `iat`, `iss`, `aud`.
   - На любую ошибку → `Unauthenticated "<reason>"` (с YC-style текстом — см. §6).
3. Subject lookup:
   - Сначала `subjectCache.Get(jwt.Subject)` — если hit (cached 30s) → используем.
   - Если miss → `subjectClient.LookupSubject(ctx, &LookupSubjectRequest{ByExternalId: jwt.Subject})`.
     - `NotFound` + mode == dev → fallback anonymous (для legacy кейсов).
     - `NotFound` + mode == production → lazy-mirror через `UpsertFromIdentity(jwt.Subject, jwt.Email, jwt.Name)`
       (D10): zitadel говорит про user'а, mirror просто отстаёт. После upsert
       снова Lookup → принимает.
     - `NotFound` + mode == production-strict → `Unauthenticated "subject not found"`.
     - `Unavailable` (kacho-iam down) → `Unavailable "iam service unavailable"` (не падаем в gateway).
   - Сохраняем в кеш с TTL 30s.
4. `Principal{Type: subj.Type, ID: subj.ID, DisplayName: subj.DisplayName}` →
   `principal.WithPrincipal(ctx, p)` → `handler(ctx, req)`.
5. Метрика `kacho_api_gateway_auth_interceptor_duration_seconds_bucket{path=...,result=success|fail,cache_hit=true|false}`.

**`internal/clients/zitadel_jwks_client.go`** (new):

JWKS-cache с TTL 30min, refresh-ahead 5min. Использует `github.com/MicahParks/keyfunc/v3`
(или `zitadel/oidc/v3/pkg/oidc.KeySet`). На startup делает initial fetch — если
Zitadel недоступен на старте, api-gateway стартует в `degraded` mode (auth-interceptor
отдаёт `Unavailable` пока JWKS не подгрузится).

**`internal/clients/iam_subject_client.go`** (new): gRPC-direct stub к
`kacho-iam:9091` для `InternalIamService.LookupSubject` и
`InternalSubjectChangeNotificationService.Watch`. Dial-target из ENV
`KACHO_API_GATEWAY_IAM__INTERNAL_ADDR`.

**`internal/cache/subject_cache.go`** (new): LRU bounded (max 10k entries) + TTL
30s. Key: `subject_external_id` (string). Value: `Principal{Type, ID, DisplayName, ExpiresAt}`.
Public API: `Get(key) (Principal, bool)`, `Set(key, p, ttl)`, `Invalidate(externalID string)`,
`InvalidateAll()`. Метрики hit/miss/eviction.

**`internal/jobs/subject_change_listener.go`** (new): background goroutine,
держит gRPC server-streaming на `kacho-iam.InternalSubjectChangeNotificationService.Watch()`,
на каждое NOTIFY-event { external_id, op: 'binding_upsert|binding_delete|user_delete|sa_revoke' }
вызывает `subjectCache.Invalidate(external_id)`. На E2 publisher (kacho-iam) шлёт
events только для `user_delete` и `sa_revoke` (E3 добавит `binding_*`).

### 4.4 corelib `principal/` + `operations.CreateWithPrincipal`

**`kacho-corelib/principal/principal.go`** (new):

```go
package principal

type Type string
const (
    TypeUser           Type = "user"
    TypeServiceAccount Type = "service_account"
    TypeSystem         Type = "system"   // bootstrap, fallback
)

type Principal struct {
    Type        Type
    ID          string  // 'usr...' / 'sva...' / 'anonymous' / 'bootstrap'
    DisplayName string
}

func WithPrincipal(ctx context.Context, p Principal) context.Context { ... }
func FromContext(ctx context.Context) (Principal, bool) { ... }
func IsAnonymous(ctx context.Context) bool { ... }

// gRPC metadata wire-format (для proxy через api-gateway → backend):
// x-kacho-principal-type:         "user" | "service_account" | "system"
// x-kacho-principal-id:           "<id>"
// x-kacho-principal-display-name: "<display>"
func MarshalToMetadata(ctx context.Context) (metadata.MD, error) { ... }
func UnmarshalFromIncomingContext(ctx context.Context) (context.Context, error) { ... }
```

Marshal/Unmarshal используется api-gateway proxy слоем при пересылке gRPC-call'а
backend-сервису: api-gateway положит три headers в outgoing-metadata, backend
unmarshal'ит на входе через свой interceptor (тонкая `principal-extract` middleware
в `kacho-corelib/grpcsrv/`, добавляется в server bootstrap).

**`kacho-corelib/operations/repo.go`** — расширение сигнатуры:

E0 (current): `func (r *Repo) Create(ctx, op Operation) (Operation, error)` — пишет
hardcoded `principal_type='system', principal_id='bootstrap', display_name='kacho-iam-bootstrap'`.

E2: добавляется `func (r *Repo) CreateWithPrincipal(ctx, op Operation) (Operation, error)` —
читает `principal.FromContext(ctx)` (fallback на system если нет), пишет в три колонки
`principal_*`. **Старая `Create` deprecated** — оставлена для backward-compat (помечена
`// Deprecated: use CreateWithPrincipal`), не удаляется до E4 (E4 переключит все existing
call-sites + удалит).

### 4.5 Mode toggle

Config:

```yaml
# kacho-api-gateway config (config.yaml + ENV override)
authn:
  mode: dev   # dev | production | production-strict
  zitadel:
    issuer:           https://zitadel.kacho.local
    expected_audience: kacho-api-gateway
    jwks_cache_ttl:    30m
  subject_cache:
    ttl:        30s
    max_size:   10000
  iam_internal_addr: kacho-iam.kacho.svc.cluster.local:9091
```

ENV override: `KACHO_API_GATEWAY_AUTHN__MODE=production-strict`.

Backwards-compat:
- `mode: dev` (default до cutover) — все existing newman-кейсы продолжают работать
  без модификации (anonymous proxy'ится в ctx, backend пишет `system` в principal).
- `mode: production` — кейсы переключаются на authenticated один-за-одним; helper
  `acquire_test_jwt()` в `tests/newman/_lib/auth.py` (E2 добавит).
- `mode: production-strict` — финальный режим после E4; включается в prod-values.

---

## 5. GWT-сценарии

Минимум 20, разбито на 7 секций по компонентам. Sync-ответ через api-gateway = gRPC
unary unless указано. Все сценарии запускаются на dev-стенде после `make dev-up`.

### 5.1 Zitadel deploy (3 сценария)

#### Scenario 01: Helm install Zitadel + post-install bootstrap-job

**ID:** 2.0-E2-GWT-01
**REQ:** REQ-IAM-E2-DEPLOY-01

**Given** свежий kind-кластер, `pg-zitadel`, `pg-iam`, `pg-openfga` ещё не существуют
**And** `values.dev.yaml` содержит секции `pg-zitadel`, `zitadel`, `pg-iam`, `openfga`,
  `kacho-iam` (E0-stubs)
**And** helm-chart `kacho-deploy/helm/umbrella` содержит template
  `post-install/zitadel-bootstrap-job.yaml`

**When** оператор запускает `make dev-up`

**Then** в течение ≤8 минут все pods в статусе `Running`/`Ready`
**And** Zitadel pod healthy (`/debug/healthz` → 200)
**And** post-install bootstrap-job завершён со статусом `Succeeded`
**And** существует Kubernetes Secret `zitadel-bootstrap` с ключами
  `admin_password`, `master_key`
**And** существует Kubernetes Secret `kacho-iam-zitadel-pat` с ключом `pat`
**And** Zitadel admin console доступен через `https://zitadel.kacho.local` (после
  добавления `/etc/hosts: 127.0.0.1 zitadel.kacho.local`)

#### Scenario 02: Bootstrap создаёт Org `kacho` + machine-user kacho-iam + OAuth apps

**ID:** 2.0-E2-GWT-02
**REQ:** REQ-IAM-E2-DEPLOY-02

**Given** stend поднят (GWT-01)

**When** оператор подключается к Zitadel admin console под `kacho-bootstrap@local`

**Then** в списке Orgs виден `kacho` (created by bootstrap-job)
**And** в Org `kacho` существует Machine User `kacho-iam@kacho` с активным PAT
**And** в Org `kacho` существует Application `kacho-ui` (Web, PKCE, redirect URIs включают `https://api.kacho.local/iam/v1/auth/callback`)
**And** в Org `kacho` существует Application `kacho-api-gateway` (API/Service profile)
**And** PAT из Secret `kacho-iam-zitadel-pat` валиден через `curl -H "Authorization: Bearer <pat>" https://zitadel.kacho.local/management/v1/users/_search` → 200 с непустым списком

#### Scenario 03: Pod kacho-iam использует PAT для management API + degraded mode при отсутствии PAT

**ID:** 2.0-E2-GWT-03
**REQ:** REQ-IAM-E2-DEPLOY-03

**Given** dev-стенд поднят (GWT-01, GWT-02)

**When** kacho-iam pod стартует; ENV `KACHO_IAM_EXTAPI__ZITADEL__MGMT_PAT` mount'нут из Secret

**Then** в логах kacho-iam видна строка
  `extapi.zitadel: PAT validated; management API reachable`
**And** `POST /iam/v1/serviceAccounts/{id}/keys:create` (через api-gateway) отвечает
  Operation → done=true → SA-key с приватным ключом

**When** оператор удаляет Secret `kacho-iam-zitadel-pat` и kubectl rollout restart kacho-iam

**Then** в логах kacho-iam видна WARN-строка
  `extapi.zitadel: PAT missing or invalid; entering degraded mode`
**And** pod healthy = false для readiness `/healthz/extapi` (но liveness ok — pod не рестартится)
**And** `POST /iam/v1/serviceAccounts/{id}/keys:create` → `Unavailable "zitadel management api unavailable"`

### 5.2 OIDC discovery + JWKS cache (2 сценария)

#### Scenario 04: OIDC well-known + JWKS endpoint доступен

**ID:** 2.0-E2-GWT-04
**REQ:** REQ-IAM-E2-OIDC-01

**Given** Zitadel deployed (GWT-01)

**When** клиент делает `GET https://zitadel.kacho.local/.well-known/openid-configuration`

**Then** ответ 200 содержит JSON с полями `issuer`, `jwks_uri`, `authorization_endpoint`, `token_endpoint`, `userinfo_endpoint`, `introspection_endpoint`, `revocation_endpoint`
**And** `issuer == "https://zitadel.kacho.local"`
**And** `GET <jwks_uri>` возвращает JSON с массивом `keys[]` где каждый ключ имеет `kid`, `kty`, `use`, `alg`, `n`, `e`

#### Scenario 05: JWKS-cache в api-gateway hit-rate

**ID:** 2.0-E2-GWT-05
**REQ:** REQ-IAM-E2-OIDC-02

**Given** api-gateway pod started, `authn.mode = production`
**And** Zitadel JWKS содержит один key с `kid = "kacho-test-1"`

**When** делаем 1000 валидных JWT-запросов через `grpcurl` с разными JWT (но одним и тем же `kid`)
**And** меряем количество outbound HTTP-запросов от api-gateway к `https://zitadel.kacho.local/keys`

**Then** в течение первого окна 30min — ровно **1** outbound запрос к JWKS
**And** метрика `kacho_api_gateway_jwks_cache_hits_total{result="hit"}` инкрементирована ≥999 раз
**And** метрика `kacho_api_gateway_jwks_cache_hits_total{result="miss"}` инкрементирована ровно 1 раз
**And** auth-interceptor p95 latency ≤5ms (NFR-1)

### 5.3 Auth callback (3 сценария)

#### Scenario 06: Happy code-exchange → cookie session

**ID:** 2.0-E2-GWT-06
**REQ:** REQ-IAM-E2-CALLBACK-01

**Given** Zitadel deployed, в Org `kacho` существует human-user `alice@example.com`
**And** alice прошла login через Zitadel `/login`, получила authorization code `<code>` через redirect на `/iam/v1/auth/callback?code=<code>&state=<state>`

**When** браузер шлёт `POST /iam/v1/auth/callback` с form-body `code=<code>&state=<state>`

**Then** api-gateway отвечает 302 Found с `Location: /` (или `state.return_to`)
**And** ответ содержит `Set-Cookie: kacho_session=<jwt>; HttpOnly; Secure; SameSite=Strict; Max-Age=900`
**And** ответ содержит `Set-Cookie: kacho_refresh=<rt>; HttpOnly; Secure; Path=/iam/v1/auth/refresh; Max-Age=2592000`
**And** ответ содержит `Set-Cookie: kacho_csrf=<token>; Secure; SameSite=Strict; Max-Age=900` (НЕ HttpOnly — UI читает)
**And** в `kacho_iam.users` появилась row с `external_id=<zitadel-user-id-of-alice>`, `email=alice@example.com` (UPSERT через `InternalUserService.UpsertFromIdentity`)
**And** последующий `GET /iam/v1/users/me` с cookie возвращает 200 с alice'ой

#### Scenario 07: Expired authorization code → reject

**ID:** 2.0-E2-GWT-07
**REQ:** REQ-IAM-E2-CALLBACK-02

**Given** alice получила code, но не использовала в течение 10min (Zitadel default code TTL)

**When** браузер шлёт `POST /iam/v1/auth/callback` с устаревшим code

**Then** api-gateway зовёт Zitadel `/oauth/token` с code → Zitadel отвечает 400 `invalid_grant`
**And** api-gateway отвечает 400 с JSON `{"code":3,"message":"authorization code expired or invalid","details":[]}` (gRPC INVALID_ARGUMENT через grpc-gateway)
**And** cookies НЕ устанавливаются
**And** в `kacho_iam.users` нет новых rows

#### Scenario 08: Redirect URL mismatch → reject

**ID:** 2.0-E2-GWT-08
**REQ:** REQ-IAM-E2-CALLBACK-03

**Given** Zitadel app `kacho-ui` зарегистрирован с redirect URIs `https://api.kacho.local/iam/v1/auth/callback`
**And** атакующий перехватил `code` и пытается обменять через подмену `redirect_uri = https://evil.local/cb`

**When** запрос `POST /iam/v1/auth/callback` приходит с `redirect_uri=https://evil.local/cb`

**Then** api-gateway зовёт Zitadel `/oauth/token` с указанным redirect_uri → Zitadel отвечает 400 `invalid_grant` (redirect_uri mismatch)
**And** api-gateway отвечает 400 с JSON `{"code":3,"message":"redirect_uri mismatch","details":[]}`
**And** cookies НЕ устанавливаются

### 5.4 JWT validation (4 сценария)

#### Scenario 09: Валидный JWT через grpcurl → 200

**ID:** 2.0-E2-GWT-09
**REQ:** REQ-IAM-E2-JWT-01

**Given** `authn.mode = production`
**And** alice имеет валидный access_token (получен через ROPC-grant или предыдущий callback)
**And** alice уже в `kacho_iam.users`

**When** клиент вызывает `grpcurl -H "authorization: Bearer <jwt>" -d '{}' api.kacho.local:443 kacho.cloud.iam.v1.UserService/List`

**Then** ответ gRPC OK с непустым списком users
**And** в логах api-gateway видна строка `auth: success; principal_type=user; principal_id=usr...`
**And** в логах backend kacho-iam видна строка `principal_type=user; principal_id=usr...` (а не `system`)

#### Scenario 10: Expired JWT → Unauthenticated

**ID:** 2.0-E2-GWT-10
**REQ:** REQ-IAM-E2-JWT-02

**Given** `authn.mode = production`
**And** alice имеет JWT с `exp` в прошлом (15min TTL истёк)

**When** клиент вызывает `grpcurl -H "authorization: Bearer <expired-jwt>" ... UserService/List`

**Then** ответ gRPC код `UNAUTHENTICATED` с message `"token expired"`
**And** в HTTP-ответе через grpc-gateway статус 401
**And** Set-Cookie НЕ выставляется (это не callback)
**And** backend kacho-iam НЕ получил запрос (interceptor отверг до проксирования)
**And** метрика `kacho_api_gateway_auth_interceptor_duration_seconds_bucket{result="fail",reason="expired"}` инкрементирована

#### Scenario 11: Wrong audience → Unauthenticated

**ID:** 2.0-E2-GWT-11
**REQ:** REQ-IAM-E2-JWT-03

**Given** `authn.mode = production`, `expected_audience = "kacho-api-gateway"`
**And** есть JWT, подписанный тем же Zitadel issuer, но с `aud = "other-app"` (например, из app `kacho-ui` напрямую)

**When** клиент шлёт этот JWT в API

**Then** ответ `UNAUTHENTICATED` с message `"token audience mismatch"`
**And** в логах WARN `auth: aud=other-app, expected=kacho-api-gateway`

#### Scenario 12: Wrong issuer → Unauthenticated

**ID:** 2.0-E2-GWT-12
**REQ:** REQ-IAM-E2-JWT-04

**Given** `authn.mode = production`, `expected_iss = "https://zitadel.kacho.local"`
**And** атакующий поднял свой Zitadel-like IdP и подписал JWT с тем же sub/aud, но `iss = "https://evil.local"`

**When** клиент шлёт этот JWT

**Then** ответ `UNAUTHENTICATED` с message `"token signature invalid"` (JWKS lookup для wrong-issuer kid не найдёт ключ → fail)
**And** НЕТ outbound HTTP к `https://evil.local/.well-known/openid-configuration` — api-gateway работает только с одним trusted issuer (no dynamic discovery)

### 5.5 Subject lookup (2 сценария)

#### Scenario 13: Existing user mirror — cache hit на повторный запрос

**ID:** 2.0-E2-GWT-13
**REQ:** REQ-IAM-E2-SUBJ-01

**Given** alice в `kacho_iam.users` с `external_id = "zit-12345"`
**And** subject_cache пуст (api-gateway только перезапущен)

**When** alice делает первый запрос с JWT (subject=zit-12345)
**Then** в логах api-gateway видна строка `subject_lookup: miss; calling iam:9091`
**And** subject_cache содержит entry `zit-12345 → Principal{Type:user, ID:usr_alice, DisplayName:alice@example.com}`

**When** alice делает второй запрос в течение 30s

**Then** в логах строка `subject_lookup: cache hit`
**And** outbound gRPC к kacho-iam:9091 НЕ происходит (verify через metrics `kacho_api_gateway_subject_lookups_total{result="cache_hit"}`)
**And** общая p95 latency auth-interceptor ≤5ms (NFR-1)

#### Scenario 14: Unknown subject (lazy-mirror через UpsertFromIdentity)

**ID:** 2.0-E2-GWT-14
**REQ:** REQ-IAM-E2-SUBJ-02

**Given** `authn.mode = production`
**And** в Zitadel есть user `bob@example.com` (Zitadel sub `zit-67890`), прошёл signup
**And** в `kacho_iam.users` отсутствует mirror для `zit-67890` (например, kacho-iam был временно down во время signup, mirror не записался)

**When** bob делает запрос `GET /iam/v1/users/me` через api-gateway с валидным JWT

**Then** auth-interceptor зовёт `subjectClient.LookupSubject({by_external_id: "zit-67890"})` → kacho-iam отвечает NOT_FOUND
**And** auth-interceptor (mode=production, D10) вызывает `subjectClient.LookupSubject({by_external_id: "zit-67890", create_if_missing: true, identity_hint: {email, display_name из JWT}})` — этот alt-method внутри делает `UpsertFromIdentity` и возвращает свежесозданный subject
**And** в `kacho_iam.users` создаётся row для bob (email/display_name из JWT-claims)
**And** запрос проходит дальше, bob получает 200 с собой как ответом
**And** в `kacho_iam.users` UPSERT идемпотентен (повторный вызов lookups → второй вызов с create_if_missing не дублирует row)

> Note: `mode=production-strict` в том же сценарии вернул бы `Unauthenticated "subject not found"` — отдельный negative-кейс в `tests/newman/cases/iam-auth-subject-not-found-strict.py`.

### 5.6 Principal propagation (3 сценария)

#### Scenario 15: VPC Network.Create показывает реального user'а в operations.principal_*

**ID:** 2.0-E2-GWT-15
**REQ:** REQ-IAM-E2-PRINCIPAL-01

**Given** alice (USER, usr_alice, email alice@example.com) с валидным JWT
**And** существует Project `prj_dev`
**And** `authn.mode = production`

**When** alice вызывает `grpcurl -H "authorization: Bearer <alice-jwt>" -d '{"name":"net-1","projectId":"prj_dev"}' ... vpc.NetworkService/Create`

**Then** api-gateway пропускает запрос через auth → Principal = {USER, usr_alice, alice@example.com}
**And** api-gateway добавляет три header'а в outgoing-metadata: `x-kacho-principal-type=user`, `x-kacho-principal-id=usr_alice`, `x-kacho-principal-display-name=alice@example.com`
**And** kacho-vpc получает запрос; corelib `principal-extract` interceptor читает headers → ctx обогащается Principal
**And** kacho-vpc handler зовёт `operations.CreateWithPrincipal(ctx, op)` — в `kacho_vpc.operations` появляется row с `principal_type='user'`, `principal_id='usr_alice'`, `principal_display_name='alice@example.com'`
**And** `GET /vpc/v1/operations/{op_id}` возвращает payload с `created_by: {type: 'USER', id: 'usr_alice', display_name: 'alice@example.com'}`

#### Scenario 16: Compute Instance.Create через SA → operations.principal_* = service_account

**ID:** 2.0-E2-GWT-16
**REQ:** REQ-IAM-E2-PRINCIPAL-02

**Given** SA `ci-runner` (sva_ci, display_name "CI Runner") с активным key (создан через GWT-19)
**And** CI-bot собирает JWT-assertion через `private_key_jwt`, обменивает на access_token (GWT-20)
**And** существует Project `prj_dev`

**When** CI-bot вызывает `grpcurl -H "authorization: Bearer <sa-access-token>" -d '{"name":"vm-ci-01","projectId":"prj_dev",...}' ... compute.InstanceService/Create`

**Then** auth-interceptor резолвит subject → Principal = {SERVICE_ACCOUNT, sva_ci, "CI Runner"}
**And** в `kacho_compute.operations` появляется row с `principal_type='service_account'`, `principal_id='sva_ci'`, `principal_display_name='CI Runner'`
**And** `GET /compute/v1/operations/{op_id}` возвращает payload с `created_by: {type: 'SERVICE_ACCOUNT', id: 'sva_ci', display_name: 'CI Runner'}`

#### Scenario 17: System bootstrap (mode=dev, anonymous) → operations.principal_* = system/bootstrap

**ID:** 2.0-E2-GWT-17
**REQ:** REQ-IAM-E2-PRINCIPAL-03

**Given** `authn.mode = dev` (backwards-compat для existing tests / first-bootstrap)
**And** клиент `grpcurl` БЕЗ Bearer header

**When** клиент вызывает `... vpc.NetworkService/Create`

**Then** auth-interceptor → `Principal = {SYSTEM, "anonymous", ""}`
**And** в `kacho_vpc.operations`: `principal_type='system'`, `principal_id='anonymous'`, `principal_display_name=''`
**And** запрос проходит и Network создаётся (mode=dev — allow anonymous)
**And** все existing newman-кейсы (предшествующие E2) продолжают работать без изменений

### 5.7 SA key-flow (3 сценария)

#### Scenario 18: ServiceAccountKey.Create — возвращает приватный ключ один раз

**ID:** 2.0-E2-GWT-18
**REQ:** REQ-IAM-E2-SAKEY-01

**Given** alice (USER, role admin на Account) с валидным JWT
**And** существует SA `ci-runner` (sva_ci) в `kacho_iam.service_accounts`

**When** alice вызывает `POST /iam/v1/serviceAccounts/sva_ci/keys:create` с body `{"expirationDays": 365}`

**Then** ответ 202 с Operation → poll → done=true → response.payload содержит JSON:
  ```
  {
    "id": "sak<17chars>",
    "keyId": "<zitadel-internal-key-id>",
    "algorithm": "RSA-2048",
    "createdAt": "2026-05-17T12:00:00Z",
    "expiresAt": "2027-05-17T12:00:00Z",
    "privateKeyPem": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----",
    "publicKeyPem":  "-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----"
  }
  ```
**And** в `kacho_iam.sa_keys` row с `service_account_id='sva_ci'`, `revoked_at=NULL`, `public_pem` совпадает
**And** при повторном `GET /iam/v1/serviceAccounts/sva_ci/keys/sak...` — поле `privateKeyPem` **отсутствует** (только public)
**And** в Zitadel машина-user для sva_ci имеет новый key (`GET /management/v1/users/{sa_user_id}/keys` через PAT возвращает свежий key_id)

#### Scenario 19: JWT-assertion обмен → access_token

**ID:** 2.0-E2-GWT-19
**REQ:** REQ-IAM-E2-SAKEY-02

**Given** SA `ci-runner` с активным key (из GWT-18) — клиент сохранил privateKeyPem

**When** клиент собирает JWT-assertion по RFC 7523:
```
header:  { "alg": "RS256", "kid": "<key_id>", "typ": "JWT" }
payload: {
  "iss":  "<zitadel-machine-user-id-of-sva_ci>",
  "sub":  "<zitadel-machine-user-id-of-sva_ci>",
  "aud":  "https://zitadel.kacho.local",
  "exp":  <now + 60s>,
  "iat":  <now>
}
signature: sign(privateKeyPem, header.payload)
```
**And** клиент POST'ит на `https://zitadel.kacho.local/oauth/v2/token` с body:
```
grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer
&assertion=<signed_jwt_assertion>
&scope=openid profile
```

**Then** Zitadel отвечает 200 с JSON `{"access_token":"<jwt>","token_type":"Bearer","expires_in":900,"scope":"openid profile"}`
**And** клиент использует этот access_token в `Authorization: Bearer` → запросы через api-gateway проходят аутентификацию (GWT-09 happy-path для SA)

#### Scenario 20: Revoked SA key → access_token reject через introspection

**ID:** 2.0-E2-GWT-20
**REQ:** REQ-IAM-E2-SAKEY-03

**Given** SA `ci-runner` с key `sak_old` (active) — клиент получил access_token (GWT-19)

**When** alice вызывает `POST /iam/v1/serviceAccounts/sva_ci/keys/sak_old:revoke`

**Then** в `kacho_iam.sa_keys` row для `sak_old` обновлён: `revoked_at = now()`
**And** в Zitadel key удалён (через `DELETE /management/v1/users/{sa_user_id}/keys/{zitadel_key_id}`)
**And** CAS: повторный revoke того же key → `FailedPrecondition "key already revoked"` (single-statement `UPDATE ... WHERE revoked_at IS NULL`)

**When** клиент пытается использовать уже-выданный access_token (issued ДО revoke)

**Then** случай (a) — access_token уже истёк (>15min) → `Unauthenticated "token expired"`
**And** случай (b) — access_token ещё активен:
  - subject-cache был invalidated через NOTIFY (publisher kacho-iam шлёт event {external_id, op:'sa_revoke'}, listener в api-gateway сбрасывает cache)
  - повторный subject lookup → kacho-iam отдаёт subject как есть (revoke касается key'а, не subject'а)
  - запрос проходит **до экспирации access_token** (Zitadel не пинается на каждый запрос — JWT self-contained)
  - **Защита от long-lived stolen tokens** — короткий TTL JWT (15min) — достаточная mitigation для MVP; cross-check через Zitadel introspection — phase 2.1 (option, NFR trade-off)

> Note для §6 / §8: если SLA требует немедленного revoke даже на in-flight access_token — добавить введение opaque-tokens + introspection-каждый-запрос (стоит лишних 5-10ms на запрос). На фазу 2.0 — outside scope.

---

## 6. Definition of Done (E2 closure)

8 пунктов, каждый верифицируется конкретным GWT или smoke-командой.

| # | DoD                                                                                                                     | GWT verify                       | Smoke / Verification command                                                                                                                       |
|---|--------------------------------------------------------------------------------------------------------------------------|----------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------|
| 1 | `make dev-up` поднимает Zitadel + console доступен через `https://zitadel.kacho.local`                                 | GWT-01, GWT-02                   | `curl -k https://zitadel.kacho.local/.well-known/openid-configuration` → 200 JSON                                                                  |
| 2 | Machine-user `kacho-iam@kacho` создан, PAT в Secret                                                                     | GWT-02                           | `kubectl get secret kacho-iam-zitadel-pat -o jsonpath='{.data.pat}' \| base64 -d \| xargs -I{} curl -H "Authorization: Bearer {}" zitadel.kacho.local/management/v1/users/_search` → 200 |
| 3 | JWT validation в api-gateway работает (mode=production reject without Bearer)                                          | GWT-09, GWT-10, GWT-11, GWT-12   | `grpcurl ... ListUsers` БЕЗ Bearer → `Unauthenticated`; С валидным Bearer → 200                                                                    |
| 4 | `InternalIamService.LookupSubject` отвечает (gRPC-direct, НЕ через restmux)                                            | GWT-13                           | `grpcurl -plaintext kacho-iam:9091 kacho.cloud.iam.v1.InternalIamService/LookupSubject -d '{"byExternalId":"zit-12345"}'` → 200; та же команда через `api.kacho.local:443` → `Unimplemented` (НЕ зарегистрирован) |
| 5 | Principal в Operation реальный (DoD #4 эпика — backend part)                                                            | GWT-15, GWT-16, GWT-17           | `psql -c "SELECT principal_type, principal_id FROM kacho_vpc.operations ORDER BY created_at DESC LIMIT 1"` после vpc create с alice → `user, usr_alice` |
| 6 | `auth_noop` удалён из `kacho-api-gateway`                                                                              | (build-check)                    | `grep -r "auth_noop\|AuthNoop" project/kacho-api-gateway/` — пусто                                                                                  |
| 7 | ServiceAccount key-flow end-to-end работает                                                                             | GWT-18, GWT-19, GWT-20           | Сценарий: создать SA → CreateKey → подписать assertion → exchange → call api-gateway → 200                                                          |
| 8 | `mode = dev` сохраняет anonymous (backwards-compat для всех existing newman-кейсов до их per-case переписывания)        | GWT-17                           | Прогон `tests/newman/cases/vpc-*` БЕЗ JWT при `KACHO_API_GATEWAY_AUTHN__MODE=dev` → все green (parity с pre-E2)                                     |

**NFR (non-functional requirements)**:
- NFR-1: auth-interceptor p95 ≤5ms на cached path (JWKS + subject_cache hit). Метрики `kacho_api_gateway_auth_interceptor_duration_seconds_bucket`.
- NFR-2: subject-cache hit-rate ≥95% в steady-state (UI идёт preloaded JWT, refresh раз в 15min).
- NFR-3: JWKS-cache hit-rate ≥99.9% (cache TTL 30min, refresh-ahead 5min).
- NFR-4: dev-up до Ready всех IAM-pods ≤3min (Zitadel ~90s + post-install bootstrap ~30s + kacho-iam ~30s).

**Тесты в том же PR (запрет #11)**:
- `kacho-iam`:
  - integration: `internal/clients/zitadel_client_integration_test.go` (testcontainers `ghcr.io/zitadel/zitadel:v2`, проверка CreateMachineKey + Revoke + ExchangeJWTAssertion).
  - integration: `internal/repo/kacho/pg/sa_key_integration_test.go` (testcontainers Postgres; CRUD + revoke CAS + UNIQUE).
  - integration: `internal/apps/kacho/api/auth_callback/handler_integration_test.go` (testcontainers Zitadel + Postgres; mock authorization code).
- `kacho-api-gateway`:
  - integration: `internal/middleware/auth_integration_test.go` (testcontainers Zitadel + mock kacho-iam через `testserver`; GWT-09…GWT-12).
  - integration: `internal/cache/subject_cache_test.go` (concurrent goroutines, TTL expiry, invalidate).
  - integration: `internal/jobs/subject_change_listener_integration_test.go` (mock NOTIFY publisher → cache invalidate).
- `kacho-corelib`:
  - unit: `principal/principal_test.go` (WithPrincipal/FromContext/MarshalToMetadata round-trip).
- `tests/newman/cases/`:
  - `iam-auth-no-bearer-dev.py` — mode=dev, no Bearer → 200.
  - `iam-auth-no-bearer-production-strict.py` — mode=production-strict, no Bearer → 401.
  - `iam-auth-expired-jwt.py` — mode=production, expired JWT → 401.
  - `iam-auth-wrong-aud.py`, `iam-auth-wrong-iss.py` — negatives.
  - `iam-auth-callback-happy.py` — full code-exchange happy path (использует ROPC к Zitadel для получения code).
  - `iam-sakey-create-and-exchange.py` — happy SA key-flow.
  - `iam-sakey-revoke.py` — revoke flow.
  - `iam-principal-vpc-create.py` — verify principal_* в operation.
- helper: `tests/newman/_lib/auth.py` (acquire JWT через ROPC к Zitadel testcontainer).

---

## 7. Cross-repo PR-chain (порядок merge)

Топологическая сортировка по graph-зависимостям (workspace `CLAUDE.md` §«Кросс-репо порядок»):

| Step | Repo                  | Branch / KAC                                  | Что включает                                                                                                                  | Depends on                                     |
|------|-----------------------|-----------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------|
| 1    | `kacho-proto`         | `KAC-107-iam-e2-proto`                        | `service_account_key.proto`, `auth.proto` (REST-only callback/refresh/logout), расширение `InternalIamService.ValidateAccessToken` (опц.) | E0 merged (`iam.v1` baseline)                  |
| 2    | `kacho-corelib`       | `KAC-107-iam-e2-principal`                    | `principal/` package + `operations.CreateWithPrincipal` + `grpcsrv/principal_extract.go` interceptor                          | step 1                                         |
| 3    | `kacho-iam`           | `KAC-107-iam-e2-zitadel`                      | `zitadel_client.go` + `auth_callback/handler.go` + `service_account_key/*` + миграция `0002_sa_keys.sql` + bootstrap-job stub | step 2                                         |
| 4    | `kacho-api-gateway`   | `KAC-107-iam-e2-interceptor`                  | `middleware/auth.go` (replaces noop) + `clients/iam_subject_client.go` + `clients/zitadel_jwks_client.go` + `cache/subject_cache.go` + `jobs/subject_change_listener.go` + `middleware/cookie_session.go` + удаление `auth_noop.go` | step 2, step 3                                 |
| 5    | `kacho-deploy`        | `KAC-107-iam-e2-zitadel-bootstrap`            | `post-install/zitadel-bootstrap-job.yaml` (Helm hook) + Secret-templates + ingress TLS cert (self-signed для dev)             | step 3, step 4 (image tags обновляются)        |
| 6    | `kacho-ui`            | `KAC-107-iam-e2-login-redirect`               | Login button → redirect Zitadel; `/auth/callback?code=...` handler → POST на api-gateway; cookie session helpers              | step 4, step 5                                 |
| 7    | `kacho-workspace`     | `KAC-107-iam-e2-docs`                         | этот acceptance-док финализирован; vault: `obsidian/kacho/edges/api-gateway-to-zitadel-jwks.md`, `edges/api-gateway-to-iam-subject-lookup.md`, `edges/iam-to-zitadel-management.md`, `packages/api-gateway-internal-middleware-auth.md`, `resources/iam-service-account-key.md`, `KAC/KAC-107.md` | все steps merged                               |

Parallelism: steps 3 и 4 можно параллелить **после** step 2 — kacho-api-gateway пишет
mock-client против kacho-iam stub-server (gRPC interface уже зафиксирован в step 1
proto'ами). Финальный e2e test требует обе кодовые базы.

`ref:`-пины в CI workflow'ах (`.github/workflows/ci.yaml`): пока step 2 не в main —
step 3/4 пинят `kacho-corelib: ref: KAC-107-iam-e2-principal`. После merge step 2 —
ref → `main`.

---

## 8. Risks & Mitigations

| Risk                                                                                                | Impact      | Mitigation                                                                                                                                              |
|------------------------------------------------------------------------------------------------------|-------------|---------------------------------------------------------------------------------------------------------------------------------------------------------|
| Zitadel chart upgrade ломает helm-values между minor-версиями                                       | High        | Version-pin Zitadel chart (`appVersion: "v2.x.y"` в `Chart.yaml`); регресс newman при каждом bump; upgrade в отдельных PR.                              |
| JWKS-cache stale при rotate Zitadel signing keys                                                    | Medium      | TTL 30min + refresh-ahead 5min + force-refresh on `kid not found in cache` (single retry с inline fetch до отказа).                                    |
| Subject-cache stale при revoke binding (E2 — частично через TTL 30s)                                | Medium      | E2 — TTL 30s worst-case; E3 — NOTIFY-канал даст sub-second invalidate. Acceptable до E3.                                                                |
| Zitadel недоступен на старте api-gateway — pod fails liveness, restart loop                         | High        | Liveness — НЕ зависит от Zitadel; readiness `/healthz/ready` — зависит. Pod стартует в degraded mode, healthz=false до первого JWKS-fetch ok.           |
| Loop в auth-interceptor через REST mux (запрет #6 violation)                                        | High        | `InternalIamService.LookupSubject` строго gRPC-direct (D3 / §3.3); allowlist test проверяет что метод НЕ зарегистрирован в restmux.                    |
| SA private key утечён в логи / metrics labels                                                       | Critical    | `privateKeyPem` помечен в proto-field-options как `(kacho.options.sensitive) = true`; sigtraps на структурный logging (skill evgeniy §G.6 audit-обёртка). |
| Существующие newman-кейсы ломаются при cutover в production-strict                                  | High        | Cutover поэтапный: mode=dev → mode=production → mode=production-strict. Каждый mode-сдвиг в отдельный PR с зелёным CI.                                  |
| Cookie SameSite=Strict ломает OIDC redirect (browser не шлёт cookie на cross-site redirect от Zitadel) | Medium  | `kacho_csrf` non-HttpOnly cookie вшит в state-param; UI добавляет `state` в URL; api-gateway проверяет state-cookie + state-param matched.              |
| Clock skew между Zitadel и api-gateway ломает `exp`/`nbf` валидацию                                 | Low         | JWT validator имеет `leeway = 60s` (standard); NTP-sync в k8s ноды.                                                                                     |

---

## 9. Out of Scope (явно отложено)

| Тема                                                          | Куда вынесено                                                |
|---------------------------------------------------------------|--------------------------------------------------------------|
| OpenFGA `Check`-interceptor + DSL bootstrap                  | E3 (KAC-108)                                                 |
| NOTIFY-publisher (kacho-iam side)                             | E3 (KAC-108) — listener в api-gateway тут, publisher там     |
| Signup-UI / IAM admin block                                   | E4 (KAC-109)                                                 |
| `operations.principal_*` enforcement во всех existing handler-ах (vpc/compute/lb) | E4 (KAC-109) — выкатить `CreateWithPrincipal` повсеместно + удалить deprecated `Create` |
| MFA / WebAuthn / TOTP                                         | Phase 2.1                                                    |
| External identity federation (Google/GitHub/SAML)             | Phase 2.1                                                    |
| Zitadel introspection-на-каждый-запрос (для instant token revoke) | Phase 2.1 (если NFR потребует); MVP — короткий JWT TTL    |
| Prod-grade TLS для Zitadel (cert-manager + Let's Encrypt)     | Phase 3 (production deployment hardening)                    |
| Zitadel multi-org / multi-tenant Zitadel hosting              | Out of scope — Kachō remains single-tenant до Phase 3        |
| Audit storage отдельным сервисом                              | Phase 3 (`kacho-audit`); E4 пишет в no-op `audit.Logger`     |

---

## 10. Связь с регламентом и запретами (повтор для reviewer)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** (acceptance gate) | этот документ DRAFT v1 → `acceptance-reviewer` APPROVED → код |
| **Запрет #2** (no "yandex") | нигде |
| **Запрет #4** (no cross-service cascade) | SA revoke в Zitadel — НЕ каскадит на existing access_tokens (Zitadel sam JWT-issuer); TTL JWT покрывает window |
| **Запрет #6** (Internal vs Public) | LookupSubject — gRPC-direct, НЕ через restmux; UpsertFromIdentity — admin REST mux только; allowlist-test verify |
| **Запрет #8** (DB-per-service) | Zitadel БД `zitadel` отдельная; `kacho_iam.sa_keys` — наша таблица, FK только within-service |
| **Запрет #10** (within-DB refs DB-level) | `sa_keys` FK на `service_accounts` ON DELETE CASCADE; revoke через atomic CAS `UPDATE ... WHERE revoked_at IS NULL` |
| **Запрет #11** (тесты в том же PR) | каждый из 6 PR (proto / corelib / iam / api-gateway / deploy / ui) содержит integration-тест + newman case как минимум |

---

## 11. Open Questions для будущего рассмотрения

Эти вопросы НЕ блокируют E2 APPROVED, но требуют решения до prod deployment:

1. **Refresh-token storage**: куда писать refresh-token в production? E2 — `httpOnly secure Path=/iam/v1/auth/refresh` cookie. Альтернатива — server-side session table в `kacho_iam` (refresh-on-server, client держит только session-cookie). Решить до Phase 3.
2. **Token revocation list (TRL)** на Zitadel side — нужно ли pollить или достаточно introspection? E2 — не используется; phase 2.1 если NFR.
3. **PAT rotation для machine-user `kacho-iam@kacho`** — на dev один статичный, на prod нужен периодический rotate через cron + Vault. Phase 3.
4. **CSRF: SameSite=Strict достаточен** или нужен double-submit token? E2 — double-submit (defense-in-depth); пересмотреть когда UI стабилизируется.
5. **Audience-binding для SA-issued JWT**: SA получает access_token с `aud=zitadel`. Нужно ли отдельный intermediate token-exchange чтобы получить `aud=kacho-api-gateway`? E2 — конфигурируем Zitadel client `kacho-api-gateway` чтобы принимать оба `aud`. Pre-prod re-review.
6. **JWT claim `sub` — uniqueness across Org**: если в будущем добавим multi-Org (за пределами scope), `sub` уникален только внутри Org. Storeit `(org_id, sub)` как external_id. Phase 3.
7. **Anonymous-mode (mode=dev) — финальный cutover** в production-strict: когда именно? Зависит от готовности E4 (UI) — выставлять флаг в одном PR с E4 closure.

---

## 12. Changelog

- **2026-05-17 — v1 (DRAFT)**: первая полная версия документа. Раскрытие из E0-stub'а (5KB → ~50KB). Зафиксированы D1-D13 решений, 20 GWT-сценариев, 8 DoD пунктов, cross-repo PR-chain из 7 шагов, integration-тесты + newman-кейсы в требованиях запрета #11.

---

**Awaiting**: `acceptance-reviewer` ✅ APPROVED → unblock `superpowers:writing-plans` →
`integration-tester` (testcontainers Zitadel + Postgres + mock kacho-iam) →
`rpc-implementer` (Zitadel client + auth interceptor + sa_keys repo) →
`api-gateway-registrar` (новый interceptor в цепочке + cookie middleware + удаление noop) →
`go-style-reviewer` → опционально `security-review` skill → merge sequence §7.
