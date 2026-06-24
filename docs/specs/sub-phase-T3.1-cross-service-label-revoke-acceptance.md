# Sub-phase T3.1 (cross-service ARM_LABELS revoke on label change) — Acceptance

> **Статус:** ✅ APPROVED (`acceptance-reviewer`, раунд 2, 2026-06-23)
> **Дата:** 2026-06-23
> **Автор:** `acceptance-author`
> **Ревьюер:** `acceptance-reviewer` — раунд 1 ❌ CHANGES REQUESTED → правки (п.1-7 + Q1-Q6) → раунд 2 ✅ APPROVED (покрытие 100%, оба двойных бага SG+listener код-сверены, gate ban #1 снят).
> **Эпик/тикет:** GitHub `PRO-Robotech/kacho-workspace#113` (bug). Продолжение/закрытие долга эпика «Resource-scoped AccessBinding» под-фаза **T3** (`epic-resource-scoped-access-binding-selectors-acceptance.md`, D4 «vpc/nlb emit labels на Create И Update-when-labels-in-mask»). KAC-Subtask(и) проставляются ДО `superpowers:writing-plans`.
> **Затронутые репо:** `kacho-vpc` / `kacho-compute` / `kacho-nlb` / `kacho-iam` (подтверждение, без изменений кода) / `kacho-deploy` (e2e-матрицы) / `kacho-workspace` (docs/vault). **`kacho-proto` НЕ затронут** (поля `labels`/`parent_project_id`/`source_version` уже в `RegisterResourceRequest`, см. §0.2 G-7).

---

## Обзор

ARM_LABELS-грант (custom-роль с правилом `{module, resources, verbs, matchLabels}`) на **cross-service** ресурс (vpc/compute/nlb) **не ревокается** при снятии/изменении метки на ресурсе: пользователь сохраняет видимость (`v_get/v_list/viewer`) бессрочно. Причина (verified live fe3455, #113): consumer-сервисы эмитят `InternalIAMService.RegisterResource` (→ `kacho_iam.resource_mirror` upsert → `mirror.upsert` reconcile-event → rsab re-materialize) **только на CREATE ресурса, а на label-UPDATE — нет**, поэтому IAM-зеркало протухает и rsab держит стейл-членство.

Эта под-фаза закрывает разрыв в **эмит-точке consumer'ов**: каждый label-selectable ресурс vpc/compute/nlb обязан эмитить `RegisterResource` (mirror.upsert с актуальными labels) **на Update, когда labels изменились**, в той же writer-tx через существующий transactional outbox (SEC-D, идемпотентно, `source_version`-monotonic). IAM-сторона (rsab reconciler) **уже** ре-материализует membership на `mirror.upsert`, включая **revoke** ставших-невалидными members (verified: `applyDiff` fell-out-loop делает `EmitTupleDelete` + `DeleteMember`) — изменений в IAM **не требуется**, кроме подтверждения revoke-пути тестом.

Документ описывает **только внешнее наблюдаемое поведение** (gRPC-коды `Check`/`ListObjects`, видимость ресурса в `List<Resource>`, eventual-consistency reconcile-семантику), не реализацию. Сценарии трассируются в имена integration-/newman-тестов через ID `T3.1-NN`. Стандартные конвенции (`api-conventions.md`, `security.md`, `data-integrity.md`) нормативны и в тело не дублируются — только ссылками (§1).

---

## 0.1 Ground-truth (сверено против кода — per-service gap-матрица)

Эмит `RegisterResource`/mirror.upsert по сервисам/ресурсам (✅ = эмитит актуальные labels, ❌ = баг #113):

| Сервис | Ресурс | Create эмитит labels | Update-on-label-change эмитит | Файл (эмит-точка) |
|---|---|---|---|---|
| vpc | network | ✅ | ❌ **BUG** | `internal/apps/kacho/api/network/{create.go:228, update.go=НЕТ}` |
| vpc | subnet | ✅ | ✅ (reference fix) | `subnet/{create.go:197, update.go:121 (labelsInMask)}` |
| vpc | securityGroup | ❌ (bare tuple, **без labels**) | ❌ **BUG (двойной)** | `securitygroup/{create.go:195 ProjectHierarchy, update.go=НЕТ}` |
| compute | instance | ✅ | ✅ (gated `emitLabelsRegister`) | `internal/repo/instance_repo.go:{186, 235}` |
| compute | disk | ✅ | ❌ **BUG** | `disk_repo.go:{150 create, 160 Update=без emit}` |
| compute | image | ✅ | ❌ **BUG** | `image_repo.go:{149 create, 159 Update=без emit}` |
| compute | snapshot | ✅ | ❌ **BUG** | `snapshot_repo.go:{138 create, 148 Update=без emit}` |
| nlb | loadBalancer | ✅ | ✅ | `loadbalancer/update.go:114 (labelsInMask)` |
| nlb | targetGroup | ✅ | ✅ | `targetgroup/update.go:114 (labelsInMaskTG)` |
| nlb | listener | ❌ (bare intent, **без labels**) | ❌ **BUG (двойной)** | `listener/{create.go:488-500 listenerRegisterIntent — БЕЗ Labels, update.go:125 labels-применяются-но-emit-НЕТ}` |

**Эталонный паттерн (subnet/update.go:121-128, nlb LB/TG):**
```
if labelsInMask(in.UpdateMask) {          // empty mask = full PATCH = true; иначе true iff "labels" в маске
    w.FGARegister().EmitRegister(ctx, fgaregister.RegisterItems(
        fgaregister.ProjectHierarchyItem(projectID, "<type>", updated.ID, domain.LabelsToMap(updated.Labels)),
    ))
}
```

**Особый случай vpc.securityGroup (двойной баг):** на Create эмитит **bare tuple без labels** (`RegisterIntent(ProjectHierarchy(...))`, `securitygroup/create.go:195`) → mirror у SG вообще без labels. Фикс обязан исправить **и Create** (перейти на `ProjectHierarchyItem` с labels), **и Update** (добавить labels-mask-gated emit). Иначе SG-селекторы не сматчатся даже свежесозданные.

**Особый случай nlb.listener (двойной баг):** `listenerRegisterIntent` (`listener/create.go:488-500`) **НЕ задаёт поле `Labels`** (в отличие от соседних `lbMirrorIntent`/`tgMirrorIntent`, которые ставят `Labels: domain.LabelsToMap(...)`) → mirror у listener эмитится с пустыми labels уже на Create. На Update labels применяются к ресурсу, но emit'а mirror.upsert нет (`update.go:125`). Значит listener сломан на **обеих** точках — ровно как securityGroup. Фикс обязан исправить **и Create** (`listenerRegisterIntent` должен задавать `Labels: domain.LabelsToMap(...)`), **и Update** (добавить `labelsInMask`-gated emit). Иначе listener-селекторы не сматчатся даже свежесозданные, а revoke-кейс REVOKE-04 будет ложно-зелёным на пустом mirror.

**IAM-сторона (verified — изменений НЕ требует):**
- `resource_mirror` (`migrations/0019`): PK `(object_type, object_id)`, `labels jsonb` (GIN), `parent_project_id/parent_account_id`, `source_version timestamptz`, `updated_at`. Upsert (`emitter.go:89-99`): `ON CONFLICT … DO UPDATE SET labels=EXCLUDED.labels (FULL REPLACE), source_version=EXCLUDED WHERE resource_mirror.source_version < EXCLUDED.source_version` — last-source-wins, идемпотентно, stale-version → 0 rows no-op.
- `RegisterResource` use-case (`internal_iam/register_resource.go`): в одной writer-tx upsert mirror + enqueue `resource_reconcile_outbox` event `mirror.upsert` (`migrations/0021`).
- rsab reconciler (`access_binding/reconcile/reconcile.go`): дренит `resource_reconcile_outbox` (≤2s) → `ReconcileObject(type,id)` → `applyDiff`. **Fell-out-loop (reconcile.go:480-492)**: member, переставший матчить selector (label removed/changed), → `EmitTupleDelete` + `ForgetEmittedTuples` + `DeleteMember` (реальный DELETE из `access_binding_target_members` + revoke FGA-tuples). Slow-sweep (≤30s) — backstop. Покрыто `reconcile_rules_test.go:TestReconcileRules_RuleRemoved_EagerRevokeByRuleFP`.

⇒ **Корень исключительно в consumer-эмите.** IAM revoke-путь работает; нужно лишь, чтобы mirror получил актуальные labels на Update.

## 0.2 Фиксированные дизайн-решения (предлагаются автором; approve ревьюером — затем НЕ переоткрывать)

| ID | Решение | Обоснование |
|---|---|---|
| **G-1 (эмит-точка)** | Каждый **label-selectable** ресурс vpc/compute/nlb эмитит `RegisterResource` (mirror.upsert, актуальные `labels`+`parent_project_id`) **на Update**, в той же writer-tx, что и UPDATE ресурса, через существующий fga-register outbox. Список ресурсов = gap-матрица §0.1: **vpc.network, vpc.securityGroup, compute.disk, compute.image, compute.snapshot, nlb.listener** (subnet/instance/LB/TG уже корректны — НЕ трогаем, только non-regression). **Два ресурса (vpc.securityGroup, nlb.listener) — двойной баг**: эмитят bare-tuple/bare-intent **без labels уже на Create**, поэтому фикс обязан охватить и Create-эмит (`securitygroup/create.go:195`, `listener/create.go:488-500 listenerRegisterIntent`), и Update-эмит. | Закрывает ровно разрыв #113. Эталон — subnet/update.go. Тот же слой/таблица/паттерн; нулевой риск для уже-корректных ресурсов. |
| **G-2 (gate: эмитить только при изменении labels)** | Эмит **gated по «labels в update_mask»** (эталон `labelsInMask`: empty mask = full-PATCH ⇒ true; иначе true iff `"labels"` ∈ mask). Update без labels-в-маске → **НЕ эмитит** (no-op). **Принято ревьюером (Q3):** gated выбран по нагрузке (меньше reconcile-шума). **External-наблюдаемое поведение идентично** для gated и always-emit (`source_version`-monotonic делает «лишний» upsert идемпотентным no-op). **Связь с тестом:** если реализатор выберет always-emit (проще, без mask-проверки), сценарий **T3.1-IDM-01** «non-label Update ⇒ нет лишнего mirror.upsert» придётся **ослабить** (с «intent НЕ эмитнут» до «mirror.labels/source_version не меняют итог reconcile»). | Не плодить лишние mirror.upsert/reconcile-events на не-label Update (rename/resize/desc). `source_version`-monotonic делает «лишний» upsert безвредным, но избегать его дешевле и чище (меньше reconcile-нагрузки). Эмит при full-PATCH (empty mask) обязателен — full-PATCH может молча обнулить labels (см. T3.1-FULLPATCH-01). |
| **G-3 (upsert, НЕ Unregister, при полном снятии меток)** | Полное снятие меток (`labels` → `{}`/`null`) эмитит **`RegisterResource` (mirror.upsert) с пустым labels-map**, НЕ `UnregisterResource`. Ресурс по-прежнему существует в источнике; mirror-строка должна остаться с `labels={}` (а не удалиться). | `UnregisterResource` = «ресурс удалён» (DELETE mirror-строки) — семантически неверно для живого ресурса с убранными метками; сломал бы owner-tuple/containment и другие (не-label) гранты. Upsert с `{}` корректно протухает label-селекторы (`labels @> matchLabels` перестаёт матчить), оставляя ресурс зарегистрированным. `UnregisterResource` остаётся **только** на Delete ресурса (как сейчас). |
| **G-4 (atomicity / SEC-D, нет dual-write)** | mirror.upsert-intent пишется в **той же writer-tx**, что и UPDATE ресурса (один `w.Commit`). Rollback Update ⇒ intent не записан. Дрейн в IAM — отдельный at-least-once drainer (mTLS, ретраи), как на Create. | Ban #10 / SEC-D transactional-outbox: запрет dual-write. Тот же контракт, что уже на Create-пути (subnet/instance). |
| **G-5 (идемпотентность)** | Повтор/ретрай эмита идемпотентен на IAM-стороне: `source_version`-monotonic upsert (stale → 0 rows), reconcile idempotent (diff desired-vs-actual). Допустимо эмитить дубликат на retry drainer — IAM схлопывает. | β-паттерн доказан. At-least-once drainer может доставить дубль; mirror upsert + reconcile его поглощают. |
| **G-6 (IAM не меняется)** | IAM-side кода **не трогаем**: rsab уже revoke-ит fell-out members на `mirror.upsert`. Требуется **обязательный новый** integration-тест на IAM (T3.1-IAM-01), фиксирующий revoke-через-`RegisterResource`-label-change end-to-end (`worker.drain`). Точного такого теста в наборе НЕТ (ревьюер сверил — см. S0); «сослаться на эквивалент» не годится. | Ground-truth: `applyDiff` fell-out-loop (`reconcile.go:480-492`) уже делает DELETE+tuple-revoke. Не плодить прод-изменений; зафиксировать гарантию обязательным тестом. |
| **G-7 (proto не меняется)** | `RegisterResourceRequest` уже несёт `labels=5`, `parent_project_id=6`, `parent_account_id=7`, `source_version=8` (proto §128/217-259). Новых полей/RPC не вводим. | Эмит-точка использует существующий wire-контракт; `proto-api-reviewer` не задействован (proto без diff). |
| **G-8 (assignability — by-design, НЕ баг)** | iam-собственные роли assignable по **scope-tier** (system/account/project), не по permission-content (`domain.IsRoleAssignable`, `role_scope.go:85-104`): account-scoped кастом-роль assignable **только** на `account:<ownAccount>`; project-scoped — только на `project:<ownProject>`; system — на любой; **нет hierarchy-down** (account-роль НЕ assignable на её projects). Bind мис-скоупленной роли → async `Operation.error` **FAILED_PRECONDITION** (code 9) `"role <id> is not assignable on <type>:<id>"` (`access_binding/create.go:207-226`). `ListAssignableRoles` возвращает ровно тот набор, что Create принимает (parity, SQL-predicate). | Это **корректное поведение**, не часть бага #113. Фиксируется здесь, чтобы newman-сюит (#211) НЕ строился на ложной предпосылке «iam.project-роль bind-ится на project-scope» — она и не должна. Терминологическое уточнение: в коде `iam.project`/`iam.account` — это **типы объектов** селекторов (FGA-types), НЕ permission-строки; assignability к ним отношения не имеет (решается scope-tier). |

---

## 1. Связь с регламентом (нормативно; в тело не дублируется)

| Регламент | Где соблюдается |
|---|---|
| `api-conventions.md` — read sync, мутации async `Operation`; Watch нет (poll Operation/List) | `<Resource>.Update` async (наследие); видимость наблюдается через `Check`/`ListObjects`/`List<Resource>` sync |
| `api-conventions.md` — update_mask discipline (`labels` mutable; empty mask = full-PATCH) | G-2, T3.1-IDM-01, T3.1-FULLPATCH-01 |
| `api-conventions.md` — JSON camelCase (`matchLabels`, `labels`, `verificationStatus`) | §A read-формы |
| `api-conventions.md` — error-format; состояние → `FAILED_PRECONDITION` (async → `Operation.error`, ban #9) | T3.1-ASSIGN-01 (G-8) |
| `data-integrity.md` §within-service — outbox-intent в writer-tx; reconcile idempotent; concurrent → integration-тест ≥2 goroutine | G-4, G-5, T3.1-CONC-01 |
| `data-integrity.md` §cross-domain — `resource_mirror` output-only зеркало (source = owner); upsert (НЕ Unregister) на Update держит зеркало актуальным, mirror-строка живёт пока жив ресурс; **НЕ новые рёбра** (`vpc/compute/nlb→iam` RegisterResource — существующие, расширяем частоту эмита, НЕ payload-форму) | G-1, G-3, G-7, §3, REVOKE-01 G-3-assert |
| `security.md` §Internal-vs-external — `RegisterResource` остаётся Internal :9091 (mTLS); НЕ external | G-1, G-4 |
| `security.md` §инфра-чувствительные — в mirror эмитятся ТОЛЬКО tenant-facing `labels`+`parent` (НЕ placement/underlay) | G-1 |
| `00-kacho-core.md` ban #9 (мутации→Operation), #10 (within-DB / SEC-D no dual-write), #4/#8 (mirror НЕ источник истины), #12/#13 (TDD), #1 (APPROVED перед кодом) | §0.2, §4 DoD RED→GREEN |
| `polyrepo.md` §порядок merge | §4: (proto N/A) → iam (подтверждение) → vpc/compute/nlb (emit) → deploy → workspace(docs) |
| sub-phase T3 (`…-selectors-acceptance.md`, D4) — selector-контракт (matchLabels, containment, verification_status, reconciler) сохраняется; эта под-фаза доводит D4 «emit на Update» до полного покрытия consumer-ресурсов | §0.1, T3.1-NREG-01 |

---

## 2. Модель видимости (нормативно — наблюдаемые точки)

Видимость ARM_LABELS-гранта наблюдается через **три** независимые публичные/internal-проекции (любая может служить assert'ом в тесте):
- **`InternalIAMService.Check`** (или публичный эквивалент authz-гейта) на `{subject, relation=v_list|v_get|viewer, object="<type>:<id>"}` → `allowed: true|false`.
- **`ListObjects`** (FGA-обратный) на `{subject, relation, type}` → массив object-id; ресурс **включён** ⇔ грант активен.
- **`<Resource>.List`** через api-gateway под токеном приглашённого (listauthz-фильтр) → ресурс присутствует ⇔ грант активен.

**Eventual consistency:** ревокация — async (drainer ≤2s + reconcile + sweep-backstop ≤30s). Тесты поллят до сходимости с таймаутом (как Operation-полл), НЕ ассертят мгновенно. «Видимость пропадает» = сходится к `false`/исключению в пределах таймаута.

---

## 3. Cross-repo граф (без изменений — подтверждение ацикличности)

- `vpc→iam`, `compute→iam`, `nlb→iam` `InternalIAMService.RegisterResource` — **существующие** рёбра (SEC-A/SEC-D owner-tuple + β labels). Эта под-фаза увеличивает **частоту** эмита (добавляет Update-trigger), НЕ вводит новых рёбер и НЕ меняет payload-форму (G-7).
- IAM **не** зовёт consumer'ов обратно (containment из same-DB mirror). Циклов нет. **НЕ заводить** `edges/iam-to-vpc|compute|nlb`.

---

## Сценарий T3.1-REVOKE-01: Happy revoke — vpc.network (главный)

**ID:** T3.1-REVOKE-01

**Given** существует сеть `net-treska` в проекте `prj-A` с `labels={"network":"treska"}`
**And** приглашённому субъекту `user:bob` выдан грант кастом-роли с ARM_LABELS-правилом `{module:vpc, resources:[network], verbs:[get,list], matchLabels:{network:treska}}` на scope `project:prj-A`
**And** субъекту `user:carol` выдан **другой, не-label** грант на тот же `net-treska` (например owner/прямой viewer на `project:prj-A`, не зависящий от `matchLabels`) — он не должен пострадать от снятия метки
**And** reconcile сошёлся: `Check{user:bob, v_list, vpc_network:net-treska} = true`, `ListObjects{user:bob, v_list, vpc_network}` включает `net-treska`

**When** клиент вызывает `POST /vpc/v1/networks/{net-treska}` (`NetworkService.Update`) с payload:
  - `updateMask = {paths:["labels"]}`
  - `labels = {}`  (метка `network` снята)

**Then** `Update` возвращает `Operation`; полл `OperationService.Get(id)` до `done=true && !error`; `Network.Get(net-treska).labels` пуст
**And** в той же writer-tx был записан mirror.upsert-intent (`vpc_network:net-treska`, `labels={}`) — наблюдаемо на IAM-стороне как обновление `resource_mirror[vpc_network:net-treska].labels={}`
**And** в пределах reconcile-таймаута видимость пропадает: `Check{user:bob, v_list, vpc_network:net-treska}` сходится к `false`
**And** `ListObjects{user:bob, v_list, vpc_network}` **исключает** `net-treska`
**And** `GET /vpc/v1/networks` под токеном `user:bob` **не** содержит `net-treska`

**Executable-assert для G-3 (upsert, НЕ Unregister — mirror-строка остаётся):**
**And** строка `resource_mirror[vpc_network:net-treska]` **ПРИСУТСТВУЕТ** с `labels={}` (а **не** удалена, как было бы при `UnregisterResource`): PK `(object_type=vpc_network, object_id=net-treska)` найден, `labels='{}'::jsonb`, `parent_project_id` сохранён, `source_version` продвинулся
**And** owner-tuple / containment-видимость владельца ресурса **СОХРАНЕНА**: `Check{user:carol, v_get, vpc_network:net-treska}` остаётся `true` (не-label грант на тот же ресурс продолжает работать) — снятие метки протухло **только** label-селекторы, не снесло регистрацию ресурса
_(этот блок — executable-якорь G-3; без него «upsert-not-unregister» не верифицируем. Может быть выделен в отдельный кейс T3.1-G3-01, если integration-tester предпочтёт.)_

---

## Сценарий T3.1-REVOKE-02: Happy revoke — vpc.securityGroup (двойной баг: Create+Update)

**ID:** T3.1-REVOKE-02

**Given** создаётся SecurityGroup `sg-okun` в `prj-A` с `labels={"sg":"okun"}` через `SecurityGroupService.Create`
**And** грант ARM_LABELS `{module:vpc, resources:[securityGroup], verbs:[get,list], matchLabels:{sg:okun}}` на `project:prj-A` субъекту `user:bob`

**When** reconcile сходится после Create

**Then** видимость появляется: `Check{user:bob, v_list, vpc_security_group:sg-okun} = true` (фиксирует фикс Create-эмита: SG обязан эмитить **labels**, а не bare-tuple — иначе mirror.labels пуст и селектор не матчит даже свежесозданный SG)

**When** клиент вызывает `SecurityGroupService.Update(sg-okun)` с `updateMask={paths:["labels"]}`, `labels={"sg":"sudak"}`

**Then** `Operation` done без error; mirror.upsert эмитнут с `labels={"sg":"sudak"}`
**And** видимость под `matchLabels:{sg:okun}` пропадает: `Check{user:bob, v_list, vpc_security_group:sg-okun}` сходится к `false`; `ListObjects` исключает `sg-okun`

---

## Сценарий T3.1-REVOKE-03: Happy revoke — compute (disk / image / snapshot)

**ID:** T3.1-REVOKE-03

**Given** существует диск `disk-treska` в `prj-A` с `labels={"tier":"treska"}` (аналогично image/snapshot — табличный прогон по трём ресурсам)
**And** грант ARM_LABELS `{module:compute, resources:[disk], verbs:[get,list], matchLabels:{tier:treska}}` на `project:prj-A` субъекту `user:bob`
**And** reconcile сошёлся: `Check{user:bob, v_list, compute_disk:disk-treska} = true`

**When** клиент вызывает `DiskService.Update(disk-treska)` с `updateMask={paths:["labels"]}`, `labels={}`

**Then** `Operation` done без error; mirror.upsert эмитнут (`compute_disk:disk-treska`, `labels={}`)
**And** видимость пропадает: `Check{…} → false`, `ListObjects` исключает `disk-treska`, `GET /compute/v1/disks` под `user:bob` не содержит его
**And** _повторить для_ `image` (`ImageService.Update`) _и_ `snapshot` (`SnapshotService.Update`) — каждый отдельный кейс (`T3.1-REVOKE-03-disk/-image/-snapshot`)

---

## Сценарий T3.1-REVOKE-04: Happy revoke — nlb.listener (двойной баг: Create+Update)

**ID:** T3.1-REVOKE-04

**Given** создаётся listener `lsn-treska` (под LB в `prj-A`) с `labels={"lsn":"treska"}` через `ListenerService.Create`
**And** грант ARM_LABELS `{module:loadbalancer, resources:[listeners], verbs:[get,list], matchLabels:{lsn:treska}}` на `project:prj-A` субъекту `user:bob`

**When** reconcile сходится после Create

**Then** видимость **появляется**: `Check{user:bob, v_list, loadbalancer_listeners:lsn-treska} = true` (фиксирует фикс Create-эмита: `listenerRegisterIntent` обязан задавать **labels**, а не bare-intent — иначе mirror.labels пуст, селектор не матчит даже свежесозданный listener, и revoke ниже был бы ложно-зелёным на пустом mirror)

**When** клиент вызывает `ListenerService.Update(lsn-treska)` с `updateMask={paths:["labels"]}`, `labels={}`

**Then** `Operation` done без error; mirror.upsert эмитнут с `labels={}`
**And** видимость пропадает: `Check{…} → false`; `ListObjects` исключает `lsn-treska`

---

## Сценарий T3.1-ADD-01: Label add → grant появляется (симметрия)

**ID:** T3.1-ADD-01

**Given** существует сеть `net-plain` в `prj-A` с `labels={}` (без меток)
**And** грант ARM_LABELS `{module:vpc, resources:[network], verbs:[get,list], matchLabels:{network:treska}}` на `project:prj-A` субъекту `user:bob`
**And** reconcile сошёлся: `Check{user:bob, v_list, vpc_network:net-plain} = false` (метки нет → не матчит)

**When** клиент вызывает `NetworkService.Update(net-plain)` с `updateMask={paths:["labels"]}`, `labels={"network":"treska"}`

**Then** `Operation` done без error; mirror.upsert эмитнут с `labels={"network":"treska"}`
**And** видимость **появляется**: `Check{user:bob, v_list, vpc_network:net-plain}` сходится к `true`; `ListObjects` включает `net-plain`

---

## Сценарий T3.1-CHANGE-01: Смена метки (treska → okun) — грант мигрирует

**ID:** T3.1-CHANGE-01

**Given** сеть `net-x` в `prj-A` с `labels={"network":"treska"}`
**And** субъекту `user:bob` выданы ДВА гранта: роль-T `{…, matchLabels:{network:treska}}` и роль-O `{…, matchLabels:{network:okun}}`, обе на `project:prj-A`
**And** reconcile сошёлся: `Check{user:bob, v_list, vpc_network:net-x} = true` (через роль-T)

**When** клиент вызывает `NetworkService.Update(net-x)` с `updateMask={paths:["labels"]}`, `labels={"network":"okun"}`

**Then** `Operation` done без error; mirror.upsert эмитнут с `labels={"network":"okun"}`
**And** членство под роль-T (`matchLabels:{network:treska}`) ревокается, под роль-O (`matchLabels:{network:okun}`) материализуется
**And** **итоговая** видимость остаётся `Check{user:bob, v_list, vpc_network:net-x} = true` (теперь через роль-O) — ресурс не «мигает» в недоступность для субъекта с обеими ролями, но grant-источник сменился (наблюдаемо: при удалении только роль-O видимость пропадёт; при удалении только роль-T — нет)

---

## Сценарий T3.1-IDM-01: Update без изменения labels → нет лишнего mirror.upsert

**ID:** T3.1-IDM-01

**Given** сеть `net-y` в `prj-A` с `labels={"network":"treska"}`, грант как в REVOKE-01, reconcile сошёлся (`Check = true`)

**When** клиент вызывает `NetworkService.Update(net-y)` с `updateMask={paths:["description"]}`, `description="renamed"` (labels НЕ в маске)

**Then** `Operation` done без error; `description` обновлён
**And** mirror.upsert-intent **НЕ** эмитнут (G-2: `labels` не в маске → no-op) — наблюдаемо: `resource_mirror[…].updated_at` / `source_version` НЕ изменились; счётчик fga-register-outbox для этого ресурса не вырос
**And** видимость без изменений: `Check{user:bob, v_list, vpc_network:net-y}` остаётся `true`

_Дополнительно (idempotency повтора):_ если drainer доставит дубликат mirror.upsert (at-least-once), IAM схлопывает его (`source_version`-monotonic) — членство стабильно, без дубль-tuple (G-5).

---

## Сценарий T3.1-FULLPATCH-01: Empty update_mask (full-PATCH) ⇒ эмит обязателен

**ID:** T3.1-FULLPATCH-01

Прямая проверка G-2 «empty mask ⇒ full-PATCH ⇒ `labelsInMask` = true ⇒ эмит» — самый коварный путь: явной маски нет, но labels (или их обнуление) применяются. Все прочие сценарии используют **явную** маску `{paths:["labels"]}`; здесь маска **пустая**.

**Случай A (full-PATCH обнуляет метку → revoke):**

**Given** сеть `net-fp` в `prj-A` с `labels={"network":"treska"}`, грант ARM_LABELS `{…, matchLabels:{network:treska}}` субъекту `user:bob`, reconcile сошёлся (`Check = true`)

**When** клиент вызывает `NetworkService.Update(net-fp)` с **пустым** `updateMask` (full-object PATCH) и телом, где `labels={}` (или поле labels отсутствует — full-PATCH трактует как `{}`)

**Then** `Operation` done без error; `Network.Get(net-fp).labels` пуст
**And** mirror.upsert эмитнут с `labels={}` (G-2: empty mask ⇒ full-PATCH ⇒ `labelsInMask`=true ⇒ эмит обязателен, даже без явного `"labels"` в маске)
**And** видимость пропадает: `Check{user:bob, v_list, vpc_network:net-fp}` сходится к `false`; `ListObjects` исключает `net-fp`

**Случай B (симметрия — full-PATCH с labels в теле → эмит):**

**Given** сеть `net-fp2` в `prj-A` с `labels={}`, тот же грант, `Check = false`

**When** `NetworkService.Update(net-fp2)` с **пустым** `updateMask` и телом `labels={"network":"treska"}`

**Then** `Operation` done без error; mirror.upsert эмитнут с `labels={"network":"treska"}`
**And** видимость **появляется**: `Check{user:bob, v_list, vpc_network:net-fp2}` сходится к `true`

---

## Сценарий T3.1-ATOM-01: Atomicity (SEC-D) — intent в writer-tx, rollback Update → нет intent

**ID:** T3.1-ATOM-01

**Given** сеть `net-z` в `prj-A` с `labels={"network":"treska"}`

**When** `NetworkService.Update(net-z)` с `labels`-изменением выполняется в writer-tx, который **откатывается** (инжектируется ошибка после UPDATE-стейтмента, до commit — integration-уровень)

**Then** ни строка `networks[net-z]` не изменилась, ни fga-register-outbox-intent не записан (одна tx — оба либо ничего)
**And** при **успешном** commit: и UPDATE ресурса, и mirror.upsert-intent присутствуют атомарно (нет dual-write; intent не может «потеряться» при успешном Update и не может «осиротеть» при неуспешном)

---

## Сценарий T3.1-CONC-01: Concurrency — конкурентный label-flip, reconcile идемпотентен

**ID:** T3.1-CONC-01

**Given** сеть `net-c` в `prj-A`, грант ARM_LABELS `{…, matchLabels:{network:treska}}`

**When** N≥2 goroutine конкурентно вызывают `NetworkService.Update(net-c)` с чередующимися `labels` (`{network:treska}` ↔ `{}`), порождая последовательность mirror.upsert с разными `source_version`

**Then** IAM применяет **last-source-wins** (`source_version`-monotonic; stale upsert → 0 rows); финальное `resource_mirror[net-c].labels` соответствует Update с наибольшим `source_version`
**And** итоговая видимость (`Check`/`ListObjects`) детерминированно соответствует финальной метке (matched ⇔ финал `={network:treska}`); нет «застрявшего» стейл-членства, нет дублей в `access_binding_target_members`
**And** (integration, testcontainers, ≥2 goroutine — обязателен `data-integrity.md` §5) ни одна гонка не оставляет mirror рассинхронизированным с финальным состоянием ресурса

---

## Сценарий T3.1-UNAVAIL-01: IAM недоступен на drain → at-least-once, intent не теряется

**ID:** T3.1-UNAVAIL-01

**Given** сеть `net-u` с `labels={"network":"treska"}`, грант как в REVOKE-01; IAM (mirror-endpoint) временно недоступен

**When** клиент вызывает `NetworkService.Update(net-u)` с `labels={}` — **Update ресурса сам по себе НЕ зависит от IAM** (mirror-эмит — async outbox, не sync-вызов IAM на request-path)

**Then** `Update` Operation done без error (UPDATE ресурса коммитится; intent лежит в outbox с `sent_at IS NULL`) — недоступность IAM **не** блокирует мутацию ресурса
**And** drainer ретраит intent (backoff, at-least-once); по восстановлении IAM mirror.upsert доставляется, reconcile ревокает членство
**And** intent **не теряется** (durable в outbox до успешной доставки) — eventual-consistency, но не потеря

_Примечание: это ОТЛИЧАЕТСЯ от sync cross-service ref на мутации (`UNAVAILABLE` fail-closed). Mirror-эмит — async outbox-relay (SEC-D), а НЕ sync-предусловие Update; поэтому Update не падает в `UNAVAILABLE`._

---

## Сценарий T3.1-NREG-01: Non-regression — same-service (iam.account/iam.project) и уже-корректные ресурсы

**ID:** T3.1-NREG-01

**Given** грант ARM_LABELS на iam-собственный ресурс (например `iam.project` с `matchLabels:{env:prod}`) — материализуется через **iam-direct same-DB** (T3-D6), НЕ через mirror
**And** существующие корректные эмиттеры: vpc.subnet, compute.instance, nlb.loadBalancer/targetGroup

**When** меняется метка на `iam.project` (через `ProjectService.Update` own-path) И, отдельно, на vpc.subnet / compute.instance / nlb.loadBalancer

**Then** для `iam.project`: видимость ре-эволюционирует на own Update-path как прежде (iam-direct reconcile) — **без регресса** (эта под-фаза iam-direct не трогает)
**And** для subnet/instance/LB/TG: revoke на label-change продолжает работать (они уже корректны — этот кейс защищает от случайной поломки эталонного паттерна при правке соседних ресурсов)

---

## Сценарий T3.1-ASSIGN-01: Assignability precondition (by-design — НЕ баг #113)

**ID:** T3.1-ASSIGN-01

**Given** account-scoped кастом-роль `role-acc` (`role.AccountID=acc-1`), проект `prj-1` (внутри `acc-1`)

**When** клиент вызывает `AccessBindingService.Create` с `roleId=role-acc`, `resourceType=project`, `resourceId=prj-1`

**Then** `Create` возвращает `Operation`; полл `OperationService.Get(id)` до `done=true`; `Operation.error` = **`FAILED_PRECONDITION`** (code 9), message `"role role-acc is not assignable on project:prj-1"` (G-8: нет hierarchy-down; account-роль не assignable на её project)
**And** `ListAssignableRoles{resourceType:project, resourceId:prj-1}` **не** содержит `role-acc` (parity: список = то, что Create принимает)

**When** (контр-кейс happy) `Create` с `roleId=role-acc`, `resourceType=account`, `resourceId=acc-1`

**Then** `Operation` done **без** error — роль assignable на своём account-scope

_Назначение кейса: зафиксировать корректность assignability как контракт, чтобы newman-сюит #211 не строился на ложной предпосылке «iam.*-роль bind-ится на project-scope». Это причина переписать #211-сюит._

---

## 3.1 Что НЕ входит в scope (явно исключено)

| Область | Статус / почему вне scope |
|---|---|
| **Корректные эмиттеры — НЕ трогаем** (vpc.subnet, compute.instance, nlb.loadBalancer, nlb.targetGroup) | Уже эмитят актуальные labels на Create **и** Update (`labelsInMask`/`emitLabelsRegister`-gate, §0.1). Покрываются **только** non-regression (T3.1-NREG-01) — менять их код запрещено. |
| **iam-direct path** (iam-собственные ресурсы: `iam.account`/`iam.project`) | Материализуются через iam-direct same-DB reconcile (T3-D6), **не** через cross-service `resource_mirror`. Эмит-баг #113 их не касается. Защищены non-regression (T3.1-NREG-01). |
| **Остаточный gap: vpc.routeTable / vpc.address / vpc.gateway / vpc.networkInterface** (ИЗВЕСТНЫЙ, отложен) | Входят в `labelSelectableTypes` (`kacho-iam/internal/domain/feed_registry.go:15-40`) — selectable, но **labels им не feed-ятся ни на Create, ни на Update** (тот же класс бага #113: эмитят bare-tuple без labels). Метятся реже, чем network/SG/disk. **Отложено осознанно** под отдельный тикет (низкий приоритет): эта под-фаза закрывает шесть ресурсов с реальным spread (network/SG/disk/image/snapshot/listener). Декларация остаточного риска: грант ARM_LABELS на эти 4 типа **не ревокается** при снятии метки, пока не закрыт follow-up. Завести GitHub Issue (`bug` + `blocked:`-ссылку на эту под-фазу) ДО merge S5. |
| **proto** (`kacho-proto`) | Без изменений: `RegisterResourceRequest` уже несёт `labels`/`parent_project_id`/`parent_account_id`/`source_version` (G-7). `proto-api-reviewer` не задействован. |
| **Схема БД** | Без изменений: `resource_mirror` (`0019`), `resource_reconcile_outbox` (`0021`), fga-register-outbox — существуют. Новых таблиц/колонок/индексов нет; миграций нет. `db-architect-reviewer` ревьюит tx-корректность эмита, не схему. |

---

## 3.2 Трассировка сценарий → тест (1-to-1; integration-tester использует имена как есть)

Готовые имена — integration-tester НЕ выводит их сам, а реализует ровно эти функции/файлы. `RED-until-fixed?` = тест обязан быть красным до прод-фикса (TDD-red, ban #12); `non-reg` = защитный тест, зелёный изначально.

| Сценарий-ID | Integration-func (`Test<R>_<ID>_<desc>`) + репо/файл | Newman-case-file (через api-gateway) | RED-until-fixed? |
|---|---|---|---|
| T3.1-REVOKE-01 | `TestNetworkRepo_T31Revoke01_LabelRemoveEmitsMirrorUpsert` — kacho-vpc `internal/repo/network_fga_register_integration_test.go` | `kacho-deploy/tests/newman/cases/label-revoke-vpc.py::revoke01_network` | **да** |
| T3.1-G3-01 (если выделен) | `TestNetworkRepo_T31G301_UpsertNotUnregister_MirrorRowStays` — kacho-iam `internal/repo/resource_mirror_integration_test.go` | (assert в `label-revoke-vpc.py::revoke01_network`) | **да** |
| T3.1-REVOKE-02 | `TestSecurityGroupRepo_T31Revoke02_CreateEmitsLabels_UpdateRevokes` — kacho-vpc `internal/repo/securitygroup_fga_register_integration_test.go` | `label-revoke-vpc.py::revoke02_securitygroup` | **да** |
| T3.1-REVOKE-03-disk | `TestDiskRepo_T31Revoke03Disk_LabelRemoveEmitsMirrorUpsert` — kacho-compute `internal/repo/disk_repo_integration_test.go` | `label-revoke-compute.py::revoke03_disk` | **да** |
| T3.1-REVOKE-03-image | `TestImageRepo_T31Revoke03Image_LabelRemoveEmitsMirrorUpsert` — kacho-compute `internal/repo/image_repo_integration_test.go` | `label-revoke-compute.py::revoke03_image` | **да** |
| T3.1-REVOKE-03-snapshot | `TestSnapshotRepo_T31Revoke03Snapshot_LabelRemoveEmitsMirrorUpsert` — kacho-compute `internal/repo/snapshot_repo_integration_test.go` | `label-revoke-compute.py::revoke03_snapshot` | **да** |
| T3.1-REVOKE-04 | `TestListenerRepo_T31Revoke04_CreateEmitsLabels_UpdateRevokes` — kacho-nlb `internal/repo/listener_fga_register_integration_test.go` | `label-revoke-nlb.py::revoke04_listener` | **да** |
| T3.1-ADD-01 | `TestNetworkRepo_T31Add01_LabelAddMaterializesGrant` — kacho-vpc `network_fga_register_integration_test.go` | `label-revoke-vpc.py::add01_network` | **да** |
| T3.1-CHANGE-01 | `TestNetworkRepo_T31Change01_LabelSwapMigratesGrant` — kacho-vpc `network_fga_register_integration_test.go` | `label-revoke-vpc.py::change01_network` | **да** |
| T3.1-IDM-01 | `TestNetworkRepo_T31Idm01_NonLabelUpdateNoEmit` — kacho-vpc `network_fga_register_integration_test.go` | `label-revoke-vpc.py::idm01_no_emit` | **да** |
| T3.1-FULLPATCH-01 | `TestNetworkRepo_T31FullPatch01_EmptyMaskEmits` — kacho-vpc `network_fga_register_integration_test.go` | `label-revoke-vpc.py::fullpatch01_empty_mask` | **да** |
| T3.1-ATOM-01 | `TestNetworkRepo_T31Atom01_RollbackNoIntent` — kacho-vpc `network_fga_register_integration_test.go` | _(integration-only; tx-rollback не наблюдаем через gateway)_ | **да** |
| T3.1-CONC-01 | `TestNetworkRepo_T31Conc01_ConcurrentLabelFlip_LastSourceWins` (≥2 goroutine, testcontainers) — kacho-vpc `network_fga_register_integration_test.go` | _(integration-only; конкурентность не воспроизводима в newman надёжно)_ | **да** |
| T3.1-UNAVAIL-01 | `TestNetworkRepo_T31Unavail01_IamDown_IntentDurable` — kacho-vpc `network_fga_register_integration_test.go` | `label-revoke-vpc.py::unavail01_intent_durable` | **да** |
| T3.1-IAM-01 | `TestReconcile_T31Iam01_LabelChangeViaRegisterResource_EagerRevoke` (via `worker.drain`) — kacho-iam `internal/apps/kacho/api/access_binding/reconcile/reconcile_rules_test.go` | _(integration-only; IAM-internal reconcile)_ | **да** |
| T3.1-NREG-01 | `TestNREG_T31Nreg01_CorrectEmittersStillRevoke` — per-service (vpc.subnet/compute.instance/nlb.LB/TG) + iam-direct (`iam.project`) | `label-revoke-nonreg.py::subnet_instance_lb_tg_iamproject` | non-reg |
| T3.1-ASSIGN-01 | `TestAccessBinding_T31Assign01_ScopeTierPrecondition` — kacho-iam `internal/apps/kacho/api/access_binding/create_integration_test.go` | `label-revoke-assign.py::assign01_scope_tier` | non-reg |

_Имена файлов newman (`label-revoke-*.py`) — новые в `kacho-deploy/tests/newman/cases/` (либо per-service `project/<svc>/tests/newman/cases/`, на усмотрение integration-tester по месту прогона e2e-матрицы); регистрировать через `validate-cases.py` → `gen.py`._

---

## 4. Definition of Done (по стадиям; кросс-репо порядок `polyrepo.md`)

Кросс-репо порядок: **(proto N/A, G-7) → iam (подтверждение) → vpc/compute/nlb (emit) → deploy (e2e) → workspace(docs/vault)**. Стадии — самостоятельные deliverable'ы; CI нижестоящего пиннит sibling к feature-ветке до merge вышестоящего. Каждая Go-стадия: **RED-first** (падающий тест ДО кода, ban #12/#13), затем GREEN; в PR показать пару RED→GREEN.

**S0 — iam (`kacho-iam`) [ОБЯЗАТЕЛЬНЫЙ новый тест, без прод-кода — test-only PR, ban #13]:**
- [ ] **T3.1-IAM-01 — обязательный новый integration-тест (testcontainers).** Ревьюер сверил: точного теста «ACTIVE member → label-change через `RegisterResource`/mirror.upsert → eager-revoke + DELETE» НЕТ (существующие покрывают другие пути: `TestReconcileRules_RuleRemoved_EagerRevokeByRuleFP` — rule-removed; `…ActiveToRejected_RevokesViaLedger` — parent-move; `TestDB1_…_LabelChangeMaterializes` — label-change-на-GRANT, не revoke). Тест писать **обязательно**, не «сослаться на эквивалент». Сценарий:
  - grant ACTIVE по `matchLabels:{network:treska}` материализован (member в `access_binding_target_members`, FGA-tuple выдан);
  - `RegisterResource(object="vpc_network:X", labels={})` с `source_version` новее текущего → mirror.upsert FULL-REPLACE labels → enqueue `resource_reconcile_outbox` event `mirror.upsert`;
  - **прогон end-to-end через `worker.drain`** (drain outbox → `ReconcileObject`), а НЕ прямой вызов `ReconcileObject` (желательно — чтобы покрыть и drain-путь);
  - **Then:** member под `matchLabels:{network:treska}` **eager-revoked** — реальный `DELETE` из `access_binding_target_members` + FGA tuple-delete (fell-out-loop `reconcile.go:480-492`).
- [ ] Подтвердить: IAM прод-код изменений НЕ требует (G-6) — тест зелёный против существующего reconciler.

**S1 — vpc (`kacho-vpc`) [emit на Update]:**
- [ ] RED integration (testcontainers): `network/update.go` label-change → fga-register-outbox получает mirror.upsert с актуальными labels (эталон `subnet/fga_register_labels_test.go`); non-labels Update → no-op (T3.1-IDM-01); ATOM (T3.1-ATOM-01 — rollback → нет intent); CONC (T3.1-CONC-01 ≥2 goroutine, **обязателен** `data-integrity.md` §5).
- [ ] `network/update.go`: добавить `labelsInMask`-gated `EmitRegister(ProjectHierarchyItem("vpc_network", …, labels))` в writer-tx (эталон subnet).
- [ ] `securitygroup/`: исправить **create.go** (`ProjectHierarchy` bare-tuple → `ProjectHierarchyItem` с labels) **и** добавить gated emit в **update.go** (двойной баг, T3.1-REVOKE-02).
- [ ] Ревью: `go-style-reviewer`, `db-architect-reviewer` (outbox-intent в tx), `system-design-reviewer` (idempotent emit, нет нового ребра).

**S2 — compute (`kacho-compute`) [emit на Update]:**
- [ ] RED integration: `disk_repo.go`/`image_repo.go`/`snapshot_repo.go` `.Update` label-change → `emitFGARegisterIntent(EventRegister, …, labels)` (эталон `instance_repo.go:235` `emitLabelsRegister`-gate); non-labels Update → no-op.
- [ ] disk/image/snapshot Update: добавить gated FGA-register-emit (instance уже корректен — non-regression).
- [ ] Ревью: `go-style-reviewer`, `db-architect-reviewer`.

**S3 — nlb (`kacho-nlb`) [двойной баг: emit на Create + Update]:**
- [ ] RED integration: (a) `listener/create.go` (`listenerRegisterIntent`) Create → mirror.upsert содержит **актуальные labels** (сейчас bare-intent без labels — RED); (b) `listener/update.go` label-change → mirror.upsert (эталон `loadbalancer/update.go:114 labelsInMask`); non-labels Update → no-op.
- [ ] `listener/create.go`: исправить `listenerRegisterIntent` (`create.go:488-500`) — задать `Labels: domain.LabelsToMap(...)` (эталон `lbMirrorIntent`/`tgMirrorIntent`).
- [ ] `listener/update.go`: добавить `labelsInMask`-gated emit (LB/TG уже корректны — non-regression).
- [ ] Ревью: `go-style-reviewer`.

**S4 — deploy + e2e (`kacho-deploy`):**
- [ ] newman e2e **RED-until-fixed** → GREEN (имена файлов — §3.2): T3.1-REVOKE-01..04 (vpc.network/SG, compute.disk/image/snapshot, nlb.listener), T3.1-ADD-01, T3.1-CHANGE-01, T3.1-IDM-01, T3.1-FULLPATCH-01, T3.1-UNAVAIL-01, T3.1-NREG-01, T3.1-ASSIGN-01 — через api-gateway, ≥1 happy + ≥1 negative на затронутый ресурс. Eventual-consistency: полл `Check`/`ListObjects` до сходимости с таймаутом.
- [ ] **#211-сюит переписывание — ОТДЕЛЬНЫЙ test-only KAC** (Q6, ban #13: тесты не трогают прод), привязан к этому эпику; в DoD S4 — только ссылкой. Содержание: корректная assignability (G-8) — account-scoped роли bind на account-scope, НЕ project-scope. T3.1-ASSIGN-01 здесь — нормативный якорь G-8 для того KAC.
- [ ] e2e-build-матрицы newman зелёные для vpc/compute/nlb/iam.

**S5 — workspace (docs/vault):**
- [ ] Этот acceptance-док → APPROVED.
- [ ] vault: `resources/iam-resource-mirror.md` (Lifecycle: mirror обновляется на consumer-Update-label-change, не только Create), `edges/vpc-to-iam-*` / `edges/compute-to-iam-*` / `edges/nlb-to-iam-*` (History: Update-trigger добавлен, KAC-номер), `KAC/KAC-<N>.md` (trail, ссылка на #113), при необходимости `resources/{vpc-network,vpc-securitygroup,compute-disk,compute-image,compute-snapshot,nlb-listener}.md` (gotcha: label-Update эмитит mirror.upsert).
- [ ] by-design G-1..G-8 — запись в `docs/architecture/` соответствующих сервисов (consumer обязан re-emit mirror на label-Update; G-3 upsert-not-unregister; G-8 assignability scope-tier).
- [ ] **Остаточный gap** (§3.1): завести GitHub Issue (`bug`) на vpc.routeTable/address/gateway/networkInterface (selectable, но labels не feed-ятся ни на Create, ни на Update) с декларацией риска и ссылкой на эту под-фазу как родителя.

**Финальная верификация (перед merge каждой Go-стадии):** `go test ./... -race` + `golangci-lint run` + `govulncheck` + `make audit-list-filter` + newman зелёные.

---

## 5. Принятые решения ревьюера (Q1-Q6 — закрыты, НЕ переоткрывать)

Вопросы первого раунда review закрыты вердиктами ревьюера; вшиты в дизайн-решения/DoD как принятые.

| # | Вопрос | **Вердикт ревьюера (принято)** | Где вшито |
|---|---|---|---|
| Q1 | Scope: одна под-фаза или дробить по сервисам? | **Одна под-фаза**; S1/S2/S3 — Go-стадии (разрыв идентичен, эталон один subnet/instance/LB). Дробление KAC-Subtask'ами внутри. | §0.2 G-1, §4 S1/S2/S3 |
| Q2 | G-3: upsert с `{}` vs Unregister при полном снятии меток? | **Upsert с `{}`, НЕ Unregister** — owner-tuple/containment живут на той же mirror-строке; `Unregister` снёс бы owner-tuple **живого** ресурса. + executable-assert (REVOKE-01 G-3-блок / T3.1-G3-01). | §0.2 G-3, REVOKE-01 executable-assert |
| Q3 | G-2: gated по labels-в-маске vs always-emit? | **Gated (`labelsInMask`) принят** (выбор по нагрузке). External-наблюдаемое поведение **идентично** для gated/always (idempotent `source_version`-monotonic). Если реализатор выберет always-emit — **T3.1-IDM-01 «no extra reconcile» придётся ослабить**. | §0.2 G-2, T3.1-IDM-01 |
| Q4 | T3.1-IAM-01: тест уже есть? | **Точного теста НЕТ** (ревьюер сверил — есть rule-removed / parent-move / label-change-на-GRANT, но не label-change-revoke через RegisterResource). T3.1-IAM-01 — **обязательный новый** тест (end-to-end через `worker.drain`). | §0.2 G-6, §4 S0, §3.2 |
| Q5 | nlb.listener в selectableTypes? | **`loadbalancer.listeners` ∈ `labelSelectableTypes`** (`feed_registry.go:34`) — REVOKE-04 **остаётся**; listener-Create-gap **реален** (двойной баг, см. §0.1). | §0.1, REVOKE-04, §4 S3 |
| Q6 | #211-сюит — в эту под-фазу или отдельно? | **Отдельный test-only KAC** (#211-newman-rework, ban #13: тесты не трогают прод), в DoD S4 — ссылкой. **T3.1-ASSIGN-01 остаётся нормативным якорем G-8** здесь. | §4 S4, T3.1-ASSIGN-01 |

---

## 6. Выход / запреты

- Единственный артефакт авторства — этот markdown. **Никакого кода** (`.go`/`.sql`/`.proto`).
- Описано только наблюдаемое поведение API/authz; DB-уровень инвариантов (outbox-tx, mirror upsert) — забота `rpc-implementer`/`db-architect-reviewer`.
- Конвенции Kachō нормативны сами по себе (§1) — без сравнений с чужими облаками, без дублирования rule-модулей в тело.
- После APPROVED (`acceptance-reviewer`): `superpowers:writing-plans` → `integration-tester` (RED по T3.1-*) → `rpc-implementer` (per-service emit). proto НЕ затронут (`proto-api-reviewer` не нужен). Схема БД не меняется (миграций нет; outbox-таблицы существуют) — `db-architect-reviewer` ревьюит tx-корректность эмита, не новую схему.
