# Sub-phase OP2-P-BGP — Kachō subnet routing via kube-ovn-speaker BGP — Acceptance

> Статус: DRAFT
> Дата: 2026-06-12
> Ревьюер: acceptance-reviewer (gate перед кодом, ban #1)
> Скилы: `k8s-operator-workflow` (dev-loop / RBAC / kind-only safety), `k8s-quality-checklist` (controller/RBAC/safety), `evgeniy` (Go-стиль для operator-кода)

### Привязка к тикету (ban #1 + git-youtrack — обязательна ДО APPROVED-for-code)

> [!important] Pre-APPROVAL gate
> Этот acceptance-док НЕ может быть APPROVED-for-code, пока поля ниже не заполнены
> **реальным** KAC-номером (не плейсхолдером). Номер присваивает orchestrator (он
> владеет YouTrack-доступом) до старта кодинга; заведение тикета + KAC-trail — последний
> шаг перед снятием gate, не часть acceptance-текста.

| Поле | Значение |
|---|---|
| Эпик | `KAC-<EPIC>` `[EPIC] kacho-vpc-operator — покрытие VPC-ресурсов (OP2)` (Subtask-иерархия; design-doc §2 roadmap + §3 multi-AZ) |
| Subtask (этот док) | `KAC-<N>` `OP2-P-BGP — subnet routing через kube-ovn-speaker BGP (замена стрипаемых Vpc.staticRoutes)` |
| Ветка `kacho-deploy` | `KAC-<N>` (speaker DaemonSet + RR-под + kube-ovn values, от `main`) |
| Ветка `kacho-vpc-operator` | `KAC-<N>` (egress: BGP-advertise аннотация на материализуемой kube-ovn Subnet, от `main`) |
| Правка vault `kacho-workspace` | `obsidian/kacho/edges/vpc-operator-to-kubeovn.md` + новая `obsidian/kacho/edges/kube-ovn-to-bgp-fabric.md` (новое data-plane ребро) + `obsidian/kacho/KAC/KAC-<N>.md` (KAC-trail) |
| YouTrack | `https://prorobotech.youtrack.cloud/issue/KAC-<N>` |
| Роль исполнителя | `acceptance-author` (этот док) → реализация: domain-агенты `kacho-vpc-operator` + `kacho-deploy` |

> Затронутые репо: `kacho-deploy` (speaker DaemonSet + RR-под/манифест + kube-ovn
> values + RBAC node-label) + `kacho-vpc-operator` (egress-reconciler выставляет
> BGP-advertise аннотацию на kube-ovn Subnet) + правка `obsidian/kacho/...`
> (`kacho-workspace`).
> Зависит от: **OP1** (KachoSubnet machinery — egress `applySubnet` field-scoped apply
> kube-ovn Subnet; shared `internal/kubeovn` — naming/labels) — **не должно
> регрессировать**.
> **Control-plane / proto НЕ меняются** (data-plane-only sub-phase). Kachō по-прежнему
> без Watch; BGP — целиком data-plane-механизм (kube-ovn ↔ BGP-фабрика), невидимый на
> публичной поверхности Kachō-ресурсов.

---

## Обзор

`kacho-vpc-operator` (data-plane sibling, вне build-графа control-plane) материализует
**Network → kube-ovn Vpc** (custom-VPC, имя = `network_id`) и
**Subnet → N×(kube-ovn Subnet + Multus NAD)** (OP1). Для inter-zone L3 (multi-AZ)
требуется, чтобы CIDR подсети каждой зоны был **доставлен в маршрутизацию** соседних
зон.

Изначально выбранный механизм — operator-written `Vpc.spec.staticRoutes[]` (OP2-P2,
multi-AZ design-doc §3.2) — **заблокирован на живом стенде**:

> [!warning] LIVE-BLOCKER (kacho-vpc-operator#2): kube-ovn стрипает user `Vpc.staticRoutes`
> На `kind-kacho` (kube-ovn v1.16.1, NON_PRIMARY custom-VPC) kube-ovn-controller удаляет
> user-добавленные `Vpc.spec.staticRoutes` (а равно `policyRoutes`) за ~1-5с (add→del
> cycle). Воспроизведено ручным `kubectl patch` (без оператора) и с явным `ecmpMode`.
> OVN LR держит только auto subnet-routes. Подозрение: route получает
> `ecmp_symmetric_reply` при `--enable-ecmp=false`. Это блокирует И OP2-P2 RouteTable,
> И multi-AZ Vpc.staticRoutes. Оператор пишет корректно (envtest-green) — блокер на
> стороне kube-ovn.

**Продуктовое решение (этот док):** маршрутизацию Kachō-подсетей вести через **BGP
(kube-ovn-speaker)**, а НЕ через стрипаемый `Vpc.spec`. Speaker анонсирует CIDR подсети
в BGP-фабрику (route-reflector); маршруты программируются BGP'ом, минуя стрипаемый
механизм → блокер обойдён. Это также **prod-тир** multi-AZ (design-doc §3.2 «Prod:
route-reflector → динамика, ECMP/BFD»), т.е. фундамент для multi-AZ inter-zone L3.

### Ground-truth (live `kind-kacho`, верифицировано 2026-06-12)

- kube-ovn **v1.16.1** (`docker.io/kubeovn/kube-ovn:v1.16.1`); kube-ovn-controller
  запущен с `--enable-ecmp=false` и `--enable-external-vpc=false`.
- Бинарь `kube-ovn-speaker` **ЕСТЬ** в образе (`/kube-ovn/kube-ovn-speaker` →
  симлинк на `/kube-ovn/kube-ovn-cmd`), но **speaker DaemonSet НЕ развёрнут** ни в
  одном namespace; chart `argo-apps/kube-ovn/` (values.kind.yaml) **не содержит**
  speaker/BGP-значений.
- Custom-VPC подсети существуют и материализуются (`netrpwd3nst6hyyhc7m9` /
  `netnqbfj22xqdjye5xtw`, kube-ovn Subnet `192.168.88.0/24` и др.); BGP-аннотаций на
  Subnet НЕТ. RR/BGP-peer на kind **отсутствует**.

### Подтверждённая механика kube-ovn-speaker (offic. доки kube-ovn, сверено с v1.16.1)

- **Развёртывание**: `kube-ovn-speaker` — **DaemonSet** на нодах, помеченных
  node-label `ovn.kubernetes.io/bgp=true` (gateway/speaker-ноды), из манифеста
  `speaker.yaml`.
- **Флаги speaker** (нормативный минимум этой фазы): `--neighbor-address` (адрес
  BGP-peer/RR), `--neighbor-as` (AS peer'а), `--cluster-as` (AS контейнерной сети),
  `--announce-cluster-ip` (анонсить ClusterIP-сервисы; **default false — НЕ включаем**),
  `--auth-password` (пароль BGP-peer), `--holdtime` (default 90с), `--graceful-restart`,
  `--ebgp-multihop`, `--passivemode`.
- **Opt-in анонса** — annotation **`ovn.kubernetes.io/bgp`** на **Subnet** (или Pod);
  значения: `true`/`cluster` → policy **Cluster** (default; CIDR анонсится со всех
  speaker'ов), `local` → policy **Local** (анонс только с нод, реально хостящих
  Pod'ы/IP); снятие — `ovn.kubernetes.io/bgp-`.
- **RR/peer обязателен** — анонсы нужно кому-то принимать (на kind RR нет → PoC сам
  поднимает RR-под).
- **Custom-VPC subnet-анонс** — официальные доки фокусируются на default-VPC
  (`ovn-cluster`); анонсируемость non-NAT подсетей **custom-VPC** через speaker **не
  задокументирована явно** → должна быть **эмпирически подтверждена на PoC-стенде**
  (см. S3, ключевой риск; при неподтверждении — задокументированное ограничение +
  follow-up).

Трассировка к требованиям — тег **[req: …]** у каждого сценария.

---

## Решения (нормативные для реализации)

**(A) Speaker-топология PoC (single-cluster).** Один speaker DaemonSet в kind-кластере
на нодах с label `ovn.kubernetes.io/bgp=true` (на single-node kind — control-plane-нода
является gateway-нодой). RR — **один под в kind** (GoBGP или BIRD), играет роль
BGP-peer/route-reflector. ASN-план — **private ASN** (RFC 6996, 64512–65534):
`cluster-as=65001` (speaker), `neighbor-as=65000` (RR). Конкретные значения —
инфра-конфиг (S5, security.md), не публичный контракт; в доке фиксируются как
**пример**, реализация берёт из config/secret.

**(B) Opt-in политика анонса.** Этой фазой — **always-on для Kachō-подсетей**: оператор
выставляет `ovn.kubernetes.io/bgp=cluster` на КАЖДОЙ материализуемой kube-ovn Subnet
(field-scoped аннотация, parity с уже-управляемыми label'ами). Policy `Cluster`
(не `local`) — детерминированный анонс CIDR без зависимости от размещения Pod'ов
(для inter-zone reachability подсети как таковой). Per-Kachō-field/policy-driven opt-in
(анонс только избранных подсетей) — **out-of-scope / future** (зафиксировано в «Не-цели»;
требует нового поля control-plane → отдельная под-фаза).

**(C) Замена staticRoutes.** RouteTable-маршруты вида «доставить этот subnet-CIDR в
маршрутизацию» (== multi-AZ remote-/18 reachability) реализуются **через BGP-анонс
подсети**, НЕ через `Vpc.spec.staticRoutes` (kube-ovn стрипает — #2). Произвольные
static-маршруты с явным next-hop, которые BGP не выражает (next-hop ≠ «анонсируй этот
CIDR»), — **out-of-scope этой фазы / задокументированы** как ограничение (см. S3-07,
«Не-цели» п.4). OP2-P2-механизм `Vpc.staticRoutes` остаётся в коде, но помечается как
**неработающий на v1.16.1** (issue #2); этот док его не удаляет, а вводит BGP-путь
рядом.

**(D) PoC-first → multi-AZ follow-on.** S1–S5 — **single-cluster PoC** (speaker + RR в
одном kind-kacho; оператор аннотирует одну подсеть `192.168.88.0/24`; RR УЧИТ этот
CIDR по BGP — маршрут **персистит**, не стрипается). Multi-AZ (3 кластера, каждый
speaker → общий RR, cross-zone /18 учится) — **отдельная follow-on стадия S6**
(описана как scope, реализация — за рамками первого PR; gated на §4-решения design-doc).

**(E) BGP — новое data-plane ребро.** `kube-ovn-speaker ↔ RR` — отдельный data-plane
канал (BGP/TCP-179), **вне gRPC mTLS-mesh** Kachō (SEC-G mTLS — только на gRPC-рёбрах
operator→{vpc,iam}). BGP-аутентификация — отдельный механизм (`--auth-password` /
TCP-MD5), фиксируется в «Безопасность» (S5). Ребро документируется в vault
(`edges/kube-ovn-to-bgp-fabric.md`).

---

## Стадии

OP2-P-BGP — самостоятельный end-to-end deliverable, 5 стадий (PoC single-cluster) +
описанная follow-on стадия S6 (multi-AZ). Порядок merge: kube-ovn values/speaker →
RR-под → operator-аннотация → live-verify → security/trail.

- **S1** — Deploy `kube-ovn-speaker` (DaemonSet, `kacho-deploy/argo-apps/kube-ovn` /
  новый манифест): gateway-node placement (node-label), config (neighbor=RR, cluster-as,
  БЕЗ announce-cluster-ip), kind-dev-safe. **Speaker сам по себе НЕ анонсит** ничего,
  пока на подсети нет аннотации.
- **S2** — Route-reflector / BGP-peer под на kind (GoBGP/BIRD): config, ASN, peering со
  speaker'ом; verification surface (как инспектировать learned routes). **BGP session
  Established** speaker↔RR.
- **S3** — Operator-интеграция: egress-reconciler выставляет `ovn.kubernetes.io/bgp`
  на каждую материализуемую kube-ovn Subnet (field-scoped, идемпотентно); снятие на
  prune. **CIDR подсети анонсится → RR УЧИТ → маршрут персистит** (ключевой результат:
  ≠ стрипается).
- **S4** — Negative/edge: speaker/RR недоступны → graceful (оператор не падает); снятие
  аннотации → withdraw; custom-VPC анонсируемость (подтвердить ИЛИ задокументировать
  ограничение).
- **S5** — Security (ASN/neighbor/auth-password — infra-sensitive, config/secret; mTLS
  perimeter note) + trail (vault edge/KAC) + регресс-гейты (OP1 Subnet-материализация
  не клоберится).
- **S6 (follow-on, scope-only)** — Multi-AZ: 3 kind, каждый speaker → общий RR,
  cross-zone /18 учится; gated на §4-решения design-doc. **В первом PR не реализуется.**

DoD каждой стадии: её PoC-сценарии верифицируемы на живом `kind-kacho`
(speaker+RR pods, BGP session, learned-route inspection); operator-аннотация —
envtest-testable. `go test ./... -race` + `golangci-lint run` зелёные для operator-кода.

---

## S1 — Deploy kube-ovn-speaker (DaemonSet, kind-dev-safe)

**Контекст (ground-truth):** бинарь `kube-ovn-speaker` уже в образе v1.16.1; DS не
развёрнут; `argo-apps/kube-ovn/values.kind.yaml` без BGP-секции. speaker — DaemonSet на
нодах с label `ovn.kubernetes.io/bgp=true`.

### Сценарий BGP-S1-01: speaker DaemonSet развёрнут на gateway-ноде (happy) [req: speaker-deploy]

**ID:** OP2-P-BGP-S1-01

**Given** kind-кластер `kind-kacho` с kube-ovn v1.16.1 (speaker-бинарь в образе)
**And** нода(ы) помечены node-label `ovn.kubernetes.io/bgp=true` (на single-node kind — control-plane-нода; gateway-роль)
**And** manifest speaker (DaemonSet) добавлен в `kacho-deploy` (`argo-apps/kube-ovn/` values/манифест) с nodeSelector `ovn.kubernetes.io/bgp=true`

**When** применяется deploy (`make dev-up` / argo sync)

**Then** DaemonSet `kube-ovn-speaker` создаётся, под(ы) `Running 1/1` **только** на нодах с label `ovn.kubernetes.io/bgp=true` (на непомеченных нодах — нет пода)
**And** speaker запущен с флагами: `--neighbor-address=<RR-IP>`, `--neighbor-as=<RR-AS>`, `--cluster-as=<cluster-AS>`, `--announce-cluster-ip=false` (ClusterIP-сервисы НЕ анонсятся)
**And** verify: `kubectl -n <ovn-ns> get ds kube-ovn-speaker` → desired==ready на gateway-нодах; `kubectl logs ds/kube-ovn-speaker` без crash/panic

### Сценарий BGP-S1-02: speaker без аннотированных подсетей ничего не анонсит (edge, baseline) [req: speaker-deploy][req: opt-in]

**ID:** OP2-P-BGP-S1-02

**Given** speaker DaemonSet `Running`, RR доступен (S2)
**And** ни на одной kube-ovn Subnet НЕТ аннотации `ovn.kubernetes.io/bgp`

**When** speaker устанавливает BGP-сессию и работает в стабильном состоянии

**Then** RR **не учит** ни одного Kachō subnet-CIDR (анонс — opt-in по аннотации, baseline нулевой)
**And** verify: на RR (`gobgp global rib` / BIRD `show route`) нет 192.168.x маршрутов из кластера

### Сценарий BGP-S1-03: deploy kind-dev-safe — не ломает существующий datapath (regression) [req: speaker-deploy][req: non-goal]

**ID:** OP2-P-BGP-S1-03

**Given** существующая kube-ovn материализация OP1 работает (custom-VPC Subnet + NAD; под получает secondary NIC)
**And** speaker DaemonSet добавляется БЕЗ изменения kube-ovn-controller флагов, ломающих datapath (не флипаем `ENABLE_NAT_GW`/underlay без отдельного гейта; `--enable-external-vpc` остаётся как было, если анонс custom-VPC того не требует — см. S4-03)

**When** speaker развёрнут

**Then** существующие kube-ovn Subnet/NAD/Vpc не затронуты; под с secondary NIC по-прежнему получает Kachō-IP (datapath OP1 цел)
**And** kube-ovn-controller / cni-server не уходят в restart-loop из-за speaker
**And** deploy таргетит ТОЛЬКО `kind-*` контекст (kind-dev-safe; `k8s-operator-workflow` safety — отказ на non-kind)

---

## S2 — Route-reflector / BGP-peer на kind (verification surface)

**Контекст:** на kind нет upstream-роутера/RR → PoC сам поднимает BGP-peer-под (GoBGP
или BIRD), с которым speaker пирится. RR — точка проверки «маршрут выучен / персистит».

### Сценарий BGP-S2-01: RR-под поднят и пирится со speaker — session Established (happy, КЛЮЧЕВОЙ) [req: rr-peer]

**ID:** OP2-P-BGP-S2-01

**Given** RR-под (GoBGP/BIRD) развёрнут в kind (`kacho-deploy` манифест) с конфигом: локальный `as=<RR-AS>` (например 65000), accept-peer от speaker-нод, `router-id` стабилен
**And** speaker сконфигурён `--neighbor-address=<RR-IP-pod-или-svc>`, `--neighbor-as=<RR-AS>`, `--cluster-as=<cluster-AS>` (например 65001), при необходимости `--auth-password=<...>` совпадает с RR

**When** speaker и RR стартуют и устанавливают сессию

**Then** BGP-сессия speaker↔RR в состоянии **Established** (verify на RR: `gobgp neighbor` → `State: Established`; на speaker — лог `peer ... state ESTABLISHED` / без flapping)
**And** ASN — private (RFC 6996 64512–65534); router-id'ы уникальны; auth (если задан) совпадает обеими сторонами
**And** verification surface зафиксирована: команда инспекции learned routes на RR (`gobgp global rib` / BIRD `birdc show route`) документирована в `kacho-deploy` (PoC-runbook)

### Сценарий BGP-S2-02: auth mismatch / неверный neighbor → session НЕ Established (negative) [req: rr-peer][req: security]

**ID:** OP2-P-BGP-S2-02

**Given** speaker `--auth-password` НЕ совпадает с паролем RR (или `--neighbor-as` неверен)

**When** speaker пытается установить сессию

**Then** BGP-сессия НЕ переходит в Established (peer не аутентифицирован / AS-mismatch) — fail-closed: без валидной сессии анонсы не доставляются
**And** speaker НЕ падает (под `Running`, лог отражает попытки/ошибку peering) — graceful, retry с backoff
**And** assert: маршруты НЕ учатся RR при не-Established сессии (нет утечки анонса в незаконного peer'а)

---

## S3 — Operator-интеграция: BGP-advertise аннотация на kube-ovn Subnet

**Контекст (recon):** egress-reconciler `KachoSubnetReconciler.applySubnet`
(`internal/controller/kachosubnet_controller.go`) уже **field-scoped** управляет
spec-ключами kube-ovn Subnet (`protocol/cidrBlock/gateway/excludeIps/provider/vpc`) и
label'ами (`mergeLabels`, идемпотентно, без spurious update). Эта фаза добавляет
**управляемую аннотацию** `ovn.kubernetes.io/bgp` на ту же Subnet — тем же
field-scoped/идемпотентным механизмом (merge только своего ключа, не клобер чужих
аннотаций/kube-ovn-дефолтов). Shared-логика — `internal/kubeovn` (drift-prevention,
design-doc §1 «drift = корень бага #1»).

### Сценарий BGP-S3-01: материализуемая Subnet получает BGP-advertise аннотацию (happy) [req: operator-annotation]

**ID:** OP2-P-BGP-S3-01

**Given** KachoSubnet `<sub-id>` (`networkId=<nid>`, CIDR `192.168.88.0/24`) — материализуется egress'ом в kube-ovn Subnet (OP1)

**When** egress-Reconciler реконсайлит `<sub-id>`

**Then** на kube-ovn Subnet `<sub-id>-<cidrhash>` присутствует аннотация `ovn.kubernetes.io/bgp=cluster` (always-on policy Cluster — решение B)
**And** аннотация выставлена **merge'ом** (field-scoped): прочие аннотации Subnet (kube-ovn-дефолты, прочие managed) НЕ затронуты
**And** управляемые spec-ключи Subnet (`cidrBlock/gateway/provider/vpc/...`) и label'ы OP1 — без изменений (BGP-аннотация — аддитивна)
**And** `KachoSubnet.status` остаётся `Ready=True/Reconciled` (аннотация — часть штатной материализации, не отдельный degraded-путь)

### Сценарий BGP-S3-02: идемпотентность аннотации — нет spurious write (positive) [req: operator-annotation][req: idempotency]

**ID:** OP2-P-BGP-S3-02

**Given** kube-ovn Subnet `<sub-id>-<cidrhash>` уже несёт `ovn.kubernetes.io/bgp=cluster`

**When** egress реконсайлит повторно (periodic resync, без изменений spec)

**Then** Subnet НЕ получает write по причине аннотации (значение уже желаемое → no-op, parity с `mergeLabels`/`specEqual` OP1)
**And** число/состав аннотаций стабильны между прогонами; чужие аннотации не «дёргаются»

### Сценарий BGP-S3-03: анонсированный CIDR выучен RR и ПЕРСИСТИТ ≠ стрипается (happy, ГЛАВНЫЙ результат фазы) [req: bgp-advertise][req: replaces-staticroutes]

**ID:** OP2-P-BGP-S3-03

**Given** speaker DS `Running`, BGP-сессия speaker↔RR Established (S2-01)
**And** оператор выставил `ovn.kubernetes.io/bgp=cluster` на kube-ovn Subnet `192.168.88.0/24` (S3-01)

**When** speaker подхватывает аннотацию и анонсирует CIDR подсети в BGP-фабрику

**Then** RR **УЧИТ** маршрут `192.168.88.0/24` (verify на RR: `gobgp global rib` / BIRD `show route` содержит `192.168.88.0/24` с next-hop = speaker/gateway-нода)
**And** **маршрут ПЕРСИСТИТ** (не исчезает за ~1-5с) — в отличие от `Vpc.spec.staticRoutes`, которые kube-ovn стрипает (#2): BGP-путь обходит блокер
**And** assert (контраст с #2): параллельная попытка добавить тот же маршрут через `Vpc.spec.staticRoutes` по-прежнему стрипается ~1-5с (демонстрирует, ЗАЧЕМ BGP), а BGP-выученный маршрут — стабилен (это и есть замена staticRoutes)
**And** verify повторно через ≥30с: маршрут всё ещё в RIB RR (стабильность, не транзиент)

### Сценарий BGP-S3-04: снятие аннотации на prune → анонс withdrawn (happy) [req: operator-annotation][req: withdraw]

**ID:** OP2-P-BGP-S3-04

**Given** kube-ovn Subnet `192.168.88.0/24` с `ovn.kubernetes.io/bgp=cluster`, CIDR выучен RR (S3-03)
**And** Kachō Subnet / её CIDR удаляется ИЛИ KachoSubnet прунит этот child (OP1 element-prune / teardown)

**When** egress удаляет kube-ovn Subnet (prune) — аннотация уходит вместе с объектом; ЛИБО (если subnet остаётся, но анонс должен сняться) оператор снимает аннотацию `ovn.kubernetes.io/bgp-`

**Then** speaker **withdraw**'ит анонс; RR удаляет `192.168.88.0/24` из RIB (verify: маршрут исчез из `gobgp global rib`)
**And** assert: при удалении самой Subnet анонс снимается автоматически (нет объекта → нечего анонсить); явный `ovn.kubernetes.io/bgp-` нужен ТОЛЬКО если Subnet остаётся, а анонс должен прекратиться (документировать как clean-up-семантику)
**And** prune не оставляет «висячего» анонса (no dangling route в RR после teardown)

### Сценарий BGP-S3-05: аннотация — единый источник в shared kubeovn-хелпере (edge, drift-prevention) [req: operator-annotation][req: non-goal]

**ID:** OP2-P-BGP-S3-05

**Given** ключ аннотации `ovn.kubernetes.io/bgp` + значение `cluster` нужны egress-reconciler'у (и потенциально webhook/multi-AZ-логике)

**When** реализуется выставление аннотации

**Then** ключ/значение и логика merge — в **shared `internal/kubeovn`** (как `LabelManagedBy`/`Provider`/`ChildName`), НЕ хардкод-дубль в reconciler (drift = корень #1)
**And** аннотация выставляется тем же field-scoped merge-примитивом, что и label'ы OP1 (no whole-metadata replace — иначе клобер kube-ovn-дефолтов/чужих аннотаций)

---

## S4 — Negative / edge / устойчивость

### Сценарий BGP-S4-01: RR недоступен → speaker graceful, оператор НЕ падает (negative, КЛЮЧЕВОЙ) [req: graceful][req: bgp-advertise]

**ID:** OP2-P-BGP-S4-01

**Given** speaker DS `Running`, Subnet аннотирована `ovn.kubernetes.io/bgp=cluster`
**And** RR-под **удалён / недоступен** (BGP-сессия рвётся)

**When** система работает в этом состоянии

**Then** speaker НЕ падает (под `Running`); пытается переустановить сессию с backoff; `--graceful-restart` (если включён) сглаживает реконнект
**And** **kacho-vpc-operator НЕ падает и НЕ деградирует** из-за недоступности RR (оператор управляет аннотацией на kube-ovn Subnet — это k8s-API-операция, не зависит от BGP-сессии; BGP — забота speaker'а, оператор его не дёргает)
**And** материализация OP1 (Subnet/NAD/Vpc) и существующий datapath — НЕ затронуты падением BGP-фабрики
**And** при восстановлении RR — сессия переустанавливается, ранее-аннотированные CIDR **повторно учатся** RR без ручного вмешательства (self-heal через speaker re-announce)

### Сценарий BGP-S4-02: speaker DS down → оператор и datapath не ломаются (negative) [req: graceful][req: non-goal]

**ID:** OP2-P-BGP-S4-02

**Given** speaker DaemonSet удалён / поды speaker не `Running`
**And** kube-ovn Subnet несут аннотацию `ovn.kubernetes.io/bgp=cluster`

**When** оператор реконсайлит и материализует подсети

**Then** оператор продолжает штатно (выставляет/держит аннотацию на Subnet — это просто metadata; отсутствие speaker'а не ошибка для оператора)
**And** CIDR'ы НЕ анонсятся (нет speaker'а — некому), RR ничего не учит — это **ожидаемая деградация** маршрутизации, не сбой оператора
**And** existing OP1 datapath (secondary NIC, intra-zone) цел; inter-zone L3 деградирован до восстановления speaker'а
**And** при возврате speaker'а — анонсы возобновляются (аннотации на месте → speaker подхватывает)

### Сценарий BGP-S4-03: custom-VPC subnet анонсируемость — подтвердить ИЛИ задокументировать ограничение (edge, ГЛАВНЫЙ РИСК) [req: custom-vpc-advertise]

**ID:** OP2-P-BGP-S4-03

**Given** Kachō кладёт каждую Network в **custom-VPC** (`kacho-<net-id>`), НЕ в default `ovn-cluster` (design-doc §3.1)
**And** офиц. доки kube-ovn явно НЕ подтверждают анонс non-NAT подсетей custom-VPC через speaker (ground-truth выше)

**When** на custom-VPC kube-ovn Subnet выставлена `ovn.kubernetes.io/bgp=cluster` и speaker работает (S3-03)

**Then** на PoC-стенде **эмпирически проверяется**: учит ли RR CIDR custom-VPC подсети
**And** ИСХОД A (анонс работает): custom-VPC subnet-CIDR выучен RR и персистит → BGP-путь валиден для Kachō-топологии (фиксируется как verified в trail/runbook)
**And** ИСХОД B (анонс НЕ работает для custom-VPC): фиксируется как **задокументированное ограничение** kube-ovn v1.16.1 + GitHub Issue (`bug`/`tech-debt`, blocked:kube-ovn) + варианты обхода (флаг `--enable-external-vpc=true` для speaker'а; либо placement подсетей; либо version-bump kube-ovn) — БЕЗ молчаливого no-op; multi-AZ (S6) gated на разрешение этого пункта
**And** assert: какой бы ни был исход — он **верифицирован на живом стенде** (не предположение); решение по обходу не меняет публичный контракт Kachō

### Сценарий BGP-S4-04: announce-cluster-ip выключен — ClusterIP-сервисы НЕ утекают (negative/security) [req: speaker-deploy][req: security]

**ID:** OP2-P-BGP-S4-04

**Given** speaker `--announce-cluster-ip=false` (default; решение A)

**When** speaker анонсит Kachō subnet-CIDR'ы

**Then** RR учит ТОЛЬКО subnet-CIDR'ы аннотированных Kachō-подсетей; **НЕ** учит k8s ClusterIP-сервисные CIDR (`10.96.0.0/16` / `SVC_CIDR`)
**And** assert: BGP-поверхность минимальна (subnet-CIDR подсетей tenant'а), не утекает инфра-сервисная адресация в фабрику (least-exposure, security.md)

---

## S5 — Безопасность (infra-sensitive config) + регресс + trail

### Сценарий BGP-S5-01: ASN/neighbor/auth-password — infra-sensitive, в config/secret, не в публичном API (security, КЛЮЧЕВОЙ) [req: security]

**ID:** OP2-P-BGP-S5-01

**Given** speaker/RR требуют ASN (`cluster-as`/`neighbor-as`), `neighbor-address`, `auth-password`

**When** конфигурируется deploy

**Then** `auth-password` — в **k8s Secret** (не plaintext в values/манифесте, не в git-committed файл); ASN/neighbor-address — в config (kube-ovn values / speaker-config), **НЕ** на публичной поверхности Kachō-ресурсов
**And** эти данные классифицируются как **infra-sensitive** (underlay/транспорт — security.md): не попадают в публичный gRPC/REST-ответ ни одного Kachō-ресурса (Subnet/Network/RouteTable публично показывают только tenant-intent: id/name/CIDR/привязки/status — НЕ BGP/ASN/next-hop/speaker-placement)
**And** assert: `grep` по публичным proto/JSON-ответам не выявляет ASN/neighbor/peer/auth-полей (BGP-механика невидима tenant'у; при необходимости admin-видимости — ТОЛЬКО Internal*-API, не публичный)
**And** vault/secret-discipline: пароль НЕ коммитится в `obsidian/`/docs/манифесты (vault.md запрет секретов)

### Сценарий BGP-S5-02: BGP-ребро вне gRPC mTLS-mesh — задокументировано (security/note) [req: security][req: mtls-perimeter]

**ID:** OP2-P-BGP-S5-02

**Given** SEC-G: gRPC-рёбра operator→{vpc,iam} — mTLS; BGP `speaker↔RR` — отдельный data-plane канал (TCP-179)

**When** документируется периметр безопасности

**Then** зафиксировано: BGP (`kube-ovn-speaker ↔ RR`) — **новое data-plane ребро ВНЕ mTLS-mesh** (mTLS — только gRPC; SEC-G явно «operator→kube-ovn/multus — вне mTLS-периметра»); его аутентификация — BGP TCP-MD5 / `--auth-password`, не mTLS
**And** ребро зафиксировано в vault `obsidian/kacho/edges/kube-ovn-to-bgp-fabric.md` (protocol BGP/TCP-179, sync/async, auth, история с KAC-номером)
**And** assert: BGP-ребро НЕ создаёт нового gRPC service→service вызова (не цикл, не новый build-edge — чисто data-plane, polyrepo.md)

### Сценарий BGP-S5-03: OP1 Subnet-материализация / mTLS / ns-operator не регрессируют (regression) [req: non-goal]

**ID:** OP2-P-BGP-S5-03

**Given** OP1 egress материализует Subnet→child Subnet+NAD (field-scoped apply, in-use guard, finalizer); SEC-G mTLS dial; ns-operator

**When** добавляется BGP-аннотация на Subnet + speaker/RR deploy

**Then** OP1-материализация неизменна по поведению (BGP-аннотация — аддитивный managed-ключ metadata; in-use guard / element-prune / finalizer — без изменений)
**And** mTLS dial (operator→{vpc,iam}) / FGA-viewer / ns-operator (namespace-lifecycle) — без регресса
**And** shared `internal/kubeovn` переиспользуется (BGP-ключ — там же, где label/naming), без drift
**And** существующие envtest/operator-тесты остаются зелёными; новый envtest на BGP-аннотацию — зелёный (S3-01/02)

### Сценарий BGP-S5-04: CRD/RBAC/deploy install + multi-AZ reuse-заметка + trail (setup/trail) [req: rbac][req: multi-az-reuse][req: vault]

**ID:** OP2-P-BGP-S5-04

**Given** speaker DS + RR-под + node-label требуют install в `kacho-deploy`; оператор требует RBAC update Subnet metadata (annotations — это update/patch на `kubeovn.io subnets`, уже есть в OP1 RBAC); design-doc §3.2 указывает BGP как prod-тир multi-AZ learn-side

**When** готовится реализация и развёртывание

**Then** speaker DaemonSet + RR-манифест + node-label-инструкция установлены в `kacho-deploy` (`argo-apps/kube-ovn/` + PoC-runbook с командами verify learned routes); kind-dev-safe
**And** RBAC оператора достаточен: update/patch `kubeovn.io subnets` (для аннотации) — без новых лишних verb'ов (OP1 уже даёт subnets update/patch; node-label — out-of-band deploy-операция, НЕ из reconcile; оператор НЕ метит ноды)
**And** установка не ломает существующий deploy (OP1 datapath, mTLS/SA/webhook — S5-03 без регресса)
**And** реализация выносит BGP-аннотацию в переиспользуемый `internal/kubeovn`-хелпер → multi-AZ (S6) reuse'ит тот же механизм (design-doc §3.2 «дорожки сходятся»: BGP-анонс подсети = learn-side custom-VPC), без копипасты
**And** `obsidian/kacho/edges/vpc-operator-to-kubeovn.md` обновлён: новый egress-аспект (BGP-аннотация на kube-ovn Subnet) + запись в «История» с KAC-номером + ссылка на issue #2 (почему BGP вместо staticRoutes)
**And** создана `obsidian/kacho/edges/kube-ovn-to-bgp-fabric.md` (новое data-plane ребро) + создан/обновлён KAC-trail `obsidian/kacho/KAC/KAC-<N>.md`

---

## S6 — Multi-AZ (follow-on, scope-only; в первом PR НЕ реализуется)

> [!note] Stage-gate
> S6 — описание целевого scope multi-AZ, НЕ реализуемого в первом PR (PoC-first,
> решение D). Реализация gated на: (1) положительный исход custom-VPC анонса
> (BGP-S4-03 ИСХОД A) ИЛИ задокументированный обход; (2) продуктовые решения
> design-doc §4 (3-kind топология, supernet-нарезка, zone_id required/immutable,
> ASN-план). Когда снято — S6 раскрывается в собственный acceptance-док под-фазы.

### Сценарий BGP-S6-01: multi-AZ — каждый speaker зоны → общий RR, cross-zone /18 учится (scope) [req: multi-az]

**ID:** OP2-P-BGP-S6-01

**Given** 3 kind-кластера (zoneA/B/C) на общем docker-бридже `kind` (ноды взаимно достижимы, design-doc §3.6); один общий RR; в каждом кластере — speaker DS + zone-aware оператор (`KACHO_VPCOPERATOR_ZONE_ID`)
**And** каждая зона материализует свою подсеть (disjoint /18: zoneA `10.80.0.0/18`, zoneB `10.80.64.0/18`, zoneC `10.80.128.0/18`) с `ovn.kubernetes.io/bgp=cluster`

**When** speaker каждой зоны анонсит свой /18 в общий RR; RR (route-reflector) реанонсит остальным speaker'ам

**Then** каждая зона **учит remote /18** соседних зон по BGP (RR рефлектит); inter-zone L3: pod zoneA → custom-VPC LR → BGP-learned remote/18 → underlay(kind bridge) → peer-zone → pod (routed L3, без L2)
**And** маршруты **персистят** (BGP-программируемые, не стрипаемые Vpc.staticRoutes — обход #2 на multi-AZ-масштабе)
**And** zone-isolation: оператор каждой зоны материализует ТОЛЬКО свою подсеть (`zone_id==ZONE_ID`), но анонс/learn — общий через RR; replica-isolation (design-doc §3.5) сохранена
**And** gated: реализуется ТОЛЬКО после BGP-S4-03 ИСХОД A (или обхода) + §4-решений design-doc

---

## Тестовая стратегия

### envtest (operator-аннотация — детерминированно)

- **envtest (egress-controller)** — обязателен для S3:
  - материализуемая Subnet → несёт `ovn.kubernetes.io/bgp=cluster`, прочие аннотации/spec/label OP1 нетронуты (BGP-S3-01).
  - идемпотентность: повторный reconcile при уже-выставленной аннотации → no spurious write (BGP-S3-02).
  - prune/teardown: удаление Subnet → аннотация уходит с объектом; (опц.) явный `ovn.kubernetes.io/bgp-` снимает анонс при сохранённой Subnet (BGP-S3-04, метаданные-уровень).
  - shared-хелпер: ключ/значение из `internal/kubeovn`, field-scoped merge (BGP-S3-05).
  - регресс OP1: Subnet/NAD материализация, in-use guard, finalizer — зелёные (BGP-S5-03).
- **unit** — BGP-аннотация-builder (ключ/значение, merge-в-metadata без клобера), policy-выбор (`cluster`), через fake client.

> [!note] Граница envtest (явно зафиксировать)
> envtest НЕ запускает реальный speaker/kube-ovn-controller/BGP → проверяет ТОЛЬКО
> механику выставления/идемпотентности/снятия аннотации на kube-ovn Subnet. **Реальный
> анонс, learned-route на RR, персистентность (≠ стрип #2), custom-VPC анонсируемость,
> graceful при RR-down** — верифицируются **на живом `kind-kacho`** (S1–S4
> PoC-сценарии). Этот разрыв декларируется в DoD (как OP1 / OP2-P2 callouts).

### Live PoC-верификация на `kind-kacho` (обязательна — verifiable surface)

- speaker DS `Running` на gateway-ноде, флаги корректны (BGP-S1-01).
- RR-под `Running`, BGP-сессия Established (`gobgp neighbor`/BIRD), auth-mismatch → не Established (BGP-S2-01/02).
- аннотированная `192.168.88.0/24` → RR учит CIDR (`gobgp global rib`), **персистит ≥30с** (≠ staticRoutes-стрип #2) — ГЛАВНЫЙ результат (BGP-S3-03).
- снятие/prune → withdraw (маршрут исчез из RIB) (BGP-S3-04).
- RR down → speaker/operator graceful, restore → re-learn (BGP-S4-01); speaker down → datapath/operator целы (BGP-S4-02).
- custom-VPC анонс: эмпирический исход A/B зафиксирован (BGP-S4-03).
- `announce-cluster-ip=false`: SVC_CIDR не в RIB (BGP-S4-04).

### TDD

- Для каждого operator-сценария (S3, S5-03): падающий envtest/unit (RED по правильной
  причине — аннотации нет) ДО кода → GREEN; в отчёте пара RED→GREEN.
- Deploy/PoC-сценарии (S1/S2/S4-live) — verifiable runbook-шаги на живом стенде (не
  Go-тест; deploy-фаза), результат фиксируется в PR/RESULTS как live-verification.

### Финальная верификация

`go test ./... -race` + `golangci-lint run` зелёные (operator); envtest BGP-аннотация
зелёный; live PoC: speaker+RR Established, CIDR выучен+персистит, withdraw на prune,
graceful при RR/speaker-down — подтверждены на `kind-kacho` (как OP1/OP2-P2 live-чек).

---

## Не-цели (explicit non-goals)

1. **Контракт Kachō / proto НЕ меняется** — никаких новых RPC/полей; BGP — целиком
   data-plane (kube-ovn speaker ↔ RR), невидимый на публичной поверхности Kachō.
   Always-on анонс Kachō-подсетей (решение B) НЕ требует control-plane-поля.
2. **Per-subnet opt-in policy (анонс только избранных подсетей по Kachō-field) — OUT OF
   SCOPE / future** — потребует нового control-plane-поля → отдельная под-фаза. Эта фаза
   — always-on `cluster` для всех Kachō-подсетей.
3. **`Vpc.spec.staticRoutes` НЕ чиним и НЕ удаляем** — он остаётся в коде OP2-P2, но
   помечен неработающим на v1.16.1 (issue #2); BGP вводится **рядом** как рабочий путь
   доставки subnet-CIDR в маршрутизацию. Удаление/депрекейт staticRoutes-механизма —
   отдельное решение.
4. **Произвольные static-маршруты с явным next-hop (не «анонсируй CIDR») — вне scope** —
   BGP-анонс подсети выражает только «этот CIDR достижим через speaker-ноду(ы)».
   Маршруты с произвольным next-hop, не сводимые к subnet-advertise, BGP этой фазы не
   покрывает — задокументировано как ограничение (решение C; при необходимости —
   follow-up через BGP policy/route-policy, не в этом PR).
5. **announce-cluster-ip / EIP / NAT-GW BGP — НЕ включаем** — `--announce-cluster-ip=false`;
   EIP/external через BGP — gated на NAT-фазу P3/P4 (design-doc §2), вне scope.
6. **Multi-AZ (S6) НЕ реализуется в первом PR** — PoC single-cluster сначала (решение D);
   S6 — scope-only, gated на BGP-S4-03 ИСХОД A + §4-решения design-doc.
7. **kube-ovn-controller datapath-флаги (`ENABLE_NAT_GW`/underlay/`--enable-ecmp`) НЕ
   флипаем без отдельного гейта** — speaker добавляется аддитивно; изменение
   `--enable-external-vpc` (если потребуется для custom-VPC анонса, BGP-S4-03) —
   отдельное решение с регресс-проверкой datapath (BGP-S1-03).
8. **mTLS на BGP-ребро НЕ распространяется** — mTLS-mesh только для gRPC (SEC-G);
   BGP-auth — TCP-MD5/`--auth-password` (решение E, BGP-S5-02).

---

## Трассировка требований → сценарии

| Требование | Сценарии |
|---|---|
| speaker-deploy (DaemonSet, gateway-node, флаги, kind-dev-safe) | BGP-S1-01, BGP-S1-02, BGP-S1-03, BGP-S4-04 |
| opt-in анонса (always-on `cluster`, baseline без аннотации — тишина) | BGP-S1-02, BGP-S3-01 |
| rr-peer (RR-под, session Established, verification surface) | BGP-S2-01, BGP-S2-02 |
| operator-annotation (`ovn.kubernetes.io/bgp` field-scoped/идемпотентно, shared kubeovn) | BGP-S3-01, BGP-S3-02, BGP-S3-05 |
| bgp-advertise (CIDR выучен RR, персистит) | BGP-S3-03, BGP-S4-01 |
| replaces-staticroutes (BGP вместо стрипаемого Vpc.staticRoutes, #2) | BGP-S3-03 |
| withdraw (снятие аннотации/prune → анонс снят) | BGP-S3-04 |
| custom-vpc-advertise (эмпирический A/B исход, не предположение) | BGP-S4-03 |
| graceful (RR/speaker down → оператор+datapath целы, self-heal) | BGP-S4-01, BGP-S4-02 |
| security (auth-password secret, ASN/neighbor infra-sensitive, announce-cluster-ip=false) | BGP-S2-02, BGP-S4-04, BGP-S5-01 |
| mtls-perimeter (BGP-ребро вне gRPC mTLS, TCP-MD5) | BGP-S5-02 |
| non-goal: OP1/mTLS/ns-operator/datapath не регрессируют | BGP-S1-03, BGP-S4-02, BGP-S5-03 |
| rbac (subnets update/patch для аннотации; node-label out-of-band) | BGP-S5-04 |
| multi-az-reuse (BGP-анонс = learn-side; reusable хелпер) | BGP-S5-04, BGP-S6-01 |
| multi-az (3-kind, cross-zone /18, scope-only follow-on) | BGP-S6-01 |
| CRD/RBAC/deploy install + trail (vault edge/KAC) | BGP-S5-04 |
| idempotency (аннотация без spurious write) | BGP-S3-02 |
| ticket/branch binding (ban #1, pre-APPROVAL gate) | заголовок §«Привязка к тикету» |
