# Epic «Resource-scoped AccessBinding» — Selectors all-services + type-dedup — Acceptance

> **Статус:** ✅ APPROVED
> **Дата:** 2026-06-20
> **Автор:** `acceptance-author`
> **Ревьюер:** `acceptance-reviewer` — APPROVED 2026-06-20. Открытые вопросы Q1–Q6 ЗАКРЫТЫ родителем/ревьюером (дефолты зафиксированы — см. отзыв ниже и §5); §5 трактовать как «зафиксированные дефолты», НЕ как live-open. Можно `superpowers:writing-plans`.
> **Эпик/тикет:** epic «Resource-scoped AccessBinding» (epic-100/103) — продолжение **γ**. Два трека: **T1 type-dedup** + **T3 selectors all-services**. KAC-номера (Subtask T1, Subtask T3 под `[EPIC]`) проставляются ДО старта `superpowers:writing-plans`. Затронутые репо: `kacho-proto` / `kacho-iam` / `kacho-vpc` / `kacho-nlb` / `kacho-compute` / `kacho-api-gateway` / `kacho-ui` / `kacho-deploy` / `kacho-workspace`(docs/vault).
> **Источник требований (verbatim intent заказчика):** «α дал per-object таргетинг по списку id; β наполнил IAM mirror метками/parent компьютовых ресурсов; γ активировал `bySelector{types,matchLabels}` E2E **только для `compute.instance`**. Теперь два долга: **(T1)** тип указан ДВАЖДЫ — в роли (через role-coverage) и в `selector.types`; объединить — `selector.types` опциональны, при опущении выводятся из role-coverage. **(T3)** selector работает только для compute.instance — распространить на ВСЕ mirror-fed типы: vpc (network/subnet/…), nlb (loadBalancers/targetGroups/listeners), compute disk/image/snapshot, и iam-собственные (project/account/user/group/role) через direct same-DB match. Только прод-код / best-2026 / польза.»

---

## Обзор

Эпик «Resource-scoped AccessBinding» прошёл α (per-object byName), β (IAM `resource_mirror` наполняется метками/parent компьютовых ресурсов), γ (активация `bySelector{types,matchLabels}` end-to-end **только для `compute.instance`**: reconciler матчит `resource_mirror.labels @> matchLabels` + containment по `mirror.parent_*` → per-object FGA-tuples; `selectableTypes` hardcoded `{compute.instance}`).

Этот документ описывает два независимых, но соседних трека:

- **T1 — type-dedup.** Сейчас целевой тип объявляется ДВАЖДЫ: неявно в роли (`role.permissions` → тип через `domain.RoleCoversType`) и явно в `selector.types`. T1 делает `selector.types` **опциональными**: опущены → выводятся из role-coverage (все КОНКРЕТНЫЕ, не-wildcard типы, что роль покрывает, ∩ `selectableTypes`); заданы → текущий γ-гейт (`selector.types ⊆ role-coverage`). Wildcard-роль + опущенные types → `INVALID_ARGUMENT` (нельзя вывести «все»).

- **T3 — selectors для всех доменов.** Распространяет γ-selector с `compute.instance` на ВСЕ mirror-fed типы: расширяет ребро `vpc→iam` / `nlb→iam` `RegisterResource` payload-ом `labels`+`parent`; добавляет vpc/nlb/compute(disk/image/snapshot) типы в `selectableTypes`; параметризует reconciler per-fed-type (перестаёт быть hardcoded `compute.instance`); для iam-собственных ресурсов (project/account/user/group/role) — **direct same-DB match** в reconciler (их labels уже в IAM-БД, mirror гонять через RegisterResource свой же сервис не нужно — нет смысла, был бы self-ребро).

Документ описывает **только внешнее наблюдаемое поведение API/UI** (gRPC-коды, REST-формы, статусы membership, eventual-consistency-семантику), не реализацию. Сценарии трассируются в имена integration-/newman-/UI-тестов через ID `T1-NN` / `T3-NN`. Стандартные конвенции (`api-conventions.md`, `security.md`, `data-integrity.md`) нормативны и в тело не дублируются — только ссылками (§1).

---

## 0.1 Карта эпика (контекст — детальные сценарии ТОЛЬКО для T1/T3)

| Под-фаза | Содержание | Статус |
|---|---|---|
| **α** (прод) | `target` oneof `all_in_scope`+`resources[]`+`selector`(был UNIMPLEMENTED); role-coverage гейт (D-13); per-object tuple + `hierarchyParentTuple` | вне scope |
| **β** (прод) | `resource_mirror`(object_type/object_id/parent_project_id/parent_account_id/labels jsonb/source_version/updated_at) наполняется `compute→iam RegisterResource` (monotonic). Mirror НЕ читался для authz | вне scope (предусловие T3) |
| **γ** (прод) | Активация `selector` end-to-end **только compute.instance**; containment из `mirror.parent` same-DB; expiry eager-revoke; reconciler-worker материализует membership в `access_binding_target_members`(verification_status); `ReplaceTargetSelector`; `selectableTypes` hardcoded `{compute.instance}` | вне scope (база T1/T3) |
| **T1** (ЭТОТ док) | `selector.types` опциональны → выводятся из role-coverage (concrete-types ∩ selectableTypes); wildcard-роль+опущ.types → INVALID_ARGUMENT; заданные types → γ-гейт `⊆ role-coverage` | **Сценарии T1-01..T1-09** |
| **T3** (ЭТОТ док) | selector для ВСЕХ mirror-fed типов: vpc/nlb label-emit в RegisterResource; compute disk/image/snapshot; iam-direct same-DB; reconciler feed-generalize (per-fed-type, не hardcoded compute.instance) | **Сценарии T3-01..T3-16** |

---

## 0. Фиксированные дизайн-решения (предлагаются автором; подлежат approve ревьюером — затем НЕ переоткрывать)

