# Sub-phase NLB-1d (gateway registration + newman shared-harness + cross-cutting verification) — Acceptance

> Статус: **✅ APPROVED** (acceptance-reviewer carve-review, 2026-07-20 — net-new NLB-1d-01..06, cross-cutting DoD carve)
> Дата: 2026-07-20
> Ревьюер: acceptance-reviewer — ✅ APPROVED (carve-partition 58/58; non-blocking notes в review-comment)
> Эпик/тикет: KAC-NLB-1 · под-фаза **1d of 4** (carve родительского APPROVED `sub-phase-NLB-1-lb-listener-targetgroup-acceptance.md`)
> Монорепо: `project/kacho` (`github.com/PRO-Robotech/kacho`) — легаси `project/kacho-*` не затрагивается.
> Порядок carve: NLB-1a → NLB-1b → NLB-1c → **NLB-1d (это, последняя)**. **Предпосылка: NLB-1a/1b/1c merged.**

## Обзор

NLB-1d — **финализирующая cross-cutting** под-фаза редизайна `kacho-nlb`: связывает три уже
редизайненных ресурса (`NetworkLoadBalancer`+`Listener` из 1b, `TargetGroup` из 1c) в единый
проверенный edge-контракт и закрывает **интеграционные инварианты**, которые родитель выразил
как **DoD e2e-smoke / authz / two-projection**-пункты (не как нумерованные `NLB-1-NN`). 1d вводит
net-new нумерованные сценарии `NLB-1d-01..06`, покрывающие эти deliverable'ы.

Что 1d делает:
1. **Gateway-coherence аудит** — весь публичный RPC-surface трёх ресурсов зарегистрирован на
   external endpoint (:9090 → REST edge); снятые RPC (`:start`/`:stop`/`:attachTargetGroup`/
   `:detachTargetGroup`) — 404 / not-registered; **никакой `Internal.*` метод не выставлен на
   external** (`security.md` ban #6). *(NB: per-RPC регистрация каждого нового public RPC — уже в
   PR его реализации 1b/1c через `api-gateway-registrar`; 1d — агрегатный аудит/финализация, не
   первичная регистрация.)*
2. **Newman shared-harness** — общая e2e-схема suite nlb: per-suite fixture isolation (свой account +
   home/cross projects), `{{runId}}`-суффиксы, `retry_until_authorized`/`retry_until_present` для
   read-your-writes, op-poll с реальной inter-poll задержкой, parallel-safety; umbrella-closeout.
3. **Two-projection field-absence** — публичные ответы LB/Listener/TG **НЕ** содержат инфра-полей
   (node/underlay/vrf/programming-status/числовой инфра-id); те живут **только** в `Internal*`
   (:9091 → NLB-3). 1d ассертит **field-absence** на реальном gateway-ответе.
4. **Integrated e2e-smoke** — полный one-shot (LB + listener + **inline redesigned-TG** из 1c) через
   real gateway до `status=ACTIVE`; derived-поля (`type°`/`placementType°`/`resolvedBackendPort°`/
   `effectivePort°`) на реальном ответе.
5. **Authz-matrix cross-account** — на `nlb_*`-типах (из 1a): listauthz-фильтр List, hide-existence
   404 byte-identical настоящему miss, cross-account/no-binding deny.

Это **verification-and-wiring** под-фаза: сценарии описывают наблюдаемое поведение **интегрированного**
edge-контракта через api-gateway (:9090) — не форму отдельного ресурса (та зафиксирована в 1b/1c).

---

## Scope

| # | Фича | Traceability (родитель) |
|---|---|---|
| G1 | Gateway-registration coherence: полный public RPC-surface трёх ресурсов на :9090; снятые RPC → 404; **никакой Internal.* на external** | родитель §DoD «per-RPC gateway-регистрация», `security.md` ban #6 |
| G2 | Newman shared-harness: per-suite fixture isolation + `{{runId}}` + retry helpers + op-poll delay + parallel-safety; umbrella-closeout | родитель §DoD «newman-кейс», `testing.md` §e2e-инварианты / §Newman EC-дисциплина |
| G3 | Two-projection field-absence: public LB/Listener/TG без инфра-полей (Internal-проекция → NLB-3) | родитель §DoD e2e-smoke «two-projection field-absence», `security.md` §Инфра-чувствительные данные |
| G4 | Integrated e2e-smoke: full one-shot (LB+listener+inline-TG) → ACTIVE; derived-поля на реальном gateway-ответе | родитель §DoD e2e-smoke (one-shot / derived) |
| G5 | Authz-matrix cross-account на `nlb_*`: listauthz-фильтр, hide-existence 404 byte-identical, no-binding/cross-account deny | родитель §DoD authz; `security.md` §Hardening инв-6 |

