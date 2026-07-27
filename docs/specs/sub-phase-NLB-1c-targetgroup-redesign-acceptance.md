# Sub-phase NLB-1c (TargetGroup redesign) — Acceptance

> Статус: **✅ APPROVED** (acceptance-reviewer carve-review, 2026-07-20 — 11 сценариев, партиция 58/58 verified)
> Дата: 2026-07-20
> Ревьюер: acceptance-reviewer — ✅ APPROVED (carve-partition 58/58; non-blocking notes в review-comment)
> Эпик/тикет: KAC-NLB-1 · под-фаза **1c of 4** (carve родительского APPROVED `sub-phase-NLB-1-lb-listener-targetgroup-acceptance.md`)
> Монорепо: `project/kacho` (`github.com/PRO-Robotech/kacho`) — легаси `project/kacho-*` не затрагивается.
> Порядок carve: NLB-1a → NLB-1b → **NLB-1c (это)** → NLB-1d. **Предпосылка: NLB-1b merged.**

## Обзор

NLB-1c завершает редизайн `TargetGroup` — третьего ядрового ресурса `kacho-nlb`. **Идёт строго
ПОСЛЕ 1b** по причине из родительской цепочки зависимостей: HealthCheck-redesign удаляет
`HealthCheck.name`, что сломало бы `attach_target_group.go` в LB — этот файл **удалён в 1b**
(снятие M:N-pivot), поэтому HealthCheck-redesign безопасен только теперь. «Clean HC redesign
presupposes pivot removal presupposes VIP relocation» — 1b снял pivot и VIP-на-LB, 1c кладёт HC.

К моменту старта 1c уже приземлены (1b): `Listener.targetGroupId` FK RESTRICT, `resolvedBackendPort°`
(эхо `TargetGroup.port`), **net-new bare-поле `TargetGroup.port` + required-BVA** (co-req 1b). 1c
редизайнит **собственную форму TargetGroup**:

1. **HealthCheck oneof-replace** — снять AS-IS `name`/id (embedded value-object, **не** ресурс);
   oneof расширить `tcp` / `http{path,expectedCodes,host,headers}` / `https{...}` / `grpc{serviceName}`;
   `probe.port` наследует `TargetGroup.port` отсутствием → `effectivePort°`. Дисциплина oneof-replace:
   scalar dotted-mask PATCH merge-validated + probe atomic-replace **c сохранением sibling-скаляров**.
2. **duration-строки [B8]** — AS-IS `deregistration_delay_seconds int32`/`slow_start_seconds int32`
   → `deregistrationDelay`/`slowStart` под `google.protobuf.Duration` (nlb-канон модуля).
3. **immutables** `regionId`/`projectId` (region-scoped, LB-agnostic reusable); **teardown RESTRICT**
   blocker-list на `TargetGroup.Delete` (FK RESTRICT создан в 1b — 1c финализирует friendly precheck).
4. **port LIVE-mutability** — `TargetGroup.port` (bare-поле из 1b) становится LIVE-mutable c
   **re-echo** в `Listener.resolvedBackendPort°` (cross-resource ripple).
5. **one-shot inline `targetGroup{port, healthCheck}` config-only** — one-shot оркестрация LB.Create
   (из 1b) расширяется приёмом inline redesigned-TG (без `targets[]`; targets → NLB-2).

Owner-side под-фаза: сценарии описывают наблюдаемое поведение публичного `TargetGroupService`
(:9090 → edge REST) + расширение one-shot `NetworkLoadBalancerService.Create` на inline redesigned-TG.

---

## Scope

| # | Фича | Родительские сценарии |
|---|---|---|
| F6 | TargetGroup.Create c `port`+redesigned `healthCheck`; region-scoped **LB-agnostic reusable**; `effectivePort°`; HealthCheck oneof-replace (scalar dotted-mask PATCH merge-validated + probe atomic-replace scalar-preservation); `port` LIVE-mutable re-echo; immutables; teardown RESTRICT blocker-list; duration-строки [B8] | NLB-1-34, 36, 37, 38, 39, 40, 41, 42, 56 |
| F7-inline | one-shot inline `targetGroup{port, healthCheck}` config-only → standalone reusable TG; inline `targets[]` → defer NLB-2; inline TG без `port` → `INVALID_ARGUMENT` | NLB-1-57, 58 |

