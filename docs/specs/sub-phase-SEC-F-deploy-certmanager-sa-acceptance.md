# Sub-phase SEC-F — kacho-deploy: cert-manager internal CA PKI + per-service mTLS Certificates + least-priv SA wiring + FGA NetworkPolicy — Acceptance

> Статус: DRAFT (v2 — переписан по acceptance-review v1, ground-truth §4.1 эпика)
> Дата: 2026-06-11
> Ревьюер: acceptance-reviewer (gate) + system-design-reviewer (на эпик-дизайн)
> Эпик/тикет: KAC-<TBD> (subtask of SEC epic — `docs/specs/sub-phase-SEC-mtls-iam-authz-epic.md`)
> Репо: `kacho-deploy`
> Зависит от: SEC-C (IAM FGA-proxy + ReBAC SA-tuples + client-cert→SA mapping), SEC-D (vpc/compute/nlb убрали прямой FGA + mTLS server/client), SEC-E (api-gateway mTLS backend-dial)

## Обзор

SEC-F — это **wiring-подфаза стенда**: она не пишет Go-кода и не меняет proto, а собирает
PKI и helm-профиль, поверх которых уже-реализованные (SEC-B..E) mTLS-транспорт и
ReBAC-least-priv service-identity начинают работать end-to-end на kind-стенде. Поставляется:
internal CA `ClusterIssuer` (CA-типа, **не** ACME/Let's Encrypt — для cluster-internal mTLS,
отдельно от существующего публичного `letsencrypt-prod`); per-service `Certificate` ×2
(раздельные **server-cert** SAN=`<svc>.kacho.svc.cluster.local` и **client-cert** URI-SAN в
**существующем SPIRE-формате** `spiffe://kacho.cloud/ns/<ns>/sa/kacho-<svc>`) в раздельных
secret'ах; helm-values профиль `mtls.enabled` (per-edge); `NetworkPolicy` «ingress в openfga
только из kacho-iam» (включается ПОСЛЕ SEC-D); монтирование каждым подом своего client-cert
так, что его identity = его SA.

**Контракт подфазы — реализм:** профиль мёржится в `main` с `mtls.enabled=false` (default).
При `enabled=false` стенд поднимается ровно как сейчас (insecure service→service), вся
существующая регрессия зелёная — нулевая регрессия. При `enabled=true` (production-профиль)
стенд целиком на mTLS, e2e зелёные под узкими ReBAC-SA. Это покрывает требования эпика
#1 (opt-in), #2 (cert-manager PKI), #4 (least-priv SA), #5 (раздельные client+server cert;
стенд целиком), #6 (FGA недостижим вне IAM — сетевая изоляция), и DoD-эпика §5.

### Ground-truth (свериться с кодом — закрывает acceptance-review v1)

Допущения v1-черновика разошлись с реальным kacho-deploy. Канонические факты (источник —
`project/kacho-deploy/helm/umbrella/{values.dev.yaml,values.prod.yaml,values.yaml,Chart.yaml}`,
`.../spire-registration/`, `.../charts/cert-manager-config/`, `.../charts/kacho-iam/templates/`,
`Makefile`, `kacho-proto/gen/permission_catalog.json`):

- **SPIRE-каркас УЖЕ есть** (НЕ «инфраструктуры ещё нет»). Umbrella содержит subchart'ы
  `spire-server`/`spire-agent`/`spiffe-csi-driver` (Chart.yaml, condition `<chart>.enabled`,
  в dev/kind выключены — `enabled:false`, включаются в `values.prod.yaml`) + dir
  `helm/umbrella/spire-registration/` + `spiffe.trustDomain=kacho.cloud`, `spiffe.clusterName=kacho`.
  Существующий identity-формат: `spiffe://{{ trustDomain }}/ns/kacho-system/sa/kacho-<svc>`
  (`spire-registration/kacho-vpc.yaml` и др.). **SEC-F НЕ вводит параллельный
  `spiffe://kacho/<sva-id>`** — cert-manager выдаёт URI-SAN В ЭТОМ ЖЕ формате (§4.1.4),
  чтобы при будущем включении SPIRE identity не мигрировала. См. §«Разрешение SPIFFE-коллизии».
- **`make e2e-test` ≠ newman**: target гоняет `bash e2e/0.1/*.sh` (стенд-смоук E1/E5/E6…).
  CRUD-регрессионный **newman живёт в сервисных репо** (`kacho-vpc/tests/newman/cases`,
  `kacho-compute/…`, `kacho-iam/…`, `kacho-nlb/…`), НЕ в kacho-deploy. SEC-F ссылается на
  реальные харнессы по их месту жительства (§«Тест-харнессы»).
- **Helm-template-assertion — НОВАЯ инфра**, не «прецедент S7.1». В kacho-deploy `tests/` —
  только `conformance/{oidc,fido}`. Manifest-тесты строятся с нуля выбранным инструментом
  (`yq`/`grep` поверх `helm template`; опционально `helm-unittest`) — презентуются как новые.
- **NLB канонически `kacho-nlb`** (Makefile `reload-svc-nlb`, `DEPLOY_NAME=kacho-nlb`).
  `spire-registration/kacho-loadbalancer.yaml` — legacy-имя, **выровнять** на `kacho-nlb`
  (часть SEC-F: переименовать registration-entry + SA, single-source `<svc>→spiffe-id`).
