# Sub-phase OP2-P0 — kacho-vpc-operator NIC-attach webhook: correct per-CIDR NAD reference + dual-stack fixed-IP — Acceptance

> Статус: DRAFT
> Дата: 2026-06-12
> Ревьюер: acceptance-reviewer (gate перед кодом, ban #1)

### Привязка к тикету (ban #1 + git-youtrack — обязательна ДО APPROVED-for-code)

> [!important] Pre-APPROVAL gate
> Этот acceptance-док НЕ может быть APPROVED-for-code, пока поля ниже не заполнены
> **реальным** KAC-номером (не плейсхолдером). Заведение тикета и создание KAC-trail —
> последний шаг перед снятием gate, **не** часть acceptance-текста; номер присваивает
> orchestrator (владеет YouTrack-доступом).

| Поле | Значение |
|---|---|
| Subtask (этот док) | `KAC-<N>` `OP2-P0 — webhook per-CIDR NAD ref + dual-stack fixed-IP` |
| Ветка `kacho-vpc-operator` | `KAC-<N>` (от `main`) |
| GitHub Issue (root-cause) | `PRO-Robotech/kacho-vpc-operator#1` (закрывается этим фиксом) |
| Правка vault `kacho-workspace` | `obsidian/kacho/edges/vpc-operator-to-kubeovn.md` + `obsidian/kacho/KAC/KAC-<N>.md` (KAC-trail) |
| YouTrack | `https://prorobotech.youtrack.cloud/issue/KAC-<N>` |
| Роль исполнителя | `acceptance-author` (этот док) → реализация: domain-агенты `kacho-vpc-operator` |

> Затронутые репо: `kacho-vpc-operator` (код webhook + shared naming-пакет) **только**.
> Никаких изменений `kacho-proto` / `kacho-vpc` / `kacho-deploy` — webhook читает уже
> существующие RPC (`NetworkInterfaceService.Get`, `AddressService.Get`,
> `SubnetService.Get`) и существующие proto-поля.
> Зависит от: OP1 (KachoSubnet CRD redesign — egress материализует child NAD'ы как
> `childName(subnetID, canonical(cidr))`) — этот фикс приводит webhook в соответствие
> с тем именованием. SEC-G (operator→vpc mTLS dial + principal) — **не должно регрессировать**.

## Обзор

После OP1-редизайна egress-контур оператора материализует на КАЖДЫЙ CIDR сабнета
отдельную пару (kube-ovn Subnet + Multus NAD) с именем
`childName(subnetID, canonical(cidr))` = `<subnetID>-<cidrhash>` (`internal/controller/naming.go`,
`internal/controller/desired.go`). Pod-mutating-webhook
(`internal/webhook/v1/pod_webhook.go`) **остался** ссылаться на NAD по голому
`<subnetID>` и формировать provider-префикс mac/ip-аннотаций как `<subnetID>.<ns>.ovn`.
NAD с именем `<subnetID>` после OP1 не существует ни одного → secondary-NIC к kube-ovn
сети молча не подключается (`failurePolicy=ignore` → admission проходит, под стартует
без NIC). Это **issue `kacho-vpc-operator#1`** (латентный — подов с NIC ещё не было).

Эта подфаза приводит webhook в соответствие с per-CIDR именованием OP1:

1. **Корректная NAD-ссылка** — `k8s.v1.cni.cncf.io/networks` указывает на
   `childName(subnetID, canonical(CIDR-A))`, где CIDR-A — CIDR сабнета, СОДЕРЖАЩИЙ
   fixed-IP данного NIC (а не голый `<subnetID>`).
2. **Корректный provider-префикс** — ключи `mac_address`/`ip_address` строятся как
   `Provider(childName, ns)` = `<childName>.<ns>.ovn` (тот же child), не
   `<subnetID>.<ns>.ovn`.
3. **Dual-stack fixed-IP** — если у NIC есть и v4-, и v6-Address,
   `ip_address = <v4>,<v6>`, а NAD/provider резолвятся по child'у CIDR каждой семьи.
4. **CIDR-resolution + fallback** — детерминированное определение CIDR-A через
   IP-in-prefix membership по списку CIDR сабнета; чётко определённое поведение, когда
   у NIC нет Address.
5. **Единый naming-контракт** — `childName`/`canonicalCIDR` переезжают в shared-пакет
   (`internal/kubeovn`), webhook и egress-контроллер используют ОДНУ функцию (drift был
   корнем #1).
6. **Сохранение guard'ов** — существующие cross-tenant guard'ы не меняются.

Трассировка к требованиям дана у каждого сценария тегом **[req: …]**.

---

## Ground-truth контракт (recon — нормативно для сценариев)

Существующие, уже доступные операторскому коду факты (не предполагать иное):

- **NIC → fixed-IP (v4)**: `NetworkInterface.v4_address_ids[0]` → `AddressService.Get`
  → `Address.internal_ipv4.address`. v6-аналог: `v6_address_ids[0]` →
  `Address.internal_ipv6.address`. (proto-getter'ы `GetV4AddressIds()`,
  `GetV6AddressIds()`, `GetInternalIpv4Address().GetAddress()`,
  `GetInternalIpv6Address().GetAddress()` существуют.)
- **Address знает свой сабнет, но НЕ свой CIDR**: `Address.internal_ipv4.subnet_id`
  (и `internal_ipv6.subnet_id`) — это id сабнета, не CIDR. Сам CIDR-блок в Address не
  хранится. Поэтому CIDR-A определяется как тот CIDR из списка сабнета, в который
  **попадает** IP адреса (IP-in-prefix membership).
- **Список CIDR сабнета**: `SubnetService.Get(subnetId)` → `Subnet.v4_cidr_blocks[]` +
  `Subnet.v6_cidr_blocks[]` (getter'ы `GetV4CidrBlocks()`, `GetV6CidrBlocks()`
  существуют; RPC `SubnetService.Get` доступен в proto). Сабнет может иметь несколько
  CIDR на семью; OP1 материализует по child'у на каждый CIDR (single-family).
- **Shared kube-ovn helpers** уже в `internal/kubeovn`: `Provider(name, ns)`
  (`<name>.<ns>.ovn`), `VpcNameFor`, `FirstUsableIP`, `NADConfig`. `childName`/
  `canonicalCIDR`/`shortHash` СЕЙЧАС в `internal/controller/naming.go` — должны
  переехать в `internal/kubeovn` (S0), чтобы webhook и egress звали идентичную функцию.
- **Webhook DI**: `PodCustomDefaulter{Resolver: NetworkInterfaceServiceClient,
  AddrResolver: AddressServiceClient}`. Добавляется третий resolver —
  `SubnetServiceClient` (для чтения CIDR-списка) — DI из `cmd/.../main.go`,
  замокиваемый в envtest/unit fake.
- **failurePolicy=ignore** — admission НЕ блокирует под при ошибке webhook'а. Значит
  любой «reject» = молчаливый под-без-NIC. Это диктует выбор fallback-семантики (см.
  S5 §обоснование) и требование **логировать + emit Event/condition** на degraded-путях.
- **Текущие guard'ы (не менять)**: `projectID`(из ключа) == `pod.Namespace`; резолвленный
  NIC обязан реально быть в `r.projectID` (`nic.GetProjectId()`) и `r.subnetID`
  (`nic.GetSubnetId()`); иначе webhook возвращает ошибку (под отвергается на уровне
  webhook-логики, до patch'а).

---

## Стадии

OP2-P0 — самостоятельный end-to-end deliverable, дробится на 3 стадии (порядок merge):

- **S0** — shared naming: перенос `childName`/`canonicalCIDR`/`shortHash` в
  `internal/kubeovn`; egress-контроллер и webhook зовут ОДНУ функцию (no-duplicate).
- **S1** — webhook: корректная per-CIDR NAD-ссылка + provider-префикс для single-v4 NIC.
- **S2** — webhook: dual-stack fixed-IP + multi-NIC + CIDR-resolution/fallback/degraded
  edge-cases; сохранение guard'ов.

DoD каждой стадии — все её сценарии зелёные (TDD red→green), `go test ./... -race` +
`golangci-lint run` зелёные, envtest (webhook через fake NIC/Address/Subnet resolvers)
зелёный. Newman неприменим (data-plane operator, не публичный API через api-gateway) —
основная интеграционная инфра здесь envtest + unit с fake-resolver'ами.

---

## S0 — Shared naming-контракт (no-duplicate `childName`/`canonicalCIDR`)

### Сценарий S0-01: `childName`/`canonicalCIDR` живут в едином shared-пакете (positive) [req: shared-naming]

**ID:** OP2-P0-S0-01

**Given** функции `childName(base, cidr)`, `canonicalCIDR(cidr)`, `shortHash(canonical)`
сейчас определены в `internal/controller/naming.go` и используются только egress-контуром
**And** webhook (`internal/webhook/v1`) — отдельный пакет, который должен строить ТЕ ЖЕ имена

**When** проводится рефакторинг: эти функции экспортируются из `internal/kubeovn`
(напр. `kubeovn.ChildName`, `kubeovn.CanonicalCIDR`)

**Then** существует РОВНО одна реализация `childName`/`canonicalCIDR`/`shortHash`
(`grep` по `internal/` показывает один источник — в `internal/kubeovn`; дублирующих
определений в `internal/controller` и `internal/webhook` нет)
**And** egress-контур (`internal/controller/desired.go`) зовёт shared-функцию (его
поведение и порождаемые имена child'ов НЕ меняются — те же имена, что до рефакторинга)
**And** webhook зовёт ту же shared-функцию (идентичный результат для тех же входов)

### Сценарий S0-02: shared `ChildName` детерминирован и каноникализует CIDR (positive) [req: shared-naming]

**ID:** OP2-P0-S0-02

**Given** shared `kubeovn.ChildName(base, cidr)`

**When** на вход подаются семантически-эквивалентные текстовые формы одного префикса
(например `192.168.88.7/24` и `192.168.88.0/24`) при одинаковом `base`

**Then** обе формы дают ОДНО имя `<base>-<shorthash(canonical)>` (внутренняя
каноникализация `netip.ParsePrefix(cidr).Masked().String()` до хеширования)
**And** имя стабильно между вызовами (детерминизм) и ≤ 63 символов (DNS-label bound;
при превышении усекается `base`, хеш-суффикс полной ширины сохраняется) — поведение
эквивалентно текущему egress-контракту (OP1 S3-02a), webhook получает ИМЕННО его

### Сценарий S0-03: egress-регрессия после переноса (regression) [req: shared-naming][req: non-goal]

**ID:** OP2-P0-S0-03

**Given** egress envtest из OP1 (KachoSubnet → N child'ов со stable-by-CIDR именами)

**When** прогон полного теста репо после переноса функций в `internal/kubeovn`

**Then** все OP1 egress-сценарии остаются зелёными — имена child'ов идентичны
(перенос — чистый рефактор, без изменения сигнатуры результата)
**And** `go test ./... -race` + `golangci-lint run` зелёные

---

## S1 — Корректная per-CIDR NAD-ссылка + provider-префикс (single-v4 NIC)

**Контекст (recon):** `Default(...)` для каждого распарсенного `nicRef` сейчас делает
`networkRefs = append(networkRefs, r.subnetID)` и
`provider := r.subnetID + "." + pod.Namespace + ".ovn"`. Обе строки — баг #1. Фикс:
резолвить fixed-IP NIC'а → найти CIDR-A (содержащий IP) через `SubnetService.Get` →
`childName(subnetID, canonical(CIDR-A))` для NAD-ссылки И для provider-префикса.

### Сценарий S1-01: single-v4 NIC → networks = childName CIDR-A (happy, КЛЮЧЕВОЙ) [req: nad-ref][req: cidr-resolution]

**ID:** OP2-P0-S1-01

**Given** project-namespace `<ns>` (== projectID `<pid>`), под с аннотацией
`<sid>.<pid>.kacho.io/nic: <nicID>`
**And** `NetworkInterfaceService.Get(<nicID>)` → NIC c `projectId=<pid>`, `subnetId=<sid>`,
`macAddress=fa:16:3e:aa:bb:cc`, `v4AddressIds=[<addrID>]`, `v6AddressIds=[]`
**And** `AddressService.Get(<addrID>)` → `internal_ipv4.address = 192.168.89.42`,
`internal_ipv4.subnet_id = <sid>`
**And** `SubnetService.Get(<sid>)` → `v4CidrBlocks=[192.168.88.0/24, 192.168.89.0/24]`, `v6CidrBlocks=[]`
**And** CIDR-A = `192.168.89.0/24` (единственный CIDR, содержащий `192.168.89.42`)

**When** admission-webhook мутирует под (`Default`)

**Then** `pod.Annotations["k8s.v1.cni.cncf.io/networks"] == kubeovn.ChildName(<sid>, "192.168.89.0/24")`
(= `<sid>-<hash(192.168.89.0/24)>`), а **НЕ** голый `<sid>`
**And** это имя совпадает с именем NAD, который egress-контур материализовал для CIDR
`192.168.89.0/24` того же сабнета (один и тот же `ChildName` → matched NAD существует)
**And** провайдер-ключи mac/ip строятся по тому же child (S1-02)

### Сценарий S1-02: provider-префикс mac/ip = childName, не bare subnet (happy, КЛЮЧЕВОЙ) [req: provider-prefix]

**ID:** OP2-P0-S1-02

**Given** условия S1-01 (CIDR-A = `192.168.89.0/24`, `childA = ChildName(<sid>, "192.168.89.0/24")`)

**When** webhook мутирует под

**Then** ключ MAC-аннотации = `kubeovn.Provider(childA, <ns>) + ".kubernetes.io/mac_address"`
= `<childA>.<ns>.ovn.kubernetes.io/mac_address`, значение `fa:16:3e:aa:bb:cc`
**And** ключ IP-аннотации = `<childA>.<ns>.ovn.kubernetes.io/ip_address`, значение `192.168.89.42`
**And** НИ ОДНА аннотация не использует bare-провайдер `<sid>.<ns>.ovn.*` (assert:
ключей с префиксом `<sid>.<ns>.ovn.kubernetes.io/` в поде нет — есть только `<childA>.<ns>.ovn.*`)
**And** provider-строка для mac и для ip — ИДЕНТИЧНА (один и тот же `childA`, один порт)

### Сценарий S1-03: первый CIDR не содержит IP → выбирается правильный CIDR (positive) [req: cidr-resolution]

**ID:** OP2-P0-S1-03

**Given** NIC с fixed-IP `192.168.88.7`, `SubnetService.Get(<sid>)` →
`v4CidrBlocks=[192.168.89.0/24, 192.168.88.0/24]` (порядок: содержащий CIDR — НЕ первый)

**When** webhook резолвит CIDR-A

**Then** CIDR-A = `192.168.88.0/24` (IP-in-prefix membership, а НЕ «первый в списке»)
**And** `networks` = `ChildName(<sid>, "192.168.88.0/24")`, provider — соответствующий child
**And** результат не зависит от порядка CIDR в списке сабнета (детерминирован по содержимому IP)

### Сценарий S1-04: idempotency повторного admission (positive) [req: idempotency]

**ID:** OP2-P0-S1-04

**Given** под уже однажды промутирован webhook'ом (аннотации `networks`/mac/ip проставлены)

**When** admission срабатывает повторно (UPDATE того же пода, те же resolver-ответы)

**Then** значения аннотаций перезаписываются в ТЕ ЖЕ значения (идемпотентно — no drift,
повторный прогон детерминирован)
**And** не появляется дублирующих/устаревших bare-`<sid>.<ns>.ovn.*` ключей от прошлой
(забагованной) версии — если такой ключ присутствует во входном поде, webhook не обязан
его удалять, но **обязан** проставить корректный `<childA>.<ns>.ovn.*` ключ (новый
контракт — авторитетен; чистку legacy-ключей зафиксировать как explicit non-goal §не-цели)

### Сценарий S1-05: NIC без fixed-IP, сабнет с РОВНО одним CIDR → этот CIDR (edge) [req: cidr-resolution][req: fallback]

**ID:** OP2-P0-S1-05

**Given** NIC `<nicID>` с `v4AddressIds=[]` и `v6AddressIds=[]` (Address ещё не привязан)
**And** `SubnetService.Get(<sid>)` → `v4CidrBlocks=[192.168.88.0/24]`, `v6CidrBlocks=[]` (ровно один CIDR)

**When** webhook мутирует под

**Then** CIDR-A = `192.168.88.0/24` (единственный CIDR сабнета — однозначен без IP)
**And** `networks` = `ChildName(<sid>, "192.168.88.0/24")`, provider — соответствующий child
**And** IP-аннотация (`...ip_address`) **НЕ** проставляется (нет fixed-IP → kube-ovn IPAM
назначит адрес сам — текущее поведение `resolveFixedIP`→"" сохраняется)
**And** MAC-аннотация проставляется, если `nic.macAddress != ""` (как сейчас)

---

## S2 — Dual-stack fixed-IP, multi-NIC, fallback >1 CIDR, degraded edge-cases

### Сценарий S2-01: dual-stack NIC → ip_address = v4,v6, NAD'ы обеих семей (happy, КЛЮЧЕВОЙ) [req: dual-stack][req: nad-ref]

**ID:** OP2-P0-S2-01

**Given** NIC `<nicID>` c `v4AddressIds=[<a4>]`, `v6AddressIds=[<a6>]`
**And** `AddressService.Get(<a4>)` → `internal_ipv4.address = 10.0.0.5`;
`AddressService.Get(<a6>)` → `internal_ipv6.address = fd00::5`
**And** `SubnetService.Get(<sid>)` → `v4CidrBlocks=[10.0.0.0/24]`, `v6CidrBlocks=[fd00::/64]`
**And** OP1 — single-family-per-CIDR: v4-CIDR и v6-CIDR материализованы как РАЗНЫЕ child'ы:
`childV4 = ChildName(<sid>, "10.0.0.0/24")`, `childV6 = ChildName(<sid>, "fd00::/64")`

**When** webhook мутирует под

**Then** **определённое поведение dual-stack NIC (решение):** под ссылается на **ОБА**
child-NAD'а — `pod.Annotations["k8s.v1.cni.cncf.io/networks"]` содержит И `childV4`, И
`childV6` (две записи NAD в `networks` для одного dual-stack NIC, т.к. в OP1 v4 и v6 —
разные kube-ovn Subnet/NAD; иначе одна семья осталась бы без NAD и не подключилась)
**And** провайдер-ключи проставлены ДЛЯ КАЖДОЙ семьи:
`<childV4>.<ns>.ovn.kubernetes.io/ip_address = 10.0.0.5` и
`<childV6>.<ns>.ovn.kubernetes.io/ip_address = fd00::5`
**And** MAC-аннотация (если задан `nic.macAddress`) проставлена для **каждого** child-провайдера
(`<childV4>.<ns>.ovn.*/mac_address` и `<childV6>.<ns>.ovn.*/mac_address` — одинаковый MAC,
по порту на семью)
**And** deterministic order записей в `networks` (стабильный порядок: сначала v4-child,
затем v6-child — фиксированный, воспроизводимый между прогонами)

> [!note] Обоснование dual-stack-решения
> OP1 (решение A) делает v4 и v6 ОТДЕЛЬНЫМИ single-family child-Subnet/NAD'ами. Чтобы
> dual-stack NIC получил оба адреса, под обязан сослаться на ОБА NAD'а. Объединять их
> в одну `<provider>.kubernetes.io/ip_address = "v4,v6"` под одним bare-`<sid>` нельзя —
> такого NAD нет. Поэтому правило: per-family child-NAD + per-family provider-ключи.
> Combined-строка `v4,v6` НЕ используется (зеркалит OP1 «никакого v4,v6-combine»).

### Сценарий S2-02: multi-NIC, разные сабнеты → comma-joined правильные child'ы, детерминированный порядок (happy) [req: multi-nic][req: nad-ref]

**ID:** OP2-P0-S2-02

**Given** под с двумя ключами:
`<sidA>.<pid>.kacho.io/nic: <nicA>` и `<sidB>.<pid>.kacho.io/nic: <nicB>` (`<sidA> < <sidB>` лексикографически)
**And** `<nicA>` (v4-IP `192.168.90.91` ∈ CIDR `192.168.90.0/24` сабнета `<sidA>`),
`<nicB>` (v4-IP `192.168.88.157` ∈ CIDR `192.168.88.0/24` сабнета `<sidB>`)

**When** webhook мутирует под

**Then** `pod.Annotations["k8s.v1.cni.cncf.io/networks"]` = comma-join в
**детерминированном порядке** (по `subnetID` ASC — как текущий `parseNICRefs` sort):
`ChildName(<sidA>,"192.168.90.0/24"),ChildName(<sidB>,"192.168.88.0/24")`
**And** провайдер-ключи каждого NIC построены по СВОЕМУ child (`<childA>.<ns>.ovn.*` для
`192.168.90.91`, `<childB>.<ns>.ovn.*` для `192.168.88.157`) — без перекрёстного смешения
**And** порядок интерфейсов воспроизводим между прогонами (детерминизм)

### Сценарий S2-03: NIC без fixed-IP, сабнет с >1 CIDR → детерминированный fallback на первый канонический CIDR (edge, решение) [req: fallback][req: cidr-resolution]

**ID:** OP2-P0-S2-03

**Given** NIC `<nicID>` c `v4AddressIds=[]`, `v6AddressIds=[]` (нет fixed-IP)
**And** `SubnetService.Get(<sid>)` → `v4CidrBlocks=[192.168.88.0/24, 192.168.89.0/24]` (>1 CIDR)

**When** webhook резолвит CIDR-A

**Then** **определённое поведение (решение: deterministic-first-CIDR, НЕ reject):**
CIDR-A = первый CIDR в детерминированном каноническом порядке (канонические CIDR
отсортированы стабильно; берётся первый) → `networks` = `ChildName(<sid>, CIDR-A)`,
provider — соответствующий child
**And** IP-аннотация НЕ проставляется (нет fixed-IP → kube-ovn IPAM сам назначит адрес
из этого child-сабнета)
**And** выбор детерминирован и НЕ зависит от порядка CIDR во входном списке (сортировка
до выбора) — повторный admission даёт тот же child

> [!note] Обоснование fallback >1 CIDR (deterministic-first, НЕ reject)
> `failurePolicy=ignore` ⇒ reject = молчаливый под-без-NIC (хуже наблюдаемости и UX, чем
> attach к детерминированно выбранному CIDR). NIC без Address — допустимое состояние
> (Address привязывается отдельно); под всё равно должен получить рабочий secondary-NIC,
> а IP назначит kube-ovn IPAM из выбранного child-сабнета. Детерминированный выбор
> (первый канонический CIDR) воспроизводим и self-consistent при повторном admission.
> Альтернатива (reject) отвергнута: молчаливый no-NIC при `failurePolicy=ignore` —
> худший наблюдаемый исход. На degraded-ветке webhook логирует выбор (info-level).

### Сценарий S2-04: fixed-IP не попадает ни в один CIDR сабнета (negative/degraded) [req: cidr-resolution]

**ID:** OP2-P0-S2-04

**Given** NIC с fixed-IP `203.0.113.9`, `SubnetService.Get(<sid>)` →
`v4CidrBlocks=[192.168.88.0/24, 192.168.89.0/24]` (IP не входит НИ в один CIDR —
рассинхрон данных upstream)

**When** webhook резолвит CIDR-A

**Then** CIDR-A не определён → webhook НЕ выдумывает child и НЕ ставит произвольный NAD
(не молча attach'ит к неверной сети); путь degraded
**And** webhook логирует ошибку (warning, с `nicID`/`addr`/`subnetID`) и при
`failurePolicy=ignore` под допускается без этого NIC (молчаливый attach к неправильному
child недопустим — это безопаснее, чем неверная сеть)
**And** assert: в поде НЕ появляется ни `networks`-запись, ни provider-ключи для этого
несопоставимого NIC (для прочих корректных NIC того же пода — проставляются, S2-02)

### Сценарий S2-05: Address-CIDR ещё не материализован в child (degraded/eventual) [req: nad-ref][req: cidr-resolution]

**ID:** OP2-P0-S2-05

**Given** NIC с fixed-IP `192.168.89.42` ∈ CIDR `192.168.89.0/24` сабнета `<sid>`
**And** egress-контур ещё НЕ создал NAD `ChildName(<sid>, "192.168.89.0/24")` (eventual:
CIDR недавно добавлен, реконсайл оператора отстаёт)

**When** webhook мутирует под

**Then** webhook **всё равно** проставляет `networks = ChildName(<sid>, "192.168.89.0/24")`
и provider-ключи по этому child — имя вычисляется детерминированно из CIDR-списка
сабнета, webhook НЕ проверяет существование NAD в кластере (он не List'ит NAD'ы)
**And** под допускается; до появления NAD CNI-attach к этому NIC не материализуется в
data-plane, но как только egress создаст NAD с тем же именем — сеть совпадёт (eventual
consistency; зеркалит graceful dangling-ref data-integrity §4)
**And** assert: webhook НЕ падает и НЕ reject'ит из-за отсутствующего NAD (он не зависит
от downstream-наличия — имя стабильно по содержимому)

### Сценарий S2-06: cross-tenant guard — projectID ключа != namespace (negative, guard сохранён) [req: guards]

**ID:** OP2-P0-S2-06

**Given** под в namespace `<ns>` с аннотацией `<sid>.<otherPid>.kacho.io/nic: <nicID>`,
где `<otherPid> != <ns>`

**When** webhook обрабатывает под

**Then** webhook возвращает ошибку cross-tenant (текст вида `references project … != pod
namespace … (cross-tenant)`) — поведение НЕ изменилось относительно текущего кода
**And** patch'а аннотаций не происходит (guard срабатывает до резолва/мутации)

### Сценарий S2-07: guard — резолвленный NIC не в claimed project/subnet (negative, guard сохранён) [req: guards]

**ID:** OP2-P0-S2-07

**Given** под в `<ns>` (== `<pid>`) с аннотацией `<sid>.<pid>.kacho.io/nic: <nicID>`
**And** `NetworkInterfaceService.Get(<nicID>)` → NIC с `projectId=<pid>` но `subnetId=<otherSid>` (`<otherSid> != <sid>`)

**When** webhook обрабатывает под

**Then** webhook возвращает ошибку (текст вида `nic … is in subnet … not … claimed in
annotation …`) — guard НЕ изменён
**And** аналогично: NIC с `projectId != <pid>` → ошибка `nic … belongs to project …` (текущее поведение сохранено)
**And** новый CIDR-resolution / provider-логика выполняется ТОЛЬКО после прохождения
обоих guard'ов (порядок: guard → resolve NIC → CIDR-resolution → patch)

### Сценарий S2-08: упавший resolver (NIC/Address/Subnet недоступен) (negative/degraded) [req: cidr-resolution][req: fallback]

**ID:** OP2-P0-S2-08

**Given** под с валидной NIC-аннотацией (guard'ы прошли бы)

**When** при обработке: (а) `NetworkInterfaceService.Get` возвращает ошибку — ЛИБО (б)
`SubnetService.Get` возвращает ошибку — ЛИБО (в) `AddressService.Get` возвращает ошибку

**Then** (а) NIC не резолвится → webhook возвращает ошибку (текущее поведение: NIC —
авторитетный источник MAC+project+subnet, без него мутировать нельзя; при
`failurePolicy=ignore` под допускается без NIC, ошибка залогирована)
**And** (б) Subnet не резолвится → CIDR-A определить нельзя → degraded: `networks`/provider
для этого NIC НЕ проставляются, ошибка залогирована (warning), прочие корректные NIC
пода — обрабатываются
**And** (в) Address не резолвится → fixed-IP неизвестен → IP-аннотация не ставится; CIDR-A
определяется по fallback-правилам (S1-05/S2-03, как если бы у NIC не было Address) —
под получает NIC, IP назначит kube-ovn IPAM (graceful degrade, не reject)

---

## Тестовая стратегия (envtest + unit с fake-resolver'ами)

- **unit (webhook `Default`)** — основной уровень. Fake-реализации
  `NetworkInterfaceServiceClient` / `AddressServiceClient` / `SubnetServiceClient`
  (table-driven), проверяющие итоговые `pod.Annotations`:
  - single-v4: `networks`==`ChildName`, provider-ключи==`<child>.<ns>.ovn.*`, нет bare-`<sid>.<ns>.ovn.*` (S1-01/02).
  - CIDR-resolution: containing-CIDR ≠ первый в списке (S1-03); IP вне всех CIDR → degraded (S2-04).
  - dual-stack: оба child-NAD в `networks`, per-family ip_address, детерминированный порядок (S2-01).
  - multi-NIC разные сабнеты: comma-join ASC, per-NIC provider (S2-02).
  - fallback: NIC без Address, 1 CIDR → этот CIDR (S1-05); >1 CIDR → deterministic-first (S2-03).
  - eventual: NAD ещё не создан → имя всё равно проставлено, не падает (S2-05).
  - guard'ы: cross-tenant project (S2-06), NIC не в claimed subnet/project (S2-07).
  - resolver-ошибки NIC/Subnet/Address → ожидаемая degraded-ветка (S2-08).
  - idempotency: повторный `Default` → те же значения (S1-04).
- **envtest (webhook integration)** — поднять webhook-server в envtest, прогнать
  CREATE/UPDATE пода с NIC-аннотацией через реальный admission-flow с fake gRPC
  resolver'ами; assert на мутированные аннотации (S1-01/02, S2-01/02 как минимум) —
  подтверждает wiring DI третьего (Subnet) resolver'а.
- **shared-naming**: unit на `kubeovn.ChildName`/`CanonicalCIDR` (каноникализация, 63-char
  bound, детерминизм — S0-02); регрессия egress-envtest после переноса (S0-03);
  `grep`-инвариант «одна реализация» (S0-01) проверяется code-review.
- **TDD** — для каждого сценария: падающий тест (RED, по правильной причине: webhook
  ставит bare-`<sid>` / нет dual-stack) ДО кода → GREEN. В отчёте показать пару RED→GREEN.
- Финальная верификация: `go test ./... -race` + `golangci-lint run` + envtest зелёные.

---

## Не-цели (explicit non-goals)

1. **kube-ovn / Multus / proto / kacho-vpc не меняются** — webhook читает существующие
   RPC (`NetworkInterfaceService.Get`, `AddressService.Get`, `SubnetService.Get`) и
   существующие proto-поля. Никаких новых RPC/полей/миграций.
2. **OP1 egress-материализация не переписывается** — этот фикс приводит webhook В
   СООТВЕТСТВИЕ с per-CIDR именованием OP1, но не меняет, как egress создаёт child'ы.
   Перенос `childName`/`canonicalCIDR` в `internal/kubeovn` — чистый рефактор (S0).
3. **Никакого combine-into-dual-stack** в провайдер-ключах — per-family child-NAD +
   per-family provider-ключи (зеркалит OP1 решение A). Combined `<provider>.../ip_address
   = "v4,v6"` под одним bare-`<sid>` НЕ используется (такого NAD нет).
4. **Чистка legacy bare-`<sid>.<ns>.ovn.*` ключей** из входного пода — НЕ цель: webhook
   проставляет корректный `<child>.<ns>.ovn.*` (новый авторитетный контракт), но не
   обязан удалять возможные остаточные ключи прошлой (забагованной) версии. (Латентность
   #1 означает, что подов с такими ключами на практике нет.)
5. **failurePolicy webhook'а не меняется** (`ignore` сохраняется) — degraded-ветки
   логируют/допускают под; смена на `Fail` — отдельное решение, вне scope.
6. **SecurityGroup→ACL / RouteTable→staticRoutes / Gateway→VpcNatGateway** — boundary
   (см. `MAPPING.md`), вне scope OP2-P0.
7. **Cross-tenant guard'ы и порядок их применения** — НЕ меняются (только дополняются
   CIDR-resolution ПОСЛЕ guard'ов).

---

## Трассировка требований → сценарии

| Требование | Сценарии |
|---|---|
| shared-naming: одна реализация `ChildName`/`CanonicalCIDR` (webhook + egress) | S0-01, S0-02, S0-03 |
| nad-ref: `networks` = `ChildName(subnetID, canonical(CIDR-A))`, не bare-`<sid>` | S1-01, S1-03, S2-01, S2-02, S2-05 |
| provider-prefix: mac/ip-ключи = `<childName>.<ns>.ovn.*`, не `<sid>.<ns>.ovn.*` | S1-02, S2-01, S2-02 |
| cidr-resolution: CIDR-A = CIDR сабнета, содержащий fixed-IP (IP-in-prefix) | S1-01, S1-03, S2-04, S2-05 |
| dual-stack: ip_address per-family v4+v6, оба child-NAD, детерм. порядок | S2-01 |
| multi-nic: comma-join по subnetID ASC, per-NIC provider | S2-02 |
| fallback: NIC без Address — 1 CIDR → этот; >1 CIDR → deterministic-first (не reject) | S1-05, S2-03, S2-08(в) |
| degraded: IP вне всех CIDR / Subnet-resolve fail / NAD не материализован | S2-04, S2-05, S2-08 |
| guards: projectID==namespace; NIC в claimed project+subnet (сохранены) | S2-06, S2-07 |
| idempotency повторного admission | S1-04 |
| non-goal: OP1/proto/kube-ovn не переписываются; failurePolicy=ignore; legacy-cleanup | §не-цели |
| root-cause issue `kacho-vpc-operator#1` (bare-`<sid>` NAD-ссылка) | S1-01, S1-02 |
| ticket/branch binding (ban #1, pre-APPROVAL gate) | заголовок §«Привязка к тикету» |