## Out-of-scope (следующие под-фазы редизайна nlb — NLB-2/3/4)

**Родитель §Out-of-scope (декомпозиция редизайна nlb):**
- **NLB-2 — Target membership + HealthCheck diagnostics**: child `Target` 4-way identity
  (`instance`/`nic`/`ipRef`/`externalIp`), `:addTargets`/`:removeTargets`/`:updateTargets`,
  `status`/`healthState`/`targetRefState`→`servingTraffic°`, `GetTargetStates` (health-проекция,
  `lastProbe`/`summary`), TG zone/region-coherence таргетов, **[CROSS-MODULE B9]** instance-target
  resolution (синхр. с compute-redesign `AttachNetworkInterface`).
- **NLB-3 — Discovery + validateOnly + Move + two-projection + EXPAND**: sync-каталоги (`:regions`,
  `:addableInstances`, `:vipAnchorCandidates`, …), `validateOnly:true` dry-run, `Move` (cross-project
  same-region), **`NetworkLoadBalancerInternalService.Get`** (two-projection full incl. инфра-поля,
  :9091 — 1d ассертит только **field-absence** на публичной стороне, сам Internal.Get RPC — NLB-3),
  `?view=EXPAND` (derived `attachedTargetGroups`/`usedByListeners`), `InternalResourceLifecycleService.
  Subscribe` (outbox → iam hierarchy-tuple sync).
- **NLB-4 — cutover**: UI (React SPA), docs-site (Docusaurus), deploy (helm/compose), удаление
  AS-IS-путей; proto-package `loadbalancer.v1`→`nlb.v1` + permission-string `loadbalancer.*`→`nlb.*`
  (не tenant-facing). 1d финализирует **gateway-регистрацию текущего NLB-1 surface**, но НЕ UI/docs/
  package-rename.

