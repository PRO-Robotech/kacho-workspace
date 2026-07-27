# Sub-phase NLB-1a (FGA relation rename `lb_*` → `nlb_*`) — Acceptance

> Статус: **✅ APPROVED** (acceptance-reviewer carve-review, 2026-07-20 — партиция 58/58 verified)
> Дата: 2026-07-20
> Ревьюер: acceptance-reviewer — ✅ APPROVED (carve-partition 58/58; non-blocking notes в review-comment)
> Эпик/тикет: KAC-NLB-1 · под-фаза **1a of 4** (carve родительского APPROVED `sub-phase-NLB-1-lb-listener-targetgroup-acceptance.md`)
> Монорепо: `project/kacho` (`github.com/PRO-Robotech/kacho`) — легаси `project/kacho-*` не затрагивается.
> Порядок carve: **NLB-1a (это) → NLB-1b → NLB-1c → NLB-1d** (строгий dependency-порядок).

## Обзор

NLB-1a — **foundation-под-фаза** редизайна `kacho-nlb`: механический консистентный
rename FGA object-type'ов `lb_network_load_balancer` / `lb_listener` / `lb_target_group`
→ **`nlb_network_load_balancer` / `nlb_listener` / `nlb_target_group`** (родитель §DoD
deliverables «FGA object-type (дефолт Q1 — hard-rename в NLB-1)» + §Дефолты Q1). Это
**tenant-facing authz-scope** (object-type виден в AccessBinding target), поэтому rename
приземляется в NLB-1 (а НЕ в NLB-4 cutover, куда вынесен non-tenant-facing дрейф
permission-string/proto-package — родитель §Out-of-scope NLB-4 / Дефолт Q2).

**Почему первой и почему зелёная сама по себе:** rename — **shape-agnostic** механическая
замена ~265 sites (nlb `authzmap` + `services/iam/internal/authzmap` + gateway `internal/check`
+ permission-catalog генератор + iam-seed) — **только строка relation/object-type**, без
изменения формы ресурсов, RPC-surface или миграций данных. nlb — greenfield в `project/kacho`
(не GA) → миграционной массы FGA-tuple'ов нет → hard-rename без Rosetta-synonym (родитель
Дефолт Q1: synonym-мост оправдан только для GA-типа с накопленными tuple'ами). Rename
**предшествует** core-редизайну (1b): 1b перекраивает форму ресурсов уже поверх `nlb_*`-типов.

Это **owner-side authz** под-фаза: сценарии описывают наблюдаемое поведение авторизации
через api-gateway (:9090 → edge REST) и permission-catalog-инварианты. Форма трёх ядровых
ресурсов **не меняется** — она остаётся AS-IS до 1b (§Out-of-scope).

---

## Scope

| # | Что 1a покрывает | Traceability |
|---|---|---|
| A1 | Rename object-type `lb_*`→`nlb_*` во всех ~265 sites; authz-Check на каждом RPC обоих листенеров резолвит по новому типу (mutate → editor, read → viewer-floor) | родитель §DoD «FGA object-type Q1», `security.md` §AuthN+AuthZ ВЕЗДЕ п.2 |
| A2 | `scope_extractor` резолвит `nlb_*`-target → project (анти-BOLA): `{nlb_network_load_balancer, network_load_balancer_id}` / `{nlb_listener, listener_id}` / `{nlb_target_group, target_group_id}` → project | `security.md` §Hardening инв-3 (object-scoped authz) |
| A3 | `permission-catalog` regen byte-identical: обе embedded-копии (iam-seed + gateway middleware) синхронны; `make -C gateway permission-catalog-check` зелёный; каждый nlb-RPC имеет запись в каталоге | `security.md` §Hardening инв-4 (каталог полон/в синхроне) |
| A4 | `List<Resource>` фильтруется listauthz под `nlb_*`-типом (`make audit-list-filter`) | `security.md` §AuthN/AuthZ, `api-conventions.md` §Pagination |
| A5 | Rename **завершён**: старый `lb_*` object-type больше не резолвит доступ (нет dangling old-type пути); regression-lock ключуется на токен `nlb_*` | родитель §Дефолт Q1, `testing.md` §Regression-lock security-фиксов |

