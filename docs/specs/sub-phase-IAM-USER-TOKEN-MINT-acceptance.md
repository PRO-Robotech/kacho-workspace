# Sub-phase IAM-USER-TOKEN-MINT — cluster-internal per-user token-mint RPC для non-interactive production-seed USER-субъектов

> **⛔ WITHDRAWN / SUPERSEDED (2026-07-22, owner-direction):** этот `InternalUserTokenService.MintUserToken` RPC **НЕ реализован** — owner отверг новый RPC в пользу минимального reuse существующего `UserTokenService.Issue`. Реализовано вместо него (commit `05a2291`, `github.com/PRO-Robotech/kacho@redesign/integration`): acr-exempt #58 bootstrap-SA caller записывает `created_by = target user (self)` + sync `created_by`-валидация (DEFECT-b). **Плюс критическая находка (эмпирически подтверждена live):** per-subject USER-токены (client_credentials ⇒ acr=0) блокируются step-up-гейтом на 372 acr>=2 resource-RPC — только `service_account`-принципал acr-exempt. Т.е. НИ MintUserToken, НИ root-USER-caller не проведут user-субъектные resource-suite'ы в production-strict. Детали — GitHub `PRO-Robotech/kacho#60`/`#59`. Документ оставлен как проектный след (анализ дизайна валиден), но **capability не эта**.
>
> **Статус (историч.):** ✅ APPROVED (`acceptance-reviewer`, 2026-07-22). Правка на review: UTM-04/O-3 текст absent-user приведён к каноническому тону `"User <id> not found"` (capital — `api-conventions.md` `"<Resource> %s not found"` = уже эмитимый `ExistsUser`; меняется только код, не текст). Решения по open-точкам: **O-3 — FAILED_PRECONDITION ПОДТВЕРЖДЁН** (own-DB FK-precondition на `users(id)` → FailedPrecondition — прямой прецедент api-conventions Gotcha «23503 → `FailedPrecondition "User <id> not found"`»; by-lane NOT_FOUND относится к direct-read САМОГО ресурса, а `user_id` здесь — referenced-precondition минта, не fetch-предмет). **O-1 — аргумент «граница доверия идентична #58» ПРИЗНАН SOUND** (кто достигает :9091+mTLS уже минтит `system_admin`-bootstrap #58 ⊇ любой user-токен ⟹ per-user mint строго менее мощен, новой capability через границу доверия не добавляет; #58-отказ от arbitrary-mint касался bootstrap-RPC, чей принципал — фикс. admin, а не existing-user-суржект) — обязателен sign-off `system-design-reviewer` перед merge (паритет с #58 O-1; аудит-атрибуция impersonation — на его усмотрение). **O-4 default ПОДТВЕРЖДЁН** (без discriminator, LEAN; seed-строка видна в user `List`/revoke-able — самолечится идемпотентным re-provision; финал — `db-architect-reviewer`).
> **Дата:** 2026-07-22
> **Ревьюер:** `acceptance-reviewer` → APPROVED
> **Эпик/тикет:** GitHub issue `PRO-Robotech/kacho#60` (первопричина); `KAC-<N>` — завести
> **Тип:** новый cluster-INTERNAL RPC (`kacho.cloud.iam.v1`, :9091, mTLS-gated) + идемпотентный per-user provisioning + hardening-фикс существующего `UserTokenService.Issue` — **не** новый tenant-facing ресурс
> **Repos:** `kacho-proto` (monorepo `proto/`: новый `internal_user_token_service.proto` + regen) · `kacho-iam` (`services/iam`: RPC + provisioning + defect-фикс) · `kacho-api-gateway` (`gateway`: регистрация ТОЛЬКО на internal sub-mux) · `kacho-deploy` (env/helm) · `kacho-workspace` (docs+vault)
> **Формат:** Given-When-Then (только markdown — без кода)
> **Sibling (APPROVED, landed):** `docs/specs/sub-phase-IAM-BOOTSTRAP-TOKEN-acceptance.md` (#58) — прямой предшественник; эта под-фаза переиспользует его exchange-машинерию end-to-end

---

## Обзор

Production-режим authN (`api-gateway authn.mode=production-strict`) принимает **только RS256**
Bearer'ы, подписанные Ory Hydra (issuer-pin = Hydra; gateway верифицирует через iam-JWKS-proxy
:9097; требует `aud=https://{API_DOMAIN}` + RS256). Sibling #58 (`InternalBootstrapTokenService.
MintBootstrapToken`) добавил non-interactive точку входа — чеканит RS256-токен для **единственного**
bootstrap-admin ServiceAccount (cluster `system_admin`, acr-exempt). Это entry-point; но newman
authz-deny suite оперирует **per-USER-субъектами**, а не только SA.

Изначальный план сева USER-токенов был: bootstrap-SA зовёт `UserTokenService.Issue` для каждого
пользователя. Этот путь **сломан by construction**: хендлер `UserTokenService.Issue`
(`services/iam/internal/apps/kacho/api/user_tokens/handler.go`) форсит
`created_by_user_id = аутентифицированный принципал` (через `authzguard.PrincipalUserID(ctx)`).
Когда вызывающий — bootstrap-SA, это возвращает id SA (`sva…`), который **не** является строкой в
`users(id)` → async Issue-Operation натыкается на FK `user_oauth_clients_created_by_fk
(created_by_user_id → users(id))` (SQLSTATE 23503) и завершается `done:true`-Operation с
**непрозрачным** `error` кодом 9 (FailedPrecondition). Non-interactive admin-пути выписать
user-токен **для другого** пользовательского принципала **не существует** — это блокирует весь
production-mode e2e для USER-субъектов (issue #60).

Эта под-фаза:
1. **DELIVERABLE 1** — добавляет **один cluster-INTERNAL RPC** `InternalUserTokenService.MintUserToken`
   на iam-листенере :9091 (граница листенера = gate; mTLS + `<exempt>`, как #58), который
   **идемпотентно провиженит per-user «seed» OAuth-клиент** и чеканит для него **короткоживущий
   RS256-токен через уже существующую машинерию Hydra-обмена #58** — токен, чей принципал =
   `user:<user_id>`. Ключевое отличие от `UserTokenService.Issue`: seed-строка персистится с
   `created_by_user_id = user_id` (self — удовлетворяет FK), поэтому FK-23503-путь исключён.
2. **DELIVERABLE 2 (DEFECT b)** — `UserTokenService.Issue` обязан **синхронно** отвергать невалидный
   `created_by` **до** создания async-Operation, чтобы SA/несуществующий-принципал падал быстро и с
   ясным сообщением, а не непрозрачным async-кодом 9.

Наблюдаемая цель: оператор/CI, имеющий доступ к cluster-internal :9091 (mTLS), одним вызовом
`MintUserToken(user_id)` получает RS256-Bearer, который gateway принимает (`200`) как токен
**этого пользователя**, применяя его собственные binding'и — **без** человеческой browser-церемонии
и **без** HS256-байпаса.

---

## 1. Ground truth (что уже существует — сверено чтением файлов, не переизобретаем)

Вся ES256 `client_assertion` → Hydra `client_credentials` + `private_key_jwt` → RS256-обменная
машинерия **уже реализована** и используется #58 — **переиспользуется целиком**:

- **ES256-подпись assertion** — `services/iam/internal/registrytoken/assertion.go`
  (`SignClientAssertionES256(kid, privateKeyPEM, AssertionClaims{iss=sub=client_id, aud, iat, exp≤60s, jti})`;
  чистый stdlib-crypto ECDSA P-256; JWS R‖S; `NewJTI()` — 128-bit replay-guard).
- **Hydra-обмен** — `services/iam/internal/clients/hydra_token_exchange.go`
  (`HydraTokenClient.ClientCredentials`); **`audience` — параметр запроса** (`form.Set("audience", …)`).
  Fail-closed: сеть/timeout/5xx/malformed-2xx → `ErrHydraUnavailable`; 4xx → `ErrHydraRejected`
  (raw-тело Hydra **никогда** не в ошибке — no auth-oracle).
- **#58 use-case (шаблон для копирования)** — `services/iam/internal/apps/kacho/api/bootstrap_token/`
  {`mint.go`, `iface.go`, `ids.go`, `keys.go`, `handler.go`}. Он: (а) **идемпотентно провиженит** Hydra
  OAuth-клиент под **transaction-scoped advisory-lock** (`BootstrapStore.LockAndGet`) + UNIQUE-backstop —
  winner-only внешний Hydra-create, Hydra `409` (`clients.IsConflict`) = idempotent success (IBT-03);
  (б) выводит **публичный JWK** из **env-held** signing-key (`Config.SigningKeyPEM`, k8s Secret,
  `KACHO_IAM_BOOTSTRAP_SA_PRIVATE_KEY_PEM` — **никогда** не персистится; `keys.go
  publicJWKFromPrivatePEM`); (в) подписывает ES256-assertion этим ключом → Hydra-обмен с
  `aud=GatewayAudience` (`Config.GatewayAudience = https://{API_DOMAIN}`) → RS256-токен; (г) возвращает
  токен **синхронно** (`Result{AccessToken, TokenType, ExpiresIn, ExpiresAt, PrincipalID, IssuedAt}`);
  `clampTTL`/`effectiveExpiresIn` → `[1s, MaxTTL]`, `DefaultTTL=5m`, `MaxTTL=15m`.
