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
| `organization_id` | TEXT NULL | FK → organizations(id) RESTRICT | org-scoped custom (KAC-127) |
| `account_id` | TEXT NULL | FK → accounts(id) RESTRICT | account-scoped custom (legacy KAC-105) |
| `project_id` | TEXT NULL | FK → projects(id) RESTRICT | project-scoped custom (KAC-127) |
| `name` | TEXT | regex (см. ниже) | UNIQUE per scope (см. partial UNIQUEs) |
| `description` | TEXT | <=256 chars | |
| `permissions` | JSONB | `iam_permissions_valid` v2 (regex per item + cardinality 1-256) | array of strings `<module>.<resource>.<resourceName>.<verb>` — strict 4-segment grammar since KAC-216 (migration 0005 promoted 3-seg legacy to `M.R.*.V`) |
| `is_system` | BOOL | | seed-only, immutable |
| `created_at` | TIMESTAMPTZ | server-set | |

## Multi-scope XOR (KAC-127 acceptance §2.3)

Ровно **один** из 4 scope-полей non-NULL, по формуле (CHECK `roles_scope_xor` в migration 0011):

| `is_system` | `cluster_id` | `organization_id` | `account_id` | `project_id` |
|---|---|---|---|---|
| `true` | **set** | NULL | NULL | NULL |
| `false` | NULL | **set** | NULL | NULL |
| `false` | NULL | NULL | **set** | NULL |
| `false` | NULL | NULL | NULL | **set** |

`domain.Role.Validate` (`role.go`) дублирует CHECK для дружелюбных ошибок до БД.

## Constraints / indexes (KAC-127)

- `roles_pkey` PRIMARY KEY (id)
- 4× FK на (clusters, organizations, accounts, projects) — все RESTRICT
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

## Lifecycle

- **Custom**: Create / Update / Delete async; system-role попытка Update/Delete → `FailedPrecondition`.
- **System-role**: immutable seed; добавление новой system-роли — только новой миграцией (запрет #5).
- **Scope migration (KAC-127 migration 0011)**: pre-existing custom roles остаются с `account_id NOT NULL`; новые roles могут использовать любой из 4 scope.

## Gotchas

- System-role id — детерминированный (stable across re-seeds), чтобы OpenFGA-tuples могли ссылаться по id.
- `roles_custom_name_check` запрещает leading `roles/` для custom — исключает коллизию с system-namespace.
- Backwards-compat: legacy custom roles (KAC-105/KAC-112) с `account_id IS NOT NULL` остаются валидными под новой `roles_scope_xor` CHECK (миграция 0011 §6.4 сначала бэк-фильнула `roles.cluster_id` для system-rows ДО добавления CHECK).
- Org-scoped custom role — доступно ВСЕМ Accounts в этом Organization (поделённый каталог).

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-role-service]] [[iam-cluster]] [[iam-organization]] [[iam-account]] [[iam-project]] [[iam-access-binding]] [[../KAC/KAC-105]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam
