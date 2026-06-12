# Sub-phase SEC-K — api-gateway REST-mux→backend mTLS + hybrid external listener (acceptance)

**Статус:** DRAFT (ожидает APPROVED от `acceptance-reviewer`)
**Репозиторий:** `kacho-api-gateway` (edge); deploy-конфиг — `kacho-deploy` (helm env).
**Тип:** security hardening (mTLS rollout) + bugfix (503 на UI→gw REST после mTLS-флипа).
**Эпик:** SEC (mTLS rollout), волна после SEC-E/SEC-I.
**Документ — markdown only, без кода.** Это spec поведения, не реализация.

---

## 0. Контекст и проблема

Эпик SEC поэтапно включил mTLS на cluster-internal рёбрах. SEC-E mTLS-ифицировал
**gRPC-director** (`proxy`) и **authz-middleware** AuthorizeService-клиент: каждый
backend дозванивается с client-cert'ом gateway'я + per-edge ServerName, когда
соответствующий edge включён (`MTLS_{VPC,COMPUTE,IAM,NLB}_ENABLE`). Cert-материал
gateway'я уже смонтирован (`KACHO_API_GATEWAY_MTLS_CLIENT_{CERT,KEY}_FILE` + `_CA_FILE`),
per-edge enable/server-name конфиг существует (`internal/config/config.go`,
`cmd/api-gateway/mtls_config.go`).

**Пропущенный путь (баг, 503):** grpc-gateway **REST-mux** (`internal/restmux/mux.go`) —
это **отдельный** proxy-path от gRPC-director'а. Он строит ОДИН `[]grpc.DialOption` с
`grpc.WithTransportCredentials(insecure.NewCredentials())` (~line 234) и передаёт его в
**КАЖДЫЙ** `RegisterXServiceHandlerFromEndpoint(ctx, mux, <addr>, opts)` — для vpc
(`vpcAddr`/`vpcInternalAddr`), compute (`computeAddr`/`computeInternalAddr`), iam
(`iamAddr`/`iamInternalAddr` — включая `AuthorizeService`), nlb (`lbAddr`/`lbInternalAddr`).
После флипа backend'ов в `tls.RequireAndVerifyClientCert` любой REST-вызов (UI → gw REST
→ backend :9090/:9091) обрывается на TLS-handshake: backend требует client-cert, а mux
дозванивается insecure → connection reset by peer → `503` («error reading server preface …
connection reset by peer»). UI читает ресурсы через REST → весь UI «лёг».

**Вторая задача (hybrid external listener):** external TLS-listener gateway'я
(`KACHO_API_GATEWAY_TLS_LISTEN_ADDR` :8443, server-cert
`KACHO_API_GATEWAY_TLS_{CERT,KEY}_FILE`) сейчас поднимается с `tls.Config` без
`ClientAuth` (эффективно `NoClientCert`) — внешний клиент аутентифицируется только по
JWT (SEC-J). Нужен **best-practice hybrid**: `tls.VerifyClientCertIfGiven` — клиент
с валидным kacho client-cert'ом аутентифицируется по идентичности сертификата
(SPIFFE SAN), клиент без сертификата — fallback на JWT (SEC-J). Internal-listener'ы
остаются строгим `RequireAndVerifyClientCert` — их НЕ трогаем.

### Цель под-фазы
1. **REST-mux→backend mTLS:** REST-mux дозванивается до каждого backend'а
   (iam/vpc/compute/nlb, public + internal addr) с client-cert'ом gateway'я +
   корректным per-backend ServerName, когда mTLS на edge включён. `enable=false` →
   insecure (текущий dev без регрессий). Переиспользуем существующие `mtls_config`-хелперы
   (`backendEdge` / `buildBackendDialCreds` / `EdgeTLSClient` / `grpcclient.TLSClientCreds`) —
   **новой cert-обвязки не изобретаем**.
2. **Hybrid external listener:** external listener использует
   `VerifyClientCertIfGiven` с internal CA как client-CA. С валидным client-cert'ом →
   principal из verified-cert (SPIFFE SAN). Без cert'а → JWT-path (SEC-J). Без cert'а и
   без JWT на protected RPC → `Unauthenticated`. Internal-listener'ы — строгий mTLS,
   без изменений.