- **Token-hook обогащение УЖЕ резолвит user-токен** — `services/iam/internal/service/
  token_enrichment_service.go`, путь **«2b»** (`userTokenClaims`): для `client_credentials` Hydra отдаёт
  `subject == client_id`; `TokenEnrichmentUserTokenPort.LookupByOAuthClientID(client_id)` находит строку
  `user_oauth_clients` → штампует `kacho_principal_type=user`, `kacho_principal_id=<user_id>`,
  `kacho_account_id=<account владельца-User>`. **Изменение enrichment НЕ требуется** — токен, минтованный
  из `user_oauth_clients`-`client_credentials`-клиента, автоматически резолвится в `user:<id>`.
- **`user_oauth_clients` схема** — миграция `0046_user_oauth_clients.sql`: `id ~ '^uoc_[0-9a-hjkmnp-tv-z]{17}$'`
  (PK), `hydra_client_id` UNIQUE + CHECK `^[A-Za-z0-9._:-]+$` (≤128), `user_id → users(id) ON DELETE CASCADE`,
  `created_by_user_id → users(id) ON DELETE RESTRICT`, `key_algorithm IN ('','ES256','RS256','EdDSA')`.
  **N:1** (нет `UNIQUE(user_id)`) — у пользователя может быть много токенов; seed-строка различается своим
  **детерминированным** `id`.
- **Sync user-existence** — `services/iam/internal/repo/kacho/pg/user_existence_checker.go`:
  `UserExistenceChecker.ExistsUser(ctx, userID)` → `SELECT 1 FROM kacho_iam.users` (без row-lock);
  отсутствие → sentinel-wrapped ошибка (текущая обёртка — `iamerr.ErrInvalidArg`, «`User %s not found`»;
  маппинг под этот RPC — см. **O-3**). Пригоден для sync-валидации существования на request-path.
- **Self created_by уже работает** — пользователь, выписывающий **свой** токен, ставит
  `created_by_user_id = user_id` (self); этот случай FK-валиден и работает штатно. MintUserToken строит
  seed-строку по **тому же** self-инварианту.
- **Internal-only маршрутизация + `<exempt>`-gate** — `InternalBootstrapTokenService` зарегистрирован
  **только** на internal sub-mux (`gateway/internal/restmux/mux.go`,
  `RegisterInternalBootstrapTokenServiceHandlerFromEndpoint(…, iamInternalAddr, …)`); `isInternalPath`
  шлёт `/iam/v1/internal/*` на internal-листенер, gRPC-router `HasInternalSuffix` **блокирует**
  `Internal…Service` на публичном (404). Route-table + `permission_catalog.json` регистрируют FQN с
  `permission="<exempt>"`. MintUserToken следует **тем же** путём регистрации.

**Наблюдаемая цель:** оператор с mTLS-доступом к :9091 вызывает `MintUserToken(user_id)` для
существующего пользователя → получает RS256-Bearer; gateway принимает его как `user:<user_id>`,
и применяются собственные binding'и этого пользователя.

---

## 2. Scope / Non-goals

### In scope
1. **kacho-proto (monorepo `proto/`):** новый `proto/kacho/cloud/iam/v1/internal_user_token_service.proto`
   (пакет `kacho.cloud.iam.v1`): сервис `InternalUserTokenService`, RPC `MintUserToken` (**sync**, не
   Operation), `permission = "<exempt>"`; regen `pkg/api/…`, buf lint/breaking/validate зелёные.