## Out-of-scope (следующая под-фаза — NLB-1d)

**→ NLB-1d (gateway/newman/cross-cutting verification):**
- **Cross-cutting e2e-smoke** (полный one-shot LB+listener+**inline-TG** через real gateway),
  **two-projection field-absence** (public TG НЕ несёт инфра-полей — Internal-проекция NLB-3),
  **umbrella newman closeout / parallel-safety**, **authz-matrix cross-account**, **read-your-writes
  budget-verification**. *(NB: per-RPC gateway-регистрация нового TargetGroup RPC-surface — в **том
  же PR** 1c, через `api-gateway-registrar`; 1d — финализация/аудит.)*

**Прямо вне NLB-1 (родитель §Out-of-scope) → NLB-2:**
- **Target-membership любого рода** — inline `targets[]` в TG.Create / listenerSpec.targetGroup,
  4-way identity (`instance`/`nic`/`ipRef`/`externalIp`), resolution, `targetRefState`/`servingTraffic`,
  health-**пробы**. В 1c `healthCheck` — **только валидируемый config на write** (пробы не стреляют).
  wired-listener → TG с **пустым пулом** резолвится (`substatus OK`) — status-рекомпут таргетов не требует.
- **Runtime health-проекция** (`GetTargetStates`, `lastProbe`, `summary`) — NLB-2.
- **TG zone-coherence на wire к ZONAL-LB / region-coherence таргетов** — NLB-2 (в 1c TG LB-agnostic
  region-coherence с LB — на Listener-wire, F4/NLB-1-23, уже 1b).

## Traceability-легенда

`°` = output-only. REST `/nlb/v1/…` (:9090). JSON camelCase. Timestamps усечены до секунд (incl.
embedded `HealthCheck`-под-запись). Каноническое существительное — **TargetGroup**; error-тон
`"<Resource> <id> not found"` / `"<field> is immutable after TargetGroup.Create"`; teardown-precheck
— литеральный текст (часть контракта). **[B8]** duration-конвенция (nlb-канон).

---

## F6 — TargetGroup: region-scoped LB-agnostic reusable; redesigned HealthCheck oneof-replace; port LIVE-mutable; teardown RESTRICT; durations

> `→ родитель F6` · `→ api-conventions.md §update_mask discipline`
> **AS-IS:** `TargetGroup` region-scoped (`region_id = 7`), embedded `HealthCheck health_check = 10`,
> `deregistration_delay_seconds int32`/`slow_start_seconds int32`. **`port` net-new — приземлён в 1b**
> (co-req). `HealthCheck` AS-IS несёт `name` (**required**) + oneof `tcp_options{port}`/`http_options
> {port,path}`. Редизайн (1c): HealthCheck теряет `name`/id (embedded value-object), oneof расширяется
> `tcp`/`http{path,expectedCodes,host,headers}`/`https{...}`/`grpc{serviceName}`; `probe.port` наследует
> `TG.port` отсутствием → `effectivePort°`; duration-строки (B8). Удаление `attach_target_group.go`
> в 1b **разблокировало** снятие `HealthCheck.name`.

### Сценарий NLB-1-34: happy — TargetGroup.Create c `port` + redesigned `healthCheck`; region-scoped reusable

**ID:** NLB-1-34

**Given** проект `prj-f9k2m4x7q1w8r3n5`, регион `eu-north` существуют; вызывающий — editor проекта

**When** `TargetGroupService.Create` (`POST /nlb/v1/targetGroups`) c payload:
  - `projectId`, `regionId = "eu-north"`, `name = "web-backends"`
  - `port = 8080`
  - `healthCheck = { interval:"2s", timeout:"1s", healthyThreshold:2, unhealthyThreshold:2, http:{ path:"/healthz", expectedCodes:"200-299" } }`  *(redesigned — БЕЗ `name`)*

