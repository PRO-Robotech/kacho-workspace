# Sub-phase 5.5 — kacho-iam: per-edge transport hardening for the HTTP hooks (:9092) + metrics (:9095) listeners — Acceptance

> **Статус:** ✅ APPROVED (acceptance-reviewer, 2026-06-16) — core-дизайн (per-edge `clientAuthMode`, server-tls-only для HMAC-аутентифицируемого ребра, fail-closed, no-new-PKI, CI-vs-live-Ory split) был pre-accepted; четыре замечания Round-5 устранены: (C1) scope-факт о :9092 переписан — listener несёт ОБА класса HMAC-вызывателей (Hydra token/refresh **и** Kratos provision), единый `*tls.Config` корректно покрывает оба; (C2) routing-drift Kratos→provision вынесен из scope как `kacho-deploy#91`, live-Ory DoD сужен; (M1) добавлен сценарий 5.5-14b (provision без HMAC → 401); (M2) `CLIENTAUTHMODE`-env добавлен в asserted-env-массив render-guard'а.
> **Дата:** 2026-06-16
> **Ревьюер:** `acceptance-reviewer` (единственный gate ✅ APPROVED — ban #1; заказчик к контракту не подключается, проверяет только финальный e2e/smoke на шаге 7)
> **Автор-агент:** `acceptance-author`
> **Эпик/тикет:** KAC-`<N>` (Round-5 P0 follow-up; GitHub `PRO-Robotech/kacho-iam#137`, supersedes the OFF-gate `#122`)
> **Затронутые репо:** `kacho-iam` (config `internal/apps/kacho/config/mtls.go` + cmd-wiring `cmd/kacho-iam/serve.go`), `kacho-deploy` (kacho-iam subchart deployment env + Ory Hydra webhook config + CA volume mount + prod gate + render-guard).
> **Зависит от:** SEC-B (corelib `grpcsrv.TLSServer` value-struct — переиспользуется как форма cert-trio), SEC-H (gRPC server-side mTLS на :9090/:9091 — **готовый образец**, который 5.5 расширяет до per-edge ClientAuth mode), SEC-F (cert-manager internal-CA PKI, server-cert `kacho-iam-server-tls` уже монтируется в pod — **переиспользуется без нового PKI**), iam#136 (server-side mTLS capability для :9092/:9095 — **SHIPPED, но GATED OFF**).
> **Связанные (вне scope 5.5):** `kacho-deploy#91` — Kratos web_hooks (registration/login/recovery) в `kratos-config-configmap.yaml` ходят на gRPC-internal `:9091 /iam/v1/internal/users:upsertFromIdentity` (и `:onRecoveryCompleted`), а НЕ на `:9092 /iam/v1/hooks/provision`-хендлер — pre-existing routing-drift (provisioning может быть сломан независимо от #137). 5.5 — транспортное шифрование :9092, не routing-correctness; фикс URL-маршрутизации Kratos→provision трекается #91.

---

## 0. Обзор

iam#136 поставил серверную mTLS-способность для двух HTTP-listener'ов kacho-iam —
**HTTP hooks (:9092)** и **Prometheus `/metrics` (:9095)** — но она **GATED
OFF в проде** (`kacho-deploy/helm/umbrella/values.prod.yaml` → `kacho-iam.mtls.httpListeners:
false`). Причина (issue #122/#137): текущий builder `serverTLSConfig()`
(`internal/apps/kacho/config/mtls.go`) жёстко зашивает `ClientAuth:
tls.RequireAndVerifyClientCert` для **обоих** рёбер.

**Scope-факт о :9092 (ground-truth, `internal/handler/iamhooks/http_server.go` →
`NewMux`).** Listener :9092 **обслуживает ТРИ hook-эндпоинта**, не только Hydra:

- `POST /iam/v1/hooks/token` — Hydra OAuth2 access-token webhook;
- `POST /iam/v1/hooks/refresh` — Hydra OAuth2 refresh-token webhook;
- `POST /iam/v1/hooks/provision` — Kratos registration/login user-provisioning webhook (C4).

**Все три вызывателя — HTTP-клиенты, аутентифицируемые HMAC shared-secret'ом** (header
`X-Kacho-Hook-Token`, общий хелпер `requireHookAuth` в `internal/handler/iamhooks/hook_auth.go`;
provision-хендлер получает тот же `HookSharedSecret`). Ни Ory Hydra OAuth2-webhook, ни Ory
Kratos web_hook **физически не умеют предъявлять transport client-cert** — оба ходят как
plaintext/`api_key`-аутентифицируемые HTTP-клиенты. `cmd/kacho-iam/serve.go` оборачивает
**весь** :9092-listener **одним** `*tls.Config` (`hooksListener = tls.NewListener(hooksListener,
hooksTLSConfig)`) — то есть **выбранный режим TLS применяется одинаково ко всем трём
hook-эндпоинтам**, как Hydra-, так и Kratos-provision-вызывателям. Никакой Prometheus-скрейпер
с client-cert на :9095 тоже не подключён.

Включение `RequireAndVerifyClientCert` на :9092 отвергнет **каждый** из трёх webhook'ов на
TLS-handshake — ещё ДО HMAC-проверки. Поэтому прод-периметр для этих двух рёбер невозможно
«просто включить» в режиме mutual. Поскольку у :9092 **только** HMAC/`api_key`-аутентифицируемые
HTTP-клиенты **без** transport client-cert (и Hydra, и Kratos-provision), единый
`server-tls-only` режим на listener'е — **корректен для обоих классов вызывателей** (это
делает `server-tls-only` более обоснованным, а не менее: он шифрует транспорт, не требуя
невыполнимого client-cert ни от Hydra, ни от Kratos).

5.5 даёт **per-edge ClientAuth mode** вместо one-size `RequireAndVerifyClientCert`,
так что прод получает **transport-шифрование** на обоих рёбрах, не ломая вызывателей:

- **Hooks edge (:9092) — `server-tls-only`** (server-side TLS, `tls.NoClientCert`):
  **все три hook-вызывателя** (Hydra token/refresh + Kratos provision) ходят по
  `https://…:9092` с CA-trust к server-cert + по-прежнему несут HMAC `X-Kacho-Hook-Token`.
  Транспорт зашифрован; caller-auth остаётся HMAC (defense-in-depth). Client-cert не
  требуется — потому что ни Hydra-webhook, ни Kratos-web_hook его не умеют. Один режим на
  listener'е корректен для обоих классов: оба — HMAC-аутентифицируемые HTTP-клиенты без
  transport client-cert.
- **Metrics edge (:9095) — `server-tls-only`** (по умолчанию для этой фазы), т.к. в
  деплое **нет** подключённого scrape-клиента с client-cert. Альтернатива `mutual`
  (RequireAndVerifyClientCert) оставлена как опция конфигурации на момент, когда
  scrape-клиент будет provision'ен с internal-CA client-cert (см. §4 «Развилка
  metrics»). 5.5 включает прод в режиме `server-tls-only`.