**Прямо вне NLB-1:** health-**пробы** реально стреляют в NLB-2 (в NLB-1 `healthCheck` — только config);
FGA owner-tuple материализация — EC, не гейтит `Operation.done` (ban #9, conv-3).

## Traceability-легенда

Родительские `NLB-1-01..58` (форма ресурсов) полностью приземлены в **1b (47)** + **1c (11)**.
1d **не наследует ни одного из 58** — он carve'ит cross-cutting DoD-deliverable'ы (gateway-coherence,
newman-harness, two-projection field-absence, integrated-smoke, authz-matrix), которые родитель
выразил как DoD-пункты, и вводит net-new `NLB-1d-01..06`. REST `/nlb/v1/…` (:9090). `°` = output-only.

---

## G1 — Gateway-registration coherence + Internal-vs-external

> `→ родитель §DoD` · `→ security.md ban #6 (Internal.* не на external), §AuthN+AuthZ ВЕЗДЕ`

### Сценарий NLB-1d-01: happy — весь public NLB-1 RPC-surface на external; снятые RPC 404; никакой Internal.* на external

**ID:** NLB-1d-01

**Given** три ресурса редизайнены (1b/1c); их public RPC (`Get`/`List` sync + `Create`/`Update`/`Delete`→Operation, one-shot `NetworkLoadBalancer.Create`) зарегистрированы per-RPC в PR своей реализации

**When** клиент обращается к external edge (:9090 → REST `/nlb/v1/…`): к каждому public RPC трёх ресурсов; отдельно — к снятым `POST …/{id}:start`, `:stop`, `:attachTargetGroup`, `:detachTargetGroup`; отдельно — к `Internal*`-методам (напр. будущий `NetworkLoadBalancerInternalService.*`)

**Then** каждый **public** RPC трёх ресурсов **маршрутизируется** (200/Operation по контракту 1b/1c); снятые `:start`/`:stop`/`:attachTargetGroup`/`:detachTargetGroup` → **404 / not-registered** (маршрут отсутствует — согласуется с NLB-1-15/21 из 1b); **никакой `Internal.*` метод не выставлен на external** (`security.md` ban #6) — Internal живёт только на cluster-internal :9091
**And** агрегатный аудит: `make -C gateway permission-catalog-check` byte-identical (нет записей снятых методов; все выставленные — с записью на `nlb_*`); нет «сиротских» gateway-маршрутов без catalog-записи (fail-closed AUTHZ_DENIED недопустим для легитимного RPC)

---

## G2 — Newman shared-harness (fixture isolation + read-your-writes + parallel-safety)

> `→ родитель §DoD` · `→ testing.md §e2e-инварианты, §Newman EC-дисциплина, §Параллельный newman`

### Сценарий NLB-1d-02: happy — per-suite fixture isolation + runId-суффиксы + read-your-writes retry; параллель-safe

**ID:** NLB-1d-02

**Given** nlb resource-suite сидится в **свой** account + home/cross projects (`setup.sh`), НЕ в общий account (иначе grant/revoke/list одного suite течёт в другой — cross-suite collision); фикстур-ресурсы несут `{{runId}}`-суффикс (идемпотентность повторного прогона, UNIQUE(name))

**When** newman-suite создаёт LB/Listener/TG, затем **сразу** Get/Update/List своего свежего ресурса, и прогоняется параллельно с другими suite (`newman-parallel.sh`)

**Then** первый Get/Update/Delete своего свежего ресурса обёрнут `retry_until_authorized` (bounded-retry на transient `403`/`404` — owner-tuple EC-окно, conv-3); List-includes своего свежего id — `retry_until_present`; op-poll — с реальной inter-poll задержкой (budget покрывает async-tail); прогон **идемпотентен** (cleanup своих ресурсов) и **parallel-safe** (изоляция account/project)
**And** обёртка ТОЛЬКО на первый пост-create доступ к своему ресурсу — **НЕ** на негативы / cross-account / absent-id / `lst-excludes` (retry там маскировал бы реальный deny); op-poll fixture проверяет `!op.error` **перед** извлечением id из `metadata` (Kachō несёт pre-allocated id даже на `done+error` — иначе phantom-id)

### Сценарий NLB-1d-03 (negative): shared-resource collision под параллелью → детерминированная энтропия, не retry-маска

**ID:** NLB-1d-03

**Given** параллельный прогон suite'ов (nlb + vpc/compute/nlb-sibling) с shared-ресурсами (VIP-пул/AddressPool, subnet-CIDR, name)

**When** suite аллоцирует из ограниченного VIP-пула (источник VIP LoadBalancer'а) под конкурентной нагрузкой

**Then** коллизия VIP-пула / CIDR / name **НЕ** маскируется retry-обёрткой (retry — только для истинного read-your-writes EC-окна): pool-contended кейсы идут `--jobs 1` ЛИБО на disjoint-CIDR/больший пул; **recycle-on-delete** VIP (NLB-1-55 из 1b) проверен на цикле `LoadBalancer.Create` → `LoadBalancer.Delete` (N alloc → N delete → N alloc снова проходит, пул не деградировал — освобождает LB, не listener); «блуждающий» флейк диагностируется как collision ПЕРЕД тем как винить EC (`testing.md` §Параллельный newman п.5)

---

## G3 — Two-projection field-absence (public без инфра-полей)

> `→ родитель §DoD e2e-smoke` · `→ security.md §Инфра-чувствительные данные (две проекции)`

### Сценарий NLB-1d-04: happy — public LB/Listener/TG НЕ содержат инфра-полей (Internal-проекция → NLB-3)

**ID:** NLB-1d-04

**Given** ресурсы созданы; клиент читает **публичную** проекцию через external edge (`GET /nlb/v1/networkLoadBalancers/{id}`, `/listeners/{id}`, `/targetGroups/{id}`)

**When** 1d ассертит **field-absence** на реальном gateway-ответе

**Then** публичная проекция несёт **только** tenant-facing «намерение + результат»: `id`, `name`/`labels`, привязки (`projectId`/`regionId`/`loadBalancerId`/`targetGroupId`), ссылку на выделенный tenant-VIP (`v4AddressId°`/`v6AddressId°` — id связанного `vpc.Address`, БЕЗ самой IP-строки), `status°`/`substatus°`, derived (`type°`/`placementType°`/`resolvedBackendPort°`/`effectivePort°`)
**And** публичный ответ **НЕ** содержит инфра-полей: node/host placement, underlay-зону public-VIP, `vipOrigin`, derived network, id VRF/routing-таблиц, host-interface/netns wiring, programming-status ядра, announce-состояние, числовой инфра-id — те живут **исключительно** в `Internal*` (:9091, `NetworkLoadBalancerInternalService.Get` → NLB-3). Assert перечисляет запрещённые ключи и проверяет их отсутствие (не только «нужные есть»)

---

## G4 — Integrated e2e-smoke (full one-shot + derived на реальном gateway)

> `→ родитель §DoD e2e-smoke` · интеграция 1b (LB+Listener) + 1c (redesigned inline-TG)

### Сценарий NLB-1d-05: happy — full one-shot (LB + listener + inline redesigned-TG) → ACTIVE; derived на реальном ответе

**ID:** NLB-1d-05

**Given** проект+регион ok; вызывающий — editor проекта; construction-verified real gateway (`make -C deploy e2e-test` / `grpcurl`)

**When** `NetworkLoadBalancerService.Create` c `placement="EXTERNAL_REGIONAL"`, `listenerSpecs=[{ name:"tcp-443", port:443, protocol:"TCP", ipVersion:"IPV4", targetGroup:{ port:8080, healthCheck:{ interval:"2s", timeout:"1s", healthyThreshold:2, unhealthyThreshold:2, tcp:{} } } }]` (inline redesigned-TG из 1c); клиент поллит `OperationService.Get` до `done`

**Then** `metadata.networkLoadBalancerId` доступен **сразу**; после `done=true` (`!error`) на реальном gateway-ответе: LB `status=ACTIVE`; listener `substatus=OK`, `resolvedBackendPort° == 8080` (эхо TG.port); inline-TG **Get-able как standalone reusable** со своим `tgr-`-id; derived на LB — `type° == "EXTERNAL"`, `placementType° == "REGIONAL"`; на TG — `healthCheck.effectivePort° == 8080`
**And** это интегрированный e2e поверх формо-контрактов 1b (NLB-1-06/19/43) + 1c (NLB-1-34/57) — smoke, не повторная реализация тех сценариев (те уже зелёные в 1b/1c PR)

---

## G5 — Authz-matrix cross-account (на `nlb_*` из 1a)

> `→ родитель §DoD authz` · `→ security.md §Hardening инв-3/6, §AuthN+AuthZ ВЕЗДЕ`

### Сценарий NLB-1d-06 (negative): cross-account/no-binding deny; listauthz-фильтр List; hide-existence 404 byte-identical

**ID:** NLB-1d-06

**Given** субъект A — editor в account A; субъект B (`jwtPureNoBindings`) — **никакого** гранта на nlb-ресурсы account A; LB/Listener/TG account A существуют

**When** субъект B вызывает `List` (все три ресурса), `Get`/`Update`/`Delete` конкретного ресурса account A

**Then** `List` (`nlb_*`-типы из 1a) **фильтруется listauthz** → субъект B видит **пустой** результат (не ресурсы account A); `Get`/`Update`/`Delete` → **hide-existence deny**: 404 **byte-identical** настоящему backend-miss (`"<Resource> <id> not found"` — не FGA-object-type-leak, не existence-oracle; `security.md` §Hardening инв-6); anonymous → `UNAUTHENTICATED`
**And** обёртка read-your-writes **НЕ** применяется к этим негативам (маскировала бы реальный deny); pagination-validate (garbage-token/`pageSize>1000`) отрабатывает **ДО** listauthz empty-grant short-circuit → `INVALID_ARGUMENT`, даже для субъекта B без грантов (согласуется с NLB-1-48 из 1b, для всех трёх List)

---

## Definition of Done (NLB-1d)

Production-complete в границах интеграции/верификации (`ai-tooling.md` §lifecycle 7, `testing.md`, `security.md`):

**Cross-cutting verification (тесты):**
- [ ] `NLB-1d-01..06` — зелёные **newman-кейсы** `# verifies NLB-1d-NN` через real api-gateway.
- [ ] **G1:** gateway-coherence аудит — весь public NLB-1 surface на :9090; снятые RPC → 404; grep/аудит: **никакой `Internal.*` на external mux**; `make -C gateway permission-catalog-check` byte-identical (агрегатно).
- [ ] **G2:** newman shared-harness — per-suite fixture isolation (`setup.sh` свой account+projects), `{{runId}}`-суффиксы, `retry_until_authorized`/`retry_until_present`, op-poll `!op.error`-перед-`metadata`, `newman-parallel.sh` fan-out **зелёный и parallel-safe** (umbrella-closeout); pool-contended → `--jobs 1`/disjoint-CIDR (не retry-маска).
- [ ] **G3:** two-projection field-absence — assert **отсутствия** инфра-ключей в публичных LB/Listener/TG (не только присутствия нужных).
- [ ] **G4:** integrated e2e-smoke — full one-shot → ACTIVE + derived на **реальном** gateway-ответе (`make -C deploy e2e-test`).
- [ ] **G5:** authz-matrix — cross-account/no-binding deny, listauthz-фильтр List, hide-existence 404 byte-identical (behaviour-level lock, `testing.md` §Regression-lock); негативы **не** обёрнуты retry.

**Проектные гейты (финальная верификация всего NLB-1, `ai-tooling.md` §lifecycle 7):**
- [ ] `go test ./... -race` · `golangci-lint run` · `govulncheck` · `make audit-list-filter` · `make -C gateway permission-catalog-check` зелёные (агрегатно по репо).
- [ ] newman зелёные — **все** `NLB-1a-NN` + `NLB-1-01..58` (1b/1c) + `NLB-1d-NN` (umbrella).
- [ ] Trail: обновить vault (`resources/nlb-*`, `rpc/nlb-*`, `edges/nlb-to-*`, `KAC/KAC-NLB-1`) + перевести тикет Test→Done с артефактами (`vault.md`, `git-youtrack.md`).

**Заказчик (шаг 7):** только финальный smoke / e2e (`make -C deploy e2e-test` / `grpcurl`) — G4/G5 на реальном стенде.

**MERGE-GATE:** 1d финализирует поверх merged 1a/1b/1c. Наследует Phase-0 MERGE-GATE (B1/B3/conv-11)
транзитивно через 1b/1c — если те не могут мёржиться до Phase-0 change-set, 1d тем более. UI/docs-site/
package-rename (`loadbalancer.v1`→`nlb.v1`) — **НЕ** здесь, а NLB-4 (§Out-of-scope).

---

## Traceability-таблица (родитель → NLB-1d)

| Родительский `NLB-1-NN` | Владение 1d? |
|---|---|
| — (нет из NLB-1-01..58) | 1d carve'ит cross-cutting DoD-deliverable'ы, не нумерованные сценарии формы |

**1d вводит net-new:** `NLB-1d-01` (G1 gateway-coherence + Internal-vs-external), `NLB-1d-02` (G2
fixture-isolation + read-your-writes), `NLB-1d-03` (G2 collision-vs-retry parallel-safety), `NLB-1d-04`
(G3 two-projection field-absence), `NLB-1d-05` (G4 integrated one-shot smoke + derived), `NLB-1d-06`
(G5 authz-matrix cross-account).

**Почему 0 из 58:** родитель выразил gateway-coherence, newman-harness, two-projection field-absence,
integrated-smoke и authz-matrix как **§DoD e2e-smoke / authz**-пункты, **не** как `NLB-1-NN`. Форма
трёх ресурсов (все 58) полностью приземлена в 1b (47) + 1c (11); 1d их **не** дублирует (это нарушило
бы same-PR test-gate). Полная сводная матрица carve (58/58, без пересечений/пропусков) — в
`sub-phase-NLB-1a-fga-relation-rename-acceptance.md` §Сводная матрица.