### Trust-инвариант (сквозной)
Principal-из-metadata (`x-kacho-principal-*`) доверяем **только** на internal
mTLS-verified hop'ах. External listener выводит principal из **JWT или verified-cert**,
**никогда** из client-supplied `x-kacho-principal-*` заголовков. Gateway продолжает
стрипать/игнорировать входящие principal-заголовки от внешних клиентов (уже сделано в
`internal/middleware/auth.go` — `HTTP()` и `authorize()` удаляют `x-kacho-principal-*` /
`grpc-metadata-x-kacho-principal-*`). Этот инвариант под-фаза НЕ ослабляет.

---

## 1. Глоссарий / сущности

| Термин | Значение |
|---|---|
| REST-mux | grpc-gateway `runtime.ServeMux` (public+internal) в `internal/restmux/mux.go`. Отдельный proxy-path от gRPC-director'а. |
| backend-key | Ключ в `BackendAddrs`: `vpc`/`vpcInternal`/`compute`/`computeInternal`/`iam`/`iamInternal`/`loadbalancer`/`loadbalancerInternal`. |
| edge | mTLS-ребро (одна backend-identity, один enable-flag): `vpc`/`compute`/`iam`/`nlb`. public+internal порт сервиса делят один edge (`backendEdge`). |
| ServerName (SNI) | Имя в dial-creds, проверяется против SAN server-cert'а backend'а. Per-edge override (`MTLS_*_SERVER_NAME`) или derive из dial-host. |
| external listener | TLS-listener :8443 для внешних клиентов (browser/CLI). server-cert `KACHO_API_GATEWAY_TLS_*`. |
| internal listener | cluster-internal listener'ы (gRPC :9091 и т.п.), строгий `RequireAndVerifyClientCert`. |
| hybrid client-auth | `tls.VerifyClientCertIfGiven` на external listener: cert опционален, при наличии — верифицируется против internal CA. |
| cert-principal | Principal, выведенный из verified client-cert SPIFFE SAN `spiffe://kacho.cloud/ns/<ns>/sa/<sa>`. |
| JWT-principal | Principal из validated Bearer (SEC-J: Hydra JWKS RS256/ES256/EdDSA, или HMAC-dev). |

---

## 2. Допущения / pre-conditions

- `D-1` Backend'ы (iam/vpc/compute/nlb) на mTLS-edge'ах сконфигурированы
  `RequireAndVerifyClientCert` (результат SEC-D/SEC-F). REST-mux — единственный
  оставшийся insecure dial-path.
- `D-2` Cert-материал gateway'я смонтирован и валиден (PEM): `MTLS_CLIENT_CERT_FILE`,
  `MTLS_CLIENT_KEY_FILE`, `MTLS_CA_FILE`. Это **тот же** материал, что использует SEC-E
  director/authz-dial.
- `D-3` Per-edge config существует: `MTLS_{VPC,COMPUTE,IAM,NLB}_ENABLE` +
  `MTLS_{VPC,COMPUTE,IAM,NLB}_SERVER_NAME`. REST-mux обязан читать те же значения, что
  SEC-E backend-dial (никаких новых per-edge env под REST-mux).
- `D-4` SEC-J JWKS-верификатор и HMAC-dev-path в `middleware/auth.go` работают и не
  меняются по контракту. Hybrid-cert path — это НОВАЯ ветвь ПЕРЕД JWT-fallback'ом.
- `D-5` Internal CA, которой подписаны client-cert'ы сервисов/операторов, доступна
  gateway'ю как client-CA для external listener'а (тот же trust-anchor, что
  `MTLS_CA_FILE`, либо явно сконфигурированный external-client-CA).
- `D-6` SPIFFE SAN-формат `spiffe://kacho.cloud/ns/<ns>/sa/<sa>` — канонический для всех
  kacho client-cert'ов (см. SEC-G operator-cert).
- `D-7` `enable=false` по умолчанию на всех edge'ах (dev backward-compat). Default-поведение
  под-фазы при всех enable=false и пустом external-client-CA — байт-в-байт текущее.

---

## 3. Acceptance-сценарии (Given-When-Then)

