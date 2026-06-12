# Sub-phase OP1 — KachoSubnet CRD redesign (intermediate CRD + two-loop materialization) — Acceptance

> Статус: DRAFT (revision v2 — адресует CHANGES REQUESTED #1–#6 ревьюера)
> Дата: 2026-06-12
> Ревьюер: acceptance-reviewer (gate перед кодом, ban #1)

### Привязка к тикету (ban #1 + git-youtrack — обязательна ДО APPROVED-for-code)

> [!important] Pre-APPROVAL gate (reviewer change #6)
> Этот acceptance-док НЕ может быть APPROVED-for-code, пока не заполнены поля ниже
> **реальным** KAC-номером (не плейсхолдером). В текущем окружении нет YouTrack
> MCP/CLI/токена и нет `gh`-issue под эту работу — поэтому номер должен присвоить
> orchestrator (он владеет YouTrack-доступом) до старта кодинга. Заведение тикета и
> создание KAC-trail — последний шаг перед снятием gate, **не** часть acceptance-текста.

| Поле | Значение |
|---|---|
| Эпик (если ≥3 репо или крупно) | `KAC-<EPIC>` `[EPIC] kacho-vpc-operator KachoSubnet CRD redesign` (Subtask-иерархия) |
| Subtask (этот док) | `KAC-<N>` `OP1 — KachoSubnet CRD + ingress/egress materialization` |
| Ветка `kacho-vpc-operator` | `KAC-<N>` (от `main`; первый собственный CRD оператора) |
| Ветка `kacho-deploy` (если CRD/RBAC install shipping туда) | `KAC-<N>` (CRD-манифест + ClusterRole; см. S1-04, S4-04) |
| Правка vault `kacho-workspace` | `obsidian/kacho/edges/vpc-operator-to-kubeovn.md` + `obsidian/kacho/KAC/KAC-<N>.md` (KAC-trail) |
| YouTrack | `https://prorobotech.youtrack.cloud/issue/KAC-<N>` |
| Роль исполнителя | `acceptance-author` (этот док) → реализация: domain-агенты `kacho-vpc-operator` |

> Затронутые репо: `kacho-vpc-operator` (код) + `kacho-deploy` (CRD-манифест + ClusterRole install, если CRD устанавливается там) + правка `obsidian/kacho/edges/vpc-operator-to-kubeovn.md` (`kacho-workspace`).
> Зависит от: SEC-G (operator→{vpc,iam} mTLS dial + least-priv SA + FGA principal) — **не должно регрессировать**.

## Обзор

Текущий `internal/syncer/syncer.go` (`upsertSubnet`) маппит Kachō Subnet → **ОДНУ**
kube-ovn Subnet через `pickCIDR` — берёт **первый v4-CIDR**, молча отбрасывает v6 и
все «лишние» CIDR'ы (Kachō Subnet хранит раздельные списки `v4CidrBlocks[]` +
`v6CidrBlocks[]`, а `kubeovn.io/Subnet.spec.cidrBlock` — одна строка, один v4
[+ опц. один v6]). Несколько CIDR на семью в одну kube-ovn Subnet не помещаются —
это и есть дефект, который заменяем.

**Согласованная архитектура — промежуточный CRD + два контура:**

1. **Новый CRD `KachoSubnet`** (`group kacho.io`, `v1`, **cluster-scoped**). Spec
   зеркалит Kachō Subnet 1:1 (`id`, `projectId`, `networkId`, `name`,
   `v4CidrBlocks []string`, `v6CidrBlocks []string`, + ссылка на project-namespace).
   **Cluster-scoped обязателен**: его `ownerReference` должен каскадно покрывать
   и **cluster-scoped** kube-ovn Subnet, и **namespaced** Multus NAD (namespaced
   dependent может иметь cluster-scoped owner; namespaced owner НЕ может владеть
   cluster-scoped kube-ovn Subnet).

2. **INGRESS-контур (Kachō API → CRD).** Существующий poll-syncer теперь зеркалит
   каждую Kachō Subnet в **ОДИН** `KachoSubnet` CR (1:1, тривиальный diff:
   create/update/delete CR под набор Kachō Subnet'ов на каждый обнаруженный
   project-namespace). У Kachō нет Watch (продуктовая конвенция) — поллинг остаётся,
   но теперь он управляет **ТОЛЬКО** `KachoSubnet` CR'ами (НЕ kube-ovn объектами).
   Удаление Kachō Subnet → удаление `KachoSubnet` CR.

3. **EGRESS-контур (CRD → kube-ovn).** controller-runtime Reconciler:
   `For(&KachoSubnet{}).Owns(kubeovn Subnet unstructured).Owns(NAD unstructured)`,
   event-driven + periodic resync. На каждый `KachoSubnet` материализует **ОДНУ**
   kube-ovn Subnet + **ОДИН** Multus NAD **НА КАЖДЫЙ CIDR** (dual-stack **РЕШЕНИЕ A**:
   один CIDR = одна single-family kube-ovn Subnet; `protocol` = `IPv4` ЛИБО `IPv6`;
   НИКАКОГО `"v4,v6"`-combine). Имя каждого child — детерминированное
   **stable-by-CIDR**: `<kachoSubnetName>-<shorthash(cidr)>` (**НИКОГДА** не
   index-based). На каждый child: `OwnerReference(KachoSubnet)` + `controller=true`,
   labels `kacho.io/upstream-id`, `kacho.io/cidr`.

**Ключевое требование — deletion sync:**

- **Element-level** (CIDR удалён из списка): egress-reconcile вычисляет desired-set
  `{name(cidr) | cidr ∈ v4∪v6}` против actual owned-children (List по
  ownerRef/label) → **PRUNE** child'ов, чьё имя ∉ desired (удалить kube-ovn Subnet
  + его NAD для удалённого CIDR).
- **Whole-Subnet delete**: удалить `KachoSubnet` CR → k8s GC каскадно сносит ВСЕ
  owned kube-ovn Subnet'ы + NAD'ы (по ownerRef). Ingress-контур удаляет CR, когда
  Kachō Subnet исчезает.
- **SAFETY (finalizer)**: на `KachoSubnet` — finalizer; перед удалением
  kube-ovn Subnet child'а, у которого ещё есть **реально аллоцированные tenant-IP**
  (pod-allocations) — **НЕ удалять**: выставить degraded condition/Event («CIDR in
  use, detach first») и requeue (graceful, зеркалит cross-domain dangling-ref правило
  `data-integrity.md` §4). Finalizer снимается только когда teardown чистый.
  **«In-use» определяется по точному status-полю kube-ovn Subnet, выверенному против
  установленной версии kube-ovn CRD** (имя поля версионно-зависимо: `v4UsingIPs`/
  `v4usingIPs`/`v4availableIPs` — не хардкодить «на память», см. S3-06 §Given).
  **gateway / excludeIps / зарезервированные kube-ovn IP (broadcast и т.п.) НЕ
  считаются in-use** — иначе свежесозданный пустой child ложно считался бы занятым и
  никогда не прунился (см. S3-06, S3-04).

Трассировка к требованиям дана у каждого сценария тегом **[req: …]**.

---

## Стадии

OP1 — самостоятельный end-to-end deliverable, дробится на 4 стадии (порядок merge):

- **S1** — CRD `KachoSubnet` (kubebuilder `api/v1` типы + DeepCopy + `config/crd` + RBAC-маркеры, cluster-scoped, spec-поля).
- **S2** — INGRESS-контур: poll-syncer 1:1 reflect Kachō Subnet → KachoSubnet CR (create/update/delete CR), перестаёт трогать kube-ovn напрямую.
- **S3** — EGRESS-контур: Reconciler 1→N per-CIDR single-family материализация (stable-by-CIDR имена + ownerRefs) + element-level prune + whole-delete cascade + finalizer/in-use safety.
- **S4** — vault/edge-trail + регресс-гейты (mTLS dial, FGA-registration, ns-operator не тронут) + kube-ovn status-field version-pin + CRD/RBAC install (`kacho-deploy`, если CRD устанавливается там).

DoD каждой стадии — все её сценарии зелёные (TDD red→green), `go test ./... -race`
+ `golangci-lint run` зелёные, envtest для egress-reconcile зелёный.

---

## S1 — CRD `KachoSubnet` (cluster-scoped, kubebuilder)

**Контекст (recon):** репо — kubebuilder/controller-runtime (`PROJECT` `cliVersion 4.10.1`,
`domain: kacho.io`, layout `go.kubebuilder.io/v4`). Сейчас у оператора **нет своих CRD**
(источник истины — БД kacho-vpc через gRPC). Добавляем первый собственный CRD
идиоматично: `api/v1/kachosubnet_types.go` (+ `zz_generated.deepcopy.go`),
`config/crd/...`, RBAC-маркеры (`+kubebuilder:rbac`).

### Сценарий S1-01: KachoSubnet — cluster-scoped CRD с зеркальным spec (happy) [req: CRD-schema]

**ID:** OP1-S1-01

**Given** kubebuilder-проект `kacho-vpc-operator` (`group kacho.io`, `version v1`)
**And** маркер `+kubebuilder:resource:scope=Cluster` на типе `KachoSubnet`

**When** генерируются CRD-манифесты (`make manifests`) и тип устанавливается в кластер (envtest/kind)

**Then** создаётся CRD `kachosubnets.kacho.io`, `spec.scope == Cluster` (НЕ Namespaced)
**And** spec содержит поля, зеркальные Kachō Subnet 1:1: `id` (string), `projectId` (string), `networkId` (string), `name` (string), `v4CidrBlocks` (`[]string`), `v6CidrBlocks` (`[]string`), `projectNamespace` (string — ссылка на namespace проекта)
**And** сгенерирован валидный `DeepCopyObject`/`DeepCopyInto` (рантайм-объект регистрируется в scheme без паники)
**And** JSON-поля в CRD — camelCase (`v4CidrBlocks`, `projectId`, `networkId`, `projectNamespace`) — единый naming Kachō

### Сценарий S1-02: cluster-scoped owner покрывает оба типа child (positive) [req: CRD-schema][req: ownerRef]

**ID:** OP1-S1-02

**Given** установленный CRD `kachosubnets.kacho.io` (cluster-scoped)
**And** в кластере зарегистрированы GVK `kubeovn.io/v1 Subnet` (cluster-scoped) и `k8s.cni.cncf.io/v1 NetworkAttachmentDefinition` (namespaced)

**When** на cluster-scoped kube-ovn Subnet И на namespaced NAD выставляется `ownerReference` на `KachoSubnet`

**Then** apiserver принимает оба ownerRef (cluster-scoped owner допустим и для cluster-scoped, и для namespaced dependent)
**And** регистрируется и подтверждается, что обратное (namespaced owner → cluster-scoped kube-ovn Subnet) apiserver'ом было бы отклонено — обоснование выбора cluster-scope зафиксировано в комментарии типа

### Сценарий S1-03: невалидный spec — пустой id / отсутствие CIDR-списков (negative) [req: CRD-schema]

**ID:** OP1-S1-03

**Given** установленный CRD `KachoSubnet`

**When** ingress-контур формирует CR из Kachō Subnet с пустым `id`

**Then** CR не создаётся с пустым `id` (ingress не порождает orphan-CR без ключа корреляции)
**And** `KachoSubnet` с ОБОИМИ пустыми `v4CidrBlocks` и `v6CidrBlocks` допустим как ресурс (Kachō Subnet без CIDR валиден), но egress-контур материализует НОЛЬ child'ов (см. S3-07) — это не ошибка валидации CRD

### Сценарий S1-04: RBAC-маркеры покрывают KachoSubnet + child-типы (edge) [req: CRD-schema]

**ID:** OP1-S1-04

**Given** RBAC-маркеры `+kubebuilder:rbac` для контроллера

**When** генерируется `config/rbac/role.yaml`

**Then** манифест даёт права на `kachosubnets.kacho.io` (get/list/watch/create/update/patch/delete + `/status` + `/finalizers`)
**And** даёт права на `kubeovn.io Subnets` и `k8s.cni.cncf.io networkattachmentdefinitions` (get/list/watch/create/update/patch/delete)
**And** на `Namespace` остаётся **read-only** (list/watch — discovery project-ns; ns-lifecycle принадлежит ns-operator, не трогаем)

---

## S2 — INGRESS-контур: Kachō Subnet → KachoSubnet CR (1:1)

**Контекст (recon):** `Syncer.reconcileOnce` обнаруживает project-namespace'ы
(label `managed-by=kacho-project-operator`, через НЕкэшированный `mgr.GetAPIReader()`),
поллит kacho-vpc `SubnetService.List(project_id)` (Kachō не имеет Watch — конвенция).
Сейчас `upsertSubnet` пишет kube-ovn Subnet+NAD напрямую — **этот вызов заменяется**
на upsert `KachoSubnet` CR. Skip-terminating-ns, fail-closed cluster-cleanup
(`listErr`), uncached reader — **сохраняются**.

### Сценарий S2-01: новая Kachō Subnet → создаётся KachoSubnet CR (happy) [req: ingress-reflect]

**ID:** OP1-S2-01

**Given** обнаружен project-namespace `<ns>` (project `<pid>`)
**And** kacho-vpc вернул Subnet `<sid>` (`name=s1`, `networkId=<nid>`, `v4CidrBlocks=[192.168.88.0/24]`, `v6CidrBlocks=[fd00:88::/64]`)
**And** `KachoSubnet` с `id=<sid>` ещё не существует

**When** `reconcileOnce` отрабатывает ingress-контур

**Then** создаётся cluster-scoped `KachoSubnet` (имя детерминированно по `<sid>`) со spec, зеркальным Kachō Subnet 1:1: `id=<sid>`, `projectId=<pid>`, `networkId=<nid>`, `name=s1`, `v4CidrBlocks=[192.168.88.0/24]`, `v6CidrBlocks=[fd00:88::/64]`, `projectNamespace=<ns>`
**And** ingress-контур НЕ создаёт никаких kube-ovn Subnet/NAD напрямую (это работа egress-контура)
**And** на CR проставлены labels `kacho.io/managed-by=kacho-vpc-operator`, `kacho.io/upstream-id=<sid>`, `kacho.io/project-id=<pid>`

### Сценарий S2-02: изменилась Kachō Subnet (добавлен CIDR) → CR обновлён (happy) [req: ingress-reflect]

**ID:** OP1-S2-02

**Given** существует `KachoSubnet` `<sid>` с `v4CidrBlocks=[192.168.88.0/24]`
**And** kacho-vpc теперь отдаёт ту же Subnet с `v4CidrBlocks=[192.168.88.0/24, 192.168.89.0/24]`

**When** `reconcileOnce` отрабатывает ingress-контур

**Then** spec существующего CR обновлён до `v4CidrBlocks=[192.168.88.0/24, 192.168.89.0/24]` (update, не дубль-create)
**And** прочие неизменившиеся поля spec не «дёргаются» зря (update идемпотентен — без spurious writes при равном spec, см. S2-04)

### Сценарий S2-03: Kachō Subnet удалена → KachoSubnet CR удаляется (happy) [req: ingress-delete]

**ID:** OP1-S2-03

**Given** существует `KachoSubnet` `<sid>` (project `<pid>`)
**And** kacho-vpc `SubnetService.List(<pid>)` больше НЕ возвращает `<sid>`
**And** все upstream-List'ы по всем проектам прошли успешно (нет `listErr`)

**When** `reconcileOnce` отрабатывает ingress-контур (prune исчезнувших)

**Then** `KachoSubnet` `<sid>` удаляется (это триггерит egress-каскад child'ов, см. S3-05)
**And** удаление НЕ происходит, если upstream-List этого project упал (`listErr` — fail-closed, как сейчас для cluster-cleanup): orphan-CR переживает временную недоступность vpc

### Сценарий S2-04: идемпотентность ingress (positive) [req: ingress-reflect][req: idempotency]

**ID:** OP1-S2-04

**Given** `KachoSubnet` `<sid>` уже в точности соответствует Kachō Subnet `<sid>`

**When** `reconcileOnce` прогоняется повторно без изменений в kacho-vpc

**Then** CR остаётся неизменным (no create, no spurious update/resourceVersion-bump при равном spec)
**And** повторный прогон детерминирован — то же множество CR

### Сценарий S2-05: Terminating project-namespace пропущен (edge) [req: ingress-reflect]

**ID:** OP1-S2-05

**Given** project-namespace `<ns>` имеет `deletionTimestamp != nil` (project удаляется)

**When** `reconcileOnce` перечисляет project-namespace'ы

**Then** `<ns>` пропускается (не итерируется) — vpc `List(<pid>)` для удалённого project не вызывается (иначе PermissionDenied → `listErr`)
**And** существующие `KachoSubnet` CR этого project станут orphan'ами и подчистятся штатно (через свой prune / GC при удалении ns)

---

## S3 — EGRESS-контур: KachoSubnet → N×(kube-ovn Subnet + NAD), per-CIDR

**Контекст (recon):** новый controller-runtime Reconciler
`For(&KachoSubnet{}).Owns(kubeovn Subnet).Owns(NAD)`, event-driven + periodic resync.
Переиспользует существующие хелперы из `internal/syncer`: `firstUsableIP`, `vpcNameFor`,
provider-строку (`<name>.<ns>.ovn`), NAD-config-builder. `pickCIDR` (first-v4-only) —
**удаляется** (заменяется итерацией по `v4∪v6`). Dual-stack — **РЕШЕНИЕ A**.

### Сценарий S3-01: KachoSubnet с N CIDR → N single-family child'ов (happy) [req: egress-materialize][req: dual-stack-A]

**ID:** OP1-S3-01

**Given** создан `KachoSubnet` `<name>` (`projectNamespace=<ns>`, `networkId=<nid>`) с `v4CidrBlocks=[192.168.88.0/24, 192.168.89.0/24]`, `v6CidrBlocks=[fd00:88::/64]`

**When** egress-Reconciler реконсайлит этот `KachoSubnet`

**Then** материализуются РОВНО 3 пары (kube-ovn Subnet + NAD) — по одной на CIDR
**And** каждая kube-ovn Subnet — single-family: `protocol=IPv4` для v4-CIDR, `protocol=IPv6` для v6-CIDR (НИКОГДА `"v4,v6"` — combine запрещён, решение A)
**And** `spec.cidrBlock` каждой kube-ovn Subnet содержит РОВНО один свой CIDR
**And** `spec.gateway` каждой = `firstUsableIP(cidr)` (переиспользованный хелпер), `spec.vpc = vpcNameFor(<nid>)`
**And** каждый NAD создаётся в `<ns>` (namespace проекта) с provider-строкой и config через существующий NAD-builder

### Сценарий S3-02: stable-by-CIDR именование child'ов (positive) [req: stable-naming]

**ID:** OP1-S3-02

**Given** `KachoSubnet` `<name>` с `v4CidrBlocks=[192.168.88.0/24, 192.168.89.0/24]`

**When** egress-Reconciler материализует child'ов

**Then** имя каждого child = `<name>-<shorthash(cidr)>` (детерминированный хеш CIDR-строки), НЕ index-based (`<name>-0/-1`)
**And** при перестановке порядка CIDR в списке (`[89, 88]` вместо `[88, 89]`) имена child'ов НЕ меняются и НЕ происходит ложного prune+recreate (имя стабильно по содержимому CIDR, не по позиции)
**And** одно и то же имя для одного и того же CIDR при повторных реконсайлах (детерминизм)

### Сценарий S3-02a: shorthash — каноникализация, ширина, 63-char DNS-bound (edge) [req: stable-naming]

**ID:** OP1-S3-02a

**Given** хелпер `name(cidr)` строит `<name>-<shorthash(cidr)>`

**When** на вход приходят семантически-эквивалентные, но текстово-разные CIDR-формы (например `192.168.88.0/24` и неканоническая запись того же префикса) и/или очень длинный `<name>` и/или набор CIDR в одном `KachoSubnet`

**Then** перед хешированием CIDR **каноникализуется** (`netip.ParsePrefix(cidr).Masked().String()`) — эквивалентные формы дают ОДНО имя (нет дубль-child / нет alias двух разных CIDR в одно имя)
**And** ширина `shorthash` достаточна, чтобы исключить коллизию в пределах CIDR-набора одного `KachoSubnet` (разные канонические CIDR → разные суффиксы; assert: для набора из ≥2 различных CIDR все суффиксы уникальны)
**And** итоговое имя child ≤ 63 символов (k8s DNS-label limit); при превышении **усекается `<name>`-часть, а НЕ хеш** (хеш-суффикс полной ширины сохраняется — иначе теряется коллизионная стойкость)
**And** усечение детерминировано (тот же `<name>`+`cidr` → то же усечённое имя на каждом реконсайле) — stable-by-CIDR сохраняется и для длинных имён

### Сценарий S3-03: ownerRef + controller=true на каждом child (positive) [req: ownerRef]

**ID:** OP1-S3-03

**Given** `KachoSubnet` `<name>` материализован в child'ов

**When** инспектируются metadata child kube-ovn Subnet'ов и NAD'ов

**Then** на КАЖДОМ child есть `ownerReference` на `KachoSubnet` `<name>` с `controller=true` и корректным `uid`/`apiVersion`/`kind`
**And** на каждом child выставлены labels `kacho.io/upstream-id=<KachoSubnet.spec.id>` и `kacho.io/cidr=<cidr>` (для desired/actual-сверки в prune)
**And** при удалении одного child вручную event `Owns(...)` триггерит reconcile и child пересоздаётся (self-heal)

### Сценарий S3-04: element-level — CIDR удалён из списка → этот child запрунен (happy, КЛЮЧЕВОЙ) [req: element-prune]

**ID:** OP1-S3-04

**Given** `KachoSubnet` `<name>` имел `v4CidrBlocks=[192.168.88.0/24, 192.168.89.0/24]` → 2 child-Subnet'а + 2 NAD'а материализованы
**And** ни один из child'ов не имеет реальных pod-аллокаций (выверенное in-use status-поле kube-ovn = 0; gateway/excludeIps не в счёт — см. S3-06)

**When** spec `KachoSubnet` обновляется до `v4CidrBlocks=[192.168.88.0/24]` (CIDR `192.168.89.0/24` удалён) и reconcile срабатывает

**Then** egress вычисляет desired-set `{name(192.168.88.0/24)}` vs actual owned-children (List по ownerRef/label) → child `<name>-<hash(192.168.89.0/24)>` ∉ desired
**And** удаляется ИМЕННО эта kube-ovn Subnet + её NAD (для `192.168.89.0/24`)
**And** child для `192.168.88.0/24` НЕ тронут (остаётся с тем же именем/uid — без recreate)
**And** **NAD удаляется только вместе со своей kube-ovn Subnet (after/with), не независимо**: in-use guard определён на Subnet-child'е, у NAD своего `usingIPs` нет; если Subnet `192.168.89.0/24` удаляется — её NAD прунится в том же шаге; если бы Subnet удержалась (in-use, S3-06) — её NAD тоже **удерживается** (не прунить живой NAD из-под работающего пода, пока его Subnet корректно сохранена)

### Сценарий S3-05: whole-delete → каскад child'ов через ownerRef (happy) [req: whole-delete-cascade]

**ID:** OP1-S3-05

**Given** `KachoSubnet` `<name>` с 2 child-Subnet'ами + 2 NAD'ами (все с ownerRef на `<name>`, IP не аллоцированы)

**When** `KachoSubnet` `<name>` удаляется (ingress-контур снёс CR — S2-03), finalizer-teardown проходит чисто (все child'ы free; controller-driven удаление в Terminating — S3-06a)

**Then** контроллер в Terminating удаляет free child'ы (Subnet+NAD), затем снимает finalizer; **после снятия finalizer** k8s GC завершает каскад по любым остаточным owned-объектам (ownerRef), без явного per-child delete от контроллера в GC-фазе
**And** в кластере не остаётся orphan-child'ов с этим ownerRef
**And** взаимодействие controller-driven (Terminating) ↔ GC-driven (после finalizer) однозначно — см. S3-06a для in-use-варианта

### Сценарий S3-06: finalizer + in-use safety — НЕ удалять CIDR с allocated IP (negative, КЛЮЧЕВОЙ) [req: finalizer-safety]

**ID:** OP1-S3-06

**Given** перед реализацией **выверено точное имя status-поля kube-ovn Subnet** против
установленной версии kube-ovn CRD (имя версионно-зависимо: `v4UsingIPs`/`v4usingIPs`/
… — определяется чтением CRD-схемы развёрнутого kube-ovn, фиксируется как именованная
константа в коде, НЕ хардкодится «на память»)
**And** «in-use» = строго **реальные tenant/pod-аллокации**: gateway, `excludeIps` и
зарезервированные kube-ovn IP (broadcast/служебные) **НЕ считаются** in-use — иначе
свежесозданный пустой child ложно был бы «занят» и никогда не прунился
**And** `KachoSubnet` `<name>` с finalizer; child kube-ovn Subnet `<name>-<hash(cidr)>`
имеет выверенное status-поле = `2` (под с NIC держит реальный IP)

**When** этот CIDR удаляется из spec (element-level) ЛИБО `KachoSubnet` удаляется целиком (whole-delete)

**Then** контроллер НЕ удаляет in-use child kube-ovn Subnet (и его парный NAD — удерживается вместе с Subnet, S3-04)
**And** выставляется degraded condition на `KachoSubnet.status` (+ Event) с сообщением вида «CIDR in use, detach first» (graceful, зеркалит dangling-ref правило data-integrity §4)
**And** reconcile requeue'ится (повтор позже), finalizer НЕ снимается, `KachoSubnet` остаётся в Terminating до чистого teardown
**And** assert: пустой (только-что-созданный, gateway/excludeIps выставлены, pod-аллокаций нет) child НЕ считается in-use и удаляется штатно при prune (защита от ложного in-use)

### Сценарий S3-06a: teardown в Terminating — контроллер-driven для free, блок только на in-use (КЛЮЧЕВОЙ) [req: finalizer-safety][req: whole-delete-cascade]

**ID:** OP1-S3-06a

**Given** `KachoSubnet` `<name>` с finalizer и 2 child-Subnet'ами: `A` (in-use, status-поле>0) и `B` (free, аллокаций нет), у каждого парный NAD
**And** `KachoSubnet` `<name>` удаляется целиком (deletionTimestamp выставлен; whole-delete)

**When** контроллер реконсайлит объект в Terminating

**Then** **во время Terminating дочерние объекты удаляет САМ контроллер** (явный `Delete`), НЕ ждём ownerRef-GC: GC сработает только когда владелец (`KachoSubnet`) реально исчезнет, а finalizer держит владельца → во время Terminating GC по ownerRef ещё не запускается
**And** free child `B` + его NAD удаляются контроллером немедленно
**And** in-use child `A` + его NAD **удерживаются**, finalizer НЕ снимается, reconcile requeue
**And** как только `A` достигает status-поле==0 (под удалён) — контроллер удаляет `A`+NAD; **finalizer снимается в момент, когда последний in-use child стал free** — после снятия finalizer владелец удаляется и GC завершает каскад (остаточные owned-объекты, если есть, подбираются ownerRef-GC)
**And** однозначно: teardown free-child'ов — **controller-driven** (в Terminating), финальная зачистка после снятия finalizer — **GC-driven** (S3-05)

### Сценарий S3-07: KachoSubnet без CIDR → ноль child'ов (edge) [req: egress-materialize]

**ID:** OP1-S3-07

**Given** `KachoSubnet` `<name>` с пустыми `v4CidrBlocks=[]` и `v6CidrBlocks=[]`

**When** egress-Reconciler реконсайлит

**Then** материализуется НОЛЬ child kube-ovn Subnet/NAD (desired-set пуст), reconcile успешен (не error)
**And** если ранее у этого `KachoSubnet` были child'ы — все они прунятся (desired пуст → все actual ∉ desired), с учётом in-use safety S3-06

### Сценарий S3-08: невалидный CIDR в списке (negative) [req: egress-materialize]

**ID:** OP1-S3-08

**Given** `KachoSubnet` `<name>` с `v4CidrBlocks=[192.168.88.0/24, "garbage"]`

**When** egress-Reconciler реконсайлит

**Then** валидный CIDR `192.168.88.0/24` материализуется (один child Subnet+NAD)
**And** невалидный `"garbage"` — НЕ материализуется; выставляется degraded condition/Event на `KachoSubnet.status` с указанием битого CIDR
**And** один битый CIDR НЕ блокирует материализацию валидных (partial-progress, per-CIDR изоляция ошибки)
**And** **prune-fail-safe**: desired-set строится ТОЛЬКО из валидных каноникализованных CIDR; битый `"garbage"` не порождает имени и НЕ участвует в set-diff — он **не** может пометить ранее-валидный child как «actual ∉ desired» и спровоцировать его удаление
**And** при наличии хотя бы одного невалидного CIDR в списке шаг prune работает против **полностью вычисленного валидного desired-set** и **никогда не удаляет** child'ы, принадлежащие всё ещё валидным CIDR (fail-safe: не прунить при частично/ошибочно вычисленном desired)
**And** assert: child для `192.168.88.0/24`, существовавший до появления `"garbage"` в списке, остаётся нетронутым (без ложного prune)

### Сценарий S3-09: идемпотентность egress (positive) [req: idempotency]

**ID:** OP1-S3-09

**Given** `KachoSubnet` `<name>` уже материализован (desired == actual)

**When** reconcile прогоняется повторно (periodic resync без изменений spec)

**Then** child'ы не пересоздаются и не получают spurious update (равный spec → no-op apply)
**And** число child'ов и их имена/uid стабильны между прогонами

### Сценарий S3-10: dual-stack один CIDR на семью (edge, решение A) [req: dual-stack-A]

**ID:** OP1-S3-10

**Given** `KachoSubnet` `<name>` с `v4CidrBlocks=[10.0.0.0/24]`, `v6CidrBlocks=[fd00::/64]`

**When** egress-Reconciler материализует

**Then** создаются ДВЕ независимые single-family kube-ovn Subnet'а: одна `protocol=IPv4 cidrBlock=10.0.0.0/24`, вторая `protocol=IPv6 cidrBlock=fd00::/64` (НЕ одна dual-stack `protocol=Dual` с `"10.0.0.0/24,fd00::/64"`)
**And** каждая — со своим NAD, своим stable-by-CIDR именем, своим ownerRef

---

## S4 — Регресс-гейты, trail, не-цели

### Сценарий S4-01: ns-operator (project-operator) не тронут (regression) [req: non-goal]

**ID:** OP1-S4-01

**Given** редизайн затрагивает `internal/syncer` + новый `api/v1` + новый egress-controller

**When** прогон полного теста репо

**Then** `cmd/nsoperator` / `internal/nssyncer` (namespace-lifecycle, AccountService.List→ProjectService.List fan-out) — без изменений поведения
**And** RBAC оператора на Namespace остаётся read-only (create/delete namespace по-прежнему ТОЛЬКО у ns-operator)

### Сценарий S4-02: mTLS dial и FGA-registration не регрессируют (regression) [req: non-goal][req: SEC-G]

**ID:** OP1-S4-02

**Given** SEC-G: per-edge mTLS dial (`upstream.Dial`/`DialIAM`, `TLSClient{enable,...}`) + principal-инжект (инвариант I2) + least-priv SA viewer-tuples

**When** ingress-контур поллит kacho-vpc через тот же `upstream.Client`

**Then** dial-поведение неизменно: `enable=false` → insecure (back-compat), `enable=true` → mTLS + principal-metadata
**And** principal/FGA-viewer требования к чтению Subnet/Network не изменились (редизайн меняет downstream-материализацию, не upstream-edge)
**And** существующие `internal/upstream/client_mtls_test.go` и config-тесты остаются зелёными

### Сценарий S4-03: edge-trail обновлён (trail) [req: vault]

**ID:** OP1-S4-03

**Given** изменилось downstream cross-system поведение оператора (intermediate CRD + два контура)

**When** работа завершена

**Then** `obsidian/kacho/edges/vpc-operator-to-kubeovn.md` обновлён: новый поток `Kachō Subnet → KachoSubnet CR (ingress) → N×(kube-ovn Subnet+NAD) per-CIDR (egress)`, deletion-семантика (element-prune / controller-driven Terminating teardown / ownerRef-cascade / finalizer in-use safety), запись в «История» с KAC-номером
**And** при необходимости создана узкая запись `resources/kacho-vpc-operator-KachoSubnet.md` (CRD-контракт: scope=Cluster, spec-поля, ownerRef-каскад, naming, выверенное in-use status-поле)
**And** создан/обновлён KAC-trail `obsidian/kacho/KAC/KAC-<N>.md` (status, repos, PRs, затронутые сущности vault, DoD)

### Сценарий S4-04: kube-ovn status-field version-pin + CRD/RBAC install (regression/setup) [req: finalizer-safety][req: CRD-schema]

**ID:** OP1-S4-04

**Given** in-use safety зависит от точного имени status-поля kube-ovn Subnet (версионно-зависимо), а первый собственный CRD оператора требует install + ClusterRole

**When** готовится реализация и развёртывание

**Then** имя in-use status-поля **выверено против установленной версии kube-ovn CRD** (прочитана CRD-схема развёрнутого kube-ovn в `kacho-deploy`; зафиксировано константой в коде + комментарием с версией) — не «на память»
**And** CRD `kachosubnets.kacho.io` и ClusterRole контроллера (S1-04) установлены там, где деплоится оператор (`kacho-deploy`, если CRD shipping туда); ветка `kacho-deploy` = `KAC-<N>` (см. заголовок)
**And** установка CRD не ломает существующий deploy оператора (mTLS/SA/webhook — S4-01/02 без регресса)

---

## Тестовая стратегия (envtest для egress-reconcile)

- **envtest (egress-controller)** — обязателен:
  - create `KachoSubnet` (N CIDR) → expect N child kube-ovn Subnet + N NAD с ownerRef+controller=true и stable-by-CIDR именами (S3-01/02/03).
  - remove CIDR из spec → expect именно тот child запрунен, остальные нетронуты; парный NAD удалён только со своей Subnet (S3-04).
  - delete `KachoSubnet` → controller-driven Terminating teardown free-child'ов + finalizer snap → GC завершает каскад (S3-05/S3-06a); in-use finalizer-path: degraded condition + requeue, child НЕ удалён пока выверенное in-use status-поле > 0, finalizer снимается в момент его обнуления (S3-06/S3-06a).
  - **in-use поле**: в envtest замокать/проставить выверенное status-поле kube-ovn Subnet (по версии установленной CRD) на child; отдельный кейс — пустой child (только gateway/excludeIps, без pod-аллокаций) НЕ считается in-use и штатно прунится (S3-06 assert).
  - shorthash: каноникализация эквивалентных CIDR-форм → одно имя; уникальность суффиксов в наборе; имя ≤ 63 символов с усечением `<name>`, не хеша (S3-02a).
  - prune-fail-safe: список с битым CIDR не удаляет child'ы валидных CIDR (S3-08).
  - пустые/битые CIDR → ноль/partial child + degraded condition (S3-07/08).
  - повторный reconcile → no-op (S3-09).
- **unit** — ingress diff-логика (create/update/delete CR против набора Kachō Subnet), stable-by-CIDR `name(cidr)` хелпер (каноникализация + 63-char bound + уникальность суффикса), desired/actual set-diff (включая fail-safe при битом CIDR), dual-stack→single-family split (решение A); через fake client / mock upstream.
- **TDD** — для каждого сценария: падающий тест (RED, по правильной причине) ДО кода → GREEN. В отчёте показать пару RED→GREEN.
- Финальная верификация: `go test ./... -race` + `golangci-lint run` + envtest зелёные.

---

## Не-цели (explicit non-goals)

1. **ns-operator (kacho-project-operator) не трогаем** — namespace-lifecycle и
   iam fan-out остаются как есть; RBAC на Namespace у vpc-operator — read-only.
2. **Контракт Kachō не меняется** — никаких новых RPC/полей в kacho-vpc/kacho-proto;
   `KachoSubnet` spec ТОЛЬКО зеркалит существующий Kachō Subnet (Kachō по-прежнему
   без Watch — поллинг сохраняется).
3. **Никакого combine-into-dual-stack** — решение A зафиксировано: один CIDR = одна
   single-family kube-ovn Subnet; `protocol=Dual`/`"v4,v6"` НЕ используется.
4. **mTLS-транспорт и FGA-registration не переписываем** — SEC-G-поведение
   (`upstream.Dial`/`DialIAM`, per-edge `enable`, principal-инжект, least-priv SA)
   сохраняется без регресса.
5. **Index-based именование child'ов запрещено** — только stable-by-CIDR
   `<name>-<shorthash(cidr)>` (перестановка/добавление CIDR не должна вызывать
   ложный prune+recreate соседних child'ов).
6. **kube-ovn IPAM / NIC-webhook fixed-IP** — вне scope этой подфазы (остаётся как
   есть; OP1 — только Subnet→child материализация и её deletion-sync).
7. **SecurityGroup→ACL / RouteTable→staticRoutes / Gateway→VpcNatGateway / Address→fixed-IP**
   — boundary (см. `MAPPING.md`), не входят в OP1.

---

## Трассировка требований → сценарии

| Требование | Сценарии |
|---|---|
| CRD schema (cluster-scoped, spec-поля, DeepCopy, RBAC) | S1-01, S1-02, S1-03, S1-04 |
| ownerRef cluster-owner → оба child-типа + controller=true | S1-02, S3-03, S3-05 |
| ingress 1:1 reflect (create/update/delete CR) | S2-01, S2-02, S2-03, S2-05 |
| egress 1→N per-CIDR single-family materialization | S3-01, S3-07, S3-10 |
| stable-by-CIDR naming (НЕ index-based) | S3-02 |
| stable-naming: каноникализация CIDR + 63-char DNS-bound + коллизионная ширина хеша | S3-02a |
| element-level CIDR removal → prune этого child (+ NAD парно) | S3-04 |
| whole-delete → controller-driven Terminating teardown + cascade via ownerRef | S3-05, S3-06a |
| finalizer + in-use safety (не удалять CIDR с реальными pod-аллокациями; gateway/excludeIps не в счёт) | S3-06, S3-06a |
| in-use status-поле kube-ovn выверено против версии CRD (не хардкод) | S3-06, S4-04 |
| teardown в Terminating: free child controller-driven, in-use блокирует finalizer | S3-06a |
| prune-fail-safe при битом CIDR (не удалять child валидных CIDR) | S3-08 |
| NAD прунится только with/after своей Subnet (нет независимого NAD-prune) | S3-04, S3-06 |
| dual-stack = A (один CIDR = одна single-family Subnet) | S3-01, S3-10 |
| idempotency (ingress + egress) | S2-04, S3-09 |
| невалидный/пустой ввод (CIDR/spec) | S1-03, S3-07, S3-08 |
| non-goal: ns-operator не тронут | S4-01 |
| non-goal: mTLS/FGA не регрессируют (SEC-G) | S4-02 |
| trail (vault edge/resource/KAC) | S4-03 |
| kube-ovn status-field version-pin + CRD/RBAC install (kacho-deploy) | S4-04 |
| ticket/branch binding (ban #1, pre-APPROVAL gate) | заголовок §«Привязка к тикету» |
