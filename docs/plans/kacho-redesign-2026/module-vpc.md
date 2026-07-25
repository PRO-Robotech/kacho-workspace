# kacho-vpc — Target tenant-facing API design

*Best-practice-2026 target. Anchored on the converged compute form: flat resource, async `Operation`, sync discovery-catalogs, reference-law, two-projection, one unified error tone. VPC must read as the same product as compute — same envelope, same verbs, same `°`-marker, same retry contract.*

Legend: `°` = **output-only** (server-set, ignored on write). Fields tagged *(write-only)* are inputs the server consumes and never echoes on read (the mirror of `°`). All JSON is camelCase over REST. Ids are `<3-char type-prefix> + crockford-base32 body`; **the prefix alone identifies the type** (`net`/`sub`/`scg`/`rtb`/`gwy`/`nic`/`adr`/`apl`) — a bare id crossing the compute↔vpc / nlb↔vpc seam is routable by type without a lookup.

**Enum round-trip contract:** on **write** a field accepts the bare `value` string (`"V4"`, `"INGRESS"`); on **read** it returns the object `{value, displayName°}` — a *superset*. A fetched resource cannot be PATCH-resubmitted verbatim: transform each enum to its `.value` first. The object form is **never** accepted on write. (Exception: pure derived read-only discriminators — see `placementType°` — are a bare token on read too.)

---

## Ментальная модель

Пять опор. Каждая — ровно один источник истины. Четыре вещи, снимающие повторяющееся непонимание, сразу: **(a) Network — это и есть «ваш VPC»** (изолированный routing-домен; `/vpc/v1/networks/{id}` ↔ один VRF, эквивалентность буквальная). **(b) SG и RouteTable по умолчанию создаёт система** — типовая рабочая сеть поднимается **без единого ручного `Create` SG/RT**; их правишь на живых дефолтных ресурсах (`:add-rule` / `:add-route`), а не пересоздаёшь. **(c) У statusless-ресурсов** (Network/Subnet/SG/RouteTable/Gateway) `Operation` приходит `done:true` уже в ответе `Create`, **и `Operation.response` несёт ПОЛНОЕ созданное тело** со всеми derived `°`-полями — follow-up `GET` не нужен (op-in-response). **(d) NIC создаётся ДО инстанса и потом связывается** (`usedBy°`) — намеренный путь владения (VPC владеет присутствием, compute референсит `nicId`), не баг; в отличие от statusless-сиблингов, NIC имеет lifecycle-присутствие (`usedBy`/dangling) и его Create — **poll**, не op-in-response.

1. **Network — изолированный routing-домен (SRv6 VRF) со своим объявленным адресным пространством, а не «список подсетей».** Источник истины изоляции И супернета — `kacho_vpc.networks` (одна строка = один VRF + `ipv4CidrBlocks[]`/`ipv6CidrBlocks[]`, из которых нарезаются subnet). Subnet/SG/RouteTable/Gateway/NIC живут *внутри* одной Network и физически не видят соседние. `networkId` на дочерних — **immutable within-service FK**, никогда не референс.

2. **Subnet — единственный placement-якорь.** `placementType° ∈ {ZONAL, REGIONAL}` (дискриминатор, server-derived из непустого `zoneId`/`regionId`) — источник истины «где». Всё, что цепляется к Subnet (Address, NIC), зону/регион **наследует** через `subnetId`. Coherence проверяется в одной точке — при link к Subnet; consumer при этом сам self-describing (`zoneId°`/`regionId°` derived).

3. **Address — единственный владелец IP-аренды (IPAM), ровно ОДИН IP на строку.** Строка `kacho_vpc.addresses` — истина «этот один IP занят» (`addressFamily` V4/V6 + одно поле `address°`). **internal vs external — не отдельное inline-поле, а следствие binding-ref**: задан `subnetId` ⇒ internal (из subnet-CIDR), задан `addressPoolId` ⇒ external (из пула); взаимоисключение держит DB-CHECK, а `scope°` его читаемо эхает. Кто держит аренду — `usedBy°` (polymorphic `Referrer`, graceful-dangling). Ни NIC, ни nlb-listener, ни compute-instance не «владеют» IP — только **референты** через CAS. Dualstack-присутствие = две Address-строки.

4. **NIC — first-class ресурс, не inline-часть Instance.** Источник истины сетевого присутствия рабочей нагрузки — `kacho_vpc.network_interfaces`. Compute/NLB ссылаются на `nicId`; VPC ими владеет и переживает удаление референта (`usedBy°` → dangling → DETACHED, не паника).

5. **Публичная поверхность = намерение + результат. Физика — только Internal* :9091.** Истина инфра-проекции (VRF-id, underlay, host-wiring, AddressPool free-list) — отдельные `Internal*`-сообщения. Публичный ресурс их не несёт даже как output-only.

> **Cross-cutting механики (держи их все в голове — «пять опор» описывают *ресурсы*, но builder обязан знать ~дюжину сквозных механик):**
> binding-ref-деривация (Address scope) · дискриминаторы `placementType`/`retention` (bare-token derived) · авто-провижн default-SG/RT при `Network.Create` · **op-in-response** (statusless Create → `done:true` + полное тело инлайн) · verb-pair collection-мутация (`:add-*`/`:remove-*`) · per-rule OCC (`expectedVersion`) · two-projection (public vs Internal*) · spec-inlining (`*Spec(s)` one-shot Create) · `Referrer` (polymorphic, graceful-dangling) · read/write enum-асимметрия (`.value` на write) · peer-validate scope-координат (iam/geo, fail-closed) · bounded client-retry на read-your-writes окне.

> **By-design omissions (узнаваемый примитив намеренно отсутствует — чтобы искомое получило ответ, а не тишину):**
> - **stateless subnet-ACL / NACL — нет by design.** Вся фильтрация — **stateful SecurityGroup на NIC**; второго (network-ACL) слоя нет. Микросегментация — SG-target-правила (`securityGroupId` в rule).
> - **VPC peering / transit / VPN / inter-Network bridge — нет в этой фазе.** Network — изолированные VRF без моста между собой by construction; связность между двумя Network не выражается ресурсом (roadmap-кандидат, не текущий контракт).
> - **Network-level DHCP-options / DNS-resolver knobs — нет.** Резолвер/опции не конфигурируются на уровне Network в этой фазе.

1. **Network — изолированный routing-домен (SRv6 VRF) со своим объявленным адресным пространством, а не «список подсетей».** *(см. опору 1 выше)*

> **Достижимость интернета — карта «намерение → форма Kachō»** (отдельного «internet-gateway»-ресурса нет by design; достижимость выражается назначением/маршрутизацией, не ресурсом-шлюзом):
>
> | Намерение | Форма Kachō |
> |---|---|
> | **ingress / floating IP** (входящий на рабочую нагрузку) | назначить **external Address** на NIC рабочей нагрузки — `NetworkInterfaceService.AssociateAddress(adr…)`; трафик приходит на этот IP |
> | **egress** (исходящий в интернет) | **NAT-gateway** (`Gateway.type=NAT_GATEWAY`, SNAT, **REGIONAL/anycast** если это shared default-route target) + статический маршрут `0.0.0.0/0` на него через `RouteTableService.AddStaticRoutes` + **egress-allow в SG** (дефолтная SG уже пускает initiating outbound) |
> | **east-west** (внутри Network) | разрешено дефолтной SG (intra-network allow + established/related), маршрут на месте — ничего делать не надо |

