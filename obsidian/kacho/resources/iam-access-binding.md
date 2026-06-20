---
title: AccessBinding
aliases:
  - AccessBinding (iam)
  - iam AccessBinding
  - ACB
category: resource
domain: iam
id_prefix: acb
owner_table: kacho_iam.access_bindings
owner_db: kacho_iam
folder_level: false
status: done
related_rpc:
  - "[[rpc/iam-access-binding-service]]"
related_packages:
  - "[[packages/iam-domain]]"
  - "[[packages/iam-repo-kacho-pg]]"
related_tickets:
  - "[[KAC-105]]"
  - "[[KAC-112]]"
  - "[[KAC-108]]"
  - "[[KAC-127]]"
  - "[[KAC-214]]"
  - "[[KAC-217]]"
tags:
  - resource
  - kacho-iam
  - iam
---

# AccessBinding

**Domain**: iam — связь `(subject) ↔ role ↔ (resource)`.
**ID prefix**: `acb` (20 chars).
**Owner table**: `kacho_iam.access_bindings`.
**Status**: KAC-105 базовый + **KAC-127 Phase 1** extension: lifecycle-поля (`status`, `condition_id`, `expires_at`, `granted_by_user_id`, `revoked_at`, `revoked_by_user_id`).

## Fields (KAC-127 extended)

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `ids.IsValid("acb")` | |
| `subject_type` | TEXT | CHECK `IN ('user','service_account','group')` | |
| `subject_id` | TEXT | **soft-ref** — без FK (полиморфно) | Phase 3 синк → OpenFGA |
| `role_id` | TEXT | FK → roles(id) RESTRICT | |
| `resource_type` | TEXT | CHECK `^[a-z][a-z0-9_]*$` или `*` | whitelisted enum |
| `resource_id` | TEXT | **soft-ref** — cross-DB (запрет #8) | opaque id (любой prefix) |
| `status` | TEXT | CHECK enum (KAC-127) | `PENDING` (initial) / `ACTIVE` / `REVOKED` |
| `condition_id` | TEXT NULL | FK → access_binding_conditions(id) RESTRICT (KAC-127) | 1:1 overlay condition |
| `scope` | SMALLINT NOT NULL | CHECK `scope IN (1,2,3)` (KAC-216 migration 0005) | RBAC v2 anchor tier — 1=CLUSTER / 2=ACCOUNT / 3=PROJECT |
| `expires_at` | TIMESTAMPTZ NULL | CHECK `IS NULL OR > created_at` (KAC-127) | TTL — JIT-bindings expire |
| `granted_by_user_id` | TEXT | length <=64 (KAC-127) | audit — кто выдал |
| `revoked_at` | TIMESTAMPTZ NULL | (KAC-127) | set когда status → REVOKED |
| `revoked_by_user_id` | TEXT NULL | length <=64 (KAC-127) | audit — кто отозвал |
| `created_at` | TIMESTAMPTZ | server-set | |

## State machine (KAC-127 Phase 1)

```
PENDING → ACTIVE → REVOKED (terminal)
```

DB CHECK `status IN ('PENDING','ACTIVE','REVOKED')`. Transitions через atomic CAS-style UPDATE (workspace §запрет #10):
- `WHERE status='PENDING'` → ACTIVE (auto on conditions-satisfied)
- `WHERE status IN ('PENDING','ACTIVE')` → REVOKED (idempotent revoke)

## Constraints / indexes

- `access_bindings_pkey` PRIMARY KEY (id)
- `access_bindings_role_fk` FK → `roles(id)` ON DELETE RESTRICT
- `access_bindings_condition_fk` FK → `access_binding_conditions(id)` RESTRICT (KAC-127)
- `access_bindings_subject_ck` / `access_bindings_resource_ck` — enum/regex CHECK
- `access_bindings_status_ck` CHECK (KAC-127): `status IN ('PENDING','ACTIVE','REVOKED')`
- `access_bindings_revoked_consistency_ck` CHECK (KAC-127): `(status='REVOKED' AND revoked_at IS NOT NULL) OR (status IN ('PENDING','ACTIVE') AND revoked_at IS NULL)`
- `access_bindings_expires_ck` CHECK (KAC-127): `expires_at IS NULL OR expires_at > created_at`
- `access_bindings_unique` UNIQUE (subject_type, subject_id, role_id, resource_type, resource_id) — **идемпотентность Create**
- Indexes: subject, resource, role, `(status, expires_at)` для expiry-cron

## Polymorphic refs

- `subject_id` ссылается полиморфно на `users` / `service_accounts` / `groups` — **без FK** (PostgreSQL FK не поддерживает alternation). Phase 3 OpenFGA-sync будет валидировать через peer-lookup в `InternalIAMService.LookupSubject`.
- `resource_id` ссылается на ресурс **другого сервиса** (cross-DB; запрет #8) — software-validation в Phase 3 OpenFGA tuples + lazy check.

## Lifecycle

- **Create** — async; UNIQUE → идемпотентный (повторный Create на тот же (subject, role, resource) → возвращает existing). **WS-2.3 ([[KAC-WS23]])**: в той же writer-TX пишет `subject_change_outbox` row (`op='binding_upsert'`) → atomic с AccessBinding INSERT (драйвит инвалидацию authz-кэша gateway, см. [[../edges/api-gateway-to-iam-subject-change]]). FGA-tuple grant — отдельным путём (sync `WriteTuples`).
- **Activate (KAC-127 Phase 7)**: PENDING → ACTIVE через CAS UPDATE (conditions met / JIT activate / approver-grant).
- **Delete / Revoke**: `Delete` физически удаляет row. **WS-2.3 ([[KAC-WS23]])**: в той же writer-TX пишет `subject_change_outbox` row (`op='binding_delete'`) → atomic с удалением. FGA-tuple revoke — отдельным путём (sync `DeleteTuples`, review #8).
- **Expire (KAC-127 Phase 7 worker)**: scan `WHERE status='ACTIVE' AND expires_at < now()` → CAS UPDATE → REVOKED.
- **ListByResource** / **ListBySubject** — sync read.
- **ListOperations** (sub-phase 1.2) — per-AB ops history (sync read, filter `resource_id`). См. [[../KAC/sub-phase-1.2-iam-operations]].
- **ListSubjectPrivileges** (sub-phase 1.3 + 1.3b) — все привилегии субъекта (effective roles) с `role_name` (LEFT JOIN roles) + `derivation`; `subject_type ∈ {user, service_account, group}` (group добавлен в 1.3b). Питает UI вкладку «Привилегии» на User/SA/Group. См. [[../KAC/sub-phase-1.3-subject-privileges]].

## Gotchas

- KAC-127: `condition_id` 1:1 UNIQUE — попытка attach двух conditions на одну binding → `23505`.
- Удаление Role с активным AccessBinding → `FailedPrecondition` (FK RESTRICT).
- Удаление User/SA/Group **не cascades** в AccessBinding (полиморфно, без FK) — оператор должен почистить через AccessReview либо ждать Phase 3 cascade-cleanup через OpenFGA.
- Phase 1 НЕ читает / НЕ enforce'ит binding'и в interceptor-ах — это Phase 3 (KAC-108). На E0 любой запрос проходит без auth (`principal=system`).

## RBAC v2 (KAC-214 / KAC-216 / KAC-217)

- `scope` derived from `resource_type` at INSERT via the
  `access_bindings_scope_default_trg` BEFORE INSERT trigger (migration 0005)
  if the writer omits it. Explicit values rejected when they contradict
  `(resource_type, resource_id)` — domain `Scope.ValidateAgainst` enforces
  CLUSTER ⇒ ('cluster','cluster_kacho_root'); ACCOUNT ⇒ ('account', starts
  'acc'); PROJECT ⇒ ('project', starts 'prj').
- `roles.permissions` JSONB strings promoted to strict 4-segment
  `module.resource.resourceName.verb` (validator `iam_permissions_valid()`).
  3-segment legacy entries are auto-promoted to `M.R.*.V` by migration 0005.
- fga_outbox emission shifted from single tier-tuple to the §3.5 matrix —
  wildcard resourceName → tier tuple at the scope anchor; concrete
  resourceName → direct per-object tuple at `fga_type(M,R):<name>`.
- **UI consumer (KAC-224)**: kacho-ui `AccessBindingsPage` показывает `scope`
  read-only колонкой (output-only, не отправляется в Create). UI-селектор
  `resource_type` ограничен `account`/`project`/`cluster` — legacy
  resource-manager типы `folder`/`organization`/`cloud` удалены (backend их
  reject'ит `INVALID_ARGUMENT "Illegal argument resource_type"`).
- **Backend gotcha (kacho-iam#97)**: domain Go `permissionElementRe` остался
  3-сегментным, тогда как DB CHECK `iam_permissions_valid` (mig0005) — строго
  4-сегментный → create custom Role сломан на RPC-пути (4-seg рубит domain,
  3-seg рубит DB). Open finding; UI RolesPage regex ждёт backend-фикса.

## Create scope-enforcement (sub-phase 1.5, D-2/D-11)

- **Create стал scope-авторитетным.** Был пермиссивен по role-vs-resource scope
  (только FK `access_bindings_role_fk` existence). 1.5 добавил проверку единого
  предиката `domain.IsRoleAssignable` (см. [[iam-role]] §isRoleAssignable) в
  `doCreate` ДО INSERT, в той же writer-tx (роль читается там же для FGA-mapping).
- Mis-scoped роль → **`Operation.error.code = FAILED_PRECONDITION`** «role <id>
  is not assignable on <type>:<id>» (async-контракт сохранён — ban #9 / Q#3;
  одна error-поверхность). Binding НЕ создаётся (tx rollback).
- **list⇔create parity:** набор `ListAssignableRoles` == набор, который Create
  принимает (нет обхода через прямой gRPC/deep-link).
- **Forward-only (D-11):** enforcement гейтит ТОЛЬКО новые Create. Pre-1.5
  mis-scoped bindings: НЕТ migration-revoke, НЕТ read-hide (видны в
  `ListByResource`/`ListSubjectPrivileges`), `Delete` отзывает как раньше.
- Predicate детерминирован per role-row+resource → нет TOCTOU; concurrent
  integration-тест (1.5-12b, 2 goroutine) подтверждает «оба rejected, 0 bindings».
- by-design: `kacho-iam/docs/architecture/assignable-roles-scope-enforcement.md`.

## Resource-scoped target (epic-100 α — proto#65 / iam#165 / gateway#88)

- **Новое поле `target` (AccessTarget oneof)** — decides WHICH objects под scope-anchor
  (`resource_type`/`resource_id`) применяются verb'ы роли: `all_in_scope` (= pre-α
  wildcard, tier-tuple) | `resources[]` (per-object tuples) | `selector` (forward γ,
  → `UNIMPLEMENTED` на α). Strict oneof. Role стал **чистым verb-bundle** —
  `resourceName` ушёл из роли в target (см. [[iam-role]]).
- **Новая таблица `kacho_iam.access_binding_targets`** (migration 0018): `binding_id`
  FK → `access_bindings(id)` **ON DELETE CASCADE** (same-DB), `type`, `id`,
  `UNIQUE(binding_id,type,id)` (идемпотентность add), CHECK `id<>'' AND id<>'*'`.
  **`all_in_scope` ≡ отсутствие строк** для binding'а (read-time проекция, D-8).
- **Role-coverage гейт (D-13)** — ТРЕТИЙ независимый детерминированный гейт на
  Create/Add (ортогонален 1.5 `IsRoleAssignable` scope-tier): `target.resources[].type`
  обязан покрываться типом в `role.permissions` (`domain.RoleCoversType`, same-DB, нет
  TOCTOU). Mis → `Operation.error` FAILED_PRECONDITION «role <id> does not grant any
  verb on <type>».
- **FGA-эмиссия**: per-object tuple `fga_type(ref.type):<id>#tier(verb)@subject`,
  источник `resourceName` = `binding.target`, НЕ `role.permissions`. Ref прошедший
  D-13 но давший 0 tuples → INTERNAL fail-closed (нет target-без-tuple split-brain).
  Всё в одной writer-tx с INSERT binding + outbox (ban #10).
- **`target.id` — opaque soft-ref** без existence/containment-валидации (как
  `resource_id`, запрет #8): IAM не звонит владельцу (НЕТ ребра iam→compute/vpc —
  цикл; `compute→iam`/`vpc→iam` уже есть). Containment «объект под scope» вынесен в γ
  (D-14). Dangling переживается graceful.
- **Last-element guard (D-10)**: `RemoveTargetResources` последнего ref →
  FAILED_PRECONDITION «use Delete to revoke» (НЕ авто-`all_in_scope`, НЕ пустой target);
  сериализация concurrent через `CountTargetsForUpdate` (`SELECT … FOR UPDATE` на parent).
- **Forward-only (D-8)**: legacy bindings (concrete-`resourceName`-в-роли) читаются как
  `all_in_scope`, без migration-revoke. β = governance IAM Tags; γ = selector+reconciler.
- by-design: `kacho-iam/docs/architecture/resource-scoped-access-binding-alpha.md`.
  Эпик: [[../KAC/epic-100-resource-scoped-access-binding]].

## Selector mutable: ReplaceTargetSelector (epic-100 γ — D2/D11)

- **`selector` — единственная mutable часть target'а** (subject/role/scope-anchor
  immutable; смена ветки oneof `selector⇄resources⇄all_in_scope` = Delete+Create, D10).
  Меняется async RPC `ReplaceTargetSelector` (atomic **полная замена**, не merge —
  `access_binding_selector` ON CONFLICT (binding_id) DO UPDATE).
- **CAS = `xmin::text`** (γ-19, ban #10): `access_bindings` **НЕ имеет** version-колонки
  (она у `conditions`), поэтому OCC-токен `resource_version` — системный `xmin` строки.
  Репо `ReplaceSelectorCAS` делает no-op `UPDATE … SET status=status WHERE id AND
  status='ACTIVE' AND xmin::text=$expected` (бампит xmin под row-lock) → конкурентный
  replace с тем же expected видит изменённый xmin → 0 rows → `ErrFailedPrecondition`
  «access binding was modified concurrently, retry». Клиент читает `resource_version`
  через `GetWithVersion` (`SELECT xmin::text, …`), эхо-ит в replace.
- **Read-side проекция selector**: `Get` теперь проецирует `selector`-arm (был только
  resources[]/all_in_scope); `dto.domainTargetToProto` эмитит `AccessTarget_Selector`.
  Membership пересчёт после CAS — `reconciler.ReconcileBinding` (выпавшие → eager-revoke,
  новые matched → emit), в отдельной writer-tx post-commit.
- migrations 0019-0022 (mirror / target_members / reconcile_outbox / selector). См.
  [[../rpc/iam-access-binding-service]] ReplaceTargetSelector + эпик γ.

## Symmetric revoke + Role.Update reconcile ledger (security #178, iam#42-followup)

- **`kacho_iam.access_binding_emitted_tuples`** (migration 0024) — persisted EXACT
  FGA tuple-set a binding emitted (PK `(binding_id, fga_user, relation, object)`,
  FK `binding_id` → `access_bindings(id)` **ON DELETE CASCADE**, non-empty CHECKs).
  Authoritative «что было эмитировано», co-commit с `EmitRelationWrite` в writer-tx
  (ban #10). **Revoke реплеит этот ledger** (`SelectEmittedTuples` → `EmitRelationDelete`),
  НЕ ре-деривит из CURRENT роли → нет orphan-tuple при Role.Update между grant и revoke.
- **Role.Update fan-out** (`access_binding.RoleTupleReconciler`, port `role.TupleReconciler`):
  при смене `role.permissions` реконсайлит FGA-tuples активных биндингов роли в ТОЙ ЖЕ
  writer-tx, что и UPDATE роли (atomic, ban #10). Bounded (`ListActiveByRole`), идемпотентен
  (diff old-ledger vs new-derive → ∅ при неизменном tier).
- **Selector arm (γ) ledger-unification (#178 C1/V3):** γ-reconciler теперь co-commit'ит
  каждый materialized member-tuple в ledger (`RecordEmittedTuples`/`ForgetEmittedTuples` в
  γ writer-tx). Следствие — **V3**: `Delete` selector-биндинга реплеит ledger ⇒ снимает и
  per-member tuples (был orphan). **C1**: `RoleTupleReconciler` для selector-арма
  ре-деривит per-member tuples (ACTIVE `access_binding_target_members` ×
  НОВЫЙ tier роли — `ListActiveMembers` + `tuplesForTarget`) → diff vs ledger ⇒ снимает
  stale-tier, пишет new-tier. γ tier-BLIND (диффит по VerificationStatus), поэтому
  понижение tier роли закрывается ИМЕННО на Role.Update, не γ-проходом.
- **Две роли-реконсайлера (не путать):** γ `reconcile.Reconciler` = MEMBERSHIP («какие
  объекты», из mirror label/containment); `RoleTupleReconciler` = ROLE-PERMISSION («на каком
  tier», на Role.Update). Комплементарны.

## Role OCC (#178 V2) — см. [[iam-role]]

`roles` не имеет version-колонки → Role.Update OCC через `xmin::text`-CAS
(`GetWithVersion` на sync-пути → `UpdateCAS … WHERE xmin::text=$exp` в worker-tx).
Конкурентный Role.Update: loser → `FAILED_PRECONDITION` «role was modified
concurrently, retry», его FGA fan-out откатывается (одна writer-tx) → нет ledger↔FGA drift.

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-access-binding-service]] [[../rpc/iam-internal-iam-service]] [[iam-role]] [[iam-access-binding-condition]] [[iam-jit-eligibility]] [[../edges/iam-to-openfga-check]] [[../edges/api-gateway-to-iam-subject-change]] [[../KAC/KAC-105]] [[../KAC/KAC-127]] [[../KAC/KAC-WS23]] [[../KAC/KAC-214]] [[../KAC/KAC-217]] [[../KAC/KAC-224]]

#resource #kacho-iam #iam