### Capability (1) — REST-mux → backend mTLS

#### A-1a — mTLS включён, UI REST-вызов проходит (нет 503) `[happy / regression-fix]`
- **Given** edge `vpc` включён (`MTLS_VPC_ENABLE=true`), gateway cert-материал смонтирован,
  backend `kacho-vpc` :9090 в `RequireAndVerifyClientCert`, ServerName сконфигурирован.
- **When** клиент делает REST `GET /vpc/v1/networks?projectId=…` (UI-сценарий) через
  REST-mux gateway'я.
- **Then** REST-mux дозванивается до vpc-backend'а с **client-cert'ом gateway'я** +
  корректным **ServerName**; TLS-handshake успешен; backend отвечает `200 OK` с телом
  ListNetworks. **НЕТ** `503` и **НЕТ** «connection reset by peer / error reading server
  preface» в логах.
- **И** то же справедливо для compute (`GET /compute/v1/instances`) и iam
  (`POST /iam/v1/authorize:check` → `AuthorizeService`) при включённых соответствующих
  edge'ах.

#### A-1b — per-backend ServerName корректность (iam vs vpc vs compute, public vs internal) `[positive / matrix]`
- **Given** включены edge'и vpc, compute, iam; per-edge `SERVER_NAME` заданы.
- **When** REST-mux регистрирует/дозванивается до каждого backend-key.
- **Then** каждый dial несёт **СВОЙ** ServerName согласно edge'у:
  - `iam` (public :9090) → ServerName edge `iam` (например `kacho-iam.kacho.svc.cluster.local`).
  - `iamInternal` (:9091) → ServerName edge `iam` (тот же edge, та же identity — `backendEdge("iamInternal")="iam"`).
  - `vpc` / `vpcInternal` → ServerName edge `vpc`.
  - `compute` / `computeInternal` → ServerName edge `compute`.
  - `loadbalancer` / `loadbalancerInternal` → ServerName edge `nlb`.