| ID | Решение | Обоснование |
|---|---|---|
| **D1 (T1 — derive)** | **`selector.types` опциональны.** Если **опущены** (`types=[]`) → выводятся async в reconciler/worker из `role.permissions`: **derived = {все КОНКРЕТНЫЕ (не-wildcard) типы, покрытые ролью} ∩ `selectableTypes`}**. Конкретный тип = `domain.PermissionObjectType` вернул `wildcard=false` (4-сегментный perm `module.resource.resourceName.verb` с не-`*` module и resource). Membership материализуется по derived-types точно как если бы они были заданы явно. Если **заданы** → текущий γ-гейт (`selector.types ⊆ role-coverage`, иначе FAILED_PRECONDITION; non-selectable/unknown → INVALID_ARGUMENT). `matchLabels` остаётся **обязательным** в обоих случаях (пустой → INVALID_ARGUMENT, как γ — `all_in_scope` для «всего scope»). | Устраняет дубль «тип в роли vs selector.types». `role.permissions` уже несёт типы (role-coverage гейт их читает); вывод детерминирован, same-DB, без новых данных. Пересечение с `selectableTypes` отбрасывает типы без feed (иначе «вечный PENDING», γ-D13). `matchLabels` не выводим (это намерение оператора) → остаётся обязательным. |
| **D2 (T1 — wildcard-роль)** | **Wildcard-роль (`*.*.*.*` либо `module.*`) + опущенные `selector.types` → sync `INVALID_ARGUMENT`** `"selector.types required for wildcard role <id> (cannot derive concrete types)"`. Wildcard покрывает «все типы» — вывести конкретный закрытый набор нельзя (это был бы «selector на всё», что = `all_in_scope`, не selector). Оператор обязан задать types явно. **Если у роли concrete-types ЕСТЬ И wildcard-perm ЕСТЬ** — derive берёт только concrete-набор (wildcard игнорируется при выводе; явный набор всегда побеждает неявную «всё»). | Нельзя материализовать membership «по всем существующим типам» — это и есть `all_in_scope` (другая ветка oneof). Wildcard без явных types — ambiguity; fail-closed sync. Mixed (concrete+wildcard) — concrete достаточно конкретен для вывода, wildcard-часть отбрасывается (consistent с «selector обязан ограничить тип», γ-D6). |
| **D3 (T1 — derive где)** | **Derive выполняется в reconciler/worker (async), НЕ на sync request-path** — кроме wildcard-only-guard (D2), который sync (нужно отклонить до Operation, т.к. роль читается на role-coverage гейте, который уже async; но «derive невозможен» детектируется проверкой «у роли есть хоть один concrete selectable type» — если ноль И types опущены → отказ). Derived-набор сохраняется как материализованный membership (через `access_binding_target_members`, γ-Q2); `Get(binding)` отдаёт **эффективный** `selector.types` (derived или explicit) для наблюдаемости. **byName[].type — НЕ трогаем** (атрибут конкретного объекта, не выводится). | Role-coverage гейт уже async (читает role.permissions в worker). Derive — то же чтение, тот же слой. wildcard-only-guard sync — fail-fast на очевидной ambiguity. Эффективный types в read даёт оператору видеть «что реально под грантом» (не пустой массив). byName — explicit per-object, derive не применим. |
| **D4 (T3 — vpc/nlb label-emit)** | **vpc и nlb эмитят `labels`+`parent` в `RegisterResource`** (зеркало compute-β): расширить vpc/nlb `fgaregister` payload + `iam_register_applier` на `labels`/`parent_project_id`. Emit на **Create** И **Update-when-labels-in-mask** (как compute-β-04; non-labels Update → no-op). Типы vpc (`vpc.network`/`vpc.subnet`/`vpc.securityGroup`/`vpc.routeTable`/`vpc.address`/`vpc.gateway`/`vpc.networkInterface`) и nlb (`loadbalancer.networkLoadBalancers`/`loadbalancer.targetGroups`/`loadbalancer.listeners`) добавляются в `selectableTypes`. **НЕ новое ребро** — `vpc→iam` / `nlb→iam` `RegisterResource` уже существуют (SEC-A owner-tuple); расширяется payload существующего ребра. | β уже доказал паттерн на compute. vpc/nlb имеют register-applier infra (только labels не эмитят). Расширение payload существующего Internal-ребра не вводит цикл (`iam` не зовёт vpc/nlb обратно). Update-on-labels-mask держит mirror актуальным под label-change reconcile (T3-06). Точный финальный список типов утверждает `proto-api-reviewer`/`db-architect-reviewer` по closed-table `authzmap.ObjectType`. |
| **D5 (T3 — compute disk/image/snapshot)** | **compute disk/image/snapshot уже несут labels в mirror** (β payload их включал) — T3 добавляет их типы (`compute.disk`/`compute.image`/`compute.snapshot`) в `selectableTypes` + reconciler feed; containment по `mirror.parent_*` тот же. Никаких изменений compute-emit (labels уже эмитятся β). | β уже эмитил labels для disk/image/snapshot — γ просто не активировал их в `selectableTypes`. T3 — чисто IAM-side добавление в whitelist + reconciler-параметризация. Минимальная работа, нулевой риск на compute-стороне. |
| **D6 (T3 — iam-direct same-DB)** | **iam-собственные ресурсы (`iam.project`/`iam.account`/`iam.user`/`iam.group`/`iam.role`) матчатся reconciler-ом из СВОИХ IAM-таблиц напрямую (direct same-DB), НЕ через `resource_mirror`.** labels на `projects`/`accounts` (и др., где есть) читаются из родных таблиц; containment — через iam-hierarchy (project ⊑ account ⊑ cluster по `projects.account_id`), не через `mirror.parent_*`. iam-типы в `selectableTypes` помечены как «direct-fed» (источник = own table, не mirror). **НЕ self-register в mirror** (был бы бессмысленный self-RegisterResource ребро `iam→iam`). | iam — владелец этих ресурсов (`data-integrity.md` карта владельцев); их labels/hierarchy уже в IAM-БД same-DB. Гонять свой же ресурс через Internal RegisterResource в собственное зеркало — лишний кругооборот без пользы (заказчик: «нет смысла»). Direct same-DB SELECT с GIN `@>` на own table — детерминирован, без eventual-consistency-lag (нет PENDING_VERIFICATION для iam-типов — объект всегда «в источнике» сразу). **Открытый вопрос Q4:** какие именно iam-типы несут labels (project/account точно; user/group/role — подтвердить наличие labels-колонки). |
| **D7 (T3 — reconciler feed-generalize)** | **`selectableTypes` и reconciler перестают быть hardcoded `compute.instance` — параметризуются per-fed-type.** Каждый selectable-тип имеет дескриптор: `feed-source` (`mirror` для consumer-типов vpc/nlb/compute | `iam-direct` для iam-типов) + `containment-rule` (`mirror.parent_*` для mirror-fed | `iam-hierarchy` для iam-direct). Reconciler matched-set вычисляется и diff'ится по дескриптору типа; per-object FGA-tuple emit/revoke универсален (`fga_type(type):<id>#tier@subject`). Membership-материализация (`access_binding_target_members`) и verification_status — без изменений формы (γ-Q2). | γ-reconciler был жёстко завязан на `compute.instance`+mirror. T3 обобщает: containment-предикат и feed-source — атрибуты типа, а не константа. Унификация (один reconciler, табличка дескрипторов) вместо per-type-ветвлений — best-2026, расширяемо под будущие типы одной строкой дескриптора. |
| **D8 (non-breaking + idempotent)** | **Оба трека non-breaking.** T1: `selector.types` уже `repeated` (опущение = пустой массив) — раньше пустой отклонялся (γ-D6 «types обязателен»), теперь пустой → derive. Существующие binding'и с явными types работают без изменений. T3: добавление типов в `selectableTypes` аддитивно (раньше → INVALID_ARGUMENT «not selectable», теперь → работает); существующие compute.instance-selector'ы не затронуты. Reconciler идемпотентен (β monotonic `source_version` для mirror-fed; iam-direct читает текущее состояние own-table; diff desired-vs-actual). | Заказчик: «non-breaking». T1 ослабляет валидацию (раньше-reject → теперь-derive) — чистое расширение. T3 расширяет whitelist — аддитивно. Идемпотентность reconciler сохраняется (γ-D7/D12 паттерн распространяется на новые feed-source без изменения diff-семантики). |

---

## 1. Связь с регламентом (нормативно; в тело не дублируется)

