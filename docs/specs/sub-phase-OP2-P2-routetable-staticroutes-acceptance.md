# Sub-phase OP2-P2 — RouteTable → kube-ovn Vpc.spec.staticRoutes (KachoRouteTable CRD) — Acceptance

> Статус: DRAFT
> Дата: 2026-06-12
> Ревьюер: acceptance-reviewer (gate перед кодом, ban #1)
> Скилы: `k8s-crd-design` (схема/версионирование/printcolumns/RBAC/reconcile), `evgeniy` (Go-стиль)

### Привязка к тикету (ban #1 + git-youtrack — обязательна ДО APPROVED-for-code)

> [!important] Pre-APPROVAL gate
> Этот acceptance-док НЕ может быть APPROVED-for-code, пока поля ниже не заполнены
> **реальным** KAC-номером (не плейсхолдером). Номер присваивает orchestrator (он
> владеет YouTrack-доступом) до старта кодинга; заведение тикета + KAC-trail — последний
> шаг перед снятием gate, не часть acceptance-текста.

| Поле | Значение |
|---|---|
| Эпик | `KAC-<EPIC>` `[EPIC] kacho-vpc-operator — покрытие VPC-ресурсов (OP2)` (Subtask-иерархия; см. design-doc §2 roadmap) |
| Subtask (этот док) | `KAC-<N>` `OP2-P2 — KachoRouteTable CRD + RouteTable → Vpc.staticRoutes materialization` |
| Ветка `kacho-vpc-operator` | `KAC-<N>` (от `main`) |
| Ветка `kacho-deploy` (CRD/RBAC install, если CRD shipping туда) | `KAC-<N>` (CRD-манифест `kachoroutetables.kacho.io` + дополнения ClusterRole — vpcs read/update) |
| Правка vault `kacho-workspace` | `obsidian/kacho/edges/vpc-operator-to-kubeovn.md` + новая `resources/kacho-vpc-operator-KachoRouteTable.md` + `obsidian/kacho/KAC/KAC-<N>.md` (KAC-trail) |
| YouTrack | `https://prorobotech.youtrack.cloud/issue/KAC-<N>` |
| Роль исполнителя | `acceptance-author` (этот док) → реализация: domain-агенты `kacho-vpc-operator` |

> Затронутые репо: `kacho-vpc-operator` (код CRD + ingress + egress) + `kacho-deploy`
> (CRD-манифест + ClusterRole `kubeovn.io vpcs` get/list/watch/update/patch, если CRD
> устанавливается там) + правка `obsidian/kacho/...` (`kacho-workspace`).
> Зависит от: **OP1** (KachoSubnet machinery — baseline: cluster-scoped CRD, ingress
> poll-syncer без Watch, egress controller-runtime Reconciler, finalizer, field-scoped
> apply, element-prune, degraded-conditions, shared `internal/kubeovn`) — **не должно
> регрессировать**. Сосуществует с **Network→Vpc** ingress: оба пишут ОДИН kube-ovn Vpc
> (см. §«Критический инвариант — field-scoped apply»).
> **Control-plane / proto НЕ меняются** (data-plane-only sub-phase, design-doc §0/§5).

## Обзор

`kacho-vpc-operator` (data-plane sibling, вне build-графа control-plane) уже
материализует **Network → kube-ovn Vpc** (имя Vpc = `network_id`, через
`kubeovn.VpcNameFor`) и **Subnet → N×(kube-ovn Subnet + Multus NAD)** (OP1). Эта
под-фаза добавляет материализацию **Kachō RouteTable → static-routes в том же
kube-ovn Vpc**.

Kachō RouteTable (`kacho_vpc.route_tables`, ID-prefix `enp`, owner `kacho-vpc`) — это
`{id, projectId, networkId, name, staticRoutes[]}`, где каждый `StaticRoute` =
`{ oneof destination{ destinationPrefix(CIDR) }, oneof nextHop{ nextHopAddress | gatewayId }, labels }`.
RouteTable принадлежит Network (`route_tables.network_id → networks(id)`), а каждая
Network 1:1 материализуется в один kube-ovn Vpc (`spec.vpc = network_id`). Целевой
sink — **`Vpc.spec.staticRoutes[]`** (live-выверено на `kind-kacho`, kube-ovn v1.16.1):

```
Vpc.spec.staticRoutes[]:  { cidr, nextHopIP, policy, routeTable, ecmpMode, bfdId }   (object)
```

Маппинг (этой фазы): `StaticRoute{destinationPrefix, nextHopAddress}` →
`Vpc.staticRoutes{ cidr = destinationPrefix, nextHopIP = nextHopAddress }`.
`policy`/`ecmpMode`/`bfdId`/`routeTable` — НЕ заполняются этой фазой (kube-ovn-дефолты
сохраняются; не наши ключи — см. field-scoped apply).

**Согласованная архитектура — промежуточный CRD + два контура (baseline OP1):**

1. **Новый CRD `KachoRouteTable`** (`group kacho.io`, `v1`, **cluster-scoped**, как
   `KachoSubnet`). Spec зеркалит Kachō RouteTable 1:1 (`id`, `projectId`, `networkId`,
   `name`, `staticRoutes[]`). status — `observedGeneration` + `conditions[]`.

2. **INGRESS-контур (Kachō API → CRD).** poll-syncer (нет Watch — конвенция Kachō,
   полл `RouteTableService.List(projectId)`) зеркалит каждую Kachō RouteTable в ОДИН
   `KachoRouteTable` CR (1:1). RouteTable — **network-global** (не зональна), поэтому
   **zone-filter здесь НЕ применяется** (в отличие от Subnet, где материализация
   gated по `zone_id`). Удаление Kachō RouteTable → удаление CR; orphan-cleanup на
   upstream-delete.

3. **EGRESS-контур (CRD → kube-ovn Vpc).** controller-runtime Reconciler материализует
   маршруты **field-scoped** в `Vpc.spec.staticRoutes[]` Network'а: добавляет/обновляет
   ТОЛЬКО элементы, которыми владеет, и **MERGE**-ит их в существующий `spec`, НИКОГДА
   не делая whole-spec/whole-array replace (см. ниже).

**Критический инвариант — field-scoped + element-scoped apply (иначе OCC hot-loop):**

`Vpc` — РАЗДЕЛЯЕМЫЙ объект: его `spec` пишет и **Network→Vpc ingress** (создаёт/держит
сам Vpc, его базовый `spec`), и **этот RouteTable egress** (`spec.staticRoutes[]`), а
kube-ovn-контроллер дефолтит/держит свои поля (`spec.staticRoutes[].policy/ecmpMode`,
прочие spec-поля Vpc). OP1 уже зафиксировал прецедент: whole-spec replace
(`current.Object["spec"] = desired`) стирал чужие/дефолтные ключи каждый reconcile →
kube-ovn передефолчивал → два контроллера в hot-loop (**~1877 OCC «object has been
modified» конфликтов/мин**, виден только на живом кластере; envtest без реального
kube-ovn-контроллера это НЕ ловит — edge-trail `vpc-operator-to-kubeovn.md`). Поэтому:

- egress **читает текущий** `Vpc.spec.staticRoutes[]`, вычисляет desired-set СВОИХ
  маршрутов, и **merge'ит по элементам**: upsert своих, prune только своих исчезнувших,
  **не трогая** ни базовый `spec` Vpc (от Network-ingress), ни staticRoutes-элементы,
  которые этому оператору не принадлежат.
- идентичность владения элементом — по ключу `(cidr, nextHopIP, policy)` (см.
  §«Owned-route identity» и сценарий P2-S3-07).

**НЕТ ownerRef-каскада.** В отличие от OP1 (KachoSubnet владеет отдельными
cluster-scoped kube-ovn Subnet + NAD через `OwnerReference`+`controller=true`),
staticRoutes — **под-поля** одного Vpc, владельцем которого является Network, а не
отдельные объекты. ownerRef на под-элемент массива невозможен и не нужен. Teardown =
**finalizer на KachoRouteTable + element-prune** (удалить из `Vpc.staticRoutes[]` ровно
свои элементы), а не k8s-GC по ownerRef.

**Owned-route identity (ключ владения/prune).** Маршрут считается «нашим» (этого
KachoRouteTable), если присутствует в его desired-set по ключу `(cidr, nextHopIP,
policy)`. element-prune снимает из `Vpc.staticRoutes[]` ровно элементы с этим ключом,
исчезнувшие из desired; элементы с другим ключом (другой RT / Network-ingress /
kube-ovn) — НЕ трогаются. (Доп. наблюдаемость — label/annotation на самом KachoRouteTable;
сам Vpc-элемент массива не несёт owner-label — это под-поле, не объект.)

**Multi-RT aggregation (решение открытого вопроса 4(a), см. ниже).** Network может
владеть НЕСКОЛЬКИМИ RouteTable, но у Vpc — ОДИН `staticRoutes[]`. Решение:
**агрегировать union всех RouteTable данной Network** в `Vpc.staticRoutes[]` (дедуп +
конфликт-политика — P2-S3-06). НЕ «только default-RT».

Трассировка к требованиям — тег **[req: …]** у каждого сценария.

---

## Решения по открытым вопросам design-doc (§4 + RouteTable-секция §2)

Design-doc (`docs/specs/2026-06-12-vpc-operator-coverage-and-multi-az-design.md`)
оставил вопросы по RouteTable открытыми. Решаем здесь (нормативно для реализации):

**(a) Один Network ↔ много RouteTable, один `Vpc.staticRoutes[]`** →
**АГРЕГИРОВАТЬ union всех маршрутов всех RouteTable данной Network** в
`Vpc.staticRoutes[]` (рекомендованный вариант design-doc), НЕ только default-RT.
Обоснование: subnet-scoped привязка `Subnet.route_table_id → policyRoutes` — вне scope
этой фазы (см. (b)); пока нет per-subnet selection, единственный корректный VPC-global
результат — объединение. Каждый egress-reconcile собирает desired-set из ВСЕХ
KachoRouteTable с тем же `networkId`.
- **Дедуп**: идентичные `(cidr, nextHopIP)` из разных RT → ОДИН элемент `Vpc.staticRoutes`
  (без дублей).
- **Конфликт** (один `cidr`, РАЗНЫЕ `nextHopIP` из двух RT): детерминированная политика
  — **первый по стабильному порядку** (сортировка кандидатов по `(routeTableId, cidr,
  nextHopIP)`), остальные конфликтующие — **degraded condition** `RouteConflict` на
  ПРОИГРАВШИХ KachoRouteTable + Event; победитель материализуется (partial-progress,
  не fail всей материализации). См. P2-S3-06.

**(b) VPC-global staticRoutes vs subnet-scoped (policyRoutes)** → эта фаза покрывает
**ТОЛЬКО VPC-global `Vpc.spec.staticRoutes[]`**. `Subnet.route_table_id` →
`Vpc.spec.policyRoutes` (per-subnet source-routing) — **OUT OF SCOPE / future** (см.
§«Не-цели» п.6; зафиксировать как follow-up при необходимости).

**`gateway_id`-next-hop** → StaticRoute с `gatewayId` (а не `nextHopAddress`)
**BLOCKED на фазе Gateway (P4)** — Gateway ещё не материализуется, резолв
`gatewayId → next-hop IP` недоступен. Такой маршрут **НЕ материализуется**, помечается
degraded (`GatewayUnresolved`) и **пропускается**, не валя остальные маршруты
(partial-progress). См. P2-S3-05.

---

## Стадии

OP2-P2 — самостоятельный end-to-end deliverable, 4 стадии (порядок merge):

- **S1** — CRD `KachoRouteTable` (kubebuilder `api/v1` типы + DeepCopy + `config/crd`
  + RBAC-маркеры; cluster-scoped; spec-поля + status conditions + printcolumns).
- **S2** — INGRESS-контур: poll-syncer 1:1 reflect Kachō RouteTable → KachoRouteTable
  CR (create/update/delete; БЕЗ zone-filter — RT network-global); orphan-cleanup.
- **S3** — EGRESS-контур: Reconciler агрегирует RouteTable(s) Network → field-scoped
  merge в `Vpc.spec.staticRoutes[]`; element-prune по `(cidr,nextHopIP,policy)`;
  `gatewayId`-degraded; conflict/dedup; finalizer-teardown (без ownerRef); invalid-CIDR
  degraded.
- **S4** — vault/edge-trail + регресс-гейты (Network→Vpc ingress не клоберится OP1;
  mTLS dial / FGA / ns-operator не тронуты) + CRD/RBAC install (`kacho-deploy`) +
  multi-AZ reuse-заметка.

DoD каждой стадии — её сценарии зелёные (TDD red→green), `go test ./... -race` +
`golangci-lint run` зелёные, envtest для egress-reconcile зелёный.

---

## S1 — CRD `KachoRouteTable` (cluster-scoped, kubebuilder)

**Контекст (recon):** репо — kubebuilder/controller-runtime (`domain: kacho.io`,
layout `go.kubebuilder.io/v4`); `KachoSubnet` (OP1) — образец первого CRD. Добавляем
второй собственный CRD идиоматично: `api/v1/kachoroutetable_types.go`
(+ `zz_generated.deepcopy.go`), `config/crd/...`, RBAC-маркеры (`+kubebuilder:rbac`).
Schema/validation/printcolumns — по скилу `k8s-crd-design`.

### Сценарий P2-S1-01: KachoRouteTable — cluster-scoped CRD с зеркальным spec (happy) [req: CRD-schema]

**ID:** OP2-P2-S1-01

**Given** kubebuilder-проект `kacho-vpc-operator` (`group kacho.io`, `version v1`)
**And** маркер `+kubebuilder:resource:scope=Cluster` на типе `KachoRouteTable` (parity с `KachoSubnet`; ingress↔egress корреляция по cluster-scoped имени)

**When** генерируются CRD-манифесты (`make manifests`) и тип устанавливается в кластер (envtest/kind)

**Then** создаётся CRD `kachoroutetables.kacho.io`, `spec.scope == Cluster`
**And** spec содержит поля, зеркальные Kachō RouteTable 1:1: `id` (string), `projectId` (string), `networkId` (string), `name` (string), `staticRoutes` (`[]StaticRoute`), где `StaticRoute = { destinationPrefix (string, CIDR), nextHopAddress (string, optional), gatewayId (string, optional), labels (map[string]string, optional) }`
**And** JSON-поля CRD — camelCase (`projectId`, `networkId`, `staticRoutes`, `destinationPrefix`, `nextHopAddress`, `gatewayId`) — единый naming Kachō
**And** сгенерирован валидный `DeepCopyObject`/`DeepCopyInto` (объект регистрируется в scheme без паники)

### Сценарий P2-S1-02: status + printcolumns + validation-маркеры (positive) [req: CRD-schema]

**ID:** OP2-P2-S1-02

**Given** тип `KachoRouteTable` с `+kubebuilder:subresource:status` и status-структурой `{ observedGeneration int64, conditions []metav1.Condition }`
**And** printcolumn-маркеры по скилу `k8s-crd-design`

**When** генерируется CRD-манифест

**Then** есть status-subresource с `observedGeneration` + `conditions[]` (стандартный condition-type `Ready`; reasons `Reconciled` / `GatewayUnresolved` / `RouteConflict` / `InvalidRoute`)
**And** printcolumns включают как минимум: `Network` (`.spec.networkId`), `Routes` (число `.spec.staticRoutes`), `Ready` (`.status.conditions[?(@.type=="Ready")].status`), `Age`
**And** валидация полей: `destinationPrefix` — required-в-каждом-элементе (CIDR-string), `nextHopAddress`/`gatewayId` — взаимоисключающие на семантическом уровне (валидируется egress'ом, см. P2-S3-08 — НЕ обязателен webhook)

### Сценарий P2-S1-03: RBAC-маркеры покрывают KachoRouteTable + Vpc-update (edge) [req: CRD-schema][req: rbac]

**ID:** OP2-P2-S1-03

**Given** RBAC-маркеры `+kubebuilder:rbac` для RouteTable-контроллера

**When** генерируется `config/rbac/role.yaml`

**Then** манифест даёт права на `kachoroutetables.kacho.io` (get/list/watch/create/update/patch/delete + `/status` + `/finalizers`)
**And** даёт права на `kubeovn.io vpcs` — **get/list/watch/update/patch** (read-modify-write `spec.staticRoutes`); **БЕЗ create/delete Vpc** (Vpc создаётся/удаляется Network-ingress'ом, RouteTable-egress только мутирует `staticRoutes` существующего Vpc — least-privilege, `k8s-crd-design` §RBAC)
**And** на `Namespace` остаётся read-only (discovery; ns-lifecycle — у ns-operator)
**And** RBAC НЕ запрашивает лишних verb'ов на ресурсах, которыми контроллер не управляет (no wildcard)

### Сценарий P2-S1-04: невалидный/пустой spec (negative) [req: CRD-schema]

**ID:** OP2-P2-S1-04

**Given** установленный CRD `KachoRouteTable`

**When** ingress формирует CR из Kachō RouteTable с пустым `id`

**Then** CR не создаётся с пустым `id` (нет orphan-CR без ключа корреляции)
**And** `KachoRouteTable` с пустым `staticRoutes=[]` допустим как ресурс (RouteTable без маршрутов валидна), egress материализует НОЛЬ наших элементов в `Vpc.staticRoutes` (см. P2-S3-09) — не ошибка валидации CRD
**And** `KachoRouteTable` с пустым `networkId` допустим как ресурс, но egress НЕ материализует маршруты (нет целевого Vpc) и выставляет degraded condition (см. P2-S3-10)

---

## S2 — INGRESS-контур: Kachō RouteTable → KachoRouteTable CR (1:1)

**Контекст (recon):** ingress-syncer (OP1-паттерн `internal/syncer`) обнаруживает
project-namespace'ы (label `managed-by=kacho-project-operator`, uncached
`mgr.GetAPIReader()`), поллит kacho-vpc (Kachō без Watch — конвенция). Для RouteTable
добавляется полл `RouteTableService.List(projectId)` и upsert `KachoRouteTable` CR.
**Zone-filter НЕ применяется** (RouteTable network-global, не зональна). Skip-terminating-ns,
fail-closed cluster-cleanup (`listErr`), uncached reader — сохраняются (parity OP1).

### Сценарий P2-S2-01: новая Kachō RouteTable → создаётся KachoRouteTable CR (happy) [req: ingress-reflect]

**ID:** OP2-P2-S2-01

**Given** обнаружен project-namespace `<ns>` (project `<pid>`)
**And** kacho-vpc `RouteTableService.List(<pid>)` вернул RouteTable `<rid>` (`name=rt1`, `networkId=<nid>`, `staticRoutes=[{destinationPrefix:10.10.0.0/24, nextHopAddress:192.168.88.5}]`)
**And** `KachoRouteTable` с `id=<rid>` ещё не существует

**When** ingress-контур отрабатывает (`reconcileOnce`)

**Then** создаётся cluster-scoped `KachoRouteTable` (имя детерминированно по `<rid>`) со spec, зеркальным Kachō RouteTable 1:1: `id=<rid>`, `projectId=<pid>`, `networkId=<nid>`, `name=rt1`, `staticRoutes=[{destinationPrefix:10.10.0.0/24, nextHopAddress:192.168.88.5}]`
**And** ingress НЕ мутирует `Vpc.staticRoutes` напрямую (это работа egress-контура)
**And** на CR проставлены labels `kacho.io/managed-by=kacho-vpc-operator`, `kacho.io/upstream-id=<rid>`, `kacho.io/project-id=<pid>` (parity OP1)

### Сценарий P2-S2-02: изменилась Kachō RouteTable (добавлен маршрут) → CR обновлён (happy) [req: ingress-reflect]

**ID:** OP2-P2-S2-02

**Given** существует `KachoRouteTable` `<rid>` с одним маршрутом `{10.10.0.0/24 → 192.168.88.5}`
**And** kacho-vpc теперь отдаёт ту же RouteTable с двумя маршрутами `{10.10.0.0/24 → 192.168.88.5}` и `{10.20.0.0/24 → 192.168.88.6}`

**When** ingress отрабатывает

**Then** spec существующего CR обновлён до двух маршрутов (update, не дубль-create)
**And** неизменившиеся поля spec не «дёргаются» зря (update идемпотентен — без spurious resourceVersion-bump при равном spec, см. P2-S2-04)

### Сценарий P2-S2-03: Kachō RouteTable удалена → KachoRouteTable CR удаляется (happy) [req: ingress-delete]

**ID:** OP2-P2-S2-03

**Given** существует `KachoRouteTable` `<rid>` (project `<pid>`)
**And** kacho-vpc `RouteTableService.List(<pid>)` больше НЕ возвращает `<rid>`
**And** все upstream-List'ы по всем проектам прошли успешно (нет `listErr`)

**When** ingress отрабатывает (prune исчезнувших — orphan-cleanup)

**Then** `KachoRouteTable` `<rid>` удаляется (это триггерит egress element-prune его маршрутов из `Vpc.staticRoutes`, см. P2-S3-04)
**And** удаление НЕ происходит, если upstream-List этого project упал (`listErr` — fail-closed, parity OP1): orphan-CR переживает временную недоступность vpc

### Сценарий P2-S2-04: идемпотентность ingress (positive) [req: ingress-reflect][req: idempotency]

**ID:** OP2-P2-S2-04

**Given** `KachoRouteTable` `<rid>` уже в точности соответствует Kachō RouteTable `<rid>`

**When** `reconcileOnce` прогоняется повторно без изменений в kacho-vpc

**Then** CR неизменен (no create, no spurious update/resourceVersion-bump при равном spec)
**And** повторный прогон детерминирован — то же множество CR

### Сценарий P2-S2-05: RouteTable network-global — НЕТ zone-filter (edge) [req: ingress-reflect][req: no-zone-filter]

**ID:** OP2-P2-S2-05

**Given** оператор запущен с `KACHO_VPCOPERATOR_ZONE_ID=zoneA` (multi-AZ конфиг design-doc §3.5)
**And** kacho-vpc отдаёт RouteTable `<rid>` для Network `<nid>` (RouteTable не имеет `zone_id` — она network-global)

**When** ingress отрабатывает

**Then** `KachoRouteTable` `<rid>` создаётся **независимо** от `KACHO_VPCOPERATOR_ZONE_ID` (RouteTable не фильтруется по зоне, в отличие от Subnet, у которой материализация gated по `zone_id == ZONE_ID`)
**And** assert: тот же `<rid>` зеркалится операторами всех зон (network-global семантика; реальная развязка между зонами — на уровне маршрутов/next-hop, не на уровне фильтрации CR)

### Сценарий P2-S2-06: Terminating project-namespace пропущен (edge) [req: ingress-reflect]

**ID:** OP2-P2-S2-06

**Given** project-namespace `<ns>` имеет `deletionTimestamp != nil`

**When** ingress перечисляет project-namespace'ы

**Then** `<ns>` пропускается — vpc `RouteTableService.List(<pid>)` для удаляемого project не вызывается (иначе PermissionDenied → `listErr`, parity OP1)
**And** существующие `KachoRouteTable` CR этого project подчищаются штатно (orphan-cleanup / GC при удалении ns)

---

## S3 — EGRESS-контур: KachoRouteTable → Vpc.spec.staticRoutes (field-scoped, без ownerRef)

**Контекст (recon):** новый controller-runtime Reconciler `For(&KachoRouteTable{})`,
event-driven + periodic resync. Целевой Vpc — `kubeovn.VpcNameFor(networkId)`
(shared `internal/kubeovn`, имя Vpc = `network_id`, тот же, что держит Network-ingress).
Переиспользует apply-дисциплину OP1 (`applyChild` field-scoped merge, `specEqual`
идемпотентность) — НО на под-поле `spec.staticRoutes[]` Vpc, БЕЗ ownerRef (staticRoutes —
не объекты). Контроллер НЕ создаёт и НЕ удаляет сам Vpc.

> [!warning] Watch на разделяемый Vpc
> Поскольку у Vpc нет ownerRef на KachoRouteTable, `Owns(Vpc)` неприменим. Реконсиляция
> Vpc-изменений — через `For(KachoRouteTable)` + periodic resync (kube-ovn-передефолт
> чужих полей не теряем, т.к. field-scoped merge). Опционально — `Watches(Vpc → enqueue
> KachoRouteTable'ы того же networkId)` для быстрого self-heal; не обязателен для
> корректности (resync покрывает). Это деталь реализации, не контракт.

### Сценарий P2-S3-01: один маршрут с nextHopAddress → один Vpc.staticRoute (happy) [req: egress-materialize]

**ID:** OP2-P2-S3-01

**Given** существует kube-ovn Vpc с именем `<nid>` (создан Network-ingress; `spec` с базовыми полями, `staticRoutes` пуст или отсутствует)
**And** создан `KachoRouteTable` `<rid>` (`networkId=<nid>`) с `staticRoutes=[{destinationPrefix:10.10.0.0/24, nextHopAddress:192.168.88.5}]`

**When** egress-Reconciler реконсайлит `<rid>`

**Then** в `Vpc(<nid>).spec.staticRoutes[]` появляется РОВНО один элемент `{ cidr: 10.10.0.0/24, nextHopIP: 192.168.88.5 }`
**And** этот элемент материализован **merge'ом** в существующий `spec` (базовые spec-поля Vpc от Network-ingress сохранены — НЕ перезаписаны)
**And** `policy`/`ecmpMode`/`bfdId`/`routeTable` этого элемента НЕ выставляются оператором (kube-ovn-дефолты не клоберятся — не наши ключи)
**And** status `KachoRouteTable.status` = `Ready=True/Reconciled`, `observedGeneration` обновлён

### Сценарий P2-S3-02: несколько маршрутов в одной RT → несколько Vpc.staticRoutes (happy) [req: egress-materialize]

**ID:** OP2-P2-S3-02

**Given** Vpc `<nid>` существует; `KachoRouteTable` `<rid>` (`networkId=<nid>`) с `staticRoutes=[{10.10.0.0/24 → .5}, {10.20.0.0/24 → .6}, {10.30.0.0/24 → .7}]`

**When** egress реконсайлит

**Then** в `Vpc(<nid>).spec.staticRoutes[]` присутствуют РОВНО 3 наших элемента: `{10.10.0.0/24,.5}`, `{10.20.0.0/24,.6}`, `{10.30.0.0/24,.7}`
**And** порядок/наличие любых не-наших элементов (Network-ingress / kube-ovn) сохранены без изменений
**And** повторный reconcile (равный spec) → no-op (нет spurious write Vpc, см. P2-S3-11)

### Сценарий P2-S3-03: multi-RT aggregation — union маршрутов всех RouteTable Network (happy, КЛЮЧЕВОЙ) [req: multi-rt-aggregation]

**ID:** OP2-P2-S3-03

**Given** Vpc `<nid>` существует
**And** `KachoRouteTable` `<rid-A>` (`networkId=<nid>`) с `staticRoutes=[{10.10.0.0/24 → .5}]`
**And** `KachoRouteTable` `<rid-B>` (`networkId=<nid>`) с `staticRoutes=[{10.20.0.0/24 → .6}]`

**When** egress реконсайлит (любой из RT триггерит сбор всех KachoRouteTable того же `networkId`)

**Then** в `Vpc(<nid>).spec.staticRoutes[]` присутствует **union**: `{10.10.0.0/24,.5}` И `{10.20.0.0/24,.6}` (агрегация всех RouteTable Network, НЕ только default-RT — решение 4(a))
**And** обе KachoRouteTable получают `Ready=True/Reconciled`
**And** assert: реконсиляция `<rid-A>` НЕ удаляет маршрут `<rid-B>` из Vpc (и наоборот) — desired-set egress'а — это union по `networkId`, а не только маршруты реконсайлящегося CR

### Сценарий P2-S3-04: element-prune — маршрут удалён из spec → удалён только этот элемент Vpc (happy, КЛЮЧЕВОЙ) [req: element-prune][req: field-scoped]

**ID:** OP2-P2-S3-04

**Given** Vpc `<nid>`, в `staticRoutes[]` наши элементы `{10.10.0.0/24,.5}` и `{10.20.0.0/24,.6}` (от `KachoRouteTable` `<rid>`)
**And** в том же `staticRoutes[]` есть НЕ-наш элемент `{0.0.0.0/0, nextHopIP: 192.168.88.1, policy: dst}` (например дефолт от Network-ingress / kube-ovn)

**When** spec `KachoRouteTable` `<rid>` обновляется до `staticRoutes=[{10.10.0.0/24 → .5}]` (маршрут `10.20.0.0/24` удалён) и reconcile срабатывает

**Then** из `Vpc(<nid>).staticRoutes[]` удаляется РОВНО элемент `{10.20.0.0/24,.6}` (ключ `(cidr,nextHopIP,policy)` ∉ desired-union)
**And** наш элемент `{10.10.0.0/24,.5}` остаётся нетронутым
**And** НЕ-наш элемент `{0.0.0.0/0,.1,dst}` остаётся нетронутым (element-scoped prune — снимаем ТОЛЬКО элементы из нашего бывшего-desired, не чужие)
**And** базовый `spec` Vpc (поля помимо staticRoutes) не тронут

### Сценарий P2-S3-05: gatewayId-next-hop → degraded GatewayUnresolved, маршрут пропущен (negative, КЛЮЧЕВОЙ) [req: gateway-blocked]

**ID:** OP2-P2-S3-05

**Given** Vpc `<nid>` существует
**And** `KachoRouteTable` `<rid>` (`networkId=<nid>`) с `staticRoutes=[{10.10.0.0/24, nextHopAddress:192.168.88.5}, {10.40.0.0/24, gatewayId:gw-xyz}]` (второй маршрут указывает next-hop через Gateway, не IP)

**When** egress реконсайлит

**Then** маршрут `{10.10.0.0/24 → .5}` (`nextHopAddress`) материализуется штатно в `Vpc.staticRoutes`
**And** маршрут с `gatewayId` **НЕ материализуется** (Gateway-фаза P4 ещё не реализована — резолв `gatewayId → IP` недоступен)
**And** `KachoRouteTable.status` = `Ready=False`, reason `GatewayUnresolved`, message указывает затронутый `cidr`/`gatewayId` (graceful, partial-progress)
**And** один `gatewayId`-маршрут НЕ блокирует материализацию остальных (`nextHopAddress`) маршрутов той же RT
**And** assert: при последующей реализации P4 этот маршрут материализуется без изменения контракта (degraded — временный, разрешается появлением резолвера; зафиксировать как gated на P4)

### Сценарий P2-S3-06: конфликт двух RT (один cidr, разный nextHop) + дедуп идентичных (negative/edge, КЛЮЧЕВОЙ) [req: multi-rt-aggregation][req: conflict-dedup]

**ID:** OP2-P2-S3-06

**Given** Vpc `<nid>` существует
**And** `KachoRouteTable` `<rid-A>` с `staticRoutes=[{10.50.0.0/24 → 192.168.88.5}]`
**And** `KachoRouteTable` `<rid-B>` с `staticRoutes=[{10.50.0.0/24 → 192.168.88.9}]` (тот же `cidr`, ДРУГОЙ nextHop) И `{10.60.0.0/24 → 192.168.88.5}`
**And** `KachoRouteTable` `<rid-C>` с `staticRoutes=[{10.60.0.0/24 → 192.168.88.5}]` (полный дубль маршрута из `<rid-B>`)

**When** egress реконсайлит (union по `networkId`)

**Then** **дедуп**: идентичный `(cidr,nextHopIP)` `{10.60.0.0/24,.5}` из `<rid-B>` и `<rid-C>` → ОДИН элемент `Vpc.staticRoutes` (без дубля)
**And** **конфликт** `10.50.0.0/24`: материализуется детерминированный победитель по стабильному порядку `(routeTableId, cidr, nextHopIP)` — РОВНО один элемент с `cidr=10.50.0.0/24` в `Vpc.staticRoutes` (kube-ovn не должен получить две конфликтующие записи на один cidr)
**And** проигравшая по конфликту KachoRouteTable получает `Ready=False`, reason `RouteConflict`, message указывает `cidr` + конкурирующий RT (Event); победитель и непротиворечивые RT — `Ready=True/Reconciled`
**And** конфликт по одному `cidr` НЕ блокирует материализацию непротиворечивых маршрутов (partial-progress)
**And** assert: результат детерминирован между прогонами (тот же победитель при тех же входах — стабильная сортировка, не map-iteration order)

### Сценарий P2-S3-07: concurrent Network-ingress + RouteTable-egress пишут один Vpc → нет whole-spec clobber (concurrency, КЛЮЧЕВОЙ) [req: field-scoped][req: no-occ-hotloop]

**ID:** OP2-P2-S3-07

**Given** Vpc `<nid>` существует; Network-ingress держит базовый `spec` Vpc (поля помимо staticRoutes — `namespaces`, `staticRoutes`-дефолты kube-ovn и т.п.)
**And** `KachoRouteTable` `<rid>` (`networkId=<nid>`) с `staticRoutes=[{10.10.0.0/24 → .5}]`
**And** в тесте моделируется конкуренция: Network-ingress переписывает свои поля Vpc, RouteTable-egress пишет `staticRoutes`, оба — на один и тот же Vpc

**When** оба пишут Vpc в одном окне (envtest: последовательные reconcile с разными revisions; на живом кластере — фактическая гонка)

**Then** RouteTable-egress читает текущий Vpc и пишет **field-scoped/element-scoped merge** (только `spec.staticRoutes` свои элементы) — НЕ `current.Object["spec"] = desired` (whole-spec replace) и НЕ whole-array replace `staticRoutes`
**And** базовые поля Vpc (от Network-ingress) и не-наши элементы `staticRoutes` после egress-write СОХРАНЕНЫ (не стёрты → нет передефолта kube-ovn → нет hot-loop ~1877 OCC/мин, прецедент OP1)
**And** при OCC-конфликте (Vpc изменён между read и write — `object has been modified`) egress делает retry-on-conflict (re-read + re-merge), НЕ слепой повторный whole-write
**And** идемпотентность: при равном desired повторный reconcile НЕ инициирует write Vpc (no spurious update — `specEqual`)
**And** assert (envtest-уровень): после серии чередующихся write'ов Vpc.spec.staticRoutes содержит ровно union(наши desired) ∪ (не-наши элементы), а базовый spec нетронут — детерминированный конечный стейт без потерь

> [!note] Граница envtest (явно зафиксировать)
> envtest НЕ запускает реальный kube-ovn-контроллер → НЕ воспроизводит сам hot-loop
> (передефолт чужих полей). envtest проверяет **механику** field-scoped/element-scoped
> merge (не-наши ключи/элементы СОХРАНЯЮТСЯ после нашего write, retry-on-conflict
> отрабатывает). Полная проверка отсутствия hot-loop — **на живом кластере** (S4-стадия,
> ручной/стендовый чек как в OP1: 0 конфликтов после фикса). Этот разрыв декларируется
> в DoD (как OP1 §callout).

### Сценарий P2-S3-08: nextHopAddress и gatewayId оба заданы / оба пусты (negative) [req: egress-materialize][req: invalid-route]

**ID:** OP2-P2-S3-08

**Given** Vpc `<nid>` существует
**And** `KachoRouteTable` `<rid>` со staticRoute, где заданы И `nextHopAddress`, И `gatewayId` (нарушение oneof `next_hop`), а также другой staticRoute, где НИ `nextHopAddress`, НИ `gatewayId` не задан

**When** egress реконсайлит

**Then** маршрут с ОБОИМИ next-hop — НЕ материализуется (некорректный next-hop), degraded `Ready=False/InvalidRoute` с указанием `cidr`
**And** маршрут БЕЗ next-hop — НЕ материализуется, тот же degraded `InvalidRoute`
**And** валидные маршруты той же RT материализуются (partial-progress, per-route изоляция)
**And** **prune-fail-safe**: desired-set строится ТОЛЬКО из валидных маршрутов; невалидный маршрут не порождает desired-элемента и НЕ участвует в set-diff → не может спровоцировать ложный prune валидного элемента

### Сценарий P2-S3-09: RouteTable без маршрутов → ноль наших элементов (edge) [req: egress-materialize]

**ID:** OP2-P2-S3-09

**Given** Vpc `<nid>` существует; `KachoRouteTable` `<rid>` (`networkId=<nid>`) с пустым `staticRoutes=[]`

**When** egress реконсайлит

**Then** в `Vpc.staticRoutes` НЕ добавляется наших элементов; не-наши элементы и базовый spec нетронуты; reconcile успешен (не error)
**And** если ранее у `<rid>` были материализованные элементы — все они прунятся из `Vpc.staticRoutes` (desired этого RT пуст → его бывшие элементы ∉ desired-union), не трогая чужие
**And** `Ready=True/Reconciled`

### Сценарий P2-S3-10: networkId пустой / целевой Vpc отсутствует (negative) [req: egress-materialize][req: dangling-ref]

**ID:** OP2-P2-S3-10

**Given** `KachoRouteTable` `<rid>` с непустыми `staticRoutes`, но `networkId=""` ЛИБО `networkId=<nid>`, для которого Vpc `<nid>` ещё не существует (Network-ingress не материализовал, или Network удалена — dangling-ref)

**When** egress реконсайлит

**Then** маршруты НЕ материализуются (нет целевого Vpc); контроллер НЕ создаёт Vpc (Vpc — владение Network-ingress, RBAC без create — P2-S1-03)
**And** `KachoRouteTable.status` = `Ready=False`, reason указывает отсутствие Vpc/networkId (graceful dangling-ref, data-integrity §4 — consumer переживает отсутствие owner без паники)
**And** reconcile requeue'ится (Vpc может появиться позже — Network-ingress материализует) — при появлении Vpc маршруты материализуются без ручного вмешательства
**And** assert: отсутствие Vpc НЕ роняет контроллер (no panic) и НЕ влияет на другие KachoRouteTable

### Сценарий P2-S3-11: идемпотентность egress (positive) [req: idempotency]

**ID:** OP2-P2-S3-11

**Given** `KachoRouteTable` `<rid>` уже материализован (desired-union == текущие наши элементы в Vpc.staticRoutes)

**When** reconcile прогоняется повторно (periodic resync без изменений spec)

**Then** Vpc НЕ получает write (равный desired → no-op merge, `specEqual` по нашим элементам)
**And** число/состав наших элементов в Vpc.staticRoutes стабильны между прогонами; не-наши элементы и базовый spec не «дёргаются»

### Сценарий P2-S3-12: invalid CIDR в destinationPrefix → degraded, пропущен (negative) [req: invalid-route]

**ID:** OP2-P2-S3-12

**Given** Vpc `<nid>` существует; `KachoRouteTable` `<rid>` с `staticRoutes=[{destinationPrefix:10.10.0.0/24, nextHopAddress:.5}, {destinationPrefix:"garbage", nextHopAddress:.6}]`

**When** egress реконсайлит

**Then** маршрут с валидным `10.10.0.0/24` материализуется
**And** маршрут с `"garbage"` — НЕ материализуется; degraded `Ready=False/InvalidRoute` с указанием битого CIDR (CIDR каноникализуется `netip.ParsePrefix` перед использованием — parity OP1 `canonicalCIDR`)
**And** битый CIDR НЕ блокирует валидные (partial-progress) и НЕ участвует в desired-set → НЕ провоцирует prune валидного элемента (prune-fail-safe, как OP1 S3-08)

---

## S4 — teardown (finalizer без ownerRef), регресс-гейты, trail, multi-AZ reuse

### Сценарий P2-S4-01: finalizer-teardown — KachoRouteTable удалён → его маршруты сняты из Vpc, чужие нетронуты (happy, КЛЮЧЕВОЙ) [req: teardown-finalizer][req: element-prune]

**ID:** OP2-P2-S4-01

**Given** на `KachoRouteTable` — finalizer `kacho.io/kachoroutetable-teardown`
**And** `KachoRouteTable` `<rid>` (`networkId=<nid>`) с двумя материализованными маршрутами `{10.10.0.0/24,.5}`, `{10.20.0.0/24,.6}` в `Vpc(<nid>).staticRoutes`
**And** в том же Vpc есть маршрут другого `KachoRouteTable` `<rid-B>` `{10.30.0.0/24,.7}` и не-наш элемент `{0.0.0.0/0,.1,dst}`

**When** `KachoRouteTable` `<rid>` удаляется (ingress снёс CR — P2-S2-03; deletionTimestamp выставлен)

**Then** контроллер в Terminating **element-prune'ит ровно маршруты `<rid>`** (`{10.10.0.0/24,.5}`, `{10.20.0.0/24,.6}`) из `Vpc.staticRoutes` (по ключу `(cidr,nextHopIP,policy)`), затем снимает finalizer
**And** маршрут `<rid-B>` `{10.30.0.0/24,.7}` и не-наш элемент `{0.0.0.0/0,.1,dst}` — **НЕ тронуты** (teardown — element-scoped, не whole-array)
**And** **НЕТ ownerRef-каскада / k8s-GC по Vpc** (Vpc — не owned-объект; teardown полностью через finalizer+element-prune; сам Vpc НЕ удаляется)
**And** базовый `spec` Vpc нетронут
**And** assert: при дедуп-сценарии (маршрут `<rid>` совпадал с маршрутом ещё-живого `<rid-B>`) элемент при teardown `<rid>` НЕ удаляется, пока он остаётся в desired-union (живой RT всё ещё «владеет» им) — element-prune считает union ОСТАВШИХСЯ RT, не «минус только мои»

### Сценарий P2-S4-02: Network→Vpc ingress (OP1) не клоберится (regression) [req: non-goal][req: field-scoped]

**ID:** OP2-P2-S4-02

**Given** Network-ingress материализует/держит Vpc `<nid>` (имя=`network_id`, базовый spec) — поведение OP1

**When** RouteTable-egress многократно мутирует `Vpc.staticRoutes`

**Then** Network-ingress продолжает корректно держать Vpc (базовый spec, имя) — RouteTable-egress НИКОГДА не создаёт/не удаляет Vpc и не переписывает его базовые поля
**And** существующая OP1-материализация (Subnet→child Subnet+NAD) не затронута (RouteTable-egress пишет ТОЛЬКО `Vpc.staticRoutes`)
**And** shared `internal/kubeovn` (`VpcNameFor`, label-ключи) переиспользуется без drift (новый egress НЕ дублирует naming-логику — design-doc §1 «drift = корень бага #1»)

### Сценарий P2-S4-03: mTLS dial / FGA / ns-operator не регрессируют (regression) [req: non-goal][req: SEC-G]

**ID:** OP2-P2-S4-03

**Given** SEC-G: per-edge mTLS dial (`upstream.Dial`/`DialIAM`, `TLSClient{enable}`) + principal-инжект + least-priv SA viewer; ns-operator владеет namespace-lifecycle

**When** ingress поллит kacho-vpc `RouteTableService.List` через тот же `upstream.Client`

**Then** dial-поведение неизменно: `enable=false` → insecure (back-compat), `enable=true` → mTLS + principal-metadata; principal/FGA-viewer требования к чтению RouteTable — те же, что для Subnet/Network (новое чтение `RouteTableService.List`, не новое ребро)
**And** `cmd/nsoperator`/`internal/nssyncer` без изменений поведения; RBAC оператора на Namespace — read-only
**And** существующие upstream/mTLS/config-тесты остаются зелёными

### Сценарий P2-S4-04: CRD/RBAC install + multi-AZ reuse-заметка (setup/trail) [req: rbac][req: multi-az-reuse][req: vault]

**ID:** OP2-P2-S4-04

**Given** второй собственный CRD оператора (`kachoroutetables.kacho.io`) требует install + расширение ClusterRole (`kubeovn.io vpcs` update/patch); design-doc §3.2/§3.5 указывает, что **тот же field-scoped `Vpc.staticRoutes` egress** — механизм для установки remote-zone /18 маршрутов в multi-AZ

**When** готовится реализация и развёртывание

**Then** CRD `kachoroutetables.kacho.io` + дополненный ClusterRole установлены там, где деплоится оператор (`kacho-deploy`, если CRD shipping туда; ветка `kacho-deploy = KAC-<N>`)
**And** установка CRD/RBAC не ломает существующий deploy (OP1 Subnet-материализация, mTLS/SA/webhook — S4-02/03 без регресса)
**And** реализация выносит запись в `Vpc.staticRoutes` в **переиспользуемый хелпер** (`internal/kubeovn` или egress-shared), чтобы multi-AZ remote-/18-route egress (design-doc §3.2 «дорожки сходятся» — RouteTable-фаза = learn-side custom-VPC) переиспользовал ту же field-scoped merge-механику, БЕЗ копипасты (drift-prevention)
**And** `obsidian/kacho/edges/vpc-operator-to-kubeovn.md` обновлён: новый поток `Kachō RouteTable → KachoRouteTable CR (ingress) → Vpc.staticRoutes field-scoped merge (egress)`, deletion-семантика (element-prune без ownerRef, finalizer), запись в «История» с KAC-номером
**And** создана узкая `resources/kacho-vpc-operator-KachoRouteTable.md` (CRD-контракт: scope=Cluster, spec-поля, **НЕТ ownerRef-каскада**, owned-route identity `(cidr,nextHopIP,policy)`, multi-RT aggregation/конфликт-политика, gatewayId-gated-P4) + создан/обновлён KAC-trail `obsidian/kacho/KAC/KAC-<N>.md`

---

## Тестовая стратегия (envtest для egress-reconcile + fake RouteTable resolver)

- **envtest (egress-controller)** — обязателен; fake kube-ovn Vpc (unstructured, GVK
  `kubeovn.io/v1 Vpc`, установленная CRD-схема из `kacho-deploy`) + fake/seeded
  KachoRouteTable CR'ы (роль «RouteTable resolver» играет набор KachoRouteTable в
  кластере — egress собирает union по `networkId`):
  - single route → один Vpc.staticRoute `{cidr,nextHopIP}`, базовый spec сохранён (P2-S3-01).
  - multi-route одной RT → N элементов (P2-S3-02).
  - multi-RT aggregation: 2 RT одного networkId → union, реконсиляция одной не сносит маршруты другой (P2-S3-03).
  - element-prune: маршрут удалён из spec → снят ровно этот элемент, наши прочие и не-наши/базовый spec нетронуты (P2-S3-04).
  - `gatewayId`-route → degraded `GatewayUnresolved`, пропущен, `nextHopAddress`-маршруты материализованы (P2-S3-05).
  - conflict (один cidr, разный nextHop) + дедуп идентичных → один детерминированный элемент, проигравший RT degraded `RouteConflict` (P2-S3-06).
  - **field-scoped/element-scoped merge**: предзаполнить Vpc базовым spec + не-нашими staticRoutes → после нашего write они СОХРАНЯЮТСЯ; whole-spec/whole-array replace → тест RED; retry-on-conflict при изменённом revision (P2-S3-07). Граница: реальный hot-loop — только живой кластер (S4, как OP1 callout).
  - invalid route (оба/ни одного next-hop; битый CIDR) → degraded `InvalidRoute`, partial-progress, prune-fail-safe (P2-S3-08, P2-S3-12).
  - пустой staticRoutes / пустой networkId / отсутствующий Vpc → ноль/degraded, no-panic, requeue (P2-S3-09, P2-S3-10).
  - повторный reconcile → no-op (P2-S3-11).
  - finalizer-teardown: delete KachoRouteTable → element-prune своих маршрутов, finalizer snap, чужие/базовый spec нетронуты, НЕТ ownerRef-GC; dedup-aware (P2-S4-01).
- **unit** — ingress diff (create/update/delete CR против набора Kachō RouteTable,
  fail-closed `listErr`, no zone-filter), desired-union builder (агрегация по
  `networkId` + дедуп + детерминированная конфликт-сортировка `(routeTableId,cidr,nextHopIP)`),
  StaticRoute→Vpc.staticRoute маппинг (`destinationPrefix→cidr`, `nextHopAddress→nextHopIP`,
  `gatewayId`→skip+degraded), owned-route identity `(cidr,nextHopIP,policy)` set-diff,
  CIDR-каноникализация; через fake client / mock upstream.
- **TDD** — для каждого сценария: падающий тест (RED по правильной причине) ДО кода →
  GREEN; в отчёте — пара RED→GREEN.
- Финальная верификация: `go test ./... -race` + `golangci-lint run` зелёные; egress
  envtest зелёный; field-scoped no-clobber подтверждён на живом стенде (S4, ручной чек
  как OP1).

---

## Не-цели (explicit non-goals)

1. **Контракт Kachō / proto НЕ меняется** — никаких новых RPC/полей в
   kacho-vpc/kacho-proto; `KachoRouteTable` spec ТОЛЬКО зеркалит существующую Kachō
   RouteTable. Kachō по-прежнему без Watch — поллинг сохраняется.
2. **Network→Vpc ingress (OP1) не переписываем** — Vpc создаёт/держит/удаляет
   Network-ingress; RouteTable-egress ТОЛЬКО мутирует `Vpc.spec.staticRoutes` (RBAC без
   create/delete Vpc).
3. **Никакого whole-spec / whole-array replace Vpc** — строго field-scoped (базовый
   spec) + element-scoped (`staticRoutes` по ключу) merge; иначе OCC hot-loop (прецедент
   OP1 ~1877 конфл/мин).
4. **gatewayId-next-hop — gated на Gateway-фазу P4** — пока degraded `GatewayUnresolved`
   + skip (не fail всей RT). Резолв `gatewayId → IP` появится с P4 без изменения этого
   контракта.
5. **mTLS/FGA/ns-operator не трогаем** — SEC-G поведение и namespace-lifecycle без
   регресса.
6. **Subnet-scoped routing (`Subnet.route_table_id` → `Vpc.spec.policyRoutes`) — OUT OF
   SCOPE / future** — эта фаза покрывает ТОЛЬКО VPC-global `Vpc.spec.staticRoutes`
   (решение 4(b)). policyRoutes/source-routing — отдельная под-фаза.
7. **`policy`/`ecmpMode`/`bfdId`/`routeTable`-поля Vpc.staticRoutes не выставляются
   оператором** — kube-ovn-дефолты не клоберятся (не наши ключи). ECMP/BFD multi-path —
   вне scope (multi-AZ prod-тир, design-doc §3.2).
8. **Multi-AZ remote-/18 routes — НЕ реализуются здесь** — лишь требуется, чтобы
   field-scoped `Vpc.staticRoutes` egress был **переиспользуемым** для будущего multi-AZ
   learn-side (design-doc §3.2/§3.5/§5 risk 2; P2-S4-04).

---

## Трассировка требований → сценарии

| Требование | Сценарии |
|---|---|
| CRD schema (cluster-scoped, spec-поля, DeepCopy, status, printcolumns, validation) | P2-S1-01, P2-S1-02, P2-S1-04 |
| RBAC least-priv (KachoRouteTable + Vpc update/patch, БЕЗ Vpc create/delete) | P2-S1-03, P2-S4-04 |
| ingress 1:1 reflect (create/update/delete CR), fail-closed listErr | P2-S2-01, P2-S2-02, P2-S2-03, P2-S2-04, P2-S2-06 |
| no zone-filter (RouteTable network-global) | P2-S2-05 |
| egress materialize StaticRoute → Vpc.staticRoute (cidr/nextHopIP) | P2-S3-01, P2-S3-02, P2-S3-09 |
| multi-RT aggregation (union по networkId, НЕ default-RT only) | P2-S3-03, P2-S3-06 |
| dedup идентичных + детерминированный conflict (cidr ↔ разный nextHop) | P2-S3-06 |
| element-prune по (cidr,nextHopIP,policy) — только свои элементы | P2-S3-04, P2-S3-09, P2-S4-01 |
| field-scoped / element-scoped apply (нет whole-spec/whole-array replace), retry-on-conflict | P2-S3-04, P2-S3-07, P2-S4-02 |
| no-OCC-hotloop (концепт + envtest-граница + живой чек) | P2-S3-07 |
| gatewayId → degraded GatewayUnresolved + skip (gated P4) | P2-S3-05 |
| invalid route (оба/ни одного next-hop; битый CIDR) → degraded InvalidRoute, partial-progress, prune-fail-safe | P2-S3-08, P2-S3-12 |
| dangling-ref (пустой networkId / отсутствующий Vpc) → degraded + requeue, no-panic, контроллер НЕ создаёт Vpc | P2-S3-10 |
| idempotency (ingress + egress) | P2-S2-04, P2-S3-11 |
| teardown через finalizer + element-prune (НЕТ ownerRef-каскада) | P2-S4-01 |
| non-goal: Network→Vpc ingress (OP1) не клоберится, shared kubeovn без drift | P2-S4-02 |
| non-goal: mTLS/FGA/ns-operator не регрессируют (SEC-G) | P2-S4-03 |
| multi-AZ reuse (field-scoped Vpc.staticRoutes egress переиспользуем) | P2-S4-04 |
| CRD/RBAC install (kacho-deploy) + trail (vault edge/resource/KAC) | P2-S4-04 |
| ticket/branch binding (ban #1, pre-APPROVAL gate) | заголовок §«Привязка к тикету» |
