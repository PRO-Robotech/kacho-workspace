# Sub-phase NLB-1b (NetworkLoadBalancer + Listener CORE) — Acceptance

> Статус: **✅ APPROVED** (acceptance-reviewer carve-review, 2026-07-20 — 47 сценариев, партиция 58/58 verified)
> Дата: 2026-07-20
> Ревьюер: acceptance-reviewer — ✅ APPROVED (carve-partition 58/58; non-blocking notes в review-comment)
> Эпик/тикет: KAC-NLB-1 · под-фаза **1b of 4** (carve родительского APPROVED `sub-phase-NLB-1-lb-listener-targetgroup-acceptance.md`)
> Монорепо: `project/kacho` (`github.com/PRO-Robotech/kacho`) — легаси `project/kacho-*` не затрагивается.
> Порядок carve: NLB-1a → **NLB-1b (это)** → NLB-1c → NLB-1d. **Предпосылка: NLB-1a merged** (FGA-типы уже `nlb_*`).

## Обзор

NLB-1b — **entangled atomic core-каскад** редизайна `kacho-nlb`: перекройка формы и проводки
**двух ядровых ресурсов** — `NetworkLoadBalancer` и `Listener` — плюс **co-requisite**
net-new поле `TargetGroup.port` (единственный источник, который эхает `Listener.resolvedBackendPort°`;
полный TargetGroup-redesign — 1c). Это большой, но **ОДИН green-каскад**: proto+Go в монорепе
`project/kacho` — единый compile-unit, поэтому pervasive-удаления (M:N-pivot, `Attach`/`Detach`,
`Start`/`Stop`) ломают билд до завершения всего каскада — «нет малого green-слайса
для core», каскад атомарен по построению.

Порядок внутри каскада (родитель §Найденная цепочка): **VIP-консолидация на LoadBalancer**
(per-family `VipSource` на `LoadBalancer.Create`; Listener адресных полей не несёт) →
**pivot-removal** (M:N `attached_target_groups` + `AttachTargetGroup`/
`DetachTargetGroup` + `Start`/`Stop` заменяются единым authoritative `Listener.targetGroupId`).
Snятие pivot удаляет `attach_target_group.go` — что **разблокирует** HealthCheck-redesign в 1c
(он ломал бы этот файл, если бы шёл раньше).

Ключевые слияния/упрощения (relative AS-IS `proto/kacho/cloud/loadbalancer/v1/*`):
1. **NetworkLoadBalancer** — слить AS-IS `type`(required)+`placement_type` в **один immutable
   input `placement ∈ {EXTERNAL_REGIONAL | INTERNAL_REGIONAL | INTERNAL_ZONAL}`**; `type°`/`placementType°`
   derived output-only; «external+zonal» невыразим by construction. `adminState` (LIVE-mutable)
   заменяет `:start`/`:stop`; `crossZoneEnabled` (REGIONAL-only, ZONAL-guard); `securityGroupIds`
   (firewall VIP, revival); status auto-recompute (ACTIVE/DEGRADED/INACTIVE/DISABLED).
   **VIP — здесь**: per-family immutable input `v4Source`/`v6Source` (`subnetId` | `addressId` |
   `public{}`) → output-only `v4AddressId°`/`v6AddressId°`; per-region partial-UNIQUE +
   single-VIP-per-LB CAS + recycle-on-delete по `vipOrigin`.
2. **Listener** — **единственный authoritative `targetGroupId`** (FK RESTRICT) вместо M:N-pivot +
   attach/detach-RPCs; адресных полей **не несёт** (`ip_version`/`address_id`/`allocated_address`/
   `subnet_id`/`region_id` — `reserved` в proto), Create — чистый INSERT без обращения к vpc;
   `substatus°`/`resolvedBackendPort°` derived; `proxyProtocolV2` LIVE-mutable;
   `UNIQUE (loadBalancerId, port, protocol)`.
3. **TargetGroup.port (co-req)** — net-new bare-field + required-BVA (единственный backend-порт,
   эхается `resolvedBackendPort°`). AS-IS HealthCheck (`name` + `tcp`/`http`) **сохраняется** до 1c
   (unused pivot-код удалён → безопасно). Полный TargetGroup-redesign — §Out-of-scope (1c).

Owner-side под-фаза: сценарии описывают наблюдаемое поведение публичных
`NetworkLoadBalancerService`/`ListenerService` (:9090 → edge REST) + co-req `TargetGroup.port`.

---

## Scope

