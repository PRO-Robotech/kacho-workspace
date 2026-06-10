# [EPIC] SEC — mTLS + IAM-fronted authz + least-privilege service identities

**Статус:** pre-acceptance design input (НЕ план к исполнению; код — только после APPROVED
Given-When-Then per-подфаза, ban #1). **Дата:** 2026-06-11. **Тип:** epic (cross-repo).

> Это проектный вход. Перед любым кодом: per-подфаза `acceptance-author` →
> `acceptance-reviewer` (✅ APPROVED) + `system-design-reviewer` на этот документ.

## 1. Цель (из требований заказчика)

1. Работа всех компонентов — на **mTLS** как **opt-in расширение** (не ломает dev).
2. PKI — через **cert-manager** (стенд в Kubernetes).
3. Каждый внешний запрос **аутентифицируется (JWT) и авторизуется (IAM)**; внутренние
   компоненты общаются **напрямую** (service→service), но под mTLS.
4. Внутренние компоненты имеют **персональные service-identity** с ролями по
   **принципу наименьших привилегий**.
5. Стенд собирается целиком — **сервисы + операторы (kacho-vpc-operator) + kube-ovn** —
   и все коммуникации по mTLS; **два раздельных сертификата: client и server**.
6. Модули **не ходят в FGA напрямую** — только через **IAM**; FGA спрятан за IAM и
   закрыт ролёвкой (пользователь/модуль не может «прощупывать» модель доступов — только
   решения в рамках своей роли, least-privilege).
7. **JWT-аутентификация сохраняется** (Hydra/Zitadel issuer, JWKS — без изменений).
8. **Контракты не меняются**, кроме работы с FGA (Internal-only FGA-proxy RPC — допустимо).

## 2. Точка отсчёта (факты разведки)

- **JWT**: валидируется в `kacho-api-gateway/internal/middleware/authz.go` (Hydra JWKS,
  dev HMAC); principal → metadata `x-kacho-principal-*`. ✅ требование #7 уже на месте.
- **Authz-gate**: `InternalIAMService.Check` (kacho-proto iam/v1) реализован в
  `kacho-iam/internal/service/authorize_service.go`; зовут api-gateway + vpc/compute/nlb
  (corelib authz-interceptor). ✅ требование #3 частично есть.
- **FGA прямой доступ** (нарушение #6): `kacho-vpc/internal/clients/openfga_write_client.go`
  и `kacho-compute/.../openfga_write_client.go` пишут hierarchy-tuple напрямую в FGA при
  Create (hot-path). `kacho-iam` — полный FGA-доступ (это норма, IAM — владелец FGA).
  api-gateway — НЕ прямой (через IAM.Check). **Чинить: vpc/compute.**
- **mTLS**: НЕ реализован. `corelib/grpcsrv`+`grpcclient` — `insecure.NewCredentials()`.
  Конфиг-заглушки: compute (bool-флаги `*_TLS` без cert-path), vpc (`TLSClient{enable,
  server-name,ca-files}` без client-cert). cert-manager-config subchart готов (Issuer +
  Certificate, usages server+client). vpc-operator webhook уже на cert-manager.
- **Стенд**: umbrella helm (api-gateway/iam/vpc/compute/nlb/ui + pg-* + openfga/kratos/
  hydra), argo-apps (multus, kube-ovn, vpc-operator). Все service→service — insecure.

## 3. Архитектурные решения (ключевые, неочевидные)

### 3.1 FGA за IAM (требование #6, #8) — transactional-outbox (после design-review)

> **C1 (design-review).** Сегодня vpc/compute пишут owner-tuple `fgawrite.Emit(...)` ПОСЛЕ
> `commit` ресурса, best-effort, ошибка проглатывается (`network/create.go` после
> `w.Commit`; `instance.go` после `repo.Insert`; `fgawrite.go` «Failures are logged, never
> returned»). Это dual-write-баг: при сбое FGA owner-tuple теряется → per-resource Check =
> DENY → пользователь создал ресурс и не видит его. Эпик ОБЯЗАН это исправить, а не пронести
> через IAM-hop. Образец правильного паттерна уже есть в IAM: `kacho-iam` пишет
> `kacho_iam.fga_outbox` в той же writer-tx, что и мутацию (`fga_applier.go` + corelib
> `outbox/drainer`, идемпотентная классификация already_exists→ok / validation→poison / 5xx→retry).

- **Новые Internal-only RPC** в `InternalIAMService` (kacho-proto, iam/v1) — НЕ публичный
  ресурсный контракт, #8 не нарушается: `RegisterResource`/`UnregisterResource` (owner-
  hierarchy tuple write/delete). **Идемпотентны как контракт** (повтор owner-tuple → gRPC
  `OK`, НЕ `AlreadyExists`; delete отсутствующего → `OK`) — от этого зависит retry-цепочка.
  Регистрируются ТОЛЬКО на internal mux :9091 (`api-gateway-registrar`), закрыты authz-
  ролёвкой: вызвать может только service-account модуля с permission `iam.fgaproxy.write`.
- **vpc/compute (Вариант A — outbox-relay, выбран design-review):** `openfga_write_client.go`
  + `fgawrite.Emit` best-effort удаляются. Намерение «register owner-tuple» пишется строкой
  в outbox **в той же writer-tx, что и Insert ресурса** (один commit — no dual-write).
  Отдельный drainer (corelib `outbox/drainer`, под `pg_advisory_xact_lock` — одна реплика)
  вызывает `InternalIAMService.RegisterResource` по mTLS. IAM применяет tuple (через свой
  `fga_outbox`+drainer). IAM `Unavailable` → drainer retry с backoff, **tuple не теряется**,
  Operation не падает. Eventual-consistent: окно DENY до применения tuple конечно и
  гарантированно закрывается (сейчас — навсегда). Симметрично: Delete ресурса →
  Unregister-intent в outbox.
- **Миграция** vpc и compute: таблица/переиспользование outbox под FGA-register-intent
  (через `db-architect-reviewer` + `migration-writer`) — входит в SEC-D.
- **FGA сетевая изоляция**: NetworkPolicy «ingress в openfga только из kacho-iam pod» —
  включается в SEC-F ТОЛЬКО ПОСЛЕ того, как vpc/compute переключены на IAM-proxy и e2e
  зелёные (иначе окно отказа). Даже при mTLS-компрометации модуля FGA недостижим вне IAM.
- **Прод-баг N5**: текущий best-effort dual-write — GitHub Issue (`bug`+`tech-debt`) в
  kacho-vpc и kacho-compute, привязать к эпику, закрывается в SEC-D.

### 3.2 mTLS как opt-in (требования #1, #2, #5)
- **corelib**: `grpcsrv` — TLS server creds (server-cert + client-CA, `RequireAndVerifyClientCert`);
  `grpcclient` — TLS client creds (client-cert + server-CA + server-name). Единая
  config-структура `TLSServer{enable,cert_file,key_file,client_ca_files}` +
  `TLSClient{enable,cert_file,key_file,ca_files,server_name}`. `enable=false` → текущий
  insecure (dev backward-compat).
- **Два раздельных сертификата** (#5): каждый под — отдельный **server-cert** (SAN =
  `<svc>.kacho.svc...`) и отдельный **client-cert** (SPIFFE-like SAN/CN = identity модуля,
  используется и для service-identity в IAM, см. 3.3). Разные secret'ы, разные Certificate.
- **cert-manager**: internal CA `ClusterIssuer` (CA-типа, не Let's Encrypt — это для
  cluster-internal mTLS); per-service `Certificate` ×2 (server, client). Renew/rotate —
  cert-manager. Поды монтируют secret, hot-reload по file-watch (или restart-on-rotate v1).
- **api-gateway** (#3): external TLS на ingress (JWT — без изменений); backend dial —
  переключить на mTLS client-cert. Internal :9091 — mTLS обязателен в production-mode.

### 3.3 Персональные service-identity + least-privilege (требование #4)
- Каждый внутренний компонент = **ServiceAccount в kacho-iam** (тип `service_account`,
  `sva<...>`) с **минимальной ролью**: только permissions, нужные его задачам. Примеры:
  - `kacho-compute` SA: `vpc.subnets.get`, `vpc.securityGroups.get`, `vpc.addresses.*`
    (IPAM), `iam.projects.get`, `iam.fgaproxy.write`. НЕ может vpc.networks.delete и т.п.
  - `kacho-vpc` SA: `compute.zones.get`, `iam.projects.get`, `iam.fgaproxy.write`.
  - `kacho-vpc-operator` SA: только `vpc.subnets.list`, `vpc.networks.get`,
    `vpc.networkInterfaces.get`, `iam.projects.list` (read-only синк). Никаких мутаций.
  - `kacho-api-gateway`: identity для mTLS, но authz — по JWT конечного пользователя.
- **Привязка identity → mTLS**: client-cert SAN/CN = `spiffe://kacho/<sa-id>` (или
  `<sva-id>`); IAM сопоставляет client-cert identity с ServiceAccount при service→service.
  JWT (#7) остаётся для пользовательских запросов; service→service — по client-cert.
- Роли SA — seed-миграцией kacho-iam (детерминированные `sva`-id, как system-roles).

> **Инвариант доверия (design-review I2).** `x-kacho-principal-*` (identity *пользователя*)
> и mTLS client-cert (identity *модуля*) — ортогональные слои, не конфликтуют (mTLS
> оборачивает транспорт, propagation идёт поверх в metadata). Правило: cluster-internal
> listener **доверяет** principal-metadata ⟺ peer прошёл mTLS client-cert verify из internal
> CA. cert-identity (модуль) и principal (пользователь) логируются ОБА для аудита.
> SPIFFE-like SAN (`spiffe://kacho/<sva-id>`) — как строка уже сейчас (cert-manager проставит),
> SPIRE-инфраструктура — позже, формат совместим (design-review N4).
> **Валидация least-priv эмпирически (I6):** прогон newman e2e сервиса в production-mode под
> его узким SA; любой легитимный сценарий с `PermissionDenied` → недостающая permission;
> over-grant ловится diff'ом «роль SA ⊇ множество Check-вызовов из e2e».

## 4. Декомпозиция на подфазы (топосортировка proto→corelib→services→gateway→deploy→operator)

| Подфаза | Репо | Содержание | Зависит от |
|---|---|---|---|
| **SEC-A** Proto: FGA-proxy RPC | kacho-proto | `InternalIAMService.RegisterResource`/`UnregisterResource` (idempotent) + permission-option `iam.fgaproxy.write`; buf lint/breaking; **public breaking-diff = 0** | — |
| **SEC-B** corelib mTLS транспорт | kacho-corelib | TLS creds в grpcsrv/grpcclient + config TLSServer/TLSClient (per-edge enable) + identity-extractor из client-cert (SAN→SA); инвариант principal⟺mTLS | — |
| **SEC-C** IAM: FGA-proxy + SA-роли | kacho-iam | RegisterResource/Unregister через `fga_outbox`+drainer (идемпотентность GWT), least-priv роли SA (seed), client-cert→SA mapping | A, B |
| **SEC-D** vpc/compute/nlb: убрать прямой FGA + mTLS | kacho-vpc, kacho-compute, kacho-nlb | удалить openfga_write_client/fgawrite → **outbox-intent в writer-tx ресурса** + drainer→IAM.RegisterResource (миграция outbox через `db-architect-reviewer`/`migration-writer`); integration-тест «IAM down → tuple не теряется»; mTLS server+client; закрыть GitHub Issue N5 | A, B, C |
| **SEC-E** api-gateway: mTLS backend, JWT сохранить | kacho-api-gateway | mTLS client-dial к backend; verify JWT не тронут; Check для каждого | B, C |
| **SEC-F** deploy: cert-manager PKI + SA + helm mTLS + FGA NetworkPolicy | kacho-deploy | internal CA ClusterIssuer, per-svc Certificate ×2, helm-values mTLS-on, NetworkPolicy openfga←iam, SA-seed wiring | C, D, E |
| **SEC-G** операторы + OVN на mTLS | kacho-vpc-operator (+deploy) | mTLS client к vpc (отд. client-cert), own SA least-priv; стенд целиком на mTLS incl. kube-ovn | D, F |

Каждая подфаза → свой `acceptance-доклад` (`docs/specs/sub-phase-SEC-<X>-*-acceptance.md`)
+ ветка `KAC-<N>` в затронутых репо + integration+newman тесты (TDD, ban #12).

## 4.1 Уточнения после acceptance-review v1 (ground-truth — обязательны для A/C/F/G)

Acceptance-review v1: **APPROVED B, D, E**; **CHANGES A, C, F, G** — допущения §3 разошлись с
кодом. Канонические решения (перекрывают §3.1/§3.3/§6.3 где конфликт):

1. **fgaproxy-permission-механизм (закрывает SEC-A C1, SEC-C OQ-C-6).** RegisterResource/
   UnregisterResource в proto несут опцию `permission = "<exempt>"` (как все 7 текущих
   Internal IAM RPC) — чтобы `verify-catalog`/`verify-permissions-coverage` были зелёными
   (non-exempt требует `required_relation`+`scope_extractor`, которых у tuple-write нет
   естественно). Least-priv энфорсится **в IAM-handler**: mTLS client-cert → SA (SEC-B),
   затем ReBAC-проверка, что SA имеет relation `fga_writer` на системном объекте
   `iam_fgaproxy:system` (tuple выдаётся модульным SA в seed). Нет SA-relation → `PermissionDenied`.
   Это ReBAC, не flat-capability и не каталог-scope.
2. **Модель authz — ReBAC (закрывает SEC-C, SEC-G).** Least-priv SA = набор **relation-
   tuples** (`viewer`/`editor` на scope-объекты: project/account/vpc_network/vpc_subnet/…),
   а НЕ список плоских permission-строк. Каждый RPC имеет `required_relation` + (для user-
   флоу) `required_acr_min`. **Service→service вызовы (mTLS-SA) освобождены от
   `required_acr_min`** — ACR-floor применяется только к user-token-флоу (у SA нет MFA;
   его аутентификация — mTLS client-cert). SA-least-priv валидируется эмпирически (e2e).
3. **Permission-строки — 4-сегментные** `module.resource.resourceName.verb` (DB CHECK
   `iam_permissions_valid`); канонические имена ресурсов берутся **ЭМПИРИЧЕСКИ из
   `kacho-proto/gen/permission_catalog.json`** (напр. реальные `vpc.subnetses.list`,
   `iam.projectses.list`, `vpc.network_interfaces.get` — не выдумывать). `iam.fgaproxy.write`
   как permission-строка НЕ вводится (механизм — exempt+ReBAC, п.1).
4. **SPIFFE SAN — существующий SPIRE-формат** `spiffe://kacho.cloud/ns/<ns>/sa/kacho-<svc>`
   (в umbrella уже есть spire-server/agent/csi subchart'ы + `spiffe.trustDomain`, dev
   `enabled:false`). cert-manager выдаёт string-SAN В ЭТОМ ЖЕ формате — сосуществует с
   будущим SPIRE без миграции identity. НЕ вводить параллельный `spiffe://kacho/<sva-id>`.
   **Сегмент `ns/<ns>` ОБЯЗАН = фактический namespace pod'а** (иначе identity не совпадёт со
   SPIRE-entry). Core-сервисы — `ns/kacho-system/sa/kacho-<svc>`; **kacho-vpc-operator
   деплоится в `kacho-vpc-operator`** → его SAN = `spiffe://kacho.cloud/ns/kacho-vpc-operator/sa/kacho-vpc-operator`
   (вариант B acceptance-review v2; consolidation в kacho-system НЕ выбран).
5. **Тест-харнесс**: newman-регрессия живёт в **сервисных репо** (`kacho-<svc>/tests/newman`),
   не в kacho-deploy; `make e2e-test` в deploy = bash-смоук `e2e/0.1/*.sh`. SEC-F/G ссылаются
   на реальные харнессы; helm-assertion — НОВАЯ инфра (yq/helm-unittest), не «по прецеденту».
6. **Имена/прецеденты сверять с кодом**: kube-labels `app.kubernetes.io/name|component`
   (не `app=`); NLB-сервис канонически `kacho-nlb` (spire-registration упоминает legacy
   `kacho-loadbalancer` — выровнять); `kacho-selfsigned` ClusterIssuer уже ссылается в
   values.dev — переиспользовать, не плодить второй.

## 5. Definition of Done (эпик)

- mTLS включается флагом; `enable=false` — dev работает как сейчас (insecure).
- В production-mode: service→service по mTLS с раздельными client/server cert; anonymous
  fail-closed; FGA недостижим вне IAM (NetworkPolicy + authz-ролёвка).
- vpc/compute/nlb НЕ имеют прямого FGA-клиента (grep `openfga` в clients/ = 0).
- Каждый внутренний компонент — SA с least-priv ролью (audit: ни одной лишней permission).
- JWT-флоу для пользователей не изменён; публичные ресурсные контракты не изменены
  (proto breaking-diff = 0 на публичных сервисах; новое — только Internal IAM).
- Стенд `make dev-up` (mTLS-профиль) поднимается: сервисы + vpc-operator + kube-ovn,
  все коммуникации mTLS; e2e newman зелёные.

## 6. Решения по распределённым аспектам (закрыто design-review 2026-06-11)

1. **Dual-write FGA tuple → решено Вариантом A** (transactional-outbox, §3.1): intent в
   writer-tx ресурса, drainer→IAM.RegisterResource, идемпотентно, eventual, не теряется.
2. **cert-rotation → restart-on-rotate для MVP — ОК** (N3): Operations персистентны в БД,
   worker'ы читают state из БД (не из памяти), Watch RPC нет → рестарт реплики не теряет
   in-flight; окно — unary `Unavailable`, клиент ретраит. Hot-reload (file-watch) — позже.
3. **client-cert ↔ SA → SPIFFE-like SAN-строка сейчас** (`spiffe://kacho/<sva-id>`), SPIRE
   позже (формат совместим). IAM читает SAN как непрозрачный identity-string.
4. **mTLS на :9090 backend-dial нужен** и ортогонален JWT (I4): api-gateway терминирует JWT,
   ставит principal-metadata, дилит к backend по mTLS client-cert «api-gateway»; backend
   authz по-прежнему по principal (Check), не по cert.
5. **rollback → per-edge feature-flag** (I7): каждое ребро (gateway→vpc/compute, vpc→iam,
   compute→iam, vpc↔compute, operator→vpc) включается независимым `enable`; mismatch →
   `Unavailable`, детектируется e2e per-edge.
6. **Ацикличность подтверждена** (N1): iam не импортирует vpc/compute; fgaproxy-рёбра
   vpc→iam / compute→iam — усиление существующего направления. vpc⇄compute — НЕ семантический
   цикл (N2: разные ресурсные контексты, запрос не порождает обратный синхронный вызов).
   Зафиксировать fgaproxy-рёбра + не-цикл-инвариант в `polyrepo.md` (в SEC-A/итог эпика).
7. **fail-closed**: mTLS handshake fail / IAM Unavailable для мутаций → `Unavailable`
   (cross-domain политика data-integrity.md). Распространяется на RegisterResource.

**Вердикт design-review: CHANGES REQUESTED → правки 1-6 внесены в этот документ; дизайн
готов к acceptance-фазе.**
