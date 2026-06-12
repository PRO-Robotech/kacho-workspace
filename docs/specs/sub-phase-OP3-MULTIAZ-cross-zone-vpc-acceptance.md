# Sub-phase OP3-MULTIAZ — cross-zone pod L3 within a VPC across 2 zonal kind clusters, isolation across VPCs — Acceptance

> Статус: DRAFT
> Дата: 2026-06-12
> Ревьюер: acceptance-reviewer (gate перед кодом, ban #1)
> Скилы: `k8s-operator-workflow` (dev-loop / RBAC / kind-only safety), `k8s-quality-checklist` (controller / RBAC / safety / idempotency), `evgeniy` (Go-стиль для operator-кода)

### Привязка к тикету (ban #1 + git-youtrack — обязательна ДО APPROVED-for-code)

> [!important] Pre-APPROVAL gate
> Этот acceptance-док НЕ может быть APPROVED-for-code, пока поля ниже не заполнены
> **реальным** KAC-номером (не плейсхолдером). Номер присваивает orchestrator (он
> владеет YouTrack-доступом) до старта кодинга; заведение тикета + KAC-trail — последний
> шаг перед снятием gate, не часть acceptance-текста. Это кросс-репо эпик (≥3 репо) →
> `[EPIC]` + Subtask-иерархия по стадиям.

| Поле | Значение |
|---|---|
| Эпик | `KAC-<EPIC>` `[EPIC] OP3-MULTIAZ — cross-zone pod L3 within a VPC, isolation across VPCs` (Subtask-иерархия по стадиям P-DERISK-EXT/P1/P2/P3) |
| Subtask P-DERISK-EXT | `KAC-<N>` `доказать external-LRP underlay-attach + host→LR ingress injection на ОДНОМ кластере (HARD GATE)` |
| Subtask P1 | `KAC-<N>` `operator zone-awareness + direct-OVN durable route writer + SSA-рефактор CR-записей (single-cluster, envtest TDD)` |
| Subtask P2 | `KAC-<N>` `2 zonal kind (zoneA/zoneB) — cross-zone pod↔pod within VPC + cross-VPC isolation (real PoC)` |
| Subtask P3 | `KAC-<N>` `hardening: zone-sharding replica-isolation, route re-assert, degraded conditions, per-zone client-cert` |
| Ветка `kacho-vpc-operator` | `KAC-<N>` (zone-awareness, direct-OVN route writer, SSA-рефактор, от `main`) |
| Ветка `kacho-deploy` | `KAC-<N>` (2 zonal kind на общем `kind`-бридже, deconflicted CIDR, NodePort, per-zone kube-ovn values, от `main`) |
| Ветка `kacho-compute` | `KAC-<N>` (seed Geography Region + Zone(zoneA/zoneB) — только если seed требует кода; иначе deploy-seed в `kacho-deploy`) |
| Правка vault `kacho-workspace` | `obsidian/kacho/edges/vpc-operator-to-kubeovn.md` + новая `obsidian/kacho/edges/vpc-operator-to-ovn-nb.md` (direct OVN-NB import-route ребро) + `obsidian/kacho/resources/kacho-vpc-operator-KachoSubnet.md` (zone-label) + `obsidian/kacho/KAC/KAC-<N>.md` (KAC-trail) |
| YouTrack | `https://prorobotech.youtrack.cloud/issue/KAC-<N>` |
| Роль исполнителя | `acceptance-author` (этот док) → реализация: domain-агенты `kacho-vpc-operator` + `kacho-deploy` (+ `kacho-compute` seed) |

> Затронутые репо: `kacho-vpc-operator` (data-plane sibling, **вне build-графа** control-plane) + `kacho-deploy` (2 kind + kube-ovn values + NodePort + Geography seed) + `kacho-compute` (Geography Zone — если кодовый seed) + правка `obsidian/kacho/...` (`kacho-workspace`).
> **Control-plane / proto НЕ меняются** — `Subnet.zone_id` + per-`network_id` EXCLUDE-gist non-overlap уже существуют (design-doc §3.4). Kachō по-прежнему без Watch (poll). Cross-zone L3 — целиком data-plane (kube-ovn LR + underlay + direct OVN-NB маршруты), невидимо на публичной поверхности Kachō-ресурсов.
> Зависит от: **OP1** (KachoSubnet machinery — egress `applySubnet` field-scoped apply, shared `internal/kubeovn` naming/labels), **OP2-P-BGP** (BGP export = advertise-half, prod-тир) — **не должно регрессировать**. Issue: `kacho-vpc-operator#2` (Vpc.staticRoutes strip).
> Источники истины ground-truth: design-doc `docs/specs/2026-06-12-vpc-operator-coverage-and-multi-az-design.md` **§3 + §6 (P-DERISK)**; vault `edges/vpc-operator-to-kubeovn.md`, `edges/kube-ovn-to-bgp-fabric.md`.

---

## Обзор

`kacho-vpc-operator` материализует **Network → kube-ovn custom-VPC** (LR, имя = `network_id`) и **Subnet → N×(kube-ovn Subnet + Multus NAD)** (OP1). Цель OP3-MULTIAZ — **routed L3** между подами разных зон в пределах **одной Kachō Network (= один логический VPC)**, при **жёсткой изоляции между разными Network (разными VPC)**.

Топология (целевая):

- Кластер `kacho` (существующий) — **CONTROL-PLANE**: kacho-vpc / iam / compute / api-gateway + БД.
- ДВА НОВЫХ kind-кластера — **DATA-PLANE**, по одному на зону: `kind-zoneA`, `kind-zoneB`. В каждом — kube-ovn + vpc-operator + project-operator + workloads.
- Требование: pod в zoneA и pod в zoneB **достижимы друг для друга в пределах одной Network**; и **НЕТ достижимости между разными Network** (изоляция вне VPC — твёрдая).

> [!danger] Honesty-gate: datapath_feasible = FALSE (pending P-DERISK-EXT)
> Adversarial review установил: на v1.16.1 механизм cross-zone no-NAT within-VPC L3
> через custom-VPC **НЕ доказан end-to-end**. Доказана durable-запись маршрута прямо в
> OVN-NB (§6.2) и структурная изоляция (§6.5), но **НЕ доказан** ни external-LRP attach
> custom-VPC LR к underlay, ни — самое главное — **host→LR ingress injection** (пакет
> из bridge доставлен ВНУТРЬ custom-VPC LR к локальному поду). Этот док объявляет дизайн
> датапас-feasible **только после прохождения P-DERISK-EXT** (HARD GATE ниже). До этого —
> design is conditional. Быть честным об этом обязательно (design-doc §6.3, §6.6).

---

## Ground-truth (P-DERISK live findings, единый 'kacho'-кластер, kube-ovn v1.16.1, верифицировано 2026-06-12)

Из design-doc §6 + vault-рёбер. **Нормативно для механизма этой фазы.**

1. **#2 strip ROOT-CAUSED (§6.1):** `Vpc.spec.staticRoutes{policyDst}` на custom-VPC устанавливается, через ~4с удаляется — kube-ovn/OVN тегает spec-driven dst-routes `ecmp_symmetric_reply`, `--enable-ecmp=false` их прунит (+ затирает spec). Auto `src-ip` subnet-routes не трогаются. ⇒ **`Vpc.spec.staticRoutes` МЁРТВ** для custom-VPC dst-routes.
2. **Durable import lever PROVEN (§6.2):** маршрут, записанный **прямо в OVN-NB** (`ovn-nbctl lr-route-add`, vendor-untagged) → plain `dst-ip` → **ПЕРСИСТИТ** через Vpc-reconcile, spec-change И полный restart/resync kube-ovn-controller (kube-ovn диффит только свои routes из `vpc.spec`, чужие NB-routes не трогает). Прямой `lr-policy` reroute **прунится на полном resync (ОТВЕРГНУТ)**. ⇒ import = **direct OVN-NB (libovsdb)**, НЕ `Vpc.spec`.
3. **THE GATE (§6.3):** custom-VPC LR имеет ТОЛЬКО subnet-порты — **нет external/gateway LRP** (у `ovn-cluster` есть `-join`). Нет provider-network / vlan / external-subnet; `ENABLE_NAT_GW=false`. ⇒ next-hop dst-route'а (node-IP) недостижим из LR, и **нет host→LR ingress-пути**. Cross-zone L3 ТРЕБУЕТ подключить каждый custom-VPC LR к **underlay** (общий kind docker-бридж `kind`, `172.19.0.0/16`) через external-LRP (`Vpc.enableExternal` + provider/underlay-subnet, либо transit-underlay subnet к VPC).
4. **VpcEgressGateway RULED OUT как import (§6.4):** VEG — `ip4.src`-reroute + SNAT (egress-to-external), НЕ `ip4.dst==remote/18` import; EVPN-on-VEG учит в FRR gw-пода + SNAT, не в OVN LR. Wrong shape для no-NAT within-VPC L3. ⇒ VEG = только external/internet-egress (future).
5. **Isolation STRUCTURAL (§6.5):** разные Network → разные custom-VPC LR → нет общих routes; оператор пишет cross-zone route в LR ТОЛЬКО для remote /18 **ТОЙ ЖЕ Network**. **Shared BGP-RR как import-путь = LEAK** (speaker анонсит все CIDR в один RIB → any-VPC утечка) → RR НЕ import-путь; prod-BGP изоляция требует per-VPC EVPN route-target (out-of-scope здесь).
6. **OP2-P-BGP (merged):** kube-ovn-speaker BGP EXPORT (advertise local /18) ПРОВЕН, но это только advertise-half — оставить для prod, **НЕ** import-путь.

Трассировка к требованиям — тег **[req: …]** у каждого сценария.

---

## Решения (нормативные для реализации)

**(A) Import-механизм = direct OVN-NB, не `Vpc.spec`.** Оператор пишет cross-zone dst-route (`remote /18 → peer-zone underlay/node-IP`) **прямо в OVN-NB через libovsdb** (vendor-untagged, plain `dst-ip` — обход ecmp-prune #2, §6.2), идемпотентно **re-assert**'ит. `Vpc.spec.staticRoutes` (OP2-P2) и `lr-policy` reroute — **отвергнуты** для этой цели (стрипаются / прунятся на resync).

**(B) Underlay-transit attach.** Каждый custom-VPC LR подключается к **общему kind docker-бриджу** `kind` (`172.19.0.0/16`) через **external-LRP** (`Vpc.enableExternal` + provider/underlay-subnet, либо transit-underlay subnet, привязанный к VPC). Это закрывает §6.3-gate: даёт LR egress-к-bridge И host→LR ingress-путь. **Точный способ attach + доказательство ingress — P-DERISK-EXT (HARD GATE).**

**(C) Isolation — структурная (§6.5).** Маршрут пишется в LR Network-X ТОЛЬКО на remote /18 ТОЙ ЖЕ Network-X. Разные Network → разные LR → нет общих routes. Shared-RR / любой «общий RIB» как import — **запрещён** (leak). Изоляция между VPC — **твёрдое требование**, проверяется явным negative-сценарием.

**(D) Zone-awareness — read-all, materialize-filtered, prune-scoped.** `KACHO_VPCOPERATOR_ZONE_ID` гейтит **МАТЕРИАЛИЗАЦИЮ** (subnet материализуется только если `subnet.zone_id == ZONE_ID`), но **НЕ ЧТЕНИЕ** (оператор читает ВСЕ subnets Network, чтобы выучить remote /18 соседних зон для import-route). Children метятся `kacho.io/zone=<zone-id>`; prune/GC **zone-scoped** (оператор НИКОГДА не трогает чужую зону).

**(E) SSA / managedFields для contended k8s-CR-записей.** Все спорные записи в общие k8s-объекты (Vpc / Subnet / KachoSubnet / KachoRouteTable CR), куда пишут несколько per-zone операторов + kube-ovn-controller, ведутся **Server-Side Apply со стабильным per-operator fieldManager** (например `kacho-vpc-operator-<zone>`) + `list-type=map`-keyed списки — **НЕ** client-side `Get→merge→Update+retry` (racy, был корнем OCC hot-loop). **OVN-NB-записи (import-routes) — НЕ k8s-объекты → SSA к ним неприменим**; для них — собственная дисциплина: идемпотентный re-assert + **ownership-by-externalID** (vendor-untagged маркер владельца на NB-route).

**(F) Cross-cluster transport.** Зональные операторы → control-plane через **NodePort** на node-IP control-plane-кластера (общий `kind`-бридж делает control-plane-ноду достижимой из зональных) поверх **SEC-G mTLS** (`server_name` пиннится на DNS SAN). NodePort экспонирует **ТОЛЬКО публичный gRPC :9090, НИКОГДА Internal :9091** (security.md ban #6). Geography Region + Zone(zoneA/zoneB) сидятся **ПЕРВЫМИ** (до Subnet.Create с `zone_id`).

**(G) CIDR-деконфликтинг (обязателен).** kindnet pod/svc CIDR + kube-ovn `ovn-default 172.30/16` + `JOIN 100.64/16` по умолчанию **идентичны во всех kind** → должны **различаться per-cluster** (иначе pod→remote/18 blackhole даже при пингуемых нодах). Kachō supernet `10.80.0.0/16` → **disjoint /18 на зону** (zoneA `10.80.0.0/18`, zoneB `10.80.64.0/18`); IPAM authority = kacho-vpc (EXCLUDE-gist per `network_id`).

**(H) P-DERISK-EXT — HARD GATE, до любого 2-cluster билда.** Дизайн НЕ объявляется датапас-feasible, пока на ОДНОМ кластере не доказан external-LRP attach + egress-к-bridge + **host→LR ingress injection**. Провал → STOP + down-scope (документированное ограничение / пивот на underlay-vlan-per-VPC). 2 кластера НЕ строятся до прохождения.

---

## Стадии

OP3-MULTIAZ — multi-stage эпик; каждая стадия — самостоятельный end-to-end deliverable со своим DoD. Порядок строго gated.

- **P-DERISK-EXT (HARD GATE, единый 'kacho'-кластер):** доказать датапас. external-LRP attach custom-VPC LR к kind-bridge underlay; durable direct-OVN dst-route заставляет пакет тест-пода **egress на bridge**; пакет с bridge **доставлен ВНУТРЬ** custom-VPC LR к локальному поду (host→LR ingress injection — реально недоказанная половина). **Провал → STOP, down-scope.** 2 кластера НЕ строить до прохождения. DoD: live-доказательство на `kind-kacho` (tcpdump/ping/ovn-trace), записано как verified-или-limitation в trail.
- **P1 (single-cluster, acceptance+TDD):** operator zone-awareness (`ZONE_ID` env → materialize-filter → zone-label → scoped prune) + **direct-OVN durable route writer** (libovsdb, идемпотентный re-assert, ownership-by-externalID) + **SSA-рефактор** спорных CR-записей. envtest RED→GREEN для operator-логики. DoD: envtest зелёные; `go test ./... -race` + `golangci-lint run` зелёные.
- **P2 (2 кластера, реальный PoC):** поднять `kind-zoneA` + `kind-zoneB` на общем `kind`-бридже (deconflicted CIDR); seed Geography zones; экспонировать control-plane :9090 через NodePort; зональные операторы читают control-plane. **ДОКАЗАТЬ: cross-zone pod↔pod в пределах одной Network работает И НЕТ достижимости между двумя разными Network.** mTLS `enable=false` сначала (развязать routing-proof), затем `on`. DoD: live cross-zone reachability + cross-VPC isolation подтверждены на стенде.
- **P3 (hardening):** zone-sharding replica-isolation; route re-assert на наблюдаемое удаление NB-route; degraded-conditions; per-zone operator client-cert. DoD: устойчивость к рестартам/удалениям + per-zone least-priv cert.

DoD каждой стадии: P-DERISK-EXT/P2-сценарии verifiable на живом стенде (ovn-nbctl / ovn-trace / tcpdump / ping / kubectl exec); P1-operator-логика — envtest-testable; разрыв «envtest vs live» декларируется (как OP1/OP2-P-BGP).

---

## P-DERISK-EXT — датапас-доказательство на ОДНОМ кластере (HARD GATE)

**Контекст (ground-truth §6.3):** custom-VPC LR имеет только subnet-порты, нет external-LRP; нет provider-network/vlan/external-subnet; `ENABLE_NAT_GW=false`. Без underlay-attach маршрут некуда направить и нет host→LR ingress. Это — последний make-or-break (design-doc §6.6).

> [!danger] Это HARD GATE. Ни одна последующая стадия (P1/P2/P3) не кодится, пока
> P-DERISK-EXT не пройден ИЛИ scope не пересмотрен (DERISK-04 ИСХОД B).

### Сценарий DERISK-01: custom-VPC LR подключается к kind-bridge underlay через external-LRP (happy, ГЕЙТ часть 1) [req: external-lrp][req: underlay-attach]

**ID:** OP3-MAZ-DERISK-01

**Given** на `kind-kacho` существует custom-VPC LR `kacho-<net-id>` с только subnet-портами (§6.3, verified — нет external/gateway LRP)
**And** общий kind docker-бридж `kind` (`172.19.0.0/16`) достижим с нод (ноды в этой подсети)

**When** custom-VPC LR подключается к underlay через external-LRP (механизм: `Vpc.enableExternal` + provider/underlay-subnet, ЛИБО transit-underlay subnet, привязанный к VPC — выбор фиксируется по результату)

**Then** на LR появляется external/gateway LRP с адресом в underlay-диапазоне (verify: `ovn-nbctl lr-route-list <lr>` / `ovn-nbctl show` показывает external LRP; раньше его НЕ было)
**And** next-hop из underlay (node-IP / peer underlay-IP) становится **достижим из LR** (был недостижим — §6.3)
**And** assert: attach НЕ ломает существующие subnet-порты LR и intra-VPC datapath (под по-прежнему получает secondary NIC, OP1 цел)
**And** какой именно механизм сработал (`enableExternal+provider-subnet` vs `transit-underlay-subnet`) — **зафиксирован как verified-решение** в trail (нормативно для P2)

### Сценарий DERISK-02: durable direct-OVN dst-route заставляет пакет egress на bridge (happy, ГЕЙТ часть 2) [req: direct-ovn-route][req: durable]

**ID:** OP3-MAZ-DERISK-02

**Given** custom-VPC LR подключён к underlay (DERISK-01); тест-под в локальной подсети custom-VPC
**And** записан **прямо в OVN-NB** (`ovn-nbctl lr-route-add`, vendor-untagged) маршрут `<remote-test-/18> → <peer/bridge-IP>` (plain `dst-ip`, §6.2)

**When** тест-под шлёт пакет на адрес в `<remote-test-/18>`

**Then** пакет **выходит из LR на underlay (kind-bridge)** через external-LRP (verify: `tcpdump` на bridge-интерфейсе / `ovn-trace` показывает egress через external LRP с правильным next-hop)
**And** маршрут **plain `dst-ip` (НЕ `ecmp_symmetric_reply`)** — `ovn-nbctl lr-route-list <lr>` показывает route без ecmp-тега (контраст с #2)
**And** **маршрут ПЕРСИСТИТ** через Vpc-reconcile, spec-change И **полный restart kube-ovn-controller** на **kube-ovn v1.16.1** (verify: после `kubectl rollout restart` controller'а маршрут всё ещё в NB — §6.2). **Durability pinned на v1.16.1**: persistence-finding §6.2 + in-use guards version-specific (kube-ovn диффит только свои `vpc.spec`-routes на этой версии) → **любой будущий bump версии kube-ovn ОБЯЗАН пере-доказать durability** (re-run DERISK-02), это не back-compat-инвариант
**And** assert (контраст): тот же маршрут, добавленный через `Vpc.spec.staticRoutes`, стрипается ~4с (#2, kube-ovn v1.16.1) — демонстрирует, ЗАЧЕМ direct-OVN

### Сценарий DERISK-03: host→LR ingress injection — пакет с bridge доставлен ВНУТРЬ custom-VPC LR к локальному поду (happy, ГЕЙТ — реально недоказанная половина) [req: host-lr-ingress]

**ID:** OP3-MAZ-DERISK-03

**Given** custom-VPC LR подключён к underlay (DERISK-01); локальный тест-под `P-local` в подсети custom-VPC с известным fixed-IP `<local-pod-IP>`
**And** **host→LR ingress-маршрут установлен явным механизмом, не предполагается** — пробуется ОДИН из конкретных кандидатов (выбор фиксируется по результату):
  - **(a) static route на kind-ноде** к локальной подсети custom-VPC через external-LRP-адрес LR (`ip route add <vpc-subnet> via <LR-external-LRP-IP>` на ноде), затем инъекция с самой ноды;
  - **(b) `ovn-nbctl` LRP + packet-injection из bridge-netns** — `ovn-trace`/`ovs-appctl ofproto/trace` от bridge-порта на `<local-pod-IP>`, либо crafted-пакет с bridge-интерфейса в LR через external-LRP
**And** **кто именно ставит host-route и КАК — записано** (мы НЕ маскируем «не смогли даже настроить»: если ни (a), ни (b) не удаётся установить, это фиксируется как **falsified** и направляет ИСХОД B в DERISK-04, а не как «нет маршрута → таймаут, значит изоляция работает»)

**When** пакет инжектится **с kind-bridge** (с ноды / из bridge-netns по выбранному механизму (a)/(b)) на `<local-pod-IP>`

**Then** пакет **доставлен ВНУТРЬ custom-VPC LR и достигает `P-local`** (verify: `tcpdump` внутри пода `P-local` видит входящий пакет; ИЛИ ping `bridge→pod` отвечает; `ovn-trace`/`ofproto/trace` показывает ingress external-LRP → subnet-port → pod)
**And** это **доказывает host→LR ingress** — единственная реально неподтверждённая половина датапаса (§6.3: «нет host→LR ingress-пути» на голом custom-VPC)
**And** **какой механизм сработал** ((a) node-static-route vs (b) ovn-nbctl-LRP+inject) — **зафиксирован как verified-решение в trail** (та же строгость, что DERISK-01 применяет к выбору attach-механизма); если оба falsified → DERISK-04 ИСХОД B
**And** assert: ingress работает **без NAT** (адрес `P-local` виден as-is, не SNAT/DNAT) — иначе помечается как «reachability-by-NAT», см. open-decision #1 и DERISK-04

### Сценарий DERISK-04: датапас провален → STOP + down-scope (negative, ГЕЙТ-исход) [req: hard-gate][req: honesty]

**ID:** OP3-MAZ-DERISK-04

**Given** одна из DERISK-01/02/03 НЕ воспроизводится на живом стенде (external-LRP не attach'ится к custom-VPC; ИЛИ direct-OVN route не egress'ит; ИЛИ host→LR ingress не доставляется)

**When** фиксируется исход P-DERISK-EXT

**Then** **ИСХОД A (всё прошло):** дизайн объявляется датапас-feasible; P1 разблокирован; verified-механизм (DERISK-01) записан в trail как нормативный для P2
**And** **ИСХОД B (провал):** **STOP** — P1/P2/P3 НЕ кодятся; фиксируется **задокументированное ограничение** (design-doc §6 + GitHub Issue `bug`/`tech-debt`, `blocked:kube-ovn`) + апстрим-issue в kube-ovn (custom-VPC external-LRP / static-route strip) + **пивот-опция**: underlay-vlan-per-VPC (каждый VPC на отдельном provider-vlan, L3 через underlay-роутер) ИЛИ reachability-by-NAT (down-scope с no-NAT)
**And** assert: исход — **верифицирован на живом стенде**, НЕ предположение (honesty-gate); 2 кластера НЕ строятся при ИСХОДЕ B без отдельного APPROVED-решения

---

## P1 — operator zone-awareness + direct-OVN route writer + SSA-рефактор (single-cluster, envtest TDD)

**Контекст (recon, vault `edges/vpc-operator-to-kubeovn.md`):** egress-reconciler уже field-scoped управляет kube-ovn Subnet (OP1) и `Vpc.staticRoutes` (OP2-P2, не работает #2); ingress зеркалит Kachō-ресурсы в CR без zone-filter. P1 добавляет zone-awareness + direct-OVN import-writer + переводит спорные CR-записи на SSA.

### Сценарий P1-01: materialize-filter по ZONE_ID — материализуется только своя зона (happy) [req: zone-materialize]

**ID:** OP3-MAZ-P1-01

**Given** оператор запущен с `KACHO_VPCOPERATOR_ZONE_ID=zoneA`
**And** Network `<nid>` с двумя subnets: `S-A` (`zone_id=zoneA`, `10.80.0.0/18`) и `S-B` (`zone_id=zoneB`, `10.80.64.0/18`)

**When** оператор реконсайлит Network `<nid>`

**Then** материализуется **только `S-A`** в kube-ovn Subnet+NAD (zoneA); `S-B` НЕ материализуется (чужая зона)
**And** child'ы `S-A` несут label `kacho.io/zone=zoneA` (решение D)
**And** assert: материализация subnet гейтится `subnet.zone_id == ZONE_ID` (envtest: subnet чужой зоны → нет child kube-ovn Subnet)

### Сценарий P1-02: read-all-for-advertise — оператор учит remote /18 чужой зоны, не материализуя её (happy, ВАЖНО) [req: zone-read-all][req: import-route]

**ID:** OP3-MAZ-P1-02

**Given** оператор `ZONE_ID=zoneA`; Network `<nid>` с `S-A` (zoneA, `10.80.0.0/18`) и `S-B` (zoneB, `10.80.64.0/18`)

**When** оператор реконсайлит Network `<nid>`

**Then** оператор **ЧИТАЕТ ВСЕ subnets** Network `<nid>` (не только свою зону) и **выучивает remote /18** `10.80.64.0/18` (zoneB) для import-route
**And** zone-фильтр гейтит **МАТЕРИАЛИЗАЦИЮ, НЕ ЧТЕНИЕ** (решение D): `S-B` прочитан, но не материализован; его /18 используется как desired import-route в LR Network `<nid>`
**And** desired import-route — `{dst=10.80.64.0/18, nexthop=<zoneB-underlay/node-IP>}` в OVN-NB LR `kacho-<nid>` (next-hop резолвится из zone→endpoint mapping, infra-sensitive — Internal*/config, open-decision #4)

### Сценарий P1-03: direct-OVN durable route writer — идемпотентный re-assert (happy, КЛЮЧЕВОЙ) [req: direct-ovn-route][req: idempotency]

**ID:** OP3-MAZ-P1-03

**Given** оператор `ZONE_ID=zoneA`; выучен remote /18 `10.80.64.0/18` → next-hop `<zoneB-ip>` (P1-02); custom-VPC LR `kacho-<nid>` подключён к underlay (DERISK-01 verified)

**When** оператор реконсайлит и пишет import-route

**Then** маршрут `10.80.64.0/18 → <zoneB-ip>` записан **прямо в OVN-NB через libovsdb** (vendor-untagged, plain `dst-ip` — решение A, §6.2), НЕ в `Vpc.spec`
**And** маршрут несёт **ownership-by-externalID** маркер владельца (например `external_ids:kacho-managed-by=kacho-vpc-operator-zoneA`, решение E) — чтобы re-assert/prune отличал свои NB-routes от чужих/auto
**And** **идемпотентность**: повторный reconcile при уже-присутствующем желаемом маршруте → **no-op** (нет spurious NB-write; envtest/unit на writer-логику с fake/recording NB-client)
**And** assert: оператор НЕ пишет этот маршрут в `Vpc.spec.staticRoutes` (решение A; OP2-P2-механизм не используется для import — он стрипается #2)

### Сценарий P1-04: route re-assert на наблюдаемое удаление NB-route (positive, self-heal) [req: direct-ovn-route][req: durable]

**ID:** OP3-MAZ-P1-04

**Given** import-route `10.80.64.0/18 → <zoneB-ip>` записан оператором в OVN-NB (P1-03)
**And** маршрут исчез из OVN-NB (внешнее удаление / resync — хотя §6.2 показывает персистентность, оператор не полагается на неё слепо)

**When** оператор реконсайлит (periodic resync)

**Then** оператор **повторно записывает** недостающий owned import-route (re-assert по desired-set, идемпотентно) — self-heal
**And** assert: re-assert трогает ТОЛЬКО owned-by-externalID маршруты (foreign / kube-ovn-auto NB-routes НЕ трогаются — §6.2: kube-ovn не трогает чужие, оператор отвечает симметрично)

### Сценарий P1-05: SSA managedFields — два writer'а не клоберят друг друга, kube-ovn-дефолты сохранены (happy, КЛЮЧЕВОЙ) [req: ssa][req: no-clobber]

**ID:** OP3-MAZ-P1-05

**Given** общий k8s-объект (Vpc / Subnet / KachoSubnet / KachoRouteTable CR), куда пишут per-zone оператор + kube-ovn-controller (kube-ovn дефолтит часть spec-полей — vault callout, OCC hot-loop root)
**And** оператор пишет свои поля через **Server-Side Apply** со стабильным `fieldManager=kacho-vpc-operator-<zone>` + `list-type=map`-keyed списки (решение E)

**When** оператор применяет свои поля

**Then** оператор владеет ТОЛЬКО своими полями (managedFields per-fieldManager); **kube-ovn-defaulted поля НЕ затираются** (apply не отправляет чужие ключи → SSA их не клоберит)
**And** второй writer (другой оператор / kube-ovn) НЕ конфликтует и НЕ клоберится (co-ownership через разные fieldManager; конфликт по одному полю → детерминированный force/owner, не silent-clobber)
**And** assert: **НЕТ** client-side `Get→merge→Update+retry` для спорных CR-записей (racy — был корнем OCC hot-loop, vault callout); envtest подтверждает 0 spurious-write при повторном apply без изменений
**And** assert (**LIVE-verified DoD, не envtest-only**): SSA-рефактор **воспроизводит существующее field-scoped no-clobber-поведение OP1 с 0 OCC-conflict против ЖИВОГО kube-ovn-controller** — на single-cluster `kind-kacho` за наблюдаемое окно reconcile-циклов **счётчик OCC-конфликтов (409 Conflict) на спорных CR = 0** и **нет write-write hot-loop** (vault emphatic: hot-loop «видно только на живом кластере» — envtest-only «0 spurious-write» НЕ покрывает реальный failure-mode, т.к. envtest не гоняет настоящий kube-ovn-controller с его defaulting). Это live-гейт DoD P1, отдельный от envtest-assert выше
**And** assert (граница): SSA применяется к **k8s-CR-записям** (Vpc/Subnet/KachoSubnet/KachoRouteTable), а к **OVN-NB-routes — НЕ** (не k8s-объекты) → у них ownership-by-externalID (P1-03), не managedFields (решение E)

### Сценарий P1-06: zone-scoped prune — оператор НИКОГДА не трогает чужую зону (happy, isolation/replica) [req: zone-prune][req: replica-isolation]

**ID:** OP3-MAZ-P1-06

**Given** оператор `ZONE_ID=zoneA`; в кластере есть child'ы с label `kacho.io/zone=zoneA` (свои) и (теоретически) `kacho.io/zone=zoneB` (чужие, не должны существовать в kind-zoneA, но проверяем guard)
**And** Kachō-subnet `S-A` (zoneA) удалена в control-plane

**When** оператор реконсайлит и прунит

**Then** prune/GC **zone-scoped** по label `kacho.io/zone=zoneA` (решение D): удаляются только свои child'ы
**And** assert: оператор `zoneA` **НИКОГДА** не удаляет/не трогает объекты с `kacho.io/zone!=zoneA` (replica-isolation, design-doc §3.5) — даже если они попали в его List
**And** import-routes прунятся zone-scoped аналогично (owned-by-externalID `...-zoneA` — P1-03): оператор zoneA не снимает import-routes другой зоны

### Сценарий P1-07: zone-aware materialize — degraded на отсутствие seed-зоны не падает (negative/edge) [req: zone-materialize][req: graceful]

**ID:** OP3-MAZ-P1-07

**Given** оператор `ZONE_ID=zoneA`; subnet с `zone_id` пустой / неизвестной зоны (рассинхрон seed)

**When** оператор реконсайлит

**Then** оператор НЕ падает; subnet с пустым/неизвестным `zone_id` → **не материализуется** + degraded-condition (`Ready=False` reason `ZoneUnresolved` / Event), requeue
**And** assert: ни materialize, ни import-route не пишутся для subnet с нерезолвимой зоной (fail-safe, partial-progress для остальных subnets)

---

## P2 — 2 zonal kind, cross-zone pod↔pod within VPC + cross-VPC isolation (реальный PoC)

**Контекст:** P-DERISK-EXT ИСХОД A пройден (датапас feasible); P1 operator-логика зелёная. P2 поднимает 2 кластера и доказывает требование заказчика на живом стенде.

> [!note] Stage-gate: P2 gated на P-DERISK-EXT ИСХОД A (DERISK-04) + P1 GREEN.

### Сценарий P2-01: 2 zonal kind на общем bridge, deconflicted CIDR (setup, happy) [req: two-cluster][req: cidr-deconflict]

**ID:** OP3-MAZ-P2-01

**Given** control-plane `kind-kacho` существует; поднимаются `kind-zoneA` + `kind-zoneB` на **общем docker-бридже `kind`** (`172.19.0.0/16` — ноды взаимно достижимы, НЕ изолировать)
**And** per-cluster **deconflicted CIDR** (решение G): kindnet pod/svc + kube-ovn `ovn-default` (≠ `172.30/16` дефолт) + `JOIN` (≠ `100.64/16` дефолт) **различны** в zoneA и zoneB; Kachō supernet `10.80.0.0/16` → zoneA `10.80.0.0/18`, zoneB `10.80.64.0/18`

**When** оба кластера развёрнуты (`kacho-deploy`, per-zone kube-ovn values, kind-dev-safe)

**Then** ноды zoneA и zoneB **взаимно пингуются** по underlay (общий bridge); kube-ovn `ovn-cluster`/`ovn-default`/`JOIN` CIDR **не пересекаются** между кластерами (verify: `kubectl get subnet -A` в обоих)
**And** assert: deploy таргетит ТОЛЬКО `kind-*` контекст (kind-dev-safe, `k8s-operator-workflow` safety)

### Сценарий P2-02: Geography seed ordering — Subnet.Create с zone_id незасиженной зоны → sync INVALID_ARGUMENT (negative, ordering-gate) [req: geography-seed][req: ordering]

**ID:** OP3-MAZ-P2-02

**Given** control-plane без засиженных Geography Zone (`zoneA`/`zoneB` ещё не созданы в kacho-compute)

**When** клиент вызывает `SubnetService.Create` с `zoneId=zoneA` (cross-domain ref vpc→compute `ZoneService.Get`, validation на request-path)

**Then** мутация отвергается **синхронно** на request-path: gRPC-код **`INVALID_ARGUMENT`**, message **verbatim `unknown zone id 'zoneA'`** (ground-truth: `validateZoneID` в `kacho-vpc/internal/apps/kacho/api/subnet/helpers.go:204-205` маппит `ZoneService.Get → repo.ErrNotFound` в `InvalidArgument`, НЕ `NOT_FOUND` — see edge `vpc-to-compute-zone-validate`)
**And** **НИКАКОЙ Operation НЕ создаётся** — `validateZoneID` исполняется синхронно ДО постановки Operation (request-path guard); клиент получает gRPC-ошибку напрямую, не через Operation-result
**And** **порядок (решение F):** seed Geography Region + Zone(zoneA/zoneB) **ПЕРВЫМ** (до Subnet с `zone_id`) → после seed тот же `Create` возвращает **Operation**, который поллится до `done && !error`; затем `SubnetService.Get` отдаёт Subnet с `zoneId=zoneA`
**And** assert: ordering зафиксирован в deploy-runbook (`kacho-deploy`); zoneA-undefined → sync fail-closed на мутации (не silent, не async-через-Operation)

### Сценарий P2-03: cross-cluster operator→control-plane через NodePort :9090 — Internal :9091 НИКОГДА не экспонирован (happy/security, КЛЮЧЕВОЙ) [req: cross-cluster-transport][req: internal-not-exposed]

**ID:** OP3-MAZ-P2-03

**Given** control-plane gRPC :9090 (публичный) экспонирован через **NodePort** на node-IP `kind-kacho` (достижим из zonal-кластеров по общему bridge, решение F); Internal :9091 — **НЕ** через NodePort
**And** оператор zoneA/zoneB дозванивается до control-plane по NodePort poverх SEC-G mTLS (`server_name` пиннится на DNS SAN control-plane-сервера)

**When** оператор zoneA читает control-plane (`NetworkService.Get` / `SubnetService.List`)

**Then** чтение успешно через NodePort :9090 (mTLS handshake, `server_name` совпал с DNS SAN — иначе fail-closed)
**And** assert: **NodePort экспонирует ТОЛЬКО :9090 (public gRPC), НИКОГДА :9091 (Internal)** — `Internal.*` методы не маршрутизируются на cross-cluster-доступную поверхность (security.md ban #6); попытка достучаться до Internal-метода через NodePort → недоступно
**And** assert: `server_name`-пиннинг на DNS SAN (не IP) — иначе mTLS отвергает (SEC-G `enable=true`)

### Сценарий P2-04: mTLS enable=false → routing-proof развязан → enable=true (staged, edge) [req: cross-cluster-transport][req: mtls-perimeter]

**ID:** OP3-MAZ-P2-04

**Given** P2 проверяет сначала **routing/datapath** (cross-zone L3), затем безопасность транспорта

**When** PoC прогоняется поэтапно

**Then** **этап 1**: mTLS `enable=false` (insecure back-compat, SEC-G per-edge enable) — чтобы доказать cross-zone routing БЕЗ примеси mTLS-проблем (routing-proof развязан)
**And** **этап 2**: mTLS `enable=true` — тот же datapath работает через mTLS (transport-security не ломает routing)
**And** assert: оба этапа зафиксированы в runbook; финальное состояние — `enable=true` (mTLS on)

### Сценарий P2-05: cross-zone pod↔pod В ПРЕДЕЛАХ одной Network — достижимы, no-NAT (happy, ГЛАВНЫЙ РЕЗУЛЬТАТ) [req: cross-zone-reachable][req: within-vpc]

**ID:** OP3-MAZ-P2-05

**Given** одна Kachō Network `<nid>` (= один логический VPC) с subnets `S-A` (zoneA, `10.80.0.0/18`) и `S-B` (zoneB, `10.80.64.0/18`)
**And** оператор zoneA материализовал `S-A` + import-route `10.80.64.0/18 → <zoneB-ip>` (direct-OVN); оператор zoneB материализовал `S-B` + import-route `10.80.0.0/18 → <zoneA-ip>` (симметрично)
**And** под `P-A` в `S-A` (zoneA, IP `10.80.0.X`) и под `P-B` в `S-B` (zoneB, IP `10.80.64.Y`), оба с secondary NIC из своей Kachō-подсети
**And** **NAT-исход НЕ пере-решается здесь** — P2-05 **наследует** no-NAT-vs-NAT-результат, уже зафиксированный DERISK-03 в trail (открытое решение #1 закрыто на гейте, до старта P2): pass-критерий P2-05 **условен по записанному gate-исходу** — к моменту прогона P2-05 ожидаемый результат **однозначен**, не «или-или»

**When** `P-A` шлёт пакет на `P-B` (`10.80.64.Y`) по secondary (kube-ovn) NIC

**Then** пакет: `P-A → custom-VPC LR(zoneA) → direct-OVN route 10.80.64.0/18 → underlay(kind bridge) → zoneB node → custom-VPC LR(zoneB) → P-B` — **routed L3, БЕЗ L2-растяжения** (design-doc §3.3)
**And** `P-B` отвечает симметрично (обратный import-route в LR zoneB); ping/TCP `P-A↔P-B` **успешен** (verify: `kubectl exec P-A -- ping 10.80.64.Y` отвечает; tcpdump на `P-B` видит src `10.80.0.X`)
**And** **NAT-проекция по gate-исходу (trail, не повторное решение):**
  - **если DERISK-03 записал no-NAT-verified** → обязательный assert: `P-B` видит реальный `P-A`-IP `10.80.0.X` (не SNAT), тот же IP-space (within-VPC L3, open-decision #1 default); SNAT-наблюдение здесь = **FAIL** P2-05;
  - **если DERISK-03 записал только reachability-by-NAT** (down-scope) → ожидаемый результат P2-05 — reachability достигнута, src может быть SNAT'нут; это **PASS как задокументированное ограничение** (не no-NAT-same-IP), уже отражённое в trail на гейте
**And** assert: достижимость — именно по **secondary kube-ovn NIC** (Kachō VPC datapath), не по primary kindnet (open-decision #5)

### Сценарий P2-06: cross-VPC НЕТ достижимости — изоляция (negative, ТВЁРДОЕ ТРЕБОВАНИЕ) [req: cross-vpc-isolation]

**ID:** OP3-MAZ-P2-06

**Given** ДВЕ разные Kachō Network: `Net-1` (subnets в zoneA+zoneB, supernet-A) и `Net-2` (subnets в zoneA+zoneB, **disjoint** supernet-B)
**And** под `P-1A` в `Net-1`/zoneA и под `P-2B` в `Net-2`/zoneB
**And** оператор каждой зоны пишет cross-zone import-route в LR ТОЛЬКО на remote /18 **ТОЙ ЖЕ Network** (решение C, §6.5): LR(`Net-1`) имеет route только на remote /18 `Net-1`; LR(`Net-2`) — только на `Net-2`

**When** `P-1A` (`Net-1`) пытается достучаться до `P-2B` (`Net-2`)

**Then** **НЕТ достижимости** (`kubectl exec P-1A -- ping <P-2B-IP>` — таймаут / no route): разные Network → разные custom-VPC LR → нет общих routes; LR(`Net-1`) не имеет маршрута в адресное пространство `Net-2`
**And** **структурная изоляция (§6.5)**: оператор НИКОГДА не пишет cross-Network route (route только same-Network remote /18); даже если CIDR оказались бы смежны, LR изолированы
**And** assert: **shared-RR / любой общий RIB как import — НЕ используется** (был бы leak: speaker анонсит все CIDR в один RIB → any-VPC утечка, §6.5) — изоляция держится **структурно**, не настройкой фильтров
**And** это — **твёрдое требование заказчика** (изоляция вне VPC firm); negative обязателен в e2e

### Сценарий P2-07: CIDR-неконфликтинг — pod→remote/18 blackhole, если CIDR пересекаются, даже при пингуемых нодах (negative, edge) [req: cidr-deconflict]

**ID:** OP3-MAZ-P2-07

**Given** zoneA и zoneB подняты, ноды взаимно пингуются (underlay OK)
**And** **НО** kube-ovn `ovn-default`/`JOIN` ИЛИ kindnet CIDR **совпадают** между кластерами (дефолт `172.30/16` / `100.64/16` не переопределён — решение G нарушено)

**When** `P-A` (zoneA) шлёт пакет на `P-B` (zoneB remote /18)

**Then** пакет **blackhole'ится** (не доставляется), **несмотря на то что ноды пингуются** — overlap внутренних kube-ovn CIDR ломает маршрутизацию (verify: node-ping OK, но pod→remote-pod fail)
**And** **фикс**: deconflict CIDR per-cluster (решение G) → P2-05 проходит
**And** assert: deconflict — **обязательная предпосылка** (не опциональная оптимизация); зафиксирован в deploy-runbook + проверяется явным negative

### Сценарий P2-08: shared-RR-as-import ОТВЕРГНУТ — почему (negative, design-rationale) [req: cross-vpc-isolation][req: non-goal]

**ID:** OP3-MAZ-P2-08

**Given** соблазн использовать общий BGP route-reflector (OP2-P-BGP) как import-путь для cross-zone routes

**When** оценивается этот вариант

**Then** **ОТВЕРГНУТ** (§6.5): shared-RR — общий RIB; speaker анонсит **все** CIDR в один RIB без per-VPC-фильтра → любой VPC выучил бы CIDR любого другого → **leak** (нарушение твёрдой cross-VPC изоляции)
**And** OP2-P-BGP остаётся только как **advertise-half / export** (prod, design-doc §3.2) — НЕ import-путь (решение, ground-truth #6)
**And** prod-BGP изоляция требовала бы **per-VPC EVPN route-target** — **out-of-scope** этой фазы (зафиксировано в «Не-цели»)
**And** assert: import = direct-OVN per-VPC LR (решение A), изоляция структурная (решение C) — НЕ shared-RR

### Сценарий P2-09: VpcEgressGateway-as-import ОТВЕРГНУТ — wrong shape (negative, design-rationale) [req: non-goal]

**ID:** OP3-MAZ-P2-09

**Given** соблазн использовать `VpcEgressGateway` как import-механизм cross-zone

**When** оценивается этот вариант

**Then** **ОТВЕРГНУТ** (§6.4): VEG = `ip4.src`-reroute + SNAT (egress-to-external), НЕ `ip4.dst==remote/18` import; EVPN-on-VEG учит в FRR gw-пода + SNAT, **не в OVN LR** → wrong shape для no-NAT within-VPC L3
**And** VEG = только external/internet-egress (future P3/P4 design-doc §2) — НЕ cross-zone import
**And** assert: import — direct-OVN dst-route в LR (решение A), не VEG

---

## P3 — hardening (после P2 GREEN)

### Сценарий P3-01: zone-sharding replica-isolation под рестартом (positive, resilience) [req: replica-isolation][req: graceful]

**ID:** OP3-MAZ-P3-01

**Given** оператор zoneA рестартует (под перезапущен); оператор zoneB работает непрерывно

**When** zoneA-оператор поднимается заново

**Then** zoneA-оператор реконсайлит свою зону (materialize `S-A`, re-assert import-routes owned-by `...-zoneA`) идемпотентно — без дублей, без spurious-write (P1-03/P1-05)
**And** assert: zoneB-оператор НЕ затронут рестартом zoneA (replica-isolation, разные fieldManager + zone-label); чужие import-routes не тронуты (ownership-by-externalID)

### Сценарий P3-02: degraded conditions на недоступность peer/endpoint (negative, observability) [req: graceful]

**ID:** OP3-MAZ-P3-02

**Given** оператор zoneA не может резолвить next-hop zoneB (endpoint mapping недоступен / control-plane unavailable)

**When** оператор реконсайлит import-route

**Then** оператор НЕ падает; import-route не пишется с невалидным next-hop → degraded-condition (`Ready=False` reason `PeerEndpointUnresolved` / Event), requeue с backoff
**And** assert: control-plane unavailable (NodePort/mTLS) → fail-closed на **мутации** (не пишет мусорный route), но existing owned-routes/materialization **переживают** (graceful dangling, data-integrity §4); intra-zone datapath цел

### Сценарий P3-03: per-zone operator client-cert — least-priv (security) [req: security][req: mtls-perimeter]

**ID:** OP3-MAZ-P3-03

**Given** каждая зона имеет персональный operator client-cert (SEC-G; SAN per-zone, например `spiffe://kacho.cloud/ns/kacho-vpc-operator-zoneA/sa/...`)

**When** оператор zoneA дозванивается до control-plane

**Then** mTLS с **per-zone** client-cert; least-priv read-only ReBAC viewer (SEC-G; без мутаций к control-plane — оператор только читает VPC-ресурсы)
**And** assert: cert zoneA не используется zoneB (per-zone изоляция identity); `server_name`-пиннинг на DNS SAN (P2-03)
**And** infra-sensitive (cert/SAN/ASN/next-hop/VNI/RT/underlay) — config/secret, не публичная поверхность (security.md, P3-04)

### Сценарий P3-04: infra-sensitive данные — ТОЛЬКО Internal*/config, не публичный API (security, КЛЮЧЕВОЙ) [req: security][req: infra-sensitive]

**ID:** OP3-MAZ-P3-04

**Given** cross-zone L3 требует: zone→underlay/node-IP next-hop mapping, ASN (если prod-BGP), VNI/RT (если EVPN), underlay-CIDR, external-LRP-адреса, supernet→/18 нарезку

**When** конфигурируется multi-AZ

**Then** все эти данные классифицируются **infra-sensitive** (placement / underlay / transport — security.md): живут в **config/secret / Internal*-API (:9091)**, **НЕ** на публичной gRPC/REST-поверхности Kachō-ресурсов
**And** публичная поверхность Subnet/Network показывает только tenant-intent: `id`/`name`/`labels`/`zoneId`/`createdAt`/`status` — **НЕ** next-hop/ASN/underlay/external-LRP/VNI/RT
**And** assert: `grep` по публичным proto/JSON-ответам не выявляет next-hop/ASN/VNI/RT/underlay-полей; supernet→/18 + cross-zone next-hops/ASN аллоцирует **Internal*-only** allocator (open-decision #4, security.md)
**And** assert: BGP-ребро (если prod) — вне gRPC mTLS-mesh (TCP-MD5, OP2-P-BGP `edges/kube-ovn-to-bgp-fabric.md`); cross-zone routing-конфиг не утекает tenant'у

### Сценарий P3-05: trail + регресс OP1/OP2-P-BGP/mTLS (regression/trail) [req: non-goal][req: vault]

**ID:** OP3-MAZ-P3-05

**Given** OP1 (Subnet→child+NAD, field-scoped apply, in-use guard, finalizer), OP2-P-BGP (BGP advertise-аннотация), SEC-G mTLS dial, ns/project-operator

**When** OP3-MULTIAZ реализован

**Then** OP1-материализация, OP2-P-BGP advertise, mTLS dial, ns/project-operator — **без регресса** (zone-awareness + direct-OVN import + SSA — аддитивны; SSA-рефактор не меняет наблюдаемое поведение OP1-материализации)
**And** shared `internal/kubeovn` переиспользуется (zone-label, naming) без drift (корень #1)
**And** vault обновлён: `edges/vpc-operator-to-kubeovn.md` (zone-awareness + materialize-filter) + новая `edges/vpc-operator-to-ovn-nb.md` (direct OVN-NB import-route ребро, libovsdb, ownership-by-externalID) + `resources/kacho-vpc-operator-KachoSubnet.md` (zone-label) + «История» с KAC-номером + KAC-trail `KAC/KAC-<N>.md`
**And** apстрим kube-ovn issue зафиксирован (custom-VPC static-route strip / external-LRP) — open-decision #7

---

## Открытые решения (recommend default per item)

| # | Вопрос | Рекомендуемый default |
|---|---|---|
| 1 | **no-NAT-same-IP vs reachability-by-any-path** | **Attempt no-NAT** (same IP-space, без SNAT) — это цель within-VPC L3 (P2-05). **Down-scope на reachability-by-NAT ТОЛЬКО если P-DERISK-EXT host→LR ingress (DERISK-03) докажет недостижимость без NAT** — тогда явно флагнуть в trail как ограничение. **Решается на гейте (DERISK-03), фиксируется в trail; P2-05 НЕ пере-решает — наследует записанный исход** (его pass-критерий условен по gate-результату). |
| 2 | **2 зоны сначала или сразу 3** | **2 (zoneA/zoneB)** — минимальный blast-radius для доказательства cross-zone + isolation; на 3 не прыгать (design-doc §3.7 «на 3 не прыгать»). |
| 3 | **`zone_id` required+immutable на multi-AZ Subnet?** | **Рекомендую required+immutable** для multi-AZ Network (зона определяет материализацию; смена зоны = пересоздание подсети) — **но это control-plane proto-change → отдельная под-фаза**, НЕ в OP3 (OP3 control-plane не меняет). В OP3 — используем существующий optional `zone_id` as-is. |
| 4 | **Кто аллоцирует supernet→/18 + cross-zone next-hops/ASN** | **Internal*-only** (security.md): supernet→/18 — внутренний allocator / конвенция оператора (не публичный API); next-hop/ASN — config/secret/Internal*. В OP3-PoC — **статическая конвенция** (zoneA `.0/18`, zoneB `.64/18`, next-hop = peer node-IP из config); полноценный allocator — future. |
| 5 | **Scope связности: secondary kube-ovn NIC vs достижимость любого Kachō-IP** | **Именно по secondary (kube-ovn) NIC** — это Kachō VPC datapath (P2-05 assert); primary kindnet вне scope (design-doc §4 п.5). |
| 6 | **Cross-cluster transport: NodePort vs MetalLB** | **NodePort** (kind-dev-safe, минимум зависимостей; решение F). MetalLB — future/prod (LoadBalancer-тип); в kind избыточен. |
| 7 | **Split kacho-iam-operator из kacho-vpc-operator (OP-SPLIT) до zone-awareness** | **Рекомендую да** (design-doc §1a): оба бинаря редеплоятся per-zonal-кластер; чистая граница до добавления zone-awareness. **Но это отдельная фаза OP-SPLIT** — может идти параллельно/до P1; не блокирует datapath-gate. |
| 8 | **Апстрим kube-ovn issue** | **Завести** (custom-VPC static-route strip #2 + отсутствие external-LRP на custom-VPC) — `blocked:kube-ovn`, ссылка в trail (P3-05). |

---

## Тестовая стратегия

### envtest (P1 operator-логика — детерминированно)

- **envtest (egress/route-controller)** — обязателен для P1:
  - materialize-filter: subnet чужой зоны → нет child (P1-01); read-all → remote /18 выучен (P1-02).
  - direct-OVN writer: идемпотентный re-assert с **fake/recording NB-client** (нет реального OVN) → desired-route записан 1×, повторный reconcile → no-op (P1-03); re-assert на удаление owned-route (P1-04).
  - SSA: повторный apply без изменений → 0 spurious-write; kube-ovn-defaulted поля сохранены; co-ownership двух fieldManager (P1-05).
  - zone-scoped prune: чужая зона не тронута (P1-06); zone-unresolved → degraded, не паника (P1-07).
- **unit** — route-writer builder (dst/nexthop/externalID, idempotency-ключ), zone-filter predicate, через fake NB-client.

> [!note] Граница envtest (явно зафиксировать)
> envtest НЕ запускает реальный kube-ovn-controller / OVN-NB / cross-cluster datapath →
> проверяет ТОЛЬКО operator-механику (filter / writer-idempotency / SSA / prune-scope) c
> fake NB-client. **Реальный external-LRP attach, host→LR ingress, durable NB-route,
> cross-zone reachability, cross-VPC isolation, CIDR-blackhole, NodePort/mTLS-транспорт**
> — верифицируются **на живом стенде** (P-DERISK-EXT single-cluster + P2 2-cluster).
> Разрыв декларируется в DoD (как OP1 / OP2-P-BGP callouts). Это и есть причина, почему
> P-DERISK-EXT — HARD GATE: envtest НЕ может доказать датапас.

### Live-верификация на стенде (обязательна — verifiable surface)

- **P-DERISK-EXT (single `kind-kacho`):** external-LRP появился (`ovn-nbctl show`), durable direct-OVN route plain `dst-ip` персистит через controller-restart (DERISK-02), пакет egress на bridge (tcpdump/ovn-trace), **host→LR ingress: пакет с bridge достигает локального пода** (tcpdump в поде / ping bridge→pod / ovn-trace) (DERISK-03). ИСХОД A/B зафиксирован (DERISK-04).
- **P2 (2 кластера):** ноды zoneA↔zoneB пингуются, CIDR deconflicted (P2-01); Geography seed-ordering — до seed `Create` отдаёт **sync `INVALID_ARGUMENT` `unknown zone id 'zoneA'`** (без Operation), после seed → Operation `done` (P2-02); NodePort :9090 (не :9091) + mTLS server_name (P2-03/04); **cross-zone pod↔pod within Network — ping/TCP OK, NAT-projection per DERISK-03 trail** (P2-05); **cross-VPC — таймаут / no route (isolation)** (P2-06); CIDR-overlap → blackhole при пингуемых нодах (P2-07).

### TDD

- Для каждого operator-сценария (P1): падающий envtest/unit (RED по правильной причине — фичи нет) ДО кода → GREEN; в отчёте пара RED→GREEN.
- P-DERISK-EXT / P2 (live) — verifiable runbook-шаги на живом стенде (не Go-тест; datapath/deploy-фаза); результат фиксируется в PR/RESULTS как live-verification (ИСХОД A/B для P-DERISK-EXT).
- Кросс-кластерный e2e (cross-zone reachable + cross-VPC isolation) — newman/e2e не покрывает L3-датапас → **scripted live-PoC** (kubectl exec ping/TCP + tcpdump), документирован в `kacho-deploy` runbook; happy (P2-05) + negative (P2-06) обязательны.

### Двусторонняя трассировка ID ↔ тест/runbook-шаг (обязательна — каждый сценарий имеет именованный артефакт)

> Дополняет таблицу «Трассировка требований → сценарии» (ниже): та идёт req→scenario;
> эта — **scenario→named-test/runbook-step** (вторая сторона). P1 → именованная envtest/unit-функция;
> live-сценарии (DERISK-0x / P2-0x / P3-0x) → пронумерованный runbook-step ID в PoC-скрипте `kacho-deploy`.

**P1 (envtest/unit — именованная Go-функция):**

| Сценарий | Named test |
|---|---|
| OP3-MAZ-P1-01 | `TestZoneFilter_MaterializeOnlyOwnZone` (envtest) |
| OP3-MAZ-P1-02 | `TestZoneFilter_ReadAllLearnRemoteCIDR` (envtest) |
| OP3-MAZ-P1-03 | `TestRouteWriter_IdempotentReassert` (envtest + unit `TestRouteBuilder_IdempotencyKey`) |
| OP3-MAZ-P1-04 | `TestRouteWriter_ReassertOnMissingOwnedRoute` (envtest) |
| OP3-MAZ-P1-05 | `TestSSA_NoClobberDefaultedFields` (envtest, 0 spurious-write) + **live** `TestSSA_ZeroOCCConflict_LiveController` (single-cluster gate, 409-count=0) |
| OP3-MAZ-P1-06 | `TestPrune_ZoneScoped_NeverTouchesForeignZone` (envtest) |
| OP3-MAZ-P1-07 | `TestZoneResolve_DegradedNotPanic` (envtest) |

**Live-сценарии (пронумерованный runbook-step в PoC-скрипте `kacho-deploy`):**

| Сценарий | Runbook step |
|---|---|
| OP3-MAZ-DERISK-01 | step **R1** (external-LRP attach + verify `ovn-nbctl show`) |
| OP3-MAZ-DERISK-02 | step **R2** (direct-OVN route → egress on bridge + controller-restart durability) |
| OP3-MAZ-DERISK-03 | step **R3** (host→LR ingress injection: mechanism (a)/(b) → record verified-or-falsified) |
| OP3-MAZ-DERISK-04 | step **R4** (ИСХОД A/B gate decision recorded in trail) |
| OP3-MAZ-P2-01 | step **R5** (2 zonal kind up, deconflicted CIDR verify) |
| OP3-MAZ-P2-02 | step **R6** (Geography seed ordering — pre-seed sync `INVALID_ARGUMENT`, post-seed Operation `done`) |
| OP3-MAZ-P2-03 | step **R7** (NodePort :9090 reachable, :9091 NOT exposed) |
| OP3-MAZ-P2-04 | step **R8** (mTLS enable=false → routing-proof → enable=true) |
| OP3-MAZ-P2-05 | step **R9** (cross-zone pod↔pod within Network, NAT-projection per R3 trail) |
| OP3-MAZ-P2-06 | step **R10** (cross-VPC isolation — ping timeout / no route) |
| OP3-MAZ-P2-07 | step **R11** (CIDR-overlap → blackhole at pingable nodes) |
| OP3-MAZ-P3-01 | step **R12** (zone-sharding replica-isolation under restart) |
| OP3-MAZ-P3-02 | step **R13** (degraded conditions on peer/endpoint unavailable) |
| OP3-MAZ-P3-03 | step **R14** (per-zone operator client-cert least-priv) |
| OP3-MAZ-P3-04 | step **R15** (infra-sensitive grep — no next-hop/ASN/VNI/RT on public surface) |
| OP3-MAZ-P3-05 | step **R16** (regression OP1/OP2-P-BGP/mTLS + vault trail) |

> P2-08 / P2-09 (design-rationale negatives «shared-RR / VEG отвергнуты») — не live-датапас-шаги, а
> design-assertion записи в runbook-rationale (документируются вместе с R10, без отдельного step-ID).

### Финальная верификация

`go test ./... -race` + `golangci-lint run` зелёные (operator, P1); envtest filter/writer/SSA/prune зелёные; live: P-DERISK-EXT ИСХОД A подтверждён (или ИСХОД B → STOP/down-scope с APPROVED-решением); P2 cross-zone reachable + cross-VPC isolation подтверждены на 2-cluster стенде.

---

## Не-цели (explicit non-goals)

1. **Контракт Kachō / proto НЕ меняется** — `Subnet.zone_id` + EXCLUDE-gist уже есть; cross-zone L3 — целиком data-plane (kube-ovn LR + underlay + direct OVN-NB), невидимо на публичной поверхности. `zone_id` required+immutable (open-decision #3) — отдельная proto-под-фаза, НЕ OP3.
2. **`Vpc.spec.staticRoutes` / `lr-policy` как import — НЕ используются** — стрипаются (#2) / прунятся на resync (§6.1/§6.2). Import = direct OVN-NB (решение A). OP2-P2-механизм остаётся в коде (issue #2), OP3 его не чинит и не удаляет.
3. **Shared-RR / общий RIB как import — ЗАПРЕЩЁН** — leak (§6.5, P2-08). OP2-P-BGP = только advertise/export (prod), не import. Per-VPC EVPN route-target (prod-BGP изоляция) — out-of-scope.
4. **VpcEgressGateway как import — НЕ используется** — wrong shape (§6.4, P2-09); VEG = external/internet-egress future.
5. **NAT / EIP / ENABLE_NAT_GW BGP — НЕ включаем** — within-VPC L3 — **no-NAT** (open-decision #1 default). external-egress NAT — future P3/P4 design-doc §2.
6. **3 кластера / 3-я зона — НЕ в OP3** — 2 зоны сначала (open-decision #2). 3-й kind — future.
7. **kube-ovn-controller datapath-флаги** меняются ТОЛЬКО осознанно с регресс-проверкой: external-LRP требует `enableExternal`/provider-subnet (DERISK-01) — это и есть scope; прочие (`ENABLE_NAT_GW` true вне external-egress) — НЕ флипаем без отдельного гейта.
8. **OP-SPLIT (kacho-iam-operator)** — рекомендован (open-decision #7) но **отдельная фаза**; OP3 datapath-gate от него не зависит.
9. **Реальный AuthN (validated JWT/IAM-token)** — приходит с IAM-интеграцией; OP3 использует SEC-G mTLS + least-priv viewer as-is (security.md), не меняет AuthN-модель.
10. **Multi-host фабрика** — все kind на одном docker-хосте (общий `kind`-бридж, open-decision #2/#6); multi-host меняет underlay — out-of-scope.

---

## Трассировка требований → сценарии

| Требование | Сценарии |
|---|---|
| external-lrp (custom-VPC LR → underlay attach) | OP3-MAZ-DERISK-01 |
| underlay-attach (kind-bridge transit) | DERISK-01, DERISK-02 |
| direct-ovn-route (libovsdb, plain dst-ip, не Vpc.spec) | DERISK-02, P1-03, P1-04 |
| durable (персистит через controller-restart) | DERISK-02, P1-04 |
| host-lr-ingress (пакет bridge→LR→pod — недоказанная половина) | DERISK-03 |
| hard-gate (датапас-feasible только после P-DERISK-EXT) | DERISK-04 |
| honesty (исход верифицирован на стенде, не предположение) | DERISK-03, DERISK-04 |
| zone-materialize (только zone_id==ZONE_ID) | P1-01, P1-07 |
| zone-read-all (читать все subnets для remote /18) | P1-02 |
| import-route (remote /18 → peer next-hop, same-Network) | P1-02, P1-03, P2-05 |
| idempotency (re-assert no-op, SSA no spurious-write) | P1-03, P1-05 |
| ssa (managedFields, per-zone fieldManager, list-type=map) | P1-05 |
| no-clobber (kube-ovn-defaulted поля сохранены) | P1-05 |
| zone-prune (zone-scoped, не трогает чужую зону) | P1-06 |
| replica-isolation (zone-sharding, рестарт) | P1-06, P3-01 |
| graceful (degraded, не паника, fail-closed мутации) | P1-07, P3-02 |
| two-cluster (2 kind на общем bridge) | P2-01 |
| cidr-deconflict (per-cluster CIDR различны; overlap → blackhole) | P2-01, P2-07 |
| geography-seed (Zone seed first, иначе sync INVALID_ARGUMENT `unknown zone id`) | P2-02 |
| ordering (seed → Subnet.Create) | P2-02 |
| cross-cluster-transport (NodePort :9090 + mTLS) | P2-03, P2-04 |
| internal-not-exposed (NodePort никогда :9091) | P2-03 |
| mtls-perimeter (enable=false→on; per-zone cert; BGP вне mesh) | P2-04, P3-03, P3-04 |
| cross-zone-reachable (pod↔pod within Network, no-NAT) | P2-05 |
| within-vpc (одна Network, routed L3 без L2) | P2-05 |
| cross-vpc-isolation (разные Network → нет достижимости, ТВЁРДОЕ) | P2-06, P2-08 |
| non-goal: shared-RR/VEG как import отвергнуты | P2-08, P2-09 |
| security (infra-sensitive Internal*/config; least-priv) | P2-03, P3-03, P3-04 |
| infra-sensitive (next-hop/ASN/VNI/RT/underlay → не публично) | P3-04 |
| non-goal: OP1/OP2-P-BGP/mTLS/ns-operator не регрессируют | P3-05 |
| vault (edges/resources/KAC-trail обновлены) | P3-05 |
| ticket/branch binding (ban #1, pre-APPROVAL gate) | заголовок §«Привязка к тикету» |