| # | Фича | Родительские сценарии |
|---|---|---|
| F1 | id-prefix per-type `nlb-`/`lst-`/`tgr-` (hyphen B3); malformed/**wrong-type** → `INVALID_ARGUMENT` первым стейтментом; well-formed-absent → `NOT_FOUND`; foreign-id (projectId/regionId/securityGroupId/instance/nic) **НЕ** prefix-checked (B4). **Записанное исключение** (решено, не «по факту реализации»): `v4Source`/`v6Source` прогоняют `subnetId`/`addressId` через синтаксический gate `corevalidate.ResourceID` ДО peer-validate. Это **не** сверка vpc-префикса: функция family-agnostic (`expectedPrefix` не читается), проверяется членство в платформенном каталоге префиксов. Обоснование и границы — `services/nlb/docs/architecture/08-known-divergences.md` §«Формат чужого id (VIP-источники)» | NLB-1-01..05 |
| F2 | NetworkLoadBalancer: один immutable input `placement`; `type°`/`placementType°` derived; «external+zonal» невыразим; `regionId` immutable + peer-geo (fail-closed); `securityGroupIds` (same-project existence, LIVE-mutable, без region-coherence) | NLB-1-06..12, 51, 52 |
| F3 | `adminState` (LIVE-mutable) заменяет `:start`/`:stop`; Update never-auto-ENABLE; `crossZoneEnabled != false` на ZONAL → `INVALID_ARGUMENT`; `sessionAffinity` LIVE-mutable; status auto-recompute | NLB-1-13..18, 53 |
| F4 | Listener единственный authoritative `targetGroupId` (FK RESTRICT); AS-IS M:N-pivot + `Attach`/`Detach` **сняты**; `substatus°`/`resolvedBackendPort°` derived; repoint + `proxyProtocolV2` LIVE-mutable; immutables; per-listener `target_port` снят | NLB-1-19..26, 54 |
| F5 | **VIP на LoadBalancer**: per-family immutable input `v4Source`/`v6Source` → `v4AddressId°`/`v6AddressId°`; uniqueness — partial-UNIQUE `(region_id, address_v4/_v6)` → generic `FAILED_PRECONDITION` (+ concurrent-race) и CAS single-VIP-per-LB; placement/zone/network-coherence источника; recycle-on-delete по `vipOrigin` на `LoadBalancer.Delete` | NLB-1-27..33, 55 |
| F6-co-req | **TargetGroup.port** net-new bare-field + required-BVA `1..65535` (co-requisite `resolvedBackendPort°`; полная port-семантика/HealthCheck — 1c) | NLB-1-35 |
| F7 | one-shot `NetworkLoadBalancer.Create` (`listenerSpecs[]` **existing** `targetGroupId`); teardown RESTRICT blocker-list + `cascade:true`; op-poll async; `deletionProtection`; pagination-validate ДО listauthz; name UNIQUE(project,name) (+ concurrent-race) | NLB-1-43..50 |

## Out-of-scope (следующая под-фаза — NLB-1c, затем 1d)

**→ NLB-1c (TargetGroup redesign):**
- **TargetGroup HealthCheck oneof-replace** (снять `name`/id, oneof `tcp`/`http`/`https`/`grpc`;
  scalar dotted-mask PATCH merge-validated + probe atomic-replace scalar-preservation; `effectivePort°`)
  — NLB-1-34, 36–39. В 1b TG несёт **AS-IS HealthCheck** (`name` + `tcp`/`http`).
- **TargetGroup immutables** (`regionId`/`projectId`) + **teardown RESTRICT blocker-list на TG.Delete**
  — NLB-1-40, 41. (FK RESTRICT `Listener.targetGroupId → TargetGroup` **создаётся в 1b**; friendly
  blocker-list precheck на `TargetGroup.Delete` — финализируется в 1c с TG-teardown-дисциплиной.)
- **duration-строки** `deregistrationDelay`/`slowStart` (B8) — NLB-1-42.
- **`TargetGroup.port` LIVE-mutable re-echo** `resolvedBackendPort°` + `effectivePort°`-inheritance —
  NLB-1-56, 39. В 1b `port` — set-at-create + BVA; LIVE-mutability + cross-resource ripple — 1c.
- **one-shot inline `targetGroup{port, healthCheck}`** (redesigned-shape) + inline-`targets[]`-reject
  — NLB-1-57, 58.

**→ NLB-1d (gateway/newman/cross-cutting):**
- **Cross-cutting e2e-smoke** (full one-shot через real gateway), **two-projection field-absence**
  (public LB/Listener НЕ несут инфра-полей; Internal-проекция — NLB-3), **umbrella newman closeout /
  parallel-safety**, **authz-matrix cross-account**, **read-your-writes budget-verification**.
  *(NB: per-RPC gateway-регистрация каждого нового public RPC LB/Listener — в **том же PR**, что и
  его реализация в 1b, через `api-gateway-registrar`; 1d — финализация/аудит-coherence, не первичная
  регистрация.)*

**Прямо вне NLB-1 (родитель §Out-of-scope):**
- **Target-membership** (4-way identity, `:addTargets`, health-пробы, `GetTargetStates`), **discovery/
  validateOnly/Move/Internal.Get/EXPAND** — NLB-2/NLB-3. В 1b wired-listener → TG с **пустым пулом**
  резолвится (`substatus OK`) — status-рекомпут таргетов не требует.
- **VIP-saga compensation-механика** (внутренняя последовательность шагов worker'а) — 1b фиксирует **наблюдаемый
  контракт** (VIP аллоцирован/эхнут, uniqueness, immutable источник, placement/zone-coherence, recycle),
  не внутреннюю сагу (`system-design-reviewer` отдельно).
- **FGA owner-tuple материализация** — EC; 1b **не** гейтит `Operation.done` на видимость (ban #9, conv-3).

## Traceability-легенда

`°` = output-only (server-derived/managed; попытка задать derived-дискриминатор `type`/`placementType`
— **explicit reject**). REST `/nlb/v1/…` (:9090, external-safe). JSON camelCase. Timestamps усечены
до секунд (incl. embedded). Каноническое существительное — **NetworkLoadBalancer**; error-тон
`"<Resource> <id> not found"`; precondition-list — литеральные строчные тексты (часть контракта).
**[PHASE-0-GATED]** = зависит от Phase-0 change-set (см. §MERGE-GATE). **[B3]** hyphen id-prefix.

---

## F1 — id-prefix per-type (hyphen B3) + malformed/wrong-type/absent first-statement + foreign-id B4

> `→ родитель F1` · `→ api-conventions.md §Naming (id-prefix hyphen-канон B3), §Error-format by-lane`
> **AS-IS:** prefix `PrefixLoadBalancer="nlb"`/`PrefixListener="lst"`/`PrefixTargetGroup="tgr"`
> (`pkg/ids/ids.go` — 3-char, БЕЗ дефиса); `PrefixOperationNLB == PrefixLoadBalancer` (quirk).
> `corevalidate.ResourceID` first-statement существует в vpc/compute; nlb приводится к нему.
> **[PHASE-0-GATED B3]:** переход `nlb`/`lst`/`tgr` → `nlb-`/`lst-`/`tgr-` (hyphen) — Phase-0
> (`corevalidate`+`api-conventions.md`). Сценарии формулируют **target hyphen-форму**; до merge —
> 3-char. Wrong-type-detect и own-only B4 — **ungated**.

### Сценарий NLB-1-01: happy — Get по валидному id каждого из трёх типов

**ID:** NLB-1-01

**Given** существуют `nlb-1a2b3c4d5e6f7g8h`, `lst-7h3k9m2x4q8w1t0y`, `tgr-2w8r4t6y1u3i5o7p` в проекте `prj-f9k2m4x7q1w8r3n5`

**When** клиент вызывает `NetworkLoadBalancerService.Get` (`GET /nlb/v1/networkLoadBalancers/nlb-1a2b3c4d5e6f7g8h`)

**Then** `200 OK`; тело — public `NetworkLoadBalancer` c `id == "nlb-1a2b3c4d5e6f7g8h"`, `projectId`, `regionId`, `createdAt°` (усечён до секунд)
**And** аналогично `ListenerService.Get`/`TargetGroupService.Get` возвращают ресурс с соответствующим `id` (TargetGroup — targetable-ресурс с co-req `port`; полный HealthCheck-redesign — 1c, но Get-форма стабильна по `id`/`projectId`/`regionId`/`createdAt`)

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

> **AS-IS:** nlb peer-validate'ит `projectId` (`iam.ProjectService.Get`) и `regionId` (`geo.RegionService.Get`). Прочие foreign id (instance/nic/`securityGroupId`) — existence-only, без format-check.

**Given** клиент создаёт NetworkLoadBalancer c `projectId = "not-a-prj-slug"` (проходит длину `<=50`, но не nlb-owned prefix) и корректным `placement`/`regionId`

**When** `NetworkLoadBalancerService.Create` (`POST /nlb/v1/networkLoadBalancers`)

**Then** отказ приходит **не** как format-`"invalid project id"` (foreign scope-coord iam-owned — **не** prefix-checked, B4 own-only), а как **peer-validate existence-result** через `iam.ProjectService.Get`
**And** конкретный код: **AS-IS `NOT_FOUND "Project not-a-prj-slug not found"`**; **[PHASE-0-GATED conv-11]** target по by-lane peer-validate → `FAILED_PRECONDITION` (единая полоса projectId/regionId; §MERGE-GATE)
**And** для VIP-источников LB (`v4Source`/`v6Source`) действует **записанное узкое исключение** из B4 (решение принято, см. `services/nlb/docs/architecture/08-known-divergences.md` §«Формат чужого id (VIP-источники)»): `subnetId`/`addressId` проходят синтаксический gate ДО peer-validate. Гейт **family-agnostic** — `corevalidate.ResourceID` не читает `expectedPrefix`, а проверяет членство первого сегмента в **платформенном** каталоге (`ids.KnownPrefixes()`/`KnownHyphenPrefixes()` + config-extras); приватный словарь vpc не копируется, тип чужого ресурса локально не утверждается (`nlb…`-id проходит и уезжает к владельцу). Мотив — что видит вызывающий: явно-не-id получает **терминальный** `INVALID_ARGUMENT "invalid subnet id '<X>'"` вместо retryable `UNAVAILABLE` при недоступном vpc и вместо ложного `"subnet <X> not found"`. Existence/тип/placement в любом случае подтверждает peer-vpc (см. F5)
**And** пустая ссылка выбранной ветки oneof (`v4Source{subnetId:""}`) — ошибка **формы запроса**: `INVALID_ARGUMENT "v4_source.subnet_id: required"` (симметрично `v6_source.address_id`), владельцу вопрос не задаётся. Прежде пустая строка доезжала до peer-адаптера и возвращалась как `"subnet  not found"` — контракт-тон отсутствия с вырезанным id

---

## F2 — NetworkLoadBalancer: один immutable input `placement`; `type°`/`placementType°` derived; regionId immutable+peer-geo; securityGroupIds

> `→ родитель F2` · `→ 00-kacho-core.md §product (VPC/Compute domains)`, `data-integrity.md §placement-coherence`
> **AS-IS (слияние):** раздельные `Type type = 10` (EXTERNAL/INTERNAL, required input) + `PlacementType
> placement_type = 27` (ZONAL/REGIONAL, input, required для INTERNAL, запрещён для EXTERNAL). Редизайн
> **сливает** в один immutable input `placement`; `type°`/`placementType°` — derived output-only
> (persist один факт — `placement`). `region_id = 7` present + peer-validate geo. `security_group_ids`
> был reserved на LB (`network_load_balancer.proto:37`) — редизайн возвращает.

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
**And** zone `eu-north-a` ∈ регион `eu-north` (peer-validate geo); mismatch зоны и региона → `FAILED_PRECONDITION` (см. F5 / NLB-1-32/33)

### Сценарий NLB-1-08 (negative): write `type`/`placementType` в теле Create → explicit reject

**ID:** NLB-1-08

**Given** `type`/`placementType` — derived output-only (не входные поля в целевой модели)

**When** клиент шлёт Create c `placement="INTERNAL_ZONAL"` **и** одновременно `type="EXTERNAL"` (либо `placementType="REGIONAL"`) в теле

**Then** **explicit reject** `INVALID_ARGUMENT` (derived-дискриминатор нельзя задать на вход — не silent-ignore; сообщение указывает, что источник режима — единственный вход `placement`)
**And** это **breaking-delta** от AS-IS, где `type` был required-input, а `placement_type` — writable

### Сценарий NLB-1-09 (edge): «external+zonal» невыразим by construction

**ID:** NLB-1-09

**Given** enum `placement` содержит **ровно** `{EXTERNAL_REGIONAL, INTERNAL_REGIONAL, INTERNAL_ZONAL}` — значения `EXTERNAL_ZONAL` **нет**

**When** клиент пытается выразить «внешний зональный» LB

**Then** комбинация **невыразима by construction** (не runtime-reject): в proto-enum нет соответствующего значения; клиент физически не может отправить нелегальную ячейку
**And** это архитектурная гарантия слияния (в отличие от AS-IS, где `type=EXTERNAL`+`placement_type=ZONAL` были бы двумя валидными полями, требующими runtime-cross-check)

### Сценарий NLB-1-10 (negative): `placement`/`regionId` immutable в Update

**ID:** NLB-1-10

**Given** LB `nlb-1a2b3c4d5e6f7g8h` создан c `placement="EXTERNAL_REGIONAL"`

**When** `NetworkLoadBalancerService.Update` c `updateMask="placement"` (или `regionId`)

**Then** **reject ДО `UpdateMask`-обработки** (immutable-switch первым) → `INVALID_ARGUMENT "placement is immutable after NetworkLoadBalancer.Create"`
**And** аналогично `regionId` → `"region_id is immutable after NetworkLoadBalancer.Create"`

### Сценарий NLB-1-11 `[PHASE-0-GATED conv-11]` (negative): несуществующий `regionId` → peer-validate geo

**ID:** NLB-1-11

> **AS-IS:** nlb peer-validate'ит region через `geo.RegionService.Get`. Целевой by-lane тон (conv-11) — **[PHASE-0-GATED]**.

**Given** вызывающий создаёт LB c `regionId = "no-such-region"` (валидный DNS-1123 slug, но geo не резолвит)

**When** `NetworkLoadBalancerService.Create`

**Then** отказ — **peer-validate existence-result** (не format): `regionId` — geo-owned human slug, **освобождён** от prefix/base32; невалидный **формат** slug → `INVALID_ARGUMENT "invalid region id '<X>'"`, но отсутствие → peer-existence
**And** конкретный код: **AS-IS `INVALID_ARGUMENT`**; **[PHASE-0-GATED conv-11]** target → `FAILED_PRECONDITION "region_id no-such-region not found"` (§MERGE-GATE)

### Сценарий NLB-1-12 (edge, fail-closed): geo недоступен на Create → `UNAVAILABLE`

**ID:** NLB-1-12

**Given** `geo.RegionService.Get` недоступен (peer down) в момент Create

**When** `NetworkLoadBalancerService.Create` c валидным `regionId`

**Then** мутация **fail-closed** → `UNAVAILABLE` (peer недоступен — мутация не проходит; `data-integrity.md` §cross-domain «fail-closed для мутаций»); LB **не** создаётся (нет phantom-row)

### Сценарий NLB-1-51: happy — `securityGroupIds` (firewall VIP) set@Create + LIVE-mutable@Update; region-coherence НЕ проверяется

**ID:** NLB-1-51

> `securityGroupIds` — реальное поле NetworkLoadBalancer (firewall самого VIP / frontend access control), LIVE-mutable скаляр-список, тривиальный same-project existence. AS-IS `security_group_ids` был reserved на LB — редизайн возвращает.

**Given** проект `prj-f9k2m4x7q1w8r3n5`; vpc SecurityGroup `sg-0k4m7t2y9u1i3o5p` существует **в том же проекте**

**When** `NetworkLoadBalancerService.Create` c `securityGroupIds = ["sg-0k4m7t2y9u1i3o5p"]`, затем `Update` c `updateMask="securityGroupIds"`, `securityGroupIds=["sg-0k4m7t2y9u1i3o5p","sg-1a2b3c4d5e6f7g8h"]` (оба same-project)

**Then** после `done` `Get` LB эхает `securityGroupIds`; каждый SG — **same-project existence-check** через vpc (peer-validate); **region-coherence НЕ проверяется** (SG network-scoped, region/zone-поля не несёт); поле LIVE-mutable

### Сценарий NLB-1-52 (negative): несуществующий / cross-project `securityGroupId` → peer-validate; vpc down → `UNAVAILABLE`

**ID:** NLB-1-52

**Given** SG `sg-00000000000000` не существует (или принадлежит **другому** проекту)

**When** `NetworkLoadBalancerService.Create`/`Update` c этим `securityGroupId`

**Then** отказ — **peer-validate existence-result** через vpc (foreign vpc-owned id, **не** nlb-prefix-checked, B4): absent/cross-project → by-lane код (**AS-IS**, target `FAILED_PRECONDITION` **[PHASE-0-GATED conv-11]**); vpc недоступен → `UNAVAILABLE` (fail-closed)
**And** malformed `securityGroupId` (`"garbage!!"`) — **не** nlb-format-reject; peer-validate вернёт not-found (foreign id, B4)

---

## F3 — adminState заменяет `:start`/`:stop`; crossZoneEnabled ZONAL-guard; status auto-recompute; sessionAffinity

> `→ родитель F3` · **AS-IS:** power-verbs `Start`/`Stop` RPCs + статусы `STARTING/STOPPING/STOPPED`;
> `disabled_announce_zones = 28` (REGIONAL drain) — снимается; `cross_zone_enabled` был reserved.
> Редизайн: `adminState: ENABLED|DISABLED` (LIVE-mutable) + `crossZoneEnabled` (REGIONAL-only) +
> `sessionAffinity` (present, `session_affinity = 11`). **status auto-recompute DB-триггер** переписан
> под глоссарий `ACTIVE/DEGRADED/INACTIVE/DISABLED` (родитель §Найденная цепочка — `0013` trigger rewrite).

### Сценарий NLB-1-13: `adminState=DISABLED` через Update → `status° == DISABLED` (конфиг цел)

**ID:** NLB-1-13

**Given** LB `nlb-1a2b3c4d5e6f7g8h` в `status=ACTIVE`, `adminState=ENABLED`, ≥1 wired listener

**When** `NetworkLoadBalancerService.Update` c `updateMask="adminState"`, `adminState="DISABLED"`

**Then** после `done` `Get` отдаёт `adminState == "DISABLED"`, `status° == "DISABLED"` («админ-выключен, конфиг сохранён» — не failure-состояние); listener'ы/wiring целы

### Сценарий NLB-1-14: Update никогда не авто-ENABLE'ит DISABLED-LB

**ID:** NLB-1-14

**Given** LB в `adminState=DISABLED`

**When** `NetworkLoadBalancerService.Update` c `updateMask="labels"` (меняет только labels, `adminState` **не** в маске)

**Then** `adminState` остаётся `"DISABLED"` (admin-state сохраняется); только явный `adminState:ENABLED` в маске возвращает LB в `ENABLED`

### Сценарий NLB-1-15: убраны `:start`/`:stop` — RPC отсутствует

**ID:** NLB-1-15

**Given** редизайн снял power-verbs

**When** клиент вызывает `POST /nlb/v1/networkLoadBalancers/{id}:start` (или `:stop`)

**Then** маршрут **отсутствует** (404 / not-registered на gateway) — enable/disable выражается **только** через `adminState` LIVE-mutable поле (`Update`); breaking-delta от AS-IS
**And** снятие `:start`/`:stop` из proto+service+gateway — **в этом PR** (per-RPC gateway-drop same-PR; аудит-coherence — NLB-1d)

### Сценарий NLB-1-16 (negative): `crossZoneEnabled != false` на ZONAL → `INVALID_ARGUMENT`

**ID:** NLB-1-16

**Given** LB c `placement="INTERNAL_ZONAL"` (ZONAL)

**When** `NetworkLoadBalancerService.Create`/`Update` c `crossZoneEnabled = true`

**Then** `INVALID_ARGUMENT "crossZoneEnabled is not applicable to ZONAL placement"` (не молчаливый inert); для REGIONAL `crossZoneEnabled` действует нормально
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

**When** referencing-TG становится нерезолвящейся (напр. `targetGroupId` обнулён — F4) → listener `substatus° == "MISCONFIGURED"`

**Then** `Get` LB отдаёт `status° == "DEGRADED"` («есть MISCONFIGURED-listener без резолвящейся TG» — silent-blackhole **не** маскируется под ACTIVE); `reason` уровня listener — `"listener <id> has no target group"`

### Сценарий NLB-1-53: `sessionAffinity` LIVE-mutable (FIVE_TUPLE ↔ CLIENT_IP_ONLY)

**ID:** NLB-1-53

> **AS-IS:** `session_affinity = 11` present; `SESSION_AFFINITY_UNSPECIFIED` персистится как `FIVE_TUPLE`-дефолт. Редизайн держит LIVE-mutable.

**Given** LB `nlb-1a2b3c4d5e6f7g8h` c `sessionAffinity="FIVE_TUPLE"` (или UNSPECIFIED → дефолт `FIVE_TUPLE`)

**When** `NetworkLoadBalancerService.Update` c `updateMask="sessionAffinity"`, `sessionAffinity="CLIENT_IP_ONLY"`

**Then** после `done` `Get` LB отдаёт `sessionAffinity == "CLIENT_IP_ONLY"` (LIVE-mutable); значения `FIVE_TUPLE`(«5-tuple hash»)|`CLIENT_IP_ONLY`(«sticky по src-IP»)

---

## F4 — Listener: единственный authoritative `targetGroupId`; attach/detach + M:N pivot сняты; substatus°/resolvedBackendPort° derived

> `→ родитель F4` · **AS-IS (упрощение):** роутинг — M:N `attached_target_groups`-pivot + RPCs
> `AttachTargetGroup`/`DetachTargetGroup`; listener «default»-семантика `default_target_group_id = 17`.
> Редизайн: **единственный authoritative** `targetGroupId` (FK RESTRICT), M:N-pivot + attach/detach
> **сняты** (удаление `attach_target_group.go` → разблокирует HealthCheck-redesign 1c); `substatus°`/
> `resolvedBackendPort°` derived. `resolvedBackendPort°` **эхает `TargetGroup.port`** → co-req поле в 1b.

### Сценарий NLB-1-19: happy — Listener.Create wiring существующей `targetGroupId` → substatus OK, resolvedBackendPort°

**ID:** NLB-1-19

**Given** LB `nlb-1a2b3c4d5e6f7g8h` и region-coherent TG `tgr-2w8r4t6y1u3i5o7p` c `port=8080` (co-req поле, F6-co-req) существуют в том же регионе

**When** `ListenerService.Create` (`POST /nlb/v1/listeners`) c payload:
  - `loadBalancerId = "nlb-1a2b3c4d5e6f7g8h"`
  - `name = "tcp-443"`, `protocol = "TCP"`, `port = 443`
  - `targetGroupId = "tgr-2w8r4t6y1u3i5o7p"`
  - адресных полей нет: VIP берётся с родительского LB (см. F5)

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

**Then** после `done` `Get` listener отдаёт `targetGroupId == "tgr-4h6j8l0n2p4r6s8u"`, `resolvedBackendPort° == 9090` (эхо новой TG); backend-порт сменился **сменой TG** (не per-listener override — F5)

### Сценарий NLB-1-23 (negative): Listener.Create c несуществующей `targetGroupId` → actionable error

**ID:** NLB-1-23

**Given** `targetGroupId = "tgr-00000000000000"` не существует (или не region-coherent с LB)

**When** `ListenerService.Create` c этим `targetGroupId`

**Then** `FAILED_PRECONDITION "listener requires an existing targetGroupId; create the TargetGroup first (POST /nlb/v1/targetGroups) or use one-shot NetworkLoadBalancer.Create"` (actionable; **не** «no target group to wire»)
**And** region-mismatch TG (TG в другом регионе, чем LB) → `FAILED_PRECONDITION` с region-coherence-текстом

### Сценарий NLB-1-24 (negative): immutable Listener-поля в Update

**ID:** NLB-1-24

**Given** listener `lst-7h3k9m2x4q8w1t0y` c `protocol="TCP"`, `port=443`, `loadBalancerId="nlb-…"`

**When** `ListenerService.Update` c `updateMask` содержащим любое из `protocol`/`port`/`loadBalancerId`

**Then** **reject ДО `UpdateMask`** → `INVALID_ARGUMENT "<field> is immutable after Listener.Create"`

### Сценарий NLB-1-25 (negative): AS-IS `targetPort`/per-listener backend-порт снят

**ID:** NLB-1-25

> **AS-IS:** `Listener.target_port = 11` («Port on which targets receive forwarded traffic») — per-listener backend-порт.

**Given** редизайн убрал per-listener backend-порт (один backend-порт = одно поле одного ресурса — `TargetGroup.port`)

**When** клиент пытается задать backend-порт на самом listener'е (AS-IS `targetPort`)

**Then** поле **отсутствует** в целевом Listener-контракте (backend-порт живёт **только** на `TargetGroup.port`); нужен другой backend-порт → ссылаться на **другую** (reusable, дешёвую) TargetGroup; наблюдаемость — `resolvedBackendPort°` (эхо, NLB-1-19)

### Сценарий NLB-1-26 (negative): Listener.Create c несуществующим/malformed `loadBalancerId`

**ID:** NLB-1-26

**When** `ListenerService.Create` c `loadBalancerId = "garbage!!"` → sync `INVALID_ARGUMENT "invalid network load balancer id 'garbage!!'"` первым стейтментом; c well-formed-но-нет `loadBalancerId = "nlb-00000000000000"` → within-service FK не резолвит → `FAILED_PRECONDITION "NetworkLoadBalancer nlb-00000000000000 not found"` (owner в той же БД, RESTRICT-FK)

**Then** malformed — sync format-first-statement; absent-owner — within-service by-lane

### Сценарий NLB-1-54: `proxyProtocolV2` LIVE-mutable на Listener

**ID:** NLB-1-54

> **AS-IS:** `proxy_protocol_v2 = 16` present. Редизайн держит LIVE-mutable.

**Given** listener `lst-7h3k9m2x4q8w1t0y` c `proxyProtocolV2=false`

**When** `ListenerService.Update` c `updateMask="proxyProtocolV2"`, `proxyProtocolV2=true`

**Then** после `done` `Get` listener отдаёт `proxyProtocolV2 == true` (LIVE-mutable); mutable-класс listener'а — `name`/`description`/`labels`/`targetGroupId`/`proxyProtocolV2`

---

## F5 — VIP на LoadBalancer: per-family источник (immutable input) + `v4AddressId°`/`v6AddressId°` + VIP-uniqueness (concurrent-race) + placement/zone-coherence + recycle

> `→ родитель F5` · `→ module-nlb §VIP — свойство LoadBalancer'а` · `→ data-integrity.md §placement-coherence, §Lease-recycle-on-delete B17`
>
> **Якорь VIP — NetworkLoadBalancer, не Listener.** LB несёт максимум один `vpc.Address` на семейство
> (`address_v4`/`address_v6` + `address_id_v4`/`address_id_v6` + `vip_origin_v4`/`vip_origin_v6`), источник
> задаётся per-family на Create (`v4Source`/`v6Source`: `subnetId` | `addressId` | `public{}`), наружу идёт
> только id связанного Address (`v4AddressId°`/`v6AddressId°`). Listener адресных полей не несёт (в proto
> `region_id`/`ip_version`/`address_id`/`allocated_address`/`subnet_id` — `reserved`) и ничего не аллоцирует.
>
> **Uniqueness — на LB:** partial-UNIQUE `(region_id, address_v4) WHERE address_v4 <> ''` (+ v6-близнец,
> оба `CONCURRENTLY` с self-heal/assert валидности) и CAS-attach `WHERE id=$1 AND (address_v4='' OR
> address_v4=$2)` для single-VIP-per-LB. Listener гарантирует `UNIQUE (load_balancer_id, port, protocol)` —
> при одном VIP на семейство это и есть «одна привязка `(VIP, port, protocol)`».
>
> Listener-level partial-UNIQUE `(region_id, allocated_address, port, protocol)` **не существует**: он
> энфорсил бы колонку, которую ни один прод-путь не пишет. Новая миграция снимает его (ban #5 — прежние
> миграции не редактируются).

### Сценарий NLB-1-27: happy — link существующего Address (`v4Source.addressId`) → `v4AddressId°`

**ID:** NLB-1-27

**Given** свободный vpc `addressId = "adrt8y2u4i6o8p0aq1"` (same project, kind соответствует `placement`) существует

**When** `NetworkLoadBalancerService.Create` c `placement="EXTERNAL_REGIONAL"`, `v4Source={addressId:"adrt8y2u4i6o8p0aq1"}`

**Then** после `done` `Get` LB отдаёт `v4AddressId° == "adrt8y2u4i6o8p0aq1"`; **сама IP-строка на публичной поверхности nlb не эхается** — тенант читает её у владельца (`vpc.AddressService.Get`), зеркала нет
**And** привязка — `SetReference` atomic-CAS с owner'ом вида `nlb_load_balancer:<lb-id>`; `vipOrigin=linked` (internal-дискриминатор, наружу не идёт) → на Delete адрес **не** удаляется
**And** `v4Source` — input-only immutable: в ответе не эхается, в `Update` не принимается

### Сценарий NLB-1-28: happy — auto-аллокация из подсети (`v4Source.subnetId`, INTERNAL)

**ID:** NLB-1-28

**Given** `placement="INTERNAL_ZONAL"`; подсеть `sub3e5r7t9y1u3i5o7` (`placementType=ZONAL`, зона `eu-north-a`, region-coherent) существует, есть свободные адреса

**When** `NetworkLoadBalancerService.Create` c `v4Source={subnetId:"sub3e5r7t9y1u3i5o7"}`

**Then** после `done` VIP аллоцирован (`vpc.InternalAddressService.AllocateInternalIP`), `v4AddressId°` непуст; `vipOrigin=auto` → на Delete адрес возвращается в пул
**And** `public{}`-источник на INTERNAL отвергается sync: `INVALID_ARGUMENT "public address source is only valid for EXTERNAL load balancer"`; `subnetId`-источник на EXTERNAL — `INVALID_ARGUMENT "subnet address source is only valid for INTERNAL load balancer"`
**And** ни одно семейство не задано → `INVALID_ARGUMENT "load balancer must declare a vip source for at least one ip family"`

### Сценарий NLB-1-29 (negative): источник VIP не мутируется после Create

**ID:** NLB-1-29

**Given** LB создан c `v4Source={addressId:"adrt8y2u4i6o8p0aq1"}`

**When** `NetworkLoadBalancerService.Update` пытается сменить источник VIP или перепривязать адрес

**Then** источник VIP в `Update`-запросе **отсутствует как поле** — сменить VIP у живого LB нельзя by construction; `v4AddressId°`/`v6AddressId°` — output-only (запись отвергается)
**And** смежный derived-reject того же класса: `type`/`placementType` на **Create** → `INVALID_ARGUMENT "<field> is derived output-only; the load balancer mode is set solely by placement"` (режим задаётся только `placement`)

### Сценарий NLB-1-30 (negative): VIP-conflict — тот же адрес в том же регионе → generic `FAILED_PRECONDITION`

**ID:** NLB-1-30

**Given** LB A уже держит адрес `203.0.113.40` (v4) в регионе `eu-north`

**When** создаётся LB B, привязывающий **тот же** адрес в том же регионе

**Then** partial-UNIQUE `(region_id, address_v4) WHERE address_v4 <> ''` даёт 23505 → **`FAILED_PRECONDITION "could not assign address to load balancer"`** — намеренно **generic**: ответ не раскрывает, кто держит адрес (анти-oracle), и это **не** `ALREADY_EXISTS`
**And** тот же адрес в **другом** регионе конфликта не даёт (ключ индекса — `region_id`)
**And** повторный attach **того же** адреса тому же LB — no-op (CAS `address_v4=$2` матчит) → retry идемпотентен; попытка привязать **второй** адрес того же семейства → `FAILED_PRECONDITION "load balancer already has an address for this family"`

### Сценарий NLB-1-31 (concurrent-race): два конкурентных claim одного адреса → ровно один проходит

**ID:** NLB-1-31

**Given** (integration, testcontainers, concurrent goroutines) две горутины одновременно делают CAS-attach **одного** адреса к **разным** LB одного региона; каждая в собственной writer-TX, открытой ДО старт-барьера

**When** барьер снимается и обе бьют в индекс

**Then** **ровно одна** транзакция коммитит, вторая получает `FAILED_PRECONDITION "could not assign address to load balancer"` — не second-writer-wins, не обе; под `-race`, детерминированно (барьер + tuple-lock индекса, не `time.Sleep`)
**And** парный race на **одной** LB-строке (два разных адреса одного семейства) → ровно один победитель по CAS, итоговый `address_v4` — адрес победителя (single-VIP-per-LB не нарушен)

### Сценарий NLB-1-32 (negative): placement VIP-источника не совпадает с placement LB

**ID:** NLB-1-32

**Given** `placement="INTERNAL_ZONAL"` (ZONAL); `v4Source.subnetId` указывает на **REGIONAL** подсеть

**When** `NetworkLoadBalancerService.Create` c этим источником

**Then** sync-reject ДО `Operation`: `INVALID_ARGUMENT "subnet placement does not match load balancer placement"` (`data-integrity.md` §placement-coherence); строка LB не создаётся, VIP не аллоцируется
**And** подсеть из **другого региона** → `INVALID_ARGUMENT "load balancer vip subnet must be in the same region as the load balancer"`
**And** тот же mismatch, пришедший через `addressId`-линк (placement/регион подсети линкуемого адреса), сворачивается в анти-oracle `INVALID_ARGUMENT "Illegal argument addressId"` — свойства чужого адреса не подтверждаются
**And** existence подсети/адреса валидируется peer-vpc, `placementType` — self-describing поле подсети; vpc недоступен → `UNAVAILABLE` (fail-closed)

### Сценарий NLB-1-33 (edge): ZONAL dualstack — обе семьи VIP в ОДНОЙ зоне и ОДНОЙ сети

**ID:** NLB-1-33

**Given** `placement="INTERNAL_ZONAL"`; `v4Source.subnetId` — подсеть зоны `eu-north-a`

**When** `v6Source.subnetId` указывает на подсеть **другой** зоны (`eu-north-b`)

**Then** sync-reject: `INVALID_ARGUMENT "dualstack load balancer families must resolve to the same zone"`
**And** семьи из разных **сетей** (при совпадающей зоне) → `INVALID_ARGUMENT "dualstack load balancer families must resolve to the same network"` — проверка сети применяется к INTERNAL при любом placement
**And** REGIONAL/anycast из зональной проверки исключён **by construction** (его подсети `zone_id` не несут — сравнивать не с чем); одиночное семейство — сравнивать не с чем
**And** отдельного `zoneId`-поля у LB нет: зона ZONAL-LB задана зоной VIP-источника и фиксируется на Create, поэтому order-dependence «какой listener пришёл первым» отсутствует by construction

### Сценарий NLB-1-55: VIP recycle-on-delete — освобождение по `vipOrigin` (`LoadBalancer.Delete`)

**ID:** NLB-1-55

> `→ data-integrity.md §Lease-recycle-on-delete B17`: VIP — vpc.Address из ограниченного пула; если Delete его не возвращает, orphan-lease исчерпывает пул под parallel-e2e.
>
> Освобождение висит на **`LoadBalancer.Delete`**, а не на `Listener.Delete`: адрес принадлежит LB и переживает любой из своих listener'ов. `Listener.Delete` VIP не трогает — освобождать нечего.

**Given** LB c auto-аллоцированным VIP (`vipOrigin=auto`); отдельно — LB c линкованным адресом (`vipOrigin=linked`); listener'ы уже удалены (Delete LB при живых listener'ах отвергается `FAILED_PRECONDITION`)

**When** `NetworkLoadBalancerService.Delete`

**Then** после `done` VIP каждого семейства освобождён по своему дискриминатору: `auto` → `ClearReference` **затем** `FreeIP` (адрес возвращён в пул; two-step обязателен — `FreeIP` упёрся бы в собственный Delete-guard на owned-референсе), `linked` → только `ClearReference` (адрес **остаётся** у тенанта)
**And** тот же release-контракт отрабатывает на **компенсации Create-саги**: падение после acquire, но до финализации освобождает уже добытые VIP в обратном порядке и снимает `CREATING`-handle
**And** краш worker'а между acquire и persist подбирает фоновый reconciler, сканирующий LB в `CREATING`/`DELETING` дольше порога, — по тем же `address_id_*`/`vip_origin_*`, идемпотентно
**And** e2e лочит pool-контракт: N alloc → N delete → N alloc снова проходит (пул не деградировал)

---

## F6-co-req — TargetGroup.port (net-new bare-field + required-BVA)

> `→ родитель F6 (NLB-1-35)` · **Co-requisite Listener-wiring:** `resolvedBackendPort°` (F4/NLB-1-19)
> эхает `TargetGroup.port`, поэтому **bare-поле `port` + required-BVA** приземляются в 1b (иначе
> `resolvedBackendPort°` нечего эхать). **AS-IS: у TG НЕТ поля `port`** (backend-порт был per-listener
> `target_port`) → `port` net-new. Полная port-семантика (**LIVE-mutable re-echo** NLB-1-56, `effectivePort°`
> inheritance NLB-1-39) и HealthCheck-redesign — **1c** (§Out-of-scope). В 1b TG несёт AS-IS HealthCheck.

### Сценарий NLB-1-35 (negative): `TargetGroup.port` вне `1..65535` → `INVALID_ARGUMENT`; отсутствие → required

**ID:** NLB-1-35

**When** `TargetGroupService.Create` c `port = 0` (или `> 65535`)

**Then** `INVALID_ARGUMENT` (backend-порт `1..65535`); отсутствие `port` — required-поле пула (net-new relative to AS-IS)
**And** `port` присутствует и валиден → TG создаётся; `Get` эхает `port` (единственный backend-порт пула); это поле, которое `Listener.resolvedBackendPort°` эхает (NLB-1-19). Полная LIVE-mutable re-echo семантика — NLB-1-56 (1c)

---

## F7 — one-shot Create (existing TG) + teardown RESTRICT + op-poll + deletionProtection + pagination-before-listauthz + name-UNIQUE race

> `→ родитель F7` · **AS-IS:** мутации уже возвращают `Operation` (async); `List` exempt от per-RPC
> Check, фильтруется listauthz; `deletion_protection = 14` present. One-shot c inline **redesigned**
> `targetGroup` (NLB-1-57/58) — 1c (нужна 1c HealthCheck-форма); 1b покрывает one-shot с **existing**
> `targetGroupId`.

### Сценарий NLB-1-43: happy — one-shot `NetworkLoadBalancer.Create` c `listenerSpecs[]` (existing TG)

**ID:** NLB-1-43

**Given** TG `tgr-2w8r4t6y1u3i5o7p` (`port=8080`) существует; проект+регион ok; вызывающий — editor проекта

**When** `NetworkLoadBalancerService.Create` c payload:
  - `projectId`, `regionId="eu-north"`, `placement="EXTERNAL_REGIONAL"`, `name="edge"`
  - `v4Source = { public: {} }` (источник VIP LB — обязателен хотя бы для одного семейства)
  - `listenerSpecs = [ { name:"tcp-443", port:443, protocol:"TCP", targetGroupId:"tgr-2w8r4t6y1u3i5o7p" } ]`

**Then** `Operation`; `metadata.networkLoadBalancerId` доступен **сразу** (до `done`); сервер разворачивает LB + listener + VIP-сагу **в одной Operation** в dependency-порядке; после `done=true` (`!error`) `Get` LB отдаёт `status=ACTIVE`, listener wired (`substatus=OK`)
**And** listenerSpec ссылается на **existing** `targetGroupId`; inline `targetGroup{port, healthCheck}` (redesigned-shape) — NLB-1-57/58 (1c); FK-топология скрыта от клиента

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

**Then** `FAILED_PRECONDITION "network load balancer has listeners: [lst-7h3k9m2x4q8w1t0y, lst-5k7m9q1w3e5r7t9y]"` (RESTRICT, precheck перечисляет блокеры — часть контракта, строчными)

### Сценарий NLB-1-46: `Delete{cascade:true}` — within-service каскад listener'ов в одной Operation

**ID:** NLB-1-46

**Given** LB c listener'ами; референсимые TG — cross-service reusable (не within-service child)

**When** `NetworkLoadBalancerService.Delete` c body `{cascade:true}`

**Then** детерминированный **within-service** каскад: listener'ы удаляются (+ VIP освобождается — NLB-1-55) в **одной** Operation (ban #4 — нет cross-service cascade); TG — **detach** (обнуление ссылки), **не** delete (TG — cross-LB reusable, чужой lifecycle)

### Сценарий NLB-1-47 (negative): `deletionProtection=true` блокирует Delete

**ID:** NLB-1-47

**Given** LB c `deletionProtection=true`, без listener'ов

**When** `NetworkLoadBalancerService.Delete`

**Then** `FAILED_PRECONDITION` (sync-precheck deletion-protection); `deletionProtection` — LIVE-mutable (сначала `Update` в `false`, затем Delete)

### Сценарий NLB-1-48 (negative): garbage `pageToken` в List → `INVALID_ARGUMENT` ДО listauthz short-circuit

**ID:** NLB-1-48

**Given** вызывающий без грантов (empty listauthz-grant) вызывает `NetworkLoadBalancerService.List` c `pageToken="!!garbage!!"` (или `pageSize=5000`)

**When** `List` (`GET /nlb/v1/networkLoadBalancers?projectId=…&pageToken=!!garbage!!`)

**Then** `INVALID_ARGUMENT` (pagination-validate **ДО** listauthz empty-grant short-circuit — иначе garbage-token / `pageSize>1000` при пустом гранте утекут в `200 {[]}`; `api-conventions.md` §Gotcha, `security.md` §Hardening инв-7); `pageSize` вне `[0..1000]` — **отвергается, не clamp'ится**
**And** валиден для `List` NetworkLoadBalancer и Listener (TG.List — тот же контракт, verify в 1c)

### Сценарий NLB-1-49 (negative): duplicate `name` в проекте → `ALREADY_EXISTS`

**ID:** NLB-1-49

**Given** LB c `name="edge"` уже существует в `prj-f9k2m4x7q1w8r3n5`

**When** `NetworkLoadBalancerService.Create` со вторым `name="edge"` в том же проекте

**Then** `ALREADY_EXISTS` (UNIQUE(project,name) partial — пустое `name` допустимо); аналогично Listener UNIQUE(loadBalancer,name); TG UNIQUE(project,name) — verify в 1c

### Сценарий NLB-1-50 (concurrent-race): две конкурентные Create одинакового `name` → ровно одна проходит

**ID:** NLB-1-50

**Given** (integration, testcontainers, concurrent goroutines) две горутины одновременно вызывают `NetworkLoadBalancer.Create` c одинаковыми `projectId`+`name="edge"`

**When** обе коммитят в один момент

**Then** **ровно одна** проходит, вторая → `ALREADY_EXISTS` (partial-UNIQUE(project,name) держит; не оба, не second-writer-wins); под `-race` детерминированно (blocker держит слот, не `time.Sleep`)

---

## Definition of Done (NLB-1b)

Production-complete в границах LB+Listener core + TG.port co-req (`ai-tooling.md` §lifecycle, `testing.md`, `security.md`):

**Traceability + тесты (1-to-1, TDD ban #12):**
- [ ] Каждый carve-сценарий (NLB-1-01..33, 35, 43..55) имеет зелёный **integration-тест** (testcontainers Postgres 16), `Test<Resource>_NLB_1_NN`, покрывающий SQL-сторону incl. CAS/UNIQUE/EXCLUDE. **Обязательные concurrent-race под `-race`, детерминированно: NLB-1-31** (per-region VIP partial-UNIQUE `(region_id, address_v4/_v6)` double-claim + CAS single-VIP-per-LB race) **и NLB-1-50** (name UNIQUE(project,name) race).
- [ ] Каждый (наблюдаемый через api-gateway) — зелёный **newman-кейс** `# verifies NLB-1-NN` (≥1 happy + ≥1 negative per фича); `{{runId}}`-суффикс; op-poll `!op.error` перед извлечением id из `metadata`.
- [ ] RED (падает по нужной причине) ДО кода; пара RED→GREEN в PR.
- [ ] read-your-writes: первый Get/Update/Delete своего свежего LB/Listener обёрнут `retry_until_authorized` (owner-tuple EC-окно, conv-3); негативы **НЕ** оборачивать.

**Deliverables редизайна (иначе AS-IS-путь остаётся):**
- [ ] **NetworkLoadBalancer:** слить `type`(required)+`placement_type` → **один immutable input** `placement`; `type°`/`placementType°` → derived output-only (write → explicit reject); снять `Start`/`Stop` RPCs + `STARTING/STOPPING/STOPPED`-статусы → `adminState: ENABLED|DISABLED` + `status` DISABLED-глосса; снять `disabled_announce_zones` → `crossZoneEnabled` (REGIONAL-only, ZONAL-guard); **вернуть** `securityGroupIds` (same-project existence, LIVE-mutable); managed `address.hostname°`; `status` auto-recompute DB-триггер (ACTIVE/DEGRADED/INACTIVE/DISABLED — переписать `0013`-trigger новой миграцией).
- [ ] **Listener:** снять M:N `attached_target_groups`-pivot + `AttachTargetGroup`/`DetachTargetGroup` RPCs (**удалить `attach_target_group.go`** → разблокирует HealthCheck-redesign 1c); `default_target_group_id` → **единственный authoritative** `targetGroupId` (FK RESTRICT); `substatus°`/`resolvedBackendPort°` (derived); адресные поля listener'а (`ip_version`/`address_id`/`allocated_address`/`subnet_id`/`region_id`) остаются `reserved` в proto — **VIP на Listener не возвращается**; Create — чистый INSERT без vpc-вызовов, Delete VIP не освобождает.
- [ ] **TargetGroup.port (co-req):** net-new bare-поле `port` (required, BVA `1..65535`) — новая миграция ALTER target_group ADD port. **AS-IS HealthCheck (`name`+`tcp`/`http`) сохраняется** (redesign — 1c). Set-at-create; LIVE-mutable re-echo — 1c.
- [ ] **Не** редактировать применённые миграции — только новые: `securityGroupIds`/`crossZoneEnabled` CHECK-редизайн (type-agnostic securityGroupIds, crossZoneEnabled ZONAL-guard), status-trigger rewrite, TG.port ADD, **снятие мёртвого listener-level `listeners_region_vip_uniq`** (индекс на колонке, которую ни один прод-путь не пишет; VIP-uniqueness живёт на `load_balancers_region_v4_uniq`/`_v6_uniq`).
- [ ] **VIP-uniqueness проверяется на LoadBalancer.** Ни один listener-level индекс/CHECK не претендует на VIP-инвариант; `listeners.allocated_address`/`address_id` прод-кодом не пишутся (`SetAllocatedAddress`/`SetVIP` — без прод-вызывающих).

**Проектные гейты:**
- [ ] `go test ./... -race` · `golangci-lint run` · `govulncheck` · `make -C services/nlb audit-list-filter` зелёные.
- [ ] proto — `buf lint`/`buf breaking` (breaking задекларированы: placement-слияние, start/stop-drop, attach/detach-drop, VIP-консолидация на LB — снятие listener-адресных полей в `reserved`) зелёные после регена. proto ревьюит `proto-api-reviewer`; миграции — `db-architect-reviewer`; VIP-сага + status-recompute CAS — `system-design-reviewer`.
- [ ] `make -C gateway permission-catalog-check` byte-identical (снятые `start`/`stop`/`attachTargetGroup`/`detachTargetGroup` — удалены из каталога; новые LB/Listener RPC — записи есть, ключёваны на `nlb_*` из 1a).
- [ ] authz на КАЖДОМ RPC обоих листенеров (`nlb_*`-типы из 1a): read → viewer-floor, мутации → editor на target, Create → editor на project; `scope_extractor` резолвит target→project; `List` фильтруется listauthz. Per-RPC gateway-регистрация каждого нового public LB/Listener RPC — **в этом PR** (`api-gateway-registrar`).

**MERGE-GATE (`[PHASE-0-GATED]` — жёсткий блокер):**
- [ ] **NLB-1b НЕ мёржится, пока Phase-0 governance change-set не приземлит** (00-unified §7 Фаза-0):
  - **B1** — 3-way ref-naming (`ResourceRef`/`Referrer`/`OciReferrer`) в `kacho.cloud.common.v1`. *NB:* `Listener.address` (managed VIP) — **generic `Referrer{type,id,name°,ip°,hostname°}`** (graceful-dangling на vpc.Address) → nlb-proto нельзя писать до landing shared `common.v1` → **build-order gate**.
  - **B3** — id-prefix hyphen-форма (`nlb-`/`lst-`/`tgr-`) в `corevalidate`. F1-сценарии формулируют target-форму; реализация до merge на 3-char, hyphen-переход одним шагом.
  - **conv-11 by-lane split + reason-tokens** — касается **только** peer-validate scope-coord absent (NLB-1-05 projectId, NLB-1-11 regionId): AS-IS heterogeneous → target `FAILED_PRECONDITION` + reason-token. До merge NLB-1-05/11 — AS-IS коды. **НЕ** касается within-service `loadBalancerId`/`targetGroupId` (NLB-1-26/23 — ungated).

Ungated части (own-only prefix-check/wrong-type/malformed; well-formed-absent NOT_FOUND; placement-слияние + derived type°/placementType°; adminState/status-recompute; single authoritative targetGroupId; VIP-anchor + uniqueness race + recycle; TG.port co-req; teardown RESTRICT blocker-list; op-poll; name-UNIQUE race; fail-closed `UNAVAILABLE`) строятся **без** ожидания change-set.

---

## Traceability-таблица (родитель → NLB-1b)

| Родительский | Фича | Тип |
|---|---|---|
| NLB-1-01 | F1 happy Get 3 типа | happy |
| NLB-1-02 | F1 malformed → INVALID_ARGUMENT | negative |
| NLB-1-03 | F1 wrong-type → INVALID_ARGUMENT | edge |
| NLB-1-04 | F1 absent → NOT_FOUND | negative |
| NLB-1-05 | F1 foreign-id peer-validate B4 | edge |
| NLB-1-06 | F2 EXTERNAL_REGIONAL derived | happy |
| NLB-1-07 | F2 INTERNAL_ZONAL derived | happy |
| NLB-1-08 | F2 write type/placementType reject | negative |
| NLB-1-09 | F2 external+zonal невыразим | edge |
| NLB-1-10 | F2 placement/regionId immutable | negative |
| NLB-1-11 | F2 regionId peer-geo | negative |
| NLB-1-12 | F2 geo down → UNAVAILABLE | edge |
| NLB-1-51 | F2 securityGroupIds happy | happy |
| NLB-1-52 | F2 securityGroupIds peer/down | negative |
| NLB-1-13 | F3 adminState=DISABLED | happy |
| NLB-1-14 | F3 never-auto-ENABLE | happy |
| NLB-1-15 | F3 :start/:stop сняты | negative |
| NLB-1-16 | F3 crossZone ZONAL-guard | negative |
| NLB-1-17 | F3 status INACTIVE→ACTIVE | happy |
| NLB-1-18 | F3 status DEGRADED | happy |
| NLB-1-53 | F3 sessionAffinity | happy |
| NLB-1-19 | F4 wiring substatus/resolvedBackendPort° | happy |
| NLB-1-20 | F4 MISCONFIGURED | edge |
| NLB-1-21 | F4 attach/detach сняты | negative |
| NLB-1-22 | F4 repoint targetGroupId | happy |
| NLB-1-23 | F4 нет TG → actionable | negative |
| NLB-1-24 | F4 immutables | negative |
| NLB-1-25 | F4 target_port снят | negative |
| NLB-1-26 | F4 loadBalancerId malformed/absent | negative |
| NLB-1-54 | F4 proxyProtocolV2 | happy |
| NLB-1-27 | F5 link Address (`v4Source.addressId`) → `v4AddressId°` | happy |
| NLB-1-28 | F5 auto-аллокация VIP из подсети (LB) | happy |
| NLB-1-29 | F5 источник VIP не мутируется после Create | negative |
| NLB-1-30 | F5 VIP-conflict → generic FAILED_PRECONDITION | negative |
| NLB-1-31 | F5 VIP-race на LB (concurrent) | concurrent-race |
| NLB-1-32 | F5 placement/region mismatch источника VIP | negative |
| NLB-1-33 | F5 dualstack same-zone/same-network | edge |
| NLB-1-55 | F5 VIP recycle на LoadBalancer.Delete | happy |
| NLB-1-35 | F6-co-req TG.port BVA | negative |
| NLB-1-43 | F7 one-shot existing TG | happy |
| NLB-1-44 | F7 op-poll async | happy |
| NLB-1-45 | F7 Delete LB blocker-list | negative |
| NLB-1-46 | F7 Delete cascade:true | happy |
| NLB-1-47 | F7 deletionProtection | negative |
| NLB-1-48 | F7 pagination-before-listauthz | negative |
| NLB-1-49 | F7 name UNIQUE | negative |
| NLB-1-50 | F7 name-race (concurrent) | concurrent-race |

**Итого NLB-1b: 47 сценариев** (родительские NLB-1-01..33, 35, 43..55). Полная сводная матрица carve
(58/58, без пересечений/пропусков) — в `sub-phase-NLB-1a-fga-relation-rename-acceptance.md` §Сводная матрица.