- **И** ServerName проверяется backend'ом против SAN его server-cert'а: подстановка
  ServerName от чужого edge'а (например vpc-ServerName на dial к iam) → TLS-verify fail
  (negative-проверка matrix'а).
- **И** маппинг backend-key→edge берётся из существующего `backendEdge` (не дублируется
  в REST-mux).

#### A-1c — `enable=false` → insecure dial, ноль регрессий `[regression / dev backward-compat]`
- **Given** все edge'и выключены (`MTLS_*_ENABLE=false`) — default dev.
- **When** REST-mux инициализируется и обслуживает REST-вызовы.
- **Then** каждый backend-dial — **insecure** (как до под-фазы); поведение REST байт-в-байт
  текущее; существующие newman-кейсы зелёные без изменений.
- **И** включение части edge'ей (например только `vpc`) → vpc-dial mTLS, остальные
  (compute/iam/nlb) остаются insecure (per-edge независимость, parity с SEC-E §3.9).

#### A-1d — включённый edge без cert-материала → fail-fast при старте `[negative / fail-closed]`
- **Given** `MTLS_VPC_ENABLE=true`, но `MTLS_CLIENT_CERT_FILE` (или key/ca) пуст/отсутствует.
- **When** gateway стартует и строит REST-mux dial-creds.
- **Then** старт **прерывается с ошибкой** (`log.Fatalf` в composition-root) — процесс НЕ
  поднимается в half-secured состоянии (паритет с SEC-E-03 / `EdgeTLSClient` fail-fast).
  Никакого «silent insecure fallback» под включённый edge.

#### A-1e — OperationService self-loopback остаётся insecure `[invariant]`
- **Given** REST-mux регистрирует `OperationService` через in-process OpsProxy (не
  cross-pod dial); backend-dial'ы для vpc/compute/iam/nlb могут быть mTLS.
- **When** клиент поллит `GET /operations/{id}` или `OperationService.Get`.
- **Then** OpsProxy работает без изменений (in-process, не пересекает pod-границу) —
  mTLS к нему не применяется (паритет с SEC-E-07 loopback). Никакой регрессии
  Operation-поллинга.

---

### Capability (2) — Hybrid external listener (optional mTLS + JWT fallback)

#### A-2a — browser без cert'а, валидный JWT → аутентификация по JWT `[happy / fallback]`
- **Given** external listener в режиме `VerifyClientCertIfGiven`; клиент (browser)
  **не предъявляет** client-cert; в запросе валидный Bearer (SEC-J: Hydra JWKS или HMAC-dev).
- **When** клиент делает REST `GET /vpc/v1/networks` на external :8443.
- **Then** TLS-handshake успешен (cert не требуется); JWT валидируется по SEC-J;
  principal выводится из verified `kacho_principal_*` claims (top-level или ext_claims),
  либо через SubjectLookuper; запрос авторизуется как JWT-principal. `200 OK`.
- **И** поведение JWT-path идентично текущему (SEC-J не регрессирует).

#### A-2b — клиент с валидным kacho client-cert'ом, без JWT → аутентификация по cert SPIFFE `[happy / cert-path]`
- **Given** external listener в `VerifyClientCertIfGiven`; клиент предъявляет **валидный**
  kacho client-cert (подписан internal CA, SAN `spiffe://kacho.cloud/ns/<ns>/sa/<sa>`);
  **нет** Authorization Bearer.
- **When** клиент делает protected REST-вызов на external :8443.
- **Then** TLS-handshake верифицирует client-cert против internal CA;
  principal выводится из **verified-cert** identity (SPIFFE SAN → cert-principal);
  JWT-требование **пропускается** (cert уже аутентифицировал). Запрос авторизуется как
  cert-principal. `200 OK` (если authz разрешает).
- **И** cert-principal проставляется gateway'ем (из verified-cert), НЕ из
  client-supplied заголовков.

#### A-2c — ни cert'а, ни JWT на protected RPC → Unauthenticated `[negative]`
- **Given** external listener в `VerifyClientCertIfGiven`; запрос protected RPC БЕЗ
  client-cert'а и БЕЗ Bearer.
- **When** клиент делает REST-вызов на external :8443.
- **Then** TLS-handshake успешен (cert опционален), но ни cert-, ни JWT-principal'а нет →
  `Unauthenticated` (HTTP 401, gRPC code 16), с `WWW-Authenticate: Bearer …`. Поведение
  эквивалентно текущему «missing Bearer на protected RPC» (контракт не меняется).
- **И** публичные/allowlist-RPC (healthz/readyz, public allowlist) продолжают работать
  без cert/JWT (под-фаза их не трогает).

#### A-2d — невалидный/forged client-cert → отклонён на handshake `[negative / security]`
- **Given** external listener в `VerifyClientCertIfGiven`, client-CA = internal CA;
  клиент предъявляет cert, **не подписанный** internal CA (self-signed / чужой CA / expired /
  отозванный).
- **When** клиент инициирует TLS-handshake на external :8443 с этим cert'ом.
- **Then** handshake **отклоняется** (cert предъявлен, но не верифицируется против
  client-CA — это семантика `VerifyClientCertIfGiven`: «если дан — должен быть валиден»).
  Запрос не доходит до authz; принципал из forged-cert'а **не** выводится.
- **И** клиент НЕ может «деградировать» к JWT-path, предъявив битый cert (битый cert =
  hard reject, не fallback).

#### A-2e — внешний клиент не может подменить identity через `x-kacho-principal-*` `[negative / trust-invariant]`
- **Given** external listener; клиент (с JWT, или с cert, или без обоих) добавляет в
  запрос заголовки `X-Kacho-Principal-Type/Id/Display-Name` (и/или
  `Grpc-Metadata-X-Kacho-Principal-*`).
- **When** запрос приходит на external :8443.
- **Then** gateway **стрипает/игнорирует** входящие principal-заголовки ДО auth-flow
  (как сейчас в `auth.HTTP()` / `authorize()`); итоговый principal — **только** из
  verified-cert или validated-JWT. Подменённый header не даёт ни identity, ни
  privilege-escalation.
- **И** если нет ни cert'а, ни JWT — наличие подменённого header'а НЕ авторизует запрос
  (остаётся `Unauthenticated`, см. A-2c).

#### A-2f — internal listener'ы остаются строгим mTLS `[invariant / non-regression]`
- **Given** под-фаза меняет только external listener client-auth.
- **When** cluster-internal клиент (другой сервис/оператор) подключается к
  internal-listener'у gateway'я (:9091 и т.п.).
- **Then** internal listener по-прежнему `RequireAndVerifyClientCert` — cert обязателен;
  принципал-из-metadata доверяется только на этом verified hop'е. Никаких изменений
  поведения internal-listener'ов.

---

## 4. Decision-table — auth-источник principal (external listener)

| client-cert | Bearer JWT | x-kacho-principal-* header | Результат | Сценарий |
|---|---|---|---|---|
| нет | валидный | (стрипается) | JWT-principal | A-2a |
| валидный (internal CA) | нет | (стрипается) | cert-principal (SPIFFE SAN) | A-2b |
| валидный | валидный | (стрипается) | cert-principal (cert приоритетнее; JWT не обязателен) | A-2b |
| нет | нет | (стрипается) | `Unauthenticated` 401 | A-2c |
| forged/невалидный | любой | (стрипается) | TLS handshake reject | A-2d |
| нет | нет | подменён | `Unauthenticated` (header игнорится) | A-2c / A-2e |

> Примечание: при наличии и cert'а, и JWT приоритет — у verified-cert (cert уже
> hard-аутентифицировал транспорт). Это закрепляется тестом и не должно «случайно»
> зависеть от порядка middleware.

