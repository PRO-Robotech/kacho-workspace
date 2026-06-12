# Sub-phase SEC-H — kacho-iam: gRPC server-side mTLS on public (:9090) + internal (:9091) listeners (opt-in per-edge) — Acceptance

> **Статус:** DRAFT
> **Дата:** 2026-06-11
> **Ревьюер:** `acceptance-reviewer` (единственный gate ✅ APPROVED — ban #1; заказчик к контракту не подключается, проверяет только финальный e2e/smoke)
> **Эпик/тикет:** KAC-<N> (subtask of эпик `[EPIC] SEC — mTLS + IAM-fronted authz`, см. `docs/specs/sub-phase-SEC-mtls-iam-authz-epic.md`)
> **Автор-агент:** `acceptance-author`
> **Затронутые репо:** `kacho-iam` (config + cmd-wiring), `kacho-deploy` (kacho-iam subchart — mtls env + server-tls secret mount).
> **Зависит от:** SEC-B (corelib `grpcsrv.TLSServer` + `grpcsrv.TLSServerCreds` + `UnaryCertIdentityExtract`/`StreamCertIdentityExtract` — уже в main); SEC-C (client-cert→SA mapping в IAM, identity-extractor consumed); SEC-D (vpc/compute/nlb server-side mTLS — **готовый образец, который SEC-H зеркалит 1:1**); SEC-F (cert-manager PKI, internal CA, per-svc `Certificate`); по cert-выпуску `kacho-iam-server-tls` — SEC-F.

---

## 0. Обзор

SEC-H закрывает последнюю незакрытую серверную дырку в mTLS-периметре: **kacho-iam сам
по-прежнему слушает оба своих gRPC-listener'а (:9090 public, :9091 internal) в plaintext**,
даже когда все остальные сервисы (vpc/compute/nlb) уже презентуют server-cert и требуют
client-cert (SEC-D, в main). Это асимметрия безопасности: vpc/compute/nlb **дилят** IAM по
mTLS как клиенты (`mtls.edges.iamRegister`), но **сам IAM** не верифицирует входящие
client-cert — его internal listener принимает кого угодно, а уже-добавленные
`UnaryCertIdentityExtract`/`StreamCertIdentityExtract`-интерсепторы (serve.go) сидят на
plaintext-канале и не видят верифицированный peer-cert, значит работают как no-op.

SEC-H — **строгий MIRROR готового SEC-D-паттерна** на kacho-iam: тот же corelib-helper
`grpcsrv.TLSServerCreds(grpcsrv.TLSServer)`, та же per-edge value-структура,
те же env-имена `KACHO_IAM_{PUBLIC,INTERNAL}_SERVER_MTLS_{ENABLE,CERTFILE,KEYFILE,CLIENTCAFILES}`,
тот же helm-механизм (`mtls.enable` + per-edge → server-tls secret mount). **Новый дизайн НЕ
изобретается** — задача чисто wiring: подключить уже существующий helper к двум уже
существующим `grpcsrv.NewServer(...)` в `cmd/kacho-iam/serve.go`.

**Инвариант (ground truth, не менять):** `enable=false` (default) → insecure, текущее
plaintext-поведение, **нулевая регрессия** (dev/CI/уже-задеплоенный чарт работают без правок
конфигурации). `enable=true` → listener презентует cert `kacho-iam-server-tls` и
**требует+верифицирует** client-cert против internal CA (`RequireAndVerifyClientCert`).
Public и internal listener — **два независимых per-edge ребра** (у каждого своя `TLSServer`).

**Контракты НЕ меняются** (требование эпика #8): proto-форма ресурсов IAM
(Account/Project/User/SA/Group/Role/AccessBinding) и Internal-сервисов
(`InternalIAMService`/`InternalUserService`) неизменна; REST-пути неизменны; JWT authN
(валидация токена в api-gateway + `x-kacho-principal-*` metadata) — без изменений; FGA-модель
и `fga_outbox`-drainer — без изменений. SEC-H — **транспортный слой**, не прикладной.

### Трассировка требований эпика → SEC-H

| Эпик | Где закрывается в SEC-H |
|---|---|
| #1/#5 (mTLS opt-in, не ломает dev; раздельные server+client cert) | S1 (server-creds per-listener, `enable=false`=insecure, Сценарий SEC-H-01) |
| #8 (контракты не меняются — только транспорт) | весь SEC-H: 0 proto-diff, 0 REST-diff, JWT/FGA нетронуты (Сценарий SEC-H-12) |
| §4.1.2 / I2 (principal⟺mTLS — principal-metadata доверяется только при верифицированном peer) | S1 + Сценарий SEC-H-11 (trust-инвариант: `CertIdentityFromContext` заполнен только при mTLS) |
| §6.5 (rollback per-edge feature-flag) | public и internal listener — независимые `enable`; один можно включить, другой нет (Сценарий SEC-H-08) |
| §6.7 (fail-closed на handshake) | plaintext-клиент против mTLS-listener → handshake reject, **нет** insecure-downgrade (Сценарий SEC-H-06) |
| SEC-C identity-extractor (consumed by IAM) | internal listener mTLS делает `UnaryCertIdentityExtract` функциональным — видит верифицированный SAN (Сценарий SEC-H-04) |

### Не входит в SEC-H (явно)

- **corelib TLS-primitive** (`grpcsrv.TLSServer`, `TLSServerCreds`, `UnaryCertIdentityExtract`) — **SEC-B** (готово в main; здесь только wiring).
- **client-cert→SA mapping** (как верифицированный SAN превращается в IAM-SA / least-priv tuple) — **SEC-C** (готово; SEC-H лишь даёт извлекателю реальный verified-cert).
- **client-side mTLS** исходящих рёбер IAM (`subject_change`-drainer → api-gateway internal, `fga_outbox` НЕ ходит наружу) — отдельное client-edge (если требуется) — **не** в SEC-H (здесь только **server-side** на двух IAM-listener'ах).
- **cert-manager PKI, выпуск `Certificate` `kacho-iam-server-tls`, internal CA, NetworkPolicy** — **SEC-F** (SEC-H лишь монтирует уже-выпущенный secret).
- **api-gateway→IAM backend-dial по mTLS** (gateway как клиент IAM) — **SEC-E** (это client-side gateway; server-side IAM — здесь).
- **vpc/compute/nlb server-side mTLS** — **SEC-D** (готово в main; SEC-H — тот же паттерн на IAM).

---

## 1. Связь с регламентом и запретами (нормативно — детали в `.claude/rules/*`, не дублируем)

| Регламент | Где соблюдаем в SEC-H |
|---|---|
| ban #1 (acceptance-first) | данный doc — gate; код только после ✅ APPROVED. |
| ban #2 (нет чужих облаков) | env/имена/cert — только `kacho`/`KACHO_IAM`; никаких чужих вендоров. |
| ban #6 / `security.md` (Internal.* не на external) | SEC-H не меняет регистрацию RPC — `InternalIAMService`/`InternalUserService` остаются на :9091; mTLS лишь укрепляет транспорт обоих listener'ов. |
| ban #8 / #4 (DB-per-service, no cross-service cascade) | SEC-H не трогает БД/схему/миграции — чисто транспорт + config + helm. |
| ban #9 (мутации → Operation) | контракт мутаций неизменен; SEC-H — транспортный слой. |
| ban #11 (без тех-долга/TODO) | `enable=true` без валидного cert-trio → **error на старте** (fail-closed), не silent-insecure и не TODO. |
| ban #12 (TDD, тесты в том же PR) | RED config-unit (`mtls_test.go`) + bufconn/integration handshake-тест + helm-render-тест до кода; §6 — источник сценариев. |
| `api-conventions.md` (error-format) | transport-reject клиента → `codes.Unavailable` (fail-closed для мутаций); тексты прикладных ошибок неизменны. |
| `architecture.md` (clean arch, wiring в composition root) | `TLSServer`-структура + `LoadMTLS`/`*ServerCreds` — в `internal/apps/kacho/config/mtls.go`; подключение `ServerOption` в `grpcsrv.NewServer(...)` — только в `cmd/kacho-iam/serve.go` (composition root). Никаких глобальных синглтонов. |
| `polyrepo.md` (порядок merge) | corelib не трогаем (SEC-B готов) → `kacho-iam` → `kacho-deploy` (subchart). |

---

## 2. Глоссарий (SEC-H-специфика)

- **server-edge** — один gRPC-listener IAM, на котором включается server-side mTLS.
  В IAM их **два**: `public` (:9090, tenant-facing RPC через api-gateway) и `internal`
  (:9091, `InternalIAMService`/`InternalUserService`, kacho-only). Каждый — независимый
  per-edge `enable`.
- **`grpcsrv.TLSServer` (SEC-B)** — горизонтальная per-edge value-структура corelib:
  `{Enable bool; CertFile string; KeyFile string; ClientCAFiles []string}`. Без абсолютных
  envconfig-тегов — env-имя выводится из иерархии полей embedding-структуры сервиса.
- **`grpcsrv.TLSServerCreds(cfg)` (SEC-B)** — builder, возвращающий `grpc.ServerOption`:
  `enable=false` → `insecure` creds (cert-файлы НЕ читаются); `enable=true` → `RequireAndVerifyClientCert`
  (server-cert из `CertFile`/`KeyFile` + client-CA-pool из `ClientCAFiles`); `enable=true`
  + нечитаемый/мусорный cert / пустой client-CA → **error** (fail-closed, без silent insecure).
- **`UnaryCertIdentityExtract`/`StreamCertIdentityExtract` (SEC-B)** — интерсепторы IAM
  internal listener (уже в `serve.go`): читают **верифицированный** peer client-cert SAN из
  `peer.Peer.AuthInfo` (TLS) и кладут identity в ctx (`CertIdentityFromContext`). На plaintext-канале
  `AuthInfo` пуст → no-op (ctx нетронут). SEC-H даёт им реальный verified-cert.
- **per-edge env-блок** — `KACHO_IAM_PUBLIC_SERVER_MTLS_*` и `KACHO_IAM_INTERNAL_SERVER_MTLS_*`,
  каждый из 4 ключей `{ENABLE,CERTFILE,KEYFILE,CLIENTCAFILES}`. Загружаются ОТДЕЛЬНО от viper-YAML
  через envconfig `corecfg.LoadPrefixed("KACHO_IAM", &cfg)` (mirror vpc `LoadMTLS`).
- **server-tls secret** — k8s Secret `kacho-iam-server-tls` (`tls.crt`/`tls.key`/`ca.crt`),
  выпущенный cert-manager (SEC-F). Монтируется в pod как volume `mtls-server` **только** когда
  mTLS включён в чарте; env `*_CERTFILE`/`*_KEYFILE`/`*_CLIENTCAFILES` указывают на mount-path.
- **mirror-инвариант** — все имена/значения/механизмы SEC-H обязаны побайтово соответствовать
  SEC-D vpc/compute/nlb (env-суффиксы, helm-ключи `mtls.enable`, secret-суффикс `-server-tls`,
  volume `mtls-server`, поведение `enable=false`/`enable=true`/fail-closed). Любое расхождение — баг SEC-H.

---

## 3. Стадии (каждая — самостоятельный end-to-end deliverable со своим DoD)

SEC-H — небольшой mirror-патч, дробится на 2 стадии; обе оставляют main в рабочем состоянии:

| Стадия | Репо | Содержание | Тип-флага в main |
|---|---|---|---|
| **S1** | `kacho-iam` | `internal/apps/kacho/config/mtls.go` (mirror vpc): `MTLSConfig{ PublicServerMTLS, InternalServerMTLS grpcsrv.TLSServer }` + `LoadMTLS()` (`corecfg.LoadPrefixed("KACHO_IAM", …)`) + `PublicServerCreds()`/`InternalServerCreds()`. Wiring в `cmd/kacho-iam/serve.go`: оба `grpcsrv.NewServer(...)` принимают соответствующий `grpc.ServerOption`-creds первым аргументом (как vpc). | `*_SERVER_MTLS_ENABLE` default `false` (dev unchanged) |
| **S2** | `kacho-deploy` | kacho-iam subchart рендерит `KACHO_IAM_{PUBLIC,INTERNAL}_SERVER_MTLS_*` env + монтирует `kacho-iam-server-tls` (volume `mtls-server`) **только** при mTLS-on, через umbrella `mtls.enable` + per-edge (mirror vpc/compute subchart); umbrella `values.mtls.yaml` overlay включает server-edge IAM. | umbrella `mtls.enabled` default `false`; OFF → 0 env, 0 mount |

> S1 → S2 по build-графу (`kacho-iam` до `kacho-deploy`). Пока S1 не в main — S2-CI пиннит
> kacho-iam к feature-ветке (`polyrepo.md`).

---

## 4. Точки изменения (для точности impl — НЕ предписание дизайна, а карта mirror'а)

| Артефакт IAM | Образец SEC-D (vpc) | Что делает SEC-H |
|---|---|---|
| `internal/apps/kacho/config/mtls.go` (новый) | `project/kacho-vpc/internal/apps/kacho/config/mtls.go` | `MTLSConfig` с `PublicServerMTLS`/`InternalServerMTLS grpcsrv.TLSServer` (envconfig-теги `PUBLIC_SERVER_MTLS`/`INTERNAL_SERVER_MTLS`) + `LoadMTLS()` (`mtlsEnvPrefix="KACHO_IAM"`) + `PublicServerCreds()`/`InternalServerCreds()`. **Без** client-edges (IAM — leaf-owner, исходящих peer-дилов на ресурсы нет; subject_change client-edge — вне SEC-H). |
| `internal/apps/kacho/config/mtls_test.go` (новый) | `project/kacho-vpc/internal/apps/kacho/config/mtls_test.go` | unit: default off, enable=true без cert → error, enable=true с cert-trio → ServerOption. |
| `cmd/kacho-iam/serve.go` | `project/kacho-vpc/cmd/vpc/main.go` (стр. ~343-368) | `mtlsCfg, _ := config.LoadMTLS()`; `publicServerCreds, err := mtlsCfg.PublicServerCreds()`; `internalServerCreds, err := mtlsCfg.InternalServerCreds()`; передать как первый аргумент в существующие `grpcsrv.NewServer(...)` для `grpcSrv` и `internalSrv`; `logger.Info("kacho-iam listener mTLS", "public_mtls", …, "internal_mtls", …)`. Существующие interceptor-цепочки (`UnaryPrincipalExtract`, `AntiAnonymousUnary`, `UnaryCertIdentityExtract`) **сохранены без изменений**. |
| kacho-iam subchart `deployment.yaml` + `values.yaml` | `helm/umbrella/charts/kacho-vpc/templates/deployment.yaml` | env `KACHO_IAM_{PUBLIC,INTERNAL}_SERVER_MTLS_{ENABLE,CERTFILE,KEYFILE,CLIENTCAFILES}` + volume `mtls-server` (secret `kacho-iam-server-tls`) + volumeMount — gated `if .Values.mtls.enable`. |
| umbrella `values.mtls.yaml` | существующий overlay | включить server-side mTLS для kacho-iam subchart (mirror vpc server-edge). |

> Ground truth wiring: corelib helper — `project/kacho-corelib/grpcsrv/tls.go`; serve.go
> текущий (plaintext) — `project/kacho-iam/cmd/kacho-iam/serve.go` (стр. 112-140 создают
> `grpcSrv`/`internalSrv` **без** TLS-ServerOption); helm-образец — `tests/helm/service-mtls-wiring-test.sh`.

---

## 5. Test discipline (ban #11/#12) — RED first

Каждый PR-набор стадии содержит тест, написанный **до** кода, с парой `RED → GREEN` в описании:

- **S1**: config-unit (`mtls_test.go`) — default-off / enable-true-no-cert-error / enable-true-creds;
  bufconn/integration handshake-тест (self-signed internal CA) — happy mTLS + no-client-cert-reject +
  cert-identity-visible. Зеркалит SEC-D `mtls_edge_handshake_ok` / `mtls_no_client_cert_rejected` /
  `mtls_disabled_default_insecure`.
- **S2**: helm-render assertions в `tests/helm/service-mtls-wiring-test.sh` (расширить блоком kacho-iam):
  OFF → нет server-mtls env, нет `mtls-server` volume, нет `kacho-iam-server-tls` secret; ON → все 4×2
  env + volume + secret присутствуют. Зеркалит vpc/compute-блоки того же скрипта.

Финальная верификация перед merge: `go test ./... -race` + `golangci-lint run` + `govulncheck`
(kacho-iam) + `helm lint`/`helm template` + `tests/helm/*.sh` зелёные.

---

## 6. Сценарии (Given-When-Then) — основа unit/integration/helm-тестов

> ID-формат: `SEC-H-<NN>` (трассируется в имена тестов). «handshake» = TLS-рукопожатие на gRPC-канале.
> «cert-trio» = (server-cert `CertFile`, key `KeyFile`, client-CA-bundle `ClientCAFiles`).

### 6.A — config (S1, unit)

#### Сценарий SEC-H-01 — mTLS disabled (default) → оба listener insecure, нулевая регрессия

**ID:** SEC-H-01

**Given** ни одна из env `KACHO_IAM_PUBLIC_SERVER_MTLS_ENABLE` / `KACHO_IAM_INTERNAL_SERVER_MTLS_ENABLE` не выставлена
**And** `MTLSConfig` загружен через `config.LoadMTLS()`

**When** проверяются `m.PublicServerMTLS.Enable` и `m.InternalServerMTLS.Enable`

**Then** оба `false` (zero-value)
**And** `m.PublicServerCreds()` и `m.InternalServerCreds()` возвращают `grpc.ServerOption` с **insecure** creds без ошибки (cert-файлы НЕ читаются)
**And** существующие unit/integration/newman-тесты kacho-iam зелёные без правок конфигурации (backward-compat, эпик §5)

---

#### Сценарий SEC-H-02 — `enable=true` без валидного cert-trio → error на старте (fail-closed, не silent-insecure)

**ID:** SEC-H-02

**Given** `KACHO_IAM_INTERNAL_SERVER_MTLS_ENABLE=true`, но `CERTFILE`/`KEYFILE` указывают на несуществующий путь (или `CLIENTCAFILES` пуст)

**When** вызывается `m.InternalServerCreds()` (в composition root — на старте процесса)

**Then** возвращается **error** (`grpcsrv: load server cert/key: …` либо `…client_ca_files is empty…`)
**And** `cmd/kacho-iam/serve.go` оборачивает её (`"internal listener mTLS creds: %w"`) и процесс **падает на старте** — нет запуска listener'а в plaintext под видом включённого mTLS (no silent downgrade, ban #11)

---

#### Сценарий SEC-H-03 — `enable=true` с валидным cert-trio → ServerOption построен

**ID:** SEC-H-03

**Given** `KACHO_IAM_INTERNAL_SERVER_MTLS_ENABLE=true`, `CERTFILE`/`KEYFILE` указывают на валидный self-signed server-cert, `CLIENTCAFILES` — на валидный PEM CA-bundle

**When** вызывается `m.InternalServerCreds()`

**Then** возвращается ненулевой `grpc.ServerOption` без ошибки
**And** под капотом — `credentials.NewTLS` с `ClientAuth = RequireAndVerifyClientCert`, `Certificates=[server-cert]`, `ClientCAs=<pool>`, `MinVersion>=TLS1.2` (контракт `TLSServerCreds`, SEC-B)

---

### 6.B — internal listener (:9091) handshake (S1, bufconn/integration)

#### Сценарий SEC-H-04 — internal mTLS on → handshake успешен, `UnaryCertIdentityExtract` видит верифицированный SAN

**ID:** SEC-H-04

**Given** IAM internal listener поднят с `InternalServerMTLS.enable=true` (cert-trio из self-signed internal CA в тесте)
**And** клиент дилит с client-cert, **подписанным той же internal CA** (SAN — module/operator identity, напр. `spiffe://kacho.cloud/ns/kacho-vpc/sa/kacho-vpc`)
**And** на internal listener — уже-существующая цепочка `UnaryCertIdentityExtract → UnaryPrincipalExtract` (serve.go, неизменна)

**When** клиент вызывает Internal RPC (напр. `InternalIAMService.RegisterResource`)

**Then** TLS-handshake успешен; IAM принимает peer (client-cert verified из internal CA)
**And** в обработчике `CertIdentityFromContext(ctx)` возвращает **заполненный** verified-cert identity (SAN клиента), а не пустой — извлекатель функционален именно благодаря mTLS (раньше на plaintext был no-op)
**And** RPC возвращает прикладной результат (контракт RPC неизменен)

> Это и есть смысл SEC-H для internal listener: SEC-C-извлекатель получает реальный verified-cert, на котором IAM строит client-cert→SA mapping.

---

#### Сценарий SEC-H-05 — internal mTLS off → handshake plaintext, извлекатель no-op (текущее dev-поведение сохранено)

**ID:** SEC-H-05

**Given** IAM internal listener поднят с `InternalServerMTLS.enable=false` (default)
**And** клиент дилит insecure (без cert) — как сегодня все service→service в dev

**When** клиент вызывает Internal RPC

**Then** RPC проходит по insecure-каналу (как до SEC-H)
**And** `CertIdentityFromContext(ctx)` возвращает пустую identity (extractor — no-op на plaintext); IAM применяет dev backward-compat (SEC-C group-D), как сегодня
**And** поведение побайтово совпадает с текущим main (нулевая регрессия)

---

#### Сценарий SEC-H-06 — fail-closed: plaintext-клиент против mTLS-on internal listener → handshake reject, нет insecure-fallback

**ID:** SEC-H-06

**Given** IAM internal listener `InternalServerMTLS.enable=true` (`RequireAndVerifyClientCert`)
**And** клиент дилит **plaintext** (insecure, без TLS) — точный сценарий, на котором споткнулся kacho-vpc-operator

**When** клиент пытается вызвать Internal RPC

**Then** клиент получает transport-ошибку handshake — каноничный текст `tls: first record does not look like a TLS handshake`
**And** ошибка маппится в `codes.Unavailable` (fail-closed для мутаций, §6.7)
**And** сервер **НЕ** откатывается на insecure (нет downgrade); ни одного байта прикладного payload не обработано

---

#### Сценарий SEC-H-07 — client-cert подписан ЧУЖОЙ CA → handshake reject (verify против internal CA)

**ID:** SEC-H-07

**Given** IAM internal listener `enable=true` с `ClientCAFiles` = internal CA
**And** клиент презентует TLS client-cert, подписанный **другой** (не internal) CA

**When** клиент вызывает Internal RPC

**Then** TLS-handshake отклонён (`RequireAndVerifyClientCert` не находит цепочку доверия к internal CA)
**And** клиент получает transport-ошибку → `codes.Unavailable`; payload не обработан (defense-in-depth: даже валидный TLS-cert чужого CA не принимается)

---

### 6.C — public listener (:9090) handshake + per-edge independence (S1)

#### Сценарий SEC-H-08 — per-edge independence: internal mTLS on, public mTLS off (и наоборот)

**ID:** SEC-H-08

**Given** `KACHO_IAM_INTERNAL_SERVER_MTLS_ENABLE=true` (валидный cert-trio), а `KACHO_IAM_PUBLIC_SERVER_MTLS_ENABLE=false`

**When** IAM стартует

**Then** internal listener (:9091) требует+верифицирует client-cert (mTLS), а public listener (:9090) остаётся plaintext insecure — **независимо**
**And** обратная комбинация (public on, internal off) тоже валидна и применяется раздельно (per-edge rollback, §6.5)
**And** `logger.Info("kacho-iam listener mTLS", "public_mtls", false, "internal_mtls", true)` отражает фактическое состояние каждого ребра

---

#### Сценарий SEC-H-09 — public mTLS on → handshake успешен с client-cert от internal CA

**ID:** SEC-H-09

**Given** IAM public listener `PublicServerMTLS.enable=true` (cert `kacho-iam-server-tls` + internal CA)
**And** клиент (напр. api-gateway backend-dial, SEC-E) дилит с client-cert от internal CA

**When** клиент вызывает публичный RPC IAM (напр. `ProjectService.Get`)

**Then** TLS-handshake успешен (server-cert презентован, client-cert верифицирован)
**And** RPC возвращает прикладной результат; контракт публичного RPC неизменен

> Замечание: SEC-H лишь делает public listener **способным** к mTLS. Кто именно дилит public по mTLS (api-gateway) — SEC-E; SEC-H предоставляет server-side готовность за per-edge флагом.

---

### 6.D — helm (S2)

#### Сценарий SEC-H-10 — kacho-iam subchart: mTLS off (default) → 0 server-mtls env, 0 mount, 0 secret

**ID:** SEC-H-10

**Given** `helm template iam <kacho-iam-subchart>` без mtls-флагов (mtls off — default)

**When** анализируется отрендеренный манифест

**Then** в env **нет** `KACHO_IAM_PUBLIC_SERVER_MTLS_ENABLE` (и остальных 7 server-mtls ключей)
**And** **нет** volume `mtls-server` и **нет** ссылки на secret `kacho-iam-server-tls`
**And** манифест идентичен текущему (нулевая регрессия деплоя) — mirror vpc OFF-кейса в `service-mtls-wiring-test.sh`

---

#### Сценарий SEC-H-11 — kacho-iam subchart: mTLS on → все 4×2 server-mtls env + `mtls-server` volume + `kacho-iam-server-tls` secret

**ID:** SEC-H-11

**Given** `helm template iam <kacho-iam-subchart> --set mtls.enable=true` (+ per-edge server flags, mirror vpc)

**When** анализируется отрендеренный манифест

**Then** env содержит полный блок:
`KACHO_IAM_PUBLIC_SERVER_MTLS_{ENABLE,CERTFILE,KEYFILE,CLIENTCAFILES}` и
`KACHO_IAM_INTERNAL_SERVER_MTLS_{ENABLE,CERTFILE,KEYFILE,CLIENTCAFILES}` (8 ключей, `ENABLE="true"`)
**And** `*_CERTFILE`/`*_KEYFILE`/`*_CLIENTCAFILES` указывают на mount-path volume `mtls-server`
**And** volume `mtls-server` смонтирован из secret `kacho-iam-server-tls`
**And** структура совпадает с vpc/compute subchart ON-кейсами (mirror-инвариант)

---

### 6.E — trust-инвариант и контрактная регрессия (cross-cutting)

#### Сценарий SEC-H-12 (trust-инвариант, КРИТИЧНО) — principal-metadata доверяется только при mTLS-верифицированном peer

**ID:** SEC-H-12

**Given** IAM internal listener `enable=true` (mTLS)
**And** на listener'е цепочка `UnaryCertIdentityExtract → UnaryPrincipalExtract` (неизменна)

**When (a)** peer подключён по mTLS с валидным internal-CA client-cert и шлёт `x-kacho-principal-*` metadata
**When (b)** peer **не** mTLS-верифицирован (или mTLS off в dev) и шлёт те же metadata

**Then (a)** `CertIdentityFromContext` заполнен верифицированным SAN; principal-metadata принимается в контексте verified-cert (доверенный путь)
**Then (b)** `CertIdentityFromContext` пуст; принятие principal-metadata происходит только в режиме dev backward-compat (SEC-C group-D), **не** под видом верифицированного peer

**Инвариант (I2):** principal-identity считается доверенной (для FGA-proxy / least-priv-gate) **исключительно** когда peer прошёл mTLS-верификацию; SEC-H — транспортная предпосылка этого инварианта. Без mTLS (dev) поведение явно деградированное (group-D), не «доверенное».

---

#### Сценарий SEC-H-13 — контракт не изменён: proto/REST diff = 0, JWT authN и FGA нетронуты

**ID:** SEC-H-13

**Given** ветка SEC-H смёржена

**When** выполняется `buf breaking` против baseline на public + internal сервисах IAM; прогон newman happy-path; ревью diff'а

**Then** breaking-diff = 0 (форма Account/Project/User/SA/Group/Role/AccessBinding + `InternalIAMService`/`InternalUserService` + REST-пути неизменны — требование #8)
**And** JWT-валидация (api-gateway) + `x-kacho-principal-*` propagation работают без изменений
**And** FGA-модель + `fga_outbox`-drainer + миграции — не затронуты (SEC-H — только транспорт)
**And** newman happy-path по существующим публичным IAM-RPC проходит без изменений запросов/ответов

---

## 7. Список тестов (TDD-red) — что подтверждает сценарии

### 7.1 Unit (kacho-iam, `internal/apps/kacho/config/mtls_test.go`)

| Тест | Сценарии |
|---|---|
| `default_off_insecure` — `LoadMTLS` без env → `Enable=false`; `*ServerCreds()` → insecure, без ошибки | SEC-H-01 |
| `enable_true_no_cert_errors` — `enable=true` + плохой cert-trio → `*ServerCreds()` возвращает error | SEC-H-02 |
| `enable_true_valid_creds` — `enable=true` + валидный cert-trio → ненулевой `ServerOption`, без ошибки | SEC-H-03 |
| `per_edge_independent` — internal enable=true, public enable=false → раздельные значения | SEC-H-08 |

### 7.2 Integration / bufconn (kacho-iam, self-signed internal CA)

| Тест | Сценарии |
|---|---|
| `internal_mtls_handshake_ok_cert_identity_visible` — server mTLS + client-cert от internal CA → handshake OK, `CertIdentityFromContext` заполнен | SEC-H-04 |
| `internal_mtls_off_plaintext_extractor_noop` — enable=false → insecure, extractor no-op (текущее поведение) | SEC-H-05 |
| `internal_mtls_plaintext_client_rejected` — plaintext-клиент против mTLS-listener → `tls: first record does not look like a TLS handshake` → `Unavailable`, нет downgrade | SEC-H-06 |
| `internal_mtls_foreign_ca_rejected` — client-cert чужого CA → handshake reject | SEC-H-07 |
| `public_mtls_handshake_ok` — public listener mTLS on → handshake OK с internal-CA client-cert | SEC-H-09 |
| `trust_invariant_principal_only_when_mtls_verified` (КРИТИЧНО) — principal-metadata доверяется только при verified peer | SEC-H-12 |

### 7.3 Helm (`kacho-deploy/tests/helm/service-mtls-wiring-test.sh` — расширить блоком kacho-iam)

| Гейт | Сценарии |
|---|---|
| iam OFF → нет server-mtls env, нет `mtls-server` volume, нет `kacho-iam-server-tls` secret | SEC-H-10 |
| iam ON → 8 server-mtls env + `mtls-server` volume + secret `kacho-iam-server-tls` | SEC-H-11 |

### 7.4 Контрактные / структурные гейты

| Гейт | Сценарий |
|---|---|
| `buf breaking` public + internal IAM = 0 diff | SEC-H-13 |
| newman happy-path IAM без изменений запросов/ответов | SEC-H-13 |
| grep: оба `grpcsrv.NewServer(...)` в `serve.go` принимают `*ServerCreds()`-ServerOption первым аргументом | SEC-H-04/SEC-H-09 (wiring) |

---

## 8. Definition of Done (SEC-H)

- [ ] `acceptance-reviewer` ✅ APPROVED данного doc (статус DRAFT → APPROVED).
- [ ] KAC-тикет(ы) + ветки `KAC-<N>` в `kacho-iam` и `kacho-deploy` (порядок по build-графу; depends-on SEC-B/C/D в main, SEC-F для cert-выпуска).
- [ ] **S1 (kacho-iam)**: `internal/apps/kacho/config/mtls.go` (mirror vpc) — `MTLSConfig{PublicServerMTLS, InternalServerMTLS grpcsrv.TLSServer}` + `LoadMTLS()` (`KACHO_IAM`-prefix) + `PublicServerCreds()`/`InternalServerCreds()`; wiring обоих `grpcsrv.NewServer(...)` в `cmd/kacho-iam/serve.go` (creds первым аргументом); существующие interceptor-цепочки сохранены.
- [ ] **S2 (kacho-deploy)**: kacho-iam subchart рендерит `KACHO_IAM_{PUBLIC,INTERNAL}_SERVER_MTLS_*` env + монтирует `kacho-iam-server-tls` (volume `mtls-server`) gated `mtls.enable`; umbrella `values.mtls.yaml` включает server-edge IAM.
- [ ] **RED → GREEN**: unit §7.1 + bufconn/integration §7.2 + helm §7.3 написаны до кода; КРИТИЧНЫЕ `internal_mtls_plaintext_client_rejected` (SEC-H-06) + `trust_invariant_principal_only_when_mtls_verified` (SEC-H-12) — обязательны, без них merge запрещён (ban #11/#12).
- [ ] **mirror-инвариант** подтверждён: env-суффиксы / helm-ключи (`mtls.enable`) / secret-суффикс (`-server-tls`) / volume (`mtls-server`) / поведение enable=false|true|fail-closed побайтово совпадают с SEC-D vpc/compute.
- [ ] **enable=false → нулевая регрессия**: существующие kacho-iam unit/integration/newman зелёные без правок конфигурации; helm OFF-рендер идентичен текущему (SEC-H-01, SEC-H-10).
- [ ] **proto breaking-diff = 0** на public + internal IAM (SEC-H-13); JWT authN + FGA + миграции не затронуты.
- [ ] Финальная верификация: `go test ./... -race` + `golangci-lint run` + `govulncheck` (kacho-iam) + `helm lint`/`helm template` + `tests/helm/service-mtls-wiring-test.sh` зелёные.
- [ ] Vault-trail:
  - [ ] `obsidian/kacho/packages/iam-config.md` (новая/обновление) — `MTLSConfig` + `LoadMTLS`/`*ServerCreds` (mirror vpc-config).
  - [ ] `obsidian/kacho/rpc/iam-internal-iam-service.md` — пометка «internal listener server-side mTLS opt-in (SEC-H); `CertIdentityFromContext` функционален при enable=true».
  - [ ] `obsidian/kacho/edges/*-to-iam-*.md` (vpc/compute/nlb→iam) — «History»: server-side mTLS на IAM-listener теперь поддержан (SEC-H, KAC-<N>); до SEC-H IAM-сторона была plaintext даже при mTLS-клиенте.
  - [ ] `obsidian/kacho/KAC/KAC-<N>.md` — trail + PR-URL + статус.
- [ ] YouTrack KAC: `In Progress` на старте → `Test` → `Done` по merge + smoke; PR-ссылки + лог тестов комментарием.
- [ ] Заказчик — финальный smoke/e2e: профиль mTLS-on (`make dev-up` c `values.mtls.yaml`) — vpc→iam `RegisterResource` handshake-ok; plaintext-клиент против :9091 → `tls: first record does not look like a TLS handshake`; профиль mTLS-off — dev работает как сегодня.

---

## 9. Open questions (DECISION-NEEDED до старта impl)

| ID | Вопрос | Рекомендация автора |
|---|---|---|
| **OQ-SEC-H-1** | `MTLSConfig` в kacho-iam — отдельный envconfig-loader (`LoadMTLS`, как vpc) **vs** встроить server-TLS-поля в основной viper-Config? | **Отдельный `LoadMTLS` через `corecfg.LoadPrefixed("KACHO_IAM", …)`** — строгий mirror vpc (`grpcsrv.TLSServer` не имеет mapstructure-тегов; envconfig обрабатывает поля напрямую). Не смешивать с viper-YAML-Config. |
| **OQ-SEC-H-2** | Public listener mTLS — включать в scope SEC-H **vs** только internal (public защищён api-gateway TLS снаружи)? | **Включить обе** (public + internal) как **независимые per-edge** — паритет формы с vpc/compute (у которых тоже public+internal server-edge). Реально дилить public по mTLS будет SEC-E (api-gateway); SEC-H даёт server-side готовность за флагом (default off — нулевая стоимость, если не включать). |
| **OQ-SEC-H-3** | hooks-HTTP listener (`KACHO_IAM_AUTH_HOOKS_*`, Hydra/CAEP ingress) — нужен ли ему mTLS в SEC-H? | **Нет** — SEC-H = только **gRPC** server-side (:9090/:9091). hooks-HTTP — отдельный HTTP-listener, cluster-internal; его TLS — вне scope SEC-H (при необходимости — отдельный тикет). Зафиксировать в Non-goals. |
| **OQ-SEC-H-4** | Имя secret — `kacho-iam-server-tls` (mirror `kacho-<svc>-server-tls`)? | **Да**, `kacho-iam-server-tls`, volume `mtls-server` — строгий mirror SEC-D/SEC-F naming. Выпуск `Certificate` — SEC-F (SEC-H только монтирует). |

> Ответы на OQ — за `acceptance-reviewer` (sign-off либо CHANGES REQUESTED). OQ-SEC-H-2/3 определяют точный scope listener'ов — разрешить до impl.

---

## 10. Ссылки

- Эпик-дизайн (ground truth): `docs/specs/sub-phase-SEC-mtls-iam-authz-epic.md`.
- **Прямой образец (mirror 1:1):** `docs/specs/sub-phase-SEC-D-services-fga-via-iam-mtls-acceptance.md` (S3 — server+client mTLS per-edge для vpc/compute/nlb).
- corelib primitive (SEC-B, готов): `project/kacho-corelib/grpcsrv/tls.go` (`TLSServer`, `TLSServerCreds`), `UnaryCertIdentityExtract`/`StreamCertIdentityExtract`.
- corelib mTLS acceptance: `docs/specs/sub-phase-SEC-B-corelib-mtls-acceptance.md`.
- IAM-сторона identity-extract / SA-mapping (SEC-C): `docs/specs/sub-phase-SEC-C-iam-fga-proxy-sa-roles-acceptance.md`.
- vpc config-образец: `project/kacho-vpc/internal/apps/kacho/config/mtls.go` + `mtls_test.go`.
- vpc cmd-wiring образец: `project/kacho-vpc/cmd/vpc/main.go` (стр. ~343-368 — `PublicServerCreds`/`InternalServerCreds` → `grpcsrv.NewServer`).
- IAM target (plaintext сегодня): `project/kacho-iam/cmd/kacho-iam/serve.go` (стр. 112-140 — `grpcSrv`/`internalSrv` без TLS-ServerOption).
- IAM config-пакет: `project/kacho-iam/internal/apps/kacho/config/` (`config.go`, `load.go`).
- helm-образец: `project/kacho-deploy/tests/helm/service-mtls-wiring-test.sh` (vpc/compute OFF/ON-блоки) + `values.mtls.yaml` overlay.
- cert-manager PKI / Certificate-выпуск (SEC-F): `docs/specs/sub-phase-SEC-F-deploy-certmanager-sa-acceptance.md`.
- Правила: `.claude/rules/{api-conventions,security,architecture,testing,polyrepo,data-integrity}.md`.
