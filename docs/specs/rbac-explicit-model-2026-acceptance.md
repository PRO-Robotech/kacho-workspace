# Эпик «Explicit RBAC model 2026» — Acceptance (design + Given-When-Then)

> Статус: **APPROVED** (round 2 — acceptance-reviewer ✅ + system-design-reviewer ✅, 2026-06-24)
> Дата: 2026-06-24 (rev2 — зашиты Q-резолюции + 5 КФ system-design + acceptance-reviewer findings)
> Ревьюер: acceptance-reviewer (round 1 ❌ → round 2 ✅ APPROVED) · system-design-reviewer (round 1 ❌ → round 2 ✅ APPROVED)
> Эпик/тикет: KAC-номер не заведён (MCP YouTrack недоступен на момент написания) — **этот документ + vault-trail = anchor эпика**. Заводится ретроспективно при первом доступном YT.
> Re-touch эпика [#109](https://github.com/PRO-Robotech/kacho-workspace/issues/109) (RBAC-rules-model).
> Backend: `kacho-iam` · Proto: `kacho-proto` (iam/v1) · Deploy: `kacho-deploy` (openfga-bootstrap) · Gateway: `kacho-api-gateway` · UI: `kacho-ui` · Docs: `kacho-workspace`
> Источники (нормативно): `.claude/rules/api-conventions.md`, `.claude/rules/data-integrity.md`, `.claude/rules/security.md`, `.claude/rules/architecture.md`; `docs/specs/01-architecture-and-services.md`; `docs/specs/02-data-model-and-conventions.md` §14 (коды ошибок).
> Опорные под-фазы: T3.1 материализация (`docs/specs/sub-phase-T3.1-cross-service-label-revoke-acceptance.md`, APPROVED 2026-06-23, epic #113); cluster-admin bootstrap (KAC-196, `InternalClusterService`); сценарий defense `vpc.address.deletion_protection` как образец protection-флага.
> Ground-truth сверен с кодом 2026-06-24 (см. §11 «Ground-truth, расхождения с формулировкой владельца»).

---

## 0. Design-решения (D-1..D-18) — целевая модель

> Это §0 нормативной части. Каждое решение фиксирует целевую семантику и обоснование. Сценарии (§§2–9) трассируются на эти решения. Открытые вопросы round 1 закрыты — резолюции в §12 «Принятые решения 2026-06-24». Декомпозиция на под-фазы — §10.

### Принцип-инвариант (overarching) — НОРМАТИВ (Q-2 закрыт)

**Bounded scope (ACCOUNT / PROJECT) → ЯВНАЯ per-object материализация. GLOBAL → per-object материализация по объектам, матчащимся `names`/`labels`-селектором кластер-wide. GLOBAL + selector `all` + `*.*.*` (cluster-admin роль) → ЕДИНСТВЕННОЕ плоское cluster-relation + Check-short-circuit (D-9) — это ЕДИНСТВЕННЫЙ легальный носитель «GLOBAL+all».** Нигде в семантике доступа нет implicit hierarchy-каскада «доступ к родителю ⇒ доступ к содержимому». Каскад остаётся ТОЛЬКО для membership-write-authz (кто вправе выдавать гранты), не для самого доступа.

**НОРМАТИВ Q-2:** `GLOBAL + selector all` для **не-cluster-admin** роли — **запрещён** (sync `INVALID_ARGUMENT`, A-05). Per-object материализация «на весь кластер» для обычной роли — анти-паттерн (churn на каждом Create, неограниченный размер ledger). Обычная роль на GLOBAL легальна ТОЛЬКО с `names`/`labels`-селектором (A-05b: материализация только по матч-объектам кластер-wide, конечный и явный набор). Cluster-admin роль (`modules:["*"], resources:["*"], verbs:["*"], selector all`) — единственное исключение, для неё GLOBAL без `names`/`labels` легален и обслуживается D-9 short-circuit (НЕ per-object).

---

**D-1. Роль = неизменная единица; rules сохраняются.**
Роль остаётся `{id, name, is_system, scope, rules[]}`, где `rules[] = [{module(s), resources[], verbs[], selector}]`. Селектор внутри правила — `all` (ARM_ANCHOR) | `names[]` (ARM_NAMES) | `labels{}` (ARM_LABELS) — **семантика и форма не меняются** (req владельца #1, #3). Меняется ТОЛЬКО способ энфорса: явная per-object материализация вместо derivation-каскада в FGA-модели.

**D-2. Доступ выдаётся ЯВНО — никакого implicit hierarchy-каскада в семантике доступа.**
Из FGA-модели убираются derivation-правила `<rel> from account` / `from project` / `from cluster` для **доступа к содержимому** и computed-usersets `g_*_<type> from <anchor>` + `sg_<type>` (escalation-engine #177). FGA становится **плоским индексом** (Zanzibar-as-storage): прямые relation-tuple, без вычисляемых каскадов доступа (req #2). Исключения каскада, которые ОСТАЮТСЯ, — D-7 (membership-write-authz tiers) и D-9 (cluster super-admin).

**D-3. Грант = (subject, role, scope), где scope — ГРАНИЦА материализации, не корень наследования.**
`scope ∈ {GLOBAL, ACCOUNT, PROJECT}` (req #4 — никаких folder/org). Селектор правила роли перечисляет/матчит объекты **внутри** scope; материализуется явный per-object tuple для каждого объекта, который (а) лежит внутри scope И (б) матчится селектором. Scope сам по себе НЕ даёт доступа к содержимому — он лишь ограничивает область материализации.
**Ограничение GLOBAL (Q-2 норматив):** `GLOBAL + selector all` допустим ТОЛЬКО для cluster-admin роли (`*.*.*`) и обслуживается D-9 short-circuit (НЕ per-object). Для обычной роли `GLOBAL + all` отклоняется sync `INVALID_ARGUMENT` (A-05); легальны лишь `GLOBAL + names` / `GLOBAL + labels` → per-object материализация по матч-объектам кластер-wide (A-05b).

**D-4. Энфорс = ЕДИНСТВЕННЫЙ materialization-движок (reconciler/feed) для ВСЕХ селекторов — per-object для `all`/`names`/`labels` (КФ-3 АРХ-РЕШЕНИЕ).**
**Единый путь материализации.** Reconciler — **единственный** механизм, материализующий доступ для всех селекторов; binding-time `scope_grant`-эмиссия удаляется ЦЕЛИКОМ (см. ниже). Для каждого активного гранта reconciler на `RegisterResource`/Create/Update ресурса (инфра `RegisterResource → resource_mirror → ReconcileObject → applyDiff`, уже построена в T3.1) вычисляет: `scope ⊇ местоположение(ресурс)` И `selector матчит(ресурс)` → эмитит/поддерживает явный per-object FGA-tuple `<objType>:<id> # v_<verb> @ <subject>` (и tier-tuple). Revoke гранта / смена метки / выход объекта из scope → tuple снимается (по сохранённому ledger, не пере-выводится из роли).

**Удаляется binding-time scope_grant-путь ЦЕЛИКОМ.** Прежний путь эмиссии scope_grant на `CreateAccessBinding` (`scope_grant_tuples.go` / `buildBindingTuples`-ветка scope_grant) **убирается полностью** — его заменяет reconciler-материализация. T3.1-движок сейчас материализует ТОЛЬКО ARM_LABELS через `desiredMembers`/feed по `LabelSelectors`; **расширяем `desiredMembers`/feed на ARM_ANCHOR(`all`) + ARM_NAMES** (не только `LabelSelectors`), так что `all`/`names`/`labels` × scope-граница идут одним кодом. Это снимает «два пути backfill» (system-design finding): нет отдельной binding-time-эмиссии и отдельной reconcile-материализации — **только reconciler**; backfill = единый reconcile-sweep по всем активным bindings (§9 migrate).

**Forward-materialization (КФ-4 / Q-3 C-01).** Ресурс, появившийся в scope гранта ПОСЛЕ Create binding (включая ресурсы, созданные после owner-binding на пустом аккаунте), материализуется тем же reconciler-путём на его `RegisterResource`/Create — без чего owner/grant «протухает». Forward-path — нормативная часть движка, не отдельный механизм.

**D-5. FGA-модель — плоский индекс.**
Удалить из `fga_model.fga` (canonical, kacho-proto) и регенерируемого configmap:
- все `<rel> from account` / `from project` / `from cluster` доступа-каскады на leaf-типах;
- весь `scope_grant` карьер: `sg_<type>` + `g_viewer/editor/admin/vget/vlist/vcreate/vupdate/vdelete_<type>` на cluster/account/project (24 resource-типа);
- (D-12) тип `organization` + все `… from organization`.
Остаются: subject-типы (`user`/`service_account`/`group#member`/`federated_subject`), прямые relation-tuple на leaf-типах (`v_*`, tier), cluster super-admin relation (D-9), CEL-conditions (без изменений).

**D-6. account/project становятся verb-bearing ресурсами.**
Сейчас `account`/`project` — tier-only (admin/editor/viewer, без `v_*`, без scope_grant; ground-truth `authzmap/fga_types.go::TypeHasVerbRelations` исключает их). Целевая модель: добавить им замкнутый набор `v_get/v_list/v_create/v_update/v_delete` как у листовых типов (`TypeHasVerbRelations` начинает возвращать `true` для них). Следствие: грант роли `iam.account.get` на ACCOUNT-scope материализует `account:<id> # v_get @ subj` — доступ к **самому** account-объекту без доступа к содержимому. «Видеть account/project в селекторе, но не иметь доступа к контенту» выпадает само (D-6a).

**D-7. Tier admin/editor/viewer/owner на account/project ОСТАЁТСЯ — но только для membership-write-authz, без down-cascade в семантике доступа.**
Tiers нужны `requireGrantAuthority` (кто вправе выдавать гранты на этот scope: владелец account или delegated-admin). Они НЕ дают доступа к содержимому (никаких `v_* from account`). То есть `account:<id> # admin @ subj` означает «subj вправе администрировать гранты на этом аккаунте», а не «subj имеет admin на все ресурсы внутри».

**D-8. owner — системная cluster-роль (НЕТ сейчас, net-new).**
Ground-truth: системной роли `owner` НЕ существует (owner — это `Account.owner_user_id` FK + FGA-tuple). Создаём системную роль `owner` (cluster-scoped, `is_system=true`).
**Состав (Q-3 закрыт, вариант A):** `rules = [{modules:["*"], resources:["*"], verbs:["*"], selector: all}]`, всегда биндится @ **ACCOUNT:<A>** (scope = граница материализации = именно этот аккаунт, НЕ кластер) → **per-object материализация** на `account:<A>` (verb-bearing, D-6) + каждый ресурс ВНУТРИ A. Это много tuple, но **конечно и явно** (границей служит ACCOUNT-scope, не GLOBAL — поэтому Q-2 GLOBAL+all-запрет не нарушается: owner = `*.*.*` @ ACCOUNT, не @ GLOBAL).
На `Account.Create` сервис авто-создаёт `AccessBinding(subject=creator-user, role=owner, scope=ACCOUNT:<A>)` с **deletion_protection=true** (D-10). Без implicit owner→admin→viewer-каскада — owner получает явные per-object tuple как любой другой грант.

**D-8a. Forward-materialization owner (Q-3 / КФ-4 / КФ-5).** На момент `Account.Create` аккаунт **пуст** (0 ресурсов) → owner-binding эмитит ровно tuple на `account:<A>` (verb-bearing self) + tier `admin` (write-authz-якорь, D-7). Per-object tuple на **содержимое** появляются **forward** через D-4: каждый ресурс, создаваемый в A после owner-binding, материализует owner-tuple на своём `RegisterResource`/Create. Это (а) снимает tx-size риск на Account.Create (КФ-5 — нет десятков тысяч INSERT в одной tx), (б) гарантирует, что owner не протухает на ресурсах, появившихся позже. reconciler досоздаёт owner-tuple на любой новый ресурс A.

**D-9. GLOBAL-all super-admin (cluster-admin) — ЕДИНСТВЕННОЕ исключение из per-object.**
Материализовать per-object на весь кластер = анти-паттерн (миллионы tuple, churn на каждом Create). Поэтому cluster-admin = ОДНО явное cluster-relation `cluster:cluster_kacho_root # system_admin @ <subj>` + **top-level Check-short-circuit** в `authorize_service.Check`: «является ли subject cluster-admin?» → ALLOW до обычного резолва. Это **плоский супер-гейт**, НЕ иерархический каскад (не `<rel> from cluster`). Остаётся явным и аудируемым (1 факт = 1 tuple = 1 строка `cluster_admin_grants`).

**D-9 short-circuit применяется и к WRITE-authz (КФ-2).** После удаления каскада доступа cluster-admin теряет implicit account/project-tier admin-tuple, через которые сейчас проходит `requireGrantAuthority`. Поэтому short-circuit «является ли subject cluster-admin?» обязан применяться НЕ только в `authorize_service.Check`, но и во ВСЕХ write-authz-проверках: `requireGrantAuthority`, `fgaHoldsAdmin`, `RelationChecker` (membership-write-gate выдачи грантов). Cluster-admin должен мочь выдать грант на `ACCOUNT:A1`, где он НЕ owner и НЕ имеет account-tier admin-tuple → проходит `requireGrantAuthority` через short-circuit. То же — доступ cluster-admin к самим `iam_access_binding`-объектам (List/Get/Delete bindings): short-circuit покрывает их, чтобы cluster-admin не осиротел после удаления каскада `system_admin from cluster`.

**D-10. deletion_protection на binding — по образцу `vpc.address.deletion_protection`.**
Добавить `AccessBinding.deletion_protection bool` (default false). owner-auto-binding ставит `true`. `DeleteAccessBinding` на protected binding → **sync FAILED_PRECONDITION** pre-check `"access binding <id> has deletion_protection enabled; clear it via Update before Delete"` + атомарный CAS-backstop `DELETE … WHERE deletion_protection=false` (защита от TOCTOU). Снять защиту — `Update(update_mask=deletion_protection)`, затем Delete. (Образец двухслойной защиты — `kacho-vpc/internal/apps/kacho/api/address/delete.go` + `DeleteGuarded`.)

**D-11. cluster-admin bootstrap — через internal-only `InternalClusterService` (KAC-196, УЖЕ есть).**
Первый cluster-admin сидится на инсталле (`bootstrap_admin.go`, env `KACHO_IAM_BOOTSTRAP_ROOT_EMAIL` → `cluster_admin_grants` + fga_outbox tuple). Self-grant через публичный API невозможен (chicken-egg + separation of duties). Дальше existing cluster-admin выдаёт другим обычным `AccessBinding(role=owner? нет → role=cluster-admin @ GLOBAL)` или через `InternalClusterService.GrantAdmin`. **Функциональная deletion-protection** cluster-admin'а: инвариант «нельзя ревокнуть последнего активного» + «нельзя ревокнуть себя» (RevokeAdmin CAS-guard, FAILED_PRECONDITION). Нового флага не вводим — инвариант покрывает.

**D-11a. role=cluster-admin @ GLOBAL — закрыто (Q-4): bootstrap Internal + далее public binding.**
Системная роль `cluster-admin` (`rules = [{modules:["*"], resources:["*"], verbs:["*"], selector: all}]`, cluster-scoped, `is_system=true`) **существует**. Путь выдачи:
- **bootstrap первого** — ТОЛЬКО через `InternalClusterService` (KAC-196, internal :9091, env-seed), deletion-protected (D-11). Публичного self-grant до bootstrap нет (chicken-egg + separation of duties).
- **далее** — публичный `AccessBindingService/Create(subject, role=cluster-admin, scope=GLOBAL)` с `requireGrantAuthority=cluster-admin`. Этот binding — **спец-случай материализации**: эмитит **D-9 cluster-relation** `cluster:cluster_kacho_root # system_admin @ subj` (НЕ per-object материализацию на весь кластер). Вызов от не-cluster-admin → `PERMISSION_DENIED` (только cluster-admin вправе выдавать cluster-admin).
**Снятие кажущегося противоречия с Q-2:** Q-2 запрещает `GLOBAL+all` для НЕ-cluster-admin роли. Роль `cluster-admin` (`*.*.*`) — именно то исключение, которому `GLOBAL+all` легален; её binding обслуживается D-9 short-circuit, а не per-object материализацией. Q-2-валидация (A-05) пропускает `GLOBAL+all` ТОЛЬКО когда roleId == системная cluster-admin роль.

**D-12. ПОЛНОЕ удаление folder/organization из authz-модели.**
- FGA-модель: удалить `type organization` (canonical `fga_model.fga` L315–323) + 5 org-фрагментов на `type account` (L328 `define organization`, L330 `admin from organization`, L331 `editor from organization`, L341 `viewer from organization`, L342 `billing_admin from organization`). После — `grep -i organization` по `fga_model.fga` = 0.
- configmap `openfga-model-stub-configmap.yaml` регенерируется из canonical (`make openfga-model-json`) — руками не правим (D-13).
- `folder` как FGA-тип НЕ существует (Project заменил Folder, `project.proto`); остаются только legacy `folder_id` field-names/comments — их зачистка **ВНЕ scope** (Q-5 закрыт, см. §12 / §«Что НЕ входит»), не блокирует authz-модель.

**D-12a. Судьба B2B-ресурса `Organization` — закрыто (Q-1): FULL-REMOVAL (вариант A).**
Удаляется ВЕСЬ B2B-`Organization`: `organization.proto` + `OrganizationService`; `account.organization_id` (field 7); `Role.organization_id` (field 9); org compliance-scope; hooks `organization_id` session-claim; org-сиды. Это breaking по **живым полям** (`organization_id` ещё в proto-сообщениях) → выполняется через **expand→contract** (§9): contract-фаза дропает поля/route. Поведение в contract-окне — сценарий G-05 («route OrganizationService отсутствует на gateway; `organization_id` в теле запроса → proto3-ignored, не ошибка»).
**Объём (P1 расширен + новая строка под-фазы на iam):** не только proto-drop — также зачистка iam compliance org-scope, hooks org session-claim, seed. **Полнота (DoD):** `grep -rEi 'organization(_id)?' ` по proto / iam / deploy / docs / seed → **0 остаточных** упоминаний `organization`/`organization_id` (кроме исторических записей в самом acceptance/vault).

**D-13. Canonical FGA = `kacho-proto/proto/kacho/cloud/iam/v1/fga_model.fga`; configmap — build-артефакт.**
Все правки модели — в canonical `.fga`; `openfga-model-stub-configmap.yaml` (DSL + JSON блоки) регенерируется. Порядок по build-графу: proto-репо первым.

**D-14. scope_ref — имя ОСТАВЛЯЕМ (Q-6 закрыт), меняем только семантику.**
`scope_ref {tier, id}` сохраняет имя (rename отклонён, Q-6 — не вводим breaking-косметику для клиентов). Семантика меняется: `scope_ref` — write-authz-anchor (`requireGrantAuthority` / `IsRoleAssignable`) **И** граница материализации (D-3); **убирается scope_grant-каскад** (D-5) — `scope_ref` больше не порождает escalation-tuple. Legacy `resource_type`/`resource_id` остаются deprecated-проекцией на чтении (как сейчас).
**Q-5 (folder_id rename) — ВНЕ scope этого эпика** (отдельная cleanup-под-фаза, non-goal — см. §«Что НЕ входит»). `folder` как FGA-тип отсутствует; массовый rename legacy `folder_id`→`project_id` field-names в compute/vpc proto не входит в authz-модель.

**D-15. Check: плоский резолв + cluster-admin short-circuit; wildcard→DENY сохраняется.**
`authorize_service.Check`: (1) short-circuit cluster-admin (D-9); (2) иначе прямой FGA Check по материализованному tuple (плоский, без каскада); (3) `resource.id == "*"` (unscoped List) → clean DENY (как сейчас, не error); (4) unknown verb → fail-closed DENY (как сейчас). `ListUsers`/`ListObjects` после удаления scope_grant работают по прямым tuple (graph-traversal теперь тривиальный — нет indirection).

**D-16. List-filter (listauthz) сохраняет инвариант** `make audit-list-filter`: публичный `List<Resource>` фильтрует по материализованным per-object tuple владельца. После плоской модели фильтр читает прямые tuple — CI-гейт остаётся.

**D-17. Миграция — forward-only, idempotent, backfill без потери доступа (дух T3.1-G5). Стратегия — phased expand→migrate→contract (Q-7 закрыт).**
§9 — **утверждённый phased** (expand → migrate → contract + verify-gate); clean-cut отклонён (прод fe3455, no-access-loss-приоритет). Re-seed **63 system-ролей** под explicit (58 catalog + 5 SEC-C module-SA ролей, mig 0009; +`owner` net-new — итог зависит от того, входит ли owner/cluster-admin в каталог, см. §13.8) — rules уже есть с миграций 0031/0033, нужна сверка плоской материализуемости. Backfill — **chunked emit с tx-size bound** (КФ-5; не десятки тысяч INSERT в одной tx): для каждого активного legacy binding пере-материализовать прямые tuple ДО удаления каскада; owner-binding на существующие аккаунты (forward-materialization содержимого, D-8a). Backfill — **singleton single-shot мигратор** (`cmd/migrator`-стиль) под `pg_advisory_xact_lock` (КФ-1). **Зафиксированный дефолт (по замечанию ревьюеров P8):** steady-state reconcile использует ОДИН примитив — `pg_advisory_xact_lock(hashtext(binding_id))` (xact-scoped, НЕ pool-scoped), чтобы concurrent integration-тест (H-05) бил детерминированно; `FOR UPDATE SKIP LOCKED` — допустимая альтернатива только если plan её обоснует. **Обязательный backstop (КФ-3/H-04, отдаётся `db-architect-reviewer` в P8):** на `access_binding_emitted_tuples` — partial-UNIQUE на `(binding_id, object_type, object_id, relation)` (или эквивалент), чтобы гонка backfill-chunk vs forward-emit не плодила дубли (idempotent-upsert опирается на эту UNIQUE, не только на advisory-lock). Никакой оператор не теряет доступ (forward-only, idempotent re-apply, partial-unique guard).

**D-18. AuthN+AuthZ инвариант (security.md) НЕ ослабляется.** Все RPC обоих листенеров (public :443 / internal :9091) сохраняют per-RPC authz-Check. `InternalClusterService` остаётся internal-only (ban #6). Никакого `anonymous → full access`.

---

## 1. Обзор

kacho-iam authz переходит с **ReBAC-каскадной модели** (FGA computed-usersets `<rel> from account/project/cluster` + scope_grant escalation-engine #177 + мёртвый `organization`-tier) на **явную RBAC с per-object материализацией**. Семантика ролей и селекторов сохраняется (D-1, D-3); меняется механизм энфорса: вместо вычисляемого каскада в графе FGA — явные per-object relation-tuple, поддерживаемые reconciler'ом (расширение T3.1-движка на все селекторы × scope). Единственное исключение из per-object — GLOBAL cluster super-admin (одно cluster-relation + Check short-circuit, D-9). FGA становится плоским индексом (Zanzibar-as-storage). Полностью удаляются folder/organization из authz-модели.

Цель — **аудируемость и предсказуемость**: каждый факт доступа = явный tuple, который можно перечислить, объяснить (`ExpandAccess`) и ревокнуть, без «магического» каскада.

---

## 2. Группа A — грант × scope × селектор → какие явные tuple

> Базовая матрица. `subj` = `user:U1` (или `service_account:*` / `group#member`). Все мутации (`CreateAccessBinding`) — async `Operation`; клиент поллит `OperationService.Get(id)` до `done=true`, затем проверяет материализацию через `ExpandAccess` / `Check`.

### Сценарий A-01: grant @ PROJECT, селектор `all` (ARM_ANCHOR)

**ID:** rbac-A-01

**Given** существует `project:P1` в `account:A1`
**And** в `P1` есть ресурсы `vpc_network:N1`, `vpc_network:N2`, `compute_instance:I1`
**And** существует системная роль `R` с rules `[{modules:["vpc"], resources:["network"], verbs:["get","list"], selector: all}]`

**When** cluster-admin вызывает `iam.v1.AccessBindingService/Create` с payload:
  - `subjects = [{type: USER, id: U1}]`
  - `roleId = R`
  - `scopeRef = {tier: PROJECT, id: P1}`

**Then** возвращается `Operation`; полл `OperationService.Get(id)` → `done=true && !error`
**And** материализованы прямые per-object tuple ровно для объектов типа `vpc_network` внутри `P1`:
  - `vpc_network:N1 # v_get @ user:U1`, `vpc_network:N1 # v_list @ user:U1`
  - `vpc_network:N2 # v_get @ user:U1`, `vpc_network:N2 # v_list @ user:U1`
**And** НЕ материализован tuple на `compute_instance:I1` (другой тип)
**And** НЕ создано НИ ОДНОГО `scope_grant:*` объекта (escalation-engine удалён, D-5)
**And** НЕ создано bare-tier tuple на `project:P1` для доступа-каскада (D-2)
**And** `Check(subject=user:U1, action=get, resource=vpc_network:N1)` → `allowed=true`
**And** `Check(subject=user:U1, action=get, resource=compute_instance:I1)` → `allowed=false` (reason: no path)

### Сценарий A-02: grant @ PROJECT, селектор `names[]` (ARM_NAMES)

**ID:** rbac-A-02

**Given** условия A-01
**And** роль `R` с rules `[{modules:["vpc"], resources:["network"], verbs:["get"], selector: {names: ["N1"]}}]` (имя/ id по конвенции селектора)

**When** cluster-admin создаёт binding `(U1, R, PROJECT:P1)`

**Then** `Operation.done && !error`
**And** материализован ТОЛЬКО `vpc_network:N1 # v_get @ user:U1`
**And** НЕ материализован tuple на `vpc_network:N2` (вне `names`)
**And** `Check(U1, get, vpc_network:N1)` → allowed; `Check(U1, get, vpc_network:N2)` → denied

### Сценарий A-03: grant @ PROJECT, селектор `labels{}` (ARM_LABELS)

**ID:** rbac-A-03

**Given** условия A-01
**And** `vpc_network:N1` имеет `labels {env: prod}`; `N2` — `labels {env: dev}`
**And** роль `R` с rules `[{modules:["vpc"], resources:["network"], verbs:["get"], selector: {labels: {env: "prod"}}}]`

**When** cluster-admin создаёт binding `(U1, R, PROJECT:P1)`
**And** `vpc_network` зарегистрирован в `resource_mirror` через `InternalIAMService.RegisterResource` (T3.1)

**Then** `Operation.done && !error`
**And** после reconcile (`ReconcileObject`, ≤2s) материализован ТОЛЬКО `vpc_network:N1 # v_get @ user:U1` (label match)
**And** НЕ материализован tuple на `N2` (`env=dev` не матчится)

### Сценарий A-04: grant @ ACCOUNT, селектор `all` — материализация в пределах account (cross-project)

**ID:** rbac-A-04

**Given** `account:A1` содержит `project:P1` и `project:P2`
**And** `vpc_network:N1 ∈ P1`, `vpc_network:N3 ∈ P2`, `vpc_network:NX ∈ другой account A2`
**And** роль `R` с rules `[{modules:["vpc"], resources:["network"], verbs:["get"], selector: all}]`

**When** cluster-admin создаёт binding `(U1, R, ACCOUNT:A1)`

**Then** `Operation.done && !error`
**And** материализованы `vpc_network:N1 # v_get @ U1` И `vpc_network:N3 # v_get @ U1` (оба внутри `A1`, scope = граница материализации, D-3)
**And** НЕ материализован tuple на `vpc_network:NX` (вне `A1`)

### Сценарий A-05: grant @ GLOBAL, селектор `all`, НЕ-cluster-admin роль → sync INVALID_ARGUMENT (Q-2 норматив)

**ID:** rbac-A-05

**Given** роль `R` (НЕ cluster-admin; roleId ≠ системная `cluster-admin` роль) rules `[{modules:["vpc"], resources:["network"], verbs:["get"], selector: all}]`

**When** cluster-admin вызывает `iam.v1.AccessBindingService/Create` с:
  - `subjects = [{type: USER, id: U1}]`
  - `roleId = R`
  - `scopeRef = {tier: GLOBAL}`

**Then** **sync** (до создания Operation) → `INVALID_ARGUMENT` с `field_violations` на `roleId`/`scopeRef`, текст вида `"GLOBAL scope requires names or labels selector for non-cluster-admin roles"`
**And** НЕ создано ни одного tuple, ни Operation (Q-2: `GLOBAL+all` легален ТОЛЬКО для cluster-admin роли `*.*.*` через D-9 short-circuit, A-05c)
**And** причина: per-object материализация «на весь кластер» для обычной роли — анти-паттерн (неограниченный ledger + churn), §0 норматив

### Сценарий A-05b: grant @ GLOBAL, селектор `names`/`labels`, обычная роль → per-object кластер-wide (легально)

**ID:** rbac-A-05b

**Given** роль `R` (НЕ cluster-admin) rules `[{modules:["vpc"], resources:["network"], verbs:["get"], selector: {labels: {tier: "gold"}}}]`
**And** в кластере (в разных аккаунтах) есть `vpc_network:NA {tier:gold} ∈ A1`, `vpc_network:NB {tier:gold} ∈ A2`, `vpc_network:NC {tier:silver} ∈ A1`

**When** cluster-admin создаёт binding `(U1, R, GLOBAL)`

**Then** `Operation.done && !error`
**And** после reconcile материализованы ТОЛЬКО `vpc_network:NA # v_get @ U1` И `vpc_network:NB # v_get @ U1` (матч `tier=gold` кластер-wide — GLOBAL = граница = весь кластер, но материализация ограничена селектором → конечный явный набор)
**And** НЕ материализован tuple на `NC` (`tier=silver` не матчится)
**And** аналогично легален `GLOBAL + names:[...]` (конечный перечень)

### Сценарий A-05c: grant @ GLOBAL, селектор `all`, роль = системная `cluster-admin` (`*.*.*`) → D-9 cluster-relation (легально, спец-случай)

**ID:** rbac-A-05c

**Given** системная роль `cluster-admin` (`rules=[{modules:["*"],resources:["*"],verbs:["*"],selector:all}]`, D-11a)
**And** caller — cluster-admin

**When** `AccessBindingService/Create(subject=U2, role=cluster-admin, scopeRef={GLOBAL})`

**Then** `Operation.done && !error`
**And** эмитится ЕДИНСТВЕННОЕ cluster-relation `cluster:cluster_kacho_root # system_admin @ user:U2` (D-9), НЕ per-object на весь кластер
**And** валидация A-05 пропускает `GLOBAL+all` ровно потому что `roleId` == системная cluster-admin роль (единственное исключение)
**And** caller НЕ cluster-admin → `PERMISSION_DENIED` (D-11a, `requireGrantAuthority=cluster-admin`)

### Сценарий A-06: grant роли с verb `*` (admin-tier) → полный набор v_* на матч-объектах

**ID:** rbac-A-06

**Given** роль `R` rules `[{modules:["compute"], resources:["instance"], verbs:["*"], selector: {names:["I1"]}}]`

**When** binding `(U1, R, PROJECT:P1)`

**Then** материализован замкнутый набор на `compute_instance:I1`: `v_get`, `v_list`, `v_create`, `v_update`, `v_delete` @ `user:U1` + tier `admin` (`ResolveVerbsAndTier(*)` → full closed set + admin)

---

## 3. Группа B — account/project как verb-bearing ресурсы (D-6)

### Сценарий B-01: «видеть account в селекторе без доступа к содержимому»

**ID:** rbac-B-01

**Given** роль `R` rules `[{modules:["iam"], resources:["account"], verbs:["get","list"], selector: all}]`
**And** `account:A1` содержит `vpc_network:N1`

**When** cluster-admin создаёт binding `(U1, R, ACCOUNT:A1)`

**Then** `Operation.done && !error`
**And** материализован `account:A1 # v_get @ user:U1` И `account:A1 # v_list @ user:U1` (account теперь verb-bearing, D-6)
**And** НЕ материализован НИ ОДИН tuple на содержимое `A1` (`vpc_network:N1` без tuple)
**And** `Check(U1, get, account:A1)` → allowed (видит сам account-объект)
**And** `Check(U1, get, vpc_network:N1)` → denied (нет доступа к содержимому — каскада нет, D-2)
**And** `IAM ProjectService/AccountService.Get/List` фильтрует так, что U1 видит `A1` в списке, но не его ресурсы

### Сценарий B-02: project verb-bearing — get/update самого project без admin на содержимое

**ID:** rbac-B-02

**Given** роль `R` rules `[{modules:["iam"], resources:["project"], verbs:["get","update"], selector: {names:["P1"]}}]`

**When** binding `(U1, R, PROJECT:P1)`

**Then** материализован `project:P1 # v_get @ U1`, `project:P1 # v_update @ U1`
**And** `Check(U1, update, project:P1)` → allowed
**And** `Check(U1, update, compute_instance:I1∈P1)` → denied

### Сценарий B-03: tier admin/editor/viewer на account остаётся write-authz-якорем (D-7)

**ID:** rbac-B-03

**Given** U2 держит `account:A1 # admin @ user:U2` (через owner-binding или delegated-admin)

**When** U2 вызывает `AccessBindingService/Create` с `scopeRef={ACCOUNT, A1}` (выдаёт грант кому-то на A1)

**Then** `requireGrantAuthority` проходит (U2 — admin на A1) → grant создаётся
**And** при этом `account:A1 # admin @ U2` САМ ПО СЕБЕ НЕ даёт U2 доступа к содержимому A1 (нет `v_* from account`, D-7): `Check(U2, get, vpc_network:N1∈A1)` → denied (если U2 не имеет отдельного материализованного гранта)

---

## 4. Группа C — owner авто-binding + deletion_protection (D-8, D-10)

### Сценарий C-01: Account.Create авто-создаёт owner-binding с per-object материализацией

**ID:** rbac-C-01

**Given** аутентифицированный `user:Uc` (creator)
**And** существует системная роль `owner` (cluster-scoped, D-8)

**When** Uc вызывает `iam.v1.AccountService/Create` с `name=acme`

**Then** возвращается `Operation`; полл → `done=true`; `Get` отдаёт `account:A1` с `ownerUserId=Uc`
**And** автоматически создан `AccessBinding(subject=user:Uc, role=owner, scopeRef={ACCOUNT, A1})` со `status=ACTIVE` и `deletion_protection=true`
**And** **dual-write co-commit (ВЗ-3, T3.1 G-4):** owner-binding-строка + emitted-tuple-ledger + `account:A1`-row INSERT + fga_outbox tuple — в ОДНОЙ writer-tx (атомарно; не «сначала account, потом отдельно binding»)
**And** аккаунт ПУСТ (0 ресурсов) → материализован конкретно: `account:A1 # v_get/v_list/v_create/v_update/v_delete @ user:Uc` (verb-bearing self, D-6) + tier `account:A1 # admin @ user:Uc` (write-authz-якорь, D-7)
**And** per-object tuple на СОДЕРЖИМОЕ A1 на этот момент НЕ создаются (содержимого нет) — они досоздаются **forward** через D-4/D-8a при Create каждого ресурса в A1
**And** `Check(Uc, admin, account:A1)` → allowed
**And** НЕТ implicit owner→admin→viewer-каскада (owner = явные tuple, D-8)

### Сценарий C-01b: forward-materialization owner на ресурс, созданный ПОСЛЕ owner-binding (Q-3 / КФ-4)

**ID:** rbac-C-01b

**Given** owner-binding `(Uc, owner, ACCOUNT:A1)` из C-01 (A1 был пуст)

**When** позже в A1 создаётся `vpc_network:Nlate` (consumer эмитит `RegisterResource`)

**Then** reconciler досоздаёт owner-tuple `vpc_network:Nlate # v_get/v_list/v_create/v_update/v_delete @ user:Uc` (forward-materialization, D-4)
**And** `Check(Uc, delete, vpc_network:Nlate)` → allowed (owner не протухает на поздних ресурсах)

### Сценарий C-02: Delete owner-binding с deletion_protection → FAILED_PRECONDITION (sync)

**ID:** rbac-C-02

**Given** owner-binding `B_owner` (`deletion_protection=true`) из C-01

**When** клиент вызывает `AccessBindingService/Delete` с `id=B_owner`

**Then** **sync** (до создания Operation) → `FAILED_PRECONDITION` `"access binding <id> has deletion_protection enabled; clear it via Update before Delete"` (образец `vpc.address`, D-10)
**And** binding остаётся `ACTIVE`; tuple не сняты

### Сценарий C-03: снять protection → Update → затем Delete проходит

**ID:** rbac-C-03

**Given** `B_owner` с `deletion_protection=true`

**When** `AccessBindingService/Update(id=B_owner, update_mask=["deletion_protection"], deletion_protection=false)` → `Operation.done`
**And** затем `AccessBindingService/Delete(id=B_owner)`

**Then** Delete → `Operation.done && !error`
**And** **(ВЗ-4)** все per-object owner-tuple на A1 (включая forward-материализованные на содержимое) сняты по сохранённому ledger (`access_binding_emitted_tuples`) **в той же writer-tx, что и DELETE binding-строки** (E-01 path, атомарно — не остаётся осиротевших tuple)
**And** `Check(Uc, admin, account:A1)` → denied (после revoke)

### Сценарий C-04: CAS-backstop против TOCTOU на Delete protected binding

**ID:** rbac-C-04

**Given** `B_owner` с `deletion_protection=false` (клиент только что снял)
**And** конкурентно другой actor ставит `deletion_protection=true` (Update) между sync-pre-check и worker-DELETE

**When** worker исполняет `DELETE … WHERE id=B_owner AND deletion_protection=false RETURNING …`

**Then** 0 rows → re-read → `deletion_protection=true` → `Operation.error = FAILED_PRECONDITION` (тот же текст)
**And** binding НЕ удалён (атомарный CAS поймал гонку, D-10 / data-integrity.md)
**And** при успешном пути (1 row) DELETE binding-строки + снятие per-object tuple по ledger — в ОДНОЙ writer-tx (ВЗ-3 dual-write co-commit на deletion_protection-Delete CAS-путь)

---

## 5. Группа D — cluster-admin bootstrap + GLOBAL Check short-circuit (D-9, D-11)

### Сценарий D-01: bootstrap первого cluster-admin через env (internal seed)

**ID:** rbac-D-01

**Given** свежая инсталляция; `KACHO_IAM_BOOTSTRAP_ROOT_EMAIL=root@acme` задан
**And** существует `user:Uroot` с email `root@acme`

**When** kacho-iam стартует (`bootstrap_admin.go`)

**Then** в одной tx: INSERT `cluster_admin_grants(subject=Uroot, granted_by='bootstrap')` + fga_outbox tuple `cluster:cluster_kacho_root # system_admin @ user:Uroot` + audit `iam.cluster_admin.granted`
**And** повторный рестарт → SQLSTATE 23505 на partial-unique → graceful skip (idempotent, D-17)
**And** self-grant cluster-admin через публичный `AccessBindingService` НЕвозможен (нет публичного пути к cluster super-admin до bootstrap; D-11)

### Сценарий D-02: cluster-admin Check short-circuit (плоский супер-гейт)

**ID:** rbac-D-02

**Given** `cluster:cluster_kacho_root # system_admin @ user:Uroot`
**And** существует `compute_instance:I9` БЕЗ каких-либо материализованных tuple для Uroot

**When** `Check(subject=user:Uroot, action=delete, resource=compute_instance:I9)`

**Then** `allowed=true` — через top-level short-circuit (D-9), БЕЗ резолва per-object tuple
**And** это плоский гейт «ты cluster-admin?», НЕ `<rel> from cluster`-каскад (модель плоская, D-5)
**And** для НЕ-cluster-admin Uother без tuple → `Check` → denied (нет short-circuit, нет tuple)

### Сценарий D-03: existing cluster-admin выдаёт cluster-admin другому

**ID:** rbac-D-03

**Given** Uroot — cluster-admin

**When** Uroot выдаёт cluster-admin пользователю U2 через public `AccessBindingService/Create(subject=U2, role=cluster-admin, scope=GLOBAL)` (Q-4 закрыт: bootstrap первого — Internal, далее public binding; см. D-11a / A-05c)

**Then** требует `requireGrantAuthority = cluster-admin` (только cluster-admin вправе; через КФ-2 short-circuit) → проходит
**And** создаётся `cluster:cluster_kacho_root # system_admin @ user:U2` (одно cluster-relation, D-9)
**And** `Check(U2, <any>, <any resource>)` → allowed (short-circuit)

### Сценарий D-04: нельзя ревокнуть последнего / себя (функциональная protection cluster-admin, D-11)

**ID:** rbac-D-04

**Given** Uroot — ЕДИНСТВЕННЫЙ активный cluster-admin

**When** `InternalClusterService/RevokeAdmin(subject=Uroot)`

**Then** `FAILED_PRECONDITION "cannot revoke last active cluster admin"`
**And** self-revoke (Uroot ревокает Uroot, даже если не последний) → `FAILED_PRECONDITION "cannot revoke own cluster admin grant"` (KAC-196 CAS-guard)

### Сценарий D-06: cluster-admin short-circuit покрывает WRITE-authz (КФ-2)

**ID:** rbac-D-06

**Given** Uroot — cluster-admin (`cluster:...# system_admin @ user:Uroot`)
**And** Uroot НЕ owner `account:A1` и НЕ имеет account-tier admin-tuple на A1 (каскад `system_admin from cluster` удалён, D-9 КФ-2)

**When** Uroot вызывает `AccessBindingService/Create(subject=U2, role=R, scopeRef={ACCOUNT, A1})` (выдаёт грант на чужой аккаунт)

**Then** `requireGrantAuthority` проходит через cluster-admin short-circuit (КФ-2: short-circuit применяется в `requireGrantAuthority`/`fgaHoldsAdmin`/`RelationChecker`, не только в `authorize_service.Check`)
**And** grant создаётся; не-cluster-admin без account-tier admin на A1 → `PERMISSION_DENIED`

### Сценарий D-07: cluster-admin доступ к самим iam_access_binding-объектам не осиротевает (КФ-2)

**ID:** rbac-D-07

**Given** Uroot — cluster-admin; в A1 есть `iam_access_binding:B1` (без материализованного tuple для Uroot)

**When** Uroot вызывает `AccessBindingService/List(scope=A1)` / `Get(B1)` / `Delete(B1)`

**Then** allowed через cluster-admin short-circuit (КФ-2 — после удаления каскада `system_admin from cluster` доступ cluster-admin к binding-объектам обеспечивается short-circuit, не каскадом)
**And** cluster-admin не теряет управление гранатами после contract-фазы

### Сценарий D-05: InternalClusterService недоступен на external endpoint (ban #6)

**ID:** rbac-D-05

**Given** api-gateway external :443

**When** клиент бьёт по public REST путь к cluster-admin-grant операции

**Then** маршрут отсутствует на external mux (404/не зарегистрирован); `InternalClusterService` доступен ТОЛЬКО на internal :9091 (D-18, security.md)

---

## 6. Группа E — revoke / label-change / scope-exit снимают tuple (D-4)

### Сценарий E-01: revoke гранта снимает все материализованные tuple

**ID:** rbac-E-01

**Given** активный binding `(U1, R[vpc.network.get, all], PROJECT:P1)` с материализованными `vpc_network:N1/N2 # v_get @ U1`

**When** `AccessBindingService/Delete(binding)`

**Then** `Operation.done && !error`
**And** сняты ВСЕ tuple по сохранённому ledger (`access_binding_emitted_tuples`) **в той же writer-tx, что и DELETE binding-строки** (ВЗ-4 dual-write co-commit), не пере-выводятся из роли (D-4)
**And** `Check(U1, get, vpc_network:N1)` → denied

### Сценарий E-02: смена метки выводит объект из-под labels-селектора → tuple снимается

**ID:** rbac-E-02

**Given** активный binding с ARM_LABELS `{env:prod}`; `vpc_network:N1 {env:prod}` материализован
**And** consumer (vpc) меняет `N1.labels` на `{env:dev}` и эмитит `RegisterResource` (T3.1 G-2: emit при labels в mask)

**When** reconcile (`ReconcileObject(vpc_network, N1)`, ≤2s)

**Then** `applyDiff` видит: N1 больше не матчится → fell-out → revoke `vpc_network:N1 # v_get @ U1` + `ForgetEmittedTuples`
**And** `Check(U1, get, vpc_network:N1)` → denied
**And** это путь, который T3.1 закрывает (consumer emit на label-Update); расширен на explicit-модель (D-4)

### Сценарий E-03: объект покидает scope (перемещение/удаление) → tuple снимается

**ID:** rbac-E-03

**Given** binding `(U1, R, PROJECT:P1)` с материализованным `vpc_network:N1∈P1`
**And** N1 удаляется (consumer эмитит `UnregisterResource`, T3.1 G-3 reserved-for-Delete)

**When** reconcile

**Then** `applyDiff` → N1 вне mirror → revoke tuple + DeleteMember
**And** dangling-ref переживается грациозно (data-integrity.md §cross-domain): IAM не паникует на отсутствующий объект

### Сценарий E-04: Role.Update меняет rules → реконсиляция диффа (добавление/снятие)

**ID:** rbac-E-04

**Given** роль `R` rules `[{vpc.network.get, names:[N1,N2]}]`; материализованы tuple на N1,N2 для всех bindings роли

**When** `RoleService/Update(R, rules=[{vpc.network.get, names:[N1]}])` (убрали N2)

**Then** для каждого активного binding роли: diff желаемое-vs-ledger → revoke `vpc_network:N2 # v_get @ subj`, оставить N1
**And** идемпотентно (повторный Update тем же → 0 изменений, D-17/G-5)

---

## 7. Группа F — Check / negative / wildcard (D-15)

### Сценарий F-01: Check по материализованному tuple (плоский, happy)

**ID:** rbac-F-01

**Given** `vpc_network:N1 # v_get @ user:U1`

**When** `InternalIAMService/Check(subject=user:U1, relation=v_get, object=vpc_network:N1)`

**Then** `allowed=true` (прямой tuple, без каскада)

### Сценарий F-02: unscoped List (resource.id="*") → clean DENY (не error)

**ID:** rbac-F-02

**When** `Check(subject=U1, action=list, resource={type:vpc_network, id:"*"})`

**Then** `allowed=false`, `denyReasons=["no path: unscoped resource"]`, БЕЗ gRPC-error (сохранение текущего поведения, D-15)

### Сценарий F-03: unknown verb → fail-closed DENY

**ID:** rbac-F-03

**When** `Check(action="frobnicate")` (не резолвится в relation)

**Then** `allowed=false` `"action … does not resolve to a known relation"` (fail-closed, D-15)

### Сценарий F-04: ExpandAccess перечисляет явных принципалов по прямым tuple

**ID:** rbac-F-04

**Given** `vpc_network:N1 # v_get @ user:U1`, `# v_get @ group:G1#member` (G1 = {U2,U3})

**When** `AccessBindingService/ExpandAccess(object=vpc_network:N1, relation=v_get)`

**Then** возвращает `[user:U1, user:U2, user:U3]` (groups развёрнуты; ListUsers по плоским tuple — после удаления scope_grant indirection тривиально, D-5/D-15)
**And** `requireGrantAuthority` на объекте энфорсится (read==enforce, security finding В3)

### Сценарий F-05: cross-service ref — owner недоступен на мутации → UNAVAILABLE

**ID:** rbac-F-05

**Given** Create binding со scope, требующим валидации через `ProjectService.Get` (project недоступен)

**When** `AccessBindingService/Create`

**Then** `Operation.error = UNAVAILABLE` (fail-closed для мутаций, data-integrity.md §2.2)

---

## 8. Группа G — удаление folder/organization (D-12)

### Сценарий G-01: FGA-модель не содержит organization после удаления

**ID:** rbac-G-01

**When** применена обновлённая `fga_model.fga` + регенерирован configmap

**Then** `grep -i organization kacho-proto/proto/kacho/cloud/iam/v1/fga_model.fga` → 0 совпадений
**And** в `type account` нет `define organization`, нет `admin/editor/viewer/billing_admin from organization`
**And** bootstrap-job OpenFGA принимает модель (валидный DSL→JSON), нет dangling-references

### Сценарий G-02: configmap регенерирован из canonical (не правлен руками)

**ID:** rbac-G-02

**When** `make openfga-model-json` (после правки canonical)

**Then** `openfga-model-stub-configmap.yaml` (DSL + JSON блоки) синхронен canonical; `grep -i organization` configmap → 0 (D-13)

### Сценарий G-03: residual org-references зачищены ПОЛНОСТЬЮ (Q-1 = full-removal, вариант A)

**ID:** rbac-G-03

**When** применён contract-этап Q-1 full-removal

**Then** `organization.proto` + `OrganizationService` удалены; `account.organization_id` (field 7) и `Role.organization_id` (field 9) дропнуты; org compliance-scope, hooks `organization_id` session-claim, org-сиды зачищены
**And** `grep -rEi 'organization(_id)?'` по proto / iam / deploy / docs / seed → **0 остаточных** упоминаний `organization`/`organization_id` (кроме исторических записей в acceptance/vault)

### Сценарий G-05: contract-окно поведения после drop организации (expand→contract, D-12a)

**ID:** rbac-G-05

**Given** клиент отправляет запрос, где в теле проставлено `organization_id` (старый клиент до contract)

**When** запрос приходит на gateway после contract-фазы (поле/route дропнуты)

**Then** route `OrganizationService` ОТСУТСТВУЕТ на gateway (404/не зарегистрирован — public и internal mux)
**And** `organization_id` в теле других запросов → **proto3-ignored** (неизвестное поле молча игнорируется, НЕ ошибка) — клиент не падает в contract-окне (expand→contract gradual rollout, §9)

### Сценарий G-04: folder — отсутствие FGA-типа подтверждено; legacy folder_id ВНЕ scope (Q-5)

**ID:** rbac-G-04

**Then** `folder` как FGA-тип отсутствует (всегда отсутствовал — Project заменил Folder); зачистка legacy `folder_id` field-names = ВНЕ scope этого эпика (Q-5 закрыт — отдельная cleanup-под-фаза, §«Что НЕ входит»), не блокирует authz-модель

---

## 9. Группа H — миграционная стратегия (D-17)

### Утверждённая стратегия (Q-7): PHASED expand → migrate → contract (clean-cut отклонён)

**Обоснование.** Это прод (fe3455) + 63 system-роли (58 catalog + 5 SEC-C module-SA) + существующие активные bindings + операторы с боевым доступом. Clean-cut (удалить каскад из модели и одномоментно пере-материализовать) рискует окном, где старые tuple ещё каскадные, новые ещё не материализованы → потеря доступа операторов. Поэтому **expand/contract** (утверждено Q-7):

**Порядок (КФ-4 forward-aware):** `expand-reconciler-live → backfill → continuous-verify → contract`. Contract НЕ снимает каскад, пока forward-path не подтверждён **живым smoke на свежесозданном ресурсе** (verify-gate непрерывный, не one-shot — см. ниже).

1. **Expand (additive, безопасно):**
   - Proto: add `account/project` verb-relations (D-6), add `AccessBinding.deletion_protection` (D-10), add `owner` system-роль seed (D-8). Org/folder ещё НЕ удаляем.
   - FGA-модель: add прямые `v_*` на account/project; **derivation-каскад и scope_grant-relations модели ещё на месте** (доступ дублируется: и каскадный, и материализованный — no-access-loss в окне).
   - iam: расширить **единый reconciler** на все селекторы × scope (D-4, КФ-3); Check short-circuit cluster-admin (Check + write-authz, КФ-2 D-9) — additive. **Примечание КФ-3:** удаление binding-time `scope_grant`-эмиссии (код `scope_grant_tuples.go`) выполняется уже в expand-фазе (заменяется reconciler-материализацией) — это безопасно, т.к. FGA-model derivation-каскад ещё держит доступ до contract; удаление scope_grant-relations из FGA-МОДЕЛИ — только в contract.

2. **Migrate (backfill, forward-only idempotent, дух T3.1-G5):**
   - Backfill — **singleton single-shot мигратор** (`cmd/migrator`-стиль) под `pg_advisory_xact_lock` (КФ-1): даже при N репликах backfill исполняет ровно один процесс; каждая единица работы (binding/аккаунт) обрабатывается ровно одной транзакцией. Steady-state reconcile-tx берёт `pg_advisory_xact_lock(hashtext(binding_id))` ИЛИ claim через `FOR UPDATE SKIP LOCKED` **внутри удерживаемой tx** (не pool-scoped) → сходимость к одному ledger.
   - Для КАЖДОГО активного legacy binding пере-материализовать прямые per-object tuple (через reconcile-sweep по всем bindings) — **chunked emit с tx-size bound** (КФ-5; не десятки тысяч INSERT в одной tx). Idempotent: повторный прогон → 0 изменений.
   - owner-binding на ВСЕ существующие аккаунты (subject = `Account.owner_user_id`, role=owner, scope=ACCOUNT, deletion_protection=true) — на пустой аккаунт сразу tuple на `account:<A>`; содержимое существующих аккаунтов материализуется тем же reconcile-sweep (chunked). Idempotent через partial-unique active-grant.
   - Re-seed **63 system-ролей** под explicit (rules уже есть с 0031/0033 — **сверить**, что материализуемы плоско; tier-parity сохранить, F-53).
   - **Verify-gate (КФ-4, непрерывный/forward-aware, НЕ one-shot):** до contract — прогон, что для каждого активного binding `Check` по новым прямым tuple == `Check` по старому каскаду (no-access-loss assertion). ПЛЮС **forward-smoke**: создать свежий ресурс в окне verify→contract → подтвердить, что forward-materialization (D-4) покрыла его до contract. Contract разрешён только когда (а) 100% no-access-loss И (б) forward-path подтверждён живым smoke на свежесозданном ресурсе.

3. **Contract (removal, после forward-aware verify):**
   - FGA-модель: удалить derivation-каскад доступа + scope_grant-relations (D-5) + `type organization` + 5 account-org-фрагментов (D-12).
   - Proto (Q-1 full-removal): drop `organization.proto`/`OrganizationService`/`account.organization_id`(f7)/`Role.organization_id`(f9); iam (P1b): зачистка compliance org-scope/hooks org session-claim/org-сидов.
   - configmap регенерировать (D-13).
   - (Код binding-time scope_grant emission уже удалён в expand — КФ-3.)

### Сценарий H-01: backfill не теряет доступ операторов

**ID:** rbac-H-01

**Given** оператор Uop имеет боевой доступ через legacy каскадный binding `(Uop, R, ACCOUNT:A1)`

**When** выполнен migrate-backfill (пере-материализация)

**Then** до contract: `Check(Uop, get, vpc_network:N1∈A1)` → allowed И через каскад, И через материализованный tuple
**And** после contract (каскад удалён): `Check` → allowed через материализованный tuple
**And** ни в какой момент окна `Check` не возвращает denied для Uop (no-access-loss, D-17)

### Сценарий H-02: idempotent re-apply миграции

**ID:** rbac-H-02

**When** migrate-backfill прогоняется повторно (рестарт/ретрай)

**Then** 0 новых tuple, 0 дублей owner-binding (partial-unique active-grant guard), 0 ошибок (forward-only idempotent, G-5)

### Сценарий H-03: re-seed 63 ролей не ломает tier-parity

**ID:** rbac-H-03

**Then** после re-seed **63 system-ролей** (58 catalog + 5 SEC-C module-SA, mig 0009): для каждой системной роли rules-derived tier == permissions-derived tier (инвариант F-53, `tier_parity_integration_test.go` зелёный — счётчик ролей обновлён 58→63)

### Сценарий H-04: коммутативность/идемпотентность backfill-sweep vs live forward-materialization

**ID:** rbac-H-04

**Given** backfill-sweep по существующим bindings выполняется ОДНОВРЕМЕННО с live forward-materialization (новый ресурс создаётся в окне backfill)

**When** оба пути (backfill chunk + forward emit на `RegisterResource`) эмитят tuple на один и тот же binding/ресурс в произвольном порядке

**Then** результат коммутативен и идемпотентен — оба пути сходятся к ОДНОМУ ledger (`access_binding_emitted_tuples`): нет дублей (partial-unique guard), нет потери tuple, порядок не влияет
**And** повторный прогон любого пути → 0 изменений (КФ-1 advisory-lock + idempotent upsert)

### Сценарий H-05: координация реплик при backfill (КФ-1 CONC)

**ID:** rbac-H-05

**Given** kacho-iam развёрнут в N репликах; backfill-мигратор запущен

**When** несколько реплик одновременно пытаются взять backfill-работу

**Then** под `pg_advisory_xact_lock` единицу работы (binding/аккаунт) обрабатывает РОВНО ОДНА реплика (остальные ждут/пропускают через SKIP LOCKED внутри удерживаемой tx)
**And** итог — сходимость к одному ledger; ни одна единица не материализуется дважды, ни одна не пропущена (КФ-1)

### Сценарий H-06: forward-aware verify-gate перед contract (КФ-4)

**ID:** rbac-H-06

**Given** expand-reconciler-live + backfill завершены; verify-gate активен

**When** в окне verify→contract создаётся свежий ресурс `vpc_network:Nfresh ∈ A1` (где U1 имеет активный grant с матчащим селектором)

**Then** forward-materialization (D-4) покрыла `Nfresh # v_get @ U1` ДО contract; live-smoke `Check(U1, get, Nfresh)` → allowed
**And** contract НЕ снимает каскад, пока этот forward-smoke на свежесозданном ресурсе не подтверждён (порядок: expand-reconciler-live → backfill → continuous-verify → contract)

---

## 10. Декомпозиция на под-фазы (порядок по build-графу)

> Каждая под-фаза = отдельный будущий APPROVED acceptance-док + KAC-subtask. Порядок строго по build-графу (`polyrepo.md`): proto → corelib (если нужно) → iam → api-gateway → deploy → ui → docs. FGA-модель (canonical в proto) — первой.

| # | Под-фаза | Репо | Содержание | Зависит от |
|---|---|---|---|---|
| **P1** | proto: scope/deletion_protection/owner+cluster-admin role + drop org (Q-1) | `kacho-proto` | `AccessBinding.deletion_protection`; verb-relations account/project в `fga_model.fga` (expand); seed-форма owner-роли (`*.*.*` @ ACCOUNT) + cluster-admin роли (`*.*.*` @ GLOBAL); (contract-фаза, Q-1 full-removal) drop `type organization` + 5 account-фрагментов + `organization.proto`/`OrganizationService` + `account.organization_id`(f7) + `Role.organization_id`(f9) | — |
| **P1b** | iam: org-decommission (Q-1 full-removal — НЕ только proto) | `kacho-iam` | зачистка iam compliance org-scope, hooks `organization_id` session-claim, org-сиды; DoD: `grep -rEi 'organization(_id)?'` по iam/deploy/seed → 0 | P1 |
| **P2** | FGA-модель flat (expand→contract) | `kacho-proto` + `kacho-deploy` | canonical `fga_model.fga`: add прямые `v_*`; (contract) drop каскад+scope_grant+org; регенерация configmap `make openfga-model-json` | P1 |
| **P3** | iam: authzmap verb-bearing account/project | `kacho-iam` | `TypeHasVerbRelations` → true для account/project; relation-sets; expandable-relations | P1,P2 |
| **P4** | iam: ЕДИНЫЙ reconciler ALL-selectors × scope; УДАЛИТЬ binding-time scope_grant-эмиссию (КФ-3) | `kacho-iam` | расширить `desiredMembers`/feed с ARM_LABELS на ARM_ANCHOR(all)+ARM_NAMES × scope-границу; emit/revoke прямых tuple; **удалить `scope_grant_tuples.go`/`buildBindingTuples` scope_grant-путь ЦЕЛИКОМ**; forward-materialization (D-4); Q-2 GLOBAL+all validation (A-05 reject) | P3 |
| **P5** | iam: Check flat + cluster-admin short-circuit (Check И write-authz, КФ-2) | `kacho-iam` | `authorize_service.Check` short-circuit (D-9); **short-circuit также в `requireGrantAuthority`/`fgaHoldsAdmin`/`RelationChecker`** (КФ-2); плоский резолв; ListUsers по прямым tuple; public Create(role=cluster-admin@GLOBAL) → D-9 cluster-relation (D-11a) | P3 |
| **P6** | iam: owner auto-bind + deletion_protection (dual-write co-commit, ВЗ-3) | `kacho-iam` | owner-роль; `Account.Create` авто-binding (owner-binding+ledger+account INSERT+outbox в ОДНОЙ tx); `deletion_protection` field + sync-precheck + CAS-backstop Delete (dual-write co-commit, ВЗ-3/ВЗ-4); Update-снятие | P3,P4 |
| **P7** | iam: list-filter (listauthz) на плоской модели | `kacho-iam` | `make audit-list-filter` зелёный по прямым tuple (D-16) | P5 |
| **P8** | migration: re-seed 63 + backfill tuple + owner-binding на существующие аккаунты | `kacho-iam` | forward-only idempotent goose-миграции; **singleton single-shot мигратор под `pg_advisory_xact_lock` (КФ-1)**; **chunked emit tx-size bound (КФ-5)**; verify-gate **непрерывный/forward-aware** (КФ-4); no-access-loss (§9); tier-parity 58→63 (F-53) | P3–P7 |
| **P9** | api-gateway | `kacho-api-gateway` | регистрация изменённых RPC (public mux / internal mux); InternalClusterService остаётся internal-only | P3–P6 |
| **P10** | deploy | `kacho-deploy` | helm/compose: bootstrap-job новой модели; env `KACHO_IAM_BOOTSTRAP_ROOT_EMAIL` | P2,P8 |
| **P11** | ui | `kacho-ui` | формы AccessBinding (deletion_protection, owner-индикатор); удаление org/folder UI-следов | P9 |
| **P12** | docs | `kacho-workspace` | спека-книга 00–04 (RBAC-глава), docs-site iam, удаление org/folder упоминаний; stale-счётчики Q-8 (cond 7→6, роли «12»→63, AccessBinding INSERT→ALREADY_EXISTS) | все |

**Контракт «expand → migrate → contract» (§9) расщепляет P1/P1b/P2/P8** на additive-фазу (expand, безопасно мёржится) и removal-фазу (contract, после forward-aware verify-gate, КФ-4). Q-1 full-removal (proto-drop + iam org-decommission) — в contract-фазе P1/P1b. Каждая под-фаза несёт собственный DoD: proto+regen (buf lint/breaking зелёные), код, integration-тест (testcontainers, включая concurrent CAS на deletion_protection Delete И concurrent backfill-replica под advisory-lock, КФ-1), newman happy+negative (вкл. A-05 GLOBAL+all reject), UI (где затронут), vault-trail (`.claude/rules/testing.md`).

---

## 11. Traceability сценариев в тесты (RED-until)

| Сценарий | Integration (testcontainers) | Newman (api-gateway) | Состояние до фикса |
|---|---|---|---|
| A-01..A-04, A-06 | reconcile applyDiff: selector×scope → прямые tuple; assert НЕТ scope_grant; единый путь (КФ-3) | grant + ExpandAccess assert per-object | RED — reconciler сейчас только labels; scope_grant ещё эмитится |
| A-05 (negative) | Create(GLOBAL+all, non-cluster-admin role) → sync INVALID_ARGUMENT field_violations | grant GLOBAL+all обычной роли → 400 | RED — валидация Q-2 не написана |
| A-05b | reconcile GLOBAL+labels/names → per-object кластер-wide матч | grant GLOBAL+labels → ExpandAccess матч-объекты | RED |
| A-05c | Create(GLOBAL+all, cluster-admin role) → D-9 cluster-relation; non-admin caller→PERMISSION_DENIED | public cluster-admin grant happy+denied | RED |
| B-01..B-03 | authzmap verb-bearing account/project; Check account vs content | account-in-selector visibility | RED — account/project tier-only |
| C-01, C-01b, C-02..C-04 | owner auto-bind on Account.Create (dual-write co-commit ВЗ-3); forward-mat C-01b; deletion_protection sync+CAS (concurrent goroutines на Delete) | owner-binding present; Delete protected→412; forward-mat на поздний ресурс | RED — owner-роль/deletion_protection/forward-mat не существуют |
| D-01..D-07 | bootstrap idempotent (23505 skip); Check short-circuit; write-authz short-circuit (КФ-2 D-06/D-07); RevokeAdmin last/self guard | InternalClusterService internal-only (404); cluster-admin grant на чужой account | partial GREEN (KAC-196 есть); short-circuit (Check+write-authz) RED |
| E-01..E-04 | applyDiff fell-out revoke по ledger (same-tx co-commit ВЗ-4); Role.Update diff | revoke→Check denied; label-change→denied | partial (T3.1 labels GREEN); all/names RED |
| F-01..F-05 | Check flat; wildcard DENY; ExpandAccess flat; UNAVAILABLE | Check/ExpandAccess black-box | partial GREEN (wildcard/unknown-verb уже есть) |
| G-01..G-05 | — | grep-assert модель/configmap/proto/iam/seed без org (0); contract-окно proto3-ignore | RED — org в модели + B2B-ресурс жив |
| H-01..H-06 | no-access-loss verify; idempotent re-apply; tier-parity 58→63; коммутативность backfill-vs-forward (H-04); replica-coord advisory-lock (H-05 CONC); forward-aware verify-gate (H-06) | — | RED — backfill/forward-verify не написаны |

Каждый сценарий → RED-тест ДО кода (`integration-tester`), GREEN после `rpc-implementer` (ban #12). Concurrent-race на deletion_protection Delete CAS — обязателен (data-integrity.md §чек-лист п.5).

---

## 12. Принятые решения 2026-06-24 (§12 ЗАКРЫТ — все Q разрешены владельцем)

> Открытые вопросы round 1 разрешены владельцем 2026-06-24 и зашиты в нормативную часть (§0 D-решения + сценарии). Этот раздел фиксирует резолюции для traceability.

**Q-1 (D-12a) — РЕШЕНО: FULL-REMOVAL organization (вариант A).** Удаляется весь B2B-`Organization`: `organization.proto`+`OrganizationService`, `account.organization_id`(f7), `Role.organization_id`(f9), org compliance-scope, hooks `organization_id` session-claim, org-сиды. Breaking по живым полям → через expand→contract (G-05 contract-окно). P1 расширен + новая P1b (iam compliance/hooks/seed зачистка — не только proto). DoD: `grep -rEi 'organization(_id)?'` по proto/iam/deploy/docs/seed → 0. → D-12a, G-03, G-05, P1/P1b.

**Q-2 (A-05) — РЕШЕНО: GLOBAL+all только для cluster-admin.** `GLOBAL + selector all` для НЕ-cluster-admin роли → sync `INVALID_ARGUMENT` (A-05 negative, field_violations roleId/scopeRef). Обычная роль на GLOBAL легальна только с `names`/`labels` → per-object кластер-wide (A-05b). Cluster-admin роль (`*.*.*`) — исключение, GLOBAL+all через D-9 short-circuit (A-05c). Принцип-инвариант §0 сделан нормативом. → §0 норматив, D-3, A-05/A-05b/A-05c.

**Q-3 (D-8a) — РЕШЕНО: owner = `[{modules:["*"],resources:["*"],verbs:["*"],selector:all}]` @ ACCOUNT, per-object.** На Account.Create аккаунт пуст → owner-tuple на `account:<A>` + tier admin сразу; содержимое — forward через D-4. reconciler досоздаёт owner-tuple на ресурсы, появляющиеся в A1 ПОСЛЕ owner-binding (иначе owner протухает). → D-8/D-8a, C-01/C-01b.

**Q-4 (D-11a) — РЕШЕНО: bootstrap Internal + далее public binding cluster-admin@GLOBAL.** Системная роль `cluster-admin` (`*.*.*`@GLOBAL) существует. bootstrap первого — `InternalClusterService` (KAC-196), deletion-protected. Далее public `Create(role=cluster-admin, scope=GLOBAL, requireGrantAuthority=cluster-admin)` → D-9 cluster-relation (спец-случай); non-cluster-admin → `PERMISSION_DENIED`. Противоречие с Q-2 снято (cluster-admin роль = исключение). → D-11a, A-05c, D-03.

**Q-5 (D-12/G-04) — РЕШЕНО: folder_id rename ВНЕ scope** (отдельная cleanup-под-фаза, non-goal). → D-14, §«Что НЕ входит».

**Q-6 (D-14) — РЕШЕНО: имя `scope_ref` ОСТАВИТЬ**, менять только семантику (убрать scope_grant-каскад). → D-14.

**Q-7 (§9) — РЕШЕНО: phased expand→migrate→contract** (утверждено, clean-cut отклонён). 3 фазы + forward-aware verify-gate. → §9, D-17.

**Q-8 — РЕШЕНО: stale-комментарии/счётчики правятся попутно в P12 docs** (condition-count 7→6 break_glass; «12 system-ролей»→63; proto-header AccessBinding INSERT→strict ALREADY_EXISTS). → P12, §13.

---

### Что НЕ входит (non-goals этого эпика)

- **folder_id rename** (`folder_id`→`project_id` field-names/comments в compute/vpc proto) — отдельная cleanup-под-фаза (Q-5).
- **Data-plane** — control-plane only; никакой реализации сетевого/compute data-plane (CLAUDE.md non-negotiable).
- **Observability** (метрики/трейсы/дашборды reconciler-материализации) — отдельный observability-эпик; здесь только функциональное поведение authz.
- **AAA сверх authz-модели** — JWT-валидация/mTLS/step-up (SEC-J/SEC-K) не меняются; эпик трогает только authz-материализацию (D-18: инвариант не ослабляется, но и не расширяется).
- **versioned modules / релизная фаза polyrepo** — остаётся `replace ../`.

---

## 13. Ground-truth: расхождения с формулировкой владельца (зафиксировано на 2026-06-24)

> Сверено с кодом ДО написания (3 параллельных explore-агента). Перечислено явно, чтобы ревьюер видел, где документ корректирует/уточняет исходную формулировку — НЕ молча.

1. **owner-роль НЕ существует** сейчас (owner = `Account.owner_user_id` FK + FGA-tuple, не seeded-роль). D-8 создаёт её net-new. (Владелец предполагал «системная cluster-роль owner» — её надо завести.)
2. **Canonical FGA = `kacho-proto/.../fga_model.fga`**, configmap — build-артефакт (генерируется `make openfga-model-json`). Правки модели — в proto-репо первым (D-13). (Владелец указал configmap как ground-truth — он верен как зеркало, но не источник.)
3. **`organization` — реальный proto-ресурс**, не только «мёртвые FGA-relations» (Q-1). Объём удаления зависит от развилки A/B.
4. **`folder` как FGA-тип НЕ существует** (Project заменил Folder, `project.proto`); остаются только legacy `folder_id` field-names (Q-5).
5. **AccessBinding `selector` НЕ на binding** — оно полностью переехало в `role.rules` (ARM_ANCHOR/NAMES/LABELS); на binding `reserved "target","target_ref","selector"` (sub-phase F clean-cut). Селекторы (req владельца #3) сохранены — но как role.rules-концепт. Согласуется.
6. **T3.1 idempotency = G-5** (не «D11» — это нумерация из другой под-фазы). resource_mirror покрывает vpc/compute/nlb; iam.account/project читаются нативно (FeedIAMDirect). reconciler сейчас материализует ТОЛЬКО labels — D-4 расширяет на all/names.
7. **cluster-admin deletion-protection** — нет флага; функционально покрыто инвариантом «нельзя ревокнуть последнего/себя» (KAC-196 RevokeAdmin CAS-guard). D-11.
8. **63 system-роли** (58 catalog + 5 SEC-C module-SA из mig 0009; не 12 как в stale CLAUDE.md); rules уже засеяны (0031/0033) — backfill сверяет плоскую материализуемость + tier-parity (F-53, счётчик `tier_parity_integration_test.go` обновляется 58→63). Net-new системные роли эпика (`owner`, `cluster-admin`) добавляются seed-миграцией поверх — итоговый каталожный счётчик уточнить при re-seed (P8).
9. **scope_grant (#177)** — текущий escalation-engine на cluster/account/project; D-5 его удаляет целиком (sg_<type> + g_*_<type>).

---

## 14. Запреты (соблюдены в этом документе)

- НЕ код — только markdown (внешнее поведение API).
- НЕ внутренние детали реализации (SQL/Go-структуры) сверх необходимого для трассировки контракта; DB-инварианты (CAS/partial-unique) указаны как наблюдаемое поведение + ссылка на data-integrity.md.
- НЕ сравнения с чужими облаками — конвенции Kachō нормативны (api-conventions.md).
- НЕ дублирование стандартных конвенций — ссылки на rule-модули.
- Internal.* (`InternalClusterService`) — только :9091, не external (D-18, ban #6, security.md).
- Неоднозначный payload в round 1 → зафиксирован как явное решение (§12 «Принятые решения»), НЕ угадано. Будущая ambiguity на пост-кодинг фазе → новая запись в §12, не молчаливый guess.

---

## 15. Координация (после APPROVE)

1. `acceptance-reviewer` + `system-design-reviewer` (распределённые аспекты: reconciler-реплики, idempotency, CAS, no-access-loss окно) → APPROVED либо CHANGES REQUESTED. Итерировать.
2. После APPROVED (статус → APPROVED) + разрешения §12: завести KAC-эпик ретроспективно + per-repo subtasks; KAC-trail в vault.
3. Per-под-фаза: `superpowers:writing-plans` → `integration-tester` (RED) → `rpc-implementer` → `proto-api-reviewer` (P1/P2) → `db-architect-reviewer` (P6/P8 миграции) → `api-gateway-registrar` (P9 public RPC).
4. Заказчик — финальный smoke/e2e (`make e2e-test` / `grpcurl`).

Сценарий стал неоднозначным после старта кодирования → вернуть сюда для уточнения; НЕ менять поведение реализации без правки этого дока.
