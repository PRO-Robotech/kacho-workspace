# Sub-phase VPC-1 (Network + Subnet placement-anchor) — Acceptance

> Статус: **✅ APPROVED** (recorded by acceptance-reviewer verdict) (ре-ревью раунд 1 применён — 6 findings + 5 дефолтов вшиты; на повторный review `acceptance-reviewer`)
> Дата: 2026-07-20
> Ревьюер: acceptance-reviewer (CHANGES REQUESTED раунд 1 → адресовано; pending re-review)
> Эпик/тикет: KAC-VPC-1 (Phase-2 owner-сервис, redesign-2026; блокирует compute+nlb)
> Монорепо: `project/kacho` (`github.com/PRO-Robotech/kacho`) — легаси `project/kacho-*` не затрагивается.

## Обзор

VPC-1 — первый инкремент пересборки-2026 модуля `kacho-vpc` — reference-grade suite
(7 ресурсов, 255 newman-кейсов), поэтому редизайн разбит на 4 под-фазы (см. §Out-of-scope
декомпозицию). VPC-1 закладывает **фундамент**: **Network** (изолированный routing-домен с
объявленным супернетом `ipv4CidrBlocks[]`/`ipv6CidrBlocks[]`, авто-провижн default-SG+default-RT,
op-in-response) и **Subnet** — **единственный placement-anchor** всего продукта
(`placementType°` server-derived из `zoneId` XOR `regionId`, CIDR ⊆ супернет, zone-coherence).
Все остальные placement-scoped ресурсы Kachō (Address/NIC/Gateway VPC, Instance/Volume compute,
NLB) наследуют зону/регион через `subnetId` — поэтому Subnet-контракт обязан быть зафиксирован
первым.

Под-фаза приводит owner-side проекции Network/Subnet к целевому tenant-facing дизайну
(`docs/plans/kacho-redesign-2026/module-vpc.md` §Network/§Subnet, §Правила 1/2/5/11/12/13/14) и
общему хребту (`00-unified-system-design.md` §1 conv-1/2/3/12, §5 инв-2/5/6). Это **owner-side**
под-фаза: сценарии описывают наблюдаемое поведение публичного `NetworkService`/`SubnetService`
(`:9090` → edge REST). Discovery-каталоги (`ListPlaceableZones`/`SuggestCidrBlocks`/
`ListLaunchableSubnets`), governance-repoint (`SetDefaultSecurityGroup`/`SetDefaultRouteTable`) и
все прочие ресурсы (SG/RT/Gateway/NIC/Address/AddressPool) — отдельные под-фазы (§Out-of-scope).

---

## Scope

Что VPC-1 покрывает сценариями (positive + negative + edge + concurrent-race):

