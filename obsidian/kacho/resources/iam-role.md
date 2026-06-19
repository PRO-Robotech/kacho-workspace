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
| `permissions` | JSONB | `iam_permissions_valid` v2 (regex per item + cardinality 1-256) | array of strings `<module>.<resource>.<resourceName>.<verb>` — strict 4-segment grammar since KAC-216 (migration 0005 promoted 3-seg legacy to `M.R.*.V`) |
| `is_system` | BOOL | | seed-only, immutable |
| `created_at` | TIMESTAMPTZ | server-set | |

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

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-role-service]] [[../rpc/iam-access-binding-service]] [[iam-cluster]] [[iam-organization]] [[iam-account]] [[iam-project]] [[iam-access-binding]] [[../KAC/KAC-105]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam
