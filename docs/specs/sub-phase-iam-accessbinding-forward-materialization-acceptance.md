# Sub-phase IAM-FMB (AccessBinding forward-fast-path materialization) — Acceptance

> **Статус:** ✅ APPROVED (`acceptance-reviewer`, 2026-07-23; gate ban #1 ОТКРЫТ — можно код). Ground-truth сверен: все load-bearing claims подтверждены реальным кодом.
> **Planning-note'ы ревьюера (non-blocking, учесть в плане; ре-ревью НЕ нужен):**
> 1. DoD throughput-гейт назвать ЯВНО heavy-burst коллекции `rbac-subject-channel-equivalence` +
>    `rbac-visibility-set` (обе реальны в `services/iam/tests/newman/cases/`) — НЕ лёгкую
>    `grant-check-propagation` (иначе implementer false-green'ит по лёгкой). Проверить/заменить
>    `access-binding-redesign` (коллекции с таким именем нет → вероятно `iam-rbac-subjects`).
> 2. §5 матрица: IAM-FMB-13 (group#member) / IAM-FMB-14 (email pending-intent) — закрепить каждый
>    за ОДНИМ конкретным artifact-классом (integration ЛИБО newman), не either-or.
> **Дата:** 2026-07-23
> **Ревьюер:** `acceptance-reviewer`
> **Эпик/тикет:** KAC-\<N\> (завести до старта кода; тип `fix`/`refactor` — throughput-регрессия; репо-локально — `kacho-iam`)
> **Repos (порядок build-графа):** `kacho-iam` (materialization-path) → `kacho-deploy` (redeploy REF_IAM) →
> `kacho-workspace` (docs/vault). **Proto/gateway НЕ затронуты** — `AccessBindingService.Create` wire-контракт
> НЕ меняется (оптимизация целиком внутри iam-реконсайлера), поэтому `proto-api-reviewer`/`api-gateway-registrar`
> в цикле НЕ участвуют.
> **Формат:** Given-When-Then (только markdown — без кода)
> **Нормативка (не дублируется в тело — ссылки):**
> - `.claude/rules/data-integrity.md` §«Authz-материализация owner-доступа — flat Contract-A (eventually-consistent)»
>   (все инварианты материализации), §«Within-service инварианты — ТОЛЬКО на DB-уровне» (advisory-lock, идемпотентный
>   additive UPSERT — ban #10), §«Group#member — outbox-emit + EC», §«grant-by-email / UserInvitation — pending-intent».
> - `.claude/rules/api-conventions.md` §«Форма ресурса — flat + Operations» (`Operation.done` = durability предмета,
>   НЕ видимость downstream side-effect — non-negotiable), §«Error-format» (коды + `reason`-token).
> - `.claude/rules/security.md` §«AuthN+AuthZ ВЕЗДЕ» (per-RPC Check на обоих листенерах, fail-closed).
> - `.claude/rules/testing.md` §«e2e-инварианты» (read-your-writes bounded client-retry), §«Newman e2e — EC-дисциплина»,
>   §«Параллельный newman — слоёная parallel-safety» (throughput материализации grant — слой 1).
> - `docs/specs/02-data-model-and-conventions.md` §14 (коды ошибок).

---

## 0. Обзор

`AccessBinding.Create` под flat-моделью (Contract-A) материализует per-object grant-tuple'ы субъекта
**НЕ синхронно в момент коммита binding'а**, а через **реконсайлер**: `Operation.done` означает, что строка
binding'а **durable** (закоммичена вместе с fga_outbox/audit/reconcile-событиями в одной writer-tx, ban #10),
а per-object доступ (`v_get`/`v_list`/`v_update`/… + tier-tuple на каждом объекте в scope, матчащемся правилами
роли) материализуется **eventually-consistent** post-commit-проходом реконсайлера. Read-your-writes окно
закрывается **bounded client-retry** на кратком `403`/`404`, а НЕ серверным confirm-барьером (ban #9 — иначе
phantom-binding; см. `api-conventions.md` и `data-integrity.md`).

**Проблема (throughput-регрессия).** Сегодня этот post-commit-проход — **FULL-path** `ReconcileBinding`:
он берёт **EXCLUSIVE** per-binding advisory-lock + `FOR UPDATE` на строке binding'а и делает **O(scope)**
пересчёт desired-set с **delete-stale**-диффом. EXCLUSIVE-lock существует **ради exactly-once под Role.Update
fan-out** (конкурентная ре-материализация ТОГО ЖЕ binding'а при смене role-rules, где delete-stale обязан не
гоняться сам с собой). Но на **mass-binding burst** (тысячи `AccessBinding.Create` back-to-back — grant-волна
роли на аккаунт/множество субъектов) FULL-path серии O(scope)-пересчётов под EXCLUSIVE-локами **не поспевают**:
grant-материализация отстаёт, read-your-writes окно **превышает даже щедрый client-retry budget** → субъект
получает `403 «lacks relation»` на СВОём только что выданном доступе, а stress-коллекции зеленеют только через
**cap-widen** (искусственное расширение retry-бюджета) — что маскирует, а не решает bottleneck. Это НЕ
«отсутствует fast-path», а **намеренно-full-path**, чей EXCLUSIVE-lock тут избыточен.

**Решение (предмет acceptance).** Ввести **forward-fast-path для AccessBinding-CREATE** — точный аналог уже
залендённого resource-forward `ReconcileObjectForward` (см. §1.2 D-0) + leaf sync-registrar-паттерна, распространённый
на **сам binding**. Create — это **чисто ADDITIVE** материализация: binding **новый**, materialized-members у него
ещё **нет**, значит **нечего delete-stale-ить**. Поэтому create-путь берёт **SHARE** advisory-lock (не EXCLUSIVE),
**без** `FOR UPDATE` row-lock, пишет **только-недостающие** per-object member'ы+tuple'ы (write-missing-only,
идемпотентно) — post-commit best-effort — а **durable fga_outbox**-enqueue (в той же forward-writer-tx, ban #10) +
периодический sweep остаются **at-least-once backstop**. **FULL-path EXCLUSIVE `ReconcileBinding` ОСТАЁТСЯ** для
Role.Update fan-out (delete-stale требует EXCLUSIVE) и для sweep-backstop. SHARE ∥ SHARE не конфликтуют → тысячи
create-forward'ов идут **конкурентно**; SHARE ⊥ EXCLUSIVE → create-forward и конкурентный FULL-проход того же
binding'а **берут очередь** (корректность delete-stale не рвётся).

**Наблюдаемая поверхность.** Материализация — iam-**внутренний** механизм; его контракт наблюдаем на **authz-
enforcement**-поверхности: gateway per-RPC `InternalIAMService.Check(subject, permission, resource)` →
`{allowed}`, доступ субъекта к целевому ресурсу (`GET`/`Update`/`List` через api-gateway → `200`/`403`), и
видимость самого binding'а (`AccessBindingService.Get`/`ListByScope`). Все Given-When-Then-утверждения ниже
сформулированы против ЭТОЙ поверхности; механизм реконсайлера (SHARE/EXCLUSIVE, additive, fga_outbox) назван лишь
чтобы зафиксировать, КАКОЙ наблюдаемый инвариант пинит сценарий — сами предикаты нормативно живут в
`data-integrity.md` §«Authz-материализация» и здесь НЕ дублируются.

Заказчик к approve контракта не подключается — он проверяет только финальный smoke/e2e (шаг 7:
`make e2e-test` / mega-rbac stress newman без cap-widen).

---

## 1. Ground truth + зафиксированные дизайн-решения

### 1.1 Текущее состояние (что уже есть — не переписываем)

- **`AccessBindingService.Create`** (public :9090) — async → `Operation`. `doCreate` в ОДНОЙ writer-tx:
  INSERT binding + subjects; эмит **binding-lifecycle** tuple'ов (hierarchy parent-pointer + scope-self tier
  для legacy permissions-only роли) в `fga_outbox` + запись их в `access_binding_emitted_tuples` (ledger,
  source=`binding`); `subject_change_outbox`; `audit_outbox`; `EmitReconcileEvent("iam.accessBinding", id)` —
  всё atomically (ban #10), commit. Эти tuple'ы **DURABLE на `Operation.done`**.
- **Post-commit (best-effort, non-fatal):** `ReconcileBinding(created.ID)` — **FULL-path**, материализует
  per-object membership ЭТОГО binding'а (ARM_ANCHOR/ARM_NAMES/ARM_LABELS-матчи → per-object `v_*`+tier). Это и
  есть O(scope)+EXCLUSIVE bottleneck. Плюс `ReconcileObject("iam.accessBinding", id)` — материализует доступ
  ДРУГИХ binding'ов (owner `*.*`, account-admin) НА новый binding-объект.
- **Реконсайлер** (`reconcile.Reconciler`) уже несёт **обе** дисциплины: `ReconcileBinding` (FULL, EXCLUSIVE
  advisory-lock + `FOR UPDATE`, delete-stale-дифф) и — для **ресурсов** — `ReconcileObjectForward` (ADDITIVE,
  **SHARE** advisory-lock `AcquireBindingLockShared`, `LoadBindingUnlocked`, write-missing-only, без delete-stale).
- **Sync-FGA read-after-write closer** — post-commit best-effort прямой OpenFGA-write собранных ACTIVE-tuple'ов
  (`applyAfterCommit`); durable `fga_outbox`-enqueue ВСЕГДА в writer-tx (ban #10); async-drainer той же строки —
  идемпотентный no-op (`already_exists ⇒ applied`).
- **Role.Update fan-out** — `RoleTupleReconciler` (binding-level tier-дельта) + `RoleMembershipFanout` (per-member
  ретиринг по rule_fp), **в той же writer-tx что и UPDATE роли** (atomic, ban #10), с delete-stale по ledger.
- **`Operation.done` = durability предмета мутации, НЕ видимость downstream side-effect** (non-negotiable,
  `api-conventions.md`). Confirm-gate на видимость owner/grant-tuple **запрещён** (ban #9 — phantom-binding).

### 1.2 Дизайн-решения IAM-FMB (locked)

- **D-0. Паттерн-прецедент — resource `ReconcileObjectForward` + leaf sync-registrar.** IAM-FMB **распространяет
  тот же, уже залендённый и отревьюенный** additive-forward-паттерн (SHARE-lock, write-missing-only, sync
  post-commit best-effort + fga_outbox/sweep backstop) с **freshly-registered объекта** на **freshly-created
  binding**. Никакой новой концепции материализации не вводится — вводится **create-специфичная ADDITIVE-ветка**
  binding-реконсайла.
- **D-1. Create-forward — ADDITIVE, SHARE-lock, без `FOR UPDATE`, write-missing-only.** На create-happy-path
  binding **новый** ⇒ current-members пуст ⇒ delete-stale-дифф **не нужен**. Forward материализует desired ACTIVE
  per-object member'ы **аддитивно** (UPSERT member + `EmitTupleWrite` в `fga_outbox` + `RecordEmittedTuples` в
  ledger, всё в forward-writer-tx, ban #10), берёт **SHARE** advisory-lock (не EXCLUSIVE) и **не** берёт
  `FOR UPDATE` на строке binding'а. Все шаги **идемпотентны** (UPSERT / `INSERT … ON CONFLICT` / drainer
  `already_exists⇒applied`) ⇒ повтор — безопасный no-op.
- **D-2. FULL-path EXCLUSIVE `ReconcileBinding` ОСТАЁТСЯ** — для (a) **Role.Update fan-out** (delete-stale по
  ledger при смене role-rules требует EXCLUSIVE — конкурентные пересчёты не должны стереть чужой just-written
  member), (b) **периодического sweep** (defense-in-depth), (c) **defensive-delegation** (см. D-4). Forward
  **НЕ** применяется к fan-out.
- **D-3. Lock-выбор — SHARE, не «no lock» (нормативно `data-integrity.md`).** SHARE ∥ SHARE не конфликтуют →
  N конкурентных create-forward'ов идут параллельно (throughput-свойство). SHARE ⊥ EXCLUSIVE → create-forward и
  конкурентный FULL-проход **того же** binding-key взаимно-исключаются (берут очередь) → их row-lock'и не
  пересекаются (нет 40P01-deadlock: FK-child `FOR KEY SHARE` INSERT'ы форварда не скрещиваются с FULL-path
  `SELECT … FOR UPDATE`), и FULL delete-stale не гоняется с mid-write форвардом. Advisory-lock'и берутся в
  **ascending binding-id order** (нет ABBA). Всё — **на DB-уровне** (ban #10, не software check-then-act).
- **D-4. DELETE-STALE guard (create-only).** Forward **аддитивен** — не умеет delete-stale. Поэтому он валиден
  **только** для binding'а **без** materialized-members (истинный create). Если у binding'а **уже есть** member'ы
  (реплей create / вызов на существующем binding'е) — forward **прозрачно делегирует** в FULL `ReconcileBinding`
  (EXCLUSIVE + delete-stale). Дешёвая one-indexed-read проверка на create-hot-path пуста ⇒ остаётся на fast-пути.
- **D-5. Backstop-огибающая (correctness envelope).** Forward — **оптимизация**, НЕ замена. At-least-once
  гарантируют: **(a)** per-object member-tuple'ы **durable** в `fga_outbox` внутри forward-writer-tx (ban #10) →
  async-drainer применит их, даже если post-commit sync-FGA-write не удался; **(b)** периодический **sweep**
  (FULL `ReconcileBinding` по всем label/anchor-binding'ам) re-конвергирует любой member, что forward пропустил.
  Пропущенный/упавший forward → EC-сходимость через (a)+(b). `Operation.done` **не ждёт** видимость (ban #9).
- **D-6. Функциональная эквивалентность (byte-identical grant).** Per-object verdict у forward и FULL —
  **общий** (одна decision-точка `desiredMemberForObject`): tuple-set объекта **byte-identical**. Forward не
  расширяет и не сужает grant относительно FULL — он лишь материализует **раньше и без EXCLUSIVE-сериализации**.
  REJECTED-containment (cross-scope) member'ы forward **не** пишет (additive-only пишет только ACTIVE-grant);
  их + audit оставляет FULL-backstop.
- **D-7. Scope IAM-FMB — только own-membership binding-create.** Меняется post-commit-вызов `ReconcileBinding(id)`
  на create-пути → его ADDITIVE forward-вариант. Существующий `ReconcileObject("iam.accessBinding", id)` (доступ
  ДРУГИХ binding'ов на новый binding-объект) уже имеет свой resource-forward (`ReconcileObjectForward`) и **вне**
  предмета этой под-фазы (может быть переключён на forward отдельно, но не required здесь). enforcement/read-path
  Check НЕ трогается.

---

## 2. Given-When-Then сценарии

> **Трассировка:** `ID` вида `IAM-FMB-NN` → имена integration-тестов (`TestReconcileBindingForward_NN_*`,
> testcontainers) и newman-кейсов (`iam-fmb-*` / расширение `iam-authz-grant-check-propagation`). Единый субъект-
> нотейшн: `Subj = user:<usr-…>`; целевой ресурс `Res`; «в ограниченном окне» = within bounded client-retry budget
> (~10s, `testing.md`), закрытый `retry_until_authorized`, **без cap-widen**.

### Группа A — Happy path / throughput (positive)

#### Сценарий IAM-FMB-01: Forward материализует grant свежего binding'а быстро и корректно

**ID:** `IAM-FMB-01`

**Given** роль `R` с ARM_ANCHOR-правилом `compute.instance:{get,update}` на project-scope
**And** в project `P` (аккаунт `A`) уже зарегистрирован ресурс `compute.instance:iX` (mirror-строка присутствует)
**And** субъект `Subj` пока НЕ имеет доступа к `iX` (`Check(Subj, compute.instance.get, iX) → {allowed:false}`)

**When** grant-authority-holder вызывает `AccessBindingService.Create` c payload:
  - `subjects[0]` = `{type: SUBJECT_TYPE_USER, id: <Subj>}`
  - `roleId` = `<R>`
  - `resourceType` = `project`, `resourceId` = `<P>`
**And** клиент поллит `OperationService.Get(op.id)` до `done=true`

**Then** `Operation.done=true` и `Operation.error` пуст (binding durable — предмет мутации закоммичен)
**And** в ограниченном окне `Check(Subj, compute.instance.get, iX) → {allowed:true}`
**And** `Check(Subj, compute.instance.update, iX) → {allowed:true}` **and** производный `compute.instance.delete` тоже
  `{allowed:true}` (leaf-editor co-materialization — тот же verb-набор, что дал бы FULL-path)
**And** `AccessBindingService.Get(op.metadata.accessBindingId)` отдаёт binding с заполненными `id`/`createdAt`/полями
**And** материализация прошла **forward-fast-path** (SHARE-lock, без EXCLUSIVE-сериализации) — доступ виден в окне
  **без** cap-widen retry-бюджета.

---

#### Сценарий IAM-FMB-02: Burst — N binding'ов back-to-back, каждый grant в ограниченном окне

**ID:** `IAM-FMB-02`

**Given** роль `R` (ARM_ANCHOR `compute.instance:{get}` на account-scope) и ресурс `compute.instance:iX` в аккаунте `A`
**And** N (≥ 50) РАЗНЫХ субъектов `Subj_1..Subj_N`

**When** grant-authority-holder создаёт N `AccessBinding` **back-to-back** (`Create(Subj_k, R, account:A)` для каждого k)
**And** для каждого k клиент поллит `Operation` до `done` и затем `Check(Subj_k, compute.instance.get, iX)`

**Then** каждый `Operation.done=true`, `error` пуст
**And** для **каждого** k `Check(Subj_k, …get, iX) → {allowed:true}` **в ограниченном окне** — bounded client-retry
  **НЕ исчерпан** ни для одного субъекта (throughput: SHARE-forward'ы не сериализуются на per-binding EXCLUSIVE-локе)
**And** ни один субъект НЕ получает устойчивый `403 «lacks relation»` на своём собственном свежем grant'е
**And** прогон повторяем идемпотентно (`{{runId}}`-суффиксы субъектов; повторный прогон не коллизит `AlreadyExists`).

> `# verifies` throughput-регрессию §0 — RED-репро (FULL-path под burst) исчерпывает retry и требует cap-widen;
> GREEN (forward) — зелено на дефолтном бюджете.

---

#### Сценарий IAM-FMB-03: Функциональная эквивалентность forward ≡ FULL (byte-identical grant)

**ID:** `IAM-FMB-03`

**Given** две идентичные grant-конфигурации `G_fwd` и `G_full` (одинаковая роль `R`, scope, набор in-scope
  объектов `{iX, iY}`, разные субъекты `Subj_fwd`/`Subj_full`)

**When** `G_fwd` материализуется create-**forward**-путём, а `G_full` — принудительно **FULL** `ReconcileBinding`
  (напр. через sweep-backstop / defensive-delegation D-4)

**Then** итоговый набор `{allowed}`-вердиктов **совпадает** для обоих субъектов на всех объектах и verb'ах:
  `Check(Subj_fwd, v, o) == Check(Subj_full, v, o)` для `v ∈ verbs(R)`, `o ∈ {iX, iY}`
**And** forward **не** гранит ничего сверх FULL (нет over-grant) и **не** теряет ни одного grant относительно FULL
**And** cross-scope-объект (в mirror'е, но НЕ contained в scope) НЕ гранится **ни** forward-, **ни** FULL-путём
  (REJECTED-containment; forward его просто пропускает, audit оставляет FULL-backstop).

---

### Группа B — Concurrency / exactly-once (DB-уровень, ban #10)

#### Сценарий IAM-FMB-04: Exactly-once — конкурентный forward + FULL на ОДНОМ binding-key

**ID:** `IAM-FMB-04`

**Given** binding `B` (роль `R` с ARM_ANCHOR `compute.instance:{get,update}`, scope project `P`, in-scope
  `{i01..i0M}`), создаваемый forward-путём
**And** конкурентно на ТОМ ЖЕ `B` инициируется **FULL** `ReconcileBinding(B)` (sweep-backstop / Role.Update-триггер)

**When** create-forward(`B`) **и** FULL `ReconcileBinding(B)` выполняются **параллельно** (повторить K итераций для
  вымывания interleavings)

**Then** ни один проход НЕ падает и НЕ упирается в deadlock (`40P01`) — SHARE ⊥ EXCLUSIVE берут очередь на
  per-binding advisory-lock (`data-integrity.md`), row-lock'и не скрещиваются
**And** итоговое materialized-состояние = **desired-set** роли `R` над `{i01..i0M}`: `Check(Subj, get/update, i0k)
  → {allowed:true}` для каждого k
**And** **ровно один** member/ledger-tuple на `(rule_fp, object)` — нет дублей (additive UPSERT + ledger PK-dedup);
  наблюдаемо: OpenFGA-batch НЕ отвергается `cannot_allow_duplicate_tuples_in_one_request`, grant когерентен
**And** нет lost-update: ни forward, ни FULL не стирает just-written member другого (in-mirror объект FULL-проходом
  как «stale» не снимается — desired-set включает его).

> **Integration-тест обязателен** (testcontainers, concurrent goroutines, `-race`) — ban #12 / `data-integrity.md`
> §«Integration-тест с concurrent goroutines на спорный путь».

---

#### Сценарий IAM-FMB-05: create-vs-concurrent-revoke race (Role.Update снимает verb V)

**ID:** `IAM-FMB-05`

**Given** роль `R` c verb-набором `{get, update}` на `compute.instance` (ARM_ANCHOR, scope `P`), объект `iX`
**And** binding `B` (`Subj`, `R`, `project:P`) создаётся **forward**-путём
**And** конкурентно `RoleService.Update(R)` **удаляет** verb `update` из `R` (fan-out delete-stale, FULL-path)

**When** create-forward(`B`) и `Role.Update(R)` (со своим fan-out) выполняются параллельно

**Then** после того как обе операции осели (ограниченное EC-окно), materialized-состояние **когерентно с ФИНАЛЬНЫМ
  определением роли**: `Check(Subj, compute.instance.update, iX) → {allowed:false}` (verb `update` снят), а
  `Check(Subj, compute.instance.get, iX) → {allowed:true}` (verb `get` остался) — **независимо от interleaving'а**
**And** НЕТ навсегда-залипшего `update`-tuple: если forward материализовал `update` ДО того как revoke сел, то
  FULL-path fan-out delete-stale + sweep снимают его в ограниченном окне (SHARE ⊥ EXCLUSIVE гарантируют, что forward
  и fan-out не рвут друг друга)
**And** нет deadlock/ошибки ни в одном проходе.

> **Integration-тест обязателен** (concurrent, `-race`) — второй спорный путь класса ban #12.

---

### Группа C — Backstop / idempotency (eventual-consistency, ban #9)

#### Сценарий IAM-FMB-06: Backstop — sync forward упал, grant материализуется всё равно

**ID:** `IAM-FMB-06`

**Given** binding `B` создаётся, но post-commit **sync-FGA-write** форварда НЕ проходит (OpenFGA недоступен/timeout
  на momentе post-commit best-effort записи)

**When** клиент поллит `Operation` до `done`

**Then** `Operation.done=true`, `error` пуст — **`Operation.done` НЕ ждёт** видимость grant-tuple'а (ban #9:
  предмет = «создать binding», не «распространить FGA-tuple»; никакого confirm-gate → нет phantom-binding)
**And** per-object member-tuple'ы **durable** в `fga_outbox` (эмитированы в forward-writer-tx, ban #10) →
  async-drainer применяет их **at-least-once** → `Check(Subj, …, Res) → {allowed:true}` материализуется в
  ограниченном окне (EC-сходимость), **без** участия sync-пути
**And** периодический sweep (FULL `ReconcileBinding`) — вторичный backstop для любого пропущенного member'а
**And** субъект в кратком pre-drain-окне может получить transient `403`/`404` на своём свежем grant'е — это
  read-your-writes-лаг, закрываемый **bounded client-retry** на клиенте, а НЕ серверным барьером.

---

#### Сценарий IAM-FMB-07: Идемпотентность — повтор forward = no-op, exactly-once

**ID:** `IAM-FMB-07`

**Given** binding `B` уже полностью материализован (create-forward отработал, либо FULL-backstop сошёлся)

**When** forward-проход для `B` (или его объектов) выполняется **повторно** (drainer-retry / overlap forward+FULL
  backstop / defensive повторный вызов)

**Then** повтор — **безопасный no-op**: write-missing-only не дублирует member'ов — **ровно одна** member-строка и
  **ровно одна** ledger-строка на `(rule_fp, object)` (наблюдаемо: grant не «удваивается», OpenFGA-batch не
  отвергается на дубликате)
**And** `Check`-вердикты не меняются от повтора (grant стабилен)
**And** pre-existing tuple в batch'е не роняет весь batch (`already_exists ⇒ applied`).

> **Integration-тест обязателен** (testcontainers, idempotency — двойной forward одного binding'а → 1 member/1 ledger).

---

### Группа D — Role.Update fan-out не сломан / revoke-стойкость

#### Сценарий IAM-FMB-08: Role.Update fan-out delete-stale по-прежнему корректен (revoke sticks)

**ID:** `IAM-FMB-08`

**Given** роль `R` (verb `{get, update}` на `compute.instance`), у неё M ACTIVE-binding'ов, каждый материализовал
  `update` на своих in-scope объектах

**When** `RoleService.Update(R)` **удаляет** verb `update` (без гонки с create — чистый fan-out)

**Then** для **всех** M binding'ов `update`-tuple'ы **сняты** (grant-removal sticks): `Check(Subj_k,
  compute.instance.update, o) → {allowed:false}` для каждого затронутого binding'а/объекта
**And** `get` остался `{allowed:true}` (снимается ровно снятый verb, не больше)
**And** delete-stale выполнен **FULL-path EXCLUSIVE** (fan-out) — forward-fast-path к fan-out **НЕ применён**
  (регрессия-guard: additive-forward не может delete-stale, поэтому fan-out обязан остаться на FULL-пути).

---

#### Сценарий IAM-FMB-09: Revoke-стойкость — Delete AccessBinding снимает материализованные tuple'ы

**ID:** `IAM-FMB-09`

**Given** binding `B` (`Subj`, `R`, `project:P`), grant материализован forward-путём (`Check(Subj, get, iX)
  → {allowed:true}`)

**When** клиент вызывает `AccessBindingService.Delete(B)` и поллит `Operation` до `done`

**Then** `Operation.done=true`, `error` пуст
**And** в ограниченном окне `Check(Subj, compute.instance.get, iX) → {allowed:false}` — материализованные
  per-object tuple'ы **сняты** (revoke реплеит ledger — тот же ledger, что forward co-commit'ил; symmetric revoke),
  grant **НЕ залипает**
**And** revoke материализуется той же EC-дисциплиной (`Operation.done` не ждёт видимость снятия — ban #9).

---

#### Сценарий IAM-FMB-10: Defensive-delegation — forward на binding'е с уже-существующими member'ами → FULL

**ID:** `IAM-FMB-10`

**Given** binding `B`, у которого **уже есть** materialized-member'ы (не истинный create — реплей / повторный вызов
  на существующем binding'е)

**When** инициируется **create-forward** для `B`

**Then** forward **прозрачно делегирует** в **FULL** `ReconcileBinding(B)` (EXCLUSIVE + delete-stale) — аддитивный
  путь для не-нового binding'а **не** применяется (иначе потерялся бы delete-stale)
**And** наблюдаемо: если desired-set `B` изменился (member выпал), выпавший grant **снимается** (`Check → {allowed:
  false}`), а не остаётся stale — delete-stale-корректность сохранена (D-4).

---

### Группа E — Negative / edge (материализация НЕ должна ломать существующую семантику)

#### Сценарий IAM-FMB-11: Negative — отвергнутый Create НЕ материализует ничего

**ID:** `IAM-FMB-11`

**Given** различные невалидные `Create`-запросы

**When** клиент вызывает `AccessBindingService.Create` c:
  - **(a)** malformed `resourceId` (напр. `"project:!!"`) → sync `INVALID_ARGUMENT «invalid access binding scope
    id '<x>'»` (первым стейтментом, до Operation)
  - **(b)** `roleId` несуществующей роли → `Operation.error` `FAILED_PRECONDITION «Role <id> not found»`
    (FK-RESTRICT backstop; binding НЕ создан — tx rollback)
  - **(c)** mis-scoped роль (роль не assignable на данный scope) → sync `FAILED_PRECONDITION` (structural gate
    `IsRoleAssignable`, до Operation)
  - **(d)** `GLOBAL(cluster)-scope + ARM_ANCHOR(all)` для не-cluster-admin роли → sync `INVALID_ARGUMENT`
    (unbounded per-object материализация запрещена — до Operation/tuple)

**Then** для **каждого** случая **никакой** per-object grant НЕ материализуется (forward **не запускается** —
  либо запрос отвергнут sync до Operation, либо Operation завершается `error` с rollback): `Check(Subj, …, Res)
  → {allowed:false}` остаётся
**And** коды/тексты — точно из `api-conventions.md`/спеки §14 (fail-closed).

---

#### Сценарий IAM-FMB-12: Edge — пустой scope / нет матчащихся объектов

**ID:** `IAM-FMB-12`

**Given** binding `B` (роль `R` c ARM_ANCHOR на `compute.instance`), но в scope `P` **нет** ни одного
  зарегистрированного `compute.instance` (mirror пуст для типа)

**When** create-forward(`B`) отрабатывает post-commit

**Then** forward материализует **ноль** per-object member'ов (нечего гранить сверх scope-anchor/hierarchy tuple'а),
  завершается **без ошибки** и **быстро** (bounded — не сканирует несуществующий scope)
**And** `Operation.done=true`, binding durable и Get-виден; per-object `Check` естественно `{allowed:false}` (нет
  объектов)
**And** когда позднее объект `iZ` регистрируется в `P`, его grant подхватывается **resource-forward'ом**
  (`ReconcileObjectForward` на mirror-событии) — вне предмета IAM-FMB, но должен продолжать работать (не-регрессия).

---

#### Сценарий IAM-FMB-13: Edge — group#member subject (EC-emit, НЕ co-commit)

**ID:** `IAM-FMB-13`

**Given** группа `G` c членом-пользователем `Usr`, роль `R`, объект `iX` в scope `P`

**When** grant-authority-holder вызывает `Create` c `subjects[0] = {type: SUBJECT_TYPE_GROUP, id: <G>}` и поллит
  `Operation` до `done`

**Then** `Operation.done=true`; forward материализует per-object `v_*`-tuple'ы, keyed на **userset**
  `group:<G>#member` (subject-независимая hierarchy + per-subject role-relation) — те же tuple'ы, что дал бы FULL
**And** членство `Usr ∈ G` резолвится **той же EC-дисциплиной** (`Group#member` — outbox-emit + reconciler, **НЕ**
  co-commit; `data-integrity.md` §B14) → в ограниченном окне `Check(user:<Usr>, compute.instance.get, iX)
  → {allowed:true}`
**And** `Operation.done` члена/binding'а **НЕ ждёт** видимость member-tuple (ban #9) — read-your-writes через
  bounded client-retry.

---

#### Сценарий IAM-FMB-14: Edge — grant-by-email pending-intent (не матчит enforcement до login-remap)

**ID:** `IAM-FMB-14`

**Given** субъект-`EMAIL` `alice@example.com`, ещё НЕ логинившийся (нет `usr-…`)

**When** grant-authority-holder вызывает `Create` c email-subject'ом на роль `R`/scope `P`

**Then** `Operation.done=true` (binding durable); grant хранится как **pending email-grant intent** — tuple keyed
  на email **НЕ матчит** enforcement (который резолвит `usr-…`), поэтому до login `Check` для будущего `usr-…`
  → `{allowed:false}` (pre-login — корректно, не залипший фантом)
**And** на **первом OIDC-login** (invitation-accept) reconciler ремапит intent в `usr-<id>`-tuple → в ограниченном
  окне доступ материализуется (`data-integrity.md` §B15)
**And** `revoke-before-login` (Delete binding'а до логина) **очищает** pending-intent — доступ НЕ материализуется
  после логина (не залипает)
**And** серверный confirm-барьер отсутствует (EC-окно, bounded client-retry; ban #9).

---

#### Сценарий IAM-FMB-15: Edge — cross-service dangling target (ацикличность, graceful)

**ID:** `IAM-FMB-15`

**Given** binding на `resourceType/resourceId`, ссылающийся на ресурс **другого сервиса** (opaque soft-ref, без FK,
  ban #8), которого нет в mirror'е (owner не зарегистрировал / удалён)

**When** клиент вызывает `Create` и поллит `Operation` до `done`

**Then** binding **создаётся** — IAM **НЕ** делает peer-validate target'а на create-пути (нет ребра iam→compute/vpc
  — это был бы цикл; материализация читает **same-DB** `resource_mirror`, а не зовёт владельца → ацикличность
  holds)
**And** forward читает mirror: dangling-target ⇒ **ноль** per-object member'ов материализуется (объекта в mirror'е
  нет) — **graceful**, без ошибки/паники, без deadlock
**And** когда/если target позднее регистрируется в mirror'е, доступ подхватывается resource-forward'ом (не-регрессия,
  вне предмета IAM-FMB).

---

## 3. Out-of-scope (явно НЕ входит в IAM-FMB)

- **Rewrite Role.Update fan-out на forward.** `RoleTupleReconciler` / `RoleMembershipFanout` **остаются FULL-path
  EXCLUSIVE** (delete-stale обязателен) — D-2/D-8. Forward к fan-out не применяется.
- **Изменение enforcement/read-path Check.** Gateway per-RPC `InternalIAMService.Check`, `InternalAuthorizeService`,
  `ListObjects`, listauthz — **не трогаются**. Меняется только **write/materialization**-путь.
- **Переключение `ReconcileObject("iam.accessBinding", id)`** (доступ ДРУГИХ binding'ов на новый binding-объект) на
  forward — у него уже есть resource-forward; отдельная возможная оптимизация, НЕ required здесь (D-7).
- **Proto/gateway/UI изменения.** `AccessBindingService.Create` wire-контракт неизменен; новых RPC/полей нет.
- **Изменение confirm-gate / введение server-side visibility-барьера.** Запрещено (ban #9) — модель остаётся
  eventually-consistent + bounded client-retry.
- **Sweep-переработка / TTL-expiry / concurrency-model реконсайлера** сверх ADDITIVE-create-ветки.
- **Устранение read-your-writes окна как такового** (окно by-design; закрывается на клиенте, не сервером).

---

## 4. Definition of Done (каждый пункт — гейт merge)

- [ ] **TDD RED→GREEN** (ban #12): падающие тесты написаны и прогнаны ДО кода; в PR — пара RED→GREEN.
- [ ] **Integration-тесты** (testcontainers Postgres 16, `internal/repo/kacho/pg/*integration_test.go`, под `-race`):
  - **exactly-once concurrency** — IAM-FMB-04 (forward ∥ FULL на одном binding-key: no deadlock, desired-set,
    1 member/1 ledger, no lost-update) **и** IAM-FMB-05 (create-vs-concurrent-revoke: финал когерентен финальной
    роли, no stuck tuple);
  - **idempotency** — IAM-FMB-07 (двойной forward → ровно 1 member/1 ledger);
  - **функц-эквивалентность** — IAM-FMB-03 (forward ≡ FULL grant-set);
  - **defensive-delegation** — IAM-FMB-10 (binding с member'ами → FULL);
  - **fan-out не сломан** — IAM-FMB-08 (revoke через Role.Update sticks, forward к fan-out не применён).
- [ ] **Newman** (`tests/newman/cases/`, black-box через api-gateway): **≥1 happy** — grant fast под burst
  (IAM-FMB-02, расширение `iam-authz-grant-check-propagation` / новый `iam-fmb-grant-burst`) **+ ≥1 negative**
  (IAM-FMB-11 — отвергнутый Create не материализует; толерантность `403|400|404` per `testing.md`).
- [ ] **mega-rbac stress-коллекции зеленеют БЕЗ cap-widen** — grant-check-propagation / rbac-subjects / access-binding-
  redesign stress-прогон проходит на **дефолтном** bounded-retry-бюджете (не расширенном) после deploy — это
  главный acceptance-гейт throughput (§0). RED-репро на FULL-path обязано требовать cap-widen; GREEN — без.
- [ ] **Ревью ролями:** `system-design-reviewer` (**обязателен** — distributed concurrency: SHARE/EXCLUSIVE
  очерёдность, exactly-once под N-репликами, EC-backstop) → `✅ APPROVED`; `db-architect-reviewer` — **если** PR
  несёт миграцию (напр. индекс под create-hot-path member-peek; SHARE advisory-lock `AcquireBindingLockShared`
  уже существует — новой схемы, скорее всего, НЕ требуется) → `✅ APPROVED`; `go-style-reviewer` (clean-arch:
  реконсайлер зависит только от domain+портов, без pgx/grpc в use-case).
- [ ] **Observability:** forward-fail (post-commit sync-FGA-write) логируется (non-fatal, warn) с binding-id;
  backstop-путь (drainer/sweep) наблюдаем. Doc-truthfulness: комментарии совпадают с кодом (`architecture.md`).
- [ ] **Финальная верификация:** `go test ./services/iam/... -race` (ПОЛНЫЙ, не `-short` — testcontainers
  выполняются) + `golangci-lint run` + `govulncheck` зелёные; umbrella newman зелёный.
- [ ] **Trail:** обновить `obsidian/kacho/resources/iam-access-binding.md` (forward-mat материализация-путь) +
  `obsidian/kacho/KAC/rbac-explicit-model-2026.md`/новый KAC-trail; тикет `To do → In Progress → Test → Done`
  с артефактами (PR-URL, RED→GREEN лог, stress-newman без cap-widen).

---

## 5. Traceability

| ID | Класс | Наблюдаемая проверка (surface) | Тест-артефакт |
|---|---|---|---|
| IAM-FMB-01 | happy | Create→done→`Check{allowed:true}` на target в окне | integration + newman |
| IAM-FMB-02 | throughput | N burst → каждый `Check{allowed}` в bounded-retry без cap-widen | newman stress |
| IAM-FMB-03 | equivalence | forward `{allowed}`-set ≡ FULL `{allowed}`-set | integration |
| IAM-FMB-04 | concurrency | forward∥FULL: no deadlock, desired-set, 1 member/1 ledger | integration `-race` (обяз.) |
| IAM-FMB-05 | concurrency | create-vs-revoke: финал = финальная роль, no stuck | integration `-race` (обяз.) |
| IAM-FMB-06 | backstop/EC | sync-fail → drainer материализует; `done`≠visibility (ban #9) | integration |
| IAM-FMB-07 | idempotency | повтор forward → 1 member/1 ledger | integration (обяз.) |
| IAM-FMB-08 | fan-out | Role.Update revoke sticks; forward не в fan-out | integration |
| IAM-FMB-09 | revoke | Delete binding → `Check{allowed:false}` в окне | integration + newman |
| IAM-FMB-10 | delete-stale guard | binding с member'ами → FULL (delete-stale цел) | integration |
| IAM-FMB-11 | negative | отвергнутый Create → 0 материализации, точные коды | integration + newman |
| IAM-FMB-12 | edge | пустой scope → 0 member, no error, bounded | integration |
| IAM-FMB-13 | edge/EC | group#member → EC-emit; member `{allowed:true}` в окне | integration/newman |
| IAM-FMB-14 | edge/EC | email pending-intent → deny до login; remap после | newman/integration |
| IAM-FMB-15 | edge/acyclic | dangling target → binding создан, 0 member, graceful | integration |

---

## 6. Координация (после `✅ APPROVED`)

1. Статус дока → `APPROVED`; завести KAC-тикет + ветку `KAC-<N>` в `kacho-iam` + KAC-trail (`vault.md`).
2. `superpowers:writing-plans` → `integration-tester` (RED-тесты по IAM-FMB-04/05/07/03/10/08) → `rpc-implementer`
   (ADDITIVE create-forward-ветка реконсайлера строгим TDD).
3. Схема БД затронута (если миграция) → `db-architect-reviewer` ревьюит после реализации; distributed-аспекты →
   `system-design-reviewer` (обязателен).
4. `kacho-deploy` redeploy `REF_IAM` → mega-rbac stress newman **без cap-widen** (главный throughput-гейт).
5. Заказчик — только финальный smoke/e2e (шаг 7).

Сценарий оказался неоднозначным ПОСЛЕ старта кодирования → вернуть сюда для уточнения; НЕ менять поведение
реализации без правки этого acceptance-дока.