2. **kacho-iam (`services/iam`):** реализация RPC на :9091; идемпотентный provisioning **per-user seed
   OAuth-клиента** (детерминированный `uoc_…` id + advisory-lock keyed per user_id + UNIQUE-backstop) с
   `created_by_user_id = user_id`; sync-валидация формата+существования `user_id`; ES256-assertion (env
   bootstrap signing key #58) → Hydra-обмен `aud=https://{API_DOMAIN}` → RS256-токен.
3. **DEFECT (b):** `UserTokenService.Issue` (и parity `SAKeyService.Issue`) — sync-reject невалидного
   `created_by` **до** создания async-Operation.
4. **kacho-api-gateway (`gateway`):** регистрация `InternalUserTokenService` **только** на internal
   sub-mux (`iamInternalAddr`); route-table + permission-catalog regen; суффикс в `HasInternalSuffix`.
5. **kacho-deploy:** переиспользование env #58 (`API_DOMAIN`/аудитория, Hydra-token-URL, bootstrap
   signing key Secret) — новых секретов не вводит.
6. Тесты (TDD, тот же PR): integration (testcontainers) — provisioning/идемпотентность/concurrency-инвариант;
   unit use-case (Hydra-обмен замокан) — malformed/unknown/ttl-clamp/hydra-down; regression-lock DEFECT (b).

### Non-goals (явно вне scope)
- **Переработка 7 newman-seed'ов** на потребление этого RPC — отдельная **Phase C** follow-up (тикет-ссылка
  при заведении). Здесь — только RPC + provisioning + defect-фикс + их тесты.
- **Смена enrichment / issuer / HS256 dev-bypass.** Token-hook (`userTokenClaims` путь 2b) **не меняется** —
  он уже резолвит seed-клиент в `user:<id>`. Hydra остаётся эмитентом/подписантом (iam только брокерит
  обмен). HS256 dev-fixture остаётся как есть; anon/HS256 против production по-прежнему `401/403`
  (UTM-11, **не меняется**).
- **Mint для несуществующего/произвольного принципала.** RPC минтит **только** для **существующего**
  `usr…`-пользователя (sync existence-check, UTM-04); фабрикация произвольных принципалов невозможна.
