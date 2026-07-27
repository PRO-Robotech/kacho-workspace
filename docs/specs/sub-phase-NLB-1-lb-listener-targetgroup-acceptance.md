# Sub-phase NLB-1 (NetworkLoadBalancer + Listener + TargetGroup core) — Acceptance

> Статус: **✅ APPROVED** (recorded by acceptance-reviewer verdict) (ре-ревью раунд 1 применён — 2 критических + 4 coverage-findings + 4 дефолта вшиты; на повторный review `acceptance-reviewer`)
> Дата: 2026-07-20
> Ревьюер: acceptance-reviewer (CHANGES REQUESTED раунд 1 → адресовано; pending re-review)
> Эпик/тикет: KAC-NLB-1 (Phase-2 redesign-2026 `kacho-nlb`; зависит от geo+vpc+compute — placement/VIP/instance-target owner'ы)
> Монорепо: `project/kacho` (`github.com/PRO-Robotech/kacho`) — легаси `project/kacho-*` не затрагивается.

## Обзор

NLB-1 — первый инкремент пересборки-2026 модуля `kacho-nlb` (региональный L4 LB, Phase-2,
блокируется geo+vpc+compute). Модуль — reference-grade suite из трёх ресурсов
(NetworkLoadBalancer / Listener / TargetGroup) + child Target + health-проекция, поэтому
редизайн разбит на 4 под-фазы (см. §Out-of-scope). NLB-1 закладывает **форму и проводку
трёх ядровых ресурсов** и приводит их к целевому tenant-facing дизайну
(`docs/plans/kacho-redesign-2026/module-nlb.md` целиком, §Правила 1-19) и общему хребту
(`00-unified-system-design.md` §1 conv-1/2/3/6/7/12, §2 nlb, §5 инв-2, §8 B3/B4/B8/B9).

Ключевые слияния/упрощения относительно AS-IS (`proto/kacho/cloud/loadbalancer/v1/*`, все
`# verifies`-ссылки сверены с реальным proto):

1. **NetworkLoadBalancer** — слить раздельные AS-IS `type` (EXTERNAL/INTERNAL) + `placement_type`
   (ZONAL/REGIONAL) в **один immutable input** `placement ∈ {EXTERNAL_REGIONAL | INTERNAL_REGIONAL
   | INTERNAL_ZONAL}` (нелегальная ячейка «external+zonal» невыразима **by construction**);
   `type°`/`placementType°` — derived output-only. Убрать power-verbs `:start`/`:stop` (+ AS-IS
   `STARTING/STOPPING/STOPPED`-статусы) → LB-нативный `adminState`. `securityGroupIds` (firewall VIP)
   возвращается на LB (AS-IS reserved). Managed endpoint `address.hostname°`+`ip°`. One-shot
   `listenerSpecs[]`.
2. **Listener** — единственный authoritative `targetGroupId` (FK RESTRICT) вместо AS-IS
   M:N `attached_target_groups`-pivot + `AttachTargetGroup`/`DetachTargetGroup` RPCs +
   «default»-семантики `default_target_group_id`. Убрать AS-IS per-listener `target_port`
   (backend-порт живёт на `TargetGroup.port`) → `resolvedBackendPort°` (эхо TG.port). **VIP остаётся
   на LoadBalancer** (per-family `v4Source`/`v6Source` → `v4AddressId°`/`v6AddressId°`); Listener
   адресных полей не несёт.
   `substatus°` (derived OK|MISCONFIGURED). Семейства обслуживаемого трафика listener не выбирает —
   он работает на всех VIP-семействах родительского LB (`ipFamilies`).
3. **TargetGroup** — region-scoped, **LB-agnostic reusable**; net-new `port` (**единственный**
   backend-порт пула — AS-IS у TG порта нет); embedded `HealthCheck` — oneof-replace дисциплина
   (scalar dotted-mask PATCH + probe atomic-replace c сохранением sibling-скаляров); AS-IS
   `deregistration_delay_seconds int32`/`slow_start_seconds int32` → duration-строки (B8-канон nlb).

Это **owner-side** под-фаза: сценарии описывают наблюдаемое поведение публичных
`NetworkLoadBalancerService`/`ListenerService`/`TargetGroupService` (:9090 → edge REST).
Target-membership (4-way identity, resolution, health-пробы), discovery-каталоги, `validateOnly`,
`Move`, Internal-проекция и UI — отдельные под-фазы (§Out-of-scope).

---

## Scope

Что NLB-1 покрывает сценариями (positive + negative + edge + concurrent-race):

| # | Фича | Traceability |
|---|---|---|
| F1 | id-prefix per-type `nlb-`/`lst-`/`tgr-` (hyphen B3); malformed/**wrong-type** → `INVALID_ARGUMENT "invalid <res> id '<X>'"` первым стейтментом; well-formed-но-нет → `NOT_FOUND`; foreign-id (`projectId`/`regionId`/`securityGroupId`/instance/nic) **НЕ** prefix-checked (B4 own-only). **Записанное узкое исключение** из B4 для `v4Source`/`v6Source`: `subnetId`/`addressId` проходят синтаксический gate `corevalidate.ResourceID` ДО peer-validate. Это **не** сверка vpc-префикса — функция family-agnostic (`expectedPrefix` не читается), проверяется членство в платформенном каталоге префиксов. Обоснование — `services/nlb/docs/architecture/08-known-divergences.md` §«Формат чужого id (VIP-источники)» | module-nlb §Правила 12/16; unified §1 conv-12 **[PHASE-0-GATED B3]**, §8 B3/B4 |
| F2 | NetworkLoadBalancer: **один immutable input `placement`** (слияние AS-IS `type`+`placement_type`); `type°`/`placementType°` derived output-only; «external+zonal» невыразим by construction; `regionId` immutable + peer-validate geo (fail-closed); `securityGroupIds` (firewall VIP, same-project existence, LIVE-mutable, **без** region-coherence) | module-nlb §Ментальная модель 1, §Правила 1/10/11/12/18; unified §2 nlb, §5 инв-2, §8 B4 |
| F3 | NetworkLoadBalancer: `adminState` (LIVE-mutable) заменяет AS-IS `:start`/`:stop`; Update никогда не авто-ENABLE'ит DISABLED; `crossZoneEnabled` write `!=false` на ZONAL → `INVALID_ARGUMENT`; `sessionAffinity` LIVE-mutable; `status°` авто-рекомпут (ACTIVE/DEGRADED/INACTIVE/DISABLED-глоссы) | module-nlb §NetworkLoadBalancer (status-recompute), §Правила 8/11/17/18; unified §2 nlb |
| F4 | Listener: **единственный authoritative `targetGroupId`** (FK RESTRICT); AS-IS `AttachTargetGroup`/`DetachTargetGroup` + M:N pivot **сняты**; `substatus°`/`resolvedBackendPort°` derived; wiring/repoint + `proxyProtocolV2` LIVE-mutable; immutables; incremental-order actionable-error | module-nlb §Listener, §Правила 4/8/9/11; unified §2 nlb |
| F5 | **VIP на LoadBalancer**: per-family immutable input `v4Source`/`v6Source` → output-only `v4AddressId°`/`v6AddressId°` (сама IP-строка не дублируется); uniqueness — per-region partial-UNIQUE `(region_id, address_v4/_v6)` → generic `FAILED_PRECONDITION` (+ concurrent-race) и CAS single-VIP-per-LB; placement/region/network/zone-coherence источника; `LoadBalancer.Delete` → recycle по `vipOrigin` | module-nlb §VIP — свойство LoadBalancer'а, §Правила 6/10/12; unified §5 инв-2 (placement-coherence), §8 B17 |
| F6 | TargetGroup: region-scoped, **LB-agnostic reusable**; net-new `port` (единственный backend-порт, LIVE-mutable → re-echo `resolvedBackendPort°`); embedded HealthCheck oneof-replace (scalar dotted-mask PATCH merge-validated + probe atomic-replace, sibling-скаляры уцелевают); `effectivePort°`; immutables; teardown RESTRICT | module-nlb §TargetGroup + §HealthCheck, §Правила 9/11/13; unified §2 nlb |
| F7 | Cross-cutting: one-shot `NetworkLoadBalancer.Create` (listenerSpecs[] existing-TG **и** inline `targetGroup{port,healthCheck}` config-only); teardown RESTRICT c blocker-list + `cascade:true`; op-poll async-модель; **B8 duration-конвенция** (Duration-строки, AS-IS int-seconds); `deletionProtection`; List pagination-validate ДО listauthz; name UNIQUE(project,name) (+ concurrent-race) | module-nlb §RPC surface, §Правила 2/3/4/13/15/16; unified §1 conv-2/3, §8 B8 |

## Out-of-scope (явно НЕ в NLB-1)

**Декомпозиция редизайна nlb на под-фазы** (порядок — по dependency-графу; ядровая форма
трёх ресурсов + проводка — фундамент, поэтому NLB-1 первым):

- **NLB-2 — Target membership + HealthCheck diagnostics** (backend-пул и здоровье):
  child `Target` **4-way identity** (`instance`/`nic`/`ipRef`/`externalIp`, exactly-one, DB-CHECK);
  `:addTargets` (идемпотентно `ON CONFLICT DO NOTHING`) / `:removeTargets` (2-фазный drain,
  `deregistrationDelay`) / `:updateTargets` (weight + in-place drain/undrain); три ортогональные
  оси `status`/`healthState`/`targetRefState` → derived `servingTraffic°`; `GetTargetStates`
  (LB-scoped И TG-scoped, cursor-paginated + `summary`, `lastProbe`/`recentProbes`);
  TG **zone-coherence** (warn-on-entry `:addTargets` + hard precheck на wire к ZONAL-LB,
  anycast-exempt для `externalIp`/REGIONAL-subnet-`ipRef`); TG **region-coherence** target'ов
  (2-hop derive `geo.Zone(instance.zoneId).regionId == TG.regionId`).
  **[CROSS-MODULE B9]** instance-target resolution (`instance → primary NIC → primary IP` по
  семействам VIP родительского LB; primary-NIC = lowest-index ИЛИ explicit-flag; multi-NIC-ambiguity →
  `FailedPrecondition`) **синхронизируется с compute-redesign-2026 `AttachNetworkInterface`** —
  до settling instance-target несёт пометку «resolution semantics pending compute attach model»;
  `nic`/`ipRef`/`externalIp` — load-bearing (не зависят от attach-редизайна). NLB-1 фиксирует TG
  как config-объект (`port` + `healthCheck`), НЕ трогая membership: wired-listener → TG с **пустым
  пулом** резолвится (substatus OK) — status-рекомпут NLB-1 не требует таргетов.
- **NLB-3 — Discovery + validateOnly + Move + two-projection + EXPAND**: sync-каталоги
  (`:regions`, `:addableInstances`/`:addableNetworkInterfaces`, `:vipAnchorCandidates`,
  `referenceableTargetGroups` c `requestFragment`); `validateOnly:true` sync dry-run (echo derived
  выведенную зону VIP-источника, resolved target-IP по семействам VIP LB, `resolvedBackendPort`/`effectivePort`, preview связываемого Address,
  unwired-listener warnings, per-target zone-verdict, crossZone-on-ZONAL reject — БЕЗ мутации);
  `Move` (`NetworkLoadBalancer`/`TargetGroup` cross-project same-region; editor на src+dst);
  `NetworkLoadBalancerInternalService.Get` (two-projection full incl. инфра-поля, :9091);
  `?view=EXPAND` (derived `attachedTargetGroups`/`usedByListeners` — LEAN, вне DEFAULT);
  `InternalResourceLifecycleService.Subscribe` (outbox → iam hierarchy-tuple sync).
- **NLB-4 — cutover**: api-gateway-регистрация полного набора (public mux) финализация, UI (React SPA),
  docs-site (Docusaurus), newman-umbrella closeout, deploy (helm/compose), удаление AS-IS-путей.
  *(NB: per-RPC gateway-регистрация каждого нового public RPC — в том же PR, что и его реализация,
  через `api-gateway-registrar`; NLB-4 — финализация/чистка, не первичная регистрация.)*
  **Также NLB-4 (дефолт Q2, дрейф именования):** proto-package `kacho.cloud.loadbalancer.v1` →
  **`kacho.cloud.nlb.v1`** (unified §2 nlb — целевой пакет `nlb.v1`) + permission-namespace
  `loadbalancer.*` → `nlb.*` (сейчас `loadbalancer.networkLoadBalancers.*` при REST/ids/FGA=`nlb`).
  Package/permission-string — **не** tenant-facing и **не** ядровая форма → вынесено в cutover, чтобы
  дрейф `loadbalancer.v1`↔`nlb`(ids/REST/FGA-type) не был молча потерян. FGA object-type rename
  `lb_*`→`nlb_*` — наоборот, **в NLB-1** (tenant-facing authz-scope, hard-rename greenfield — дефолт Q1, §DoD).

**Прямо вне NLB-1 (даже по трём ядровым ресурсам):**
- **Target-membership любого рода** — inline `targets[]` в TG.Create / listenerSpec.targetGroup,
  4-way identity resolution, `targetRefState`/`servingTraffic`, health-пробы. NLB-1 one-shot Create
  принимает `listenerSpecs[]` со ссылкой на **существующую** `targetGroupId` ЛИБО inline
  `targetGroup{port, healthCheck}` **без** `targets[]`; полный one-shot c inline-targets + saga-
  compensation → NLB-2.
- **Runtime health-проекция** (`GetTargetStates`, `lastProbe`, `summary`) — NLB-2 (пробы реально
  стреляют там). NLB-1 `healthCheck` — только валидируемый config на write.
- **VIP-saga compensation-детали** (внутренняя последовательность шагов worker'а) — NLB-1 фиксирует **наблюдаемый
  контракт** (VIP аллоцирован/эхнут, uniqueness, immutable источник, placement/zone-coherence, recycle), не
  внутреннюю механику саги (system-design-review отдельно).
- **FGA owner-tuple материализация** (`fga_register_outbox` drainer/reconciler) — EC; NLB-1 **не
  гейтит** `Operation.done` на её видимость (ban #9, conv-3); read-your-writes окно — bounded
  client-retry.

## Traceability-легенда

`°` = output-only поле (server-derived/managed, на вход не принимается; попытка задать derived-
дискриминатор `type`/`placementType` — **explicit reject**, не silent). REST-пути публичные
`/nlb/v1/…` (:9090, external-safe). JSON — camelCase (`projectId`, `regionId`, `targetGroupId`,
`adminState`, `createdAt`). Все timestamps усечены до секунд на wire (включая embedded/child).
Каждый feature-блок несёт `→ module-nlb §…` / `→ unified §…` и `> **AS-IS:**`-примечание
(сверено с реальным proto). **[PHASE-0-GATED]** = зависит от Phase-0 governance change-set
(см. §Definition of Done merge-gate). **[CROSS-MODULE]** = зависит от другого модуля (compute).
**[B8]** = duration-конвенция (nlb-канон, не hard-gate).

Каноническое существительное — **NetworkLoadBalancer** во всей прозе/RPC/metadata-key; error-тон
`"<Resource> <id> not found"` (капитализованный ресурс), precondition-list — литеральные тексты
module-nlb §Правила 12 (`"network load balancer has listeners: [<ids>]"` строчными — часть контракта).

---

## F1 — id-prefix per-type (hyphen B3) + malformed/wrong-type/absent first-statement + foreign-id B4

> `→ module-nlb` §Правила 12 (format-check own-only), §Правила 16 (id-формат) · `→ unified §1 conv-12 [PHASE-0-GATED B3], §8 B3/B4`
> **AS-IS:** prefix-константы `PrefixLoadBalancer="nlb"`, `PrefixListener="lst"`, `PrefixTargetGroup="tgr"`
> (`pkg/ids/ids.go:87-89`) — **3-char, БЕЗ дефиса**. `PrefixOperationNLB` == `PrefixLoadBalancer`
> (`ids.go:114` — quirk: operation-prefix aliases nlb resource-prefix). Механизм format-first-statement
> (`corevalidate.ResourceID`) существует в vpc/compute; nlb приводится к нему.
> **[PHASE-0-GATED B3]:** переход `nlb`/`lst`/`tgr` → `nlb-`/`lst-`/`tgr-` (hyphen) фиксируется Phase-0 в
> `corevalidate`+`api-conventions.md` (00-unified §8 B3: **с дефисом**), затем vpc/nlb приводятся
> ОДНИМ шагом с corelib prefix→type-router. Сценарии формулируют **target hyphen-форму**; до merge
> реализация на 3-char. Wrong-type-detection и own-only prefix-check (B4) — **ungated**.

### Сценарий NLB-1-01: happy — Get по валидному id каждого из трёх типов

**ID:** NLB-1-01

**Given** существуют `nlb-1a2b3c4d5e6f7g8h`, `lst-7h3k9m2x4q8w1t0y`, `tgr-2w8r4t6y1u3i5o7p` в проекте `prj-f9k2m4x7q1w8r3n5`

**When** клиент вызывает `NetworkLoadBalancerService.Get` (`GET /nlb/v1/networkLoadBalancers/nlb-1a2b3c4d5e6f7g8h`)

**Then** `200 OK`; тело — public `NetworkLoadBalancer` c `id == "nlb-1a2b3c4d5e6f7g8h"`, `projectId`, `regionId`, `createdAt°` (усечён до секунд)
**And** аналогично `ListenerService.Get`/`TargetGroupService.Get` возвращают ресурс с соответствующим `id`

### Сценарий NLB-1-02 (negative): malformed id → sync `INVALID_ARGUMENT` первым стейтментом

**ID:** NLB-1-02

**When** клиент вызывает `NetworkLoadBalancerService.Get` (`GET /nlb/v1/networkLoadBalancers/garbage!!`)

**Then** **синхронный** `INVALID_ARGUMENT "invalid network load balancer id 'garbage!!'"` — malformed ловится `corevalidate.ResourceID` **до** любого repo-вызова (repo НЕ вызывается)
**And** то же для `ListenerService.Get` → `"invalid listener id 'garbage!!'"` и `TargetGroupService.Get` → `"invalid target group id 'garbage!!'"`

### Сценарий NLB-1-03 (edge): wrong-type prefix → `INVALID_ARGUMENT` (не `NOT_FOUND`)

**ID:** NLB-1-03

**Given** id `tgr-2w8r4t6y1u3i5o7p` — валиден по charset/длине, но с **чужим** типом-префиксом (`tgr-`, не `nlb-`)

**When** клиент вызывает `NetworkLoadBalancerService.Get` (`GET /nlb/v1/networkLoadBalancers/tgr-2w8r4t6y1u3i5o7p`)

**Then** **синхронный** `INVALID_ARGUMENT "invalid network load balancer id 'tgr-2w8r4t6y1u3i5o7p'"` — prefix однозначно кодирует тип, wrong-type ловится тем же first-statement (не доезжает до `repo.Get` → **не** `NOT_FOUND`)

### Сценарий NLB-1-04: well-formed-но-отсутствует → `NOT_FOUND` (direct-read lane)

**ID:** NLB-1-04

**When** клиент вызывает `NetworkLoadBalancerService.Get` (`GET /nlb/v1/networkLoadBalancers/nlb-00000000000000`) — валиден, но не существует

**Then** `NOT_FOUND "NetworkLoadBalancer nlb-00000000000000 not found"` (прошёл format-check, `repo.Get` вернул miss)

### Сценарий NLB-1-05 (edge, B4): foreign-id НЕ prefix-checked — только peer-validate existence

**ID:** NLB-1-05

> **AS-IS:** nlb уже peer-validate'ит `projectId` через `iam.ProjectService.Get` и `regionId` через `geo.RegionService.Get` (`services/nlb/internal/clients/{iam,geo}`). Прочие foreign id (instance/nic/`securityGroupId`) — existence-only, без format-check.

**Given** клиент создаёт NetworkLoadBalancer c `projectId = "not-a-prj-slug"` (проходит длину `<=50`, но не nlb-owned prefix) и корректным `placement`/`regionId`

**When** `NetworkLoadBalancerService.Create` (`POST /nlb/v1/networkLoadBalancers`)

**Then** отказ приходит **не** как format-`"invalid project id"` (foreign scope-coord iam-owned — **не** prefix-checked, B4 own-only), а как **peer-validate existence-result** через `iam.ProjectService.Get`
**And** конкретный код: **AS-IS `NOT_FOUND "Project not-a-prj-slug not found"`**; **[PHASE-0-GATED conv-11]** target по by-lane peer-validate-полосе → `FAILED_PRECONDITION` (единая полоса projectId/regionId; см. F2/DoD merge-gate)
**And** для VIP-источников LB (`v4Source`/`v6Source`) действует **записанное узкое исключение** из B4 (решение принято — `services/nlb/docs/architecture/08-known-divergences.md` §«Формат чужого id (VIP-источники)»): `subnetId`/`addressId` проходят **family-agnostic** синтаксический gate ДО peer-validate existence (`corevalidate.ResourceID` не читает `expectedPrefix`; проверяется членство в платформенном каталоге, не приватный словарь vpc, и тип чужого ресурса локально не утверждается — `nlb…`-id проходит к владельцу). Мотив — терминальный `INVALID_ARGUMENT "invalid subnet id '<X>'"` на явно-не-id вместо retryable `UNAVAILABLE` при недоступном vpc и вместо ложного `"subnet <X> not found"`. Тип/существование/placement подтверждает peer-vpc (см. F5)
**And** пустая ссылка выбранной ветки oneof → `INVALID_ARGUMENT "v4_source.subnet_id: required"` / `"v6_source.address_id: required"` (форма запроса; владельцу вопрос не задаётся)

---

## F2 — NetworkLoadBalancer: один immutable input `placement`; `type°`/`placementType°` derived; regionId immutable+peer-geo

> `→ module-nlb` §Ментальная модель 1, §Правила 1/10/11/12 · `→ unified §2 nlb, §5 инв-2, §8 B4`
> **AS-IS (слияние):** `NetworkLoadBalancer` несёт **раздельные** `Type type = 10` (EXTERNAL/INTERNAL,
> AS-IS **required input** в Create — `network_load_balancer_service.proto:247`) и `PlacementType
> placement_type = 27` (ZONAL/REGIONAL, AS-IS input, required для INTERNAL, запрещён для EXTERNAL —
> `:255-257`). Редизайн **сливает** их в один immutable input `placement`; `type°`/`placementType°`
> становятся **derived output-only** (persist остаётся один факт — `placement`; оба эмитятся queryable,
> паритет с subnet `placement_type`). `region_id = 7` уже present + peer-validate geo.

### Сценарий NLB-1-06: Create `EXTERNAL_REGIONAL` → `type°`/`placementType°` derived на read

**ID:** NLB-1-06

**Given** проект `prj-f9k2m4x7q1w8r3n5` существует (peer-validate iam ok); регион `eu-north` существует (peer-validate geo ok); вызывающий — editor проекта

**When** `NetworkLoadBalancerService.Create` (`POST /nlb/v1/networkLoadBalancers`) c payload:
  - `projectId = "prj-f9k2m4x7q1w8r3n5"`
  - `regionId = "eu-north"`
  - `name = "public-north-edge"`
  - `placement = "EXTERNAL_REGIONAL"`

**Then** `Operation`; `metadata.networkLoadBalancerId` доступен **сразу** (до `done`); после полла до `done=true` (`!error`) `Get` отдаёт LB c `placement == "EXTERNAL_REGIONAL"`, **derived** `type° == "EXTERNAL"`, `placementType° == "REGIONAL"`, `zoneId° == ""` (REGIONAL anycast)
**And** `type`/`placementType` — голые токены на read (клиент не re-парсит `placement`-строку)

### Сценарий NLB-1-07: Create `INTERNAL_ZONAL` c явным `zoneId` → derived `type°=INTERNAL`, `placementType°=ZONAL`

**ID:** NLB-1-07

**Given** проект и регион `eu-north` (зоны `eu-north-a`/`eu-north-b`) существуют; вызывающий — editor

**When** `NetworkLoadBalancerService.Create` c `placement = "INTERNAL_ZONAL"`, `regionId = "eu-north"`, опц. input `zoneId = "eu-north-a"`

**Then** после `done` `Get` отдаёт `type° == "INTERNAL"`, `placementType° == "ZONAL"`, `zoneId == "eu-north-a"` (authoritative из input'а)
**And** zone `eu-north-a` ∈ регион `eu-north` (peer-validate geo); mismatch зоны и региона → `FAILED_PRECONDITION` (см. NLB-1-11)

### Сценарий NLB-1-08 (negative): write `type`/`placementType` в теле Create → explicit reject

**ID:** NLB-1-08

**Given** `type`/`placementType` — derived output-only (не входные поля в целевой модели)

**When** клиент шлёт Create c `placement="INTERNAL_ZONAL"` **и** одновременно `type="EXTERNAL"` (либо `placementType="REGIONAL"`) в теле

**Then** **explicit reject** `INVALID_ARGUMENT` (derived-дискриминатор нельзя задать на вход — не silent-ignore; сообщение указывает, что источник режима — единственный вход `placement`)
**And** это **breaking-delta** от AS-IS, где `type` был required-input, а `placement_type` — writable (см. §DoD deliverables)

### Сценарий NLB-1-09 (edge): «external+zonal» невыразим by construction

**ID:** NLB-1-09

**Given** enum `placement` содержит **ровно** `{EXTERNAL_REGIONAL, INTERNAL_REGIONAL, INTERNAL_ZONAL}` — значения `EXTERNAL_ZONAL` **нет**

**When** клиент пытается выразить «внешний зональный» LB

**Then** комбинация **невыразима by construction** (не runtime-reject): в proto-enum нет соответствующего значения; клиент физически не может отправить нелегальную ячейку
**And** это архитектурная гарантия слияния (в отличие от AS-IS, где `type=EXTERNAL`+`placement_type=ZONAL` были бы двумя валидными полями, требующими runtime-cross-check)

### Сценарий NLB-1-10 (negative): `placement` immutable в Update

**ID:** NLB-1-10

**Given** LB `nlb-1a2b3c4d5e6f7g8h` создан c `placement="EXTERNAL_REGIONAL"`

**When** `NetworkLoadBalancerService.Update` c `updateMask="placement"` (или `regionId`)

**Then** **reject ДО `UpdateMask`-обработки** (immutable-switch первым) → `INVALID_ARGUMENT "placement is immutable after NetworkLoadBalancer.Create"` (тон module-nlb §Правила 11)
**And** аналогично `regionId` → `"region_id is immutable after NetworkLoadBalancer.Create"`

### Сценарий NLB-1-11 `[PHASE-0-GATED conv-11]` (negative): несуществующий `regionId` → peer-validate geo

**ID:** NLB-1-11

> **AS-IS:** nlb peer-validate'ит region через `geo.RegionService.Get` (`clients/geo`). Целевой by-lane тон (conv-11: peer-validate scope-coord absent → `FAILED_PRECONDITION` + reason-token) — **[PHASE-0-GATED]**.

**Given** вызывающий создаёт LB c `regionId = "no-such-region"` (валидный DNS-1123 slug, но geo не резолвит)

**When** `NetworkLoadBalancerService.Create`

**Then** отказ — **peer-validate existence-result** (не format): `regionId` — geo-owned human slug, **освобождён** от prefix/base32 и от `"invalid <res> id"`; невалидный **формат** slug → `INVALID_ARGUMENT "invalid region id '<X>'"`, но отсутствие → peer-existence
**And** конкретный код: **AS-IS `INVALID_ARGUMENT`**; **[PHASE-0-GATED conv-11]** target по by-lane peer-validate → `FAILED_PRECONDITION "region_id no-such-region not found"` (единая полоса projectId/regionId; merge-gate — §DoD)

### Сценарий NLB-1-12 (edge, fail-closed): geo недоступен на Create → `UNAVAILABLE`

**ID:** NLB-1-12

**Given** `geo.RegionService.Get` недоступен (peer down) в момент Create

**When** `NetworkLoadBalancerService.Create` c валидным `regionId`

**Then** мутация **fail-closed** → `UNAVAILABLE` (peer недоступен — мутация не проходит; module-nlb §Правила 12, unified §5 инв-2 «fail-closed для мутаций»); LB **не** создаётся (нет phantom-row)

### Сценарий NLB-1-51: happy — `securityGroupIds` (firewall VIP) set@Create + LIVE-mutable@Update; region-coherence НЕ проверяется

**ID:** NLB-1-51

> **Дефолт Q4 (review раунд 1):** `securityGroupIds` — реальное поле NetworkLoadBalancer (`module-nlb §Правила 18`, firewall самого VIP / frontend access control), **остаётся в NLB-1** (LIVE-mutable скаляр-список, тривиальный same-project existence). AS-IS: `security_group_ids` был reserved на LB (`network_load_balancer.proto:37`) — редизайн его возвращает.

**Given** проект `prj-f9k2m4x7q1w8r3n5`; vpc SecurityGroup `sg-0k4m7t2y9u1i3o5p` существует **в том же проекте**

**When** `NetworkLoadBalancerService.Create` c `securityGroupIds = ["sg-0k4m7t2y9u1i3o5p"]`, затем `Update` c `updateMask="securityGroupIds"`, `securityGroupIds=["sg-0k4m7t2y9u1i3o5p","sg-1a2b3c4d5e6f7g8h"]` (оба same-project)

**Then** после `done` `Get` LB эхает `securityGroupIds`; каждый SG — **same-project existence-check** через vpc (peer-validate); **region-coherence НЕ проверяется** (SG network-scoped, region/zone-поля не несёт — module-nlb §Правила 10/18); поле LIVE-mutable

### Сценарий NLB-1-52 (negative): несуществующий / cross-project `securityGroupId` → peer-validate; vpc down → `UNAVAILABLE`

**ID:** NLB-1-52

**Given** SG `sg-00000000000000` не существует (или принадлежит **другому** проекту)

**When** `NetworkLoadBalancerService.Create`/`Update` c этим `securityGroupId`

**Then** отказ — **peer-validate existence-result** через vpc (foreign vpc-owned id, **не** nlb-prefix-checked, B4): absent/cross-project → by-lane код (**AS-IS**, target `FAILED_PRECONDITION` **[PHASE-0-GATED conv-11]**); vpc недоступен → `UNAVAILABLE` (fail-closed для мутации)
**And** malformed `securityGroupId` (`"garbage!!"`) — **не** nlb-format-reject; peer-validate вернёт not-found (foreign id, B4 own-only)

---

## F3 — adminState заменяет `:start`/`:stop`; crossZoneEnabled ZONAL-guard; status auto-recompute

> `→ module-nlb` §NetworkLoadBalancer (status-recompute), §Правила 8/11/17/18 · `→ unified §2 nlb`
> **AS-IS:** power-verbs `Start`/`Stop` RPCs (`network_load_balancer_service.proto:94-122`) + статусы
> `STARTING/STOPPING/STOPPED` (`network_load_balancer.proto:44-47`). `disabled_announce_zones = 28`
> (REGIONAL drain) — снимается. `cross_zone_enabled` был reserved (`:37`). Редизайн: LB-нативный
> `adminState: ENABLED|DISABLED` (LIVE-mutable) + `crossZoneEnabled` (REGIONAL-only) + `sessionAffinity`
> (AS-IS present, `session_affinity = 11`).

### Сценарий NLB-1-13: `adminState=DISABLED` через Update → `status° == DISABLED` (конфиг цел)

**ID:** NLB-1-13

**Given** LB `nlb-1a2b3c4d5e6f7g8h` в `status=ACTIVE`, `adminState=ENABLED`, ≥1 wired listener

**When** `NetworkLoadBalancerService.Update` c `updateMask="adminState"`, `adminState="DISABLED"`

**Then** после `done` `Get` отдаёт `adminState == "DISABLED"`, `status° == "DISABLED"` («админ-выключен, конфиг сохранён» — не failure-состояние); listener'ы/wiring целы

### Сценарий NLB-1-14: Update никогда не авто-ENABLE'ит DISABLED-LB

**ID:** NLB-1-14

**Given** LB в `adminState=DISABLED`

**When** `NetworkLoadBalancerService.Update` c `updateMask="labels"` (меняет только labels, `adminState` **не** в маске)

**Then** `adminState` остаётся `"DISABLED"` (admin-state сохраняется — module-nlb §Правила 11); только явный `adminState:ENABLED` в маске возвращает LB в `ENABLED`

### Сценарий NLB-1-15: убраны `:start`/`:stop` — RPC отсутствует

**ID:** NLB-1-15

**Given** редизайн снял power-verbs

**When** клиент вызывает `POST /nlb/v1/networkLoadBalancers/{id}:start` (или `:stop`)

**Then** маршрут **отсутствует** (404 / not-registered на gateway) — enable/disable выражается **только** через `adminState` LIVE-mutable поле (`Update`); это breaking-delta от AS-IS (§DoD deliverables)

### Сценарий NLB-1-16 (negative): `crossZoneEnabled != false` на ZONAL → `INVALID_ARGUMENT`

**ID:** NLB-1-16

**Given** LB c `placement="INTERNAL_ZONAL"` (ZONAL)

**When** `NetworkLoadBalancerService.Create`/`Update` c `crossZoneEnabled = true`

**Then** `INVALID_ARGUMENT "crossZoneEnabled is not applicable to ZONAL placement"` (не молчаливый inert — module-nlb §Правила 10); для REGIONAL `crossZoneEnabled` действует нормально
**And** REGIONAL — anycast, из зональной проверки исключён by construction

### Сценарий NLB-1-17: status auto-recompute — `INACTIVE` без listener'ов, `ACTIVE` при wired-listener

**ID:** NLB-1-17

**Given** LB создан **без** listener'ов (config incomplete), `adminState=ENABLED`

**When** клиент `Get` LB, затем создаёт listener c резолвящейся `targetGroupId` и снова `Get`

**Then** до listener'а `status° == "INACTIVE"` («config incomplete: нет listener'ов»); после wired-listener'а `status° == "ACTIVE"` (⟺ `adminState=ENABLED` ∧ ≥1 listener ∧ **каждый** резолвит свою TG)
**And** рекомпут авто (DB-триггер, не клиентский); TG может быть с **пустым** пулом таргетов — резолв TG, а не наличие таргетов, гейтит ACTIVE (target-membership → NLB-2)

### Сценарий NLB-1-18: status auto-recompute — `DEGRADED` при MISCONFIGURED-listener

**ID:** NLB-1-18

**Given** LB `status=ACTIVE` c одним listener'ом, wired на `tgr-2w8r4t6y1u3i5o7p`

**When** referencing-TG становится нерезолвящейся (напр. `targetGroupId` обнулён — см. F4) → listener `substatus° == "MISCONFIGURED"`

**Then** `Get` LB отдаёт `status° == "DEGRADED"` («есть MISCONFIGURED-listener без резолвящейся TG» — silent-blackhole **не** маскируется под ACTIVE); `reason` уровня listener — `"listener <id> has no target group"`

### Сценарий NLB-1-53: `sessionAffinity` LIVE-mutable (FIVE_TUPLE ↔ CLIENT_IP_ONLY)

**ID:** NLB-1-53

> **AS-IS:** `session_affinity = 11` present (`network_load_balancer.proto:93`); `SESSION_AFFINITY_UNSPECIFIED` персистится как `FIVE_TUPLE`-дефолт. Редизайн сохраняет поле LIVE-mutable.

**Given** LB `nlb-1a2b3c4d5e6f7g8h` c `sessionAffinity="FIVE_TUPLE"` (или UNSPECIFIED → дефолт `FIVE_TUPLE`)

**When** `NetworkLoadBalancerService.Update` c `updateMask="sessionAffinity"`, `sessionAffinity="CLIENT_IP_ONLY"`

**Then** после `done` `Get` LB отдаёт `sessionAffinity == "CLIENT_IP_ONLY"` (LIVE-mutable); значения `FIVE_TUPLE`(«5-tuple hash»)|`CLIENT_IP_ONLY`(«sticky по src-IP») — module-nlb §NetworkLoadBalancer

---

## F4 — Listener: единственный authoritative `targetGroupId`; attach/detach + M:N pivot сняты; substatus°/resolvedBackendPort° derived

> `→ module-nlb` §Listener, §Правила 4/8/9 · `→ unified §2 nlb`
> **AS-IS (упрощение):** роутинг — M:N `attached_target_groups`-pivot (`network_load_balancer.proto:98`,
> deprecated) + RPCs `AttachTargetGroup`/`DetachTargetGroup` (`network_load_balancer_service.proto:147-181`);
> у listener'а — «default»-семантика `default_target_group_id = 17` (`listener.proto:88` — «receives
> traffic when no per-listener routing rule matches»). Редизайн: **единственный authoritative**
> `targetGroupId` (FK RESTRICT), M:N-pivot + attach/detach-RPCs **сняты**; `substatus°`/`resolvedBackendPort°`
> — derived (AS-IS отсутствуют).

### Сценарий NLB-1-19: happy — Listener.Create wiring существующей `targetGroupId` → substatus OK, resolvedBackendPort°

**ID:** NLB-1-19

**Given** LB `nlb-1a2b3c4d5e6f7g8h` и region-coherent TG `tgr-2w8r4t6y1u3i5o7p` c `port=8080` существуют в том же регионе

**When** `ListenerService.Create` (`POST /nlb/v1/listeners`) c payload:
  - `loadBalancerId = "nlb-1a2b3c4d5e6f7g8h"`
  - `name = "tcp-443"`, `protocol = "TCP"`, `port = 443`
  - `targetGroupId = "tgr-2w8r4t6y1u3i5o7p"`
  - источник VIP LoadBalancer'а (см. F5)

**Then** после `done` `Get` listener отдаёт `substatus° == "OK"` (targetGroupId резолвится) и `resolvedBackendPort° == 8080` (эхо `TargetGroup.port` выбранной TG — наблюдаем БЕЗ dry-run; **не путать** с frontend `port=443`)

### Сценарий NLB-1-20 (edge): listener без резолвящейся TG → substatus MISCONFIGURED, LB DEGRADED

**ID:** NLB-1-20

**Given** listener создаётся c `targetGroupId=""` (nullable) ЛИБО его TG впоследствии обнулена

**When** клиент `Get` listener

**Then** `substatus° == "MISCONFIGURED"`, reason `"listener <id> has no target group"` (чистая server/client-производная, не persist); родительский LB → `status° == "DEGRADED"` (F3/NLB-1-18) — silent-blackhole **surfaced, не скрыт**

### Сценарий NLB-1-21 (negative): `AttachTargetGroup`/`DetachTargetGroup` RPCs сняты

**ID:** NLB-1-21

**Given** редизайн убрал M:N-pivot и attach/detach-семантику

**When** клиент вызывает `POST /nlb/v1/networkLoadBalancers/{id}:attachTargetGroup` (или `:detachTargetGroup`)

**Then** маршрут **отсутствует** (404 / not-registered) — «привязать TG» = навести listener на неё (`targetGroupId`); «отвязать» = сменить/обнулить `targetGroupId`; набор attached-TG у LB — **производная** (объединение `listeners[].targetGroupId`, EXPAND-only → NLB-3)

### Сценарий NLB-1-22: `targetGroupId` LIVE-mutable — repoint listener'а на другую TG

**ID:** NLB-1-22

**Given** listener `lst-7h3k9m2x4q8w1t0y` wired на `tgr-2w8r4t6y1u3i5o7p` (`port=8080`); существует вторая region-coherent TG `tgr-4h6j8l0n2p4r6s8u` (`port=9090`)

**When** `ListenerService.Update` c `updateMask="targetGroupId"`, `targetGroupId="tgr-4h6j8l0n2p4r6s8u"`

**Then** после `done` `Get` listener отдаёт `targetGroupId == "tgr-4h6j8l0n2p4r6s8u"`, `resolvedBackendPort° == 9090` (эхо новой TG); backend-порт сменился **сменой TG** (не per-listener override — F5/module-nlb §Правила 9)

### Сценарий NLB-1-23 (negative): Listener.Create c несуществующей `targetGroupId` → actionable error

**ID:** NLB-1-23

**Given** `targetGroupId = "tgr-00000000000000"` не существует (или не region-coherent с LB)

**When** `ListenerService.Create` c этим `targetGroupId`

**Then** `FAILED_PRECONDITION "listener requires an existing targetGroupId; create the TargetGroup first (POST /nlb/v1/targetGroups) or use one-shot NetworkLoadBalancer.Create"` (actionable — module-nlb §Правила 4; **не** «no target group to wire»)
**And** region-mismatch TG (TG в другом регионе, чем LB) → `FAILED_PRECONDITION` с region-coherence-текстом

### Сценарий NLB-1-24 (negative): immutable Listener-поля в Update

**ID:** NLB-1-24

**Given** listener `lst-7h3k9m2x4q8w1t0y` c `protocol="TCP"`, `port=443`, `loadBalancerId="nlb-…"`

**When** `ListenerService.Update` c `updateMask` содержащим любое из `protocol`/`port`/`loadBalancerId`

**Then** **reject ДО `UpdateMask`** → `INVALID_ARGUMENT "<field> is immutable after Listener.Create"` (module-nlb §Правила 11)

### Сценарий NLB-1-25 (negative): AS-IS `targetPortOverride`/per-listener backend-порт снят

**ID:** NLB-1-25

> **AS-IS:** `Listener.target_port = 11` («Port on which targets receive forwarded traffic» — `listener.proto:81`) — per-listener backend-порт.

**Given** редизайн убрал per-listener backend-порт (один backend-порт = одно поле одного ресурса — `TargetGroup.port`)

**When** клиент пытается задать backend-порт на самом listener'е (AS-IS `targetPort`)

**Then** поле **отсутствует** в целевом Listener-контракте (backend-порт живёт **только** на `TargetGroup.port`); нужен другой backend-порт → ссылаться на **другую** (reusable, дешёвую) TargetGroup; наблюдаемость — `resolvedBackendPort°` (эхо, F4/NLB-1-19)

### Сценарий NLB-1-26 (negative): Listener.Create c несуществующим/malformed `loadBalancerId`

**ID:** NLB-1-26

**When** `ListenerService.Create` c `loadBalancerId = "garbage!!"` → sync `INVALID_ARGUMENT "invalid network load balancer id 'garbage!!'"` первым стейтментом; c well-formed-но-нет `loadBalancerId = "nlb-00000000000000"` → within-service FK не резолвит → `FAILED_PRECONDITION "NetworkLoadBalancer nlb-00000000000000 not found"` (owner в той же БД, RESTRICT-FK)

**Then** malformed — sync format-first-statement; absent-owner — within-service by-lane (module-nlb §Правила 12)

### Сценарий NLB-1-54: `proxyProtocolV2` LIVE-mutable на Listener

**ID:** NLB-1-54

> **AS-IS:** `proxy_protocol_v2 = 16` present (`listener.proto:84`). Редизайн держит его LIVE-mutable (module-nlb §Правила 11, listener-пример).

**Given** listener `lst-7h3k9m2x4q8w1t0y` c `proxyProtocolV2=false`

**When** `ListenerService.Update` c `updateMask="proxyProtocolV2"`, `proxyProtocolV2=true`

**Then** после `done` `Get` listener отдаёт `proxyProtocolV2 == true` (LIVE-mutable, не immutable); mutable-класс listener'а — `name`/`description`/`labels`/`targetGroupId`/`proxyProtocolV2` (module-nlb §Правила 11)

---

## F5 — VIP на LoadBalancer: per-family источник (immutable input) + `v4AddressId°`/`v6AddressId°` + VIP-uniqueness (concurrent-race) + placement/zone-coherence

> `→ module-nlb` §VIP — свойство LoadBalancer'а, §Правила 6/10/12 · `→ unified §5 инв-2 (placement-coherence)`, `§8 B17`
> **Детальные Given-When-Then этой фичи живут в под-фазе 1b** (`sub-phase-NLB-1b-…` §F5) — здесь
> зафиксирован только контракт-инвариант, чтобы родитель и ребёнок не разъезжались.
>
> **Якорь VIP — NetworkLoadBalancer.** LB несёт максимум один `vpc.Address` на семейство; источник
> задаётся per-family на `Create` (`v4Source`/`v6Source`: `subnetId` auto-alloc | `addressId` link |
> `public{}` платформенный), immutable, input-only; наружу идёт только id связанного Address
> (`v4AddressId°`/`v6AddressId°`) — сама IP-строка на публичной поверхности nlb не дублируется.
> **Listener адресных полей не несёт** (`region_id`/`ip_version`/`address_id`/`allocated_address`/
> `subnet_id` — `reserved` в proto): он открывает `(port, protocol)` на VIP родительского LB, ничего
> не аллоцирует и на Delete ничего не освобождает.

| Инвариант | Где энфорсится | Наблюдаемый исход |
|---|---|---|
| один адрес на (регион, семейство) | partial-UNIQUE `(region_id, address_v4) WHERE address_v4 <> ''` + v6-близнец (`CONCURRENTLY`, self-heal + assert валидности) | generic `FAILED_PRECONDITION "could not assign address to load balancer"` (анти-oracle; **не** `ALREADY_EXISTS`) |
| один VIP на LB на семейство | CAS-attach `WHERE id=$1 AND (address_v4='' OR address_v4=$2)` (ban #10, не check-then-act) | `FAILED_PRECONDITION "load balancer already has an address for this family"`; повтор того же адреса — no-op |
| одна привязка `(VIP, port, protocol)` | `UNIQUE (load_balancer_id, port, protocol)` на listener'ах — при одном VIP на семейство это и есть VIP-уникальность порта | `ALREADY_EXISTS` |
| источник × режим | sync-матрица ДО `Operation` | `INVALID_ARGUMENT "subnet address source is only valid for INTERNAL load balancer"` / `"public address source is only valid for EXTERNAL load balancer"` / `"load balancer must declare a vip source for at least one ip family"` |
| placement/region/network/zone-coherence источника | sync peer-validate vpc ДО `Operation`; fail-closed | `"subnet placement does not match load balancer placement"` · `"load balancer vip subnet must be in the same region as the load balancer"` · `"dualstack load balancer families must resolve to the same network"` · `"dualstack load balancer families must resolve to the same zone"`; через `addressId`-линк всё сворачивается в анти-oracle `"Illegal argument addressId"`; vpc down → `UNAVAILABLE` |
| recycle-on-delete (B17) | `LoadBalancer.Delete` + компенсация Create-саги + фоновый reconciler застрявших `CREATING`/`DELETING` | `vipOrigin=auto` → `ClearReference`+`FreeIP` (в пул); `vipOrigin=linked` → только `ClearReference` (адрес остаётся у тенанта) |

**Listener-level partial-UNIQUE `(region_id, allocated_address, port, protocol)` контрактом НЕ является**
и в схеме отсутствует: он энфорсил бы колонку, которую ни один прод-путь не пишет.


---

## F6 — TargetGroup: region-scoped LB-agnostic reusable; single `port`; embedded HealthCheck oneof-replace; teardown RESTRICT

> `→ module-nlb` §TargetGroup + §HealthCheck, §Правила 9/11/13 · `→ unified §2 nlb, §8 B8`
> **AS-IS:** `TargetGroup` region-scoped (`region_id = 7`), embedded `HealthCheck health_check = 10`,
> `deregistration_delay_seconds int32`/`slow_start_seconds int32` (`target_group.proto:52-56`). **У TG
> НЕТ поля `port`** (backend-порт был per-listener `target_port`). `HealthCheck` AS-IS несёт `name`
> (**required** — `health_check.proto:32`) и oneof `tcp_options{port}`/`http_options{port,path}`
> (`:47-55`). Редизайн: net-new `TargetGroup.port` (единственный backend-порт); HealthCheck теряет
> `name`/id (embedded value object, не ресурс), oneof расширяется до `tcp`/`http{path,expectedCodes,
> host,headers}`/`https{...}`/`grpc{serviceName}`, `probe.port` наследует `TG.port` отсутствием →
> `effectivePort°`; duration-строки (B8).

### Сценарий NLB-1-34: happy — TargetGroup.Create c `port` + `healthCheck`; region-scoped reusable

**ID:** NLB-1-34

**Given** проект `prj-f9k2m4x7q1w8r3n5`, регион `eu-north` существуют; вызывающий — editor проекта

**When** `TargetGroupService.Create` (`POST /nlb/v1/targetGroups`) c payload:
  - `projectId`, `regionId = "eu-north"`, `name = "web-backends"`
  - `port = 8080`
  - `healthCheck = { interval:"2s", timeout:"1s", healthyThreshold:2, unhealthyThreshold:2, http:{ path:"/healthz", expectedCodes:"200-299" } }`

**Then** после `done` `Get` TG отдаёт `port == 8080` (единственный backend-порт пула), `regionId == "eu-north"`, `healthCheck.effectivePort° == 8080` (`probe.port` опущен → наследует `TG.port`), `status == "ACTIVE"`
**And** TG **LB-agnostic**: та же TG может быть wired несколькими listener'ами разных LB (region-coherence, не привязка к LB); zone-coherence — на wire к ZONAL-LB (→ NLB-2)

### Сценарий NLB-1-35 (negative): `TargetGroup.port` вне `1..65535` → `INVALID_ARGUMENT`

**ID:** NLB-1-35

**When** `TargetGroupService.Create` c `port = 0` (или `> 65535`)

**Then** `INVALID_ARGUMENT` (backend-порт `1..65535`); отсутствие `port` — required-поле пула (net-new relative to AS-IS)

### Сценарий NLB-1-36: HealthCheck скалярный dotted-mask PATCH — merge-validated

**ID:** NLB-1-36

**Given** TG c `healthCheck = { interval:"2s", timeout:"1s", healthyThreshold:2, unhealthyThreshold:2, http:{...} }`

**When** `TargetGroupService.Update` c `updateMask="healthCheck.interval"`, `healthCheck.interval="3s"`

**Then** **частичный мёрж** (проба не трогается); валидируется **МЕРЖ**: `interval="3s"` перевалидируется против **хранимого** `timeout="1s"` (`timeout < interval` на смёрженном объекте — ok); `probe`-тип и sibling-скаляры целы (module-nlb §HealthCheck)
**And** нарушение cross-field (`timeout="4s"` при `interval="2s"`, `timeout < interval` ложно) → `INVALID_ARGUMENT`; bounds `interval∈[1s,300s]`, threshold `2..10`

### Сценарий NLB-1-37: HealthCheck probe atomic-replace — sibling-скаляры уцелевают при смене типа пробы

**ID:** NLB-1-37

**Given** TG c `healthCheck = { interval:"3s", timeout:"1s", healthyThreshold:5, unhealthyThreshold:4, http:{path:"/healthz",...} }` (тюненые скаляры)

**When** `TargetGroupService.Update` c `updateMask="healthCheck.grpc"`, `healthCheck.grpc={serviceName:"grpc.health.v1.Health"}` (смена пробы http→grpc)

**Then** **atomic-replace** скоупится **ровно в probe-oneof**: проба становится `grpc`, а sibling-скаляры (`interval:"3s"`, `timeout:"1s"`, `healthyThreshold:5`, `unhealthyThreshold:4`) **переживают** смену (не сбрасываются в дефолт — regression-lock «probe-type switch preserves tuned scalars», module-nlb §HealthCheck)
**And** `effectivePort° == TG.port` (grpc-проба без `port`-override)

### Сценарий NLB-1-38 (negative): маска на пробу без дискриминатора → `INVALID_ARGUMENT` (не silent-clear)

**ID:** NLB-1-38

**When** `TargetGroupService.Update` c `updateMask="healthCheck.http"` (или generic `healthCheck` c probe-oneof), но **тело пробы пусто** / дискриминатор не задан

**Then** `INVALID_ARGUMENT` — при atomic-replace пробы дискриминатор (`http`/`tcp`/`grpc`/`https`) **обязан** присутствовать; **НЕ** silent-clear пробы (module-nlb §HealthCheck)

### Сценарий NLB-1-39: `probe.port` override → `effectivePort°` отражает override

**ID:** NLB-1-39

**Given** TG c `port=8080`

**When** `TargetGroupService.Update` c `healthCheck.https={ port:8443, path:"/healthz", expectedCodes:"200,204" }` (явный probe-port override)

**Then** `Get` TG отдаёт `healthCheck.effectivePort° == 8443` (override пробы); backend-`port` пула остаётся `8080` — расхождение probe-vs-traffic **видимо by construction** (module-nlb §Правила 9)

### Сценарий NLB-1-40 (negative): `regionId`/`projectId` immutable в Update TG

**ID:** NLB-1-40

**Given** TG `tgr-2w8r4t6y1u3i5o7p` c `regionId="eu-north"`, `projectId="prj-…"`

**When** `TargetGroupService.Update` c `updateMask="regionId"` (или `projectId`)

**Then** **reject ДО `UpdateMask`** → `INVALID_ARGUMENT "<field> is immutable after TargetGroup.Create"` (TG region-scoped immutable — module-nlb §Правила 11)

### Сценарий NLB-1-41 (negative): Delete TG, на которую ссылается listener → `FAILED_PRECONDITION` (RESTRICT, blocker-list)

**ID:** NLB-1-41

**Given** TG `tgr-2w8r4t6y1u3i5o7p` wired listener'ом `lst-7h3k9m2x4q8w1t0y` (FK RESTRICT)

**When** `TargetGroupService.Delete`

**Then** `FAILED_PRECONDITION "target group is referenced by listeners: [lst-7h3k9m2x4q8w1t0y]"` (RESTRICT product-decision, precheck **перечисляет** блокирующие id, чтобы порядок не угадывался — module-nlb §Правила 13); Delete проходит только после смены/обнуления `targetGroupId` всех ссылающихся listener'ов

### Сценарий NLB-1-42: `deregistrationDelay`/`slowStart` — duration-строки (B8), LIVE-mutable

**ID:** NLB-1-42

> **AS-IS:** `deregistration_delay_seconds int32` (0-3600), `slow_start_seconds int32` (0-900) — **scalar
> секунды**. Редизайн: duration-строки `"300s"`/`"0s"` под `google.protobuf.Duration` (**B8** nlb-канон).

**When** `TargetGroupService.Update` c `updateMask="deregistrationDelay"`, `deregistrationDelay="300s"` (duration-строка)

**Then** после `done` `Get` TG отдаёт `deregistrationDelay == "300s"`, `slowStart == "0s"` (duration-строки, не int-секунды); bounds `deregistrationDelay∈[0s,3600s]`, `slowStart∈[0s,900s]`
**And** **[B8]** это breaking proto-change (int32-seconds → Duration); nlb — duration-канон модуля (§DoD deliverables); `interval`/`timeout` уже AS-IS Duration (`health_check.proto:35/38`)

### Сценарий NLB-1-56: `TargetGroup.port` LIVE-mutable → wired-listener `resolvedBackendPort°` ре-эхается

**ID:** NLB-1-56

**Given** TG `tgr-2w8r4t6y1u3i5o7p` c `port=8080`, на неё wired listener `lst-7h3k9m2x4q8w1t0y` (`resolvedBackendPort° == 8080`, F4/NLB-1-19)

**When** `TargetGroupService.Update` c `updateMask="port"`, `port=9090` (LIVE-mutable — module-nlb §Правила 11)

**Then** после `done` `Get` TG отдаёт `port == 9090`; `Get` wired-listener'а отдаёт **ре-эхнутый** `resolvedBackendPort° == 9090` (единственная LIVE-mutable-мутация, рябящая в derived-поле другого ресурса); `healthCheck.effectivePort°` следует `TG.port` (если `probe.port` не override)
**And** это отличается от repoint listener'а (NLB-1-22, где меняется сама ссылка) — здесь меняется backend-порт **той же** TG

---

## F7 — one-shot Create + teardown RESTRICT + op-poll + deletionProtection + pagination-before-listauthz + name-UNIQUE race

> `→ module-nlb` §RPC surface, §Правила 2/3/13/15/16 · `→ unified §1 conv-2/3, §8 B8`
> **AS-IS:** мутации уже возвращают `Operation` (async, `network_load_balancer_service.proto`); `List`
> exempt от per-RPC Check, фильтруется listauthz (`:40`); `deletion_protection = 14` present.

### Сценарий NLB-1-43: happy — one-shot `NetworkLoadBalancer.Create` c `listenerSpecs[]` (existing TG)

**ID:** NLB-1-43

**Given** TG `tgr-2w8r4t6y1u3i5o7p` (`port=8080`) существует; проект+регион ok; вызывающий — editor проекта

**When** `NetworkLoadBalancerService.Create` c payload:
  - `projectId`, `regionId="eu-north"`, `placement="EXTERNAL_REGIONAL"`, `name="edge"`
  - `v4Source = { public: {} }` (источник VIP LB — обязателен хотя бы для одного семейства)
  - `listenerSpecs = [ { name:"tcp-443", port:443, protocol:"TCP", targetGroupId:"tgr-2w8r4t6y1u3i5o7p" } ]`

**Then** `Operation`; `metadata.networkLoadBalancerId` доступен **сразу** (до `done`); сервер разворачивает LB + listener + VIP-сагу **в одной Operation** в dependency-порядке; после `done=true` (`!error`) `Get` LB отдаёт `status=ACTIVE`, listener wired (`substatus=OK`)
**And** listenerSpec может нести inline `targetGroup{port, healthCheck}` (**без** `targets[]` — targets → NLB-2) ЛИБО existing `targetGroupId`; FK-топология скрыта от клиента (module-nlb §Правила 4)

### Сценарий NLB-1-44: happy — async op-poll модель (Get sync, Create/Update/Delete async)

**ID:** NLB-1-44

**Given** вызывающий создаёт LB

**When** клиент поллит `OperationService.Get(id)` (`GET /nlb/v1/operations/{id}`) до `done=true`

**Then** `done=true` = ресурс **DURABLE** (row закоммичена) — **не** downstream-видимость (ban #9, conv-3); Watch RPC нет; первый `Get`/`Update`/`Delete` своего свежего LB может кратко отдать `403`/`404` (owner-tuple EC-окно) — **read-your-writes лаг**, оборачивается client-side `retry_until_authorized` (bounded), НЕ серверным confirm-барьером
**And** `Operation.metadata.readReadyHintMs` — НЕ-authoritative hint окна (сервер `done` на него не гейтит)

### Сценарий NLB-1-45 (negative): Delete LB c listener'ами → `FAILED_PRECONDITION` (blocker-list)

**ID:** NLB-1-45

**Given** LB `nlb-1a2b3c4d5e6f7g8h` c listener'ами `[lst-7h3k9m2x4q8w1t0y, lst-5k7m9q1w3e5r7t9y]`

**When** `NetworkLoadBalancerService.Delete` (без `cascade`)

**Then** `FAILED_PRECONDITION "network load balancer has listeners: [lst-7h3k9m2x4q8w1t0y, lst-5k7m9q1w3e5r7t9y]"` (RESTRICT, precheck перечисляет блокеры — module-nlb §Правила 13)

### Сценарий NLB-1-46: `Delete{cascade:true}` — within-service каскад listener'ов в одной Operation

**ID:** NLB-1-46

**Given** LB c listener'ами; референсимые TG — cross-service reusable (не within-service child)

**When** `NetworkLoadBalancerService.Delete` c body `{cascade:true}`

**Then** детерминированный **within-service** каскад: listener'ы удаляются (+ VIP освобождается) в **одной** Operation (ban #4 — нет cross-service cascade); TG — **detach** (обнуление ссылки), **не** delete (TG — cross-LB reusable, чужой lifecycle)

### Сценарий NLB-1-47 (negative): `deletionProtection=true` блокирует Delete

**ID:** NLB-1-47

**Given** LB c `deletionProtection=true`, без listener'ов

**When** `NetworkLoadBalancerService.Delete`

**Then** `FAILED_PRECONDITION` (sync-precheck deletion-protection — module-nlb §Правила 12/13); `deletionProtection` — LIVE-mutable (сначала `Update` в `false`, затем Delete)

### Сценарий NLB-1-48 (negative): garbage `pageToken` в List → `INVALID_ARGUMENT` ДО listauthz short-circuit

**ID:** NLB-1-48

**Given** вызывающий без грантов (empty listauthz-grant) вызывает `NetworkLoadBalancerService.List` c `pageToken="!!garbage!!"` (или `pageSize=5000`)

**When** `List` (`GET /nlb/v1/networkLoadBalancers?projectId=…&pageToken=!!garbage!!`)

**Then** `INVALID_ARGUMENT` (pagination-validate **ДО** listauthz empty-grant short-circuit — иначе garbage-token / `pageSize>1000` при пустом гранте утекут в `200 {[]}`; api-conventions Gotcha, module-nlb §Правила 14/16); `pageSize` вне `[0..1000]` — **отвергается, не clamp'ится**
**And** валиден для `List` всех трёх ресурсов (NLB/Listener/TG)

### Сценарий NLB-1-49 (negative): duplicate `name` в проекте → `ALREADY_EXISTS`

**ID:** NLB-1-49

**Given** LB c `name="edge"` уже существует в `prj-f9k2m4x7q1w8r3n5`

**When** `NetworkLoadBalancerService.Create` со вторым `name="edge"` в том же проекте

**Then** `ALREADY_EXISTS` (UNIQUE(project,name) partial — пустое `name` допустимо; module-nlb §Правила 16); аналогично TG UNIQUE(project,name) и Listener UNIQUE(loadBalancer,name)

### Сценарий NLB-1-50 (concurrent-race): две конкурентные Create одинакового `name` → ровно одна проходит

**ID:** NLB-1-50

**Given** (integration, testcontainers, concurrent goroutines) две горутины одновременно вызывают `NetworkLoadBalancer.Create` c одинаковыми `projectId`+`name="edge"`

**When** обе коммитят в один момент

**Then** **ровно одна** проходит, вторая → `ALREADY_EXISTS` (partial-UNIQUE(project,name) держит; не оба, не second-writer-wins); под `-race` детерминированно (blocker держит слот, не `time.Sleep`)

### Сценарий NLB-1-57: happy — one-shot inline `targetGroup{port, healthCheck}` config-only → standalone reusable TG создаётся

**ID:** NLB-1-57

> **Дефолт Q3 (review раунд 1):** NLB-1 one-shot принимает inline `targetGroup{port, healthCheck}` **без** `targets[]` (config-only). TG без таргетов — валидный config-объект: wired-listener резолвит пустой пул → `substatus OK` → LB `ACTIVE` (согласуется c NLB-1-17). Полный one-shot c inline `targets[]` + saga-compensation → **NLB-2**.

**Given** TG нет заранее; проект+регион ok; вызывающий — editor проекта

**When** `NetworkLoadBalancerService.Create` c `placement="EXTERNAL_REGIONAL"`, `regionId="eu-north"` и
  - `listenerSpecs = [ { name:"tcp-443", port:443, protocol:"TCP", ipVersion:"IPV4", targetGroup:{ port:8080, healthCheck:{ interval:"2s", timeout:"1s", healthyThreshold:2, unhealthyThreshold:2, tcp:{} } } } ]`

**Then** сервер разворачивает **в одной Operation** в dependency-порядке: TG (config-only, без таргетов) → listener wired на неё → VIP-сага; после `done` созданная TG **Get-able как standalone reusable region-scoped ресурс** со своим `tgr-`-id (не «скрытый child»); listener `substatus=OK`, `resolvedBackendPort°=8080`; LB `status=ACTIVE`
**And** созданная TG переиспользуема (LB-agnostic) — на неё может навестись другой listener/LB (F6/NLB-1-34)

### Сценарий NLB-1-58 (negative): inline `targetGroup` c `targets[]` → defer NLB-2; inline TG без `port` → `INVALID_ARGUMENT`

**ID:** NLB-1-58

**Given** граница NLB-1/NLB-2: target-membership (4-way identity) — NLB-2

**When** клиент шлёт one-shot c inline `targetGroup{ port:8080, targets:[{instance:{id:"ins-…"}}] }` (targets внутри inline-TG)

**Then** **отклоняется в NLB-1** — inline `targets[]` не поддержан (targets → NLB-2 `:addTargets`; сообщение actionable: добавить таргеты после создания через `TargetGroupService.AddTargets`); реализация NLB-1 принимает inline `targetGroup` **только** c `{port, healthCheck}`
**And** inline `targetGroup` **без** обязательного `port` → `INVALID_ARGUMENT` (`port` — required-поле пула, F6/NLB-1-35)

---

## Definition of Done

NLB-1 готова к merge только при выполнении ВСЕГО чек-листа (`ai-tooling.md` §lifecycle gate 4-7; `testing.md`):

**Traceability + тесты (1-to-1):**
- [ ] Каждый `NLB-1-NN` имеет зелёный **integration-тест** (testcontainers Postgres 16) —
  `Test<Resource>_NLB_1_NN` (напр. `TestListener_NLB_1_31`) — покрывающий SQL-сторону, включая
  CAS/UNIQUE/EXCLUDE. **Обязательные concurrent-race под `-race`, детерминированно (blocker держит слот,
  не `time.Sleep`): NLB-1-31** (VIP partial-UNIQUE `(region,ip,port,protocol)` race) **и NLB-1-50**
  (name UNIQUE(project,name) race).
- [ ] Каждый `NLB-1-NN` (наблюдаемый через api-gateway) имеет зелёный **newman-кейс**
  `tests/newman/cases/*.py` c аннотацией `# verifies NLB-1-NN` — ≥1 happy + ≥1 negative per фича;
  трассировка `NLB-1-NN ↔ Test<R>_NLB_1_NN ↔ cases/*.py`. Фикстур-ресурсы несут `{{runId}}`-суффикс
  (идемпотентность прогона); op-poll проверяет `!op.error` **перед** извлечением id из `metadata`.
- [ ] TDD-порядок соблюдён: RED (падает по нужной причине) ДО кода, пара RED→GREEN в PR.

**e2e-smoke (real gateway, construction-verified):**
- [ ] one-shot: `NetworkLoadBalancer.Create` c `listenerSpecs[].targetGroupId` (existing TG) →
  `metadata.networkLoadBalancerId` сразу; после `done` LB `status=ACTIVE`, listener `substatus=OK`,
  `resolvedBackendPort° == TG.port` (F4/F7).
- [ ] derived: `Get` LB отдаёт `type°`/`placementType°` из `placement`; `Get` TG отдаёт
  `healthCheck.effectivePort°` (F2/F6) — на реальном gateway-ответе.
- [ ] two-projection field-absence: public LB/Listener/TG НЕ содержат инфра-полей (node/underlay/vrf/
  programming-status) — те живут только в `*Internal*` (:9091, → NLB-3); NLB-1 assert'ит field-absence.
- [ ] read-your-writes: первый Get/Update/Delete своего свежего LB/Listener/TG обёрнут bounded-retry
  (`retry_until_authorized`) на transient 403/404 (owner-tuple EC-окно, conv-3).

**Deliverables редизайна (implementer обязан выполнить — иначе AS-IS-путь остаётся):**
- [ ] **NetworkLoadBalancer:** слить AS-IS `type`(required)+`placement_type` → **один immutable input**
  `placement ∈ {EXTERNAL_REGIONAL,INTERNAL_REGIONAL,INTERNAL_ZONAL}`; `type°`/`placementType°` →
  **derived output-only** (write → explicit reject); снять `Start`/`Stop` RPCs + `STARTING/STOPPING/
  STOPPED`-статусы → `adminState: ENABLED|DISABLED` (LIVE-mutable) + `status` DISABLED-глосса; снять
  `disabled_announce_zones` → `crossZoneEnabled` (REGIONAL-only, ZONAL-guard); **вернуть**
  `securityGroupIds` (firewall VIP, same-project existence, LIVE-mutable); managed `address.hostname°`;
  `status` auto-recompute DB-триггер (ACTIVE/DEGRADED/INACTIVE/DISABLED).
- [ ] **Listener:** снять M:N `attached_target_groups`-pivot + `AttachTargetGroup`/`DetachTargetGroup`
  RPCs; `default_target_group_id` → **единственный authoritative** `targetGroupId` (FK RESTRICT);
  снять per-listener `target_port` (backend-порт на TG); `substatus°`/`resolvedBackendPort°` (derived);
  адресных полей листенер **не получает** (`ip_version`/`address_id`/`allocated_address`/`subnet_id`/
  `region_id` остаются `reserved` в proto) — Create чистый INSERT, Delete VIP не трогает.
- [ ] **VIP (на LoadBalancer):** per-family immutable input `v4Source`/`v6Source` → output-only
  `v4AddressId°`/`v6AddressId°`; per-region partial-UNIQUE `(region_id, address_v4/_v6)` + `AttachVIP`
  CAS single-VIP-per-LB; **VIP recycle-on-delete** (unified §8 B17): `LoadBalancer.Delete` возвращает
  `auto`-VIP в пул / снимает референс `linked` (concurrent alloc/free + re-create integration-lock,
  NLB-1-55/31); мёртвый listener-level `listeners_region_vip_uniq` снят новой миграцией (ban #5 —
  прежние не редактируются).
- [ ] **TargetGroup:** net-new `port` (единственный backend-порт, required); embedded `HealthCheck`
  снять `name`/id → oneof расширить (`tcp`/`http{path,expectedCodes,host,headers}`/`https`/`grpc{serviceName}`),
  `probe.port` наследует `TG.port` → `effectivePort°`; oneof-replace дисциплина (scalar dotted-mask
  PATCH merge-validated + probe atomic-replace scalar-preservation); **[B8]** `deregistration_delay_seconds`/
  `slow_start_seconds` int32 → `deregistrationDelay`/`slowStart` **duration-строки**.
- [ ] **FGA object-type (дефолт Q1 — hard-rename в NLB-1):** AS-IS `lb_network_load_balancer`/`lb_listener`/
  `lb_target_group` → **`nlb_*`** (module-nlb §Правила 14) — миграция FGA-модели iam-seed + gateway
  scope_extractor + permission-catalog regen ОДНИМ кросс-cutting change-set'ом (analog registry
  B7-Rosetta, но hard-rename: nlb greenfield в `project/kacho`, не GA → миграционной массы tuple'ов нет).
  Verify: `permission-catalog-check` byte-identical + `scope_extractor nlb_* → project` + newman authz-кейс
  (editor-on-`nlb_network_load_balancer`). **NB (дефолт Q2):** permission-string namespace `loadbalancer.*`
  и proto-package `loadbalancer.v1` → `nlb.*`/`nlb.v1` — **не** ядровая форма, вынесено в **NLB-4 cutover**
  (§Out-of-scope); object-type (Q1, tenant-facing authz) и permission-string (Q2, не tenant-facing) —
  независимые аннотации, split когерентен.
- [ ] **Не** редактировать применённые миграции (`0001`–`0014`) — только новые (`0015+`).
- [ ] **[PHASE-0-GATED B3]:** id-prefix `nlb`/`lst`/`tgr` → `nlb-`/`lst-`/`tgr-` (hyphen) приземляется
  вместе c corelib prefix→type-router; до Phase-0 строим на текущей 3-char, hyphen-переход — атомарный
  шаг c change-set (сценарии формулируют target hyphen-форму, не редактировать).

**Проектные гейты (финальная верификация):**
- [ ] `go test ./... -race` · `golangci-lint run` · `govulncheck` · `make audit-list-filter` зелёные.
- [ ] `make -C gateway permission-catalog-check` byte-identical (новые/изменённые RPC — записи в каталоге; снятые
  `start`/`stop`/`attachTargetGroup`/`detachTargetGroup` — удалены); proto — `buf lint`/`buf breaking`
  (breaking-changes задекларированы: placement-слияние, start/stop-drop, attach/detach-drop, target_port-drop,
  duration-rename, FGA-type rename) зелёные после регена. proto ревьюит `proto-api-reviewer`; миграции —
  `db-architect-reviewer`; распределённые аспекты (VIP-сага, status-recompute CAS) — `system-design-reviewer`.
- [ ] authz на КАЖДОМ RPC обоих листенеров: read/discovery → viewer-floor, мутации → editor на
  target-объекте (`nlb_*`), Create → editor на `project`; `scope_extractor` резолвит target→project
  (анти-BOLA); `List` фильтруется listauthz. newman зелёные (все `NLB-1-NN`).

**MERGE-GATE (`[PHASE-0-GATED]` — жёсткий блокер, кросс-фазовые зависимости):**
- [ ] **NLB-1 НЕ мёржится, пока Phase-0 governance change-set не приземлит в `api-conventions.md`/
  `data-integrity.md`** (00-unified §7 Фаза-0 step 3, §9 MUST-close):
  - **B1** — 3-way ref-naming (`ResourceRef`/`Referrer`/`OciReferrer`) в `kacho.cloud.common.v1`.
    *NB:* NLB-1 `Listener.address` (managed VIP) — **generic `Referrer{type,id,name°,ip°,hostname°}`**
    (graceful-dangling на vpc.Address) → nlb-proto нельзя писать до landing shared `common.v1` →
    **build-order gate**.
  - **B3** — id-prefix hyphen-форма (`nlb-`/`lst-`/`tgr-`) в `corevalidate`. Сценарии F1 формулируют
    target-форму; реализация до merge на текущей 3-char, hyphen-переход одним шагом.
  - **conv-11 by-lane split (peer-validate lane) + reason-tokens** — касается **только** peer-validate
    scope-coord absent (NLB-1-05 projectId, NLB-1-11 regionId): AS-IS heterogeneous → target унификация
    `FAILED_PRECONDITION` + reason-token (`PROJECT_NOT_FOUND`/`REGION_NOT_FOUND`). До merge change-set
    NLB-1-05/11 остаются AS-IS кодами. **НЕ** касается within-service `loadBalancerId`/`targetGroupId`
    (NLB-1-26/23 — within-service by-lane, ungated).
- [ ] **[CROSS-MODULE B9]** instance-target resolution — **NLB-2**, не блокирует NLB-1 (ядровая форма
  трёх ресурсов + wiring через `targetGroupId` не зависит от target-membership). NLB-1 фиксирует TG как
  config-объект; зависимость от compute `AttachNetworkInterface`-редизайна помечена и вынесена в NLB-2.

Ungated части (own-only prefix-check/wrong-type/malformed → `INVALID_ARGUMENT`; well-formed-absent →
`NOT_FOUND`; placement-слияние + derived type°/placementType°; adminState/status-recompute; single
authoritative targetGroupId; VIP-anchor + uniqueness race; TG.port + HealthCheck oneof-replace; teardown
RESTRICT blocker-list; op-poll; duration-строки; name-UNIQUE race; two-projection field-absence;
fail-closed `UNAVAILABLE`) строятся в NLB-1 **без** ожидания change-set.

---

## Changelog — что этот док покрывает

- **F1** id-prefix per-type hyphen `nlb-`/`lst-`/`tgr-` **[PHASE-0-GATED B3]**; malformed/**wrong-type**
  first-statement `INVALID_ARGUMENT`; well-formed-absent `NOT_FOUND`; foreign-id (projectId/regionId/
  addressId/subnetId) НЕ prefix-checked B4 (NLB-1-01..05).
- **F2** NetworkLoadBalancer **один immutable input `placement`** (слияние AS-IS `type`+`placement_type`);
  `type°`/`placementType°` derived (write → reject); «external+zonal» невыразим by construction; `placement`/
  `regionId` immutable; regionId peer-geo fail-closed `UNAVAILABLE`; `securityGroupIds` firewall-VIP
  same-project existence LIVE-mutable (region-coherence НЕ проверяется) (NLB-1-06..12, 51..52).
- **F3** `adminState` (LIVE-mutable) заменяет `:start`/`:stop` (AS-IS RPCs+статусы сняты); Update
  never-auto-ENABLE; `crossZoneEnabled != false` на ZONAL → `INVALID_ARGUMENT`; `sessionAffinity`
  LIVE-mutable; status auto-recompute (INACTIVE/ACTIVE/DEGRADED/DISABLED-глоссы) (NLB-1-13..18, 53).
- **F4** Listener **единственный authoritative `targetGroupId`** (FK RESTRICT); AS-IS M:N-pivot +
  `AttachTargetGroup`/`DetachTargetGroup` сняты; `substatus°`/`resolvedBackendPort°` derived; repoint +
  `proxyProtocolV2` LIVE-mutable; per-listener `target_port` снят; immutables; incremental actionable-error
  (NLB-1-19..26, 54).
- **F5** **VIP на LoadBalancer**: per-family immutable input `v4Source`/`v6Source` → output-only
  `v4AddressId°`/`v6AddressId°` (сама IP-строка не дублируется — её отдаёт vpc); VIP-uniqueness
  partial-UNIQUE `(region_id, address_v4/_v6)` → generic `FAILED_PRECONDITION` «could not assign address
  to load balancer» **+ concurrent-race** и `AttachVIP` CAS single-VIP-per-LB; placement/region/network/
  zone-coherence источника; recycle-on-delete по `vip_origin` на `LoadBalancer.Delete` (NLB-1-27..33, 55).
- **F6** TargetGroup region-scoped **LB-agnostic reusable**; net-new single `port` (LIVE-mutable →
  re-echo `resolvedBackendPort°`); embedded HealthCheck oneof-replace (scalar dotted-mask PATCH
  merge-validated + probe atomic-replace scalar-preservation); `effectivePort°`; immutables; teardown
  RESTRICT blocker-list; duration-строки **[B8]** (NLB-1-34..42, 56).
- **F7** one-shot `NetworkLoadBalancer.Create` (listenerSpecs existing-TG **и** inline `targetGroup{port,
  healthCheck}` config-only); teardown RESTRICT blocker-list + `cascade:true`; op-poll async-модель
  (done=durability, ban #9); `deletionProtection`; pagination-validate ДО listauthz; name UNIQUE(project,name)
  **+ concurrent-race** (NLB-1-43..50, 57..58).

Покрытие обязательного минимума (task): NetworkLoadBalancer placement-слияние + derived type°/placementType° +
adminState + managed endpoint ✓ (F2/F3/F5) · Listener single authoritative targetGroupId (M:N-pivot снят) +
resolvedBackendPort° + substatus° ✓ (F4) · TargetGroup region-scoped reusable + single port + HealthCheck
oneof atomic-replace ✓ (F6) · positive+negative+edge на каждую фичу ✓ · concurrent-race UNIQUE/placement
(VIP-uniqueness NLB-1-31, name NLB-1-50) в DoD ✓ · PHASE-0 gating помечен (B3 hyphen, conv-11 by-lane,
B1 build-order) ✓ · [CROSS-MODULE B9] instance-target → NLB-2 отмечено ✓ · B8 duration помечено ✓ ·
Out-of-scope (NLB-2 Target/HealthCheck-diag, NLB-3 discovery/validateOnly/Move/Internal, NLB-4 UI) ✓ ·
non-negotiables (flat, Operation-async, placement-coherence REGIONAL-anycast/ZONAL-zone) ✓.

**Что изменилось в ре-ревью раунд 1** (2 критических + 4 coverage-findings acceptance-reviewer'а + 4
дефолта адресованы): (1) **[критич.#1]** `securityGroupIds` — 0 сценариев → добавлены NLB-1-51/52
(happy+LIVE-mutable+same-project existence+region-coherence-НЕ-проверяется; absent/cross-project/peer-down
fail-closed). (2) **[критич.#2]** one-shot inline `targetGroup` config-only — только `And`-клауза →
выделены NLB-1-57 (happy: standalone reusable TG Get-able) + NLB-1-58 (negative: inline `targets[]`
defer NLB-2, inline TG без `port` → `INVALID_ARGUMENT`). (3) **[#3]** `sessionAffinity` LIVE-mutable →
NLB-1-53. (4) **[#4]** `proxyProtocolV2` (был 0 упоминаний) → NLB-1-54. (5) **[#5]** `TargetGroup.port`
LIVE-mutable Update + re-echo `resolvedBackendPort°` → NLB-1-56. (6) **[#6]** standalone `Listener.Delete`
→ VIP recycle-on-delete (B17) → NLB-1-55 + DoD-deliverable. Итог: 50 → **58 сценариев**.

## Дефолты, зафиксированные на review (раунд 1)

Все 4 прежних open questions разрешены ревьюером и вшиты в сценарии/Scope/Out-of-scope/DoD выше:

1. **FGA object-type `lb_*` → `nlb_*` — ПРИНЯТ hard-rename в NLB-1** (не accepted-synonym). Совпадает c
   `module-nlb §Правила 14` + `unified §2 nlb`; synonym-Rosetta оправдан только для GA-типа c миграционной
   массой tuple'ов — у nlb (greenfield `project/kacho`, не GA) её нет. Verify: permission-catalog
   byte-identical + `scope_extractor nlb_*→project` + newman authz-кейс. Отражено: §DoD deliverables (FGA).
2. **Permission-namespace `loadbalancer.*` + proto-package `loadbalancer.v1` → `nlb.*`/`nlb.v1` — вынесено
   в NLB-4 cutover** (не NLB-1). object-type (Q1, tenant-facing authz-scope) и permission-string/package
   (Q2, не tenant-facing) — независимые аннотации, split когерентен; целевой пакет `nlb.v1` (unified §2)
   зафиксирован явной строкой, чтобы дрейф не был потерян. Отражено: §Out-of-scope NLB-4, §DoD (FGA-NB).
3. **one-shot inline `targetGroup{port, healthCheck}` config-only — ПРИНЯТ в NLB-1** (TG без таргетов =
   валидный config-объект, wired-listener резолвит пустой пул → ACTIVE, согласуется c NLB-1-17). Полный
   one-shot c inline `targets[]` + saga-compensation → NLB-2. Отражено: NLB-1-57/58, §Out-of-scope.
4. **`securityGroupIds` (firewall VIP) — ПРИНЯТ в NLB-1** (реальное `module-nlb §Правила 18`-поле,
   тривиальный same-project existence, LIVE-mutable, без region-coherence). Отражено: F2-scope, NLB-1-51/52,
   §DoD deliverables.

Открытых вопросов к reviewer нет — док готов к повторному review.
