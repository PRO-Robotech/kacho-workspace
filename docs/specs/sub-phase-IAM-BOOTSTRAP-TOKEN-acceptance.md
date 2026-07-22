# Sub-phase IAM-BOOTSTRAP-TOKEN — cluster-internal bootstrap-token RPC для non-interactive production-seed

> **Статус:** ✅ APPROVED (`acceptance-reviewer`, 2026-07-22 — 2 правки внесены на review: §8 O-1 narrowly-scoped SA-exemption + mechanism-lock regress-тест; IBT-03 доп. And на idempotent Hydra-OAuth-client provisioning под конкуренцией). Механизм O-1 (gateway step-up-gate SA-exemption) — обязательно через `system-design-reviewer` перед merge.
> **Дата:** 2026-07-22
> **Ревьюер:** `acceptance-reviewer` → APPROVED
> **Эпик/тикет:** KAC-`<N>` (завести); первопричина — GitHub issue `PRO-Robotech/kacho#58`
> **Тип:** новый cluster-INTERNAL RPC (`kacho.cloud.iam.v1`, :9091, mTLS-gated) + идемпотентный provisioning — **не** новый tenant-facing ресурс
> **Repos:** `kacho-proto` (новый `internal_*.proto` + regen) · `kacho-iam` (RPC + provisioning + миграция) · `kacho-api-gateway` (регистрация ТОЛЬКО на internal sub-mux) · `kacho-deploy` (env/helm) · `kacho-workspace` (docs+vault)
> **Формат:** Given-When-Then (только markdown — без кода)

---

## Обзор