### Граница trust (HMAC vs transport vs client-cert) — нормативная модель

| Слой | Что обеспечивает | Кто несёт | На каком ребре |
|---|---|---|---|
| **Transport TLS (server-only)** | confidentiality + server-authentication (клиент верит, что говорит с настоящим kacho-iam) | server-cert `kacho-iam-server-tls` (SEC-F) + CA-trust у клиента | hooks :9092, metrics :9095 |
| **Transport mTLS (mutual)** | то же + client-authentication по cert SAN | + client-cert из той же internal-CA | metrics :9095 (опция); gRPC :9090/:9091 (SEC-H, вне scope) |
| **Caller-auth HMAC** | кто звонит (валидный shared-secret) | `X-Kacho-Hook-Token` (Hydra token/refresh **и** Kratos provision) | hooks :9092 (все три hook-эндпоинта) |

**Ключевой инвариант hooks-ребра:** transport TLS **НЕ заменяет** HMAC. На hooks-ребре
для **всех трёх** эндпоинтов (token/refresh/provision) caller-auth обеспечивает **HMAC**
(общий `requireHookAuth` в `hook_auth.go`), TLS даёт только шифрование +
server-authentication. Это **намеренно `server-tls-only`, не mTLS** — потому что ни
Hydra-webhook, ни Kratos-web_hook не способны предъявить client-cert; HMAC — приемлемая
caller-auth для этого ребра (constant-time compare, fail-closed на пустом секрете), и
снятие требования client-cert не ослабляет периметр (двойной барьер: TLS-шифрование +
HMAC), что доказывается сценариями 5.5-14 (token без HMAC → 401) и 5.5-14b (provision без
HMAC → 401).

### Per-edge ClientAuth matrix (целевое прод-состояние 5.5)

| Listener | Порт | clientAuthMode | TLS `ClientAuth` | Caller-auth | Включён в проде 5.5 |
|---|---|---|---|---|---|
| gRPC public | :9090 | (SEC-H, вне scope) | RequireAndVerifyClientCert | JWT (api-gateway) | да (SEC-H) |
| gRPC internal | :9091 | (SEC-H, вне scope) | RequireAndVerifyClientCert | mTLS SAN + per-RPC policy | да (SEC-H) |
| **HTTP hooks** | **:9092** | **`server-tls-only`** | `tls.NoClientCert` | **HMAC `X-Kacho-Hook-Token`** (token/refresh/provision — все три эндпоинта) | **да (5.5)** |
| **HTTP metrics** | **:9095** | **`server-tls-only`** (опция `mutual`) | `tls.NoClientCert` (опция Require…) | network-segregation (опция client-cert) | **да (5.5)** |