## 5. Decision-table — REST-mux backend dial (per edge)

| MTLS_<edge>_ENABLE | cert-материал | dial-creds | Результат |
|---|---|---|---|
| false (default) | любой | insecure | dev backward-compat (A-1c) |
| true | полный (cert+key+ca) | TLS client-cert + per-edge ServerName | mTLS dial (A-1a/A-1b) |
| true | частичный/пустой | — | fail-fast при старте (A-1d) |

---

## 6. Non-goals (явно вне scope)

- **Internal listener'ы НЕ трогаем** — остаются строгим `RequireAndVerifyClientCert`
  (A-2f). Под-фаза меняет только (а) REST-mux backend-dial creds и (б) external listener
  client-auth-режим.
- **Контракт API не меняется** — ни proto, ни REST-пути, ни форма ресурсов/ошибок.
  Это transport/security-уровень.
- **Новой cert-обвязки не создаём** — переиспользуем `mtls_config`-хелперы
  (`backendEdge` / `buildBackendDialCreds` / `EdgeTLSClient` / `grpcclient.TLSClientCreds`)
  и существующий per-edge config. Никаких новых env под REST-mux отдельно от SEC-E.
- **SEC-J JWKS/HMAC-dev path не переписываем** — hybrid-cert это новая ветвь ПЕРЕД
  JWT-fallback'ом; JWT-поведение остаётся как есть.
- **Авторизация (authz) не меняется** — под-фаза про authN-источник principal'а
  (cert vs JWT) и про транспортную mTLS. Per-RPC authz-gate (`InternalIAMService.Check`,
  listauthz) работает как прежде, независимо от того, cert- или JWT-principal.
- **Маппинг SPIFFE SAN → роли/permissions** на стороне IAM — вне scope (под-фаза только
  выводит cert-principal из SAN; что он может — решает существующий authz).
- **DPoP / mTLS-bound токены** (`middleware/dpop*`, `mtls_bound*`) — отдельная механика,
  под-фаза её не меняет.
- **Изменение OpsProxy/in-process loopback** — нет (остаётся insecure, A-1e).

---

## 7. Traceability — ground-truth якоря