- **Labels — `app.kubernetes.io/name|component`** (прецедент: `kacho-iam` chart уже несёт
  `networkpolicy-audit.yaml` c `podSelector.matchLabels.app.kubernetes.io/name: …`). НЕ `app=<svc>`.
- **`kacho-selfsigned` ClusterIssuer** ссылается в `values.dev.yaml:713` (annotation
  `cert-manager.io/cluster-issuer: kacho-selfsigned`), но **НЕ определён** в cert-manager-config
  (там только `letsencrypt-prod`/`letsencrypt-staging`). SEC-F **переиспользует**
  `kacho-selfsigned` как bootstrap-root (а заодно фиксирует его недостающее определение), а не
  плодит второй overlapping self-signed issuer (§4.1.6).
- **Namespace стенда — `kacho`** (Makefile `dev-up … -n kacho`), но spire-registration
  фиксирует `ns/kacho-system` в SPIFFE-id. Расхождение разрешается в §«Разрешение SPIFFE-коллизии».

> **Границы (out of scope для SEC-F):**
> - Go/proto/SQL-код mTLS-транспорта (SEC-B corelib), FGA-proxy RPC (SEC-A/C), removal прямого
>   FGA-клиента (SEC-D), api-gateway backend-dial (SEC-E) — здесь только потребляются.
> - `kacho-vpc-operator` + kube-ovn на mTLS — **SEC-G** (зависит от F). SEC-F готовит CA и
>   профиль, операторное ребро включается в G.
> - Включение SPIRE-subchart'ов (`spire-server`/`spire-agent`/`spiffe-csi-driver`) — НЕ в SEC-F.
>   SEC-F даёт совместимый по формату cert-manager-string-SAN при выключенном SPIRE (dev).
> - Публичный external TLS (`letsencrypt-*`, `kacho-wildcard-tls`) — **не трогается**;
>   internal CA — отдельный issuer, отдельные certs, отдельные secret'ы (аддитивно).
> - JWT-флоу — не трогается (требование #7); URI-SAN client-cert — identity *модуля*,
>   ортогонален `x-kacho-principal-*` пользователя (инвариант I2 эпика).
> - Определение ReBAC-tuples SA и proto-опции `<exempt>` для FGA-proxy RPC — **SEC-A/C**
>   (здесь только эмпирически валидируются e2e под узким SA).

## Разрешение SPIFFE-коллизии (центральный identity-контракт — закрывает v1 критику #1)

Существующий SPIRE-каркас уже фиксирует формат `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-<svc>`
(trustDomain=`kacho.cloud`). Cert-manager-выданный client-cert ОБЯЗАН использовать **этот же формат**:

- **Канонический URI-SAN client-cert** = `spiffe://kacho.cloud/ns/<ns>/sa/kacho-<svc>`, где
  `<ns>` — namespace, в котором реально крутится под, а `<svc>` — каноническое имя сервиса
  (`api-gateway`, `iam`, `vpc`, `compute`, `nlb`; полная строка-SAN — `…/sa/kacho-nlb` и т.д.).
- **Namespace-выравнивание (часть SEC-F).** Сегодня стенд `kacho` (Makefile), а spire-registration —
  `ns/kacho-system`. SEC-F фиксирует **один** `<ns>` как single-source в values
  (`spiffe.namespace`) и использует его И в cert-manager-SAN, И при выравнивании
  spire-registration-entries. Дефолт — namespace стенда (`kacho`); если решение «оставить
  `kacho-system» для будущего SPIRE» — registration-entries и dev-namespace выравниваются на него.
  Любой из вариантов допустим, но он **один** — коллизия снимается, не консервируется.
- **Сосуществование с SPIRE.** В dev SPIRE-subchart'ы выключены (`enabled:false`), identity
  выдаётся cert-manager-string-SAN; IAM (SEC-C) читает URI-SAN как непрозрачный identity-string
  → mapping на SA. При будущем включении SPIRE формат идентичен → миграция identity НЕ нужна.
- **NLB-выравнивание (§4.1.6).** `spire-registration/kacho-loadbalancer.yaml` переименовывается
  на `kacho-nlb` (SAN `…/sa/kacho-nlb`); values-таблица `<svc>→spiffe-id` — единый источник для
  cert-manager-SAN, IAM SA-mapping (SEC-C) и spire-registration.

> **Почему string-SAN сейчас допустим (design-review N4 / §4.1.4):** SPIRE-subchart'ы в dev
> выключены, identity нужна для mTLS уже сейчас; cert-manager проставляет URI-SAN в SPIRE-совместимом
> формате как непрозрачную строку. SPIRE-инфра — позже, без смены identity-контракта.

## Тест-харнессы (закрывает v1 критику #2, #3 — ground-truth §4.1.5)

| Что | Где живёт | Команда | Тип |
|---|---|---|---|
| Стенд-смоук (поднятие, секреты, ingress) | `kacho-deploy/e2e/0.1/*.sh` | `make e2e-test` | bash-смоук (НЕ newman) |
| CRUD-регрессия vpc | `kacho-vpc/tests/newman/cases` | newman против REST api-gateway | newman (сервисный репо) |
| CRUD-регрессия compute | `kacho-compute/tests/newman/cases` | newman | newman (сервисный репо) |
| CRUD-регрессия iam | `kacho-iam/tests/newman/cases` | newman | newman (сервисный репо) |
| CRUD-регрессия nlb | `kacho-nlb/tests/newman/cases` | newman | newman (сервисный репо) |
| Manifest/template-assertion | `kacho-deploy/tests/helm/` (**НОВАЯ** инфра) | `yq`/`grep` поверх `helm template` (опц. `helm-unittest`) | helm-assertion (новый) |
| Cert-инспекция SAN | `kacho-deploy/tests/helm/` (**НОВАЯ**) | bash + `openssl x509` поверх выпущенных secret'ов | runtime-assertion (новый) |

«Полный newman-прогон против mTLS-стенда» = поднять стенд (`make dev-up MTLS=on`), затем
прогнать newman-наборы **сервисных репо** (vpc/compute/iam/nlb) против REST api-gateway этого
стенда. `make e2e-test` (deploy) валидирует только bash-смоук стенда — он расширяется кейсом
«mTLS-стенд поднялся, service→service handshake успешен».

## Трассировка сценариев → требованиям эпика

| Сценарий | Покрывает требование/решение эпика |
|---|---|
| SEC-F-01 internal CA ClusterIssuer (переиспользует `kacho-selfsigned` root) | #2, §3.2, §4.1.6, v1#5 |
| SEC-F-02 per-svc Certificate ×2 раздельные secret'ы | #5, §3.2 |
| SEC-F-03 server-cert SAN = service DNS | #5, §3.2 |
| SEC-F-04 client-cert URI-SAN = SPIRE-формат `spiffe://kacho.cloud/ns/<ns>/sa/kacho-<svc>` | #4, §3.3, §4.1.4, v1#1 |
| SEC-F-05 helm `mtls.enabled=false` → текущий dev | #1, DoD §5, I7 (opt-in, нулевая регрессия) |
| SEC-F-06 helm `mtls.enabled=true` → mTLS-профиль поднимается | #1, #5, DoD §5 |
| SEC-F-07 per-edge enable | I7, §6.5 (per-edge feature-flag, rollback) |
| SEC-F-08 mTLS-стенд: сервисный newman + deploy-смоук зелёные | DoD §5, #8, §4.1.5, v1#2 |
| SEC-F-09 SA-seed wiring: под монтирует свой client-cert, identity=его SA | #4, §3.3, §4.1.6, v1#4/#6 |
| SEC-F-10 ReBAC-least-priv валидация (e2e под узким SA, нет over-grant) | #4, I6, §4.1.1/§4.1.2 |
| SEC-F-11 cert renew / restart-on-rotate, Operations не теряются | §3.2, §6.2, N3 |
| SEC-F-12 NetworkPolicy openfga←iam (после SEC-D) | #6, §3.1, v1#4 (label-format) |
| SEC-F-13 mTLS handshake mismatch → fail-closed Unavailable | §6.7, I7 |
| SEC-F-14 helm-lint / template / dependency на оба профиля | DoD (артефакты валидны), §4.1.5 |

---

## SEC-F-01: internal CA ClusterIssuer существует; bootstrap через `kacho-selfsigned`

**ID:** SEC-F-01

**Given** ветка SEC-F и umbrella-чарт `helm/umbrella` с расширенным subchart
  `cert-manager-config` (новый template-блок internal-CA)
**And** в cert-manager-config **определяется недостающий** self-signed root
  `ClusterIssuer/kacho-selfsigned` (тип `selfSigned`) — он уже ссылается в
  `values.dev.yaml` (annotation `cert-manager.io/cluster-issuer: kacho-selfsigned`), но не
  определён; SEC-F закрывает этот пробел и **переиспользует** его как bootstrap-root (§4.1.6),
  НЕ создаёт второй overlapping self-signed issuer
**And** values содержат `certManager.internalCA` блок (selfSigned root → CA-Issuer):
  - `internalCA.enabled = true`
  - `internalCA.rootIssuerName = "kacho-selfsigned"` (переиспользуемый selfSigned)
  - `internalCA.clusterIssuerName = "kacho-internal-ca"`
  - тип целевого issuer — `ca` (ссылается на secret CA-сертификата), **не** `acme`

**When** `helm template kacho-umbrella ./helm/umbrella -f values.prod.yaml` рендерится
  и манифесты применяются на kind-кластер с установленным cert-manager

**Then** существует bootstrap-цепочка: `ClusterIssuer/kacho-selfsigned` (selfSigned) →
  `Certificate` (CA root, `isCA: true`, `issuerRef: kacho-selfsigned`) → secret CA →
  `ClusterIssuer/kacho-internal-ca` типа `ca` (`spec.ca.secretName`, **не** `spec.acme`)
**And** `kubectl get clusterissuer kacho-internal-ca -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` == `"True"`
**And** существует ровно ОДИН self-signed issuer (`kacho-selfsigned`) — не два overlapping
**And** существующие `ClusterIssuer/letsencrypt-prod` / `letsencrypt-staging` и
  `kacho-wildcard-tls` **не изменены** (internal CA — отдельная сущность, не подменяет ACME).

---

## SEC-F-02: per-service Certificate ×2 в раздельных secret'ах

**ID:** SEC-F-02

**Given** ветка SEC-F; values `certManager.internalCA.services` — список внутренних
  компонентов с каноническими именами: `api-gateway`, `kacho-iam`, `kacho-vpc`,
  `kacho-compute`, `kacho-nlb` (`kacho-nlb`, НЕ legacy `kacho-loadbalancer`; vpc-operator — SEC-G)
**And** для каждого сервиса заданы два логических cert: `server` и `client`

**When** `helm template` рендерится для prod-профиля и применяется

**Then** для каждого сервиса `<svc>` существуют **два** `Certificate`:
  - `<svc>-server-tls` → `secretName: <svc>-server-tls`, `issuerRef: kacho-internal-ca`
  - `<svc>-client-tls` → `secretName: <svc>-client-tls`, `issuerRef: kacho-internal-ca`
**And** server-cert и client-cert лежат в **разных** secret'ах (раздельные cert — требование #5):
  `kubectl get secret <svc>-server-tls <svc>-client-tls` — оба существуют, разные `tls.crt`
**And** оба `Certificate` достигают `Ready=True` (выпущены internal CA)
**And** `usages` server-cert содержит `server auth` (+ `client auth` допустимо как backstop),
  client-cert — `client auth`
**And** `privateKey.rotationPolicy: Always` (ротация ключа при renew, §3.2).

---

## SEC-F-03: server-cert SAN = service DNS-имя

**ID:** SEC-F-03

**Given** SEC-F-02 (server-cert выпущены); `<ns>` = single-source `spiffe.namespace` (§«коллизия»)

**When** инспектируется server-cert каждого сервиса
  (`kubectl get secret <svc>-server-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text`)

**Then** SAN server-cert (DNS-SAN) содержит `<svc>.<ns>.svc.cluster.local`
  (и допустимо короткие формы `<svc>.<ns>.svc`, `<svc>.<ns>`) — то, по чему клиент верифицирует
  `server_name` при mTLS-дайле (SEC-B `TLSClient.server_name`)
**And** SAN server-cert **не** содержит URI-SAN `spiffe://…` (это identity-роль client-cert, не server).

---

## SEC-F-04: client-cert URI-SAN = SPIRE-совместимый identity модуля

**ID:** SEC-F-04

**Given** SEC-F-02 (client-cert выпущены)
**And** values-таблица `internalCA.services.<svc>.spiffeId` — единый источник истины,
  потребляемый cert-manager-SAN, IAM SA-mapping (SEC-C) и spire-registration; формат —
  существующий SPIRE: `spiffe://kacho.cloud/ns/<ns>/sa/kacho-<svc>` (§«коллизия», §4.1.4)

**When** инспектируется client-cert каждого сервиса (`openssl x509 -noout -text`)

**Then** SAN client-cert содержит **URI-SAN** `spiffe://kacho.cloud/ns/<ns>/sa/kacho-<svc>`
  (НЕ выдуманный `spiffe://kacho/<sva-id>`; trustDomain=`kacho.cloud` из `spiffe.trustDomain`,
  совпадает с spire-registration) — IAM читает её как непрозрачный identity-string при
  client-cert→SA mapping (SEC-C)
**And** URI-SAN client-cert **совпадает** с `spec.spiffeId` соответствующего
  `spire-registration/kacho-<svc>.yaml` (один формат → при включении SPIRE миграции identity нет;
  для `kacho-nlb` registration-entry выровнен с legacy `kacho-loadbalancer`, §4.1.6)
**And** client-cert каждого сервиса несёт **разный** `spiffe://…/sa/kacho-<svc>` (персональная
  identity на компонент — требование #4)
**And** trustDomain в URI-SAN == `spiffe.trustDomain` (`kacho.cloud`), не хардкод.

---

## SEC-F-05: `mtls.enabled=false` (default) → стенд ведёт себя как текущий dev (нулевая регрессия)

**ID:** SEC-F-05

**Given** ветка SEC-F мёржится в `main`; `values.dev.yaml` — `mtls.enabled: false` (default)
**And** SEC-B..E уже в `main` (corelib/services/gateway понимают `mtls.enabled`, при false →
  `insecure.NewCredentials()`)

**When** `make dev-up` на свежем kind-кластере (профиль dev, mTLS выключен, namespace `kacho`)

**Then** все `kacho-*` поды достигают `Ready` в стандартный таймаут (`helm … --wait --timeout 10m`)
**And** service→service общение — insecure (текущее поведение); поды **не** монтируют
  client/server cert-secret'ы (либо монтируют, но creds не используются — `enabled=false`)
**And** internal CA `ClusterIssuer` и per-svc `Certificate` в dev-профиле **не создаются**
  (или создаются, но не потребляются — допустимо; критерий: dev работает без них)
**And** `make e2e-test` (bash-смоук `e2e/0.1/*.sh`) — **полностью зелёный** (E1/E5/E6…),
  ни один кейс не падает
**And** регрессионный **newman сервисных репо** (vpc/compute/iam/nlb против REST api-gateway
  этого стенда) — полностью зелёный, ни один кейс не падает и не пропущен
  (требование #1 «не ломает dev»; DoD-эпика §5).

---

## SEC-F-06: `mtls.enabled=true` (prod-профиль) → mTLS-стенд поднимается

**ID:** SEC-F-06

**Given** профиль `values.mtls.yaml` (overlay поверх dev) или `values.prod.yaml`-секция с
  `mtls.enabled: true` и `mtls.edges.*` все включены (см. SEC-F-07)
**And** cert-manager установлен; SEC-C seed'ит ReBAC-SA-tuples и client-cert→SA mapping

**When** `make dev-up MTLS=on` (helm-профиль с `-f values.dev.yaml -f values.mtls.yaml`)
  на свежем kind-кластере (namespace `kacho`)

**Then** internal CA `ClusterIssuer` + все per-svc `Certificate` ×2 выпускаются (`Ready=True`)
  до старта rollout сервисов (зависимость порядка установки соблюдена)
**And** каждый сервисный под монтирует свой `<svc>-server-tls` (как server) и
  `<svc>-client-tls` (как client) в ожидаемые mount-path, переданные в config
  (`KACHO_<DOMAIN>_TLS_SERVER_*` / `KACHO_<DOMAIN>_TLS_CLIENT_*`)
**And** все `kacho-*` поды достигают `Ready` в таймаут (`helm upgrade --install --wait` не падает)
**And** service→service хендшейки успешны (no `Unavailable`/handshake-error в логах
  на установившемся стенде): smoke-проба `OperationService.Get`/любой `List` через api-gateway → 200.

---

## SEC-F-07: per-edge enable — каждое ребро включается независимым флагом

**ID:** SEC-F-07

**Given** values-структура `mtls.edges` с отдельными булями на ребро (решение I7, §6.5):
  - `mtls.edges.gateway_to_vpc`
  - `mtls.edges.gateway_to_compute`
  - `mtls.edges.gateway_to_iam`
  - `mtls.edges.gateway_to_nlb`
  - `mtls.edges.vpc_to_iam`
  - `mtls.edges.compute_to_iam`
  - `mtls.edges.nlb_to_iam`
  - (vpc↔compute заполняется в SEC-D; operator→vpc — в SEC-G)

**When** `helm template` рендерится с профилем, где включено только подмножество рёбер
  (напр. `gateway_to_iam=true`, остальные false)

**Then** в рендере у соответствующего клиента/сервера выставлены только включённые
  edge-флаги в env/config (mismatch-комбинация не приводит к ошибке рендера)
**And** включённое ребро прокидывает client-cert+server-CA на dial-стороне и server-cert+client-CA
  на listen-стороне; выключенное ребро — insecure на этом ребре
**And** при асимметрии (одна сторона ребра mTLS, другая insecure) ожидаемый рантайм-результат —
  `Unavailable` на этом ребре (детектируется per-edge e2e, см. SEC-F-13) — а не молчаливый bypass.

---

## SEC-F-08: mTLS-стенд — сервисный newman + deploy-смоук зелёные

**ID:** SEC-F-08

**Given** SEC-F-06 (mTLS-стенд поднят `make dev-up MTLS=on`, все рёбра включены)
**And** SA-seed применён (SEC-F-09), ReBAC-least-priv роли активны

**When** против этого стенда прогоняются: (a) `make e2e-test` (deploy bash-смоук `e2e/0.1/*.sh`)
  и (b) регрессионный **newman сервисных репо** (`kacho-vpc/tests/newman` и аналоги
  compute/iam/nlb) против REST api-gateway

**Then** (a) bash-смоук зелёный (стенд поднялся, секреты/ingress на месте, service→service handshake)
**And** (b) весь регрессионный newman зелёный (happy + negative по vpc/compute/iam/nlb):
  каждый публичный CRUD-флоу (Create→poll Operation→Get) проходит сквозь mTLS service→service
**And** ни один кейс не падает из-за `PermissionDenied` (ReBAC-least-priv роли покрывают
  легитимные вызовы — иначе finding SEC-F-10)
**And** ни один кейс не падает из-за `Unavailable` (все рёбра mTLS-согласованы)
**And** результат **идентичен** запуску тех же newman-наборов на insecure-профиле (mTLS
  прозрачен для публичного контракта — требование #8 «контракты не меняются»).

---

## SEC-F-09: SA-seed wiring — под монтирует свой client-cert, его identity = его SA

**ID:** SEC-F-09

**Given** SEC-C seed'ит в kacho-iam детерминированные ServiceAccount (`sva`-id) с
  ReBAC-least-priv tuples на каждый внутренний компонент (§3.3, §4.1.2)
**And** values-таблица `<svc>→spiffeId` (`spiffe://kacho.cloud/ns/<ns>/sa/kacho-<svc>`) —
  единый источник истины, потребляемый cert-manager `Certificate` (SAN, SEC-F-04),
  IAM SA-mapping (SEC-C) и spire-registration (выровнен NLB-entry, §4.1.6)

**When** `make dev-up MTLS=on` поднимает стенд

**Then** под каждого сервиса `<svc>` монтирует **только свой** `<svc>-client-tls` secret
  (не чужой). Селектор пода — каноническая label (§4.1.6, прецедент `networkpolicy-audit.yaml`):
  `kubectl get pod -l app.kubernetes.io/name=<svc> -o jsonpath='{.spec.volumes}'` ссылается на `<svc>-client-tls`
  (НЕ `app=<svc>` — таких лейблов в репо нет)
**And** при service→service вызове IAM сопоставляет предъявленный client-cert URI-SAN
  (`spiffe://kacho.cloud/ns/<ns>/sa/kacho-<svc>`) с seed'нутым SA → caller-identity = этот SA (SEC-C)
**And** аудит-лог IAM (`Check`/`RegisterResource`) фиксирует **оба** слоя: cert-identity модуля
  (URI-SAN) и principal пользователя (`x-kacho-principal-*`), не конфликтуя (I2)
**And** ни один внутренний компонент не делит client-cert/SA с другим (1 под-роль = 1 SA = 1 client-cert).

---

## SEC-F-10: ReBAC-least-priv валидация — e2e под узким SA зелёный, нет over-grant

**ID:** SEC-F-10

**Given** mTLS-стенд (SEC-F-06) с ReBAC-least-priv SA. Модель — НЕ плоские permission-строки,
  а relation-tuples на scope-объекты (§4.1.2). Канонические permission-строки и required_relation
  — эмпирически из `kacho-proto/gen/permission_catalog.json` (§4.1.3, validated эмпирически из каталога):
  - `kacho-compute` SA должен мочь: `vpc.subnets.get` (rel `viewer`, scope `vpc_subnet`),
    `vpc.security_groups.get` (`viewer`/`vpc_security_group`), `vpc.addresses.get` (`viewer`/`vpc_address`)
    и `vpc.addresseses.list` (`viewer`/`project`) для IPAM, `iam.projects.get` (`viewer`/`project`)
  - `kacho-vpc` SA должен мочь: `compute.zones.get` (`viewer`, scope `cluster`),
    `iam.projects.get` (`viewer`/`project`)
  - FGA-proxy-вызов (`InternalIAMService/RegisterResource`/`UnregisterResource`) НЕ требует
    permission-строки: proto-опция `<exempt>` (как все 7 текущих Internal IAM RPC — в каталоге
    `InternalIAMService/Check`, `WriteCreatorTuple` и др. = `<exempt>`), least-priv энфорсится в
    IAM-handler ReBAC-проверкой relation `fga_writer` на `iam_fgaproxy:system` (§4.1.1, SEC-A/C)
**And** **service→service SA освобождены от `required_acr_min`** (§4.1.2): ACR-floor — только
  user-token-флоу; у SA аутентификация = mTLS client-cert, MFA нет. `<exempt>`-RPC и так без
  `required_acr_min` (каталог)
**And** production-mode authz активен (anonymous fail-closed)

**When** прогон полного newman e2e сервиса (из его сервисного репо) под его узким SA (требование I6)

**Then** **под-достаточность:** ни один легитимный сценарий не падает `PermissionDenied`
  (если падает → недостающий relation-tuple в SA → finding, чинится в SEC-C/SEC-D, не в SEC-F)
**And** **нет over-grant:** diff «множество relation-tuples в SA» ⊇ «множество `Check`-вызовов
  (fqn+required_relation+scope-object), наблюдаемых из e2e этого сервиса» НЕ содержит лишних
  элементов; любой tuple в SA, не встречающийся ни в одном Check за прогон — over-grant →
  finding (GitHub Issue + правка seed в SEC-C)
**And** негативная проба: попытка узкого SA на запрещённое ему relation/scope
  (напр. `kacho-vpc` SA → `editor` на `compute_disk` для мутации compute) → `PermissionDenied`
  (роль действительно узкая)
**And** негативная проба FGA-proxy: SA без relation `fga_writer` на `iam_fgaproxy:system` зовёт
  `RegisterResource` → `PermissionDenied` (ReBAC-энфорс §4.1.1)
**And** `make audit-list-filter` (CI-гейт) — зелёный (List-фильтрация под SA не регрессирует).

---

## SEC-F-11: cert renew / restart-on-rotate — Operations не теряются

**ID:** SEC-F-11

**Given** mTLS-стенд; per-svc `Certificate` с коротким `duration`/`renewBefore`
  (тестовый профиль — напр. `duration: 1h`, `renewBefore: 55m` — чтобы renew наступил в прогоне)
**And** in-flight Operation: запущена async-мутация (напр. `POST /vpc/v1/networks`),
  Operation в БД `done=false` (worker читает state из БД, не из памяти — N3)

**When** cert-manager выпускает новый cert (renew) и под перезапускается
  (restart-on-rotate, MVP-стратегия §6.2: reloader/rollout по изменению secret)

**Then** после рестарта реплики Operation **не теряется**: повторный
  `OperationService.Get(<id>)` в итоге даёт `done=true && !error`, ресурс создан
  (worker подхватил state из БД — Operations персистентны, N3)
**And** окно недоступности во время рестарта — unary `Unavailable` на in-flight вызовах;
  клиент ретраит, после Ready — успех (нет потери данных, нет «застрявшей» Operation)
**And** новый cert имеет новый serial/notAfter (renew состоялся), client-cert URI-SAN
  (`spiffe://kacho.cloud/ns/<ns>/sa/kacho-<svc>`) **стабилен** (identity при ротации не меняется →
  SA-mapping не ломается)
**And** существующие хендшейки после ротации валидны под новым cert (issuer тот же internal CA).

---

## SEC-F-12: NetworkPolicy «ingress в openfga только из kacho-iam» (ПОСЛЕ SEC-D)

**ID:** SEC-F-12

**Given** SEC-D смёржен и e2e зелёные: vpc/compute/nlb **больше не ходят в FGA напрямую**
  (grep `openfga` в их `internal/clients/` = 0), а только через `InternalIAMService.RegisterResource`
  (предусловие включения политики — §3.1, иначе окно отказа)
**And** values `networkPolicy.openfgaIngressFromIamOnly.enabled = true`
**And** прецедент NetworkPolicy в репо — `kacho-iam` chart, `templates/networkpolicy-audit.yaml`
  (использует `podSelector.matchLabels.app.kubernetes.io/name` — этот же селектор-стиль применяем)

**When** `helm template` рендерится и `NetworkPolicy` применяется на стенд

**Then** существует `NetworkPolicy`, селектирующая под(ы) openfga
  (`podSelector.matchLabels.app.kubernetes.io/name: openfga`, по факту-чарта), с `policyTypes: [Ingress]`
  и `ingress.from` only `podSelector.matchLabels.app.kubernetes.io/name: kacho-iam`
  на FGA-порт (gRPC/HTTP openfga) — формат лейблов как в `networkpolicy-audit.yaml` (НЕ `app=`)
**And** позитив: `kacho-iam` под достигает openfga (newman-флоу с FGA-tuple — Create ресурса
  через IAM-proxy → owner-tuple применён → per-resource `Check` = ALLOW; пользователь видит ресурс)
**And** негатив: под, эмулирующий vpc/compute (или прямой `kubectl exec` из не-iam пода),
  **не** может открыть соединение к openfga (connection refused/timeout) — FGA недостижим вне IAM
  даже при mTLS-компрометации модуля (требование #6, defense-in-depth)
**And** при `networkPolicy.openfgaIngressFromIamOnly.enabled = false` (или до SEC-D-готовности)
  политика не создаётся — стенд работает как до изоляции (нет окна отказа).

---

## SEC-F-13: mTLS mismatch / handshake fail → fail-closed `Unavailable` (per-edge)

**ID:** SEC-F-13

**Given** mTLS-стенд; намеренно созданная асимметрия одного ребра
  (напр. `mtls.edges.gateway_to_vpc=true` на gateway, но vpc-под поднят без server-cert —
  или предъявлен client-cert, выпущенный НЕ internal CA `kacho-internal-ca`)

**When** клиент совершает запрос через это ребро (api-gateway → vpc)

**Then** ребро fail-closed: вызов возвращает `Unavailable` (mTLS handshake fail / cert не
  верифицируется CA → не молчаливый insecure-fallback) — решение §6.7
**And** ошибка локализуется на конкретное ребро (per-edge e2e детектирует именно его, I7);
  остальные согласованные рёбра продолжают работать
**And** для мутаций это означает: Operation не создаётся / возвращается `Unavailable` синхронно
  (fail-closed для мутаций, cross-domain политика data-integrity) — не «тихо прошло без mTLS».

---

## SEC-F-14: helm-артефакты валидны на обоих профилях

**ID:** SEC-F-14

**Given** ветка SEC-F с новыми/изменёнными yaml (selfSigned root + internal-CA Issuer,
  Certificate, NetworkPolicy, values, service-чарты с cert-mount + per-edge env)

**When** прогоняются `helm dep update` + `helm lint` + `helm template` для **обоих** профилей
  (`values.dev.yaml` mTLS-off и `values.dev.yaml + values.mtls.yaml` mTLS-on)

**Then** `helm lint` — 0 ошибок на обоих профилях
**And** `helm template … -f values.dev.yaml` НЕ рендерит internal-CA Certificate/NetworkPolicy
  (либо рендерит, но не монтирует — критерий SEC-F-05)
**And** `helm template … -f values.dev.yaml -f values.mtls.yaml` рендерит: `ClusterIssuer/kacho-selfsigned`
  (selfSigned, ровно один) + CA-root `Certificate` + `ClusterIssuer/kacho-internal-ca` (type `ca`),
  по 2 `Certificate` на каждый из 5 сервисов (= 10), 1 openfga `NetworkPolicy`
  (селектор `app.kubernetes.io/name`), cert-mount на каждый под
**And** манифесты проходят `kubeconform`/`kubectl apply --dry-run=server` (валидные K8s-объекты,
  cert-manager CRD-схема соблюдена)
**And** публичный `letsencrypt-*` / `kacho-wildcard-tls` присутствует без изменений в обоих рендерах
  (internal CA — аддитивен, не подменяет external TLS).

---

## Definition of Done (SEC-F)

- [ ] Ветка `KAC-<N>` в `kacho-deploy` от `main`; KAC-trail в vault (`obsidian/kacho/KAC/KAC-<N>.md`).
- [ ] **Артефакты yaml/values:**
  - [ ] internal CA: **переиспользуемый** selfSigned root `ClusterIssuer/kacho-selfsigned`
        (закрыть недостающее определение, §4.1.6) → CA-root `Certificate` → `ClusterIssuer/kacho-internal-ca`
        (type `ca`), отдельно от `letsencrypt-*`. Ровно один self-signed issuer.
  - [ ] per-svc `Certificate` ×2 (`<svc>-server-tls` SAN=`<svc>.<ns>.svc.cluster.local`,
        `<svc>-client-tls` URI-SAN=`spiffe://kacho.cloud/ns/<ns>/sa/kacho-<svc>` — SPIRE-формат),
        раздельные secret'ы, для `api-gateway/kacho-iam/kacho-vpc/kacho-compute/kacho-nlb`.
  - [ ] helm-values `mtls.enabled` (default false) + `mtls.edges.*` (per-edge, incl. `gateway_to_nlb`,
        `nlb_to_iam`) + cert-mount на сервисные чарты + env (`KACHO_<DOMAIN>_TLS_*`).
  - [ ] values-таблица `<svc>→spiffeId` (`spiffe.namespace` single-source) — единый источник для
        cert-SAN, IAM SA-mapping и spire-registration. **Выровнять** `spire-registration/kacho-loadbalancer.yaml`
        на `kacho-nlb` (§4.1.6) и namespace (`ns/<ns>`, снять `kacho` vs `kacho-system` расхождение).
  - [ ] `NetworkPolicy` openfga-ingress-from-iam-only (флаг `networkPolicy.openfgaIngressFromIamOnly.enabled`),
        селекторы `app.kubernetes.io/name` (стиль `networkpolicy-audit.yaml`, §4.1.6).
- [ ] **TDD (RED→GREEN), тесты в том же PR (харнессы — §«Тест-харнессы»):**
  - [ ] **Manifest/template-тесты — НОВАЯ инфра** `kacho-deploy/tests/helm/` (`yq`/`grep` поверх
        `helm template`, опц. `helm-unittest`; НЕ «прецедент S7.1» — его нет): ассерты на наличие
        Issuer-цепочки/Certificate/NetworkPolicy в mTLS-профиле и их **отсутствие** в dev-профиле
        (SEC-F-01/02/05/14). RED — до добавления шаблонов.
  - [ ] **cert-инспекция-тест** (НОВАЯ, `tests/helm/`): bash+`openssl x509` извлекает SAN из
        выпущенных secret'ов — server-SAN=DNS, client-URI-SAN=`spiffe://kacho.cloud/ns/<ns>/sa/kacho-<svc>`,
        совпадает со spire-registration `spiffeId`, разные secret'ы (SEC-F-03/04). RED — до internal-CA Certificate.
  - [ ] **e2e dev-profile (mTLS-off):** `make e2e-test` (deploy bash-смоук) + newman сервисных
        репо (vpc/compute/iam/nlb) — зелёные, нулевая регрессия (SEC-F-05).
  - [ ] **e2e mTLS-profile:** `make dev-up MTLS=on` → `make e2e-test` (deploy bash-смоук, расширен
        smoke service→service handshake) + newman сервисных репо — зелёные (SEC-F-06/08).
  - [ ] **ReBAC-least-priv e2e + over-grant diff:** прогон newman сервисного репо под узким SA,
        сбор `Check`-вызовов (fqn+relation+scope), diff SA-tuples⊇Check; негативная проба
        запрещённого relation/scope и FGA-proxy без `fga_writer` → `PermissionDenied` (SEC-F-10).
        Permission-строки/relation — из `permission_catalog.json` (validated эмпирически из каталога).
  - [ ] **renew/rotate-тест:** короткий duration cert, in-flight Operation, restart-on-rotate →
        Operation `done=true`, URI-SAN стабилен (SEC-F-11).
  - [ ] **NetworkPolicy isolation-тест:** позитив iam→openfga ALLOW; негатив не-iam→openfga DENY,
        селектор `app.kubernetes.io/name` (SEC-F-12). Гейт: только после SEC-D зелёного.
  - [ ] **per-edge mismatch-тест:** асимметрия ребра → `Unavailable`, локализация на ребро (SEC-F-07/13).
- [ ] `helm lint` + `helm template` + `kubectl apply --dry-run=server`/`kubeconform` — зелёные на обоих профилях (SEC-F-14).
- [ ] `make audit-list-filter` зелёный под least-priv SA (SEC-F-10).
- [ ] **Зависимости-гейты соблюдены:** SEC-C/D/E в `main` до включения mTLS-профиля; NetworkPolicy
      openfga — только после SEC-D зелёного (§3.1).
- [ ] PR `PRO-Robotech/kacho-deploy#<N>` открыт; CI зелёный; PR-URL в KAC-тикет (комментарий) + в KAC-trail.
- [ ] vault-trail: `edges/` (gateway→vpc/compute/iam/nlb, vpc→iam, compute→iam, nlb→iam — отметка
      «mTLS opt-in, internal CA, per-edge flag, SPIRE-формат URI-SAN») + KAC-trail обновлены.
- [ ] KAC-тикет → `In Progress` при PR-open → `Test` → `Done` после merge со всеми артефактами
      (PR-URL, лог RED→GREEN, e2e-лог обоих профилей).

## Зависимости и порядок (внутри эпика)

- **Вход:** SEC-C (IAM FGA-proxy `RegisterResource`/`Unregister` (`<exempt>`+ReBAC `fga_writer`)
  + ReBAC-least-priv SA-seed + client-cert→SA mapping), SEC-D (vpc/compute/nlb убрали прямой FGA →
  outbox-intent + mTLS), SEC-E (api-gateway mTLS backend-dial) — все в `main`.
- **Выход → SEC-G:** internal CA `ClusterIssuer` + per-edge mTLS-профиль + SPIRE-совместимый
  URI-SAN-контракт переиспользуются для `kacho-vpc-operator` (отдельный client-cert + own
  least-priv SA) и kube-ovn — стенд целиком на mTLS.
- **Гейт NetworkPolicy:** включается ТОЛЬКО после SEC-D-готовности и зелёного e2e (§3.1 — иначе
  окно отказа FGA).
