# Sub-phase SEC-C — IAM FGA-proxy (RegisterResource/UnregisterResource) + least-privilege service-account identities (ReBAC) + client-cert→SA mapping — Acceptance

> Статус: DRAFT (re-draft v2 — закрыты critical findings acceptance-review v1; v3 — §2.1/A-01..A-07 выровнены на SYNC RegisterResourceResponse по ground-truth SEC-A proto)
> Дата: 2026-06-11
>
> **Согласование с SEC-A proto (v3, system-design review I2):** §2.1 и сценарии A-01..A-07 в
> v2 описывали `RegisterResource`/`UnregisterResource` как async через `operation.Operation`
> (ban #9). Реальный SEC-A-контракт (ground truth — `kacho-proto` `InternalIAMService`) —
> **SYNC unary**: `RegisterResource(RegisterResourceRequest) → RegisterResourceResponse{}`
> (пустой ответ; success = gRPC `OK`). Это осознанное исключение из ban #9 для FGA-proxy:
> at-least-once-гарантия обеспечивается **caller-side drainer'ом (SEC-D)** через
> transactional-outbox, а не LRO; сам RegisterResource — тонкий relay, коммитящий tuple-intent
> в `kacho_iam.fga_outbox` в одной writer-tx и возвращающий пустой ответ синхронно. Спека
> приведена к sync (Operation-поллинг для этих RPC убран); код корректен.
> Ревьюер: acceptance-reviewer (gate per workspace `CLAUDE.md` §Non-negotiables #1; + `system-design-reviewer` на распределённые аспекты)
> Автор-агент: acceptance-author
> Эпик: [EPIC] SEC — mTLS + IAM-fronted authz + least-privilege service identities — `docs/specs/sub-phase-SEC-mtls-iam-authz-epic.md` (подфаза **SEC-C**, зависит от SEC-A + SEC-B). **Канон-вход: эпик §4.1 «Уточнения после acceptance-review v1».**
> Тикет: KAC-<N> (subtask SEC-C эпика SEC; ветка `KAC-<N>` в `kacho-iam`)
> Backend: `kacho-iam` (PRIMARY) · Proto: `kacho-proto` (контракт из SEC-A, потребляется здесь) · corelib: `kacho-corelib` (mTLS-creds + cert-SAN-extractor из SEC-B, потребляется здесь)
> Конвенции (нормативно, не дублируются в теле — ссылки): `.claude/rules/api-conventions.md` (Internal-RPC, error-format, Operation), `.claude/rules/data-integrity.md` (within-service DB-инварианты, fail-closed cross-domain), `.claude/rules/security.md` (Internal-vs-public, ban #6), `.claude/rules/testing.md` (TDD-red, ban #12/#13), `.claude/rules/polyrepo.md` (кросс-репо порядок).

---

## 0. Обзор

SEC-C — серверная половина решения «FGA за IAM» (эпик §3.1, требования #6/#8) **плюс** server-side
энфорсмент least-privilege service-identity в модели **ReBAC** (эпик §4.1 п.1/п.2, требование #4).

Она реализует в `kacho-iam` два **Internal-only** RPC — `InternalIAMService.RegisterResource` и
`UnregisterResource` — которые принимают намерение «зарегистрировать/снять owner-hierarchy-tuple
ресурса» от модульных сервисов (kacho-vpc / kacho-compute / kacho-nlb) и применяют его к FGA
**через уже существующий `kacho_iam.fga_outbox` + drainer** (тот же транзакционно-outbox-путь,
что `fga_applier.go`: payload `{user, relation, object}`, классификация already_exists→ok /
validation→poison / 5xx→retry), а не прямым sync-вызовом OpenFGA. Это устраняет dual-write-баг
(эпик §3.1 C1): owner-tuple больше не теряется при недоступности FGA.

**Authz-gate этих RPC — ReBAC, не flat-capability (эпик §4.1 п.1).** В proto (SEC-A) оба RPC несут
опцию `permission = "<exempt>"` (как все текущие Internal IAM RPC — см. §2), чтобы catalog-гейты
`verify-catalog` / `verify-permissions-coverage` были зелёными (non-exempt требует `required_relation`
+ `scope_extractor`, которых у tuple-write нет естественно). Least-priv энфорсится **внутри
IAM-handler**: mTLS client-cert → ServiceAccount (cert-SAN-extractor SEC-B + mapping SEC-C), затем
**ReBAC-проверка** — есть ли у этого SA relation `fga_writer` на системном объекте `iam_fgaproxy:system`
(tuple выдан модульным SA в seed). Нет relation → `PERMISSION_DENIED`. Никакой permission-строки
`iam.fgaproxy.write` **не вводится** (эпик §4.1 п.1/п.3).

**Least-priv SA — набор relation-tuples, не плоский список permission-строк (эпик §4.1 п.2).** SEC-C
сидит seed-миграцией персональные SA-identity каждого модуля (compute, vpc, nlb, vpc-operator,
api-gateway) с **детерминированными `sva`-id** и привязывает им **минимальный набор ReBAC-relation'ов**
(`viewer`/`editor` на scope-объекты: project / account / cluster и т.п. + `fga_writer` на
`iam_fgaproxy:system` для модулей, которым нужен FGA-proxy). Параллельно сидятся backing RBAC-v2
roles+AccessBinding'и (роль = носитель набора permission-строк **строго 4-сегментной грамматики**
`module.resource.resourceName.verb`, см. §2.3) — это существующий механизм seed'а system-ролей
(precedent 0025_nlb). **Авторитетная модель least-priv для SEC-C — ReBAC** (relation-tuples);
RBAC-v2-роль — backing-носитель, чьи permission-строки берутся **эмпирически из
`kacho-proto/gen/permission_catalog.json`** (не выдумываются, см. §2.3).

Наконец, SEC-C добавляет mapping client-cert SAN
(`spiffe://kacho.cloud/ns/<ns>/sa/kacho-<svc>` — существующий SPIRE-формат, эпик §4.1 п.4) →
ServiceAccount, чтобы при service→service-вызове по mTLS IAM знал, какой модуль звонит, и проверял
его ReBAC-relation.

**Opt-in / backward-compat (эпик DoD).** Подфаза мёржится в `main` без поломки текущего поведения:
mTLS и ReBAC-гейт на FGA-proxy включаются per-edge флагами (`enable=false` = текущий dev insecure +
anonymous→full-access; см. сценарии группы D). Когда модули ещё пишут FGA напрямую (это убирается в
SEC-D), новые RPC просто не вызываются — их наличие никому не мешает.

**Контракты не меняются (требование #8).** `RegisterResource`/`UnregisterResource` живут в
`InternalIAMService` (cluster-internal :9091, ban #6) — это **не** публичный ресурсный контракт;
public proto breaking-diff = 0 (гейт SEC-A). Никакой публичный RPC не трогается.

### Что НЕ входит в SEC-C (boundary; не tech-debt)

- **Proto-определение** `RegisterResource`/`UnregisterResource` + проставление `permission="<exempt>"` —
  это **SEC-A** (`kacho-proto`). SEC-C **потребляет** уже сгенерированные stubs; форма payload
  (см. §2) — отражение SEC-A-контракта, а не его определение здесь.
- **Authorization-model FGA**: объявление типа `iam_fgaproxy` с relation `fga_writer` в FGA-модели —
  координируется в **SEC-A** (authorization-model меняется вместе с proto). SEC-C опирается на
  наличие этого типа/relation и пишет seed-tuple (`<sva>#fga_writer@iam_fgaproxy:system`).
- **corelib mTLS-creds** (TLSServer/TLSClient) + **извлечение identity из client-cert SAN** — это
  **SEC-B** (`kacho-corelib`). SEC-C потребляет SEC-B-экстрактор; SAN-парсинг здесь не реализуется,
  только mapping «извлечённый SAN-string → ServiceAccount-lookup».
- **Удаление прямого FGA-клиента в vpc/compute/nlb + outbox-intent в writer-tx ресурса + drainer→
  IAM.RegisterResource** — это **SEC-D** (consumer-сторона). SEC-C — серверная (callee) сторона.
- **cert-manager PKI / per-svc Certificate ×2 (SAN в формате §4.1 п.4) / NetworkPolicy openfga←iam /
  SA-seed helm-wiring** — это **SEC-F** (`kacho-deploy`). SEC-C сидит SA-identity + relation-tuples +
  backing-роли в БД IAM seed-миграцией; helm-проброс client-cert SAN ↔ secret — SEC-F.
- **api-gateway mTLS backend-dial** — это **SEC-E**.

---

## 1. Связь с регламентом, требованиями эпика и решениями (трассировка)

| Что | Где соблюдаем / какой сценарий |
|---|---|
| Требование #4 (least-priv SA) | эпик §3.3 + §4.1 п.2 (ReBAC) → сценарии группы B (B-01..B-09): seed SA-identity, relation-tuples, backing 4-сегментные роли, over-/under-grant. |
| Требование #6 (FGA только через IAM) | RegisterResource/Unregister — Internal-only :9091 (ban #6); сценарии A-* (через IAM tuple применяется) + D-04 (контракт «FGA за IAM»; network-side — SEC-F). |
| Требование #8 (контракты не меняются) | Internal-only RPC, public breaking-diff=0 (гейт SEC-A); §0 boundary + сценарий A-09 (RPC нет на external listener). |
| Решение §3.1 / §6.1 (transactional-outbox Вариант A, идемпотентность) | RegisterResource применяет tuple через `fga_outbox`+drainer; идемпотентность как **контракт** — сценарии A-01..A-06. |
| **эпик §4.1 п.1 (fgaproxy = exempt-proto + ReBAC relation `fga_writer` на `iam_fgaproxy:system`)** | §2.2; сценарии B-07/B-08 (allow/deny через ReBAC-relation, **не** permission-строку). **OQ-C-6 закрыт** (механизм зафиксирован). |
| **эпик §4.1 п.2 (модель authz = ReBAC; service→SA освобождены от `required_acr_min`)** | §2.2; группа B (relation-tuples); сценарий B-09 (SA-вызов без ACR-floor → не блокируется). |
| **эпик §4.1 п.3 (permission-строки 4-сегментные; имена ресурсов из `permission_catalog.json`)** | §2.3; сценарии B-02..B-05 (byte-for-byte 4-сегментные строки из каталога). |
| **эпик §4.1 п.4 (SPIFFE SAN = `spiffe://kacho.cloud/ns/<ns>/sa/kacho-<svc>`)** | §2.4; группа C (C-01..C-05). |
| **эпик §4.1 п.6 (имена/прецеденты: NLB=`kacho-nlb`, переиспользовать `kacho-selfsigned`, kube-labels `app.kubernetes.io/*`)** | §2.4 (SA-имя nlb выровнено на `kacho-nlb`); SEC-F-boundary (issuer/labels — deploy). |
| Решение §6.7 / data-integrity fail-closed | FGA/drainer-недоступность → tuple не теряется, sync RPC не падает (A-07); IAM down для модуля → Unavailable (SEC-D-сторона; здесь — A-07 «intent не теряется»). |
| Решение §3.1 invariant I2 (principal ⟺ mTLS, оба логируются) | сценарий C-04 (audit-лог несёт cert-identity модуля + propagated principal). |
| **Решение §6.2 (restart-on-rotate MVP; Operations персистентны, worker читает state из БД)** | сценарий A-07 (in-flight intent переживает рестарт drainer-реплики). |
| ban #10 (within-service инвариант на DB-уровне) | atomic claim drainer'а (наследуется из W1.1); seed-идемпотентность через `ON CONFLICT (id) DO NOTHING`; сценарий A-06 (конкурентный двойной Register → ровно один tuple). |
| ban #9 (мутации → Operation) | **Осознанное исключение для FGA-proxy:** RegisterResource/Unregister — **SYNC unary** (`RegisterResourceResponse{}`, ground-truth SEC-A proto, как `WriteCreatorTuple`); at-least-once даёт caller-side drainer (SEC-D) через outbox, не LRO — §2.1 + A-01. |
| ban #5 (применённые миграции не редактируем) | новая seed-миграция SEC-C (следующий свободный номер; не трогаем 0001..0008/0025). |
| ban #12 (TDD-red) | §7 — список integration+newman тестов, написанных RED до кода (1:1 на ID). |

---

## 2. Контракт RPC + authz-модель + permission-грамматика + identity (форма из SEC-A; здесь — наблюдаемое поведение)

### 2.1 RPC-форма

> Точные proto-определения — SEC-A (ground truth). Ниже — поведенческий контракт, на который опираются сценарии.
> Форма следует образцу `InternalIAMService.WriteCreatorTuple` (Internal :9091, **SYNC unary**,
> пустой response; success = gRPC `OK`); tuple-словарь `subject_id`/`relation`/`object` совпадает с
> FGA-вокабуляром и с payload `fga_outbox`-эмиттера (`user`/`relation`/`object`).

- **`InternalIAMService.RegisterResource(RegisterResourceRequest) → RegisterResourceResponse{}`** (SYNC unary; см. согласование с SEC-A proto в шапке — исключение из ban #9 для FGA-proxy).
  Cluster-internal :9091, REST internal mux `POST /iam/v1/internal:registerResource` (только internal listener; **нет** на external — ban #6).
  Payload (camelCase в REST; точные имена — SEC-A proto):
  - `subjectId` (string, FGA-subject `"<type>:<id>"`, напр. `project:<prj_…>`) — required, `INVALID_ARGUMENT` если пуст.
  - `relation` (string, FGA-relation owner-tuple, напр. `parent`/`admin`) — required, `INVALID_ARGUMENT` если пуст.
  - `object` (string, FGA-object `"<type>:<id>"`, напр. `vpc_network:<enp_…>`) — required, `INVALID_ARGUMENT` если пуст.
  - `traceId` (string, опционален; для correlation в логах; не влияет на семантику — она идемпотентна сама по себе).
  Семантика: пишет owner-hierarchy-tuple `{user: subjectId, relation, object}` (FGA-строки приходят уже
  скомпонованными от модуля — relay не знает resource-type; точная relation/форма — из SEC-A authorization-model,
  «owner-hierarchy tuple ресурс→проект» — OQ-C-1 §2.5) в `kacho_iam.fga_outbox` (event_type `fga.tuple.write`)
  **в одной tx**, затем **синхронно** возвращает пустой `RegisterResourceResponse` (gRPC `OK`); drainer применяет
  к FGA асинхронно (как сегодня `fga_applier.go`).

- **`InternalIAMService.UnregisterResource(UnregisterResourceRequest) → UnregisterResourceResponse{}`** (SYNC unary).
  Cluster-internal :9091, REST internal mux `POST /iam/v1/internal:unregisterResource`.
  Payload: те же `subjectId` / `relation` / `object` / `traceId`.
  Семантика: пишет тот же tuple в `fga_outbox` с event_type `fga.tuple.delete` (симметричный revoke), синхронный пустой ответ.

- **Idempotency как контракт (решение §3.1/§6.1):** повторный `RegisterResource` тем же tuple → gRPC `OK`
  (пустой response), **НЕ** `ALREADY_EXISTS`; `UnregisterResource` отсутствующего tuple → gRPC `OK`,
  **НЕ** `NOT_FOUND`. Это требование — на нём держится retry-цепочка SEC-D-drainer'а. Реализуется
  естественно: drainer-applier уже маппит FGA `already_exists`→`ErrAlreadyApplied`→success и
  `cannot_delete`/`does not exist`/`not_found`→`ErrAlreadyApplied`→success (`fga_applier.go`).

### 2.2 Authz-gate — exempt-в-proto + ReBAC relation (закрывает OQ-C-6, эпик §4.1 п.1/п.2)

- **В proto (SEC-A) оба RPC помечены `permission = "<exempt>"`** — как все текущие Internal IAM RPC
  (`InternalIAMService/Check`, `.../WriteCreatorTuple`, `InternalAuthorizeService/WriteTuples` и др. —
  все exempt в `permission_catalog.json`). Это держит `verify-catalog`/`verify-permissions-coverage`
  зелёными: non-exempt RPC обязан нести `required_relation` + `scope_extractor`, которых у generic
  tuple-write по чужому ресурсу нет естественно.
- **Энфорсмент least-priv — внутри IAM-handler (ReBAC):**
  1. mTLS client-cert → SAN-string (SEC-B extractor) → ServiceAccount-lookup (SEC-C mapping, группа C).
  2. ReBAC-проверка тем же путём, что `AuthorizeService.Check`: `subject = "service_account:<sva-id>"`,
     `relation = "fga_writer"`, `object = "iam_fgaproxy:system"` → FGA `Check`. ALLOW → RPC отрабатывает;
     DENY → `PERMISSION_DENIED`.
  3. Это **ReBAC**, не flat-capability и не каталог-scope: право «писать через FGA-proxy» выражено
     relation-tuple'ом `<sva>#fga_writer@iam_fgaproxy:system`, выдаваемым модульному SA в seed (§2.3 / B-01).
- **Service→service (mTLS-SA) освобождены от `required_acr_min` (эпик §4.1 п.2):** ACR-floor применяется
  только к user-token-флоу (у SA нет MFA; его аутентификация — mTLS client-cert). Сценарий B-09 это фиксирует.
- **Anonymous в production-mode** (нет валидного cert → нет SA → нет relation) → `PERMISSION_DENIED` (fail-closed).
- **Где живёт mapping/проверка (OQ-C-4):** внутренний шаг authz-interceptor IAM internal listener
  (cert-SAN→SA-lookup → ReBAC-Check `fga_writer`), **без** нового публичного/Internal RPC сверх SEC-A.

### 2.3 Least-priv SA — relation-tuples (авторитет) + backing RBAC-v2 4-сегментные роли

Эпик §4.1 п.2: least-priv SA — **набор relation-tuples** на scope-объекты. SEC-C для каждого
модульного SA сидит:
- **ReBAC relation-tuples** (авторитетная модель least-priv): минимальный набор `viewer`/`editor`/
  `fga_writer` на scope-объекты (cluster / project / account / `iam_fgaproxy:system`), достаточный
  ровно под задачи модуля (эпик §3.3) — ни одного лишнего.
- **Backing RBAC-v2 role + AccessBinding** (механизм seed system-ролей, precedent 0025_nlb): роль
  несёт набор **permission-строк строго 4-сегментной грамматики** `module.resource.resourceName.verb`
  (DB CHECK `iam_permissions_valid`, миграция 0005/KAC-216 — regex отвергает 3-сегментные). Имена
  ресурсов — **эмпирически из `kacho-proto/gen/permission_catalog.json`** (не выдумываются).

**Канон-сводка permission-строк (4-сегментные, из каталога; `*` — wildcard-resourceName, как
promotion в 0005 и precedent в `seed_nlb_roles`):**

| Модульный SA | Backing-роль (4-сегментные permission-строки из `permission_catalog.json`) | ReBAC relation-tuples |
|---|---|---|
| **compute** | `vpc.subnets.*.get`, `vpc.security_groups.*.get`, `vpc.addresses.*.get`, `vpc.addresses.*.create`, `vpc.addresses.*.delete`, `vpc.addresses.*.update`, `iam.projects.*.get` | `viewer` на scope (project/cluster под read) + **`fga_writer` на `iam_fgaproxy:system`** |
| **vpc** | `compute.zones.*.get`, `iam.projects.*.get` | `viewer` на scope + **`fga_writer` на `iam_fgaproxy:system`** |
| **nlb** | `vpc.subnets.*.get`, `iam.projects.*.get` | `viewer` на scope + **`fga_writer` на `iam_fgaproxy:system`** (OQ-C-2) |
| **vpc-operator** | `vpc.subnetses.*.list`, `vpc.networks.*.get`, `vpc.network_interfaces.*.get`, `iam.projectses.*.list` | только `viewer` на scope (read-only синк); **БЕЗ** `fga_writer` |
| **api-gateway** | пустая/минимальная (identity-only; authz по JWT пользователя) | **БЕЗ** `fga_writer`, без ресурсных relation'ов (OQ-C-3) |

> Примечания (сверено с каталогом эмпирически): list-ресурсы имеют каталожный сегмент с двойным
> множественным числом — `vpc.subnetses` (для `List Subnets`), `iam.projectses` (для `List Projects`) —
> это реальные строки `permission_catalog.json`, не опечатка; 4-сегментная форма `vpc.subnetses.*.list`
> / `iam.projectses.*.list` проходит CHECK-regex (resource-сегмент `[a-z][a-zA-Z0-9_]*`).
> `vpc.security_groups` / `vpc.network_interfaces` — snake_case-сегменты из каталога. `fgaproxy` как
> permission-resource-сегмент **не вводится** (эпик §4.1 п.3): право FGA-proxy — ReBAC-relation, не permission-строка.

### 2.4 Identity — SPIFFE SAN (эпик §4.1 п.4) + имена SA (эпик §4.1 п.6)

- SAN client-cert = **существующий SPIRE-формат** `spiffe://kacho.cloud/ns/<ns>/sa/kacho-<svc>`
  (trustDomain `kacho.cloud` уже в umbrella; ns — `kacho-system`). НЕ вводить параллельный
  `spiffe://kacho/<sva-id>`. IAM читает SAN как непрозрачную identity-строку и маппит на ServiceAccount.
- Имена сервис-сегмента SAN: `kacho-iam`, `kacho-vpc`, `kacho-compute`, **`kacho-nlb`** (канон; legacy
  `kacho-loadbalancer` в spire-registration выравнивается на `kacho-nlb` — эпик §4.1 п.6),
  `kacho-vpc-operator`, `kacho-api-gateway`.
- cert-manager (SEC-F) выдаёт string-SAN в этом же формате → сосуществует с будущим SPIRE без миграции
  identity. `kacho-selfsigned` ClusterIssuer (уже в `values.dev`) переиспользуется — SEC-F-сторона.

### 2.5 Open questions — дефолты приняты в контракт (для разблокировки integration-tester)

| ID | Вопрос | Принятый дефолт (фиксируется как решение; финализация — по SEC-A) |
|---|---|---|
| **OQ-C-1** | Точная FGA-relation/форма owner-hierarchy tuple RegisterResource. | `{user:"project:<projectId>", relation:"parent", object:"<resourceType>:<resourceId>"}` — owner-hierarchy ресурс→проект. **Финализируется по SEC-A authorization-model**; integration-tester использует этот дефолт. |
| **OQ-C-2** | Точный permission-/relation-набор nlb-SA (эпик §3.3 явно не разложил nlb). | Backing: `{vpc.subnets.*.get, iam.projects.*.get}` + ReBAC `viewer` + `fga_writer` на `iam_fgaproxy:system`. Сверить с nlb cross-service edge. |
| **OQ-C-3** | Состав api-gateway-SA (identity-only — нужна ли роль вообще). | Минимальная/пустая backing-роль; **БЕЗ** `fga_writer`, без ресурсных relation'ов: identity для mTLS, authz по JWT пользователя. |
| **OQ-C-4** | Где живёт cert-SAN→SA lookup + ReBAC-проверка. | Внутренний шаг authz-interceptor IAM internal listener (нет нового RPC сверх SEC-A). |
| **OQ-C-5** | Хранение SAN↔SA mapping. | Детерминированно из имени сервиса: SAN `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-<svc>` ↔ детерминированный `sva`-id модуля (`'sva' || substr(md5('kacho-<svc>'),1,17)`); без новой колонки. cert-manager проставит SAN по этому имени (SEC-F). |
| **OQ-C-6** | **[закрыт]** Механизм authz-gate `fgaproxy`. | **exempt-в-proto + ReBAC relation `fga_writer` на `iam_fgaproxy:system`** (эпик §4.1 п.1). Не permission-map-запись, не permission-string-scan. См. §2.2. |

> OQ-C-1/OQ-C-4/OQ-C-5 затрагивают форму tuple / mapping — дефолты приняты в контракт выше, чтобы
> integration-tester не блокировался; финализация формы tuple — по SEC-A authorization-model (sign-off ревьюера на §2.5).

---

## Группа A — RegisterResource / UnregisterResource: идемпотентность + outbox-применение + fail-safe

### Сценарий A-01: RegisterResource (happy path) → sync OK → tuple применён в FGA

**ID:** SEC-C-A-01-REGISTER-OK
**Трассировка:** эпик §3.1 (Вариант A), §6.1; ban #9.

**Given** kacho-iam поднят с FGA-stub (или testcontainers OpenFGA), drainer запущен (как сегодня в `cmd/kacho-iam/main.go`)
**And** проект `project:prj-1` существует в authorization-model (seed)
**And** caller — module-SA `kacho-vpc` (`sva`-id из B-01) с relation `fga_writer` на `iam_fgaproxy:system` (см. группу B), production-mode authz

**When** caller вызывает `InternalIAMService/RegisterResource` (`POST /iam/v1/internal:registerResource` на internal listener) с payload:
  - subjectId = `"project:prj-1"`
  - relation = `"parent"`
  - object = `"vpc_network:enp00000000000000001"`
  - traceId = `"enp00000000000000001"`

**Then** ответ синхронно — пустой `RegisterResourceResponse{}`, gRPC `OK` (sync-контракт SEC-A proto; нет Operation-id)
**And** в `kacho_iam.fga_outbox` появилась ровно **одна** строка `event_type='fga.tuple.write'`, payload `{user:"project:prj-1", relation:"parent", object:"vpc_network:enp00000000000000001"}` (точная форма tuple — OQ-C-1/§2.5), `sent_at IS NULL`, закоммичена в **одной writer-tx** (rollback ⇒ нет orphan-строки)
**And** в течение ≤ 2 c (drainer NOTIFY-apply) строка помечена `sent_at IS NOT NULL`, `last_error IS NULL`
**And** последующий FGA-Check «является ли `project:prj-1` parent для `vpc_network:enp00000000000000001`» → ALLOW.

### Сценарий A-02: RegisterResource повторно тем же tuple → OK (идемпотентно, не ALREADY_EXISTS)

**ID:** SEC-C-A-02-REGISTER-IDEMPOTENT
**Трассировка:** эпик §3.1 «повтор owner-tuple → gRPC OK, НЕ AlreadyExists»; §6.1.

**Given** tuple для `vpc_network:enp00000000000000001`/`project:prj-1` уже зарегистрирован и применён (A-01 отработал)

**When** caller повторно вызывает `RegisterResource` с **идентичным** payload (A-01)

**Then** ответ — пустой `RegisterResourceResponse{}`, gRPC `OK`
**And** **не** возвращается `ALREADY_EXISTS`
**And** в FGA по-прежнему ровно **один** соответствующий tuple (не задвоен)
**And** drainer пометил повторную outbox-строку `sent_at IS NOT NULL` (FGA `already_exists`→`ErrAlreadyApplied`→success, `fga_applier.go`).

### Сценарий A-03: UnregisterResource (happy path) → tuple удалён

**ID:** SEC-C-A-03-UNREGISTER-OK
**Трассировка:** эпик §3.1 «Симметрично: Delete ресурса → Unregister-intent».

**Given** tuple для `vpc_network:enp00000000000000001`/`project:prj-1` зарегистрирован (A-01)

**When** caller (module-SA `kacho-vpc`, relation `fga_writer`) вызывает `UnregisterResource` с тем же `subjectId`/`relation`/`object` (что в A-01)

**Then** ответ — пустой `UnregisterResourceResponse{}`, gRPC `OK`
**And** в `fga_outbox` строка `event_type='fga.tuple.delete'` появилась и помечена `sent_at IS NOT NULL`
**And** последующий FGA-Check для этого tuple → DENY (tuple отсутствует).

### Сценарий A-04: UnregisterResource отсутствующего tuple → OK (идемпотентно, не NOT_FOUND)

**ID:** SEC-C-A-04-UNREGISTER-IDEMPOTENT
**Трассировка:** эпик §3.1 «delete отсутствующего → OK».

**Given** для `vpc_network:enp99999999999999999`/`project:prj-1` tuple **никогда** не регистрировался

**When** caller вызывает `UnregisterResource(subjectId="project:prj-1", relation="parent", object="vpc_network:enp99999999999999999")`

**Then** ответ — пустой `UnregisterResourceResponse{}`, gRPC `OK`
**And** **не** возвращается `NOT_FOUND`
**And** drainer пометил outbox-строку `sent_at IS NOT NULL` (FGA `cannot_delete`/`does not exist`→`ErrAlreadyApplied`→success).

### Сценарий A-05: RegisterResource с невалидным payload → sync INVALID_ARGUMENT (outbox-строка НЕ создаётся)

**ID:** SEC-C-A-05-NEG-INVALID-INPUT
**Трассировка:** `.claude/rules/api-conventions.md` error-format (validation → INVALID_ARGUMENT, sync до эмиссии outbox).

**Given** caller — module-SA с relation `fga_writer` на `iam_fgaproxy:system`

**When / Then** (каждый под-кейс — sync `INVALID_ARGUMENT`, outbox-строка **не** создаётся):
  - **A-05a** `subjectId=""` → `INVALID_ARGUMENT` «subject_id required»
  - **A-05b** `relation=""` → `INVALID_ARGUMENT` «relation required»
  - **A-05c** `object=""` → `INVALID_ARGUMENT` «object required»
  - **A-05d** `object`/`subjectId` содержит запрещённые для FGA-грамматики символы (пробел / `#`, либо нет ровно одного `:`) → `INVALID_ARGUMENT` «invalid object»/«invalid subject_id»
**And** в `kacho_iam.fga_outbox` новых строк **нет**.

### Сценарий A-06: Concurrency — два конкурентных RegisterResource тем же tuple → ровно один эффективный tuple

**ID:** SEC-C-A-06-CONCURRENT-REGISTER (integration / testcontainers)
**Трассировка:** ban #10 (DB-level invariant, без TOCTOU); drainer atomic-claim (W1.1 §4.2).

**Given** kacho-iam + drainer + FGA-stub; tuple ещё не зарегистрирован

**When** две goroutine одновременно вызывают `RegisterResource` с идентичным payload (`vpc_network:enp00000000000000002`/`project:prj-1`)

**Then** обе вернули gRPC `OK` (пустой `RegisterResourceResponse{}`)
**And** в FGA — ровно **один** соответствующий tuple (вторая outbox-строка → drainer `already_exists`→`ErrAlreadyApplied`→success; idempotent, без двойного эффекта)
**And** сервис **не** падает и **не** возвращает `INTERNAL` с leak'ом pgx/FGA-текста (error-format).

### Сценарий A-07: FGA/drainer недоступен (incl. рестарт реплики) → intent не теряется, RPC не падает (fail-safe)

**ID:** SEC-C-A-07-FGA-DOWN-INTENT-PERSISTS (integration / testcontainers)
**Трассировка:** эпик §3.1 «IAM Unavailable → drainer retry с backoff, tuple не теряется»; §6.7 fail-closed; **§6.2 (restart-on-rotate; intent-строка персистентна в БД, drainer читает state из БД)**.

**Given** kacho-iam поднят, **FGA-stub настроен возвращать 5xx/transient** (или drainer временно остановлен)
**And** caller — module-SA с relation `fga_writer` на `iam_fgaproxy:system`

**When** caller вызывает `RegisterResource(subjectId=project:prj-1, relation=parent, object=vpc_network:enp00000000000000003)`

**Then** `RegisterResource` **синхронно** возвращает `OK` (пустой `RegisterResourceResponse{}`): запись-намерение в `fga_outbox` коммитится в writer-tx **независимо** от доступности FGA — intent **не** теряется
**And** outbox-строка остаётся `sent_at IS NULL` с растущим `attempt_count` + `last_error` (transient-retry, `fga_applier.go` классифицирует 5xx как retryable)
**And** sync-ответ RegisterResource **не** становится ошибкой из-за недоступности FGA (запись intent выполнена; применение eventual через drainer)
**And** **(рестарт реплики, §6.2)** если drainer-реплику рестартнуть в окне до применения — `sent_at IS NULL`-строка переживает рестарт (state в БД, не в памяти; Watch RPC нет), после старта новая реплика подхватывает строку
**And** после восстановления FGA-stub (отдаёт 200) drainer в течение ≤ 5 c помечает строку `sent_at IS NOT NULL`; FGA-Check → ALLOW (окно DENY конечно и гарантированно закрывается — эпик §3.1).

### Сценарий A-08: Decoder-poison — некорректный intent → poison, drainer не застревает

**ID:** SEC-C-A-08-POISON-ROW (integration / testcontainers)
**Трассировка:** эпик §3.1 «validation→poison»; `fga_applier.go` `ErrPermanent`.

**Given** kacho-iam + drainer; в `fga_outbox` (прямым INSERT, моделируя bug-payload) появилась строка с tuple, который FGA отвергнет как validation-error (напр. `object` ссылается на undefined object-type)

**When** drainer обрабатывает строку

**Then** строка помечена `attempt_count >= MaxAttempts` (force-poison), `last_error LIKE '%validation%'`, `sent_at IS NULL`
**And** последующая нормальная Register-строка применяется (`sent_at IS NOT NULL`) — drainer не застрял на poison-row
**And** RegisterResource-RPC, отдавший корректный payload, **не** генерирует poison (валидный intent → валидный tuple); poison моделируется только прямым bug-INSERT (regression-guard).

### Сценарий A-09: Internal-only — RegisterResource/Unregister НЕ доступны на external listener (ban #6)

**ID:** SEC-C-A-09-INTERNAL-ONLY
**Трассировка:** требование #6/#8; `.claude/rules/security.md` ban #6.

**Given** kacho-iam с external listener (advertised) и cluster-internal listener :9091

**When / Then:**
  - **A-09a** запрос `RegisterResource` через **external** TLS endpoint / external REST mux → маршрут **не существует** (`UNIMPLEMENTED`/404 — RPC не зарегистрирован на external mux)
  - **A-09b** тот же запрос через **internal** :9091 / internal REST mux → доходит до authz-gate (далее по группе B)
**And** `buf breaking` на публичных сервисах = 0 (новый RPC только в `InternalIAMService`; гейт SEC-A, здесь — регрессионная сверка).

---

## Группа B — Least-privilege SA-identity (seed): ReBAC relation-tuples + backing 4-сегментные роли + fgaproxy-гейт

> Seed-механика следует precedent'у `0025_nlb_operator_target_manager_roles.sql` (см.
> `seed_nlb_roles_integration_test.go`): детерминированные `rol`-id (`'rol' || substr(md5('<role-name>'),1,17)`),
> детерминированные `sva`-id (аналогично, `'sva' || substr(md5('kacho-<svc>'),1,17)`), `is_system=true`,
> `cluster_id='cluster_kacho_root'`, `account_id IS NULL`, `ON CONFLICT (id) DO NOTHING` (идемпотентный re-apply),
> immutable (Update/Delete системной роли → `ErrFailedPrecondition`, verbatim «System role»).
> Permission-строки в backing-роли — **строго 4-сегментные** `module.resource.resourceName.verb`
> (DB CHECK `iam_permissions_valid`, миграция 0005/KAC-216); 3-сегментные регекс отвергает. ReBAC
> relation-tuples (`<sva>#<relation>@<scope-object>`) сидятся в FGA через `fga_outbox`-эмиттер в той же
> seed-tx (как owner-tuple'ы), либо через FGA bootstrap-путь — без прямого best-effort write (ban dual-write).

### Сценарий B-01: Seed создаёт SA-identity + ReBAC relation-tuples + backing-роль для каждого модуля (детерминированные id)

**ID:** SEC-C-B-01-SEED-MODULE-SA-IDENTITY (integration / testcontainers)
**Трассировка:** требование #4; эпик §3.3 + §4.1 п.2.

**Given** свежая БД `kacho_iam` + FGA-stub/контейнер

**When** применяется новая seed-миграция SEC-C (goose; ban #5 — существующие миграции не редактируем)

**Then** созданы **5** module ServiceAccount'ов (`is_system`/`account_id IS NULL`, детерминированные `sva`-id из `'sva' || substr(md5('kacho-<svc>'),1,17)`):
  - `kacho-vpc`, `kacho-compute`, `kacho-nlb`, `kacho-vpc-operator`, `kacho-api-gateway`
**And** каждому привязана персональная **backing-роль** (детерминированный `rol`-id, `cluster_id='cluster_kacho_root'`) с **точным** 4-сегментным permission-набором из §2.3 (см. B-02..B-05) — byte-for-byte, отсортировано
**And** созданы AccessBinding'и (SA → backing-роль → cluster-scope) — детерминированные `acb`-id, `ON CONFLICT DO NOTHING`-идемпотентны (точный binding-scope — B-06)
**And** в FGA для каждого модуля, которому нужен FGA-proxy (vpc/compute/nlb), записан ReBAC relation-tuple `service_account:<sva-id>#fga_writer@iam_fgaproxy:system`; для vpc-operator и api-gateway этот tuple **отсутствует** (B-04/B-05).

### Сценарий B-02: compute SA — точный backing permission-набор (least-priv, ни одного лишнего)

**ID:** SEC-C-B-02-SEED-COMPUTE-SA-PERMS (integration)
**Трассировка:** эпик §3.3 «compute SA»; §4.1 п.3.

**Given** seed применён

**When** читаем permissions backing-роли compute-SA

**Then** набор **в точности** (4-сегментный, byte-for-byte, отсортировано) =
  `{vpc.subnets.*.get, vpc.security_groups.*.get, vpc.addresses.*.get, vpc.addresses.*.create, vpc.addresses.*.delete, vpc.addresses.*.update, iam.projects.*.get}`
**And** в FGA присутствует relation-tuple `service_account:<sva-compute>#fga_writer@iam_fgaproxy:system`
**And** в наборе **отсутствуют** `vpc.networks.*.delete`, `vpc.networks.*.create` и любые мутации vpc-сетей (over-grant negative — явный assert «нет permission X»)
**And** каждая строка проходит `iam_permissions_valid` (4-сегментная); 3-сегментная форма (напр. `vpc.subnets.get`) в наборе **отсутствует**
**And** Update/Delete этой системной роли → `FAILED_PRECONDITION`, verbatim «System role» (immutable, как `seed_nlb_roles` 05/06).

### Сценарий B-03: vpc SA — точный backing permission-набор

**ID:** SEC-C-B-03-SEED-VPC-SA-PERMS (integration)
**Трассировка:** эпик §3.3 «vpc SA»; §4.1 п.3.

**Given** seed применён
**When** читаем permissions backing-роли vpc-SA
**Then** набор **в точности** (4-сегментный) = `{compute.zones.*.get, iam.projects.*.get}`
**And** в FGA присутствует relation-tuple `service_account:<sva-vpc>#fga_writer@iam_fgaproxy:system`
**And** в наборе **отсутствуют** любые `compute.instances.*.*` мутации и любые `iam.*` кроме `iam.projects.*.get`.

### Сценарий B-04: nlb SA — точный backing permission-набор (+ fgaproxy)

**ID:** SEC-C-B-04-SEED-NLB-SA-PERMS (integration)
**Трассировка:** эпик §3.3 (nlb-модуль среди модулей с персональным SA); эпик §4 SEC-D (kacho-nlb); §4.1 п.6 (имя `kacho-nlb`).

**Given** seed применён
**When** читаем permissions backing-роли nlb-SA
**Then** набор **в точности** (4-сегментный) = `{vpc.subnets.*.get, iam.projects.*.get}` (точный набор — OQ-C-2, дефолт = минимум под nlb cross-service edge; сверяется ревьюером)
**And** в FGA присутствует relation-tuple `service_account:<sva-nlb>#fga_writer@iam_fgaproxy:system`
**And** SA-имя/SAN-сегмент — **`kacho-nlb`** (канон; не legacy `kacho-loadbalancer`)
**And** в наборе нет ни одной мутации vpc/compute.

### Сценарий B-05: vpc-operator SA — read-only, БЕЗ fgaproxy relation, без мутаций

**ID:** SEC-C-B-05-SEED-OPERATOR-SA-READONLY (integration)
**Трассировка:** эпик §3.3 «kacho-vpc-operator SA: только read-only синк, никаких мутаций».

**Given** seed применён
**When** читаем permissions backing-роли vpc-operator-SA + его relation-tuples
**Then** backing-набор **в точности** (4-сегментный) = `{vpc.subnetses.*.list, vpc.networks.*.get, vpc.network_interfaces.*.get, iam.projectses.*.list}`
**And** в FGA relation-tuple `...#fga_writer@iam_fgaproxy:system` для этого SA **отсутствует** (operator только читает; ресурсы в FGA не регистрирует)
**And** в backing-наборе нет ни одной `*.create/*.update/*.delete` мутации (только `get`/`list`).

### Сценарий B-06: AccessBinding-scope + идемпотентность re-apply (binding-уровень)

**ID:** SEC-C-B-06-SEED-BINDING-SCOPE-IDEMPOTENT (integration)
**Трассировка:** ground-truth `access_bindings` (subject_type/subject_id/role_id/resource_type/resource_id + ON CONFLICT идемпотентность, миграция 0003/0005 scope-колонка).

**Given** seed применён один раз

**When** seed-миграция применяется повторно (re-apply / migrator HA cold-start)

**Then** для каждого module-SA создан ровно **один** AccessBinding `(subject_type='service_account', subject_id=<sva-id>, role_id=<rol-id>, resource_type='cluster', resource_id='cluster_kacho_root')` — cluster-scope (`scope=1`)
**And** повторное применение **не** создаёт дубль (та же `ON CONFLICT`-идемпотентность, что у ролей; binding UNIQUE по `(subject_type, subject_id, role_id, resource_type, resource_id)` → дубль = no-op)
**And** count AccessBinding'ов module-SA после re-apply неизменен (по одному на SA).

### Сценарий B-07: SA с relation `fga_writer` вызывает RegisterResource → разрешено (ReBAC allow)

**ID:** SEC-C-B-07-AUTHZ-ALLOW (integration / e2e)
**Трассировка:** требование #4; эпик §4.1 п.1 (ReBAC relation, не permission-строка).

**Given** caller — vpc-SA (в FGA есть tuple `service_account:<sva-vpc>#fga_writer@iam_fgaproxy:system`), production-mode authz, identity установлена (по client-cert→SA, группа C, либо через тестовый principal-носитель)

**When** caller вызывает `RegisterResource` (валидный payload, A-01)

**Then** authz-gate выполняет ReBAC-Check `service_account:<sva-vpc>` / `fga_writer` / `iam_fgaproxy:system` → ALLOW; RPC отрабатывает по A-01 (sync `OK`, пустой `RegisterResourceResponse{}`)
**And** решение принято **по ReBAC-relation**, а **не** по наличию permission-строки `iam.fgaproxy.write` (такой строки нет — эпик §4.1 п.3).

### Сценарий B-08: SA БЕЗ relation `fga_writer` вызывает RegisterResource → PERMISSION_DENIED (ReBAC deny)

**ID:** SEC-C-B-08-NEG-AUTHZ-DENY (integration / e2e)
**Трассировка:** требование #4 (least-priv эмпирически, эпик I6); §6.7 fail-closed; §4.1 п.1.

**Given** caller — vpc-operator-SA (в FGA **нет** tuple `#fga_writer@iam_fgaproxy:system`, B-05), production-mode authz

**When** caller вызывает `RegisterResource` (валидный payload)

**Then** ReBAC-Check `service_account:<sva-operator>` / `fga_writer` / `iam_fgaproxy:system` → DENY → gRPC `PERMISSION_DENIED` (authz-gate срабатывает до relay; outbox-строка **НЕ** появляется)
**And** в `kacho_iam.fga_outbox` новых строк нет
**And** (anonymous-вариант) anonymous caller в production-mode → `PERMISSION_DENIED` (fail-closed); в dev-mode (`enable=false`, anonymous→full-access) → разрешено (backward-compat, группа D).

### Сценарий B-09: service→service SA освобождён от required_acr_min (эпик §4.1 п.2)

**ID:** SEC-C-B-09-SA-EXEMPT-FROM-ACR (integration)
**Трассировка:** эпик §4.1 п.2 «service→service вызовы (mTLS-SA) освобождены от `required_acr_min`».

**Given** caller — vpc-SA с relation `fga_writer` на `iam_fgaproxy:system`, аутентифицирован по mTLS client-cert (нет user-JWT, нет ACR/MFA-claim'а)

**When** caller вызывает `RegisterResource` (валидный payload)

**Then** ACR-floor (`required_acr_min`) к вызову **не** применяется (SA-аутентификация = mTLS client-cert, у SA нет MFA); вызов проходит ReBAC-гейт и отрабатывает по A-01
**And** (контраст) ACR-floor — это только user-token-флоу; для SA отсутствие ACR-claim'а **не** даёт `PERMISSION_DENIED` (иначе ни один service→service RegisterResource не прошёл бы).

---

## Группа C — client-cert SAN → ServiceAccount mapping (SPIRE-формат)

> Извлечение SAN-строки из client-cert — это **SEC-B** (corelib extractor). SEC-C реализует
> mapping «извлечённый identity-string → ServiceAccount-lookup» и проброс этой identity в ReBAC-гейт (§2.2).
> Формат SAN — **существующий SPIRE-формат** `spiffe://kacho.cloud/ns/<ns>/sa/kacho-<svc>` (эпик §4.1 п.4;
> IAM читает SAN как непрозрачную строку и маппит на детерминированный `sva`-id, OQ-C-5).

### Сценарий C-01: Валидный client-cert SAN (SPIRE-формат) → распознан как module-SA

**ID:** SEC-C-C-01-CERT-TO-SA-OK (integration)
**Трассировка:** требование #4; эпик §4.1 п.4; §6.3.

**Given** kacho-iam с mTLS-enable на internal listener (SEC-B creds, per-edge флаг), client-cert модуля vpc с SAN `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-vpc`
**And** ServiceAccount `kacho-vpc` (`sva`-id из B-01) существует (seed)

**When** vpc-модуль вызывает `RegisterResource` по mTLS (client-cert предъявлен)

**Then** IAM сопоставляет SAN `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-vpc` → ServiceAccount `<sva-vpc>` (детерминированно, OQ-C-5) и резолвит его как ReBAC-subject `service_account:<sva-vpc>`
**And** caller-identity для authz-gate = этот SA (далее по B-07 — relation `fga_writer` присутствует → allow).

### Сценарий C-02: client-cert SAN ссылается на несуществующий SA → PERMISSION_DENIED (fail-closed)

**ID:** SEC-C-C-02-NEG-CERT-UNKNOWN-SA (integration)
**Трассировка:** §6.7 fail-closed; data-integrity cross-domain «не найдено → отказ».

**Given** mTLS-enable, client-cert с SAN `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-unknown` (well-formed SPIRE-формат, но такого SA нет в `kacho_iam`)

**When** caller вызывает `RegisterResource`

**Then** ответ — gRPC `PERMISSION_DENIED` (identity не резолвится в известный SA → fail-closed; не INTERNAL, не «анонимный full-access» в production-mode)
**And** outbox-строка не появляется.

### Сценарий C-03: client-cert SAN в нераспознаваемом формате → PERMISSION_DENIED

**ID:** SEC-C-C-03-NEG-CERT-MALFORMED-SAN (integration)
**Трассировка:** эпик §4.1 п.4 «IAM читает SAN как непрозрачный identity-string»; fail-closed.

**Given** mTLS-enable, client-cert с SAN, который не парсится как `spiffe://kacho.cloud/ns/<ns>/sa/kacho-<svc>` (напр. `spiffe://other-trust-domain/x`, чужой trustDomain, или произвольная строка)

**When** caller вызывает `RegisterResource`

**Then** ответ — gRPC `PERMISSION_DENIED` (нераспознанный identity → не маппится в SA → fail-closed)
**And** (boundary) точная грань «malformed vs unknown» — обе ветки fail-closed; различие только в логе.

### Сценарий C-04: Оба слоя identity логируются (cert-identity модуля + propagated principal)

**ID:** SEC-C-C-04-AUDIT-DUAL-IDENTITY (integration)
**Трассировка:** эпик §3.1 invariant I2 «cert-identity (модуль) и principal (пользователь) логируются ОБА».

**Given** mTLS-enable; vpc-модуль вызывает `RegisterResource` по mTLS, неся в metadata propagated principal конечного пользователя (`x-kacho-principal-*`, инициатор Create ресурса)

**When** RPC обрабатывается

**Then** в audit/structured-log IAM присутствуют **оба**: cert-identity модуля (SAN `…/sa/kacho-vpc` → `<sva-vpc>`) **и** propagated principal пользователя
**And** authz-решение FGA-proxy опирается на **cert-identity модуля** (его relation `fga_writer`), а **не** на principal пользователя — это ортогональные слои (I2); principal пользователя — для трассировки/аудита, не для gate этого Internal RPC.

### Сценарий C-05: principal-metadata доверяется только при пройденном mTLS client-cert verify (invariant I2)

**ID:** SEC-C-C-05-PRINCIPAL-TRUST-REQUIRES-MTLS (integration)
**Трассировка:** эпик §3.1 invariant I2 «internal listener доверяет principal-metadata ⟺ peer прошёл mTLS client-cert verify».

**Given** internal listener с mTLS-enable (production-mode)

**When / Then:**
  - **C-05a** peer **прошёл** mTLS client-cert verify (cert из internal CA) → принесённая им `x-kacho-principal-*` metadata **доверяется** (используется для аудита C-04)
  - **C-05b** (boundary, dev-mode `enable=false`) mTLS выключен → текущее поведение сохраняется (principal-metadata принимается как сегодня, anonymous→full-access) — backward-compat, группа D
**And** при mTLS-enable handshake-fail (cert не из internal CA / нет cert) → соединение отклоняется на транспортном уровне (SEC-B creds, `RequireAndVerifyClientCert`), RPC не доходит до handler.

---

## Группа D — opt-in / backward-compat (enable=false = текущее поведение)

### Сценарий D-01: mTLS-enable=false (dev) — service→service insecure, текущее поведение

**ID:** SEC-C-D-01-MTLS-OFF-BACKWARD-COMPAT
**Трассировка:** требование #1; эпик §3.2 «enable=false → текущий insecure»; DoD «enable=false — dev работает как сейчас».

**Given** kacho-iam с TLSServer.enable=false на internal listener (dev-дефолт)

**When** module-сервис вызывает `RegisterResource` без client-cert (insecure, как сегодня), dev-mode authz (anonymous→full-access)

**Then** RPC обрабатывается без mTLS (соединение не требует cert); identity не из cert, а текущим путём (principal-metadata / anonymous)
**And** authz-gate в dev-mode не блокирует anonymous (backward-compat); RPC отрабатывает по A-01
**And** **никакой** существующий dev-флоу/тест не ломается фактом наличия новых RPC.

### Сценарий D-02: production-mode authz + mTLS-enable=true — fail-closed

**ID:** SEC-C-D-02-PROD-FAIL-CLOSED
**Трассировка:** требование #1/#3/#4; §6.7; §4.1 п.1.

**Given** kacho-iam: `KACHO_IAM_AUTH_MODE=production`, internal listener mTLS-enable=true

**When / Then:**
  - module-SA с валидным cert + relation `fga_writer` на `iam_fgaproxy:system` → allow (A-01)
  - anonymous (нет cert) → транспорт отклоняет handshake; если как-то прошёл — `PERMISSION_DENIED` (fail-closed)
  - cert валиден, но SA без relation `fga_writer` → `PERMISSION_DENIED` (B-08).

### Сценарий D-03: Per-edge независимое включение (rollback-safe)

**ID:** SEC-C-D-03-PER-EDGE-FLAG
**Трассировка:** решение §6.5 (per-edge feature-flag); §6.7.

**Given** kacho-iam internal listener mTLS-enable конфигурируется независимым per-edge `enable`

**When** ребро `vpc→iam` включено в mTLS, а другое ребро ещё нет (mismatch)

**Then** mismatch (одна сторона ждёт mTLS, другая insecure) детектируется как `Unavailable` на mismatch-ребре (не «тихо в insecure») — соответствует §6.5; SEC-C-сторона: IAM с mTLS-required отклоняет insecure-peer
**And** включённое ребро работает; не-включённые — текущим insecure-путём (rollback = выключить флаг).

### Сценарий D-04: FGA недостижим вне IAM — на уровне SEC-C (контракт «FGA за IAM»)

**ID:** SEC-C-D-04-FGA-ONLY-VIA-IAM
**Трассировка:** требование #6; эпик §3.1 (NetworkPolicy — SEC-F, но контракт «модуль ходит в FGA только через IAM-RegisterResource» закрепляется здесь).

**Given** SEC-C предоставляет единственный санкционированный путь модуля к owner-tuple-записи: `InternalIAMService.RegisterResource`/`UnregisterResource` (закрытые ReBAC-relation `fga_writer`)

**When / Then:**
  - единственный способ для модуля повлиять на FGA-tuple ресурса — вызвать эти Internal RPC; IAM — единственный, кто пишет в OpenFGA напрямую (как сегодня)
  - сетевая изоляция OpenFGA (ingress только из kacho-iam pod, NetworkPolicy) — **SEC-F**, включается после переключения модулей (эпик §3.1); SEC-C фиксирует **контракт** «FGA за IAM», network-enforcement — позже
**And** (boundary) удаление прямого FGA-клиента в самих vpc/compute/nlb — **SEC-D** (consumer-сторона), здесь не делается.

---

## Out of scope (явно — не tech-debt)

| Что | Куда |
|---|---|
| proto `RegisterResource`/`UnregisterResource` + проставление `permission="<exempt>"` + объявление FGA-типа `iam_fgaproxy`/relation `fga_writer` в authorization-model (buf lint/breaking) | **SEC-A** (kacho-proto) |
| corelib mTLS-creds (TLSServer/TLSClient) + cert-SAN-extractor (парсинг `spiffe://kacho.cloud/ns/<ns>/sa/<name>`) | **SEC-B** (kacho-corelib) |
| Удаление `openfga_write_client.go`/`fgawrite.Emit` в vpc/compute/nlb + outbox-intent в writer-tx ресурса + drainer→IAM.RegisterResource + миграция outbox в этих репо | **SEC-D** |
| api-gateway mTLS backend-dial | **SEC-E** |
| cert-manager PKI (переиспользовать `kacho-selfsigned` ClusterIssuer), per-svc Certificate ×2 (SAN в SPIRE-формате), helm mTLS-values, NetworkPolicy openfga←iam, SA-seed helm-wiring, kube-labels `app.kubernetes.io/*` | **SEC-F** (kacho-deploy) |
| vpc-operator + kube-ovn на mTLS; spire-registration legacy `kacho-loadbalancer`→`kacho-nlb` выравнивание | **SEC-G** / **SEC-F** (deploy) |
| Hot-reload cert по file-watch (restart-on-rotate для MVP — §6.2) | follow-up (после SEC-F) |
| Полный generic outbox-drainer (уже есть — W1.1) | **W1.1** (потребляется AS-IS) |

---

## Definition of Done (подфаза SEC-C)

- [ ] `acceptance-reviewer` ✅ APPROVED данного дока (gate, ban #1); `system-design-reviewer` — на A-06/A-07/C-05 (идемпотентность/fail-safe/trust-invariant).
- [ ] OQ-C-1..OQ-C-5 — дефолты приняты в §2.5 (sign-off ревьюера на форму tuple OQ-C-1); **OQ-C-6 закрыт** (§2.2: exempt-proto + ReBAC `fga_writer`).
- [ ] Ветка `KAC-<N>` в `kacho-iam`; SEC-A (proto + authorization-model `iam_fgaproxy`/`fga_writer`) + SEC-B (corelib) уже в `main` либо запиннены feature-ветками (кросс-репо порядок, `polyrepo.md`).
- [ ] **RED phase**: integration + newman тесты §7 написаны и прогнаны RED **до** кода (RED→GREEN-пара в PR).
- [ ] **GREEN phase**:
  - [ ] `RegisterResource`/`UnregisterResource` use-case + handler (Internal listener :9091; tuple-INSERT в `fga_outbox` в одной writer-tx; **sync** возврат пустого `RegisterResourceResponse{}`/`UnregisterResourceResponse{}`, gRPC `OK` — ground-truth SEC-A proto, не Operation).
  - [ ] Идемпотентность как контракт (повтор→OK, не AlreadyExists/NotFound) — опирается на drainer `fga_applier.go` already_exists/cannot_delete→ErrAlreadyApplied.
  - [ ] **ReBAC authz-gate** на оба RPC: cert-SAN→SA → `Check(service_account:<sva>, fga_writer, iam_fgaproxy:system)` (§2.2; **не** permission-строка).
  - [ ] service→service SA освобождены от `required_acr_min` (B-09).
  - [ ] Seed-миграция (новая goose; ban #5): 5 module-SA + 5 backing-ролей (4-сегментные permission-строки из каталога) + AccessBinding'и (cluster-scope) + FGA relation-tuples `<sva>#fga_writer@iam_fgaproxy:system` для vpc/compute/nlb; детерминированные `sva`/`rol`/`acb`-id, `ON CONFLICT (id) DO NOTHING`, immutable system-role.
  - [ ] cert-SAN→SA mapping (потребляет SEC-B extractor; формат `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-<svc>`; OQ-C-4/OQ-C-5 решения) + проброс identity в ReBAC-гейт.
  - [ ] internal-mux регистрация RegisterResource/Unregister (через `api-gateway-registrar`, только internal listener; ban #6) — координация в SEC-E/SEC-F wiring, но IAM-сторона RPC готова здесь.
- [ ] Integration (testcontainers Postgres 16 + FGA-stub/контейнер) покрывает A-01..A-09, B-01..B-09, C-01..C-05, D-01..D-04 (1:1, §7).
- [ ] **Concurrent race-тест A-06 обязателен** (ban #10) — без него merge запрещён.
- [ ] **Fail-safe тест A-07** (FGA down + рестарт реплики → intent не теряется, §6.2) обязателен (эпик ключевое требование).
- [ ] **4-сегментная permission-грамматика**: backing-роли проходят `iam_permissions_valid`; integration-assert B-02..B-05 — byte-for-byte против строк из `permission_catalog.json` (промотированных в `module.resource.*.verb`).
- [ ] Newman: ≥1 happy + ≥1 negative per RPC через internal-mux (RegisterResource OK / PERMISSION_DENIED / INVALID_ARGUMENT); least-priv матрица (SA с/без relation `fga_writer`).
- [ ] Финальная верификация: `go test ./... -race` + `golangci-lint run` + `govulncheck` + newman зелёные (`.claude/rules/testing.md`).
- [ ] Vault-trail обновлён: `rpc/iam-internal-iam-service.md` (новые RegisterResource/Unregister, exempt+ReBAC `fga_writer`), `resources/iam-service-account.md` (module-SA + ReBAC relation-tuples + backing 4-сегментные роли + SAN-mapping), `edges/`-запись «module→iam fgaproxy» (усиление vpc→iam / compute→iam / nlb→iam; `polyrepo.md`), `KAC/KAC-<N>.md` trail + PR-URL + status.
- [ ] YouTrack SEC-C subtask: To do → In Progress → Test → Done с артефактами (PR-URL, тест-логи).

---

## Тесты (TDD-red список — основа `integration-tester`; 1:1 на ID-сценарий)

**Integration (kacho-iam, testcontainers Postgres 16 + FGA-stub):**
- `internal/service/register_resource_integration_test.go` — A-01, A-02, A-03, A-04, A-05(a-d), A-09.
- `internal/service/register_resource_concurrency_integration_test.go` — A-06 (concurrent goroutines, ровно один tuple).
- `internal/service/register_resource_failsafe_integration_test.go` — A-07 (FGA 5xx → intent персистит + рестарт реплики, §6.2), A-08 (poison).
- `internal/repo/kacho/pg/seed_module_sa_identity_integration_test.go` — B-01..B-06 (детерминированные `sva`/`rol`/`acb`-id, 4-сегментные permission-наборы byte-for-byte, ReBAC relation-tuples, immutable, ON CONFLICT идемпотентность binding-уровня).
- `internal/service/fgaproxy_authz_rebac_integration_test.go` — B-07 (ReBAC allow), B-08 (ReBAC deny без `fga_writer`), B-09 (SA exempt от required_acr_min).
- `internal/authzguard/cert_to_sa_integration_test.go` — C-01, C-02, C-03, C-05 (SPIRE-формат mapping + fail-closed + trust-invariant); C-04 (dual-identity log assert).
- `internal/service/fgaproxy_backward_compat_integration_test.go` — D-01, D-02, D-03, D-04 (enable=false/true, per-edge, контракт FGA-за-IAM).

**Newman (tests/newman/cases/sec-c-*.py → gen.py; через internal-mux):**
- `sec-c-register-resource-ok.py` — A-01 happy (sync `OK`, FGA-Check ALLOW).
- `sec-c-register-resource-idempotent.py` — A-02 (повтор → OK, не AlreadyExists).
- `sec-c-unregister-resource-ok.py` + `sec-c-unregister-idempotent.py` — A-03, A-04.
- `sec-c-register-invalid-arg.py` — A-05 negative.
- `sec-c-fgaproxy-rebac-denied.py` — B-08 negative (SA без relation `fga_writer` → PERMISSION_DENIED).
- `sec-c-fgaproxy-rebac-allow.py` — B-07 happy (SA с relation `fga_writer`).
- `sec-c-register-internal-only.py` — A-09a (external → не доступно) negative.

> Все тесты пишутся и прогоняются **RED до** кода (ban #12); RED→GREEN-пара — в PR-описании.