**Then** после `done` `Get` TG отдаёт `port == 8080` (единственный backend-порт пула), `regionId == "eu-north"`, `healthCheck.effectivePort° == 8080` (`probe.port` опущен → наследует `TG.port`), `status == "ACTIVE"`; `healthCheck` **не** несёт `name`/id (embedded value-object)
**And** TG **LB-agnostic**: та же TG может быть wired несколькими listener'ами разных LB (region-coherence, не привязка к LB); zone-coherence — на wire к ZONAL-LB (→ NLB-2)

### Сценарий NLB-1-36: HealthCheck скалярный dotted-mask PATCH — merge-validated

**ID:** NLB-1-36

**Given** TG c `healthCheck = { interval:"2s", timeout:"1s", healthyThreshold:2, unhealthyThreshold:2, http:{...} }`

**When** `TargetGroupService.Update` c `updateMask="healthCheck.interval"`, `healthCheck.interval="3s"`

**Then** **частичный мёрж** (проба не трогается); валидируется **МЕРЖ**: `interval="3s"` перевалидируется против **хранимого** `timeout="1s"` (`timeout < interval` на смёрженном объекте — ok); `probe`-тип и sibling-скаляры целы
**And** нарушение cross-field (`timeout="4s"` при `interval="2s"`, `timeout < interval` ложно) → `INVALID_ARGUMENT`; bounds `interval∈[1s,300s]`, threshold `2..10`

### Сценарий NLB-1-37: HealthCheck probe atomic-replace — sibling-скаляры уцелевают при смене типа пробы

**ID:** NLB-1-37

**Given** TG c `healthCheck = { interval:"3s", timeout:"1s", healthyThreshold:5, unhealthyThreshold:4, http:{path:"/healthz",...} }` (тюненые скаляры)

**When** `TargetGroupService.Update` c `updateMask="healthCheck.grpc"`, `healthCheck.grpc={serviceName:"grpc.health.v1.Health"}` (смена пробы http→grpc)

**Then** **atomic-replace** скоупится **ровно в probe-oneof**: проба становится `grpc`, а sibling-скаляры (`interval:"3s"`, `timeout:"1s"`, `healthyThreshold:5`, `unhealthyThreshold:4`) **переживают** смену (не сбрасываются в дефолт — regression-lock «probe-type switch preserves tuned scalars»)
**And** `effectivePort° == TG.port` (grpc-проба без `port`-override)

### Сценарий NLB-1-38 (negative): маска на пробу без дискриминатора → `INVALID_ARGUMENT` (не silent-clear)

**ID:** NLB-1-38

**When** `TargetGroupService.Update` c `updateMask="healthCheck.http"` (или generic `healthCheck` c probe-oneof), но **тело пробы пусто** / дискриминатор не задан

**Then** `INVALID_ARGUMENT` — при atomic-replace пробы дискриминатор (`http`/`tcp`/`grpc`/`https`) **обязан** присутствовать; **НЕ** silent-clear пробы

### Сценарий NLB-1-39: `probe.port` override → `effectivePort°` отражает override

**ID:** NLB-1-39

**Given** TG c `port=8080`

**When** `TargetGroupService.Update` c `healthCheck.https={ port:8443, path:"/healthz", expectedCodes:"200,204" }` (явный probe-port override)

**Then** `Get` TG отдаёт `healthCheck.effectivePort° == 8443` (override пробы); backend-`port` пула остаётся `8080` — расхождение probe-vs-traffic **видимо by construction**

### Сценарий NLB-1-40 (negative): `regionId`/`projectId` immutable в Update TG

**ID:** NLB-1-40

**Given** TG `tgr-2w8r4t6y1u3i5o7p` c `regionId="eu-north"`, `projectId="prj-…"`

**When** `TargetGroupService.Update` c `updateMask="regionId"` (или `projectId`)

