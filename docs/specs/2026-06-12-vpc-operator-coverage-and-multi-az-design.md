# Дизайн: покрытие ресурсов kacho-vpc-operator + multi-AZ L3-interconnect

**Документ:** design-proposal (pre-acceptance для нереализованных фаз) · 2026-06-12
**Статус:** Часть «покрытие ресурсов» — активный roadmap реализации; «multi-AZ» —
proposal, ждёт продуктовых решений (см. §«Открытые вопросы»).
**Scope:** `kacho-vpc-operator` (data-plane sibling, вне build-графа control-plane) +
`kacho-deploy` (kube-ovn helm/kind) + `kacho-compute` (Geography Zone seed). Control-plane
proto/API менять **не требуется** для v1 (`Subnet.zone_id` + per-Network EXCLUDE-gist
non-overlap уже есть).

Основано на двух research-workflow (2026-06-12), заземлённых на живом стенде
(kube-ovn v1.16.1, `kind-kacho`) + офиц. доки kube-ovn. Полные per-resource mappings и
per-angle findings — в transcript'ах workflow.

---

## 1. Текущее состояние (что уже материализуется)

OP1 (KachoSubnet CRD): **Network → kube-ovn Vpc** (`=net-id`, isolated custom VPC);
**Subnet → N×(kube-ovn Subnet + Multus NAD)** по одному на CIDR (single-family, решение A),
cluster-scoped intermediate CRD `KachoSubnet`, ingress poll-syncer + egress
controller-runtime Reconciler (ownerRef+finalizer, element-prune, field-scoped apply,
stable-by-**immutable-id** имена `<sub-id>-<cidrhash>`). NIC fixed-IP — частично (webhook).