Production-режим authN (`api-gateway authn.mode=production-strict`) принимает **только RS256**
Bearer'ы, подписанные Ory Hydra (issuer-pin = Hydra; gateway верифицирует через iam-JWKS-proxy
:9097; требует `aud=https://{API_DOMAIN}` + RS256). Newman/e2e-seed чеканит **HS256** dev-secret
JWT — они инертны против production-стенда (anon + HS256 → 403), а на kind-стенде у Hydra **ноль**
seeded OAuth-клиентов, поэтому единственный вход к первому реальному токену — **человеческая**
Kratos→Hydra browser-церемония. Это блокирует **весь** production-mode e2e (issue #58).

Эта под-фаза добавляет **один cluster-INTERNAL RPC** на iam-листенере :9091 (граница листенера
= gate; mTLS + `<exempt>`-permission, как у прочих :9091-hooks), который **идемпотентно
провиженит** единственный **bootstrap-admin ServiceAccount** (cluster `system_admin`) и чеканит
для него **короткоживущий RS256 access-token через уже существующую машинерию Hydra-обмена** —
non-interactive точка входа для seed'а. RPC минтит **только** этот bootstrap-принципал; произвольный
«mint-for-any-principal» skeleton-key **явно отвергнут** как over-broad. Внешнее поведение: token,
полученный по :9091, gateway принимает как валидный RS256-Bearer (`200`, не `401/403`), а его
принципал может звать `UserTokenService.Issue` / `SAKeyService.Issue` для per-subject-seed'а.

---

## 1. Ground truth (что уже существует — сверено чтением файлов, не переизобретаем)

Полный ES256 `client_assertion` → Hydra `client_credentials` + `private_key_jwt` → RS256
kacho-JWT обмен **уже реализован** и используется registry-шимом `/iam/token`:

- **ES256-подпись assertion** — `services/iam/internal/registrytoken/assertion.go`
  (`SignClientAssertionES256(kid, privateKeyPEM, claims)`; чистый stdlib-crypto, `iss=sub=client_id`,
  `exp ≤ 60s`).
- **Hydra-обмен** — `services/iam/internal/clients/hydra_token_exchange.go`
  (`HydraTokenClient.ClientCredentials`); `grant_type=client_credentials`,
  `client_assertion_type=…jwt-bearer`, и **`audience` — параметр запроса** (`form.Set("audience", …)`).
  Fail-closed: сеть/timeout/5xx/malformed-2xx → `ErrHydraUnavailable`; 4xx → `ErrHydraRejected`
  (raw-тело Hydra **никогда** не в ошибке — no auth-oracle).
- **Use-case брокеринга** — `services/iam/internal/apps/kacho/api/registry_token/token.go` +
  wiring `services/iam/internal/registrytokenwire/build.go`. Отличие bootstrap-токена от registry-шима —
  **только запрашиваемый `audience`**: шим просит `aud=registry.*`, bootstrap обязан просить
  `aud=https://{API_DOMAIN}` (который принимает gateway).
- **Token-hook обогащения** — `services/iam/internal/handler/iamhooks/token_hook_handler.go` +
  `services/iam/internal/service/token_enrichment_service.go`. Для `client_credentials` Hydra отдаёт
  пустой end-user `subject` → хендлер fallback'ит на `client_id`; enricher резолвит его
  `LookupByOAuthClientID` → штампует `kacho_principal_type=service_account`,
  `kacho_principal_id=<sva-id>`, `kacho_account_id`, `kacho_acr` (passthrough Hydra-session ACR,
  для `client_credentials` ≈ `"0"`).
- **Provisioning OAuth-клиента** — iam уже **регистрирует и удаляет** Hydra OAuth-клиентов через
  Hydra Admin (`clients.CreateOAuthClient`/`DeleteOAuthClient`), см. `sa_keys/usecases.go`,
  `user_tokens/usecases.go`. Провижн bootstrap-SA + его OAuth-клиента — уже-поддержанная плюмбинг.
- **Grant `system_admin@cluster` на ServiceAccount уже смоделирован** — enum
  `ClusterGrantSubjectType.SERVICE_ACCOUNT = 2` (`proto/kacho/cloud/iam/v1/cluster_admin_grant.proto`);
  FGA-объект `cluster:cluster_kacho_root#system_admin@service_account:<sva>` — валиден. (Существующий
  `InternalClusterService.GrantAdmin` пока принимает лишь `USER`, но доменная/DB-модель grant'а на SA
  уже есть.)
- **`<exempt>`-permission = «листенер и есть gate»** — паттерн `option (kacho.iam.authz.v1.permission)
  = "<exempt>"` у всех Internal IAM RPC, которых зовёт не человек, а сервис/hook (`InternalIamHooksService.TokenHook`,
  `InternalIAMService.Check/RegisterResource/…`). Каталог-gate байпасится **только** для `<exempt>`;
  authN на транспорте (mTLS) остаётся обязательным.
- **Internal-only маршрутизация** — Internal-сервисы регистрируются **только** на internal sub-mux
  gateway (`restmux/mux.go`, `RegisterInternal*ServiceHandlerFromEndpoint`); `isInternalPath` шлёт
  `/iam/v1/internal/*` на internal-листенер, а gRPC-router `HasInternalSuffix` **блокирует** их на
  публичном листенере (dispatcher 404 на external TLS).
- **acr-exemption сервис-принципала** — `services/iam/internal/authzguard/acr_floor.go`:
  «SAs have no MFA / no acr; they are acr-EXEMPT by design»; `authzguard/fgaproxy.go`:
  «service→service (mTLS-SA) path never consults `required_acr_min`». Это фундамент решения
  «принципал = ServiceAccount» (см. §4).

**Наблюдаемая цель:** оператор/CI, имеющий доступ к cluster-internal :9091 (mTLS), одним вызовом
получает RS256-Bearer, который gateway принимает (`200`), а его принципал (bootstrap-SA с cluster
`system_admin`) может засеять per-subject токены — **без** человеческой browser-церемонии и **без**
HS256-байпаса.

---

## 2. Scope / Non-goals

### In scope
1. **kacho-proto:** новый `internal_bootstrap_token_service.proto` (пакет `kacho.cloud.iam.v1`):
   сервис `InternalBootstrapTokenService`, RPC `MintBootstrapToken` (**sync**, не Operation),
   `permission = "<exempt>"`; regen `gen/`, buf lint/breaking/validate зелёные.
2. **kacho-iam:** реализация RPC на :9091-листенере; идемпотентный provisioning bootstrap-SA
   (+ его Hydra OAuth-клиента + `system_admin@cluster`-grant) при отсутствии; ES256-assertion →
   Hydra-обмен с `aud=https://{API_DOMAIN}` → RS256-токен; DB-инвариант «ровно один bootstrap-SA»;
   миграция под provisioning-строку.
3. **kacho-api-gateway:** регистрация `InternalBootstrapTokenService` **только** на internal sub-mux
   (`iamInternalAddr`); RPC-суффикс попадает в `HasInternalSuffix` (не роутится на external).
4. **kacho-deploy:** env для `API_DOMAIN`/аудитории bootstrap-токена + Hydra-token-URL (переиспользуют
   существующие registry-шим/hook конфиги, где применимо).
5. Тесты (TDD, тот же PR): integration (testcontainers) идемпотентности + «ровно один bootstrap-SA»
   инвариант; unit use-case через mock-порты (Hydra-обмен замокан); assertion token-hook-обогащения
   (SA-принципал claims).

### Non-goals (явно вне scope)
- **Переработка 7 newman-seed'ов** на потребление этого RPC — отдельная **Phase C** follow-up
  (тикет-ссылка при заведении). Здесь — только сам RPC + его provisioning + его тесты.
- **Mint для произвольного принципала.** RPC минтит **исключительно** bootstrap-admin SA. Никакого
  `subject`/`principal`-поля в запросе; skeleton-key «mint-for-any» отвергнут **by construction**
  (см. IBT-11) — расширение под это = отдельный дизайн с отдельным acceptance.
- **Смена issuer/signer.** Hydra остаётся эмитентом/подписантом; iam НЕ чеканит RS256 (только
  брокерит обмен, как registry-шим). Issuer-pin/JWKS-путь не трогаем.
- **Отмена HS256-байпаса dev-стенда** — dev/newman fixture остаётся как есть; production-mode получает
  этот путь. Anonymous/HS256 против production по-прежнему `401/403` (IBT-10, поведение **не меняется**).
- **Полный e2e-conformance-suite** (anon/HS256→403, real-token→200) — Phase C (issue #58 п.3), тут
  зафиксирован как traceability-note, а не реализуется.

---

## 3. Naming (предлагаемые контракты — фиксируются в этом acceptance)

| Артефакт | Значение |
|---|---|
| proto-файл | `proto/kacho/cloud/iam/v1/internal_bootstrap_token_service.proto` |
| package | `kacho.cloud.iam.v1` |
| service | `InternalBootstrapTokenService` (Internal-only, :9091) |
| RPC | `rpc MintBootstrapToken (MintBootstrapTokenRequest) returns (MintBootstrapTokenResponse)` — **sync** |
| permission | `option (kacho.iam.authz.v1.permission) = "<exempt>"` (листенер = gate; НЕ `required_relation`/`scope_extractor`) |
| REST (только internal sub-mux) | `POST /iam/v1/internal/bootstrapToken:mint` |
| request-поля | `int64 ttl_seconds = 1` (опц.; `0` → серверный дефолт; клампится к hard-max, см. IBT-09). **НЕТ** поля subject/principal. |
| response-поля (camelCase) | `accessToken` (RS256 JWT), `tokenType` (`"Bearer"`), `expiresIn` (сек), `expiresAt` (Timestamp, truncate до секунд), `principalId` (id bootstrap-SA, `sva_…`), `issuedAt` (Timestamp, truncate до секунд) |

Стандартные конвенции (`api-conventions.md`, `security.md`, `data-integrity.md`) — нормативны
по ссылке, в тело не дублируются.

---

## 4. Дизайн-решения (для ревьюера — обоснование отклонений и выборов)

### D-1. Принципал = **ServiceAccount** (cluster `system_admin`), НЕ User — обоснование
Bootstrap-принципал обязан звать `acr>=2`-гейтированные seed-RPC (`UserTokenService.Issue`,
`SAKeyService.Issue` — оба несут `required_acr_min="2"`, сверено в proto). **Сервис-принципал
acr-EXEMPT by design** (`acr_floor.go`, `fgaproxy.go`: у SA нет MFA/acr; service→service не
консультирует `required_acr_min`) — поэтому SA удовлетворяет acr-floor **без инъекции acr** в токен.
User-принципал потребовал бы либо реальный MFA/step-up (нет non-interactive пути — снова #58), либо
подделку acr (запрещено). Следствие: bootstrap-принципал — **ServiceAccount**, держащий
`system_admin@cluster:cluster_kacho_root` (модель grant'а на SA уже есть: `ClusterGrantSubjectType.
SERVICE_ACCOUNT`). См. **открытую точку верификации O-1** ниже — она пинит наблюдаемое, а не механизм.

### D-2. **Sync request/response, НЕ `Operation`** — declared-исключение из «мутации→Operation»
`MintBootstrapToken` возвращает `MintBootstrapTokenResponse` **синхронно**, не `operation.Operation`.
Обоснование (для ревьюера — это осознанное отклонение от non-negotiable #9):
- Минт токена — **derivation, read-shaped** (короткий round-trip к Hydra → `{accessToken, expiresIn}`),
  как token-hooks и registry-шим — они тоже sync HTTP, не Operation.
- Это **соответствует уже зафиксированной конвенции** редизайна iam (`docs/plans/kacho-redesign-2026/
  module-iam.md`, rule 17 / §509): `OAuthClient:token` и `AuthService.TokenExchange` — **declared
  sync-исключения** (`client_credentials`-обмен → `{accessToken°, expiresIn}` за один round-trip;
  durable-credential чеканит только async `Create/Rotate`). Bootstrap-mint — того же класса.
- Единственная **durable** часть — идемпотентный provisioning (SA/OAuth-клиент/grant); он **не** предмет
  токен-минта и safe к повтору (D-3). Оборачивать sync-derivation в async `Operation` (клиент поллил бы
  `Operation.Get` ради строки, которую он и так получает синхронно) — лишний round-trip без durability-
  выигрыша. Токен возвращается **в теле ответа**, не в `Operation.response`.

### D-3. Идемпотентный provisioning + DB-инвариант «ровно один bootstrap-SA»
Первый вызов провиженит (если отсутствует): bootstrap-SA (cluster-scoped), его Hydra OAuth-клиент
(`client_credentials` + `private_key_jwt`), и `system_admin@cluster`-grant. Последующие — **переиспользуют**
существующие. «Ровно один bootstrap-SA» — **DB-инвариант** (partial-`UNIQUE`/singleton-row, `data-integrity.md`
ban #10 — не software check-then-act), устойчивый к конкурентным первым-вызовам (IBT-03). Идемпотентность
делает production-newman-seed **re-run-safe**.

### D-4. Граница листенера = gate (`<exempt>` + mTLS), Internal-only
RPC несёт `permission="<exempt>"` (как прочие :9091-hooks): per-RPC FGA-Check байпасится, **потому что
доступ уже ограничен транспортом** — mTLS-verified cluster-internal :9091, недостижимый с external
endpoint (ban #6). AuthN (mTLS) остаётся обязательным (не «internal = trusted»); non-mTLS → reject
на транспорте (IBT-07). Регистрация **только** на internal sub-mux (IBT-06).

---

## Сценарии

> ID трассируются в имена integration/unit/e2e-тестов. `{API_DOMAIN}` = публичный домен gateway
> (аудитория, которую принимает production-authN). `:9091` = cluster-internal iam-листенер (mTLS).

### Сценарий IBT-01: Happy path — первый вызов провиженит bootstrap-SA и чеканит токен

**ID:** `IBT-01`

**Given** production-mode стенд: gateway `authn.mode=production-strict`, iam-JWKS-proxy :9097 отдаёт
Hydra-kids, Hydra доступна
**And** bootstrap-SA ещё **не** провижен (fresh стенд; строки provisioning нет)
**And** вызывающий имеет валидный клиентский mTLS-сертификат для :9091

**When** клиент вызывает `InternalBootstrapTokenService.MintBootstrapToken` по :9091 (mTLS) с payload:
  - `ttlSeconds` = 0 (серверный дефолт)

**Then** ответ `200` — синхронный `MintBootstrapTokenResponse` (НЕ `Operation`)
**And** iam идемпотентно создал: bootstrap-SA (`principalId` = `sva_…`), его Hydra OAuth-клиент
(`client_credentials`/`private_key_jwt`), и `system_admin@cluster:cluster_kacho_root`-grant на этот SA
**And** `accessToken` — непустой **RS256** JWT (header `alg=RS256`, Hydra-`kid`)
**And** `tokenType` = `"Bearer"`, `expiresIn` > 0, `expiresAt`/`issuedAt` заполнены (truncate до секунд)
**And** декодированный `accessToken` несёт `kacho_principal_type=service_account`,
`kacho_principal_id` == `principalId`, `aud` включает `https://{API_DOMAIN}`, `iss` = Hydra-issuer

---

### Сценарий IBT-02: Идемпотентность — повторный вызов переиспользует bootstrap-SA

**ID:** `IBT-02`

**Given** bootstrap-SA **уже** провижен предыдущим вызовом (IBT-01), `principalId` = `P`

**When** клиент повторно вызывает `MintBootstrapToken` по :9091 (mTLS)

**Then** ответ `200`; `principalId` == `P` (тот же SA — новый SA НЕ создаётся)
**And** новый Hydra OAuth-клиент/grant **не** создаётся (переиспользуются существующие)
**And** возвращается **свежий** `accessToken` для того же принципала (новый `exp`/`iat`)
**And** provisioning-строка bootstrap-SA осталась ровно одна (инвариант, ср. IBT-03)

---

### Сценарий IBT-03: Concurrency — конкурентные первые-вызовы → ровно один bootstrap-SA

**ID:** `IBT-03`

**Given** fresh стенд (bootstrap-SA не провижен)

**When** `N` конкурентных горутин одновременно вызывают `MintBootstrapToken` (первый provisioning-путь)

**Then** **ровно одна** транзакция создаёт bootstrap-SA; остальные видят/переиспользуют его
(DB-инвариант partial-`UNIQUE`/singleton-row — `data-integrity.md`, не software check-then-act)
**And** все `N` ответов несут **один и тот же** `principalId`
**And** в БД — ровно одна provisioning-строка bootstrap-SA (нет дублей, нет constraint-INTERNAL-leak)
**And** внешний Hydra OAuth-клиент bootstrap-SA провижится **не более одного раза** под конкуренцией:
провижн-порядок — сначала выиграть DB-singleton (CAS/partial-`UNIQUE`), и **только** победитель создаёт
Hydra-клиента, привязанного к этому единственному SA; проигравшие горутины переиспользуют его. Dual-write
(DB-строка + внешний Hydra-клиент) гейтится **DB-инвариантом**, а не отдельным software-guard'ом → нет
orphan/дубль-Hydra-клиента (`system-design-reviewer`: cross-boundary side-effect за durable-CAS)

> Проверяется integration-тестом с concurrent goroutines (`data-integrity.md` §чек-лист п.5).

---

### Сценарий IBT-04: Токен принимается gateway (RS256 через :9097 JWKS) — не 401/403

**ID:** `IBT-04`

**Given** `accessToken` получен из `MintBootstrapToken` (IBT-01)
**And** gateway верифицирует подпись через iam-JWKS-proxy :9097 (Hydra-kids)

**When** клиент делает gateway-API-вызов на **external** endpoint с `Authorization: Bearer <accessToken>`
(напр. `GET /iam/v1/accounts` → `AccountService.List`, либо system-admin CRUD)

**Then** gateway верифицирует токен (RS256, `iss`=Hydra, `aud=https://{API_DOMAIN}`) и пропускает —
ответ `200` (**НЕ** `401 invalid_token`, **НЕ** `403 permission denied`)
**And** для system-admin-gated RPC доступ разрешён, т.к. принципал держит `system_admin@cluster`

---

### Сценарий IBT-05: Bootstrap-SA сеет per-subject токены (acr-exempt)

**ID:** `IBT-05`

**Given** `accessToken` bootstrap-SA (system_admin, `kacho_principal_type=service_account`), IBT-01
**And** существует целевой User `usr_…` / ServiceAccount `sva_…` для сева

**When** клиент вызывает `UserTokenService.Issue` (REST `POST /iam/v1/users/{userId}/tokens`, несёт
`required_acr_min="2"`) с `Authorization: Bearer <bootstrap accessToken>`

**Then** ответ `200` — `Operation` (async), **НЕ** `401` step-up-challenge (сервис-принципал acr-exempt —
D-1); поллинг `OperationService.Get` до `done=true && !error` отдаёт выпущенный токен
**And** аналогично `SAKeyService.Issue` (`required_acr_min="2"`) с тем же Bearer → `200` `Operation`
**And** per-subject-seed для остальных newman-субъектов работает этим же путём

> Зависимость от корректности token-hook-claims (`kacho_principal_type=service_account`,
> `kacho_principal_id`) — покрыто unit-assertion'ом обогащения (Traceability `IBT-T5`).

---

### Сценарий IBT-06: Internal-only — RPC не роутится на external endpoint (ban #6)

**ID:** `IBT-06`

**Given** production-стенд; `InternalBootstrapTokenService` зарегистрирован **только** на internal sub-mux

**When** клиент обращается к `POST /iam/v1/internal/bootstrapToken:mint` на **external** TLS endpoint
(`api.{API_DOMAIN}:443`)

**Then** запрос **не** маршрутизируется на хендлер — `404 Not Found` (dispatcher/`HasInternalSuffix`
блокирует Internal-суффикс на публичном листенере)
**And** RPC достижим **только** через cluster-internal :9091 / internal sub-mux (port-forward/admin-tooling)

---

### Сценарий IBT-07: Non-mTLS вызывающий на :9091 → отклонён

**ID:** `IBT-07`

**Given** production-стенд, :9091 требует verified client-cert (mTLS)

**When** клиент вызывает `MintBootstrapToken` по :9091 **без** валидного клиентского сертификата
(plaintext/insecure или неверный SAN)

**Then** соединение/запрос отклоняется на транспорте (TLS handshake fail либо `UNAVAILABLE`/
`UNAUTHENTICATED`) — токен **не** выдаётся
**And** «internal = trusted, mTLS не нужен» — недопустимо (`security.md` §authN-везде); хендлер
недостижим без mTLS

---

### Сценарий IBT-08: Hydra недоступна → fail-closed `UNAVAILABLE`

**ID:** `IBT-08`

**Given** валидный mTLS-вызов на :9091, но Hydra token-endpoint недоступен (сеть/timeout/5xx/malformed-2xx)

**When** клиент вызывает `MintBootstrapToken`

**Then** ответ `UNAVAILABLE` (gRPC 14) — **fail-closed**: токен НЕ выдаётся, open-fail недопустим
(`hydra_token_exchange.go` → `ErrHydraUnavailable`; тон сообщения фиксированный, raw-тело Hydra **не**
протекает — no auth-oracle, `security.md` hardening-инвариант #1)
**And** provisioning, выполненный ДО обмена (если это был первый вызов), остаётся идемпотентно
переиспользуемым при retry (не создаёт дубль-SA — IBT-03/IBT-02)

---

### Сценарий IBT-09: Короткоживущий токен — bounded TTL

**ID:** `IBT-09`

**Given** валидный mTLS-вызов на :9091

**When** клиент вызывает `MintBootstrapToken` с `ttlSeconds` = очень большим значением (напр. `86400`)

**Then** выданный `accessToken` — **короткоживущий**: `expiresIn` ≤ серверный hard-max (bootstrap-токен
намеренно кратко-живущий; запрошенный TTL **клампится**, не превышается)
**And** `expiresAt - issuedAt` == `expiresIn` (в пределах truncate-до-секунд) и ≤ hard-max
**And** `ttlSeconds` = 0 → применяется серверный дефолт (тоже ≤ hard-max)

---

### Сценарий IBT-10: Anonymous / HS256 против production по-прежнему отвергаются (регресс-lock, не меняется)

**ID:** `IBT-10`

**Given** production-mode gateway (`authn.mode=production-strict`)

**When** клиент делает gateway-API-вызов (а) без токена, либо (б) с **HS256**-forged dev-secret JWT

**Then** (а) `401 UNAUTHENTICATED`; (б) `401 invalid_token`/`403` — HS256 отвергается (RS256-only,
CWE-347) — поведение **не изменено** этой под-фазой
**And** ТОЛЬКО RS256-токен из bootstrap-mint (или реальной Hydra-выдачи) принимается (IBT-04) —
bootstrap-путь **не** ослабляет production-authN

---

### Сценарий IBT-11: Only-bootstrap — произвольный принципал не минтится (skeleton-key отвергнут by construction)

**ID:** `IBT-11`

**Given** валидный mTLS-вызов на :9091

**When** клиент пытается запросить токен для произвольного субъекта — `MintBootstrapTokenRequest`
**не содержит** поля subject/principal; клиент присылает лишний/неизвестный ключ (напр. `subjectId`)

**Then** RPC чеканит токен **только** для bootstrap-admin SA (единственный принципал по контракту);
неизвестное поле игнорируется grpc-gateway (не влияет на принципал) ИЛИ, если добавлено в схему как
запрещённое, → `INVALID_ARGUMENT`
**And** нет пути выписать токен для другого User/SA этим RPC (over-broad mint отсутствует **by design**,
D-2/Non-goals) — per-subject-выдача идёт **только** через `UserTokenService.Issue`/`SAKeyService.Issue`
под authz (IBT-05), не через bootstrap-RPC

---

## 5. Security-раздел (почему минт admin-токена на :9091 приемлем)

Минт токена cluster-`system_admin`-принципала — чувствительная операция; она приемлема **строго** при
одновременном выполнении (defense-in-depth, `security.md`):

1. **Internal-only surface** — RPC достижим **только** на cluster-internal :9091 / internal sub-mux;
   dispatcher 404 на external (ban #6, IBT-06). Публичный периметр его не видит.
2. **mTLS обязателен** — verified client-cert; non-mTLS → reject (IBT-07). AuthN не байпасится
   (`<exempt>` снимает лишь per-RPC FGA-Check, не транспортный authN — «internal = trusted» запрещено).
3. **Bootstrap-only принципал** — минтится **исключительно** заранее-известный bootstrap-admin SA; нет
   произвольного-принципала (IBT-11). Компрометация RPC не даёт «выписать токен на любого» — только на
   тот единственный принципал, что и так провижится идемпотентно.
4. **Короткий TTL** — токен намеренно кратко-живущий, TTL клампится к hard-max (IBT-09); окно
   злоупотребления ограничено.
5. **Инфра-нейтрально** — ответ несёт только `accessToken`/`expiry`/`principalId`; ни placement/underlay/
   инфра-идентификаторов (`security.md` инфра-чувствительные данные не применимы — это identity-токен).
6. **No auth-oracle / no leak** — Hydra-недоступность → фикс. `UNAVAILABLE`, raw-тело Hydra не протекает
   (IBT-08); INTERNAL никогда не эхает `err.Error()` (`security.md` #1).
7. **Не ослабляет production-authN** — anon/HS256 по-прежнему `401/403` (IBT-10); добавляется лишь
   легитимный RS256-путь через существующий Hydra-обмен.

---

## 6. Traceability (сценарий → тест)

| ID | Проверяемое | Уровень теста | Тест-идентификатор |
|---|---|---|---|
| IBT-01 | happy-path provisioning + RS256-токен + SA-claims | integration (testcontainers + fake/mock Hydra-exchange) | `TestMintBootstrapToken_FirstCall_ProvisionsAndMints` |
| IBT-02 | идемпотентный reuse (тот же `principalId`, свежий токен) | integration | `TestMintBootstrapToken_Idempotent_ReusesSA` |
| IBT-03 | concurrency → ровно один bootstrap-SA (DB-инвариант) | integration, concurrent goroutines | `TestMintBootstrapToken_Concurrent_SingleBootstrapSA` |
| IBT-04 | gateway принимает RS256-Bearer (200, не 401/403) | e2e-conformance (Phase C follow-up) | `IBT-04::bootstrap-token-accepted` (Phase C) |
| IBT-05 | bootstrap-SA зовёт acr-gated Issue → 200 (acr-exempt) | e2e-conformance (Phase C) + unit acr-exempt | `IBT-05::seed-usertoken-sakey` (Phase C) |
| IBT-06 | Internal-only: external → 404 | e2e/gateway-routing | `IBT-06::not-on-external` (Phase C) |
| IBT-07 | non-mTLS → reject | integration/transport | `TestMintBootstrapToken_NonMTLS_Rejected` |
| IBT-08 | Hydra down → fail-closed UNAVAILABLE, no-leak | unit use-case (Hydra-exchange mock → ErrHydraUnavailable) | `TestMintBootstrapToken_HydraUnavailable_FailClosed` |
| IBT-09 | bounded TTL (clamp) | unit use-case (injected clock) | `TestMintBootstrapToken_TTLClampedToMax` |
| IBT-10 | anon/HS256 по-прежнему 401/403 (регресс-lock) | e2e-conformance (Phase C) | `IBT-10::hs256-still-rejected` (Phase C) |
| IBT-11 | only-bootstrap, нет arbitrary-mint | unit (request-схема) | `TestMintBootstrapToken_NoArbitraryPrincipal` |
| IBT-T5 | token-hook обогащение: SA-принципал claims | unit (`token_enrichment_service`) | `TestEnrichClaims_BootstrapSA_ServiceAccountClaims` |

> Уровни, помеченные «Phase C», — e2e-conformance против задеплоенного стенда (issue #58 п.3): пишутся
> в follow-up-под-фазе потребления seed'ом; здесь фиксируются как traceability-обязательство. RED→GREEN
> для integration/unit — **в том же PR** (ban #12).

---

## 7. Definition of Done (этой под-фазы)

- [ ] `internal_bootstrap_token_service.proto` в `kacho-proto` + regen `gen/`; `buf lint`/`breaking`/`validate` зелёные (`proto-api-reviewer`).
- [ ] Миграция под provisioning-строку с DB-инвариантом «ровно один bootstrap-SA» (partial-`UNIQUE`/singleton-row); не редактирует применённую (`db-architect-reviewer`).
- [ ] Реализация RPC (sync), use-case + порты (Hydra-exchange за портом), idempotent provisioning; `permission="<exempt>"`; на :9091.
- [ ] `kacho-api-gateway`: регистрация **только** на internal sub-mux; суффикс в `HasInternalSuffix` (Internal-only на external — 404).
- [ ] Integration-тесты IBT-01/02/03/07 (testcontainers, concurrent-race для инварианта); unit IBT-08/09/11 + IBT-T5 (mock-порты). RED→GREEN пара показана.
- [ ] `go test ./services/iam/... -race` (полный, не `-short`) + `golangci-lint` + `govulncheck` зелёные.
- [ ] vault-trail: `edges/` (new: iam bootstrap-mint → Hydra reuse), `rpc/iam-*`, `KAC/KAC-<N>.md`.
- [ ] Phase C follow-up тикет заведён (переработка 7 newman-seed'ов + e2e-conformance IBT-04/05/06/10) и связан с эпиком **ДО** merge (ban #12 исключение для e2e-conformance).

---

## 8. Открытые точки верификации / допущения (для ревьюера)

- **O-1 (acr-floor на публичном пути для сервис-принципала).** Внутренний acr-floor (`acr_floor.go`)
  и fgaproxy (`fgaproxy.go`) недвусмысленно освобождают service→service / module-SA от `required_acr_min`.
  Однако публичный gateway step-up-gate (`gateway/internal/middleware/dpop_http_middleware.go`,
  `stepUp.Check(verified, req)`) в прочитанном коде выполняется для **любого** verified-токена и **не имеет
  явной ветки-исключения для `kacho_principal_type=service_account`**; enrichment штампует
  `kacho_acr="0"` для `client_credentials`. IBT-05 пинит **наблюдаемое** (bootstrap-SA-Bearer →
  `UserTokenService.Issue` → `200`, не `401` step-up), а не конкретный механизм. Реализация обязана
  обеспечить это одним из санкционированных способов, **консистентно с §4.1.2 (сервис-принципал
  acr-exempt)**: (а) SA-exemption-ветка в gateway step-up-gate (паритет с internal acr-floor —
  предпочтительно, единый инвариант) — **но narrowly-scoped**: exemption НЕ должен превратиться в
  blanket-байпас step-up для **любого** `service_account`-токена на публичном пути (это ослабило бы
  `security.md` authZ-на-каждом-RPC для всех SA-key-holder'ов кластера); ветка гейтится строго на
  принципал(ы), у которых acr-exemption легитимен (bootstrap-SA / service→service by construction) +
  регресс-тест «обычный (не-exempt) user с acr<floor всё ещё получает step-up» (mechanism-lock, чтобы
  фикс не реинтродуцировал шире); либо (б) минт токена с acr, удовлетворяющим floor для bootstrap-SA —
  где acr **легитимен** (реальный ACR Hydra-сессии bootstrap-клиента), **НЕ** инъекция/подделка
  acr-claim (это запрещено D-1 и было бы acr-spoofing). Выбор механизма — на реализацию/`system-design-reviewer`;
  acceptance фиксирует **исход**. Если ни (а)/(б) не выбираемы без более широкого изменения — эскалировать (ambiguity в спеке).
- **O-2 (`API_DOMAIN`-аудитория).** Bootstrap-mint обязан запрашивать у Hydra `aud=https://{API_DOMAIN}`
  (то, что принимает gateway) — единственное отличие от registry-шима (`aud=registry.*`). Точное значение
  и его конфиг-источник — из `kacho-deploy` values (переиспользовать существующий gateway-`API_DOMAIN`).
- **O-3 (grant `system_admin` на SA-субъект).** Доменная/DB-модель grant'а на `SERVICE_ACCOUNT` уже есть
  (`ClusterGrantSubjectType.SERVICE_ACCOUNT`), но текущий `InternalClusterService.GrantAdmin` принимает
  лишь `USER`. Provisioning bootstrap-SA пишет `system_admin@cluster:…@service_account:<sva>` напрямую
  (тем же `cluster_admin_grants` + `fga_outbox`-путём), не через публичный `GrantAdmin` — детали
  provisioning, наблюдаемое (SA держит `system_admin@cluster`) закреплено в IBT-01/IBT-04.