**Then** **reject ДО `UpdateMask`** → `INVALID_ARGUMENT "<field> is immutable after TargetGroup.Create"` (TG region-scoped immutable)

### Сценарий NLB-1-41 (negative): Delete TG, на которую ссылается listener → `FAILED_PRECONDITION` (RESTRICT, blocker-list)

**ID:** NLB-1-41

**Given** TG `tgr-2w8r4t6y1u3i5o7p` wired listener'ом `lst-7h3k9m2x4q8w1t0y` (FK RESTRICT — создан в 1b)

**When** `TargetGroupService.Delete`

**Then** `FAILED_PRECONDITION "target group is referenced by listeners: [lst-7h3k9m2x4q8w1t0y]"` (RESTRICT product-decision, precheck **перечисляет** блокирующие id, чтобы порядок не угадывался); Delete проходит только после смены/обнуления `targetGroupId` всех ссылающихся listener'ов

### Сценарий NLB-1-42: `deregistrationDelay`/`slowStart` — duration-строки (B8), LIVE-mutable

**ID:** NLB-1-42

> **AS-IS:** `deregistration_delay_seconds int32` (0-3600), `slow_start_seconds int32` (0-900) — **scalar секунды**. Редизайн: duration-строки под `google.protobuf.Duration` (**B8** nlb-канон). `interval`/`timeout` уже AS-IS Duration.

**When** `TargetGroupService.Update` c `updateMask="deregistrationDelay"`, `deregistrationDelay="300s"` (duration-строка)

**Then** после `done` `Get` TG отдаёт `deregistrationDelay == "300s"`, `slowStart == "0s"` (duration-строки, не int-секунды); bounds `deregistrationDelay∈[0s,3600s]`, `slowStart∈[0s,900s]`
**And** **[B8]** это breaking proto-change (int32-seconds → Duration); nlb — duration-канон модуля

### Сценарий NLB-1-56: `TargetGroup.port` LIVE-mutable → wired-listener `resolvedBackendPort°` ре-эхается

**ID:** NLB-1-56

> **Co-req из 1b:** bare-поле `port` + BVA приземлены в 1b; **LIVE-mutability + cross-resource re-echo** — 1c.

**Given** TG `tgr-2w8r4t6y1u3i5o7p` c `port=8080`, на неё wired listener `lst-7h3k9m2x4q8w1t0y` (`resolvedBackendPort° == 8080`, F4/NLB-1-19 из 1b)

**When** `TargetGroupService.Update` c `updateMask="port"`, `port=9090` (LIVE-mutable)

**Then** после `done` `Get` TG отдаёт `port == 9090`; `Get` wired-listener'а отдаёт **ре-эхнутый** `resolvedBackendPort° == 9090` (единственная LIVE-mutable-мутация, рябящая в derived-поле другого ресурса); `healthCheck.effectivePort°` следует `TG.port` (если `probe.port` не override)
**And** это отличается от repoint listener'а (NLB-1-22 из 1b, где меняется сама ссылка) — здесь меняется backend-порт **той же** TG

---

## F7-inline — one-shot inline `targetGroup{port, healthCheck}` config-only (расширение one-shot из 1b)

> `→ родитель F7 (NLB-1-57/58)` · One-shot **оркестрация** LB.Create доказана в 1b (NLB-1-43, existing
> `targetGroupId`). 1c расширяет её приёмом inline **redesigned** `targetGroup{port, healthCheck}`
> (config-only, без `targets[]`). TG без таргетов — валидный config-объект: wired-listener резолвит
> пустой пул → `substatus OK` → LB `ACTIVE` (согласуется с NLB-1-17 из 1b). Полный one-shot c inline
> `targets[]` + saga-compensation → **NLB-2**.

### Сценарий NLB-1-57: happy — one-shot inline `targetGroup{port, healthCheck}` config-only → standalone reusable TG создаётся

**ID:** NLB-1-57

**Given** TG нет заранее; проект+регион ok; вызывающий — editor проекта

