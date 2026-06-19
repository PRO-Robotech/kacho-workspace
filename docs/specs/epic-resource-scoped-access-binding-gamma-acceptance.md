# Epic «Resource-scoped AccessBinding» — Sub-phase γ (selector + containment + expiry) — Acceptance

> **Статус:** ✅ APPROVED
> **Дата:** 2026-06-19
> **Автор:** `acceptance-author`
> **Ревьюер:** `acceptance-reviewer` — ✅ APPROVED (round-2, 2026-06-19; round-1 CHANGES REQUESTED закрыт)
> **Эпик/тикет:** epic «Resource-scoped AccessBinding» (вариант C — selector-based grants), под-фаза **γ**. Затронутые репо: `kacho-proto` / `kacho-iam` / `kacho-api-gateway` / `kacho-ui` / `kacho-deploy` / `kacho-workspace`(docs/vault). KAC-номер проставляется ДО старта `superpowers:writing-plans` (фича → Subtask γ под `[EPIC]`).
> **Источник требований (verbatim intent заказчика):** «α дал per-object таргетинг по явному списку id. β наполнил IAM mirror метками/parent чужих ресурсов. γ — это и есть рабочий вариант C: дать субъекту доступ к ресурсам **по меткам**, чтобы новый объект с подходящими метками автоматически попадал под грант, а снятие метки — снимало доступ. Плюс γ закрывает два долга α: (1) containment — нельзя положить чужой объект под свой scope; (2) TTL-гранты должны реально истекать. Целевой грант:`{subjectType,subjectId,roleId,resourceType:"project",resourceId:"prj_prod",target:{selector:{types:["compute.instance"],matchLabels:{env:"prod",team:"payments"}}}}`.»
> **Ground-truth (контекст из α/β, vault `resources/iam-access-binding.md`):**
> - **α (APPROVED, в проде):** `AccessBinding.target` (oneof `all_in_scope` (16) | `resources[]` | `selector`); `all_in_scope`+`resources[]` рабочие, `selector` непустой → **sync `UNIMPLEMENTED`** (α-13); role-coverage гейт (D-13); per-object FGA tuple `fga_type(ref.type):<id>#tier(verb)@subject` из `binding.target` (D-6); `hierarchyParentTuple` эмитится; `target.resources[].id` — opaque soft-ref **без** existence/containment (D-14/D-15 known-limitation, вынесено в γ); 3 гейта — (1) role-scope 1.5, (2) role-coverage α, (3) containment [вынесен в γ].
> - **β (в проде):** таблица `kacho_iam.resource_mirror` (`object_type` TEXT, `object_id` TEXT, `parent_project_id` TEXT, `parent_account_id` TEXT, `labels` JSONB, `source_version` BIGINT, `updated_at` TIMESTAMPTZ; PK `(object_type,object_id)`; GIN-индекс на `labels`) наполняется ребром `compute→iam` `RegisterResource` (monotonic по `source_version`). **В β mirror НЕ читался для authz** — только наполнялся. proto несёт `ResourceSelector{types, match_tags}`. Инфраструктура `ConditionalTuple.Condition` существует. condition-поля на `AccessBinding` (`condition_id`/`builtin_condition`(incl `NON_EXPIRED`)/`expires_at`) существуют (KAC-127).
> - `access_bindings`: `expires_at` TIMESTAMPTZ NULL (CHECK `> created_at`); state machine `PENDING → ACTIVE → REVOKED`; индекс `(status, expires_at)` под expiry-scan; transitions через atomic CAS UPDATE (ban #10).
> - **Карта владельцев / граф (`polyrepo.md`):** `compute→iam` `RegisterResource` уже существует (наполняет mirror); ребра `iam→compute`/`iam→vpc` **НЕ существуют и не вводятся** (был бы цикл — non-negotiable «циклы запрещены»). Containment в γ резолвится **из IAM same-DB `resource_mirror.parent_*`**, без peer-call.
> **Образцы формата:** `epic-resource-scoped-access-binding-alpha-acceptance.md` (родительский α), `sub-phase-1.5-assignable-roles-acceptance.md`.

---

## Обзор

Под-фаза **γ** активирует третью ветку `AccessBinding.target` — **`selector`** (label-based grant), снимая `UNIMPLEMENTED`-заглушку α-13, и делает рабочим целевой грант заказчика: «дать субъекту роль на **все объекты типов `T` с метками `L`** под scope-anchor». Membership такого гранта **динамичен** — новый объект с подходящими метками автоматически попадает под грант, снятие метки снимает доступ. Это рабочий **вариант C** эпика.

Одновременно γ закрывает два долга α, ставшие технически разрешимыми после β (mirror содержит `parent_*` и `labels`):
- **containment** (D-14 α known-limitation) — теперь и для `resources[]` (byName), и для `selector` (byLabel): «объект обязан лежать под scope» проверяется **из IAM same-DB `resource_mirror.parent_*`** (НЕ peer-call → НЕ цикл);
- **expiry** — TTL-гранты (`expires_at`) реально истекают через **eager-revoke в reconciler**, а не вычисляются на каждом Check.

Механизм — **IAM reconciler-worker** (outbox-driven, как существующие kacho-iam воркеры): он материализует selector → per-object FGA tuples, диффит при изменениях mirror/expiry, эмитит/eager-revoke'ит tuples через `fga_outbox` атомарно. `selector` становится mutable через новый async RPC `ReplaceTargetSelector` (CAS по `resource_version`). proto-rename `match_tags → match_labels` (намеренный pre-activation breaking — 0 wire-clients).

Документ описывает **только внешнее наблюдаемое поведение API/UI** (gRPC-коды, REST-формы, статусы membership, eventual-consistency-семантику), не реализацию. Сценарии трассируются в имена integration-/newman-/UI-тестов через ID `γ-<NN>`. Стандартные конвенции (`api-conventions.md`, `security.md`, `data-integrity.md`) нормативны и в тело не дублируются — только ссылками (§1).

---

## 0.1 Карта эпика (контекст — детальные сценарии ТОЛЬКО для γ)

| Под-фаза | Содержание | Статус |
|---|---|---|
| **α** (APPROVED, прод) | `target` oneof: `all_in_scope`+`resources[]` рабочие; `selector`→`UNIMPLEMENTED`; role-coverage гейт; per-object tuple + `hierarchyParentTuple`; `target.id` opaque без containment (D-14 known-limit) | вне scope γ |
| **β** (прод) | `resource_mirror` (object_type/object_id/parent_project_id/parent_account_id/labels jsonb/source_version/updated_at) наполняется `compute→iam RegisterResource` (monotonic). Mirror НЕ читался для authz. proto `ResourceSelector{types,match_tags}`. condition-инфра | вне scope γ (предусловие) |
| **γ** (ЭТОТ док) | Активация `selector` end-to-end (label-membership через mirror) + containment (byName и byLabel из mirror.parent) + expiry (eager-revoke в reconciler). reconciler-worker диффит per-object FGA tuples. `ReplaceTargetSelector` (async). proto rename `match_tags→match_labels`, condition oneof формализация. `compute.instance` тип (vpc-типы — следующая итерация) | **Сценарии γ-01..γ-24 ниже** |
| **δ** (future — упомянуть) | Чистая форма `scope:{}` (аддитивно non-breaking) | вне scope γ (forward-ref) |
| **ε** (future — упомянуть) | Прочие builtin-conditions (не `non_expired`): CEL-вычисление на Check-пути. γ их только schema-forward'ит (эмитит в conditional-tuple metadata, Check НЕ вычисляет) | вне scope γ (forward-ref) |

---

## 0. Фиксированные дизайн-решения (предлагаются автором; подлежат approve ревьюером — затем НЕ переоткрывать)

| ID | Решение | Обоснование |
|---|---|---|
| **D1** | **Containment — hybrid (sync-если-знаем + eventual-verify).** На `Create`/`AddTargetResources`/`ReplaceTargetSelector`: для каждого таргетируемого объекта (`resources[]` byName или materialized-set byLabel) **если объект ЕСТЬ в `resource_mirror`** → containment вычисляется **синхронно** из `mirror.parent_*` vs scope-anchor: **под scope → OK; НЕ под scope → отказ** (`FAILED_PRECONDITION` для byName, ref помечается `REJECTED`+audit для byLabel). **Если объекта НЕТ в mirror** (гонка: грант раньше `RegisterResource`) → ref/membership получает статус **`PENDING_VERIFICATION`**, FGA-tuple НЕ эмитится; reconciler позже (по приходу mirror-row) верифицирует: под scope → `ACTIVE`+эмит tuple; не под scope → `REJECTED`+audit (**не silent**). Per-ref / per-membership verification-status, наблюдаемый на чтении. | Containment теперь решается **same-DB из `resource_mirror.parent_*`** (β наполнил) — НЕ peer-call `iam→compute/vpc`, цикл не вводится (закрывает D-14 α без нарушения non-negotiable). Hybrid нужен из-за eventual-consistency edge `compute→iam`: на момент гранта mirror может ещё не знать объект; «sync-reject когда знаем, eventual-verify когда не знаем» — fail-safe (нет tuple до подтверждения containment) и не отбрасывает легитимные гранты в гонке. REJECTED фиксируется в audit, а не молча — оператор видит «объект не под scope». |
| **D2** | **`target` частично mutable.** `subject_*` / `role_id` / scope-anchor (`resource_type`/`resource_id`/`scope`) **остаются immutable** (как α/§4.3 kacho-iam). **`selector` mutable** через новый async RPC **`ReplaceTargetSelector`** (atomic replace всего selector, CAS по `resource_version`); `resources[]` mutable через α-`Add`/`RemoveTargetResources` (без изменений). Изменение selector → reconciler пересчитывает membership-diff (добавленные → эмит, выпавшие → eager-revoke). Смена **ветки** oneof (`resources` ⇄ `selector` ⇄ `all_in_scope`) — НЕ поддержана, только `Delete`+`Create` (как α-D10). | Селектор — единственная «настраиваемая политика» гранта (объекты приходят/уходят сами по меткам); ручной replace selector — естественная мутация. CAS по `resource_version` сериализует конкурентные replace (OCC, ban #10 — не TOCTOU). Subject/role/scope-immutability — инвариант AccessBinding (смена = новый грант). |
| **D3 (condition)** | **Рабочий condition в γ — ТОЛЬКО `non_expired` (TTL)**, реализованный **expiry eager-revoke в reconciler** (НЕ CEL-вычислением на Check-пути). `expires_at` наступил → reconciler eager-revoke'ит FGA-tuples + CAS `status→REVOKED`. **Прочие builtin-conditions — schema-only forward**: формализуются в proto `condition` oneof (`none` | `expiry` | `forward`-для-будущих), эмитятся в conditional-tuple metadata, но Check их НЕ вычисляет (→ ε-волна, вне γ). `non_expired` НЕ кодируется в conditional-tuple-condition (он реализован revoke'ом, не Check-time). | Решение «expiry через eager-revoke, не CEL-на-Check»: Check остаётся простым (нет CEL-runtime на каждом authz-запросе), TTL надёжно истекает воркером. Прочие conditions — forward-only schema (γ не вводит CEL-engine; их активация — ε). Одна рабочая семантика condition в γ = детерминированность. |
| **D4 (parent_account_id)** | **`resource_mirror.parent_account_id` дополняется IAM same-DB** из `projects.account_id` (IAM — владелец Project), НЕ cross-service-вызовом. Когда `RegisterResource` приносит `parent_project_id`, IAM при upsert mirror-row резолвит `account_id` из своей таблицы `projects` (same-DB JOIN). | `account`-scoped selector-грант требует знать account объекта; объект знает свой project, IAM знает project→account (Project — его ресурс). Резолв same-DB → нет нового ребра, нет цикла. |
| **D5 (rename)** | **proto rename `ResourceSelector.match_tags` → `match_labels`** в γ-proto (одновременно с активацией selector). Pre-activation: 0 wire-clients (β только объявил поле, никто не слал непустой selector — α reject'ил `UNIMPLEMENTED`). `buf breaking` ожидаемо краснеет на этом поле — **намеренный, осознанный** breaking (фиксируется в PR-описании + by-design). | Заказчик/целевой JSON оперирует `matchLabels` (метки ресурса, не «теги» — теги были β-governance-концепцией, отдельной от resource-labels). Имя выравнивается на семантику «метки объекта в mirror». Делается СЕЙЧАС, пока нет клиентов, чтобы не ломать позже. |
| **D6 (selector-семантика)** | **`matchLabels` — AND-equality match** по `resource_mirror.labels` (JSONB `@>` containment): объект matches, если для **каждой** пары `k:v` из `matchLabels` выполнено `labels[k]==v` (superset допустим — у объекта могут быть лишние метки). Пустой `matchLabels` → `INVALID_ARGUMENT` (грант «на всё в scope» = `all_in_scope`, не selector). `types` — непустой whitelist (closed-table `authzmap.ObjectType`); объект matches, только если `object_type ∈ types`. Membership = `types`-фильтр AND `matchLabels`-фильтр AND containment-под-scope. | AND-equality `@>` — детерминированный, индексируемый (GIN на `labels`), без regex/range-сложности (range/`In`-операторы — будущая итерация). Пустой `matchLabels` запрещён, чтобы не было двух способов сказать «весь scope». `types` непустой — selector обязан ограничить тип (FGA-object-type детерминирован). |
| **D7 (reconciler)** | **IAM reconciler-worker** — outbox-driven фоновый воркер (паттерн существующих kacho-iam воркеров: LRO-worker, expiry-cron KAC-127). Триггеры пересчёта: **(a)** `Create`/`ReplaceTargetSelector` с selector (новый/изменённый грант); **(b)** изменение `resource_mirror` (`RegisterResource` принёс/обновил/удалил объект → его labels/parent изменились); **(c)** `expires_at` наступил. На каждый триггер: вычислить **desired** per-object FGA-tuple-set (matched-под-scope) → **diff** с текущим → эмит добавленных / **eager-revoke** выпавших|expired через `fga_outbox` (+`hierarchyParentTuple`), всё в одной writer-tx (ban #10). | Selector-membership динамичен (метки меняются вне IAM) → нужен материализующий воркер, а не on-Check-вычисление (Check остаётся O(1) tuple-lookup, нет mirror-scan на authz-пути). Outbox-tx — существующий атомарный путь kacho-iam (tuple-emission ⊕ state в одной tx). Eager-revoke (а не lazy) — tuple исчезает сразу при выпадении, доступ снимается. |
| **D8 (status модель)** | **Per-membership / per-ref verification status:** `ACTIVE` (под scope, tuple эмитится) | `PENDING_VERIFICATION` (объект ещё не в mirror — гонка; tuple НЕ эмитится) | `REJECTED` (в mirror, но НЕ под scope — tuple НЕ эмитится, audit-запись). Для byLabel — это статус каждого materialized-члена; для byName (`resources[]`) — статус каждого ref. AccessBinding-level `status` (`PENDING`/`ACTIVE`/`REVOKED`) — без изменений (α/KAC-127); membership-статусы — отдельная проекция, наблюдаемая на чтении binding'а. | Eventual-consistency edge `compute→iam` означает, что часть таргета может быть «ещё не подтверждена». Явный per-member status (вместо silent drop) даёт оператору наблюдаемость «что под грантом сейчас, что ждёт верификации, что отклонено». REJECTED → audit (не silent) — требование заказчика «не silent». |
| **D9 (expiry)** | **Expiry — reconciler scan + eager-revoke.** Воркер периодически сканирует `access_bindings WHERE status='ACTIVE' AND expires_at IS NOT NULL AND expires_at < now()` (индекс `(status, expires_at)`) → для каждого: eager-revoke **всех** per-object FGA-tuples гранта через `fga_outbox` + CAS `UPDATE … WHERE status='ACTIVE' AND id=$id → status='REVOKED', revoked_at=now()` (ban #10 CAS). После REVOKED Check → denied. condition `non_expired` прокидывается в conditional-tuple metadata (forward, D3), но фактическое истечение делает revoke (не Check-time CEL). | Eager-revoke надёжнее lazy-Check-expiry (tuple физически исчезает; нет окна «expired но ещё allowed по кэшу»). CAS на `status` сериализует с конкурентным Delete/Activate. Переиспользует KAC-127 expiry-cron инфраструктуру (индекс + state machine). |
| **D10 (containment byName, закрытие α-D14)** | **Containment-гейт закрывается и для `resources[]` (byName).** В α `resources[].id` принимался opaque без containment (D-14). В γ: на `Create`/`Add` для byName-ref — **если объект в mirror и НЕ под scope → `FAILED_PRECONDITION` `"<type>:<id> is not contained in scope <scope-type>:<scope-id>"`** (sync-reject в async-worker, `Operation.error`); **если не в mirror → `PENDING_VERIFICATION`** (как selector, D1). Закрывает α known-limitation «чужой объект под своим scope». | β сделал containment вычислимым same-DB (`mirror.parent_*`). α-D14 явно зарезервировал закрытие за γ. byName и byLabel используют **один** containment-предикат (parity) — нет обхода через byName. |
| **D11 (ReplaceTargetSelector vs Delete+Create)** | **`selector` меняется через `ReplaceTargetSelector` (async, atomic CAS), НЕ через Delete+Create.** Replace атомарно заменяет весь selector (полная замена, не merge), CAS по `resource_version`; reconciler диффит старый materialized-set vs новый → revoke выпавших + эмит добавленных. Это сохраняет binding-id, audit-trail, condition. Смена ветки oneof (selector→resources) по-прежнему = Delete+Create (D2). | Selector — мутабельная политика; пересоздание binding'а на каждое изменение метки-фильтра рвало бы id/audit/history. Atomic replace + reconciler-diff — минимально-инвазивная мутация. CAS защищает от lost-update при конкурентных replace. |
| **D12 (dangling reconcile-sweep)** | **β-residual: периодический reconcile-sweep сверяет materialized FGA-tuples с актуальным mirror-состоянием** (объект удалён из mirror / метки изменились так, что больше не matches / больше не под scope) → eager-revoke устаревших tuples. Покрывает случай, когда триггер (b) был пропущен (потеря outbox-события / рестарт воркера до обработки). Sweep идемпотентен (diff desired vs actual). | Defense-in-depth против дрейфа materialized-set от mirror-истины (eventual-consistency, потерянные события). Idempotent diff-sweep — стандартный reconciler-паттерн (desired-state reconciliation). |
| **D13 (типы в γ)** | **γ активирует selector ТОЛЬКО для `compute.instance`** (тип из closed-table `authzmap.ObjectType`, mirror наполняется `compute→iam`). vpc-типы (`vpc.subnet`/`vpc.network`) — следующая итерация (требует `vpc→iam RegisterResource`, наполняющего mirror vpc-объектами; вне scope γ). `selector.types` с типом без mirror-наполнения → membership всех таких объектов `PENDING_VERIFICATION` навсегда (нет источника) — на γ запрещаем sync `INVALID_ARGUMENT` для типов без активного mirror-feed. | Mirror для compute уже наполняется (β). vpc-feed — отдельная работа. Запрет selector на не-наполняемый тип предотвращает «вечный PENDING» (грант, который никогда не активируется). |

---

## 1. Связь с регламентом (нормативно; в тело не дублируется)

| Регламент | Где соблюдается |
|---|---|
| `api-conventions.md` — read **sync**, мутации async `Operation`; Watch не существует (polling Operation/List) | `ReplaceTargetSelector` async→Operation (§C); membership наблюдается через `Get`/`ListByResource` sync (§A) |
| `api-conventions.md` — flat message + oneof; `AccessTarget.selector` ветка активируется; `condition` oneof формализуется (D3) | D2, D3, D5, §2.1 |
| `api-conventions.md` — REST `:verb`-suffix (`:replaceTargetSelector`); JSON camelCase (`matchLabels`, `selector`, `types`, `verificationStatus`) | §C REST-формы, §J |
| `api-conventions.md` — error-format; malformed → sync `INVALID_ARGUMENT`; состояние → `FAILED_PRECONDITION` (async → `Operation.error`, ban #9) | D1, D6, D10, D13, γ-08..γ-12, γ-16 |
| `data-integrity.md` §within-service — CAS на `resource_version` (selector replace) + `status` (expiry); `resource_mirror` GIN `@>`; concurrent → integration-тест ≥2 goroutine | D2, D9, D11, γ-18, γ-19 |
| `data-integrity.md` §cross-domain — containment резолвится из IAM **same-DB** `resource_mirror.parent_*` (НЕ peer-call); `target.id` остаётся soft-ref; dangling переживается; mirror — output-only зеркало владельца (source = owner) | D1, D4, D10, γ-04, γ-12, γ-21 |
| `data-integrity.md` §cross-domain — **γ НЕ вводит ребра `iam→compute/vpc`** (containment из mirror, не из owner-call) — ацикличность графа сохранена | D1, D10, §6 S2 |
| `security.md` §AuthN+AuthZ ВЕЗДЕ — каждый RPC per-RPC Check; `requireGrantAuthority` на `ReplaceTargetSelector`; анонимный fail-closed | D2, γ-10, γ-11 |
| `security.md` §Internal-vs-external — `ReplaceTargetSelector` **public** (tenant grant-форма), НЕ Internal | §C (public endpoint) |
| `security.md` §инфра-чувствительные — `resource_mirror.labels` отдаются как tenant-facing метки; placement/underlay в selector-membership НЕ светятся | D6, γ-16 |
| `00-kacho-core.md` ban #9 (мутации→Operation), #10 (within-DB CAS, не TOCTOU), #4 (same-DB cascade), #8 (нет shared БД — mirror НЕ источник истины), #12 (TDD), #1 (APPROVED перед кодом) | §C async; D2/D9 CAS; D7 outbox-tx; §6 DoD RED→GREEN |
| `polyrepo.md` §порядок merge | §6 DoD: proto → iam → api-gateway → ui → deploy → workspace(docs) |
| sub-phase α (APPROVED) — `all_in_scope`/`resources[]` контракт + role-coverage гейт сохраняются; selector снимает `UNIMPLEMENTED` | D1, D10, γ-22 (α non-regression) |
| `buf breaking` намеренный (rename `match_tags→match_labels`, pre-activation, 0 clients) | D5, §6 S1 |

---

## 2. Selector-модель, containment, expiry (нормативно — D1/D6/D9/D13)

### 2.1 Форма (proto-ориентир — финал за `proto-api-reviewer`)

```
// γ: rename match_tags → match_labels (D5, намеренный breaking, 0 wire-clients)
message ResourceSelector {
  repeated string         types        = 1;   // непустой; ⊆ closed-table; γ: только compute.instance (D13)
  map<string,string>      match_labels = 2;   // непустой; AND-equality по resource_mirror.labels (@>, D6)
}

message AccessTarget {                         // α — без изменений формы oneof
  oneof target {
    bool             all_in_scope = 1;
    ResourceRefList  resources    = 2;
    ResourceSelector selector     = 3;          // γ: активируется (был UNIMPLEMENTED на α)
  }
}

// condition oneof формализация (D3) — рабочий только expiry(non_expired):
//   none | expiry(expires_at) | forward(прочие builtin — schema-only, Check НЕ вычисляет → ε)

// AccessBinding.target.resources[] / selector-membership несут per-ref/per-member:
//   verification_status: ACTIVE | PENDING_VERIFICATION | REJECTED   (D8, output-only)

// Новый RPC:
//   rpc ReplaceTargetSelector(ReplaceTargetSelectorRequest) returns (operation.Operation);  // async (D2/D11)
```

### 2.2 Containment-предикат (D1/D10 — единый для byName и byLabel)

Для объекта `O{type,id}` и scope-anchor `S{type=project|account|cluster, id}`:

| Состояние mirror | Containment-вердикт | Действие |
|---|---|---|
| `O` в mirror **И** `mirror.parent_*` ⊑ `S` (под scope) | **OK** | tuple эмитится; status `ACTIVE` |
| `O` в mirror **И** `mirror.parent_*` ⋢ `S` (не под scope) | **REJECT** | byName → `Operation.error` FAILED_PRECONDITION; byLabel → member `REJECTED`+audit; tuple НЕ эмитится |
| `O` **НЕ** в mirror (гонка / нет feed) | **UNKNOWN** | status `PENDING_VERIFICATION`; tuple НЕ эмитится; reconciler довычислит по приходу mirror-row |

`⊑` (под scope): `project:P` ⊑ `project:P`; `project:P` ⊑ `account:A` если `mirror.parent_account_id==A` (D4); любой ⊑ `cluster:cluster_kacho_root`.

### 2.3 Матрица `selector` × поведение (γ)

| Вход | Валидность | Поведение |
|---|---|---|
| `selector{types:[compute.instance], matchLabels:{env:prod}}`, объекты под scope в mirror | ✅ | membership materialized; per-object tuples на matched-под-scope; новый matched объект → reconciler добавляет (γ-02) |
| `selector` с `matchLabels` пустым | ❌ `INVALID_ARGUMENT` | «весь scope» = `all_in_scope` (D6) |
| `selector` с `types` пустым | ❌ `INVALID_ARGUMENT` | selector обязан ограничить тип (D6) |
| `selector.types` ⊄ closed-table | ❌ `INVALID_ARGUMENT` | unknown тип (D6) |
| `selector.types` содержит тип без mirror-feed (напр. vpc.* на γ) | ❌ `INVALID_ARGUMENT` | предотвращает «вечный PENDING» (D13) |
| `selector.types` ⊄ role-coverage (role.permissions) | ❌ `Operation.error` FAILED_PRECONDITION | role-coverage гейт (α D-13, переиспользуется для selector.types) |
| matched объект НЕ под scope | member `REJECTED`+audit | tuple НЕ эмитится (D1/D8) |
| matched объект ещё не в mirror | member `PENDING_VERIFICATION` | eventual-verify (D1/D8) |

---

## §A — Backend: selector membership (наблюдение через read)

> Membership selector-гранта наблюдается через существующие sync read (`Get`/`ListByResource`) — отдельного Watch нет (`api-conventions.md`). Каждый materialized-член несёт `verificationStatus` (D8).

### Сценарий γ-01: Happy path — Create с selector → matched объект получает доступ

**ID:** `γ-01`

**Given** account `acc-A` c проектом `prj_prod` (owner `usr-OWNER`)
**And** reusable роль `rol-computeeditor` (verb-bundle на `compute.instance.*`; assignable на `prj_prod` по 1.5; покрывает `compute.instance` по role-coverage)
**And** в `resource_mirror` под `prj_prod` есть `inst-1` c labels `{env:prod, team:payments}` и `inst-2` c labels `{env:dev}`
**And** caller — `usr-OWNER`

**When** caller вызывает `POST /iam/v1/accessBindings` c payload:
  - `subjectType` = `"user"`, `subjectId` = `"usr-MEMBER"`
  - `roleId` = `"rol-computeeditor"`
  - `resourceType` = `"project"`, `resourceId` = `"prj_prod"`, `scope` = `PROJECT`
  - `target` = `{ "selector": { "types":["compute.instance"], "matchLabels":{"env":"prod","team":"payments"} } }`

**Then** RPC возвращает `Operation`; poll `OperationService.Get(id)` до `done=true`
**And** Operation `done && !error`; `response` несёт `AccessBinding` c `id` (acb-…), `createdAt`, `target.selector` с теми же `types`/`matchLabels`
**And** reconciler материализует membership: `inst-1` (matches AND под scope) → `verificationStatus=ACTIVE`, эмитится per-object tuple `compute_instance:inst-1#<tier>@user:usr-MEMBER` (+`hierarchyParentTuple`); `inst-2` НЕ matches (`env:dev`) → не в membership
**And** `InternalIAMService.Check` на `inst-1` → allowed; на `inst-2` → НЕ allowed (точечность по меткам)

### Сценарий γ-02: Eventual — объект помечается env=prod ПОСЛЕ гранта → доступ появляется (reconciler emit)

**ID:** `γ-02`

**Given** selector-binding из γ-01 (`matchLabels:{env:prod, team:payments}`) активен
**And** инстанс `inst-3` под `prj_prod` c labels `{env:dev, team:payments}` (НЕ matches — нет доступа)

**When** владелец (kacho-compute) меняет метку `inst-3` → `{env:prod, team:payments}` и шлёт `RegisterResource` (mirror обновляется monotonic)

**Then** (eventual) reconciler по триггеру (b) пересчитывает membership: `inst-3` теперь matches AND под scope → добавляется в membership `ACTIVE`, эмитится per-object tuple
**And** после reconcile-lag `Check` на `inst-3` → allowed (новый объект автоматически попал под грант — суть варианта C)
**And** до reconcile (lag) `Check` на `inst-3` → ещё НЕ allowed (eventual-consistency — см. γ-21)

### Сценарий γ-03: Eventual — снятие метки env=prod→dev → доступ снимается (eager-revoke)

**ID:** `γ-03`

**Given** selector-binding из γ-01; `inst-1` (`{env:prod, team:payments}`) сейчас `ACTIVE` в membership, tuple эмитится, Check allowed

**When** владелец меняет `inst-1` → `{env:dev, team:payments}` (больше НЕ matches) и шлёт `RegisterResource`

**Then** reconciler по триггеру (b) пересчитывает: `inst-1` выпал из matched-set → **eager-revoke** per-object tuple через `fga_outbox`; `inst-1` убран из membership
**And** после reconcile `Check` на `inst-1` → НЕ allowed (снятие метки сняло доступ); binding-level `status` остаётся `ACTIVE` (другие члены живы)

### Сценарий γ-04: Containment (byLabel) — matched объект чужого проекта → REJECTED+audit (не silent)

**ID:** `γ-04`

**Given** selector-binding на scope `project:prj_prod`, `matchLabels:{env:prod}`
**And** в mirror есть `inst-foreign` c labels `{env:prod}`, но `mirror.parent_project_id = prj_other` (другой проект)

**When** reconciler материализует membership

**Then** `inst-foreign` matches по labels/types, **но НЕ под scope** (`prj_other ⋢ prj_prod`) → member `verificationStatus=REJECTED`; per-object tuple **НЕ** эмитится (D1/D8)
**And** пишется **audit-запись** «`compute.instance:inst-foreign` rejected: not contained in scope project:prj_prod» (не silent — требование заказчика)
**And** `Check` на `inst-foreign` от `usr-MEMBER` → НЕ allowed (containment закрыл α known-limitation D-14)

### Сценарий γ-05: PENDING_VERIFICATION → ACTIVE (объект приходит в mirror после гранта)

**ID:** `γ-05`

**Given** selector-binding `matchLabels:{env:prod}` на `prj_prod`
**And** инстанс `inst-late` создаётся во владельце c `{env:prod}` под `prj_prod`, НО `RegisterResource` ещё не дошёл (mirror не знает `inst-late`)

**When** reconciler материализует membership на момент гранта/триггера

**Then** `inst-late` НЕ в mirror → НЕ попадает в membership (нечего матчить ещё); никакого tuple
**And** _(позже)_ `RegisterResource` приносит `inst-late` c `{env:prod}`, `parent_project_id=prj_prod` → reconciler триггер (b) → matches AND под scope → member `ACTIVE`, tuple эмитится → `Check` allowed

> _Примечание (D8):_ `PENDING_VERIFICATION` явно возникает в byName-сценарии γ-13 (ref на объект, которого ещё нет в mirror). Для byLabel «объект ещё не в mirror» = «ещё не член membership» (матчить нечего), поэтому γ-05 — переход «появился в mirror → ACTIVE».

### Сценарий γ-13: PENDING_VERIFICATION (byName) → доступ только после верификации

**ID:** `γ-13`

**Given** `Create` c `target.resources=[{compute.instance, inst-notyet}]` на scope `project:prj_prod`, где `inst-notyet` **ещё не в mirror**, caller — owner

**When** caller вызывает `Create` → poll Operation

**Then** Operation `done && !error`; binding создан; ref `inst-notyet` несёт `verificationStatus=PENDING_VERIFICATION`; per-object tuple **НЕ** эмитится (containment не подтверждён — D1/D10)
**And** `Check` на `inst-notyet` → НЕ allowed (нет tuple)

**When** `RegisterResource` приносит `inst-notyet` c `parent_project_id=prj_prod` (под scope)
**Then** reconciler триггер (b) верифицирует → ref `ACTIVE`, tuple эмитится → `Check` allowed

### Сценарий γ-14: PENDING_VERIFICATION (byName) → REJECTED (объект пришёл, но не под scope)

**ID:** `γ-14`

**Given** binding из γ-13 c ref `inst-notyet` в `PENDING_VERIFICATION`

**When** `RegisterResource` приносит `inst-notyet`, но `parent_project_id=prj_other` (НЕ под `prj_prod`)

**Then** reconciler верифицирует → ref `verificationStatus=REJECTED`; tuple НЕ эмитится; audit-запись «not contained» (не silent — D8)
**And** `Check` → НЕ allowed; ref остаётся в binding как `REJECTED` (оператор видит причину), не вызывает паники

### Сценарий γ-15: Conformance — membership-read несёт verificationStatus, без инфра-полей

**ID:** `γ-15`

**Given** selector-binding γ-01 с членами `inst-1`(ACTIVE), `inst-foreign`(REJECTED)

**When** caller читает `Get(acb-…)` / `ListByResource`

**Then** ответ несёт materialized membership c `verificationStatus` per member (`ACTIVE`/`PENDING_VERIFICATION`/`REJECTED`) и tenant-facing `type`/`id`/`labels`-зеркало (D6/D8)
**And** ответ **не** содержит инфра-чувствительных полей (placement/underlay/wiring — `security.md`); membership — output-only проекция, source = owner-сервис

### Сценарий γ-24: Ре-верификация при смене `mirror.parent` — REJECTED↔ACTIVE (объект переезжает под/из-под scope; Q5=(b))

**ID:** `γ-24`

> Closed-decision Q5=(b): containment `REJECTED` **ре-верифицируем** — `mirror.parent_*` объекта может измениться (объект переехал в другой проект во владельце), и reconciler триггер (b) обязан ре-оценить его. γ-04/γ-14 покрывают только **вход** в `REJECTED`; γ-24 покрывает **выход** (оба направления). Это **смена scope через parent**, не выпадение по label (label-выпадение — γ-03).

**Направление A — REJECTED → ACTIVE (объект переехал ПОД scope):**

**Given** selector-binding на scope `project:prj_prod`, `matchLabels:{env:prod}`, subject `usr-MEMBER`
**And** в mirror `inst-foreign` c labels `{env:prod}` и `parent_project_id=prj_other` → член `verificationStatus=REJECTED` (matches по labels, но НЕ под scope — как γ-04), per-object tuple НЕ эмитится
**And** `Check`(`usr-MEMBER`, `inst-foreign`) → НЕ allowed

**When** владелец (kacho-compute) переносит `inst-foreign` в `prj_prod` и шлёт `RegisterResource` → IAM upsert'ит mirror-row монотонно по `source_version`: `parent_project_id` становится `prj_prod` (+ `parent_account_id` ре-резолвится same-DB из `projects.account_id`, D4)

**Then** reconciler по триггеру (b) ре-оценивает REJECTED-члена: теперь matches по labels AND **под scope** (`prj_prod ⊑ prj_prod`) → `verificationStatus` `REJECTED → ACTIVE`; per-object tuple `compute_instance:inst-foreign#<tier>@user:usr-MEMBER` эмитится через `fga_outbox` (+`hierarchyParentTuple`)
**And** после reconcile `Check`(`usr-MEMBER`, `inst-foreign`) → allowed (REJECTED не терминальный — Q5=(b))
**And** audit-запись «`compute.instance:inst-foreign` re-verified: now contained in scope project:prj_prod»

**Направление B — ACTIVE → REJECTED (объект уехал ИЗ-под scope через смену parent, не label):**

**Given** тот же selector-binding; `inst-moving` c `{env:prod}`, `parent_project_id=prj_prod` → член `ACTIVE`, tuple эмитится, `Check` allowed
**And** объект остаётся matched по labels (`env:prod` не меняется — это НЕ label-выпадение γ-03)

**When** владелец переносит `inst-moving` в `prj_other` (метки те же) и шлёт `RegisterResource` → mirror-row монотонно: `parent_project_id` становится `prj_other`

**Then** reconciler по триггеру (b) ре-оценивает: всё ещё matches по labels, но **больше НЕ под scope** (`prj_other ⋢ prj_prod`) → `verificationStatus` `ACTIVE → REJECTED`; per-object tuple **eager-revoke** через `fga_outbox`; audit-запись «`compute.instance:inst-moving` rejected: no longer contained in scope project:prj_prod»
**And** после reconcile `Check`(`usr-MEMBER`, `inst-moving`) → НЕ allowed (scope-выпадение через parent сняло доступ — отличается от γ-03 label-выпадения тем, что объект остаётся matched, но REJECTED, а не покидает membership)
**And** binding-level `status` остаётся `ACTIVE` (другие члены живы)

---

## §C — Backend: Create(selector) + ReplaceTargetSelector + expiry

REST: `POST /iam/v1/accessBindings` (body несёт `target.selector`); `POST /iam/v1/accessBindings/{access_binding_id}:replaceTargetSelector`.
gRPC: `Create`/`ReplaceTargetSelector` — async → Operation (ban #9).

### Сценарий γ-08: Negative — невалидный selector → sync INVALID_ARGUMENT

**ID:** `γ-08`

**Given** аутентифицированный caller, grant-authority на `prj_prod`

**When** `Create` c `target.selector={types:[], matchLabels:{env:prod}}` (пустой types) → **Then** sync `INVALID_ARGUMENT` `"target.selector.types must not be empty"` (D6), до Operation
**When** `Create` c `target.selector={types:[compute.instance], matchLabels:{}}` (пустой matchLabels) → **Then** sync `INVALID_ARGUMENT` `"target.selector.matchLabels must not be empty (use all_in_scope for entire scope)"` (D6)
**When** `Create` c `target.selector={types:[foo.bar], matchLabels:{env:prod}}` (unknown type) → **Then** sync `INVALID_ARGUMENT` `"Illegal argument target.selector.types (unknown resource type)"` (D6)
**When** `Create` c `target.selector={types:[vpc.subnet], matchLabels:{env:prod}}` (тип без mirror-feed на γ) → **Then** sync `INVALID_ARGUMENT` `"target.selector.types: vpc.subnet is not selectable yet (no resource feed)"` (D13)

### Сценарий γ-09: Negative — selector.types НЕ покрыт ролью → FAILED_PRECONDITION (role-coverage, α D-13 reuse)

**ID:** `γ-09`

**Given** scope `project:prj_prod`, роль `rol-computeonly` (verb'ы только на `compute.*`), assignable на `prj_prod` (1.5 проходит)

**When** caller вызывает `Create` c `target.selector={types:[vpc.network], …}` — _(для сценария: vpc.network гипотетически selectable, но роль его не покрывает; на γ vpc недоступен D13 → этот neg проверяется для compute с ролью без compute-verb'ов)_. Каноничный кейс: `selector.types=[compute.instance]`, роль БЕЗ единого verb'а на `compute.instance` → poll Operation

**Then** Operation `done && error.code = FAILED_PRECONDITION`, message `"role <id> does not grant any verb on compute.instance"` (role-coverage гейт α D-13 переиспользован для `selector.types`; детерминирован, same-DB)
**And** binding **не** создан; никакие tuple'ы не эмитятся

### Сценарий γ-10: AuthZ — caller без grant-authority → PERMISSION_DENIED

**ID:** `γ-10`

**Given** `prj_prod` (owner `usr-OWNER`); сторонний `usr-X` без grant-authority

**When** `usr-X` вызывает `Create` c selector ИЛИ `…:replaceTargetSelector`

**Then** gRPC `PERMISSION_DENIED`, REST `403` (`requireGrantAuthority` — тот же gate, что α/1.5); до постановки Operation/мутации

### Сценарий γ-11: Negative — анонимный caller → fail-closed

**ID:** `γ-11`

**Given** запрос без валидного principal (анонимный)

**When** вызывается `Create`(selector) / `…:replaceTargetSelector`

**Then** отклоняется fail-closed (gRPC `UNAUTHENTICATED`/`PERMISSION_DENIED`; REST `401`/`403` — `RequireAuthenticated`), до данных/мутации

### Сценарий γ-12: Containment (byName) — объект в mirror, но чужой scope → FAILED_PRECONDITION (закрытие α D-14)

**ID:** `γ-12`

**Given** scope `project:prj_prod`, reusable роль; в mirror `inst-other` c `parent_project_id=prj_other` (чужой проект)

**When** caller вызывает `Create` c `target.resources=[{compute.instance, inst-other}]` → poll Operation

**Then** Operation `done && error.code = FAILED_PRECONDITION`, message `"compute.instance:inst-other is not contained in scope project:prj_prod"` (containment-гейт byName — D10; в α это принималось opaque, теперь reject; объект В mirror и НЕ под scope)
**And** binding **не** создан; tuple не эмитится; (закрывает α-05/D-14 known-limitation)

> _Примечание:_ если `inst-other` **НЕ** в mirror — поведение γ-13 (`PENDING_VERIFICATION`), а не reject. Reject — только когда mirror авторитетно говорит «чужой scope».

### Сценарий γ-16: Expiry — TTL-грант истекает → eager-revoke → denied

**ID:** `γ-16`

**Given** selector-binding на `prj_prod` c `expires_at` = now+T (короткий TTL); `inst-1` matches, `ACTIVE`, tuple эмитится, `Check` allowed
**And** binding-level `status=ACTIVE`

**When** наступает `expires_at < now`

**Then** reconciler expiry-scan (D9, индекс `(status, expires_at)`) находит грант → **eager-revoke** всех per-object tuples гранта через `fga_outbox` + CAS `UPDATE … WHERE status='ACTIVE' → status='REVOKED', revoked_at=now()`
**And** после reconcile `Check` на `inst-1` → НЕ allowed; `Get(acb-…)` → `status=REVOKED`, `revokedAt` заполнен
**And** condition `non_expired` прокинут в conditional-tuple metadata (forward D3), но фактическое истечение сделал revoke, не Check-time CEL

### Сценарий γ-18: ReplaceTargetSelector — atomic replace + reconciler diff (D2/D11)

**ID:** `γ-18`

**Given** selector-binding `acb-R` c `matchLabels:{env:prod}`; членами `inst-1`,`inst-2` (оба `env:prod`, ACTIVE, tuples эмитятся), caller — owner

**When** caller вызывает `POST …/acb-R:replaceTargetSelector` c `selector={types:[compute.instance], matchLabels:{env:prod, team:payments}}` (сузил) → poll Operation

**Then** Operation `done && !error`; selector заменён целиком (полная замена, не merge — D11)
**And** reconciler диффит: `inst-1`(`{env:prod,team:payments}`) остаётся ACTIVE; `inst-2`(`{env:prod}`, нет team:payments) выпал → **eager-revoke** его tuple
**And** `Get(acb-R).target.selector.matchLabels` = `{env:prod, team:payments}`; `Check` на `inst-2` → больше НЕ allowed, на `inst-1` → allowed
**And** binding-id, condition, audit-trail сохранены (не пересоздание — D11)

### Сценарий γ-19: Concurrency — конкурентные ReplaceTargetSelector → CAS, ровно один побеждает

**ID:** `γ-19`

**Given** selector-binding `acb-C` (`resource_version=V`), caller — owner

**When** запускаются **две конкурентные** `:replaceTargetSelector` (разные `matchLabels`), обе читали `resource_version=V`

**Then** **ровно одна** Operation `done && !error` (CAS `UPDATE … WHERE resource_version=V` прошёл, version→V+1); **вторая** Operation `done && error.code = FAILED_PRECONDITION` `"access binding was modified concurrently, retry"` (OCC lost-update guard, ban #10 — не TOCTOU)
**And** финальный selector детерминирован (значение победившего replace); materialized-set соответствует ему; нет «полу-применённого» selector
**And** _Обоснование (для `integration-tester`/`db-architect-reviewer`):_ CAS по `resource_version` на `access_bindings`-row сериализует конкурентные replace; concurrent integration-тест (testcontainers, ≥2 goroutine) ОБЯЗАТЕЛЕН (RED-first, S2 DoD).

### Сценарий γ-20: Concurrency — конкурентный label-flip + reconcile → membership детерминирован, без дублей tuple

**ID:** `γ-20`

**Given** selector-binding на `prj_prod` (`matchLabels:{env:prod}`); `inst-X` под scope

**When** конкурентно: (a) несколько `RegisterResource` для `inst-X` флипают `env` prod↔dev (monotonic `source_version`); (b) reconciler пересчитывает membership

**Then** финальное membership-состояние `inst-X` соответствует **последнему по `source_version`** mirror-row (monotonic — старый source_version игнорируется); ровно один tuple если финально matches, ноль если нет — без дублей/leak'а
**And** reconcile идемпотентен (diff desired vs actual); повторный прогон того же mirror-состояния не плодит tuple'ов
**And** concurrent integration-тест (≥2 goroutine, mirror-flip + reconcile) ОБЯЗАТЕЛЕН (RED-first)

### Сценарий γ-22: Conformance — α-ветки (all_in_scope/resources) и role-coverage НЕ регрессируют

**ID:** `γ-22`

**Given** существующие α-binding'и: `acb-AIS` (`all_in_scope`), `acb-RES` (`resources=[inst-1]` byName, созданный в α как opaque)

**When** читаются/проверяются после деплоя γ

**Then** `acb-AIS` → tier-tuple на scope (без изменений, α D-2); `acb-RES` → per-object tuple (без изменений)
**And** role-coverage гейт α D-13 продолжает reject'ить mis-covered target (для resources И selector — единый гейт)
**And** _Примечание:_ γ закрывает containment для byName (D10) **forward-only** — НЕ revoke'ит pre-γ `resources[]`-binding'и, чьи объекты задним числом окажутся не под scope (паритет α D-8 forward-only); containment-гейт применяется только к новым Create/Add/Replace после γ

### Сценарий γ-23: Delete — снятие selector-binding'а revoke'ит все materialized tuples

**ID:** `γ-23`

**Given** selector-binding `acb-D` с членами `inst-1`,`inst-2` (2 tuple'а), caller — owner

**When** caller вызывает `DELETE /iam/v1/accessBindings/acb-D` → poll Operation

**Then** Operation `done && !error`; binding удалён; **все** materialized per-object FGA tuple'а revoke'нуты (как α-23 / vault §Lifecycle); membership-проекция исчезает
**And** последующий `Get(acb-D)` → `NOT_FOUND`/`PERMISSION_DENIED`; reconciler не пытается ре-материализовать удалённый binding

---

## §B — UI: selector-режим в grant-форме

> γ добавляет в grant-форму (после α «весь scope / конкретные объекты») третий режим — **«По меткам»** (selector), и показывает membership с verification-статусами.

### Сценарий γ-06: Форма — режим «По меткам» (selector) доступен

**ID:** `γ-06`

**Given** оператор на grant-форме (resource-first): subject + scope (`prj_prod`) + reusable-роль выбраны

**When** форма отрендерила секцию «Цель»

**Then** доступны **три** режима: «Весь scope» (`all_in_scope`), «Конкретные объекты» (`resources[]`), **«По меткам»** (`selector`)
**And** при «По меткам» появляются: picker типа объекта (closed-table; на γ — `compute.instance`) + редактор `matchLabels` (key/value пары, ≥1)
**And** submit отправляет `Create` c `target.selector={types,matchLabels}` (γ-01)

### Сценарий γ-07: Форма — превью membership + verification-статусы

**ID:** `γ-07`

**Given** оператор задал `selector{types:[compute.instance], matchLabels:{env:prod}}` на `prj_prod`

**When** binding создан и форма/детальный экран читает `Get(acb-…)`

**Then** UI рендерит materialized membership: список объектов c `verificationStatus`-бейджем (`ACTIVE` зелёный / `PENDING_VERIFICATION` нейтральный / `REJECTED` красный + причина «не под scope»)
**And** оператор может изменить `matchLabels` через «Заменить селектор» → `:replaceTargetSelector` (γ-18); пустой `matchLabels` форма не даёт сабмитить (клиентская + серверная γ-08 валидация)

---

## §J — Smoke / e2e (заказчик: финальная верификация, шаг 7)

### Сценарий γ-21: e2e — label-based grant end-to-end + eventual + containment + expiry (REST + gRPC + UI)

**ID:** `γ-21`

**Given** развёрнутый стенд (`make dev-up`); bootstrap `acc-A` + `prj_prod` + owner; reusable SYSTEM-роль `rol-computeeditor`; под `prj_prod` — `inst-1`{env:prod,team:payments}, `inst-2`{env:dev}; чужой `inst-foreign`{env:prod} под `prj_other`; mirror наполнен через `compute→iam RegisterResource`

**When** owner создаёт selector-binding (REST `POST accessBindings`, целевой JSON):
  `{subjectType:"user", subjectId:"usr-MEMBER", roleId:"rol-computeeditor", resourceType:"project", resourceId:"prj_prod", target:{selector:{types:["compute.instance"], matchLabels:{env:"prod", team:"payments"}}}}` → poll Operation
**Then** Operation `done`; reconciler материализует: `inst-1` ACTIVE+tuple; `inst-2` не matches; `inst-foreign` REJECTED+audit (чужой scope, containment D1/D4)
**And** `InternalIAMService.Check`(`usr-MEMBER`, `inst-1`) → allowed; на `inst-2`/`inst-foreign` → НЕ allowed

**When** owner помечает `inst-2` → `{env:prod, team:payments}`, `RegisterResource` обновляет mirror
**Then** (eventual, после reconcile-lag) `Check`(`inst-2`) → allowed (новый matched объект попал под грант сам — вариант C)

**When** owner снимает метку `inst-1` → `{env:dev,...}`, `RegisterResource`
**Then** reconciler eager-revoke'ит tuple `inst-1`; `Check`(`inst-1`) → НЕ allowed

**When** owner вызывает `grpcurl … :replaceTargetSelector` сужая `matchLabels:{env:prod, team:payments, tier:critical}`
**Then** Operation done; reconciler диффит; объекты без `tier:critical` выпадают (tuples revoke); `Get` отдаёт новый selector

**When** создаётся отдельный TTL selector-binding c коротким `expires_at`; ждём истечения
**Then** reconciler eager-revoke'ит tuples + `status→REVOKED`; `Check` → denied; `Get` → `status=REVOKED`

**And** UI: grant-форма → режим «По меткам» → задать `types/matchLabels` → submit → детальный экран показывает membership c verification-бейджами (`inst-1` ACTIVE, `inst-foreign` REJECTED) → «Заменить селектор» меняет membership

---

## 5. Зафиксированные решения (closed — родитель закрыл Q1-Q5; НЕ переоткрывать)

Все пять вопросов закрыты заказчиком/родителем; склонность автора совпала с вердиктом. Решения нормативны для `writing-plans` / `db-architect-reviewer` / `system-design-reviewer`; форму материализации (Q2) финально утверждает `db-architect-reviewer` на impl.

| # | Вопрос | Вердикт (closed) | Обоснование |
|---|---|---|---|
| **Q1** | **Триггер reconciler на изменение `resource_mirror`** | **(c)** `RegisterResource`-handler пишет reconcile-событие в `fga_outbox`/reconcile-queue в **той же writer-tx**, что mirror-upsert (event-driven, atomic) + periodic sweep (D12) как defense-in-depth | Переиспользует существующий outbox-tx путь kacho-iam (атомарно с mirror-upsert, ban #10), без нового poll-цикла на горячем пути; sweep ловит потерянные события / рестарт воркера (eventual-consistency) |
| **Q2** | **Desired-state membership: материализованная таблица vs recompute** | **(a)** materialized `access_binding_target_members` (с `verification_status` per member) | Даёт наблюдаемый `verificationStatus` per member (D8) для read/UI без mirror-scan на read-пути; diff дешевле. **Конкретную форму таблицы (колонки/индексы/FK) утверждает `db-architect-reviewer` на impl** |
| **Q3** | **Интервал expiry-scan воркера** (D9) | **(c)** переиспользовать KAC-127 expiry-cron (индекс `(status, expires_at)`) — расширить его на eager-revoke FGA-tuples | KAC-127 cron уже сканирует `(status,expires_at)`; единый воркер expiry для всех binding-форм; eager-revoke tuples добавляется к существующему `status→REVOKED` CAS |
| **Q4** | **`ReplaceTargetSelector` vs `Delete`+`Create`** (D11) | **(a)** отдельный async `ReplaceTargetSelector` (CAS по `resource_version`, сохраняет id/audit/condition) | Selector — mutable-политика; пересоздание binding'а рвёт audit-trail и id (на которые могут ссылаться); CAS-replace минимально-инвазивен и сериализует конкурентные replace (γ-19) |
| **Q5** | **Containment `REJECTED` — терминальный или ре-верифицируемый?** | **(b)** ре-верифицируемый — `mirror.parent_*` может измениться (объект переехал); reconciler ре-оценивает REJECTED-членов при mirror-change | Объект может переехать под/из-под scope сменой parent; REJECTED не терминальный. **Покрыто γ-24** (оба направления REJECTED↔ACTIVE) |

> Поведение API наблюдаемо одинаково для всех вердиктов — закрытие влияет на план реализации (`writing-plans`) и DB-форму (`db-architect-reviewer`), не на сценарии. Все Q закрыты → S2 стартует без блокеров.

---

## 6. Definition of Done (на каждую стадию)

Кросс-репо порядок (`polyrepo.md`): **proto → iam → api-gateway → ui → deploy → workspace(docs)**. Стадии — самостоятельные deliverable'ы; CI нижестоящего пиннит sibling к feature-ветке до merge вышестоящего.

**S1 — proto (`kacho-proto`):**
- [ ] Rename `ResourceSelector.match_tags → match_labels` (D5, **намеренный `buf breaking`** — pre-activation, 0 wire-clients; задокументировать в PR + by-design); `types` остаётся.
- [ ] `condition` oneof формализация (D3): `none` | `expiry` | `forward`-каркас для прочих builtin (schema-only).
- [ ] RPC `ReplaceTargetSelector` (async → Operation) + request/response (`access_binding_id`, `selector`, `resource_version` для CAS); REST `:replaceTargetSelector`; permission/required_relation/scope_extractor/required_acr_min аннотации (паритет `Create`/`AddTargetResources`, D2/D10).
- [ ] `verification_status` (enum ACTIVE/PENDING_VERIFICATION/REJECTED) на per-ref/per-member проекции (D8, output-only).
- [ ] `buf lint` зелёный; `buf breaking` — краснеет ТОЛЬКО на ожидаемом rename (D5), остальное additive; `gen/go/...` регенерирован. Ревью — `proto-api-reviewer`.

**S2 — iam (`kacho-iam`):**
- [ ] RED integration-тесты (testcontainers) по γ-01..γ-24 первыми, **включая γ-19 (concurrent replace CAS), γ-20 (concurrent mirror-flip + reconcile), γ-16 (expiry eager-revoke), γ-04/γ-12/γ-14 (containment reject), γ-05/γ-13 (PENDING→ACTIVE), γ-24 (ре-верификация при смене mirror.parent — оба направления REJECTED↔ACTIVE, Q5=(b)), γ-22 (α non-regression)** → подтверждён красный → GREEN.
- [ ] Миграция: materialized membership-таблица (Q2=(a), closed) `access_binding_target_members`(binding_id FK CASCADE same-DB, type, id, verification_status, UNIQUE(binding_id,type,id)); `resource_mirror` read-path (GIN `@>` matchLabels); `parent_account_id` backfill из `projects.account_id` same-DB (D4). **Конкретную форму таблицы утверждает `db-architect-reviewer` на impl.** **Не редактировать применённые** (новая миграция, ban #5).
- [ ] `Create` принимает selector: формат-валидация sync (`INVALID_ARGUMENT`: пустой types/matchLabels, unknown/non-fed type — D6/D13) → role-coverage гейт (selector.types ⊆ role-types, α D-13 reuse, γ-09) → reconciler-материализация membership (containment из mirror.parent same-DB — D1; matched-под-scope → ACTIVE+tuple, в mirror-не-под-scope → REJECTED+audit, не-в-mirror → PENDING_VERIFICATION) → эмиссия per-object tuples из target + `hierarchyParentTuple` через `fga_outbox` **в writer-tx** (ban #10). **НЕТ peer-call iam→compute/vpc** (containment из mirror).
- [ ] Containment-гейт byName (D10): `Create`/`AddTargetResources` ref в mirror-не-под-scope → `Operation.error` FAILED_PRECONDITION (γ-12); не-в-mirror → PENDING_VERIFICATION (γ-13/γ-14). Закрывает α D-14. Forward-only (γ-22).
- [ ] `ReplaceTargetSelector` (D2/D11): atomic replace, **CAS по `resource_version`** (конкурентный → FAILED_PRECONDITION OCC, γ-19); reconciler membership-diff (revoke выпавших + эмит добавленных).
- [ ] **Reconciler-worker** (D7): триггеры (a) Create/Replace, (b) mirror-change (Q1=(c) closed: reconcile-событие в `fga_outbox` в той же writer-tx, что mirror-upsert RegisterResource), (c) expiry; desired-set diff → emit/eager-revoke через `fga_outbox` (+ idempotent reconcile-sweep D12). **(b)** ре-оценивает и REJECTED-членов при смене `mirror.parent_*` (Q5=(b) closed, γ-24).
- [ ] **Expiry eager-revoke** (D9): scan `(status,expires_at)` → revoke tuples + CAS `status→REVOKED` (γ-16). condition `non_expired` прокид в conditional-tuple metadata (forward D3).
- [ ] **Concurrent-non-regression тесты (testcontainers, ≥2 goroutine):** γ-19 (replace CAS), γ-20 (mirror-flip + reconcile idempotent) — ОБЯЗАТЕЛЬНЫ (RED-first, `data-integrity.md` §within-service п.5).
- [ ] Error-mapping (`INVALID_ARGUMENT`/`FAILED_PRECONDITION`/`PERMISSION_DENIED`/`UNAUTHENTICATED`), без leak pgx. `UNAVAILABLE` для containment в γ **НЕ применяется** (containment из mirror same-DB, не peer-call).
- [ ] by-design D1/D2/D3/D4/D5/D6/D7/D9/D10/D13 — запись в `docs/architecture/` kacho-iam (selector-материализация через reconciler; containment из mirror.parent same-DB — НЕ peer-call, ацикличность; expiry eager-revoke; rename match_tags→match_labels).
- [ ] Ревью — `db-architect-reviewer` (membership-таблица FK CASCADE/UNIQUE, CAS resource_version, GIN `@>`), `go-style-reviewer`, `system-design-reviewer` (reconciler-координация / eventual-consistency / idempotent diff / outbox-атомарность; **подтвердить, что γ НЕ вводит ребра iam→compute/vpc** — containment из mirror, ацикличность сохранена).

**S3 — api-gateway (`kacho-api-gateway`):**
- [ ] Регистрация **public** `ReplaceTargetSelector` (allowlist + gRPC-director + REST `:replaceTargetSelector` на external) — НЕ Internal. Исполнение — `api-gateway-registrar`.
- [ ] permission-catalog entry (D2) embedded; authz-middleware реальный Check (anti-anon + ACR floor; scope-полиморфный extractor).
- [ ] newman happy (γ-01, γ-02 eventual, γ-18 replace, γ-24 ре-верификация REJECTED→ACTIVE при смене parent, целевой JSON γ-21) + negative (γ-08, γ-09, γ-10, γ-11, γ-12 containment, γ-16 expiry, γ-24 ACTIVE→REJECTED scope-выпадение через parent) + α non-regression (γ-22) через api-gateway, RED-first.

**S4 — ui (`kacho-ui`):**
- [ ] `iamApi.replaceTargetSelector(...)` + типы `ResourceSelector{types,matchLabels}` / `verificationStatus`.
- [ ] grant-форма: режим «По меткам» (types-picker + matchLabels key/value editor, γ-06); membership-превью c verification-бейджами (γ-07); «Заменить селектор» → `:replaceTargetSelector`.
- [ ] back-compat: режимы «Весь scope»/«Конкретные объекты» (α) сохранены; UI-инварианты α/1.5 (resource-first, named control) сохранены.
- [ ] UI-тесты (vitest/playwright) по γ-06/γ-07; verification-бейдж члена ре-рендерится при смене статуса (γ-24: `REJECTED→ACTIVE` бейдж краснеет→зеленеет, `ACTIVE→REJECTED` наоборот — после reconcile-lag по `Get`-refresh).

**S5 — deploy (`kacho-deploy`):** helm/compose — reconciler-worker как часть iam-процесса (in-process воркер, без нового деплоя); expiry-scan переиспользует KAC-127 expiry-cron (Q3=(c) closed — расширить на eager-revoke tuples), конфиг reconcile-интервала при необходимости; e2e-build-матрицы newman зелёные.

**S6 — workspace (docs/vault):** обновить `rpc/iam-access-binding-service.md` (`ReplaceTargetSelector` + Create-selector дельта), `resources/iam-access-binding.md` (selector активирован + verification_status + containment из mirror + expiry eager-revoke), **обновить vault-trail mirror** (`resources/iam-resource-mirror.md` — read-for-authz в γ + `parent_account_id` backfill D4; файл уже создан в β — **обязательный DoD-пункт**, не «создать если нет»), KAC-trail; этот acceptance-док → APPROVED. **НЕ заводить `edges/iam-to-compute`/`iam-to-vpc`** — γ НЕ вводит cross-domain ребра (containment из same-DB mirror, D1/D10).

**Финальная верификация (перед merge каждой Go-стадии):** `go test ./... -race` + `golangci-lint run` + `govulncheck` + `make audit-list-filter` + newman зелёные.

---

## 7. Выход / запреты

- Единственный артефакт этого шага — настоящий markdown. **Никакого кода** (ни `.go`, ни `.sql`, ни `.proto`).
- Описано только наблюдаемое поведение API/UI; DB-форма (membership-таблица, GIN, CAS, reconciler-планировка) — забота `db-architect-reviewer`/`migration-writer`/`system-design-reviewer`/`rpc-implementer`.
- **sub-phase α НЕ модифицируется** (D-кросс): `all_in_scope`/`resources[]`-контракт, role-coverage гейт сохраняются; γ снимает `UNIMPLEMENTED` с `selector` и закрывает α-D14 containment forward-only.
- **γ НЕ вводит ребра `iam→compute/vpc`** (containment резолвится из IAM same-DB `resource_mirror.parent_*` — β наполнил) — ацикличность графа non-negotiable (`polyrepo.md`).
- Рабочий condition в γ — ТОЛЬКО `non_expired` (через eager-revoke, D3); прочие builtin — schema-only forward (ε-волна, вне γ); selector ограничен типом `compute.instance` (vpc — следующая итерация, D13).
- Без сравнений с чужими облаками — конвенции Kachō нормативны (`api-conventions.md`).
- Координация после APPROVED: §5 Q1-Q5 уже closed → KAC Subtask γ + `superpowers:writing-plans` → `integration-tester` (RED по γ-NN) → `rpc-implementer` → `proto-api-reviewer` (proto/rename) / `db-architect-reviewer` (membership-таблица/CAS/GIN) / `system-design-reviewer` (reconciler/eventual-consistency/ацикличность) / `api-gateway-registrar` (public ReplaceTargetSelector) → заказчик: финальный smoke (§J γ-21).