### Что 5.5 НЕ делает (явно вне scope)

- **НЕ трогает gRPC :9090/:9091** — там mutual mTLS из SEC-H остаётся как есть.
- **НЕ чинит Kratos provision-webhook routing-drift (вне scope, `kacho-deploy#91`).**
  Текущий `kratos-config-configmap.yaml` отправляет registration/login/recovery web_hooks на
  gRPC-internal `http://kacho-iam…:9091/iam/v1/internal/users:upsertFromIdentity` (и
  `:onRecoveryCompleted` для recovery), а **НЕ** на смонтированный `:9092 /iam/v1/hooks/provision`
  HTTP-хендлер. Это pre-existing **routing/correctness drift** (provisioning может быть сломан
  независимо от #137): in-process provision-хендлер на :9092 присутствует и работает, но
  деплой-конфиг его не вызывает. Исправление URL-маршрутизации Kratos→provision **не относится
  к transport-encryption** и трекается отдельно как **`kacho-deploy#91`**. 5.5 шифрует
  транспорт :9092 для тех hook-вызывателей, что реально на нём (Hydra token/refresh; и
  Kratos-provision, когда #91 переключит маршрут) — без изменения самой маршрутизации.
- **НЕ меняет HMAC-логику** (`hook_auth.go`) — caller-auth неизменен для всех трёх hook-эндпоинтов
  (token/refresh/provision); 5.5 — транспортный слой.
- **НЕ выпускает новый PKI** — переиспользуется уже-монтируемый SEC-F server cert-trio
  (`tls.crt`/`tls.key`/`ca.crt`).
- **НЕ добавляет proto / REST / БД-изменений** — это инфра/конфиг hardening, не API.
  Контракты IAM-ресурсов неизменны.
- **НЕ вводит hot-reload cert'ов** — ротация = рестарт pod'а (mirror SEC-B/SEC-H §6.2,
  не TODO).

### CI-validatable vs требует live Ory

- **CI-validatable (в этом PR):** Go config unit-тесты нового `clientAuthMode`
  (`server-tls-only` → `tls.NoClientCert`; `mutual` → `RequireAndVerifyClientCert`;
  fail-closed на неполном cert-trio / неизвестном режиме); helm-render-guard
  (prod emits правильный per-edge env; dev emits none; capability intact). TLS-handshake
  поведение покрывается Go-тестом через локальный `httptest`/`net/http` клиент с/без
  CA-trust против собранного `*tls.Config`.
- **Требует live Ory (не на CI newman-стенде — он бежит без mTLS):** реальный
  Hydra→:9092 https-webhook end-to-end с CA-trust + HMAC (`token`/`refresh` приняты;
  plaintext отвергнут). Эти сценарии валидируются **reasoning + smoke на проде/staging-стенде**
  (шаг 7, заказчик), помечены ниже как **[live-Ory]**. Newman-стенд остаётся plaintext
  (gate OFF на dev) → byte-identical, без регрессии.
- **Граница live-Ory DoD 5.5 (важно — не over-promise):** 5.5 обещает только, что
  **:9092-listener принимает Hydra token/refresh поверх TLS+HMAC и отвергает plaintext**
  (плюс что provision-эндпоинт по-прежнему требует HMAC, 5.5-14b). 5.5 **НЕ** обещает
  «registration работает end-to-end»: корректность provisioning зависит от
  Kratos→provision routing-фикса `kacho-deploy#91` (Kratos сейчас бьёт в :9091
  `upsertFromIdentity`, а не в :9092 provision-хендлер). Транспортное шифрование :9092
  (5.5) и routing-correctness provisioning (#91) — независимы.

---

## Стадия S1 — kacho-iam config: per-edge `clientAuthMode`

> **DoD S1:** `config.MTLSConfig` несёт per-edge `clientAuthMode`; `serverTLSConfig`
> строит `*tls.Config` с `ClientAuth` по режиму (не жёстко `RequireAndVerifyClientCert`);
> `Validate()` fail-closed по режиму; config unit-тесты RED→GREEN; `go test ./... -race`
> + `golangci-lint` зелёные. Без deploy-изменений S1 самодостаточен (capability готова,
> прод по-прежнему OFF).

### Сценарий 5.5-01: hooks-edge `server-tls-only` строит `*tls.Config` без client-cert требования

**ID:** 5.5-01

**Given** конфиг kacho-iam с включённым hooks-edge: `KACHO_IAM_HOOKS_SERVER_MTLS_ENABLE=true`,
валидный server cert-trio (`CERTFILE`/`KEYFILE`/`CLIENTCAFILES` указывают на SEC-F mount)
**And** для hooks-edge задан `clientAuthMode = server-tls-only`

**When** composition root вызывает `mtlsCfg.HooksServerTLSConfig()`

**Then** возвращается не-nil `*tls.Config` с:
  - `Certificates` = загруженный server-cert (`tls.crt`/`tls.key`)
  - `ClientAuth` = `tls.NoClientCert` (НЕ `RequireAndVerifyClientCert`)
  - `MinVersion` = `tls.VersionTLS12`
**And** `error == nil`
**And** для режима `server-tls-only` `ClientCAFiles` НЕ обязателен (client-cert не верифицируется), пустой `ClientCAFiles` НЕ является ошибкой.

### Сценарий 5.5-02: metrics-edge `mutual` строит `*tls.Config` с RequireAndVerifyClientCert

**ID:** 5.5-02

**Given** конфиг с включённым metrics-edge: `KACHO_IAM_METRICS_SERVER_MTLS_ENABLE=true`,
валидный server cert-trio (включая непустой `CLIENTCAFILES`)
**And** для metrics-edge задан `clientAuthMode = mutual`

**When** composition root вызывает `mtlsCfg.MetricsServerTLSConfig()`

**Then** возвращается не-nil `*tls.Config` с:
  - `ClientAuth` = `tls.RequireAndVerifyClientCert`
  - `ClientCAs` = pool, собранный из `CLIENTCAFILES`
  - `MinVersion` = `tls.VersionTLS12`
**And** `error == nil`.

### Сценарий 5.5-03: edge disabled → builder отдаёт (nil, nil), listener остаётся plaintext

**ID:** 5.5-03

**Given** конфиг с `KACHO_IAM_HOOKS_SERVER_MTLS_ENABLE` не задан (zero-value `Enable=false`)
**And** аналогично `KACHO_IAM_METRICS_SERVER_MTLS_ENABLE=false`

**When** composition root вызывает `HooksServerTLSConfig()` и `MetricsServerTLSConfig()`

**Then** оба возвращают `(*tls.Config)(nil), nil`
**And** cert-файлы НЕ читаются (даже если пути заданы и невалидны)
**And** в `serve.go` `tls.NewListener` НЕ оборачивает raw TCP listener → listener остаётся PLAINTEXT (byte-identical к dev/newman-стенду — нулевая регрессия).

### Сценарий 5.5-04: edge enabled с неполным cert-trio → fail-closed на boot (Validate)

**ID:** 5.5-04

**Given** конфиг с `KACHO_IAM_HOOKS_SERVER_MTLS_ENABLE=true`, но `CERTFILE` пустой
(или `KEYFILE` пустой)

**When** composition root вызывает `mtlsCfg.Validate()` до запуска listener'ов

**Then** возвращается non-nil error, агрегированная через multierr, с сегментом
`"hooks-server mTLS edge: enabled but cert_file/key_file is empty (fail-closed)"`
**And** `serve.go` возвращает `"listener mTLS config invalid: …"` и процесс НЕ стартует listener'ы (никакого silent insecure-fallback, ban #11).

### Сценарий 5.5-05: edge enabled `mutual` с пустым client-CA → fail-closed

**ID:** 5.5-05

**Given** конфиг с metrics-edge `ENABLE=true`, `clientAuthMode=mutual`, валидные `CERTFILE`/`KEYFILE`,
но `CLIENTCAFILES` пустой

**When** `mtlsCfg.Validate()`

**Then** non-nil error с сегментом, указывающим что `mutual`/RequireAndVerifyClientCert требует client-CA
(текст в духе `"metrics-server mTLS edge: clientAuthMode=mutual requires a non-empty client_ca_files"`)
**And** процесс НЕ стартует.

**And** **граничный случай:** для того же edge с `clientAuthMode=server-tls-only` и
пустым `CLIENTCAFILES` `Validate()` проходит (client-CA не нужен, когда client-cert не верифицируется).

### Сценарий 5.5-06: неизвестный clientAuthMode → fail-closed (не дефолт к небезопасному)

**ID:** 5.5-06

**Given** конфиг с hooks-edge `ENABLE=true`, валидный cert-trio, но `clientAuthMode = "open"`
(или любая неизвестная строка)

**When** `mtlsCfg.Validate()` (или builder)

**Then** non-nil error: `"hooks-server mTLS edge: unknown clientAuthMode \"open\" (expected server-tls-only|mutual)"`
**And** процесс НЕ стартует (неизвестный режим никогда не интерпретируется как «без проверок»; fail-closed).

### Сценарий 5.5-07: дефолт clientAuthMode при включённом edge

**ID:** 5.5-07

**Given** конфиг с hooks-edge `ENABLE=true`, валидный cert-trio, `clientAuthMode` **не задан** (пустая строка)

**When** builder/`Validate()` обрабатывают edge

**Then** применяется **явный безопасный дефолт по типу ребра**: для hooks дефолт —
`server-tls-only` (Ory не умеет client-cert); для metrics дефолт — `server-tls-only`
(scrape-клиент пока без cert)
**And** дефолт задокументирован в коде и в env как осознанное решение (не «случайный zero-value»).

> Примечание для реализации (не нормативно для contract-теста): дефолт может быть
> прошит per-edge в композиции/в struct-теге; нормативно — что **enabled-edge без явного
> mode не падает в RequireAndVerifyClientCert для hooks** (это и был баг #122).

---

## Стадия S2 — deploy: Ory CA-trust + https-URL + per-edge env + прод gate ON + render-guard

> **DoD S2:** `values.prod.yaml` flip'ает прод gate ON для двух рёбер в режиме
> `server-tls-only`; Hydra webhook URL → `https://…:9092` + смонтирован internal-CA
> bundle в Hydra pod (CA-trust к server-cert); deployment.yaml эмитит per-edge
> `clientAuthMode` env; render-guard переписан на assert прод-ON-wiring; dev остаётся
> OFF (plaintext). helm-render зелёный; render-guard зелёный.

### Сценарий 5.5-08: прод-профиль эмитит per-edge server-tls-only env для hooks + metrics

**ID:** 5.5-08 (CI-validatable, render-guard)

**Given** `helm template kacho-umbrella -f values.prod.yaml`
**And** в `values.prod.yaml` `kacho-iam.mtls.httpListeners: true` (gate flipped ON для server-tls-only рёбер)

**When** рендерится `charts/kacho-iam/templates/deployment.yaml`

**Then** container env содержит:
  - `KACHO_IAM_HOOKS_SERVER_MTLS_ENABLE = "true"`
  - `KACHO_IAM_HOOKS_SERVER_MTLS_CLIENTAUTHMODE = "server-tls-only"`
  - `KACHO_IAM_HOOKS_SERVER_MTLS_CERTFILE` / `KEYFILE` → SEC-F mounted `tls.crt` / `tls.key`
  - `KACHO_IAM_METRICS_SERVER_MTLS_ENABLE = "true"`
  - `KACHO_IAM_METRICS_SERVER_MTLS_CLIENTAUTHMODE = "server-tls-only"`
  - `KACHO_IAM_METRICS_SERVER_MTLS_CERTFILE` / `KEYFILE` → тот же SEC-F mount
**And** все cert-пути ссылаются на **тот же** уже-монтируемый SEC-F server-secret (`{{ .Values.mtls.mountPath }}/server/...`) — **нового PKI не появляется**.

### Сценарий 5.5-09: dev-профиль НЕ эмитит hooks/metrics mTLS env (plaintext, без регрессии)

**ID:** 5.5-09 (CI-validatable, render-guard)

**Given** `helm template … -f values.dev.yaml` (где `kacho-iam.mtls.httpListeners: false`)

**When** рендерится `charts/kacho-iam/templates/deployment.yaml`

**Then** НИ ОДНОГО из env `KACHO_IAM_{HOOKS,METRICS}_SERVER_MTLS_*` (включая `CLIENTAUTHMODE`) в контейнере нет
**And** dev/newman hooks- и metrics-listener'ы остаются PLAINTEXT (byte-identical к до-5.5 поведению; newman e2e не ломается).

### Сценарий 5.5-10: Hydra webhook URL переведён на https + смонтирован CA-trust

**ID:** 5.5-10 (CI-validatable частично, render-guard; e2e — [live-Ory])

**Given** прод-профиль с включённым hooks-edge (5.5-08)

**When** рендерится Ory Hydra OAuth2-конфиг (token_hook/refresh_token_hook)

**Then** оба webhook URL — `https://kacho-iam-internal.<ns>.svc.cluster.local:9092/iam/v1/hooks/{token,refresh}` (схема `https`, не `http`)
**And** в Hydra pod смонтирован internal-CA bundle (`ca.crt` той же SEC-F PKI), сконфигурированный как trusted CA для исходящих webhook-вызовов (Hydra доверяет server-cert kacho-iam)
**And** HMAC-аутентификация сохранена: header `X-Kacho-Hook-Token` с тем же shared-secret (`KACHO_IAM_HOOK_TOKEN`) — транспорт сменился на https, caller-auth не изменился.

### Сценарий 5.5-11: render-guard переписан с «assert OFF» на «assert прод-ON-wiring»

**ID:** 5.5-11 (CI-validatable)

**Given** обновлённый `tests/helm/iam-hooks-metrics-mtls-test.sh`

**When** guard прогоняется против rendered прод-профиля

**Then** guard ассертит (вместо прежнего «prod emits NONE»):
  - prod эмитит все hooks/metrics env **с `CLIENTAUTHMODE=server-tls-only`** (5.5-08)
  - prod Hydra webhook URL = `https://…:9092` (5.5-10)
  - dev по-прежнему эмитит NONE (5.5-09)
  - cert-trio переиспользует SEC-F mount (нет нового PKI)
**And** **новый env `KACHO_IAM_HOOKS_SERVER_MTLS_CLIENTAUTHMODE` и
`KACHO_IAM_METRICS_SERVER_MTLS_CLIENTAUTHMODE` ДОБАВЛЕНЫ в asserted-env-массив guard'а**
(`HOOKS_METRICS_ENV` в `tests/helm/iam-hooks-metrics-mtls-test.sh`). Текущий массив содержит
только `ENABLE`/`CERTFILE`/`KEYFILE`/`CLIENTCAFILES` per-edge и **не знает** про
`CLIENTAUTHMODE` — поэтому:
  - в section «CAPABILITY INTACT» (assert `name: <env>` присутствует в template) добавление
    `CLIENTAUTHMODE` к массиву → guard **RED** против текущего template, который этого env
    ещё не эмитит (RED→GREEN: добавить env в `deployment.yaml`);
  - в section «dev → NONE» расширенный массив дополнительно доказывает, что dev не эмитит и
    `CLIENTAUTHMODE` (no-regression);
  - в section «prod ON» — guard явно проверяет `CLIENTAUTHMODE=server-tls-only` (5.5-08).
**And** комментарий-обоснование в guard заменён: убрано «would reject Hydra/Kratos webhooks → auth-break» (это про старый RequireAndVerifyClientCert) на «hooks-edge server-TLS-only by design: ни Hydra-webhook, ни Kratos-web_hook не умеют client-cert, HMAC — caller-auth; единый режим на :9092 покрывает все три hook-эндпоинта».

---

## Стадия S3 — поведенческие сценарии (smoke / live-Ory) — целевой прод-периметр

> **DoD S3 (scoped — транспорт, не provisioning-correctness):** на staging/prod-стенде с
> поднятым Ory: Hydra `token`/`refresh` webhook идёт по https с CA-trust + HMAC и
> **принимается**; plaintext-попытка **отклоняется** на транспорте; provision-эндпоинт
> по-прежнему **требует HMAC** (5.5-14b). 5.5 **НЕ** обещает «registration работает
> end-to-end» — корректность Kratos→provision-маршрутизации зависит от `kacho-deploy#91`
> (Kratos сейчас бьёт в :9091, не в :9092 provision-хендлер) и вне scope этой фазы. Эти
> сценарии — финальная верификация заказчика (шаг 7), не CI newman (newman-стенд без mTLS).
> Где возможно — продублированы Go-`httptest`-уровнем.

### Сценарий 5.5-12: Hydra webhook по https с CA-trust + валидным HMAC → принят (encrypted, HMAC-authed)

**ID:** 5.5-12 **[live-Ory]** (+ Go-`httptest`-аналог CI-validatable)

**Given** прод hooks-edge `server-tls-only` (5.5-08), Hydra с CA-trust + https-URL (5.5-10)
**And** валидный `X-Kacho-Hook-Token`

**When** Hydra вызывает `https://…:9092/iam/v1/hooks/token` с CA-trust к server-cert и корректным HMAC-header

**Then** TLS-handshake успешен (клиент доверяет server-cert, server client-cert НЕ требует)
**And** HMAC проходит (`hook_auth.go` constant-time compare)
**And** hook возвращает `200` с enrichment-claims (token_hook), соединение зашифровано.

**Go-`httptest`-аналог (CI):** `net/http`-клиент с CA-pool, доверяющим тест-CA, против
`httptest`-сервера, поднятого с `*tls.Config` из `HooksServerTLSConfig()`
(`server-tls-only`), client-cert НЕ предъявляется → handshake OK + handler-200.

### Сценарий 5.5-13: plaintext http-попытка против https-listener в проде → отклонена

**ID:** 5.5-13 **[live-Ory]** (+ Go-`httptest`-аналог CI-validatable)

**Given** прод hooks-edge `server-tls-only` (TLS обязателен)

**When** клиент делает plaintext `http://…:9092/iam/v1/hooks/token` (без TLS)

**Then** соединение отвергается на транспортном уровне (TLS required) — handler не достигается
**And** **никакого insecure-downgrade** (нет fallback на plaintext-обслуживание).

### Сценарий 5.5-14: TLS-клиент БЕЗ HMAC-секрета → отклонён на HMAC-слое (TLS не заменяет HMAC)

**ID:** 5.5-14 **[live-Ory]** (+ Go-`httptest`-аналог CI-validatable)

**Given** прод hooks-edge `server-tls-only`, клиент с CA-trust (TLS-handshake пройдёт)
**And** у клиента НЕТ валидного `X-Kacho-Hook-Token` (или header отсутствует)

**When** клиент шлёт корректный https-запрос на `/iam/v1/hooks/token` без валидного HMAC

**Then** TLS-handshake успешен, НО handler отвечает `401` `{"error":"invalid_hook_token"}` с header `WWW-Authenticate: Bearer realm="kacho-iam-hooks"`
**And** это подтверждает trust-инвариант: **TLS даёт шифрование, HMAC даёт caller-auth — они независимы; снятие client-cert требования не открыло hooks для неаутентифицированных вызывателей.**

### Сценарий 5.5-14b: Kratos provision-эндпоинт TLS OK + без HMAC → 401 (server-tls-only не открыл provision неаутентифицированным)

**ID:** 5.5-14b **[live-Ory]** (+ Go-`httptest`-аналог CI-validatable)

**Given** прод hooks-edge `server-tls-only` (5.5-08), клиент с CA-trust (TLS-handshake пройдёт)
**And** у клиента НЕТ валидного `X-Kacho-Hook-Token` (header отсутствует или невалиден)

**When** клиент шлёт корректный https-запрос на `/iam/v1/hooks/provision` (Kratos provision-эндпоинт) без валидного HMAC

**Then** TLS-handshake успешен, НО handler отвечает `401` `{"error":"invalid_hook_token"}` с header `WWW-Authenticate: Bearer realm="kacho-iam-hooks"` (тот же `requireHookAuth`, что и у token/refresh — общий `HookSharedSecret`)
**And** это доказывает, что **переход на `server-tls-only` НЕ открыл provision-эндпоинт для неаутентифицированных вызывателей** — HMAC-барьер сохранён симметрично для всех трёх hook-эндпоинтов на :9092 (а не только для Hydra-хуков).

**Go-`httptest`-аналог (CI):** `net/http`-клиент с CA-pool против `httptest`-сервера с
`*tls.Config` из `HooksServerTLSConfig()` (`server-tls-only`); POST на provision-route **без**
`X-Kacho-Hook-Token` → handshake OK + handler-`401` `{"error":"invalid_hook_token"}`. (Этот
сценарий валидирует только транспорт+HMAC provision-эндпоинта; корректность самой
маршрутизации Kratos→provision — вне scope 5.5, трекается `kacho-deploy#91`.)

### Сценарий 5.5-15: metrics `/metrics` по https в режиме server-tls-only → скрейпится без client-cert

**ID:** 5.5-15 (Go-`httptest`-аналог CI-validatable; e2e — smoke)

**Given** прод metrics-edge `server-tls-only` (5.5-08)

**When** клиент (с CA-trust) делает `https://…:9095/metrics` без client-cert

**Then** TLS-handshake успешен, отдаётся Prometheus exposition (200), соединение зашифровано
**And** plaintext `http://…:9095/metrics` → отвергается на транспорте.

### Сценарий 5.5-16 (опция, не включается в прод 5.5): metrics `mutual` — scrape с client-cert принят, без — отклонён

**ID:** 5.5-16 (Go-`httptest`-аналог CI-validatable; задокументирована как готовая опция)

**Given** конфиг metrics-edge `clientAuthMode=mutual` (НЕ дефолт прода 5.5; включается, когда scrape-клиент provision'ен с internal-CA client-cert)

**When** scrape-клиент **с** internal-CA client-cert делает `https://…:9095/metrics`

**Then** handshake успешен, `/metrics` отдаётся.

**And When** scrape-клиент **без** client-cert делает тот же запрос

**Then** TLS-handshake reject (RequireAndVerifyClientCert), `/metrics` не достигается.

> Этот сценарий доказывает, что `mutual`-режим работает и готов; 5.5 не включает его в
> проде, т.к. scrape-клиента с cert ещё нет — поэтому прод-дефолт `server-tls-only`
> (шифрование без невыполнимого требования client-cert). Переключение на `mutual` —
> отдельный values-flip + provision scrape-cert, без кода.

---

## DoD (сводно)

| Артефакт | Репо | CI-validatable? |
|---|---|---|
| `config.MTLSConfig` per-edge `clientAuthMode` + builder ветвится по режиму | kacho-iam | да (Go unit RED→GREEN) |
| `Validate()` fail-closed: неполный trio (5.5-04), `mutual`+пустой CA (5.5-05), unknown mode (5.5-06), безопасный дефолт (5.5-07) | kacho-iam | да (Go unit) |
| `serve.go` wiring неизменно по форме (builder отдаёт `*tls.Config`, `tls.NewListener` как раньше) | kacho-iam | да (компиляция + unit) |
| Go-`httptest` handshake-тесты: server-tls-only (с/без CA-trust), mutual (с/без client-cert), HMAC независим от TLS для token **и** provision-эндпоинтов (5.5-12..16 + 5.5-14b аналоги) | kacho-iam | да |
| deployment.yaml эмитит `CLIENTAUTHMODE` env per-edge; SEC-F mount переиспользован | kacho-deploy | да (render-guard 5.5-08/09) |
| Hydra webhook URL → https + internal-CA mount (CA-trust) | kacho-deploy | частично (render-guard URL-scheme + mount); e2e [live-Ory] |
| `values.prod.yaml` gate ON (`httpListeners: true`, server-tls-only), WHY-OFF комментарий заменён на WHY-ON-rationale | kacho-deploy | да (render-guard) |
| render-guard переписан: assert прод-ON-wiring + dev-OFF + no-new-PKI; **`CLIENTAUTHMODE` добавлен в `HOOKS_METRICS_ENV`-массив** (M2) | kacho-deploy | да |
| live-Ory smoke (scoped): :9092 принимает **Hydra token/refresh** поверх TLS+HMAC; plaintext отвергнут; provision требует HMAC. **НЕ** «registration end-to-end» — это зависит от `kacho-deploy#91` (Kratos→provision routing, вне scope 5.5) | стенд | нет — шаг 7 (заказчик) |

**TDD-порядок (ban #12):** все Go config unit-тесты (5.5-01..07) + httptest handshake-тесты
(5.5-12..16 + 5.5-14b-аналоги) пишутся RED первыми → реализация builder/Validate → GREEN;
render-guard 5.5-08..11 — RED против текущего «assert OFF» guard'а (а также RED от добавления
`CLIENTAUTHMODE` в `HOOKS_METRICS_ENV`-массив, который текущий template ещё не эмитит, M2) →
переписать deploy → GREEN. В PR показать пары RED→GREEN.

**Кросс-репо порядок (polyrepo.md):** corelib не трогается (`grpcsrv.TLSServer` уже несёт
форму cert-trio; `clientAuthMode` живёт в `config.MTLSConfig` kacho-iam, т.к. это
per-service wiring; если решат вынести в corelib — порядок corelib → iam → deploy).
Фактический порядок 5.5: **kacho-iam (config+serve) → kacho-deploy (values+template+Hydra
CA-mount+guard)**. proto/api-gateway/БД не затронуты.

## Замечания для ревьюера (scope/traceability)

- **Issue trail:** #122 завёл OFF-gate (RequireAndVerifyClientCert ломал бы webhook'и);
  #136 поставил capability OFF; **#137 (эта фаза)** делает per-edge mode и включает прод
  в `server-tls-only`. Прежний render-guard, ассертивший «prod OFF», переписывается —
  это ожидаемо, не регрессия (5.5-11).
- **Что :9092 реально несёт (ground-truth, C1-фикс):** `iamhooks.NewMux` монтирует **три**
  hook-эндпоинта — `/iam/v1/hooks/token` + `/iam/v1/hooks/refresh` (Hydra) **и**
  `/iam/v1/hooks/provision` (Kratos). `serve.go` оборачивает **весь** :9092 одним
  `*tls.Config`, поэтому выбранный режим TLS применяется ко всем трём. Все три — HMAC/`api_key`-
  аутентифицируемые HTTP-клиенты без transport client-cert → единый `server-tls-only` корректен
  для обоих классов (Hydra и Kratos-provision). Это делает выбор `server-tls-only` **более**
  обоснованным, не менее.
- **Почему hooks — `server-tls-only`, не mutual:** нормативно зафиксировано в §0
  (trust-граница) и проверяется 5.5-14 (token без HMAC → 401) + 5.5-14b (provision без HMAC →
  401) — ни Hydra-webhook, ни Kratos-web_hook не способны предъявить client-cert, HMAC
  покрывает caller-auth для всех трёх эндпоинтов, TLS покрывает шифрование. Приемлемый
  прод-posture.
- **Почему metrics — `server-tls-only` (а не mutual) в проде 5.5:** в деплое нет
  scrape-клиента с client-cert; `mutual` отклонил бы любой scrape. Опция `mutual` готова
  и покрыта 5.5-16, включается отдельным values-flip когда scrape-cert provision'ен.
- **Kratos provision-webhook routing-drift вне scope (C2, `kacho-deploy#91`):** текущий
  `kratos-config-configmap.yaml` шлёт registration/login/recovery web_hooks на gRPC-internal
  `:9091 …users:upsertFromIdentity` (+ `:onRecoveryCompleted`), а НЕ на :9092 provision-хендлер
  — pre-existing routing/correctness bug (provisioning может быть сломан независимо от #137).
  5.5 — **только транспортное шифрование** :9092; фикс маршрутизации Kratos→provision трекается
  **`kacho-deploy#91`**. Соответственно live-Ory DoD 5.5 сужен: обещается «:9092 принимает
  Hydra token/refresh по TLS+HMAC, plaintext отвергнут, provision требует HMAC» — **НЕ**
  «registration работает end-to-end» (последнее зависит от #91).
