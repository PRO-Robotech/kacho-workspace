# Sub-phase SEC-I — CLIENT mTLS на read/authz рёбрах `*→kacho-iam` (vpc / compute / nlb)

> **Статус:** DRAFT (на ревью `acceptance-reviewer` — единственный gate APPROVED, ban #1)
> **Дата:** 2026-06-12
> **Type:** acceptance (Given-When-Then), markdown-only, без кода
> **Эпик:** SEC (cluster-internal mTLS mesh). Предшественники: SEC-B (corelib
> `grpcclient.TLSClient`), SEC-D (per-edge mTLS config + register-drainer edge),
> SEC-F (cert-manager internal-CA PKI), SEC-H (`kacho-iam` server-side
> `RequireAndVerifyClientCert` на обоих listener'ах).
> **Репозитории:** `kacho-vpc`, `kacho-compute`, `kacho-nlb`, `kacho-deploy`
> (helm + wiring-тест). **Без** `kacho-proto` / `kacho-corelib` / `kacho-api-gateway`
> изменений (см. §«Non-goals»).

---

## 0. Контекст и постановка (ground truth)

SEC-H включает на `kacho-iam` серверный `tls.RequireAndVerifyClientCert` (corelib
`grpcsrv`) на **обоих** listener'ах (public :9090 — `ProjectService`/`AuthorizeService`;
internal :9091 — `InternalIAMService.{Check,RegisterResource,UnregisterResource}`). После
этого **любой** gRPC-dial в `kacho-iam` без предъявленного клиентского сертификата падает на
TLS-handshake (`tls: first record does not look like a TLS handshake` для plaintext-клиента,
либо `bad certificate` для cert-less). Значит **каждое** ребро `*→kacho-iam` должно
предъявлять client-cert ДО включения SEC-H, иначе стенд ляжет.

SEC-D уже закрыл **одно** ребро каждого сервиса — `register-drainer`
(`InternalIAMService.RegisterResource/UnregisterResource`) — через corelib-примитив
`grpcclient.TLSClient` + per-edge env `KACHO_<SVC>_IAM_REGISTER_MTLS_*`. **SEC-I — это
зеркало того же паттерна на ОСТАВШИХСЯ read/authz рёбрах `*→iam`.** Никакого нового
дизайна: тот же `grpcclient.TLSClientCreds`/`TLSClientTransportCreds`, тот же уже
смонтированный client-cert secret `kacho-<svc>-client-tls`, тот же helm-gating
`mtls.edges.*` + `mtls.serverName.*`.

### Примитив (существует, SEC-B — НЕ меняем)

`kacho-corelib/grpcclient/tls.go`:
`type TLSClient { Enable bool; CertFile, KeyFile string; CAFiles []string; ServerName string }`
+ `TLSClientCreds(TLSClient) (grpc.DialOption, error)` + `TLSClientTransportCreds(TLSClient)
(credentials.TransportCredentials, error)`.
Контракт (fail-closed): `Enable=false` → insecure dial, **cert-файлы не читаются** (текущий
dev, нулевая регрессия); `Enable=true` → предъявляет client-cert (CertFile/KeyFile), проверяет
server-cert против CAFiles и `ServerName` против SAN; `Enable=true` + пустой `ca_files`/
`server_name`/нечитаемый cert → **error** (никогда не молчаливый insecure-fallback).

### GAP — НЕ единый «триада на каждый сервис»; рёбра перечисляются по-сервисно

> **КРИТИЧНО:** набор iam-dialing conn'ов в каждом сервисе **разный**. NLB read/authz-рёбра
> **уже** mTLS-готовы. Completeness-инвариант («ни одно iam-ребро не plaintext») проверяется
> против *фактического* набора conn'ов конкретного сервиса, а НЕ против фиксированной
> четвёрки.

| Сервис | iam-dialing conn (ground-truth dial-site) | RPC по ребру | Текущее состояние | SEC-I action |
|---|---|---|---|---|
| **vpc** | `iamConn` — `clients.Build{Endpoint: cfg.ExtAPI.IAM.Endpoint, TLS: cfg.ExtAPI.IAM.TLS}` (`cmd/vpc/main.go:171`) | `ProjectService.Get` (existence + leaf-owner, :9090) | **plaintext / server-auth-only bool** — gap | client-cert mTLS |
| **vpc** | `authzConn` — `clients.Build{Endpoint: cfg.AuthZ.IAMEndpoint, TLS: cfg.AuthZ.IAMTLS.Enable}` (`cmd/vpc/main.go:225`) | per-RPC `InternalIAMService.Check` (:9091) | **plaintext / server-auth-only bool** — gap | client-cert mTLS |
| **vpc** | list-filter — **тот же** `authzConn` (`newListAuthz(... authzConn)`, `cmd/vpc/main.go:246`) | List-authz `Check` (:9091) | покрывается вместе с `authzConn` (один conn) | покрыто (один conn) |
| **vpc** | register-drainer conn (`startRegisterDrainer` → `mtlsCfg.IAMRegisterClientCreds()`, `cmd/vpc/main.go:519`) | `RegisterResource` (:9091) | **уже mTLS (SEC-D)** | НЕ трогаем |
| **compute** | iam conn — `dialPeer(cfg.IAMGRPCAddr, cfg.IAMTLS, ...)` через `peerDialOpts(useTLS bool, idle)` | `ProjectService.Get` (:9090) | **plaintext / bool useTLS** — gap | client-cert mTLS |
| **compute** | authz conn — `dialPeer(cfg.AuthZIAMGRPCAddr, cfg.AuthZIAMTLS, ...)` | per-RPC `Check` + list-filter (reuse того же authorize-endpoint) (:9091) | **plaintext / bool useTLS** — gap | client-cert mTLS |
| **compute** | register-drainer conn (`IAMRegisterMTLS` + `IAMRegisterClientCreds()`) | `RegisterResource` (:9091) | **уже mTLS (SEC-D)** | НЕ трогаем |
| **nlb** | `iamPublicConn` — `dialOne("iam-public", iamPublicAddr, cfg.ExtAPI.IAM.TLS, cfg.MTLS.IAMRegister)` (`cmd/kacho-loadbalancer/main.go:543`) | `ProjectService.Get` (:9090) | **УЖЕ предъявляет client-cert** (через `cfg.MTLS.IAMRegister`) | only ServerName-correctness (OQ-5) |
| **nlb** | `iamInternalConn` — `dialOne("iam-internal", iamInternalAddr, cfg.ExtAPI.IAM.TLS, cfg.MTLS.IAMRegister)` (`cmd/kacho-loadbalancer/main.go:549`) | `Check` + `RegisterResource` (:9091) | **УЖЕ предъявляет client-cert** | only ServerName-correctness (OQ-5) |
| **nlb** | list-filter conn | — | **НЕ существует** (Check идёт через `iamInternalConn`, нет `newListAuthz`-аналога) | n/a |

**Итог GAP:**
- **vpc** — закрыть 1 conn (`iamConn`) + 1 conn (`authzConn`, он же list-filter) = два plaintext-ребра.
- **compute** — закрыть 1 conn (iam) + 1 conn (authz) = два plaintext-ребра.
- **nlb** — read/authz уже mTLS-готовы; SEC-I по nlb = решить ServerName-семантику (OQ-5),
  *не* добавлять отсутствующие dial-ы и *не* объявлять «insecure/server-auth path».

---

## 1. Глоссарий и инварианты

- **I1 — Зеркало register-drainer, не редизайн.** SEC-I переиспользует SEC-B
  `grpcclient.TLSClient` + per-edge env + уже смонтированный `kacho-<svc>-client-tls`.
  Никаких новых secret'ов/volume'ов/CA/портов.
- **I2 — Trust-инвариант.** `kacho-iam` доверяет principal-метаданным запроса
  (`x-kacho-project-id` / `x-kacho-admin` / `x-kacho-actor`, и owner-principal в
  `RegisterResource`) **только** потому, что peer аутентифицирован mTLS. SEC-H — серверная
  половина (`RequireAndVerifyClientCert`); SEC-I — клиентская половина. Plaintext-клиент,
  доживший до SEC-H, роняет хендшейк (видимый отказ); поэтому SEC-I обязан закрыть **все**
  read/authz iam-рёбра.
- **I3 — Fail-closed, нулевой silent-fallback.** `Enable=true` без валидного cert-trio →
  startup error, не insecure-dial. `Enable=false` → insecure (текущий dev).
- **I4 — Per-edge независимость + per-service opt-in.** Каждое ребро — отдельный
  `TLSClient` value-struct со своим env-блоком; каждый сервис включается независимо через
  helm. Один процесс одновременно держит mTLS-клиента (→iam) и (до SEC-H) insecure-сервер.
- **I5 — Контракт не меняется.** Те же RPC, те же сигнатуры, те же error-коды
  (`Unavailable` при недоступном/неаутентифицируемом peer — fail-closed для мутаций;
  read-рёбра тоже surface'ят `Unavailable`/`FailedPrecondition` как и до SEC-I). Меняется
  **только транспорт** конкретного dial-а.
- **I6 — Два ServerName на iam.** `kacho-iam` server-cert SAN покрывает оба host'а:
  `kacho-iam` (public :9090) и `kacho-iam-internal` (internal :9091)
  (`cert-manager-config` `serverHosts: ["kacho-iam","kacho-iam-internal"]`). Клиент,
  дойдя до конкретного listener'а, обязан выставить ServerName = фактический dial-host
  этого listener'а:
  - ProjectService.Get (:9090) → `kacho-iam.kacho.svc.cluster.local`
  - Check / RegisterResource (:9091) → `kacho-iam-internal.kacho.svc.cluster.local`

---

## 2. Env-конвенция (зеркало `KACHO_VPC_IAM_REGISTER_MTLS_*`)

Каждое новое iam-ребро получает свой блок из пяти env-имён, выведенных corelib
`config.LoadPrefixed("KACHO_<DOMAIN>", &cfg)` из тега родительского поля (SEC-B FD-3):

```
KACHO_<SVC>_<EDGE>_MTLS_ENABLE       (bool)
KACHO_<SVC>_<EDGE>_MTLS_CERTFILE     (path → client tls.crt)
KACHO_<SVC>_<EDGE>_MTLS_KEYFILE      (path → client tls.key)
KACHO_<SVC>_<EDGE>_MTLS_CAFILES      (path → internal-CA ca.crt)
KACHO_<SVC>_<EDGE>_MTLS_SERVERNAME   (dial-host SAN пира)
```

Кандидаты имён рёбер (зеркало `IAM_REGISTER_MTLS`, финал — OQ-4):
- vpc: `KACHO_VPC_IAM_PROJECT_MTLS_*` (ProjectService.Get) + `KACHO_VPC_IAM_AUTHZ_MTLS_*` (Check+list-filter).
- compute: `KACHO_COMPUTE_IAM_PROJECT_MTLS_*` + `KACHO_COMPUTE_IAM_AUTHZ_MTLS_*`.
- nlb: при per-listener split — `KACHO_NLB_MTLS__IAM-PROJECT__*` (:9090) +
  `KACHO_NLB_MTLS__IAM-INTERNAL__*` (:9091, Check+Register), mapstructure-стиль nlb (OQ-5).

---

## A. Сценарии — corelib-примитив уже даёт контракт (регресс-якоря, SEC-B)

> НЕ новый код; фиксируют поведение `grpcclient.TLSClient`, на котором SEC-I держится.
> Verified против `kacho-corelib/grpcclient/tls.go`.

### A-01 — Enable=false → insecure, cert не читается (нулевая регрессия)
**Given** `TLSClient{Enable:false}` (любые/пустые cert-поля)
**When** строится dial-creds
**Then** возвращается insecure transport-creds; CertFile/KeyFile/CAFiles **не** читаются;
поведение идентично доныне-plaintext dial-у.

### A-02 — Enable=true, валидный cert-trio → mTLS-creds
**Given** `TLSClient{Enable:true, CertFile, KeyFile, CAFiles:[ca], ServerName}` все валидны
**When** строится dial-creds
**Then** возвращаются TLS-creds, предъявляющие client-cert, проверяющие server-cert против CA
и ServerName против SAN; ошибки нет.

### A-03 — Enable=true, пустой ca_files → fail-closed error
**Given** `TLSClient{Enable:true, CAFiles:[]}`
**When** строится dial-creds
**Then** **error** (`ca_files is empty`), не insecure-fallback.

### A-04 — Enable=true, пустой server_name → fail-closed error
**Given** `TLSClient{Enable:true, ServerName:""}` (ca валиден)
**When** строится dial-creds
**Then** **error** (`server_name is empty`), не insecure-fallback.

### A-05 — Enable=true, нечитаемый/garbage client cert → fail-closed error
**Given** `TLSClient{Enable:true}`, CertFile указывает на несуществующий/битый PEM
**When** строится dial-creds
**Then** **error** (`load client cert/key`), не insecure-fallback.

---

## B. Сценарии VPC (`kacho-vpc`) — закрыть `iamConn` + `authzConn`

Ground truth: `internal/apps/kacho/config/mtls.go` (уже есть `IAMRegisterMTLS` + helper);
dial-сайты `cmd/vpc/main.go:171` (`iamConn`) и `:225` (`authzConn`, он же list-filter через
`newListAuthz` `:246`). Edge-config — добавить новые `TLSClient`-поля в `MTLSConfig` (тот же
`LoadPrefixed("KACHO_VPC")`, mtls.go).

### B-01 — vpc dev default: все iam-рёбра insecure (нулевая регрессия)
**Given** новые vpc iam-edge env (`*_IAM_PROJECT_MTLS_ENABLE`, `*_IAM_AUTHZ_MTLS_ENABLE`)
не заданы / `=false`, `kacho-iam` БЕЗ SEC-H
**When** vpc стартует и обслуживает `Network.Create` (→ ProjectService.Get), любой
gated-RPC (→ Check) и `List*` (→ list-filter Check)
**Then** `iamConn` и `authzConn` диалятся insecure (как сегодня); cert-файлы не читаются;
все три пути работают; поведение/ошибки без изменений.

### B-02 — vpc ProjectService.Get edge mTLS on → existence/leaf-owner поверх mTLS
**Given** `KACHO_VPC_IAM_PROJECT_MTLS_{ENABLE=true,CERTFILE,KEYFILE,CAFILES,SERVERNAME=
kacho-iam.kacho.svc.cluster.local}`, `kacho-iam` public :9090 на `RequireAndVerifyClientCert`
**When** vpc выполняет `Network.Create` с валидным `project_id`
**Then** `iamConn` предъявляет `kacho-vpc-client-tls` client-cert, верифицирует iam server-cert
против internal-CA и ServerName=`kacho-iam` (∈ SAN); `ProjectService.Get` отрабатывает;
existence + leaf-owner-lookup успешен; ресурс создаётся.

### B-03 — vpc per-RPC Check edge mTLS on → authz-gate поверх mTLS
**Given** `KACHO_VPC_IAM_AUTHZ_MTLS_{ENABLE=true,...,SERVERNAME=
kacho-iam-internal.kacho.svc.cluster.local}`, iam internal :9091 на `RequireAndVerifyClientCert`
**When** приходит gated-RPC и authz-interceptor зовёт `InternalIAMService.Check`
**Then** `authzConn` предъявляет client-cert и верифицирует iam server-cert + ServerName=
`kacho-iam-internal`; `Check` отрабатывает; allow/deny корректно; principal-метаданные
доверяются (I2).

### B-04 — vpc list-filter Check поверх того же `authzConn` (покрыт вместе с B-03)
**Given** `authz.list-filter.enabled=true` и `KACHO_VPC_IAM_AUTHZ_MTLS_ENABLE=true`
**When** `ListNetworks`/`ListSubnets`/… фильтруют результат через `listauthz` → `Check`
**Then** list-filter использует **тот же** `authzConn` (`newListAuthz(... authzConn)`), который
уже mTLS из B-03; отдельного list-filter-conn'а нет; фильтрация работает поверх mTLS.
*(verifies: list-filter делит conn с per-RPC gate — OQ-2.)*

### B-05 — vpc остаточный plaintext iam-edge при SEC-H → handshake FAILS (предотвращаемая регрессия)
**Given** SEC-H на iam, но ОДНО vpc iam-ребро оставлено plaintext (например
`IAM_AUTHZ_MTLS_ENABLE=false`, а `IAM_PROJECT_MTLS_ENABLE=true`)
**When** срабатывает per-RPC Check по `authzConn`
**Then** TLS-handshake падает (`tls: first record does not look like a TLS handshake` /
`bad certificate`) → `Check` → `Unavailable`; запрос fail-closed.
**Демонстрирует:** нельзя оставить НИ ОДНО iam-ребро plaintext — completeness-инвариант (I2).

### B-06 — vpc fail-closed на кривой конфиг (зеркало A-03/A-04/A-05)
**Given** любое vpc iam-edge `*_MTLS_ENABLE=true` с пустым CAFILES / пустым SERVERNAME /
битым cert
**When** vpc стартует (creds строятся на composition-root)
**Then** startup-error, pod не стартует (no silent insecure); видимый отказ.

---

## C. Сценарии COMPUTE (`kacho-compute`) — закрыть iam + authz conn

> **Ground-truth:** у compute **нет** `internal/config/mtls.go`. Register-edge живёт в
> **`internal/config/config.go`**: `IAMRegisterMTLS grpcclient.TLSClient
> \`envconfig:"IAM_REGISTER_MTLS"\`` + `IAMRegisterClientCreds()`. Read/authz dial-ы используют
> **plain bool** `cfg.IAMTLS` / `cfg.AuthZIAMTLS` через seam `dialPeer(addr, useTLS bool, idle)`
> → `peerDialOpts(useTLS, idle)`. SEC-I по compute = протянуть `grpcclient.TLSClient` /
> `TransportCredentials` через эти seam-функции (заменив/дополнив bool `useTLS`) — ровно тот seam,
> что инспектирует существующий `peerDialOpts`-тест. **Файл изменений — `internal/config/config.go`,
> НЕ `mtls.go`** (создавать `mtls.go` запрещено — это фантомный путь).

### C-01 — compute dev default: iam + authz insecure (нулевая регрессия)
**Given** новые compute iam-edge env (`*_IAM_PROJECT_MTLS_ENABLE`, `*_IAM_AUTHZ_MTLS_ENABLE`)
не заданы / `=false`, iam БЕЗ SEC-H
**When** compute выполняет `Instance.Create` (→ ProjectService.Get), gated-RPC (→ Check), `List*`
**Then** оба conn'а insecure (как сегодня через `peerDialOpts(false, …)`); cert не читается;
поведение без изменений.

### C-02 — compute ProjectService.Get edge mTLS on
**Given** `KACHO_COMPUTE_IAM_PROJECT_MTLS_{ENABLE=true,...,SERVERNAME=
kacho-iam.kacho.svc.cluster.local}`, iam :9090 на `RequireAndVerifyClientCert`
**When** compute выполняет `Instance.Create` с валидным `project_id`
**Then** iam-conn предъявляет `kacho-compute-client-tls` client-cert, верифицирует server-cert
+ ServerName=`kacho-iam`; `ProjectService.Get` отрабатывает; existence/leaf-owner ок.

### C-03 — compute per-RPC Check edge mTLS on
**Given** `KACHO_COMPUTE_IAM_AUTHZ_MTLS_{ENABLE=true,...,SERVERNAME=
kacho-iam-internal.kacho.svc.cluster.local}`, iam :9091 на `RequireAndVerifyClientCert`
**When** срабатывает authz-interceptor → `InternalIAMService.Check`
**Then** authz-conn предъявляет client-cert + верифицирует server-cert + ServerName=
`kacho-iam-internal`; `Check` отрабатывает; allow/deny корректно.

### C-04 — compute list-filter поверх authz-conn (тот же authorize-endpoint)
**Given** `KACHO_COMPUTE_LIST_FILTER_ENABLED=true` и `*_IAM_AUTHZ_MTLS_ENABLE=true`
**When** `ListInstances`/… фильтруют через `Check`
**Then** list-filter переиспользует authz iam-endpoint (`AuthZIAMGRPCAddr`), который уже mTLS из
C-03; отдельного conn'а нет; фильтрация поверх mTLS.

### C-05 — compute остаточный plaintext iam-edge при SEC-H → handshake FAILS
**Given** SEC-H на iam, одно compute iam-ребро plaintext
**When** срабатывает соответствующий dial
**Then** handshake падает → `Unavailable`; fail-closed. Completeness-инвариант (I2).

### C-06 — compute seam threading сохраняет bool-совместимость для НЕ-iam dial-ов
**Given** `dialPeer`/`peerDialOpts` теперь принимают per-edge mTLS-параметр для iam-рёбер
**When** compute диалит VPC (`cfg.VPCMTLS` — SEC-D), iam (SEC-I) и legacy bool-TLS-пиров
**Then** каждое ребро резолвит свой `TLSClient`/bool независимо; не-iam dial-ы (legacy
`VPCTLS`/`VPCInternalTLS` bool) не ломаются; существующий `peerDialOpts`-тест зелёный.
*(verifies: seam-рефактор не регрессит — OQ-3.)*

### C-07 — compute fail-closed на кривой конфиг (зеркало A-03/A-04/A-05)
**Given** compute iam-edge `*_MTLS_ENABLE=true` с пустым CAFILES / SERVERNAME / битым cert
**When** compute стартует
**Then** startup-error; pod не стартует; no silent insecure.

---

## D. Сценарии NLB (`kacho-nlb`) — read/authz УЖЕ mTLS; SEC-I = ServerName-корректность

> **Ground-truth:** NLB **не** содержит plaintext read/authz iam-ребра.
> `cmd/kacho-loadbalancer/main.go:543` (`iam-public` → `peers.Project` = ProjectService.Get) и
> `:549` (`iam-internal` → `peers.Check` + `peers.Register`) **уже** диалятся через
> `dialOne(..., cfg.MTLS.IAMRegister)` — оба предъявляют client-cert при
> `cfg.MTLS.IAMRegister.Enable=true` (`dialOne` строит `grpcclient.TLSClientTransportCreds`,
> передаёт через `clients.BuildOptions.MTLSCreds`). list-filter-conn'а **нет** (Check идёт через
> `iamInternalConn`). Реальный недочёт: оба conn'а наследуют **единственный** ServerName
> register-ребра (`serverName.iamRegister = kacho-iam-internal.*`), верный для :9091, но
> **неверный** для public :9090 ProjectService dial-host'а `kacho-iam`. Под SEC-H это провалит
> ServerName-SAN-проверку на public-ребре (I6). SEC-I по nlb = разрешить ServerName-семантику
> (OQ-5), а НЕ добавлять отсутствующие dial-ы.

### D-01 — nlb baseline: read/authz iam уже предъявляют client-cert (НЕ регрессировать)
**Given** `cfg.MTLS.IAMRegister.Enable=true`
**When** nlb диалит `iam-public` (:543) и `iam-internal` (:549)
**Then** оба conn'а строятся через `dialOne(..., cfg.MTLS.IAMRegister)` и предъявляют
`kacho-nlb-client-tls` client-cert; ProjectService.Get, Check, RegisterResource — все mTLS.
*(SEC-I не должен превратить уже-mTLS-conn в plaintext.)*

### D-02 — nlb public-ребро (:9090) с корректным ServerName под SEC-H
**Given** SEC-H на iam (обоих listener'ах), nlb `iam-public` conn выставляет ServerName=
`kacho-iam.kacho.svc.cluster.local` (фактический :9090 dial-host)
**When** nlb зовёт `ProjectService.Get`
**Then** ServerName ∈ iam server-SAN (`kacho-iam`); handshake проходит; `ProjectService.Get` ок.

### D-03 — nlb internal-ребро (:9091) с корректным ServerName под SEC-H
**Given** SEC-H на iam, nlb `iam-internal` conn выставляет ServerName=
`kacho-iam-internal.kacho.svc.cluster.local` (:9091 dial-host)
**When** nlb зовёт `Check` / `RegisterResource`
**Then** ServerName ∈ SAN (`kacho-iam-internal`); handshake проходит; оба RPC работают.

### D-04 — nlb latent-bug якорь: единый ServerName ломает одно из двух рёбер под SEC-H
**Given** (текущее поведение ДО SEC-I) оба iam-conn'а наследуют **один** ServerName=
`kacho-iam-internal.*` (`cfg.MTLS.IAMRegister`), SEC-H включён
**When** nlb зовёт `ProjectService.Get` по public :9090 conn'у с ServerName=`kacho-iam-internal`
**Then** ServerName не совпадает с фактическим dial-host'ом :9090 — это и есть latent
ServerName-bug; SEC-I фиксит его per-listener-ServerName (D-02/D-03).
*(verifies: разъезд public/internal SAN — OQ-5; RED-якорь для решения OQ-5.)*

### D-05 — nlb dev default: read/authz iam insecure при `Enable=false`
**Given** iam-edge поле(я) `Enable=false` (shared `cfg.MTLS.IAMRegister` или per-listener split — все false), iam БЕЗ SEC-H
**When** nlb диалит iam-public / iam-internal
**Then** оба insecure (текущий dev); cert не читается; нулевая регрессия.

---

## E. Сценарии helm / deploy (`kacho-deploy`) — переиспользовать смонтированный secret

Ground truth: `kacho-<svc>-client-tls` secret **уже смонтирован** в каждый pod (vpc/compute/nlb)
для register-drainer-ребра, в раздельном volume `$cli = {mountPath}/client` (tls.crt/tls.key/ca.crt;
`clientSecretName: kacho-<svc>-client-tls`). Env-рендер gated `mtls.edges.<edge>` +
`mtls.serverName.<edge>` (см. vpc `deploy/templates/deployment.yaml` — register-блок).

### E-01 — helm OFF (default): новых iam-edge env нет (нулевая dev-регрессия)
**Given** `helm template <svc>/deploy` без mtls-override (mtls.enable не задан)
**When** рендерится Deployment
**Then** **нет** новых `KACHO_<SVC>_IAM_*_MTLS_*` env; нет лишних volume/mount;
поведение чарта как до SEC-I.

### E-02 — helm ON: новые iam read/authz env рендерятся, secret переиспользуется
**Given** `helm template <svc>/deploy --set mtls.enable=true --set mtls.edges.iamProject=true
--set mtls.edges.iamAuthz=true` (имена edge-флагов — по выбранной структуре, зеркало `iamRegister`)
**When** рендерится Deployment
**Then** появляются `KACHO_<SVC>_IAM_PROJECT_MTLS_{ENABLE,CERTFILE,KEYFILE,CAFILES,SERVERNAME}`
и `KACHO_<SVC>_IAM_AUTHZ_MTLS_{...}`; CERTFILE/KEYFILE/CAFILES указывают в **существующий**
`$cli`-volume (`kacho-<svc>-client-tls`); **нового** secret'а/volume'а не добавлено (I1).

### E-03 — helm ServerName-корректность per-edge (I6)
**Given** ON-рендер
**When** проверяется `*_IAM_PROJECT_MTLS_SERVERNAME` и `*_IAM_AUTHZ_MTLS_SERVERNAME`
**Then** ProjectService-edge SERVERNAME = `kacho-iam.kacho.svc.cluster.local` (:9090 host);
authz/Check-edge SERVERNAME = `kacho-iam-internal.kacho.svc.cluster.local` (:9091 host);
оба ∈ iam server-SAN `["kacho-iam","kacho-iam-internal"]`.

### E-04 — nlb helm: ServerName split для двух iam-listener'ов (или явное обоснование reuse)
**Given** nlb-чарт под решение OQ-5
**When** рендерится nlb Deployment с включённым iam-edge
**Then** public-conn SERVERNAME = `kacho-iam`, internal-conn SERVERNAME = `kacho-iam-internal`
(per-listener split); либо — если OQ-5 решит reuse — рендер явно документирует, что один
ServerName не может быть корректен для обоих listener'ов (D-04), и это запрещено под SEC-H.

### E-05 — umbrella `values.mtls.yaml`: per-service opt-in новых read/authz рёбер
**Given** `values.mtls.yaml` уже включает `edges.iamRegister:true` для vpc/compute/nlb +
`kacho-iam.mtls.enable:true` (SEC-H)
**When** добавляются новые edge-флаги для read/authz рёбер vpc/compute (+ nlb per OQ-5)
**Then** umbrella-рендер прокидывает их в subchart'ы; включение SEC-H (`kacho-iam.mtls.enable`)
сопровождается включением ВСЕХ iam read/authz рёбер каждого сервиса (completeness-gate, §F).

---

## F. Completeness-gate (SEC-I-07) — «ни одно iam-ребро не plaintext» по ФАКТИЧЕСКОМУ набору

> Gate проверяет per-service фактический набор iam-conn'ов, а НЕ фиксированную четвёрку.
> Иначе он потребует несуществующий nlb list-filter-dial (ложный fail) или пройдёт вакуумно.

### SEC-I-07 — статический gate: каждый iam-dialing conn сервиса предъявляет cert при SEC-H
**Given** фактический набор iam-conn'ов на сервис:
- vpc: `iamConn` (ProjectService.Get) + `authzConn` (Check+list-filter) + register-drainer-conn (SEC-D)
- compute: iam-conn (ProjectService.Get) + authz-conn (Check+list-filter) + register-drainer-conn (SEC-D)
- nlb: `iamPublicConn` (ProjectService.Get) + `iamInternalConn` (Check+Register) — оба уже mTLS (SEC-D)

**When** прогоняется статическая проверка (grep dial-сайтов + helm-render-assertion в
`service-mtls-wiring-test.sh`) + cluster smoke с `kacho-iam` на `RequireAndVerifyClientCert`
**Then** **каждый** перечисленный conn под mTLS-профилем строится с client-cert (не insecure);
ни один не остаётся plaintext; gate enumerates именно эти conn'ы (не требует отсутствующего
nlb list-filter-dial'а).

### SEC-I-08 — финальный smoke (зеркало SEC-D/SEC-H DoD)
**Given** kind-стенд, `values.mtls.yaml` (SEC-H on + все read/authz iam-рёбра on)
**When** прогон базового e2e (создать/прочитать/удалить ресурс в vpc и compute; nlb через свои
RPC) при iam на `RequireAndVerifyClientCert` на обоих listener'ах
**Then** все операции зелёные; в логах iam НЕТ handshake-ошибок ни по одному `*→iam` ребру;
iam-лог/захват показывает client-cert на каждом iam-dial'е.

---

## 3. Карта изменений (для impl-агента; пути и строки — ground truth)

| Репо / файл | Что | Что НЕ делать |
|---|---|---|
| `kacho-vpc/internal/apps/kacho/config/mtls.go` | + 2 поля `TLSClient` (iam-project, iam-authz) в `MTLSConfig` + helper'ы (зеркало `IAMRegisterClientCreds`); тот же `LoadPrefixed("KACHO_VPC")` | не создавать новый загрузчик |
| `kacho-vpc/cmd/vpc/main.go` (`iamConn` `:171`, `authzConn` `:225`, list-filter `newListAuthz` `:246`) | прокинуть mTLS-creds в `clients.Build` для `iamConn` и `authzConn` (list-filter покрыт через тот же `authzConn`) | не трогать `startRegisterDrainer` (`:519`, SEC-D готово) |
| `kacho-compute/internal/config/config.go` | + 2 поля `TLSClient` (iam-project, iam-authz) рядом с `IAMRegisterMTLS` + helper'ы; протянуть `TransportCredentials` через `dialPeer`/`peerDialOpts` seam | **не** создавать `mtls.go`; не трогать `IAMRegisterMTLS` |
| `kacho-nlb/internal/apps/kacho/config/config.go` (`MTLSConfig`) + `cmd/kacho-loadbalancer/main.go` (`dialOne(..., cfg.MTLS.IAMRegister)` для `iam-public` `:543` и `iam-internal` `:549`) | per-listener ServerName для двух iam-conn'ов (OQ-5); read/authz уже mTLS | **не** добавлять plaintext-dial-ы; не объявлять «insecure path» |
| `kacho-deploy` service-charts (vpc/compute/nlb `deploy/templates/deployment.yaml`, `values.yaml`) | новые `mtls.edges.iam*` + `mtls.serverName.iam*` env-блоки, gated; reuse `kacho-<svc>-client-tls` (`$cli`-volume) | **не** добавлять новый secret/volume/mount |
| `kacho-deploy/helm/umbrella/values.mtls.yaml` | per-service opt-in новых read/authz рёбер | — |
| `kacho-deploy/tests/helm/service-mtls-wiring-test.sh` | расширить OFF/ON-ассерты на новые env + per-service completeness (§F) | — |

---

## 4. Тестовая стратегия (строгий TDD, ban #12)

- **RED ДО кода** на каждом уровне; в PR показать пару RED→GREEN.
- **corelib (A-01..A-05):** уже покрыто `grpcclient` unit-тестами (SEC-B) — регресс-якорь.
- **vpc/compute (config/wiring):** unit на новые `TLSClient`-поля (env-резолв через
  `LoadPrefixed`/`envconfig`) + fail-closed (B-06/C-07 ⇄ A-03/A-04/A-05); compute — расширить
  существующий `peerDialOpts`-seam-тест (C-06).
- **handshake-FAIL якоря (B-05/C-05/D-04):** integration/среда с iam на
  `RequireAndVerifyClientCert` — plaintext-ребро → `Unavailable`; mTLS-ребро → success.
- **helm (E-01..E-05, F):** манифест-ассерты в `service-mtls-wiring-test.sh` (OFF: нет env/volume;
  ON: точные env-имена + reuse client-secret + ServerName-значения) + per-service completeness-gate.
- **e2e smoke (SEC-I-08):** kind с `values.mtls.yaml` (SEC-H + все iam read/authz рёбра on),
  базовый CRUD vpc/compute/nlb зелёный, iam-логи без handshake-ошибок.
- Финал перед merge: `go test ./... -race` + `golangci-lint run` + `govulncheck` +
  helm wiring-тест + smoke зелёные.

---

## 5. Non-goals (явно вне scope)

- **Контракт/proto/RPC** — без изменений (`kacho-proto` не трогаем). Меняется только транспорт dial-а.
- **FGA-модель / authz-семантика / list-filter-логика** — без изменений.
- **register-drainer ребро (SEC-D)** — уже mTLS во всех трёх сервисах; **не переделывать**.
- **Серверная сторона iam (SEC-H)** — отдельная под-фаза; SEC-I — только клиентская половина.
- **`kacho-corelib` `grpcclient`** — примитив готов (SEC-B); не расширять.
- **`kacho-api-gateway`** — backend-dial mTLS закрыт SEC-E; вне SEC-I.
- **Cert-rotation runtime-reload** — out of scope (rotation = pod restart, эпик §6.2).
- **Новые secret'ы / volume'ы / CA / порты** — запрещены; reuse `kacho-<svc>-client-tls`.

---

## 6. Открытые вопросы (решить ДО кода)

- **OQ-1 (vpc edge-структура).** Два отдельных `TLSClient`-поля (`iam-project`, `iam-authz`)
  ИЛИ один общий iam-edge, переиспользуемый обоими conn'ами? Рекомендация: **два поля** —
  ProjectService.Get (:9090) и Check (:9091) имеют **разный** ServerName (I6), значит общий
  один `TLSClient` не может нести оба ServerName. Два поля = зеркало register-стиля.
- **OQ-2 (vpc list-filter).** list-filter делит `authzConn` с per-RPC gate
  (`newListAuthz(... authzConn)`), → покрывается одним `iam-authz`-полем. Подтверждено
  ground-truth (B-04). Решение: **не** заводить отдельное list-filter-поле.
- **OQ-3 (compute seam).** `dialPeer(addr, useTLS bool, idle)` / `peerDialOpts(useTLS, idle)`
  — заменить `useTLS bool` на `TransportCredentials`/`TLSClient` ИЛИ добавить параллельный
  параметр? Рекомендация: протянуть `TransportCredentials` (как nlb `dialOne` `MTLSCreds`),
  сохранив bool для legacy не-iam пиров до их миграции (C-06).
- **OQ-4 (env-имена).** Финальные имена рёбер: `IAM_PROJECT_MTLS` / `IAM_AUTHZ_MTLS` (зеркало
  `IAM_REGISTER_MTLS`)? Зафиксировать в proto-style/go-style review.
- **OQ-5 (nlb ServerName — БЛОКИРУЮЩИЙ).** Сейчас `iam-public` (:9090, `main.go:543`) и
  `iam-internal` (:9091, `:549`) conn'ы **оба** диалятся через `cfg.MTLS.IAMRegister` — единый
  cert-trio + **единый** ServerName (`kacho-iam-internal.*`). Под SEC-H варианты:
  - (a) **оставить shared** `MTLS.IAMRegister` → ServerName не может быть корректным для обоих
    listener'ов (конфликт с I6/D-04: public dial-host = `kacho-iam`, internal = `kacho-iam-internal`), либо
  - (b) **split** на per-listener поля: `MTLS.IAMProject` (:9090 ServerName=`kacho-iam`) +
    `MTLS.IAMInternal` (:9091 ServerName=`kacho-iam-internal`, покрывает Check **и** Register).
  **Рекомендация: (b)** — единственный вариант, при котором SEC-H `RequireAndVerifyClientCert` +
  ServerName-SAN-проверка проходит на ОБОИХ listener'ах nlb. Решить ДО impl (определяет
  helm-рендер E-04 и nlb-сценарии D-02/D-03).

---

## 7. Traceability

| Требование (prompt) | Сценарии |
|---|---|
| (A) enable=false → insecure, нулевая регрессия | A-01, B-01, C-01, D-05, E-01 |
| (B) enable=true → каждый iam-dial предъявляет `kacho-<svc>-client-tls` + верифицирует iam server-cert против internal-CA, корректный ServerName per-listener | A-02, B-02/B-03, C-02/C-03, D-02/D-03, E-02/E-03/E-04, I6 |
| (C) остаточный plaintext iam-edge при SEC-H → handshake FAILS (предотвращаемая регрессия); ни одно ребро не plaintext | B-05, C-05, D-04, SEC-I-07, SEC-I-08 |
| (D) trust-инвариант: principal-метаданные доверяются только при mTLS-verified peer | I2, B-03, C-03, D-03 |
| (E) per-service scope: vpc/compute/nlb, независимый opt-in | I4, B-*, C-*, D-*, E-05 |
| (F) helm: reuse смонтированного `kacho-<svc>-client-tls`; env только при enable | I1, E-01..E-05 |
| Env-конвенция зеркалит `KACHO_VPC_IAM_REGISTER_MTLS_*` | §2, OQ-4 |

| Sub-phase | Roadmap |
|---|---|
| SEC-B | corelib `grpcclient.TLSClient` (примитив) — done |
| SEC-D | per-edge mTLS config + register-drainer edge (vpc/compute/nlb) — done |
| SEC-F | cert-manager internal-CA PKI + `kacho-<svc>-{server,client}-tls` — done |
| SEC-H | `kacho-iam` server `RequireAndVerifyClientCert` (оба listener'а) — клиентская половина = SEC-I |
| **SEC-I** | **CLIENT mTLS на read/authz рёбрах `*→iam` (vpc/compute; nlb = ServerName-fix)** |

---

## 8. Definition of Done

- [ ] OQ-1..OQ-5 решены (OQ-5 — до impl, блокирующий nlb-рендер).
- [ ] vpc: `iamConn` + `authzConn` (он же list-filter) предъявляют client-cert при
      enable=true; fail-closed при кривом конфиге; dev insecure при enable=false.
- [ ] compute: iam + authz conn через seam с `TransportCredentials`; изменения в
      `internal/config/config.go` (НЕ `mtls.go`); `peerDialOpts`-seam-тест зелёный; fail-closed; dev insecure.
- [ ] nlb: per-listener ServerName (OQ-5) для уже-mTLS `iam-public`/`iam-internal`; read/authz
      НЕ регрессируют в plaintext; latent ServerName-bug закрыт.
- [ ] helm: новые `mtls.edges.iam*` + `serverName.iam*` env-блоки (vpc/compute, nlb per OQ-5),
      reuse `kacho-<svc>-client-tls`; ServerName per-listener корректен (E-03/E-04).
- [ ] `service-mtls-wiring-test.sh`: OFF/ON-ассерты на новые env + per-service completeness-gate
      (§F, фактический набор conn'ов, без фантомного nlb list-filter).
- [ ] TDD RED→GREEN на каждом уровне; финал: `go test ./... -race` + `golangci-lint` +
      `govulncheck` + helm wiring + smoke (SEC-I-08) зелёные.
- [ ] Completeness verified: с `kacho-iam` на `RequireAndVerifyClientCert` (оба listener'а) НИ
      ОДНО `*→iam` read/authz ребро vpc/compute/nlb не plaintext (SEC-I-07/08).
- [ ] Non-goals соблюдены: без proto/FGA/contract-изменений; register-drainer не переделан.
- [ ] vault-trail: `edges/*-to-iam-*` обновлены (read/authz рёбра теперь mTLS) + KAC-trail.