| Артефакт | Файл / символ |
|---|---|
| Баг 503 (insecure opts на все Register*) | `internal/restmux/mux.go` ~`opts := []grpc.DialOption{grpc.WithTransportCredentials(insecure.NewCredentials())}` (~line 234), используется во всех `RegisterXServiceHandlerFromEndpoint(ctx, mux, <addr>, opts)`. |
| Backend-key set | `internal/restmux/mux.go` (`vpcAddr`/`vpcInternalAddr`/`computeAddr`/`computeInternalAddr`/`iamAddr`/`iamInternalAddr`/`lbAddr`/`lbInternalAddr`); `internal/config/config.go` `BackendAddrs()`. |
| Существующая mTLS-обвязка (переиспользовать) | `cmd/api-gateway/mtls_config.go` (`backendEdge`, `buildBackendDialCreds`, `dialBackends`, `iamEdgeDialCreds`, `loopbackDialCreds`). |
| Per-edge config + EdgeTLSClient | `internal/config/config.go` (`MTLS_{VPC,COMPUTE,IAM,NLB}_ENABLE`/`_SERVER_NAME`, `MTLSClient{Cert,Key}File`/`MTLSCAFile`, `EdgeTLSClient`, `edgeMTLS`, `BackendAddrs`). |
| TLS client-creds builder (corelib) | `kacho-corelib/grpcclient/tls.go` `TLSClientCreds(TLSClient)` (`ServerName` → SAN-check). |
| External TLS listener (текущий, без ClientAuth) | `cmd/api-gateway/main.go` ~line 483-507 (`tls.Config{Certificates, NextProtos, MinVersion}`, `tls.Listen`). |
| SEC-J JWT-path (fallback) | `internal/middleware/auth.go` (`authorize`, `HTTP`, `WithVerifier`, `principalFromVerifiedToken`, `isAsymmetricJWT`, `writeHTTPUnauthorized`). |
| Trust-инвариант (strip principal headers) | `internal/middleware/auth.go` `authorize()` (strip incoming md) + `HTTP()` (strip `X-Kacho-Principal-*` / `Grpc-Metadata-*`). |
| SPIFFE SAN формат | `spiffe://kacho.cloud/ns/<ns>/sa/<sa>` (SEC-G operator-cert; gateway SAN `…/ns/kacho-system/sa/kacho-api-gateway`). |

---

## 8. DoD (definition of done) — для последующих кодинг-тасков (НЕ часть APPROVED-gate, ориентир)

- **TDD RED→GREEN** на оба capability:
  - REST-mux: unit/bufconn-тест — при `enable=true` dial несёт TLS-creds + правильный
    ServerName (паритет с `cmd/api-gateway/mtls_dial_bufconn_test.go`); при `enable=false` —
    insecure; включённый edge без cert → fail-fast.
  - External listener: тест client-auth-режима — cert-клиент аутентифицируется по SPIFFE,
    no-cert+JWT → JWT, no-cert+no-JWT → 401, forged-cert → handshake reject, подменённый
    principal-header игнорируется.
- **Newman-кейс(ы)** (black-box через api-gateway): ≥1 happy (UI REST при mTLS-on → 200) +
  ≥1 negative (no-auth → 401).
- **Регрессия:** существующие newman зелёные при `enable=false`.
- **Helm/env (`kacho-deploy`):** включение REST-mux mTLS не требует новых per-edge env
  сверх SEC-E (тот же `MTLS_*`-блок); external-client-CA проброшен в gateway-chart.
- **Финальная верификация:** `go test ./... -race` + `golangci-lint run` + `govulncheck` +
  `make audit-list-filter` + newman зелёные.
- **Vault-trail:** обновить `edges/` (gateway→backend REST-mux mTLS; external-listener
  hybrid auth) + `KAC/KAC-<N>.md`.

---

## 9. Открытые вопросы (для reviewer'а)

- `OQ-1` Client-CA для external listener'а — переиспользуем `MTLS_CA_FILE` (тот же internal
  trust-anchor) или вводим явный `KACHO_API_GATEWAY_EXTERNAL_CLIENT_CA_FILE`? (Раздельный
  CA даёт независимый rollback hybrid-auth; общий — меньше конфигурации.) Default при пустом
  значении: `NoClientCert` (текущее, чтобы не сломать dev без internal-CA).
- `OQ-2` При наличии И cert'а, И JWT — фиксируем приоритет cert (раздел 4). Подтвердить, что
  это не ломает service→service сценарии, где сервис ходит с cert'ом И сервисным JWT.
- `OQ-3` Per-edge gating REST-mux dial обязан читать ТЕ ЖЕ `MTLS_*_ENABLE`, что
  director/authz (SEC-E) — подтвердить отсутствие отдельного REST-mux-флага (иначе drift:
  director mTLS, REST insecure → снова 503).
