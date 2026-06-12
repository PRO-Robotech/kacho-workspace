# Sub-phase SEC-M — завершение CLIENT mTLS-меша на resource-creation рёбрах `compute→vpc` + `nlb→{vpc,compute}`

> **Статус:** DRAFT (на ревью `acceptance-reviewer` — единственный gate APPROVED, ban #1)
> **Дата:** 2026-06-12
> **Type:** acceptance (Given-When-Then), markdown-only, без кода
> **Эпик:** SEC (cluster-internal mTLS mesh). Предшественники: SEC-B (corelib
> `grpcclient.TLSClient`), SEC-D (per-edge mTLS config + register-drainer edge),
> SEC-F (cert-manager internal-CA PKI + `kacho-<svc>-{server,client}-tls`),
> SEC-H (`kacho-iam` server-side `RequireAndVerifyClientCert`), SEC-I (CLIENT mTLS
> на read/authz рёбрах `*→iam`). **Зеркало** уже отгруженного `vpc→compute`-ребра
> (SEC-D-19) и SEC-I iam-рёбер — НЕ новый дизайн.
> **Репозитории:** `kacho-compute`, `kacho-nlb`, `kacho-deploy` (helm + wiring-тест).
> **Без** `kacho-proto` / `kacho-corelib` / `kacho-api-gateway` изменений (см. §«Non-goals»).

---

## 0. Контекст и постановка (ground truth)

Серверы `kacho-vpc`, `kacho-compute`, `kacho-nlb` **уже** работают на
`tls.RequireAndVerifyClientCert` (corelib `grpcsrv`, SEC-F/H-семейство) под
mTLS-профилем. После этого **любой** gRPC-dial в такой сервер БЕЗ предъявленного
клиентского сертификата падает: для plaintext-клиента — `error reading server
preface: EOF` / `connection reset by peer` (gRPC code 14 `Unavailable`), для
cert-less TLS-клиента — `bad certificate`. Значит **каждое** клиентское ребро,
дойдя до mTLS-сервера, обязано предъявлять client-cert ДО включения серверного
`RequireAndVerifyClientCert`, иначе соответствующая операция ляжет.

`vpc→compute` (валидация `zone_id` через `ZoneService.Get`) **уже** закрыт
(`kacho-vpc/cmd/vpc/main.go` ветвится на `mtlsCfg.ComputeMTLS.Enable` →
`grpc.NewClient(..., ComputeClientCreds())`; helm vpc-чарт рендерит
`KACHO_VPC_COMPUTE_MTLS_*` gated на `.Values.mtls.edges.compute`; umbrella
`values.mtls.yaml` ставит `vpc.mtls.edges.compute=true`). SEC-I закрыл рёбра
`*→iam`. **SEC-M — это зеркало того же паттерна на ОСТАВШИХСЯ resource-creation
рёбрах**, без которых end-to-end создание ресурсов под mTLS-профилем не работает:

- **`compute→vpc`** — `Instance.Create` валидирует NIC-spec (Subnet/SecurityGroup
  через `vpc.SubnetService.Get`/`SecurityGroupService.Get`) и IPAM-аллоцирует
  one-to-one-NAT Address (`vpc.AddressService.Get` + internal IPAM) вызовом vpc.
  Без client-cert на этом ребре `Instance.Create` падает под SEC-H-vpc.
- **`nlb→vpc`** + **`nlb→compute`** — NLB-create-флоу резолвит Address/Subnet/NIC
  (vpc) и Region/Instance (compute).

Никакого нового дизайна: тот же corelib-примитив `grpcclient.TLSClient` /
`TLSClientCreds` / `TLSClientTransportCreds` (SEC-B), тот же уже смонтированный
client-cert secret `kacho-<svc>-client-tls`, тот же helm-gating
`mtls.edges.<edge>` + `mtls.serverName.<edge>`.

### Примитив (существует, SEC-B — НЕ меняем)

`kacho-corelib/grpcclient/tls.go`:
`type TLSClient { Enable bool; CertFile, KeyFile string; CAFiles []string; ServerName string }`
+ `TLSClientCreds(TLSClient) (grpc.DialOption, error)` + `TLSClientTransportCreds(TLSClient)
(credentials.TransportCredentials, error)`.
Контракт (fail-closed): `Enable=false` → insecure dial, **cert-файлы не читаются** (текущий
dev, нулевая регрессия); `Enable=true` → предъявляет client-cert (CertFile/KeyFile), проверяет
server-cert против CAFiles и `ServerName` против SAN; `Enable=true` + пустой `ca_files`/
`server_name`/нечитаемый cert → **error** (никогда не молчаливый insecure-fallback).

### GAP — фактический per-репо набор conn'ов (резюме ground-truth, НЕ фиксированная схема)

> **КРИТИЧНО:** набор vpc/compute-dialing conn'ов в каждом сервисе **разный**, и часть
> работы УЖЕ отгружена. Completeness-инвариант («ни одно resource-creation-ребро не
> plaintext под mTLS-профилем») проверяется против *фактического* набора conn'ов
> конкретного сервиса, а НЕ против фиксированного списка.

| Сервис | dialing conn (ground-truth dial-site) | RPC по ребру | Текущее состояние | SEC-M action |
|---|---|---|---|---|
| **compute** | `vpcConn` — `dialPeer(cfg.VPCGRPCAddr, cfg.VPCTLS, false)` (`cmd/compute/main.go:332`) | `Subnet/SecurityGroup/Address.Get` (NIC-spec + IPAM, public :9090) | **plaintext / server-auth-only bool `cfg.VPCTLS`** — gap | client-cert mTLS |
| **compute** | `vpcInternalConn` — `dialPeer(cfg.VPCInternalGRPCAddr, cfg.VPCInternalTLS, false)` (`cmd/compute/main.go:337`) | internal IPAM (one-to-one-NAT alloc/free, internal :9091) | **plaintext / server-auth-only bool `cfg.VPCInternalTLS`** — gap | client-cert mTLS |
| **compute** | iam/authz/register conn'ы | `ProjectService.Get` / `Check` / `Register` | **уже mTLS (SEC-I/SEC-D)** | НЕ трогаем |
| **nlb** | `vpcPublicConn` — `dialOne("vpc-public", …, cfg.MTLS.VPC)` (`cmd/kacho-loadbalancer/main.go:595`) | `Address/Subnet/NetworkInterface.Get` (public) | **УЖЕ предъявляет client-cert** (`cfg.MTLS.VPC`) | verify-only (regress-anchor) |
| **nlb** | `vpcInternalConn` — `dialOne("vpc-internal", …, cfg.MTLS.VPC)` (`cmd/kacho-loadbalancer/main.go:601`) | `InternalAddressService` (IPAM, internal) | **УЖЕ предъявляет client-cert** (`cfg.MTLS.VPC`) | verify-only (regress-anchor) |
| **nlb** | `computeConn` — `dialOne("compute", …, cfg.MTLS.Compute)` (`cmd/kacho-loadbalancer/main.go:582`) | `Region/Instance.Get` | **УЖЕ предъявляет client-cert** (`cfg.MTLS.Compute`) | verify-only (regress-anchor) |
| **nlb** | iam conn'ы | `ProjectService.Get` / `Check` / `Register` | **уже mTLS (SEC-I/SEC-D)** | НЕ трогаем |

**Итог GAP:**
- **compute** — закрыть 2 conn'а (`vpcConn` :9090 + `vpcInternalConn` :9091): config-поле
  `cfg.VPCMTLS` (`grpcclient.TLSClient`, `envconfig:"VPC_MTLS"`) + helper `cfg.VPCClientCreds()`
  УЖЕ существуют (`internal/config/config.go:148-182`), но **НЕ протянуты в dial-сайты** —
  оба conn'а всё ещё диалятся plaintext bool'ом. SEC-M по compute = протянуть creds в
  `vpcConn`/`vpcInternalConn` ровно как `vpc→compute`.
- **nlb** — `nlb→vpc` (`cfg.MTLS.VPC`) и `nlb→compute` (`cfg.MTLS.Compute`) **уже** диалятся
  через `dialOne(..., creds)` (предъявляют `kacho-nlb-client-tls`). SEC-M по nlb = **verify**:
  подтвердить, что dial действительно потребляет creds и helm рендерит config-блоки
  `mtls.vpc`/`mtls.compute`; **не** добавлять отсутствующие dial-ы и **не** объявлять
  «insecure/server-auth path».

### Что уже отгружено (НЕ переделывать в SEC-M)

- **compute config**: `cfg.VPCMTLS` + `cfg.VPCClientCreds()` существуют (config.go:148-182). Не дублировать.
- **compute helm**: deploy-template УЖЕ рендерит `KACHO_COMPUTE_VPC_MTLS_{ENABLE,CERTFILE,KEYFILE,CAFILES,SERVERNAME}`
  gated на `.Values.mtls.edges.vpc` (compute `deploy/templates/deployment.yaml`), а compute-чарт
  `deploy/values.yaml` УЖЕ держит `edges.vpc: false` + `serverName.vpc: vpc.kacho.svc.cluster.local`.
- **nlb Go**: `cfg.MTLS.VPC`/`cfg.MTLS.Compute` (`mapstructure:"vpc"`/`"compute"`) + dial через `dialOne`.
- **nlb helm**: configmap УЖЕ рендерит `mtls.vpc`/`mtls.compute`-блоки gated; umbrella
  `kacho-nlb.mtls.edges.vpc=true` + `compute=true` УЖЕ стоят.

---

## 1. Глоссарий и инварианты

- **M1 — Зеркало `vpc→compute`, не редизайн.** SEC-M переиспользует SEC-B
  `grpcclient.TLSClient` + per-edge env/config + уже смонтированный `kacho-<svc>-client-tls`.
  Никаких новых secret'ов/volume'ов/CA/портов.
- **M2 — Завершение меша = end-to-end resource creation.** Цель — чтобы под mTLS-профилем
  `Instance.Create` (compute→vpc NIC/IPAM) и NLB-create-флоу (nlb→vpc + nlb→compute)
  отрабатывали полностью. Plaintext-ребро, доживший до серверного
  `RequireAndVerifyClientCert`, роняет хендшейк (видимый отказ code 14) → операция fail.
- **M3 — Fail-closed, нулевой silent-fallback.** `Enable=true` без валидного cert-trio →
  startup error, не insecure-dial. `Enable=false` → insecure (текущий dev, нулевая регрессия).
- **M4 — Per-edge независимость + per-service opt-in.** Каждое ребро — отдельный
  `TLSClient` value-struct со своим env/config-блоком; каждый сервис включается независимо
  через helm. Один процесс одновременно держит mTLS-клиента (→vpc/compute) и (до своего
  серверного flip) insecure-сервер.
- **M5 — Контракт не меняется.** Те же RPC, те же сигнатуры, те же error-коды:
  peer недоступен/не-аутентифицируем → `Unavailable` (fail-closed для мутаций); not-found →
  `NotFound`; не то состояние → `FailedPrecondition` — как и до SEC-M. Меняется **только
  транспорт** конкретного dial-а.
- **M6 — ServerName = фактический dial-host пира.** Каждый клиентский dial выставляет
  ServerName = bare-Service-host, который он реально диалит, и этот host обязан быть ∈ SAN
  server-cert'а пира (cert-manager-config `serverHosts`):
  - vpc Service называется **`vpc`** → SAN покрывает оба listener-host'а; и `vpcConn` (:9090),
    и `vpcInternalConn` (:9091) диалят host `vpc` → ServerName=`vpc.kacho.svc.cluster.local`
    для ОБОИХ (один host покрывает оба порта; per-listener split НЕ требуется, в отличие от
    iam в SEC-I, где Service'ы `kacho-iam` и `kacho-iam-internal` различаются).
  - compute Service → ServerName=`compute.kacho.svc.cluster.local` (nlb→compute).

---

## 2. Env / config-конвенция (зеркало `KACHO_VPC_COMPUTE_MTLS_*`)

compute (corelib `config.LoadPrefixed("KACHO_COMPUTE", &cfg)` через `envconfig`-теги) —
блок из пяти env-имён на ребро:

```
KACHO_COMPUTE_VPC_MTLS_ENABLE       (bool)
KACHO_COMPUTE_VPC_MTLS_CERTFILE     (path → client tls.crt)
KACHO_COMPUTE_VPC_MTLS_KEYFILE      (path → client tls.key)
KACHO_COMPUTE_VPC_MTLS_CAFILES      (path → internal-CA ca.crt)
KACHO_COMPUTE_VPC_MTLS_SERVERNAME   (dial-host SAN пира = vpc.kacho.svc.cluster.local)
```

> Поле `cfg.VPCMTLS` + helper `cfg.VPCClientCreds()` УЖЕ существуют — SEC-M их **потребляет**
> в dial-сайтах `vpcConn`/`vpcInternalConn`, а не заводит заново.

nlb (viper, `mapstructure`-делимитер `__`) — блоки **уже** существуют:
`KACHO_NLB_MTLS__VPC__{ENABLE,CERTFILE,KEYFILE,CAFILES,SERVERNAME}` (`cfg.MTLS.VPC`) и
`KACHO_NLB_MTLS__COMPUTE__*` (`cfg.MTLS.Compute`). SEC-M по nlb — verify, не добавление.

---

## A. Сценарии — corelib-примитив уже даёт контракт (регресс-якоря, SEC-B)

> НЕ новый код; фиксируют поведение `grpcclient.TLSClient`, на котором SEC-M держится.
> Verified против `kacho-corelib/grpcclient/tls.go`.

### A-01 — Enable=false → insecure, cert не читается (нулевая регрессия)
**Given** `TLSClient{Enable:false}` (любые/пустые cert-поля)
**When** строятся dial-creds
**Then** возвращается insecure transport-creds; CertFile/KeyFile/CAFiles **не** читаются;
поведение идентично доныне-plaintext dial-у.

### A-02 — Enable=true, валидный cert-trio → mTLS-creds
**Given** `TLSClient{Enable:true, CertFile, KeyFile, CAFiles:[ca], ServerName}` все валидны
**When** строятся dial-creds
**Then** возвращаются TLS-creds, предъявляющие client-cert, проверяющие server-cert против CA
и ServerName против SAN; ошибки нет.

### A-03 — Enable=true, пустой ca_files → fail-closed error
**Given** `TLSClient{Enable:true, CAFiles:[]}`
**When** строятся dial-creds
**Then** **error** (`ca_files is empty`), не insecure-fallback.

### A-04 — Enable=true, пустой server_name → fail-closed error
**Given** `TLSClient{Enable:true, ServerName:""}` (ca валиден)
**When** строятся dial-creds
**Then** **error** (`server_name is empty`), не insecure-fallback.

### A-05 — Enable=true, нечитаемый/garbage client cert → fail-closed error
**Given** `TLSClient{Enable:true}`, CertFile указывает на несуществующий/битый PEM
**When** строятся dial-creds
**Then** **error** (`load client cert/key`), не insecure-fallback.

---

## B. Сценарии COMPUTE (`kacho-compute`) — закрыть `vpcConn` + `vpcInternalConn`

Ground truth: `internal/config/config.go` (поле `cfg.VPCMTLS` + helper `cfg.VPCClientCreds()` —
УЖЕ есть, lines 148-182). Dial-сайты — `cmd/compute/main.go:332` (`vpcConn`,
`dialPeer(cfg.VPCGRPCAddr, cfg.VPCTLS, false)`) и `:337` (`vpcInternalConn`,
`dialPeer(cfg.VPCInternalGRPCAddr, cfg.VPCInternalTLS, false)`). SEC-M = протянуть
`cfg.VPCMTLS`-creds в оба dial-сайта через seam `dialPeerCreds`/`peerDialOptsCreds`
(тот же seam, что уже несёт iam-creds), ветвясь на `cfg.VPCMTLS.Enable` ровно как
`vpc→compute` ветвится на `mtlsCfg.ComputeMTLS.Enable`.

### B-01 — compute dev default: оба vpc-conn'а insecure (нулевая регрессия)
**Given** `KACHO_COMPUTE_VPC_MTLS_ENABLE` не задан / `=false`, `kacho-vpc` БЕЗ серверного
`RequireAndVerifyClientCert`
**When** compute выполняет `Instance.Create` (→ vpc Subnet/SecurityGroup/Address NIC-валидация
+ IPAM one-to-one-NAT alloc через internal-conn)
**Then** `vpcConn` и `vpcInternalConn` диалятся insecure (как сегодня через
`dialPeer(..., cfg.VPCTLS/VPCInternalTLS, false)`); cert-файлы не читаются; `Instance.Create`
работает; поведение/ошибки без изменений.

### B-02 — compute→vpc public edge mTLS on → NIC-spec валидация поверх mTLS
**Given** `KACHO_COMPUTE_VPC_MTLS_{ENABLE=true,CERTFILE,KEYFILE,CAFILES,SERVERNAME=
vpc.kacho.svc.cluster.local}`, vpc public :9090 на `RequireAndVerifyClientCert`
**When** compute выполняет `Instance.Create` с валидным NIC-spec (subnet_id, security_group_ids)
**Then** `vpcConn` предъявляет `kacho-compute-client-tls` client-cert, верифицирует vpc
server-cert против internal-CA и ServerName=`vpc` (∈ SAN); `Subnet.Get`/`SecurityGroup.Get`
отрабатывают; NIC-spec валиден; `Instance.Create` доходит до RUNNING.

### B-03 — compute→vpc internal edge (IPAM) mTLS on → one-to-one-NAT Address поверх mTLS
**Given** `KACHO_COMPUTE_VPC_MTLS_ENABLE=true` (тот же cert-trio, ServerName=`vpc`), vpc
internal :9091 на `RequireAndVerifyClientCert`
**When** `Instance.Create` с `one_to_one_nat` (требует IPAM-аллокацию Address через
`vpcInternalConn`)
**Then** `vpcInternalConn` предъявляет client-cert и верифицирует vpc server-cert +
ServerName=`vpc` (тот же Service-host покрывает :9091, M6); IPAM-аллокация Address успешна;
`Instance.Create` с one-to-one-NAT доходит до RUNNING.

### B-04 — compute→vpc оба conn'а делят один cert-trio + один ServerName (host `vpc`)
**Given** `KACHO_COMPUTE_VPC_MTLS_ENABLE=true`
**When** строятся creds для `vpcConn` (:9090) и `vpcInternalConn` (:9091)
**Then** оба conn'а используют **один** `cfg.VPCMTLS` (один cert-trio, один
ServerName=`vpc.kacho.svc.cluster.local`); per-listener split НЕ нужен — vpc Service `vpc`
один host для обоих портов (контраст с iam в SEC-I, M6).
*(verifies: единый ServerName корректен для обоих vpc-listener'ов — отличие от iam OQ-5.)*

### B-05 — compute остаточный plaintext vpc-edge при vpc-серверном mTLS → handshake FAILS (предотвращаемая регрессия)
**Given** vpc на `RequireAndVerifyClientCert`, но compute оставлен с plaintext vpc-dial
(`KACHO_COMPUTE_VPC_MTLS_ENABLE=false`, vpc-server уже требует cert)
**When** `Instance.Create` зовёт `Subnet.Get` по `vpcConn`
**Then** TLS-handshake падает (`error reading server preface: EOF` / `connection reset by
peer`, code 14) → `Subnet.Get` → `Unavailable` → `Instance.Create` fail-closed.
**Демонстрирует:** под vpc-серверным mTLS нельзя оставить compute→vpc plaintext —
completeness-инвариант (M2). Это и есть регрессия, которую SEC-M предотвращает.

### B-06 — compute seam threading сохраняет совместимость для остальных dial-ов
**Given** `vpcConn`/`vpcInternalConn` теперь резолвят `cfg.VPCMTLS` через
`dialPeerCreds`/`peerDialOptsCreds`
**When** compute диалит vpc (SEC-M), iam (SEC-I, через `dialPeerCreds`) и любые legacy
bool-TLS-пиры
**Then** каждое ребро резолвит свой `TLSClient`/creds независимо; iam-рёбра (SEC-I) не
ломаются; существующий `peerDialOpts`/`peerDialOptsCreds`-seam-тест зелёный.
*(verifies: seam-рефактор compute→vpc не регрессит iam-рёбра.)*

### B-07 — compute fail-closed на кривой конфиг (зеркало A-03/A-04/A-05)
**Given** `KACHO_COMPUTE_VPC_MTLS_ENABLE=true` с пустым CAFILES / пустым SERVERNAME / битым cert
**When** compute стартует (creds строятся на composition-root, до Serve)
**Then** startup-error, pod не стартует (no silent insecure); видимый отказ.

---

## C. Сценарии NLB (`kacho-nlb`) — `nlb→vpc` + `nlb→compute` УЖЕ mTLS; SEC-M = verify + regress-anchor

> **Ground-truth:** NLB **не** содержит plaintext vpc/compute resource-creation рёбер.
> `cmd/kacho-loadbalancer/main.go:582` (`compute` → `cfg.MTLS.Compute`), `:595`
> (`vpc-public` → `cfg.MTLS.VPC`), `:601` (`vpc-internal` → `cfg.MTLS.VPC`) **уже**
> диалятся через `dialOne(name, addr, useTLS, mtls)`, который при `mtls.Enable=true`
> строит `grpcclient.TLSClientTransportCreds` и передаёт через `clients.BuildOptions.MTLSCreds`.
> SEC-M по nlb = **подтвердить** это (regress-anchor) + helm-render verify, а НЕ добавлять dial-ы.

### C-01 — nlb baseline: vpc/compute рёбра уже предъявляют client-cert (НЕ регрессировать)
**Given** `cfg.MTLS.VPC.Enable=true` + `cfg.MTLS.Compute.Enable=true`
**When** nlb диалит `vpc-public` (:595), `vpc-internal` (:601), `compute` (:582)
**Then** все три conn'а строятся через `dialOne(..., creds)` и предъявляют
`kacho-nlb-client-tls` client-cert; `Address/Subnet/NIC.Get` (vpc), IPAM
(`InternalAddressService`, vpc :9091) и `Region/Instance.Get` (compute) — все mTLS.
*(SEC-M не должен превратить уже-mTLS-conn в plaintext.)*

### C-02 — nlb→vpc под vpc-серверным mTLS с корректным ServerName
**Given** vpc на `RequireAndVerifyClientCert`, nlb `vpc-public`/`vpc-internal` conn'ы
выставляют ServerName=`vpc.kacho.svc.cluster.local`
**When** nlb create-флоу резолвит Address/Subnet/NIC + IPAM
**Then** ServerName ∈ vpc server-SAN (host `vpc`); handshake проходит; vpc-RPC работают.

### C-03 — nlb→compute под compute-серверным mTLS с корректным ServerName
**Given** compute на `RequireAndVerifyClientCert`, nlb `compute` conn выставляет ServerName=
`compute.kacho.svc.cluster.local`
**When** nlb create-флоу резолвит Region/Instance
**Then** ServerName ∈ compute server-SAN (host `compute`); handshake проходит; compute-RPC работают.

### C-04 — nlb dev default: vpc/compute рёбра insecure при `Enable=false`
**Given** `cfg.MTLS.VPC.Enable=false` + `cfg.MTLS.Compute.Enable=false`, vpc/compute БЕЗ
серверного mTLS
**When** nlb диалит vpc/compute
**Then** все conn'а insecure (текущий dev); cert не читается; нулевая регрессия.

### C-05 — nlb остаточный plaintext под серверным mTLS → handshake FAILS
**Given** vpc (или compute) на `RequireAndVerifyClientCert`, соответствующее nlb-ребро
оставлено plaintext (`Enable=false`)
**When** nlb-флоу зовёт RPC по этому conn'у
**Then** handshake падает (code 14) → RPC `Unavailable` → операция fail-closed.
Completeness-инвариант (M2).

---

## D. Сценарии helm / deploy (`kacho-deploy`) — переиспользовать смонтированный secret

Ground truth: `kacho-<svc>-client-tls` secret **уже смонтирован** в каждый pod (compute/nlb)
в раздельный volume `$cli = {mountPath}/client` (tls.crt/tls.key/ca.crt;
`clientSecretName: kacho-<svc>-client-tls`). compute deploy-template УЖЕ рендерит
`KACHO_COMPUTE_VPC_MTLS_*` gated на `mtls.edges.vpc`; nlb configmap УЖЕ рендерит
`mtls.vpc`/`mtls.compute`-блоки gated на `mtls.edges.vpc`/`mtls.edges.compute`.

### D-01 — compute helm OFF (default): vpc-edge env нет (нулевая dev-регрессия)
**Given** `helm template compute kacho-compute/deploy` без mtls-override (mtls.enable не задан)
**When** рендерится Deployment
**Then** **нет** `KACHO_COMPUTE_VPC_MTLS_*` env; нет лишних volume/mount; поведение чарта как сегодня.

### D-02 — compute helm ON: `KACHO_COMPUTE_VPC_MTLS_*` рендерится, secret переиспользуется
**Given** `helm template compute kacho-compute/deploy --set mtls.enable=true --set mtls.edges.vpc=true`
**When** рендерится Deployment
**Then** появляются `KACHO_COMPUTE_VPC_MTLS_{ENABLE,CERTFILE,KEYFILE,CAFILES,SERVERNAME}`;
CERTFILE/KEYFILE/CAFILES указывают в **существующий** `$cli`-volume (`kacho-compute-client-tls`,
тот же, что у iam-рёбер); **нового** secret'а/volume'а не добавлено (M1).

### D-03 — compute helm ServerName-корректность (M6)
**Given** ON-рендер
**When** проверяется `KACHO_COMPUTE_VPC_MTLS_SERVERNAME`
**Then** значение = `vpc.kacho.svc.cluster.local` (host `vpc`, покрывает оба vpc-listener'а);
∈ vpc server-SAN (cert-manager-config `serverHosts` для vpc).

### D-04 — nlb helm: `mtls.vpc`/`mtls.compute`-блоки рендерятся, secret переиспользуется
**Given** `helm template nlb kacho-nlb/deploy --set mtls.enable=true --set mtls.edges.vpc=true
--set mtls.edges.compute=true`
**When** рендерится configmap (nlb config.yaml)
**Then** `mtls.vpc.enable=true` (ServerName=`vpc.kacho.svc.cluster.local`) и
`mtls.compute.enable=true` (ServerName=`compute.kacho.svc.cluster.local`); certfile/keyfile/cafiles
указывают в существующий `$cli`-volume (`kacho-nlb-client-tls`); нового secret'а/volume'а нет (M1).
OFF (без override) — блоки `enable=false`/пусты, cert-пути не выставлены.

### D-05 — umbrella `values.mtls.yaml`: per-service opt-in resource-creation рёбер
**Given** `values.mtls.yaml` уже включает `vpc.mtls.edges.compute=true` (vpc→compute) и
`kacho-nlb.mtls.edges.vpc=true`/`compute=true`
**When** добавляется `compute.mtls.edges.vpc=true` (+ умбрелла-intent-флаг `compute_to_vpc` и,
для симметрии графа, `nlb_to_vpc`/`nlb_to_compute`, если их ещё нет в `edges:`-секции)
**Then** umbrella-рендер прокидывает их в subchart'ы; включение серверного mTLS на vpc/compute
сопровождается включением ВСЕХ входящих resource-creation client-рёбер (completeness-gate, §E).

---

## E. Completeness-gate (SEC-M-07) — «ни одно resource-creation-ребро не plaintext» по ФАКТИЧЕСКОМУ набору

> Gate проверяет per-service фактический набор vpc/compute-dialing conn'ов, а НЕ
> фиксированный список. Иначе он потребует несуществующего ребра (ложный fail) или
> пройдёт вакуумно.

### SEC-M-07 — статический gate: каждый vpc/compute-dialing conn предъявляет cert под серверным mTLS пира
**Given** фактический набор resource-creation-conn'ов:
- vpc→compute: `computeConn` (`ZoneService.Get`) — **уже mTLS (SEC-D-19)**
- compute→vpc: `vpcConn` (NIC-spec, :9090) + `vpcInternalConn` (IPAM, :9091) — **SEC-M закрывает**
- nlb→vpc: `vpcPublicConn` + `vpcInternalConn` (`cfg.MTLS.VPC`) — **уже mTLS**
- nlb→compute: `computeConn` (`cfg.MTLS.Compute`) — **уже mTLS**

**When** прогоняется статическая проверка (grep dial-сайтов + helm-render-assertion в
`service-mtls-wiring-test.sh`) + cluster smoke с vpc/compute на `RequireAndVerifyClientCert`
**Then** **каждый** перечисленный conn под mTLS-профилем строится с client-cert (не insecure);
ни один resource-creation-conn не остаётся plaintext; gate enumerates именно эти conn'ы (не
требует отсутствующих рёбер).

### SEC-M-08 — финальный e2e smoke (зеркало SEC-D/SEC-I DoD)
**Given** kind-стенд, `values.mtls.yaml` (vpc/compute серверный mTLS on + все
resource-creation рёбра on)
**When** прогон базового e2e: `Instance.Create` с NIC-spec + one-to-one-NAT (compute→vpc
NIC/IPAM); NLB-create-флоу (nlb→vpc + nlb→compute) при vpc/compute на
`RequireAndVerifyClientCert`
**Then** все операции зелёные; в логах vpc/compute НЕТ handshake-ошибок ни по одному
resource-creation ребру; захват показывает client-cert на каждом compute→vpc /
nlb→{vpc,compute} dial'е.

---

## 3. Карта изменений (для impl-агента; пути и строки — ground truth)

| Репо / файл | Что | Что НЕ делать |
|---|---|---|
| `kacho-compute/cmd/compute/main.go` (`dialPeers`, `vpcConn` `:332`, `vpcInternalConn` `:337`) | ветвить на `cfg.VPCMTLS.Enable` → дилить оба conn'а через `dialPeerCreds`/`peerDialOptsCreds` с `cfg.VPCClientCreds()` (зеркало `vpc→compute` ветки `mtlsCfg.ComputeMTLS.Enable`); else текущий `dialPeer(..., cfg.VPCTLS/VPCInternalTLS, false)` | **не** заводить `cfg.VPCMTLS`/`VPCClientCreds()` заново (УЖЕ есть, config.go:148-182); не трогать iam-conn'ы (SEC-I) и register-drainer (SEC-D) |
| `kacho-compute/internal/config/config.go` | **ничего** — `VPCMTLS` + `VPCClientCreds()` уже на месте | не создавать `mtls.go` (фантомный путь); не дублировать поле |
| `kacho-nlb/cmd/kacho-loadbalancer/main.go` (`compute` `:582`, `vpc-public` `:595`, `vpc-internal` `:601`) | **verify-only** — подтвердить, что `dialOne(..., cfg.MTLS.{VPC,Compute})` реально потребляет creds | **не** добавлять plaintext-dial-ы; не объявлять «insecure path»; правка только если verify выявит несоответствие |
| `kacho-compute/deploy/templates/deployment.yaml` + `deploy/values.yaml` | **ничего** (уже рендерит `KACHO_COMPUTE_VPC_MTLS_*` + `edges.vpc`/`serverName.vpc`) | не дублировать env-блок |
| `kacho-nlb/deploy/templates/configmap.yaml` + `deploy/values.yaml` | **ничего** (уже рендерит `mtls.vpc`/`mtls.compute`) | не дублировать |
| `kacho-deploy/helm/umbrella/values.mtls.yaml` | `compute.mtls.edges.vpc=true` (compute→vpc) + добавить umbrella-intent-флаги `compute_to_vpc` (+ `nlb_to_vpc`/`nlb_to_compute`, если их нет в `edges:`) | `kacho-nlb.mtls.edges.vpc/compute` уже стоят — не дублировать |
| `kacho-deploy/tests/helm/service-mtls-wiring-test.sh` | расширить compute OFF/ON-ассерты на `KACHO_COMPUTE_VPC_MTLS_*` (ServerName=`vpc.*`, reuse client-secret) + nlb `mtls.vpc`/`mtls.compute` render-assert + per-service completeness (§E) | — |

---

## 4. Тестовая стратегия (строгий TDD, ban #12)

- **RED ДО кода** на каждом уровне; в PR показать пару RED→GREEN.
- **corelib (A-01..A-05):** уже покрыто `grpcclient` unit-тестами (SEC-B) — регресс-якорь.
- **compute (wiring):** unit/seam-тест на ветвление `vpcConn`/`vpcInternalConn` по
  `cfg.VPCMTLS.Enable` (расширить существующий `peerDialOpts`/`peerDialOptsCreds`-seam-тест,
  B-06) + fail-closed (B-07 ⇄ A-03/A-04/A-05) + единый ServerName для обоих vpc-conn'ов (B-04).
- **nlb (verify):** unit/assert, что `dialOne(..., cfg.MTLS.{VPC,Compute})` строит mTLS-creds
  при `Enable=true` (C-01); если verify выявит plaintext — это finding (GitHub Issue `bug` +
  RED-тест), фикс в отдельном PR со своим KAC (ban #13).
- **handshake-FAIL якоря (B-05/C-05):** integration/среда с vpc/compute на
  `RequireAndVerifyClientCert` — plaintext-ребро → `Unavailable`; mTLS-ребро → success.
- **helm (D-01..D-05, E):** манифест-ассерты в `service-mtls-wiring-test.sh` (compute OFF: нет
  `KACHO_COMPUTE_VPC_MTLS_*`; ON: точные env-имена + ServerName=`vpc.*` + reuse client-secret;
  nlb: `mtls.vpc`/`mtls.compute` render) + per-service completeness-gate.
- **e2e smoke (SEC-M-08):** kind с `values.mtls.yaml` (vpc/compute серверный mTLS + все
  resource-creation рёбра on); `Instance.Create` (NIC + one-to-one-NAT) + NLB-create зелёные;
  vpc/compute-логи без handshake-ошибок.
- Финал перед merge: `go test ./... -race` + `golangci-lint run` + `govulncheck` +
  helm wiring-тест + smoke зелёные.

---

## 5. Non-goals (явно вне scope)

- **Контракт/proto/RPC** — без изменений (`kacho-proto` не трогаем). Меняется только транспорт dial-а.
- **NIC-spec / IPAM / Address-allocation семантика** — без изменений (только транспорт compute→vpc).
- **iam-рёбра (`*→iam`)** — закрыты SEC-I; **не переделывать**.
- **register-drainer ребро (SEC-D)** — уже mTLS; **не переделывать**.
- **`vpc→compute` ребро (SEC-D-19)** — уже отгружено; SEC-M его не трогает (только enumerates в gate §E).
- **Серверная сторона vpc/compute (`RequireAndVerifyClientCert`)** — отдельная под-фаза;
  SEC-M — только клиентская половина resource-creation рёбер.
- **`kacho-corelib` `grpcclient`** — примитив готов (SEC-B); не расширять.
- **`kacho-api-gateway`** — backend-dial mTLS закрыт SEC-E; вне SEC-M.
- **Cert-rotation runtime-reload** — out of scope (rotation = pod restart, эпик).
- **Новые secret'ы / volume'ы / CA / порты** — запрещены; reuse `kacho-<svc>-client-tls`.

---

## 6. Открытые вопросы (решить ДО кода)

- **OQ-1 (compute single-vs-split поле).** `vpcConn` (:9090) и `vpcInternalConn` (:9091)
  диалят **один** vpc Service-host `vpc` → один ServerName покрывает оба порта (M6).
  Рекомендация: **один** `cfg.VPCMTLS` (уже существующее поле) для обоих conn'ов — НЕ заводить
  per-listener split (контраст с iam SEC-I OQ-5, где Service'ы различаются). Подтверждено
  ground-truth (vpc Service = `vpc`; compute helm `serverName.vpc` — одно значение).
- **OQ-2 (compute seam форма).** Протянуть `cfg.VPCClientCreds()` (grpc.DialOption) напрямую
  как `vpc→compute`, ИЛИ через `dialPeerCreds`(`TransportCredentials`)? Рекомендация: переиспользовать
  существующий `dialPeerCreds`/`peerDialOptsCreds` seam (тот, что уже несёт iam-creds) — единый путь,
  существующий seam-тест расширяется, не дублируется.
- **OQ-3 (nlb verify-исход).** Если verify (C-01) подтверждает, что `dialOne` уже потребляет
  `cfg.MTLS.{VPC,Compute}` — nlb не требует прод-кода (только wiring-test-assert). Если выявит
  расхождение — finding → GitHub Issue + отдельный PR/KAC (ban #13). Зафиксировать исход ДО impl.
- **OQ-4 (umbrella intent-флаги).** Нужны ли явные `compute_to_vpc` / `nlb_to_vpc` /
  `nlb_to_compute` в `mtls.edges:`-секции `values.mtls.yaml` (для симметрии с
  `vpc_to_iam`/`compute_to_iam`/`operator_to_vpc`), или достаточно прямого
  `compute.mtls.edges.vpc=true` в subchart-блоке? Решить для консистентности профиля.

---

## 7. Traceability

| Требование (prompt) | Сценарии |
|---|---|
| (A) compute→vpc enable=true → дилит vpc (+vpc-internal) с client cert → Instance.Create (NIC/IPAM) ok; enable=false → insecure (unchanged) | A-02, B-01, B-02, B-03, B-04, D-02 |
| (B) plaintext compute→vpc под vpc-серверным mTLS FAILS (предотвращаемая регрессия, code 14 reset) | B-05, SEC-M-07, SEC-M-08 |
| (C) nlb→vpc + nlb→compute предъявляют client cert | C-01, C-02, C-03, D-04 |
| (D) per-edge ServerName-корректность (vpc dial-host `vpc.kacho.svc.cluster.local` ∈ vpc SAN; compute ∈ compute SAN) | M6, B-04, C-02, C-03, D-03, D-04 |
| (E) helm рендерит новые env/config только при enable, reuse существующих client-cert secret'ов | D-01..D-05, M1 |
| (F) completeness: каждый resource-creation dial к mTLS-серверу покрыт (нет plaintext-ребра под mTLS-профилем) | E (SEC-M-07/08), B-05, C-05 |
| enable=false → insecure, нулевая регрессия | A-01, B-01, C-04, D-01 |
| Зеркало паттерна `vpc→compute` + SEC-I, без contract-изменений | §0, §5 Non-goals, M1 |

| Sub-phase | Roadmap |
|---|---|
| SEC-B | corelib `grpcclient.TLSClient` (примитив) — done |
| SEC-D | per-edge mTLS config + register-drainer + `vpc→compute` (SEC-D-19) — done |
| SEC-F | cert-manager internal-CA PKI + `kacho-<svc>-{server,client}-tls` — done |
| SEC-H | `kacho-iam` server `RequireAndVerifyClientCert` — done |
| SEC-I | CLIENT mTLS на read/authz рёбрах `*→iam` (vpc/compute/nlb) — done |
| **SEC-M** | **CLIENT mTLS на resource-creation рёбрах `compute→vpc` (закрыть) + `nlb→{vpc,compute}` (verify) — завершение меша** |

---

## 8. Definition of Done

- [ ] OQ-1..OQ-4 решены (OQ-3 — verify-исход nlb зафиксирован ДО impl).
- [ ] compute: `vpcConn` (:9090) + `vpcInternalConn` (:9091) предъявляют `kacho-compute-client-tls`
      client-cert при `cfg.VPCMTLS.Enable=true` (через `dialPeerCreds`/`peerDialOptsCreds` seam);
      fail-closed при кривом конфиге; dev insecure при `Enable=false`. `cfg.VPCMTLS`/`VPCClientCreds()`
      НЕ передублированы.
- [ ] compute: единый `cfg.VPCMTLS` (один ServerName=`vpc.*`) корректен для обоих vpc-listener'ов
      (B-04); iam-рёбра (SEC-I) не регрессировали; `peerDialOpts`-seam-тест зелёный.
- [ ] nlb: verify подтверждён — `nlb→vpc` (`cfg.MTLS.VPC`) + `nlb→compute` (`cfg.MTLS.Compute`)
      предъявляют client-cert; не регрессируют в plaintext; расхождение (если есть) → отдельный KAC/PR.
- [ ] helm: compute `KACHO_COMPUTE_VPC_MTLS_*` (ServerName=`vpc.*`, reuse `kacho-compute-client-tls`)
      и nlb `mtls.vpc`/`mtls.compute` рендерятся только при enable; OFF-рендер чист (D-01..D-05).
- [ ] umbrella `values.mtls.yaml`: `compute.mtls.edges.vpc=true` (+ intent-флаги per OQ-4);
      `kacho-nlb.mtls.edges.vpc/compute` подтверждены on.
- [ ] `service-mtls-wiring-test.sh`: compute OFF/ON-ассерты на `KACHO_COMPUTE_VPC_MTLS_*` +
      nlb `mtls.vpc`/`mtls.compute` render + per-service completeness-gate (§E, фактический набор
      conn'ов, без фантомных рёбер).
- [ ] TDD RED→GREEN на каждом уровне; финал: `go test ./... -race` + `golangci-lint` +
      `govulncheck` + helm wiring + smoke (SEC-M-08) зелёные.
- [ ] Completeness verified: с vpc/compute на `RequireAndVerifyClientCert` НИ ОДНО
      resource-creation ребро (`compute→vpc`, `nlb→vpc`, `nlb→compute`) не plaintext (SEC-M-07/08);
      `Instance.Create` (NIC + one-to-one-NAT) и NLB-create зелёные end-to-end.
- [ ] Non-goals соблюдены: без proto/contract-изменений; iam-рёбра (SEC-I), register-drainer
      (SEC-D), `vpc→compute` (SEC-D-19) не переделаны.
- [ ] vault-trail: `edges/compute-to-vpc-nic-validate.md` (+ nlb→vpc/compute edges) обновлены
      (transport теперь mTLS, History-запись с KAC-номером) + KAC-trail.