> **Recipe A — «Network с выходом в интернет для всех подсетей» (end-to-end, минимум вызовов):**
> 1. `NetworkService.Create` → Network (система инлайном создаёт **default SG** и **default RouteTable**, они уже привязаны — SG/RT руками не создаём; `Operation.response` уже несёт `defaultSecurityGroupId°`/`defaultRouteTableId°`).
> 2. `SubnetService.Create` (ZONAL) → Subnet; автопривязывается к `network.defaultRouteTableId°`.
> 3. `GatewayService.Create` с `externalAddressSpec`, **`regionId` (REGIONAL/anycast)** → NAT-Gateway **и** внешний Address одной Operation. **REGIONAL обязателен**, если этот gateway — цель `0.0.0.0/0` в **shared** default-RT: RT network-scoped и разделён между зонами, ZONAL-gateway обслужил бы только свою зону (см. Rule 5).
> 4. `RouteTableService.AddStaticRoutes` на **дефолтном** RT: `0.0.0.0/0 → natGatewayId` (правим живой дефолт, не пересоздаём). ⚠️ **Callout:** default-RT автопривязан ко **ВСЕМ** подсетям Network → этот один маршрут включает egress для **всех** подсетей сети сразу. Дефолтная SG уже пускает initiating outbound, поэтому маршрут не «немой».
> 5. `NetworkInterfaceService.Create` (`securityGroupIds` пуст → наследует default-SG) → NIC для рабочей нагрузки; для входящего — `AssociateAddress` внешнего Address.
>
> **Recipe B — «public + private подсети» (per-subnet изоляция требует override-RouteTable):** дефолтный RT общий на всю сеть, поэтому `0.0.0.0/0` в нём открывает egress **всем**. Чтобы одна подсеть НЕ имела выхода:
> 1. `RouteTableService.Create` → dedicated RT **без** `0.0.0.0/0` (только intra-network).
> 2. `Subnet.Update` приватной подсети: `routeTableId = <dedicated>` (override дефолта).
> 3. Публичная подсеть остаётся на default-RT с `0.0.0.0/0 → natGatewayId`.
> **Per-subnet isolation невозможна без override-RT** — «лёгкий путь» (Recipe A) даёт egress всем; приватность — осознанный override.
>
> **Callout:** tenant-созданная SG **не действует сама по себе** — она вступает в силу только когда NIC перечисляет её в `securityGroupIds`. Пустой `securityGroupIds` у NIC ⇒ наследуется `network.defaultSecurityGroupId°` (не deny-all).

---

## Network *(aka «isolated VPC / routing domain»)*

Изолированный routing-домен с объявленным супернетом. Project-scoped unique name. Statusless (control-plane-only, ACTIVE сразу после Create → **op-in-response: `Operation` приходит `done:true`, а `Operation.response` несёт полное тело ниже, включая `defaultSecurityGroupId°`/`defaultRouteTableId°` на момент создания — follow-up GET не нужен**).

```jsonc
{
  "id": "netv8f3k2q9m4t1n7",             // ° prefix net
  "projectId": "prjb3n7k1x9q2m5t8",      // scope-coord → peer-validate iam, flat slug, hard-fail
  "name": "core-prod",                    // UNIQUE(projectId,name); immutable after Create
  "description": "Primary production VPC",
  "labels": { "team": "platform", "env": "prod" },
  "ipv4CidrBlocks": ["10.20.0.0/16"],    // declared SUPERNET(s); each Subnet.ipv4CidrPrimary ⊆ one block. NO 'primary' at Network level.
  "ipv6CidrBlocks": ["fd00:20::/48"],    // declared v6 SUPERNET(s); mutated via :add/:remove-cidr-blocks
  "defaultSecurityGroupId": "scg0d3f7k1t9m2q5v",  // ° inline default SG, system-created at Network.Create
  "defaultRouteTableId": "rtb9k3m7t2q5n8v1h",     // ° default RT, system-created, auto-associated to new Subnets
  "createdAt": "2026-07-19T08:14:22Z"    // ° truncate → seconds
  // vrfId / underlay — НЕ здесь. Инфра-чувствительно → InternalNetworkService.GetNetwork только.
}
```

- `projectId` — **scope-координата**: flat slug + peer-validate `iam.ProjectService.Get` (hard-fail `Unavailable` если iam down). Immutable — Move снят целиком (contract-removal).
- `ipv4CidrBlocks[]`/`ipv6CidrBlocks[]` — **объявленный супернет** (в отличие от Subnet, у Network НЕТ `*CidrPrimary` — это чистый набор супернет-блоков, из которых нарезаются подсети). Каждый Subnet-CIDR обязан быть подмножеством одного из блоков (валидируется на Subnet.Create → `INVALID_ARGUMENT "subnet CIDR %s is not within any network CIDR block"`). Мутируются только через `:add-cidr-blocks`/`:remove-cidr-blocks` (не через Update).
- `defaultSecurityGroupId°` / `defaultRouteTableId°` — **единственный источник истины** «какие SG/RT дефолтны для сети»; создаются системой инлайном при `Network.Create` и **эхаются в `Operation.response`** сразу. **Default-SG-политика**: разрешает весь intra-network трафик + established/related возврат **+ stateful initiating egress `0.0.0.0/0`** (свежий исходящий пакет к `8.8.8.8` проходит — иначе NAT+route были бы немыми); deny входящего из-за пределов Network.
- **Defaults-governance (владелец сети владеет своими дефолтами):** re-point дефолтов — публичный `NetworkService.SetDefaultSecurityGroup`/`SetDefaultRouteTable` (async), в т.ч. promote собственноручно созданной SG/RT в дефолт сети. Само *обозначение* «default» — намерение, не инфра-данные, поэтому на публичной поверхности; free-list/underlay пула остаются в Internal*.
- Delete непустой → `FAILED_PRECONDITION "network is not empty"` (FK без cascade через Subnet/SG/RT/Gateway).

---

## Subnet

Placement-якорь. `placementType°` — дискриминатор, **server-derived** из того, какой из `zoneId`/`regionId` непуст (взаимоисключение держит DB-CHECK). **На write клиент шлёт ровно один из `zoneId`/`regionId` — самого `placementType` на write НЕТ** (он read-only, выводится; попытка задать → explicit reject, см. ниже). Statusless: op-in-response (`Operation` приходит `done:true` + полное тело в `response`, poll не нужен).

> **Форма enum (единообразно во всех модулях):** на **write** — голая строка `value` (`"addressFamily":"V4"`, rule-`"direction":"INGRESS"`); на **read** — inline-объект `{value, displayName°}`. **Исключение — чистые derived-дискриминаторы** (`placementType°`): read-only, голый токен `"ZONAL"` не несёт информации сверх себя → **не** оборачивается в `{value,displayName}`.

```jsonc
{
  "id": "subt4k8n2q0m5v9h1",             // ° prefix sub
  "projectId": "prjb3n7k1x9q2m5t8",      // scope-coord (peer-validate iam)
  "networkId": "netv8f3k2q9m4t1n7",      // within-service FK → networks(id), immutable
  "placementType": "ZONAL",              // ° derived (bare token) from whichever of zoneId/regionId is set. NOT writable.
  "zoneId": "zone-nova-a",               // set iff ZONAL; scope-coord → peer-validate geo.ZoneService.Get
  "regionId": "",                         // empty iff ZONAL (mutually exclusive, DB-CHECK)
  "name": "app-tier-a",
  "description": "",
  "labels": {},
  "ipv4CidrPrimary": "10.20.0.0/24",     // immutable placement anchor; a SUBSET of one network.ipv4CidrBlocks supernet block
  "ipv4CidrBlocks": ["10.20.8.0/24"],    // extra ranges (:add-cidr-blocks), each ⊆ network supernet
  "ipv6CidrPrimary": "fd00:20::/64",     // subnet may be v6-only (ipv4CidrPrimary optional)
  "ipv6CidrBlocks": [],
  "routeTableId": "rtb9k3m7t2q5n8v1h",   // within-service ref → route_tables; auto = network.defaultRouteTableId
  "createdAt": "2026-07-19T08:15:03Z"    // °
}
```

REGIONAL (anycast) form — client sends `regionId`, `placementType°` derives to `"REGIONAL"`; excluded from zonal coherence *by construction*:

```jsonc
{ "regionId": "region-nova", "ipv4CidrPrimary": "10.99.0.0/24" }   // write shape (no placementType on write)
// read → "placementType": "REGIONAL", "zoneId": ""
```

- **CIDR-роль (Network vs Subnet, одноимённые поля — разные роли):** Subnet несёт `ipv4CidrPrimary` (**immutable placement anchor**, подмножество одного супернет-блока) **+** дополнительные `ipv4CidrBlocks[]`; Network несёт **только** `ipv4CidrBlocks[]` (**declared supernet**, без primary). Одноимённый `ipv4CidrBlocks[]` на Network = «объявленный супернет», на Subnet = «доп. диапазоны сверх primary» — не обобщай роль между ними.
- **Coherence law** — enforced *at Subnet* (single point); consumers inherit via `subnetId` и сами несут derived `zoneId°`/`regionId°`.
- **CIDR-overlap** — EXCLUDE gist per (network, family) → 23P01 → **всегда** `FAILED_PRECONDITION "subnet CIDRs can not overlap"` (не ALREADY_EXISTS — тот строго для UNIQUE(name)).
- `zoneId`/`regionId` existence — peer-validate geo, fail-closed. `placementType`(derived,unwritable)/`zoneId`/`regionId`/`ipv4CidrPrimary` immutable.
- **Placement write-feedback (explicit reject, не silent):** `zoneId` и `regionId` оба заданы ИЛИ оба пусты → `INVALID_ARGUMENT "exactly one of zoneId, regionId must be set"`; `placementType` в теле write → `INVALID_ARGUMENT "placementType is server-derived; set zoneId or regionId instead"` (**не** silent-ignore — silent наименее предсказуем для «set-the-type» новичка).
- **List filter whitelist:** `name=`, `zoneId=`, `networkId=` (compute-интегратор с инстансом в зоне X матчит существующую same-zone subnet server-side, без per-launch Get-and-eyeball).

