# Sub-phase SEC-E — api-gateway backend-dial mTLS (JWT preserved) — Acceptance

> **Status**: DRAFT (awaiting `acceptance-reviewer` — gate per CLAUDE.md ban #1 / `.claude/rules/ai-tooling.md` §lifecycle gate 1).
> **Date**: 2026-06-11
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer` (single APPROVED gate; customer does NOT review the contract — only the final smoke/e2e per §DoD).
> **Epic**: [`sub-phase-SEC-mtls-iam-authz-epic.md`](./sub-phase-SEC-mtls-iam-authz-epic.md) — подфаза **SEC-E**, table §4.
> **Epic ticket / KAC**: KAC-`<SEC-E>` (subtask of the SEC epic; created by the controller after this doc reaches APPROVED).
> **Target repo (primary)**: `PRO-Robotech/kacho-api-gateway`.
> **Touched (verification only, no prod code change)**: `kacho-corelib` (consumes the TLS-creds helpers landed in SEC-B), `kacho-iam` (mTLS server side comes from SEC-C/SEC-D; SEC-E is the client side of those edges).
> **Depends on (epic §4)**: **SEC-B** (corelib `grpcclient` TLS client-creds + `TLSClient{enable,cert_file,key_file,ca_files,server_name}` config struct, epic §3.2) and **SEC-C** (kacho-iam mTLS **server** side present on its listeners so the gateway has an mTLS peer to dial). SEC-D supplies the vpc/compute/nlb mTLS server side; until SEC-D is merged the gateway→vpc / gateway→compute / gateway→nlb edges are exercised with their own `enable=false` per-edge flag (see §2.2, §3.9).
> **Branch (all repos)**: `KAC-<SEC-E>`.

---

## Обзор

SEC-E переключает **исходящий backend-dial** api-gateway с `insecure.NewCredentials()` на
**mTLS client-cert** идентичности модуля «api-gateway» (epic requirement #3, decision §6.4),
управляемый **per-edge feature-флагом** (decision §6.5, rollback-safe). JWT-аутентификация
конечного пользователя (Hydra JWKS / dev HMAC) и principal-propagation (`x-kacho-principal-*`
в metadata) **не меняются** (#7) — mTLS оборачивает только транспорт, principal-слой идёт
поверх и ортогонален (epic «Инвариант доверия I2»). Каждый non-allowlisted запрос
по-прежнему проходит `InternalIAMService.Check` (#3 — уже на месте, SEC-E лишь подтверждает,
что mTLS не ломает этот вызов). External-сторона (ingress TLS, где терминируется JWT) и
правило «Internal.* не на external endpoint» (ban #6) **не трогаются**. `enable=false` (default)
= текущее insecure-поведение; подфаза мёржится в `main` без поломки dev-стенда.

---

## 0. Точка отсчёта (факты разведки, HEAD `main`, 2026-06-11)

Точные пути/строки — чтобы ревьюер мог отследить дрейф.

### 0.1 Backend-dial сегодня — insecure, в одной общей `dialOpts`

- `cmd/api-gateway/main.go:77-85` — одна общая `dialOpts` с
  `grpc.WithTransportCredentials(insecure.NewCredentials())` + keepalive (10s/3s,
  `PermitWithoutStream`) + round-robin service-config. Применяется в цикле
  `cmd/api-gateway/main.go:88-95` ко **всем** backend-ClientConn из `cfg.BackendAddrs()`
  (ключи: `vpc`, `vpcInternal`, `compute`, `computeInternal`, `iam`, `iamInternal`,
  `loadbalancer`, `loadbalancerInternal` — `internal/config/config.go:268-279`).
- `cmd/api-gateway/main.go:106-115` — `opsLoopback` ClientConn для домена `operation` дилит
  **сам api-gateway** (`127.0.0.1:8080`, `cfg.ListenAddr`) той же `dialOpts`. Это
  in-process self-loopback (yc-shim Operation rewrite), **НЕ** cross-pod ребро — mTLS на него
  не распространяется (см. §2.3, §3.7).
- Два отдельных dial вне общей карты, тоже insecure:
  - `internal/clients/iam_subject_client.go:45-47` (`NewIAMSubjectClient` → `iam:9091`
    InternalIAMService.LookupSubject/UpsertFromIdentity для auth-interceptor).
  - `internal/clients/iam_authorize_client.go:163-165` (`NewIAMAuthorizeClient` →
    iam AuthorizeService.Check для list-filter authz).

**Итого 4 production dial-площадки** (общая backends-карта, iam-subject, iam-authorize,
opsLoopback). Площадки 1-3 — реальные cross-pod рёбра → переводятся на mTLS per-edge.
Площадка 4 (opsLoopback) — in-process → остаётся insecure (внутри pod, не пересекает сеть).

### 0.2 JWT-верификация и principal-propagation — уже на месте, НЕ трогаем (#7)

- JWT verify: `internal/middleware/jwt_verifier.go` (Hydra JWKS, alg-whitelist, iss/aud/exp)
  + dev HMAC через `AuthNDevSecret` (`internal/config/config.go:81-84`); включается флагом
  `KACHO_API_GATEWAY_AUTHN_ENABLE_DPOP` / `AuthNMode`. Всё на **входящей** (external) стороне.
- principal → metadata: auth-interceptor выставляет `x-kacho-principal-{type,id,display-name}`
  на outgoing-ctx; director (`internal/proxy/director.go:54-57`) пробрасывает входящие
  metadata как исходящие (`metadata.FromIncomingContext` → `metadata.NewOutgoingContext`).
  Это и есть слой, который должен пережить mTLS (§3.5, §3.6).
- Стрип клиентских `x-kacho-principal-*` на входе (anti-spoof, KAC-122 CRIT-8) — на external
  стороне, SEC-E не касается; подтверждаем неизменность (§3.10).

### 0.3 mTLS-bound (RFC 8705) ≠ backend-dial mTLS — НЕ путать

- `internal/middleware/mtls_bound.go` — RFC 8705 cert-bound **access tokens** (`cnf.x5t#S256`):
  это про **клиент↔gateway** external TLS и привязку JWT к клиентскому сертификату. Слой
  аутентификации пользователя/M2M-клиента. SEC-E про **gateway↔backend** транспорт. Две
  разные вещи; SEC-E `mtls_bound.go` не трогает (§5).

### 0.4 Per-RPC authz Check — уже вызывается (#3 частично есть)

- Каждый non-allowlisted публичный RPC проходит authz-middleware
  (`internal/middleware/authz.go:665` → `Checker.Check(ctx, AuthzCheckInput{...})` →
  `InternalIAMService.Check` через iam-authorize/subject клиентов). Public-allowlist
  (login/register/recovery/health/reflection/Internal-exempt) — `authz_public_allowlist.go`.
  SEC-E **не меняет** логику Check; подтверждает, что Check продолжает срабатывать поверх
  mTLS-транспорта (§3.4, §3.6).

### 0.5 Internal-vs-external — listener-уровень, mTLS его усиливает (ban #6)

- `internal/proxy/director.go:29` + `internal/proxy/server.go:30` — `HasInternalSuffix(method)`
  блокирует `*InternalService.*` на публичном director'е; `allowlist.IsAllowed` — whitelist.
  SEC-E mTLS — на dial-стороне; ban #6-инвариант (Internal.* не маршрутизируется на external)
  остаётся как есть. Подтверждаем неизменность (§3.8).

---

## 1. Что меняется (по файлам)

> Только внешне-наблюдаемое поведение и публичная конфигурация. Внутренняя реализация
> (структуры, helper-сигнатуры) — забота `rpc-implementer` / `go-style-reviewer`; здесь —
> контракт конфигурации и поведение на сети.

### 1.1 `internal/config/config.go` — per-edge mTLS-конфиг

Новые env-переменные (naming per `00-kacho-core.md`: `KACHO_API_GATEWAY_*`), все
**default = выключено / пусто** (backward-compat). Контракт значений (точные имена
финализируются вместе с SEC-B `TLSClient`-струкурой, но семантика фиксируется здесь):

| Env | Назначение | Default |
|---|---|---|
| `KACHO_API_GATEWAY_MTLS_CLIENT_CERT_FILE` | PEM client-cert идентичности «api-gateway» (SAN = `spiffe://kacho/<sva-id>`, epic §3.3/§6.3) | `""` |
| `KACHO_API_GATEWAY_MTLS_CLIENT_KEY_FILE` | PEM private key client-cert | `""` |
| `KACHO_API_GATEWAY_MTLS_CA_FILE` | PEM internal-CA bundle для верификации server-cert backend'ов | `""` |
| `KACHO_API_GATEWAY_MTLS_VPC_ENABLE` | per-edge: mTLS на dial к vpc (`vpc` + `vpcInternal`) | `false` |
| `KACHO_API_GATEWAY_MTLS_COMPUTE_ENABLE` | per-edge: mTLS на dial к compute (`compute` + `computeInternal`) | `false` |
| `KACHO_API_GATEWAY_MTLS_IAM_ENABLE` | per-edge: mTLS на dial к iam (`iam`, `iamInternal`, iam-subject :9091, iam-authorize) | `false` |
| `KACHO_API_GATEWAY_MTLS_NLB_ENABLE` | per-edge: mTLS на dial к nlb (`loadbalancer` + `loadbalancerInternal`) | `false` |
| `KACHO_API_GATEWAY_MTLS_<EDGE>_SERVER_NAME` | override SNI/server-name для верификации SAN backend-cert (per edge; пусто → derive из dial-addr host) | `""` |

- `enable=true` для ребра при пустых cert/key/ca → **fail-fast при старте** (`log.Fatalf`),
  НЕ тихий fallback на insecure (epic fail-closed §6.7). Контракт: «включил mTLS без
  материала → процесс не стартует», а не «деградировал до insecure».

### 1.2 `cmd/api-gateway/main.go` — per-edge dial-creds

- Backend-цикл (`main.go:88-95`) выбирает creds **по ребру** домена: для каждого backend-ключа
  (`vpc`/`vpcInternal`/`compute`/…) — если соответствующий `MTLS_<EDGE>_ENABLE=true` → TLS
  client-creds из SEC-B (`grpcclient.TLSClient{…}`), иначе `insecure.NewCredentials()`.
- iam-subject (`NewIAMSubjectClient`) и iam-authorize (`NewIAMAuthorizeClient`) — оба под
  `MTLS_IAM_ENABLE` (это рёбра gateway→iam).
- `opsLoopback` (`main.go:106-115`) — **всегда insecure** (in-process self-loopback; §3.7).
- keepalive / round-robin / principal-MD propagation — без изменений.

### 1.3 corelib — потребление, без нового кода в SEC-E

SEC-E **использует** `grpcclient.TLSClient` creds-конструктор из SEC-B (epic §3.2). Если
SEC-B по какой-то причине не покрыл нужную форму (per-edge server-name) — это дефект SEC-B,
заводится отдельным KAC, не реализуется в gateway локально (ban #11 «no tech-debt», corelib
горизонталь — `architecture.md`).

### 1.4 НЕ меняется

- `internal/middleware/*` (JWT verify, DPoP, mtls_bound, authz Check, subject extract,
  principal inject, anti-spoof strip).
- `internal/allowlist/list.go`, `internal/proxy/director.go` логика маршрутизации, ban #6.
- External TLS listener (`TLSListenAddr`/`TLSCertFile`/`TLSKeyFile`, `config.go:30-32`,199).
- proto / `kacho-proto` — нет нового RPC/поля.

---

## 2. Объём / границы

### 2.1 В объёме
Per-edge mTLS client-creds на исходящих dial api-gateway → vpc / compute / iam / nlb (public
:9090 и internal :9091 порты), включаемые независимыми флагами; fail-fast при misconfig;
сохранение JWT-флоу, principal-propagation и per-RPC Check поверх mTLS.

### 2.2 Не в объёме (delegated)
- mTLS **server**-сторона backend'ов (vpc/compute/nlb — SEC-D; iam — SEC-C). SEC-E — только
  клиент. До мёржа server-стороны соответствующее ребро держим `enable=false`; positive-mTLS
  e2e для ребра гоняется, когда обе стороны включены (§3.9 описывает edge-mismatch контракт).
- cert-manager PKI, Certificate-ресурсы ×2, helm mTLS-values, SA-seed, FGA NetworkPolicy — SEC-F.
- Внесение `api-gateway` SA least-priv роли в IAM — SEC-C/SEC-F (gateway authz по JWT
  пользователя, не по cert — epic §3.3 «api-gateway: identity для mTLS, но authz — по JWT»).
- Hot-reload cert по file-watch — позже (epic §6.2 restart-on-rotate для MVP).
- Изменение FGA-доступа / RegisterResource — SEC-A/C/D, не gateway.

### 2.3 opsLoopback
`operation`-домен дилит сам gateway (in-process). Не cross-pod, mTLS не нужен; остаётся
insecure явно и навсегда в этом контексте.

---

## 3. Сценарии (Given-When-Then)

> Карта покрытия: §3.1-3.2 — конфиг/старт; §3.3 — insecure default (dev backward-compat);
> §3.4 — Check поверх mTLS (happy e2e, #3); §3.5-3.6 — principal-propagation поверх mTLS (#7,I2);
> §3.7 — opsLoopback insecure; §3.8 — ban #6; §3.9 — per-edge rollback / edge-mismatch (#6.5,fail-closed);
> §3.10 — anti-spoof неизменность; §3.11-3.12 — negative misconfig / cert-reject; §3.13 — newman.

### 3.1 Scenario SEC-E-01 — mTLS выключен по умолчанию (insecure, dev backward-compat)

**ID**: SEC-E-01

**Given**
- ни одна `KACHO_API_GATEWAY_MTLS_*_ENABLE` не выставлена (все default `false`);
- `KACHO_API_GATEWAY_MTLS_CLIENT_CERT_FILE` / `_KEY_FILE` / `_CA_FILE` пусты.

**When** api-gateway стартует (`config.Load()` + backend-dial цикл).

**Then** все backend-ClientConn (`vpc`/`compute`/`iam`/`nlb` + internal-порты) и iam-subject /
iam-authorize клиенты дилятся с `insecure.NewCredentials()` — поведение **идентично** текущему
`main` (epic DoD «enable=false — dev работает как сейчас»).

**And** процесс стартует без ошибок; health-probe (`grpc.health.v1.Health/Check`) отвечает.

**And** существующий dev-стенд (`make dev-up`) поднимается, newman-suite зелёный (no regression).

### 3.2 Scenario SEC-E-02 — mTLS включён для ребра с полным cert-материалом → старт ОК

**ID**: SEC-E-02

**Given**
- `KACHO_API_GATEWAY_MTLS_CLIENT_CERT_FILE`, `_KEY_FILE`, `_CA_FILE` указывают на валидные
  PEM-файлы (client-cert SAN = `spiffe://kacho/<api-gateway-sva-id>`, internal-CA bundle);
- `KACHO_API_GATEWAY_MTLS_IAM_ENABLE=true` (остальные рёбра `false`).

**When** api-gateway стартует.

**Then** ClientConn'ы для домена `iam` (`iam`, `iamInternal`) **и** iam-subject (:9091) **и**
iam-authorize дилятся с TLS client-creds (cert+key+CA+server-name); ClientConn'ы `vpc`/`compute`/
`nlb` остаются insecure (их флаги `false`).

**And** процесс стартует без `log.Fatalf`.

### 3.3 Scenario SEC-E-03 — mTLS включён без cert-материала → fail-fast (не тихий insecure)

**ID**: SEC-E-03

**Given** `KACHO_API_GATEWAY_MTLS_IAM_ENABLE=true`, но `KACHO_API_GATEWAY_MTLS_CLIENT_CERT_FILE`
(или `_KEY_FILE`, или `_CA_FILE`) пуст / файл не существует / PEM невалиден.

**When** api-gateway стартует.

**Then** процесс завершается с ненулевым кодом и сообщением вида
`mtls iam enabled but client cert/key/ca missing or invalid` (fail-closed, epic §6.7).

**And** процесс **НЕ** дилит iam insecure-fallback'ом (нет тихой деградации до insecure при
включённом mTLS — это и есть гарантия безопасности контракта).

### 3.4 Scenario SEC-E-04 — happy path e2e: пользовательский Create через mTLS-backend, Check проходит (#3)

**ID**: SEC-E-04

**Given**
- Полный стенд в mTLS-профиле: api-gateway (`MTLS_VPC_ENABLE=true`, `MTLS_IAM_ENABLE=true`) +
  kacho-vpc (mTLS server, SEC-D) + kacho-iam (mTLS server, SEC-C) + OpenFGA + Postgres;
- `AuthNMode=production` (или `dev` с валидным HMAC), AuthZ включён (`AUTHZ_ENABLED=true`,
  `AUTHZ_FAIL_OPEN=false`);
- пользователь `usr_alice` с валидным JWT владеет проектом `prj_a` (AccessBinding +
  FGA owner-tuple применён).

**When** alice делает `POST /vpc/v1/networks` (REST) с телом `{ "projectId": "prj_a",
"name": "net-mtls-01" }` и `Authorization: Bearer <alice JWT>`.

**Then** последовательно и наблюдаемо:
1. gateway верифицирует JWT (Hydra JWKS / dev HMAC) → principal `user:usr_alice` (#7, без изменений);
2. gateway выставляет `x-kacho-principal-{type=user,id=usr_alice,display-name=...}` в metadata;
3. authz-middleware зовёт `InternalIAMService.Check(subject=user:usr_alice,
   relation=vpc.networks.create, object=project:prj_a)` **через mTLS-канал к iam** → `allowed=true`;
4. director дилит vpc **по mTLS** (TLS-handshake с client-cert «api-gateway», верификация
   server-cert vpc по internal-CA);
5. vpc выполняет project-ownership Check (видит `user:usr_alice` из propagated metadata) → проходит.

**And** ответ — `200 OK` с `Operation` (мутация async, `api-conventions.md`); полл
`OperationService.Get(opId)` → `done=true && !error`; затем `GET /vpc/v1/networks/{id}` отдаёт
Network с заполненными `id`, `createdAt`, `projectId=prj_a`, `name=net-mtls-01`.

**And** mTLS-handshake-метрики/логи показывают peer-cert идентичности `api-gateway` для
backend-соединений (cert-identity модуля логируется — epic I2).

### 3.5 Scenario SEC-E-05 — principal-propagation переживает mTLS (#7, инвариант I2)

**ID**: SEC-E-05

**Given**
- api-gateway с `MTLS_VPC_ENABLE=true`, dialит vpc-backend-stub (mTLS server, записывает
  incoming metadata и peer-cert SAN);
- валидный JWT для `usr_alice` → principal выставлен на ctx + metadata.

**When** запрос `GET /vpc/v1/networks/enp_xxx` проходит gateway → vpc-stub по mTLS.

**Then** vpc-stub фиксирует на проводе **одновременно**:
- TLS peer-cert с SAN/CN = идентичность «api-gateway» (mTLS-слой);
- gRPC metadata `x-kacho-principal-type=user`, `x-kacho-principal-id=usr_alice`,
  `x-kacho-principal-display-name=<...>` (principal-слой, поверх mTLS, не затёрт).

**And** оба слоя ортогональны: cert идентифицирует **модуль**, metadata — **пользователя**
(epic «Инвариант доверия I2»). Ни один не подменяет другой.

### 3.6 Scenario SEC-E-06 — anonymous-в-dev пробрасывается поверх mTLS без изменений

**ID**: SEC-E-06

**Given** api-gateway `AuthNMode=dev`, `MTLS_VPC_ENABLE=true`, запрос без Bearer (anonymous-в-dev).

**When** `GET /vpc/v1/networks/enp_xxx` проходит gateway → vpc по mTLS.

**Then** backend получает metadata `x-kacho-principal-type=system`, `x-kacho-principal-id=anonymous`
(существующее gateway anonymous-injection-поведение; SEC-E его сохраняет) — mTLS не меняет
семантику anonymous-в-dev.

**And** в `AuthNMode=production` тот же запрос без Bearer → `401 Unauthenticated` **на входе
gateway** (до backend-dial); mTLS-слой не достигается (auth раньше транспорта). Подтверждает,
что mTLS не ослабляет и не усиливает JWT-гейт.

### 3.7 Scenario SEC-E-07 — opsLoopback (operation-домен) остаётся insecure

**ID**: SEC-E-07

**Given** api-gateway с **любыми** `MTLS_*_ENABLE=true` (например все включены).

**When** приходит `GET` к `OperationService.Get` (yc-shim путь, переписываемый на
`kacho.cloud.operation.OperationService/Get` и дилимый через `opsLoopback` на сам gateway).

**Then** `opsLoopback` дилит `127.0.0.1:8080` (себя) с `insecure.NewCredentials()` —
in-process self-loopback не оборачивается в mTLS (нет cross-pod границы).

**And** `OperationService.Get` отвечает корректно (фан-аут OpsProxy по domain-prefix не сломан
включённым backend-mTLS).

### 3.8 Scenario SEC-E-08 — Internal.* не маршрутизируется на external (ban #6, неизменно)

**ID**: SEC-E-08

**Given** api-gateway в mTLS-профиле (`MTLS_VPC_ENABLE=true`, `MTLS_IAM_ENABLE=true`).

**When** внешний клиент пытается вызвать `/kacho.cloud.vpc.v1.InternalAddressPoolService/List`
(или любой `Internal*Service.*`) через публичный gRPC-director.

**Then** ответ `NOT_FOUND` («unknown method») — `HasInternalSuffix` блокирует на director'е
до выбора backend-creds (поведение из §0.5 неизменно; mTLS на dial-стороне его не ослабляет).

**And** mTLS на backend-dial **не открывает** Internal.* на external endpoint — изоляция была
и остаётся на listener/director-уровне (ban #6).

### 3.9 Scenario SEC-E-09 — per-edge rollback: одно ребро mTLS, другое insecure, независимо

**ID**: SEC-E-09

**Given**
- api-gateway `MTLS_IAM_ENABLE=true`, `MTLS_VPC_ENABLE=false`;
- kacho-iam — mTLS server (SEC-C, требует client-cert); kacho-vpc — ещё insecure (SEC-D не смёржен).

**When** проходят два запроса: (a) пользовательский поток, требующий `iam.Check` (любой
non-allowlisted RPC); (b) `GET /vpc/v1/networks/enp_xxx`.

**Then**
- (a) gateway→iam — успешный mTLS-handshake, Check отрабатывает;
- (b) gateway→vpc — insecure-dial к insecure vpc → запрос проходит (рёбра независимы).

**And** обратная конфигурация-рассинхрон (epic §6.5 «mismatch → Unavailable»): если
`MTLS_VPC_ENABLE=true`, а vpc **insecure** (server без TLS) → gateway→vpc TLS-handshake падает
→ запрос получает `UNAVAILABLE` (fail-closed, не тихий plaintext-fallback). Детектируется
per-edge на e2e.

### 3.10 Scenario SEC-E-10 — anti-spoof стрип клиентского principal-header неизменен (verification)

**ID**: SEC-E-10

**Given** api-gateway в mTLS-профиле; вредоносный REST-клиент шлёт
`GET /vpc/v1/networks/enp_xxx` с `Authorization: Bearer <usr_alice>` **и** подделанным
`X-Kacho-Principal-Id: usr_admin`.

**When** gateway обрабатывает запрос.

**Then** gateway стрипает клиентский `X-Kacho-Principal-*` (KAC-122 CRIT-8), резолвит principal
из Bearer (`usr_alice`), и backend по mTLS получает `x-kacho-principal-id=usr_alice` (не
`usr_admin`).

**And** mTLS не вводит нового «trust client header»-канала: cert идентифицирует модуль,
не пользователя; подделка principal по-прежнему невозможна (epic I2 + defense-in-depth).

### 3.11 Scenario SEC-E-11 — backend предъявляет cert не из internal-CA → handshake reject (negative)

**ID**: SEC-E-11

**Given** api-gateway `MTLS_VPC_ENABLE=true` с internal-CA bundle `CA_FILE`; vpc-backend-stub
предъявляет server-cert, подписанный **посторонним** CA (не internal-CA).

**When** gateway дилит vpc и отправляет первый RPC.

**Then** TLS-handshake падает на верификации цепочки server-cert → RPC завершается
`UNAVAILABLE` (fail-closed). gateway **НЕ** принимает untrusted backend и **НЕ** деградирует
до insecure.

**And** для мутации (`Create`/`Update`/`Delete`) клиент видит `UNAVAILABLE` (epic §6.7,
`data-integrity.md` cross-domain fail-closed) — не частичный успех, не plaintext.

### 3.12 Scenario SEC-E-12 — backend требует client-cert, gateway его не шлёт → reject (negative)

**ID**: SEC-E-12

**Given** vpc-backend-stub настроен `RequireAndVerifyClientCert` (epic §3.2 server side);
api-gateway по ошибке конфигурации дилит vpc **insecure** (`MTLS_VPC_ENABLE=false` при mTLS-only backend).

**When** gateway отправляет RPC к vpc.

**Then** backend отвергает соединение (нет client-cert) → RPC `UNAVAILABLE`. Это симметрия
edge-mismatch из §3.9; контракт — fail-closed, наблюдаемый per-edge на e2e (никакого молчаливого
прохода без mTLS, когда backend его требует).

### 3.13 Scenario SEC-E-13 — newman happy + negative через mTLS-стенд

**ID**: SEC-E-13

**Given** newman-suite запускается против стенда в mTLS-профиле (gateway `MTLS_IAM_ENABLE=true`
+ `MTLS_VPC_ENABLE=true`, backend'ы — mTLS server).

**When** выполняется кейс `SEC-E-GATEWAY-MTLS-A` (happy): авторизованный
`POST /vpc/v1/networks` (как §3.4) → 200 + Operation → полл до done → `GET` ресурса.

**Then** кейс зелёный; ответ идентичен insecure-профилю (mTLS прозрачен для REST-контракта —
тот же JSON, те же коды, camelCase-поля).

**And** negative-кейс `SEC-E-GATEWAY-MTLS-NEG-A`: запрос на ресурс чужого проекта (как
cross-tenant deny) → `403 PermissionDenied` (Check сработал поверх mTLS, не открылся из-за
транспортного слоя).

**And** контроль ban #6: `GET /vpc/v1/addressPools` (Internal-ресурс) через **external**
endpoint → не доступен (kacho-only internal, как и в insecure-профиле).

---

## 4. Definition of Done (подфаза SEC-E)

- [ ] **Конфиг**: per-edge mTLS env-переменные (§1.1) добавлены в `internal/config/config.go`
      с default'ами «выкл/пусто»; `enable=true` без cert-материала → fail-fast (§3.3).
- [ ] **Dial**: `cmd/api-gateway/main.go` выбирает creds per-edge (TLS из SEC-B `grpcclient.TLSClient`
      vs insecure); iam-subject + iam-authorize под `MTLS_IAM_ENABLE`; `opsLoopback` всегда insecure (§1.2, §3.7).
- [ ] **JWT / principal / Check — не изменены**: код `internal/middleware/*` и
      `internal/allowlist/*` не тронут; verification-тесты §3.5/§3.6/§3.10 подтверждают.
- [ ] **TDD RED→GREEN** (ban #12, `testing.md`): для каждого нового поведения сначала падающий
      тест, потом код. Пара RED→GREEN в PR-описании для: config fail-fast, per-edge creds-выбор,
      principal-поверх-mTLS, edge-mismatch fail-closed.
- [ ] **Integration-тесты** (Go, in-memory TLS через bufconn + сгенерённые тестовые cert/CA,
      без docker где возможно) — список §6.
- [ ] **Newman**: `SEC-E-GATEWAY-MTLS-A` (happy) + `SEC-E-GATEWAY-MTLS-NEG-A` (negative)
      добавлены в `tests/newman/cases/` (`validate-cases.py` → `gen.py`), зелёные на mTLS-стенде.
- [ ] **e2e (заказчик, §7 канона)**: на стенде в mTLS-профиле — пользовательский Create через
      gateway (`make e2e-test` / `grpcurl`) проходит JWT → principal → mTLS-dial → Check (§3.4);
      `enable=false` → стенд работает как dev (§3.1).
- [ ] **Финальная верификация** (`ai-tooling.md` gate 7): `go test ./... -race` +
      `golangci-lint run` + `govulncheck` + `make audit-list-filter` + newman зелёные.
- [ ] **Ревью**: `go-style-reviewer` (thin handlers, ctx, no panic) + `system-design-reviewer`
      (fail-closed на edge-mismatch, per-edge rollback). Public proto breaking-diff = 0 (proto не трогали).
- [ ] **Vault-trail**: `obsidian/kacho/KAC/KAC-<SEC-E>.md` создан (PR-URL, DoD, status);
      `edges/api-gateway-to-iam-authorize.md` + `edges/api-gateway-to-iam-subject-change.md` —
      History-запись «SEC-E: backend-dial → mTLS client-cert, per-edge `MTLS_IAM_ENABLE`»;
      новая узкая записка `packages/api-gateway-backend-dial-mtls.md` (per-edge creds-выбор).
- [ ] **Тикет**: KAC-`<SEC-E>` → Test → Done с артефактами (PR-URL, лог тестов, e2e-вывод).

---

## 5. Out of scope (повтор для ясности)

- mTLS server-сторона backend'ов (vpc/compute/nlb — SEC-D; iam — SEC-C). SEC-E — клиент.
- cert-manager PKI / Certificate ×2 / helm mTLS-values / SA-seed / FGA NetworkPolicy — SEC-F.
- vpc/compute прямой FGA → IAM-proxy outbox-relay — SEC-D (gateway уже ходит в IAM, не в FGA).
- Hot-reload cert по file-watch — позже (restart-on-rotate MVP, epic §6.2).
- RFC 8705 cert-bound tokens (`mtls_bound.go`) — слой клиент↔gateway, не backend-dial (§0.3).
- Изменение JWT-верификации, DPoP, authz-Check-логики, allowlist, anti-spoof-стрипа (#7,#8).
- `api-gateway` SA least-priv роль в IAM — gateway авторизует по JWT пользователя, не по cert
  (epic §3.3); роль SA — SEC-C/SEC-F.

---

## 6. Тесты для подтверждения сценариев (TDD-red список)

> Integration — Go (`cmd/api-gateway`, `internal/clients`, `internal/proxy`) с in-memory
> TLS (bufconn + сгенерённые ephemeral cert/CA в тесте), без внешних зависимостей где можно.
> Newman — black-box через api-gateway на mTLS-стенде.

**Integration (RED first):**
1. `cmd/api-gateway/mtls_config_test.go::TestMTLS_DefaultDisabled_AllInsecure` → §3.1.
2. `…::TestMTLS_IAMEnabled_FullCert_StartsOK` → §3.2.
3. `…::TestMTLS_Enabled_MissingCert_FailFast` → §3.3 (assert `Load`/wiring возвращает ошибку,
   не insecure-fallback).
4. `…::TestMTLS_PerEdgeCredsSelection` → §3.2/§3.9 (vpc insecure, iam mTLS одновременно).
5. `internal/proxy/director_mtls_test.go::TestDirector_PropagatesPrincipalMD_OverMTLS` →
   §3.5 (bufconn TLS server-stub фиксирует peer-cert SAN + `x-kacho-principal-*`).
6. `…::TestDirector_AnonymousDev_PropagatedOverMTLS` → §3.6.
7. `cmd/api-gateway/mtls_loopback_test.go::TestOpsLoopback_AlwaysInsecure` → §3.7.
8. `internal/proxy/director_internal_block_mtls_test.go::TestInternalSuffix_BlockedUnderMTLS` → §3.8.
9. `…::TestEdge_MTLSClient_vs_InsecureServer_FailsClosed` → §3.9/§3.12 (handshake fail → Unavailable).
10. `…::TestBackendCert_UntrustedCA_Rejected` → §3.11 (server-cert вне internal-CA → Unavailable).
11. `internal/middleware/anti_spoof_mtls_test.go::TestClientPrincipalHeader_StrippedUnderMTLS` →
    §3.10 (verification, ожидается уже-зелёным если поведение неизменно; иначе finding).
12. `cmd/api-gateway/mtls_check_test.go::TestCheck_StillCalled_OverMTLS_IAM` → §3.4 (Check
    срабатывает на non-allowlisted RPC при `MTLS_IAM_ENABLE=true`; allowlisted — пропускается).

**Newman (RED first):**
13. `tests/newman/cases/sec_e_gateway_mtls.py` — кейс `SEC-E-GATEWAY-MTLS-A` (happy, §3.4/§3.13).
14. там же — `SEC-E-GATEWAY-MTLS-NEG-A` (cross-tenant 403 поверх mTLS, §3.13).
15. там же / существующий — контроль `GET /vpc/v1/addressPools` через external недоступен (ban #6, §3.8/§3.13).

---

## 7. Traceability — сценарий → требование эпика / решение

| Сценарий | Эпик req / decision |
|---|---|
| SEC-E-01 (insecure default) | #1 (opt-in, не ломает dev); DoD «enable=false как сейчас»; §6.5 |
| SEC-E-02 (full cert → старт) | #1, #5 (раздельный client-cert); §3.2 |
| SEC-E-03 (fail-fast misconfig) | §6.7 (fail-closed); #1 (не тихая деградация) |
| SEC-E-04 (happy e2e + Check) | #3 (внешний JWT + IAM authz; service→service mTLS); §6.4 |
| SEC-E-05 (principal поверх mTLS) | #7 (JWT сохранён); I2 (principal ⊥ cert) |
| SEC-E-06 (anonymous-в-dev) | #7; #1 (dev backward-compat) |
| SEC-E-07 (opsLoopback insecure) | §6.4 (backend-dial mTLS — про cross-pod рёбра) |
| SEC-E-08 (ban #6) | #8 (контракты не меняются); security.md ban #6 |
| SEC-E-09 (per-edge rollback) | §6.5 (per-edge flag, independent enable, mismatch→Unavailable) |
| SEC-E-10 (anti-spoof неизменен) | #7; I2; defense-in-depth |
| SEC-E-11 (untrusted CA reject) | §6.7 (fail-closed); #5 (CA-верификация) |
| SEC-E-12 (client-cert required) | §6.5/§6.7 (edge-mismatch fail-closed) |
| SEC-E-13 (newman happy+neg) | #3, #8; testing.md (≥1 happy + ≥1 negative) |

---

## 8. Открытые вопросы

| ID | Вопрос | Рекомендация |
|---|---|---|
| OQ-SEC-E-1 | Точные имена env (`MTLS_<EDGE>_ENABLE` vs reuse SEC-B `TLSClient`-struct-полей напрямую)? | Согласовать с SEC-B на review; семантика (per-edge enable + общий cert/key/ca) зафиксирована здесь, имена — деталь реализации, не контракт поведения. |
| OQ-SEC-E-2 | `MTLS_<EDGE>_SERVER_NAME` per-edge override vs derive из dial-host? | Default — derive из host dial-адреса (`<svc>.kacho.svc…`); override нужен только если SAN cert ≠ DNS-имя. Решает SEC-F (cert-manager SAN). |
| OQ-SEC-E-3 | iam-subject и iam-authorize — один `MTLS_IAM_ENABLE` или раздельные? | Один (оба — ребро gateway→iam, одна backend-идентичность). Раздельный split — преждевременная гранулярность. |
| OQ-SEC-E-4 | Нужен ли отдельный `MTLS_OPERATION_ENABLE`? | Нет — opsLoopback in-process, mTLS неприменим (§2.3, §3.7). Явно НЕ добавлять флаг. |