**When** `NetworkLoadBalancerService.Create` c `placement="EXTERNAL_REGIONAL"`, `regionId="eu-north"` и
  - `listenerSpecs = [ { name:"tcp-443", port:443, protocol:"TCP", ipVersion:"IPV4", targetGroup:{ port:8080, healthCheck:{ interval:"2s", timeout:"1s", healthyThreshold:2, unhealthyThreshold:2, tcp:{} } } } ]`  *(redesigned inline TG — БЕЗ `name`)*

**Then** сервер разворачивает **в одной Operation** в dependency-порядке: TG (config-only, без таргетов) → listener wired на неё → VIP-сага; после `done` созданная TG **Get-able как standalone reusable region-scoped ресурс** со своим `tgr-`-id (не «скрытый child»); listener `substatus=OK`, `resolvedBackendPort°=8080`; LB `status=ACTIVE`
**And** созданная TG переиспользуема (LB-agnostic) — на неё может навестись другой listener/LB (NLB-1-34)

### Сценарий NLB-1-58 (negative): inline `targetGroup` c `targets[]` → defer NLB-2; inline TG без `port` → `INVALID_ARGUMENT`

**ID:** NLB-1-58

**Given** граница NLB-1/NLB-2: target-membership (4-way identity) — NLB-2

**When** клиент шлёт one-shot c inline `targetGroup{ port:8080, targets:[{instance:{id:"ins-…"}}] }` (targets внутри inline-TG)

**Then** **отклоняется в NLB-1** — inline `targets[]` не поддержан (targets → NLB-2 `:addTargets`; сообщение actionable: добавить таргеты после создания через `TargetGroupService.AddTargets`); реализация NLB-1 принимает inline `targetGroup` **только** c `{port, healthCheck}`
**And** inline `targetGroup` **без** обязательного `port` → `INVALID_ARGUMENT` (`port` — required-поле пула, NLB-1-35 из 1b)

---

## Definition of Done (NLB-1c)

Production-complete в границах TargetGroup redesign (`ai-tooling.md` §lifecycle, `testing.md`, `security.md`):