**Discovery-near-launch (три грани):**
- `SubnetService.ListPlaceableZones` (§Discovery) — где можно **создать** ZONAL/REGIONAL subnet; item несёт `requestFragment` (zoneId/regionId не гадать).
- `SubnetService.SuggestCidrBlocks` (§Discovery) — свободные под-диапазоны супернета под заданный `prefixLen`, каждый с готовым `requestFragment.ipv4CidrPrimary` (закрывает единственную «слепую» точку net-builder'а — вырезание CIDR из супернета). `validateOnly:true` на `Subnet.Create` дополнительно echo'ит `resolved{suggestedCidr, conflictingRanges}`.
- `SubnetService.ListLaunchableSubnets` (§Discovery) — **существующие** subnet в зоне X со свободной ёмкостью (`freeAddressCount°`/`hasCapacity°`) + `requestFragment.subnetId` под `NIC.Create` (закрывает самый частый compute-путь «прицепить NIC к существующей subnet в зоне X с headroom»).

---

## SecurityGroup

`networkId` required + immutable (SG↔SG rules валидны только внутри одной Network). Statusless (op-in-response). Правила — **отдельный collection-mutation путь** (`:add-rule`/`:remove-rule`, симметрично `:add-cidr-blocks`) + single-rule OCC (`UpdateRule` с per-rule `expectedVersion`); общий `Update` правила НЕ трогает. **Один OCC-токен (per-rule `version°`) и одна collection-идиома (verb-pair)** — SG-level `version` для правил упразднён.

```jsonc
{
  "id": "scg5h2t9k0m3q7v1n",             // ° prefix scg
  "projectId": "prjb3n7k1x9q2m5t8",
  "networkId": "netv8f3k2q9m4t1n7",      // REQUIRED + immutable (not in Update mask)
  "name": "web-ingress",
  "description": "",
  "labels": {},
  "rules": [
    {
      "id": "rul7k2m9t4q1n8v3",          // ° stable per-rule id
      "version": "v-1b8e4d90",           // ° per-rule etag (server maps to xmin); pass as expectedVersion to UpdateRule
      "direction": {"value":"INGRESS","displayName":"Inbound to interface"},   // write: "INGRESS"
      "protocol": {"value":"TCP","displayName":"TCP"},                          // write: "TCP"
      "fromPort": 443, "toPort": 443,
      "cidrBlocks": ["0.0.0.0/0"],        // OR securityGroupId — mutually exclusive source
      "securityGroupId": "",              // ref to peer SG in SAME network (validated)
      "description": "https"
    },
    {
      "id": "rul3t8k1m9q4n7v2",          // ° an EGRESS example — initiating outbound to the internet
      "version": "v-77c2ab13",           // °
      "direction": {"value":"EGRESS","displayName":"Outbound from interface"},  // write: "EGRESS"
      "protocol": {"value":"ANY","displayName":"Any protocol"},                 // write: "ANY"
      "fromPort": 0, "toPort": 0,
      "cidrBlocks": ["0.0.0.0/0"],        // stateful initiating egress — pairs with a NAT route
      "securityGroupId": "",
      "description": "allow all egress"
    }
  ],
  "createdAt": "2026-07-19T08:16:40Z"    // °
}
```

- `CreateSecurityGroupRequest.ruleSpecs[]` — **initial** rules seed (one-shot). Форма spec: `{direction, protocol, fromPort, toPort, cidrBlocks[] | securityGroupId, description}`.
- **`defaultForNetwork` снят** (derivable из `network.defaultSecurityGroupId°`; читатель всё равно фетчит Network за дефолтами — reverse-mirror-флаг был дублем истины Network).
- General `Update` mask = `{name, description, labels}` — **bare** (no OCC), **без `ruleSpecs`** (вторая дверь с lost-update устранена — правила мутируются только через verb-pair/UpdateRule).
- **Collection-mutation (одна идиома):** `AddRules` (`:add-rule`) / `RemoveRules` (`:remove-rule`) — async, симметрично `:add-cidr-blocks`/`:remove-cidr-blocks`. Точечная правка одного правила — `UpdateRule` с `expectedVersion` (If-Match на per-rule `version°`); mismatch/0 rows → `FAILED_PRECONDITION "security group rule was modified concurrently"`.
- **EGRESS — first-class direction** (не только INGRESS). Дефолтная SG сети уже несёт stateful-initiating-egress-allow (см. Network default-SG-policy) — поэтому Recipe A egress «просто работает»; кастомная SG с пустым egress-набором **не** пропустит исходящий пакет к интернету (добавь egress-allow rule).
- SG-target rule → cross-network/missing → `INVALID_ARGUMENT` + `BadRequest.field_violations`.
- Rule-protocol каталог — **статический inline enum** (`{value,displayName,defaultPorts}` в схеме/OpenAPI), не RPC: `TCP`, `UDP`, `ICMP` (`{type,code}` вместо портов), `ICMPV6`, `ANY`. Набор не зависит от состояния.

---

## RouteTable

```jsonc
{
  "id": "rtb9k3m7t2q5n8v1h",             // ° prefix rtb
  "projectId": "prjb3n7k1x9q2m5t8",
  "networkId": "netv8f3k2q9m4t1n7",      // within-service FK, immutable
  "name": "egress-default",
  "description": "", "labels": {},
  "staticRoutes": [
    { "id": "srt2k9m4t7q1n8v3",          // ° stable per-route id (target of :remove-route)
      "destinationPrefix": "0.0.0.0/0",
      "natGatewayId": "gwy3t8k1m9q4n7v2h",   // within-service ref → gateways(id) SAME network (NAT/egress Gateway resource); OR nextHopAddress
      "nextHopAddress": "" },
    { "id": "srt7t2q9n0v3h4k8m", "destinationPrefix": "10.50.0.0/16",
      "nextHopAddress": "10.20.0.1",         // next-hop IP (raw L3 router address); OR natGatewayId
      "natGatewayId": "" }
  ],
  "createdAt": "2026-07-19T08:17:12Z"    // °
}
```

- **`natGatewayId` vs `nextHopAddress` — два разных next-hop-вида в одной route-строке, не путать:** `natGatewayId` = ссылка на **Gateway-ресурс** (NAT/egress) той же Network; `nextHopAddress` = **сырой L3 next-hop IP** (роутер). Взаимоисключающи per-route. (Переименовано из перегруженного `gatewayId`, который читался двусмысленно — «Gateway-ресурс» vs «шлюз-IP».)
- Auto-associated to Subnet at Subnet.Create (`network.defaultRouteTableId°`); tenant overrides via `Subnet.Update.routeTableId`.
- **`staticRoutes` — живая коллекция, правится через verb-pair, НЕ пересозданием:** `RouteTableService.AddStaticRoutes` (`:add-route`) / `RemoveStaticRoutes` (`:remove-route`) — async, симметрично `:add-cidr-blocks`. **Дефолтный/живой RT правится именно так** (egress-шаг recipe = добавить `0.0.0.0/0 → natGatewayId` на существующий default-RT, а не создавать новый и перецеливать Subnet). ⚠️ default-RT привязан ко всем подсетям Network → маршрут в нём действует на **все** подсети.
- **Coherence-enforcement Subnet↔Gateway-через-RT (закрывает вторую placement-шов):** RT network-scoped и разделён между зонами. При `AddStaticRoutes` c `0.0.0.0/0 → natGatewayId`, где Gateway **ZONAL**, а RT ассоциирован с подсетями **вне** зоны этого gateway → `FAILED_PRECONDITION "gateway is in zone %s, route table serves subnets in zone %s"` (иначе — silent black-hole/cross-zone egress). Shared default-route target обязан быть **REGIONAL (anycast)** gateway (обслуживает все зоны когерентно).
- Delete while associated (`subnets.route_table_id` not NULL) → `FAILED_PRECONDITION`.
- `staticRoutes[].natGatewayId` — within-service FK на Gateway той же Network (VRF-изоляция: immutable `networkId` обеих таблиц гарантирует same-VRF).

---

## Address

IPAM lease — **ровно один IP**. `addressFamily` (V4/V6) + одно поле `address°`; **internal/external выводится из binding-ref** (`subnetId` ⇒ internal, `addressPoolId` ⇒ external — взаимоисключение DB-CHECK) и читаемо эхается через `scope°`. placement и binding наследуются от subnet/pool. `usedBy°` — polymorphic `Referrer` (graceful-dangling). Dualstack NIC ссылается на две Address-строки.

```jsonc
{
  "id": "adrk9m2t7q4n1v8h3",             // ° prefix adr
  "projectId": "prjb3n7k1x9q2m5t8",
  "name": "web-vip", "description": "", "labels": {},
  "addressFamily": {                      // discriminator V4 | V6; write: "V4"
    "value": "V4",
    "displayName": "IPv4"
  },
  "scope": {                              // ° DERIVED from binding-ref (subnetId⇒INTERNAL, addressPoolId⇒EXTERNAL); read-only, not writable
    "value": "EXTERNAL",
    "displayName": "External — leased from an address pool"
  },
  "requestedAddress": "203.0.113.42",    // (write-only) optional; omit → IPAM auto-picks. Never echoed on read.
  "address": "203.0.113.42",             // ° server-assigned IP (echo of the actually-leased address)
  "addressPoolId": "aplm4k8t2q9n0v3h7",  // binding-ref: set ⇒ scope°=EXTERNAL (allocation source = pool)
  "subnetId": "",                         // binding-ref: set ⇒ scope°=INTERNAL (allocation source = subnet CIDR)
  "zoneId": "",                           // ° derived (internal→subnet.zone; external→pool.zone; anycast→'')
  "regionId": "region-nova",             // ° derived
  "retention": {                          // discriminator EPHEMERAL(default) | RESERVED; write: "RESERVED"
    "value": "RESERVED",
    "displayName": "Reserved — held even when unreferenced"
  },
  "usedBy": {                             // ° Referrer — polymorphic, graceful-dangling
    "type": {"value":"compute.instance","displayName":"Compute Instance"},
    "id": "cpni7k2m9t4q1n8v3",
    "name": "web-01"                      // ° denormalized mirror, source of truth = compute.Instance
  },
  "createdAt": "2026-07-19T08:18:55Z"    // °
}
```

Internal form (allocated from a subnet, zone inherited — `subnetId` set ⇒ `scope°`=INTERNAL, no glue field needed):

```jsonc
{ "addressFamily": {"value":"V4","displayName":"IPv4"},
  "scope": {"value":"INTERNAL","displayName":"Internal — leased from a subnet CIDR"},   // ° derived
  "subnetId": "subt4k8n2q0m5v9h1", "addressPoolId": "",
  "address": "10.20.0.15", "zoneId": "zone-nova-a", "regionId": "region-nova",   // zoneId°/regionId° derived
  "retention": {"value":"EPHEMERAL","displayName":"Released only when a referrer is detached (usedBy non-empty→empty); never reaped before first attach"} }
```

- **`scope°`** — output-only derived echo of binding-ref (`subnetId`⇒INTERNAL, `addressPoolId`⇒EXTERNAL). **Не пишется** (истина — binding-ref + DB-CHECK); присутствует, потому что internal/external — первое, к чему тянется оператор при IP-alloc. Читаемое эхо восстанавливает ожидаемое поле при нулевой цене инварианта.
- `requestedAddress` *(write-only)* — опциональный запрос конкретного IP (static-IP path); опущен → IPAM авто-выбирает. **Не** возвращается на read (write-vs-derived разделение, зеркалит compute request-spec). Результат аренды всегда читается из `address°`.
- `retention` (переименован из `lifecycle` — ближе к industry allocation/reservation-вокабуляру; «lifecycle» ложно намекал на time-based expiry, которого нет) — единственная ось «сохранность аренды»: `EPHEMERAL`, `RESERVED`. Взаимоисключение by construction (DB-CHECK). `EPHEMERAL↔RESERVED` — легальный LIVE-toggle (Rule 11).
- **Retention-гарантия EPHEMERAL (в глоссе displayName, не в отдалённой прозе):** строка reap'ается **только** на переходе `usedBy` non-empty→empty (референт снят). Свежесозданный EPHEMERAL с ещё-пустым `usedBy` (никогда не референсился) **не** reap'ается — стандартный pre-alloc-паттерн «alloc EIP → Associate» безопасен в окне между Create и Associate. (Долгоживущий static EIP всё равно предпочитает `retention=RESERVED`.)
- **binding-ref взаимоисключение — spoken failure:** оба (`subnetId`+`addressPoolId`) заданы ИЛИ оба пусты → `INVALID_ARGUMENT "exactly one of subnetId, addressPoolId must be set"` (а не немой DB-CHECK-отказ).
- External IP CAS-allocated из AddressPool (`FOR UPDATE SKIP LOCKED LIMIT 1`); internal — из subnet CIDR.
- `usedBy` set/cleared **только** через `InternalAddressService.SetReference`/`ClearReference` (atomic CAS `used_by IN ('',$ours)`), никогда не tenant-writable, никогда software check-then-act.
- Delete while `usedBy` non-empty → `FAILED_PRECONDITION`.
- Discovery для выбора external-пула (zonal vs anycast) — `AddressService.ListPlaceableExternalPools` (§Discovery); инфра-детали пула остаются в Internal*.

**IP-assignment decision-table (одна ось, три входа — не три параллельные двери):**

| Намерение | Путь | Вызов(ы) |
|---|---|---|
| **новый ephemeral IP при создании NIC** | inline `NIC.Create.addressSpecs[]` (alloc+attach) | один `NIC.Create` |
| **повесить уже выделенный reserved EIP** | `Address.Create(retention=RESERVED)` → `NIC.AssociateAddress` | два |
| **перенести EIP на другой NIC** | `DisassociateAddress` → `AssociateAddress` | два |

---

## Gateway

Placement-несущий edge-ресурс: подчинён общему дискриминатору `placementType°` и reference-law (`networkId` FK), как все ресурсы модуля. Достижимость интернета выражается им (egress/SNAT), см. карту в Ментальной модели. Statusless (op-in-response).

```jsonc
{
  "id": "gwy3t8k1m9q4n7v2h",             // ° prefix gwy
  "projectId": "prjb3n7k1x9q2m5t8",
  "networkId": "netv8f3k2q9m4t1n7",      // within-service FK → networks(id), immutable (VRF-scoping)
  "name": "shared-egress-nova",
  "description": "", "labels": {},
  "type": {                               // recognizable generic token in the VALUE (not only gloss); write: "NAT_GATEWAY"
    "value": "NAT_GATEWAY",
    "displayName": "NAT gateway — shared egress (SNAT) to the internet"
  },
  "placementType": "REGIONAL",           // ° derived (bare token) from whichever of zoneId/regionId is set. NOT writable.
  "zoneId": "",                           // set iff ZONAL (pins egress to one zone); peer-validate geo, fail-closed
  "regionId": "region-nova",             // set iff REGIONAL (anycast egress — required for a shared default-route target); mutually exclusive, DB-CHECK
  "natGateway": {                         // type-specific block (oneof-by-type)
    "externalAddressId": "adrk9m2t7q4n1v8h3"   // ° ref to external Address (its zone/region must cohere)
  },
  "createdAt": "2026-07-19T08:19:30Z"    // °
}
```

- `networkId` immutable — Gateway живёт в одном VRF; `RouteTable.staticRoutes[].natGatewayId` резолвится внутри той же (immutable-networkId) таблицы → per-Network изоляция.
- `placementType°` derived (как Subnet, голый токен): **ZONAL egress пришпилен к своей зоне** — обслуживает трафик только из подсетей той зоны; **REGIONAL egress — anycast по региону**, обслуживает все зоны когерентно. На write — ровно один из `zoneId`/`regionId`, самого `placementType` на write нет (задать → reject как у Subnet).
- **Coherence Subnet↔Gateway-через-RT:** shared default-route target **обязан быть REGIONAL** — иначе `RouteTableService.AddStaticRoutes` отвергает `0.0.0.0/0 → ZONAL-gatewayId` на RT, обслуживающем подсети вне зоны gateway (см. RouteTable-раздел; закрывает silent cross-zone/black-hole egress-риск). Coherence с `natGateway.externalAddressId` проверяется по общему placement-правилу.
- **One-shot Create** — `CreateGatewayRequest.externalAddressSpec` (alloc+bind внешний Address в ОДНОЙ Operation у owner; снимает chicken-and-egg «Address-before-Gateway»). Форма — **общий `AddressSpec`** (см. Rule 9): `{ addressFamily, addressPoolId, requestedAddress? }`. **Пул резолвится через `AddressService.ListPlaceableExternalPools` → `requestFragment` вставляется в `externalAddressSpec` byte-for-byte** (тот же key-set — discovery-фрагмент paste-ready).
- Gateway-type каталог — **статический inline enum** (не RPC).
- Держит external Address → эмитит `usedBy°` типа `vpc.gateway` на ту Address-строку (Rule 4 shared enum).
- Delete while referenced by `RouteTable.staticRoutes[].natGatewayId` → `FAILED_PRECONDITION`.

---

## NetworkInterface (NIC)

First-class. `usedBy°` polymorphic; placement self-describing. **Create — poll** (не op-in-response: NIC несёт lifecycle-присутствие `usedBy`/dangling, в отличие от statusless-сиблингов). One-shot Create может inline `addressSpecs` (allocate+attach IPs одной Operation); уже существующий/reserved Address вешается через `AssociateAddress`.

```jsonc
{
  "id": "nic6q2h8k4m1n0p3r",             // ° prefix nic
  "projectId": "prjb3n7k1x9q2m5t8",
  "subnetId": "subt4k8n2q0m5v9h1",       // within-service FK → subnets(id) RESTRICT; immutable (placement anchor)
  "networkId": "netv8f3k2q9m4t1n7",      // ° derived from subnet
  "zoneId": "zone-nova-a",               // ° derived from subnet (self-describing for cross-service coherence)
  "regionId": "region-nova",             // ° derived from subnet
  "name": "eth0-web01", "description": "", "labels": {},
  "securityGroupIds": ["scg5h2t9k0m3q7v1n"],       // DECLARED set (tenant intent); empty on Create ⇒ inherits default; LIVE-mutable
  "effectiveSecurityGroupIds": ["scg5h2t9k0m3q7v1n"],  // ° RESOLVED operative set — echoes network.defaultSecurityGroupId° when declared empty
  "macAddress": "02:1a:4f:8c:2d:e0",     // auto-generated if omitted; tenant-facing intent; immutable after Create
  "addressIds": ["adrk9m2t7q4n1v8h3", "adr3f7k1t9m2q5v8h"],  // ° associated Address rows (v4 + v6 dualstack); dereference for the IP
  "primaryAddressIds": ["adrk9m2t7q4n1v8h3"],       // ° per-family primary Address refs (source of truth = Address; no echoed IP string)
  "usedBy": {                             // ° Referrer, dangling-safe
    "type": {"value":"compute.instance","displayName":"Compute Instance"},
    "id": "cpni7k2m9t4q1n8v3", "name": "web-01"   // name° = mirror, source of truth = compute.Instance
  },
  "createdAt": "2026-07-19T08:20:11Z"    // °
}
```

- **`securityGroupIds` (declared) vs `effectiveSecurityGroupIds°` (resolved):** пустой declared на Create ⇒ операционный firewall = `network.defaultSecurityGroupId°`, и это **видно из тела NIC** через `effectiveSecurityGroupIds°` (empty-means-inherit больше не скрытая связь — не нужно кросс-фетчить Network default). Declared-набор round-trip'ится как есть (tenant intent). Явно перечисленные SG заменяют дефолт; каждый validated same-network.
- **IP-строки не эхаются:** `primaryV4Address`/`primaryV6Address` (echoed, stale-able дубли Address-истины) сняты. NIC несёт только **refs** — `addressIds°` + `primaryAddressIds°`; кому нужен IP, разыменовывает Address-id, который уже держит (single source of truth = Address).
- Delete while `usedBy` non-empty → `FAILED_PRECONDITION`.
- No auto-NIC on Instance.Create; NIC — explicit CRUD-ресурс. `usedBy` пишется CAS-ом со стороны compute при attach (`InternalNetworkInterfaceService.SetReference`); VPC compute обратно не зовёт (acyclic).
- **AssociateAddress / DisassociateAddress** (public async) — CAS-биндят УЖЕ существующий/reserved `adr…` ↔ NIC (`used_by IN ('',$ours)`): tenant-путь «выделил static EIP → повесил на NIC» и re-association (перенос EIP между NIC). owner=VPC, ацикличность holds.
- **`addressSpecs[]` семантика (зеркалит compute inline-spec placement-inheritance — одна `*Specs`-семантика на весь продукт):** для internal-пути `addressSpec.subnetId` **пуст ⇒ наследует `NIC.subnetId`**; непуст и **≠ `NIC.subnetId`** ⇒ `INVALID_ARGUMENT "internal address subnet must match the interface subnet"` (cross-subnet/zone internal IP не принимается молча). Форма — общий `AddressSpec` (Rule 9): `{ addressFamily, subnetId?, addressPoolId?, requestedAddress?, primary? }`.
- **Primary среди нескольких same-family:** primary — тот, у кого в spec/associate `primary:true`; если не задан явно — первый ассоциированный этого family. `primaryAddressIds°` — derived-refs (source of truth = Address).
- **List filter whitelist:** `name=`, `zoneId=`, `networkId=`.

> **Handoff compute↔vpc (модель неизменна — spine: VPC владеет присутствием, compute референсит `nicId`). Две co-canonical двери:**
> - **NIC-first** — `NetworkInterfaceService.Create` заранее, затем `nicId` в `compute.Instance.Create`. Путь VPC-only-читателя «prepare a NIC for an instance».
> - **inline** — `compute.Instance.Create.networkInterfaceSpecs[]` = `{ subnetId, securityGroupIds[], addressSpecs[] (общий AddressSpec), primary? }` — compute-saga фан-аутит их в VPC (Create NIC + alloc Address у owner) одной Operation. Схема показана здесь (в VPC-доке self-serve, не только на compute-стороне).
>
> Обе — **равноправны**, дефолтной нет; выбирай по тому, нужен ли NIC до инстанса. `usedBy` в обоих случаях пишет **compute** через `InternalNetworkInterfaceService.SetReference` (eventually-consistent, bounded client-retry на кратком окне). Same-zone-инвариант Instance↔NIC энфорсит **compute-сторона**, читая self-describing `NIC.zoneId°`/`regionId°` (REGIONAL/anycast NIC → зона consumer'а ∈ регион, не zone-equality).
>
> **REGIONAL NIC ↔ compute ZONE_SPREAD-реконсиляция:** spread-инстанс, растянутый по N зонам, прицепляет **N ZONAL NIC** (по одному на зону, каждый в same-zone subnet) — **не** один anycast/REGIONAL NIC. REGIONAL/anycast NIC применим для regional-subnet-workload, зоне-независимого by construction; он не «покрывает» spread. Маппинг spread→NIC принадлежит compute-стороне, но VPC-контракт фиксирует: одна NIC = одна subnet = один placement-scope.

---

## AddressPool — Internal* only (`:9091`)

Admin/kacho-only. Не на публичной поверхности. Cloud/zone-level (не project-level).

```jsonc
{
  "id": "aplm4k8t2q9n0v3h7",             // ° prefix apl
  "name": "ext-v4-nova-a", "description": "", "labels": {},
  "kind": {"value":"EXTERNAL_V4","displayName":"External IPv4 pool"},  // internal_v4 | external_v4 | external_v6 …
  "zoneId": "zone-nova-a",               // nullable ("" = cross-zone/global default)
  "ipv4CidrBlocks": ["203.0.113.0/24"],  // mutated via :add-cidr-blocks / :remove-cidr-blocks only
  "ipv6CidrBlocks": [],
  "isDefault": true,                      // UNIQUE(coalesce(zoneId,''),kind) WHERE isDefault
  "createdAt": "2026-07-19T08:12:00Z"    // °
}
```

Resolution chain для tenant Address.Create: `network_default` → `zone_default` → `global_default`. CIDR-overlap per kind — EXCLUDE gist (`address_pool_cidrs`) → **всегда** `FAILED_PRECONDITION "address pool CIDRs can not overlap"`.

---

## RPC surface

Все RPC на **обоих** листенерах несут per-RPC authz-Check (`InternalIAMService.Check`) с object-scoped `scope_extractor` (target→project), fail-closed; транспорт mTLS (svc→svc) / TLS+JWT (edge). `Get`/`List`/discovery = **sync**; `Create`/`Update`/`Delete`/`:verb` = **async → Operation**. `validateOnly:true` на любой мутирующей RPC = **sync dry-run** (полная валидация, без Operation, без state-gate) → `{warnings[], resolved{…}}`.

**Async-класс мутаций** (колонка ниже): **op-in-response** = statusless-ресурс, `Operation` приходит `done:true` + **полное тело в `Operation.response`**, follow-up GET не нужен; **poll** = клиент поллит `OperationService.Get`. Statusless = *durable, но readiness НЕ наблюдается контрактом* (никакого фейкового `status`-поля).

### Public (`kacho-vpc:9090` → edge REST)

| Service | Method | Sync/Async | Async-class | REST |
|---|---|---|---|---|
| **NetworkService** | Get / List | sync | — | `GET /vpc/v1/networks/{id}` · `GET /vpc/v1/networks` |
| | Create / Update / Delete | **async** | **op-in-response** | `POST` · `PATCH /{id}` · `DELETE /{id}` |
| | AddCidrBlocks / RemoveCidrBlocks | **async** | op-in-response | `POST …/{id}:add-cidr-blocks` · `:remove-cidr-blocks` |
| | SetDefaultSecurityGroup / SetDefaultRouteTable | **async** | op-in-response | `POST …/{id}:set-default-security-group` · `:set-default-route-table` |
| | ListSubnets / ListSecurityGroups / ListRouteTables / ListGateways | sync | — | `GET …/{id}/{subnets\|securityGroups\|routeTables\|gateways}` |
| | ListOperations | sync | — | `GET …/{id}/operations` |
| **SubnetService** | Get / List *(filter `name=`,`zoneId=`,`networkId=`)* | sync | — | `GET /vpc/v1/subnets/{id}` · `GET /vpc/v1/subnets` |
| | Create / Update / Delete | **async** | **op-in-response** | `POST` · `PATCH /{id}` · `DELETE /{id}` |
| | AddCidrBlocks / RemoveCidrBlocks | **async** | op-in-response | `POST …/{id}:add-cidr-blocks` · `:remove-cidr-blocks` |
| | ListPlaceableZones *(discovery, dynamic)* | sync | — | `GET /vpc/v1/subnets:placeableZones` |
| | SuggestCidrBlocks *(discovery, dynamic)* | sync | — | `GET /vpc/v1/subnets:suggestCidr` *(`networkId=`,`prefixLen=`,`family=`)* |
| | ListLaunchableSubnets *(discovery, dynamic)* | sync | — | `GET /vpc/v1/subnets:launchable` *(`zoneId=`,`networkId=`)* |
| | ListOperations | sync | — | `GET …/{id}/operations` |
| **SecurityGroupService** | Get / List | sync | — | `GET /vpc/v1/securityGroups/{id}` · `…` |
| | Create / Update / Delete | **async** | **op-in-response** | `POST` · `PATCH /{id}` · `DELETE /{id}` |
| | AddRules / RemoveRules *(collection verb-pair)* | **async** | op-in-response | `POST …/{id}:add-rule` · `:remove-rule` |
| | UpdateRule *(single, OCC per-rule `expectedVersion`)* | **async** | op-in-response | `PATCH …/{id}/rules/{ruleId}` |
| | ListOperations | sync | — | `GET …/{id}/operations` |
| **RouteTableService** | Get / List · Create / Update / Delete | sync · **async** | **op-in-response** | `/vpc/v1/routeTables…` |
| | AddStaticRoutes / RemoveStaticRoutes *(verb-pair; edits live/default RT; coherence-gated)* | **async** | op-in-response | `POST …/{id}:add-route` · `:remove-route` |
| **AddressService** | Get / List *(filter `subnetId=`,`address=`)* | sync | — | `GET /vpc/v1/addresses/{id}` · `GET /vpc/v1/addresses` |
| | Create / Update / Delete | **async** | **poll** | `POST` · `PATCH /{id}` · `DELETE /{id}` |
| | ListPlaceableExternalPools *(discovery, dynamic)* | sync | — | `GET /vpc/v1/addresses:placeableExternalPools` |
| **GatewayService** | Get / List · Create / Update / Delete | sync · **async** | **op-in-response** | `/vpc/v1/gateways…` (Create carries `externalAddressSpec`) |
| **NetworkInterfaceService** | Get / List *(filter `name=`,`zoneId=`,`networkId=`)* | sync | — | `GET /vpc/v1/networkInterfaces/{id}` · `…` |
| | Create / Update / Delete | **async** | **poll** *(usedBy/dangling lifecycle — не statusless)* | `POST` · `PATCH /{id}` · `DELETE /{id}` |
| | AssociateAddress / DisassociateAddress | **async** | poll | `POST …/{id}:associate-address` · `:disassociate-address` |
| **OperationService** | Get / List | sync | — | `GET /vpc/v1/operations/{id}` · `GET /vpc/v1/operations` |

*Removed (contract-removal): все `:move` / `:relocate`, NIC `:attach`/`:detach`, `AddressService.ListBySubnet`, `AddressService.GetByValue`/`:byValue` (→ `List?filter=address=`), `SubnetService.ListUsedAddresses` (→ `AddressService.List?filter=subnetId`), discovery-RPC `ListRuleProtocols` / `ListGatewayTypes` (→ static inline enum), `SecurityGroupService.UpdateRules` (replace-set → verb-pair `:add-rule`/`:remove-rule`), Address `scope` **как write-поле** (→ derived `scope°` из binding-ref), SG-level rules `version` (→ per-rule OCC only), SG `defaultForNetwork°` (→ derivable из Network default), NIC `primaryV4Address°`/`primaryV6Address°` (→ `primaryAddressIds°` refs). `projectId` immutable. Default-designation перенесён Internal→public (`SetDefaultSecurityGroup`/`SetDefaultRouteTable`). `RouteTable.staticRoutes[].gatewayId` → `natGatewayId`. Address `lifecycle` → `retention`.*

### Internal (`kacho-vpc:9091`, cluster-internal, **не** на external TLS)

| Service | Purpose |
|---|---|
| **InternalNetworkService** | `GetNetwork` (full projection **incl. `vrfId`** + underlay) |
| **InternalAddressService** | `Allocate` (ephemeral) · `SetReference`/`ClearReference` (atomic CAS on `usedBy`) — called by compute/nlb |
| **InternalNetworkInterfaceService** | `GetNetworkInterface` (full projection — host-wiring/underlay) · `SetReference`/`ClearReference` (atomic CAS on `usedBy`, **байт-симметрично** InternalAddressService) — compute пишет NIC-ребро тем же кодом, что Address-ребро |
| **InternalAddressPoolService** | AddressPool CRUD + `:add-cidr-blocks`/`:remove-cidr-blocks` (admin-only) |

---

## Discovery-каталоги (sync, рядом с launch — только **динамические**, зависящие от состояния)

**`SubnetService.ListPlaceableZones`** → `GET /vpc/v1/subnets:placeableZones` — фан-аут в geo, где можно **создать** ZONAL/REGIONAL subnet; каждый item — готовый фрагмент для `CreateSubnetRequest`:

```jsonc
{ "zones": [
  { "zoneId": "zone-nova-a", "regionId": "region-nova", "displayName": "Nova / Zone A",
    "requestFragment": { "zoneId": "zone-nova-a" } },
  { "regionId": "region-nova", "displayName": "Nova (regional / anycast)",
    "requestFragment": { "regionId": "region-nova" } }
] }
```

**`SubnetService.SuggestCidrBlocks`** → `GET /vpc/v1/subnets:suggestCidr?networkId=netv8f3k2q9m4t1n7&prefixLen=24&family=V4` — свободные под-диапазоны супернета (закрывает «слепое» вырезание CIDR); item несёт готовый фрагмент:

```jsonc
{ "suggestions": [
  { "cidr": "10.20.4.0/24", "family": "V4", "requestFragment": { "ipv4CidrPrimary": "10.20.4.0/24" } },
  { "cidr": "10.20.5.0/24", "family": "V4", "requestFragment": { "ipv4CidrPrimary": "10.20.5.0/24" } }
], "conflictingRanges": ["10.20.0.0/24", "10.20.8.0/24"] }
```

**`SubnetService.ListLaunchableSubnets`** → `GET /vpc/v1/subnets:launchable?zoneId=zone-nova-a&networkId=netv8f3k2q9m4t1n7` — зеркально ListPlaceableZones, но для **attach-to-existing**: существующие subnet в зоне X со свободной ёмкостью + paste-ready `requestFragment.subnetId` под `NIC.Create` (закрывает самый частый compute-launch: «прицепить NIC к существующей subnet в зоне X с headroom» — `List?zoneId=` даёт subnet, но не free-IP запас):

```jsonc
{ "subnets": [
  { "subnetId": "subt4k8n2q0m5v9h1", "name": "app-tier-a", "networkId": "netv8f3k2q9m4t1n7",
    "zoneId": "zone-nova-a", "placementType": "ZONAL",
    "freeAddressCount": 244, "hasCapacity": true,                 // ° derived
    "requestFragment": { "subnetId": "subt4k8n2q0m5v9h1" } },
  { "subnetId": "sub7t2q9n0v3h4k8m", "name": "app-tier-a-2", "networkId": "netv8f3k2q9m4t1n7",
    "zoneId": "zone-nova-a", "placementType": "ZONAL",
    "freeAddressCount": 3, "hasCapacity": true,
    "requestFragment": { "subnetId": "sub7t2q9n0v3h4k8m" } }
] }
```

**`AddressService.ListPlaceableExternalPools`** → `GET /vpc/v1/addresses:placeableExternalPools` — зеркально ListPlaceableZones: показывает **результат** placement (zonal vs anycast external-egress), не инфру пула (free-list/CIDR/топология — Internal*). `requestFragment` **paste-ready** и в `Address.Create`, и в `Gateway.externalAddressSpec` (общий `AddressSpec` key-set):

```jsonc
{ "pools": [
  { "displayName": "External IPv4 — Nova / Zone A", "placement": "zonal",
    "zoneId": "zone-nova-a", "regionId": "region-nova",
    "requestFragment": { "addressFamily": "V4", "addressPoolId": "aplm4k8t2q9n0v3h7" } },
  { "displayName": "External IPv4 — Nova (anycast)", "placement": "anycast",
    "regionId": "region-nova",
    "requestFragment": { "addressFamily": "V4", "addressPoolId": "apl7t2q9n0v3h4k8m" } }
] }
```

> **Не-RPC (статический inline enum в схеме/OpenAPI):** rule-протоколы (`{value,displayName,defaultPorts}` — TCP/UDP/ICMP(`{type,code}`)/ICMPV6/ANY) и gateway-типы (`{value,displayName}` + skeleton type-specific блока) — набор не зависит от состояния, живёт как enum-глосса, а не отдельная RPC.

---

## Правила (нормативно)

1. **Flat resource, no envelope.** Domain-поля на верхнем уровне; никаких `spec/status/metadata/resourceVersion/generation/finalizers`. Output-only поля помечены `°` и игнорируются на write; write-only входы (`requestedAddress`, `*Spec`-поля) сервер потребляет и **не эхает** на read. **Enum-форма единообразна:** на **write** — голая строка `value` (`"V4"`, `"INGRESS"`, `"NAT_GATEWAY"`); на **read** — inline `{value, displayName°}` (superset — для re-PATCH бери `.value`; объект на write **не** принимается). **Исключение:** чистые derived read-only дискриминаторы (`placementType°`) — голый токен без обёртки (обёртка не несёт информации сверх токена).

2. **Async-модель + op-in-response (product-wide spine, не VPC-диалект).** `Get`/`List`/discovery — sync. `Create`/`Update`/`Delete`/`:verb` → `Operation`; id ресурса доступен в `Operation.metadata` **сразу** (до `done`). Клиент поллит `OperationService.Get` (`GET /vpc/v1/operations/{id}`). **Для statusless control-plane-ресурсов (durable-immediately: Network/Subnet/SG/RouteTable/Gateway) `Operation` приходит `done:true` уже в ответе Create, И `Operation.response` (Any) несёт ПОЛНОЕ созданное тело со всеми derived `°`-полями — follow-up GET НЕ требуется** (напр. `Network.Create.response` эхает `defaultSecurityGroupId°`/`defaultRouteTableId°` на момент создания). Это **продукт-широкое** правило («statusless control-plane resource → `done:true` + полное тело инлайн»), сериализуется **идентично** во всех модулях (compute/nlb/storage). Ресурсы с lifecycle-присутствием (NIC — `usedBy`/dangling) — **poll**, не op-in-response. Statusless = *durable, readiness НЕ наблюдается контрактом* — **никакого фейкового `status`-поля.** **Watch RPC нет.**

3. **`Operation.done` = DURABLE, не downstream-видимость.** `done=true` ⇔ строка закоммичена. owner-tuple в OpenFGA / зеркала `usedBy.name°` материализуются eventually-consistent в ограниченном окне. Запрещён серверный confirm-барьер на видимость (ban #9, phantom-ресурс). «Создал→сразу Get/Update/Delete/Associate своего» → **bounded client-retry** на кратком 403/404-окне.

4. **Reference law — три класса, не смешивать.**
   - within-service (`networkId`, `subnetId`, `routeTableId`, `securityGroupIds`, `staticRoutes.natGatewayId`, `natGateway.externalAddressId`, Address `subnetId`/`addressPoolId`) → flat `<x>Id` + **DB FK**. Никогда не референсифицировать ради единообразия.
   - scope/placement-координата (`projectId`, `zoneId`, `regionId`) → flat slug + **peer-validate** (iam/geo) hard-fail (`Unavailable` если peer down).
   - dependency на чужой owned-ресурс (`usedBy`) → first-class **`Referrer{ type:{value,displayName}, id, name° }`** — polymorphic, graceful-dangling (референт удалён → DETACHED/degraded, не паника; `name°` — output-only зеркало, source of truth = owner). Токены `type` — версионированный shared-каталог `kacho.cloud.common.v1.ReferrerType` (kacho-proto, явный owner): `compute.instance`, `vpc.networkInterface`, `vpc.gateway`, `nlb.listener`, … — с inline-глоссой; **`vpc.gateway` присутствует** (NAT-Gateway держит external Address). Drift/typo между модулями отсекается общим enum, не bare-строкой.

5. **Placement-coherence (все placement-scoped связи когерентны, `data-integrity.md`).** Дискриминатор `placementType° ∈ {ZONAL,REGIONAL}` — **server-derived, read-only, голый токен** (на write нет — задаётся ровно один из `zoneId`/`regionId`, DB-CHECK взаимоисключает) на Subnet **и Gateway**. ZONAL↔ZONAL — та же `zoneId`; REGIONAL — anycast, из зональной проверки исключён by construction. Consumers (Address/NIC) зону **наследуют** через `subnetId` и **сами self-describing** — несут derived `zoneId°`/`regionId°` (source of truth = Subnet), чтобы cross-service edge (compute Instance↔NIC same-zone) читал placement с owner-payload без double-hop. **Subnet↔Gateway-через-shared-RT — тоже покрыт:** RT network-scoped/cross-zone, поэтому shared default-route target (`0.0.0.0/0`) **обязан быть REGIONAL** gateway; `AddStaticRoutes` отвергает `0.0.0.0/0 → ZONAL-gatewayId` на RT, обслуживающем подсети вне зоны gateway → `FAILED_PRECONDITION "gateway is in zone %s, route table serves subnets in zone %s"` (закрывает silent cross-zone/black-hole egress). Enforcement placement — в точках link (Subnet/pool + RT↔Gateway). Zone-mismatch → `"<A> is in zone %s, <B> zone is %s"` → `FAILED_PRECONDITION`/`INVALID_ARGUMENT`.

6. **Two-projection.** Инфра-чувствительное (`vrfId`, underlay/carrier, host-iface/netns/wiring, numeric-infra-id, AddressPool free-list, топология) — **только** `Internal*` :9091. Публичный ресурс их не несёт даже как `°`. Публичная поверхность = намерение + результат. `macAddress` — tenant-facing intent, остаётся публичным. Обозначение default-SG/RT — намерение (не инфра), поэтому re-point публичный (`SetDefaultSecurityGroup`/`SetDefaultRouteTable`), а free-list/underlay пула — Internal*.

7. **AuthN+AuthZ на КАЖДОМ RPC обоих листенеров.** mTLS (svc→svc) / TLS+JWT (edge); per-RPC `InternalIAMService.Check` с object-scoped `scope_extractor` (target→project), fail-closed. Internal :9091 не освобождён. Публичный `List*` фильтрует через listauthz.

8. **`validateOnly:true` — sync dry-run.** Полная валидация (peer-validate zone/pool/SG-target, coherence, CIDR ⊆ supernet, CIDR-overlap precheck) **без** мутации, **без** Operation, **без** state-gate (можно на живом ресурсе). Возвращает `{warnings[], resolved{…}}` (echo выведенных значений: resolved pool, `addressFamily`, `scope`, allocated-CIDR preview, `suggestedCidr`/`conflictingRanges` для Subnet.Create, derived `networkId`/`placementType`).

9. **One-shot Create + единый `AddressSpec` (DRY, один input-контракт «выделить IP»).** Зависимые под-ресурсы через `*Spec(s)`, развёрнутые в ОДНОЙ Operation у owner-сервиса. **Единое переиспользуемое proto-сообщение `kacho.cloud.vpc.v1.AddressSpec` = `{ addressFamily, subnetId? | addressPoolId?, requestedAddress?, primary? }`** (= standalone `Address.Create` body минус scope-coords) встраивается **verbatim** в:
   - `NetworkInterface.Create.addressSpecs[]` (internal-путь: `subnetId` пуст ⇒ наследует `NIC.subnetId`; ≠ `NIC.subnetId` ⇒ `INVALID_ARGUMENT "internal address subnet must match the interface subnet"` — та же inline-spec placement-inheritance, что у compute).
   - `Gateway.Create.externalAddressSpec` (external-путь: `addressPoolId` — из `ListPlaceableExternalPools.requestFragment`, paste-ready тем же key-set).
   - `SecurityGroup.Create.ruleSpecs[]` = `{ direction, protocol, fromPort, toPort, cidrBlocks[] | securityGroupId, description }` (seed rules).
   - inline default-SG/RT при `Network.Create` (система).
   `ListPlaceableExternalPools.requestFragment` — вставляется и в `Address.Create`, и в `Gateway.externalAddressSpec` без переформатирования (near-but-not-identical fragment устранён). Не заставлять делать 3–4 вызова там, где логичен один.

10. **Discovery рядом с мутацией — только для динамики.** Sync-каталог (`ListPlaceableZones`, `SuggestCidrBlocks`, `ListLaunchableSubnets`, `ListPlaceableExternalPools`) сидит у того же сервиса, зависит от состояния (geo fan-out / свободный CIDR супернета / free-IP headroom существующих subnet / pool availability), item несёт `requestFragment`. Статические наборы (rule-протоколы, gateway-типы) — inline enum-глосса, не RPC.

11. **Update mutability-классы (единообразно, exhaustive).** LIVE-mutable: `name`/`description`/`labels`; SG `rules` (только через verb-pair `:add-rule`/`:remove-rule` + single `UpdateRule` с per-rule `expectedVersion`); NIC `securityGroupIds` (пустой на Create ⇒ наследует default-SG, resolved виден в `effectiveSecurityGroupIds°`); Subnet `routeTableId`; RouteTable `staticRoutes` (через `:add-route`/`:remove-route`, coherence-gated); Address `retention` (`EPHEMERAL↔RESERVED`, reap только на `usedBy` non-empty→empty). Immutable (reject **до** `UpdateMask`, порядок: immutable-switch → UpdateMask): `projectId`, `networkId`, Subnet `placementType`(derived,unwritable)/`zoneId`/`regionId`/`ipv4CidrPrimary`, SG `networkId`, Gateway `networkId`/`type`, **NIC `subnetId`/`macAddress`** (placement-anchor + сетевой identity), Address `addressFamily`/binding-ref/`requestedAddress` → `"<field> is immutable after <R>.Create"`. CIDR-списки (Network/Subnet supernet, AddressPool) — не через Update, а через `:add-cidr-blocks`/`:remove-cidr-blocks`. Derived `°` (`placementType`, `scope`, `networkId`/`zoneId`/`regionId` на NIC, `primaryAddressIds`, `addressIds`, `effectiveSecurityGroupIds`, `address`) — не пишутся вовсе. Пустой mask → full PATCH mutable-полей; immutable из тела silently игнорируются.

12. **Within-service инварианты — на DB-уровне (ban #10).** FK (`networkId`/`subnetId`/`routeTableId`/`natGatewayId`/Address binding-ref), partial-UNIQUE (`(project,name)`, `(pool,ip)`), EXCLUDE gist (subnet no-overlap, pool CIDR-overlap), CHECK (subnet-CIDR ⊆ network supernet, placement взаимоисключение `zoneId XOR regionId`, `retention`-дискриминатор, Address binding-ref взаимоисключение `subnetId XOR addressPoolId`), xmin-OCC (per-rule SG version), CAS (`usedBy` attach/associate, `used_by IN ('',$ours)`). internal/external адреса — **не** отдельная колонка, а следствие binding-ref (`scope°` — read-only эхо, redundancy устранена by construction). Никакого software check-then-act. Concurrent-race integration-тест (testcontainers) на каждый спорный путь.

13. **Единый тон ошибок (часть контракта), детерминированный маппинг.** `"<Resource> <id> not found"` (NOT_FOUND) · `"<field> is immutable after <R>.Create"` (INVALID_ARGUMENT) · `"network is not empty"` (FAILED_PRECONDITION) · **binding/placement mutual-exclusion — spoken, не немой DB-CHECK:** `"exactly one of subnetId, addressPoolId must be set"` / `"exactly one of zoneId, regionId must be set"` (INVALID_ARGUMENT) · `"placementType is server-derived; set zoneId or regionId instead"` (INVALID_ARGUMENT, explicit reject, не silent-ignore) · `"internal address subnet must match the interface subnet"` (INVALID_ARGUMENT) · **coherence через-RT:** `"gateway is in zone %s, route table serves subnets in zone %s"` (FAILED_PRECONDITION) · **CIDR-overlap (subnet ИЛИ pool) → всегда `FAILED_PRECONDITION`** (`"subnet CIDRs can not overlap"` / `"address pool CIDRs can not overlap"`) · **UNIQUE(name) → строго `ALREADY_EXISTS`** (никакой развилки «по контексту») · SG rule OCC-mismatch → `"security group rule was modified concurrently"` (FAILED_PRECONDITION) · peer down → UNAVAILABLE (fail-closed) · INTERNAL — фиксированный opaque-текст, **без pgx/SQL-leak**. Malformed-id → `INVALID_ARGUMENT "invalid <res> id '<X>'"` **первым стейтментом** RPC (`corevalidate.ResourceID`) до repo. Валидация формата/pagination — **ДО** listauthz empty-grant short-circuit.

14. **Формат / prefix-закон.** JSON camelCase; id = `<3-char type-prefix> + crockford-base32` — **префикс однозначно кодирует тип**: `net` Network · `sub` Subnet · `scg` SecurityGroup · `rtb` RouteTable · `gwy` Gateway · `nic` NetworkInterface · `adr` Address · `apl` AddressPool. Malformed-id-первым-стейтментом ловит и **wrong-type** (не только wrong-length): bare-id через seam compute↔vpc / nlb↔vpc routable по типу без lookup. UNIQUE(project,name) (partial-index допускает пустое name); все timestamps truncate до секунд (включая под-записи rules/staticRoutes). **CIDR-именование едино во всём модуле:** `ipv4CidrBlocks`/`ipv6CidrBlocks` (Network/Subnet/AddressPool), Subnet primary — `ipv4CidrPrimary`/`ipv6CidrPrimary`; **роль одноимённого поля разная** (Network `ipv4CidrBlocks[]` = declared supernet, у Subnet есть `ipv4CidrPrimary` — anchor-subset + доп. `ipv4CidrBlocks[]`) — задокументировано в Subnet-прозе, не обобщать. Дрейф `v4…` vs `ipv4…` устранён.

15. **Vendor-agnostic (ban #2).** Никаких имён чужих облаков в полях/типах/значениях/gloss. Родовые сетевые термины (`NAT gateway`, `internal/external IPv4`, `isolated VPC / routing domain`) — допустимы (не бренды). Узнаваемость — знакомой ФОРМОЙ (flat + Operation + Referrer + placementType-дискриминатор) и discoverable reachability-картой, не брендом; отдельного internet-gateway-ресурса нет by design (как и NACL / VPC-peering / DHCP-options — см. by-design omissions в Ментальной модели).