## Out-of-scope (следующая под-фаза — NLB-1b)

- **Форма трёх ядровых ресурсов** (placement-merge, adminState, VIP-контракт на LoadBalancer, единый
  `targetGroupId`, снятие M:N-pivot + `Attach`/`Detach` + `Start`/`Stop`, status-recompute,
  `securityGroupIds`, `resolvedBackendPort°`/`substatus°`, `TargetGroup.port`) — **NLB-1b**.
  1a оставляет форму ресурсов AS-IS; меняется **только** FGA object-type строка.
- **TargetGroup HealthCheck oneof-replace / durations / immutables** — **NLB-1c**.
- **Gateway-регистрация нового RPC-surface, newman shared-harness, cross-cutting verification,
  two-projection field-absence** — **NLB-1d**.
- **permission-string namespace `loadbalancer.*`→`nlb.*` + proto-package `loadbalancer.v1`→`nlb.v1`**
  — **NLB-4 cutover** (не tenant-facing; родитель §Out-of-scope NLB-4 / Дефолт Q2). 1a трогает
  **только** object-type (tenant-facing authz-scope) — это независимая от permission-string аннотация.
- **FGA owner-tuple материализация** (`fga_register_outbox` drainer/reconciler) — EC; 1a не гейтит
  `Operation.done` на её видимость (ban #9, conv-3); read-your-writes окно — bounded client-retry (NLB-1d).

## Traceability-легенда

Родительские сценарии `NLB-1-01..58` описывают **форму редизайненных** ресурсов и приземляются
в **1b/1c** (см. §Сводная матрица ниже). FGA-rename родитель выразил как **DoD-deliverable Q1**
(не как нумерованный `NLB-1-NN`), поэтому 1a **не наследует ни одного из 58** и вводит
**net-new** нумерованные сценарии `NLB-1a-01..05`, покрывающие rename-инвариант. Это не пропуск
покрытия: authz-**enforcement** по каждому ресурсу далее энфорсится в 1b/1c/1d на `nlb_*`-типах,
заложенных здесь. REST — `/nlb/v1/…` (:9090). `°` = output-only.

---

## A — FGA object-type rename `lb_*` → `nlb_*`

> `→ родитель §DoD deliverables (FGA), §Дефолты Q1` · `→ security.md §AuthN+AuthZ ВЕЗДЕ, §Hardening инв-3/4`
> **AS-IS:** FGA object-type `lb_network_load_balancer` / `lb_listener` / `lb_target_group`
> (iam FGA-модель + gateway scope_extractor + permission-catalog). REST-пути / ids уже `nlb`
> (`/nlb/v1/…`, `nlb-`/`lst-`/`tgr-`), permission-namespace ещё `loadbalancer.*` (→ NLB-4).
> Rename — **hard**, greenfield, без synonym-Rosetta (nlb не GA — нет накопленной tuple-массы).

### Сценарий NLB-1a-01: happy — editor проекта мутирует LB; scope_extractor резолвит `nlb_*`-target → project

**ID:** NLB-1a-01

**Given** проект `prj-f9k2m4x7q1w8r3n5` существует; вызывающий имеет binding **editor** на этом проекте; LB `nlb-1a2b3c4d5e6f7g8h` принадлежит проекту

**When** клиент вызывает мутацию `NetworkLoadBalancerService.Update` (`PATCH /nlb/v1/networkLoadBalancers/nlb-1a2b3c4d5e6f7g8h`)

**Then** api-gateway per-RPC authz-Check резолвит target по object-type **`nlb_network_load_balancer`** (не `lb_*`); `scope_extractor{nlb_network_load_balancer, network_load_balancer_id}` резолвит target→**project**; editor-грант проходит → мутация принимается
**And** аналогично `nlb_listener` (`{nlb_listener, listener_id}`) и `nlb_target_group` (`{nlb_target_group, target_group_id}`) резолвят target→project; каждая мутация трёх ресурсов гейтится editor-tier на резолвнутом проекте (анти-BOLA — `security.md` §Hardening инв-3)

### Сценарий NLB-1a-02: happy — permission-catalog regen byte-identical (две embedded-копии в синхроне)

**ID:** NLB-1a-02

**Given** rename применён во всех sites; permission-catalog сгенерирован из proto (`make -C gateway permission-catalog`)

**When** CI-гейт `make -C gateway permission-catalog-check` сравнивает две embedded-копии каталога (iam-seed + api-gateway middleware)

**Then** обе копии **byte-identical**; каждый выставленный nlb-RPC (обоих листенеров) имеет запись в каталоге, ключёванную на `nlb_*`-object-type; отсутствие записи → рантайм `catalog: no entry for method` = AUTHZ_DENIED (fail-closed) — недопустимо (`security.md` §Hardening инв-4)
**And** снятие несуществующих (после core-редизайна) методов из каталога — задача 1b/1c; 1a **только** переименовывает object-type в существующих записях, не меняя набор методов

### Сценарий NLB-1a-03: happy — read/List под viewer-floor + listauthz-фильтр по `nlb_*`-типу

**ID:** NLB-1a-03

**Given** субъект имеет **viewer**-грант на project с LB `nlb-1a2b3c4d5e6f7g8h`, и **не имеет** гранта на LB `nlb-9z8y7x6w5v4u3t2s` (другой project)

**When** субъект вызывает `NetworkLoadBalancerService.List` (`GET /nlb/v1/networkLoadBalancers?projectId=…`) и `NetworkLoadBalancerService.Get` обоих LB

**Then** read-RPC пропускается под **viewer-floor** (не требует editor); `List` **фильтруется listauthz** под object-type `nlb_network_load_balancer` (`make audit-list-filter`) → в результате виден **только** `nlb-1a2b3c4d5e6f7g8h`, `nlb-9z8y7x6w5v4u3t2s` **отсутствует**
**And** `Get` на `nlb-9z8y7x6w5v4u3t2s` (нет гранта) → hide-existence отказ (byte-identical настоящему miss — `security.md` §Hardening инв-6); тот же listauthz-контракт для `nlb_listener`/`nlb_target_group` List

### Сценарий NLB-1a-04 (negative): нет binding'а на `nlb_*` → fail-closed deny; cross-account deny

**ID:** NLB-1a-04

**Given** субъект в account B **без** какого-либо binding'а на nlb-ресурсы account A

**When** субъект вызывает `NetworkLoadBalancerService.Update`/`Get` на LB account A (`nlb_network_load_balancer`)

**Then** **fail-closed deny** (нет пути в FGA под `nlb_*`-типом) → мутация отвергается; cross-account — deny (субъект account B не резолвит target→project account A); anonymous → `UNAUTHENTICATED` (authN обязателен на обоих листенерах — `security.md` §AuthN+AuthZ ВЕЗДЕ п.1)
**And** «internal = trusted» **не** допущение: :9091-листенер тоже проходит authz-Check на `nlb_*` (defense-in-depth)

### Сценарий NLB-1a-05 (negative / regression): старый `lb_*` object-type больше не резолвит доступ; regression-lock на токен `nlb_*`

**ID:** NLB-1a-05

**Given** rename **завершён** — в модели FGA, scope_extractor и каталоге нет `lb_*`-путей (hard-rename, не synonym)

**When** (regression) тест проверяет, что authz-решение ключуется на **`nlb_*`** — assert токена object-type в scope_extractor-выводе И в permission-catalog-записи (не только «доступ разрешён»)

**Then** доступ резолвится **исключительно** по `nlb_*`; попытка резолва по `lb_*` не даёт пути (нет dangling old-type route) — rename не оставил backdoor; regression-lock ассертит **сам токен** `nlb_network_load_balancer`/`nlb_listener`/`nlb_target_group` (behaviour-level lock — `testing.md` §Regression-lock, не только «зелёный код»)
**And** это гарантия «rename консистентен по всем ~265 sites» — частичный rename (один site пропущен) ловится этим assert'ом (catalog-drift → `permission-catalog-check` красный)

---

## Definition of Done (NLB-1a)

Production-complete в своих границах (`ai-tooling.md` §lifecycle, `testing.md`, `security.md`):

**Rename-консистентность:**
- [ ] Object-type `lb_network_load_balancer`/`lb_listener`/`lb_target_group` → `nlb_*` заменён во **всех** sites: nlb `authzmap`, `services/iam/internal/authzmap`, gateway `internal/check`, permission-catalog генератор, iam-seed FGA-модель. Grep `lb_(network_load_balancer|listener|target_group)` по репо — пусто (кроме исторических migration-комментов, если есть).
- [ ] `scope_extractor` для трёх ресурсов ключёван на `nlb_*` → project (`{nlb_*, <res>_id}`).

**Тесты (TDD, ban #12) — RED до кода, пара RED→GREEN в PR:**
- [ ] `NLB-1a-01..05` — зелёный **newman authz-кейс** (`tests/newman/cases/*.py`, `# verifies NLB-1a-NN`): ≥1 happy (editor-on-`nlb_network_load_balancer` мутирует; viewer-floor read; listauthz-фильтр) + ≥1 negative (no-binding/cross-account deny). Фикстур-ресурсы — `{{runId}}`-суффикс; op-poll `!op.error` перед извлечением id из `metadata`.
- [ ] Regression-lock **behaviour-level** (`NLB-1a-05`): assert токена `nlb_*` в scope_extractor-выводе + catalog-записи (не только code) — `testing.md` §Regression-lock.
- [ ] read-your-writes: первый Get своего свежего ресурса обёрнут `retry_until_authorized` (owner-tuple EC-окно, conv-3) — но негативы (cross-account deny) **НЕ** оборачивать.

**Проектные гейты:**
- [ ] `make -C gateway permission-catalog-check` **byte-identical** (обе embedded-копии); `make audit-list-filter` зелёный; `go test ./... -race` · `golangci-lint run` · `govulncheck` зелёные.
- [ ] `buf lint` зелёный (proto-package/permission-string **не** трогаются — они NLB-4; rename object-type — на уровне FGA-модели/каталога, не proto-shape).
- [ ] Нет shape-change ресурсов, нет новых миграций данных, нет изменения RPC-surface — 1a строго shape-agnostic.

**MERGE-GATE:** 1a **не** зависит от Phase-0 governance change-set (rename ungated). Может мёржиться первой, до 1b. (Родитель MERGE-GATE B1/B3/conv-11 касается формы ресурсов — это 1b, не 1a.)

---

## Сводная traceability-матрица NLB-1 carve (все 58 сценариев родителя)

> **Инвариант carve:** объединение назначений = **все NLB-1-01..58**, **пересечений нет**,
> **пропусков нет**. 1a/1d carve'ят DoD-deliverable'ы родителя (FGA-rename / cross-cutting
> verification), которые родитель выразил **не** как нумерованные `NLB-1-NN`, поэтому вводят
> net-new `NLB-1a-NN`/`NLB-1d-NN`; **все 58** формо-сценариев партиционируются между **1b (47)**
> и **1c (11)**.

### Партиция 58 родительских сценариев

| Под-фаза | Родительские `NLB-1-NN` (владение) | Кол-во |
|---|---|---|
| **NLB-1a** (FGA rename) | — (нет; carve DoD-Q1; net-new `NLB-1a-01..05`) | 0 |
| **NLB-1b** (LB + Listener core + TG.port co-req) | 01,02,03,04,05 · 06,07,08,09,10,11,12,51,52 · 13,14,15,16,17,18,53 · 19,20,21,22,23,24,25,26,54 · 27,28,29,30,31,32,33,55 · **35** · 43,44,45,46,47,48,49,50 | **47** |
| **NLB-1c** (TargetGroup redesign) | 34,36,37,38,39,40,41,42,56 · 57,58 | **11** |
| **NLB-1d** (gateway/newman/cross-cutting) | — (нет; carve DoD e2e-smoke/authz/two-projection; net-new `NLB-1d-01..06`) | 0 |
| **Итого** | | **58** |

### По feature-блокам родителя (F1–F7)

| F | Сценарии родителя | Разбивка по под-фазам |
|---|---|---|
| **F1** id-prefix/malformed/wrong-type/foreign-id | 01,02,03,04,05 | все → **1b** (id-router — фундамент core; все три ресурса Get-able в 1b) |
| **F2** placement-merge/type°/regionId/securityGroupIds | 06,07,08,09,10,11,12,51,52 | все → **1b** |
| **F3** adminState/crossZone/status-recompute/sessionAffinity | 13,14,15,16,17,18,53 | все → **1b** |
| **F4** Listener authoritative targetGroupId/substatus°/resolvedBackendPort°/proxyProtocolV2 | 19,20,21,22,23,24,25,26,54 | все → **1b** |
| **F5** VIP на LoadBalancer: per-family источник/`v4AddressId°`/uniqueness-race/placement-coherence/recycle | 27,28,29,30,31,32,33,55 | все → **1b** |
| **F6** TargetGroup region-scoped/port/HealthCheck oneof-replace/durations/teardown | 34,**35**,36,37,38,39,40,41,42,56 | **35 → 1b** (TG.port field = co-req resolvedBackendPort°); **34,36–42,56 → 1c** |
| **F7** one-shot/teardown/op-poll/deletionProtection/pagination/name-race | 43,44,45,46,47,48,49,50,**57,58** | **43–50 → 1b**; **57,58 → 1c** (inline redesigned TG — needs 1c HealthCheck/port shape) |

### Ключевые carve-решения (для reviewer)

1. **F1 (01–05) → 1b целиком.** id-format-router (`corevalidate.ResourceID` first-statement,
   wrong-type detect, own-only B4, foreign-id peer-validate) — фундамент core. Все три ресурса
   **существуют и Get-able** в 1b (TargetGroup — targetable-ресурс с добавленным `port`; полный
   HealthCheck-redesign — 1c), поэтому multi-resource happy-Get (01) / malformed (02) / wrong-type
   (03) / absent (04) / foreign-id (05) тестируемы уже в 1b.
2. **NLB-1-35 (TG.port BVA) → 1b, НЕ 1c.** `resolvedBackendPort°` (F4, родитель явно кладёт в 1b —
   task 1b-spec `resolvedBackendPort°/substatus°`) **эхает `TargetGroup.port`** → bare-field `port`
   + required-BVA (35) — **co-requisite** Listener-wiring, приземляется в 1b. Полная **port-семантика**
   (LIVE-mutable re-echo `56`, `effectivePort°`-inheritance `39`) — в 1c. Это не деление одного
   сценария: 35 (валидация поля) целиком в 1b, 56/39 (mutability/inheritance) целиком в 1c.
3. **NLB-1-57/58 (one-shot inline `targetGroup`) → 1c.** One-shot **оркестрация** (LB+listener+VIP-сага)
   доказана в 1b через `NLB-1-43` (existing `targetGroupId`); inline-`targetGroup{port,healthCheck}`
   использует **редизайненную** HealthCheck-форму (без `name`, `tcp:{}` oneof) → требует 1c → 57/58 → 1c.
4. **1a/1d владеют 0 из 58** — родитель выразил FGA-rename (Q1) и cross-cutting verification
   (two-projection field-absence, e2e-smoke, authz-matrix, gateway-coherence, read-your-writes) как
   **DoD-пункты**, не как `NLB-1-NN`. 1a/1d carve'ят эти deliverable'ы + вводят net-new нумерованные
   сценарии. Формо-контракт (58) полностью в 1b+1c → покрытие 58/58 доказано.

**Проверка полноты:** 47 (1b) + 11 (1c) = **58**; пересечение 1b∩1c = ∅ (NLB-1-35 в 1b исключён из
1c-списка F6; NLB-1-57/58 в 1c исключены из 1b-списка F7). 1a/1d ∩ {01..58} = ∅. **58/58 покрыты
ровно один раз.**