| # | Фича | Traceability |
|---|---|---|
| F1 | id-prefix per-type: `net-`/`sub-` (hyphen B3); malformed/**wrong-type** → `INVALID_ARGUMENT "invalid <res> id '<X>'"` первым стейтментом; foreign-id (projectId/zoneId) **НЕ** prefix-checked (B4 own-only) | module-vpc §Правила 14; unified §1 conv-12 **[PHASE-0-GATED B3]**, §8 B3/B4 |
| F2 | Network: declared супернет `ipv4CidrBlocks[]`/`ipv6CidrBlocks[]` (immutable через `Update`; мутируется только `:add-cidr-blocks`/`:remove-cidr-blocks`) | module-vpc §Network, §Правила 11/14; unified §2 vpc |
| F3 | Network: system-provisioned default-SG **и** default-RT (**безусловно**), их id эхаются в `Operation.response`; default-SG-политика — stateful initiating egress `0.0.0.0/0` | module-vpc §Network (defaults), §Ментальная модель Recipe A; unified §1 conv-4 |
| F4 | Network: op-in-response (statusless → `Operation{done:true}` + **полное тело** в `response`, follow-up GET не нужен); happy CRUD | module-vpc §Network, §Правила 2; unified §1 conv-2, §3 |
| F5 | Network: Delete непустой → `FAILED_PRECONDITION "network is not empty"`; `projectId` immutable; `name` UNIQUE(project,name) → `ALREADY_EXISTS` (+ concurrent-race) | module-vpc §Network, §Правила 12/13; unified §5 инв-6 |
| F6 | Subnet: единственный placement-anchor; `placementType°` **server-derived** (unwritable) из `zoneId` XOR `regionId`; explicit reject (оба/ни одного; `placementType` в теле write) | module-vpc §Subnet, §Правила 5/11; unified §2 vpc, §5 инв-2 |
| F7a | Сеть без объявленного супернета семейства ОТКАЗЫВАЕТ подсети этого семейства: `INVALID_ARGUMENT "network declares no IPv4 supernet: add blocks via :add-cidr-blocks (ipv4CidrBlocks) before creating an IPv4 subnet"`. Прежде проверка на пустом супернете ПРОПУСКАЛАСЬ, а поле не обязательно на создании сети — то есть ограничение не действовало на целом классе сетей, при том что контракт заявлял вложенность безусловно. Отсутствие супернета ЧУЖОГО семейства подсети не касается | выведено 2026-08-11 из вопроса «зачем супернет, если подсети нарезаются в subnets» |
| F7 | Subnet CIDR: `ipv4CidrPrimary` (immutable anchor ⊆ **одного** супернет-блока) + `ipv4CidrBlocks[]`; CIDR ∉ супернет → `INVALID_ARGUMENT`; no-overlap EXCLUDE → `FAILED_PRECONDITION "subnet CIDRs can not overlap"` (+ concurrent-race) | module-vpc §Subnet (CIDR-роль), §Правила 12/13; unified §5 инв-6 |
| F7a | **Уточнение F7:** вложенность из F7 действует **безусловно** — сеть, не объявившая супернет семейства, подсеть этого семейства НЕ принимает: `INVALID_ARGUMENT "network declares no IPv4 supernet: add blocks via :add-cidr-blocks (ipv4CidrBlocks) before creating an IPv4 subnet"` (v6 — зеркально). Поле супернета опционально на `Network.Create`, поэтому сеть без адресного плана — штатное состояние, а не край; путь вперёд назван в самом отказе. Отсутствие супернета **чужого** семейства подсети не касается | module-vpc §Subnet (CIDR-роль), §Network (declared супернет); unified §5 инв-6 |
| F8 | Subnet: zone/region coherence — существование `zoneId`/`regionId` peer-validate geo (fail-closed `UNAVAILABLE`); auto-associate `routeTableId = network.defaultRouteTableId°`; immutables | module-vpc §Subnet, §Правила 4/5/11; unified §4 (vpc→geo), §5 инв-2 |
| F9 | Subnet: op-in-response; within-service absent-network → `NOT_FOUND` (ungated, pre-flight); peer-validate zone/region → target `FAILED_PRECONDITION` **[PHASE-0-GATED conv-11]**; malformed sync-reject; DhcpOptions сняты by design; List-filter `zoneId=`/`networkId=`; v6-only edge | module-vpc §Subnet, by-design omissions, §Правила 13; unified §1 conv-11 **[peer-validate/reason-token PHASE-0-GATED]** |

> **Как читать идентификаторы фич (введено вместе с F7a).** Номер без буквы — самостоятельная
> фича. **Буквенный суффикс — уточнение своей базовой фичи**, и строка с ним стоит **сразу
> после** базовой, а не перед ней. Отсюда однозначность обеих форм ссылки: `F7` означает
> базовую строку и ровно её (вложенность CIDR подсети в объявленный блок + непересечение) —
> смысл этой ссылки не менялся, и все существующие упоминания `F7` в коде, пробах и записках
> остаются верны; `F7a` означает уточнение и называется полностью там, где речь именно о нём.
> Ссылка «F7 и его уточнения» пишется словами, а не подразумевается порядком строк.
>
> **Нумерация сценариев — только вперёд.** Новые сценарии получают следующие свободные номера
> (`VPC-1-47` и далее) и **никогда** не вклиниваются в занятый диапазон: `VPC-1-NN` — живая
> координата в аннотациях `# verifies …` newman-кейсов и в именах integration-проб, поэтому
> перенумерация сделала бы неверными ссылки, которые уже кем-то написаны. Раздел фичи при этом
> вправе стоять рядом со своей базовой, даже если его сценарии по номеру идут последними.

## Out-of-scope (явно НЕ в VPC-1)

**Декомпозиция редизайна vpc на под-фазы** (порядок — по dependency-графу; placement-anchor
Subnet — фундамент, поэтому VPC-1 первым):

- **VPC-2 — SecurityGroup + RouteTable** (network-children, без внешних deps): `SecurityGroup`
  (`networkId` immutable, rules через verb-pair `:add-rule`/`:remove-rule`, per-rule OCC
  `expectedVersion`, general `Update` bare без rules; prefix `scg` **AS-IS `sgr`** — B3-приведение);
  `RouteTable` (`staticRoutes` через `:add-route`/`:remove-route`, `natGatewayId` vs `nextHopAddress`;
  coherence-gate Subnet↔Gateway-через-RT приземляется когда Gateway существует — VPC-4). Также
  сюда: `NetworkService.SetDefaultSecurityGroup`/`SetDefaultRouteTable` (governance re-point на
  **tenant-созданную** SG/RT — существуют только после VPC-2); снятие `SecurityGroup.defaultForNetwork°`.
- **VPC-3 — Address + AddressPool + sweeper** (IPAM-фундамент, **до** Gateway/NIC — оба
  референсят/аллоцируют Address): `Address` (IPAM lease, один IP, `scope°` derived из binding-ref,
  `retention EPHEMERAL/RESERVED`, **recycle-on-delete B17**, `usedBy°` `Referrer` CAS через
  `InternalAddressService.SetReference`/`ClearReference`); `AddressPool` **Internal-only** (`:9091`);
  compensation sweeper-reconciler **B12** (реклейм dangling-lease past TTL).
- **VPC-4 — Gateway + NIC** (оба зависят от Address VPC-3 + SG VPC-2 + Subnet VPC-1): `Gateway`
  (`networkId` FK immutable, `NAT_GATEWAY`, `placementType°`, one-shot `externalAddressSpec` →
  alloc external Address; shared default-route target обязан быть REGIONAL); `NetworkInterface`
  (first-class, `usedBy°` polymorphic `Referrer`, **poll** не op-in-response, `effectiveSecurityGroupIds°`,
  `AssociateAddress`/`DisassociateAddress`, `addressSpecs[]` one-shot, `InternalNetworkInterfaceService.SetReference`).
  Coherence Subnet↔Gateway-через-RT замыкается здесь.

> **Open question к reviewer (ordering):** task-канва предлагала VPC-3=Gateway+NIC, VPC-4=Address.
> Черновик **инвертирует**: Address (VPC-3) → Gateway+NIC (VPC-4), т.к. `Gateway.externalAddressSpec`,
> `NIC.addressSpecs[]` и `NIC.AssociateAddress` **все** аллоцируют/референсят Address — форвард-
> зависимость Gateway/NIC → Address недопустима, если Address последний. См. §Открытые вопросы.

**Прямо вне VPC-1 (даже по Network/Subnet):**
- **Discovery-каталоги Subnet** (`SubnetService.ListPlaceableZones` / `SuggestCidrBlocks` /
  `ListLaunchableSubnets`) — net-new sync-каталоги с `requestFragment`; переиспользуют geo-fan-out
  и свободный-CIDR-расчёт супернета. Выносятся в **VPC-1b (discovery)** (после того как Network-супернет
  и Subnet-anchor зафиксированы). VPC-1 фиксирует **только** прямые CRUD Network/Subnet.
- **`validateOnly:true` sync dry-run** (conv-6) на Network/Subnet Create — net-new dry-run path
  (echo `resolved{suggestedCidr, conflictingRanges}`, derived `placementType`). Выносится в VPC-1b
  вместе с discovery (обе фичи закрывают «слепое вырезание CIDR» совместно). VPC-1 покрывает
  реальную мутацию + все её негативы.
- **`InternalNetworkService.GetNetwork`** (full-проекция incl. `vrfId`/underlay, two-projection
  conv-8) — `vrfId` (`route_distinguisher`/`vrf_id`) уже AS-IS Internal-only; VPC-1 лишь фиксирует,
  что публичный `Network` **не несёт** `vrfId`/underlay (assert field-absence), но саму
  Internal-проекцию не расширяет (owner — отдельная internal-под-фаза).
- **FGA owner-tuple материализация** (`fga_register_outbox` register-drainer/reconciler) —
  eventually-consistent; VPC-1 **не гейтит** `Operation.done` на её видимость (ban #9, conv-3).
  Поведение outbox не меняется; read-your-writes окно закрывается bounded client-retry на клиенте.
- **Cross-service peer-validate placement из consumer'ов** (`compute→vpc`, `nlb→vpc`) — под-фазы
  консумеров. VPC-1 фиксирует **только** vpc-side coherence (Subnet↔zoneId через geo) и
  self-describing derived `zoneId°`/`regionId°` на Subnet, которые консумер потом читает.

## Traceability-легенда

`°` = output-only поле (server-derived, на вход не принимается; попытка задать — silent-ignore для
derived-эхо, **explicit reject** для write-feedback полей вроде `placementType`). REST-пути публичные
`/vpc/v1/…` (:9090, external-safe). JSON — camelCase (`projectId`, `networkId`, `ipv4CidrBlocks`,
`createdAt`). Все timestamps усечены до секунд на wire. Каждый сценарий несёт ссылку
`→ module-vpc §…` / `→ unified §…`. **[PHASE-0-GATED]** = зависит от Phase-0 governance change-set
(см. §Definition of Done merge-gate).

---

## F1 — id-prefix per-type (hyphen B3) + malformed/wrong-type first-statement

> `→ module-vpc` §Правила 14, легенда · `→ unified §1 conv-12 [PHASE-0-GATED B3], §8 B3/B4`
> **AS-IS:** `corevalidate.ResourceID("network", ids.PrefixNetwork, id)` **уже** отрабатывает
> первым стейтментом (`network/get.go:61`, `subnet/get.go:62`) → `"invalid network id '<X>'"`;
> текущие prefix'ы `ids.PrefixNetwork="net"`, `ids.PrefixSubnet="sub"` — **3-char, БЕЗ дефиса**
> (`pkg/ids/ids.go:49-50`). Механизм first-statement-reject существует; B3 меняет **байты
> префикса** на hyphen-форму `net-`/`sub-`.
> **[PHASE-0-GATED B3]:** переход `net`/`sub` → `net-`/`sub-` фиксируется Phase-0 в
> `corevalidate`+`api-conventions.md` (рекомендация 00-unified §8 B3: **с дефисом**), затем
> vpc/nlb приводятся. До merge change-set VPC-1 строит на текущей 3-char-форме; hyphen-миграция
> приземляется одним махом с corelib prefix→type-router. Wrong-type-detection и own-only
> prefix-check (B4) — **ungated** (действуют в любой форме префикса).
> **NB (module-vpc пример vs B3):** JSONC-примеры в `module-vpc.md` показывают `netv8f3k…`
> (без дефиса, до-B3); нормативна **B3-резолюция с дефисом** — примеры дока обновятся.

### Сценарий VPC-1-01: happy — Network.Get по валидному `net-`-id

**ID:** VPC-1-01

**Given** сеть `net-v8f3k2q9m4t1n7` существует в проекте `prj-b3n7k1x9q2m5t8`

**When** клиент вызывает `NetworkService.Get` (`GET /vpc/v1/networks/net-v8f3k2q9m4t1n7`)

**Then** `200 OK`; тело — public `Network` с `id == "net-v8f3k2q9m4t1n7"`, `projectId`, `createdAt°` (усечён до секунд)

### Сценарий VPC-1-02 (negative): malformed id → sync `INVALID_ARGUMENT` первым стейтментом

**ID:** VPC-1-02

**When** клиент вызывает `NetworkService.Get` (`GET /vpc/v1/networks/garbage!!`)

**Then** **синхронный** `INVALID_ARGUMENT` с текстом `"invalid network id 'garbage!!'"` — malformed ловится `corevalidate.ResourceID` **до** любого repo-вызова (repo НЕ вызывается)
**And** то же для `SubnetService.Get` (`GET /vpc/v1/subnets/garbage!!`) → `"invalid subnet id 'garbage!!'"`

### Сценарий VPC-1-03 (edge): wrong-type prefix → `INVALID_ARGUMENT` (не `NOT_FOUND`)

**ID:** VPC-1-03

**Given** id `sub-t4k8n2q0m5v9h1` — валидный по charset/длине, но с **чужим** типом-префиксом (`sub-`, не `net-`)

**When** клиент вызывает `NetworkService.Get` (`GET /vpc/v1/networks/sub-t4k8n2q0m5v9h1`)

**Then** **синхронный** `INVALID_ARGUMENT "invalid network id 'sub-t4k8n2q0m5v9h1'"` — prefix однозначно кодирует тип, wrong-type ловится тем же first-statement (не доезжает до `repo.Get` → **не** `NOT_FOUND`); bare-id через seam compute↔vpc / nlb↔vpc routable по типу без lookup

### Сценарий VPC-1-04: well-formed-но-отсутствует → `NOT_FOUND` (direct-read lane)

**ID:** VPC-1-04

**When** клиент вызывает `NetworkService.Get` (`GET /vpc/v1/networks/net-000000000000000`) — валиден, но не существует

**Then** `NOT_FOUND "Network net-000000000000000 not found"` (direct-read lane — прошёл format-check, `repo.Get` вернул miss)

### Сценарий VPC-1-05 (edge, B4): foreign-id (projectId) НЕ prefix-checked — только peer-validate existence

**ID:** VPC-1-05

> **AS-IS:** `NetworkService.Create` c отсутствующим `projectId` возвращает `NOT_FOUND "Project %s not found"` (`network/create.go:197`, peer-validate `iam.ProjectService.Get`). Целевой by-lane тон (conv-11: peer-validate → `FAILED_PRECONDITION`) — **[PHASE-0-GATED]**, см. F8/VPC-1-35 и §Definition of Done merge-gate.

**Given** вызывающий создаёт Network c `projectId = "not-a-prj-slug"` (проходит длину `<=50`, но не соответствует ни одному vpc-owned prefix)

**When** `NetworkService.Create` (`POST /vpc/v1/networks`) с этим `projectId`

**Then** отказ приходит **не** как format-`"invalid project id"` (foreign scope-coord iam-owned — **не** prefix-checked форматом, B4 own-only), а как **peer-validate existence-result**: `Operation{done:true}` c `result.error`, где вызывающий проверяется через `iam.ProjectService.Get` (existence-only, не format)
**And** конкретный код: **AS-IS `NOT_FOUND "Project not-a-prj-slug not found"`**; **[PHASE-0-GATED]** target по conv-11 peer-validate-lane → `FAILED_PRECONDITION` (см. F8 — единая полоса для projectId/zoneId/regionId)
**And** различие полос: `networkId` (within-service direct-read) → `NOT_FOUND` (VPC-1-41, ungated); scope-coord `projectId`/`zoneId`/`regionId` (cross-service peer-validate) → by-lane target `FAILED_PRECONDITION` (gated)

---

## F2 — Network declared супернет `ipv4CidrBlocks[]`/`ipv6CidrBlocks[]`

> `→ module-vpc` §Network, §Правила 11/14 · `→ unified §2 vpc`
> **AS-IS (behavior-change, net-new поле):** текущий `Network`-message **не несёт** супернет-полей
> (`network.proto` — только `id/projectId/createdAt/name/description/labels/defaultSecurityGroupId`);
> DB-таблица `networks` **не имеет** cidr-колонок. Network сейчас — «список подсетей» без объявленного
> адресного пространства. VPC-1 добавляет `ipv4_cidr_blocks text[]` / `ipv6_cidr_blocks text[]` (новая
> миграция) и одноимённые proto-поля. Роль поля: **declared супернет** (у Network НЕТ `*CidrPrimary`
> — только набор супернет-блоков; НЕ путать с одноимённым `ipv4CidrBlocks[]` Subnet = «доп. диапазоны
> сверх primary», module-vpc §Subnet CIDR-роль).

### Сценарий VPC-1-06: Create Network с супернетом → блоки эхаются на read

**ID:** VPC-1-06

**Given** проект `prj-b3n7k1x9q2m5t8` существует (peer-validate iam ok); вызывающий — editor проекта

**When** `NetworkService.Create` (`POST /vpc/v1/networks`) с payload:
  - `projectId` = `"prj-b3n7k1x9q2m5t8"`
  - `name` = `"core-prod"`
  - `ipv4CidrBlocks` = `["10.20.0.0/16"]`
  - `ipv6CidrBlocks` = `["fd00:20::/48"]`

**Then** `Operation{done:true}`; `result.response` анмаршалится в public `Network` с `ipv4CidrBlocks == ["10.20.0.0/16"]`, `ipv6CidrBlocks == ["fd00:20::/48"]`, заполненными `id` (`net-…`), `createdAt°`
**And** последующий `NetworkService.Get` возвращает те же супернет-блоки

### Сценарий VPC-1-07 (negative): супернет-блок в `Update.updateMask` → immutable-reject

**ID:** VPC-1-07

**Given** сеть `net-v8f3k2q9m4t1n7` создана с `ipv4CidrBlocks=["10.20.0.0/16"]`

**When** `NetworkService.Update` (`PATCH /vpc/v1/networks/net-v8f3k2q9m4t1n7`) с `updateMask=["ipv4CidrBlocks"]`, `ipv4CidrBlocks=["10.30.0.0/16"]`

**Then** **синхронный** `INVALID_ARGUMENT "ipv4CidrBlocks is immutable after Network.Create"` (immutable-switch срабатывает **до** `corevalidate.UpdateMask`; супернет мутируется **только** через verb-pair, не через generic Update)

### Сценарий VPC-1-08: `:add-cidr-blocks` расширяет супернет; `:remove-cidr-blocks` сужает

**ID:** VPC-1-08

**Given** сеть `net-v8f3k2q9m4t1n7` с `ipv4CidrBlocks=["10.20.0.0/16"]`

**When** `NetworkService.AddCidrBlocks` (`POST /vpc/v1/networks/net-v8f3k2q9m4t1n7:add-cidr-blocks`) с `ipv4CidrBlocks=["10.30.0.0/16"]`

**Then** `Operation{done:true}`; `result.response.ipv4CidrBlocks` содержит оба блока `["10.20.0.0/16","10.30.0.0/16"]` (op-in-response)

**When** затем `NetworkService.RemoveCidrBlocks` (`:remove-cidr-blocks`) с `ipv4CidrBlocks=["10.30.0.0/16"]`

**Then** `Operation{done:true}`; `result.response.ipv4CidrBlocks == ["10.20.0.0/16"]`

### Сценарий VPC-1-09 (negative): malformed CIDR в супернете → `INVALID_ARGUMENT`

**ID:** VPC-1-09

**When** `NetworkService.Create` с `ipv4CidrBlocks=["10.20.0.0/33"]` (невалидная маска)

**Then** **синхронный** `INVALID_ARGUMENT` с текстом, называющим невалидный CIDR — format-валидация ДО создания Operation

> **AS-IS тон (behavior-change, deliverable):** текущий CIDR-валидатор отдаёт `"Illegal argument Invalid
> network prefix /<N>"` (`subnet/helpers.go:52`, legacy-тон); редизайн-цель — конвенционный
> `"invalid CIDR block '<X>'"` (module-vpc §Правила 13 единый тон). Implementer правит текст.

### Сценарий VPC-1-10 (edge): `:remove-cidr-blocks` последнего блока, покрывающего живую подсеть → `FAILED_PRECONDITION`

**ID:** VPC-1-10

**Given** сеть `net-v8f3k2q9m4t1n7` с `ipv4CidrBlocks=["10.20.0.0/16"]` и подсетью `sub-…` с `ipv4CidrPrimary=10.20.0.0/24` (⊆ этого блока)

**When** `NetworkService.RemoveCidrBlocks` с `ipv4CidrBlocks=["10.20.0.0/16"]` (единственный блок, из которого нарезана живая подсеть)

**Then** `Operation{done:true}` c `result.error` `FAILED_PRECONDITION "network CIDR block 10.20.0.0/16 still contains subnets"` — нельзя удалить супернет-блок, покрывающий существующую подсеть (иначе её `ipv4CidrPrimary` осиротеет вне супернета)

---

## F3 — System-provisioned default-SG + default-RT (безусловно); default-SG egress-политика

> `→ module-vpc` §Network (defaults), §Ментальная модель Recipe A · `→ unified §1 conv-4`
> **AS-IS (behavior-change):** (1) default-SG создаётся **условно** — env `KACHO_VPC_DEFAULT_SG_INLINE`
> / `CreateNetworkRequest.create_default_security_group` (optional bool, `network/create.go:44,217`);
> редизайн делает его **безусловным**. (2) **default-RT вообще не создаётся** — `networks`-таблица
> не имеет `default_route_table_id` (net-new колонка + net-new провижн default-RT в той же writer-TX).
> (3) Текущий default-SG **УЖЕ несёт ДВА правила: INGRESS ANY 0.0.0.0/0 И EGRESS ANY 0.0.0.0/0**
> (`security_group_builders.go:30-31` возвращает оба, wide-open обе стороны). Значит **egress-allow
> 0.0.0.0/0 — AS-IS present** (VPC-1-12 лочит его наличие, тривиально зелёный). Реальное изменение
> редизайна — **сужение INGRESS-ANY-0.0.0.0/0 → intra-network allow + established/related** (deny
> внешнего ingress) — и оно отнесено к **VPC-2** (SG rules verb-pair/OCC). VPC-1 фиксирует **факт
> создания** default-SG/RT, эхо их id и **наличие egress-allow 0.0.0.0/0** (Recipe-A предпосылка).
> **Дефолт (предложение к reviewer):** re-point дефолтов (`SetDefaultSecurityGroup`/`SetDefaultRouteTable`)
> вынесен в VPC-2 (цель re-point — tenant-созданная SG/RT, которых до VPC-2 нет). VPC-1 покрывает только
> **system-created** дефолты.

### Сценарий VPC-1-11: Network.Create безусловно создаёт default-SG и default-RT, id эхаются в response

**ID:** VPC-1-11

**Given** проект `prj-b3n7k1x9q2m5t8` существует; вызывающий — editor; **никакой** флаг/env опт-аута не задан

**When** `NetworkService.Create` (`POST /vpc/v1/networks`) с `projectId`, `name="core-prod"`, `ipv4CidrBlocks=["10.20.0.0/16"]`

**Then** `Operation{done:true}`; `result.response` (public `Network`) несёт **непустые** `defaultSecurityGroupId°` (`scg-…`/AS-IS `sgr-…`) **и** `defaultRouteTableId°` (`rtb-…`) — оба system-created в **той же** writer-TX, что и Insert(Network) (atomic; orphan-окна нет)
**And** `NetworkService.Get` показывает те же `defaultSecurityGroupId°`/`defaultRouteTableId°`

### Сценарий VPC-1-12: default-SG несёт stateful initiating egress 0.0.0.0/0

**ID:** VPC-1-12

**Given** сеть `net-…` создана как в VPC-1-11; `defaultSecurityGroupId° = "scg-0d3f7k1t9m2q5v"`

**When** клиент читает default-SG (через `SecurityGroupService.Get` — read-path SG существует AS-IS; полная SG-мутация — VPC-2)

**Then** default-SG несёт egress-правило `{direction:EGRESS, protocol:ANY, cidrBlocks:["0.0.0.0/0"]}` — свежий исходящий пакет к интернету проходит (иначе NAT+route были бы «немыми», Recipe A)
**And** описание/имя маркируют его system-created дефолтом (формула `default-sg-<short>`); детальная intra-network ingress-политика проверяется в VPC-2 (SG rules)

> Примечание scope: VPC-1 локает **наличие** egress-allow (Recipe-A предпосылка) + факт system-provision;
> сужение INGRESS 0.0.0.0/0 → intra-network + verb-pair мутация правил — VPC-2. `→ module-vpc` §Network default-SG-policy.

### Сценарий VPC-1-13 (edge): default-SG/RT — atomic single-provision (orphan-absence + partial-UNIQUE existence)

**ID:** VPC-1-13

> Это **не** concurrent-race (две Create с разными `name` → разные `network_id` → ноль contention на
> per-network partial-UNIQUE `security_groups_one_default_per_network (network_id) WHERE default_for_network`,
> `0005:26-27`). Локается **атомарность single-provision** + отсутствие orphan.

**Given** DB несёт `security_groups_one_default_per_network` partial-UNIQUE (`0005_default_sg_fk_and_unique`) — AS-IS SG; **аналогичный single-default-RT-на-сеть — net-new** (AS-IS RT partial-UNIQUE нет → источник уникальности: DB-constraint ЛИБО single-atomic-provision в writer-TX Create — implementer выбирает, db-reviewer сверяет)

**When** (integration) Network.Create коммитится

**Then** сеть получает **ровно один** default-SG и **ровно один** default-RT — оба в **той же** writer-TX, что Insert(Network); при crash между шагами (Abort) — ни Network, ни orphan-SG/RT (all-or-nothing); partial-UNIQUE `WHERE default_for_network` — backstop против двух дефолтов на сеть

---

## F4 — Network op-in-response (statusless) + happy CRUD

> `→ module-vpc` §Network, §Правила 2 · `→ unified §1 conv-2, §3`
> **AS-IS (behavior-change):** сейчас `Network.Create` — **async-poll**: `operations.Run(...)` запускает
> worker в фоне и возвращает `&op` с `done:false` **сразу** (`network/create.go:137,164`); клиент поллит.
> Редизайн: Network — statusless (durable-immediately) → **op-in-response**: `Operation` приходит
> `done:true` уже в ответе Create, и `Operation.response` (Any) несёт **полное** созданное тело со
> всеми derived `°` (incl. `defaultSecurityGroupId°`/`defaultRouteTableId°`). Implementer обязан
> завершать worker-fn **синхронно** до возврата (config-INSERT-класс, без саги) и класть полное тело в
> `.response`. Statusless = *durable, readiness НЕ наблюдается* — **никакого `status`-поля** на Network.

### Сценарий VPC-1-14: happy Create — done:true немедленно, unwrap .response, id в metadata сразу

**ID:** VPC-1-14

**Given** проект существует; вызывающий — editor

**When** `NetworkService.Create` с `projectId`, `name="core-prod"`, `ipv4CidrBlocks=["10.20.0.0/16"]`

**Then** **в том же** ответе `Operation.done == true` (statusless, durable-immediately)
**And** `Operation.metadata` анмаршалится в `CreateNetworkMetadata{networkId:"net-…"}` (id доступен сразу, до/без polling)
**And** `Operation.result` — `response` (не `error`); анмаршал даёт **полное** тело public `Network` (`id`, `projectId`, `name`, `ipv4CidrBlocks`, `defaultSecurityGroupId°`, `defaultRouteTableId°`, `createdAt°` усечён до секунд)
**And** повторный `OperationService.Get(op.id)` (`GET /vpc/v1/operations/{id}`) возвращает тот же `done:true` (поллить не требуется)

### Сценарий VPC-1-15: happy Update (LIVE-mutable name/description/labels) → op-in-response

**ID:** VPC-1-15

**Given** сеть `net-…` с `name="core-prod"`, `labels={}`

**When** `NetworkService.Update` (`PATCH /vpc/v1/networks/net-…`) с `updateMask=["description","labels"]`, `description="Primary prod VPC"`, `labels={"env":"prod"}`

**Then** `Operation{done:true}`; `result.response.description == "Primary prod VPC"`, `labels == {"env":"prod"}` (op-in-response); `name`/`ipv4CidrBlocks`/`defaultSecurityGroupId°` не изменены

### Сценарий VPC-1-16 (negative): public Network НЕ несёт `vrfId`/underlay (two-projection field-absence)

**ID:** VPC-1-16

**Given** сеть `net-…` существует (внутренне несёт `route_distinguisher` — AS-IS baseline `0001_initial.sql:196` — и `vrf_id` — AS-IS `0007_network_vrf_id`)

**When** `NetworkService.Get`/`List` на публичном листенере

**Then** сериализованное тело public `Network` **не содержит** `vrfId`, `routeDistinguisher`, underlay-полей (инфра-чувствительное — только `InternalNetworkService.GetNetwork` :9091, conv-8); assert field-absence

### Сценарий VPC-1-17 (negative): пустой `updateMask` → full-PATCH mutable; immutable из тела silently игнорируются

**ID:** VPC-1-17

**Given** сеть `net-…` с `name="core-prod"`, `projectId="prj-b3n7k1x9q2m5t8"`

**When** `NetworkService.Update` с **пустым** `updateMask` и телом, где `description="x"`, `projectId="prj-other"` (immutable в теле)

**Then** `Operation{done:true}`; `description` применён (full-PATCH mutable); `projectId` **не** изменён (immutable из тела silently игнорируется при пустом mask — module-vpc §Правила 11)

---

## F5 — Network Delete-non-empty; projectId immutable; name UNIQUE → ALREADY_EXISTS

> `→ module-vpc` §Network, §Правила 12/13 · `→ unified §5 инв-6`
> **AS-IS:** `UNIQUE(project_id, name)` **уже** есть (`networks_project_id_name_key`,
> `0001_initial.sql:206`) — **безусловный** (без `WHERE name<>''`, в отличие от subnets/route_tables
> partial-index; если редизайн допускает пустые Network-имена, отметить асимметрию — на VPC-1-21/22 не
> влияет). Network.Create дополнительно делает sync software-precheck по name (`network/create.go:104-118`,
> fast-fail) + DB-UNIQUE backstop. `projectId` — **Move снят целиком** (contract-removal), immutable.
> Subnet FK `network_id → networks(id)` (RESTRICT-подобный: base FK без ON DELETE cascade) — Delete
> непустой сети упирается в FK.

### Сценарий VPC-1-18: Delete непустой сети → FAILED_PRECONDITION "network is not empty"

**ID:** VPC-1-18

**Given** сеть `net-v8f3k2q9m4t1n7` с ≥1 подсетью (`sub-…`)

**When** `NetworkService.Delete` (`DELETE /vpc/v1/networks/net-v8f3k2q9m4t1n7`)

**Then** `Operation{done:true}` c `result.error` `FAILED_PRECONDITION "network is not empty"` (within-service FK через Subnet/SG/RT/Gateway — DB-backstop, ban #10; НЕ software-precheck)

### Сценарий VPC-1-19: Delete пустой сети → успех; default-SG/RT снимаются вместе

**ID:** VPC-1-19

**Given** сеть `net-…` без подсетей/SG/RT кроме своих system-created дефолтов

**When** `NetworkService.Delete`

**Then** `Operation{done:true}` c `result.response` (Empty); последующий `NetworkService.Get` → `NOT_FOUND "Network net-… not found"`; system default-SG/default-RT сети сняты вместе (не оставляют dangling FK)

### Сценарий VPC-1-20 (negative): projectId в updateMask → immutable-reject

**ID:** VPC-1-20

**Given** сеть `net-…` с `projectId="prj-b3n7k1x9q2m5t8"`

**When** `NetworkService.Update` с `updateMask=["projectId"]`, `projectId="prj-other"`

**Then** **синхронный** `INVALID_ARGUMENT "projectId is immutable after Network.Create"` (immutable-switch до `corevalidate.UpdateMask`; Move снят целиком)

### Сценарий VPC-1-21 (negative): duplicate name в проекте → ALREADY_EXISTS

**ID:** VPC-1-21

**Given** сеть с `name="core-prod"` уже существует в `prj-b3n7k1x9q2m5t8`

**When** `NetworkService.Create` с тем же `projectId` и `name="core-prod"`

**Then** отказ `ALREADY_EXISTS` (UNIQUE(project,name), строго `ALREADY_EXISTS` — никакой развилки «по контексту»); текст `"Network with name core-prod already exists"`

### Сценарий VPC-1-22 (concurrent-race): две конкурентные Create одинакового name → ровно одна проходит

**ID:** VPC-1-22

**Given** (integration, testcontainers) две горутины одновременно вызывают Network.Create c одинаковыми `projectId`+`name="core-prod"`

**When** обе доезжают до Insert (software-precheck может пропустить обе — TOCTOU)

**Then** **ровно одна** транзакция коммитится; вторая ловит UNIQUE(project,name) 23505 → `ALREADY_EXISTS` (DB-backstop authoritative под concurrency, не software-precheck); ноль дублей в таблице

---

## F6 — Subnet единственный placement-anchor; `placementType°` derived (unwritable)

> `→ module-vpc` §Subnet, §Правила 5/11 · `→ unified §2 vpc, §5 инв-2`
> **AS-IS (behavior-change, write-контракт):** `CreateSubnetRequest.placement_type` — сейчас
> **writable, required** enum (`subnet_service.proto` field 13; `subnet.proto` field 15;
> UNSPECIFIED → InvalidArgument, консистентность zone/region энфорсится в хендлере). Редизайн делает
> `placementType°` **server-derived, read-only, unwritable, голый токен** на read (чистый
> derived-дискриминатор — НЕ оборачивается в `{value,displayName}`). На write клиент шлёт **ровно
> один** из `zoneId`/`regionId`; сам `placementType` в теле write → **explicit reject** (не silent).
> DB-CHECK `subnets_placement_payload_chk` (биусловие `ZONAL⟺zone_id≠''∧region_id='' / REGIONAL⟺…`)
> — **AS-IS present** (`0012_subnet_placement.sql`); меняется только API-write-слой (server выводит
> `placement_type`-колонку из непустого zoneId/regionId, клиент её не задаёт).

### Сценарий VPC-1-23: Create ZONAL subnet — placementType° выводится в "ZONAL" (голый токен на read)

**ID:** VPC-1-23

**Given** сеть `net-…` с супернетом `["10.20.0.0/16"]`; зона `ru-central1-a` существует (peer-validate geo ok)

**When** `SubnetService.Create` (`POST /vpc/v1/subnets`) с payload (**без** `placementType`):
  - `projectId` = `"prj-b3n7k1x9q2m5t8"`
  - `networkId` = `"net-v8f3k2q9m4t1n7"`
  - `name` = `"app-tier-a"`
  - `zoneId` = `"ru-central1-a"`
  - `ipv4CidrPrimary` = `"10.20.0.0/24"`

**Then** `Operation{done:true}`; `result.response.placementType° == "ZONAL"` (**голый токен**, не `{value,displayName}`) — server-derived из непустого `zoneId`; `regionId° == ""`
**And** `zoneId° == "ru-central1-a"`; on-read placementType неизменно ZONAL

### Сценарий VPC-1-24: Create REGIONAL subnet — placementType° выводится в "REGIONAL"

**ID:** VPC-1-24

**Given** сеть `net-…`; регион `ru-central1` существует (peer-validate geo ok)

**When** `SubnetService.Create` с `regionId="ru-central1"`, `ipv4CidrPrimary="10.99.0.0/24"` (**без** `zoneId`, **без** `placementType`)

**Then** `Operation{done:true}`; `result.response.placementType° == "REGIONAL"` (голый токен); `zoneId° == ""`; `regionId° == "ru-central1"` — anycast, из зональной coherence-проверки исключён by construction

### Сценарий VPC-1-25 (negative): оба zoneId+regionId заданы → explicit reject (spoken)

**ID:** VPC-1-25

**When** `SubnetService.Create` с **обоими** `zoneId="ru-central1-a"` и `regionId="ru-central1"`

**Then** **синхронный** `INVALID_ARGUMENT "exactly one of zoneId, regionId must be set"` (spoken, не немой DB-CHECK-отказ; format-validate до Operation)

### Сценарий VPC-1-26 (negative): ни zoneId ни regionId → explicit reject

**ID:** VPC-1-26

**When** `SubnetService.Create` с **пустыми** `zoneId` и `regionId`

**Then** **синхронный** `INVALID_ARGUMENT "exactly one of zoneId, regionId must be set"`

### Сценарий VPC-1-27 (negative): `placementType` в теле write → explicit reject (не silent-ignore)

**ID:** VPC-1-27

**When** `SubnetService.Create` с `zoneId="ru-central1-a"`, `ipv4CidrPrimary="10.20.0.0/24"` **и** явно заданным `placementType="ZONAL"` в теле

**Then** **синхронный** `INVALID_ARGUMENT "placementType is server-derived; set zoneId or regionId instead"` — **не** silent-ignore (silent наименее предсказуем для «set-the-type» новичка); reject даже когда значение «совпало бы» с derived

### Сценарий VPC-1-28 (negative): placementType/zoneId/regionId immutable в Update

**ID:** VPC-1-28

**Given** subnet `sub-t4k8n2q0m5v9h1` ZONAL в `ru-central1-a`

**When** `SubnetService.Update` с `updateMask=["zoneId"]`, `zoneId="ru-central1-b"`

**Then** **синхронный** `INVALID_ARGUMENT "zoneId is immutable after Subnet.Create"` (перенос подсети между зонами сломал бы coherence всех размещённых ресурсов); то же для `updateMask=["placementType"]` → `"placementType is server-derived; set zoneId or regionId instead"` и `updateMask=["regionId"]`/`["ipv4CidrPrimary"]` → immutable-reject

---

## F7 — Subnet CIDR: ipv4CidrPrimary anchor ⊆ супернет + no-overlap

> `→ module-vpc` §Subnet (CIDR-роль), §Правила 12/13 · `→ unified §5 инв-6`
> **AS-IS (behavior-change):** сейчас Subnet несёт `v4_cidr_blocks[]`/`v6_cidr_blocks[]` (repeated),
> DB-primary — generated `v4_cidr_primary = blocks[1]` (`0001_initial.sql`). Редизайн вводит
> **explicit** `ipv4CidrPrimary`/`ipv6CidrPrimary` (single immutable placement-anchor) **+**
> `ipv4CidrBlocks[]`/`ipv6CidrBlocks[]` (доп. диапазоны через `:add-cidr-blocks`). Именование
> `v4_…` → `ipv4…` — унификация всего модуля (module-vpc §Правила 14, дрейф устранён).
> **Net-new:** `ipv4CidrPrimary` обязан быть **подмножеством одного** из `network.ipv4CidrBlocks`
> супернет-блоков — **AS-IS такой проверки нет** (Network не имел супернета). Валидируется в
> writer-TX против network-строки (в той же БД). No-overlap: EXCLUDE gist `subnets_no_overlap_v4/v6`
> + child `subnet_cidr_blocks_no_overlap` (per-network) — **AS-IS present**, 23P01 → `FailedPrecondition`
> (`iface_address_pool.go` использует тот же паттерн). Редизайн-текст: `"subnet CIDRs can not overlap"`.

### Сценарий VPC-1-29: happy — ipv4CidrPrimary ⊆ супернет-блока принимается

**ID:** VPC-1-29

**Given** сеть `net-…` с супернетом `ipv4CidrBlocks=["10.20.0.0/16"]`

**When** `SubnetService.Create` с `zoneId="ru-central1-a"`, `ipv4CidrPrimary="10.20.0.0/24"` (⊆ `10.20.0.0/16`)

**Then** `Operation{done:true}`; `result.response.ipv4CidrPrimary == "10.20.0.0/24"`, `ipv4CidrBlocks° == []` (доп. диапазонов пока нет)

### Сценарий VPC-1-30 (negative): ipv4CidrPrimary ∉ ни одного супернет-блока → INVALID_ARGUMENT

**ID:** VPC-1-30

**Given** сеть `net-…` с супернетом `["10.20.0.0/16"]`

**When** `SubnetService.Create` с `zoneId="ru-central1-a"`, `ipv4CidrPrimary="192.168.0.0/24"` (вне супернета)

**Then** `Operation{done:true}` c `result.error` `INVALID_ARGUMENT "subnet CIDR 192.168.0.0/24 is not within any network CIDR block"` (net-new: валидация против network-супернета в writer-TX)

### Сценарий VPC-1-31 (negative): overlapping subnet CIDR в той же сети → FAILED_PRECONDITION

**ID:** VPC-1-31

**Given** сеть `net-…` (супернет `["10.20.0.0/16"]`) с подсетью `sub-A` `ipv4CidrPrimary=10.20.0.0/24`

**When** `SubnetService.Create` подсети `sub-B` с `ipv4CidrPrimary="10.20.0.0/25"` (пересекается с `10.20.0.0/24`)

**Then** `Operation{done:true}` c `result.error` `FAILED_PRECONDITION "subnet CIDRs can not overlap"` (EXCLUDE gist 23P01 → `FailedPrecondition`; **не** `ALREADY_EXISTS` — тот строго для UNIQUE(name))

> **AS-IS тон (behavior-change, deliverable):** текущий текст — `"Subnet CIDRs can not overlap"` (заглавная
> S, `subnet/create.go:282`, `helpers.go:112`); редизайн-цель — lowercase `"subnet CIDRs can not overlap"`
> (module-vpc §Правила 13). Код (`FAILED_PRECONDITION`) уже AS-IS верен; правится только регистр текста.

### Сценарий VPC-1-32 (edge): подсети РАЗНЫХ сетей могут иметь одинаковый CIDR (per-network изоляция)

**ID:** VPC-1-32

**Given** сети `net-A` и `net-B` (обе с супернетом `["10.20.0.0/16"]`)

**When** в каждой создаётся подсеть с `ipv4CidrPrimary="10.20.0.0/24"`

**Then** обе `Operation{done:true}` успешно — EXCLUDE scope = `network_id` (изоляция per-network VRF); пересечение отвергается **только** внутри одной сети

### Сценарий VPC-1-33 (concurrent-race): две конкурентные Create overlapping CIDR → ровно одна проходит

**ID:** VPC-1-33

**Given** (integration, testcontainers, concurrent goroutines) сеть `net-…`; две горутины одновременно создают подсети с пересекающимися `ipv4CidrPrimary` (`10.20.0.0/24` и `10.20.0.128/25`)

**When** обе доезжают до Insert

**Then** **ровно одна** коммитится; вторая ловит EXCLUDE gist 23P01 → `FAILED_PRECONDITION "subnet CIDRs can not overlap"` (declarative race-free by construction, ban #10 — не software check-then-act); ноль двойного IPAM-выделения

### Сценарий VPC-1-34: `:add-cidr-blocks` добавляет доп. диапазон ⊆ супернет

**ID:** VPC-1-34

**Given** подсеть `sub-…` c `ipv4CidrPrimary=10.20.0.0/24`; сеть-супернет `["10.20.0.0/16"]`

**When** `SubnetService.AddCidrBlocks` (`POST /vpc/v1/subnets/sub-…:add-cidr-blocks`) с `ipv4CidrBlocks=["10.20.8.0/24"]` (⊆ супернет, не пересекается)

**Then** `Operation{done:true}`; `result.response.ipv4CidrBlocks° == ["10.20.8.0/24"]`; `ipv4CidrPrimary` (immutable anchor) не изменён
**And** добавление диапазона вне супернета → `INVALID_ARGUMENT "subnet CIDR … is not within any network CIDR block"`; пересекающегося → `FAILED_PRECONDITION "subnet CIDRs can not overlap"`

---

## F7a — вложенность из F7 безусловна: сеть без объявленного супернета семейства не принимает подсеть этого семейства

> `→ module-vpc` §Subnet (CIDR-роль), §Network (declared супернет) · `→ unified §5 инв-6`
>
> **Отношение к F7 — чтобы обе формы ссылки читались однозначно.** F7 говорит, ЧТО обязано быть
> верно про принятую подсеть: её CIDR лежит внутри одного из объявленных блоков сети. F7a
> отвечает на вопрос, который F7 оставлял открытым: что происходит, когда объявленных блоков
> нет. Ответ — ограничение действует **безусловно** и не пропускается ни при каком состоянии
> сети. Ссылки на `F7` продолжают означать вложенность и непересечение; F7a ничего в них не
> переопределяет и ничего у них не отнимает.
>
> **Почему отказ, а не приём.** Супернет **опционален** на `Network.Create` (F2), поэтому сеть
> без объявленного адресного плана — не редкий край, а штатное состояние целого класса сетей.
> Пока проверка на пустом наборе блоков пропускалась, контракт заявлял вложенность безусловно,
> а на этом классе она не значила ничего: два места об одном предмете, из которых верно одно.
> Ослабить текст контракта было нельзя, потому что нарезать не из чего: без объявленного блока
> подсеть перестаёт быть частью чего-либо и остаётся произвольным диапазоном, у которого с
> соседями по сети нет отношения, кроме непересечения. Именно ради этого отношения супернет и
> объявляется.
>
> **Отказ обучающий, а не тупиковый: путь вперёд назван в самом его тексте** — `:add-cidr-blocks`,
> тот же глагол, которым супернет растят (F2/VPC-1-08). Тенанту не нужно ни пересоздавать сеть,
> ни угадывать, чего не хватило.
>
> **Где стоит проверка.** Дважды, одним и тем же предикатом: синхронно **до** `Operation` — по
> строке сети, прочитанной в том же Reader-TX; и backstop'ом в writer-TX — по актуальной строке
> под share-lock'ом, потому что супернет мог измениться между чтением и вставкой. Тон один,
> доставка разная: sync-путь отвечает немедленно, backstop кладёт отказ в `result.error` уже
> созданной `Operation`.
>
> **Уровни проверки (обязательство DoD, названное прямо, чтобы не осталось непроверяемых
> сценариев).** VPC-1-47/48/49 наблюдаемы через api-gateway и обязаны нести newman-кейс;
> VPC-1-50 и VPC-1-51 через публичную поверхность **не конструируются** (см. их «And») и
> закрепляются пробами уровня use-case и integration соответственно.

### Сценарий VPC-1-47 (negative): сеть без объявленного супернета семейства → sync INVALID_ARGUMENT

**ID:** VPC-1-47

**Given** сеть `net-…` создана **без** `ipv4CidrBlocks` и `ipv6CidrBlocks` (оба поля опциональны на `Network.Create`, F2) — у сети нет объявленного адресного плана ни одного семейства

**When** `SubnetService.Create` с `zoneId="ru-central1-a"`, `ipv4CidrPrimary="10.77.7.0/24"`

**Then** **синхронный** `INVALID_ARGUMENT "network declares no IPv4 supernet: add blocks via :add-cidr-blocks (ipv4CidrBlocks) before creating an IPv4 subnet"` — отказ приходит **до** создания `Operation` (отвергнут ввод, а не состояние уже начатой мутации)

**And** пара, которую утверждает кейс: на крае HTTP **400** (`api-conventions.md` §«gRPC-код → HTTP-статус»: `INVALID_ARGUMENT` → 400) **и** `code` в `google.rpc.Status` — `INVALID_ARGUMENT`. Один без другого не утверждается: только HTTP не отличил бы валидацию от состояния ресурса, только код не заметил бы смены отображения на крае

**And** текст называет **семейство** (`IPv4`) и **имя поля** (`ipv4CidrBlocks`) — иначе непонятно, какие блоки объявлять; v6-зеркало: сеть без `ipv6CidrBlocks` на v6-подсеть отвечает тем же с `IPv6`/`ipv6CidrBlocks`

### Сценарий VPC-1-48 (edge, положительный контроль): отсутствие супернета ЧУЖОГО семейства подсети не касается

**ID:** VPC-1-48

**Given** сеть `net-…` объявила **только** `ipv4CidrBlocks=["10.20.0.0/16"]`; `ipv6CidrBlocks` пуст

**When** `SubnetService.Create` с `zoneId="ru-central1-a"`, `ipv4CidrPrimary="10.20.0.0/24"` (v6 не запрашивается вовсе)

**Then** `Operation{done:true}`, подсеть создана — пустой v6-план к запросу отношения не имеет, и отказ был бы про то, чего не просили

**And** зеркало: сеть, объявившая только `ipv6CidrBlocks`, принимает v6-only подсеть (VPC-1-46) при пустом v4-плане

**And** этот сценарий — **обязательный** положительный контроль рядом с VPC-1-47: без него «отказ» зеленел бы и на реализации, отвергающей любую подсеть по любой причине. Отрицание засчитывается только в паре с положительным

### Сценарий VPC-1-49: путь вперёд — объявить блоки тем глаголом, который назван в отказе

**ID:** VPC-1-49

**Given** сеть `net-…` и подсеть из VPC-1-47 — та же самая, только что отвергнутая

**When** `NetworkService.AddCidrBlocks` (`POST /vpc/v1/networks/net-…:add-cidr-blocks`) с `ipv4CidrBlocks=["10.77.0.0/16"]`, затем **повтор того же** `SubnetService.Create` с `ipv4CidrPrimary="10.77.7.0/24"`

**Then** `Operation{done:true}`; подсеть создана; `ipv4CidrPrimary` тот же, что был отвергнут минуту назад — отказ снимается ровно тем действием, которое он назвал, и ничем сверх него (ни пересозданием сети, ни сменой CIDR подсети)

**And** оба шага живут в **одном** e2e-кейсе: отказ и снятие отказа проверяются на одной и той же подсети, иначе «путь вперёд» остаётся утверждением документа, а не свойством продукта

### Сценарий VPC-1-50 (edge): объявленные блоки есть, но ни один из них не читается

**ID:** VPC-1-50

**Given** строка сети несёт **непустой** `ipv4CidrBlocks`, ни один элемент которого не разбирается в префикс

**When** `SubnetService.Create` с `ipv4CidrPrimary="10.77.7.0/24"`

**Then** отказ контрактным тоном F7 — `INVALID_ARGUMENT "subnet CIDR 10.77.7.0/24 is not within any network CIDR block"`. Проверка **не отвечает «да»** оттого, что сравнивать оказалось не с чем: пустой разобранный набор — то же отсутствие плана, что и пустой объявленный

**And** разница между «план не объявлен» и «план объявлен нечитаемым» касается того, **кто это чинит**, а не того, можно ли из этого нарезать: и там и там у сети нет адресного плана

**And** **уровень проверки, названный честно:** через публичную поверхность это состояние не построить — формат супернет-блоков валидируется на `Network.Create` и на `:add-cidr-blocks` (VPC-1-09), поэтому newman-кейса у сценария нет и быть не может; он закрепляется пробой уровня use-case. Требование от этого не слабее: ветка обязана отвергать, иначе первый же путь, приносящий блоки мимо этой валидации (восстановление из резервной копии, импорт, правка строки в обход API), вернёт молчаливый приём — и вернёт его невидимо, потому что снаружи такой сети не отличить от исправной

### Сценарий VPC-1-51 (concurrent-race): супернет опустошён между sync-проверкой и вставкой

**ID:** VPC-1-51

**Given** (integration, testcontainers, concurrent goroutines) сеть `net-…` с `ipv4CidrBlocks=["10.1.0.0/16"]`; конкурентный `NetworkService.RemoveCidrBlocks` снимает **последний** блок семейства. Его ∉-guard (VPC-1-10) защищает только **живые** подсети, а создаваемая ещё не закоммичена — окно двустороннее и реально

**When** `SubnetService.Create` с `ipv4CidrPrimary="10.1.5.0/24"` доезжает до writer-TX после коммита удаления

**Then** backstop под share-lock на строке сети перечитывает **актуальный** набор и отвергает: `Operation{done:true}` c `result.error` `INVALID_ARGUMENT "network declares no IPv4 supernet: …"`. Подсети вне адресного плана в БД не появляется — решение принимается по актуальной строке, а не по устаревшему снимку (ban #10, не software check-then-act)

**And** порядок блокировок единый — network → subnet (тот же, что у `Network.Delete`), поэтому инверсии с конкурентной мутацией супернета нет

**And** через api-gateway этот сценарий не воспроизводится (нужны две транзакции с управляемым перекрытием) — закрепляется integration-пробой под `-race`, детерминированно: writer держит лок, а не `time.Sleep`

---

## F8 — Subnet zone/region coherence (peer-validate geo); auto-associate default-RT; immutables

> `→ module-vpc` §Subnet, §Правила 4/5/11 · `→ unified §4 (vpc→geo), §5 инв-2`
> **AS-IS:** vpc→geo `ZoneService.Get`/`RegionService.Get` peer-validate — существующее runtime-ребро
> (`polyrepo.md`, `edges/apigw-to-vpc`). `zoneId`/`regionId` — scope-координаты (flat slug, geo-owned,
> **не** prefix-checked форматом — B4), существование валидируется peer-вызовом, fail-closed
> (`UNAVAILABLE` если geo down). **AS-IS absent-zone/region тон (heterogeneous):** отсутствующая зона →
> `InvalidArgument "unknown zone id '<X>'"` (`subnet/helpers.go:197`); отсутствующий регион →
> `InvalidArgument "unknown region id '<X>'"` (`helpers.go:221`). Это отличается от absent-project
> (`NOT_FOUND`, F1/VPC-1-05) — **AS-IS полосы peer-validate неоднородны по коду**; целевой by-lane
> conv-11 **унифицирует** все три (projectId/zoneId/regionId) peer-validate-absent → `FAILED_PRECONDITION`
> (**[PHASE-0-GATED]**). `subnets.route_table_id` — nullable FK → `route_tables(id)` ON DELETE SET NULL
> (`0001_initial.sql`).
> **AS-IS RT-auto-assoc (behavior-change — механизм СУЩЕСТВУЕТ):** DB несёт триггеры
> `rt_auto_assoc_subnets` (AFTER INSERT route_tables) + `subnet_auto_pick_rt` (BEFORE INSERT subnets),
> которые авто-заполняют `subnets.route_table_id` **самым ранним** RT сети (`0001_initial.sql:95-112,638-644`).
> Редизайн заменяет «earliest-RT» на **явный** `network.defaultRouteTableId°` (F3); implementer обязан
> **reconcile/удалить** старый trigger-выбор, не оставлять два конкурирующих механизма выбора RT.

### Сценарий VPC-1-35 `[PHASE-0-GATED]` (negative): несуществующий zoneId → peer-validate geo

**ID:** VPC-1-35

**Given** зона `ru-central1-z` НЕ существует в geo

**When** `SubnetService.Create` с `zoneId="ru-central1-z"`, `ipv4CidrPrimary="10.20.0.0/24"`

**Then** существование `zoneId` валидируется `geo.ZoneService.Get`; отсутствует → отказ с конкретным кодом:
**And** **AS-IS `INVALID_ARGUMENT "unknown zone id 'ru-central1-z'"`** (`subnet/helpers.go:197`); absent-region симметрично → `INVALID_ARGUMENT "unknown region id '<X>'"` (`helpers.go:221`)
**And** **[PHASE-0-GATED]** target по conv-11 (peer-validate-lane унификация projectId/zoneId/regionId) → `FAILED_PRECONDITION` + reason-token — приземляется после Phase-0 governance change-set; до merge остаётся AS-IS `INVALID_ARGUMENT`

> `[PHASE-0-GATED]`: код-унификация peer-validate-absent → `FAILED_PRECONDITION` приземляется **только**
> после Phase-0 by-lane-таблицы в `api-conventions.md`. До merge — AS-IS heterogeneous (project→`NOT_FOUND`,
> zone/region→`INVALID_ARGUMENT`). Merge-gate — §Definition of Done.

### Сценарий VPC-1-36 (edge, fail-closed): geo недоступен на Subnet.Create → UNAVAILABLE

**ID:** VPC-1-36

**Given** `geo.ZoneService.Get` недоступен (peer down)

**When** `SubnetService.Create` с валидным `zoneId="ru-central1-a"`

**Then** `Operation{done:true}` c `result.error` `UNAVAILABLE` (fail-closed для мутаций — owner недоступен, **никогда** allow); Subnet не создаётся (no phantom)

### Сценарий VPC-1-37: авто-ассоциация default-RT при Create (routeTableId не задан)

**ID:** VPC-1-37

**Given** сеть `net-…` с `defaultRouteTableId° = "rtb-9k3m7t2q5n8v1h"` (system-created, F3)

**When** `SubnetService.Create` с `zoneId="ru-central1-a"`, `ipv4CidrPrimary="10.20.0.0/24"` (**без** `routeTableId`)

**Then** `Operation{done:true}`; `result.response.routeTableId == "rtb-9k3m7t2q5n8v1h"` (auto = `network.defaultRouteTableId°` — **явный** default, заменяет AS-IS «earliest-RT» trigger `subnet_auto_pick_rt`); tenant override (`routeTableId=<dedicated>`) — VPC-2 (dedicated RT ещё нет)
**And** (integration) старый trigger-выбор не конкурирует: подсеть без явного `routeTableId` детерминированно получает `network.defaultRouteTableId°`, не «самый ранний RT» (implementer reconcile'ит trigger — F8 AS-IS)

### Сценарий VPC-1-38 (negative): networkId immutable в Update

**ID:** VPC-1-38

**Given** subnet `sub-…` в сети `net-v8f3k2q9m4t1n7`

**When** `SubnetService.Update` с `updateMask=["networkId"]`, `networkId="net-other"`

**Then** **синхронный** `INVALID_ARGUMENT "networkId is immutable after Subnet.Create"` (within-service FK immutable, VRF-scoping; immutable-switch до `UpdateMask`)

### Сценарий VPC-1-39: Subnet self-describing — derived `zoneId°`/`regionId°` читаемы консумером

**ID:** VPC-1-39

**Given** subnet `sub-…` ZONAL в `ru-central1-a`

**When** `SubnetService.Get`

**Then** тело несёт `zoneId° == "ru-central1-a"`, `regionId° == ""`, `placementType° == "ZONAL"` — self-describing, чтобы cross-service edge (compute Instance↔NIC same-zone) читал placement с owner-payload без double-hop (coherence-law enforced **at Subnet**, single point; консумеры наследуют)

---

## F9 — Subnet op-in-response; by-lane absent-network; malformed; DhcpOptions dropped

> `→ module-vpc` §Subnet, by-design omissions, §Правила 13 · `→ unified §1 conv-11 [reason-token PHASE-0-GATED]`
> **AS-IS:** Subnet.Create — тоже async-poll (как Network); редизайн → op-in-response (statusless).
> **absent-networkId — within-service direct-read lane, УЖЕ `NOT_FOUND` (не FK-`FAILED_PRECONDITION`):**
> `subnet/create.go` делает **pre-flight resolve** — reader-path `rd.Networks().Get` → при miss
> `status.Errorf(codes.NotFound, "Network %s not found", …)` (`create.go:133`), и повторно в writer-TX
> (`create.go:213`). FK 23503 на `subnets.network_id` — **только** create-race backstop (parent удалён
> между pre-flight и Insert). Значит target-`NOT_FOUND` для within-service absent-parent **уже landed
> ungated** — VPC-1-41 гейтит **только reason-token detail**, не сам код (в отличие от GEO-1-34, где
> AS-IS был FK-`FAILED_PRECONDITION`). **By-design omission (behavior-change):** `DhcpOptions`
> (`subnet.proto` field 13 + `dhcp_options` jsonb) **снят** — Network-level DHCP/DNS-resolver knobs
> отсутствуют by design (module-vpc §by-design omissions); implementer удаляет поле из write/read-
> контракта (breaking proto-change — см. §Definition of Done).

### Сценарий VPC-1-40: happy Subnet.Create → op-in-response с полным телом

**ID:** VPC-1-40

**When** `SubnetService.Create` с `projectId`, `networkId="net-…"`, `name="app-tier-a"`, `zoneId="ru-central1-a"`, `ipv4CidrPrimary="10.20.0.0/24"`

**Then** **в том же** ответе `Operation.done == true`; `metadata` → `CreateSubnetMetadata{subnetId:"sub-…"}` (id сразу); `result.response` — полный public `Subnet` (`id`, `networkId`, `placementType°="ZONAL"`, `zoneId°`, `ipv4CidrPrimary`, `routeTableId` auto, `createdAt°` усечён)

### Сценарий VPC-1-41 (negative): Subnet.Create с несуществующим networkId → NOT_FOUND (ungated)

**ID:** VPC-1-41

**Given** сеть `net-000000000000000` НЕ существует

**When** `SubnetService.Create` с `networkId="net-000000000000000"`, валидными zone/CIDR

**Then** `Operation{done:true}` c `result.error`: код `NOT_FOUND`, текст `"Network net-000000000000000 not found"` (within-service direct-read lane — pre-flight resolve `create.go:133/213`; **не** FK-`FAILED_PRECONDITION`) — **ungated, уже-landed** (в отличие от GEO-1-34)
**And** **[PHASE-0-GATED]** только detail `reason:"NETWORK_NOT_FOUND"` в `google.rpc.Status.details` — приземляется после Phase-0 reason-token таблицы; сам `NOT_FOUND`-код от гейта НЕ зависит
**And** FK 23503 на `subnets.network_id` остаётся DB-backstop для create-race (parent удалён между pre-flight resolve и Insert)

### Сценарий VPC-1-42 (negative): malformed subnet networkId → sync INVALID_ARGUMENT первым стейтментом

**ID:** VPC-1-42

**When** `SubnetService.Create` с `networkId="garbage!!"` (malformed)

**Then** **синхронный** `INVALID_ARGUMENT "invalid network id 'garbage!!'"` первым стейтментом (`corevalidate.ResourceID` до repo/peer-вызова; операция не создаётся)

### Сценарий VPC-1-43 (edge): DhcpOptions снят by design — поле отсутствует в write и read

**ID:** VPC-1-43

**Given** subnet `sub-…` существует

**When** `SubnetService.Get` / `SubnetService.Create` (любой запрос/ответ)

**Then** сериализованное тело **не содержит** `dhcpOptions`/`dhcp_options`, `domainNameServers`, `ntpServers` (Network-level DHCP/DNS-resolver knobs отсутствуют by design — module-vpc §by-design omissions); попытка задать `dhcpOptions` в Create-теле игнорируется/reject (unknown-field)

### Сценарий VPC-1-44 (negative): garbage page_token в List → INVALID_ARGUMENT ДО listauthz short-circuit

**ID:** VPC-1-44

**Given** аутентифицированный принципал

**When** `SubnetService.List` (`GET /vpc/v1/subnets?projectId=prj-…&pageToken=%%%not-base64%%%`)

**Then** `INVALID_ARGUMENT` — format-validate `pageToken`/`pageSize`/id **ДО** listauthz empty-grant short-circuit (иначе caller без грантов получил бы `200 {[]}` на garbage-token); `pageSize>1000` → `INVALID_ARGUMENT` (отвергается, не clamp'ится); то же для `NetworkService.List`

### Сценарий VPC-1-45: Subnet.List filter-whitelist `zoneId=`/`networkId=` (compute-integration)

**ID:** VPC-1-45

> **AS-IS (behavior-change):** текущий `SubnetService.List` filter — только `name=`. Редизайн расширяет
> whitelist до `name=`/`zoneId=`/`networkId=` (module-vpc §RPC-surface): compute-интегратор с инстансом
> в зоне X матчит существующую same-zone subnet **server-side**, без per-launch Get-and-eyeball. Net-new
> filter-поля.

**Given** проект с подсетями: `sub-A` (zoneId=`ru-central1-a`, net-X), `sub-B` (zoneId=`ru-central1-b`, net-X), `sub-C` (zoneId=`ru-central1-a`, net-Y)

**When** `SubnetService.List` (`GET /vpc/v1/subnets?projectId=prj-…&filter=zoneId="ru-central1-a"`)

**Then** массив содержит `sub-A`, `sub-C` (zoneId матч), не `sub-B`; `filter=networkId="net-X"` → `sub-A`,`sub-B`; unknown filter-поле → `INVALID_ARGUMENT` (whitelist); результат дополнительно фильтруется listauthz (только доступные caller'у)

### Сценарий VPC-1-46 (edge): v6-only subnet — ipv4CidrPrimary опционален

**ID:** VPC-1-46

> `→ module-vpc` §Subnet («subnet may be v6-only (ipv4CidrPrimary optional)»).

**Given** сеть `net-…` с супернетом `ipv6CidrBlocks=["fd00:20::/48"]` (v6), `ipv4CidrBlocks=[]`

**When** `SubnetService.Create` с `zoneId="ru-central1-a"`, `ipv6CidrPrimary="fd00:20::/64"` (**без** `ipv4CidrPrimary`)

**Then** `Operation{done:true}`; `result.response.ipv6CidrPrimary == "fd00:20::/64"`, `ipv4CidrPrimary° == ""` (v6-only легитимна); v6-CIDR ⊆ v6-супернета валидируется тем же правилом; v6-overlap → `FAILED_PRECONDITION "subnet CIDRs can not overlap"` (EXCLUDE per family)
**And** subnet **без** ни одного CIDR (ни v4 ни v6) → `INVALID_ARGUMENT` (хотя бы один primary обязателен)

---

## Definition of Done

VPC-1 готова к merge только при выполнении ВСЕГО чек-листа (`ai-tooling.md` §lifecycle gate 4-7;
`testing.md`):

**Traceability + тесты (1-to-1):**
- [ ] Каждый `VPC-1-NN` имеет зелёный **integration-тест** (testcontainers Postgres 16) —
  `Test<Resource>_VPC_1_NN` (напр. `TestSubnet_VPC_1_31`) — покрывающий SQL-сторону, включая
  CAS/UNIQUE/EXCLUDE. **Обязательные concurrent-race под `-race`, детерминированно (blocker держит слот,
  не `time.Sleep`): VPC-1-22** (UNIQUE(project,name) name-race) **и VPC-1-33** (EXCLUDE-gist CIDR-overlap
  race). VPC-1-13 — **не** race (atomicity/orphan-absence), гоняется как обычный integration.
- [ ] Каждый `VPC-1-NN` (наблюдаемый через api-gateway) имеет зелёный **newman-кейс**
  `tests/newman/cases/*.py` с аннотацией `# verifies VPC-1-NN` — ≥1 happy + ≥1 negative per фича;
  трассировка `VPC-1-NN ↔ Test<R>_VPC_1_NN ↔ cases/*.py`. Фикстур-ресурсы несут `{{runId}}`-суффикс
  (идемпотентность прогона); op-poll проверяет `!op.error` перед извлечением id из metadata.
- [ ] TDD-порядок соблюдён: RED (падает по нужной причине) ДО кода, пара RED→GREEN в PR.

**e2e-smoke (real gateway, construction-verified):**
- [ ] one-shot bootstrap: `NetworkService.Create` → `Operation.response` несёт непустые
  `defaultSecurityGroupId°`/`defaultRouteTableId°` (op-in-response, F3/F4); follow-up GET **не** нужен.
- [ ] `SubnetService.Create` ZONAL → `placementType° == "ZONAL"` derived, `routeTableId` auto =
  `network.defaultRouteTableId°`, `ipv4CidrPrimary` ⊆ супернет (F6/F7/F8) — на реальном gateway-ответе.
- [ ] two-projection field-absence: public `Network` НЕ содержит `vrfId`/underlay (VPC-1-16).
- [ ] read-your-writes: первый Get/Update/Delete своего свежего Network/Subnet обёрнут bounded-retry
  (`retry_until_authorized`) на transient 403/404 (owner-tuple EC-окно, conv-3).

**Deliverables редизайна (implementer обязан выполнить — иначе старый путь остаётся):**
- [ ] **Network net-new поля/провижн:** `ipv4_cidr_blocks`/`ipv6_cidr_blocks` (новая миграция +
  proto); `default_route_table_id` (новая колонка + system-provision default-RT в writer-TX Create);
  снят env/флаг опт-аута default-SG (`KACHO_VPC_DEFAULT_SG_INLINE` / `create_default_security_group`)
  — default-SG+RT **безусловны**.
- [ ] **Subnet write-контракт:** `placement_type` из **writable-required** → **derived/unwritable**
  (server выводит из `zoneId` XOR `regionId`; explicit reject `placementType`-в-теле); `v4_cidr_blocks[]`
  → **explicit** `ipv4CidrPrimary` (immutable anchor) + `ipv4CidrBlocks[]`; net-new валидация
  `ipv4CidrPrimary ⊆ network supernet` (sync по строке сети + backstop в writer-TX против
  актуальной строки) — **безусловная**: пустой либо нечитаемый набор блоков даёт отказ, а не
  пропуск проверки (F7a, VPC-1-47..51).
- [ ] **AS-IS удаления (breaking proto-changes):** снят `DhcpOptions` (subnet); `v4_/v6_`-именование
  proto → `ipv4…/ipv6…` (module-vpc §Правила 14 дрейф). Op-in-response: Create/Update/Delete
  Network/Subnet возвращают `Operation{done:true}` + полное тело в `.response` (worker-fn синхронно
  до возврата, statusless-класс).
- [ ] **Не** редактировать применённые миграции (`0001`–`0014`) — только новые (`0015+`).
- [ ] **[PHASE-0-GATED B3]:** id-prefix `net`/`sub` → `net-`/`sub-` (hyphen) приземляется вместе с
  corelib prefix→type-router; до Phase-0 строим на текущей 3-char-форме, hyphen-переход — атомарный
  шаг с change-set (не редактировать сценарии — они формулируют target hyphen-форму).

**Проектные гейты (финальная верификация):**
- [ ] `go test ./... -race` · `golangci-lint run` · `govulncheck` · `make -C services/vpc audit-list-filter` зелёные.
- [ ] `make -C gateway permission-catalog-check` byte-identical (новые/изменённые RPC — записи в каталоге);
  proto — `buf lint`/`buf breaking` (breaking-changes задекларированы: DhcpOptions-drop,
  placement_type write-contract, cidr-rename) зелёные после регена.
- [ ] newman зелёные (все `VPC-1-NN`); proto-контракт ревьюит `proto-api-reviewer`; миграции —
  `db-architect-reviewer`.

**MERGE-GATE (`[PHASE-0-GATED]` — жёсткий блокер, кросс-фазовые зависимости):**
- [ ] **VPC-1 НЕ мёржится, пока Phase-0 governance change-set не приземлит в `api-conventions.md`/
  `data-integrity.md`** (00-unified §7 Фаза-0 step 3, §9 MUST-close):
  - **B1** — 3-way ref-naming (`ResourceRef`/`Referrer`/`OciReferrer`) в `kacho.cloud.common.v1`.
    *NB:* Network/Subnet VPC-1 **не несут** `Referrer`-поля (их refs — within-service FK + scope-coord
    peer-validate), но vpc-proto нельзя писать до landing shared `common.v1` → **build-order gate**.
  - **B3** — id-prefix hyphen-форма (`net-`/`sub-`) в `corevalidate`. До merge — сценарии F1
    формулируют target-форму, реализация на текущей 3-char, hyphen-переход одним шагом.
  - **conv-11 by-lane split (peer-validate lane) + reason-tokens** — **[PHASE-0-GATED]** касается
    **только** peer-validate scope-coord absent (VPC-1-05 projectId, VPC-1-35 zoneId/regionId): AS-IS
    heterogeneous (project→`NOT_FOUND`, zone/region→`INVALID_ARGUMENT`) → target унификация
    `FAILED_PRECONDITION` + reason-token (`NETWORK_NOT_FOUND`/`ZONE_NOT_FOUND`/`REGION_NOT_FOUND`).
    **НЕ** касается within-service `networkId` (VPC-1-41 — `NOT_FOUND` **уже landed ungated** через
    pre-flight resolve; гейтится лишь reason-token detail). До merge change-set VPC-1-05/35 остаются
    AS-IS кодами.
  Ungated части (within-service absent-parent→`NOT_FOUND`, malformed→`INVALID_ARGUMENT`,
  dup→`ALREADY_EXISTS`, overlap→`FAILED_PRECONDITION`, op-in-response, supernet-provision,
  default-SG/RT-provision, placement-derived, CIDR⊆супернет, immutable-текст, two-projection
  field-absence, peer-validate fail-closed `UNAVAILABLE`) строятся в VPC-1 **без** ожидания change-set.

---

## Changelog — что этот док покрывает

- **F1** id-prefix per-type hyphen `net-`/`sub-` **[PHASE-0-GATED B3]**; malformed/**wrong-type**
  first-statement `INVALID_ARGUMENT`; foreign-id (projectId/zoneId) НЕ prefix-checked B4 (VPC-1-01..05).
- **F2** Network declared супернет `ipv4CidrBlocks[]`/`ipv6CidrBlocks[]` (immutable-via-Update;
  verb-pair мутация; ∉-guard на remove живого блока) (VPC-1-06..10).
- **F3** system-provisioned default-SG **и** default-RT **безусловно** (AS-IS flag-gated / RT net-new),
  id эхаются op-in-response; default-SG egress-allow 0.0.0.0/0; single-default под concurrency (VPC-1-11..13).
- **F4** Network op-in-response (AS-IS async-poll → `done:true` + полное тело в `.response`); happy
  CRUD; two-projection `vrfId` field-absence; empty-mask full-PATCH (VPC-1-14..17).
- **F5** Delete-non-empty `"network is not empty"`; `projectId` immutable (Move снят); UNIQUE(name)
  → `ALREADY_EXISTS` + concurrent-race (VPC-1-18..22).
- **F6** Subnet placement-anchor; `placementType°` **derived/unwritable** (AS-IS writable-required),
  голый токен на read; explicit reject (both/neither/placementType-in-body); immutables (VPC-1-23..28).
- **F7** CIDR: explicit `ipv4CidrPrimary` anchor ⊆ супернет (net-new validation) + `ipv4CidrBlocks[]`;
  no-overlap `FAILED_PRECONDITION "subnet CIDRs can not overlap"`; per-network изоляция;
  concurrent-race (VPC-1-29..34).
- **F7a** уточнение F7: вложенность **безусловна** — сеть без объявленного супернета семейства
  отвергает подсеть этого семейства (`INVALID_ARGUMENT`, текст называет семейство, поле и глагол
  `:add-cidr-blocks`); чужое семейство не задевается; нечитаемый объявленный план равен
  необъявленному; backstop writer-TX ловит опустошение супернета под гонкой (VPC-1-47..51).
- **F8** zone/region coherence peer-validate geo (fail-closed `UNAVAILABLE`); auto-associate default-RT;
  `networkId` immutable; self-describing derived `zoneId°`/`regionId°` (VPC-1-35..39).
- **F9** Subnet op-in-response; by-lane absent-network → `NOT_FOUND` **ungated** (уже landed via
  pre-flight; reason-token gated); peer-validate zone/region → AS-IS `INVALID_ARGUMENT`, target
  `FAILED_PRECONDITION` **[PHASE-0-GATED conv-11]** (VPC-1-35); malformed first-statement; `DhcpOptions`
  снят by design; pagination-validate до listauthz; List-filter `zoneId=`/`networkId=`; v6-only subnet
  edge (VPC-1-40..46).

**Что изменилось в ре-ревью раунд 1** (все 6 findings acceptance-reviewer'а адресованы + 5 дефолтов
вшиты): (1) F9 AS-IS исправлен — absent-`networkId` **уже** `NOT_FOUND` (pre-flight resolve
`create.go:133/213`), не FK-`FAILED_PRECONDITION`; VPC-1-41 разгейчен (только reason-token gated).
(2) VPC-1-35 — конкретный код: AS-IS `INVALID_ARGUMENT "unknown zone id"` (`helpers.go:197`), target
`FAILED_PRECONDITION` gated. (3) Полосы разведены: within-service `networkId`→`NOT_FOUND` (ungated) vs
peer-validate `projectId`/`zoneId`/`regionId`→ by-lane `FAILED_PRECONDITION` (gated); VPC-1-05 поправлен.
(4) VPC-1-13 переформулирован как atomicity/orphan-absence (не race); DoD `-race` — только VPC-1-22/33.
(5) F3 AS-IS: egress-allow **уже** present (ingress+egress ANY 0.0.0.0/0); реальное изменение —
INGRESS-сужение (VPC-2). (6) F8 AS-IS: RT-auto-assoc triggers **существуют** (`rt_auto_assoc_subnets`/
`subnet_auto_pick_rt`) — редизайн reconcile'ит; `route_distinguisher` — 0001-baseline (не 0007);
AS-IS тон-тексты (malformed-CIDR / overlap-регистр) названы; +VPC-1-45 (List-filter) / +VPC-1-46 (v6-only).

Покрытие обязательного минимума (task): id-prefix per-type ✓ (VPC-1-01..05, PHASE-0-GATED B3) ·
declared-супернет immutable+verb-pair ✓ (F2) · default-SG/RT + op-in-response + egress-0.0.0.0/0 ✓ (F3/F4) ·
Subnet single placement-anchor + placementType° derived DB-CHECK биконд. ✓ (F6) · CIDR ⊆ супернет +
no-overlap FAILED_PRECONDITION фикс-текст ✓ (F7) · zone-coherence peer geo ✓ (F8) · concurrent-race в
DoD ✓ (VPC-1-13/22/33) · positive+negative+edge на каждую фичу ✓. PHASE-0 gating помечен (B1 build-order,
B3 hyphen, conv-11 by-lane); by-lane тон conv-11 ✓.

## Дефолты, зафиксированные на review (раунд 1)

Все 5 прежних open questions разрешены ревьюером и вшиты в сценарии/Scope/Out-of-scope/DoD выше:

1. **Декомпозиция — ПРИНЯТА инверсия task-канвы:** VPC-3 = **Address**+AddressPool+sweeper, VPC-4 =
   **Gateway+NIC**. Форвард-зависимость `Gateway.externalAddressSpec` / `NIC.addressSpecs[]` /
   `NIC.AssociateAddress` → Address реальна ⇒ Address обязан идти раньше. Отражено: §Out-of-scope
   декомпозиция.
2. **Discovery + `validateOnly` → VPC-1b:** `ListPlaceableZones`/`SuggestCidrBlocks`/
   `ListLaunchableSubnets` + `validateOnly:true` dry-run вынесены в отдельный VPC-1b (net-new
   sync-catalog + dry-run path). VPC-1 = CRUD-фундамент. Отражено: §Out-of-scope. List-filter
   `zoneId=`/`networkId=` (не discovery, а базовый List-контракт) — **в VPC-1** (VPC-1-45).
3. **default-SG INGRESS-сужение → VPC-2:** VPC-1 локает **наличие** egress-allow 0.0.0.0/0 (уже AS-IS,
   VPC-1-12 тривиально зелёный) + факт system-provision; сужение AS-IS INGRESS-ANY-0.0.0.0/0 →
   intra-network + verb-pair мутация правил — VPC-2. Отражено: F3-intro, VPC-1-12, §Out-of-scope.
4. **`SetDefaultSecurityGroup`/`SetDefaultRouteTable` → VPC-2** (re-point целит tenant-созданные SG/RT,
   которых до VPC-2 нет). VPC-1 — только system-created дефолты. Отражено: F3-intro, §Out-of-scope.
5. **B3 hyphen-форма в сценариях с merge-gate — ПРИЕМЛЕМО** (как GEO-1): target `net-`/`sub-` + явный
   merge-gate, дублировать AS-IS/target не нужно. Отражено: F1-intro, DoD merge-gate.

Открытых вопросов к reviewer нет — док готов к повторному review.