**Traceability + тесты (1-to-1, TDD ban #12):**
- [ ] Каждый carve-сценарий (NLB-1-34, 36..42, 56, 57, 58) имеет зелёный **integration-тест** (testcontainers Postgres 16), `TestTargetGroup_NLB_1_NN` — SQL-сторона, incl. teardown-RESTRICT (FK 23503→FailedPrecondition), oneof-replace merge-validation, port LIVE-mutable re-echo.
- [ ] Каждый (наблюдаемый через api-gateway) — зелёный **newman-кейс** `# verifies NLB-1-NN` (≥1 happy + ≥1 negative per фича); `{{runId}}`-суффикс; op-poll `!op.error` перед извлечением id из `metadata`.
- [ ] RED (падает по нужной причине) ДО кода; пара RED→GREEN в PR.
- [ ] read-your-writes: первый Get/Update/Delete своей свежей TG обёрнут `retry_until_authorized` (owner-tuple EC-окно, conv-3); негативы **НЕ** оборачивать.
- [ ] **Regression-lock (behaviour-level):** NLB-1-37 «probe-type switch preserves tuned scalars» (assert конкретные скаляры уцелели, не только код); NLB-1-56 «TG.port ripple → listener.resolvedBackendPort°» (assert re-echo значение).

**Deliverables редизайна:**
- [ ] **TargetGroup HealthCheck:** снять `name`/id → oneof расширить (`tcp`/`http{path,expectedCodes,host,headers}`/`https`/`grpc{serviceName}`); `probe.port` наследует `TG.port` → `effectivePort°`; oneof-replace дисциплина (scalar dotted-mask PATCH merge-validated + probe atomic-replace scalar-preservation; маска на пробу без дискриминатора → `INVALID_ARGUMENT`, не silent-clear).
- [ ] **[B8]** `deregistration_delay_seconds`/`slow_start_seconds` int32 → `deregistrationDelay`/`slowStart` **duration-строки**.
- [ ] **immutables** `regionId`/`projectId` (immutable-switch ДО `UpdateMask`); **teardown RESTRICT** friendly blocker-list на `TargetGroup.Delete` (FK создан в 1b — 1c финализирует precheck-текст).
- [ ] **`TargetGroup.port` LIVE-mutable** + re-echo `Listener.resolvedBackendPort°`.
- [ ] **one-shot inline `targetGroup{port, healthCheck}`** (redesigned-shape, config-only, без `targets[]`) → standalone reusable TG; inline `targets[]` → actionable-reject (defer NLB-2); inline TG без `port` → `INVALID_ARGUMENT`.
- [ ] **Не** редактировать применённые миграции — только новые (продолжение `0015+` из 1b): HealthCheck restructure (drop `name`, oneof-расширение), durations-column type change, TG.port LIVE-mutable (снятие immutable-guard если ставился в 1b).

**Проектные гейты:**
- [ ] `go test ./... -race` · `golangci-lint run` · `govulncheck` · `make -C services/nlb audit-list-filter` зелёные.
- [ ] proto — `buf lint`/`buf breaking` (breaking задекларированы: HealthCheck `name`-drop + oneof-расширение, duration-rename) зелёные после регена. proto ревьюит `proto-api-reviewer`; миграции — `db-architect-reviewer`; oneof-replace merge-семантика — `go-style-reviewer`.
- [ ] `make -C gateway permission-catalog-check` byte-identical (TargetGroup RPC — записи есть, ключёваны на `nlb_target_group` из 1a).
- [ ] authz на КАЖДОМ RPC (`nlb_target_group`-тип из 1a): read → viewer-floor, мутации → editor на target, Create → editor на project; `scope_extractor{nlb_target_group, target_group_id}` резолвит target→project; `List` (TG) фильтруется listauthz + pagination-validate ДО listauthz (тот же контракт, что NLB-1-48 в 1b). Per-RPC gateway-регистрация нового TargetGroup RPC-surface — **в этом PR** (`api-gateway-registrar`).

**MERGE-GATE:** 1c наследует Phase-0 MERGE-GATE из 1b (B1 `common.v1`-Referrer для HealthCheck-эмбеддинга не требуется — HealthCheck value-object; B3 hyphen id-prefix; conv-11 by-lane касается peer-validate scope-coord — в 1c нет новых peer-validate lane сверх 1b). Ungated (HealthCheck oneof-replace, durations, immutables, teardown RESTRICT, port LIVE-mutable, inline config-only TG) строятся **без** ожидания change-set.

---

## Traceability-таблица (родитель → NLB-1c)

| Родительский | Фича | Тип |
|---|---|---|
| NLB-1-34 | F6 TG.Create port+redesigned healthCheck; reusable | happy |
| NLB-1-36 | F6 HealthCheck dotted-mask PATCH merge-validated | happy |
| NLB-1-37 | F6 probe atomic-replace scalar-preservation | happy |
| NLB-1-38 | F6 probe без дискриминатора → INVALID_ARGUMENT | negative |
| NLB-1-39 | F6 probe.port override → effectivePort° | happy |
| NLB-1-40 | F6 regionId/projectId immutable | negative |
| NLB-1-41 | F6 teardown RESTRICT blocker-list | negative |
| NLB-1-42 | F6 duration-строки [B8] | happy |
| NLB-1-56 | F6 TG.port LIVE-mutable re-echo | happy |
| NLB-1-57 | F7 one-shot inline TG config-only → standalone reusable | happy |
| NLB-1-58 | F7 inline targets[] defer / inline TG без port | negative |

**Итого NLB-1c: 11 сценариев** (родительские NLB-1-34, 36..42, 56, 57, 58). NLB-1-35 (TG.port BVA)
принадлежит **1b** (co-req `resolvedBackendPort°`) — исключён из 1c. Полная сводная матрица carve
(58/58) — в `sub-phase-NLB-1a-fga-relation-rename-acceptance.md` §Сводная матрица.