**Baseline для всех новых фаз** — машинерия KachoSubnet: cluster-scoped CRD, ingress
1:1 mirror (без Watch), egress Reconciler, `SetControllerReference`+finalizer teardown,
content-stable id-naming, **field-scoped apply** (писать только свои ключи),
element-prune, in-use guard, degraded-conditions. Общие хелперы (`internal/kubeovn`,
`naming.go`/`canonicalCIDR`/`childName`) — **shared-пакеты**, не дублировать (drift =
корень бага #1).

---

## 1a. Разделение кодовой базы: IAM-контроллер ⟂ VPC-контроллер (решение 2026-06-12)

Сейчас репо `kacho-vpc-operator` совмещает **два независимых контроллера**:
- **IAM/project-контроллер** (`cmd/nsoperator`, `internal/nssyncer`) — потребляет
  kacho-iam (`AccountService.List → ProjectService.List`), материализует Project → k8s
  Namespace (lifecycle/labels/prune). Никак не зависит от kube-ovn/VPC.
- **VPC-контроллер** (`cmd/main.go`, `internal/{syncer,controller,kubeovn,webhook}`,
  `api/v1 KachoSubnet`) — материализует VPC-сущности → kube-ovn/Multus.

**Решение:** разнести в **две отдельные кодовые базы** (polyrepo-native):
- `kacho-iam-operator` (новый репо) — IAM/project-контроллер (проекты→namespaces).
- `kacho-vpc-operator` — только VPC-сущности→kube-ovn (остаётся; из него уходит
  `cmd/nsoperator` + `internal/nssyncer`).

Зачем: чистая граница ответственности (один контроллер = один домен), независимый
lifecycle/CI/RBAC (project-оператору нужен только namespace-CRUD + чтение iam; vpc-
оператору — kube-ovn/Multus + чтение vpc), отсутствие ложной связности доменов в одном
бинаре. Соответствует `kacho-<part>` конвенции и build-границам (оба — sibling вне
build-графа control-plane). Фаза **OP-SPLIT** (см. §2) — фундаментальная, до добавления
новых VPC-ресурсов в VPC-контроллер.

## 1b. Скилы для разработки kube-контроллеров (обязательно)

Вся разработка/рефакторинг контроллеров (CRD, reconciler, webhook, dev-loop) ведётся с
применением плагин-скилов: **`k8s-crd-design`** (схема/версионирование CRD),
**`k8s-operator-workflow`** (kubebuilder-паттерны, dev-loop, RBAC), **`k8s-quality-
checklist`** (проверка качества контроллера), **`k8s-templates`**; Go-стиль — `evgeniy`.
Это дополняет (не отменяет) acceptance-first + строгий TDD (envtest).

## 2. Roadmap покрытия ресурсов (single-cluster)

Заземлено на живом стенде: все целевые kube-ovn CRD присутствуют
(`vips`, `security-groups`, `vpc-egress-gateways`, `vpc-nat-gateways`, `ovn-eips`);
NAT-путь **выключен**: `ENABLE_NAT_GW=false` + `ENABLE_EIP_SNAT=false`
(`argo-apps/kube-ovn/{values.kind.yaml,application.yaml}`).

| Фаза | Ресурс | Механизм | Гейт/риск |
|---|---|---|---|
| **P0** (старт) | NIC fixed-IP + internal Address (v4/v6) | **pod-annotation** (webhook). Чинит **#1** (NAD по `<sub-id>-<cidrhash>`, не голый `<subnet-id>`), общий `childName` пакет, dual-stack | latent data-loss, без CRD/NAT |
| **P1** | SecurityGroup + rules + NIC-binding | `KachoSecurityGroup` CRD → `security-groups.kubeovn.io` (ACL ingress/egress) + per-NIC `<provider>.kubernetes.io/security_groups` annotation | ⚠ проверить, что SG-ACL действует **внутри custom-VPC** (иначе silent no-op изоляции) |
| **P2** | RouteTable + static routes | `KachoRouteTable` CRD → `Vpc.spec.staticRoutes[]` (field-scoped, **без** ownerRef-каскада; prune по `(cidr,nextHop,policy)`) | write-contention на Vpc (Network ingress тоже пишет Vpc) → строго field-scoped |
| **P3** | infra enablement | flip `ENABLE_NAT_GW=true` + external underlay (kacho-deploy), re-roll kube-ovn | отдельный гейт; re-roll может задеть рабочий datapath |
| **P4** | Gateway (shared-egress/NAT) | `KachoGateway` CRD → `vpc-egress-gateways.kubeovn.io` (Namespaced, self-SNAT) | gated P3; proto Gateway **пустой** → scoping/external-IP/placement только через Internal* (security.md) |
| **P5** | Address (reserved internal + external/elastic) | `KachoAddress` CRD → `vips` (reserved-internal, pin точного IP) / `ovn-eips`+NAT-rules (external). NIC-bound internal остаётся P0 pod-annotation | gated P4; IPAM-pin, **не** `ips`/`ippools` (kube-ovn-owned); atomic teardown EIP+NAT |

**DAG:** `P0 → P1`; `P0 → P5 (+P4)`; `P2` (NAT-independent, но `gateway_id`-next-hop ждёт P4);
`P3 → P4 → P5(external)`. P0/P1/P2 — без NAT, можно сразу.

**Фундаментальная фаза OP-SPLIT (до/параллельно P0):** разнести IAM/project-контроллер в
новый репо `kacho-iam-operator`, оставить `kacho-vpc-operator` чисто VPC (см. §1a). Это
рефактор-перенос (`cmd/nsoperator`+`internal/nssyncer` → новый репо; deploy `operator-up.sh`
поднимает оба; CI на оба). P0 (webhook) — VPC-контроллер, остаётся в `kacho-vpc-operator`.

**Рекоменд. старт: OP-SPLIT → P0** — P0 чинит латентную регрессию NIC-attach (#1),
webhook-only, без CRD/NAT, минимальный blast-radius, задаёт shared-naming контракт для P1/P5.

---

## 3. Multi-AZ L3-interconnect (proposal)

### 3.1 Главный verified-вывод
**OVN-IC связывает только default-VPC (`ovn-cluster`).** Kachō кладёт каждую Network в
**custom-VPC** (`kacho-<net-id>`) → vanilla `enable-ic + auto-route` = **тихий no-op**
(ноль связности Kachō-подсетей, без ошибки). VPC Peering (`vpcPeerings`) — только
внутри кластера. ⇒ **OVN-IC отвергнут**; явно запретить `ENABLE_IC` в deploy-values
(ловушка). На живом стенде IC не установлен/не сконфигурён (verified).

> [!warning] LIVE-BLOCKER (2026-06-12, kacho-vpc-operator#2) — Vpc.staticRoutes стрипается
> На стенде (kube-ovn v1.16.1, NON_PRIMARY custom-VPC) **kube-ovn-controller удаляет
> user-добавленные `Vpc.spec.staticRoutes` за ~1с** (add→del cycle; vpc.go:525 add →
> vpc.go:507 del с `ECMPMode:ecmp_symmetric_reply`). Воспроизведено и ручным
> `kubectl patch` (без оператора), и с явным `ecmpMode`. OVN LR держит только auto
> subnet-routes. Подозрение: route получает `ecmp_symmetric_reply` при
> `--enable-ecmp=false` → kube-ovn его удаляет. **Это блокирует И OP2-P2 RouteTable, И
> выбранный ниже multi-AZ-механизм (operator-written Vpc.staticRoutes).** До решения
> (kube-ovn config/version, либо `policyRoutes`, либо BGP) inter-zone L3 через
> staticRoutes не работает. Оператор пишет корректно (envtest-green) — блокер на стороне
> kube-ovn.

### 3.2 Выбранный механизм — операторские `Vpc.spec.staticRoutes` (BGP в prod)
Каждый оператор пишет в свой custom-VPC `staticRoutes` на remote /18 (next-hop =
gateway-нода соседней зоны). Два тира:
- **PoC/kind:** static-route mesh, без BGP. 3 kind на общем docker-бридже `kind`
  (172.19.0.0/16 → ноды взаимно достижимы). Детерминированно, in-version.
- **Prod:** `VpcEgressGateway.bgpConf` + route-reflector → динамика, ECMP/BFD. EVPN
  отложить (экспериментальный в 1.16). Honest gap: в v1.16.1 нет CRD-поля, авто-
  устанавливающего BGP-learned префиксы в custom-VPC LR → learn-side = оператор пишет
  `Vpc.staticRoutes` (это **и есть** фаза RouteTable — дорожки сходятся).

### 3.3 Топология
```
control-plane (1 набор): Network enp-X · Subnet-A zoneA 10.80.0.0/18 · -B zoneB 10.80.64.0/18 · -C zoneC 10.80.128.0/18
   (DB EXCLUDE-gist subnets_no_overlap per network_id — непересечение уже гарантировано)
        │ gRPC poll (mTLS SEC-G); каждый оператор читает ВСЕ subnets, материализует свою зону, УЧИТ remote /18
 kind-zoneA / kind-zoneB / kind-zoneC  (= 3 AZ; vpc+project-оператор; KACHO_ZONE_ID=zoneX)
   VPC enp=net-id  ← одно имя, 3 НЕЗАВИСИМЫХ LR (НЕ растянутый L2)
   Subnet своей зоны +NAD; gw-нода
   Vpc.staticRoutes → два remote /18 via peer-node-IP (PoC) / BGP-learned (prod)
 Итог: pod zoneA → VPC-LR → route remote/18 nh=peer-node → underlay(kind bridge) → peer VPC-LR → pod. Routed L3, без L2.
```

### 3.4 Адресация
Network **не имеет CIDR-поля** (supernet — admin/AddressPool-конвенция). Пример
supernet `10.80.0.0/16` → disjoint /18 на зону. IPAM authority = **kacho-vpc**
(EXCLUDE-gist per network_id). kube-ovn IPAM — subordinate (каждый kube-ovn Subnet
держит только свой /18; pod fixed-IP через NIC→Address→annotation). ⚠ Нарезать
per-cluster дефолты kube-ovn (`ovn-default 172.30/16`, `JOIN_CIDR 100.64/16` —
одинаковы во всех kind) + distinct kindnet pod/svc subnets.

### 3.5 Изменения оператора (zone-awareness)
1. `KACHO_VPCOPERATOR_ZONE_ID` env; пробросить `subnet.zone_id` в `KachoSubnetSpec.ZoneID`.
2. Материализовать subnet только если `zone_id == ZONE_ID`; один деплой оператора на kind.
3. VPC-name `=net-id` одинаков во всех кластерах (3 независимых LR — задокументировать).
4. Route-advertise: оператор читает ВСЕ subnets Network (zone-фильтр гейтит только
   *материализацию*, не *чтение*), пишет remote /18 в `Vpc.staticRoutes` (+ `bgpConf` в prod).
5. **Replica-isolation**: партиционирование по `zone_id`; prune/GC zone-scoped
   (label `kacho.io/zone=<zone-id>`) — оператор не трогает чужую зону.
6. `Vpc.staticRoutes` пишется **field-scoped** (как egress applyChild) — иначе OCC hot-loop.
7. Блокирующий пререквизит: фикс #1 (NAD-name) — иначе поды в multi-AZ не attach'атся.

### 3.6 Изменения kacho-deploy
3 kind на общем `kind`-бридже (НЕ изолировать — нужны взаимно достижимые ноды);
distinct pod/svc subnets per kind; per-zone kube-ovn values; `func.ENABLE_NAT_GW=true`
(для GW/BGP-пути), `--enable-ecmp`/`--enable-external-vpc` где надо; **НЕ** `ENABLE_IC`;
`dataplane-up.sh`/`operator-up.sh` параметризовать per-context (`KACHO_ZONE_ID`); seed
3 Geography Zone в kacho-compute (под `Subnet.zone_id` валидацию). Next-hop/ASN/VRF —
infra-sensitive → только Internal* (security.md).

### 3.7 Фазы multi-AZ
`P0`(#1 NAD-fix) → `P0.5` custom-VPC route proof (1 кластер) → `P1` 2-cluster static-mesh
PoC + zone-aware оператор → `P2` zone-sharding hardening → `P3` 3 кластера + 3 Zone →
`P4` prod BGP+RR. **Старт: P0 → P0.5 → P1, на 3 не прыгать.**

---

## 4. Открытые вопросы (нужны продуктовые решения до acceptance/epic)
1. Цель v1 multi-AZ: static-mesh (проще) или сразу BGP+RR?
2. 3 kind остаются single-host (общий `kind`-бридж)? Multi-host меняет фабрику.
3. Где нарезка supernet→/18: AddressPool / новый internal-allocator / конвенция оператора?
4. `zone_id` делаем required+immutable для multi-AZ Network? Одна подсеть на зону или N?
5. Scope связности: pod-to-pod именно по secondary (kube-ovn) NIC, или достижимости Kachō-IP достаточно?
6. ASN-план + какой Internal*-API отдаёт next-hops/ASN.
7. Завести cross-repo EPIC (operator zone-shard+routes · deploy 3-kind · compute zone-seed · workspace docs).

---

## 5. Сквозные риски (master)
1. **OVN-IC silent-no-op** для custom-VPC — запретить `ENABLE_IC`.
2. **Custom-VPC learn-side gap** — нет CRD авто-установки BGP-routes в custom-VPC LR → оператор → `Vpc.staticRoutes`.
3. **OCC hot-loop** — все записи в общий Vpc (staticRoutes) строго field-scoped; ловится только на живом кластере (envtest слеп).
4. **VPC-scope SG-ACL** в custom-VPC — возможен silent no-op изоляции; проверить до P1.
5. **Delete-cascade ordering** — external Address EIP+NAT atomic; route element-prune без ownerRef; in-use guards.
6. **Internal-vs-public surface** — Gateway scoping/external-IP/placement + NAT-wiring + next-hops/ASN — только Internal* (security.md).
7. **#1 NAD-ref** блокирует attach подов → P0 первым.

> Реализация — только после APPROVED Given-When-Then на под-фазу (ban #1). Multi-AZ —
> после решений §4. Связанные сущности vault: [[vpc-operator-to-kubeovn]],
> [[kacho-vpc-operator-KachoSubnet]]. Issues: kacho-vpc-operator#1 (NAD-ref).

---

## 6. P-DERISK live findings (2026-06-12, single 'kacho' cluster) — multi-AZ goal

Эмпирическая де-рисковка (design-research workflow + adversarial-verify + live nbctl). Меняет §3.

### 6.1 Root-cause #2 (strip) — установлен
`Vpc.spec.staticRoutes {policyDst}` на custom-VPC: kube-ovn ставит LR-route (`dst-ip`),
через ~4с удаляет. Логи: `vpc.go:525 add ... ECMPMode:` (пусто) → `vpc.go:507 del ...
ECMPMode:ecmp_symmetric_reply`. kube-ovn/OVN тегает spec-driven dst-routes
`ecmp_symmetric_reply`, при `--enable-ecmp=false` reconcile их прунит (+ затирает из
`vpc.spec.staticRoutes`). Auto `src-ip` subnet-routes не трогаются.

### 6.2 Durable import lever — НАЙДЕН
Route, записанный **напрямую в OVN-NB** (`ovn-nbctl lr-route-add`, vendor-untagged) →
plain `dst-ip` (без `ecmp_symmetric_reply`) → **ПЕРСИСТИТ через Vpc-reconcile,
spec-change И полный restart kube-ovn-controller** (kube-ovn диффит только свои routes
из `vpc.spec`, чужие NB-routes не трогает). Прямой `lr-policy` reroute переживает
reconcile, но **прунится на полном resync** (отвергнут). ⇒ import = **direct OVN-NB
(libovsdb), не `Vpc.spec.staticRoutes`**.

### 6.3 Реальный gate — custom-VPC LR не имеет external-порта
Custom-VPC LR имеет ТОЛЬКО subnet-порты (по одному на subnet), **нет external/gateway
LRP** (у `ovn-cluster` есть `-join`). ⇒ next-hop dst-route'а (node-IP) недостижим из LR,
и нет host→LR ingress-пути. На стенде НЕТ provider-network / vlan / external-subnet
(`ENABLE_NAT_GW=false`). Cross-zone L3 требует подключить каждый custom-VPC LR к
**underlay (kind-бридж)** через external-LRP (`Vpc.enableExternal` + provider-subnet).

### 6.4 VpcEgressGateway — НЕ механизм import (adversarial-verify)
VEG — `ip4.src`-reroute + SNAT (egress-to-external), НЕ `ip4.dst==remote/18` import. Его
EVPN/BGP учит routes в FRR gw-пода + SNAT, не в OVN LR. Wrong shape для no-NAT
within-VPC L3. ⇒ VEG = только external/internet-egress (P3/P4), не cross-zone import.

### 6.5 Изоляция VPC — структурная (sound)
Разные Network → разные custom-VPC LR → нет общих routes. Оператор пишет cross-zone
route в LR ТОЛЬКО на remote /18 ТОЙ ЖЕ Network → VPC-X не достаёт VPC-Y. **Shared BGP-RR
для import = leak** (speaker анонсит все CIDR в один RIB без Spec.Vpc-фильтра) → RR НЕ
использовать как import-путь; для prod-BGP изоляция требует per-VPC EVPN route-target.

### 6.6 Пересмотренный механизм (для acceptance)
Cross-zone no-NAT within-VPC L3 на v1.16.1 custom-VPC = (a) каждый custom-VPC LR на
underlay (kind-бридж) через external-LRP; (b) durable dst-route на remote /18 →
peer-node/underlay-IP, записанный **прямо в OVN-NB** (libovsdb, не Vpc.spec — обход
ecmp-prune) с SSA-стилем ownership (managedFields неприменим к OVN-NB, но к k8s-CR —
да); (c) underlay = общий kind docker-бридж; (d) изоляция структурная per-VPC.
**Открытый gate до acceptance-кода:** доказать external-LRP + forwarding pod→bridge на
ОДНОМ кластере (provider-network setup) — это последний make-or-break.

### 6.7 P-DERISK-EXT RESULT — datapath FEASIBLE (PROVEN live, 2026-06-12)

Hard gate из acceptance OP3-MULTIAZ пройден на одном кластере 'kacho' (kube-ovn v1.16.1).
`datapath_feasible` пересмотрен с FALSE → **TRUE**.

**Проверенный рецепт (custom-VPC LR ↔ underlay-бридж):**
1. Второй docker-NIC на ноде (`docker network create kacho-underlay 172.31.0.0/16` +
   `docker network connect` → нода получает eth1).
2. kube-ovn `ProviderNetwork{defaultInterface: eth1}` + `Vlan{id:0, provider}` +
   `Subnet{vlan, vpc: <custom>, cidr: 172.31.0.0/16}` (underlay, attached to custom VPC).
   → kube-ovn создаёт OVS `br-underlay`, переносит IP eth1→br-underlay, provider ready.
3. **`subnet.spec.u2oInterconnection: true`** — ключевой шаг: kube-ovn создаёт LRP
   `<vpc>-<transit-subnet>` на custom-VPC LR с u2oIP (172.31.0.51) + auto-route
   `172.31.0.0/16 → 172.31.0.1 src-ip`. **Это внешняя дверь LR на underlay.**
4. Durable cross-zone route: `ovn-nbctl lr-route-add <vpc> <remote/18> <peer-transit-IP>`
   (прямой OVN-NB, plain dst-ip, переживает reconcile+restart — §6.2).

**Доказанный датапас (bidirectional):** pod `192.168.88.12` (net1) → LR `192.168.88.1`
→ transit-LRP `172.31.0.51` → br-underlay/eth1 → нода `172.31.0.2` — **ping 3/3, 0% loss**.
Обратный путь (нода→`172.31.0.51`→LR→pod) = **host→LR ingress injection РАБОТАЕТ** (та самая
«недоказанная половина» из adversarial-verify). Cross-zone = заменить «ноду 172.31.0.2» на
transit-IP LR соседней зоны + durable dst-route на remote /18.

**Изоляция:** pod net1 → CIDR другого VPC (29.62.0.1) = 100% loss (нет route → нет пути).
Структурно: оператор пишет cross-zone route ТОЛЬКО на remote /18 той же Network; без route
пути нет. (Для prod на shared underlay — per-VPC transit для L2-изоляции.)

**Следующее (P1/P2):** оператор zone-aware + программирует transit-subnet(u2o) + durable
dst-route на remote /18 (libovsdb) per materialized Network; затем 2 зональных kind на общем
бридже, кросс-роуты same-Network /18, проверка A↔B within-VPC + cross-VPC изоляция.

### 6.8 P2 MANUAL DATAPATH PROVEN — cross-zone within-VPC + isolation (live, 2026-06-12)

3 kind на общих бриджах (`kind` 172.19/16 + `kacho-underlay` 172.31/16):
`kacho`(cp, .2), `kacho-zonea`(.3), `kacho-zoneb`(.4). Per-zone kube-ovn v1.16.1
NON_PRIMARY с деконфликтнутыми CIDR (ovn-default 172.32/172.33, join 100.65/100.66,
kindnet pod 10.245/10.246, svc 10.97/10.98) + multus + provider-network(eth1)+vlan.

**Per zone (manual, = будущая работа оператора):** Vpc `net-demo` + overlay subnet
(zoneA 10.80.0.0/18, zoneB 10.80.64.0/18) + transit subnet (172.31/16, vlan, vpc=net-demo,
**u2oInterconnection** → LRP на underlay: zoneA u2oIP 172.31.0.101, zoneB .151) + NAD +
pod (net1 на overlay). Cross-route (direct OVN-NB): zoneA `10.80.64.0/18→172.31.0.151`,
zoneB `10.80.0.0/18→172.31.0.101`. Pod route на remote /18 через net1-LR (NET_ADMIN).

**РЕЗУЛЬТАТ:**
- ✅ **Cross-zone within-VPC: demo-zonea (10.80.0.3) ↔ demo-zoneb (10.80.64.3) — 0% loss,
  bidirectional, TTL=62 (2 LR-хопа).** Поды в РАЗНЫХ kind-кластерах видят друг друга в
  рамках одного VPC, routed L3 через underlay (без L2-растяжки).
- ✅ **Cross-VPC изоляция: other-zonea (net-other 10.81.0.2) НЕ достаёт net-demo**
  (10.80.0.3 ни 10.80.64.3) даже с добавленным pod-route — LR net-other не имеет route →
  drop. net-demo при этом продолжает работать. Изоляция структурная (per-VPC LR).

⇒ Цель достижима. Остаётся **автоматизация оператором** (P1): zone-aware materialize +
transit(u2o) + direct-OVN cross-route + cross-cluster чтение control-plane.

### 6.9 P1 OPERATOR AUTOMATION — реализовано (kacho-vpc-operator, ветка OP3-MULTIAZ, envtest TDD)

Автоматизирует ручной рецепт §6.7/§6.8 в коде оператора (envtest RED→GREEN; live-verify
отдельно). Реализованные части:

1. **`KachoSubnetSpec.ZoneID`** (`api/v1`, `json:"zoneId"`) — зеркало `Subnet.zone_id`;
   syncer (`internal/syncer`) заполняет из `Subnet.GetZoneId()` (read-all, без zone-фильтра
   на чтении — решение D).
2. **Zones config** (`internal/config/zones.go`): `KACHO_VPCOPERATOR_ZONE_ID` (своя зона) +
   `KACHO_VPCOPERATOR_ZONES` (JSON `[{"id","transitHost"}]`). Типизированный `Zones` +
   `ByID/OtherThan/TransitIP`. `VpcIdx(networkID)=crc32%240` (детерминирован, стабилен между
   зонами; коллизии допускаются для PoC — разные Network = разные LR, изоляция структурна).
   transit IP `(vpcIdx,zone)` = `172.31.<vpcIdx>.<transitHost>` — вычислим обеими зонами из
   общего config → симметричные cross-routes без runtime-обмена.
3. **Zone-filter материализации** (`KachoSubnetReconciler.ZoneID`): материализуем kube-ovn
   Subnet+NAD только для своей зоны (`ks.Spec.ZoneID==ZoneID`); чужая зона — CR удерживается
   (read-all для cross-route awareness), но НЕ материализуется/прунится (replica-isolation).
   `ZoneID=""` ИЛИ пустой `ks.Spec.ZoneID` → materialize-all (single-cluster back-compat —
   незональный оператор/подсеть не «прячутся»).
4. **`KachoInterconnectReconciler`** (`internal/controller/kachointerconnect_controller.go`,
   `For(KachoSubnet)`, группировка по NetworkID): per-Network с local-zone subnet'ом —
   ensure ОДНУ transit u2o Subnet (`<nid>-transit`, `cidrBlock=172.31.<idx>.0/24`,
   `u2oInterconnection:true`, `vlan=underlay-vlan`, `vpc=<nid>`, `excludeIps` пинит
   u2oIP на own-zone host) + cross-routes на remote-/18 той же Network через REUSE
   `applyVpcRoutesFor`/`mergeStaticRoutes` (element-scoped, owned-set, OCC-retry; `policyDst`).
5. **Pod remote-routes** (`internal/webhook/v1`): `kubeovn.PodRoutes(gw, remoteCIDRs)` →
   аннотация `<provider>.kubernetes.io/routes`; webhook резолвит remote-/18 той же Network
   (`SubnetResolver.List` + фильтр `networkId` + `zone!=own`) и инъектит маршрут через
   gateway overlay-подсети (LR). Изоляция: только same-Network.

> **РЕШЕНИЕ ПО МЕХАНИЗМУ cross-route (отличие от §6.2 direct-OVN-NB):** P1-реализация
> пишет cross-route в **`Vpc.spec.staticRoutes`** (REUSE OP2-P2 writer), а НЕ через
> прямой OVN-NB libovsdb. Это сознательный выбор для текущего тира: стенд гоняется с
> **`--enable-ecmp=TRUE`**, при котором spec-driven dst-routes НЕ прунятся (#2 root-cause
> §6.1 — прун происходит при `--enable-ecmp=false`). Под ecmp=TRUE `Vpc.spec.staticRoutes`
> ПЕРСИСТИТ, поэтому direct-OVN-NB (сложность libovsdb + ownership-by-externalID) не нужен.
> **Если кластер вернётся к `--enable-ecmp=false`** — cross-route снова будет стрипаться,
> и потребуется direct-OVN-NB writer (§6.2) как отдельная под-фаза. Durability пиннится на
> (kube-ovn v1.16.1, ecmp=TRUE).

> **SSA follow-up (решение E):** спорные записи в общие CR (transit Subnet, `Vpc.spec.staticRoutes`)
> ведутся **field/element-scoped** (мёрж только своих ключей/элементов, no whole-object
> clobber) + стабильный **fieldManager `kacho-vpc-operator-<zone>`** (через `client.FieldOwner`
> на Create/Update). Полный переход на **Server-Side Apply** (`Patch` + `types.ApplyPatchType`,
> `list-type=map`-keyed staticRoutes) — отдельная follow-up под-фаза P3 (не блокирует
> datapath P2; текущий field-scoped+fieldManager уже устраняет whole-object clobber и даёт
> per-operator co-ownership). **Это не code-TODO — это документированное by-design-решение
> тира P1.**

### 6.9 OP3-MULTIAZ operator (live, 2026-06-12/13) — automated cross-zone

Зональный оператор (`KACHO_VPCOPERATOR_ZONE_ID` + `KACHO_VPCOPERATOR_ZONES`) развёрнут в
2 зональных kind (`kacho-zonea`/`kacho-zoneb`), читает control-plane cross-cluster
(NodePort `vpc-cross` :9090 на node-IP контрол-плейна, **только public, не :9091**;
SEC-G mTLS, SERVERNAME pin `vpc.kacho.svc.cluster.local`). Автоматизирует:
- **syncer** mirror control-plane Subnet→KachoSubnet (ZoneID из `Subnet.zone_id`, read-all);
- **zone-filter** материализации (своя зона материализует kube-ovn Subnet+NAD, чужую — нет);
- **interconnect**: transit-subnet (u2o) + cross-route computation для multi-zone Network.
Live: pod zoneA `192.168.88.2` ↔ pod zoneB `10.80.64.2` в одном VPC `netrpwd…` — **0% loss
bidirectional**; single-zone VPC `netnqb…` без transit/cross-route — изолирован.
Deploy: `kacho-deploy/multiaz/{operator-up.sh,kind-zone{a,b}.yaml}`.

### 6.10 РЕШЕНО/follow-up — transit /16 + cross-route delivery

- **Transit ОБЯЗАН быть полный bridge /16** (real gateway `172.31.0.1`): /24-срез не
  бриджуется (gateway `172.31.<idx>.1` не на L2) → LR transit-порт недостижим. Оператор
  создаёт `172.31.0.0/16` u2o-transit ТОЛЬКО для multi-zone VPC; multi multi-AZ VPC —
  per-VPC VLAN (follow-up).
- **#2 strip нестабилен**: `Vpc.spec.staticRoutes` dst-route стрипается kube-ovn v1.16.1
  (`ecmp_symmetric_reply`) **НЕЗАВИСИМО от `--enable-ecmp`** (ранее §6.9-черновик ошибочно
  считал ecmp=true фиксом — на нестабильном стенде flaky). **Надёжный механизм — direct
  OVN-NB `lr-route-add`** (переживает reconcile+restart, §6.2). Live-демо cross-route'ы
  заведены прямым OVN-NB. **Follow-up:** оператор `applyCrossRoutes` → libovsdb direct-OVN
  вместо `Vpc.spec.staticRoutes` (kube-ovn-operator#2). Pod remote-/18 route — через
  webhook (NIC-attach flow); в demo добавлен вручную (raw-NAD поды).

### 6.11 OP3-MULTIAZ COMPLETE — operator-automated, continuous, stable (live, 2026-06-13)

Cross-route доставка переведена с `Vpc.spec.staticRoutes` (стрипается, конфликтует) на
**direct OVN-NB** (`ovn-nbctl lr-route-{list,add,del}` exec в поде ovn-central, пакет
`internal/ovnnb`). interconnect-reconciler: list→diff→add/del, owned-set = next-hop ∈
transit-IP всех зон (add=desired\current, del=owned-current\desired, чужие не трогаем),
`Vpc.spec` НЕ пишется. RBAC: pods get/list + pods/exec create.

**Финальный live-результат (операторы РАБОТАЮТ непрерывно, не g-down):**
- Оператор сам программирует cross-routes в OVN-NB (лог `added cross-zone LR route`);
  `Vpc.spec.staticRoutes` пуст → нет strip-конфликта; LR-route стабилен ≥30с.
- pod zoneA `192.168.88.2` ↔ pod zoneB `10.80.64.2` в одном VPC — **0% loss bidirectional,
  СТАБИЛЬНО при работающих операторах**.
- single-zone VPC — без transit/cross-route (изоляция).

⇒ Multi-AZ цель закрыта end-to-end автоматически: control-plane на опорном kind, 2
зональных kind с операторами, поды A↔B в рамках VPC видят друг друга, вне VPC — нет.
PR: kacho-vpc-operator#4, kacho-deploy#76. Остаток (prod-hardening, не блокер):
full SSA, per-VPC VLAN для нескольких multi-AZ VPC, pod remote-route через webhook
(NIC-attach flow) вместо ручного, libovsdb вместо exec.
