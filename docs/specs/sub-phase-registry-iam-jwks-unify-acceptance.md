# Sub-phase registry-iam-jwks-unify — kacho-registry verifies via kacho-iam INTERNAL JWKS proxy

> **Статус:** DRAFT (awaiting `acceptance-reviewer` APPROVED gate — ban #1)
> **Дата:** 2026-07-15
> **Ревьюер:** `acceptance-reviewer`
> **Эпик/тикет:** KAC-<N>
> **Тип:** bugfix + config (authN key-distribution wiring; new INTERNAL HTTP listener + config rename) — **не** новый ресурс/RPC/proto/схема-БД
> **Repos:** `kacho-iam` (code+chart) · `kacho-registry` (config+tests) · `kacho-deploy` (helm/env) · `kacho-workspace` (docs+vault)
> **Формат:** Given-When-Then (только markdown — без кода)

---

## Обзор

Сегодня kacho-registry data-plane верифицирует подпись docker-Bearer'а, скачивая JWKS
**напрямую с Hydra** (`registry.hydra.jwksUrl` → hydra-public well-known). Эта фаза
разворачивает единый путь: **kacho-iam публикует cluster-INTERNAL HTTPS-эндпоинт
`GET /.well-known/jwks.json`, который является короткоживущим кэширующим reverse-proxy
публичного JWKS Hydra**, а data-plane скачивает JWKS **из iam и НИКОГДА не звонит в Hydra
напрямую**. **Hydra остаётся эмитентом и подписантом** токена (issuer-pin остаётся на
Hydra); iam ничего не пере-подписывает — он отдаёт **байт-в-байт зеркало** JWKS Hydra,
поэтому `kid`/`alg` совпадают с реально подписанными Hydra access-токенами. Изменение —
чисто по распределению ключей верификации: JWKS-URL указывает на iam, issuer-pin остаётся
на Hydra; это два **раздельных** конфиг-переключателя.

---

## 1. Ground truth (что и почему)

- **Кто подписывает Bearer.** Hydra чеканит и подписывает registry-Bearer. Шим `/iam/token`
  (`clients/hydra_token_exchange.go`) лишь брокерит client_credentials-токен из Hydra и
  ретранслирует Hydra'шный `access_token`; iam подписывает только одноразовый
  `client_assertion` **предъявленным SA-ключом**, а не JWKS-ключом.
- **Почему PROXY, а не serve-from-store.** iam НЕ должен отдавать ключи из своего стора
  `oidc_jwks_keys`. `kid`-mismatch фатален: собственные `kid` iam имеют форму
  `kacho-<alg>-<unixnano>` (`generateKID`, `KidPrefix "kacho-"`), тогда как Hydra-подписанный
  токен несёт **Hydra'шный `kid`** → отдача `kacho-*`-ключей = гарантированный kid-miss =
  fail-closed отказ **каждого** pull. Стор `oidc_jwks_keys` + jwks-rotator + `HydraPublisher` —
  **рудимент** удалённого дизайна «iam чеканит RS256 registry-token» (читается только
  `GetJWKSStatus`, а `HydraPublisher` вообще целится в **неправильный** keyset
  `hydra.openid.id-token`). Поэтому iam отдаёт **достоверное зеркало** публичного JWKS Hydra.
- **Прагматика keyset'а.** iam проксирует **ту же самую** Hydra well-known JWKS-URL, которую
  data-plane успешно скачивает **сегодня** (`.../.well-known/jwks.json`) — раз этот документ
  уже верифицирует живые pull'ы, зеркалирование гарантирует kid/alg-паритет без гадания о
  выборе keyset'а.
- **Registry-verifier origin-agnostic.** `jwks/verifier.go` — «голый» `http.Client{Timeout:10s}`
  GET по JWKS-URL, kid-keyed cache, on-miss single-refetch. Он **не знает и не должен знать**,
  что за URL — Hydra или iam. Поэтому на стороне registry — **только config**, verifier не
  трогаем.

**Наблюдаемая цель:** реальный docker-pull верифицируется подписью, ключи для которой
скачаны **из iam**, при этом registry не открывает **ни одного** соединения к Hydra, а
`iss`-пин по-прежнему держит Hydra; отказ iam-эндпоинта fail-closed'ит pull в 401, но
**никогда** не открывает доступ.

---

## 2. Scope / Non-goals

### In scope
1. **kacho-iam:** новый cluster-INTERNAL HTTPS-листенер (4-й, рядом с hooks:9092 / metrics:9095 /
   registry-token:9096), по умолчанию `:9097`, отдающий `GET /.well-known/jwks.json` как
   short-TTL кэширующий reverse-proxy публичного JWKS Hydra; server-TLS (one-way) с internal-CA
   leaf; per-call-timeout http-клиент к апстриму; выставлен **только** на Service
   `kacho-iam-internal`.
2. **kacho-registry:** config-rename `HydraJWKSURL`→`IAMJWKSURL`, env
   `KACHO_REGISTRY_HYDRA_JWKS_URL`→`KACHO_REGISTRY_IAM_JWKS_URL`, default → iam-URL, обновление
   doc-комментария; 4 ссылки в `serve.go` (empty-check/error-text, `requireSecureJWKSURL`,
   `jwks.New`, env-имя внутри error-строки). **`verifier.go` не трогаем.**
3. **Issuer-pin остаётся на Hydra:** `HydraIssuer` / `KACHO_REGISTRY_HYDRA_ISSUER` **НЕ**
   переименовывается и **НЕ** перенаправляется; оба prod-гарда сохраняются
   (`requireSecureJWKSURL` теперь форсит https на iam-URL, `requireIssuerPinned` по-прежнему
   форсит пиннутый Hydra-issuer). Alg-allowlist `{RS256, ES256}` и `aud=registry.kacho.local` —
   registry-owned, без изменений.
4. **kacho-deploy:** порт/Service iam-JWKS + CA-trust registry-пода; флип
   `registry.iam.jwksUrl` на **живой** iam-эндпоинт; сиквенс iam-first.
5. **kacho-workspace:** polyrepo.md runtime-edge `kacho-registry → kacho-iam (jwks-fetch)`;
   security.md заметка про internal-only unauthenticated-by-design; vault
   `edges/registry-to-iam-jwks-fetch.md` + KAC-trail; **исправление устаревших docstring'ов**,
   отрицающих JWKS-эндпоинт (security.md инвариант #5, doc-truthfulness).

### Non-goals (явно вне скоупа)
- **Hydra остаётся подписантом/эмитентом.** iam **не** пере-чеканит registry-токен. `iss`
  токена остаётся Hydra-issuer'ом.
- **Не воскрешаем vestige.** `oidc_jwks_keys` / jwks-rotator / `HydraPublisher` остаются
  нетронутыми и **вне** verify-пути. Изменение — строго Hydra-JWKS **proxy**.
- **Никакой новой криптографии / нового verifier'а** — `jwks/verifier.go` origin-agnostic и
  не меняется.
- **Никакого нового proto / нового gRPC-RPC / новой схемы БД.** Это HTTP-листенер + config, не
  ресурс. `proto-api-reviewer` и `db-architect-reviewer` для этой фазы не требуются.
- **JWKS-route НЕ регистрируется** ни в одном external `*Addr`-блоке
  `kacho-api-gateway/internal/restmux/mux.go` — internal-only, прямой svc-to-svc (ban #6).
- **Не меняем docker access-control flow** (`/iam/token`-шим, SA-key → token). Меняется только
  **источник ключей верификации**.

---

## 3. Acceptance-сценарии (Given-When-Then)

ID трассируются в имена integration- / newman-тестов. Стадии S1–S4 — по кросс-репо-графу
(iam → registry → deploy → docs); каждая стадия — самостоятельный deliverable со своим DoD (§6).

Термины: **iam-JWKS-эндпоинт** = новый internal HTTPS `GET /.well-known/jwks.json` на iam
(:9097). **registry-verifier** = data-plane `jwks/verifier.go`, скачивающий JWKS по
сконфигурированному URL. **Upstream** = публичный JWKS Hydra.

---

### Стадия S1 — kacho-iam: internal Hydra-JWKS proxy эндпоинт

#### RJU-01 — happy: iam отдаёт байт-в-байт зеркало JWKS Hydra с Cache-Control

**Given** iam сконфигурирован с апстримом `KACHO_IAM_HYDRA_JWKS_URL` (default in-cluster база
  `http://kacho-umbrella-hydra-public.<ns>.svc:4444/.well-known/jwks.json`, fallback
  `ResolveHydraIssuer()+"/.well-known/jwks.json"`)
**And** апстрим (fake Hydra в тесте) отдаёт JWKS-документ с `kid=hydra-kid-1`, `alg=RS256`

**When** клиент делает `GET https://<iam-internal>:9097/.well-known/jwks.json`

**Then** ответ `200 OK`, тело **байт-в-байт идентично** апстрим-JWKS (тот же набор `kid`,
  тот же `alg`, тот же `n`/`e`/`x`/`y`)
**And** установлен заголовок `Cache-Control` (эндпоинт кэширует ~5m TTL, honor'ит upstream
  `Cache-Control`)
**And** отдаётся **именно** Hydra'шный keyset — ни одного `kacho-*`-`kid` из `oidc_jwks_keys`
**And** соединение обслужено по **server-TLS** с internal-CA leaf (не mTLS)

#### RJU-02 — per-call timeout на апстрим-фетч (не DefaultClient)

**Given** апстрим Hydra отвечает медленно / висит (half-open)

**When** iam-JWKS-эндпоинт фетчит апстрим на cold-cache

**Then** используется http-клиент с **per-call `context.WithTimeout`** (architecture.md: никогда
  `http.DefaultClient` на hot-path) — фетч ограничен по времени, горутина не висит вечно
**And** по истечении таймаута апстрим считается недоступным → см. RJU-03 (fail-closed)

#### RJU-03 — fail-closed: cold-cache + Hydra недоступна → 502/503 (никогда empty-200)

**Given** кэш iam-JWKS-эндпоинта **пуст** (cold) для запрашиваемого документа
**And** апстрим Hydra недоступен (network error / non-200 / пустой keyset / timeout)

**When** клиент делает `GET /.well-known/jwks.json`

**Then** ответ `502` **или** `503` (registry трактует non-200 как fail-closed reject)
**And** iam **никогда** не отдаёт `200` с пустым keyset
**And** iam **никогда** не подставляет собственные `oidc_jwks_keys` `kacho-*`-`kid`ы как замену
**And** ошибка залогирована (operability: указывает на апстрим-инфру, не на клиента)

#### RJU-04 — warm-cache bounded-stale во время кратковременного blip Hydra

**Given** iam-JWKS-эндпоинт ранее успешно сфетчил и закэшировал JWKS (warm cache, within TTL)
**And** апстрим Hydra кратковременно недоступен (blip)

**When** клиент делает `GET /.well-known/jwks.json` в окне blip'а

**Then** отдаётся **закэшированный** документ (bounded-stale в пределах короткого TTL) с `200`
**And** после истечения TTL при всё ещё недоступном апстриме поведение деградирует в RJU-03
  (fail-closed), не в indefinitely-stale

#### RJU-05 — ротация ключей: Hydra публикует новый kid → iam обновляет и отдаёт новый kid

**Given** iam-JWKS-эндпоинт закэшировал keyset с `kid=hydra-kid-1`
**And** Hydra ротирует ключи: апстрим теперь отдаёт `{hydra-kid-1, hydra-kid-2}`

**When** истекает TTL кэша iam (либо upstream `Cache-Control` инвалидирует) и приходит новый
  `GET /.well-known/jwks.json`

**Then** iam рефетчит апстрим и отдаёт **обновлённый** keyset, содержащий `hydra-kid-2`
**And** отданные `kid`ы по-прежнему **ровно** Hydra'шные (не `kacho-*`) → токен, подписанный
  новым `hydra-kid-2`, верифицируем data-plane'ом

#### RJU-06 — internal-only lock: JWKS только на internal-листенере, не на external

**Given** iam поднят с листенерами hooks(:9092) / metrics(:9095) / registry-token(:9096, «EXTERNAL-reachable», `serve.go:466`) / **jwks-proxy(:9097, новый)**

**When** пробуют достучаться до `/.well-known/jwks.json`

**Then** маршрут отвечает **только** на internal jwks-proxy-листенере (:9097), выставленном
  **исключительно** на Service `kacho-iam-internal`
**And** маршрут **НЕ** доступен на external registry-token-муксе (:9096) — регрессия ban #6
  (публикация JWKS на EXTERNAL-endpoint запрещена)
**And** маршрут **НЕ** на gRPC :9091 (не умеет отдать plain HTTP GET)
**And** порт `:9097` **не** выставлен на публичном Service iam (только `kacho-iam-internal`)

#### RJU-07 — unauthenticated-by-design (осознанное задокументированное исключение)

**Given** JWKS-route отдаёт **публичные ключи верификации** (standard OIDC well-known)

**When** приходит `GET /.well-known/jwks.json` без клиентского токена/сертификата

**Then** маршрут отвечает без authN-гейта (public keys) — осознанное, **задокументированное**
  исключение из security.md «authN на каждом листенере», обосновано: internal-only surface +
  server-TLS, отдаётся только публичный материал
**And** это исключение зафиксировано в security.md (§ Non-goals / doc-truthfulness) и в vault-edge
**And** (по решению) mTLS-gating возможен, но требует изменения TLS-клиента registry-verifier'а
  (ломает свойство «verifier untouched») — риск R5, решение принято в пользу documented exception

#### RJU-08 — vestige untouched: oidc_jwks_keys вне verify-пути

**Given** в iam остаётся стор `oidc_jwks_keys` + jwks-rotator + `HydraPublisher` (рудимент)

**When** iam-JWKS-эндпоинт обслуживает запрос

**Then** verify-путь **не** читает `oidc_jwks_keys` — тело ответа берётся **только** из
  апстрим-фетча/кэша Hydra
**And** отданные `kid`ы никогда не имеют префикса `kacho-` (это был бы гарантированный kid-miss)
**And** `oidc_jwks_keys` / rotator / `HydraPublisher` не изменены и не подключены к новому пути

---

### Стадия S2 — kacho-registry: config-rename, verifier untouched, issuer-pin retained

#### RJU-09 — happy: валидный Hydra-подписанный токен, JWKS из iam → подпись верна → push+pull авторизованы

**Given** registry сконфигурирован `KACHO_REGISTRY_IAM_JWKS_URL` = URL iam-JWKS-эндпоинта (https)
**And** `KACHO_REGISTRY_HYDRA_ISSUER` пиннит Hydra-issuer (issuer-pin остаётся на Hydra)
**And** iam-JWKS-эндпоинт отдаёт Hydra-зеркало (fake-iam в тесте отдаёт Hydra-mirrored keys)
**And** клиент держит Hydra-стиль-подписанный access-токен: `alg=RS256`, `kid=hydra-kid-1`,
  `iss=<Hydra issuer>`, `aud=registry.kacho.local`, `exp` в будущем

**When** data-plane верифицирует Bearer при docker push/pull

**Then** registry-verifier фетчит JWKS **из iam-URL** (не из Hydra), резолвит `kid=hydra-kid-1`,
  подпись **верна**
**And** `iss`-пин по-прежнему энфорсится (Hydra-issuer совпал) → verify OK
**And** push и pull **авторизованы**
**And** registry **не открывает ни одного** сетевого соединения к Hydra (data-plane never dials Hydra)

#### RJU-10 — ротация на data-plane: новый kid → verifier делает single-refetch из iam → верифицирует

**Given** registry-verifier закэшировал `{hydra-kid-1}` из iam
**And** предъявлен токен, подписанный `hydra-kid-2` (после ротации, RJU-05)

**When** verifier не находит `hydra-kid-2` в кэше (kid-miss)

**Then** verifier делает **single-refetch** JWKS из iam-URL, получает `{hydra-kid-1, hydra-kid-2}`
**And** резолвит `hydra-kid-2`, подпись верна → verify OK (существующее on-miss-refetch-поведение
  verifier'а сохранено, origin-agnostic)

#### RJU-11 — fail-closed: iam-JWKS недоступен/5xx + нет кэш-ключа → 401 invalid_token (никогда allow)

**Given** registry-verifier сконфигурирован на iam-URL
**And** iam-JWKS-эндпоинт недоступен / отдаёт 5xx (RJU-03), и в TTL-кэше verifier'а нет пригодного
  ключа для `kid` токена

**When** клиент делает docker pull с корректным по форме Hydra-Bearer'ом

**Then** verify падает (JWKS-fetch/unreachable) → data-plane отвечает docker-клиенту
  **HTTP 401** `WWW-Authenticate: Bearer ... error="invalid_token"` — fail-closed
**And** доступ **никогда** не открывается (never allow, never fail-open)
**And** различие в логе: «JWKS unreachable» vs «token invalid» (указывает на инфру vs клиента)

> Различение хопов (load-bearing): **iam-эндпоинт** при cold-cache+Hydra-down отдаёт **502/503**
> registry-verifier'у (RJU-03); **registry data-plane**, не сумев верифицировать и не имея
> кэш-ключа, отдаёт **401 invalid_token** docker-клиенту (RJU-11). Клиент видит 401, не 5xx.

#### RJU-12 — within-TTL кэш во время blip iam → verify из кэша успешен

**Given** registry-verifier ранее сфетчил и закэшировал ключ для `kid` токена (within TTL)

**When** тот же токен предъявлен, пока iam-JWKS-эндпоинт кратковременно down

**Then** verify **успешен из кэша** (существующее cache-поведение verifier'а сохранено;
  fail-closed применяется только когда пригодного ключа нет)

#### RJU-13 — negative token-классы → 401 (пин/allowlist сохранены)

**Given** registry-verifier на iam-JWKS-URL, issuer-пин на Hydra, alg-allowlist `{RS256, ES256}`,
  `aud=registry.kacho.local`

**When** предъявлен Bearer, невалидный по каждому из классов:
  - **n1** unknown `kid` (нет в iam-JWKS даже после force-refetch)
  - **n2** `iss` не совпадает с пиннутым Hydra-issuer'ом (issuer-pin retained)
  - **n3** `aud` не `registry.kacho.local`
  - **n4** `alg` вне `{RS256, ES256}` (в т.ч. `alg=none`)
  - **n5** `exp` в прошлом (за пределами clock-skew leeway)
  - **n6** подпись не верифицируется против JWKS-ключа

**Then** каждый класс → data-plane отвечает **HTTP 401** `WWW-Authenticate ... invalid_token`
**And** доступ **никогда** не открывается
**And** `iss`-пин продолжает отвергать mismatch **несмотря** на то, что JWKS теперь из iam
  (декаплинг: JWKS-URL=iam, issuer=Hydra — раздельные knob'ы)

#### RJU-14 — config: новый env распарсен, prod-гарды сохранены, HydraIssuer не тронут

**Given** обновлённый `config.go`: поле `IAMJWKSURL`, env `KACHO_REGISTRY_IAM_JWKS_URL`,
  doc-комментарий обновлён; `serve.go` обновил 4 ссылки

**When** сервис стартует и валидирует config

**Then** `KACHO_REGISTRY_IAM_JWKS_URL` парсится и питает `jwks.New(...)`
**And** `requireSecureJWKSURL` в production отвергает `http://`-iam-URL (форсит https)
**And** `requireIssuerPinned` **не изменён**: пустой Hydra-issuer по-прежнему отвергается на старте
**And** `HydraIssuer` / `KACHO_REGISTRY_HYDRA_ISSUER` **не** переименован и **не** перенаправлен
  (токен `iss` остаётся Hydra-issuer'ом; `verifier.go` отвергает iss-mismatch)
**And** `jwks/verifier.go` **не изменён** (origin-agnostic; проверяется diff'ом PR)

---

### Стадия S3 — kacho-deploy: iam JWKS порт/Service + CA-trust + registry env flip

#### RJU-15 — iam subchart рендерит jwksProxy-порт на kacho-iam-internal Service

**Given** чарт `charts/kacho-iam` с добавленным `ports.jwksProxy` (default `9097`)

**When** рендерится iam-манифест

**Then** порт `9097` добавлен в `service-internal.yaml` (Service `kacho-iam-internal`), **не** в
  публичный Service
**And** проброшен env `KACHO_IAM_HYDRA_JWKS_URL` (cluster-internal hydra-public база)
**And** internal-CA leaf `serverHosts` включает `kacho-iam-internal` (values.yaml:241 — подтвердить)
**And** helm-template-тест ассертит: порт на internal-Service, отсутствует на публичном

#### RJU-16 — registry subchart: env-flip на iam-URL + CA-trust internal-CA + reconcile TLS-sidecar

**Given** subchart registry с env `KACHO_REGISTRY_IAM_JWKS_URL` (переименован с `HYDRA_JWKS_URL`),
  source `.Values.iam.jwksUrl`; `values.yaml` default переименован

**When** рендерится registry-манифест

**Then** env `KACHO_REGISTRY_IAM_JWKS_URL` =
  `https://kacho-iam-internal.kacho.svc.cluster.local:9097/.well-known/jwks.json`
**And** registry-под доверяет internal-CA, подписавшему iam-internal leaf (SSL_CERT_DIR / CA-bundle),
  иначе fetch-fail → 401-storm (риск R3)
**And** TLS-sidecar reconciled: либо upstream sidecar'а перенаправлен с hydra-public на iam-JWKS
  Service, либо JWKS-proxy-роль sidecar'а снята (рекомендация: фетчить iam напрямую)
**And** `registry.hydra.issuer` (helm-ключ) **сохранён** как Hydra-issuer

#### RJU-17 — deploy-сиквенс: registry env флипается только после live-and-verified iam-эндпоинта

**Given** fail-closed-семантика (преждевременный флип = 401-storm на всех pull'ах — риск R4)

**When** раскатывается изменение

**Then** порядок enforced: **iam-эндпоинт задеплоен и подтверждён serving** (smoke
  `GET /.well-known/jwks.json` → 200 с Hydra-kid'ами) → **затем** флип `registry.iam.jwksUrl`
**And** документированный runbook фиксирует iam-first + smoke-before-flip

#### RJU-18 — JWKS-route не зарегистрирован в external api-gateway restmux

**Given** политика ban #6 (internal-only, direct svc-to-svc)

**When** проверяется `kacho-api-gateway/internal/restmux/mux.go`

**Then** маршрут `/.well-known/jwks.json` **не** зарегистрирован ни в одном external `*Addr`-блоке
**And** registry фетчит iam напрямую (svc-to-svc), не через api-gateway

---

### Стадия S4 — kacho-workspace: docs + vault + doc-truthfulness

#### RJU-19 — polyrepo.md runtime-edge registry→iam (jwks-fetch); ацикличность

**Given** `kacho-registry` сейчас **вообще отсутствует** в polyrepo.md

**When** обновляется polyrepo.md

**Then** добавлено runtime-ребро `kacho-registry → kacho-iam (jwks-fetch)`: HTTPS GET JWKS с
  cluster-internal iam-эндпоинта, sync request-path, fail-closed, internal-CA-trusted, **замещает**
  прямой Hydra-public fetch
**And** ацикличность holds: iam **никогда** не зовёт registry
**And** (опц.) registry бэкфиллится в таблицу репо/build-граф + отмечены два уже существующих
  ребра `registry → iam` (Check/fgaproxy :9091, ProjectService.Get :9090)

#### RJU-20 — security.md заметка про internal-only unauthenticated-by-design

**When** обновляется security.md

**Then** зафиксировано: JWKS-route — internal-only, unauthenticated-by-design (публичные ключи,
  standard OIDC), server-TLS — осознанное задокументированное исключение из «authN на каждом
  листенере» (RJU-07)

#### RJU-21 — vault edge + KAC-trail

**When** обновляется vault

**Then** создан `obsidian/kacho/edges/registry-to-iam-jwks-fetch.md` (protocol HTTPS GET JWKS, sync,
  fail-closed, internal-CA-trusted, History с KAC-номером)
**And** заведён/обновлён `obsidian/kacho/KAC/KAC-<N>.md` (Status, Repos, PRs, «Что и зачем»,
  затронутые сущности vault, DoD-чеклист)

#### RJU-22 — doc-truthfulness: устаревшие docstring'и исправлены (security.md инвариант #5)

**Given** сейчас минимум четыре docstring'а утверждают, что iam **не** отдаёт JWKS / нет
  `/iam/token/jwks`-эндпоинта — стейл, приглашает будущего контрибьютора «пере-удалить» эндпоинт

**When** применяется изменение

**Then** исправлены (в том же изменении):
  - `handler/registrytokenhttp/handler.go:11-13`
  - `config/registry_token.go:5` (уже само-противоречив с handler.go)
  - `registrytokenwire/build.go:42-44`
  - `clients/hydra_token_exchange.go:4-9`
**And** новый текст утверждает: iam теперь отдаёт **Hydra-JWKS PROXY** на internal-surface (Hydra
  по-прежнему issuer/подписант, iam **не** чеканит)

---

### Сквозные e2e-сценарии (через развёрнутый стек)

#### RJU-23 — e2e happy: docker login → /iam/token → push+pull, верификация из iam-JWKS

**Given** развёрнутый стек: iam-JWKS-эндпоинт live, registry сконфигурирован на iam-URL

**When** `docker login` → токен через `/iam/token` (Hydra-brokered client_credentials) →
  `docker push` + `docker pull`

**Then** push и pull **успешны**, верификация подписи ключами **из iam-JWKS** (не из Hydra)
**And** registry **не** открывает соединение к Hydra (наблюдаемо: нет сетевого хопа registry→Hydra)

#### RJU-24 — e2e negative: iam-JWKS down → pull 401 invalid_token (fail-closed, never allow)

**Given** развёрнутый стек, iam-JWKS-эндпоинт **выведен из строя** (down / 5xx), кэш verifier'а
  без пригодного ключа

**When** `docker pull`

**Then** pull → **HTTP 401** `WWW-Authenticate: Bearer error="invalid_token"` (fail-closed)
**And** **никогда** не 503 наружу клиенту, **никогда** не allow

---

## 4. Инварианты (MUST hold — для ревьюера)

| # | Инвариант | Сценарии |
|---|---|---|
| I1 | iam отдаёт **байт-в-байт** зеркало JWKS Hydra; `kid`/`alg`-паритет с Hydra-подписанными токенами. | RJU-01, RJU-08 |
| I2 | iam **никогда** не отдаёт `kacho-*`-`kid`ы из `oidc_jwks_keys`; vestige вне verify-пути. | RJU-08 |
| I3 | Fail-closed: cold-cache+Hydra-down → iam 502/503; verifier без кэш-ключа → 401; **никогда** allow, **никогда** empty-200, **никогда** fail-open. | RJU-03, RJU-11, RJU-24 |
| I4 | Bounded-stale только в пределах короткого TTL; никогда indefinitely-stale. | RJU-04, RJU-12 |
| I5 | Issuer-pin остаётся на **Hydra**; `iss`-mismatch отвергается несмотря на смену JWKS-URL на iam (декаплинг knob'ов). | RJU-13/n2, RJU-14 |
| I6 | JWKS-route internal-only: только `:9097` на `kacho-iam-internal`; **не** на external :9096, **не** на :9091, **не** в api-gateway restmux (ban #6). | RJU-06, RJU-18 |
| I7 | `jwks/verifier.go` **не изменён** (origin-agnostic); registry-side — только config. | RJU-09, RJU-14 |
| I8 | data-plane **не открывает ни одного** соединения к Hydra. | RJU-09, RJU-23 |
| I9 | Ротация ключей проходит end-to-end: Hydra new-kid → iam refetch → verifier on-miss refetch → verify OK. | RJU-05, RJU-10 |
| I10 | Per-call timeout на апстрим-фетче iam (не DefaultClient) — hot-path не висит. | RJU-02 |
| I11 | Deploy iam-first + smoke-before-flip; преждевременный флип-риск задокументирован. | RJU-17 |
| I12 | Стейл-docstring'и исправлены в том же изменении (security.md инвариант #5). | RJU-22 |
| I13 | Hydra остаётся подписантом; iam-minting **не** воскрешается. | Non-goals, RJU-08 |

---

## 5. Тест-план (строгий TDD — RED до GREEN, ban #12)

Все тесты авторятся и прогоняются **RED до** кода; пара RED→GREEN показывается в PR.

### 5.1 kacho-iam (unit / handler)
- **RJU-01 happy:** handler-unit с **fake** Hydra-апстрим-сервером → маршрут `/.well-known/jwks.json`
  отдаёт **байт-в-байт** JWKS (те же `kid`ы), ставит `Cache-Control`.
- **RJU-02 timeout:** ассерт, что апстрим-фетч использует per-call `context.WithTimeout` (не
  DefaultClient) — тест с висящим апстримом завершается по таймауту, не вечно.
- **RJU-03 fail-closed:** cold cache + Hydra unreachable (500 / closed / empty keys / timeout) →
  `502`/`503`; **никогда** empty-`200`; **никогда** `kacho-*`-`kid`ы `oidc_jwks_keys`.
- **RJU-04 bounded-stale:** warm cache + blip → закэшированный `200`; после TTL → fail-closed.
- **RJU-05 rotation:** апстрим меняет keyset → после TTL iam отдаёт новый `kid`.
- **RJU-06 internal-only lock:** маршрут доступен **только** на internal jwks-листенере и **НЕ**
  достижим на external :9096 registry-token-муксе (регрессия ban #6).
- **RJU-08 vestige:** verify-путь не читает `oidc_jwks_keys`; отданные `kid`ы никогда `kacho-*`.

### 5.2 kacho-registry (config / verifier)
- Существующие `jwks/verifier_test.go` уже локают несущее поведение **origin-agnostic**:
  `WrongIssuer` (verifier_test.go:247 пиннит `iss=Hydra`), `JWKSUnreachable_FailClosed` (:478),
  `StaleCacheJWKSDown_FailClosed` (:491).
- **RJU-09/RJU-13 verify:** новый кейс — verifier направлен на **fake iam** JWKS-сервер, отдающий
  Hydra-mirrored ключи; Hydra-стиль-подписанный токен проходит, при этом `iss`-пин по-прежнему
  форсит Hydra (n2 mismatch → reject).
- **RJU-14 config:** новый `KACHO_REGISTRY_IAM_JWKS_URL` распарсен; `requireSecureJWKSURL`
  отвергает `http://` в production; `requireIssuerPinned` без изменений (пустой Hydra-issuer
  отвергается). **RED first** — переименование env-ожидания.
- Diff-guard: `jwks/verifier.go` без изменений.

### 5.3 kacho-deploy (helm-template)
- **RJU-15:** рендер iam-манифеста — порт `9097` на `kacho-iam-internal` Service, отсутствует на
  публичном; env `KACHO_IAM_HYDRA_JWKS_URL` проброшен; `serverHosts ∋ kacho-iam-internal`.
- **RJU-16:** рендер registry-манифеста — env `KACHO_REGISTRY_IAM_JWKS_URL` = live iam-URL (https);
  CA-bundle/SSL_CERT_DIR доверяет internal-CA; TLS-sidecar reconciled.

### 5.4 e2e / newman (через развёрнутый стек)
- **Happy (RJU-23):** `docker login` → токен `/iam/token` (Hydra-brokered) → push+pull успешны,
  верификация из iam-JWKS (registry never dials Hydra). ≥1 happy.
- **Negative (RJU-24):** iam-JWKS-эндпоинт down → pull → **HTTP 401** `invalid_token` (fail-closed,
  **никогда** 503 наружу, **никогда** allow). ≥1 negative.

> Финальный гейт (ai-tooling §7): `go test ./... -race` + `golangci-lint run` + `govulncheck` +
> newman green **в обоих** репо (iam и registry); плюс ручной smoke iam-эндпоинта до registry-флипа
> (RJU-17) и e2e push+pull на развёрнутом стеке.

---

## 6. DoD по стадиям (кросс-репо-граф iam → registry → deploy → docs)

**S1 — kacho-iam (первым; live-and-serving ДО любого registry-флипа):** 4-й internal HTTPS-листенер
`:9097` `GET /.well-known/jwks.json` (reverse-proxy Hydra-JWKS, server-TLS internal-CA leaf, per-call
timeout, ~5m TTL honor Cache-Control); fail-closed 502/503 на cold+down; internal-only lock;
vestige `oidc_jwks_keys` не тронут; стейл-docstring'и исправлены; RED→GREEN unit (RJU-01..08). DoD:
RJU-01..08 зелёные.

**S2 — kacho-registry (после live iam-эндпоинта):** config-rename `HydraJWKSURL`→`IAMJWKSURL`, env
`KACHO_REGISTRY_HYDRA_JWKS_URL`→`KACHO_REGISTRY_IAM_JWKS_URL`, default→iam-URL, doc-комментарий; 4
ссылки `serve.go`; `KACHO_REGISTRY_HYDRA_ISSUER` пиннут на Hydra (не тронут); оба prod-гарда;
`verifier.go` untouched; RED→GREEN config+verifier (RJU-09..14). DoD: RJU-09..14 зелёные, diff
verifier.go пуст.

**S3 — kacho-deploy:** порт `jwksProxy=9097` на `kacho-iam-internal` + `KACHO_IAM_HYDRA_JWKS_URL`
upstream; registry env-flip + internal-CA-trust + reconcile TLS-sidecar; JWKS-route не в external
restmux; **сиквенс iam-first + smoke-before-flip**; helm-render тесты (RJU-15..18). DoD: RJU-15..18
зелёные, endpoint verified serving до флипа.

**S4 — kacho-workspace:** polyrepo.md runtime-edge (+опц. registry-backfill); security.md
internal-only-note; vault `edges/registry-to-iam-jwks-fetch.md` + KAC-trail; doc-truthfulness
(RJU-19..22). DoD: docs+vault обновлены.

**Общий DoD эпика:**
- [ ] APPROVED `acceptance-reviewer` (этот док) до любого кода (ban #1).
- [ ] KAC-тикет + ветки `KAC-<N>` в затронутых репо; KAC-trail в vault.
- [ ] RED-тесты авторены и прогнаны первыми для RJU-01..24 — пара RED→GREEN в PR.
- [ ] iam: internal Hydra-JWKS proxy live-and-serving (RJU-01..08); vestige не тронут (I2/I13).
- [ ] registry: config-only, `verifier.go` untouched (I7); issuer-pin на Hydra (I5); data-plane
      never dials Hydra (I8).
- [ ] Fail-closed на всех путях (I3); ротация end-to-end (I9); internal-only (I6).
- [ ] deploy iam-first + smoke-before-flip (I11); CA-trust настроен (RJU-16).
- [ ] docs/vault/edge + doc-truthfulness (RJU-19..22, I12).
- [ ] `go test ./... -race` + `golangci-lint run` + `govulncheck` + newman green в iam и registry.
- [ ] e2e push+pull на стенде (RJU-23) + fail-closed pull-401 (RJU-24); тикет → Test → Done с
      артефактами (PR-URL, лог тестов RED→GREEN), vault-trail обновлён.

---

## 7. Трассируемость к дизайну (APPROVED)

| Пункт дизайна | Сценарий / Инвариант |
|---|---|
| keyOwnership: PROXY Hydra-JWKS, iam НЕ serve-from-store `oidc_jwks_keys`; kid-mismatch фатален | RJU-01, RJU-08, I1, I2 |
| iamEndpoint: 4-й internal HTTPS-листенер :9097, server-TLS internal-CA leaf, per-call timeout, TTL/Cache-Control | RJU-01, RJU-02, RJU-15, I10 |
| iamEndpoint: fail-closed cold+down → 502/503; warm-blip bounded-stale | RJU-03, RJU-04, I3, I4 |
| iamEndpoint: internal-only (не :9091, не :9096), unauthenticated-by-design | RJU-06, RJU-07, I6 |
| registryChange: config-only, `verifier.go` untouched, rename env, 4 refs serve.go | RJU-14, I7 |
| registryChange: issuer-pin остаётся Hydra; оба prod-гарда; alg/aud неизменны | RJU-13, RJU-14, I5 |
| registryChange: data-plane never dials Hydra | RJU-09, RJU-23, I8 |
| deployChange: port/Service iam + CA-trust + env-flip + reconcile sidecar; не в external restmux | RJU-15..18, I6, I11 |
| deployChange/crossRepoOrder: iam-first deploy + smoke-before-flip | RJU-17, I11 |
| deployChange: polyrepo-edge + security.md note + vault + doc-truthfulness | RJU-19..22, I12 |
| testStrategy: iam unit (fake Hydra), registry verifier/config, e2e happy+negative | §5.1–5.4 |
| risks R1 (wrong-keyset outage): зеркало точного Hydra-URL + byte/kid-паритет | RJU-01, I1 |
| risks R2 (iam new hard-dep): short-TTL + verifier fresh-cache, never fail-open | RJU-03, RJU-04, RJU-12, I3, I4 |
| risks R3 (TLS/CA-trust): https-in-prod + registry доверяет internal-CA | RJU-16, RJU-14 |
| risks R4 (deploy-sequencing): iam-first + smoke | RJU-17, I11 |
| risks R5 (authN-everywhere tension): documented internal-only exception (не mTLS) | RJU-07, RJU-20 |
| risks R6 (doc-truthfulness debt): 4 docstring'а исправлены | RJU-22, I12 |
| risks R7 (vestige revival): iam-minting не воскрешён, oidc_jwks_keys вне пути | RJU-08, Non-goals, I13 |
| risks R8 (polyrepo/vault completeness): edge backfill + vault-note | RJU-19, RJU-21 |

---

## 8. Координация (после APPROVED)

1. `acceptance-reviewer` → `✅ APPROVED` (статус дока → APPROVED). Итерации по замечаниям.
2. `superpowers:writing-plans` → `integration-tester` (RED-тесты по RJU-*) → `rpc-implementer`
   (реализация по стадиям S1→S4, кросс-репо-граф).
3. **Не требуются** для этой фазы: `proto-api-reviewer` (нет proto-изменений),
   `db-architect-reviewer` (нет схемы БД — `oidc_jwks_keys` не тронут). Ревью — `go-style-reviewer`
   (iam handler + config), `system-design-reviewer` (fail-closed / cache / new hard-dep),
   `security.md`-инварианты (internal-only, doc-truthfulness).
4. Заказчик — только финальный smoke / e2e (RJU-23/RJU-24: `docker login`+push+pull, fail-closed
   pull-401), шаг 7.

Сценарий оказался неоднозначным после старта кодирования → вернуть сюда для уточнения; НЕ менять
поведение реализации без правки этого дока.
