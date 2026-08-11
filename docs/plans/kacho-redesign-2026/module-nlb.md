## kacho-nlb — целевой tenant-facing дизайн (best-practice 2026)

> Один продукт Kachō, форма якорится на compute: flat-ресурс без envelope, мутации → `Operation`, sync-каталоги рядом с launch, reference-law по классу ссылки, two-projection, единый тон ошибок. NetworkLoadBalancer — региональный домен: `regionId` — обязательная placement-координата, режим несёт **один** immutable input-дискриминатор `placement` (а `type°`/`placementType°` эмитятся сервером как output-only производные — queryable, как у любого placement-scoped родственника), зона деривится (или объявляется явным опциональным input'ом), таргеты — polymorphic-референсы на compute/vpc. Роутинг «этот listener → эта TargetGroup» выражен **одной** нормализованной связью (`Listener.targetGroupId`). Backend-порт — **одно** поле **одного** ресурса (`TargetGroup.port`); проба наследует его отсутствием override. Power-модель compute-стиля (`:start`/`:stop`) заменена LB-нативным `adminState`.

> **Начни отсюда (default onboarding path).** Не выстраивай ресурсы руками — вызови **`NetworkLoadBalancer.Create` (one-shot)**: передай `listenerSpecs[]`, где каждый listener несёт `targetGroupId` (existing) ЛИБО inline `targetGroup{port, healthCheck, targets[]}`. Сервер разворачивает TG+HealthCheck+targets+VIP-сагу **в правильном dependency-порядке** внутри ОДНОЙ Operation — FK-топология тебя не касается. `Operation.metadata.networkLoadBalancerId` доступен СРАЗУ (до `done`). После создания **первый** `Get`/`Update`/`Delete` своего свежего LB оборачивай в SDK-хелпер `retry_until_authorized` (см. OperationService) — owner-tuple материализуется eventually-consistent, короткое `403`/`404` — это read-your-writes лаг, не сбой.

---

## Ментальная модель

Пять опор, у каждой ровно один источник истины:

1. **NetworkLoadBalancer — региональный якорь, единица владения И носитель VIP.** Живёт в одном `regionId` (immutable), несёт **один** immutable **input**-дискриминатор `placement ∈ {EXTERNAL_REGIONAL | INTERNAL_REGIONAL | INTERNAL_ZONAL}` — нелегальная ячейка «external+zonal» невыразима **by construction** (не runtime-reject). Из `placement` сервер деривит и **эмитит** output-only `type°∈{EXTERNAL,INTERNAL}` и `placementType°∈{ZONAL,REGIONAL}` (persist остаётся один — `placement`; но оба факта queryable на wire, как `placement_type` у subnet/родственников — модуль не «другой продукт» на этом стыке). **VIP — ровно один на семейство (v4/v6) на весь LB**: источник задаётся пофамильно на Create (`v4Source`/`v6Source`), резолвится в связанный `vpc.Address` и эхается output-only `v4AddressId°`/`v6AddressId°`. Все listener'ы LB делят этот VIP. Всё within-service (Listener) висит на нём FK. Источник истины по проекту/региону/режиму/имени/admin-state/**VIP** — **сам NetworkLoadBalancer**.
2. **Listener — порт на VIP балансировщика И единственный authoritative-указатель на TargetGroup.** Владеет `(port, protocol)` frontend'а (immutable) + **ровно одной** ссылкой `targetGroupId`. Собственного адреса listener НЕ несёт и не аллоцирует: VIP — свойство LoadBalancer'а (опора 1), listener открывает на нём порт. Роутинг выражен ТОЛЬКО `targetGroupId` — набор «attached TG» у LB **выводится** как объединение TG, на которые ссылаются listener'ы. Frontend-порт — свойство listener'а; backend-порт — НЕ его свойство (живёт на TG, но эхается output-only `resolvedBackendPort°` для наблюдаемости). Источник истины по «какой порт и куда роутит» — **Listener**; по «на каком VIP» — **LoadBalancer**.
3. **TargetGroup — переиспользуемый REGION-scoped, LB-agnostic пул бэкендов на backend-порту + health-контракт.** Несёт `port` (**единственный** backend-порт пула), регионально-когерентна (не зонально — зона проверяется на wire к ZONAL-LB, не на самой TG). Health-check — embedded value object; `probe.port` наследует `TargetGroup.port` **отсутствием** override (не magic-zero). Источник истины по «на каком порту бэкенды и как их проверять» — **TargetGroup**.
4. **Target — polymorphic-референс на owned-ресурс.** 4-way identity (instance / nic / in-cloud IP / external IP), exactly-one. Зависимость на чужой ресурс → graceful-dangling Referrer с тремя **ортогональными наблюдаемыми осями**: lifecycle-`status` (гейтит трафик), `healthState` (исход пробы), `targetRefState` (резолвится ли owner). Все три сворачиваются сервером в один output-only `servingTraffic°` для «берёт ли этот бэкенд трафик» одним взглядом. Источник истины по «что за бэкенд» — **owner-сервис** (compute/vpc); nlb хранит ссылку + вес.
5. **Placement-когерентность — закон связывания.** REGIONAL-ресурсы когерентны по региону, ZONAL — по зоне. Зона ZONAL-LB **не персистится и не эмитится отдельным полем** — она задана зоной подсети, из которой резолвится VIP, и энфорсится на Create: обе dualstack-семьи обязаны резолвиться в ОДНУ зону, каждый VIP-источник обязан совпасть с LB по `placementType` и по региону. Порядок вызовов на неё не влияет — VIP аллоцируется один раз, в `LoadBalancer.Create`. TG region-coherence энфорсится всегда; TG zone-coherence — warn на target-entry + hard на wire к ZONAL-LB. Источник истины по географии — **kacho-geo** (`RegionService`/`ZoneService`), nlb только peer-валидирует fail-closed.

---

## NetworkLoadBalancer

ID prefix `nlb` · owner `kacho_nlb.network_load_balancers` · REST `/nlb/v1/networkLoadBalancers`

### Пример 1 — `EXTERNAL_REGIONAL` (публичный anycast-VIP)

```jsonc
{
  "id": "nlb1a2b3c4d5e6f7g8h",              // ° 3-char prefix + base32 (nlb-owned → prefix-checked)
  "projectId": "prjf9k2m4x7q1w8r3",         // scope-slug → iam.Project, peer-validate (hard-fail); IMMUTABLE; НЕ prefix-checked (foreign id)
  "regionId": "eu-north",                   // geo-slug → geo.Region, peer-validate (hard-fail); IMMUTABLE; human slug, НЕ prefix/base32
  "name": "public-north-edge",              // DNS-1123; UNIQUE(project,name) partial (пустое имя разрешено)
  "description": "public north-edge ingress",
  "labels": { "tier": "edge", "team": "net" },

  "placement": "EXTERNAL_REGIONAL",         // IMMUTABLE INPUT — ЕДИНСТВЕННЫЙ persist-дискриминатор режима.
                                            //   Сплавляет scheme × scope: scheme(EXTERNAL=internet-facing / INTERNAL=private VIP)
                                            //   × scope(REGIONAL=anycast/regional / ZONAL=pinned к одной зоне):
                                            //     EXTERNAL_REGIONAL — публичный VIP из региона, anycast (зоне-независим)
                                            //     INTERNAL_REGIONAL — приватный VIP из anycast/regional subnet
                                            //     INTERNAL_ZONAL    — приватный VIP, привязан к ОДНОЙ зоне
                                            //   «external+zonal» невыразим by construction (нет такого значения)
  "type": "EXTERNAL",                       // ° derived output-only из placement (scheme); queryable, не persist
  "placementType": "REGIONAL",              // ° derived output-only из placement (scope); queryable, не persist

  // ── VIP: ровно один Address на семейство на ВЕСЬ LB; listener'ы делят его ──
  "v4Source": { "public": {} },             // INPUT-only (в ответе не эхается): источник v4-VIP, IMMUTABLE.
                                            //   oneof: public{} (EXTERNAL, платформенный) | subnetId (INTERNAL, auto-alloc)
                                            //         | addressId (link существующего vpc.Address)
                                            //   Хотя бы одно семейство (v4Source|v6Source) обязано быть задано
  "v4AddressId": "adrt8y2u4i6o8p0aq1",       // ° output-only: связанный vpc.Address (IPv4). Пусто пока status=CREATING.
                                            //   САМ IP здесь НЕ дублируется — читается vpc.AddressService.Get(v4AddressId)
  "v6AddressId": "",                        // ° то же для IPv6; пусто = семейство не объявлено

  "adminState": "ENABLED",                  // ENABLED(«принимает трафик»)|DISABLED(«админ-выключен, конфиг сохранён»);
                                            //   LIVE-mutable — LB-нативный enable/disable (НЕ compute power-verbs);
                                            //   DISABLED сохраняется, Update никогда не авто-ENABLE'ит
  "sessionAffinity": "FIVE_TUPLE",          // FIVE_TUPLE(«5-tuple hash»)|CLIENT_IP_ONLY(«sticky по src-IP»); LIVE-mutable
  "crossZoneEnabled": true,                 // LIVE-mutable; REGIONAL — балансит поперёк зон региона.
                                            //   Для ZONAL write !=false → InvalidArgument (см. правило 12) — не молчаливый inert
  "deletionProtection": false,              // LIVE-mutable; sync-precheck в Delete

  "securityGroupIds": [ "sg0k4m7t2y9u1i3o" ],   // flat-slug → vpc.SecurityGroup (SAME PROJECT existence-check);
                                            //   peer-validate hard-fail; LIVE-mutable; firewall САМОГО VIP (frontend access control).
                                            //   Region-coherence НЕ проверяется: SG network-scoped, у owner'а нет region/zone-поля

  "listeners": [                            // ° within-service children (FK), lean-проекция для обзора.
                                            //   Адресных полей у listener'а нет — VIP один на LB (v4AddressId° выше)
    { "id": "lst7h3k9m2x4q8w1t", "name": "tcp-443", "port": 443, "protocol": "TCP",
      "targetGroupId": "tgr2w8r4t6y1u3i5o", "resolvedBackendPort": 8080,
      "substatus": "OK" }                   // ° DERIVED (не persist): OK ⟺ targetGroupId резолвится, иначе MISCONFIGURED
  ],

  "status": "ACTIVE",                       // ° INACTIVE|CREATING|DEGRADED|ACTIVE|DISABLED|DELETING
  "createdAt": "2026-07-19T08:12:00Z",      // ° truncate до секунд
  "updatedAt": "2026-07-19T09:40:00Z"       // °
}
```

### Пример 2 — `INTERNAL_ZONAL` (приватный VIP в одной зоне, явный zoneId-input)

```jsonc
{
  "id": "nlb9z8y7x6w5v4u3t2",
  "projectId": "prjf9k2m4x7q1w8r3",
  "regionId": "eu-north",                   // IMMUTABLE
  "name": "internal-api-vip",
  "description": "private east-api load balancer",
  "labels": { "tier": "internal", "app": "api" },

  "placement": "INTERNAL_ZONAL",            // IMMUTABLE INPUT — приватный VIP, привязан к одной зоне
  "type": "INTERNAL",                       // ° derived
  "placementType": "ZONAL",                 // ° derived

  // ── VIP: dualstack — ДВА Address (по одному на семейство), ОБЯЗАНЫ резолвиться в ОДНУ зону и ОДНУ сеть ──
  "v4Source": { "subnetId": "sub3e5r7t9y1u3i5o7" },  // INPUT-only, IMMUTABLE: ZONAL-подсеть зоны eu-north-a →
                                            //   auto-аллокация свежего internal Address. placementType подсети
                                            //   ОБЯЗАН совпасть с placementType LB, и подсеть — region-coherent
  "v6Source": { "subnetId": "sub3e5r7t9y1u3i5o7" },  // та же подсеть → та же зона и сеть (инвариант выполнен)
  "v4AddressId": "adr1q3w5e7r9t1y3u5",       // ° output-only; IP читается vpc.AddressService.Get
  "v6AddressId": "adr2w4e6r8t0y2u4i6",       // ° output-only

                                            // Зона ZONAL-LB отдельным полем НЕ эмитится: она задана зоной
                                            //   подсети VIP-источника и зафиксирована на Create (см. правило 10)

  "adminState": "ENABLED",                  // LIVE-mutable
  "sessionAffinity": "CLIENT_IP_ONLY",      // LIVE-mutable
  "crossZoneEnabled": false,                // для ZONAL допустимо ТОЛЬКО false (write !=false → InvalidArgument)
  "deletionProtection": true,               // LIVE-mutable
  "securityGroupIds": [ "sg03e5r7t9y1u3i5o" ],  // firewall VIP (same-project existence); LIVE-mutable

  "listeners": [                            // °
    { "id": "lst5k7m9q1w3e5r7t", "name": "tcp-8443", "port": 8443, "protocol": "TCP",
      "targetGroupId": "tgr4h6j8l0n2p4r6s", "resolvedBackendPort": 8080,
      "substatus": "OK" }                   // ° порт 8443 открыт на ОБОИХ VIP (v4 и v6) этого LB
  ],

  "status": "ACTIVE",                       // °
  "createdAt": "2026-07-19T08:20:00Z",      // °
  "updatedAt": "2026-07-19T08:20:00Z"       // °
}
```

**Инфра-поля (node/underlay/vrf/programming-status) — НЕ здесь.** Публичная проекция = намерение (`placement`/`region`/`adminState`/`v4Source`/`v6Source`) + результат (`status`/`v4AddressId°`/`v6AddressId°`). Физика — только в `NetworkLoadBalancerInternal` (:9091, two-projection ниже). Сюда же относится **сам VIP-IP**: публичная проекция несёт только **id** связанного `vpc.Address`, IP-строку тенант читает у владельца (`vpc.AddressService.Get`) — nlb её не дублирует. Не выходят на публичную поверхность и `vipOrigin` (auto|linked), derived network, announce/route-состояние. (Отдельной «underlay-зоны public-VIP» **не существует**: public-VIP anycast и зоне-независим — см. таблицу источников ниже.) `attachedTargetGroups` в дефолтной проекции **не материализуется** — выводим из `listeners[].targetGroupId` (LEAN); доступен по запросу `?view=EXPAND`.

`status` авто-рекомпутится DB-триггером: `ACTIVE` ⟺ `adminState=ENABLED`, есть ≥1 listener и КАЖДЫЙ listener резолвит свою TargetGroup; **`DEGRADED`** ⟺ есть listener с `substatus=MISCONFIGURED` (нет резолвящейся TG — silent-blackhole не маскируется под ACTIVE); `INACTIVE` пока config-incomplete (нет ни одного listener); **`DISABLED`** ⟺ `adminState=DISABLED` (админ-выключен, конфиг цел). `adminState` сохраняется: **Update никогда не авто-ENABLE'ит DISABLED-LB** — только явный `adminState:ENABLED` в маске.

### VIP — свойство LoadBalancer'а (один на семейство, аллоцируется на Create)

**VIP живёт на NetworkLoadBalancer, не на Listener.** LB несёт максимум по одному `vpc.Address` на семейство; listener'ы открывают на нём порты и собственной аллокации не делают. Никакой другой ресурс модуля адрес не держит.

**Источник VIP — `v4Source`/`v6Source`, per-family oneof, IMMUTABLE input.** Хотя бы одно семейство обязано быть задано (иначе `InvalidArgument "load balancer must declare a vip source for at least one ip family"`). Три источника, матрица «источник × режим» проверяется sync, до `Operation`:

| Источник | Допустим для | Что делает Create-worker | `vipOrigin` (internal) |
|---|---|---|---|
| `subnetId` | **INTERNAL** (`subnet address source is only valid for INTERNAL load balancer`) | `vpc.InternalAddressService.AllocateInternalIP`/`…IPv6` — свежий адрес из подсети | `auto` |
| `public {}` | **EXTERNAL** (`public address source is only valid for EXTERNAL load balancer`) | `AllocateExternalIP`/`…IPv6` **БЕЗ зоны** — EXTERNAL всегда `EXTERNAL_REGIONAL`, т.е. REGIONAL/anycast, т.е. зоне-независим by construction (правило 5/10): VIP берётся из **зоне-независимого** (anycast) AddressPool vpc (`zone_id IS NULL`). Зона НЕ деривится: любая деривация (напр. «первая зона региона») пинит anycast-VIP к префиксу и failure-domain'у ОДНОЙ зоны и работает лишь тогда, когда та зона случайно держит пул нужного семейства. Нет anycast-пула → `FAILED_PRECONDITION "could not allocate load balancer address"` (лосси by design, причина — в server-лог) | `auto` |
| `addressId` | оба (kind адреса обязан соответствовать `type°`) | `SetReference`-CAS на существующий `vpc.Address` — link, без аллокации | `linked` |

**Аллокация — часть `NetworkLoadBalancer.Create`-Operation** (саги на уровне listener'а не существует). Порядок worker'а: INSERT durable-handle (`status=CREATING`, адреса пусты) → per-family acquire → CAS-attach VIP (отдельный commit на семейство) → финальный CAS `CREATING→INACTIVE` + outbox + FGA-intent. `Operation.metadata.networkLoadBalancerId` доступен сразу; `done` означает durability строки, не видимость owner-tuple (правило 3).

**Компенсация и release.** Откат саги до финализации освобождает **каждый** уже добытый VIP в обратном порядке и удаляет handle. `LoadBalancer.Delete` (после того как listener'ы удалены — RESTRICT-precheck) освобождает VIP каждого семейства. Ветка release выбирается дискриминатором происхождения: `auto` → `ClearReference` + `FreeIP` (адрес возвращается в пул), `linked` → только `ClearReference` (адрес **остаётся** у тенанта). Оба шага идемпотентны (повтор на уже свободном — no-op). Backstop на краш worker'а между acquire и persist — фоновый reconciler, сканирующий LB в `CREATING`/`DELETING` дольше порога и освобождающий их адреса по тому же дискриминатору (`data-integrity.md` §Lease-recycle-on-delete B17: пул не течёт).

**VIP-uniqueness — DB, на уровне LoadBalancer'а:**

- **один IP на регион на семейство** — partial-UNIQUE `(region_id, address_v4) WHERE address_v4 <> ''` и v6-близнец. Двойной claim одного адреса двумя LB в регионе → 23505 → **generic** `FAILED_PRECONDITION "could not assign address to load balancer"` (анти-oracle: чей именно адрес — не раскрывается). Индексы строятся `CONCURRENTLY` и несут self-heal + assert валидности: прерванный build оставил бы INVALID-индекс, который молча ничего не энфорсит.
- **один VIP на LB на семейство** — кардинальность строки + атомарный CAS-attach `UPDATE … WHERE id=$1 AND (address_v4='' OR address_v4=$2)` (не check-then-act, ban #10). 0 rows → `FAILED_PRECONDITION "load balancer already has an address for this family"`; повтор того же адреса — no-op (retry идемпотентен).
- **`(port, protocol)` на LB** — `UNIQUE (load_balancer_id, port, protocol)` на listener'ах. Поскольку у LB ровно один VIP на семейство, это **и есть** «одна привязка `(VIP, port, protocol)`»: два listener'а на одном VIP допустимы только при разных `(port, protocol)`.

**Placement-когерентность VIP** энфорсится sync, ДО `Operation`: `placementType` подсети (или подсети linked-адреса) обязан совпасть с `placementType` LB; подсеть обязана быть region-coherent с LB (`InvalidArgument "load balancer vip subnet must be in the same region as the load balancer"`); при dualstack обе семьи обязаны резолвиться в **одну сеть** (`"dualstack load balancer families must resolve to the same network"`) и, для ZONAL, в **одну зону** (`"dualstack load balancer families must resolve to the same zone"`). REGIONAL/anycast из зональной проверки исключён by construction — его подсети зоны не несут. Для `addressId`-линка любой mismatch (проект/семейство/kind/placement/регион) сворачивается в единый анти-oracle `InvalidArgument "Illegal argument addressId"` — чужой адрес не подтверждается ни существованием, ни свойствами.

---

## Listener

ID prefix `lst` · owner `kacho_nlb.listeners` · REST `/nlb/v1/listeners`

```jsonc
{
  "id": "lst7h3k9m2x4q8w1t",
  "loadBalancerId": "nlb1a2b3c4d5e6f7g8h",  // within-service FK (RESTRICT); flat id; IMMUTABLE
  "projectId": "prjf9k2m4x7q1w8r3",         // ° denorm с LB (для keyset-пагинации и authz-скоупа); source of truth = LB.
                                            //   Берётся не из snapshot'а, а из строки LB под locking-read — иначе
                                            //   конкурентный LB.Move записал бы stale-проект (TOCTOU)

  "name": "tcp-443",                        // DNS-1123; UNIQUE(loadBalancer,name) partial
  "description": "",
  "labels": {},

  "protocol": "TCP",                        // TCP|UDP (L4-only; TLS-termination вне scope nlb); IMMUTABLE
  "port": 443,                              // FRONTEND-порт на VIP родительского LB (1..65535); IMMUTABLE.
                                            //   UNIQUE(loadBalancerId, port, protocol) — см. §VIP-uniqueness

  // ── единственный authoritative-указатель роутинга (within-service FK, RESTRICT) ──
  "targetGroupId": "tgr2w8r4t6y1u3i5o",     // куда шлёт трафик; region-coherent с LB; nullable → substatus=MISCONFIGURED. LIVE-mutable
                                            //   backend-порт живёт на TargetGroup.port — НЕТ per-listener port-override (правило 9).
                                            //   Нужен другой backend-порт → ссылаться на ДРУГУЮ (дешёвую, reusable) TargetGroup
  "defaultTargetGroupId": "tgr2w8r4t6y1u3i5o",  // тот же референс (обе формы читаются с одной колонки)
  "resolvedBackendPort": 8080,              // ° output-only echo = TargetGroup.port выбранной TG — фактический backend-порт;
                                            //   0 когда TG не резолвится (не путать с frontend port:443 выше)

  // ── адресных полей НЕТ by design ──
  // Ни addressId, ни subnetId, ни ipVersion, ни allocatedAddress, ни regionId: listener — это
  // (port, protocol) на VIP родительского LB. VIP читается с LB (v4AddressId°/v6AddressId°), регион —
  // тоже с LB. Дуальстековый LB обслуживает listener на ОБОИХ своих VIP одновременно: отдельного
  // per-listener выбора семейства не существует.

  "proxyProtocolV2": false,                 // LIVE-mutable

  "status": "ACTIVE",                       // ° CREATING|ACTIVE|UPDATING|DELETING — Create завершается СРАЗУ в ACTIVE
                                            //   (аллоцировать нечего, durable-handle/CREATING-фаза не нужна)
  "substatus": "OK",                        // ° DERIVED (не persist): OK | MISCONFIGURED — MISCONFIGURED когда
                                            //   targetGroupId не резолвится (тот же факт, что LB DEGRADED, на уровне listener'а)
  "createdAt": "2026-07-19T08:12:03Z",      // °
  "updatedAt": "2026-07-19T08:12:03Z"       // °
}
```

**`Listener.Create` — чистый INSERT, без внешних side-effect'ов.** Sync-фаза: резолв родительского LB (`NOT_FOUND`, если нет; `FAILED_PRECONDITION`, если LB в `DELETING`), precheck `targetGroupId` (существует в проекте LB, авторизован вызывающему, region-coherent) и валидация домена. Async-worker — **одна** writer-TX: INSERT (`status=ACTIVE`) + outbox `nlb_listener CREATED` + `nlb_load_balancer UPDATED` + FGA-register-intent. Ни vpc, ни какой-либо другой peer на этом пути не вызывается — аллоцировать нечего. INSERT сериализуется с `LoadBalancer.Move` и `LoadBalancer.Delete` через locking-read строки LB: listener не может быть вставлен в LB, который уже помечен `DELETING`, и не может унести stale `projectId`.

**`Listener.Delete` VIP не освобождает** — освобождать нечего: адрес принадлежит LB и живёт дольше listener'а. Delete снимает строку listener'а (+ outbox), после чего DB-триггер пересчитывает `status` LB (`ACTIVE→INACTIVE`, если wired-listener'ов не осталось). Адрес высвобождается **только** при `LoadBalancer.Delete` / компенсации Create-саги (см. §VIP выше).

**Backend-IP таргета резолвится по семействам VIP родительского LB** (`ipFamilies`), а не по полю listener'а — listener семейства не несёт. Discovery-каталог инстансов surfaces обе семьи (`primaryV4Address`/`primaryV6Address`).

**Роутинг — только через `targetGroupId`.** Нет параллельного M:N-pivot и нет `:attachTargetGroup`-RPC: «привязать TG к LB» = навести на неё listener; «отвязать» = сменить/обнулить `targetGroupId`. `attachedTargetGroups` у LB — **производная** этих ссылок (в `?view=EXPAND`).

---

## TargetGroup

ID prefix `tgr` · owner `kacho_nlb.target_groups` · REST `/nlb/v1/targetGroups`

```jsonc
{
  "id": "tgr2w8r4t6y1u3i5o",
  "projectId": "prjf9k2m4x7q1w8r3",         // scope-slug → iam.Project; IMMUTABLE
  "regionId": "eu-north",                   // geo-slug → geo.Region; IMMUTABLE — TG REGION-scoped, LB-agnostic (reusable)
  "name": "web-backends",                   // DNS-1123; UNIQUE(project,name) partial
  "description": "",
  "labels": { "app": "web" },

  "port": 8080,                             // ЕДИНСТВЕННЫЙ backend-порт пула (1..65535) — «бэкенды слушают на N»; LIVE-mutable.
                                            //   Якорь backend-порта живёт ТОЛЬКО здесь; per-target/per-listener override ОТСУТСТВУЕТ
                                            //   by design (правило 9): другой backend-порт ⇒ отдельная reusable TargetGroup.
                                            //   probe наследует этот порт отсутствием probe.port-override

  "targetKinds": [ "compute.instance" ],    // ° derived aggregate типов присутствующих identity (['compute.instance','externalIp'…])
                                            //   — group-level read-signal «что за пул» поверх per-target 4-way identity

  "healthCheck": {                          // embedded value object (НЕ отдельный ресурс); скаляры — dotted-mask PATCH,
                                            //   смена пробы — atomic-replace (см. HealthCheck ниже)
    "interval": "2s",                       // duration-строка; bounds 1s..300s
    "timeout": "1s",                        // duration-строка; cross-field: timeout < interval (иначе InvalidArgument)
    "healthyThreshold": 2,                  // 2..10 — floor=2 (anti-flapping)
    "unhealthyThreshold": 2,                // 2..10 — floor=2 (anti-flapping)
    // exactly-one из проб (discriminated union). probe.port ОПУЩЕН ⟹ наследует TargetGroup.port; ЗАДАН ⟹ явный override:
    "http": { "path": "/healthz", "expectedCodes": "200-299",   // matcher дефолт 2xx; host/headers опц.
              "host": "", "headers": {} },  // tcp{} | http{...} | https{...} | grpc{serviceName}
    "effectivePort": 8080                   // ° derived output-only: разрешённый probe-порт (probe.port override ИЛИ TG.port)
  },

  "deregistrationDelay": "300s",            // duration-строка 0s..3600s; LIVE-mutable (connection-drain окно)
  "slowStart": "0s",                        // duration-строка 0s..900s; LIVE-mutable (ramp-up новых таргетов)

  "targets": [                              // ° children (см. Target); embed только при Create, далее :addTargets/:removeTargets/:updateTargets
    { "instance": { "type": "compute.instance", "id": "ctie1a3c5e7g9i1k", "name": "web-a-01" },
      "weight": 100, "status": "ACTIVE", "targetRefState": "RESOLVED" }   // ° polymorphic Referrer + вес
  ],
  "usedByListeners": [                      // ° DERIVED back-ref, EXPAND-only (parity с attachedTargetGroups на LB): listener'ы+LB, ссылающиеся на TG
    { "listenerId": "lst7h3k9m2x4q8w1t", "loadBalancerId": "nlb1a2b3c4d5e6f7g8h", "name": "tcp-443" }  // °
  ],

  "status": "ACTIVE",                       // ° ACTIVE|DELETING
  "createdAt": "2026-07-19T07:00:00Z",      // °
  "updatedAt": "2026-07-19T09:15:00Z"       // °
}
```

### HealthCheck (embedded value object)

Не first-class ресурс, без id/CRUD — живёт внутри TargetGroup, редактируется через `TargetGroup.Update`. Дисциплина маски — **тот же oneof-replace прецедент, что AddressPool v4/v6 split** (product-wide, не nlb-local):

- **скалярный dotted-mask PATCH** (`healthCheck.interval`, `healthCheck.timeout`, `healthCheck.healthyThreshold`, `healthCheck.unhealthyThreshold`) → частичный мёрж; **валидируется МЕРЖ** (напр. одиночный `healthCheck.interval` перевалидирует пару против **хранимого** `timeout`: `timeout < interval` на смёрженном объекте) — самое частое health-тюнинг-действие остаётся дешёвым;
- **atomic-replace** — ТОЛЬКО когда маска трогает саму **пробу** (`healthCheck.http`/`tcp`/`grpc`/`https`): смена типа пробы, где частичный мёрж бессмыслен → проба-дискриминатор ОБЯЗАН присутствовать (`InvalidArgument`, НЕ silent-clear). **Sibling-скаляры `interval`/`timeout`/`healthyThreshold`/`unhealthyThreshold` ВСЕГДА переживают смену типа пробы** (не сбрасываются в дефолт) — atomic-replace скоупится РОВНО в probe-oneof, не в весь `healthCheck`. Regression-lock: «probe-type switch preserves tuned scalars».

Проба — **discriminated union** (exactly-one); `port` опущен ⟹ наследует `TargetGroup.port` (эхается `effectivePort°`), задан ⟹ override пробы. http/https несут matcher/host/headers:

```jsonc
"healthCheck": {
  "interval": "2s", "timeout": "1s", "healthyThreshold": 2, "unhealthyThreshold": 2,
  "grpc": { "serviceName": "grpc.health.v1.Health" },   // port опущен → TG.port
  "effectivePort": 8080                                  // ° = TG.port (тюн-скаляры выше уцелеют при смене на tcp/http/https)
  // альтернативы (ровно одна):
  //   "tcp":   { }                                                            // L4 connect-check на TG.port
  //   "http":  { "path": "/healthz", "expectedCodes": "200-299",              // 2xx = healthy (matcher настраиваемый)
  //              "host": "api.internal", "headers": { "X-Probe": "nlb" } }     // port опущен → TG.port
  //   "https": { "port": 8443, "path": "/healthz", "expectedCodes": "200,204", // явный override пробы (TLS + matcher)
  //              "host": "", "headers": {} }                                    // → effectivePort° = 8443
}
```

### Target (child of TargetGroup)

Без id-prefix (композитный child). **4-way identity — exactly-one**, DB-CHECK + domain-validate. instance/nic/ipRef — polymorphic graceful-dangling Referrer; externalIp — raw-строка (out-of-cloud, resolve нет, только sync bogon-check):

```jsonc
// (1) compute-инстанс — resolve instance→primary NIC→primary IP (по семействам VIP родительского LB) в worker.
//     region-coherent: instance ЗОНАЛЕН (region-поля нет) → 2-hop derive geo.Zone(instance.zoneId).regionId == TG.regionId.
//     ⚠ instance-target resolution semantics PENDING compute-redesign-2026 attach model (см. reference-law + правило 6):
//        primary NIC = lowest-index ИЛИ explicitly-flagged; multi-NIC ambiguity → FailedPrecondition, называет instance.
{ "instance": { "type": "compute.instance", "id": "ctie1a3c5e7g9i1k", "name": "web-a-01" },  // name°
  "weight": 100, "status": "ACTIVE", "targetRefState": "RESOLVED" }   // ° status: lifecycle (ACTIVE|DRAINING)

// (2) vpc NetworkInterface — прямой, НЕ зависит от attach-редизайна (load-bearing путь).
//     region-coherent (2-hop через subnet zone→region); zone-coherent при wire к ZONAL-LB
{ "nic": { "type": "vpc.networkInterface", "id": "nic4f6h8j0l2n4p6r", "name": "web-a-01-eth0" },
  "weight": 100, "status": "ACTIVE", "targetRefState": "RESOLVED" }

// (3) in-cloud raw IP (валидируется ∈ CIDR subnet'а; subnet region-coherent с TG) — load-bearing путь
{ "ipRef": { "subnetId": "sub3e5r7t9y1u3i5o7", "address": "10.20.1.15" },
  "weight": 50, "status": "ACTIVE", "targetRefState": "RESOLVED" }

// (4) out-of-cloud raw IP (bogon-reject: loopback/link-local/multicast/unspecified/v4-mapped) — load-bearing путь
{ "externalIp": { "address": "198.51.100.7", "affinityZoneId": "eu-north-a" },  // affinityZoneId — routing-hint,
                                                                                 //   НЕ coherence-проверяется (external вне geo-authority); опционален
  "weight": 100, "status": "DRAINING", "drainStartedAt": "2026-07-19T09:10:00Z", "targetRefState": "RESOLVED" }  // °
}
```

- **`status`** (`ACTIVE|DRAINING`) — **lifecycle-ось, единое имя во ВСЕХ проекциях** (targets[] И targetStates[]); authoritative для «берёт ли трафик»; `DRAINING` сопровождается `drainStartedAt°`.
- **`targetRefState`** (`RESOLVED|STOPPED|DANGLING`) — **ТОЛЬКО ref-резолюция** owner'ом: `RESOLVED` (owner отдаёт живой ресурс) · `STOPPED` (ресурс существует, но не в serving-состоянии — напр. остановленный инстанс → ремонт ≠ delete) · `DANGLING` (owner НЕ резолвит — ресурс удалён → нужна замена/removeTargets). Делает graceful-dangling **наблюдаемым и remediation-различимым**, отдельно от probe-fail.
- `:addTargets` идемпотентен (`ON CONFLICT DO NOTHING` per identity-key). `:removeTargets` — 2-фазный drain (Phase A мгновенно `status=DRAINING`, Operation `done=true` быстро; Phase B — фоновый runner удаляет по истечении `deregistrationDelay`). `:updateTargets` — сменить `weight` и/или тогглить in-place drain/undrain (`status: DRAINING↔ACTIVE`) БЕЗ дерегистрации (стандартный weighted-pool / maintenance-drain жест, без remove+re-add).

---

## Runtime health-проекция (tenant-facing результат)

Sync-снимок «намерение + результат» с per-target диагностикой пробы (tenant-сигнал health-тюнинга, **не** инфра-физика). Доступен и на LB, и **TG-scoped** (валидировать пробу без attach к живому LB — пробы **реально стреляют** и в TG-scoped режиме). Коллекция — List-образная (пул в сотни таргетов) → **product-wide cursor-pagination** + `summary`-агрегат:

```jsonc
// GET /nlb/v1/networkLoadBalancers/{id}/targetStates?pageSize=50&pageToken=…
// GET /nlb/v1/targetGroups/{id}/targetStates?pageSize=50&pageToken=…    ← TG-scoped: пробы стреляют даже без listener'а
{
  "summary": {                              // ° агрегат по ВСЕМУ пулу (не по странице) — health-дебаг без ручной свёртки
    "total": 42, "healthy": 38, "unhealthy": 2, "warmingUp": 1, "draining": 1, "dangling": 0,
    "serving": 38,                          // ° сколько реально берут трафик (status=ACTIVE ∧ HEALTHY ∧ RESOLVED)
    "backendPort": 8080 },                  // ° backend-порт пула = TargetGroup.port (один раз, а не в каждой строке)
  "targetStates": [
    { "targetGroupId": "tgr2w8r4t6y1u3i5o",
      "target": { "instance": { "type": "compute.instance", "id": "ctie1a3c5e7g9i1k", "name": "web-a-01" } },
      "servingTraffic": false,      // ° DERIVED single-glance: (status=ACTIVE ∧ healthState=HEALTHY ∧ targetRefState=RESOLVED)
      "healthState": "UNHEALTHY",   // ° health-first (исход пробы): WARMING_UP(«ниже healthyThreshold»)|HEALTHY|UNHEALTHY
                                    //   |UNUSED(«TG не привязана НИ ОДНИМ listener'ом» — ТОЛЬКО в LB-scoped контексте; TG-scoped даёт реальный health)
      "status": "ACTIVE",           // ° traffic-admission LIFECYCLE, НЕ health (см. healthState) — ЕДИНОЕ имя оси; ACTIVE|DRAINING
      "targetRefState": "RESOLVED", // ° RESOLVED|STOPPED|DANGLING — «backend gone/stopped» отличается от probe-fail
      "probePort": 8080,            // ° разрешённый probe-порт (probe.port override ИЛИ TG.port) — может отличаться от backendPort (в summary)
      "lastProbe": {                // ° per-target диагностика причины (public — намерение+результат, не топология)
        "outcome": "UNEXPECTED_STATUS",  // SUCCESS|CONNECTION_REFUSED|TIMEOUT|UNEXPECTED_STATUS|TLS_ERROR
        "observedCode": 503,             // http/https observed status (или "" для tcp/grpc)
        "latencyMs": 12 },
      "recentProbes": [             // ° bounded ring последних N исходов (flapping виден без Watch RPC)
        { "outcome": "UNEXPECTED_STATUS", "observedCode": 503, "at": "2026-07-19T09:40:05Z" },
        { "outcome": "SUCCESS", "observedCode": 200, "at": "2026-07-19T09:40:03Z" } ],
      "consecutiveFailures": 3,     // °
      "lastCheckedAt": "2026-07-19T09:40:05Z",   // °
      "lastTransitionAt": "2026-07-19T09:39:41Z",// °
      "zoneId": "eu-north-a" }      // ° зона таргета (для cross-zone-видимости)
    // node/host/programming-status/underlay — НЕ здесь; только Internal
  ],
  "nextPageToken": "eyJjcmVhdGVkQXQiOiIyMDI2…"   // ° cursor (created_at,id); пусто = конец
}
```

---

## RPC surface

Все RPC — на обоих листенерах — под per-RPC authz-Check (`InternalIAMService.Check` → OpenFGA), fail-closed, mTLS/JWT. Object-scoped `scope_extractor` резолвит target→project (анти-BOLA).

### NetworkLoadBalancerService — `kacho-nlb:9090` (public)

| RPC | Тип | REST |
|---|---|---|
| `Get` | sync | `GET /nlb/v1/networkLoadBalancers/{id}` (`?view=DEFAULT\|EXPAND` — EXPAND добавляет derived `attachedTargetGroups`) |
| `List` | sync | `GET /nlb/v1/networkLoadBalancers` — filter `name=`, cursor `(created_at,id)`, per-object listauthz |
| `Create` | **async → Operation** | `POST /nlb/v1/networkLoadBalancers` — **DEFAULT onboarding path**, one-shot: обязательный `placement`, per-family `v4Source`/`v6Source` (VIP-сага), `listenerSpecs[]`, каждый со своей `targetGroupId` (existing) ИЛИ inline `targetGroup{…}` (TG+HC+targets создаются в ТОЙ ЖЕ Operation в dependency-порядке) |
| `Update` | **async → Operation** | `PATCH /nlb/v1/networkLoadBalancers/{id}` — UpdateMask |
| `Delete` | **async → Operation** | `DELETE /nlb/v1/networkLoadBalancers/{id}` — sync-precheck (deletion-protection, «есть listener'ы»); **освобождает VIP каждого семейства** по origin (`auto` → в пул, `linked` → снять референс); опц. body `{cascade:true}` (within-service каскад listener'ов, cross-service TG — detach не delete) |
| `Move` | **async → Operation** | `POST …/{id}:move` — cross-project, same-region |
| `GetTargetStates` | sync | `GET …/{id}/targetStates` — paginated + summary |
| `ListOperations` | sync | `GET …/{id}/operations` |

> Power-модель compute-стиля отсутствует: **нет `:start`/`:stop` RPC** — enable/disable выражается LIVE-mutable полем `adminState` через `Update`. Роутинг-wiring (LB↔TG) — через Listener; **нет** `AttachTargetGroup`/`DetachTargetGroup`.

### ListenerService — `kacho-nlb:9090` (public)

| RPC | Тип | REST |
|---|---|---|
| `Get` / `List` / `ListOperations` | sync | `GET /nlb/v1/listeners…` |
| `Create` | **async → Operation** | `POST /nlb/v1/listeners` — INSERT + wire `targetGroupId` в одной Operation, без внешних side-effect'ов (VIP уже на LB). Требует **существующую** `targetGroupId` |
| `Update` | **async → Operation** | `PATCH /nlb/v1/listeners/{id}` — `targetGroupId`/`proxyProtocolV2`/name/labels |
| `Delete` | **async → Operation** | `DELETE /nlb/v1/listeners/{id}` — снимает строку; VIP не трогает (принадлежит LB) |

### TargetGroupService — `kacho-nlb:9090` (public)

| RPC | Тип | REST |
|---|---|---|
| `Get` / `List` / `ListOperations` | sync | `GET /nlb/v1/targetGroups…` |
| `GetTargetStates` | sync | `GET /nlb/v1/targetGroups/{id}/targetStates` — TG-scoped health-view (пробы стреляют без attach; paginated + summary) |
| `Create` | **async → Operation** | `POST /nlb/v1/targetGroups` — inline `targets[]` + `healthCheck` + `port` в одной Operation |
| `Update` | **async → Operation** | `PATCH /nlb/v1/targetGroups/{id}` — `port`/HC(scalar-dotted \| probe-atomic)/dereg/slow-start/labels; targets отдельно |
| `Delete` | **async → Operation** | `DELETE /nlb/v1/targetGroups/{id}` — precheck: no referencing listener, no targets |
| `Move` | **async → Operation** | `POST …/{id}:move` — blocked при referencing-listener |
| `AddTargets` / `RemoveTargets` / `UpdateTargets` | **async → Operation** | `POST …/{id}:addTargets` · `:removeTargets` (2-phase drain) · `:updateTargets` (weight + in-place drain/undrain без дерегистрации) |

### OperationService — `kacho-nlb:9090` (public, sync)

`GET /nlb/v1/operations/{id}` — клиент поллит до `done=true`. Watch RPC нет.

```jsonc
// POST /nlb/v1/networkLoadBalancers → 200 (id доступен в metadata СРАЗУ, до done):
{ "id": "opr9x2m4k6q8w0e2r", "description": "create network load balancer",
  "createdAt": "2026-07-19T08:12:00Z", "done": false,
  "metadata": { "@type": "…CreateNetworkLoadBalancerMetadata",
                "networkLoadBalancerId": "nlb1a2b3c4d5e6f7g8h",     // ← id есть сразу
                "readReadyHintMs": 5000 } }                          // ← НЕ-authoritative hint: типичное окно материализации owner-tuple
```

`done=true` = ресурс **DURABLE** (row закоммичена). Видимость owner-tuple в FGA — eventually-consistent (не гейтится на `done`). **ПЕРВЫЙ `Get`/`Update`/`Delete` своего только что созданного ресурса может кратко отдать `403`/`404` (owner-tuple ещё материализуется), List — не содержать его: это read-your-writes лаг, НЕ «create молча провалился».**

**Официальный клиентский дефолт (не серверный барьер, ban #9):** SDK по умолчанию оборачивает **первый** пост-create self-доступ в `retry_until_authorized(step)` (retry на transient `403`/`404` у Get/Update/Delete своего свежего ресурса) и `retry_until_present(step, "<idVar>")` (retry у List пока id отсутствует); budget ≈ `readReadyHintMs`×запас (~10s), fail-open по budget → реальный assert падает если не сошлось. Оборачивать ТОЛЬКО первый доступ к своему свежему ресурсу — НИКОГДА negative/cross-account/absent-id. Confirm-gate на видимость запрещён (phantom-ресурс).

### Internal-only — `kacho-nlb:9091` (mTLS, cluster-internal; НЕ на external :443)

| RPC | Тип | Назначение |
|---|---|---|
| `InternalResourceLifecycleService.Subscribe` | server-stream | outbox lifecycle-события → kacho-iam (hierarchy tuple sync) |
| `NetworkLoadBalancerInternalService.Get` | sync | full-проекция с инфра-полями (two-projection) |

Оба листенера несут authz-Check (internal НЕ освобождён).

---

## Discovery-каталоги (sync, рядом с мутацией)

Не гадать id вслепую — каждый item несёт готовый inline-фрагмент запроса. Каталоги покрывают **весь** путь one-shot Create: обязательную первую координату (`regionId`), выбор таргетов (**во время** Create, не только после), оба reject-prone источника VIP LoadBalancer'а. Все фильтруются listauthz + региональной когерентностью — они *и есть* контракт «что я могу выбрать». **Дедуп:** `addable*` каталоги — по ОДНОМУ RPC на kind, scope-параметризованы (`?targetGroupId=` для TG-scoped ИЛИ `?regionId=&projectId=` для create-time); оба VIP-источника (subnet-auto + link существующего Address) слиты в один `:vipAnchorCandidates`.

```jsonc
// GET /nlb/v1/networkLoadBalancers:regions   ← region-discovery для САМОЙ ПЕРВОЙ обязательной координаты
{ "items": [
  { "regionId": "eu-north", "displayName": "EU North", "zoneIds": ["eu-north-a","eu-north-b"],
    "createFragment": { "regionId": "eu-north" } }  // ← в POST /networkLoadBalancers
]}

// GET /nlb/v1/networkLoadBalancers:addableInstances?regionId=eu-north&projectId=prjf9k2m4x7q1w8r3&ipVersion=IPV4
//   ── ИЛИ TG-scoped ── GET /nlb/v1/targetGroups/{id}:addableInstances     (один RPC, scope через query)
// → compute-инстансы проекта в регионе, ДОСТУПНЫ ВО ВРЕМЯ one-shot Create (create-time, нет LB id).
//   Surface ОБЕ семьи; backend-IP резолвится по семействам VIP родительского LB:
{ "items": [
  { "instanceId": "ctie1a3c5e7g9i1k", "name": "web-a-01", "regionId": "eu-north", "zoneId": "eu-north-a",
    "primaryV4Address": "10.20.1.15", "primaryV6Address": "2001:db8:20:1::15",
    "addFragment": { "instance": { "id": "ctie1a3c5e7g9i1k" }, "weight": 100 } }  // ← в listenerSpec.targetGroup.targets[] ИЛИ :addTargets
]}

// GET /nlb/v1/networkLoadBalancers:addableNetworkInterfaces?regionId=eu-north&projectId=prjf9k2m4x7q1w8r3
//   ── ИЛИ TG-scoped ── GET /nlb/v1/targetGroups/{id}:addableNetworkInterfaces   (один RPC, scope через query)
{ "items": [
  { "networkInterfaceId": "nic4f6h8j0l2n4p6r", "name": "web-a-01-eth0", "regionId": "eu-north", "zoneId": "eu-north-a",
    "primaryV4Address": "10.20.1.15", "primaryV6Address": "2001:db8:20:1::15",
    "addFragment": { "nic": { "id": "nic4f6h8j0l2n4p6r" }, "weight": 100 } }
]}

// GET /nlb/v1/networkLoadBalancers:vipAnchorCandidates?regionId=eu-north&projectId=prjf9k2m4x7q1w8r3&placement=INTERNAL_ZONAL&ipVersion=IPV4
// → ЕДИНЫЙ каталог «чем заякорить VIP LB»: subnet-кандидаты (для INTERNAL auto) И свободные vpc.Address для link,
//   УЖЕ отфильтрованные по placementType LB (ZONAL→ZONAL) + региону + семье — снимает оба самых reject-prone входа
//   NetworkLoadBalancer.Create (фрагменты кладутся в v4Source/v6Source, НЕ в listener):
{ "subnets": [
    { "subnetId": "sub3e5r7t9y1u3i5o7", "name": "internal-a", "regionId": "eu-north", "zoneId": "eu-north-a",
      "placementType": "ZONAL", "freeV4Count": 250,
      "wireFragment": { "v4Source": { "subnetId": "sub3e5r7t9y1u3i5o7" } } } ],   // ← INTERNAL auto-alloc из подсети
  "addresses": [
    { "addressId": "adrt8y2u4i6o8p0aq1", "name": "north-vip-1", "ip": "203.0.113.40", "ipVersion": "IPV4",
      "placementType": "REGIONAL", "regionId": "eu-north",
      "wireFragment": { "v4Source": { "addressId": "adrt8y2u4i6o8p0aq1" } } } ] } // ← link существующего Address

// GET /nlb/v1/networkLoadBalancers/{id}/referenceableTargetGroups   ← LB-scoped (для смены listener.targetGroupId)
{ "items": [
  { "targetGroupId": "tgr2w8r4t6y1u3i5o", "name": "web-backends", "regionId": "eu-north",
    "port": 8080, "targetCount": 3,
    "wireFragment": { "targetGroupId": "tgr2w8r4t6y1u3i5o" } }  // ← в listener Create/Update
]}
```

---

## Правила (нормативно)

1. **Flat, без envelope.** Domain-поля на верхнем уровне; никаких `spec/status/metadata/resourceVersion`. `°` — output-only (server-set: `id`, `status`/`substatus`(derived), `type`/`placementType`(derived), `v4AddressId`/`v6AddressId`, `resolvedBackendPort`, `healthCheck.effectivePort`, `targetKinds`, `targetRefState`, `servingTraffic`, `probePort`, `recentProbes`, все denorm-зеркала и derived-коллекции `usedByListeners`/`attachedTargetGroups` (обе EXPAND-only), Referrer.`name`). **Persist остаётся один факт — `placement`**; `type`/`placementType` не персистятся, но **эмитятся** output-only (queryable, паритет с `placement_type` у родственников — не форсить клиента re-парсить enum-строку). `v4Source`/`v6Source` — зеркальный случай: **input-only**, в ответе не эхаются (результат наблюдаем через `v4AddressId°`/`v6AddressId°`).
2. **Read sync, mutate async.** `Get`/`List`/`Get*States`/discovery-каталоги — sync. `Create`/`Update`/`Delete`/`:verb` → `Operation`; id ресурса — в `Operation.metadata` немедленно. Клиент поллит `OperationService.Get`. Watch RPC нет.
3. **`Operation.done` = durability, НЕ downstream-видимость.** owner-tuple/зеркала материализуются в ограниченном окне (outbox+drainer+reconciler). Confirm-gate на видимость запрещён (ban #9, phantom). «Создал→сразу мутирую» — **официальный SDK-дефолт `retry_until_authorized`/`retry_until_present`** (bounded, на транзиентном 403/404), оборачивать ТОЛЬКО первый доступ к своему свежему ресурсу; опц. `Operation.metadata.readReadyHintMs` — НЕ-authoritative hint окна. Сервер `readReadyHintMs` не гейтит done.
4. **Create — one-shot по умолчанию; incremental-нарратив НЕ инвертирует FK-топологию.**
   - **one-shot (DEFAULT, ведёт весь onboarding):** `NetworkLoadBalancer.Create` принимает `listenerSpecs[]`, где каждый listener несёт `targetGroupId` (existing) ЛИБО inline `targetGroup{port, healthCheck (embedded value object, НЕ ресурс), targets[]}` — сервер разворачивает TG+HC+targets+VIP-сагу **в dependency-порядке** в ТОЙ ЖЕ Operation с компенсацией на откате. Один вызов, FK-порядок скрыт.
   - **incremental (продвинутый): `TargetGroup(-first) → Listener → LB-wire`.** Порядок диктуется FK: Listener **REFERENCES** TargetGroup (RESTRICT) → TG создаётся **до** listener'а. HealthCheck — под-часть шага TG, не отдельный шаг; «attach TG к LB» — не RPC, а наведение listener'а. Ошибка actionable: `"listener requires an existing targetGroupId; create the TargetGroup first (POST /nlb/v1/targetGroups) or use one-shot NetworkLoadBalancer.Create"` (НЕ «no target group to wire»).
   - Не заставлять делать 3 вызова там, где логичен один.
5. **`validateOnly:true` — sync dry-run.** Полная валидация (peer-checks региона/зоны/subnet/instance/SG, placement-когерентность, VIP-конфликт, **unwired-listener → warnings[]**, **per-target zone-verdict list**, **crossZone-on-ZONAL → reject**) БЕЗ мутации/Operation/state-gate. Возвращает `warnings[]` + echo выведенных значений: выведенную зону VIP-источника (ДО коммита), resolved target-IP (по семействам VIP LB), `resolvedBackendPort`/`effectivePort`, предпросмотр связываемого Address.
6. **Reference law — по классу ссылки, не ради единообразия.**
   - within-service (`Listener.loadBalancerId`, `Listener.targetGroupId`, TG-back-ref) → **flat id + DB FK** (RESTRICT).
   - scope/placement-АНКЕР (`projectId`, `regionId`; `securityGroupIds`; **LB `v4Source`/`v6Source`** — выбор-анкер источника VIP, НЕ dependency-Referrer) → **flat slug + peer-validate hard-fail** (geo/iam/vpc). `v4Source`/`v6Source` — immutable **input**; результат эхается ЕДИНОЖДЫ как `v4AddressId°`/`v6AddressId°` (id связанного `vpc.Address`, БЕЗ дубля самой IP-строки — её отдаёт владелец).
   - зависимость на чужой owned-ресурс (Target identity) → **`Referrer{type,id,name°}` polymorphic, graceful-dangling** (dangling/stopped → `targetRefState`, не паника).
   - **instance-target resolution chain (документировано, PENDING cross-repo):** `instance → primary NIC → primary IP по семействам VIP родительского LB`. **primary NIC** детерминирован: lowest-index NIC ИЛИ explicitly-flagged; **multi-NIC ambiguity → `FailedPrecondition`, называющий instance** (не молчаливый выбор). Instance-target **gated на compute-redesign-2026 `AttachNetworkInterface`** (vpc KAC-266 снял public Attach/Detach; редизайн вводит его заново) — до settling instance-target несёт пометку «resolution semantics pending compute attach model»; **`nic`/`ipRef`/`externalIp` — load-bearing пути** (не зависят от attach-редизайна).
7. **Two-projection.** Публичная поверхность = намерение (`placement`/`region`/`adminState`/specs) + результат (`status`/`substatus`/`type`/`placementType`/`v4AddressId°`/`v6AddressId°`/`healthState`/`servingTraffic`/`lastProbe`). Инфра-чувствительное (dataplane-node, vrf/routing-id, programming-status, numeric-infra-id, wiring, announce-состояние) — ТОЛЬКО `*Internal*` на :9091. «Underlay-зоны public-VIP» в модели нет: EXTERNAL всегда REGIONAL/anycast, его VIP берётся из зоне-независимого пула (правило 10). Сама IP-строка VIP на публичной поверхности nlb **не дублируется**: наружу идёт `v4AddressId°`/`v6AddressId°`, IP отдаёт владелец (`vpc.AddressService.Get`) — один источник истины, без расхождения зеркал. Per-target `lastProbe`/`recentProbes`/`consecutiveFailures` — tenant-сигнал (health-тюнинг), не топология → остаётся public.
8. **Роутинг — одна нормализованная связь; substatus — производная.** «Listener → TargetGroup» выражается ТОЛЬКО `Listener.targetGroupId`. Набор attached-TG у LB — **производная** (объединение ссылок listener'ов), EXPAND-only (LEAN). Нет M:N-pivot и нет attach/detach-RPC. `listener.substatus` (`OK|MISCONFIGURED`) — **чистая server/client-производная** (`targetGroupId==null || unresolving`), НЕ персистится (тот же факт, что LB `DEGRADED`, на уровне listener'а). Listener без резолвящейся TG ⟹ `MISCONFIGURED` (reason `listener <id> has no target group`) ⟹ LB `DEGRADED` (silent-blackhole не маскируется под ACTIVE).
9. **Один backend-порт = одно поле одного ресурса.** Backend-порт живёт ТОЛЬКО в `TargetGroup.port`. **Нет** `Listener.targetPortOverride` — listener'у с другим backend-портом ссылаться на ДРУГУЮ (reusable, дешёвую) TargetGroup. `probe.port` **наследует** `TargetGroup.port` **отсутствием** override (unset — НЕ magic-zero); задан ⟹ явный per-probe override. Оба порта наблюдаемы БЕЗ dry-run: `Listener.resolvedBackendPort°`, `healthCheck.effectivePort°`, `targetStates.summary.backendPort°`/`.probePort°` — расхождение probe-vs-traffic исчезает by construction, но остаётся видимым.
10. **Placement-когерентность; TG region-scoped и LB-agnostic.** Один immutable input-дискриминатор `placement ∈ {EXTERNAL_REGIONAL|INTERNAL_REGIONAL|INTERNAL_ZONAL}` — «external+zonal» невыразима by construction.
    - **TG region-coherence** проверяется ВСЕГДА на TG (`:addTargets`/Create). Instance зонален (region-поля не несёт) → **2-hop derive** `geo.Zone(instance.zoneId).regionId == TG.regionId`; error derive-aware: `"<target> zone %s is in region %s, target group region is %s"`.
    - **TG zone-coherence** — двухфазно, снимает self-contradiction «REGIONAL-легален, ZONAL-нелегален»: (a) на `:addTargets` — **`warnings[]` (не reject)**, если таргет вне зоны ЛЮБОГО уже-ссылающегося ZONAL-LB (warn в точке входа таргета, называет target id и его зону); (b) на **wire** listener'а ZONAL-LB → TG — **hard precheck** (все таргеты TG резолвятся в зону LB), error называет SPECIFIC target id: `"<target> is in zone %s, load balancer zone is %s"`. Reusable region-scoped TG **перестаёт принимать out-of-zone таргеты, как только на неё ссылается ZONAL-LB** (граница region/zone-reusability). `externalIp` и REGIONAL-subnet-`ipRef` таргеты на ZONAL-wire — **anycast-exempt** (нет резолвимой зоны → исключены из zone-check by construction, как REGIONAL).
    - ZONAL LB пинится зоной **своего VIP-источника** — отдельного input/output-`zoneId` нет и order-dependence не возникает: VIP аллоцируется единожды, в `NetworkLoadBalancer.Create`, а listener'ы адреса не выбирают. Инварианты Create: `placementType` подсети (или подсети linked-адреса) ОБЯЗАН совпасть с `placementType` LB, подсеть ОБЯЗАНА быть region-coherent (`"load balancer vip subnet must be in the same region as the load balancer"`), dualstack v4/v6 → ОДНА сеть (`"dualstack load balancer families must resolve to the same network"`) и ОДНА зона (`"dualstack load balancer families must resolve to the same zone"`). REGIONAL/anycast из зональной проверки исключён by construction (его подсети зоны не несут).
    - `crossZoneEnabled` действует только для REGIONAL. **Для ZONAL write `crossZoneEnabled != false` → `InvalidArgument "crossZoneEnabled is not applicable to ZONAL placement"`** (не молчаливый inert). REGIONAL — anycast, из зональной проверки исключён by construction.
    - **`securityGroupIds` — SAME-PROJECT existence-check ТОЛЬКО** (без region-coherence): vpc.SecurityGroup network-scoped, region/zone-поля не несёт — с чем когерировать нет.
11. **Update — единообразные mutability-классы.**
    - **immutable** (reject ДО `UpdateMask`, тон `"<field> is immutable after <R>.Create"`): LB `placement`/`regionId`/`projectId`/`v4Source`/`v6Source` (VIP-источник фиксируется на Create; сменить VIP = пересоздать LB); Listener `loadBalancerId`/`protocol`/`port`; TG `projectId`/`regionId`. `type`/`placementType` на LB — не просто immutable, а **derived output-only**: их передача даже на Create → `InvalidArgument "<field> is derived output-only; the load balancer mode is set solely by placement"`.
    - **LIVE-mutable**: `name`/`description`/`labels`, `adminState`, `sessionAffinity`, `crossZoneEnabled` (REGIONAL only), `deletionProtection`, `securityGroupIds`, `proxyProtocolV2`, `targetGroupId`, TG `port`, `deregistrationDelay`, `slowStart`.
    - **`healthCheck` — oneof-replace дисциплина (прецедент AddressPool v4/v6):** скаляры (`.interval`/`.timeout`/`.healthyThreshold`/`.unhealthyThreshold`) — **точечный dotted-mask PATCH**, валидируется МЕРЖ (bounds `interval∈[1s,300s]`, cross-field `timeout<interval` на смёрженной паре, threshold `2..10`); **atomic-replace** — ТОЛЬКО при маске на пробу (`.http/.tcp/.grpc/.https`): проба-дискриминатор обязателен (`InvalidArgument`, НЕ silent-clear), **sibling-скаляры ВСЕГДА уцелевают** при смене типа пробы.
    - **admin-state сохраняется**: Update никогда не авто-ENABLE'ит `DISABLED`-LB.
    - пустая маска → full-object PATCH mutable-полей; immutable из тела silently игнорируются.
12. **Единый тон ошибок (контракт).** `"<Resource> <id> not found"` · `"<field> is immutable after <R>.Create"` · malformed-id → `InvalidArgument "invalid <res> id '<X>'"` ПЕРВЫМ стейтментом RPC. **Prefix+base32 / `"invalid <res> id"` format-check применяется ТОЛЬКО к nlb-owned id (`nlb`/`lst`/`tgr`).** **Записанное узкое исключение** (B4 carve-out, решение принято — `services/nlb/docs/engineering/architecture/08-known-divergences.md` §«Формат чужого id (VIP-источники)»): `v4Source`/`v6Source` несут **vpc-owned** `subnetId`/`addressId`, и они прогоняются через `corevalidate.ResourceID` ДО peer-validate. Две прежние формулировки этого места были **фактически неверны** и сняты: (а) это **не** сверка «своего vpc-prefix'а» — функция **family-agnostic по контракту**, `expectedPrefix` в ней не читается, проверяется лишь членство первого сегмента в **платформенном** каталоге `ids.KnownPrefixes()`/`KnownHyphenPrefixes()`+config-extras (id с чужим для поля префиксом проходит к владельцу); (б) это **и есть** prefix-check, а не «разбор oneof-варианта». Мотив исключения — что видит вызывающий: терминальный `INVALID_ARGUMENT "invalid subnet id '<X>'"` вместо retryable `UNAVAILABLE` при недоступном vpc и вместо ложного `"subnet <X> not found"`; тип/существование/placement решает владелец. Пустая ссылка выбранной ветки oneof → `"<v4|v6>_source.subnet_id: required"` (форма запроса). Всё остальное foreign (instance/nic/`securityGroupId`/`projectId`) — peer-validated existence-only, **НИКОГДА не prefix-checked**. Placement-координаты (`regionId`/`zoneId`) — geo-owned human slugs (DNS-1123), освобождены от prefix/base32; валидируются peer-existence (`geo.Region/ZoneService.Get`). Коды: `INVALID_ARGUMENT` (формат; матрица источник×режим — `"subnet address source is only valid for INTERNAL load balancer"` / `"public address source is only valid for EXTERNAL load balancer"` / `"load balancer must declare a vip source for at least one ip family"`; placement-coherence VIP — region/network/zone-mismatch; анти-oracle `"Illegal argument addressId"`; `crossZoneEnabled-on-ZONAL`), `NOT_FOUND` (well-formed-но-нет), `FAILED_PRECONDITION` (`"network load balancer has listeners: [<ids>]"` / `"target group is referenced by listeners: [<ids>]"` / **`"could not assign address to load balancer"`** (per-region VIP double-claim, generic) / **`"load balancer already has an address for this family"`** (CAS single-VIP-per-LB) / **`"could not allocate load balancer address"`** (пул исчерпан/источник не резолвится — намеренно лосси, причина уходит в server-лог) / multi-NIC-ambiguity / deletion-protection), `ALREADY_EXISTS` (UNIQUE name; **VIP-конфликт сюда НЕ попадает** — он generic FAILED_PRECONDITION, анти-oracle), `UNAVAILABLE` (geo/vpc/compute/iam down — fail-closed для мутаций), `INTERNAL` (opaque, без pgx-leak).
13. **Teardown — RESTRICT (product-decision), precheck перечисляет блокеры.** Delete LB/TG падает `FailedPrecondition` со **списком** блокирующих id, чтобы порядок не угадывался. Опц. `Delete{cascade:true}` — детерминированный within-service каскад listener'ов + detach TG (не delete) в ОДНОЙ Operation (ban #4).
14. **authz на КАЖДОМ RPC обоих листенеров.** Read/discovery → viewer-floor; мутации → editor на target-объекте (`nlb_network_load_balancer`/`nlb_listener`/`nlb_target_group`), Create → editor на `project`, Move → editor на src+dst project. `scope_extractor` (object_type + from_request_field) резолвит target→project — иначе BOLA. Permission-catalog генерируется из proto, byte-identical в iam-seed и gateway. `List`/`Get*States` фильтруются listauthz (валидация pagination — ДО empty-grant short-circuit).
15. **Одна конвенция длительностей.** Все длительности модуля — **duration-строки** (`interval:"2s"`, `timeout:"1s"`, `deregistrationDelay:"300s"`, `slowStart:"0s"`, под `google.protobuf.Duration`) — **nlb canon** (при расхождении с compute/vpc/storage anchor'ом — pending product-wide convergence, не форсить кросс-модульную uniformity голословно); никаких смешанных `*Seconds int` внутри модуля.
16. **Формат / pagination.** JSON camelCase; nlb-owned id = 3-char prefix (`nlb`/`lst`/`tgr`) + base32; UNIQUE(project,name) partial (пустое name допустимо); timestamps truncate до секунд на всех уровнях (включая embedded/child `drainStartedAt`/`lastCheckedAt`/`recentProbes[].at`/…). Cursor-pagination `(created_at,id)` на `List` **И `GetTargetStates`** (`page_size` 0→50/max1000, вне диапазона → `InvalidArgument`, не clamp; `GetTargetStates` несёт `summary`-агрегат по всему пулу, включая `serving`/`backendPort`). Каноническое существительное — **NetworkLoadBalancer** во всей прозе/RPC/metadata-key; id-prefix `nlb` — ASCII-идентификатор.
17. **Статус-глоссы несут причину; три target-оси + одна сводная.** LB: `INACTIVE`(«config incomplete: нет listener'ов») · `DEGRADED`(«есть MISCONFIGURED-listener без TG») · `DISABLED`(«admin-выключен, конфиг цел», не failure). Target-оси **ортогональны**: lifecycle-`status`(«traffic-admission, гейтит трафик», ACTIVE|DRAINING) ⟂ `healthState`(«исход пробы»: `WARMING_UP`«ниже healthyThreshold» / HEALTHY / UNHEALTHY / `UNUSED`«TG не привязана НИ ОДНИМ listener'ом», UNUSED — ТОЛЬКО LB-scoped; TG-scoped даёт реальный health, пробы стреляют) ⟂ `targetRefState`(«owner-резолюция»: RESOLVED|STOPPED«существует, не serving»|DANGLING«удалён»). Сервер сворачивает их в один output-only **`servingTraffic° = (status=ACTIVE ∧ HEALTHY ∧ RESOLVED)`** — «берёт ли трафик» одним взглядом, без ручной свёртки трёх осей. `slowStart`(«traffic ramp: healthy, вес поднимается») ≠ `WARMING_UP` (переименован из INITIAL, чтобы не путать с slowStart).
18. **Access control / power-модель — LB-нативно.** Frontend VIP защищается `securityGroupIds[]` (vpc.SecurityGroup, same-project; LB-уровневый firewall; делегирование firewalling target-side — явное решение, не молчаливый пробел). Endpoint LB — связанный `vpc.Address` (`v4AddressId°`/`v6AddressId°`); managed DNS-имени поверх него модуль не выпускает. Enable/disable — LB-нативный `adminState: ENABLED|DISABLED` (LIVE-mutable), **не** compute `:start`/`:stop`.
19. **Vendor-agnostic (ban #2).** Ни в полях, ни в типах, ни в enum-значениях, ни в error-текстах — никаких имён чужих облаков. Узнаваемость — знакомой ФОРМОЙ (NetworkLoadBalancer/Listener/TargetGroup/HealthCheck, 5-tuple hash, connection-drain, slow-start, admin-disable, anycast-VIP, weighted targets, L4 TCP/UDP), не брендом. TLS-termination вне scope nlb (L4-only) — намеренное out-of-scope решение.