| Регламент | Где соблюдается |
|---|---|
| `api-conventions.md` — read sync, мутации async `Operation`; Watch не существует (poll Operation/List) | `Create`/`ReplaceTargetSelector` async (γ-наследие); membership наблюдается через `Get`/`ListByResource` sync |
| `api-conventions.md` — flat message + oneof; `selector.types` остаётся `repeated` (опущение = derive, D1) | D1, D2, §2.1 |
| `api-conventions.md` — JSON camelCase (`matchLabels`, `selector`, `types`, `verificationStatus`) | §A/§C read-формы |
| `api-conventions.md` — error-format; malformed → sync `INVALID_ARGUMENT`; состояние → `FAILED_PRECONDITION` (async → `Operation.error`, ban #9) | T1-02, T1-04, T3-08, T3-15 |
| `data-integrity.md` §within-service — reconciler diff идемпотентен; iam-direct SELECT `@>` на own GIN; concurrent → integration-тест ≥2 goroutine | D7, D8, T3-13 |
| `data-integrity.md` §cross-domain — vpc/nlb mirror-fed (output-only зеркало, source = owner); iam-direct — own-table (источник истины); containment same-DB (`mirror.parent` для consumer, iam-hierarchy для iam-owned) | D4, D6, D7, T3-04, T3-05 |
| `data-integrity.md` §cross-domain — **НЕ новые рёбра**: `vpc→iam`/`nlb→iam` RegisterResource — существующие (расширяем payload); iam-ресурсы — same-DB (НЕТ self-ребра `iam→iam`); ацикличность сохранена | D4, D6, §6 S2/S3 |
| `security.md` §AuthN+AuthZ ВЕЗДЕ — каждый RPC per-RPC Check; `requireGrantAuthority` на Create/Replace; анонимный fail-closed | T1-08, T3-14 (наследуют γ-10/γ-11) |
| `security.md` §инфра-чувствительные — mirror/own-table `labels` отдаются как tenant-facing метки; placement/underlay в selector-membership НЕ светятся; vpc/nlb эмитят в mirror ТОЛЬКО labels+parent (НЕ underlay/placement) | D4, D6, T3-12 |
| `security.md` §Internal-vs-external — `RegisterResource` (vpc/nlb расширенный payload) остаётся Internal :9091 (НЕ external); selector-формы public (наследие γ) | D4, §6 S3 |
| `00-kacho-core.md` ban #9 (мутации→Operation), #10 (within-DB), #4/#8 (нет shared БД — mirror НЕ источник истины), #12 (TDD), #1 (APPROVED перед кодом) | §6 DoD RED→GREEN |
| `polyrepo.md` §порядок merge | §6 DoD: proto(T1) → iam(T1 derive + T3 reconciler/iam-direct) → vpc/nlb/compute(T3 emit) → api-gateway → ui → deploy → workspace(docs) |
| sub-phase γ (прод) — selector-контракт (matchLabels обязателен, containment, expiry, ReplaceTargetSelector, verification_status) сохраняется; T1 ослабляет только types-обязательность; T3 расширяет только `selectableTypes`+feed | D1, D8, T1-07, T3-16 (γ non-regression) |

---

## 2. Модель T1/T3 (нормативно — D1/D2/D6/D7)

### 2.1 Форма (proto-ориентир — финал за `proto-api-reviewer`)

```
// T1: ResourceSelector.types становится ОПЦИОНАЛЬНЫМ (поле уже repeated — опущение = пустой).
//     Семантика пустого types меняется: γ → INVALID_ARGUMENT; T1 → derive из role-coverage (D1).
message ResourceSelector {
  repeated string         types        = 1;   // ОПЦИОНАЛЬНО (T1); пусто → derive (D1); задан → γ-гейт ⊆ role-coverage
  map<string,string>      match_labels = 2;   // ОБЯЗАТЕЛЕН (без изменений, γ); пусто → INVALID_ARGUMENT
}

// T3: selectableTypes расширяется (НЕ proto-изменение — server-side whitelist):
//   compute.instance (γ) + compute.disk/image/snapshot (D5)
//   + vpc.network/subnet/securityGroup/routeTable/address/gateway/networkInterface (D4)
//   + loadbalancer.networkLoadBalancers/targetGroups/listeners (D4)
//   + iam.project/account/user/group/role (D6, direct-fed)
// Финальный список типов — closed-table authzmap.ObjectType ∩ active-feed; утверждает proto-api-reviewer.

// Get(binding) отдаёт ЭФФЕКТИВНЫЙ selector.types (derived ИЛИ explicit) — D3, наблюдаемость.
```

### 2.2 Derive-предикат T1 (D1/D2)

Для роли с `permissions` и selector с `types`:

| Вход `selector.types` | Роль | Поведение |
|---|---|---|
| пусто (опущен) | роль имеет ≥1 concrete (не-wildcard) selectable тип | derived = {concrete-types(role)} ∩ `selectableTypes`; membership по derived (T1-01) |
| пусто (опущен) | роль — wildcard-only (`*.*.*.*`/`module.*`), нет concrete selectable | sync `INVALID_ARGUMENT` «selector.types required for wildcard role …» (D2, T1-02) |
| пусто (опущен) | роль mixed (concrete + wildcard) | derived = concrete-набор ∩ selectableTypes (wildcard-часть игнорируется, D2, T1-03) |
| задан, ⊆ role-coverage | любая | γ-гейт проходит; membership по explicit types (T1-04 happy) |
| задан, ⊄ role-coverage | любая | `Operation.error` FAILED_PRECONDITION (γ role-coverage гейт, T1-05) |
| задан, unknown/non-selectable тип | любая | sync `INVALID_ARGUMENT` (γ-D6/D13, T1-06) |

«concrete type» = `domain.PermissionObjectType(p)` → `wildcard=false` (perm `module.resource.resourceName.verb`, module≠`*`, resource≠`*`).

### 2.3 Feed-source × containment T3 (D6/D7)

| Тип-семейство | feed-source | containment-rule |
|---|---|---|
| `compute.*` (instance/disk/image/snapshot) | `resource_mirror` (`compute→iam RegisterResource`) | `mirror.parent_project_id`/`parent_account_id` ⊑ scope |
| `vpc.*` (network/subnet/…) | `resource_mirror` (`vpc→iam RegisterResource`, расширенный payload, D4) | `mirror.parent_*` ⊑ scope |
| `loadbalancer.*` (nlb) | `resource_mirror` (`nlb→iam RegisterResource`, расширенный payload, D4) | `mirror.parent_*` ⊑ scope |
| `iam.*` (project/account/user/group/role) | **iam-direct** own-table (D6) | iam-hierarchy (`project ⊑ account ⊑ cluster` через `projects.account_id`) |

---

## §A — Backend T1: derive selector.types из role-coverage

> Membership наблюдается через sync read (`Get`/`ListByResource`), как γ. `Get` отдаёт эффективный (derived/explicit) `selector.types` (D3).

### Сценарий T1-01: Happy — selector БЕЗ types + concrete-роль → types выведены, membership корректен

**ID:** `T1-01`

**Given** account `acc-A` c проектом `prj_prod`, owner `usr-OWNER`
**And** reusable роль `rol-insteditor` c permissions, покрывающими ТОЛЬКО `compute.instance` concrete (напр. `compute.instance.<r>.update`/`.get`; без wildcard, без других типов)
**And** в `resource_mirror` под `prj_prod` есть `inst-1`{env:prod} и `inst-2`{env:dev}
**And** caller — `usr-OWNER`

**When** caller вызывает `POST /iam/v1/accessBindings` c payload:
  - `subjectType`=`"user"`, `subjectId`=`"usr-MEMBER"`, `roleId`=`"rol-insteditor"`
  - `resourceType`=`"project"`, `resourceId`=`"prj_prod"`, `scope`=`PROJECT`
  - `target` = `{ "selector": { "matchLabels": { "env":"prod" } } }`  _(types ОПУЩЕН)_

**Then** RPC возвращает `Operation`; poll до `done=true`; `done && !error`
**And** reconciler выводит `types = {compute.instance}` (единственный concrete selectable тип роли, D1) и материализует membership: `inst-1`(matches `env:prod`, под scope) → `verificationStatus=ACTIVE`+per-object tuple; `inst-2` НЕ matches → не в membership
**And** `Get(acb-…)` отдаёт эффективный `target.selector.types = ["compute.instance"]` (derived, D3) и `matchLabels={env:prod}`
**And** `InternalIAMService.Check`(`usr-MEMBER`, `inst-1`) → allowed; на `inst-2` → НЕ allowed (поведение идентично γ-01 с явными types)

### Сценарий T1-02: Negative — selector БЕЗ types + wildcard-only-роль → INVALID_ARGUMENT

**ID:** `T1-02`

**Given** scope `project:prj_prod`; роль `rol-superuser` c permissions `["*.*.*.*"]` (либо `["compute.*.*.*"]` — wildcard-only, нет concrete selectable типа)
**And** caller — owner

**When** caller вызывает `Create` c `target={selector:{matchLabels:{env:prod}}}` (types опущен)

**Then** sync `INVALID_ARGUMENT` `"selector.types required for wildcard role rol-superuser (cannot derive concrete types)"` (D2), до Operation
**And** binding не создан; tuple не эмитится

### Сценарий T1-03: Mixed-роль (concrete + wildcard) + опущенные types → derive только concrete-набор

**ID:** `T1-03`

**Given** scope `project:prj_prod`; роль `rol-mixed` c permissions `["compute.instance.<r>.update", "vpc.*.*.*"]` (concrete compute.instance + wildcard vpc.*)
**And** `compute.instance` И vpc-типы — selectable (после T3)

**When** caller вызывает `Create` c `target={selector:{matchLabels:{env:prod}}}` (types опущен)

**Then** Operation `done && !error`; reconciler выводит `types = {compute.instance}` ТОЛЬКО (concrete-набор ∩ selectableTypes; wildcard `vpc.*` игнорируется при derive — явный набор побеждает «всё», D2)
**And** membership материализуется только по `compute.instance`; vpc-объекты под scope НЕ попадают в этот грант (нужен явный types для vpc)
**And** `Get` отдаёт `selector.types=["compute.instance"]`

### Сценарий T1-04: Happy — selector С types ⊆ role-coverage → как в γ (regression-paritет)

**ID:** `T1-04`

**Given** scope `project:prj_prod`; роль `rol-insteditor` (покрывает `compute.instance`); `inst-1`{env:prod} под scope

**When** caller вызывает `Create` c `target={selector:{types:["compute.instance"], matchLabels:{env:prod}}}` (types ЗАДАН)

**Then** Operation `done && !error`; γ role-coverage гейт проходит (`compute.instance ⊆ role-coverage`); membership как γ-01
**And** поведение идентично γ (T1 не меняет explicit-types-путь — D1)

### Сценарий T1-05: Negative — selector С types ⊄ role-coverage → FAILED_PRECONDITION (γ-гейт D-13)

**ID:** `T1-05`

**Given** scope `project:prj_prod`; роль `rol-vpconly` (verb'ы только на vpc, НЕ покрывает `compute.instance`)

**When** caller вызывает `Create` c `target={selector:{types:["compute.instance"], matchLabels:{env:prod}}}` → poll Operation

**Then** Operation `done && error.code=FAILED_PRECONDITION` `"role rol-vpconly does not grant any verb on compute.instance"` (role-coverage гейт γ D-13, не изменён T1)
**And** binding не создан; tuple не эмитится

### Сценарий T1-06: Negative — explicit types unknown/non-selectable → INVALID_ARGUMENT (γ-D6/D13 паритет)

**ID:** `T1-06`

**Given** scope `project:prj_prod`; роль reusable

**When** `Create` c `target={selector:{types:["foo.bar"], matchLabels:{env:prod}}}` → **Then** sync `INVALID_ARGUMENT` «unknown resource type» (γ-D6)
**When** `Create` c `target={selector:{types:["<тип-без-feed]}` _(гипотетический не-fed после T3)_ → **Then** sync `INVALID_ARGUMENT` «not selectable yet (no resource feed)» (γ-D13)

### Сценарий T1-07: Conformance — empty matchLabels всё ещё INVALID_ARGUMENT (T1 НЕ ослабляет matchLabels)

**ID:** `T1-07`

**Given** scope `project:prj_prod`; concrete-роль

**When** `Create` c `target={selector:{matchLabels:{}}}` (types опущен И matchLabels пуст)

**Then** sync `INVALID_ARGUMENT` `"target.selector.matchLabels must not be empty (use all_in_scope for entire scope)"` (γ-D6; T1 опускает только types, matchLabels остаётся обязательным — D1)
**And** проверяется ДО derive (matchLabels-валидация не зависит от роли)

### Сценарий T1-08: ReplaceTargetSelector БЕЗ types → derive по тому же предикату

**ID:** `T1-08`

**Given** selector-binding `acb-R` c явными `types:["compute.instance"]`, `matchLabels:{env:prod}`; роль `rol-insteditor` (concrete compute.instance)

**When** caller вызывает `POST …/acb-R:replaceTargetSelector` c `selector={matchLabels:{env:prod, team:payments}}` (types опущен)

**Then** Operation `done && !error`; reconciler выводит types из role-coverage (как D1) → `{compute.instance}`; selector заменён целиком; membership пересчитан по derived-types + новым matchLabels
**And** `Get(acb-R).target.selector.types = ["compute.instance"]` (эффективный), `matchLabels={env:prod,team:payments}`
**And** wildcard-роль + опущенные types на Replace → sync `INVALID_ARGUMENT` (D2 паритет с Create)

### Сценарий T1-09: Derive стабилен — повторный reconcile того же binding'а не меняет derived-types

**ID:** `T1-09`

**Given** binding из T1-01 (derived `types={compute.instance}`); роль `rol-insteditor` неизменна

**When** reconciler срабатывает повторно (триггер mirror-change / sweep, без изменения роли)

**Then** derived-types детерминирован (читает те же `role.permissions`) → `{compute.instance}`; membership-diff пуст (идемпотентно, D8); tuple'ы не дублируются
**And** _Примечание (для writing-plans):_ если роль ИЗМЕНИЛАСЬ (permissions меняются — отдельный Role.Update flow вне этого эпика), пересчёт derived-types при следующем reconcile-триггере — by-design; этот док НЕ вводит триггер reconciler на Role.Update (открытый вопрос Q3)

---

## §C — Backend T3: selectors для vpc / nlb / compute(disk/image/snapshot) / iam

> vpc/nlb эмитят labels+parent в существующий Internal `RegisterResource` (D4). compute disk/image/snapshot — labels уже в mirror (D5). iam-типы — direct same-DB (D6). reconciler параметризован per-fed-type (D7).

### Сценарий T3-01: Happy — selector для vpc.subnet (label match → tuple → Check)

**ID:** `T3-01`

**Given** account `acc-A`, проект `prj_prod`, owner; роль `rol-subneteditor` (покрывает `vpc.subnet`)
**And** vpc создал `sub-1`{env:prod} под `prj_prod` И послал `RegisterResource` c labels+parent (D4) → `resource_mirror` содержит `sub-1` (`object_type=vpc.subnet`, `parent_project_id=prj_prod`, `labels={env:prod}`)
**And** `sub-2`{env:dev} под `prj_prod` в mirror

**When** caller вызывает `Create` c `target={selector:{types:["vpc.subnet"], matchLabels:{env:prod}}}` на `prj_prod` → poll Operation

**Then** Operation `done && !error`; reconciler (feed-source=mirror, containment=mirror.parent, D7) материализует: `sub-1`→`ACTIVE`+per-object tuple `vpc_subnet:sub-1#<tier>@user:usr-MEMBER`; `sub-2` НЕ matches
**And** `Check`(`usr-MEMBER`, `sub-1`) → allowed; на `sub-2` → НЕ allowed

### Сценарий T3-02: Happy — selector для loadbalancer.targetGroups (nlb)

**ID:** `T3-02`

**Given** проект `prj_prod`, owner; роль покрывает `loadbalancer.targetGroups`
**And** nlb создал `tg-1`{tier:critical} под `prj_prod` + `RegisterResource` c labels+parent (D4) → mirror содержит `tg-1`
**And** `tg-2`{tier:standard} в mirror

**When** `Create` c `target={selector:{types:["loadbalancer.targetGroups"], matchLabels:{tier:critical}}}` → poll Operation

**Then** Operation `done && !error`; reconciler материализует `tg-1`→ACTIVE+tuple; `tg-2` НЕ matches
**And** `Check`(`usr-MEMBER`, `tg-1`) → allowed; на `tg-2` → НЕ allowed

### Сценарий T3-03: Happy — selector для compute.disk (labels уже в mirror, D5)

**ID:** `T3-03`

**Given** проект `prj_prod`, owner; роль покрывает `compute.disk`
**And** в mirror `disk-1`{env:prod} под `prj_prod` (compute β уже эмитил labels для disk — D5); `disk-2`{env:dev}

**When** `Create` c `target={selector:{types:["compute.disk"], matchLabels:{env:prod}}}` → poll Operation

**Then** Operation `done && !error`; `disk-1`→ACTIVE+tuple; `disk-2` НЕ matches (без изменений compute-emit — D5)
**And** `Check`(`usr-MEMBER`, `disk-1`) → allowed; на `disk-2` → НЕ allowed

### Сценарий T3-04: Happy — selector для iam.project (direct same-DB, D6)

**ID:** `T3-04`

**Given** account `acc-A` (owner `usr-OWNER`) c проектами `prj_a`{tier:gold} и `prj_b`{tier:silver} (labels на `projects` в IAM-БД)
**And** роль `rol-projviewer` (покрывает `iam.project`); scope-anchor `account:acc-A`

**When** caller вызывает `Create` c `subjectId=usr-MEMBER`, `roleId=rol-projviewer`, `resourceType=account`, `resourceId=acc-A`, `target={selector:{types:["iam.project"], matchLabels:{tier:gold}}}` → poll Operation

**Then** Operation `done && !error`; reconciler (feed-source=**iam-direct**, containment=iam-hierarchy, D6) матчит `projects` own-table: `prj_a`(`tier:gold`, под `acc-A`)→ACTIVE+per-object tuple `project:prj_a#<tier>@user:usr-MEMBER`; `prj_b`(`tier:silver`) НЕ matches
**And** `Check`(`usr-MEMBER`, `prj_a`) → allowed; на `prj_b` → НЕ allowed
**And** iam-direct типы НЕ имеют `PENDING_VERIFICATION` (объект всегда в источнике same-DB — D6); нет eventual-lag

### Сценарий T3-05: Containment per-service — iam-hierarchy (project под чужим account) → REJECTED

**ID:** `T3-05`

**Given** selector-binding на scope `account:acc-A`, `types:["iam.project"]`, `matchLabels:{tier:gold}`
**And** `prj_foreign`{tier:gold} под `acc-OTHER` (другой account, `projects.account_id=acc-OTHER`)

**When** reconciler материализует membership

**Then** `prj_foreign` matches по labels/type, но **НЕ под scope** (iam-hierarchy: `acc-OTHER ⋢ acc-A`) → `verificationStatus=REJECTED`; tuple НЕ эмитится; audit «not contained» (γ-D8 паритет, containment-rule=iam-hierarchy для iam-direct, D6)
**And** `Check`(`usr-MEMBER`, `prj_foreign`) → НЕ allowed
**And** _Параллельный mirror-fed случай:_ vpc.subnet чужого проекта (`mirror.parent_project_id=prj_other`) → REJECTED по containment-rule=mirror.parent (D7) — единый verification-результат, разные containment-предикаты per feed-source

### Сценарий T3-06: label-change reconcile per-service — vpc.subnet env=prod→dev → eager-revoke

**ID:** `T3-06`

**Given** selector-binding `types:["vpc.subnet"]`, `matchLabels:{env:prod}`; `sub-1`{env:prod} ACTIVE, tuple эмитится, Check allowed

**When** vpc обновляет метку `sub-1` → `{env:dev}` и шлёт `RegisterResource` (labels-in-mask → mirror upsert monotonic, D4)

**Then** reconciler (триггер mirror-change) пересчитывает: `sub-1` выпал из matched-set → eager-revoke tuple; убран из membership (γ-03 паттерн, обобщён на vpc через feed-source=mirror)
**And** после reconcile `Check`(`sub-1`) → НЕ allowed; binding-level `status` остаётся ACTIVE (другие члены живы)

### Сценарий T3-07: label-change reconcile — iam.project tier gold→silver (direct same-DB) → eager-revoke

**ID:** `T3-07`

**Given** selector-binding `types:["iam.project"]`, `matchLabels:{tier:gold}` на `account:acc-A`; `prj_a`{tier:gold} ACTIVE, tuple эмитится

**When** оператор меняет метку `prj_a` → `{tier:silver}` (через `Project.Update` labels-mask — own IAM resource)

**Then** reconciler (триггер: own-resource label-change на iam-direct тип — D6/D7) пересчитывает: `prj_a` больше НЕ matches → eager-revoke tuple
**And** `Check`(`prj_a`) → НЕ allowed
**And** _Открытый вопрос Q2:_ механизм триггера reconcile на iam-direct own-resource label-change (Project.Update labels) — outbox-событие в той же writer-tx (как γ-Q1 для mirror) ИЛИ reconcile-sweep; финал за `system-design-reviewer`

### Сценарий T3-08: Negative — non-fed тип всё ещё INVALID_ARGUMENT (полнота whitelist)

**ID:** `T3-08`

**Given** scope `project:prj_prod`; роль reusable

**When** `Create` c `target={selector:{types:["<тип-вне-selectableTypes-после-T3>"], matchLabels:{env:prod}}}` (тип в closed-table authzmap, но без active feed)

**Then** sync `INVALID_ARGUMENT` `"<type> is not selectable yet (no resource feed)"` (γ-D13 паттерн сохранён — T3 расширяет whitelist, но НЕ открывает его целиком; типы без feed по-прежнему reject)
**And** _Примечание:_ конкретный «non-fed после T3» тип определяется финальным списком D4/D6 (Q1/Q4); сценарий проверяет, что граница whitelist энфорсится (не «любой тип теперь selectable»)

### Сценарий T3-09: PENDING_VERIFICATION для mirror-fed (vpc объект ещё не в mirror) → ACTIVE

**ID:** `T3-09`

**Given** selector-binding `types:["vpc.subnet"]`, `matchLabels:{env:prod}` на `prj_prod`; `sub-late` создаётся в vpc, но `RegisterResource` ещё не дошёл (mirror не знает)

**When** reconciler материализует на момент гранта

**Then** `sub-late` НЕ в mirror → не член membership (нечего матчить — γ-05 паттерн для mirror-fed)
**And** _(позже)_ `RegisterResource` приносит `sub-late`{env:prod, parent_project_id=prj_prod} → reconciler триггер (mirror-change) → matches AND под scope → `ACTIVE`+tuple → Check allowed
**And** _Контраст:_ iam-direct типы (T3-04) НЕ проходят через PENDING (объект сразу в own-table source, D6)

### Сценарий T3-10: Containment байName per-service — vpc.subnet чужого проекта → FAILED_PRECONDITION

**ID:** `T3-10`

**Given** scope `project:prj_prod`; роль покрывает `vpc.subnet`; в mirror `sub-other`{parent_project_id=prj_other}

**When** `Create` c `target={resources:[{vpc.subnet, sub-other}]}` (byName) → poll Operation

**Then** Operation `done && error.code=FAILED_PRECONDITION` `"vpc.subnet:sub-other is not contained in scope project:prj_prod"` (γ-D10 byName containment, обобщён на vpc через mirror.parent — D7)
**And** binding не создан; tuple не эмитится
**And** _Примечание:_ byName containment-гейт распространяется на ВСЕ mirror-fed/iam-direct типы (паритет с byLabel — единый containment-предикат per feed-source)

### Сценарий T3-11: ReplaceTargetSelector — смена типа vpc.subnet → vpc.network (оба selectable)

**ID:** `T3-11`

**Given** selector-binding `acb-V` c `types:["vpc.subnet"], matchLabels:{env:prod}`; роль покрывает И `vpc.subnet` И `vpc.network`; член `sub-1` ACTIVE

**When** caller вызывает `…:replaceTargetSelector` c `selector={types:["vpc.network"], matchLabels:{env:prod}}` → poll Operation

**Then** Operation `done && !error`; selector заменён целиком; reconciler диффит: `sub-1`(vpc.subnet) выпал → eager-revoke tuple; matched vpc.network-объекты под scope → ACTIVE+tuples
**And** `Check`(`sub-1`) → НЕ allowed; matched network → allowed (γ-18 replace-паттерн, обобщён на смену types в пределах selectable)

### Сценарий T3-12: Conformance — vpc/nlb эмитят в mirror ТОЛЬКО labels+parent, без инфра-полей

**ID:** `T3-12`

**Given** vpc/nlb с расширенным `RegisterResource` payload (D4)

**When** проверяется содержимое `resource_mirror` после `RegisterResource` от vpc/nlb

**Then** mirror-row несёт ТОЛЬКО `object_type`/`object_id`/`parent_project_id`/`parent_account_id`/`labels`/`source_version` (tenant-facing) — НЕ placement/underlay/wiring (`security.md` инфра-чувствительные; vpc/nlb не светят физику в зеркало)
**And** selector-membership-read (`Get`) тоже без инфра-полей (γ-15 паритет)

### Сценарий T3-13: Concurrency — конкурентный label-flip vpc + reconcile → детерминирован, без дублей

**ID:** `T3-13`

**Given** selector-binding `types:["vpc.subnet"]`, `matchLabels:{env:prod}`; `sub-X` под scope

**When** конкурентно: (a) несколько `RegisterResource` для `sub-X` флипают `env` prod↔dev (monotonic source_version); (b) reconciler пересчитывает

**Then** финальное membership-состояние `sub-X` соответствует последнему по `source_version` mirror-row (monotonic, старый игнорируется — γ-20 паттерн обобщён); ровно один tuple если финально matches, ноль если нет; без дублей/leak'а
**And** reconcile идемпотентен (diff desired-vs-actual)
**And** concurrent integration-тест (≥2 goroutine, mirror-flip + reconcile) ОБЯЗАТЕЛЕН (RED-first, `data-integrity.md` §within-service п.5)

### Сценарий T3-14: AuthZ/anon — Create selector (любой тип) → requireGrantAuthority / fail-closed

**ID:** `T3-14`

**Given** `prj_prod` (owner); сторонний `usr-X` без grant-authority; и анонимный запрос

**When** `usr-X` вызывает `Create` c vpc/nlb/iam-selector → **Then** `PERMISSION_DENIED`/`403` (γ-10 паритет, не зависит от типа)
**When** анонимный вызывает `Create` c selector → **Then** fail-closed `UNAUTHENTICATED`/`PERMISSION_DENIED` (γ-11 паритет)

### Сценарий T3-15: Negative — vpc/nlb эмитят невалидные labels → отклоняются (защита mirror)

**ID:** `T3-15`

**Given** vpc/nlb `RegisterResource` с невалидным `labels` (не jsonb-object / нарушает `corevalidate.Labels`)

**When** IAM обрабатывает `RegisterResource`

**Then** невалидные labels отклоняются (`INVALID_ARGUMENT` на Internal-ребре, β-15 паттерн) ИЛИ DB CHECK jsonb-object (defense-in-depth) — mirror не загрязняется (паритет с compute-β label-validation)
**And** _Примечание:_ это контракт расширенного payload (D4) — vpc/nlb обязаны слать sane labels, как compute

### Сценарий T3-16: Conformance — γ compute.instance-selector НЕ регрессирует; α-ветки целы

**ID:** `T3-16`

**Given** существующий γ-binding `acb-INST` (`selector{types:[compute.instance], matchLabels:{env:prod}}`, в проде до T1/T3); α-binding'и (`all_in_scope`, `resources[]`)

**When** читаются/проверяются после деплоя T1+T3

**Then** `acb-INST` membership/tuples без изменений (T3 аддитивен к selectableTypes — D8; compute.instance остаётся selectable); α-ветки целы (γ-22 паритет)
**And** role-coverage гейт (T1-05) и containment (γ) продолжают энфорситься для всех типов
**And** existing-binding с явными `selector.types` работает идентично (T1 опускает только пустой-types-путь — D1/D8)

---

## §B — UI: types-picker опционален + типы всех доменов

> UI grant-форма (γ: «Весь scope»/«Конкретные объекты»/«По меткам») расширяется: types-picker становится опциональным (T1) и предлагает типы всех selectable-доменов (T3).

### Сценарий T3-17 (UI): Форма — types-picker опционален + hint про derive

**ID:** `T3-17`

**Given** оператор на grant-форме, режим «По меткам», subject+scope+reusable-роль выбраны

**When** форма рендерит секцию selector

**Then** types-picker **опционален** (можно не выбирать); при пустом — hint «типы будут выведены из роли» (T1/D1); `matchLabels`-editor обязателен (≥1 пара)
**And** types-picker предлагает типы всех selectable-доменов (compute instance/disk/image/snapshot, vpc network/subnet/…, nlb loadBalancers/targetGroups/listeners, iam project/account/… — T3)
**And** submit с пустым types отправляет `Create` c `selector{matchLabels}` без types (T1-01); wildcard-роль + пустой types → серверный INVALID_ARGUMENT (T1-02) показывается как ошибка формы

### Сценарий T3-18 (UI): membership-превью с verification-бейджами для всех типов

**ID:** `T3-18`

**Given** оператор создал selector с vpc/nlb/iam-типом

**When** детальный экран читает `Get(acb-…)`

**Then** UI рендерит эффективный `selector.types` (derived или explicit, D3) + membership-список объектов c `verificationStatus`-бейджем (ACTIVE/PENDING_VERIFICATION/REJECTED) — единообразно для всех типов
**And** iam-direct типы (project/account) не показывают PENDING (D6) — бейджи только ACTIVE/REJECTED

---

## §J — Smoke / e2e (заказчик: финальная верификация, шаг 7)

### Сценарий T1T3-E2E: end-to-end derive + all-services selector (REST + gRPC + UI)

**ID:** `T1T3-E2E`

**Given** развёрнутый стенд (`make dev-up`); bootstrap `acc-A`+`prj_prod`+owner; reusable роли (concrete compute.instance / vpc.subnet / iam.project); mirror наполнен через `compute→iam`, `vpc→iam`, `nlb→iam` RegisterResource (расширенный payload D4); под `prj_prod` — `inst-1`{env:prod}, `sub-1`{env:prod}, `disk-1`{env:prod}; `prj_a`{tier:gold} под `acc-A`

**When** owner создаёт selector-binding БЕЗ types (concrete compute.instance роль): `target={selector:{matchLabels:{env:prod}}}` → poll Operation
**Then** Operation done; `Get` отдаёт derived `types=["compute.instance"]`; `Check`(`inst-1`) → allowed (T1-01 derive E2E)

**When** owner создаёт selector для `vpc.subnet` (explicit types): `target={selector:{types:["vpc.subnet"], matchLabels:{env:prod}}}`
**Then** `sub-1`→ACTIVE; `Check`(`usr-MEMBER`, `sub-1`) → allowed (T3-01 vpc E2E)

**When** owner создаёт selector для `iam.project` на `account:acc-A`: `target={selector:{types:["iam.project"], matchLabels:{tier:gold}}}`
**Then** `prj_a`→ACTIVE (direct same-DB); `Check`(`prj_a`) → allowed (T3-04 iam-direct E2E)

**When** vpc меняет `sub-1` env=prod→dev + RegisterResource
**Then** reconciler eager-revoke'ит `sub-1` tuple; `Check`(`sub-1`) → НЕ allowed (T3-06 label-reconcile E2E)

**And** UI: grant-форма «По меткам» → types-picker пустой (hint про derive) → submit → детальный экран показывает derived types + membership-бейджи; смена типа на vpc.subnet через «Заменить селектор» меняет membership

---

## 5. Зафиксированные решения (бывш. открытые вопросы — ЗАКРЫТЫ на APPROVED; НЕ переоткрывать)

> Все Q1–Q6 закрыты родителем/ревьюером на review. Колонка «Решение (FIXED)» — нормативна; столбец «Кому» оставлен как указание, кто финализирует деталь реализации (точный список типов / SQL-форма триггера) в рамках уже-принятого решения, НЕ как «вопрос на согласование».

| # | Вопрос | Решение (FIXED — на APPROVED) | Финализирует деталь impl |
|---|---|---|---|
| **Q1** | **Полный список vpc/nlb типов в `selectableTypes`** (D4) — все ли (network/subnet/SG/RT/address/gateway/NIC; LB/TG/listener) или подмножество с реальными tenant-labels? | Все, у которых owner эмитит labels через RegisterResource; типы без осмысленных labels (напр. служебные) — не включать. Финал — по closed-table authzmap ∩ active-feed. | `proto-api-reviewer` / заказчик |
| **Q2** | **Триггер reconcile на iam-direct own-resource label-change** (T3-07, D6) — outbox-событие в writer-tx `Project.Update`(labels-mask) (как γ-Q1 для mirror) ИЛИ reconcile-sweep? | (a) outbox-событие в той же writer-tx, что Project.Update labels (event-driven, атомарно) + sweep как defense-in-depth — паритет γ-Q1. | `system-design-reviewer` |
| **Q3** | **Триггер reconcile на Role.Update (permissions change) для derived-types** (T1-09) — пересчитывать derived-types selector-binding'ов при изменении роли? | На этом эпике — НЕТ автотриггера (Role.permissions редко меняются; derived пересчитается на следующем mirror/sweep-триггере). Если нужен немедленный — отдельный тикет. Подтвердить, что «derived-types eventual при Role.Update» приемлемо. | заказчик / `system-design-reviewer` |
| **Q4** | **Какие iam-типы реально несут labels** (D6) — project/account точно; user/group/role — есть ли labels-колонка / нужны ли они в selector? | project/account — да (labels есть). user/group/role — включать только если есть labels И есть юзкейс; иначе ограничить selector подмножеством iam-типов (project/account). НЕ добавлять labels-колонку ради selector. | заказчик |
| **Q5** | **`selectableTypes` дескриптор — где конфигурируется** (D7) — статический закрытый код-реестр (per-type дескриптор feed-source+containment в Go) ИЛИ конфиг? | Статический код-реестр (closed-table, как authzmap.ObjectType) — типы добавляются только с feed-кодом, не через конфиг; конфиг-driven открыл бы «вечный PENDING» для типа без feed. | `system-design-reviewer` |
| **Q6** | **Mixed-роль derive (T1-03)** — derive concrete-набор, wildcard игнор; ИЛИ wildcard+опущ.types всегда reject даже при наличии concrete? | (a) derive concrete-набор, wildcard игнор (concrete достаточно для вывода; «явный набор побеждает всё»). Reject ТОЛЬКО когда concrete selectable = ∅ (wildcard-only). | заказчик / `acceptance-reviewer` |

> Поведение API наблюдаемо одинаково для большинства вердиктов — закрытие влияет на план (`writing-plans`) и реализацию (reconciler-триггеры, список типов), не на форму сценариев. Q1/Q4 (списки типов) могут добавить/убрать happy-сценарии — уточнить ДО `integration-tester`.

---

## 6. Definition of Done (на каждую стадию)

Кросс-репо порядок (`polyrepo.md`): **proto → iam → vpc/nlb/compute → api-gateway → ui → deploy → workspace(docs)**. Стадии — самостоятельные deliverable'ы; CI нижестоящего пиннит sibling к feature-ветке до merge вышестоящего. **T1 и T3 — независимые Subtask'и**; T1 не требует T3 (derive работает и для compute.instance), но E2E-полнота — после обоих.

**S1 — proto (`kacho-proto`) [T1]:**
- [ ] `ResourceSelector.types` документирован как ОПЦИОНАЛЬНЫЙ (поле уже `repeated`; меняется только семантика пустого — server-side, НЕ wire-breaking). `match_labels` остаётся обязательным.
- [ ] Если `RegisterResource` payload vpc/nlb требует новых полей `labels`/`parent_*` (T3, D4) — проверить, что они УЖЕ в proto (β добавил для compute generic `RegisterResource`) → переиспользовать; новых proto-полей не вводить (additive если нужно). Ревью — `proto-api-reviewer`.
- [ ] `buf lint`/`breaking` зелёные (T1 — НЕ breaking: семантика пустого, не форма).

**S2 — iam (`kacho-iam`) [T1 + T3 core]:**
- [ ] RED integration-тесты (testcontainers) по T1-01..T1-09, T3-01..T3-16 первыми, **включая T1-02/T1-03 (wildcard/mixed derive), T3-04/T3-07 (iam-direct), T3-05/T3-10 (containment per feed-source), T3-13 (concurrent vpc label-flip), T3-16 (γ non-regression)** → подтверждён красный → GREEN.
- [ ] **T1 derive (D1/D2/D3):** `selector.types` пустой → derive из `role.permissions` (concrete-types ∩ selectableTypes) в reconciler/worker; wildcard-only+пусто → sync `INVALID_ARGUMENT` (D2); mixed → concrete-набор (D2); `Get` отдаёт эффективный types (D3); `matchLabels` остаётся обязателен (T1-07).
- [ ] **T3 reconciler feed-generalize (D7):** `selectableTypes` — per-type дескриптор (feed-source mirror|iam-direct + containment-rule mirror.parent|iam-hierarchy); reconciler перестаёт быть hardcoded `compute.instance`; matched-set+diff per дескриптор; emit/revoke универсален. Закрытый код-реестр (Q5).
- [ ] **T3 compute disk/image/snapshot (D5):** типы в `selectableTypes`+reconciler feed; labels уже в mirror (нет compute-emit изменений).
- [ ] **T3 iam-direct (D6):** iam.project/account/(user/group/role per Q4) — direct same-DB SELECT `@>` на own-table + iam-hierarchy containment; БЕЗ self-register-mirror; iam-типы без PENDING_VERIFICATION; триггер reconcile на own-resource label-change (Q2).
- [ ] **vpc/nlb labels-validation на RegisterResource (T3-15):** невалидные labels reject (β-15 паттерн) + DB CHECK jsonb-object.
- [ ] Error-mapping (`INVALID_ARGUMENT`/`FAILED_PRECONDITION`/`PERMISSION_DENIED`/`UNAUTHENTICATED`), без leak pgx.
- [ ] **Concurrent integration-тест** T3-13 (vpc label-flip + reconcile idempotent, ≥2 goroutine) ОБЯЗАТЕЛЕН (RED-first).
- [ ] by-design D1/D2/D3/D6/D7 — запись в `docs/architecture/` kacho-iam (derive из role-coverage; reconciler feed-generalize per-type дескриптор; iam-direct same-DB vs mirror; ацикличность — НЕ self-ребро, НЕ новые рёбра).
- [ ] Ревью — `db-architect-reviewer` (iam-direct GIN `@>` на own-table, containment iam-hierarchy SQL), `go-style-reviewer`, `system-design-reviewer` (reconciler feed-generalize / iam-direct триггер / **подтвердить: НЕТ новых рёбер `iam→vpc/nlb/compute`, НЕТ self-ребра `iam→iam`** — vpc/nlb расширяют существующий RegisterResource payload, iam — same-DB; ацикличность сохранена).

**S3 — vpc/nlb (`kacho-vpc`, `kacho-nlb`) [T3 label-emit]:**
- [ ] RED тесты: `RegisterResource` payload включает `labels`+`parent_project_id` (+`parent_account_id` если резолвится) на Create + Update-when-labels-in-mask; non-labels Update → no-op (β-04 паритет).
- [ ] vpc: расширить `fgaregister` payload + `iam_register_applier` на labels/parent; emit на Network/Subnet/… Create+Update-labels-mask (D4). nlb: аналогично для LB/TG/listener.
- [ ] `RegisterResource` остаётся Internal :9091 (НЕ external); mTLS; идемпотентно (β паттерн).
- [ ] Integration-тест: Create/Update-labels → mirror-side получает labels+parent (через IAM, проверяется на IAM-стороне S2 / e2e). vpc/nlb-side: payload-формирование.
- [ ] Ревью — `go-style-reviewer`; edge-обновление `edges/vpc-to-iam-*` / `edges/nlb-to-iam-*` (payload расширен labels/parent).

**S4 — api-gateway (`kacho-api-gateway`) [T3]:**
- [ ] Селектор-формы (Create/ReplaceTargetSelector) уже public (γ) — изменений регистрации НЕТ (T1/T3 не вводят новых RPC). Проверить, что vpc/nlb типы проходят через существующий public-путь.
- [ ] newman happy (T1-01 derive, T3-01 vpc, T3-02 nlb, T3-03 disk, T3-04 iam-direct, T1T3-E2E целевой JSON) + negative (T1-02 wildcard, T1-05 role-coverage, T1-07 matchLabels, T3-08 non-fed, T3-10 byName containment, T3-14 authz/anon) + γ non-regression (T3-16) через api-gateway, RED-first.

**S5 — ui (`kacho-ui`) [T1 + T3]:**
- [ ] types-picker опционален + hint про derive (T3-17, T1); типы всех selectable-доменов в picker (T3).
- [ ] membership-превью с verification-бейджами для всех типов (T3-18); эффективный derived types в детальном экране (D3).
- [ ] back-compat: режимы «Весь scope»/«Конкретные объекты»/«По меткам» (γ) сохранены; existing-binding с явными types рендерится идентично.
- [ ] UI-тесты (vitest/playwright) по T3-17/T3-18.

**S6 — deploy (`kacho-deploy`) [T3]:**
- [ ] vpc/nlb register-applier labels-emit — конфиг (если есть feature-flag); reconciler feed-дескриптор — in-process (без нового деплоя); e2e-build-матрицы newman зелёные для всех затронутых сервисов.

**S7 — workspace (docs/vault):** обновить `resources/iam-resource-mirror.md` (vpc/nlb теперь fed labels+parent — расширить «Lifecycle» секцию), `resources/iam-access-binding.md` (selector.types опциональны + derive; selectable-типы расширены до all-services + iam-direct), `rpc/iam-access-binding-service.md` (derive-семантика), `edges/vpc-to-iam-*` / `edges/nlb-to-iam-*` (payload labels/parent + History KAC), KAC-trail (Subtask T1, Subtask T3); этот acceptance-док → APPROVED. **НЕ заводить `edges/iam-to-vpc`/`iam-to-nlb`/`iam-to-compute`** (containment из same-DB mirror/own-table); **НЕ заводить `edges/iam-to-iam`** (iam-direct same-DB).

**Финальная верификация (перед merge каждой Go-стадии):** `go test ./... -race` + `golangci-lint run` + `govulncheck` + `make audit-list-filter` + newman зелёные.

---

## 7. Выход / запреты

- Единственный артефакт этого шага — настоящий markdown. **Никакого кода** (ни `.go`, ни `.sql`, ни `.proto`).
- Описано только наблюдаемое поведение API/UI; DB-форма (iam-direct GIN, containment SQL, reconciler дескриптор-реестр), reconciler-планировка — забота `db-architect-reviewer`/`migration-writer`/`system-design-reviewer`/`rpc-implementer`.
- **sub-phase γ НЕ модифицируется** в части формы: selector-контракт (matchLabels обязателен, containment, expiry, ReplaceTargetSelector, verification_status) сохраняется; T1 ослабляет ТОЛЬКО types-обязательность (derive); T3 расширяет ТОЛЬКО `selectableTypes`+feed-source.
- **НЕ вводятся новые cross-domain рёбра:** `vpc→iam`/`nlb→iam` `RegisterResource` — существующие (расширяем payload labels/parent); iam-ресурсы — same-DB direct (НЕТ self-ребра `iam→iam`, НЕТ `iam→owner`); ацикличность графа non-negotiable (`polyrepo.md`).
- **Non-breaking** (D8): T1 — пустой types раньше reject, теперь derive (расширение); T3 — типы раньше «not selectable», теперь работают (аддитивно); existing-binding'и не затронуты.
- Без сравнений с чужими облаками — конвенции Kachō нормативны (`api-conventions.md`).
- Координация после APPROVED: KAC Subtask T1 + Subtask T3 + `superpowers:writing-plans` → `integration-tester` (RED по T1-NN/T3-NN) → `rpc-implementer` → `proto-api-reviewer` (types-опциональность / RegisterResource payload) / `db-architect-reviewer` (iam-direct same-DB / GIN / containment) / `system-design-reviewer` (reconciler feed-generalize / iam-direct триггер / ацикличность) → заказчик: финальный smoke (§J T1T3-E2E).