- **Полный e2e-conformance-suite** (gateway принимает user-Bearer; anon/HS256→403) — Phase C (issue #60);
  здесь зафиксирован как traceability-обязательство (UTM-06/07/11), а не реализуется в этом PR.
- **acr-step-up-байпас для user-токена.** Минтованный USER-токен несёт `kacho_acr` сессии
  `client_credentials` (≈`"0"`); он экзерсайзит нормальные (не-step-up) binding'и пользователя, но **не**
  байпасит step-up для acr-gated RPC (`Issue`/rotate) — это **корректно** (bounded impersonation, §5.4).

---

## 3. Naming (предлагаемые контракты — фиксируются в этом acceptance)

### DELIVERABLE 1 — `InternalUserTokenService`

| Артефакт | Значение |
|---|---|
| proto-файл | `proto/kacho/cloud/iam/v1/internal_user_token_service.proto` |
| package | `kacho.cloud.iam.v1` |
| service | `InternalUserTokenService` (Internal-only, :9091) |
| RPC | `rpc MintUserToken (MintUserTokenRequest) returns (MintUserTokenResponse)` — **sync** |
| permission | `option (kacho.iam.authz.v1.permission) = "<exempt>"` (листенер = gate; НЕ `required_relation`/`scope_extractor`) |
| REST (только internal sub-mux) | `POST /iam/v1/internal/users/{user_id}/token:mint` (`body: "*"`; `user_id` из path) |
| request-поля | `string user_id = 1` (**required**, prefix `usr`; из path-параметра); `int64 ttl_seconds = 2 [(value) = ">=0"]` (опц.; `0` → серверный дефолт; клампится к hard-max, UTM-10) |
| response-поля (camelCase) | `accessToken` (RS256 JWT), `tokenType` (`"Bearer"`), `expiresIn` (сек, ≤ hard-max), `expiresAt` (Timestamp, truncate до секунд), `principalId` (= `user_id`, который токен аутентифицирует), `issuedAt` (Timestamp, truncate до секунд) |

Провиженинг seed-клиента (детерминированные значения, по образцу #58 `ids.go`):

| Артефакт | Значение |
|---|---|
| seed uoc id | `uoc_` + `substr(md5("kacho-seed-usr" ‖ user_id), 1, 17)` — детерминированный per-user (PK-singleton) |
| Hydra `client_id` | `kacho-seed-usr-<user_id>` (детерминированный, читаемый; ⊂ `^[A-Za-z0-9._:-]+$`) |
| Hydra `owner` | `<user_id>` |
| grant_types | `[client_credentials]`; token_endpoint_auth_method `private_key_jwt`; signing_alg `ES256` |
| JWKS | публичный JWK из **того же** env bootstrap signing key (#58 `Config.SigningKeyPEM`) |
| audience (whitelist + request) | `[https://{API_DOMAIN}]` (`GatewayAudience`) |
| `created_by_user_id` строки | `= user_id` (**self** — удовлетворяет FK `user_oauth_clients_created_by_fk`) |

### DELIVERABLE 2 — DEFECT (b) сообщения (тон — часть контракта, `api-conventions.md`)

| Условие | Код | Сообщение |
|---|---|---|
| `created_by_user_id` prefix ≠ `usr` (напр. `sva…`) | `INVALID_ARGUMENT` | `"created_by_user_id must be a user principal"` |
| `created_by_user_id` well-formed `usr…`, но не known user | `FAILED_PRECONDITION` | `"created_by_user_id <id> is not a known user"` |

Стандартные конвенции (`api-conventions.md`, `security.md`, `data-integrity.md`) — нормативны
по ссылке, в тело не дублируются.

---

## 4. Дизайн-решения (для ревьюера — обоснование отклонений и выборов)

### D-1. Переиспользование #58 exchange-машинерии end-to-end — НЕ переизобретаем
`MintUserToken` использует **ту же** цепочку, что `MintBootstrapToken`: `registrytoken.
SignClientAssertionES256` (ES256-assertion) → `TokenExchanger.Exchange` (обёртка над
`HydraTokenClient.ClientCredentials`, `aud=https://{API_DOMAIN}`) → RS256-токен; тот же env-held signing
key (`KACHO_IAM_BOOTSTRAP_SA_PRIVATE_KEY_PEM`, **никогда** не персистится), тот же
`publicJWKFromPrivatePEM` для деривации публичного JWK. Единственная новизна — **per-user** seed-клиент
(другой `client_id`/`owner`/строка) вместо singleton bootstrap-SA. Общий signing key для всех seed-клиентов
корректен: Hydra верифицирует assertion против JWKS **этого** `client_id` (assertion `iss=sub=client_id`
дискриминирует), а публичный ключ у всех seed-клиентов один и тот же — по дизайну.

### D-2. **Sync request/response, НЕ `Operation`** — declared-исключение из «мутации→Operation»
`MintUserToken` возвращает `MintUserTokenResponse` **синхронно**, не `operation.Operation` — **тот же
declared-deviation D-2, что #58** (осознанное отклонение от non-negotiable #9). Обоснование: минт токена —
**derivation, read-shaped** (короткий round-trip к Hydra → `{accessToken, expiresIn}`), как token-hooks и
registry-шим; единственная **durable** часть — идемпотентный provisioning seed-клиента, он **не** предмет
токен-минта и safe к повтору (D-3). Оборачивать sync-derivation в async `Operation` (клиент поллил бы
`Operation.Get` ради строки, которую и так получает синхронно) — лишний round-trip без durability-выигрыша.
Токен возвращается **в теле ответа**, не в `Operation.response`. (Заметь: **`UserTokenService.Issue`
остаётся async `Operation`** — он генерит durable долгоживущий credential с приватным ключом; это другой
класс. `MintUserToken` не генерит новый credential-per-call — он переиспользует один seed-клиент и брокерит
короткоживущий access-токен.)

### D-3. Идемпотентный per-user provisioning + DB-инвариант «≤ один seed-клиент на user»
Первый вызов для `user_id` провиженит (если отсутствует): seed OAuth-клиент в Hydra
(`client_credentials`/`private_key_jwt`, JWKS = публичный JWK env-ключа) + строку `user_oauth_clients` с
**детерминированным** `id` (`uoc_<md5(seed‖user_id)>`) и `created_by_user_id = user_id`. Последующие вызовы
**переиспользуют** существующую строку/клиент. Инвариант «≤ один seed на user» — **DB-уровневый**
(`data-integrity.md` ban #10, не software check-then-act): детерминированный `id` = **PK** → второй INSERT
той же строки = PK-коллизия = невозможен by construction; **transaction-scoped advisory-lock keyed per
user_id** (`pg_advisory_xact_lock`, освобождается на commit/rollback) сериализует конкурентные первые-вызовы
→ **winner-only** внешний Hydra-create; `UNIQUE(hydra_client_id)` + Hydra `409`=idempotent — backstop.
Порядок: выиграть DB-singleton (advisory-lock + PK) → **только** победитель создаёт Hydra-клиента →
проигравшие переиспользуют (IBT-03-паттерн #58). Идемпотентность делает production-newman-seed
**re-run-safe**. **Миграция не требуется** (seed-строка живёт в существующей `user_oauth_clients` 0046;
per-user singleton — детерминированным PK; discriminator-колонка не нужна — см. **O-4**).

### D-4. Граница листенера = gate (`<exempt>` + mTLS), Internal-only
RPC несёт `permission="<exempt>"` (как #58 и прочие :9091-hooks): per-RPC FGA-Check байпасится, **потому что
доступ уже ограничен транспортом** — mTLS-verified cluster-internal :9091, недостижимый с external endpoint
(ban #6). AuthN (mTLS) остаётся **обязательным** (не «internal = trusted»); non-mTLS → reject на транспорте
(UTM-08). Регистрация **только** на internal sub-mux (UTM-07).

### D-5. Impersonation-for-seed приемлем — граница доверия **идентична** уже-принятому #58
В отличие от #58 (минтил для **ровно одного** фиксированного bootstrap-принципала и явно отверг
«mint-for-any-principal» skeleton-key), `MintUserToken` минтит для **любого заданного СУЩЕСТВУЮЩЕГО**
`user_id` — это **admin-impersonation-for-seed** capability. Она приемлема и **не** является
privilege-escalation, потому что **граница доверия та же**, что у уже-принятого bootstrap-mint: кто может
достичь :9091 по mTLS, тот **уже** может сминтить cluster-`system_admin` bootstrap-токен (#58) и тем самым
**уже** эффективно контролирует кластер. `MintUserToken` **не открывает никакой новой capability** актору с
меньшими привилегиями через границу доверия — он лишь предлагает **более узкую**, per-user идентичность для
сева, гейтированную **тем же самым** периметром (:9091 + mTLS). Полное обоснование — §5.

### D-6. DEFECT (b) — sync-reject невалидного `created_by` до async-Operation
`UserTokenService.Issue.Execute` сегодня валидирует `UserID` (prefix `usr`), но `CreatedByUserID` проверяет
**лишь на непустоту** (`user_tokens/usecases.go`, нет prefix/existence-check) → `sva…`-принципал проходит →
async-op → FK-23503 → непрозрачный `done:true`+`error` код 9. Фикс: sync-валидация `created_by_user_id`
**до** `operations.NewFromContext`/`opsRepo.Create` (**никакой async-op не создаётся**): prefix ≠ `usr` →
`INVALID_ARGUMENT`; well-formed `usr…` но не known user (`ExistsUser`) → `FAILED_PRECONDITION`. `SAKeyService.
Issue` несёт **идентичный** паттерн (`CreatedByUserID: principal`, `sa_keys/handler.go`) → **тот же**
латентный дефект; применить **тот же** sync-guard как parity-фикс (primary — user_tokens). Регресс-lock
ассертит код+сообщение **и** что async-op не создан.

---

## Сценарии

> ID трассируются в имена integration/unit/e2e-тестов. `{API_DOMAIN}` = публичный домен gateway
> (аудитория production-authN). `:9091` = cluster-internal iam-листенер (mTLS). `U` = существующий
> `usr…`-пользователь.

### Сценарий UTM-01: Happy path — первый вызов провиженит seed-клиент и чеканит user-токен

**ID:** `UTM-01`

**Given** production-mode стенд: gateway `authn.mode=production-strict`, iam-JWKS-proxy :9097 отдаёт
Hydra-kids, Hydra доступна
**And** существует пользователь `U` (`usr…`), его seed OAuth-клиент ещё **не** провижен
**And** вызывающий имеет валидный клиентский mTLS-сертификат для :9091

**When** клиент вызывает `InternalUserTokenService.MintUserToken` по :9091 (mTLS) с payload:
  - `userId` = `U`
  - `ttlSeconds` = 0 (серверный дефолт)

**Then** ответ `200` — синхронный `MintUserTokenResponse` (НЕ `Operation`)
**And** iam идемпотентно создал: seed OAuth-клиент в Hydra (`client_id=kacho-seed-usr-<U>`,
`client_credentials`/`private_key_jwt`, `owner=U`, JWKS = публичный JWK env-ключа) + строку
`user_oauth_clients` с детерминированным `id=uoc_<md5(seed‖U)>` и **`created_by_user_id = U`** (self)
**And** `accessToken` — непустой **RS256** JWT (header `alg=RS256`, Hydra-`kid`)
**And** `tokenType` = `"Bearer"`, `expiresIn` > 0, `expiresAt`/`issuedAt` заполнены (truncate до секунд),
`principalId` == `U`
**And** декодированный `accessToken` несёт `kacho_principal_type=user`, `kacho_principal_id` == `U`,
`kacho_account_id` == account владельца-`U`, `aud` включает `https://{API_DOMAIN}`, `iss` = Hydra-issuer
**And** FK `user_oauth_clients_created_by_fk` **не** нарушен (created_by=U — валидный `users(id)`) — путь
23503, ломавший SA-caller, исключён by construction

> Уровень: integration (testcontainers + fake/mock Hydra-exchange) + unit (enrichment path 2b).

---

### Сценарий UTM-02: Идемпотентность — повторный вызов переиспользует seed-клиент

**ID:** `UTM-02`

**Given** seed-клиент пользователя `U` **уже** провижен предыдущим вызовом (UTM-01)

**When** клиент повторно вызывает `MintUserToken` с `userId=U` по :9091 (mTLS)

**Then** ответ `200`; `principalId` == `U`
**And** новая строка `user_oauth_clients` **не** создаётся (детерминированный `id` уже есть — reuse);
новый Hydra OAuth-клиент **не** создаётся (переиспользуется существующий)
**And** возвращается **свежий** `accessToken` для того же принципала (новый `exp`/`iat`)
**And** в БД по-прежнему **ровно одна** seed-строка для `U` (инвариант, ср. UTM-03)

> Уровень: integration.

---

### Сценарий UTM-03: Concurrency — конкурентные первые-вызовы для одного user → ровно один seed

**ID:** `UTM-03`

**Given** fresh стенд, существует `U`, seed-клиент `U` не провижен

**When** `N` конкурентных горутин одновременно вызывают `MintUserToken(userId=U)` (первый provisioning-путь)

**Then** **ровно одна** транзакция создаёт seed-строку `U`; остальные видят/переиспользуют её (DB-инвариант:
детерминированный PK + transaction-scoped advisory-lock keyed per `user_id` — `data-integrity.md` §чек-лист
п.5, не software check-then-act)
**And** внешний Hydra OAuth-клиент seed'а провижится **не более одного раза** под конкуренцией: провижн-порядок —
сначала выиграть DB-singleton (advisory-lock + PK), и **только** победитель создаёт Hydra-клиента; проигравшие
переиспользуют; `UNIQUE(hydra_client_id)` + Hydra `409` — backstop (нет orphan/дубль-Hydra-клиента)
**And** все `N` ответов несут **один и тот же** `principalId` == `U`
**And** в БД — ровно одна seed-строка для `U` (нет дублей, нет constraint-INTERNAL-leak)

> Проверяется integration-тестом с concurrent goroutines (`data-integrity.md` §чек-лист п.5;
> `system-design-reviewer`: cross-boundary side-effect за durable-CAS).

---

### Сценарий UTM-04: Несуществующий user — well-formed id, но строки нет → sync `FAILED_PRECONDITION`

**ID:** `UTM-04`

**Given** валидный mTLS-вызов на :9091
**And** `userId` = well-formed `usr…`, но такого пользователя в `kacho_iam.users` **нет**

**When** клиент вызывает `MintUserToken(userId=<absent usr…>)`

**Then** **синхронный** `FAILED_PRECONDITION` (gRPC 9) с фикс. сообщением `"User <id> not found"` —
**НЕТ** async-Operation, **НЕТ** provisioning, **НЕТ** FK-23503-leak (existence проверяется `ExistsUser`
**до** любой мутации/Hydra-вызова)
**And** raw pgx/SQL-текст наружу не течёт (`security.md` #1); тон сообщения — фикс. контракт

> Уровень: integration/unit. Код FAILED_PRECONDITION выбран сознательно — см. **O-3** (by-lane-конвенция
> предполагала бы NOT_FOUND для own-owned id; здесь user_id — precondition минта, не fetch-предмет; код
> совпадает с тем, что async-FK-путь #60 уже возвращал (9), делая sync-fast-fail drop-in-совместимым).

---

### Сценарий UTM-05: Malformed user id — prefix ≠ `usr` → sync `INVALID_ARGUMENT` первым стейтментом

**ID:** `UTM-05`

**Given** валидный mTLS-вызов на :9091

**When** клиент вызывает `MintUserToken` с `userId` невалидного формата (пустой, `sva…`, `garbage`,
прочий-prefix)

**Then** **синхронный** `INVALID_ARGUMENT` (gRPC 3) `"invalid user id '<X>'"` — **первым стейтментом** RPC,
**до** `ExistsUser`/provisioning/Hydra (`api-conventions.md` malformed-id-first)
**And** async-Operation не создаётся; никакого repo/Hydra-вызова

> Уровень: unit (request-схема / use-case format-check).

---

### Сценарий UTM-06: Токен принимается gateway как user-Bearer (RS256 через :9097 JWKS) — не 401/403

**ID:** `UTM-06`

**Given** `accessToken` получен из `MintUserToken(userId=U)` (UTM-01)
**And** gateway верифицирует подпись через iam-JWKS-proxy :9097 (Hydra-kids)
**And** у `U` есть binding'и (напр. editor на своём проекте)

**When** клиент делает gateway-API-вызов на **external** endpoint с `Authorization: Bearer <accessToken>`
на ресурс, доступный `U` (напр. `GET`/`List` в его проекте)

**Then** gateway верифицирует токен (RS256, `iss`=Hydra, `aud=https://{API_DOMAIN}`) и пропускает — ответ
`200` (**НЕ** `401 invalid_token`, **НЕ** `403 permission denied`)
**And** authZ применяет **собственные binding'и `U`** (принципал = `user:U` — enrichment path 2b): доступное
`U` разрешено, недоступное `U` — `403` (токен действует **как этот пользователь**, не как admin)

> Уровень: e2e-conformance (**Phase C** follow-up). Экзерсайзятся **нормальные** (не-step-up) binding'и;
> acr-gated RPC как `U` — вне scope (§5.4 / §2 non-goal).

---

### Сценарий UTM-07: Internal-only — RPC не роутится на external endpoint (ban #6)

**ID:** `UTM-07`

**Given** production-стенд; `InternalUserTokenService` зарегистрирован **только** на internal sub-mux

**When** клиент обращается к `POST /iam/v1/internal/users/{user_id}/token:mint` на **external** TLS
endpoint (`api.{API_DOMAIN}:443`)

**Then** запрос **не** маршрутизируется на хендлер — `404 Not Found` (dispatcher/`HasInternalSuffix`
блокирует `Internal…Service` на публичном листенере)
**And** RPC достижим **только** через cluster-internal :9091 / internal sub-mux (port-forward/admin-tooling)

> Уровень: e2e/gateway-routing (**Phase C**).

---

### Сценарий UTM-08: Non-mTLS вызывающий на :9091 → отклонён

**ID:** `UTM-08`

**Given** production-стенд, :9091 требует verified client-cert (mTLS)

**When** клиент вызывает `MintUserToken` по :9091 **без** валидного клиентского сертификата
(plaintext/insecure или неверный SAN)

**Then** соединение/запрос отклоняется на транспорте (TLS handshake fail либо `UNAVAILABLE`/
`UNAUTHENTICATED`) — токен **не** выдаётся
**And** «internal = trusted, mTLS не нужен» — недопустимо (`security.md` §authN-везде); хендлер недостижим
без mTLS

> Уровень: integration/transport.

---

### Сценарий UTM-09: Hydra недоступна → fail-closed `UNAVAILABLE`, без leak'а

**ID:** `UTM-09`

**Given** валидный mTLS-вызов на :9091 для существующего `U`, но Hydra token-endpoint недоступен
(сеть/timeout/5xx/malformed-2xx)

**When** клиент вызывает `MintUserToken(userId=U)`

**Then** ответ `UNAVAILABLE` (gRPC 14) — **fail-closed**: токен НЕ выдаётся, open-fail недопустим
(`hydra_token_exchange.go` → `ErrHydraUnavailable`; тон сообщения фиксированный, raw-тело Hydra **не**
протекает — no auth-oracle, `security.md` hardening-инвариант #1)
**And** provisioning seed-клиента, выполненный ДО обмена (если это был первый вызов), остаётся идемпотентно
переиспользуемым при retry (не создаёт дубль-строку/клиент — UTM-02/UTM-03)

> Уровень: unit use-case (Hydra-exchange mock → `ErrHydraUnavailable`).

---

### Сценарий UTM-10: Короткоживущий токен — bounded TTL clamp

**ID:** `UTM-10`

**Given** валидный mTLS-вызов на :9091 для существующего `U`

**When** клиент вызывает `MintUserToken` с `ttlSeconds` = очень большим значением (напр. `86400`)

**Then** выданный `accessToken` — **короткоживущий**: `expiresIn` ≤ серверный hard-max (seed-токен намеренно
кратко-живущий; запрошенный TTL **клампится**, не превышается) — `effectiveExpiresIn = min(clamped-request,
hydra-lifespan, MaxTTL)`
**And** `expiresAt - issuedAt` == `expiresIn` (в пределах truncate-до-секунд) и ≤ hard-max
**And** `ttlSeconds` = 0 → применяется серверный дефолт (тоже ≤ hard-max)

> Уровень: unit use-case (injected clock).

---

### Сценарий UTM-11: Anonymous / HS256 против production по-прежнему отвергаются (регресс-lock, не меняется)

**ID:** `UTM-11`

**Given** production-mode gateway (`authn.mode=production-strict`)

**When** клиент делает gateway-API-вызов (а) без токена, либо (б) с **HS256**-forged dev-secret JWT

**Then** (а) `401 UNAUTHENTICATED`; (б) `401 invalid_token`/`403` — HS256 отвергается (RS256-only, CWE-347) —
поведение **не изменено** этой под-фазой
**And** ТОЛЬКО RS256-токен из `MintUserToken` (или реальной Hydra-выдачи) принимается (UTM-06) — seed-путь
**не** ослабляет production-authN

> Уровень: e2e-conformance (**Phase C**).

---

### Сценарий UTM-12: DEFECT (b) — невалидный `created_by` на `UserTokenService.Issue` → sync-reject, не async код 9

**ID:** `UTM-12`

**Given** аутентифицированный вызов `UserTokenService.Issue` (публичный RPC), где принципал-caller
резолвится в `created_by_user_id`

**When** (а) вызывающий — **ServiceAccount** (`created_by_user_id` = `sva…`, как bootstrap-SA);
**When** (б) `created_by_user_id` = well-formed `usr…`, но такого пользователя **нет**

**Then** (а) **синхронный** `INVALID_ARGUMENT` (gRPC 3) `"created_by_user_id must be a user principal"` —
**НЕ** async `Operation` с непрозрачным кодом 9; async-Operation **не создаётся**
**And** (б) **синхронный** `FAILED_PRECONDITION` (gRPC 9) `"created_by_user_id <id> is not a known user"`
(проверка `ExistsUser` до `opsRepo.Create`); async-Operation **не создаётся**
**And** валидация происходит **до** `operations.NewFromContext`/`opsRepo.Create` — ни строки `operations`,
ни FK-23503-leak
**And** регресс-lock ассертит **код И сообщение И** отсутствие созданной async-op (behaviour-level,
`testing.md`)
**And** **parity:** `SAKeyService.Issue` несёт идентичный паттерн → тот же sync-guard; regression-lock и на нём

> Уровень: unit (handler/use-case, fake-порты) + integration (assert нет строки `operations` + нет
> `user_oauth_clients`-строки при SA-caller).

---

### Traceability-note UTM-Tenrich: token-hook path 2b резолвит seed-клиент в `user:<id>` (enrichment НЕ меняется)

**ID:** `UTM-Tenrich`

**Given** токен, минтованный `MintUserToken` из seed `client_credentials`-клиента `kacho-seed-usr-<U>`

**When** Hydra зовёт token-hook (`subject == client_id`)

**Then** `TokenEnrichmentService` путь **2b** (`userTokenClaims`): `LookupByOAuthClientID(client_id)` →
seed-строка `user_oauth_clients` → `kacho_principal_type=user`, `kacho_principal_id=U`, `kacho_account_id`
**And** изменение enrichment-кода **не требуется** — покрыто существующими unit-тестами обогащения; добавить
assertion, что seed-`client_id` резолвится в `user:<U>`

> Уровень: unit (`token_enrichment_service`).

---

## 5. Security-раздел (почему per-user impersonation-mint на :9091 приемлем — head-on)

`MintUserToken` минтит токен, аутентифицирующийся **как произвольный существующий пользователь** — это
чувствительнее #58 (который минтил для одного фиксированного bootstrap-SA). Раздел обосновывает, почему это
**приемлемо и НЕ является privilege-escalation** (defense-in-depth, `security.md`):

1. **Граница доверия ИДЕНТИЧНА уже-принятому #58 — нет новой capability через границу.** RPC достижим
   **только** на cluster-internal :9091 / internal sub-mux (ban #6, UTM-07: dispatcher 404 на external) и
   **только** по mTLS (verified client-cert, UTM-08). Любой актор, способный достичь :9091 с mTLS, **уже**
   может вызвать `MintBootstrapToken` (#58) и получить cluster-`system_admin` bootstrap-токен — т.е. **уже**
   эффективно контролирует кластер. Следовательно `MintUserToken` **не открывает никакой новой capability**
   актору с меньшими привилегиями: он не расширяет privilege через границу доверия, а лишь предлагает
   **более узкую**, per-user идентичность для сева, гейтированную **тем же** периметром. (`system_admin`
   bootstrap-токен ⊇ любой user-токен по правам — per-user mint строго **менее** мощен, чем уже-доступный
   admin-mint.)
2. **mTLS обязателен; `<exempt>` не байпасит authN.** `<exempt>` снимает лишь per-RPC FGA-Check (потому что
   транспорт уже ограничивает доступ), **не** транспортный authN — «internal = trusted» запрещено
   (`security.md` §authN-везде). Non-mTLS → reject (UTM-08).
3. **Только СУЩЕСТВУЮЩИЙ пользователь — фабрикация принципала невозможна.** Sync existence-check
   (`ExistsUser`, UTM-04) → нельзя выписать токен для несуществующего/произвольного субъекта; `user_id`
   валидируется по формату (UTM-05) и существованию до любого provisioning/Hydra-вызова.
4. **Bounded impersonation — токен не всесилен.** Минтованный USER-токен несёт `kacho_acr` сессии
   `client_credentials` (≈`"0"`) и применяет **собственные binding'и** пользователя (UTM-06), **не** admin.
   Он экзерсайзит нормальные (не-step-up) операции пользователя, но **не** байпасит step-up для acr-gated
   RPC (`Issue`/rotate) — это **корректно**: seed-токен не должен обходить step-up для чувствительных
   операций. Impersonation ограничена не-step-up-поверхностью **by construction**.
5. **Короткий TTL** — токен намеренно кратко-живущий, TTL клампится к hard-max (UTM-10); окно
   злоупотребления ограничено.
6. **Инфра-нейтрально** — ответ несёт только `accessToken`/`expiry`/`principalId`; ни placement/underlay/
   инфра-идентификаторов (`security.md` инфра-чувствительные данные не применимы — это identity-токен).
7. **No auth-oracle / no leak** — Hydra-недоступность → фикс. `UNAVAILABLE`, raw-тело Hydra не протекает
   (UTM-09); INTERNAL никогда не эхает `err.Error()` (`security.md` #1); отсутствие пользователя → фикс.
   сообщение (UTM-04), не existence-oracle с pgx-текстом.
8. **Не ослабляет production-authN** — anon/HS256 по-прежнему `401/403` (UTM-11); добавляется лишь
   легитимный RS256-путь через существующий Hydra-обмен.

**Обязательная верификация:** рассуждение о impersonation-границе (пп. 1/4) — **открытая точка O-1**,
требует sign-off `system-design-reviewer` (паритет с #58 O-1), + `proto-api-reviewer` (proto) +
`db-architect-reviewer` (per-user singleton / advisory-lock / FK).

---

## 6. Traceability (сценарий → тест)

| ID | Проверяемое | Уровень теста | Тест-идентификатор |
|---|---|---|---|
| UTM-01 | happy-path provisioning + RS256 user-токен + created_by=user_id + user-claims | integration (testcontainers + mock Hydra-exchange) + unit | `TestMintUserToken_FirstCall_ProvisionsAndMints` |
| UTM-02 | идемпотентный reuse seed-клиента (тот же `principalId`, свежий токен) | integration | `TestMintUserToken_Idempotent_ReusesSeedClient` |
| UTM-03 | concurrency → ровно один seed на user (DB-инвариант, winner-only Hydra) | integration, concurrent goroutines | `TestMintUserToken_Concurrent_SingleSeedPerUser` |
| UTM-04 | unknown user → sync FAILED_PRECONDITION, no-async, no-FK-leak | integration/unit | `TestMintUserToken_UnknownUser_FailedPrecondition` |
| UTM-05 | malformed user id → sync INVALID_ARGUMENT первым стейтментом | unit | `TestMintUserToken_MalformedUserID_InvalidArgument` |
| UTM-06 | gateway принимает user-Bearer (200, не 401/403), собственные binding'и | e2e-conformance (Phase C) | `UTM-06::usertoken-accepted-as-user` (Phase C) |
| UTM-07 | Internal-only: external → 404 | e2e/gateway-routing (Phase C) | `UTM-07::not-on-external` (Phase C) |
| UTM-08 | non-mTLS → reject | integration/transport | `TestMintUserToken_NonMTLS_Rejected` |
| UTM-09 | Hydra down → fail-closed UNAVAILABLE, no-leak | unit use-case (exchange mock → ErrHydraUnavailable) | `TestMintUserToken_HydraUnavailable_FailClosed` |
| UTM-10 | bounded TTL (clamp) | unit use-case (injected clock) | `TestMintUserToken_TTLClampedToMax` |
| UTM-11 | anon/HS256 по-прежнему 401/403 (регресс-lock) | e2e-conformance (Phase C) | `UTM-11::hs256-still-rejected` (Phase C) |
| UTM-12 | DEFECT(b): SA/unknown created_by → sync reject, no-async-op | unit (fake-порты) + integration (нет op-строки) | `TestUserTokenIssue_InvalidCreatedBy_SyncReject` · `TestSAKeyIssue_InvalidCreatedBy_SyncReject` |
| UTM-Tenrich | token-hook 2b: seed-client → `user:<id>` (enrichment не меняется) | unit (`token_enrichment_service`) | `TestEnrichClaims_SeedUserTokenClient_UserPrincipal` |

> Уровни «Phase C» — e2e-conformance против задеплоенного стенда (issue #60): пишутся в follow-up-под-фазе
> потребления seed'ом; здесь фиксируются как traceability-обязательство. RED→GREEN для integration/unit —
> **в том же PR** (ban #12).

---

## 7. Definition of Done (этой под-фазы)

- [ ] `internal_user_token_service.proto` в `kacho-proto` (monorepo `proto/`) + regen; `buf lint`/`breaking`/`validate` зелёные (`proto-api-reviewer`).
- [ ] Реализация RPC (sync), use-case + порты (Hydra-exchange + BootstrapStore-подобный per-user store за портами); переиспользует #58 `SignClientAssertionES256`/`TokenExchanger`/env signing key; `permission="<exempt>"`; на :9091.
- [ ] Идемпотентный per-user provisioning: детерминированный `uoc_…` id (PK-singleton per user) + advisory-lock keyed per `user_id` (winner-only Hydra-create) + `UNIQUE(hydra_client_id)`-backstop; `created_by_user_id=user_id`. **Миграция не требуется** (reuse 0046) — подтвердить `db-architect-reviewer` (или additive-миграция, если O-4 требует discriminator).
- [ ] DEFECT (b): `UserTokenService.Issue` **и** `SAKeyService.Issue` — sync-reject невалидного `created_by` до `opsRepo.Create` (код+сообщение по §3-таблице); async-op не создаётся.
- [ ] `kacho-api-gateway`: регистрация `InternalUserTokenService` **только** на internal sub-mux; route-table + permission-catalog regen (обе embedded-копии byte-identical, `make permission-catalog-check`); суффикс в `HasInternalSuffix` (404 на external).
- [ ] Тесты: integration UTM-01/02/03/04/08 (testcontainers, concurrent-race для инварианта) + unit UTM-05/09/10/12 + UTM-Tenrich (mock-порты). **RED→GREEN пара показана** (ban #12); regress-lock DEFECT(b) — behaviour-level (код+сообщение+нет-op).
- [ ] `go test ./services/iam/... -race` (**полный, не `-short`**) + `golangci-lint` + `govulncheck` зелёные.
- [ ] vault-trail: `edges/` (new: iam user-token-mint → Hydra reuse #58), `rpc/iam-*` (новый Internal RPC + defect-фикс), `KAC/KAC-<N>.md` («Затронутые сущности» + PR-URL + status).
- [ ] Phase C follow-up тикет заведён (переработка 7 newman-seed'ов + e2e-conformance UTM-06/07/11) и связан с эпиком **ДО** merge (ban #12 исключение для e2e-conformance).

---

## 8. Открытые точки верификации / допущения (для ревьюера)

- **O-1 (impersonation-boundary — sign-off `system-design-reviewer`).** Ключевое допущение §5 пп.1/4:
  граница доверия `MintUserToken` **идентична** уже-принятому #58 (кто достигает :9091+mTLS, уже минтит
  `system_admin` bootstrap-токен ⟹ per-user mint не добавляет privilege через границу). Плюс bounded-impersonation
  (§5.4): минтованный user-токен несёт acr сессии `client_credentials` (≈`"0"`) и **не** байпасит step-up
  для acr-gated RPC — это трактуется как **корректное** ограничение, не дефект. Оба тезиса — обязательный
  sign-off `system-design-reviewer` (паритет с #58 O-1). Если ревьюер сочтёт границу неэквивалентной — эскалировать.
- **O-2 (`API_DOMAIN`-аудитория — reuse #58).** `MintUserToken` запрашивает у Hydra `aud=https://{API_DOMAIN}`
  через тот же `GatewayAudience`-конфиг #58; seed Hydra-клиент whitelist'ит эту аудиторию (иначе «audience has
  not been whitelisted», ср. #320). Значение/источник — из `kacho-deploy` values (переиспользовать существующий).
- **O-3 (код для absent user на MintUserToken — FAILED_PRECONDITION vs by-lane NOT_FOUND).** `api-conventions.md`
  by-lane-split предполагал бы **NOT_FOUND** для own-owned id, не резолвящегося в своей БД (direct-read lane).
  Acceptance закрепляет **FAILED_PRECONDITION** (UTM-04) осознанно: (i) `user_id` здесь — **precondition минта**
  (не fetch-предмет RPC); (ii) код **совпадает** с тем, что async-FK-путь #60 уже возвращал (9 FailedPrecondition),
  делая sync-fast-fail drop-in-совместимым по observable-коду. Существующий `ExistsUser` оборачивает
  `iamerr.ErrInvalidArg` + «`User %s not found`» (capital) → маппится в INVALID_ARGUMENT: реализация обязана
  **либо** re-map absence → `ErrFailedPrecondition`, **сохраняя** канонический текст `"User <id> not found"`
  (capital — `api-conventions.md` `"<Resource> %s not found"`, уже эмитится `ExistsUser`; меняется только КОД,
  не текст), **либо** добавить dedicated existence-метод. Acceptance пинит **исход** (FAILED_PRECONDITION +
  канонический capital-текст `"User <id> not found"`);
  `acceptance-reviewer` подтверждает выбор кода против by-lane-конвенции (если reviewer настаивает на NOT_FOUND —
  это правка acceptance, не реализации).
- **O-4 (discriminator seed-строки — нужен ли).** Seed-строка живёт в `user_oauth_clients` (0046) рядом с
  обычными user-токенами; различается **детерминированным** `id`. Обычный `List`/Revoke пользователя увидит
  seed-строку как ещё один токен. Если это нежелательно (напр. seed не должен показываться в `ListUserTokens`
  или быть revoke-able пользователем) — потребуется additive-миграция с discriminator-колонкой (`is_seed
  boolean`) + фильтрация в List/Revoke. Acceptance по умолчанию НЕ вводит discriminator (LEAN, ban #11) —
  `db-architect-reviewer` подтверждает, приемлема ли видимость seed-строки в user-facing List, или нужен
  discriminator (тогда — новый сценарий + миграция).
- **O-5 (reuse #58 signing-key для per-user seed — приемлемость).** Все per-user seed-клиенты регистрируют
  JWKS = публичный JWK **одного** env bootstrap signing key (#58). Assertion `iss=sub=client_id` дискриминирует
  клиента; Hydra верифицирует против JWKS этого `client_id`. Общий приватный ключ на много seed-клиентов —
  осознанное решение (не вводит новый Secret). `system-design-reviewer`/`db-architect-reviewer`: подтвердить,
  что shared-key не создаёт cross-client-подделки (не создаёт — assertion привязан к конкретному `client_id`,
  зарегистрированному в Hydra; чужой client_id потребовал бы его Hydra-регистрации, что и есть provisioning).
- **O-6 (kid seed-assertion).** JWK `kid`, регистрируемый на seed-клиенте, и `kid` в header assertion обязаны
  совпадать (Hydra выбирает ключ по kid). Предлагается `kid = seed uoc id` (`uoc_…`), по образцу #58
  (`kid=SocID`). Деталь реализации; наблюдаемое (Hydra принимает assertion) закреплено UTM-01.
