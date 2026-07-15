# Sub-phase nlb-vpc-zone-coherence — Acceptance

> Статус: DRAFT
> Дата: 2026-07-12
> Ревьюер: acceptance-reviewer (ожидает первого прохода)
> Эпик/тикет: KAC-<TBD> (завести до старта кода; тип `fix`/hardening, backend-only)
> Backend: `kacho-nlb` (GAP-1, GAP-2) · `kacho-vpc` (GAP-3) · **proto НЕ меняется** (см. §«Proto / scope»)
> Источники (нормативно, не дублируются в тело — ссылки):
> - `.claude/rules/data-integrity.md` §«Placement-coherence — ВСЕ ресурсы связываются зонально ИЛИ регионально» (главный источник инварианта + канон error-текстов)
> - `.claude/rules/data-integrity.md` §«Cross-domain ссылки» (peer-validate на request-path, fail-closed `Unavailable`, ban #4/#8)
> - `.claude/rules/api-conventions.md` §«Error-format» (коды/тексты), §«Форма ресурса» (async Operation)
> - `docs/specs/02-data-model-and-conventions.md` §14 (коды ошибок)
> - vault: `[[resources/nlb-load-balancer]]`, `[[resources/vpc-subnet]]`, `[[resources/vpc-address]]`,
>   `[[resources/geo-zone]]`, `[[resources/geo-region]]`,
>   `[[edges/nlb-to-vpc-subnet-validation]]`, `[[edges/nlb-to-vpc-byo-address]]`,
>   `[[edges/nlb-to-geo-region-validate]]`, `[[edges/vpc-to-geo-zone-validate]]`
> - placement-модель Subnet введена `docs/specs/sub-phase-vpc-redesign-kac239-acceptance.md`
>   (`placement_type ∈ {ZONAL(zone_id) | REGIONAL(region_id)}`, DB-CHECK `subnets_placement_payload_chk`)

---

## 0. Обзор

Аудит backend-валидации нашёл три дыры в **placement-когерентности** — местах, где Kachō
позволяет связать placement-scoped ресурсы из **разной зоны/региона** (нарушение
`data-integrity.md §Placement-coherence`). Все три — на request-path, наблюдаемы через
публичный API, чинятся **только backend-валидацией** (никаких изменений proto/схемы БД):

1. **GAP-1 (kacho-nlb) — ZONAL dualstack same-zone.** Для ZONAL LoadBalancer v4-VIP и v6-VIP
   обязаны быть в **одной зоне**. Сейчас `CreateLoadBalancerUseCase.resolveSources`
   (`internal/apps/kacho/api/loadbalancer/create.go:180-194`) сверяет только «одна **сеть**»
   для dualstack, а зону — нет. Разнозональный dualstack проходит.
2. **GAP-2 (kacho-nlb) — region-coherence VIP↔LB.** subnet/address, из которого аллоцируется VIP,
   обязан быть в регионе `lb.region_id`. Сейчас `regionClient.Get` (`create.go:277-281`) проверяет
   только **существование** региона, а `subnetPlacementMatches` (`create.go:209-212`, `246-257`) —
   только **тип** placement (ZONAL vs REGIONAL), не регион. VIP из чужого региона проходит.
3. **GAP-3 (kacho-vpc) — external `Address.zone_id` не валидируется в geo.** `Subnet` и `AddressPool`
   при Create валидируют `zone_id`/`region_id` через `geo.v1.ZoneService.Get` / `RegionService.Get`,
   а external `Address` — **нет** (`CreateAddressUseCase.Execute`,
   `internal/apps/kacho/api/address/create.go`; `ExternalAddrSpec.ZoneID` не проверяется). External
   Address с несуществующей `zone_id` создаётся.

Все три — **cross-service peer-validate на request-path** (`nlb→vpc`, `nlb→geo`, `vpc→geo`), а не
within-service DB-инварианты: через границу сервиса FK невозможен (DB-per-service, ban #4/#8), поэтому
проверка выполняется sync-вызовом owner-API и **fail-closed** — недоступность peer'а → `UNAVAILABLE`,
мутация НЕ выполняется (`data-integrity.md §Cross-domain` п.2). Заказчик проверяет только финальный
smoke/e2e (шаг 7).

### Placement-модель (краткая справка; нормативка — в rule-модуле)

- **Subnet** — каноничный placement-якорь: `placement_type = ZONAL` (несёт `zone_id`, `region_id=''`)
  **XOR** `REGIONAL` (несёт `region_id`, `zone_id=''`; anycast, зоне-независим). Взаимоисключение —
  DB-CHECK `subnets_placement_payload_chk`.
- **Address** зону **не несёт сам** (для internal) — наследует через `subnet_id`. External Address
  несёт `zone_id` в spec (зональный external из зонального пула) **либо** `zone_id=''` (anycast, external
  из global-пула).
- **LoadBalancer** зону **не несёт** (by design; поля 15/18 reserved). Зональность LB выражена
  `placement_type ∈ {ZONAL | REGIONAL(anycast)}` (только для INTERNAL) + `region_id`. `resolvePlacement`
  требует ZONAL|REGIONAL для INTERNAL и запрещает placement для EXTERNAL — поэтому **ZONAL LB ⟹ INTERNAL**,
  а его subnet/address-source обязаны быть ZONAL (уже энфорсит `subnetPlacementMatches`).
- **Anycast/REGIONAL-исключение:** REGIONAL-ресурс (`zone_id=''`) из **зональной** проверки исключён
  **by construction** (сравнивать не с чем) — остаётся только **региональная** проверка.

---

## Proto / scope

- **Proto НЕ меняется.** Все нужные поля уже есть: `Subnet.placement_type` / `zone_id` / `region_id`
  (`kacho/cloud/vpc/v1/subnet.proto`), `CreateNetworkLoadBalancerRequest.placement_type` / `region_id` /
  `v4_source` / `v6_source` (`network_load_balancer_service.proto`), external `Address.zone_id`
  (`address_service.proto`). Работа — **чистая backend-валидация** + доработка nlb subnet-client
  (маппинг `region_id` REGIONAL-подсети + zone→region резолв ZONAL-подсети через `geo.ZoneService.Get`).
- **Схема БД НЕ меняется.** Проверки — cross-service peer-validate на request-path (не DB-CHECK/FK).
  DB-CHECK `subnets_placement_payload_chk` уже гарантирует «Subnet несёт ровно одно из zone/region»
  и здесь **не трогается**.
- Новые cross-service вызовы фиксируются в `polyrepo.md` только если появляется новое ребро; здесь все
  рёбра уже существуют (`nlb→vpc`, `nlb→geo`, `vpc→geo`) — обновляются лишь `edges/*` History-записи.

### Out of scope (граница — НЕ tech-debt)

- **EXTERNAL LB region-constraint по subnet.** EXTERNAL LB VIP — public (сети нет); underlying-зона
  деривится **из** `lb.region_id` (`deriveUnderlayZone`, `create.go:401-416`) → по построению in-region.
  Отдельной region-проверки для EXTERNAL public-VIP не добавляем (нечего сверять). GAP-2 — про
  **INTERNAL** LB (subnet/address-backed VIP).
- **Selection пула по зоне / ёмкость пула.** GAP-3 проверяет только **существование** `zone_id` в geo
  (как Subnet). «Зона существует, но пула в ней нет» — отдельный allocation-failure (async), не эта фича.
- **Ретроактивная миграция уже созданных incoherent-ресурсов.** Prod-раскатки нет; фикс — forward-only
  (новые Create отвергаются). Backfill/reconcile существующих — не в этой под-фазе (при появлении — отдельный тикет).
- **`update_mask`/Update-пути.** `placement_type`/`region_id`/`v4_source`/`v6_source` — immutable после
  Create (`network_load_balancer_service.proto:278-284`, reserved в Update); `Subnet.zone_id`/`region_id`
  immutable; external `Address` zone задаётся на Create. Поэтому фиксы — **только на Create-путях**.

---

## Группа 1 — nlb GAP-1: ZONAL dualstack — обе VIP в ОДНОЙ зоне

> Инвариант: `data-integrity.md §Placement-coherence` → «NLB(ZONAL) ↔ subnet/address (та же зона,
> **включая v4/v6 dualstack в ОДНОЙ зоне**)». Место фикса: `create.go` `resolveSources` (рядом с
> существующей same-network проверкой 180-194). Проверка **дополнительна** к same-network: одна Network
> может содержать ZONAL-подсети разных зон, поэтому same-network пройдёт, а same-zone — нет.
> `subnetPlacementMatches` уже гарантирует, что для ZONAL LB обе подсети — ZONAL (несут `zone_id`).

### Сценарий 1.1: ZONAL dualstack, v4 и v6 в разных зонах → sync INVALID_ARGUMENT

**ID:** ZC-NLB-ZONE-01-NEG-DUALSTACK-CROSS-ZONE

**Given** проект `P`, регион `R1`, зоны `R1-a` и `R1-b` (обе ∈ `R1`, seed geo)
**And** сеть `net-A` (`<netA>`) в `P`
**And** ZONAL-подсеть `sn-v4` в `net-A`, `placementType=ZONAL`, `zoneId=R1-a`, с v4-CIDR (`<snV4>`)
**And** ZONAL-подсеть `sn-v6` в `net-A`, `placementType=ZONAL`, `zoneId=R1-b`, с v6-CIDR (`<snV6>`)

**When** клиент вызывает `kacho.cloud.loadbalancer.v1.NetworkLoadBalancerService/Create`
(REST `POST /nlb/v1/networkLoadBalancers`) с payload:
  - project_id = `<P>`
  - region_id = `R1`
  - type = `INTERNAL`
  - placement_type = `ZONAL`
  - v4_source = `{ subnet_id: <snV4> }`   (зона `R1-a`)
  - v6_source = `{ subnet_id: <snV6> }`   (зона `R1-b`)

**Then** ответ — **синхронный** gRPC `INVALID_ARGUMENT` (Operation **НЕ** создаётся;
       `OperationService` новой записи не отдаёт)
**And** текст ошибки — **`"dualstack load balancer families must resolve to the same zone"`**
       (behaviour-level: assert точную строку, не только код)
**And** в `kacho_nlb.load_balancers` новая строка не появляется; VIP в vpc не аллоцируется.

> Design-note (текст ошибки): выбран **параллельно** соседней same-network-проверке
> `create.go:191-192` (`"dualstack load balancer families must resolve to the same network"`) —
> симметричный dual-family кейс, форма без embedded-значений консистентна с существующим sibling'ом.
> Rule-модуль даёт общий шаблон mismatch-зоны `"<A> is in zone %s, <B> zone is %s"`; если ревьюер
> предпочитает embedded-значения зон — заменить на `"dualstack load balancer families must be in the
> same zone (v4 %s, v6 %s)"` (первое `%s` — зона v4-семейства, второе — v6; порядок детерминирован:
> `resolveVipSources` собирает specs в порядке v4→v6). **Решение под ревью** — один из двух, зафиксировать в APPROVE.

### Сценарий 1.2: ZONAL dualstack, обе VIP в одной зоне → OK (happy path)

**ID:** ZC-NLB-ZONE-02-DUALSTACK-SAME-ZONE-OK

**Given** проект `P`, регион `R1`, зона `R1-a`
**And** сеть `net-A`; ZONAL-подсеть `sn-4` (`zoneId=R1-a`, v4-CIDR, `<sn4>`) и ZONAL-подсеть `sn-6`
       (`zoneId=R1-a`, v6-CIDR, `<sn6>`) — обе в `net-A`, **обе в зоне `R1-a`**

**When** клиент вызывает `Create` с `type=INTERNAL`, `placement_type=ZONAL`, `region_id=R1`,
       `v4_source={subnet_id:<sn4>}`, `v6_source={subnet_id:<sn6>}`

**Then** ответ синхронно содержит `operation.Operation` (непустой `id`, `done=false`)
**And** poll `GET /nlb/v1/operations/<opId>` сходится к `done=true` без `error`; `response` — созданный
       `NetworkLoadBalancer` с `placementType=ZONAL`, `regionId=R1`, `status=INACTIVE`, заполненными
       `id` (`nlb…`) и `createdAt` (truncated to seconds)
**And** `GET /nlb/v1/networkLoadBalancers/<lbId>` показывает обе VIP-привязки (v4/v6), выделенные из зоны `R1-a`.

### Сценарий 1.3: ZONAL single-family (только v4) → same-zone проверка не применяется → OK

**ID:** ZC-NLB-ZONE-03-SINGLE-FAMILY-OK

**Given** проект `P`, регион `R1`, зона `R1-a`; ZONAL-подсеть `sn-4` (`zoneId=R1-a`, v4-CIDR, `<sn4>`)

**When** клиент вызывает `Create` с `type=INTERNAL`, `placement_type=ZONAL`, `region_id=R1`,
       `v4_source={subnet_id:<sn4>}`, **без** `v6_source`

**Then** Operation → `done=true` без `error` (одно семейство — сравнивать не с чем; same-zone-проверка
       для dualstack не срабатывает)
**And** LB создан с единственной v4-VIP из зоны `R1-a`.

### Сценарий 1.4: REGIONAL dualstack → same-zone проверка ПРОПУЩЕНА (anycast-исключение) → OK

**ID:** ZC-NLB-ZONE-04-REGIONAL-EXEMPT-OK

**Given** проект `P`, регион `R1`; сеть `net-A`
**And** REGIONAL-подсеть `sn-r4` (`placementType=REGIONAL`, `regionId=R1`, `zoneId=''`, v4-CIDR, `<snR4>`)
       и REGIONAL-подсеть `sn-r6` (`placementType=REGIONAL`, `regionId=R1`, `zoneId=''`, v6-CIDR, `<snR6>`)

**When** клиент вызывает `Create` с `type=INTERNAL`, `placement_type=REGIONAL`, `region_id=R1`,
       `v4_source={subnet_id:<snR4>}`, `v6_source={subnet_id:<snR6>}`

**Then** Operation → `done=true` без `error` — REGIONAL-подсети `zone_id` не несут (`zoneId=''`),
       поэтому same-zone-проверка **исключена by construction** (anycast); остаётся same-network
       (существующая) + region-coherence (Группа 2)
**And** LB создан (anycast dualstack).

### Сценарий 1.5: ZONAL dualstack, mixed source (subnet + linked address) в разных зонах → INVALID_ARGUMENT

**ID:** ZC-NLB-ZONE-05-NEG-MIXED-SOURCE-CROSS-ZONE

**Given** проект `P`, регион `R1`, зоны `R1-a`, `R1-b`; сеть `net-A`
**And** ZONAL-подсеть `sn-4` (`zoneId=R1-a`, v4-CIDR) в `net-A`
**And** ZONAL-подсеть `sn-6b` (`zoneId=R1-b`, v6-CIDR) в `net-A`
**And** external-less **internal** v6-Address `addr-6` в проекте `P`, привязанный к `sn-6b`
       (наследует зону `R1-b`), свободный (`usedBy=''`), id `<addr6>`

**When** клиент вызывает `Create` с `type=INTERNAL`, `placement_type=ZONAL`, `region_id=R1`,
       `v4_source={subnet_id:<sn4>}` (зона `R1-a`), `v6_source={address_id:<addr6>}`
       (подсеть адреса — зона `R1-b`)

**Then** ответ — **синхронный** gRPC `INVALID_ARGUMENT` с текстом
       **`"dualstack load balancer families must resolve to the same zone"`** (зона каждого семейства
       берётся из его резолвнутой подсети независимо от вида source: subnet-auto или linked-address)
**And** LB не создаётся; уже линкованный `addr-6` **не** получает `usedBy` (sync fail-fast до аллокации/линка).

> Impl-note: зона linked-адреса резолвится через его `subnet_id` (уже читается в
> `resolveLinkedAddress`, `create.go:242-258` для placement-type проверки) — добавляется извлечение
> `subnet.ZoneID` в `familyVIPSpec` рядом с `networkID`, затем same-zone-сравнение семейств в
> `resolveSources` (аналогично same-network 180-194).

---

## Группа 2 — nlb GAP-2: region-coherence VIP↔LoadBalancer (INTERNAL)

> Инвариант: `data-integrity.md §Placement-coherence` → «NLB(REGIONAL) ↔ subnet/address (тот же
> регион + anycast)» и общее правило «зональный ↔ региональный: зона consumer'а ∈ регион peer'а».
> Регион подсети: у **REGIONAL**-подсети — прямой `region_id`; у **ZONAL**-подсети — резолв
> `zone→region` через `geo.v1.ZoneService.Get` (`Zone.region_id`). Оба обязаны == `lb.region_id`.
> Место фикса: `resolveOneSource`/`resolveLinkedAddress` (`create.go:199-261`) — рядом с
> `subnetPlacementMatches`, который сегодня сверяет только **тип**, не регион.

### Сценарий 2.1: INTERNAL LB, ZONAL subnet-source из ЧУЖОГО региона → sync INVALID_ARGUMENT

**ID:** ZC-NLB-REGION-01-NEG-ZONAL-SUBNET-WRONG-REGION

**Given** регионы `R1`, `R2`; зона `R2-a` ∈ `R2` (seed geo)
**And** проект `P`, сеть `net-A`; ZONAL-подсеть `sn-r2` (`zoneId=R2-a` → регион `R2`, v4-CIDR, `<snR2>`)

**When** клиент вызывает `Create` с:
  - type = `INTERNAL`, placement_type = `ZONAL`
  - region_id = `R1`
  - v4_source = `{ subnet_id: <snR2> }`   (подсеть в зоне `R2-a` региона `R2`)

**Then** ответ — **синхронный** gRPC `INVALID_ARGUMENT` (Operation НЕ создаётся)
**And** текст ошибки — **`"load balancer vip subnet must be in the same region as the load balancer"`**
       (rule-шаблон region-mismatch: «… must be in the same region»)
**And** LB не создаётся; VIP не аллоцируется.

### Сценарий 2.2: INTERNAL LB, REGIONAL subnet-source из ЧУЖОГО региона → sync INVALID_ARGUMENT

**ID:** ZC-NLB-REGION-02-NEG-REGIONAL-SUBNET-WRONG-REGION

**Given** регионы `R1`, `R2`; проект `P`, сеть `net-A`
**And** REGIONAL-подсеть `sn-rr2` (`placementType=REGIONAL`, `regionId=R2`, `zoneId=''`, v4-CIDR, `<snRR2>`)

**When** клиент вызывает `Create` с `type=INTERNAL`, `placement_type=REGIONAL`, `region_id=R1`,
       `v4_source={subnet_id:<snRR2>}`   (REGIONAL-подсеть региона `R2`)

**Then** ответ — **синхронный** gRPC `INVALID_ARGUMENT` с тем же текстом
       **`"load balancer vip subnet must be in the same region as the load balancer"`**
**And** LB не создаётся.

> Impl-note: nlb subnet-client (`internal/clients/vpc/subnet_client.go`) сегодня маппит `ZoneID`, но
> **не** `RegionID` (denormalised mirror, adapter оставляет пустым). Для REGIONAL-подсети регион нужно
> взять из `resp.GetRegionId()` (добавить маппинг). Для ZONAL-подсети — резолв `zone→region` через
> `geo.ZoneService.Get` (ребро `nlb→geo` уже существует). Единый helper «регион подсети» → сравнение с `lb.region_id`.

### Сценарий 2.3: INTERNAL LB, subnet-source в ТОМ ЖЕ регионе → OK (happy path)

**ID:** ZC-NLB-REGION-03-SAME-REGION-OK

**Given** регион `R1`, зона `R1-a` ∈ `R1`; проект `P`, сеть `net-A`
**And** ZONAL-подсеть `sn-ok` (`zoneId=R1-a` → регион `R1`, v4-CIDR, `<snOk>`)

**When** клиент вызывает `Create` с `type=INTERNAL`, `placement_type=ZONAL`, `region_id=R1`,
       `v4_source={subnet_id:<snOk>}`

**Then** Operation → `done=true` без `error`; LB создан (`regionId=R1`), VIP из зоны `R1-a` региона `R1`
**And** зеркально: REGIONAL-подсеть `regionId=R1` при `region_id=R1` тоже проходит (`placement_type=REGIONAL`).

### Сценарий 2.4: INTERNAL LB, linked internal Address из ЧУЖОГО региона → generic INVALID_ARGUMENT (anti-oracle)

**ID:** ZC-NLB-REGION-04-NEG-LINKED-ADDRESS-WRONG-REGION

**Given** регионы `R1`, `R2`; проект `P`
**And** internal Address `addr-r2` в `P`, привязанный к подсети региона `R2` (REGIONAL или ZONAL),
       свободный, id `<addrR2>`

**When** клиент вызывает `Create` с `type=INTERNAL`, `placement_type` соответствует подсети адреса,
       `region_id=R1`, `v4_source={address_id:<addrR2>}`

**Then** ответ — **синхронный** gRPC `INVALID_ARGUMENT` с **generic** текстом
       **`"Illegal argument addressId"`** (анти-oracle: link-путь `resolveLinkedAddress` уже отдаёт
       generic на любой mismatch — `create.go:239/253/256` — чтобы не подтверждать детали чужого
       адреса; region-mismatch линкованного адреса следует тому же паттерну, а НЕ descriptive-тексту
       из 2.1/2.2)
**And** LB не создаётся; `addr-r2` не получает `usedBy`.

> Design-note: descriptive-текст (2.1/2.2) — для caller-supplied `subnet_id` (форма запроса, не oracle);
> generic-текст (2.4) — для `address_id` (ownership/placement линкованного ресурса, анти-oracle-паттерн
> уже зафиксирован в `resolveLinkedAddress`). Разделение осознанное, зеркалит существующее поведение.

---

## Группа 3 — vpc GAP-3: external `Address.zone_id` — geo-валидация существования

> Инвариант: `data-integrity.md §Placement-coherence` → «Существование `zone_id`/`region_id` —
> валидировать peer-вызовом `geo.v1.ZoneService.Get` … Пропуск (напр. **непроверенная зона внешнего
> адреса**) — баг». Зеркалит `Subnet.validateZoneID`
> (`kacho-vpc/internal/apps/kacho/api/subnet/helpers.go:185-200`, `InvalidArgument "unknown zone id '%s'"`)
> и `AddressPool` (`addresspool/create.go:83-88`). Место фикса: `CreateAddressUseCase.Execute`
> (`address/create.go`) для `ExternalSpec.ZoneID` и `ExternalIpv6Spec.ZoneID`.
> **Отличие от Subnet:** для external Address пустой `zone_id` **валиден** (anycast из global-пула) —
> проверка условная: непустой `zone_id` → existence-check; пустой → освобождён.

### Сценарий 3.1: Create external Address с несуществующей zone_id → sync INVALID_ARGUMENT

**ID:** ZC-VPC-ADDR-ZONE-01-NEG-UNKNOWN-ZONE

**Given** проект `P`; зона `zzz-nonexistent-9` **отсутствует** в `kacho_geo.zones`

**When** клиент вызывает `kacho.cloud.vpc.v1.AddressService/Create`
(REST `POST /vpc/v1/addresses`) с payload:
  - project_id = `<P>`
  - external_ipv4_address_spec = `{ zone_id: "zzz-nonexistent-9" }`

**Then** ответ — **синхронный** gRPC `INVALID_ARGUMENT` (Operation **НЕ** создаётся)
**And** текст ошибки — **`"unknown zone id 'zzz-nonexistent-9'"`** (verbatim-зеркало Subnet.validateZoneID)
**And** в `kacho_vpc.addresses` новая строка не появляется.

### Сценарий 3.2: Create external IPv6 Address с несуществующей zone_id → sync INVALID_ARGUMENT

**ID:** ZC-VPC-ADDR-ZONE-02-NEG-UNKNOWN-ZONE-V6

**Given** проект `P`; зона `zzz-nonexistent-9` отсутствует в geo

**When** клиент вызывает `Create` с `external_ipv6_address_spec = { zone_id: "zzz-nonexistent-9" }`

**Then** синхронный `INVALID_ARGUMENT` с текстом **`"unknown zone id 'zzz-nonexistent-9'"`**
**And** строка не создаётся (симметрия v4/v6 — оба external-spec'а валидируются).

### Сценарий 3.3: Create external Address с существующей zone_id → OK (happy path)

**ID:** ZC-VPC-ADDR-ZONE-03-KNOWN-ZONE-OK

**Given** проект `P`; зона `R1-a` существует в `kacho_geo.zones` (seed, status `UP`)
**And** доступен зональный external-пул, покрывающий зону `R1-a` (иначе аллокация даст отдельный
       async-fail — вне scope этой проверки)

**When** клиент вызывает `Create` с `external_ipv4_address_spec = { zone_id: "R1-a" }`

**Then** зона проходит existence-check (Operation создаётся); poll `GET /vpc/v1/operations/<opId>`
       сходится к `done=true` без `error`; `response` — `Address` с непустым `id` (`e9b…`),
       заполненным `externalIpv4.address` и `createdAt` (truncated to seconds)
**And** `GET /vpc/v1/addresses/<addrId>` возвращает Address зоны `R1-a`.

### Сценарий 3.4: Create external Address БЕЗ zone_id (anycast / global-пул) → освобождён → OK

**ID:** ZC-VPC-ADDR-ZONE-04-ANYCAST-EMPTY-ZONE-OK

**Given** проект `P`; доступен global (не-зональный) external-пул

**When** клиент вызывает `Create` с `external_ipv4_address_spec = { }` (**`zone_id` пуст/отсутствует**)

**Then** existence-check **не выполняется** (пустой `zone_id` = anycast из global-пула, освобождён —
       в отличие от Subnet, где ZONAL требует непустой `zone_id`); Operation → `done=true` без `error`
**And** `Address` создан как global/anycast (`externalIpv4.address` заполнен, зона пуста).

### Сценарий 3.5: Internal Address — зона наследуется от subnet, отдельной проверки нет (boundary)

**ID:** ZC-VPC-ADDR-ZONE-05-INTERNAL-INHERITS-SUBNET

**Given** проект `P`; ZONAL-подсеть `sn-4` (`zoneId=R1-a`, v4-CIDR, `<sn4>`)

**When** клиент вызывает `Create` с `internal_ipv4_address_spec = { subnet_id: <sn4> }`

**Then** Operation → `done=true` без `error` — internal Address зону **не несёт**, наследует через
       `subnet_id` (зона подсети уже была провалидирована на `Subnet.Create`); GAP-3 добавляет проверку
       **только** для external-spec'ов, internal-путь (`assertSubnetOwned`, `address/create.go:170-179`)
       не меняется
**And** это подтверждает scope: GAP-3 узкий — только `ExternalSpec.ZoneID` / `ExternalIpv6Spec.ZoneID`.

---

## Группа X — cross-cutting: fail-closed peer-недоступность + TOCTOU

> `data-integrity.md §Cross-domain` п.2: cross-service ref валидируется через API владельца на
> request-path; **owner недоступен → `UNAVAILABLE` (fail-closed для мутаций)**. Это НЕ DB-инвариант
> (ban #4/#8) — гарантия достигается sync-precheck'ом + fail-closed, не FK.

### Сценарий X.1: geo/vpc недоступен во время placement-precheck → sync UNAVAILABLE (fail-closed)

**ID:** ZC-X-01-NEG-PEER-UNAVAILABLE-FAILCLOSED

**Given** валидный запрос (любой из Групп 1/2/3), но peer-owner недоступен на request-path:
  - **X.1a (nlb→vpc):** `SubnetService.Get` недоступен при резолве subnet-source (Группа 1/2)
  - **X.1b (nlb→geo):** `ZoneService.Get` недоступен при zone→region резолве ZONAL-подсети (Группа 2)
  - **X.1c (vpc→geo):** `ZoneService.Get` недоступен при existence-проверке external `zone_id` (Группа 3)

**When** клиент вызывает соответствующий `Create`

**Then** ответ — **синхронный** gRPC `UNAVAILABLE` (мутация **не** выполнена; Operation не создаётся;
       ресурс не записан) — **fail-closed**: недоступность owner'а НЕ трактуется как «валидно»
**And** ретрай после восстановления peer'а проходит штатно (idempotent — sync precheck без side-effect'ов).

> Impl-note: рёбра уже несут `retry.OnUnavailable` + per-call deadline (subnet-client
> `DefaultSubnetGetTimeout=5s`; region-client stateless pass-through). После исчерпания ретраев —
> `Unavailable`. Для linked-address subnet-lookup ветка уже существует
> (`create.go:250-252` → `Unavailable "subnet lookup unavailable"`); новые placement-проверки
> **не должны** глотать `Unavailable` как «coherence-fail».

### Сценарий X.2: TOCTOU — удаление subnet между sync-precheck и async VIP-аллокацией → нет incoherent-LB

**ID:** ZC-X-02-CONCURRENT-SUBNET-DELETE-NO-PARTIAL

**Given** валидный ZONAL dualstack Create (обе подсети зоны `R1-a`, регион `R1`) — sync-prechecks (зона/регион) прошли

**When** параллельно: (a) worker `doCreate` начинает VIP fan-out (`create.go:297-306`), (b) одна из
       subnet-source удаляется в vpc **между** sync-precheck и async-аллокацией

**Then** итог детерминирован и **когерентен**:
  - либо обе VIP успели аллоцироваться до удаления → LB финализируется валидным (обе VIP зоны `R1-a`);
  - либо аллокация из удалённой подсети падает в worker'е → Operation завершается с `error`
    (`INVALID_ARGUMENT`/`FAILED_PRECONDITION` per-family reason), а `compensateCreate`
    (`create.go:507-531`) освобождает уже аллоцированную VIP и удаляет CREATING-handle
**And** **ни при каком исходе** не появляется LB с VIP из разных зон/регионов, и сервис не отдаёт
       `INTERNAL` с leak'ом pgx/peer-текста
**And** `Subnet.zone_id`/`region_id` **immutable** (placement-якорь) — поэтому «смена зоны подсети
       после precheck» невозможна by construction; единственная гонка — удаление, покрытое компенсацией.

> Примечание: это НЕ within-service DB-CAS-гонка (VIP аллоцируется cross-service в vpc). Детерминизм
> обеспечивается async-worker'ом + compensation, а не «ровно одна транзакция проходит». Integration-тест
> (testcontainers vpc + fake/real subnet-delete) фиксирует: partial-incoherent-LB не персистится.

---

## Traceability (сценарий → аудит-код → инвариант)

| Группа | Сценарии | Аудит (file:line) | Нормативный источник |
|---|---|---|---|
| GAP-1 same-zone (nlb) | ZC-NLB-ZONE-01..05 | `kacho-nlb .../loadbalancer/create.go:180-194` (same-network only) | `data-integrity.md §Placement-coherence` (NLB ZONAL dualstack) |
| GAP-2 region (nlb) | ZC-NLB-REGION-01..04 | `create.go:209-212`, `246-257` (placement type-only), `277-281` (region existence-only) | `data-integrity.md §Placement-coherence` (NLB REGIONAL/zonal∈region) |
| GAP-3 ext zone (vpc) | ZC-VPC-ADDR-ZONE-01..05 | `kacho-vpc .../address/create.go` (external spec без geo-validate); эталон `subnet/helpers.go:185-200` | `data-integrity.md §Placement-coherence` («непроверенная зона внешнего адреса — баг») |
| Cross-cutting | ZC-X-01, ZC-X-02 | `create.go:250-252`, `297-306`, `401-416`, `507-531` | `data-integrity.md §Cross-domain` п.2 (fail-closed `Unavailable`) |

ID'ы трассируются в имена integration- и newman-кейсов (`ZC-*`).

---

## DoD (per-stage; TDD — RED до кода)

**Stage nlb (GAP-1 + GAP-2)** — `kacho-nlb`:
- [ ] RED-тесты первыми: unit use-case (fake `SubnetClient`/`AddressClient`/`ZoneClient`/`RegionClient`) на
      ZC-NLB-ZONE-01/05 и ZC-NLB-REGION-01/02/04 (exact-text + code); happy 02/03/04 и REGION-03.
- [ ] Код: same-zone-сравнение семейств в `resolveSources`; region-coherence в `resolveOneSource`/
      `resolveLinkedAddress`; subnet-client маппит `RegionID` (REGIONAL) + zone→region резолв (ZONAL, `nlb→geo`).
- [ ] Integration (testcontainers + peer-stubs) на cross-region/cross-zone negative + TOCTOU (ZC-X-02).
- [ ] Newman: ≥1 happy (ZONE-02, REGION-03) + ≥1 negative (ZONE-01, REGION-01) через api-gateway.
- [ ] `go test ./... -race` + `golangci-lint` + `govulncheck` зелёные; error-текст assert'ится (behaviour-level).
- [ ] proto/схема **не тронуты**; vault: обновить `edges/nlb-to-vpc-subnet-validation`,
      `edges/nlb-to-geo-region-validate`, `resources/nlb-load-balancer` (History + coherence-инвариант).

**Stage vpc (GAP-3)** — `kacho-vpc`:
- [ ] RED-тесты первыми: unit use-case (fake `ZoneRegistry`) на ZC-VPC-ADDR-ZONE-01/02 (unknown zone,
      exact text) + 04 (empty zone anycast pass) + 03 (known zone pass).
- [ ] Код: условная geo-validation `ExternalSpec.ZoneID`/`ExternalIpv6Spec.ZoneID` в `Execute`
      (непустой → `geo.ZoneService.Get` existence; пустой → skip), зеркало `subnet.validateZoneID`,
      fail-closed `Unavailable`.
- [ ] Integration + newman (happy known-zone, negative unknown-zone).
- [ ] `go test ./... -race` + lint + govulncheck; vault: `resources/vpc-address` (external zone validated) + `edges/vpc-to-geo-zone-validate` History.

**Финал:** заказчик — smoke/e2e (`make e2e-test` / `grpcurl` cross-zone/cross-region negative + happy).
