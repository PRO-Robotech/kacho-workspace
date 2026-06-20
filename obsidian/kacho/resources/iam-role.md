---
title: Role
aliases:
  - Role (iam)
  - iam Role
category: resource
domain: iam
id_prefix: rol
owner_table: kacho_iam.roles
owner_db: kacho_iam
folder_level: false
status: done
related_rpc:
  - "[[rpc/iam-role-service]]"
related_packages:
  - "[[packages/iam-domain]]"
  - "[[packages/iam-repo-kacho-pg]]"
related_tickets:
  - "[[KAC-105]]"
  - "[[KAC-112]]"
  - "[[KAC-127]]"
tags:
  - resource
  - kacho-iam
  - iam
---

# Role

**Domain**: iam — bundle of permissions для AccessBinding.
**ID prefix**: `rol` (20 chars; system-роли имеют детерминированные id вида `rol00000000000000iamad`).
**Owner table**: `kacho_iam.roles`.
**Status**: KAC-105 базовый (account-scoped); **KAC-127 Phase 1 — multi-scope refactor** (cluster / organization / account / project XOR).

## Fields (KAC-127 multi-scope)

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `ids.IsValid("rol")` | |
| `cluster_id` | TEXT NULL | FK → clusters(id) RESTRICT | set ⇔ `is_system=true` (system-role) |
| `account_id` | TEXT NULL | FK → accounts(id) RESTRICT | account-scoped custom |
| `project_id` | TEXT NULL | FK → projects(id) RESTRICT | project-scoped custom |
| ~~`organization_id`~~ | — | — | **removed in KAC-223** (migration 0008 — Organization domain dropped) |
| `name` | TEXT | regex (см. ниже) | UNIQUE per scope (см. partial UNIQUEs) |
| `description` | TEXT | <=256 chars | |
| `permissions` | JSONB | `iam_permissions_valid` v2 (regex per item + cardinality 1-**1024**) | **INTERNAL compiled** form (anchor/names arms) — derived from `rules` (RBAC rules-model 2026, gh#182). **NOT on the public API surface** (empty in Get/List for rules-roles). cap raised 256→1024 (migration 0025, lockstep DB+domain+proto). strict 4-segment `M.R.rn.V` |
| `rules` | JSONB | `iam_rules_valid` shape CHECK (≤64; each rule modules/resources/verbs 1..16; resourceNames≤256 XOR matchLabels≤16) | **authored policy + public API surface** (gh#182, migration 0025). `[]` default for legacy permissions-only roles. Compiled → `permissions` by `domain.CompileRules` (matchLabels NOT compiled) |
| `is_system` | BOOL | | seed-only, immutable |
| `created_at` | TIMESTAMPTZ | server-set | |
| `created_by_user_id` | TEXT | proto-only (sub-phase A) | authoring principal; output |
| `updated_at` | TIMESTAMPTZ | proto-only (sub-phase A) | last-mutation; output |

## Multi-scope XOR (CHECK `roles_scope_xor`)

Ровно **один** scope-поле non-NULL. Org-scope удалён в KAC-223 (migration 0008
переписала `roles_scope_xor` без org-ветки):

| `is_system` | `cluster_id` | `account_id` | `project_id` |
|---|---|---|---|
| `true` | **set** | NULL | NULL |
| `false` | NULL | **set** | NULL |
| `false` | NULL | NULL | **set** |

`domain.Role.Validate` (`role.go`) дублирует CHECK для дружелюбных ошибок до БД.

## Constraints / indexes (KAC-127)

- `roles_pkey` PRIMARY KEY (id)
- 3× FK на (clusters, accounts, projects) — все RESTRICT (organizations FK dropped, KAC-223)
- `roles_scope_xor` **CHECK** — multi-scope формула выше
- `roles_system_unique` partial UNIQUE (`cluster_id`, `name`) WHERE `is_system=true`
- `roles_org_custom_unique` partial UNIQUE (`organization_id`, `name`) WHERE `organization_id IS NOT NULL`
- `roles_acc_custom_unique` partial UNIQUE (`account_id`, `name`) WHERE `account_id IS NOT NULL`
- `roles_prj_custom_unique` partial UNIQUE (`project_id`, `name`) WHERE `project_id IS NOT NULL`
- `roles_custom_name_check` — custom: `^[a-z][-a-z0-9]*(\.[a-z][a-z0-9_]*){0,2}$`
- `roles_system_name_check` — system: `^[a-z]+(\.[a-z_]+){0,2}$` (e.g. `kacho-system.admin`)
- `roles_permissions_valid` CHECK — pgPL/SQL func, regex per item

## Default system-roles (Phase 1 — moved from account-scope to cluster-scope)

KAC-105 (12 system-roles) + KAC-121/KAC-122 (YC-style catalog) + KAC-127 (refactor с `account_id=NULL` → `cluster_id=cluster_kacho_root`):

- `roles/iam.{admin,editor,viewer}`, `roles/vpc.{admin,editor,viewer}`, `roles/compute.{admin,editor,viewer}`, `roles/loadbalancer.{admin,editor,viewer}` — legacy
- KAC-121 семейство YC-style (`kacho-system.admin`, `viewer`, `editor`, ...)

## Permission string

Format: `<module>.<resource>.<verb>` (`*` wildcard на отдельных позициях). Examples: `vpc.networks.*`, `iam.*.read`, `*.*.*` (admin).
Wildcards в permissions **не разворачиваются** при INSERT — хранятся as-is; expansion — в OpenFGA Check на Phase 3.

## RBAC v2 (KAC-214 / KAC-216)

- Strict 4-segment grammar: `module.resource.resourceName.verb`. Each segment is
  `[a-zA-Z][a-zA-Z0-9_-]*` (module lowercase, resource camelCase, verb lowercase
  camelCase) or literal `*`. `resourceName` may be `*` (wildcard — covers all
  instances) or a concrete id (`inst-abc`, `prj-prod`).
- Migration 0005 (W3) auto-promotes legacy 3-segment perms (`M.R.V` → `M.R.*.V`).
- Concrete-resourceName grants emit a direct per-object FGA tuple at
  `fga_type(M,R):<resourceName>`; wildcard-resourceName grants emit a tier tuple
  at the binding's scope anchor (see [[iam-access-binding]] §RBAC v2).
- See [[../KAC/KAC-214]] for the design + emission matrix.
- **epic-100 α shift (proto#65 / iam#165):** Role становится **чистым verb-bundle** —
  конкретный объект-таргет уходит из `permissions.resourceName` в
  `AccessBinding.target` (oneof). Новые роли несут wildcard `resourceName=*`
  (`M.R.*.V`); per-object FGA tuple теперь эмитится из `binding.target.resources[]`,
  не из `role.permissions`. Новый Create-гейт **role-coverage** (D-13): тип объекта в
  target обязан покрываться типом в `role.permissions`. Legacy concrete-`resourceName`
  роли продолжают работать (forward-only, D-8). См.
  [[iam-access-binding]] §Resource-scoped target, [[../KAC/epic-100-resource-scoped-access-binding]].

## RBAC rules-model 2026 — sub-phase A (gh#182, migration 0025)

K8s-style **rules-in-role**: Role становится переиспользуемой allow-only политикой с
`rules[]` (authority + публичная API-поверхность); `permissions[]` низведён до
**internal compiled** проекции (не в API-ответе).

- **Rule** (`domain.Rule`, чистый Go): `{modules[], resources[], verbs[]}` над
  декартовым `modules × resources`, опц. суженный `resourceNames[]` **XOR**
  `matchLabels{}`. Self-validating `Validate(systemCtx)`.
- **Три арма** (`domain.Arm`): ANCHOR (нет селектора) → `m.r.*.v`; NAMES
  (`resourceNames`) → `m.r.<id>.v`; LABELS (`matchLabels`) → **НЕ компилируется** в
  permissions (reconciler-driven, sub-phase C).
- **Компилятор** `domain.CompileRules(rules)` (детерминированный): anchor+names →
  4-seg permissions; verb-`*` → проекция держит `*` (`m.r.*.*`), НЕ разворачивает
  per-verb набор (это sub-phase B); cap ≤1024 (`>1024 → INVALID_ARGUMENT "compiled
  permissions exceed 1024"`).
- **Wildcard-политика**: verb-`*` ДОПУСТИМ в custom (R-3); module-`*`/resource-`*`
  **system-only** (custom → `INVALID_ARGUMENT "wildcard '*' is system-only"`).
- **Feed-gate (matchLabels)** — `domain.IsLabelSelectableType` (закрытый registry в
  `domain/feed_registry.go`): mirror-fed compute/vpc/loadbalancer + iam-direct
  **ровно** `iam.project`/`iam.account` (O-4). Не-fed тип → `INVALID_ARGUMENT "type
  <m>.<r> is not selectable (no resource feed)"`. ARM_NAMES gate'у НЕ подлежит.
  Консистентность с `access_binding.selectableTypes` пиннится self-тестом.
- **API**: Create/Update принимают `rules` (валидируют+компилируют+хранят rules JSONB
  + compiled permissions в одной writer-tx); `permissions` на входе → `INVALID_ARGUMENT
  "Illegal argument permissions (compiled/output-only)"` (A-02, первым стейтментом
  handler'а). Get/List → `Role` с `rules[]`, `permissions` **пустое**. update_mask:
  `rules`(+name/description) mutable, `permissions` immutable. OCC через `resource_version`
  (xmin) при mask с `rules`.
- **Back-compat (F-01)**: legacy permissions-only роли (`rules='[]'`) читаются валидно;
  backfill rules из permissions — sub-phase F.
- Осталось на **sub-phase B**: FGA-эмиссия (`scope_grant`-примитив, per-verb relations,
  arm-tagged emit, verb-`*` разворот в полный per-verb набор). A — только
  compile/validate/store/serve.

## A-16 — Role.Delete RESTRICT (within-DB FK, не TOCTOU)

Delete custom-роли с активными биндингами → `FAILED_PRECONDITION "role is in use by
active access bindings"` через FK `access_bindings_role_fk` ON DELETE RESTRICT (SQLSTATE
`23503` → FailedPrecondition в `WrapPgErr`, kindHint `"Role.Delete"`, без leak pgx).
Прежний software `NOT EXISTS`-pre-check **удалён** (ban #10 — был TOCTOU); `is_system`/
not-found остаются probe-discrimination (не FK-выразимы). После revoke всех биндингов —
Delete проходит.

## Lifecycle

- **Custom**: Create / Update / Delete async; system-role попытка Update/Delete → `FailedPrecondition`.
- **System-role**: immutable seed; добавление новой system-роли — только новой миграцией (запрет #5).
- **Scope migration (KAC-127 migration 0011)**: pre-existing custom roles остаются с `account_id NOT NULL`; новые roles могут использовать любой из 4 scope.

## Gotchas

- System-role id — детерминированный (stable across re-seeds), чтобы OpenFGA-tuples могли ссылаться по id.
- `roles_custom_name_check` запрещает leading `roles/` для custom — исключает коллизию с system-namespace.
- Backwards-compat: legacy custom roles (KAC-105/KAC-112) с `account_id IS NOT NULL` остаются валидными под новой `roles_scope_xor` CHECK (миграция 0011 §6.4 сначала бэк-фильнула `roles.cluster_id` для system-rows ДО добавления CHECK).
- Org-scoped custom role — доступно ВСЕМ Accounts в этом Organization (поделённый каталог).

## Assignable projection — `isRoleAssignable` / `ScopeGroup` (sub-phase 1.5)

Единый предикат `domain.IsRoleAssignable(role, resource_type, resource_id)`
(`internal/domain/role_scope.go`) — ОДИН источник истины «какие роли валидны
для привязки на ресурсе», общий для `AccessBindingService.ListAssignableRoles`
(SQL-mirror в `Reader.ListAssignable`) и `AccessBinding.Create` (enforcement,
mis-scoped → `Operation.error` FAILED_PRECONDITION). STRICT-матрица (Q#1):

| resource | SYSTEM | ACCOUNT-роль (`account_id=X`) | PROJECT-роль (`project_id=Y`) |
|---|---|---|---|
| `account acc-A` | ✅ | ✅ iff `X==acc-A` | ❌ |
| `project prj-P` | ✅ | ❌ (нет hierarchy-down) | ✅ iff `Y==prj-P` |
| `cluster …root` | ✅ | ❌ | ❌ |

- `ScopeGroupOf(role)` → `RoleScopeGroup` {SYSTEM, ACCOUNT, PROJECT} (proto
  `ScopeGroup`); legacy `organization_id` **игнорируется** (Q#4) — нет
  ORGANIZATION-значения.
- **roleCols read-side расширен (1.5):** `role_repo.go` `roleCols` теперь
  селектит `cluster_id, project_id` (+ `account_id`) — до 1.5 они опускались,
  `domain.Role.ClusterID`/`ProjectID` оставались пустыми после read. То же в
  `RoleReadAdapter.Get`. Регресс-тест `TestRole_RoleColsRegression_ScopeFieldsPopulated`.
- Critical-note (ground-truth): публичный Role API минтит только account-scoped
  custom-роли; PROJECT-scoped роли существуют лишь схематически (forward-safe —
  предикат и `scope_group=PROJECT` определены, строка пока пуста в v1).

## Update OCC + FGA tuple reconcile (security #178)

- **xmin-CAS на Role.Update (V2):** `roles` не имеет version-колонки → OCC через
  системный `xmin::text`. Use-case читает токен на sync-пути (`Roles().GetWithVersion`),
  эхо-ит в worker-tx (`RolesW().UpdateCAS(r, mask, expectedVersion)` → `UPDATE … WHERE
  id=$id AND xmin::text=$exp RETURNING`). Конкурентный Role.Update: row-lock сериализует,
  loser видит бампнутый xmin → 0 rows → `ErrFailedPrecondition` «role was modified
  concurrently, retry», и его FGA fan-out откатывается (одна writer-tx, ban #10) → нет
  ledger↔FGA drift. `expectedVersion==""` → unconditional last-writer (back-compat).
- **FGA fan-out на смену permissions:** Role.Update реконсайлит FGA-tuples активных
  биндингов роли (`role.TupleReconciler` ⇒ `access_binding.RoleTupleReconciler`) в ТОЙ ЖЕ
  writer-tx — diff old-ledger vs derive-from-new-role. Покрывает все три target-арма
  (all_in_scope/resources[]/selector); понижение tier роли снимает orphan-tuples.
  Детали ledger — [[iam-access-binding]] §«Symmetric revoke + Role.Update reconcile».

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-role-service]] [[../rpc/iam-access-binding-service]] [[iam-cluster]] [[iam-organization]] [[iam-account]] [[iam-project]] [[iam-access-binding]] [[../KAC/KAC-105]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam
